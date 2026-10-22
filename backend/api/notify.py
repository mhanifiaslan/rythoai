"""Bildirim uçları: zamanlayıcı tetikli toplu gönderim + olay tetikli tekil.

İki farklı güven modeli var ve bilinçli olarak ayrılmıştır:

- ``POST /run`` yalnızca **Cloud Scheduler** tarafından çağrılır ve paylaşılan
  gizli anahtarla korunur. Bu uç tüm kullanıcılara bildirim gönderebilir;
  kullanıcı oturumuyla erişilebilir olsaydı herkes herkese bildirim
  attırabilirdi.
- ``POST /reaction`` normal kullanıcı oturumuyla çağrılır ama **yalnızca
  karşılıklı arkadaşa** ve **kapalı tepki kümesinden** gönderim yapar; ikisi
  de sunucuda doğrulanır (istemcinin söylediğine güvenilmez). Üstüne
  **çift başına günlük tekrar koruması** gelir: bu uç bir tur boyunca
  hiçbir sayaca tabi değildi ve tek bir arkadaş sınırsız push
  attırabiliyordu (ölçüldü — `infra/firestore.rules` `nudges` kuralı da
  oluşturma sayısını sınırlamıyor, yani tek hat buydu).

Zamanlayıcı SAATTE BİR çalışır; hangi kullanıcının sırası geldiğine
notification_service karar verir (yerel saat + sessiz saat + tekrar koruması).
Koşunun gövdesi ``services/notify_runner`` (AD8): panelin prova ve
"kendime test gönder" araçları aynı mantığı paylaşır.
"""
from __future__ import annotations

import logging
import secrets
from typing import Any, Literal

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

from core import config
from core.auth import AuthUser, get_current_user
from core.i18n import get_language
from core.messages import text
from services import (
    notification_service,
    notify_runner,
    profile_service,
    prompts,
    push_service,
)
# Geriye uyum (AD8): koşu gövdesi services/notify_runner'a taşındı; eski
# adlar buradan da okunabilir. Monkeypatch edilecek bağımlılıklar
# (`_iter_profiles`, `get_sky_now`, `firestore_client`, `_bayat_jetonu_sil`)
# artık `services.notify_runner` üzerinde yamalanır.
from services.notify_runner import (  # noqa: F401
    PAGE_SIZE,
    RunResult,
    _bayat_jetonu_sil,
    _iter_profiles,
    _jeton_sahipleri,
    _kosu_kaydet,
)

logger = logging.getLogger(__name__)
router = APIRouter()

#: Arkadaş tepkisi bildiriminde gösterilebilecek tepkiler. Firestore kuralıyla
#: (infra/firestore.rules, nudges) AYNI küme olmak zorunda.
REACTION_EMOJIS = {
    "streak": "🔥",
    "thinking_of_you": "💭",
    "shine": "✨",
    "keep_going": "💪",
    "congrats": "🎉",
    # OB5 onarımı: burası 🌊 idi, mobil picker 🛰️ gösteriyor — kullanıcının
    # BASTIĞI emoji kanonik olandır; alıcı farklı bir emoji görmemeli.
    "same_frequency": "🛰️",
    "good_night": "🌙",
    "check_today": "👀",
    # R3-4 genişlemesi — mobil kReactions + firestore.rules ile aynı küme.
    "hug": "🤗",
    "luck": "🍀",
    "coffee": "☕",
    "miss": "🫶",
}

#: Tepki anahtarı -> dile göre etiket. İstemcideki reactionLabel ile aynı
#: metinler; bildirim sunucuda üretildiği için burada da gerekli.
REACTION_LABELS = {
    "tr": {
        "streak": "Seriyi sürdür",
        "thinking_of_you": "Seni düşündüm",
        "shine": "Parlıyorsun",
        "keep_going": "Devam et",
        "congrats": "Tebrikler",
        "same_frequency": "Aynı frekans",
        "good_night": "İyi geceler",
        "check_today": "Bugüne bak",
        "hug": "Sarıldım",
        "luck": "Bol şans",
        "coffee": "Kahve içelim",
        "miss": "Özledim",
    },
    "en": {
        "streak": "Keep the streak",
        "thinking_of_you": "Thinking of you",
        "shine": "You're shining",
        "keep_going": "Keep going",
        "congrats": "Congrats",
        "same_frequency": "Same frequency",
        "good_night": "Good night",
        "check_today": "Check today",
        "hug": "A hug",
        "luck": "Good luck",
        "coffee": "Coffee soon?",
        "miss": "Miss you",
    },
}


def _verify_scheduler(authorization: str | None) -> None:
    if not config.NOTIFY_SCHEDULER_SECRET:
        logger.error("NOTIFY_SCHEDULER_SECRET tanimsiz; uc reddedildi.")
        raise HTTPException(status_code=503,
                            detail="Bildirim zamanlayicisi yapilandirilmamis.")
    if not authorization or not secrets.compare_digest(
        authorization, config.NOTIFY_SCHEDULER_SECRET
    ):
        raise HTTPException(status_code=401, detail="Gecersiz zamanlayici anahtari.")


def _tam_dusus_kapisi(sonuc: RunResult) -> None:
    """Tamamen düşen koşuyu 503'e çevirir (SZ-turu).

    NEDEN var — ölçüldü (2026-10-02): üretim yolundaki Gemini 403'ü BİR AY
    boyunca hiçbir yerde kırmızı görünmedi. Sebep bu uçtaydı: üretim
    düşünce bildirim şablon "teknik" satıra düşüp normal gidiyor, `sent`
    sağlıklı çıkıyor ve uç 200 dönüyordu. Cloud Scheduler günlüğü yalnız
    DURUM KODUNU gösterir — yanıt gövdesini kimse açmıyor — yani her saat
    yeşil bir satır yazılıyordu. Gövdeye sayı eklemek bu yüzden tek başına
    yetmez; kırmızı olan ŞEY durum kodu olmak zorunda.

    Eşik, "kısmi başarısızlık kırmızı DEĞİLDİR" kuralı ve prova muafiyeti
    `services/notify_runner._KIRMIZI_ESIGI` ile `_dusus_gerekcesi`de;
    burada tek karar `tamamen_dustu` adının okunması.

    503 bir telafi DEĞİL, yalnız GÖRÜNÜRLÜK: `infra/create-scheduler.ps1`
    işlere `--max-retry-attempts` vermiyor, yani düşen koşu yeniden
    denenmiyor (aynı gerekçe `maintenance/horoscope-warm` ucunda da yazılı).
    Sayılar gövdede kalır: hangi kapının yandığı `status`tan, kaç deneme /
    kaç başarı / kaç düşüş olduğu `generation` ve `queued`/`sent`/`failed`
    alanlarından okunur.
    """
    gerekce = notify_runner.tamamen_dustu(sonuc)
    if gerekce is None:
        return
    logger.error("Bildirim ucu 503: %s (%s)", gerekce, sonuc.model_dump())
    raise HTTPException(status_code=503, detail=sonuc.model_dump())


@router.post("/run", response_model=RunResult)
def run(type: Literal["daily", "midday", "circle", "winback",
                      "checkin", "streak"] = "daily",
        dry_run: bool = False,
        force: bool = False,
        ignore_dedupe: bool = False,
        authorization: str | None = Header(default=None)) -> RunResult:
    """Cloud Scheduler tetikli toplu gönderim — ince sarmalayıcı (AD8).

    Saatte bir çağrılır. Her kullanıcı için yerel saat hesaplanır ve yalnızca
    hedef saate denk gelenlere gönderilir; böylece tek bir zamanlayıcı işi tüm
    saat dilimlerini karşılar. Gövde `services/notify_runner.run_batch`
    (panelin prova/test araçlarıyla paylaşılır); burada yalnız zamanlayıcı
    sırrı kapısı ve bayrak doğrulaması kalır.

    İki operasyon bayrağı (ikisi de zamanlayıcı anahtarının arkasında):

    - ``dry_run``: her şey hesaplanır ama **hiçbir bildirim gönderilmez** ve
      gönderim kaydı yazılmaz. Deploy sonrası "kime gidecekti" sorusunu
      cevaplar; sıfır riskli.
    - ``force``: yalnızca **hedef saat** kontrolünü atlar.
    - ``ignore_dedupe``: yalnızca **tekrar koruması** kontrolünü atlar; tek
      başına anlamsız olduğu için ``force`` ile birlikte kullanılmalıdır.
      Aynı gün ikinci bir duman testi yapabilmek için var.

    **Sessiz saat ve kullanıcı tercihi hiçbir bayrakla atlanmaz.**

    **TAMAMEN düşen koşu 200 DÖNMEZ** (SZ-turu): 503 + gövdede sayılar.
    Gerekçe `_tam_dusus_kapisi`de.
    """
    _verify_scheduler(authorization)

    if ignore_dedupe and not force:
        raise HTTPException(
            status_code=400,
            detail="ignore_dedupe yalnizca force ile birlikte kullanilir.")

    sonuc = notify_runner.run_batch(type, dry_run=dry_run, force=force,
                                    ignore_dedupe=ignore_dedupe)
    _tam_dusus_kapisi(sonuc)
    return sonuc


class ReactionPush(BaseModel):
    friend_uid: str = Field(min_length=1, max_length=128)
    reaction: str = Field(min_length=1, max_length=32)


@router.post("/reaction")
def reaction(req: ReactionPush,
             user: AuthUser = Depends(get_current_user),
             lang: str = Depends(get_language)):
    """Arkadaşa gönderilen hazır tepkinin bildirimi.

    İstemci tepkiyi Firestore'a yazdıktan sonra burayı çağırır. Sunucu
    istemciye güvenmez: arkadaşlık karşılıklı mı, tepki kapalı kümede mi,
    alıcı bu bildirimi istiyor mu — hepsi burada doğrulanır.

    Bildirim gönderilemese bile 200 döner: tepki zaten Firestore'a yazıldı ve
    uygulama içindeki kutuda görünüyor. Push, üstüne eklenen bir şey.

    **TEKRAR KORUMASI (ölçülen istismar yolu).** Bu uç bir tur boyunca
    hiçbir tekrar korumasına tabi değildi: tepki kümesi kapalı ve
    arkadaşlık doğrulanıyordu ama AYNI arkadaş AYNI tepkiyi istediği kadar
    gönderip alıcının telefonunu sınırsız titretebiliyordu. Firestore
    kuralı da yardım etmiyor — `nudges` oluşturma sayısı orada
    sınırsızdır. Koruma davet/kabul ucuyla AYNI biçimde: alıcının kapalı
    dokümanında ``reaction-{gönderen}LastSent`` günü, yani çift başına
    günde EN FAZLA BİR push.
    Günlük TOPLAM tavan ayrıca `can_send_event` içinde; ikisi birlikte
    çalışmak zorunda — tavan tek başına olsaydı bir arkadaş alıcının bütün
    günlük bütçesini kendi dürtmeleriyle bitirebilirdi, çift koruması tek
    başına olsaydı yeterince arkadaş aynı günde bombardıman yapabilirdi.
    """
    if req.reaction not in REACTION_EMOJIS:
        raise HTTPException(status_code=400, detail=text("reaction.unknown", lang))

    if req.friend_uid == user.uid:
        raise HTTPException(status_code=400, detail=text("dyad.self", lang))

    if not profile_service.are_friends(user.uid, req.friend_uid):
        raise HTTPException(status_code=403,
                            detail=text("dyad.not_friends", lang))

    alici = profile_service.get_profile(req.friend_uid) or {}
    alici["uid"] = req.friend_uid
    gonder, gerekce = notification_service.can_send_event(alici, "friend")
    if not gonder:
        logger.info("Tepki bildirimi atlandi (%s): %s", req.friend_uid, gerekce)
        return {"status": "skipped", "reason": gerekce}

    # Çift başına günlük koruma. Tür adı GÖNDERENİ taşır: başka bir
    # arkadaşın dürtmesi bu kaydı görmez ve kendi hakkını kullanır.
    tekrar_turu = f"reaction-{user.uid}"
    gun = notification_service.local_now(alici).date().isoformat()
    if notification_service.already_sent(req.friend_uid, tekrar_turu, gun):
        logger.info("Tepki bildirimi atlandi (%s): zaten-gonderildi",
                    req.friend_uid)
        return {"status": "skipped", "reason": "zaten-gonderildi"}

    gonderen = profile_service.get_profile(user.uid) or {}
    alici_dili = notification_service.profile_language(alici)
    etiket = REACTION_LABELS.get(alici_dili, REACTION_LABELS["tr"])[req.reaction]

    baslik, govde = notification_service.friend_push(
        name=gonderen.get("displayName") or gonderen.get("username") or "…",
        emoji=REACTION_EMOJIS[req.reaction],
        label=etiket,
        lang=alici_dili,
    )

    sonuc = push_service.send([push_service.Message(
        uid=req.friend_uid, token=alici["fcmToken"],
        title=baslik, body=govde,
        # `src` (BY-turu): istemci tepkiyi davetten/kabulden ayırt edip
        # doğru hedefe yönlendirir (src: midday konvansiyonu).
        data={"type": "friend", "fromUid": user.uid, "src": "reaction"},
    )])
    # Kayıt yalnız gönderim BAŞARILIYSA yazılır (davet ucuyla aynı
    # sözleşme): FCM'in anlık hatası yüzünden arkadaşın o günkü tek
    # dürtme hakkı yanmasın.
    if sonuc.sent:
        notification_service.mark_sent(req.friend_uid, tekrar_turu, gun)
    return {"status": "ok", "sent": sonuc.sent}


class InvitePush(BaseModel):
    friend_uid: str = Field(min_length=1, max_length=128)


def _event_push(alici_uid: str, gonderen_uid: str, tur: str,
                baslik_sablonu: str, govde_sablonu: str,
                src: str) -> dict[str, Any]:
    """Davet/kabul push'unun ortak kuyruğu (OB2).

    Doğrulama ÇAĞIRANDA biter; buradan sonrası asla raise etmez — davet
    Firestore'a zaten yazıldı, push üstüne eklenen bir şeydir (tepki
    ucuyla aynı sözleşme). Tekrar koruması alıcının dokümanında
    ``{tur}LastSent`` günüyle: aynı çift aynı gün en fazla bir push
    (davet geri çek-tekrar gönder spam'ine karşı ikinci hat; birinci
    hat çağırandaki gerçek-kenar doğrulaması).
    """
    alici = profile_service.get_profile(alici_uid) or {}
    alici["uid"] = alici_uid

    gonder, gerekce = notification_service.can_send_event(alici, "friend")
    if not gonder:
        logger.info("Davet bildirimi atlandi (%s/%s): %s",
                    tur, alici_uid, gerekce)
        return {"status": "skipped", "reason": gerekce}

    gun = notification_service.local_now(alici).date().isoformat()
    if notification_service.already_sent(alici_uid, tur, gun):
        logger.info("Davet bildirimi atlandi (%s/%s): zaten-gonderildi",
                    tur, alici_uid)
        return {"status": "skipped", "reason": "zaten-gonderildi"}

    gonderen = profile_service.get_profile(gonderen_uid) or {}
    ad = gonderen.get("displayName") or gonderen.get("username") or "…"
    alici_dili = notification_service.profile_language(alici)
    p = prompts.get(alici_dili)

    sonuc = push_service.send([push_service.Message(
        uid=alici_uid, token=alici["fcmToken"],
        title=getattr(p, baslik_sablonu).format(name=ad),
        body=getattr(p, govde_sablonu),
        # `type=friend` + `src` (BY-turu): davet Çevrem sekmesine (istek
        # en üstte), kabul ise doğrudan o arkadaşın ilişki ekranına
        # yönlenir — istemci kararı `src` ile verir.
        data={"type": "friend", "fromUid": gonderen_uid, "src": src},
    )])
    if sonuc.sent:
        notification_service.mark_sent(alici_uid, tur, gun)
    return {"status": "ok", "sent": sonuc.sent}


@router.post("/invite")
def invite(req: InvitePush,
           user: AuthUser = Depends(get_current_user),
           lang: str = Depends(get_language)):
    """Arkadaş daveti gönderilince karşı tarafa push (OB2).

    Davet akışı bugüne dek tamamen sessizdi: istemci Firestore'a kenarları
    yazar, karşı taraf ancak uygulamayı açınca görürdü. Bu uç istemciden
    sonra çağrılır ve istemciye güvenmez: alıcının ağacında GERÇEK bir
    ``incoming`` kenarı olmalı — firestore.rules o kenarı yalnız gerçek
    davet akışının kurmasına izin verdiği için "davet etmeden push atma"
    vektörü kaynağında kapalı.
    """
    if req.friend_uid == user.uid:
        raise HTTPException(status_code=400, detail=text("dyad.self", lang))

    if not profile_service.has_pending_invite(user.uid, req.friend_uid):
        raise HTTPException(status_code=403, detail=text("invite.none", lang))

    # U17 (App Store 1.2): alıcı göndereni engellediyse push YOK. Dağıtılmış
    # kural bu kenarın kurulmasını zaten reddediyor; ama kenar kuralın
    # dağıtımından önce (ya da geri alınmış bir kuralla) kurulmuş olabilir
    # ve bu uç o hâlde engellenenin push'unu engelleyene düşürürdü. 200 +
    # skipped: davet ucunun sözleşmesi (doğrulamadan sonra raise yok).
    if profile_service.has_blocked(req.friend_uid, user.uid):
        logger.info("Davet bildirimi atlandi (%s): engelli", req.friend_uid)
        return {"status": "skipped", "reason": "engelli"}

    return _event_push(req.friend_uid, user.uid, f"invite-{user.uid}",
                       "PUSH_INVITE_TITLE", "PUSH_INVITE_BODY",
                       src="invite")


@router.post("/invite-accepted")
def invite_accepted(req: InvitePush,
                    user: AuthUser = Depends(get_current_user),
                    lang: str = Depends(get_language)):
    """Davet kabul edilince daveti GÖNDERENE push (OB2).

    Kabulden sonra iki kenar da ``accepted`` olduğu için yönün kim davet
    etti tarafı ispatlanamaz (bilinen sınır); ``are_friends`` çift taraflı
    doğrulaması + çift-başına-günlük tekrar koruması bunu zararsız kılar.
    """
    if req.friend_uid == user.uid:
        raise HTTPException(status_code=400, detail=text("dyad.self", lang))

    if not profile_service.are_friends(user.uid, req.friend_uid):
        raise HTTPException(status_code=403,
                            detail=text("dyad.not_friends", lang))

    return _event_push(req.friend_uid, user.uid, f"accept-{user.uid}",
                       "PUSH_INVITE_ACCEPTED_TITLE",
                       "PUSH_INVITE_ACCEPTED_BODY",
                       src="invite_accepted")

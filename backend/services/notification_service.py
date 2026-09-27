"""Bildirim zamanlama mantığı — kime, ne zaman, kaç kez.

Bu modül **gönderim yapmaz**; yalnızca karar verir. Gönderim api/notify.py
içindedir. Ayrım bilinçli: buradaki kurallar (yerel saat, sessiz saat, tekrar
koruması) FCM'e hiç dokunmadan test edilebilmeli.

Üç kural birlikte çalışır ve üçü de kullanıcıyı korumak içindir:

1. **Yerel saat.** Bildirim kullanıcının sabahına denk gelmeli. Sunucu UTC'de
   çalışır; kullanıcının saat dilimi profilinde IANA adı olarak tutulur.
   Doğum şehri kullanılamaz — kişi doğduğu yerde yaşamıyor olabilir.
2. **Sessiz saat.** Gece bildirim göndermek, bu kategoride uygulamanın
   silinmesinin en hızlı yoludur. Varsayılan 22:00-08:00.
3. **Tekrar koruması.** Zamanlayıcı saatte bir çalışır ve yeniden deneme
   yapabilir; aynı bildirim iki kez gitmemeli. Gönderim kaydı sunucuya kapalı
   bir dokümanda tutulur.
"""
from __future__ import annotations

import datetime as dt
import logging
from dataclasses import dataclass
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from core import cache, firestore as firestore_client, i18n
from services import gemini_service, prompts

logger = logging.getLogger(__name__)

#: Saat dilimi okunamazsa kullanılacak varsayılan. Kullanıcıların büyük
#: çoğunluğu bu dilimde; yine de her profilde saat dilimi olması hedeflenir.
DEFAULT_TIMEZONE = "Europe/Istanbul"

#: Sessiz saat varsayılanları (yerel saat, 24 saatlik).
DEFAULT_QUIET_FROM = 22
DEFAULT_QUIET_TO = 8

#: Bildirim türlerinin hedef yerel saati. Zamanlayıcı saatte bir çalışır ve
#: yalnızca yerel saati bu değere eşit olan kullanıcılara gönderir.
TARGET_HOURS = {
    "daily": 9,     # sabah: günün okuması hazır
    "midday": 13,   # öğle: yalnız BUGÜN gerçekten kesinleşen olay varsa (OB3)
    "checkin": 20,  # akşam: günün önemli sinyaline bağlı kişisel soru (KA4)
    "streak": 20,   # akşam: seri kırılmadan önce son hatırlatma (soru yoksa)
}

#: Zamanlayıcıdan tetiklenebilecek türler.
SCHEDULED_TYPES = tuple(TARGET_HOURS)

#: Serinin hatırlatmaya değer sayılması için gereken en az gün. Tek günlük
#: seri için bildirim göndermek rahatsız edici olur; kaybedilecek bir şey yok.
MIN_STREAK_FOR_REMINDER = 2


def _notification_doc(uid: str):
    client = firestore_client.get_client()
    if client is None:
        return None
    return (client.collection("users").document(uid)
            .collection("private").document("notifications"))


# ---------------------------------------------------------------------------
# Yerel saat
# ---------------------------------------------------------------------------

def user_timezone(profile: dict[str, Any]) -> ZoneInfo:
    """Profildeki saat dilimi; tanınmıyorsa varsayılan.

    Bilinmeyen bir dilim yüzünden istisna fırlatmak, tek bir bozuk profilin
    tüm toplu gönderimi düşürmesi demek olurdu.
    """
    ad = (profile.get("timezone") or "").strip()
    if ad:
        try:
            return ZoneInfo(ad)
        except (ZoneInfoNotFoundError, ValueError):
            logger.info("Taninmayan saat dilimi: %s", ad)
    return ZoneInfo(DEFAULT_TIMEZONE)


def local_now(profile: dict[str, Any],
              now_utc: dt.datetime | None = None) -> dt.datetime:
    """Kullanıcının yerel saati."""
    now_utc = now_utc or dt.datetime.now(dt.timezone.utc)
    if now_utc.tzinfo is None:
        now_utc = now_utc.replace(tzinfo=dt.timezone.utc)
    return now_utc.astimezone(user_timezone(profile))


# ---------------------------------------------------------------------------
# Sessiz saat
# ---------------------------------------------------------------------------

def _saat(deger: Any, varsayilan: int) -> int:
    try:
        saat = int(deger)
    except (TypeError, ValueError):
        return varsayilan
    return saat if 0 <= saat <= 23 else varsayilan


def in_quiet_hours(profile: dict[str, Any], yerel: dt.datetime) -> bool:
    """Yerel saat sessiz aralıkta mı?

    Aralık gece yarısını aşabilir (22:00-08:00). ``from == to`` sessiz saat
    yok demektir; aksi halde 24 saat sessiz olurdu ve kullanıcı hiç bildirim
    almazdı.
    """
    baslangic = _saat(profile.get("quietFrom"), DEFAULT_QUIET_FROM)
    bitis = _saat(profile.get("quietTo"), DEFAULT_QUIET_TO)
    if baslangic == bitis:
        return False

    saat = yerel.hour
    if baslangic < bitis:
        return baslangic <= saat < bitis
    # Gece yarısını aşan aralık
    return saat >= baslangic or saat < bitis


# ---------------------------------------------------------------------------
# Tekrar koruması
# ---------------------------------------------------------------------------

def already_sent(uid: str, tur: str, gun: str) -> bool:
    """Bu tür bildirim bu yerel gün için gönderildi mi?"""
    doc = _notification_doc(uid)
    if doc is None:
        # Firestore yoksa tekrar korumasını uygulayamayız. Güvenli taraf
        # GÖNDERMEMEK: aynı bildirimi iki kez atmak, hiç atmamaktan kötüdür.
        return True
    try:
        anlik = doc.get()
    except Exception as exc:
        logger.warning("Gonderim kaydi okunamadi (%s): %s", uid, exc)
        return True
    if not anlik.exists:
        return False
    return (anlik.to_dict() or {}).get(f"{tur}LastSent") == gun


def mark_sent(uid: str, tur: str, gun: str,
              extra: dict[str, Any] | None = None) -> None:
    """Gönderim kaydı. ``extra`` (OT1): daily dalı gönderilen GÖVDEYİ ve
    odak sinyalini de yazar — ertesi günün rotasyonu ve öğle kopya
    koruması bu hafızaya bakar. Tek merge yazımı; ek tur maliyeti yok.
    """
    doc = _notification_doc(uid)
    if doc is None:
        return
    try:
        doc.set({f"{tur}LastSent": gun, **(extra or {}),
                 "updatedAt": dt.datetime.now(dt.timezone.utc)}, merge=True)
    except Exception as exc:
        logger.warning("Gonderim kaydi yazilamadi (%s): %s", uid, exc)


def _body_hash(metin: str) -> str:
    import hashlib
    return hashlib.sha256(metin.encode("utf-8")).hexdigest()[:16]


def daily_sent_fields(gun: str, govde: str, idx: int,
                      sinyal: dict[str, Any], lang: str) -> dict[str, Any]:
    """Sabah gönderiminin `mark_sent(extra=...)` alanları (OT1.1).

    ``dailyBodyLang`` (PBZ-turu): gövde hangi dilde gittiyse o. Etiket
    olmayınca dil değişen günün sabahı dünkü Türkçe cümle İngilizce
    promptun içine `avoid=` olarak giriyordu; öğle kopya koruması da
    başka dildeki sabah gövdesiyle karşılaştırıyordu.
    """
    return {
        "dailyBody": govde[:200],
        "dailyBodyHash": _body_hash(govde),
        "dailyBodyLang": lang,
        "dailyFocusFp": (f"{sinyal.get('transit')}-{sinyal.get('aspect')}"
                         f"-{sinyal.get('natal')}"),
        "dailyFocusIdx": idx,
        "dailyTheme": sinyal.get("theme") or "",
        "dailyBodyDay": gun,
    }


def last_daily_sent(uid: str) -> dict[str, Any] | None:
    """Son gönderilen sabah bildiriminin hafızası; yoksa None (OT1.1).

    Sunucuya kapalı `private/notifications` dokümanından okur — istemci
    bu alanları ne görür ne yazabilir (firestore.rules private/**).
    """
    doc = _notification_doc(uid)
    if doc is None:
        return None
    try:
        anlik = doc.get()
    except Exception as exc:
        logger.warning("Gonderim hafizasi okunamadi (%s): %s", uid, exc)
        return None
    if not anlik.exists:
        return None
    veri = anlik.to_dict() or {}
    if not veri.get("dailyBodyHash"):
        return None
    return {
        "body": veri.get("dailyBody") or "",
        "bodyHash": veri["dailyBodyHash"],
        # Etiketsiz eski kayıt (bu deploy'dan önce yazılmış) "" döner:
        # hash kıyasına girer, gövdesi prompta girmez (`_hash_kiyaslanir`).
        "lang": veri.get("dailyBodyLang") or "",
        "focusFp": veri.get("dailyFocusFp") or "",
        "focusIdx": veri.get("dailyFocusIdx"),
        "theme": veri.get("dailyTheme") or "",
        "day": veri.get("dailyBodyDay") or veri.get("dailyLastSent") or "",
    }


def _hash_kiyaslanir(hafiza: dict[str, Any], lang: str) -> bool:
    """Hafızadaki gövdeyle HASH kıyası yapılır mı (PBZ-turu).

    Etiket bugünkü dilse evet. Etiket YOKSA ("" — bu deploy'dan önce
    yazılmış kayıt) da evet: aksi halde deploy günü eski kayıtlı herkes
    için "dünün/sabahın kopyası asla" koruması sessizce kapanırdı; hash
    aynıysa metin aynıdır, dili bilinmese de. Etiket BAŞKA dilse hayır —
    karşılaştırılacak ortak metin yok.

    Bu yalnız KIYAS kararıdır. Gövdeyi prompta sokmak (`avoid=`) etiketin
    bugünkü dille tam eşitliğini ister: etiketsiz gövde hangi dilde
    bilinmez, İngilizce promptun içine Türkçe cümle girebilirdi.
    """
    return (hafiza.get("lang") or "") in ("", lang)


# ---------------------------------------------------------------------------
# Karar
# ---------------------------------------------------------------------------

#: Tür -> profildeki tercih alanı. `checkin` BİLEREK streak tercihini
#: paylaşır: ikisi de "akşam dürtmesi" ailesinden ve akşam en fazla biri
#: gider — ayrı bir anahtar mobil ayar ekranını büyütürdü. Kullanıcılar
#: ayrı kapatmak isterse `notifyCheckin` o zaman eklenir.
PREF_FIELDS = {
    "daily": "notifyDaily",
    # OB3: öğle slotu "günün okuması" ailesinden — sabahı kapatan kullanıcı
    # öğleni de istemiyordur; ayrı bir anahtar ayar ekranını büyütürdü.
    "midday": "notifyDaily",
    "checkin": "notifyStreak",
    "streak": "notifyStreak",
    "friend": "notifyFriends",
}


def wants(profile: dict[str, Any], tur: str) -> bool:
    """Kullanıcı bu türü açık bırakmış mı? Alan yoksa AÇIK sayılır."""
    alan = PREF_FIELDS.get(tur)
    if alan is None:
        return False
    return profile.get(alan) is not False


def should_send(profile: dict[str, Any], tur: str,
                now_utc: dt.datetime | None = None,
                ignore_target_hour: bool = False,
                ignore_dedupe: bool = False) -> tuple[bool, str]:
    """Zamanlayıcı bu kullanıcıya şimdi göndermeli mi?

    ``(gonderilsin, gerekce)`` döner. Gerekçe loglama ve test içindir;
    "gönderilmedi" kararlarının neden alındığı görünür olmalı.

    ``ignore_target_hour`` ve ``ignore_dedupe`` yalnızca duman testi içindir
    (yayın sonrası "bildirim gerçekten gidiyor mu" kontrolü).

    **Sessiz saat ve tercih HİÇBİR bayrakla atlanmaz.** Bu ikisi kullanıcının
    açık iradesi; elinde zamanlayıcı anahtarı olan biri bile kullanıcıyı gece
    yarısı uyandıramamalı ya da kapattığı bildirimi ona gönderememeli.
    """
    if tur not in SCHEDULED_TYPES:
        return False, "bilinmeyen-tur"
    if not profile.get("fcmToken"):
        return False, "token-yok"
    if not profile.get("onboardingCompleted"):
        return False, "onboarding-tamamlanmamis"
    if not wants(profile, tur):
        return False, "tercih-kapali"

    yerel = local_now(profile, now_utc)
    if not ignore_target_hour and yerel.hour != TARGET_HOURS[tur]:
        return False, "saat-uygun-degil"
    if in_quiet_hours(profile, yerel):
        # Hedef saat sessiz aralığa denk geliyorsa kullanıcının tercihi
        # kazanır; bildirim atlanır.
        return False, "sessiz-saat"

    if tur == "streak":
        seri = int(profile.get("streakCount") or 0)
        if seri < MIN_STREAK_FOR_REMINDER:
            return False, "seri-kisa"
        if profile.get("lastSeenDaily") == yerel.date().isoformat():
            return False, "bugun-zaten-okudu"
        # KA4: akşam EN FAZLA bir bildirim — check-in gittiyse seri
        # hatırlatması susar. (checkin işi :08'de, streak :10'da koşar;
        # bu koruma sırayı da yeniden denemeyi de dert etmez.)
        if already_sent(profile["uid"], "checkin",
                        yerel.date().isoformat()):
            return False, "aksam-checkin-gitti"

    if tur == "checkin" and already_sent(profile["uid"], "streak",
                                         yerel.date().isoformat()):
        # Ters sıra da korunur: streak bir şekilde önce gittiyse aynı
        # akşam bir de soru göndermeyiz.
        return False, "aksam-streak-gitti"

    if not ignore_dedupe and already_sent(profile["uid"], tur,
                                          yerel.date().isoformat()):
        return False, "zaten-gonderildi"

    return True, "gonderilecek"


# ---------------------------------------------------------------------------
# Bildirim metni
#
# Birim ekonomi kuralı burada da geçerli: bildirim metni KULLANICI BAŞINA
# üretilmez. Günlük bildirimin gövdesi (burç, gün, dil) anahtarıyla
# önbelleklenir — 12 burç x 2 dil = günde en fazla 24 LLM çağrısı, kaç
# kullanıcı olursa olsun. Seri ve arkadaş bildirimleri hiç LLM kullanmaz.
# ---------------------------------------------------------------------------

#: Bildirim satırı için üst sınır. Prompt 85 karakter istiyor; model taşarsa
#: kırpmak yerine yedek metne düşeriz (yarım cümle göstermeyiz).
MAX_PUSH_BODY = 110


def daily_push_cache_key(sign: str, gun: str, lang: str) -> str:
    return f"push-daily-{sign}-{gun}-{lang}"


def daily_push_body(sign: str, sky: dict[str, Any], lang: str,
                    gun: str | None = None) -> str:
    """Burç için günün tek satırlık bildirim metni.

    ``sign`` İngilizce burç anahtarıdır ("leo"). ``sky`` çağıran tarafından
    **dile göre yerelleştirilmiş** olarak gelir.
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    gun = gun or dt.date.today().isoformat()
    p = prompts.get(lang)
    sign_adi = p.SIGN_NAMES.get(sign, sign)

    anahtar = daily_push_cache_key(sign, gun, lang)
    onbellekten = cache.get(anahtar)
    if onbellekten is not None:
        return onbellekten

    moon = (sky or {}).get("moon_phase") or {}
    retros = ", ".join((sky or {}).get("retrogrades") or []) or p.NONE_LABEL
    prompt = p.PUSH_DAILY_PROMPT.format(
        sign=sign_adi, today=gun, moon_name=moon.get("name") or "-",
        illumination=moon.get("illumination"), retros=retros,
    )

    metin = (gemini_service.generate(prompt, lang=lang,
                                     feature="push_daily") or "").strip()
    # Model bazen tırnak içinde döndürüyor; bildirimde tırnak görünmemeli.
    metin = metin.strip('"').strip("'").strip()
    if not metin or len(metin) > MAX_PUSH_BODY:
        if metin:
            logger.info("Push satiri cok uzun (%s kar.), yedege dusuldu",
                        len(metin))
        metin = p.PUSH_DAILY_FALLBACK.format(
            sign=sign_adi, date=prompts.signal_date(lang, gun))

    # Yedek metin de önbelleklenir: aksi halde Gemini'nin sorunlu olduğu bir
    # saatte her burç için tekrar tekrar denenirdi.
    cache.set(anahtar, metin, ttl_seconds=36 * 3600)
    return metin


def _bundle_body(paket: dict[str, Any] | None, idx: int,
                 yerel: list[dict[str, Any]], lang: str,
                 uid: str = "") -> str:
    """idx'inci sinyalin gövdesi: paket cümlesi; yoksa, taşarsa ya da DİLİ
    UYMAZSA teknik satır.

    Boş dize dönerse o sinyalden gövde çıkmadı demektir (teknik satır da
    taşmış) — çağıran başka sinyale bakar ya da None döner.

    DM-turu (cihaz bulgusu "hem İngilizce hem Türkçe push"): paket cümlesi
    LLM'den gelir ve LLM'in dili SÖZ değildir. Muhafız deterministik ve
    BURADA: sabah (`signal_push`, yeniden üretim yolu dahil) ve öğle
    (`midday_push`) paket cümlesini yalnız bu fonksiyondan okur; tek nokta
    ikisini de kapatır. Teknik satır şablondur, dili kesindir — ona düşmek
    güvenli. ``uid`` yalnız log içindir.
    """
    govde = ""
    if paket and len(paket.get("insights") or []) > idx:
        govde = paket["insights"][idx]
        if not 0 < len(govde) <= prompts.get(lang).SIGNAL_INSIGHT_MAX:
            govde = ""
        elif i18n.language_conflicts(govde, lang):
            logger.warning(
                "Bildirim gövdesi dili uyuşmuyor: uid=%s lang=%s tahmin=%s "
                "— teknik satıra düşüldü",
                uid, lang, i18n.guess_language(govde))
            govde = ""
    if not govde:
        govde = yerel[idx]["technical"]
        if not 0 < len(govde) <= MAX_PUSH_BODY:
            return ""
    return govde


def ai_izinli(profile: dict[str, Any]) -> bool:
    """Bu kullanıcının sinyal satırları Gemini'ye gidebilir mi? (U06)

    Uçlardaki kararın AYNISI (`core.ai_consent.izin_var`); sürüm
    başlıktan değil sunucunun yazdığı sürüm aynasından (`appBuild`) gelir
    — zamanlanmış koşunun isteği kullanıcının cihazından gelmiyor. Onayı
    geri almış ya da "Şimdi değil" demiş kullanıcının sabah bildirimi
    AI'sız teknik satıra düşer; bildirim yine gider.
    """
    from core import ai_consent, app_gate
    return ai_consent.izin_var(str(profile.get("uid") or ""),
                               app_gate.parse_build(profile.get("appBuild")))


def signal_push(profile: dict[str, Any], lang: str,
                today: dt.date | None = None,
                onceki: dict[str, Any] | None = None
                ) -> tuple[str, str, str, int, dict[str, Any]] | None:
    """Sabah bildirimi — TEMA ÇARKLI odak sinyalinden (R2-S4 → OT-turu).

    ``(başlık, gövde, parmak_izi, idx, hafıza_alanları)`` döner. Gövde uç
    ile AYNI paylaşılan paketten; günde toplam bir LLM çağrısı korunur.

    OT-turu (cihaz bulgusu "dünkü bildirimle aynıydı"): odak artık hep
    0 değil — bugün kesinleşen varsa o, yoksa dünkü temadan SONRAKİ tema
    (`daily_focus_index`, kullanıcı kararı: "bir gün ilişki, bir gün
    mali, bir gün iç dünya"). Gövde dünkü gövdeyle AYNI çıkarsa: önce
    farklı sinyal denenir (bedava), sonra TEK yeniden üretim (dünkü
    cümle negatif örnek), o da tutmazsa geri sayımlı teknik satır —
    hiçbir yolda dünkü metnin kopyası gönderilmez.

    PBZ-turu: aynılık koruması dünkü gövde BAŞKA dilde gittiyse çalışmaz.
    Dil değişen sabah dünkü hafıza başka dildedir — hash'i karşılaştırmak
    anlamsız, gövdesini `avoid=` ile prompta sokmak ise Türkçe cümleyi
    İngilizce promptun içine koymak demek (prompts/en.py'nin kendi
    uyarısı). Etiketsiz eski kayıt (bu deploy'dan önce yazılmış) hash
    kıyasına GİRER — deploy günü koruma kapanmaz — ama gövdesi `avoid=`
    ile prompta girmez (`_hash_kiyaslanir`). Tema çarkı dilden
    bağımsızdır, o hep dünü okur.

    Üretilemezse None döner ve çağıran paylaşımlı burç satırına düşer;
    bildirim ASLA atlanmaz.
    """
    try:
        from services import signal_service
        ham = signal_service.cached_signals(profile, today=today)
        if not ham or not ham.get("signals"):
            return None
        gun = (today or dt.date.today()).isoformat()

        dun = onceki if (onceki and onceki.get("day") != gun) else None
        # Hash kıyası: aynı dil YA DA etiketsiz eski kayıt. `avoid=` ise
        # yalnız etiket bugünkü dille TAM eşitse (etiketsiz gövdenin dili
        # bilinmez; prompta girmez).
        hash_kiyaslanir = dun is not None and _hash_kiyaslanir(dun, lang)
        ayni_dil = dun is not None and dun.get("lang") == lang
        idx = signal_service.daily_focus_index(
            ham,
            prev_theme=(dun or {}).get("theme") or None,
            prev_fp=(dun or {}).get("focusFp") or None)

        uid = profile.get("uid") or ""
        # U06: onay yoksa paket ne ÜRETİLİR ne OKUNUR. Yalnız üretimi
        # kesmek yetmezdi: aynı haritaya sahip başka bir kullanıcının
        # ürettiği paket önbellekte durabilir ve "hayır" diyen kullanıcı
        # yine AI cümlesi alırdı — veri gitmese de ekranın söylediğiyle
        # çelişen bir deneyim.
        izinli = ai_izinli(profile)
        paket = (signal_service.cached_insight_bundle(ham, lang)
                 if izinli else None)
        yerel = prompts.localize_signals(lang, ham)["signals"]
        # DM-turu: dil muhafızı `_bundle_body` içinde — aşağıdaki her
        # gövde adayı (ilk seçim, farklı sinyal, yeniden üretim) oradan
        # geçer; teknik satırın kendisi şablon olduğu için burada ayrıca
        # kontrol yoktur.
        govde = _bundle_body(paket, idx, yerel, lang, uid=uid)

        # Dünle aynılık koruması (OT1.3) — sınırlı: 1 ek LLM çağrısı.
        # Başka dildeki dünkü gövdeyle kıyas yok: ortak metin yok.
        if (govde and hash_kiyaslanir
                and _body_hash(govde) == dun.get("bodyHash")):
            for aday in range(len(yerel)):
                if aday == idx:
                    continue
                aday_govde = _bundle_body(paket, aday, yerel, lang, uid=uid)
                if aday_govde and _body_hash(aday_govde) != dun["bodyHash"]:
                    idx, govde = aday, aday_govde
                    break
            else:
                # Dünkü cümle negatif örnek olarak YALNIZ aynı dilde girer.
                yeni = (signal_service.insight_bundle(
                    ham, lang,
                    avoid=(dun.get("body") or "") if ayni_dil else "")
                    if izinli else None)
                if yeni:
                    cache.set(
                        signal_service.bundle_key(
                            signal_service.signals_fingerprint(ham), lang),
                        yeni, ttl_seconds=signal_service.BUNDLE_TTL_OK)
                    aday_govde = _bundle_body(yeni, idx, yerel, lang, uid=uid)
                    if aday_govde and _body_hash(aday_govde) != dun["bodyHash"]:
                        govde = aday_govde
                if _body_hash(govde) == dun["bodyHash"]:
                    govde = yerel[idx]["technical"]
                    if (not 0 < len(govde) <= MAX_PUSH_BODY
                            or _body_hash(govde) == dun["bodyHash"]):
                        return None
        if not govde:
            return None

        sinyal = yerel[idx]
        p = prompts.get(lang)
        iz = signal_service.signals_fingerprint(ham)
        extra = daily_sent_fields(gun, govde, idx,
                                  (ham.get("signals") or [])[idx], lang)
        return (p.PUSH_SIGNAL_TITLE.format(
                    emoji=prompts.theme_emoji(sinyal.get("theme")),
                    theme=sinyal["theme_local"]),
                govde, iz, idx, extra)
    except Exception as exc:
        logger.warning("Sinyal bildirimi uretilemedi (%s): %s",
                       profile.get("uid"), exc)
        return None


@dataclass(frozen=True)
class PushIcerik:
    """Bir bildirimin metni + gövdesinin BİÇİMİ.

    ``soru`` bu turun (SS) çekirdek ayrımı. Kullanıcının koyduğu kural
    bildirimin TÜRÜYLE değil gövdesinin biçimiyle ilgili: gövde bir
    SORUysa Rytho sohbette önce yazar ve kullanıcı cevaplar; İFADEyse
    dokunuş bugünkü gibi kullanıcının sorusunu ön-doldurur.

    Kararı ÜRETİCİ verir, çağıran değil. `notify.py` yalnız bu bayrağa
    bakar; hiçbir yerde `if type == "checkin"` yazmaz. Yeni bir soru
    biçimli bildirim eklemek tek satır: `soru=True`.
    """

    baslik: str
    govde: str
    soru: bool = False


def _bundle_in_other_language(fp: str, lang: str) -> bool:
    """Bugünün paketi ``lang`` DIŞINDA bir dilde SORULU üretilmiş mi?

    Yalnız önbellek okur. Kayıt yorum taşıyorsa o sabah push gitmiştir;
    ama akşam üretiminin tek anlamı SORU: `checkin_question` odak
    sinyaline bağlıdır (`significant_signal` — determinist, dilden
    bağımsız). Diğer dildeki paket sorusuzsa (önemli sinyal yok) yeni
    dilde üretilecek paket de sorusuz çıkar; LLM boşa yanardı. Ölçüt bu
    yüzden `insights` değil `checkin_question`.
    """
    from services import signal_service
    for diger in i18n.SUPPORTED:
        if diger == lang:
            continue
        kayit = cache.get(signal_service.bundle_key(fp, diger))
        if (kayit and not kayit.get("failed")
                and kayit.get("checkin_question")):
            return True
    return False


def checkin_push(profile: dict[str, Any], lang: str,
                 today: dt.date | None = None) -> PushIcerik | None:
    """Akşam check-in sorusu (KA4) — YALNIZ önbellekten, LLM yakmaz.

    Soru sabahki toplu üretimin son satırıdır; akşam işi yalnız okur
    (`generate_if_missing=False`). Paket yoksa ya da o gün "önemli
    sinyal" çıkmadıysa None döner — çağıran kullanıcıyı atlar ve :10'daki
    seri hatırlatması normal davranır.

    Tek istisna (PBZ-turu, dil değişen gün): paket bugünkü dilde yok ama
    BAŞKA desteklenen dilde var — yani sabah bu kullanıcıya o dilde push
    gitti, sonra dil değişti. Eskiden akşam "soru-yok" ile sessizce
    düşüyordu. Şimdi yeni dilde BİR KEZ üretilir; `cached_insight_bundle`
    önbelleğe yazdığı için aynı günün ikinci koşusu yeniden üretmez.
    Hiçbir dilde paket yoksa eskisi gibi: LLM yakılmaz, None.

    ``soru=True`` döner: gövde `checkin_question` alanından geliyor, yani
    tanım gereği bir sorudur.
    """
    try:
        from services import signal_service
        ham = signal_service.cached_signals(profile, today=today)
        if not ham or not ham.get("signals"):
            return None
        # U06: akşam sorusu hem AI çıktısı hem de sohbete (AI) açılan bir
        # davet; onaysız kullanıcıya hiç gitmez. Dil değişen gün yolu
        # aşağıda paketi ÜRETEBİLDİĞİ için kapı ondan önce.
        if not ai_izinli(profile):
            return None
        paket = signal_service.cached_insight_bundle(
            ham, lang, generate_if_missing=False)
        if paket is None and _bundle_in_other_language(
                signal_service.signals_fingerprint(ham), lang):
            paket = signal_service.cached_insight_bundle(
                ham, lang, generate_if_missing=True)
        soru = (paket or {}).get("checkin_question")
        if not soru:
            return None
        # DM-turu: soru da LLM çıktısı, dili söz değil. Yanlış dildeyse
        # akşam sorusu ATLANIR — bu bildirim isteğe bağlı, :10'daki seri
        # hatırlatması devreye girer; sohbete yanlış dilde tohum da
        # atılmamış olur. Yedek metin yok: soru biçimli şablon uydurmayız.
        if i18n.language_conflicts(soru, lang):
            logger.warning(
                "Check-in sorusu dili uyuşmuyor: uid=%s lang=%s tahmin=%s "
                "— akşam sorusu atlandı",
                profile.get("uid"), lang, i18n.guess_language(soru))
            return None
        return PushIcerik(prompts.get(lang).PUSH_CHECKIN_TITLE, soru,
                          soru=True)
    except Exception as exc:
        logger.warning("Check-in bildirimi uretilemedi (%s): %s",
                       profile.get("uid"), exc)
        return None


def midday_push(profile: dict[str, Any], lang: str,
                today: dt.date | None = None
                ) -> tuple[tuple[str, str, dict[str, str]] | None, str]:
    """Öğle ölçülü slotu (OB3 → OT1.2) — yalnız gerçekten olay varsa, LLM'siz.

    ``(yük, gerekçe)`` döner; yük None ise gerekçe "olay-yok" ya da
    "sabahla-ayni" — öğle bildirimi bir HAK değil, ölçülmüş bir olayın
    haberi ve SABAH GÖNDERİLENİN KOPYASI ASLA DEĞİL (canlıda yakalanan
    açık: bugün kesinleşen sinyal çoğunlukla sabahın odağıydı ve 13:00
    gövdesi 09:00'unkiyle bayt-aynı çıkıyordu). Çözüm sırası:

    a) **Kendi haritasında BUGÜN kesinleşen açı** (``days_to_exact == 0``,
       sabahki paylaşımlı sinyal önbelleği): gövde sabah paketindeki
       indeks-hizalı AI cümlesi (yalnız okunur — öğle LLM yakmaz), yoksa
       dürüst teknik satır. SABAH GÖVDESİYLE AYNI ÇIKARSA aynı paketten
       farklı bir sinyal denenir; o da yoksa (b)'ye düşülür.
    b) **Çift ânı, YALNIZ ÖNBELLEK** (`pair_transits_cached` — asla
       hesaplamaz). Yük `type=friend` → Çevrem sekmesi.
    c) Hiçbiri → (None, gerekçe).
    """
    try:
        from services import (circle_context, people_service, profile_service,
                              signal_service, synastry_service)

        today = today or dt.date.today()
        gun = today.isoformat()

        # Sabah hafızası (OT1.1): bugün gönderilen gövdenin kopyası yasak.
        # PBZ-turu: sabah gövdesi BAŞKA dilde gittiyse (dil öğlene kadar
        # değişti) karşılaştırılacak ortak metin yok; etiketsiz eski kayıt
        # yine kıyaslanır (`_hash_kiyaslanir`).
        uid = profile.get("uid") or ""
        dun = last_daily_sent(uid)
        sabah_hash = (dun or {}).get("bodyHash") \
            if ((dun or {}).get("day") == gun
                and _hash_kiyaslanir(dun or {}, lang)) else None
        sabahla_ayni = False

        # --- a) kendi haritasında bugün kesinleşen ---
        ham = signal_service.cached_signals(profile, today=today)
        sinyaller = (ham or {}).get("signals") or []
        bugunku = [i for i, s in enumerate(sinyaller)
                   if s.get("exact_on") and s.get("days_to_exact") == 0]
        if ham and bugunku:
            p = prompts.get(lang)
            yereller = prompts.localize_signals(lang, ham)["signals"]
            # U06: sabahla aynı kural — onaysız kullanıcıya paket okunmaz.
            paket = (signal_service.cached_insight_bundle(
                ham, lang, generate_if_missing=False)
                if ai_izinli(profile) else None)
            # Bugün kesinleşenler önce; hepsi sabahın kopyasıysa diğer
            # sinyaller de denenir (paket zaten elimizde, sıfır maliyet).
            for idx in bugunku + [i for i in range(len(sinyaller))
                                  if i not in bugunku]:
                # DM-turu: dil muhafızı `_bundle_body` içinde (sabahla ortak).
                govde = _bundle_body(paket, idx, yereller, lang, uid=uid)
                if not govde:
                    continue
                if sabah_hash and _body_hash(govde) == sabah_hash:
                    sabahla_ayni = True
                    continue
                yerel = yereller[idx]
                baslik = p.PUSH_MIDDAY_TITLE.format(
                    emoji=prompts.theme_emoji(yerel.get("theme")),
                    theme=yerel["theme_local"])
                veri = {"type": "daily", "route": "signal",
                        "fp": signal_service.signals_fingerprint(ham),
                        "idx": str(idx), "d": gun, "src": "midday"}
                sign = profile_service.sun_sign_key(profile)
                if sign:
                    veri["sign"] = sign
                return (baslik, govde, veri), "gonderilecek"
        # --- b) çift ânı, yalnız önbellekten ---
        # Aday = (karşı taraf, hedef kimliği). Kimlik yükte taşınır (BY):
        # dokununca O ilişkinin ekranı açılır — kimliksiz yük istemciyi
        # yalnız Çevrem sekmesine bırakıyordu ("sadece uygulama açılıyor").
        adaylar: list[tuple[Any, dict[str, str]]] = []
        for friend_uid in circle_context.list_accepted_friend_uids(uid):
            cp = synastry_service.friend_counterpart(uid, friend_uid)
            if cp is not None:
                adaylar.append((cp, {"fromUid": friend_uid}))
        for kayit in people_service.list_people(uid):
            cp = synastry_service.person_counterpart(
                uid, kayit["id"], lang=lang)
            if cp is not None:
                adaylar.append((cp, {"pid": kayit["id"]}))

        from services import chart_context
        en_iyi: tuple[tuple[int, float], Any, dict[str, str],
                      dict[str, Any]] | None = None
        for cp, kimlik in adaylar:
            veri_cp = synastry_service.pair_transits_cached(uid, cp,
                                                            today=today)
            vuruslar = (veri_cp or {}).get("hits") or []
            if not vuruslar:
                continue
            v = vuruslar[0]  # zaten yavaş-önce + dar-orb sıralı
            sira = (0 if chart_context.is_slow_mover(v.get("transit")) else 1,
                    float(v.get("orb") or 99.0))
            if en_iyi is None or sira < en_iyi[0]:
                en_iyi = (sira, cp, kimlik, v)

        if en_iyi is not None:
            _, cp, kimlik, v = en_iyi
            satirlar = synastry_service.pair_transit_lines([v], cp.label,
                                                           lang)
            if satirlar and 0 < len(satirlar[0]) <= MAX_PUSH_BODY:
                p = prompts.get(lang)
                baslik = p.PUSH_MIDDAY_PAIR_TITLE.format(name=cp.label)
                return ((baslik, satirlar[0],
                         {"type": "friend", "src": "midday", "d": gun,
                          **kimlik}),
                        "gonderilecek")

        return None, ("sabahla-ayni" if sabahla_ayni else "olay-yok")
    except Exception as exc:
        logger.warning("Ogle bildirimi uretilemedi (%s): %s",
                       profile.get("uid"), exc)
        return None, "olay-yok"


def streak_push(profile: dict[str, Any], lang: str) -> tuple[str, str]:
    """Seri hatırlatması — şablon, LLM yok."""
    p = prompts.get(lang)
    seri = int(profile.get("streakCount") or 0)
    return p.PUSH_STREAK_TITLE.format(days=seri), p.PUSH_STREAK_BODY


def friend_push(name: str, emoji: str, label: str,
                lang: str) -> tuple[str, str]:
    """Arkadaş tepkisi — şablon, LLM yok."""
    p = prompts.get(lang)
    return (p.PUSH_FRIEND_TITLE.format(name=name),
            p.PUSH_FRIEND_BODY.format(emoji=emoji, label=label))


def profile_language(profile: dict[str, Any]) -> str:
    """Profildeki dil; yoksa varsayılan.

    Bildirim sunucuda üretildiği için istemcinin ``Accept-Language`` başlığı
    burada yoktur — dil profile yazılır (bkz. apps/mobile/lib/core/locale.dart).
    """
    kod = (profile.get("language") or "").strip().lower()
    return kod if kod in i18n.SUPPORTED else i18n.DEFAULT


def can_send_event(profile: dict[str, Any], tur: str,
                   now_utc: dt.datetime | None = None) -> tuple[bool, str]:
    """Olay tabanlı bildirim (arkadaş tepkisi) gönderilebilir mi?

    Zamanlayıcıdan farkı: hedef saat yoktur, olay ne zaman olduysa o zaman
    gider. Ama sessiz saat yine de geçerlidir — bir arkadaşın tepkisi gece
    3'te telefonu titretmeye yetmez. Sessiz saatte bildirim DÜŞÜRÜLÜR,
    ertelenmez; tepki uygulama içindeki kutuda zaten görünüyor.
    """
    if not profile.get("fcmToken"):
        return False, "token-yok"
    if not wants(profile, tur):
        return False, "tercih-kapali"
    if in_quiet_hours(profile, local_now(profile, now_utc)):
        return False, "sessiz-saat"
    return True, "gonderilecek"

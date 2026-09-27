"""Abonelik uclari: RevenueCat webhook'u ve istemci icin durum sorgusu.

Abonelik durumunun **tek yazma yolu** buradaki webhook'tur. Istemci kendi
abonelik kaydini yazamaz (``users/{uid}/private/**`` Firestore kurallarinda
istemciye kapalidir), cunku aksi halde ucretli icerik istemci tarafindan
acilabilirdi.

RevenueCat'in `app_user_id` alani Firebase uid'sidir; istemci satin alma
oncesi `Purchases.logIn(uid)` cagirir.
"""
from __future__ import annotations

import datetime as dt
import logging
import secrets
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

from core import config, entitlements, wallet
from core import firestore as firestore_client
from core.auth import AuthUser, get_current_user
from core.i18n import get_language
from core.messages import text

logger = logging.getLogger(__name__)
router = APIRouter()

#: Aboneligi baslatan/surduren olaylar.
_ACTIVATING_EVENTS = {
    "INITIAL_PURCHASE", "RENEWAL", "TRIAL_STARTED", "TRIAL_CONVERTED",
    "UNCANCELLATION", "PRODUCT_CHANGE", "SUBSCRIPTION_EXTENDED",
}

#: Erisimi hemen bitiren olaylar.
_DEACTIVATING_EVENTS = {"EXPIRATION", "SUBSCRIPTION_PAUSED", "REFUND"}

#: Otomatik yenilemeyi kapatan ama erisimi SURDUREN olaylar.
#: RevenueCat'te CANCELLATION "iptal edildi" degil "yenilenmeyecek" demektir;
#: kullanici odedigi donemin sonuna kadar erisimini korur.
_CANCELLATION_EVENTS = {"CANCELLATION", "BILLING_ISSUE"}

#: Parasal anlami olan olaylar — append-only gelir defterine yazilir (W3).
#: TRIAL_STARTED bilerek yok: deneme baslangicinda para el degistirmez.
_REVENUE_EVENTS = {
    "INITIAL_PURCHASE", "RENEWAL", "TRIAL_CONVERTED",
    "NON_RENEWING_PURCHASE", "REFUND",
}

#: Parasal OLMAYAN ama abonelik geçmişi için anlamlı olaylar (AD5). Aynı
#: deftere `price=0, monetary=false` ile yazılır: `private/subscription`
#: `set()` ile ezildiği için "ne zaman iptal etti, ödeme sorunu ne zaman
#: başladı" sorusunun tek kalıcı cevabı bu kayıtlardır. Panel gelir
#: toplamlarında `monetary` süzgeciyle ayrışırlar.
_NON_MONETARY_EVENTS = {
    "CANCELLATION", "BILLING_ISSUE", "EXPIRATION", "SUBSCRIPTION_PAUSED",
    "TRIAL_STARTED", "UNCANCELLATION", "PRODUCT_CHANGE",
    "SUBSCRIPTION_EXTENDED",
}

#: RevenueCat ortamı: `PRODUCTION` | `SANDBOX`. Alanı olmayan eski
#: olaylar backfill'de SANDBOX etiketlenir (kapalı test öncesi gerçek
#: satış yok); webhook'ta alan yoksa PRODUCTION varsayılır — canlıda
#: RevenueCat alanı her olayda gönderir.
_DEFAULT_ENVIRONMENT = "PRODUCTION"


def _environment(event: dict[str, Any]) -> str:
    return str(event.get("environment") or _DEFAULT_ENVIRONMENT).upper()

#: Aboneligi bir kimlikten digerine tasiyan olay.
#:
#: Anonim bir kimlikle satin alma yapilip sonra oturum acildiginda RevenueCat
#: kaydi devreder ve bu olayi gonderir. Islenmezse abonelik anonim dokumanda
#: kalir, kullanicinin uid'i altinda hicbir sey olmaz ve odeme yapmis kullanici
#: kilitli ekranla kalir.
#:
#: Bu olayin yukunde `app_user_id` YOKTUR; kimlikler `transferred_from` ve
#: `transferred_to` listelerinde gelir.
_TRANSFER_EVENT = "TRANSFER"


class SubscriptionStatus(BaseModel):
    active: bool
    product_id: str | None = None
    expires_at: str | None = None
    will_renew: bool | None = None
    is_trial: bool | None = None
    #: OT6: sunucu taraflı 3 günlük deneme — paywall'daki geri sayım.
    #: Yalnız deneme aktifken dolu; mağaza aboneliğinde None.
    trial_days_left: int | None = None


@router.get("/status", response_model=SubscriptionStatus)
def status(user: AuthUser = Depends(get_current_user)):
    """Istemcinin arayuzu kilitlemek icin sordugu durum.

    Istemci RevenueCat SDK'sinin yerel durumunu da gorur; bu uc sunucunun
    gordugu gercegi doner ve ikisi ayrisirsa sunucu esas alinir.
    """
    subscription = entitlements.get_subscription(user.uid)
    expires_at = subscription.get("expiresAt")
    # OT6: mağaza aboneliği yokken deneme dönemi de "açık" sayılır
    # (is_subscriber zaten öyle diyor); istemci geri sayımı buradan okur.
    deneme_kalan = (None if subscription.get("active")
                    else entitlements.trial_days_left(user.uid))
    return SubscriptionStatus(
        # `is_subscriber` ile aynı kaynağa bakar — ham `active` alanına DEĞİL.
        #
        # İkisi ayrışabiliyordu: `RYTHO_FORCE_PLUS=1` ile uçlar açılıyor ama
        # bu uç "kapalı" diyordu, dolayısıyla istemci kilitli kart gösterip
        # kullanıcıyı çalışan bir özelliğe sokmuyordu. Bu ucun sözleşmesi
        # "sunucunun gördüğü gerçek"; sunucu çağrıyı kabul edecekse burada da
        # açık görünmeli, aksi halde istemci ile sunucu ayrışır.
        active=entitlements.is_subscriber(user.uid),
        product_id=subscription.get("productId"),
        expires_at=expires_at.isoformat() if hasattr(expires_at, "isoformat") else None,
        will_renew=subscription.get("willRenew"),
        is_trial=subscription.get("isTrial") or (deneme_kalan is not None),
        trial_days_left=deneme_kalan,
    )


class WalletStatus(BaseModel):
    allowance: int
    purchased: int
    total: int
    monthly_allowance: int
    allowance_resets_at: str | None = None
    costs: dict[str, int]


@router.get("/wallet", response_model=WalletStatus)
def wallet_status(user: AuthUser = Depends(get_current_user)):
    """İstemcinin bakiye göstergesi ve token mağazası için tek gerçek.

    İstemci paket adetlerini de buradan öğrenmez — yalnızca bedel tablosunu
    görür; paket içerikleri satın alma sonrası webhook'la sunucuda yüklenir.
    """
    # KT2: consent çağrısı düşmüşse deneme jetonunu ilk cüzdan okuması
    # tamamlar (defterle idempotent — çift yükleme imkânsız).
    wallet.ensure_trial_tokens(user.uid)
    cuzdan = wallet.get_wallet(user.uid)
    resets_at = cuzdan.get("allowance_resets_at")
    return WalletStatus(
        allowance=cuzdan["allowance"],
        purchased=cuzdan["purchased"],
        total=cuzdan["allowance"] + cuzdan["purchased"],
        monthly_allowance=cuzdan["monthly_allowance"],
        allowance_resets_at=(resets_at.isoformat()
                             if hasattr(resets_at, "isoformat") else None),
        costs=cuzdan["costs"],
    )


class RedeemCodeRequest(BaseModel):
    code: str = Field(min_length=2, max_length=32)


@router.post("/redeem-code")
def redeem_code(req: RedeemCodeRequest,
                user: AuthUser = Depends(get_current_user),
                lang: str = Depends(get_language)):
    """Ortak kodu kullanımı (W7): atıf + jeton bonusu.

    Her hesapta TEK kod geçer (attribution tek sefer); kod satın almadan
    ÖNCE girilmiş olmalı ki sonraki gelir ortağa atfedilsin.
    """
    from services import partner_service
    try:
        sonuc = partner_service.redeem(user.uid, req.code)
    except partner_service.RedeemError as e:
        anahtar = {"not_found": "promo.not_found",
                   "inactive": "promo.expired",
                   "expired": "promo.expired",
                   "exhausted": "promo.exhausted",
                   "already_redeemed": "promo.already_redeemed",
                   # Ortak kendi kodunu kendi hesabında kullanamaz (OP).
                   "self_referral": "promo.self_referral",
                   }.get(e.reason, "promo.invalid")
        raise HTTPException(status_code=e.status,
                            detail=text(anahtar, lang,
                                        fallback="promo.invalid"))
    return {"status": "ok", "bonusTokens": sonuc["bonusTokens"]}


def _verify_secret(authorization: str | None) -> None:
    """Webhook'un gercekten RevenueCat'ten geldigini dogrular."""
    if not config.REVENUECAT_WEBHOOK_SECRET:
        # Gizli anahtar tanimsizken ucu acik birakmak, herkesin kendine
        # abonelik yazabilmesi demek olurdu.
        logger.error("REVENUECAT_WEBHOOK_SECRET tanimsiz; webhook reddedildi.")
        raise HTTPException(status_code=503, detail="Webhook yapilandirilmamis.")

    if not authorization or not secrets.compare_digest(
        authorization, config.REVENUECAT_WEBHOOK_SECRET
    ):
        raise HTTPException(status_code=401, detail="Gecersiz webhook imzasi.")


def _ms_to_datetime(value: Any) -> dt.datetime | None:
    if value is None:
        return None
    try:
        return dt.datetime.fromtimestamp(int(value) / 1000, tz=dt.timezone.utc)
    except (TypeError, ValueError):
        return None


def _subscription_ref(client, uid: str):
    return (client.collection("users").document(uid)
            .collection("private").document("subscription"))


def _handle_transfer(client, event: dict[str, Any]) -> dict[str, Any]:
    """Aboneligi eski kimlik(ler)den yeni kimlige tasir.

    Olayin yukunde urun ve bitis tarihi gelmiyor, bu yuzden kayit eski
    dokumandan KOPYALANIR. Sifirdan "aktif" yazsaydik bitis tarihini
    kaybeder ve suresi gecmis bir aboneligi sonsuza kadar acik birakirdik.
    """
    kaynaklar = [u for u in (event.get("transferred_from") or []) if u]
    hedefler = [u for u in (event.get("transferred_to") or []) if u]

    if not hedefler:
        logger.warning("TRANSFER olayinda hedef kimlik yok; atlandi.")
        return {"status": "ignored", "event": _TRANSFER_EVENT}

    # Cüzdan devri ABONELİK kaydından ÖNCE ve ONDAN BAĞIMSIZ: satın alınmış
    # bakiye kullanıcının parasıdır ve abonelik olmadan da var olabilir (paket
    # almak için abonelik şart değil — bkz. core/wallet.py charge_metered). Bu
    # çağrı aşağıdaki "kaynak abonelik kaydi bulunamadi" erken çıkışının
    # ALTINDAYDI: yalnız kredi paketi almış bir kimlikten devirde parayla
    # alınmış bakiye eski kimlikte öksüz kalıyordu.
    # `event_id` ZORUNLU sayılmalı: devrin tekrar koruması artık kaynağın
    # sıfırlanmasına değil hedefteki `ledger/transfer-{id}` işaretine bağlı
    # (sıra tersine döndü — bkz. wallet.transfer_wallet). Kimlik geçmezsek
    # webhook tekrarı çift kredi verir. RevenueCat her olayda `id` yolluyor;
    # `_record_revenue_event` de aynı alanı idempotency için kullanıyor.
    wallet.transfer_wallet(client, kaynaklar, hedefler,
                           event_id=str(event.get("id") or "") or None)

    kayit: dict[str, Any] | None = None
    for kaynak in kaynaklar:
        anlik = _subscription_ref(client, kaynak).get()
        if anlik.exists and kayit is None:
            kayit = anlik.to_dict() or None
        # Erisim iki kimlikte birden acik kalmamali.
        _subscription_ref(client, kaynak).set(
            {"active": False, "lastEvent": _TRANSFER_EVENT,
             "updatedAt": dt.datetime.now(dt.timezone.utc)},
            merge=True,
        )

    if kayit is None:
        # Kaynak dokuman yoksa devredecek bir sey de yok. Uydurma bir kayit
        # yazmak, odemesi olmayan kullaniciya erisim vermek olurdu.
        logger.info("TRANSFER: kaynak abonelik kaydi bulunamadi.")
        return {"status": "ok", "event": _TRANSFER_EVENT, "active": False}

    kayit = {**kayit, "lastEvent": _TRANSFER_EVENT,
             "updatedAt": dt.datetime.now(dt.timezone.utc)}
    for hedef in hedefler:
        _subscription_ref(client, hedef).set(kayit)
        _mirror_plan(client, hedef, kayit)
        # Zaman çizelgesi (AD5): hedef başına ayrı doküman — TRANSFER'in
        # tek `event.id`'si var ama iki hedef aynı kaydı ezmemeli.
        _record_revenue_event(event, _TRANSFER_EVENT, hedef, monetary=False,
                              doc_id=f"{event.get('id')}-{hedef}")
    for kaynak in kaynaklar:
        _mirror_plan(client, kaynak, {"active": False})

    logger.info("Abonelik devredildi: %s -> %s aktif=%s",
                kaynaklar, hedefler, kayit.get("active"))
    return {"status": "ok", "event": _TRANSFER_EVENT,
            "active": bool(kayit.get("active"))}


def _plan_from(record: dict[str, Any] | None,
               now: dt.datetime | None = None) -> str:
    """Abonelik kaydından panel planı: `plus` | `trial` | `free` (AD5).

    `active` ve süresi geçmemiş (`expiresAt` yok ya da gelecekte) kayıt
    deneme dönemindeyse `trial`, değilse `plus`; gerisi `free`. Sunucu
    taraflı 3 günlük deneme (`createdAt`) BURAYA GİRMEZ — o "yeni"
    rozetidir, mağaza denemesi değil.
    """
    record = record or {}
    if not record.get("active"):
        return "free"
    expires_at = record.get("expiresAt")
    if expires_at is not None:
        try:
            simdi = now or dt.datetime.now(dt.timezone.utc)
            if expires_at.timestamp() < simdi.timestamp():
                return "free"
        except AttributeError:
            pass
    return "trial" if record.get("isTrial") is True else "plus"


def _mirror_plan(client, uid: str, record: dict[str, Any] | None) -> None:
    """`users/{uid}.{plan, planAt, planProduct}` aynası — best-effort.

    `update()` BİLEREK (`set(merge)` değil): doküman yoksa yazım düşer ve
    bu doğru — anonim RevenueCat kimlikleri (`$RCAnonymousID:…`) için
    hayalet `users` dokümanı üretilmemeli. Panelin plan süzgeci ve
    kohort tablosu bu alandan okur; abonelik gerçeği `private/subscription`.
    """
    try:
        client.collection("users").document(uid).update({
            "plan": _plan_from(record),
            "planAt": dt.datetime.now(dt.timezone.utc),
            "planProduct": (record or {}).get("productId"),
        })
    except Exception as exc:
        logger.info("Plan aynası yazılamadı (%s): %s", uid, exc)


def _bump_revenue_totals(client, uid: str, environment: str,
                         event_type: str, price: float) -> None:
    """`users/{uid}/private/revenueTotals.{ENV:{grossUsd, refundsUsd,
    events}}` — yalnız PARASAL olaylarda, Increment ile (AD5).

    Kullanıcı 360 "toplam gelir"i artık revenueEvents'i taramadan buradan
    okur. `grossUsd` satışların toplamı, `refundsUsd` iadelerin MUTLAK
    toplamı; net = gross − refunds. Backfill (`--totals`) MUTLAK yazar.
    """
    from google.cloud import firestore as gcf
    tutar = abs(float(price or 0))
    alanlar: dict[str, Any] = {"events": gcf.Increment(1)}
    if event_type == "REFUND":
        alanlar["refundsUsd"] = gcf.Increment(tutar)
    else:
        alanlar["grossUsd"] = gcf.Increment(tutar)
    (client.collection("users").document(uid)
     .collection("private").document("revenueTotals")
     ).set({environment: alanlar}, merge=True)


def _record_revenue_event(event: dict[str, Any], event_type: str,
                          uid: str, *, monetary: bool = True,
                          doc_id: str | None = None) -> None:
    """Olayi append-only gelir/abonelik defterine yazar (W3 → AD5).

    Abonelik dokumani ``set()`` ile ezildigi icin gecmis tutmuyor; para
    cinsinden gelirin TEK gercegi ``revenueEvents`` koleksiyonudur. Dokuman
    kimligi RevenueCat ``event.id`` — ayni olayin tekrari ayni dokumani ezer
    (ledger deseniyle ayni dogal idempotency, bkz. core/wallet.py).

    AD5: parasal OLMAYAN olaylar da (``monetary=False``, ``price=0``) aynı
    deftere girer — Kullanıcı 360 zaman çizelgesi ve churn sayımı
    buradan. ``environment`` her olayda; panel test alımlarını bununla
    ayırır. Parasal olay ayrıca ``private/revenueTotals``ı artırır.

    Yazim EN-IYI-CABA: gelir kaydi dusse bile abonelik/cuzdan islemeye devam
    eder — muhasebe kaydi ugruna kullanicinin erisimi kesilmez.
    """
    event_id = str(event.get("id") or "")
    if not event_id:
        logger.warning("Gelir olayinda event.id yok; deftere yazilmadi: %s",
                       event_type)
        return
    client = firestore_client.get_client()
    if client is None:
        logger.warning("Gelir defteri yazilamadi (Firestore yok): %s", event_id)
        return
    environment = _environment(event)
    try:
        # Ortak atfi (W7): kod kullanmis kullanicinin geliri ortagina islenir.
        # Kod sistemi kurulana kadar dokuman yoktur ve alan null kalir.
        partner_id = None
        attribution = (client.collection("users").document(uid)
                       .collection("private").document("attribution").get())
        if getattr(attribution, "exists", False):
            partner_id = (attribution.to_dict() or {}).get("partnerId")

        fiyat = event.get("price") if monetary else 0
        client.collection("revenueEvents").document(doc_id or event_id).set({
            "uid": uid,
            "eventType": event_type,
            "productId": event.get("product_id"),
            "store": event.get("store"),
            # `price` RevenueCat'in USD normalize degeri; satin alinan para
            # birimindeki ham deger ayrica tasinir. REFUND'da isaret HAM
            # birakilir — yorum panelin isi (eventType zaten ayirt ediyor).
            "price": fiyat,
            "priceInPurchasedCurrency": (
                event.get("price_in_purchased_currency") if monetary else 0),
            "currency": event.get("currency"),
            "countryCode": event.get("country_code"),
            "isTrial": str(event.get("period_type") or "").upper() == "TRIAL",
            "partnerId": partner_id,
            "at": (_ms_to_datetime(event.get("event_timestamp_ms"))
                   or dt.datetime.now(dt.timezone.utc)),
            "recordedAt": dt.datetime.now(dt.timezone.utc),
            # AD5 alanları.
            "environment": environment,
            "monetary": bool(monetary),
            "periodType": (str(event.get("period_type")).upper()
                           if event.get("period_type") else None),
            "cancelReason": event.get("cancel_reason"),
            "expirationAt": _ms_to_datetime(event.get("expiration_at_ms")),
        })
    except Exception as exc:
        logger.warning("Gelir defteri yazilamadi (%s): %s", event_id, exc)
        return
    if monetary:
        try:
            _bump_revenue_totals(client, uid, environment, event_type,
                                 float(event.get("price") or 0))
        except Exception as exc:
            logger.warning("Gelir toplamı yazılamadı (%s): %s", uid, exc)

    _ortaklik_hakedisi(client, uid, event, event_type, environment,
                       partner_id, monetary, event_id)


def _ortaklik_hakedisi(client, uid: str, event: dict[str, Any],
                       event_type: str, environment: str,
                       partner_id: Any, monetary: bool,
                       event_id: str) -> None:
    """Ortaklık hakedişini açar ya da iptal eder (OP-turu).

    Gelir defterinin SONUNDA çalışır ve hiçbir şey fırlatmaz: para zaten
    alındı, ortaklık ikincil bir defterdir ve onun hatası webhook'u
    düşürmemeli.

    Ödül kuralı — beşi birden gerekir:
      1. `PRODUCTION` — SANDBOX/test alımı ödül üretmez (canlıda 1756
         sahte olay var; süzülmezse ortağa sahte gelirden para ödenir).
      2. Olay türü `INITIAL_PURCHASE` ya da `TRIAL_CONVERTED`. Yenileme
         ödül vermez; jeton paketleri zaten yalnız
         `NON_RENEWING_PURCHASE` olarak geldiği için bu küme onları
         kendiliğinden dışarıda bırakır — ürün listesi gerekmiyor.
      3. `monetary` — parasal olay.
      4. `isTrial` DEĞİL. Bu ayrı bir koşul çünkü `period_type=TRIAL` olan
         bir `INITIAL_PURCHASE` hem `monetary=True` hem `isTrial=True`
         gelir; yani tek başına `monetary` para geçtiğini KANITLAMAZ.
      5. Kullanıcının bir ortağa atfı var.
    """
    from services import partner_service

    try:
        if event_type in partner_service.VOID_EVENT_TYPES:
            partner_service.void_qualification(client, uid, event_type)
            return
        if not partner_id:
            return
        if environment != "PRODUCTION" or not monetary:
            return
        if event_type not in partner_service.REWARD_EVENT_TYPES:
            return
        if str(event.get("period_type") or "").upper() == "TRIAL":
            return
        partner_service.open_qualification(
            client, uid, str(partner_id),
            event_id=event_id,
            product_id=event.get("product_id"),
            purchased_at=(_ms_to_datetime(event.get("event_timestamp_ms"))
                          or dt.datetime.now(dt.timezone.utc)),
        )
    except Exception as exc:
        logger.warning("Ortaklik hakedisi islenemedi (%s): %s", uid, exc)


@router.post("/revenuecat")
async def revenuecat_webhook(
    payload: dict[str, Any],
    authorization: str | None = Header(default=None),
):
    """RevenueCat abonelik olaylarini kullanicinin gizli kaydina yazar."""
    _verify_secret(authorization)

    event = payload.get("event") or {}
    event_type = str(event.get("type") or "").upper()
    uid = event.get("app_user_id")
    product_id = str(event.get("product_id") or "")

    # ---- TOKEN PAKETLERİ: abonelik borusundan ÖNCE ayrılır. ----
    #
    # Sıralama kritik ve iki doğrulanmış tuzağı kapatıyor:
    # 1. NON_RENEWING_PURCHASE "bilinen" kümede değildi — paket satışı
    #    sessizce yutulurdu.
    # 2. REFUND _DEACTIVATING_EVENTS içinde — paket iadesi aşağıdaki
    #    abonelik yazımına düşseydi kullanıcının AYRI ödediği ABONELİĞİNİ
    #    kapatırdı. Ürün kimliği paket listesindeyse abonelik dokümanına
    #    asla dokunulmaz.
    if product_id in wallet.TOKEN_PACKS:
        if not uid:
            raise HTTPException(status_code=400, detail="app_user_id eksik.")
        event_id = str(event.get("id") or "")
        if not event_id:
            # Kimliksiz olayda idempotency kurulamaz; RevenueCat yeniden
            # denesin diye 400 DEĞİL 500'e yakın davranmak yanlış — kimlik
            # yükün kalıcı özelliği, tekrar denemede de gelmez. Logla, geç.
            logger.warning("Paket olayında event.id yok; atlandı: %s", event_type)
            return {"status": "ignored", "event": event_type}
        if event_type == "NON_RENEWING_PURCHASE":
            wallet.credit_pack(uid, product_id, event_id)
            _record_revenue_event(event, event_type, uid)
            return {"status": "ok", "event": event_type, "pack": product_id}
        if event_type == "REFUND":
            wallet.debit_refund(uid, product_id, event_id)
            _record_revenue_event(event, event_type, uid)
            return {"status": "ok", "event": event_type, "pack": product_id}
        logger.info("Paket ürününde beklenmeyen olay: %s", event_type)
        return {"status": "ignored", "event": event_type}

    # KT2/K-4: TOKEN_PACKS dışı kimlikle gelen NON_RENEWING_PURCHASE,
    # "para alındı ama jeton yüklenmedi" demektir (Play Console'da ürün
    # kimliği bir harf sapmış olabilir). Eskiden yalnız INFO loguna düşüp
    # kayboluyordu; artık ERROR + kalıcı denetim izi — panelin Sistem
    # sekmesinde görünür, kullanıcı şikâyet etmeden yakalanır.
    if event_type == "NON_RENEWING_PURCHASE":
        logger.error("BİLİNMEYEN paket kimliği: %r (uid=%s) — para alındı, "
                     "jeton YÜKLENMEDİ. Play/RevenueCat ürün kimliğini "
                     "wallet.TOKEN_PACKS ile karşılaştır.", product_id, uid)
        try:
            client = firestore_client.get_client()
            if client is not None:
                client.collection("adminAudit").document().set({
                    "adminUid": "system", "adminEmail": "webhook",
                    "action": "billing.unknown_pack", "targetUid": uid,
                    "params": {"productId": product_id,
                               "eventId": str(event.get("id") or "")},
                    "at": dt.datetime.now(dt.timezone.utc)})
        except Exception:
            pass
        return {"status": "ignored", "event": event_type}

    bilinen = (_ACTIVATING_EVENTS | _DEACTIVATING_EVENTS
               | _CANCELLATION_EVENTS | {_TRANSFER_EVENT})
    # Bilmedigimiz olay tiplerinde mevcut durumu bozmadan onaylayip geciyoruz;
    # aksi halde RevenueCat tekrar tekrar denerdi.
    if event_type not in bilinen:
        logger.info("Islenmeyen RevenueCat olayi: %s", event_type)
        return {"status": "ignored", "event": event_type}

    # TRANSFER disindaki her olay tek bir kimlige yazilir. Bu kontrol Firestore
    # erisiminden ONCE yapilir: eksik kimlik istemci hatasidir (400), gecici
    # altyapi sorunu degil (500).
    if event_type != _TRANSFER_EVENT and not uid:
        raise HTTPException(status_code=400, detail="app_user_id eksik.")

    client = firestore_client.get_client()
    if client is None:
        # 500 donersek RevenueCat tekrar dener — gecici Firestore sorununda
        # istedigimiz davranis budur.
        raise HTTPException(status_code=500, detail="Firestore erisilemiyor.")

    if event_type == _TRANSFER_EVENT:
        return _handle_transfer(client, event)

    # KT2/K-4 ikizi: REFUND yalnız KAYITLI abonelik ürünüyle eşleşiyorsa
    # aboneliğe dokunabilir. Paket listesi dışında kalan yanlış bir ürün
    # kimliğinin iadesi, kullanıcının AYRI ödediği aboneliğini
    # söndürmemeli — gelir defterine negatif işlenir, abonelik durur.
    if event_type == "REFUND" and product_id:
        try:
            mevcut = _subscription_ref(client, uid).get()
            mevcut_urun = ((mevcut.to_dict() or {}).get("productId")
                           if getattr(mevcut, "exists", False) else None)
        except Exception:
            mevcut_urun = None
        if mevcut_urun and product_id != mevcut_urun:
            logger.error("REFUND ürünü %r kayıtlı abonelikle %r eşleşmiyor; "
                         "abonelik DOKUNULMADI (uid=%s).",
                         product_id, mevcut_urun, uid)
            _record_revenue_event(event, event_type, uid)
            return {"status": "ignored", "event": event_type,
                    "reason": "urun-eslesmiyor"}

    expires_at = _ms_to_datetime(event.get("expiration_at_ms"))
    active = event_type in (_ACTIVATING_EVENTS | _CANCELLATION_EVENTS)

    record = {
        "active": active,
        "productId": event.get("product_id"),
        "expiresAt": expires_at,
        "willRenew": event_type not in _CANCELLATION_EVENTS,
        "isTrial": str(event.get("period_type") or "").upper() == "TRIAL",
        "lastEvent": event_type,
        "store": event.get("store"),
        "updatedAt": dt.datetime.now(dt.timezone.utc),
    }

    _subscription_ref(client, uid).set(record)
    _mirror_plan(client, uid, record)

    # Parasal abonelik olaylari gelir defterine de islenir (W3); parasal
    # olmayanlar zaman çizelgesi için price=0 ile (AD5).
    if event_type in _REVENUE_EVENTS:
        _record_revenue_event(event, event_type, uid, monetary=True)
    elif event_type in _NON_MONETARY_EVENTS:
        _record_revenue_event(event, event_type, uid, monetary=False)

    # Yeni/yenilenen donem aylik token hakkini tazeler. Idempotent: ayni
    # donemin tekrarlanan webhook'u hakki iki kez veremez (isaret esitligi).
    #
    # K2 yedegi: webhook `expiration_at_ms` tasimadan gelirse eskiden
    # reset_allowance HIC yazmiyordu ve ilk alimda bakiye 0 gorunuyordu
    # (ic test bulgusu). Aktive eden olayda son kullanma yoksa 35 gunluk
    # emniyet penceresi kullanilir — bir sonraki RENEWAL gercek tarihi
    # yazar; hak hicbir durumda verilmemis kalmaz.
    if event_type in _ACTIVATING_EVENTS:
        wallet.reset_allowance(
            uid,
            expires_at
            or dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=35))

    logger.info("Abonelik guncellendi: uid=%s olay=%s aktif=%s", uid, event_type, active)
    return {"status": "ok", "event": event_type, "active": active}

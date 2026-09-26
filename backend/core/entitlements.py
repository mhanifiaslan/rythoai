"""Yetki (entitlement) katmani — kim neye erisebilir, ucretsiz kotalar ne kadar.

Urunun birim ekonomisi buradan yonetilir. Temel kural:

**Ucretsiz katman kullanici sayisindan bagimsiz maliyetle calisir.** Ucretsiz
icerik (burc yorumu, gokyuzu) paylasimli onbellekten servis edilir; kullanici
basina LLM cagrisi gerektiren her sey ya aboneliğe ya da gunluk bir kotaya
baglidir. Aksi halde kullanici arttikca maliyet dogrusal buyur ve urun batar.

Abonelik durumu **yalnizca sunucu tarafindan** yazilir
(``users/{uid}/private/subscription``); istemcinin o yola yazma izni yoktur
(bkz. infra/firestore.rules). Kaynak su an RevenueCat webhook'udur ama katman
kaynaktan bagimsizdir: baska bir saglayiciya gecilirse yalnizca yazan taraf
degisir.

Kota sayaclari da Firestore'da tutulur. Bellek ici sayac Cloud Run'da
instance basina ayri olurdu ve kullanici instance degistirerek kotayi
sifirlayabilirdi.
"""
from __future__ import annotations

import datetime as dt
import logging
import os
from typing import Any

from fastapi import Depends, Header, HTTPException

from core import firestore as firestore_client
from core.auth import AuthUser, get_current_user
from core.i18n import DEFAULT as DEFAULT_LANG, get_language
from core.messages import text

logger = logging.getLogger(__name__)

#: Kilitli ozellik icin donen HTTP kodu. Istemci bunu gorunce paywall acar.
PAYWALL_STATUS = 402

#: Gelistirme/otomasyon icin tum ozellikleri acar. Uretimde ASLA 1 olmamali.
FORCE_PLUS: bool = os.getenv("RYTHO_FORCE_PLUS", "0") == "1"

# ---------------------------------------------------------------------------
# Ucretsiz katman kotalari
# ---------------------------------------------------------------------------

#: Ucretsiz kullanicinin gunluk sohbet mesaji hakki. Abonede sinirsizdir.
FREE_CHAT_PER_DAY = 5

#: I Ching "hafif gunluk ritual" olarak ucretsiz kalir ama gunde bir cekilis.
#: Sinirsiz olsa kullanici basina acik uclu LLM maliyeti olusurdu.
FREE_ICHING_PER_DAY = 1

#: Kilitli uclarda ve dolu kotalarda donen metinler artik core/messages.py'de,
#: dile gore tutuluyor: bu metinler istemcide dogrudan kullaniciya gosteriliyor
#: (bkz. friendlyError) ve Ingilizce kullanan biri Turkce paywall metni
#: gormemeli. Anahtarlar "paywall.<ozellik>" ve "quota.<anahtar>" bicimindedir.


def _private_doc(uid: str, name: str):
    client = firestore_client.get_client()
    if client is None:
        return None
    return client.collection("users").document(uid).collection("private").document(name)


# ---------------------------------------------------------------------------
# Abonelik durumu
# ---------------------------------------------------------------------------

def get_subscription(uid: str) -> dict[str, Any]:
    """Kullanicinin abonelik kaydi. Okunamazsa ucretsiz kabul edilir.

    Firestore erisilemedigi icin kullaniciya ucretli icerik ACMAYIZ; hata
    durumunda guvenli taraf ucretsizdir.
    """
    doc_ref = _private_doc(uid, "subscription")
    if doc_ref is None:
        return {"active": False, "reason": "firestore-yok"}
    try:
        snapshot = doc_ref.get()
    except Exception as exc:
        logger.warning("Abonelik okunamadi (%s): %s", uid, exc)
        return {"active": False, "reason": "okuma-hatasi"}

    if not snapshot.exists:
        return {"active": False}

    data = snapshot.to_dict() or {}
    expires_at = data.get("expiresAt")
    if expires_at is not None:
        try:
            if expires_at.timestamp() < dt.datetime.now(dt.timezone.utc).timestamp():
                # Webhook gecikmis olabilir; suresi gecmis kaydi aktif sayma.
                return {"active": False, "expired": True,
                        "productId": data.get("productId")}
        except AttributeError:
            pass

    return {
        "active": bool(data.get("active")),
        "productId": data.get("productId"),
        "expiresAt": expires_at,
        "willRenew": data.get("willRenew"),
        "isTrial": data.get("isTrial"),
    }


#: Yeni hesabın tüm Plus yüzeylerini kullandığı süre (OT6, kullanıcı
#: kararı: "ilk 3 günlük ücretsiz dönemdekiler tüm Plus özelliklerini
#: kullanabilsin" — kartsız, sunucu taraflı).
TRIAL_DAYS = 3

#: Profil okumasını kısa süre önbellekle (`_user_tz` deseni). Önbelleklenen
#: şey KARAR DEĞİL, kararın girdisi (`createdAt`) — aşağıdaki gerekçe.
_TRIAL_CACHE_TTL = 15 * 60

#: `createdAt` okunamadı / yok işareti. Önbellekte `None` "kayıt yok"
#: anlamına geldiği için ayrı bir sentinel gerekiyor.
_TRIAL_YOK = 0.0


def _created_at_ts(uid: str) -> float:
    """Profilin ``createdAt`` epoch değeri; yoksa/okunamazsa 0.

    ## Neden karar değil GİRDİ önbellekleniyor (KL-turu onarımı)

    Eskiden `in_trial`'ın **boolean sonucu** 15 dakika saklanıyordu. Deneme
    sınırı geçildiğinde önbellekte `True` kalan bir çağrı "abone" derken,
    önbelleği boş olan başka bir çağrı "değil" diyordu — aynı kullanıcı için
    aynı anda iki farklı yetki cevabı. Cihazda birebir görüldü: Profil
    ekranı "Rytho+" gösterirken `/api/v1/people` kontenjanı ücretsiz
    katmanın 1'i olarak döndürdü ("4/1 kişi").

    Cloud Run birden çok instance açtığında bellek içi önbellek instance
    başına ayrı olduğu için sapma dakikalarca sürebiliyor.

    `createdAt` **değişmeyen** bir olgudur; onu saklayıp kararı her çağrıda
    yeniden hesaplayınca bütün yollar aynı anda dönüyor. TTL artık yalnız
    "yeni yazılmış profili ne kadar sonra görürüz" sorusunu etkiliyor.
    """
    from core import cache  # tembel: core.cache -> core.* yonu karisik olmasin
    anahtar = f"user-created-{uid}"
    ts = cache.get(anahtar)
    if ts is None:
        ts = _TRIAL_YOK
        try:
            from services import profile_service
            olusturma = (profile_service.get_profile(uid) or {}).get(
                "createdAt")
            if olusturma is not None and hasattr(olusturma, "timestamp"):
                ts = float(olusturma.timestamp())
        except Exception as exc:
            logger.warning("Deneme durumu okunamadi (%s): %s", uid, exc)
        cache.set(anahtar, ts, ttl_seconds=_TRIAL_CACHE_TTL, owner_uid=uid)
    return float(ts)


def _trial_remaining(uid: str) -> float | None:
    """Denemenin bitmesine kalan saniye; denemede değilse None."""
    olusturma = _created_at_ts(uid)
    if not olusturma:
        # Alan yoksa deneme YOK — eski hesaplar ve alan yazılmadan kalmış
        # kayıtlar sessizce ücretsiz katmanda kalır ("okunamazsa ücretsiz").
        return None
    yas = dt.datetime.now(dt.timezone.utc).timestamp() - olusturma
    toplam = TRIAL_DAYS * 24 * 3600
    if not (0 <= yas < toplam):
        return None
    return toplam - yas


def in_trial(uid: str) -> bool:
    """Hesap ilk ``TRIAL_DAYS`` günü içinde mi? (OT6)"""
    return _trial_remaining(uid) is not None


def trial_days_left(uid: str) -> int | None:
    """Denemede kalan TAM gün (yukarı yuvarlanır, en az 1); denemede
    değilse None. Paywall'daki geri sayım buradan beslenir."""
    kalan = _trial_remaining(uid)
    if kalan is None:
        return None
    return max(1, -(-int(kalan) // (24 * 3600)))


def is_subscriber(uid: str) -> bool:
    if FORCE_PLUS:
        return True
    # OT6: deneme dönemi TÜM Plus kapılarını açar — require_plus dahil her
    # yol buradan geçtiği için tek noktadan uygulanır. Gerçek abonelik
    # önce denenir (daha ucuz: tek private doküman okuması, deneme kararı
    # ayrıca önbellekli).
    return bool(get_subscription(uid).get("active")) or in_trial(uid)


# ---------------------------------------------------------------------------
# Gunluk kotalar
# ---------------------------------------------------------------------------

#: Kullanicinin saat dilimi profilden gelir (cihaz yaziyor). Kota sicak bir
#: yol; her istekte profil okumamak icin kisa sureli onbelleklenir. Dilim
#: degisikligi en fazla bu kadar gecikmeyle yansir.
_TZ_CACHE_TTL = 15 * 60


def _user_tz(uid: str):
    """Kullanicinin saat dilimi; okunamazsa varsayilan (bildirimlerle ayni)."""
    from core import cache  # tembel: core.cache -> core.* yonu karisik olmasin
    anahtar = f"user-tz-{uid}"
    ad = cache.get(anahtar)
    if ad is None:
        # Tembel import: services -> core yonu zaten var, modul duzeyinde
        # geri bag dongusel import olurdu (device desenindeki gerekce).
        from services import notification_service, profile_service
        tz = notification_service.user_timezone(
            profile_service.get_profile(uid) or {})
        cache.set(anahtar, tz.key, ttl_seconds=_TZ_CACHE_TTL, owner_uid=uid)
        return tz
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
    try:
        return ZoneInfo(ad)
    except (ZoneInfoNotFoundError, ValueError):
        from services.notification_service import DEFAULT_TIMEZONE
        return ZoneInfo(DEFAULT_TIMEZONE)


def user_local_date(uid: str) -> dt.date:
    """Kullanicinin YEREL takvim gunu.

    Gun sinirinin tek kaynagi burasi: sunucu UTC'de calisiyor ve
    `dt.date.today()` her yerde sunucunun gununu veriyordu — Turkiye'de
    kullanicinin gunu saat 03:00'te donuyor, gece yarisindan sonra gunluk
    okuma dunku metni gosteriyordu. Saat dilimi profilden gelir ve kisa
    sureli onbelleklidir (bkz. `_user_tz`).
    """
    return dt.datetime.now(dt.timezone.utc).astimezone(_user_tz(uid)).date()


def _quota_window(tz) -> tuple[str, float]:
    """(yerel gun etiketi, pencerenin UTC epoch olarak kapanis ani).

    Gun sinirini SUNUCUNUN degil kullanicinin gunune baglar: Cloud Run
    UTC'de calisiyor ve Turkiye'de kullanicinin gunu saat 03:00'te
    donuyordu — gece yarisindan sonra kota hâlâ dunku sayaci tasiyordu.
    """
    simdi = dt.datetime.now(dt.timezone.utc)
    gun = simdi.astimezone(tz).date()
    kapanis = dt.datetime.combine(gun + dt.timedelta(days=1), dt.time.min,
                                  tzinfo=tz)
    return gun.isoformat(), kapanis.timestamp()


def _sayac_gecerli(data: dict[str, Any], gun: str, simdi_ts: float) -> bool:
    """Kayitli sayac hâlâ yururlukteki pencereye mi ait?

    Yerel gune gecmenin acacagi istismar kapisi burada kapaniyor: gun
    etiketi tek basina yeterli olsaydi kullanici cihazinin saat dilimini
    oynatarak gunde defalarca "yeni gun" tetikleyip ucretsiz kotayi
    sifirlayabilirdi. Bu yuzden sifirlama, kayitli pencerenin GERCEKTEN
    kapanmis olmasina bagli — dilim degisse de zaman geri alinamaz.

    ``resetAtUtc`` tasimayan eski kayitlar icin davranis eskisi gibi: gun
    etiketi degistiginde sifirlanir.
    """
    if data.get("date") == gun:
        return True
    return simdi_ts < float(data.get("resetAtUtc") or 0)


def quota_state(uid: str, key: str, limit: int, tz=None) -> tuple[int, int]:
    """(kullanilan, kalan) — sayaci artirmadan okur."""
    doc_ref = _private_doc(uid, "quota")
    if doc_ref is None:
        return 0, limit
    try:
        snapshot = doc_ref.get()
    except Exception:
        return 0, limit

    data = (snapshot.to_dict() or {}) if snapshot.exists else {}
    gun, _ = _quota_window(tz or _user_tz(uid))
    if not _sayac_gecerli(data, gun,
                          dt.datetime.now(dt.timezone.utc).timestamp()):
        return 0, limit
    used = int(data.get(key, 0))
    return used, max(limit - used, 0)


def consume_quota(uid: str, key: str, limit: int, tz=None) -> bool:
    """Kotadan bir hak duser. Hak kalmadiysa ``False`` doner ve dusmez.

    Sayaclar kullanicinin YEREL gunu dondugunde sifirlanir; belgedeki
    ``date`` etiketi o gunu, ``resetAtUtc`` ise pencerenin kapanis anini
    tutar (bkz. `_sayac_gecerli`).
    """
    doc_ref = _private_doc(uid, "quota")
    if doc_ref is None:
        # Firestore yoksa kotayi zorlayamayiz; istegi dusurmek yerine gecir.
        # Lokal gelistirmede bu normaldir, uretimde Firestore her zaman vardir.
        return True

    try:
        snapshot = doc_ref.get()
        data = (snapshot.to_dict() or {}) if snapshot.exists else {}
        gun, kapanis = _quota_window(tz or _user_tz(uid))
        if not _sayac_gecerli(data, gun,
                              dt.datetime.now(dt.timezone.utc).timestamp()):
            data = {"date": gun, "resetAtUtc": kapanis}

        used = int(data.get(key, 0))
        if used >= limit:
            return False

        data[key] = used + 1
        # Pencere alanlari SIFIRLAMA aninda yazilir, tuketimde degil: aksi
        # halde dilim oynatan kullanici pencereyi ileri kaydirabilirdi.
        doc_ref.set(data)
        return True
    except Exception as exc:
        logger.warning("Kota guncellenemedi (%s/%s): %s", uid, key, exc)
        return True


# ---------------------------------------------------------------------------
# FastAPI bagimliliklari
# ---------------------------------------------------------------------------

def require_plus(feature: str):
    """Aboneliğe bagli uclar icin bagimlilik uretir.

    Kullanim:  ``user: AuthUser = Depends(require_plus("natal_report"))``

    Tek cihaz kilidi de BURADAN uygulanir: aboneli her yol bu bagimliliktan
    geciyor — ayri bir dependency her uca tek tek eklenmek zorunda kalirdi
    ve biri unutulurdu. Kilit yalnizca UCRETLI abonede etkili (deneme muaf);
    o ayrimi ve "son giris kazanir" hakemini (auth_time) core.device yapar.
    """

    def dependency(user: AuthUser = Depends(get_current_user),
                   lang: str = Depends(get_language),
                   x_device_id: str | None = Header(default=None),
                   x_device_platform: str | None = Header(default=None),
                   ) -> AuthUser:
        if not is_subscriber(user.uid):
            raise HTTPException(
                status_code=PAYWALL_STATUS,
                detail=text(f"paywall.{feature}", lang,
                            fallback="paywall.default"),
            )
        # Tembel import: core.device -> core.entitlements yonu zaten var,
        # modul duzeyinde geri bag dongusel import olurdu.
        from core import device
        device.enforce_single_device(user.uid, x_device_id,
                                     auth_time=user.auth_time,
                                     platform=x_device_platform, lang=lang)
        return user

    return dependency


def enforce_daily_quota(user: AuthUser, key: str, limit: int,
                        lang: str = DEFAULT_LANG) -> None:
    """Ucretsiz kullanici icin gunluk kotayi uygular; abone sinirsizdir.

    Kota dolduysa paywall koduyla (402) hata firlatir. ``lang`` yalnizca
    kullaniciya donen metni belirler; kotanin kendisi dilden bagimsizdir.
    """
    if is_subscriber(user.uid):
        return
    if not consume_quota(user.uid, key, limit):
        raise HTTPException(
            status_code=PAYWALL_STATUS,
            detail=text(f"quota.{key}", lang, fallback="quota.default",
                        limit=limit),
        )

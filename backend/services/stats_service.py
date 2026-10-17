"""Admin istatistik toplayıcısı (W5 → AD7 rollup'lar).

SAATLİK `rytho-stats` Scheduler işi (`zamanlanmis_kosu`; ya da panelden
elle tetikleme) tüm sayımları BURADA yapar ve sonucu iki dokümana yazar:

* `adminStats/{YYYY-MM-DD}` — panelin okuduğu günlük özet. İki yarım:
  `_snapshot_users` (BUGÜNÜN kullanıcı/abonelik taraması: DAU, plan
  dağılımı, kohortlar, MRR) + `_day_events` (O GÜNÜN olayları: gelir
  ortam/ürün/mağaza/ülke kırılımı, olay sayıları, AI maliyeti, jeton
  akışı, bildirim koşuları). Geçmiş bir gün yeniden hesaplanırken
  (`snapshot=False`) yalnız olay bölümleri merge edilir — dünün DAU'su
  bugünkü taramadan üretilemez, uydurulmaz.
* `adminEconomics/{YYYY-MM-DD}` — kullanıcı başına gün ekonomisi
  (`{uid: {r, rs, c, n, t, p}}`, top-500 + `others`). Panelin ekonomi
  tablosu 90 günü bu dokümanlardan BİRLEŞTİRİR; canlı tarama yok.
  `p` ortak (affiliate) edinme maliyetidir ve dokümandaki TEK ₺ alandır:
  kur burada UYGULANMAZ, çünkü kuru okuyan tek yer `admin_service`
  (`_kur_oku`) ve ikinci bir kur yolu açmak aynı marjı iki ekranda iki
  farklı sayıya çevirirdi. Günün toplamı ayrıca `partnerTry` olarak
  yazılır; o alan aynı zamanda ÖLÇÜM İŞARETİdir — taşımayan gün (bu
  ölçümden eski rollup) "ortak maliyeti bilinmiyor"dur, "0" değil.

KRİTİK KURAL: abonelik sayımı HAM Firestore dokümanından yapılır —
`entitlements.is_subscriber` ASLA kullanılmaz. O fonksiyon RYTHO_FORCE_PLUS=1
(test dönemi) iken herkese True döner ve istatistiği zehirler.

Parasal toplamlar yalnız `monetary == True` olaylardan (alanı olmayan eski
kayıt parasal sayılır; `environment` yoksa SANDBOX — kapalı test öncesi
gerçek satış yok, backfill de aynı varsayımla etiketler).
"""
from __future__ import annotations

import datetime as dt
import logging
import threading
import time
from typing import Any

from core import app_gate, config, firestore as firestore_client

logger = logging.getLogger(__name__)

PAGE_SIZE = 500

#: Streak histogram kovaları — panel bu adlarla gösterir.
_STREAK_KOVALARI = ("0", "1-3", "4-7", "8+")

#: adminEconomics'te ad ad tutulan en fazla kullanıcı; gerisi `others`.
ECONOMICS_TOP_N = 500

#: Yeniden hesaplamanın tek seferde kabul ettiği en uzun aralık.
RECOMPUTE_MAX_DAYS = 90

#: Panelde takip edilen RevenueCat olay türleri — eventCounts anahtarları
#: hep bu sırayla ve tam listeyle döner (panel "0" ile "yok"u ayırmasın).
EVENT_TYPES = ("INITIAL_PURCHASE", "RENEWAL", "CANCELLATION", "EXPIRATION",
               "BILLING_ISSUE", "REFUND", "TRIAL_STARTED", "TRIAL_CONVERTED")

#: Ortam etiketleri; alanı olmayan eski olay SANDBOX sayılır.
ENVIRONMENTS = ("PRODUCTION", "SANDBOX")
_LEGACY_ENV = "SANDBOX"

#: Bildirim türleri — TEK KAYNAKTAN türetiliyor, elle sayılmıyor.
#:
#: Eskiden ("daily", "midday", "checkin", "streak") diye elle yazılıydı ve
#: aynı küme depoda ALTI yerde kopyalanmıştı. 48-turunda `RUN_TYPES`a
#: `circle` ve `winback` eklenince bu liste 4'te kaldı: yeni slotların
#: `notify.{tür}` rollup'ı HİÇ toplanmadı, yani iki yeni bildirim türü
#: panelde görünmez oldu. Tam da bu turun kendi dersi ("zamanlanmış işler
#: bir ay yeşil yalan söyledi") yeni slotlar için yarım kalıyordu.
#: İçe aktarma GECİKMELİ: `notify_runner` servis katmanının üstünde duruyor
#: ve modül düzeyinde almak döngüsel import üretir (bu dosya 739. satırda
#: `admin_service` için aynı kırıcıyı kullanıyor).
def _notify_turleri() -> tuple[str, ...]:
    from services.notify_runner import RUN_TYPES
    return tuple(RUN_TYPES)

#: Geçmiş gün merge'inde ezilen üst alanlar — kullanıcı taraması
#: (`users`, `subs`, …) DOKUNULMAZ.
_EVENT_SECTIONS = ("date", "eventsRecomputedAt", "revenue", "tokens", "ai",
                   "notify", "feedback")

_recompute_lock = threading.Lock()


def _streak_kovasi(deger: int) -> str:
    if deger <= 0:
        return "0"
    if deger <= 3:
        return "1-3"
    if deger <= 7:
        return "4-7"
    return "8+"


def _count(sorgu) -> int:
    """Firestore count() aggregation — dokümanları taşımadan sayar.

    Kitaplık/emülatör desteklemiyorsa -1 döner; panel "-" gösterir.
    Sayım uğruna toplama işi düşürülmez.
    """
    try:
        sonuc = sorgu.count().get()
        return int(sonuc[0][0].value)
    except Exception as exc:
        logger.warning("count() basarisiz: %s", exc)
        return -1


def _iter_users(client):
    """Tüm kullanıcı dokümanlarını sayfalayarak dolaşır (notify emsali).

    Filtre YOK: onboarding'i bitirmemiş kullanıcı da sayılmalı (dönüşüm
    oranının paydası). PAGE_SIZE'lık sayfalar bellek güvenliği sağlar.
    """
    son = None
    while True:
        sorgu = (client.collection("users")
                 .order_by("__name__")
                 .limit(PAGE_SIZE))
        if son is not None:
            sorgu = sorgu.start_after({"__name__": son})
        sayfa = list(sorgu.stream())
        if not sayfa:
            return
        for anlik in sayfa:
            veri = anlik.to_dict() or {}
            veri["uid"] = anlik.id
            yield veri
        son = sayfa[-1].id
        if len(sayfa) < PAGE_SIZE:
            return


def _gun_araligi(tarih: dt.date) -> tuple[dt.datetime, dt.datetime]:
    baslangic = dt.datetime.combine(tarih, dt.time.min, tzinfo=dt.timezone.utc)
    return baslangic, baslangic + dt.timedelta(days=1)


def _ts(value: Any) -> float:
    try:
        return value.timestamp()
    except AttributeError:
        return 0.0


def _ay(value: Any) -> str | None:
    """createdAt → 'YYYY-MM' (kohort anahtarı); damgasız kayıt kohortsuz."""
    if value is None or not hasattr(value, "strftime"):
        return None
    try:
        return value.strftime("%Y-%m")
    except Exception:
        return None


def _urun_mrr(product_id: str) -> float:
    """Ürünün aylık USD katkısı: yıllık ürün /12. Fiyat girilmediyse 0."""
    fiyat = float(config.SUBSCRIPTION_PRICES_USD.get(product_id, 0) or 0)
    if "yearly" in product_id or "annual" in product_id:
        return round(fiyat / 12, 4)
    return fiyat


def _artir(kova: dict[str, dict[str, Any]], anahtar: str,
           tutar: float) -> None:
    satir = kova.setdefault(anahtar, {"gross": 0.0, "count": 0})
    satir["gross"] = round(satir["gross"] + tutar, 4)
    satir["count"] += 1


# ---------------------------------------------------------------------------
# Bugünün taraması: kullanıcılar + abonelikler + hafif sayımlar
# ---------------------------------------------------------------------------

def _snapshot_users(client, tarih: dt.date,
                    simdi: dt.datetime) -> dict[str, Any]:
    """Kullanıcı ve abonelik durumunun BUGÜNKÜ fotoğrafı.

    Tek geçişte dağılımlar (dil, saat dilimi, platform, sürüm, plan,
    kohort); abonelikler HAM collection-group sorgusundan (MRR, deneme,
    3 gün içinde bitecek deneme); sosyal/sistem count() sayımları.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    tarih_str = tarih.isoformat()
    gun_bas, gun_son = _gun_araligi(tarih)

    toplam = onboarded = bugun_yeni = dau = push = 0
    rehber_acik = seri_gorunur = 0
    streak_kovalar = {k: 0 for k in _STREAK_KOVALARI}
    dil: dict[str, int] = {}
    saat_dilimi: dict[str, int] = {}
    platformlar: dict[str, int] = {}
    surumler: dict[str, int] = {}
    surum_bilinmiyor = 0
    planlar: dict[str, int] = {"free": 0, "trial": 0, "plus": 0}
    kohortlar: dict[str, dict[str, int]] = {}
    for veri in _iter_users(client):
        toplam += 1
        if veri.get("onboardingCompleted") is True:
            onboarded += 1
        olusturma = veri.get("createdAt")
        if olusturma is not None and hasattr(olusturma, "timestamp"):
            if gun_bas.timestamp() <= olusturma.timestamp() < gun_son.timestamp():
                bugun_yeni += 1
        if veri.get("lastSeenDaily") == tarih_str:
            dau += 1
        if veri.get("fcmToken"):
            push += 1
        if veri.get("contactMatch") is True:
            rehber_acik += 1
        if veri.get("streakVisible") is True:
            seri_gorunur += 1
        streak_kovalar[_streak_kovasi(
            int(veri.get("streakCount") or 0))] += 1
        d = str(veri.get("language") or "-")
        dil[d] = dil.get(d, 0) + 1
        tz = str(veri.get("timezone") or "-")
        saat_dilimi[tz] = saat_dilimi.get(tz, 0) + 1
        # Platform aynası (AP-turu, core/device._claim yazar); alanı
        # olmayan eski kullanıcılar dürüstçe "bilinmiyor".
        pf = str(veri.get("platform") or "bilinmiyor")
        platformlar[pf] = platformlar.get(pf, 0) + 1
        # Sürüm aynası (PBZ, core/auth.get_current_user yazar). Başlık
        # göndermeyen ≤34 istemciler alanı hiç taşımaz → "bilinmiyor";
        # panel bunu "eşiğin altında" sayısından AYRI gösterir.
        sb = app_gate.parse_build(veri.get("appBuild"))
        if sb > 0:
            surumler[str(sb)] = surumler.get(str(sb), 0) + 1
        else:
            surum_bilinmiyor += 1
        # Plan aynası (AD5, api/billing._mirror_plan yazar); alanı olmayan
        # kullanıcı ücretsizdir — backfill_search_fields tamamlar.
        plan = str(veri.get("plan") or "free")
        planlar[plan] = planlar.get(plan, 0) + 1
        # Kohort: kayıt ayı → kayıt sayısı + bugün Plus olan sayısı. Ödeme
        # dönüşümü (Plus/kayıt) panelde buradan; deneme ayrı sayılmaz.
        ay = _ay(olusturma)
        if ay:
            k = kohortlar.setdefault(ay, {"signups": 0, "plus": 0})
            k["signups"] += 1
            if plan == "plus":
                k["plus"] += 1

    # ---- Sürüm kırılımı: eşiğin altında kaç kişi (PBZ) ----
    # Ayrı count() sorgusu YOK — yukarıdaki tek geçişten türetilir.
    surum_blok: dict[str, Any] = {"byBuild": {}, "min": -1,
                                  "belowMin": -1, "unknown": -1}
    try:
        esik = app_gate.current_min_build()
        surum_blok = {
            "byBuild": surumler,
            "min": esik,
            "belowMin": sum(n for b, n in surumler.items()
                            if int(b) < esik) if esik > 0 else 0,
            "unknown": surum_bilinmiyor,
        }
    except Exception as exc:
        logger.warning("Sürüm kırılımı hesaplanamadı: %s", exc)

    # ---- Abonelikler: HAM collection-group sorgusu (is_subscriber YASAK) ----
    aktif = 0
    urun: dict[str, int] = {}
    magaza: dict[str, int] = {}
    deneme = 0
    iptal_ama_aktif = 0
    mrr = 0.0
    mrr_urun: dict[str, float] = {}
    deneme_bitiyor = 0
    uc_gun = simdi + dt.timedelta(days=3)
    try:
        abonelikler = (client.collection_group("private")
                       .where(filter=FieldFilter("active", "==", True))
                       .where(filter=FieldFilter("expiresAt", ">", simdi))
                       .stream())
        for anlik in abonelikler:
            veri = anlik.to_dict() or {}
            aktif += 1
            u = str(veri.get("productId") or "-")
            urun[u] = urun.get(u, 0) + 1
            m = str(veri.get("store") or "-")
            magaza[m] = magaza.get(m, 0) + 1
            if veri.get("willRenew") is False:
                iptal_ama_aktif += 1
            if veri.get("isTrial") is True:
                deneme += 1
                if _ts(veri.get("expiresAt")) < uc_gun.timestamp():
                    deneme_bitiyor += 1
                continue  # deneme MRR'a girmez: henüz para yok
            katki = _urun_mrr(u)
            mrr += katki
            mrr_urun[u] = round(mrr_urun.get(u, 0.0) + katki, 4)
    except Exception as exc:
        logger.warning("Abonelik sorgusu düştü (indeks?): %s", exc)
        aktif = -1

    # ---- Hafif sayımlar: count() aggregation ----
    arkadaslik = _count(
        client.collection_group("friends")
        .where(filter=FieldFilter("status", "==", "accepted")))
    if arkadaslik > 0:
        arkadaslik //= 2  # çift taraflı yazım — tek ilişki iki doküman
    sikayet = _count(client.collection("reports"))
    onbellek = _count(client.collection("aiCache"))
    konusma = _count(client.collection_group("conversations"))
    kullanici_adi = _count(client.collection("usernames"))

    return {
        "users": {
            "total": toplam,
            "onboarded": onboarded,
            "newToday": bugun_yeni,
            "dau": dau,
            "push": push,
            "contactMatchOn": rehber_acik,
            "streakVisibleOn": seri_gorunur,
            "usernames": kullanici_adi,
            "streakBuckets": streak_kovalar,
            "byLanguage": dil,
            "byTimezone": saat_dilimi,
            "byPlatform": platformlar,
            # AD7 ekleri.
            "byPlan": planlar,
        },
        "cohorts": kohortlar,
        "subs": {
            "active": aktif,
            "byProduct": urun,
            "byStore": magaza,
            "trial": deneme,
            "cancelledButActive": iptal_ama_aktif,
            # AD7 ekleri: MRR tahmini (config.SUBSCRIPTION_PRICES_USD).
            "trialing": deneme,
            "mrrUsd": round(mrr, 2),
            "mrrByProduct": mrr_urun,
            "trialExpiring3d": deneme_bitiyor,
        },
        "social": {
            "friendships": arkadaslik,
            "reportsOpen": sikayet,
        },
        "system": {
            "aiCacheCount": onbellek,
            "conversationsCount": konusma,
        },
        # PBZ: zorunlu güncelleme paneli. Eski dokümanlarda yok → "—".
        "builds": surum_blok,
    }


# ---------------------------------------------------------------------------
# O günün olayları: gelir + jeton + AI + bildirim (+ kullanıcı ekonomisi)
# ---------------------------------------------------------------------------

def _kullanici_kovasi(kovalar: dict[str, dict[str, Any]],
                      uid: str) -> dict[str, Any]:
    # `p` (ortak ödülü) ₺, ötekiler $ ya da adet. Birim karışımı bilinçli
    # ve modül başında yazılı; çeviren taraf `admin_service`.
    return kovalar.setdefault(uid, {"r": 0.0, "rs": 0.0, "c": 0.0,
                                    "n": 0, "t": 0, "p": 0.0})


def _day_events(client, tarih: dt.date,
                simdi: dt.datetime) -> tuple[dict[str, Any], dict[str, Any]]:
    """`tarih` gününün olay bölümleri + adminEconomics dokümanı.

    Döner: (`{"revenue","tokens","ai","notify"}`, `adminEconomics` dokümanı).
    Her kaynak kendi try'ında — indeksi kurulmamış bir sorgu diğerlerini
    düşürmez; düşen kaynak `-1`/boş ile dürüstçe işaretlenir.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    tarih_str = tarih.isoformat()
    gun_bas, gun_son = _gun_araligi(tarih)
    kullanicilar: dict[str, dict[str, Any]] = {}
    paylasimli = {"c": 0.0, "n": 0}

    # ---- Gelir: revenueEvents günlük filtre ----
    brut = 0.0
    para_birimi: dict[str, float] = {}
    paket_satis: dict[str, int] = {}
    iade = 0
    by_env: dict[str, dict[str, Any]] = {
        env: {"gross": 0.0, "refunds": 0.0, "count": 0, "byProduct": {},
              "byStore": {}, "byCountry": {},
              "eventCounts": {t: 0 for t in EVENT_TYPES}}
        for env in ENVIRONMENTS}
    by_product: dict[str, dict[str, Any]] = {}
    by_store: dict[str, dict[str, Any]] = {}
    by_country: dict[str, dict[str, Any]] = {}
    event_counts: dict[str, int] = {t: 0 for t in EVENT_TYPES}
    try:
        olaylar = (client.collection("revenueEvents")
                   .where(filter=FieldFilter("at", ">=", gun_bas))
                   .where(filter=FieldFilter("at", "<", gun_son))
                   .stream())
        for anlik in olaylar:
            veri = anlik.to_dict() or {}
            tur = str(veri.get("eventType") or "-")
            env = str(veri.get("environment") or _LEGACY_ENV).upper()
            if env not in by_env:
                by_env[env] = {"gross": 0.0, "refunds": 0.0, "count": 0,
                               "byProduct": {}, "byStore": {},
                               "byCountry": {},
                               "eventCounts": {t: 0 for t in EVENT_TYPES}}
            kova = by_env[env]
            kova["eventCounts"][tur] = kova["eventCounts"].get(tur, 0) + 1
            event_counts[tur] = event_counts.get(tur, 0) + 1

            # Parasal olmayan olay (CANCELLATION vb.) sayılır, toplanmaz.
            parasal = veri.get("monetary")
            if parasal is False:
                continue
            fiyat = float(veri.get("price") or 0)
            uid = str(veri.get("uid") or "")
            if tur == "REFUND":
                iade += 1
                brut -= abs(fiyat)
                kova["refunds"] = round(kova["refunds"] + abs(fiyat), 4)
                kova["count"] += 1
                if uid:
                    k = _kullanici_kovasi(kullanicilar, uid)
                    k["r" if env == "PRODUCTION" else "rs"] = round(
                        k["r" if env == "PRODUCTION" else "rs"]
                        - abs(fiyat), 4)
                continue
            brut += fiyat
            pb = str(veri.get("currency") or "-")
            ham = float(veri.get("priceInPurchasedCurrency") or 0)
            para_birimi[pb] = para_birimi.get(pb, 0.0) + ham
            u = str(veri.get("productId") or "-")
            if u.startswith("rytho_tokens_"):
                paket_satis[u] = paket_satis.get(u, 0) + 1
            kova["gross"] = round(kova["gross"] + fiyat, 4)
            kova["count"] += 1
            _artir(kova["byProduct"], u, fiyat)
            _artir(kova["byStore"], str(veri.get("store") or "-"), fiyat)
            _artir(kova["byCountry"], str(veri.get("countryCode") or "-"),
                   fiyat)
            _artir(by_product, u, fiyat)
            _artir(by_store, str(veri.get("store") or "-"), fiyat)
            _artir(by_country, str(veri.get("countryCode") or "-"), fiyat)
            if uid:
                k = _kullanici_kovasi(kullanicilar, uid)
                alan = "r" if env == "PRODUCTION" else "rs"
                k[alan] = round(k[alan] + fiyat, 4)
    except Exception as exc:
        logger.warning("Gelir sorgusu düştü: %s", exc)
        brut = -1.0

    # ---- Jeton akışı: cüzdan defterinin gün dilimi (AP-turu) ----
    # collection_group("ledger") fieldOverride indeksi ister (infra/
    # firestore.indexes.json); indeks henüz kurulmadıysa sorgu düşer ve
    # mevcut duruşla boş/None yazılır — toplama işi düşmez.
    jeton_harcanan: dict[str, int] = {}
    jeton_harcanan_toplam = -1
    jeton_kredi_toplam = -1
    try:
        harcanan_toplam = 0
        kredi_toplam = 0
        for anlik in (client.collection_group("ledger")
                      .where(filter=FieldFilter("at", ">=", gun_bas))
                      .where(filter=FieldFilter("at", "<", gun_son))
                      .stream()):
            veri = anlik.to_dict() or {}
            adet = int(veri.get("amount") or 0)
            if veri.get("type") == "debit":
                harcanan_toplam += adet
                oz = str(veri.get("feature") or "unknown")
                jeton_harcanan[oz] = jeton_harcanan.get(oz, 0) + adet
                # Yol: users/{uid}/private/wallet/ledger/{id}
                yol = getattr(getattr(anlik, "reference", None), "path", "")
                parcalar = str(yol).split("/")
                if len(parcalar) > 1 and parcalar[0] == "users":
                    _kullanici_kovasi(kullanicilar, parcalar[1])["t"] += adet
            elif veri.get("type") in ("credit", "promo", "admin"):
                kredi_toplam += adet
        jeton_harcanan_toplam = harcanan_toplam
        jeton_kredi_toplam = kredi_toplam
    except Exception as exc:
        logger.warning("Ledger sorgusu düştü (indeks?): %s", exc)

    # ---- AI kullanımı: usageEvents gün eşitliği (AP-turu) ----
    ai_cagri = -1
    ai_maliyet = -1.0
    ai_ozellik: dict[str, int] = {}
    maliyet_ozellik: dict[str, float] = {}
    token_ozellik: dict[str, dict[str, int]] = {}
    model_kirilim: dict[str, dict[str, Any]] = {}
    try:
        cagri = 0
        maliyet = 0.0
        for anlik in (client.collection("usageEvents")
                      .where(filter=FieldFilter("day", "==", tarih_str))
                      .stream()):
            veri = anlik.to_dict() or {}
            bedel = float(veri.get("estCostUsd") or 0)
            cagri += 1
            maliyet += bedel
            oz = str(veri.get("feature") or "unknown")
            ai_ozellik[oz] = ai_ozellik.get(oz, 0) + 1
            maliyet_ozellik[oz] = round(maliyet_ozellik.get(oz, 0.0) + bedel, 6)
            tk = token_ozellik.setdefault(oz, {"prompt": 0, "output": 0})
            tk["prompt"] += int(veri.get("promptTokens") or 0)
            tk["output"] += (int(veri.get("outputTokens") or 0)
                             + int(veri.get("thinkingTokens") or 0))
            md = str(veri.get("model") or "-")
            mk = model_kirilim.setdefault(md, {"calls": 0, "cost": 0.0})
            mk["calls"] += 1
            mk["cost"] = round(mk["cost"] + bedel, 6)
            uid = str(veri.get("uid") or "")
            if uid:
                k = _kullanici_kovasi(kullanicilar, uid)
                k["c"] = round(k["c"] + bedel, 6)
                k["n"] += 1
            else:
                paylasimli["c"] = round(paylasimli["c"] + bedel, 6)
                paylasimli["n"] += 1
        ai_cagri = cagri
        ai_maliyet = round(maliyet, 6)
    except Exception as exc:
        logger.warning("usageEvents sorgusu düştü: %s", exc)

    # ---- Ortak edinme maliyeti: O GÜN AÇILAN hakedişler (P4) ----
    # NEDEN `purchasedAt`: hakediş satın almayla doğar, yani bu maliyet
    # aynı günün gelir olayının karşılığıdır. `maturedAt` seçilse maliyet
    # gelirden 15 gün SONRAKİ güne düşerdi ve arada kalan her marj
    # penceresi yanlış çıkardı — hiçbir ekranda hata görünmeden.
    #
    # `void` SAYILMAZ, `pending` SAYILIR: `admin_service._ortak_maliyeti`
    # (Kullanıcı 360) ile birebir aynı kural. İki yüzey ayrışırsa aynı
    # kullanıcının marjı iki ekranda farklı çıkar ve hangisinin doğru
    # olduğunu söyleyecek hiçbir kanıt kalmaz.
    #
    # Durum süzgeci sorguda DEĞİL Python'da: `purchasedAt` aralığı +
    # `status` eşitliği bileşik indeks isterdi ve gün başına açılan
    # hakediş sayısı (o günün İLK abonelikleriyle sınırlı) bunu
    # gerektirmeyecek kadar küçük.
    #
    # ⚠️ BİLİNEN SINIR: durum TOPLAMA ÂNINDA fotoğraflanır. Satın alma
    # gününden sonra `void`a düşen bir hakediş (iade / pasifleşen ortak,
    # `mature_qualifications`) o günün yazılmış rollup'ında maliyet olarak
    # DURMAYA devam eder; düzeltmesi sahibin "Yeniden hesapla"sıdır.
    # Sapma tek yönlü ve bilinçli: maliyet fazla, yani marj OLDUĞUNDAN
    # DÜŞÜK görünür. Ters yön (marjı yüksek göstermek) kabul edilemezdi —
    # fiyat kararı o sayıyla veriliyor. Kullanıcı 360 canlı okuduğu için
    # her zaman günceldir; iki ekran bu noktada AYRILIR ve doğrusu 360'tır.
    # Sorgu nasıl yazılırsa yazılsın çözülmez: rollup geçmiş bir günü
    # yazıyor, sonradan olanı ancak yeniden toplamak görür.
    ortak_try = -1.0
    try:
        gunun_odulu: dict[str, float] = {}
        for anlik in (client.collection("partnerQualifications")
                      .where(filter=FieldFilter("purchasedAt", ">=", gun_bas))
                      .where(filter=FieldFilter("purchasedAt", "<", gun_son))
                      .stream()):
            veri = anlik.to_dict() or {}
            if str(veri.get("status") or "pending") == "void":
                continue
            # Çözümlenemeyen tutar (ör. elle yazılmış "30,00" dizesi)
            # ValueError atar ve BLOĞU düşürür: günün toplamı −1
            # ("bilinmiyor") olur. Satırı atlayıp devam etmek, ölçülmemiş
            # bir eksiği "maliyet yok" diye yazmak olurdu.
            odul = float(veri.get("rewardTry") or 0)
            if odul > 0:
                # Doküman kimliği uid (partner_service'in yapısal "kullanıcı
                # başına tek ödül" garantisi), yine de toplanarak yazılıyor:
                # garanti kırılırsa sayı eksilmesin.
                gunun_odulu[anlik.id] = round(
                    gunun_odulu.get(anlik.id, 0.0) + odul, 4)
        # Kullanıcı kovalarına ancak TAM okunmuş gün işlenir: yarı işlenmiş
        # bir gün, doküman `partnerTry: -1` ("bilinmiyor") derken satırlarda
        # tutar taşırdı ve okuyan taraf hangisine güveneceğini bilemezdi.
        for hak_uid, odul in gunun_odulu.items():
            kova = _kullanici_kovasi(kullanicilar, hak_uid)
            kova["p"] = round(kova["p"] + odul, 4)
        ortak_try = round(sum(gunun_odulu.values()), 4)
    except Exception as exc:
        logger.warning("partnerQualifications sorgusu düştü: %s", exc)

    # ---- Bildirim koşuları: notifyRuns {gün}-{tür} (AP-turu) ----
    bildirim: dict[str, Any] = {}
    try:
        for tur in _notify_turleri():
            anlik = (client.collection("notifyRuns")
                     .document(f"{tarih_str}-{tur}").get())
            if getattr(anlik, "exists", False):
                veri = anlik.to_dict() or {}
                bildirim[tur] = {
                    "sent": int(veri.get("sent") or 0),
                    "failed": int(veri.get("failed") or 0),
                    "skippedTotal": sum(
                        int(v or 0)
                        for v in (veri.get("skipped") or {}).values()),
                    # AD7: dil dağılımı + budanan ölü jeton.
                    "languages": {str(k): int(v or 0) for k, v in
                                  (veri.get("languages") or {}).items()},
                    "pruned": int(veri.get("pruned") or 0),
                }
    except Exception as exc:
        logger.warning("notifyRuns okunamadı: %s", exc)

    # ---- Geri bildirim (GB-turu): o gün yazılan kayıt, türe göre ----
    geri_bildirim: dict[str, Any] = {"new": 0, "byType": {}}
    try:
        for anlik in (client.collection("feedback")
                      .where(filter=FieldFilter("createdAt", ">=", gun_bas))
                      .where(filter=FieldFilter("createdAt", "<", gun_son))
                      .stream()):
            veri = anlik.to_dict() or {}
            tur = str(veri.get("type") or "other")
            geri_bildirim["new"] += 1
            geri_bildirim["byType"][tur] = (
                geri_bildirim["byType"].get(tur, 0) + 1)
    except Exception as exc:
        logger.warning("feedback sorgusu düştü: %s", exc)

    bolumler = {
        "revenue": {
            "grossToday": round(brut, 2),
            "byCurrency": {k: round(v, 2) for k, v in para_birimi.items()},
            "packSalesToday": paket_satis,
            "refundsToday": iade,
            # AD7: ortam ayrımı + kırılımlar. Üst düzey kırılımlar TÜM
            # ortamların toplamı; ortam başına olanlar `byEnv` içinde.
            "byEnv": by_env,
            "byProduct": by_product,
            "byStore": by_store,
            "byCountry": by_country,
            "eventCounts": event_counts,
        },
        "tokens": {
            "spentToday": jeton_harcanan,
            "spentTotalToday": jeton_harcanan_toplam,
            "creditedToday": jeton_kredi_toplam,
        },
        "ai": {
            "callsToday": ai_cagri,
            "estCostToday": ai_maliyet,
            "byFeature": ai_ozellik,
            # AD7 ekleri.
            "costByFeature": maliyet_ozellik,
            "tokensByFeature": token_ozellik,
            "byModel": model_kirilim,
        },
        "notify": bildirim,
        "feedback": geri_bildirim,
    }

    # ---- adminEconomics: top-N kullanıcı + gerisi tek kovada ----
    # Sıralama anahtarına `p` GİRMEZ: o ₺, ötekiler $ — toplamak ₺30'luk
    # bir ödülü $30'lık bir gelirmiş gibi tartar ve top-N seçimini bozar.
    # Kayıp da yok: hakediş ancak satın almayla doğduğu için ödülü olan
    # kullanıcının aynı gün `r`/`rs`si de var, yani zaten üst sıralarda.
    sirali = sorted(kullanicilar.items(),
                    key=lambda kv: kv[1]["r"] + kv[1]["rs"] + kv[1]["c"],
                    reverse=True)
    ustler = dict(sirali[:ECONOMICS_TOP_N])
    digerleri = {"r": 0.0, "rs": 0.0, "c": 0.0, "n": 0, "t": 0, "p": 0.0}
    for _, k in sirali[ECONOMICS_TOP_N:]:
        for alan in digerleri:
            digerleri[alan] = round(digerleri[alan] + k[alan], 6)
    ekonomi = {
        "date": tarih_str,
        "generatedAt": simdi,
        "users": ustler,
        "others": digerleri,
        "shared": paylasimli,
        # Günün TOPLAM ortak maliyeti (₺) — top-N dışı kullanıcılar dahil.
        # Okuyan taraf pencere toplamını satırları toplayarak DEĞİL buradan
        # alıyor, çünkü bu alanın yokluğu aynı zamanda "bu gün ölçülmedi"
        # demek ve `others.p` o ayrımı taşıyamaz (0 hem "yok" hem
        # "ölçülmedi" okunurdu).
        "partnerTry": ortak_try,
        "count": len(kullanicilar),
    }
    return bolumler, ekonomi


# ---------------------------------------------------------------------------
# Toplama + yeniden hesaplama
# ---------------------------------------------------------------------------

def collect(tarih: dt.date | None = None, *,
            snapshot: bool = True) -> dict[str, Any]:
    """Günün istatistiklerini toplar; `adminStats/{tarih}` ve
    `adminEconomics/{tarih}` dokümanlarını yazar.

    `snapshot=True` (bugün): tam doküman ezilir — idempotent, birikmez.
    `snapshot=False` (geçmiş gün): yalnız olay bölümleri (`revenue`,
    `tokens`, `ai`, `notify`) merge edilir; o günün DAU/plan fotoğrafı
    varsa korunur, yoksa uydurulmaz. Dönen sözlük yazılanın aynısıdır.
    """
    client = firestore_client.get_client()
    if client is None:
        raise RuntimeError("Firestore erişilemiyor; istatistik toplanamadı.")

    tarih = tarih or dt.datetime.now(dt.timezone.utc).date()
    tarih_str = tarih.isoformat()
    baslangic = time.monotonic()
    simdi = dt.datetime.now(dt.timezone.utc)

    bolumler, ekonomi = _day_events(client, tarih, simdi)

    if snapshot:
        dokuman: dict[str, Any] = {"date": tarih_str, "generatedAt": simdi}
        dokuman.update(_snapshot_users(client, tarih, simdi))
        dokuman.update(bolumler)
        dokuman["durationMs"] = int((time.monotonic() - baslangic) * 1000)
        client.collection("adminStats").document(tarih_str).set(dokuman)
        logger.info("adminStats/%s yazıldı (%d kullanıcı, %d ms)",
                    tarih_str, dokuman["users"]["total"],
                    dokuman["durationMs"])
    else:
        dokuman = {"date": tarih_str, "eventsRecomputedAt": simdi}
        dokuman.update(bolumler)
        client.collection("adminStats").document(tarih_str).set(
            dokuman, merge=list(_EVENT_SECTIONS))
        logger.info("adminStats/%s olay bölümleri yeniden yazıldı", tarih_str)

    client.collection("adminEconomics").document(tarih_str).set(ekonomi)
    return dokuman


def recompute(start_date: dt.date, end_date: dt.date) -> dict[str, Any]:
    """Aralıktaki her günü yeniden toplar (sahip tetikler, AD7).

    Tek koşu kilidi: eşzamanlı ikinci istek `RuntimeError("busy")` (uç
    409'a çevirir). En fazla `RECOMPUTE_MAX_DAYS` gün (`ValueError`).
    Bugün tam fotoğraf (`snapshot=True`), geçmiş günler yalnız olaylar.
    Gelecek günler atlanır. Bitince ekonomi önbelleği temizlenir ki panel
    eski birleşimi 10 dakika daha göstermesin.
    """
    if end_date < start_date:
        raise ValueError("Bitiş tarihi başlangıçtan önce olamaz.")
    gun_sayisi = (end_date - start_date).days + 1
    if gun_sayisi > RECOMPUTE_MAX_DAYS:
        raise ValueError(f"En fazla {RECOMPUTE_MAX_DAYS} gün.")
    if not _recompute_lock.acquire(blocking=False):
        raise RuntimeError("busy")
    try:
        bugun = dt.datetime.now(dt.timezone.utc).date()
        gunler: list[str] = []
        for i in range(gun_sayisi):
            gun = start_date + dt.timedelta(days=i)
            if gun > bugun:
                break
            collect(gun, snapshot=(gun == bugun))
            gunler.append(gun.isoformat())
        from services import admin_service  # döngüsel import kırıcı
        admin_service.clear_economics_cache()
        return {"days": len(gunler), "from": start_date.isoformat(),
                "to": end_date.isoformat(), "recomputed": gunler}
    finally:
        _recompute_lock.release()


def zamanlanmis_kosu(simdi: dt.datetime | None = None) -> dict[str, Any]:
    """Scheduler'ın SAATLİK koşusu: bugünün tam dokümanı + gerekirse dünün
    olay kapanışı.

    İş eskiden gecede BİR kez (23:40 UTC) koşuyordu ve iki kusuru vardı
    (ölçüldü 2026-10-17): (1) bugünün geliri panelde HİÇ görünmüyordu —
    ertesi gece 23:40'a kadar; sahip görmek için "Yeniden hesapla"ya tarih
    girip basmak zorundaydı. (2) 23:40–24:00 arasındaki olaylar o günün
    dokümanına HİÇ girmiyordu; kimse elle yeniden hesaplamazsa kalıcı kayıp.

    Saatlik koşu (1)'i kapatır — panel yine yalnız rollup okur (AD7: panel
    okuması tarama yapmaz), yalnız rollup en çok bir saat bayat. (2)'yi
    "dün, gün BİTTİKTEN SONRA hiç toplanmadıysa olaylarını yeniden topla"
    kuralı kapatır. Kural saate ("gece yarısından sonraki ilk koşu") değil
    DAMGAYA bağlı: o koşu düşerse bir sonraki koşu yine kapatır.
    """
    simdi = simdi or dt.datetime.now(dt.timezone.utc)
    bugun = simdi.date()
    dun = bugun - dt.timedelta(days=1)
    dokuman = collect(bugun)

    # Dünün kapanışı BEST-EFFORT: okunamazsa bugünün yazılmış dokümanı
    # bunun yüzünden 500'e dönmez; kural damgaya bağlı olduğu için bir
    # sonraki koşu kapanışı yine dener.
    gun_sonu = dt.datetime.combine(bugun, dt.time.min, tzinfo=dt.timezone.utc)
    kapandi = True
    try:
        client = firestore_client.get_client()
        if client is not None:
            anlik = client.collection("adminStats").document(
                dun.isoformat()).get()
            eski = ((anlik.to_dict() or {})
                    if getattr(anlik, "exists", False) else {})
            damgalar = [eski.get("generatedAt"), eski.get("eventsRecomputedAt")]
            kapandi = any(d is not None and _ts(d) >= gun_sonu.timestamp()
                          for d in damgalar)
            if not kapandi:
                collect(dun, snapshot=False)
    except Exception as exc:
        logger.warning("adminStats/%s kapanışı ertelendi: %s", dun, exc)
        kapandi = True
    return {"date": dokuman["date"], "durationMs": dokuman["durationMs"],
            "closedDay": None if kapandi else dun.isoformat()}


def read_days(days: int) -> list[dict[str, Any]]:
    """Son N TAKVİM gününün hazır istatistik dokümanları (yeniden eskiye).

    Pencere takvimdir, doküman sayısı DEĞİL: eskiden `limit(N)` "son N
    doküman" dönüyordu ve rollup'ın atladığı her gün "30 gün" penceresini
    sessizce geriye uzatıyordu (panel 30 gün derken 40 günü topluyordu).
    Eksik gün artık eksik görünür.

    Sıralama `date` ALANINA göre — doküman kimliğiyle aynı değer ama
    `__name__` üzerinden azalan sıralama otomatik indekslenmiyor
    (üretimde 400 FailedPrecondition olarak ölçüldü, AP2); tek-alan
    otomatik indeks ise her iki yönü de kapsar.
    """
    client = firestore_client.get_client()
    if client is None:
        return []
    from google.cloud.firestore_v1.base_query import FieldFilter

    bugun = dt.datetime.now(dt.timezone.utc).date()
    alt = (bugun - dt.timedelta(days=max(1, min(days, 365)) - 1)).isoformat()
    sorgu = (client.collection("adminStats")
             .where(filter=FieldFilter("date", ">=", alt))
             .order_by("date", direction="DESCENDING"))
    return [anlik.to_dict() or {} for anlik in sorgu.stream()]


def son_dokuman() -> dict[str, Any] | None:
    """Tarihi ne olursa olsun EN SON rollup dokümanı — bayatlık ölçümü için.

    `read_days` takvim penceresine geçince "7 günde hiç doküman yoksa en
    sonuncusu ne zaman?" sorusunu artık cevaplamıyor; o soru buraya taşındı.
    """
    client = firestore_client.get_client()
    if client is None:
        return None
    sorgu = (client.collection("adminStats")
             .order_by("date", direction="DESCENDING").limit(1))
    for anlik in sorgu.stream():
        return anlik.to_dict() or {}
    return None

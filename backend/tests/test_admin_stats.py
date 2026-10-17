"""Admin istatistikleri (W5 → AD7): toplama mantığı + uç kapıları.

Değişmezler:
- Abonelik sayımı HAM dokümandan: RYTHO_FORCE_PLUS=1 sayımı DEĞİŞTİRMEZ.
- collect idempotent: çift çalıştırma aynı dokümanı ezer, birikmez.
- AD7: gelir ortam/monetary ayrımı, olay sayıları, adminEconomics top-N +
  others, geçmiş gün `snapshot=False` yalnız olay bölümlerini merge eder,
  MRR fiyat tablosundan, recompute kilitli ve ≤90 gün.
- /stats ve /live yalnız admin claim ile; /collect scheduler sırrıyla da.
"""
from __future__ import annotations

import datetime as dt

import pytest
from fastapi.testclient import TestClient

from _sahte_firestore import SahteFirestore
from core import config
from services import stats_service

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover - ortama bagli
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulamasi ice aktarilamadi: {_APP_IMPORT_ERROR}",
)

_SIMDI = dt.datetime.now(dt.timezone.utc)
_BUGUN = _SIMDI.date().isoformat()


def _ornek_veri() -> dict[str, dict]:
    return {
        "users/u1": {"onboardingCompleted": True, "createdAt": _SIMDI,
                     "lastSeenDaily": _BUGUN, "streakCount": 5,
                     "language": "tr", "fcmToken": "t", "plan": "plus"},
        "users/u2": {"onboardingCompleted": True, "streakCount": 0,
                     "language": "en",
                     "createdAt": _SIMDI - dt.timedelta(days=40)},
        "users/u3": {"streakCount": 12, "language": "tr"},  # onboarded değil
        # collection_group("private"): yalnız subscription dokümanları
        # `active` taşır; wallet eşleşmez.
        "users/u1/private/subscription": {
            "active": True, "expiresAt": _SIMDI + dt.timedelta(days=10),
            "productId": "rytho_plus_monthly", "store": "PLAY_STORE",
            "isTrial": True, "willRenew": False},
        "users/u2/private/subscription": {
            "active": False, "expiresAt": _SIMDI + dt.timedelta(days=5)},
        "users/u3/private/subscription": {
            "active": True, "expiresAt": _SIMDI - dt.timedelta(days=1)},
        "users/u1/private/wallet": {"allowance": 100},
        "revenueEvents/e1": {"uid": "u1", "eventType": "INITIAL_PURCHASE",
                             "price": 4.99, "currency": "TRY",
                             "priceInPurchasedCurrency": 169.99,
                             "productId": "rytho_plus_monthly", "at": _SIMDI},
        "revenueEvents/e2": {"uid": "u2", "eventType": "NON_RENEWING_PURCHASE",
                             "price": 1.99, "currency": "USD",
                             "priceInPurchasedCurrency": 1.99,
                             "productId": "rytho_tokens_small", "at": _SIMDI},
        "revenueEvents/e3": {"uid": "u2", "eventType": "REFUND", "price": 1.99,
                             "currency": "USD",
                             "productId": "rytho_tokens_small", "at": _SIMDI},
        "users/a/friends/f1": {"status": "accepted"},
        "users/b/friends/f2": {"status": "accepted"},
        "users/b/friends/f3": {"status": "incoming"},
        "aiCache/c1": {}, "users/a/conversations/k1": {}, "usernames/ad1": {},
    }


@pytest.fixture()
def sahte(monkeypatch):
    depo = SahteFirestore(_ornek_veri())
    monkeypatch.setattr(
        "services.stats_service.firestore_client.get_client", lambda: depo)
    # Eşik memo'su süreç içi (PBZ): önceki testin değeri sızmasın.
    from core import app_gate
    app_gate.reset_memo()
    yield depo
    app_gate.reset_memo()


def _stats(depo, gun=_BUGUN):
    return depo.docs[f"adminStats/{gun}"]


def test_toplama_sayilari(sahte, monkeypatch):
    # FORCE_PLUS istatistiği ZEHİRLEYEMEZ: toplayıcı ham dokümana bakar.
    monkeypatch.setattr("core.entitlements.FORCE_PLUS", True)
    d = stats_service.collect()

    assert d["users"]["total"] == 3
    assert d["users"]["onboarded"] == 2
    assert d["users"]["newToday"] == 1
    assert d["users"]["dau"] == 1
    assert d["users"]["streakBuckets"] == {"0": 1, "1-3": 0, "4-7": 1, "8+": 1}
    assert d["users"]["byLanguage"] == {"tr": 2, "en": 1}
    # Aktif abone 1: pasif ve süresi geçmiş olanlar ile wallet dokümanı
    # (active alanı yok) SAYILMAZ — FORCE_PLUS açıkken bile.
    assert d["subs"]["active"] == 1
    assert d["subs"]["trial"] == 1
    assert d["subs"]["cancelledButActive"] == 1
    # Gelir (eski alanlar korunur): 4.99 + 1.99 - 1.99 (iade)
    assert d["revenue"]["grossToday"] == pytest.approx(4.99)
    assert d["revenue"]["packSalesToday"] == {"rytho_tokens_small": 1}
    assert d["revenue"]["refundsToday"] == 1
    assert d["social"]["friendships"] == 1  # 2 doküman / 2
    assert _stats(sahte) == d


def test_toplama_ap_ekleri(sahte, monkeypatch):
    """AP-turu: jeton akışı (debit ledger), AI kullanımı (usageEvents),
    bildirim koşuları (notifyRuns) ve platform kırılımı dokümana girer;
    AD7 kırılımları (maliyet/token/model, bildirim dilleri) yanına."""
    sahte.docs.update({
        "users/u1/private/wallet/ledger/l1": {"type": "debit", "feature": "chat",
                                              "amount": 1, "at": _SIMDI},
        "users/u1/private/wallet/ledger/l2": {"type": "debit", "feature": "natal",
                                              "amount": 5, "at": _SIMDI},
        "users/u2/private/wallet/ledger/l3": {"type": "credit",
                                              "productId": "rytho_tokens_small",
                                              "amount": 100, "at": _SIMDI},
        # Dün kalan kayıt gün dilimine GİRMEZ.
        "users/u1/private/wallet/ledger/l0": {"type": "debit", "feature": "chat",
                                              "amount": 9,
                                              "at": _SIMDI - dt.timedelta(days=2)},
        "usageEvents/x1": {"day": _BUGUN, "feature": "chat", "estCostUsd": 0.002,
                           "uid": "u1", "model": "m1", "promptTokens": 100,
                           "outputTokens": 20, "thinkingTokens": 5},
        "usageEvents/x2": {"day": _BUGUN, "feature": "natal",
                           "estCostUsd": 0.0033, "uid": None, "model": "m2",
                           "promptTokens": 900, "outputTokens": 300},
        "usageEvents/x3": {"day": "2020-01-01", "feature": "chat",
                           "estCostUsd": 9.9},  # başka gün — girmez
        f"notifyRuns/{_BUGUN}-daily": {"sent": 4, "failed": 1, "pruned": 2,
                                       "languages": {"tr": 3, "en": 1},
                                       "skipped": {"sessiz-saat": 2,
                                                   "tercih": 1}},
    })

    d = stats_service.collect()

    assert d["tokens"]["spentToday"] == {"chat": 1, "natal": 5}
    assert d["tokens"]["spentTotalToday"] == 6
    assert d["tokens"]["creditedToday"] == 100
    assert d["ai"]["callsToday"] == 2
    assert d["ai"]["estCostToday"] == pytest.approx(0.0053)
    assert d["ai"]["byFeature"] == {"chat": 1, "natal": 1}
    assert d["ai"]["costByFeature"] == {"chat": 0.002, "natal": 0.0033}
    assert d["ai"]["tokensByFeature"] == {"chat": {"prompt": 100, "output": 25},
                                          "natal": {"prompt": 900, "output": 300}}
    assert d["ai"]["byModel"] == {"m1": {"calls": 1, "cost": 0.002},
                                  "m2": {"calls": 1, "cost": 0.0033}}
    assert d["notify"]["daily"] == {"sent": 4, "failed": 1, "skippedTotal": 3,
                                    "languages": {"tr": 3, "en": 1},
                                    "pruned": 2}
    assert d["users"]["byPlatform"] == {"bilinmiyor": 3}
    # adminEconomics: u1 jeton 6 + maliyet; paylaşımlı üretim `shared`.
    # `p` = 0.0 ve `partnerTry` = 0.0: hakediş dokümanı YOK, yani ortak
    # maliyeti ÖLÇÜLDÜ ve sıfır bulundu. Alanın yokluğu "ölçülmedi" demek
    # olurdu ve okuyan taraf marjı −1'e düşürürdü (P4).
    e = sahte.docs[f"adminEconomics/{_BUGUN}"]
    assert e["users"]["u1"] == {"r": 0.0, "rs": 4.99, "c": 0.002, "n": 1,
                                "t": 6, "p": 0.0}
    assert e["shared"] == {"c": 0.0033, "n": 1}
    assert e["partnerTry"] == 0.0


def test_toplama_gelir_ortam_ve_olay_sayilari(sahte):
    """AD7: ortamsız eski olay SANDBOX; monetary=false toplama girmez ama
    sayılır; eventCounts tam anahtar listesiyle döner."""
    sahte.docs["revenueEvents/e4"] = {
        "uid": "u1", "eventType": "RENEWAL", "price": 4.99,
        "environment": "PRODUCTION", "monetary": True, "at": _SIMDI,
        "productId": "rytho_plus_monthly", "store": "APP_STORE",
        "countryCode": "DE"}
    sahte.docs["revenueEvents/e5"] = {
        "uid": "u1", "eventType": "CANCELLATION", "price": 0,
        "environment": "PRODUCTION", "monetary": False, "at": _SIMDI}
    sahte.docs["revenueEvents/e6"] = {
        "uid": "u1", "eventType": "BILLING_ISSUE", "price": 0,
        "environment": "SANDBOX", "monetary": False, "at": _SIMDI}

    d = stats_service.collect()
    r = d["revenue"]
    prod, sand = r["byEnv"]["PRODUCTION"], r["byEnv"]["SANDBOX"]
    assert prod["gross"] == 4.99 and prod["refunds"] == 0 and prod["count"] == 1
    assert sand["gross"] == pytest.approx(6.98)
    assert sand["refunds"] == 1.99 and sand["count"] == 3
    assert prod["byStore"] == {"APP_STORE": {"gross": 4.99, "count": 1}}
    assert prod["byCountry"] == {"DE": {"gross": 4.99, "count": 1}}
    assert prod["eventCounts"]["RENEWAL"] == 1
    assert prod["eventCounts"]["CANCELLATION"] == 1
    assert sand["eventCounts"]["BILLING_ISSUE"] == 1
    assert set(r["eventCounts"]) >= set(stats_service.EVENT_TYPES)
    assert r["eventCounts"]["REFUND"] == 1 and r["eventCounts"]["EXPIRATION"] == 0
    assert r["byProduct"]["rytho_plus_monthly"] == {"gross": 9.98, "count": 2}
    # Kullanıcı ekonomisi ortamı ayırır: r PRODUCTION, rs SANDBOX.
    e = sahte.docs[f"adminEconomics/{_BUGUN}"]
    assert e["users"]["u1"]["r"] == 4.99 and e["users"]["u1"]["rs"] == 4.99
    assert e["users"]["u2"]["rs"] == 0.0     # 1.99 − 1.99 iade
    assert e["count"] == 2


def test_toplama_plan_kohort_mrr(sahte, monkeypatch):
    monkeypatch.setattr(config, "SUBSCRIPTION_PRICES_USD",
                        {"rytho_plus_monthly": 4.99, "rytho_plus_yearly": 36.0})
    sahte.docs["users/u4"] = {"plan": "plus", "createdAt": _SIMDI}
    sahte.docs["users/u4/private/subscription"] = {
        "active": True, "expiresAt": _SIMDI + dt.timedelta(days=200),
        "productId": "rytho_plus_yearly", "isTrial": False}
    sahte.docs["users/u5/private/subscription"] = {
        "active": True, "expiresAt": _SIMDI + dt.timedelta(days=1),
        "productId": "rytho_plus_monthly", "isTrial": True}
    sahte.docs["users/u5"] = {"plan": "trial", "createdAt": _SIMDI}

    d = stats_service.collect()

    assert d["users"]["byPlan"] == {"free": 2, "trial": 1, "plus": 2}
    ay = _SIMDI.strftime("%Y-%m")
    assert d["cohorts"][ay] == {"signups": 3, "plus": 2}
    onceki = (_SIMDI - dt.timedelta(days=40)).strftime("%Y-%m")
    assert d["cohorts"][onceki] == {"signups": 1, "plus": 0}
    # MRR: yalnız deneme dışı aktifler; yıllık /12.
    assert d["subs"]["active"] == 3 and d["subs"]["trialing"] == 2
    assert d["subs"]["mrrUsd"] == pytest.approx(3.0)
    assert d["subs"]["mrrByProduct"] == {"rytho_plus_yearly": 3.0}
    assert d["subs"]["trialExpiring3d"] == 1


def test_economics_top_n_ve_others(sahte, monkeypatch):
    monkeypatch.setattr(stats_service, "ECONOMICS_TOP_N", 1)
    sahte.docs["usageEvents/y1"] = {"day": _BUGUN, "uid": "u9",
                                    "estCostUsd": 9.0, "feature": "chat"}
    stats_service.collect()
    e = sahte.docs[f"adminEconomics/{_BUGUN}"]
    assert list(e["users"]) == ["u9"]          # r+rs+c en büyük
    assert e["others"]["rs"] == pytest.approx(4.99)   # u1 + u2(0)
    assert e["count"] == 3


def test_ortak_edinme_maliyeti_gune_yazilir(sahte):
    """P4: o gün AÇILAN hakedişin ₺ ödülü kullanıcı kovasına (`p`) ve gün
    toplamına (`partnerTry`) girer.

    Üç değişmez: `void` sayılmaz (yükümlülük ortadan kalktı), `pending`
    sayılır (tutar hakediş ânında dondurulmuş gerçek bir ₺ borç), ve gün
    ayrımı `purchasedAt`e göredir — başka günün hakedişi bu güne girmez.
    Kural `admin_service._ortak_maliyeti` (Kullanıcı 360) ile birebir aynı;
    ayrışırsa aynı kullanıcının marjı iki ekranda farklı çıkar.
    """
    sahte.docs.update({
        "partnerQualifications/u1": {"partnerId": "p1", "status": "pending",
                                     "rewardTry": 30.0,
                                     "purchasedAt": _SIMDI},
        "partnerQualifications/u2": {"partnerId": "p1", "status": "void",
                                     "rewardTry": 30.0,
                                     "purchasedAt": _SIMDI},
        "partnerQualifications/u3": {"partnerId": "p1", "status": "qualified",
                                     "rewardTry": 45.0,
                                     "purchasedAt": _SIMDI - dt.timedelta(days=3)},
    })

    stats_service.collect()

    e = sahte.docs[f"adminEconomics/{_BUGUN}"]
    assert e["partnerTry"] == pytest.approx(30.0)
    assert e["users"]["u1"]["p"] == pytest.approx(30.0)
    assert e["users"]["u2"]["p"] == 0.0        # void marjdan düşülmez
    assert "u3" not in e["users"]              # başka günün hakedişi


def test_ortak_maliyeti_cozumlenemeyen_tutar_gunu_bilinmiyor_yapar(sahte):
    """Tutarı okunamayan hakediş günü `0` DEĞİL `-1` yapar.

    0 yazmak "o gün ortak maliyeti yoktu" iddiasıdır ve ölçülmemiştir;
    üstelik marj olduğundan yüksek çıkar ve hiçbir yerde hata görünmez.
    Somut senaryo: Firestore'da elle düzeltilmiş `rewardTry: "30,00"`.
    Blok kendi try'ında olduğu için günün geri kalanı (gelir/AI) yazılmaya
    devam eder ve kullanıcı kovasına YARIM tutar da işlenmez.
    """
    sahte.docs["partnerQualifications/u1"] = {
        "partnerId": "p1", "status": "pending", "rewardTry": "30,00",
        "purchasedAt": _SIMDI}

    stats_service.collect()

    e = sahte.docs[f"adminEconomics/{_BUGUN}"]
    assert e["partnerTry"] == -1.0
    assert e["users"]["u1"]["p"] == 0.0
    assert e["users"]["u1"]["rs"] == pytest.approx(4.99)   # gelir bloğu sağlam


def test_gecmis_gun_yalniz_olay_bolumlerini_merge_eder(sahte):
    dun = (_SIMDI - dt.timedelta(days=1)).date()
    sahte.docs[f"adminStats/{dun.isoformat()}"] = {
        "date": dun.isoformat(), "users": {"total": 42, "dau": 7},
        "revenue": {"grossToday": 99.0, "byEnv": {"ESKI": {}}}}
    sahte.docs["revenueEvents/d1"] = {
        "uid": "u1", "eventType": "RENEWAL", "price": 2.0,
        "environment": "PRODUCTION", "monetary": True,
        "at": dt.datetime.combine(dun, dt.time(12), tzinfo=dt.timezone.utc)}

    d = stats_service.collect(dun, snapshot=False)

    dok = _stats(sahte, dun.isoformat())
    assert dok["users"] == {"total": 42, "dau": 7}      # fotoğraf KORUNDU
    assert dok["revenue"]["grossToday"] == 2.0           # olaylar yenilendi
    assert "ESKI" not in dok["revenue"]["byEnv"]         # alan ezildi, birikmedi
    assert dok["eventsRecomputedAt"] and "generatedAt" not in dok
    assert "users" not in d and d["date"] == dun.isoformat()
    assert sahte.docs[f"adminEconomics/{dun.isoformat()}"]["users"]["u1"]["r"] == 2.0


def test_toplama_surum_kirilimi(sahte, monkeypatch):
    """PBZ: `appBuild` aynasından sürüm kırılımı. Alanı olmayan ≤34
    istemciler 'unknown', eşiğin altındakiler AYRI sayılır — ek count()
    sorgusu yok, tek geçişten türetilir."""
    for k in [k for k in sahte.docs if k.startswith("users/")]:
        del sahte.docs[k]
    sahte.docs.update({
        "users/u1": {"appBuild": 35}, "users/u2": {"appBuild": 36},
        "users/u3": {"appBuild": 36},
        "users/u4": {"displayName": "başlıksız eski istemci"},
        "users/u5": {"appBuild": "bozuk"},  # bozuk değer de bilinmiyor
    })
    monkeypatch.setattr(stats_service.app_gate, "current_min_build",
                        lambda: 36)

    d = stats_service.collect()

    assert d["builds"] == {"byBuild": {"35": 1, "36": 2}, "min": 36,
                           "belowMin": 1, "unknown": 2}


def test_toplama_esik_kapaliyken_altinda_sifir(sahte, monkeypatch):
    monkeypatch.setattr(stats_service.app_gate, "current_min_build",
                        lambda: 0)
    d = stats_service.collect()
    assert d["builds"]["belowMin"] == 0
    assert d["builds"]["min"] == 0


def test_toplama_idempotent(sahte):
    stats_service.collect()
    stats_service.collect()
    # Tek doküman, ezilmiş — birikme yok.
    yollar = [y for y in sahte.docs if y.startswith("adminStats/")]
    assert len(yollar) == 1
    assert sahte.docs[yollar[0]]["users"]["total"] == 3


# ---------------------------------------------------------------------------
# recompute (AD7): kilit, sınır, gün seçimi
# ---------------------------------------------------------------------------

def test_recompute_gunleri_ve_siniri(sahte, monkeypatch):
    cagrilar: list = []
    monkeypatch.setattr(stats_service, "collect",
                        lambda gun, snapshot=True: cagrilar.append((gun, snapshot)))
    monkeypatch.setattr("services.admin_service.clear_economics_cache",
                        lambda: cagrilar.append("temizlendi"))
    bugun = _SIMDI.date()
    sonuc = stats_service.recompute(bugun - dt.timedelta(days=2),
                                    bugun + dt.timedelta(days=1))
    assert sonuc["days"] == 3
    assert cagrilar[:3] == [(bugun - dt.timedelta(days=2), False),
                            (bugun - dt.timedelta(days=1), False),
                            (bugun, True)]
    assert cagrilar[-1] == "temizlendi"
    with pytest.raises(ValueError):
        stats_service.recompute(bugun - dt.timedelta(days=90), bugun)
    with pytest.raises(ValueError):
        stats_service.recompute(bugun, bugun - dt.timedelta(days=1))


def test_recompute_kilitliyken_busy(sahte, monkeypatch):
    monkeypatch.setattr(stats_service, "collect",
                        lambda gun, snapshot=True: None)
    assert stats_service._recompute_lock.acquire(blocking=False)
    try:
        with pytest.raises(RuntimeError, match="busy"):
            stats_service.recompute(_SIMDI.date(), _SIMDI.date())
    finally:
        stats_service._recompute_lock.release()
    # Kilit serbest: koşar ve kilidi geri bırakır.
    monkeypatch.setattr("services.admin_service.clear_economics_cache",
                        lambda: None)
    stats_service.recompute(_SIMDI.date(), _SIMDI.date())
    assert stats_service._recompute_lock.acquire(blocking=False)
    stats_service._recompute_lock.release()


# ---------------------------------------------------------------------------
# Uç katmanı
# ---------------------------------------------------------------------------

@uygulama_gerekir
def test_stats_ucu_claim_ister(monkeypatch):
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(config, "DEV_ADMIN", False)
    with TestClient(app) as client:
        yanit = client.get("/api/v1/admin/stats")
    assert yanit.status_code == 403


@uygulama_gerekir
def test_collect_scheduler_sirriyla_gecer(sahte, monkeypatch):
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(config, "DEV_ADMIN", False)
    monkeypatch.setattr(config, "NOTIFY_SCHEDULER_SECRET", "sir")
    with TestClient(app) as client:
        red = client.post("/api/v1/admin/collect")
        kabul = client.post("/api/v1/admin/collect",
                            headers={"Authorization": "sir"})
    assert red.status_code == 403
    assert kabul.status_code == 200
    assert kabul.json()["status"] == "ok"


@uygulama_gerekir
def test_collect_dev_admin_bayragiyla_da_gecer(sahte, monkeypatch):
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(config, "DEV_ADMIN", True)
    with TestClient(app) as client:
        yanit = client.post("/api/v1/admin/collect")
    assert yanit.status_code == 200


# ---------------------------------------------------------------------------
# Saatlik koşu + takvim penceresi (2026-10-17)
# ---------------------------------------------------------------------------

def test_saatlik_kosu_dunu_gun_bittikten_sonra_toplanmadiysa_kapatir(
        sahte, monkeypatch):
    """23:40'ta toplanmış dün, 23:40–24:00 olaylarını kaçırmıştır: bir
    sonraki koşu onu YALNIZ olay bölümleriyle yeniden toplar."""
    simdi = dt.datetime(2026, 10, 17, 0, 40, tzinfo=dt.timezone.utc)
    sahte.docs["adminStats/2026-10-16"] = {
        "date": "2026-10-16",
        "generatedAt": dt.datetime(2026, 10, 16, 23, 40,
                                   tzinfo=dt.timezone.utc)}
    cagrilar = []
    monkeypatch.setattr(stats_service, "collect",
                        lambda tarih=None, *, snapshot=True: (
                            cagrilar.append((tarih.isoformat(), snapshot))
                            or {"date": tarih.isoformat(), "durationMs": 1}))
    sonuc = stats_service.zamanlanmis_kosu(simdi)
    assert cagrilar == [("2026-10-17", True), ("2026-10-16", False)]
    assert sonuc["closedDay"] == "2026-10-16"


def test_saatlik_kosu_kapanmis_gunu_yeniden_toplamaz(sahte, monkeypatch):
    simdi = dt.datetime(2026, 10, 17, 5, 40, tzinfo=dt.timezone.utc)
    sahte.docs["adminStats/2026-10-16"] = {
        "date": "2026-10-16",
        "generatedAt": dt.datetime(2026, 10, 16, 23, 40,
                                   tzinfo=dt.timezone.utc),
        "eventsRecomputedAt": dt.datetime(2026, 10, 17, 0, 40,
                                          tzinfo=dt.timezone.utc)}
    cagrilar = []
    monkeypatch.setattr(stats_service, "collect",
                        lambda tarih=None, *, snapshot=True: (
                            cagrilar.append((tarih.isoformat(), snapshot))
                            or {"date": tarih.isoformat(), "durationMs": 1}))
    sonuc = stats_service.zamanlanmis_kosu(simdi)
    assert cagrilar == [("2026-10-17", True)]
    assert sonuc["closedDay"] is None


def test_read_days_takvim_penceresi_eksik_gunle_geriye_uzamaz(sahte):
    """Eskiden `limit(N)` son N DOKÜMANI dönüyordu: rollup bir gün
    atlayınca "2 gün" penceresi 3 gün öncesini içeri alıyordu."""
    bugun = dt.datetime.now(dt.timezone.utc).date()
    gun = lambda n: (bugun - dt.timedelta(days=n)).isoformat()
    for n in (0, 2):
        sahte.docs[f"adminStats/{gun(n)}"] = {"date": gun(n)}
    assert [d["date"] for d in stats_service.read_days(2)] == [gun(0)]
    assert [d["date"] for d in stats_service.read_days(3)] == [gun(0), gun(2)]
    assert stats_service.son_dokuman()["date"] == gun(0)

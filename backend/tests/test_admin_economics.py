"""Rollup okumaları (AD7): economics birleşimi + önbellek, revenue_summary,
revenue_events imleci, usage_summary, attention listesi.

Değişmez: bu fonksiyonların HİÇBİRİ usageEvents/revenueEvents/users'ı
taramaz — sahte depoda o koleksiyonlar boş bırakılır ve sonuç yine
rollup'tan gelir (revenue_events hariç: o ham olay sayfasıdır).
"""
from __future__ import annotations

import datetime as dt

import pytest

from _sahte_firestore import SahteFirestore
from core import app_gate, cache, config
from services import admin_service, stats_service

_SIMDI = dt.datetime.now(dt.timezone.utc)
_BUGUN = _SIMDI.date().isoformat()
_DUN = (_SIMDI - dt.timedelta(days=1)).date().isoformat()


def _stats(gun, *, prod=(10.0, 0.0, 2), sand=(3.0, 1.0, 3), issue=0,
           generated=None):
    def env(g, r, n):
        return {"gross": g, "refunds": r, "count": n,
                "byProduct": {"rytho_plus_monthly": {"gross": g, "count": n}},
                "byStore": {"PLAY_STORE": {"gross": g, "count": n}},
                "byCountry": {"TR": {"gross": g, "count": n}},
                "eventCounts": {"INITIAL_PURCHASE": n, "BILLING_ISSUE": issue}}
    return {
        "date": gun, "generatedAt": generated or _SIMDI,
        "users": {"total": 5}, "cohorts": {"2026-09": {"signups": 5, "plus": 1}},
        "subs": {"active": 2, "trialing": 1, "mrrUsd": 9.98,
                 "mrrByProduct": {"rytho_plus_monthly": 9.98},
                 "trialExpiring3d": 1},
        "revenue": {"byEnv": {"PRODUCTION": env(*prod), "SANDBOX": env(*sand)}},
        "ai": {"callsToday": 4, "estCostToday": 0.02,
               "byFeature": {"chat": 3, "natal": 1},
               "costByFeature": {"chat": 0.015, "natal": 0.005},
               "tokensByFeature": {"chat": {"prompt": 300, "output": 100},
                                   "natal": {"prompt": 900, "output": 400}},
               "byModel": {"gemini": {"calls": 4, "cost": 0.02}}},
        "notify": {"daily": {"sent": 3, "failed": 1, "skippedTotal": 0}},
    }


@pytest.fixture()
def depo(monkeypatch, tmp_path):
    sahte = SahteFirestore({
        "users/u1": {"displayName": "Ayşe", "email": "a@x.y"},
        "users/u2": {"displayName": "Bora", "email": "b@x.y"},
        "adminStats/" + _DUN: _stats(_DUN, issue=1),
        "adminStats/" + _BUGUN: _stats(_BUGUN),
        # `partnerTry: 0.0` = "ortak maliyeti ÖLÇÜLDÜ, sıfır". Alan hiç
        # yoksa okuyan taraf "ölçülmedi" sayar ve marjı −1'e düşürür (P4);
        # aşağıdaki eksik-gün testi tam o hâli kuruyor.
        "adminEconomics/" + _DUN: {
            "date": _DUN,
            "users": {"u1": {"r": 10.0, "rs": 0, "c": 0.5, "n": 5, "t": 4},
                      "u2": {"r": 0, "rs": 3.0, "c": 0.1, "n": 1, "t": 0}},
            "others": {"r": 1.0, "rs": 0, "c": 0.2, "n": 2, "t": 1},
            "shared": {"c": 0.05, "n": 1}, "partnerTry": 0.0, "count": 2},
        "adminEconomics/" + _BUGUN: {
            "date": _BUGUN,
            "users": {"u1": {"r": 0, "rs": 0, "c": 0.25, "n": 2, "t": 1}},
            "others": {"r": 0, "rs": 0, "c": 0, "n": 0, "t": 0},
            "shared": {"c": 0, "n": 0}, "partnerTry": 0.0, "count": 1},
    })
    monkeypatch.setattr(
        "services.admin_service.firestore_client.get_client", lambda: sahte)
    monkeypatch.setattr(
        "services.stats_service.firestore_client.get_client", lambda: sahte)
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    admin_service._ECON_CACHE_KEYS.clear()
    yield sahte
    cache._memory.clear()


# --- economics ---------------------------------------------------------------

def test_economics_birlesim_ve_ortam(depo):
    p = admin_service.economics(days=30, env="PRODUCTION")
    assert p["coverage"] == {"daysFound": 2, "oldest": _DUN}
    u1 = next(s for s in p["users"] if s["uid"] == "u1")
    assert u1["revenueUsd"] == 10.0 and u1["sandboxUsd"] == 0
    assert u1["aiCostUsd"] == pytest.approx(0.75)
    assert u1["calls"] == 7 and u1["tokensSpent"] == 5
    assert u1["marginUsd"] == pytest.approx(10 * 0.85 - 0.75)
    assert u1["displayName"] == "Ayşe" and u1["email"] == "a@x.y"
    u2 = next(s for s in p["users"] if s["uid"] == "u2")
    assert u2["marginUsd"] == pytest.approx(-0.1)  # PRODUCTION geliri 0
    t = p["totals"]
    assert t["revenueUsd"] == 11.0          # u1 + others
    assert t["sandboxUsd"] == 3.0
    assert t["aiCostUsd"] == pytest.approx(0.75 + 0.1 + 0.2 + 0.05)
    assert t["sharedAiCostUsd"] == pytest.approx(0.05)
    assert t["calls"] == 7 + 1 + 2 + 1

    s = admin_service.economics(days=30, env="SANDBOX")
    u2s = next(x for x in s["users"] if x["uid"] == "u2")
    assert u2s["marginUsd"] == pytest.approx(3.0 * 0.85 - 0.1)
    assert s["totals"]["marginUsd"] == pytest.approx(
        3.0 * 0.85 - (0.75 + 0.1 + 0.2 + 0.05))


def test_economics_ortak_maliyeti_marjdan_dusulur(depo, monkeypatch):
    """P4: rollup'taki ₺ ödül (`p`) kurla dolara çevrilip marjdan düşülür.

    `grossMarginUsd` ortak öncesi marjdır ve değişmez; `marginUsd` üç
    terimlidir — Kullanıcı 360'taki formülün aynısı. Kur TEK yerden
    (`admin_service.USD_TRY`) okunur: rollup ₺ yazar, çeviriyi burası
    yapar, yoksa iki ekran iki farklı marj gösterirdi.
    """
    monkeypatch.setattr(admin_service, "USD_TRY", 40.0)
    depo.docs["adminEconomics/" + _BUGUN]["users"]["u1"]["p"] = 40.0
    depo.docs["adminEconomics/" + _BUGUN]["partnerTry"] = 40.0

    p = admin_service.economics(days=30, env="PRODUCTION")

    u1 = next(s for s in p["users"] if s["uid"] == "u1")
    assert u1["partnerCostTry"] == 40.0
    assert u1["partnerCostUsd"] == pytest.approx(1.0)
    assert u1["grossMarginUsd"] == pytest.approx(10 * 0.85 - 0.75)
    assert u1["marginUsd"] == pytest.approx(10 * 0.85 - 0.75 - 1.0)
    u2 = next(s for s in p["users"] if s["uid"] == "u2")
    assert u2["partnerCostUsd"] == 0.0     # ölçüldü, ödülü yok
    t = p["totals"]
    assert t["partnerDaysMissing"] == 0
    assert t["partnerCostTry"] == 40.0
    assert t["partnerCostUsd"] == pytest.approx(1.0)
    assert t["usdTryRate"] == 40.0
    assert t["marginUsd"] == pytest.approx(t["grossMarginUsd"] - 1.0)


def test_economics_olcmeyen_gun_ortak_maliyetini_bilinmiyor_yapar(depo,
                                                                 monkeypatch):
    """`partnerTry` taşımayan gün → ortak maliyeti ve marj −1, 0 DEĞİL.

    0 demek "ortak maliyeti yoktu" iddiasıdır ve ölçülmemiştir. Eksik günde
    hangi kullanıcının ödülünün kayıp olduğu da bilinmediği için satır
    bazında kurtarılamaz: SATIRLARIN HEPSİ bilinmiyor olur. Ölçülmüş
    terimler (gelir, AI, ortak öncesi marj) yine döner ki panel gösterecek
    dürüst bir sayı bulsun.
    """
    monkeypatch.setattr(admin_service, "USD_TRY", 40.0)
    del depo.docs["adminEconomics/" + _DUN]["partnerTry"]   # eski rollup

    p = admin_service.economics(days=30, env="PRODUCTION")

    t = p["totals"]
    assert t["partnerDaysMissing"] == 1
    assert t["partnerCostTry"] == -1.0 and t["partnerCostUsd"] == -1.0
    assert t["marginUsd"] == -1.0
    assert t["grossMarginUsd"] == pytest.approx(11.0 * 0.85 - 1.1)
    u1 = next(s for s in p["users"] if s["uid"] == "u1")
    assert u1["partnerCostUsd"] == -1.0 and u1["marginUsd"] == -1.0
    assert u1["grossMarginUsd"] == pytest.approx(10 * 0.85 - 0.75)


def test_economics_kur_yokken_try_olculu_marj_bilinmiyor(depo, monkeypatch):
    """Kur ayarsızken ₺ tutar ölçülüdür, dolar ve marj değil.

    Ödülü OLMAYAN satır kur yokken de 0 maliyetlidir ve marjı ölçülüdür —
    sıfır kontrolü kur kontrolünden önce geldiği için tablo boşalmıyor.
    """
    monkeypatch.setattr(admin_service, "USD_TRY", 0.0)
    depo.docs["adminEconomics/" + _BUGUN]["users"]["u1"]["p"] = 40.0
    depo.docs["adminEconomics/" + _BUGUN]["partnerTry"] = 40.0

    p = admin_service.economics(days=30, env="PRODUCTION")

    u1 = next(s for s in p["users"] if s["uid"] == "u1")
    assert u1["partnerCostTry"] == 40.0     # ölçülen birim ₺
    assert u1["partnerCostUsd"] == -1.0     # çevrilemedi
    assert u1["marginUsd"] == -1.0
    u2 = next(s for s in p["users"] if s["uid"] == "u2")
    assert u2["partnerCostUsd"] == 0.0
    assert u2["marginUsd"] == pytest.approx(-0.1)
    assert p["totals"]["usdTryRate"] == -1


def test_economics_onbellek_ve_temizleme(depo, monkeypatch):
    ilk = admin_service.economics(days=30, env="PRODUCTION")
    # Firestore artık yok — sonuç önbellekten gelmeli.
    monkeypatch.setattr(
        "services.admin_service.firestore_client.get_client", lambda: None)
    assert admin_service.economics(days=30, env="PRODUCTION") == ilk
    admin_service.clear_economics_cache()
    with pytest.raises(RuntimeError):
        admin_service.economics(days=30, env="PRODUCTION")


def test_economics_top_n_kirpar(depo, monkeypatch):
    monkeypatch.setattr(admin_service, "ECONOMICS_TOP_N", 1)
    p = admin_service.economics(days=30, env="PRODUCTION")
    assert [s["uid"] for s in p["users"]] == ["u1"]
    assert p["totals"]["usersCounted"] == 2   # toplam yine iki kullanıcı


# --- revenue_summary -----------------------------------------------------------

def test_revenue_summary_rolluptan(depo):
    r = admin_service.revenue_summary(days=7, env="PRODUCTION")
    assert [g["date"] for g in r["byDay"]] == [_DUN, _BUGUN]
    assert r["grossUsd"] == 20.0 and r["refundsUsd"] == 0.0
    assert r["byProduct"]["rytho_plus_monthly"] == {"gross": 20.0, "count": 4}
    assert r["eventCounts"]["INITIAL_PURCHASE"] == 4
    assert r["eventCounts"]["BILLING_ISSUE"] == 1
    assert r["eventCounts"]["REFUND"] == 0     # tam anahtar listesi
    assert r["mrrUsd"] == 9.98 and r["activeSubs"] == 2 and r["trialing"] == 1
    assert r["cohorts"] == {"2026-09": {"signups": 5, "plus": 1}}
    s = admin_service.revenue_summary(days=7, env="SANDBOX")
    assert s["grossUsd"] == 6.0 and s["refundsUsd"] == 2.0


# --- revenue_events ------------------------------------------------------------

def test_revenue_events_suzgec_ve_imlec(depo):
    for i in range(5):
        depo.docs[f"revenueEvents/e{i}"] = {
            "uid": "u1", "environment": "SANDBOX",
            "eventType": "RENEWAL" if i % 2 else "CANCELLATION",
            "at": _SIMDI - dt.timedelta(hours=i)}
    depo.docs["revenueEvents/p1"] = {"uid": "u1", "environment": "PRODUCTION",
                                     "eventType": "RENEWAL", "at": _SIMDI}
    depo.docs["revenueEvents/eski"] = {"uid": "u1", "eventType": "RENEWAL",
                                       "at": _SIMDI}  # ortamsız: hiçbir sayfada
    ilk = admin_service.revenue_events(env="SANDBOX", limit=2)
    assert [e["id"] for e in ilk["events"]] == ["e0", "e1"]
    assert ilk["nextCursor"]
    ikinci = admin_service.revenue_events(env="SANDBOX", limit=2,
                                          cursor=ilk["nextCursor"])
    assert [e["id"] for e in ikinci["events"]] == ["e2", "e3"]
    ucuncu = admin_service.revenue_events(env="SANDBOX", limit=2,
                                          cursor=ikinci["nextCursor"])
    assert [e["id"] for e in ucuncu["events"]] == ["e4"]
    assert ucuncu["nextCursor"] is None
    yenileme = admin_service.revenue_events(env="SANDBOX", event_type="renewal")
    assert [e["id"] for e in yenileme["events"]] == ["e1", "e3"]
    assert [e["id"] for e in admin_service.revenue_events()["events"]] == ["p1"]


# --- usage_summary -------------------------------------------------------------

def test_usage_summary_rolluptan(depo):
    u = admin_service.usage_summary(days=7)
    assert u["byDay"][_BUGUN] == {"calls": 4, "estCostUsd": 0.02}
    assert u["totals"]["calls"] == 8
    assert u["totals"]["estCostUsd"] == pytest.approx(0.04)
    assert u["byFeature"]["chat"] == {"calls": 6, "estCostUsd": 0.03,
                                      "promptTokens": 600, "outputTokens": 200}
    assert u["byModel"]["gemini"]["calls"] == 8
    # topUsers: en son adminEconomics, maliyete göre; ad get_all ile.
    assert u["topUsers"][0]["uid"] == "u1"
    assert u["topUsers"][0]["displayName"] == "Ayşe"
    assert u["topUsers"][0]["aiCostUsd"] == 0.25
    assert u["costs"]


# --- attention ------------------------------------------------------------------

def test_attention_kalemleri(depo, monkeypatch):
    depo.docs[f"notifyRuns/{_BUGUN}-daily"] = {"failed": 2}
    depo.docs[f"notifyRuns/{_BUGUN}-streak"] = {"failed": 1}
    depo.docs["users/u3"] = {"authDisabled": True}
    depo.docs["users/u1/private/subscription"] = {
        "isTrial": True, "expiresAt": _SIMDI + dt.timedelta(days=1)}
    depo.docs["users/u2/private/subscription"] = {
        "isTrial": True, "expiresAt": _SIMDI + dt.timedelta(days=9)}
    depo.docs["users/u3/private/subscription"] = {
        "isTrial": True, "expiresAt": _SIMDI - dt.timedelta(days=1)}  # bitmiş
    monkeypatch.setattr(app_gate, "current_min_build", lambda: 40)
    monkeypatch.setattr(app_gate, "count_below", lambda esik: 7)

    kalemler = {k["tur"]: k for k in admin_service.attention()}
    assert kalemler["failedPushesToday"]["sayi"] == 3
    assert kalemler["failedPushesToday"]["seviye"] == "uyari"
    assert kalemler["billingIssues7d"]["sayi"] == 1
    assert kalemler["trialsExpiring3d"]["sayi"] == 1
    assert kalemler["belowMin"]["sayi"] == 7
    assert kalemler["disabledTotal"]["sayi"] == 1
    assert "rollupStale" not in kalemler   # bugünün rollup'ı taze
    assert all(k["rota"].startswith("#/") for k in kalemler.values())


def test_attention_bayat_rollup_ve_bos(depo, monkeypatch):
    depo.docs["adminStats/" + _BUGUN]["generatedAt"] = _SIMDI - dt.timedelta(hours=40)
    monkeypatch.setattr(app_gate, "current_min_build", lambda: 0)
    kalemler = {k["tur"]: k for k in admin_service.attention()}
    assert kalemler["rollupStale"]["seviye"] == "hata"
    assert kalemler["rollupStale"]["sayi"] >= 40
    assert "belowMin" not in kalemler
    assert "failedPushesToday" not in kalemler   # sıfır kalem listelenmez


def test_attention_firestore_yokken_bos(monkeypatch):
    monkeypatch.setattr(
        "services.admin_service.firestore_client.get_client", lambda: None)
    assert admin_service.attention() == []


def test_recompute_onbellegi_temizler(depo, monkeypatch):
    """stats_service.recompute → admin_service.clear_economics_cache."""
    ilk = admin_service.economics(days=30, env="PRODUCTION")
    assert ilk["users"][0]["aiCostUsd"] == pytest.approx(0.75)
    monkeypatch.setattr(stats_service, "collect",
                        lambda gun, snapshot=True: None)
    depo.docs["adminEconomics/" + _BUGUN]["users"]["u1"]["c"] = 5.0
    stats_service.recompute(_SIMDI.date(), _SIMDI.date())
    yeni = admin_service.economics(days=30, env="PRODUCTION")
    assert yeni["users"][0]["aiCostUsd"] == pytest.approx(5.5)

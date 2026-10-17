"""Admin kullanıcı uçlarının bekçileri (AP-turu).

Değişmezler:
- Uçlar admin claim'siz 403 (varlık sızdırmayan jenerik mesaj zaten
  require_admin'de).
- Liste satırı ve 360, fcmToken DEĞERİNİ asla döndürmez (hasPush bool).
- 360 sohbet/hafıza/günlük İÇERİĞİ taşımaz — yalnız sayılar.
- Elle kredi: gerekçesiz/pozitif-olmayan tutar 422; başarılı yol defteri
  VE denetim izini birlikte yazar.
"""
from __future__ import annotations

import datetime as dt

import pytest
from fastapi.testclient import TestClient

from core import config
from services import admin_service, search_mirror

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


from _sahte_firestore import SahteFirestore  # noqa: E402


_SIMDI = dt.datetime.now(dt.timezone.utc)


@pytest.fixture()
def depo(monkeypatch):
    sahte = SahteFirestore()
    sahte.docs.update({
        "users/u1": {"displayName": "Ayşe", "email": "ayse@ornek.com",
                     "username": "ayse", "sunSign": "leo",
                     **search_mirror.compute({"displayName": "Ayşe",
                                              "email": "ayse@ornek.com",
                                              "username": "ayse"}),
                     "createdAt": _SIMDI, "lastSeenDaily": "2026-08-29",
                     "streakCount": 4, "language": "tr",
                     "timezone": "Europe/Istanbul", "platform": "android",
                     "onboardingCompleted": True, "fcmToken": "GIZLI-TOKEN",
                     "birthDate": "1990-01-01"},
        "users/u2": {"displayName": "Erkan", "email": "erkan@ornek.com",
                     "createdAt": _SIMDI - dt.timedelta(days=3),
                     **search_mirror.compute({"displayName": "Erkan",
                                              "email": "erkan@ornek.com"})},
        "users/u1/private/subscription": {"active": True,
                                          "productId": "rytho_plus_monthly"},
        "users/u1/private/notifications": {"dailyLastSent": "2026-08-29",
                                           "dailyTheme": "inner",
                                           "dailyBody": "GIZLI GOVDE"},
        "users/u1/private/wallet/ledger/l1": {"type": "debit",
                                              "feature": "chat", "amount": 1,
                                              "at": _SIMDI},
        "users/u1/conversations/c1": {"messageCount": 3},
        "users/u1/conversations/c1/messages/m1": {"text": "GIZLI MESAJ"},
        "users/u1/friends/f1": {"status": "accepted"},
        "revenueEvents/e1": {"uid": "u1", "eventType": "INITIAL_PURCHASE",
                             "price": 4.99, "at": _SIMDI},
    })
    monkeypatch.setattr(
        "services.admin_service.firestore_client.get_client", lambda: sahte)
    monkeypatch.setattr(admin_service.wallet, "get_wallet",
                        lambda uid: {"allowance": 0, "purchased": 30,
                                     "monthly_allowance": 300,
                                     "allowance_resets_at": None,
                                     "costs": {}})
    return sahte


def test_liste_sekli_ve_token_sizmaz(depo):
    sonuc = admin_service.list_users()
    assert sonuc["mode"] == "filter" and sonuc["nextCursor"] is None
    satirlar = sonuc["users"]
    assert len(satirlar) == 2
    ayse = next(s for s in satirlar if s["uid"] == "u1")
    assert ayse["hasPush"] is True
    assert "fcmToken" not in ayse
    assert ayse["platform"] == "android"
    # createdAt desc: u1 (bugün) önce
    assert satirlar[0]["uid"] == "u1"


def test_liste_onek_aramasi(depo):
    """Arama modu: ayna alanında önek (AD4) — tam tarama yok."""
    sonuc = admin_service.list_users(q="Erk", alan="ad")
    assert sonuc["mode"] == "search"
    assert [s["uid"] for s in sonuc["users"]] == ["u2"]
    assert admin_service.list_users(q="yok")["users"] == []


def test_360_sekli_mahremiyet_cizgisi(depo):
    detay = admin_service.user_360("u1")
    assert detay is not None
    assert detay["profile"]["hasPush"] is True
    assert "fcmToken" not in detay["profile"]
    assert detay["subscription"]["productId"] == "rytho_plus_monthly"
    assert detay["counts"]["conversations"] == 1
    assert detay["counts"]["friends"] == 1
    assert detay["ledger"][0]["type"] == "debit"
    assert detay["revenueEvents"][0]["eventType"] == "INITIAL_PURCHASE"
    # Bildirim META'sı: gövde metni DÖNMEZ, LastSent/tema döner.
    assert detay["notifications"]["dailyLastSent"] == "2026-08-29"
    assert "dailyBody" not in detay["notifications"]
    # İçerik hiçbir anahtarda yok.
    duz = str(detay)
    assert "GIZLI MESAJ" not in duz
    assert "GIZLI GOVDE" not in duz
    assert "GIZLI-TOKEN" not in duz


def test_360_bilinmeyen_kullanici_none(depo):
    assert admin_service.user_360("yok") is None


def test_360_onboarding_rozeti_bool_doner(depo):
    """360 rozeti de `onboardingCompleted === false` arıyor
    (kullanicilar.js). Profil HAM dokümandan üretildiği için alanı hiç
    yazmamış kullanıcıda anahtar bile gelmiyordu ve rozet yanmıyordu —
    gösterilmesi gereken tam o kullanıcı. u1 alanı taşıyor, u2 (akışı yarım
    bırakan) taşımıyor."""
    assert "onboardingCompleted" not in depo.docs["users/u2"]
    u1 = admin_service.user_360("u1")
    assert u1["profile"]["onboardingCompleted"] is True
    u2 = admin_service.user_360("u2")
    assert u2["profile"]["onboardingCompleted"] is False


# ---------------------------------------------------------------------------
# 360 ekonomisi: ortak (affiliate) edinme maliyeti (OP13)
# ---------------------------------------------------------------------------
#
# Bu bekçilerin varlık sebebi SESSİZ bir kusurdur: ortaklık programı
# açıldıktan sonra her atıflı abone gerçek bir ₺ ödemesi doğuruyor ama
# marj formülü onu düşmüyordu. Panel marjı olduğundan yüksek gösteriyor,
# hiçbir yerde hata görünmüyordu ve sahibi fiyat kararını o sayıyla
# veriyordu.

#: 360 ekonomisinin hesaplanabilmesi için gereken iki rollup dokümanı.
#: Yokken tüm ekonomi alanları −1 olur (o dal ayrıca test ediliyor).
_GELIR_TOPLAM = {"PRODUCTION": {"grossUsd": 10.0, "refundsUsd": 0.0}}
_KULLANIM_TOPLAM = {"estCostUsd": 0.5, "calls": 7}


def _ekonomi_kur(depo, *, hakedis: dict | None = None):
    """u1'e rollup toplamlarını, istenirse hakediş kaydını yazar."""
    depo.docs["users/u1/private/revenueTotals"] = dict(_GELIR_TOPLAM)
    depo.docs["users/u1/private/usageTotals"] = dict(_KULLANIM_TOPLAM)
    if hakedis is not None:
        depo.docs["partnerQualifications/u1"] = hakedis


def test_360_ortak_maliyeti_marji_dusurur(depo, monkeypatch):
    """Kesinleşmiş hakediş: marj ORTAK MALİYETİ KADAR düşük çıkar.

    84 ₺ / 42 = $2 — kur `USD_TRY`den geliyor, koddan değil."""
    monkeypatch.setattr(admin_service, "USD_TRY", 42.0)
    _ekonomi_kur(depo, hakedis={"partnerId": "p1", "status": "qualified",
                                "rewardTry": 84.0, "purchasedAt": _SIMDI})

    e = admin_service.user_360("u1")["economics"]

    assert e["partnerRewardTry"] == pytest.approx(84.0)
    assert e["partnerCostUsd"] == pytest.approx(2.0)
    assert e["partnerStatus"] == "qualified"
    assert e["usdTryRate"] == pytest.approx(42.0)
    assert e["marginUsd"] == pytest.approx(10.0 * 0.85 - 0.5 - 2.0)
    # Sözleşme kırılmadı: eski alanlar aynen duruyor.
    assert e["revenueUsd"] == pytest.approx(10.0)
    assert e["aiCostUsd"] == pytest.approx(0.5)
    assert e["calls"] == 7
    assert e["storeCutRate"] == 0.15


def test_360_bekleyen_hakedis_de_dusulur(depo, monkeypatch):
    """`pending` muhtemel bir yükümlülüktür: sayılmazsa her atıflı abone
    ilk 15 gün boyunca olduğundan kârlı görünür."""
    monkeypatch.setattr(admin_service, "USD_TRY", 42.0)
    _ekonomi_kur(depo, hakedis={"partnerId": "p1", "status": "pending",
                                "rewardTry": 42.0})

    e = admin_service.user_360("u1")["economics"]

    assert e["partnerStatus"] == "pending"
    assert e["partnerCostUsd"] == pytest.approx(1.0)
    assert e["marginUsd"] == pytest.approx(10.0 * 0.85 - 0.5 - 1.0)


def test_360_iptal_hakedis_marji_dusurmez(depo, monkeypatch):
    """`void`ta yükümlülük gerçekten ortadan kalktı (iade/erken sona erme)
    — tutar dokümanda DURUYOR ama marjdan düşülmez."""
    monkeypatch.setattr(admin_service, "USD_TRY", 42.0)
    _ekonomi_kur(depo, hakedis={"partnerId": "p1", "status": "void",
                                "rewardTry": 84.0, "voidReason": "REFUND"})

    e = admin_service.user_360("u1")["economics"]

    assert e["partnerStatus"] == "void"
    assert e["partnerCostUsd"] == 0.0
    assert e["partnerRewardTry"] == 0.0
    assert e["marginUsd"] == pytest.approx(10.0 * 0.85 - 0.5)


def test_360_ortaksiz_kullanicinin_marji_degismedi(depo, monkeypatch):
    """Atfı olmayan kullanıcıda formül BİREBİR eski davranışta kalmalı —
    yoksa düzeltme, düzelttiğinden çok sayıyı bozar."""
    monkeypatch.setattr(admin_service, "USD_TRY", 42.0)
    _ekonomi_kur(depo)

    e = admin_service.user_360("u1")["economics"]

    assert e["partnerCostUsd"] == 0.0
    assert e["partnerStatus"] is None
    assert e["marginUsd"] == pytest.approx(10.0 * 0.85 - 0.5)


def test_360_kur_bilinmiyorsa_sentinel(depo, monkeypatch):
    """Kur çözümlenemediyse ₺ yükümlülük dolara çevrilemez: `−1` sentinel
    doktrini (panelde "—"), uydurma kurla hesaplanmış bir marj DEĞİL.
    ₺ tutarı ham hâliyle yine döner."""
    monkeypatch.setattr(admin_service, "USD_TRY", 0.0)
    _ekonomi_kur(depo, hakedis={"partnerId": "p1", "status": "qualified",
                                "rewardTry": 84.0})

    e = admin_service.user_360("u1")["economics"]

    assert e["partnerCostUsd"] == -1.0
    assert e["partnerRewardTry"] == pytest.approx(84.0)
    assert e["usdTryRate"] == -1
    assert e["marginUsd"] == -1.0
    # Gelir/maliyet ölçüldü, onlar sentinel'e düşmez.
    assert e["revenueUsd"] == pytest.approx(10.0)
    assert e["aiCostUsd"] == pytest.approx(0.5)


def test_360_kur_bozukken_ortaksiz_marj_hesaplanir(depo, monkeypatch):
    """Kur yoksa bile ATFI OLMAYAN kullanıcının marjı hesaplanabilir:
    çevrilecek bir ₺ tutarı yok. Sentinel'i buraya da yaymak, kusuru
    olmayan kullanıcıların marjını sebepsiz "—" yapardı."""
    monkeypatch.setattr(admin_service, "USD_TRY", 0.0)
    _ekonomi_kur(depo)

    e = admin_service.user_360("u1")["economics"]

    assert e["partnerCostUsd"] == 0.0
    assert e["marginUsd"] == pytest.approx(10.0 * 0.85 - 0.5)


def test_360_cozumlenemeyen_odul_tutari_sentinel(depo, monkeypatch):
    """Hakediş dokümanı VAR ama tutarı sayıya çevrilemiyor: bu "maliyet
    sıfır" değil "maliyet bilinmiyor"dur. 0 dönmek marjı olduğundan
    yüksek gösterirdi ve hiçbir yerde hata görünmezdi. Somut senaryo:
    Firestore'da elle düzeltilmiş `rewardTry: "30,00"` (Türkçe ondalık)."""
    monkeypatch.setattr(admin_service, "USD_TRY", 42.0)
    _ekonomi_kur(depo, hakedis={"partnerId": "p1", "status": "pending",
                                "rewardTry": "30,00"})

    e = admin_service.user_360("u1")["economics"]

    assert e["partnerCostUsd"] == -1.0
    assert e["partnerRewardTry"] == -1.0
    assert e["partnerStatus"] == "pending"
    assert e["marginUsd"] == -1.0
    # Ölçülmüş olanlar sentinel'e düşmez.
    assert e["revenueUsd"] == pytest.approx(10.0)


def test_kur_oku_bozuk_degerde_sifira_duser(monkeypatch):
    """`_kur_oku` bozuk değerde VARSAYILANA DÜŞMEZ (config._int_env'in
    tersi): kimsenin niyet etmediği bir kurla hesaplanmış sayıyı "marj"
    adıyla sunmak, "—" göstermekten daha kötüdür. Boş env bozuk değil,
    yalnız ayarlanmamıştır."""
    monkeypatch.delenv("RYTHO_USD_TRY", raising=False)
    assert admin_service._kur_oku() == admin_service.USD_TRY_DEFAULT

    monkeypatch.setenv("RYTHO_USD_TRY", "43.5")
    assert admin_service._kur_oku() == pytest.approx(43.5)
    # Türkçe klavye alışkanlığı: virgüllü ondalık da okunur.
    monkeypatch.setenv("RYTHO_USD_TRY", "43,5")
    assert admin_service._kur_oku() == pytest.approx(43.5)

    for bozuk in ("kirk-iki", "", "0", "-42"):
        monkeypatch.setenv("RYTHO_USD_TRY", bozuk)
        beklenen = (admin_service.USD_TRY_DEFAULT if bozuk == "" else 0.0)
        assert admin_service._kur_oku() == beklenen, bozuk


# ---------------------------------------------------------------------------
# Uç katmanı
# ---------------------------------------------------------------------------

@uygulama_gerekir
def test_ucler_claim_ister(monkeypatch):
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(config, "DEV_ADMIN", False)
    with TestClient(app) as client:
        for yol in ("/api/v1/admin/users", "/api/v1/admin/users/u1",
                    "/api/v1/admin/usage", "/api/v1/admin/notify-runs",
                    "/api/v1/admin/audit", "/api/v1/admin/economics"):
            assert client.get(yol).status_code == 403, yol
        assert client.post("/api/v1/admin/users/u1/credit",
                           json={"amount": 5, "reason": "test"}
                           ).status_code == 403
        assert client.post("/api/v1/admin/users/u1/disable",
                           json={"disabled": True, "reason": "test"}
                           ).status_code == 403
        assert client.request("DELETE", "/api/v1/admin/users/u1",
                              json={"confirm": "SIL", "reason": "test"}
                              ).status_code == 403


@uygulama_gerekir
def test_kredi_dogrulama_422(monkeypatch, depo):
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(config, "DEV_ADMIN", True)
    with TestClient(app) as client:
        # Gerekçesiz → 422 (zorunlu alan).
        r1 = client.post("/api/v1/admin/users/u1/credit",
                         json={"amount": 5})
        # Sıfır/negatif tutar → 422 (gt=0).
        r2 = client.post("/api/v1/admin/users/u1/credit",
                         json={"amount": 0, "reason": "sebep var"})
    assert r1.status_code == 422
    assert r2.status_code == 422


@uygulama_gerekir
def test_kredi_basarili_defter_ve_audit(monkeypatch, depo):
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(config, "DEV_ADMIN", True)

    verilen: list = []
    monkeypatch.setattr(admin_service.wallet, "credit_admin",
                        lambda uid, amount, reason, admin_uid:
                        verilen.append((uid, amount, reason, admin_uid)))
    # Denetim izi api.admin'in kendi istemcisiyle yazılır.
    monkeypatch.setattr("api.admin.firestore_client.get_client",
                        lambda: depo)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/admin/users/u1/credit",
                            json={"amount": 50,
                                  "reason": "paket gelmedi, telafi"})

    assert yanit.status_code == 200
    assert verilen == [("u1", 50, "paket gelmedi, telafi", "dev-user")]
    izler = [v for k, v in depo.docs.items() if k.startswith("adminAudit/")]
    assert len(izler) == 1
    assert izler[0]["action"] == "user.credit"
    assert izler[0]["targetUid"] == "u1"
    assert izler[0]["params"]["reason"] == "paket gelmedi, telafi"


# ---------------------------------------------------------------------------
# Yönetim eylemleri (AP2): devre dışı bırak + sil emniyetleri
# ---------------------------------------------------------------------------

class _SahteFbAuth:
    def __init__(self):
        self.guncellenen = []
        self.revoke_edilen = []

    def update_user(self, uid, disabled=None):
        self.guncellenen.append((uid, disabled))

    def revoke_refresh_tokens(self, uid):
        self.revoke_edilen.append(uid)

    class _K:
        disabled = False

    def get_user(self, uid):
        return self._K()


@uygulama_gerekir
def test_disable_akisi_ve_kendini_koruma(monkeypatch, depo):
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(config, "DEV_ADMIN", True)
    sahte_auth = _SahteFbAuth()
    import firebase_admin
    monkeypatch.setattr(firebase_admin, "auth", sahte_auth, raising=False)
    import sys
    monkeypatch.setitem(sys.modules, "firebase_admin.auth", sahte_auth)
    monkeypatch.setattr("api.admin.firestore_client.get_client",
                        lambda: depo)

    with TestClient(app) as client:
        tamam = client.post("/api/v1/admin/users/u1/disable",
                            json={"disabled": True, "reason": "kotu kullanim"})
        kendisi = client.post("/api/v1/admin/users/dev-user/disable",
                              json={"disabled": True, "reason": "x-y-z"})
        gerekcesiz = client.post("/api/v1/admin/users/u1/disable",
                                 json={"disabled": True})

    assert tamam.status_code == 200
    assert sahte_auth.guncellenen == [("u1", True)]
    assert sahte_auth.revoke_edilen == ["u1"]
    assert kendisi.status_code == 400
    assert gerekcesiz.status_code == 422
    izler = [v for k, v in depo.docs.items() if k.startswith("adminAudit/")]
    assert [i["action"] for i in izler] == ["user.disable"]


@uygulama_gerekir
def test_silme_emniyetleri_ve_akisi(monkeypatch, depo):
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(config, "DEV_ADMIN", True)
    monkeypatch.setattr("api.admin.firestore_client.get_client",
                        lambda: depo)

    silinen = []
    from services import account_service
    monkeypatch.setattr(account_service, "delete_account",
                        lambda uid: silinen.append(uid) or
                        type("R", (), {"__dict__": {"ok": True}})())

    with TestClient(app) as client:
        onaysiz = client.request("DELETE", "/api/v1/admin/users/u1",
                                 json={"confirm": "sil", "reason": "test-sil"})
        kendisi = client.request("DELETE", "/api/v1/admin/users/dev-user",
                                 json={"confirm": "SIL", "reason": "test-sil"})
        tamam = client.request("DELETE", "/api/v1/admin/users/u1",
                               json={"confirm": "SIL", "reason": "test-sil"})

    assert onaysiz.status_code == 400
    assert kendisi.status_code == 400
    assert tamam.status_code == 200
    assert silinen == ["u1"]
    izler = [v for k, v in depo.docs.items() if k.startswith("adminAudit/")]
    assert [i["action"] for i in izler] == ["user.delete"]
    assert izler[0]["params"]["email"] == "ayse@ornek.com"


def test_economics_marj_matematigi(depo, monkeypatch):
    """Kâr = gelir × 0,85 − AI maliyeti; iade negatif; paylaşımlı üretim
    kullanıcıya yazılmaz ama toplamda görünür — kaynak adminEconomics
    rollup'ı (AD7), canlı tarama YOK (usageEvents/revenueEvents boş olsa
    da sonuç aynı)."""
    monkeypatch.setattr(admin_service.cache, "get", lambda k: None)
    monkeypatch.setattr(admin_service.cache, "set", lambda *a, **k: None)
    # Günler BUGÜNE göre: pencere takvimdir (son 30 GÜN), sabit 2026-09
    # tarihleri pencere ilerledikçe dışarıda kalırdı.
    bugun = dt.datetime.now(dt.timezone.utc).date()
    g1 = (bugun - dt.timedelta(days=6)).isoformat()
    g2 = (bugun - dt.timedelta(days=5)).isoformat()
    depo.docs[f"adminEconomics/{g1}"] = {
        "date": g1,
        "users": {"u1": {"r": 4.99, "rs": 0, "c": 0.05, "n": 1, "t": 3}},
        "others": {"r": 0, "rs": 0, "c": 0, "n": 0, "t": 0},
        # `partnerTry: 0.0` = ortak maliyeti ÖLÇÜLDÜ ve sıfır (P4). Alan
        # olmasa gün "ölçülmedi" sayılır, marj −1 döner ve aşağıdaki iki
        # terimli matematik sınanamaz olurdu.
        "shared": {"c": 0.01, "n": 1}, "partnerTry": 0.0, "count": 1}
    depo.docs[f"adminEconomics/{g2}"] = {
        "date": g2,
        "users": {"u1": {"r": -1.0, "rs": 2.5, "c": 0, "n": 0, "t": 0}},
        "others": {"r": 0, "rs": 0, "c": 0, "n": 0, "t": 0},
        "shared": {"c": 0, "n": 0}, "partnerTry": 0.0, "count": 1}

    sonuc = admin_service.economics(days=30, env="PRODUCTION")

    u1 = next(s for s in sonuc["users"] if s["uid"] == "u1")
    assert u1["displayName"] == "Ayşe"          # get_all ile ad
    assert u1["revenueUsd"] == pytest.approx(3.99)   # 4.99 − 1.00 iade
    assert u1["sandboxUsd"] == pytest.approx(2.5)
    assert u1["aiCostUsd"] == pytest.approx(0.05)
    assert u1["marginUsd"] == pytest.approx(3.99 * 0.85 - 0.05)
    assert sonuc["totals"]["sharedAiCostUsd"] == pytest.approx(0.01)
    assert sonuc["totals"]["aiCostUsd"] == pytest.approx(0.06)
    assert sonuc["coverage"] == {"daysFound": 2, "oldest": g1}
    # Hareketsiz kullanıcı rollup'ta yok → satır da yok (top-N tablosu).
    assert all(s["uid"] != "u2" for s in sonuc["users"])

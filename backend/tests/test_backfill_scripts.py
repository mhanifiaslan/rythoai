"""Backfill betikleri (AD11): prova varsayılan, idempotent (ikinci koşu 0
yazım), sahte Firestore ile uçtan uca."""
from __future__ import annotations

import datetime as dt
import importlib.util
import sys
from pathlib import Path

import pytest

from _sahte_firestore import SahteFirestore
from services import stats_service

_SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
_SIMDI = dt.datetime.now(dt.timezone.utc)


def _yukle(ad: str):
    if str(_SCRIPTS) not in sys.path:
        sys.path.insert(0, str(_SCRIPTS))
    spec = importlib.util.spec_from_file_location(ad, _SCRIPTS / f"{ad}.py")
    modul = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modul)
    return modul


def _yazim(depo: SahteFirestore) -> int:
    return len(depo.yazimlar)


# --- backfill_revenue_env -------------------------------------------------------

@pytest.fixture()
def gelir_depo():
    return SahteFirestore({
        "revenueEvents/e1": {"uid": "u1", "eventType": "INITIAL_PURCHASE",
                             "price": 4.99, "at": _SIMDI},
        "revenueEvents/e2": {"uid": "u1", "eventType": "REFUND", "price": 1.0,
                             "at": _SIMDI},
        "revenueEvents/e3": {"uid": "u2", "eventType": "RENEWAL", "price": 2.0,
                             "environment": "PRODUCTION", "monetary": True,
                             "at": _SIMDI},
        "revenueEvents/e4": {"uid": "u2", "eventType": "CANCELLATION",
                             "price": 0, "at": _SIMDI},
    })


def test_revenue_env_prova_ve_apply(gelir_depo):
    m = _yukle("backfill_revenue_env")
    prova = m.etiketle(gelir_depo, "SANDBOX")
    assert prova["yazilacak"] == 3 and _yazim(gelir_depo) == 0
    uygulanan = m.etiketle(gelir_depo, "SANDBOX", apply=True)
    assert uygulanan["yazilan"] == 3
    assert gelir_depo.docs["revenueEvents/e1"]["environment"] == "SANDBOX"
    assert gelir_depo.docs["revenueEvents/e1"]["monetary"] is True
    assert gelir_depo.docs["revenueEvents/e4"]["monetary"] is False
    assert gelir_depo.docs["revenueEvents/e3"]["environment"] == "PRODUCTION"
    # İkinci koşu: 0 yazım.
    n = _yazim(gelir_depo)
    assert m.etiketle(gelir_depo, "SANDBOX", apply=True)["yazilan"] == 0
    assert _yazim(gelir_depo) == n


def test_revenue_totals_mutlak_ve_idempotent(gelir_depo):
    m = _yukle("backfill_revenue_env")
    m.etiketle(gelir_depo, "SANDBOX", apply=True)
    # Eski/yanlış birikim: mutlak yazım düzeltmeli.
    gelir_depo.docs["users/u1/private/revenueTotals"] = {
        "SANDBOX": {"grossUsd": 99.0, "refundsUsd": 0, "events": 9}}
    assert m.toplamlar(gelir_depo)["yazilacak"] == 2
    assert m.toplamlar(gelir_depo, apply=True)["yazilan"] == 2
    assert gelir_depo.docs["users/u1/private/revenueTotals"] == {
        "SANDBOX": {"grossUsd": 4.99, "refundsUsd": 1.0, "events": 2}}
    assert gelir_depo.docs["users/u2/private/revenueTotals"] == {
        "PRODUCTION": {"grossUsd": 2.0, "refundsUsd": 0.0, "events": 1}}
    n = _yazim(gelir_depo)
    assert m.toplamlar(gelir_depo, apply=True)["yazilan"] == 0
    assert _yazim(gelir_depo) == n


# --- backfill_search_fields --------------------------------------------------------

def test_search_fields_diff_only(monkeypatch):
    depo = SahteFirestore({
        "users/u1": {"displayName": "İpek", "email": "I@X.com"},
        "users/u2": {"displayName": "Can", "nameLower": "can",
                     "emailLower": "", "usernameLower": "", "plan": "free"},
        "users/u1/private/subscription": {
            "active": True, "expiresAt": _SIMDI + dt.timedelta(days=5),
            "productId": "rytho_plus_monthly", "isTrial": True},
        "users/u2/private/subscription": {
            "active": True, "expiresAt": _SIMDI - dt.timedelta(days=5),
            "productId": "rytho_plus_monthly"},
    })
    m = _yukle("backfill_search_fields")
    bayraklar = {"u1": False, "u2": True}
    prova = m.calistir(depo, bayraklar=bayraklar)
    assert prova["yazilacak"] == 2 and _yazim(depo) == 0
    assert m.calistir(depo, apply=True, bayraklar=bayraklar)["yazilan"] == 2
    u1 = depo.docs["users/u1"]
    assert u1["nameLower"] == "ipek" and u1["emailLower"] == "ı@x.com"
    assert u1["plan"] == "trial" and u1["planProduct"] == "rytho_plus_monthly"
    assert u1["planAt"] and u1["authDisabled"] is False
    u2 = depo.docs["users/u2"]
    assert u2["plan"] == "free" and u2["authDisabled"] is True
    assert "planAt" not in u2            # plan değişmedi → damga yok
    n = _yazim(depo)
    assert m.calistir(depo, apply=True, bayraklar=bayraklar)["yazilan"] == 0
    assert _yazim(depo) == n
    # Auth listesi yoksa alan atlanır, gerisi yine idempotent.
    assert m.calistir(depo, apply=True, bayraklar=None)["yazilan"] == 0


def test_search_fields_createdat_yalniz_auth_damgasiyla_dolar():
    """`createdAt` alanı OLMAYAN doküman panelin `order_by("createdAt")`
    listesinden düşüyor: onboarding'i yarım bırakan hesap "kim takıldı"
    sorusunun cevabı olduğu halde görünmüyordu. Damga UYDURULMAZ — Auth'ta
    karşılığı olmayan doküman alansız KALIR; `simdi` yazılsa kayıt tarihi
    bugüne kayar ve core/entitlements 3 günlük denemeyi sıfırdan açardı. Var
    olan damga da ezilmez."""
    dogum = dt.datetime(2026, 9, 1, 8, 30, tzinfo=dt.timezone.utc)
    onceki = dt.datetime(2026, 1, 2, 3, 4, tzinfo=dt.timezone.utc)
    ayna = {"emailLower": "", "usernameLower": "", "plan": "free"}
    depo = SahteFirestore({
        "users/yarim": {"displayName": "Can", "nameLower": "can", **ayna},
        "users/damgasiz": {"displayName": "Ece", "nameLower": "ece", **ayna},
        "users/tam": {"displayName": "Ali", "nameLower": "ali",
                      "createdAt": onceki, **ayna},
    })
    m = _yukle("backfill_search_fields")
    sonuc = m.calistir(depo, apply=True, kayit_damgalari={"yarim": dogum})
    assert sonuc["kayit"] == "ok" and sonuc["yazilan"] == 1
    assert depo.docs["users/yarim"]["createdAt"] == dogum
    # Auth'ta damgası olmayan hesap: alan UYDURULMAZ.
    assert "createdAt" not in depo.docs["users/damgasiz"]
    # Var olan damga ezilmez (3 günlük deneme penceresi ona bağlı).
    assert depo.docs["users/tam"]["createdAt"] == onceki
    # Diff-only: ikinci koşu hiç yazmaz.
    n = _yazim(depo)
    assert m.calistir(depo, apply=True,
                      kayit_damgalari={"yarim": dogum})["yazilan"] == 0
    assert _yazim(depo) == n
    # Auth okunamadı yolu: alan hiç yazılmaz ve özet bunu SÖYLER (prova
    # çıktısı "atlandı" demezse operatör sessiz atlamayı göremez).
    bos = m.calistir(depo, apply=True)
    assert bos["yazilan"] == 0 and bos["kayit"] == "atlandı"
    assert "createdAt" not in depo.docs["users/damgasiz"]


# --- backfill_usage_totals ----------------------------------------------------------

def test_usage_totals_mutlak(monkeypatch):
    depo = SahteFirestore({
        "usageEvents/x1": {"uid": "u1", "feature": "chat", "estCostUsd": 0.01,
                           "promptTokens": 10, "outputTokens": 5,
                           "thinkingTokens": 1, "at": _SIMDI},
        "usageEvents/x2": {"uid": "u1", "feature": "natal", "estCostUsd": 0.02,
                           "promptTokens": 20, "outputTokens": 5,
                           "at": _SIMDI - dt.timedelta(hours=1)},
        "usageEvents/x3": {"uid": None, "feature": "horoscope",
                           "estCostUsd": 9.0, "at": _SIMDI},
        "users/u1/private/usageTotals": {"calls": 999, "estCostUsd": 5.0},
    })
    m = _yukle("backfill_usage_totals")
    assert m.calistir(depo)["yazilacak"] == 1 and _yazim(depo) == 0
    assert m.calistir(depo, apply=True)["yazilan"] == 1
    t = depo.docs["users/u1/private/usageTotals"]
    assert t["calls"] == 2 and t["estCostUsd"] == pytest.approx(0.03)
    assert t["promptTokens"] == 30 and t["outputTokens"] == 10
    assert t["thinkingTokens"] == 1
    assert t["byFeature"] == {"chat": {"calls": 1, "estCostUsd": 0.01},
                              "natal": {"calls": 1, "estCostUsd": 0.02}}
    assert t["lastAt"] == _SIMDI
    assert "users/None/private/usageTotals" not in depo.docs
    n = _yazim(depo)
    assert m.calistir(depo, apply=True)["yazilan"] == 0
    assert _yazim(depo) == n


# --- backfill_rollups -------------------------------------------------------------

def test_rollups_prova_yazmaz_apply_gunleri_toplar(monkeypatch):
    depo = SahteFirestore()
    cagrilar: list = []
    monkeypatch.setattr(stats_service, "collect",
                        lambda gun, snapshot=True: cagrilar.append((gun, snapshot)))
    m = _yukle("backfill_rollups")
    bugun = _SIMDI.date()
    prova = m.calistir(depo, bugun - dt.timedelta(days=2), bugun + dt.timedelta(days=3))
    assert prova["incelenen"] == 3 and cagrilar == []
    m.calistir(depo, bugun - dt.timedelta(days=2), bugun, apply=True)
    assert cagrilar == [(bugun - dt.timedelta(days=2), False),
                        (bugun - dt.timedelta(days=1), False), (bugun, True)]
    with pytest.raises(SystemExit):
        m.calistir(depo, bugun, bugun - dt.timedelta(days=1))


# --- cleanup_orphan_users ---------------------------------------------------------
#
# B9'un ARTIĞI: kusur kodda kapatıldı (aynalar artık `update`), ama üretimde
# bıraktığı yetim dokümanlar kendiliğinden gitmiyor. Betik geri alınamaz bir
# silme yapıyor, o yüzden buradaki iddiaların çoğu SİLMEMEYE dair.

@pytest.fixture()
def yetim_depo():
    return SahteFirestore({
        # Auth'ta VAR — gerçek kullanıcı, dokunulmamalı.
        "users/gercek": {"language": "tr", "appBuild": 46,
                         "createdAt": _SIMDI},
        # Auth'ta YOK, çıplak iskelet — B9'un ürettiği kayıt.
        "users/yetim1": {"appBuild": 41},
        "users/yetim2": {"appBuild": 41},
        # Auth'ta YOK ama alt ağacı var — çıplak silme onu bırakır.
        "users/altli": {"appBuild": 41},
    })


def _altlar(_client, uid: str):
    return ["private"] if uid == "altli" else []


def test_yetim_temizligi_prova_silmez_apply_yalniz_yetimi_siler(yetim_depo):
    m = _yukle("cleanup_orphan_users")
    prova = m.calistir(yetim_depo, auth_uids={"gercek"},
                       alt_koleksiyonlar=_altlar)
    assert prova["incelenen"] == 4 and prova["silinecek"] == 2
    assert prova["korunan"] == 1
    assert _yazim(yetim_depo) == 0, "prova kipinde silme olmamalı"

    uygulanan = m.calistir(yetim_depo, auth_uids={"gercek"}, apply=True,
                           alt_koleksiyonlar=_altlar)
    assert uygulanan["silinen"] == 2
    assert set(yetim_depo.docs) == {"users/gercek", "users/altli"}
    # İkinci koşu: silinecek kalmadı.
    assert m.calistir(yetim_depo, auth_uids={"gercek"}, apply=True,
                      alt_koleksiyonlar=_altlar)["silinen"] == 0


def test_yetim_temizligi_alt_koleksiyonluyu_SILMEZ(yetim_depo):
    """Üst dokümanı silmek alt koleksiyonları silmez; `private/**` yerinde
    kalır ve `collection_group` sorgularına görünmeye devam eder. Böyle bir
    kayıt gerçek silme ister (panelin 'Hesabı sil' ucu)."""
    m = _yukle("cleanup_orphan_users")
    m.calistir(yetim_depo, auth_uids={"gercek"}, apply=True,
               alt_koleksiyonlar=_altlar)
    assert "users/altli" in yetim_depo.docs


def test_yetim_temizligi_alt_koleksiyon_okunamazsa_SILMEZ(yetim_depo):
    """"Bilinmiyor" = VAR sayılır: emin olmadığımız dokümanı silmek
    arkasında görünmez bir alt ağaç bırakma riski demek.

    İKİ iddia var ve ikincisi zorunlu: yalnız `_alt_koleksiyonlar`ın
    `["<okunamadı>"]` döndüğünü ölçmek testin ADINI karşılamaz — `calistir`
    içindeki `if altlar` kapısı "okunamadı"yı eleyecek biçimde daraltılsa
    (`altlar != ["<okunamadı>"]` gibi makul görünen bir sadeleştirme) bu
    test YEŞİL kalır ve emniyet sessizce kaybolurdu.
    """
    m = _yukle("cleanup_orphan_users")

    class _Patlayan:
        def collection(self, ad):
            raise RuntimeError("izin yok")

    assert m._alt_koleksiyonlar(_Patlayan(), "yetim1") == ["<okunamadı>"]

    # Okuma HER uid için düşüyor: apply olsa bile tek doküman silinmemeli.
    def _okunamadi(_client, _uid):
        return ["<okunamadı>"]

    sonuc = m.calistir(yetim_depo, auth_uids={"gercek"}, apply=True,
                       alt_koleksiyonlar=_okunamadi)
    assert sonuc["silinen"] == 0 and sonuc["korunan"] == 3
    assert len(yetim_depo.docs) == 4 and _yazim(yetim_depo) == 0


@pytest.mark.parametrize("auth", [None, set()])
def test_yetim_temizligi_auth_listesi_yoksa_HICBIR_SEY_silmez(yetim_depo, auth):
    """En tehlikeli hâl. `list_users` düşerse ya da boş dönerse her
    kullanıcı "yetim" görünür ve betik GERÇEK hesapların profillerini
    silerdi. Boş liste de hata sayılır: canlı projede en az bir hesap
    (sahibin kendisi) vardır."""
    m = _yukle("cleanup_orphan_users")
    with pytest.raises(SystemExit):
        m.calistir(yetim_depo, auth_uids=auth, apply=True,
                   alt_koleksiyonlar=_altlar)
    assert len(yetim_depo.docs) == 4 and _yazim(yetim_depo) == 0

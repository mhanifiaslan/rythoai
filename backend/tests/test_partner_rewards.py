"""Ortaklık ödülü (OP-turu) — zarar ve dolandırıcılık kapıları.

Her iddia gerçek para ödemesi üretebilecek bir yolu kapatıyor. Ödül
kuralının beş koşulu (PRODUCTION · doğru olay türü · parasal · deneme
değil · atıf var) tek tek sınanıyor, çünkü biri gevşerse kayıp sessizdir:
panel "hakediş" gösterir, sahip öder, yanlış olduğu ancak mutabakatta
anlaşılır.

Çalıştırma:
    .venv\\Scripts\\python.exe -m pytest tests/test_partner_rewards.py -q
"""
from __future__ import annotations

import datetime as dt

import pytest

from api.billing import _ortaklik_hakedisi
from services import partner_service as ps


# --- Sorgu destekli sahte Firestore (test_partner_codes.py sahtesinin
# --- genişletilmiş hâli: where/limit/stream + snapshot.reference) --------

class SahteAnlik:
    def __init__(self, depo, yol, data):
        self._depo = depo
        self._yol = yol
        self._data = data

    @property
    def exists(self):
        return self._data is not None

    @property
    def id(self):
        return self._yol.rsplit("/", 1)[-1]

    @property
    def reference(self):
        return SahteDoc(self._depo, self._yol)

    def to_dict(self):
        return dict(self._data) if self._data else {}


class SahteDoc:
    def __init__(self, depo, yol):
        self._depo = depo
        self._yol = yol

    @property
    def id(self):
        return self._yol.rsplit("/", 1)[-1]

    def get(self, transaction=None):
        return SahteAnlik(self._depo, self._yol, self._depo.get(self._yol))

    def set(self, data, merge=False):
        mevcut = dict(self._depo.get(self._yol) or {}) if merge else {}
        mevcut.update(data)
        self._depo[self._yol] = mevcut

    def update(self, data):
        mevcut = dict(self._depo.get(self._yol) or {})
        mevcut.update(data)
        self._depo[self._yol] = mevcut

    def create(self, data):
        if self._yol in self._depo:
            raise RuntimeError("already-exists")
        self._depo[self._yol] = dict(data)

    def collection(self, ad):
        return SahteKoleksiyon(self._depo, f"{self._yol}/{ad}")


def _karsilastir(deger, op, hedef):
    if deger is None:
        return False
    if op == "==":
        return deger == hedef
    if op == "<=":
        return deger <= hedef
    if op == ">=":
        return deger >= hedef
    raise AssertionError(f"desteklenmeyen operator: {op}")


class SahteKoleksiyon:
    def __init__(self, depo, yol, suzgecler=None, tavan=None):
        self._depo = depo
        self._yol = yol
        self._suzgecler = list(suzgecler or [])
        self._tavan = tavan

    def document(self, ad=None):
        if ad is None:
            # Otomatik kimlik BENZERSİZ olmalı: aynı koleksiyona iki ödeme
            # yazılınca sabit bir ad ikincisini birincinin üstüne yazar ve
            # bakiye testi sahte bir sonuç verir.
            ad = f"oto-{len(self._depo)}"
        return SahteDoc(self._depo, f"{self._yol}/{ad}")

    def where(self, filter=None, **_):
        # google.cloud.firestore_v1 FieldFilter: alan/op/deger
        alan = getattr(filter, "field_path", None) or filter._field_path
        op = getattr(filter, "op_string", None) or filter._op_string
        deger = getattr(filter, "value", None)
        if deger is None:
            deger = filter._value
        return SahteKoleksiyon(self._depo, self._yol,
                               self._suzgecler + [(alan, op, deger)],
                               self._tavan)

    def limit(self, n):
        return SahteKoleksiyon(self._depo, self._yol, self._suzgecler, n)

    def stream(self):
        onek = self._yol + "/"
        sonuc = []
        for yol, veri in list(self._depo.items()):
            if not yol.startswith(onek) or "/" in yol[len(onek):]:
                continue
            if all(_karsilastir(veri.get(a), o, d)
                   for a, o, d in self._suzgecler):
                sonuc.append(SahteAnlik(self._depo, yol, veri))
        return sonuc[:self._tavan] if self._tavan else sonuc


class SahteTransaction:
    def set(self, ref, data):
        ref.set(data)

    def update(self, ref, data):
        ref.update(data)


class SahteClient:
    def __init__(self, depo):
        self._depo = depo

    def collection(self, ad):
        return SahteKoleksiyon(self._depo, ad)

    def transaction(self):
        return SahteTransaction()


@pytest.fixture()
def depo(monkeypatch):
    veriler: dict = {}
    client = SahteClient(veriler)
    monkeypatch.setattr(ps.firestore_client, "get_client", lambda: client)
    monkeypatch.setattr("google.cloud.firestore.transactional", lambda f: f)
    veriler["_client"] = client
    return veriler


def _ortak(depo, pid="p-1", **ek):
    veri = {"name": "Ortak", "active": True,
            "rewardModel": ps.REWARD_MODEL_FIXED, "rewardTry": 30.0}
    veri.update(ek)
    depo[f"partners/{pid}"] = veri


def _olay(**ek):
    e = {"product_id": "rytho_plus_monthly", "event_timestamp_ms": None}
    e.update(ek)
    return e


def _tetikle(depo, uid="u1", *, tur="INITIAL_PURCHASE", ortam="PRODUCTION",
             parasal=True, urun="rytho_plus_monthly", donem=None,
             partner="p-1"):
    _ortaklik_hakedisi(depo["_client"], uid,
                       _olay(product_id=urun, period_type=donem),
                       tur, ortam, partner, parasal, "evt-1")


# --- Ödül DOĞURAN yol ---------------------------------------------------

def test_ilk_abonelik_hakedis_acar(depo):
    _ortak(depo)
    _tetikle(depo)
    kayit = depo["partnerQualifications/u1"]
    assert kayit["status"] == ps.STATUS_PENDING
    assert kayit["partnerId"] == "p-1"
    assert kayit["rewardTry"] == 30.0
    # 15 günlük pencere.
    assert (kayit["maturesAt"] - kayit["purchasedAt"]).days == \
        ps.MATURATION_DAYS


def test_denemeden_donusen_abone_de_hakedis_acar(depo):
    """`INITIAL_PURCHASE`e bakmak YETMEZ: mağaza denemesi açılırsa ödeyen
    aboneye dönüşüm `TRIAL_CONVERTED` ile gelir."""
    _ortak(depo)
    _tetikle(depo, tur="TRIAL_CONVERTED")
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_PENDING


# --- Ödül ÜRETMEYEN yollar (zarar kapıları) -----------------------------

def test_jeton_paketi_hakedis_acmaz(depo):
    _ortak(depo)
    _tetikle(depo, tur="NON_RENEWING_PURCHASE", urun="rytho_tokens_small")
    assert "partnerQualifications/u1" not in depo


def test_sandbox_hakedis_acmaz(depo):
    """Canlıda 1756 SANDBOX olayı var; süzülmezse sahte gelirden para ödenir."""
    _ortak(depo)
    _tetikle(depo, ortam="SANDBOX")
    assert "partnerQualifications/u1" not in depo


def test_deneme_baslangici_hakedis_acmaz(depo):
    """`period_type=TRIAL` olan INITIAL_PURCHASE `monetary=True` gelir —
    yani `monetary` tek başına para geçtiğini KANITLAMAZ."""
    _ortak(depo)
    _tetikle(depo, donem="TRIAL")
    assert "partnerQualifications/u1" not in depo


def test_parasal_olmayan_olay_hakedis_acmaz(depo):
    _ortak(depo)
    _tetikle(depo, parasal=False)
    assert "partnerQualifications/u1" not in depo


def test_atifsiz_kullanici_hakedis_acmaz(depo):
    _ortak(depo)
    _tetikle(depo, partner=None)
    assert "partnerQualifications/u1" not in depo


def test_pasif_ortak_hakedis_acmaz(depo):
    _ortak(depo, active=False)
    _tetikle(depo)
    assert "partnerQualifications/u1" not in depo


def test_gecersiz_odul_tutari_hakedis_acmaz(depo):
    """Bozuk `rewardTry` sessizce 0 ödeme yazmak yerine kaydı hiç açmaz."""
    _ortak(depo, rewardTry=0)
    _tetikle(depo)
    assert "partnerQualifications/u1" not in depo


def test_yenileme_ikinci_kayit_acmaz(depo):
    """Doküman kimliği uid olduğu için kural YAPISAL — sorguya bağlı değil."""
    _ortak(depo)
    _tetikle(depo)
    ilk = dict(depo["partnerQualifications/u1"])
    _tetikle(depo, tur="RENEWAL")
    assert depo["partnerQualifications/u1"] == ilk


def test_ikinci_abonelik_ikinci_odul_vermez(depo):
    _ortak(depo)
    _tetikle(depo)
    ilk = dict(depo["partnerQualifications/u1"])
    # Aylar sonra tekrar abone olsa bile yeni INITIAL_PURCHASE gelir.
    _tetikle(depo, tur="INITIAL_PURCHASE")
    assert depo["partnerQualifications/u1"] == ilk


def test_odul_tutari_dondurulur(depo):
    """Panelden tutar değişince GEÇMİŞ hakediş yeniden fiyatlanmaz."""
    _ortak(depo, rewardTry=30.0)
    _tetikle(depo, uid="u1")
    depo["partners/p-1"]["rewardTry"] = 90.0
    _tetikle(depo, uid="u2")
    assert depo["partnerQualifications/u1"]["rewardTry"] == 30.0
    assert depo["partnerQualifications/u2"]["rewardTry"] == 90.0


# --- İade ve olgunlaşma -------------------------------------------------

def test_iade_bekleyen_hakedisi_iptal_eder(depo):
    _ortak(depo)
    _tetikle(depo)
    _tetikle(depo, tur="REFUND")
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_VOID


def test_iptal_hakedisi_DUSURMEZ(depo):
    """`CANCELLATION` = otomatik yenileme kapatıldı, para iadesi DEĞİL.
    O ayın parası bizde kaldı; ortak o aboneyi gerçekten kazandı."""
    _ortak(depo)
    _tetikle(depo)
    _tetikle(depo, tur="CANCELLATION")
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_PENDING


def test_15_gun_dolmadan_kesinlesmez(depo):
    _ortak(depo)
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["purchasedAt"] + \
        dt.timedelta(days=ps.MATURATION_DAYS - 1)
    sayac = ps.mature_qualifications(now=simdi)
    assert sayac["taranan"] == 0
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_PENDING


def test_15_gun_sonra_kesinlesir(depo):
    _ortak(depo)
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    sayac = ps.mature_qualifications(now=simdi)
    assert sayac["kesinlesen"] == 1
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_QUALIFIED


def test_olgunlastirma_kacirilan_iadeyi_yakalar(depo):
    """Webhook kaçırılmış olabilir: olgunlaşmada gelir defteri yeniden
    taranır ve iade bulunursa hakediş yine iptal olur."""
    _ortak(depo)
    _tetikle(depo)
    alindi = depo["partnerQualifications/u1"]["purchasedAt"]
    depo["revenueEvents/geç-iade"] = {
        "uid": "u1", "eventType": "REFUND",
        "at": alindi + dt.timedelta(days=3)}
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    sayac = ps.mature_qualifications(now=simdi)
    assert sayac["iptal"] == 1
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_VOID


def test_olgunlastirma_idempotent(depo):
    """İkinci koşu aynı kaydı `pending` bulamaz — `Increment` değil,
    durum alanı üzerinden."""
    _ortak(depo)
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)
    ikinci = ps.mature_qualifications(now=simdi)
    assert ikinci["taranan"] == 0


# --- Dolandırıcılık kapıları --------------------------------------------

def test_ortak_kendi_kodunu_kullanamaz(depo, monkeypatch):
    _ortak(depo, uid="ortak-uid")
    depo["partnerCodes/ORTAK10"] = {
        "partnerId": "p-1", "bonusTokens": 0, "maxRedemptions": None,
        "redemptionCount": 0, "expiresAt": None, "active": True}
    monkeypatch.setattr(ps.wallet, "credit_promo", lambda *a: True)
    with pytest.raises(ps.RedeemError) as h:
        ps.redeem("ortak-uid", "ORTAK10")
    assert h.value.status == 403
    assert h.value.reason == "self_referral"
    assert "users/ortak-uid/private/attribution" not in depo
    assert depo["partnerCodes/ORTAK10"]["redemptionCount"] == 0


def test_baskasi_ayni_kodu_kullanabilir(depo, monkeypatch):
    _ortak(depo, uid="ortak-uid")
    depo["partnerCodes/ORTAK10"] = {
        "partnerId": "p-1", "bonusTokens": 0, "maxRedemptions": None,
        "redemptionCount": 0, "expiresAt": None, "active": True}
    monkeypatch.setattr(ps.wallet, "credit_promo", lambda *a: True)
    ps.redeem("baska-uid", "ORTAK10")
    assert depo["users/baska-uid/private/attribution"]["partnerId"] == "p-1"


# --- Ödeme kapıları -----------------------------------------------------

def test_odeme_bakiyeyi_asamaz(depo):
    _ortak(depo)
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)            # bakiye 30
    with pytest.raises(ps.RedeemError) as h:
        ps.add_payout("p-1", 31.0, "TRY", "fazla")
    assert h.value.reason == "exceeds_balance"
    ps.add_payout("p-1", 30.0, "TRY", "tam")       # sınırda geçer


def test_negatif_duzeltme_gerekce_ister(depo):
    _ortak(depo)
    with pytest.raises(ps.RedeemError) as h:
        ps.add_payout("p-1", -10.0, "TRY", "")
    assert h.value.reason == "reason_required"
    ps.add_payout("p-1", -10.0, "TRY", "iade duzeltmesi")


def test_sifir_odeme_reddedilir(depo):
    _ortak(depo)
    with pytest.raises(ps.RedeemError) as h:
        ps.add_payout("p-1", 0, "TRY", "bos")
    assert h.value.reason == "invalid_amount"


# --- Ortağın kendi panosu: sızıntı yok ----------------------------------

def test_ortak_panosu_isletme_verisi_sizdirmaz(depo):
    _ortak(depo, uid="ortak-uid")
    _tetikle(depo)
    depo["revenueEvents/e1"] = {
        "partnerId": "p-1", "environment": "PRODUCTION", "monetary": True,
        "eventType": "INITIAL_PURCHASE", "price": 3.0, "uid": "u1"}
    gorunum = ps.partner_self_view("p-1")
    assert "attributedGrossUsd" not in gorunum
    assert "attributedEvents" not in gorunum
    assert "uid" not in gorunum
    # Ortağın görmesi gerekenler duruyor.
    assert gorunum["pendingCount"] == 1
    assert gorunum["rewardTry"] == 30.0


def test_uid_ile_ortak_bulunur(depo):
    _ortak(depo, uid="ortak-uid")
    assert ps.partner_id_for_uid("ortak-uid") == "p-1"
    assert ps.partner_id_for_uid("yabanci") is None


# --- Yetki sınırı: ortak ≠ yönetici -------------------------------------

def test_ortak_claimi_yonetim_kapisini_GECMEZ():
    """Bu turun en kritik güvenlik iddiası.

    `"partner"` [core.auth.ROLES]'a eklenseydi `require_admin`'in
    `user.role in ROLES` kapısını geçer ve bir ortak token'ı tüm kullanıcı
    listesini, geliri, sistemi ve DİĞER ortakların detaylarını açardı.
    Ortaklık bu yüzden ayrı bir claim boyutu.
    """
    from fastapi import HTTPException
    from core import auth

    coz = auth._ortak_coz({"partner": True, "partnerId": "p-1"})
    assert coz == "p-1"
    ortak = auth.AuthUser(uid="o1", partner_id=coz)

    assert ortak.admin is False
    assert ortak.role is None
    assert "partner" not in auth.ROLES

    with pytest.raises(HTTPException) as h:
        auth.require_admin(ortak)
    assert h.value.status_code == 403
    # Kendi kapısından geçer.
    assert auth.require_partner(ortak) is ortak


def test_partnerId_tek_basina_yetki_VERMEZ():
    """`_rol_coz`un disiplini: kapı ayırt edici bayrağa dayanır, taşınabilir
    bir kimliğe değil. `partner: true` olmadan `partnerId` yok sayılır."""
    from core import auth
    assert auth._ortak_coz({"partnerId": "p-1"}) is None
    assert auth._ortak_coz({"partner": False, "partnerId": "p-1"}) is None


def test_ortaksiz_kullanici_ortak_kapisindan_gecemez():
    from fastapi import HTTPException
    from core import auth
    sade = auth.AuthUser(uid="u1")
    with pytest.raises(HTTPException) as h:
        auth.require_partner(sade)
    assert h.value.status_code == 403


def test_yonetici_de_ortak_kapisindan_gecemez():
    """Simetri: admin claim'i ortak panosuna erişim vermez."""
    from fastapi import HTTPException
    from core import auth
    yonetici = auth.AuthUser(uid="a1", admin=True, role="owner")
    with pytest.raises(HTTPException):
        auth.require_partner(yonetici)


def test_huni_ve_bakiye(depo):
    _ortak(depo)
    depo["partnerCodes/K1"] = {"partnerId": "p-1", "redemptionCount": 7,
                               "active": True}
    _tetikle(depo, uid="u1")
    _tetikle(depo, uid="u2")
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)
    detay = ps.partner_detail("p-1")
    assert detay["referredUsers"] == 7
    assert detay["qualifiedCount"] == 2
    assert detay["earnedTry"] == 60.0
    assert detay["balanceTry"] == 60.0

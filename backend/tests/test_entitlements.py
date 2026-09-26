"""Faz 2 testleri: yetki katmani, kotalar ve RevenueCat webhook'u.

Calistirma:  .venv\\Scripts\\python.exe -m pytest tests/test_entitlements.py -q
"""
import datetime as dt

import pytest
from fastapi.testclient import TestClient

from core import config, entitlements

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

DOGUM = {"name": "Ada", "year": 1994, "month": 8, "day": 11,
         "hour": 9, "minute": 30, "city": "Izmir"}


@pytest.fixture(autouse=True)
def zorlamayi_kapat(monkeypatch):
    """FORCE_PLUS acikken tum kapilar acilir; testler kapali varsayar."""
    monkeypatch.setattr(entitlements, "FORCE_PLUS", False)


def _basliklar(etiket: str) -> dict:
    return {"Authorization": f"Bearer test-{etiket}"}


# --------------------------------------------------------------------------
# Abonelik durumu
# --------------------------------------------------------------------------

def test_firestore_yokken_abone_sayilmaz(monkeypatch):
    """Guvenli taraf ucretsizdir: durum okunamiyorsa ucretli icerik acilmaz."""
    monkeypatch.setattr(entitlements.firestore_client, "get_client", lambda: None)
    assert entitlements.is_subscriber("kimse") is False


def test_suresi_gecmis_abonelik_aktif_sayilmaz(monkeypatch):
    gecmis = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)
    monkeypatch.setattr(entitlements, "get_subscription",
                        lambda uid: {"active": False, "expired": True})
    assert entitlements.is_subscriber("x") is False


def test_force_plus_tum_kapilari_acar(monkeypatch):
    """Sadece gelistirme icin; uretimde 0 olmali."""
    monkeypatch.setattr(entitlements, "FORCE_PLUS", True)
    assert entitlements.is_subscriber("kimse") is True


# --------------------------------------------------------------------------
# 3 gunluk deneme (OT6, kullanici karari: kartsiz, sunucu tarafli)
# --------------------------------------------------------------------------

class _SahteZaman:
    """createdAt gibi davranan minimal nesne (Firestore Timestamp arayuzu)."""

    def __init__(self, ts: float):
        self._ts = ts

    def timestamp(self) -> float:
        return self._ts


def _in_trial_with_age(monkeypatch, saat_once: float | None):
    from core import cache
    from services import profile_service

    monkeypatch.setattr(cache, "get", lambda k: None)
    monkeypatch.setattr(cache, "set", lambda *a, **k: None)
    if saat_once is None:
        profil = {}
    else:
        simdi = dt.datetime.now(dt.timezone.utc).timestamp()
        profil = {"createdAt": _SahteZaman(simdi - saat_once * 3600)}
    monkeypatch.setattr(profile_service, "get_profile", lambda uid: profil)
    return entitlements.in_trial("deneme-uid")


def test_deneme_ilk_uc_gun_acik(monkeypatch):
    assert _in_trial_with_age(monkeypatch, saat_once=2) is True
    assert _in_trial_with_age(monkeypatch, saat_once=71) is True


def test_deneme_uc_gun_sonra_ve_alan_yokken_kapali(monkeypatch):
    """Suresi dolan hesap ucretsiz katmana doner; `createdAt` olmayan eski
    hesaplar HIC denemeye girmez (okunamazsa ucretsiz doktrini)."""
    assert _in_trial_with_age(monkeypatch, saat_once=73) is False
    assert _in_trial_with_age(monkeypatch, saat_once=None) is False


def test_deneme_kullanicisi_abone_sayilir(monkeypatch):
    """OT6'nin ozu: is_subscriber TEK kapi — deneme donemi require_plus
    dahil TUM Plus yollarini acar; abonelik pasifken bile."""
    monkeypatch.setattr(entitlements, "get_subscription",
                        lambda uid: {"active": False})
    monkeypatch.setattr(entitlements, "in_trial", lambda uid: True)
    assert entitlements.is_subscriber("yeni-hesap") is True
    monkeypatch.setattr(entitlements, "in_trial", lambda uid: False)
    assert entitlements.is_subscriber("yeni-hesap") is False


@uygulama_gerekir
def test_consent_deneme_jetonunu_bir_kez_yazar(monkeypatch):
    """Onboarding bitisindeki /account/consent deneme kullanicisina TEK
    SEFERLIK hos geldin jetonu yazar; ikinci cagri (yasal metin yeniden
    onayi) tekrar yazmaz — defter kimligi sabit (idempotent)."""
    from core import wallet
    from services import consent_service

    monkeypatch.setattr(consent_service, "grant_terms_consent",
                        lambda uid, version, lang: True)
    monkeypatch.setattr(entitlements, "in_trial", lambda uid: True)

    yuklenen: list = []

    def sahte_promo(uid, code, amount):
        ilk = (uid, code) not in yuklenen
        if ilk:
            yuklenen.append((uid, code))
        return ilk

    monkeypatch.setattr(wallet, "credit_promo", sahte_promo)

    with TestClient(app) as client:
        for _ in range(2):
            yanit = client.post("/api/v1/account/consent", json={},
                                headers=_basliklar("deneme"))
            assert yanit.status_code == 200
    assert yuklenen == [("dev-user", wallet.TRIAL_PROMO_CODE)]


# --------------------------------------------------------------------------
# Ucretli uclar
# --------------------------------------------------------------------------

@uygulama_gerekir
@pytest.mark.parametrize("yol,govde", [
    ("/api/v1/reports/daily", DOGUM),
    ("/api/v1/reports/natal", DOGUM),
    ("/api/v1/reports/bazi", DOGUM),
    ("/api/v1/reports/dyad", {"friend_uid": "arkadas"}),
])
def test_ucretsiz_kullanici_ucretli_uca_giremez(monkeypatch, yol, govde):
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: False)

    with TestClient(app) as client:
        response = client.post(yol, json=govde, headers=_basliklar(yol))

    assert response.status_code == entitlements.PAYWALL_STATUS
    assert "Rytho+" in response.json()["detail"]


@uygulama_gerekir
def test_burc_yorumu_ucretsiz_kalir(monkeypatch):
    """Ucretsiz katmanin omurgasi paywall'in arkasina DUSMEMELI."""
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: False)

    with TestClient(app) as client:
        response = client.get("/api/v1/reports/horoscope/leo",
                              headers=_basliklar("bedava"))

    assert response.status_code == 200


# --------------------------------------------------------------------------
# Gunluk kotalar
# --------------------------------------------------------------------------

@uygulama_gerekir
def test_sohbet_kotasi_dolunca_paywall(monkeypatch):
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: False)

    kullanilan = {"n": 0}

    def sahte_kota(uid, key, limit):
        assert key == "chat"
        kullanilan["n"] += 1
        return kullanilan["n"] <= limit

    monkeypatch.setattr(entitlements, "consume_quota", sahte_kota)
    monkeypatch.setattr("services.gemini_service.chat", lambda h, m, **k: "merhaba")

    with TestClient(app) as client:
        for i in range(entitlements.FREE_CHAT_PER_DAY):
            response = client.post("/api/v1/chat", json={"message": f"selam {i}"},
                                   headers=_basliklar("kota"))
            assert response.status_code == 200, f"{i}. mesaj reddedildi"

        response = client.post("/api/v1/chat", json={"message": "bir tane daha"},
                               headers=_basliklar("kota"))

    assert response.status_code == entitlements.PAYWALL_STATUS
    assert "Rytho+" in response.json()["detail"]


@uygulama_gerekir
def test_abone_sohbette_kotaya_takilmaz(monkeypatch):
    # KT2 sözleşmesi: kotayı atlayan şey GERÇEK mağaza aboneliğidir
    # (get_subscription.active) — is_subscriber değil; in_trial kullanıcı
    # is_subscriber=True olsa da günlük hakkını korur (test_wallet'ta).
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: True)
    monkeypatch.setattr(entitlements, "get_subscription",
                        lambda uid: {"active": True})
    monkeypatch.setattr(entitlements, "consume_quota",
                        lambda *a: pytest.fail("Abonede kota dusulmemeli"))
    monkeypatch.setattr("services.gemini_service.chat", lambda h, m, **k: "merhaba")

    with TestClient(app) as client:
        for i in range(entitlements.FREE_CHAT_PER_DAY + 3):
            response = client.post("/api/v1/chat", json={"message": f"m{i}"},
                                   headers=_basliklar("abone"))
            assert response.status_code == 200


def test_kota_gun_degisince_sifirlanir(monkeypatch):
    """Sayac dokumandaki tarihe bagli; gun degisince bastan baslar."""
    kayit = {"date": "2020-01-01", "chat": 99}

    class SahteDoc:
        exists = True

        @staticmethod
        def to_dict():
            return kayit

    class SahteRef:
        @staticmethod
        def get():
            return SahteDoc()

        @staticmethod
        def set(data):
            kayit.clear()
            kayit.update(data)

    monkeypatch.setattr(entitlements, "_private_doc", lambda uid, name: SahteRef())

    assert entitlements.consume_quota("u", "chat", 5) is True
    assert kayit["date"] == dt.date.today().isoformat()
    assert kayit["chat"] == 1


# --------------------------------------------------------------------------
# RevenueCat webhook
# --------------------------------------------------------------------------

@uygulama_gerekir
def test_webhook_gizli_anahtarsiz_calismaz(monkeypatch):
    """Anahtar tanimsizken uc acik kalirsa herkes kendine abonelik yazabilirdi."""
    monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", None)

    with TestClient(app) as client:
        response = client.post("/api/v1/billing/revenuecat",
                               json={"event": {"type": "RENEWAL", "app_user_id": "u"}})
    assert response.status_code == 503


@uygulama_gerekir
def test_webhook_yanlis_anahtari_reddeder(monkeypatch):
    monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", "dogru-anahtar")

    with TestClient(app) as client:
        response = client.post("/api/v1/billing/revenuecat",
                               json={"event": {"type": "RENEWAL", "app_user_id": "u"}},
                               headers={"Authorization": "yanlis-anahtar"})
    assert response.status_code == 401


@uygulama_gerekir
def test_webhook_iptali_erisimi_hemen_kesmez(monkeypatch):
    """RevenueCat'te CANCELLATION 'yenilenmeyecek' demektir, 'bitti' degil.

    Kullanici odedigi donemin sonuna kadar erisimini korumali.
    """
    monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", "anahtar")

    yazilan: dict = {}

    class SahteDoc:
        @staticmethod
        def set(data):
            yazilan.update(data)

    class SahteKoleksiyon:
        def document(self, _):
            return self

        def collection(self, _):
            return self

        def set(self, data):
            yazilan.update(data)

    class SahteClient:
        def collection(self, _):
            return SahteKoleksiyon()

    monkeypatch.setattr("api.billing.firestore_client.get_client", lambda: SahteClient())

    with TestClient(app) as client:
        response = client.post(
            "/api/v1/billing/revenuecat",
            json={"event": {"type": "CANCELLATION", "app_user_id": "u",
                            "product_id": "rytho_plus_yearly",
                            "expiration_at_ms": 4102444800000}},
            headers={"Authorization": "anahtar"},
        )

    assert response.status_code == 200
    assert yazilan["active"] is True
    assert yazilan["willRenew"] is False
    assert SahteDoc  # kullanilmayan yardimci uyari vermesin


@uygulama_gerekir
def test_webhook_suresi_dolunca_kapatir(monkeypatch):
    monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", "anahtar")

    yazilan: dict = {}

    class SahteKoleksiyon:
        def document(self, _):
            return self

        def collection(self, _):
            return self

        def set(self, data):
            yazilan.update(data)

    class SahteClient:
        def collection(self, _):
            return SahteKoleksiyon()

    monkeypatch.setattr("api.billing.firestore_client.get_client", lambda: SahteClient())

    with TestClient(app) as client:
        response = client.post(
            "/api/v1/billing/revenuecat",
            json={"event": {"type": "EXPIRATION", "app_user_id": "u"}},
            headers={"Authorization": "anahtar"},
        )

    assert response.status_code == 200
    assert yazilan["active"] is False


@uygulama_gerekir
def test_webhook_app_user_id_olmadan_reddeder(monkeypatch):
    monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", "anahtar")

    with TestClient(app) as client:
        response = client.post("/api/v1/billing/revenuecat",
                               json={"event": {"type": "RENEWAL"}},
                               headers={"Authorization": "anahtar"})
    assert response.status_code == 400


# --------------------------------------------------------------------------
# TRANSFER: anonim kimlikten gercek kullaniciya devir
#
# Kullanici oturum acmadan (ya da RevenueCat kimligi baglanmadan) satin alma
# yaparsa kayit `$RCAnonymousID:...` altina yazilir. Sonradan logIn olunca
# RevenueCat aboneligi devreder ve TRANSFER gonderir. Islenmezse kullanici
# odeme yapmis olmasina ragmen kilitli kalir ve paywall tekrar tekrar acilir.
# --------------------------------------------------------------------------

class _SahteFirestore:
    """Asgari sahte istemci: anahtar "{uid}/{yaprak}".

    Eskiden ``users/{uid}/private/<herhangi>`` yollarinin TAMAMI uid ile
    anahtarlanmis TEK dokumana iniyordu ve cuzdan yazimi ABONELIK dokumanina
    dusuyordu: devir sonrasi hedefin "abonelik" kaydinda allowance/purchased
    goruluyordu. Uretimde ``private/wallet`` ile ``private/subscription``
    AYRI dokumanlar; sahtenin sadakat kaybi uretim kodundan onarim istemesine
    yol aciyordu.
    """

    def __init__(self, baslangic=None):
        self.dokumanlar = dict(baslangic or {})

    def collection(self, _):
        return _SahteKoleksiyon(self, None)


class _SahteKoleksiyon:
    def __init__(self, store, uid):
        self._store = store
        self._uid = uid

    def document(self, ad):
        # users/{uid}/private/{yaprak} — ilk document cagrisi uid, ikincisi
        # yaprak adi. Yaprak adini atmak wallet ile subscription'i tek
        # dokumana karistiriyordu (bkz. _SahteFirestore).
        if self._uid is None:
            return _SahteKoleksiyon(self._store, ad)
        return _SahteDokuman(self._store, f"{self._uid}/{ad}")

    def collection(self, _):
        return self


class _SahteAltKoleksiyon:
    """Dokumanin ALT koleksiyonu — anahtar "{dokuman}/{ad}/{belge}".

    Uretimde bir dokumanin alt koleksiyonu olabilir ve devrin tekrar
    korumasi tam da buna dayaniyor: `wallet/ledger/transfer-{event_id}`.
    Sahte bunu tasimazsa devir kodu AttributeError ile duser ve bekci
    olcecegi seyi hic olcemez.
    """

    def __init__(self, store, onek):
        self._store = store
        self._onek = onek

    def document(self, ad):
        return _SahteDokuman(self._store, f"{self._onek}/{ad}")


class _SahteDokuman:
    def __init__(self, store, anahtar):
        self._store = store
        # "uid" DEGIL "{uid}/{yaprak}": ad yaniltmasin, wallet ile
        # subscription ayri dokumanlar.
        self._anahtar = anahtar

    def collection(self, ad):
        return _SahteAltKoleksiyon(self._store, f"{self._anahtar}/{ad}")

    def get(self):
        return _SahteAnlik(self._store.dokumanlar.get(self._anahtar))

    def set(self, data, merge=False):
        if merge and self._anahtar in self._store.dokumanlar:
            self._store.dokumanlar[self._anahtar] = {
                **self._store.dokumanlar[self._anahtar], **data}
        else:
            self._store.dokumanlar[self._anahtar] = dict(data)


class _SahteAnlik:
    def __init__(self, veri):
        self._veri = veri

    @property
    def exists(self):
        return self._veri is not None

    def to_dict(self):
        return dict(self._veri or {})


def _transfer_gonder(monkeypatch, store, govde):
    monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", "anahtar")
    monkeypatch.setattr("api.billing.firestore_client.get_client",
                        lambda: store)
    with TestClient(app) as client:
        return client.post("/api/v1/billing/revenuecat", json={"event": govde},
                           headers={"Authorization": "anahtar"})


@uygulama_gerekir
def test_transfer_aboneligi_gercek_kullaniciya_tasir(monkeypatch):
    anonim = "$RCAnonymousID:abc123"
    store = _SahteFirestore({
        f"{anonim}/subscription": {
            "active": True, "productId": "rytho_plus_monthly",
            "expiresAt": "2099-01-01", "willRenew": True},
    })

    yanit = _transfer_gonder(monkeypatch, store, {
        "type": "TRANSFER",
        "transferred_from": [anonim],
        "transferred_to": ["firebase-uid"],
    })

    assert yanit.status_code == 200
    yeni = store.dokumanlar["firebase-uid/subscription"]
    assert yeni["active"] is True
    # Urun ve bitis tarihi kaynaktan kopyalanmali; sifirdan yazsaydik suresi
    # gecmis bir aboneligi sonsuza kadar acik birakabilirdik.
    assert yeni["productId"] == "rytho_plus_monthly"
    assert yeni["expiresAt"] == "2099-01-01"
    # Erisim kaydi CUZDAN alanlariyla kirlenmemeli: iki ayri dokuman.
    assert "purchased" not in yeni
    # Eski kimlikte erisim kalmamali.
    assert store.dokumanlar[f"{anonim}/subscription"]["active"] is False


@uygulama_gerekir
def test_transfer_app_user_id_istemez(monkeypatch):
    """TRANSFER yukunde app_user_id YOKTUR; 400 donmek sonsuz yeniden
    denemeye yol acardi."""
    store = _SahteFirestore({"eski/subscription": {"active": True}})
    yanit = _transfer_gonder(monkeypatch, store, {
        "type": "TRANSFER",
        "transferred_from": ["eski"],
        "transferred_to": ["yeni"],
    })
    assert yanit.status_code == 200


@uygulama_gerekir
def test_transfer_kaynaksizsa_erisim_acmaz(monkeypatch):
    """Devredilecek kayit yoksa uydurma abonelik yazilmamali."""
    store = _SahteFirestore()
    yanit = _transfer_gonder(monkeypatch, store, {
        "type": "TRANSFER",
        "transferred_from": ["yok"],
        "transferred_to": ["yeni"],
    })

    assert yanit.status_code == 200
    assert yanit.json()["active"] is False
    assert "yeni/subscription" not in store.dokumanlar
    # Devir artik abonelik yazimindan ONCE kostugu icin bos cuzdan dokumani
    # da uretilmemeli (bkz. core/wallet.py transfer_wallet).
    assert "yeni/wallet" not in store.dokumanlar


@uygulama_gerekir
def test_transfer_abonelik_kaydi_olmasa_da_cuzdani_tasir(monkeypatch):
    """Kredi paketi almis ama hic abone olmamis kimlikten devir.

    `users/{kaynak}/private/subscription` YOKTUR. Eski siralamada cuzdan
    devri "kaynak abonelik kaydi bulunamadi" erken cikisinin ALTINDA kaldigi
    icin parayla alinmis bakiye eski kimlikte oksuz kaliyordu — paket almak
    icin abonelik sart degil (bkz. core/wallet.py charge_metered), yani bu
    senaryo gercek.
    """
    cagrilar: list[tuple] = []
    monkeypatch.setattr("api.billing.wallet.transfer_wallet",
                        lambda c, s, t, **k: cagrilar.append(
                            (list(s), list(t))))
    store = _SahteFirestore()

    yanit = _transfer_gonder(monkeypatch, store, {
        "type": "TRANSFER",
        "transferred_from": ["yalniz-paket-almis"],
        "transferred_to": ["yeni"],
    })

    assert yanit.status_code == 200
    assert cagrilar == [(["yalniz-paket-almis"], ["yeni"])], (
        "cuzdan devri abonelik kaydinin varligina bagli olamaz")
    # Uydurma abonelik YAZILMAZ: cuzdan tasinir, erisim acilmaz.
    assert "yeni/subscription" not in store.dokumanlar


# ---------------------------------------------------------------------------
# Devirde kredi kaybi (2026-09-19 denetimi, OLCULDU)
# ---------------------------------------------------------------------------
#
# Eski sirada kaynaklar ONCE sifirlaniyor, hedefe yazim yutuluyor ve webhook
# 200 donuyordu: RevenueCat bir daha denemedigi icin para KALICI olarak yok
# oluyordu. Sira tersine cevrildi, hedef yazimindaki genis `except` kalkti ve
# tekrar korumasi DEFTERE baglandi.


# `wallet` modul duzeyinde ice aktarilmiyor (dosyanin geri kalani fonksiyon
# icinde aliyor); devir bekcileri dogrudan cagirdigi icin burada aliniyor.
from core import wallet  # noqa: E402


class _PatlayanHedef(_SahteFirestore):
    """Hedef cuzdanina yazim denendiginde patlar; digerleri normal."""

    def __init__(self, baslangic=None):
        super().__init__(baslangic)
        self.patlasin = True

    def collection(self, _):
        return _PatlayanKoleksiyon(self, None)


class _PatlayanKoleksiyon(_SahteKoleksiyon):
    def document(self, ad):
        if self._uid is None:
            return _PatlayanKoleksiyon(self._store, ad)
        return _PatlayanDokuman(self._store, f"{self._uid}/{ad}")


class _PatlayanDokuman(_SahteDokuman):
    def set(self, data, merge=False):
        if (self._store.patlasin and self._anahtar.endswith("/wallet")
                and self._anahtar.startswith("h/")):
            raise RuntimeError("Firestore dustu")
        super().set(data, merge=merge)


def test_devir_HEDEF_YAZIMI_DUSERSE_kredi_KAYBOLMAZ():
    """Hedef yazimi dusunce FIRLAT: webhook 500 gorup yeniden denemeli.

    Yutulsaydi (eski hal) kaynaklar zaten sifirlanmis oldugu icin tekrar
    hedefe 0 yazardi ve 350 kredi kalici olarak yok olurdu -- olculdu.
    """
    depo = _PatlayanHedef({"a/wallet": {"purchased": 100},
                           "b/wallet": {"purchased": 250}})
    with pytest.raises(Exception):
        wallet.transfer_wallet(depo, ["a", "b"], ["h"], event_id="olay-1")

    # Kaynaklar HENUZ sifirlanmadi: para duruyor.
    assert depo.dokumanlar["a/wallet"]["purchased"] == 100
    assert depo.dokumanlar["b/wallet"]["purchased"] == 250

    depo.patlasin = False          # Firestore duzeldi, webhook tekrar geldi
    wallet.transfer_wallet(depo, ["a", "b"], ["h"], event_id="olay-1")
    assert depo.dokumanlar["h/wallet"]["purchased"] == 350
    assert depo.dokumanlar["a/wallet"]["purchased"] == 0
    assert depo.dokumanlar["b/wallet"]["purchased"] == 0


def test_devir_defter_isareti_CIFT_KREDI_vermez():
    """Sira tersine dondugu icin "kaynak zaten sifir" guvencesi kalkti;
    yerini hedefteki `ledger/transfer-{event_id}` isareti aldi."""
    depo = _SahteFirestore({"a/wallet": {"purchased": 100},
                            "h/wallet": {"purchased": 0}})
    wallet.transfer_wallet(depo, ["a"], ["h"], event_id="olay-1")
    wallet.transfer_wallet(depo, ["a"], ["h"], event_id="olay-1")
    assert depo.dokumanlar["h/wallet"]["purchased"] == 100
    assert "h/wallet/ledger/transfer-olay-1" in depo.dokumanlar


def test_devir_kaynaklar_EN_SONDA_sifirlanir():
    """Hedef yazilmadan kaynak sifirlanirsa para havada kalir."""
    sira = []

    class _Izleyen(_SahteFirestore):
        def collection(self, _):
            return _IzleyenKoleksiyon(self, None)

    class _IzleyenKoleksiyon(_SahteKoleksiyon):
        def document(self, ad):
            if self._uid is None:
                return _IzleyenKoleksiyon(self._store, ad)
            return _IzleyenDokuman(self._store, f"{self._uid}/{ad}")

    class _IzleyenDokuman(_SahteDokuman):
        def set(self, data, merge=False):
            if self._anahtar.endswith("/wallet"):
                sira.append(self._anahtar)
            super().set(data, merge=merge)

    depo = _Izleyen({"a/wallet": {"purchased": 100},
                     "h/wallet": {"purchased": 0}})
    wallet.transfer_wallet(depo, ["a"], ["h"], event_id="olay-2")
    assert sira == ["h/wallet", "a/wallet"], (
        "hedef ONCE yazilmali, kaynak EN SONDA sifirlanmali")

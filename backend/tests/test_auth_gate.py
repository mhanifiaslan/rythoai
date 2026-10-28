r"""Kimlik dogrulama kapisinin HIZI ve dogru tarafa dusmesi.

Iki ayri kusur bu dosyada korunuyor.

**Birincisi (yavaslik).** Kimlik bilgisi cozulemedigi halde her istek ~12
saniye deneyip vazgeciyordu; kullanici bunu "sohbet gec geliyor", "ekran
acilmiyor" diye gordu. Olculen: `google.auth.default()` ADC'siz bir makinede
11,98 saniye. Ayni cagriyi Firestore istemcisi de yapiyordu.

**Ikincisi (uretimi kiran duzeltme).** Ilk duzeltme yoklamayi 3 saniye ile
sinirlayip sonuclanmazsa "kimlik yok" sayiyordu. Cloud Run soguk
baslatmasinda meta veri sunucusu 3 saniyeyi asti:

    ADC yoklamasi 3.0 sn icinde sonuclanmadi.
    Kimlik bilgisi yok; Firestore devre disi.   -> webhook 500
    ADC cozulemedi. Tum istekler 401 donecek.

Abonelik webhook'lari dustu, kullanici odeme yapti ve ekranlar kilitli kaldi.
Hata: "yoklama bitmedi" ile "kimlik yok" ayni sey sayildi.

Bu yuzden buradaki en onemli test `test_sonuclanmamis_yoklama_hicbir_seyi_
kapatmaz`. Digerleri hizi korur; o, DOGRULUGU korur.

Calistirma:  .venv\Scripts\python.exe -m pytest tests/test_auth_gate.py -q
"""
from __future__ import annotations

import asyncio
import threading
import time

import pytest

from core import auth, config, firestore, gcp_credentials


@pytest.fixture(autouse=True)
def temiz_durum():
    auth.reset_firebase_state()
    firestore._client = None
    firestore._failed = False
    yield
    auth.reset_firebase_state()
    firestore._client = None
    firestore._failed = False


class _SahteToken:
    def __init__(self, token: str = "sahte"):
        self.credentials = token


def _dusen_yoklama():
    def yokla():
        raise RuntimeError("ADC yok")

    return yokla


def _asili_yoklama(kapi: threading.Event):
    """Hic sonuclanmayan yoklama — Cloud Run'da yasanan durum."""

    def yokla():
        kapi.wait(timeout=30)
        raise RuntimeError("ADC yok")

    return yokla


# ---------------------------------------------------------------------------
# DOGRULUK — uretimi kiran kusur
# ---------------------------------------------------------------------------

def test_sonuclanmamis_yoklama_hicbir_seyi_kapatmaz(monkeypatch):
    """Yoklama sonuclanmadiysa erisim ACIK varsayilmali.

    Uretimi kiran tam olarak buydu: sonucsuz bir yoklama "kimlik yok" diye
    okundu, Firestore ve token dogrulama kapandi.
    """
    kapi = threading.Event()
    monkeypatch.setattr("google.auth.default", _asili_yoklama(kapi))
    try:
        # Yoklama arka planda asili dururken:
        assert gcp_credentials.available() is True, (
            "sonuclanmamis yoklama 'kimlik yok' sayiliyor — uretimi kiran hata"
        )
        # Ust uste sorulunca da ayni.
        for _ in range(5):
            assert gcp_credentials.available() is True
    finally:
        kapi.set()


def test_yoklama_istek_yolunu_bloklamaz(monkeypatch):
    """`available()` BEKLEMEZ. Her istegin onunde duran bir cagri bu."""
    kapi = threading.Event()
    monkeypatch.setattr("google.auth.default", _asili_yoklama(kapi))
    try:
        bas = time.monotonic()
        for _ in range(20):
            gcp_credentials.available()
        gecen = time.monotonic() - bas
        assert gecen < 0.5, f"20 cagri {gecen:.2f} sn surdu; bloklaniyor"
    finally:
        kapi.set()


def test_firestore_kimlik_yoklamasindan_KALICI_kapanmaz(monkeypatch):
    """Firestore'un `_failed` mandali kimlik yoklamasindan KURULMAMALI.

    Kalici bir mandaldi: kimlik gorunmedigi anda kuruluyordu ve Firestore
    instance omru boyunca kapaniyordu — abonelik webhook'lari 500 dondu.
    Mandal yalnizca istemci GERCEKTEN kurulamadiginda kurulmali, ki kimlik
    sonradan gorunurse toparlanabilsin.
    """
    monkeypatch.setattr("google.auth.default", _dusen_yoklama())
    gcp_credentials.warm_up()
    assert gcp_credentials._bekle(timeout=10) is False

    assert firestore.get_client() is None
    assert firestore._failed is False, (
        "kimlik yoklamasi Firestore'u KALICI olarak kapatti"
    )


def test_kesin_olumsuz_sonuc_erisimi_kapatir(monkeypatch):
    """Yoklama KESIN olarak dustuyse erisim kapanmali — sinir orada."""
    monkeypatch.setattr("google.auth.default", _dusen_yoklama())

    gcp_credentials.warm_up()
    assert gcp_credentials._bekle(timeout=10) is False
    assert gcp_credentials.available() is False


def test_olumsuz_sonuc_kalici_degil(monkeypatch):
    """Gecici bir sorun kimlik dogrulamayi surekli kapatmamali."""
    monkeypatch.setattr("google.auth.default", _dusen_yoklama())
    monkeypatch.setattr(gcp_credentials, "NEGATIVE_TTL_SECONDS", 0.05)

    gcp_credentials.warm_up()
    assert gcp_credentials._bekle(timeout=10) is False
    assert gcp_credentials.available() is False

    time.sleep(0.1)
    # Sure dolunca yeniden yoklanir ve bu arada ERISILEBILIR varsayilir.
    assert gcp_credentials.available() is True


# ---------------------------------------------------------------------------
# HIZ — ilk kusur
# ---------------------------------------------------------------------------

def test_yoklama_bir_kez_yapilir(monkeypatch):
    """Yoklama istek basina TEKRARLANMAMALI; asil yavaslik kusuru buydu."""
    sayac = {"n": 0}

    def yokla():
        sayac["n"] += 1
        raise RuntimeError("ADC yok")

    monkeypatch.setattr("google.auth.default", yokla)

    gcp_credentials.warm_up()
    gcp_credentials._bekle(timeout=10)
    for _ in range(10):
        gcp_credentials.available()

    assert sayac["n"] == 1, f"yoklama {sayac['n']} kez calisti"


def test_firestore_ayni_yoklamayi_paylasir(monkeypatch):
    """Firestore kendi ADC cozumlemesini yapmamali — bedel iki kez odeniyordu."""
    sayac = {"n": 0}

    def yokla():
        sayac["n"] += 1
        raise RuntimeError("ADC yok")

    monkeypatch.setattr("google.auth.default", yokla)

    gcp_credentials.warm_up()
    gcp_credentials._bekle(timeout=10)
    auth._init_firebase()
    firestore.get_client()

    assert sayac["n"] == 1, "auth ve firestore ayri ayri yokluyor"


# ---------------------------------------------------------------------------
# Kapi davranisi
# ---------------------------------------------------------------------------

def test_kimlik_yoksa_uretimde_401(monkeypatch):
    """Kimlik KESIN yoksa uretim FAIL-CLOSED kalmali."""
    monkeypatch.setattr("google.auth.default", _dusen_yoklama())
    monkeypatch.setattr(config, "DEV_MODE", False)

    gcp_credentials.warm_up()
    gcp_credentials._bekle(timeout=10)

    from fastapi import HTTPException

    with pytest.raises(HTTPException) as hata:
        asyncio.run(auth.get_current_user(credentials=_SahteToken(), lang="tr"))
    assert hata.value.status_code == 401


def test_dogrulama_olay_dongusunu_bloklamaz(monkeypatch):
    """`verify_id_token` bloklayan bir cagri; is parcacigi havuzunda kosmali.

    Imza anahtarlari ~6 saatte bir Google'dan yeniden cekiliyor. Bu ag turu
    olay dongusunde yapilirsa o sirada gelen TUM istekler bekler.
    """
    monkeypatch.setattr(auth, "_firebase_ready", True)
    monkeypatch.setattr(config, "DEV_MODE", False)

    def yavas_dogrula(token):
        time.sleep(0.4)
        return {"uid": "u1", "email": "a@b.c"}

    monkeypatch.setattr(auth, "_verify", yavas_dogrula)

    isaret = {"kosti": False}

    async def digeri():
        await asyncio.sleep(0.1)
        isaret["kosti"] = True

    async def senaryo():
        _, kullanici = await asyncio.gather(
            digeri(),
            auth.get_current_user(credentials=_SahteToken(), lang="tr"),
        )
        return kullanici

    kullanici = asyncio.run(senaryo())

    assert kullanici.uid == "u1"
    assert isaret["kosti"], "olay dongusu bloklandi"


# ---------------------------------------------------------------------------
# Surum aynasi (PBZ, K10): users/{uid}.appBuild
# ---------------------------------------------------------------------------

class NotFound(Exception):
    """Firestore'un var olmayan dokumana `update` yazimina verdigi yanit.

    Sinif ADI gercegiyle (`google.api_core.exceptions.NotFound`) birebir:
    `app_gate._DOKUMAN_YOK` sembole degil ADA bakiyor, bu sahte de o
    sozlesmeyi siniyor. Adi degistirmek bekciyi SESSIZCE devre disi
    birakir.
    """


class _SahteAyna:
    """`users/{uid}` yuzeyi: get / update / set. Yazimlari KIPIYLE sayar.

    `set` bilerek DURUYOR: silinseydi `set`e donen bir gerileme
    `AttributeError` ile patlar ve testler onu "ayna dustu, kimlik dusmedi"
    dalinda YUTARDI (ayna best-effort). Duruyorsa yazim `yazimlar`a
    `("set", ...)` diye girer ve iddia patlar — bekci ancak boyle gorur.

    `update` gercegi taklit eder: dokuman YOKSA yazmaz, `NotFound`
    firlatir. B9'un bekcisi bu sadakat.
    """

    def __init__(self, docs=None):
        self.docs: dict = dict(docs or {})
        self.yazimlar: list = []
        self._uid = None

    def collection(self, ad):
        assert ad == "users"
        return self

    def document(self, uid):
        self._uid = uid
        return self

    class _Anlik:
        def __init__(self, veri):
            self._veri = veri
            self.exists = veri is not None

        def to_dict(self):
            return dict(self._veri) if self._veri is not None else None

    def get(self, transaction=None):
        return self._Anlik(self.docs.get(self._uid))

    def set(self, veri, merge=False):
        uid = self._uid
        self.yazimlar.append(("set", uid, dict(veri)))
        mevcut = dict(self.docs.get(uid) or {}) if merge else {}
        mevcut.update(veri)
        self.docs[uid] = mevcut

    def update(self, veri):
        uid = self._uid
        if uid not in self.docs:
            raise NotFound(f"Dokuman yok: users/{uid}")
        self.yazimlar.append(("update", uid, dict(veri)))
        mevcut = dict(self.docs[uid])
        mevcut.update(veri)
        self.docs[uid] = mevcut


#: `u1`in dokumani: arama aynasinin (AD4) FARK gormemesi icin normalize
#: alanlar zaten dogru. Token'da e-posta/ad yok, yani `compute` ucunu de bos
#: dizgi verir ve `search_mirror.ensure` HIC yazmaz — bu dosyanin iddialari
#: yalniz SURUM aynasini gormeli.
_U1 = {"emailLower": "", "usernameLower": "", "nameLower": ""}


@pytest.fixture()
def ayna(monkeypatch):
    """Dogrulanmis token yolu (DEV_MODE kapali) + sahte Firestore."""
    from core import app_gate
    from services import search_mirror

    depo = _SahteAyna({"u1": dict(_U1)})
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: depo)
    monkeypatch.setattr(auth, "_firebase_ready", True)
    monkeypatch.setattr(auth, "_verify", lambda t: {"uid": "u1"})
    monkeypatch.setattr(config, "DEV_MODE", False)
    app_gate.reset_memo()
    # Arama aynasinin memo'su MODUL duzeyinde: sifirlanmazsa bir testin
    # memo'su sonrakine sizar (bu fixture'i kuran her test ayni uid'i
    # kullaniyor).
    search_mirror.reset_memo()
    yield depo
    app_gate.reset_memo()
    search_mirror.reset_memo()


def _dogrula(**kw):
    return asyncio.run(auth.get_current_user(
        credentials=_SahteToken(), lang="tr", **kw))


def test_ayna_uid_basina_bir_kez(ayna):
    """Her kimlikli istek buradan geciyor; yazim uid basina gunde bir."""
    for _ in range(5):
        kullanici = _dogrula(x_app_build="35")
        assert kullanici.uid == "u1"
    assert ayna.yazimlar == [("update", "u1", {"appBuild": 35})]


def test_ayna_surum_degisince_yeniden_yazar(ayna):
    """Gun icinde guncelleyen kullanici eski surumde gorunmemeli."""
    _dogrula(x_app_build="35")
    _dogrula(x_app_build="36")
    _dogrula(x_app_build="36")
    assert [v["appBuild"] for _, _, v in ayna.yazimlar] == [35, 36]


def test_basliksiz_ve_bozuk_baslik_yazmaz(ayna):
    """Baslik yoksa 'bilinmiyor' durustce bilinmiyor kalir (0 yazilmaz)."""
    _dogrula(x_app_build=None)
    _dogrula(x_app_build="abc")
    _dogrula(x_app_build="0")
    _dogrula(x_app_build="-2")
    assert ayna.yazimlar == []


def test_depends_disi_cagri_sentinel_yazmaz(ayna):
    """api/admin.py collect ve bu dosyadaki testler `x_app_build` vermeden
    cagiriyor; o yolda parametre None DEGIL, FastAPI'nin truthy Header
    nesnesi olur. Dizgi sanilip yazilmamali, kimlik de dusmemeli."""
    kullanici = _dogrula()
    assert kullanici.uid == "u1"
    assert ayna.yazimlar == []


def test_ayna_dusunce_kimlik_dusmez(ayna, monkeypatch):
    """Best-effort: Firestore patlasa da istek 401'e DONMEZ."""
    from core import app_gate

    class _Bozuk:
        def collection(self, ad):
            raise RuntimeError("Firestore dustu")

    monkeypatch.setattr(app_gate.firestore_client, "get_client",
                        lambda: _Bozuk())
    kullanici = _dogrula(x_app_build="35")
    assert kullanici.uid == "u1"


def test_ayna_yazim_dusunce_memo_kurulmaz(ayna, monkeypatch):
    """Gecici hata: bir sonraki istek yeniden dener (24 saat beklemez)."""
    from core import app_gate

    class _Bozuk:
        def collection(self, ad):
            raise RuntimeError("Firestore dustu")

    monkeypatch.setattr(app_gate.firestore_client, "get_client",
                        lambda: _Bozuk())
    _dogrula(x_app_build="35")
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: ayna)
    _dogrula(x_app_build="35")
    assert ayna.yazimlar == [("update", "u1", {"appBuild": 35})]


# ---------------------------------------------------------------------------
# B9: kimlik yolundaki aynalar SILINEN hesabi diriltmez (uretimde olculdu)
# ---------------------------------------------------------------------------

def test_silinmis_uid_dokuman_YARATMAZ(ayna, monkeypatch):
    """Bulgu B9. `delete_account` `users/{uid}`'yi siliyor ama Firebase
    kimlik jetonu BIR SAATE KADAR gecerli kaliyor; o pencerede gelen tek
    kimlikli istek bu fonksiyondan geciyor ve iki "en iyi caba" aynasini
    tetikliyor. Yazim yaratici oldugu surece doküman geri doguyordu —
    uretimde 19 `users` dokumaninin yalniz 12'sinin Auth karsiligi vardi.

    Iddia iki aynayi BIRLIKTE kapsiyor: depo TAMAMEN bos kalmali.
    """
    monkeypatch.setattr(auth, "_verify", lambda t: {
        "uid": "silinmis", "email": "silinen@ornek.com", "name": "Ali"})
    ayna.docs.clear()
    kullanici = _dogrula(x_app_build="46")
    # Kimlik hala gecerli — ayna best-effort, oturumu dusuremez.
    assert kullanici.uid == "silinmis"
    assert ayna.docs == {}, "silinmis hesap aynalarla dirildi"
    assert ayna.yazimlar == []


def test_yeni_kullanicinin_aynasi_dokuman_dogunca_yazilir(ayna, monkeypatch):
    """Duzeltmenin sessiz gerileme riski: yeni kullanici KAYBOLMAMALI.

    `users/{uid}` oturum acilisinda ISTEMCIDE doguyor
    (`language_sync._firestoreWrite`) ve ilk kimlikli istek o doğumun
    ONUNE gecebilir. O istekte ayna yazmaz ama memo da KURMAZ; doküman
    dogduktan sonraki ilk istek hem surum hem arama aynasini yazar.
    Bu test olmasa "silinmis hesabi diriltme" duzeltmesi panelin aramasini
    ve surum kirilimini sessizce oldururdu.
    """
    from core import app_gate

    monkeypatch.setattr(auth, "_verify", lambda t: {
        "uid": "yeni", "email": "Yeni@Ornek.COM"})
    ayna.docs.clear()

    _dogrula(x_app_build="46")
    assert ayna.docs == {}
    assert not app_gate.build_remembered("yeni", 46), \
        "yazilmayan ayna memo kurmamali; yoksa 24 saat hic denenmez"

    # Istemci dokumani dogurdu. IKI memo da BILEREK sifirlanmiyor: dogum
    # oncesi cagrinin memo KURMADIGI da bu testin iddiasi.
    ayna.docs["yeni"] = {"language": "tr", "email": "Yeni@Ornek.COM"}
    _dogrula(x_app_build="46")

    assert ayna.docs["yeni"]["appBuild"] == 46, "surum aynasi yazilmadi"
    assert ayna.docs["yeni"]["emailLower"] == "yeni@ornek.com", \
        "arama aynasi yazilmadi — panelde arama sessizce olurdu"
    assert {kip for kip, _, _ in ayna.yazimlar} == {"update"}, \
        "yaratan bir yazim bicimi geri geldi"


def test_dev_mode_anonim_yolunda_ayna_yok(ayna, monkeypatch):
    """DEV_MODE'un dev-user'i icin ayna yazilmaz — dogrulanmis token yolu
    disinda yazim yok."""
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(auth, "_init_firebase", lambda: False)
    kullanici = asyncio.run(auth.get_current_user(
        credentials=None, lang="tr", x_app_build="35"))
    assert kullanici.uid == "dev-user"
    assert ayna.yazimlar == []


# ---------------------------------------------------------------------------
# Hermetiklik pini (tests/conftest.py `adc_hermetik`)
# ---------------------------------------------------------------------------

#: Gercek `google.auth.default()`un sirayla yokladigi dort kimlik kaynagi.
#: Pin yoksa en az ilki HER makinede cagrilir (ADC'li makinede dosyayi
#: bulan ikincisi, ADC'siz makinede meta veri sunucusuna giden dorduncusu).
_ADC_KAYNAKLARI = ("_get_explicit_environ_credentials",
                   "_get_gcloud_sdk_credentials",
                   "_get_gae_credentials",
                   "_get_gce_credentials")


def _adc_kaydedicisi(monkeypatch) -> list[str]:
    """Gercek ADC kaynaklarinin yerine kaydedici koyar.

    Kaydedici "kimlik yok" (None, None) doner ve AGA CIKMAZ: pin delikse
    bile bekci meta veri sunucusunu beklemez, uretime de dokunmaz.
    Kaynak duzeyinde olculmesinin NEDENI: yalniz hatanin turune bakmak
    yetmezdi — ADC'siz makinede gercek `default()` da ayni turde hata
    firlatiyor (sadece ~4 sn sonra).
    """
    from google.auth import _default as adc

    ulasilan: list[str] = []
    for ad in _ADC_KAYNAKLARI:
        def kaydet(*_a, _ad=ad, **_k):
            ulasilan.append(_ad)
            return None, None
        monkeypatch.setattr(adc, ad, kaydet)
    return ulasilan


def test_pin_sahtelenmemis_dogrulama_adc_ye_ulasmaz(monkeypatch):
    """conftest `adc_hermetik` pininin BEYANI olculur, zamanin GITTIGI
    kapidan: `_verify`i sahtelemeyen bir test (Bearer baslikli her
    `TestClient` istegi) gercek ADC'yi HIC cozmez.

    2026-10-28 olcumu: bu kapi pinsiz ADC'siz Mac'te istek basina ~4 sn
    bekletiyordu (25 istekli kota testleri ~100 sn). Varsayilan Firebase
    uygulamasi uretimdeki gibi kurulur — yoksa `verify_id_token` kimlige
    hic varmadan "uygulama yok" diye duserdi ve bekci bos olcerdi.
    """
    import firebase_admin
    from google.auth import exceptions as adc_hatalari

    ulasilan = _adc_kaydedicisi(monkeypatch)
    kurdum = not firebase_admin._apps
    if kurdum:
        firebase_admin.initialize_app(
            options={"projectId": config.GOOGLE_CLOUD_PROJECT})
    try:
        with pytest.raises(adc_hatalari.DefaultCredentialsError,
                           match="conftest.adc_hermetik"):
            auth._verify("pin-bekcisi")
    finally:
        if kurdum:
            firebase_admin.delete_app(firebase_admin.get_app())

    assert ulasilan == [], (
        f"pin delik: dogrulama gercek ADC kaynaklarina ulasti {ulasilan}")


def test_pin_sahtelenmemis_yoklama_adc_ye_ulasmaz(monkeypatch):
    """Ayni beyanin ikinci kapisi: her `TestClient` acilisinda (lifespan
    `warm_up`) baslayan `gcp_credentials` yoklamasi. Pinliyken aninda
    KESIN olumsuz sonuclanir — uretimin "ADC yok" dali, yeni dal degil."""
    ulasilan = _adc_kaydedicisi(monkeypatch)

    gcp_credentials.warm_up()

    assert gcp_credentials._bekle(timeout=10) is False
    assert ulasilan == [], (
        f"pin delik: yoklama gercek ADC kaynaklarina ulasti {ulasilan}")

"""Paket geneli test kancaları — kapı hermetikliği (PBZ-turu).

`AppGateMiddleware` HER TestClient isteğinde canlı: `/api/v1/` altındaki
muaf olmayan yol `X-App-Build` başlığını eşiğe vurur. Eşik okuması
(`app_gate.current_min_build`) memo boşken `core.firestore.get_client`'a
gider; geliştirici makinesinde ADC varsa bu GERÇEK projenin
`config/app.minBuild` dokümanıdır (`GOOGLE_CLOUD_PROJECT` varsayılanı
üretim). Panelden eşik > 0 yazıldığı an, başlık göndermeyen ve kapıyı hiç
düşünmeyen her test (uç, kota, kimlik testleri...) 426 ile düşerdi —
kapı testleri dışındaki hiçbir test kapıdan haberdar değil ve olmamalı.

Pin: eşiğin doküman ayağı, Firestore istemcisi SAHTELENMEMİŞKEN okumadan
0 döner — hiçbir test istemeden gerçek ADC'ye gidemez. Env tabanı da 0'a
sabitlenir (kabuktaki `RYTHO_MIN_BUILD` aynı şekilde her testi kilitlerdi)
ve iki memo her testin önünde/arkasında sıfırlanır.

Çıkış (kapıyı BİLEREK sınayan testler): `core.firestore.get_client`'ı
kendi sahtesiyle ya da `lambda: None` ile değiştiren test gerçek okuma
mantığını olduğu gibi çalıştırır — test_app_gate `esik`, test_app_config
`hermetik`, test_admin_min_build `depo`, test_auth_gate `ayna` zaten
böyle yapıyor. Pin yalnız Firestore'u düşünmeyen testi korur; bekçisi
test_app_gate `test_pin_firestore_sahtelenmemisken_esik_sifir`.
"""
from __future__ import annotations

import os

import google.auth
import pytest
from google.auth import exceptions as google_auth_hatalari

from core import app_gate, config
from core import firestore as firestore_client
from services import (account_service, gemini_service, partner_service,
                      push_service, sky_service)

#: Toplama anında yakalanır: henüz hiçbir fixture koşmadı, bu gerçek
#: istemci kurucusudur. Kıyas kimlikle (`is`) — sahte istemci kuran her
#: test modül niteliğini değiştirmiş olur.
_GERCEK_GET_CLIENT = firestore_client.get_client


def _pin_get_client():
    """`firestore_hermetik` pininin istemcisi: Firestore YOK.

    Modul duzeyinde ve ADLI: `kapi_hermetik` "bu testte istemci
    sahtelendi mi" sorusunu KIMLIKLE soruyor, lambda her fixture
    kosusunda yeni bir nesne olurdu ve iki pin birbirini bozardi.
    """
    return None


@pytest.fixture(autouse=True)
def kapi_hermetik(monkeypatch):
    gercek_doc_min_build = app_gate._doc_min_build

    def korumali_doc_min_build() -> int:
        # Sahte istemci kurulduysa gerçek mantık; kurulmadıysa dokümanı
        # OKUMADAN 0 — ADC'ye gidilmez.
        # Iki "sahtelenmemis" hali var: gercek kurucu ve
        # `firestore_hermetik` pini. Ikisi de "bu test Firestore'u
        # dusunmuyor" demek, yani dokuman OKUNMAZ.
        if firestore_client.get_client in (_GERCEK_GET_CLIENT,
                                           _pin_get_client):
            return 0
        return gercek_doc_min_build()

    app_gate.reset_memo()
    monkeypatch.setattr(app_gate, "_doc_min_build", korumali_doc_min_build)
    monkeypatch.setattr(config, "MIN_APP_BUILD", 0)
    yield
    app_gate.reset_memo()


class _BosKova:
    """Hiçbir dosyası olmayan kova: `list_blobs` boş döner, silme olmaz."""

    def list_blobs(self, prefix: str = ""):  # noqa: ARG002
        return ()


@pytest.fixture(autouse=True)
def depolama_hermetik(monkeypatch):
    """Hiçbir test istemeden GERÇEK Cloud Storage kovasına gitmesin.

    `delete_account` 2026-09-18'den beri `avatars/{uid}/` önekini de
    siliyor (hesabı silinmiş kullanıcının fotoğrafı kovada kalıyordu).
    Çağrıyı `account_service._delete_storage_files` yapıyor ve uid'i
    sahteleyen 18 mevcut silme testi kovayı sahtelemiyor.

    Bugün o testler KAZARA güvenli: `firebase_admin` uygulaması testte
    hiç başlatılmadığı için `storage.bucket()` anında fırlıyor ve
    fonksiyonun best-effort `except`i yutuyor ("The default Firebase app
    does not exist" uyarısı log'a düşüyor). Ama bu tek bir satıra bağlı:
    ileride bir test ya da içe aktarma yan etkisi varsayılan uygulamayı
    başlatırsa, makinede ADC varken aynı 18 test ÜRETİM kovasında
    `list_blobs` + `delete` koşar. Kaza ile güvenli olan şey güvence
    değildir; pin bunu yapısal hâle getiriyor.

    ⚠️ "Hiç başlatılmadığı için" öncülü YANLIŞTI (ölçüldü 2026-10-28):
    `Bearer` başlıklı her test isteği `core.auth._init_firebase` üzerinden
    varsayılan uygulamayı KURUYORDU — soket izinde `verify_id_token`
    kimlik çözümüne vardı, uygulama yokken varamazdı. Yani "ileride"
    denen durum zaten vardı ve kalkan sıraya bağlıydı; bu pin o yüzden
    gerekliydi. Altındaki ikinci kalkan artık `adc_hermetik`: uygulama
    kurulsa da kimlik çözülemez.

    `kapi_hermetik`in Firestore pini ile aynı doktrin ve aynı çıkış yolu:
    kovayı BİLEREK sınayan test `_kova`'yı kendi sahtesiyle değiştirir
    (test_account_deletion `kova`) ve o yama bunun ÜSTÜNE yazdığı için
    kazanır.
    """
    monkeypatch.setattr(account_service, "_kova", _BosKova)


@pytest.fixture(autouse=True)
def firestore_hermetik(monkeypatch):
    """Hiçbir test istemeden GERÇEK Firestore'a YAZAMASIN.

    ⚠️ Bu pin bir VARSAYIMLA değil, KANITLA kondu. 2026-09-18'de üretim
    `rhytoai` projesinde `users/dev-user` dokümanı bulundu; içinde o gün
    yazılmış bir `termsConsent` vardı. `dev-user`, `config.DEV_MODE`
    açıkken kimliksiz isteğe verilen uid'dir ve `RYTHO_DEV_MODE`
    varsayılanı **"1"**, yani yerelde DEV_MODE AÇIK. Aynı koleksiyonda
    `u1`/`u2` fikstür uid'leri de duruyordu. Yani bir koşu gerçek
    Firestore'a ulaşmış: makinede ADC var ve `get_client` projeyi
    `rhytoai`ye bağlıyor.

    `kapi_hermetik` yalnız EŞİK OKUMASINI pinliyordu ("hiçbir test
    istemeden gerçek ADC'ye gidemez") — ama pin `_doc_min_build`e özeldi,
    `get_client`in kendisine değil. Boşluk buradaydı.

    Varsayılan artık `None`: depo boyunca `client is None` zaten
    desteklenen ve test edilen daldır (servisler sessizce atlar,
    `scripts/_ortak.istemci` açık mesajla çıkar). Firestore'u BİLEREK
    kullanan test kendi sahtesini kurar ve o yama bunun üstüne yazar —
    test_app_gate `esik`, test_admin_min_build `depo`, test_auth_gate
    `ayna` zaten böyle yapıyor.
    """
    monkeypatch.setattr(firestore_client, "get_client", _pin_get_client)


class _AuthYok:
    """Firebase Auth pini: her cagri acik bir hatayla duser.

    `firebase_admin.auth`in None ile degil BIR NESNEYLE pinlenmesi
    bilincli: servis `_auth_modulu()` donusune her zaman bir modul gibi
    davraniyor ve None pini `AttributeError` yerine sessiz bir dal
    degisikligi uretirdi.
    """

    class UserNotFoundError(Exception):
        pass

    @staticmethod
    def get_user(uid):
        raise RuntimeError("Firebase Auth testte pinli (conftest).")

    @staticmethod
    def set_custom_user_claims(uid, claims):
        raise RuntimeError("Firebase Auth testte pinli (conftest).")


@pytest.fixture(autouse=True)
def auth_hermetik(monkeypatch):
    """Hicbir test istemeden GERCEK Firebase Auth'a gidemesin.

    CLAUDE.md'nin kurali: dis dunyaya cikan HER yeni istemci icin ayri
    pin. Ortaklik erisimi (`partner_service.set_partner_access`) bu
    doktrine tabi YENI bir istemci acti ve tek basina en tehlikelisi:
    Firestore pini yalnizca YAZMAYI durdururdu, burada yazilan sey
    **yetki** — pinlenmemis bir dal, makinede ADC varken gercek
    `rhytoai` hesaplarina CLAIM BASABILIRDI.

    Bugun kaza ile guvenliydi: `firebase_admin` uygulamasi testte
    baslatilmadigi icin `get_user` zaten firliyor ve servisin dallari
    onu yutuyor. Firestore pininin gerekcesi tam olarak buydu —
    **kaza ile guvenli olan sey guvence degildir**; bir gun baska bir
    test `initialize_app` cagirdiginda bu kalkan sessizce duserdi.

    ⚠️ "Baslatilmadigi icin" onculu YANLISTI (olculdu 2026-10-28): o gun
    zaten gelmisti — `Bearer` baslikli test istekleri `core.auth.
    _init_firebase` uzerinden varsayilan uygulamayi kuruyordu (gerekce
    `depolama_hermetik`te). Pin bu yuzden gercek bir boslugu kapatiyor;
    alttaki ikinci kalkan `adc_hermetik`.

    Auth'u BILEREK sinayan test `_auth_modulu`yu kendi sahtesiyle
    degistirir (test_partner_rewards `_auth_pinle`) ve o yama bunun
    USTUNE yazdigi icin kazanir — `kapi_hermetik`/`depolama_hermetik`
    ile ayni cikis yolu.
    """
    monkeypatch.setattr(partner_service, "_auth_modulu",
                        lambda: _AuthYok)


#: `adc_hermetik` pininin hata metni. Bekcileri (test_auth_gate) bu imzayi
#: arar: gercek `default()` da ayni turde hata firlatir, ayirt eden metindir.
ADC_PIN_MESAJI = "ADC testte pinli (conftest.adc_hermetik)."


def _pin_adc(*_a, **_k):
    raise google_auth_hatalari.DefaultCredentialsError(ADC_PIN_MESAJI)


@pytest.fixture(autouse=True)
def adc_hermetik(monkeypatch):
    """Hicbir test istemeden makinenin GERCEK kimlik bilgisini (ADC) cozemesin.

    ⚠️ OLCULDU (2026-10-28, Mac, ADC YOK): tam takim 975 sn; en yavas iki
    test (`test_hardening` kota testleri, 25'er istek) ~100'er sn. CPU %1 —
    hesap degil BEKLEME. Soket izi: 99 sn'lik testte 169.254.169.254'e (GCE
    meta veri sunucusu) 78 baglanti denemesi (~30 sn zaman asimi) ve 52
    geri cekilme uykusu (~77 sn). Yol: `Bearer` baslikli her istek
    `core.auth._verify` -> `firebase_admin.auth.verify_id_token` ->
    `ApplicationDefault._load_credential` -> `google.auth.default()`; ADC
    dosyasi olmayan makinede bu, meta veri sunucusuna 3 denemeli ping +
    ustel geri cekilme demek: istek basina ~4 sn. Ayni cagriyi
    `gcp_credentials` yoklamasi da her `TestClient` acilisinda yapiyor.

    NEDEN istek basina: `firebase_admin` BASARISIZ kimlik cozumunu
    onbellege almiyor (yalniz basariliyi), `core.auth._init_firebase` de
    `_firebase_ready` mandalini yoklama sonuclanmadan (fail-open) kuruyor
    ve `available()`a bir daha bakmiyor. Yani "yoklama bir kez" degismezi
    dogrulama yolunda tutmuyor (uretim kodu; bu pin onu DEGISTIRMIYOR).

    NEDEN kokten (`google.auth.default`), istemci istemci degil: §5'in
    olculmus kok nedeni "makinede ADC var". Firebase Admin (Auth, Firestore,
    Storage, FCM), `google.cloud` istemcileri ve `gcp_credentials`
    yoklamasi kimligi HEP buradan aliyor (venv kaynaginda okundu: hepsi
    cagri aninda `google.auth.default` niteligine bakiyor). ADC'li makinede
    (Windows) unutulmus bir istemci pini artik uretime YAZAMAZ; ADC'siz
    makinede (Mac) meta veri sunucusuna gidilmez.

    Istemci pinlerinin YERINE degil ALTINDA: kimligi ADC'den almayan kapi
    (Gemini, API anahtari) bunun kapsami disinda; §5 kurali (her istemciye
    ayri pin) aynen gecerli.

    Yeni davranis UYDURMUYOR: `DefaultCredentialsError` gercek `default()`un
    "kimlik yok" hatasi ve uretim kodu o dali biliyor (`gcp_credentials`
    "ADC cozulemedi", dogrulama DEV_MODE'a duser, Firestore istemcisi
    kurulmaz).
    Bu Mac'te takim zaten ADC'siz yesildi; pin yalniz bekleme suresini
    siliyor ve ADC'li makineyi ayni hale getiriyor.

    Cikis: `google.auth.default`i kendisi yamalayan test (test_auth_gate)
    kendi degerini alir — testin setattr'i pinden sonra kosar. Bekcileri
    davranissal, ikisi de test_auth_gate'te:
    `test_pin_sahtelenmemis_dogrulama_adc_ye_ulasmaz` ve
    `test_pin_sahtelenmemis_yoklama_adc_ye_ulasmaz`.
    """
    monkeypatch.setattr(google.auth, "default", _pin_adc)


class _HorizonsYok:
    """`sky_service`in `httpx` modulunun yerine: istemci KURULAMAZ."""

    class Client:
        def __init__(self, *_a, **_k):
            raise RuntimeError(
                "NASA Horizons testte pinli (conftest.horizons_hermetik).")


@pytest.fixture(autouse=True)
def horizons_hermetik(monkeypatch):
    """Hicbir test istemeden GERCEK NASA JPL Horizons'a gidemesin.

    OLCULDU (2026-10-28, Mac): `adc_hermetik` kurulduktan sonra da
    `test_i18n::test_baslik_yoksa_turkce` 15,8 sn surdu, CPU %3. Soket izi
    tek baglanti gosterdi: `ssd.jpl.nasa.gov:443`, yol `api/reports.py`
    -> `get_sky_now` -> `_horizons_distances` — gezegen basina bir GET
    (9 sirali istek, httpx tek baglantiyi yeniden kullaniyor, zaman yanit
    beklemede). Gokyuzunu kullanan uc testleri onbellegi `tmp_path`e
    izole ettigi icin (test_horoscope `temiz_onbellek`) HER test NASA'ya
    yeniden gidiyordu. Uretime yazmiyor (halka acik, salt okuma) ama
    takimin hem suresi hem SONUCU NASA'nin o anki ayakta olusuna bagliydi.
    Uretim kodunda dogrudan HTTP yapan tek yer burasi (`api/services/core`
    tarandi).

    NEDEN `_horizons_distances` degil `sky_service.httpx`: islevin kendi
    dallari (gunluk onbellek, `except` -> bos sozluk) kosmaya devam etsin.
    Islevin kendisi pinlenseydi, Horizons ayristirmasini BILEREK sinayan
    bir test onu dogrudan cagirdiginda pini cagirip SESSIZCE bos olcerdi.

    Yeni davranis UYDURMUYOR: istemci kurulamayinca uretimin "Horizons
    erisilemedi" dali calisir (modul docstring'i: "yalniz swisseph verisi
    doner"), `distance_au` None. Cikis: `sky_service.httpx`i kendi
    sahtesiyle degistiren test kendi degerini alir. Bekcisi davranissal:
    `test_sky_horizons.py::test_pin_sahtelenmemis_gokyuzu_nasa_ya_ulasmaz`.
    """
    monkeypatch.setattr(sky_service, "httpx", _HorizonsYok)


#: Canli LLM cagrisina ACIK izin. Anahtarin VARLIGI izin DEGILDIR.
_CANLI_LLM_IZNI = "RYTHO_CANLI_LLM"


@pytest.fixture(autouse=True)
def gemini_hermetik(monkeypatch):
    """Hicbir test istemeden GERCEK Gemini'ye gidemesin.

    CLAUDE.md'nin kurali: dis dunyaya cikan HER yeni istemci icin ayri pin.
    Dort pin vardi (kapi, depolama, Firestore, Auth) ama Gemini YOKTU ve
    bedeli ODENDI: 48-turunda bir ajan `test_chat_style`i dort kez
    kosturdugunu ve uretim kotasindan ~4 sohbet cagrisi harcadigini
    bildirdi. Ayni gun uretim projesi `Lightning dunning` reddi
    aliyordu — yani kota gercek para ve o para bir kesintinin ortasinda
    yandi.

    ⚠️ ESKI KALKAN YETERSIZDI: canli test `skipif(not GEMINI_API_KEY)`
    tasiyordu ve bu bir kalkan DEGIL, yalnizca bir YOKLUK kontrolu.
    Gelistirici makinesinde `backend/.env` uzerinden anahtar VARDIR
    (olculdu), yani kosul her zaman dogru ve test her zaman kosar.
    **Anahtarin varligi, harcama izni demek degildir.**

    Izin artik ACIK: `RYTHO_CANLI_LLM=1`. Varsayilan hal HERMETIK ve
    `_get_client` None donuyor — uretim kodu bu hali zaten biliyor
    (anahtarsiz kurulum) ve yedek yollarina duser, yani pin yeni bir
    davranis UYDURMUYOR, var olan bir dala sabitliyor.

    ⚠️ PININ ILK HALI YARIMDI ve yukaridaki basligi (`hicbir test`)
    TUTMUYORDU — dogrulama turunda olculdu (2026-10-03): Gemini'ye iki
    KAPI var ve pin yalnizca birini kapatiyordu. Ikincisi
    `rag_service._KnowledgeBase._embed_texts`: `gemini_service` hic
    devreye girmiyor, islev `from google import genai` ile ICINDE kendi
    `genai.Client(api_key=config.GEMINI_API_KEY)`ini kuruyor ve
    `models.embed_content` cagiriyor. Olcum: `genai.Client` bir
    kaydediciyle degistirildiginde kaydediciye ULASILDI ve gecen anahtar
    GERCEK uretim anahtariydi (`AIza...`, 39 karakter, `backend/.env`
    uzerinden). Yani bes test dosyasi (`test_rag`, `test_rag_books`,
    `test_rag_coverage`, `test_report_depth`, `test_admin_system`)
    soguk bir bilgi tabanina dokundugu an uretim kotasindan PARA
    harciyordu. CLAUDE.md bu kapi ciftini zaten adiyla yaziyor:
    "`gemini_service.generate_content` VE `rag_service.embed_content` —
    iki yuzey, biri atlanirsa teshis eksik kalir."

    Ikinci kapi ANAHTARDAN kapatiliyor, ayri bir yama ile degil: her iki
    kapi da `config.GEMINI_API_KEY`i ON KOSUL olarak okuyor
    (`gemini_service.py:38`, `rag_service.py:521`), yani anahtari bos
    gormek ikisini de uretimin ANAHTARSIZ dalina dusuruyor — `_get_client`
    None, `_embed_texts` None ve arama kelime ortusmesine geriliyor. Yeni
    bir davranis yine UYDURULMUYOR. Secim bilincli: `_embed_texts`i tek
    tek sahtelemek yalniz BUGUNKU ikinci kapiyi kapatirdi, anahtar pini
    ise anahtari on kosul yapan her kapiyi (bugunku ucu:
    `scripts/build_embeddings.py`, `scripts/eval_genericness.py` da
    ayni kosula bakiyor).

    Bekcisi: `test_honesty.py::TestPinBeyanlari` — bu docstring bir BEYAN
    ve bu depoda beyan OLCULUR.
    """
    if os.getenv(_CANLI_LLM_IZNI) == "1":
        return
    monkeypatch.setattr(gemini_service, "_get_client", lambda: None)
    monkeypatch.setattr(config, "GEMINI_API_KEY", "")


@pytest.fixture(autouse=True)
def push_hermetik(monkeypatch):
    """Hicbir test istemeden GERCEK FCM'e bildirim gonderemesin.

    CLAUDE.md'nin kurali (dis dunyaya cikan her istemci icin ayri pin) push
    icin acikti (olculdu 2026-10-24, konsol arastirmasi): `push_service.
    _get_messaging` firebase_admin uygulamasi yoksa
    `initialize_app(projectId=rhytoai)` kuruyor; makinede ADC varken
    `push_service.send`i sahtelemeden cagiran bir test GERCEK kullanicilara
    bildirim gonderebilirdi. Bugunku testler `send`i ya da `_get_messaging`i
    kendisi sahteliyor — pin, bunu unutan bir sonraki testi korur.

    `_get_messaging` None doner: uretim kodu bu hali zaten biliyor ("FCM
    kullanilamiyor", hepsi basarisiz) — pin yeni bir davranis UYDURMUYOR.
    Cikis: `_get_messaging`i ya da `send`i kendi sahtesiyle degistiren test
    (test_push_yuku) kendi degerini alir, testin icindeki setattr pinden
    sonra kosar. Bekcisi davranissal:
    `test_push_yuku.py::test_pin_sahtelenmemis_send_fcm_e_ulasmaz`.
    """
    monkeypatch.setattr(push_service, "_get_messaging", lambda: None)
#: Canli embedding OLMADAN GECERSIZ olan testlerin nodeid IMZALARI.
#:
#: NEDEN burada ve neden `skipif` degil: `gemini_hermetik` pini RAG
#: embedding kapisini kapattigi an bu testler kirmizi oluyor, cunku
#: olctukleri sey ANLAMSAL isabet ve pinli halde `search()` kelime
#: ortusmesine geriliyor (`rag_service.search`, vektor modu kapali).
#: Yani testler YANLIS DEGIL, yalnizca varsayilan kosunun VERMEDIGI bir
#: izni (canli, UCRETLI embedding) ON KOSUL sayiyorlar. Emsali depoda
#: duruyor: `test_chat_style.py` ayni izni `skipif(RYTHO_CANLI_LLM != 1)`
#: ile kendi dosyasinda istiyor.
#:
#: ⚠️ DOGRU SON HAL O EMSALDIR, bu liste DEGIL: izin kosulu testin KENDI
#: dosyasinda durmali. Liste burada cunku `test_rag_coverage.py` baska bir
#: paketin dosyasi (yedi ajan ayni depoda) ve dogrulama turunda ona
#: dokunulmadi. Kirmizi birakmak yerine ATLAMA secildi: atlama kosulu
#: ADIYLA goruluyor, kirmizi ise "pin bozuk mu, test mi bozuk" sorusunu
#: her kosuda yeniden sorduruyordu.
#:
#: Imza KISALTILMIS degil TAM AYIRT EDICI: `[en-` parametre onekiyle
#: baglaniyor cunku ayni testin `tr-` parametreleri pinli halde de GECIYOR
#: (kelime ortusmesi Turkce basliklari buluyor) ve onlari atlamak gereksiz
#: kapsam olurdu.
_CANLI_EMBEDDING_ISTEYENLER = (
    "test_rag_coverage.py::TestKorpusKarsiligi::"
    "test_tohum_ve_mesajla_dogru_bolum_gelir[en-",
)


def pytest_collection_modifyitems(items):
    """Canli embedding isteyen testleri izin yoksa ATLAR.

    ⚠️ IMZA: parametre adlari pytest icin SOZLESMEDIR, suslemeye acik degil.
    Bu kanca bir tur boyunca `(config_, items)` diye yaziliydi ve pluggy
    eklentiyi REDDEDIYORDU ("Argument(s) {'config_'} ... can not be found in
    the hookspec") — sonucu "bir test kirmizi" degil, TUM TAKIMIN HIC
    TOPLANAMAMASIYDI. Kanca hookspec'in ALT KUMESINI alabilir, o yuzden
    kullanilmayan parametre eklenmez: yalniz `items` isteniyor.

    Izin ACIK: `RYTHO_CANLI_LLM=1` — pinin kendi izniyle ayni degisken,
    cunku istenen sey ayni: uretim kotasindan harcama izni. Iki ayri
    degisken olsaydi biri verilip oteki unutulur ve "neden hala
    atliyor" sorusu dogardi.

    ⚠️ BAYAT IMZA SESSIZ KALMAZ: imzasi hicbir teste uymayan bir girdi
    `pytest.fail` uretir. Gerekcesi olculdu — bu kanca bir seyin
    YOKLUGUNU (izin yok) kullanarak test atliyor, ve capasi kaydigi an
    atlama sessizce HIC olmazdi; o halde pin yine kirmizi uretir ve
    kimse bu listeyi suclamaz. Kontrol yalniz o dosya TOPLANDIYSA
    yapiliyor: alt kume kosusunda (`pytest tests/test_honesty.py`)
    eslesme olmamasi normaldir.
    """
    if os.getenv(_CANLI_LLM_IZNI) == "1":
        return

    sebep = ("canli (UCRETLI) embedding ister; izin: RYTHO_CANLI_LLM=1. "
             "Dogru son hal: kosulu testin kendi dosyasina skipif olarak "
             "koymak (bkz. conftest._CANLI_EMBEDDING_ISTEYENLER).")
    for imza in _CANLI_EMBEDDING_ISTEYENLER:
        dosya = imza.split("::", 1)[0]
        toplandi = any(dosya in item.nodeid for item in items)
        eslesen = [item for item in items if imza in item.nodeid]
        if toplandi and not eslesen:
            pytest.fail(
                f"conftest._CANLI_EMBEDDING_ISTEYENLER imzasi BAYAT: "
                f"{imza!r} hicbir teste uymuyor ama {dosya} toplandi. "
                f"Test yeniden adlandirildiysa imza da guncellenir; "
                f"canli embedding ihtiyaci kalktiysa girdi SILINIR.",
                pytrace=False)
        for item in eslesen:
            item.add_marker(pytest.mark.skip(reason=sebep))

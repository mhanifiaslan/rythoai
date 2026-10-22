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

import pytest

from core import ai_consent, app_gate, config
from core import firestore as firestore_client
from services import (account_service, consent_service, gemini_service,
                      partner_service)

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

    Auth'u BILEREK sinayan test `_auth_modulu`yu kendi sahtesiyle
    degistirir (test_partner_rewards `_auth_pinle`) ve o yama bunun
    USTUNE yazdigi icin kazanir — `kapi_hermetik`/`depolama_hermetik`
    ile ayni cikis yolu.
    """
    monkeypatch.setattr(partner_service, "_auth_modulu",
                        lambda: _AuthYok)


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


@pytest.fixture(autouse=True)
def ai_onayi_hermetik(monkeypatch, tmp_path):
    """AI onay kaydı ve zorlama eşiği her testte TEMİZ başlar (U06).

    İki sızıntı kapatılıyor:

    1. Yerel kayıt dosyası: Firestore pinliyken onay `config.CACHE_DIR`
       altındaki `ai_consent.json`'a yazılır — depodaki GERÇEK önbellek
       dizini. Bir testin yazdığı "Şimdi değil" (``granted: False``)
       kaydı kalıcı olur ve sonraki koşularda aynı uid'nin sohbet/rapor
       uçlarını 403'e düşürürdü; hata o testle hiç ilgisi olmayan bir
       yerde, üstelik yalnız İKİNCİ koşuda görünürdü.
    2. Eşik: memo süreç içi; env tabanı kabuktan gelebilir
       (`RYTHO_AI_CONSENT_MIN_BUILD`). İkisi de sıfırlanır — zorlamayı
       sınayan test eşiği kendisi kurar.
    """
    monkeypatch.setattr(consent_service, "_ai_local_store",
                        lambda: tmp_path / "ai_consent.json")
    monkeypatch.setattr(config, "AI_CONSENT_MIN_BUILD", 0)
    ai_consent.reset_memo()
    yield
    ai_consent.reset_memo()

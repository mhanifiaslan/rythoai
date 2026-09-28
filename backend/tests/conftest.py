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

import pytest

from core import app_gate, config
from core import firestore as firestore_client
from services import account_service, partner_service

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

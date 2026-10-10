"""Hata yolunun dili ve ham istisna sızıntısı.

Faz 3'te uç YANITLARI iki dile taşındı ama HATA yolu Türkçe kalmıştı.
İstemci sunucunun `detail` alanını doğrudan ekrana bastığı için (bkz.
apps/mobile/lib/core/api.dart, friendlyError) İngilizce kullanan biri kilitli
bir ekrana geldiğinde Türkçe metin görüyordu.

İkinci kusur: uçlar `detail=str(e)` döndürüyordu, yani Python istisna metni
kullanıcıya gösteriliyor ve sunucunun iç yapısı dışarı sızıyordu.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_messages.py -q
"""
import pytest
from fastapi.testclient import TestClient

from core import config, entitlements, i18n
from core.messages import _MESSAGES, text

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulaması içe aktarılamadı: {_APP_IMPORT_ERROR}",
)


# --------------------------------------------------------------------------
# Mesaj tablosu
# --------------------------------------------------------------------------

def test_her_mesaj_her_dilde_var():
    """Eksik çeviri sessizce Türkçeye düşer; tabloda hiç olmaması daha iyidir."""
    for anahtar, çeviriler in _MESSAGES.items():
        for kod in i18n.SUPPORTED:
            assert çeviriler.get(kod), f"{anahtar} -> {kod} eksik"


def test_ceviriler_birbirinden_farkli():
    """Kopyala-yapıştır artığı: aynı metnin iki dile de yazılması."""
    for anahtar, çeviriler in _MESSAGES.items():
        assert çeviriler["tr"] != çeviriler["en"], f"{anahtar} çevrilmemiş"


def test_dil_secimi():
    assert text("auth_required", "en") == _MESSAGES["auth_required"]["en"]
    assert text("auth_required", "tr") == _MESSAGES["auth_required"]["tr"]
    # Desteklenmeyen dil varsayılana düşer — istek patlamaz
    assert text("auth_required", "de") == _MESSAGES["auth_required"]["tr"]


def test_yedek_anahtar():
    """Yeni bir kilitli özellik eklendiğinde metni yoksa genel metne düşmeli."""
    sonuç = text("paywall.henuz_yok", "en", fallback="paywall.default")
    assert sonuç == _MESSAGES["paywall.default"]["en"]


def test_bilinmeyen_anahtar_bos_donmez():
    """Boş string, kullanıcıya boş bir hata kutusu göstermek olurdu."""
    assert text("boyle_bir_anahtar_yok", "en")


def test_kota_metnine_limit_yerlesir():
    # Şablon artık aylık hak ve bedel yer tutucuları da taşıyor; `format`
    # eksik anahtarda KeyError atar, o yüzden çağıranın tam kümesi geçilir
    # (bkz. test_kota_cagiranlarinin_kwarg_kumesi_yer_tutuculari_kapsar).
    assert "5" in text("quota.chat", "en", limit=5, allowance=100,
                       chat_cost=1, cost=1)
    assert "5" in text("quota.chat", "tr", limit=5, allowance=100,
                       chat_cost=1, cost=1)


# --------------------------------------------------------------------------
# Kota metni: vaat değil SAYI — ve sayı çağırandan gelir
# --------------------------------------------------------------------------
#
# `quota.chat` bir tur boyunca "Rytho+ ile sınırsız konuşabilirsin" /
# "removes the limit", `quota.iching` "istediğin kadar çekebilirsin" diyordu
# (ölçüldü 2026-10-10). Abone sınırsız DEĞİL: her mesaj cüzdandan düşer ve
# aylık hak tavanlı (wallet.charge_metered). ozellikler.md "İddia
# edilemeyecekler" tablosu "Sınırsız AI"yı yasaklıyor, doğrusu "Ayda N AI
# kredisi". Yasak kelimenin YOKLUĞUNU test_honesty.py ölçüyor; burası
# yerine gelen SAYININ doğru kaynaktan aktığını ölçüyor.

def test_kota_sablonu_sayi_soyler_vaat_degil():
    """`quota.chat` aylık hakkı ve mesaj bedelini, `quota.iching` çekim
    bedelini YER TUTUCU olarak taşır.

    Yer tutucu, elle yazılmış sayı DEĞİL: "Rytho+ ayda 100 kredi verir"
    diye yazılsaydı tavan değiştiğinde (300→100 bir kez oldu, K1) metin
    sessizce bayatlar ve kullanıcıya yanlış sayı söylenirdi. messages.py
    wallet'ı içe alamaz (döngü), o yüzden sayı şablona değil çağrıya girer.
    """
    for dil in i18n.SUPPORTED:
        sohbet = _MESSAGES["quota.chat"][dil]
        assert "{allowance}" in sohbet, (
            f"quota.chat/{dil} aylık hakkı yer tutucuyla söylemiyor")
        assert "{chat_cost}" in sohbet, (
            f"quota.chat/{dil} mesaj bedelini yer tutucuyla söylemiyor")
        assert "{cost}" in _MESSAGES["quota.iching"][dil], (
            f"quota.iching/{dil} çekim bedelini yer tutucuyla söylemiyor")


def _kota_cagri_kwarglari() -> dict[str, set[str]]:
    """`text(f"quota.{...}", ...)` çağrılarının kwarg adları — KAYNAKTAN.

    AST ile okunur, regex ile değil: çağrı iki-üç satıra yayılmış ve bir
    kwarg eklendiğinde/silindiğinde kalıp bakımı bekçiyi kör bırakırdı.
    Hem wallet hem entitlements taranır: `enforce_daily_quota` bugün
    çağrılmıyor ama `quota.chat` ile aynı şablona basıyor.
    """
    import ast
    from pathlib import Path

    kok = Path(__file__).resolve().parent.parent / "core"
    bulunan: dict[str, set[str]] = {}
    for dosya in ("wallet.py", "entitlements.py"):
        agac = ast.parse((kok / dosya).read_text(encoding="utf-8"))
        for dugum in ast.walk(agac):
            if not (isinstance(dugum, ast.Call)
                    and isinstance(dugum.func, ast.Name)
                    and dugum.func.id == "text" and dugum.args):
                continue
            ilk = dugum.args[0]
            if isinstance(ilk, ast.JoinedStr):
                baslangic = ilk.values[0]
                on_ek = (baslangic.value
                         if isinstance(baslangic, ast.Constant) else "")
            elif isinstance(ilk, ast.Constant):
                on_ek = str(ilk.value)
            else:
                continue
            if not str(on_ek).startswith("quota."):
                continue
            bulunan[f"{dosya}:{dugum.lineno}"] = {
                k.arg for k in dugum.keywords if k.arg and k.arg != "fallback"}
    return bulunan


def test_kota_cagiranlarinin_kwarg_kumesi_yer_tutuculari_kapsar():
    """Her `quota.*` şablonunun yer tutucuları ⊆ her çağıranın kwarg'ları.

    `str.format` eksik anahtarda KeyError atar: bir yer tutucu eklenip
    çağıranda unutulursa kullanıcı tam kotası dolduğu anda 402 yerine 500
    görür. Fazla kwarg zararsız (`format` yok sayar), eksik olan ölümcül.
    Kümeler KAYNAKTAN ölçülür; test kendi elle yazdığı kwarg listesiyle
    yeşil kalamaz.
    """
    from string import Formatter

    cagrilar = _kota_cagri_kwarglari()
    assert cagrilar, "hiç quota.* text() çağrısı bulunamadı — tarama bozuk"

    sablonlar = {anahtar: ceviriler for anahtar, ceviriler in _MESSAGES.items()
                 if anahtar.startswith("quota.")}
    assert "quota.chat" in sablonlar
    for anahtar, ceviriler in sablonlar.items():
        for dil, metin in ceviriler.items():
            yer_tutucular = {alan for _, alan, _, _ in Formatter().parse(metin)
                             if alan}
            for yer, kwarglar in cagrilar.items():
                eksik = yer_tutucular - kwarglar
                assert not eksik, (
                    f"{anahtar}/{dil} şablonu {sorted(eksik)} bekliyor ama "
                    f"{yer} çağrısı geçmiyor — kota dolduğunda KeyError/500")

    # Çalışma zamanı ikizi: sayılar GERÇEKTEN ürün sabitlerinden akıyor.
    from core import wallet

    sohbet = wallet.quota_detail("chat", 5, "en")
    assert str(wallet.MONTHLY_TOKEN_ALLOWANCE) in sohbet
    assert str(wallet.TOKEN_COSTS["chat"]) in sohbet
    assert "5" in sohbet
    cekim = wallet.quota_detail("iching", 1, "tr")
    assert str(wallet.TOKEN_COSTS["iching"]) in cekim


def test_her_ozellik_icin_paywall_metni_var():
    """require_plus ile korunan her özellik adının bir metni olmalı.

    Liste ELLE TUTULMUYOR: kaynak dosyalardan `require_plus("...")` çağrıları
    taranıyor. Elle tutulan önceki liste "firasa"yı kaçırmıştı — özellik
    kilitliydi ama kullanıcı jenerik metne düşüyordu ve bu test yeşildi.
    Testin görmediği kusur, kusur değil sanılıyor.
    """
    import re
    from pathlib import Path

    api_klasoru = Path(__file__).resolve().parent.parent / "api"
    bulunan: set[str] = set()
    for dosya in api_klasoru.glob("*.py"):
        bulunan.update(
            re.findall(r'require_plus\(\s*"(\w+)"\s*\)', dosya.read_text(encoding="utf-8"))
        )

    assert bulunan, "hiç require_plus çağrısı bulunamadı — tarama bozuk"
    for özellik in sorted(bulunan):
        assert f"paywall.{özellik}" in _MESSAGES, (
            f"require_plus({özellik!r}) kilitli ama paywall.{özellik} metni yok"
        )


# --------------------------------------------------------------------------
# Uç davranışı: hata metni kullanıcının dilinde
# --------------------------------------------------------------------------

@uygulama_gerekir
def test_paywall_metni_dile_gore(monkeypatch):
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: False)

    with TestClient(app) as client:
        tr = client.post("/api/v1/reports/dyad", json={"friend_uid": "x"},
                         headers={"Authorization": "Bearer t1"})
        en = client.post("/api/v1/reports/dyad", json={"friend_uid": "x"},
                         headers={"Authorization": "Bearer t2",
                                  "Accept-Language": "en-US,en;q=0.9"})

    assert tr.status_code == entitlements.PAYWALL_STATUS
    assert en.status_code == entitlements.PAYWALL_STATUS
    assert "Rytho+" in tr.json()["detail"]
    assert "abonel" in tr.json()["detail"].lower()
    assert "part of Rytho+" in en.json()["detail"]


@uygulama_gerekir
def test_kota_metni_dile_gore(monkeypatch):
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: False)
    monkeypatch.setattr(entitlements, "consume_quota", lambda *a: False)

    with TestClient(app) as client:
        en = client.post("/api/v1/chat", json={"message": "hello"},
                         headers={"Authorization": "Bearer t3",
                                  "Accept-Language": "en"})

    assert en.status_code == entitlements.PAYWALL_STATUS
    detay = en.json()["detail"]
    assert "Rytho+" in detay
    assert "sohbet" not in detay.lower(), "İngilizce isteğe Türkçe metin döndü"


@uygulama_gerekir
def test_kimlik_hatasi_dile_gore(monkeypatch):
    """401 metni de kullanıcıya gösteriliyor."""
    monkeypatch.setattr(config, "DEV_MODE", False)

    with TestClient(app) as client:
        tr = client.get("/api/v1/reports/horoscope/leo")
        en = client.get("/api/v1/reports/horoscope/leo",
                        headers={"Accept-Language": "en"})

    assert tr.status_code == 401
    assert en.status_code == 401
    assert "signed in" in en.json()["detail"]
    assert "oturum" in tr.json()["detail"].lower()


# --------------------------------------------------------------------------
# Ham istisna sızıntısı
# --------------------------------------------------------------------------

@uygulama_gerekir
def test_istisna_metni_kullaniciya_sizmaz(monkeypatch):
    """Kullanıcı "KeyError: 'sun'" değil, anlaşılır bir metin görmeli."""
    from services import astro_service

    def patla(**kwargs):
        raise KeyError("gizli_ic_alan")

    monkeypatch.setattr(astro_service, "get_natal_chart", patla)
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: True)

    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.post(
            "/api/v1/reports/daily",
            json={"year": 1990, "month": 5, "day": 12},
            headers={"Authorization": "Bearer t4", "Accept-Language": "en"},
        )

    assert response.status_code == 500
    detay = response.json()["detail"]
    assert "gizli_ic_alan" not in detay
    assert "KeyError" not in detay
    assert detay == _MESSAGES["internal"]["en"]

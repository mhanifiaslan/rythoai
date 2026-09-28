"""Zorunlu güncelleme kapısı (PBZ): sunucu zorlaması + sıcak anahtar.

Değişmezler:
- `/api/v1/` altında `X-App-Build < eşik` → 426; eşit/yeni geçer.
- Başlık YOK → build 0 → eşik > 0 iken 426 (K7); eşik 0 → herkes geçer.
- Muaf önekler ve `/api/v1/` dışı yollar başlıksız da geçer; OPTIONS geçer.
- Eşik = max(env, `config/app.minBuild`); Firestore yok/bozuk → env;
  okuma HİÇ fırlatmaz.
- 60 s süreç içi memo — `core/cache` DEĞİL (K8).
- 426 gövdesi: `code` + yerelleştirilmiş `detail` + `min_build` (K6).
- 426'lar kotaya tabi (RateLimit, AppGate'in dışında).
- Hermetiklik pini (tests/conftest.py): Firestore sahtelenmemişken eşik 0.
- `remember_build` HİÇ fırlatmaz — ayna best-effort, kimliği düşüremez.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_app_gate.py -q
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from core import app_gate, cache, config
from core.messages import text
from main import app

#: Kapı yönlendirme ÖNCESİ koşar: var olmayan uç geçerse 404, kilitliyse 426.
YOL = "/api/v1/astrology/olmayan-uc"


# ---------------------------------------------------------------------------
# Bellek içi sahte Firestore — app_gate'in kullandığı yüzey:
# collection().document().get()/set()
# ---------------------------------------------------------------------------

class _Anlik:
    def __init__(self, veri):
        self._veri = veri

    @property
    def exists(self):
        return self._veri is not None

    def to_dict(self):
        return dict(self._veri) if self._veri else {}


class NotFound(Exception):
    """Firestore'un var olmayan dokümana `update` yazımına verdiği yanıt.

    Sınıf ADI gerçeğiyle (`google.api_core.exceptions.NotFound`) birebir:
    `app_gate._DOKUMAN_YOK` sembole değil ADA bakıyor, bu sahte de o
    sözleşmeyi sınıyor.
    """


class _Dokuman:
    def __init__(self, depo, yol):
        self._depo = depo
        self._yol = yol

    def get(self):
        self._depo.okuma += 1
        return _Anlik(self._depo.docs.get(self._yol))

    def set(self, veri, merge=False):
        mevcut = dict(self._depo.docs.get(self._yol) or {}) if merge else {}
        mevcut.update(veri)
        self._depo.docs[self._yol] = mevcut

    def update(self, veri):
        """Gerçek Firestore gibi: doküman YOKSA yazmaz, NotFound fırlatır.

        Bu sadakat B9'un bekçisi — `set` semantiğiyle taklit edilse
        dirilme testte görünmez olurdu.
        """
        if self._yol not in self._depo.docs:
            raise NotFound(f"Doküman yok: {self._yol}")
        mevcut = dict(self._depo.docs[self._yol])
        mevcut.update(veri)
        self._depo.docs[self._yol] = mevcut


class _Koleksiyon:
    def __init__(self, depo, ad):
        self._depo = depo
        self._ad = ad

    def document(self, ad):
        return _Dokuman(self._depo, f"{self._ad}/{ad}")


class SahteFirestore:
    def __init__(self, docs=None):
        self.docs = dict(docs or {})
        self.okuma = 0

    def collection(self, ad):
        return _Koleksiyon(self, ad)


class _BozukFirestore:
    """İstemci var ama her erişim patlıyor (ağ/izin)."""

    def collection(self, ad):
        raise RuntimeError("Firestore düştü")


@pytest.fixture(autouse=True)
def temiz_memo():
    app_gate.reset_memo()
    yield
    app_gate.reset_memo()


@pytest.fixture()
def esik(monkeypatch):
    """config/app.minBuild = 35, env tabanı 0."""
    depo = SahteFirestore({"config/app": {"minBuild": 35}})
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: depo)
    monkeypatch.setattr(config, "MIN_APP_BUILD", 0)
    return depo


# Kota anahtarı Authorization başlığının özeti; her test KENDİ başlığını
# verir ki kovalar ayrılsın (test_hardening deseni).
def _baslik(ad: str, build: int | str | None = None, **ek: str) -> dict:
    h = {"Authorization": f"Bearer kapi-testi-{ad}"}
    if build is not None:
        h["X-App-Build"] = str(build)
    h.update(ek)
    return h


# ---------------------------------------------------------------------------
# Kapı
# ---------------------------------------------------------------------------

def test_eski_build_426(esik):
    with TestClient(app) as client:
        yanit = client.get(YOL, headers=_baslik("eski", 34))
    assert yanit.status_code == 426


def test_esit_ve_yeni_build_gecer(esik):
    with TestClient(app) as client:
        esit = client.get(YOL, headers=_baslik("esit", 35))
        yeni = client.get(YOL, headers=_baslik("yeni", 36))
    assert esit.status_code == 404, "eşit build kapıdan geçmeli"
    assert yeni.status_code == 404


def test_basliksiz_istek_esik_acikken_426(esik):
    """K7: başlık yoksa build 0 sayılır — açık oturumdaki ≤34 da kilitlenir."""
    with TestClient(app) as client:
        yanit = client.get(YOL, headers=_baslik("basliksiz"))
    assert yanit.status_code == 426


def test_basliksiz_istek_esik_sifirken_gecer(esik):
    esik.docs["config/app"] = {"minBuild": 0}
    with TestClient(app) as client:
        yanit = client.get(YOL, headers=_baslik("sifir"))
    assert yanit.status_code == 404


@pytest.mark.parametrize("bozuk", ["abc", "-3", "35abc", "", "35.0"])
def test_bozuk_baslik_sifir_sayilir(esik, bozuk):
    with TestClient(app) as client:
        yanit = client.get(YOL, headers=_baslik("bozuk-" + bozuk, bozuk))
    assert yanit.status_code == 426, bozuk


@pytest.mark.parametrize("yol", [
    "/api/v1/config/app",           # eşiğin kendisi — kilitli istemci de okur
    "/api/v1/admin/stats",          # panel (tarayıcı, versionCode yok)
    "/api/v1/billing/revenuecat",   # RevenueCat webhook
    "/api/v1/notify/run",           # Cloud Scheduler
    "/api/v1/maintenance/cleanup",  # Cloud Scheduler
    "/health",                      # /api/v1/ dışı — panel çağırıyor
    "/healthz",
    "/",
])
def test_muaf_yollar_basliksiz_gecer(esik, yol):
    with TestClient(app) as client:
        muaf = client.get(yol, headers=_baslik("muaf-" + yol))
        kontrol = client.get(YOL, headers=_baslik("muaf-kontrol-" + yol))
    assert muaf.status_code != 426, yol
    # Pozitif kontrol: aynı koşulda muaf olmayan yol kilitli.
    assert kontrol.status_code == 426


def test_options_preflight_gecer(esik):
    """Preflight en içteki CORS'a ulaşmalı; kapı OPTIONS'a bakmaz."""
    with TestClient(app) as client:
        yanit = client.options(YOL, headers={
            "Origin": "http://localhost",
            "Access-Control-Request-Method": "GET",
        })
    assert yanit.status_code == 200
    assert "access-control-allow-origin" in yanit.headers


def test_426_kotaya_tabi(esik):
    """Sıra: RateLimit → AppGate. 426'lar kotayı yer; kapı dışarıda olsaydı
    kimliksiz sel sonsuz 426 alırdı ve kota hiç işlemezdi."""
    with TestClient(app) as client:
        for _ in range(60):
            yanit = client.get(YOL, headers=_baslik("kota", 1))
            assert yanit.status_code == 426
        yanit = client.get(YOL, headers=_baslik("kota", 1))
    assert yanit.status_code == 429


# ---------------------------------------------------------------------------
# Eşik kaynağı: env tabanı + doküman
# ---------------------------------------------------------------------------

def test_dokuman_env_tabanini_gecer(esik, monkeypatch):
    monkeypatch.setattr(config, "MIN_APP_BUILD", 10)
    assert app_gate.current_min_build() == 35
    with TestClient(app) as client:
        yanit = client.get(YOL, headers=_baslik("dok-env", 20))
    assert yanit.status_code == 426


def test_env_dokumani_gecer(esik, monkeypatch):
    """Env yalnız TABAN: dokümandan büyükse o geçerli (panel 0 yazsa da)."""
    monkeypatch.setattr(config, "MIN_APP_BUILD", 40)
    assert app_gate.current_min_build() == 40
    with TestClient(app) as client:
        kilit = client.get(YOL, headers=_baslik("env-dok-a", 35))
        gecer = client.get(YOL, headers=_baslik("env-dok-b", 40))
    assert kilit.status_code == 426
    assert gecer.status_code == 404


def test_firestore_yokken_env(monkeypatch):
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: None)
    monkeypatch.setattr(config, "MIN_APP_BUILD", 7)
    assert app_gate.current_min_build() == 7


def test_firestore_dusunce_env_ve_firlatmaz(monkeypatch):
    monkeypatch.setattr(app_gate.firestore_client, "get_client",
                        lambda: _BozukFirestore())
    monkeypatch.setattr(config, "MIN_APP_BUILD", 7)
    assert app_gate.current_min_build() == 7
    with TestClient(app) as client:
        yanit = client.get(YOL, headers=_baslik("dusen", 7))
    assert yanit.status_code == 404, "kapı Firestore düştü diye isteği düşüremez"


@pytest.mark.parametrize("dokuman", [
    {"minBuild": "abc"}, {"minBuild": -5}, {"minBuild": None}, {},
    {"minBuild": "35.0"}, {"minBuild": True},
])
def test_bozuk_dokuman_yok_sayilir(monkeypatch, dokuman):
    depo = SahteFirestore({"config/app": dokuman})
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: depo)
    monkeypatch.setattr(config, "MIN_APP_BUILD", 3)
    assert app_gate.current_min_build() == 3, dokuman


def test_parse_build():
    assert app_gate.parse_build(None) == 0
    assert app_gate.parse_build("35") == 35
    assert app_gate.parse_build(" 35 ") == 35
    assert app_gate.parse_build(35) == 35
    assert app_gate.parse_build("-1") == 0
    assert app_gate.parse_build("x") == 0
    assert app_gate.parse_build(True) == 0


# ---------------------------------------------------------------------------
# Memo
# ---------------------------------------------------------------------------

def test_memo_60_saniye(esik, monkeypatch):
    saat = [1000.0]
    monkeypatch.setattr(app_gate, "_now", lambda: saat[0])

    assert app_gate.current_min_build() == 35
    assert esik.okuma == 1
    esik.docs["config/app"] = {"minBuild": 50}

    for _ in range(5):
        assert app_gate.current_min_build() == 35
    assert esik.okuma == 1, "memo varken Firestore'a gidilmemeli"

    saat[0] += 59
    assert app_gate.current_min_build() == 35
    saat[0] += 2
    assert app_gate.current_min_build() == 50
    assert esik.okuma == 2


def test_memo_reset_yeni_degeri_hemen_gorur(esik):
    assert app_gate.current_min_build() == 35
    esik.docs["config/app"] = {"minBuild": 36}
    app_gate.reset_memo()
    assert app_gate.current_min_build() == 36


def test_memo_hata_yolunda_da_kurulur(monkeypatch):
    """Düşen Firestore her istekte yeniden yoklanmaz."""
    sayac = {"n": 0}

    def dusen():
        sayac["n"] += 1
        raise RuntimeError("Firestore düştü")

    class _Depo:
        def collection(self, ad):
            dusen()

    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: _Depo())
    monkeypatch.setattr(config, "MIN_APP_BUILD", 0)
    for _ in range(5):
        assert app_gate.current_min_build() == 0
    assert sayac["n"] == 1


def test_memo_core_cache_kullanmaz(esik, monkeypatch):
    """K8: core/cache kalıcı katmana da yazar — bir okuma okuma+yazma olurdu."""
    def yasak(*a, **k):
        raise AssertionError("app_gate core.cache'e dokunmamalı")

    monkeypatch.setattr(cache, "get", yasak)
    monkeypatch.setattr(cache, "set", yasak)
    assert app_gate.current_min_build() == 35
    assert app_gate.current_min_build() == 35


# ---------------------------------------------------------------------------
# 426 gövdesi
# ---------------------------------------------------------------------------

def test_426_govdesi_dil_ve_min_build(esik):
    with TestClient(app) as client:
        en = client.get(YOL, headers=_baslik("govde-en", 34,
                                             **{"Accept-Language": "en-GB"}))
        tr = client.get(YOL, headers=_baslik("govde-tr", 34))
    for yanit in (en, tr):
        assert yanit.status_code == 426
        govde = yanit.json()
        assert govde["status"] == "error"
        assert govde["code"] == "update_required"
        assert govde["min_build"] == 35
    assert en.json()["detail"] == text("update_required", "en")
    assert tr.json()["detail"] == text("update_required", "tr")
    # K6: ≤34 istemci detail'i olduğu gibi basıyor — ham kod orada olmamalı.
    assert "update_required" not in tr.json()["detail"]


# ---------------------------------------------------------------------------
# Hermetiklik pini (tests/conftest.py)
# ---------------------------------------------------------------------------

def test_pin_get_client_URETIME_ULASMAZ():
    """conftest `firestore_hermetik`: `get_client` varsayilan olarak None.

    ⚠️ Bu bekci bir VARSAYIMLA degil KANITLA kondu. 2026-09-18'de uretim
    `rhytoai` projesinde `users/dev-user` dokumani bulundu ve icinde o gun
    yazilmis bir `termsConsent` vardi; `dev-user` DEV_MODE'un uid'i ve
    `RYTHO_DEV_MODE` varsayilani "1". Yani bir kosu gercek Firestore'a
    ULASMISTI. Pin konduktan sonra tam takimin suresi 214 sn'den 83 sn'ye
    dustu -- sizinti hem gercekti hem yayginmis.

    `kapi_hermetik` yalniz ESIK OKUMASINI koruyordu; bu pin `get_client`in
    KENDISINI kapatiyor.
    """
    from core import firestore as fc

    assert fc.get_client() is None, (
        "test Firestore istemcisi aliyor: ADC'li makinede bu URETIM "
        "projesidir ve yazim gercek veriye gider")


def test_pin_firestore_sahtelenmemisken_esik_sifir(monkeypatch):
    """conftest `kapi_hermetik`: `get_client` gerçek kurucuyken doküman
    OKUNMAZ, eşik 0. Üretimde `config/app.minBuild` = 40 yazılsa bile
    ADC'li makinede kapıyı düşünmeyen başlıksız istekler geçmeli — yoksa
    panelden eşik yazıldığı an paketin tamamı 426 ile düşerdi. "Gerçek
    doküman 40 der" durumu `read_doc` seviyesinde kurulur (istemci
    dokunulmaz kalır): pin olmasa okuma yolu 40 döner, test kızarır."""
    okumalar = {"n": 0}

    def dokuman_40():
        okumalar["n"] += 1
        return {"minBuild": 40}

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(app_gate, "read_doc", dokuman_40)
        assert app_gate.current_min_build() == 0
        assert okumalar["n"] == 0, "pin varken doküman hiç okunmamalı"
        with TestClient(app) as client:
            yanit = client.get(YOL, headers=_baslik("pin-basliksiz"))
        assert yanit.status_code == 404

    # Çıkış yolu: istemci sahtelenince pin kalkar, aynı doküman kilitler —
    # kapı testleri gerçek mantığı böyle çalıştırır.
    app_gate.reset_memo()
    depo = SahteFirestore({"config/app": {"minBuild": 40}})
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: depo)
    assert app_gate.current_min_build() == 40
    with TestClient(app) as client:
        yanit = client.get(YOL, headers=_baslik("pin-kontrol"))
    assert yanit.status_code == 426


# ---------------------------------------------------------------------------
# Sürüm aynası: remember_build hiç fırlatmaz
# ---------------------------------------------------------------------------

def test_remember_build_yazim_dusunce_firlatmaz_memo_kurmaz(monkeypatch):
    monkeypatch.setattr(app_gate.firestore_client, "get_client",
                        lambda: _BozukFirestore())
    assert app_gate.remember_build("u1", 35) is None
    assert not app_gate.build_remembered("u1", 35), \
        "düşen yazım memo kurmamalı; sonraki istek yeniden dener"

    depo = SahteFirestore({"users/u1": {"language": "tr"}})
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: depo)
    assert app_gate.remember_build("u1", 35) is None
    assert depo.docs["users/u1"] == {"language": "tr", "appBuild": 35}
    assert app_gate.build_remembered("u1", 35)


# ---------------------------------------------------------------------------
# B9: ayna silinmiş hesabı DİRİLTMEZ (ölçüldü 2026-09-18, üretimde)
# ---------------------------------------------------------------------------

def test_remember_build_dokuman_yoksa_YARATMAZ(monkeypatch):
    """Bulgu B9'un çekirdeği.

    `delete_account` `users/{uid}`'yi siliyor ama kimlik jetonu bir saate
    kadar geçerli kalıyor. O pencerede gelen tek kimlikli istek buradan
    geçiyor; yazım `set(merge=True)` olduğu sürece dokümanı
    `{appBuild: N}` iskeletiyle GERİ getiriyordu — üretimde ölçülen yetim
    dokümanların dördü tam böyleydi.
    """
    depo = SahteFirestore()
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: depo)
    assert app_gate.remember_build("silinmis-uid", 46) is None
    assert depo.docs == {}, "silinmiş hesap aynayla dirildi"


def test_remember_build_dokuman_yoksa_memo_kurmaz_sonra_yazar(monkeypatch):
    """Yeni kullanıcı SESSİZCE kaybolmamalı.

    `users/{uid}` oturum açılışında istemcide doğuyor; ilk kimlikli istek
    o doğumun önüne geçebilir. Ayna o istekte yazmaz ama memo da KURMAZ —
    doküman doğduktan sonraki ilk istek yazar. Bu iki koşul birlikte
    olmasa düzeltme sessiz bir gerilemeye dönerdi: 24 saat boyunca hiçbir
    yazım denenmez ve panelin sürüm kırılımı yeni kullanıcıyı hiç görmez.
    """
    depo = SahteFirestore()
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: depo)
    app_gate.remember_build("yeni", 46)
    assert not app_gate.build_remembered("yeni", 46)

    # İstemci dokümanı doğurdu (language_sync._firestoreWrite).
    depo.docs["users/yeni"] = {"language": "tr"}
    app_gate.remember_build("yeni", 46)
    assert depo.docs["users/yeni"]["appBuild"] == 46
    assert app_gate.build_remembered("yeni", 46)


def test_remember_build_memo_budamasi_dusse_de_firlatmaz(monkeypatch):
    """Havuzda eşzamanlı koşar: budama sırasında başka bir iş parçacığı
    sözlüğü değiştirir ("dictionary changed size during iteration") ya da
    `reset_memo()` temizler. Sızarsa core/auth'un genel except'i geçerli
    token'ı 401'e çevirir. Sözlüğün `items()`'ı patlatılır; yazım yapılmış
    olmalı, çağrı None dönmeli."""
    class _KaypakMemo(dict):
        def items(self):
            raise RuntimeError("dictionary changed size during iteration")

    depo = SahteFirestore({"users/u1": {}})
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: depo)
    monkeypatch.setattr(app_gate, "_BUILD_MEMO_PRUNE_AT", 1)
    monkeypatch.setattr(app_gate, "_build_memo",
                        _KaypakMemo({"u0": (35, 0.0)}))
    assert app_gate.remember_build("u1", 35) is None
    assert depo.docs["users/u1"] == {"appBuild": 35}


def test_remember_build_budama_suresi_dolanlari_atar(monkeypatch):
    """Budama anlık kopya üzerinde döner: süresi dolan atılır, taze kalır."""
    saat = [1000.0]
    monkeypatch.setattr(app_gate, "_now", lambda: saat[0])
    # Dokümanlar VAR: ayna artık `update` kullanıyor ve yoksa yazmaz (B9).
    depo = SahteFirestore({"users/eski": {}, "users/taze": {},
                           "users/yeni": {}})
    monkeypatch.setattr(app_gate.firestore_client, "get_client", lambda: depo)
    monkeypatch.setattr(app_gate, "_BUILD_MEMO_PRUNE_AT", 2)

    app_gate.remember_build("eski", 35)
    saat[0] += app_gate.BUILD_MEMO_TTL + 1
    app_gate.remember_build("taze", 35)
    app_gate.remember_build("yeni", 35)      # boy 2 → budama
    assert set(app_gate._build_memo) == {"taze", "yeni"}
    assert app_gate.build_remembered("taze", 35)
    assert app_gate.build_remembered("yeni", 35)


# ---------------------------------------------------------------------------
# Altyapı bekçileri: rules + deploy betiği (test_face_consent deseni)
# ---------------------------------------------------------------------------

def _repo_dosyasi(*parcalar: str) -> str:
    from pathlib import Path
    return (Path(__file__).resolve().parent.parent.parent
            .joinpath(*parcalar)).read_text(encoding="utf-8")


def test_rules_appbuild_listede_ve_degismez():
    """K10: `appBuild` sunucu yazımlı ama `hasOnly` listesinde OLMALI —
    yoksa 35'in ilk kimlikli isteğinden sonra istemcinin TÜM profil
    yazımları permission-denied ile düşer (platform/faceConsent vakası;
    motor merge'de SONUÇ dokümana bakar). Ve DEĞİŞMEZ olmalı — yoksa
    istemci sürümünü sahteler, K9 doğrulaması ve "eşiğin altında" sayımı
    istemcinin insafına kalır."""
    kurallar = _repo_dosyasi("infra", "firestore.rules")
    bas = kurallar.index("match /users/{uid}")
    liste_son = kurallar.index("]);", bas)
    assert "'appBuild'" in kurallar[bas:liste_son], (
        "appBuild hasOnly listesinde değil; sunucu aynayı yazınca "
        "istemcinin merge yazımları düşer.")
    # AD-turu: `appBuildDegismedi()` sunucu yazımlı alanların ortak
    # bekçisi `sunucuAlanlariDegismedi()` içine genelleşti — değişmez aynı.
    assert "function sunucuAlanlariDegismedi()" in kurallar, (
        "değişmezlik yardımcısı yok.")
    assert "sunucuAlaniDegismedi('appBuild')" in kurallar, (
        "appBuild ortak bekçide listelenmiyor.")
    kural_son = kurallar.index("allow delete", bas)
    assert "sunucuAlanlariDegismedi()" in kurallar[bas:kural_son], (
        "yardımcı tanımlı ama users/{uid} kuralında çağrılmıyor.")
    assert ("request.resource.data[alan] == resource.data[alan]"
            in kurallar), "değişmezlik eşitlik ile kurulmamış."


def test_deploy_betigi_min_build_envini_yazmaz():
    """Sıcak anahtarın varlık sebebi: `--set-env-vars` içindeki
    `RYTHO_MIN_BUILD=0` her deploy'da elle verilen eşiği sessizce
    sıfırlıyordu (34 sürümdür kapı hiç kurulmadı). Betik env'i HİÇ
    tanımlamamalı — env yalnız isteğe bağlı taban, anahtar config/app."""
    betik = _repo_dosyasi("infra", "deploy-backend.ps1")
    ayar = [s for s in betik.splitlines()
            if "--set-env-vars" in s and not s.lstrip().startswith("#")]
    assert ayar, "deploy betiğinde --set-env-vars satırı bulunamadı"
    for satir in ayar:
        assert "RYTHO_MIN_BUILD" not in satir, satir

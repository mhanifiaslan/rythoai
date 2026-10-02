"""Zamanlanmış işin SESSİZLİĞİ (SZ-turu): tamamen düşen koşu 200 DÖNMEZ.

Bu dosyanın tek derdi DURUM KODU. Gerekçesi ölçüldü (2026-10-02): üretim
yolundaki Gemini 403'ü bir AY boyunca hiçbir yerde kırmızı görünmedi.
Sebep bildirim ucuydu — `signal_push` üretim düşünce sinyalin şablon
"teknik" satırına düşüp push'u normal gönderiyor, yani `sent` sağlıklı
çıkıyor ve uç 200 dönüyordu. Cloud Scheduler günlüğü yalnız durum kodunu
gösterir; yanıt gövdesini kimse açmaz. Bu yüzden "gövdeye sayı eklemek"
tek başına bir onarım DEĞİL: kırmızı olan şey durum kodu olmak zorunda.

Çivilenen değişmezler:

1. Üretimin TAMAMI düştüyse uç 503 döner ve gövde sayıları taşır.
2. Gönderimin TAMAMI düştüyse uç 503 döner (FCM hiç kullanılamadığında
   `push_service.send` tek satır bile denemeden hepsini başarısız sayıyor).
3. KISMİ başarısızlık kırmızı DEĞİLDİR — bir bozuk profil koşuyu düşürmez.
4. Eşiğin altında (deneme < 3) kırmızı yanmaz: orada "hepsi düştü" ile
   "o tek profil bozuk" ayırt edilemez.
5. Prova (`dry_run`) kırmızı yanmaz: gönderim orada tanım gereği denenmez.
6. `notifyRuns.lastStatus` ile ucun döndüğü durum AYNI addır — panel
   "ok" derken Scheduler 503 görmemeli.
7. Üretim tetiklemeyen tür (`streak`) boş bir üretim dökümüyle yeşil
   kalır: boş döküm "ölçülemedi" demek, "düştü" demek değil.

Çalıştırma:
  .venv/Scripts/python.exe -m pytest tests/test_zamanlanmis_is_sessizligi.py -q
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from core import cache, config
from services import notification_service as ns
from services import notify_runner, push_service, signal_service

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulamasi ice aktarilamadi: {_APP_IMPORT_ERROR}",
)

SAHTE_GOKYUZU = {"moon_phase": {"key": "full_moon", "name": "Dolunay",
                                "illumination": 98}, "retrogrades": []}

#: Eşiği (3) GEÇEN en küçük profil sayısı. Sabit yazılmadı: eşik değişirse
#: bu testler sessizce eşiğin altına düşüp hepsi yeşil kalırdı.
PROFIL_SAYISI = notify_runner._KIRMIZI_ESIGI


@pytest.fixture(autouse=True)
def temiz_onbellek(tmp_path, monkeypatch):
    """Önbellek dosya tabanlı ve TESTE ÖZEL.

    Üretimin başarılı olup olmadığı GERÇEK önbellek kaydından okunuyor
    (`signal_service.bundle_key`). `cache.get` sahtelenseydi test, ucun
    doğru anahtara baktığını değil yalnız bir çağrı yaptığını ölçerdi.
    """
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    yield
    cache._memory.clear()


def _profil(sira: int) -> dict:
    """Bildirim almaya uygun asgari profil; sessiz saat kapalı."""
    return {
        "uid": f"u{sira}",
        "fcmToken": f"token-{sira}",
        "onboardingCompleted": True,
        "timezone": "Europe/Istanbul",
        "language": "tr",
        "sunSign": "Aslan ♌",
        "streakCount": 5,
        "quietFrom": 0,
        "quietTo": 0,
    }


def _iz(sira: int) -> str:
    """Her profilin KENDİ parmak izi: paketi tek tek sıcak/soğuk yapabilmek
    için (kısmi başarısızlık testi tam olarak buna dayanıyor)."""
    return f"iz-{sira}"


def _paket_isit(sira: int, lang: str = "tr") -> None:
    """O profilin kişisel AI paketini önbelleğe yazar — üretim BAŞARILI."""
    cache.set(signal_service.bundle_key(_iz(sira), lang),
              {"insights": ["Bugün ölçülü bir açı var."],
               "checkin_question": None},
              ttl_seconds=3600)


def _paket_coz(sira: int, lang: str = "tr") -> None:
    """Üretimin DÜŞTÜĞÜ hâl: `cached_insight_bundle`in kısa ömürlü
    başarısızlık sentinel'i. Gemini 403 verdiğinde canlıda yazılan kayıt
    birebir bu — "anahtar hiç yok" hâli de aynı sonucu vermeli, ikisi de
    sınanıyor."""
    cache.set(signal_service.bundle_key(_iz(sira), lang),
              {"insights": None, "checkin_question": None, "failed": True},
              ttl_seconds=3600)


@pytest.fixture()
def kosu(monkeypatch):
    """Üç profilli bir `daily` koşusu; gönderim başarılı, kayıtlar izlenir.

    `signal_push` sahtelenir çünkü ölçülen şey onun İÇİ değil: koşunun
    üretimin düştüğünü GÖRÜP GÖRMEDİĞİ. Sahte, canlıdaki davranışı birebir
    taklit eder — paket olsa da olmasa da bir gövde döndürür (teknik satır),
    yani kusur yalnız önbellek kaydından anlaşılabilir.
    """
    kayit: dict = {"kosu": [], "isaretlenen": []}
    monkeypatch.setattr(config, "NOTIFY_SCHEDULER_SECRET", "dogru")
    monkeypatch.setattr(notify_runner, "get_sky_now", lambda: SAHTE_GOKYUZU)
    monkeypatch.setattr(notify_runner, "_iter_profiles", lambda: iter(
        [_profil(i) for i in range(1, PROFIL_SAYISI + 1)]))
    monkeypatch.setattr(ns, "already_sent", lambda uid, tur, gun: False)
    monkeypatch.setattr(ns, "last_daily_sent", lambda uid: None)
    monkeypatch.setattr(
        ns, "signal_push",
        lambda p, lang, today=None, onceki=None: (
            "🌙 Bugün: İç dünya", "Bugün ölçülü bir açı var.",
            _iz(int(p["uid"][1:])), 0, {}))
    monkeypatch.setattr(
        ns, "mark_sent",
        lambda uid, tur, gun, extra=None: kayit["isaretlenen"].append(uid))
    monkeypatch.setattr(
        notify_runner, "_kosu_kaydet",
        lambda tur, gun, sonuc, an: kayit["kosu"].append(sonuc))
    monkeypatch.setattr(push_service, "send", lambda m: push_service.SendResult(
        sent=len(m), failed=0, pruned=[], failed_uids=[]))
    return kayit


def _cagir(ek: str = "") -> object:
    with TestClient(app) as client:
        return client.post(f"/api/v1/notify/run?type=daily&force=true{ek}",
                           headers={"Authorization": "dogru"})


# --------------------------------------------------------------------------
# 1 + 2: tamamen düşen koşu kırmızı
# --------------------------------------------------------------------------

@uygulama_gerekir
def test_uretim_tamamen_dustugunde_uc_200_donmez(kosu):
    """ÖLÇÜLEN kesintinin birebir taklidi: her üretim düşüyor ama push'lar
    gidiyor. Eskiden 200 + sent=3 idi; bir ay boyunca görünen şey buydu."""
    for i in range(1, PROFIL_SAYISI + 1):
        _paket_coz(i)

    yanit = _cagir()

    assert yanit.status_code == 503
    govde = yanit.json()["detail"]
    assert govde["status"] == "uretim-tamamen-dustu"
    # Sayılar gövdede: kaç denendi, kaç başarılı, kaç düştü.
    assert govde["generation"] == {"attempted": PROFIL_SAYISI,
                                   "fallback": PROFIL_SAYISI}
    # Push'ların gitmiş olması kusuru maskelemiyor — kapı tam da bu.
    assert govde["sent"] == PROFIL_SAYISI and govde["failed"] == 0


@uygulama_gerekir
def test_paket_kaydi_hic_yokken_de_kirmizi(kosu):
    """Sentinel yazılamadığı hâl (önbellek yazımı da düştü) aynı sonucu
    vermeli: kayıt YOK da "üretilemedi" demektir."""
    yanit = _cagir()
    assert yanit.status_code == 503
    assert yanit.json()["detail"]["status"] == "uretim-tamamen-dustu"


@uygulama_gerekir
def test_gonderim_tamamen_dustugunde_uc_200_donmez(kosu, monkeypatch):
    """FCM hiç kullanılamadığında `push_service.send` tek satır bile
    denemeden hepsini başarısız sayıyor; koşu buna da "ok" diyordu."""
    for i in range(1, PROFIL_SAYISI + 1):
        _paket_isit(i)
    monkeypatch.setattr(push_service, "send", lambda m: push_service.SendResult(
        sent=0, failed=len(m), pruned=[], failed_uids=[x.uid for x in m]))

    yanit = _cagir()

    assert yanit.status_code == 503
    govde = yanit.json()["detail"]
    assert govde["status"] == "gonderim-tamamen-dustu"
    assert govde["queued"] == PROFIL_SAYISI and govde["sent"] == 0
    # Üretim sağlamdı: gerekçe doğru kapıyı göstermeli.
    assert govde["generation"]["ok"] == PROFIL_SAYISI


# --------------------------------------------------------------------------
# 3 + 4: yanlış alarm üretmemeli
# --------------------------------------------------------------------------

@uygulama_gerekir
def test_uretim_calisirken_uc_200_doner(kosu):
    """Sağlıklı koşu yeşil kalmalı; aksi halde bekçi her saat yanar ve
    okunmaz hâle gelir (kusurun kökü tam olarak okunmayan günlüktü)."""
    for i in range(1, PROFIL_SAYISI + 1):
        _paket_isit(i)

    yanit = _cagir()

    assert yanit.status_code == 200
    govde = yanit.json()
    assert govde["status"] == "ok"
    assert govde["generation"] == {"attempted": PROFIL_SAYISI,
                                   "ok": PROFIL_SAYISI}


@uygulama_gerekir
def test_kismi_dusus_kirmizi_degil(kosu):
    """Tek bir kullanıcının verisi bozuk olabilir; o yüzden tüm koşuyu
    kırmızı yapmak yanlış alarmdır. Sayılar yine görünür."""
    _paket_isit(1)
    for i in range(2, PROFIL_SAYISI + 1):
        _paket_coz(i)

    yanit = _cagir()

    assert yanit.status_code == 200
    govde = yanit.json()
    assert govde["status"] == "ok"
    assert govde["generation"]["ok"] == 1
    assert govde["generation"]["fallback"] == PROFIL_SAYISI - 1


@uygulama_gerekir
def test_esigin_altinda_kirmizi_yanmaz(kosu, monkeypatch):
    """Eşiğin altında "hepsi düştü" ile "o tek profil bozuk" AYNI
    gözlemdir; ayırt edilemeyen şeyden alarm üretilmez."""
    monkeypatch.setattr(notify_runner, "_iter_profiles", lambda: iter(
        [_profil(i) for i in range(1, PROFIL_SAYISI)]))

    yanit = _cagir()

    assert yanit.status_code == 200
    assert yanit.json()["status"] == "ok"
    # Sayaçlar `skipped`/`languages` gibi SEYREK: sıfır kalan anahtar hiç
    # yazılmaz, yani "ok" anahtarının YOKLUĞU sıfır demek.
    assert yanit.json()["generation"] == {"attempted": PROFIL_SAYISI - 1,
                                          "fallback": PROFIL_SAYISI - 1}


@uygulama_gerekir
def test_prova_kirmizi_yanmaz(kosu):
    """Provada gönderim DENENMEZ (`sent` tanım gereği 0); gönderim kapısı
    orada her zaman yanardı. Prova operatörün gözü önünde koşar."""
    yanit = _cagir("&dry_run=true")

    assert yanit.status_code == 200
    assert yanit.json()["status"] == "dry-run"
    # Prova gövdesi üretim sayılarını yine taşır: operatör okuyabilsin.
    assert yanit.json()["generation"]["attempted"] == PROFIL_SAYISI


@uygulama_gerekir
def test_uretim_tetiklemeyen_tur_yesil_kalir(kosu):
    """`streak` üretim tetiklemez, dökümü boş gelir. Boş döküm "ölçülemedi"
    demek; "düştü" sayılsaydı seri hatırlatması her saat kırmızı yanardı."""
    with TestClient(app) as client:
        yanit = client.post("/api/v1/notify/run?type=streak&force=true",
                            headers={"Authorization": "dogru"})

    assert yanit.status_code == 200
    assert yanit.json()["status"] == "ok"
    assert yanit.json()["generation"] == {}
    assert yanit.json()["sent"] == PROFIL_SAYISI


# --------------------------------------------------------------------------
# 6: panel ile Scheduler aynı adı görmeli
# --------------------------------------------------------------------------

@uygulama_gerekir
def test_kosu_kaydi_ayni_durumu_tasir(kosu):
    """`notifyRuns.lastStatus` ile ucun döndüğü durum AYNI ad olmalı.
    Ayrışsaydı panel "ok" derken Scheduler 503 görür ve kusuru aramak bir
    tur daha gecikirdi."""
    for i in range(1, PROFIL_SAYISI + 1):
        _paket_coz(i)

    yanit = _cagir()

    assert yanit.status_code == 503
    assert len(kosu["kosu"]) == 1
    assert kosu["kosu"][0].status == "uretim-tamamen-dustu"

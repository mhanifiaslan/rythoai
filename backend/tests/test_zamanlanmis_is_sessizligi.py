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

import datetime as dt

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


# --------------------------------------------------------------------------
# B3: kirmizi esigi SLOT BASINA
# --------------------------------------------------------------------------

def _sonuc(type_: str, **gen) -> notify_runner.RunResult:
    """Kapiyi UNIT olarak sinamak icin asgari RunResult.

    Uctan ucu kurmak yerine kapi dogrudan olculuyor: `winback` icin tam
    kuyruk kurmak (sessizlik epizodu + basamak durumu + olcum dususu)
    testin olctugu seyi kapidan uzaklastirir ve kirilma yeri belirsizlesir.
    `daily` ucu zaten yukaridaki uctan-uca bekcilerle civili.
    """
    return notify_runner.RunResult(
        status="ok", type=type_, scanned=1, queued=gen.pop("queued", 0),
        sent=gen.pop("sent", 0), failed=0, pruned=0, skipped={},
        generation=dict(gen))


def test_winback_tek_adayla_da_kirmizi_yanar():
    """B3'un cekirdegi: esik 3 iken `winback` kapisi HIC dolmuyordu.

    Olculdu (gercek `winback_tier`, 18 profil ve HEPSI sessiz — ust
    sinir): bir kosunun kuyrugu ortalama 0.79, en cok 2, 3'e ulasma
    orani %0. Cunku `winback_tier` basamagi bir kez gonderdikten sonra
    susuyor, yani bir kullanici 30 gunluk sessizlik epizodunda EN FAZLA
    UC kosuda kuyruga giriyor. Sabit esik 3'te uretim tamamen dusse de
    uc 200 donuyordu: bu turun dersi yeni slotlar icin yarim kaliyordu.
    """
    assert notify_runner._dusus_gerekcesi(
        _sonuc("winback", attempted=1, fallback=1)) == "uretim-tamamen-dustu"


def test_ayni_dokum_daily_slotunda_kirmizi_YANMAZ():
    """Esigin SLOTA bagli oldugunun bagimsiz isareti.

    Ustteki bekci tek basina, esigi her slot icin 1 yapan bir mutasyondan
    da GECER. Ayni dokumun `daily`de yesil kalmasi, farkin gercekten slot
    basina oldugunu olcuyor — `daily` kuyrugu olculmustu (10/5/1) ve orada
    tek deneme "hepsi dustu" ile "o tek profil bozuk" arasini AYIRMAZ.
    """
    assert notify_runner._dusus_gerekcesi(
        _sonuc("daily", attempted=1, fallback=1)) is None


def test_winback_olay_yokken_kirmizi_yanmaz():
    """Esik 1 olsa bile "olay yok" dusus DEGILDIR.

    Kuyrugun gunlerin yarisinda 0 oldugu olculdu (ortalama 0.79); bos
    kuyruk kirmizi yansa slot her gun yanar ve okunmaz hale gelirdi —
    yani 403'u bir ay saklayan kusurun aynisi ters yonden geri gelirdi.
    """
    assert notify_runner._dusus_gerekcesi(_sonuc("winback")) is None
    assert notify_runner._dusus_gerekcesi(
        _sonuc("winback", attempted=0)) is None


def test_winback_esigi_olculen_kuyrugun_USTUNDE_olamaz():
    """Esik, slotun gercek kuyrugundan buyukse bekci HIC dolmaz.

    Kuyruk burada YENIDEN olculuyor (gercek `winback_tier` ile), yani
    `WINBACK_TIERS` buyutulup esik guncellenmezse bu bekci yanar.
    Capa tek bir sayiya degil OLCUME bagli.
    """
    profiller = [{"son_giris": -i, "gonderilen": 0} for i in range(18)]
    gunluk = []
    for gun in range(40):
        yerel = dt.datetime(2026, 10, 1, 19, 0,
                            tzinfo=dt.timezone.utc) + dt.timedelta(days=gun)
        bugun = 0
        for p in profiller:
            fark = gun - p["son_giris"]
            profil = {"timezone": "UTC",
                      "lastSeenDaily": (yerel.date()
                                        - dt.timedelta(days=fark)).isoformat()}
            basamak, _ = ns.winback_tier(profil, yerel, p["gonderilen"])
            if basamak is not None:
                bugun += 1
                p["gonderilen"] = basamak
        gunluk.append(bugun)

    # ⚠️ 0. GUN BIRIKMIS BACKLOG'U BOSALTIR ve olcume KATILMAZ: baslangicta
    # her profilin `gonderilen`i 0, yani "sessizligi 3 gunu gecmis ama hic
    # cagrilmamis" 16 kullanici AYNI GUN kuyruga giriyor (olculdu: 16).
    # Bu gercek bir olay — slot ilk defa aciligi gun aynen yasanir — ama
    # KALICI HAL degil; esik kalici hale gore secilir. Bu satiri silip 1.
    # gunden baslamak olcumu 2'den 16'ya cikarir (ilk yazimda oyle yaptim
    # ve bekci KENDI yontem hatasiyla kirmizi yandi).
    kararli = gunluk[1:]
    en_cok = max(kararli)
    assert gunluk[0] > en_cok, \
        "backlog gunu kalici halden buyuk olmali; kurulum bozulmus"
    assert en_cok <= 2, f"kuyruk olcumu degismis: en cok {en_cok}"
    assert notify_runner._kirmizi_esigi("winback") <= en_cok, (
        "winback esigi olculen kuyrugun ustunde; bekci hic dolmaz "
        f"(esik={notify_runner._kirmizi_esigi('winback')}, kuyruk={en_cok})")


def test_uretim_saymayan_slotlar_esikten_muaf_kalir():
    """`checkin`/`streak`/`midday` `generation` sayacini HIC artirmiyor.

    Esik tablosuna eklenirlerse hicbir sey degismez ama yorum YANLIS
    gerekce tasir ("esigi dusurduk ki gorunsun"), oysa o slotlarda uretim
    kapisi tanim geregi sessiz. Bekci bu yanlis gerekceyi engelliyor.
    """
    for tur in ("checkin", "streak", "midday"):
        assert tur not in notify_runner._SLOT_KIRMIZI_ESIGI
        assert notify_runner._dusus_gerekcesi(_sonuc(tur)) is None


def test_GONDERIM_kapisi_da_slot_esigini_kullanir():
    """Esik IKI kapida da slottan okunmali — biri atlanirsa yarim kalir.

    ⚠️ Bu bekci bir KOR BEKCI onarimidir (dogrulama turu, minimal
    mutasyonla olculdu): gonderim kapisini sabit `_KIRMIZI_ESIGI`ye
    geri dusuren mutasyon 61/61 YESIL geciyordu. Ustteki butun B3
    bekcileri `generation` kapisini olcuyor; GONDERIM kapisi
    olculmuyordu.

    Neden ayni esik: `queued` ile `attempted` AYNI kuyruktan besleniyor
    (olculdu: `winback` kuyrugu kararli halde 0-2). Gonderim kapisi 3'te
    kalirsa `winback` push'u TAMAMEN olse de uc 200 doner — yani bu
    turun dersi ("zamanlanmis isler bir ay yesil yalan soyledi")
    uretim yolunda kapanip gonderim yolunda acik kalirdi.
    """
    assert notify_runner._dusus_gerekcesi(
        _sonuc("winback", queued=1, sent=0)) == "gonderim-tamamen-dustu"
    # BAGIMSIZ isaret: ayni dokum `daily`de yesil kalmali, yoksa
    # ustteki iddia "esik her slotta 1" mutasyonundan da gecerdi.
    assert notify_runner._dusus_gerekcesi(
        _sonuc("daily", queued=1, sent=0)) is None

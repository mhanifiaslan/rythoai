"""Burç yorumu gece ön-üretimi (P3) — ısıtma ucu + zamanlayıcı işi.

Ölçülen durum: önbellek mimarisi zaten doğruydu (paylaşımlı, sahipsiz, TTL
kova süresiyle hizalı) ama ÖN-ÜRETİM yoktu; her (burç, dönem, dil, kova)
dörtlüsünün ilk isteyeni RAG + Gemini (+ olası ikinci deneme) + fact_guard
turunu tam tamına bekliyordu. Günlük yorumda bu günde 24 kullanıcı eder ve
bunlar rastgele değil SABAH İLK AÇANLARdır.

Buradaki bekçilerin her biri SESSİZ bir kusuru hedefliyor — ısıtma koşup
hiçbir işe yaramasa da ne kullanıcı ne operatör bunu görür:

- Kapı: sır yoksa uç kapalı; kapı üretimden ÖNCE çalışmalı.
- Sürüm kapısı muafiyeti: muaf olmazsa eşik > 0 yazıldığı gün iş 426 yer.
- Yerel gün: UTC günü ısıtılırsa Türkiye'de dünün kovası dolar.
- Tek burcun patlaması kalan 23'ü düşürmemeli.
- Fallback ısınma SAYILMAZ: yedek metin önbelleğe yazılmıyor.
- Kalıcı katmana YAZILAMAYAN üretim de ısınma SAYILMAZ: paylaşımlı
  önbellek boş kalır, yalnız o instance'ın belleği dolar.
- Betikteki yol gerçek bir route olmalı; iş adı/yolu kayarsa 404 sessizdir.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_horoscope_warm.py -q
"""
from __future__ import annotations

import datetime as dt
import re
from pathlib import Path
from typing import get_args

import pytest
from fastapi.testclient import TestClient

from api import maintenance
from core import app_gate, config, i18n
from services import prompts, report_service

try:
    from main import app
    _APP_IMPORT_HATASI = None
except Exception as exc:  # pragma: no cover - ortama bağlı
    app = None
    _APP_IMPORT_HATASI = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_HATASI is not None,
    reason=f"FastAPI uygulaması içe aktarılamadı: {_APP_IMPORT_HATASI}",
)

YOL = "/api/v1/maintenance/horoscope-warm"
SIR = "test-zamanlayici-sirri"
_KOK = Path(__file__).resolve().parent.parent.parent


# ---------------------------------------------------------------------------
# Sahte ısıtma: gökyüzü hesabı ve LLM zinciri YOK — ölçülen şey sayaç ve kapı.
# ---------------------------------------------------------------------------

class _Kayit:
    """Isıtma çağrılarını toplar; ayrıca her çağrının sonucunu belirler."""

    def __init__(self):
        self.cagrilar: list[tuple[str, str, str, dt.date]] = []
        self.patlayan: set[tuple[str, str]] = set()
        self.yedege_dusen: set[tuple[str, str]] = set()
        #: Üretim OLDU ama kalıcı katmana yazılamadı (Firestore düştü).
        self.yazilamayan: set[tuple[str, str]] = set()
        self.hepsi_sicak = False

    def horoscope_reading(self, sign, period, sky, lang=None, today=None):
        self.cagrilar.append((sign, period, lang, today))
        if (sign, lang) in self.patlayan:
            raise RuntimeError("Gemini erişilemiyor")
        if (sign, lang) in self.yedege_dusen:
            return {"text": "yedek", "cached": False, "fallback": True,
                    "persisted": False}
        return {
            "text": "yorum", "cached": self.hepsi_sicak,
            # `persisted` GERÇEK `_cached_generate`in üretim yolunda her
            # zaman var. Sahte onu atlasaydı bekçiler sessizce kayardı:
            # her kombinasyon "yazılamadı" sayılır ve yeşil kalan
            # testler kalmazdı ama kırmızı olanlar da YANLIŞ sebeple
            # kırmızı olurdu. Anahtarın gerçekten üretildiği
            # `tests/test_onbellek_yazim_raporu.py` ile çivili.
            "persisted": (sign, lang) not in self.yazilamayan,
            "generated_for": today.isoformat() if today else None}


@pytest.fixture()
def isitma(monkeypatch):
    kayit = _Kayit()
    monkeypatch.setattr(config, "NOTIFY_SCHEDULER_SECRET", SIR)
    # Gökyüzü hesabı swisseph'e gidiyor; ısıtma sayacının ölçümü için
    # içeriği önemsiz — yalnız "bir kez hesaplanıyor" korunur.
    monkeypatch.setattr(maintenance, "get_sky_now",
                        lambda: {"retrogrades": [], "aspects": [],
                                 "moon_phase": None})
    monkeypatch.setattr(maintenance.report_service, "horoscope_reading",
                        kayit.horoscope_reading)
    return kayit


def _basliklar(etiket: str, sir: bool = True) -> dict:
    """Kota kovası Authorization özetine bağlı; her test kendi etiketini verir."""
    if sir:
        return {"Authorization": SIR}
    return {"Authorization": f"Bearer isitma-{etiket}"}


# ---------------------------------------------------------------------------
# Kapı
# ---------------------------------------------------------------------------

@uygulama_gerekir
def test_sirsiz_istek_reddedilir(isitma):
    """Sır yok/yanlış + owner değil → kapı kapalı (401 ya da 403)."""
    with TestClient(app) as client:
        yanit = client.post(YOL, headers=_basliklar("sirsiz", sir=False))
    assert yanit.status_code in (401, 403), yanit.text
    # Kapı ÜRETİMDEN ÖNCE çalışmalı: aksi halde kimliksiz bir istek 24
    # Gemini üretimi tetikleyebilirdi (faturayı yabancı yazdırır).
    assert isitma.cagrilar == []


@uygulama_gerekir
def test_basliksiz_istek_de_reddedilir(isitma):
    with TestClient(app) as client:
        yanit = client.post(YOL)
    assert yanit.status_code in (401, 403), yanit.text
    assert isitma.cagrilar == []


@uygulama_gerekir
def test_yanlis_sir_reddedilir(isitma):
    with TestClient(app) as client:
        yanit = client.post(YOL, headers={"Authorization": SIR + "x"})
    assert yanit.status_code in (401, 403), yanit.text
    assert isitma.cagrilar == []


@uygulama_gerekir
def test_sir_tanimsizken_uc_kapali(isitma, monkeypatch):
    """Fail-closed: anahtar yoksa sır kapısı hiç açılmaz."""
    monkeypatch.setattr(config, "NOTIFY_SCHEDULER_SECRET", "")
    with TestClient(app) as client:
        yanit = client.post(YOL, headers={"Authorization": ""})
    assert yanit.status_code in (401, 403), yanit.text
    assert isitma.cagrilar == []


@uygulama_gerekir
@pytest.mark.parametrize("yol", ["/api/v1/maintenance/horoscope-warm",
                                 "/api/v1/maintenance/cleanup"])
def test_ascii_olmayan_baslik_500_degil_kapi_yanitini_alir(isitma, yol):
    """ÖLÇÜLDÜ (2026-10-02): `Authorization` başlığı latin-1 çözülüyor ve
    `secrets.compare_digest` ASCII olmayan dizeyi `TypeError` ile reddediyor.

    Son baytı 0xE9 olan bir başlık KİMLİKSİZ bir istekten **500** döndürüyor
    ve her denemede sunucu günlüğüne yığın izi yazdırıyordu; gerçek kapı
    (401) maskeleniyordu. İki uç BİRLİKTE sınanır: ikisi de aynı
    `_scheduler_gecerli`den geçiyor.
    """
    with TestClient(app, raise_server_exceptions=False) as client:
        yanit = client.post(yol, headers={"Authorization": b"sir\xe9"})
    assert yanit.status_code != 500, yanit.text
    assert yanit.status_code in (401, 403), yanit.text
    assert isitma.cagrilar == []


@uygulama_gerekir
def test_cleanup_kapisi_korundu(monkeypatch):
    """`_scheduler_gecerli` bu turda `_verify_scheduler`dan AYRIŞTIRILDI ve
    `/cleanup` onu paylaşıyor; ayrışmanın hiçbir bekçisi yoktu.

    Ölçüldü: yanlış anahtar kontrolü silindiğinde takımın tamamı YEŞİL
    kalıyordu — yani sohbet arşivi temizliği kimliksiz çağrılabilir hâle
    gelse kimse görmezdi. Anahtar yok → 503 (fail-closed), yanlış → 401.
    """
    cagrildi: list[bool] = []
    monkeypatch.setattr(
        maintenance.chat_history, "purge_expired",
        lambda limit, dry_run: cagrildi.append(True) or {"deleted": 0})
    yol = "/api/v1/maintenance/cleanup"
    with TestClient(app) as client:
        monkeypatch.setattr(config, "NOTIFY_SCHEDULER_SECRET", "")
        assert client.post(yol, headers={"Authorization": SIR}
                           ).status_code == 503
        monkeypatch.setattr(config, "NOTIFY_SCHEDULER_SECRET", SIR)
        assert client.post(yol, headers={"Authorization": SIR + "x"}
                           ).status_code == 401
        assert cagrildi == []
        assert client.post(yol, headers={"Authorization": SIR}
                           ).status_code == 200
    assert cagrildi == [True]


# ---------------------------------------------------------------------------
# Isınma sayacı
# ---------------------------------------------------------------------------

@uygulama_gerekir
def test_sirla_butun_burc_dil_ikilileri_isinir(isitma):
    with TestClient(app) as client:
        yanit = client.post(YOL, headers=_basliklar("tam"))
    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()
    beklenen = len(maintenance.BURCLAR) * len(i18n.SUPPORTED)
    assert veri["toplam"] == beklenen
    assert veri["isinan"] == beklenen
    assert veri["dusen"] == 0
    assert veri["dusenler"] == []
    # Her (burç, dil) ikilisi BİR kez — iki kez çağırmak ikinci kez
    # ödenecek bir üretim demekti.
    ikililer = {(b, d) for b, _, d, _ in isitma.cagrilar}
    assert ikililer == {(b, d) for b in maintenance.BURCLAR
                        for d in i18n.SUPPORTED}
    assert len(isitma.cagrilar) == beklenen


@uygulama_gerekir
def test_bir_burc_patlasa_kalanlar_isinir(isitma):
    """Her burç AYRI try/except: biri patlayınca kalan 23 kaybedilmez."""
    isitma.patlayan = {("leo", "tr")}
    with TestClient(app) as client:
        yanit = client.post(YOL, headers=_basliklar("patlak"))
    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()
    beklenen = len(maintenance.BURCLAR) * len(i18n.SUPPORTED)
    assert veri["toplam"] == beklenen
    assert veri["isinan"] == beklenen - 1
    assert veri["dusen"] == 1
    assert veri["dusenler"] == ["leo/tr"]
    # Patlayan burçtan SONRAKİ burçlar da denenmiş olmalı.
    assert len(isitma.cagrilar) == beklenen


@uygulama_gerekir
def test_fallback_isinmis_sayilmaz(isitma):
    """Yedek metin önbelleğe YAZILMAZ; onu başarı saymak ölçülen düşüşü
    yanlış adla sunmak olurdu (`_cached_generate` yedeği cache'lemiyor)."""
    isitma.yedege_dusen = {("aries", "en")}
    with TestClient(app) as client:
        yanit = client.post(YOL, headers=_basliklar("yedek"))
    veri = yanit.json()
    assert yanit.status_code == 200, yanit.text
    assert veri["dusen"] == 1
    assert veri["dusenler"] == ["aries/en"]
    assert veri["isinan"] == len(maintenance.BURCLAR) * len(i18n.SUPPORTED) - 1


@uygulama_gerekir
def test_yazilamayan_isinmis_sayilmaz(isitma):
    """Üretim yapıldı, PAYLAŞIMLI katmana yazılamadı → ısınma DEĞİL.

    Ölçülen kusur buydu: `cache.set` kalıcı katman hatasını fail-open
    yutuyor ve eskiden hiçbir şey söylemiyordu, `_cached_generate` de
    başarı döndürüyordu. Sonuç: bu uç "isinan: 24" + HTTP 200 raporlar,
    paylaşımlı önbellek BOŞ kalır (dolan şey yalnız o instance'ın
    belleği; max-instances 3), sabah ilk açan kullanıcı yine bekler ve
    geriye yalnız 24 üretimin Gemini faturası kalır.

    `dusen`den AYRI sayıldığı da sınanıyor: Gemini'nin patlaması ile
    Firestore'un yazamaması aynı sayaca girerse operatör hangi sistemi
    onaracağını bilemez.
    """
    isitma.yazilamayan = {("leo", "tr"), ("virgo", "en")}
    with TestClient(app) as client:
        yanit = client.post(YOL, headers=_basliklar("yazilamayan"))
    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()
    beklenen = len(maintenance.BURCLAR) * len(i18n.SUPPORTED)
    assert veri["toplam"] == beklenen
    assert veri["isinan"] == beklenen - 2
    assert veri["yazilamayan"] == 2
    assert sorted(veri["yazilamayanlar"]) == ["leo/tr", "virgo/en"]
    # Gemini patlaması DEĞİL.
    assert veri["dusen"] == 0
    assert veri["dusenler"] == []


@uygulama_gerekir
def test_hicbiri_yazilamazsa_kosu_basarili_gorunmez(isitma):
    """Firestore yazımının tamamen düştüğü bir gece YEŞİL görünmemeli.

    Onarımdan önce bu koşu 200 + `isinan: 24` dönüyordu: Scheduler
    günlüğünde kusursuz bir gece, gerçekte sıfır ısınma.
    """
    isitma.yazilamayan = {(b, d) for b in maintenance.BURCLAR
                          for d in i18n.SUPPORTED}
    with TestClient(app) as client:
        yanit = client.post(YOL, headers=_basliklar("hic-yazilmayan"))
    assert yanit.status_code == 503, yanit.text
    ayrinti = yanit.json()["detail"]
    assert ayrinti["isinan"] == 0
    assert ayrinti["zaten_sicak"] == 0
    assert ayrinti["yazilamayan"] == (len(maintenance.BURCLAR)
                                     * len(i18n.SUPPORTED))


@uygulama_gerekir
def test_hepsi_dusen_kosu_basarili_gorunmez(isitma):
    """Tamamen boşa koşan bir gece Scheduler günlüğünde YEŞİL görünmemeli;
    yeniden deneme olmadığı için tek uyarı budur."""
    isitma.yedege_dusen = {(b, d) for b in maintenance.BURCLAR
                           for d in i18n.SUPPORTED}
    with TestClient(app) as client:
        yanit = client.post(YOL, headers=_basliklar("hepsi-dusen"))
    assert yanit.status_code == 503, yanit.text
    ayrinti = yanit.json()["detail"]
    assert ayrinti["isinan"] == 0
    assert ayrinti["dusen"] == len(maintenance.BURCLAR) * len(i18n.SUPPORTED)


@uygulama_gerekir
def test_zaten_sicak_kova_ayri_sayilir(isitma):
    """Haftalık/aylık işler her gece koşuyor; isabetli gece 'ısındı' DEMEZ —
    operatör 24 üretim olduğunu sanmasın."""
    isitma.hepsi_sicak = True
    with TestClient(app) as client:
        yanit = client.post(YOL + "?period=weekly",
                            headers=_basliklar("sicak"))
    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()
    assert veri["isinan"] == 0
    assert veri["zaten_sicak"] == len(maintenance.BURCLAR) * len(i18n.SUPPORTED)
    assert veri["period"] == "weekly"
    assert {p for _, p, _, _ in isitma.cagrilar} == {"weekly"}


@uygulama_gerekir
def test_gokyuzu_hesaplanamazsa_kosu_basarisiz(isitma, monkeypatch):
    def patla():
        raise RuntimeError("swisseph yok")

    monkeypatch.setattr(maintenance, "get_sky_now", patla)
    with TestClient(app) as client:
        yanit = client.post(YOL, headers=_basliklar("gokyuzu"))
    assert yanit.status_code == 503
    assert isitma.cagrilar == []


@uygulama_gerekir
def test_gecersiz_donem_reddedilir(isitma):
    with TestClient(app) as client:
        yanit = client.post(YOL + "?period=yillik",
                            headers=_basliklar("yillik"))
    assert yanit.status_code == 422
    assert isitma.cagrilar == []


# ---------------------------------------------------------------------------
# Yerel gün kovası — ısıtmanın İŞE YARAMASININ koşulu
# ---------------------------------------------------------------------------

@uygulama_gerekir
def test_ofset_yerel_gunu_isitir(isitma, monkeypatch):
    """Türkiye UTC+3: yerel gün 21:00 UTC'de döner.

    21:15 UTC'de `offset_minutes=180` olmadan sunucu kendi UTC gününü
    (DÜNÜ) ısıtır; iş koşar, kullanıcı sabah yine bekler ve hiçbir yerde
    hata görünmez. Ölçülen şey tam olarak bu.
    """
    monkeypatch.setattr(maintenance, "_simdi_utc",
                        lambda: dt.datetime(2026, 10, 2, 21, 15,
                                            tzinfo=dt.timezone.utc))
    with TestClient(app) as client:
        ofsetli = client.post(YOL + "?offset_minutes=180",
                              headers=_basliklar("ofset"))
        ofsetsiz = client.post(YOL, headers=_basliklar("ofset"))

    assert ofsetli.json()["local_date"] == "2026-10-03"
    assert {g for _, _, _, g in isitma.cagrilar[:len(maintenance.BURCLAR)]} \
        == {dt.date(2026, 10, 3)}
    # Varsayılan saf UTC: tek bir ülke sunucuya gömülü DEĞİL.
    assert ofsetsiz.json()["local_date"] == "2026-10-02"


@uygulama_gerekir
def test_ofset_gercek_saat_dilimi_araliginda_sinirli(isitma):
    """Dünyadaki UTC farkları -12:00 ile +14:00 arasında; dışı yazım hatasıdır."""
    with TestClient(app) as client:
        buyuk = client.post(YOL + "?offset_minutes=900",
                            headers=_basliklar("buyuk"))
        kucuk = client.post(YOL + "?offset_minutes=-900",
                            headers=_basliklar("kucuk"))
    assert buyuk.status_code == 422
    assert kucuk.status_code == 422


# ---------------------------------------------------------------------------
# Süre bütçesi — Cloud Run'ın 300s duvarı
# ---------------------------------------------------------------------------

def test_varsayilan_butce_cloud_run_zaman_asiminin_altinda():
    """Duvar Scheduler'ın 900s attempt-deadline'ı DEĞİL: Cloud Run servisi
    `--timeout 300` ile dağıtılıyor ve istek 300. saniyede ÖLDÜRÜLÜR.

    Bütçe o değere eşit ya da üstünde olursa döngü kendini hiç kesmez;
    istek ortada kesilir, log satırı HİÇ basılmaz, 503 HİÇ dönmez ve
    Scheduler günlüğünde gövdesiz bir zaman aşımı kalır.
    """
    betik = (_KOK / "infra" / "deploy-backend.ps1").read_text(
        encoding="utf-8")
    eslesme = re.search(r'"--timeout",\s*"(\d+)"', betik)
    assert eslesme, "deploy betiğinde --timeout okunamadı"
    duvar = int(eslesme.group(1))
    assert maintenance._VARSAYILAN_BUTCE_SN < duvar, (
        f"butce {maintenance._VARSAYILAN_BUTCE_SN}s, duvar {duvar}s")


@uygulama_gerekir
def test_butce_dolunca_kalanlar_atlanan_sayilir(isitma, monkeypatch):
    """Bütçe dolduğunda kalan kombinasyonlar 'ısındı' DEĞİL 'atlandı'.

    Sayılmasalardı `toplam` küçülür ve yarım ısınmış bir gece
    "24'te 24" gibi görünürdü — ölçülen düşüşü yanlış adla sunmak.
    """
    # Saat çağrı SAYISINA değil ÜRETİM sayısına bağlanır: aynı süreçte
    # `time.monotonic` middleware'den de çağrılıyor (kota penceresi), sayıya
    # bağlı bir sahte saat testi sessizce yanlış yere kaydırır.
    saat = {"t": 0.0}
    gercek = isitma.horoscope_reading

    def yavas_uretim(*args, **kwargs):
        saat["t"] += 100.0  # her üretim 100 sn sürüyor varsayımı
        return gercek(*args, **kwargs)

    monkeypatch.setattr(maintenance.time, "monotonic", lambda: saat["t"])
    monkeypatch.setattr(maintenance.report_service, "horoscope_reading",
                        yavas_uretim)
    with TestClient(app) as client:
        yanit = client.post(YOL, headers=_basliklar("butce"))
    # Yarım kalan koşu YEŞİL görünmez: gövde Scheduler günlüğüne düşmez,
    # yalnız durum kodu düşer.
    assert yanit.status_code == 503, yanit.text
    veri = yanit.json()["detail"]
    beklenen = len(maintenance.BURCLAR) * len(i18n.SUPPORTED)
    assert veri["toplam"] == beklenen
    assert veri["atlanan"] == beklenen - veri["isinan"]
    assert veri["atlanan"] > 0
    assert len(veri["atlananlar"]) == veri["atlanan"]
    # Atlanan kombinasyon ÜRETİLMEMİŞ olmalı: aksi halde bütçe yalnız
    # raporda var, faturada yok.
    assert len(isitma.cagrilar) == veri["isinan"]
    # Kesintinin kurbanı son dil olur (tr önce ısınır).
    assert all(a.endswith("/" + i18n.SUPPORTED[-1])
               for a in veri["atlananlar"][-1:])


@uygulama_gerekir
def test_butce_sinirlari_dogrulanir(isitma):
    with TestClient(app) as client:
        assert client.post(YOL + "?budget_seconds=0",
                           headers=_basliklar("b0")).status_code == 422
        assert client.post(YOL + "?budget_seconds=99999",
                           headers=_basliklar("b9")).status_code == 422
    assert isitma.cagrilar == []


# ---------------------------------------------------------------------------
# Sürüm kapısı muafiyeti
# ---------------------------------------------------------------------------

def test_isitma_yolu_surum_kapisindan_muaf():
    """Muaf olmazsa eşik > 0 yazıldığı gün iş 426 yer ve ısıtma SESSİZCE
    ölür — tam olarak `/partners/` önekinde yaşanan kusur."""
    assert YOL.startswith(app_gate.EXEMPT_PREFIXES)


@uygulama_gerekir
def test_esik_yuksekken_isitma_kilitlenmez(isitma, monkeypatch):
    """Uçtan uca: zamanlayıcı `X-App-Build` göndermiyor, eşik yüksek."""
    monkeypatch.setattr(config, "MIN_APP_BUILD", 9999)
    app_gate.reset_memo()
    try:
        with TestClient(app) as client:
            yanit = client.post(YOL, headers=_basliklar("esik"))
            kontrol = client.get("/api/v1/reports/horoscope/leo",
                                 headers=_basliklar("esik-kontrol", sir=False))
    finally:
        app_gate.reset_memo()
    assert yanit.status_code == 200, yanit.text
    # Pozitif kontrol: aynı koşulda muaf OLMAYAN yol kilitli.
    assert kontrol.status_code == 426


# ---------------------------------------------------------------------------
# Tek kaynak: burç ve dönem kümeleri
# ---------------------------------------------------------------------------

def test_isitilan_burclar_ucun_kabul_ettigi_kumeyle_ayni():
    """Isıtılmayan burcun önbelleği soğuk kalır ve ilk kullanıcısı tam
    zinciri yine bekler; listede olmaması hiçbir yerde hata üretmez."""
    from api.reports import SignName

    assert maintenance.BURCLAR == get_args(SignName)
    assert len(maintenance.BURCLAR) == 12


@pytest.mark.parametrize("dil", i18n.SUPPORTED)
def test_isitilan_her_burcun_her_dilde_adi_var(dil):
    """Dil tablosunda adı olmayan burç `prompts` içinde anahtarına düşer ve
    kullanıcıya 'leo' yazardı — ısıtma o metni ÖNBELLEĞE yazar."""
    assert set(maintenance.BURCLAR) <= set(prompts.get(dil).SIGN_NAMES)


def test_donemler_ttl_tablosuyla_ayni():
    """FastAPI statik Literal istiyor, yani dönem listesi iki yerde duruyor.
    TTL tablosunda olmayan bir dönem 24 saatlik varsayılana düşer: aylık
    yorum her gün yeniden üretilirdi (30 kat maliyet)."""
    assert set(get_args(maintenance.Donem)) == set(report_service._HOROSCOPE_TTL)


# ---------------------------------------------------------------------------
# Zamanlayıcı işi (infra/create-scheduler.ps1)
# ---------------------------------------------------------------------------

def _betik() -> str:
    return (_KOK / "infra" / "create-scheduler.ps1").read_text(
        encoding="utf-8")


def _kod() -> str:
    """Yorumsuz betik: gerekçe metni iş tanımı sanılmasın.

    Bu depoda iki kez yaşandı: bir şeyin YOKLUĞUNU arayan bekçi, onu
    ANLATAN yorumu gördü ve yanlış karar verdi.
    """
    return "\n".join(s for s in _betik().splitlines()
                     if not s.lstrip().startswith("#"))


def _isler() -> dict[str, tuple[str, str]]:
    """ad -> (cron, uri); yalnız ısıtma işleri."""
    bulunan = {}
    for ad, uri, cron in re.findall(
            r'ad\s*=\s*"(rytho-horoscope-warm[^"]*)"[^\n]*?'
            r'uri\s*=\s*"([^"]+)"[^\n]*?cron\s*=\s*"([^"]+)"', _kod()):
        bulunan[ad] = (cron, uri)
    return bulunan


def _istemci_donemleri() -> set[str]:
    """İstemcinin GERÇEKTEN isteyebildiği burç kovaları.

    `daily` her zaman içeride: uç `period` almazsa onu varsayıyor, yani düz
    çağrı o kovayı doldurur. Diğerleri ancak istemci kaynağında `period`
    gönderen bir satır VARSA sayılır.

    Yorumlar atılıyor — bu depoda iki kez bir şeyin YOKLUĞUNU arayan bekçi
    onu ANLATAN yoruma takıldı.
    """
    govde = []
    for yol in (_KOK / "apps" / "mobile" / "lib").rglob("*.dart"):
        for satir in yol.read_text(encoding="utf-8",
                                   errors="replace").splitlines():
            kirpik = satir.strip()
            if kirpik.startswith("//"):
                continue
            govde.append(kirpik)
    metin = "\n".join(govde)
    bulunan = {"daily"}
    for donem in get_args(maintenance.Donem):
        if f"period={donem}" in metin or f"'period': '{donem}'" in metin:
            bulunan.add(donem)
    return bulunan


def test_isitilan_her_donem_istemciden_ISTENEBILIR():
    """Isıtma yalnız OKUNABİLECEK kovalar için kurulur.

    Bir tur boyunca haftalık/aylık için de iş kuruldu ve ikisi de (adlarına
    rağmen) `* * *` ile HER GECE koşuyordu: 2 × 12 burç × 2 dil = 48 LLM
    üretimi (RAG embedding + Gemini + fact_guard), ve üretilen önbelleği
    hiçbir istemci okuyamıyordu — `period` gönderen tek satır yok. Ölçülebilir
    fatura, sıfır karşılık.

    Bekçi iki yöne de çalışır: istenebilir bir kova ısıtılmıyorsa da kırmızı
    olur, yani haftalık/aylık ürün yüzeyine açıldığı gün bu test işi
    eklemeyi HATIRLATIR.
    """
    istenebilir = _istemci_donemleri()
    uriler = " ".join(uri for _, uri in _isler().values())
    for donem in get_args(maintenance.Donem):
        isitiliyor = f"period={donem}" in uriler
        if donem in istenebilir:
            assert isitiliyor, f"istemci istiyor ama ısıtma işi yok: {donem}"
        else:
            assert not isitiliyor, (
                f"ısıtma işi var ama `{donem}` kovasını hiçbir istemci "
                "isteyemiyor — her gece bedava LLM faturası")


def test_isitma_yerel_gun_donduktan_sonra_kosar():
    """Kova YEREL güne bağlı. Türkiye UTC+3 → yerel gün 21:00 UTC'de döner;
    ısıtma ondan ÖNCE koşarsa dünün kovasını doldurur."""
    assert _isler(), "ısıtma işi hiç kurulmamış"
    for ad, (cron, _) in _isler().items():
        dakika, saat = cron.split()[:2]
        assert int(saat) == 21, f"{ad}: yerel gün dönüşünden sonra koşmalı"
        assert int(dakika) >= 5, f"{ad}: 21:00'ı geçmiş olmalı"


def test_isitma_isleri_bildirim_slotlarina_binmez():
    """Bildirim işleri her saatin :05/:08/:10/:12'sinde koşuyor; ısıtma 24
    üretim yapıyor ve aynı dakikada başlamaları ikisini de yavaşlatır."""
    for ad, (cron, _) in _isler().items():
        assert int(cron.split()[0]) not in (5, 8, 10, 12), ad


def test_isitma_isi_yerel_gun_ofseti_geciyor():
    """Ofset olmadan iş koşar ama İŞE YARAMAZ: UTC günü (dün) ısıtılır."""
    for ad, (_, uri) in _isler().items():
        assert "offset_minutes=180" in uri, f"{ad}: yerel gün ofseti yok"


def test_isitma_isleri_ayri_ayri_kurulur():
    """Dönemler tek işte birleştirilmez: kova başına ayrı iş.

    Birleştirilirse yerel ayın 1'i ile Pazartesi'nin çakıştığı gece üç kova
    tek koşuya sığar ve duvara ORTADA çarpar (yeniden deneme yok).

    ⚠️ Duvar bir tur boyunca "Scheduler'ın 900s attempt-deadline'ı" diye
    yazılmıştı; ÖLÇÜLEN duvar Cloud Run'ın istek zaman aşımıdır —
    `infra/deploy-backend.ps1` servisi `--timeout 300` ile dağıtıyor, yani
    istek 300. saniyede ölür ve kalan 600 saniye hiç kullanılmaz. Uç artık
    kendi bütçesini tutuyor (240s < 300s) ve yetişmeyenleri `atlanan` sayıp
    adlarıyla warning'e yazıyor.

    Sayı `Donem`e değil ISITILAN kova sayısına bağlı: ısıtılamayacak
    (istemciden istenemeyen) bir kova için iş olmaması DOĞRU hâl.
    """
    assert len(_isler()) == len(_istemci_donemleri())


@uygulama_gerekir
def test_betikteki_yol_gercek_bir_route():
    """İş adı/yolu kayarsa Cloud Scheduler her gece 404 alır ve bu yalnız
    Scheduler günlüğünde durur — uygulamada hiçbir belirti olmaz."""
    # Yollar OpenAPI şemasından okunur, `app.routes`tan DEĞİL: bu FastAPI
    # sürümünde `include_router` yolları düzleştirmiyor, sarmalayıcı
    # (`_IncludedRouter`) altında önekiyle duruyor. Şema ise son kayıtlı
    # yolu önekiyle birlikte veriyor.
    yollar = set(app.openapi()["paths"])
    for ad, (_, uri) in _isler().items():
        assert uri.split("?")[0] in yollar, f"{ad}: yol yok ({uri})"


def test_isitma_isi_zamanlayici_ile_utc_kurulur():
    """Saat seçiminin tüm gerekçesi UTC gün penceresi; iş yerel saatle
    kurulsa pencere sessizce kayardı.

    `_betik()` DEĞİL `_kod()`: betiğin yorumları artık saat dilimi
    tercihini ANLATIYOR ve bayrağı metin olarak içeriyor. Ham metinde
    arayan bir bekçi, bayrak komuttan düşse bile yorumla yeşil kalırdı —
    bu depodaki "bekçi kendi yorumunu gördü" tuzağının ters yönü.
    """
    assert '--time-zone "UTC"' in _kod()

"""Faz 3 testleri: dil çözümleme, dile göre persona/prompt ve önbellek ayrımı.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_i18n.py -q
"""
import datetime as dt

import pytest
from fastapi.testclient import TestClient

from core import cache, config, i18n
from services import prompt_composer, prompts, report_service

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

SAHTE_GOKYUZU = {
    "moon_phase": {"name": "Full Moon", "emoji": "🌕", "illumination": 98},
    "retrogrades": ["Mercury"],
    "aspects": [{"p1": "Sun", "p2": "Saturn", "aspect": "square"}],
}


@pytest.fixture(autouse=True)
def temiz_onbellek(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    yield
    cache._memory.clear()


# --------------------------------------------------------------------------
# Accept-Language çözümleme
# --------------------------------------------------------------------------

@pytest.mark.parametrize("baslik,beklenen", [
    (None, "tr"),
    ("", "tr"),
    ("tr", "tr"),
    ("en", "en"),
    ("en-US", "en"),            # bölgesel varyant ana dile katlanır
    ("en-GB,en;q=0.9", "en"),
    ("de", "tr"),               # desteklenmeyen dil varsayılana düşer
    ("de,en;q=0.8", "en"),      # ilk desteklenen dil seçilir
    ("tr;q=0.3,en;q=0.9", "en"),  # ağırlık sırası dikkate alınır
    ("bozuk;q=abc", "tr"),      # hatalı q sessizce yok sayılır
])
def test_dil_cozumleme(baslik, beklenen):
    assert i18n.resolve_language(baslik) == beklenen


def test_desteklenen_diller_ve_varsayilan_tutarli():
    assert i18n.DEFAULT in i18n.SUPPORTED
    # Her desteklenen dilin prompt modülü olmalı
    for kod in i18n.SUPPORTED:
        modul = prompts.get(kod)
        assert modul.SYSTEM_INSTRUCTION
        assert modul.CHAT_SYSTEM_INSTRUCTION
        assert len(modul.SIGN_NAMES) == 12


# --------------------------------------------------------------------------
# Persona ve şablonlar dile göre değişir
# --------------------------------------------------------------------------

def test_personalar_ayri_metinler():
    tr = prompts.get("tr")
    en = prompts.get("en")
    assert tr.SYSTEM_INSTRUCTION != en.SYSTEM_INSTRUCTION
    # İngilizce persona İngilizce olmalı, çeviri artığı taşımamalı
    assert "NO FLATTERY" in en.SYSTEM_INSTRUCTION
    assert "POHPOHLAMA" not in en.SYSTEM_INSTRUCTION
    assert "POHPOHLAMA YOK" in tr.SYSTEM_INSTRUCTION


def test_her_iki_dilde_ayni_yasaklar_var():
    """Dürüstlük ve yasak alan kuralları dile göre gevşemez."""
    tr, en = prompts.get("tr"), prompts.get("en")
    for anahtar in ("hamile", "ölüm", "hukuki"):
        assert anahtar in tr.SYSTEM_INSTRUCTION.lower()
    for anahtar in ("pregnancy", "death", "legal advice"):
        assert anahtar in en.SYSTEM_INSTRUCTION.lower()


def test_burc_adlari_dile_gore():
    assert prompts.sign_name("tr", "leo") == "Aslan"
    assert prompts.sign_name("en", "leo") == "Leo"
    assert prompts.sign_name("de", "leo") == "Aslan"  # varsayılana düşer


def test_taninmayan_dil_varsayilan_modul():
    assert prompts.get("de") is prompts.get("tr")
    assert prompts.get(None) is prompts.get("tr")


# --------------------------------------------------------------------------
# Önbellek dile göre ayrışır — en kritik davranış
# --------------------------------------------------------------------------

def test_burc_onbellek_anahtari_dili_icerir():
    """Dil anahtara girmezse İngilizce kullanıcı Türkçe yorumu görür."""
    tr = report_service.horoscope_cache_key("leo", "daily", "2026-07-29", "tr")
    en = report_service.horoscope_cache_key("leo", "daily", "2026-07-29", "en")
    assert tr != en


def test_turkce_onbellek_ingilizce_istegi_karsilamaz(monkeypatch):
    """Türkçe üretilmiş yorum, İngilizce isteğe servis edilmemeli."""
    bucket = report_service._horoscope_bucket("daily", dt.date.today())
    cache.set(report_service.horoscope_cache_key("leo", "daily", bucket, "tr"),
              "Türkçe yorum.", ttl_seconds=600)

    uretilen: list[str] = []

    def sahte_generate(prompt, **k):
        uretilen.append(k.get("lang") or "?")
        return "English reading."

    monkeypatch.setattr(report_service.gemini_service, "generate", sahte_generate)
    monkeypatch.setattr(report_service, "retrieve_context", lambda *a, **k: "")

    sonuc = report_service.horoscope_reading("leo", "daily", SAHTE_GOKYUZU,
                                             lang="en")

    assert sonuc["cached"] is False, "Türkçe önbellek İngilizceye servis edildi"
    assert sonuc["text"] == "English reading."
    assert uretilen == ["en"], "üretim İngilizce persona ile yapılmalı"


def test_gunluk_okuma_onbellegi_dile_gore_ayrisir(monkeypatch):
    monkeypatch.setattr(report_service, "retrieve_context", lambda *a, **k: "")
    monkeypatch.setattr(report_service.memory_service, "memory_context",
                        lambda uid, max_chars=600, **k: "")
    monkeypatch.setattr(report_service.gemini_service, "generate",
                        lambda prompt, **k: f"reading-{k.get('lang')}")

    natal = {"sun_sign": "Leo", "moon_sign": "Aries", "ascendant": "Libra"}
    tr = report_service.daily_reading("u1", natal, SAHTE_GOKYUZU, lang="tr")
    en = report_service.daily_reading("u1", natal, SAHTE_GOKYUZU, lang="en")

    assert tr["text"] == "reading-tr"
    assert en["text"] == "reading-en", "aynı kullanıcı için diller karıştı"


# --------------------------------------------------------------------------
# Prompt şablonları dile göre doldurulur
# --------------------------------------------------------------------------

def test_ingilizce_burc_promptu_ingilizce(monkeypatch):
    yakalanan: dict[str, str] = {}

    def sahte_generate(prompt, **k):
        yakalanan["prompt"] = prompt
        return "ok"

    monkeypatch.setattr(report_service.gemini_service, "generate", sahte_generate)
    monkeypatch.setattr(report_service, "retrieve_context", lambda *a, **k: "")

    report_service.horoscope_reading("leo", "weekly", SAHTE_GOKYUZU, lang="en")

    prompt = yakalanan["prompt"]
    assert "TASK:" in prompt
    assert "Leo" in prompt
    assert "GÖREV" not in prompt, "İngilizce prompt'a Türkçe sızdı"


@uygulama_gerekir
def test_sohbet_gokyuzu_ozeti_dile_gore(monkeypatch):
    """Gökyüzü bloğu prompt'a giriyor; Türkçe etiketler İngilizce prompt'un
    içinde kalırsa model iki dil arasında sallanır."""
    from api import chat as chat_api

    monkeypatch.setattr(chat_api, "get_sky_now", lambda: SAHTE_GOKYUZU)

    tr = chat_api._sky_summary("tr")
    en = chat_api._sky_summary("en")

    assert "Ay evresi" in tr and "Retro gezegenler" in tr
    assert "Moon phase" in en and "Retrograde planets" in en
    assert "Ay evresi" not in en, "İngilizce gökyüzü özetine Türkçe sızdı"


def test_sohbet_gokyuzu_bos_retro_etiketi_dile_gore(monkeypatch):
    from api import chat as chat_api

    monkeypatch.setattr(chat_api, "get_sky_now",
                        lambda: {**SAHTE_GOKYUZU, "retrogrades": []})

    assert "yok" in chat_api._sky_summary("tr")
    assert "none" in chat_api._sky_summary("en")


def test_fisilti_etiketleri_dile_gore():
    tr = prompt_composer.compose_chat_message(
        "selam", [], chart="- Güneş: Aslan", lang="tr")
    en = prompt_composer.compose_chat_message(
        "hello", [], chart="- Sun: Leo", lang="en")

    assert "KULLANICININ HARİTASI" in tr
    assert "THE READER'S CHART" in en
    assert "KULLANICININ MESAJI: selam" in tr
    assert "THE READER'S MESSAGE: hello" in en


# --------------------------------------------------------------------------
# Uç davranışı
# --------------------------------------------------------------------------

@uygulama_gerekir
def test_burc_ucu_dili_yansitir(monkeypatch):
    monkeypatch.setattr(report_service.gemini_service, "generate",
                        lambda prompt, **k: f"reading in {k.get('lang')}")
    monkeypatch.setattr(report_service, "retrieve_context", lambda *a, **k: "")

    with TestClient(app) as client:
        response = client.get(
            "/api/v1/reports/horoscope/leo",
            headers={"Authorization": "Bearer test-en",
                     "Accept-Language": "en-US,en;q=0.9"},
        )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["lang"] == "en"
    assert data["sign_name"] == "Leo"
    assert data["reading"] == "reading in en"


@uygulama_gerekir
def test_baslik_yoksa_turkce(monkeypatch):
    monkeypatch.setattr(report_service.gemini_service, "generate",
                        lambda prompt, **k: f"yorum {k.get('lang')}")
    monkeypatch.setattr(report_service, "retrieve_context", lambda *a, **k: "")

    with TestClient(app) as client:
        response = client.get("/api/v1/reports/horoscope/virgo",
                              headers={"Authorization": "Bearer test-tr"})

    data = response.json()["data"]
    assert data["lang"] == "tr"
    assert data["sign_name"] == "Başak"


# --------------------------------------------------------------------------
# Tüm rapor türleri dile göre üretilir
# --------------------------------------------------------------------------

def test_tum_sablonlar_iki_dilde_var():
    """Bir şablon yalnızca bir dilde tanımlıysa o dilde AttributeError alırız."""
    zorunlu = [
        "SYSTEM_INSTRUCTION", "CHAT_SYSTEM_INSTRUCTION",
        "HOROSCOPE", "HOROSCOPE_FALLBACK", "DAILY", "DAILY_FALLBACK",
        "DYAD", "DYAD_FALLBACK", "NATAL", "NATAL_FALLBACK",
        "BAZI", "BAZI_FALLBACK", "ICHING", "ICHING_TRANSFORMED",
        "SYNASTRY", "SYNASTRY_FALLBACK", "MEMORY_BLOCK",
        "WHISPER_RAG", "WHISPER_MEMORY", "WHISPER_CHART", "WHISPER_SKY",
        "FACT_GUARD_RETRY",
        # S1 persona bekçisi (2026-10-10): fısıltı, düzeltme ve sabit cümle
        # çiftleri — biri tek dilde kalırsa o dilde AttributeError.
        "PERSONA_WHISPER_TASK", "PERSONA_WHISPER_BIRTH",
        "PERSONA_RETRY_TASK", "PERSONA_RETRY_THIRD_PARTY",
        "PERSONA_FALLBACK_TASK", "PERSONA_FALLBACK_THIRD_PARTY",
        "SKY_MOON", "SKY_RETROS", "SKY_ASPECTS",
        "USER_MESSAGE_LABEL", "NONE_LABEL", "NO_ASPECTS",
        "SIGN_NAMES", "PERIOD_NAMES", "PERIOD_LENGTHS",
    ]
    for kod in i18n.SUPPORTED:
        modul = prompts.get(kod)
        for ad in zorunlu:
            assert hasattr(modul, ad), f"{kod} dilinde {ad} eksik"


def test_sinastri_promptuna_uyum_skoru_girmez(monkeypatch):
    """Skor hesaplanıyor ama prompt'a girmemeli: ilişkiyi tek sayıya indirgemek
    ikili dinamikte de yasak, sinastride de olmamalı."""
    yakalanan: dict[str, str] = {}
    monkeypatch.setattr(report_service.gemini_service, "generate",
                        lambda prompt, **k: yakalanan.update(p=prompt) or "ok")
    monkeypatch.setattr(report_service, "retrieve_context", lambda *a, **k: "")

    sinastri = {
        "person1": {"name": "Ada", "sun": {"sign_tr": "Leo"},
                    "moon": {"sign_tr": "Aries"}},
        "person2": {"name": "Deniz", "sun": {"sign_tr": "Libra"},
                    "moon": {"sign_tr": "Pisces"}},
        "relationship_score": {"score": 74, "description": "high"},
        "aspects": [],
    }
    report_service.synastry_report("u", sinastri, lang="en")

    assert "74" not in yakalanan["p"]
    assert "compatibility score" in yakalanan["p"].lower()


def test_natal_ve_bazi_onbellegi_dile_gore_ayrisir(monkeypatch):
    uretilen: list[str] = []
    monkeypatch.setattr(report_service.gemini_service, "generate",
                        lambda prompt, **k: uretilen.append(k.get("lang")) or "x")
    monkeypatch.setattr(report_service, "retrieve_context", lambda *a, **k: "")

    natal = {"sun_sign": "Leo", "moon_sign": "Aries", "ascendant": "Libra",
             "points": [], "aspects": []}
    report_service.natal_report("u", natal, lang="tr")
    report_service.natal_report("u", natal, lang="en")

    # İki ayrı üretim olmalı; tek anahtar olsaydı ikincisi önbellekten gelirdi
    assert uretilen == ["tr", "en"]


def test_natal_onbellek_ozeti_gunes_yukselen_yetmez():
    """Saat düzeltilip Güneş+Yükselen aynı kalsa eski rapor servis edilmesin."""
    a = {
        "sun_sign": "Leo", "ascendant": "Libra", "hour_known": True,
        "points": [
            {"name": "Sun", "abs_position": 120.0, "house_no": 10},
            {"name": "Moon", "abs_position": 40.0, "house_no": 7},
        ],
        "asc": {"sign": "Libra", "position": 12.0},
    }
    b = {
        **a,
        "points": [
            {"name": "Sun", "abs_position": 120.0, "house_no": 10},
            {"name": "Moon", "abs_position": 55.0, "house_no": 8},
        ],
    }
    assert report_service._natal_cache_digest(a) != (
        report_service._natal_cache_digest(b))
    a_saat = {**a, "hour_known": False, "asc": None}
    assert report_service._natal_cache_digest(a) != (
        report_service._natal_cache_digest(a_saat))


def test_uydurma_isaretlenir_ama_UCRETLENDIRMEYI_etkilemez(monkeypatch):
    """Bekçinin şüphesi önbellek ömrünü KISALTMAZ — bilinçli karar.

    İlk sürüm şüpheli metni hiç önbelleğe yazmıyordu. Ölçüldü: bekçi
    iddiaları metinden yakınlıkla çıkardığı için DOĞRU natal raporları da
    her koşuda işaret alıyordu (üç ayrı üretimde 2-3 işaret, küme her
    seferinde değişti). Sonuç: kullanıcı 5 jeton ödüyor, rapor önbelleğe
    girmiyor, Atlas'ı her açışında yeniden 5 jeton ödüyordu — üstelik
    raporda gerçek bir hata olmadan.

    Bekçinin faydası YENİDEN ÜRETİM (hata modele iade edilip düzeltilir).
    İşaret yanıtta ve logda kalır; ücretlendirmeye karışmaz.
    """
    from core import cache

    monkeypatch.setattr(
        report_service.gemini_service, "generate",
        lambda prompt, **k: "Satürn senin İkizler burcunda.")
    anahtar = "natal-fg-ungrounded"
    sonuc = report_service._cached_generate(
        anahtar, "Satürn: Oğlak (10. ev)", "fallback", lang="tr")
    assert sonuc.get("ungrounded") is True, "işaret yanıtta kalmalı"
    # Kullanıcı ikinci kez ücretlendirilmesin diye metin ÖNBELLEKTE.
    assert cache.get(anahtar) is not None


# --------------------------------------------------------------------------
# Ay evresi adı
#
# Evre adı sky_service içinde sabit Türkçe metindi ("Dolunay") ve gökyüzü
# paylaşımlı önbellekten servis edildiği için İngilizce kullanıcı da onu
# görüyordu. Hesap dilden bağımsızdır; ad isteğin dilinde çözülür.
# --------------------------------------------------------------------------

def test_ay_evresi_hesabi_dil_tasimaz():
    """sky_service metin degil ANAHTAR dondurmeli."""
    from services import sky_service

    for _, anahtar, _ in sky_service._MOON_PHASES:
        assert anahtar.islower() and " " not in anahtar
    anahtarlar = {a for _, a, _ in sky_service._MOON_PHASES}
    for kod in i18n.SUPPORTED:
        tablo = prompts.get(kod).MOON_PHASES
        eksik = anahtarlar - set(tablo)
        assert not eksik, f"{kod} dilinde eksik ay evresi: {eksik}"


def test_ay_evresi_adi_dile_gore():
    assert prompts.moon_phase_name("tr", "full_moon") == "Dolunay"
    assert prompts.moon_phase_name("en", "full_moon") == "Full Moon"
    assert prompts.moon_phase_name("de", "full_moon") == "Dolunay"


def test_ay_evresi_yerellestirme_anahtarsiz_veriyi_bozmaz():
    """Eski onbellek kaydinda `key` yok; elimizdeki ad korunmali."""
    eski = {"name": "Dolunay", "emoji": "🌕", "illumination": 98}
    assert prompts.localize_moon_phase("en", eski)["name"] == "Dolunay"
    assert prompts.localize_moon_phase("en", None) == {}


def test_ay_evresi_adlari_iki_dilde_farkli():
    tr = prompts.get("tr").MOON_PHASES
    en = prompts.get("en").MOON_PHASES
    for anahtar in tr:
        assert tr[anahtar] != en[anahtar], f"{anahtar} cevrilmemis"


@uygulama_gerekir
def test_gokyuzu_ucu_ay_evresini_yerellestirir(monkeypatch):
    from api import sky as sky_api

    monkeypatch.setattr(sky_api, "get_sky_now", lambda: {
        "moon_phase": {"key": "full_moon", "emoji": "🌕", "illumination": 98},
        "retrogrades": [], "aspects": [], "planets": [],
    })

    with TestClient(app) as client:
        tr = client.get("/api/v1/sky/now",
                        headers={"Authorization": "Bearer t-ay-tr"})
        en = client.get("/api/v1/sky/now",
                        headers={"Authorization": "Bearer t-ay-en",
                                 "Accept-Language": "en"})

    assert tr.json()["data"]["moon_phase"]["name"] == "Dolunay"
    assert en.json()["data"]["moon_phase"]["name"] == "Full Moon"


def test_gokyuzu_hesabi_ad_degil_anahtar_tasir():
    """Retro listesi ve acilar da dilden bagimsiz olmali.

    Gokyuzu paylasimli onbellekten servis ediliyor: onbellegi ilk dolduran
    dilin adlari herkese gidiyordu ve Ingilizce kullanici "Saturn retro" degil
    "Saturn retro" yerine "Satürn retro" goruyordu.
    """
    from services import sky_service

    gezegen_anahtarlari = {ad for ad, _, _, _ in sky_service._PLANETS}
    aci_anahtarlari = {a for _, a, _ in sky_service._MAJOR_ASPECTS}
    for kod in i18n.SUPPORTED:
        modul = prompts.get(kod)
        assert not gezegen_anahtarlari - set(modul.PLANET_NAMES)
        assert not aci_anahtarlari - set(modul.ASPECT_NAMES)


def test_gokyuzu_yerellestirme():
    ham = {
        "moon_phase": {"key": "full_moon", "emoji": "🌕", "illumination": 93},
        "retrogrades": ["Saturn", "Neptune", "Pluto"],
        "aspects": [{"p1": "Neptune", "p2": "Pluto", "aspect": "sextile",
                     "orb": 1.2}],
        "planets": [{"name": "Sun"}],
    }

    tr = prompts.localize_sky("tr", ham)
    en = prompts.localize_sky("en", ham)

    assert tr["retrogrades"] == ["Satürn", "Neptün", "Plüton"]
    assert en["retrogrades"] == ["Saturn", "Neptune", "Pluto"]
    # HA1 (canlı hata onarımı): açı anahtarları KARARLI kalır, çeviri
    # *_local alanlarına EKLENİR. Eski davranış p1/p2/aspect'in üzerine
    # yazıyordu ve mobil çark açı uçlarını planets[].name (İngilizce) ile
    # eşleyemediği için TR'de SIFIR açı çizgisi çiziyordu.
    assert tr["aspects"][0]["aspect"] == "sextile"
    assert tr["aspects"][0]["aspect_local"] == "Altmışlık"
    assert tr["aspects"][0]["p1"] == "Neptune"
    assert tr["aspects"][0]["p1_local"] == "Neptün"
    assert en["aspects"][0]["aspect"] == "sextile"
    assert en["aspects"][0]["aspect_local"] == "Sextile"
    assert tr["moon_phase"]["name"] == "Dolunay"
    assert en["moon_phase"]["name"] == "Full Moon"
    # Gezegenlere yerelleştirilmiş adlar EKLENİR, mevcut alanlar korunur.
    assert en["planets"][0]["name"] == "Sun"
    assert en["planets"][0]["name_local"] == "Sun"
    assert tr["planets"][0]["name_local"] == "Güneş"
    assert en["aspects"][0]["orb"] == 1.2
    # Ham veri degismemeli
    assert ham["retrogrades"] == ["Saturn", "Neptune", "Pluto"]


def test_gokyuzu_carki_sozlesmesi():
    """ÇARK SÖZLEŞMESİ (HA1 bekçisi): yerelleştirilmiş gökyüzünde her açı
    ucu planets[].name içinde bulunmalı ve açı türü küçük-harf anahtar
    kalmalı — mobil çark uçları adla, rengi anahtarla çözer. Bu tutmazsa
    açı ağı SESSİZCE boş çizilir (canlıda aylarca fark edilmedi)."""
    from services import sky_service

    ham = sky_service.get_sky_now(include_nasa=False)
    for kod in i18n.SUPPORTED:
        yerel = prompts.localize_sky(kod, ham)
        adlar = {p["name"] for p in yerel["planets"]}
        anahtarlar = {a for _, a, _ in sky_service._MAJOR_ASPECTS}
        for a in yerel["aspects"]:
            assert a["p1"] in adlar, f"{kod}: {a['p1']} planets'te yok"
            assert a["p2"] in adlar, f"{kod}: {a['p2']} planets'te yok"
            assert a["aspect"] in anahtarlar
            assert a.get("p1_local") and a.get("p2_local")
            assert a.get("aspect_local")


def test_gokyuzu_yerellestirme_bos_veri():
    """Gökyüzü alınamadığında çeviri patlamamalı; sohbet gökyüzsüz devam eder."""
    assert prompts.localize_sky("en", None) == {}
    assert prompts.localize_sky("en", {}) == {}
    # Alanları eksik ama var olan bir yük normalize edilmeli.
    assert prompts.localize_sky("en", {"planets": []})["retrogrades"] == []


@uygulama_gerekir
def test_gokyuzu_ucu_retro_ve_acilari_yerellestirir(monkeypatch):
    from api import sky as sky_api

    monkeypatch.setattr(sky_api, "get_sky_now", lambda: {
        "moon_phase": {"key": "full_moon", "emoji": "🌕", "illumination": 93},
        "retrogrades": ["Saturn"],
        "aspects": [{"p1": "Venus", "p2": "Mars", "aspect": "square",
                     "orb": 2.0}],
        "planets": [],
    })

    with TestClient(app) as client:
        en = client.get("/api/v1/sky/now",
                        headers={"Authorization": "Bearer t-sky-en",
                                 "Accept-Language": "en"})

    veri = en.json()["data"]
    assert veri["retrogrades"] == ["Saturn"]
    # HA1: kararlı anahtar korunur, çeviri *_local'de.
    assert veri["aspects"][0]["aspect"] == "square"
    assert veri["aspects"][0]["aspect_local"] == "Square"
    assert veri["aspects"][0]["p1"] == "Venus"
    assert veri["moon_phase"]["name"] == "Full Moon"


# ---------------------------------------------------------------------------
# Varsayılan hitap dile göre (D8)
# ---------------------------------------------------------------------------

def test_varsayilan_ad_dile_gore():
    """Ad vermeyen kullanıcıya hitap dile göre; bilinmeyen dilde varsayılan dil.

    "Gezgin" bir tur boyunca TR-only sabitti ve İngilizce arayüzdeki kullanıcı
    promptta "Gezgin" diye anılıyordu (D6 ölçümü).
    """
    from core.i18n import DEFAULT, default_name
    assert default_name("tr") == "Gezgin"
    assert default_name("en") == "Traveler"
    assert default_name("xx") == default_name(DEFAULT)
    assert default_name(None) == default_name(DEFAULT)


def test_dogum_modeli_sabit_ad_tasimaz():
    """`BirthData.name` varsayılanı BOŞ; adı `_natal_kwargs(d, lang)` dilden kurar."""
    import io as _io
    from pathlib import Path
    kok = Path(__file__).resolve().parents[1]
    for dosya in ("api/reports.py", "api/astrology.py"):
        govde = _io.open(kok / dosya, encoding="utf-8").read()
        assert 'name: str = "Gezgin"' not in govde, dosya
        assert "default_name(lang)" in govde, dosya

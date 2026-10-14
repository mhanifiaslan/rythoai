"""gz-2 bekçisi: üretilmemiş YORUM, rapor gibi dönmez.

Gemini kotası dolunca ``_cached_generate`` yedek metni döndürüyor ve harcanan
jetonu iade ediyor. Bu bayrak uçlarda DÜŞÜYORDU (yalnız /horoscope ve /dyad
taşıyordu): kullanıcı üç cümlelik jenerik paragrafı ürün sanıyor, jeton
iadesini de öğrenmiyor ve istemcideki ``report_generated`` sayacı "üretildi"
diyordu.

Üç katman ayrı ayrı sınanır, çünkü üç ayrı kusur:
  1. ``_cached_generate`` ``refunded`` bayrağını ÜRETİYOR mu — ve jeton
     harcanmayan uçta (günlük okuma) YALAN SÖYLEMİYOR mu.
  2. Uçlar bu iki bayrağı yanıt gövdesinde TAŞIYOR mu. İlk onarım dört ucu
     kapattı; altı uç (iching, solar-return, progressions, birth-hexagram,
     synastry, relationship) ve /dyad'ın ``refunded``ı bir tur daha
     düşmeye devam etti — uç başına test yazmak yazılmayan ucu korumuyor,
     o yüzden 2c'deki meta-bekçi kaynağı okuyor.
  3. Üretim hatası yığın izi ile mi loglanıyor — yedek metin artık kullanıcıya
     "ürünü göremedin" demek olduğu için kotayı (429) ağır hatadan ayırmak
     gerekiyor.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_yedek_bayragi.py -q
"""
from __future__ import annotations

import ast
import datetime as dt
import logging
import pathlib

import pytest
from fastapi.testclient import TestClient

from core import entitlements, wallet
from core.auth import AuthUser, get_current_user
from services import report_service

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover - ortama bağlı
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulaması içe aktarılamadı: {_APP_IMPORT_ERROR}",
)

DOGUM = {"name": "Ada", "year": 1994, "month": 8, "day": 11,
         "hour": 9, "minute": 30, "city": "Izmir"}

ORANLAR = {"jawToCheek": 0.80, "mouthToFaceWidth": 0.41,
           "eyeSpacing": 0.45, "symmetry": 0.98,
           "upperThird": 0.33, "middleThird": 0.33, "lowerThird": 0.34,
           "widthToHeight": 0.70, "lipFullness": 0.05}

#: Yedek metne düşen üretimin taklidi: gerçek ``_cached_generate``'in döndüğü
#: sözlük şekli. Uçların bayrağı TAŞIYIP taşımadığını ölçmek için yeterli.
YEDEK_YANIT = {"text": "Üç cümlelik hazır paragraf.", "cached": False,
               "fallback": True, "refunded": True}
YEDEK_IADESIZ = {"text": "Üç cümlelik hazır paragraf.", "cached": False,
                 "fallback": True, "refunded": False}
GERCEK_YANIT = {"text": "Gerçek rapor.", "cached": False}


# ---------------------------------------------------------------------------
# 1. Katman: `_cached_generate` bayrağı ÜRETİYOR
# ---------------------------------------------------------------------------

@pytest.fixture()
def llm_dustu(monkeypatch, tmp_path):
    """Gemini hiç metin üretmiyor; önbellek de izole."""
    from core import cache, config
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    monkeypatch.setattr(report_service.gemini_service, "generate",
                        lambda prompt, **k: "")
    yield
    cache._memory.clear()


def test_iade_edilen_jeton_yanitta_SOYLENIR(llm_dustu):
    iadeler: list[str] = []
    sonuc = report_service._cached_generate(
        "gz2-iadeli", "istem", "YEDEK METİN",
        refund=lambda: bool(iadeler.append("natal")) or True)

    assert sonuc["fallback"] is True
    assert sonuc["refunded"] is True, "istemci bunu kullanıcıya söyleyecek"
    assert iadeler == ["natal"], "iade gerçekten yapılmalı"


def test_jeton_harcamayan_ucta_iade_CUMLESI_KURULMAZ(llm_dustu):
    """Günlük okuma jeton harcamaz: "jetonun iade edildi" demek YALAN olurdu.

    Bayrak bu yüzden istemcide sabitlenemez; üretim yerinden gelmek zorunda.
    """
    sonuc = report_service._cached_generate("gz2-iadesiz", "istem", "YEDEK")

    assert sonuc["fallback"] is True
    assert sonuc["refunded"] is False


def test_basarili_uretimde_fallback_bayragi_HIC_YOK(monkeypatch, tmp_path):
    """Yoksa her rapor istemcide hataya dönerdi."""
    from core import cache, config
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    monkeypatch.setattr(report_service.gemini_service, "generate",
                        lambda prompt, **k: "Gerçek metin.")
    monkeypatch.setattr(report_service.fact_guard, "enforce",
                        lambda t, p, **k: (t, True))

    sonuc = report_service._cached_generate("gz2-basarili", "istem", "YEDEK")

    assert sonuc.get("fallback", False) is False
    assert sonuc.get("refunded", False) is False


# ---------------------------------------------------------------------------
# 2. Katman: UÇLAR bayrağı TAŞIYOR
# ---------------------------------------------------------------------------

@pytest.fixture()
def abone(monkeypatch):
    """Ücretli abone; cihaz kilidi ve cüzdan devre dışı.

    Testin konusu jeton bakiyesi ya da harita hesabı değil, yanıtın
    DÜRÜSTLÜĞÜ: uç, üretimden gelen bayrağı gövdeye taşıyor mu?
    """
    from core import device
    app.dependency_overrides[get_current_user] = lambda: AuthUser(
        uid="gz2", email="a@b.c", admin=False, auth_time=1000)
    monkeypatch.setattr(entitlements, "FORCE_PLUS", False)
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: True)
    monkeypatch.setattr(entitlements, "user_local_date",
                        lambda uid: dt.date(2026, 9, 18))
    monkeypatch.setattr(device, "enforce_single_device",
                        lambda *a, **k: None)
    monkeypatch.setattr(wallet, "spender", lambda uid, ozellik, **k: None)
    monkeypatch.setattr(wallet, "refund_spend",
                        lambda uid, ozellik: True)
    yield
    app.dependency_overrides.clear()


@pytest.fixture()
def harita_sahte(monkeypatch):
    """Efemeris ve yerelleştirme devre dışı: uç yalnız sözlük kuruyor."""
    from api import reports
    harita = {"sun_sign": "Leo", "moon_sign": "Aries", "ascendant": "Libra",
              "planets": {}}
    monkeypatch.setattr(reports.astro_service, "get_natal_chart",
                        lambda **k: harita)
    monkeypatch.setattr(reports.astro_service, "subject_kwargs", lambda d: {})
    monkeypatch.setattr(reports, "get_bazi_chart", lambda **k: {"pillars": {}})
    monkeypatch.setattr(reports, "get_sky_now",
                        lambda: {"moon_phase": None, "retrogrades": []})
    monkeypatch.setattr(reports.prompts, "localize_sky",
                        lambda lang, sky: {"moon_phase": None,
                                           "retrogrades": []})
    monkeypatch.setattr(reports.prompts, "localize_chart",
                        lambda lang, c: c)
    monkeypatch.setattr(reports.prompts, "localize_bazi", lambda lang, c: c)
    return reports


@uygulama_gerekir
def test_natal_ucu_bayraklari_TASIR(abone, harita_sahte, monkeypatch):
    monkeypatch.setattr(harita_sahte.report_service, "natal_report",
                        lambda *a, **k: YEDEK_YANIT)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/reports/natal", json=DOGUM)

    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["fallback"] is True, "yedek metin rapor gibi döndü"
    assert veri["refunded"] is True, "jeton iadesi söylenmedi"


@uygulama_gerekir
def test_bazi_ucu_bayraklari_HARITAYLA_BIRLIKTE_tasir(abone, harita_sahte,
                                                     monkeypatch):
    """BaZi'de bayrak haritayı GÖTÜRMEZ, ona eşlik eder.

    Harita deterministik hesap ve ücreti ödendi; eksik olan yalnız yorum.
    Sekme bu iki bayrağa bakıp haritayı çiziyor, yorumun yerine dürüst cümleyi
    koyuyor — bu yüzden `chart` yanıtta DURMAK ZORUNDA.
    """
    monkeypatch.setattr(harita_sahte.report_service, "bazi_report",
                        lambda *a, **k: YEDEK_YANIT)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/reports/bazi", json=DOGUM)

    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["fallback"] is True
    assert veri["refunded"] is True
    assert veri["chart"] is not None, "ölçülmüş harita yanıttan düştü"


@uygulama_gerekir
def test_gunluk_okuma_bayragi_tasir_ama_IADE_YOK(abone, harita_sahte,
                                                 monkeypatch):
    """Günlük okuma jeton harcamaz; istemci iade cümlesini KURMAYACAK."""
    monkeypatch.setattr(harita_sahte.report_service, "daily_reading",
                        lambda *a, **k: YEDEK_IADESIZ)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/reports/daily", json=DOGUM)

    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["fallback"] is True
    assert veri["refunded"] is False


@uygulama_gerekir
def test_firaset_ucu_bayraklari_TASIR(abone, monkeypatch):
    from api import face_reading
    monkeypatch.setattr(face_reading.consent_service, "has_face_consent",
                        lambda uid: True)
    monkeypatch.setattr(face_reading.profile_service, "get_profile",
                        lambda uid: {})
    monkeypatch.setattr(face_reading.chart_context, "chart_whisper",
                        lambda *a, **k: None)
    monkeypatch.setattr(face_reading.report_service, "firasa_report",
                        lambda *a, **k: YEDEK_YANIT)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/face/reading", json=ORANLAR)

    assert yanit.status_code == 200, yanit.text
    govde = yanit.json()
    assert govde["fallback"] is True
    assert govde["refunded"] is True


@uygulama_gerekir
def test_gercek_rapor_bayraksiz_doner(abone, harita_sahte, monkeypatch):
    """Bayrak yoksa `False` gelmeli; aksi halde her rapor hataya dönerdi."""
    monkeypatch.setattr(harita_sahte.report_service, "natal_report",
                        lambda *a, **k: GERCEK_YANIT)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/reports/natal", json=DOGUM)

    veri = yanit.json()["data"]
    assert veri["fallback"] is False
    assert veri["refunded"] is False


# ---------------------------------------------------------------------------
# 2b. Katman: altı uç bir tur boyunca bayrağı DÜŞÜRÜYORDU
# ---------------------------------------------------------------------------
#
# Ölçüldü: `_cached_generate` her yedekte bayrağı üretiyor, ama /iching,
# /solar-return, /progressions, /birth-hexagram, /synastry gövdeyi
# `"report": report["text"]` ile kurup bayrağı atıyordu; /relationship
# `okuma` sözlüğünde taşıyıp uçta atıyordu; /dyad `fallback` taşıyıp
# `refunded`ı atıyordu. Jeton iade ediliyordu (para kaybı yok) ama bakiye
# açıklamasız yükselirken ekranda "rapor" duruyordu (CLAUDE.md "kullanıcı
# farkı anlamayan yedekler"). Her test ölçülmüş verinin de yanıtta
# KALDIĞINI sabitler — bayrak haritayı götürmez, ona eşlik eder.

@uygulama_gerekir
def test_iching_ucu_bayraklari_TASIR(abone, harita_sahte, monkeypatch):
    r = harita_sahte
    monkeypatch.setattr(r, "cast_iching",
                        lambda soru, method="coins": {"hexagram": {"n": 1}})
    monkeypatch.setattr(r, "enrich_cast", lambda cast, **k: cast)
    monkeypatch.setattr(r.profile_service, "get_profile", lambda uid: None)
    monkeypatch.setattr(r.prompts, "localize_iching", lambda lang, c: c)
    monkeypatch.setattr(r.report_service, "iching_reading",
                        lambda *a, **k: YEDEK_YANIT)

    with TestClient(app) as client:
        # Soru verilmez: soru kapısı (LLM hükmü) bu testin konusu değil.
        yanit = client.post("/api/v1/reports/iching", json={"method": "coins"})

    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["fallback"] is True, "yedek metin okuma gibi döndü"
    assert veri["refunded"] is True, "jeton iadesi söylenmedi"
    assert veri["cast"] == {"hexagram": {"n": 1}}, "ölçülen çekim düştü"


@uygulama_gerekir
def test_solar_return_ucu_bayraklari_TASIR(abone, harita_sahte, monkeypatch):
    from services import predict_service
    r = harita_sahte
    monkeypatch.setattr(predict_service, "solar_return",
                        lambda *a, **k: {"sun_sign": "Leo"})
    monkeypatch.setattr(r.profile_service, "get_profile", lambda uid: {})
    monkeypatch.setattr(r.report_service, "solar_return_report",
                        lambda *a, **k: YEDEK_YANIT)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/reports/solar-return", json=DOGUM)

    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["fallback"] is True
    assert veri["refunded"] is True
    assert veri["solar_return"] == {"sun_sign": "Leo"}, "yıl haritası düştü"


@uygulama_gerekir
def test_progressions_ucu_bayraklari_TASIR(abone, harita_sahte, monkeypatch):
    from services import predict_service
    r = harita_sahte
    monkeypatch.setattr(predict_service, "secondary_progressions",
                        lambda *a, **k: {"moon": "Aries"})
    monkeypatch.setattr(predict_service, "solar_arc_hits",
                        lambda *a, **k: [])
    monkeypatch.setattr(r.prompts, "localize_progressions",
                        lambda lang, prog, hits: {"prog": prog, "hits": hits})
    monkeypatch.setattr(r.report_service, "progressions_report",
                        lambda *a, **k: YEDEK_YANIT)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/reports/progressions", json=DOGUM)

    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["fallback"] is True
    assert veri["refunded"] is True
    assert veri["progressions"]["prog"] == {"moon": "Aries"}


@uygulama_gerekir
def test_birth_hexagram_ucu_bayraklari_TASIR(abone, harita_sahte,
                                             monkeypatch):
    r = harita_sahte
    konum = {"gate": 25, "line": 3, "longitude": 10.0, "hour_known": True,
             "hexagram": {"number": 25}, "alternate_gate": None,
             "alternate_hexagram": None,
             "gate_passage": {"gate_tr": "Kapı dokusu", "gate_en": "Gate"}}
    monkeypatch.setattr(r.birth_hexagram_service, "birth_hexagram",
                        lambda **k: konum)
    monkeypatch.setattr(r.prompts, "localize_hexagram", lambda lang, h: h)
    monkeypatch.setattr(r.report_service, "birth_hexagram_report",
                        lambda *a, **k: YEDEK_YANIT)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/reports/birth-hexagram", json=DOGUM)

    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["fallback"] is True
    assert veri["refunded"] is True
    # Kalıcı çekirdek (kapı + çizgi + sabit pasaj) yanıtta durur; düşen
    # yalnız günün kesişimi.
    assert veri["position"]["gate"] == 25
    assert veri["position"]["line"] == 3
    assert veri["gate_text"] == "Kapı dokusu"


@uygulama_gerekir
def test_synastry_ucu_bayraklari_TASIR(abone, harita_sahte, monkeypatch):
    r = harita_sahte
    monkeypatch.setattr(r.astro_service, "get_synastry",
                        lambda a, b: {"aspects": [{"p1": "sun"}]})
    monkeypatch.setattr(r.report_service, "synastry_report",
                        lambda *a, **k: YEDEK_YANIT)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/reports/synastry",
                            json={"person1": DOGUM, "person2": DOGUM})

    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["fallback"] is True
    assert veri["refunded"] is True
    assert veri["synastry"] == {"aspects": [{"p1": "sun"}]}


@pytest.fixture()
def karsi_taraf(harita_sahte, monkeypatch):
    """Arkadaş yolu: iki profil de sunucuda, hesap sahte, ölçüm LLM'siz."""
    from services import synastry_service
    r = harita_sahte
    karsi = synastry_service.Counterpart(key="gz2-dost", birth={},
                                         label="Deniz")
    monkeypatch.setattr(r.profile_service, "are_friends", lambda a, b: True)
    monkeypatch.setattr(synastry_service, "friend_counterpart",
                        lambda uid, dost: karsi)
    monkeypatch.setattr(r.profile_service, "get_profile",
                        lambda uid: {"displayName": "Ada"})
    monkeypatch.setattr(r.profile_service, "birth_kwargs", lambda p, lang=None: {})
    monkeypatch.setattr(r.chart_context, "has_birth_data", lambda p: True)
    monkeypatch.setattr(r.astro_service, "get_synastry",
                        lambda a, b: {"person1": {}, "person2": {}})
    monkeypatch.setattr(synastry_service, "pair_transits",
                        lambda *a, **k: None)
    return synastry_service


@uygulama_gerekir
def test_dyad_ucu_bayraklari_TASIR(abone, harita_sahte, karsi_taraf,
                                   monkeypatch):
    """/dyad `fallback` taşıyordu ama `refunded`ı değil — ikili dinamik
    jeton harcar, iade söylenmeliydi."""
    r = harita_sahte
    monkeypatch.setattr(r.prompts, "sign_from_point", lambda lang, p: None)
    monkeypatch.setattr(r.report_service, "dyad_reading",
                        lambda *a, **k: YEDEK_YANIT)

    with TestClient(app) as client:
        yanit = client.post("/api/v1/reports/dyad", json={"friend_uid": "d"})

    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["fallback"] is True
    assert veri["refunded"] is True, "jeton iadesi söylenmedi"


@uygulama_gerekir
def test_relationship_ucu_bayragi_tasir_ama_IADE_YOK(abone, harita_sahte,
                                                     karsi_taraf,
                                                     monkeypatch):
    """İlişki okuması JETONSUZ: bayrak taşınır, iade cümlesi KURULMAZ.

    Abone dalında `okuma` sözlüğü bayrağı taşıyor ama uç atıyordu; ölçülen
    eksenler (LLM'siz hesap) yanıtta kalmak zorunda — "hesap bedava,
    yorum paralı" sözleşmesi.
    """
    r = harita_sahte
    monkeypatch.setattr(karsi_taraf, "axes_for",
                        lambda uid, o: {"calc_version": "1", "axes": []})
    monkeypatch.setattr(r.prompts, "localize_relationship_axes",
                        lambda lang, e, rel: {"axes": [
                            {"axis": "communication", "level": "high"}]})
    monkeypatch.setattr(r.report_service, "relationship_reading",
                        lambda *a, **k: {**YEDEK_IADESIZ,
                                         "axis_lines": {}, "theme": ""})

    with TestClient(app) as client:
        yanit = client.post("/api/v1/reports/relationship",
                            json={"friend_uid": "d"})

    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["fallback"] is True, "yedek metin ilişki okuması gibi döndü"
    assert veri["refunded"] is False, "jetonsuz uçta iade cümlesi yalan olur"
    assert veri["axes"][0]["axis"] == "communication", "ölçüm düştü"


# ---------------------------------------------------------------------------
# 2c. META-BEKÇİ: report_service çağıran HER uç iki bayrağı taşır
# ---------------------------------------------------------------------------

_UC_DOSYALARI = ("api/reports.py", "api/face_reading.py")

#: Bugün bilinen uçlar: ölçümün BOŞ geçmediğinin kanıtı. Yeni uç listeye
#: yazılmadan da denetlenir (küme kaynaktan türetilir); buradaki adlar
#: yalnız "ağaç gezgini hiçbir şey bulamadı" hâlini kırmızıya çevirir.
_BILINEN_UCLAR = {
    "horoscope", "daily", "natal", "bazi", "iching", "solar_return",
    "progressions", "birth_hexagram", "dyad", "relationship", "synastry",
    "firasa_reading",
}


def _router_uclari(agac: "ast.Module"):
    """`@router.<yöntem>(...)` ile süslenmiş fonksiyonlar."""
    for dugum in ast.walk(agac):
        if not isinstance(dugum, ast.FunctionDef):
            continue
        for dek in dugum.decorator_list:
            hedef = dek.func if isinstance(dek, ast.Call) else dek
            if (isinstance(hedef, ast.Attribute)
                    and isinstance(hedef.value, ast.Name)
                    and hedef.value.id == "router"):
                yield dugum
                break


def _report_service_cagiriyor(fn: "ast.FunctionDef") -> bool:
    return any(isinstance(d, ast.Attribute)
               and isinstance(d.value, ast.Name)
               and d.value.id == "report_service"
               for d in ast.walk(fn))


def _tasinan_anahtarlar(fn: "ast.FunctionDef") -> set[str]:
    """Gövdede kurulan sözlük anahtarları + `veri["x"] = ...` atamaları."""
    anahtarlar: set[str] = set()
    for d in ast.walk(fn):
        if isinstance(d, ast.Dict):
            anahtarlar.update(k.value for k in d.keys
                              if isinstance(k, ast.Constant)
                              and isinstance(k.value, str))
        elif isinstance(d, ast.Assign):
            for hedef in d.targets:
                if (isinstance(hedef, ast.Subscript)
                        and isinstance(hedef.slice, ast.Constant)
                        and isinstance(hedef.slice.value, str)):
                    anahtarlar.add(hedef.slice.value)
    return anahtarlar


def test_report_service_cagiran_HER_uc_bayragi_tasir():
    """Yeni bir LLM ucu eklenince kendiliğinden kırmızı.

    Altı uç bir tur boyunca bayrağı düşürdü ve hiçbir test bunu
    görmedi — uç başına test yazmak, yazılmayan ucu korumaz. Bu bekçi
    kaynağın kendisini okur: `report_service.` çağıran her `@router`
    bloğu yanıt gövdesinde `"fallback"` VE `"refunded"` anahtarlarını
    kurmak zorunda.

    Okuma AST ile, metin eşleşmesiyle DEĞİL: "bir şeyin yokluğunu arayan
    bekçi onu anlatan yorumu görmemeli" (CLAUDE.md §5) ve burada yorumlar
    tam da `fallback` kelimesini açıklıyor; `#` satırlarını atmak
    docstring'leri ve satır sonu yorumlarını yine görürdü. Ağaçta yorum
    yok, docstring ise anahtar OLARAK kullanılan bir sabit değil.
    """
    kok = pathlib.Path(__file__).resolve().parents[1]
    eksik: list[str] = []
    denetlenen: set[str] = set()
    for dosya in _UC_DOSYALARI:
        agac = ast.parse((kok / dosya).read_text(encoding="utf-8"),
                         filename=dosya)
        for uc in _router_uclari(agac):
            if not _report_service_cagiriyor(uc):
                continue
            denetlenen.add(uc.name)
            kayip = {"fallback", "refunded"} - _tasinan_anahtarlar(uc)
            if kayip:
                eksik.append(f"{dosya}::{uc.name} → {sorted(kayip)} yok")

    assert _BILINEN_UCLAR <= denetlenen, (
        f"ağaç gezgini bilinen uçları bulamadı: "
        f"{sorted(_BILINEN_UCLAR - denetlenen)}")
    assert not eksik, (
        "report_service çağıran uç yedek bayrağını düşürüyor — istemci "
        "şablon metni rapor sanır:\n  " + "\n  ".join(eksik))


# ---------------------------------------------------------------------------
# 3. Katman: üretim hatası YIĞIN İZİYLE loglanır
# ---------------------------------------------------------------------------

class _Patlayan:
    """Kotası dolmuş istemci taklidi."""

    class models:
        @staticmethod
        def generate_content(*a, **k):
            raise RuntimeError("429 RESOURCE_EXHAUSTED")


def test_uretim_hatasi_YIGIN_IZIYLE_loglanir(monkeypatch, caplog):
    """Yedek metin artık kullanıcıya "ürünü göremedin" demek (gz-2).

    Kotayı (429) ağır hatadan ayırmak için yığın izi ŞART; `logger.warning`
    onu taşımaz ve bu satır artık bir ÜRÜN kaybının tek izi.
    """
    from services import gemini_service
    monkeypatch.setattr(gemini_service, "_get_client", lambda: _Patlayan())
    with caplog.at_level(logging.WARNING, logger=gemini_service.__name__):
        assert gemini_service.generate("istem") is None
    kayitlar = [r for r in caplog.records
                if "Gemini üretim hatası" in r.getMessage()]
    assert kayitlar, "üretim hatası hiç loglanmadı"
    assert kayitlar[0].exc_info is not None, (
        "logger.warning yığın izi taşımaz; kota ile ağır hata ayırt edilemez")

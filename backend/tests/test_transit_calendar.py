r"""R5-6: transit takvimi ucretsiz katmana acildi — ama YALNIZCA olcum.

Urunun kurali "hesap bedava, yorum parali". Takvimin tarihleri ve temalari
hesabin kendisi (LLM'siz, zaten onbellekli); kilitli olan tek sey okuma.
Bu dosya o cizgiyi korur: ucretsiz yanitta yorum cumlesi KALMAMALI, tarih
ve tema KALMALI. Ciziginin iki yonu de kirilgan — biri sizdirir, digeri
teaser'i anlamsizlastirir.

Calistirma:  .venv\Scripts\python.exe -m pytest tests/test_transit_calendar.py -q
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from core import cache, entitlements
from core.auth import AuthUser, get_current_user

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover - ortama bagli
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulamasi ice aktarilamadi: {_APP_IMPORT_ERROR}",
)

#: Sunucunun urettigi ham takvim (zenginlestirme sonrasi hali).
SAHTE_TAKVIM = {
    "events": [
        {"type": "aspect_exact", "date": "2026-08-20",
         "transit": "Mars", "natal": "Venus", "aspect": "trine",
         "orb": 0.4, "theme": "relationships", "tone": "support"},
        # OP2: tur ve gezegen GERCEK olmali. `predict_service` "station"
        # diye bir tur uretmiyor (yalniz station_retrograde /
        # station_direct) ve Merkur transit gezegeni degil - eski sahte
        # yuk ikisini de uyduruyordu. Bedeli olculdu: istasyon anlam
        # cumlesi eklendikten sonra da bu dosya yesil kaliyordu, cunku
        # uydurma tur tabloya hic ugramiyordu. Sahte yuk motorun
        # URETTIGI bicimde degilse bekci kordur.
        {"type": "station_retrograde", "date": "2026-09-02",
         "transit": "Pluto"},
    ],
    "active_now": [],
}


@pytest.fixture(autouse=True)
def zorlamayi_kapat(monkeypatch):
    monkeypatch.setattr(entitlements, "FORCE_PLUS", False)


@pytest.fixture
def kullanici():
    app.dependency_overrides[get_current_user] = lambda: AuthUser(
        uid="takvim-uid", email="a@b.c")
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def sahte_motor(monkeypatch):
    """Uc, takvimi hesaplamak yerine sabit yuku dondurur."""
    from api import astrology
    from services import chart_context, predict_service, profile_service,\
        signal_service

    monkeypatch.setattr(profile_service, "get_profile",
                        lambda uid: {"birthTime": "14:30"})
    monkeypatch.setattr(chart_context, "has_birth_data", lambda p: True)
    monkeypatch.setattr(profile_service, "birth_kwargs", lambda p: {
        "name": "t", "year": 1990, "month": 5, "day": 12,
        "hour": 14, "minute": 30, "city": "Istanbul", "nation": "TR"})
    monkeypatch.setattr(predict_service, "transit_calendar",
                        lambda **kw: dict(SAHTE_TAKVIM))
    monkeypatch.setattr(chart_context, "chart_facts", lambda uid, p, **kw: {})
    monkeypatch.setattr(signal_service, "enrich_events",
                        lambda olaylar, natal: olaylar)
    # Ç-turu: yorum katmani (LLM) ayrica sahtelenir — gercek gemini_service
    # cagrisina hic GIDILMEZ, deterministik kalir. Cagri sayaci disaridan
    # okunabilir (ucretsiz katmanda sifir kalmali — bkz. Ç6 testleri).
    sayac = {"n": 0}

    def sahte_yorum(events, lang):
        sayac["n"] += 1
        olay = events[0]
        return {signal_service.event_fingerprint(olay):
                "Bu gune ozgu cumle."}

    monkeypatch.setattr(signal_service, "calendar_insights", sahte_yorum)
    monkeypatch.setattr(astrology, "_test_yorum_sayaci", sayac,
                        raising=False)
    # Onbellek testler arasinda tasinmasin: bir kosuda yazilan yuk
    # digerine sizarsa kilit testi yanlislikla gecerdi.
    bellek: dict = {}
    monkeypatch.setattr(cache, "get", lambda k: bellek.get(k))
    monkeypatch.setattr(cache, "set",
                        lambda k, v, ttl_seconds=None, **kw: bellek.update({k: v}))
    return astrology


def _cek(monkeypatch, astrology, abone: bool) -> dict:
    monkeypatch.setattr(astrology, "is_subscriber", lambda uid: abone)
    with TestClient(app) as client:
        yanit = client.get("/api/v1/astrology/transit-calendar",
                           headers={"Authorization": "Bearer test-takvim"})
    assert yanit.status_code == 200, yanit.text
    return yanit.json()["data"]


@uygulama_gerekir
def test_ufuk_otuz_gun(sahte_motor):
    """Kullanici karari (R5-6): 90 -> 30. Sabit tek yerde; sapmasi
    onbellek anahtarini da bozar (anahtarda gun sayisi var)."""
    assert sahte_motor.TRANSIT_CALENDAR_DAYS == 30


@uygulama_gerekir
def test_ucretsiz_kullanici_402_ALMAZ(monkeypatch, kullanici, sahte_motor):
    """Uc `require_plus` arkasindaydi; ucretsiz kullanici sadece paywall
    goruyordu. Artik hesabi gorebiliyor."""
    veri = _cek(monkeypatch, sahte_motor, abone=False)
    assert veri["events"], "ucretsiz kullanici olaylari gormeli"


@uygulama_gerekir
def test_ucretsizde_yorum_YOK_olcum_VAR(monkeypatch, kullanici, sahte_motor):
    veri = _cek(monkeypatch, sahte_motor, abone=False)
    olay = veri["events"][0]

    # Giden: yorum.
    assert "line" not in olay
    assert "technical" not in olay
    assert olay["locked"] is True

    # Kalan: olcum. Teaser durust olmali — tarih ve tema GERCEK.
    assert olay["date"] == "2026-08-20"
    assert olay["theme"] == "relationships"
    assert olay["theme_local"]
    assert olay["tone"] == "support"
    assert olay["date_local"]


@uygulama_gerekir
def test_abonede_okuma_AYNEN_kalir(monkeypatch, kullanici, sahte_motor):
    veri = _cek(monkeypatch, sahte_motor, abone=True)
    olay = veri["events"][0]

    assert olay["line"], "abonede gundelik cumle gelmeli"
    assert olay["technical"], "abonede dayanak satiri gelmeli"
    assert "locked" not in olay


@uygulama_gerekir
def test_paylasimli_okumaya_kilit_KONMAZ(monkeypatch, kullanici,
                                         sahte_motor):
    """Istasyonun okumasi PAYLASIMLI oldugu icin kilit rozeti ona konmaz.

    Bu testin eski gerekcesi "istasyonlarin hicbir katmanda gundelik
    cumlesi yok" diyordu ve OP2'den sonra YANLISTIR: istasyon artik sabit
    tablodan bir anlam cumlesi aliyor. Degismez AYNI kaldi, gerekcesi
    degisti - ve gerekce onemli, cunku kilit kosulu `theme` varligina
    bakiyor, `line`a bakmiyor (bkz. api/astrology.py `_takvimi_kilitle`).

    Yeni gerekce: o cumle kisiye ozel DEGIL. Gezegenin kendi dogasini ve
    yonunun evresini anlatir, kullaniciyi anlatmaz; olculmus ve paylasimli
    bir olgudur, bu yuzden ucretsiz katmanda da gorunur. Ona "Rytho+ ile
    acilir" demek abonelikte FAZLA bir sey vermeyen bir kilit satmak
    olurdu - cihaz turunda (1.5.1+18) kullanici gun kartinda tam bunu
    gordu.
    """
    veri = _cek(monkeypatch, sahte_motor, abone=False)
    tipler = {o["type"]: o for o in veri["events"]}

    assert tipler["aspect_exact"]["locked"] is True
    assert "locked" not in tipler["station_retrograde"]
    # Istasyonun olcumu ucretsiz katmanda da duruyor.
    assert tipler["station_retrograde"]["transit_local"]
    # OP2: ANLAMI da duruyor. `_KILITLI_ALANLAR` bu iki alani ucretsiz
    # katmanda siliyor; silme kosulu temasiz olaya ugramadigi icin
    # istasyonun anlami gecip gidiyor. Kosul `line` varligina baglansa
    # sahibin sikayet ettigi ciplak satir geri donerdi.
    assert tipler["station_retrograde"]["line"]
    assert tipler["station_retrograde"]["technical"]


@uygulama_gerekir
def test_istasyonun_anlami_HER_KATMANDA_AYNI(monkeypatch, kullanici,
                                             sahte_motor):
    """Ucretsiz ve abone kullanici istasyonda AYNI cumleyi gorur.

    Ayrim bilerek boyle: "hesap bedava, yorum parali" kurali KISIYE OZEL
    yoruma bakar. Istasyon cumlesi LLM'den gelmiyor, sabit tablodan
    geliyor ve kullanicidan bagimsiz - iki katmanda farkli olmasi icin
    hicbir gerekce yok. Iki yonu de kirilgan: ayrisirsa ya ucretsiz
    kullanici ciplak satira doner ya da abone fazladan bir sey aldigini
    sanir.
    """
    ucretsiz = _cek(monkeypatch, sahte_motor, abone=False)
    abone = _cek(monkeypatch, sahte_motor, abone=True)

    def istasyon(veri):
        return next(o for o in veri["events"]
                    if o["type"] == "station_retrograde")

    assert istasyon(ucretsiz)["line"] == istasyon(abone)["line"]
    assert istasyon(ucretsiz)["technical"] == istasyon(abone)["technical"]


@uygulama_gerekir
def test_ucretsiz_kullanicida_yorum_hic_uretilmez(monkeypatch, kullanici,
                                                   sahte_motor):
    """Ç6: 'hesap bedava, yorum parali' — ucretsiz kullanicida takvim
    yorumu (LLM cagrisi) HIC tetiklenmemeli. Onceki tasarimda her aci-
    kesinlesmesi otomatik `line` aldigi icin bu ayrim yoktu; simdi
    `calendar_insights` YALNIZCA abone dalinda cagriliyor — bu test
    ucretsiz kullanicida cagri sayacinin sifir kaldigini dogrudan olcer.
    """
    _cek(monkeypatch, sahte_motor, abone=False)
    assert sahte_motor._test_yorum_sayaci["n"] == 0


@uygulama_gerekir
def test_abonede_yorum_tek_seferde_uretilir_ve_onbelleklenir(
        monkeypatch, kullanici, sahte_motor):
    """Ç2: yorum onbellegi 24s TTL ile ayri anahtarlanir — ayni istek
    ikinci kez atildiginda LLM'e tekrar gidilmez."""
    _cek(monkeypatch, sahte_motor, abone=True)
    _cek(monkeypatch, sahte_motor, abone=True)
    assert sahte_motor._test_yorum_sayaci["n"] == 1

"""NASA JPL Horizons kapisi: `sky_service`in tek dis istemcisi.

Gokyuzu yukundeki `distance_au` alani Horizons'tan gelir; ag erisilemezse
konumlar yine swisseph'ten hesaplanir ve uzaklik bos kalir. Testlerde bu
kapi conftest `horizons_hermetik` ile kapali (gerekcesi ve olcumu orada).

Calistirma:  .venv\\Scripts\\python.exe -m pytest tests/test_sky_horizons.py -q
"""
from __future__ import annotations

import httpx
import pytest

from services import sky_service


@pytest.fixture
def temiz_onbellek(tmp_path, monkeypatch):
    """Onceki bir kosunun gunluk Horizons kaydi bekciyi KOR etmesin: kayit
    varsa `_horizons_distances` istemciye hic varmadan doner ve pin delik
    olsa bile bekci yesil kalirdi."""
    from core import cache, config
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    yield
    cache._memory.clear()


def test_pin_sahtelenmemis_gokyuzu_nasa_ya_ulasmaz(monkeypatch,
                                                   temiz_onbellek):
    """conftest `horizons_hermetik` pininin BEYANI olculur: hicbir seyi
    sahtelemeyen bir test (uclarin yolu: `include_nasa` varsayilan acik)
    gercek HTTP istemcisine HIC ulasmaz.

    Kaydedici gercek `httpx.Client`in yerine konur ve firlatir: pin
    delikse bile NASA'ya gidilmez, uretimin `except` dali yakalar ve
    bekci kaydediciden kizarir."""
    ulasilan: list[str] = []

    def kaydedici(*_a, **_k):
        ulasilan.append("httpx.Client")
        raise AssertionError("pin yok: bu istemci NASA'ya gidecekti")

    monkeypatch.setattr(httpx, "Client", kaydedici)

    gokyuzu = sky_service.get_sky_now()

    assert ulasilan == [], (
        f"pin delik: gokyuzu gercek HTTP istemcisine ulasti {ulasilan}")
    # Uretimin "Horizons erisilemedi" dali: konum var, uzaklik yok.
    assert gokyuzu["planets"]
    assert all(p["distance_au"] is None for p in gokyuzu["planets"])

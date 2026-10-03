"""Gün sınırı kullanıcının yerel gününde (D2).

Sunucu UTC'de çalışıyor ve gün sınırı her yerde `dt.date.today()` idi.
Türkiye'de sonucu şuydu: kullanıcının günü saat 03:00'te dönüyordu — gece
yarısıyla 03:00 arasında günlük okuma dünkü metni gösteriyor, ücretsiz kota
da o saatte yenileniyordu.

Yerel güne geçmek tek başına bir istismar kapısı açar: kullanıcı cihazının
saat dilimini oynatarak "yeni gün" tetikleyip kotayı sıfırlayabilir. Bu
yüzden sıfırlama gün ETİKETİNE değil, kayıtlı pencerenin gerçekten
kapanmış olmasına bağlı. İkisi de burada sınanıyor.
"""
from __future__ import annotations

import datetime as dt
from zoneinfo import ZoneInfo

import pytest

from core import entitlements


@pytest.fixture
def temiz_onbellek(tmp_path, monkeypatch):
    from core import cache, config
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    yield
    cache._memory.clear()


class TestYerelGun:
    def test_gece_yarisindan_sonra_yeni_gun(self, monkeypatch):
        """TR'de 00:30 (=21:30 UTC dün) yerel gün BUGÜNÜ göstermeli."""
        istanbul = ZoneInfo("Europe/Istanbul")
        monkeypatch.setattr(entitlements, "_user_tz", lambda uid: istanbul)

        sahte_utc = dt.datetime(2026, 8, 6, 21, 30, tzinfo=dt.timezone.utc)

        class SahteDatetime(dt.datetime):
            @classmethod
            def now(cls, tz=None):
                return sahte_utc if tz else sahte_utc.replace(tzinfo=None)

        monkeypatch.setattr(entitlements.dt, "datetime", SahteDatetime)
        # UTC'de hâlâ 6 Ağustos; kullanıcı için 7 Ağustos 00:30.
        assert entitlements.user_local_date("u1") == dt.date(2026, 8, 7)

    def test_pencere_yerel_gun_sonunda_kapanir(self):
        """TR günü UTC 21:00'de biter — pencere kapanışı onu göstermeli."""
        istanbul = ZoneInfo("Europe/Istanbul")
        gun, kapanis = entitlements._quota_window(istanbul)
        kapanis_utc = dt.datetime.fromtimestamp(kapanis, dt.timezone.utc)
        yerel = kapanis_utc.astimezone(istanbul)
        assert yerel.hour == 0 and yerel.minute == 0
        assert yerel.date() == dt.date.fromisoformat(gun) + dt.timedelta(days=1)


class TestKotaPenceresi:
    """`_sayac_gecerli` — dilim oynatarak kota sıfırlama kapalı mı?"""

    def test_ayni_gun_sayac_gecerli(self):
        assert entitlements._sayac_gecerli(
            {"date": "2026-08-07", "chat": 3}, "2026-08-07", 1000.0)

    def test_pencere_kapandiysa_sifirlanir(self):
        """Gerçek gün dönümü: kayıtlı pencere geçmişte kaldı."""
        data = {"date": "2026-08-06", "resetAtUtc": 500.0}
        assert not entitlements._sayac_gecerli(data, "2026-08-07", 900.0)

    def test_dilim_oynatmak_sifirlamaz(self):
        """Gün etiketi ileri kaydı ama pencere HENÜZ kapanmadı.

        İstismar senaryosu: kullanıcı UTC+3'ten UTC+14'e geçerek yerel
        gününü bir ileri alır. Sayaç sıfırlanmamalı — zaman geri alınamaz.
        """
        data = {"date": "2026-08-07", "chat": 5, "resetAtUtc": 2000.0}
        assert entitlements._sayac_gecerli(data, "2026-08-08", 1500.0)

    def test_dilim_geri_almak_da_sifirlamaz(self):
        data = {"date": "2026-08-07", "chat": 5, "resetAtUtc": 2000.0}
        assert entitlements._sayac_gecerli(data, "2026-08-06", 1500.0)

    def test_eski_kayit_resetsiz_gun_etiketiyle_sifirlanir(self):
        """`resetAtUtc` alanı olmayan eski belgeler eski davranışta kalır."""
        assert not entitlements._sayac_gecerli(
            {"date": "2026-08-06", "chat": 5}, "2026-08-07", 100.0)


class TestOkumaAnahtari:
    def test_gunluk_okuma_verilen_gunu_kullanir(self, monkeypatch,
                                                temiz_onbellek):
        """`today` geçildiğinde önbellek anahtarı ONU taşımalı."""
        from services import report_service

        yakalanan: dict[str, str] = {}

        def sahte_cached_generate(cache_key, prompt, fallback, **kw):
            yakalanan["key"] = cache_key
            return {"text": "ok", "cached": False}

        monkeypatch.setattr(report_service, "_cached_generate",
                            sahte_cached_generate)
        monkeypatch.setattr(report_service, "retrieve_context",
                            lambda *a, **k: "")
        monkeypatch.setattr(report_service.memory_service, "memory_context",
                            lambda uid, max_chars=600, **k: "")
        # Yerel gün çağrılırsa test niyetini kaçırırız: parametre kazanmalı.
        monkeypatch.setattr(
            report_service.entitlements, "user_local_date",
            lambda uid: pytest.fail("today verildiyse profil okunmamalı"))

        report_service.daily_reading(
            "u-d2", {"sun_sign": "Boğa", "moon_sign": "Aslan",
                     "ascendant": "Terazi", "points": [], "aspects": []},
            {"moon_phase": {}, "retrogrades": [], "aspects": []},
            lang="tr", today=dt.date(2026, 8, 7))

        assert "2026-08-07" in yakalanan["key"]

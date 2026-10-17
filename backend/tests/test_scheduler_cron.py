"""Zamanlayıcı saatleri (olcum-1): gecelik rollup UTC gününün SONUNDA koşar.

`POST /admin/collect` tarih parametresi almazsa BUGÜNÜ topluyor
(services/stats_service `collect`) ve gün penceresi `[00:00, +1 gün)`. Sabaha
karşı koşan bir iş günün yalnız ilk saatlerini görür: DAU ~0,
gelir/AI/jeton serileri boş. Kusur SESSİZ — `rollupStale` uyarısı
`generatedAt`e baktığı için doküman TAZE sayılır, zil çalmaz ve operatör
yanlış sayıyı doğru sanıp fiyat/maliyet kararı verir.

Saat bir sonraki düzenlemede sessizce geri kaymasın diye burada kilitlenir.
Betiğin YORUMLARI önce atılır: gerekçe metni eski saati (02:40) anlatıyor ve
ham arama o yorumu iş tanımı sanardı.
"""
from __future__ import annotations

import re
from pathlib import Path

_KOK = Path(__file__).resolve().parent.parent.parent


def _betik() -> str:
    return (_KOK / "infra" / "create-scheduler.ps1").read_text(
        encoding="utf-8")


def _kod() -> str:
    """Yorumsuz betik: `#` ile başlayan satırlar atılır."""
    return "\n".join(s for s in _betik().splitlines()
                     if not s.lstrip().startswith("#"))


def _cron(ad: str) -> str:
    """İş tanımındaki cron ifadesi (tanım tek satır)."""
    esleme = re.search(
        r'ad\s*=\s*"' + re.escape(ad) + r'"[^\n]*?cron\s*=\s*"([^"]+)"',
        _kod())
    assert esleme is not None, f"zamanlayıcı işi bulunamadı: {ad}"
    return esleme.group(1)


def test_rollup_saatlik_ve_gunun_son_kosusu_gece_yarisindan_once():
    """Saatlik (2026-10-17): gecede tek koşu bugünün gelirini panelde ertesi
    geceye kadar göstermiyordu. Dakika payı aynı gerekçeyle duruyor —
    günün SON koşusu 23:MM'de, gece yarısını geçmeden."""
    dakika, saat = _cron("rytho-stats").split()[:2]
    assert saat == "*", "rollup her saat koşmalı"
    # Gece yarısını GEÇEN bir tetik `now().date()`i ertesi güne taşır ve o gün
    # HİÇ yazılmaz. Kalan pay YALNIZ sevk gecikmesi + koşu süresi içindir:
    # betik `--max-retry-attempts` vermiyor, yani düşen koşu yeniden
    # DENENMEZ, bir sonraki günü bekler.
    assert 30 <= int(dakika) <= 50, "gece yarısına pay kalmalı"


def test_temizlik_saati_degismedi():
    """Cleanup 30 gündür kullanılmayan konuşmaları siliyor ve günün olay
    penceresi onları saymıyor — ama iş rollup'ın saatine kaydırılırsa iki
    ağır geçiş çakışır."""
    assert _cron("rytho-cleanup").split()[:2] == ["20", "3"]


def test_isler_utc_ile_kurulur():
    """Saat seçiminin tüm gerekçesi UTC gün penceresi; iş yerel saatle
    kurulsa pencere sessizce kayardı."""
    assert '--time-zone "UTC"' in _betik()


def test_dokuman_kod_ile_ayni_saati_soyluyor():
    """Operatör koşu saatini docs/konsol-gorevleri.md'den okuyor; saat iki
    yerde yazılı olduğu için biri güncellenmeden kalırsa yanlış saatte koşu
    beklenir (ve eksik sayı 'iş kaçmış' sanılır)."""
    belge = (_KOK / "docs" / "konsol-gorevleri.md").read_text(
        encoding="utf-8")
    dakika, saat = _cron("rytho-stats").split()[:2]
    assert saat == "*"
    assert f"her saat :{int(dakika):02d} UTC `rytho-stats`" in belge

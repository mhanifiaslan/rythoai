"""Özellik adları bekçisi: kullanıcıya görünen ad EKRANDAKİ addır.

NEDEN bu bekçi var (ölçüldü 2026-10-23): aynı özellik iki adla
yaşıyordu ve hiçbir test kırmızı değildi —

* progresyon ekranının başlığı ve Atlas kartı Ağustos'tan beri
  "İç mevsim" / "Inner season" (R5-turu), ama Plus faydaları ile ücretsiz
  plan metni, sunucunun Rytho+ uyarısı ve ürün tarifesi "İç Takvim" /
  "Inner Calendar" diyordu;
* doğum heksagramı ekranının başlığı "Doğum Heksagramı" iken Atlas kartı,
  satış metni ve web ana sayfası "Doğum Kapısı" / "Birth Gate" diyordu;
* her yerde "I Ching" yazarken kilitli ekranın başlığı, sunucu uyarısı,
  web ana sayfası ve yönetim paneli "İ Ching" diyordu.

Sahip kuralı (2026-10-23): korpus (RAG'in yedi kitabı) bu ürün adlarını
hiç kullanmıyor — tekniğin adı orada "progression" / "ilerleme" — bu
yüzden ölçüt EKRANDA GÖRÜNEN ADDIR.

Kelimeler başka anlamda meşru ve burada YASAK DEĞİL: küçük harfli
"doğum kapın" / "birth gate" kavramdır (64 kapılı çarktaki kapı), özelliğin
adı değil — ad büyük harfle yazılır ("Doğum Kapısı", "Birth Gate").
Kod yorumları, tarihçe belgeleri ve LLM istemleri kapsam DIŞI: kullanıcı
onları görmez; bekçi yalnız kullanıcıya giden metne bakar.
"""
from __future__ import annotations

import importlib.util
import io
import json
import re
from pathlib import Path

import pytest

from core import messages

_KOK = Path(__file__).resolve().parents[2]

#: Eski adlar. "İç takvim" küçük t'yle de yasak: satış açıklamasında
#: "ilerletilmiş iç takvimin" diye yaşıyordu (ölçüldü).
_YASAK = re.compile(
    r"İç [Tt]akvim|\biç takvim|Inner [Cc]alendar|\binner calendar"
    r"|İ Ching|Doğum Kapısı|Birth Gate")

#: Kartın adı ekran başlığıyla AYNI olmalı — iki anahtar ayrı yaşadığı
#: için ayrışma yeniden doğabilir; bekçi bunu yapısal olarak bağlar.
_KART_EKRAN = (("atlasInnerCalendar", "innerCalendarTitle"),
               ("birthHexagram", "birthHexagramTitle"))


def _oku(yol: str) -> str:
    return io.open(_KOK / yol, encoding="utf-8").read()


def _arb(dil: str) -> dict[str, str]:
    veri = json.loads(_oku(f"apps/mobile/lib/l10n/app_{dil}.arb"))
    return {k: v for k, v in veri.items()
            if not k.startswith("@") and isinstance(v, str)}


def _yorumsuz_html(metin: str) -> str:
    # Bir şeyin yokluğunu arayan bekçi onu anlatan yorumu görmemeli
    # (CLAUDE.md §5).
    return re.sub(r"<!--.*?-->", " ", metin, flags=re.S)


def _js_literalleri(kaynak: str) -> list[tuple[int, str]]:
    # Sözlük bekçisinin ayrıştırıcısı yeniden kullanılır: yorumları ve
    # regex literallerini doğru atladığı orada ölçüldü (test_sozluk).
    yol = Path(__file__).with_name("test_sozluk.py")
    spec = importlib.util.spec_from_file_location("_sozluk_bekcisi", yol)
    modul = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modul)
    return modul._js_literalleri(kaynak)


@pytest.mark.parametrize("dil", ["tr", "en"])
def test_atlas_karti_ekran_basligiyla_ayni_adi_tasir(dil):
    arb = _arb(dil)
    for kart, ekran in _KART_EKRAN:
        assert arb[kart] == arb[ekran], (
            f"app_{dil}.arb: {kart}={arb[kart]!r} ama ekran başlığı "
            f"{ekran}={arb[ekran]!r} — kullanıcıya görünen ad ekrandaki ad")


@pytest.mark.parametrize("dil", ["tr", "en"])
def test_arb_degerlerinde_eski_ozellik_adi_yok(dil):
    ihlaller = [(k, v) for k, v in _arb(dil).items() if _YASAK.search(v)]
    assert not ihlaller, f"app_{dil}.arb eski özellik adı taşıyor: {ihlaller}"


def test_sunucu_mesajlarinda_eski_ozellik_adi_yok():
    ihlaller = [(anahtar, dil, metin)
                for anahtar, diller in messages._MESSAGES.items()
                for dil, metin in diller.items() if _YASAK.search(metin)]
    assert not ihlaller, f"core.messages eski özellik adı taşıyor: {ihlaller}"


@pytest.mark.parametrize("sayfa", [
    "web/index.html", "web/en/index.html",
    "web/legal/gizlilik.html", "web/en/legal/privacy.html",
])
def test_web_sayfalarinda_eski_ozellik_adi_yok(sayfa):
    bulunan = _YASAK.findall(_yorumsuz_html(_oku(sayfa)))
    assert not bulunan, f"{sayfa} eski özellik adı taşıyor: {bulunan}"


def test_yonetim_paneli_dizelerinde_eski_ozellik_adi_yok():
    ihlaller = []
    for js in sorted((_KOK / "web/rytho-admin").rglob("*.js")):
        for satir, metin in _js_literalleri(js.read_text(encoding="utf-8")):
            if _YASAK.search(metin):
                ihlaller.append((js.relative_to(_KOK).as_posix(), satir, metin))
    assert not ihlaller, f"yönetim paneli eski özellik adı taşıyor: {ihlaller}"


def test_urun_tarifesinde_eski_ozellik_adi_yok():
    # `docs/ozellikler.md` koddan sapmamalı (CLAUDE.md §8): tarifede başka
    # ad yazarsa sahibin okuduğu ürün ile kullanıcının gördüğü ayrışır.
    bulunan = _YASAK.findall(_oku("docs/ozellikler.md"))
    assert not bulunan, f"docs/ozellikler.md eski özellik adı taşıyor: {bulunan}"


def test_taramanin_DISI_var():
    """Taban: yasak kalıp gerçekten eşleşiyor ve kavram kullanımı muaf.
    Yoksa tarama kördür ve 'ihlal yok' hiçbir şey ölçmez."""
    for eski in ("İç Takvim", "ilerletilmiş iç takvimin", "Inner Calendar",
                 "İ Ching", "Doğum Kapısı", "the Birth Gate"):
        assert _YASAK.search(eski), eski
    for kavram in ("64 kapı çarkındaki doğum kapın", "Doğum kapımı açtım",
                   "I've opened my birth gate", "I Ching", "İç mevsim"):
        assert not _YASAK.search(kavram), kavram

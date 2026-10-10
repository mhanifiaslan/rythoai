r"""Yayındaki HTML'de geliştirici yorumu kalmaz — bekçi.

NEDEN (ölçüldü 2026-10-10): herkese açık sayfalar onlarca satır geliştirici
gerekçesi taşıyordu — `web/index.html` 25 satırlık tek blokta dört
`.dart`/`.py` dosya adı, `web/ortaklik.html` 19 blok / 60 satır,
`web/r/index.html` bayat bir satır numarası (`paywall_screen.dart:329`
diyordu; o satır bir fayda satırının Row düzeni, kod girme kararı 429'da).
"Kaynağı görüntüle" diyen herkes iç dosya adlarını, satır numaralarını ve
"bu kapı ağaçta henüz yoktu" türü ölçüm notlarını okuyordu. Satır
numaraları ayrıca TAŞINIR: HTML'deki `:329` yazıldığı gün bile doğru
olmayabilir, altı ay sonra kesin yanlış.

Karar: gerekçe metni KAYBOLMAZ, `docs/web-notlari.md`'ye taşınır (sayfa ve
bölüm başlığıyla); HTML'de yalnız tek satırlık işaretler kalır
(`<!-- ---------- X ---------- -->` ya da docs'a işaret eden tek satır).
Derleme adımı BİLEREK yok: hosting kökü `web/`, `test_web_seo` yolları ve
Search Console doğrulama dosyası (53 bayt, birebir) taşınmasın.

İki iddia, iki yöne:

* yorum TEK SATIR — çok satırlı blok, gerekçe metninin geri sızdığının
  işaretidir;
* yorum kaynak dosyası (`.dart .py .js .ps1`) ya da `:satır` anmaz —
  tek satıra sığdırılmış bir "bkz. foo.py:12" de aynı sızıntı.

Kapsam `test_honesty.TestPazarlamaDili._SAYFALAR` (15 sayfa); liste
kopyalanmıyor, tamlığını orası kanıtlıyor. Bu turda dokunulmayan sayfalar
`_BASKA_TURDA` ile STRICT xfail: bugün kirli oldukları ölçüldü,
temizlendikleri gün XPASS(strict) kırmızı döner ve girdi silinir — kalıcı
muafiyet değil, sırası gelmemiş borç.

JS yorumları (`//`, `/* */`) kapsam DIŞI ve bu bilinçli: `web/r/` sayfasının
JS gerekçeleri `test_web_seo._r_sayfasi_kodu` ile ölçülen sıranın
açıklaması, ve o yardımcı yorumları zaten atarak ölçüyor.
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import sys

import pytest

_KOK = pathlib.Path(__file__).resolve().parents[2]


def _honesty():
    """`test_honesty` modülü — sayfa listesi oradan (test_sozluk ile aynı yol)."""
    try:
        import test_honesty
        return test_honesty
    except ImportError:
        yol = pathlib.Path(__file__).with_name("test_honesty.py")
        spec = importlib.util.spec_from_file_location("test_honesty", yol)
        mod = importlib.util.module_from_spec(spec)
        sys.modules["test_honesty"] = mod
        spec.loader.exec_module(mod)
        return mod


_SAYFALAR: tuple[str, ...] = tuple(_honesty().TestPazarlamaDili._SAYFALAR)

#: Bu turda DOKUNULMAYAN sayfalar — başka turun/ajanın dosyaları. Kirli
#: oldukları ÖLÇÜLDÜ (2026-10-10). STRICT xfail: dosya temizlendiği gün
#: bu testler XPASS(strict) ile kırmızı döner ve girdi buradan silinir.
#: Dalga kapanışında (2026-10-10) iki sayfa da temizlendi; mekanizma
#: yarın başka bir sayfa kirli ölçülürse diye duruyor.
_BASKA_TURDA: dict[str, str] = {}


def _parametreler():
    return [
        pytest.param(y, marks=pytest.mark.xfail(
            strict=True, reason=f"bu turda dokunulmadı: {_BASKA_TURDA[y]}"))
        if y in _BASKA_TURDA else y
        for y in _SAYFALAR
    ]


_YORUM = re.compile(r"<!--(.*?)-->", re.S)

#: Kaynak dosyası uzantısı ya da `:satır` — iki ayrı sızıntı biçimi.
#: `.md` BİLEREK listede yok: işaret yorumları `docs/web-notlari.md`'ye
#: gönderiyor, gerekçenin yeni adresi o.
_KAYNAK_IZI = re.compile(r"\.(?:dart|py|js|ps1)\b|:\d+")


def _yorumlar(metin: str) -> list[tuple[int, str]]:
    """(başladığı satır, gövde) — hata mesajı satır göstersin diye."""
    return [(metin[:m.start()].count("\n") + 1, m.group(1))
            for m in _YORUM.finditer(metin)]


@pytest.mark.parametrize("yol", _parametreler())
def test_yorumlar_tek_satir(yol: str):
    metin = (_KOK / yol).read_text(encoding="utf-8")
    cok = [(no, g.strip().split("\n")[0][:60]) for no, g in _yorumlar(metin)
           if "\n" in g]
    assert not cok, (
        f"{yol}: çok satırlı HTML yorumu — gerekçe metni herkese açık "
        f"kaynağa geri sızmış. docs/web-notlari.md'ye taşı, yerine tek "
        f"satırlık işaret bırak:\n  "
        + "\n  ".join(f"satır {no}: {g!r}…" for no, g in cok))


@pytest.mark.parametrize("yol", _parametreler())
def test_yorumlar_kaynak_dosyasi_ve_satir_anmaz(yol: str):
    metin = (_KOK / yol).read_text(encoding="utf-8")
    iz = [(no, _KAYNAK_IZI.search(g).group(0), g.strip()[:60])
          for no, g in _yorumlar(metin) if _KAYNAK_IZI.search(g)]
    assert not iz, (
        f"{yol}: HTML yorumu kaynak dosyası ya da satır numarası anıyor — "
        f"iç yapı herkese açık, satır numarası yarın bayat:\n  "
        + "\n  ".join(f"satır {no}: {bul!r} içinde {g!r}" for no, bul, g in iz))


def test_bekcinin_DISI_var():
    """Ayırıcı işaret yorumunu geçirir, dört sızıntı biçimini yakalar.

    Bu test olmasa "15 sayfada ihlal yok" iki sebeple doğru çıkabilir:
    sayfalar temiz olduğu için, ya da `_YORUM` hiçbir yorumu bulmadığı
    için.
    """
    ornek = ("<!-- ---------- HERO ---------- -->\n"
             "<!-- gerekçe docs/web-notlari.md §Hero -->\n"
             "<!-- iki\nsatır -->\n"
             "<!-- bkz. hesap.py -->\n"
             "<!-- paywall:329 -->\n"
             "<!-- hero.js okur -->\n"
             "<!-- betik.ps1 -->\n"
             "<!-- ekran.dart -->")
    yorumlar = _yorumlar(ornek)
    assert len(yorumlar) == 8
    assert [no for no, g in yorumlar if "\n" in g] == [3]
    assert [no for no, g in yorumlar if _KAYNAK_IZI.search(g)] == [5, 6, 7, 8, 9]


def test_baska_turda_listesi_taranan_sayfalari_gosteriyor():
    """Muafiyet taranmayan bir dosyaya işaret ederse ölü kalır ve kimse
    fark etmez; taşınan/silinen dosya için de aynısı."""
    for yol in _BASKA_TURDA:
        assert yol in _SAYFALAR, f"{yol} 15 sayfalık listede değil"
        assert (_KOK / yol).exists(), f"{yol} yok"

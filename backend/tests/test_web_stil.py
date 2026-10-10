r"""Web stil sözleşmesi — hepsi SESSİZ bozulan şeyler.

Beş iddia; her biri 2026-10-10'da ölçülmüş bir kusurdan doğdu:

1. **Çıplak renk yok.** `rytho.css` üçüncü satırı "sayfalar çıplak renk
   yazmaz" diyordu; `:root` dışında 12 çıplak hex vardı (hero dibi, maket
   çerçeveleri, küre, indirme bandı). Dört küçük sayfa (davet, ortak
   bağlantısı, hesap işlemi, 404) rytho.css'i HİÇ yüklemiyor ve 49 çıplak
   hex ile ESKİ paleti çiziyordu; not metinleri 12 px ve zeminde 3,97:1
   (AA eşiği 4,5). Dört sayfanın tek bir kabuğa bağlı olduğu, ancak bir
   bekçi varken doğru kalır.
2. **Satır içi stil yalnız kademe değişkeni.** Ana sayfa 47 `style=`
   taşıyordu (9'u `--i:N` dışında), ortaklık 39/11. Satır içi değer
   token'ı atlar: `border-color:rgba(183,156,255,.3)` hiçbir değişkene
   bağlı değildi.
3. **Yazı tipi bağlantısı render'ı kilitlemez.** Google Fonts `<link>`'i
   düz `rel="stylesheet"` idi: CSS inene kadar ilk boya bekler.
   `media="print"` + `onload` deseni ve `<noscript>` yedeği.
4. **Dokunma hedefleri 44 px.** Hamburger 40×40, küçük düğme 40 px,
   hesap işlemi "göster" düğmesi 12,5 px metin + 6/8 dolgu; şifre girdisi
   15 px (iOS Safari 16 px altını odakta yakınlaştırır, geri almaz).
5. **CTA kontrastı AA.** Beyaz metin `.buton`un `--primary-gradient`
   magenta ucunda 3,36:1. Uygulama aynı ölçümle `ctaGradient`e geçmişti
   (her durak ≥ 4,6), web geçmemişti. `--cta-gradient` o degradenin aynası;
   durakları buradaki formülle yeniden ölçülüyor.

Ortak yan: bozulduklarında hiçbir yerde hata görünmez — derleme yok,
deploy yeşil, sayfa açılıyor. Fark yalnız gözle ya da bir ekran
okuyucuyla ölçülür.

Kapsam `test_honesty.TestPazarlamaDili._SAYFALAR` (15 sayfa) + rytho.css.
Bu turda dokunulmayan sayfalar STRICT xfail: kirli oldukları ölçüldü,
temizlendikleri gün XPASS kırmızı döner ve girdi silinir.

Yorumlar eşleşmeden ÖNCE atılır — bir şeyin YOKLUĞUNU arayan bekçi, onu
ANLATAN yorumu görmemeli (CLAUDE.md §5; `.rozet.yakinda` yorumu `href="#"`
diyor, token yorumları eski hex değerleri anıyor).
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import sys

import pytest

_KOK = pathlib.Path(__file__).resolve().parents[2]
_WEB = _KOK / "web"
_CSS = _WEB / "assets" / "rytho.css"


def _honesty():
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

#: Bu turda DOKUNULMAYAN sayfalar, iddia başına. Ölçüldü 2026-10-10.
#: Dalga kapanışında (2026-10-10) iki sayfa da temizlendi; sözlükler boş
#: ama mekanizma duruyor (yarın kirli ölçülen sayfa buraya girer).
_BASKA_TURDA_SATIR_ICI: dict[str, str] = {}
_BASKA_TURDA_FONT: dict[str, str] = {}


def _param(sozluk: dict[str, str]):
    return [
        pytest.param(y, marks=pytest.mark.xfail(
            strict=True, reason=f"bu turda dokunulmadı: {sozluk[y]}"))
        if y in sozluk else y
        for y in _SAYFALAR
    ]


# ---------------------------------------------------------------------------
# (1) Çıplak renk
# ---------------------------------------------------------------------------

#: 3/4/6/8 haneli hex; `\b` ile biter ki `#7B2FF7`nin ilk üçü ayrı
#: eşleşmesin. HTML çapaları (`#neler-var`, `#faq`) hex olmayan harf
#: taşıdığı için yakalanmaz; bekçi zaten yalnız CSS görünümüne bakıyor.
_HEX = re.compile(r"#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}"
                  r"|[0-9a-fA-F]{8})\b")
_CSS_YORUM = re.compile(r"/\*.*?\*/", re.S)


def _bosalt(metin: str, i: int, j: int) -> str:
    """[i, j) aralığını boşluğa çevirir, SATIR SAYISINI korur."""
    return metin[:i] + re.sub(r"[^\n]", " ", metin[i:j]) + metin[j:]


def _root_disi(css: str) -> str:
    """`:root { … }` bloklarını boşaltır — token tanımları hex'in tek
    meşru yeri. Süslü parantez sayarak: `:root { color-scheme: dark; }`
    tek satır, `rytho.css`inki 60 satır."""
    while True:
        i = css.find(":root")
        if i < 0:
            return css
        j = css.index("{", i)
        derinlik, k = 1, j + 1
        while derinlik:
            if css[k] == "{":
                derinlik += 1
            elif css[k] == "}":
                derinlik -= 1
            k += 1
        css = _bosalt(css, i, k)


def _maskesiz(css: str) -> str:
    """`mask` satırları boşaltılır: maskedeki `#000` bir palet rengi değil,
    alfa kanalı (hero video penceresinin kenarı)."""
    return "\n".join(re.sub(r"[^\n]", " ", s) if "mask" in s else s
                     for s in css.split("\n"))


def _css_gorunumu(sayfa: str) -> str:
    """Sayfanın yalnız CSS'i: `<style>` gövdeleri ve `style=""` değerleri;
    gerisi boşluk, satır sayısı korunur."""
    tut = bytearray(len(sayfa))
    for m in re.finditer(r"<style[^>]*>(.*?)</style>", sayfa, re.S):
        tut[m.start(1):m.end(1)] = b"\x01" * (m.end(1) - m.start(1))
    for m in re.finditer(r'style="([^"]*)"', sayfa):
        tut[m.start(1):m.end(1)] = b"\x01" * (m.end(1) - m.start(1))
    return "".join(c if (tut[i] or c == "\n") else " "
                   for i, c in enumerate(sayfa))


def _temiz_css(css: str) -> str:
    yorumsuz = _CSS_YORUM.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), css)
    return _maskesiz(_root_disi(yorumsuz))


def _hexler(css: str) -> list[tuple[int, str]]:
    return [(css[:m.start()].count("\n") + 1, m.group(0))
            for m in _HEX.finditer(css)]


def test_rytho_css_root_disinda_ciplak_renk_yok():
    css = _CSS.read_text(encoding="utf-8")
    # Taban: token katmanı gerçekten hex tanımlıyor — yoksa "dışarıda hex
    # yok" hiçbir şey ölçmez (palet başka dosyaya taşınmış olabilir).
    kok = re.search(r":root\s*\{", css)
    assert kok, "rytho.css'te :root yok"
    assert len(_HEX.findall(css[kok.start():])) >= 20, (
        "rytho.css :root içinde beklenenden az hex — palet taşındıysa bekçi "
        "de taşınır")
    bulunan = _hexler(_temiz_css(css))
    assert not bulunan, (
        "rytho.css :root DIŞINDA çıplak renk — :root'a token olarak ekle, "
        "yerinde var(--…) kullan:\n  "
        + "\n  ".join(f"satır {no}: {h}" for no, h in bulunan))


@pytest.mark.parametrize("yol", _SAYFALAR)
def test_sayfanin_kendi_css_inde_ciplak_renk_yok(yol: str):
    sayfa = (_KOK / yol).read_text(encoding="utf-8")
    bulunan = _hexler(_temiz_css(_css_gorunumu(sayfa)))
    assert not bulunan, (
        f"{yol}: sayfa içi CSS çıplak renk yazıyor — rytho.css token'ı "
        f"(var(--…)) kullanılmalı; token yoksa :root'a eklenir:\n  "
        + "\n  ".join(f"satır {no}: {h}" for no, h in bulunan))


def test_ciplak_renk_bekcisinin_DISI_var():
    """Yorumdaki, :root'taki ve maskedeki hex sayılmaz; gövdedeki sayılır;
    HTML çapası ve rgba hiç eşleşmez."""
    ornek = ("<a href=\"#faq\">x</a>\n"
             "<style>\n"
             ":root { --a: #ABCDEF; }\n"
             "/* eski değer #123456 */\n"
             ".x { mask-image: radial-gradient(#000 0 99%, transparent); }\n"
             ".y { color: #fff; background: rgba(1, 2, 3, 0.4); }\n"
             "</style>\n"
             "<p style=\"color:#123\">y</p>")
    assert _hexler(_temiz_css(_css_gorunumu(ornek))) == [(6, "#fff"), (8, "#123")]


# ---------------------------------------------------------------------------
# (2) Satır içi stil
# ---------------------------------------------------------------------------

_KADEME = re.compile(r"^--i:\d+$")


@pytest.mark.parametrize("yol", _param(_BASKA_TURDA_SATIR_ICI))
def test_satir_ici_stil_yalniz_kademe_degiskeni(yol: str):
    sayfa = (_KOK / yol).read_text(encoding="utf-8")
    assert "style='" not in sayfa, f"{yol}: tek tırnaklı style= — bekçi çift tırnak arıyor"
    sapma = [(sayfa[:m.start()].count("\n") + 1, m.group(1))
             for m in re.finditer(r'style="([^"]*)"', sayfa)
             if not _KADEME.match(m.group(1).strip())]
    assert not sapma, (
        f"{yol}: satır içi stil yalnız kademe değişkeni (--i:N) taşır; "
        f"gerisi rytho.css'te bir sınıf olur (.panel.vurgulu, .not-kucuk, "
        f".bolum-bas gibi):\n  "
        + "\n  ".join(f"satır {no}: style=\"{s}\"" for no, s in sapma))


# ---------------------------------------------------------------------------
# (3) Yazı tipi bağlantısı
# ---------------------------------------------------------------------------

_FONT_LINK = re.compile(r"<link[^>]*fonts\.googleapis\.com/css2[^>]*>")


@pytest.mark.parametrize("yol", _param(_BASKA_TURDA_FONT))
def test_yazi_tipi_baglantisi_renderi_kilitlemez(yol: str):
    sayfa = (_KOK / yol).read_text(encoding="utf-8")
    noscript = [(m.start(), m.end())
                for m in re.finditer(r"<noscript>.*?</noscript>", sayfa, re.S)]
    linkler = list(_FONT_LINK.finditer(sayfa))
    assert linkler, (
        f"{yol}: Google Fonts bağlantısı yok — sayfa kabuğa bağlı değil ya da "
        f"kalıp değişti (bekçi kör)")
    canli = [m for m in linkler
             if not any(a <= m.start() < b for a, b in noscript)]
    yedek = [m for m in linkler if any(a <= m.start() < b for a, b in noscript)]
    assert canli, f"{yol}: fonts bağlantısı yalnız <noscript> içinde"
    for m in canli:
        assert 'media="print"' in m.group(0) and "onload=" in m.group(0), (
            f"{yol}: Google Fonts bağlantısı render'ı kilitliyor — "
            f'media="print" onload="this.media=\'all\'" deseni bekleniyor')
    assert yedek, f"{yol}: JS kapalıyken yazı tipi yüklenmez — <noscript> yedeği yok"

    def adres(m: re.Match) -> str:
        return re.search(r'href="([^"]+)"', m.group(0)).group(1)

    assert {adres(m) for m in canli} == {adres(m) for m in yedek}, (
        f"{yol}: canlı ve noscript yazı tipi adresleri farklı")


# ---------------------------------------------------------------------------
# (4) Dokunma hedefleri
# ---------------------------------------------------------------------------

def _blok(css: str, secici: str) -> str:
    m = re.search(re.escape(secici) + r"\s*\{([^}]*)\}", css)
    assert m, f"CSS'te {secici!r} bloğu yok"
    return m.group(1)


def _px(blok: str, ozellik: str) -> float:
    m = re.search(ozellik + r"\s*:\s*([\d.]+)px", blok)
    assert m, f"blokta {ozellik} yok: {blok.strip()[:80]!r}"
    return float(m.group(1))


def test_dokunma_hedefleri_44px():
    css = _CSS.read_text(encoding="utf-8")
    hamburger = _blok(css, ".mobil-menu summary")
    assert _px(hamburger, "width") >= 44 and _px(hamburger, "height") >= 44, (
        "hamburger 44×44 altında (eskiden 40×40)")
    assert _px(_blok(css, ".buton.kucuk"), "min-height") >= 44, (
        ".buton.kucuk min-height 44 altında (eskiden 40)")
    assert _px(_blok(css, ".dil-sec"), "min-height") >= 44, (
        ".dil-sec (EN/TR pili) min-height 44 altında")

    auth = (_WEB / "auth" / "action" / "index.html").read_text(encoding="utf-8")
    toggle = _blok(auth, ".toggle")
    assert _px(toggle, "min-width") >= 44 and _px(toggle, "min-height") >= 44, (
        'hesap işlemi "göster" düğmesi 44×44 altında')
    girdi = _blok(auth, 'input[type="password"], input[type="text"]')
    assert _px(girdi, "font-size") >= 16, (
        "şifre girdisi 16 px altında — iOS Safari odakta sayfayı yakınlaştırır "
        "ve geri almaz")


# ---------------------------------------------------------------------------
# (5) CTA kontrastı
# ---------------------------------------------------------------------------

def _parlaklik(hex6: str) -> float:
    r, g, b = (int(hex6[i:i + 2], 16) / 255 for i in (1, 3, 5))

    def dogrusal(c: float) -> float:
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * dogrusal(r) + 0.7152 * dogrusal(g) + 0.0722 * dogrusal(b)


def _kontrast(a: str, b: str) -> float:
    la, lb = _parlaklik(a), _parlaklik(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def test_kontrast_formulunun_DISI_var():
    """Formül WCAG'ın kendisi; iki bilinen değerle sınanır — uygulamanın
    kendi ölçümüyle aynı sayılar (3,36 ve 5,85)."""
    assert round(_kontrast("#FFFFFF", "#E64ACF"), 2) == 3.36
    assert round(_kontrast("#FFFFFF", "#7B2FF7"), 2) == 5.85


def test_cta_degradesinin_her_duragi_AA():
    css = _CSS.read_text(encoding="utf-8")
    metin = re.search(r"--on-gradient:\s*(#[0-9A-Fa-f]{6})", css)
    degrade = re.search(r"--cta-gradient:\s*linear-gradient\(([^)]*)\)", css)
    assert metin and degrade, "rytho.css'te --on-gradient / --cta-gradient yok"
    duraklar = re.findall(r"#[0-9A-Fa-f]{6}", degrade.group(1))
    assert len(duraklar) >= 2, "cta degradesinde en az iki durak bekleniyor"
    for d in duraklar:
        oran = _kontrast(metin.group(1), d)
        assert oran >= 4.5, (
            f"--cta-gradient durağı {d}: {metin.group(1)} üstünde {oran:.2f}:1, "
            f"AA 4,5 ister. Metin taşıyan düğme bu degradeyi kullanıyor; "
            f"primary-gradient'in magenta ucu tam bu yüzden dışarıda (3,36)")
    # Ters yön: düğme gerçekten bu degradeyi KULLANIYOR. Token doğru olup
    # düğme primary'ye dönerse kontrast yine 3,36'ya düşer, yukarısı yeşil
    # kalırdı.
    for secici in (".buton", ".gezinti .mobil-menu-panel .mobil-menu-cta"):
        blok = _blok(css, secici)
        assert "var(--cta-gradient)" in blok, f"{secici} --cta-gradient kullanmıyor"
        assert "var(--on-gradient)" in blok, f"{secici} metin rengi --on-gradient değil"

r"""Web görsel varlık bütçesi — ağırlık SESSİZ büyür, bekçi.

NEDEN (ölçüldü 2026-10-10): ana sayfa 9 PNG + 1 MP4 ile ~15,6 MB görsel
taşıyordu; WebP, srcset ve `<picture>` hiç yoktu. hero-nebula.png (1,11 MB)
her genişlikte yüksek öncelikle preload ediliyor, beş gezegen PNG'si
(7,73 MB, 1024²) 112 px'lik kürelerde çiziliyor, video (4,42 MB)
`preload="auto"` taşıyordu. Hiçbiri bir yerde kırmızı görünmez: sayfa
açılır, deploy yeşil, derleme yok.

Üretici `tools/web_gorsel_optimize.py` (Pillow). Bu bekçi üç şeyi bağlar:

1. **Tavan.** HTML'in referans verdiği her görsel diskte var; tek dosya
   ≤ 300 KB, sayfa toplamı ≤ 3 MB. PNG yalnız WebP `<source>` taşıyan bir
   `<picture>`ın `<img>` yedeğiyse SAYILMAZ (WebP çözen tarayıcı onu hiç
   çekmez). Hero PNG'si mobil preload olarak sayılır ve tavanı aşıyor —
   STRICT xfail, gerekçesi `_TAVAN_DISI`'nda.
2. **Eşleştirme.** Her PNG `<img>` WebP `<source>` taşıyan bir `<picture>`
   içinde; adaylar PNG'nin gövdesini paylaşıyor ve `-1x`/`-2x` eki srcset
   tanımlayıcısıyla aynı. Bir `<source>` silinirse sayfa sessizce PNG'ye
   döner, görünürde hiçbir şey bozulmaz.
3. **Köken.** Her WebP, diskteki PNG'den ve aracın BUGÜNKÜ sabitleriyle
   üretilmiş (EXIF damgası, SHA-256). Ekran görüntüsü yeniden yakalanıp
   araç koşulmazsa site ESKİ ekranı gösterir; kalite sabiti değişip araç
   koşulmazsa docstring'deki sayılar yalan olur. Git mtime taşımadığı
   için bu damgasız ölçülemez.

Hero'nun iki tüketicisi iki preload'a bağlı: ≤980 px preload'u CSS'in
arka plan dosyasıyla, ≥981 px preload'u video posteriyle AYNI dosya olmak
zorunda. Ayrışırlarsa aynı görsel iki kez iner ve bunu yalnız ağ sekmesi
gösterir.

Yorumlar eşleşmeden ÖNCE atılır — bir şeyin YOKLUĞUNU arayan bekçi onu
ANLATAN yorumu görmemeli (CLAUDE.md §5).
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
from dataclasses import dataclass

import pytest

_KOK = pathlib.Path(__file__).resolve().parents[2]
_WEB = _KOK / "web"
_CSS = _WEB / "assets" / "rytho.css"
_ARAC = _KOK / "tools" / "web_gorsel_optimize.py"

#: Görsel taşıyan iki sayfa; gerisi (hukuk, davet, 404…) yalnız SVG logo.
_SAYFALAR = ("web/index.html", "web/en/index.html")

#: Tavanlar. 300 KB: en büyük WebP (shot-5-chat-2x, 116 KB) üç kat pay
#: bırakıyor; bir ekran görüntüsü yeniden yakalanıp PNG olarak girerse
#: (660 KB–1,29 MB ölçüldü) yakalanır. 3 MB: ölçülen toplam ~1,73 MB
#: (hero PNG 925 KB dâhil).
_TEK_GORSEL_TAVAN = 300 * 1024
_SAYFA_TAVAN = 3 * 1024 * 1024

_RASTER = {".png", ".webp", ".jpg", ".jpeg", ".avif", ".gif"}
_VIDEO = {".mp4", ".webm"}

#: Tek-dosya tavanını AŞTIĞI ölçülen ve bu turda düşürülemeyen dosya.
#: STRICT xfail: referanstan düştüğü gün `test_tavan_disi_listesi_…`
#: kırmızı döner ve girdi silinir — kalıcı muafiyet değil.
#: Boş (2026-10-10): hero PNG artık yalnız image-set anlamayan tarayıcının
#: yedeği; CSS image-set(webp) + mobil preload webp ile referanstan düştü.
#: Mekanizma duruyor — tavanı bilerek aşan bir dosya gerekçesiyle buraya girer.
_TAVAN_DISI: dict[str, str] = {}


def _yorumsuz(metin: str) -> str:
    """HTML yorumlarını boşluğa çevirir, SATIR SAYISINI korur."""
    return re.sub(r"<!--.*?-->",
                  lambda m: re.sub(r"[^\n]", " ", m.group(0)), metin, flags=re.S)


def _css_yorumsuz(css: str) -> str:
    return re.sub(r"/\*.*?\*/",
                  lambda m: re.sub(r"[^\n]", " ", m.group(0)), css, flags=re.S)


def _nitelikler(govde: str) -> dict[str, str]:
    return dict(re.findall(r'([a-zA-Z-]+)="([^"]*)"', govde))


def _adaylar(srcset: str) -> list[list[str]]:
    """`srcset` → [[url, tanımlayıcı?], …]."""
    return [p.strip().split() for p in srcset.split(",") if p.strip()]


def _disk(yol: str) -> pathlib.Path:
    return _WEB / yol.split("?", 1)[0].split("#", 1)[0].lstrip("/")


@dataclass(frozen=True)
class Ref:
    satir: int
    yol: str
    etiket: str
    #: Bütçeye girer mi — WebP yedeği olan PNG girmez.
    sayilir: bool


_ETIKET = re.compile(r"<(img|source|link|video)\b([^>]*)>")
_PICTURE = re.compile(r"<picture>(.*?)</picture>", re.S)


def _referanslar(metin: str) -> list[Ref]:
    metin = _yorumsuz(metin)
    pictures = [(m.start(), m.end(), m.group(1)) for m in _PICTURE.finditer(metin)]
    refs: list[Ref] = []
    for m in _ETIKET.finditer(metin):
        etiket, n = m.group(1), _nitelikler(m.group(2))
        satir = metin[:m.start()].count("\n") + 1
        if etiket == "img" and "src" in n:
            webp_yedek = any(a <= m.start() < b and 'type="image/webp"' in g
                             for a, b, g in pictures)
            refs.append(Ref(satir, n["src"], "img",
                            not (webp_yedek and n["src"].endswith(".png"))))
        elif etiket == "source":
            if "srcset" in n:
                refs += [Ref(satir, a[0], "source", True) for a in _adaylar(n["srcset"])]
            elif "src" in n:
                refs.append(Ref(satir, n["src"], "video-source", True))
        elif etiket == "link" and n.get("rel") == "preload" and n.get("as") == "image":
            if "imagesrcset" in n:
                refs += [Ref(satir, a[0], "preload", True)
                         for a in _adaylar(n["imagesrcset"])]
            if "href" in n:
                refs.append(Ref(satir, n["href"], "preload", True))
        elif etiket == "video" and "poster" in n:
            refs.append(Ref(satir, n["poster"], "poster", True))
    return refs


def _sayfa(yol: str) -> str:
    return (_KOK / yol).read_text(encoding="utf-8")


def _uzanti(yol: str) -> str:
    return pathlib.PurePosixPath(yol.split("?", 1)[0]).suffix.lower()


def _arac():
    """Üretici betik — hedef listesi ve damga çözücü oradan, kopyalanmaz."""
    spec = importlib.util.spec_from_file_location("web_gorsel_optimize", _ARAC)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------
# (1) Tavan
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("yol", _SAYFALAR)
def test_her_referans_diskte_var(yol: str):
    eksik = [(r.satir, r.yol) for r in _referanslar(_sayfa(yol))
             if _uzanti(r.yol) in _RASTER | _VIDEO and not _disk(r.yol).is_file()]
    assert not eksik, (
        f"{yol}: sayfa olmayan dosyaya işaret ediyor — tarayıcı 404 alır, "
        f"<picture> sessizce PNG'ye düşer:\n  "
        + "\n  ".join(f"satır {s}: {d}" for s, d in eksik))


def _tavan_parametreleri():
    params = []
    for yol in _SAYFALAR:
        dosyalar = sorted({r.yol for r in _referanslar(_sayfa(yol))
                           if r.sayilir and _uzanti(r.yol) in _RASTER})
        for d in dosyalar:
            if d in _TAVAN_DISI:
                params.append(pytest.param(yol, d, marks=pytest.mark.xfail(
                    strict=True, reason=_TAVAN_DISI[d])))
            else:
                params.append(pytest.param(yol, d))
    return params


@pytest.mark.parametrize(("yol", "dosya"), _tavan_parametreleri())
def test_tek_gorsel_tavani(yol: str, dosya: str):
    boyut = _disk(dosya).stat().st_size
    assert boyut <= _TEK_GORSEL_TAVAN, (
        f"{yol} → {dosya}: {boyut:,} B > {_TEK_GORSEL_TAVAN:,} B. PNG ise "
        f"<picture> + WebP ister (tools/web_gorsel_optimize.py); WebP ise "
        f"kaynak boyutu ya da kalite yeniden ölçülmeli")


@pytest.mark.parametrize("yol", _SAYFALAR)
def test_sayfa_toplami_tavani(yol: str):
    dosyalar = sorted({r.yol for r in _referanslar(_sayfa(yol))
                       if r.sayilir and _uzanti(r.yol) in _RASTER})
    # Taban: sayfa gerçekten görsel taşıyor — sıfır dosya "bütçe tutuyor"
    # diye yeşil döner ve hiçbir şey ölçmez.
    assert len(dosyalar) >= 10, f"{yol}: yalnız {len(dosyalar)} görsel sayıldı"
    toplam = sum(_disk(d).stat().st_size for d in dosyalar)
    assert toplam <= _SAYFA_TAVAN, (
        f"{yol}: sayılan görsel toplamı {toplam:,} B > {_SAYFA_TAVAN:,} B "
        f"({len(dosyalar)} dosya; WebP yedeği olan PNG'ler sayılmadı)")


# ---------------------------------------------------------------------------
# (2) Eşleştirme: PNG <img> ↔ WebP <source>
# ---------------------------------------------------------------------------

_IMG_PNG = re.compile(r'<img\b[^>]*\bsrc="([^"]+\.png)"[^>]*>')


@pytest.mark.parametrize("yol", _SAYFALAR)
def test_png_img_webp_kaynakli_picture_icinde(yol: str):
    metin = _yorumsuz(_sayfa(yol))
    pictures = [(m.start(), m.end(), m.group(1)) for m in _PICTURE.finditer(metin)]
    imgler = list(_IMG_PNG.finditer(metin))
    assert imgler, f"{yol}: PNG <img> yok — bekçi kör mü, sayfa mı değişti?"
    sapma = []
    for m in imgler:
        satir = metin[:m.start()].count("\n") + 1
        png = m.group(1)
        kap = next((g for a, b, g in pictures if a <= m.start() < b), None)
        if kap is None:
            sapma.append(f"satır {satir}: {png} <picture> dışında")
            continue
        kaynaklar = [n for t, n in ((t, _nitelikler(a)) for t, a in _ETIKET.findall(kap))
                     if t == "source" and n.get("type") == "image/webp"]
        if len(kaynaklar) != 1 or "srcset" not in kaynaklar[0]:
            sapma.append(f"satır {satir}: {png} için tek bir WebP <source srcset> yok")
            continue
        govde = png[:-4]
        adaylar = _adaylar(kaynaklar[0]["srcset"])
        beklenen = {f"{govde}-1x.webp": "1x", f"{govde}-2x.webp": "2x"}
        gorulen = {a[0]: (a[1] if len(a) > 1 else "") for a in adaylar}
        if gorulen != beklenen:
            sapma.append(f"satır {satir}: {png} adayları {gorulen} ≠ {beklenen}")
    assert not sapma, (
        f"{yol}: PNG <img> WebP kaynağıyla eşleşmiyor — tarayıcı sessizce "
        f"PNG'yi (0,66–1,70 MB) çeker:\n  " + "\n  ".join(sapma))


# ---------------------------------------------------------------------------
# (3) Video: preload="none", poster WebP, MP4 yalnız geniş ekranda
# ---------------------------------------------------------------------------

_VIDEO_ETIKETI = re.compile(r"<video\b([^>]*)>(.*?)</video>", re.S)


def _video(yol: str) -> tuple[dict[str, str], dict[str, str]]:
    """(video nitelikleri, mp4 <source> nitelikleri) — tek video var."""
    metin = _yorumsuz(_sayfa(yol))
    videolar = list(_VIDEO_ETIKETI.finditer(metin))
    assert len(videolar) == 1, f"{yol}: {len(videolar)} <video> — bekçi tek video varsayıyor"
    v = _nitelikler(videolar[0].group(1))
    kaynaklar = [_nitelikler(a) for t, a in _ETIKET.findall(videolar[0].group(2))
                 if t == "source"]
    assert len(kaynaklar) == 1, f"{yol}: video {len(kaynaklar)} <source> taşıyor"
    return v, kaynaklar[0]


@pytest.mark.parametrize("yol", _SAYFALAR)
def test_video_preload_none_poster_webp(yol: str):
    v, _ = _video(yol)
    assert v.get("preload") == "none", (
        f"{yol}: video preload={v.get('preload')!r} — 4,42 MB'lık MP4 sayfa "
        f"açılırken tamponlanır; poster ilk boyayı taşır, preload=\"none\"")
    poster = v.get("poster", "")
    assert poster.endswith(".webp") and _disk(poster).is_file(), (
        f"{yol}: poster {poster!r} WebP değil ya da diskte yok — poster "
        f"masaüstünde hero'nun ilk boyası, PNG'si 925 KB")


@pytest.mark.parametrize("yol", _SAYFALAR)
def test_mp4_kaynagi_media_sorgusu_tasir(yol: str):
    _, kaynak = _video(yol)
    assert kaynak.get("src", "").endswith(".mp4") and _disk(kaynak["src"]).is_file()
    assert re.fullmatch(r"\(min-width: \d+px\)", kaynak.get("media", "")), (
        f"{yol}: MP4 <source> media sorgusu taşımıyor — CSS videoyu ≤980 px'te "
        f"gizler ama display:none indirmeyi durdurmaz; 4,42 MB telefona iner")


# ---------------------------------------------------------------------------
# (4) Hero: iki preload, iki tüketici, aynı dosyalar
# ---------------------------------------------------------------------------

def _preloadlar(yol: str) -> list[dict[str, str]]:
    metin = _yorumsuz(_sayfa(yol))
    return [n for t, a in _ETIKET.findall(metin)
            for n in [_nitelikler(a)]
            if t == "link" and n.get("rel") == "preload" and n.get("as") == "image"]


def _media_bloklari(css: str) -> list[tuple[str, int, int]]:
    """(sorgu, başlangıç, bitiş) — süslü parantez sayarak."""
    bloklar = []
    for m in re.finditer(r"@media\s*([^{]+)\{", css):
        derinlik, k = 1, m.end()
        while derinlik:
            if css[k] == "{":
                derinlik += 1
            elif css[k] == "}":
                derinlik -= 1
            k += 1
        bloklar.append((m.group(1).strip(), m.start(), k))
    return bloklar


def _css_hero_arka_plani() -> tuple[str, str]:
    """(dosya, onu saran @media sorgusu) — rytho.css'in hero arka plan tüketicisi.

    Blok `image-set()` taşıyorsa WebP çözen tarayıcının çekeceği dosya
    `type('image/webp')` adayıdır; düz `url()` ise o. Bu ayrım bekçinin
    kendisi için: CSS image-set'e geçtiği gün bekçi "mobil preload PNG
    olsun" diye direnmemeli, tam tersine WebP istemeli.
    """
    return _css_hero_arka_plani_coz(_CSS.read_text(encoding="utf-8"))


def _css_hero_arka_plani_coz(ham_css: str) -> tuple[str, str]:
    css = _css_yorumsuz(ham_css)
    # İki blok var: masaüstü `display: none` ve ≤980 px'teki url() taşıyan;
    # tüketici yalnız ikincisi.
    bloklar = [m for m in re.finditer(r"\.hero-fallback::before\s*\{([^}]*)\}", css)
               if "url(" in m.group(1)]
    assert len(bloklar) == 1, (
        f"rytho.css: url() taşıyan {len(bloklar)} .hero-fallback::before bloğu — "
        f"tüketici taşındı mı?")
    blok = bloklar[0]
    govde = blok.group(1)
    webp = re.search(r"image-set\([^)]*url\('([^']+\.webp)'\)\s*type\('image/webp'\)", govde)
    dosya = webp.group(1) if webp else re.search(r"url\('([^']+)'\)", govde).group(1)
    saran = [q for q, a, b in _media_bloklari(css) if a <= blok.start() < b]
    assert len(saran) == 1, f"hero arka planı {len(saran)} @media bloğu içinde"
    return dosya, saran[0]


@pytest.mark.parametrize("yol", _SAYFALAR)
def test_hero_mobil_preload_css_arka_planiyla_ayni(yol: str):
    dosya, sorgu = _css_hero_arka_plani()
    mobil = [p for p in _preloadlar(yol) if p.get("media") == sorgu]
    assert len(mobil) == 1, (
        f"{yol}: media=\"{sorgu}\" taşıyan tek bir hero preload bekleniyor "
        f"(CSS'in arka plan bloğuyla aynı sorgu), {len(mobil)} var")
    assert mobil[0].get("href") == dosya, (
        f"{yol}: mobil preload {mobil[0].get('href')!r}, CSS arka planı "
        f"{dosya!r} — iki ayrı dosya iki kez iner; CSS image-set(webp)'e "
        f"geçtiyse preload da webp'ye döner")
    assert mobil[0].get("fetchpriority") == "high"
    if dosya.endswith(".webp"):
        assert mobil[0].get("type") == "image/webp", (
            f"{yol}: WebP preload'u type=\"image/webp\" taşımalı — çözemeyen "
            f"tarayıcı CSS'in PNG adayına düşer, preload'u boşuna indirmemeli")


@pytest.mark.parametrize("yol", _SAYFALAR)
def test_hero_masaustu_preload_posterle_ayni(yol: str):
    v, kaynak = _video(yol)
    masa = [p for p in _preloadlar(yol) if p.get("media") == kaynak.get("media")]
    assert len(masa) == 1, (
        f"{yol}: MP4'ün media sorgusunu taşıyan tek bir hero preload "
        f"bekleniyor, {len(masa)} var")
    assert masa[0].get("href") == v.get("poster"), (
        f"{yol}: masaüstü preload {masa[0].get('href')!r} ≠ poster "
        f"{v.get('poster')!r} — iki dosya iki kez iner")
    assert masa[0].get("type") == "image/webp", (
        f"{yol}: WebP preload'u type=\"image/webp\" taşımalı — çözemeyen "
        f"tarayıcı yoksa dosyayı boşuna indirir")


@pytest.mark.parametrize("yol", _SAYFALAR)
def test_hero_preloadlari_birbirini_tamamlar(yol: str):
    """≤N ve ≥N+1: boşluk kalırsa o genişlikte hero geç gelir, çakışırsa
    iki dosya birden iner."""
    sorgular = sorted(p.get("media", "") for p in _preloadlar(yol))
    assert len(sorgular) == 2, f"{yol}: {len(sorgular)} görsel preload"
    ust = re.fullmatch(r"\(max-width: (\d+)px\)", sorgular[0])
    alt = re.fullmatch(r"\(min-width: (\d+)px\)", sorgular[1])
    assert ust and alt, f"{yol}: preload media sorguları {sorgular}"
    assert int(alt.group(1)) == int(ust.group(1)) + 1, f"{yol}: {sorgular} bitişik değil"


# ---------------------------------------------------------------------------
# (5) Köken damgası: WebP ↔ PNG ↔ araç sabitleri
# ---------------------------------------------------------------------------

def test_webp_damgasi_diskteki_png_ve_arac_sabitiyle_ayni():
    arac = _arac()
    bayat = []
    for png, webp, genislik in arac.hedefler():
        if not arac.guncel_mi(str(_WEB / "assets" / png),
                              str(_WEB / "assets" / webp), genislik):
            bayat.append(webp)
    assert not bayat, (
        "WebP diskteki PNG'den ya da aracın bugünkü sabitleriyle "
        "(KALITE/genişlik) üretilmemiş — yeniden yakalanan ekran siteye "
        "yansımaz. Koş: backend\\.venv\\Scripts\\python.exe "
        "tools\\web_gorsel_optimize.py\n  " + "\n  ".join(bayat))


def test_her_webp_nin_ureticisi_ve_okuyucusu_var():
    """Diskteki her WebP aracın listesinde (yoksa kimse yenilemez) ve HTML'in
    referans verdiği her WebP de orada (yoksa damga bekçisi onu görmez).
    Üçüncü yön: aracın ürettiği her WebP bir sayfadan okunuyor — okuyucusu
    olmayan şey ısıtılmaz."""
    arac = _arac()
    uretilen = {"/assets/" + webp for _, webp, _ in arac.hedefler()}
    diskte = {"/assets/" + p.relative_to(_WEB / "assets").as_posix()
              for p in (_WEB / "assets").rglob("*.webp")}
    okunan = {r.yol for yol in _SAYFALAR for r in _referanslar(_sayfa(yol))
              if _uzanti(r.yol) == ".webp"}
    assert diskte - uretilen == set(), f"araç listesinde olmayan WebP: {diskte - uretilen}"
    assert okunan - uretilen == set(), f"HTML'in okuduğu ama aracın üretmediği: {okunan - uretilen}"
    assert uretilen - okunan == set(), f"üretilen ama hiçbir sayfanın okumadığı: {uretilen - okunan}"


# ---------------------------------------------------------------------------
# Bekçinin DIŞI ve muafiyet listesi
# ---------------------------------------------------------------------------

def test_bekcinin_DISI_var():
    """Yorumdaki img sayılmaz; WebP yedeği olan PNG sayılmaz ama listelenir;
    çıplak PNG ve WebP'siz <picture> PNG'si sayılır; preload hem href hem
    imagesrcset; poster ve video kaynağı ayrı etiketle; stylesheet yok."""
    ornek = (
        '<!-- <img src="/a/yorum.png"> -->\n'
        '<picture><source type="image/webp" srcset="/a/b-1x.webp 1x, /a/b-2x.webp 2x">'
        '<img src="/a/b.png"></picture>\n'
        '<img src="/a/c.png">\n'
        '<picture><img src="/a/d.png"></picture>\n'
        '<link rel="preload" as="image" href="/a/h.webp" imagesrcset="/a/h-1.webp 1x">\n'
        '<video poster="/a/p.webp"><source src="/a/v.mp4" type="video/mp4"></video>\n'
        '<link rel="stylesheet" href="/a/s.css">')
    refs = {(r.satir, r.yol, r.etiket, r.sayilir) for r in _referanslar(ornek)}
    assert refs == {
        (2, "/a/b-1x.webp", "source", True), (2, "/a/b-2x.webp", "source", True),
        (2, "/a/b.png", "img", False),
        (3, "/a/c.png", "img", True),
        (4, "/a/d.png", "img", True),
        (5, "/a/h-1.webp", "preload", True), (5, "/a/h.webp", "preload", True),
        (6, "/a/p.webp", "poster", True), (6, "/a/v.mp4", "video-source", True),
    }
    # @media blok sayacı iç içe parantezi doğru kapatıyor
    css = "@media (max-width: 1px) { .x { a: b } @supports (c) { .y { d: e } } } .z{}"
    assert _media_bloklari(css) == [("(max-width: 1px)", 0, len(css) - 5)]
    # Hero tüketicisi: düz url() → o dosya; image-set → WebP adayı; yorumdaki
    # url() görülmez (bir şeyin yokluğunu arayan bekçi onu anlatan yorumu görmez)
    duz = ("/* url('/eski.png') */ @media (max-width: 9px) { .hero-fallback::before {"
           " background: red url('/a.png') center / cover; } }")
    assert _css_hero_arka_plani_coz(duz) == ("/a.png", "(max-width: 9px)")
    kume = ("@media (max-width: 9px) { .hero-fallback::before {"
            " background: red url('/a.png') center / cover;"
            " background-image: image-set(url('/a.webp') type('image/webp'),"
            " url('/a.png') type('image/png')); } }")
    assert _css_hero_arka_plani_coz(kume) == ("/a.webp", "(max-width: 9px)")


def test_tavan_disi_listesi_referans_edilen_dosyalari_gosteriyor():
    """Muafiyet artık referans edilmeyen bir dosyaya işaret ederse ölü kalır
    ve kimse fark etmez — o gün girdi silinir."""
    okunan = {r.yol for yol in _SAYFALAR for r in _referanslar(_sayfa(yol)) if r.sayilir}
    for d in _TAVAN_DISI:
        assert d in okunan, f"{d} artık sayılan referans değil — _TAVAN_DISI'ndan sil"
        assert _disk(d).stat().st_size > _TEK_GORSEL_TAVAN, (
            f"{d} artık tavanın altında — xfail(strict) zaten kırmızı döner, girdiyi sil")

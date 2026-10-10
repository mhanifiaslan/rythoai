# -*- coding: utf-8 -*-
r"""Uygulamanın yazı tiplerini PAKETE koyar: statik ağırlık üretir, alt küme alır, glif fontunu kurar.

NEDEN BU BETİK VAR
------------------
`rytho_theme.dart` üç aileyi (Sora, Manrope, JetBrains Mono) yalnız
`GoogleFonts.*` ile kullanıyordu: ilk açılışta `fonts.gstatic.com`'a istek,
ağsız açılışta yedek fontla çizim ve ölçüldü — `test/chart_wheel_test.dart`
bile `allowRuntimeFetching = false` yazmak zorunda kalmıştı. Fontlar pakette
olunca açılışta ağ çağrısı yok, yedek font flaşı yok, test ortamıyla cihaz
aynı fontu çizer.

İkinci iş GLİF FONTU: ♀/♂ ve burç glifleri Android'de RENKLİ EMOJİ olarak
çıkıyordu (store/play/shot-2-chart.png, raw/04-cevrem.png'de görüldü). Kök:
`wheel_painter.dart` gezegen glifini Manrope ile basıyor, Manrope'ta ♀♂ yok,
Skia emoji fontuna düşüyor. Çözüm `RythoText.*`'a `fontFamilyFallback:
['RythoGlyphs']` — bu betik o fontu iki OFL kaynaktan (Noto Sans Symbols +
Noto Sans Symbols 2) YALNIZ gereken kod noktalarıyla kurar. Kapsam iddia
edilmez, ÖLÇÜLÜR: `*.codepoints.txt` dosyaları yazılır ve Dart bekçisi
(`test/font_paketi_test.dart`) uygulamanın kullandığı her karakteri orada arar.

KULLANIM
--------
    backend/.venv/Scripts/python.exe tools/font_paketi_uret.py --indir <klasör>

`<klasör>` altında şu dosyalar beklenir (github.com/google/fonts, ofl/):
    sora/Sora[wght].ttf · manrope/Manrope[wght].ttf ·
    jetbrainsmono/JetBrainsMono[wght].ttf ·
    notosanssymbols/NotoSansSymbols[wght].ttf ·
    notosanssymbols2/NotoSansSymbols2-Regular.ttf
`fonttools` gerekir (`pip install fonttools brotli`) — deploy imajına GİRMEZ,
yalnız bu araç için venv'e kurulur.

ÇIKTI
-----
    apps/mobile/assets/google_fonts/<Aile>-<Ağırlık>.ttf   (google_fonts paketi
        dosya adını `<Aile>-<Regular|Medium|SemiBold|Bold>` olarak arar —
        google_fonts_variant.dart:181-184; başka ad SESSİZCE bulunamaz ve
        allowRuntimeFetching=false ile fırlatır)
    apps/mobile/assets/fonts/RythoGlyphs.ttf
    her font için <ad>.codepoints.txt  (bekçinin okuduğu kapsam listesi)

AĞIRLIK KÜMESİ ÖLÇÜLDÜ, VARSAYILMADI (2026-10-10): `RythoText.*(` çağrılarının
gövdesindeki TÜM `FontWeight.wNNN` literalleri (üçlü ifadeler dahil) + kurucu
varsayılanları → Sora 600/700, Manrope 400/500/600/700, JetBrains Mono
400/700. Yeni bir ağırlık isteyen kod bekçide kırmızı döner; buraya eklenip
betik yeniden koşturulur.
"""
from __future__ import annotations

import argparse
import glob
import io
import json
import re
import sys
import tempfile
from pathlib import Path

from fontTools.merge import Merger
from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

KOK = Path(__file__).resolve().parent.parent
MOBIL = KOK / "apps" / "mobile"
GF_CIKTI = MOBIL / "assets" / "google_fonts"
GLIF_CIKTI = MOBIL / "assets" / "fonts"

# google_fonts paketinin aradığı dosya adı ekleri (google_fonts_variant.dart:181-184).
AGIRLIK_ADI = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}

# (aile, kaynak dosya, ölçülen ağırlıklar)
METIN_FONTLARI = [
    ("Sora", "sora/Sora[wght].ttf", (600, 700)),
    # 500: ZodiacChip seçili/seçilmemiş ağırlığı üçlü ifadeyle seçiyor
    # (`w700 : w500`); ilk ölçüm yalnız ilk literali aldığı için kaçırmıştı,
    # bekçi yakaladı. Eksik ağırlık = cihazda fırlatma.
    ("Manrope", "manrope/Manrope[wght].ttf", (400, 500, 600, 700)),
    ("JetBrainsMono", "jetbrainsmono/JetBrainsMono[wght].ttf", (400, 700)),
]

# Metin fontlarında TUTULAN bloklar. Cömert bırakıldı: Latin'in tamamı,
# noktalama, para (₺), oklar, matematik (− × ≈ ≤ ≥), geometrik şekiller,
# dingbat (✦ ✓). Atılan şey Kiril/Yunanca/Vietnamca gibi uygulamanın hiç
# yazmadığı yazı sistemleri — Manrope'un boyutunun çoğu bunlar.
METIN_BLOKLARI = (
    "U+0000-024F,U+02B0-02FF,U+0300-036F,U+1E00-1EFF,U+2000-206F,U+2070-209F,"
    "U+20A0-20CF,U+2100-214F,U+2150-218F,U+2190-21FF,U+2200-22FF,U+2300-23FF,"
    "U+2460-24FF,U+25A0-25FF,U+2600-26FF,U+2700-27BF,U+FB00-FB06,U+FE00-FE0F,"
    "U+FFFD"
)

# Glif fontunun kapsamı — uygulamanın GLİF OLARAK bastığı her şey
# (`lib/theme/rytho_glyphs.dart` tabloları). İki Noto kaynağı birbirini
# tamamlıyor (ölçüldü): Symbols burçları ve gezegenlerin 11'ini, Symbols 2
# ise ☉ △ □ ✦ ▴ ▾'yi taşıyor.
GLIF_KODLARI = (
    list(range(0x2648, 0x2654))                    # ♈–♓ burçlar
    + [0x2609, 0x263D, 0x263F, 0x2640, 0x2642,     # ☉ ☽ ☿ ♀ ♂
       0x2643, 0x2644, 0x2645, 0x2646, 0x2647]      # ♃ ♄ ♅ ♆ ♇
    + [0x260A, 0x260B]                              # ☊ ☋ düğümler
    + [0x26B7, 0x26B8]                              # ⚷ Kiron ⚸ Lilith
    + [0x260C, 0x260D, 0x25B3, 0x25A1, 0x26B9]      # ☌ ☍ △ □ ⚹ açılar
    + [0x2726, 0x2727, 0x25B4, 0x25BE]              # ✦ ✧ ▴ ▾ marka/abonelik/katlanır
    + [0x25CB, 0x2691]                              # ○ İ Ching eski yang · ⚑ güvenlik bayrağı
)

# Uygulamanın BİLEREK renkli emoji olarak bastığı karakterler (ürün kararı:
# 🔥🪙👁️✨ gibi ikonlar renkli). Bunlar sistem emoji fontuna düşer, glif
# fontuna GİRMEZ; ölçümde "açık" sayılmaz. VS16 (U+FE0F) ile yazılanlar
# zaten emoji sunumu ister.
BILINCLI_EMOJI = {
    0x2600,  # ☀️ Büyük Üçlü "Güneş" etiketi (profile_screen, sky_screen)
    0x2B06,  # ⬆️ Büyük Üçlü "Yükselen"
    0x2615,  # ☕ arkadaşlık ilişki ikonu (core/friends.dart)
    0x262F,  # ☯/☯️ İ Ching ikonu — D7'de ozellik_katalogu tek biçime (VS16) çeker
    0x21A9,  # ↩️ retro çipi (sky_now_screen)
    0x2728, 0x2764, 0x26A0, 0xFE0F, 0xFE0E, 0x200D,
}

# Bilinen açıklar: paket fontlarda OLMAYAN ve henüz değiştirilmemiş
# karakterler. Her biri gerekçeli; D-dalgası kapanınca buradan SİLİNİR ve
# betik o karakteri bulursa kırmızı döner.
BILINEN_ACIK = {
    0x211E: "℞ iki Noto kaynağında da yok; D6'da çarkın zaten kullandığı 'R' "
            "retro işaretiyle birleştirilecek (atlas_detail 305/446, app_en.arb "
            "retrogradeMeaning). O güne kadar sistem fontuna düşer.",
}


def _emoji_mi(kod: int) -> bool:
    return kod >= 0x1F000 or kod in BILINCLI_EMOJI


def _alt_kume(font: TTFont, unicodes: str | list[int]) -> TTFont:
    opt = Options()
    opt.layout_features = ["*"]  # tnum (JetBrains Mono tabular figures) ve kerning kalsın
    opt.notdef_outline = True
    opt.name_IDs = ["*"]
    opt.recalc_bounds = True
    sub = Subsetter(options=opt)
    if isinstance(unicodes, str):
        kodlar: list[int] = []
        for parca in unicodes.split(","):
            a, _, b = parca.replace("U+", "").partition("-")
            lo = int(a, 16)
            hi = int(b, 16) if b else lo
            kodlar.extend(range(lo, hi + 1))
        sub.populate(unicodes=kodlar)
    else:
        sub.populate(unicodes=list(unicodes))
    sub.subset(font)
    return font


def _kapsami_yaz(font_yolu: Path) -> set[int]:
    cmap = TTFont(str(font_yolu)).getBestCmap()
    kodlar = sorted(cmap)
    io.open(str(font_yolu.with_suffix(".codepoints.txt")), "w",
            encoding="utf-8", newline="\n").write(
        "\n".join(f"U+{k:04X}" for k in kodlar) + "\n")
    return set(kodlar)


def metin_fontlari(indir: Path) -> dict[str, set[int]]:
    GF_CIKTI.mkdir(parents=True, exist_ok=True)
    kapsam: dict[str, set[int]] = {}
    for aile, kaynak, agirliklar in METIN_FONTLARI:
        for w in agirliklar:
            vf = TTFont(str(indir / kaynak))
            statik = instantiateVariableFont(vf, {"wght": w})
            statik = _alt_kume(statik, METIN_BLOKLARI)
            hedef = GF_CIKTI / f"{aile}-{AGIRLIK_ADI[w]}.ttf"
            statik.save(str(hedef))
            boyut = hedef.stat().st_size
            print(f"  {hedef.name:28s} {boyut/1024:7.1f} KB")
        # Kapsam aile başına tek dosya: ağırlıklar aynı cmap'i taşır.
        kapsam[aile] = _kapsami_yaz(GF_CIKTI / f"{aile}-{AGIRLIK_ADI[agirliklar[-1]]}.ttf")
        # Diğer ağırlıkların .codepoints.txt'si gereksiz; bekçi aile adıyla okur.
        for w in agirliklar[:-1]:
            (GF_CIKTI / f"{aile}-{AGIRLIK_ADI[w]}.codepoints.txt").unlink(missing_ok=True)
        # `replace`, `rename` değil: betik yeniden koşunca eski kapsam dosyası
        # duruyor ve Windows'ta `rename` var olanın üstüne yazmıyor (ölçüldü).
        (GF_CIKTI / f"{aile}-{AGIRLIK_ADI[agirliklar[-1]]}.codepoints.txt").replace(
            GF_CIKTI / f"{aile}.codepoints.txt")
    return kapsam


def glif_fontu(indir: Path) -> set[int]:
    GLIF_CIKTI.mkdir(parents=True, exist_ok=True)
    sym = instantiateVariableFont(
        TTFont(str(indir / "notosanssymbols/NotoSansSymbols[wght].ttf")), {"wght": 400})
    sym2 = TTFont(str(indir / "notosanssymbols2/NotoSansSymbols2-Regular.ttf"))
    cm1, cm2 = sym.getBestCmap(), sym2.getBestCmap()
    # Önce Symbols'tan al, onda olmayanı Symbols 2'den — iki fontta da olan
    # tek fontta kalsın ki merge çakışma görmesin.
    k1 = [k for k in GLIF_KODLARI if k in cm1]
    k2 = [k for k in GLIF_KODLARI if k not in cm1 and k in cm2]
    eksik = [k for k in GLIF_KODLARI if k not in cm1 and k not in cm2]
    if eksik:
        raise SystemExit("Glif fontu kuramadı, iki kaynakta da yok: "
                         + ", ".join(f"U+{k:04X} {chr(k)}" for k in eksik))
    with tempfile.TemporaryDirectory() as tmp:
        a = Path(tmp) / "a.ttf"
        b = Path(tmp) / "b.ttf"
        _alt_kume(sym, k1).save(str(a))
        _alt_kume(sym2, k2).save(str(b))
        birlesik = Merger().merge([str(a), str(b)])
        hedef = GLIF_CIKTI / "RythoGlyphs.ttf"
        birlesik.save(str(hedef))
    print(f"  {hedef.name:28s} {hedef.stat().st_size/1024:7.1f} KB  "
          f"(Symbols {len(k1)} + Symbols2 {len(k2)} kod noktası)")
    kapsam = _kapsami_yaz(hedef)
    eksik2 = [k for k in GLIF_KODLARI if k not in kapsam]
    if eksik2:
        raise SystemExit("Birleşik fontta kayıp glif: "
                         + ", ".join(f"U+{k:04X}" for k in eksik2))
    return kapsam


def uygulamanin_karakterleri() -> set[int]:
    """ARB değerleri + Dart dize literallerindeki ASCII-dışı her karakter."""
    kullanilan: set[int] = set()
    for p in ("app_tr.arb", "app_en.arb"):
        veri = json.load(io.open(str(MOBIL / "lib" / "l10n" / p), encoding="utf-8"))
        for k, v in veri.items():
            if isinstance(v, str) and not k.startswith("@"):
                kullanilan |= {ord(ch) for ch in v if ord(ch) > 127}
    for yol in glob.glob(str(MOBIL / "lib" / "**" / "*.dart"), recursive=True):
        if "l10n" in Path(yol).parts:
            continue
        # Yorum satırları atılır: doküman yorumlarındaki π φ ψ gibi
        # karakterler ekrana HİÇ çizilmiyor, ölçüme girmemeli (ilk koşuda
        # tam bu yüzden üç sahte açık çıktı).
        s = "\n".join(
            satir for satir in io.open(yol, encoding="utf-8").read().split("\n")
            if not satir.lstrip().startswith("//"))
        for m in re.finditer(r"'((?:[^'\\]|\\.)*)'", s):
            kullanilan |= {ord(ch) for ch in m.group(1) if ord(ch) > 127}
    return kullanilan


def main() -> int:
    # Windows konsolu cp1254: glif listesini basarken UnicodeEncodeError
    # fırlatıyordu (ölçüldü) — çıktı her zaman UTF-8.
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--indir", required=True, help="indirilen ham fontların klasörü")
    indir = Path(ap.parse_args().indir)

    print("Metin fontları:")
    metin = metin_fontlari(indir)
    print("Glif fontu:")
    glif = glif_fontu(indir)

    # ÖLÇÜM: uygulamanın yazdığı her karakter paketlenen fontların birinde mi?
    hepsi = set().union(*metin.values()) | glif
    kullanilan = uygulamanin_karakterleri()
    acik = sorted(k for k in kullanilan if not _emoji_mi(k) and k not in hepsi)
    print(f"Uygulamanın ASCII-dışı karakteri: {len(kullanilan)} "
          f"(emoji hariç {sum(1 for k in kullanilan if not _emoji_mi(k))})")
    bilinen = [k for k in acik if k in BILINEN_ACIK]
    yeni = [k for k in acik if k not in BILINEN_ACIK]
    for k in bilinen:
        print(f"   bilinen açık U+{k:04X} {chr(k)} — {BILINEN_ACIK[k]}")
    # Bilinen açık listesinde durup artık KULLANILMAYAN bir karakter varsa
    # liste bayatlamış demektir — o da kırmızı: kapanan iş listeden silinmeli.
    bayat = [k for k in BILINEN_ACIK if k not in kullanilan]
    if yeni or bayat:
        if yeni:
            print("⚠️ HİÇBİR PAKET FONTTA OLMAYAN karakterler (sistem fontuna düşer):")
            for k in yeni:
                print(f"   U+{k:04X} {chr(k)}")
        if bayat:
            print("⚠️ BILINEN_ACIK bayat — artık kullanılmıyor, listeden sil: "
                  + ", ".join(f"U+{k:04X}" for k in bayat))
        return 1
    print("OK: emoji dışı her karakter paketlenen fontlarda var "
          f"(bilinen açık: {len(bilinen)}).")
    toplam = sum(p.stat().st_size for p in list(GF_CIKTI.glob("*.ttf")) + list(GLIF_CIKTI.glob("*.ttf")))
    print(f"Toplam font yükü: {toplam/1024:.1f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())

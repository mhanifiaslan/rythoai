# -*- coding: utf-8 -*-
r"""Web görsellerini WebP'ye çevirir; 1x/2x adaylarını ve hero posterini üretir.

Çıktı: web/assets/space/*.webp ve web/assets/screens/*.webp. PNG kaynaklar
yerinde kalır — `<picture>` yedeği ve mobil hero arka planı onları okuyor.

## Neden (ölçüldü 2026-10-10)

Ana sayfa 9 PNG + 1 MP4 ile ~15,6 MB görsel taşıyordu; WebP, srcset ve
`<picture>` hiç yoktu. Aynı görsellerin WebP q80 karşılığı (Pillow,
method=6):

    hero-nebula   1.111.791 B → 23.474 B
    planet-*      1,29–1,70 MB → 24–92 KB
    shot-*        0,66–1,29 MB → 61–116 KB

Hero'da ortalama mutlak hata 1,29/255 — gözle ayırt edilmiyor. 256 renkli
PNG kuantizasyonu ise (121 KB) nebula bulutlarını görünür biçimde
lekeliyor (yan yana kırpım ölçüldü); bu yüzden hiçbir PNG KAYIPLI
küçültülmez.

## Üç sınıf, üç kural

* Gezegen küreleri (1024²): 1x = 512, 2x = 1024. En büyük tüketici
  `.buyuk-kure` min(460px, 84vw) — 2x'te 920 px ister, 1024 yeter.
* Ekran görüntüleri (1080×1920): 1x = 540, 2x = 1080. ⚠️ Kaynak PNG'ler
  store/play ile md5 birebir; sahip yeniden yakalayana kadar DOKUNULMAZ,
  yalnız WebP üretilir.
* Hero (1344×752): TEK WebP, tam boy. "1x" adayı üretilmiyor çünkü
  tüketicisi yok — poster yalnız ≥981 px CSS genişlikte görünür ve
  100vw × ≥1 DPR her zaman 1344'ü seçer. Aynı dosya video posteridir:
  videonun ilk karesi nebuladan ortalama 1,9/255 uzak (64×36'ya
  indirgenerek ölçüldü), yani poster → video geçişinde sıçrama yok ve
  preload ile poster TEK fetch.

Hero PNG'si ayrıca KAYIPSIZ yeniden sıkıştırılır (1.111.791 → 925.235 B,
piksel birebir; ikinci geçiş aynı baytı verir, yani betik tekrar
koşulabilir). Sebep: rytho.css'in ≤980 px bloğu hero arka planını
PNG'den okuyor ve o dosya her mobil ziyarette iniyor. WebP'ye geçiş o
CSS satırının işi; geçene kadar PNG küçülebildiği kadar küçülmeli.

## Köken damgası

Her WebP'nin EXIF ImageDescription alanına kaynak PNG'nin SHA-256'sı,
kalite ve genişlik yazılır. Bekçi (`backend/tests/test_web_varlik_butcesi.py`)
bunu diskteki PNG ile karşılaştırır. Damga olmasa şu kusur sessiz kalır:
ekran görüntüsü yeniden yakalanır, betik koşulmaz, site ESKİ ekranı
(WebP) gösterirken depo YENİ PNG'yi taşır. Git mtime taşımadığı için
"WebP güncel mi" sorusu damgasız ölçülemez.

Bağımlılık: Pillow (backend/.venv'de 12.3.0, WebP desteği açık — ölçüldü
`features.check("webp")`). infra/store-graphics.py ile aynı araç.

Koşum:  backend\.venv\Scripts\python.exe tools\web_gorsel_optimize.py
        --kontrol → yalnız güncellik raporu basar, dosya yazmaz; bayat ya da
        eksik çıktı varsa 1 ile çıkar.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import os
import sys

from PIL import Image
from PIL.PngImagePlugin import PngInfo

KOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VARLIK = os.path.join(KOK, "web", "assets")

#: libwebp kalite. Bekçi diskteki damgayla karşılaştırır: sabit değişirse
#: eski WebP'ler bayat sayılır ve betik yeniden koşulana kadar kırmızı.
KALITE = 80
#: 0–6; 6 en yavaş ve en küçük. Tek seferlik üretim, süre önemsiz.
YONTEM = 6
EXIF_ACIKLAMA = 0x010E  # ImageDescription

#: (PNG, (etiket, genişlik)…). Etiket dosya adına girer (`planet-x-1x.webp`);
#: `None` etiket çıplak `.webp` üretir (tek aday, hero).
PLANLAR: tuple[tuple[str, tuple[tuple[str | None, int], ...]], ...] = (
    ("space/hero-nebula.png", ((None, 1344),)),
    ("space/planet-alerts.png", (("1x", 512), ("2x", 1024))),
    ("space/planet-bazi.png", (("1x", 512), ("2x", 1024))),
    ("space/planet-firaset.png", (("1x", 512), ("2x", 1024))),
    ("space/planet-natal.png", (("1x", 512), ("2x", 1024))),
    ("space/planet-transits.png", (("1x", 512), ("2x", 1024))),
    ("screens/shot-1-sky.png", (("1x", 540), ("2x", 1080))),
    ("screens/shot-2-chart.png", (("1x", 540), ("2x", 1080))),
    ("screens/shot-5-chat.png", (("1x", 540), ("2x", 1080))),
)

#: Yalnız bu PNG'ler kayıpsız yeniden sıkıştırılır: canlı tüketicisi olan
#: tek PNG hero (mobil CSS arka planı). Gezegen ve ekran PNG'leri yalnız
#: WebP çözemeyen tarayıcıya iner; onları yeniden yazmak 7 MB ikili diff
#: üretir, kimseye bir şey kazandırmaz. Ekran görüntüleri ayrıca store/play
#: ile bayt birebir kalmalı.
KAYIPSIZ_SIKISTIR: tuple[str, ...] = ("space/hero-nebula.png",)


def sha256(yol: str) -> str:
    h = hashlib.sha256()
    with open(yol, "rb") as f:
        for parca in iter(lambda: f.read(1 << 20), b""):
            h.update(parca)
    return h.hexdigest()


def webp_adi(png_goreli: str, etiket: str | None) -> str:
    govde = png_goreli[:-4]
    return f"{govde}-{etiket}.webp" if etiket else f"{govde}.webp"


def hedefler() -> list[tuple[str, str, int]]:
    """(PNG göreli, WebP göreli, genişlik) — üretim ve bekçi aynı listeyi okur."""
    return [(png, webp_adi(png, etiket), genislik)
            for png, adaylar in PLANLAR
            for etiket, genislik in adaylar]


def damga_yaz(kaynak_adi: str, sha: str, genislik: int) -> str:
    return f"kaynak={kaynak_adi} sha256={sha} q={KALITE} w={genislik}"


def damga_coz(webp_yol: str) -> dict[str, str] | None:
    """EXIF ImageDescription → {kaynak, sha256, q, w}; damga yoksa None."""
    try:
        with Image.open(webp_yol) as im:
            metin = im.getexif().get(EXIF_ACIKLAMA)
    except (OSError, ValueError):
        return None
    if not metin:
        return None
    parcalar = dict(p.split("=", 1) for p in str(metin).split() if "=" in p)
    return parcalar if {"kaynak", "sha256", "q", "w"} <= parcalar.keys() else None


def guncel_mi(png_yol: str, webp_yol: str, genislik: int) -> bool:
    """WebP, diskteki PNG'den ve BU betiğin sabitleriyle mi üretilmiş?"""
    if not os.path.exists(webp_yol):
        return False
    d = damga_coz(webp_yol)
    return bool(d) and (d["sha256"] == sha256(png_yol)
                        and d["q"] == str(KALITE)
                        and d["w"] == str(genislik))


def webp_uret(png_yol: str, webp_yol: str, genislik: int) -> int:
    """PNG → WebP (q=KALITE); genişlik kaynağınkinden küçükse LANCZOS ile
    indirger, büyükse BÜYÜTMEZ (kaynak çözünürlüğün üstü uydurma olur)."""
    sha = sha256(png_yol)
    with Image.open(png_yol) as im:
        im = im.convert("RGB")
        w, h = im.size
        if genislik > w:
            raise SystemExit(f"{png_yol}: {genislik} px isteniyor, kaynak {w} px")
        if genislik < w:
            im = im.resize((genislik, round(h * genislik / w)),
                           Image.Resampling.LANCZOS)
        exif = Image.Exif()
        exif[EXIF_ACIKLAMA] = damga_yaz(os.path.basename(png_yol), sha, genislik)
        tampon = io.BytesIO()
        im.save(tampon, "WEBP", quality=KALITE, method=YONTEM, exif=exif.tobytes())
    veri = tampon.getvalue()
    with open(webp_yol, "wb") as f:
        f.write(veri)
    return len(veri)


def kayipsiz_sikistir(png_yol: str) -> tuple[int, int]:
    """PNG'yi piksel birebir yeniden sıkıştırır; yalnız küçülüyorsa yazar.

    Metin parçaları (`hf-job-id` gibi köken notları) korunur — Pillow
    varsayılanı onları düşürür ve kaynağın nereden geldiği kaybolurdu.
    """
    eski = os.path.getsize(png_yol)
    with Image.open(png_yol) as im:
        bilgi = PngInfo()
        for anahtar, deger in im.info.items():
            if isinstance(deger, str):
                bilgi.add_text(anahtar, deger)
        tampon = io.BytesIO()
        im.save(tampon, "PNG", optimize=True, pnginfo=bilgi)
    veri = tampon.getvalue()
    if len(veri) < eski:
        with open(png_yol, "wb") as f:
            f.write(veri)
    return eski, min(eski, len(veri))


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    p.add_argument("--kontrol", action="store_true",
                   help="yalnız güncellik raporu; dosya yazmaz")
    args = p.parse_args(argv)
    # Windows konsolu cp1254 ile açılıyor ve Türkçe harfler sığsa da U+2192
    # gibi işaretler UnicodeEncodeError ile betiği ÇÖKERTİYOR (ölçüldü,
    # ilk koşum). Rapor satırları bu yüzden UTF-8'e zorlanır.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    # Kayıpsız sıkıştırma WebP'den ÖNCE: damga PNG'nin SHA-256'sını taşıyor,
    # sıra tersine dönerse yeni yazılan PNG damgayı aynı koşumda bayatlatır.
    if not args.kontrol:
        for png in KAYIPSIZ_SIKISTIR:
            eski, yeni = kayipsiz_sikistir(os.path.join(VARLIK, png))
            print(f"kayıpsız      {png}  {eski:,} -> {yeni:,} B")

    bayat = 0
    for png, webp, genislik in hedefler():
        png_yol = os.path.join(VARLIK, png)
        webp_yol = os.path.join(VARLIK, webp)
        if not os.path.exists(png_yol):
            print(f"EKSİK KAYNAK  {png}")
            bayat += 1
            continue
        if guncel_mi(png_yol, webp_yol, genislik):
            print(f"güncel        {webp}  {os.path.getsize(webp_yol):>9,} B")
            continue
        if args.kontrol:
            print(f"BAYAT/EKSİK   {webp}")
            bayat += 1
            continue
        boyut = webp_uret(png_yol, webp_yol, genislik)
        print(f"üretildi      {webp}  {boyut:>9,} B")

    if bayat:
        print(f"{bayat} çıktı bayat ya da eksik - betiği --kontrol'süz koş.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

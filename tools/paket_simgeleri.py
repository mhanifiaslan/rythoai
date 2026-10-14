# -*- coding: utf-8 -*-
r"""Kredi paketlerinin Play ürün simgeleri — 1024×1024, 32 bit PNG.

Play kuralı: metin, tanıtım ve marka YOK; her ürün için benzersiz görsel.
Ürünleri ayıran şey sikke SAYISI (küçük 1, orta 2, büyük 3) — adet yazmak
kurala aykırı olurdu ve adet değişince görsel yalan söylerdi (2026-10-14'te
100/300/1000 → 50/100/200 oldu; sayı yazan görsel o gün bayatlardı).

Renkler uygulamanın paletinden (`rytho_theme.dart`): zemin `ink`→mor
degrade, sikke altın (`gold`/`goldBright`), üstünde `✦` kesiği. Kenar
yumuşaklığı için 4 kat büyük çizilip küçültülür.

Kullanım: backend/.venv/Scripts/python.exe tools/paket_simgeleri.py
Çıktı:    store/play/urunler/rytho_tokens_{small,medium,large}.png
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

BOYUT = 1024
OLCEK = 4
B = BOYUT * OLCEK

INK = (17, 11, 26)          # RythoColors.ink yakını
MOR = (74, 30, 140)         # degrade alt ucu (primaryGradient tonu, koyulaştırılmış)
ALTIN = (255, 194, 75)      # RythoColors.gold
ALTIN_PARLAK = (255, 217, 138)  # RythoColors.goldBright
ALTIN_KOYU = (196, 132, 30)

CIKTI = Path(__file__).resolve().parents[1] / "store" / "play" / "urunler"


def _zemin() -> Image.Image:
    """Dikey degrade: üst koyu mürekkep, alt mor; ortada hafif ışık halesi."""
    img = Image.new("RGBA", (B, B))
    px = img.load()
    for y in range(B):
        t = y / (B - 1)
        r = round(INK[0] + (MOR[0] - INK[0]) * t)
        g = round(INK[1] + (MOR[1] - INK[1]) * t)
        b = round(INK[2] + (MOR[2] - INK[2]) * t)
        for x in range(B):
            px[x, y] = (r, g, b, 255)
    hale = Image.new("RGBA", (B, B), (0, 0, 0, 0))
    d = ImageDraw.Draw(hale)
    for i in range(40, 0, -1):
        a = int(3 * (40 - i) / 40 * 4)
        rr = B * 0.18 + i * B * 0.008
        d.ellipse([B / 2 - rr, B * 0.52 - rr, B / 2 + rr, B * 0.52 + rr],
                  fill=(255, 194, 75, a))
    return Image.alpha_composite(img, hale)


def _yildiz(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, renk):
    """Dört kollu yıldız (✦): içbükey kenarlı, dört uç."""
    noktalar = []
    for i in range(8):
        aci = math.pi / 4 * i - math.pi / 2
        yaricap = r if i % 2 == 0 else r * 0.28
        noktalar.append((cx + yaricap * math.cos(aci), cy + yaricap * math.sin(aci)))
    d.polygon(noktalar, fill=renk)


def _sikke(img: Image.Image, cx: float, cy: float, r: float) -> None:
    """Altın sikke: gölge, kenar halkası, iç yüz, ortada ✦."""
    katman = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(katman)
    golge = r * 0.06
    d.ellipse([cx - r, cy - r + golge * 2, cx + r, cy + r + golge * 2],
              fill=(0, 0, 0, 90))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ALTIN_KOYU + (255,))
    ic = r * 0.90
    d.ellipse([cx - ic, cy - ic, cx + ic, cy + ic], fill=ALTIN + (255,))
    halka = r * 0.74
    d.ellipse([cx - halka, cy - halka, cx + halka, cy + halka],
              outline=ALTIN_KOYU + (255,), width=max(1, int(r * 0.045)))
    _yildiz(d, cx, cy, r * 0.46, ALTIN_PARLAK + (255,))
    _yildiz(d, cx, cy, r * 0.46 * 0.55, (255, 245, 220, 255))
    img.alpha_composite(katman)


def uret(adet: int) -> Image.Image:
    img = _zemin()
    # Sikke sayısı arttıkça küçülür ki kompozisyon aynı alanı doldursun.
    r = B * {1: 0.27, 2: 0.22, 3: 0.20}[adet]
    yer = {
        1: [(0.50, 0.52)],
        2: [(0.40, 0.58), (0.60, 0.46)],
        3: [(0.33, 0.62), (0.67, 0.62), (0.50, 0.40)],
    }[adet]
    # Arkadan öne: yukarıdaki sikke arkada kalsın diye y'ye göre sıralanır.
    for fx, fy in sorted(yer, key=lambda p: p[1]):
        _sikke(img, B * fx, B * fy, r)
    return img.resize((BOYUT, BOYUT), Image.LANCZOS)


def main() -> None:
    CIKTI.mkdir(parents=True, exist_ok=True)
    for ad, adet in (("small", 1), ("medium", 2), ("large", 3)):
        yol = CIKTI / f"rytho_tokens_{ad}.png"
        uret(adet).save(yol, "PNG")
        print(yol, Image.open(yol).mode, Image.open(yol).size)


if __name__ == "__main__":
    main()

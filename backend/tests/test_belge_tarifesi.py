"""Belgelerdeki ve uygulama metnindeki AYLIK JETON HAKKI sayısı, sunucudaki
sabitle birebir aynı olmak zorundadır.

NEDEN bu bekçi var (ölçüldü 2026-10-02): aylık hak K1'de 300'den 100'e
indirildi (`core/wallet.py` `MONTHLY_TOKEN_ALLOWANCE`). Sunucu 100 verdi,
uygulama metni 100 dedi — ama `docs/store-launch.md` **300 yazmaya devam
etti** ve hiçbir test düşmedi. O belge özel: içindeki mağaza metni bloğu
sahibin Play Console'a **elle kopyaladığı** metindir, yani oradaki sayı
mağaza listesine girer. Yanlış sayı mağazaya girerse düzeltmesi bir kod
yaması değil, mağaza incelemesinden geçecek yeni bir metin sürümüdür.

Aynı sayı bugün **beş ayrı yerde** elle yazılı duruyor ve hiçbiri sabite
bağlı değil: `docs/store-launch.md` (TR + EN mağaza metni ve monetizasyon
tablosu), `docs/ozellikler.md`, `docs/maliyet-calismasi.md`,
`docs/test-raporu.md`, ve uygulamanın `benefitChatTitle` dizesi (arb + üretilen
Dart). `docs/maliyet-calismasi.md` bu kırılganlığı zaten yazıyordu
("İki yer sabite BAĞLI DEĞİL, elle yazılı") ama yazmak bekçi değildir.

Bekçi bilerek KIRILGAN DEĞİL:

* **Serbest sayı aranmıyor, İDDİA KALIBI aranıyor.** "300" dizesini yasaklamak
  işe yaramazdı: belgeler eski sayıyı anlatarak tutuyor ("hak 300'den 100'e
  indi", "300 jeton paketi"), üstelik `rytho_tokens_medium` paketinin ADI
  gerçekten "300 AI Kredisi". Bu yüzden eşleşme niteleyiciye bağlandı —
  "ayda/aylık ... hakkı" kalıbı — ve paket adları kalıba hiç girmiyor.
* **Alt dize değil kelime kalıbı** (CLAUDE.md §5): Türkçe `lower()` bozuk
  olduğu için küçültme HİÇ yapılmıyor; büyük/küçük baş harf kalıbın içinde
  açıkça sayılıyor ("ayda" ve "Ayda").
* **Blockquote satırları eşleşmeden ÖNCE atılır.** Bu bekçi bir şeyin
  YOKLUĞUNU da arıyor (hiçbir canlı iddia eski sayıyı taşımamalı) ve bu
  depoda iki kez tam olarak şu patladı: bir şeyin yokluğunu arayan bekçi,
  onu ANLATAN yoruma takıldı (CLAUDE.md §5). Markdown'da yorum yok; bu
  depodaki belgelerin karşılığı `> ⚠️` ile başlayan geriye dönük notlardır
  ("önceki hâli 300 diyordu"). Onlar atılmazsa, kusuru anlatan not kusurun
  kendisi sayılırdı.
* **Taban sayısı var.** Yalnız "bulunan her sayı doğru olsun" demek yetmezdi:
  iddia cümlesi silinse ya da öyle bir yeniden yazılsa ki kalıba hiç
  uymasa, bekçi SESSİZCE yeşil kalırdı — yani hiçbir şey ölçmez olurdu.
  Bu yüzden mağaza metninin iki dili ve tarife belgesi için en az bir
  eşleşme ŞART.
"""
from __future__ import annotations

import io
import json
import re
from pathlib import Path

import pytest

from core.wallet import MONTHLY_TOKEN_ALLOWANCE

_KOK = Path(__file__).resolve().parents[2]

#: Aylık hak iddiasının kalıpları. Her kalıp sayıyı YAKALAR ve niteleyici
#: ("ayda" / "aylık ... hakkı" / "a month") kalıbın İÇİNDE — paket adları
#: ("100 AI Kredisi", "300 AI Credits") bu yüzden eşleşmiyor.
_KALIPLAR = {
    # "ayda 100 AI kredisi" · "Ayda 100 AI kredisi" · "ayda **100 jeton**"
    "tr_ayda": re.compile(r"(?:ayda|Ayda)\s+\*{0,2}(\d+)\s+(?:AI kredisi|jeton)"),
    # "**aylık 100 token** hakkı"
    "tr_aylik_hak": re.compile(r"aylık\s+\*{0,2}(\d+)\s+token\*{0,2}\s+hakkı"),
    # "100 AI credits a month" — mağaza metninde satır başına sarılıyor,
    # bu yüzden araya \s+ konuyor (tek boşluk yazılsa EN iddiası GÖRÜNMEZDİ).
    "en_a_month": re.compile(r"(\d+)\s+AI\s+credits a month"),
}

#: (belge, kalıp) -> en az kaç eşleşme olmalı. Buradakiler iddianın
#: YAŞAMAK ZORUNDA olduğu yüzeyler: mağazaya elle girilen metnin iki dili
#: ve "koddan sapmamalı" diye işaretli tarife belgesi.
_ZORUNLU = {
    ("docs/store-launch.md", "tr_ayda"): 1,
    ("docs/store-launch.md", "en_a_month"): 1,
    ("docs/store-launch.md", "tr_aylik_hak"): 1,
    ("docs/ozellikler.md", "tr_ayda"): 1,
}


def _canli_metin(yol: Path) -> str:
    """Geriye dönük notları (blockquote) atmış belge gövdesi.

    `> ` ile başlayan satır bu depoda "bu bir tur boyunca yanlıştı" notudur,
    canlı bir iddia değil. Satır silinmiyor BOŞALTILIYOR: satır numaraları
    korunuyor ki hata mesajı doğru yeri göstersin.
    """
    satirlar = io.open(yol, encoding="utf-8").read().split("\n")
    return "\n".join(
        "" if s.lstrip().startswith(">") else s for s in satirlar)


def _iddialar(yol: Path) -> list[tuple[str, int, str]]:
    """(kalıp adı, satır no, yakalanan sayı) üçlüleri."""
    metin = _canli_metin(yol)
    bulunan: list[tuple[str, int, str]] = []
    for ad, kalip in _KALIPLAR.items():
        for m in kalip.finditer(metin):
            satir = metin[:m.start()].count("\n") + 1
            bulunan.append((ad, satir, m.group(1)))
    return bulunan


def test_belgelerdeki_aylik_hak_sunucu_sabitiyle_ayni():
    """docs/ altındaki her canlı aylık-hak iddiası sabitle aynı sayıyı söyler."""
    sapma = []
    for yol in sorted((_KOK / "docs").glob("*.md")):
        for ad, satir, sayi in _iddialar(yol):
            if int(sayi) != MONTHLY_TOKEN_ALLOWANCE:
                sapma.append(
                    f"docs/{yol.name}:{satir} [{ad}] {sayi} "
                    f"(sabit {MONTHLY_TOKEN_ALLOWANCE})")
    assert not sapma, (
        "Belgedeki aylık hak sunucudan saptı. `wallet.MONTHLY_TOKEN_ALLOWANCE` "
        "değiştiyse AŞAĞIDAKİ HER SATIR elle düzeltilir — "
        "docs/store-launch.md'deki mağaza metni bloğu Play Console'a "
        "KOPYALANAN metindir, oradaki sayı mağaza listesine girer:\n  "
        + "\n  ".join(sapma))


@pytest.mark.parametrize("belge,kalip", sorted(_ZORUNLU))
def test_aylik_hak_iddiasi_belgede_duruyor(belge: str, kalip: str):
    """İddia cümlesi silinirse ya da kalıptan kaçarsa bekçi KIRMIZI olur.

    Bu test olmasa üstteki test "bulunan her sayı doğru" diyerek, hiç iddia
    kalmadığında da yeşil kalırdı — yani mağaza metninden aylık hak
    cümlesinin tamamen düşmesi sessizce geçerdi.
    """
    yol = _KOK / belge
    sayilar = [s for ad, _, s in _iddialar(yol) if ad == kalip]
    assert len(sayilar) >= _ZORUNLU[(belge, kalip)], (
        f"{belge} içinde '{kalip}' kalıbına uyan aylık hak iddiası YOK. "
        "Cümle silindiyse geri konur; yeniden yazıldıysa "
        "test_belge_tarifesi._KALIPLAR da birlikte güncellenir "
        "(iddia kalıptan kaçarsa bekçi hiçbir şey ölçmez).")


#: Uygulamanın paywall'da gösterdiği aylık hak dizesi. Mağaza metninden
#: ayrı tutuluyor çünkü kaynağı ayrı: burası kullanıcının EKRANDA gördüğü
#: vaat, öteki mağaza listesinde gördüğü vaat.
_ARB = {
    "apps/mobile/lib/l10n/app_tr.arb": "Ayda {n} AI kredisi",
    "apps/mobile/lib/l10n/app_en.arb": "{n} AI credits a month",
}

#: Üretilen l10n dosyaları depoda DURUYOR, yani arb düzeltilip codegen
#: koşmazsa cihaza eski sayı gider. Bu yüzden üretilen hâl de çivileniyor.
_URETILEN = {
    "apps/mobile/lib/l10n/app_localizations_tr.dart": "Ayda {n} AI kredisi",
    "apps/mobile/lib/l10n/app_localizations_en.dart": "{n} AI credits a month",
}


@pytest.mark.parametrize("arb_yolu", sorted(_ARB))
def test_paywall_metnindeki_aylik_hak_sunucu_sabitiyle_ayni(arb_yolu: str):
    """`benefitChatTitle` sabitle aynı sayıyı yazar.

    NEDEN ekranda yazan sayı önemli: paywall "sınırsız" demiyor, SAYI
    söylüyor (K3 kararı) — yani vaat ölçülebilir, dolayısıyla yanlış
    olabilir. Sunucu 100 verirken ekran 300 derse bu yanlış beyandır.
    """
    veri = json.loads(io.open(_KOK / arb_yolu, encoding="utf-8").read())
    beklenen = _ARB[arb_yolu].format(n=MONTHLY_TOKEN_ALLOWANCE)
    assert veri["benefitChatTitle"] == beklenen, (
        f"{arb_yolu} benefitChatTitle = {veri['benefitChatTitle']!r}, "
        f"beklenen {beklenen!r} (wallet.MONTHLY_TOKEN_ALLOWANCE = "
        f"{MONTHLY_TOKEN_ALLOWANCE}).")


@pytest.mark.parametrize("dart_yolu", sorted(_URETILEN))
def test_uretilen_l10n_aylik_hakki_tasiyor(dart_yolu: str):
    """arb düzeltilip `flutter gen-l10n` koşulmazsa cihaza eski sayı gider."""
    gövde = io.open(_KOK / dart_yolu, encoding="utf-8").read()
    beklenen = _URETILEN[dart_yolu].format(n=MONTHLY_TOKEN_ALLOWANCE)
    assert f"benefitChatTitle => '{beklenen}'" in gövde, (
        f"{dart_yolu} içinde benefitChatTitle {beklenen!r} değil. "
        "arb düzeltildi ama l10n yeniden üretilmemiş olabilir.")

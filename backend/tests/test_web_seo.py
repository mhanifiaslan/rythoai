r"""Web yüzeyinin arama motoru sözleşmesi — hepsi SESSİZ bozulan şeyler.

Bu dosyadaki her iddia 2026-09-26'da ölçülmüş gerçek bir kusurdan doğdu;
hiçbiri teorik değil. Ortak yanları: bozulduklarında hiçbir yerde hata
görünmüyor — ne derlemede, ne deploy'da, ne panelde. Yalnızca aylar sonra
"sayfa aramada yok" ya da "Search Console erişimim gitti" diye fark ediliyor.

Çalıştırma:
    .venv\Scripts\python.exe -m pytest tests/test_web_seo.py -q
"""
from __future__ import annotations

import pathlib
import re

_KOK = pathlib.Path(__file__).resolve().parents[2]
_WEB = _KOK / "web"
_TABAN = "https://rytho.app"

# Bu klasörler bilerek indekslenmiyor: panel ve auth işleyicisi
# X-Robots-Tag ile, /i/ kendi noindex'i ile (aşağıda ayrı test).
# `r` = ortak bağlantısı (OP): /i/ ile aynı gerekçe — tek sayfa sınırsız
# URL'ye hizmet ediyor, indekslenirse kopya içerik olur.
# `ortak` = ortağın KENDİ panosu (OP9): rytho-admin gibi özel bir pano,
# hiçbir yerden linklenmez ve firebase.json'daki /ortak/** girdisiyle
# X-Robots-Tag: noindex taşır. Burada olmasa sitemap tamlık testi
# patlardı — test her indekslenebilir .html'in sitemap'te olmasını
# zorluyor ve giriş kapısı sitemap'e girmemeli.
_HARIC_KLASOR = {"rytho-admin", "auth", "i", "r", "ortak", "assets",
                 ".well-known"}
# 404 sayfası bir hata yüzeyi; doğrulama dosyası Google'ın kendi artefaktı.
_HARIC_DOSYA = {"404.html", "googleb6af2cb19834337d.html"}


def _sitemap() -> str:
    return (_WEB / "sitemap.xml").read_text(encoding="utf-8")


def _robots_yorumsuz() -> str:
    """robots.txt'i `#` yorumları ATILMIŞ hâlde döndürür.

    ⚠️ Bu depoda iki kez yaşandı: bir şeyin YOKLUĞUNU arayan bekçi, o şeyi
    ANLATAN yorumu görüp sahte hata verdi (build-aab.ps1 izin kapısı ve
    davet sayfası testi). robots.txt'teki açıklama satırı kelimesi
    kelimesine "Disallow: /i/" içeriyor — yorumlar atılmazsa aşağıdaki
    "Disallow yok" iddiası kendi gerekçesine takılır.
    """
    ham = (_WEB / "robots.txt").read_text(encoding="utf-8")
    return re.sub(r"(?m)^\s*#.*$", "", ham)


def _indekslenebilir_sayfalar() -> list[str]:
    """web/ altındaki her indekslenebilir sayfanın kanonik URL'si."""
    yollar = []
    for p in sorted(_WEB.rglob("*.html")):
        goreli = p.relative_to(_WEB)
        if _HARIC_KLASOR & set(goreli.parts[:-1]):
            continue
        if goreli.name in _HARIC_DOSYA:
            continue
        # index.html dizin URL'sine çöker: en/index.html -> /en/
        if goreli.name == "index.html":
            dizin = "/".join(goreli.parts[:-1])
            yollar.append(f"{_TABAN}/{dizin + '/' if dizin else ''}")
        else:
            yollar.append(f"{_TABAN}/{goreli.as_posix()}")
    return yollar


def test_dogrulama_dosyasi_yerinde_ve_bozulmamis():
    """Google doğrulamayı TEK SEFERLİK yapmaz, periyodik tekrar okur.

    Firebase Hosting her deploy'da siteyi `web/` klasörüyle TAMAMEN
    değiştiriyor; dosya depoda olmazsa başka bir makineden (ör. Mac)
    yapılan ilk deploy onu canlıdan siler ve Search Console mülkü
    SESSİZCE doğrulanmamış duruma döner — uyarı yalnızca e-postaya gelir.
    """
    dosya = _WEB / "googleb6af2cb19834337d.html"
    assert dosya.exists(), "Search Console doğrulama dosyası yok"
    assert dosya.read_bytes() == (
        b"google-site-verification: googleb6af2cb19834337d.html"), (
        "doğrulama dosyasının içeriği birebir olmalı — satır sonu ya da "
        "BOM eklenmesi bile doğrulamayı düşürür")


def test_robots_sitemap_ayni_ana_makineyi_gosteriyor():
    """Farklı ana makinedeki sitemap ÇAPRAZ GÖNDERİM sayılıp yok sayılır.

    robots.txt bir süre `rhytoai.web.app` sitemap'ini duyurdu, oysa
    sitemap içindeki tüm URL'ler `rytho.app`. Search Console sitemap'i
    keşfediyor ama işlemiyordu; hiçbir yerde hata görünmüyordu.
    """
    beyan = re.search(r"(?m)^Sitemap:\s*(\S+)\s*$", _robots_yorumsuz())
    assert beyan, "robots.txt'te Sitemap satırı yok"
    assert beyan.group(1).startswith(_TABAN + "/"), (
        f"sitemap beyanı {_TABAN} dışında bir ana makineyi gösteriyor: "
        f"{beyan.group(1)}")
    for loc in re.findall(r"<loc>([^<]+)</loc>", _sitemap()):
        assert loc.startswith(_TABAN + "/"), (
            f"sitemap içinde yabancı ana makine: {loc}")


def test_sitemap_tum_indekslenebilir_sayfalari_listeliyor():
    """Sitemap'te olmayan sayfa, ona link de yoksa HİÇ keşfedilemez.

    Hesap silme sayfaları tam olarak böyleydi: birbirlerinden başka hiçbir
    yerden bağlanmıyorlardı ve sitemap'te yoktular. Play'in zorunlu
    tuttuğu veri silme sayfası aramada hiç görünmüyordu.
    """
    listelenen = set(re.findall(r"<loc>([^<]+)</loc>", _sitemap()))
    eksik = [u for u in _indekslenebilir_sayfalar() if u not in listelenen]
    assert not eksik, f"sitemap'te olmayan sayfalar: {eksik}"
    olu = [u for u in listelenen if u not in set(_indekslenebilir_sayfalar())]
    assert not olu, f"sitemap'te karşılığı olmayan URL'ler: {olu}"


def test_davet_sayfasi_noindex_tasiyor_VE_taranabiliyor():
    """İkisi BİRLİKTE olmak zorunda — tek başına her biri işe yaramaz.

    Sezgiye aykırı olan şu: `Disallow` indekslemeyi ENGELLEMEZ, yalnız
    taramayı durdurur. Dış linkle ulaşılan sayfa yine indekslenir, üstelik
    başlıksız ("Indexed, though blocked by robots.txt"). Ve Google
    noindex'i GÖREBİLMEK için sayfayı tarayabilmek zorundadır — yani
    Disallow geri eklenirse noindex sessizce ölür.
    """
    sayfa = (_WEB / "i" / "index.html").read_text(encoding="utf-8")
    assert re.search(r'<meta\s+name="robots"\s+content="[^"]*noindex', sayfa), (
        "davet sayfasında noindex yok; /i/** yeniden yazımı sınırsız URL'yi "
        "bu tek sayfaya düşürüyor, hepsi kopya içerik olarak indekslenir")
    assert "Disallow: /i/" not in _robots_yorumsuz(), (
        "robots.txt /i/ taramasını engelliyor — Google bu sayfanın "
        "noindex'ini okuyamaz ve koruma boşa düşer")


def test_ortak_baglanti_sayfasi_backend_ile_ayni_kod_desenini_kullaniyor():
    r"""`web/r/` sayfası kodu Play'e taşımadan önce KENDİ doğruluyor.

    Desen backend'deki `partner_service._KOD_DESENI` ile birebir aynı
    olmalı. Ayrışırsa iki sessiz kusurdan biri olur: sayfa geçerli bir
    kodu reddedip kullanıcıyı atıfsız mağazaya yollar, ya da geçersiz
    birini taşıyıp `redeem-code` ucunda 400'e düşürür — ikisi de yalnız
    o ortağın gelirinde görünür, hata olarak hiçbir yerde görünmez.
    """
    from services import partner_service

    sayfa = (_WEB / "r" / "index.html").read_text(encoding="utf-8")
    desen = re.search(r"var DESEN = /(.+?)/;", sayfa)
    assert desen, "sayfada kod deseni bulunamadı"
    assert desen.group(1) == partner_service._KOD_DESENI.pattern, (
        f"sayfa {desen.group(1)!r} diyor, backend "
        f"{partner_service._KOD_DESENI.pattern!r}")

    # Kod mağaza bağlantısında utm_campaign olarak taşınır; uygulama
    # tarafı (partner_referrer.dart) tam olarak o alanı okuyor.
    assert "utm_campaign=" in sayfa
    assert "&referrer=" in sayfa
    assert 'name="robots" content="noindex' in sayfa


def test_hreflang_kumelerinde_x_default_var():
    """x-default yoksa dili eşleşmeyen ziyaretçiye Google kendi tahminiyle
    bir dil seçer. Ürün TR-öncelikli (uygulamada da desteklenmeyen dil
    `kSupportedLocales.first` = tr'ye düşer), bu yüzden beyan edilmeli."""
    for p in sorted(_WEB.rglob("*.html")):
        metin = p.read_text(encoding="utf-8")
        if 'hreflang="tr"' not in metin:
            continue
        assert 'hreflang="x-default"' in metin, f"x-default yok: {p}"

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
# `affiliate` (eski `ortak`, 2026-10-19) = ortağın KENDİ panosu (OP9): rytho-admin gibi özel bir pano,
# hiçbir yerden linklenmez ve firebase.json'daki /affiliate/** girdisiyle
# X-Robots-Tag: noindex taşır. Burada olmasa sitemap tamlık testi
# patlardı — test her indekslenebilir .html'in sitemap'te olmasını
# zorluyor ve giriş kapısı sitemap'e girmemeli.
_HARIC_KLASOR = {"rytho-admin", "auth", "i", "r", "affiliate", "assets",
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


def _r_sayfasi_kodu() -> str:
    r"""`web/r/index.html` içindeki JS'i YORUMLARI ATILMIŞ hâlde döndürür.

    ⚠️ Yorumları atmak ŞART ve gerekçesi bu depoda iki kez patladı: bir
    şeyin YOKLUĞUNU arayan bekçi, onu ANLATAN yorumu görmemeli. Aşağıdaki
    testler tam bunu yapıyor — biri `document.cookie`nin geçmediğini
    kanıtlıyor, öteki `location.replace(` ile ping çağrısının SIRASINA
    bakıyor. Ping'i açıklayan yorum blokları hem "çerez" hem
    "location.replace" kelimelerini geçiriyor; ham metinde arama yapan bir
    bekçi ilkinde yanlış pozitif verir, ikincisinde yanlış NEGATİF —
    yorum kodun önünde geldiği için sıra testi her hâlükârda "geçer".

    Satır yorumları YALNIZ satır başından atılıyor, gövde içi kuyruk
    yorumu bırakılıyor. Naif bir `//`→satır sonu temizliği dize
    literallerini de keserdi: sayfada `'https://play.google.com/...'`
    duruyor (ölçüldü, dosyadaki tek gövde-içi `//` tam o) ve mağaza
    adresi yarısından kesilirdi.

    ⚠️ SIRA ÖLÇÜLDÜ ve tersi SESSİZCE KOD YUTUYOR: satır yorumları blok
    yorumlarından ÖNCE atılmalı. Sayfadaki bir satır yorumu Hosting
    yeniden yazımından söz ediyor ve içinde `/api/**` geçiyor — o dizi
    `/*` ile başlıyor. Blok temizliği önce koşarsa oradan başlayıp bir
    sonraki `*/`ye kadar HER ŞEYİ siliyor; ping fonksiyonunun tamamı
    kaybolmuş hâlde teste giriyordu (ilk yazımda tam bu oldu, testler
    "sendBeacon yok" diye kırmızı döndü ve suçlu sayfa değil bu
    yardımcıydı).
    """
    sayfa = (_WEB / "r" / "index.html").read_text(encoding="utf-8")
    js = re.search(r"<script>(.*?)</script>", sayfa, re.S)
    assert js, "sayfada <script> bloğu yok"
    kod = re.sub(r"(?m)^[ \t]*//.*$", "", js.group(1))
    return re.sub(r"/\*.*?\*/", "", kod, flags=re.S)


def test_ortak_sayfasi_tiklamayi_YONLENDIRMEDEN_SAG_CIKACAK_bicimde_bildiriyor():
    """Ping, mağaza yönlendirmesinden SAĞ ÇIKMAK zorunda.

    Android dalı `location.replace` çağırıyor ve sıradan bir `fetch` o anda
    İPTAL EDİLİR: istek hiç gitmez, konsolda hata da görünmez. Sonuç
    tam olarak ölçülemeyen bir ölçüm olurdu — panoda tıklama 0 yazar,
    "kimse tıklamamış" gibi okunur ve ortak tanıtımını boşuna suçlar.
    `sendBeacon` bu iş için var (sayfa kapanırken de gönderir), `keepalive`
    da yedeği. İkisi birden düşerse ping ATLANIR; ziyaretçi bir sayaç için
    mağazaya gitmeyi beklemez.

    Sıra da pinleniyor: ping çağrısı yönlendirmeden ÖNCE gelmeli. Sonra
    gelirse hiç çalışmaz — Android'de o satıra varılmaz bile.
    """
    kod = _r_sayfasi_kodu()

    assert "navigator.sendBeacon(" in kod, (
        "ping `sendBeacon` kullanmıyor — `location.replace` sıradan bir "
        "fetch'i iptal eder ve tıklama ölçümü sessizce kaybolur")
    assert "keepalive: true" in kod, (
        "sendBeacon yedeği `keepalive: true` taşımıyor; bayrak olmadan "
        "yönlendirme yedek isteği de keser")

    cagri = re.search(r"(?m)^[ \t]*tiklamaBildir\(", kod)
    assert cagri, "ping hiçbir yerden ÇAĞRILMIYOR (yalnız tanımlı)"
    yonlendirme = kod.index("location.replace(")
    assert cagri.start() < yonlendirme, (
        "ping çağrısı `location.replace(`'ten SONRA — Android'de o satıra "
        "hiç varılmaz, tıklama hiç sayılmaz")

    # Gizlilik çizgisi (sahibin şartı, pazarlık yok): gövdede YALNIZ kod.
    # Bu iddia ekranda da yazıyor (yönetim panelinde "Kimlik saklanmıyor"),
    # yani gövde büyürse ürün tutmadığı bir söz vermiş olur.
    assert "JSON.stringify({ code: kod })" in kod, (
        "ping gövdesi beklenen tek alanlı biçimde değil; tıklama ölçümünde "
        "koddan başka hiçbir şey gönderilmez")
    assert "document.cookie" not in kod, (
        "sayfa çerez okuyor — tıklama ölçümü kimliksiz olmak zorunda")


def test_ortak_sayfasinin_pingledigi_uc_backend_te_GERCEKTEN_tanimli():
    """Sayfanın pinglediği yol ile backend'in mounted yolu AYNI olmalı.

    `DESEN` testiyle aynı sınıf bir sessiz kopma: yol ayrışırsa sayfa
    404'e ping atar, beacon sessiz olduğu için hiçbir yerde hata görünmez
    ve pano "tıklama yok" der. Sözleşme yolu `POST /api/v1/partners/click`.

    Bu test page↔route EŞLEŞMESİNİ pinliyor; ucun kendi davranışı
    (204, gövde yok, kimlik yok) backend paketinin testlerinde.
    """
    kod = _r_sayfasi_kodu()
    yol = re.search(r"var adres = '([^']+)';", kod)
    assert yol, "sayfada ping adresi bulunamadı"
    beklenen = yol.group(1)
    assert beklenen.startswith("/api/"), (
        f"ping adresi göreli /api/ yolu değil: {beklenen!r} — ana makine "
        "sabit yazılırsa sayfa rhytoai.web.app üstünden çapraz kökene düşer")

    from main import app

    # ⚠️ `app.routes` ÜZERİNDEN OKUNMUYOR ve gerekçesi ölçüldü: bu FastAPI
    # sürümünde `include_router` alt yolları düzleştirmiyor, `app.routes`
    # içine `_IncludedRouter` sarmalayıcıları koyuyor. `getattr(r, "path")`
    # o nesnelerde YOK, yani yolları orada arayan bir bekçi hiçbir uç
    # bulamaz ve uç VARKEN bile kırmızı döner (ilk yazımda tam bu oldu).
    # OpenAPI şeması mount edilmiş yolu tek gerçek kaynak olarak veriyor.
    # Sınır: `include_in_schema=False` ile gizlenen bir uç burada
    # görünmez — o gün bu test uca değil BEKÇİYE işaret eder.
    yollar = app.openapi().get("paths", {})
    assert beklenen in yollar, (
        f"sayfa {beklenen!r} adresine POST atıyor ama backend bu yolu "
        "tanımlamıyor; beacon sessiz olduğu için kayıp hiçbir yerde "
        f"görünmez. Tanımlı ortak yolları: "
        f"{sorted(p for p in yollar if 'partner' in p)}")
    assert "post" in yollar[beklenen], (
        f"{beklenen!r} tanımlı ama POST yok: {sorted(yollar[beklenen])} — "
        "sayfa beacon'u POST olarak yolluyor")


def test_hreflang_kumelerinde_x_default_var():
    """x-default yoksa dili eşleşmeyen ziyaretçiye Google kendi tahminiyle
    bir dil seçer. Ürün TR-öncelikli (uygulamada da desteklenmeyen dil
    `kSupportedLocales.first` = tr'ye düşer), bu yüzden beyan edilmeli."""
    for p in sorted(_WEB.rglob("*.html")):
        metin = p.read_text(encoding="utf-8")
        if 'hreflang="tr"' not in metin:
            continue
        assert 'hreflang="x-default"' in metin, f"x-default yok: {p}"


# ---------------------------------------------------------------------------
# Stil/yorum turu (2026-10-10): ölü bağlantı, hukuk tarihi, EN logo kökü
# ---------------------------------------------------------------------------

def _honesty():
    """`test_honesty` modülü — 15 sayfalık liste oradan alınır, kopyalanmaz
    (tamlığını `test_yayindaki_her_sayfa_listede` kanıtlıyor). test_sozluk
    ile aynı yükleme yolu: pytest `tests/`i sys.path'e koymazsa dosyadan."""
    try:
        import test_honesty
        return test_honesty
    except ImportError:
        import importlib.util
        import sys
        yol = pathlib.Path(__file__).with_name("test_honesty.py")
        spec = importlib.util.spec_from_file_location("test_honesty", yol)
        mod = importlib.util.module_from_spec(spec)
        sys.modules["test_honesty"] = mod
        spec.loader.exec_module(mod)
        return mod


def _yorumsuz_html(metin: str) -> str:
    """Bir şeyin YOKLUĞUNU arayan bekçi, onu ANLATAN yorumu görmemeli —
    davet sayfasının eski yorumu kelimesi kelimesine `href="#"` içeriyordu."""
    return re.sub(r"<!--.*?-->", " ", metin, flags=re.S)


def test_hicbir_sayfada_olu_baglanti_yok():
    """`href="#"` tıklanınca sayfa başına atlar: düğme gibi görünür, hiçbir
    yere gitmez.

    Ölçüldü 2026-10-10: iki ana sayfada App Store "düğmesi" `href="#"` +
    `aria-disabled` idi — aria-disabled için tek satır CSS yoktu, yani
    görünüşte normal bir ikincil düğmeydi ve tıklayan hero'ya geri
    fırlıyordu. Davet sayfası aynı deseni daha önce "çalışmayan düğme,
    çevrilmemiş metinden kötü" diye kaldırmıştı; ortak bağlantısı sayfası
    ise JS koşmazsa `href="#"` ile kalıyordu. Karar: bağlantı olmayan
    şey bağlantı gibi işaretlenmez — "yakında" bir metin hapıdır
    (`.rozet.yakinda`), mağaza düğmesi JS'siz de gerçek adrese gider.
    """
    for yol in _honesty().TestPazarlamaDili._SAYFALAR:
        metin = _yorumsuz_html((_KOK / yol).read_text(encoding="utf-8"))
        assert 'href="#"' not in metin, (
            f"{yol}: href=\"#\" var — ya gerçek adres yaz ya da öğe bağlantı "
            f"olmaktan çıksın (metin hapı: .rozet.yakinda)")
    # Ters yön: yerine geçen hap gerçekten tanımlı ve kullanılıyor. Sınıf
    # silinirse "yakında" yazısı stilsiz düz metne düşer, yukarısı yine
    # yeşil kalırdı.
    css = (_WEB / "assets" / "rytho.css").read_text(encoding="utf-8")
    assert ".rozet.yakinda {" in css, "rytho.css'te .rozet.yakinda tanımı yok"
    for yol in ("index.html", "en/index.html"):
        assert 'class="rozet yakinda"' in (_WEB / yol).read_text(
            encoding="utf-8"), f"{yol}: App Store hapı (.rozet.yakinda) yok"


#: Hukuk sayfası tarih satırı — dil başına kalıp. "Son güncelleme" /
#: "Last updated" satırı okuyucunun "bu metin güncel mi" sorusunun tek
#: cevabı; iki hesap silme sayfası bu satırı taşımıyordu (ölçüldü
#: 2026-10-10), yalnız geliştirici adı yazıyordu.
_TARIH = {
    "tr": re.compile(r'class="tarih">Son güncelleme: \d{1,2} '
                     r'[A-ZÇĞİÖŞÜ][a-zçğıöşü]+ \d{4}'),
    "en": re.compile(r'class="tarih">Last updated: [A-Z][a-z]+ \d{1,2}, \d{4}'),
}


def test_hukuk_sayfalari_tarih_satiri_tasiyor():
    sayfalar = (sorted((_WEB / "legal").glob("*.html"))
                + sorted((_WEB / "en" / "legal").glob("*.html")))
    assert len(sayfalar) >= 6, f"hukuk sayfası sayısı düştü: {len(sayfalar)}"
    for p in sayfalar:
        metin = p.read_text(encoding="utf-8")
        dil = re.search(r'<html lang="(\w+)"', metin)
        assert dil and dil.group(1) in _TARIH, f"{p}: html lang okunamadı"
        assert _TARIH[dil.group(1)].search(metin), (
            f"{p.relative_to(_KOK).as_posix()}: 'Son güncelleme / Last "
            f"updated' tarih satırı yok ya da biçimi bozuk (gün Ay yıl / "
            f"Month day, year)")


_LOGO = re.compile(r'<a\s+(?:class="marka"\s+)?href="([^"]+)"\s*>\s*'
                   r'<img src="/assets/rytho_logo.svg"')


def test_ingilizce_sayfalarda_logo_ingilizce_koke_gider():
    """`/en/**` altında logo `/`'e giderse İngilizce okuyan ziyaretçi bir
    tıkla Türkçe ana sayfaya düşer. Ölçüldü 2026-10-10:
    en/legal/delete-account.html logosu `/` idi, kardeşleri `/en/`."""
    for p in sorted((_WEB / "en").rglob("*.html")):
        metin = p.read_text(encoding="utf-8")
        hedefler = _LOGO.findall(metin)
        assert hedefler, (
            f"{p.relative_to(_KOK).as_posix()}: logo bağlantısı bulunamadı — "
            f"kalıp değiştiyse bekçi kör")
        for h in hedefler:
            assert h.startswith("/en/"), (
                f"{p.relative_to(_KOK).as_posix()}: logo {h!r} adresine "
                f"gidiyor, /en/ bekleniyor")

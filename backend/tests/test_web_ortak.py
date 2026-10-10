r"""Ortak panosunun DİL katmanı — `web/ortak/` (OP9) bekçisi.

NEDEN (ölçüldü 2026-10-10): `web/en/partners.html` İngilizce bir ortaklık
programı sunuyor ve girişin arkasında bir "partner panel" vaat ediyor;
pano ise YALNIZ Türkçeydi — `ortak.js`te dil mantığı sıfır,
`toLocaleString('tr-TR')` beş yerde sabit. İngilizce ortak panoya girince
Türkçe görüyordu, vaat tutmuyordu ve hiçbir bekçi kırmızı değildi: `test_sozluk`
ile `test_honesty` HTML sayfalarını tarıyor, panonun metni JS'te yaşıyor.

Katman `web/i/index.html` deseniyle kuruldu: `SOZLUK = {tr: {…}, en: {…}}`,
seçim `?lang=` → `navigator.language` → tr. Bu dosya şunları çiviliyor:

1. İki dilin anahtar kümesi EŞİT. Bir dilde eksik anahtar JS'te hata DEĞİL —
   `t()` anahtarın adını basar, pano "yeşil" görünür.
2. Biçimlendirme yerel ayarı DİLDEN türer; sabit 'tr-TR' kalıntısı yok.
   Kalırsa İngilizce panoda "1.234,50", "28 Eyl" çıkar ve bunu gören tek kişi
   ortaktır.
3. HTML'deki `data-i18n` anahtarları ile JS'teki `T.x` / `t('x')` göndermeleri
   sözlükte VAR; sözlükteki her anahtar da bir yerden OKUNUYOR (okunmayan
   anahtar, çevirisi sessizce bayatlayan anahtardır).
4. Sözlük değerleri `test_sozluk` (kredi/credit) ve `test_honesty` (sınırsız
   sınıfı, sağlık iddiası, NASA) yasaklarından geçer. Ölçüldü: pano "jeton
   paketi" diyordu ve D0 sözlük turunda görülmedi — hiçbir bekçi JS'e
   bakmıyordu.
5. Olgunlaşma gün sayısı sözlükte YAZILI DEĞİL, `OLGUNLASMA_GUN`dan gelir ve o
   sabit `partner_service.MATURATION_DAYS` ile aynı. Bu sabit hiçbir yerde
   pinli değildi (`test_honesty` yalnız iki HTML sayfasını pinliyor).
6. Hata cümleleri panonun KENDİ haritasından geçer, paylaşılan `RY.hataMetni`
   (ry-api.js, yönetim paneliyle ortak, Türkçe sabit) çağrılmaz.

Bir şeyin YOKLUĞUNU arayan bekçi onu ANLATAN yorumu görmemeli (CLAUDE.md §5):
`ortak.js`in başlık yorumu `toLocaleString('tr-TR')` ve `RY.hataMetni`
kelimelerini açıkça anıyor; JS yorumları `_yorumsuz_js` ile atılır.

Çalıştırma:
    .venv\Scripts\python.exe -m pytest tests/test_web_ortak.py -q
"""
from __future__ import annotations

import importlib
import importlib.util
import re
import sys
from pathlib import Path

import pytest

_KOK = Path(__file__).resolve().parents[2]
_JS = _KOK / "web" / "ortak" / "ortak.js"
_HTML = _KOK / "web" / "ortak" / "index.html"
_DILLER = ("tr", "en")

#: Sözlük boyutu tabanı: ayrıştırıcı GERÇEKTEN okuyor mu? Yazıldığı gün
#: (2026-10-10) dil başına 108 anahtar ölçüldü; taban bilerek altında —
#: anahtar birleştirmek meşru, sıfıra inmek bekçinin körlüğüdür.
_EN_AZ_ANAHTAR = 60


def _modul(ad: str):
    """`test_honesty` / `test_sozluk` — yasak listeleri ve JS literal
    ayrıştırıcısı ORADAN. Kopyalanmıyor: kopya sessizce ayrışır
    (`test_sozluk._honesty` ile aynı gerekçe ve aynı yükleme yolu)."""
    try:
        return importlib.import_module(ad)
    except ImportError:
        yol = Path(__file__).with_name(f"{ad}.py")
        spec = importlib.util.spec_from_file_location(ad, yol)
        mod = importlib.util.module_from_spec(spec)
        sys.modules[ad] = mod
        spec.loader.exec_module(mod)
        return mod


def _yorumsuz_js(kaynak: str) -> str:
    """JS yorumlarını boşluğa çevirir; DİZELER ve satır sayısı korunur.

    Naif bir `//`→satır sonu temizliği `'https://rytho.app/r/'` literalini
    de keserdi (dosyada var: `PAYLASIM_TABANI`); `.replace(/"/g, …)`
    içindeki tırnak da dize açmaz. Bu yüzden `test_sozluk._js_literalleri`
    ile aynı küçük durum makinesi — o literalleri döndürür, bu KODU
    (yorumsuz) döndürür; iki ihtiyaç ayrı. Regex literali, önündeki anlamlı
    karakter ayraç/işleçse öyle sayılır (bölme sayı ya da kapanıştan sonra
    gelir). Dişi: `test_ayristiricilarin_DISI_var`.
    """
    cikti: list[str] = []
    i, n = 0, len(kaynak)
    while i < n:
        c = kaynak[i]
        if kaynak.startswith("//", i):
            j = kaynak.find("\n", i)
            j = n if j < 0 else j
            cikti.append(" " * (j - i))
            i = j
        elif kaynak.startswith("/*", i):
            j = kaynak.find("*/", i + 2)
            j = n if j < 0 else j + 2
            cikti.append(re.sub(r"[^\n]", " ", kaynak[i:j]))
            i = j
        elif c in "'\"`":
            j = i + 1
            while j < n and kaynak[j] != c:
                j += 2 if kaynak[j] == "\\" else 1
            j = min(j + 1, n)
            cikti.append(kaynak[i:j])
            i = j
        elif c == "/":
            k = i - 1
            while k >= 0 and kaynak[k] in " \t":
                k -= 1
            if k < 0 or kaynak[k] in "(,=:[!&|?{};\n+-*%<>~^":
                j, sinif = i + 1, False
                while j < n and kaynak[j] != "\n":
                    if kaynak[j] == "\\":
                        j += 2
                        continue
                    if kaynak[j] == "[":
                        sinif = True
                    elif kaynak[j] == "]":
                        sinif = False
                    elif kaynak[j] == "/" and not sinif:
                        break
                    j += 1
                if j < n and kaynak[j] == "/":
                    cikti.append(kaynak[i:j + 1])
                    i = j + 1
                    continue
            cikti.append(c)
            i += 1
        else:
            cikti.append(c)
            i += 1
    return "".join(cikti)


def _kod() -> str:
    return _yorumsuz_js(_JS.read_text(encoding="utf-8"))


def _sozluk_ayristir(kod: str) -> dict[str, dict[str, str]]:
    """`SOZLUK = {tr: {…}, en: {…}}` → {dil: {anahtar: metin}}.

    JS ayrıştırıcı yok; sözleşme GİRİNTİ: `var SOZLUK = {` 2 boşlukta,
    `tr: {` / `en: {` 4'te, anahtar 6'da, değerin devam satırları 8'de
    (`'a ' +` zincirleri). Bir anahtarın metni, satırından bir sonraki
    anahtara kadarki dize literallerinin BİRLEŞİMİ — yasak kelime ve yer
    tutucu o metinde aranır. Girinti bozulursa anahtar görünmez olur ve
    küme testi (eşitlik + taban) onu yakalar; sessiz kalmaz.
    """
    sozluk_mod = _modul("test_sozluk")
    satirlar = kod.split("\n")
    try:
        bas = satirlar.index("  var SOZLUK = {")
    except ValueError:
        raise AssertionError(
            "ortak.js'te `  var SOZLUK = {` satırı yok — sözlük taşındıysa "
            "ya da girintisi değiştiyse bekçi yeniden nişanlanır") from None
    son = next((i for i in range(bas, len(satirlar)) if satirlar[i] == "  };"),
               None)
    assert son is not None, "SOZLUK bloğu `  };` ile kapanmıyor"
    sozluk: dict[str, dict[str, str]] = {}
    dil = anahtar = None
    for satir in satirlar[bas + 1:son]:
        m = re.match(r"^    (tr|en): \{$", satir)
        if m:
            dil, anahtar = m.group(1), None
            sozluk[dil] = {}
            continue
        m = re.match(r"^      ([A-Za-z_]\w*): ", satir)
        if m and dil:
            anahtar = m.group(1)
            assert anahtar not in sozluk[dil], f"{dil}.{anahtar} iki kez"
            sozluk[dil][anahtar] = ""
        if dil and anahtar:
            for _, literal in sozluk_mod._js_literalleri(satir):
                sozluk[dil][anahtar] += literal
    return sozluk


def _sozluk() -> dict[str, dict[str, str]]:
    return _sozluk_ayristir(_kod())


def _html_anahtarlari() -> set[str]:
    """`data-i18n="x"` ve `data-i18n-placeholder="x"` — HTML yorumları
    atılmış hâlde (yorum, özniteliği örnek olarak anabilir)."""
    ham = _modul("test_honesty")._yorumsuz_html(
        _HTML.read_text(encoding="utf-8"))
    return set(re.findall(r'data-i18n(?:-[a-z]+)?="(\w+)"', ham))


def _js_gondermeleri(kod: str) -> set[str]:
    """`T.x`, `t('x'…)` ve `cogul(n, 'tek', 'cok')` anahtarları."""
    bulunan = set(re.findall(r"\bT\.([A-Za-z_]\w*)", kod))
    bulunan |= set(re.findall(r"\bt\('([A-Za-z_]\w*)'", kod))
    for tek, cok in re.findall(r"\bcogul\([^)]*?'(\w+)',\s*'(\w+)'", kod):
        bulunan |= {tek, cok}
    return bulunan


# ---------------------------------------------------------------------------
# (1) İki dil, aynı anahtar kümesi
# ---------------------------------------------------------------------------

def test_iki_dilin_anahtar_kumeleri_esit():
    sozluk = _sozluk()
    assert set(sozluk) == set(_DILLER), (
        f"sözlükte beklenen diller {_DILLER}, bulunan {sorted(sozluk)}")
    for dil in _DILLER:
        assert len(sozluk[dil]) >= _EN_AZ_ANAHTAR, (
            f"{dil}: {len(sozluk[dil])} anahtar — taban {_EN_AZ_ANAHTAR}. Ya "
            f"sözlük küçüldü (taban güncellenir) ya da ayrıştırıcı girintiyi "
            f"okuyamıyor (bekçi kör)")
        bos = [k for k, v in sozluk[dil].items() if not v.strip()]
        assert not bos, f"{dil}: metni boş anahtarlar: {bos}"
    tr, en = set(sozluk["tr"]), set(sozluk["en"])
    assert tr == en, (
        "iki dilin anahtar kümesi ayrışmış — eksik anahtar ekranda anahtar "
        f"ADIYLA görünür, JS hata vermez. Yalnız tr'de: {sorted(tr - en)}; "
        f"yalnız en'de: {sorted(en - tr)}")
    # Yer tutucular da eşit: `{n}` bir dilde varken ötekinde yoksa o dilde
    # sayı hiç basılmaz ve cümle sayısız kalır.
    for anahtar in sorted(tr):
        yt = {d: set(re.findall(r"\{(\w+)\}", sozluk[d][anahtar]))
              for d in _DILLER}
        assert yt["tr"] == yt["en"], (
            f"{anahtar}: yer tutucular ayrışmış tr={sorted(yt['tr'])} "
            f"en={sorted(yt['en'])}")


# ---------------------------------------------------------------------------
# (2) Biçimlendirme yerel ayarı dilden türer
# ---------------------------------------------------------------------------

def test_bicimlendirme_yerel_ayari_dilden_turuyor():
    kod = _kod()
    cagrilar = re.findall(
        r"(?:toLocale(?:Date)?String|Intl\.NumberFormat)\(\s*([^,)]+)", kod)
    # Taban: çağrı GEÇMEK zorunda — biçimlendirme başka bir yola taşınırsa
    # "hepsi YEREL" iddiası boş kümede yeşil kalırdı.
    assert len(cagrilar) >= 4, (
        f"ortak.js'te yalnız {len(cagrilar)} biçimlendirme çağrısı bulundu; "
        "sayı/tarih biçimi taşındıysa bekçi yeniden nişanlanır")
    sapma = [c for c in cagrilar if c.strip() != "YEREL"]
    assert not sapma, (
        f"biçimlendirme çağrısı YEREL yerine sabit yerel ayar alıyor: {sapma} "
        "— İngilizce panoda Türkçe sayı/tarih biçimi çıkar")
    # 'tr-TR' literali YALNIZ YEREL'in tanımlandığı satırda olabilir.
    for no, satir in enumerate(kod.split("\n"), 1):
        if "'tr-TR'" in satir:
            assert "YEREL" in satir, (
                f"ortak.js:{no} sabit 'tr-TR' — yerel ayar dilden türemeli")
    assert re.search(r"var YEREL = lang === 'en' \? '[a-z]{2}-[A-Z]{2}' : 'tr-TR';",
                     kod), "YEREL dilden türemiyor (`lang === 'en' ? … : 'tr-TR'`)"


# ---------------------------------------------------------------------------
# (3) Dil seçimi: ?lang= → tarayıcı → tr
# ---------------------------------------------------------------------------

def test_dil_secimi_sorgu_tarayici_tr_sirasiyla():
    """`web/i/index.html` deseni birebir: sorgu, tarayıcı, tr. Sıra önemli —
    tarayıcı sorgudan önce okunsa `?lang=` ile QA yapılamaz; tr'ye düşüş
    olmasa desteklenmeyen dilde `T` undefined olur ve pano hiç çizilmez."""
    kod = _kod()
    secim = re.search(
        r"var lang = \(params\.get\('lang'\) \|\| navigator\.language \|\| 'tr'\)",
        kod)
    assert secim, "dil seçimi `params.get('lang') || navigator.language || 'tr'` değil"
    assert "if (lang !== 'en') lang = 'tr';" in kod, (
        "desteklenmeyen dil tr'ye düşmüyor — `SOZLUK[lang]` undefined olur")
    assert "document.documentElement.lang = lang;" in kod, (
        "<html lang> seçilen dile çekilmiyor; ekran okuyucu yanlış dille okur")
    assert "var T = SOZLUK[lang];" in kod
    # Pano hiçbir yerden linklenmez; `?lang=` yalnız OKUNUR, bir bağlantıya
    # yazılmaz (CLAUDE.md: adres ortağa elden verilir).
    assert "lang=" not in kod.replace("params.get('lang')", ""), (
        "ortak.js bir bağlantıya `lang=` yazıyor — pano linklenmez, "
        "parametre yalnız okunur")


# ---------------------------------------------------------------------------
# (4) HTML ve JS göndermeleri ↔ sözlük
# ---------------------------------------------------------------------------

def test_html_data_i18n_anahtarlari_sozlukte():
    sozluk = _sozluk()
    html = _html_anahtarlari()
    assert len(html) >= 10, (
        f"index.html'de yalnız {len(html)} data-i18n anahtarı — sabit "
        "metinler JS'ten dolmuyor ya da öznitelik adı değişti")
    for dil in _DILLER:
        eksik = sorted(html - set(sozluk[dil]))
        assert not eksik, (
            f"index.html data-i18n anahtarı {dil} sözlüğünde yok: {eksik} — "
            "o öğe ekranda anahtar adıyla görünür")
    ham = _modul("test_honesty")._yorumsuz_html(_HTML.read_text(encoding="utf-8"))
    assert re.search(r'<title data-i18n="\w+">', ham), (
        "<title> data-i18n taşımıyor — sekme başlığı Türkçe kalır")


def test_js_gondermeleri_sozlukte_ve_her_anahtar_okunuyor():
    sozluk = _sozluk()
    kod = _kod()
    gonderme = _js_gondermeleri(kod)
    assert len(gonderme) >= _EN_AZ_ANAHTAR, (
        f"JS'te yalnız {len(gonderme)} sözlük göndermesi bulundu — desen "
        "(`T.x`, `t('x'`, `cogul(…)`) değiştiyse bekçi yeniden nişanlanır")
    anahtarlar = set(sozluk["tr"])
    yok = sorted(gonderme - anahtarlar)
    assert not yok, (
        f"JS sözlükte olmayan anahtara gönderiyor: {yok} — ekranda anahtar "
        "adı basılır, hata çıkmaz")
    okunmayan = sorted(anahtarlar - gonderme - _html_anahtarlari())
    assert not okunmayan, (
        f"sözlükte okuyucusu olmayan anahtar: {okunmayan} — çevirisi "
        "sessizce bayatlar; ya kullan ya sil")


# ---------------------------------------------------------------------------
# (5) Sözlük değerleri: yasak sözlük ve yasak vaat
# ---------------------------------------------------------------------------

def test_sozluk_degerleri_yasak_sozlugu_ve_vaatleri_tasimiyor():
    """`test_sozluk` ve `test_honesty` HTML sayfalarını tarıyor; panonun
    metni JS'te yaşıyor ve orada "jeton paketi" bir tur boyunca kaldı
    (ölçüldü 2026-10-10). Aynı iki süzgeç burada sözlük DEĞERLERİNE
    uygulanır — ham dosyaya değil: `ortak.js` yorumları yasak kelimeyi
    gerekçesiyle anıyor."""
    sozluk_mod = _modul("test_sozluk")
    honesty = _modul("test_honesty")
    sozluk = _sozluk()
    yasaklar = honesty.TestPazarlamaDili._YASAKLAR
    sapma = []
    for dil in _DILLER:
        for anahtar, metin in sozluk[dil].items():
            h = sozluk_mod._ihlal(metin, metin)
            if h:
                sapma.append(f"{dil}.{anahtar} → {h!r} (sözlük: kredi/credit)")
            kucuk = honesty._turkce_kucult(metin)
            for aranan, neden in yasaklar:
                if aranan in kucuk:
                    sapma.append(f"{dil}.{anahtar} → {aranan!r}: {neden}")
    # Taban: ödül kuralı paketi anıyor; iki dil yeni kelimeyi taşımalı.
    assert "kredi" in honesty._turkce_kucult(sozluk["tr"]["odulP2"])
    assert "credit" in sozluk["en"]["odulP2"]
    assert not sapma, "sözlük değerinde yasak ifade:\n  " + "\n  ".join(sapma)


# ---------------------------------------------------------------------------
# (6) Gün sayısı sabitten gelir, sözlükte yazılı değil
# ---------------------------------------------------------------------------

def test_olgunlasma_gunu_sabitten_geliyor_ve_kodla_ayni():
    honesty = _modul("test_honesty")
    kod = _kod()
    m = re.search(r"var OLGUNLASMA_GUN = (\d+);", kod)
    assert m, "ortak.js'te `var OLGUNLASMA_GUN = N;` yok"
    assert int(m.group(1)) == honesty._OLGUNLASMA_GUNU, (
        f"ortak.js {m.group(1)} gün diyor, `partner_service.MATURATION_DAYS` "
        f"{honesty._OLGUNLASMA_GUNU} — ortağın 'paramı ne zaman alırım' "
        "cevabı koddan sapmış")
    sozluk = _sozluk()
    gun = str(honesty._OLGUNLASMA_GUNU)
    for dil in _DILLER:
        for anahtar in ("bekleyenCumle", "gunSonraKesinlesir"):
            assert "{gun}" in sozluk[dil][anahtar], (
                f"{dil}.{anahtar} gün sayısını {{gun}} ile almıyor")
        yazili = [k for k, v in sozluk[dil].items()
                  if re.search(rf"\b{gun}\b", v)]
        assert not yazili, (
            f"{dil}: gün sayısı sözlükte LİTERAL yazılı: {yazili} — "
            "MATURATION_DAYS değişince bu metin sessizce bayatlar; "
            "`{gun}` yer tutucusu + OLGUNLASMA_GUN kullanılır")


# ---------------------------------------------------------------------------
# (7) Hata cümlesi panonun dilinden geçer
# ---------------------------------------------------------------------------

def test_hata_cumlesi_panonun_dilinden_geciyor():
    """`RY.hataMetni` ry-api.js'te yönetim paneliyle paylaşılan, Türkçe
    sabit bir harita. Pano ondan bir satır bile çağırsa İngilizce ortak
    Türkçe bant görür. YOKLUK bekçisi: yorumlar atılmış koda bakar — başlık
    yorumu `RY.hataMetni`yi adıyla anıyor."""
    kod = _kod()
    assert "RY.hataMetni(" not in kod, (
        "ortak.js paylaşılan Türkçe `RY.hataMetni`yi çağırıyor — "
        "İngilizce panoda Türkçe hata bandı çıkar")
    assert re.search(r"^  function hataMetni\(hata\) \{", kod, re.M), (
        "ortak.js'in kendi `hataMetni(hata)` haritası yok")
    assert "hataMetni(hata)" in kod.replace("function hataMetni(hata)", ""), (
        "yerel `hataMetni` tanımlı ama hiç çağrılmıyor")


def test_ry_api_429_toasti_panonun_haritasindan_geciyor():
    """ry-api.js 429'da toast'ı KENDİ basıyor (`toastBas(...)`) ve metni
    modülün Türkçe `hataMetni`sinden alıyordu — panonun yerel haritası o
    yolu kapatmıyordu, İngilizce ortak tek bir Türkçe toast görürdü (ölçüldü
    2026-10-10). Kanca iki parça ve ikisi de şart: pano `RY.hataMetni`yi
    kaydeder; modül 429'da `(RY.hataMetni || hataMetni)` kullanır VE kendi
    kaydını `RY.hataMetni || hataMetni` ile yapar (ortak.js ry-api.js'ten
    SONRA yükleniyor, ama sıra değişirse ezmesin)."""
    kod = _kod()
    assert re.search(r"^  RY\.hataMetni = hataMetni;", kod, re.M), (
        "ortak.js dil bilen haritasını RY.hataMetni olarak kaydetmiyor")
    api = _yorumsuz_js((_KOK / "web" / "assets" / "ry-api.js").read_text(encoding="utf-8"))
    assert "toastBas((RY.hataMetni || hataMetni)(hata))" in api, (
        "ry-api.js 429 toast'ı sayfanın RY.hataMetni'sinden geçmiyor")
    assert "RY.hataMetni = RY.hataMetni || hataMetni;" in api, (
        "ry-api.js kendi haritasını koşulsuz kaydediyor — sayfanınkini ezer")


# ---------------------------------------------------------------------------
# Dişi: ayrıştırıcılar gerçekten ayırt ediyor mu
# ---------------------------------------------------------------------------

def test_ayristiricilarin_DISI_var():
    """Yorum temizleyici dizeyi/regex'i korur, yorumu siler; sözlük
    ayrıştırıcı girintiden anahtar ve birleşik metin çıkarır. Bu test
    olmasa "ihlal yok" iki sebeple yeşil çıkabilir: dosya temiz olduğu
    için, ya da ayrıştırıcı bir regex'teki tırnağa takılıp dosyanın
    kalanını yorum sandığı için."""
    ornek = (
        "var a = 'https://x/y'; // 'yorum' tr-TR\n"
        "/* blok 'yorum'\n tr-TR */ var b = s.replace(/\"/g, '&quot;');\n"
        "var c = 6 / 2; var d = /\\{(\\w+)\\}/g;\n")
    temiz = _yorumsuz_js(ornek)
    assert "'https://x/y'" in temiz
    assert "'&quot;'" in temiz and "/\\{(\\w+)\\}/g" in temiz
    assert "tr-TR" not in temiz and "yorum" not in temiz
    assert temiz.count("\n") == ornek.count("\n")

    kod = (
        "  var SOZLUK = {\n"
        "    tr: {\n"
        "      a: 'bir ' +\n"
        "        'iki {n}',\n"
        "      b: 'üç'\n"
        "    },\n"
        "    en: {\n"
        "      a: 'one {n}',\n"
        "      b: 'three'\n"
        "    }\n"
        "  };\n")
    assert _sozluk_ayristir(kod) == {
        "tr": {"a": "bir iki {n}", "b": "üç"},
        "en": {"a": "one {n}", "b": "three"}}
    with pytest.raises(AssertionError, match="SOZLUK"):
        _sozluk_ayristir("var baska = 1;\n")

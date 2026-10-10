"""Sözlük bekçisi: kullanıcıya görünen TEK kelime TR "kredi", EN "credit(s)".

NEDEN bu bekçi var (ölçüldü 2026-10-10): uygulama 15 ARB anahtarında
"kredi" derken Türkçe site "jeton", İngilizce site "token", admin paneli
"Jeton", kullanım şartları "Jeton paketleri" ve `docs/store-launch.md`
monetizasyon tablosu "token" diyordu — aynı ürün için dört kelime, hiçbir
test kırmızı değildi. Sahip kararı: kullanıcıya görünen tek kelime
kredi/credit. Makbuzdaki "1000 Jeton" Play Console'daki ürün adıdır
(sahibin konsol görevi, `docs/store-launch.md` §"Mağaza ürün adları"),
depoda değil.

Kelime İKİ başka anlamda meşru ve burada YASAK DEĞİL:

* **Push / kimlik jetonu** (FCM jetonu, ID jetonu, oturum jetonu): standart
  Türkçe karşılık budur, "kredi" denmez. İşareti aynı SATIRDAKİ bağlam
  kelimesi — `_MUAF_PUSH` + `_MUAF_ID`.
* **LLM kullanım sayacı** ("Girdi token", "token × birim fiyat"): Gemini'nin
  faturalandırma birimi, kredi DEĞİL — krediyle adlandırmak ölçüleni yanlış
  adla sunmak olurdu (CLAUDE.md §1). İşareti aynı satırdaki `_MUAF_LLM`.
  Bu muafiyet YALNIZ admin JS'de uygulanır: sayaç yalnız orada var, öteki
  yüzeylerde açık bırakmak kör nokta açardı.

Tasarım notları (her biri bir ölçüme dayanıyor):

* `str.lower()` HİÇ kullanılmıyor (CLAUDE.md §5: "İ".lower() bozuk);
  küçültme `test_honesty._turkce_kucult`.
* Kod tanımlayıcıları kapsam DIŞI: ARB'de anahtarlar değil DEĞERLER
  (`subBuyTokens` anahtarının değeri "Kredi paketi al"), `core.messages`
  ham dosya değil İÇE ALINAN `_MESSAGES` (yorumlar `token_store_screen`
  diyor), admin JS'de yorum ve tanımlayıcı değil DİZE LİTERALLERİ.
* Admin JS'de tek parçalı küçük-harf ASCII literal (`'jeton'` ikon
  anahtarı, `'g-kul-token'` DOM kimliği, `'jeton-yok'` sözlük anahtarı)
  kullanıcıya görünen metin değil koddan koda geçen anahtardır; atlanır.
  Kabul edilen kör nokta: bir etiketi küçük harf tek kelime yazmak.
  Paneldeki etiketler büyük harfle başlıyor (ölçüldü: "Jeton" → "Kredi").
* `bildirimler.js` bütünüyle FCM jetonu görünümü ("Jeton yok", "Temizlenen
  jeton") ve o satırlarda bağlam kelimesi geçmiyor; dosya düzeyinde muaf.
* HTML yorumları eşleşmeden ÖNCE atılır, satır sayısı korunarak — bir
  şeyin yokluğunu arayan bekçi onu anlatan yorumu görmemeli (CLAUDE.md
  §5, iki kez patladı). İki sayfanın yorumu da `TestJetonIddialari` diyor.
* `docs/store-launch.md`'de yalnız DİL ETİKETSİZ çit blokları taranır:
  belgenin kendi geleneğinde komut/konfig blokları etiketli (powershell,
  properties, kotlin), Console'a kopyalanan metin etiketsiz.
* Her yüzeyde TABAN var: yeni kelime gerçekten görülmeli. Yoksa tarama
  kördür ve "ihlal yok" hiçbir şey ölçmez.
"""
from __future__ import annotations

import importlib.util
import io
import json
import re
import sys
from pathlib import Path

import pytest

from core import messages

_KOK = Path(__file__).resolve().parents[2]


def _honesty():
    """`test_honesty` modülü — sayfa listesi ve Türkçe küçültme oradan.

    Kopyalanmıyor: `_SAYFALAR`ın TAM olduğunu orası kanıtlıyor
    (`test_yayindaki_her_sayfa_listede`); bir kopya sessizce ayrışırdı.
    pytest `tests/`i sys.path'e koyar; koymayan içe alma modunda modül
    yoldan yüklenir.
    """
    try:
        import test_honesty
        return test_honesty
    except ImportError:
        yol = Path(__file__).with_name("test_honesty.py")
        spec = importlib.util.spec_from_file_location("test_honesty", yol)
        mod = importlib.util.module_from_spec(spec)
        sys.modules["test_honesty"] = mod
        spec.loader.exec_module(mod)
        return mod


def _kucult(metin: str) -> str:
    return _honesty()._turkce_kucult(metin)


#: Yasak kelime, KÜÇÜLTÜLMÜŞ metinde: "jeton" + her eki (jetonu, jetonlar),
#: "token"/"tokens" TAM kelime — `tokenCostsNote`, `promptTokens`,
#: `rytho_tokens_small` tanımlayıcıları kelime sınırı yüzünden eşleşmez.
_YASAK = re.compile(r"\bjeton|\btokens?\b")

#: Push/kimlik jetonu bağlamı — küçültülmüş satırda aranır.
_MUAF_PUSH = re.compile(r"push|fcm|cihaz|oturum|bildirim|device|session")

#: "ID" AYRI ve HAM satırda, büyük harfle: küçültülünce "ıd" olur ve
#: HTML'deki `id="…"` özniteliğiyle karışırdı — id taşıyan her satır muaf
#: kalır, "jeton paketi" bir `<p id=…>` içinde sessizce geçerdi.
_MUAF_ID = re.compile(r"\bID\b")

#: LLM sayacı bağlamı (yalnız admin JS).
_MUAF_LLM = re.compile(r"girdi|çıktı|prompt|output|maliyet|rollup|kırılım")


def _ihlal(metin: str, baglam: str, *, llm_muaf: bool = False) -> str | None:
    """Metindeki yasak kelime, ya da bağlam onu aklıyorsa None.

    `metin` ölçülen şey (ARB değeri, JS literali, HTML satırı), `baglam`
    muafiyetin arandığı SATIR — "aynı satırda push/FCM/ID… geçiyorsa muaf".
    """
    bulunan = _YASAK.search(_kucult(metin))
    if not bulunan:
        return None
    if _MUAF_PUSH.search(_kucult(baglam)) or _MUAF_ID.search(baglam):
        return None
    if llm_muaf and _MUAF_LLM.search(_kucult(baglam)):
        return None
    return bulunan.group(0)


# ---------------------------------------------------------------------------
# (1) ARB değerleri — uygulamanın kullanıcıya gösterdiği her dize
# ---------------------------------------------------------------------------

_ARB = ("apps/mobile/lib/l10n/app_tr.arb", "apps/mobile/lib/l10n/app_en.arb")

#: Dosya başına taban kelimesi: tarama değerleri gerçekten okuyor mu?
_ARB_TABAN = {"app_tr.arb": "kredi", "app_en.arb": "credit"}


def _arb_degerleri(yol: str) -> list[tuple[str, str, int]]:
    """(anahtar, değer, satır) — `@` meta girdileri ve dize olmayanlar hariç.

    Satır numarası ham dosyadan aranıyor; JSON ayrıştırıcı satır vermez ve
    hata mesajı "hangi satır" demeden işe yaramaz.
    """
    ham = io.open(_KOK / yol, encoding="utf-8").read()
    satirlar = ham.split("\n")
    cikti = []
    for anahtar, deger in json.loads(ham).items():
        if anahtar.startswith("@") or not isinstance(deger, str):
            continue
        satir = next((no for no, s in enumerate(satirlar, 1)
                      if s.lstrip().startswith(f'"{anahtar}"')), 0)
        cikti.append((anahtar, deger, satir))
    return cikti


def test_arb_degerlerinde_eski_sozluk_yok():
    sapma = []
    for yol in _ARB:
        degerler = _arb_degerleri(yol)
        taban = _ARB_TABAN[Path(yol).name]
        assert any(taban in _kucult(d) for _, d, _ in degerler), (
            f"{yol}: hiçbir değer {taban!r} demiyor — ya sözlük yeniden "
            f"değişti (bekçi güncellenir) ya da tarama değerleri okumuyor")
        for anahtar, deger, satir in degerler:
            h = _ihlal(deger, deger)
            if h:
                sapma.append(f"{yol}:{satir} {anahtar} → {h!r}: {deger[:70]!r}")
    assert not sapma, (
        "ARB değerinde eski sözlük var (kullanıcıya görünen tek kelime "
        "kredi/credit):\n  " + "\n  ".join(sapma))


# ---------------------------------------------------------------------------
# (2) core.messages — sunucunun `detail` ile ekrana bastığı metinler
# ---------------------------------------------------------------------------

def test_messages_sozlugunde_eski_sozluk_yok():
    """`_MESSAGES` İÇE ALINARAK ölçülür; ham dosyanın yorumları kapsam dışı."""
    sapma, gorulen = [], {"tr": "", "en": ""}
    for anahtar, diller in messages._MESSAGES.items():
        for dil, metin in diller.items():
            gorulen[dil] = gorulen.get(dil, "") + " " + _kucult(metin)
            h = _ihlal(metin, metin)
            if h:
                sapma.append(f"core.messages[{anahtar!r}][{dil}] → {h!r}: "
                             f"{metin[:70]!r}")
    # Taban: cüzdan mesajı iki dilde yeni kelimeyi taşıyor olmalı.
    assert "kredi" in gorulen["tr"] and "credit" in gorulen["en"], (
        "core.messages hiç kredi/credit demiyor — tarama kör ya da sözlük "
        "yine değişti")
    assert not sapma, (
        "core.messages değerinde eski sözlük var; istemci bu metni OLDUĞU "
        "GİBİ ekrana basıyor:\n  " + "\n  ".join(sapma))


# ---------------------------------------------------------------------------
# (3) Yayındaki HTML sayfaları — test_honesty'nin listesi
# ---------------------------------------------------------------------------

def _yorumsuz_html_satirlar(metin: str) -> str:
    """HTML yorumlarını boşluğa çevirir, SATIR SAYISINI korur."""
    return re.sub(r"<!--.*?-->",
                  lambda m: re.sub(r"[^\n]", " ", m.group(0)),
                  metin, flags=re.S)


def test_yayindaki_sayfalarda_eski_sozluk_yok():
    sayfalar = _honesty().TestPazarlamaDili._SAYFALAR
    sapma = []
    for yol in sayfalar:
        ham = (_KOK / yol).read_text(encoding="utf-8")
        for no, satir in enumerate(_yorumsuz_html_satirlar(ham).split("\n"), 1):
            h = _ihlal(satir, satir)
            if h:
                sapma.append(f"{yol}:{no} → {h!r}: {satir.strip()[:80]!r}")
    # Taban: iki ana sayfa yeni kelimeyi taşıyor (yorumlar atılmış hâlde).
    for yol, kelime in (("web/index.html", "kredi"),
                        ("web/en/index.html", "credit")):
        govde = _kucult(_yorumsuz_html_satirlar(
            (_KOK / yol).read_text(encoding="utf-8")))
        assert kelime in govde, (
            f"{yol} hiç {kelime!r} demiyor — fiyat panosu yeniden mi "
            f"yazıldı? Bekçi hiçbir şey ölçmez olur.")
    assert not sapma, (
        "Yayındaki sayfada eski sözlük var (push/FCM/ID jetonu aynı satırda "
        "anılmadıkça yasak):\n  " + "\n  ".join(sapma))


# ---------------------------------------------------------------------------
# (4) Admin paneli — yalnız dize literalleri
# ---------------------------------------------------------------------------

_ADMIN = "web/rytho-admin"

#: Bütünüyle FCM jetonu olan görünüm; satır düzeyi muafiyet orada yetmiyor
#: ("Jeton yok", "Temizlenen jeton" satırlarında bağlam kelimesi yok).
_PUSH_DOSYALARI = {"web/rytho-admin/gorunumler/bildirimler.js"}

#: Koddan koda geçen anahtar: tek parça, boşluksuz, küçük harf ASCII.
_ANAHTAR_GIBI = re.compile(r"^[a-z0-9_.#/\-]+$")


def _js_literalleri(kaynak: str) -> list[tuple[int, str]]:
    """(başladığı satır, içerik) — yorumlar ve regex literalleri atlanır.

    Küçük bir durum makinesi; regex yerine, çünkü `'https://…'` içindeki
    `//` yorum değil ve `.replace(/'/g, …)` içindeki tırnak dize açmaz
    (`bilesenler.js:26`, ölçüldü). Regex literali, önündeki anlamlı
    karakter bir ayraç/işleçse öyle sayılır (bölme işleci sayı ya da
    kapanış parantezinden sonra gelir). Dişi: aşağıdaki DISI testi.
    """
    cikti: list[tuple[int, str]] = []
    i, n, satir = 0, len(kaynak), 1
    while i < n:
        c = kaynak[i]
        if c == "\n":
            satir += 1
            i += 1
        elif kaynak.startswith("//", i):
            j = kaynak.find("\n", i)
            i = n if j < 0 else j
        elif kaynak.startswith("/*", i):
            j = kaynak.find("*/", i + 2)
            j = n if j < 0 else j + 2
            satir += kaynak.count("\n", i, j)
            i = j
        elif c in "'\"`":
            j, parca = i + 1, []
            while j < n and kaynak[j] != c:
                if kaynak[j] == "\\" and j + 1 < n:
                    parca.append(kaynak[j + 1])
                    j += 2
                else:
                    parca.append(kaynak[j])
                    j += 1
            metin = "".join(parca)
            cikti.append((satir, metin))
            satir += kaynak.count("\n", i, j)
            i = j + 1
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
                    i = j + 1
                    continue
            i += 1
        else:
            i += 1
    return cikti


def test_js_literal_ayristiricisinin_DISI_var():
    """Ayrıştırıcı yorumu, URL'yi, kaçışı ve tırnaklı regex'i doğru ayırır.

    Bu test olmasa "admin panelinde ihlal yok" iki sebeple doğru çıkabilir:
    panel temiz olduğu için, ya da ayrıştırıcı bir regex'teki tırnağa
    takılıp dosyanın kalanını tek bir sahte literal sandığı için.
    """
    ornek = (
        "var a = 'x // yorum değil'; // 'yorum'\n"
        "/* 'blok\n"
        "yorum' */ var b = \"it's\";\n"
        "var c = 'kaç\\'ım'; var d = s.replace(/'/g, '&#39;'); var e = 6 / 2;\n"
        "var f = `şablon ${x}`;"
    )
    assert _js_literalleri(ornek) == [
        (1, "x // yorum değil"), (3, "it's"), (4, "kaç'ım"), (4, "&#39;"),
        (5, "şablon ${x}")]


def _admin_dosyalari() -> list[Path]:
    # Ortak panosunun JS sözlüğü de kullanıcı yüzeyi: "jeton paketi" tam bu
    # tarama dışında kaldığı için D0'da görülmedi (ölçüldü 2026-10-10).
    return sorted((_KOK / _ADMIN).rglob("*.js")) + [_KOK / "web" / "ortak" / "ortak.js"]


def test_admin_paneli_dizelerinde_eski_sozluk_yok():
    for muaf in _PUSH_DOSYALARI:
        assert (_KOK / muaf).exists(), (
            f"{muaf} yok: dosya düzeyi muafiyet boşa işaret ediyor — "
            f"taşındıysa güncellenir, silindiyse muafiyet de silinir")
    sapma, kredi_gorulen = [], False
    for yol in _admin_dosyalari():
        goreli = yol.relative_to(_KOK).as_posix()
        if goreli in _PUSH_DOSYALARI:
            continue
        kaynak = yol.read_text(encoding="utf-8")
        satirlar = kaynak.split("\n")
        for no, literal in _js_literalleri(kaynak):
            if _ANAHTAR_GIBI.match(literal):
                continue
            if "kredi" in _kucult(literal):
                kredi_gorulen = True
            h = _ihlal(literal, satirlar[no - 1], llm_muaf=True)
            if h:
                sapma.append(f"{goreli}:{no} → {h!r}: {literal[:70]!r}")
    assert kredi_gorulen, (
        "admin panelinde hiçbir literal 'kredi' demiyor — ayrıştırıcı "
        "literal bulmuyor ya da sözlük yine değişti")
    assert not sapma, (
        "Admin paneli literalinde eski sözlük var. Alan etiketi 'Jeton' → "
        "'Kredi'; push/FCM/ID jetonu ya da LLM sayacı (girdi/çıktı token) "
        "ise aynı satırda bağlam kelimesi bulunmalı:\n  "
        + "\n  ".join(sapma))


# ---------------------------------------------------------------------------
# (5) docs/store-launch.md — Console'a kopyalanan metin blokları
# ---------------------------------------------------------------------------

_MAGAZA = "docs/store-launch.md"


def _magaza_bloklari() -> list[tuple[int, str]]:
    """Dil etiketsiz ``` çit bloklarının (satır no, satır) çiftleri."""
    cikti, icinde, komut = [], False, False
    metin = io.open(_KOK / _MAGAZA, encoding="utf-8").read()
    for no, satir in enumerate(metin.split("\n"), 1):
        if satir.startswith("```"):
            if not icinde:
                icinde, komut = True, satir.strip() != "```"
            else:
                icinde = False
            continue
        if icinde and not komut:
            cikti.append((no, satir))
    return cikti


def test_magaza_metni_bloklarinda_eski_sozluk_yok():
    bloklar = _magaza_bloklari()
    govde = "\n".join(s for _, s in bloklar)
    # Taban: iki dilin Rytho+ paragrafı kapsamda — kredi iddiası orada.
    for capa in ("RYTHO+ (aylık)", "RYTHO+ (monthly)"):
        assert capa in govde, (
            f"{_MAGAZA}: {capa!r} paragrafı etiketsiz çit bloğunda değil — "
            f"mağaza metni taşındıysa `_magaza_bloklari` yeniden nişanlanır")
    sapma = [f"{_MAGAZA}:{no} → {h!r}: {s.strip()[:80]!r}"
             for no, s in bloklar if (h := _ihlal(s, s))]
    assert not sapma, (
        "Play Console'a KOPYALANAN mağaza metninde eski sözlük var; bu metin "
        "mağaza listesine girer ve düzeltmesi yeni bir inceleme turudur:\n  "
        + "\n  ".join(sapma))


# ---------------------------------------------------------------------------
# Dişi testleri — muafiyet ve tarama gerçekten ayırt ediyor mu
# ---------------------------------------------------------------------------

def test_muafiyetin_DISI_var():
    """Muafiyet push/ID/LLM bağlamını aklar, düz ihlali aklamaz.

    Üç paket "mutasyonların hepsi kırmızı" dedi, minimal mutasyonla
    sınandığında kör bekçiler çıktı (test_honesty doktrini) — bu yüzden
    her muafiyet dalı ve her yasak biçimi burada tek tek ölçülüyor.
    """
    push = "failedPushesToday: ['Başarısız push (bugün)', 'geçersiz jeton'],"
    assert _ihlal("geçersiz jeton", push) is None
    assert _ihlal("ortağın ID jetonu yenilenene kadar",
                  "ortağın ID jetonu yenilenene kadar") is None
    # Küçük harfli `id=` ÖZNİTELİĞİ aklamaz.
    assert _ihlal("jeton paketi", '<p id="x">jeton paketi</p>') == "jeton"
    # LLM sayacı yalnız admin modunda muaf.
    satir = "ad: 'Girdi token', deger: b.sayi(toplam.promptTokens)"
    assert _ihlal("Girdi token", satir, llm_muaf=True) is None
    assert _ihlal("Girdi token", satir) == "token"
    # Düz ihlaller, iki dil ve büyük harf (str.lower değil).
    assert _ihlal("Aylık 100 jeton hakkı", "Aylık 100 jeton hakkı<br>") == "jeton"
    assert _ihlal("100 tokens every month", "100 tokens every month") == "tokens"
    assert _ihlal("JETON PAKETİ", "JETON PAKETİ") == "jeton"
    # Tanımlayıcılar ve yeni sözlük eşleşmez.
    for temiz in ("tokenCostsNote", "promptTokens", "rytho_tokens_small",
                  "Kredi Mağazası", "100 AI credits a month"):
        assert _ihlal(temiz, temiz) is None, temiz


def test_arb_ve_messages_taramasinin_DISI_var(monkeypatch):
    """İki yüzeyin bekçisi BELLEKTE mutasyonla sınanır.

    Diske değil: `app_tr.arb` ve `messages.py` bu turda başka paketlerin
    dosyası ve ajanlar aynı depoda çalışıyor — diske inen geçici bir
    mutasyon başka bir ajanın yazısını ezebilirdi (emsal:
    `test_honesty.test_bedel_kablosu_capasinin_DISI_var`).
    """
    sahte = dict(messages._MESSAGES)
    sahte["olcum.mesaji"] = {"tr": "Bakiyen 3 jeton.", "en": "ok"}
    monkeypatch.setattr(messages, "_MESSAGES", sahte)
    with pytest.raises(AssertionError, match="olcum.mesaji"):
        test_messages_sozlugunde_eski_sozluk_yok()

    gercek = _arb_degerleri

    def sahte_arb(yol: str):
        return gercek(yol) + [("olcumAnahtari", "{count} jeton", 0)]

    monkeypatch.setattr(sys.modules[__name__], "_arb_degerleri", sahte_arb)
    with pytest.raises(AssertionError, match="olcumAnahtari"):
        test_arb_degerlerinde_eski_sozluk_yok()

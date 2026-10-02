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

Dosya büyüdü; bugün DÖRT konu var ve hepsi aynı sınıf kusurun örneği
("bir sunucu gerçeği, onu gösteren yüzeyden sessizce ayrışıyor"):

1. **Aylık hak** — yukarıdaki kalıplar; belgeler + paywall dizesi
   `MONTHLY_TOKEN_ALLOWANCE` ile aynı sayıyı söyler.
2. **Özellik başına bedel** — `/billing/wallet` yanıtı `TOKEN_COSTS`
   tablosunu olduğu gibi taşır. Mağaza ekranındaki bedel satırı artık o
   haritadan üretiliyor; istemci ucu `apps/mobile/test/bedel_satiri_test.dart`.
3. **Konsola elle girilen ürün adları** — tam tablo TEK belgede durur,
   ikinci belge oraya işaret eder ve onunla çelişmez.
4. **Maliyet belgesindeki "bugünkü bedel" sütunu** — `docs/maliyet-calismasi.md`
   §6l'nin bedel/marj tablosu `TOKEN_COSTS` ile aynı sayıyı söyler. Bu sütun
   sahibin bedel kararının dayanağı; bedel değişip tablo kalırsa karar BAYAT
   bir sayıya dayanır.
"""
from __future__ import annotations

import io
import json
import re
from pathlib import Path

import pytest

from core import wallet
from core.wallet import MONTHLY_TOKEN_ALLOWANCE, TOKEN_COSTS

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


# ---------------------------------------------------------------------------
# Özellik başına bedel: ekrana giden zincirin SUNUCU ucu (B1)
# ---------------------------------------------------------------------------
#
# NEDEN burada: bu dosyanın konusu "bir sunucu sabiti ile onu EKRANDA/METİNDE
# gösteren yüzey arasındaki sessiz ayrışma". Aylık hak (yukarısı) o sınıfın
# bir örneği, özellik bedelleri ötekisi.
#
# Mağazadaki bedel satırı artık sunucudan geliyor (bkz.
# `apps/mobile/.../token_store_screen.dart` → `bedelSatiri`, bekçisi
# `apps/mobile/test/bedel_satiri_test.dart`). Ama o bekçi zincirin yalnız
# SON iki halkasını ölçüyor: "istemci `costs` haritasını kullanıyor mu".
# İlk halka burada çivileniyor: harita gerçekten `TOKEN_COSTS` mü, ve
# yanıt modeli onu geçiriyor mu? Bu halka koparsa harita boş gelir,
# istemci sessizce şablona düşer ve "iki kaynak" hâli geri gelir —
# üstelik hiçbir test kırmızı olmadan.

def test_cuzdan_yaniti_TOKEN_COSTS_tablosunu_OLDUGU_GIBI_tasir():
    """`get_wallet` bedel tablosunu süzmeden/yeniden adlandırmadan verir."""
    cuzdan = wallet.get_wallet("bekci-uid")
    assert cuzdan["costs"] == TOKEN_COSTS, (
        "/billing/wallet yanıtındaki `costs` artık TOKEN_COSTS değil. "
        "Mağaza ekranındaki bedel satırı bu haritadan üretiliyor; harita "
        "sapınca ekran ya yanlış sayı gösterir ya da şablona düşüp elle "
        "yazılmış dizeye geri döner (bedel gerçeğinin İKİNCİ kaynağı).")
    # Kopya olmalı: çağıranın eline canlı tabloyu vermek, bir yanıt
    # katmanının kazara tabloyu DEĞİŞTİRMESİNE kapı açardı.
    assert cuzdan["costs"] is not TOKEN_COSTS


def test_cuzdan_ucu_bedelleri_YANITA_koyuyor():
    """Uç katmanı haritayı düşürmüyor.

    `get_wallet` doğru veriyi üretse de yanıt modeli alanı taşımazsa
    istemciye hiç ulaşmaz. Kaynaktan ölçülüyor çünkü uç kimlik
    gerektiriyor ve bu dosyanın derdi taşıma değil ALAN.
    """
    kaynak = io.open(_KOK / "backend/api/billing.py", encoding="utf-8").read()
    assert re.search(r"costs:\s*dict\[str,\s*int\]", kaynak), (
        "WalletStatus yanıt modelinde `costs` alanı yok: istemci bedelleri "
        "hiç görmez ve mağaza satırı şablona düşer")
    assert re.search(r'costs\s*=\s*cuzdan\["costs"\]', kaynak), (
        "Yanıt `costs`u `get_wallet` çıktısından doldurmuyor")


#: Ücretsiz katman uyarısındaki DENKLİK: "N kredi = M sohbet mesajı".
#: Çapa tek bir Türkçe kelimeye BAĞLANMIYOR — iki dilin ARB'si ayrı
#: kalıpla aranıyor ve aşağıdaki bekçi İKİSİNDEN de eşleşme istiyor;
#: kalıplar kelime sınırına bağlı (`\b`), çünkü alt dize eşleşmesi bu
#: depoda yanlış pozitif üretiyor. `lower()` HİÇ kullanılmıyor: Türkçe
#: kıvrımı bozuk ve burada gereği de yok, sayı karşılaştırması tam.
_DENKLIK = {
    "app_tr.arb": re.compile(r"(\d+)\s+kredi\s*=\s*(\d+)\s+sohbet\b"),
    "app_en.arb": re.compile(r"(\d+)\s+credits?\s*=\s*(\d+)\s+chat\b"),
}


def test_ucretsiz_katman_uyarisi_SOHBET_BEDELIYLE_tutarli():
    """Aynı ekrandaki İKİNCİ bedel iddiası da `TOKEN_COSTS` ile tutarlı.

    NEDEN eklendi (ölçüldü 2026-10-02, doğrulama turu): B1 mağazadaki bedel
    satırını (`tokenCostsNote`) sunucudan türetti, ama AYNI ekran
    (`token_store_screen.dart` → `_PaketlerPlusaOzel`) ücretsiz katman
    uyarısını da çiziyor ve o cümle "1 kredi = 1 sohbet mesajı" diyor —
    yani `TOKEN_COSTS["chat"]` değerini elle tekrarlıyor. Depoda bu cümleyi
    çivileyen hiçbir bekçi yoktu (`backend/tests` + `apps/mobile/test`
    taraması boş döndü), yani B1'in kapattığı kusur aynı yüzeyde İKİNCİ bir
    kopya olarak duruyordu.

    NEDEN bu satır `bedelSatiri` gibi SUNUCUDAN üretilmiyor: cümledeki ilk
    sayı bir bedel DEĞİL, BİRİM ("1 kredi"). Konuma bağlı sayı değiştirme
    onu da ezer ve "7 kredi = 7 sohbet mesajı" gibi bir yalan üretirdi —
    bayat sayıdan kötü. Elde kalan doğru araç, ayrışmayı SESSİZ olmaktan
    çıkarmak: bedel değişirse bu bekçi kırmızı olur ve çeviri cümlesinin
    yeniden yazılması gerektiğini söyler.

    İddia ORAN olarak yazılı (N kredi = M mesaj → N == chat × M), tek bir
    "1" beklentisi olarak değil: cümle "2 kredi = 1 sohbet mesajı" diye
    yeniden yazılırsa bekçi haklı olarak yeşil kalır.
    """
    chat = TOKEN_COSTS["chat"]
    for dosya, kalip in _DENKLIK.items():
        yol = _KOK / "apps" / "mobile" / "lib" / "l10n" / dosya
        cumle = json.loads(io.open(yol, encoding="utf-8").read())[
            "tokenFreeTierWarnBody"]
        eslesmeler = kalip.findall(cumle)
        # Çapanın KENDİSİ de ölçülüyor: cümle yeniden yazılıp kalıbın
        # dışına çıkarsa bekçi SESSİZCE hiçbir şey ölçmez olurdu.
        assert eslesmeler, (
            f"{dosya}: tokenFreeTierWarnBody artık 'N kredi = M sohbet "
            f"mesajı' biçiminde değil ({cumle[:60]!r}…). Cümle yeniden "
            f"yazıldıysa bu bekçi de güncellenir; yoksa ekrandaki bedel "
            f"iddiası ölçüsüz kalır.")
        for kredi, mesaj in eslesmeler:
            assert int(kredi) == chat * int(mesaj), (
                f"{dosya}: uyarı '{kredi} kredi = {mesaj} sohbet mesajı' "
                f"diyor ama TOKEN_COSTS['chat'] = {chat}. Kredi Mağazası "
                f"ekranı aynı sayfada iki ayrı bedel gerçeği gösteriyor; "
                f"bu cümle `lib/l10n/app_*.arb` içinde elle yazılı ve "
                f"koddan türetilemiyor (ilk sayı bedel değil BİRİM).")



# ---------------------------------------------------------------------------
# Konsola ELLE girilen ürün adları: kanonik tablo TEK belgede (B5)
# ---------------------------------------------------------------------------
#
# NEDEN (ölçüldü): Play Console'daki ürün adı **makbuza basılıyor** ve paket
# kimliği tanınmazsa `product.title` olarak uygulamanın İÇİNDE görünüyor.
# O alana hangi metnin girileceğini iki belge birden yazdırıyordu ve ikisi
# ayrı şey diyordu: `docs/konsol-gorevleri.md` bir tur boyunca "100 Token",
# `docs/store-launch.md` ise "100 AI Kredisi". "Token/Jeton" kelimesi
# kullanıcıya gösterilen sözlükten R2-F2 kararıyla ÇIKARILDI, yani yanlış
# kopya izlenirse makbuzda uygulamanın hiç kullanmadığı bir kelime kalır.
#
# Belgeler bu turda düzeltildi (ikinci belge artık kanonik tabloya işaret
# ediyor) ama düzeltmeyi çivileyen bir bekçi YOKTU — yani ayrışma sessizce
# geri gelebilirdi. Ürün adları koddan türetilemiyor (mağaza konsolunda
# yaşıyorlar), bu yüzden ölçülebilen tek şey TEKLİK: tam tablo bir yerde
# durur, öteki belgeler oraya işaret eder ve ONUNLA ÇELİŞMEZ.

#: Kanonik tablonun yaşadığı belge.
_KANONIK = "docs/store-launch.md"

#: Tablo satırı: `| \`kimlik\` | Ad (TR) | Ad (EN) |`. Eşleşme SATIR
#: YAPISINA bağlı, serbest metne değil — bu bekçi bir şeyin YOKLUĞUNU da
#: arıyor (tablo ikinci bir belgede durmasın) ve ayrışmayı ANLATAN prose
#: aynı belgede yaşıyor. Prose tablo satırı olmadığı için kapsama hiç
#: girmiyor; blockquote notları ayrıca `_canli_metin` ile boşaltılıyor.
_TABLO_SATIRI = re.compile(
    r"^\|\s*`(rytho_[a-z_]+)`\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*$",
    re.M)

#: Konsola girilecek ürün kimlikleri — tablonun TAM olması bununla ölçülür.
_URUN_KIMLIKLERI = {"rytho_plus_monthly", "rytho_tokens_small",
                    "rytho_tokens_medium", "rytho_tokens_large"}

#: Satır içinde çift tırnaklı metin.
_ALINTI = re.compile(r'"([^"\n]{1,60})"')

#: "Ürün ADI gibi duran" alıntı: SAYIYLA başlıyor **ve** birim kelimesini
#: taşıyor. İki koşul birden, çünkü tek başına hiçbiri yetmiyor — ölçüldü
#: (2026-10-02, `docs/*.md` taraması): sayıyla başlayan masum alıntılar
#: gerçekten var (`docs/test-raporu.md` "3 gün ücretsiz, sonra ₺149,99",
#: `docs/ortaklik-programi.md` "2 Ağustos 2026"), birim kelimesi de ad
#: olmayan cümlelerde geçiyor.
#:
#: ⚠️ `re.I`nin gerekçesi bir tur boyunca YANLIŞ yazılıydı ("kalıptaki
#: kelimelerde Türkçe'ye özgü harf yok, yani kıvrım ASCII'de kalıyor").
#: Ölçüm bunu yalanladı: Python'un `re.I`si Unicode katlama yapıyor ve
#: `re.match("i", "ı", re.I)` ile `re.match("i", "İ", re.I)` İKİSİ DE
#: True — yani kalıp ASCII'de KALMIYOR, ASCII'den GENİŞ. Kalıbın işi
#: "bu alıntı ad gibi mi" sorusuna evet/hayır demek, yani geniş olması
#: GÜVENLİ yön: "100 KREDİSİ" de "100 kredısi" de kapsama girer, bir
#: sapma bu yüzden KAÇMAZ. Daraltma olsaydı kusur sessizce geçerdi.
#: Türkçe tuzağının gerçek yeri eşitlik karşılaştırması olurdu (CLAUDE.md
#: §5) ve bu bekçi orada `lower()` HİÇ kullanmıyor: kanonik adlarla
#: karşılaştırma tam dize eşitliğiyle yapılıyor. Kelime sınırları `\b` ile
#: bağlı: alt dize eşleşmesi yanlış pozitif üretirdi.
_URUN_ADI_GIBI = re.compile(
    r"^\d+\s+.*\b(?:Kredi(?:si|leri)?|Credits?|Token(?:s|lar)?|"
    r"Jeton(?:lar)?)\b", re.I)


def _kanonik_adlar() -> dict[str, tuple[str, str]]:
    """Kanonik belgedeki (kimlik -> (TR ad, EN ad)) tablosu."""
    metin = _canli_metin(_KOK / _KANONIK)
    return {k: (tr, en) for k, tr, en in _TABLO_SATIRI.findall(metin)}


def test_kanonik_urun_adi_tablosu_YALNIZ_bir_belgede():
    """Tam tablo (kimlik + TR + EN) ikinci bir belgede DURAMAZ.

    Taban da burada: tablo kanonik belgede DÖRT ürünün hepsini sayıyor
    olmak zorunda. Yalnız "ikinci kopya yok" demek yetmezdi — tablo
    silinse ya da kısalsa bekçi sessizce yeşil kalır, üstelik öteki
    belgelerin işaret ettiği yer boşalmış olurdu.
    """
    adlar = _kanonik_adlar()
    assert set(adlar) == _URUN_KIMLIKLERI, (
        f"{_KANONIK} içindeki ürün adı tablosu eksik ya da kaymış "
        f"(bulunan: {sorted(adlar)}). Bu tablo konsola ELLE girilen "
        f"metnin tek kaynağı; `docs/konsol-gorevleri.md` buraya işaret "
        f"ediyor.")

    kopyalar = []
    for yol in sorted((_KOK / "docs").glob("*.md")):
        if f"docs/{yol.name}" == _KANONIK:
            continue
        for kimlik, _tr, _en in _TABLO_SATIRI.findall(_canli_metin(yol)):
            kopyalar.append(f"docs/{yol.name}: {kimlik}")
    assert not kopyalar, (
        "Ürün adı tablosu İKİNCİ bir belgede de duruyor:\n  "
        + "\n  ".join(kopyalar)
        + f"\nAynı Console alanına iki belge iki ayrı metin yazdırır ve "
          f"ayrışma sessiz olur (bu bir tur boyunca yaşandı: '100 Token' "
          f"vs '100 AI Kredisi'). Tam tablo yalnız {_KANONIK} içinde "
          f"durur; öteki belge oraya İŞARET eder.")


def test_ikinci_belgedeki_urun_adlari_kanonikle_CELISMEZ():
    """Kanonik olmayan belgedeki ürün adı alıntıları tabloyla aynı metni söyler.

    Tabloyu tek yere indirmek yetmiyor: ikinci belge adım adım anlatırken
    adı yine yazıyor (Console'da doldurulacak alan o). Ölçülen hâl bugün
    tutarlı; bu bekçi ayrışmanın GERİ GELMESİNİ yakalıyor.

    Kapsam SATIR BAŞINA daraltıldı — yalnız bir ürün kimliği ANAN satırdaki
    alıntılar okunuyor. Gerekçe bu depoda iki kez patlayan tuzak: bir şeyin
    yokluğunu arayan bekçi, onu ANLATAN metni kusur sanıyor. Aynı belgede
    "bu belge bir tur boyunca '100 Token' yazdırıyordu" diyen bir cümle var
    ve o satırda kimlik geçmiyor; kapsam dışı kalması tesadüf değil, bu
    bekçinin tasarımı (ölçüldü: o alıntı `_URUN_ADI_GIBI`ye UYUYOR, yani
    kapsam daralmasa bekçi kendi anlattığı kusura takılırdı).

    Kabul kümesi TR **ve** EN adların İKİSİNİ birden taşıyor. Yalnız TR
    yazılmıştı ve bu ölçülmüş bir yanlış pozitif kapısıydı: aynı Console
    alanının İngilizce karşılığı da belgeye yazılabilir ve kanonik tabloda
    DOĞRU hâliyle duruyor olmasına rağmen sapma sayılırdı. Kalıba uyan
    böyle bir alıntı depoda bugün de var (`docs/maliyet-calismasi.md`
    "100 AI credits a month"); bugün kapsam dışı çünkü satırında kimlik
    geçmiyor, ama o satıra bir kimlik eklenmesi bekçiyi haksız yere
    kırmızıya çevirirdi.

    ⚠️ SINIRI ölçüldü: `_canli_metin` blockquote satırlarını BOŞALTIYOR
    (gerekçe yukarıda, aylık hak bölümünde: `> ` ile başlayan satır bu
    depoda "bir tur boyunca yanlıştı" notudur). Dolayısıyla Console'a
    girilecek adı bir uyarı kutusunun İÇİNE yazan bir düzenleme bu
    bekçinin görüş alanına girmez. Mutasyonla doğrulandı: ad satırı
    blockquote'a taşınıp bozulduğunda test YEŞİL kalıyor. Bugünkü
    belgelerde adı yazan hiçbir adım blockquote'ta değil ve bu sınır
    bilerek kabul edildi — alternatifi, kusuru ANLATAN notları kusur
    saymaktı.
    """
    kanonik = {ad for ikili in _kanonik_adlar().values() for ad in ikili}
    assert kanonik, "kanonik tablo okunamadı: bekçi kör kalırdı"

    sapma = []
    for yol in sorted((_KOK / "docs").glob("*.md")):
        if f"docs/{yol.name}" == _KANONIK:
            continue
        satirlar = _canli_metin(yol).split("\n")
        for no, satir in enumerate(satirlar, 1):
            if not re.search(r"`rytho_[a-z_]+`", satir):
                continue
            for alinti in _ALINTI.findall(satir):
                if _URUN_ADI_GIBI.match(alinti) and alinti not in kanonik:
                    sapma.append(f"docs/{yol.name}:{no} {alinti!r}")
    assert not sapma, (
        "Belgedeki ürün adı kanonik tablodan saptı:\n  "
        + "\n  ".join(sapma)
        + f"\nAd makbuza basılıyor ve paket kimliği tanınmazsa uygulamanın "
          f"İÇİNDE görünüyor. Kanonik metin {_KANONIK} tablosunda; "
          f"değiştiyse ikinci belge de birlikte düzeltilir "
          f"(kabul edilen adlar: {sorted(kanonik)}).")


def test_ikinci_belge_kanonik_belgeyi_ANIYOR():
    """İşaret, ürün kimliklerinin anıldığı BÖLÜMÜN içinde durmak zorunda.

    Belgenin herhangi bir yerinde `store-launch.md` aramak yetmezdi: o ad
    belgede başka gerekçelerle de geçebilir ve işaret, adı yazdıran adımdan
    kopuk kaldığı an kimse onu okumaz. Çapa tek bir Türkçe kelimeye
    (ör. "kanonik") BAĞLANMIYOR — iki bağımsız işaret birlikte aranıyor:
    bölüm ürün kimliklerini anıyor **ve** aynı bölüm kanonik belgenin
    YOLUNU veriyor.

    ⚠️ Bu bacağın SINIRI mutasyonla ölçüldü ve burada yazılı duruyor:
    bölümdeki kanonik yol geçişlerinden yalnız BİRİNİ silmek bekçiyi
    kırmızıya çevirmiyor, çünkü aynı bölümde ayrışmayı ANLATAN cümle de
    yolu anıyor. Yani bu bacak "okuyucu kanonik tabloya YÖNLENDİRİLİYOR"
    değil, "bölüm kanonik belgeyi HÂLÂ ANIYOR" diyor — fazlasını iddia
    etmesin. Asıl koruma öteki iki bacakta: tam tablo ikinci belgede
    duramaz ve yazılı adlar tabloyla çelişemez.

    Bu yüzden testin ADI da daraltıldı (doğrulama turu, 2026-10-02): eski
    ad `..._kanonik_tabloya_ISARET_ediyor` idi ve docstring'inin tam
    tersini vaat ediyordu. Mutasyon yeniden koşturuldu: GERÇEK işaret
    cümlesi ("…kanonik olarak store-launch.md'deki tabloda") silinip
    yalnız ayrışmayı ANLATAN cümle bırakıldığında takım YEŞİL kalıyor,
    iki geçiş birden silindiğinde kırmızı oluyor. Ölçülen şey "anıyor",
    vaat edilen şey "yönlendiriyor"du — ölçülen yanlış adla sunulmaz, ad
    ölçülene çekildi.

    Kapsam ölçüm sonrası DARALTILDI. Eski hâli "kimlik anan **ve içinde
    HERHANGİ bir alıntı bulunan** bölüm" diyordu ve bu ölçülmüş bir yanlış
    kırmızı kapısıydı: bölümün alıntısı bir hata mesajı ya da bir ortam
    değişkeni de olabilir, o bölümün Console'a ad yazdırmakla hiç ilgisi
    olmaz ama bekçi ondan da kanonik yola işaret etmesini isterdi
    (mutasyon sınavında birebir bu oldu — bir tablo satırı belgenin
    sonuna düştüğünde bu bacak, ilgisiz `2c. RevenueCat paneli` bölümü
    yüzünden kırmızıya döndü). Ölçülen ad: kapsam "ÜRÜN ADI YAZDIRAN
    bölüm", yani içinde `_URUN_ADI_GIBI` bir alıntı geçen bölüm.
    """
    yol = _KOK / "docs/konsol-gorevleri.md"
    # Bölümler `###` başlıklarıyla ayrılıyor; ilk parça başlıktan önceki
    # gövde.
    bolumler = re.split(r"(?m)^###\s", _canli_metin(yol))
    adli = [b for b in bolumler if re.search(r"`rytho_tokens_[a-z]+`", b)
            and any(_URUN_ADI_GIBI.match(a) for a in _ALINTI.findall(b))]
    assert adli, (
        "docs/konsol-gorevleri.md artık Console'a girilecek ürün ADINI "
        "hiç yazmıyor: bu bekçinin ölçtüğü şey kalmadı — ya bölüm "
        "yeniden yazıldı (bekçi güncellenir) ya da adım kayboldu.")
    for bolum in adli:
        assert _KANONIK in bolum, (
            "docs/konsol-gorevleri.md ürün adını yazdıran bölümde kanonik "
            f"tabloya ({_KANONIK}) işaret YOK. İşaret olmadan iki belge "
            "aynı Console alanına bağımsız iki metin yazdırır.")


# ---------------------------------------------------------------------------
# GÜNLÜK yüzeylerin bedeli: maliyet belgesindeki tablo ile TOKEN_COSTS (GÜ)
# ---------------------------------------------------------------------------
#
# NEDEN burada: bu dosyanın konusu "bir sunucu sabiti ile onu METİNDE gösteren
# yüzey arasındaki sessiz ayrışma" ve bu, o sınıfın DÖRDÜNCÜ örneği.
# `docs/maliyet-calismasi.md` §6l üç günlük yüzeyin (firaset / BaZi / doğum
# kapısı) **bugünkü bedelini** yazıyor ve aynı satırdaki marj hücrelerini o
# bedele göre hesaplıyor. Bedel koddan okunmuyor, ELLE yazılı.
#
# Kusur sessiz olurdu ve zararı belgenin İŞİNDEN geliyor: o tablonun tek
# amacı sahibin bedel kararına dayanak olmak (bugün 5 jeton, öneri 1-3
# jeton). Bedel `TOKEN_COSTS`ta değişip tablo olduğu yerde kalırsa karar
# BAYAT bir sayıya dayanır — hem "bugünkü bedel" sütunu hem de ondan
# türeyen bütün marj yüzdeleri birden yanlışa döner.
#
# Bu bekçi FİYATI SABİTLEMİYOR: bedel özgürce değişir, yalnız belgenin
# onunla BİRLİKTE düzeltilmesi gerekir.
#
# Çapa tek bir Türkçe kelimeye BAĞLI DEĞİL (CLAUDE.md §5) — iki bağımsız
# işaret birlikte aranıyor: satırın bir hücresi `TOKEN_COSTS` ANAHTARINI
# (ASCII, sunucunun kendi sözlüğünden) ters tırnak içinde taşıyor **ve**
# ondan SONRAKİ hücrede bir sayı var. "jeton" kelimesi kalıbın hiçbir
# yerinde geçmiyor; eşleşme satır YAPISINA bağlı, serbest metne değil.
# Blockquote satırları `_canli_metin` ile boşaltılıyor: bu bekçi de bir
# şeyin YOKLUĞUNU arıyor (sapmış bedel durmasın) ve bu depoda iki kez
# kusuru ANLATAN not kusur sanıldı.

#: Bedel satırı: `| <yüzey adı> | \`<anahtar>\` | <bedel hücresi> | …`
#: Bedel hücresi ham alınıp içindeki İLK sayı okunuyor — kalın (`**5**`),
#: birimli ("5 jeton") ya da çıplak ("5") yazım hepsi geçerli olsun diye.
_BEDEL_SATIRI = re.compile(
    r"^\|[^|\n]*\|\s*`([a-z_]+)`\s*\|([^|\n]*)\|", re.M)

#: §6l'nin ölçtüğü üç yüzey. Küme SABİT ve gerekçesi var: tabloda bu üç
#: satırın BULUNMASI da ölçülüyor (aşağıdaki taban testi). `TOKEN_COSTS`un
#: tamamını istemek yanlış olurdu — belge her yüzeyi tablolamak zorunda
#: değil, yalnız günlüğe çevrilen üçünü tablolamış durumda.
_GUNLUK_YUZEYLER = {"face", "bazi", "birth_hexagram"}

#: Bedel/marj tablosunun yaşadığı belge.
_MALIYET = "docs/maliyet-calismasi.md"


def _belgedeki_bedeller(yol: Path) -> list[tuple[str, int, int]]:
    """(TOKEN_COSTS anahtarı, satır no, belgedeki bedel) üçlüleri."""
    metin = _canli_metin(yol)
    bulunan: list[tuple[str, int, int]] = []
    for m in _BEDEL_SATIRI.finditer(metin):
        anahtar = m.group(1)
        if anahtar not in _GUNLUK_YUZEYLER:
            continue
        sayilar = re.findall(r"\d+", m.group(2))
        if not sayilar:
            continue
        satir = metin[:m.start()].count("\n") + 1
        bulunan.append((anahtar, satir, int(sayilar[0])))
    return bulunan


def test_belgedeki_gunluk_yuzey_bedeli_TOKEN_COSTS_ile_ayni():
    """docs/ altındaki her canlı bedel satırı sunucudaki bedeli söyler."""
    sapma = []
    for yol in sorted((_KOK / "docs").glob("*.md")):
        for anahtar, satir, bedel in _belgedeki_bedeller(yol):
            if bedel != TOKEN_COSTS[anahtar]:
                sapma.append(
                    f"docs/{yol.name}:{satir} [{anahtar}] {bedel} "
                    f"(TOKEN_COSTS {TOKEN_COSTS[anahtar]})")
    assert not sapma, (
        "Belgedeki bedel sunucudan saptı. `wallet.TOKEN_COSTS` değiştiyse "
        "AŞAĞIDAKİ HER SATIR elle düzeltilir — ve satırın yalnız bedel "
        "sütunu değil, o bedelden türeyen MARJ hücreleri de yeniden "
        "hesaplanır (yöntem: marj = 1 − maliyet ÷ (bedel × jeton başına "
        "gelir)):\n  " + "\n  ".join(sapma))


@pytest.mark.parametrize("anahtar", sorted(_GUNLUK_YUZEYLER))
def test_gunluk_yuzeyin_bedel_satiri_maliyet_belgesinde_duruyor(anahtar: str):
    """Satır silinirse ya da kalıptan kaçarsa bekçi KIRMIZI olur.

    Taban testi. Bu olmasa üstteki test "bulunan her bedel doğru" diyerek,
    hiç satır kalmadığında da yeşil kalırdı — yani üç yüzeyden birinin
    tablodan düşmesi ya da tablonun yeniden yazılıp kalıbın dışına çıkması
    SESSİZCE geçerdi. İkisi ayrı kusur: birincisi sahibin kararına dayanak
    bırakmaz, ikincisi bekçiyi kör bırakır.
    """
    bulunan = [a for a, _, _ in _belgedeki_bedeller(_KOK / _MALIYET)]
    assert anahtar in bulunan, (
        f"{_MALIYET} içinde `{anahtar}` yüzeyinin bedel satırı YOK "
        f"(bulunan: {sorted(set(bulunan))}). Satır, günlüğe çevrilen üç "
        f"yüzeyin bedel kararının dayanağı; yeniden yazıldıysa "
        f"test_belge_tarifesi._BEDEL_SATIRI de birlikte güncellenir "
        f"(satır kalıptan kaçarsa bekçi hiçbir şey ölçmez).")

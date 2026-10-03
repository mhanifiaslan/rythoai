"""Sohbet prompt'unun DİSİPLİNİ: tek konu, bağlayıcı uzunluk, bütçe.

Bu dosya 48-turunda, sahibin iki gün gerçek kullanımdan çıkardığı iki
şikâyetin üstüne yazıldı: "makale okumak gibi" ve "bir paragrafta
birbirinden farklı alanlarda bilgi". Ölçülen kök neden kalite değil,
TALİMATIN KENDİ KENDİNİ YEMESİYDİ — ve bir talimat çatışmasını hiçbir
çıktı testi yakalayamaz, çünkü model çatışmayı "çözerek" geçer.

O yüzden buradaki bekçiler çıktıyı değil PROMPT'UN KENDİSİNİ ölçüyor:
çelişen cümle geri gelirse, zorunlu hamle geri konursa, hafıza yeniden
en ağırlıklı konuma kayarsa ya da fısıltı bütçesi sessizce büyürse test
kırmızıya döner. Hiçbir testi canlı model çağırmıyor — Gemini kotası
üretim projesinde gerçek para.

ÇAPA KURALI (bu depoda bir kez pahalıya öğrenildi): hiçbir iddia TEK bir
Türkçe kelimeye bağlanmaz. Diyakritikli tek çapa ASCII yazımla
geçilebiliyor, o yüzden aşağıda ya diyakritik katlanıyor (`_katla`) ya
birbirinden bağımsız birkaç işaret birden isteniyor.

Çalıştırma:
    .venv\\Scripts\\python.exe -m pytest tests/test_chat_prompt_disiplini.py -q
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

from services import gemini_service, memory_service, prompt_composer, prompts

DILLER = ("tr", "en")

#: Türkçe diyakritikleri ASCII'ye katlayan tablo. `str.lower()` KULLANILMIYOR:
#: Türkçe bilmiyor ("İ".lower() → "i" + U+0307) ve bu dosyadaki iddialar
#: büyük/küçük harfe değil, yazıma duyarlı.
_KATLAMA = str.maketrans({
    "ı": "i", "İ": "I", "ş": "s", "Ş": "S", "ğ": "g", "Ğ": "G",
    "ü": "u", "Ü": "U", "ö": "o", "Ö": "O", "ç": "c", "Ç": "C",
})


def _katla(metin: str) -> str:
    """Diyakritiği atar, BÜYÜK/küçük ayrımını korur.

    Amaç: "uzunluğunu değil" ile "uzunlugunu degil"i aynı çapayla yakalamak.
    Kendi bekçim ilk hâlinde tam buradan kör çıktı — tek diyakritikli çapaya
    güveniyordu ve ASCII yazım onu geçiyordu.
    """
    return metin.translate(_KATLAMA)


def _sohbet(dil: str) -> str:
    return prompts.get(dil).CHAT_SYSTEM_INSTRUCTION


def _tek_konu_blogu(dil: str) -> str:
    """Persona'nın YALNIZ birinci kuralının metni ("1) ..." → "2) ...").

    Dilim neden gerekli (doğrulama turunda MUTASYONLA ölçüldü): bu
    kuralın "seçilmeyeni o yanıtta hiç ANMA" işareti persona'nın
    TAMAMINDA aranıyordu ve orada "anma" alt dizisi BEŞ yerde geçiyor
    (çevre kuralının "hiç anma"sı, sensitivity kuralının "anmazsın —
    anmak da dokunmaktır"ı). Yani TEK KONU kuralından o cümleyi
    silmek testi KIRMIZIYA DÜŞÜRMÜYORDU: bekçi kördü. Alt dize
    eşleşmesinin yanlış pozitifi bu depoda bilinen bir sınıf; çözümü
    çapayı kuralın kendi sınırına bağlamak.

    Dilim bulunamazsa test AÇIKÇA kırılır — sessizce persona'nın
    tamamına düşmek, körlüğü geri getirmek olurdu.
    """
    ham = _sohbet(dil)
    bas = re.search(r"^1\)\s", ham, re.M)
    son = re.search(r"^2\)\s", ham, re.M)
    assert bas and son and bas.start() < son.start(), (
        f"{dil}: iki öncelikli kuralın numaralı yapısı bozulmuş — "
        f"TEK KONU bloğu ayrıştırılamıyor")
    return ham[bas.start():son.start()]


# ---------------------------------------------------------------------------
# 1. Uzunluk kuralı: BAĞLAYICI ve çelişkisiz
# ---------------------------------------------------------------------------

#: Uzunluğun belirlenmediğini SÖYLEYEN kalıplar. Bunlardan biri prompt'a
#: geri girerse, yukarıdaki üst sınırların hiçbir bağlayıcılığı kalmaz —
#: ölçülen davranış buydu: model çatışmayı uzunluk kuralını bırakarak
#: çözüyordu. Diyakritik katlanmış aranır.
_CELISKI_KALIPLARI = (
    "uzunlugunu degil",
    "uzunlugu degil",
    "uzunluk degil",
    "not its length",
    "not the length",
    "not how long",
)


@pytest.mark.parametrize("dil", DILLER)
def test_uzunluk_kurali_celismiyor(dil):
    """"Ağırlık uzunluğu belirlemez" cümlesi GERİ DÖNMESİN.

    Bu, 48-turunun birinci bulgusu: uzunluk hakkında tek ve yumuşak bir
    kural vardı ve 40+ satır sonra gelen bu cümle onu doğrudan çürütüyordu.
    """
    metin = _katla(_sohbet(dil))
    for kalip in _CELISKI_KALIPLARI:
        assert kalip not in metin, (
            f"{dil}: uzunluk kuralını çürüten kalıp geri geldi: {kalip!r}")


@pytest.mark.parametrize("dil", DILLER)
def test_uzunluk_konuya_gore_ve_ustsinir(dil):
    """Üç konu kutusu ve üç eşik prompt'ta DURUYOR (K4).

    Üç bağımsız işaret birden isteniyor: eşiklerin kendisi, bunların bir
    ÜST SINIR olduğunu söyleyen dil, ve belirsizlikte kısa olanı seçme
    kuralı. Biri kalkarsa kural yumuşamış olur.
    """
    ham = _sohbet(dil)
    metin = _katla(ham)

    assert "2-4" in ham, f"{dil}: kısa kutu eşiği yok"
    # "en çok 5" / "at most 5" — sayı tek başına aranmaz, eşik olduğu
    # görünsün diye bağlamıyla aranır.
    assert re.search(r"(en cok|at most) 5", metin), f"{dil}: orta kutu yok"
    assert re.search(r"(en cok|at most) 8", metin), f"{dil}: dolu kutu yok"

    ustsinir = ("UST SINIR" in metin or "CEILING" in metin.upper()
                or "ust sinir" in metin)
    assert ustsinir, f"{dil}: eşikler ÜST SINIR olarak tanıtılmıyor"

    emin_degilsen = ("emin degilsen" in metin or "when unsure" in metin)
    assert emin_degilsen, f"{dil}: belirsizlikte kısa olanı seçme kuralı yok"


# ---------------------------------------------------------------------------
# 2. TEK KONU: şikâyetin asıl çözümü
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("dil", DILLER)
def test_tek_konu_kurali_var(dil):
    """"Bu turda bir alan seç" kuralı prompt'ta OLMALI.

    Promptta altı ayrı alan fısıltısı var (ilişki, harita, çevre, gökyüzü,
    kaynak, hafıza) ve bu kural eklenene kadar HİÇBİR YERDE "birini seç"
    demiyordu; "en fazla tek bir ayrıntı" sınırı yalnız RAG bloğundaydı.
    Markdown yasak olduğu için alan sınırı kullanıcıya görünmüyor ve altı
    alan aynı paragrafa akıyordu.

    Üç BAĞIMSIZ işaret isteniyor; tek kelimelik çapa yetmez. Üçü de
    kuralın KENDİ bloğunda aranır, persona'nın tamamında değil —
    gerekçesi `_tek_konu_blogu`'nda (kör çıkan çapa oradaydı).
    """
    metin = _katla(_tek_konu_blogu(dil))

    # (a) seçme emri
    assert re.search(r"\b(SEC|PICK)\b", metin), f"{dil}: seçme emri yok"
    # (b) alanların ALTERNATİF olduğu (gündem değil)
    assert re.search(r"(ALTERNATIF|ALTERNATIVES)", metin), (
        f"{dil}: alanlar alternatif olarak tanıtılmıyor")
    # (c) seçilmeyenin o yanıtta ANILMAMASI. Çapa kelime başına bağlı:
    #     "anma"nın alt dize olarak geçtiği başka kurallar var.
    birakma = (re.search(r"\banma\b", metin)
               or "unmentioned" in metin)
    assert birakma, f"{dil}: seçilmeyen alanın anılmaması söylenmiyor"


# ---------------------------------------------------------------------------
# 3. Zorunlu hamleler TEŞVİKE indi
# ---------------------------------------------------------------------------

#: Her biri bir ZORUNLU içerik hamlesiydi. 2-4 cümlede hepsini yapmak
#: yapısal olarak imkânsızdı; biri geri dönerse uzunluk kuralı yine
#: yenilir. Kalıplar diyakritik katlanmış halde aranır.
_ZORUNLU_HAMLE_KALIPLARI = {
    "tr": (
        ("daima somut ve kucuk bir adimla bitir", "sohbet"),
        ("sorulmadan da", "sohbet"),
    ),
    "en": (
        ("then always close with one small", "sohbet"),
        ("weave circle knowledge in even", "sohbet"),
    ),
}


@pytest.mark.parametrize("dil", DILLER)
def test_zorunlu_hamleler_tesvike_indi(dil):
    metin = _katla(_sohbet(dil))
    for kalip, _ in _ZORUNLU_HAMLE_KALIPLARI[dil]:
        assert kalip not in metin, (
            f"{dil}: zorunlu hamle geri geldi: {kalip!r}")


@pytest.mark.parametrize("dil", DILLER)
def test_cevre_etiketi_personayla_celismiyor(dil):
    """Çevre ETİKETİ, persona'nın gevşettiği emri geri getirmesin.

    Doğrulama turunda ölçüldü: persona "çevre yalnız kullanıcı o kişiden
    söz ettiğinde girer" diyecek şekilde düzeltilmişti ama `WHISPER_CIRCLE`
    etiketi aynı turda dokunulmadan kalmıştı ve "gökyüzü ilişki/aile
    temasına değiyorsa işe kat" demeye devam ediyordu. İki katman
    çeliştiğinde model çatışmayı kendi çözer ve hangisini bıraktığı hiçbir
    çıktı testinde görünmez — paketin kapatmak için kurulduğu kusur sınıfı
    buydu. Persona testleri etiketi GÖRMEZ, o yüzden ayrı bekçi gerekti.

    İki bağımsız işaret: koşul dili VAR ve davetsiz dokunuş yasağı VAR.
    (Yasak metni etikette duruyor; bu test etiketin KENDİSİNİ okuyor,
    yani kaynak dosyadaki açıklama yorumuna takılamaz.)
    """
    ham = prompts.get(dil).WHISPER_CIRCLE
    metin = _katla(ham)

    kosul = ("SOZ ETTIYSE" in metin or "HAS BROUGHT" in ham)
    assert kosul, f"{dil}: çevre etiketi koşula bağlanmamış"

    davetsiz_yasak = ("KENDILIGINDEN gecme" in metin
                      or "do not move to the" in ham)
    assert davetsiz_yasak, (
        f"{dil}: etiket davetsiz çevre dokunuşunu yasaklamıyor — persona "
        f"ile çelişir")


@pytest.mark.parametrize("dil", DILLER)
def test_duygu_hamlesi_tek_secim(dil):
    """Ağır duyguda ÜÇ hamle (karşıla + pencere + adım) dayatılmasın.

    Tek bir "seçimli ve tek" ifadesi yetmez diye iki işaret birden
    isteniyor: seçim dili VE ikisini birden sıkıştırmanın yasaklandığı.
    """
    metin = _katla(_sohbet(dil))
    secim = ("SECIMLI" in metin or "a CHOICE of ONE" in metin
             or "CHOICE of ONE" in metin)
    assert secim, f"{dil}: ağır duygu hamlesi seçimli değil"
    ikisi_birden = ("ikisini birden" in metin or "both" in metin)
    assert ikisi_birden, f"{dil}: ikisini birden yapma yasağı yok"


def test_iliski_eksen_adi_zorunlu_degil():
    """"EN AZ BİR EKSENİ ADIYLA AN" zorunluluğu kalkmış olmalı — ama
    DAYANAK zorunluluğu KALMALI.

    İkisini ayırmak önemli: adı zorunlu kılmak yanıtı teknikleştiriyordu
    (cihaz bulgusu: "konuşmalar çok teknik"), ama dayanağı serbest
    bırakmak jenerikliği geri getirirdi. Yani bu test iki yönlü.
    """
    for dil in DILLER:
        ham = prompts.get(dil).WHISPER_RELATIONSHIP
        metin = _katla(ham)
        assert "En az bir ekseni" not in ham, f"{dil}: eksen adı hâlâ zorunlu"
        assert "Name at least one axis" not in ham, (
            f"{dil}: eksen adı hâlâ zorunlu")
        # Zorunlu DEĞİL diyen dil
        assert ("ZORUNLU DEGIL" in metin or "NOT required" in ham), (
            f"{dil}: adın serbest olduğu söylenmiyor")
        # ... ama dayanak hâlâ isteniyor
        assert ("dayansin" in metin or "Ground what you say" in ham), (
            f"{dil}: ölçüme dayanma şartı düşmüş — jeneriklik geri gelir")


# ---------------------------------------------------------------------------
# 4. `sensitivity`: yasak, malzeme değil
# ---------------------------------------------------------------------------

def test_sensitivity_kategorisi_hala_var():
    """Kategori adı UYDURULMUYOR: kaynağından okunuyor.

    Aşağıdaki bekçiler bu ada dayanıyor; ad `memory_service`'te
    değişirse bu test ilk kırılan olur ve prompt'u da güncellememiz
    gerektiğini söyler.
    """
    assert "sensitivity" in memory_service.CATEGORIES


@pytest.mark.parametrize("dil", DILLER)
def test_sensitivity_yasak_olarak_tanitiliyor(dil):
    """Kategori "bunu konuşma" demek için var ama sohbet promptu o kelimeyi
    HİÇ anmıyordu — model yasak kaydı KONUŞMA MALZEMESİ sanıyordu.

    Hem persona hem hafıza etiketi anmalı: hafıza bloğu etikete en yakın
    yer, persona da kuralın her turda görüldüğü yer.
    """
    kategori = "sensitivity"
    sohbet = _sohbet(dil)
    hafiza = prompts.get(dil).WHISPER_MEMORY

    assert kategori in sohbet, f"{dil}: persona kategoriyi anmıyor"
    assert kategori in hafiza, f"{dil}: hafıza etiketi kategoriyi anmıyor"

    # Yasak olduğunu söyleyen İKİ bağımsız işaret (tek kelime yetmez).
    for ad, metin in (("persona", _katla(sohbet)), ("hafiza", _katla(hafiza))):
        yasak = ("KONUSULMAYACAK" in metin or "NOT TO BE DISCUSSED" in metin)
        malzeme_degil = ("malzeme" in metin or "not material" in metin
                         or "it is not material" in metin)
        assert yasak, f"{dil}/{ad}: konuşulmayacak konu olduğu söylenmiyor"
        assert malzeme_degil, f"{dil}/{ad}: malzeme olmadığı söylenmiyor"


# ---------------------------------------------------------------------------
# 5. Hafızanın YERİ ve DİLİ (K6)
# ---------------------------------------------------------------------------

def test_hafiza_olculmus_verinin_onunde():
    """Hafıza, ölçülmüş astrolojik veriden ÖNCE gelmeli — yani en zayıf
    konumda.

    Mekanizma: kullanıcı mesajına yakınlık modelde ağırlık demek. Hafıza
    eskiden sondan ikinciydi ve tohum sorusu yalnız Rytho'nun açtığı
    konuşmalarda var, yani NORMAL bir turda hafıza prompt'un EN SON
    bloğuydu. Sahibin şikâyeti birebir bunun tarifiydi: hafıza
    "haritaları, gezegenleri, kitabı bilgileri zehirleyen bir yapı".

    İddia metin aramıyor, SIRA ölçüyor: hafızayı geri taşıyan bir
    değişiklik bu testi kırar.
    """
    for dil in DILLER:
        p = prompts.get(dil)
        cikti = prompt_composer.compose_chat_message(
            "soru", [{"doc": "d", "title": "t", "text": "pasaj", "score": 1.0}],
            memory="- (work) is degisikligi", chart="- Gunes Aslan",
            sky="- Ay evresi: Dolunay", relationship="- Iletisim: Guclu",
            circle="- esin: Gunes Terazi", lang=dil)

        yer = {ad: cikti.index(getattr(p, ad)) for ad in (
            "WHISPER_MEMORY", "WHISPER_RELATIONSHIP", "WHISPER_CHART",
            "WHISPER_CIRCLE", "WHISPER_SKY", "WHISPER_RAG")}
        for sonra in ("WHISPER_RELATIONSHIP", "WHISPER_CHART",
                      "WHISPER_CIRCLE", "WHISPER_SKY", "WHISPER_RAG"):
            assert yer["WHISPER_MEMORY"] < yer[sonra], (
                f"{dil}: hafıza {sonra}'dan sonra geliyor — ölçümü eziyor")

        # Mesaj hâlâ en sonda: "en yakın yer en ağır" iddiasının dayanağı.
        assert cikti.rstrip().endswith("soru"), f"{dil}: mesaj sonda değil"


@pytest.mark.parametrize("dil", DILLER)
def test_hafiza_dili_kosullu(dil):
    """Dil "bunları kullan"dan "YALNIZ doğrudan ilgiliyse dokun"a çevrilmiş
    olmalı, ve ölçümün kazandığı yazılı olmalı.

    İki bağımsız işaret: koşul dili VE çelişkide ölçümün üstün olduğu.
    """
    ham = prompts.get(dil).WHISPER_MEMORY
    metin = _katla(ham)

    kosul = ("YALNIZCA" in metin or "ONLY if" in ham)
    assert kosul, f"{dil}: hafıza dokunuşu koşula bağlanmamış"

    degmiyorsa = ("HIC anma" in metin or "do not mention it at all" in ham)
    assert degmiyorsa, f"{dil}: konu değmiyorsa anmama kuralı yok"

    olcum_kazanir = ("EZMEZ" in metin or "do NOT" in ham and "override" in ham)
    assert olcum_kazanir, f"{dil}: ölçümün üstünlüğü yazılı değil"


# ---------------------------------------------------------------------------
# 6. Fısıltı bütçesi — bu depoda HİÇ ölçülmemişti
# ---------------------------------------------------------------------------
#
# Toplam prompt boyutunu ölçen bir test yoktu: o iddia bir turda bilerek
# kaldırılmıştı (bkz. `test_chat_style.py`'deki kırpma testinin gerekçesi —
# sabit etiketlerle değişken pasajı aynı bütçede toplamak yanlıştı) ama
# yerine bir TOPLAM bekçisi konmamıştı. Bu bölüm o boşluğu dolduruyor ve
# ikisini KARIŞTIRMIYOR: aşağıdaki iddia pasaj kırpmasını değil, sunucunun
# mesaja eklediği her şeyin toplamını ölçüyor.

_TASKIN = "x" * 20_000

#: ÖLÇÜLEN tavanlar — modülden OKUNMUYOR, buraya yazıldı.
#:
#: Bu ayrım bir mutasyon denemesinde ortaya çıktı ve bekçimin ilk hâli
#: KÖRDÜ: iddia `prompt_composer.MAX_CHART_CHARS`a karşı kuruluyordu, yani
#: sabiti 200.000 yapmak iddianın kendisini de 200.000'e çıkarıyor ve test
#: YEŞİL kalıyordu. Kendi ölçtüğü şeyi sanığa soran bir bekçi, bekçi
#: değildir. Sayılar burada sabit: tavanı yükseltmek artık BU DOSYAYI da
#: değiştirmeyi, yani bilinçli bir kararı gerektirir.
#:
#: Değerler 48-turunda ölçüldü (bloklar taşacak kadar beslenerek): altı
#: blok tavanının toplamı 5.800, iki pasaj 2.528, etiketler TR 3.978 /
#: EN 4.486 → en kötü hâl TR 12.370, EN 12.896 karakter.
OLCULEN_BLOK_TAVANLARI = {
    "chart": 1_400,
    "memory": 1_200,
    "relationship": 1_200,
    "circle": 800,
    "sky": 600,
    "seed_question": 600,
}
OLCULEN_FISILTI_TAVANI = 13_500


def test_blok_tavanlari_sessizce_buyumemis():
    """Modüldeki tavanlar ölçülen değerlerle AYNI kalmalı.

    Aşağıdaki kırpma testleri modül sabitlerini kullanıyor (kırpmanın
    gerçekten o sınıra uyduğunu göstermek için); bu test de o sabitlerin
    kendisini ölçülen değere çiviliyor. İkisi birlikte hem "kırpma
    çalışıyor" hem "sınır büyümedi" diyor.
    """
    for ad, beklenen in OLCULEN_BLOK_TAVANLARI.items():
        gercek = getattr(prompt_composer,
                         f"MAX_{ad.split('_')[0].upper()}_CHARS")
        assert gercek == beklenen, (
            f"{ad} tavanı {gercek} olmuş (ölçülen: {beklenen}). Değişikliği "
            f"isteyen bu testi de güncellemeli — gerekçesiyle.")
    assert prompt_composer.MAX_WHISPER_CHARS == OLCULEN_FISILTI_TAVANI, (
        f"toplam fısıltı tavanı {prompt_composer.MAX_WHISPER_CHARS} olmuş "
        f"(ölçülen: {OLCULEN_FISILTI_TAVANI})")


@pytest.mark.parametrize("dil", DILLER)
def test_fisilti_butcesi_asilmaz(dil):
    """Her blok taşsa bile sunucunun eklediği kısım tavanı aşmaz.

    İddia ÖLÇÜLEN sabite karşı kurulu, modülden okunan değere değil —
    gerekçe `OLCULEN_FISILTI_TAVANI`nın yanında.
    """
    mesaj = "kisa soru"
    pasaj = {"doc": "d", "title": "t", "text": _TASKIN, "score": 0.9,
             "authority": 5,
             "source": {"school_tr": "Okul", "school": "School",
                        "era_tr": "Donem", "era": "Era"}}
    cikti = prompt_composer.compose_chat_message(
        mesaj, [pasaj] * 5, memory=_TASKIN, chart=_TASKIN, sky=_TASKIN,
        relationship=_TASKIN, circle=_TASKIN, seed_question=_TASKIN,
        lang=dil)

    eklenen = len(cikti) - len(mesaj)
    assert eklenen <= OLCULEN_FISILTI_TAVANI, (
        f"{dil}: fısıltı bütçesi aşıldı: {eklenen} > "
        f"{OLCULEN_FISILTI_TAVANI}")

    # Testin kendi kendini kandırmaması için: kırpma GERÇEKTEN çalıştı mı?
    # Girdi 20.000 karakterdi; çıktı toplamı ondan küçükse kırpılmıştır.
    assert eklenen < len(_TASKIN), f"{dil}: bloklar hiç kırpılmamış"


@pytest.mark.parametrize("dil", DILLER)
def test_her_blok_kendi_tavanina_kirpilir(dil):
    """Tavanlar tek tek uygulanıyor — toplam iddiası ancak böyle kanıtlanır.

    `chart` özellikle ölçülüyor: kaynağında (`chart_context.chart_whisper`)
    runtime sınırı YOK. Oradaki tek tavan bir TEST iddiası ve yalnız bir
    fikstür profili için (`test_chart_context.py`, < 1400 karakter);
    açısı/transiti bol bir harita üretimde o boyu aşabilir ve kimse
    göremezdi.
    """
    for ad, tavan in OLCULEN_BLOK_TAVANLARI.items():
        cikti = prompt_composer.compose_chat_message(
            "soru", [], lang=dil, **{ad: _TASKIN})
        # Etiket + ayırıcılar + "…" payı: 1.200 karakter fazlasıyla yeter
        # (en uzun etiket 1.181 karakter, o da RAG'in ve burada RAG yok).
        assert len(cikti) <= tavan + 1_200, (
            f"{dil}/{ad}: blok tavanına kırpılmamış ({len(cikti)} karakter, "
            f"tavan {tavan})")


def test_kullanici_mesaji_kirpilmaz():
    """Kullanıcının kendi cümlesi KIRPILMAZ — bu bilinçli bir asimetri.

    Fısıltılar sunucunun eklediği şey; mesaj kişinin kendi sözü. Yarısını
    atmak "ölçülmeyen söylenmez"in tersi olurdu: kullanıcı sorduğunu
    sanar, model görmez, kimse fark etmez.
    """
    uzun = "Merkur retrosu " * 500
    cikti = prompt_composer.compose_chat_message(
        uzun, [], memory="- (work) bir not", lang="tr")
    assert uzun in cikti, "kullanıcı mesajı kırpılmış"


def test_mesaj_sinirinin_kaynagi_duruyor():
    """Tur başı girdi iddiasının ÜÇÜNCÜ halkası başka bir modülde.

    `prompt_composer` kullanıcı mesajını BİLEREK kırpmıyor ve bunu
    "mesaj kişinin kendi sözü" diye gerekçelendiriyor. O gerekçe ancak
    mesajın BAŞKA bir yerde bağlı olmasıyla tamamlanıyor: `api/chat.py`
    composer'a vermeden önce `chat_history.clip_message` uyguluyor
    (doğrulama turunda ölçüldü). O sınır sessizce büyürse composer'daki
    toplam bütçe gerekçesi bayatlar ve kimse göremez.

    İddia GEVŞEK bağlı: `chat_history` başka bir pakete ait, o yüzden
    tam eşitlik değil bir ÜST SINIR isteniyor — büyüme bir karar olsun.
    """
    from services import chat_history

    assert chat_history.MAX_MESSAGE_CHARS <= 2_000, (
        f"mesaj sınırı {chat_history.MAX_MESSAGE_CHARS} olmuş — "
        f"prompt_composer'daki toplam bütçe gerekçesi güncellenmeli")


def test_gecmis_payinin_kaynagi_duruyor():
    """Tur basi girdi iddiasinin DORDUNCU halkasi: SOHBET GECMISI.

    `prompt_composer`in butce gerekcesi tur basi girdiyi dort kalemle
    topluyor: "fisilti <= 13.500 + mesaj <= 2.000 + gecmis <= 12x1.200 +
    persona <= 7.600" ve "bu zincirin halkalari burada tek tek civili"
    diyor. Olculdu: UC halkanin bekcisi vardi, GECMISIN bekcisi YOKTU —
    yani yorumun kendi gerekcesi yanlisti ve bu depoda yanlis gerekce
    KUSUR sayilir.

    Kalem KUCUK DEGIL, en BUYUGU: 12 x 1.200 = 14.400 karakter, yani
    bekcisi olan fisilti tavaninin (13.500) UZERINDE. `chat_history`de
    `PROMPT_HISTORY_MESSAGES` 12 -> 30 yapilsa tur basi girdi ~21.600
    karakter artar, fatura iki katina cikar ve HICBIR test konusmaz —
    fisilti bekcisi yalniz `compose_chat_message` CIKTISINI olcuyor,
    gecmis ise `api/chat.py`den dogrudan `gemini_service.chat`in
    `history` parametresine gidiyor, composer'dan HIC gecmiyor.

    Iddia BILEREK GEVSEK (tam esitlik degil, ust sinir): `chat_history`
    baska bir pakete ait ve dusurmek serbest olmali; buyume ise bir
    KARAR olsun. Ayni gerekce `test_mesaj_sinirinin_kaynagi_duruyor`da.

    Iki carpan AYRI AYRI da civili: yalniz carpimi olcmek, 6 x 2.400
    gibi mesaj BASINA iki kat buyuyen bir degisikligi sessiz gecirirdi
    (toplam ayni kalir ama tek bir uzun mesaj prompt'ta iki kat yer
    tutar ve kirpma noktasi kayar).
    """
    from services import chat_history

    assert chat_history.PROMPT_HISTORY_MESSAGES <= 12, (
        f"prompt gecmisi {chat_history.PROMPT_HISTORY_MESSAGES} mesaja "
        f"cikmis — prompt_composer'daki toplam butce gerekcesi "
        f"guncellenmeli")
    assert chat_history.PROMPT_MESSAGE_CHARS <= 1_200, (
        f"prompt mesaj tavani {chat_history.PROMPT_MESSAGE_CHARS} olmus "
        f"— prompt_composer'daki toplam butce gerekcesi guncellenmeli")
    pay = (chat_history.PROMPT_HISTORY_MESSAGES
           * chat_history.PROMPT_MESSAGE_CHARS)
    assert pay <= 14_400, f"gecmis payi {pay} karaktere cikmis"


@pytest.mark.parametrize("dil", DILLER)
def test_persona_boyutu_butcede(dil):
    """Persona HER turda gidiyor; sessiz büyümesi doğrudan para.

    Ölçülen boy: TR 5.882, EN 6.538 karakter (48-turu, iki yeni bağlayıcı
    kural eklendikten SONRA). 7.600 bunun hemen üstünde — bir sonraki
    "bir cümle daha ekleyelim" turunda bekçi konuşsun diye bilerek dar.
    """
    boy = len(_sohbet(dil))
    assert boy <= 7_600, f"{dil}: persona {boy} karaktere çıktı"
    # Alt sınır da var: persona çökerse (boş dize, yanlış dil dosyası)
    # yukarıdaki içerik testleri tek tek kırılır ama sebebi görünmez.
    assert boy >= 4_000, f"{dil}: persona şüpheli derecede küçük ({boy})"


# ---------------------------------------------------------------------------
# 7. Çıktı tavanı: ölçülen bantta
# ---------------------------------------------------------------------------

def test_sohbet_cikti_tavani_olculen_bantta():
    """`CHAT_MAX_OUTPUT_TOKENS` iki ölçümün arasında kalmalı.

    ALT SINIR 500, çünkü tavan düşünme dahil TOPLAM çıktı bütçesidir:
    `GEMINI_MODEL` ile pin dışına çıkılırsa ölçülen en kötü düşünme
    sızıntısı 286 token (`gemini_service` gerekçesi) ve prompt'un yeni üst
    sınırı 8 cümle ≈ 195 token → 481. Daha aşağısı sızıntıyı sessiz
    kesilmeye çevirir.

    ÜST SINIR 800, çünkü 8 cümlelik en uzun yanıt ~195 token ve pinli
    modelde ölçülen düşünme 0: bundan büyüğü ölçülmemiş bir paydır.
    """
    tavan = gemini_service.CHAT_MAX_OUTPUT_TOKENS
    assert 500 <= tavan <= 800, (
        f"CHAT_MAX_OUTPUT_TOKENS ölçülen bandın dışında: {tavan}")


def test_yedek_varyant_dusunmeye_yer_biraksin():
    """Tavan düşerken İKİNCİ varyantın geniş bütçesi düşmemiş olmalı.

    Savunma iki katmanlı: ilk varyant düşünmeyi kapatır ve dar bütçeyle
    gider, tutmazsa ikinci varyant düşünmeyi tamamen açar. İkincisi de
    daralırsa kesilme kurtarma yolu kalmaz.
    """
    varyantlar = gemini_service._CHAT_CONFIG_VARIANTS
    assert len(varyantlar) >= 2, "yedek varyant kalmamış"
    son = varyantlar[-1]
    assert "thinking_config" not in son, (
        "son varyant düşünmeyi kapatıyor — kurtarma yolu değil")
    assert son["max_output_tokens"] >= 2048, (
        "kurtarma varyantının bütçesi daralmış")


# ---------------------------------------------------------------------------
# 8. Sinastri: sabit iskelet yok, yağcılık emri yok
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("dil", DILLER)
def test_sinastri_sabit_baslik_dayatmiyor(dil):
    """Her çifte aynı üç bölümü dayatan satır kalkmış olmalı.

    İki farklı çift aynı iskeleti görüyordu; bu, "tüm arkadaşlarla aynı
    cevaplar var" bulgusunun prompt tarafıydı. İki işaret birden: numaralı
    iskelet YOK ve değişkenliği söyleyen dil VAR.
    """
    ham = prompts.get(dil).SYNASTRY
    metin = _katla(ham)

    assert not re.search(r"\(1\).{0,80}\(2\).{0,80}\(3\)", ham, re.S), (
        f"{dil}: sinastri hâlâ numaralı sabit iskelet dayatıyor")
    degisken = ("BU CIFTIN" in metin or "THIS PAIR'S" in ham)
    assert degisken, f"{dil}: bölümlerin çifte göre değiştiği söylenmiyor"
    iskelet_yasagi = ("iskelet" in metin or "skeleton" in ham)
    assert iskelet_yasagi, f"{dil}: sabit iskelet yasağı yazılı değil"


#: Zorluğu olumluya çeviren YUMUŞATICI KÖKLER. Kaynak: deponun kendi
#: yağcılık dedektörü (`scripts/eval_genericness.py`) — orada baş×kuyruk
#: çarpımı olarak aranıyor ("büyüme"+"alanı", "gelişim"+"fırsatı"...).
#:
#: Buraya KOPYALANDI, dedektörden okunmuyor. Üç sebep: (1) o dosya başka
#: bir pakete ait ve bu turda yeniden yazıldı — adına bağlanan bir test
#: onun her düzenlemesinde yanlış kırmızı verir; (2) çarpım listesini
#: prompt'a karşı çalıştırmak, YASAĞI ANLATAN cümlenin kendisini yakalardı
#: (bu depoda iki kez patlayan tuzak); (3) burada duran liste neyin
#: yasaklandığını okunur kılıyor.
#:
#: Bu yüzden prompt'ta bu köklerin HİÇBİRİ geçmiyor — yasak, kökleri
#: anmadan anlatılıyor ("zorluğu olumlu bir kavrama çevirerek yumuşatma").
#:
#: Son üç kök (farkındalık, olgunlaşma, öğrenme) buraya ELLE değil, aşağıdaki
#: bayatlama bekçisi sayesinde girdi: ilk hâlinde liste eksikti ve test
#: dedektörün bildiği üç kökü bilmediğimi söyledi. Kopyanın bedeli budur ve
#: ödenmesi gereken yer tam burası.
_YUMUSATICI_KOKLER = (
    "büyüme", "gelişim", "gelişme", "ilerleme", "dönüşüm",
    "farkındalık", "olgunlaşma", "öğrenme",
    "growth", "development", "opportunity", "journey",
)


def test_sinastri_yumusatici_kalip_emretmiyor():
    """Ürün, bekçisinin yasakladığı dili modele EMRETMESİN.

    İroni ölçüldü: sinastri promptu her çifte "Dikkat ve büyüme alanı" diye
    bir bölüm dayatıyordu ve bu ifade, dedektörün avladığı kalıbın anlam
    ikizidir. Yani ürün, bekçisinin cezalandırdığı dili modele emrediyordu.
    """
    for dil in DILLER:
        ham = prompts.get(dil).SYNASTRY
        katlanmis = _katla(ham)
        for kok in _YUMUSATICI_KOKLER:
            assert _katla(kok) not in katlanmis, (
                f"{dil}: sinastri promptu yumuşatıcı kök içeriyor: {kok!r}")


def test_dedektorun_yumusatici_kokleri_hala_avlaniyor():
    """Yukarıdaki liste dedektörle UYUMLU mu — kopyanın bayatlama bekçisi.

    Kopyalanan liste bir borçtur: dedektör tarafı yeni bir kök eklerse bu
    dosya onu bilmez. Bu test iki tarafı gevşek bağlar — dedektörde kök
    olarak duran Türkçe ifadelerin burada da bulunmasını ister, ama
    dedektörün YAPISINA bağlanmaz: dosya ya da sabit adı değişirse atlar.
    """
    kaynak = (Path(__file__).resolve().parents[1]
              / "scripts" / "eval_genericness.py")
    if not kaynak.exists():
        pytest.skip("eval_genericness.py bulunamadı (başka paket)")
    metin = kaynak.read_text(encoding="utf-8")
    blok = re.search(r"YAGCILIK_BAS\s*=\s*\(([^)]*)\)", metin, re.S)
    if not blok:
        pytest.skip("dedektörün kök listesi bu adla ayrıştırılamadı")
    kokler = re.findall(r'"([^"]+)"', blok.group(1))
    assert kokler, "dedektörün kök listesi boş okundu"
    eksik = [k for k in kokler if k not in _YUMUSATICI_KOKLER]
    assert not eksik, (
        f"dedektör şu kökleri de avlıyor ama bu dosya bilmiyor: {eksik} — "
        f"_YUMUSATICI_KOKLER'e ekleyin ve prompt'ları kontrol edin")


# ---------------------------------------------------------------------------
# 9. İki dilin AYRIŞMASI bir kusur sınıfı
# ---------------------------------------------------------------------------

def test_tr_ve_en_ayni_disiplinde():
    """Aynı kurallar iki dosyada da olmalı.

    Bu depoda ayrışma bir kusur sınıfı: kusur yalnız bir dilde görünür ve
    İngilizce taraf aylarca sessizce bozuk kalır. Yukarıdaki testler zaten
    `parametrize` ile iki dili birden geziyor; bu test o kapsamanın
    KENDİSİNİ koruyor — yeni bir dil eklenirse listeye girmesi gerektiğini
    söyler.
    """
    # İlk hâlinde burada `hasattr(prompts, "AVAILABLE")` fallback'i vardı ve
    # o öznitelik YOK — yani iddia sessizce hiçbir şey ölçmüyordu. Paket
    # dilleri `_MODULES`'te tutuyor; kapsama onun ÜZERİNDEN sorulur, yoksa
    # yeni bir dil eklendiğinde bu dosya hiç konuşmaz.
    paketin_dilleri = set(prompts._MODULES)
    assert paketin_dilleri == set(DILLER), (
        f"prompts paketi {sorted(paketin_dilleri)} dillerini sunuyor ama bu "
        f"dosya {sorted(DILLER)} geziyor — yeni dil aynı disipline girmeli")

    for dil in DILLER:
        p = prompts.get(dil)
        for ad in ("CHAT_SYSTEM_INSTRUCTION", "WHISPER_MEMORY",
                   "WHISPER_RELATIONSHIP", "WHISPER_CHART", "SYNASTRY"):
            assert getattr(p, ad, "").strip(), f"{dil}: {ad} boş"

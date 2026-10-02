"""Sohbet prompt düzenleyicisi — seçici RAG ve arka plan fısıltısı.

İki görev üstlenir:
1. should_use_rag: Kullanıcı mesajının bilgi tabanı (RAG) araması gerektirip
   gerektirmediğine sezgisel olarak karar verir. Selamlaşma, duygu paylaşımı
   ve kısa onaylarda RAG (ve dolayısıyla embedding çağrısı) atlanır — hem
   gecikme düşer hem de model gereksiz kaynak dökümünden uzak durur.
2. compose_chat_message: Bulunan pasajları prompta olduğu gibi boca etmek
   yerine, en fazla 2 pasajı kırpılmış birer "arka plan fısıltısı" olarak
   iliştirir ve modele bunları asla blok halinde aktarmamasını söyler.
"""
from __future__ import annotations

import re

from services import prompts

# Pasaj başına karakter sınırı ve en fazla pasaj sayısı.
#
# Bu iki sayı 13 parçalık, dil başına ~9 KB'lık bir korpus için konmuştu ve
# o zaman doğruydu: dönen pasaj çoğu zaman alakasızdı, alakasız metni
# büyütmek cevabı iyileştirmez, yalnızca pahalılaştırırdı.
#
# Üç şey değişti ve ölçüldü:
#   1. Korpus gerçek bir kitap taşıyor (Tetrabiblos, EN 136 / TR 33 parça).
#   2. Sorgu artık haritadan kuruluyor; dönen pasajlar 0,71–0,84 skorla
#      gerçekten ilgili (alakasız sorgular 0,49–0,56'da kalıyor).
#   3. 280 karakter, ortalama 907 karakterlik bir parçanın **%68'ini**
#      atıyordu — yani doğru bulunan pasajın üçte ikisi çöpe gidiyordu.
#
# 700 → 1200 (RD-turu, kullanıcı kararı): kitap korpusunun parçaları
# ~3.300 karakter — 700'lük kesim içeriğin çoğunu atıyordu. 1200, bir
# parçanın ana fikrini bütünüyle taşıyor; tur başına ek maliyet ~+125
# girdi token (≈ +$0,0001) — ihmal edilebilir.
#
# Pasaj SAYISI 2'de bırakıldı (kullanıcı bunu da onayladı). Üçüncü kaynak
# odağı dağıtıyor ve persona zaten "en fazla tek bir ilgili ayrıntıyı
# kendi cümlene sindir" diyor; daha çok kaynak vermek modeli aktarmaya
# davet ediyor. Çeşitlilik kuralı sayesinde bu 2 pasaj zaten farklı
# bölümlerden geliyor.
MAX_PASSAGES = 2
MAX_PASSAGE_CHARS = 1200

# ---------------------------------------------------------------------------
# Fısıltı bütçesi (48-turu)
# ---------------------------------------------------------------------------
#
# Bu tavanlar neden ÇAĞIRANDA değil BURADA:
#
# Prompt'u kuran yer burası, dolayısıyla "prompt ne kadar büyüyebilir"
# sorusunun tek cevap verebileceği yer de burası. Bloklar altı ayrı
# serviste üretiliyor ve her biri kendi sınırını kendi koyuyordu —
# `memory_context(max_chars=600)`, `synastry_service.whisper_for(
# max_chars=900)`, `circle_context.MAX_CIRCLE_CHARS = 400` — ama
# `chart_context.chart_whisper` hiç KARAKTER sınırı almıyordu. Ölçüldü:
# harita bloğunun bir tavanı var ama yalnız TESTTE ve yalnız TEK bir
# fikstür profili için (`tests/test_chart_context.py`, < 1400 karakter).
# Toplam prompt boyutunu ölçen de HİÇBİR test yoktu — o iddia bir turda
# bilerek kaldırılmıştı (bkz. `test_chat_style.py`, kırpma testinin
# gerekçesi), yerine bir toplam bekçisi konmadan.
#
# Sınırın bedeli ölçülü: blok HER sohbet turunda, her kullanıcı için
# gidiyor; girdi token'ı doğrudan para.
#
# ⚠️ PAYLAR EŞİT DEĞİL, ve ilk hâlindeki "her birine ~2 katı pay bırakıldı,
# normal hiçbir turda kırpma olmaz" cümlesi ÖLÇÜMLE ÇÜRÜDÜ (düzeltildi).
# Ölçülen gerçek:
#   * `memory` 600 → 1200 ve `circle` 400 → 800: gerçekten 2 kat. Bu iki
#     blok kaynağında KARAKTERLE sınırlı, yani tavan burada yalnız bir
#     yedek kapı.
#   * `relationship`: kaynak varsayılanı 900 (600 DEĞİL) ve `api/chat.py`
#     çağrıyı max_chars vermeden yapıyor → pay 1,33 kat.
#   * `chart`: ölçülen blok 891 karakter, BaZi dahil 1126
#     (`tests/test_chart_context.py` fikstürü, TR) → pay 1,24 kat. Tavan
#     bilerek o testin kendi sınırına (1400) eşit: harita bloğu KARAKTERLE
#     sınırlı değil ama ÖĞE ile sınırlı (`chart_context`: 6 natal açı,
#     4 transit), yani boyu bu bandın üstüne çıkmaz. 1400 bu bandın
#     backstop'u, cömert bir pay değil — zengin bir harita kırpılabilir
#     ve bu BİLİNÇLİ: kırpma, sessiz büyümeye yeğdir.
#   * `sky`: en kötü hâl TR 292 / EN 305 karakter (doğrulama turunda
#     ölçüldü: sekiz gezegen birden retroda, üç açı, en uzun menzil
#     adı). Blok beş satır ve ÖĞE ile sınırlı — `api/chat.py` en çok
#     3 açı yazıyor — yani pay ~2 kat ve kırpma normal turda hiç
#     tetiklenmez; burada yalnız yedek kapı.
#   * `seed_question`: tavanı KAYNAĞININ ALTINDA olan tek blok bu ve
#     bu bilinçli. Kaynak sınırı `chat_history.clip_message` = 2.000
#     karakter (arşiv sınırı), ama tohum metni Rytho'nun akşam
#     bildirim gövdesi — bir cümle. 600 onun fazlasıyla üstünde ve
#     2.000'lik ARŞİV sınırının prompt bütçesine taşınmasını önlüyor.
#
# KULLANICININ MESAJI BİLEREK KIRPILMIYOR: o metin sunucunun eklediği bir
# şey değil, kişinin kendi cümlesi. Yarısını atmak "ölçülmeyen söylenmez"
# ilkesinin tersi olurdu — kullanıcı sorduğunu sanır, model görmez.
# Buradaki bütçe yalnız SUNUCUNUN EKLEDİĞİ kısmı bağlar. Mesajın kendisi
# yine de sınırsız DEĞİL: `api/chat.py` onu composer'a vermeden önce
# `chat_history.clip_message` ile 2.000 karaktere indiriyor (ölçüldü,
# doğrulama turu). Yani tur başı girdinin tamamı bağlı — fısıltı ≤ 13.500
# + mesaj ≤ 2.000 + geçmiş ≤ 12×1.200 + persona ≤ 7.600 — ve bu zincirin
# halkaları `test_chat_prompt_disiplini.py`'de tek tek çivili.
MAX_CHART_CHARS = 1400          # kaynağında runtime sınırı YOK; asıl boşluk bu
MAX_RELATIONSHIP_CHARS = 1200   # synastry_service varsayılanı 900
MAX_CIRCLE_CHARS = 800          # circle_context sınırı 400
MAX_MEMORY_CHARS = 1200         # memory_service varsayılanı 600
MAX_SKY_CHARS = 600
MAX_SEED_CHARS = 600

#: Sunucunun mesaja eklediği HER ŞEYİN toplam tavanı (etiketler + bloklar).
#:
#: Ölçüldü (bu dosya, altı bloğun hepsi taşacak kadar beslenerek): tavanlar
#: dolduğunda ve iki pasaj sınırda geldiğinde Türkçe kurulum 12.460,
#: İngilizce 13.029 karakter — yani İngilizce tarafta tavanın altında
#: yalnız 471 karakter boşluk var (doğrulama turunda yeniden ölçüldü:
#: çevre etiketi persona ile hizalanırken TR +106 / EN +157 karakter
#: uzadı ve eski sayılar bayatladı). İngilizce daha uzun çünkü etiket
#: seti daha
#: uzun. Gerçek bir tur bunun çok altında kalıyor; doğrulama turunda
#: GİRDİLERİYLE birlikte yeniden ölçüldü (sayı girdisi yazılmadan
#: tekrar ölçülemez, o yüzden burada duruyor): hafıza 600 + harita 891
#: + gökyüzü 292 + çevre 400 + iki pasaj 1.200 — ilişki ve tohum YOK,
#: ikisi de istisnai — → TR 8.065 karakter. İlişki fısıltısı da
#: gelirse 9.634.
#:
#: 13.500, ölçülen en kötü hâlin hemen üstünde. BİLEREK dar: yedinci bir
#: fısıltı bloğu eklenmesi ya da bir etiketin iki katına çıkması bu sınırı
#: AŞAR ve bekçi kırmızıya döner. Sınırı yükseltmek bir karardır — tavan
#: her sohbet turunda, her kullanıcı için ödenen girdi token'ıdır.
MAX_WHISPER_CHARS = 13_500


def _kirp(metin: str, sinir: int) -> str:
    """Bloğu sınıra indirir; kelime ortasından kesmemeye çalışır.

    Kelime sınırı önemsiz bir süs değil: kesik bir sözcük modele
    YANLIŞ BİR OLGU olarak okunabiliyor (örnek: "Satürn 7. ev" →
    "Satürn 7" bir derece sanılır). Boşluk bulunamazsa ham kesilir —
    sınırın aşılmaması daha önemli.
    """
    if len(metin) <= sinir:
        return metin
    kesik = metin[:sinir]
    bosluk = kesik.rfind(" ")
    if bosluk > sinir // 2:
        kesik = kesik[:bosluk]
    return kesik.rstrip() + "…"

# Bilgi tabanının kapsadığı kadim sistem terimleri (kök bazlı, küçük harf).
# Mesajda bunlardan biri geçiyorsa korpus araması değerlidir.
#
# Terimler İKİ DİLDE birden aranır ve mesajın dili sorulmaz: liste yalnızca
# Türkçe olduğu sürece İngilizce yazan kullanıcı için RAG hiç tetiklenmiyordu
# ("what does my Mercury retrograde mean" korpusa hiç uğramıyordu). Fazladan
# arama maliyeti düşük, eksik arama ise cevabın kalitesini doğrudan düşürür.
_DOMAIN_TERMS = (
    # Türkçe
    "burc", "burç", "yükselen", "yukselen", "astroloji", "gezegen", "retro",
    "merkür", "merkur", "venüs", "venus", "jüpiter", "jupiter",
    "satürn", "saturn", "plüton", "pluton", "neptün", "neptun", "uranüs",
    "uranus", "natal", "harita", "transit", "sinastri", "nakshatra", "dasha",
    "bazi", "day master", "on tanrı", "on tanri", "heksagram", "i ching",
    "iching", "yin", "yang", "element", "mizaç", "mizac", "kıyafetname",
    "kiyafetname", "sima", "mian xiang", "yüz okuma", "yuz okuma", "ay evresi",
    "dolunay", "yeniay", "tutulma", "ev yerleş", "ev yerles", "açı", "orb",
    "koç", "boğa", "ikizler", "yengeç", "yengec", "aslan", "başak", "basak",
    "terazi", "akrep", "yay", "oğlak", "oglak", "kova", "balık",
    # İngilizce
    "zodiac", "sign", "rising", "ascendant", "astrolog", "planet",
    "retrograde", "mercury", "venus", "mars", "jupiter", "saturn", "pluto",
    "neptune", "uranus", "chart", "synastry", "hexagram", "horoscope",
    "house", "aspect", "conjunction", "sextile", "square", "trine",
    "opposition", "moon phase", "full moon", "new moon", "eclipse",
    "temperament", "four humours", "four humors", "physiognomy",
    "aries", "taurus", "gemini", "cancer", "leo", "virgo", "libra",
    "scorpio", "sagittarius", "capricorn", "aquarius", "pisces",
)

# Derinlemesine açıklama isteyen soru kalıpları (tam kelime olarak aranır ki
# "nasılsın" içindeki "nasıl" tetiklemesin).
_QUESTION_WORDS = {
    "neden", "nasıl", "nasil", "niye", "anlat", "anlatır",
    "anlatir", "nedir", "açıkla", "acikla", "ne demek",
    "why", "how", "explain", "meaning", "means", "what",
}

# Selamlaşma / duygu / kısa onay işaretleri — RAG'e gerek yok.
_SMALL_TALK = {
    "selam", "merhaba", "günaydın", "gunaydin", "nasılsın",
    "nasilsin", "naber", "teşekkür", "tesekkur", "teşekkürler",
    "tesekkurler", "sağol", "sagol", "evet", "hayır", "hayir",
    "tamam", "peki", "olur", "harika", "süper", "super", "eyvallah",
    "keyifsiz", "üzgün", "uzgun", "mutlu", "yorgun", "moral",
    "canım", "canim", "sıkıldım", "sikildim", "iyiyim", "kötüyüm",
    "kotuyum", "görüşürüz", "gorusuruz", "iyi geceler",
    "hi", "hello", "hey", "thanks", "thank", "ok", "okay", "sure",
    "yes", "no", "great", "awesome", "bye", "goodnight", "tired",
    "sad", "happy", "lonely", "bored",
}


def normalize(message: str) -> str:
    """Küçük harfe indirger — Türkçe noktalı I'yı doğru ele alarak.

    Python'un `str.lower()` metodu Türkçe bilmez: ``"İ".lower()`` sonucu
    ``"i"`` DEĞİL, ``"i" + U+0307`` (birleşik nokta) olur. Sonuç sessiz bir
    bozulmaydı — "İşimle ilgili..." diye başlayan bir mesajda ``"iş"`` kökü
    hiç eşleşmiyor, yani RAG tetiklenmiyor ve kullanıcı kaynaksız cevap
    alıyordu. Aynı şekilde ``"I".lower()`` ``"i"`` verir, oysa Türkçede
    karşılığı ``"ı"``.

    Türkçe cümleler büyük harfle başladığı için bu, kenar durum değil —
    "İşim", "İlişkim", "İnsanlar" gibi en sık sorulan kelimeler tam da
    buradan düşüyordu.
    """
    return message.replace("İ", "i").replace("I", "ı").lower()


def _words(message: str) -> list[str]:
    return re.findall(r"[a-zçğıöşü]+", normalize(message))


#: Konu -> mesajda geçince o konuyu tetikleyen kökler.
#:
#: Eşleşme dile göre farklı çalışır ve bu bilinçli:
#:
#: **Türkçe: kelime BAŞI eşleşmesi.** Türkçe sondan eklemeli, yani "işim",
#: "işimle", "işten" hep "iş" ile başlar. Alt dizi araması denendi ve yanlış
#: eşleşti: "ilişkimde" kelimesinin içinde de "iş" geçiyor (il-**iş**-kimde)
#: ve ilişki sorusu meslek konusunu tetikliyordu.
#:
#: **İngilizce: alt dizi.** Ekler öne de gelir ("overthink" içinde "think");
#: kelime başı eşleşmesi bunları kaçırırdı.
_TOPIC_TRIGGERS = {
    "tr": {
        "vocation": ("iş", "meslek", "kariyer", "çalış", "patron", "terfi",
                     "mesai", "statü", "emek", "mesleğ"),
        "relationship": ("ilişki", "sevgili", "eş", "evli", "evlen", "aşk",
                         "partner", "ayrıl", "flört", "arkadaş", "dost",
                         "nişan", "boşan", "sevdiğ"),
        # S-turu: "para" ve "aile" hiç konu SAYILMIYORDU. Ölçüldü — "Para
        # konusunda hep aynı hatayı yapıyorum" ve "Babamla aram düzelmeyecek
        # mi" RAG'e hiç gitmiyordu, oysa korpusta artık doğrudan karşılığı
        # var (servet_doktrin.md, aile_doktrin.md).
        "money": ("para", "borç", "kazanç", "geçim", "birikim", "maaş",
                  "harca", "tasarruf", "gelir", "zengin", "fakir",
                  "yoksul", "servet"),
        "family": ("annem", "babam", "anneme", "babama", "annemle",
                   "babamla", "annesi", "babası", "ebeveyn", "kardeş",
                   "abim", "ablam", "kardeşim", "ailem", "ailesi",
                   "çocuğum", "evlad"),
        "mind": ("düşün", "kafam", "zihin", "odaklan", "karar", "anlam",
                 "öğren", "konsantr", "unut", "hafıza", "akıl", "akl"),
        "temperament": ("mizaç", "mizac", "huy", "karakter", "element",
                        "kişilik", "doğam", "yapım"),
        # "yüz" tek başına KULLANILMIYOR: "bu yüzden", "onun yüzünden" gibi
        # kalıplar Türkçede çok sık ve konuyla ilgisiz. Daha dar kökler ve
        # çok kelimeli kalıplar tercih edildi.
        "physiognomy": ("yüzüm", "suratım", "çehre", "sima", "firaset",
                        "kıyafetname", "yüz okuma", "yüz hat"),
        "travel": ("yolculuk", "seyahat", "taşın", "göç", "yurtdışı",
                   "uzağa", "şehir değiş"),
        # "bugün", "şimdi" gibi kelimeler BİLEREK yok: sıradan sohbette çok
        # sık geçiyorlar ve "bugün biraz keyifsizim" gibi bir duygu ifadesini
        # dönem sorusu sanmaya yol açıyorlardı.
        "timing": ("dönem", "transit", "ne zaman", "bu ara", "şu an",
                   "bu sıralar"),
    },
    "en": {
        "vocation": ("job", "work", "career", "profession", "boss",
                     "promotion", "employ", "vocation", "business",
                     "colleague", "office"),
        "relationship": ("relationship", "partner", "marri", "love",
                         "boyfriend", "girlfriend", "spouse", "dating",
                         "breakup", "friend", "divorce", "engaged"),
        # S-turu: "money" and "family" weren't topics at all. Measured —
        # "I keep making the same mistake with money" and "will things
        # ever be right with my father" never reached RAG, though the
        # corpus now has a direct answer (wealth_doctrine.md,
        # family_doctrine.md).
        "money": ("money", "debt", "income", "savings", "salary", "spend",
                  "afford", "broke", "wealth", "poor", "rich", "budget"),
        "family": ("my mother", "my father", "my mom", "my dad",
                   "my parent", "my sibling", "my brother", "my sister",
                   "my family", "my child", "my kid", "my son",
                   "my daughter"),
        "mind": ("think", "mind", "focus", "decide", "decision", "learn",
                 "memory", "understand", "concentrat"),
        "temperament": ("temperament", "character", "personality", "nature",
                        "element", "who i am"),
        "physiognomy": ("my face", "facial", "physiognom", "my looks",
                        "my features", "face reading", "appearance"),
        "travel": ("travel", "move abroad", "relocat", "journey", "emigrat",
                   "moving to"),
        # "when" ve "today" bilerek yok — İngilizcede her cümlede geçebilirler.
        "timing": ("right now", "period", "transit", "these days", "lately",
                   "at the moment"),
    },
}


def _topic_hits(message: str, dil: str, konu: str) -> int:
    kokler = _TOPIC_TRIGGERS[dil][konu]
    dusuk = normalize(message)
    kelimeler = _words(message)
    adet = 0
    for kok in kokler:
        if " " in kok or dil != "tr":
            adet += 1 if kok in dusuk else 0
        else:
            adet += 1 if any(k.startswith(kok) for k in kelimeler) else 0
    return adet


def detect_topics(message: str, lang: str | None = None) -> list[str]:
    """Mesajın hangi konu(lar)a değdiğini döndürür.

    Konu, bilgi tabanında karşılığı olan bir alan demektir; bu yüzden konu
    tespiti aynı zamanda "korpusta aranacak bir şey var" kanıtıdır
    (bkz. `should_use_rag`).
    """
    dil = lang if lang in _TOPIC_TRIGGERS else "tr"
    skorlar = [(_topic_hits(message, dil, konu), konu)
               for konu in _TOPIC_TRIGGERS[dil]]
    skorlar = sorted((s for s in skorlar if s[0]), key=lambda s: -s[0])
    # En fazla iki konu: üçüncüsü sorguyu odaksız hale getiriyor.
    return [konu for _, konu in skorlar[:2]]


def should_use_rag(message: str, lang: str | None = None) -> bool:
    """Mesaj kadim bilgi gerektiriyorsa True; selamlaşma/duygu/onay ise False."""
    lowered = normalize(message)
    words = _words(message)

    # Alan terimi geçiyorsa korpus her zaman değerli
    if any(term in lowered for term in _DOMAIN_TERMS):
        return True

    # Bilinen bir konuya değiyorsa korpusta karşılığı var demektir.
    #
    # Bu kapı olmadan "İşimle ilgili ne yapmalıyım?" RAG'e hiç uğramıyordu:
    # mesajda alan terimi yok, "ne yapmalıyım" derin soru kalıbı listesinde
    # değil ve mesaj 4 kelime olduğu için kısa sayılıp eleniyordu. Oysa
    # korpusta o soruya doğrudan cevap veren bir bölüm var.
    #
    # "timing" TEK BAŞINA yeterli sayılmaz: zaman kelimeleri duygu
    # paylaşımında da geçiyor ve tek başına korpusa gitmeyi haklı çıkarmıyor.
    # Gerçek bir dönem sorusu ("şu an nasıl bir dönemdeyim") zaten aşağıdaki
    # soru kalıbı kapısından geçer.
    if [k for k in detect_topics(message, lang) if k != "timing"]:
        return True

    # "neden/nasıl/anlat" gibi derin soru kalıpları (tam kelime eşleşmesi)
    if "ne demek" in lowered or any(w in _QUESTION_WORDS for w in words):
        return True

    # Kısa mesajlar ve bariz sohbet/duygu ifadeleri: RAG atla
    if len(words) <= 5:
        return False
    if any(w in _SMALL_TALK for w in words):
        return False

    # Alan terimi içermeyen serbest sohbet: korpusun katkısı düşük, atla
    return False


def compose_chat_message(message: str, passages: list[dict],
                         memory: str = "", chart: str = "",
                         sky: str = "", relationship: str = "",
                         circle: str = "",
                         seed_question: str = "", seed_pending: bool = False,
                         lang: str | None = None) -> str:
    """Bilgi tabanı pasajlarını, kullanıcı hafızasını, haritasını ve bugünün
    gökyüzünü mesaja iliştirir.

    Hepsi "arka plan fısıltısı" olarak verilir: model bunları blok halinde
    aktarmaz, en fazla tek bir ilgili ayrıntıyı kendi cümlesine sindirir.
    Hafızayı olduğu gibi döktürmek, kullanıcıya "hakkında tuttuğum notlar"
    okumak gibi olur ve ürkütücüdür.

    ``relationship`` (R4-2): kullanıcı bir ARKADAŞ bağlamında soruyorsa
    sunucunun ölçtüğü ilişki eksenleri buradan girer. Cihaz bulgusuydu:
    bağlam olmadan model arkadaşı tanımadan kullanıcının kendi haritasından
    GENEL cevap uyduruyordu ("ikimiz özelinde cevap vermesi gerekirken").

    ``circle`` (KA6): kullanıcının Çevrem listesi + arkadaşları, kompakt.
    Model çevreyi BİLİR (kim var, ilişki türleri, burçları) ama sayıp
    dökmez; konu değince doğal biçimde işe katar. Ölçüm içermez.

    SIRA BİR SÖZLEŞMEDİR (48-turu), süs değil: bloklar hafıza → ilişki →
    harita → çevre → gökyüzü → kaynak → tohum sırasıyla dizilir ve
    kullanıcının mesajı en sona gelir. Mesaja YAKINLIK modelde AĞIRLIK
    demek, bu yüzden en yakın yerde HESAPLANMIŞ veri durur, en uzak yerde
    de en eski ve en belirsiz olan (hafıza). Sırayı değiştirmek, prompt'ta
    tek kelime değiştirmeden ürünün neyi öne çıkardığını değiştirir.

    BÜTÇE: bu fonksiyonun döndürdüğü metnin "kullanıcı mesajı dışındaki"
    kısmı ``MAX_WHISPER_CHARS``ı aşmaz; her blok kendi tavanına kırpılır.
    Kullanıcının mesajı KIRPILMAZ (gerekçe yukarıda, tavanların yanında).

    Hiçbiri yoksa mesaj olduğu gibi döner; API şeması ve model arayüzü değişmez.
    """
    whispers = []
    p_etiket = prompts.get(lang)
    for passage in passages[:MAX_PASSAGES]:
        text = re.sub(r"\s+", " ", passage.get("text", "")).strip()
        if len(text) > MAX_PASSAGE_CHARS:
            text = text[:MAX_PASSAGE_CHARS].rsplit(" ", 1)[0] + "…"
        if not text:
            continue
        # RD5: kitap pasajları İÇ etiket taşır (okul + dönem + otorite) —
        # model çelişen gelenekleri ayırt edip yüksek otoriteyi izleyebilsin.
        # Etiket YALNIZ modele; WHISPER_RAG kullanıcıya anmayı yasaklar.
        # Kitap/yazar adı etikete BİLEREK girmez. Eski md pasajları
        # etiketsiz kalır (kaynakta school alanı yok).
        kaynak = passage.get("source") or {}
        okul = kaynak.get("school_tr" if (lang or "tr") != "en"
                          else "school")
        if okul:
            donem = kaynak.get("era_tr" if (lang or "tr") != "en"
                               else "era") or ""
            otorite = passage.get("authority") or 0
            etiket = okul if not donem else f"{okul} · {donem}"
            if otorite:
                etiket += " · " + p_etiket.RAG_AUTHORITY_FMT.format(
                    weight=otorite)
            whispers.append(f"- [{etiket}] {text}")
        else:
            whispers.append(f"- {text}")

    # Kırpma BURADA, birleştirmeden önce: aşağıdaki toplam bütçe iddiası
    # ancak her blok kendi tavanına uyarsa kanıtlanabilir olur.
    memory = _kirp((memory or "").strip(), MAX_MEMORY_CHARS)
    chart = _kirp((chart or "").strip(), MAX_CHART_CHARS)
    sky = _kirp((sky or "").strip(), MAX_SKY_CHARS)
    relationship = _kirp((relationship or "").strip(),
                         MAX_RELATIONSHIP_CHARS)
    circle = _kirp((circle or "").strip(), MAX_CIRCLE_CHARS)
    seed_question = _kirp((seed_question or "").strip(), MAX_SEED_CHARS)
    if (not whispers and not memory and not chart and not sky
            and not relationship and not circle and not seed_question):
        return message

    # Etiketler dile göre gelir: İngilizce sohbette Türkçe başlık görmek modeli
    # dil karıştırmaya iter.
    labels = prompts.get(lang)
    parts = []
    # HAFIZA EN ÖNDE — yani EN ZAYIF konumda (48-turu).
    #
    # Eskiden hafıza sondan ikinciydi ve tohum sorusu yalnız Rytho'nun
    # açtığı konuşmalarda var; yani NORMAL bir turda hafıza prompt'un EN
    # SON bloğuydu, kullanıcının mesajına en yakın yer. Yakınlık modelde
    # ağırlık demek ve sahibin şikâyeti birebir bunun tarifiydi: hafıza
    # "haritaları, gezegenleri, kitabı bilgileri zehirleyen bir yapı".
    #
    # Düzeltme ters sırada: hafıza en başa, ölçülmüş astrolojik veri
    # (ilişki → harita → çevre → gökyüzü) ve kadim kaynak ONUN ARDINA.
    # Böylece mesaja en yakın duran şey HESAPLANMIŞ olan oluyor, en uzak
    # duran şey de en eski ve en belirsiz olan. Hafıza hâlâ prompt'ta —
    # kaldırmak "seni tanıyor" hissini öldürürdü — ama artık çerçeve
    # kuruyor, gündem kurmuyor. Dil tarafı da aynı turda değişti
    # (`prompts.WHISPER_MEMORY`: "kullan" → "yalnız doğrudan ilgiliyse").
    if memory:
        parts.append(labels.WHISPER_MEMORY + "\n" + memory)
    # İlişki bağlamı ölçümlerin EN ÖNÜNDE: soru o arkadaş hakkındaysa
    # modelin merkezi bu ölçüm olmalı, kullanıcının kendi haritası
    # destekleyici kalmalı.
    if relationship:
        parts.append(labels.WHISPER_RELATIONSHIP + "\n" + relationship)
    if chart:
        parts.append(labels.WHISPER_CHART + "\n" + chart)
    # Çevre HARİTADAN SONRA, gökyüzünden önce: arka plan bilgisi ama
    # "bugünün göğü"nden daha kalıcı.
    if circle:
        parts.append(labels.WHISPER_CIRCLE + "\n" + circle)
    if sky:
        parts.append(labels.WHISPER_SKY + "\n" + sky)
    if whispers:
        parts.append(labels.WHISPER_RAG + "\n" + "\n".join(whispers))
    # SS-turu: konuşmayı Rytho açtıysa açılış sorusu EN SONA, kullanıcı
    # mesajının hemen üstüne girer — cevabın neye cevap olduğu modele en
    # yakın yerde dursun. İddia turdan tura değişir: yalnız tohum HENÜZ
    # cevaplanmamışken "bu mesaj sorunun cevabıdır" denir.
    if seed_question:
        kalip = (labels.WHISPER_SEED_PENDING if seed_pending
                 else labels.WHISPER_SEED_PAST)
        parts.append(kalip.format(question=seed_question))

    return ("\n\n".join(parts)
            + f"\n\n{labels.USER_MESSAGE_LABEL}: {message}")

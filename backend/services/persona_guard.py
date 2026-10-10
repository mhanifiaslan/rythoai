"""Persona bekçisi — sohbet yanıtı Rytho'nun YETKİ ALANINDA kalsın.

## Neden var (üretimde ölçüldü, 2026-10-10)

Konuşma ssFpW7dgpeHkD37GGLwj: kullanıcı akşamki sunumunu anlatırken model
9. turda KENDİLİĞİNDEN "sunumun havasını nasıl tasarlayacağını düşünürsen,
buradayım" diye teklif etti; 12. turda "sen sunum hazırlayabilir misin"
gelince 13. turda "harika bir sunum taslağı ve akış planı hazırlayabilirim
elbette, hangi konuda konuşacağınızı, öğrencilerin yaş grubunu … anlatman
yeterli" dedi. Rytho astrolog-yoldaş olmaktan çıkıp genel amaçlı asistana
dönüştü; prompt'ta yetki alanını sınırlayan TEK cümle yoktu.

İkinci sınıf: sohbete yazılan doğum tarihinden harita uydurma. "29/04/2010
istanbul" → "Ayşe Öykü, Güneş'i Boğa burcunda ve Ay'ı Akrep burcunda".
Sohbet HİÇBİR ŞEY hesaplamaz; kişi haritası yalnız Çevrem'de hesaplanır ve
fısıltıyla gelir. `fact_guard` bunu yakalayamaz ve sebebi biçim değil
(ölçüldü: `extract_claims` "Güneş'i Boğa burcunda" biçimini görüyor) —
iddia kümesi KİMİN Güneş'i olduğunu bilmez: kullanıcının kendi Güneş'i
Boğa'ysa ("sign", "Sun", "taurus") dayanakta vardır ve üçüncü kişiye
yakıştırılan aynı iddia "doğru" sayılır. Sahibi ancak ADIN ele verir.

## Üç katman, hepsi deterministik ve çevrimdışı

1. GİRİŞ fısıltısı (`whisper` / `attach`): mesaj görev talebi ya da doğum
   verisi taşıyorsa prompt'a kısa bir uyarı iliştirilir — modeli kusurdan
   ÖNCE çevirmek, ÇIKTIYI düzeltmekten ucuzdur (bir LLM turu).
2. ÇIKIŞ bekçisi (`drifted`, `third_party_claims`): yanıt görev
   üstleniyor/teklif ediyor ya da fısıltıda olmayan bir kişiye
   Güneş/Ay/Yükselen yakıştırıyorsa kusurludur.
3. `enforce`: kusur varsa BİR kez yeniden üretim; hâlâ kusurluysa metin
   kullanıcıya GİTMEZ — dile göre dürüst sabit cümle döner. `fact_guard`
   aynı dalda metni yine döndürür (rapor yüzeyleri önbellek kararı için ona
   dayanıyor, bkz. oradaki `enforce` docstring'i); sohbette o dal yanlıştır
   — kullanıcı "sunum taslağı hazırlayabilirim"i gördü.

## Eşleşme disiplini (CLAUDE.md §5)

`str.lower()` Türkçe bilmez; diyakritik önce katlanır (`_katla`), sonra
küçültülür ve kalıplar ASCII'dir. Her kalıp KELİME SINIRINA bağlı: "yaz"
tek başına mevsimdir ("bu yaz ne olacak"), görev ancak görev nesnesi ve
talep ekiyle görevdir ("sunumu yazar mısın"). Yanlış pozitifin bedeli bir
LLM turu ve en kötü hâlde yanlış bir "alanım değil" cümlesi; bu yüzden
kalıplar DAR tutuldu ve her sınır testte çivili
(`tests/test_persona_guard.py`).
"""
from __future__ import annotations

import logging
import re
from typing import Callable

from services import prompts

logger = logging.getLogger(__name__)

#: Kusur türleri — `enforce` bunlara göre düzeltme ve sabit cümle seçer.
KUSUR_GOREV = "task"
KUSUR_UCUNCU_KISI = "third_party"

_KATLAMA = str.maketrans({
    "ç": "c", "Ç": "c", "ğ": "g", "Ğ": "g", "ı": "i", "I": "i", "İ": "i",
    "ö": "o", "Ö": "o", "ş": "s", "Ş": "s", "ü": "u", "Ü": "u",
    "â": "a", "î": "i", "û": "u", "’": "'",
})


def _katla(metin: str) -> str:
    """Diyakritiği ASCII'ye katlar, SONRA küçültür.

    Sıra önemli: ``"İ".lower()`` ``i + U+0307`` üretir; önce katlayıp sonra
    küçültmek bunu baştan engeller, artakalan birleşen nokta da silinir.
    """
    return (metin or "").translate(_KATLAMA).lower().replace("̇", "")


# ---------------------------------------------------------------------------
# 1. GİRİŞ: görev talebi
# ---------------------------------------------------------------------------
#
# Üç işaret birlikte aranır — `safety_rules.forbidden_topic` ile aynı
# darlık ilkesi: tek kelime yetmez.
#
#   * GÖREV NESNESİ: sunum/ödev/metin/kod… (astrolojik nesne değil)
#   * ZAYIF FİİL: hazırla/yaz/yap/oluştur… — tek başına her şeyi kapsar
#     ("ne yapmalıyım" bir karar sorusudur, görev değil), bu yüzden
#     nesne ister.
#   * GÜÇLÜ FİİL: araştır/kodla/google — nesnesiz de görevdir.
#   * TALEP: mısın/-abilir/lütfen/bana… — "sunumum var, yetişmiyor" bir
#     yük paylaşımıdır, delege etme değil; persona onu zaten karşılıyor.
#
#   görev = TALEP ∧ ((NESNE ∧ (ZAYIF ∨ GÜÇLÜ)) ∨ GÜÇLÜ)
_GOREV_NESNESI = {
    "tr": re.compile(
        r"\b(?:sunum\w*|slayt\w*|odev\w*|makale\w*|kompozisyon\w*|"
        r"e-?posta\w*|mail\w*|cv|ozgecmis\w*|dilekce\w*|rapor\w*|tez\w*|"
        r"kod\w*|ceviri\w*|arastirma\w*|tarif\w*|metin\w*|taslak\w*|"
        r"konusma metni|ders notu|proje\w*|"
        r"ingilizce\w*|turkce\w*|almanca\w*|fransizca\w*)\b"),
    "en": re.compile(
        r"\b(?:presentation\w*|slides?|slide ?deck|deck|homework|essay\w*|"
        r"assignment\w*|e-?mails?|cover letter|resume|cv|report\w*|thesis|"
        r"code|scripts?|program\w*|translation\w*|summary|summaries|"
        r"research|recipes?|text|drafts?|outlines?|speech\w*|lesson plan|"
        r"projects?|talking points)\b"),
}
_ZAYIF_FIIL = {
    "tr": re.compile(
        r"\b(?:hazirla\w*|yaz\w*|yap\w*|olustur\w*|tasarla\w*|duzenle\w*|"
        r"bul\w*|kur\w*|planla\w*|ozetle\w*|cevir\w*|yardim\w*|destek\w*|"
        r"ver)\b"),
    "en": re.compile(
        r"\b(?:write|writing|prepare|preparing|make|making|create|creating|"
        r"draft|drafting|design|designing|build|building|put together|"
        r"help|fix|edit|improve|proofread|translate|translating|"
        r"summari[sz]e|do)\b"),
}
_GUCLU_FIIL = {
    "tr": re.compile(r"\b(?:arastir\w*|kodla\w*|googl\w*|internette)\b"),
    "en": re.compile(
        r"\b(?:research|google|look (?:it |this |that )?up|"
        r"search the web)\b"),
}
_TALEP = {
    "tr": re.compile(
        r"\bm[iu]s[iu]n(?:iz)?\b|(?:abilir|ebilir)\b|(?:sana|sene)\b|"
        r"\b(?:lutfen|istiyorum|isterim|rica|bana|benim icin|yerime)\b"),
    "en": re.compile(
        r"\b(?:can you|could you|would you|will you|please|help me|"
        r"i need you|i want you|for me|write me|make me|give me|"
        r"do you mind|are you able)\b"),
}


def task_request(message: str, lang: str | None = None) -> bool:
    """Mesaj Rytho'ya bir GÖREV mi delege ediyor (sunum/ödev/metin/kod…)?

    ``lang`` yalnız hangi kalıp kümesinin ÖNCE sınandığını belirler; mesaj
    her iki dilin kalıplarına da bakılır — Türkçe oturumda İngilizce
    yazan kullanıcı var (`safety_rules` ile aynı tercih).
    """
    hedef = _katla(message)
    if not hedef.strip():
        return False
    diller = ("tr", "en") if (lang or "tr") != "en" else ("en", "tr")
    for dil in diller:
        if not _TALEP[dil].search(hedef):
            continue
        guclu = bool(_GUCLU_FIIL[dil].search(hedef))
        nesne = bool(_GOREV_NESNESI[dil].search(hedef))
        zayif = bool(_ZAYIF_FIIL[dil].search(hedef))
        if guclu or (nesne and zayif):
            return True
    return False


# ---------------------------------------------------------------------------
# 1b. GİRİŞ: doğum verisi
# ---------------------------------------------------------------------------
_AYLAR = (
    r"ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|"
    r"aralik|january|february|march|april|may|june|july|august|september|"
    r"october|november|december|jan|feb|mar|apr|jun|jul|aug|sept?|oct|nov|"
    r"dec")
_DOGUM_VERISI = (
    # 29/04/2010 · 29.04.2010 · 29-4-10
    re.compile(r"\b\d{1,2}[./\-]\d{1,2}[./\-](?:19|20)?\d{2}\b"),
    # 2010-04-29 (ISO)
    re.compile(r"\b(?:19|20)\d{2}-\d{1,2}-\d{1,2}\b"),
    # 29 nisan 2010 · april 29, 2010 · 29 april 2010
    re.compile(rf"\b\d{{1,2}}\s+(?:{_AYLAR})\s+(?:19|20)\d{{2}}\b"),
    re.compile(rf"\b(?:{_AYLAR})\s+\d{{1,2}},?\s+(?:19|20)\d{{2}}\b"),
    # "1990 doğumlu", "doğumluyum", "born on/in"
    re.compile(r"\bdogumlu\w*|\bborn (?:on|in)\b"),
)


def birth_data_in_message(message: str) -> bool:
    """Mesajda bir doğum tarihi (ya da "doğumlu"/"born") geçiyor mu?

    Yalnız "doğum tarihi" demek yetmez ("doğum tarihimi değiştirmek
    istiyorum" bir ayar sorusudur) — bir TARİH ya da doğumluluk beyanı
    gerekir. Tarih bir transit sorusu da olabilir ("10.10.2026'da ne
    olacak"); fısıltı bu yüzden "kişinin doğum verisiyse" diye koşullu
    konuşur, kararı model verir.
    """
    hedef = _katla(message)
    return any(k.search(hedef) for k in _DOGUM_VERISI)


def whisper(message: str, lang: str | None = None) -> str:
    """Mesaja göre prompt'a eklenecek kısa uyarı(lar); yoksa boş dize."""
    p = prompts.get(lang)
    satirlar = []
    if task_request(message, lang):
        satirlar.append(p.PERSONA_WHISPER_TASK)
    if birth_data_in_message(message):
        satirlar.append(p.PERSONA_WHISPER_BIRTH)
    return "\n".join(satirlar)


def attach(composed: str, user_message: str, lang: str | None = None) -> str:
    """Fısıltıyı KULLANICI MESAJININ HEMEN ÜSTÜNE iliştirir.

    `compose_chat_message` SONRASINDA çağrılır (o modül bu paketin değil).
    Yer bilinçli: mesaja yakınlık modelde ağırlık demek
    (`prompt_composer` sıra sözleşmesi) ve bu uyarı tam o turun mesajına
    dairdir. Hiç fısıltı kurulamamışsa (çıplak mesaj) etiket de burada
    eklenir ki uyarı ile mesaj birbirine karışmasın.
    """
    ek = whisper(user_message, lang)
    if not ek:
        return composed
    etiket = f"\n\n{prompts.get(lang).USER_MESSAGE_LABEL}: "
    yer = composed.rfind(etiket)
    if yer >= 0:
        return composed[:yer] + "\n\n" + ek + composed[yer:]
    return ek + etiket + composed


# ---------------------------------------------------------------------------
# 2. ÇIKIŞ: persona kayması
# ---------------------------------------------------------------------------
#
# Yanıt tarafında nesne listesi GİRİŞTEKİNDEN DAR: "plan" ("planların"),
# "konuşma" ("konuşmamız"), "özet" ("özetleyeyim") doğal astroloji
# cümlelerinde geçer ve tek başına kusur değildir. Kusur, nesne + şu
# üçünden biri: (A) üstlenme/teklif fiili, (B) görev için bilgi toplama
# sorusu, (C) "nasıl tasarlayacağını düşünürsen buradayım" biçimli
# kendiliğinden teklif, (D) madde/numara listesi.
_KAYMA_NESNESI = {
    "tr": re.compile(
        r"\b(?:sunum\w*|slayt\w*|odev\w*|taslak\w*|akis plani|sunum plani|"
        r"calisma plani|metin\w*|e-?posta\w*|mail\w*|cv|ozgecmis\w*|"
        r"kod\w*|makale\w*|kompozisyon\w*|arastirma\w*|ceviri\w*|"
        r"konusma metni|icerik plani|baslik onerisi|basliklar\w*)\b"),
    "en": re.compile(
        r"\b(?:presentation\w*|slides?|slide ?deck|deck|outlines?|drafts?|"
        r"homework|essay\w*|assignment\w*|e-?mails?|cover letter|resume|cv|"
        r"code|scripts?|report\w*|translation\w*|recipes?|talking points|"
        r"speech\w*|lesson plan|agenda)\b"),
}
#: (A) Birinci tekil üstlenme/teklif. "yardımcı olabilirim" tek başına
#: dost cümlesidir ("gerginlikle başa çıkmanda yardımcı olabilirim");
#: hazırlama/tasarlama kökü de yanında olmalı.
_TEKLIF = {
    "tr": re.compile(
        r"\b(?:hazirlayabilirim|hazirlarim|hazirlayayim|hazirlayalim|"
        r"yazabilirim|yazarim|yazayim|yazalim|tasarlayabilirim|"
        r"tasarlayayim|tasarlayalim|olusturabilirim|olusturayim|"
        r"olusturalim|ozetleyebilirim|ozetleyeyim|cevirebilirim|cevireyim|"
        r"arastirabilirim|arastirayim|kodlayabilirim|kurabilirim|"
        r"kuralim|duzenleyebilirim|duzenleyeyim)\b"),
    "en": re.compile(
        r"\bi(?:'d| would| can| could|'ll| will)(?: be)?(?: happy| glad)?"
        r"(?: to)? (?:draft|write|prepare|put together|create|design|"
        r"outline|build|translate|summari[sz]e|research|code|sketch|"
        r"structure)\b"),
}
_GENEL_YARDIM = {
    "tr": re.compile(r"\byardim(?:ci)? (?:ol|ed)\w*"),
    "en": re.compile(r"\b(?:happy|glad|here) to help\b|\bhelp you\b"),
}
_HAZIRLIK_KOKU = {
    "tr": re.compile(r"\b(?:hazirl|tasarl|planl|kurgul|yaz|olustur)\w*"),
    "en": re.compile(
        r"\b(?:prepar|design|structur|draft|writ|build|outlin|plan)\w*"),
}
#: (B) Görev için bilgi toplama — "anlatman yeterli".
_BILGI_TOPLAMA = {
    "tr": re.compile(
        r"\b(?:hangi konuda|konusu ne|yas grubu\w*|kac dakika\w*|"
        r"kac slayt|hedef kitle\w*|anlatman yeterli|anlatman yeter|"
        r"detaylari (?:ver|paylas|yaz)\w*|bilgileri (?:ver|paylas|yaz)\w*|"
        r"ne kadar sure\w*)\b"),
    "en": re.compile(
        r"\b(?:what(?:'s| is) the topic|which topic|what topic|age group|"
        r"how many slides|how long (?:is|should|do)|target audience|"
        r"just (?:tell|let) me|give me the details|send me the|"
        r"share the details)\b"),
}
#: (C) Kendiliğinden teklif: "sunumun havasını nasıl tasarlayacağını
#: düşünürsen, buradayım". "sunum gerginliğin için buradayım" bir dost
#: cümlesidir — ayıran şey tasarlama/hazırlama fiilidir.
_KENDILIGINDEN = {
    "tr": re.compile(
        r"\b(?:nasil|neyi|ne sekilde)\b.{0,30}\b(?:tasarla|hazirla|kur|"
        r"planla|yaz)\w*.{0,50}\b(?:buradayim|yardimci|yardim|yanindayim)"),
    "en": re.compile(
        r"\b(?:how to|what to|how you(?:'ll|'d| want to| might| could))\b"
        r".{0,30}\b(?:design|structure|prepare|write|build|plan|shape)\w*"
        r".{0,50}\b(?:i'm here|i am here|here for you|happy to help|"
        r"glad to help)"),
}
#: (D) Madde/numaralı liste — persona zaten yasaklıyor; görev nesnesiyle
#: birlikte "işte taslağın" demektir.
_LISTE_SATIRI = re.compile(r"^\s*(?:[-*•]|\d{1,2}[.)])\s+\S", re.M)


def drifted(reply: str, lang: str | None = None) -> bool:
    """Yanıt bir görev üstleniyor, teklif ediyor ya da görev için bilgi
    topluyor mu? Her işaret görev NESNESİ ister (bkz. yukarıdaki not)."""
    hedef = _katla(reply)
    if not hedef.strip():
        return False
    for dil in ("tr", "en"):
        nesne = _KAYMA_NESNESI[dil].search(hedef)
        if not nesne:
            continue
        if _TEKLIF[dil].search(hedef):
            return True
        if (_GENEL_YARDIM[dil].search(hedef)
                and _HAZIRLIK_KOKU[dil].search(hedef)):
            return True
        if _BILGI_TOPLAMA[dil].search(hedef):
            return True
        if _KENDILIGINDEN[dil].search(hedef):
            return True
        if len(_LISTE_SATIRI.findall(reply)) >= 3:
            return True
    return False


# ---------------------------------------------------------------------------
# 2b. ÇIKIŞ: üçüncü kişiye konum yakıştırma
# ---------------------------------------------------------------------------
#
# Türkçe'nin iyelik eki SAHİBİ söyler ve bekçi bunu kullanır: "Güneş'in"
# (2. tekil) kullanıcının kendi Güneş'idir — meşru; "Güneş'i" / "Ay'ı" /
# "Yükseleni" (3. tekil) bir başkasınındır. İngilizcede "Name's Sun".
# Ad, kalıbın hemen önünde büyük harfle durur ("Ayşe Öykü, Güneş'i…",
# "Ayşe'nin Ay'ı…", "Ayşe's Sun…"); cümle başı bağlaçları ("Ancak,
# Güneş'i…") ve astroloji sözlüğü ("Boğa Güneş'i") ad DEĞİLDİR —
# `_AD_DEGIL` listesi.
_AD = r"(?P<ad>[A-ZÇĞİÖŞÜ][a-zçğıöşüâîû]+(?:\s+[A-ZÇĞİÖŞÜ][a-zçğıöşüâîû]+)?)"
_GENITIF = r"(?:['’](?:n?[ıiuü]n))?"
_UCUNCU_KISI_TR = re.compile(
    _AD + _GENITIF + r",?\s+(?:(?:ise|de|da|icin|için|ve)\s+)?"
    r"(?:Güneş['’]?i|Gunes['’]?i|Ay['’]?ı|Ay['’]?i|Yükselen['’]?i|"
    r"Yukselen['’]?i|Yükseleni|Yükselen burcu|Yukselen burcu)"
    r"(?:nin|ni|ne|nde|nden|nın|nı|na|nda|ndan)?\b")
_UCUNCU_KISI_EN = re.compile(
    _AD + r"(?:['’]s\s+|\s+has\s+(?:a\s+|an\s+|her\s+|his\s+|their\s+)?)"
    r"(?:Sun|Moon|Rising|Ascendant)\b")
#: "Ayşe Boğa burcu(ndan)" / "Ayşe's a Taurus" — yıldızsız burç yakıştırma.
_BURC_TR = (r"(?:Koç|Koc|Boğa|Boga|İkizler|Ikizler|Yengeç|Yengec|Aslan|"
            r"Başak|Basak|Terazi|Akrep|Yay|Oğlak|Oglak|Kova|Balık|Balik)")
_BURC_EN = (r"(?:Aries|Taurus|Gemini|Cancer|Leo|Virgo|Libra|Scorpio|"
            r"Sagittarius|Capricorn|Aquarius|Pisces)")
_UCUNCU_BURC_TR = re.compile(
    _AD + _GENITIF + r"(?:,?\s+(?:burcu\s+)?" + _BURC_TR
    + r"['’]?\w*\s*burc\w*|\s+burcu\s+" + _BURC_TR + r"\b)")
_UCUNCU_BURC_EN = re.compile(
    _AD + r"(?:['’]s)?\s+(?:is|was)\s+(?:a|an)\s+" + _BURC_EN + r"\b")
#: Kalıptan sonra 48 karakter içinde burç adı yoksa iddia değildir
#: ("Ayşe'nin Güneş'i parlıyor" bir benzetmedir).
_BURC_SOZLUGU = re.compile(
    r"\b(?:koc|boga|ikizler|yengec|aslan|basak|terazi|akrep|yay|oglak|kova|"
    r"balik|aries|taurus|gemini|cancer|leo|virgo|libra|scorpio|sagittarius|"
    r"capricorn|aquarius|pisces)\w*")
_AD_DEGIL = frozenset("""
koc boga ikizler yengec aslan basak terazi akrep yay oglak kova balik
aries taurus gemini cancer leo virgo libra scorpio sagittarius capricorn
aquarius pisces gunes ay merkur venus mars jupiter saturn uranus neptun
pluton kiron lilith yukselen alcalan tepe sun moon mercury jupiter saturn
uranus neptune pluto chiron rising ascendant north south node
bugun yarin dun simdi ancak ama fakat yani aslinda bence evet hayir tabii
elbette zaten hem ayrica ustelik neyse peki tamam sonra once boylece
mesela ornegin gerci oysa yine bu su o senin sana seni sen ben biz siz
onun kendi belki iste bir iki her hic cok daha en ne nasil hangi kim neden
niye nerede cunku eger ya rytho cevrem plus bazi retro retrosu dolunay
yeniay gokyuzu burada orada ote kisacasi sonucta ozetle dogrusu acikcasi
ocak subat mart nisan mayis haziran temmuz agustos eylul ekim kasim aralik
pazartesi sali carsamba persembe cuma cumartesi pazar
haritanda haritan haritasinda haritasi haritani gokyuzunde bugunku ozellikle
simdi hele boyle soyle bence aslinda galiba herhalde sonucta sonrasinda
the today tomorrow yesterday tonight your you her his their its my our
this that these those but and so yes no well also still then now right
sure true maybe only even if when while since because here there it he
she they we i with for in on at of to a an what which who how why where
january february march april may june july august september october
november december monday tuesday wednesday thursday friday saturday sunday
""".split())


def _ad_mi(ham: str) -> str | None:
    """Yakalanan büyük harfli parçadan GERÇEK adı süzer; yoksa None.

    Başta duran bağlaç/sözlük kelimeleri atılır ("Ancak Ayşe" → "Ayşe");
    hiçbir şey kalmazsa ("Ancak", "Boğa") bu bir ad değildir.
    """
    parcalar = [p for p in ham.split() if p]
    while parcalar and _katla(parcalar[0]) in _AD_DEGIL:
        parcalar.pop(0)
    if not parcalar or any(_katla(p) in _AD_DEGIL for p in parcalar):
        return None
    return " ".join(parcalar)


def _adli_iddialar(reply: str) -> list[str]:
    """Yanıtta bir ADA bağlanmış Güneş/Ay/Yükselen/burç iddialarının adları."""
    adlar: list[str] = []
    for kalip in (_UCUNCU_KISI_TR, _UCUNCU_KISI_EN):
        for m in kalip.finditer(reply):
            ad = _ad_mi(m.group("ad"))
            if not ad:
                continue
            pencere = _katla(reply[m.end():m.end() + 48])
            if _BURC_SOZLUGU.search(pencere):
                adlar.append(ad)
    for kalip in (_UCUNCU_BURC_TR, _UCUNCU_BURC_EN):
        for m in kalip.finditer(reply):
            ad = _ad_mi(m.group("ad"))
            if ad:
                adlar.append(ad)
    return adlar


def third_party_claims(reply: str, message: str = "", circle: str = "",
                       relationship: str = "", history: str = "") -> bool:
    """Yanıt, fısıltıda ÖLÇÜMÜ OLMAYAN bir kişiye konum yakıştırıyor mu?

    Fısıltıda adıyla duran arkadaş (çevre listesi "Ad (Burç)" yazar) ya da
    ilişki ölçümündeki kişi meşrudur: onun burcu sunucuda hesaplandı.
    Ad orada yoksa iddia sohbetten uydurulmuştur — kullanıcı o adı
    mesajında vermiş olsa bile (mesajda ad geçmesi hesaplama yerine geçmez).

    KAPI: bekçi yalnız sohbete DOĞUM VERİSİ girdiğinde bakar (bu mesaj ya da
    prompt'a giren geçmiş). Ölçüldü (2026-10-10, kapanış probu): kullanıcının
    KENDİ haritasını anlatan meşru bir yanıt ("Haritanda Güneş'inin Yay
    burcundaki Jüpiter…") cümle başındaki büyük harfli sıradan kelime yüzünden
    "adlı iddia" sayılıyor ve ikinci üretim de aynı doğru cümleyi kurunca
    kullanıcıya doğru cevap yerine SABİT "Çevrem'e ekle" cümlesi gidiyordu.
    Uydurmanın ölçülmüş tek kaynağı sohbete yazılan doğum tarihidir
    (4 turun 3'ü) ve uydurma sonraki tarihsiz turlara GEÇMİŞLE taşınır —
    o yüzden kapı geçmişe de bakar, yalnız son mesaja değil.
    """
    if not (birth_data_in_message(message) or birth_data_in_message(history)):
        return False
    adlar = _adli_iddialar(reply)
    if not adlar:
        return False
    fisilti = _katla(f"{circle}\n{relationship}")
    for ad in adlar:
        parcalar = _katla(ad).split()
        # Adın HERHANGİ bir parçası fısıltıda duruyorsa ("Ayşe" → "Ayşe
        # (Boğa)") kişi ölçülmüştür. Tek harfli parça sayılmaz.
        if any(len(p) > 1 and re.search(rf"\b{re.escape(p)}\b", fisilti)
               for p in parcalar):
            continue
        return True
    return False


# ---------------------------------------------------------------------------
# 3. enforce
# ---------------------------------------------------------------------------

def _kusurlar(reply: str, lang: str | None, circle: str,
              relationship: str, message: str = "",
              history: str = "") -> list[str]:
    bulunan = []
    if third_party_claims(reply, message=message, circle=circle,
                          relationship=relationship, history=history):
        bulunan.append(KUSUR_UCUNCU_KISI)
    if drifted(reply, lang):
        bulunan.append(KUSUR_GOREV)
    return bulunan


def retry_instruction(kusurlar: list[str], lang: str | None) -> str:
    """Kusur(lar)ı modele iade eden düzeltme; birden çoksa alt alta."""
    p = prompts.get(lang)
    satirlar = []
    if KUSUR_UCUNCU_KISI in kusurlar:
        satirlar.append(p.PERSONA_RETRY_THIRD_PARTY)
    if KUSUR_GOREV in kusurlar:
        satirlar.append(p.PERSONA_RETRY_TASK)
    return "\n".join(satirlar)


def fallback(kusurlar: list[str], lang: str | None) -> str:
    """İkinci üretim de kirliyse kullanıcıya giden DÜRÜST sabit cümle.

    Üçüncü kişi önce gelir: uydurulmuş veri, görev kaymasından ağırdır.
    """
    p = prompts.get(lang)
    if KUSUR_UCUNCU_KISI in kusurlar:
        return p.PERSONA_FALLBACK_THIRD_PARTY
    return p.PERSONA_FALLBACK_TASK


def enforce(reply: str, prompt: str, lang: str | None = None,
            regenerate: Callable[[str], str | None] | None = None,
            circle: str = "", relationship: str = "",
            message: str = "", history: str = "") -> tuple[str, bool]:
    """Kusur varsa BİR kez yeniden üretir; hâlâ kusurluysa metin
    kullanıcıya GİTMEZ, sabit cümle döner.

    Dönen çift: (metin, temiz). ``temiz is False`` ise dönen metin
    modelin değil ürünün cümlesidir. `fact_guard.enforce`'tan farkı tam
    burada: o, ikinci üretimde de uydurma kalırsa metni döndürüp yalnız
    önbelleği kapatır (rapor yüzeyleri için doğru karar); sohbette kirli
    metni göstermek kusurun kendisidir — "sunum taslağı hazırlayabilirim"
    kullanıcıya bir kez gitti, bir daha gitmez.

    ``regenerate`` yoksa (ya da boş dönerse) yeniden üretim atlanır ve
    doğrudan sabit cümleye düşülür; jeton ikinci kez düşülmez (çağıran
    aynı turun kapanışını kullanır).
    """
    kusurlar = _kusurlar(reply, lang, circle, relationship, message, history)
    if not kusurlar:
        return reply, True
    logger.warning("Persona bekçisi kusur yakaladı: %s", kusurlar)
    if regenerate is not None:
        duzelti = prompt + "\n\n" + retry_instruction(kusurlar, lang)
        tekrar = regenerate(duzelti)
        if tekrar:
            kalan = _kusurlar(tekrar, lang, circle, relationship,
                              message, history)
            if not kalan:
                return tekrar, True
            logger.warning("Persona bekçisi yeniden üretimde de kusur: %s",
                           kalan)
            kusurlar = kalan
    return fallback(kusurlar, lang), False

"""Yasak alan kapısı — LLM'e hiç gitmeyen kesin engel.

Persona talimatındaki "sağlık/finans yorumu yapma" kuralı bir tavsiyedir; model
ona uyar ya da uymaz. Sağlık, hamilelik, ölüm ve finans gibi alanlarda yanlış
bir cümlenin bedeli yüksek olduğu için burada deterministik bir kapı var:
istek bu kalıplara uyuyorsa model çağrılmaz, sabit ve şeffaf bir yanıt döner.

**Kapı bilinçli olarak DARDIR.** Bir mesajın engellenmesi için hem bir YASAK
KONU hem de bir CEVAP TALEBİ işareti gerekir. Konunun tek başına geçmesi
yetmez — yoksa "annem hasta, çok üzgünüm" gibi bir duygu paylaşımı da
engellenirdi ve kullanıcı teselli aradığı anda duvara çarpardı. Bu, yasak
soruyu cevaplamaktan daha büyük bir hata olur.

İki işaret ayrı ayrı arandığı için sıraları önemli değil: "hastalığım geçecek
mi" ile "geçecek mi acaba hastalığım" aynı şekilde yakalanır.

**Konu kalıpları KELİME SINIRINA bağlıdır, alt dize eşleşmesi DEĞİL.** Kapı
bir tur boyunca alt dizeyle çalıştı ve bedeli ölçüldü (2026-10-10): "Bugün
çok kötü **hisse**diyorum, geçecek mi?" finans reddi yedi; "Bu transitin
**altın**da ne zaman rahatlarım?" finans; "Sunumu yetiştirirsem mutlu
**olurum**, ne yapmalıyım?" ölüm; "I'm **sick** of my job, will it change?"
sağlık. Dördü de sıradan sohbet cümlesi ve dördü de kullanıcıya "bu konuda
konuşamam" dedi — yani SORULMAMIŞ bir çekince. Sahibin "alakasız yere maddi
konularda tavsiye veremem diyor" şikâyetinin kaynağı buydu. Engellenen
turlar arşive yazılmadığı için 498 mesajlık korpusta kayıtlı engel SIFIRDI;
kusur yalnız ekranda görüldü. Türkçe ek aldığı için `\\b` tek başına yetmez:
her kalıp KAPALI bir ek listesiyle yazılır (`hisse` + ler/si/yi… ama
`hisse` + `diyorum` DEĞİL). Bekçisi
`test_safety_rules.py::test_kaliplar_tuzak_kelimelere_takilmaz`.

**Katlamanın sakladığı bir çakışma:** "ölür müyüm" ASCII'ye katlanınca "olur
muyum" ("will I become") ile AYNI dizeye düşer ve "zengin olur muyum" bir
ölüm sorusu değildir. Bu yüzden o kalıp katlanMAMIŞ (aksanlı) metinde aranır
(`konu_aksanli`). Aksansız yazan kullanıcı için cümle gerçekten belirsizdir
ve kapı belirsizlikte GEÇİRİR — ikinci hat persona talimatıdır.

**Kapı her dilde kurulur ve mesaj TÜM dillerin kalıplarına karşı sınanır.**
Kalıplar yalnızca Türkçe olsaydı, uygulamayı İngilizce kullanan biri için
kapı hiç var olmazdı ("will my cancer get better?" doğrudan modele giderdi) —
ve dili değiştirmek kapıyı aşmanın yolu olurdu. Konu tespiti dilden
bağımsızdır; kullanıcıya dönen yanıt onun dilindedir.

Konu ile talep işaretinin **aynı dilden** olması gerekir: diller arası eşleşme
(Türkçe konu + İngilizce talep) gerçek bir cümlede neredeyse hiç oluşmaz ama
yanlış pozitif üretebilir.

**Ret metni bir sınır beyanıdır, "tavsiye veremem" refleksi değil.** Ürün bir
lifestyle uygulaması ve Rytho bilge, dost canlısı bir astrolog: yetkin
olduğu alanı söyler ("benim alanım haritan") ve haritaya köprü kurar
("istersen bu dönemin temalarına bakalım"). Kapı DAR kaldığı için bu metin
yalnız gerçekten sorulduğunda görünür.

İkinci savunma hattı persona talimatıdır (gemini_service); bu kapı yalnızca en
maliyetli hataları keser.
"""
from __future__ import annotations

import re

from core.i18n import DEFAULT, SUPPORTED

#: Türkçe soru eki, çekimli biçimleriyle: mı, mıyım, mısın, mıyız, mısınız...
#: Sadece "mı" aramak yetmiyor ("bırakmalı mıyım" yakalanmıyordu); sonuna
#: `\w{0,4}` koymak da "mimar" gibi kelimeleri yanlışlıkla yakalıyor.
#: BAŞTAKİ `\b` şart: ek ayrı yazılır ("geçecek mi") ve sınırsız hâli
#: "kendi**mi**", "is**mi**", "res**mi**", "eli**mi**" gibi kelimelerin
#: sonuna takılıyordu — "Kendimi hasta hissediyorum" bir talep değil, duygu
#: paylaşımı; ölçüldü, kapı onu talep sayıp engelliyordu.
_SORU_TR = r"\bm[iuü](?:y[iuü]m|s[iuü]n(?:[iuü]z)?|y[iuü]z)?\b"

#: Cevap/öngörü talebi işaretleri, dile göre. Biri YOKSA mesaj engellenmez.
_TALEP: dict[str, re.Pattern[str]] = {
    "tr": re.compile(
        _SORU_TR
        + r"|olacak|olur mu|gecece|iyilesece|kurtulaca|yakalanaca"
        + r"|birakmali|ne zaman|yukselece|dusece|alsam|satsam|al[iı]r m"
        + r"|kac yil|ne kadar surece",
        re.IGNORECASE,
    ),
    # İngilizcede soru eki yok; talep yardımcı fiil ve kalıplarla kurulur.
    # `\b` sınırları şart: "will" gibi parçalar başka kelimelerin içinde geçer.
    "en": re.compile(
        r"\bwill\b|\bwon't\b|\bshould i\b|\bshall i\b|\bam i\b|\bwas i\b"
        r"|\bis it\b|\bare they\b|\bdo i\b|\bdid i\b|\bcan i\b|\bcould i\b"
        r"|\bgoing to\b|\bwhen (?:will|do|does|should)\b|\bhow long\b"
        r"|\bhow many years\b|\bwhat are (?:my|the) chances\b"
        r"|\bpredict\b|\bforecast\b|\bshould i (?:buy|sell)\b",
        re.IGNORECASE,
    ),
}


class _Rule:
    """Bir yasak alan: dile göre konu işaretleri + dile göre yanıt.

    ``konu`` ve ``yanit`` sözlükleri dil koduyla anahtarlanır. Bir dil için
    konu kalıbı tanımlanmamışsa o dilde bu kural sınanmaz.

    ``konu_aksanli`` (isteğe bağlı): katlanMAMIŞ metinde aranan kalıplar.
    Tek kullanım yeri ölüm kuralındaki "ölür müyüm" — katlanınca "olur
    muyum" ile çakışıyor (modül docstring'i).
    """

    def __init__(self, kategori: str, konu: dict[str, str],
                 yanit: dict[str, str],
                 konu_aksanli: dict[str, str] | None = None):
        self.kategori = kategori
        self.konu = {dil: re.compile(kalip, re.IGNORECASE)
                     for dil, kalip in konu.items()}
        self.konu_aksanli = {dil: re.compile(kalip, re.IGNORECASE)
                             for dil, kalip in (konu_aksanli or {}).items()}
        self.yanit = yanit


#: Türkçe AD eklerinin KAPALI listesi (çoğul + iyelik + hâl birleşimleri).
#: `\w*` DEĞİL: "hisse\w*" "hissediyorum"u, "altin\w*" "altında"yı yakalar.
#: Liste kapalı olduğu için fiil gövdeleri (hisse-t, hisse-d) dışarıda kalır;
#: iki ünlü uyumu da var ("hisse-leri-mi" / "euro-ları-mı") — tek harmoni
#: "Eurolarımı satsam mı"yı kaçırıyordu (ölçüldü).
#: "hisse" + "diyorum" hiçbir ekle eşleşmez ve `\b` düşer.
_EK = (r"(?:ler|leri|lerim|lerimi|lerin|lerini|lerde|lerden|lerle"
       r"|lar|lari|larim|larimi|larin|larini|larda|lardan|larla"
       r"|si|sini|sine|sinde|sinden|su|sunu|suna"
       r"|yi|ye|ya|yu|yla|yle|de|da|den|dan|le|la"
       r"|m|mi|n|ni|nin|niz|nizi|im|imi|in|ini|um|umu|un|unu|u|i|a|e)?")

#: Altın bir ARAÇ değil, önce bir kelime: "altın gibi fırsat", "altın kalpli",
#: "altın yıllar" ve en sinsisi "altında/altına" (under). Çıplak `altin`
#: kalıbı bunların hepsini finans reddine çeviriyordu. Kalıp alım-satım
#: BAĞLAMINA daraltıldı: "altın al/sat/fiyat/kur/yüksel/düş…" ya da
#: "gram/çeyrek/külçe altın". Ek listesi `_EK` DEĞİL: "altına"/"altını"
#: (under it) ile çakıştığı için tekil hâl ekleri bilerek yok.
_ALTIN_TR = (r"\baltin(?:lar|lari|larimi|larim|larini|im|imi)?"
             r" (?:al|sat|fiyat|kur|gram|ons|yatirim|bozdur|biriktir"
             r"|yuksel|dus)"
             r"|\b(?:gram|ceyrek|yarim|tam|cumhuriyet|kulce) altin")

#: İngilizce "Cancer" aynı zamanda bir BURÇ — bu bir astroloji uygulaması ve
#: "I'm a Cancer, will this week be good?" en sıradan soru. Çıplak `cancer`
#: onu sağlık reddine çeviriyordu. Kalıp hastalık bağlamına daraltıldı
#: ("my cancer" burç sözcüğü izlemiyorsa, "have cancer", "breast cancer",
#: "cancer treatment"…).
_ZODYAK_IZLEYEN_EN = (r"(?! (?:sun|moon|rising|ascendant|asc|season|sign"
                      r"|man|woman|men|women|guy|girl|placement|energy"
                      r"|stellium|venus|mars|mercury|jupiter|saturn|north"
                      r"|south|and|or|with|compatib|friend|partner"
                      r"|boyfriend|girlfriend|ex|husband|wife)\b)")
_KANSER_EN = (rf"\bmy cancer\b{_ZODYAK_IZLEYEN_EN}"
              r"|\b(?:have|has|had|got|beat|survive|surviving|fight"
              r"|fighting|cure|curing) cancer\b"
              r"|\bcancer (?:treatment|diagnos|patient|surgery|cure|stage"
              r"|spread|return|come back|comes back|came back|get better"
              r"|gets better|get worse|be cured|go away|goes away|kill"
              r"|free|cells?|screening|test|scan|risk)"
              r"|\b(?:breast|lung|skin|prostate|colon|bowel|brain|blood"
              r"|bone|liver|stomach|cervical|ovarian|thyroid|pancreatic"
              r"|testicular|bladder|kidney|throat|mouth|oral|rectal) cancer\b"
              r"|\bcancerous\b")

#: "ill" mesajlaşmada çoğu zaman kesme işaretsiz "I'll"dir ("ill be fine,
#: will it work out?"). Bir fiil izliyorsa hastalık değil, gelecek zaman.
_ILL_EN = (r"\bill\b(?! (?:be|do|go|get|try|see|have|make|take|call|ask"
           r"|let|just|never|always|probably|definitely|not|wait|check"
           r"|send|text|come|keep|stay|start|stop|look|find|give|tell|talk"
           r"|think|need|want|say|write|buy|sell|pay|work|leave|move|meet"
           r"|put|bring|show|help|miss|pass|hold|sleep|pick|turn|lose|know"
           r"|feel|cry|sit|stand|fall|change|end|finish|manage|deal|forget"
           r"|remember|decide|choose|hope)\b)")


#: Konu kalıpları normalize edilmiş metne (ı/İ -> i, küçük harf) uygulanır.
#: İngilizce yanıtlar Türkçenin birebir çevirisi değil: aynı dürüst duruşu o
#: dilde doğal duran bir tonla kurar.
_RULES: list[_Rule] = [
    _Rule(
        "saglik",
        {
            # "hasta\b" ve "hastayim" kalır; "hastane" bilerek yok —
            # "hastaneye gittim, annem iyi mi olacak" üçüncü kişi/duygu
            # cümlesi ve geçmeli (ölçüldü, geçiyor). "kısır döngü" bir
            # deyim, kısırlık değil.
            "tr": r"\bkanser|\btumor|\bhastali[gk]|\bteshis|\btani\b"
                  r"|\bameliyat|\bilac|\btedavi"
                  r"|\bkisir(?:lik|im|sin|iz|lar)?\b(?! ?dongu)"
                  r"|\bdepresyon|\bhasta\b|\bhastayim\b|\biyilesece",
            # "recover" / "get better" bilinçli olarak YOK: "will things get
            # better?" hayata dair sıradan bir soru ve engellenmesi kapıyı
            # aşırı geniş yapardı. "sick of" bir deyim (bıkmak), hastalık
            # değil; "silent treatment", "business operation", "study
            # medicine" de öyle.
            "en": _KANSER_EN
                  + r"|\btumou?rs?\b|\billness(?:es)?\b|\bdiseases?\b"
                  r"|\bdiagnos|\bsurger(?:y|ies)\b"
                  r"|(?<!business )\boperation\b"
                  r"|\bmedications?\b"
                  r"|(?<!study )(?<!studying )(?<!in )(?<!of )\bmedicine\b"
                  r"|(?<!silent )(?<!royal )(?<!special )\btreatment"
                  r"|\bchemo|\binfertil|\bdepress(?:ed|ion|ive)\b"
                  r"|\bsick\b(?! (?:of|and tired|to death)\b)"
                  + "|" + _ILL_EN
                  + r"|\bsymptoms?\b",
        },
        {
            "tr": "Benim alanım haritan ve gökyüzü; sağlık ise bir hekimin "
                  "alanı — bu soruyu yıldızlardan cevaplamam seni "
                  "yanıltmak olur, onu yapmam. Bunu bir hekimle konuşmanı "
                  "isterim. İstersen bu dönemin sana ne taşıdığına, "
                  "enerjinin nereye aktığına birlikte bakalım.",
            "en": "My ground is your chart and the sky above it; health "
                  "belongs with a doctor — answering this from the stars "
                  "would only mislead you, and I won't do that. I'd want "
                  "you to talk to a doctor about it. If you'd like, we can "
                  "look at what this period is carrying for you instead.",
        },
    ),
    _Rule(
        "hamilelik",
        {
            # "bebeğim" aynı zamanda bir hitap ("bebeğim beni seviyor mu?")
            # — çıplak hâli hamilelik reddi yiyordu. Yalnız "bebeğim
            # olacak/olur/ne zaman…" bağlamı sayılır.
            "tr": r"\bhamile|\bgebe(?:lik|yim)?\b"
                  r"|\bbebegim (?:olacak|olur|olsun|ne zaman|dogacak)"
                  r"|\bcocugum (?:olacak|olur|olsun|ne zaman)"
                  r"|\bcocuk sahibi|\btup bebek",
            "en": r"\bpregnan|\bconceiv(?:e|ing)\b|\bfertility\b|\bivf\b"
                  r"|\bhaving a baby\b|\bget(?:ting)? pregnant\b"
                  r"|\bexpecting a (?:baby|child)\b|\btrying for a baby\b",
        },
        {
            "tr": "Çocuk sahibi olmak gibi bir konuda gökyüzüne dayanarak "
                  "bir şey söylemem sana haksızlık olur; bu bir hekimin "
                  "alanı. Benim alanım haritan — istersen bu dönemin genel "
                  "temalarına, yeni başlangıçlara nasıl baktığına birlikte "
                  "bakalım.",
            "en": "On having children I won't speak from a chart — that "
                  "wouldn't be fair to you; it belongs with a doctor. My "
                  "ground is your sky. If you'd like, we can look at the "
                  "broader themes of this period and how it holds new "
                  "beginnings.",
        },
    ),
    _Rule(
        "olum",
        {
            # "olurum" ve "yasarim" BİLEREK YOK: "mutlu olurum", "ne
            # yaşarım bilmiyorum" günlük dil. Ömür sorusu yalnız açık
            # kalıplarla: "kaç yıl yaşarım", "ömrüm", "ölecek", "ölüm".
            # "vefat etti" (geçmiş) yok — yas tutan kişi "ne zaman
            # toparlanırım" diye sorduğunda engellenmemeli.
            "tr": r"\bolece|\bomrum\b|\byasar m[iu]y[iu]m\b"
                  r"|\bkac (?:yil|sene) (?:daha )?yasar"
                  r"|\bne kadar (?:daha )?yasar"
                  rf"|\bolum{_EK}\b|\bvefat (?:edece|eder mi)",
            # Deyimler dışarıda: "dying to know", "scared to death",
            # "do or die", "my father's death" (yas, kehanet değil).
            "en": r"(?<!or )(?<!say )\bdie\b(?! (?:hard|for|laughing|trying)\b)"
                  r"|\bdying\b(?! (?:to|for|laughing)\b)"
                  r"|(?<!to )(?<!'s )\bdeath\b(?! of\b)"
                  r"|\bpass(?:ing)? away\b"
                  r"|\bhow long (?:do|will) i (?:have|live)\b"
                  r"|\blife ?spans?\b|\bwhen will i die\b",
        },
        {
            "tr": "Ömür ve ölüm üzerine kehanet benim alanım değil — bunu "
                  "kimse bilemez, bilirmiş gibi davranmak zarar verir. "
                  "Aklını meşgul eden bir korku varsa onu konuşabiliriz; "
                  "istersen bu dönemin haritanda neye dokunduğuna birlikte "
                  "bakalım.",
            "en": "Predicting death or how long someone will live isn't my "
                  "ground — no one knows that, and pretending otherwise "
                  "does harm. If there's a fear sitting with you, we can "
                  "talk about that; or, if you'd like, we can look at what "
                  "this period is touching in your chart.",
        },
        # Aksanlı metinde: "ölür müyüm" / "ne zaman ölürüm". Katlanınca
        # "olur muyum" / "ne zaman olurum" ile çakışır (modül docstring'i).
        # "ölürüm" tek başına yok — "sensiz ölürüm" bir aşk cümlesi.
        konu_aksanli={
            "tr": r"\bölür m[üu]y[üu]m\b|\bne zaman ölürüm\b",
        },
    ),
    _Rule(
        "finans",
        {
            # Somut araçlar + ek listesi. "yatırım", "kredi", "borç" yok:
            # "kendime yatırım" finans değil, "kredi" ürünün jeton adı.
            # "fon müziği" (background music) deyimdir, fon değil.
            "tr": rf"\bhisse{_EK}\b|\bborsa|\bkripto(?!graf)|\bbitcoin"
                  rf"|\bethereum|\bbtc\b|\bcoin{_EK}\b|\bdoviz"
                  rf"|\bdolar{_EK}\b|\beuro{_EK}\b|{_ALTIN_TR}"
                  rf"|\bfon{_EK}\b(?! muzi)|\bportfoy|\bfaiz",
            # Somut araçlarla sınırlı. Yalın "invest" veya "shares" YOK:
            # "should I invest more time in this?" ya da "he shares my
            # feelings" finans sorusu değil. "gold" yalnız alım-satım/fiyat
            # bağlamında — "gold earrings" bir takı. "dollars" tek başına
            # yok: "a few dollars left, will things get better?" bir
            # yatırım sorusu değil, para TEMASI; onu model haritadan
            # anlatır. "portfolio" tasarımcının da portföyü, yalnız
            # yatırım/hisse bağlamı. "fund" fiil de olur ("will they fund
            # my project?"), yalnız fon türleri.
            "en": r"(?<!of )(?<!take )\bstocks?\b(?! up\b)|\bstock market\b"
                  r"|\bshare price|\b(?:buy|sell|buying|selling) shares\b"
                  r"|\bcrypto|\bbitcoin|\bethereum|\bbtc\b"
                  r"|(?<!flip a )(?<!toss a )(?<!same )\bcoins?\b"
                  r"|\bforex\b|\bexchange rate"
                  r"|\bthe dollar\b|\bus dollar|\busd\b"
                  r"|\bdollar (?:rate|index|exchange|price|rise|fall|drop"
                  r"|go|strengthen|weaken)"
                  r"|\b(?:buy|sell|buying|selling) (?:dollars|euros|gold)\b"
                  r"|\bthe euro\b"
                  r"|\beuro (?:rate|exchange|price|rise|fall|drop|go)"
                  r"|\bgold (?:price|rate|market|rise|fall|drop|go up"
                  r"|go down|bars?|coins?|bullion)\b"
                  r"|\binvest(?:ing)? in gold\b|\bprice of gold\b"
                  r"|\b(?:mutual|index|hedge|pension|investment) funds?\b"
                  r"|\betfs?\b|\b(?:investment|stock|crypto) portfolio\b"
                  r"|\binterest rates?\b",
        },
        {
            "tr": "Al-sat kararı benim alanım değil; onu yetkili bir "
                  "danışmanla konuşmanı isterim. Benim alanım haritan — "
                  "istersen bu dönemin para ve kaynaklarla ilgili "
                  "temalarına birlikte bakalım.",
            "en": "Buy-or-sell calls aren't my ground — that's for a "
                  "licensed advisor. What I can read is your chart: if "
                  "you'd like, let's look at what this period says about "
                  "money and resources for you.",
        },
    ),
]


#: Türkçe harfleri ASCII'ye katlama tablosu.
#: Kalıplar ASCII yazılır, gelen metin buraya katlanır — aksi halde her kalıbı
#: "yasarim|yaşarım" gibi çift yazmak gerekir ve biri mutlaka atlanır.
_FOLD = str.maketrans({
    "ç": "c", "Ç": "c", "ğ": "g", "Ğ": "g",
    "ı": "i", "I": "i", "İ": "i", "i": "i",
    "ö": "o", "Ö": "o", "ş": "s", "Ş": "s",
    "ü": "u", "Ü": "u",
    # Bileşik noktalı i (aşağıdaki nota bakın)
    "̇": "",
})

#: Yalnız BÜYÜK/küçük katlaması, aksanlar yerinde: `konu_aksanli` için.
#: Türkçeye özel iki harf elle: Python'da "I".lower() "i" verir ("ı" değil),
#: "İ".lower() ise "i" + birleşen nokta.
_KUCULT = str.maketrans({"I": "ı", "İ": "i"})


def _normalize(text: str) -> str:
    """Metni ASCII'ye katlar ve küçük harfe indirir.

    Sıra önemli: Python'da ``"İ".lower()`` iki kodpuanlı ``i + U+0307`` üretir,
    yani önce küçültüp sonra "İ" aramak hiçbir zaman eşleşmez. Bu yüzden
    katlama küçültmeden ÖNCE yapılır; artakalan birleşen nokta da tabloda
    siliniyor.
    """
    return text.translate(_FOLD).lower().replace("̇", "")


def _kucult(text: str) -> str:
    """Aksanları KORUYARAK küçük harfe indirir (`konu_aksanli` hedefi)."""
    return text.translate(_KUCULT).lower().replace("̇", "")


#: KRİZ İŞARETLERİ — kullanıcının KENDİSİ zor durumda (S-turu).
#:
#: ## Neden yasak-konu kapısından ayrı
#:
#: Yasak konu kapısı iki işaret arıyor: konu VE cevap talebi. Bu doğru bir
#: darlık ("annem hasta, üzgünüm" engellenmemeli). Ama krizde olan biri
#: SORU SORMAZ; "artık yaşamak istemiyorum" der ve orada durur. İki işaret
#: aramak, bu cümlenin kapıdan geçmesi demekti — ölçüldü, geçiyordu:
#: doğrudan astroloji modeline gidiyor ve persona gereği "önce duyguyu
#: kabul et, sonra kozmik pencere aç" cevabı alıyordu.
#:
#: Bu yüzden burada TEK işaret yeter.
#:
#: ## Darlık nasıl korunuyor
#:
#: Kalıplar niyet bildiren tam ifadelere bağlı, tek kelimeye değil.
#: "bitirmek" tek başına yok ("bu işi bitirmek istiyorum" krize girmez);
#: "hayatımı bitirmek" var. Yanlış pozitif riski bilinçli kabul edilir:
#: krizde olmayan birine yardım hattı göstermek, gerçekten krizde olana
#: burç yorumu vermekten kat kat iyidir.
_CRISIS_PATTERNS: dict[str, str] = {
    "tr": (
        r"intihar"
        r"|kendimi oldur|kendime zarar|canima kiy"
        r"|yasamak istemiyorum|yasamak istemiyor"
        r"|olmek istiyorum|olsem keske|keske olsem"
        r"|hayatima son|hayatimi bitir|her seye son ver"
        r"|yasamanin anlami kalmadi|yasamak icin bir sebep"
        r"|dayanacak gucum kalmadi|artik dayanamiyorum"
        # Şiddet mağduriyeti: astroloji sorusu değil, güvenlik meselesi.
        r"|siddet uygul|dovuyor|tehdit ediyor|beni doviyor"
        r"|tacize ugra|tecavuz"
        # Akut panik: "geçirdim" (geçmiş) değil, ŞU AN.
        r"|panik atak geciriyorum|nefes alamiyorum"
    ),
    "en": (
        r"suicide|suicidal"
        r"|kill myself|hurt myself|harm myself|end my life"
        r"|want to die|wish i was dead|wish i were dead"
        r"|end it all|no reason to live|can't go on|cannot go on"
        r"|can't take it anymore|cannot take it anymore"
        r"|abusing me|beating me|threatening me|assault|raped"
        r"|having a panic attack|can't breathe"
    ),
}

_CRISIS_RE: dict[str, re.Pattern[str]] = {
    dil: re.compile(kalip, re.IGNORECASE)
    for dil, kalip in _CRISIS_PATTERNS.items()
}


def crisis_signal(message: str) -> str | None:
    """Mesaj kriz işareti taşıyorsa kategori adını döner, yoksa ``None``.

    Yanıt METNİ burada değil `core.messages` içinde: kullanıcıya dönen her
    metin orada toplanıyor ve iki dilde tutuluyor.

    Mesaj TÜM dillerin kalıplarına karşı sınanır — dili değiştirmek kapıyı
    aşmanın yolu olmamalı (yasak konu kapısındaki duruşun aynısı).
    """
    if not message:
        return None
    hedef = _normalize(message)
    for dil, kalip in _CRISIS_RE.items():
        if kalip.search(hedef):
            return "crisis"
    return None


def forbidden_topic(message: str, lang: str = DEFAULT) -> tuple[str, str] | None:
    """Mesaj yasak bir alanda cevap talep ediyorsa (kategori, yanıt) döner.

    Engelleme için iki koşul birlikte gerekir: yasak konu + cevap talebi, ve
    ikisi aynı dilin kalıplarından gelmelidir. Mesaj desteklenen tüm dillere
    karşı sınanır; ``lang`` yalnızca dönen yanıtın dilini belirler.

    Eşleşme yoksa ``None`` — mesaj normal akışa devam eder.
    """
    if not message:
        return None

    hedef = _normalize(message)
    aksanli = _kucult(message)

    # Talep işareti taşıyan diller. Hiçbiri yoksa mesaj bir soru değil:
    # duygu paylaşımı, anlatı ya da genel sohbet.
    talep_dilleri = [dil for dil, kalip in _TALEP.items() if kalip.search(hedef)]
    if not talep_dilleri:
        return None

    yanit_dili = lang if lang in SUPPORTED else DEFAULT

    for rule in _RULES:
        for dil in talep_dilleri:
            kalip = rule.konu.get(dil)
            aksanli_kalip = rule.konu_aksanli.get(dil)
            if ((kalip is not None and kalip.search(hedef))
                    or (aksanli_kalip is not None
                        and aksanli_kalip.search(aksanli))):
                yanit = rule.yanit.get(yanit_dili) or rule.yanit[DEFAULT]
                return rule.kategori, yanit
    return None

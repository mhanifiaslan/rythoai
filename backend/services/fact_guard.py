"""LLM çıktısının prompt'taki olgulara sadık kalması — uydurma denetimi.

Derinleştirme planının yazılmış ama kodlanmamış regresyonu:

    Prompt'ta olmayan bir konum/açı/transit cevapta geçmemeli.

Hesap katmanı Swiss Ephemeris ile kilitli; cümle katmanı değildi. Bu modül
cevapta geçen **yapılandırılmış iddiaları** (gezegen+burç, gezegen+ev,
gezegen+açı+gezegen) tarar ve prompt'ta (harita fısıltısı, gökyüzü, RAG,
kullanıcı mesajı) karşılığı olmayanları ayırır.

Yalın gezegen adı ("Satürn yavaştır") iddia sayılmaz — doktrin konuşmasına
izin vardır. Yakalanan şey "Satürn senin 10. evinde" gibi **konum** iddiasıdır.

Çalışma zamanında: uydurma varsa bir kez yeniden üretim istenir; hâlâ
uydurmaysa metin döner ama önbelleğe yazılmaz (yanlış natal raporu 30 gün
kilitlemesin).
"""
from __future__ import annotations

import logging
import re
from typing import Any, Callable

from services import prompt_composer, prompts

logger = logging.getLogger(__name__)

#: (kind, ...) değişmezleri. kind: "sign" | "house" | "aspect"
Claim = tuple[str, ...]


def _alias_map() -> dict[str, str]:
    """Görünen ad (küçük harf, noktalı I düzeltilmiş) -> kanonik anahtar."""
    tablo: dict[str, str] = {}
    for lang in ("tr", "en"):
        p = prompts.get(lang)
        for anahtar, ad in p.PLANET_NAMES.items():
            tablo[prompt_composer.normalize(ad)] = anahtar
        for anahtar, ad in p.SIGN_NAMES.items():
            tablo[prompt_composer.normalize(ad)] = anahtar
        for anahtar, ad in p.ASPECT_NAMES.items():
            tablo[prompt_composer.normalize(ad)] = anahtar
    # ASCII / yaygın yazım sapmaları — normalize noktalı harfi düşürmez.
    tablo.update({
        "gunes": "Sun", "yukselen": "Ascendant", "merkur": "Mercury",
        "venus": "Venus", "jupiter": "Jupiter", "saturn": "Saturn",
        "uranus": "Uranus", "neptun": "Neptune", "pluton": "Pluto",
        "kiron": "Chiron", "mc": "Medium_Coeli", "midheaven": "Medium_Coeli",
        "rising": "Ascendant", "asc": "Ascendant",
        "kavusum": "conjunction", "karsit": "opposition", "ucgen": "trine",
        "altmis": "sextile", "altmislik": "sextile",
        "boga": "taurus", "yengec": "cancer", "basak": "virgo",
        "oglak": "capricorn", "balik": "pisces", "koc": "aries",
        "north node": "True_North_Lunar_Node",
        "south node": "True_South_Lunar_Node",
        "kuzey ay dugumu": "True_North_Lunar_Node",
        "guney ay dugumu": "True_South_Lunar_Node",
    })
    return tablo


_ALIAS = _alias_map()

#: Gezegen adları uzun olandan kısaya — "kuzey ay düğümü" "ay"dan önce.
_PLANET_KEYS = (
    "True_North_Lunar_Node", "True_South_Lunar_Node", "Medium_Coeli",
    "Mean_Lilith", "Ascendant", "Descendant", "Imum_Coeli",
    "Mercury", "Jupiter", "Neptune", "Uranus", "Saturn", "Pluto",
    "Chiron", "Venus", "Mars", "Moon", "Sun",
)
_SIGN_KEYS = (
    "sagittarius", "capricorn", "aquarius", "pisces", "gemini",
    "taurus", "cancer", "scorpio", "aries", "virgo", "libra", "leo",
)
_ASPECT_KEYS = (
    "conjunction", "opposition", "quincunx", "quintile",
    "sextile", "square", "trine",
)


def _names_for(keys: tuple[str, ...]) -> list[tuple[str, str]]:
    """(normalize edilmiş ad, kanonik anahtar) — uzun ad önce."""
    ciftler: list[tuple[str, str]] = []
    gorulen: set[str] = set()
    for anahtar in keys:
        for lang in ("tr", "en"):
            if anahtar in prompts.get(lang).PLANET_NAMES:
                ad = prompt_composer.normalize(
                    prompts.get(lang).PLANET_NAMES[anahtar])
            elif anahtar in prompts.get(lang).SIGN_NAMES:
                ad = prompt_composer.normalize(
                    prompts.get(lang).SIGN_NAMES[anahtar])
            elif anahtar in prompts.get(lang).ASPECT_NAMES:
                ad = prompt_composer.normalize(
                    prompts.get(lang).ASPECT_NAMES[anahtar])
            else:
                continue
            if ad and ad not in gorulen:
                gorulen.add(ad)
                ciftler.append((ad, anahtar))
        # ASCII kısa ad
        for k, v in _ALIAS.items():
            if v == anahtar and k not in gorulen and len(k) >= 3:
                gorulen.add(k)
                ciftler.append((k, anahtar))
    ciftler.sort(key=lambda c: -len(c[0]))
    return ciftler


_PLANET_NAMES = _names_for(_PLANET_KEYS)
_SIGN_NAMES = _names_for(_SIGN_KEYS)
_ASPECT_NAMES = _names_for(_ASPECT_KEYS)

#: "bu ay" / "this month" Ay gezegeni değildir.
_AY_DEGIL = re.compile(
    r"\b(?:bu|her|o|geçen|gecen|önümüzdeki|onumuzdeki|this|next|last)\s+ay\b"
)


def _find_spans(text: str, names: list[tuple[str, str]]) -> list[tuple[int, int, str]]:
    """Metindeki ad geçişleri: (baş, son, kanonik). Örtüşen kısa ad elenir."""
    bulunan: list[tuple[int, int, str]] = []
    for ad, anahtar in names:
        if ad == "ay":
            continue  # ayrı ele alınır
        desen = re.compile(rf"(?<![a-zçğıöşü]){re.escape(ad)}(?![a-zçğıöşü])")
        for m in desen.finditer(text):
            bulunan.append((m.start(), m.end(), anahtar))
    # Ay: yalnız başlı başına, "bu ay" değil.
    temiz = _AY_DEGIL.sub(" " * 5, text)
    for m in re.finditer(r"(?<![a-zçğıöşü])ay(?:['’]ın|ın|in)?(?![a-zçğıöşü])",
                         temiz):
        bulunan.append((m.start(), m.end(), "Moon"))
    bulunan.sort(key=lambda t: (t[0], -(t[1] - t[0])))
    # Örtüşen kısa eşleşmeyi at: "kuzey ay düğümü" içindeki "ay".
    süzülmüş: list[tuple[int, int, str]] = []
    for bas, son, anahtar in bulunan:
        if any(bas >= b and son <= s and (bas, son) != (b, s)
               for b, s, _ in süzülmüş):
            continue
        süzülmüş.append((bas, son, anahtar))
    return süzülmüş


_EV_TR = re.compile(r"(\d{1,2})\s*\.\s*ev")
_EV_EN = re.compile(r"(?:house\s+(\d{1,2})|(\d{1,2})(?:st|nd|rd|th)\s+house)")
#: RAG düzyazısı "onuncu ev" / "tenth house" yazar; rakamlı biçimle aynı iddia.
_EV_KELIME = (
    ("on birinci", 11), ("onbirinci", 11),
    ("on ikinci", 12), ("onikinci", 12),
    ("birinci", 1), ("ikinci", 2), ("üçüncü", 3), ("ucuncu", 3),
    ("dördüncü", 4), ("dorduncu", 4), ("beşinci", 5), ("besinci", 5),
    ("altıncı", 6), ("altinci", 6), ("yedinci", 7), ("sekizinci", 8),
    ("dokuzuncu", 9), ("onuncu", 10),
    ("eleventh", 11), ("twelfth", 12), ("tenth", 10),
    ("first", 1), ("second", 2), ("third", 3), ("fourth", 4),
    ("fifth", 5), ("sixth", 6), ("seventh", 7), ("eighth", 8),
    ("ninth", 9),
)

#: Gezegen ile burç/ev arasındaki en uzak karakter.
#:
#: 48'di ve fazla genişti: "Neptün'ün Oğlak'taki derinliği, Boğa'daki
#: Güneş'e…" cümlesinde Neptün ile Boğa 48 karakter içinde kalıp
#: ("sign", Neptune, taurus) diye SAHTE bir iddia üretiyordu. Ölçüldü —
#: gerçek bir natal raporunda bu sınıftan 5 yanlış pozitif çıkıyor ve
#: rapor haksız yere "uydurma" damgası alıyordu. Gerçek bir iddiada
#: burç/ev gezegenin hemen yanındadır ("Uranüs Oğlak'ta", "Mars 7. evde").
_PENCERE = 24


#: "-daki/-deki/-taki/-teki" eki, kendisinden SONRA geleni niteler:
#: "Boğa'daki Güneş" → Boğa, Güneş'in burcudur. Eksiz biçim ("Başak'ta",
#: "1. evde") ise kendisinden ÖNCE gelen gezegenin durumunu bildirir:
#: "Merkür'ün Başak'ta, 1. evde durması".
_NITELEYEN_EK = re.compile(r"\A['’]?(?:da|de|ta|te)ki\b")


def _en_yakin_gezegen(bas: int, son: int, metin: str,
                      gezegenler: list[tuple[int, int, str]]) -> str | None:
    """Bir burç/ev geçişini SAHİPLENEN gezegen.

    İlk sürüm pencereye giren HER gezegenle eşleştiriyordu ve bu düzyazıda
    sahte iddialar üretiyordu: "Neptün'ün etkisi, Boğa'daki Güneş'e
    dokunuyor" cümlesinde Boğa hem Neptün'e hem Güneş'e bağlanıyordu, oysa
    Güneş'in burcudur. Bir burç/ev cümlede TEK bir gezegene aittir.

    Sahibi bulurken yön önemli ve yönü Türkçe'nin kendi eki söylüyor
    (bkz. `_NITELEYEN_EK`): niteleyen ekliyse sonraki gezegen, değilse
    önceki. Yalnız mesafeye bakmak yetmiyordu — "Merkür: Başak (1. ev) ·
    Satürn: …" dizisinde "1. ev"e en yakın ad Satürn çıkıyor ama ev
    Merkür'ün.
    """
    niteleyen = bool(_NITELEYEN_EK.match(metin[son:son + 6]))
    oncekiler = [(bas - g_son, gez) for g_bas, g_son, gez in gezegenler
                 if g_son <= bas]
    sonrakiler = [(g_bas - son, gez) for g_bas, g_son, gez in gezegenler
                  if g_bas >= son]
    sirali = ([sonrakiler, oncekiler] if niteleyen
              else [oncekiler, sonrakiler])
    for aday in sirali:
        if not aday:
            continue
        mesafe, gez = min(aday, key=lambda t: t[0])
        if mesafe <= _PENCERE:
            return gez
    return None


def extract_claims(text: str) -> set[Claim]:
    """Serbest metindeki konum/açı iddialarını kanonik kümeye çevirir."""
    if not text:
        return set()
    dusuk = prompt_composer.normalize(text)
    gezegenler = _find_spans(dusuk, _PLANET_NAMES)
    burclar = _find_spans(dusuk, _SIGN_NAMES)
    acilar = _find_spans(dusuk, _ASPECT_NAMES)

    iddialar: set[Claim] = set()

    # Her burç geçişi TEK bir gezegene bağlanır: en yakın olana.
    for b_bas, b_son, burc in burclar:
        if burc not in _SIGN_KEYS:
            continue
        sahip = _en_yakin_gezegen(b_bas, b_son, dusuk, gezegenler)
        if sahip:
            iddialar.add(("sign", sahip, burc))

    # gezegen + ev
    evler: list[tuple[int, int, int]] = []
    for m in _EV_TR.finditer(dusuk):
        n = int(m.group(1))
        if 1 <= n <= 12:
            evler.append((m.start(), m.end(), n))
    for m in _EV_EN.finditer(dusuk):
        n = int(m.group(1) or m.group(2))
        if 1 <= n <= 12:
            evler.append((m.start(), m.end(), n))
    for kelime, n in _EV_KELIME:
        desen = re.compile(rf"{re.escape(kelime)}\s+(?:ev|house)")
        for m in desen.finditer(dusuk):
            evler.append((m.start(), m.end(), n))
    # Ev geçişleri de aynı kuralla: en yakın gezegen sahiplenir.
    for e_bas, e_son, ev in evler:
        sahip = _en_yakin_gezegen(e_bas, e_son, dusuk, gezegenler)
        if sahip:
            iddialar.add(("house", sahip, ev))

    # gezegen açı gezegen (açı iki gezegen arasında)
    for a_bas, a_son, aci in acilar:
        soldakiler = [(g_son, gez) for g_bas, g_son, gez in gezegenler
                      if 0 < a_bas - g_son <= _PENCERE]
        sagdakiler = [(g_bas, gez) for g_bas, g_son, gez in gezegenler
                      if 0 < g_bas - a_son <= _PENCERE]
        if not soldakiler or not sagdakiler:
            continue
        p1 = soldakiler[-1][1]
        p2 = sagdakiler[0][1]
        if p1 == p2:
            continue
        uclar = tuple(sorted((p1, p2)))
        iddialar.add(("aspect", uclar[0], aci, uclar[1]))

    return iddialar


#: Harita AÇILARI: ev numaraları tanım gereği sabittir (Yükselen 1. evin
#: başlangıcı, Alçalan 7'nin, MC 10'un, IC 4'ün). Model "Alçalan 7. evde"
#: dediğinde bu bir iddia değil, tanımın tekrarıdır.
_ACI_EVLERI = {
    "Ascendant": 1, "Descendant": 7, "Medium_Coeli": 10, "Imum_Coeli": 4,
}


def chart_facts(chart: dict[str, Any] | None) -> set[Claim]:
    """Hesaplanmış haritayı iddia kümesine çevirir — METİN DEĞİL, VERİ.

    ## Neden var

    İlk sürüm cevabın iddialarını **prompt metninden yeniden çıkarılan**
    iddialarla karşılaştırıyordu. Bu, iki tarafın yazım biçiminin birebir
    tutmasını gerektiriyor ve tutmuyordu: natal prompt evleri ``(Ev 9)``
    diye yazarken bekçinin Türkçe deseni yalnız ``9. ev`` biçimini
    tanıyordu. Sonuç ölçüldü — gerçek bir natal raporunda prompt'tan
    **sıfır** ev iddiası çıkıyor, cevaptan 27 iddia çıkıyor ve doğru
    yerleşimler (Jüpiter 10. ev, Mars 7. ev, Ay 4. ev…) "uydurma"
    sayılıyordu. Rapor önbelleğe yazılmıyor, kullanıcı her açılışta
    yeniden 5 jeton ödüyordu.

    Kaynak artık hesabın kendisi: biçim diye bir sorun kalmaz.
    """
    if not chart:
        return set()
    olgular: set[Claim] = set()

    def ekle(ad: Any, burc: Any, ev: Any) -> None:
        if not ad:
            return
        if burc:
            # Motor burç KODU tutuyor ("Cap"); iddia kümesi tam ad
            # kullanıyor ("capricorn").
            olgular.add(("sign", ad,
                         _SIGN_CODE_TO_KEY.get(burc, str(burc).lower())))
        if isinstance(ev, int) and 1 <= ev <= 12:
            olgular.add(("house", ad, ev))

    # İki şekil de kabul edilir ve HER İKİSİNİN DE TÜM alanları okunur:
    #
    #   * `astro_service` haritası: `points` (+ `house_no`), `asc`,
    #     `sr_ascendant`, `aspects`.
    #   * `chart_context.chart_facts` olguları: `placements` (+ `house`),
    #     `sun`, `moon`, `ascendant` (DÜZ DİZE), `aspects`, `transits`,
    #     `upcoming`.
    #
    # ⚠️ "İki şekil de kabul edilir" bir tur boyunca burada yazılıydı ama
    # ikinci şeklin ÜÇ alanı (`ascendant` dizesi, `transits`, `upcoming`)
    # sessizce atlanıyordu — yani iddia doğru, kapsam eksikti. Eksik
    # dayanak yanlış pozitif demek ve yanlış pozitifin bedeli BİR LLM TURU.
    for pt in chart.get("points") or []:
        ekle(pt.get("name"), pt.get("sign"), pt.get("house_no"))
    for pt in chart.get("placements") or []:
        ekle(pt.get("planet"), pt.get("sign"), pt.get("house"))
    for anahtar in ("sun", "moon"):
        pt = chart.get(anahtar)
        if isinstance(pt, dict):
            ekle(pt.get("planet"), pt.get("sign"), pt.get("house"))

    # Yükselen ayrı alanda gelir; yıl haritasında adı `sr_ascendant`.
    #
    # İKİ ŞEKİL: `astro_service` sözlük veriyor (`{"sign": "Vir"}`),
    # `chart_context.chart_facts` ise DÜZ DİZE (`"virgo"`). Dize şekli bir
    # tur boyunca sessizce atlanıyordu ve bunun ölçülmüş sonucu şu: sohbet
    # ucu dayanağı `facts=`ten kuruyor (`api/chat.py`), yani Yükselen burcu
    # dayanak kümesine HİÇ girmiyordu. Metin yolu onu kurtarıyordu (fısıltı
    # bloğunun ilk satırı "Yükselen: Başak" yazıyor ve `extract_claims` onu
    # görüyor), ama kurtarma TESADÜFİ: blok prompt bütçesinde kırpılırsa ya
    # da fısıltı sığ özete düşerse dayanak kaybolur ve DOĞRU bir Yükselen
    # cümlesi "uydurma" damgası yiyip bir LLM turu daha ısmarlar.
    # Ölçüldü (2026-10-03): dize şekliyle `("sign", "Ascendant", "virgo")`
    # dayanakta YOKTU; blok prompt'tan düşürülünce yanlış pozitif üretti.
    for anahtar in ("asc", "sr_ascendant", "ascendant"):
        asc = chart.get(anahtar)
        if isinstance(asc, dict) and asc.get("sign"):
            olgular.add(("sign", "Ascendant",
                         _SIGN_CODE_TO_KEY.get(asc["sign"],
                                               str(asc["sign"]).lower())))
        elif isinstance(asc, str) and asc.strip():
            olgular.add(("sign", "Ascendant",
                         _SIGN_CODE_TO_KEY.get(asc, asc.strip().lower())))

    for a in chart.get("aspects") or []:
        p1, p2, aci = a.get("p1"), a.get("p2"), a.get("aspect")
        if p1 and p2 and aci:
            uclar = tuple(sorted((p1, p2)))
            olgular.add(("aspect", uclar[0], aci, uclar[1]))

    # TRANSİT ve YAKLAŞAN açılar da dayanaktır — alan adları farklı
    # (`transit`/`natal`, `p1`/`p2` değil) ve bu yüzden yukarıdaki döngü
    # onları görmüyordu. İkisi de prompt'a MEŞRU olarak giriyor (fısıltı
    # bloğu ya da `gunun_gokyuzu`), yani burada eksik kalmaları yalnızca
    # dayanağı daraltır: gün satırlarını taşımayan bir çağıran
    # (`include_transits=False`) için doğru bir transit cümlesi dayanaksız
    # kalır. Dayanağı genişletmek yalnız YANLIŞ POZİTİFİ azaltır; gerçek
    # bir uydurma hâlâ kümenin dışındadır.
    for a in (chart.get("transits") or []) + (chart.get("upcoming") or []):
        gezen, natal, aci = a.get("transit"), a.get("natal"), a.get("aspect")
        if gezen and natal and aci:
            uclar = tuple(sorted((gezen, natal)))
            olgular.add(("aspect", uclar[0], aci, uclar[1]))

    return olgular


#: Motor burç kodu ("Cap") -> iddia anahtarı ("capricorn").
_SIGN_CODE_TO_KEY = {
    "Ari": "aries", "Tau": "taurus", "Gem": "gemini", "Can": "cancer",
    "Leo": "leo", "Vir": "virgo", "Lib": "libra", "Sco": "scorpio",
    "Sag": "sagittarius", "Cap": "capricorn", "Aqu": "aquarius",
    "Pis": "pisces",
}


def invented_claims(reply: str, prompt: str,
                    facts: dict[str, Any] | None = None) -> set[Claim]:
    """Cevapta olup DAYANAĞI OLMAYAN konum/açı iddiaları.

    Dayanak iki kaynaktan gelir: hesaplanmış harita (``facts``) ve prompt
    metni. Harita verilmişse asıl ölçüt odur; prompt metni yine eklenir
    çünkü haritada bulunmayan meşru bilgiler de prompta giriyor (bugünün
    transitleri, gökyüzü, RAG pasajları, kullanıcının kendi cümlesi).

    Harita açılarının ev numaraları (Yükselen 1, Alçalan 7, MC 10, IC 4)
    tanım gereği doğrudur; iddia sayılmaz.
    """
    dayanak = extract_claims(prompt) | chart_facts(facts)
    dayanak |= {("house", ad, ev) for ad, ev in _ACI_EVLERI.items()}
    return extract_claims(reply) - dayanak


def format_claims(claims: set[Claim], lang: str | None = None) -> str:
    """Log / yeniden üretim uyarısı için okunur liste."""
    if not claims:
        return ""
    satirlar = []
    for c in sorted(claims, key=str):
        if c[0] == "sign":
            satirlar.append(
                f"{prompts.planet_name(lang, c[1])} {prompts.sign_name(lang, c[2])}")
        elif c[0] == "house":
            satirlar.append(
                f"{prompts.planet_name(lang, c[1])} "
                f"{prompts.get(lang).HOUSE_FMT.format(house=c[2])}")
        else:
            satirlar.append(
                f"{prompts.planet_name(lang, c[1])} "
                f"{prompts.aspect_name(lang, c[2])} "
                f"{prompts.planet_name(lang, c[3])}")
    return "; ".join(satirlar)


def retry_instruction(claims: set[Claim], lang: str | None) -> str:
    """Uydurma iddiaları modele iade eden kısa düzeltme."""
    liste = format_claims(claims, lang) or str(claims)
    return prompts.get(lang).FACT_GUARD_RETRY.format(claims=liste)


def enforce(reply: str, prompt: str, lang: str | None = None,
            regenerate: Callable[[str], str | None] | None = None,
            facts: dict[str, Any] | None = None) -> tuple[str, bool]:
    """Uydurma varsa bir kez yeniden üretir.

    ``facts`` hesaplanmış haritadır ve VARSA asıl ölçüttür (bkz.
    `chart_facts`). Verilmezse eski davranış sürer: yalnız prompt metni.

    Dönen çift: (metin, grounded). ``grounded is False`` ise çağıran
    metni uzun ömürlü önbelleğe YAZMAMALI.
    """
    uydurma = invented_claims(reply, prompt, facts)
    if not uydurma:
        return reply, True
    logger.warning("Olgu bekçisi uydurma yakaladı: %s",
                   format_claims(uydurma, lang))
    if regenerate is None:
        return reply, False
    duzelti = prompt + "\n\n" + retry_instruction(uydurma, lang)
    tekrar = regenerate(duzelti)
    if not tekrar:
        return reply, False
    kalan = invented_claims(tekrar, prompt, facts)
    if not kalan:
        return tekrar, True
    logger.warning("Olgu bekçisi yeniden üretimde de uydurma: %s",
                   format_claims(kalan, lang))
    return tekrar, False

"""Dil çözümleme — istekten tek bir dil koduna.

Dil, her uca ayrı bir gövde alanı olarak eklenmek yerine ``Accept-Language``
başlığından okunur. Gerekçe: standart olan yol bu, istemci başlığı Dio
interceptor'ında bir kez ayarlar, ve mevcut istek şemalarının hiçbiri
değişmez.

Desteklenmeyen bir dil geldiğinde hata verilmez — varsayılana düşülür.
Kullanıcının uygulamayı kullanamaması, yorumu yabancı dilde görmesinden
kötüdür.
"""
from __future__ import annotations

import re

from fastapi import Header

#: Desteklenen diller. Yeni dil eklemek için: buraya kod, services/prompts
#: altına modül, knowledge/corpus altına dizin.
SUPPORTED: tuple[str, ...] = ("tr", "en")

#: Başlık yoksa veya tanınmıyorsa kullanılacak dil.
DEFAULT = "tr"


def resolve_language(accept_language: str | None) -> str:
    """``Accept-Language`` başlığını desteklenen bir dil koduna indirger.

    Ağırlıkları (``q=``) sırayla değerlendirir; ilk desteklenen dili döndürür.
    Bölgesel varyantlar ana dile katlanır: ``en-GB`` -> ``en``.
    """
    if not accept_language:
        return DEFAULT

    adaylar: list[tuple[float, str]] = []
    for parca in accept_language.split(","):
        parca = parca.strip()
        if not parca:
            continue
        kod, _, nitelik = parca.partition(";")
        kod = kod.strip().lower().split("-")[0]
        agirlik = 1.0
        if nitelik.strip().startswith("q="):
            try:
                agirlik = float(nitelik.strip()[2:])
            except ValueError:
                agirlik = 0.0
        adaylar.append((agirlik, kod))

    # Ağırlığı yüksek olan önce; eşitlikte başlıktaki sıra korunur.
    for _, kod in sorted(adaylar, key=lambda x: -x[0]):
        if kod in SUPPORTED:
            return kod
    return DEFAULT


#: Ad verilmeyen kullanıcıya hitap — dile göre. "Gezgin" bir tur boyunca
#: TR-only sabitti ve İngilizce arayüzdeki kullanıcı promptta "Gezgin" diye
#: anılıyordu (D6 ölçümü; istemci ad yoksa alanı artık göndermiyor).
_VARSAYILAN_AD: dict[str, str] = {"tr": "Gezgin", "en": "Traveler"}


def default_name(lang: str | None) -> str:
    """Dile göre varsayılan hitap; bilinmeyen dilde varsayılan dilinki."""
    return _VARSAYILAN_AD.get(lang or DEFAULT, _VARSAYILAN_AD[DEFAULT])


def get_language(accept_language: str | None = Header(default=None)) -> str:
    """FastAPI bağımlılığı: ``lang: str = Depends(get_language)``."""
    return resolve_language(accept_language)


# ---------------------------------------------------------------------------
# Dil tahmini — bildirim muhafızı (DM-turu)
#
# Cihaz bulgusu: "hem İngilizce hem Türkçe" bir push. Kompozisyon kodu tek
# dilli; gövde LLM'den gelir ve LLM'in dili SÖZ değildir. Buradaki sezgi
# DETERMİNİSTİKTİR ve LLM üretiminden SONRA çalışır — amaç dil tespiti
# değil, iki desteklenen dil arasındaki ÇELİŞKİYİ yakalamak. Kararsız
# kaldığında None döner; None hiçbir zaman çelişki sayılmaz.
# ---------------------------------------------------------------------------

#: Yalnızca Türkçede bulunan harfler. Ortak i/o/u yok; liste bilinçli dar
#: (tests/test_language_isolation.py'deki desenle aynı küme).
TURKCE_HARFLER = frozenset("çğıöşüÇĞİŞÖÜ")

#: İşlev sözcükleri — kasıtlı küçük. İki dilde de geçen sözcük listeye
#: girmez; tek sözcük karar vermez, en az iki isabet gerekir.
_TR_SOZCUKLER = frozenset((
    "ve", "bir", "bu", "için", "ile", "bugün", "sen", "senin", "seni",
    "ama", "daha", "gibi", "mi", "mı", "mu", "mü", "değil", "var", "yok"))
_EN_SOZCUKLER = frozenset((
    "the", "and", "you", "your", "today", "is", "are", "to", "of", "with",
    "this", "that", "it"))

#: Sözcük = harf dizisi (Unicode). Alt dizi eşleşmesi YOK: "bu",
#: "bugün"ün içinde sayılmaz; noktalama ve kesme işareti ayırıcıdır.
_SOZCUK = re.compile(r"[^\W\d_]+")


#: Karışık metin eşiği: Türkçe işaret VARKEN bu kadar İngilizce işlev
#: sözcüğü de varsa cümle iki dillidir ("hem İngilizce hem Türkçe" —
#: cihazda görülen şikâyet). "it" sayılmaz: Türkçe'de de sözcük (köpek).
_EN_KARISIK_ESIK = 3
_EN_TURKCE_ORTAK = frozenset(("it",))


def guess_language(text: str) -> str | None:
    """Metnin dili: ``"tr"``, ``"en"``, ``"mixed"`` ya da ``None`` (kararsız).

    - Türkçe harf varsa YA DA Türkçe işlev sözcüğünden en az iki isabet
      varsa ``"tr"`` (aksansız yazılmış Türkçe de yakalanır)…
    - …AMA aynı metinde İngilizce işlev sözcüğünden en az
      [_EN_KARISIK_ESIK] isabet de varsa ``"mixed"``: iki dilli cümle hiçbir
      profille uyuşmaz (`language_conflicts` her dilde True döner).
    - Hiç Türkçe işaret yoksa VE İngilizce işlev sözcüğünden en az iki
      isabet varsa ``"en"``.
    - Aksi halde ``None`` — kısa/nötr metin ("42", "OK", çoğu başlık)
      çelişki üretmez.

    Noktalı ``İ`` (Python ``lower()`` onu iki karaktere böler) harf
    kontrolüne takılır; sözcük sayımı `lower()` sonrası yapılır ama Türkçe
    kararı harf kontrolünden geldiği için bundan etkilenmez.
    """
    if not text:
        return None
    turkce_harf = any(harf in TURKCE_HARFLER for harf in text)
    sozcukler = _SOZCUK.findall(text.lower())
    tr_isabet = sum(s in _TR_SOZCUKLER for s in sozcukler)
    en_isabet = sum(s in _EN_SOZCUKLER and s not in _EN_TURKCE_ORTAK
                    for s in sozcukler)
    turkce = turkce_harf or tr_isabet >= 2
    if turkce and en_isabet >= _EN_KARISIK_ESIK:
        return "mixed"
    if turkce:
        return "tr"
    if en_isabet >= 2:
        return "en"
    return None


def language_conflicts(text: str, lang: str) -> bool:
    """Metin ``lang`` DIŞINDA bir dilde mi görünüyor?

    Tahmin ``None`` ise ya da ``lang`` desteklenmiyorsa asla çelişki yok:
    muhafız yalnız emin olduğunda konuşur. ``"mixed"`` her dille çelişir.
    """
    tahmin = guess_language(text)
    return tahmin is not None and lang in SUPPORTED and tahmin != lang


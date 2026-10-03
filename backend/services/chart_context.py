"""Harita derinliği — sohbetin kullanıcının GERÇEK haritasını görmesi.

Sorun neydi: sohbet ucu kullanıcı hakkında yalnızca üç şey biliyordu —
Güneş, Ay ve Yükselen burcu (`profile_service.chart_summary`). Bu, bir
astroloğun "Aslan burcusun" demesinden fazlası değil ve cevapların jenerik
kalmasının birinci sebebiydi. Bir astroloğu spesifik yapan şey "Satürn
yedinci evinden geçiyor" diyebilmesidir; Swiss Ephemeris bunu zaten
hesaplıyordu, sohbet katmanına hiç taşınmıyordu.

Bu modül aradaki köprüyü kurar ve üç kuralı korur:

**1. Uydurma yok.** Doğum tarihi veya şehri eksikse harita HESAPLANMAZ;
   `birth_kwargs` varsayılanı (2000-01-01, Istanbul) gerçek bir haritaymış
   gibi sunulursa ürün ilkesi ("gök verisi uydurulmaz") çiğnenir. O durumda
   bugüne kadarki sığ özete düşülür.

**2. Ham doğum verisi prompt'a girmez.** Modele yalnızca türetilmiş konumlar
   verilir; doğum tarihi/saati/şehri asla. `profile_service`'in gizlilik
   kuralı burada da geçerli.

**3. Dilden bağımsız hesap.** Sayımlar burç ADINDAN değil anahtarından
   yapılır; adlandırma yalnızca son adımda, isteğin dilinde olur.

Maliyet: LLM çağrısı YOK, yalnızca efemeris hesabı. Yine de her sohbet
turunda yeniden hesaplamak gereksiz gecikme demek olurdu:

* **Natal olgular** doğum verisine bağlıdır, değişmez → uzun ömürlü önbellek.
  Anahtar doğum verisinin özetini taşır, böylece kullanıcı doğum bilgisini
  düzeltince önbellek kendiliğinden geçersizleşir.
* **Transitler** güne bağlıdır → günlük önbellek. Bu yüzden GEZEN AY listeye
  alınmaz: Ay günde ~13° yol alır, sabahleyin hesaplanan bir Ay açısı akşama
  yanlış olur. Ay'ın bugünkü hali zaten "gökyüzü" fısıltısında evresiyle
  geçiyor.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import logging
from typing import Any

from core import cache
from core import entitlements
from services import astro_service, profile_service, prompts

logger = logging.getLogger(__name__)

#: Sohbete taşınan gezegenler. Geleneksel yedili bilinçli bir seçim: klasik
#: kaynaklar bu yedisiyle konuşur. Dış gezegenler (Uranüs/Neptün/Plüton)
#: yerleşim satırına da girer — dönem işaretçisi olmaları yalnız transitte
#: kalırsa sohbet "haritanı biliyor" iddiasını sığ bırakıyordu (denetim R).
TRADITIONAL = ("Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn")
OUTER = ("Uranus", "Neptune", "Pluto")

#: Büyük üçlü ayrı satırda verildiği için yerleşim satırında tekrarlanmaz.
_PLACEMENT_POINTS = ("Mercury", "Venus", "Mars", "Jupiter", "Saturn") + OUTER

#: Açı sayımına giren noktalar. Yükselen ve MC eklendi: bir açının açıya
#: değdiği yer kadar, hayatın hangi alanına düştüğü de anlam taşır.
_ASPECT_POINTS = frozenset(TRADITIONAL + ("Ascendant", "Medium_Coeli"))

#: Harita açıları (Yükselen, MC). Bir gezegenle açı yapmaları anlamlı ama
#: BİRBİRLERİYLE yaptıkları açı değil: Yükselen-MC arasındaki mesafe doğum
#: enleminin geometrik sonucudur, kişiye dair bir şey söylemez. Listeye
#: girdiğinde de dar orb'u sayesinde gerçek bir açının yerini alıyordu.
_ANGLES = frozenset(("Ascendant", "Medium_Coeli"))

#: Yalnızca majör açılar. Beşlik/yüzelli gibi küçük açıları da eklemek
#: listeyi gürültüye boğar ve gerçekten belirgin olanı gölgeler.
_MAJOR_ASPECTS = frozenset(
    ("conjunction", "opposition", "square", "trine", "sextile"))

#: Transitte gezen taraf olarak kabul edilenler. **Ay bilerek yok** (bkz.
#: modül açıklaması). Merkür/Venüs/Mars/Güneş günde ~1° veya daha az yol
#: alır; günlük önbellekle uyumludurlar.
_TRANSIT_MOVERS = frozenset((
    "Sun", "Mercury", "Venus", "Mars", "Jupiter", "Saturn",
    "Uranus", "Neptune", "Pluto", "Chiron",
))

#: Transit açısının "şimdi geçerli" sayılması için en geniş orb (derece).
#: Kerykeion daha geniş orb'larla da açı üretir; 3° eşiği listeyi bugün
#: gerçekten hissedilen açılarla sınırlar.
_TRANSIT_MAX_ORB = 3.0

#: Yavaş gezenler. Sıralamayı yalnızca orb'a bırakmak listeyi Merkür'e
#: boğuyordu: Merkür günde ~1° yol aldığı için her gün birilerine 0.1°'lik
#: bir açı yapar ve daima en "sıkı" açı olur. Oysa dönemi işaretleyen şey
#: aylarca aynı noktada duran Satürn/Plüton'dur. Bu yüzden önce yavaşlar
#: sıralanır, hızlılar kalan yeri doldurur.
_SLOW_MOVERS = frozenset(
    ("Jupiter", "Saturn", "Uranus", "Neptune", "Pluto", "Chiron"))

#: kerykeion ev adı -> ev numarası. `_point_dict` bu alanı ham bırakıyor ve
#: değer ``"Twelfth_House"`` biçiminde bir metin; sayıya çevrilmezse hem ev
#: satırı hem yığılma sayımı sessizce boş kalır.
_HOUSE_NUMBER = {
    ad: i + 1 for i, ad in enumerate((
        "First_House", "Second_House", "Third_House", "Fourth_House",
        "Fifth_House", "Sixth_House", "Seventh_House", "Eighth_House",
        "Ninth_House", "Tenth_House", "Eleventh_House", "Twelfth_House",
    ))
}


def _house_number(deger: Any) -> int | None:
    """kerykeion'un ev alanını (metin ya da sayı) ev numarasına çevirir."""
    if isinstance(deger, int):
        return deger if 1 <= deger <= 12 else None
    return _HOUSE_NUMBER.get(deger)

#: Prompt'a giren en fazla açı/transit satırı.
#: Denetim: 4/3 sığ kalıyordu; 6/4 hâlâ kompakt, sohbet turuna sığar.
_MAX_NATAL_ASPECTS = 6
_MAX_TRANSITS = 4

#: Kaç gezegen bir arada olunca "yığılma" denir.
_STELLIUM_MIN = 3

_ELEMENTS = {
    "fire": ("aries", "leo", "sagittarius"),
    "earth": ("taurus", "virgo", "capricorn"),
    "air": ("gemini", "libra", "aquarius"),
    "water": ("cancer", "scorpio", "pisces"),
}
_MODALITIES = {
    "cardinal": ("aries", "cancer", "libra", "capricorn"),
    "fixed": ("taurus", "leo", "scorpio", "aquarius"),
    "mutable": ("gemini", "virgo", "sagittarius", "pisces"),
}
_SIGN_TO_ELEMENT = {s: e for e, signs in _ELEMENTS.items() for s in signs}
_SIGN_TO_MODALITY = {s: m for m, signs in _MODALITIES.items() for s in signs}

#: Natal olgular doğum verisi değişmedikçe geçerli. Anahtara doğum özeti
#: gömüldüğü için "değişti mi" sorusunu ayrıca sormaya gerek yok.
NATAL_TTL_SECONDS = 180 * 24 * 3600
#: Transitler güne bağlı; gün dönümünde kendiliğinden yenilenir. TTL bir
#: günden biraz uzun tutuldu ki saat dilimi farkları boşluk yaratmasın.
TRANSIT_TTL_SECONDS = 36 * 3600


# --------------------------------------------------------------------------
# Doğum verisi
# --------------------------------------------------------------------------

def has_birth_data(profile: dict[str, Any] | None) -> bool:
    """Gerçek bir harita hesaplanabilir mi?

    `profile_service.birth_kwargs` eksik alanları sessizce varsayılana
    çeviriyor (2000-01-01, 12:00, Istanbul). Bu, rapor uçları için makul bir
    davranış; ama o varsayılanla hesaplanan haritayı "senin haritan" diye
    sunmak veri uydurmaktır. Bu yüzden derinlik yalnızca tarih VE şehir
    gerçekten girilmişse üretilir.
    """
    if not profile:
        return False
    return bool(str(profile.get("birthDate") or "").strip()
                and str(profile.get("birthCity") or "").strip())


def _birth_digest(birth: dict[str, Any]) -> str:
    """Doğum verisinin önbellek anahtarına girecek özeti.

    İsim dışarıda: haritayı etkilemez, değişmesi önbelleği boşa düşürmemeli.
    Özet kullanılıyor çünkü anahtarın kendisi ham doğum verisi taşımamalı.
    """
    ham = "|".join(str(birth.get(k)) for k in (
        "year", "month", "day", "hour", "minute", "city", "nation",
        "hour_known"))
    return hashlib.sha256(ham.encode("utf-8")).hexdigest()[:16]


# --------------------------------------------------------------------------
# Olgu çıkarımı (dilden bağımsız)
# --------------------------------------------------------------------------

def natal_facts(birth: dict[str, Any]) -> dict[str, Any]:
    """Natal haritadan dilden bağımsız olgular çıkarır.

    Dönen sözlükteki her değer ya sayı ya da anahtar (``"leo"``,
    ``"square"``); hiçbir görüntülenecek ad içermez. Adlandırma
    `render` aşamasında, isteğin dilinde yapılır.
    """
    chart = astro_service.get_natal_chart(
        **astro_service.subject_kwargs(birth),
        hour_known=astro_service.hour_is_known(birth),
    )
    points = {p.get("name"): p for p in chart.get("points", [])}

    def yerlesim(ad: str) -> dict[str, Any] | None:
        p = points.get(ad)
        if not p:
            return None
        burc = prompts.sign_key_from_code(p.get("sign"))
        if not burc:
            return None
        pos = p.get("position")
        return {
            "planet": ad,
            "sign": burc,
            "house": _house_number(p.get("house")),
            "retrograde": bool(p.get("retrograde")),
            "position": round(float(pos), 1) if pos is not None else None,
        }

    yerlesimler = [y for y in (
        yerlesim(ad) for ad in TRADITIONAL + OUTER) if y]

    yukselen = prompts.sign_key_from_code(
        (chart.get("asc") or {}).get("sign"))

    # Element/nitelik dengesi geleneksel yedili + Yükselen üzerinden sayılır;
    # Yükselen'i katmak yaygın pratiktir ve eksik elementi daha doğru gösterir.
    # Dış gezegenler sayıma girmez (R5-1 kanonu).
    burclar = [y["sign"] for y in yerlesimler if y["planet"] in TRADITIONAL]
    if yukselen:
        burclar.append(yukselen)

    elementler = {e: 0 for e in _ELEMENTS}
    nitelikler = {m: 0 for m in _MODALITIES}
    for burc in burclar:
        elementler[_SIGN_TO_ELEMENT[burc]] += 1
        nitelikler[_SIGN_TO_MODALITY[burc]] += 1

    ev_sayimi: dict[int, int] = {}
    for y in yerlesimler:
        ev = y.get("house")
        if isinstance(ev, int):
            ev_sayimi[ev] = ev_sayimi.get(ev, 0) + 1
    yigilmalar = sorted(
        ({"house": ev, "count": adet} for ev, adet in ev_sayimi.items()
         if adet >= _STELLIUM_MIN),
        key=lambda y: (-y["count"], y["house"]),
    )

    acilar = []
    for a in chart.get("aspects", []):
        if a.get("aspect") not in _MAJOR_ASPECTS:
            continue
        if a.get("p1") not in _ASPECT_POINTS or a.get("p2") not in _ASPECT_POINTS:
            continue
        if a.get("p1") in _ANGLES and a.get("p2") in _ANGLES:
            continue
        acilar.append({
            "p1": a["p1"], "p2": a["p2"], "aspect": a["aspect"],
            "orb": abs(float(a.get("orbit") or 0.0)),
        })
    # En sıkı açı en güçlüsüdür; sıralama orb'a göre.
    acilar.sort(key=lambda a: a["orb"])

    return {
        "sun": next((y for y in yerlesimler if y["planet"] == "Sun"), None),
        "moon": next((y for y in yerlesimler if y["planet"] == "Moon"), None),
        "ascendant": yukselen,
        "hour_known": astro_service.hour_is_known(birth),
        "placements": [y for y in yerlesimler
                       if y["planet"] in _PLACEMENT_POINTS],
        "elements": elementler,
        "modalities": nitelikler,
        "stelliums": yigilmalar,
        "aspects": acilar[:_MAX_NATAL_ASPECTS],
    }


def filter_transit_hits(raw_aspects: list[dict[str, Any]],
                        natal_points: frozenset | set = _ASPECT_POINTS,
                        cap: int = _MAX_TRANSITS) -> list[dict[str, Any]]:
    """Transit süzgeç doktrini TEK yerde (GT1): majör açı, Ay'sız gezenler,
    orb ≤ 3.0, yavaş-önce sıralama, üst sınır.

    `transit_facts` ve `synastry_service.pair_transits` aynı doktrini
    kullanır — iki kopya iki ayrı doktrine ayrışırdı. `movement` alanı da
    taşınır (kaynakta zaten var; çift katmanı "güçleniyor/sönüyor" der).
    """
    vurus = []
    for a in raw_aspects or []:
        if a.get("aspect") not in _MAJOR_ASPECTS:
            continue
        gezen, natal = a.get("p1"), a.get("p2")
        if gezen not in _TRANSIT_MOVERS or natal not in natal_points:
            continue
        orb = abs(float(a.get("orbit") or 0.0))
        if orb > _TRANSIT_MAX_ORB:
            continue
        vurus.append({"transit": gezen, "natal": natal,
                      "aspect": a["aspect"], "orb": orb,
                      "movement": a.get("movement")})
    # Önce yavaş gezenler, sonra orb. Salt orb sıralaması listeyi her gün
    # Merkür'le doldurup dönemin asıl temasını dışarıda bırakıyordu.
    vurus.sort(key=lambda v: (0 if v["transit"] in _SLOW_MOVERS else 1,
                              v["orb"]))
    return vurus[:cap]


def is_slow_mover(planet: str) -> bool:
    """Gezenin yavaşlardan olup olmadığı — çift katmanının birleşim
    sıralaması da aynı doktrini kullansın diye dışa açık."""
    return planet in _SLOW_MOVERS


def transit_facts(birth: dict[str, Any]) -> dict[str, Any]:
    """Bugünkü gökyüzünün natal haritaya değdiği noktalar.

    Gezen Ay listeye alınmaz (bkz. modül açıklaması) ve orb eşiği dardır:
    amaç haritanın tam kopyasını vermek değil, bugün gerçekten baskın olan
    bir-iki teması modele göstermektir.
    """
    ham = astro_service.get_transits(
        **astro_service.subject_kwargs(birth),
        hour_known=astro_service.hour_is_known(birth),
    )
    vurus = filter_transit_hits(ham.get("aspects_to_natal", []))

    # YAKLAŞANLAR (T3): önümüzdeki 7 günün ilk 2 kesinleşmesi. Takvim
    # üretilemezse günlük okuma yaklaşansız devam eder — vuruşlarla aynı
    # hoşgörü.
    yaklasan: list[dict[str, Any]] = []
    try:
        from services import predict_service
        cal = predict_service.transit_calendar(
            **astro_service.subject_kwargs(birth),
            hour_known=astro_service.hour_is_known(birth), days=7)
        yaklasan = [{"date": o["date"], "transit": o["transit"],
                     "natal": o["natal"], "aspect": o["aspect"]}
                    for o in cal["events"]
                    if o["type"] == "aspect_exact"][:2]
    except Exception as exc:
        logger.warning("Yaklaşan transitler üretilemedi: %s", exc)

    return {"hits": vurus, "upcoming": yaklasan}


# --------------------------------------------------------------------------
# Önbellekli erişim
# --------------------------------------------------------------------------

def _cached(key: str, uid: str, ttl: int, uret) -> dict[str, Any] | None:
    """Önbellekten oku, yoksa üret ve yaz.

    ``owner_uid`` yazılıyor: bu içerik kullanıcıya ÖZELDİR ve hesap silme
    akışının onu bulup temizleyebilmesi gerekir (önbellek doküman kimlikleri
    anahtarın özeti olduğu için başka türlü sorgulanamaz).
    """
    mevcut = cache.get(key)
    if mevcut is not None:
        return mevcut
    try:
        deger = uret()
    except Exception as exc:
        # Efemeris hesabı düşerse sohbet düşmemeli; sığ özete geri dönülür.
        logger.warning("Harita olguları üretilemedi (%s): %s", key, exc)
        return None
    cache.set(key, deger, ttl_seconds=ttl, owner_uid=uid)
    return deger


def chart_facts(uid: str, profile: dict[str, Any],
                today: dt.date | None = None) -> dict[str, Any] | None:
    """Kullanıcının natal + transit olgularını (önbellekli) döndürür."""
    if not has_birth_data(profile):
        return None
    birth = profile_service.birth_kwargs(profile)
    ozet = _birth_digest(birth)
    gun = (today or dt.date.today()).isoformat()

    # v2 (T0): motora declination/speed/movement/disclosures alanları girdi;
    # anahtar sürümlenmezse 180 günlük TTL boyunca eski şekilli kayıtlar
    # servis edilirdi (sky-now-v3 dersi).
    natal = _cached(f"natal-facts-v3-{uid}-{ozet}", uid,
                    NATAL_TTL_SECONDS, lambda: natal_facts(birth))
    if natal is None:
        return None

    # Transit üretilemezse natal kısmı yine değerli; sohbet transitsiz devam eder.
    # v2 (T3): "upcoming" alanı eklendi — sürümsüz anahtar 36 saatlik TTL
    # boyunca alansız kayıt servis ederdi.
    transit = _cached(f"transit-facts-v2-{uid}-{ozet}-{gun}", uid,
                      TRANSIT_TTL_SECONDS, lambda: transit_facts(birth))
    # `upcoming` da taşınır (KA8): 7 günlük kesinleşmeler zaten transit
    # önbelleğinde hesaplıydı ama burada ATILIYORDU — sohbet "bu hafta
    # beni ne bekliyor?" sorusuna dayanaksız kalıyordu; günlük okuma
    # görüyordu, sohbet görmüyordu.
    return {**natal, "transits": (transit or {}).get("hits", []),
            "upcoming": (transit or {}).get("upcoming", [])}


def bazi_facts(uid: str, profile: dict[str, Any]) -> dict[str, Any] | None:
    """Sohbet fısıltısı için KOMPAKT BaZi olguları (Revize B8).

    Motorun tam çıktısı değil, sohbete her turda girecek kadar küçük bir
    özet: Day Master, güç hükmü, yararlı elementler, aktif Da Yun, yıl
    sütunu ve en fazla iki yıldız. "BaZi'm ne?" sorusunun cevabı artık
    modelin hafızasından değil deterministik hesaptan gelir.

    Anahtar ay damgası taşır: Liu Nian Li Chun'da değişir; yıl+ay
    granülariteli anahtar en fazla ~1 aylık sınır bulanıklığıyla bunu
    izler — günlük yeniden hesap israf olurdu.
    """
    if not has_birth_data(profile):
        return None
    birth = profile_service.birth_kwargs(profile)
    ozet = _birth_digest(birth)
    bugun = dt.date.today()

    def uret() -> dict[str, Any]:
        from services import bazi_service
        chart = bazi_service.get_bazi_chart(
            name=birth["name"], year=birth["year"], month=birth["month"],
            day=birth["day"],
            # Profilde saat yoksa BaZi saat sütunu kurmaz (B1) — fısıltı
            # da kurmamalı; birth_kwargs'ın 12:00 dolgusu natal içindir.
            hour=birth["hour"] if profile.get("birthTime") else None,
            minute=birth["minute"], city=birth["city"],
            nation=birth.get("nation"),
            gender=profile.get("gender") or "",
        )
        s = chart.get("strength") or {}
        idx = chart.get("current_luck_index")
        aktif = (chart["luck_pillars"][idx]
                 if idx is not None else None)
        return {
            "day_master": {k: chart["day_master"][k]
                           for k in ("pinyin", "element", "polarity")},
            "verdict": s.get("verdict"),
            "season_state": s.get("season_state"),
            "favorable_elements": s.get("favorable_elements") or [],
            "current_luck": ({"label": aktif["label"],
                              "from_year": aktif["from_year"],
                              "to_year": aktif["to_year"],
                              "ten_god": aktif["ten_god"]["name"]}
                             if aktif else None),
            "current_year": {
                "label": chart["current_year_pillar"]["label"],
                "ten_god": chart["current_year_pillar"]["ten_god"]["name"],
            },
            "stars": [{"key": y["key"], "pillar": y["pillar"]}
                      for y in (chart.get("shen_sha") or [])[:2]],
            "hour_known": chart.get("hour_known", True),
        }

    return _cached(
        f"bazi-facts-v1-{uid}-{ozet}-{bugun.year}-{bugun.month:02d}",
        uid, NATAL_TTL_SECONDS, uret)


# --------------------------------------------------------------------------
# Adlandırma (dile bağlı tek aşama)
# --------------------------------------------------------------------------

def _ev(lang: str | None, house: Any) -> str:
    if not isinstance(house, int):
        return ""
    return prompts.get(lang).HOUSE_FMT.format(house=house)


def _yerlesim_metni(lang: str | None, y: dict[str, Any]) -> str:
    p = prompts.get(lang)
    ad = prompts.planet_name(lang, y["planet"])
    burc = prompts.sign_name(lang, y["sign"])
    derece = y.get("position")
    if isinstance(derece, (int, float)):
        burc = f"{burc} {derece:.1f}°"
    ekler = [e for e in (_ev(lang, y.get("house")),
                         p.RETROGRADE_LABEL if y.get("retrograde") else "") if e]
    parantez = f" ({', '.join(ekler)})" if ekler else ""
    return f"{ad}: {burc}{parantez}"


def render(facts: dict[str, Any], lang: str | None = None,
           include_transits: bool = True) -> str:
    """Olguları isteğin dilinde kompakt bir fısıltı bloğuna çevirir.

    Blok her sohbet turunda prompt'a giriyor; bu yüzden satırlar kısa ve
    ayrıştırılabilir tutuldu. Modelden bunu okumasını değil, üzerine
    konuşmasını istiyoruz.

    ``include_transits=False`` GÜNE BAĞLI iki satırı (bugünün transitleri +
    önümüzdeki 7 günün kesinleşmeleri) dışarıda bırakır. Bayrak bir
    "ayıklama" aracı DEĞİL, bir BÖLME aracı: günü prompt'tan çıkarmak için
    değil, kalıcı olanla bugüne ait olanı AYRI BAŞLIKLAR altında vermek için
    var. Karşılığı `gunun_gokyuzu`; ikisi birlikte aynı olguların tamamını
    verir, yalnız modele hangisinin kalıcı hangisinin bugüne ait olduğunu
    söyleyerek.

    Tek `False` geçen çağıran ölçüldü: firaset yolu (`api/face_reading`).
    Sohbet `True` geçiyor çünkü orada blok tek bir turda tüketiliyor ve
    "bugün" ile "her zaman" ayrımını modele cümlenin kendisi taşıyor.
    Savunma ESKİDEN tüketicide, `report_service`te etiket literaline göre
    satır ayıklayan bir süzgeçteydi; o süzgeç kaldırıldı çünkü aynı işi
    kaynakta bir bayrak yapıyor ve yeni bir tüketici ayıklamayı hatırlamak
    zorunda kalmıyor.
    """
    p = prompts.get(lang)
    satirlar: list[str] = []

    ucler = []
    for anahtar in ("sun", "moon"):
        y = facts.get(anahtar)
        if y:
            ucler.append(_yerlesim_metni(lang, y))
    if facts.get("ascendant"):
        ucler.append(f"{prompts.planet_name(lang, 'Ascendant')}: "
                     f"{prompts.sign_name(lang, facts['ascendant'])}")
    if ucler:
        satirlar.append("- " + " · ".join(ucler))

    yerlesimler = [_yerlesim_metni(lang, y) for y in facts.get("placements", [])]
    if yerlesimler:
        satirlar.append("- " + " · ".join(yerlesimler))

    # Sıfır sayımlar da yazılır: EKSİK element astrolojik olarak anlamlı bir
    # ifadedir ("haritanda hiç su yok"), listeden düşürülürse kaybolur.
    elementler = facts.get("elements") or {}
    if elementler:
        satirlar.append("- {}: {}".format(
            p.CHART_ELEMENT_LABEL,
            ", ".join(f"{p.ELEMENT_NAMES[e]} {elementler.get(e, 0)}"
                      for e in _ELEMENTS)))
    nitelikler = facts.get("modalities") or {}
    if nitelikler:
        satirlar.append("- {}: {}".format(
            p.CHART_MODALITY_LABEL,
            ", ".join(f"{p.MODALITY_NAMES[m]} {nitelikler.get(m, 0)}"
                      for m in _MODALITIES)))

    yigilmalar = facts.get("stelliums") or []
    if yigilmalar:
        satirlar.append("- {}: {}".format(
            p.CHART_STELLIUM_LABEL,
            " · ".join(p.CHART_STELLIUM_FMT.format(
                house=_ev(lang, y["house"]), count=y["count"])
                for y in yigilmalar)))

    acilar = facts.get("aspects") or []
    if acilar:
        satirlar.append("- {}: {}".format(
            p.CHART_NATAL_ASPECTS_LABEL,
            " · ".join(p.CHART_ASPECT_FMT.format(
                p1=prompts.planet_name(lang, a["p1"]),
                p2=prompts.planet_name(lang, a["p2"]),
                aspect=prompts.aspect_name(lang, a["aspect"]),
                orb=f"{a['orb']:.1f}") for a in acilar)))

    transitler = facts.get("transits") or []
    if include_transits and transitler:
        satirlar.append("- {}: {}".format(
            p.CHART_TRANSITS_LABEL,
            " · ".join(p.CHART_TRANSIT_FMT.format(
                transit=prompts.planet_name(lang, t["transit"]),
                natal=prompts.planet_name(lang, t["natal"]),
                aspect=prompts.aspect_name(lang, t["aspect"]),
                orb=f"{t['orb']:.1f}") for t in transitler)))

    # Yaklaşan 7 günün kesinleşmeleri (KA8): hesap zaten vardı, sohbete
    # hiç girmiyordu — "bu hafta beni ne bekliyor?" dayanaksız kalıyordu.
    #
    # Bu satır transit bayrağına BAĞLI ve bilerek: taşıdığı şey TAKVİM
    # TARİHİ ("2026-10-07: Satürn → Venüs"). Kalıcı sayılan bir bloğa giren
    # bir tarih, o bloğu tüketen metnin ömrü boyunca dondurulur; transit
    # satırıyla aynı sınıfta.
    yaklasan = facts.get("upcoming") or []
    if include_transits and yaklasan:
        satirlar.append("- {}: {}".format(
            p.CHART_UPCOMING_LABEL, upcoming_lines(yaklasan, lang)))

    # Not: profildeki `wuXingElement` / `mizac` alanları bilerek YAZILMIYOR.
    # Yüz okuma cihaz üstünde; bu anahtarlar sunucu fısıltısına girmez.
    # Değerleri serbest Türkçe metindi ("Demevi (sıcak-nemli)") — İngilizce
    # prompt'a sızdırırlardı. Geri gelirlerse anahtar olarak üretilmeli.
    return "\n".join(satirlar)


def transit_lines(hits: list[dict[str, Any]],
                  lang: str | None = None) -> str:
    """Transit vuruşlarını isteğin dilinde tek satıra çevirir.

    `render` içindeki transit biçiminin dışarıya açılmış hâli: günlük okuma
    (Revize R8) aynı satırı prompt'una koyuyor. Biçim tek yerde kalsın diye
    format sabitleri paylaşılıyor; iki ayrı yazım, iki ayrı dilde ayrışırdı.
    """
    p = prompts.get(lang)
    return " · ".join(p.CHART_TRANSIT_FMT.format(
        transit=prompts.planet_name(lang, t["transit"]),
        natal=prompts.planet_name(lang, t["natal"]),
        aspect=prompts.aspect_name(lang, t["aspect"]),
        orb=f"{t['orb']:.1f}") for t in hits)


def upcoming_lines(events: list[dict[str, Any]],
                   lang: str | None = None) -> str:
    """Yaklaşan kesinleşmeleri isteğin dilinde tek satıra çevirir (T3).

    `transit_lines`'ın kardeşi: günlük okuma prompt'unun YAKLAŞANLAR alanı
    bu satırı kullanır. Tarih ISO kalır — model tarihten kehanet kurmasın
    diye prompt kuralı ayrıca uyarır.
    """
    p = prompts.get(lang)
    return " · ".join(p.CHART_UPCOMING_FMT.format(
        date=e["date"],
        transit=prompts.planet_name(lang, e["transit"]),
        natal=prompts.planet_name(lang, e["natal"]),
        aspect=prompts.aspect_name(lang, e["aspect"])) for e in events)


def gunun_gokyuzu(facts: dict[str, Any] | None, lang: str | None = None,
                  today: dt.date | None = None) -> str:
    """`render`in GÜN yarısı: tarih damgası + transitler + yaklaşanlar.

    `render(..., include_transits=False)` ile birlikte kullanılır: o kalıcı
    olanı verir, bu bugüne ait olanı. Bölmenin sebebi modele hangi satırın
    kaç gün geçerli olduğunu söylemek; iki blok ayrı başlıklara girdiği için
    "bugün" iddiası artık metnin içinde kaybolmuyor.

    Tarih damgası ŞART çünkü `yaklasan` satırları mutlak tarih taşıyor
    ("2026-10-07: …"); bugünün tarihi bilinmezse model o tarihi bugünden
    kaç gün sonra olduğunu bilemez ve "yarın" diye okuyabilir.

    **Günün olgusu yoksa BOŞ döner** ve bu kuralın bedeli ölçülmüştür:
    bu blok tüketicinin önbellek KOVASIDIR (bkz. `report_service._gun_kovasi`).
    Yalnız tarih damgası basılsa kova her gün dönerdi; dönen her kova bir
    LLM üretimi demek, yani içeriği gün gün AYNI olan bir metin için günde
    5 jeton. Ölçüm (2026-10-03, 30 günlük efemeris taraması, Istanbul 1990
    doğumu): transit satırı 30 günün 30'unda farklı ve hiçbir gün boş değil
    — yani doğum verisi olan kullanıcıda blok zaten her gün dönüyor; boş
    dönmesi yalnız doğum verisi olmayan ya da efemerisin düştüğü hâlde olur
    ve o hâlde söylenecek bir "bugün" de yoktur.

    ``today`` verilmezse SUNUCUNUN günü kullanılır; çağıranlar KULLANICININ
    yerel gününü geçer (`entitlements.user_local_date`) — gün sınırının tek
    kaynağı orası, çünkü sunucu UTC'de koşuyor ve Türkiye'de kullanıcının
    günü 03:00'te dönüyor.
    """
    if not facts:
        return ""
    vurus = facts.get("transits") or []
    yaklasan = facts.get("upcoming") or []
    if not vurus and not yaklasan:
        return ""

    p = prompts.get(lang)
    satirlar = ["- {}: {}".format(
        p.CHART_TODAY_LABEL, (today or dt.date.today()).isoformat())]
    if vurus:
        satirlar.append("- {}: {}".format(
            p.CHART_TRANSITS_LABEL, transit_lines(vurus, lang)))
    if yaklasan:
        satirlar.append("- {}: {}".format(
            p.CHART_UPCOMING_LABEL, upcoming_lines(yaklasan, lang)))
    return "\n".join(satirlar)


def render_bazi(facts: dict[str, Any], lang: str | None = None) -> str:
    """BaZi olgularını 2-3 satırlık fısıltı bloğuna çevirir (B8)."""
    p = prompts.get(lang)
    satirlar: list[str] = []

    dm = facts.get("day_master") or {}
    parcalar = [f"{p.CHART_BAZI_DM_LABEL}: {dm.get('pinyin', '?')} "
                f"{p.POLARITY_NAMES.get(dm.get('polarity', ''), '')} "
                f"{p.BAZI_ELEMENTS.get(dm.get('element', ''), '')}".strip()]
    if facts.get("verdict"):
        parcalar.append(
            f"{p.BAZI_STRENGTH_NAMES.get(facts['verdict'], facts['verdict'])}"
            f" ({p.BAZI_SEASON_STATES.get(facts.get('season_state') or '', '')})")
    if facts.get("favorable_elements"):
        parcalar.append(p.CHART_BAZI_FAV_LABEL + ": " + ", ".join(
            p.BAZI_ELEMENTS.get(e, e) for e in facts["favorable_elements"]))
    satirlar.append("- " + " · ".join(parcalar))

    donem = []
    aktif = facts.get("current_luck")
    if aktif:
        donem.append(f"Da Yun {aktif['label']} "
                     f"({aktif['from_year']}-{aktif['to_year']}, "
                     f"{aktif['ten_god']})")
    yil = facts.get("current_year")
    if yil:
        donem.append(f"{p.CHART_BAZI_YEAR_LABEL} {yil['label']} "
                     f"({yil['ten_god']})")
    if donem:
        satirlar.append("- " + " · ".join(donem))

    if facts.get("stars"):
        satirlar.append("- " + " · ".join(
            f"{p.SHEN_SHA_NAMES.get(y['key'], y['key'])} [{y['pillar']}]"
            for y in facts["stars"]))
    return "\n".join(satirlar)


#: ``facts`` için "HİÇ VERİLMEDİ" nöbetçisi.
#:
#: ``None`` iki ayrı şeyi anlatıyordu ve ikisi karıştığı için iş tekrar
#: ediyordu: "ben hesaplamadım, sen hesapla" ile "HESAPLADIM ve olgu
#: ÇIKMADI". İki çağıran da (`api/chat.py`, `api/face_reading.py`) olguları
#: kendisi üretip geçiyor — yorumlarında yazdığı gerekçe de bu: "iki ayrı
#: çağrı iki ayrı önbellek turu demek olurdu". Ama `chart_facts` düştüğünde
#: (efemeris hatası) ``None`` dönüyor, eski kapı onu "verilmedi" sanıp
#: AYNI isteği bir kez daha deniyordu: istek başına iki boşa hesap.
#: `_cached` hata yolunda `cache.set` çağırmadığı için ikinci deneme de
#: önbellekten dönmüyor — gerçekten iki kez hesaplanıyordu.
_OLGU_VERILMEDI = object()


def chart_whisper(uid: str, profile: dict[str, Any] | None,
                  lang: str | None = None,
                  facts: dict[str, Any] | None | object = _OLGU_VERILMEDI,
                  include_bazi: bool = False,
                  include_transits: bool = True) -> str:
    """Sohbete iliştirilecek harita bloğu.

    Derin sürüm ancak gerçek doğum verisi varsa ve hesap başarılıysa üretilir;
    aksi halde bugüne kadarki sığ özete (`profile_service.chart_summary`)
    düşülür. Sohbet hiçbir koşulda haritasız kalmaz.

    ``facts`` verilirse yeniden hesaplanmaz. Sohbet ucu olguları bilgi tabanı
    sorgusunu kurmak için zaten üretiyor; ikinci kez istemek gereksiz bir
    önbellek turu demek olurdu. ``facts=None`` GEÇMEK de "verildi"
    sayılır ve "hesaplandı, olgu çıkmadı" demektir — çağıran o hâlde sığ
    özete düşülmesini istiyor, yeniden denenmesini DEĞİL (bkz.
    `_OLGU_VERILMEDI`).

    ``include_bazi`` (Revize B8) yalnızca Rytho+ sohbetinde açılır: BaZi
    ücretli üründür ve fısıltıdan sızdırılmaz — dürüst kapı, gizli tanıtım
    değil. Açıkken "BaZi'm ne?" sorusu deterministik veriyle cevaplanır.

    ``include_transits=False`` güne bağlı satırları bu bloktan çıkarır;
    onları ayrı bir başlık altında isteyen çağıran `gunun_gokyuzu`yu
    kullanır (bkz. `render`). SIĞ özete düşüldüğünde bayrak etkisizdir ve
    olması gereken de bu: sığ özet (Güneş/Ay/Yükselen) hiç transit
    taşımıyor.
    """
    if not profile:
        return ""
    if facts is _OLGU_VERILMEDI:
        # ⚠️ `today=` BURADA DA geçilir. Bu, çağıranın olguları hazır
        # vermediği YEDEK dal ve bir tur boyunca `chart_facts(uid, profile)`
        # diye çağrılıyordu — yani kova SUNUCUNUN UTC gününden kuruluyordu.
        # Türkiye'de (UTC+3) 00:00-03:00 arasında bu kullanıcının DÜNÜNE
        # düşer ve model dünün transitini "bugün" diye anlatır. Asıl yolda
        # (`api/chat.py`, `api/face_reading.py`) onarılmış olan kusur, tam
        # da kimsenin bakmadığı yedek dalda yaşamaya devam ediyordu.
        facts = chart_facts(uid, profile,
                            today=entitlements.user_local_date(uid))
    if not facts:
        # SESSİZ kalmasın (KA8): bu düşüş "sadece burcumu biliyor"
        # şikâyetinin birebir mekanizmasıydı ve loglarda hiç görünmüyordu.
        logger.info("Harita fısıltısı SIĞ özete düştü (%s): olgular yok "
                    "(doğum verisi eksik ya da hesap üretilemedi)", uid)
        return profile_service.chart_summary(profile, lang=lang)
    metin = render(facts, lang=lang,
                   include_transits=include_transits).strip()
    if include_bazi:
        bazi = bazi_facts(uid, profile)
        if bazi:
            try:
                metin = (metin + "\n" +
                         render_bazi(bazi, lang=lang)).strip()
            except Exception as exc:  # fısıltı süsü sohbeti düşürmesin
                logger.warning("BaZi fısıltısı üretilemedi: %s", exc)
    return metin or profile_service.chart_summary(profile, lang=lang)

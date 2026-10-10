"""BaZi (Dört Sütun / Kaderin Sekiz Karakteri) hesaplama motoru.

Gerçek güneş terimlerine (Jie Qi) dayanır: Güneş'in ekliptik boylamı Swiss
Ephemeris ile hesaplanır, ay sütunları 30 derecelik güneş dilimlerine göre
belirlenir (klasik Ziping yöntemi).

- Yıl sütunu: Li Chun (Güneş 315 derece) sınırına göre
- Ay sütunu: Beş Kaplan kuralı (yıl gövdesinden ay gövdesi)
- Gün sütunu: 1949-10-01 = JiaZi çapası ile doğrulanmış 60'lık döngü
- Saat sütunu: Beş Sıçan kuralı (gün gövdesinden saat gövdesi)
- Şans Sütunları (Da Yun): cinsiyet + yıl polaritesine göre ileri/geri,
  başlangıç yaşı bir sonraki/önceki Jie sınırına olan gün sayısı / 3
"""
from __future__ import annotations

import datetime as dt
from typing import Any
from zoneinfo import ZoneInfo

import swisseph as swe

from services.geo_service import resolve_city

STEMS = [
    {"pinyin": "Jia", "cn": "甲", "element": "wood", "polarity": "Yang"},
    {"pinyin": "Yi", "cn": "乙", "element": "wood", "polarity": "Yin"},
    {"pinyin": "Bing", "cn": "丙", "element": "fire", "polarity": "Yang"},
    {"pinyin": "Ding", "cn": "丁", "element": "fire", "polarity": "Yin"},
    {"pinyin": "Wu", "cn": "戊", "element": "earth", "polarity": "Yang"},
    {"pinyin": "Ji", "cn": "己", "element": "earth", "polarity": "Yin"},
    {"pinyin": "Geng", "cn": "庚", "element": "metal", "polarity": "Yang"},
    {"pinyin": "Xin", "cn": "辛", "element": "metal", "polarity": "Yin"},
    {"pinyin": "Ren", "cn": "壬", "element": "water", "polarity": "Yang"},
    {"pinyin": "Gui", "cn": "癸", "element": "water", "polarity": "Yin"},
]

BRANCHES = [
    {"pinyin": "Zi", "cn": "子", "animal": "rat", "element": "water"},
    {"pinyin": "Chou", "cn": "丑", "animal": "ox", "element": "earth"},
    {"pinyin": "Yin", "cn": "寅", "animal": "tiger", "element": "wood"},
    {"pinyin": "Mao", "cn": "卯", "animal": "rabbit", "element": "wood"},
    {"pinyin": "Chen", "cn": "辰", "animal": "dragon", "element": "earth"},
    {"pinyin": "Si", "cn": "巳", "animal": "snake", "element": "fire"},
    {"pinyin": "Wu", "cn": "午", "animal": "horse", "element": "fire"},
    {"pinyin": "Wei", "cn": "未", "animal": "goat", "element": "earth"},
    {"pinyin": "Shen", "cn": "申", "animal": "monkey", "element": "metal"},
    {"pinyin": "You", "cn": "酉", "animal": "rooster", "element": "metal"},
    {"pinyin": "Xu", "cn": "戌", "animal": "dog", "element": "earth"},
    {"pinyin": "Hai", "cn": "亥", "animal": "pig", "element": "water"},
]

# Element uretim dongusu: wood -> fire -> earth -> metal -> water -> wood
# Degerler dilden bagimsiz ANAHTARDIR; adlar services/prompts altinda.
_ELEMENT_ORDER = ["wood", "fire", "earth", "metal", "water"]

#: Gizli kökler (藏干) — dal indeksi → [(gövde indeksi, ağırlık), ...].
#:
#: Her dal tek elementten ibaret değildir: 寅 (Yin) içinde Jia ahşabının
#: yanında Bing ateşi ve Wu toprağı da yatar. Bunlar sayılmadan element
#: dağılımı sistematik yanlış çıkar — "haritanda hiç su yok" denen kişinin
#: suyu çoğu zaman bir dalın içindedir (Revize B2).
#:
#: Ana qi önce. Kaynak: kanonik Ziping tablosu (Zi Ping Zhen Quan geleneği).
#: Si ve Xu'nun artık-qi SIRASI kaynaklar arasında oynayabilir; seçilen
#: sürüm budur ve test_bazi_engine ile dondurulmuştur.
#:
#: Ağırlıklar: tek gövdeli 1.0; iki gövdeli 0.7/0.3; üç gövdeli 0.6/0.3/0.1.
#: Her dal toplam 1.0 dağıtır — böylece 8 karakterlik dağılımın toplamı
#: 8.0 kalır (saatsiz haritada 6.0). Değişmez, testle korunur.
HIDDEN_STEMS: dict[int, list[tuple[int, float]]] = {
    0: [(9, 1.0)],                       # Zi   子: Gui
    1: [(5, 0.6), (9, 0.3), (7, 0.1)],   # Chou 丑: Ji, Gui, Xin
    2: [(0, 0.6), (2, 0.3), (4, 0.1)],   # Yin  寅: Jia, Bing, Wu
    3: [(1, 1.0)],                       # Mao  卯: Yi
    4: [(4, 0.6), (1, 0.3), (9, 0.1)],   # Chen 辰: Wu, Yi, Gui
    5: [(2, 0.6), (6, 0.3), (4, 0.1)],   # Si   巳: Bing, Geng, Wu
    6: [(3, 0.7), (5, 0.3)],             # Wu   午: Ding, Ji
    7: [(5, 0.6), (3, 0.3), (1, 0.1)],   # Wei  未: Ji, Ding, Yi
    8: [(6, 0.6), (8, 0.3), (4, 0.1)],   # Shen 申: Geng, Ren, Wu
    9: [(7, 1.0)],                       # You  酉: Xin
    10: [(4, 0.6), (7, 0.3), (3, 0.1)],  # Xu   戌: Wu, Xin, Ding
    11: [(8, 0.7), (0, 0.3)],            # Hai  亥: Ren, Jia
}

# On Tanri (Ten Gods) — Day Master ile diger govdeler arasindaki iliski.
#
# Pinyin ad dilden bagimsizdir; ACIKLAMA metni tasinmaz, yerine anahtar
# doner (services/prompts altindaki TEN_GOD_MEANINGS tablosundan cozulur).
_TEN_GODS = {
    ("same", True): ("Bi Jian", "bi_jian"),
    ("same", False): ("Jie Cai", "jie_cai"),
    ("produces_me", True): ("Pian Yin", "pian_yin"),
    ("produces_me", False): ("Zheng Yin", "zheng_yin"),
    ("i_produce", True): ("Shi Shen", "shi_shen"),
    ("i_produce", False): ("Shang Guan", "shang_guan"),
    ("i_control", True): ("Pian Cai", "pian_cai"),
    ("i_control", False): ("Zheng Cai", "zheng_cai"),
    ("controls_me", True): ("Qi Sha", "qi_sha"),
    ("controls_me", False): ("Zheng Guan", "zheng_guan"),
}


def _element_relation(me: str, other: str) -> str:
    i, j = _ELEMENT_ORDER.index(me), _ELEMENT_ORDER.index(other)
    if i == j:
        return "same"
    if (i + 1) % 5 == j:
        return "i_produce"
    if (j + 1) % 5 == i:
        return "produces_me"
    if (i + 2) % 5 == j:
        return "i_control"
    return "controls_me"


def _ten_god(day_stem: int, other_stem: int) -> dict[str, str]:
    me, other = STEMS[day_stem], STEMS[other_stem]
    relation = _element_relation(me["element"], other["element"])
    same_polarity = me["polarity"] == other["polarity"]
    name, meaning_key = _TEN_GODS[(relation, same_polarity)]
    return {"name": name, "meaning_key": meaning_key}


def attach_hidden_stems(pillars: dict[str, Any], day_stem: int) -> None:
    """Her dalın gizli köklerini ve ana-qi On Tanrısını iliştirir (B2).

    Gün gövdesinin kendisi On Tanrı almaz (Day Master'dır); gizli köklerin
    HEPSİ alır — gün dalındaki gizli kök Day Master'la aynı gövdeyse bu
    meşru bir Bi Jian'dır (omuzdaş), istisna değil.
    """
    for p in pillars.values():
        if p is None:
            continue
        dal = p["branch"]
        hidden = []
        for s_idx, agirlik in HIDDEN_STEMS[dal["index"]]:
            hidden.append({
                "index": s_idx,
                **STEMS[s_idx],
                "weight": agirlik,
                "ten_god": _ten_god(day_stem, s_idx),
            })
        dal["hidden"] = hidden
        # Ana qi'nin On Tanrısı dalın kendisinin On Tanrısı sayılır —
        # klasik kullanım bu (dalın "temsilcisi" ana qi'dir).
        dal["ten_god"] = hidden[0]["ten_god"]


def element_distribution_for(
        pillars: dict[str, Any]) -> dict[str, float]:
    """Gizli kök ağırlıklı element dağılımı (B2). Saf — test edilebilir.

    Gövdeler 1.0, dalın gizli kökleri kendi ağırlıklarıyla (dal başına
    toplam 1.0). Değişmez: 4 sütunda toplam 8.0, saatsizde 6.0.
    """
    sayim = {e: 0.0 for e in _ELEMENT_ORDER}
    for p in pillars.values():
        if p is None:
            continue
        sayim[p["stem"]["element"]] += 1.0
        for h in p["branch"]["hidden"]:
            sayim[h["element"]] += h["weight"]
    return {e: round(v, 2) for e, v in sayim.items()}


#: "Eksik element" eşiği: ağırlıklı toplam bunun altındaysa element fiilen
#: beslenmiyor sayılır. Düz "hiç yok" tanımı gizli kökler yüzünden yanıltıcı
#: olurdu; 0.35, tek bir zayıf artık-qi'nin (0.1-0.3) "var" sayılmamasını,
#: bir ana-qi'nin (0.6+) sayılmasını sağlar.
MISSING_THRESHOLD = 0.35


def _sun_longitude(when_utc: dt.datetime) -> float:
    jd = swe.julday(
        when_utc.year, when_utc.month, when_utc.day,
        when_utc.hour + when_utc.minute / 60 + when_utc.second / 3600,
    )
    pos, _ = swe.calc_ut(jd, swe.SUN)
    return pos[0] % 360


def _pillar(stem_idx: int, branch_idx: int) -> dict[str, Any]:
    s, b = STEMS[stem_idx % 10], BRANCHES[branch_idx % 12]
    return {
        "stem": {"index": stem_idx % 10, **s},
        "branch": {"index": branch_idx % 12, **b},
        "label": f"{s['cn']}{b['cn']} ({s['pinyin']} {b['pinyin']})",
    }


def _find_jie_boundary(start_utc: dt.datetime, forward: bool) -> dt.datetime:
    """Bir sonraki/önceki güneş terimi (Jie: boylam % 30 == 15 dereceleri
    değil, ay sınırları 315+30k) anını 1 saatlik adım + ikili arama ile bulur."""
    def month_index(t: dt.datetime) -> int:
        return int(((_sun_longitude(t) - 315) % 360) // 30)

    step = dt.timedelta(hours=6) * (1 if forward else -1)
    t = start_utc
    base = month_index(t)
    for _ in range(140 * 4):  # en fazla ~35 gün
        t2 = t + step
        if month_index(t2) != base:
            lo, hi = (t, t2) if forward else (t2, t)
            for _ in range(30):
                mid = lo + (hi - lo) / 2
                if (month_index(mid) != base) == forward:
                    hi = mid
                else:
                    lo = mid
            return hi if forward else lo
        t = t2
    return t


def _true_solar_time(local: dt.datetime, lng: float) -> tuple[dt.datetime, int]:
    """Duvar saatini Gerçek Güneş Zamanı'na çevirir (Revize B1).

    Kullanıcının girdiği "kol saati" BaZi için geçersizdir: saat dilimi bir
    19. yüzyıl idari icadı, saat dalı ise Güneş'in gökteki GERÇEK konumu.
    İki düzeltme uygulanır:

    * **Boylam:** İstanbul (28.98°D) UTC+3 diliminin 45° meridyenine göre
      Güneş'ten ~64 dakika geridedir — dilim içindeki konum fark eder.
    * **Zaman Denklemi:** Dünya'nın yörüngesi eliptik; Güneş duvara göre
      −14…+16 dakika "hızlı/yavaş" gider. `swe.time_equ` GÜN cinsinden düz
      float döndürür, işareti görünür−ortalama (Kasım başı +16.4 dk, Şubat
      ortası −14.2 dk — test_bazi_engine bunu kilitler).

    Dönen: (güneş duvar saati [naive], duvar saatine göre sapma dakikası).
    Toplam sapma İstanbul'da ~−60…−80 dk: saat dilimi 120 dk olduğu için
    doğumların kabaca üçte birinde saat DALINI değiştirir — bu düzeltme
    süs değil, saat sütununun ta kendisi.
    """
    utc = local.astimezone(dt.timezone.utc)
    jd = swe.julday(utc.year, utc.month, utc.day,
                    utc.hour + utc.minute / 60 + utc.second / 3600)
    eot_gun = swe.time_equ(jd)
    solar = (utc.replace(tzinfo=None)
             + dt.timedelta(hours=lng / 15.0, days=eot_gun))
    sapma = round((solar - local.replace(tzinfo=None)).total_seconds() / 60)
    return solar, sapma


#: Beş Kaplan (yıl gövdesi → ilk ayın gövdesi) ve Beş Sıçan (gün gövdesi
#: → Zi saatinin gövdesi) tabloları — İ2'de modül sabitine çıkarıldı:
#: get_bazi_chart ile tarih yardımcıları aynı tabloyu paylaşır.
FIVE_TIGERS = {0: 2, 5: 2, 1: 4, 6: 4, 2: 6, 7: 6, 3: 8, 8: 8, 4: 0, 9: 0}
FIVE_RATS = {0: 0, 5: 0, 1: 2, 6: 2, 2: 4, 7: 4, 3: 6, 8: 6, 4: 8, 9: 8}


def day_pillar_for_date(date: dt.date) -> dict[str, Any]:
    """Verilen (güneş-günü) tarihin gün sütunu — 60'lık döngü (İ2).

    `get_bazi_chart` içine gömülü aritmetiğin dışarı çıkarılmış hâli;
    harita da bunu çağırır (tek doğruluk kaynağı). Çapa 1900-01-01 =
    JiaXu — test_bazi_engine altın vektörleriyle kilitli. `cycle` da
    döner: Kong Wang (bazi_stars.void_branches) ve Liu Yao gün bağlamı
    ona ihtiyaç duyar.
    """
    days_since_anchor = (date - dt.date(1900, 1, 1)).days
    cycle = (days_since_anchor + 10) % 60
    return {**_pillar(cycle % 10, cycle % 12), "cycle": cycle}


def month_pillar_for_date(date: dt.date) -> dict[str, Any]:
    """Verilen tarihin ay sütunu — güneş boylamı + Beş Kaplan (İ2)."""
    ogle = dt.datetime(date.year, date.month, date.day, 12,
                       tzinfo=dt.timezone.utc)
    lon = _sun_longitude(ogle)
    yil = year_pillar_for_date(date)
    month_no = int(((lon - 315) % 360) // 30) + 1
    month_branch = (month_no + 1) % 12
    month_stem = (FIVE_TIGERS[yil["stem"]["index"]] + (month_no - 1)) % 10
    return _pillar(month_stem, month_branch)


def year_pillar_for_date(date: dt.date) -> dict[str, Any]:
    """Verilen tarihin yıl sütunu — Liu Nian (yıllık sütun) için (B5).

    Li Chun sınırı burada da geçerli: 15 Ocak hâlâ önceki yılın
    sütunundadır. Doğum yılı formülünün tarihe genellenmiş hâli.
    """
    ogle = dt.datetime(date.year, date.month, date.day, 12,
                       tzinfo=dt.timezone.utc)
    lon = _sun_longitude(ogle)
    y = date.year
    if date.month <= 2 and 270 <= lon < 315:
        y -= 1
    return _pillar((y - 4) % 10, (y - 4) % 12)


def get_bazi_chart(
    year: int, month: int, day: int, hour: int | None, minute: int,
    city: str = "Istanbul", nation: str | None = None,
    # Varsayılan "female" idi: cinsiyet vermeyen çağıran sessizce kadın
    # kuralıyla yön alıyordu. Motorun kendi varsayılanı da aynı sessiz
    # varsayımdı; "unspecified" ile yön ölçülemez sayılır (aşağıda).
    gender: str = "unspecified", name: str = "Gezgin",
) -> dict[str, Any]:
    # Saat bilinmiyorsa (hour=None) SAHTE bir saat üretilmez: saat sütunu
    # hiç kurulmaz, gün/yıl/ay üç sütunla devam edilir. 12:00 varsaymak
    # öğlen doğmuş gibi Wu saati üretiyordu — ölçmediğini ölçmüş gibi
    # göstermek. İç hesaplar (boylam, Jie mesafesi) gün ortasını kullanır;
    # gün ortası TST'yle de gece yarısını aşamaz, gün sütunu güvendedir.
    hour_known = hour is not None
    ic_saat, ic_dakika = (hour, minute) if hour_known else (12, 0)

    loc = resolve_city(city, nation)
    local = dt.datetime(year, month, day, ic_saat, ic_dakika,
                        tzinfo=ZoneInfo(loc.tz_str))
    utc = local.astimezone(dt.timezone.utc)

    # Gerçek Güneş Zamanı: saat dalı ve 23:00 gün-devri kararı BUNUNLA.
    # Yıl/ay sütunu güneş boylamından (zaten gerçek), Da Yun mesafesi
    # UTC'den hesaplanır — ikisine dokunulmaz.
    solar, tst_sapma = _true_solar_time(local, loc.lng)

    sun_lon = _sun_longitude(utc)

    # --- Yıl sütunu (Li Chun sınırı) ---
    bazi_year = year
    if month <= 2 and sun_lon < 315 and sun_lon >= 270:
        bazi_year = year - 1
    year_stem = (bazi_year - 4) % 10
    year_branch = (bazi_year - 4) % 12

    # --- Ay sütunu (güneş boylamından; ay 1 = Kaplan/Yin, Li Chun'da başlar) ---
    month_no = int(((sun_lon - 315) % 360) // 30) + 1  # 1..12
    month_branch = (month_no + 1) % 12  # ay 1 -> Yin (index 2)
    month_stem = (FIVE_TIGERS[year_stem] + (month_no - 1)) % 10

    # --- Gün sütunu (GÜNEŞ saatiyle 23:00 sonrası ertesi güne sayılır —
    # geç Zi ekolü, sabit ve belgeli; aritmetik day_pillar_for_date'te) ---
    day_date = solar.date()
    if solar.hour >= 23:
        day_date = day_date + dt.timedelta(days=1)
    gun = day_pillar_for_date(day_date)
    day_cycle = gun["cycle"]
    day_stem = gun["stem"]["index"]
    day_branch = gun["branch"]["index"]

    # --- Saat sütunu (Güneş saatiyle; saat bilinmiyorsa HİÇ kurulmaz) ---
    hour_pillar = None
    if hour_known:
        hour_branch = ((solar.hour + 1) // 2) % 12
        hour_stem = (FIVE_RATS[day_stem] + hour_branch) % 10
        hour_pillar = _pillar(hour_stem, hour_branch)

    pillars = {
        "year": _pillar(year_stem, year_branch),
        "month": _pillar(month_stem, month_branch),
        "day": _pillar(day_stem, day_branch),
        "hour": hour_pillar,
    }

    # --- Day Master ve On Tanrı ---
    # Aciklama metni burada KURULMAZ: "Gunun Efendisi: Yang Ahsap" gibi bir
    # cumle dili yuke gomerdi. Bilesenler doner, cumle isteğin dilinde
    # services/prompts icinde kurulur.
    day_master = {**STEMS[day_stem]}
    ten_gods = {
        "year": _ten_god(day_stem, year_stem),
        "month": _ten_god(day_stem, month_stem),
    }
    if hour_pillar is not None:
        ten_gods["hour"] = _ten_god(day_stem, hour_pillar["stem"]["index"])

    # --- Gizli kökler + ağırlıklı element dağılımı (B2) ---
    attach_hidden_stems(pillars, day_stem)
    element_count = element_distribution_for(pillars)
    dominant = max(element_count, key=element_count.get)
    missing = [e for e, c in element_count.items()
               if c < MISSING_THRESHOLD]

    # --- Day Master gücü + yararlı element (B3) ---
    # İçe aktarma fonksiyon içinde: bazi_strength bu modülün tablolarını
    # kullanıyor, modül düzeyinde içe aktarmak döngü kurardı.
    from services import bazi_stars, bazi_strength
    strength = bazi_strength.assess_strength(pillars, day_stem,
                                             element_count)

    # --- Shen Sha (B4): 5 yıldız + Kong Wang ---
    shen_sha = bazi_stars.find_shen_sha(pillars, day_cycle)

    # --- Şans Sütunları (Da Yun) ---
    yang_year = STEMS[year_stem]["polarity"] == "Yang"
    cinsiyet = (gender or "").lower()
    is_male = cinsiyet in ("male", "erkek", "m", "man")
    is_female = cinsiyet in ("female", "kadin", "kadın", "f", "woman")
    # Yön yalnız cinsiyet BİLİNİYORSA hesaplanır. "unspecified", "other",
    # boş dize ve tanınmayan her değer aynı kapıdan geçer: eskiden bunlar
    # sessizce `is_male=False` → yin (kadın) kuralına düşüyor ve kullanıcı
    # "belirtmek istemiyorum" dediği hâlde yanıtta `gender: "female"` ve
    # tek yönlü sekiz dönem görüyordu — ölçülmeyen şey ölçülmüş gibi
    # sunuluyordu.
    yon_biliniyor = is_male or is_female

    # --- Hesap varsayımı beyanları ---
    # Motor bir temel SEÇMEK zorunda kaldıysa bunu anahtar olarak söyler;
    # cümle localize_bazi'de isteğin dilinde kurulur, rapor ve ekranda
    # görünür. Sessiz varsayım bu motorda yasak.
    note_keys: list[str] = []
    if not yon_biliniyor:
        # Yön HESAPLANMADI (eski anahtar `luck_direction_yin` bir varsayımı
        # beyan ediyordu; artık varsayım yok, yokluk beyan ediliyor).
        note_keys.append("luck_direction_unknown")
    if not hour_known:
        note_keys.append("hour_unknown")
    if loc.fallback:
        # Şehir çözülemedi, İstanbul boylamıyla hesaplandı: TST düzeltmesi
        # yanlış boylamla hatayı büyütebilir — kullanıcı bilmeli.
        note_keys.append("tst_fallback_city")

    def _sans_dizisi(ileri: bool) -> tuple[list[dict[str, Any]],
                                           dict[str, Any]]:
        """Verilen yön için sekiz dönem + başlangıç yaşı.

        "Yönsüz sütun" diye bir şey YOK, bu yüzden yön bilinmeyince
        sütunlar tek listede verilemiyor: dönem sütunu ay sütunundan
        ±i adımla kuruluyor (ileri 1. dönem = ay+1, geri = ay−1) VE
        başlangıç yaşı yönün Jie sınırına olan mesafeden geliyor (ileri:
        sonraki sınır, geri: önceki sınır; ikisi bir ay içinde toplanır,
        yani yaşlar da ayrışır). İki yön iki ayrı dizidir.
        """
        boundary = _find_jie_boundary(utc, forward=ileri)
        days_to_boundary = abs((boundary - utc).total_seconds()) / 86400

        # Klasik dönüşüm TAM çözünürlükle (B5): 3 gün = 1 yıl → 1 gün = 4
        # ay. Eski `round(days/3)` ay/gün bilgisini atıyordu ve geçiş
        # tarihi ±6 aya kadar kayıyordu; `max(1,...)` kelepçesi de 0-1 gün
        # mesafeli doğumları gizliyordu — "0 yaş 4 ay" meşru bir sonuçtur.
        toplam_ay = max(0, round(days_to_boundary * 4))
        start_years, start_months = divmod(toplam_ay, 12)
        ay_indeksi = local.month - 1 + toplam_ay
        start_takvim_yili = local.year + ay_indeksi // 12
        baslangic = {
            "years": start_years,
            "months": start_months,
            # Ay çözünürlüğü bilinçli: gün bileşeni doğum saatine bağlı ve
            # saatsiz haritada zaten ±4 ay belirsizlik var.
            "date": f"{start_takvim_yili}-{ay_indeksi % 12 + 1:02d}",
        }

        donemler = []
        for i in range(1, 9):
            offset = i if ileri else -i
            lp = _pillar(month_stem + offset, month_branch + offset)
            from_year = start_takvim_yili + (i - 1) * 10
            donemler.append({
                "from_age": start_years + (i - 1) * 10,
                "to_age": start_years + i * 10 - 1,
                # Takvim yılları (B5): "3-13 yaş" tek başına kullanıcıya
                # hesap yaptırıyordu; "1993-2003" yaptırmaz.
                "from_year": from_year,
                "to_year": from_year + 9,
                **lp,
                "ten_god": _ten_god(day_stem, (month_stem + offset) % 10),
            })
        return donemler, baslangic

    if yon_biliniyor:
        forward = yang_year == is_male  # yang+erkek veya yin+kadın -> ileri
        luck_pillars, luck_start = _sans_dizisi(forward)
        luck_direction = "forward" if forward else "backward"
        luck_pillar_candidates = None
    else:
        # Yön bilinmeyince `luck_pillars` BOŞ, iki yön de `candidates`
        # altında: her okuyucu (`localize_bazi`, rapor prompt'u `[:4]`,
        # mobil sekmenin yatay listesi, `chart_context` aktif dönem) düz
        # listeyi "bu senin dönemlerin" diye sunuyor — içine iki diziyi
        # art arda koymak, prompt'a ilk dördü (= tek yön) sokardı; tek
        # yönü koymak eski kusurun ta kendisi. Boş liste bu okuyucuların
        # hepsinde ölçüldü: prompt boş satır, sekme boş şerit, aktif
        # dönem None — hiçbiri düşmüyor. Adaylar okuyucusu açıldığında
        # "iki olası yol" diye gösterilsin diye taşınır; yorumlanmaz.
        forward = None
        luck_pillars, luck_start = [], None
        luck_direction = None
        luck_pillar_candidates = {
            yon: dict(zip(("luck_pillars", "luck_start"),
                          _sans_dizisi(yon == "forward")))
            for yon in ("forward", "backward")
        }

    # --- Liu Nian: içinde bulunulan yılın sütunu + aktif Da Yun (B5) ---
    bugun = dt.date.today()
    yillik = year_pillar_for_date(bugun)
    current_year_pillar = {
        **yillik,
        "year": bugun.year,
        "ten_god": _ten_god(day_stem, yillik["stem"]["index"]),
    }
    current_luck_index = next(
        (i for i, lp in enumerate(luck_pillars)
         if lp["from_year"] <= bugun.year <= lp["to_year"]), None)

    return {
        "name": name,
        # Üçüncü değer eskiden yoktu: ikili olmayan her şey "female"
        # yazılıyordu ve rapor önbellek anahtarına da öyle giriyordu.
        "gender": ("male" if is_male
                   else "female" if is_female else "unspecified"),
        # Şans sütunlarının yönü ÖLÇÜLDÜ mü — False ise `luck_direction`
        # None, `luck_pillars` boş ve iki aday `luck_pillar_candidates`ta.
        "luck_direction_known": yon_biliniyor,
        "luck_pillar_candidates": luck_pillar_candidates,
        # Hesap sürümü: hesap davranışı değişen her fazda artar ve rapor
        # önbellek anahtarına girer — eski metinler kendiliğinden düşer,
        # "yeni harita + 30 günlük eski rapor" çelişkisi hiç yaşanmaz.
        # v3: Gerçek Güneş Zamanı (B1). v4: gizli kökler + ağırlıklı
        # dağılım (B2). v5: şans başlangıcı ay çözünürlüğü + takvim
        # yılları + Liu Nian (B5).
        "calc_version": "5",
        "note_keys": note_keys,
        "hour_known": hour_known,
        # Güneş duvar saati ve duvar saatine göre sapma — beyan bundan
        # kurulur ("13:30 → 12:22, −68 dk"). Saat bilinmiyorsa anlamsız.
        "solar_time": solar.isoformat() if hour_known else None,
        "tst_offset_minutes": tst_sapma if hour_known else None,
        "birth_local": local.isoformat(),
        "timezone": loc.tz_str,
        "pillars": pillars,
        "day_master": day_master,
        "ten_gods": ten_gods,
        "element_distribution": element_count,
        "dominant_element": dominant,
        "missing_elements": missing,
        "strength": strength,
        "shen_sha": shen_sha,
        "zodiac_animal": BRANCHES[year_branch]["animal"],
        "luck_pillars": luck_pillars,
        "luck_direction": luck_direction,
        "luck_start": luck_start,
        # Saat bilinmeden Jie mesafesi gün ortasından hesaplanır; gün içi
        # ±12 saat, klasik dönüşümle (1 gün = 4 ay) ±4 ay eder.
        "luck_start_uncertainty_months": 0 if hour_known else 4,
        "current_year_pillar": current_year_pillar,
        "current_luck_index": current_luck_index,
    }

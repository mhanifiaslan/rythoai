"""Dile göre prompt ve persona modülleri.

Prompt'lar dilden bağımsız bir şablona çevirilerin doldurulmasıyla üretilmiyor;
her dil kendi modülünde kendi metnini taşıyor. Gerekçe: bunlar arayüz etiketi
değil, karakter tanımı. Türkçedeki samimi "sen" dili İngilizceye birebir
çevrildiğinde ton bozulur — İngilizcede aynı sıcaklık farklı cümle yapısıyla
kurulur. Kelime kelime çeviri, personayı düzleştirir.

Kullanım:
    from services import prompts
    p = prompts.get("en")
    p.SYSTEM_INSTRUCTION
"""
from __future__ import annotations

from types import ModuleType

from core import i18n
from services.prompts import en as _en
from services.prompts import tr as _tr

_MODULES: dict[str, ModuleType] = {"tr": _tr, "en": _en}


def get(lang: str | None) -> ModuleType:
    """Dilin prompt modülü; tanınmayan dil varsayılana düşer."""
    return _MODULES.get(lang or "", _MODULES[i18n.DEFAULT])


def sign_name(lang: str | None, sign_key: str) -> str:
    """Burç anahtarının (``leo``) o dildeki adı."""
    return get(lang).SIGN_NAMES.get(sign_key, sign_key)


def moon_phase_name(lang: str | None, phase_key: str | None) -> str:
    """Ay evresi anahtarının (``full_moon``) o dildeki adı."""
    if not phase_key:
        return ""
    return get(lang).MOON_PHASES.get(phase_key, phase_key)


def localize_moon_phase(lang: str | None, moon: dict | None) -> dict:
    """Gökyüzü sözlüğündeki ay evresine dile göre ``name`` alanı ekler.

    Hesap paylaşımlı önbellekten geldiği için evre yalnızca anahtar taşır;
    ada çeviri isteğin dilinde, yanıt üretilirken eklenir.
    """
    if not moon:
        return {}
    key = moon.get("key")
    if not key:
        # Anahtarsız gökyüzü (eski önbellek kaydı ya da test verisi):
        # elimizdeki ``name`` neyse onunla devam et, boş metin döndürme.
        return dict(moon)
    return {**moon, "name": moon_phase_name(lang, key)}


#: kerykeion burç kodu -> prompt modüllerindeki burç anahtarı.
_SIGN_CODE_TO_KEY = {
    "Ari": "aries", "Tau": "taurus", "Gem": "gemini", "Can": "cancer",
    "Leo": "leo", "Vir": "virgo", "Lib": "libra", "Sco": "scorpio",
    "Sag": "sagittarius", "Cap": "capricorn", "Aqu": "aquarius",
    "Pis": "pisces",
}


def sign_key_from_code(code: str | None) -> str | None:
    """kerykeion burç kodunun (``Leo``) dilden bağımsız anahtarı (``leo``).

    Element/nitelik gibi türetilmiş sayımlar burç ADINDAN değil anahtarından
    yapılmalı; aksi halde hesap dile bağımlı hale gelir.
    """
    return _SIGN_CODE_TO_KEY.get(code) if code else None


#: Sinyal teması -> emoji (OB5). Dil-nötr olduğu için modüllerde değil
#: burada; mobil `kThemeIcons` (basis_sheet.dart) ile AYNI dört tema.
#: Bildirim başlıklarında kullanılır; bilinmeyen temada yıldız.
THEME_EMOJIS = {
    "career": "💼",
    "relationships": "❤️",
    "inner": "🌙",
    "finance": "🪙",
}

DEFAULT_THEME_EMOJI = "✨"


def theme_emoji(theme: str | None) -> str:
    return THEME_EMOJIS.get(theme or "", DEFAULT_THEME_EMOJI)


def sign_name_from_code(lang: str | None, code: str | None) -> str:
    """kerykeion burç kodunun (``Leo``, ``Ari``) o dildeki adı."""
    if not code:
        return ""
    anahtar = _SIGN_CODE_TO_KEY.get(code)
    return sign_name(lang, anahtar) if anahtar else code


def sign_from_point(lang: str | None, point: dict | None) -> str:
    """Bir nokta sözlüğündeki burcu isteğin dilinde döndürür.

    Önce kerykeion kodu (``sign``) denenir; yoksa elde ne varsa (``sign_tr``)
    olduğu gibi gösterilir. Kod bulunamadığında boş string dönmek, arayüzde
    burç alanını tamamen boşaltırdı.
    """
    if not point:
        return ""
    kod = point.get("sign")
    if kod and kod in _SIGN_CODE_TO_KEY:
        return sign_name_from_code(lang, kod)
    return point.get("sign_tr") or kod or ""


def planet_name(lang: str | None, key: str | None) -> str:
    """Gezegen anahtarının (``Saturn``) o dildeki adı."""
    if not key:
        return ""
    return get(lang).PLANET_NAMES.get(key, key)


def aspect_name(lang: str | None, key: str | None) -> str:
    """Açı anahtarının (``square``) o dildeki adı."""
    if not key:
        return ""
    return get(lang).ASPECT_NAMES.get(key, key)


def localize_bazi(lang: str | None, chart: dict | None) -> dict:
    """BaZi haritasındaki anahtarları isteğin diline çevirir.

    Hesap motoru (bazi_service) element, hayvan ve On Tanrı için **anahtar**
    döndürür; ad ve açıklama burada kurulur. Motorda Türkçe ad tutulsaydı
    İngilizce kullanıcı hem ekranda hem yorumda "Ahşap" görürdü.
    """
    if not chart:
        return {}
    p = get(lang)

    def element(key: str | None) -> str:
        return p.BAZI_ELEMENTS.get(key or "", key or "")

    def polarity(key: str | None) -> str:
        return p.POLARITY_NAMES.get(key or "", key or "")

    def tanri(god: dict | None) -> dict:
        if not god:
            return {}
        return {**god,
                "meaning": p.TEN_GOD_MEANINGS.get(god.get("meaning_key") or "",
                                                  god.get("meaning_key") or "")}

    def sutun(pillar: dict | None) -> dict:
        if not pillar:
            return {}
        gövde = pillar.get("stem") or {}
        dal = pillar.get("branch") or {}
        çevrili_dal = {
            **dal,
            "element": element(dal.get("element")),
            "animal": p.BAZI_ANIMALS.get(dal.get("animal") or "",
                                         dal.get("animal") or ""),
        }
        # Gizli kökler (B2): element/polarite adları ve On Tanrı açıklaması
        # da isteğin dilinde.
        if dal.get("hidden"):
            çevrili_dal["hidden"] = [
                {**h,
                 "element": element(h.get("element")),
                 "polarity": polarity(h.get("polarity")),
                 "ten_god": tanri(h.get("ten_god"))}
                for h in dal["hidden"]
            ]
        if dal.get("ten_god"):
            çevrili_dal["ten_god"] = tanri(dal["ten_god"])
        return {
            **pillar,
            "stem": {**gövde,
                     "element": element(gövde.get("element")),
                     "polarity": polarity(gövde.get("polarity"))},
            "branch": çevrili_dal,
        }

    day_master = chart.get("day_master") or {}
    çevrilmiş_dm = {
        **day_master,
        "element": element(day_master.get("element")),
        "polarity": polarity(day_master.get("polarity")),
    }
    if day_master:
        çevrilmiş_dm["description"] = p.DAY_MASTER_DESCRIPTION.format(
            polarity=çevrilmiş_dm["polarity"], element=çevrilmiş_dm["element"],
            cn=day_master.get("cn", ""), pinyin=day_master.get("pinyin", ""),
        )

    return {
        **chart,
        "gender": p.GENDER_NAMES.get(chart.get("gender") or "",
                                     chart.get("gender") or ""),
        # Saat sütunu bilinmeyen doğumda None'dır ve None KALIR: boş sözlük
        # "veri var ama boş" okunur, None "ölçülmedi" der (Revize B1).
        "pillars": {ad: (sutun(v) if v else None)
                    for ad, v in (chart.get("pillars") or {}).items()},
        "day_master": çevrilmiş_dm,
        "ten_gods": {ad: tanri(v)
                     for ad, v in (chart.get("ten_gods") or {}).items()},
        "element_distribution": {
            element(k): v
            for k, v in (chart.get("element_distribution") or {}).items()},
        "dominant_element": element(chart.get("dominant_element")),
        "missing_elements": [element(e)
                             for e in (chart.get("missing_elements") or [])],
        "zodiac_animal": p.BAZI_ANIMALS.get(chart.get("zodiac_animal") or "",
                                            chart.get("zodiac_animal") or ""),
        "luck_pillars": [{**sutun(lp), "ten_god": tanri(lp.get("ten_god"))}
                         for lp in (chart.get("luck_pillars") or [])],
        # Liu Nian (B5): içinde bulunulan yılın sütunu da çevrilir.
        "current_year_pillar": (
            {**sutun(chart["current_year_pillar"]),
             "ten_god": tanri(chart["current_year_pillar"].get("ten_god"))}
            if chart.get("current_year_pillar") else None),
        # Güç hükmü (B3): anahtarlar korunur, *_name alanları isteğin
        # dilinde eklenir — UI ve prompt cümleyi buradan okur.
        "strength": _strength_local(p, element, chart.get("strength")),
        # Shen Sha (B4): ad ve kısa anlam isteğin dilinde.
        "shen_sha": [
            {**s,
             "name": p.SHEN_SHA_NAMES.get(s.get("key") or "",
                                          s.get("key") or ""),
             "meaning": p.SHEN_SHA_MEANINGS.get(s.get("key") or "", "")}
            for s in chart.get("shen_sha") or []
        ],
        # Hesap varsayımlarının beyanı (Revize B0/B1): motor anahtar
        # döndürür, cümle burada kurulur. Boş liste = beyan gerektiren
        # varsayım yok. TST satırı ayrıca kurulur çünkü içine gerçek
        # saatler giriyor — düz tablodan çıkmaz.
        "notes": _bazi_notes(p, chart),
    }


def _strength_local(p, element, strength: dict | None) -> dict | None:
    if not strength:
        return None
    return {
        **strength,
        "verdict_name": p.BAZI_STRENGTH_NAMES.get(
            strength.get("verdict") or "", strength.get("verdict") or ""),
        "season_state_name": p.BAZI_SEASON_STATES.get(
            strength.get("season_state") or "",
            strength.get("season_state") or ""),
        "favorable_names": [element(e)
                            for e in strength.get("favorable_elements") or []],
        "unfavorable_names": [
            element(e) for e in strength.get("unfavorable_elements") or []],
        "climate_element_name": element(strength.get("climate_element"))
        if strength.get("climate_element") else None,
    }


def _bazi_notes(p, chart: dict) -> list[str]:
    notes = [p.BAZI_NOTES[k]
             for k in (chart.get("note_keys") or [])
             if k in p.BAZI_NOTES]
    # Gerçek Güneş Zamanı beyanı: sapma saat DALINI değiştirebilecek
    # büyüklükte olduğu için kullanıcı dönüşümü görmeli.
    solar = chart.get("solar_time")
    sapma = chart.get("tst_offset_minutes")
    yerel = chart.get("birth_local")
    if solar and yerel and sapma is not None:
        notes.append(p.BAZI_TST_NOTE.format(
            local=yerel[11:16], solar=solar[11:16],
            offset=f"{sapma:+d}"))
    return notes


def localize_hexagram(lang: str | None, h: dict | None) -> dict:
    """Tek heksagramı isteğin diline indirger (Revize İ0).

    Veri katmanı her dili ayrı alanda tutuyor (``judgment_tr`` /
    ``judgment_en``); burada tek bir ``judgment``/``image``/``name_local``
    alanına düşürülür. `localize_iching`'in içindeki kapatıcının dışarı
    çıkarılmış hâli — /iching/hexagram/{n} sözlük ucu da bunu kullanır
    (eskiden localize'sız dönüyor, judgment_tr sızıyordu).
    """
    if not h:
        return {}
    son_ek = "en" if (lang or DEFAULT) == "en" else "tr"
    p = get(lang)

    def trigram(t: dict | None) -> dict:
        if not t:
            return {}
        return {**t,
                "name": t.get(f"name_{son_ek}") or t.get("name_tr") or "",
                "element": p.BAZI_ELEMENTS.get(t.get("element") or "",
                                               t.get("element") or "")}

    return {
        **h,
        "name_local": h.get(f"name_{son_ek}") or h.get("name_tr") or "",
        "judgment": h.get(f"judgment_{son_ek}") or h.get("judgment_tr") or "",
        "image": h.get(f"image_{son_ek}") or h.get("image_tr") or "",
        # 384 yao pasajı (İ1): isteğin diline indirgenmiş çizgi metinleri.
        "line_texts": h.get(f"lines_{son_ek}") or h.get("lines_tr"),
        "all_lines": h.get(f"all_lines_{son_ek}") or h.get("all_lines_tr"),
        "lower_trigram": trigram(h.get("lower_trigram")),
        "upper_trigram": trigram(h.get("upper_trigram")),
    }


def localize_iching(lang: str | None, cast: dict | None) -> dict:
    """I Ching çekilişindeki heksagram metinlerini isteğin diline indirger."""
    if not cast:
        return {}
    p = get(lang)
    sonuç = {**cast,
             "primary": localize_hexagram(lang, cast.get("primary"))}
    if cast.get("transformed"):
        sonuç["transformed"] = localize_hexagram(lang, cast["transformed"])
    if cast.get("nuclear"):
        sonuç["nuclear"] = localize_hexagram(lang, cast["nuclear"])
    # Gün bağlamı (İ2): sütun etiketleri dilden bağımsız; yalnız Day
    # Master ilişki adları çevrilir.
    baglam = cast.get("context")
    if baglam:
        sonuç["context"] = {
            **baglam,
            "trigram_relation_names": {
                konum: p.ELEMENT_RELATION_NAMES.get(rel, rel)
                for konum, rel in
                (baglam.get("trigram_relations") or {}).items()},
        }
    # Liu Yao (İ3): akraba adları isteğin dilinde eklenir.
    liu_yao = cast.get("liu_yao")
    if liu_yao:
        sonuç["liu_yao"] = {
            **liu_yao,
            "lines": [
                {**c,
                 "relative_name": p.LIU_QIN_NAMES.get(
                     c.get("relative") or "", c.get("relative") or "")}
                for c in (liu_yao.get("lines") or [])
            ],
        }
    return sonuç


def _disclosure_texts(lang: str | None, chart: dict) -> list[str]:
    """Beyan anahtarlarını isteğin dilinde cümleye çevirir.

    Bazı beyanlar biçim alanı taşır (``{city}`` — hangi şehre kuruldu,
    ``{birth_city}`` — doğum yeri): sabit metin yetmez, değeri yükün
    kendisinden gelir. BaZi'nin `BAZI_TST_NOTE` deseninin aynısı, tablo
    tarafında.

    Doğum şehri yükte yoksa (eski önbellek kayıtları) alan boş kalır ve
    metin yine kurulur — beyan hiçbir koşulda ``{birth_city}`` diye ham
    görünmez.
    """
    p = get(lang)
    yer = chart.get("location") or {}
    alanlar = {"city": yer.get("city") or "",
               "birth_city": yer.get("birth_city") or ""}
    metinler = []
    for anahtar in chart.get("disclosures") or []:
        ham = p.ASTRO_NOTES.get(anahtar, anahtar)
        for alan, deger in alanlar.items():
            ham = ham.replace("{" + alan + "}", deger)
        metinler.append(ham)
    return metinler


def localize_chart(lang: str | None, chart: dict | None) -> dict:
    """Natal haritadaki nokta ve açı adlarını isteğin diline çevirir.

    astro_service her ikisini de döndürüyor (``name`` / ``name_tr``); rapor
    katmanı koşulsuz Türkçe olanı seçtiği için İngilizce prompt'a Türkçe
    gezegen ve burç adları giriyordu.
    """
    if not chart:
        return {}

    def nokta(pt: dict) -> dict:
        return {**pt,
                "name_local": planet_name(lang, pt.get("name")),
                "sign_local": sign_name_from_code(lang, pt.get("sign"))}

    def açı(a: dict) -> dict:
        p = get(lang)
        hareket = a.get("movement")
        return {**a,
                "p1_local": planet_name(lang, a.get("p1")),
                "p2_local": planet_name(lang, a.get("p2")),
                "aspect_local": aspect_name(lang, a.get("aspect")),
                "movement_local": (p.MOVEMENT_NAMES.get(hareket)
                                   if hareket else None)}

    sonuç = {**chart,
             "points": [nokta(p) for p in (chart.get("points") or [])],
             "aspects": [açı(a) for a in (chart.get("aspects") or [])]}

    # Deklinasyon paralelleri (T4): tür anahtarı burada ada çözülür.
    dekl = chart.get("declination_aspects")
    if dekl:
        p = get(lang)
        sonuç["declination_aspects"] = [
            {**d,
             "p1_local": planet_name(lang, d.get("p1")),
             "p2_local": planet_name(lang, d.get("p2")),
             "type_local": p.DECLINATION_ASPECT_NAMES.get(d.get("type"),
                                                          d.get("type"))}
            for d in dekl]

    # Beyanlar (T0): motor anahtar döner, metin burada çözülür — BaZi'nin
    # note_keys deseni. Mobil doğrudan bu metin listesini basar.
    if chart.get("disclosures"):
        sonuç["disclosure_texts"] = _disclosure_texts(lang, chart)

    # Solar return alanları (T5): mobil ekran kod değil ad basar.
    if chart.get("sr_ascendant"):
        sonuç["sr_ascendant"] = {
            **chart["sr_ascendant"],
            "sign_local": sign_name_from_code(
                lang, chart["sr_ascendant"].get("sign"))}
    if chart.get("sr_moon_sign"):
        sonuç["sr_moon_local"] = sign_name_from_code(
            lang, chart["sr_moon_sign"])

    # ``sun_sign`` / ``moon_sign`` / ``ascendant`` alanlarına DOKUNULMAZ:
    # onboarding bu değerleri Firestore profiline yazıyor ve mobil tarafta
    # burç eşleştirmesi ("Kova ♒") bu biçime bağlı. Biçimi değiştirmek eski
    # profillerle yenileri uyumsuz hale getirirdi. Yerelleştirilmiş karşılık
    # ayrı bir alanda döner.
    for alan, kaynak in (("sun_sign_local", "sun"), ("moon_sign_local", "moon"),
                         ("ascendant_local", "asc")):
        kod = (chart.get(kaynak) or {}).get("sign")
        if kod:
            sonuç[alan] = sign_name_from_code(lang, kod)
    return sonuç


def localize_progressions(lang: str | None, prog: dict | None,
                          hits: list[dict] | None = None) -> dict:
    """Progresyon çıktısını (T2) isteğin diline çevirir.

    Motor anahtar üretir (kerykeion burç kodu, sky ile ortak lunasyon evre
    anahtarı, PLANET_NAMES biçiminde nokta adları); ad ve beyan cümlesi
    burada kurulur. Mobil İç Takvim ekranı da bu alanları basar.
    """
    if not prog:
        return {}
    p = get(lang)

    def burçlu(alan: dict | None) -> dict | None:
        if not alan:
            return None
        return {**alan,
                "sign_local": sign_name_from_code(lang, alan.get("sign"))}

    sonuç = {**prog,
             "prog_moon": burçlu(prog.get("prog_moon")),
             "prog_sun": burçlu(prog.get("prog_sun"))}
    if sonuç["prog_moon"] and prog["prog_moon"].get("phase"):
        sonuç["prog_moon"]["phase_local"] = moon_phase_name(
            lang, prog["prog_moon"]["phase"])
    for alan in ("prog_asc", "prog_mc"):
        if prog.get(alan):
            sonuç[alan] = burçlu(prog[alan])

    if prog.get("disclosures"):
        sonuç["disclosure_texts"] = _disclosure_texts(lang, prog)

    if hits is not None:
        sonuç["solar_arc_hits"] = [
            {**h,
             "directed_local": planet_name(lang, h.get("directed")),
             "natal_local": planet_name(lang, h.get("natal")),
             "aspect_local": aspect_name(lang, h.get("aspect"))}
            for h in hits
        ]
    return sonuç


def localize_transit_calendar(lang: str | None, cal: dict | None) -> dict:
    """Transit takvimini (T3) isteğin diline çevirir.

    Takvim paylaşımlı önbellekten dilden bağımsız anahtarlarla gelir;
    olay/nokta/açı adları yanıt üretilirken burada kurulur.
    """
    if not cal:
        return {}
    p = get(lang)

    def olay(o: dict) -> dict:
        sonuç = {**o,
                 "type_local": p.TRANSIT_EVENT_NAMES.get(o.get("type"),
                                                         o.get("type")),
                 "transit_local": planet_name(lang, o.get("transit"))}
        if o.get("natal"):
            sonuç["natal_local"] = planet_name(lang, o["natal"])
        if o.get("aspect"):
            sonuç["aspect_local"] = aspect_name(lang, o["aspect"])
        if o.get("date"):
            sonuç["date_local"] = signal_date(lang, o["date"])
        # R2-Z1: tema/ton taşıyan kesinleşme olayı "Bu tarih neden önemli?"
        # sayfasını sinyal kartlarıyla AYNI dille doldurur: gündelik cümle
        # + teknik dayanak satırı.
        #
        # KESİNLEŞME olaylarının `line`ı burada ÜRETİLMEZ (Ç-turu).
        # Eskiden tema×ton sabit bir 12 cümlelik tabloya
        # (`SIGNAL_HUMAN_LINES`) bakıyordu ve birçok farklı astrolojik
        # olay birebir aynı cümleye düşüyordu (ölçüldü: bir günde üç ayrı
        # olay aynı cümleyi üç kez gösterdi). Yorum artık
        # `api/astrology.py`'de abone için `calendar_insights` ile
        # ÖNCEDEN üretilip olaya `o["line"]` olarak yazılıyor; burası
        # yalnız OLDUĞU GİBİ taşır. Üretilmediyse (ücretsiz kullanıcı ya
        # da AI biçimi tutturamadıysa) boş kalır — mobil bu durumda kendi
        # teknik dayanak yedeğini gösterir (`calendar_strip.dart`).
        #
        # ⚠️ Bu gerekçe YALNIZ kesinleşmeler için geçerli. İSTASYONLARIN
        # `line`ı aşağıdaki dalda BURADA kurulur ve kurulması gerekir:
        # `calendar_insights` LLM'e yalnız `aspect_exact` + temalı
        # olayları veriyor, yani istasyon hiçbir katmanda LLM cümlesi
        # ALMAZ — üzerine yazma riski de yok.
        if o.get("theme") and o.get("tone"):
            sonuç["theme_local"] = p.SIGNAL_THEME_NAMES.get(o["theme"],
                                                            o["theme"])
            sonuç["line"] = o.get("line", "")
            sonuç["technical"] = p.SIGNAL_LINE_EXACT.format(
                transit=sonuç["transit_local"],
                natal=sonuç.get("natal_local", ""),
                aspect=sonuç.get("aspect_local", ""),
                orb=o.get("orb"),
                date=sonuç.get("date_local", o.get("date")))
            if o.get("natal_sign"):
                sonuç["natal_sign_local"] = sign_name(lang, o["natal_sign"])
        elif str(o.get("type") or "").startswith("station"):
            # OP2-turu: istasyon satırı bir ADLANDIRMAYDI, okuma değildi.
            # Cihazda gün sayfasında tek satır "Plüton — ileri harekete
            # dönüş" yazıyordu; sahip "bu ne demek, ne getirip ne
            # götürüyor" diye sordu ve cevap üründe HİÇBİR YERDE yoktu.
            #
            # Anlam SABİT TABLODAN kurulur — LLM yok, jeton yok (emsal:
            # `atlas_detail_screens.dart` gezegen rolü × ev alanı).
            # `signal_service.enrich_events` istasyona TEMA VERMİYOR ve
            # vermemeli: istasyon kişisel bir natal noktaya bağlanmıyor.
            # Burada üretilen cümle de bu yüzden KİŞİSEL DEĞİL —
            # gezegenin kendi doğası ve yönünün evresi anlatılır, kullanıcı
            # anlatılmaz. Kişiye özel olmadığı için `locked` da konmaz:
            # paylaşımlı bir olgu, ücretsiz katmanda da görünür.
            #
            # Yön evresi tabloda yoksa cümle HİÇ yazılmaz. Olay türünü
            # tanımadan "istasyon işte" diye genel bir cümle basmak
            # ölçülmeyeni söylemek olurdu; mobil o durumda kendi teknik
            # dayanak yedeğini gösterir.
            evre = p.STATION_PHASE_LINES.get(o.get("type"))
            tema = p.STATION_PLANET_THEMES.get(o.get("transit"))
            if evre and tema:
                sonuç["line"] = evre.format(
                    transit=sonuç["transit_local"], theme=tema)
                sonuç["technical"] = p.STATION_LINE_TECHNICAL.format(
                    transit=sonuç["transit_local"],
                    date=sonuç.get("date_local", o.get("date")),
                    event=sonuç["type_local"])
        return sonuç

    sonuç = {**cal,
             "events": [olay(o) for o in (cal.get("events") or [])],
             "active_now": [
                 {**a,
                  "transit_local": planet_name(lang, a.get("transit")),
                  "natal_local": planet_name(lang, a.get("natal")),
                  "aspect_local": aspect_name(lang, a.get("aspect")),
                  "movement_local": p.MOVEMENT_NAMES.get(
                      a.get("movement"), a.get("movement"))}
                 for a in (cal.get("active_now") or [])]}
    if cal.get("disclosures"):
        sonuç["disclosure_texts"] = _disclosure_texts(lang, cal)
    return sonuç


def signal_date(lang: str | None, iso: str | None) -> str:
    """ISO tarihi insan diliyle yazar ("2026-08-18" -> "18 Ağustos")."""
    if not iso:
        return ""
    p = get(lang)
    try:
        yil, ay, gun = (int(x) for x in iso.split("-"))
    except ValueError:
        return iso
    return p.SIGNAL_DATE_FMT.format(day=gun,
                                    month=p.MONTH_NAMES.get(ay, ay))


def localize_signals(lang: str | None, data: dict | None) -> dict:
    """Sinyalleri (R2-S1) isteğin diline çevirir ve başlık cümlesini kurar.

    Başlık ŞABLONDUR: her alanı ölçülmüş veriden gelir, LLM'siz üretilir ve
    her katmana açıktır. AI yorumu (``insight``) varsa olduğu gibi taşınır
    (KA-turu'ndan beri her katmana üretilir, yalnız aboneye değil).
    """
    if not data:
        return {}
    p = get(lang)

    def sinyal(s: dict) -> dict:
        alanlar = {
            "transit": planet_name(lang, s.get("transit")),
            "natal": planet_name(lang, s.get("natal")),
            "aspect": aspect_name(lang, s.get("aspect")),
            "orb": s.get("orb"),
            "date": signal_date(lang, s.get("exact_on")),
        }
        # TEKNİK satır: dayanak sayfasının ilk cümlesi (kart yüzeyinde DEĞİL).
        gunler = s.get("days_to_exact")
        if s.get("exact_on") and gunler == 0:
            teknik = p.SIGNAL_LINE_EXACT_TODAY.format(**alanlar)
        elif s.get("exact_on") and isinstance(gunler, int) and gunler >= 1:
            # OT1.4: geri sayımlı biçim — {days} her gün azaldığı için bu
            # satır yedek olarak bildirime düştüğünde bile günlük değişir.
            teknik = p.SIGNAL_LINE_EXACT_SOON.format(**alanlar, days=gunler)
        elif s.get("exact_on"):
            teknik = p.SIGNAL_LINE_EXACT.format(**alanlar)
        elif s.get("movement") == "applying":
            teknik = p.SIGNAL_LINE_APPLYING.format(**alanlar)
        elif s.get("movement") == "separating":
            teknik = p.SIGNAL_LINE_SEPARATING.format(**alanlar)
        else:
            teknik = p.SIGNAL_LINE_ACTIVE.format(**alanlar)

        # KART cümlesi: AI yorumu (`insight`) İSTEMCİDE tercih edilir;
        # `headline` yalnız yorumun bulunmadığı ana (nadir biçim hatası,
        # kısa-TTL penceresi) düşülen SON ÇARE metnidir.
        #
        # KA-turu: buradaki tema×ton sabit tablosu (`SIGNAL_HUMAN_LINES`)
        # SİLİNDİ. Cihazda ölçülen kusur: aynı ekranda iki ÖZDEŞ kart,
        # biri "güçleniyor" biri "sönüyor" etiketiyle; sabah bildirimi de
        # aynı tabloyu kullandığı için herkese haftalarca aynı cümle
        # gitti. Kullanıcı kararıyla yorum artık HERKESE kişi başı AI
        # (`signal_service.insight_bundle`); son çare hazır cümle değil
        # DÜRÜST teknik satır — ölçülmüş veridir, uydurma değil.
        insan = teknik

        # ZAMANLAMA satırı — kartın altındaki küçük çizgi.
        if s.get("exact_on") and s.get("days_to_exact") == 0:
            zaman = p.SIGNAL_TIMING_TODAY
        elif s.get("exact_on"):
            zaman = p.SIGNAL_TIMING_FUTURE.format(date=alanlar["date"])
        elif s.get("movement") == "applying":
            zaman = p.SIGNAL_TIMING_APPLYING
        elif s.get("movement") == "separating":
            zaman = p.SIGNAL_TIMING_SEPARATING
        else:
            zaman = p.SIGNAL_TIMING_ACTIVE

        sonuç = {**s,
                 "headline": insan,
                 "technical": teknik,
                 "timing_local": zaman,
                 "transit_local": alanlar["transit"],
                 "natal_local": alanlar["natal"],
                 "aspect_local": alanlar["aspect"],
                 "theme_local": p.SIGNAL_THEME_NAMES.get(s.get("theme"),
                                                         s.get("theme")),
                 "movement_local": p.MOVEMENT_NAMES.get(s.get("movement"),
                                                        s.get("movement"))}
        if s.get("exact_on"):
            sonuç["exact_on_local"] = alanlar["date"]
        if s.get("natal_sign"):
            sonuç["natal_sign_local"] = sign_name(lang, s["natal_sign"])
        return sonuç

    sonuç = {**data,
             "signals": [sinyal(s) for s in (data.get("signals") or [])]}
    if data.get("disclosures"):
        sonuç["disclosure_texts"] = _disclosure_texts(lang, data)
    return sonuç


def relation_label(lang: str | None, relation: str | None) -> str:
    """Eklenen kişinin ilişki etiketi ("eşin" / "your partner").

    Sunucu bu kişilerin gerçek adını bilmiyor (etiket cihazda kalır), bu
    yüzden prompt'ta ve fısıltıda geçen ad budur.
    """
    p = get(lang)
    return p.RELATION_LABELS.get(relation or "other",
                                 p.RELATION_LABELS["other"])


def relation_frame(lang: str | None, relation: str | None) -> str:
    """İlişki türünün AI'ya verdiği çerçeve kısıtı; yoksa boş string."""
    if not relation:
        return ""
    return get(lang).RELATION_FRAME.get(relation, "")


def axis_name(lang: str | None, axis: str | None,
              relation: str | None = None) -> str:
    """Eksenin gösterilecek adı — ilişki türü onu değiştiriyorsa değişmiş
    hâliyle.

    Ölçüm türden ETKİLENMEZ; değişen yalnız ad (bkz. RELATION_AXIS_NAMES).
    "Çocuğunuzla çekim: güçlü" yazmak ölçümü doğru ama sunumu yanlış
    yapmak olurdu.
    """
    p = get(lang)
    if relation:
        ozel = p.RELATION_AXIS_NAMES.get(relation) or {}
        if axis in ozel:
            return ozel[axis]
    return p.SYNASTRY_AXIS_NAMES.get(axis, axis)


def localize_relationship_axes(lang: str | None, data: dict | None,
                               relation: str | None = None) -> dict:
    """İlişki eksenlerini (R2-L1) isteğin diline çevirir.

    Sayısal uyum puanı YOK: seviye adı, ton adı ve dayanak açılar
    (gerçek gezegenler + ölçülen orb) taşınır.

    **Hazır cümle YOK** (1.6.0). Eskiden her eksene `SYNASTRY_AXIS_LINES`
    tablosundan bir cümle iliştiriliyordu; tablo yalnız eksen × ton ile
    anahtarlıydı ve tüm üründe 16 cümle vardı. Ölçüldü: 15 çiftin 15'i
    farklı ölçüm üretiyordu ama yalnız 12'si farklı metin görüyordu — üç
    çift dört cümlenin dördünü de birebir aynı okuyordu. Yorumu artık
    ölçümden AI yazıyor (`report_service.relationship_reading`); bu
    fonksiyon yalnız ÖLÇÜMÜ dile çevirir.
    """
    if not data:
        return {}
    p = get(lang)

    def eksen(e: dict) -> dict:
        anahtar = e.get("axis")
        seviye = e.get("level") or "quiet"
        ton = e.get("tone") or "quiet"
        return {**e,
                # Eksen adı ilişki türüne göre değişebilir (P-turu);
                # seviye/ton ve dayanak açılar DEĞİŞMEZ.
                "axis_local": axis_name(lang, anahtar, relation),
                "level_local": p.SYNASTRY_LEVEL_NAMES.get(seviye, seviye),
                "tone_local": p.SYNASTRY_TONE_NAMES.get(ton, ton),
                "basis": [
                    {**b,
                     "p1_local": planet_name(lang, b.get("p1")),
                     "p2_local": planet_name(lang, b.get("p2")),
                     "aspect_local": aspect_name(lang, b.get("aspect"))}
                    for b in (e.get("basis") or [])
                ]}

    sonuc = {**data,
             "axes": [eksen(e) for e in (data.get("axes") or [])],
             "footnote": p.SYNASTRY_FOOTNOTE}
    # Saatsizlik beyanı (1.7.0): taraflardan birinin doğum saati yoksa
    # Yükselen/MC temasları hesaba girmedi ve bu SÖYLENİR.
    if data.get("disclosures"):
        sonuc["disclosure_texts"] = _disclosure_texts(lang, data)
    return sonuc


#: Destekleyici sayılan açılar — şeritteki renklendirme dayanak
#: satırlarının idiomunu izler (lilac/copper).
_SUPPORTIVE_ASPECTS = frozenset(("conjunction", "trine", "sextile"))


def localize_pair_transits(lang: str | None, data: dict | None,
                           other_label: str) -> dict:
    """Çift-transit ölçümünü (GT-turu) isteğin diline çevirir.

    Her vuruş hem alanlarıyla hem hazır `text` satırıyla döner; mobil
    şerit sunucu metnini olduğu gibi çizer (yan etiketi kişi yolunda
    ilişki etiketidir — gerçek ad sunucuda yok).
    """
    if not data:
        return {}
    p = get(lang)

    def vurus(v: dict) -> dict:
        yan = (p.PAIR_SIDE_SELF if v.get("side") == "user"
               else p.PAIR_SIDE_OTHER_FMT.format(label=other_label))
        hareket = v.get("movement")
        hareket_yerel = p.MOVEMENT_NAMES.get(hareket, "") if hareket else ""
        return {**v,
                "side_label": yan,
                "transit_local": planet_name(lang, v.get("transit")),
                "natal_local": planet_name(lang, v.get("natal")),
                "aspect_local": aspect_name(lang, v.get("aspect")),
                "movement_local": hareket_yerel,
                "supportive": v.get("aspect") in _SUPPORTIVE_ASPECTS,
                "text": p.PAIR_TRANSIT_FMT.format(
                    side=yan,
                    transit=planet_name(lang, v.get("transit")),
                    natal=planet_name(lang, v.get("natal")),
                    aspect=aspect_name(lang, v.get("aspect")),
                    orb=v.get("orb"),
                    movement=f", {hareket_yerel}" if hareket_yerel else "")}

    return {"date": data.get("date"),
            "hits": [vurus(v) for v in (data.get("hits") or [])]}


def localize_synastry(lang: str | None, synastry: dict | None) -> dict:
    """Sinastri çıktısındaki iki kişinin nokta adlarını ve açıları çevirir."""
    if not synastry:
        return {}

    def kişi(p: dict | None) -> dict:
        if not p:
            return {}
        çevrilmiş = dict(p)
        for alan in ("sun", "moon", "ascendant", "asc"):
            nokta = p.get(alan)
            if isinstance(nokta, dict):
                çevrilmiş[alan] = {**nokta,
                                   "sign_local": sign_from_point(lang, nokta)}
        return çevrilmiş

    # HA9: sinastri çarkı için tam nokta/ev listeleri de çevrilir (ek
    # anahtarlar; yoksa boş liste — eski yükler etkilenmez).
    def nokta(pt: dict) -> dict:
        return {**pt,
                "name_local": planet_name(lang, pt.get("name")),
                "sign_local": sign_name_from_code(lang, pt.get("sign"))}

    return {
        **synastry,
        "person1": kişi(synastry.get("person1")),
        "person2": kişi(synastry.get("person2")),
        "points1": [nokta(p) for p in (synastry.get("points1") or [])],
        "points2": [nokta(p) for p in (synastry.get("points2") or [])],
        "aspects": [
            {**a,
             "p1_local": planet_name(lang, a.get("p1")),
             "p2_local": planet_name(lang, a.get("p2")),
             "aspect_local": aspect_name(lang, a.get("aspect"))}
            for a in (synastry.get("aspects") or [])
        ],
    }


def localize_transits(lang: str | None, data: dict | None) -> dict:
    """Transit yükünü çevirir (HA8) — HA1 sözleşmesi: kararlı anahtarlar
    korunur, çeviri ``*_local`` alanlarına EKLENİR.

    `/astrology/transits` bugüne dek yerelleştirmesizdi çünkü mobil
    tüketicisi yoktu; bi-wheel'in natal↔transit çapraz açıları bu uca
    bağlanınca (Harita İnceleme) çeviri sözleşmesi de gerekti.
    """
    if not data:
        return {}
    p = get(lang)

    def nokta(pt: dict) -> dict:
        return {**pt,
                "name_local": planet_name(lang, pt.get("name")),
                "sign_local": sign_name_from_code(lang, pt.get("sign"))}

    def açı(a: dict) -> dict:
        hareket = a.get("movement")
        return {**a,
                "p1_local": planet_name(lang, a.get("p1")),
                "p2_local": planet_name(lang, a.get("p2")),
                "aspect_local": aspect_name(lang, a.get("aspect")),
                "movement_local": (p.MOVEMENT_NAMES.get(hareket)
                                   if hareket else None)}

    return {
        **data,
        "transiting_points": [nokta(pt)
                              for pt in (data.get("transiting_points") or [])],
        "aspects_to_natal": [açı(a)
                             for a in (data.get("aspects_to_natal") or [])],
    }


def localize_sky(lang: str | None, sky: dict | None) -> dict:
    """Gökyüzü yükünü isteğin diline çevirir.

    Hesap dilden bağımsızdır ve paylaşımlı önbellekten servis edilir; bu
    yüzden retro listesi, açılar ve ay evresi anahtar taşır. Çeviri **yanıt
    üretilirken** yapılır — aksi halde önbelleği ilk dolduran dil herkese
    servis edilirdi (İngilizce kullanıcı "Satürn retro" görüyordu).

    HA1 (canlı hata onarımı): açıların ``p1/p2/aspect`` anahtarları artık
    ÜZERİNE YAZILMAZ — kararlı (İngilizce/küçük-harf) kalır ve
    ``p1_local/p2_local/aspect_local`` EKLENİR (localize_chart deseni).
    Eski davranış gökyüzü çarkının açı ağını öldürüyordu: mobil,
    ``planets[].name`` (İngilizce) ile açı uçlarını eşleyemiyor ve TR'de
    SIFIR açı çizgisi çiziyordu; EN'de "Conjunction" küçük-harf renk
    tablosunu ıskalayıp görünmez renge düşüyordu.
    """
    if not sky:
        return {}
    return {
        **sky,
        "moon_phase": localize_moon_phase(lang, sky.get("moon_phase")),
        "planets": [
            {**gezegen,
             "name_local": planet_name(lang, gezegen.get("name")),
             "sign_local": sign_name(lang, gezegen.get("sign"))}
            for gezegen in (sky.get("planets") or [])
        ],
        "retrogrades": [planet_name(lang, p)
                        for p in (sky.get("retrogrades") or [])],
        "aspects": [
            {**a,
             "p1_local": planet_name(lang, a.get("p1")),
             "p2_local": planet_name(lang, a.get("p2")),
             "aspect_local": aspect_name(lang, a.get("aspect"))}
            for a in (sky.get("aspects") or [])
        ],
    }

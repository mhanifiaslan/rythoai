"""Harita derinligi — sohbete giden harita blogunun davranisi.

Bu katmanin degeri iki seye bagli: cevabin gercekten spesifik olmasi (yani
blokta ev, aci ve transit bulunmasi) ve bunu yaparken ham dogum verisini
disari sizdirmamasi. Testler agirlikli olarak bu iki degismezi korur.

Calistirma:  .venv\\Scripts\\python.exe -m pytest tests/test_chart_context.py -q
"""
from __future__ import annotations

import datetime as dt

import pytest

from services import chart_context, prompts

DOGUM = dict(name="Test", year=1990, month=8, day=14, hour=7, minute=35,
             city="Istanbul", nation="TR")

PROFIL = {
    "displayName": "Test",
    "birthDate": "1990-08-14",
    "birthTime": "07:35",
    "birthCity": "Istanbul",
    "birthNation": "TR",
    "sunSign": "Aslan ♌",
}


@pytest.fixture
def temiz_onbellek(tmp_path, monkeypatch):
    from core import cache, config
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    yield
    cache._memory.clear()


# --------------------------------------------------------------------------
# Dogum verisi kapisi — uydurma harita uretilmemeli
# --------------------------------------------------------------------------

def test_dogum_verisi_eksikse_derinlik_uretilmez():
    """`birth_kwargs` eksik alani sessizce 2000-01-01/Istanbul'a cevirir.

    O varsayilanla hesaplanan haritayi "senin haritan" diye sunmak veri
    uydurmaktir; kapi tam da bunu engeller.
    """
    assert chart_context.has_birth_data(PROFIL)
    assert not chart_context.has_birth_data(None)
    assert not chart_context.has_birth_data({})
    assert not chart_context.has_birth_data({"birthCity": "Istanbul"})
    assert not chart_context.has_birth_data({"birthDate": "1990-08-14"})
    assert not chart_context.has_birth_data(
        {"birthDate": "  ", "birthCity": "Istanbul"})


def test_dogum_verisi_yoksa_sig_ozete_dusulur(temiz_onbellek):
    """Sohbet hicbir kosulda haritasiz kalmaz."""
    sig_profil = {"sunSign": "Aslan ♌", "moonSign": "Kova ♒"}
    blok = chart_context.chart_whisper("u-yok", sig_profil, lang="tr")
    assert "Aslan" in blok
    # Sig ozette ev/aci/transit bulunmaz.
    assert "ev" not in blok


# --------------------------------------------------------------------------
# Ev numarasi — kerykeion metin donduruyor, sayiya cevrilmezse sessizce kaybolur
# --------------------------------------------------------------------------

def test_ev_adi_sayiya_cevrilir():
    """Regresyon: kerykeion ``"Twelfth_House"`` donduruyor, tamsayi degil.

    Cevrilmedigi surece hem ev satiri hem yigilma sayimi sessizce bos
    kaliyordu — hata yok, sadece derinlik yok.
    """
    assert chart_context._house_number("First_House") == 1
    assert chart_context._house_number("Twelfth_House") == 12
    assert chart_context._house_number(7) == 7
    assert chart_context._house_number("Onucuncu_Ev") is None
    assert chart_context._house_number(None) is None
    assert chart_context._house_number(13) is None


# --------------------------------------------------------------------------
# Olgu cikarimi
# --------------------------------------------------------------------------

@pytest.fixture(scope="module")
def olgular():
    return chart_context.natal_facts(DOGUM)


def test_dis_gezegenler_ve_derece_yerlesimde(olgular):
    """Denetim: Uranüs/Neptün/Plüton yalnız transitte kalırsa sohbet sığ kalır."""
    adlar = [y["planet"] for y in olgular["placements"]]
    assert adlar == list(chart_context._PLACEMENT_POINTS)
    assert {"Uranus", "Neptune", "Pluto"} <= set(adlar)
    assert all(y.get("position") is not None for y in olgular["placements"])
    blok = chart_context.render(olgular, lang="tr")
    assert "°" in blok


def test_gezegenler_eve_yerlesir(olgular):
    assert olgular["sun"]["house"] in range(1, 13)
    assert olgular["moon"]["house"] in range(1, 13)
    assert olgular["ascendant"]
    yerlesimler = olgular["placements"]
    assert [y["planet"] for y in yerlesimler] == list(
        chart_context._PLACEMENT_POINTS)
    assert all(y["house"] in range(1, 13) for y in yerlesimler)


def test_saat_yoksa_yukselen_ve_ev_uydurulmaz(temiz_onbellek):
    """Noon dolgusu 'senin yükselenin' diye fısıltıya girmez."""
    from services import profile_service

    profil = {k: v for k, v in PROFIL.items() if k != "birthTime"}
    olgular = chart_context.natal_facts(profile_service.birth_kwargs(profil))
    assert olgular["ascendant"] is None
    assert olgular["hour_known"] is False
    assert all(y.get("house") is None for y in olgular["placements"])
    blok = chart_context.chart_whisper("u-saat", profil, lang="tr")
    assert "Yükselen" not in blok
    assert ". ev" not in blok


def test_denge_sayimlari_yedi_gezegen_arti_yukselen(olgular):
    """Geleneksel yedili + Yukselen = 8. Yukselen'i katmak yaygin pratik ve
    eksik elementi daha dogru gosterir."""
    assert sum(olgular["elements"].values()) == 8
    assert sum(olgular["modalities"].values()) == 8
    assert set(olgular["elements"]) == {"fire", "earth", "air", "water"}
    assert set(olgular["modalities"]) == {"cardinal", "fixed", "mutable"}


def test_eksik_element_sifir_olarak_kalir(olgular):
    """Sifir sayim listeden dusurulmez: 'haritanda hic hava yok' astrolojik
    olarak anlamli bir ifade, kaybolmamali."""
    assert all(isinstance(v, int) for v in olgular["elements"].values())
    blok = chart_context.render(olgular, lang="tr")
    assert "Hava 0" in blok  # bu dogum haritasinda hava elementi yok


def test_acilar_orb_sirasinda_ve_majör(olgular):
    acilar = olgular["aspects"]
    assert acilar, "Bu haritada hic majör aci cikmadi — filtre fazla dar"
    assert len(acilar) <= chart_context._MAX_NATAL_ASPECTS
    assert acilar == sorted(acilar, key=lambda a: a["orb"])
    assert all(a["aspect"] in chart_context._MAJOR_ASPECTS for a in acilar)


def test_yukselen_mc_acisi_listeye_girmez(olgular):
    """Yukselen ile MC arasindaki mesafe dogum ENLEMININ sonucu; kisiye dair
    bir sey soylemez. Dar orb'u sayesinde gercek bir acinin yerini aliyordu."""
    for a in olgular["aspects"]:
        assert not (a["p1"] in chart_context._ANGLES
                    and a["p2"] in chart_context._ANGLES)


# --------------------------------------------------------------------------
# Transitler
# --------------------------------------------------------------------------

def test_gezen_ay_transit_listesine_girmez():
    """Ay gunde ~13° yol alir; gunluk onbellekli bir listede sabah hesaplanan
    Ay acisi aksama yanlis olur. Ay'in bugunku hali zaten gokyuzu fisiltisinda
    evresiyle geciyor."""
    assert "Moon" not in chart_context._TRANSIT_MOVERS
    vurus = chart_context.transit_facts(DOGUM)["hits"]
    assert all(v["transit"] != "Moon" for v in vurus)


def test_transitler_once_yavas_gezenleri_gosterir():
    """Salt orb siralamasi listeyi her gun Merkur'e boguyordu: Merkur gunde
    ~1° yol aldigi icin daima birine cok dar bir aci yapar. Donemi isaretleyen
    ise aylarca ayni noktada duran Saturn/Pluton."""
    ham = [
        {"p1": "Mercury", "p2": "Sun", "aspect": "trine", "orbit": 0.05},
        {"p1": "Saturn", "p2": "Moon", "aspect": "square", "orbit": 2.4},
        {"p1": "Venus", "p2": "Mars", "aspect": "sextile", "orbit": 0.3},
        {"p1": "Pluto", "p2": "Sun", "aspect": "conjunction", "orbit": 1.1},
    ]
    import services.astro_service as astro
    eski = astro.get_transits
    astro.get_transits = lambda **k: {"aspects_to_natal": ham}
    try:
        vurus = chart_context.transit_facts(DOGUM)["hits"]
    finally:
        astro.get_transits = eski

    assert [v["transit"] for v in vurus] == [
        "Pluto", "Saturn", "Mercury", "Venus"]


def test_genis_orb_transitleri_elenir():
    ham = [{"p1": "Saturn", "p2": "Sun", "aspect": "square", "orbit": 5.0}]
    import services.astro_service as astro
    eski = astro.get_transits
    astro.get_transits = lambda **k: {"aspects_to_natal": ham}
    try:
        assert chart_context.transit_facts(DOGUM)["hits"] == []
    finally:
        astro.get_transits = eski


# --------------------------------------------------------------------------
# Gizlilik — en onemli degismez
# --------------------------------------------------------------------------

def test_ham_dogum_verisi_bloga_girmez(temiz_onbellek):
    """Modele yalnizca TURETILMIS konumlar verilir.

    Dogum tarihi + saati + yeri kimlik dogrulama sorularinda kullanilan hassas
    bir uclu; prompt'a girmesi icin hicbir sebep yok, ciktiya sizmasi icin
    her sebep var (model onu kullaniciya tekrarlayabilir).
    """
    blok = chart_context.chart_whisper("u-gizlilik", PROFIL, lang="tr")
    for yasak in ("1990", "08-14", "07:35", "Istanbul", "TR"):
        assert yasak not in blok, f"Ham dogum verisi bloga sizdi: {yasak}"


def test_onbellek_anahtari_ham_dogum_verisi_tasimaz():
    """Anahtar da veri: onbellek anahtarlari loglanabilir ve dokuman
    kimligine donusur."""
    from services import profile_service

    ozet = chart_context._birth_digest(profile_service.birth_kwargs(PROFIL))
    for yasak in ("1990", "Istanbul", "07", "35"):
        assert yasak not in ozet or len(ozet) == 16
    assert len(ozet) == 16
    assert "Istanbul" not in ozet


def test_isim_degisince_onbellek_bosa_dusmez():
    """Isim haritayi etkilemez; ozete girmemeli."""
    from services import profile_service

    a = profile_service.birth_kwargs(PROFIL)
    b = profile_service.birth_kwargs({**PROFIL, "displayName": "Baska"})
    assert chart_context._birth_digest(a) == chart_context._birth_digest(b)


def test_dogum_verisi_degisince_onbellek_gecersizlesir():
    """Kullanici dogum saatini duzeltirse eski harita gosterilmemeli."""
    from services import profile_service

    a = profile_service.birth_kwargs(PROFIL)
    b = profile_service.birth_kwargs({**PROFIL, "birthTime": "18:00"})
    assert chart_context._birth_digest(a) != chart_context._birth_digest(b)


# --------------------------------------------------------------------------
# Onbellek — efemeris hesabi her sohbet turunda tekrarlanmamali
# --------------------------------------------------------------------------

def test_natal_hesap_bir_kez_yapilir(temiz_onbellek, monkeypatch):
    sayac = {"n": 0}
    gercek = chart_context.natal_facts

    def sayarak(birth):
        sayac["n"] += 1
        return gercek(birth)

    monkeypatch.setattr(chart_context, "natal_facts", sayarak)
    monkeypatch.setattr(chart_context, "transit_facts", lambda b: {"hits": []})

    for _ in range(3):
        chart_context.chart_facts("u-onbellek", PROFIL)
    assert sayac["n"] == 1, "Natal harita her turda yeniden hesaplaniyor"


def test_transit_onbellegi_gunluk(temiz_onbellek, monkeypatch):
    sayac = {"n": 0}
    monkeypatch.setattr(chart_context, "natal_facts", lambda b: {"aspects": []})

    def sayarak(birth):
        sayac["n"] += 1
        return {"hits": []}

    monkeypatch.setattr(chart_context, "transit_facts", sayarak)

    bugun = dt.date(2026, 8, 1)
    chart_context.chart_facts("u-transit", PROFIL, today=bugun)
    chart_context.chart_facts("u-transit", PROFIL, today=bugun)
    assert sayac["n"] == 1

    chart_context.chart_facts("u-transit", PROFIL, today=dt.date(2026, 8, 2))
    assert sayac["n"] == 2, "Yeni gunde transitler yeniden hesaplanmali"


def test_hesap_duserse_sohbet_haritasiz_kalmaz(temiz_onbellek, monkeypatch):
    """Efemeris hesabi patlarsa sig ozete dusulur, istek dusmez."""
    def patla(birth):
        raise RuntimeError("efemeris yok")

    monkeypatch.setattr(chart_context, "natal_facts", patla)
    blok = chart_context.chart_whisper("u-hata", PROFIL, lang="tr")
    assert "Aslan" in blok  # sig ozet devrede


# --------------------------------------------------------------------------
# Blok bicimi
# --------------------------------------------------------------------------

def test_blok_ev_aci_ve_denge_icerir(temiz_onbellek):
    blok = chart_context.chart_whisper("u-bicim", PROFIL, lang="tr")
    assert ". ev" in blok, "Ev yerlesimi bloga girmemis"
    assert "Element dengesi" in blok
    assert "en sıkı açıları" in blok
    assert not any(s.strip() == "-" for s in blok.splitlines())


def test_blok_prompt_butcesini_asmaz(temiz_onbellek):
    """Blok HER sohbet turunda gidiyor; buyumesi dogrudan maliyet demek."""
    blok = chart_context.chart_whisper("u-butce", PROFIL, lang="tr")
    assert len(blok) < 1400, f"Harita blogu {len(blok)} karaktere cikti"


# --------------------------------------------------------------------------
# BaZi fisiltisi (Revize B8)
# --------------------------------------------------------------------------

_BAZI_OLGULAR = {
    "day_master": {"pinyin": "Xin", "element": "metal", "polarity": "Yin"},
    "verdict": "weak",
    "season_state": "si",
    "favorable_elements": ["earth", "metal"],
    "current_luck": {"label": "丙戌 (Bing Xu)", "from_year": 2020,
                     "to_year": 2029, "ten_god": "Zheng Guan"},
    "current_year": {"label": "丙午 (Bing Wu)", "ten_god": "Zheng Guan"},
    "stars": [{"key": "tian_yi", "pillar": "year"}],
    "hour_known": True,
}


def test_bazi_fisiltisi_bicimi_tr():
    blok = chart_context.render_bazi(_BAZI_OLGULAR, lang="tr")
    assert "BaZi Günün Efendisi" in blok
    assert "Zayıf" in blok                      # hüküm adı çevrili
    assert "Da Yun" in blok and "2020-2029" in blok
    assert "Göksel Soylu" in blok               # yıldız adı çevrili


def test_bazi_fisiltisi_ingilizce_turkce_tasimaz():
    blok = chart_context.render_bazi(_BAZI_OLGULAR, lang="en")
    assert "Weak" in blok
    for tr_iz in ("Günün", "Zayıf", "yararlı", "yıl sütunu"):
        assert tr_iz not in blok


def test_bazi_fisiltisi_yalnizca_kapida_acilir(temiz_onbellek, monkeypatch):
    """BaZi ücretli ürün: include_bazi=False iken fısıltıya SIZMAZ.

    Kapı chart_whisper imzasında; sohbet ucu bayrağı abonelikten kurar.
    Sızıntı olursa hata çıkmaz — ücretsiz kullanıcı ücretli veriyi görür.
    """
    monkeypatch.setattr(chart_context, "chart_facts",
                        lambda uid, profile, **kw: {"sun": None, "moon": None,
                                              "placements": [],
                                              "transits": []})
    monkeypatch.setattr(chart_context, "bazi_facts",
                        lambda uid, profile: _BAZI_OLGULAR)

    kapali = chart_context.chart_whisper("u-b8", PROFIL, lang="tr",
                                         include_bazi=False)
    assert "BaZi" not in kapali

    acik = chart_context.chart_whisper("u-b8", PROFIL, lang="tr",
                                       include_bazi=True)
    assert "BaZi Günün Efendisi" in acik


def test_bazi_olgulari_kompakt_ve_ham_dogum_tasimiyor(temiz_onbellek):
    """Fısıltı olgusu her tura girer: küçük kalmalı ve ham doğum verisi
    (tarih/saat/şehir) taşımamalı — gizlilik değişmezi natal fısıltıyla aynı."""
    olgular = chart_context.bazi_facts("u-b8-olgu", PROFIL)
    assert olgular is not None
    assert set(olgular) <= {"day_master", "verdict", "season_state",
                            "favorable_elements", "current_luck",
                            "current_year", "stars", "hour_known"}
    import json
    metin = json.dumps(olgular, ensure_ascii=False)
    assert "07:35" not in metin
    assert "Istanbul" not in metin


# --------------------------------------------------------------------------
# Olgu NOBETCISI: "hesaplamadim" ile "hesapladim, cikmadi" ayni sey degil
# --------------------------------------------------------------------------

def test_olgular_None_GECILIRSE_yeniden_HESAPLANMAZ(temiz_onbellek,
                                                    monkeypatch):
    """`facts=None` GECMEK "hesapla" demek DEGIL, "cikmadi" demek.

    Olculen kusur: iki cagiran da (`api/chat.py`, `api/face_reading.py`)
    olgulari KENDISI uretip geciyor ve gerekcesi yorumlarinda yaziyor —
    "iki ayri cagri iki ayri onbellek turu demek olurdu". Ama efemeris
    dustugunde `chart_facts` None donuyordu ve eski kapi (`if facts is
    None`) onu "verilmedi" sanip AYNI hesabi bir kez daha deniyordu:
    istek basina IKI bosa hesap. `_cached` hata yolunda `cache.set`
    cagirmadigi icin ikinci deneme de onbellekten donmuyor.

    Iki yon birden olculuyor, yoksa bekci kor kalir: nobetci kapiyi
    kilitlediyse olgu HIC verilmeyen cagiranda da hesap yapilmazdi ve
    sohbet kalici olarak sig ozete duserdi.
    """
    sayac = {"n": 0}

    def sahte_olgular(uid, profile, today=None):
        sayac["n"] += 1
        return None

    monkeypatch.setattr(chart_context, "chart_facts", sahte_olgular)

    blok = chart_context.chart_whisper("u-nob-1", PROFIL, lang="tr",
                                       facts=None)
    assert sayac["n"] == 0, (
        "`facts=None` gecilmesine ragmen olgular YENIDEN hesaplandi: "
        "efemeris dustugunde istek basina iki bosa hesap")
    assert "Aslan" in blok, "sig ozete dusulmeliydi"

    # Olgu HIC verilmedi: hesap YAPILMALI (nobetci kapiyi kilitlemedi).
    chart_context.chart_whisper("u-nob-2", PROFIL, lang="tr")
    assert sayac["n"] == 1, (
        "olgu hic verilmediginde de hesap yapilmadi: nobetci kapiyi "
        "kilitlemis, sohbet kalici olarak sig ozete duser")


# --------------------------------------------------------------------------
# Butce: TEK fikstur degil EN KOTU HAL
# --------------------------------------------------------------------------

#: Yigilma UST SINIRI — kaynakta dilim YOK, sayim turetiyor.
#:
#: `chart_facts` yigilmalari `TRADITIONAL + OUTER` (10 nokta) uzerinden
#: sayiyor ve esik `_STELLIUM_MIN`. Hicbir `[:n]` dilimi yok, yani ust
#: sinir aritmetikten gelir: 10 // 3 = 3. Sabit BURADA tanimlanmiyor,
#: kaynaktan TURETILIYOR — elle "2" yazildigi tur en kotu hal eksik
#: olculdu (asagidaki uyari).
_EN_COK_YIGILMA = len(chart_context.TRADITIONAL + chart_context.OUTER) \
    // chart_context._STELLIUM_MIN


def _en_kotu_olgular(lang: str) -> dict:
    """Oge sinirlari TAM DOLU + O DILDE en uzun adlar.

    Blok KARAKTERLE sinirli degil OGE ile sinirli (`_MAX_NATAL_ASPECTS`,
    `_MAX_TRANSITS`, `_PLACEMENT_POINTS`, `_EN_COK_YIGILMA`, iki yaklasan).
    O yuzden en kotu hal HESAPLANABILIR.

    ⚠️ Bu fikstur bir tur boyunca "en uzun secenek" diyor ama IKI yerde
    ALT SINIRIN altini olcuyordu (olculdu 2026-10-03):

      * burc adi elle `"sagittarius"` yazilmisti. EN tarafta dogru
        ("Sagittarius", 11 krk) ama TR tarafta o burcun adi "Yay" (3 krk)
        ve TR'nin en uzunu "Ikizler" (7). Ad 11 yerde geciyor (Gunes, Ay,
        Yukselen + 8 yerlesim), yani TR olcumu ~65 karakter eksikti.
      * "en fazla iki yigilma" deniyordu; kaynakta dilim yok, ucu da
        mumkun (bkz. `_EN_COK_YIGILMA`).

    Ikisi de hukmu degistirmedi (tavan yine asilmiyor) ama BILDIRILEN
    bosluk gercek bosluktan %70 buyuktu — ve bu bekcinin tek isi o
    boslugu dogru bildirmek. Burc adi artik DILIN KENDI tablosundan
    turetiliyor: tabloya daha uzun bir ad girdigi gun fikstur kendini
    guncelliyor.

    Gunes/Ay BILEREK retro DEGIL: gokte olmayan bir hali olcup "en kotu
    hal" demek, olculmeyeni soylemek olurdu. Yerlesimlerin hepsi retro.
    """
    burclar = prompts.get(lang).SIGN_NAMES
    uzun_burc = max(burclar, key=lambda k: len(burclar[k]))
    uzun_cift = ("Medium_Coeli", "True_North_Lunar_Node")
    return {
        "sun": {"planet": "Sun", "sign": uzun_burc, "house": 12,
                "retrograde": False, "position": 29.9},
        "moon": {"planet": "Moon", "sign": uzun_burc, "house": 11,
                 "retrograde": False, "position": 29.9},
        "ascendant": uzun_burc,
        "placements": [{"planet": ad, "sign": uzun_burc, "house": 12,
                        "retrograde": True, "position": 29.9}
                       for ad in chart_context._PLACEMENT_POINTS],
        "elements": {"fire": 4, "earth": 2, "air": 1, "water": 1},
        "modalities": {"cardinal": 4, "fixed": 2, "mutable": 2},
        "stelliums": [{"house": 12 - i, "count": 3}
                      for i in range(_EN_COK_YIGILMA)],
        "aspects": [{"p1": uzun_cift[0], "p2": uzun_cift[1],
                     "aspect": "opposition", "orb": 0.1}
                    for _ in range(chart_context._MAX_NATAL_ASPECTS)],
        "transits": [{"transit": uzun_cift[0], "natal": uzun_cift[1],
                      "aspect": "opposition", "orb": 0.1}
                     for _ in range(chart_context._MAX_TRANSITS)],
        "upcoming": [{"date": "2026-10-07", "transit": uzun_cift[0],
                      "natal": uzun_cift[1], "aspect": "opposition"}
                     for _ in range(2)],
    }


def test_blok_EN_KOTU_HALDE_de_butceyi_asmaz():
    """Ustteki bekci TEK fikstur olcuyor; bu, OGE SINIRLARININ sonucunu.

    Fark neden onemli: `chart_whisper` kaynaginda KARAKTER sinirI almiyor
    ve tavan `prompt_composer.MAX_CHART_CHARS`ta, yani YALNIZ sohbet
    yolunda. Oteki cagiran (`api/face_reading` -> `report_service`)
    composer'dan gecmiyor, dolayisiyla onun tek guvencesi bloğun OGE ile
    sinirli olmasi. Bu bekci o guvenceyi sayiya baglar: bir sonraki tur
    `_MAX_NATAL_ASPECTS`i 6'dan 12'ye cikarirsa ya da yerlesim satirina
    yeni bir alan eklerse burasi kirmizi doner.

    Olculen (2026-10-03, DOGRULAMA turu, fikstur duzeltildikten SONRA):
      * `render(..., include_transits=True)` TR 1296 / EN 1286 karakter —
        yani tavana kalan bosluk 104 / 114, eski olcumun bildirdigi
        169 / 137 DEGIL;
      * `render(..., include_transits=False)` (kalici yari) TR 902 / EN 921;
      * `gunun_gokyuzu` TR 422 / EN 391;
      * firaset prompt'una giren TOPLAM (kalici + gun) TR 1324 / EN 1312.

    ⚠️ Son satir asil olcu: firaset yolunun HIC tavani yok (composer'dan
    gecmiyor) ve en kotu halde 1400'e 76 karakter kaliyor. Bu bekci o
    yuzden kalici + gun toplamini da olcuyor — `render`i tek basina
    olcmek o yolu eksik olcmek olurdu.

    ⚠️ BaZi fisiltisi EKLENDIGINDE tavan ASILIYOR ve bu BILINCLI:
    `include_bazi` yalniz SOHBET yolunda aciliyor ve o yol composer'dan
    geciyor — `prompt_composer._kirp` kirpar ve o dosyanin kendi gerekcesi
    "kirpma, sessiz buyumeye yegdir" diyor. Burada olculen sey
    composer'siz yolun tavani, o yuzden BaZi haric.
    """
    from services import prompt_composer

    for lang in ("tr", "en"):
        kotu = _en_kotu_olgular(lang)
        tam = chart_context.render(kotu, lang=lang)
        kalici = chart_context.render(kotu, lang=lang,
                                      include_transits=False)
        gok = chart_context.gunun_gokyuzu(kotu, lang=lang)
        assert len(tam) < prompt_composer.MAX_CHART_CHARS, (
            f"[{lang}] en kotu halde blok {len(tam)} karakter — tavan "
            f"{prompt_composer.MAX_CHART_CHARS}; composer'dan gecmeyen "
            f"cagiranda kirpilmadan prompt'a girer")
        assert len(kalici) + len(gok) < prompt_composer.MAX_CHART_CHARS, (
            f"[{lang}] firaset yolunun TOPLAMI {len(kalici) + len(gok)} "
            f"karakter — o yol composer'dan gecmiyor, yani kirpilmadan "
            f"prompt'a giriyor")
        assert len(kalici) < len(tam), (
            f"[{lang}] include_transits=False blogu kucultmedi: gun "
            f"satirlari kalici bloktan cikmiyor")

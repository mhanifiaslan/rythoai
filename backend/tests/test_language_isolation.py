"""Dil sizintisi muhafizi.

Bu dosya tek tek hatalari degil, HATA SINIFINI kapatir. Ayni kusur bes kez
farkli yerde ortaya cikti (burc yorumu, ay evresi, retro listesi, acilar,
BaZi elementleri): hesap katmani ciktisinda TURKCE AD tutuyordu ve o ad,
paylasimli onbellek uzerinden ya da dogrudan, dil ne olursa olsun kullaniciya
gidiyordu.

Buradaki degismezler:

1. Hesap motorlari (sky/bazi/iching) dilden bagimsizdir — ciktilarinda Turkce
   ad bulunmaz, anahtar bulunur.
2. Her dilin ad tablolari ayni anahtar kumesini kapsar.
3. Ingilizce uretilen prompt'lar Turkce karakter icermez.

Ucuncu madde en degerlisi: yeni bir rapor turu eklendiginde ve Turkce bir alan
prompt'a sizdiginda test kirmizi doner.

Calistirma:  .venv\\Scripts\\python.exe -m pytest tests/test_language_isolation.py -q
"""
from __future__ import annotations

import datetime as dt
import re

import pytest

from core import i18n
from services import (bazi_service, bazi_stars, iching_service, prompts,
                      sky_service)

#: Yalnizca Turkcede bulunan harfler. "i", "o", "u" gibi ortak harfler yok;
#: yanlis pozitif uretmemesi icin liste bilincli olarak dar.
TURKCE_HARFLER = re.compile(r"[ığşİĞŞçöüÇÖÜ]")

TABLOLAR = [
    "SIGN_NAMES", "PERIOD_NAMES", "PERIOD_LENGTHS", "MOON_PHASES",
    "PLANET_NAMES", "ASPECT_NAMES", "BAZI_ELEMENTS", "BAZI_ANIMALS",
    "TEN_GOD_MEANINGS", "POLARITY_NAMES", "GENDER_NAMES",
    "ELEMENT_NAMES", "MODALITY_NAMES", "BAZI_NOTES",
    "BAZI_STRENGTH_NAMES", "BAZI_SEASON_STATES",
    "SHEN_SHA_NAMES", "SHEN_SHA_MEANINGS",
    "TRIGRAM_FAMILY_NAMES", "TRIGRAM_ATTRIBUTE_NAMES",
    "ELEMENT_RELATION_NAMES", "LIU_QIN_NAMES", "ICHING_METHOD_NAMES",
    "TRANSIT_EVENT_NAMES", "DECLINATION_ASPECT_NAMES",
    "MOVEMENT_NAMES", "ASTRO_NOTES",
]


#: Turkce olmadigi halde bu harfleri tasiyan mesru parcalar.
#: "Lü" -> 10. ve 56. heksagramin pinyin adi; her iki dilde de boyle yazilir.
MESRU_ISTISNALAR = ("Lü",)


def _istisnalari_ayikla(metin: str) -> str:
    for istisna in MESRU_ISTISNALAR:
        metin = metin.replace(istisna, "")
    return metin


def turkce_kalinti(metin: str) -> set[str]:
    """Metindeki Turkce harfleri dondurur; mesru istisnalar ayiklanir."""
    return set(TURKCE_HARFLER.findall(_istisnalari_ayikla(metin)))


def turkce_kelime_kalintisi(metin: str) -> set[str]:
    """Ad tablolarindaki Turkce degerlerden metinde gecenleri dondurur.

    Regex tek basina yetmez: "Aslan", "Kova", "Terazi", "Akrep" gibi Turkce
    adlarin ayirt edici harfi yok. Bu kontrol tam da onlari yakalar —
    Ingilizce karsiligi farkli olan her Turkce degeri arar.
    """
    tr, en = prompts.get("tr"), prompts.get("en")
    bulunanlar = set()
    for tablo in TABLOLAR:
        tr_tablo, en_tablo = getattr(tr, tablo), getattr(en, tablo)
        for anahtar, tr_deger in tr_tablo.items():
            en_deger = en_tablo.get(anahtar)
            if not isinstance(tr_deger, str) or tr_deger == en_deger:
                continue  # iki dilde ayni olan ad (Mars, Yang) sorun degil
            if re.search(rf"\b{re.escape(tr_deger)}\b", metin):
                bulunanlar.add(tr_deger)
    return bulunanlar


def turkce_izi(deger, yol: str = "") -> list[str]:
    """Ic ice yapida Turkce karakter tasiyan METIN alanlarini bulur.

    Yalnizca degerlere bakar; anahtar adlari (ornegin ``name_tr``) sorun
    degildir — iki dili ayri alanlarda tutmak kasitli bir tasarim.
    """
    bulunanlar: list[str] = []
    if isinstance(deger, dict):
        for anahtar, alt in deger.items():
            # `*_tr` alanlari Turkce olmak ZORUNDA; onlari denetlemeyiz.
            if isinstance(anahtar, str) and anahtar.endswith("_tr"):
                continue
            bulunanlar += turkce_izi(alt, f"{yol}.{anahtar}")
    elif isinstance(deger, (list, tuple)):
        for i, alt in enumerate(deger):
            bulunanlar += turkce_izi(alt, f"{yol}[{i}]")
    # MESRU_ISTISNALAR burada da ayiklanir. Eksikligi gercek bir sorundu:
    # 10. ve 56. heksagramin adi "Lü" (履 ve 旅'nin pinyin okunusu, iki dilde
    # de boyle yazilir) ve `turkce_kalinti` bunu zaten muaf tutuyordu ama
    # `turkce_izi` tutmuyordu. Sonuc: I Ching testi RASTGELE cekim o ikisine
    # denk geldiginde kiriliyordu (64'te 2, ~%3). Bir kez "sira bagimli"
    # sanilip gecildi; oyle degil, yanlis pozitifti.
    elif isinstance(deger, str) and TURKCE_HARFLER.search(
            _istisnalari_ayikla(deger)):
        bulunanlar.append(f"{yol} = {deger!r}")
    return bulunanlar


# --------------------------------------------------------------------------
# 1. Hesap motorlari dilden bagimsiz
# --------------------------------------------------------------------------

@pytest.fixture
def temiz_onbellek(tmp_path, monkeypatch):
    """Her test kendi onbellegiyle calisir.

    Gokyuzu 1 saat onbellekli: onceki bir kosunun (veya eski bicimin) kaydi
    okunursa test gercekte olani olcmez.
    """
    from core import cache, config
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    yield
    cache._memory.clear()


def test_gokyuzu_motoru_turkce_tasimaz(temiz_onbellek):
    sky = sky_service.get_sky_now(include_nasa=False)
    sizinti = turkce_izi(sky, "sky")
    assert not sizinti, f"Gokyuzu hesabinda Turkce ad: {sizinti}"


def test_bazi_motoru_turkce_tasimaz():
    chart = bazi_service.get_bazi_chart(
        year=1990, month=5, day=12, hour=14, minute=30,
        city="Istanbul", nation="TR", gender="female", name="Test",
    )
    sizinti = turkce_izi(chart, "bazi")
    assert not sizinti, f"BaZi hesabinda Turkce ad: {sizinti}"


def test_iching_motoru_turkce_tasimaz():
    # `*_tr` alanlari haric her sey dilden bagimsiz olmali.
    cast = iching_service.cast_iching("test", method="coins")
    sizinti = turkce_izi(cast, "iching")
    assert not sizinti, f"I Ching ciktisinda Turkce ad: {sizinti}"


# --------------------------------------------------------------------------
# 2. Ad tablolari her dilde ayni anahtarlari kapsar
# --------------------------------------------------------------------------

@pytest.mark.parametrize("tablo", TABLOLAR)
def test_ad_tablolari_ayni_anahtarlari_tasir(tablo):
    kumeler = {kod: set(getattr(prompts.get(kod), tablo))
               for kod in i18n.SUPPORTED}
    referans = kumeler[i18n.DEFAULT]
    for kod, kume in kumeler.items():
        assert kume == referans, (
            f"{tablo} tablosunda {kod} ile {i18n.DEFAULT} ayrisiyor: "
            f"eksik={referans - kume} fazla={kume - referans}")


def test_motor_anahtarlari_tablolarda_karsiligi_var():
    """Motor yeni bir anahtar uretirse tablo da guncellenmeli."""
    beklenen = {
        "MOON_PHASES": {a for _, a, _ in sky_service._MOON_PHASES},
        "ASPECT_NAMES": {a for _, a, _ in sky_service._MAJOR_ASPECTS},
        "PLANET_NAMES": {ad for ad, _, _, _ in sky_service._PLANETS},
        "BAZI_ELEMENTS": set(bazi_service._ELEMENT_ORDER),
        "BAZI_ANIMALS": {b["animal"] for b in bazi_service.BRANCHES},
        "TEN_GOD_MEANINGS": {v[1] for v in bazi_service._TEN_GODS.values()},
        "SHEN_SHA_NAMES": set(bazi_stars.STAR_KEYS),
        "SHEN_SHA_MEANINGS": set(bazi_stars.STAR_KEYS),
    }
    for kod in i18n.SUPPORTED:
        modul = prompts.get(kod)
        for tablo, anahtarlar in beklenen.items():
            eksik = anahtarlar - set(getattr(modul, tablo))
            assert not eksik, f"{kod}/{tablo} icinde eksik anahtar: {eksik}"


def test_ceviriler_gercekten_farkli():
    """Ayni metnin iki dile de yazilmasi (kopyala-yapistir artigi) yakalanir.

    Ozel adlar dogal olarak ayni kalir (Mars, Yang, Metal); bunlar disarida.
    """
    ayni_kalabilir = {
        # Mars her iki dilde ayni; Kiron/Lilith/IC uluslararasi kisaltma ve
        # ozel ad oldugu icin cevrilmez.
        "PLANET_NAMES": {"Mars", "Chiron", "Mean_Lilith", "Imum_Coeli"},
        "POLARITY_NAMES": {"Yang", "Yin"},
        "BAZI_ELEMENTS": {"metal"},
        "SIGN_NAMES": {"leo", "libra", "virgo"},
        "PERIOD_NAMES": set(),
        "PERIOD_LENGTHS": set(),
        "MOON_PHASES": set(),
        "ASPECT_NAMES": set(),
        "BAZI_ANIMALS": set(),
        "TEN_GOD_MEANINGS": set(),
        "GENDER_NAMES": set(),
        "ELEMENT_NAMES": set(),
        "MODALITY_NAMES": set(),
    }
    tr, en = prompts.get("tr"), prompts.get("en")
    for tablo, muaf in ayni_kalabilir.items():
        tr_tablo, en_tablo = getattr(tr, tablo), getattr(en, tablo)
        for anahtar in tr_tablo:
            if anahtar in muaf:
                continue
            assert tr_tablo[anahtar] != en_tablo[anahtar], (
                f"{tablo}[{anahtar}] iki dilde ayni: {tr_tablo[anahtar]!r}")


# --------------------------------------------------------------------------
# 3. Ingilizce prompt'lar Turkce karakter icermez
#
# Asil muhafiz bu: yeni bir rapor turu eklenip Turkce bir alan prompt'a
# sizarsa test kirmizi doner.
# --------------------------------------------------------------------------

def _yakala(monkeypatch, report_service):
    """Uretilen prompt'u yakalayan sahte generate."""
    kutu: dict[str, str] = {}

    def sahte(prompt, **k):
        kutu["prompt"] = prompt
        return "ok"

    monkeypatch.setattr(report_service.gemini_service, "generate", sahte)
    monkeypatch.setattr(report_service, "retrieve_context", lambda *a, **k: "")
    return kutu


def test_ingilizce_natal_promptu_turkce_icermez(monkeypatch, temiz_onbellek):
    from services import astro_service, report_service

    kutu = _yakala(monkeypatch, report_service)
    chart = astro_service.get_natal_chart(
        name="Test", year=1990, month=5, day=12, hour=14, minute=30,
        city="Istanbul", nation="TR",
    )
    report_service.natal_report("u-natal-en", chart, lang="en")

    prompt = kutu["prompt"]
    assert not turkce_kalinti(prompt),         f"Ingilizce natal prompt'unda Turkce harf: {turkce_kalinti(prompt)}"
    assert not turkce_kelime_kalintisi(prompt),         f"Ingilizce natal prompt'unda Turkce ad: {turkce_kelime_kalintisi(prompt)}"


def test_ingilizce_bazi_promptu_turkce_icermez(monkeypatch, temiz_onbellek):
    from services import report_service

    kutu = _yakala(monkeypatch, report_service)
    chart = bazi_service.get_bazi_chart(
        year=1990, month=5, day=12, hour=14, minute=30,
        city="Istanbul", nation="TR", gender="male", name="Test",
    )
    report_service.bazi_report("u-bazi-en", chart, lang="en")

    prompt = kutu["prompt"]
    assert not turkce_kalinti(prompt),         f"Ingilizce BaZi prompt'unda Turkce harf: {turkce_kalinti(prompt)}"
    assert not turkce_kelime_kalintisi(prompt),         f"Ingilizce BaZi prompt'unda Turkce ad: {turkce_kelime_kalintisi(prompt)}"


def test_ingilizce_iching_promptu_turkce_icermez(monkeypatch, temiz_onbellek):
    from services import report_service

    kutu = _yakala(monkeypatch, report_service)
    # 64 heksagramin hepsi denenir: tek bir heksagramin Ingilizce metni
    # eksikse rastgele cekimde gozden kacardi.
    for numara in range(1, 65):
        heksagram = iching_service.get_hexagram(numara)
        cast = {
            "question": "what now",
            "method": "coins",
            "moving_lines": [],
            "primary": heksagram,
        }
        report_service.iching_reading(f"u-ic-{numara}", cast, lang="en")
        kalinti = turkce_kalinti(kutu["prompt"])
        assert not kalinti, (
            f"#{numara} heksagraminin Ingilizce prompt'unda Turkce: {kalinti}")


def test_ingilizce_burc_ve_gunluk_promptu_turkce_icermez(monkeypatch,
                                                         temiz_onbellek):
    from services import astro_service, report_service

    kutu = _yakala(monkeypatch, report_service)
    monkeypatch.setattr(report_service.memory_service, "memory_context",
                        lambda uid, max_chars=600, **k: "")

    sky = prompts.localize_sky(
        "en", sky_service.get_sky_now(include_nasa=False))

    report_service.horoscope_reading("leo", "daily", sky, lang="en")
    assert not turkce_kalinti(kutu["prompt"])
    assert not turkce_kelime_kalintisi(kutu["prompt"]),         f"Ingilizce burc prompt'unda Turkce ad: "         f"{turkce_kelime_kalintisi(kutu['prompt'])}"

    natal = astro_service.get_natal_chart(
        name="Test", year=1990, month=5, day=12, hour=14, minute=30,
        city="Istanbul", nation="TR",
    )
    report_service.daily_reading("u-daily-en", natal, sky, lang="en")
    assert not turkce_kalinti(kutu["prompt"])
    assert not turkce_kelime_kalintisi(kutu["prompt"]),         f"Ingilizce gunluk prompt'unda Turkce ad: "         f"{turkce_kelime_kalintisi(kutu['prompt'])}"


def test_ingilizce_harita_fisiltisi_turkce_icermez(temiz_onbellek):
    """Sohbete iliştirilen harita blogu en riskli yuzey: HER mesajda gider.

    Blok gezegen, burc, ev, aci, element ve nitelik adlarinin hepsini bir
    arada tasiyor; bunlardan biri anahtar yerine Turkce ad tutarsa Ingilizce
    konusan kullanici her turda Turkce bir kelime gorur.
    """
    from services import chart_context

    birth = dict(name="Test", year=1990, month=5, day=12, hour=14, minute=30,
                 city="Istanbul", nation="TR")
    facts = {**chart_context.natal_facts(birth),
             "transits": chart_context.transit_facts(birth)["hits"]}

    blok = chart_context.render(facts, lang="en")
    assert blok, "Ingilizce harita blogu bos dondu"
    assert not turkce_kalinti(blok), \
        f"Ingilizce harita blogunda Turkce harf: {turkce_kalinti(blok)}"
    assert not turkce_kelime_kalintisi(blok), \
        f"Ingilizce harita blogunda Turkce ad: {turkce_kelime_kalintisi(blok)}"

    # Karsi kontrol: Turkce tarafta gercekten Turkce uretiliyor mu?
    assert turkce_kalinti(chart_context.render(facts, lang="tr"))


def test_harita_olgulari_dilden_bagimsiz(temiz_onbellek):
    """Olgu sozlugu hicbir gosterilecek ad tasimaz, yalnizca anahtar."""
    from services import chart_context

    birth = dict(name="Test", year=1990, month=5, day=12, hour=14, minute=30,
                 city="Istanbul", nation="TR")
    facts = chart_context.natal_facts(birth)
    sizinti = turkce_izi(facts, "chart")
    assert not sizinti, f"Harita olgularinda Turkce ad: {sizinti}"


def test_turkce_promptlar_turkce_kalir(monkeypatch, temiz_onbellek):
    """Karsi kontrol: yerellestirme her seyi Ingilizceye cevirmemeli."""
    from services import astro_service, report_service

    kutu = _yakala(monkeypatch, report_service)
    chart = astro_service.get_natal_chart(
        name="Test", year=1990, month=5, day=12, hour=14, minute=30,
        city="Istanbul", nation="TR",
    )
    report_service.natal_report("u-natal-tr", chart, lang="tr")

    assert TURKCE_HARFLER.search(kutu["prompt"]), \
        "Turkce prompt Turkce karakter icermeli"


# --------------------------------------------------------------------------
# 4. Sohbet yolu
# --------------------------------------------------------------------------

def test_sohbet_harita_ozeti_dile_gore():
    """Harita ozeti prompt'a giriyor; etiketleri sabit Turkce idi."""
    from services import profile_service

    profil = {"sunSign": "Kova ♒", "moonSign": "Aslan",
              "ascendant": "Terazi ♎"}

    tr = profile_service.chart_summary(profil, lang="tr")
    en = profile_service.chart_summary(profil, lang="en")

    assert "Kova" in tr and "Aslan" in tr
    assert "Aquarius" in en and "Leo" in en and "Libra" in en
    assert not turkce_kalinti(en), \
        f"Ingilizce harita ozetinde Turkce: {turkce_kalinti(en)}"
    assert not turkce_kelime_kalintisi(en), \
        f"Ingilizce harita ozetinde Turkce ad: {turkce_kelime_kalintisi(en)}"


def test_rag_tetigi_iki_dilde_calisir():
    """Terim listesi yalnizca Turkce oldugunda Ingilizce soru korpusa hic
    ugramiyordu — cevabin kalitesi sessizce dusuyordu."""
    from services.prompt_composer import should_use_rag

    for mesaj in ("Merkur retrosu iliskimi nasil etkiler",
                  "Yukselen burcum ne anlama geliyor",
                  "What does my Mercury retrograde mean for my relationship",
                  "Can you explain what my rising sign means",
                  "How does the full moon affect a Scorpio"):
        assert should_use_rag(mesaj), f"RAG tetiklenmeliydi: {mesaj}"

    for mesaj in ("selam", "merhaba nasilsin", "hi there", "thanks a lot"):
        assert not should_use_rag(mesaj), f"RAG tetiklenmemeliydi: {mesaj}"


def test_ingilizce_sohbet_promptu_turkce_icermez(monkeypatch, temiz_onbellek):
    """Sohbet promptunun tamami: fisilti etiketleri, harita, gokyuzu."""
    from api import chat as chat_api
    from services.prompt_composer import compose_chat_message
    from services import profile_service

    monkeypatch.setattr(chat_api, "get_sky_now",
                        lambda: sky_service.get_sky_now(include_nasa=False))

    mesaj = compose_chat_message(
        "what does my chart say about work",
        passages=[],
        memory="",
        chart=profile_service.chart_summary(
            {"sunSign": "Kova ♒", "moonSign": "Aslan"}, lang="en"),
        sky=chat_api._sky_summary("en"),
        lang="en",
    )

    assert not turkce_kalinti(mesaj), \
        f"Ingilizce sohbet promptunda Turkce: {turkce_kalinti(mesaj)}"
    assert not turkce_kelime_kalintisi(mesaj), \
        f"Ingilizce sohbet promptunda Turkce ad: {turkce_kelime_kalintisi(mesaj)}"


# --------------------------------------------------------------------------
# 5. Bildirimler
#
# Bildirim metni SUNUCUDA uretiliyor ve kullanicinin diline gore secilmesi
# profildeki `language` alanina bagli. Sablonlardan biri tek dilde kalirsa
# kullanici yanlis dilde bildirim alir ve bunu bize bildirmesinin yolu yok.
# --------------------------------------------------------------------------

PUSH_SABLONLARI = [
    "PUSH_DAILY_TITLE", "PUSH_DAILY_FALLBACK", "PUSH_STREAK_TITLE",
    "PUSH_STREAK_BODY", "PUSH_FRIEND_TITLE", "PUSH_FRIEND_BODY",
    "PUSH_DAILY_PROMPT",
    # OB-turu: korumasiz kalan + yeni sablonlar — hepsi tr+en ve GERCEKTEN
    # cevrilmis olmali (davet pushu Ingilizce kullaniciya Turkce gitmesin).
    "PUSH_SIGNAL_TITLE", "PUSH_CHECKIN_TITLE",
    "PUSH_MIDDAY_TITLE", "PUSH_MIDDAY_PAIR_TITLE",
    "PUSH_INVITE_TITLE", "PUSH_INVITE_BODY",
    "PUSH_INVITE_ACCEPTED_TITLE", "PUSH_INVITE_ACCEPTED_BODY",
    # AD-turu: panelin "kendime test gönder" sabit metni.
    "PUSH_TEST_TITLE", "PUSH_TEST_BODY",
    # GB-turu: panelden geri bildirim yanıtı pushu.
    "PUSH_FEEDBACK_REPLY_TITLE",
    # PBZ-turu: "dünkü cümleyi yineleme" bloğu prompt'a giriyor; tek dilde
    # kalsaydı Ingilizce prompt Turkce talimat tasirdi.
    "SIGNALS_AVOID_BLOCK",
]


@pytest.mark.parametrize("sablon", PUSH_SABLONLARI)
def test_push_sablonlari_her_dilde_var(sablon):
    for kod in i18n.SUPPORTED:
        assert getattr(prompts.get(kod), sablon), f"{kod}/{sablon} eksik"


def test_push_sablonlari_gercekten_cevrilmis():
    tr, en = prompts.get("tr"), prompts.get("en")
    for sablon in PUSH_SABLONLARI:
        # PUSH_FRIEND_BODY salt yer tutucudan ibaret ("{emoji} {label}"),
        # dogal olarak iki dilde ayni.
        if sablon == "PUSH_FRIEND_BODY":
            continue
        assert getattr(tr, sablon) != getattr(en, sablon), \
            f"{sablon} cevrilmemis"


def test_ingilizce_push_promptu_turkce_icermez():
    from services import notification_service as ns

    sky = prompts.localize_sky("en", sky_service.get_sky_now(include_nasa=False))
    moon = sky.get("moon_phase") or {}
    prompt = prompts.get("en").PUSH_DAILY_PROMPT.format(
        sign=prompts.sign_name("en", "leo"), today="2026-06-15",
        moon_name=moon.get("name") or "-",
        illumination=moon.get("illumination"),
        retros=", ".join(sky.get("retrogrades") or []) or
        prompts.get("en").NONE_LABEL,
    )
    assert not turkce_kalinti(prompt), \
        f"Ingilizce push promptunda Turkce: {turkce_kalinti(prompt)}"
    assert not turkce_kelime_kalintisi(prompt), \
        f"Ingilizce push promptunda Turkce ad: {turkce_kelime_kalintisi(prompt)}"
    assert ns.MAX_PUSH_BODY > 0


def test_ingilizce_sablon_bildirimleri_turkce_icermez():
    from services import notification_service as ns

    baslik, govde = ns.streak_push({"streakCount": 5}, "en")
    assert not turkce_kalinti(baslik + govde)

    baslik, govde = ns.friend_push("Ada", "🔥", "Keep the streak", "en")
    assert not turkce_kalinti(baslik + govde)


def test_turkce_avoid_ingilizce_prompta_girmez(monkeypatch, temiz_onbellek):
    """PBZ-turu: dil degisen sabah dunku TURKCE govde `avoid=` ile Ingilizce
    prompta giriyordu (prompts/en.py'nin kendi uyarisi). Artik dunku hafiza
    yalniz ayni dilde okunur. Gemini'ye giden HER prompt yakalanir ve
    TURKCE_HARFLER ile taranir.

    Hash esitligi ZORLANIR (dunku kayit bugunku Ingilizce govdenin hash'ini
    tasir): iki dilde bayt-ayni govde gercekte cikmaz; eski kod yolu bu
    girdide avoid'i kesin enjekte ederdi — test kapinin hash'e degil DILE
    baktigini sabitler."""
    from services import notification_service as ns
    from services import signal_service

    ham = {"generated_for": "2026-06-15", "signals": [
        {"transit": "Saturn", "natal": "Moon", "aspect": "Square",
         "orb": 0.3, "theme": "inner", "active": True,
         "exact_on": "2026-06-18", "days_to_exact": 3,
         "movement": "applying"}]}
    bugun_en = "Saturn asks for a quiet review of what you carry."
    dun_tr = "Dünkü cümle: iç dünyanda kapanış var, şükret."
    promptlar: list[str] = []

    def sahte(prompt, lang=None, **k):
        promptlar.append(prompt)
        return f"1. {bugun_en}\nQUESTION: -"

    monkeypatch.setattr(signal_service.gemini_service, "generate", sahte)
    monkeypatch.setattr(signal_service, "cached_signals",
                        lambda p, today=None: ham)

    onceki = {"day": "2026-06-14", "body": dun_tr,
              "bodyHash": ns._body_hash(bugun_en), "lang": "tr",
              "focusFp": "Saturn-Square-Moon", "focusIdx": 0,
              "theme": "inner"}
    sonuc = ns.signal_push({"uid": "u-avoid-en", "language": "en"}, "en",
                           today=dt.date(2026, 6, 15), onceki=onceki)
    assert sonuc is not None and sonuc[1] == bugun_en
    assert promptlar, "Ingilizce sinyal prompt'u hic uretilmedi"
    for prompt in promptlar:
        assert not turkce_kalinti(prompt), \
            f"Ingilizce sinyal prompt'unda Turkce: {turkce_kalinti(prompt)}"

    # Karsi kontrol: ayni dilde (tr etiketi + tr kosusu) blok GERCEKTEN
    # girer — yakalama duzenegi calisiyor, test bosuna gecmiyor.
    promptlar.clear()
    dunku_tr = "Aynı cümle."
    monkeypatch.setattr(signal_service.gemini_service, "generate",
                        lambda prompt, lang=None, **k: (
                            promptlar.append(prompt)
                            or f"1. {dunku_tr}\nSORU: -"))
    onceki_tr = {**onceki, "body": dunku_tr,
                 "bodyHash": ns._body_hash(dunku_tr), "lang": "tr"}
    ns.signal_push({"uid": "u-avoid-tr", "language": "tr"}, "tr",
                   today=dt.date(2026, 6, 15), onceki=onceki_tr)
    assert len(promptlar) == 2 and dunku_tr in promptlar[-1]


def test_tepki_etiketleri_dile_gore_farkli():
    from api import notify

    tr, en = notify.REACTION_LABELS["tr"], notify.REACTION_LABELS["en"]
    for anahtar in tr:
        assert tr[anahtar] != en[anahtar], f"{anahtar} cevrilmemis"

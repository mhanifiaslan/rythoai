"""Revize R8: içerik derinliği.

İki iddia sınanıyor ve ikisi de sessizce bozulabilecek türden:

1. Kişisel günlük okuma bugünün transit-natal kesişimini GÖRÜYOR. Eskiden
   yalnızca genel gökyüzü veriliyordu; satır prompt'tan düşerse hiçbir hata
   çıkmaz, okuma yalnızca jenerikleşir.
2. Rapor RAG sorguları isteğin dilinde kuruluyor. Eski sabit şablonlar
   ("sun sign temperament character") TR korpusta İngilizce arıyordu —
   dönen pasaj alakasızlaşır ama üretim "başarılı" görünürdü.
"""
from __future__ import annotations

import pytest

from services import prompts, report_service, sky_service


@pytest.fixture
def temiz_onbellek(tmp_path, monkeypatch):
    from core import cache, config
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    yield
    cache._memory.clear()


def _kur(monkeypatch):
    """Prompt'u ve RAG sorgusunu yakalayan sahte uçlar."""
    kutu: dict[str, str] = {}

    def sahte_generate(prompt, **k):
        kutu["prompt"] = prompt
        return "ok"

    def sahte_rag(query, **k):
        kutu["sorgu"] = query
        return ""

    monkeypatch.setattr(report_service.gemini_service, "generate",
                        sahte_generate)
    # from-import DEĞİL modül niteliği: report_service.retrieve_context
    # adıyla yamalanabilir kalmalı (bkz. wallet'taki aliasing dersi).
    monkeypatch.setattr(report_service, "retrieve_context", sahte_rag)
    monkeypatch.setattr(report_service.memory_service, "memory_context",
                        lambda uid, max_chars=600, **k: "")
    return kutu


def _natal():
    from services import astro_service
    return astro_service.get_natal_chart(
        name="Test", year=1990, month=5, day=12, hour=14, minute=30,
        city="Istanbul", nation="TR",
    )


_BIRTH = dict(name="Test", year=1990, month=5, day=12, hour=14, minute=30,
              city="Istanbul", nation="TR")

_VURUS = {"hits": [{"transit": "Saturn", "natal": "Sun",
                    "aspect": "square", "orb": 0.8}]}


def test_gunluk_okuma_transiti_prompta_koyar(monkeypatch, temiz_onbellek):
    kutu = _kur(monkeypatch)
    monkeypatch.setattr(report_service.chart_context, "transit_facts",
                        lambda birth: _VURUS)

    sky = prompts.localize_sky(
        "tr", sky_service.get_sky_now(include_nasa=False))
    report_service.daily_reading("u-r8-tr", _natal(), sky, lang="tr",
                                 birth=_BIRTH)

    # Yerelleştirilmiş adlarla: "Saturn" değil "Satürn" görünmeli.
    assert prompts.planet_name("tr", "Saturn") in kutu["prompt"]
    assert prompts.aspect_name("tr", "square") in kutu["prompt"]
    assert "Yerleşimler:" in kutu["prompt"]


def test_gunluk_okuma_birthsiz_eski_davranista(monkeypatch, temiz_onbellek):
    """birth verilmezse transit hesabı HİÇ çağrılmaz (eski çağıranlar aynı)."""
    kutu = _kur(monkeypatch)

    def patlama(birth):
        raise AssertionError("birth yokken transit hesaplanmamalı")

    monkeypatch.setattr(report_service.chart_context, "transit_facts",
                        patlama)
    sky = prompts.localize_sky(
        "tr", sky_service.get_sky_now(include_nasa=False))
    sonuc = report_service.daily_reading("u-r8-eski", _natal(), sky,
                                         lang="tr")
    assert sonuc["text"] == "ok"
    assert "{transits}" not in kutu["prompt"]


def test_transit_hesabi_dusunce_okuma_devam_eder(monkeypatch,
                                                 temiz_onbellek):
    """Efemeris düşerse günlük okuma düşmez — transitsiz üretilir."""
    kutu = _kur(monkeypatch)

    def dusen(birth):
        raise RuntimeError("efemeris yok")

    monkeypatch.setattr(report_service.chart_context, "transit_facts", dusen)
    sky = prompts.localize_sky(
        "tr", sky_service.get_sky_now(include_nasa=False))
    sonuc = report_service.daily_reading("u-r8-dusen", _natal(), sky,
                                         lang="tr", birth=_BIRTH)
    assert sonuc["text"] == "ok"
    assert kutu["prompt"]  # prompt yine kuruldu


def test_gunluk_sorgu_istegin_dilinde(monkeypatch, temiz_onbellek):
    kutu = _kur(monkeypatch)
    monkeypatch.setattr(report_service.chart_context, "transit_facts",
                        lambda birth: _VURUS)
    sky = prompts.localize_sky(
        "tr", sky_service.get_sky_now(include_nasa=False))
    report_service.daily_reading("u-r8-sorgu", _natal(), sky, lang="tr",
                                 birth=_BIRTH)

    sorgu = kutu["sorgu"]
    # TR tohumu var, eski İngilizce dolgu yok.
    assert "Mizaç" in sorgu
    assert "temperament" not in sorgu
    assert "interpretation" not in sorgu


def test_natal_sorgu_ingilizce_dolgu_icermez(monkeypatch, temiz_onbellek):
    kutu = _kur(monkeypatch)
    report_service.natal_report("u-r8-natal", _natal(), lang="tr")

    sorgu = kutu["sorgu"]
    assert "sun sign temperament" not in sorgu
    assert "character" not in sorgu
    assert "Mizaç" in sorgu


def test_iching_promptu_cizgi_metnini_tasir(monkeypatch, temiz_onbellek):
    """İ4: hareketli çizginin METNİ prompt'ta — numarası değil.

    Metin düşerse hata çıkmaz; model yalnız 'çizgi 3 hareketli' bilgisiyle
    genelleme yapar. Bu test o sessiz gerilemeyi tutar.
    """
    from services import iching_service
    kutu = _kur(monkeypatch)
    beslenen = iter([7, 7, 9, 8, 8, 8])   # 11 Tai, hareketli 3. çizgi
    monkeypatch.setattr(iching_service, "_cast_line_coins",
                        lambda: next(beslenen))
    cekim = iching_service.cast_iching("işim ne olacak", method="coins")
    cekim = iching_service.enrich_cast(
        cekim, day_pillar={"label": "甲子 (Jia Zi)", "cycle": 0},
        day_master_element="wood", basis="utc")
    report_service.iching_reading("u-i4", cekim, lang="tr")

    prompt = kutu["prompt"]
    h11 = iching_service.get_hexagram(11)
    assert h11["lines_tr"][2] in prompt            # 3. çizginin METNİ
    assert "甲子" in prompt                         # gün sütunu etiketi
    assert "üç para" in prompt                     # yöntem adı çevrili
    assert "coins" not in prompt
    assert "saray" in prompt.lower() or "qian" in prompt.lower()
    # RAG sorgusu isteğin dilinde.
    assert "Değişimler Kitabı" in kutu["sorgu"]


def test_iching_hareketsizde_donusum_bloku_yok(monkeypatch, temiz_onbellek):
    from services import iching_service
    kutu = _kur(monkeypatch)
    beslenen = iter([7, 8, 7, 8, 7, 8])   # 63 Ji Ji, hareketli yok
    monkeypatch.setattr(iching_service, "_cast_line_coins",
                        lambda: next(beslenen))
    cekim = iching_service.cast_iching("soru", method="coins")
    report_service.iching_reading("u-i4b", cekim, lang="tr")

    prompt = kutu["prompt"]
    assert "DÖNÜŞEN HEKSAGRAM" not in prompt
    assert "METİNLERİ (yorumun ağırlık merkezi): -" in prompt
    # Bağlamsız çekimde kişiselleştirme satırı "-".
    assert "Danışanla bağ (Day Master ↔ trigramlar): -" in prompt


def test_bazi_promptu_derin_veriyi_tasir(monkeypatch, temiz_onbellek):
    """B6: rapor promptu motorun yeni ürettiklerini gerçekten görüyor.

    Güç hükmü, dayanak dökümü, gizli kökler, Liu Nian ve kapsam beyanı —
    bunlardan biri prompt kurulumundan düşerse hiçbir hata çıkmaz, model
    yalnızca o konuda genelleme yapar. Bu test o sessiz gerilemeyi tutar.
    """
    from services import bazi_service, prompts as prompt_mod
    kutu = _kur(monkeypatch)
    chart = bazi_service.get_bazi_chart(
        1990, 5, 12, 14, 30, city="Istanbul", gender="female")
    report_service.bazi_report("u-b6", chart, lang="tr")

    prompt = kutu["prompt"]
    yerel = prompt_mod.localize_bazi("tr", chart)
    assert "GÜÇ HÜKMÜ" in prompt
    assert yerel["strength"]["verdict_name"] in prompt
    assert "month_command" in prompt          # dayanak dökümü
    assert "→" in prompt                       # gizli kök satırı
    assert str(chart["current_year_pillar"]["year"]) in prompt
    # Kapsam beyanı: kombinasyonlar hesapta yok — model bunu okumalı.
    assert "he/chong" in prompt

    # Sorgu bazi tohumunu taşıyor.
    assert "Dört Sütun" in kutu["sorgu"]


def test_natal_promptu_denge_bloklarini_tasir(monkeypatch, temiz_onbellek):
    """T4: element/nitelik dengesi, yığılma ve deklinasyon blokları promptta.

    Bu satırlar kurulumdan düşerse hata çıkmaz — model yalnızca o konularda
    genelleme yapar (B6 ile aynı sessiz gerileme sınıfı).
    """
    kutu = _kur(monkeypatch)
    report_service.natal_report("u-t4-natal", _natal(), lang="tr")

    prompt = kutu["prompt"]
    assert "DENGE" in prompt
    assert "Ateş" in prompt and "Su" in prompt          # element sayımı
    assert "Öncü" in prompt or "Sabit" in prompt        # nitelik sayımı
    assert "DEKLİNASYON" in prompt
    # Açı satırları hareket bilgisini taşıyor (T0'ın bedeli ödenmiş alanı).
    assert ("yaklaşıyor" in prompt or "ayrılıyor" in prompt
            or "durağan" in prompt)


def test_solar_return_promptu_saatsizlik_beyanini_tasir(monkeypatch,
                                                        temiz_onbellek):
    """T1/T4: saatsiz SR promptunda ASC '-' ve beyan metni var."""
    from services import predict_service
    kutu = _kur(monkeypatch)
    sr = predict_service.solar_return(
        "Test", 1990, 5, 12, 12, 0, "Istanbul",
        hour_known=False, target_year=2025)
    report_service.solar_return_report("u-t4-sr", sr, lang="tr")

    prompt = kutu["prompt"]
    assert "Yıl haritası Yükseleni: -" in prompt
    assert prompts.get("tr").ASTRO_NOTES["sr_hour_unknown"] in prompt
    # Sorgu isteğin dilinde: yıl Ay'ının Türkçe adı geçiyor.
    assert prompts.sign_name_from_code("tr", sr["sr_moon_sign"]) \
        in kutu["sorgu"]


def test_progressions_promptu_omurgayi_tasir(monkeypatch, temiz_onbellek):
    """T2/T4: progres Ay burcu, lunasyon evresi ve solar arc satırları."""
    from services import predict_service
    kutu = _kur(monkeypatch)
    prog = predict_service.secondary_progressions(
        "Test", 1990, 5, 12, 14, 30, "Istanbul")
    hits = predict_service.solar_arc_hits(
        "Test", 1990, 5, 12, 14, 30, "Istanbul")
    report_service.progressions_report("u-t4-prog", prog, hits, lang="tr")

    prompt = kutu["prompt"]
    yerel = prompts.localize_progressions("tr", prog, hits)
    assert yerel["prog_moon"]["sign_local"] in prompt
    assert yerel["prog_moon"]["phase_local"] in prompt
    assert prog["prog_moon"]["next_sign_at"] in prompt
    assert str(prog["solar_arc_deg"]) in prompt
    if hits:
        assert yerel["solar_arc_hits"][0]["directed_local"] in prompt


def test_progressions_saatsiz_prompt_asc_gizler(monkeypatch,
                                                temiz_onbellek):
    from services import predict_service
    kutu = _kur(monkeypatch)
    prog = predict_service.secondary_progressions(
        "Test", 1990, 5, 12, 12, 0, "Istanbul", hour_known=False)
    report_service.progressions_report("u-t4-prog2", prog, [], lang="tr")

    prompt = kutu["prompt"]
    assert "Progres Yükselen: -" in prompt
    assert prompts.get("tr").ASTRO_NOTES["prog_hour_unknown"] in prompt


# ---------------------------------------------------------------------------
# Firaset RAG sorgusu: SABIT dize herkese AYNI uc pasaji cekiyordu
# ---------------------------------------------------------------------------
#
# Olculen kusur (2026-10-03): `prompts.FIRASA_RAG_QUERY` dil basina SABIT bir
# dize ve kullaniciya ait hicbir terim tasimiyordu. `rag_service.search` sorgu
# sabit oldugunda deterministik, yani ayni dildeki HER kullanicinin firaset
# raporu HER gun korpustan BIREBIR AYNI uc pasaji aliyordu. Bu, deponun kendi
# JENERIKLIK kok nedeni sinifinin ikinci bicimi: birincisi "hazir cumle
# tablosu"ydu (`SYNASTRY_AXIS_LINES`), bu "hazir pasaj uclusu".

#: Iki BELIRGIN SEKILDE FARKLI yuz. Esikler (`firasa_service._T`) genis
#: tutuldugu icin ortalama bir yuz hic belirti uretmiyor; iki fikstur de
#: bilerek uc degerlerde.
_YUZ_A = {"jawToCheek": 0.95, "mouthToFaceWidth": 0.50, "eyeSpacing": 0.33,
          "symmetry": 0.97, "upperThird": 0.40, "middleThird": 0.31,
          "lowerThird": 0.29, "widthToHeight": 0.85, "lipFullness": 0.22,
          "motionRate": 0.9, "motionSeconds": 12.0}
_YUZ_B = {"jawToCheek": 0.70, "mouthToFaceWidth": 0.33, "eyeSpacing": 0.47,
          "symmetry": 0.99, "upperThird": 0.28, "middleThird": 0.31,
          "lowerThird": 0.41, "widthToHeight": 0.62, "lipFullness": 0.03,
          "motionRate": 0.05, "motionSeconds": 12.0}
#: Hicbir orani uc OLMAYAN yuz: `descriptors` bos liste donuyor.
_YUZ_ORTALAMA = {"jawToCheek": 0.82, "mouthToFaceWidth": 0.42,
                 "eyeSpacing": 0.45, "symmetry": 0.97}


def test_firaset_RAG_sorgusu_YUZE_GORE_degisir():
    """Sorgu OLCULEN belirtileri tasiyor; capa da yerinde duruyor.

    Uc bagimsiz isaret: (1) iki ayri yuz iki ayri sorgu veriyor, (2) sabit
    capa ikisinde de ONDE duruyor — korpusun firaset bolumune denk gelme
    isini o yapiyor ve "ahlat-i erbaa / kuru-nemli mizac" terimlerini
    yalniz o tasiyor, (3) sorguya giren terim UYDURMA degil, olculen
    belirtinin kendi metni.
    """
    from services import firasa_service

    p = prompts.get("tr")
    sorgu_a = report_service._firasa_rag_sorgusu(_YUZ_A, "tr")
    sorgu_b = report_service._firasa_rag_sorgusu(_YUZ_B, "tr")

    assert sorgu_a != sorgu_b, (
        "iki FARKLI yuz ayni RAG sorgusunu uretti: korpustan donen uc pasaj "
        "da ayni olur ve iki okuma ayni klasik alintilara yaslanir")
    assert sorgu_a.startswith(p.FIRASA_RAG_QUERY), "sabit capa dustu"
    assert sorgu_b.startswith(p.FIRASA_RAG_QUERY), "sabit capa dustu"

    ozet_a = firasa_service.summary(_YUZ_A, "tr")
    assert ozet_a["lines"], "fikstur hic belirti uretmiyor: olcum bos"
    assert ozet_a["lines"][0] in sorgu_a, (
        "olculen belirti sorguya girmedi: kisiselleştirme adi var kendi yok")

    ek = len(sorgu_a) - len(p.FIRASA_RAG_QUERY)
    assert ek <= report_service._FIRASA_RAG_MAX_EK_KRK + 2, (
        f"eklenen terimler {ek} karakter — tavan "
        f"{report_service._FIRASA_RAG_MAX_EK_KRK}; capa gomulur ve getirme "
        f"yuz hatlarindan baska yere kayar")


def test_firaset_RAG_sorgusu_belirti_YOKSA_CAPAYA_duser():
    """Ortalama bir yuzde eklenecek olcum yok — uydurma terim de yok.

    "Olculmeyen soylenmez": belirti uretmeyen yuz icin sorguya bir sey
    eklemek, olcmedigimiz bir seyi aramak olurdu. O halde eski davranisin
    aynisi dogru hal.
    """
    from services import firasa_service

    p = prompts.get("tr")
    assert not firasa_service.descriptors(_YUZ_ORTALAMA), (
        "fikstur belirti uretiyor: bu testin onkosulu dustu")
    assert report_service._firasa_rag_sorgusu(_YUZ_ORTALAMA, "tr") == \
        p.FIRASA_RAG_QUERY


#: Sekiz belirti birden ureten yuz: San Ting'den IKI (bir baskin + bir
#: kisa) + en/boy + cene + agiz + dudak + goz + simetri. `descriptors`in
#: yapisal ust siniri bu (bkz. `firasa_service.descriptors`), ve nem + isi
#: terimleriyle birlikte sorguya ADAY terim sayisi 10 oluyor.
_YUZ_ASIRI = {"upperThird": 0.45, "middleThird": 0.31, "lowerThird": 0.24,
              "widthToHeight": 0.95, "jawToCheek": 0.98,
              "mouthToFaceWidth": 0.55, "lipFullness": 0.40,
              "eyeSpacing": 0.50, "symmetry": 0.80,
              "motionRate": 0.90, "motionSeconds": 12.0}


def _aday_terimler(ratios: dict, lang: str) -> list[str]:
    """`_firasa_rag_sorgusu`nun gordugu TUM aday terimler (tavandan ONCE).

    Yardimcinin kendi derlemesi BIREBIR tekrarlaniyor; amac kirpilanin
    hangi terim oldugunu isimle sorabilmek. Iki yerde yasayan bir derleme
    ayrisabilir — o yuzden onkosul olarak aday sayisi da sorulacak.
    """
    from services import firasa_service

    p = prompts.get(lang)
    ozet = firasa_service.summary(ratios, lang)
    terimler = list(ozet.get("lines") or [])
    if ozet.get("moisture") in p.FIRASA_MOISTURE:
        terimler.append(p.FIRASA_MOISTURE[ozet["moisture"]])
    if ozet.get("heat") in p.FIRASA_HEAT:
        terimler.append(p.FIRASA_HEAT[ozet["heat"]])
    return terimler


def test_firaset_RAG_sorgusu_TAVANI_gercekten_BAGLIYOR(monkeypatch):
    """TAVAN OLCULUYOR — sabitin VARLIGI degil, BAGLADIGI.

    ⚠️ Olculen korluk (dogrulama turu, 2026-10-03): `_FIRASA_RAG_MAX_TERIM`
    ile `_FIRASA_RAG_MAX_EK_KRK` kapilarini kaldiran MINIMAL mutasyon
    (dongu `terimler[:N]` yerine `terimler` uzerinde kosuyor, karakter
    kapisi hic bakmiyor) bu dosyayi YESIL biraktı. Sebebi: ustteki bekci
    `ek` degerini SABITIN KENDISIYLE karsilastiriyor ve fiksturu tavana
    hic yaklasmiyor (TR 61 krk / tavan 300), yani sabit silinse de hicbir
    sey kirmizi donmezdi. Tavanin yaziliu GEREKCESI ("sekizi birden
    eklenirse capa gomulur ve getirme yuz hatlarindan baska yere kayar")
    boylece olculmemis bir iddia olarak kaliyordu.

    IKI KAPI AYRI AYRI olculuyor, cunku normal veride yalniz BIRI
    bagliyor:

      * TERIM kapisi gercek veriyle baglanabilir: 8 belirti ureten bir yuz
        var ve nem + isi ile aday 10'a cikiyor (TR adaylarin toplami 327
        krk, sorguya giren 134 — yani karakter kapisi burada bakmiyor).
      * KARAKTER kapisi bugunku `FIRASA_SIGNS` tablosuyla HIC baglamiyor
        (en uzun satirlar kisa). O yuzden uzun terimler TAKLIT ediliyor:
        kapinin amaci zaten "terim sayisi az ama uzunsa da capa gomulmesin"
        ve o hali tablolar degisirse gercek olur. Taklit etmemek, kapinin
        yarisini olcmemek olurdu.
    """
    from services import firasa_service

    for lang in ("tr", "en"):
        p = prompts.get(lang)
        adaylar = _aday_terimler(_YUZ_ASIRI, lang)
        assert len(firasa_service.descriptors(_YUZ_ASIRI)) == 8, (
            "fikstur artik 8 belirti uretmiyor: bu testin onkosulu dustu")
        assert len(adaylar) > report_service._FIRASA_RAG_MAX_TERIM, (
            f"[{lang}] fikstur tavanin ALTINDA kaldi ({len(adaylar)} aday): "
            f"tavanin bagladigi olculemez")
        assert len(set(adaylar)) == len(adaylar), (
            f"[{lang}] aday terimler tekrarli: asagidaki uyelik olcumu "
            f"yanlis sayar")

        sorgu = report_service._firasa_rag_sorgusu(_YUZ_ASIRI, lang)
        giren = [t for t in adaylar if t in sorgu]
        assert len(giren) == report_service._FIRASA_RAG_MAX_TERIM, (
            f"[{lang}] sorguya {len(giren)} terim girdi, tavan "
            f"{report_service._FIRASA_RAG_MAX_TERIM}: capa "
            f"({p.FIRASA_RAG_QUERY[:30]}…) gomulur ve getirme yuz "
            f"hatlarindan baska yere kayar")
        assert adaylar[report_service._FIRASA_RAG_MAX_TERIM] not in sorgu, (
            f"[{lang}] tavanin USTUNDEKI terim yine de sorguya girdi")
        # Capa kirpilan tarafta DEGIL: her hal icin yine ONDE.
        assert sorgu.startswith(p.FIRASA_RAG_QUERY)

    # KARAKTER kapisi: terim sayisi tavanin ALTINDA ama terimler uzun.
    uzun = ["x" * 80] * (report_service._FIRASA_RAG_MAX_TERIM - 1)
    monkeypatch.setattr(
        report_service.firasa_service, "summary",
        lambda ratios, lang=None: {"keys": [], "lines": list(uzun),
                                   "moisture": None, "heat": None})
    p = prompts.get("tr")
    sorgu = report_service._firasa_rag_sorgusu(_YUZ_ASIRI, "tr")
    ek = len(sorgu) - len(p.FIRASA_RAG_QUERY)
    assert ek <= report_service._FIRASA_RAG_MAX_EK_KRK + 2, (
        f"terim sayisi tavanin altinda ama eklenen metin {ek} karakter — "
        f"karakter kapisi ({report_service._FIRASA_RAG_MAX_EK_KRK}) "
        f"baglamadi; capa uzun terimlerin altinda gomulur")
    assert sorgu.startswith(p.FIRASA_RAG_QUERY)


def test_firaset_RAG_sorgusu_UCTAN_UCA_kisiye_ozgu(monkeypatch,
                                                   temiz_onbellek):
    """KOR BEKCI KAPISI: yukaridaki iki test yardimciyi DOGRUDAN cagiriyor.

    `firasa_report` sorguyu yine `p.FIRASA_RAG_QUERY` ile kurmaya donse o
    testlerin ikisi de YESIL kalirdi — yardimci calisiyor, kimse
    kullanmiyor. Bu bekci gercek uretim yolundan gecen sorguyu olcuyor.
    """
    kutu = _kur(monkeypatch)
    report_service.firasa_report("u-rag-a", _YUZ_A, lang="tr")
    sorgu_a = kutu["sorgu"]
    report_service.firasa_report("u-rag-b", _YUZ_B, lang="tr")
    sorgu_b = kutu["sorgu"]

    assert sorgu_a != sorgu_b, (
        "uretim yolundan gecen RAG sorgusu iki farkli yuz icin AYNI: "
        "firasa_report sabit dizeye donmus olabilir")
    for sorgu, yuz_adi in ((sorgu_a, "A"), (sorgu_b, "B")):
        assert prompts.get("tr").FIRASA_RAG_QUERY in sorgu, (
            f"yuz {yuz_adi}: sabit capa uretim yolunda dustu")


# ---------------------------------------------------------------------------
# Olgu bekcisinin DAYANAGI: sohbet olgularinin TAMAMI okunmali
# ---------------------------------------------------------------------------

def test_olgu_bekcisi_SOHBET_olgularinin_TAMAMINI_dayanak_sayar():
    """`chart_facts` iki sekli de kabul ettigini soyluyordu; kapsami eksikti.

    Olculen (2026-10-03): `chart_context.chart_facts` ciktisinda UC alan
    sessizce atlaniyordu — `ascendant` (orada DUZ DIZE, sozluk degil),
    `transits` ve `upcoming` (alan adlari `transit`/`natal`, `p1`/`p2`
    degil). Sohbet ucu dayanagi tam o sekilden kuruyor
    (`api/chat.py`: `fact_guard.enforce(..., facts=facts)`), yani Yukselen
    burcu ve transit acilari dayanak kumesine HIC girmiyordu.

    Bedeli: eksik dayanak = yanlis pozitif, yanlis pozitifin karsiligi BIR
    LLM TURU DAHA (`enforce` -> `regenerate`). Metin yolu bunu tesaduften
    kurtariyordu (fisilti blogu "Yukselen: Basak" yaziyor) — blok prompt
    butcesinde kirpilirsa ya da fisilti sig ozete duserse kurtarma gider.

    Son iki iddia bekcinin KOR OLMADIGINI olcuyor: dayanagi genisletmek
    gercek bir uydurmayi gecirmemeli.
    """
    from services import fact_guard

    olgular = {
        "sun": {"planet": "Sun", "sign": "leo", "house": 11},
        "moon": {"planet": "Moon", "sign": "aquarius", "house": 5},
        "ascendant": "virgo",
        "placements": [{"planet": "Mercury", "sign": "virgo", "house": 12}],
        "aspects": [{"p1": "Sun", "p2": "Saturn", "aspect": "square"}],
        "transits": [{"transit": "Saturn", "natal": "Venus",
                      "aspect": "trine", "orb": 0.8}],
        "upcoming": [{"date": "2026-10-07", "transit": "Mars",
                      "natal": "Sun", "aspect": "square"}],
    }
    dayanak = fact_guard.chart_facts(olgular)

    assert ("sign", "Ascendant", "virgo") in dayanak, (
        "`ascendant` DUZ DIZE seklinde atlandi: sohbette Yukselen burcu "
        "dayanaksiz kalir")
    assert ("aspect", "Saturn", "trine", "Venus") in dayanak, (
        "`transits` dayanaga girmedi")
    assert ("aspect", "Mars", "square", "Sun") in dayanak, (
        "`upcoming` dayanaga girmedi")
    assert ("sign", "Sun", "leo") in dayanak
    assert ("house", "Mercury", 12) in dayanak

    # Metin yolu OLMADAN da dogru cumle temiz gecmeli (yanlis pozitif yok).
    assert fact_guard.invented_claims("Yükselen Başak'ta.", "",
                                      olgular) == set()
    # Bekci kor olmadi: gercek uydurma HALA yakalaniyor.
    assert ("sign", "Ascendant", "aries") not in dayanak
    assert fact_guard.invented_claims("Yükselen Koç'ta.", "", olgular)


# ---------------------------------------------------------------------------
# Onbellek ISABETI: `persisted` anahtari YOK, `False` DEGIL
# ---------------------------------------------------------------------------

def test_onbellek_ISABETI_persisted_IDDIA_ETMEZ(monkeypatch,
                                                temiz_onbellek):
    """IKI YON: uretimde `persisted` VAR, isabette HIC YOK.

    Kapatilan sey bir yanlis GEREKCEYDI (dogrulama turu, 2026-10-03):
    `_cached_generate`in isabet yolu "katmanin hangisi oldugu OLCULMEDI,
    olculmeyen soylenmez" diyordu. O gerekce bayattI — `cache.get_katmanli`
    eklendikten sonra katman OLCULEBILIYOR ve o islevin kendi docstring'i
    BU NOKTAYI adiyla anip "artik olculebiliyor" diyor. Iki yorum
    birbiriyle celisiyordu ve bu depoda yanlis gerekce kusurdur.

    Gercek gerekce daha dar ve bu bekci onu civiliyor: olculebilen sey
    KATMAN, `persisted` ise PAYLASIMLILIK iddiasi. `KATMAN_BELLEK` donusu
    "kalici katmanda YOK" demiyor, "kalici katmana BAKILMADI" diyor. Yani
    bir isabette `persisted: False` yazmak olculeni yanlis adla sunmak
    olurdu.

    ⚠️ Bugun o yanlis bir ZARAR URETMIYOR ve sebebi OLCULDU: `persisted`i
    okuyan tek yer `api/maintenance` isitma dongusu ve o dongu
    `yazilamayan`a dusmeden ONCE `cached`e bakiyor (`elif` sirasi). Yani
    savunma TUKETICIDE. Sira degisirse ya da `cached`i sormadan
    `persisted`i okuyan ikinci bir cagiran eklenirse her isabet
    "Firestore'a yazamadik" diye sayilir — 24 Gemini uretiminin faturasini
    yazmis bir tur, isitma raporunda basarisiz gorunur. Anahtari HIC
    koymamak o savunmayi kaynaga tasiyor; bu bekci de onu orada tutuyor.

    ⚠️ Bu yuzden bekci `is False` DEGIL `not in` soruyor: "yanlis bir
    ONARIM" (anahtari `False` ile doldurmak) tam da kacinilan hal ve
    `.get("persisted")` ile okuyan cagiran icin ikisi ayirt edilemez.
    Ikinci yon (uretimde anahtar VAR) olmadan bekci tek yonlu kalirdi:
    anahtari her iki yoldan birden silen bir degisiklik yesil gecerdi.
    """
    from core import cache

    _kur(monkeypatch)
    anahtar = "g2v-isabet-1"

    uretim = report_service._cached_generate(anahtar, "prompt", "yedek",
                                             lang="tr")
    assert uretim["cached"] is False
    assert "persisted" in uretim, (
        "uretim yolunda `persisted` yok: isitma dongusu paylasimli katmana "
        "yazilamayan bir turu `isinan` sayar")
    assert uretim["persisted"] is True

    # Bellek katmanini bosalt: isabet KALICI katmandan gelsin ki olculen
    # hal "yalniz bu surecte okunabildi" ile karistirilmasin.
    cache._memory.clear()
    isabet = report_service._cached_generate(anahtar, "prompt", "yedek",
                                            lang="tr")
    assert isabet["cached"] is True
    assert "persisted" not in isabet, (
        "onbellek isabeti `persisted` iddia ediyor: `KATMAN_BELLEK` donusu "
        "'kalici katmanda yok' DEMEZ, yalniz 'bakilmadi' der — `False` "
        "yazmak isitma raporunda yanlis bir `yazilamayan` uretir")


# ---------------------------------------------------------------------------
# B3: iliski okumasinin KISA OMUR yazimi sessizce dusuyordu
# ---------------------------------------------------------------------------

_EKSENLER = {"calc_version": "test-1", "axes": []}


def _bicimsiz_uretim(monkeypatch, kisa_omur_duser: bool) -> dict:
    """Bicimi tutmayan uretim + kisa omurlu yazimin hukmu kontrollu.

    `cache.set` fail-open: Firestore hatasini `logger.warning` ile yutar ve
    False doner. Bu fikstur tam o hali TTL'e gore taklit ediyor.
    """
    monkeypatch.setattr(report_service.gemini_service, "generate",
                        lambda prompt, **k: "bicimi tutmayan metin")
    monkeypatch.setattr(report_service, "retrieve_context",
                        lambda *a, **k: "")
    monkeypatch.setattr(report_service.fact_guard, "enforce",
                        lambda text, prompt, **k: (text, True))

    kutu: dict = {"ttl": []}
    gercek_set = report_service.cache.set

    def sahte_set(key, value, ttl_seconds=24 * 3600, owner_uid=None):
        kutu["ttl"].append(ttl_seconds)
        if kisa_omur_duser and ttl_seconds == 3600:
            return False
        return gercek_set(key, value, ttl_seconds=ttl_seconds,
                          owner_uid=owner_uid)

    monkeypatch.setattr(report_service.cache, "set", sahte_set)
    return kutu


def test_iliski_okumasi_KISA_OMUR_yazilamazsa_BILDIRILIR(monkeypatch,
                                                         temiz_onbellek):
    """Dusen uzerine yazma, kartlari bir AY bos birakiyordu ve sessizdi.

    Dalin TAM AMACI "bicimi tutmayan uretim 30 gun kilitlenmesin". Kisa
    omurlu uzerine yazma fail-open dustugunde `_cached_generate`in yazdigi
    30 GUNLUK kayit yerinde kaliyor — yani amac bosa gidiyor, kartlar o
    cift icin bir ay bos kaliyor ve yanit yine `persisted: True` diyor.

    `persisted` AND'lenMEZ ve bu olculmus bir ayrim: metin paylasimli
    katmana GERCEKTEN yazildi, `persisted` onu dogru soyluyor. Dusen sey
    OMRUN KISALTILMASI — ayri bir olgu, ayri bir ad.
    """
    kutu = _bicimsiz_uretim(monkeypatch, kisa_omur_duser=True)
    sonuc = report_service.relationship_reading(
        "u-b3", "pair-b3", "Ben", "O", _EKSENLER, lang="tr")

    assert not sonuc.get("axis_lines"), "fikstur bicimi TUTTU: onkosul dustu"
    assert 3600 in kutu["ttl"], "kisa omurlu uzerine yazma hic denenmedi"
    assert sonuc["malformed_locked"] is True, (
        "kisa omur yazilamadi ama yanit bunu BILDIRMIYOR: 30 gunluk kayit "
        "yerinde kaldi, kartlar bir ay bos kalacak")
    assert sonuc["persisted"] is True, (
        "`persisted` yanlis adlandirildi: metin paylasimli katmana yazildi, "
        "dusen sey omrun kisaltilmasiydi")


def test_iliski_okumasi_KISA_OMUR_yazilirsa_BAYRAK_TEMIZ(monkeypatch,
                                                         temiz_onbellek):
    """Ters yon: yazim basarirsa bayrak False — yoksa bekci tek yonlu kalir."""
    kutu = _bicimsiz_uretim(monkeypatch, kisa_omur_duser=False)
    sonuc = report_service.relationship_reading(
        "u-b3b", "pair-b3b", "Ben", "O", _EKSENLER, lang="tr")

    assert 3600 in kutu["ttl"]
    assert sonuc["malformed_locked"] is False

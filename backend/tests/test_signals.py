"""Sinyal motoru bekçileri (R2-S1).

Sıralama ve tema eşleme DETERMİNİST olmalı: aynı takvim + aynı harita =
aynı sinyaller. Takvim ve natal olgular sahtelenir; burada test edilen şey
efemeris değil, puanlama/tema/çeşitlilik kuralları ve başlık şablonlarıdır.
"""
from __future__ import annotations

import pytest

from services import prompts, signal_service


#: 16 Ağustos gününe kurulu sahte takvim. Kuzey Düğümü adayı bilerek var:
#: sinyale GİRMEMELİ (_SINYAL_NATAL yedili + eksenlerle sınırlı).
SAHTE_TAKVIM = {
    "calc_version": "3",
    "start": "2026-08-16",
    "days": 8,
    "events": [
        {"date": "2026-08-18", "type": "aspect_exact", "transit": "Saturn",
         "natal": "Moon", "aspect": "square", "orb": 0.1},
        {"date": "2026-08-20", "type": "aspect_exact", "transit": "Jupiter",
         "natal": "Venus", "aspect": "trine", "orb": 0.2},
        {"date": "2026-08-17", "type": "station_retrograde",
         "transit": "Uranus"},
    ],
    "active_now": [
        {"transit": "Saturn", "natal": "Moon", "aspect": "square",
         "orb": 0.8, "movement": "applying"},
        {"transit": "Uranus", "natal": "Medium_Coeli",
         "aspect": "conjunction", "orb": 2.4, "movement": "applying"},
        {"transit": "Chiron", "natal": "True_North_Lunar_Node",
         "aspect": "sextile", "orb": 0.1, "movement": "separating"},
    ],
    "disclosures": [],
}

SAHTE_NATAL = {
    "sun": {"planet": "Sun", "sign": "taurus", "house": 10},
    "moon": {"planet": "Moon", "sign": "cancer", "house": 4},
    "ascendant": "leo",
    "placements": [
        {"planet": "Venus", "sign": "aries", "house": 8},
    ],
}

DOGUM = {"name": "t", "year": 1990, "month": 5, "day": 12,
         "hour": 14, "minute": 30, "city": "Istanbul", "nation": None}


def _hesapla(monkeypatch, takvim=None, natal=SAHTE_NATAL):
    monkeypatch.setattr(signal_service.predict_service, "transit_calendar",
                        lambda **kw: takvim or SAHTE_TAKVIM)
    return signal_service.compute_signals(DOGUM, natal=natal)


class TestSiralamaVeTema:
    def test_determinist_siralama_ve_ust_sinir(self, monkeypatch):
        ham = _hesapla(monkeypatch)
        sinyaller = ham["signals"]
        assert len(sinyaller) <= signal_service.MAX_SIGNALS
        # Puan: Satürn-Ay (aktif, dar orb, yaklaşan, ışık) > Uranüs-MC >
        # Jüpiter-Venüs (henüz orb dışında, 4 gün uzakta).
        assert [(s["transit"], s["natal"]) for s in sinyaller] == [
            ("Saturn", "Moon"), ("Uranus", "Medium_Coeli"),
            ("Jupiter", "Venus")]
        # Aynı girdi -> aynı çıktı (determinizm).
        tekrar = _hesapla(monkeypatch)
        assert [s["score"] for s in tekrar["signals"]] == [
            s["score"] for s in sinyaller]

    def test_ayrilan_aci_geri_duser(self, monkeypatch):
        """Sönen etki, aynı koşuldaki yaklaşan etkinin arkasında kalır."""
        takvim = {**SAHTE_TAKVIM, "events": [], "active_now": [
            {"transit": "Saturn", "natal": "Sun", "aspect": "square",
             "orb": 1.0, "movement": "separating"},
            {"transit": "Saturn", "natal": "Moon", "aspect": "square",
             "orb": 1.0, "movement": "applying"},
        ]}
        ham = _hesapla(monkeypatch, takvim=takvim)
        assert [s["natal"] for s in ham["signals"]] == ["Moon", "Sun"]

    def test_dugum_sinyal_olmaz(self, monkeypatch):
        ham = _hesapla(monkeypatch)
        assert all(s["natal"] != "True_North_Lunar_Node"
                   for s in ham["signals"])

    def test_dayanak_alanlari_dolu(self, monkeypatch):
        """Her sinyal 'Neden?' alt-sayfasının çizeceği dayanağı taşımalı."""
        birinci = _hesapla(monkeypatch)["signals"][0]
        assert birinci["transit"] == "Saturn"
        assert birinci["aspect"] == "square"
        assert birinci["orb"] == 0.8
        assert birinci["movement"] == "applying"
        assert birinci["exact_on"] == "2026-08-18"
        assert birinci["days_to_exact"] == 2
        assert birinci["natal_sign"] == "cancer"
        assert birinci["natal_house"] == 4
        assert birinci["theme"] == "inner"  # Ay natal 4. evde

    def test_ev_temasi_ve_nokta_yedegi(self, monkeypatch):
        ham = _hesapla(monkeypatch)
        temalar = {(s["transit"], s["natal"]): s["theme"]
                   for s in ham["signals"]}
        assert temalar[("Uranus", "Medium_Coeli")] == "career"  # ev 10
        assert temalar[("Jupiter", "Venus")] == "finance"       # ev 8
        # Natal olgular yoksa nokta tabanlı temaya düşülür, alanlar uydurulmaz.
        monkeypatch.setattr(signal_service.chart_context, "natal_facts",
                            lambda birth: (_ for _ in ()).throw(RuntimeError))
        monkeypatch.setattr(signal_service.predict_service,
                            "transit_calendar", lambda **kw: SAHTE_TAKVIM)
        yedek = signal_service.compute_signals(DOGUM)
        ay = next(s for s in yedek["signals"] if s["natal"] == "Moon")
        assert ay["theme"] == "inner"
        assert "natal_sign" not in ay and "natal_house" not in ay

    def test_tema_kesin_tekil(self, monkeypatch):
        """KA-turu cihaz bulgusu: aynı temadan İKİNCİ kart ASLA çıkmaz.

        Eski davranış kullanılmamış tema kalmayınca temayı tekrar seçiyordu
        ve ekranda iki "İç dünya" kartı beliriyordu — kullanıcı tema
        etiketini kimlik okuyup "hangisi doğru?" diye sordu. Artık tema
        başına en güçlü tek olay kart olur; havuzda 3'ten az tema varsa
        3'ten az kart döner (fazla olaylar takvim şeridinde zaten var).
        """
        takvim = {**SAHTE_TAKVIM, "events": [], "active_now": [
            # İki güçlü kariyer adayı + bir zayıf ilişki adayı.
            {"transit": "Saturn", "natal": "Sun", "aspect": "conjunction",
             "orb": 0.3, "movement": "applying"},
            {"transit": "Uranus", "natal": "Medium_Coeli",
             "aspect": "square", "orb": 0.5, "movement": "applying"},
            {"transit": "Jupiter", "natal": "Venus", "aspect": "sextile",
             "orb": 2.8, "movement": "separating"},
        ]}
        natal = {**SAHTE_NATAL, "placements": [
            {"planet": "Venus", "sign": "aries", "house": 7}]}
        ham = _hesapla(monkeypatch, takvim=takvim, natal=natal)
        # 1: Satürn-Güneş (kariyer, en güçlü). 2: ilişkiler. İkinci
        # kariyer adayı KART OLMAZ — üç yerine iki kart.
        assert [s["theme"] for s in ham["signals"]] == [
            "career", "relationships"]


class TestYerellestirme:
    """Kart yüzeyinin sözleşmesi: AI yorumu (`insight`) istemcide tercih
    edilir; `headline` = dürüst teknik yedek (KA-turu)."""

    def test_kart_yedegi_durust_teknik_satir(self, monkeypatch):
        """KA-turu: `headline` artık tema×ton tablosundan GELMEZ — tablo
        silindi. Gündelik dil görevi herkese üretilen AI yorumunda
        (`insight`, istemci tercih eder); `headline` yalnız yorum yokken
        düşülen SON ÇARE ve o da uydurma değil, ölçülmüş teknik satırdır.

        Eski davranış cihazda ölçülen kusurdu: 12 sabit cümle, aynı
        ekranda iki özdeş kart + her sabah aynı bildirim üretiyordu.
        """
        ham = _hesapla(monkeypatch)
        birinci = prompts.localize_signals("tr", ham)["signals"][0]
        assert birinci["headline"] == birinci["technical"]
        assert birinci["theme_local"] == "İç dünya"
        assert birinci["timing_local"] == "18 Ağustos günü netleşiyor"
        ing = prompts.localize_signals("en", ham)["signals"][0]
        assert ing["headline"] == ing["technical"]
        assert ing["timing_local"] == "Peaks on August 18"

    def test_teknik_satir_dayanakta_durur(self, monkeypatch):
        """Teknik bilgi KAYBOLMAZ — 'Neye dayanıyor?' sayfasının ilk satırı.

        OT1.4: yaklaşan kesinleşme GERİ SAYIMLI ("{days} gün sonra") —
        satır yedek olarak bildirime düştüğünde bile günlük değişir."""
        ham = _hesapla(monkeypatch)
        birinci = prompts.localize_signals("tr", ham)["signals"][0]
        assert birinci["technical"] == (
            "Satürn, natal Ay ile Kare açısını 2 gün sonra (18 Ağustos) "
            "kesinleştiriyor.")
        assert birinci["natal_sign_local"] == "Yengeç"
        ing = prompts.localize_signals("en", ham)["signals"][0]
        assert ing["technical"] == (
            "Saturn perfects its Square to your natal Moon in 2 days "
            "(August 18).")

    def test_zamanlama_satirlari(self):
        bugun = {"generated_for": "2026-08-16", "signals": [
            {"transit": "Saturn", "natal": "Moon", "aspect": "square",
             "orb": 0.1, "movement": "applying", "active": True,
             "exact_on": "2026-08-16", "days_to_exact": 0,
             "theme": "inner", "tone": "tension"},
            {"transit": "Jupiter", "natal": "Sun", "aspect": "trine",
             "orb": 1.4, "movement": "separating", "active": True,
             "theme": "career", "tone": "support"},
        ]}
        yerel = prompts.localize_signals("tr", bugun)
        assert yerel["signals"][0]["timing_local"] == "Bugün kesinleşiyor"
        assert yerel["signals"][1]["timing_local"] == "Etkisi sönüyor"
        assert "bugün kesinleştiriyor" in yerel["signals"][0]["technical"]

    def test_ton_acidan_turetilir(self, monkeypatch):
        ham = _hesapla(monkeypatch)
        tonlar = {(s["transit"], s["aspect"]): s["tone"]
                  for s in ham["signals"]}
        assert tonlar[("Saturn", "square")] == "tension"
        assert tonlar[("Jupiter", "trine")] == "support"
        assert tonlar[("Uranus", "conjunction")] == "focus"

    def test_insight_oldugu_gibi_tasinir(self):
        veri = {"signals": [
            {"transit": "Saturn", "natal": "Moon", "aspect": "square",
             "orb": 1.0, "movement": "applying", "active": True,
             "theme": "inner", "insight": "Deneme yorumu."}]}
        yerel = prompts.localize_signals("tr", veri)
        assert yerel["signals"][0]["insight"] == "Deneme yorumu."


class TestYorumPaketi:
    """KA1: `insight_bundle` — N kart cümlesi + akşam sorusu, TEK çağrı.

    `days_to_exact=1` olan ilk sinyal `significant_signal`'ın "önemli gün"
    seçimidir; prompta "(bugünün odağı)" işaretiyle girer ve son satırdaki
    SORU ona bağlanır.
    """

    HAM = {"generated_for": "2026-08-16", "signals": [
        {"transit": "Saturn", "natal": "Moon", "aspect": "square",
         "orb": 0.8, "exact_on": "2026-08-18", "days_to_exact": 1,
         "movement": "applying", "theme": "inner"},
        {"transit": "Uranus", "natal": "Medium_Coeli",
         "aspect": "conjunction", "orb": 2.4, "movement": "separating",
         "theme": "career"},
    ]}

    def test_dogru_bicim_paket_doner(self, monkeypatch):
        monkeypatch.setattr(
            signal_service.gemini_service, "generate",
            lambda prompt, lang=None, **_: ("1. Birinci yorum.\n2. İkinci yorum."
                                       "\nSORU: Bugün nasıl geçti?"))
        paket = signal_service.insight_bundle(self.HAM, "tr")
        assert paket == {"insights": ["Birinci yorum.", "İkinci yorum."],
                         "checkin_question": "Bugün nasıl geçti?"}

    def test_numarali_soru_satiri_da_taninir(self, monkeypatch):
        """CANLI kusur (rev 00069, 18:13): model soruyu "3. SORU: ..."
        diye numaralayarak yazdı; numara soyulunca soru kart cümlesi
        sanılıp paket komple reddedildi ve kartlar teknik yedeğe düştü —
        kullanıcı ekranda gördü. Önek soyulmuş hâl de soru sayılmalı."""
        monkeypatch.setattr(
            signal_service.gemini_service, "generate",
            lambda prompt, lang=None, **_: ("1. Bir.\n2. İki."
                                       "\n3. SORU: Bugün nasıl geçti?"))
        paket = signal_service.insight_bundle(self.HAM, "tr")
        assert paket["insights"] == ["Bir.", "İki."]
        assert paket["checkin_question"] == "Bugün nasıl geçti?"

    def test_soru_tire_ise_none(self, monkeypatch):
        monkeypatch.setattr(
            signal_service.gemini_service, "generate",
            lambda prompt, lang=None, **_: "1. Bir.\n2. İki.\nSORU: -")
        paket = signal_service.insight_bundle(self.HAM, "tr")
        assert paket["insights"] == ["Bir.", "İki."]
        assert paket["checkin_question"] is None

    def test_emojili_soru_kabul_edilir(self, monkeypatch):
        """OB5: SORU satırına "en fazla bir emoji" izni verildi — emojili
        soru 120 sınırındaysa ayrıştırıcıdan AYNEN geçmeli (emoji çok
        baytlı; sınır karakter sayısıyla ölçülür, bayt ile değil)."""
        soru = "Bugün iç dünyanda bir kapanış görünüyordu — nasıl geçti? 🌙"
        assert len(soru) <= signal_service.CHECKIN_QUESTION_MAX
        monkeypatch.setattr(
            signal_service.gemini_service, "generate",
            lambda prompt, lang=None, **_: f"1. Bir.\n2. İki.\nSORU: {soru}")
        paket = signal_service.insight_bundle(self.HAM, "tr")
        assert paket["insights"] == ["Bir.", "İki."]
        assert paket["checkin_question"] == soru

    def test_soru_satiri_eksikse_kismi_kabul(self, monkeypatch):
        """Sabah bildirimi akşam sorusuna rehin olmaz: SORU satırı
        gelmezse yorumlar YİNE kabul edilir."""
        monkeypatch.setattr(signal_service.gemini_service, "generate",
                            lambda prompt, lang=None, **_: "1. Bir.\n2. İki.")
        paket = signal_service.insight_bundle(self.HAM, "tr")
        assert paket["insights"] == ["Bir.", "İki."]
        assert paket["checkin_question"] is None

    def test_uzun_soru_atilir_yorumlar_kalir(self, monkeypatch):
        uzun_soru = "SORU: " + "s" * 200
        monkeypatch.setattr(
            signal_service.gemini_service, "generate",
            lambda prompt, lang=None, **_: f"1. Bir.\n2. İki.\n{uzun_soru}")
        paket = signal_service.insight_bundle(self.HAM, "tr")
        assert paket["insights"] == ["Bir.", "İki."]
        assert paket["checkin_question"] is None

    def test_satir_sayisi_tutmazsa_none(self, monkeypatch):
        monkeypatch.setattr(signal_service.gemini_service, "generate",
                            lambda prompt, lang=None, **_: "1. Tek satır.")
        assert signal_service.insight_bundle(self.HAM, "tr") is None

    def test_asiri_uzun_satir_none(self, monkeypatch):
        uzun = "1. " + "ç" * 200 + "\n2. Kısa."
        monkeypatch.setattr(signal_service.gemini_service, "generate",
                            lambda prompt, lang=None, **_: uzun)
        assert signal_service.insight_bundle(self.HAM, "tr") is None

    def test_prompt_hareket_ve_odak_isaretleri_tasir(self, monkeypatch):
        """Ç-kusurunun kökü: cümle zamanlama etiketiyle çelişebiliyordu.
        Prompt artık her satıra movement ipucunu ve önemli sinyale odak
        işaretini koyar."""
        yakalanan = {}

        def sahte(prompt, lang=None, **_):
            yakalanan["prompt"] = prompt
            return "1. Bir.\n2. İki.\nSORU: -"

        monkeypatch.setattr(signal_service.gemini_service, "generate", sahte)
        signal_service.insight_bundle(self.HAM, "tr")
        p = prompts.get("tr")
        assert p.SIGNAL_PROMPT_APPLYING in yakalanan["prompt"]
        assert p.SIGNAL_PROMPT_SEPARATING in yakalanan["prompt"]
        assert p.SIGNAL_PROMPT_FOCUS_MARK in yakalanan["prompt"]

    def test_odak_yoksa_soru_kullanilmaz(self, monkeypatch):
        """"Önemli gün" hükmü determinist seçicinin: odak yokken modelin
        yine de yazdığı soru atılır — akşam bildirimi uydurma bir öneme
        bağlanmaz."""
        odaksiz = {"generated_for": "2026-08-16", "signals": [
            {"transit": "Saturn", "natal": "Moon", "aspect": "square",
             "orb": 2.5, "movement": "applying", "theme": "inner",
             "active": True}]}
        assert signal_service.significant_signal(odaksiz) is None
        monkeypatch.setattr(
            signal_service.gemini_service, "generate",
            lambda prompt, lang=None, **_: "1. Bir.\nSORU: Nasıl geçti?")
        paket = signal_service.insight_bundle(odaksiz, "tr")
        assert paket["insights"] == ["Bir."]
        assert paket["checkin_question"] is None

    def test_onemli_gun_secimi(self):
        # exact_on + days_to_exact <= 1 olan İLK sinyal.
        assert signal_service.significant_signal(self.HAM) == 0
        # Kesinleşme uzaktaysa: 1 numara aktif ve dar orb'luysa o.
        dar = {"signals": [{"transit": "Saturn", "natal": "Sun",
                            "aspect": "square", "orb": 0.5, "active": True}]}
        assert signal_service.significant_signal(dar) == 0
        # Ne kesinleşme ne dar orb: soru üretilmez.
        genis = {"signals": [{"transit": "Saturn", "natal": "Sun",
                              "aspect": "square", "orb": 2.5,
                              "active": True}]}
        assert signal_service.significant_signal(genis) is None

    def test_parmak_izi_tarih_ve_kumeye_bagli(self):
        iz1 = signal_service.signals_fingerprint(self.HAM)
        iz2 = signal_service.signals_fingerprint(
            {**self.HAM, "generated_for": "2026-08-17"})
        assert iz1 != iz2


class TestPaketOnbellegi:
    """KA1/KA2: uç ve bildirim AYNI önbelleği paylaşır; başarısızlık KISA
    ömürle yazılır (eski `[] 24 saat` zehirlenmesinin onarımı)."""

    HAM = TestYorumPaketi.HAM

    def _bellek(self, monkeypatch):
        import core.cache as cache_mod
        depo: dict = {}
        yazilan_ttl: dict = {}
        monkeypatch.setattr(cache_mod, "get", depo.get)

        def sahte_set(k, v, ttl_seconds=0, owner_uid=None):
            depo[k] = v
            yazilan_ttl[k] = ttl_seconds

        monkeypatch.setattr(cache_mod, "set", sahte_set)
        return depo, yazilan_ttl

    def test_ayni_gun_tek_uretim(self, monkeypatch):
        self._bellek(monkeypatch)
        sayac = {"n": 0}

        def sahte(prompt, lang=None, **_):
            sayac["n"] += 1
            return "1. Bir.\n2. İki.\nSORU: Nasıl geçti?"

        monkeypatch.setattr(signal_service.gemini_service, "generate", sahte)
        bir = signal_service.cached_insight_bundle(self.HAM, "tr")
        iki = signal_service.cached_insight_bundle(self.HAM, "tr")
        assert bir == iki and bir["insights"] == ["Bir.", "İki."]
        assert sayac["n"] == 1

    def test_yalniz_oku_uretmez(self, monkeypatch):
        self._bellek(monkeypatch)
        sayac = {"n": 0}

        def sahte(prompt, lang=None, **_):
            sayac["n"] += 1
            return "1. Bir.\n2. İki.\nSORU: -"

        monkeypatch.setattr(signal_service.gemini_service, "generate", sahte)
        assert signal_service.cached_insight_bundle(
            self.HAM, "tr", generate_if_missing=False) is None
        assert sayac["n"] == 0  # akşam yolu LLM yakmaz

    def test_basarisizlik_kisa_ttl_ile_yazilir(self, monkeypatch):
        depo, ttl = self._bellek(monkeypatch)
        monkeypatch.setattr(signal_service.gemini_service, "generate",
                            lambda prompt, lang=None, **_: "bozuk çıktı")
        assert signal_service.cached_insight_bundle(self.HAM, "tr") is None
        anahtar = next(iter(depo))
        assert depo[anahtar].get("failed") is True
        assert ttl[anahtar] == signal_service.BUNDLE_TTL_FAIL
        # Başarı 24 saatle yazılır.
        depo.clear(); ttl.clear()
        monkeypatch.setattr(
            signal_service.gemini_service, "generate",
            lambda prompt, lang=None, **_: "1. Bir.\n2. İki.\nSORU: -")
        assert signal_service.cached_insight_bundle(self.HAM, "tr")
        anahtar = next(iter(depo))
        assert ttl[anahtar] == signal_service.BUNDLE_TTL_OK


class TestTakvimYorumu:
    """Ç1/Ç6: `calendar_insights` — `signal_insights`'la (R2-S1) BİREBİR
    AYNI biçim/doğrulama deseninde çalışır, ama eşleşme SIRAYLA değil
    `event_fingerprint` KİMLİĞİYLE yapılır (takvim olayları sinyaller gibi
    sabit-3'lük bir liste değil).

    `test_cakisma_bekcisi_farkli_olaylar_farkli_cumle_alir` bu turun ÖLÇÜLMÜŞ
    kusurunu birebir yakalar: eskiden `SIGNAL_HUMAN_LINES` (4 tema × 3 ton
    = 12 sabit cümle) yüzünden 30 günlük takvimde birçok farklı astrolojik
    olay (özellikle "iç dünya"/Ay simgesi teması) BİREBİR AYNI cümleye
    düşüyordu; bir örnek haritada bir günde üç olay aynı cümleyi üç kez
    gösterdi.
    """

    OLAYLAR = [
        {"date": "2026-08-18", "type": "aspect_exact", "transit": "Saturn",
         "natal": "Moon", "aspect": "square", "theme": "inner",
         "tone": "tension"},
        {"date": "2026-08-20", "type": "aspect_exact", "transit": "Uranus",
         "natal": "Mercury", "aspect": "conjunction", "theme": "inner",
         "tone": "focus"},
        {"date": "2026-09-10", "type": "aspect_exact", "transit": "Neptune",
         "natal": "Sun", "aspect": "square", "theme": "inner",
         "tone": "tension"},
        # İstasyonun teması yok — havuzdan düşmeli (SIGNAL_HUMAN_LINES'ta
        # istasyonların zaten hiç cümlesi yoktu, bu yeni fonksiyonda da
        # olmamalı).
        {"date": "2026-08-25", "type": "station_retrograde",
         "transit": "Pluto"},
    ]

    def test_dogru_bicimde_parmak_izine_eslenir(self, monkeypatch):
        monkeypatch.setattr(
            signal_service.gemini_service, "generate",
            lambda prompt, lang=None, **_: "1. Birinci.\n2. İkinci.\n3. Üçüncü.")
        yorumlar = signal_service.calendar_insights(self.OLAYLAR, "tr")
        assert len(yorumlar) == 3
        for o, beklenen in zip(self.OLAYLAR[:3],
                               ["Birinci.", "İkinci.", "Üçüncü."]):
            assert yorumlar[signal_service.event_fingerprint(o)] == beklenen

    def test_istasyon_ve_temasiz_olay_promptan_cikar(self, monkeypatch):
        yakalanan = {}

        def sahte_uret(prompt, lang=None, **_):
            yakalanan["prompt"] = prompt
            return "1. Birinci.\n2. İkinci.\n3. Üçüncü."

        monkeypatch.setattr(signal_service.gemini_service, "generate",
                            sahte_uret)
        signal_service.calendar_insights(self.OLAYLAR, "tr")
        assert "Pluto" not in yakalanan["prompt"]

    def test_satir_sayisi_tutmazsa_none(self, monkeypatch):
        monkeypatch.setattr(signal_service.gemini_service, "generate",
                            lambda prompt, lang=None, **_: "1. Tek satır.")
        assert signal_service.calendar_insights(self.OLAYLAR, "tr") is None

    def test_asiri_uzun_satir_none(self, monkeypatch):
        uzun = "1. " + "ç" * 200 + "\n2. Kısa.\n3. Kısa."
        monkeypatch.setattr(signal_service.gemini_service, "generate",
                            lambda prompt, lang=None, **_: uzun)
        assert signal_service.calendar_insights(self.OLAYLAR, "tr") is None

    def test_temali_olay_yoksa_cagirmadan_none(self, monkeypatch):
        """Yalnız istasyon varsa LLM'e hiç gidilmez — boşuna harcama yok."""
        cagrildi = {"n": 0}

        def sahte_uret(prompt, lang=None, **_):
            cagrildi["n"] += 1
            return "1. x"

        monkeypatch.setattr(signal_service.gemini_service, "generate",
                            sahte_uret)
        istasyonlar = [o for o in self.OLAYLAR if o["type"] != "aspect_exact"]
        assert signal_service.calendar_insights(istasyonlar, "tr") is None
        assert cagrildi["n"] == 0

    def test_yigin_ust_siniri_uygulanir(self, monkeypatch):
        """20'den fazla açı-kesinleşmesi verilse bile yalnız ilk
        CALENDAR_INSIGHT_MAX_EVENTS kadarı promta girer — maliyet tavanı
        (Ç-turu ölçümü: gerçek 30-90 günlük takvimlerde 3-17 olay çıktı)."""
        cok = [{"date": f"2026-{(i % 12) + 1:02d}-10", "type": "aspect_exact",
               "transit": "Saturn", "natal": f"Point{i}", "aspect": "square",
               "theme": "inner"} for i in range(30)]
        yakalanan = {}

        def sahte_uret(prompt, lang=None, **_):
            yakalanan["prompt"] = prompt
            n = signal_service.CALENDAR_INSIGHT_MAX_EVENTS
            return "\n".join(f"{i}. Yorum {i}." for i in range(1, n + 1))

        monkeypatch.setattr(signal_service.gemini_service, "generate",
                            sahte_uret)
        yorumlar = signal_service.calendar_insights(cok, "tr")
        assert len(yorumlar) == signal_service.CALENDAR_INSIGHT_MAX_EVENTS
        assert "Point20" not in yakalanan["prompt"]  # 21. olay dışarda kaldı

    def test_cakisma_bekcisi_farkli_olaylar_farkli_cumle_alir(
            self, monkeypatch):
        """Bu turun ölçülen kusurunu birebir yakalar (bkz. sınıf docstring).

        Beşi de 'inner' temasında — eski tabloda hepsi aynı 1-2 cümleye
        düşerdi. Burada model beş FARKLI cümle üretir (sahtelenmiş) ve
        fonksiyonun bunları beş AYRI olaya, birbirine karıştırmadan
        eşlediği doğrulanır: ne çakışma (aynı cümle iki olaya), ne kayıp
        (bir olay cümlesiz kalması).
        """
        genis_takvim = [
            {"date": f"2026-09-{d:02d}", "type": "aspect_exact",
             "transit": t, "natal": n, "aspect": "square", "theme": "inner"}
            for d, (t, n) in enumerate(
                [("Uranus", "Mercury"), ("Uranus", "Venus"),
                 ("Neptune", "Sun"), ("Neptune", "Ascendant"),
                 ("Pluto", "Moon")], start=1)
        ]
        monkeypatch.setattr(
            signal_service.gemini_service, "generate",
            lambda prompt, lang=None, **_: "\n".join(
                f"{i}. Bu olaya özgü {i}. cümle." for i in range(1, 6)))
        yorumlar = signal_service.calendar_insights(genis_takvim, "tr")
        assert len(yorumlar) == 5
        assert len(set(yorumlar.values())) == 5  # tekrar YOK
        for i, o in enumerate(genis_takvim, 1):
            assert yorumlar[signal_service.event_fingerprint(o)] == (
                f"Bu olaya özgü {i}. cümle.")


class TestTakvimParmakIzi:
    """`event_fingerprint` + `calendar_fingerprint`: önbellek anahtarının
    dayandığı kararlı kimlik."""

    def test_event_fingerprint_kararli_ve_ayirt_edici(self):
        o1 = {"transit": "Saturn", "natal": "Moon", "aspect": "square",
              "date": "2026-08-18"}
        o2 = {**o1}
        o3 = {**o1, "date": "2026-09-07"}  # yalnız tarih farklı
        assert signal_service.event_fingerprint(o1) == \
            signal_service.event_fingerprint(o2)
        assert signal_service.event_fingerprint(o1) != \
            signal_service.event_fingerprint(o3)

    def test_calendar_fingerprint_farkli_kumeler_farkli_iz(self):
        temel = [{"type": "aspect_exact", "theme": "inner",
                  "transit": "Saturn", "natal": "Moon", "aspect": "square",
                  "date": "2026-08-18"}]
        genisletilmis = temel + [{"type": "aspect_exact", "theme": "career",
                                  "transit": "Jupiter", "natal": "Sun",
                                  "aspect": "trine", "date": "2026-08-20"}]
        assert signal_service.calendar_fingerprint(temel) != \
            signal_service.calendar_fingerprint(genisletilmis)

    def test_calendar_fingerprint_istasyonu_ve_temasizi_saymaz(self):
        """İmzaya yalnız temalı açı-kesinleşmeleri girer — istasyon
        değişse de takvim yorumu önbelleği boşuna tazelenmemeli."""
        temel = [{"type": "aspect_exact", "theme": "inner",
                  "transit": "Saturn", "natal": "Moon", "aspect": "square",
                  "date": "2026-08-18"}]
        istasyonlu = temel + [{"type": "station_retrograde",
                               "transit": "Pluto", "date": "2026-08-25"}]
        temasiz = temel + [{"type": "aspect_exact", "transit": "Mars",
                            "natal": "Sun", "aspect": "opposition",
                            "date": "2026-08-19"}]  # theme yok
        assert signal_service.calendar_fingerprint(temel) == \
            signal_service.calendar_fingerprint(istasyonlu)
        assert signal_service.calendar_fingerprint(temel) == \
            signal_service.calendar_fingerprint(temasiz)


class TestSignalHumanLinesKapsami:
    """KA2 regresyon bekçisi: `SIGNAL_HUMAN_LINES` artık HİÇBİR YERDE yok.

    Ç-turu tabloyu takvimden kaldırıp kartlarda "risk düşük" diye
    bırakmıştı; cihazda iki özdeş kart + her sabah aynı bildirim olarak
    geri döndü. Kullanıcı kararı: hazır cümle asla — yorum herkese AI,
    son çare dürüst teknik satır. Biri tabloyu geri yapıştırırsa bu
    testler kırılır.
    """

    def test_tablo_modullerde_yok(self):
        for lang in ("tr", "en"):
            assert not hasattr(prompts.get(lang), "SIGNAL_HUMAN_LINES"), lang

    def test_yerellestirme_tabloya_erismez(self):
        """`.SIGNAL_HUMAN_LINES` ERİŞİMİ (gerçek kullanım) aranır — geçmişi
        anlatan yorumlardaki tırnaksız anma bilerek dışarıda bırakılır."""
        import inspect
        for fonksiyon in (prompts.localize_signals,
                          prompts.localize_transit_calendar):
            assert ".SIGNAL_HUMAN_LINES" not in inspect.getsource(fonksiyon)


class TestTakvimZenginlestirme:
    """R2-Z1: 90 günlük takvim olayları sinyallerle aynı tema/ton dilini
    taşır; istasyonlara tema UYDURULMAZ."""

    OLAYLAR = [
        {"date": "2026-08-18", "type": "aspect_exact", "transit": "Saturn",
         "natal": "Moon", "aspect": "square", "orb": 0.1},
        {"date": "2026-08-20", "type": "station_retrograde",
         "transit": "Uranus"},
    ]

    def test_kesinlesme_tema_ton_alir_istasyon_almaz(self):
        zengin = signal_service.enrich_events(self.OLAYLAR, SAHTE_NATAL)
        kesin, istasyon = zengin
        assert kesin["theme"] == "inner" and kesin["tone"] == "tension"
        assert kesin["natal_sign"] == "cancer"
        assert "theme" not in istasyon and "tone" not in istasyon

    def test_natal_yoksa_temasiz_ama_cokmez(self):
        zengin = signal_service.enrich_events(self.OLAYLAR, None)
        assert zengin[0]["theme"] == "inner"  # nokta tabanlı yedek (Ay)
        assert "natal_sign" not in zengin[0]

    def test_yerellestirme_teknik_hep_var_line_onceden_yazilirsa_gecer(self):
        """Ç-turu: `line` artık tema×ton tablosundan DEĞİL, olaya ÖNCEDEN
        yazılmış AI metninden gelir (`api/astrology.py`'nin
        `calendar_insights` sonucunu olaya yazdığı yer). Bu fonksiyon
        yalnız TAŞIR — kendi başına üretmez.

        Ölçülen kusur tam olarak buydu: eskiden burası tema+ton'a bakıp
        12 sabit cümleden birini seçiyordu ve 30 günde birçok farklı olay
        birebir aynı cümleye düşüyordu.
        """
        zengin = signal_service.enrich_events(self.OLAYLAR, SAHTE_NATAL)
        cal = {"start": "2026-08-16", "days": 90, "events": zengin,
               "active_now": [], "disclosures": []}
        yerel = prompts.localize_transit_calendar("tr", cal)
        kesin = yerel["events"][0]
        # Teknik dayanak HER ZAMAN üretilir (tema+ton'dan bağımsız,
        # `SIGNAL_LINE_EXACT` şablonundan) — bu değişmedi.
        assert kesin["theme_local"] == "İç dünya"
        assert "Satürn" in kesin["technical"]
        assert kesin["date_local"] == "18 Ağustos"
        # `line` önceden yazılmadıysa BOŞ kalır — sabit cümleye DÜŞMEZ.
        assert kesin["line"] == ""
        # İstasyon satırı ARTIK `line` TAŞIYOR — bu bilinçli bir değişiklik.
        #
        # Eski hâl `assert "line" not in istasyon` idi ve gerekçesi doğruydu:
        # istasyon kişisel bir natal noktaya bağlanmadığı için ona TEMA
        # uydurmak "ölçülmeyen söylenmez"i ihlal ederdi. Ama sahibin isteği o
        # kuralı ihlal ETMİYOR: kişisel tema değil, HAREKETİN KENDİSİNİN ne
        # demek olduğu isteniyor. "Plüton temeli söker ve yeniden döker"
        # cümlesi PLÜTON HAKKINDADIR, kullanıcı hakkında değil — ölçülmüş ve
        # doğru. Cihazda şikâyet edilen hâl şuydu: gün sayfasında yalnız
        # "Plüton — ileri harekete dönüş" yazıyor, anlamı hiç yok.
        #
        # Kaynak metin uydurma değil: `knowledge/corpus/tr/tahmin_doktrin.md`
        # (`license: rytho-original`) altı yavaş gezegenin temasını ve istasyon
        # doktrinini zaten yazıyor; tablo oradan türetildi ve 6 tema × 2 yön
        # olarak ÇARPILIYOR (12 dize elle yazılmadı).
        istasyon = yerel["events"][1]
        assert istasyon["line"], "istasyon anlam cümlesi üretilmiyor"
        assert istasyon["technical"], "istasyonun sebep satırı üretilmiyor"
        assert istasyon["type_local"] == "retroya dönüş"
        # ⚠️ ASIL KAPI: cümle KİŞİSELLEŞTİRİLMEZ. Bunu kaybetmek, yukarıdaki
        # eski kuralın haklı olduğu zemine geri düşmek olurdu.
        for yasak in ("senin", "haritanda", "sana ", "haritandaki"):
            assert yasak not in istasyon["line"].lower(), (
                f"istasyon cümlesi kişiselleştirilmiş ({yasak!r}): hareket "
                f"herkes için aynı, kullanıcının haritasına bağlı değil")

    def test_onceden_yazilmis_ai_metni_oldugu_gibi_tasinir(self):
        """`api/astrology.py` `line`'ı olaya YAZDIKTAN SONRA çağırır —
        localize bunu değiştirmeden geçirmeli."""
        zengin = signal_service.enrich_events(self.OLAYLAR, SAHTE_NATAL)
        zengin[0] = {**zengin[0], "line": "Bu çift o güne özgü bir cümle."}
        cal = {"start": "2026-08-16", "days": 90, "events": zengin,
               "active_now": [], "disclosures": []}
        yerel = prompts.localize_transit_calendar("tr", cal)
        assert yerel["events"][0]["line"] == "Bu çift o güne özgü bir cümle."


PROFIL = {"uid": "u1", "birthDate": "1990-05-12", "birthTime": "14:30",
          "birthCity": "Istanbul", "displayName": "t"}


class TestSinyalUcu:
    """KA1: /reports/signals — yorum HERKESE (abonelik kapısı KALKTI) ve
    yanıt derin bağlantı için `fingerprint` + akşam için
    `checkin_question` taşır."""

    def test_ucretsiz_kullanici_da_yorum_alir(self, monkeypatch):
        import pytest
        try:
            from main import app
        except Exception as exc:  # pragma: no cover - ortama bağlı
            pytest.skip(f"FastAPI uygulaması içe aktarılamadı: {exc}")
        from fastapi.testclient import TestClient
        from api import reports
        from core import entitlements
        from services import profile_service

        monkeypatch.setattr(entitlements, "FORCE_PLUS", False)
        # AÇIKÇA abone DEĞİL — eski kodda bu kullanıcı yorumsuz kalırdı.
        monkeypatch.setattr(reports.entitlements, "is_subscriber",
                            lambda uid: False)
        monkeypatch.setattr(profile_service, "get_profile",
                            lambda uid: dict(PROFIL))
        ham = {"generated_for": "2026-08-16", "signals": [
            {"transit": "Saturn", "natal": "Moon", "aspect": "square",
             "orb": 0.8, "exact_on": "2026-08-18", "days_to_exact": 1,
             "movement": "applying", "theme": "inner", "tone": "tension"},
        ], "disclosures": []}
        monkeypatch.setattr(signal_service, "cached_signals",
                            lambda profile, today=None: ham)
        monkeypatch.setattr(
            signal_service, "cached_insight_bundle",
            lambda h, lang, generate_if_missing=True: {
                "insights": ["Bugüne özgü cümle."],
                "checkin_question": "Bugün nasıl geçti?"})

        with TestClient(app) as client:
            yanit = client.get("/api/v1/reports/signals",
                               headers={"Authorization": "Bearer test-sig"})
        assert yanit.status_code == 200, yanit.text
        veri = yanit.json()["data"]
        assert veri["signals"][0]["insight"] == "Bugüne özgü cümle."
        assert veri["fingerprint"]
        assert veri["checkin_question"] == "Bugün nasıl geçti?"


@pytest.fixture(autouse=True)
def ai_onayi_verilmis(monkeypatch):
    """Bu dosya AI bildirim satırının KENDİSİNİ sınıyor; kullanıcı onay
    vermiş sayılır. Arka plan yolu kayıtsız yeni kullanıcıya AI satırı
    göndermediği için (U06, `arka_plan_karari`) pinsiz profiller teknik
    satıra düşerdi. Onay kapısının kendisi test_ai_consent.py'de."""
    from core import ai_consent
    monkeypatch.setattr(ai_consent, "arka_plan_izni_var",
                        lambda uid, build: True)


class TestOnbellekVeBildirim:
    def test_cached_signals_gunde_bir_hesaplar(self, monkeypatch):
        """Uç ve bildirim aynı kaydı paylaşır: ikinci çağrı hesap yapmaz.

        Önbellek BELLEK-İÇİ sahteyle izole edilir: gerçek katman kalıcı
        (dosya/Firestore) olduğu için sabit anahtar önceki test KOŞUSUNDAN
        dönebilir ve sayaç hiç artmazdı (tam takımda bir kez düştü).
        """
        import datetime as dt
        import core.cache as cache_mod
        depo: dict = {}
        monkeypatch.setattr(cache_mod, "get", depo.get)
        monkeypatch.setattr(
            cache_mod, "set",
            lambda k, v, ttl_seconds=0, owner_uid=None: depo.update({k: v}))

        sayac = {"n": 0}

        def sahte_hesap(birth, hour_known=True):
            sayac["n"] += 1
            return {"calc_version": "1", "generated_for": "2099-01-01",
                    "signals": [], "disclosures": []}

        monkeypatch.setattr(signal_service, "compute_signals", sahte_hesap)
        gun = dt.date(2099, 1, 1)
        birinci = signal_service.cached_signals(PROFIL, today=gun)
        ikinci = signal_service.cached_signals(PROFIL, today=gun)
        assert birinci == ikinci
        assert sayac["n"] == 1

    def test_cached_signals_dogum_verisi_yoksa_none(self):
        assert signal_service.cached_signals({"uid": "u2"}) is None

    HAM_SINYAL = {"generated_for": "2026-08-16", "signals": [
        {"transit": "Saturn", "natal": "Moon", "aspect": "square",
         "orb": 0.8, "movement": "applying", "active": True,
         "exact_on": "2026-08-18", "days_to_exact": 2,
         "theme": "inner", "tone": "tension"}], "disclosures": []}

    def test_bildirim_bir_numarali_sinyalin_ai_yorumu(self, monkeypatch):
        """KA2: sabah bildirimi artık sabit tablo DEĞİL, o güne özgü AI
        cümlesi (uçla paylaşılan paket). Eski davranışta tema+ton
        haftalarca sabit kaldığı için herkese her sabah birebir aynı
        metin gidiyordu — kullanıcının cihaz bulgusu."""
        from services import notification_service
        monkeypatch.setattr(signal_service, "cached_signals",
                            lambda profile, today=None: self.HAM_SINYAL)
        monkeypatch.setattr(
            signal_service, "cached_insight_bundle",
            lambda ham, lang, generate_if_missing=True: {
                "insights": ["Bugüne özgü tek cümle."],
                "checkin_question": None})
        baslik, govde, iz, idx, extra = notification_service.signal_push(
            PROFIL, "tr")
        # OB5: başlık tema emojisi taşır (THEME_EMOJIS — mobil kThemeIcons
        # ile aynı dörtlü).
        assert baslik == "🌙 Bugün: İç dünya"
        assert govde == "Bugüne özgü tek cümle."
        assert iz  # derin bağlantı eşleşmesi için parmak izi taşır
        # OT1.1: hafıza alanları gönderilen gövdeyi ve odağı taşır.
        assert idx == 0
        assert extra["dailyBody"] == govde
        assert extra["dailyTheme"] == "inner"

    def test_bildirim_paket_yoksa_teknik_satira_duser(self, monkeypatch):
        """AI üretilemezse gövde SABİT CÜMLE DEĞİL dürüst teknik satır —
        o da ölçülmüş veridir ve tarih içerdiği için günden güne değişir."""
        from services import notification_service
        monkeypatch.setattr(signal_service, "cached_signals",
                            lambda profile, today=None: self.HAM_SINYAL)
        monkeypatch.setattr(
            signal_service, "cached_insight_bundle",
            lambda ham, lang, generate_if_missing=True: None)
        baslik, govde, iz, _idx, _extra = notification_service.signal_push(
            PROFIL, "tr")
        # OT1.4: yaklaşan kesinleşme GERİ SAYIMLI yazılır ({days} her gün
        # azalır) — sabit tarihli satır iki kötü sabahda bayt-aynıydı.
        assert govde == ("Satürn, natal Ay ile Kare açısını 2 gün sonra "
                         "(18 Ağustos) kesinleştiriyor.")

    def test_bildirim_sinyal_yoksa_none(self, monkeypatch):
        """None dönüşü çağıranı paylaşımlı burç satırına düşürür."""
        from services import notification_service
        monkeypatch.setattr(signal_service, "cached_signals",
                            lambda profile, today=None: None)
        assert notification_service.signal_push(PROFIL, "tr") is None

    def test_bildirim_uzun_yorumda_teknige_duser(self, monkeypatch):
        """Taşan AI cümlesi kırpılıp gönderilmez (yarım cümle kuralı) —
        teknik satıra düşülür; o da taşarsa bildirim None."""
        from services import notification_service
        monkeypatch.setattr(signal_service, "cached_signals",
                            lambda profile, today=None: self.HAM_SINYAL)
        monkeypatch.setattr(
            signal_service, "cached_insight_bundle",
            lambda ham, lang, generate_if_missing=True: {
                "insights": ["u" * 200], "checkin_question": None})
        baslik, govde, iz, _idx, _extra = notification_service.signal_push(
            PROFIL, "tr")
        assert govde.startswith("Satürn, natal Ay ile")

    def test_checkin_push_yalniz_onbellekten(self, monkeypatch):
        """KA4: akşam sorusu önbellekten OKUNUR; yoksa None döner ve
        üretim HİÇ tetiklenmez (akşam LLM yakmaz)."""
        from services import notification_service
        monkeypatch.setattr(signal_service, "cached_signals",
                            lambda profile, today=None: self.HAM_SINYAL)
        cagrilar = []

        def sahte_paket(ham, lang, generate_if_missing=True):
            cagrilar.append(generate_if_missing)
            if generate_if_missing:
                return {"insights": ["x"], "checkin_question": "Soru?"}
            return None

        monkeypatch.setattr(signal_service, "cached_insight_bundle",
                            sahte_paket)
        assert notification_service.checkin_push(PROFIL, "tr") is None
        assert cagrilar == [False]  # yalnız-oku ile çağrıldı

        monkeypatch.setattr(
            signal_service, "cached_insight_bundle",
            lambda ham, lang, generate_if_missing=True: {
                "insights": ["x"], "checkin_question": "Bugün nasıl geçti?"})
        icerik = notification_service.checkin_push(PROFIL, "tr")
        assert icerik.govde == "Bugün nasıl geçti?"
        assert icerik.baslik == "🔮 Rytho merak ediyor"  # OB5 emoji başlığı
        # SS-turu: gövde `checkin_question` alanından geliyor, yani tanım
        # gereği SORU. Ayrımı üretici beyan eder; notify.py tür adına
        # bakmaz.
        assert icerik.soru is True

    def test_bildirim_hatada_dusmez(self, monkeypatch):
        """Sinyal hesabı düşerse bildirim düşmez; None ile yedeğe geçilir."""
        from services import notification_service
        monkeypatch.setattr(
            signal_service, "cached_signals",
            lambda profile, today=None: (_ for _ in ()).throw(RuntimeError))
        assert notification_service.signal_push(PROFIL, "tr") is None

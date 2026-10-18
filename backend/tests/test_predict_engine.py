"""Tahmin katmanı altın vektörleri (T1+).

Efemeris T0'da DIŞ almanak çapalarına bağlandı (ekinoks/kavuşum/tutulma);
buradaki testler çözücüleri TANIMLARINA karşı doğrular: solar return anı,
tanımı gereği Güneş'in natal boylamına döndüğü andır — iki taraf da aynı
(dışarıdan çapalanmış) efemerisi kullandığı için bu bileşim geçerli bir
doğrulamadır.
"""
from __future__ import annotations

import datetime as dt

from services import astro_service, predict_service


def _natal_gunes(y, m, d, hh, mm, city="Istanbul"):
    chart = astro_service.get_natal_chart("t", y, m, d, hh, mm, city)
    for p in chart["points"]:
        if p["name"] == "Sun":
            return p["abs_position"]
    raise AssertionError("Güneş yok")


class TestSolarReturn:
    def test_donus_ani_tanimi(self):
        """SR anında Güneş boylamı == natal Güneş boylamı (çözücü tanımı)."""
        natal_boylam = _natal_gunes(1990, 5, 12, 14, 30)
        sr = predict_service.solar_return(
            "t", 1990, 5, 12, 14, 30, "Istanbul", target_year=2025)
        an = dt.datetime.fromisoformat(sr["return_at_utc"])
        # Dönüş anındaki Güneş'i motorla yeniden hesapla. Motor YEREL saat
        # bekler: Londra Mayıs'ta BST'dedir (UTC+1) — UTC saatini çevirmeden
        # geçirmek tam 1 saatlik (≈0.04°) kaymaya yol açıyordu.
        from zoneinfo import ZoneInfo
        yerel = an.astimezone(ZoneInfo("Europe/London"))
        sr_gunes = _natal_gunes(yerel.year, yerel.month, yerel.day,
                                yerel.hour, yerel.minute, city="Londra")
        fark = abs(sr_gunes - natal_boylam)
        fark = min(fark, 360 - fark)
        # Dakika yuvarlaması Güneş'te en fazla ~0.0007°/dk → bol pay.
        assert fark < 0.02

    def test_aktif_gecmiste_sonraki_gelecekte(self):
        sr = predict_service.solar_return(
            "t", 1990, 5, 12, 14, 30, "Istanbul")
        simdi = dt.datetime.now(dt.timezone.utc)
        aktif = dt.datetime.fromisoformat(sr["return_at_utc"])
        assert aktif <= simdi
        # Sonraki dönüş aktiften ~1 yıl sonra (365 ± 2 gün).
        sonraki = dt.datetime.fromisoformat(sr["next_return_at_local"])
        gun_fark = (sonraki.replace(tzinfo=None)
                    - aktif.replace(tzinfo=None)).days
        assert 363 <= gun_fark <= 367

    def test_saatsizlik_asc_uretmez_ve_beyan_tasir(self):
        """Dürüstlük değişmezi: saat yoksa SR ASC/ev alanları HİÇ yok."""
        sr = predict_service.solar_return(
            "t", 1990, 5, 12, 12, 0, "Istanbul", hour_known=False)
        assert "sr_ascendant" not in sr
        assert "sr_sun_house" not in sr
        assert "sr_hour_unknown" in sr["disclosures"]
        # 2026-10-18: gezegen başına ev de gitmiyor (öğlene göre
        # hesaplanmış ev ölçülmüş gibi görünürdü) ve köşe açısı yok.
        assert all("house_no" not in p and "house" not in p
                   for p in sr["points"])
        assert not [a for a in sr["aspects"]
                    if {a.get("p1"), a.get("p2")} & predict_service._KOSELER]
        saatli = predict_service.solar_return(
            "t", 1990, 5, 12, 12, 0, "Istanbul")
        assert any(p.get("house_no") for p in saatli["points"])

    def test_hedef_yil_secimi(self):
        sr = predict_service.solar_return(
            "t", 1990, 5, 12, 14, 30, "Istanbul", target_year=2020)
        assert sr["return_at_utc"].startswith("2020-05-1")

    def test_relocation_ani_degistirmez_haritayi_degistirir(self):
        """D3: yıl haritası yaşanan şehre kurulur.

        Dönüş ANI evrensel bir olaydır (Güneş natal boylamına döner) ve
        konumdan bağımsızdır; değişen Yükselen, MC ve evlerdir. Ölçüm:
        aynı anda İstanbul'da İkizler, Sydney'de Terazi yükseliyor.
        """
        dogum = ("t", 1990, 5, 12, 14, 30, "Istanbul")
        ev = predict_service.solar_return(*dogum, target_year=2026)
        uzak = predict_service.solar_return(*dogum, target_year=2026,
                                            relocation_city="Sydney")

        assert ev["return_at_utc"] == uzak["return_at_utc"]
        assert ev["sr_moon_sign"] == uzak["sr_moon_sign"]  # burçlar evrensel
        assert ev["sr_ascendant"] != uzak["sr_ascendant"]
        assert uzak["location"]["city"] == "Sydney"
        assert uzak["location"]["relocated"] is True

    def test_relocation_beyanlari(self):
        dogum = ("t", 1990, 5, 12, 14, 30, "Istanbul")
        ev = predict_service.solar_return(*dogum, target_year=2026)
        assert "sr_birthplace_fallback" in ev["disclosures"]

        uzak = predict_service.solar_return(*dogum, target_year=2026,
                                            relocation_city="Sydney")
        assert "sr_relocated" in uzak["disclosures"]
        # Metin şehri TAŞIMALI — sabit cümle "bir yere kuruldu" derdi.
        from services import prompts
        metinler = prompts.localize_chart("tr", uzak)["disclosure_texts"]
        assert any("Sydney" in m for m in metinler)

    def test_beyan_iki_sehri_de_anar(self):
        """R5-5: cihaz turunda Urfa doğumlu / Ankara'da yaşayan kullanıcı
        "yıl haritası doğum gününde bulunulan yere kurulur" beyanını okuyup
        kendi doğum yeriyle ilişkilendiremedi. Hesap doğruydu, anlatım
        eksikti — beyan artık İKİ şehri de adıyla anar."""
        from services import prompts
        uzak = predict_service.solar_return(
            "t", 1990, 5, 12, 14, 30, "Sanliurfa", target_year=2026,
            relocation_city="Ankara")

        assert uzak["location"]["birth_city"]
        for dil in ("tr", "en"):
            metin = " ".join(
                prompts.localize_chart(dil, uzak)["disclosure_texts"])
            assert "Ankara" in metin, dil
            assert uzak["location"]["birth_city"] in metin, dil
            # Biçim alanı ham kalmamalı.
            assert "{" not in metin, dil

    def test_beyanda_dogum_sehri_yoksa_ham_alan_kalmaz(self):
        """Eski önbellek kayıtlarında `birth_city` yok; metin yine kurulur."""
        from services import prompts
        eski = {"disclosures": ["sr_relocated"],
                "location": {"city": "Ankara"}}
        metin = prompts.localize_chart("tr", eski)["disclosure_texts"][0]
        assert "{birth_city}" not in metin
        assert "Ankara" in metin

    def test_saatsizlikte_konum_beyani_yok(self):
        """Saat yoksa ASC/ev zaten üretilmiyor; konumu anmak yanıltıcı."""
        sr = predict_service.solar_return(
            "t", 1990, 5, 12, 12, 0, "Istanbul", hour_known=False,
            target_year=2026, relocation_city="Sydney")
        assert "sr_relocated" not in sr["disclosures"]
        assert "sr_birthplace_fallback" not in sr["disclosures"]
        assert "sr_hour_unknown" in sr["disclosures"]

    def test_sr_gunes_evi_sayi(self):
        """Ev alanı SAYI döner — kerykeion'un "Tenth_House" metni değil.

        Metin sızarsa mobil int cast'i çöker ve prompt'a İngilizce ev adı
        girer; bu test o gerilemeyi tutar.
        """
        sr = predict_service.solar_return(
            "t", 1990, 5, 12, 14, 30, "Istanbul", target_year=2025)
        assert isinstance(sr["sr_sun_house"], int)
        assert 1 <= sr["sr_sun_house"] <= 12

    def test_cozulmeyen_sehir_beyani(self):
        sr = predict_service.solar_return(
            "t", 1990, 5, 12, 14, 30, "BilinmeyenKoy", target_year=2025)
        assert "geo_fallback_city" in sr["disclosures"]


class TestProgresyon:
    """T2 — gün-yıl kuralı: iki bağımsız kaynak.

    (1) Aritmetik EL HESABI: doğumdan tam N×365.2425 gün sonrası için
    progres an, doğum + tam N gün olmalı — motorsuz doğrulanabilir.
    (2) TANIM: progres harita, kaydırılmış tarihe DOĞRUDAN kurulan natal
    haritayla aynı olmalı (efemeris T0'da dışarıdan çapalı).
    """

    _DOGUM_UTC = dt.datetime(1990, 5, 12, 11, 30, tzinfo=dt.timezone.utc)
    # 1990 Mayıs'ında İstanbul yaz saatinde (UTC+3): 14:30 yerel = 11:30 UTC.

    def test_gun_yil_aritmetigi_el_hesabi(self):
        on = self._DOGUM_UTC + dt.timedelta(days=10 * 365.2425)
        prog = predict_service._prog_ani(self._DOGUM_UTC, on)
        beklenen = self._DOGUM_UTC + dt.timedelta(days=10)
        assert abs((prog - beklenen).total_seconds()) < 1

    def test_progres_ay_tanimi(self):
        """Yaş tam 30 yıl → progres Ay = doğum+30 gün anının Ay'ı."""
        from zoneinfo import ZoneInfo
        on = self._DOGUM_UTC + dt.timedelta(days=30 * 365.2425)
        p = predict_service.secondary_progressions(
            "t", 1990, 5, 12, 14, 30, "Istanbul", on_date=on)

        yerel = (self._DOGUM_UTC + dt.timedelta(days=30)).astimezone(
            ZoneInfo("Europe/Istanbul"))
        chart = astro_service.get_natal_chart(
            "t", yerel.year, yerel.month, yerel.day,
            yerel.hour, yerel.minute, "Istanbul")
        ay = next(pt for pt in chart["points"] if pt["name"] == "Moon")
        assert p["prog_moon"]["sign"] == ay["sign"]
        assert abs(p["prog_moon"]["position"] - ay["position"]) < 0.05

    def test_ay_burc_degisim_tarihi_sinira_dusuyor(self):
        """Dönen tarihte progres Ay burç sınırının dibinde olmalı.

        Tarih, o ANDAKİ Ay hızıyla tek adımda ileri atılıyor; hız yıl
        (=1 prog-gün) içinde biraz değişir — tolerans ondan.
        """
        p1 = predict_service.secondary_progressions(
            "t", 1990, 5, 12, 14, 30, "Istanbul")
        sinir_gunu = dt.datetime.fromisoformat(
            p1["prog_moon"]["next_sign_at"]).replace(tzinfo=dt.timezone.utc)
        p2 = predict_service.secondary_progressions(
            "t", 1990, 5, 12, 14, 30, "Istanbul", on_date=sinir_gunu)
        poz = p2["prog_moon"]["position"]
        assert poz < 1.5 or poz > 28.5

    def test_saatsizlik_prog_asc_mc_uretmez(self):
        p = predict_service.secondary_progressions(
            "t", 1990, 5, 12, 12, 0, "Istanbul", hour_known=False)
        assert "prog_asc" not in p
        assert "prog_mc" not in p
        assert p["prog_moon"]["natal_house"] is None
        assert "prog_hour_unknown" in p["disclosures"]

    def test_solar_arc_kesinlesmeleri(self):
        """Kapalı form kendi tanımını tutmalı: verilen tarihte yay,
        gereken açı ayrımını ±0.35° içinde vermeli (doğrusallaştırma payı).
        """
        aci_derecesi = {"conjunction": 0, "sextile": 60, "square": 90,
                        "trine": 120, "opposition": 180}
        hits = predict_service.solar_arc_hits(
            "t", 1990, 5, 12, 14, 30, "Istanbul", years=3)
        assert hits, "3 yılda hiç kesinleşme çıkmadı — şüpheli"
        tarihler = [h["exact_on"] for h in hits]
        assert tarihler == sorted(tarihler)
        simdi = dt.datetime.now(dt.timezone.utc)
        for h in tarihler:
            fark_gun = (dt.datetime.fromisoformat(h).replace(
                tzinfo=dt.timezone.utc) - simdi).days
            assert -1 <= fark_gun <= int(3 * 366) + 1

        natal, _ = astro_service._build_subject(
            "t", 1990, 5, 12, 14, 30, "Istanbul", None)
        ilk = hits[0]
        an = dt.datetime.fromisoformat(ilk["exact_on"]).replace(
            tzinfo=dt.timezone.utc)
        p_o_gun = predict_service.secondary_progressions(
            "t", 1990, 5, 12, 14, 30, "Istanbul", on_date=an)
        arc = p_o_gun["solar_arc_deg"]

        def boylam(ad: str) -> float:
            if ad == "Ascendant":
                return float(natal.first_house.abs_pos)
            if ad == "Medium_Coeli":
                return float(natal.tenth_house.abs_pos)
            return float(getattr(natal, ad.lower()).abs_pos)

        yonlu = (boylam(ilk["directed"]) + arc) % 360
        ayrim = abs(yonlu - boylam(ilk["natal"])) % 360
        ayrim = min(ayrim, 360 - ayrim)
        assert abs(ayrim - aci_derecesi[ilk["aspect"]]) < 0.35


_ACI_DERECESI = {"conjunction": 0, "sextile": 60, "square": 90,
                 "trine": 120, "opposition": 180}


class TestTransitTakvimi:
    """T3 — kesinleşme günleri günlük örneklemeden seçilir; tanım testi
    o gün gezenin natal noktaya ayrımının açı derecesini tutturmasıdır.
    """

    _BASLANGIC = dt.datetime(2026, 8, 5, tzinfo=dt.timezone.utc)

    def _takvim(self, **kw):
        return predict_service.transit_calendar(
            "t", 1990, 5, 12, 14, 30, "Istanbul",
            start=self._BASLANGIC, **kw)

    def test_pencere_ve_siralama(self):
        cal = self._takvim()
        assert cal["start"] == "2026-08-05"
        tarihler = [o["date"] for o in cal["events"]]
        assert tarihler == sorted(tarihler)
        son = self._BASLANGIC + dt.timedelta(days=cal["days"])
        for t in tarihler:
            an = dt.datetime.fromisoformat(t).replace(tzinfo=dt.timezone.utc)
            assert self._BASLANGIC - dt.timedelta(days=1) <= an <= son

    def test_kesinlesme_tanimi(self):
        """Kesin günde gezenin natal noktaya ayrımı ≈ açı derecesi.

        Günlük örnekleme yarım güne kadar şaşabilir; en hızlı gezen
        (Jüpiter ~0.22°/gün) için bu ≤0.11° eder — 0.5° bol pay.
        """
        cal = self._takvim()
        kesinler = [o for o in cal["events"] if o["type"] == "aspect_exact"]
        assert kesinler, "30 günde hiç kesinleşme yok — şüpheli"
        olay = kesinler[0]
        gun = dt.datetime.fromisoformat(olay["date"])
        gokyuzu, _ = astro_service._build_subject(
            "now", gun.year, gun.month, gun.day, 12, 0, "Istanbul", None)
        natal, _ = astro_service._build_subject(
            "t", 1990, 5, 12, 14, 30, "Istanbul", None)

        def boylam(kim, ad: str) -> float:
            if ad == "Ascendant":
                return float(kim.first_house.abs_pos)
            if ad == "Medium_Coeli":
                return float(kim.tenth_house.abs_pos)
            return float(getattr(kim, ad.lower()).abs_pos)

        ayrim = abs(boylam(gokyuzu, olay["transit"])
                    - boylam(natal, olay["natal"])) % 360
        ayrim = min(ayrim, 360 - ayrim)
        assert abs(ayrim - _ACI_DERECESI[olay["aspect"]]) < 0.5
        assert olay["orb"] < 0.5

    def test_istasyon_olaylari_bicimi(self):
        cal = self._takvim()
        for o in cal["events"]:
            if o["type"].startswith("station"):
                assert "natal" not in o and "aspect" not in o
            else:
                assert o["transit"] in ("Jupiter", "Saturn", "Uranus",
                                        "Neptune", "Pluto", "Chiron")

    def test_saatsizlik_eksen_hedefi_uretmez(self):
        cal = self._takvim(hour_known=False)
        hedefler = {o.get("natal") for o in cal["events"]}
        hedefler |= {a["natal"] for a in cal["active_now"]}
        assert not hedefler & {"Ascendant", "Medium_Coeli",
                               "Descendant", "Imum_Coeli"}
        assert "transit_hour_unknown" in cal["disclosures"]

    def test_aktif_liste_orb_sirali(self):
        cal = self._takvim()
        orblar = [a["orb"] for a in cal["active_now"]]
        assert orblar == sorted(orblar)
        for a in cal["active_now"]:
            assert a["movement"] in ("applying", "separating", "static")
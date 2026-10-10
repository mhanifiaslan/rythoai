"""Olgu bekçisi: prompt'ta olmayan konum/açı cevapta geçmemeli.

Derinleştirme planının yazılmış regresyonu. LLM çağrısı YOK — tarama
saf metin; bu yüzden CI'da her commit'te çalışır.
"""
from __future__ import annotations

from services import fact_guard


def test_prompttaki_yerlesim_uydurma_degil():
    prompt = "Merkür: Başak (1. ev) · Satürn: Oğlak (10. ev)"
    cevap = "Merkür'ün Başak'ta, 1. evde durması zihni keskinleştirir."
    assert fact_guard.invented_claims(cevap, prompt) == set()


def test_promptta_olmayan_burc_uydurmadir():
    prompt = "Satürn: Oğlak (10. ev)"
    cevap = "Satürn senin İkizler burcunda."
    uydurma = fact_guard.invented_claims(cevap, prompt)
    assert ("sign", "Saturn", "gemini") in uydurma
    assert ("sign", "Saturn", "capricorn") not in uydurma


def test_promptta_olmayan_ev_uydurmadir():
    prompt = "Satürn: Oğlak (10. ev)"
    cevap = "Satürn 7. evinden geçiyor."
    assert ("house", "Saturn", 7) in fact_guard.invented_claims(cevap, prompt)
    assert ("house", "Saturn", 10) not in fact_guard.invented_claims(
        cevap, prompt)


def test_promptta_olmayan_aci_uydurmadir():
    prompt = "Güneş Kare Mars (0.5°)"
    cevap = "Güneş üçgen Jüpiter teması seni şişiriyor."
    uydurma = fact_guard.invented_claims(cevap, prompt)
    assert ("aspect", "Jupiter", "trine", "Sun") in uydurma
    # Verilen kare uydurma değil.
    assert not any(c[0] == "aspect" and c[2] == "square" for c in uydurma)


def test_ingilizce_house_nth_yakalanir():
    prompt = "Saturn in Capricorn (house 10)"
    cevap = "Saturn in your 4th house is a heavy root."
    assert ("house", "Saturn", 4) in fact_guard.invented_claims(cevap, prompt)


def test_yalin_gezegen_adi_iddia_degildir():
    """'Satürn yavaştır' doktrin konuşmasıdır, konum uydurması değil."""
    prompt = "Güneş: Aslan"
    cevap = "Satürn yavaş hareket eder; acele etmez."
    assert fact_guard.invented_claims(cevap, prompt) == set()


def test_bu_ay_ay_gezegeni_degildir():
    prompt = "Güneş: Aslan"
    cevap = "Bu ay işler yavaş ilerler."
    assert fact_guard.invented_claims(cevap, prompt) == set()


def test_ragdeki_konum_izinlidir():
    """Prompt'ta RAG pasajı varsa oradaki konum 'uydurma' sayılmaz —
    derinleştirme kuralı 'prompt'ta olmayan'dır."""
    prompt = ("KAYNAK: Satürn onuncu evde meslek ve statü.\n"
              "KULLANICININ HARİTASI:\n- Güneş: Aslan")
    cevap = "Satürn 10. evde meslek teması açılır."
    assert fact_guard.invented_claims(cevap, prompt) == set()


def test_enforce_temiz_metni_oldugu_gibi_birakir():
    prompt = "Venüs: Terazi"
    cevap = "Venüs Terazi'de ilişkiyi kolaylaştırır."
    metin, grounded = fact_guard.enforce(cevap, prompt)
    assert grounded is True
    assert metin == cevap


def test_enforce_uydurmada_yeniden_uretir():
    prompt = "Venüs: Terazi"
    kirli = "Venüs senin Koç burcunda."
    temiz = "Venüs Terazi'de duruyor."
    cagrilar: list[str] = []

    def uret(p: str) -> str:
        cagrilar.append(p)
        return temiz

    metin, grounded = fact_guard.enforce(
        kirli, prompt, lang="tr", regenerate=uret)
    assert grounded is True
    assert metin == temiz
    assert cagrilar and "DÜZELTME" in cagrilar[0]
    assert "Koç" in cagrilar[0] or "aries" in cagrilar[0].lower()


def test_enforce_ikinci_kez_de_uydurma_onbellegi_engeller():
    prompt = "Venüs: Terazi"
    kirli = "Venüs Koç'ta."

    def uret(_p: str) -> str:
        return "Venüs yine Koç'ta."

    metin, grounded = fact_guard.enforce(
        kirli, prompt, lang="tr", regenerate=uret)
    assert grounded is False
    assert "Koç" in metin


# ---------------------------------------------------------------------------
# Yanlis pozitif onarimi (1.6.2) — bekci YAPISAL VERIYLE karsilastirir
# ---------------------------------------------------------------------------

class TestYapisalKarsilastirma:
    """Bekci ilk surumde cevabin iddialarini PROMPT METNINDEN yeniden
    cikarilan iddialarla karsilastiriyordu; bu, iki tarafin yazim biciminin
    birebir tutmasini gerektiriyordu ve tutmuyordu.

    Olculdu: natal prompt evleri "(Ev 9)" diye yaziyordu, bekcinin TR
    deseni yalniz "9. ev" biciminde tanıyordu. Gercek bir raporda
    prompt'tan SIFIR ev iddiasi cikiyor, cevaptan 27 cikiyor ve DOGRU
    yerlesimler (Jupiter 10. ev, Mars 7. ev, Ay 4. ev...) "uydurma"
    sayiliyordu. Rapor onbellege yazilmiyor, kullanici Atlas'i her
    acisinda yeniden 5 jeton oduyordu.
    """

    HARITA = {
        "points": [
            {"name": "Jupiter", "sign": "Can", "house_no": 10},
            {"name": "Mars", "sign": "Pis", "house_no": 7},
            {"name": "Saturn", "sign": "Cap", "house_no": 5},
        ],
        "asc": {"sign": "Vir"},
        "aspects": [
            {"p1": "Mercury", "p2": "Jupiter", "aspect": "sextile"},
        ],
    }

    def test_dogru_yerlesim_UYDURMA_sayilmaz(self):
        cevap = ("Jüpiter 10. evinde duruyor; Mars 7. evde, "
                 "Satürn ise 5. evde.")
        # Prompt BOS: tek dayanak haritanin kendisi.
        assert fact_guard.invented_claims(cevap, "", self.HARITA) == set()

    def test_bicim_farki_artik_onemli_degil(self):
        """Prompt 'Ev 10' de yazsa '10. ev' de yazsa sonuc ayni."""
        cevap = "Jüpiter 10. evinde."
        for bicim in ("Jüpiter: Yengeç (Ev 10)", "Jüpiter: Yengeç (10. ev)",
                      "Jupiter: Cancer (House 10)", ""):
            assert fact_guard.invented_claims(
                cevap, bicim, self.HARITA) == set(), bicim

    def test_gercek_uydurma_HALA_yakalanir(self):
        """Onarim bekciyi kor etmemeli."""
        cevap = "Satürn 12. evinde."
        uydurma = fact_guard.invented_claims(cevap, "", self.HARITA)
        assert ("house", "Saturn", 12) in uydurma

    def test_harita_acilari_tanim_geregi_dogru(self):
        """Yukselen 1., Alcalan 7., MC 10., IC 4. evin baslangicidir;
        bunlari soylemek iddia degil tanimin tekraridir."""
        cevap = "Yükselen 1. evde, Alçalan 7. evde başlar."
        assert fact_guard.invented_claims(cevap, "", self.HARITA) == set()

    def test_yukselen_burcu_haritadan_okunur(self):
        assert fact_guard.invented_claims(
            "Yükselen Başak'ta.", "", self.HARITA) == set()
        assert fact_guard.invented_claims(
            "Yükselen Koç'ta.", "", self.HARITA)

    def test_arada_baska_gezegen_varsa_eslesmez(self):
        """'Neptun'un ... Boga'daki Gunes' cumlesinde Boga, Gunes'in
        burcudur; Neptun'un degil. Yakinlik tek basina dilbilgisi yerine
        gecmiyordu ve bu sinif yanlis pozitif uretiyordu."""
        iddialar = fact_guard.extract_claims(
            "Neptün'ün etkisi, Boğa'daki Güneş'e dokunuyor.")
        assert ("sign", "Neptune", "taurus") not in iddialar
        assert ("sign", "Sun", "taurus") in iddialar

    def test_sohbet_olgu_bicimi_de_kabul_edilir(self):
        """chart_context 'placements' sekli uretiyor; bekci ikisini de
        anlamali."""
        olgular = {"placements": [
            {"planet": "Venus", "sign": "Lib", "house": 3}]}
        assert fact_guard.invented_claims(
            "Venüs Terazi'de, 3. evde.", "", olgular) == set()
# ---------------------------------------------------------------------------
# Ucuncu kisi bicimleri (P-turu) — OLCUM, onarim degil
# ---------------------------------------------------------------------------

class TestUcuncuKisiBicimleri:
    """Uretimde "29/04/2010 istanbul" sonrasi "Ayse Oyku, Gunes'i Boga
    burcunda ve Ay'i Akrep burcunda" kullaniciya gitti ve olgu bekcisi
    yakalamadi. Ilk hipotez `extract_claims`in iyelik bicimini
    ("Gunes'i … burcunda") kacirdigiydi — OLCULDU (2026-10-10), kacirmiyor.
    Gercek bosluk YAPISAL: iddia kumesi KIMIN Gunes'i oldugunu bilmez.
    Kullanicinin kendi Gunes'i Boga ise ("sign","Sun","taurus") dayanakta
    vardir ve ucuncu kisiye yakistirilan ayni iddia "dogru" sayilir. O
    boslugu sohbette `persona_guard.third_party_claims` kapatir (adi
    fisiltida olmayan kisi); bu sinif burada yalniz olcumu civiler.
    """

    def test_iyelik_bicimleri_yakalanir(self):
        iddialar = fact_guard.extract_claims(
            "Ayse Oyku, Gunes'i Boga burcunda ve Ay'i Akrep burcunda.")
        assert ("sign", "Sun", "taurus") in iddialar
        assert ("sign", "Moon", "scorpio") in iddialar
        assert ("sign", "Sun", "sagittarius") in fact_guard.extract_claims(
            "Gunes'inin Yay burcundaki konumu ona ates katiyor.")

    def test_iddia_kumesi_sahibi_bilmez(self):
        """SINIR BEYANI: kullanici Boga ise ucuncu kisinin Boga Gunes'i
        'uydurma' SAYILMAZ — bekci sahibi gormez. Bu test onarilacak bir
        kusur degil, ayrimin nerede durdugunun kaydidir."""
        olgular = {"sun": {"planet": "Sun", "sign": "Tau"}}
        assert fact_guard.invented_claims(
            "Ayse Oyku, Gunes'i Boga burcunda.", "", olgular) == set()
        # Sahipsiz ayni iddia, kullanici Boga DEGILSE yakalanir.
        assert ("sign", "Sun", "taurus") in fact_guard.invented_claims(
            "Ayse Oyku, Gunes'i Boga burcunda.", "",
            {"sun": {"planet": "Sun", "sign": "Leo"}})
def test_gunes_ay_yukselen_sayimi_aci_iddiasi_degildir():
    """"Ay" ozel eslesmesi bir tur boyunca ACI listesine de ekleniyordu:
    "Gunes, Ay, Yukselen" sayimi ("aspect", "Ascendant", "Moon", "Sun")
    diye SAHTE bir aci uretiyor ve ucluyu bir cumlede anan her dogru yanit
    bir LLM turu daha ismarliyordu (olculdu 2026-10-10, persona
    fisiltisinin "burc, Gunes, Ay, Yukselen" satirinda yakalandi)."""
    for cumle in ("Burc, Gunes, Ay, Yukselen cikarma.",
                  "Gunes'in, Ay'in ve Yukselenin bir arada okunmasi gerekir."):
        iddialar = fact_guard.extract_claims(cumle)
        assert not any(c[0] == "aspect" for c in iddialar), (cumle, iddialar)
    # Gercek bir Ay acisi HALA yakalanir — onarim bekciyi kor etmemeli.
    assert ("aspect", "Moon", "square", "Sun") in fact_guard.extract_claims(
        "Gunes kare Ay teması sende gerilim yaratir.")

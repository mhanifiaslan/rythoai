r"""OP2: istasyon satirinin ANLAMI — 12 kutunun degismezleri.

Sahip cihaz ekran goruntusuyle geldi: gun alt sayfasindaki "Diger
hareketler" satiri tek satirdi — "Pluton — ileri harekete donus" — ve
baska hicbir sey yoktu. O satir bir ADLANDIRMAYDI, okuma degildi;
hareketin ne demek oldugu, ne getirip ne goturdugu uzerinde HICBIR
yuzeyde yoktu.

Bu dosya cumlenin METNINI civilemez (metin degisebilir); cumlenin
KURULUSUNU civiler. Kurulusun uc sarti var ve ucu de bir kez bedel
odedi:

  1. CARPIM, toplama degil. Depoda kayitli kusur: 44 sabit cumle yan yana
     BASILIYORDU, sentezlenmiyordu. 12 kutu `6 gezegen temasi x 2 yon
     evresi` carpimindan dogar; elle yazilan 12 cumle ayni kusuru geri
     getirir.
  2. KISISELLESTIRME YOK. Istasyon kisisel bir natal noktaya baglanmiyor
     (bkz. signal_service.enrich_events) — "senin haritanda" demek
     "olculmeyen soylenmez"i ihlal ederdi. Anlatilan sey gezegenin kendi
     dogasi: "Pluton temeli soker" cumlesi Pluton hakkindadir.
  3. ANAHTARLAR MOTORLA AYNI. Tabloda eksik bir gezegen ya da evre,
     cumlesiz bir istasyon uretir ve kullanici yine ciplak satir gorur.
     Tabloda FAZLA bir kutu ise okuyucusu olmayan bir kutudur.

Calistirma:
  .venv\Scripts\python.exe -m pytest tests/test_istasyon_anlami.py -q
"""
from __future__ import annotations

import pathlib
import re

import pytest

from services import predict_service, prompts

DILLER = ("tr", "en")


def _motorun_istasyon_turleri() -> set[str]:
    """`predict_service`in GERCEKTEN urettigi istasyon turleri.

    Sabit bir liste yazmak yetmezdi: motora ucuncu bir istasyon turu
    eklendigi gun liste sessizce bayatlar ve yeni tur cumlesiz kalir.
    Olcum kaynagin kendisinden alinir.

    Yorumlar eslesmeden ONCE atilir. Bu depoda iki kez patlayan kusur:
    bir seyin varligini/yoklugunu arayan bekci, onu ANLATAN yorumu
    gorup kendi kendini yanlis besliyordu.
    """
    kaynak = pathlib.Path(predict_service.__file__).read_text(
        encoding="utf-8")
    kodsuz = re.sub(r"#[^\n]*", "", kaynak)
    return set(re.findall(r'"type":\s*"(station[A-Za-z_]*)"', kodsuz))


#: İkinci tekil sahis isaretleri. Tek bir kelimeye baglanmadi (TR+EN,
#: birden cok ek): tek kelimelik capa, cumle biraz degisince sessizce
#: korlesir. `str.lower()` BILEREK kullanilmadi — Turkce bilmiyor
#: ("I".lower() noktali i uretir); kalip ilk harfin iki halini de alir.
_KISISEL_ISARETLER = (
    r"[Ss]en", r"[Ss]enin", r"[Ss]ana", r"[Ss]ende", r"[Ss]enden",
    r"[Ss]eni", r"[Hh]aritan\w*", r"[Ss]izin", r"[Ss]ize",
    r"[Yy]ou", r"[Yy]our", r"[Yy]ours", r"[Yy]ourself",
)
_KISISEL = re.compile(r"\b(?:" + "|".join(_KISISEL_ISARETLER) + r")\b")


def _tum_cumleler(lang: str) -> dict[tuple[str, str], str]:
    """Bir dilin 12 kutusu: (gezegen, evre) -> kurulmus cumle."""
    p = prompts.get(lang)
    return {
        (gezegen, evre): kalip.format(
            transit=prompts.planet_name(lang, gezegen), theme=tema)
        for gezegen, tema in p.STATION_PLANET_THEMES.items()
        for evre, kalip in p.STATION_PHASE_LINES.items()
    }


@pytest.mark.parametrize("lang", DILLER)
def test_on_iki_kutu_DOLU(lang):
    """6 gezegen x 2 evre = 12; hicbiri bos degil, hicbiri yarim degil."""
    cumleler = _tum_cumleler(lang)
    assert len(cumleler) == 12, cumleler.keys()
    for (gezegen, evre), cumle in cumleler.items():
        # Gezegen adi cumlede GECMELI: ozne dusunce kullanici neyin
        # hareket ettigini kaybeder — sahibin sikayet ettigi satir tam
        # olarak ozne + etiketten olusuyordu.
        assert prompts.planet_name(lang, gezegen) in cumle, (gezegen, evre)
        # Kalip yer tutucusu kaldiysa cumle ekranda "{theme}" basar.
        assert "{" not in cumle and "}" not in cumle, (gezegen, evre)
        assert len(cumle) > 120, (gezegen, evre, len(cumle))


@pytest.mark.parametrize("lang", DILLER)
def test_kalip_CARPIM_zorunlu(lang):
    """Her evre kalibi iki yer tutucuyu da tasimali.

    `{theme}`si olmayan bir kalip, gezegen temasini cumleye KATMADAN
    basar: tablo carpim olmaktan cikar, 12 kutu 2 cumleye coker ve altı
    gezegen ayni seyi der. `{transit}`i olmayan kalip ozneyi kaybeder.
    Elle yazilmis 12 cumle de bu kapidan gecemez.
    """
    for evre, kalip in prompts.get(lang).STATION_PHASE_LINES.items():
        assert "{transit}" in kalip, evre
        assert "{theme}" in kalip, evre


@pytest.mark.parametrize("lang", DILLER)
def test_on_iki_cumle_BIRBIRINDEN_FARKLI(lang):
    """Carpimin anlami: 12 kutu 12 ayri cumle vermeli.

    Depoda kayitli kusur bunun tersiydi — birbirinden farkli olaylar
    birebir ayni cumleye dusuyordu ve kullanici tekrari bilgi saniyordu.
    """
    cumleler = _tum_cumleler(lang)
    assert len(set(cumleler.values())) == 12


@pytest.mark.parametrize("lang", DILLER)
def test_cumle_KISISELLESTIRILMIYOR(lang):
    """Hicbir cumle kullaniciyi anlatmaz — gezegeni anlatir.

    Istasyon kisisel bir natal noktaya baglanmiyor; ona "senin
    haritanda" demek olculmeyeni soylemek olurdu. Dayanak satiri da
    ayni kapidan gecer: o da bir OLCUMU adlandirir.
    """
    p = prompts.get(lang)
    for (gezegen, evre), cumle in _tum_cumleler(lang).items():
        bulunan = _KISISEL.findall(cumle)
        assert not bulunan, (gezegen, evre, bulunan)
    assert not _KISISEL.findall(p.STATION_LINE_TECHNICAL)


def test_TR_ve_EN_SIMETRIK():
    """Iki dil AYNI 12 anahtari tasimali.

    Tek dilde eksik bir anahtar, o dilde cumlesiz bir istasyon demek —
    ve bu, yalniz o dilin cihazinda gorunur. Depoda "Ingilizceye cevirince
    de Turkce kaliyor" sinifinda bir cihaz bulgusu var; eksik anahtarin
    sessiz hali bunun kardesi.
    """
    tr, en = prompts.get("tr"), prompts.get("en")
    assert set(tr.STATION_PLANET_THEMES) == set(en.STATION_PLANET_THEMES)
    assert set(tr.STATION_PHASE_LINES) == set(en.STATION_PHASE_LINES)


@pytest.mark.parametrize("lang", DILLER)
def test_gezegen_anahtarlari_MOTORLA_AYNI(lang):
    """Tablo, takvime giren gezegen listesiyle birebir ortusmeli."""
    assert (set(prompts.get(lang).STATION_PLANET_THEMES)
            == set(predict_service._TRANSIT_GEZEGENLERI))


@pytest.mark.parametrize("lang", DILLER)
def test_evre_anahtarlari_MOTORLA_AYNI(lang):
    """Tablo, motorun URETTIGI istasyon turleriyle birebir ortusmeli."""
    uretilen = _motorun_istasyon_turleri()
    assert uretilen, "kaynaktan hic istasyon turu okunamadi"
    assert set(prompts.get(lang).STATION_PHASE_LINES) == uretilen


@pytest.mark.parametrize("lang", DILLER)
def test_uctan_uca_istasyon_ANLAM_ve_DAYANAK_alir(lang):
    """Dalin kendisi: ham olay -> `line` + `technical`.

    Daha onceki hal bu ikisini YALNIZ tema+ton tasiyan kesinlesmeler
    icin yaziyordu; istasyon hicbir yerde almiyordu ve istemci iki
    etiketi tire ile yapistirmak zorunda kaliyordu.
    """
    ham = {"events": [{"type": "station_direct", "date": "2026-10-14",
                       "transit": "Pluto"}]}
    o = prompts.localize_transit_calendar(lang, ham)["events"][0]

    assert o["line"], o
    assert o["technical"], o
    # Dayanak OLCUMU adiyla soyler: gezegen, tarih ve olay adi.
    assert o["transit_local"] in o["technical"]
    assert o["date_local"] in o["technical"]
    assert o["type_local"] in o["technical"]
    # Paylasimli olgu: kilit rozeti burada DOGMAZ.
    assert "locked" not in o


@pytest.mark.parametrize("lang", DILLER)
def test_TANINMAYAN_istasyon_cumle_ALMAZ(lang):
    """Tabloda olmayan tur ya da gezegen icin cumle UYDURULMAZ.

    "Istasyon iste" diye genel bir cumle basmak olculmeyeni soylemek
    olurdu: hangi gezegen, hangi yon bilinmeden anlam da yok. O durumda
    `line` HIC yazilmaz ve istemci kendi teknik yedegini gosterir
    (calendar_strip.dart `_OlaySatiri`).
    """
    ham = {"events": [
        # Tur tabloda yok (motorun uretmedigi bir ad).
        {"type": "station", "date": "2026-10-14", "transit": "Pluto"},
        # Gezegen tabloda yok (hizli gezegen takvime hic girmiyor).
        {"type": "station_direct", "date": "2026-10-15",
         "transit": "Mercury"},
    ]}
    for o in prompts.localize_transit_calendar(lang, ham)["events"]:
        assert "line" not in o, o
        assert "technical" not in o, o
        # Olcum yine de duruyor: istemci yedek satirini bundan kuruyor.
        assert o["transit_local"]

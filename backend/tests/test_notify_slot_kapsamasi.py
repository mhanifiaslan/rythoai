"""YENI SLOTLARIN KAPSAMASI: tasan govde, aksam sirasi, zamanlayici isi.

Bu dosya DOGRULAMA turunda dogdu. CV/K7 paketinin bekcileri mutasyonla
sinandi; 40 minimal mutasyonun 37'si kirmizi yandi ve UCU YESIL KALDI.
Burasi o uc bosluk icin — her biri gercek bir kapi, her biri olculerek
ulasilabilir bulundu.

1. **Tasan govde (iki yerde kor).** `winback_push` ve `circle_push`
   govdeyi `MAX_PUSH_BODY` (110) ile siniriyor, ama uzunluk terimini
   geri alan mutasyon takimi YESIL biraktı. Kapi gercekten
   ulasilabilir: `displayName` HICBIR YERDE siniri yok — ne istemcide
   (apps/mobile/.../account_screen.dart yalnizca BOS olup olmadigina
   bakiyor), ne `infra/firestore.rules`'ta, ne de sunucuda. Olculdu: 90
   harflik bir ad 10. basamak govdesini 139 karaktere, Cevrem satirini
   141 karaktere cikariyor.
   ⚠️ Capa `lang="tr"` ve bu OLCULDU, varsayilmadi: maskeleme yalniz
   `lang="en"` + Turkce harfli ad ikilisinde mumkun (tahmin "mixed"
   cikiyor ve KOMSU kapi — dil muhafizi — kapaniyor; uzunluk terimi
   sokulse bile test kirmizi kalir, yanlis guven). `lang="tr"`de
   govdenin tahmini her halde "tr" oldugu icin dil muhafizi ASLA
   firlamaz; ad ASCII olsun ya da olmasin. Bir katmani tutan bekci
   digerinin korlugunu MASKELER, o yuzden capa yalniz uzunluk.
   (Bu gerekcenin ilk hali YANLISTI — "ASCII ad kullaniliyor cunku
   Turkce harf dil muhafizini tetikler" yaziyordu. Mutasyonla sinandi:
   ad "Ş"*90'a cevrildiginde takim YESIL kaldi, yani sebep adin
   harfleri degil govdenin dili.)

2. **Cevrem slotu aksam sirasini KAZANMAK zorunda.** `TARGET_HOURS`
   icinde `circle`i 18'den 20'ye tasiyan mutasyon takimi YESIL biraktı.
   Olculdu: 20'de `checkin` (Scheduler dakikasi :08) `circle`den (:14)
   ONCE kosuyor, aksam ailesi kurali geregi isaretliyor ve Cevrem slotu
   HIC gecmiyor — yani slot sessizce OLUYOR. Paketin varlik sebebi tam
   olarak bu olumun onarilmasiydi (ogle yedek dalinda olu kaliyordu),
   dolayisiyla "en fazla bir aksam bildirimi" yetmez: HANGISININ gectigi
   de civilenmek zorunda.

3. **Her tur icin zamanlayici isi.** Depoda ters dersi var ("okuyucusu
   olmayan seyi isitma": haftalik/aylik burc kovalari her gece
   isitiliyordu, okuyucusu sifirdi). Buradaki yon tam tersi: ISI OLMAYAN
   bir SLOT. `winback` kodda dursa ve `create-scheduler.ps1`e is
   eklenmese kimse fark etmez — testler yesil, uc saglikli, kullanici
   hicbir zaman geri cagrilmaz. Bekci iki yone de calisir: betikteki her
   bildirim isi de BILINEN bir tur olmak zorunda.

Calistirma:
  .venv/Scripts/python.exe -m pytest tests/test_notify_slot_kapsamasi.py -q
"""
from __future__ import annotations

import datetime as dt
import re
import typing
from pathlib import Path

import pytest

from core import i18n
from services import notification_service as ns
from services import notify_runner, synastry_service

KOK = Path(__file__).resolve().parent.parent.parent
BUGUN = dt.date(2026, 6, 15)
GUN = BUGUN.isoformat()

#: Uzunluk kapisini tetikleyen ad. Dil muhafizi bu dosyada ZATEN
#: firlayamaz (govde Turkce, istenen dil "tr") — bkz. modul basi.
UZUN_AD = "A" * 90

#: Maskelemenin GERCEKTEN mumkun oldugu ikili — asagidaki bagimsizlik
#: testi bunu karsi ornek olarak kullaniyor, yoksa "dil muhafizi
#: firlamiyor" iddiasi bos bir temenni olurdu.
MASKELEYEN_AD = "Ş" * 90

SAHTE_GOKYUZU = {"moon_phase": {"key": "full_moon", "name": "Dolunay",
                                "illumination": 98}, "retrogrades": []}


def profil(**alanlar):
    temel = {
        "uid": "u1",
        "fcmToken": "token-1",
        "onboardingCompleted": True,
        "timezone": "UTC",
        "language": "tr",
        "sunSign": "Aslan",
        "streakCount": 5,
        "quietFrom": 0,
        "quietTo": 0,
        "lastSeenDaily": GUN,
    }
    temel.update(alanlar)
    return temel


def _cp(label: str):
    return synastry_service.Counterpart(key="u1-f1", birth={}, label=label,
                                        sun_sign="leo")


def _vurus(side: str = "other"):
    """`side` ONEMLI: `pair_transit_lines` adi YALNIZ karsi taraf
    vurusunda satira koyuyor (`PAIR_SIDE_SELF` ad almiyor). `side="user"`
    ile uzun ad govdeye hic girmez ve test hicbir sey olcmezdi."""
    return {"side": side, "transit": "Saturn", "natal": "Venus",
            "aspect": "Trine", "orb": 0.8, "movement": "applying"}


# ---------------------------------------------------------------------------
# 1: tasan govde — uzunluk kapisi
# ---------------------------------------------------------------------------

def test_uzunluk_capasi_dil_muhafizinden_BAGIMSIZ():
    """CAPANIN BAGIMSIZLIGI — maskeleme bu dosyada mumkun DEGIL.

    Asagidaki iki test yalnizca uzunluk terimini sinamak zorunda. Dil
    muhafizi ayni `if`in oteki terimi: o da kapaniyorsa uzunluk sokulse
    bile testler kirmizi kalir ve "bekci var" sanilir.

    Olculdu: celiski yalniz `lang="en"` + Turkce harfli adda cikiyor
    (tahmin "mixed"). `lang="tr"`de govdenin tahmini her halde "tr",
    yani muhafiz hangi harfle olursa olsun susuyor. Karsi ornek de
    burada duruyor ki iddia bos bir temenni olmasin.
    """
    for ad in (UZUN_AD, MASKELEYEN_AD):
        govde = ns.WINBACK_TEXTS[10]["tr"]["veri"].format(
            label=ad, transit="Satürn")
        assert len(govde) > ns.MAX_PUSH_BODY
        assert not i18n.language_conflicts(govde, "tr")
        satir = synastry_service.pair_transit_lines([_vurus()], ad, "tr")[0]
        assert len(satir) > ns.MAX_PUSH_BODY
        assert not i18n.language_conflicts(satir, "tr")

    # KARSI ORNEK: maskelemenin gercekten var oldugu ikili. Bu satir
    # kirmizi yanarsa yukaridaki "tr'de muhafiz susuyor" gerekcesi
    # anlamini yitirir ve capa yeniden secilmelidir.
    ingilizce = ns.WINBACK_TEXTS[10]["en"]["veri"].format(
        label=MASKELEYEN_AD, transit="Saturn")
    assert i18n.language_conflicts(ingilizce, "en")


def test_geri_kazanim_govdesi_TASARSA_yalin_soruya_duser(monkeypatch):
    """Sinirsiz `displayName` govdeyi tasirabilir; o zaman iddia KUCULUR,
    bildirim DUSMEZ (geri cagri o kullaniciya ulasmak zorunda)."""
    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [("cp", {"fromUid": "f1"})])
    monkeypatch.setattr(
        ns, "_en_iyi_vurus",
        lambda uid, adaylar, today, hesapla: (
            (_cp(UZUN_AD), {"fromUid": "f1"}, {"transit": "Saturn"}), True))

    icerik, veri, olctu = ns.winback_push(
        profil(), "tr", 10, sky=SAHTE_GOKYUZU, today=BUGUN)

    assert icerik.govde == ns.WINBACK_TEXTS[10]["tr"]["yalin"]
    assert len(icerik.govde) <= ns.MAX_PUSH_BODY
    # Tasan govde OLCUM SAYILMAZ: kullaniciya ulasan sey veri-siz soru.
    assert olctu is False
    assert icerik.soru is True and veri["src"] == "winback"


def test_cevrem_govdesi_TASARSA_push_GITMEZ(monkeypatch):
    """Cevrem slotunda yalin bir yedek YOK — olculmus satir gitmezse
    gonderilecek bir sey de yok. Kirpmak "olculen yanlis adla sunulur"
    olurdu (yarim bir transit cumlesi)."""
    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [(_cp(UZUN_AD), {"fromUid": "f1"})])
    monkeypatch.setattr(
        ns, "_en_iyi_vurus",
        lambda uid, adaylar, today, hesapla: (
            (_cp(UZUN_AD), {"fromUid": "f1"}, _vurus()), True))

    yuk, gerekce, olctu = ns.circle_push(profil(), "tr", today=BUGUN)

    assert yuk is None and gerekce == "olay-yok"
    # Olcum ELDE EDILDI (vurus vardi), gonderilemeyen sey govdeydi:
    # bu bir URETIM dususu DEGIL, yoksa uzun adli tek kullanici kosuyu
    # kirmiziya cevirirdi.
    assert olctu is True


# ---------------------------------------------------------------------------
# 2: aksam sirasi — Cevrem slotu gecmek zorunda
# ---------------------------------------------------------------------------

class _SahteAnlik:
    def __init__(self, veri):
        self._veri = veri
        self.exists = bool(veri)

    def to_dict(self):
        return dict(self._veri)


class _SahteDoc:
    def __init__(self, depo):
        self.depo = depo

    def get(self):
        return _SahteAnlik(self.depo)

    def set(self, veri, merge=False):
        if not merge:
            self.depo.clear()
        self.depo.update(veri)


@pytest.fixture()
def kayit(monkeypatch):
    depo: dict = {}
    monkeypatch.setattr(ns, "_notification_doc", lambda uid: _SahteDoc(depo))
    return depo


#: Scheduler isinin GERCEK dakika sirasi (infra/create-scheduler.ps1).
#: Ayni yerel saate dusen turlerden once kosan isaretler, sonraki susar.
DAKIKA_SIRASI = ("daily", "checkin", "streak", "midday", "circle", "winback")


def _gunun_gecenleri(p: dict) -> dict[str, int]:
    gecen: dict[str, int] = {}
    for saat in range(24):
        an = dt.datetime(2026, 6, 15, saat, tzinfo=dt.timezone.utc)
        for tur in DAKIKA_SIRASI:
            gonder, _ = ns.should_send(p, tur, an)
            if gonder:
                gecen[tur] = saat
                ns.mark_sent(p["uid"], tur, GUN)
    return gecen


def test_cevrem_aksam_slotunu_GERCEKTEN_alir(kayit):
    """AKTIF kullanicinin aksam slotu `circle` olmak zorunda.

    "En fazla bir aksam bildirimi" bu kusuru YAKALAMAZ: `circle` olurse
    yerine `checkin` gecer, sayi yine bir kalir ve test yesil yanar.
    Olculdu (mutasyon: `circle` 18 -> 20): o anda `checkin` dakika :08'de
    kosup isaretliyor, `circle` :14'te aksam ailesine takiliyor ve
    HIC GECMIYOR — paketin onardigi olum geri geliyor.
    """
    gecen = _gunun_gecenleri(profil(lastSeenDaily="2026-06-14"))

    assert gecen.get("circle") == ns.TARGET_HOURS["circle"]
    assert "checkin" not in gecen and "streak" not in gecen


def test_cevrem_saati_oteki_aksam_uyelerinden_ONCE(kayit):
    """Sirayi SAAT belirler, kod degil. `circle` oteki aksam uyeleriyle
    ayni saate dusurse Scheduler dakikasi karar verir ve `circle` kaybeder
    (:14, `checkin` :08). Bu yuzden saat STRICT kucuk olmak zorunda."""
    for diger in ("winback", "checkin", "streak"):
        assert ns.TARGET_HOURS["circle"] < ns.TARGET_HOURS[diger], (
            f"circle, {diger} ile ayni ya da sonraki saate dusemez")


# ---------------------------------------------------------------------------
# 3: her tur icin zamanlayici isi
# ---------------------------------------------------------------------------

def _betik_kodu() -> str:
    """Yorumsuz betik. Yorumlar ONCE atilir: bir seyin YOKLUGUNU arayan
    bekci, onu ANLATAN yorumu gormemeli — bu depoda iki kez patladi."""
    ham = (KOK / "infra" / "create-scheduler.ps1").read_text(
        encoding="utf-8")
    return "\n".join(s for s in ham.splitlines()
                     if not s.lstrip().startswith("#"))


def _betikteki_bildirim_turleri() -> set[str]:
    return set(re.findall(r'tur\s*=\s*"([^"]+)"', _betik_kodu()))


def test_her_zamanlanmis_tur_icin_SCHEDULER_ISI_VAR():
    """ISI OLMAYAN SLOT = olu kod. Tur `TARGET_HOURS`ta durur, uc onu
    kabul eder, testler yesil yanar — ama hicbir sey onu CAGIRMAZ ve bu
    hicbir yerde kirmizi gorunmez."""
    eksik = set(ns.SCHEDULED_TYPES) - _betikteki_bildirim_turleri()
    assert not eksik, f"zamanlayici isi olmayan slot: {sorted(eksik)}"


def test_betikteki_her_BILDIRIM_ISI_bilinen_tur():
    """Ters yon: betikte kalmis bir tur uca `422` yedirirdi ve Scheduler
    gunlugunde her saat kirmizi bir is dururdu."""
    fazla = _betikteki_bildirim_turleri() - set(ns.SCHEDULED_TYPES)
    assert not fazla, f"betikte bilinmeyen bildirim turu: {sorted(fazla)}"


def test_kosu_turleri_ucun_LITERALIYLE_ayni():
    """`notify_runner.RUN_TYPES` ile `/notify/run` Literal'i ayni kume
    olmak zorunda: uc kendi Literal'ini dogruluyor, kosu kendi listesini.
    Ayrisirlarsa ya uc 422 ile reddeder (kosu hic calismaz) ya da kosu
    `ValueError` atar (uc 500 doner) — iki yonde de slot sessizce olur."""
    from api import notify as notify_uc

    literal = typing.get_type_hints(notify_uc.run)["type"]
    assert set(typing.get_args(literal)) == set(notify_runner.RUN_TYPES)
    # Zamanlanmis turlerin TAMAMI kosturulabilir olmak zorunda.
    assert set(ns.SCHEDULED_TYPES) == set(notify_runner.RUN_TYPES)

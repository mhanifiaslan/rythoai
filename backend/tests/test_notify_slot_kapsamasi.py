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

    Olculdu: HAM `i18n` celiskisi yalniz `lang="en"` + Turkce harfli
    adda cikiyor (tahmin "mixed"). `lang="tr"`de govdenin tahmini her
    halde "tr", yani muhafiz hangi harfle olursa olsun susuyor. Karsi
    ornek de burada duruyor ki iddia bos bir temenni olmasin.
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
    #
    # ⚠️ MASKELEYEN SEY DEGISTI (olculdu 2026-10-03). Eskiden karsi ornek
    # `lang="en"` + Turkce harfli AD ikilisiydi; dil kapisi artik adi
    # olcumden cikardigi icin (`ns.ozel_ad_haric`) o ikili KAPIDA
    # maskelemiyor. Ham `i18n` cagrisi yine celisiyor ama kapi
    # firlamiyor, yani eski karsi ornek kapi hakkinda HICBIR SEY
    # kanitlamazdi. Gecerli maskeleme sinifi: dil isareti ADDAN DEGIL
    # CUMLEDEN gelen govde. Iki satir bunu birlikte olcuyor.
    ham = ns.WINBACK_TEXTS[10]["en"]["veri"].format(
        label=MASKELEYEN_AD, transit="Saturn")
    assert i18n.language_conflicts(ham, "en")
    assert not i18n.language_conflicts(
        ns.ozel_ad_haric(ham, MASKELEYEN_AD), "en"), (
        "ad kaynakli celiski kapida HALA maskeliyor")

    ascii_ad = "J" * 90
    gercek_kacak = ns.WINBACK_TEXTS[10]["tr"]["veri"].format(
        label=ascii_ad, transit="Saturn")
    assert len(gercek_kacak) > ns.MAX_PUSH_BODY
    assert i18n.language_conflicts(
        ns.ozel_ad_haric(gercek_kacak, ascii_ad), "en"), (
        "gercek dil kacagi artik maskelemiyorsa capa yeniden secilmeli")


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

    yuk, gerekce, olctu, _ad = ns.circle_push(profil(), "tr", today=BUGUN)

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


# ---------------------------------------------------------------------------
# 4: OZEL AD DIL TASIMAZ — kosunun ortak dil agi ada takilmamali
# ---------------------------------------------------------------------------
#
# NEDEN burada (olculdu 2026-10-03): `i18n.guess_language` karari HARF
# tabanli veriyor ve karsi tarafin GORUNEN ADI baska bir dilin harflerini
# tasiyabilir. Olculen zincir:
#
#   lang="en" + arkadas adi "Seyma" (Turkce yazimiyla)
#     -> baslik "🔭 Today: you and Şeyma"  -> guess_language "mixed"
#     -> language_conflicts(..., "en") True
#     -> kosunun ortak agi push'u TAMAMEN dusuruyor
#     -> atlanan["dil-uyusmaz"] += 1, kullanici o bildirimi HIC almiyor
#
# Govde de ayni: "for Şeyma: mars → venus Trine (…)" -> "tr".
#
# Yani Ingilizce kullanan birinin Turkce adli bir arkadasi/eklenen kisisi
# varsa Cevrem slotu o kullaniciya HER GUN sessizce olu kaliyordu. Onarim
# agi KALDIRMADI, olctugu metni arindirdi (`ns.ozel_ad_haric`).
#
# Bekciler UCTAN UCA (`notify_runner._run`) kosuyor, cunku kusur tek bir
# fonksiyonda degil iki katmanin ARASINDA: uretici dogru metni kuruyor,
# ag onu dusuruyordu.


#: Kosu GERCEK `now_utc` ile calisiyor (test sabiti `BUGUN` degil), yani
#: `lastSeenDaily` de gercek bugun olmali: aksi halde `should_send` profili
#: `geri-kazanim-penceresi` diye atlar ve bekci dil agina HIC ulasmaz.
BUGUN_GERCEK = dt.datetime.now(dt.timezone.utc).date().isoformat()


def _kosu_ortami(monkeypatch, profiller):
    """Kosuyu Firestore'suz ve FCM'siz kurar.

    `push_service.send` de sahte: kalibrasyon uyarisi PROVA yolunda degil
    GERCEK kosu yolunda basiliyor (prova erken donuyor) ve prova zaten
    operatorun elle denemesi — zamanlanmis kosu olculmesi gereken yol.
    """
    from services import push_service

    monkeypatch.setattr(
        push_service, "send",
        lambda mesajlar: push_service.SendResult(
            sent=len(mesajlar), failed=0, pruned=[], failed_uids=[]))
    monkeypatch.setattr(notify_runner, "get_sky_now", lambda: SAHTE_GOKYUZU)
    monkeypatch.setattr(notify_runner.firestore_client, "get_client",
                        lambda: None)
    monkeypatch.setattr(ns, "already_sent", lambda uid, tur, gun: False)
    monkeypatch.setattr(ns, "mark_sent",
                        lambda uid, tur, gun, extra=None: None)
    monkeypatch.setattr(notify_runner, "_iter_profiles",
                        lambda: iter(profiller))


def _cevrem_kosusu(monkeypatch, profiller):
    _kosu_ortami(monkeypatch, profiller)
    return notify_runner._run("circle", dry_run=True, force=True,
                              ignore_dedupe=True, only_uid=None, mark=False)


def test_TURKCE_ADLI_arkadas_INGILIZCE_kullanicinin_cevremini_OLDURMEZ(
        monkeypatch):
    """Ad kaynakli dil celiskisi push'u dusurmemeli.

    Uc BAGIMSIZ isaret soruluyor; biri tek basina yetmez:
      1. `dil-uyusmaz` sayaci HIC artmamali (agin firlamadigi),
      2. kuyrukta mesaj olmali ve adi BASLIKTA da GOVDEDE de tasimali
         (dusurulen seyin gercekten bu push oldugu),
      3. `languages` "en" saymali (profil dilinin degismedigi).
    """
    ad = "Şeyma Gülşah"
    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [(_cp(ad), {"fromUid": "f1"})])
    monkeypatch.setattr(
        ns, "_en_iyi_vurus",
        lambda uid, adaylar, today, hesapla: (
            (_cp(ad), {"fromUid": "f1"}, _vurus()), True))

    sonuc, mesajlar = _cevrem_kosusu(
        monkeypatch, [profil(language="en", lastSeenDaily=BUGUN_GERCEK)])

    assert "dil-uyusmaz" not in sonuc.skipped, (
        f"ad yuzunden dusuruldu: {sonuc.skipped}")
    assert len(mesajlar) == 1, f"kuyruk bos: {sonuc.skipped}"
    assert ad in mesajlar[0].title and ad in mesajlar[0].body
    assert sonuc.languages == {"en": 1}


def test_cevremde_GERCEK_dil_kacagi_hala_dusuruluyor(monkeypatch):
    """Ad muafiyeti agi KAPATMADI — karsi ornek olmadan muafiyet bos cek.

    Ad ASCII ("John"), yani ad cikarildiktan SONRA da govde Turkce
    kaliyor: dil isareti CUMLEDEN geliyor ve ag firlamak zorunda. Bu
    bekci olmadan `ozel_ad_haric` yerine "her zaman bos dize don"
    yazilabilir ve yukaridaki test yine yesil kalirdi.
    """
    yuk = ("🔭 Today: you and John",
           "John tarafında: Satürn → Venüs Üçgen (0.8°, yaklaşıyor)",
           {"type": "friend", "src": "midday",
            "d": BUGUN_GERCEK, "fromUid": "f1"})
    monkeypatch.setattr(ns, "circle_push",
                        lambda p, lang, today=None: (yuk, "gonderilecek",
                                                     True, "John"))

    sonuc, mesajlar = _cevrem_kosusu(
        monkeypatch, [profil(language="en", lastSeenDaily=BUGUN_GERCEK)])

    assert sonuc.skipped.get("dil-uyusmaz") == 1
    assert mesajlar == []


def test_ozel_ad_haric_ALT_DIZEYE_degil_SOZCUGE_bakar():
    """Alt dize eslesmesi bu depoda iki kez yanlis pozitif uretti.

    Ad "Ay" olsa bile "ayrica" bozulmamali; tersine, adin KENDISI
    cikmali. Capa iki yone de calisiyor: desen `\\b` birakilip ham
    `str.replace`e cevrilirse bu test kirmizi yanar.

    ⚠️ SINIR IKI TARAFLI ve tek bir ornek IKISINI OLCMEZ (olculdu
    2026-10-03, mutasyon D4-M03b): SOL `\\b` sokuldugunda — yani desen
    `re.escape(ad) + r"\\b"` yapildiginda — takim YESIL kaliyordu.
    "Ayrica" ornegi yalnizca SAG siniri tutuyor, cunku adin PESINDEN
    sozcuk karakteri geliyor; adin ONUNDEN gelen durum (ad bir sozcugun
    SONU) hic sinanmamisti. Asagidaki ikinci satir onu tutuyor.
    """
    assert ns.ozel_ad_haric("Ayrıca bugün Ay sakin", "Ay") \
        == "Ayrıca bugün   sakin"
    # SOL sinir: ad bir sozcugun SONU oldugunda arindirilmamali.
    # Gorunen ad DOGRULANMAMIS kullanici girdisi (ne istemcide ne
    # kurallarda ne sunucuda bir bicim siniri var — bkz. modul basi),
    # yani kucuk harfli ya da baska bir sozcugun soneki olan bir ad
    # varsayim dis birakilamaz.
    #
    # ⚠️ BUGUNKU ZARAR "ASIRI SILME"dir, dil kacagini MASKELEME DEGIL —
    # ve bu ayrim olculdu, varsayilmadi: gercek sablonlarin (WINBACK_TEXTS
    # 3/10/30 + `pair_transit_lines`) her sozcugunun 2-6 harflik TUM
    # sonekleri ad olarak denendi ve SOL sinir sokuldugunda
    # `language_conflicts`i True'dan False'a ceviren TEK bir ad bile
    # cikmadi. Yani buraya "maskelemeyi onluyor" yazmak olculmemis bir
    # gerekce olurdu; terim metni MUTILE etmeyi onluyor.
    assert ns.ozel_ad_haric("Günay ile ay arasında", "ay") \
        == "Günay ile   arasında"
    # Bos ad metne DOKUNMAMALI: ad tasimayan her uretici bu yoldan
    # geciyor ve davranislari birebir ayni kalmak zorunda.
    assert ns.ozel_ad_haric("Ayrıca bugün Ay sakin", "") \
        == "Ayrıca bugün Ay sakin"
    # Gorunen ad kullanici girdisi: duzenli ifade metakarakteri
    # kacirilmazsa burada `re.error` firlar ya da yanlis yer silinir.
    assert ns.ozel_ad_haric("selam A+B gule gule", "A+B") \
        == "selam   gule gule"


def test_KOSU_geri_kazanim_govdesindeki_adi_da_olcumden_cikarir(
        monkeypatch):
    """Ayni muafiyet 10. basamakta da KOSU TARAFINDA baglanmali.

    `winback_push` adi `PushIcerik.ozel_ad` ile tasiyor ama onu OKUMAK
    kosunun isi. Okumayi atlayan mutasyon `winback_push`in kendi
    bekcilerini YESIL birakir: o testler fonksiyonun donusunu olcuyor,
    agin firlayip firlamadigini olcmuyor. Bu yuzden bekci uctan uca.
    """
    ad = "Şeyma Gülşah"
    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [(_cp(ad), {"fromUid": "f1"})])
    monkeypatch.setattr(
        ns, "_en_iyi_vurus",
        lambda uid, adaylar, today, hesapla: (
            (_cp(ad), {"fromUid": "f1"}, _vurus()), True))
    monkeypatch.setattr(ns, "winback_state", lambda uid, profile: 0)

    sessiz = (dt.datetime.now(dt.timezone.utc).date()
              - dt.timedelta(days=ns.WINBACK_TIERS[1])).isoformat()
    _kosu_ortami(monkeypatch, [profil(language="en", lastSeenDaily=sessiz)])
    sonuc, mesajlar = notify_runner._run(
        "winback", dry_run=True, force=True, ignore_dedupe=True,
        only_uid=None, mark=False)

    assert "dil-uyusmaz" not in sonuc.skipped, (
        f"ad yuzunden dusuruldu: {sonuc.skipped}")
    assert len(mesajlar) == 1, f"kuyruk bos: {sonuc.skipped}"
    assert ad in mesajlar[0].body
    # Olcum GERCEKTEN elde edildi: ad kaynakli dusus `fallback` sayilmamali,
    # yoksa `_SLOT_KIRMIZI_ESIGI["winback"] = 1` tek kullanicida uca 503
    # dondururdu.
    assert sonuc.generation.get("ok") == 1
    assert sonuc.generation.get("fallback", 0) == 0


# ---------------------------------------------------------------------------
# 5: esik kalibrasyonunun SON KULLANMA TARIHI
# ---------------------------------------------------------------------------
#
# `_SLOT_KIRMIZI_ESIGI["winback"] = 1` BUGUNUN nufusuyla dogru. Bagimsiz
# olculdu: 18 profille kuyruk en cok 2, 50 profille en cok 5 (%26 gun),
# 200 profille en cok 20 (%77). Yani esik buyuyen nufusta YANLIS ALARM
# uretir ve uyari yalnizca bir YORUMDA duruyordu — okunmazsa hicbir yerde
# gorunmezdi. Kosu artik bandin disina cikildigini SOYLUYOR.


def test_her_DUSURULMUS_esigin_olculmus_bir_TAVANI_VAR():
    """Iki yone calisan kapi.

    Esigi dusurulen yeni bir slot, olcumunu KAYDETMEDEN eklenemez
    (yoksa "bugun dogru" iddiasi dayanaksiz kalir); tersine, tavan
    kaydi birakilip esik varsayilana donerse olu kayit da kalmaz.
    """
    assert (set(notify_runner._SLOT_KIRMIZI_ESIGI)
            == set(notify_runner._OLCULEN_KUYRUK_TAVANI)), (
        "dusurulmus esik ile olculmus tavan listeleri ayristi")
    for tur, tavan in notify_runner._OLCULEN_KUYRUK_TAVANI.items():
        # Tavanin esikten BUYUK olmasi anlamsiz degil, ZORUNLU: esik
        # tavanin ustundeyse kapi o slotta hic dolmaz (eski kusur).
        assert notify_runner._kirmizi_esigi(tur) <= tavan, tur


def test_kalibrasyon_bandi_ASILMADIKCA_SUSAR():
    """Olcumu olmayan slot ve tavanin altindaki kuyruk konusmamali —
    yoksa uyari her kosuda yanar ve okunmaz hale gelir (bu depoda
    ayni ders bir kez odendi)."""
    tavan = notify_runner._OLCULEN_KUYRUK_TAVANI["winback"]
    assert notify_runner._kalibrasyon_bandi_asildi("winback", tavan) is None
    assert notify_runner._kalibrasyon_bandi_asildi("winback", 0) is None
    # Olcumu OLMAYAN slot: tahminle tavan uydurulmamali.
    assert notify_runner._kalibrasyon_bandi_asildi("daily", 10_000) is None


def test_kalibrasyon_bandi_asilirsa_KOSU_UYARIR(monkeypatch, caplog):
    """Uyari UCTAN UCA kosudan cikmali: saf fonksiyonu olcmek yetmez,
    cunku kusur `_run`in o fonksiyonu HIC cagirmamasiydi."""
    import logging

    tavan = notify_runner._OLCULEN_KUYRUK_TAVANI["winback"]
    sessiz = (dt.datetime.now(dt.timezone.utc).date()
              - dt.timedelta(days=ns.WINBACK_TIERS[0])).isoformat()
    profiller = [profil(uid=f"u{i}", fcmToken=f"token-{i}",
                        lastSeenDaily=sessiz)
                 for i in range(tavan + 1)]
    monkeypatch.setattr(ns, "winback_state", lambda uid, profile: 0)
    _kosu_ortami(monkeypatch, profiller)

    with caplog.at_level(logging.WARNING):
        sonuc, mesajlar = notify_runner._run(
            "winback", dry_run=False, force=True, ignore_dedupe=True,
            only_uid=None, mark=False)

    assert sonuc.queued == tavan + 1, f"kuyruk kurulamadi: {sonuc.skipped}"
    uyari = [r.getMessage() for r in caplog.records
             if "KALIBRASYON BANDI DISINDA" in r.getMessage()]
    assert uyari, "band asildi ama kosu susuyor"
    assert f"kuyruk={tavan + 1}" in uyari[0] and f"tavan={tavan}" in uyari[0]


# ---------------------------------------------------------------------------
# 6: "OLCULECEK SEY YOKTU" ile "OLCTUM VE DUSTU" ayrimini KOSU OKUMALI
# ---------------------------------------------------------------------------
#
# `_en_iyi_vurus`/`winback_push`/`circle_push` `olctu`yu UC DEGERLI
# donduruyor ve gerekcesi kendi docstring'lerinde yazili: None = olculecek
# bir sey yoktu, False = olcum DUSTU. URETICI tarafi bekcili (mutasyon
# D4-M40/M41 kirmizi yaniyor). Eksik olan TUKETICI tarafiydi: kosudaki
# `if olctu is not None:` kapisini kaldiran mutasyonlar (D4-M42 circle,
# D4-M44 winback) takimi YESIL biraktı — 184 test gectii.
#
# ZARAR OLCULDU (_dusus_gerekcesi dogrudan cagrilarak):
#   * winback 30. basamak VERI KULLANMAZ (`WINBACK_TEXTS[30]`te `veri`
#     anahtari yok), yani `olctu` her zaman None. Kapi kalkarsa o profil
#     attempted=1/fallback=1 sayilir ve `_SLOT_KIRMIZI_ESIGI["winback"]=1`
#     ile `uretim-tamamen-dustu` -> uc **503**. Push BASARIYLA gitmis
#     olsa bile. Yani 30 gunluk son cagrinin gittigi HER gun Scheduler
#     gunlugu kirmizi yanardi.
#   * circle'da `olctu is None` demek "kullanicinin cevresi yok"
#     (`_cift_adaylari` bos). Kapi kalkarsa cevresi olmayan UC kullanici
#     attempted=3/fallback=3 uretir ve circle esigi 3 oldugu icin kosu
#     yine 503 doner — hicbir sey bozuk olmadigi halde.
#
# Iki bekci de UCTAN UCA: kusur ureticide degil kosunun DEFTERINDE, ve
# 503 karari `tamamen_dustu()`den geciyor — bekciler o karari DOGRUDAN
# soruyor, `generation` sozlugunu okumakla yetinmiyor.


def _kosu(monkeypatch, tur, profiller):
    _kosu_ortami(monkeypatch, profiller)
    return notify_runner._run(tur, dry_run=False, force=True,
                              ignore_dedupe=True, only_uid=None, mark=False)


def test_geri_kazanimin_30_BASAMAGI_kosuyu_KIRMIZI_yapmaz(monkeypatch):
    """Veri kullanmayan basamak URETIM DUSUSU sayilmamali.

    Uc BAGIMSIZ isaret: (1) push GERCEKTEN gitti (yani kirmizi yanacak
    bir sey yok), (2) `generation` DENEME saymadi, (3) 503 karari
    `None` — ucuncusu olmadan bekci yalnizca bir sozlugu olcer, ucun
    gercekten 200 dondugunu olcmez.
    """
    sessiz = (dt.datetime.now(dt.timezone.utc).date()
              - dt.timedelta(days=ns.WINBACK_TIERS[-1])).isoformat()
    monkeypatch.setattr(ns, "winback_state", lambda uid, profile: 0)

    sonuc, mesajlar = _kosu(
        monkeypatch, "winback", [profil(lastSeenDaily=sessiz)])

    assert len(mesajlar) == 1 and sonuc.sent == 1, (
        f"30. basamak hic gitmedi: {sonuc.skipped}")
    assert sonuc.generation.get("attempted", 0) == 0, (
        f"veri kullanmayan basamak DENEME sayildi: {sonuc.generation}")
    assert notify_runner.tamamen_dustu(sonuc) is None, (
        f"uc 503 dondururdu: status={sonuc.status} {sonuc.generation}")


def test_CEVRESI_OLMAYAN_kullanicilar_kosuyu_KIRMIZI_yapmaz(monkeypatch):
    """"Cevresi yok" ile "cevre olcumu dustu" ayni kovaya girmemeli.

    Profil sayisi ESIGE BAGLI secildi (`_kirmizi_esigi("circle")`): tek
    profille mutasyon esigin altinda kalir ve bekci sahte bir guven
    verirdi. Esik degisirse bu test onunla birlikte olceklenir.
    """
    monkeypatch.setattr(ns, "_cift_adaylari", lambda uid, lang: [])
    esik = notify_runner._kirmizi_esigi("circle")
    profiller = [profil(uid=f"u{i}", fcmToken=f"token-{i}",
                        lastSeenDaily=BUGUN_GERCEK)
                 for i in range(esik)]

    sonuc, mesajlar = _kosu(monkeypatch, "circle", profiller)

    assert sonuc.skipped.get("cevre-yok") == esik, (
        f"senaryo kurulamadi: {sonuc.skipped}")
    assert sonuc.generation.get("attempted", 0) == 0, (
        f"cevresi olmayan kullanici DENEME sayildi: {sonuc.generation}")
    assert notify_runner.tamamen_dustu(sonuc) is None, (
        f"uc 503 dondururdu: status={sonuc.status} {sonuc.generation}")


def test_cevre_olcumu_GERCEKTEN_dustugunde_kosu_KIRMIZI_yanar(monkeypatch):
    """KARSI ORNEK: ayrim agi KAPATMADI.

    Bu bekci olmadan yukaridaki ikisi "hicbir zaman deneme sayma"
    yazilarak da yesil kalirdi — ve o, paketin onardigi asil kusurun
    (bir ay yesil yalan) geri gelmesi olurdu. Burada aday VAR ama olcum
    DUSUYOR (`olctu=False`): kosu bunu uretim dususu saymak ZORUNDA.
    """
    monkeypatch.setattr(ns, "circle_push",
                        lambda p, lang, today=None: (None, "olay-yok",
                                                     False, ""))
    esik = notify_runner._kirmizi_esigi("circle")
    profiller = [profil(uid=f"u{i}", fcmToken=f"token-{i}",
                        lastSeenDaily=BUGUN_GERCEK)
                 for i in range(esik)]

    sonuc, _mesajlar = _kosu(monkeypatch, "circle", profiller)

    assert sonuc.generation.get("attempted") == esik
    assert sonuc.generation.get("ok", 0) == 0
    assert notify_runner.tamamen_dustu(sonuc) == "uretim-tamamen-dustu", (
        f"gercek dusus 200 donuyor: status={sonuc.status}")

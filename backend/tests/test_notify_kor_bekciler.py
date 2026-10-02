"""KOR KALAN KAPILAR: mutasyon sinavindan sonra eklenen dort civi.

Bu dosya ikinci bir DOGRULAMA turunda dogdu. CV/K7 paketinin kapilari 45
MINIMAL mutasyonla (her biri TEK terim) sinandi; 38'i kirmizi yandi, dordu
YESIL KALDI. Burasi o dort bosluk icin. Her birinin neden kor kaldigi
asagida yazili, cunku bosluklarin SEBEBI ortak: testler o katmani
`monkeypatch` ile tamamen degistiriyor ya da beklenen degeri kodun
KENDI sabitinden turetiyordu — bir seyin dogrulugunu kendi tanimina
sormak sinamamaktir.

1. **`should_send`in `winback` kapisi.** Kapi `should_send` icinde
   duruyor ama HICBIR test onu o duzeyde cagirmiyordu: basamak testleri
   `winback_tier`i dogrudan sinar, uctan uca testler ise kosudan gecer ve
   kosu basamagi YENIDEN okuyup "basamak-kayboldu" ile atliyor. Yani
   kosunun yedek kapisi `should_send`in kapisini MASKELIYOR (olculdu:
   D13 ve D38 mutasyonlari birlikte). Bedeli davranis degil OLCUM:
   kapi dusse hicbir push yanlis gitmez ama sessiz olmayan HER kullanici
   her gun "basamak-kayboldu" kovasina yazilir — o kova bir YARIS
   gostergesi, ve yanlis adla dolarsa gercek yarisi gizler. Ustelik
   `should_send` bu modulun dis sozlesmesi; dogrulugu cagiranin yedek
   kapisina emanet edilemez.

2. **10. basamagin GUNDE BIR hesabi.** `_cevre_govdesi` ayni olcumu
   Cevrem slotuyla paylasiyor ve onbellek bosken bir aday HESAPLIYOR
   (`hesapla=True`). Hicbir test bunu tutmuyordu cunku 10. basamak
   testleri `_en_iyi_vurus`u butunuyle sahteliyor. Bedeli tam da paketin
   varlik sebebi: 10 gundur girmemis kullanici o gun iliski ekranini
   KESINLIKLE acmamistir, yani onbellek bostur — terim dusse 10. basamak
   HER ZAMAN veri-siz yalin soruya duserdi ve "KISISEL ton" diye
   yazilan sey hicbir zaman kisisel olmazdi. Kusur sessiz: `olctu=False`
   dokume girer ama push gider, yani kimse fark etmez.

3. **Yeni slotlarin TERCIH anahtari.** `PREF_FIELDS["circle"]`in
   `notifyFriends` olmasi BILINCLI bir davranis degisikligi: ayni icerik
   oglenin yedek dalindayken `notifyDaily`ye bagliydi, yani arkadas
   bildirimlerini kapatip gunlugu acik birakan kullanici cift anini
   ALIYORDU. Haritayi eski haline dondurmek (tek kelime) takimi YESIL
   biraktı — yani kullanicinin acik iradesini geri bozan degisiklik
   sessizce gecerdi. Capa UC BAGIMSIZ ISARET: harita sabiti, `circle`in
   davranisi, `winback`in davranisi. Beklenen deger `PREF_FIELDS`ten
   TURETILMEZ (bkz. bu turda yakalanan aksam-ailesi kusuru: parametre
   listesini kumenin kendisinden turetmek, kume kuculdugunde testi de
   kucultuyordu).

4. **Tepki kaydinin gonderime bagli olmasi.** `/reaction` kaydi yalniz
   `sonuc.sent` ise yaziyor ve gerekcesi yorumda yazili ("FCM'in anlik
   hatasi yuzunden arkadasin o gunku tek durtme hakki yanmasin"), ama
   hicbir test gonderimin DUSTUGU hali kosturmuyordu: fixture her zaman
   basarili donuyordu. Terim dusse FCM'in tek bir anlik hatasi, o cifti
   o gun icin tamamen susturur ve kullanici hicbir sey gormez.

Calistirma:
  .venv/Scripts/python.exe -m pytest tests/test_notify_kor_bekciler.py -q
"""
from __future__ import annotations

import datetime as dt

import pytest
from fastapi.testclient import TestClient

from core.auth import AuthUser, get_current_user
from services import notification_service as ns

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulamasi ice aktarilamadi: {_APP_IMPORT_ERROR}",
)

BUGUN = dt.date(2026, 6, 15)
GUN = BUGUN.isoformat()

SAHTE_GOKYUZU = {"moon_phase": {"key": "full_moon", "name": "Dolunay",
                                "illumination": 98}, "retrogrades": []}


# ---------------------------------------------------------------------------
# Sahte gonderim kaydi — GERCEK `already_sent`/`mark_sent`/`winback_state`
# kodu kossun diye yalnizca dokuman pinlenir.
# ---------------------------------------------------------------------------

class _SahteAnlik:
    def __init__(self, veri: dict | None):
        self._veri = veri
        self.exists = veri is not None

    def to_dict(self):
        return dict(self._veri or {})


class _SahteDoc:
    def __init__(self, depo: dict):
        self.depo = depo

    def get(self):
        return _SahteAnlik(self.depo if self.depo else None)

    def set(self, veri, merge=False):
        if not merge:
            self.depo.clear()
        self.depo.update(veri)


@pytest.fixture()
def kayit(monkeypatch):
    depo: dict = {}
    monkeypatch.setattr(ns, "_notification_doc", lambda uid: _SahteDoc(depo))
    return depo


def profil(gun_once: int | None = None, **alanlar):
    """Saat dilimi UTC, sessiz saat KAPALI — testin derdi saat degil kapi."""
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
    }
    if gun_once is not None:
        temel["lastSeenDaily"] = (BUGUN - dt.timedelta(days=gun_once)
                                  ).isoformat()
    temel.update(alanlar)
    return temel


def utc(saat: int) -> dt.datetime:
    return dt.datetime(BUGUN.year, BUGUN.month, BUGUN.day, saat,
                       tzinfo=dt.timezone.utc)


def _cp(label: str = "eşin", key: str = "u1-f1"):
    from services import synastry_service
    return synastry_service.Counterpart(key=key, birth={}, label=label,
                                        sun_sign="leo")


def _vurus():
    return {"side": "other", "transit": "Saturn", "natal": "Venus",
            "aspect": "Trine", "orb": 0.8, "movement": "applying"}


# ---------------------------------------------------------------------------
# 1: `should_send`in winback kapisi KENDI duzeyinde
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("ad,p,beklenen_gerekce", [
    # Sessizlik esigin altinda: hic basamak yok.
    ("sessizlik-kisa", profil(gun_once=2), "sessizlik-kisa"),
    # Son giris bilinmiyor: "hic okumadin" ile "uc gundur okumadin" ayni
    # sey degil ve elimizde yalniz ikincisini olcecek veri var.
    ("son-giris-yok", profil(), "son-giris-bilinmiyor"),
])
def test_should_send_winback_kapisini_KENDI_duzeyinde_tutar(
        kayit, ad, p, beklenen_gerekce):
    """Kapi `should_send` icinde ve orada sinanmak zorunda.

    Kosunun yedek kapisi ("basamak-kayboldu") bu kapiyi maskeliyor; o
    yuzden capa KOSU DEGIL dogrudan `should_send`in donusu. Gerekce de
    civili, cunku bu kapinin urunu bir BOOL degil bir AD: panel atlanma
    nedenlerini o adla gosteriyor.
    """
    gonder, gerekce = ns.should_send(p, "winback", utc(19))
    assert gonder is False, f"{ad}: basamaksiz profil winback'ten gecti"
    assert gerekce == beklenen_gerekce


def test_should_send_30_SONRASI_sessizligi_kendi_duzeyinde_tutar(kayit):
    """31. gun: son basamak gitmisse SUSAR (kovulma degil, saygi).

    Bu, 1. maddedeki kapinin en pahali hali: `winback_tier` None donuyor
    ama `should_send` onu okumazsa kosu her gun yeniden karar vermek
    zorunda kalir ve atlanma gerekcesi yanlis adla dolar.
    """
    p = profil(gun_once=31)
    kayit.update(ns.winback_sent_fields(30, p))
    gonder, gerekce = ns.should_send(p, "winback", utc(19))
    assert (gonder, gerekce) == (False, "basamaklar-bitti")


def test_should_send_basamak_VARSA_gecirir(kayit):
    """Karsi ornek: kapi her seyi kesmiyor. Bu satir olmasa yukaridaki
    iki test `should_send` hep False donse de yesil kalirdi."""
    gonder, gerekce = ns.should_send(profil(gun_once=3), "winback", utc(19))
    assert (gonder, gerekce) == (True, "gonderilecek")


# ---------------------------------------------------------------------------
# 2: 10. basamagin kendi hesabi
# ---------------------------------------------------------------------------

def test_onuncu_basamak_onbellek_BOSKEN_GUNDE_BIR_hesaplar(monkeypatch):
    """10 gundur girmeyen kullanicinin onbellegi TANIMI GEREGI bos.

    `_en_iyi_vurus`u sahtelemek bu kapiyi gizliyordu; burada gercek
    fonksiyon kosuyor ve yalniz `synastry_service` katmani sahtelenir.
    Iki sey birden olculur: gercekten HESAPLANDI mi (bir kez) ve govde
    o olcumun kendisini mi tasiyor.
    """
    from services import synastry_service

    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [(_cp(), {"pid": "p1"})])
    monkeypatch.setattr(synastry_service, "pair_transits_cached",
                        lambda uid, other, today=None: None)
    hesaplanan: list = []

    def sahte_hesap(uid, other, today=None):
        hesaplanan.append(other.label)
        return {"hits": [_vurus()]}

    monkeypatch.setattr(synastry_service, "pair_transits", sahte_hesap)

    icerik, veri, olctu = ns.winback_push(profil(gun_once=10), "tr", 10,
                                          sky=SAHTE_GOKYUZU, today=BUGUN)

    assert hesaplanan == ["eşin"], (
        "10. basamak onbellek bosken HESAPLAMADI — kullaniciya her zaman "
        "veri-siz yalin soru giderdi, yani 'KISISEL ton' bos bir ad olurdu")
    assert olctu is True
    assert icerik.govde != ns.WINBACK_TEXTS[10]["tr"]["yalin"]
    assert "eşin" in icerik.govde and "Satürn" in icerik.govde
    assert icerik.soru is True and veri["src"] == "winback"


# ---------------------------------------------------------------------------
# 3: yeni slotlarin tercih anahtari
# ---------------------------------------------------------------------------

def test_yeni_slotlarin_TERCIH_ANAHTARI_civili(kayit):
    """UC BAGIMSIZ ISARET; beklenen deger `PREF_FIELDS`ten TURETILMEZ.

    (a) Harita sabiti. `circle` ELLE yazilmis `notifyFriends` olmak
        zorunda: icerik cevredeki insanlarla ilgili. Ayni icerik oglenin
        yedek dalindayken `notifyDaily`ye bagliydi, yani arkadas
        bildirimlerini KAPATAN kullanici onu aliyordu. Haritanin eski
        haline donmesi kullanicinin acik iradesini geri bozar.
    (b) `circle`in davranisi: `notifyFriends=False` olan kullanici 18:00'de
        gecmemeli, `notifyDaily=False` olan ise GECMELI (kapi dogru
        anahtara bagli mi, yoksa yalnizca "bir anahtara" mi).
    (c) `winback`in davranisi: simetrik olarak `notifyDaily`ye bagli —
        geri kazanimin varsayilan sesi gokyuzunden bir ayrinti.
    """
    assert ns.PREF_FIELDS["circle"] == "notifyFriends"
    assert ns.PREF_FIELDS["winback"] == "notifyDaily"

    # (b) circle ⇄ notifyFriends
    assert ns.should_send(profil(gun_once=0, notifyFriends=False),
                          "circle", utc(18)) == (False, "tercih-kapali")
    assert ns.should_send(profil(gun_once=0, notifyDaily=False),
                          "circle", utc(18)) == (True, "gonderilecek")

    # (c) winback ⇄ notifyDaily
    assert ns.should_send(profil(gun_once=3, notifyDaily=False),
                          "winback", utc(19)) == (False, "tercih-kapali")
    assert ns.should_send(profil(gun_once=3, notifyStreak=False),
                          "winback", utc(19)) == (True, "gonderilecek")


# ---------------------------------------------------------------------------
# 4: tepki kaydi yalniz basarili gonderimde
# ---------------------------------------------------------------------------

@pytest.fixture()
def tepki_ortami_dusen(monkeypatch, kayit):
    """Arkadaslik dogru, alici uygun, ama FCM GONDERMIYOR.

    Mevcut tepki testleri her zaman basarili bir `send` sahteliyordu; bu
    fixture tam tersini kurar, cunku civilenen sey "kayit gonderime
    BAGLI mi".
    """
    from services import profile_service, push_service

    monkeypatch.setattr(profile_service, "are_friends", lambda a, b: True)
    monkeypatch.setattr(
        profile_service, "get_profile",
        lambda uid: profil(gun_once=0, uid=uid, displayName=f"Ad-{uid}"))
    denenen: list = []

    def dusen_send(mesajlar):
        denenen.extend(mesajlar)
        return push_service.SendResult(
            sent=0, failed=len(mesajlar), pruned=[],
            failed_uids=[m.uid for m in mesajlar])

    monkeypatch.setattr(push_service, "send", dusen_send)
    yield denenen, kayit
    app.dependency_overrides.clear()


def _tepki(client, gonderen: str, alici: str = "alici"):
    app.dependency_overrides[get_current_user] = lambda: AuthUser(uid=gonderen)
    return client.post("/api/v1/notify/reaction",
                       json={"friend_uid": alici, "reaction": "shine"})


@uygulama_gerekir
def test_tepki_kaydi_yalniz_BASARILI_gonderimde_yazilir(tepki_ortami_dusen):
    """FCM'in anlik hatasi arkadasin o gunku tek hakkini YAKMAMALI.

    Yorumun gerekcesi buydu ama hicbir test dusen gonderimi
    kosturmuyordu. Iki bagimsiz isaret: kayit YAZILMAMIS olmali ve
    ikinci deneme GERCEKTEN kuyruga girmis olmali (yalniz kaydi okumak,
    atlamanin baska bir kapidan gelmedigini kanitlamaz).
    """
    denenen, kayit = tepki_ortami_dusen
    with TestClient(app) as client:
        birinci = _tepki(client, "arkadas-a").json()
        ikinci = _tepki(client, "arkadas-a").json()

    assert birinci == {"status": "ok", "sent": 0}
    assert "reaction-arkadas-aLastSent" not in kayit, (
        "gonderim dusmesine ragmen kayit yazildi — arkadasin o gunku "
        "tek durtme hakki yandi")
    assert ikinci == {"status": "ok", "sent": 0}
    assert len(denenen) == 2, "ikinci deneme hic kuyruga girmedi"

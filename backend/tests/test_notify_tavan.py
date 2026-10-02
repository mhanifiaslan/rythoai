"""Bildirim BUTCESI: gunluk toplam tavan + aksam ailesi + tepki istismari.

Bu dosyanin derdi TEK bir sayi: kullanicinin bir gunde kac bildirim
aldigi. Ucu de olculdu, hicbiri varsayilmadi:

1. **Zamanlanmis tavan 3'tu.** Olcum gercek `should_send` ile,
   Scheduler'in gercek dakika sirasiyla (:05 daily, :08 checkin,
   :10 streak, :12 midday) 24 yerel saat boyunca kosturularak alindi.
   Yeni iki slot (`circle`, `winback`) bu sayiyi YUKSELTMEMELI — yoksa
   48, "calisiyor ama yanlis hissettiriyor"u onarmak yerine buyutur.
2. **Olay yolunda tavan SONSUZDU.** `can_send_event` yalniz
   jeton/tercih/sessiz saate bakiyordu.
3. **`/notify/reaction` hicbir tekrar korumasina tabi degildi.** Tek bir
   arkadas ayni tepkiyi istedigi kadar gonderip alicinin telefonunu
   sinirsiz titretebiliyordu; `infra/firestore.rules` `nudges` kurali da
   olusturma sayisini sinirlamiyor, yani tek hat bu uctu.

Civilenen degismezler:

- Zamanlanmis yolun tavani, senaryo ne olursa olsun, `GUNLUK_PUSH_TAVANI`
  eksi bir. O bir, insan yoluna (arkadas durtmesi) ayrilmis paydir.
- Tavan sayimi TURETILMIS: `{tur}LastSent == gun` alanlarindan. Yalniz
  BUGUNU ve yalniz GERCEK gonderim alanlarini sayar.
- Tavan okunamadiginda ACIK kalir, ama onundeki tekrar korumasi KAPANIR;
  yani okuma kesintisinde bildirim yine gitmez.
- Aksam penceresinde (`EVENING_FAMILY`, yerel 18-20) en fazla BIR bildirim.
- Ayni arkadastan ayni gun ikinci push gitmez; BASKA arkadas kendi hakkini
  kullanir; tavan dolunca ikisi de susar.

Calistirma:
  .venv/Scripts/python.exe -m pytest tests/test_notify_tavan.py -q
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

GUN = "2026-06-15"


# ---------------------------------------------------------------------------
# Sahte gonderim kaydi
#
# `_notification_doc` pinlenerek GERCEK `already_sent` / `mark_sent` /
# `gunluk_push_sayisi` kodu kosuyor. Fonksiyonlarin kendisi sahtelenseydi
# test, sayimin DOGRU alanlara baktigini degil yalnizca bir cagri
# yapildigini olcerdi — ve bu dosyanin tek derdi tam olarak o sayim.
# ---------------------------------------------------------------------------

class _SahteAnlik:
    def __init__(self, veri: dict | None):
        self._veri = veri
        self.exists = veri is not None

    def to_dict(self):
        return dict(self._veri or {})


class _SahteDoc:
    """`set(merge=True)` davranisini taklit eden tek dokuman."""

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
    """Gonderim kaydi deposu; testler dogrudan icine yazar."""
    depo: dict = {}
    monkeypatch.setattr(ns, "_notification_doc", lambda uid: _SahteDoc(depo))
    return depo


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


def utc(saat: int) -> dt.datetime:
    return dt.datetime(2026, 6, 15, saat, tzinfo=dt.timezone.utc)


# ---------------------------------------------------------------------------
# 1: zamanlanmis tavan — ENUMERE EDILEREK
# ---------------------------------------------------------------------------

#: Scheduler isinin gercek dakika sirasi (infra/create-scheduler.ps1).
#: Sira onemli: ayni yerel saate dusen turlerden ONCE kosan isaretler.
DAKIKA_SIRASI = ("daily", "checkin", "streak", "midday", "circle", "winback")

#: Aksam penceresinin uyeleri — SABIT YAZILDI, `ns.EVENING_FAMILY`den
#: TURETILMEDI.
#:
#: Ilk hali turetiyordu ve mutasyon sinavinda KOR cikti: kume
#: ("checkin", "streak")'e indirildiginde parametre listesi de kuculdu,
#: yani test kaldirilan uyeleri hic sinamadi ve YESIL kaldi. Bir seyin
#: dogrulugunu onun kendi tanimina sorarak sinamak, sinamamaktir.
#:
#: Kume degisirse `test_aksam_ailesi_uyeleri_sabit` kirmizi yanar ve bu
#: liste BILINCLI olarak guncellenir.
AKSAM_AILESI = ("circle", "winback", "checkin", "streak")


def _bir_gunde_gecenler(p: dict) -> list[tuple[str, int]]:
    """Bir yerel gun boyunca `should_send`ten GECEN (tur, saat) ciftleri.

    Zamanlayici saatte bir, her tur icin ayri bir isle kosuyor; gecen her
    tur gonderim kaydina isaretlenir ve sonraki turler onu gorur. Olcum
    budur — sabit bir liste degil.
    """
    gecen: list[tuple[str, int]] = []
    for saat in range(24):
        an = utc(saat)
        for tur in DAKIKA_SIRASI:
            gonder, _ = ns.should_send(p, tur, an)
            if gonder:
                gecen.append((tur, saat))
                ns.mark_sent(p["uid"], tur, GUN)
    return gecen


@pytest.mark.parametrize("ad,degisiklik", [
    # Aktif kullanici: dun girmis. Geri kazanim penceresi kapali.
    ("aktif", {"lastSeenDaily": "2026-06-14"}),
    # Sessiz kullanici: bes gundur girmemis. Seri 0, yani `streak` ona
    # yapisal olarak ulasamiyor — geri kazanimin var olma sebebi bu.
    ("sessiz", {"lastSeenDaily": "2026-06-10", "streakCount": 0}),
    # Bugun okumus kullanici: seri hatirlatmasi anlamsiz.
    ("bugun-okumus", {"lastSeenDaily": GUN}),
])
def test_zamanlanmis_tavan_insan_payini_bozmaz(kayit, ad, degisiklik):
    """Zamanlanmis yolun tavani `GUNLUK_PUSH_TAVANI - 1` olmak zorunda.

    NEDEN bu iliski civilendi: `GUNLUK_PUSH_TAVANI` tahminle secilmis bir
    sayi degil, OLCULEN tavan (3) artiik insan yolu icin ayrilmis bir pay
    (1). Yeni bir zamanlanmis slot bu sayiyi 4'e cikarirsa bu test kirmizi
    yanar ve tavan yeniden OLCULMEK zorunda kalir; sessizce buyumez.
    """
    gecen = _bir_gunde_gecenler(profil(**degisiklik))

    assert len(gecen) == ns.GUNLUK_PUSH_TAVANI - 1, (
        f"{ad}: zamanlanmis tavan degisti -> {gecen}")
    # Sabah ve ogle her senaryoda var; ucuncu slot senaryoya gore degisir.
    assert ("daily", 9) in gecen
    assert ("midday", 13) in gecen
    # Ucuncu slot AKSAM penceresinden ve tek.
    aksam = [t for t, _ in gecen if t in AKSAM_AILESI]
    assert len(aksam) == 1, f"{ad}: aksam penceresinde birden fazla -> {gecen}"


def test_sessiz_kullanici_aksam_slotu_geri_kazanimdir(kayit):
    """UC GUNDUR GIRMEYENIN SERISI 0 ve bu yuzden `streak` ona hic
    ulasmiyordu: en cok cagrilmasi gereken kisi sistemin yapisal olarak en
    sessiz kaldigi kisiydi. Artik aksam slotunu geri kazanim aliyor."""
    gecen = dict(_bir_gunde_gecenler(
        profil(lastSeenDaily="2026-06-10", streakCount=0)))

    assert gecen.get("winback") == ns.TARGET_HOURS["winback"]
    assert "streak" not in gecen and "checkin" not in gecen
    # Cevrem slotu geri kazanima yol verdi (ayni olcumden beslenirler).
    assert "circle" not in gecen


# ---------------------------------------------------------------------------
# 2: tavanin kendisi
# ---------------------------------------------------------------------------

def test_tavan_dolunca_zamanlanmis_push_durur(kayit):
    """Tavanin ALTINDA gecer, tavanda durur."""
    for i in range(ns.GUNLUK_PUSH_TAVANI - 1):
        kayit[f"sahte{i}LastSent"] = GUN
    gonder, gerekce = ns.should_send(profil(), "daily", utc(9))
    assert gonder, gerekce

    kayit[f"sahte{ns.GUNLUK_PUSH_TAVANI}LastSent"] = GUN
    gonder, gerekce = ns.should_send(profil(), "daily", utc(9))
    assert not gonder and gerekce == "gunluk-tavan"


def test_tavan_olay_yolunu_da_kapsar(kayit):
    """Telefon push'un hangi alt sistemden geldigini bilmiyor: arkadas
    durtmesi de ayni butceden harcar. Bu yol bugune dek HICBIR sayaca
    tabi degildi."""
    for i in range(ns.GUNLUK_PUSH_TAVANI):
        kayit[f"sahte{i}LastSent"] = GUN
    gonder, gerekce = ns.can_send_event(profil(), "friend", utc(12))
    assert not gonder and gerekce == "gunluk-tavan"

    kayit.clear()
    gonder, gerekce = ns.can_send_event(profil(), "friend", utc(12))
    assert gonder, gerekce


def test_tavan_yalniz_bugunun_gercek_gonderimlerini_sayar(kayit):
    """Turetilmis sayim YANLIS ADLA sunulmamali: dunun kaydi ve gonderim
    OLMAYAN alanlar (govde hafizasi, capa, zaman damgasi) sayiya girmez.

    `dailyBodyDay` ve `winbackAnchor` de bugunun tarihini tasiyabilir —
    sayim son eke bagli oldugu icin onlari gormez. Alanlarin hepsi ayni
    dokumanda yasadigi icin bu ayrim kagit uzerinde degil gercek."""
    kayit.update({
        "dailyLastSent": GUN,
        "middayLastSent": GUN,
        "checkinLastSent": "2026-06-14",      # dun
        "dailyBodyDay": GUN,                  # gonderim degil, hafiza
        "winbackAnchor": GUN,                 # gonderim degil, capa
        "updatedAt": GUN,
    })
    assert ns.gunluk_push_sayisi("u1", GUN) == 2


def test_tavan_okuma_dusunce_acik_kalir_tekrar_korumasi_kapatir(monkeypatch):
    """Tavan okuma dusunce ACIK kalir (0 doner) — ama ayni kesintide
    tekrar korumasi KAPANIR, yani bildirim yine gitmez.

    Tavani da kapatmak ayni karari iki kez vermek olurdu ve butun
    bildirimleri tek bir Firestore kesintisine baglardi.

    ⚠️ Bu testin ilk hali guvenceyi SIRAYA bagliyordu ("tekrar korumasi
    once gectigi icin guvenli"); dogrulama turunda olculdu ve YANLIS
    cikti: olay yolu TERS sirada kosuyor (`can_send_event` tavani bakar,
    `already_sent` cagirana SONRA gelir) ve ayni guvenceyi veriyor.
    Guvence, gonderimden once IKI kapinin da degerlendirilmesinden
    geliyor. Bu yuzden asagidaki olcum olay yolunu da kapsiyor.
    """
    monkeypatch.setattr(ns, "_notification_doc", lambda uid: None)

    assert ns.gunluk_push_sayisi("u1", GUN) == 0
    assert ns.already_sent("u1", "daily", GUN) is True
    gonder, gerekce = ns.should_send(profil(), "daily", utc(9))
    assert not gonder and gerekce == "zaten-gonderildi"
    # OLAY YOLU: tavan kapisi ONCE kosuyor ve okuma dustugu icin ACIK
    # geciyor; gonderimi engelleyen sey cagirandaki `already_sent`.
    gonder_olay, gerekce_olay = ns.can_send_event(profil(), "friend",
                                                  utc(12))
    assert gonder_olay and gerekce_olay == "gonderilecek"


# ---------------------------------------------------------------------------
# 3: aksam ailesi
# ---------------------------------------------------------------------------

def test_aksam_ailesi_uyeleri_sabit():
    """Kume ile bu dosyadaki SABIT liste birebir ayni olmak zorunda.

    Bu test, asagidaki davranis testinin capasidir: parametre listesi
    kumeden turetilseydi kume kuculdugunde test de kuculur ve kaldirilan
    uyeler hic sinanmazdi (mutasyon sinavinda tam bu oldu).

    Ikinci BAGIMSIZ isaret: her uyenin hedef saati gercekten AKSAM
    penceresinde (18-21). Yalniz ad listesi tutulsaydi, sabah bir turu
    aileye katmak sessizce gecerdi ve tek bir akSam bildirimi ertesi
    sabahin okumasini yutabilirdi.
    """
    assert tuple(ns.EVENING_FAMILY) == AKSAM_AILESI
    for tur in AKSAM_AILESI:
        assert 18 <= ns.TARGET_HOURS[tur] <= 21, tur


@pytest.mark.parametrize("giden", AKSAM_AILESI)
def test_aksam_penceresinde_en_fazla_bir_bildirim(kayit, giden):
    """Aile icindeki biri gittiyse DIGERLERININ HEPSI susar — sira ne
    olursa olsun. Kural simetrik; eskiden yalniz checkin/streak ciftine
    elle yazilmisti ve yeni bir tur eklendiginde sessizce eksik kalirdi."""
    kayit[f"{giden}LastSent"] = GUN
    # Bes gundur girmemis profil: geri kazanim da aday, Cevrem de.
    p = profil(lastSeenDaily="2026-06-10", streakCount=5)

    for tur in AKSAM_AILESI:
        if tur == giden:
            continue
        gonder, gerekce = ns.should_send(p, tur, utc(ns.TARGET_HOURS[tur]))
        assert not gonder, f"{tur} aksam ailesini asti"
        assert gerekce == f"aksam-{giden}-gitti", (tur, gerekce)


def test_sabah_ve_ogle_aksam_ailesinden_degil(kayit):
    """Aile yalniz AKSAM penceresi: sabah okumasi akSam bir sey gittigi
    icin kaybolmaz. Aksi halde tek bir akSam bildirimi ertesi sabahin
    okumasini da yutabilirdi."""
    kayit["checkinLastSent"] = GUN
    for tur, saat in (("daily", 9), ("midday", 13)):
        gonder, gerekce = ns.should_send(profil(), tur, utc(saat))
        assert gonder, (tur, gerekce)


# ---------------------------------------------------------------------------
# 4: /notify/reaction istismar yolu
# ---------------------------------------------------------------------------

@pytest.fixture()
def tepki_ortami(monkeypatch, kayit):
    """Tepki ucu: arkadaslik dogru, alici push'a uygun, gonderim sayiliyor."""
    from services import profile_service, push_service

    monkeypatch.setattr(profile_service, "are_friends", lambda a, b: True)
    monkeypatch.setattr(
        profile_service, "get_profile",
        lambda uid: profil(uid=uid, displayName=f"Ad-{uid}"))
    gonderilen: list = []

    def sahte_send(mesajlar):
        gonderilen.extend(mesajlar)
        return push_service.SendResult(sent=len(mesajlar), failed=0,
                                       pruned=[], failed_uids=[])

    monkeypatch.setattr(push_service, "send", sahte_send)
    yield gonderilen
    app.dependency_overrides.clear()


def _tepki(client, gonderen: str, alici: str = "alici"):
    app.dependency_overrides[get_current_user] = lambda: AuthUser(
        uid=gonderen)
    return client.post("/api/v1/notify/reaction",
                       json={"friend_uid": alici, "reaction": "shine"})


@uygulama_gerekir
def test_tepki_ayni_arkadastan_ikinci_pushu_atmaz(tepki_ortami):
    """OLCULEN istismar yolu: bu uc hicbir tekrar korumasina tabi degildi,
    yani tek arkadas sinirsiz push attirabiliyordu."""
    with TestClient(app) as client:
        birinci = _tepki(client, "arkadas-a").json()
        ikinci = _tepki(client, "arkadas-a").json()

    assert birinci["status"] == "ok" and birinci["sent"] == 1
    assert ikinci == {"status": "skipped", "reason": "zaten-gonderildi"}
    assert len(tepki_ortami) == 1, "ikinci push gonderildi"


@uygulama_gerekir
def test_tepki_baska_arkadasin_hakkini_yemez(tepki_ortami):
    """Koruma CIFT basina: bir arkadasin durtmesi digerini susturmamali.
    Tek bir gunluk anahtar kullanilsaydi ilk durten herkesi kilitlerdi."""
    with TestClient(app) as client:
        a = _tepki(client, "arkadas-a").json()
        b = _tepki(client, "arkadas-b").json()

    assert a["sent"] == 1 and b["sent"] == 1
    assert len(tepki_ortami) == 2


@uygulama_gerekir
def test_tepki_gunluk_tavani_asamaz(tepki_ortami):
    """Cift basina koruma TEK BASINA yetmez: yeterince arkadas ayni gun
    bombardiman yapabilirdi. Tavan dolunca uc sessizce 200 degil GORUNUR
    bir gerekceyle atlar."""
    with TestClient(app) as client:
        yanitlar = [_tepki(client, f"arkadas-{i}").json()
                    for i in range(ns.GUNLUK_PUSH_TAVANI + 2)]

    gidenler = [y for y in yanitlar if y.get("status") == "ok"]
    assert len(gidenler) == ns.GUNLUK_PUSH_TAVANI
    assert yanitlar[-1] == {"status": "skipped", "reason": "gunluk-tavan"}
    assert len(tepki_ortami) == ns.GUNLUK_PUSH_TAVANI

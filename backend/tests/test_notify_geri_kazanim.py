"""GERI KAZANIM (K7) ve CEVREM slotu — kademeli cagri, sonra sessizlik.

Olculen bosluk: geri kazanim bildirimi HIC YOKTU. `lastSeenDaily` depoda
alti yerde okunuyordu (admin suzgeci, seri kapisi, istatistik, jeton
sahipligi) ama hicbiri "X gundur girmedi"yi HESAPLAMIYORDU. Ustelik
mevcut tek geri cagri turu olan `streak`, `streakCount >= 2` istiyor —
yani uc gundur girmeyenin serisi 0'dir ve o kullanici HIC geri cagri
almiyordu. En cok cagrilmasi gereken kisi, sistemin yapisal olarak en
sessiz kaldigi kisiydi.

Ikinci olculen bosluk: "eklenen kisiler/aile" yolu VARDI ama pratikte
OLUYDU. `midday_push`un (b) dali hem YEDEK daldi (kullanicinin kendi
haritasinda bugun kesinlesen bir aci varsa hic kosmuyor) hem de
`pair_transits_cached` ASLA hesaplamiyor — yani kullanici o gun iliski
ekranini KENDI acmadiysa onbellek bostu. Kisir dongu: bildirimle geri
getirmek istedigin kullanici, bildirimin on sartini yerine getirmemis
olandir.

Civilenen degismezler:

1. Esikler: 3 / 10 / 30 tam gun. Altinda sessiz.
2. Bir basamak gittikten sonra sonraki esige kadar SUSAR (4-9. gunler
   ayni bildirimi tekrar etmez).
3. Kacirilan basamak kaybolmaz: 3. gun gidemediyse 9. gune kadar hala 3
   calar. Ama 10. gunde 3 DEGIL 10 calar — metin sessizligin gercek
   uzunluguna uymak zorunda.
4. 30'dan SONRA HIC: 31. ve 100. gun sessiz.
5. Basamak sayaci kullanici DONDUGU AN sifirlanir ve bunu yapan ayri bir
   yazim yoktur (donusu sunucuda goren kosu yok) — sayac gonderildigi
   andaki `lastSeenDaily` degerine civili.
6. Uc basamak UC AYRI TON ve ucu de SORU.
7. LLM cagrilmaz: metinler sablon, ayrinti paylasilan gokyuzunden.
8. Ayrinti elde edilemezse bildirim DUSMEZ, iddia kuculur — ve bu dusus
   kosunun `generation` dokumune girer, tamami duserse uc 503 doner.
   (Bu turun dersi: uretim bir ay boyunca dusmusken kosu "gonderilen=10
   basarisiz=0" diyip 200 donuyordu.)
9. Cevrem slotu geri kazanima YOL VERIR — ayni olcumden beslenirler.
10. Cevrem yukunde `src` "midday" KALIR: istemcinin rota anahtari o.

Calistirma:
  .venv/Scripts/python.exe -m pytest tests/test_notify_geri_kazanim.py -q
"""
from __future__ import annotations

import datetime as dt

import pytest
from fastapi.testclient import TestClient

from core import cache, config
from services import notification_service as ns
from services import notify_runner, push_service

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
YEREL = dt.datetime(2026, 6, 15, 19, tzinfo=dt.timezone.utc)
SAHTE_GOKYUZU = {"moon_phase": {"key": "full_moon", "name": "Dolunay",
                                "illumination": 98}, "retrogrades": []}


@pytest.fixture(autouse=True)
def temiz_onbellek(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    yield
    cache._memory.clear()


def profil(gun_once: int | None = 5, **alanlar):
    """`gun_once` gun once girmis, push'a uygun profil.

    None verilirse `lastSeenDaily` HIC YOKTUR — "hic okumadin" ile
    "uc gundur okumadin" ayni sey degil.
    """
    temel = {
        "uid": "u1",
        "fcmToken": "token-1",
        "onboardingCompleted": True,
        "timezone": "UTC",
        "language": "tr",
        "sunSign": "Aslan",
        "streakCount": 0,
        "quietFrom": 0,
        "quietTo": 0,
    }
    if gun_once is not None:
        temel["lastSeenDaily"] = (BUGUN - dt.timedelta(days=gun_once)
                                  ).isoformat()
    temel.update(alanlar)
    return temel


# ---------------------------------------------------------------------------
# 1-4: basamak esikleri ve 30 sonrasi sessizlik
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("fark,gonderilen,beklenen,gerekce", [
    # Esigin altinda hicbir sey.
    (0, 0, None, "sessizlik-kisa"),
    (2, 0, None, "sessizlik-kisa"),
    # Ilk esik.
    (3, 0, 3, "gonderilecek"),
    # Basamak gittikten sonra sonraki esige kadar SUSAR.
    (4, 3, None, "basamak-gitti"),
    (9, 3, None, "basamak-gitti"),
    # Kacirilan basamak kaybolmaz.
    (9, 0, 3, "gonderilecek"),
    # 10. gunde 3 hic gitmemisse 3 DEGIL 10 calar.
    (10, 0, 10, "gonderilecek"),
    (10, 3, 10, "gonderilecek"),
    (29, 10, None, "basamak-gitti"),
    (30, 10, 30, "gonderilecek"),
    # 30'dan SONRA HIC — "basamaklar-bitti" ayri bir ad: operator
    # "susturuldu" ile "henuz sirasi degil"i ayirt edebilsin.
    (31, 30, None, "basamaklar-bitti"),
    (100, 30, None, "basamaklar-bitti"),
    (365, 30, None, "basamaklar-bitti"),
])
def test_basamak_esikleri(fark, gonderilen, beklenen, gerekce):
    basamak, ger = ns.winback_tier(profil(gun_once=fark), YEREL, gonderilen)
    assert basamak == beklenen
    assert ger == gerekce


def test_son_giris_bilinmiyorsa_gonderilmez():
    """`lastSeenDaily` yoksa sessizligin UZUNLUGU olculemez. "Hic okumadin"
    baska bir iddia ve onu olcecek verimiz yok — olculmeyen soylenmez."""
    basamak, gerekce = ns.winback_tier(profil(gun_once=None), YEREL, 0)
    assert basamak is None and gerekce == "son-giris-bilinmiyor"

    # Bozuk deger de ayni yola duser; tek bozuk profil kosuyu dusurmez.
    basamak, gerekce = ns.winback_tier(
        profil(lastSeenDaily="dun"), YEREL, 0)
    assert basamak is None and gerekce == "son-giris-bilinmiyor"


def test_gelecege_yazilmis_damga_negatif_fark_uretmez():
    """Saat dilimi degistiren ya da saati ileri alinmis cihaz gelecege
    damga yazabilir; negatif fark 0'a kirpilir ve bildirim gitmez."""
    assert ns.son_gorulme_farki(profil(gun_once=-5), YEREL) == 0
    basamak, gerekce = ns.winback_tier(profil(gun_once=-5), YEREL, 0)
    assert basamak is None and gerekce == "sessizlik-kisa"


def test_yerel_gune_gore_olculur():
    """Kiyas UTC gunune degil KULLANICININ yerel gunune karsi yapilir.
    `lastSeenDaily` cihazin yerel gunu; UTC ile kiyaslamak UTC+3'te her
    gece bir gunluk hayali sessizlik uretirdi."""
    p = profil(lastSeenDaily="2026-06-12", timezone="Pacific/Kiritimati")
    # 2026-06-14 23:00 UTC = Kiritimati'de 2026-06-15 13:00 (UTC+14).
    an = dt.datetime(2026, 6, 14, 23, tzinfo=dt.timezone.utc)
    assert ns.local_now(p, an).date() == dt.date(2026, 6, 15)
    assert ns.son_gorulme_farki(p, ns.local_now(p, an)) == 3


# ---------------------------------------------------------------------------
# 5: sayac donuste sifirlanir
# ---------------------------------------------------------------------------

class _SahteAnlik:
    def __init__(self, veri):
        self._veri = veri
        self.exists = veri is not None

    def to_dict(self):
        return dict(self._veri or {})


class _SahteDoc:
    def __init__(self, depo):
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


def test_sayac_ayni_epizotta_korunur(kayit):
    p = profil(gun_once=3)
    kayit.update(ns.winback_sent_fields(3, p))
    assert ns.winback_state("u1", p) == 3


def test_sayac_kullanici_dondugu_an_sifirlanir(kayit):
    """Basamak, gonderildigi andaki `lastSeenDaily` DEGERINE civili.

    Donusu sunucuda goren hicbir kosu yok: kullanici uygulamayi acar,
    istemci `lastSeenDaily`yi yazar, sunucuya haber gitmez. Sifirlamayi
    yapan ayri bir YAZIM OLMADIGI icin capa sart — capasiz tasarimda donen
    kullanici 10. gun bildirimini de yerdi."""
    eski = profil(gun_once=12)
    kayit.update(ns.winback_sent_fields(10, eski))
    assert ns.winback_state("u1", eski) == 10

    # Kullanici dondu (istemci lastSeenDaily'yi bugune yazdi), sonra uc gun
    # daha girmedi: YENI epizot, sayac 0, yani 3. basamak yeniden calar.
    donen = profil(gun_once=3)
    assert ns.winback_state("u1", donen) == 0
    basamak, gerekce = ns.winback_tier(donen, YEREL,
                                       ns.winback_state("u1", donen))
    assert (basamak, gerekce) == (3, "gonderilecek")


def test_capasiz_eski_kayit_sifir_sayilir(kayit):
    """Bu surumden once yazilmis (capasiz) bir basamak hangi epizoda ait
    oldugunu soylemiyor; 10. gun bildirimini 3. gunu hic gormemis birine
    gonderebilirdi."""
    kayit["winbackTier"] = 10
    assert ns.winback_state("u1", profil(gun_once=4)) == 0


# ---------------------------------------------------------------------------
# 6-7: uc ton, hepsi soru, LLM yok
# ---------------------------------------------------------------------------

def test_her_basamak_metinli_ve_her_metin_basamakli():
    """Tablo basamak kumesinin KENDISI: metinsiz basamak ya da basamaksiz
    metin eklenemez. Bekci ikisini BIRDEN sorar."""
    assert tuple(sorted(ns.WINBACK_TEXTS)) == tuple(sorted(ns.WINBACK_TIERS))
    for basamak, diller in ns.WINBACK_TEXTS.items():
        for dil in ("tr", "en"):
            sablon = diller[dil]
            assert sablon["baslik"].strip(), (basamak, dil)
            assert 0 < len(sablon["yalin"]) <= ns.MAX_PUSH_BODY, (basamak, dil)


def test_uc_basamak_uc_AYRI_ton(monkeypatch):
    """Tek bir "ozledik" bildirimi degil: ucu de farkli baslik, farkli
    govde. Ayni metin uc kez tekrarlansa ikincisinde inandiriciligini
    yitirirdi."""
    monkeypatch.setattr(ns, "_cift_adaylari", lambda uid, lang: [])
    basliklar, govdeler = set(), set()
    for basamak in ns.WINBACK_TIERS:
        icerik, _veri, _olctu = ns.winback_push(
            profil(), "tr", basamak, sky=SAHTE_GOKYUZU, today=BUGUN)
        basliklar.add(icerik.baslik)
        govdeler.add(icerik.govde)
    assert len(basliklar) == len(ns.WINBACK_TIERS)
    assert len(govdeler) == len(ns.WINBACK_TIERS)


@pytest.mark.parametrize("basamak", ns.WINBACK_TIERS)
@pytest.mark.parametrize("dil", ["tr", "en"])
def test_her_basamak_soru_bicimli_ve_dilinde(monkeypatch, basamak, dil):
    """SORU olmak zorunda: dokunus sohbeti o soruyla acar ve cevap
    hafizaya duser (`PushIcerik.soru`). Govde profil dilinin DISINDA
    gorunemez — kosudaki ortak dil agi push'u dusururdu."""
    from core import i18n
    from services import prompts

    monkeypatch.setattr(ns, "_cift_adaylari", lambda uid, lang: [])
    sky = prompts.localize_sky(dil, SAHTE_GOKYUZU)
    icerik, veri, _olctu = ns.winback_push(
        profil(), dil, basamak, sky=sky, today=BUGUN)

    assert icerik.soru is True
    assert icerik.govde.rstrip().endswith("?")
    assert 0 < len(icerik.govde) <= ns.MAX_PUSH_BODY
    assert not i18n.language_conflicts(icerik.govde, dil), icerik.govde
    assert not i18n.language_conflicts(icerik.baslik, dil), icerik.baslik
    # Yuk: `type` istemcinin ROTA anahtari, `src` gercek koken.
    assert veri["type"] == "checkin" and veri["route"] == "chat"
    assert veri["src"] == "winback" and veri["tier"] == str(basamak)
    assert veri["q"] == icerik.govde
    assert all(isinstance(v, str) for v in veri.values())


def test_geri_kazanim_llm_cagirmaz(monkeypatch):
    """Birim ekonomi: bu slot kullanici basina LLM yakmaz. Ayrinti
    PAYLASILAN gokyuzunden geliyor, metinler sablon."""
    from services import gemini_service, signal_service

    def patla(*a, **k):
        raise AssertionError("geri kazanim LLM CAGIRMAMALI")

    monkeypatch.setattr(gemini_service, "generate", patla)
    monkeypatch.setattr(signal_service, "insight_bundle", patla)
    monkeypatch.setattr(ns, "_cift_adaylari", lambda uid, lang: [])
    for basamak in ns.WINBACK_TIERS:
        ns.winback_push(profil(), "tr", basamak, sky=SAHTE_GOKYUZU,
                        today=BUGUN)


def test_merak_basamagi_o_gune_ozgu_ayrinti_tasir(monkeypatch):
    """3. basamagin tonu MERAK ve iddiasi olculmus: gokyuzunden o gune
    ozgu bir ayrinti. Ayrintisiz gonderilse "hist bi baksana" bos bir
    durtme olurdu."""
    monkeypatch.setattr(ns, "_cift_adaylari", lambda uid, lang: [])
    icerik, _veri, olctu = ns.winback_push(
        profil(), "tr", 3, sky=SAHTE_GOKYUZU, today=BUGUN)
    assert "Dolunay" in icerik.govde
    assert olctu is True

    # Ay evresi yoksa retro ayrintiya duser (ikinci bagimsiz kaynak).
    icerik, _veri, olctu = ns.winback_push(
        profil(), "tr", 3, today=BUGUN,
        sky={"moon_phase": {}, "retrogrades": ["Merkür"]})
    assert "Merkür" in icerik.govde and olctu is True


def test_kisisel_basamak_cevredeki_biriyle_ilgili(monkeypatch):
    """10. basamagin tonu KISISEL ve Cevrem slotuyla AYNI olcumden
    besleniyor — tek hesap, iki yuzey."""
    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [("cp", {"pid": "p1"})])
    monkeypatch.setattr(
        ns, "_en_iyi_vurus",
        lambda uid, adaylar, today, hesapla: (
            (type("C", (), {"label": "eşin"})(), {"pid": "p1"},
             {"transit": "Saturn", "natal": "Venus", "aspect": "Trine",
              "orb": 0.8}),
            True))
    icerik, _veri, olctu = ns.winback_push(
        profil(), "tr", 10, sky=SAHTE_GOKYUZU, today=BUGUN)
    assert "eşin" in icerik.govde and "Satürn" in icerik.govde
    assert olctu is True


# ---------------------------------------------------------------------------
# 8: ayrinti elde edilemezse bildirim DUSMEZ, iddia kuculur
# ---------------------------------------------------------------------------

def test_gokyuzu_dusunce_iddia_kuculur_bildirim_dusmez(monkeypatch):
    """`get_sky_now` dustuginde kosu `ham_sky = {}` ile devam ediyor ve bu
    bugune dek TAMAMEN sessizdi. Artik: veri-siz soru gider ve dusus
    `olctu=False` ile dokume girer."""
    monkeypatch.setattr(ns, "_cift_adaylari", lambda uid, lang: [])
    icerik, _veri, olctu = ns.winback_push(profil(), "tr", 3, sky={},
                                           today=BUGUN)
    assert olctu is False
    assert icerik.govde == ns.WINBACK_TEXTS[3]["tr"]["yalin"]
    assert icerik.soru is True


def test_cevresi_olmayan_kullanici_dusus_SAYILMAZ(monkeypatch):
    """Hic eklenen kisisi/arkadasi olmayan kullanici bir KUSUR degil:
    olculecek bir sey yoktu. `olctu is None` demek "olculemedi", "dustu"
    degil — ayrim olmasaydi cevresiz kullanicilar sahte alarm uretirdi."""
    monkeypatch.setattr(ns, "_cift_adaylari", lambda uid, lang: [])
    icerik, _veri, olctu = ns.winback_push(
        profil(), "tr", 10, sky=SAHTE_GOKYUZU, today=BUGUN)
    assert olctu is None
    assert icerik.govde == ns.WINBACK_TEXTS[10]["tr"]["yalin"]


def test_sakin_gun_dusus_SAYILMAZ(monkeypatch):
    """Olcum yapildi ama vurus cikmadi: sakin bir gun kusur degildir."""
    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [("cp", {"pid": "p1"})])
    monkeypatch.setattr(ns, "_en_iyi_vurus",
                        lambda uid, adaylar, today, hesapla: (None, True))
    _icerik, _veri, olctu = ns.winback_push(
        profil(), "tr", 10, sky=SAHTE_GOKYUZU, today=BUGUN)
    assert olctu is True


def _adli_vurus(monkeypatch, ad):
    """10. basamagin olcumunu `ad` adli bir karsi tarafla kurar."""
    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [("cp", {"fromUid": "f1"})])
    monkeypatch.setattr(
        ns, "_en_iyi_vurus",
        lambda uid, adaylar, today, hesapla: (
            (type("C", (), {"label": ad})(), {"fromUid": "f1"},
             {"transit": "Saturn"}),
            True))


def test_karsi_tarafin_ADI_dil_dususu_SAYILMAZ(monkeypatch):
    """OZEL AD DIL TASIMAZ: adi yuzunden olculmus govde FEDA EDILMEZ.

    Onceki hali yalin soruya dusuyordu ve gerekcesi "kosudaki ortak dil
    agi butun push'u dusururdu" diye yaziliydi. O gerekce ARTIK YANLIS:
    ag adi olcumden cikariyor (`ozel_ad_haric`). Yarim onarimin bedeli
    olculdu — `olctu=False` yazmak SAHTE bir uretim dususu uretiyordu ve
    `_SLOT_KIRMIZI_ESIGI["winback"] = 1` ile birleserek, kuyrukta yalniz
    Turkce adli arkadasi olan tek bir Ingilizce kullanici varsa ucu
    **503**e dusuruyordu: hicbir sey bozuk olmadigi halde Scheduler
    kirmizi.

    Uc bagimsiz isaret soruluyor, ciddiyeti ayri: govde olculmus satir
    olmali, dokum `ok` saymali, ve ad koseden kosuya TASINMALI (yoksa
    ortak ag ayni push'u bir sonraki kapida dusururdu).
    """
    from services import prompts

    _adli_vurus(monkeypatch, "Şeyma Gülşah")
    icerik, _veri, olctu = ns.winback_push(
        profil(language="en"), "en", 10,
        sky=prompts.localize_sky("en", SAHTE_GOKYUZU), today=BUGUN)

    assert icerik.govde != ns.WINBACK_TEXTS[10]["en"]["yalin"], (
        "adi yuzunden olculmus govde feda edildi")
    assert "Şeyma Gülşah" in icerik.govde
    assert olctu is True, "ad kaynakli dusus URETIM dususu sayildi"
    assert icerik.ozel_ad == "Şeyma Gülşah", (
        "ad kosuya tasinmadi — ortak dil agi ayni push'u dusurur")


def test_GERCEK_dil_kacagi_hala_yalin_soruya_duser(monkeypatch):
    """Ad muafiyeti agi KAPATMADI: dil isareti CUMLEDEN geliyorsa yedek.

    Kacak ad ASCII tutularak kuruluyor (`"John"`), yani Turkce isaret
    yalnizca sablonun kendisinden gelebilir — muafiyet onu maskelemez.
    """
    from services import prompts

    _adli_vurus(monkeypatch, "John")
    # Sablonu TURKCE olanla degistirip profili `en` birakiyoruz: govde
    # gercekten baska dilde uretilmis olur (olculen kacak sinifi).
    monkeypatch.setitem(ns.WINBACK_TEXTS[10], "en",
                        dict(ns.WINBACK_TEXTS[10]["tr"],
                             yalin=ns.WINBACK_TEXTS[10]["en"]["yalin"]))
    icerik, _veri, olctu = ns.winback_push(
        profil(language="en"), "en", 10,
        sky=prompts.localize_sky("en", SAHTE_GOKYUZU), today=BUGUN)

    assert icerik.govde == ns.WINBACK_TEXTS[10]["en"]["yalin"]
    assert olctu is False
    assert icerik.ozel_ad == "", "yedege dusen govdenin adi tasinmamali"


# ---------------------------------------------------------------------------
# 9-10: Cevrem slotu
# ---------------------------------------------------------------------------

def _vurus():
    return {"side": "user", "transit": "Saturn", "natal": "Venus",
            "aspect": "Trine", "orb": 0.8, "movement": "applying"}


def _cp(label="Erkan", key="u1-f1"):
    from services import synastry_service
    return synastry_service.Counterpart(key=key, birth={}, label=label,
                                        sun_sign="leo")


def test_cevrem_onbellekteki_cifti_BEDAVA_kullanir(monkeypatch):
    """Kullanici o gun iliski ekranini kendi actiysa olcum zaten var:
    hesap YAPILMAZ. Eski davranis yalniz bu asamaydi."""
    from services import synastry_service

    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [(_cp(), {"fromUid": "f1"})])
    monkeypatch.setattr(synastry_service, "pair_transits_cached",
                        lambda uid, other, today=None: {"hits": [_vurus()]})

    def hesap_yasak(*a, **k):
        raise AssertionError("onbellek varken HESAPLANMAMALI")

    monkeypatch.setattr(synastry_service, "pair_transits", hesap_yasak)

    yuk, gerekce, olctu, _ad = ns.circle_push(profil(), "tr", today=BUGUN)
    assert gerekce == "gonderilecek" and olctu is True
    baslik, govde, veri = yuk
    assert "Erkan" in baslik and govde
    # `src` "midday" KALIR: istemcinin rota anahtari o. "circle" yazsaydik
    # bugun kurulu her istemci `default` dalina dusup yalniz Cevrem
    # sekmesini acardi (BY-turunda kapatilan kusur).
    assert veri["type"] == "friend" and veri["src"] == "midday"
    assert veri["fromUid"] == "f1"
    assert all(isinstance(v, str) for v in veri.values())


def test_cevrem_onbellek_bosken_GUNDE_BIR_hesaplar(monkeypatch):
    """Olculen olu dal buydu: onbellek bosken eski kod sessizce atliyordu.
    Artik tek bir aday hesaplanir — hepsi degil (maliyet O(kullanici))."""
    from services import synastry_service

    adaylar = [(_cp("A", "k-a"), {"pid": "a"}),
               (_cp("B", "k-b"), {"pid": "b"}),
               (_cp("C", "k-c"), {"pid": "c"})]
    monkeypatch.setattr(ns, "_cift_adaylari", lambda uid, lang: adaylar)
    monkeypatch.setattr(synastry_service, "pair_transits_cached",
                        lambda uid, other, today=None: None)
    hesaplanan: list = []

    def sahte_hesap(uid, other, today=None):
        hesaplanan.append(other.label)
        return {"hits": [_vurus()]}

    monkeypatch.setattr(synastry_service, "pair_transits", sahte_hesap)

    yuk, gerekce, olctu, _ad = ns.circle_push(profil(), "tr", today=BUGUN)
    assert gerekce == "gonderilecek" and olctu is True and yuk is not None
    assert len(hesaplanan) == 1, f"gunde birden fazla hesap: {hesaplanan}"


def test_cevrem_aday_sirasi_GUNE_gore_doner(monkeypatch):
    """Sabit indeks secilseydi ayni kisi haftalarca tekrarlanirdi. Sira
    gun ordinalinden turetiliyor, yani her gun baskasi yuzeye cikar."""
    from services import synastry_service

    adaylar = [(_cp("A", "k-a"), {"pid": "a"}),
               (_cp("B", "k-b"), {"pid": "b"}),
               (_cp("C", "k-c"), {"pid": "c"})]
    monkeypatch.setattr(synastry_service, "pair_transits_cached",
                        lambda uid, other, today=None: None)
    monkeypatch.setattr(synastry_service, "pair_transits",
                        lambda uid, other, today=None: {"hits": [_vurus()]})

    secilenler = []
    for i in range(len(adaylar)):
        secim, _ = ns._en_iyi_vurus("u1", adaylar,
                                    BUGUN + dt.timedelta(days=i),
                                    hesapla=True)
        secilenler.append(secim[0].label)
    assert sorted(secilenler) == ["A", "B", "C"], secilenler


def test_cevrem_adayi_olmayan_kullanici_dusus_SAYILMAZ(monkeypatch):
    monkeypatch.setattr(ns, "_cift_adaylari", lambda uid, lang: [])
    yuk, gerekce, olctu, _ad = ns.circle_push(profil(), "tr", today=BUGUN)
    assert yuk is None and gerekce == "cevre-yok" and olctu is None


def test_cevrem_olcum_elde_edilemezse_dusus_SAYILIR(monkeypatch):
    """`pair_transits` None donuyor (profil okunamadi / dogum verisi yok):
    bu bir kusur ve dokume `fallback` olarak girer."""
    from services import synastry_service

    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [(_cp(), {"fromUid": "f1"})])
    monkeypatch.setattr(synastry_service, "pair_transits_cached",
                        lambda uid, other, today=None: None)
    monkeypatch.setattr(synastry_service, "pair_transits",
                        lambda uid, other, today=None: None)

    yuk, gerekce, olctu, _ad = ns.circle_push(profil(), "tr", today=BUGUN)
    assert yuk is None and gerekce == "olay-yok" and olctu is False


def test_cevrem_geri_kazanim_penceresinde_SUSAR(kayit):
    """Cevrem slotu geri kazanima YOL VERIR. Iki sebep: 10. basamak ayni
    olcumden besleniyor (iki push, bir hesap), ve uc gundur girmeyen birine
    icerigin ucuncu cesidi degil geri cagri gerekiyor.

    Aksam ailesi bunu SAGLAMAZ: circle yerel 18'de, winback 19'da kosuyor
    — aile kurali "once kosan kazanir" demektir ve circle her zaman once
    kosar. Bu yuzden kapi saatten BAGIMSIZ."""
    saat = ns.TARGET_HOURS["circle"]
    an = dt.datetime(2026, 6, 15, saat, tzinfo=dt.timezone.utc)

    gonder, gerekce = ns.should_send(profil(gun_once=3), "circle", an)
    assert not gonder and gerekce == "geri-kazanim-penceresi"

    # Esigin ALTINDA Cevrem normal calisir.
    gonder, gerekce = ns.should_send(profil(gun_once=2), "circle", an)
    assert gonder, gerekce

    # Basamak gitmis olsa bile pencere KAPALI kalir: fark esigin
    # ustundeyse kullanici hala "donmemis" sayilir ve sessizlik boyunca
    # Cevrem her gun calsaydi kademeli susma karari hic yasanmazdi.
    p = profil(gun_once=20)
    kayit.update(ns.winback_sent_fields(10, p))
    gonder, gerekce = ns.should_send(p, "circle", an)
    assert not gonder and gerekce == "geri-kazanim-penceresi"


# ---------------------------------------------------------------------------
# Uctan uca: yeni slot da SESSIZ DUSMEZ (bu turun dersi)
# ---------------------------------------------------------------------------

def _kosu_profili(sira: int) -> dict:
    """Kosu icin, GERCEK bugune gore bes gundur girmemis profil."""
    bugun = dt.datetime.now(dt.timezone.utc).date()
    return {
        "uid": f"u{sira}",
        "fcmToken": f"token-{sira}",
        "onboardingCompleted": True,
        "timezone": "UTC",
        "language": "tr",
        "sunSign": "Aslan",
        "streakCount": 0,
        "quietFrom": 0,
        "quietTo": 0,
        "lastSeenDaily": (bugun - dt.timedelta(days=5)).isoformat(),
    }


@pytest.fixture()
def winback_kosusu(monkeypatch):
    """Esigi gecen sayida profille bir `winback` kosusu."""
    from services import chat_history

    kayitlar: dict = {"kosu": []}
    monkeypatch.setattr(config, "NOTIFY_SCHEDULER_SECRET", "dogru")
    monkeypatch.setattr(notify_runner, "_iter_profiles", lambda: iter(
        [_kosu_profili(i)
         for i in range(1, notify_runner._KIRMIZI_ESIGI + 1)]))
    monkeypatch.setattr(ns, "already_sent", lambda uid, tur, gun: False)
    monkeypatch.setattr(ns, "gunluk_push_sayisi", lambda uid, gun: 0)
    monkeypatch.setattr(ns, "winback_state", lambda uid, profil: 0)
    monkeypatch.setattr(ns, "mark_sent",
                        lambda uid, tur, gun, extra=None: None)
    monkeypatch.setattr(ns, "_cift_adaylari", lambda uid, lang: [])
    monkeypatch.setattr(chat_history, "seed_assistant_message",
                        lambda uid, text, lang, gun: "cid-1")
    monkeypatch.setattr(notify_runner, "_kosu_kaydet",
                        lambda tur, gun, sonuc, an: kayitlar["kosu"].append(
                            sonuc))
    monkeypatch.setattr(push_service, "send",
                        lambda m: push_service.SendResult(
                            sent=len(m), failed=0, pruned=[], failed_uids=[]))
    return kayitlar


def _cagir(ek: str = "") -> object:
    with TestClient(app) as client:
        return client.post(
            f"/api/v1/notify/run?type=winback&force=true{ek}",
            headers={"Authorization": "dogru"})


@uygulama_gerekir
def test_kosu_gokyuzu_sagliklyken_yesil(winback_kosusu, monkeypatch):
    monkeypatch.setattr(notify_runner, "get_sky_now", lambda: SAHTE_GOKYUZU)
    yanit = _cagir()

    assert yanit.status_code == 200
    govde = yanit.json()
    assert govde["status"] == "ok"
    assert govde["sent"] == notify_runner._KIRMIZI_ESIGI
    assert govde["generation"]["ok"] == notify_runner._KIRMIZI_ESIGI


@uygulama_gerekir
def test_kosu_gokyuzu_dusunce_200_DONMEZ(winback_kosusu, monkeypatch):
    """BU TURUN DERSI: bildirim kosusu bir ay boyunca uretim tamamen
    dusmusken de "gonderilen=10 basarisiz=0" diyip 200 donuyordu. Yeni
    slot ayni sessizlige dusmemeli — gokyuzu servisi yandiginda push'lar
    yine gidiyor (veri-siz soru) ama DURUM KODU kirmizi olmak zorunda;
    Cloud Scheduler gunlugu yalniz onu gosteriyor."""
    def patla():
        raise RuntimeError("gokyuzu alinamadi")

    monkeypatch.setattr(notify_runner, "get_sky_now", patla)
    yanit = _cagir()

    assert yanit.status_code == 503
    govde = yanit.json()["detail"]
    assert govde["status"] == "uretim-tamamen-dustu"
    assert govde["generation"] == {
        "attempted": notify_runner._KIRMIZI_ESIGI,
        "fallback": notify_runner._KIRMIZI_ESIGI}
    # Push'larin gitmis olmasi kusuru maskelemiyor — kapi tam da bu.
    assert govde["sent"] == notify_runner._KIRMIZI_ESIGI
    assert winback_kosusu["kosu"][0].status == "uretim-tamamen-dustu"


@uygulama_gerekir
def test_kosu_basamagi_ve_capayi_KAYDA_yazar(winback_kosusu, monkeypatch):
    """Kosu, basamagi ve sessizlik epizodunun capasini `mark_sent(extra=)`
    ile yazmak ZORUNDA.

    Bu kablo kopsa birim testlerin hepsi yesil kalirdi ama canlida en kotu
    kusur olurdu: basamak hic kaydedilmediginden sayac her gun 0 okunur ve
    3 gundur girmeyen kullanici 3. basamak bildirimini HER GUN alir —
    yani geri kazanim dogrudan bir bombardimana donerdi.

    Ikinci bagimsiz isaret: yazilan tur adi `winback` (gonderim kaydindaki
    anahtar). Yanlis tur adiyla yazilsa tekrar korumasi da calismazdi.
    """
    yazilan: list = []
    monkeypatch.setattr(notify_runner, "get_sky_now", lambda: SAHTE_GOKYUZU)
    monkeypatch.setattr(
        ns, "mark_sent",
        lambda uid, tur, gun, extra=None: yazilan.append((uid, tur, extra)))

    assert _cagir().status_code == 200

    assert len(yazilan) == notify_runner._KIRMIZI_ESIGI
    bugun = dt.datetime.now(dt.timezone.utc).date()
    bes_gun_once = (bugun - dt.timedelta(days=5)).isoformat()
    for _uid, tur, extra in yazilan:
        assert tur == "winback"
        assert extra["winbackTier"] == ns.WINBACK_TIERS[0]
        assert extra["winbackAnchor"] == bes_gun_once


@pytest.fixture()
def cevrem_kosusu(monkeypatch):
    """Esigi gecen sayida profille bir `circle` kosusu.

    Profiller DUN girmis: geri kazanim penceresi kapali, yani Cevrem slotu
    kendi kapisindan geciyor.
    """
    kayitlar: dict = {"kosu": []}
    bugun = dt.datetime.now(dt.timezone.utc).date()
    profiller = []
    for i in range(1, notify_runner._KIRMIZI_ESIGI + 1):
        p = _kosu_profili(i)
        p["lastSeenDaily"] = (bugun - dt.timedelta(days=1)).isoformat()
        profiller.append(p)

    monkeypatch.setattr(config, "NOTIFY_SCHEDULER_SECRET", "dogru")
    monkeypatch.setattr(notify_runner, "get_sky_now", lambda: SAHTE_GOKYUZU)
    monkeypatch.setattr(notify_runner, "_iter_profiles",
                        lambda: iter(profiller))
    monkeypatch.setattr(ns, "already_sent", lambda uid, tur, gun: False)
    monkeypatch.setattr(ns, "gunluk_push_sayisi", lambda uid, gun: 0)
    monkeypatch.setattr(ns, "mark_sent",
                        lambda uid, tur, gun, extra=None: None)
    monkeypatch.setattr(ns, "_cift_adaylari",
                        lambda uid, lang: [(_cp(), {"fromUid": "f1"})])
    monkeypatch.setattr(notify_runner, "_kosu_kaydet",
                        lambda tur, gun, sonuc, an: kayitlar["kosu"].append(
                            sonuc))
    monkeypatch.setattr(push_service, "send",
                        lambda m: push_service.SendResult(
                            sent=len(m), failed=0, pruned=[], failed_uids=[]))
    return kayitlar


def _cevrem_cagir() -> object:
    with TestClient(app) as client:
        return client.post("/api/v1/notify/run?type=circle&force=true",
                           headers={"Authorization": "dogru"})


@uygulama_gerekir
def test_cevrem_kosusu_olcum_varken_yesil(cevrem_kosusu, monkeypatch):
    from services import synastry_service

    monkeypatch.setattr(synastry_service, "pair_transits_cached",
                        lambda uid, other, today=None: {"hits": [_vurus()]})
    yanit = _cevrem_cagir()

    assert yanit.status_code == 200
    govde = yanit.json()
    assert govde["status"] == "ok"
    assert govde["sent"] == notify_runner._KIRMIZI_ESIGI
    assert govde["generation"]["ok"] == notify_runner._KIRMIZI_ESIGI


@uygulama_gerekir
def test_cevrem_kosusu_olcum_hic_elde_edilemezse_200_DONMEZ(cevrem_kosusu,
                                                            monkeypatch):
    """BU TURUN DERSI yeni slot icin de gecerli: cift olcumu herkes icin
    elde edilemiyorsa (profil okumalari ya da efemeris yolu dusmus) kosu
    sessizce "olay-yok" deyip 200 DONMEMELI.

    Dikkat: SAKIN BIR GUN (olcum yapildi, vurus cikmadi) bu kapidan
    gecmez — o `ok` sayilir. Ayrim `_en_iyi_vurus`un uc degerli donusunde;
    olmasaydi vurussuz bir gun her saat sahte alarm uretirdi ve bekci
    okunmaz hale gelirdi (kusurun kokunun ta kendisi)."""
    from services import synastry_service

    monkeypatch.setattr(synastry_service, "pair_transits_cached",
                        lambda uid, other, today=None: None)
    monkeypatch.setattr(synastry_service, "pair_transits",
                        lambda uid, other, today=None: None)
    yanit = _cevrem_cagir()

    assert yanit.status_code == 503
    govde = yanit.json()["detail"]
    assert govde["status"] == "uretim-tamamen-dustu"
    assert govde["generation"] == {
        "attempted": notify_runner._KIRMIZI_ESIGI,
        "fallback": notify_runner._KIRMIZI_ESIGI}
    assert cevrem_kosusu["kosu"][0].status == "uretim-tamamen-dustu"


@uygulama_gerekir
def test_cevrem_kosusu_sakin_gun_YESIL(cevrem_kosusu, monkeypatch):
    """Olcum yapildi, vurus yok: kosu yesil kalir ve atlama GORUNUR bir
    gerekceyle sayilir. Sahte alarm uretmemenin bekcisi."""
    from services import synastry_service

    monkeypatch.setattr(synastry_service, "pair_transits_cached",
                        lambda uid, other, today=None: {"hits": []})
    yanit = _cevrem_cagir()

    assert yanit.status_code == 200
    govde = yanit.json()
    assert govde["status"] == "ok" and govde["sent"] == 0
    assert govde["generation"]["ok"] == notify_runner._KIRMIZI_ESIGI
    assert govde["skipped"]["olay-yok"] == notify_runner._KIRMIZI_ESIGI


@uygulama_gerekir
def test_kosu_soruyu_sohbete_tohumlar(winback_kosusu, monkeypatch):
    """Ucu de SORU: dokunus sohbeti o soruyla acar. Tohum `PushIcerik.soru`
    bayragindan geliyor — kosu hicbir yerde `if type == "winback"`
    yazmiyor."""
    gonderilen: list = []
    monkeypatch.setattr(notify_runner, "get_sky_now", lambda: SAHTE_GOKYUZU)

    def sahte_send(m):
        gonderilen.extend(m)
        return push_service.SendResult(sent=len(m), failed=0, pruned=[],
                                       failed_uids=[])

    monkeypatch.setattr(push_service, "send", sahte_send)
    assert _cagir().status_code == 200

    assert gonderilen
    for m in gonderilen:
        assert m.data["route"] == "chat_answer"
        assert m.data["cid"] == "cid-1"
        assert m.data["src"] == "winback"

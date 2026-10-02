"""Ortaklık ödülü (OP-turu) — zarar ve dolandırıcılık kapıları.

Her iddia gerçek para ödemesi üretebilecek bir yolu kapatıyor. Ödül
kuralının beş koşulu (PRODUCTION · doğru olay türü · parasal · deneme
değil · atıf var) tek tek sınanıyor, çünkü biri gevşerse kayıp sessizdir:
panel "hakediş" gösterir, sahip öder, yanlış olduğu ancak mutabakatta
anlaşılır.

Ortak ERİŞİMİ bloğu para değil YETKİ koruyor ve buraya ait: ortağın
kendi bakiyesini gördüğü panonun kapısı da bu dosyadaki `partnerId`
bağına dayanıyor — tek hesap iki ortağa bağlanırsa ortak YANLIŞ ortağın
parasını görür.

Son blok (TIKLAMA) ne para ne yetki, ÖLÇÜMÜN DÜRÜSTLÜĞÜNÜ koruyor:
huninin tepesi, kimliksiz bir uçtan gelen bir sayaç. İki şeyi birden
sınıyor — kimliksiz uca konan kapılar (kod gerçekten var mı, yazım
best-effort mi, kişisel veri yazılmıyor mu) ve sayının doğru ADLA
sunulması (`referredUsers` = KURAN, tıklama ayrı).

Çalıştırma:
    .venv\\Scripts\\python.exe -m pytest tests/test_partner_rewards.py -q
"""
from __future__ import annotations

import datetime as dt

import pytest
from google.cloud.firestore_v1.transforms import Increment

from api.billing import _ortaklik_hakedisi
from services import partner_service as ps


# --- Sorgu destekli sahte Firestore (test_partner_codes.py sahtesinin
# --- genişletilmiş hâli: where/limit/stream + snapshot.reference) --------

class SahteAnlik:
    def __init__(self, depo, yol, data):
        self._depo = depo
        self._yol = yol
        self._data = data

    @property
    def exists(self):
        return self._data is not None

    @property
    def id(self):
        return self._yol.rsplit("/", 1)[-1]

    @property
    def reference(self):
        return SahteDoc(self._depo, self._yol)

    def to_dict(self):
        return dict(self._data) if self._data else {}


def _artimi_coz(mevcut: dict, veri: dict) -> dict:
    """`Increment` dönüşümünü sahte depoda uygular.

    Sahte istemci bunu ANLAMAK zorunda: `Increment` çözülmezse depoya bir
    NESNE yazılır, `int(...)` fırlar ve test "sayaç artmadı" değil
    "sahtelik eksik" diye düşer — iki arıza birbirine benzemez.
    """
    cozulmus = {}
    for anahtar, deger in veri.items():
        if isinstance(deger, Increment):
            cozulmus[anahtar] = int(mevcut.get(anahtar) or 0) + deger.value
        else:
            cozulmus[anahtar] = deger
    return cozulmus


class SahteDoc:
    def __init__(self, depo, yol):
        self._depo = depo
        self._yol = yol

    @property
    def id(self):
        return self._yol.rsplit("/", 1)[-1]

    def _yazimi_say(self):
        # YAZIM SAYACI (isteğe bağlı, `_okumalar` emsali): "var olmayan kod
        # HİÇBİR ŞEY yazdırmaz" iddiası ancak yazımın YOKLUĞU ölçülerek
        # kurulabilir. Depoya bakıp "doküman yok" demek yetmez — yazım
        # olup da boş veri yazılmış olabilir.
        sayaclar = self._depo.get("_yazimlar")
        if sayaclar is not None:
            sayaclar[self._yol] = sayaclar.get(self._yol, 0) + 1

    def get(self, transaction=None):
        # OKUMA SAYACI (isteğe bağlı): testler "aynı dokümanı döngü içinde
        # N kez çekmiyoruz" iddiasını ancak okumayı görerek kurabilir.
        # `_okumalar` anahtarı depoda yoksa hiçbir maliyeti yok.
        sayaclar = self._depo.get("_okumalar")
        if sayaclar is not None:
            sayaclar[self._yol] = sayaclar.get(self._yol, 0) + 1
        return SahteAnlik(self._depo, self._yol, self._depo.get(self._yol))

    def set(self, data, merge=False):
        mevcut = dict(self._depo.get(self._yol) or {}) if merge else {}
        mevcut.update(_artimi_coz(mevcut, data))
        self._depo[self._yol] = mevcut
        self._yazimi_say()

    def update(self, data):
        mevcut = dict(self._depo.get(self._yol) or {})
        mevcut.update(_artimi_coz(mevcut, data))
        self._depo[self._yol] = mevcut
        self._yazimi_say()

    def create(self, data):
        if self._yol in self._depo:
            raise RuntimeError("already-exists")
        self._depo[self._yol] = dict(data)
        self._yazimi_say()

    def collection(self, ad):
        return SahteKoleksiyon(self._depo, f"{self._yol}/{ad}")

    @property
    def var_mi(self):
        return self._yol in self._depo


def _karsilastir(deger, op, hedef):
    if deger is None:
        return False
    if op == "==":
        return deger == hedef
    if op == "<=":
        return deger <= hedef
    if op == ">=":
        return deger >= hedef
    raise AssertionError(f"desteklenmeyen operator: {op}")


class SahteKoleksiyon:
    def __init__(self, depo, yol, suzgecler=None, tavan=None):
        self._depo = depo
        self._yol = yol
        self._suzgecler = list(suzgecler or [])
        self._tavan = tavan

    def document(self, ad=None):
        if ad is None:
            # Otomatik kimlik BENZERSİZ olmalı: aynı koleksiyona iki ödeme
            # yazılınca sabit bir ad ikincisini birincinin üstüne yazar ve
            # bakiye testi sahte bir sonuç verir.
            ad = f"oto-{len(self._depo)}"
        return SahteDoc(self._depo, f"{self._yol}/{ad}")

    def where(self, filter=None, **_):
        # google.cloud.firestore_v1 FieldFilter: alan/op/deger
        alan = getattr(filter, "field_path", None) or filter._field_path
        op = getattr(filter, "op_string", None) or filter._op_string
        deger = getattr(filter, "value", None)
        if deger is None:
            deger = filter._value
        return SahteKoleksiyon(self._depo, self._yol,
                               self._suzgecler + [(alan, op, deger)],
                               self._tavan)

    def limit(self, n):
        return SahteKoleksiyon(self._depo, self._yol, self._suzgecler, n)

    def stream(self):
        onek = self._yol + "/"
        sonuc = []
        for yol, veri in list(self._depo.items()):
            if not yol.startswith(onek) or "/" in yol[len(onek):]:
                continue
            if all(_karsilastir(veri.get(a), o, d)
                   for a, o, d in self._suzgecler):
                sonuc.append(SahteAnlik(self._depo, yol, veri))
        return sonuc[:self._tavan] if self._tavan else sonuc


class SahteTransaction:
    def set(self, ref, data):
        ref.set(data)

    def update(self, ref, data):
        ref.update(data)


class SahteToplu:
    """`client.batch()` — gerçek `WriteBatch` gibi ATOMİK.

    Atomiklik taklit değil test edilen bir özellik: tıklama, gün sayacını
    ve kod dokümanındaki koşan toplamı AYNI toplu yazımda artırıyor. İkisi
    ayrı ayrı yazılsaydı biri düşünce ekrandaki "toplam", gün serisinin
    toplamını sessizce tutmazdı. Bu yüzden `update` hedefi yoksa HİÇBİR
    işlem uygulanmaz — gerçek Firestore da tam böyle davranır.
    """

    def __init__(self):
        self._islemler = []

    def set(self, ref, data, merge=False):
        self._islemler.append(("set", ref, data, merge))

    def update(self, ref, data):
        self._islemler.append(("update", ref, data))

    def commit(self):
        for islem in self._islemler:
            if islem[0] == "update" and not islem[1].var_mi:
                raise RuntimeError("not-found")
        for islem in self._islemler:
            if islem[0] == "set":
                islem[1].set(islem[2], merge=islem[3])
            else:
                islem[1].update(islem[2])


class SahteClient:
    def __init__(self, depo):
        self._depo = depo

    def collection(self, ad):
        return SahteKoleksiyon(self._depo, ad)

    def transaction(self):
        return SahteTransaction()

    def batch(self):
        return SahteToplu()

    def get_all(self, referanslar, **_):
        """Gerçek `get_all` SIRASIZ döner; sahte bunu TERSİNE ÇEVİRİP kanıtlar.

        Çağıran anlık görüntüleri doküman kimliğiyle (gün) eşleştirmek
        zorunda. Sahte sırayı korusaydı, sıraya bel bağlayan bir hata
        yeşil test verir ve ancak canlıda görünürdü.
        """
        return [r.get() for r in reversed(list(referanslar))]


@pytest.fixture()
def depo(monkeypatch):
    veriler: dict = {}
    client = SahteClient(veriler)
    monkeypatch.setattr(ps.firestore_client, "get_client", lambda: client)
    monkeypatch.setattr("google.cloud.firestore.transactional", lambda f: f)
    veriler["_client"] = client
    return veriler


def _ortak(depo, pid="p-1", **ek):
    veri = {"name": "Ortak", "active": True,
            "rewardModel": ps.REWARD_MODEL_FIXED, "rewardTry": 30.0}
    veri.update(ek)
    depo[f"partners/{pid}"] = veri


def _olay(**ek):
    e = {"product_id": "rytho_plus_monthly", "event_timestamp_ms": None}
    e.update(ek)
    return e


def _tetikle(depo, uid="u1", *, tur="INITIAL_PURCHASE", ortam="PRODUCTION",
             parasal=True, urun="rytho_plus_monthly", donem=None,
             partner="p-1"):
    _ortaklik_hakedisi(depo["_client"], uid,
                       _olay(product_id=urun, period_type=donem),
                       tur, ortam, partner, parasal, "evt-1")


# --- Ödül DOĞURAN yol ---------------------------------------------------

def test_ilk_abonelik_hakedis_acar(depo):
    _ortak(depo)
    _tetikle(depo)
    kayit = depo["partnerQualifications/u1"]
    assert kayit["status"] == ps.STATUS_PENDING
    assert kayit["partnerId"] == "p-1"
    assert kayit["rewardTry"] == 30.0
    # 15 günlük pencere.
    assert (kayit["maturesAt"] - kayit["purchasedAt"]).days == \
        ps.MATURATION_DAYS


def test_denemeden_donusen_abone_de_hakedis_acar(depo):
    """`INITIAL_PURCHASE`e bakmak YETMEZ: mağaza denemesi açılırsa ödeyen
    aboneye dönüşüm `TRIAL_CONVERTED` ile gelir."""
    _ortak(depo)
    _tetikle(depo, tur="TRIAL_CONVERTED")
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_PENDING


# --- Ödül ÜRETMEYEN yollar (zarar kapıları) -----------------------------

def test_jeton_paketi_hakedis_acmaz(depo):
    _ortak(depo)
    _tetikle(depo, tur="NON_RENEWING_PURCHASE", urun="rytho_tokens_small")
    assert "partnerQualifications/u1" not in depo


def test_sandbox_hakedis_acmaz(depo):
    """Canlıda 1756 SANDBOX olayı var; süzülmezse sahte gelirden para ödenir."""
    _ortak(depo)
    _tetikle(depo, ortam="SANDBOX")
    assert "partnerQualifications/u1" not in depo


def test_deneme_baslangici_hakedis_acmaz(depo):
    """`period_type=TRIAL` olan INITIAL_PURCHASE `monetary=True` gelir —
    yani `monetary` tek başına para geçtiğini KANITLAMAZ."""
    _ortak(depo)
    _tetikle(depo, donem="TRIAL")
    assert "partnerQualifications/u1" not in depo


def test_parasal_olmayan_olay_hakedis_acmaz(depo):
    _ortak(depo)
    _tetikle(depo, parasal=False)
    assert "partnerQualifications/u1" not in depo


def test_atifsiz_kullanici_hakedis_acmaz(depo):
    _ortak(depo)
    _tetikle(depo, partner=None)
    assert "partnerQualifications/u1" not in depo


def test_pasif_ortak_hakedis_acmaz(depo):
    _ortak(depo, active=False)
    _tetikle(depo)
    assert "partnerQualifications/u1" not in depo


def test_gecersiz_odul_tutari_hakedis_acmaz(depo):
    """Bozuk `rewardTry` sessizce 0 ödeme yazmak yerine kaydı hiç açmaz."""
    _ortak(depo, rewardTry=0)
    _tetikle(depo)
    assert "partnerQualifications/u1" not in depo


def test_yenileme_ikinci_kayit_acmaz(depo):
    """Doküman kimliği uid olduğu için kural YAPISAL — sorguya bağlı değil."""
    _ortak(depo)
    _tetikle(depo)
    ilk = dict(depo["partnerQualifications/u1"])
    _tetikle(depo, tur="RENEWAL")
    assert depo["partnerQualifications/u1"] == ilk


def test_ikinci_abonelik_ikinci_odul_vermez(depo):
    _ortak(depo)
    _tetikle(depo)
    ilk = dict(depo["partnerQualifications/u1"])
    # Aylar sonra tekrar abone olsa bile yeni INITIAL_PURCHASE gelir.
    _tetikle(depo, tur="INITIAL_PURCHASE")
    assert depo["partnerQualifications/u1"] == ilk


def test_odul_tutari_dondurulur(depo):
    """Panelden tutar değişince GEÇMİŞ hakediş yeniden fiyatlanmaz."""
    _ortak(depo, rewardTry=30.0)
    _tetikle(depo, uid="u1")
    depo["partners/p-1"]["rewardTry"] = 90.0
    _tetikle(depo, uid="u2")
    assert depo["partnerQualifications/u1"]["rewardTry"] == 30.0
    assert depo["partnerQualifications/u2"]["rewardTry"] == 90.0


# --- İade ve olgunlaşma -------------------------------------------------

def test_iade_bekleyen_hakedisi_iptal_eder(depo):
    _ortak(depo)
    _tetikle(depo)
    _tetikle(depo, tur="REFUND")
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_VOID


def test_iptal_hakedisi_DUSURMEZ(depo):
    """`CANCELLATION` = otomatik yenileme kapatıldı, para iadesi DEĞİL.
    O ayın parası bizde kaldı; ortak o aboneyi gerçekten kazandı."""
    _ortak(depo)
    _tetikle(depo)
    _tetikle(depo, tur="CANCELLATION")
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_PENDING


def test_15_gun_dolmadan_kesinlesmez(depo):
    _ortak(depo)
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["purchasedAt"] + \
        dt.timedelta(days=ps.MATURATION_DAYS - 1)
    sayac = ps.mature_qualifications(now=simdi)
    assert sayac["taranan"] == 0
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_PENDING


def test_15_gun_sonra_kesinlesir(depo):
    _ortak(depo)
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    sayac = ps.mature_qualifications(now=simdi)
    assert sayac["kesinlesen"] == 1
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_QUALIFIED


def test_olgunlastirma_kacirilan_iadeyi_yakalar(depo):
    """Webhook kaçırılmış olabilir: olgunlaşmada gelir defteri yeniden
    taranır ve iade bulunursa hakediş yine iptal olur."""
    _ortak(depo)
    _tetikle(depo)
    alindi = depo["partnerQualifications/u1"]["purchasedAt"]
    depo["revenueEvents/geç-iade"] = {
        "uid": "u1", "eventType": "REFUND",
        "at": alindi + dt.timedelta(days=3)}
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    sayac = ps.mature_qualifications(now=simdi)
    assert sayac["iptal"] == 1
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_VOID


def test_olgunlastirma_idempotent(depo):
    """İkinci koşu aynı kaydı `pending` bulamaz — `Increment` değil,
    durum alanı üzerinden."""
    _ortak(depo)
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)
    ikinci = ps.mature_qualifications(now=simdi)
    assert ikinci["taranan"] == 0


# --- Pasif ortağın BEKLEYEN hakedişi (kullanım şartlarındaki madde) ------

def test_pasif_ortagin_bekleyen_hakedisi_olgunlastirmada_DUSER(depo):
    """`open_qualification` yalnız YENİ hakedişi engelliyor; olgunlaştırma
    sorgusu ise `status` + `maturesAt` süzüyor ve ortağın `active` alanına
    bakmıyordu. Kırılma: kötüye kullanım yüzünden pasifleştirilen ortağın
    5 gün önce açılmış kaydı 10 gün sonra `qualified` olup bakiyeye giriyor
    ve ödeme kapısı, şartların "düştü" dediği parayı ödemeye izin veriyor.
    """
    _ortak(depo)
    _tetikle(depo)
    # Hakediş AÇILDIKTAN SONRA pasifleştirme — kırılmanın gerçek sırası.
    depo["partners/p-1"]["active"] = False
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    sayac = ps.mature_qualifications(now=simdi)

    kayit = depo["partnerQualifications/u1"]
    assert kayit["status"] == ps.STATUS_VOID
    assert kayit["voidReason"] == ps.VOID_REASON_PARTNER_INACTIVE
    assert sayac["iptal_pasif"] == 1
    # İade iptaliyle aynı sayaçta toplanmıyor: mutabakatta "neden düştü"
    # sorusu cevapsız kalmasın.
    assert sayac["iptal"] == 0
    assert sayac["kesinlesen"] == 0
    # Düşen tutar bakiyeye GİRMEZ, yani ödenebilir hâle gelmez.
    assert ps.partner_detail("p-1")["earnedTry"] == 0.0


def test_silinmis_ortagin_bekleyen_hakedisi_de_DUSER(depo):
    """Doküman yoksa "aktif değil" sayılır: ödenecek kimsesi olmayan bir
    borcu kesinleştirmenin anlamı yok."""
    _ortak(depo)
    _tetikle(depo)
    del depo["partners/p-1"]
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    sayac = ps.mature_qualifications(now=simdi)
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_VOID
    assert sayac["iptal_pasif"] == 1


def test_AKTIF_ortagin_bekleyen_hakedisi_hala_kesinlesir(depo):
    """Regresyon: pasif kapısı normal yolu kapatmamalı."""
    _ortak(depo)
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    sayac = ps.mature_qualifications(now=simdi)
    assert depo["partnerQualifications/u1"]["status"] == ps.STATUS_QUALIFIED
    assert sayac["kesinlesen"] == 1
    assert sayac["iptal_pasif"] == 0
    assert "voidReason" not in depo["partnerQualifications/u1"]


def test_olgunlastirma_ortak_dokumanini_kayit_basina_OKUMAZ(depo):
    """Aynı ortağın iki kaydı bir koşuda olgunlaşınca ortak dokümanı
    bir kez okunur. Bellek-içi harita olmadan okuma sayısı kayıt sayısıyla
    büyür — küçük bir ortak listesinde bile bedava değil."""
    depo["_okumalar"] = {}
    _ortak(depo)
    _tetikle(depo, uid="u1")
    _tetikle(depo, uid="u2")
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    depo["_okumalar"].clear()      # yalnız olgunlaştırmanın okumaları
    sayac = ps.mature_qualifications(now=simdi)
    assert sayac["kesinlesen"] == 2
    assert depo["_okumalar"].get("partners/p-1") == 1


# --- Dolandırıcılık kapıları --------------------------------------------

def test_ortak_kendi_kodunu_kullanamaz(depo, monkeypatch):
    _ortak(depo, uid="ortak-uid")
    depo["partnerCodes/ORTAK10"] = {
        "partnerId": "p-1", "bonusTokens": 0, "maxRedemptions": None,
        "redemptionCount": 0, "expiresAt": None, "active": True}
    monkeypatch.setattr(ps.wallet, "credit_promo", lambda *a: True)
    with pytest.raises(ps.RedeemError) as h:
        ps.redeem("ortak-uid", "ORTAK10")
    assert h.value.status == 403
    assert h.value.reason == "self_referral"
    assert "users/ortak-uid/private/attribution" not in depo
    assert depo["partnerCodes/ORTAK10"]["redemptionCount"] == 0


def test_baskasi_ayni_kodu_kullanabilir(depo, monkeypatch):
    _ortak(depo, uid="ortak-uid")
    depo["partnerCodes/ORTAK10"] = {
        "partnerId": "p-1", "bonusTokens": 0, "maxRedemptions": None,
        "redemptionCount": 0, "expiresAt": None, "active": True}
    monkeypatch.setattr(ps.wallet, "credit_promo", lambda *a: True)
    ps.redeem("baska-uid", "ORTAK10")
    assert depo["users/baska-uid/private/attribution"]["partnerId"] == "p-1"


# --- Ödeme kapıları -----------------------------------------------------

def test_odeme_bakiyeyi_asamaz(depo):
    _ortak(depo)
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)            # bakiye 30
    with pytest.raises(ps.RedeemError) as h:
        ps.add_payout("p-1", 31.0, "TRY", "fazla")
    assert h.value.reason == "exceeds_balance"
    ps.add_payout("p-1", 30.0, "TRY", "tam")       # sınırda geçer


def test_negatif_duzeltme_gerekce_ister(depo):
    _ortak(depo)
    with pytest.raises(ps.RedeemError) as h:
        ps.add_payout("p-1", -10.0, "TRY", "")
    assert h.value.reason == "reason_required"
    ps.add_payout("p-1", -10.0, "TRY", "iade duzeltmesi")


def test_sifir_odeme_reddedilir(depo):
    _ortak(depo)
    with pytest.raises(ps.RedeemError) as h:
        ps.add_payout("p-1", 0, "TRY", "bos")
    assert h.value.reason == "invalid_amount"


def test_farkli_para_biriminde_odeme_REDDEDILIR(depo):
    """Ölçülen kırılma: ortak ₺500 biriktirir, yönetici tutarı 400 + birimi
    USD girer. Birime bakmayan kapı 400 < 500 gördüğü için GEÇİYOR; pano
    "Ödenen ₺400, Bakiye ₺100" yazıyor ama ortağa ~₺14.000 gitmiş oluyor.
    """
    _ortak(depo, rewardTry=500.0)
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)            # bakiye ₺500

    with pytest.raises(ps.RedeemError) as h:
        ps.add_payout("p-1", 400.0, "USD", "USD olarak odendi")
    assert h.value.status == 400
    assert h.value.reason == "currency_mismatch"
    # Defter hiç kirlenmedi.
    assert ps.partner_detail("p-1")["paidTry"] == 0.0
    # Ortağın birimindeki aynı tutar geçer — kapı tutarı değil BİRİMİ
    # süzüyor.
    ps.add_payout("p-1", 400.0, "try", "kucuk harf de kabul")


def test_ortagin_kendi_birimi_TRY_DISI_olabilir(depo):
    """Kapı sabit "TRY" değil ortağın `payoutCurrency` alanıdır."""
    _ortak(depo, payoutCurrency="USD")
    with pytest.raises(ps.RedeemError) as h:
        ps.add_payout("p-1", -10.0, "TRY", "duzeltme")
    assert h.value.reason == "currency_mismatch"
    ps.add_payout("p-1", -10.0, "USD", "duzeltme")
    kayitlar = [v for k, v in depo.items()
                if k.startswith("partners/p-1/payouts/")]
    assert [o["currency"] for o in kayitlar] == ["USD"]


def test_odeme_toplami_yalniz_ESLESEN_birimi_sayar(depo):
    """Uyumsuz kayıt sessizce atılmıyor: listede duruyor ve sayısı yanıtta
    görünüyor. Farkı gizlemek, yanlış toplamak kadar kötüdür."""
    _ortak(depo)
    # Kapıdan ÖNCE yazılmış karışık birimli defter (geriye dönük hâl).
    depo["partners/p-1/payouts/a"] = {"amount": 10.0, "currency": "TRY"}
    depo["partners/p-1/payouts/b"] = {"amount": 400.0, "currency": "USD"}
    # `currency` alanı HİÇ olmayan eski kayıt: ortağın birimi kabul edilir.
    depo["partners/p-1/payouts/c"] = {"amount": 5.0}

    detay = ps.partner_detail("p-1")
    assert detay["paidTry"] == 15.0
    assert detay["payoutCurrency"] == "TRY"
    assert detay["payoutCurrencyMismatchCount"] == 1
    # Kayıt kaybolmadı, kendi birimiyle duruyor.
    assert len(detay["payouts"]) == 3
    assert any(o.get("currency") == "USD" for o in detay["payouts"])
    # Ortak da kendi panosunda işareti görür — `paidTry` onun gördüğü sayı.
    assert ps.partner_self_view("p-1")["payoutCurrencyMismatchCount"] == 1


def test_karisik_birimli_defterde_POZITIF_odeme_dusser(depo):
    """Birim süzgecinin AÇTIĞI yolun bekçisi (ölçüldü).

    Süzgeç `paidTry`ye yalnız eşleşen kaydı sayıyor; bu doğru toplam ama
    bakiye kapısını anlamsız bırakıyor. Ölçülen zincir: ₺500 hakediş →
    ₺500 TRY ödeme → bakiye 0 (ikinci ödeme `exceeds_balance` ile düşer) →
    tek bir `PATCH payoutCurrency=USD` → `paidTry` 0, bakiye yine ₺500 →
    500 USD'lik İKİNCİ ödeme kapıdan GEÇİYOR. Yani ortağa iki kez ödenir
    ve kapı bunu engellediğini sanır.
    """
    _ortak(depo, rewardTry=500.0, payoutCurrency="TRY")
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)
    ps.add_payout("p-1", 500.0, "TRY", "odendi")
    assert ps.partner_detail("p-1")["balanceTry"] == 0.0

    # Ödeme defteri yazıldıktan SONRA birim değişimi.
    ps.update_partner("p-1", {"payoutCurrency": "USD"})
    detay = ps.partner_detail("p-1")
    assert detay["payoutCurrencyMismatchCount"] == 1
    # Bakiye yeniden ₺500 görünüyor — sayı yanlış ve bu işaretle görünür.
    assert detay["balanceTry"] == 500.0

    # Ama para ÇIKIŞI kapalı: yönetici sebebi görüyor, ödeme sessizce
    # geçmiyor.
    with pytest.raises(ps.RedeemError) as h:
        ps.add_payout("p-1", 500.0, "USD", "ikinci kez")
    assert h.value.status == 400
    assert h.value.reason == "ledger_currency_mixed"
    kayitlar = [k for k in depo if k.startswith("partners/p-1/payouts/")]
    assert len(kayitlar) == 1              # defter kirlenmedi

    # Düzeltme (negatif) kaydı BİLEREK serbest: karışıklığı gidermenin yolu
    # onun üzerinden geçiyor, kapatılırsa defter kilitlenirdi.
    ps.add_payout("p-1", -500.0, "USD", "yanlis birim duzeltmesi")
    assert len([k for k in depo
                if k.startswith("partners/p-1/payouts/")]) == 2


# --- Ortağın kendi panosu: sızıntı yok ----------------------------------

def test_ortak_panosu_isletme_verisi_sizdirmaz(depo):
    _ortak(depo, uid="ortak-uid")
    _tetikle(depo)
    depo["revenueEvents/e1"] = {
        "partnerId": "p-1", "environment": "PRODUCTION", "monetary": True,
        "eventType": "INITIAL_PURCHASE", "price": 3.0, "uid": "u1"}
    gorunum = ps.partner_self_view("p-1")
    assert "attributedGrossUsd" not in gorunum
    assert "attributedEvents" not in gorunum
    assert "uid" not in gorunum
    # Ortağın görmesi gerekenler duruyor.
    assert gorunum["pendingCount"] == 1
    assert gorunum["rewardTry"] == 30.0


def test_uid_ile_ortak_bulunur(depo):
    _ortak(depo, uid="ortak-uid")
    assert ps.partner_id_for_uid("ortak-uid") == "p-1"
    assert ps.partner_id_for_uid("yabanci") is None


# --- Yetki sınırı: ortak ≠ yönetici -------------------------------------

def test_ortak_claimi_yonetim_kapisini_GECMEZ():
    """Bu turun en kritik güvenlik iddiası.

    `"partner"` [core.auth.ROLES]'a eklenseydi `require_admin`'in
    `user.role in ROLES` kapısını geçer ve bir ortak token'ı tüm kullanıcı
    listesini, geliri, sistemi ve DİĞER ortakların detaylarını açardı.
    Ortaklık bu yüzden ayrı bir claim boyutu.
    """
    from fastapi import HTTPException
    from core import auth

    coz = auth._ortak_coz({"partner": True, "partnerId": "p-1"})
    assert coz == "p-1"
    ortak = auth.AuthUser(uid="o1", partner_id=coz)

    assert ortak.admin is False
    assert ortak.role is None
    assert "partner" not in auth.ROLES

    with pytest.raises(HTTPException) as h:
        auth.require_admin(ortak)
    assert h.value.status_code == 403
    # Kendi kapısından geçer.
    assert auth.require_partner(ortak) is ortak


def test_partnerId_tek_basina_yetki_VERMEZ():
    """`_rol_coz`un disiplini: kapı ayırt edici bayrağa dayanır, taşınabilir
    bir kimliğe değil. `partner: true` olmadan `partnerId` yok sayılır."""
    from core import auth
    assert auth._ortak_coz({"partnerId": "p-1"}) is None
    assert auth._ortak_coz({"partner": False, "partnerId": "p-1"}) is None


def test_ortaksiz_kullanici_ortak_kapisindan_gecemez():
    from fastapi import HTTPException
    from core import auth
    sade = auth.AuthUser(uid="u1")
    with pytest.raises(HTTPException) as h:
        auth.require_partner(sade)
    assert h.value.status_code == 403


def test_yonetici_de_ortak_kapisindan_gecemez():
    """Simetri: admin claim'i ortak panosuna erişim vermez."""
    from fastapi import HTTPException
    from core import auth
    yonetici = auth.AuthUser(uid="a1", admin=True, role="owner")
    with pytest.raises(HTTPException):
        auth.require_partner(yonetici)


# --- `/me`: GEÇİCİ hata ≠ KALICI yetki kaybı ----------------------------

def _me_hatasi(monkeypatch, hata: ps.RedeemError):
    """`/me` ucunu servis hatasıyla besler ve fırlatılan HTTP'yi döndürür."""
    from fastapi import HTTPException
    from api import partners as partners_api
    from core.auth import AuthUser

    # İki argüman: uç `caller_uid`i de geçiriyor (bayat claim kapısı).
    # Sahtenin imzası ucunkiyle uyuşmazsa test, ölçmek istediği hata
    # eşlemesi yerine bir `TypeError` ölçer.
    def _dus(_partner_id, _caller_uid=None):
        raise hata

    monkeypatch.setattr(partners_api.partner_service, "partner_self_view",
                        _dus)
    with pytest.raises(HTTPException) as h:
        partners_api.partner_me(AuthUser(uid="o1", partner_id="p-1"))
    return h.value


def test_me_gecici_hatada_503_doner(monkeypatch):
    """Ölçülen kırılma: soğuk Cloud Run örneğinde ADC henüz çözülmemişken
    `get_client()` None döner ve servis "unavailable" fırlatır. Bu 403
    olarak çıkınca pano zorunlu çıkış yapıp jenerik 404 basıyor; ortak
    hesabının kapatıldığını sanıyor, F5 ile düzeliyor ve olay hiçbir yerde
    hata olarak görünmüyor. `core/firestore.py` kalıcı mandalı BİLEREK
    kurmuyor, yani bu hâl gerçekten geçici."""
    hata = _me_hatasi(monkeypatch, ps.RedeemError(500, "unavailable"))
    assert hata.status_code == 503
    # Makine-okur kod: istemci "tekrar dene"yi metne bakmadan ayırt etsin.
    assert hata.detail["code"] == "temporarily_unavailable"
    assert hata.detail["reason"] == "unavailable"
    assert hata.headers.get("Retry-After")


def test_me_kayit_yoksa_403_kalir(monkeypatch):
    """Kalıcı hâl: claim var, ortak kaydı yok. Jenerik 403 — "kayıt yok"
    demek silinmiş bir ortağa sistemin şeklini anlatır."""
    hata = _me_hatasi(monkeypatch, ps.RedeemError(404, "not_found"))
    assert hata.status_code == 403
    assert hata.detail == "Yetkisiz."


def test_pasif_ortak_panoyu_GORMEYE_DEVAM_EDER(depo):
    """Yorumun ölçülen gerçeğe uyduğunun bekçisi: `partner_detail` yalnız
    doküman YOKKEN 404 fırlatıyor, `active: false` kontrolü hiçbir yerde
    yok. Bu bilinçli — ortak neden kazanmadığını görmek zorunda."""
    _ortak(depo)
    _tetikle(depo)
    depo["partners/p-1"]["active"] = False
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)        # kayıt `partner_inactive`

    gorunum = ps.partner_self_view("p-1")
    assert gorunum["active"] is False
    assert gorunum["name"] == "Ortak"
    # Yorumun dayandığı şey: kazanmadığını GÖREBİLİYOR — kapıyı kapatmak
    # ona yalnız açıklamasız bir hata gösterirdi.
    assert gorunum["voidCount"] == 1
    assert gorunum["pendingCount"] == 0
    assert gorunum["earnedTry"] == 0.0


# --- Uç modeli: uid zorunlu (kendi-kodunu-kullanma kapısının şartı) ------

def test_uidsiz_ortak_olusturma_uc_modelinde_REDDEDILIR():
    """uid boşken kapı `None != uid` yüzünden sessizce devre dışı kalıyor;
    ortak kendi kodunu kendi hesabında kullanıp kendine atıf üretebiliyor.
    Tanıtım sayfası ise "uç bunu reddeder" diye yazıyor."""
    from pydantic import ValidationError
    from api.admin import PartnerCreate

    with pytest.raises(ValidationError):
        PartnerCreate(name="Ortak", contact="a@b.c")      # uid hiç yok
    with pytest.raises(ValidationError):
        PartnerCreate(name="Ortak", contact="a@b.c", uid="")
    # Geçerli uid ile model kurulur.
    assert PartnerCreate(name="Ortak", contact="a@b.c",
                         uid="firebase-uid").uid == "firebase-uid"


def test_uidsiz_ortak_olusturma_SERVISTE_de_reddedilir(depo):
    """İkinci katman: uç değişse bile servis beyanı korur. Yalnız
    boşluktan oluşan uid `min_length` kapısını geçebilir, buradan geçemez."""
    for bozuk in [None, "", "   "]:
        with pytest.raises(ps.RedeemError) as h:
            ps.create_partner("Ortak", "a@b.c", 0, uid=bozuk)
        assert h.value.reason == "uid_required"
    ortak = ps.create_partner("Ortak", "a@b.c", 0, uid=" firebase-uid ")
    assert ortak["uid"] == "firebase-uid"


def test_ortak_uidi_PATCH_ile_bosaltilamaz(depo):
    """uid'i sonradan silebilmek, kendi-kodunu-kullanma kapısını tek bir
    PATCH ile sessizce kapatmanın yolu olurdu."""
    _ortak(depo, uid="ortak-uid")
    with pytest.raises(ps.RedeemError) as h:
        ps.update_partner("p-1", {"uid": ""})
    assert h.value.reason == "uid_required"
    assert depo["partners/p-1"]["uid"] == "ortak-uid"
    # Alanı hiç göndermemek serbest.
    ps.update_partner("p-1", {"notes": "not"})
    assert depo["partners/p-1"]["uid"] == "ortak-uid"


def test_uidsiz_ortagin_kodu_kapinin_calismadigini_LOGLAR(depo, monkeypatch,
                                                          caplog):
    """403 yapmıyoruz (uid'i henüz bağlanmamış eski ortağın TÜM atıflarını
    kırardı) ama kapının o ortakta çalışmadığı görünür olmalı."""
    _ortak(depo)                      # uid alanı YOK
    depo["partnerCodes/ORTAK10"] = {
        "partnerId": "p-1", "bonusTokens": 0, "maxRedemptions": None,
        "redemptionCount": 0, "expiresAt": None, "active": True}
    monkeypatch.setattr(ps.wallet, "credit_promo", lambda *a: True)
    with caplog.at_level("WARNING"):
        ps.redeem("kim-olursa", "ORTAK10")
    assert "uid bos" in caplog.text
    # Atıf yine yazıldı: uyarı akışı durdurmuyor.
    assert depo["users/kim-olursa/private/attribution"]["partnerId"] == "p-1"


# --- Ortak ERİŞİMİ: claim'i komut satırından panele taşımak --------------
#
# Korunan şey panonun ULAŞILABİLİRLİĞİ: ortaklık claim'i yalnız
# `tools/set_admin.py --partner` ile basılabildiği sürece, panelden ortak
# açan yönetici için `web/ortak/` panosu pratikte YOKTU (ölçüldü — sahip
# test ortağını ekledi ve ortağın nereden gireceği hiçbir yerde yazmıyordu).


class UserNotFoundError(Exception):
    """`firebase_admin.auth.UserNotFoundError`ın ADAŞI.

    Ad birebir aynı olmak ZORUNDA: `ps._kullanici_yok_mu` sınıfın ADINA
    bakıyor — gerçek sınıf `firebase_admin._auth_utils` içinde tanımlı,
    yani alt çizgili bir modülde (emsal
    `test_admin_audit.FailedPrecondition`). Ad kayarsa "böyle hesap yok"
    hâli sessizce "geçici arıza"ya düşer ve aşağıdaki iki iddia birbirinin
    yerine geçer.
    """


class SahteHesap:
    def __init__(self, uid, email=None, claims=None):
        self.uid = uid
        self.email = email
        self.custom_claims = dict(claims) if claims else None


class SahteAuth:
    """`firebase_admin.auth`ın test karşılığı; yazımları kaydeder."""

    def __init__(self, hesaplar=None, *, okuma_hatasi=None,
                 yazma_hatasi=None):
        self.hesaplar = {h.uid: h for h in (hesaplar or [])}
        self._okuma_hatasi = okuma_hatasi
        self._yazma_hatasi = yazma_hatasi
        self.yazimlar: list = []

    def get_user(self, uid):
        if self._okuma_hatasi is not None:
            raise self._okuma_hatasi
        if uid not in self.hesaplar:
            raise UserNotFoundError(uid)
        return self.hesaplar[uid]

    def set_custom_user_claims(self, uid, claims):
        if self._yazma_hatasi is not None:
            raise self._yazma_hatasi
        self.yazimlar.append((uid, claims))
        self.hesaplar[uid].custom_claims = dict(claims) if claims else None


@pytest.fixture(autouse=True)
def _tiklama_tavani_sifirla():
    """Kod başına tıklama sayacı MODÜL DÜZEYİNDE bir sözlük.

    Pinlenmezse testler arası sızar: bir testte tavana dayanan kod,
    sonraki testte ilk istekte reddedilir ve o test ölçmek istediği
    şey yerine komşusunun artığını ölçer. (Bu tam olarak oldu:
    `..._AUTHORIZATION_basligiyla_ATLATILAMAZ` komşusu yüzünden
    kırmızıya döndü.) `conftest` pinleri ile aynı doktrin — süreç içi
    durum testin girdisidir, testler arası taşınamaz.
    """
    from api import partners as partners_api
    partners_api._kod_vurus.clear()
    yield
    partners_api._kod_vurus.clear()

def _auth_pinle(monkeypatch, sahte):
    """Auth'u BİLEREK sınayan testin kendi sahtesi.

    `conftest.auth_hermetik` `_auth_modulu`yu her testte açık hatayla
    düşen bir pine bağlıyor (CLAUDE.md: dışa çıkan her istemciye ayrı
    pin); bu yama onun ÜSTÜNE yazdığı için kazanır —
    `kapi_hermetik`/`depolama_hermetik` ile aynı çıkış yolu.
    """
    monkeypatch.setattr(ps, "_auth_modulu", lambda: sahte)
    return sahte


def _sahip_kullanici():
    from core.auth import AuthUser
    return AuthUser(uid="sahip", email="sahip@ornek.com", admin=True,
                    role="owner")


def test_hesap_yok_hatasi_GERCEK_sinif_adiyla_taniniyor():
    """Yukarıdaki adaşın dayandığı şey ÖLÇÜLÜYOR: kurulu `firebase_admin`in
    gerçek sınıfı da aynı adı taşıyor. Ad kayarsa (ya da sınıf yeniden
    adlandırılırsa) bütün `user_not_found` yolu sessizce `unavailable`a
    döner — yönetici "hesap yok"u hiç görmez, sonsuza kadar "biraz sonra
    tekrar dene" okur."""
    from firebase_admin import auth as fb_auth

    assert ps._kullanici_yok_mu(fb_auth.UserNotFoundError("yok")) is True
    assert ps._kullanici_yok_mu(UserNotFoundError("yok")) is True
    assert ps._kullanici_yok_mu(RuntimeError("deadline exceeded")) is False


def test_erisim_acilinca_claim_basilir_ve_admin_claimi_KORUNUR(depo,
                                                               monkeypatch):
    """Claim BİRLEŞTİRİLİR, ezilmez (`tools/set_admin.py` disiplini).

    Somut kırılma: sahip kendi hesabını test ortağı yapar. Claim komple
    ezilseydi `admin`/`role` de silinir ve sahip PANELDEN KİLİTLENİRDİ —
    geri dönüşün tek yolu komut satırı olurdu.
    """
    _ortak(depo, uid="sahip-uid")
    sahte = _auth_pinle(monkeypatch, SahteAuth([
        SahteHesap("sahip-uid", "sahip@ornek.com",
                   {"admin": True, "role": "owner"})]))

    erisim = ps.set_partner_access("p-1", True)

    assert erisim == {"uid": "sahip-uid", "granted": True,
                      "email": "sahip@ornek.com", "reason": None}
    assert sahte.hesaplar["sahip-uid"].custom_claims == {
        "admin": True, "role": "owner", "partner": True, "partnerId": "p-1"}


def test_erisim_kapatilinca_YALNIZ_ortaklik_anahtarlari_silinir(depo,
                                                                monkeypatch):
    """Kaldırma da birleştirmedir: `admin`/`role` DURUR."""
    _ortak(depo, uid="sahip-uid")
    sahte = _auth_pinle(monkeypatch, SahteAuth([
        SahteHesap("sahip-uid", "sahip@ornek.com",
                   {"admin": True, "role": "owner", "partner": True,
                    "partnerId": "p-1"})]))

    erisim = ps.set_partner_access("p-1", False)

    assert erisim["granted"] is False
    assert sahte.hesaplar["sahip-uid"].custom_claims == {"admin": True,
                                                         "role": "owner"}


def test_sade_hesapta_erisim_kapatmak_claimi_TAMAMEN_bosaltir(depo,
                                                              monkeypatch):
    """`mevcut or None`: Firebase'de "claim yok" hâli boş sözlük değil
    ``None``dur (set_admin.py deseni)."""
    _ortak(depo, uid="ortak-uid")
    sahte = _auth_pinle(monkeypatch, SahteAuth([
        SahteHesap("ortak-uid", "o@ornek.com",
                   {"partner": True, "partnerId": "p-1"})]))

    ps.set_partner_access("p-1", False)

    assert sahte.yazimlar == [("ortak-uid", None)]


def test_ayni_ortaga_yeniden_basmak_IDEMPOTENT(depo, monkeypatch):
    """Panel iki kez basılabilir; ikinci basış hata değil aynı sonuç."""
    _ortak(depo, uid="ortak-uid")
    sahte = _auth_pinle(monkeypatch, SahteAuth([
        SahteHesap("ortak-uid", "o@ornek.com",
                   {"partner": True, "partnerId": "p-1"})]))

    assert ps.set_partner_access("p-1", True)["granted"] is True
    assert sahte.hesaplar["ortak-uid"].custom_claims == {
        "partner": True, "partnerId": "p-1"}


def test_uidsiz_ortakta_erisim_basilamaz(depo, monkeypatch):
    """`partners/{id}.uid` yoksa basılacak hedef de yok. 400 `no_uid`:
    yönetici önce hesabı bağlamalı."""
    _ortak(depo)                                  # uid alanı YOK
    sahte = _auth_pinle(monkeypatch, SahteAuth())
    with pytest.raises(ps.RedeemError) as h:
        ps.set_partner_access("p-1", True)
    assert (h.value.status, h.value.reason) == (400, "no_uid")
    assert sahte.yazimlar == []


def test_olmayan_hesaba_erisim_basilamaz(depo, monkeypatch):
    """uid yazılı ama Firebase hesabı yok (yanlış yazım ya da silinmiş
    hesap). GEÇİCİ arızadan ayrı bir sebep dönmeli, yoksa yönetici doğru
    yazılmış bir uid'i "düzeltmeye" başlar."""
    _ortak(depo, uid="hayalet-uid")
    _auth_pinle(monkeypatch, SahteAuth())
    with pytest.raises(ps.RedeemError) as h:
        ps.set_partner_access("p-1", True)
    assert (h.value.status, h.value.reason) == (400, "user_not_found")


def test_olmayan_ortakta_erisim_404(depo, monkeypatch):
    _ortak(depo)
    _auth_pinle(monkeypatch, SahteAuth())
    with pytest.raises(ps.RedeemError) as h:
        ps.set_partner_access("yok-boyle-ortak", True)
    assert (h.value.status, h.value.reason) == (404, "not_found")


def test_BASKA_ortaga_bagli_uid_reddedilir(depo, monkeypatch):
    """Sızıntı kapısı: tek hesap iki ortağa bağlanırsa `/partners/me`
    claim'deki `partnerId`yi okur ve ortak YANLIŞ ortağın bakiyesini
    görür."""
    _ortak(depo, pid="p-1", uid="ortak-uid")
    _ortak(depo, pid="p-2", uid="ortak-uid")       # aynı hesap, ikinci ortak
    sahte = _auth_pinle(monkeypatch, SahteAuth([
        SahteHesap("ortak-uid", "o@ornek.com",
                   {"partner": True, "partnerId": "p-1"})]))

    with pytest.raises(ps.RedeemError) as h:
        ps.set_partner_access("p-2", True)
    assert (h.value.status, h.value.reason) == (400, "uid_taken")
    # p-1'in claim'i DOKUNULMADI.
    assert sahte.hesaplar["ortak-uid"].custom_claims["partnerId"] == "p-1"


def test_BASKA_ortagin_erisimi_buradan_KAPATILAMAZ(depo, monkeypatch):
    """Kapı kaldırmada da geçerli: p-2'de "kapat"a basmak, silinecek
    claim p-1'in claim'i olduğu için p-1'in panosunu sessizce kapatırdı."""
    _ortak(depo, pid="p-1", uid="ortak-uid")
    _ortak(depo, pid="p-2", uid="ortak-uid")
    sahte = _auth_pinle(monkeypatch, SahteAuth([
        SahteHesap("ortak-uid", "o@ornek.com",
                   {"partner": True, "partnerId": "p-1"})]))

    with pytest.raises(ps.RedeemError) as h:
        ps.set_partner_access("p-2", False)
    assert h.value.reason == "uid_taken"
    assert sahte.yazimlar == []


def test_claim_yazimi_dusverse_500_unavailable(depo, monkeypatch):
    """Yazım düşerse sessiz kalınamaz: yönetici "açtım" sanıp ortağı
    kapıda bırakır."""
    _ortak(depo, uid="ortak-uid")
    _auth_pinle(monkeypatch, SahteAuth(
        [SahteHesap("ortak-uid", "o@ornek.com")],
        yazma_hatasi=RuntimeError("503 Auth backend hatasi")))
    with pytest.raises(ps.RedeemError) as h:
        ps.set_partner_access("p-1", True)
    assert (h.value.status, h.value.reason) == (500, "unavailable")


def test_erisim_gostergesi_AUTH_patlayinca_FIRLATMAZ(depo, monkeypatch):
    """`granted` üçüncü değeri (None) tam olarak bunun için var: "kapalı"
    ile "bilmiyoruz" aynı şey değil. Auth kesintisi ortak detay sayfasının
    tamamını — hakediş ve ödeme sayılarını — düşürmemeli."""
    _ortak(depo, uid="ortak-uid")
    _auth_pinle(monkeypatch, SahteAuth(
        okuma_hatasi=RuntimeError("deadline exceeded")))

    erisim = ps.partner_access("p-1")
    assert erisim == {"uid": "ortak-uid", "granted": None, "email": None,
                      "reason": "unavailable"}
    # Sayfanın geri kalanı ayakta: `partner_detail` de fırlatmadı.
    assert ps.partner_detail("p-1")["access"]["reason"] == "unavailable"


def test_erisim_gostergesi_uid_yoksa_no_uid(depo, monkeypatch):
    _ortak(depo)                                  # uid alanı YOK
    _auth_pinle(monkeypatch, SahteAuth())
    assert ps.partner_access("p-1") == {"uid": None, "granted": None,
                                        "email": None, "reason": "no_uid"}


def test_erisim_gostergesi_hesap_yoksa_user_not_found(depo, monkeypatch):
    _ortak(depo, uid="hayalet-uid")
    _auth_pinle(monkeypatch, SahteAuth())
    assert ps.partner_access("p-1")["reason"] == "user_not_found"
    assert ps.partner_access("p-1")["granted"] is None


def test_erisim_gostergesi_BASKA_ortaga_bagliysa_FALSE(depo, monkeypatch):
    """Bu claim bu panoyu açmıyor — "erişimi var" demek yanlış olurdu.
    `granted` None DEĞİL: durum ölçüldü ve biliniyor."""
    _ortak(depo, pid="p-2", uid="ortak-uid")
    _auth_pinle(monkeypatch, SahteAuth([
        SahteHesap("ortak-uid", "o@ornek.com",
                   {"partner": True, "partnerId": "p-1"})]))
    erisim = ps.partner_access("p-2")
    assert erisim["granted"] is False
    assert erisim["reason"] is None


def test_partner_detail_erisim_gostergesini_TASIR(depo, monkeypatch):
    """Panel sözleşmesi: yönetici ortağın giremediğini detay sayfasında
    görmek zorunda."""
    _ortak(depo, uid="ortak-uid")
    _auth_pinle(monkeypatch, SahteAuth([
        SahteHesap("ortak-uid", "o@ornek.com",
                   {"partner": True, "partnerId": "p-1"})]))
    assert ps.partner_detail("p-1")["access"] == {
        "uid": "ortak-uid", "granted": True, "email": "o@ornek.com",
        "reason": None}


def test_ortak_panosu_ve_ODEME_yolu_AUTHA_GITMEZ(depo, monkeypatch):
    """Dar görünüm değişmedi (ortağın kendi claim'ini görmesine gerek yok)
    ve para yolu Firebase Auth'a bağlanmadı: `add_payout` bakiye için
    `partner_detail` çağırıyor, claim'le işi yok."""
    class _Patlar:
        def get_user(self, uid):                       # noqa: ARG002
            raise AssertionError("bu yol Firebase Auth'a gitmemeli")

    _ortak(depo, uid="ortak-uid")
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)                # bakiye 30
    monkeypatch.setattr(ps, "_auth_modulu", lambda: _Patlar())

    gorunum = ps.partner_self_view("p-1")
    assert "access" not in gorunum
    ps.add_payout("p-1", 30.0, "TRY", "tam")           # kapı Auth'suz çalıştı


def test_erisim_ucu_denetim_izine_duser(depo, monkeypatch):
    """Yetki değişikliğinin TEK kaydı bu iz: Firebase Auth'ta okunabilir
    bir geçmiş yok, yani iz düşmezse kimin ne zaman erişim açtığı hiçbir
    yerde kalmaz."""
    from api import admin as admin_api

    _ortak(depo, uid="ortak-uid")
    _auth_pinle(monkeypatch, SahteAuth([SahteHesap("ortak-uid",
                                                   "o@ornek.com")]))
    yanit = admin_api.partner_access_set(
        "p-1", admin_api.PartnerAccessRequest(grant=True), _sahip_kullanici())

    assert yanit["status"] == "ok"
    assert yanit["access"]["granted"] is True
    izler = [v for k, v in depo.items() if k.startswith("adminAudit/")]
    assert len(izler) == 1
    assert izler[0]["action"] == "partner.access"
    assert izler[0]["params"] == {"partnerId": "p-1", "grant": True}
    assert izler[0]["phase"] == "done"
    assert izler[0]["adminRole"] == "owner"
    # Claim'i ALAN hesap izde duruyor: "kim erişim aldı" sorusu diğer
    # eylemlerle aynı alandan (`targetUid`) cevaplanıyor.
    assert izler[0]["targetUid"] == "ortak-uid"


def test_ODEME_KIMLIGI_denetim_izine_DEGERIYLE_yazilmaz(depo):
    """IBAN ve vergi kimliği ize DEĞERİYLE düşmez; öteki alanlar düşer.

    `_audit` `params`ı olduğu gibi `adminAudit` dokümanına yazıyor ve o
    koleksiyon KALICI — her düzeltmede ortağın ödeme kimliğinin bir kopyası
    daha birikirdi. İzin işi "kim neyi ne zaman değiştirdi"dir; alanın
    DEĞİŞTİĞİ görünür kalıyor, DEĞERİ kalmıyor.

    `minPayoutTry` BİLEREK maskesiz: para tutarı sır değil ve mutabakatta
    "eşik o gün kaçtı" sorusunun tek cevabı bu iz.
    """
    from api import admin as admin_api

    _ortak(depo, pid="p-1", uid="ortak-uid")
    yanit = admin_api.patch_partner(
        "p-1",
        admin_api.PartnerPatch(iban="TR120006200000000006297561",
                               taxId="1234567890",
                               minPayoutTry=250),
        _sahip_kullanici())
    assert yanit["status"] == "ok"
    # Yazım GERÇEKTEN olmuş: maske izi değiştiriyor, veriyi değiştirmiyor.
    assert depo["partners/p-1"]["iban"] == "TR120006200000000006297561"
    assert depo["partners/p-1"]["minPayoutTry"] == 250

    iz = [v for k, v in depo.items() if k.startswith("adminAudit/")][0]
    assert iz["action"] == "partner.update"
    assert "TR120006200000000006297561" not in str(iz["params"])
    assert "1234567890" not in str(iz["params"])
    # Alanın DEĞİŞTİĞİ hâlâ görünüyor (iz zayıflamadı) ve uzunluk kalıyor.
    assert "26 hane" in iz["params"]["iban"]
    assert "10 hane" in iz["params"]["taxId"]
    assert iz["params"]["minPayoutTry"] == 250


def test_iz_yazilamazsa_claim_BASILMAZ(depo, monkeypatch):
    """Ön-iz (`zorunlu=True`) emsali `user.disable`: iz yazılamazken yetki
    değiştirmek, kaydı hiç olmayan bir erişim açmaktır.

    503 iddiası sırayı da kilitliyor: eylem izden ÖNCE koşsaydı servis
    Firestore'suz `unavailable` fırlatır ve yanıt 500 olurdu.
    """
    from api import admin as admin_api
    from fastapi import HTTPException

    _ortak(depo, uid="ortak-uid")
    sahte = _auth_pinle(monkeypatch, SahteAuth([SahteHesap("ortak-uid")]))
    monkeypatch.setattr(admin_api.firestore_client, "get_client",
                        lambda: None)

    with pytest.raises(HTTPException) as h:
        admin_api.partner_access_set(
            "p-1", admin_api.PartnerAccessRequest(grant=True),
            _sahip_kullanici())
    assert h.value.status_code == 503
    assert sahte.yazimlar == []


def test_erisim_ucu_OWNER_kapisi_arkasinda(monkeypatch):
    """Destek rolü bir hesaba yetki BASAMAZ; emsal `user.disable` ve
    `config.min_build` (ikisi de owner). Owner'ın 403 DEĞİL 503 alması
    kapının geçildiğini gösteriyor: gövdedeki ön-iz, pinli Firestore
    yokluğunda düşüyor."""
    from fastapi.testclient import TestClient
    from core import config
    from main import app

    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(config, "DEV_ADMIN", True)
    monkeypatch.setattr(config, "DEV_ADMIN_ROLE", "support")
    with TestClient(app) as istemci:
        assert istemci.post("/api/v1/admin/partners/p-1/access",
                            json={"grant": True}).status_code == 403
        monkeypatch.setattr(config, "DEV_ADMIN_ROLE", "owner")
        yanit = istemci.post("/api/v1/admin/partners/p-1/access",
                             json={"grant": True})
    assert yanit.status_code == 503
    # Sebep ÖLÇÜLÜYOR: 503'ün ön-izden geldiği yazılmazsa test başka bir
    # arızayla da yeşil kalır ve "kapı geçildi" iddiası kanıtsız olur.
    assert yanit.json()["detail"] == "Denetim izi yazılamadı; işlem yapılmadı."


def test_huni_ve_bakiye(depo):
    _ortak(depo)
    depo["partnerCodes/K1"] = {"partnerId": "p-1", "redemptionCount": 7,
                               "active": True}
    _tetikle(depo, uid="u1")
    _tetikle(depo, uid="u2")
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)
    detay = ps.partner_detail("p-1")
    assert detay["referredUsers"] == 7
    assert detay["qualifiedCount"] == 2
    assert detay["earnedTry"] == 60.0
    assert detay["balanceTry"] == 60.0


# ---------------------------------------------------------------------------
# YÖNETİM LİSTESİ: huninin ilk iki basamağı
#
# Buradaki iddialar para değil ÖLÇÜMÜN DÜRÜSTLÜĞÜNÜ koruyor. Liste ekranı
# ortak dokümanını döndürüyor ama tıklama ve kuran sayıları KOD
# dokümanlarında duruyor; toplama düşerse panel bir sayı göstermek ZORUNDA
# değil — göstermemesi gerekiyor. "0 tıklama" yazmak, çalışan bir tanıtımı
# ölmüş gibi göstermek olurdu ve hata hiçbir yerde görünmezdi.
# ---------------------------------------------------------------------------


def test_liste_tiklama_ve_kuran_KOD_BASINA_toplanir(depo):
    """İki kodun sayıları TEK ortakta toplanır; başka ortağa sızmaz."""
    _ortak(depo, pid="p-1")
    _ortak(depo, pid="p-2")
    depo["partnerCodes/K1"] = {"partnerId": "p-1", "clickCount": 40,
                               "redemptionCount": 3}
    depo["partnerCodes/K2"] = {"partnerId": "p-1", "clickCount": 2,
                               "redemptionCount": 1}
    depo["partnerCodes/K9"] = {"partnerId": "p-2", "clickCount": 5,
                               "redemptionCount": 0}
    liste = {o["id"]: o for o in ps.list_partners()}
    assert (liste["p-1"]["clicks"], liste["p-1"]["referredUsers"]) == (42, 4)
    assert (liste["p-2"]["clicks"], liste["p-2"]["referredUsers"]) == (5, 0)


def test_liste_KODU_OLMAYAN_ortakta_SIFIR_yazar(depo):
    """Kodu olmayan ortakta 0 ÖLÇÜLMÜŞ sonuçtur: kod yoksa tıklama da yok.

    Yokluk ile sıfırın ayrıldığı yer bu değil (o aşağıdaki test) — burada
    toplama BAŞARILI ve sonucu gerçekten sıfır.
    """
    _ortak(depo, pid="p-1")
    ortak = ps.list_partners()[0]
    assert ortak["clicks"] == 0
    assert ortak["referredUsers"] == 0


def test_liste_partnerIdSIZ_kod_HIC_KIMSEYE_yazilmaz(depo):
    """Hangi ortağa ait olduğu bilinmeyen kod, bir ortağa yazılmaz.

    Bozuk/yetim bir kod dokümanı (elle açılmış, ya da silinmiş ortaktan
    kalmış) ilk ortağa eklenseydi o ortağın huni sayısı sessizce şişer ve
    kimse nedenini bulamazdı.
    """
    _ortak(depo, pid="p-1")
    depo["partnerCodes/YETIM"] = {"clickCount": 99, "redemptionCount": 9}
    depo["partnerCodes/BOSLUK"] = {"partnerId": "  ", "clickCount": 7}
    ortak = ps.list_partners()[0]
    assert ortak["clicks"] == 0
    assert ortak["referredUsers"] == 0


def test_liste_toplamasi_DUSERSE_anahtarlar_HIC_OLMAZ(depo, monkeypatch):
    """Toplama patlarsa liste AYAKTA kalır ve iki anahtar YANITTA OLMAZ.

    `0` yazmak en pahalı seçenekti: panel "ölçtük, hiç tıklama yok" diye
    çizer ve ortağın çalışan tanıtımı ölmüş görünür. Ortağın KENDİSİNİ hiç
    göstermemek de yanlış — telemetri okuması yönetim ekranını düşürmemeli.
    """
    _ortak(depo, pid="p-1")

    def patla(_client):
        raise RuntimeError("partnerCodes okunamadi")

    monkeypatch.setattr(ps, "_kod_toplamlari", patla)
    ortaklar = ps.list_partners()
    assert len(ortaklar) == 1 and ortaklar[0]["id"] == "p-1"
    assert "clicks" not in ortaklar[0]
    assert "referredUsers" not in ortaklar[0]


# ---------------------------------------------------------------------------
# ÖDEME EŞİĞİ (`minPayoutTry`): üç hâl, üç ayrı anlam
#
# Alan yalnız o ortağın ANLAŞMASINDA varsa girilir; ürün genelinde bir eşik
# YOK (`web/ortaklik.html`: "alt sınır anlaşmada yazılır"). Bu yüzden
# `create_partner` alanı hiç yazmıyor ve dar görünüm de uydurmuyor —
# olmayan bir eşiği ortağa duyurmak, panonun tutamayacağı bir söz olurdu.
# ---------------------------------------------------------------------------


def test_yeni_ortakta_esik_HIC_YAZILMAZ(depo):
    """`create_partner` varsayılan eşik YAZMAZ — bu karar, eksiklik değil.

    Bir sayı yazmak kimsenin kabul etmediği bir alt sınır icat etmek,
    0 yazmak da "alt sınır yok" diye anlaşmayı aşan bir söz vermek olurdu.
    """
    ortak = ps.create_partner("Ortak", "a@x.co", 0, uid="U1")
    assert "minPayoutTry" not in ortak
    assert "minPayoutTry" not in depo[f"partners/{ortak['id']}"]


def test_esik_GIRILMEMISSE_dar_gorunumde_ANAHTAR_YOK(depo):
    """Yokluk taşınır: pano eşikten hiç söz etmesin."""
    _ortak(depo, pid="p-1", uid="U1")
    assert "minPayoutTry" not in ps.partner_self_view("p-1", "U1")


def test_esik_SIFIR_ile_esik_YOK_dar_gorunumde_AYRI(depo):
    """0 ölçülmüş bir DEĞER ("alt sınır yok"), eksik alan değil.

    İkisi aynı şekle sıkışsaydı pano "alt sınır yok" diyemez ya da
    girilmemiş bir eşiği "yok" sanıp öyle duyururdu.
    """
    _ortak(depo, pid="p-1", uid="U1", minPayoutTry=0)
    gorunum = ps.partner_self_view("p-1", "U1")
    assert "minPayoutTry" in gorunum and gorunum["minPayoutTry"] == 0.0


def test_esik_POZITIFSE_dar_gorunume_TASINIR(depo):
    _ortak(depo, pid="p-1", uid="U1", minPayoutTry=250)
    assert ps.partner_self_view("p-1", "U1")["minPayoutTry"] == 250.0


def test_BOZUK_esik_panoya_GIRMEZ(depo):
    """Sayı olmayan eşik ÖLÇÜLMEMİŞ sayılır; pano "NaN ₺ kaldı" yazmasın.

    Elle açılmış ya da yanlış tipte yazılmış bir alan panonun tamamını
    okunmaz yapardı — eksik bir kart, yanlış bir karttan iyidir.
    """
    _ortak(depo, pid="p-1", uid="U1", minPayoutTry="çok")
    assert "minPayoutTry" not in ps.partner_self_view("p-1", "U1")


def test_esik_ISLETME_verisi_SIZDIRMIYOR(depo):
    """Eşik eklendi diye dar görünüm genişlemedi: ödeme KİMLİĞİ hâlâ dışarıda.

    `taxId`/`iban` ortağın panosunda hiç görünmemeli; pano paylaşılabilir
    bir ekran ve o iki alanın orada karar değeri yok.
    """
    _ortak(depo, pid="p-1", uid="U1", minPayoutTry=100,
           taxId="1234567890", iban="TR000000000000000000000000")
    gorunum = ps.partner_self_view("p-1", "U1")
    assert "taxId" not in gorunum and "iban" not in gorunum


# ---------------------------------------------------------------------------
# Bayat claim kapısı: uid değişince ESKİ hesap düşmeli
# ---------------------------------------------------------------------------


def test_bayat_claim_bir_sonraki_istekte_duser(depo):
    """Claim `partnerId` taşır; kaynaktaki bağ değişince ESKİ hesap düşer.

    Ölçülen sızıntı buydu: `_ortak_coz` partnerId'yi YALNIZ claim'den
    okuyor. uid A→B değiştirildiğinde A'nın claim'i hiçbir ekranda
    görünmüyor ve Firebase propagasyonu yüzünden bir saate kadar
    geçerli kalıyordu. Kapı kaynakta olmalı.
    """
    _ortak(depo, uid="B")
    assert ps.partner_self_view("p-1", "B")["name"] == "Ortak"
    with pytest.raises(ps.RedeemError) as h:
        ps.partner_self_view("p-1", "A")
    assert h.value.status == 404


def test_self_view_uidsiz_cagride_bagi_DOGRULAMAZ(depo):
    """Geriye uyum: `caller_uid` verilmeyen çağrı eski davranışta kalır.

    `add_payout` ve yönetim yolları bu biçimi kullanıyor; oradaki
    çağıran ortak DEĞİL, bağ karşılaştırması anlamsız olurdu.
    """
    _ortak(depo, uid="B")
    assert ps.partner_self_view("p-1")["name"] == "Ortak"


def test_uid_degisince_ESKI_hesabin_claimi_dusurulur(depo, monkeypatch):
    """Yazma anındaki temizlik: eski hesapta ölü bağ kalmaz.

    Okuma kapısının yerine GEÇMEZ (Firebase claim'i bir saate kadar
    taşımaya devam eder) — Firebase tarafını da tutarlı tutar.
    """
    _ortak(depo, uid="A")
    auth = _auth_pinle(monkeypatch, SahteAuth([
        SahteHesap("A", "a@x.co", {"partner": True, "partnerId": "p-1"}),
        SahteHesap("B", "b@x.co"),
    ]))
    ps.update_partner("p-1", {"uid": "B"})
    assert depo["partners/p-1"]["uid"] == "B"
    assert auth.hesaplar["A"].custom_claims is None


def test_uid_degisiminde_eski_hesabin_ADMIN_claimi_KORUNUR(depo, monkeypatch):
    """Temizlik yalnız ortaklık anahtarlarını siler.

    Somut kırılma: sahip kendi hesabını test ortağı yapar, sonra uid'i
    gerçek ortağa çevirir. Claim komple ezilseydi kendi `admin`
    claim'ini kaybeder ve PANELDEN KİLİTLENİRDİ.
    """
    _ortak(depo, uid="A")
    auth = _auth_pinle(monkeypatch, SahteAuth([
        SahteHesap("A", "a@x.co", {"admin": True, "role": "owner",
                                   "partner": True, "partnerId": "p-1"}),
        SahteHesap("B", "b@x.co"),
    ]))
    ps.update_partner("p-1", {"uid": "B"})
    assert auth.hesaplar["A"].custom_claims == {"admin": True,
                                                "role": "owner"}


def test_eski_hesap_silinmisse_uid_degisimi_DUSMEZ(depo, monkeypatch):
    """Temizlik best-effort: Firestore yazımı ZATEN olmuş durumda.

    Auth erişilemiyor diye yöneticiye hata döndürmek, yapılmış bir
    değişikliği başarısız gibi gösterir ve tekrar denemeye iter.
    """
    _ortak(depo, uid="A")
    _auth_pinle(monkeypatch, SahteAuth([SahteHesap("B", "b@x.co")]))
    ps.update_partner("p-1", {"uid": "B"})   # fırlatmamalı
    assert depo["partners/p-1"]["uid"] == "B"


# ---------------------------------------------------------------------------
# Huninin TEPESİ: tıklama sayacı
#
# Buradaki iddialar para değil ÖLÇÜMÜN DÜRÜSTLÜĞÜNÜ koruyor ve bu dosyaya
# ait: huninin geri kalanı (kuran → hakediş → ödeme) yukarıda ölçülüyor,
# tıklama onun bölenidir. Sayaç sessizce ölürse kimse zarar görmez ama
# ortak tanıtımının işe yarayıp yaramadığını bilemez ve dönüşüm oranı
# hesaplanamaz.
#
# Uç KİMLİKSİZ ve herkese açık: kapı testleri (biçim, kodun varlığı, yazım
# yokluğu) bu yüzden ödül kapıları kadar sıkı.
# ---------------------------------------------------------------------------

#: Gün dokümanının kimliğini ÖLÇÜLEBİLİR kılan sabit an (UTC).
_AN = dt.datetime(2026, 9, 28, 12, 0, tzinfo=dt.timezone.utc)
_BUGUN = "2026-09-28"


@pytest.fixture()
def gun(monkeypatch):
    """Saati sabitler. `_now` sahtelenmezse gün kimliği koşu tarihine bağlı
    olur ve test yarın kendiliğinden çöker."""
    monkeypatch.setattr(ps, "_now", lambda: _AN)
    return _AN


def _kod(depo, kod="KOD1", pid="p-1", **ek):
    veri = {"partnerId": pid, "active": True, "redemptionCount": 0}
    veri.update(ek)
    depo[f"partnerCodes/{kod}"] = veri


def _saat(monkeypatch, gun_metni: str):
    """Saati belirli bir güne kurar — geçmiş güne tıklama yazmanın tek yolu."""
    an = dt.datetime.fromisoformat(gun_metni + "T12:00:00+00:00")
    monkeypatch.setattr(ps, "_now", lambda: an)


# --- Yazım yolu ve kapılar ----------------------------------------------

def test_tiklama_dogru_GUN_dokumanina_yazilir(depo, gun):
    _kod(depo)
    # Küçük harf de kabul: link büyük/küçük yazılmış olabilir ve
    # `normalize_code` aynı kodu iki ayrı sayaca bölmemeli.
    assert ps.record_click("kod1") is True
    assert depo[f"partnerCodes/KOD1/clicks/{_BUGUN}"]["count"] == 1
    assert depo["partnerCodes/KOD1"]["clickCount"] == 1


def test_ayni_gun_ikinci_tiklama_sayaci_ARTIRIR(depo, gun):
    """`Increment` yolu: iki eşzamanlı tıklama birbirinin üstüne yazmaz."""
    _kod(depo)
    ps.record_click("KOD1")
    ps.record_click("KOD1")
    assert depo[f"partnerCodes/KOD1/clicks/{_BUGUN}"]["count"] == 2
    assert depo["partnerCodes/KOD1"]["clickCount"] == 2


def test_tiklama_kaydinda_KISISEL_VERI_yok(depo, gun):
    """Gizlilik çizgisinin bekçisi — sahibin pazarlıksız şartı.

    Gün dokümanında sayaçtan BAŞKA hiçbir alan olmamalı: IP, User-Agent,
    kimlik, çerez, zaman damgası bile yok. Bir gün "hangi ülkeden geldi"
    eklemek isteyen biri bu testi kırmak zorunda kalır — sessizce
    ekleyemez.
    """
    _kod(depo)
    ps.record_click("KOD1")
    assert set(depo[f"partnerCodes/KOD1/clicks/{_BUGUN}"]) == {"count"}


def test_var_olmayan_kod_HIC_YAZIM_uretmez(depo, gun):
    """Uç herkese açık: bu kapı olmadan uydurma kodlarla SINIRSIZ doküman
    yazdırılabilirdi (fatura + çöp veri)."""
    depo["_yazimlar"] = {}
    assert ps.record_click("YOKKOD") is False
    assert depo["_yazimlar"] == {}


@pytest.mark.parametrize("kod", ["", "AB", "K!1", "A" * 25, "  "])
def test_bicimsiz_kod_HIC_OKUMA_HIC_YAZIM_uretmez(depo, gun, kod):
    """Biçim kapısı en dışta: geçersiz kod bir OKUMAYA bile mal olmamalı."""
    depo["_yazimlar"] = {}
    depo["_okumalar"] = {}
    assert ps.record_click(kod) is False
    assert depo["_yazimlar"] == {}
    assert depo["_okumalar"] == {}


def test_firestore_patlarsa_tiklama_YUTULUR(depo, gun, monkeypatch):
    """Best-effort: telemetri ziyaretçinin mağazaya gitmesini engellemez."""
    _kod(depo)

    def _patlak():
        raise RuntimeError("firestore down")

    monkeypatch.setattr(depo["_client"], "batch", _patlak)
    assert ps.record_click("KOD1") is False      # fırlatmadı, False döndü


def test_kod_arada_silinirse_GUN_sayaci_da_yazilmaz(depo, gun, monkeypatch):
    """Atomiklik: iki sayaç AYNI toplu yazımda artıyor.

    Ayrı yazımlar olsaydı, silinmiş bir kodun gün dokümanı yazılır ve
    sahibi olmayan bir alt koleksiyon kalırdı; `set(merge=True)` ile kod
    dokümanı da yalnız `clickCount` alanıyla yeniden DOĞARDI.
    """
    _kod(depo)
    gercek_batch = depo["_client"].batch

    def _sil_ve_ver():
        del depo["partnerCodes/KOD1"]            # okuma ile commit arasında
        return gercek_batch()

    monkeypatch.setattr(depo["_client"], "batch", _sil_ve_ver)
    assert ps.record_click("KOD1") is False
    assert "partnerCodes/KOD1" not in depo       # yeniden doğmadı
    assert f"partnerCodes/KOD1/clicks/{_BUGUN}" not in depo


def test_PASIF_kod_tiklamayi_YINE_sayar(depo, gun):
    """Bilinçli karar: kapatılmış kodun linki internette durmaya devam
    eder ve o trafik GERÇEKTEN olmuş bir olaydır. Kapalı kod yalnız
    `redeem`i düşürür."""
    _kod(depo, active=False)
    assert ps.record_click("KOD1") is True


# --- Toplama: seri, toplam, dönüşüm -------------------------------------

def test_seri_30_GUN_ve_eksik_gunler_SIFIR(depo, monkeypatch):
    """Seri hep 30 uzunlukta, delik YOK ve pencere DIŞI gün girmiyor.

    Ayrıca `clicks` (tüm zaman) ile `clicks30` (pencere) AYRI şeyler:
    ikisini karıştırmak, ocak ayındaki tıklamayı bu ayın performansı
    gibi göstermek olurdu.
    """
    _ortak(depo)
    _kod(depo)
    _saat(monkeypatch, "2026-01-01")
    ps.record_click("KOD1")                      # pencere DIŞI
    _saat(monkeypatch, "2026-09-20")
    for _ in range(2):
        ps.record_click("KOD1")
    _saat(monkeypatch, _BUGUN)
    for _ in range(5):
        ps.record_click("KOD1")

    detay = ps.partner_detail("p-1")
    seri = detay["clickSeries"]
    assert len(seri) == ps.CLICK_SERIES_DAYS
    assert seri[0]["day"] == "2026-08-30", "eskiden yeniye sıralı"
    assert seri[-1]["day"] == _BUGUN
    gunler = {g["day"]: g["count"] for g in seri}
    assert gunler[_BUGUN] == 5
    assert gunler["2026-09-20"] == 2
    assert gunler["2026-09-19"] == 0, "eksik gün 0 ile DOLU"
    assert detay["clicks30"] == 7
    assert detay["clicks"] == 8, "tüm zaman: pencere dışı tıklama da sayılır"


def test_seri_IKI_KODUN_ayni_gununu_toplar(depo, gun):
    """Seri ortak düzeyinde; kod başına toplam ayrı alanda."""
    _ortak(depo)
    _kod(depo, "KOD1")
    _kod(depo, "KOD2")
    ps.record_click("KOD1")
    ps.record_click("KOD2")
    ps.record_click("KOD2")

    detay = ps.partner_detail("p-1")
    assert detay["clickSeries"][-1]["count"] == 3
    assert detay["clicks"] == 3
    assert {k["code"]: k["clicks"] for k in detay["codes"]} == {"KOD1": 1,
                                                               "KOD2": 2}


def test_donusum_orani_tiklama_YOKKEN_None(depo, gun):
    """"%0 dönüşüm" ile "henüz ölçüm yok" AYNI ŞEY DEĞİL: ilkini göstermek
    ortağa tanıtımının başarısız olduğunu söyler — ölçülmemiş bir hüküm."""
    _ortak(depo)
    _kod(depo, redemptionCount=3)
    detay = ps.partner_detail("p-1")
    assert detay["clicks"] == 0
    assert detay["conversionRate"] is None


def test_donusum_orani_KURAN_bolu_tiklama(depo, gun):
    _ortak(depo)
    _kod(depo, redemptionCount=2)
    for _ in range(8):
        ps.record_click("KOD1")
    detay = ps.partner_detail("p-1")
    assert detay["referredUsers"] == 2
    assert detay["conversionRate"] == 0.25


def test_donusum_orani_1in_USTUNE_cikabilir(depo, gun):
    """Kırpılmıyor: Play linkini doğrudan paylaşan kurulum `redemptionCount`ı
    artırır, tıklamayı artırmaz. Kırpmak ölçüm boşluğunu gizlemek olurdu."""
    _ortak(depo)
    _kod(depo, redemptionCount=3)
    ps.record_click("KOD1")
    assert ps.partner_detail("p-1")["conversionRate"] == 3.0


def test_seri_okumasi_dusverse_pano_AYAKTA_ve_anahtar_DUSER(depo, gun,
                                                            monkeypatch):
    """Ortak bakiyesini bir telemetri okuması yüzünden kaybetmez. Anahtar
    0 ile DOLDURULMAZ: 0 "ölçtük, hiç yok" demek olurdu."""
    _ortak(depo)
    _kod(depo)

    def _patlak(*_a, **_k):
        raise RuntimeError("get_all down")

    monkeypatch.setattr(depo["_client"], "get_all", _patlak)
    detay = ps.partner_detail("p-1")
    assert "clickSeries" not in detay
    assert "clicks30" not in detay
    assert detay["balanceTry"] == 0.0          # panonun geri kalanı ayakta


# --- Para yolu tıklama okumaz -------------------------------------------

def test_PARA_yolu_tiklama_gunlerini_OKUMAZ(depo, gun):
    """`add_payout` bakiye için `partner_detail` çağırıyor; 30 gün
    dokümanı okumak orada katıksız israf. Emsal: aynı çağrıdaki
    `erisim=False` (Firebase Auth'a gitmeme) kararı."""
    _ortak(depo, uid="ortak-uid")
    _tetikle(depo)
    simdi = depo["partnerQualifications/u1"]["maturesAt"] + \
        dt.timedelta(seconds=1)
    ps.mature_qualifications(now=simdi)

    depo["_okumalar"] = {}
    ps.add_payout("p-1", 30.0, "TRY", "tam")
    assert [y for y in depo["_okumalar"] if "/clicks/" in y] == []


def test_bayrak_KAPALIYKEN_bedava_sayilar_DURUR(depo, gun):
    """Bayrağın kapsamı DAR ve bilinçli: yalnız gün dokümanı okumalarını
    kapatır. `clicks`/`conversionRate` elde olan kod dokümanlarından
    geliyor — bedava bir sayıyı gizlemenin gerekçesi olmazdı."""
    _ortak(depo)
    _kod(depo)
    ps.record_click("KOD1")
    dar = ps.partner_detail("p-1", tiklama_serisi=False)
    assert "clickSeries" not in dar
    assert "clicks30" not in dar
    assert dar["clicks"] == 1
    assert dar["codes"][0]["clicks"] == 1


# --- Ortağın dar görünümü -----------------------------------------------

def test_ortak_panosu_tiklamayi_GORUR(depo, gun):
    """Sahibin sorusunun cevabı: ortak kaç kişi gelmiş, kaçı kurmuş
    görebiliyor — ve hiçbiri kişisel veri değil (sadece sayı)."""
    _ortak(depo, uid="ortak-uid")
    _kod(depo, redemptionCount=1)
    ps.record_click("KOD1")

    gorunum = ps.partner_self_view("p-1")
    assert gorunum["clicks"] == 1
    assert gorunum["clicks30"] == 1
    assert len(gorunum["clickSeries"]) == ps.CLICK_SERIES_DAYS
    assert gorunum["conversionRate"] == 1.0
    assert gorunum["codes"][0]["clicks"] == 1
    # Dar görünüm hâlâ dar: işletme verisi sızmadı.
    assert "attributedGrossUsd" not in gorunum
    assert "uid" not in gorunum


def test_ortak_panosunda_seri_DUSERSE_anahtar_YOK(depo, gun, monkeypatch):
    """`tam.get(...)` ile kopyalamak `None` yazardı ve pano "ölçüldü, boş"
    ile "ölçülemedi"yi ayırt edemezdi."""
    _ortak(depo, uid="ortak-uid")
    _kod(depo)

    def _patlak(*_a, **_k):
        raise RuntimeError("get_all down")

    monkeypatch.setattr(depo["_client"], "get_all", _patlak)
    gorunum = ps.partner_self_view("p-1")
    assert "clickSeries" not in gorunum
    assert "clicks30" not in gorunum
    assert gorunum["clicks"] == 0               # bedava sayı yine var


# --- Uç: kimliksiz, her hâlde 204 ---------------------------------------

def _istemci():
    from fastapi.testclient import TestClient
    from main import app
    return TestClient(app)


def test_tiklama_ucu_204_ve_GOVDESIZ(depo, gun):
    _kod(depo)
    with _istemci() as istemci:
        yanit = istemci.post("/api/v1/partners/click", json={"code": "kod1"},
                             headers={"x-forwarded-for": "10.9.0.1"})
    assert yanit.status_code == 204
    assert yanit.content == b""
    assert depo[f"partnerCodes/KOD1/clicks/{_BUGUN}"]["count"] == 1


@pytest.mark.parametrize("tur", [
    # ⚠️ `navigator.sendBeacon(url, "…")` TAM BU içerik türünü gönderir ve
    # Pydantic modeli olsaydı FastAPI 422 dönerdi: sayaç sessizce ölür,
    # sayfa beacon yanıtını okumadığı için hiçbir yerde hata görünmez.
    "text/plain;charset=UTF-8",
    "application/json",
    None,                                       # başlıksız
])
def test_tiklama_ucu_her_ICERIK_TURUNDE_sayar(depo, gun, tur):
    _kod(depo)
    basliklar = {"x-forwarded-for": "10.9.0.2"}
    if tur:
        basliklar["content-type"] = tur
    with _istemci() as istemci:
        yanit = istemci.post("/api/v1/partners/click",
                             content='{"code":"KOD1"}', headers=basliklar)
    assert yanit.status_code == 204, tur
    assert depo[f"partnerCodes/KOD1/clicks/{_BUGUN}"]["count"] == 1, tur


@pytest.mark.parametrize("govde", ["", "bozuk-json", "[]", '{"code":123}',
                                   '{"code":"YOKKOD"}', '{"kod":"KOD1"}'])
def test_tiklama_ucu_BOZUK_istekte_de_204(depo, gun, govde):
    """Uç 4xx dönmez: ziyaretçinin konsoluna hata basmanın hiçbir faydası
    yok ve "kod yok" ile "kod bozuk" ayrımı kod tahmin etmeyi ucuzlatır."""
    _kod(depo)
    depo["_yazimlar"] = {}
    with _istemci() as istemci:
        yanit = istemci.post("/api/v1/partners/click", content=govde,
                             headers={"x-forwarded-for": "10.9.0.3"})
    assert yanit.status_code == 204, govde
    assert depo["_yazimlar"] == {}, govde


def test_tiklama_ucu_BUYUK_govdeyi_okumaz(depo, gun):
    """Kimliksiz uca megabaytlık gövde pompalamak ucuz olmamalı."""
    _kod(depo)
    depo["_yazimlar"] = {}
    with _istemci() as istemci:
        yanit = istemci.post(
            "/api/v1/partners/click",
            content='{"code":"KOD1","dolgu":"' + "x" * 2000 + '"}',
            headers={"x-forwarded-for": "10.9.0.4"})
    assert yanit.status_code == 204
    assert depo["_yazimlar"] == {}


def test_tiklama_kotasi_AYRI_kovada(depo, gun):
    """Kimliksiz uç → kota anahtarı IP. Türkiye'de mobil operatörler CGNAT
    kullanıyor: yüzlerce ziyaretçi TEK IP paylaşabilir. Genel kovada
    (dakikada 60) bir tanıtım tweet'i kendi ölçümünü kırpardı.

    İki yönü de ölçülüyor (`adm:` emsali): 61 tıklama geçiyor VE aynı
    IP'nin genel kotası hâlâ boş."""
    _kod(depo)
    basliklar = {"x-forwarded-for": "10.9.9.9"}
    with _istemci() as istemci:
        for sira in range(61):
            yanit = istemci.post("/api/v1/partners/click",
                                 json={"code": "KOD1"}, headers=basliklar)
            assert yanit.status_code == 204, sira
        # Aynı IP'den genel kovaya bir istek: tıklama seli onu YEMEDİ.
        genel = istemci.get("/api/v1/partners/me", headers=basliklar)
    assert genel.status_code != 429
    assert depo[f"partnerCodes/KOD1/clicks/{_BUGUN}"]["count"] == 61


# --- Sürüm kapısı: SESSİZ ÖLÜM TUZAĞI -----------------------------------

def test_tiklama_yolu_SURUM_KAPISINDAN_muaf(depo, gun, monkeypatch):
    """ÖLÇÜLEN TUZAK: çağıran tarayıcıdır ve `x-app-build` GÖNDERMEZ; K7
    gereği build 0 sayılır. Eşik > 0 açıldığı gün uç 426 dönmeye başlar ve
    sayaç SESSİZCE ölür — sayfa yanıtı okumaz, hiçbir ekranda hata
    görünmez, ortak "kimse tıklamıyor" sanır."""
    from core import app_gate, config

    _kod(depo)
    monkeypatch.setattr(config, "MIN_APP_BUILD", 999)
    app_gate.reset_memo()
    with _istemci() as istemci:
        yanit = istemci.post("/api/v1/partners/click", json={"code": "KOD1"},
                             headers={"x-forwarded-for": "10.9.0.5"})
        # POZİTİF KONTROL (test_app_gate emsali): kapı gerçekten AÇIK mı.
        # Olmasa iddia boşa düşer — kapı kapalıyken de 204 gelirdi.
        kontrol = istemci.get("/api/v1/astrology/olmayan-uc",
                              headers={"x-forwarded-for": "10.9.0.5"})
    assert yanit.status_code == 204
    assert kontrol.status_code == 426
    assert depo[f"partnerCodes/KOD1/clicks/{_BUGUN}"]["count"] == 1


def test_partners_me_de_surum_kapisindan_MUAF(monkeypatch):
    """`/partners/me` KAPININ DIŞINDA — bu test bir turu tersine çevirdi.

    Önceki hâli 426 bekliyordu ve gerekçesi "uygulamanın kendi ucu"ydu.
    ÖLÇÜLDÜ, yanlıştı: `grep -rn "partners/" apps/mobile/lib
    --include=*.dart` SIFIR sonuç veriyor; ucun tek çağıranı tarayıcı
    (`web/ortak/ortak.js`) ve tarayıcı `x-app-build` göndermiyor.

    Yani o test bir sessiz ölümü ÇİVİLİYORDU: eşik > 0 yazıldığı an
    ortak panosu 426 alır, `ortak.js` bunu ne 403 ne 5xx gördüğü için
    kalıcı hata bandına düşer ve ortağa olmayan bir uygulamayı
    güncellemesini söyler. Kapının amacı eski UYGULAMAYI kilitlemek.

    Kimlik kapısı (403) bekleniyor: sürüm kapısına HİÇ takılmamalı.
    """
    from core import app_gate, config

    monkeypatch.setattr(config, "MIN_APP_BUILD", 999)
    app_gate.reset_memo()
    with _istemci() as istemci:
        yanit = istemci.get("/api/v1/partners/me",
                            headers={"x-forwarded-for": "10.9.0.6"})
        # POZİTİF KONTROL: kapı gerçekten açık mı — olmasa iddia boşa düşer.
        kontrol = istemci.get("/api/v1/astrology/olmayan-uc",
                              headers={"x-forwarded-for": "10.9.0.6"})
    # 403: sürüm kapısı DEĞİL kimlik kapısı karşıladı — iddia bu.
    assert yanit.status_code == 403, yanit.text
    assert kontrol.status_code == 426


def test_partners_mature_surum_kapisindan_MUAF(monkeypatch):
    """Zamanlayıcı `x-app-build` GÖNDERMEZ — kapı arkasında kalsaydı
    gecelik olgunlaştırma her gece 426 alır ve ORTAKLARA PARA ÖDENMEZDİ.

    `infra/create-scheduler.ps1` (satır 178/186) işe yalnız `Authorization`
    başlığı veriyor; kardeş zamanlayıcı yolları (`/notify/run`,
    `/maintenance/`, `/admin/collect`) tam bu yüzden muaf. Bu yol bir tur
    boyunca unutulmuştu ve hata yalnız Cloud Scheduler günlüğünde
    görünürdü: panoda, panelde, hiçbir ekranda uyarı çıkmazdı.
    """
    from core import app_gate, config

    monkeypatch.setattr(config, "MIN_APP_BUILD", 999)
    app_gate.reset_memo()
    with _istemci() as istemci:
        yanit = istemci.post("/api/v1/partners/mature",
                             headers={"x-forwarded-for": "10.9.0.7"})
    # Sürüm kapısı DEĞİL, sırrın/kimliğin kapısı karşılamalı.
    assert yanit.status_code != 426, yanit.text


# --- Kimliksiz uç: tavanın GERÇEKTEN tavan olması -----------------------

def test_tiklama_kotasi_AUTHORIZATION_basligiyla_ATLATILAMAZ(depo, gun):
    """ÖLÇÜLEN DELİK: kota anahtarı `Authorization` özetine düşüyordu.

    Uçta kimlik kapısı YOK, yani başlık hiç doğrulanmaz: her isteğe farklı
    bir `Authorization` yazan istemci her istekte YENİ bir kova açıyordu ve
    aynı IP'den 700 istek tek bir 429 görmüyordu. Kimliksiz + YAZAN bir
    uçta bu, tavanın hiç olmaması demekti (Firestore yazımı = fatura).

    Sınırın hemen üstünde ölçülüyor: `CLICK_LIMIT_PER_MINUTE` kadar istek
    geçer, bir sonraki 429 alır — kova başlığa bakmadığı için.
    """
    from core.ratelimit import CLICK_LIMIT_PER_MINUTE

    _kod(depo)
    sinir = CLICK_LIMIT_PER_MINUTE
    with _istemci() as istemci:
        for sira in range(sinir):
            yanit = istemci.post(
                "/api/v1/partners/click", json={"code": "KOD1"},
                headers={"x-forwarded-for": "10.9.8.1",
                         "authorization": "Bearer sahte-%d" % sira})
            assert yanit.status_code == 204, sira
        tasan = istemci.post(
            "/api/v1/partners/click", json={"code": "KOD1"},
            headers={"x-forwarded-for": "10.9.8.1",
                     "authorization": "Bearer sahte-yeni"})
    assert tasan.status_code == 429
    # Kota kesilen istek YAZMADI: sayaç sınırda durdu.
    assert depo[f"partnerCodes/KOD1/clicks/{_BUGUN}"]["count"] == sinir


def test_tiklama_ucu_CHUNKED_govdeyi_de_KESER(depo, gun):
    """ÖLÇÜLEN DELİK: `Content-Length` YOKKEN başlık kapısı hiç çalışmıyor.

    `Transfer-Encoding: chunked` bir istekte `await request.body()` gövdenin
    TAMAMINI belleğe alıyordu; sınıra ancak sonra bakıldığı için 2 MB'lık
    bir gövde uca kadar gelip tamponlanıyordu (yazım engelleniyordu, bellek
    engellenmiyordu). Kimliksiz bir uçta bellek maliyetini istemcinin
    seçimine bırakmak, kotanın tavan olmasını boşa çıkarır.

    Burada UÇ davranışı ölçülüyor (204 + yazım yok); okunan bayt sayısı
    BURADAN ölçülemez, çünkü `TestClient`in taşıyıcısı akışı sunucuya
    vermeden önce kendi belleğinde topluyor — istemci tarafındaki bir sayaç
    httpx'i ölçer, ucu ölçmez (ölçüldü: delik kapatıldıktan SONRA da 2 MB
    sayıyordu). Kesmenin kendisi bir alttaki testte ölçülüyor.
    """
    _kod(depo)

    def _akis():
        yield b'{"code":"KOD1","dolgu":"'
        for _ in range(200):
            yield b"x" * 10000            # toplam ~2 MB
        yield b'"}'

    depo["_yazimlar"] = {}
    with _istemci() as istemci:
        yanit = istemci.post("/api/v1/partners/click", content=_akis(),
                             headers={"x-forwarded-for": "10.9.8.2"})
    assert yanit.status_code == 204
    assert depo["_yazimlar"] == {}, "sınırı aşan gövde yazdırmamalı"


def test_tiklama_govdesi_SINIRI_ASINCA_akisi_BIRAKIR():
    """Kesmenin kendisi: okuma sınırdan sonra DEVAM ETMEMELİ.

    Bu iddia ancak akış tüketicisinin yanında ölçülebilir (yukarıdaki
    notun gerekçesi). `await request.body()` ile aynı gövde sonuna kadar
    tamponlanıyordu; parça 10 KB ve sınır 1 KB olduğu için doğru davranış
    TEK parçadan sonra bırakmaktır.
    """
    import asyncio

    from api import partners as ap

    okunan = {"bayt": 0}

    class _SahteIstek:
        async def stream(self):
            for _ in range(200):
                okunan["bayt"] += 10000
                yield b"x" * 10000

    govde = asyncio.run(ap._tiklama_govdesi(_SahteIstek()))
    assert govde == b"", "sınırı aşan gövde çağırana VERİLMEZ"
    assert okunan["bayt"] == 10000, (
        "akış sınırdan sonra da tüketildi: %d bayt" % okunan["bayt"])


def test_kod_basina_tiklama_TAVANI_IP_sahtelemesini_bosa_cikarir(depo, gun):
    """Kota anahtarı XFF'e bağlı ve XFF çağıranın denetiminde.

    Ölçüldü: Google'ın yük dengeleyicisi istemcinin gönderdiği
    `x-forwarded-for`un SONUNA ekliyor, `_client_key` ise İLK öğeyi
    alıyor — yani her isteğe farklı bir XFF yazan istemci her istekte
    YENİ bir IP kovası açar ve dakikalık tavan hiç devreye girmez.
    Kimliksiz + YAZAN bir uçta bedeli fatura: istek başına 1 okuma + 2
    Firestore yazımı. Tavanın KODA bağlı olması bu yüzden şart.
    """
    from api import partners as partners_api

    _kod(depo)
    tavan = partners_api._KOD_TIKLAMA_TAVANI
    partners_api._kod_vurus.clear()
    with _istemci() as istemci:
        for i in range(tavan + 25):
            istemci.post("/api/v1/partners/click", json={"code": "KOD1"},
                         headers={"x-forwarded-for": f"10.1.{i // 250}.{i % 250}"})
    # Sahte IP her istekte değişti, ama sayaç tavanda durdu.
    assert depo[f"partnerCodes/KOD1/clicks/{_BUGUN}"]["count"] == tavan

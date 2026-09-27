"""Ortaklık ödülü (OP-turu) — zarar ve dolandırıcılık kapıları.

Her iddia gerçek para ödemesi üretebilecek bir yolu kapatıyor. Ödül
kuralının beş koşulu (PRODUCTION · doğru olay türü · parasal · deneme
değil · atıf var) tek tek sınanıyor, çünkü biri gevşerse kayıp sessizdir:
panel "hakediş" gösterir, sahip öder, yanlış olduğu ancak mutabakatta
anlaşılır.

Çalıştırma:
    .venv\\Scripts\\python.exe -m pytest tests/test_partner_rewards.py -q
"""
from __future__ import annotations

import datetime as dt

import pytest

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


class SahteDoc:
    def __init__(self, depo, yol):
        self._depo = depo
        self._yol = yol

    @property
    def id(self):
        return self._yol.rsplit("/", 1)[-1]

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
        mevcut.update(data)
        self._depo[self._yol] = mevcut

    def update(self, data):
        mevcut = dict(self._depo.get(self._yol) or {})
        mevcut.update(data)
        self._depo[self._yol] = mevcut

    def create(self, data):
        if self._yol in self._depo:
            raise RuntimeError("already-exists")
        self._depo[self._yol] = dict(data)

    def collection(self, ad):
        return SahteKoleksiyon(self._depo, f"{self._yol}/{ad}")


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


class SahteClient:
    def __init__(self, depo):
        self._depo = depo

    def collection(self, ad):
        return SahteKoleksiyon(self._depo, ad)

    def transaction(self):
        return SahteTransaction()


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

    def _dus(_partner_id):
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

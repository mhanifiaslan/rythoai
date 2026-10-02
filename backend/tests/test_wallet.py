"""Token cüzdanının değişmezleri (Revize R1).

Cüzdan PARA taşır; buradaki her test gerçek bir kayıp senaryosunu tutuyor:

* Yarış: iki eşzamanlı istek aynı bakiyeyi iki kez harcayamaz (transaction).
* Webhook yeniden denemesi aynı paketi iki kez yükleyemez (event-id defteri).
* Paket iadesi kullanıcının AYRI ödediği aboneliğini kapatamaz (ürün ayrımı).
* Sönmüş abonelikten kalan aylık hak harcanamaz; satın alınan bakiye yaşar.
"""
from __future__ import annotations

import datetime as dt

import pytest
from fastapi import HTTPException

from core import wallet


# ---------------------------------------------------------------------------
# Bellek içi sahte Firestore — transaction dahil
# ---------------------------------------------------------------------------

class SahteAnlik:
    def __init__(self, data):
        self._data = data

    @property
    def exists(self):
        return self._data is not None

    def to_dict(self):
        return dict(self._data) if self._data else {}


class SahteDoc:
    def __init__(self, depo: dict, yol: str):
        self._depo = depo
        self._yol = yol

    def get(self, transaction=None):
        return SahteAnlik(self._depo.get(self._yol))

    def set(self, data, merge=False):
        mevcut = dict(self._depo.get(self._yol) or {}) if merge else {}
        for k, v in data.items():
            if type(v).__name__ == "Increment":
                mevcut[k] = int(mevcut.get(k, 0)) + v.value
            else:
                mevcut[k] = v
        self._depo[self._yol] = mevcut

    def collection(self, ad):
        return SahteKoleksiyon(self._depo, f"{self._yol}/{ad}")


class SahteKoleksiyon:
    _oto_sayac = 0

    def __init__(self, depo: dict, yol: str):
        self._depo = depo
        self._yol = yol

    def document(self, ad=None):
        # Gerçek istemcide argümansız document() otomatik kimlik üretir —
        # debit defteri (AP-turu) bu yolu kullanıyor.
        if ad is None:
            SahteKoleksiyon._oto_sayac += 1
            ad = f"oto-{SahteKoleksiyon._oto_sayac}"
        return SahteDoc(self._depo, f"{self._yol}/{ad}")


class SahteTransaction:
    def set(self, ref, data):
        ref.set(data)


class SahteClient:
    def __init__(self, depo: dict):
        self._depo = depo

    def collection(self, ad):
        return SahteKoleksiyon(self._depo, ad)

    def transaction(self):
        return SahteTransaction()


@pytest.fixture()
def depo(monkeypatch):
    """Sahte Firestore + kapalı abonelik varsayılanı."""
    veriler: dict = {}
    client = SahteClient(veriler)
    monkeypatch.setattr(wallet.firestore_client, "get_client", lambda: client)
    # Gerçek `transactional` gerçek Transaction ister; sahtede kimliğe iner.
    monkeypatch.setattr("google.cloud.firestore.transactional", lambda f: f)
    # Modül üzerinden yamalanıyor: wallet entitlements'a DİNAMİK erişir
    # (kopyalanmış ad monkeypatch'i görmez — bir kez yaşandı).
    monkeypatch.setattr(wallet.entitlements, "get_subscription",
                        lambda uid: {"active": False})
    monkeypatch.setattr(wallet.entitlements, "is_subscriber",
                        lambda uid: False)
    monkeypatch.setattr(wallet, "TOKENS_ENFORCE", True)
    return veriler


def _cuzdan_yaz(depo, uid="u1", **alanlar):
    depo[f"users/{uid}/private/wallet"] = alanlar


def _cuzdan(depo, uid="u1"):
    return depo.get(f"users/{uid}/private/wallet", {})


def _defter(depo, uid="u1"):
    """Ledger kayıtları (yazım sırasıyla — sahte depo dict'i eklemeli)."""
    onek = f"users/{uid}/private/wallet/ledger/"
    return [v for k, v in depo.items() if k.startswith(onek)]


def _abone_yap(monkeypatch, expires: dt.datetime):
    monkeypatch.setattr(wallet.entitlements, "get_subscription",
                        lambda uid: {"active": True, "expiresAt": expires})
    monkeypatch.setattr(wallet.entitlements, "is_subscriber",
                        lambda uid: True)


_DONEM = dt.datetime(2026, 9, 1, tzinfo=dt.timezone.utc)


# ---------------------------------------------------------------------------
# Harcama sırası
# ---------------------------------------------------------------------------

def test_once_allowance_sonra_purchased(depo, monkeypatch):
    """Yanacak olan önce harcanır; parayla alınan bakiye korunur."""
    _abone_yap(monkeypatch, _DONEM)
    _cuzdan_yaz(depo, allowance=3, allowanceExpiresAt=_DONEM, purchased=10)

    wallet.spend("u1", "natal")  # bedel 5: 3 allowance + 2 purchased

    assert _cuzdan(depo)["allowance"] == 0
    assert _cuzdan(depo)["purchased"] == 8


def test_yetersiz_bakiye_402_ve_baslik(depo, monkeypatch):
    """402'nin yanında X-Paywall-Reason: tokens — istemci paywall yerine
    token mağazasını bu başlıkla seçiyor (detail düz kullanıcı metni)."""
    _abone_yap(monkeypatch, _DONEM)
    _cuzdan_yaz(depo, allowance=1, allowanceExpiresAt=_DONEM, purchased=1)

    with pytest.raises(HTTPException) as exc:
        wallet.spend("u1", "natal")  # bedel 5 > 2

    assert exc.value.status_code == 402
    assert exc.value.headers["X-Paywall-Reason"] == "tokens"
    # Reddedilen istek bakiyeyi DEĞİŞTİRMEZ.
    assert _cuzdan(depo)["allowance"] == 1
    assert _cuzdan(depo)["purchased"] == 1


def test_kuru_calisma_reddetmez(depo, monkeypatch):
    """TOKENS_ENFORCE=0: eski mobil sürümler yayılana kadar üretim bu kipte."""
    monkeypatch.setattr(wallet, "TOKENS_ENFORCE", False)
    _abone_yap(monkeypatch, _DONEM)
    _cuzdan_yaz(depo, allowance=0, allowanceExpiresAt=_DONEM, purchased=0)

    wallet.spend("u1", "natal")  # fırlatmamalı


def test_firestore_yokken_istek_dusmez(monkeypatch):
    """Fail-open: altyapı sorunu kullanıcının suçu değil."""
    monkeypatch.setattr(wallet.firestore_client, "get_client", lambda: None)
    wallet.spend("u1", "chat")  # fırlatmamalı


# ---------------------------------------------------------------------------
# Dönem tazeleme
# ---------------------------------------------------------------------------

def test_tembel_tazeleme_yeni_donemde_hak_verir(depo, monkeypatch):
    """Webhook RENEWAL'i kaçırsa bile kullanıcı yeni dönemde hakkını alır."""
    eski_donem = dt.datetime(2026, 8, 1, tzinfo=dt.timezone.utc)
    _abone_yap(monkeypatch, _DONEM)
    _cuzdan_yaz(depo, allowance=0, allowanceExpiresAt=eski_donem, purchased=0)

    wallet.spend("u1", "chat")  # bedel 1, tazelenen haktan düşer

    assert _cuzdan(depo)["allowance"] == wallet.MONTHLY_TOKEN_ALLOWANCE - 1


def test_K1_yeni_donemde_aylik_hak_YUZ(depo, monkeypatch):
    """K1: aylık hak 300 → 100. Sayı burada LİTERAL pinli, sabite göre
    DEĞİL — yukarıdaki test sabitle hesapladığı için sabit 7'ye düşse de
    yeşil kalır ve "hak değişti" sessizce geçerdi. 100 bir ekonomi kararıdır
    (bkz. wallet.MONTHLY_TOKEN_ALLOWANCE gerekçesi): hak 210 jeton/ay
    ölçülen kullanım hızının ALTINA çekilsin ki paket satışı doğsun.
    """
    eski_donem = dt.datetime(2026, 8, 1, tzinfo=dt.timezone.utc)
    _abone_yap(monkeypatch, _DONEM)
    _cuzdan_yaz(depo, allowance=0, allowanceExpiresAt=eski_donem, purchased=0)

    wallet.spend("u1", "chat")

    assert _cuzdan(depo)["allowance"] == 99
    assert wallet.get_wallet("u1")["monthly_allowance"] == 100


def test_K3_mevcut_donemde_eski_hak_GERI_ALINMAZ(depo, monkeypatch):
    """K3: hak değişimi BİR SONRAKİ dönemden; elindeki hak geri alınmaz.

    En sessiz kırılma noktası burası: `_spend_txn` içindeki TEMBEL TAZELEME
    dönem ortasında da koşuyor ve `allowance = MONTHLY_TOKEN_ALLOWANCE`
    yazıyor. Koşulsuz olsaydı eski dönemde 300 hak almış hesap, 300'üncü
    jetonunu harcamaya çalıştığı anda bakiyesini 100'e DÜŞÜRÜLMÜŞ bulurdu —
    kapalı testte gerçek alım yapmış hesaplar var (sahibinki dahil) ve
    "jetonlarım gitti" şikâyeti tam buradan doğar. Kapı: tazeleme yalnız
    dönem işareti İLERİ gittiğinde yazar, aynı dönemde bir daha tetiklenmez.
    """
    _abone_yap(monkeypatch, _DONEM)  # abonelik dönemi: cüzdandaki işaretle AYNI
    _cuzdan_yaz(depo, allowance=300, allowanceExpiresAt=_DONEM, purchased=0)

    wallet.spend("u1", "chat")  # bedel 1

    assert _cuzdan(depo)["allowance"] == 299, "yeni tavan eski hakkı yemiş"
    assert _cuzdan(depo)["allowanceExpiresAt"] == _DONEM

    # Görünüm de kırpmıyor: kullanıcının GERÇEK hakkı 299, tavan 100 —
    # ikisi bir dönem boyunca tutarsız görünür ve bu doğrudur.
    gorunum = wallet.get_wallet("u1")
    assert gorunum["allowance"] == 299
    assert gorunum["monthly_allowance"] == 100


# --- K3'ün gerçek kırılma yolu: işaret dönem ORTASINDA ileri gidebiliyor ----
#
# Yukarıdaki test işaretin EŞİT olduğu hâli ölçüyor ve o hâlde tembel tazeleme
# hiç koşmuyor — yani kapıyı değil kapının kapalı olduğu bir ânı ölçüyor.
# Aşağıdaki üç test, tazelemenin GERÇEKTEN koştuğu yolu çağırır. Sebebi
# ölçüldü: `_ACTIVATING_EVENTS` yalnız dönem başlarında gelmiyor
# (SUBSCRIPTION_EXTENDED, UNCANCELLATION, PRODUCT_CHANGE dönem ortasında
# düşebiliyor) ve `api/billing.py` son kullanma taşımayan olayda işareti
# "şimdi + 35 gün" yapıyor — bu, aylık bir dönemin işaretinden HER ZAMAN
# ileridir. 300 → 100 inişinden ÖNCE bu yol zararsızdı (300'ü yine 300
# yapıyordu); tavan düştüğü an KAYIP üretir.

_ILERI = _DONEM + dt.timedelta(days=20)


def test_K3_webhook_donem_ORTASINDA_isareti_ileri_atarsa_hak_KORUNUR(depo):
    """`reset_allowance` webhook'un BİRİNCİL yolu ve hakkı azaltamaz.

    Düz atama (`"allowance": MONTHLY_TOKEN_ALLOWANCE`) burada 287 hakkı olan
    kullanıcıyı 100'e indiriyordu. Mutasyon kontrolü: `max(...)` yerine düz
    atama yazılırsa bu test KIRMIZI olmak zorunda.
    """
    _cuzdan_yaz(depo, allowance=287, allowanceExpiresAt=_DONEM, purchased=1000)

    wallet.reset_allowance("u1", _ILERI)  # EXTENDED: dönem ortasında, ileri

    assert _cuzdan(depo)["allowance"] == 287, "tazeleme hakkı AZALTTI (K3 ihlali)"
    assert _cuzdan(depo)["allowanceExpiresAt"] == _ILERI, "işaret taşınmadı"
    assert _cuzdan(depo)["purchased"] == 1000, "parayla alınan bakiye bozuldu"


def test_K3_tazeleme_hakki_tavana_kadar_YUKARI_ceker(depo):
    """Aynı kapı gerçek dönem dönüşünde hâlâ çalışmak zorunda.

    `max` korumasının bedeli "tazeleme hiç çalışmıyor" OLMAMALI: elinde
    tavanın ALTINDA hak kalan kullanıcı yeni dönemde tam hakkını alır.
    Bu test, korumanın kapıyı tümden kapatmadığını sabitler.
    """
    _cuzdan_yaz(depo, allowance=12, allowanceExpiresAt=_DONEM, purchased=0)

    wallet.reset_allowance("u1", _ILERI)

    assert _cuzdan(depo)["allowance"] == wallet.MONTHLY_TOKEN_ALLOWANCE


def test_K3_harcama_yolunda_isaret_ileri_giderse_hak_KORUNUR(depo, monkeypatch):
    """Yazan ikinci yol: `_spend_txn` içindeki tembel tazeleme.

    Webhook'un reseti düşmüşse (istisna yutuluyor) kayıp buradan da girebilir:
    abonelik kaydı ileri tarihliyken cüzdan işareti geride kalır, tazeleme
    koşar ve düz atama olsaydı 287 → 100 yazılırdı. Harcama o yazımı KALICI
    yapar, yani en pahalı kırılma noktası burasıdır.
    """
    _abone_yap(monkeypatch, _ILERI)  # abonelik dönemi İLERİ
    _cuzdan_yaz(depo, allowance=287, allowanceExpiresAt=_DONEM, purchased=0)

    wallet.spend("u1", "chat")  # bedel 1

    assert _cuzdan(depo)["allowance"] == 286, "tembel tazeleme hakkı yedi"
    assert _cuzdan(depo)["allowanceExpiresAt"] == _ILERI


def test_K2_son_kullanma_YOKSA_hak_verilir_isaret_UYDURULMAZ(depo):
    """Son kullanma taşımayan aktive eden olay: hak verilir, işaret DURUR.

    İşaretin uydurulması (eski hâl: "şimdi + 35 gün") bir sonraki GERÇEK
    yenilemeyi yutuyordu — aşağıdaki test onu ayrıca ölçüyor.
    """
    _cuzdan_yaz(depo, allowance=0, purchased=0)

    wallet.reset_allowance("u1", None)

    assert _cuzdan(depo)["allowance"] == wallet.MONTHLY_TOKEN_ALLOWANCE
    assert "allowanceExpiresAt" not in _cuzdan(depo), "işaret uyduruldu"


def test_K2_son_kullanmasiz_olay_hakki_IKINCI_KEZ_vermez(depo):
    """İşaret taşınmadığı için idempotency ayrı bir bayrakla kurulu.

    Aksi hâlde tekrarlanan bir UNCANCELLATION, harcanmış hakkı her seferinde
    100'e geri doldurur — bedava hak musluğu. Bayrak olmadan bu dal tarihten
    "bu dönemde verdim mi" sorusunu CEVAPLAYAMAZ.
    """
    _cuzdan_yaz(depo, allowance=0, purchased=0)

    wallet.reset_allowance("u1", None)
    assert _cuzdan(depo)["allowance"] == wallet.MONTHLY_TOKEN_ALLOWANCE
    assert _cuzdan(depo)["allowanceGrantedWithoutExpiry"] is True

    _cuzdan_yaz(depo, **{**_cuzdan(depo), "allowance": 40})  # harcandı
    wallet.reset_allowance("u1", None)  # olay TEKRARLANDI

    assert _cuzdan(depo)["allowance"] == 40, "hak ikinci kez verildi"


def test_K2_gercek_son_kullanma_bayragi_TEMIZLER(depo):
    """Bayrak kalıcı olsaydı bir sonraki son kullanmasız olay yutulurdu.

    Yani bayrağı silmemek, onu koymanın kendisi kadar önemli: aksi hâlde
    kullanıcı ileride gerçekten hak alması gereken bir aktivasyonda hiçbir
    şey almaz. Bu test o temizliği çiviliyor.
    """
    _cuzdan_yaz(depo, allowance=0, purchased=0)
    wallet.reset_allowance("u1", None)
    assert _cuzdan(depo)["allowanceGrantedWithoutExpiry"] is True

    wallet.reset_allowance("u1", _DONEM)  # gerçek son kullanma

    assert _cuzdan(depo)["allowanceGrantedWithoutExpiry"] is False


def test_K2_uydurulmayan_isaret_sonraki_YENILEMEYI_YUTMAZ(depo):
    """Bu turun asıl kusuru: uydurma işaret bir dönemin hakkını yiyordu.

    Senaryo ölçülebilir: son kullanmasız olay gelir (hak verilir), ÜÇ GÜN
    sonra gerçek yenileme düşer ve son kullanması BİR AY sonrasıdır. Eski
    hâlde işaret "şimdi + 35 gün"dü, yani yenilemenin tarihi (bir ay) ondan
    GERİDE kalıyor, `_ts(expires_at) <= _ts(marker)` kapısı düşüyor ve hak
    HİÇ tazelenmiyordu. İşaret uydurulmadığı için artık tazeleniyor.
    """
    _cuzdan_yaz(depo, allowance=0, purchased=0)
    wallet.reset_allowance("u1", None)          # son kullanmasız aktivasyon
    _cuzdan_yaz(depo, **{**_cuzdan(depo), "allowance": 3})  # harcandı

    gercek_donem_sonu = _DONEM + dt.timedelta(days=30)
    wallet.reset_allowance("u1", gercek_donem_sonu)

    assert _cuzdan(depo)["allowance"] == wallet.MONTHLY_TOKEN_ALLOWANCE, \
        "gerçek yenileme yutuldu: kullanıcı o dönemin hakkını almadı"
    assert _cuzdan(depo)["allowanceExpiresAt"] == gercek_donem_sonu


def test_K3_deneme_kullanicisi_hak_dususunden_ETKILENMEZ(depo, monkeypatch):
    """SUNUCU TARAFI kartsız deneme (OT6) hakkın değil `purchased` kovasının
    müşterisi.

    O yolda abonelik KAYDI yoktur, yani `get_wallet`/`_spend_txn` hakkı
    0'a sabitler ve 30'luk karşılama jetonu `purchased`a yazılır. 300 → 100
    inişinin bu denemeye dokunacak bir yolu yok; bu test o ayrımı sabitliyor
    ki ileride "hak düştü, deneme de orantılı düşsün" diye sessizce
    bağlanmasın. TRIAL_TOKENS literal pinli (30 ≈ $0,06 tavan maliyet).

    ⚠️ Kapsam bilinçli olarak DAR: "deneme = aylık hak 0" GENEL bir doğru
    DEĞİL. Mağaza denemesi (RevenueCat `period_type=TRIAL`) başka bir yol —
    `TRIAL_STARTED` `api/billing.py::_ACTIVATING_EVENTS` içinde olduğu için
    aktif abonelik kaydı yazılır ve `reset_allowance` çağrılır, yani o
    kullanıcı tam hakkı alır. Bu test onu kapsamıyor; burada `in_trial`
    yamalanıp abonelik kaydı KASITLI olarak yaratılmıyor.
    """
    assert wallet.TRIAL_TOKENS == 30
    monkeypatch.setattr(wallet.entitlements, "in_trial", lambda uid: True,
                        raising=False)

    wallet.ensure_trial_tokens("u1")
    assert _cuzdan(depo)["purchased"] == 30

    wallet.spend("u1", "natal")  # bedel 5 — hak 0 olduğu için tamamı paketten

    assert _cuzdan(depo)["allowance"] == 0
    assert _cuzdan(depo)["purchased"] == 25

    gorunum = wallet.get_wallet("u1")
    assert gorunum["allowance"] == 0, "denemeye aylık hak yazılmış"
    assert gorunum["purchased"] == 25


def test_sonmus_abonelikte_allowance_harcanamaz(depo, monkeypatch):
    """Dönem yoksa hak da yok; yalnızca satın alınan bakiye geçerli."""
    _cuzdan_yaz(depo, allowance=50, allowanceExpiresAt=_DONEM, purchased=3)

    wallet.spend("u1", "chat")  # abone DEĞİL: 1 token purchased'dan düşmeli

    assert _cuzdan(depo)["allowance"] == 0
    assert _cuzdan(depo)["purchased"] == 2


def test_reset_allowance_idempotent(depo, monkeypatch):
    """Aynı dönemin tekrarlanan webhook'u hakkı iki kez veremez.

    "Kısmen harcanmış" değer 40; eskiden 100 yazılıyordu ve K1'den sonra
    (hak 300 → 100) o sayı TAVANIN KENDİSİ oldu: test tazeleme gerçekten
    koşsa da 100 görür ve YEŞİL kalırdı. Değer tavandan farklı OLMAK
    ZORUNDA, yoksa bu test hiçbir şey ölçmez.
    """
    wallet.reset_allowance("u1", _DONEM)
    assert _cuzdan(depo)["allowance"] == wallet.MONTHLY_TOKEN_ALLOWANCE
    _cuzdan_yaz(depo, **{**_cuzdan(depo), "allowance": 40})  # kısmen harcandı
    wallet.reset_allowance("u1", _DONEM)  # AYNI dönem tekrar

    assert _cuzdan(depo)["allowance"] == 40  # tazelenmedi


# ---------------------------------------------------------------------------
# Kredi ve iade
# ---------------------------------------------------------------------------

def test_kredi_idempotent(depo):
    """Webhook yeniden denemesi paketi iki kez yükleyemez."""
    wallet.credit_pack("u1", "rytho_tokens_small", "evt-1")
    wallet.credit_pack("u1", "rytho_tokens_small", "evt-1")

    assert _cuzdan(depo)["purchased"] == 100  # 200 değil


def test_farkli_olaylar_ayri_yuklenir(depo):
    """Aynı paketi gerçekten iki kez almak iki kez yükler."""
    wallet.credit_pack("u1", "rytho_tokens_small", "evt-1")
    wallet.credit_pack("u1", "rytho_tokens_small", "evt-2")

    assert _cuzdan(depo)["purchased"] == 200


def test_iade_sifirda_kelepcelenir(depo):
    """Bakiye harcanmışsa iade eksiye düşürmez — borç defteri tutmayız."""
    wallet.credit_pack("u1", "rytho_tokens_small", "evt-1")
    _cuzdan_yaz(depo, **{**_cuzdan(depo), "purchased": 30})  # 70'i harcandı

    wallet.debit_refund("u1", "rytho_tokens_small", "evt-1")

    assert _cuzdan(depo)["purchased"] == 0


def test_taninmayan_urun_kredi_yuklemez(depo):
    assert wallet.credit_pack("u1", "bilinmeyen_urun", "evt-9") is False
    assert _cuzdan(depo) == {}


def test_llm_iadesi_purchased_a_gider(depo, monkeypatch):
    """İade purchased'a yazılır: devrettiği için asla yanmaz — kullanıcı
    lehine yanılmak doğru."""
    _cuzdan_yaz(depo, allowance=0, allowanceExpiresAt=None, purchased=0)
    wallet.refund_spend("u1", "natal")
    assert _cuzdan(depo)["purchased"] == 5


# ---------------------------------------------------------------------------
# Harcama defteri (AP-turu) — debit kayıtları bakiye mutasyonunu aynalar
# ---------------------------------------------------------------------------
# Not: sahte `transactional → kimlik` indirgemesi (fixture) gerçek retry
# semantiğini göremez; çift-yazım güvencesi gerçek kütüphanenin transaction
# TAMPONUNDAN gelir (yazımlar yalnız başarılı commit'te işlenir ve her
# retry gövdeyi — ledger_ref dahil — sıfırdan kurar).

def test_harcama_defterde_kirilimla_izlenir(depo, monkeypatch):
    """Debit kaydı: feature + tutar + allowance/purchased kırılımı."""
    _abone_yap(monkeypatch, _DONEM)
    _cuzdan_yaz(depo, allowance=2, allowanceExpiresAt=_DONEM, purchased=3)

    wallet.spend("u1", "dyad")  # bedel 3: 2 allowance + 1 purchased

    kayitlar = _defter(depo)
    assert len(kayitlar) == 1
    kayit = kayitlar[0]
    assert kayit["type"] == "debit"
    assert kayit["feature"] == "dyad"
    assert kayit["amount"] == 3
    assert kayit["allowancePart"] == 2
    assert kayit["purchasedPart"] == 1


def test_kuru_calismada_da_debit_yazilir(depo, monkeypatch):
    """ENFORCE=0'da YETERLİ bakiye DÜŞÜYOR (kod gerçeği) — defter bakiye
    mutasyonunu aynalar, bayraktan bağımsız."""
    monkeypatch.setattr(wallet, "TOKENS_ENFORCE", False)
    _abone_yap(monkeypatch, _DONEM)
    _cuzdan_yaz(depo, allowance=10, allowanceExpiresAt=_DONEM, purchased=0)

    wallet.spend("u1", "chat")

    assert _cuzdan(depo)["allowance"] == 9
    assert [k["type"] for k in _defter(depo)] == ["debit"]


def test_yetersiz_bakiyede_defter_bos_kalir(depo, monkeypatch):
    """Bakiye yetmeyip yazım olmayan yol (kuru çalışmada bile) hiçbir
    ledger kaydı üretmez — düşmeyen jetonun izi olmaz."""
    monkeypatch.setattr(wallet, "TOKENS_ENFORCE", False)
    _abone_yap(monkeypatch, _DONEM)
    _cuzdan_yaz(depo, allowance=1, allowanceExpiresAt=_DONEM, purchased=0)

    wallet.spend("u1", "natal")  # bedel 5 > 1; ENFORCE=0 → fırlatmaz

    assert _cuzdan(depo)["allowance"] == 1
    assert _defter(depo) == []


def test_llm_iadesi_deftere_yazilir(depo):
    wallet.refund_spend("u1", "natal")
    kayitlar = _defter(depo)
    assert len(kayitlar) == 1
    assert kayitlar[0]["type"] == "spend_refund"
    assert kayitlar[0]["feature"] == "natal"
    assert kayitlar[0]["amount"] == 5


def test_admin_kredisi_defter_ve_bakiye(depo):
    """credit_admin: purchased artar; kayıt gerekçe + adminUid taşır.
    Bilinçli olarak İDEMPOTENT DEĞİL — çift tıklama koruması panelde."""
    wallet.credit_admin("u1", 50, "paket gelmedi, telafi", "admin-1")
    wallet.credit_admin("u1", 50, "paket gelmedi, telafi", "admin-1")

    assert _cuzdan(depo)["purchased"] == 100  # iki ayrı olay
    kayitlar = [k for k in _defter(depo) if k["type"] == "admin"]
    assert len(kayitlar) == 2
    assert kayitlar[0]["reason"] == "paket gelmedi, telafi"
    assert kayitlar[0]["adminUid"] == "admin-1"


def test_admin_kredisi_pozitif_sart(depo):
    assert wallet.credit_admin("u1", 0, "sebep", "admin-1") is False
    assert wallet.credit_admin("u1", -5, "sebep", "admin-1") is False
    assert _cuzdan(depo) == {}


# ---------------------------------------------------------------------------
# Birleşik kapı (sohbet / iching)
# ---------------------------------------------------------------------------

class _Kullanici:
    uid = "u1"


def test_ucretsiz_gunluk_hak_token_dusurmez(depo, monkeypatch):
    monkeypatch.setattr("core.entitlements.consume_quota",
                        lambda uid, key, limit: True)
    harcandi = wallet.charge_metered(_Kullanici(), "chat", 5)
    assert harcandi is False
    assert _cuzdan(depo) == {}


def test_deneme_kullanicisi_gunluk_hakkini_KORUR(depo, monkeypatch):
    """KT2: in_trial 'abone' sayılıyordu ve consume_quota hiç
    çağrılmıyordu — deneme kullanıcısı günde 5 ücretsiz sohbetini
    kaybedip 30 jetonu sohbete yakıyordu. Ayrım artık GERÇEK mağaza
    aboneliği: denemede önce günlük hak, jeton rapor gibi işlere kalır."""
    # in_trial=True senaryosu: is_subscriber True olurdu ama abonelik yok.
    monkeypatch.setattr(wallet.entitlements, "is_subscriber",
                        lambda uid: True)
    kota = {"n": 0}
    monkeypatch.setattr("core.entitlements.consume_quota",
                        lambda uid, key, limit: kota.__setitem__(
                            "n", kota["n"] + 1) or True)
    _cuzdan_yaz(depo, allowance=0, allowanceExpiresAt=None, purchased=30)

    harcandi = wallet.charge_metered(_Kullanici(), "chat", 5)

    assert harcandi is False          # ücretsiz haktan geçti
    assert kota["n"] == 1             # kota GERÇEKTEN soruldu
    assert _cuzdan(depo)["purchased"] == 30  # jetona dokunulmadı


def test_deneme_kota_bitince_jeton_devreye_girer(depo, monkeypatch):
    monkeypatch.setattr(wallet.entitlements, "is_subscriber",
                        lambda uid: True)
    monkeypatch.setattr("core.entitlements.consume_quota",
                        lambda uid, key, limit: False)
    _cuzdan_yaz(depo, allowance=0, allowanceExpiresAt=None, purchased=30)

    harcandi = wallet.charge_metered(_Kullanici(), "chat", 5)

    assert harcandi is True
    assert _cuzdan(depo)["purchased"] == 29


def test_gercek_abone_kotaya_ugramaz(depo, monkeypatch):
    """Mağaza abonesi eskisi gibi doğrudan cüzdandan harcar — aylık hak
    (MONTHLY_TOKEN_ALLOWANCE) bunun için var; günlük kota hiç sorgulanmaz."""
    _abone_yap(monkeypatch, _DONEM)
    monkeypatch.setattr(
        "core.entitlements.consume_quota",
        lambda uid, key, limit: (_ for _ in ()).throw(
            AssertionError("abonede kota sorgulanmamalı")))
    _cuzdan_yaz(depo, allowance=10, allowanceExpiresAt=_DONEM, purchased=0)

    assert wallet.charge_metered(_Kullanici(), "chat", 5) is True
    assert _cuzdan(depo)["allowance"] == 9


# ---------------------------------------------------------------------------
# Deneme jetonu tembel telafisi (KT2)
# ---------------------------------------------------------------------------

def test_tembel_telafi_eksik_jetonu_tamamlar(depo, monkeypatch):
    monkeypatch.setattr(wallet.entitlements, "in_trial", lambda uid: True,
                        raising=False)
    wallet.ensure_trial_tokens("u1")
    assert _cuzdan(depo)["purchased"] == wallet.TRIAL_TOKENS
    # İkinci çağrı defter kaydını görür, İKİNCİ KEZ yüklemez.
    wallet.ensure_trial_tokens("u1")
    assert _cuzdan(depo)["purchased"] == wallet.TRIAL_TOKENS


def test_tembel_telafi_deneme_disinda_calismaz(depo, monkeypatch):
    monkeypatch.setattr(wallet.entitlements, "in_trial", lambda uid: False,
                        raising=False)
    wallet.ensure_trial_tokens("u1")
    assert _cuzdan(depo) == {}


def test_kota_bitince_paket_kurtarir(depo, monkeypatch):
    """Paket almak için abonelik ŞART DEĞİL — bilinçli ürün kararı."""
    monkeypatch.setattr("core.entitlements.consume_quota",
                        lambda uid, key, limit: False)
    _cuzdan_yaz(depo, allowance=0, allowanceExpiresAt=None, purchased=2)

    harcandi = wallet.charge_metered(_Kullanici(), "chat", 5)

    assert harcandi is True
    assert _cuzdan(depo)["purchased"] == 1


def test_kota_ve_paket_yoksa_402(depo, monkeypatch):
    monkeypatch.setattr("core.entitlements.consume_quota",
                        lambda uid, key, limit: False)

    with pytest.raises(HTTPException) as exc:
        wallet.charge_metered(_Kullanici(), "chat", 5)

    assert exc.value.status_code == 402


def test_onbellekli_kapi_pesin_harcamaz(depo, monkeypatch):
    """`metered_callbacks` hemen harcamaz; geri çağrı önbellek kaçırılınca
    çalışır — abone, aynı çekilişe ikinci bakışında ödemesin."""
    _abone_yap(monkeypatch, _DONEM)
    _cuzdan_yaz(depo, allowance=10, allowanceExpiresAt=_DONEM, purchased=0)

    spend_cb, refund_cb = wallet.metered_callbacks(_Kullanici(), "iching", 1)

    assert _cuzdan(depo)["allowance"] == 10  # henüz dokunulmadı
    spend_cb()
    assert _cuzdan(depo)["allowance"] == 8  # iching bedeli 2
    refund_cb()
    assert _cuzdan(depo)["purchased"] == 2  # iade purchased'a


# ---------------------------------------------------------------------------
# Kimlik devri (TRANSFER)
#
# Devir PARA taşır: aynı Play hesabıyla farklı Firebase hesapları arasında
# geçiş sıradan bir davranıştır ve TRANSFER'i tetikler. Buradaki testler
# `transfer_wallet`'ın GERÇEK gövdesini koşar (monkeypatch YOK) ve sahte depo
# TAM YOLLA anahtarlanır — kümenin en pahalı satırı olan oku-topla-yaz tam
# burada ölçülüyor.
# ---------------------------------------------------------------------------

def test_devir_IKI_kaynagi_da_toplar(depo):
    """RevenueCat'in `transferred_from` alanı LİSTEDİR (anonim kimlik + eski
    uid birlikte gelebilir). Eski kod yalnız İLK var olan kaynağın cüzdanını
    alıyor ama HER kaynağı sıfırlıyordu: ölçüldü, a=100 + b=250 devrinde hedef
    100 aldı ve 250 kredi buharlaştı."""
    depo["users/a/private/wallet"] = {"allowance": 0, "purchased": 100}
    depo["users/b/private/wallet"] = {"allowance": 0, "purchased": 250}

    wallet.transfer_wallet(SahteClient(depo), ["a", "b"], ["yeni"])

    assert _cuzdan(depo, "yeni")["purchased"] == 350
    # Aynı bakiye iki kimlikte birden duramaz.
    assert _cuzdan(depo, "a")["purchased"] == 0
    assert _cuzdan(depo, "b")["purchased"] == 0


def test_devir_cok_kaynakta_ileri_donemli_hakki_secer(depo):
    """Çok kaynakta `allowance` de TOPLANMAZ: dönem sonunda yanacak iki hakkı
    toplamak uydurma bakiye üretirdi; ileri tarihli dönem kazanır."""
    ileri = dt.datetime(2026, 10, 1, tzinfo=dt.timezone.utc)
    depo["users/a/private/wallet"] = {
        "allowance": 40, "allowanceExpiresAt": _DONEM, "purchased": 0}
    depo["users/b/private/wallet"] = {
        "allowance": 250, "allowanceExpiresAt": ileri, "purchased": 0}

    wallet.transfer_wallet(SahteClient(depo), ["a", "b"], ["yeni"])

    hedef = _cuzdan(depo, "yeni")
    assert hedef["allowance"] == 250
    assert hedef["allowanceExpiresAt"] == ileri


def test_devir_hedefin_bakiyesini_TOPLAR(depo):
    """`merge=True` ALAN düzeyinde birleştirir, yani eski yazım hedefin
    `purchased` alanını EZİYORDU — hedefte 300, kaynakta 100 varken hedef
    100'e düşüyor ve 300 kredi yok oluyordu."""
    depo["users/eski/private/wallet"] = {"allowance": 0, "purchased": 100}
    depo["users/yeni/private/wallet"] = {"allowance": 0, "purchased": 300}

    wallet.transfer_wallet(SahteClient(depo), ["eski"], ["yeni"])

    assert _cuzdan(depo, "yeni")["purchased"] == 400
    assert _cuzdan(depo, "eski")["purchased"] == 0


def test_devir_geride_kalmis_doneme_dokunmaz(depo):
    """Kaynağın dönemi geride kalmışsa hedefin kalan hakkı korunur."""
    geri = dt.datetime(2026, 8, 1, tzinfo=dt.timezone.utc)
    depo["users/eski/private/wallet"] = {
        "allowance": 250, "allowanceExpiresAt": geri, "purchased": 0}
    depo["users/yeni/private/wallet"] = {
        "allowance": 10, "allowanceExpiresAt": _DONEM, "purchased": 0}

    wallet.transfer_wallet(SahteClient(depo), ["eski"], ["yeni"])

    assert _cuzdan(depo, "yeni")["allowance"] == 10


def test_devir_webhook_tekrarinda_bakiyeyi_BOZMAZ(depo):
    """TRANSFER olayının olay kimliğiyle tekrar koruması YOK: RevenueCat aynı
    olayı ikinci kez gönderdiğinde ne `purchased` çift kredi üretmeli ne de
    `allowance` ikinci kez yazılmalı. Kaynak ilk geçişte sıfırlandığı için
    toplama 0 ekler; dönem işareti eşitlendiği için hak tekrar geçmez."""
    ileri = dt.datetime(2026, 10, 1, tzinfo=dt.timezone.utc)
    depo["users/eski/private/wallet"] = {
        "allowance": 250, "allowanceExpiresAt": ileri, "purchased": 100}
    depo["users/yeni/private/wallet"] = {"allowance": 0, "purchased": 300}
    client = SahteClient(depo)

    wallet.transfer_wallet(client, ["eski"], ["yeni"])
    wallet.transfer_wallet(client, ["eski"], ["yeni"])

    hedef = _cuzdan(depo, "yeni")
    assert hedef["purchased"] == 400
    assert hedef["allowance"] == 250
    assert hedef["allowanceExpiresAt"] == ileri


def test_devir_cuzdansiz_kaynak_hedefi_SIFIRLAMAZ(depo):
    """Cüzdanı olmayan bir kimlikten devir, hedefin bakiyesine dokunamaz."""
    depo["users/yeni/private/wallet"] = {"allowance": 0, "purchased": 300}

    wallet.transfer_wallet(SahteClient(depo), ["hic-yok"], ["yeni"])

    assert _cuzdan(depo, "yeni")["purchased"] == 300


def test_devir_olmayan_kaynakta_BOS_DOKUMAN_yaratmaz(depo):
    """Var olmayan cüzdanı sıfırlamak boş bir doküman yaratmaktan başka iş
    yapmaz; devir artık abonelik yazımından ÖNCE koştuğu için gereksiz
    doküman hiç üretilmemeli."""
    wallet.transfer_wallet(SahteClient(depo), ["hic-yok"], ["yeni"])

    assert "users/hic-yok/private/wallet" not in depo
    assert "users/yeni/private/wallet" not in depo


def test_devir_COK_HEDEFTE_krediyi_cogaltir(depo):
    """BİLİNÇLİ sınır, kaza değil: her hedef kaynakların TAM toplamını alır,
    yani kredi hedef sayısı kadar çoğalır. RevenueCat pratikte tek hedef
    gönderiyor; bu test kararı GÖRÜNÜR kılıyor — sessizce değişmesin."""
    depo["users/eski/private/wallet"] = {"allowance": 0, "purchased": 100}

    wallet.transfer_wallet(SahteClient(depo), ["eski"], ["a", "b"])

    assert _cuzdan(depo, "a")["purchased"] == 100
    assert _cuzdan(depo, "b")["purchased"] == 100


# ---------------------------------------------------------------------------
# "Jetonun iade edildi" CUMLESI dogru mu (gz-2, 2026-09-19)
# ---------------------------------------------------------------------------
#
# Yama bu vaadi kullanicinin EKRANINA koyuyor. Eskiden bayrak
# `refund is not None` idi, yani "geri cagri gecildi mi" sorusunu
# cevapliyordu; iade yazimi dusup `logger.warning` ile yutuldugunda ekranda
# YINE "iade edildi" yaziyordu ve bakiye eksik kaliyordu.


def test_iade_basarisizsa_refund_spend_FALSE_doner(monkeypatch):
    """Bakiye artisi yazilamadiysa "iade edildi" denemez."""
    from core import wallet as w

    class _Patlayan:
        def set(self, *a, **k):
            raise RuntimeError("Firestore dustu")

        def collection(self, _):
            raise AssertionError("bakiye yazilamadan deftere gidilmemeli")

    monkeypatch.setattr(w, "_wallet_ref", lambda uid: _Patlayan())
    assert w.refund_spend("u1", "natal") is False


def test_iade_yazildiysa_TRUE_doner(monkeypatch):
    from core import wallet as w

    yazimlar = []

    class _Defter:
        def document(self, *a):
            return self

        def set(self, veri, **k):
            yazimlar.append(("defter", veri))

    class _Ref:
        def set(self, veri, **k):
            yazimlar.append(("bakiye", veri))

        def collection(self, _):
            return _Defter()

    monkeypatch.setattr(w, "_wallet_ref", lambda uid: _Ref())
    assert w.refund_spend("u1", "natal") is True
    assert [t for t, _ in yazimlar] == ["bakiye", "defter"]


def test_defter_dusse_de_iade_YAPILDI_sayilir(monkeypatch):
    """Iade bakiyeye yazildi; yalniz izi eksik kaldi. Kullaniciya
    "iade edilmedi" demek burada YANLIS olurdu."""
    from core import wallet as w

    class _Defter:
        def document(self, *a):
            return self

        def set(self, *a, **k):
            raise RuntimeError("defter dustu")

    class _Ref:
        def set(self, *a, **k):
            pass

        def collection(self, _):
            return _Defter()

    monkeypatch.setattr(w, "_wallet_ref", lambda uid: _Ref())
    assert w.refund_spend("u1", "natal") is True


def test_bilinmeyen_ozellikte_iade_YOK():
    from core import wallet as w

    assert w.refund_spend("u1", "olmayan-ozellik") is False


def test_cached_generate_refunded_GERCEK_sonucu_tasir(monkeypatch):
    """Bayrak "geri cagri gecildi mi"yi degil "iade yazildi mi"yi soyler."""
    from services import report_service as rs

    monkeypatch.setattr(rs.gemini_service, "generate", lambda *a, **k: None)
    monkeypatch.setattr(rs.cache, "get", lambda k: None)
    monkeypatch.setattr(rs.cache, "set", lambda *a, **k: None)

    basarili = rs._cached_generate(
        "anahtar-1", "prompt", fallback="yedek", refund=lambda: True)
    assert basarili["refunded"] is True

    basarisiz = rs._cached_generate(
        "anahtar-2", "prompt", fallback="yedek", refund=lambda: False)
    assert basarisiz["refunded"] is False, (
        "iade yazilamadi ama ekranda 'iade edildi' yazacakti")

    gericagrisiz = rs._cached_generate(
        "anahtar-3", "prompt", fallback="yedek")
    assert gericagrisiz["refunded"] is False

"""Webhook'un token paketi dallanması (Revize R1).

En kritik değişmez: **paket iadesi aboneliğe dokunamaz.** REFUND,
`_DEACTIVATING_EVENTS` kümesinde; ürün ayrımı olmasaydı 1,99$'lık paket
iadesi kullanıcının AYRI ödediği aboneliğini kapatırdı. Bu dosyadaki
testler o ayrımı ve NON_RENEWING_PURCHASE yolunu tutuyor.
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from core import config, wallet

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover - ortama bagli
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulamasi ice aktarilamadi: {_APP_IMPORT_ERROR}",
)


@pytest.fixture()
def sahte(monkeypatch):
    """Webhook sırrı + cüzdan çağrılarının kaydı + abonelik yazım kaydı."""
    monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", "anahtar")

    kayit = {"credit": [], "refund": [], "subscription_set": [],
             "audit": [], "mevcut_urun": None,
             # AD5: merge yazımları (private/revenueTotals) ayrı kovada —
             # abonelik kaydı her zaman düz `set(record)` ile yazılır.
             "merge": []}

    monkeypatch.setattr(
        "api.billing.wallet.credit_pack",
        lambda uid, pid, eid: kayit["credit"].append((uid, pid, eid)) or True)
    monkeypatch.setattr(
        "api.billing.wallet.debit_refund",
        lambda uid, pid, eid: kayit["refund"].append((uid, pid, eid)) or True)
    monkeypatch.setattr(
        "api.billing.wallet.reset_allowance", lambda uid, exp: None)
    monkeypatch.setattr(
        "api.billing.wallet.transfer_wallet", lambda c, s, t: None)

    class SahteKoleksiyon:
        def __init__(self, ad):
            self.ad = ad

        def document(self, _=None):
            return self

        def collection(self, _):
            return self

        def get(self):
            urun = kayit.get("mevcut_urun")

            class _Anlik:
                exists = urun is not None

                def to_dict(self):
                    return {"productId": urun}
            return _Anlik()

        def set(self, data, merge=False):
            # Koleksiyona göre ayrık kayıt: gelir defteri yazımları
            # abonelik yazımlarıyla karışmasın (fixture'a get() gelince
            # attribution okuması artık düşmüyor ve revenue yazımı
            # gerçekten buraya ulaşıyor).
            if self.ad == "adminAudit":
                kayit["audit"].append(data)
            elif self.ad == "revenueEvents":
                kayit.setdefault("revenue", []).append(data)
            elif merge:
                kayit["merge"].append(data)
            else:
                kayit["subscription_set"].append(data)

    class SahteClient:
        def collection(self, ad):
            return SahteKoleksiyon(ad)

    monkeypatch.setattr("api.billing.firestore_client.get_client",
                        lambda: SahteClient())
    return kayit


def _gonder(client, event):
    return client.post("/api/v1/billing/revenuecat", json={"event": event},
                       headers={"Authorization": "anahtar"})


@uygulama_gerekir
def test_paket_satisi_cuzdana_yuklenir(sahte):
    with TestClient(app) as client:
        yanit = _gonder(client, {
            "type": "NON_RENEWING_PURCHASE", "app_user_id": "u",
            "product_id": "rytho_tokens_small", "id": "evt-1"})

    assert yanit.status_code == 200
    assert sahte["credit"] == [("u", "rytho_tokens_small", "evt-1")]
    # Paket olayı abonelik dokümanına YAZMAZ.
    assert sahte["subscription_set"] == []


@uygulama_gerekir
def test_paket_iadesi_aboneligi_kapatamaz(sahte):
    """REFUND _DEACTIVATING_EVENTS içinde; ürün ayrımı olmasaydı bu istek
    `active: False` yazardı."""
    with TestClient(app) as client:
        yanit = _gonder(client, {
            "type": "REFUND", "app_user_id": "u",
            "product_id": "rytho_tokens_large", "id": "evt-2"})

    assert yanit.status_code == 200
    assert sahte["refund"] == [("u", "rytho_tokens_large", "evt-2")]
    assert sahte["subscription_set"] == []  # abonelik dokunulmadı


@uygulama_gerekir
def test_abonelik_iadesi_hala_kapatir(sahte):
    """Ayrım yalnızca paket ürünlerine: abonelik iadesi eski davranışını
    korur — erişim kesilir."""
    with TestClient(app) as client:
        yanit = _gonder(client, {
            "type": "REFUND", "app_user_id": "u",
            "product_id": "rytho_plus_monthly", "id": "evt-3"})

    assert yanit.status_code == 200
    assert sahte["refund"] == []
    assert len(sahte["subscription_set"]) == 1
    assert sahte["subscription_set"][0]["active"] is False


@uygulama_gerekir
def test_kimliksiz_paket_olayi_atlanir(sahte):
    """event.id yoksa idempotency kurulamaz; kredi yazılmaz, 200 dönülür
    (kimlik yükün kalıcı özelliği — yeniden denemede de gelmez)."""
    with TestClient(app) as client:
        yanit = _gonder(client, {
            "type": "NON_RENEWING_PURCHASE", "app_user_id": "u",
            "product_id": "rytho_tokens_small"})

    assert yanit.status_code == 200
    assert sahte["credit"] == []


@uygulama_gerekir
def test_pakette_bilinmeyen_olay_yutulur(sahte):
    with TestClient(app) as client:
        yanit = _gonder(client, {
            "type": "TEST_EVENT", "app_user_id": "u",
            "product_id": "rytho_tokens_small", "id": "evt-4"})

    assert yanit.status_code == 200
    assert sahte["credit"] == []
    assert sahte["refund"] == []


@uygulama_gerekir
def test_bilinmeyen_paket_kimligi_iz_birakir(sahte):
    """KT2/K-4: Play'de ürün kimliği bir harf sapsa "para alındı, jeton
    yok" olur — eskiden yalnız INFO loguna düşüp kayboluyordu. Artık
    adminAudit'e system kaydı düşer, kredi yazılmaz, abonelik dokunulmaz."""
    with TestClient(app) as client:
        yanit = _gonder(client, {
            "type": "NON_RENEWING_PURCHASE", "app_user_id": "u",
            "product_id": "rytho_tokens_100", "id": "evt-yanlis"})

    assert yanit.status_code == 200
    assert yanit.json()["status"] == "ignored"
    assert sahte["credit"] == []
    assert sahte["subscription_set"] == []
    assert len(sahte["audit"]) == 1
    assert sahte["audit"][0]["action"] == "billing.unknown_pack"
    assert sahte["audit"][0]["params"]["productId"] == "rytho_tokens_100"


@uygulama_gerekir
def test_yanlis_kimlikli_iade_abonelige_dokunmaz(sahte):
    """KT2/K-4 ikizi: kayıtlı abonelik ürünüyle EŞLEŞMEYEN bir REFUND
    aboneliği söndüremez (paket listesi dışı yanlış kimlik senaryosu)."""
    sahte["mevcut_urun"] = "rytho_plus_monthly"
    with TestClient(app) as client:
        yanit = _gonder(client, {
            "type": "REFUND", "app_user_id": "u",
            "product_id": "rytho_tokens_100", "id": "evt-yanlis-iade"})

    assert yanit.status_code == 200
    assert yanit.json()["status"] == "ignored"
    assert sahte["subscription_set"] == []


@uygulama_gerekir
def test_eslesen_abonelik_iadesi_kapatir(sahte):
    """Emniyet daraltması gerçek iadeyi engellemez: ürün kayıtla
    eşleşiyorsa erişim eskisi gibi kesilir."""
    sahte["mevcut_urun"] = "rytho_plus_monthly"
    with TestClient(app) as client:
        yanit = _gonder(client, {
            "type": "REFUND", "app_user_id": "u",
            "product_id": "rytho_plus_monthly", "id": "evt-gercek-iade"})

    assert yanit.status_code == 200
    assert len(sahte["subscription_set"]) == 1
    assert sahte["subscription_set"][0]["active"] is False


def test_paket_listesi_sunucu_gercegi():
    """İstemciden gelen hiçbir sayıya güvenilmez; adetler burada."""
    assert set(wallet.TOKEN_PACKS) == {
        "rytho_tokens_small", "rytho_tokens_medium", "rytho_tokens_large"}
    assert all(v > 0 for v in wallet.TOKEN_PACKS.values())


@uygulama_gerekir
def test_expiration_olmayan_aktivasyonda_hak_yine_verilir(monkeypatch, sahte):
    """K2: webhook `expiration_at_ms` tasimasa da aylik hak yazilir.

    Eski davranis: expires None -> reset_allowance hic yazmiyordu ve ilk
    alimda bakiye 0 gorunuyordu.

    Bir tur boyunca cozum "simdi + 35 gun" UYDURMAKTI ve gerekcesi "bir
    sonraki RENEWAL gercek tarihi yazar" diye yaziliydi. Gerekce TERSINI
    uretiyordu: uydurulan isaret gercek donem sonundan ILERIDE kaldigi icin
    bir sonraki yenilemenin tarihi ondan GERIDE kaliyor, idempotency kapisi
    dusmuyor ve kullanici o donemin hakkini HIC ALMIYOR.
    Artik None oldugu gibi geciliyor; hakki `reset_allowance` isareti
    TASIMADAN veriyor (bkz. test_K2_son_kullanma_YOKSA_isaret_UYDURULMAZ)."""
    cagrilar = []
    monkeypatch.setattr(
        "api.billing.wallet.reset_allowance",
        lambda uid, exp: cagrilar.append((uid, exp)))

    with TestClient(app) as client:
        yanit = _gonder(client, {
            "type": "INITIAL_PURCHASE", "app_user_id": "u-k2",
            "product_id": "rytho_plus_monthly", "id": "evt-k2"})
        # expiration_at_ms YOK.

    assert yanit.status_code == 200
    assert len(cagrilar) == 1
    uid, exp = cagrilar[0]
    assert uid == "u-k2"
    # Tarih UYDURULMAZ: None oldugu gibi gecer. Hakkin gercekten verildigi
    # cuzdan katmaninda olculuyor (test_wallet.py), cunku burada
    # reset_allowance yamali.
    assert exp is None, "son kullanma uyduruldu: sonraki yenileme yutulur"

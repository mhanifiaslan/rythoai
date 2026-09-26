"""Token cüzdanı — abonelik hakkı + satın alınan paketler.

## Neden var

Abonelik tek başına "sınırsız sohbet" vaat ediyordu ve sohbet, kullanıcı
başına önbelleksiz LLM çağrısı olan TEK uçtur: öngörülemeyen yoğun kullanım
maliyeti doğrusal büyütür. Model değişti — abonelik aylık bir token hakkı
verir, dilenirse üstüne paket alınır:

* ``allowance`` — abonelikle gelen aylık hak. Dönem bitince YENİLENİR,
  DEVREDİLMEZ (kullanıcı kararı).
* ``purchased`` — satın alınan paket bakiyesi. Aya DEVREDER, hiç yanmaz.

Harcama sırası önce ``allowance`` sonra ``purchased``: yanacak olan önce
harcanır, kullanıcının parayla aldığı bakiye korunur.

## Neden transaction

Mevcut ``consume_quota`` get-then-set çalışır ve bu bilinçli bir
yumuşaklıktır (günlük 5 sohbet hakkında yarış penceresi kimseyi
ilgilendirmez). Cüzdan İSE para: iki eşzamanlı istek aynı bakiyeyi iki kez
harcayabilir ya da webhook yeniden denemesi aynı paketi iki kez
yükleyebilir. Harcama ve kredi Firestore transaction'ı içinde; kredi ayrıca
RevenueCat olay kimliğiyle deftere yazılıp idempotent kılınır.

## Sıfır bakiyede ne olur

402 döner — mevcut paywall borusunun aynısı — ama yanına
``X-Paywall-Reason: tokens`` başlığı eklenir. ``detail`` alanı istemcide
kullanıcıya gösterilen düz metindir (friendlyError sözleşmesi), ayrım oraya
gömülemez; istemci başlığa bakıp paywall yerine token mağazasını açar.

## Kademeli açılış

``RYTHO_TOKENS_ENFORCE=0`` iken harcama hesaplanır ve loglanır ama asla
reddedilmez. Eski mobil sürümler yayılana kadar üretim bu kipte çalışır;
bayrak açıldığında istemciler mağaza ekranını zaten biliyor olur.
"""
from __future__ import annotations

import datetime as dt
import logging
import os
from typing import Any, Callable

from fastapi import HTTPException

from core import firestore as firestore_client
# `entitlements` MODÜL olarak: `from ... import is_subscriber` ile kopyalanan
# ad, testlerin (ve olası çalışma zamanı yamalarının) `entitlements.X`
# üzerine yaptığı monkeypatch'i GÖRMEZ — bu dosyada bir kez yaşandı.
from core import entitlements
from core.entitlements import PAYWALL_STATUS
from core.i18n import DEFAULT as DEFAULT_LANG
from core.messages import text

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Ürün gerçeği — SUNUCUDA tutulur, istemciye güvenilmez
# ---------------------------------------------------------------------------

#: Özellik başına token bedeli. Fiyatlandırma LLM maliyetiyle hizalı:
#: sohbet tek kısa çağrı (1), derin raporlar uzun üretim (5). Önbellekten
#: servis edilen tekrar okumalar HİÇ düşmez (bkz. report_service).
TOKEN_COSTS: dict[str, int] = {
    "chat": 1,
    "iching": 2,
    "dyad": 3,
    "natal": 5,
    "bazi": 5,
    "synastry": 5,
    "face": 5,
    # Doğum Heksagramı (İ5): natal ile aynı sınıf — kişiye özel, 30 gün
    # önbellekli kalıcı üretim.
    "birth_hexagram": 5,
    # Yıl haritası (T1): natal sınıfı — SR yılı boyunca önbellekten.
    "solar_return": 5,
    # İç Takvim (T2): natal sınıfı — ay hassasiyetli 30 gün önbellek.
    "progressions": 5,
}

#: Abonelikle gelen aylık hak. En kötü durum maliyeti sınırlar: 300 token
#: tamamı sohbete gitse ~$0,45 LLM gideri — abonelik bedelinin küçük kesri.
MONTHLY_TOKEN_ALLOWANCE = 300

#: RevenueCat consumable ürün kimliği -> token adedi. Webhook yalnızca bu
#: listedeki ürünleri paket sayar; liste dışı ürün kimliği abonelik borusuna
#: gider. İstemciden gelen hiçbir sayıya güvenilmez.
TOKEN_PACKS: dict[str, int] = {
    "rytho_tokens_small": 100,
    "rytho_tokens_medium": 300,
    "rytho_tokens_large": 1000,
}

#: Kuru çalışma bayrağı. 0 iken harcama loglanır ama reddedilmez.
TOKENS_ENFORCE: bool = os.getenv("RYTHO_TOKENS_ENFORCE", "0") == "1"

#: Deneme dönemi hoş geldin jetonu (OT6): yeni hesap ilk 3 gün Plus
#: kapılarını kullanır (core.entitlements.in_trial) ama jetonlu yüzeyler
#: (rapor 5, dyad 3, sohbet 1) bakiye ister — deneme "tüm özellikler"
#: vaadini ancak küçük bir başlangıç bakiyesiyle tutar. `credit_promo`
#: defteriyle hesap başına TEK SEFER yüklenir; deneme bitince kalan
#: bakiye kullanıcıda kalır (30 jeton ≈ $0,06 tavan maliyet).
TRIAL_PROMO_CODE = "TRIAL-WELCOME"
TRIAL_TOKENS = 30


def _wallet_ref(uid: str):
    client = firestore_client.get_client()
    if client is None:
        return None
    return (client.collection("users").document(uid)
            .collection("private").document("wallet"))


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _ts(value: Any) -> float:
    """Firestore zaman damgasını karşılaştırılabilir sayıya indirger."""
    try:
        return value.timestamp()
    except AttributeError:
        return 0.0


# ---------------------------------------------------------------------------
# Okuma
# ---------------------------------------------------------------------------

def get_wallet(uid: str) -> dict[str, Any]:
    """Cüzdanın istemciye gösterilecek hâli; tembel sıfırlama YANSITILIR
    ama yazılmaz (yazma yalnızca harcama/kredi anında, transaction içinde).
    """
    ref = _wallet_ref(uid)
    data: dict[str, Any] = {}
    if ref is not None:
        try:
            snapshot = ref.get()
            data = (snapshot.to_dict() or {}) if snapshot.exists else {}
        except Exception as exc:
            logger.warning("Cüzdan okunamadı (%s): %s", uid, exc)

    allowance = int(data.get("allowance", 0))
    marker = data.get("allowanceExpiresAt")

    sub = entitlements.get_subscription(uid)
    sub_expires = sub.get("expiresAt")
    if sub.get("active") and _ts(sub_expires) > _ts(marker):
        # Yeni dönem başlamış, webhook resetini kaçırmışız: görünümde tam
        # hakkı göster. Kalıcı yazım ilk harcamada yapılır.
        allowance = MONTHLY_TOKEN_ALLOWANCE
        marker = sub_expires

    return {
        "allowance": allowance if sub.get("active") else 0,
        "purchased": int(data.get("purchased", 0)),
        "monthly_allowance": MONTHLY_TOKEN_ALLOWANCE,
        "allowance_resets_at": marker,
        "costs": dict(TOKEN_COSTS),
    }


# ---------------------------------------------------------------------------
# Harcama
# ---------------------------------------------------------------------------

def _spend_txn(transaction, ref, uid: str, feature: str, cost: int) -> bool:
    """Transaction gövdesi: oku, gerekirse dönemi tazele, düş, yaz.

    Başarılı düşüm deftere de yazılır (type=debit): "kim, neye, kaç jeton"
    sorusunun kalıcı cevabı. Defter bakiye MUTASYONUNU aynalar — kuru
    çalışma bayrağından bağımsızdır, çünkü ENFORCE=0'da da bakiye düşer
    (bayrak yalnız yetersiz-bakiye reddini bastırır). Yazım transaction
    tamponunda biriktiği için retry çift kayıt üretemez: her deneme
    gövdeyi (ve ledger_ref'i) sıfırdan kurar, tampon yalnız başarılı
    commit'te işlenir.
    """
    snapshot = ref.get(transaction=transaction)
    data = (snapshot.to_dict() or {}) if snapshot.exists else {}

    allowance = int(data.get("allowance", 0))
    marker = data.get("allowanceExpiresAt")

    # Tembel dönem tazeleme: webhook RENEWAL'i kaçırdıysa bile kullanıcı
    # yeni dönemde hakkını alır. `get_subscription` transaction dışı bir
    # okuma ama tek yönlü: yalnızca İLERİ tarihli döneme tazeler, aynı
    # dönemde ikinci kez tetiklenemez (işaret eşitlenince koşul düşer).
    sub = entitlements.get_subscription(uid)
    if sub.get("active"):
        if _ts(sub.get("expiresAt")) > _ts(marker):
            allowance = MONTHLY_TOKEN_ALLOWANCE
            marker = sub.get("expiresAt")
    else:
        # Abonelik yoksa dönem de yok: sönmüş dönemden kalan hak HARCANAMAZ.
        # Yalnızca satın alınmış bakiye geçerlidir; o zaten devrediyor.
        allowance = 0

    purchased = int(data.get("purchased", 0))
    if allowance + purchased < cost:
        return False

    # Önce yanacak olan: dönem sonunda sıfırlanan allowance.
    dusen = min(allowance, cost)
    allowance -= dusen
    purchased -= cost - dusen

    transaction.set(ref, {
        "allowance": allowance,
        "allowanceExpiresAt": marker,
        "purchased": purchased,
        "updatedAt": _now(),
    })
    ledger_ref = ref.collection("ledger").document()
    transaction.set(ledger_ref, {
        "type": "debit",
        "feature": feature,
        "amount": cost,
        "allowancePart": dusen,
        "purchasedPart": cost - dusen,
        "at": _now(),
    })
    return True


def spend(uid: str, feature: str, *, lang: str = DEFAULT_LANG) -> None:
    """Özelliğin bedelini düşer; bakiye yetmezse 402 (tokens) fırlatır.

    Firestore erişilemezse İSTEK DÜŞÜRÜLMEZ (fail-open) — mevcut kota
    katmanının duruşuyla tutarlı: altyapı sorunu kullanıcının suçu değil.
    """
    cost = TOKEN_COSTS.get(feature)
    if not cost:
        return

    ref = _wallet_ref(uid)
    if ref is None:
        logger.warning("Cüzdan yok (Firestore kapalı); %s bedava geçti.", feature)
        return

    try:
        from google.cloud import firestore as gcf

        client = firestore_client.get_client()
        transaction = client.transaction()

        @gcf.transactional
        def _run(txn):
            return _spend_txn(txn, ref, uid, feature, cost)

        yeterli = _run(transaction)
    except Exception as exc:
        logger.warning("Token düşümü yapılamadı (%s/%s): %s", uid, feature, exc)
        return

    if yeterli:
        return

    if not TOKENS_ENFORCE:
        # Kuru çalışma: reddedilecek isteği logla ama geçir. Bayrak
        # açılmadan önce üretimdeki gerçek etkiyi buradan ölçeriz.
        logger.info("TOKENS kuru-çalışma: %s/%s reddedilecekti.", uid, feature)
        return

    raise HTTPException(
        status_code=PAYWALL_STATUS,
        detail=text("tokens.empty", lang),
        headers={"X-Paywall-Reason": "tokens"},
    )


def refund_spend(uid: str, feature: str) -> bool:
    """LLM üretemediyse bedeli iade eder — kullanıcı almadığı şeye ödemez.

    İade ``purchased``'a yazılır: hangi kovadan düştüğünü geri izlemek
    transaction dışında güvenilmez ve kullanıcı LEHİNE yanılmak doğrudur
    (purchased devrettiği için iade asla yanmaz).

    DÖNÜŞ: bakiye artışı GERÇEKTEN yazıldıysa ``True``.

    ⚠️ Bu dönüş bir süs değil: istemci artık kullanıcıya "harcanan jetonun
    iade edildi" CÜMLESİNİ kuruyor (gz-2). Eskiden çağıran taraf yalnız
    "iade geri çağrısı geçildi mi" bilgisine bakıyordu, yani iade yazımı
    düşüp `logger.warning` ile yutulduğunda ekranda YİNE "iade edildi"
    yazıyordu — ödemiş kullanıcıya verilen yalan bir söz. Defterin
    düşmesi ``True``'yu bozmaz: iade YAPILDI, yalnız izi eksik kaldı.
    """
    cost = TOKEN_COSTS.get(feature)
    if not cost:
        return False
    ref = _wallet_ref(uid)
    if ref is None:
        return False
    try:
        from google.cloud import firestore as gcf
        ref.set({"purchased": gcf.Increment(cost), "updatedAt": _now()},
                merge=True)
    except Exception as exc:
        logger.warning("Token iadesi yapılamadı (%s/%s): %s", uid, feature, exc)
        return False
    try:
        # İade defteri: bakiye artışının izi. Ayrı try — defter düşerse
        # iade YAPILDI, yalnız iz eksik kalır; log bunu doğru söylemeli.
        ref.collection("ledger").document().set({
            "type": "spend_refund", "feature": feature,
            "amount": cost, "at": _now(),
        })
    except Exception as exc:
        logger.warning("İade defteri yazılamadı (%s/%s): %s", uid, feature, exc)
    # Defter düşse de iade YAPILDI: kullanıcının bakiyesi arttı.
    return True


def spender(uid: str, feature: str, *, lang: str = DEFAULT_LANG) -> Callable[[], None]:
    """`_cached_generate`'e verilecek harcama geri çağrısı üretir."""
    def _spend() -> None:
        spend(uid, feature, lang=lang)
    return _spend


# ---------------------------------------------------------------------------
# Ücretsiz katman + cüzdan birleşik kapısı (sohbet / iching)
# ---------------------------------------------------------------------------

def charge_metered(user, feature: str, free_limit: int,
                   *, lang: str = DEFAULT_LANG) -> bool:
    """Günlük ücretsiz hak + cüzdanı tek kapıda birleştirir (ÖNBELLEKSİZ
    uçlar için — sohbet). Dönen değer: cüzdandan token düştü mü (iade
    kararı için; ücretsiz kotadan geçen istekte iade edilecek şey yok).

    Sıra: abone cüzdanından harcar (aylık hak bunun için var); ücretsiz
    kullanıcı önce günlük hakkını yer, bitince satın alınmış paketi varsa
    ondan harcar (paket almak için abonelik ŞART DEĞİL — bilinçli karar),
    o da yoksa mevcut kota metniyle 402.
    """
    from core.entitlements import consume_quota  # döngüsel import kırıcı

    # KT2: yalnız GERÇEK mağaza abonesi (ya da FORCE_PLUS test kipi)
    # doğrudan cüzdandan harcar — aylık 300'lük hak bunun için var.
    # Sunucu denemesindeki (in_trial) kullanıcı ESKİDEN buraya düşüyordu
    # ve günlük ücretsiz hakkını KAYBEDİYORDU: 30 karşılama jetonu bir
    # rapor turunda bitince, denemenin kalan günlerinde ücretsiz
    # kullanıcıdan bile kısıtlı kalıyordu. Deneme artık ücretsiz hakkın
    # ÜSTÜNE jeton verir, yerine değil.
    if entitlements.FORCE_PLUS or entitlements.get_subscription(
            user.uid).get("active"):
        spend(user.uid, feature, lang=lang)
        return True

    if consume_quota(user.uid, feature, free_limit):
        return False

    # Günlük hak bitti; bakiye (deneme jetonu ya da paket) kurtarabilir.
    wallet_state = get_wallet(user.uid)
    if wallet_state.get("purchased", 0) >= TOKEN_COSTS.get(feature, 0):
        spend(user.uid, feature, lang=lang)
        return True

    raise HTTPException(
        status_code=PAYWALL_STATUS,
        detail=text(f"quota.{feature}", lang, fallback="quota.default",
                    limit=free_limit),
    )


def metered_callbacks(user, feature: str, free_limit: int,
                      *, lang: str = DEFAULT_LANG,
                      ) -> tuple[Callable[[], None] | None,
                                 Callable[[], bool] | None]:
    """ÖNBELLEKLİ ölçülü uçlar (iching) için harcama geri çağrıları.

    `charge_metered`'dan farkı: burada hiçbir şey HEMEN harcanmaz — dönen
    ``spend`` geri çağrısı `_cached_generate` içinde yalnızca önbellek
    kaçırıldığında çalışır. Peşin harcasaydık abone, saatlik önbellekteki
    aynı çekilişe ikinci bakışında da ödeme yapardı.

    Ücretsiz günlük hak İSE peşin düşer (bugünkü davranış): "günde 1 çekiliş"
    ritüel sınırıdır, üretim maliyeti sınırı değil.
    """
    from core.entitlements import consume_quota  # döngüsel import kırıcı

    def _spend() -> None:
        spend(user.uid, feature, lang=lang)

    def _refund() -> bool:
        # Dönüş TAŞINIR: `_cached_generate` bununla "jetonun iade edildi"
        # cümlesini kuruyor (gz-2). Yutarsak iching yolunda bayrak her
        # zaman False olur ve iade edilen jeton kullanıcıya SÖYLENMEZ.
        return refund_spend(user.uid, feature)

    # KT2: charge_metered ile aynı ayrım — deneme kullanıcısı günlük
    # ücretsiz hakkını korur (gerekçe yukarıda).
    if entitlements.FORCE_PLUS or entitlements.get_subscription(
            user.uid).get("active"):
        return _spend, _refund

    if consume_quota(user.uid, feature, free_limit):
        return None, None

    wallet_state = get_wallet(user.uid)
    if wallet_state.get("purchased", 0) >= TOKEN_COSTS.get(feature, 0):
        return _spend, _refund

    raise HTTPException(
        status_code=PAYWALL_STATUS,
        detail=text(f"quota.{feature}", lang, fallback="quota.default",
                    limit=free_limit),
    )


# ---------------------------------------------------------------------------
# Kredi — RevenueCat webhook'undan
# ---------------------------------------------------------------------------

def credit_pack(uid: str, product_id: str, event_id: str) -> bool:
    """Paket satın alımını cüzdana yükler. Olay kimliğiyle idempotent:
    webhook yeniden denemesi aynı paketi İKİ KEZ yükleyemez.
    """
    amount = TOKEN_PACKS.get(product_id)
    if not amount:
        return False
    ref = _wallet_ref(uid)
    if ref is None:
        # Yükleme kaybolmasın: hata fırlat ki webhook 500 görüp yeniden
        # denesin. Harcamadaki fail-open BURADA YANLIŞ olurdu — orada
        # kaybedilen tek istek, burada kullanıcının parası.
        raise RuntimeError("Firestore erisilemiyor; kredi ertelendi.")

    ledger_ref = ref.collection("ledger").document(str(event_id))

    from google.cloud import firestore as gcf

    client = firestore_client.get_client()
    transaction = client.transaction()

    @gcf.transactional
    def _run(txn) -> bool:
        if ledger_ref.get(transaction=txn).exists:
            return False  # zaten işlendi
        snapshot = ref.get(transaction=txn)
        data = (snapshot.to_dict() or {}) if snapshot.exists else {}
        txn.set(ref, {**data,
                      "purchased": int(data.get("purchased", 0)) + amount,
                      "updatedAt": _now()})
        txn.set(ledger_ref, {"type": "credit", "productId": product_id,
                             "amount": amount, "at": _now()})
        return True

    islendi = _run(transaction)
    if islendi:
        logger.info("Token paketi yüklendi: uid=%s ürün=%s +%d", uid, product_id, amount)
    else:
        logger.info("Token kredisi zaten işlenmiş (idempotent): %s", event_id)
    return True


def credit_promo(uid: str, code: str, amount: int) -> bool:
    """Ortak kodu bonusunu cüzdana yükler (W7) — credit_pack'in varyantı.

    Defter kimliği ``promo-{KOD}``: aynı kullanıcı aynı kodu iki kez
    yükleyemez (uid başına idempotent; kod zaten attribution'la tek sefer
    ama savunma iki katmanlı). ``False`` = zaten işlenmişti.
    """
    if amount <= 0:
        return False
    ref = _wallet_ref(uid)
    if ref is None:
        raise RuntimeError("Firestore erisilemiyor; promo ertelendi.")

    ledger_ref = ref.collection("ledger").document(f"promo-{code}")

    from google.cloud import firestore as gcf

    client = firestore_client.get_client()
    transaction = client.transaction()

    @gcf.transactional
    def _run(txn) -> bool:
        if ledger_ref.get(transaction=txn).exists:
            return False
        snapshot = ref.get(transaction=txn)
        data = (snapshot.to_dict() or {}) if snapshot.exists else {}
        txn.set(ref, {**data,
                      "purchased": int(data.get("purchased", 0)) + amount,
                      "updatedAt": _now()})
        txn.set(ledger_ref, {"type": "promo", "code": code,
                             "amount": amount, "at": _now()})
        return True

    islendi = _run(transaction)
    logger.info("Promo %s: uid=%s kod=%s +%d",
                "yüklendi" if islendi else "zaten işlenmiş", uid, code, amount)
    return islendi


def ensure_trial_tokens(uid: str) -> None:
    """Deneme jetonu TEMBEL TELAFİSİ (KT2).

    30'luk karşılama jetonu normalde onboarding'in `/account/consent`
    çağrısında yüklenir — ama o çağrı iki katmanda da sessizce
    yutuluyordu ve tek ağ hıçkırığı denemeyi jetonsuz bırakıyordu.
    Cüzdan her okunduğunda: kullanıcı denemede VE defterde karşılama
    kaydı yoksa, kredi tamamlanır (credit_promo zaten defterle
    idempotent — çift yükleme imkânsız). Varlık kontrolü ucuz bir
    okuma; kayıt varsa transaction hiç kurulmaz.
    """
    try:
        if not entitlements.in_trial(uid):
            return
        ref = _wallet_ref(uid)
        if ref is None:
            return
        kayit = (ref.collection("ledger")
                 .document(f"promo-{TRIAL_PROMO_CODE}").get())
        if getattr(kayit, "exists", False):
            return
        if credit_promo(uid, TRIAL_PROMO_CODE, TRIAL_TOKENS):
            logger.info("Deneme jetonu tembel telafiyle yüklendi: %s", uid)
    except Exception as exc:
        logger.warning("Deneme telafisi yapılamadı (%s): %s", uid, exc)


def credit_admin(uid: str, amount: int, reason: str, admin_uid: str) -> bool:
    """Panelden elle kredi (AP-turu) — credit_promo'nun denetimli varyantı.

    Gerekçe ZORUNLU (uç Pydantic'te de zorlar): "neden verildi" sorusunun
    cevabı defterde durur. Bilinçli olarak İDEMPOTENT DEĞİL — her elle
    kredi ayrı bir olaydır; çift tıklama koruması panelde (buton kilidi +
    onay). Firestore yoksa hata fırlatılır: para kaybolmaz, admin hatayı
    görür (credit_pack duruşu).
    """
    if amount <= 0:
        return False
    ref = _wallet_ref(uid)
    if ref is None:
        raise RuntimeError("Firestore erisilemiyor; kredi verilemedi.")

    import uuid

    ledger_ref = ref.collection("ledger").document(f"admin-{uuid.uuid4().hex}")

    from google.cloud import firestore as gcf

    client = firestore_client.get_client()
    transaction = client.transaction()

    @gcf.transactional
    def _run(txn) -> None:
        snapshot = ref.get(transaction=txn)
        data = (snapshot.to_dict() or {}) if snapshot.exists else {}
        txn.set(ref, {**data,
                      "purchased": int(data.get("purchased", 0)) + amount,
                      "updatedAt": _now()})
        txn.set(ledger_ref, {"type": "admin", "amount": amount,
                             "reason": reason, "adminUid": admin_uid,
                             "at": _now()})

    _run(transaction)
    logger.info("Admin kredisi: uid=%s +%d (%s)", uid, amount, admin_uid)
    return True


def debit_refund(uid: str, product_id: str, event_id: str) -> bool:
    """Paket iadesini bakiyeden düşer (0'da kelepçe), defterle idempotent."""
    amount = TOKEN_PACKS.get(product_id)
    if not amount:
        return False
    ref = _wallet_ref(uid)
    if ref is None:
        raise RuntimeError("Firestore erisilemiyor; iade ertelendi.")

    ledger_ref = ref.collection("ledger").document(f"refund-{event_id}")

    from google.cloud import firestore as gcf

    client = firestore_client.get_client()
    transaction = client.transaction()

    @gcf.transactional
    def _run(txn) -> None:
        if ledger_ref.get(transaction=txn).exists:
            return
        snapshot = ref.get(transaction=txn)
        data = (snapshot.to_dict() or {}) if snapshot.exists else {}
        # Kelepçe: kullanıcı bakiyeyi harcadıysa eksiye düşürmeyiz; mağaza
        # iade kararını verdi, biz borç defteri tutmayız.
        yeni = max(int(data.get("purchased", 0)) - amount, 0)
        txn.set(ref, {**data, "purchased": yeni, "updatedAt": _now()})
        txn.set(ledger_ref, {"type": "refund", "productId": product_id,
                             "amount": amount, "at": _now()})

    _run(transaction)
    logger.info("Token paketi iadesi işlendi: uid=%s ürün=%s", uid, product_id)
    return True


def reset_allowance(uid: str, expires_at: dt.datetime | None) -> None:
    """Yeni abonelik dönemi: aylık hakkı tazeler (webhook birincil yol,
    ``spend`` içindeki tembel tazeleme yedek).

    İşaret karşılaştırması idempotent kılar: aynı dönemin tekrarlanan
    webhook'u hakkı İKİ KEZ vermez.
    """
    if expires_at is None:
        return
    ref = _wallet_ref(uid)
    if ref is None:
        return
    try:
        snapshot = ref.get()
        data = (snapshot.to_dict() or {}) if snapshot.exists else {}
        if _ts(expires_at) <= _ts(data.get("allowanceExpiresAt")):
            return
        ref.set({**data,
                 "allowance": MONTHLY_TOKEN_ALLOWANCE,
                 "allowanceExpiresAt": expires_at,
                 "updatedAt": _now()})
        logger.info("Aylık token hakkı tazelendi: uid=%s", uid)
    except Exception as exc:
        logger.warning("Hak tazelenemedi (%s): %s", uid, exc)


#: Devirde taşınan alanlar. Tüm dokümanı körlemesine kopyalamak yasak:
#: kaynakta cüzdan dışı bir şey varsa (bozuk yazım, ileride eklenen alan)
#: hedefte ne olduğu belirsiz bir doküman doğar.
_WALLET_FIELDS = ("allowance", "allowanceExpiresAt", "purchased")


def _devir_govdesi(anlik, kaynak: dict[str, Any]) -> dict[str, Any]:
    """Devirde hedefe yazılacak gövde: satın alınan bakiye TOPLANIR.

    Eski hâli ``{**kayit}`` + ``merge=True`` idi ve merge ALAN düzeyinde
    birleştirir: hedefte 300 kredi varken kaynaktan 100 gelince hedef 100'e
    DÜŞÜYORDU — yok olan 300 kredi parayla alınmıştı.

    ``allowance`` PARA DEĞİL, aylık haktır ve devretmez; iki dönemden İLERİ
    tarihli olanı geçerli sayılır (dönem sonunda yanacak olanı toplamak
    uydurma bakiye üretirdi). Bu kural devri aynı zamanda tekrara dayanıklı
    kılar: TRANSFER olayının olay kimliğiyle idempotency koruması YOKTUR, ama
    kaynak ilk geçişte sıfırlandığı için toplama 0 ekler ve dönem işareti
    eşitlendiği için hak ikinci kez yazılmaz.

    Bilinen daraltma: kaynakta ``allowance`` var ama ``allowanceExpiresAt``
    YOKSA hak artık taşınmaz (``_ts(None)`` iki tarafta da 0). Eski
    körlemesine merge taşıyordu; dar bir eski-veri hâli, bilinçli kabul.
    """
    mevcut = (anlik.to_dict() or {}) if getattr(anlik, "exists", False) else {}
    govde: dict[str, Any] = {
        "purchased": (int(mevcut.get("purchased", 0) or 0)
                      + int(kaynak.get("purchased", 0) or 0)),
        "updatedAt": _now(),
    }
    if _ts(kaynak.get("allowanceExpiresAt")) > _ts(
            mevcut.get("allowanceExpiresAt")):
        govde["allowance"] = int(kaynak.get("allowance", 0) or 0)
        govde["allowanceExpiresAt"] = kaynak.get("allowanceExpiresAt")
    return govde


def transfer_wallet(client, sources: list[str], targets: list[str],
                    *, event_id: str | None = None) -> None:
    """TRANSFER olayında cüzdanı da taşır — satın alınmış bakiye kullanıcının
    parasıdır, kimlik değişiminde kaybolamaz.

    Yalnızca [_WALLET_FIELDS] taşınır ve kaynakların HİÇBİRİNDE bu
    alanlardan biri yoksa hedefe HİÇ yazılmaz: cüzdanı olmayan bir kimlikten
    devir, hedefin mevcut cüzdanını sıfırlamamalı.

    Hedefe yazım OKU-TOPLA-YAZ'dır ([_devir_govdesi]): ``purchased``
    toplanır, ``allowance``ta ileri tarihli dönem kazanır.

    Transaction KULLANILMIYOR ve gerekçe "tek yazan webhook işleyicisi"
    DEĞİL — o ifade yanlıştı: bu dokümana sıradan API istekleri de yazıyor
    ([_spend_txn] her harcamada ``purchased``ı düşürüyor, [credit_pack] ve
    [refund_spend] de yazıyor). Gerçek gerekçe: oku-topla-yaz'ın açtığı yarış
    penceresine düşmek için hedefin, kimliğin devredildiği milisaniyelerde
    ikinci bir cihazda harcama yapması gerekir; TRANSFER nadir bir olay ve bu
    kesişim bilinçli kabul edildi. Kapatılacaksa `client.transaction()` ile
    ayrı bir iş.

    Çok HEDEFLİ TRANSFER'de her hedef kaynakların TAM toplamını alır, yani
    kredi hedef sayısı kadar çoğalır (eski kod da böyleydi; artık hedefin
    mevcut bakiyesinin ÜSTÜNE eklendiği için adı konuyor). Pratikte RevenueCat
    tek hedef gönderiyor.

    Çağıran taraf bu fonksiyonu abonelik kaydının VARLIĞINDAN bağımsız
    çağırmak zorundadır (bkz. api/billing.py `_handle_transfer`) — paket almak
    için abonelik şart değil, yani abonelik kaydı olmayan bir kimliğin de
    bakiyesi olabilir.

    SIRA: önce HEDEFLER yazılır, kaynaklar EN SONDA sıfırlanır — ve hedef
    yazımındaki hata YUTULMAZ, fırlatılır.

    ⚠️ Tersi ölçüldü ve kalıcı kredi kaybı üretiyordu. Eski sırada kaynaklar
    ÖNCE sıfırlanıyor, hedefe yazım ``except Exception: logger.warning`` ile
    yutuluyor, webhook 200 dönüyor ve RevenueCat bir daha DENEMİYORDU. Geçici
    bir Firestore hatasında: 1. geçişte kaynaklar 0'landı ve hedef yazılamadı;
    Firestore düzelince tekrar gelen olay hedefe 350 değil **0** yazdı —
    350 kredi kalıcı olarak yok. [credit_pack] tam bu yüzden fırlatıyor ve
    gerekçesi orada yazılı: "orada kaybedilen tek istek, burada kullanıcının
    parası." Devir de kullanıcının parasıdır.

    TEKRAR KORUMASI artık kaynağın sıfır olmasına DEĞİL DEFTERE bağlı:
    ``event_id`` verildiğinde hedefin ``ledger/transfer-{event_id}`` işareti
    aranır ve varsa o hedef atlanır. Sıra tersine döndüğü için "kaynak zaten
    sıfır, tekrar 0 ekler" güvencesi ortadan kalkıyordu; defter onun yerini
    alıyor. ``event_id`` YOKSA (eski çağıran) koruma da yok — o hâlde tekrar
    çift kredi verebilir, bu yüzden çağıran olay kimliğini GEÇMELİ.

    Bilinen sınır (AP-turu): ledger alt koleksiyonu TAŞINMAZ — kredi
    geçmişi eski uid'de kalır, hedefte idempotency işaretleri sıfırlanır.
    Devir nadir bir olaydır; defter birleştirme ayrı bir iş.
    """
    def _ref(uid: str):
        return (client.collection("users").document(uid)
                .collection("private").document("wallet"))

    # BÜTÜN kaynaklar TOPLANIR. Eski hâli "ilk var olan kaynak kazanır"dı
    # (``if snapshot.exists and kayit is None``) ama döngü HER kaynağı
    # sıfırlıyordu: ikinci kaynağın bakiyesi hiçbir yere gitmeden yok
    # oluyordu. Ölçüldü: a=100, b=250, hedef=0 → hedef 100, 250 kredi
    # buharlaştı. Sıcak yol, çünkü RevenueCat'in ``transferred_from`` alanı
    # LİSTEDİR (anonim kimlik + eski uid birlikte gelebilir).
    toplam = 0
    hak: dict[str, Any] = {}
    cuzdan_bulundu = False
    for kaynak in sources:
        try:
            snapshot = _ref(kaynak).get()
            if not snapshot.exists:
                # Sıfırlama YALNIZ var olan cüzdana: olmayanı sıfırlamak boş
                # bir doküman YARATMAKTAN başka iş yapmaz.
                continue
            ham = snapshot.to_dict() or {}
            if any(k in ham for k in _WALLET_FIELDS):
                cuzdan_bulundu = True
            toplam += int(ham.get("purchased", 0) or 0)
            if _ts(ham.get("allowanceExpiresAt")) > _ts(
                    hak.get("allowanceExpiresAt")):
                hak = {"allowance": int(ham.get("allowance", 0) or 0),
                       "allowanceExpiresAt": ham.get("allowanceExpiresAt")}
        except Exception as exc:
            # Okunamayan kaynak ATLANIR: bir kaynağın erişilemez olması
            # diğerlerinin parasını rehin almamalı.
            logger.warning("Cüzdan devri (kaynak %s) okunamadı: %s",
                           kaynak, exc)

    if not cuzdan_bulundu:
        return
    kayit = {**hak, "purchased": toplam}

    # 1) HEDEFLER. Buradaki hata YUTULMAZ — fırlatırsa webhook 500 görür ve
    #    RevenueCat yeniden dener. Kaynaklar henüz sıfırlanmadığı için o
    #    tekrar parayı bulur.
    for hedef in targets:
        hedef_ref = _ref(hedef)
        defter = (hedef_ref.collection("ledger")
                  .document(f"transfer-{event_id}") if event_id else None)
        if defter is not None and getattr(defter.get(), "exists", False):
            # Bu olay bu hedefe zaten işlendi: tekrar çift kredi vermez.
            continue
        # OKU-TOPLA-YAZ: `merge=True` ALAN düzeyinde birleştirdiği için düz
        # yazım hedefin bakiyesini EZİYORDU (bkz. _devir_govdesi). Hedef
        # okuması döngünün İÇİNDE: her hedef kendi bakiyesiyle toplanır.
        hedef_ref.set(_devir_govdesi(hedef_ref.get(), kayit), merge=True)
        if defter is not None:
            defter.set({"type": "transfer", "from": list(sources),
                        "amount": int(kayit.get("purchased", 0) or 0),
                        "at": _now()})

    # 2) KAYNAKLAR en sonda. Buraya gelindiyse para hedefte.
    for kaynak in sources:
        try:
            _ref(kaynak).set({"allowance": 0, "purchased": 0,
                              "updatedAt": _now()}, merge=True)
        except Exception as exc:
            # Sıfırlama düşerse para hedefte DURUYOR; en kötüsü kaynakta da
            # görünmeye devam etmesi. Defter işareti tekrarı zaten kesiyor.
            logger.warning("Cüzdan devri (kaynak %s) sıfırlanamadı: %s",
                           kaynak, exc)

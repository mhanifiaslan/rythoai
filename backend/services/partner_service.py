"""Ortak (affiliate) kod sistemi (W7 → OP).

Veri modeli (yalnız Admin SDK yazar/okur; Firestore kurallarında eşleşmeyen
yol varsayılan kapalı — kural değişikliği gerekmez):

    partners/{partnerId}:  name, contact, active, createdAt, notes,
                           uid, rewardModel, rewardTry, sharePercent,
                           payoutCurrency, taxId, iban, minPayoutTry
    partnerCodes/{KOD}:    partnerId, bonusTokens, maxRedemptions,
                           redemptionCount, expiresAt, active, createdAt
    users/{uid}/private/attribution: code, partnerId, at   (TEK sefer)
    partnerQualifications/{uid}: partnerId, code, eventId, productId,
                           purchasedAt, maturesAt, status, rewardTry,
                           maturedAt, voidReason        (OP — kimlik = uid)
    partners/{id}/payouts/{n}: amount, currency, at, note

DÜRÜST MODEL: mağaza fiyatı koddan değiştirilemez — ortağa faydası, koddan
SONRAKİ satın almaların atfıdır. Kod satın almadan önce girilmiş olmalı;
sonradan girilen kod geçmiş geliri atfetmez.

ÖDÜL MODELİ (OP-turu): kullanıcıya ödül YOK. Ortak, getirdiği kişi İLK KEZ
abonelik aldığında sabit tutar kazanır. Kullanıcı ödülü yalnızca kodu ELLE
yazdırmak için gerekiyordu; Play Install Referrer ile kullanıcı hiçbir şey
yapmadığı için motive edilecek eylem de kalmadı.

`partnerQualifications` dokümanının kimliği **uid**'dir ve bu bilinçlidir:
"kullanıcı başına tek ödül" kuralını sorguyla değil YAPISAL olarak garanti
eder — yenileme de, ikinci abonelik de ikinci kayıt açamaz.

`rewardTry` hakediş anında dokümana KOPYALANIR. Panelden tutar değişince
geçmiş hakediş yeniden fiyatlanmaz; eski `sharePercent` anlık hesabı
(bu dosyanın önceki hâli) tam tersini yapıyor ve ödenmiş dönemleri bile
yeniden fiyatlandırıyordu.

Benzersizlik deseni: doküman kimliği = BÜYÜK HARF kod (usernames emsali).
"""
from __future__ import annotations

import datetime as dt
import logging
import re
import secrets
import string
from typing import Any

from core import firestore as firestore_client
from core import wallet

logger = logging.getLogger(__name__)

#: Kod biçimi: 4-24 karakter, harf/rakam/altçizgi/tire. Küçük girilse de
#: BÜYÜK saklanır ve aranır.
_KOD_DESENI = re.compile(r"^[A-Z0-9_-]{4,24}$")

#: Tek desteklenen ödül modeli. `sharePercent` alanı ve yüzde hesabı kodda
#: DURUYOR ama kullanılmıyor — model değişirse zemin hazır olsun diye.
REWARD_MODEL_FIXED = "fixed"

#: Ödül tutarının üst sınırı (₺). Tavan bir YAZIM HATASI kapısıdır: 30
#: yerine 3000 yazılırsa her kazanılan abone abonelik fiyatının (₺179,99)
#: on katına mal olur ve bunu fark ettirecek hiçbir sinyal yoktur.
#: `sharePercent`'in 0-90 tavanıyla (api/admin.py) aynı gerekçe.
MAX_REWARD_TRY = 500.0

#: Hakediş kesinleşme penceresi. Satın almadan bu kadar gün sonra, iade/
#: iptal gelmediyse ödül "kesinleşti" sayılır. Mağaza iade penceresini
#: kapsayacak kadar uzun, ortağı bekletmeyecek kadar kısa.
MATURATION_DAYS = 15

#: Hakediş durumları.
STATUS_PENDING = "pending"
STATUS_QUALIFIED = "qualified"
STATUS_VOID = "void"

#: Ödül DOĞURAN olay türleri. `INITIAL_PURCHASE` tek başına YETMEZ:
#: mağaza denemesi açılırsa denemeden ödüşen abone `TRIAL_CONVERTED` ile
#: gelir (api/billing.py:46-49) ve yalnız ilkine bakan kural onu kaçırır.
#: Jeton paketleri bu kümeye hiç giremez — paket alımları yalnızca
#: `NON_RENEWING_PURCHASE` olarak geliyor, yani ürün listesi gerekmiyor.
REWARD_EVENT_TYPES = frozenset({"INITIAL_PURCHASE", "TRIAL_CONVERTED"})

#: Bekleyen hakedişi İPTAL EDEN olaylar.
#:
#: `CANCELLATION` BİLEREK YOK: RevenueCat'te iptal "otomatik yenilemeyi
#: kapattı" demektir, para iadesi değil — kullanıcı dönem sonuna kadar
#: erişimini sürdürür ve o ayın parası bizde kalır. Ortak o aboneyi
#: gerçekten kazandı; iptali ceza saymak haksız olurdu.
#:
#: `EXPIRATION` ise 15 günlük pencere içinde anormaldir (aylık abonelik
#: 30 gün sürer): erken sona erme pratikte iade ya da tahsilat hatasıdır.
VOID_EVENT_TYPES = frozenset({"REFUND", "EXPIRATION"})


class RedeemError(Exception):
    """Kod kullanım hatası; `status` HTTP koduna eşlenir."""

    def __init__(self, status: int, reason: str):
        super().__init__(reason)
        self.status = status
        self.reason = reason


def normalize_code(code: str) -> str:
    kod = (code or "").strip().upper()
    if not _KOD_DESENI.match(kod):
        raise RedeemError(400, "invalid_format")
    return kod


def generate_code(prefix: str = "") -> str:
    """Panel için rastgele kod: OKUNAKLI alfabe (0/O, 1/I karışmaz)."""
    alfabe = "".join(c for c in string.ascii_uppercase + string.digits
                     if c not in "01OIL")
    govde = "".join(secrets.choice(alfabe) for _ in range(8))
    kod = f"{prefix.strip().upper()}{govde}" if prefix else govde
    return normalize_code(kod)


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def redeem(uid: str, raw_code: str) -> dict[str, Any]:
    """Kodu kullanır: atıf yazar + bonus jetonu yükler.

    Transaction içinde: (a) kod aktif + süresi geçmemiş + limiti dolmamış,
    (b) kullanıcının attribution'ı YOK (tek sefer — varsa 409),
    (c) sayaç artar, atıf yazılır. Bonus, transaction başarıyla bittikten
    sonra cüzdana yüklenir (kendi defter kimliğiyle idempotent).
    """
    kod = normalize_code(raw_code)
    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")

    kod_ref = client.collection("partnerCodes").document(kod)
    atif_ref = (client.collection("users").document(uid)
                .collection("private").document("attribution"))

    from google.cloud import firestore as gcf

    transaction = client.transaction()

    @gcf.transactional
    def _run(txn) -> dict[str, Any]:
        # Firestore işlemi TÜM okumaları yazımlardan önce ister; sıra bu
        # yüzden kod → ortak → atıf.
        kod_anlik = kod_ref.get(transaction=txn)
        if not kod_anlik.exists:
            raise RedeemError(404, "not_found")
        veri = kod_anlik.to_dict() or {}
        if veri.get("active") is not True:
            raise RedeemError(400, "inactive")
        son = veri.get("expiresAt")
        if son is not None and hasattr(son, "timestamp") \
                and son.timestamp() < _now().timestamp():
            raise RedeemError(400, "expired")
        limit = veri.get("maxRedemptions")
        sayac = int(veri.get("redemptionCount") or 0)
        if limit is not None and sayac >= int(limit):
            raise RedeemError(400, "exhausted")

        # Ortak kendi kodunu kendi hesabında kullanamaz. Ödül gerçek para
        # olduğu için bu kapı olmadan ortak kendi kodunu girip kendine
        # abone olarak doğrudan ödeme üretebilirdi. (Ekonomik olarak
        # zararına — ₺179,99 ödeyip ₺30 kazanır — ama iade yoluyla
        # çevrilebilir; kapı o yüzden var.)
        partner_id = veri.get("partnerId")
        if partner_id:
            ortak_anlik = (client.collection("partners")
                           .document(str(partner_id)).get(transaction=txn))
            if getattr(ortak_anlik, "exists", False):
                if (ortak_anlik.to_dict() or {}).get("uid") == uid:
                    raise RedeemError(403, "self_referral")

        atif_anlik = atif_ref.get(transaction=txn)
        if atif_anlik.exists:
            # Tek sefer: kullanıcı ikinci bir kod kullanamaz — atıf
            # sonradan değiştirilemesin (ortaklar arası çekişme kapısı).
            raise RedeemError(409, "already_redeemed")

        txn.update(kod_ref, {"redemptionCount": sayac + 1})
        txn.set(atif_ref, {"code": kod,
                           "partnerId": veri.get("partnerId"),
                           "at": _now()})
        return {"code": kod,
                "partnerId": veri.get("partnerId"),
                "bonusTokens": int(veri.get("bonusTokens") or 0)}

    sonuc = _run(transaction)

    bonus = sonuc["bonusTokens"]
    if bonus > 0:
        wallet.credit_promo(uid, kod, bonus)

    logger.info("Kod kullanıldı: uid=%s kod=%s ortak=%s bonus=%d",
                uid, kod, sonuc["partnerId"], bonus)
    return sonuc


# ---------------------------------------------------------------------------
# Hakediş (OP): doğuş → olgunlaşma → iptal
# ---------------------------------------------------------------------------

def _hakedis_ref(client, uid: str):
    return client.collection("partnerQualifications").document(uid)


def open_qualification(client, uid: str, partner_id: str, *,
                       event_id: str, product_id: Any,
                       purchased_at: dt.datetime) -> bool:
    """İlk abonelik için bekleyen hakediş açar. Döner: açıldı mı.

    ASLA FIRLATMAZ. Ödül yazımı satın alma borusunu düşürmemeli — para
    zaten alındı, ortaklık muhasebesi ikincil bir defterdir.

    İki değişmez:
    * Doküman kimliği `uid` → aynı kullanıcı için İKİNCİ kayıt imkânsız.
      Yenileme, ikinci abonelik, hatta farklı bir ortak — hepsi düşer.
    * `.create()` kullanılır (`create_code`'daki `partnerCodes` deseni):
      webhook tekrarı çakışır ve sessizce geçilir.

    Tutar dokümana KOPYALANIR: panelden ödül değişince geçmiş hakediş
    yeniden fiyatlanmaz.
    """
    try:
        ortak_anlik = (client.collection("partners")
                       .document(str(partner_id)).get())
        if not getattr(ortak_anlik, "exists", False):
            return False
        ortak = ortak_anlik.to_dict() or {}
        if ortak.get("active") is not True:
            # Pasif ortak yeni hakediş kazanmaz; geçmişi durur.
            return False
        if ortak.get("rewardModel", REWARD_MODEL_FIXED) != REWARD_MODEL_FIXED:
            return False
        try:
            odul = _rewardi_dogrula(ortak.get("rewardTry"))
        except RedeemError:
            logger.warning("Ortak %s icin gecersiz rewardTry: %r",
                           partner_id, ortak.get("rewardTry"))
            return False

        atif = (client.collection("users").document(uid)
                .collection("private").document("attribution").get())
        kod = (atif.to_dict() or {}).get("code") if getattr(
            atif, "exists", False) else None

        _hakedis_ref(client, uid).create({
            "partnerId": str(partner_id),
            "code": kod,
            "eventId": event_id,
            "productId": product_id,
            "purchasedAt": purchased_at,
            "maturesAt": purchased_at + dt.timedelta(days=MATURATION_DAYS),
            "status": STATUS_PENDING,
            "rewardTry": odul,
            "createdAt": _now(),
        })
        logger.info("Hakedis acildi: uid=%s ortak=%s odul=%.2f",
                    uid, partner_id, odul)
        return True
    except Exception as exc:
        # `create` zaten varsa AlreadyExists atar — beklenen ve sessiz.
        logger.debug("Hakedis acilmadi (uid=%s): %s", uid, exc)
        return False


def void_qualification(client, uid: str, reason: str) -> bool:
    """Bekleyen hakedişi iptal eder (iade/erken sona erme). ASLA FIRLATMAZ.

    `qualified` olmuşa DOKUNMAZ: o tutar ödenmiş sayılır ve düzeltmesi
    panelden negatif ödeme kaydıyla yapılır — geçmişi sessizce değiştirmek,
    ortağın gördüğü bakiyeyi açıklamasız oynatmak olurdu.
    """
    try:
        ref = _hakedis_ref(client, uid)
        anlik = ref.get()
        if not getattr(anlik, "exists", False):
            return False
        if (anlik.to_dict() or {}).get("status") != STATUS_PENDING:
            return False
        ref.update({"status": STATUS_VOID, "voidReason": reason,
                    "voidedAt": _now()})
        logger.info("Hakedis iptal: uid=%s sebep=%s", uid, reason)
        return True
    except Exception as exc:
        logger.warning("Hakedis iptal edilemedi (uid=%s): %s", uid, exc)
        return False


def _iade_var_mi(client, uid: str, sonra: dt.datetime) -> bool:
    """`sonra`dan beri bu kullanıcıda iade/erken-sona-erme olayı var mı?

    Webhook kaçırılmış olabilir diye olgunlaşmada ikinci kez bakılır.
    `revenueEvents(uid ASC, at DESC)` composite indeksi ZATEN var
    (infra/firestore.indexes.json), yeni indeks gerekmiyor.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter
    try:
        for g in (client.collection("revenueEvents")
                  .where(filter=FieldFilter("uid", "==", uid))
                  .where(filter=FieldFilter("at", ">=", sonra))
                  .stream()):
            if (g.to_dict() or {}).get("eventType") in VOID_EVENT_TYPES:
                return True
    except Exception as exc:
        # Sorgu düşerse hakedişi kesinleştirmek YERİNE beklemede bırakmak
        # daha güvenli: para ödemesi tek yönlüdür.
        logger.warning("Iade taramasi dustu (uid=%s): %s", uid, exc)
        raise
    return False


def mature_qualifications(now: dt.datetime | None = None,
                          limit: int = 500) -> dict[str, int]:
    """Süresi dolan bekleyen hakedişleri kesinleştirir ya da iptal eder.

    Günlük Cloud Scheduler işi çağırır. Sorgu "≥15 gün olmuş VE hâlâ
    beklemede" biçiminde olduğu için kaçırılan bir koşu kendiliğinden
    telafi edilir — zamanlayıcıda yeniden deneme yok
    (infra/create-scheduler.ps1 bunu açıkça yazıyor).

    İdempotans durum alanından gelir, `Increment`'ten değil: iki kez koşan
    iş aynı dokümanı ikinci kez `pending` bulamaz.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")
    simdi = now or _now()
    sayac = {"taranan": 0, "kesinlesen": 0, "iptal": 0, "atlanan": 0}

    for anlik in (client.collection("partnerQualifications")
                  .where(filter=FieldFilter("status", "==", STATUS_PENDING))
                  .where(filter=FieldFilter("maturesAt", "<=", simdi))
                  .limit(limit).stream()):
        sayac["taranan"] += 1
        uid = anlik.id
        veri = anlik.to_dict() or {}
        try:
            alindi = veri.get("purchasedAt") or simdi
            if _iade_var_mi(client, uid, alindi):
                anlik.reference.update({"status": STATUS_VOID,
                                        "voidReason": "refund_detected",
                                        "voidedAt": simdi})
                sayac["iptal"] += 1
                continue
            anlik.reference.update({"status": STATUS_QUALIFIED,
                                    "maturedAt": simdi})
            sayac["kesinlesen"] += 1
        except Exception as exc:
            # Beklemede bırak: bir sonraki koşu yeniden dener.
            logger.warning("Hakedis olgunlastirilamadi (uid=%s): %s",
                           uid, exc)
            sayac["atlanan"] += 1

    logger.info("Hakedis olgunlastirma: %s", sayac)
    return sayac


# ---------------------------------------------------------------------------
# Panel CRUD yardımcıları (admin.py çağırır; hepsi Admin SDK)
# ---------------------------------------------------------------------------

def list_partners() -> list[dict[str, Any]]:
    client = firestore_client.get_client()
    if client is None:
        return []
    sonuc = []
    for anlik in client.collection("partners").stream():
        veri = anlik.to_dict() or {}
        veri["id"] = anlik.id
        sonuc.append(veri)
    return sonuc


def create_partner(name: str, contact: str, share_percent: float,
                   notes: str = "", *, reward_try: float = 30.0,
                   uid: str | None = None) -> dict[str, Any]:
    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")
    ref = client.collection("partners").document()
    veri = {"name": name.strip(), "contact": contact.strip(),
            "sharePercent": float(share_percent), "active": True,
            "notes": notes.strip(), "createdAt": _now(),
            # OP: tutar ORTAK BAŞINA ve panelden düzenlenir; kodda sabit
            # değil. Varsayılan yalnızca bir başlangıç noktasıdır.
            "rewardModel": REWARD_MODEL_FIXED,
            "rewardTry": _rewardi_dogrula(reward_try),
            # Ortağın kendi Firebase hesabı: hem kendi panelini görmesi
            # hem kendi kodunu kullanamaması bu bağa dayanıyor.
            "uid": (uid or "").strip() or None,
            "payoutCurrency": "TRY"}
    ref.set(veri)
    veri["id"] = ref.id
    return veri


def _rewardi_dogrula(deger: Any) -> float:
    """Ödül tutarını sınırlar; bozuk/absürt değer RedeemError verir.

    Tavan kasten dar (`MAX_REWARD_TRY`): bu alan gerçek para ödemesi
    üretiyor ve yanlış yazılmış bir sıfır panelde göze çarpmaz.
    """
    try:
        sayi = float(deger)
    except (TypeError, ValueError):
        raise RedeemError(400, "invalid_reward")
    if not (0 < sayi <= MAX_REWARD_TRY):
        raise RedeemError(400, "invalid_reward")
    return round(sayi, 2)


def update_partner(partner_id: str, alanlar: dict[str, Any]) -> None:
    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")
    izinli = {k: v for k, v in alanlar.items()
              if k in {"name", "contact", "sharePercent", "active", "notes",
                       # OP: panelden düzenlenebilen yeni alanlar.
                       "uid", "rewardTry", "payoutCurrency", "taxId", "iban",
                       "minPayoutTry"}}
    if "rewardTry" in izinli:
        izinli["rewardTry"] = _rewardi_dogrula(izinli["rewardTry"])
    if "uid" in izinli:
        izinli["uid"] = (str(izinli["uid"] or "").strip() or None)
    if izinli:
        client.collection("partners").document(partner_id).update(izinli)


def create_code(partner_id: str, code: str | None, bonus_tokens: int,
                max_redemptions: int | None,
                expires_at: dt.datetime | None) -> dict[str, Any]:
    """Kod üretir/rezerve eder. `create()` var olan kodda düşer —
    usernames benzersizlik deseni: yarışta ikinci istek hata alır."""
    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")
    kod = normalize_code(code) if code else generate_code()
    veri = {"partnerId": partner_id,
            "bonusTokens": int(bonus_tokens),
            "maxRedemptions": (int(max_redemptions)
                               if max_redemptions is not None else None),
            "redemptionCount": 0,
            "expiresAt": expires_at,
            "active": True,
            "createdAt": _now()}
    try:
        client.collection("partnerCodes").document(kod).create(veri)
    except Exception:
        raise RedeemError(409, "code_taken")
    veri["code"] = kod
    return veri


def partner_detail(partner_id: str) -> dict[str, Any]:
    """Ortak + kodları + atfedilen gelir + hakediş + ödemeler."""
    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")

    from google.cloud.firestore_v1.base_query import FieldFilter

    anlik = client.collection("partners").document(partner_id).get()
    if not getattr(anlik, "exists", False):
        raise RedeemError(404, "not_found")
    ortak = anlik.to_dict() or {}
    ortak["id"] = partner_id

    kodlar = []
    for k in (client.collection("partnerCodes")
              .where(filter=FieldFilter("partnerId", "==", partner_id))
              .stream()):
        veri = k.to_dict() or {}
        veri["code"] = k.id
        kodlar.append(veri)

    # Huninin ilk basamağı kodların sayacından gelir — atıf dokümanları
    # kullanıcı altında dağınık olduğu için ayrıca taranmaz (bedava sayı).
    gelen = sum(int(k.get("redemptionCount") or 0) for k in kodlar)

    # Hakediş: artık gelir taramasından DEĞİL, hakediş kayıtlarından.
    # Her kayıt kendi dondurulmuş `rewardTry`sini taşır.
    huni = {STATUS_PENDING: 0, STATUS_QUALIFIED: 0, STATUS_VOID: 0}
    hakedis = 0.0
    bekleyen_tutar = 0.0
    for h in (client.collection("partnerQualifications")
              .where(filter=FieldFilter("partnerId", "==", partner_id))
              .stream()):
        veri = h.to_dict() or {}
        durum = veri.get("status") or STATUS_PENDING
        huni[durum] = huni.get(durum, 0) + 1
        tutar = float(veri.get("rewardTry") or 0)
        if durum == STATUS_QUALIFIED:
            hakedis += tutar
        elif durum == STATUS_PENDING:
            bekleyen_tutar += tutar

    # Atfedilen gelir YALNIZ bilgi amaçlı (ödülü artık belirlemiyor).
    # ⚠️ `environment` ve `monetary` süzgeçleri ŞART: canlıda 1756 SANDBOX
    # olayı var ve süzülmezse panel sahte geliri gerçekmiş gibi gösterir.
    brut = 0.0
    olay = 0
    for g in (client.collection("revenueEvents")
              .where(filter=FieldFilter("partnerId", "==", partner_id))
              .stream()):
        veri = g.to_dict() or {}
        if veri.get("environment") != "PRODUCTION":
            continue
        if veri.get("monetary") is not True:
            continue
        fiyat = float(veri.get("price") or 0)
        brut += -abs(fiyat) if veri.get("eventType") == "REFUND" else fiyat
        olay += 1

    odenen = 0.0
    odemeler = []
    for o in (client.collection("partners").document(partner_id)
              .collection("payouts").stream()):
        veri = o.to_dict() or {}
        veri["id"] = o.id
        odemeler.append(veri)
        odenen += float(veri.get("amount") or 0)

    return {"partner": ortak, "codes": kodlar,
            # Huni — sahibin sorduğu "kaç kişi geldi, kaçı alım yaptı".
            "referredUsers": gelen,
            "pendingCount": huni[STATUS_PENDING],
            "qualifiedCount": huni[STATUS_QUALIFIED],
            "voidCount": huni[STATUS_VOID],
            # Para (₺) — kesinleşen üzerinden.
            "earnedTry": round(hakedis, 2),
            "pendingTry": round(bekleyen_tutar, 2),
            "paidTry": round(odenen, 2),
            "balanceTry": round(hakedis - odenen, 2),
            # Bilgi amaçlı gelir (süzülmüş).
            "attributedGrossUsd": round(brut, 2),
            "attributedEvents": olay,
            "payouts": odemeler}


def add_payout(partner_id: str, amount: float, currency: str,
               note: str = "") -> dict[str, Any]:
    """Ödeme kaydı. Pozitif = ortağa ödendi, negatif = geri alındı.

    Bakiye kapısı: bakiyeden FAZLA pozitif ödeme yazılamaz. Ödeme defteri
    gerçek para transferinin aynasıdır; aynanın bakiyeyi aşması, ya yanlış
    tutar girildiğini ya da hakedişin iptal edildiğini gösterir.

    Negatif kayıt BİLEREK serbest: `qualified` olmuş bir hakediş sonradan
    iade edilirse geçmişi sessizce değiştirmek yerine düzeltme kaydı
    açılır — ortağın gördüğü bakiye açıklanabilir kalır.
    """
    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")

    tutar = round(float(amount), 2)
    if tutar == 0:
        raise RedeemError(400, "invalid_amount")
    if tutar < 0 and not note.strip():
        # Düzeltme kaydı gerekçesiz olamaz.
        raise RedeemError(400, "reason_required")
    if tutar > 0:
        mevcut = partner_detail(partner_id)
        bakiye = float(mevcut.get("balanceTry") or 0)
        if tutar > bakiye + 0.005:
            raise RedeemError(400, "exceeds_balance")

    ref = (client.collection("partners").document(partner_id)
           .collection("payouts").document())
    veri = {"amount": tutar, "currency": currency.strip().upper(),
            "note": note.strip(), "at": _now()}
    ref.set(veri)
    veri["id"] = ref.id
    return veri


# ---------------------------------------------------------------------------
# Ortağın KENDİ paneli (api/partners.py çağırır)
# ---------------------------------------------------------------------------

def partner_id_for_uid(uid: str) -> str | None:
    """Bu Firebase hesabı hangi ortak kaydına bağlı? Yoksa None."""
    from google.cloud.firestore_v1.base_query import FieldFilter
    client = firestore_client.get_client()
    if client is None:
        return None
    for anlik in (client.collection("partners")
                  .where(filter=FieldFilter("uid", "==", uid))
                  .limit(1).stream()):
        return anlik.id
    return None


def partner_self_view(partner_id: str) -> dict[str, Any]:
    """Ortağa gösterilecek DAR görünüm.

    `partner_detail`'in alt kümesi: işletmeye ait hiçbir sayı (atfedilen
    gelir, diğer ortaklar, kullanıcı kimlikleri) DIŞARI ÇIKMAZ. Ortak
    yalnız kendi hunisini, bakiyesini ve kodlarını görür.
    """
    tam = partner_detail(partner_id)
    ortak = tam["partner"]
    return {
        "name": ortak.get("name"),
        "active": ortak.get("active"),
        "rewardTry": ortak.get("rewardTry"),
        "payoutCurrency": ortak.get("payoutCurrency") or "TRY",
        "codes": [{"code": k.get("code"),
                   "redemptionCount": k.get("redemptionCount"),
                   "active": k.get("active"),
                   "expiresAt": k.get("expiresAt")}
                  for k in tam["codes"]],
        "referredUsers": tam["referredUsers"],
        "pendingCount": tam["pendingCount"],
        "qualifiedCount": tam["qualifiedCount"],
        "earnedTry": tam["earnedTry"],
        "pendingTry": tam["pendingTry"],
        "paidTry": tam["paidTry"],
        "balanceTry": tam["balanceTry"],
        "payouts": [{"amount": o.get("amount"), "currency": o.get("currency"),
                     "at": o.get("at"), "note": o.get("note")}
                    for o in tam["payouts"]],
    }

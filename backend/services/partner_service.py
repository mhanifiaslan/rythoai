"""Ortak (affiliate) kod sistemi (W7 → OP).

Veri modeli (yalnız Admin SDK yazar/okur; Firestore kurallarında eşleşmeyen
yol varsayılan kapalı — kural değişikliği gerekmez):

    partners/{partnerId}:  name, contact, active, createdAt, notes,
                           uid, rewardModel, rewardTry, sharePercent,
                           payoutCurrency, taxId, iban, minPayoutTry
    partnerCodes/{KOD}:    partnerId, bonusTokens, maxRedemptions,
                           redemptionCount, expiresAt, active, createdAt,
                           clickCount                   (koşan tıklama toplamı)
    partnerCodes/{KOD}/clicks/{YYYY-MM-DD}: count       (kimliksiz gün sayacı)
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
yazdırmak için gerekiyordu; kod artık otomatik geldiği için motive edilecek
eylem de kalmadı.

`partnerCodes.bonusTokens` alanı veri modelinde DURUYOR ama artık sıfır
dışını kabul etmiyor (`create_code`), yani UYUYAN bir alandır — silinmedi
çünkü o karardan önce açılmış kodlar hâlâ canlı ve verdikleri sözü tutmak
zorunda. Kilidin gerekçesi alanın kendisi değil BEYAN: `web/ortaklik.html`
herkese açık biçimde "kullanıcıya jeton ya da indirim vermez" yazıyor ve
tek bir koda girilmiş bonus bu cümleyi yalanlar — çelişki yalnız o ortağın
gelirinde görünür, hiçbir ekranda görünmez. Model geri açılırsa tanıtım
sayfası VE kullanım şartları da değişmek zorundadır.

KODUN BU UCA GELİŞ YOLLARI (istemci tarafı, Android):
  1. Kurulum:  ortak linki → `web/r/index.html` → Play `&referrer=` →
     Install Referrer → `POST /billing/redeem-code`
  2. Kurulu uygulama: ortak linki → App Links (`/r/` intent-filter) →
     aynı uç
İkisi de tek bir SharedPreferences bayrağı paylaşır, yani aynı cihazda iki
kez denenmez. ⚠️ Bu dosya "kod elle girilmez" varsayımına yazılmıştır ama
uç ELLE girişe de açıktır (paywall'da kod alanı ileride geri gelebilir);
bu yüzden `redeem` içindeki doğrulama ve kendi-kodunu-kullanma kapısı
istemciye hiç güvenmez.

iOS'ta Install Referrer'ın dengi YOK; orada çözüm App Store Custom Product
Page + derin bağlantı olacak ve BU UÇ değişmeden çalışacak.

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

#: Pasif ortağın KESİNLEŞMEMİŞ hakedişinin iptal sebebi. Kullanım şartları
#: "programdan çıkarılma hâlinde kesinleşmemiş hakediş düşer" diyor ve bu
#: sebep o maddenin koddaki karşılığıdır — sebep alanı olmadan pasif iptali
#: iade iptalinden ayırt edilemezdi ve ortağa neden düştüğü anlatılamazdı.
VOID_REASON_PARTNER_INACTIVE = "partner_inactive"

#: Ödemelerin varsayılan para birimi. `create_partner` alanı HER ZAMAN
#: yazıyor, yani boş olması normal yol değil — elle açılmış ya da alan
#: eklenmeden önce yazılmış bir kayıttır. Öyle bir kayıtta varsayılana
#: düşmek, kapının kendisini atlamaktan iyidir.
DEFAULT_PAYOUT_CURRENCY = "TRY"

#: GEÇİCİ hata sebepleri: istek yeniden denenirse geçebilir; kalıcı bir
#: YETKİ ya da VERİ sorunu DEĞİL. `core/firestore.get_client()`in ``None``
#: dönüşü bu sınıftandır. Gerekçesi tam olarak şu: o dosyada kimlik
#: bilgisi yoklaması BAŞARISIZ olduğunda kalıcı mandal (`_failed`) BİLEREK
#: kurulmuyor — kimlik bilgisinin o an görünmemesi soğuk bir Cloud Run
#: örneğinde normaldir ve ilk sürümde mandal orada kurulduğu için webhook'lar
#: instance ömrü boyunca 500 dönmüştü. Mandal yalnız istemci GERÇEKTEN
#: kurulamazsa kurulur; o hâlde bu örnek artık toparlanmaz ama istek başka
#: bir örneğe düşebilir, yani "yeniden dene" cevabı yine doğru olandır.
#: Uçlar bu sebepleri KALICI bir hata koduna değil
#: 503'e çevirir (bkz. `api/partners.py`): geçici bir hâl kalıcı yetki
#: kaybı ya da sunucu kusuru gibi görünürse istemci yanlış karar verir
#: (zorunlu çıkış, jenerik 404).
TRANSIENT_REASONS = frozenset({"unavailable"})

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

#: Tıklama serisinin uzunluğu (gün). Panodaki tek zaman serisi bu.
CLICK_SERIES_DAYS = 30

#: `get_all` başına en çok kaç doküman referansı. Seri, ortağın kod sayısı
#: × 30 doküman okur; 20 kodlu bir ortakta tek çağrıda 600 referans olurdu
#: ve BatchGetDocuments'in pratik sınırına dayanmak, panonun kod sayısı
#: arttıkça SESSİZCE düşmesi demek. Parçalama sınırı test etmiyor —
#: sınırın var olduğunu garanti ediyor.
_GET_ALL_CHUNK = 300


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


# ---------------------------------------------------------------------------
# Huninin TEPESİ: tıklama telemetrisi
# ---------------------------------------------------------------------------
#
# Neden var: pano tıklamayı hiç ölçmüyordu, yani ortak yalnız hunisinin
# SONUCUNU görüyordu. Linkini 500 kişiye gönderen ortak "3" görür ve
# tanıtımının işe yarayıp yaramadığını bilemez — dönüşüm oranı da tıklama
# olmadan hesaplanamaz (bölen yok).
#
# ⚠️ GİZLİLİK ÇİZGİSİ (pazarlık yok): bu modülün YAZDIĞI kayıtta IP,
# User-Agent, kimlik ve çerez YOK — Firestore'a inen tek şey bir SAYAÇ.
#
# Çizgi bir tur boyunca MUTLAK yazılıydı ("ziyaretçiye ait tek bir bayt bile
# yazılmaz") ve o gerekçe yanlıştı. Ölçülen hâl: aynı istek kota katmanından
# geçiyor ve `core/ratelimit.py` tıklama ucunda kova anahtarını ziyaretçinin
# IP'sinden kuruyor (`_client_key(..., sadece_ip=True)`; uç kimliksiz olduğu
# için `Authorization` BİLEREK dinlenmiyor, yoksa istemci her istekte yeni
# kova açıp tavanı yok ederdi). O anahtar middleware'in BELLEĞİNDEKİ kayan
# pencere sözlüğünde duruyor (`RateLimitMiddleware._hits`): süreç ömürlü,
# hiçbir kalıcı yere inmez. Ne kadar kalabildiği ölçüldü (yeniden
# ölçüldü 2026-10-02, `ratelimit.py`): kova penceresi 60 sn ama budama
# YALNIZ yeni bir istek geldiğinde ve en çok beş dakikada bir koşuyor,
# yani anahtar ~6 dakika yaşayabilir — ve o süreçte hiç istek gelmezse
# HİÇ silinmez (sözlük süreç ölene kadar durur). Bir tur boyunca buraya
# "beş dakika" yazılıydı; sınır beş dakika DEĞİL, ölçülen hâl bu.
# Ayrıca bu uca ÖZEL değil: kimliksiz her istek böyle sayılıyor.
# Aynı ayrım `api/partners.py::click` gövdesinde de yazılı; ikisi
# birlikte okunur.
#
# Çizginin ölçülmüş hâli: KALICI kayıt sayaçtan ibarettir. Bu yüzden
# "tekil ziyaretçi" de ölçülemez — tekillik ancak SAKLANAN bir işaretle
# ölçülür ve o işaret kişisel veridir. Pano bu sayıyı TIKLAMA diye sunar,
# ziyaretçi diye SUNMAZ.
#
# Veri: `partnerCodes/{KOD}/clicks/{YYYY-MM-DD}` → {count}
#   Gün başına ayrı doküman, tek dokümanda büyüyen bir harita DEĞİL: harita
#   sınırsız büyür (1 MB doküman tavanına yürür), ayrı doküman hem sınırlı
#   hem `Increment` ile yarış-güvenli.
#
# Buna EK olarak `partnerCodes/{KOD}.clickCount` koşan toplam tutulur.
# Gerekçe: toplam tıklamayı gün dokümanlarını tarayarak bulmak, panoyu her
# geçen gün yavaşlatır (kod başına yılda 365 doküman) ve bu yavaşlama
# sinsidir — bugün 2 okuma, iki yıl sonra 730. Toplam ile gün sayacı AYNI
# toplu yazımda (atomik) artar, yoksa ikisi sessizce ayrışır ve ekrandaki
# "toplam" gün serisinin toplamını tutmaz.

def _gun_kimligi(an: dt.date) -> str:
    """Gün dokümanının kimliği — **UTC** takvim günü.

    UTC seçimi keyfî değil: bu programdaki her tarih (`purchasedAt`,
    `maturesAt`, ödeme `at`) UTC üretiliyor ve tıklamayı yerel takvime
    almak, panoda yan yana duran iki seriyi farklı takvimlerde sayardı.
    Günü SUNUCU koyar (sayfa yalnız kodu gönderir), yani tek bir saat var.

    BİLİNEN SINIR: Türkiye UTC+3, yani yerel 00:00-03:00 arası tıklamalar
    önceki günün çubuğuna düşer. Ortağın gördüğü gün toplamı bu kadar
    kayabilir; kabul edildi çünkü alternatifi iki takvimi karıştırmak.
    """
    return an.strftime("%Y-%m-%d")


def record_click(raw_code: str) -> bool:
    """Ortak linkinin bir kez açıldığını sayar. **ASLA FIRLATMAZ.**

    Dönen değer yalnız log ve test içindir: uç her hâlde 204 döner, çünkü
    telemetri ziyaretçinin mağazaya gitmesini ENGELLEMEMELİ. Sayaç kayıpsa
    kaybedilen şey bir istatistik, bir kurulum değil.

    Uç KİMLİKSİZ ve herkese açık; üç kapı bu yüzden ZORUNLU:

    1. Biçim (`normalize_code`) — desene uymayan kod hiç yazıma girmez.
    2. Kod GERÇEKTEN var mı. Bu kapı olmadan herkes uydurduğu kodla istek
       atıp sınırsız Firestore dokümanı yazdırabilir: hem fatura hem çöp
       veri. Bir okumaya değer.
    3. Her hata yutulur (best-effort).

    Kodun VAR OLMADIĞI bilgisi çağırana SIZDIRILMAZ (uç 404 değil 204
    döner): ayrım, kod tahmin etmeyi ucuz bir oyuna çevirir.

    Kodun `active` olması ŞART DEĞİL — bilinçli. Kapatılmış bir kodun linki
    internette durmaya devam eder ve o linke gelen trafik GERÇEKTEN olmuş
    bir olaydır; saymamak, ortağın tanıtımını görünmez kılar. Kapalı kod
    yalnız `redeem`i düşürür, tıklamayı değil.
    """
    try:
        kod = normalize_code(raw_code)
    except RedeemError:
        return False

    client = firestore_client.get_client()
    if client is None:
        return False

    try:
        from google.cloud import firestore as gcf

        kod_ref = client.collection("partnerCodes").document(kod)
        if not getattr(kod_ref.get(), "exists", False):
            return False

        gun = _gun_kimligi(_now())
        toplu = client.batch()
        # Gün sayacı `set(merge=True)`: doküman ilk tıklamada doğar.
        toplu.set(kod_ref.collection("clicks").document(gun),
                  {"count": gcf.Increment(1)}, merge=True)
        # Koşan toplam `update`: kod dokümanı YUKARIDA var olduğu ölçüldü.
        # `set(merge=True)` olsaydı, arada silinmiş bir kodu yalnız
        # `clickCount` alanıyla yeniden DOĞURUR ve panelde sahibi olmayan
        # bir kod belirirdi.
        toplu.update(kod_ref, {"clickCount": gcf.Increment(1)})
        toplu.commit()
        return True
    except Exception as exc:
        # Uyarı seviyesi: ölçüm kaybı sessiz kalmasın ama isteği düşürmesin.
        logger.warning("Tiklama sayilamadi (kod=%s): %s", kod, exc)
        return False


def _tiklama_serisi(client, kodlar: list[dict[str, Any]],
                    bugun: dt.date | None = None,
                    gun_sayisi: int = CLICK_SERIES_DAYS
                    ) -> list[dict[str, Any]]:
    """Son N günün günlük tıklaması — eskiden yeniye, EKSİK GÜNLER 0.

    Eksik günü atlamak yerine 0 yazmak bir sunum kararı değil doğruluk
    kararı: delikli bir seri panoda "veri kayboldu" gibi görünür ve
    ortağın okuduğu şey "o gün tıklama olmadı" değil "bu pano bozuk" olur.

    Okuma yolu: 30 belirli gün dokümanı KİMLİKLE çekilir (`get_all`),
    sorgu kurulmaz. Yani hiçbir bileşik indeks gerekmez ve maliyet kod
    başına SABİT 30 okumadır — `clicks` alt koleksiyonunu taramak
    (gün sayısı büyüdükçe artan maliyet) bilinçli olarak seçilmedi.

    Aynı gün birden çok kodda görünür ve TOPLANIR; bu yüzden anlık görüntü
    hangi koda ait olduğu bilinmeden, yalnız doküman kimliği (gün)
    üzerinden eşleştirilebiliyor.
    """
    bugun = bugun or _now().date()
    gunler = [_gun_kimligi(bugun - dt.timedelta(days=i))
              for i in range(gun_sayisi - 1, -1, -1)]
    sayaclar = dict.fromkeys(gunler, 0)

    referanslar = [
        client.collection("partnerCodes").document(str(k.get("code")))
        .collection("clicks").document(gun)
        for k in kodlar if k.get("code")
        for gun in gunler]

    for bas in range(0, len(referanslar), _GET_ALL_CHUNK):
        for anlik in client.get_all(referanslar[bas:bas + _GET_ALL_CHUNK]):
            if not getattr(anlik, "exists", False):
                continue
            gun = getattr(anlik, "id", None)
            if gun in sayaclar:
                sayaclar[gun] += int((anlik.to_dict() or {}).get("count") or 0)

    return [{"day": gun, "count": sayaclar[gun]} for gun in gunler]


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
                ortak_uid = (ortak_anlik.to_dict() or {}).get("uid")
                if not ortak_uid:
                    # Kapı `uid` karşılaştırmasına dayanıyor; alan boşsa
                    # kapı O ORTAK İÇİN hiç çalışmaz ve `None == uid` asla
                    # tutmadığı için hiçbir iz de bırakmaz. Bu log o
                    # sessizliği kırıyor.
                    #
                    # 403 DEĞİL: uid'i henüz bağlanmamış eski bir ortak
                    # varsa onun TÜM atıflarını kırardı. Yeni ortakta uid
                    # artık zorunlu (`create_partner` + `api/admin.py`
                    # PartnerCreate); bu uyarı o zorunluluktan ÖNCE açılmış
                    # kayıtları görünür kılmak için duruyor.
                    logger.warning(
                        "Ortak %s icin uid bos: kendi-kodunu-kullanma "
                        "kapisi bu ortakta CALISMIYOR (kod=%s)",
                        partner_id, kod)
                elif ortak_uid == uid:
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
        # UYUYAN YOL: yeni kodlarda `bonusTokens` sıfır zorunlu (K-a,
        # `create_code` + uç), yani bu dal yalnız o karardan ÖNCE açılmış
        # kodlarda çalışır. Silinmedi çünkü o kodlar hâlâ canlı; verilmiş
        # sözü geri almak, kullanıcının gördüğü bakiyeyi açıklamasız
        # düşürmek olurdu. Model geri açılırsa `web/ortaklik.html` ve
        # kullanım şartları da güncellenmek zorundadır.
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


def _ortak_aktif_mi(client, partner_id: str,
                    onbellek: dict[str, bool]) -> bool:
    """Ortak aktif mi? Aynı koşuda ortak başına TEK okuma.

    Önbellek gerekli çünkü tek koşuda aynı ortağın birden çok hakedişi
    olgunlaşabilir ve döngü içinde aynı dokümanı N kez çekmek bedava değil.
    Koşu kısa ömürlü olduğu için okuma bayatlaması sorun değil: ortak
    koşunun ortasında pasifleşse bile bir sonraki günlük koşu yakalar.

    Doküman YOKSA aktif sayılmaz: silinmiş bir ortağa hakediş
    kesinleştirmek, ödenecek kimsesi olmayan bir borç yazmaktır.
    """
    if partner_id in onbellek:
        return onbellek[partner_id]
    aktif = False
    if partner_id:
        anlik = client.collection("partners").document(partner_id).get()
        if getattr(anlik, "exists", False):
            aktif = (anlik.to_dict() or {}).get("active") is True
    onbellek[partner_id] = aktif
    return aktif


def mature_qualifications(now: dt.datetime | None = None,
                          limit: int = 500) -> dict[str, int]:
    """Süresi dolan bekleyen hakedişleri kesinleştirir ya da iptal eder.

    Günlük Cloud Scheduler işi çağırır. Sorgu "≥15 gün olmuş VE hâlâ
    beklemede" biçiminde olduğu için kaçırılan bir koşu kendiliğinden
    telafi edilir — zamanlayıcıda yeniden deneme yok
    (infra/create-scheduler.ps1 bunu açıkça yazıyor).

    İdempotans durum alanından gelir, `Increment`'ten değil: iki kez koşan
    iş aynı dokümanı ikinci kez `pending` bulamaz.

    ⚠️ Ortağın `active` alanı BURADA da bakılır, yalnız `open_qualification`
    içinde değil: o yalnız YENİ hakedişi engeller, zaten açılmış olanı
    değil. Sorgu `status` + `maturesAt` süzdüğü için pasifleşme kaydın
    üstünden sessizce geçiyordu.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")
    simdi = now or _now()
    # `iptal` iade kaynaklı, `iptal_pasif` ortak kaynaklı: aynı sayaçta
    # toplanırsa mutabakatta "neden düştü" sorusu cevapsız kalır.
    sayac = {"taranan": 0, "kesinlesen": 0, "iptal": 0, "iptal_pasif": 0,
             "atlanan": 0}
    ortak_onbellek: dict[str, bool] = {}

    for anlik in (client.collection("partnerQualifications")
                  .where(filter=FieldFilter("status", "==", STATUS_PENDING))
                  .where(filter=FieldFilter("maturesAt", "<=", simdi))
                  .limit(limit).stream()):
        sayac["taranan"] += 1
        uid = anlik.id
        veri = anlik.to_dict() or {}
        try:
            # Programdan çıkarılan ortağın KESİNLEŞMEMİŞ hakedişi düşer
            # (kullanım şartlarındaki madde). Bu kapı olmadan ölçülen hâl:
            # kötüye kullanım yüzünden pasifleştirilen ortağın 5 gün önce
            # açılmış kaydı 10 gün sonra `qualified` oluyor, bakiyeye
            # giriyor ve ödeme kapısı ödemeye izin veriyordu — sahibi,
            # şartların "düştü" dediği parayı borç sanırdı.
            #
            # İade taramasından ÖNCE: sorgu gerektirmiyor ve sonuç aynı
            # (her iki yol da `void`), ucuz kapı önce çalışsın.
            if not _ortak_aktif_mi(client, str(veri.get("partnerId") or ""),
                                   ortak_onbellek):
                anlik.reference.update({
                    "status": STATUS_VOID,
                    "voidReason": VOID_REASON_PARTNER_INACTIVE,
                    "voidedAt": simdi})
                sayac["iptal_pasif"] += 1
                continue
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

def _kod_toplamlari(client) -> dict[str, list[int]]:
    """partnerId → [tıklama, kuran]. TEK koleksiyon akışı.

    `partnerId` alanı boş/eksik olan kod dokümanı atlanır: hangi ortağa
    yazılacağı bilinmeyen bir sayıyı bir ortağa yazmak, ölçüleni yanlış
    yere bağlamaktır. SİLİNMİŞ bir ortağa işaret eden kod ise toplanır ama
    kimse okumaz — listede o kimlik yok.
    """
    toplam: dict[str, list[int]] = {}
    for k in client.collection("partnerCodes").stream():
        veri = k.to_dict() or {}
        pid = str(veri.get("partnerId") or "").strip()
        if not pid:
            continue
        kutu = toplam.setdefault(pid, [0, 0])
        kutu[0] += int(veri.get("clickCount") or 0)
        kutu[1] += int(veri.get("redemptionCount") or 0)
    return toplam


def list_partners() -> list[dict[str, Any]]:
    """Ortak listesi + huninin İLK İKİ basamağı (`clicks`, `referredUsers`).

    İki sayı da partner dokümanında DURMUYOR; ikisi de kod dokümanlarının
    alanı (`clickCount`, `redemptionCount`). Toplama ORTAK BAŞINA sorguyla
    değil `partnerCodes` koleksiyonunun TEK akışıyla yapılıyor: N+1 aynı
    dokümanları okur ama sorgu sayısını ortak sayısıyla çarpar, yani
    panelin en sık açılan ekranı kayıt sayısıyla birlikte yavaşlar.
    Koleksiyon küçük kalıyor çünkü kod = KANAL, ortak = kişi.

    Ortak dokümanına koşan bir toplam YAZILMADI (öteki seçenek buydu):
    tıklama sayacı kimliksiz ve KOTALI bir uçtan geliyor (`record_click`)
    ve orada ikinci bir doküman güncellemek, en çok yazım alan yola
    ortak başına bir çekişme noktası daha koyardı. Okuma tarafı ucuz, yazma
    tarafı değil.

    Toplama DÜŞERSE anahtarlar yanıta HİÇ KONMAZ, 0 yazılmaz: 0 "ölçtük,
    hiç tıklama yok" demek ve panel çalışan bir tanıtımı ölmüş gibi
    gösterirdi (`partner_detail`in `clickSeries` doktrini — yokluk
    "bakılmadı").
    """
    client = firestore_client.get_client()
    if client is None:
        return []
    sonuc = []
    for anlik in client.collection("partners").stream():
        veri = anlik.to_dict() or {}
        veri["id"] = anlik.id
        sonuc.append(veri)
    try:
        toplam = _kod_toplamlari(client)
    except Exception as exc:
        # Liste ortağın KENDİSİNİ göstermeye devam eder: telemetri
        # okuması yüzünden yönetim ekranını hiç çizmemek, ölçülen zararı
        # ölçülmeyen bir kayıpla büyütmek olurdu.
        logger.warning("Ortak listesinde kod toplamlari okunamadi: %s", exc)
        return sonuc
    for veri in sonuc:
        tiklama, kuran = toplam.get(veri["id"], [0, 0])
        # Adlar `partner_detail` ile AYNI (`clicks`, `referredUsers`):
        # aynı sayının iki ekranda iki adı olsaydı panelin hangi alanı
        # okuduğu gözle doğrulanamazdı.
        veri["clicks"] = tiklama
        veri["referredUsers"] = kuran
    return sonuc


def create_partner(name: str, contact: str, share_percent: float,
                   notes: str = "", *, reward_try: float = 30.0,
                   uid: str | None = None) -> dict[str, Any]:
    """Yeni ortak açar. `uid` ZORUNLU — imza gereği değil kapı gereği.

    Kendi-kodunu-kullanma kapısı `partners/{id}.uid == uid` karşılaştırmasına
    dayanıyor; alan boşsa kapı SESSİZCE devre dışı kalır ve ortak kendi
    kodunu kendi hesabında kullanıp kendine atıf üretebilir (redeem 200
    döner, `None != uid`). Tanıtım sayfası ise "uç bunu reddeder" diyor.
    Uç de (`api/admin.py` PartnerCreate) alanı zorunlu tutuyor; buradaki
    kapı uç değişse bile beyanı korur.
    """
    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")
    if not (uid or "").strip():
        raise RedeemError(400, "uid_required")
    ref = client.collection("partners").document()
    veri = {"name": name.strip(), "contact": contact.strip(),
            "sharePercent": float(share_percent), "active": True,
            "notes": notes.strip(), "createdAt": _now(),
            # OP: tutar ORTAK BAŞINA ve panelden düzenlenir; kodda sabit
            # değil. Varsayılan yalnızca bir başlangıç noktasıdır.
            "rewardModel": REWARD_MODEL_FIXED,
            "rewardTry": _rewardi_dogrula(reward_try),
            # Ortağın kendi Firebase hesabı: hem kendi panelini görmesi
            # hem kendi kodunu kullanamaması bu bağa dayanıyor. Yukarıdaki
            # kapı yüzünden burada asla None olmaz.
            "uid": uid.strip(),
            # Sabitten okunuyor, literal değil: `DEFAULT_PAYOUT_CURRENCY`
            # yorumu "bu fonksiyon alanı HER ZAMAN yazıyor" diyor ve iki
            # kopya ayrışırsa o gerekçe sessizce yalan olur — kapı
            # (`add_payout`) sabiti okuyor, yazan taraf literali.
            "payoutCurrency": DEFAULT_PAYOUT_CURRENCY}
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
        # Alanı BOŞALTMAK yasak: `create_partner` uid'i zorunlu tuttuğu
        # hâlde panelden sonradan silinebilmesi, kendi-kodunu-kullanma
        # kapısını tek bir PATCH ile sessizce kapatmanın yolu olurdu.
        # Alanı hiç göndermemek serbest (model `exclude_none` ile geçiyor);
        # yasak olan boş dize yazmak.
        yeni_uid = str(izinli["uid"] or "").strip()
        if not yeni_uid:
            raise RedeemError(400, "uid_required")
        izinli["uid"] = yeni_uid
    eski_uid = None
    if "uid" in izinli:
        anlik = client.collection("partners").document(partner_id).get()
        eski_uid = ((anlik.to_dict() or {}).get("uid")
                    if getattr(anlik, "exists", False) else None)
    if izinli:
        client.collection("partners").document(partner_id).update(izinli)
    if eski_uid and eski_uid != izinli.get("uid"):
        _eski_bagi_temizle(partner_id, str(eski_uid))


def _eski_bagi_temizle(partner_id: str, eski_uid: str) -> None:
    """uid değişti — ESKİ hesaptaki ortaklık claim'ini düşür.

    Olmazsa ne olur (ölçüldü): claim `partnerId` taşıyor ve panel artık
    YENİ uid'i ölçtüğü için eski hesabın claim'i hiçbir ekranda görünmez;
    yönetici onu ne görebilir ne kapatabilir. Eski hesap o ortağın
    bakiyesini okumaya devam ederdi.

    ⚠️ Bu temizlik TEK BAŞINA yeterli DEĞİL ve öyle sunulmamalı: Firebase
    claim'i yalnız yeni bir ID jetonunda taşındığı için iptal en çok bir
    saat gecikir. Asıl sınır `partner_self_view`'daki bağ doğrulaması —
    o, bayat claim'i bir sonraki istekte düşürür. Buradaki temizlik onun
    yerine geçmez, Firebase tarafını da tutarlı tutar (bir denetim
    `custom_claims`e baktığında ölü bir bağ görmesin).

    BEST-EFFORT: fırlatmaz. `update_partner` çağıranı bir panel PATCH'i
    ve Firestore yazımı ZATEN olmuş durumda; Auth erişilemiyor diye
    yöneticiye hata döndürmek, yapılmış bir değişikliği başarısız gibi
    gösterir ve tekrar denemeye iter.
    """
    try:
        set_partner_access_for_uid(partner_id, eski_uid, False)
    except RedeemError as exc:
        if exc.reason == "user_not_found":
            return  # Hesap zaten yok; temizlenecek claim de yok.
        logger.warning("Eski ortaklik bagi temizlenemedi "
                       "(ortak=%s eski uid=%s): %s",
                       partner_id, eski_uid, exc.reason)
    except Exception as exc:  # pragma: no cover — savunma
        logger.warning("Eski ortaklik bagi temizlenemedi "
                       "(ortak=%s eski uid=%s): %s", partner_id, eski_uid, exc)


def create_code(partner_id: str, code: str | None, bonus_tokens: int,
                max_redemptions: int | None,
                expires_at: dt.datetime | None) -> dict[str, Any]:
    """Kod üretir/rezerve eder. `create()` var olan kodda düşer —
    usernames benzersizlik deseni: yarışta ikinci istek hata alır.

    `bonus_tokens` YALNIZ 0 kabul edilir (K-a). Gerekçe alanın kendisi değil
    BEYAN: `web/ortaklik.html` herkese açık biçimde kullanıcının jeton ya da
    indirim almadığını yazıyor; sıfır dışı bir bonus o cümleyi yalanlar ve
    çelişki yalnız o ortağın gelirinde görünür. Uç de (`api/admin.py`
    CodeCreate) sıfır dışını almıyor; buradaki kapı uç değişse bile beyanı
    korur.
    """
    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")
    if int(bonus_tokens or 0) != 0:
        raise RedeemError(400, "bonus_not_allowed")
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


def _odeme_birimi(ortak: dict[str, Any]) -> str:
    """Ortağın ödeme birimi; alan yoksa `DEFAULT_PAYOUT_CURRENCY`.

    Tek yerden okunuyor çünkü `partner_detail` toplarken ve `add_payout`
    kapı kurarken AYNI değeri görmek zorunda: ikisi ayrışırsa kapı bir
    birimi kabul edip toplam başka birimi sayar ve kayıp yine sessiz olur.
    """
    return (str(ortak.get("payoutCurrency") or DEFAULT_PAYOUT_CURRENCY)
            .strip().upper())


def partner_detail(partner_id: str, *, erisim: bool = True,
                   tiklama_serisi: bool = True) -> dict[str, Any]:
    """Ortak + kodlar + tıklama + gelir + hakediş + ödemeler + erişim.

    `erisim=False` Firebase Auth'a HİÇ gitmez ve yanıtta `access` anahtarı
    OLMAZ. Anahtarın yokluğu "bakılmadı", `granted: None` ise "bakıldı,
    bilinemedi" demek; ikisini aynı şekle sıkıştırmak ölçülmemiş bir şeyi
    ölçülmüş gibi sunmak olurdu.

    Kapatan iki çağıran ve gerekçeleri: `add_payout` (para yolu — bakiye
    kapısı için çağırıyor, claim'le işi yok) ve `partner_self_view`
    (ortağın kendi panosu, her yüklemede çalışır ve dar görünüm zaten
    `access` taşımıyor). İkisinde de Auth isteği katıksız israf olurdu.

    `tiklama_serisi=False` aynı doktrinin tıklama tarafı ama kapsamı DAHA
    DAR, çünkü tıklamanın yalnız BİR ayağı okuma maliyeti taşıyor:

    * `clicks` / `conversionRate` / `codes[].clicks` — kod dokümanlarındaki
      `clickCount` alanından gelir, o dokümanlar ZATEN okundu. Bayrak
      bunları kapatmaz; bedava bir sayıyı gizlemenin gerekçesi olmazdı.
    * `clicks30` / `clickSeries` — kod başına 30 gün dokümanı okur. Bayrak
      YALNIZ bunları kapatır ve anahtarlar yanıttan DÜŞER (`access`
      emsali: yokluk "bakılmadı" demek, 0 ise "bakıldı, hiç yok").

    `add_payout` kapatır: para yolu bakiye için çağırıyor, telemetri
    okumasının orada hiçbir işi yok.
    """
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
        # Ham alan `clickCount`, yanıttaki ad `clicks`: sözleşme tek bir ad
        # kullanıyor ve panonun ham alan adını bilmesi gerekmiyor.
        veri["clicks"] = int(veri.get("clickCount") or 0)
        kodlar.append(veri)

    # ⚠️ ADLANDIRMA DÜZELTMESİ (ölçüldü): bu sayı "gelen kullanıcı" DEĞİL.
    # Toplanan şey kodların `redemptionCount`ı ve o sayaç `redeem` içinde
    # KURULUMDAN SONRA artıyor — yani ölçülen "KURAN" kullanıcıdır. Önceki
    # ad (`gelen`) ve panodaki "Gelen kullanıcı" etiketi, gelen ile kuranı
    # aynı şey sayıp dönüşüm oranını da yanlış yere bağlıyordu. Huninin
    # gerçek tepesi artık ayrı ölçülüyor (`clicks`).
    #
    # Alan adı `referredUsers` DEĞİŞMEDİ (panel ve pano onu okuyor);
    # değişen şey neyi anlattığı ve ekranda hangi etiketle sunulduğu.
    #
    # ⚠️ AMA "KURAN" da TAM DEĞİL, sınırı burada yazılı olmalı: bu dosyanın
    # başındaki "kodun bu uca geliş yolları" listesi İKİ yol sayıyor ve
    # ikincisi (App Links: KURULU uygulama ortak linkiyle açılıyor)
    # kurulumdan doğmuyor. Yani sayaç "bu linkten dolayı kuran"ı değil
    # "kodu KULLANAN (atfedilen) kullanıcı"yı ölçüyor; her ikisinde de
    # uygulama kuruludur ama nedensellik yalnız birincisinde var.
    #
    # Bu fark ŞU AN en büyük: kapalı testte herkeste uygulama ZATEN kurulu,
    # yani ortak linkine dokunan her testçi hiç kurulum olmadan bu sayacı
    # artırır. Huni etiketi "kuran" okunursa sahibi 12 testçiyi 12 kurulum
    # sanar. Ekran metinleri bu dosyada değil; buradaki iddia dar tutuldu.
    #
    # Atıf dokümanları kullanıcı altında dağınık olduğu için ayrıca
    # taranmaz — bu sayı elde olan kod dokümanlarından bedava geliyor.
    kuran = sum(int(k.get("redemptionCount") or 0) for k in kodlar)
    tiklama = sum(int(k.get("clicks") or 0) for k in kodlar)

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

    # Ödeme toplamı YALNIZ ortağın kendi ödeme birimindeki kayıtları sayar.
    # Ölçülen kırılma: ortak ₺500 hakediş biriktirir, yönetici tutarı 400 +
    # birimi USD girer; birime bakmayan toplam 400 < 500 gördüğü için kapı
    # geçer, pano "Ödenen ₺400, Bakiye ₺100" yazar ama ortağa ~₺14.000
    # gönderilmiştir.
    #
    # Eşleşmeyen kayıt SESSİZCE ATILMIYOR: `payouts` listesinde kendi
    # birimiyle duruyor ve sayısı `payoutCurrencyMismatchCount` olarak
    # yanıtta görünüyor. Farkı gizlemek, yanlış toplamak kadar kötüdür —
    # ikisinde de panodaki sayı gerçeği anlatmaz.
    birim = _odeme_birimi(ortak)
    odenen = 0.0
    uyumsuz = 0
    odemeler = []
    for o in (client.collection("partners").document(partner_id)
              .collection("payouts").stream()):
        veri = o.to_dict() or {}
        veri["id"] = o.id
        odemeler.append(veri)
        # Eski kayıtlarda `currency` alanı YOK (alan sonradan eklendi);
        # onları ortağın birimi saymak geriye uyumdur — o dönemde tek
        # birim vardı ve varsayılan buydu.
        kayit_birim = str(veri.get("currency") or birim).strip().upper()
        if kayit_birim == birim:
            odenen += float(veri.get("amount") or 0)
        else:
            uyumsuz += 1

    sonuc: dict[str, Any] = {
            "partner": ortak, "codes": kodlar,
            # Huni — sahibin sorduğu "kaç kişi gelmiş, kaçı alım yapmış":
            # tıklama → KURAN → hakediş.
            "clicks": tiklama,
            # `referredUsers` = KURAN kullanıcı (yukarıdaki gerekçe).
            "referredUsers": kuran,
            # Dönüşüm: kuran / tıklama. Tıklama 0 iken **None**, 0.0 DEĞİL —
            # "%0 dönüşüm" ile "henüz ölçüm yok" aynı şey değildir ve
            # ilkini göstermek ortağa tanıtımının başarısız olduğunu
            # SÖYLER: ölçülmemiş bir hüküm.
            #
            # 1'in ÜSTÜNE çıkabilir ve bu bilinçli olarak kırpılmıyor:
            # Play linkini doğrudan paylaşan (ya da tıklaması sayılamamış)
            # bir kurulum sayacı artırır, tıklamayı artırmaz. Kırpmak
            # ölçüm boşluğunu gizlemek olurdu; oran 1'i aşıyorsa
            # gerçekten aşıyor.
            "conversionRate": (round(kuran / tiklama, 4)
                               if tiklama > 0 else None),
            "pendingCount": huni[STATUS_PENDING],
            "qualifiedCount": huni[STATUS_QUALIFIED],
            "voidCount": huni[STATUS_VOID],
            # Para (₺) — kesinleşen üzerinden.
            #
            # ⚠️ BİLİNEN SINIR: hakediş tarafı YALNIZ ₺ üretir (`rewardTry`,
            # `MAX_REWARD_TRY`), ödeme birimi ise ortak başına serbest
            # (`PartnerPatch.payoutCurrency`). `payoutCurrency` ödeme
            # yazıldıktan SONRA değiştirilirse eski kayıtlar uyumsuz olur,
            # `paidTry` onları saymaz ve BU SAYI ödenmiş parayı ödenmemiş
            # gösterir — `balanceTry` olduğundan büyük çıkar.
            #
            # Para ÇIKIŞI bu hâlde kapalı: `add_payout` uyumsuz kayıt
            # görünce pozitif ödemeyi `ledger_currency_mixed` ile düşürür.
            # Kapatılmayan şey EKRANDAKİ sayı; `payoutCurrencyMismatchCount`
            # tam olarak onu işaretlemek için var. Kalıcı çözüm hakedişin de
            # birim taşıması ya da `payoutCurrency`nin TRY'ye kilitlenmesi.
            "earnedTry": round(hakedis, 2),
            "pendingTry": round(bekleyen_tutar, 2),
            "paidTry": round(odenen, 2),
            "balanceTry": round(hakedis - odenen, 2),
            # Ortağın ödeme birimi + o birime UYMAYAN kayıt sayısı. Sıfır
            # dışı bir değer, `paidTry`nin defterin tamamını anlatmadığını
            # söyler; panonun bunu göstermesi gerekir.
            "payoutCurrency": birim,
            "payoutCurrencyMismatchCount": uyumsuz,
            # Bilgi amaçlı gelir (süzülmüş).
            "attributedGrossUsd": round(brut, 2),
            "attributedEvents": olay,
            "payouts": odemeler}
    if tiklama_serisi:
        try:
            seri = _tiklama_serisi(client, kodlar)
            sonuc["clickSeries"] = seri
            # Türetilmiş: serinin toplamı. Ayrı okuma YOK.
            sonuc["clicks30"] = sum(g["count"] for g in seri)
        except Exception as exc:
            # Seri okuması panonun GERİ KALANINI düşürmemeli: ortak
            # bakiyesini bir telemetri okuması yüzünden kaybetmez. Anahtar
            # yanıttan DÜŞER (0 yazmak "ölçtük, hiç yok" demek olurdu) ve
            # kayıp log'da durur.
            logger.warning("Tiklama serisi okunamadi (%s): %s",
                           partner_id, exc)
    if erisim:
        # Ortak dokümanı ELDE: `partner_access` yerine iç yardımcı
        # çağrılıyor, yoksa aynı doküman bir kez daha okunurdu.
        sonuc["access"] = _erisim_durumu(partner_id, ortak.get("uid"))
    return sonuc


def add_payout(partner_id: str, amount: float, currency: str,
               note: str = "") -> dict[str, Any]:
    """Ödeme kaydı. Pozitif = ortağa ödendi, negatif = geri alındı.

    Bakiye kapısı: bakiyeden FAZLA pozitif ödeme yazılamaz. Ödeme defteri
    gerçek para transferinin aynasıdır; aynanın bakiyeyi aşması, ya yanlış
    tutar girildiğini ya da hakedişin iptal edildiğini gösterir.

    Negatif kayıt BİLEREK serbest: `qualified` olmuş bir hakediş sonradan
    iade edilirse geçmişi sessizce değiştirmek yerine düzeltme kaydı
    açılır — ortağın gördüğü bakiye açıklanabilir kalır.

    Para birimi ortağın `payoutCurrency` alanına EŞİT olmak zorunda. Kapı
    olmadan ölçülen hâl: bakiye ₺500 iken tutar 400 + birim USD girilir,
    bakiye kapısı 400 < 500 gördüğü için GEÇER; pano "Ödenen ₺400" yazar
    ama ortağa ~₺14.000 gitmiştir. Bakiye tek birimde tutulduğu sürece
    yabancı birimli tutarı onunla karşılaştırmak anlamsızdır.

    Defterde ortağın birimine uymayan ESKİ kayıt varsa pozitif ödeme de
    düşer (`ledger_currency_mixed`): o hâlde `paidTry` defterin tamamını
    saymadığı için bakiye kapısı ölçtüğünü sandığı şeyi ölçmez.
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

    # Birim kapısı bakiye kapısından ÖNCE: bakiye karşılaştırması ancak
    # birimler eşitken bir şey ifade eder.
    ortak_anlik = client.collection("partners").document(partner_id).get()
    if not getattr(ortak_anlik, "exists", False):
        raise RedeemError(404, "not_found")
    birim = _odeme_birimi(ortak_anlik.to_dict() or {})
    if (currency or "").strip().upper() != birim:
        raise RedeemError(400, "currency_mismatch")

    if tutar > 0:
        # `erisim=False`: burada bakiye ölçülüyor, claim değil — para
        # yolunun Firebase Auth'a bağımlılığı olmaması gerekir.
        # `tiklama_serisi=False` aynı gerekçe: bakiye kapısı tıklamaya
        # bakmıyor, 30 gün dokümanı okumak katıksız israf olurdu.
        mevcut = partner_detail(partner_id, erisim=False,
                                tiklama_serisi=False)
        if int(mevcut.get("payoutCurrencyMismatchCount") or 0) > 0:
            # Defterde ortağın birimine UYMAYAN kayıt varsa bakiye kapısı
            # ölçtüğünü sandığı şeyi ölçmez: `paidTry` o kayıtları saymadığı
            # için bakiye, ÖDENMİŞ parayı ödenmemiş gösterir.
            #
            # ÖLÇÜLDÜ: ₺500 hakediş → ₺500 TRY ödeme → bakiye 0 (ikinci
            # ödeme `exceeds_balance` ile düşüyor). Tek bir
            # `PATCH payoutCurrency=USD` sonrası `paidTry` 0'a, `balanceTry`
            # yeniden ₺500'e döndü ve 500 USD'lik İKİNCİ bir ödeme kapıdan
            # GEÇTİ. Birim süzgeci (yukarıda) bu yolu kapatmıyor: yeni kayıt
            # ortağın YENİ birimine uyuyor, eskiler uymuyor.
            #
            # Karışık defterde para çıkışı kapalı kalır. Tek yönlü bir
            # işlemi "belki doğrudur" ile açmak yerine yöneticiye sebebini
            # söylemek: defteri düzeltmeden (ya da `payoutCurrency`yi eski
            # hâline alarak) pozitif ödeme yazılamaz. Negatif düzeltme
            # kaydı BİLEREK serbest — karışıklığı gidermenin yolu odur.
            raise RedeemError(400, "ledger_currency_mixed")
        bakiye = float(mevcut.get("balanceTry") or 0)
        if tutar > bakiye + 0.005:
            raise RedeemError(400, "exceeds_balance")

    ref = (client.collection("partners").document(partner_id)
           .collection("payouts").document())
    veri = {"amount": tutar, "currency": birim,
            "note": note.strip(), "at": _now()}
    ref.set(veri)
    veri["id"] = ref.id
    return veri


# ---------------------------------------------------------------------------
# Ortak ERİŞİMİ: panonun kapısını açan claim (api/admin.py çağırır)
# ---------------------------------------------------------------------------
#
# Ortağın `web/ortak/` panosunu görebilmesi Firebase custom claim'ine bağlı
# (`{partner: true, partnerId: ...}` → `core/auth.require_partner`). O claim
# bu tura kadar YALNIZ `tools/set_admin.py --partner` ile, yerel makinede,
# servis hesabı kimliğiyle basılabiliyordu; panel bunu söylemiyordu bile.
# Ölçülen sonuç: yönetici panelden ortak açıyor, ortağa "hazır" diyor ve
# ortak hiçbir yere giremiyor — panonun kendisi pratikte ULAŞILAMAZ.
# Buradaki iki fonksiyon o komutu panele taşıyor; komut satırı yolu
# (kurtarma yolu) olduğu gibi duruyor.

#: Ortaklık claim'inin İKİ anahtarı — ve bu listenin kapsamı KASTEN dar.
#: `admin`/`role` bu kümede YOK: claim yazımı birleştirmedir, ezme değil
#: (bkz. `set_partner_access`).
PARTNER_CLAIM_KEYS = ("partner", "partnerId")


def _auth_modulu():
    """`firebase_admin.auth` modülü — testin pinleyebileceği TEK kapı.

    İçe aktarma fonksiyon içinde ve tek yerde: modül düzeyinde olsaydı bu
    dosyanın her içe aktarımı `firebase_admin`e bağlanırdı (emsal:
    `services/admin_service.py`, `core/auth.py` — hepsi çağrı anında alıyor).
    Tek kapı olması ayrıca test hermetikliğinin şartı: `conftest.py`
    Firestore'u ve Storage'ı pinliyor, Firebase Auth'u DEĞİL — yani bu
    modülü doğrudan içe aktaran bir dal, makinede ADC varken GERÇEK
    `rhytoai` hesaplarını okuyabilir, hatta CLAIM YAZABİLİRDİ. Aynı
    SINIFTAN bir boşluk (pinlenmemiş dış istemci) 2026-09-18'de üretim
    Firestore'una `users/dev-user` dokümanını yazdırmıştı; oradaki ders
    şuydu: kaza ile güvenli olan şey güvence değildir. Tek fonksiyon
    üzerinden geçirmek, o pini tek satırla kurulabilir kılıyor
    (`tests/test_partner_rewards._auth_pinle`).
    """
    from firebase_admin import auth as fb_auth

    return fb_auth


def _kullanici_yok_mu(exc: BaseException) -> bool:
    """İstisna "böyle bir Firebase hesabı yok" mu, yoksa geçici bir arıza mı?

    Sınıf ADIYLA bakılıyor, sembolle değil (`push_service._olu_token` ile
    aynı desen). ÖLÇÜLEN gerekçe: sınıf `firebase_admin.auth`ta değil
    `firebase_admin._auth_utils` içinde tanımlı ve oraya yalnız yeniden
    ihraç ediliyor (7.5.0'da MRO:
    `_auth_utils.UserNotFoundError → exceptions.NotFoundError`). ALT ÇİZGİLİ
    bir modüle bağlanmak sürüm yükseltmesinde sessizce kopar; ada bakmak
    ayrıca sahte auth modülünün bu sınıfı taşımasını gerektirmiyor.

    Ayrım ZORUNLU: iki hâl aynı sebebe düşerse panel geçici bir arızada
    "hesap yok" der ve yönetici doğru yazılmış bir uid'i "düzeltmeye"
    başlar (ya da tersi — silinmiş hesap "birazdan geçer" sanılır).
    """
    return type(exc).__name__ == "UserNotFoundError"


def _erisim_durumu(partner_id: str, uid: Any) -> dict[str, Any]:
    """`access` sözleşmesini uid ELDEYKEN üretir. ASLA FIRLATMAZ.

    `granted` ÜÇ değerlidir ve üçüncüsü (``None``) bilinçli: "kapalı" ile
    "bilmiyoruz" aynı şey değil. Auth okunamazken `False` dönmek, yöneticiye
    ölçülmemiş bir şeyi ölçülmüş gibi söylemek olurdu — ortak aslında
    girebiliyorken panel "erişimi yok" der, yönetici ikinci kez basar ve
    hiçbir şey açıklanmaz.

    `granted` yalnız claim BU ortağa aitse `True`. Başka bir ortağa bağlı
    uid `False` döner (ve uyarı log'u düşer): o claim ortağa bu panonun
    değil BAŞKASININ bakiyesini açar, yani "erişimi var" demek yanlış olur.
    """
    temiz = str(uid or "").strip()
    if not temiz:
        # Ortak kaydında hesap bağı yok: claim basılacak bir hedef de yok.
        # Yeni kayıtta uid zorunlu (`create_partner`), yani bu hâl o
        # zorunluluktan ÖNCE açılmış kayıtlardır.
        return {"uid": None, "granted": None, "email": None,
                "reason": "no_uid"}
    try:
        kullanici = _auth_modulu().get_user(temiz)
    except Exception as exc:
        if _kullanici_yok_mu(exc):
            # KALICI ve bilinen hâl: `partners/{id}.uid` yanlış yazılmış ya
            # da hesap silinmiş. `granted` None kalır çünkü claim durumu
            # gerçekten okunamadı; sebep onu açıklıyor.
            return {"uid": temiz, "granted": None, "email": None,
                    "reason": "user_not_found"}
        # GEÇİCİ hâl. Bu dal, ortak detay sayfasının tamamını düşürmemek
        # için var: `partner_detail` canlı bir paneli besliyor ve orada
        # hakediş/ödeme sayıları da duruyor — Auth kesintisi o sayıları
        # görünmez etmemeli. Gösterge düşer, sayfa ayakta kalır.
        logger.warning("Ortak erisim durumu okunamadi (ortak=%s uid=%s): %s",
                       partner_id, temiz, exc)
        return {"uid": temiz, "granted": None, "email": None,
                "reason": "unavailable"}
    claimler = dict(getattr(kullanici, "custom_claims", None) or {})
    bagli = str(claimler.get("partnerId") or "")
    verili = claimler.get("partner") is True and bagli == str(partner_id)
    if claimler.get("partner") is True and bagli and bagli != str(partner_id):
        # Bu hesap BAŞKA bir ortağın panosunu açıyor. Ekranda yalnız
        # "erişim yok" görünür (sözleşme dört alanlı) ve yazma kapısı
        # `uid_taken` ile reddeder; bu log o sessizliği kırıyor.
        logger.warning("Ortak %s uid'i BASKA ortaga bagli (%s) — panoda o "
                       "ortagin bakiyesi gorunur", partner_id, bagli)
    return {"uid": temiz, "granted": verili,
            "email": getattr(kullanici, "email", None), "reason": None}


def partner_access(partner_id: str) -> dict[str, Any]:
    """Ortağın pano erişim durumu (GÖSTERGE — asla fırlatmaz).

    Ortak kaydı ya da Firestore okunamazsa da şekil korunur: gösterge bir
    sayfanın köşesidir, sayfayı düşürmemeli. Eylem tarafı (`ortağı yok`
    demek gerekiyorsa) `set_partner_access`in işi; o FIRLATIR.

    ⚠️ PROPAGASYON: `granted: True` "ortak ŞU AN girebiliyor" demek DEĞİL.
    Firebase custom claim değişikliği o kişinin ID jetonu yenilenene kadar
    (en çok 1 saat, ya da çıkış/yeniden giriş) geçerli olmaz — bu gösterge
    SUNUCUDAKİ claim'i okur, ortağın elindeki jetonu değil.
    """
    client = firestore_client.get_client()
    if client is None:
        return {"uid": None, "granted": None, "email": None,
                "reason": "unavailable"}
    try:
        anlik = client.collection("partners").document(partner_id).get()
    except Exception as exc:
        logger.warning("Ortak %s okunamadi (erisim gostergesi): %s",
                       partner_id, exc)
        return {"uid": None, "granted": None, "email": None,
                "reason": "unavailable"}
    if not getattr(anlik, "exists", False):
        # Ortak yok: bağlanacak uid de yok. `no_uid` doğru sebep — kayıt
        # yokluğu için ayrı bir sebep uydurmak, sözleşmeyi bu fonksiyon
        # için genişletmek olurdu; çağıran (uç) 404'ü zaten kendisi görür.
        return {"uid": None, "granted": None, "email": None,
                "reason": "no_uid"}
    return _erisim_durumu(partner_id, (anlik.to_dict() or {}).get("uid"))


def set_partner_access(partner_id: str, grant: bool) -> dict[str, Any]:
    """Ortaklık claim'ini basar (grant) ya da kaldırır. FIRLATIR.

    `partner_access`in tersine bu bir EYLEM: sessizce başarısız olması,
    yöneticiye "açtım" dedirtip ortağı kapıda bırakır.

    CLAIM BİRLEŞTİRİLİR, EZİLMEZ (`tools/set_admin.py` ile aynı disiplin).
    Somut kırılma: sahip kendi hesabını test ortağı yapar, sonra erişimi
    kapatır; claim komple ezilseydi kendi `admin` claim'i de silinir ve
    PANELDEN KİLİTLENİRDİ — geri almanın tek yolu komut satırı olurdu.
    Kaldırmada yalnız [PARTNER_CLAIM_KEYS] silinir.

    `uid_taken` kapısı GRANT ve REVOKE için birden geçerli:
    * grant'ta tek hesap iki ortağa bağlanırsa `/partners/me` claim'deki
      `partnerId`yi okur ve ortak YANLIŞ ortağın bakiyesini görür — sızıntı.
    * revoke'ta ise silinecek claim BAŞKA ortağın claim'idir: B ortağında
      "kapat"a basmak A ortağının panosunu sessizce kapatırdı.
    Aynı ortağa yeniden basmak serbest ve idempotenttir.

    ⚠️ PROPAGASYON GERÇEĞİ: dönüş `granted: True` olsa bile ortak HEMEN
    giremez. Custom claim yalnız yeni bir ID jetonunda taşınır; eski jeton
    yenilenene kadar (en çok 1 saat) ya da ortak çıkıp yeniden girene kadar
    ESKİ claim geçerlidir. Kaldırmada da aynısı: erişim anında kesilmez.

    Bu yüzden `revoke_refresh_tokens` BİLEREK ÇAĞRILMIYOR — iki gerekçe:
    (1) jeton iptali erişimi yine de anında kesmez, çünkü `core/auth._verify`
    `check_revoked` KULLANMIYOR; yani "anında kesildi" hissi yanlış olurdu.
    (2) ortağın uid'i sıradan bir Rytho hesabıdır: jetonlarını iptal etmek
    onu MOBİL UYGULAMADAN da atardı — ortaklık erişimini kapatmanın bedeli
    müşterinin oturumu olamaz.
    """
    client = firestore_client.get_client()
    if client is None:
        raise RedeemError(500, "unavailable")
    anlik = client.collection("partners").document(partner_id).get()
    if not getattr(anlik, "exists", False):
        raise RedeemError(404, "not_found")
    uid = str((anlik.to_dict() or {}).get("uid") or "").strip()
    if not uid:
        raise RedeemError(400, "no_uid")
    return set_partner_access_for_uid(partner_id, uid, grant)


def set_partner_access_for_uid(partner_id: str, uid: str,
                               grant: bool) -> dict[str, Any]:
    """[set_partner_access]'in uid'i AÇIKÇA verilen biçimi.

    Ayrı durmasının tek sebebi var: uid değiştiğinde ESKİ hesabın
    claim'i düşürülmeli ve o uid artık `partners/{id}.uid` alanında
    YAZMIYOR — kaynaktan okuyan biçim onu bulamaz. Kapıların hepsi
    (birleştirme, `uid_taken`, geçici/kalıcı hata ayrımı) burada,
    yani iki yol aynı disipline uyuyor.
    """
    fb_auth = _auth_modulu()
    try:
        kullanici = fb_auth.get_user(uid)
    except Exception as exc:
        if _kullanici_yok_mu(exc):
            raise RedeemError(400, "user_not_found")
        # Geçici arıza KALICI bir veri hatası gibi görünmemeli: yönetici
        # 400 görünce `partners/{id}.uid` alanını "düzeltmeye" başlar.
        logger.warning("Ortak %s icin hesap okunamadi (uid=%s): %s",
                       partner_id, uid, exc)
        raise RedeemError(500, "unavailable")

    mevcut = dict(getattr(kullanici, "custom_claims", None) or {})
    bagli = str(mevcut.get("partnerId") or "")
    if mevcut.get("partner") is True and bagli and bagli != str(partner_id):
        raise RedeemError(400, "uid_taken")

    if grant:
        mevcut["partner"] = True
        mevcut["partnerId"] = str(partner_id)
    else:
        for anahtar in PARTNER_CLAIM_KEYS:
            mevcut.pop(anahtar, None)

    try:
        # `mevcut or None`: boşalan claim sözlüğü yerine None geçmek
        # `set_admin.py`nin deseni — Firebase'de "claim yok" hâli budur.
        fb_auth.set_custom_user_claims(uid, mevcut or None)
    except Exception as exc:
        logger.warning("Ortaklik claim'i yazilamadi (ortak=%s uid=%s): %s",
                       partner_id, uid, exc)
        raise RedeemError(500, "unavailable")

    logger.info("Ortak erisimi %s: ortak=%s uid=%s",
                "ACILDI" if grant else "KAPATILDI", partner_id, uid)
    # Yazdığımız değer döndürülüyor, Auth yeniden OKUNMUYOR: claim yazımı
    # okumaya anında yansımayabilir ve tazeleme uğruna ikinci bir istek
    # atmak, başarılı yazımdan sonra "bilinmiyor" dönme riski demektir.
    return {"uid": uid, "granted": bool(grant),
            "email": getattr(kullanici, "email", None), "reason": None}


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


def partner_self_view(partner_id: str,
                      caller_uid: str | None = None) -> dict[str, Any]:
    """Ortağa gösterilecek DAR görünüm.

    `partner_detail`'in alt kümesi: işletmeye ait hiçbir sayı (atfedilen
    gelir, diğer ortaklar, kullanıcı kimlikleri) DIŞARI ÇIKMAZ. Ortak
    yalnız kendi hunisini, bakiyesini ve kodlarını görür.

    `erisim=False`: ortağın kendi claim durumunu görmesine gerek yok —
    claim'i yoksa bu görünümü hiç göremiyor (`require_partner`). Alanı
    burada ayıklamak yerine hiç istememek, her pano yüklemesinde bir
    Firebase Auth isteğini de ortadan kaldırıyor.

    ⚠️ `caller_uid` BAYAT CLAIM KAPISI ve asıl güvenlik sınırı burası.
    Ölçülen sızıntı: claim `{partner, partnerId}` taşır ve `_ortak_coz`
    partnerId'yi YALNIZ claim'den okur — `partners/{id}.uid` ile hiç
    karşılaştırmazdı. Senaryo: ortak uid=A ile açılır, erişim verilir
    (A claim alır), sonra panelden uid B'ye düzeltilir. Panel artık B'yi
    ölçtüğü için "erişim kapalı" gösterir ve yönetici B'ye erişim verir;
    **A'nın claim'i hiçbir yerde görünmez ve hiç silinmez**, yani A o
    ortağın bakiyesini sonsuza kadar okumaya devam eder.

    Claim'i temizlemek (`update_partner`) TEK BAŞINA yetmez: Firebase
    claim'i yalnız yeni bir ID jetonunda taşınır, yani iptal en çok bir
    saat gecikir. Kaynaktaki bağı her okumada doğrulamak o pencereyi
    kapatıyor — bağ bozuksa BİR SONRAKİ istek düşer.
    """
    tam = partner_detail(partner_id, erisim=False)
    ortak = tam["partner"]
    if caller_uid is not None and ortak.get("uid") != caller_uid:
        # Jenerik `not_found`: çağırana "claim'in bayat" demek, silinmiş
        # ya da devredilmiş bir kaydın varlığını anlatır. Uç bunu zaten
        # jenerik 403'e çeviriyor.
        logger.warning(
            "Bayat ortaklik claim'i reddedildi: partnerId=%s claim uid=%s "
            "kayitli uid=%s", partner_id, caller_uid, ortak.get("uid"))
        raise RedeemError(404, "not_found")
    gorunum: dict[str, Any] = {
        "name": ortak.get("name"),
        "active": ortak.get("active"),
        "rewardTry": ortak.get("rewardTry"),
        "payoutCurrency": tam["payoutCurrency"],
        # Ortağın KENDİ ödeme defterine ait bir işaret, işletme verisi
        # değil: `paidTry` onun gördüğü sayı ve eksik topluyorsa bunu ilk
        # öğrenmesi gereken kişi ortaktır.
        "payoutCurrencyMismatchCount": tam["payoutCurrencyMismatchCount"],
        "codes": [{"code": k.get("code"),
                   "redemptionCount": k.get("redemptionCount"),
                   # Kod başına tıklama: ortak hangi kanalın çalıştığını
                   # ancak kod başına görürse bilebilir (tek toplam, iki
                   # farklı tanıtımı tek sayıya karıştırır).
                   "clicks": k.get("clicks"),
                   "active": k.get("active"),
                   "expiresAt": k.get("expiresAt")}
                  for k in tam["codes"]],
        # Huninin TEPESİ. Kişisel veri değil — kimliksiz bir sayaç
        # (`record_click`: IP/UA/çerez yok), bu yüzden dar görünüme giriyor
        # ve ortağın bunu görmesi programın ASIL sorusunu cevaplıyor:
        # "tanıtımım işe yarıyor mu?"
        "clicks": tam["clicks"],
        "conversionRate": tam["conversionRate"],
        "referredUsers": tam["referredUsers"],
        "pendingCount": tam["pendingCount"],
        "qualifiedCount": tam["qualifiedCount"],
        # DÜŞEN kayıt sayısı ortağa da gösterilir. İşletme verisi değil,
        # kendi hunisi; ve gizlenirse bekleyen hakedişi iptal olan ortak
        # sayının neden düştüğünü hiçbir yerden anlayamaz — pasif ortağın
        # panoyu görmeye devam etmesinin gerekçesi (api/partners.py `/me`)
        # tam olarak buna dayanıyor.
        "voidCount": tam["voidCount"],
        "earnedTry": tam["earnedTry"],
        "pendingTry": tam["pendingTry"],
        "paidTry": tam["paidTry"],
        "balanceTry": tam["balanceTry"],
        "payouts": [{"amount": o.get("amount"), "currency": o.get("currency"),
                     "at": o.get("at"), "note": o.get("note")}
                    for o in tam["payouts"]],
    }
    # ÖDEME EŞİĞİ — yalnız KAYITLIYSA taşınır ve VARSAYILANI BİLEREK YOK.
    #
    # Tanıtım sayfası (`web/ortaklik.html`, EN aynası `web/en/partners.html`)
    # "Ödeme takvimi, alt sınır ve ödeme kanalı ANLAŞMADA yazılır" diyor.
    # Yani eşik ürünün değil O ORTAKLA yapılan anlaşmanın sayısıdır ve
    # kodun bileceği bir varsayılanı YOK: bir sayı yazmak (₺100) kimsenin
    # kabul etmediği bir alt sınır icat etmek, 0 yazmak da "alt sınır yok"
    # diye anlaşmanın söylemediği bir söz vermek olurdu. `create_partner`
    # bu yüzden alanı hiç yazmıyor — eksiklik değil, karar.
    #
    # Üç hâl ÜÇ AYRI şey ve pano üçünü ayrı çiziyor: anahtar YOK = anlaşma
    # değeri girilmedi (pano eşikten HİÇ söz etmez), 0 = alt sınır yok
    # (kesinleşen her tutar ödenebilir), >0 = eşik.
    esik = ortak.get("minPayoutTry")
    if esik is not None:
        try:
            gorunum["minPayoutTry"] = round(float(esik), 2)
        except (TypeError, ValueError):
            # Bozuk değer ÖLÇÜLMEMİŞ sayılır. Sayı olmayan bir eşiği panoya
            # göndermek orada "NaN ₺ kaldı" yazdırır; eksik bir kart,
            # yanlış bir karttan iyidir.
            logger.warning("Bozuk minPayoutTry (%s): %r", partner_id, esik)
    # Seri anahtarları KOPYALANARAK taşınıyor, `tam.get(...)` ile DEĞİL:
    # okuma düşmüşse anahtar `partner_detail`de yok ve burada da OLMAMALI.
    # `None` yazmak "ölçtük, bilinemedi" demek olurdu — pano ikisini ayırt
    # edemez ve boş bir grafiği "hiç tıklama yok" diye okur.
    for anahtar in ("clicks30", "clickSeries"):
        if anahtar in tam:
            gorunum[anahtar] = tam[anahtar]
    return gorunum

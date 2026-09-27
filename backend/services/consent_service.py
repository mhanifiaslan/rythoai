"""Biyometrik işleme rızası — bir kez alınır, geri alınabilir, kayıtlıdır.

## Neden ayrı bir rıza

Yüz okuma biyometrik veri işliyor ve bu **özel nitelikli** veri. GDPR Md.9
*explicit consent* istiyor; Md.7(2) ise "başka konuları da içeren bir beyanın
parçası olarak" alınan rızayı geçersiz sayıyor. KVKK md.6 aynı şekilde ayrı
bir **açık rıza** arıyor.

Yani rızayı üyelik sözleşmesine ya da gizlilik metnine gömmek işe yaramaz —
o, yasanın adını koyduğu geçersiz kalıbın ta kendisi.

## Ama HER SEFERINDE sormak da gerekmiyor

İlk sürümde her çekimde soruluyordu ve bu fazla temkinliydi: rızanın **geri
alınabilir** olması gerekiyor, her seferinde yeniden sorulması değil. Gereken
dört şey şu:

1. Ayrı ve açık olmalı (başka şartlarla paketlenmemeli),
2. İşlemeden ÖNCE alınmalı,
3. Verildiği kadar kolay geri alınabilmeli,
4. **İspatlanabilmeli** — bu yüzden sunucuda kayıtlı; istemcinin hafızasında
   tutulan rıza, denetimde hiçbir şey ifade etmez.

## Sürümleme

Rıza **neye** rıza gösterildiğini kapsar. Yarın işlem değişirse (ör. ses
eklenirse) eski rıza onu kapsamaz. Bu yüzden rıza bir sürüm numarasıyla
saklanıyor ve sürüm ilerlediğinde kullanıcıya yeniden soruluyor —
"bir kez alıp ömür boyu kullanma" sorunu buradan çözülüyor.
"""
from __future__ import annotations

import datetime as dt
import json
import logging
from typing import Any

from core import config, firestore as firestore_client

logger = logging.getLogger(__name__)


def _local_store():
    """Firestore yokken kullanılan yerel kayıt dosyası.

    Önbellekteki desenin aynısı (`core/cache.py`): yerelde dosya, üretimde
    Firestore. Bu bir KAPI GEVŞETMESİ DEĞİL, depolama seçimi — rıza yine
    gerçekten aranıyor ve kayıt yoksa işleme reddediliyor.

    Yanlış tarafa düşme yönü de doğru: kayıt kaybolursa kullanıcıya rıza
    yeniden sorulur (can sıkıcı ama zararsız), rıza kendiliğinden "var"
    sayılmaz. Yani hata durumunda sistem kapanıyor, açılmıyor.
    """
    return config.CACHE_DIR / "face_consent.json"


def _local_read() -> dict[str, Any]:
    path = _local_store()
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _local_write(kayitlar: dict[str, Any]) -> bool:
    try:
        _local_store().write_text(
            json.dumps(kayitlar, ensure_ascii=False), encoding="utf-8")
        return True
    except Exception as exc:
        logger.warning("Yerel rıza kaydı yazılamadı: %s", exc)
        return False

#: Yüz okuma rızasının güncel sürümü.
#:
#: **İşlenen veri ya da işleme biçimi değiştiğinde ARTIRILIR.** Örnekler:
#: ses kaydı eklenmesi, görüntünün sunucuya taşınması, verinin üçüncü tarafla
#: paylaşılması. Sürüm arttığında eski rıza geçersiz sayılır ve kullanıcıya
#: yeniden sorulur.
#:
#: Metin düzeltmesi (yazım hatası, daha anlaşılır ifade) sürüm artırmaz;
#: kullanıcıyı aynı şey için ikinci kez rahatsız etmek rıza yorgunluğu üretir
#: ve rızayı anlamsızlaştırır.
FACE_CONSENT_VERSION = 1

#: Kullanım şartları + gizlilik kabulünün güncel sürümü (O3).
#:
#: Metinlerin ANLAMI değiştiğinde artırılır (yeni veri işleme, yeni
#: paylaşım); yazım düzeltmesi artırmaz (rıza yorgunluğu üretmemek —
#: FACE_CONSENT_VERSION ile aynı kural). Sürüm artınca sihirbaz/istemci
#: kabulü yeniden sorar; uçlar ZORLAMAZ (bu bir kilit değil, ispat kaydı).
TERMS_CONSENT_VERSION = 1

#: users/{uid}.termsConsent — faceConsent gibi YALNIZ sunucu yazar
#: (firestore.rules: listede ama değişmezlik bekçili).
_TERMS_FIELD = "termsConsent"


def grant_terms_consent(uid: str, version: int, locale: str) -> bool:
    """Şartlar/gizlilik kabulünü İSPATLANABİLİR biçimde kaydeder.

    "İstemci alanı metni hiç görmeden yazdı" itirazını kapatan şey yazımın
    sunucudan olması; "neye rıza gösterildi" sorusunu kapatan şey ise
    İSTEMCİNİN GÖRDÜĞÜ sürümün kaydedilmesi — sunucunun güncel sürümü
    değil. Eski istemci eski metni gösteriyorsa kayıt bunu söylemeli.
    """
    kayit = {
        "granted": True,
        "version": version,
        "acceptedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "locale": locale,
    }
    doc_ref = _user_doc(uid)
    if doc_ref is None:
        kayitlar = _local_read()
        kayitlar[f"terms-{uid}"] = kayit
        return _local_write(kayitlar)
    try:
        doc_ref.set({_TERMS_FIELD: kayit}, merge=True)
        return True
    except Exception as exc:
        logger.warning("Şartlar kabulü kaydedilemedi (%s): %s", uid, exc)
        return False

#: Firestore kullanıcı dokümanındaki alan.
#:
#: **Bu alan `infra/firestore.rules` içindeki yazılabilir alan listesine ASLA
#: eklenmemeli.** Liste `hasOnly(...)` ile çalışıyor; `faceConsent` orada
#: olmadığı için istemci bu alanı yazamıyor ve yalnızca sunucu (Admin SDK,
#: kuralları atlar) yazabiliyor.
#:
#: Eklenirse kullanıcı kendi rızasını uydurabilir: rıza metnini hiç görmeden
#: `granted: true` yazar ve hem bilgilendirme hem ispat kaydı çöker. Kural
#: `tests/test_face_consent.py` içinde bekçileniyor.
_FIELD = "faceConsent"


def _user_doc(uid: str):
    client = firestore_client.get_client()
    if client is None:
        return None
    return client.collection("users").document(uid)


def face_consent(uid: str) -> dict[str, Any] | None:
    """Kayıtlı rıza kaydı; yoksa ``None``."""
    doc_ref = _user_doc(uid)
    if doc_ref is None:
        return _local_read().get(uid)
    try:
        snapshot = doc_ref.get()
    except Exception as exc:
        logger.warning("Rıza okunamadı (%s): %s", uid, exc)
        return None
    if not snapshot.exists:
        return None
    return (snapshot.to_dict() or {}).get(_FIELD)


def has_face_consent(uid: str) -> bool:
    """Güncel sürüm için geçerli bir rıza var mı?

    Okuma başarısız olursa **False** döner. Rızayı doğrulayamadığımızda
    "vardır" varsaymak, biyometrik işlemeyi rızasız yapmak demek olurdu;
    hata durumunda güvenli taraf reddetmektir.
    """
    kayit = face_consent(uid)
    if not isinstance(kayit, dict):
        return False
    # `is True` — truthy DEĞİL. `{"granted": "false"}` gibi bir metin değer
    # truthy'dir ve gevşek kontrolde rızayı geçerli sayardı. Bu alanı yalnızca
    # sunucu yazıyor (aşağıdaki nota bkz.) ama tip kontrolü ucuz ve bir
    # sunucu hatası ya da veri göçü bozuk değer bırakabilir.
    if kayit.get("granted") is not True:
        return False
    surum = kayit.get("version")
    if not isinstance(surum, int) or isinstance(surum, bool):
        return False
    return surum >= FACE_CONSENT_VERSION


def grant_face_consent(uid: str) -> bool:
    """Rızayı kaydeder.

    Zaman damgası ve sürüm birlikte tutuluyor: ispat yükü bizde ve "ne zaman,
    neye rıza gösterildi" sorusunun cevabı olmadan kayıt bir işe yaramaz.
    """
    kayit = {
        "granted": True,
        "version": FACE_CONSENT_VERSION,
        "grantedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    doc_ref = _user_doc(uid)
    if doc_ref is None:
        kayitlar = _local_read()
        kayitlar[uid] = kayit
        return _local_write(kayitlar)
    try:
        doc_ref.set({_FIELD: {
            "granted": True,
            "version": FACE_CONSENT_VERSION,
            "grantedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        }}, merge=True)
        return True
    except Exception as exc:
        logger.warning("Rıza kaydedilemedi (%s): %s", uid, exc)
        return False


def withdraw_face_consent(uid: str) -> bool:
    """Rızayı geri alır.

    Kayıt SİLİNMİYOR, ``granted: False`` olarak işaretleniyor. Sebebi:
    "rıza vardı ve geri alındı" ile "hiç rıza olmadı" farklı durumlar ve
    ikincisini birincinin üstüne yazmak, geçmişte yapılan işlemenin
    dayanağını yok etmek olurdu.

    Üretilmiş okumaların silinmesi ÇAĞIRANIN işi (bkz. api/face_reading.py):
    rızayı geri alıp veriyi bırakmak, geri almayı anlamsız kılar.
    """
    doc_ref = _user_doc(uid)
    if doc_ref is None:
        kayitlar = _local_read()
        kayitlar[uid] = {
            "granted": False,
            "version": FACE_CONSENT_VERSION,
            "withdrawnAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        }
        return _local_write(kayitlar)
    try:
        doc_ref.set({_FIELD: {
            "granted": False,
            "version": FACE_CONSENT_VERSION,
            "withdrawnAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        }}, merge=True)
        return True
    except Exception as exc:
        logger.warning("Rıza geri alınamadı (%s): %s", uid, exc)
        return False


def delete_face_readings(uid: str) -> int:
    """Kullanıcının üretilmiş firaset okumalarını siler.

    Önbellek doküman kimliği anahtarın özeti olduğu için kullanıcıya göre
    sorgulanamaz; kişiye özel üretimlere ``ownerUid`` yazılıyor (bkz.
    core/cache.py) ve silme o alandan yürüyor.

    Yalnızca FIRASET okumalarını siler, kullanıcının diğer üretimlerine
    (natal, BaZi, günlük) dokunmaz — rızayı geri almak yüz okumadan
    vazgeçmektir, hesabı silmek değil.
    """
    client = firestore_client.get_client()
    if client is None:
        return 0

    silinen = 0
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter

        while True:
            belgeler = list(
                client.collection("aiCache")
                .where(filter=FieldFilter("ownerUid", "==", uid))
                .limit(200).stream())
            if not belgeler:
                break
            kalan = 0
            for belge in belgeler:
                veri = belge.to_dict() or {}
                # Firaset kayıtları anahtar önekiyle ayırt ediliyor. Alan adı
                # `keyHint` (bkz. core/cache.py); doküman kimliği anahtarın
                # SHA-256 özeti olduğu için anahtarın kendisi ayrıca
                # saklanıyor ve tam da bu tür seçmeli silmeyi mümkün kılıyor.
                if str(veri.get("keyHint") or "").startswith("firasa-"):
                    belge.reference.delete()
                    silinen += 1
                else:
                    kalan += 1
            # Bu turda hiçbir şey silinmediyse sayfa ilerlemiyor demektir:
            # kalan kayıtların hepsi firaset dışı, sonsuz döngüye girmeyelim.
            if kalan == len(belgeler):
                break
    except Exception as exc:
        logger.warning("Firaset okumaları silinemedi (%s): %s", uid, exc)
    return silinen


# --------------------------------------------------------------------------
# Üçüncü taraf AI (Google Gemini) aktarım onayı — U06, Apple 5.1.2(i)
# --------------------------------------------------------------------------
#
# Yüz rızasından AYRI bir kayıt, çünkü konusu ayrı: o biyometrik işleme,
# bu kişisel verinin (harita, sohbet, günlük, kişi etiketleri...) ÜÇÜNCÜ
# bir tarafa — Google'ın Gemini API'sine — gönderilmesi. Birini diğerinin
# içine gömmek GDPR Md.7(2)'nin geçersiz saydığı "paket rıza" olurdu.
#
# Neden `users/{uid}` alanı DEĞİL de `private/aiConsent` dokümanı: kullanıcı
# dokümanına sunucunun yazdığı her yeni alan `infra/firestore.rules`
# içindeki `hasOnly` listesine GİRMEK zorunda; girmezse o kullanıcının
# sonraki TÜM istemci yazımları (saat dilimi, FCM token, seri) sessizce
# permission-denied ile düşer — faceConsent/residenceCity/platform
# vakalarının üçü de canlıda yaşandı. Kural dağıtımı backend'den AYRI bir
# adım ve sırası unutulursa aynı tuzak dördüncü kez kurulurdu. `private/`
# istemciye tamamen kapalı (okuma da yazma da): kayıt uydurulamaz, kural
# değişikliği gerekmez, hesap silmede alt koleksiyonla birlikte gider.
# Bedeli: istemci durumu doğrudan okuyamaz, `GET /account/ai-consent` ile
# sorar ve yerelde önbellekler.

#: AI aktarım onayı metninin güncel sürümü.
#:
#: Gönderilen veri KATEGORİSİ ya da sağlayıcı değiştiğinde artırılır (ör.
#: yeni bir veri türünün prompta girmesi, Gemini'den başka bir sağlayıcıya
#: geçiş). Yazım düzeltmesi artırmaz — FACE_CONSENT_VERSION ile aynı rıza
#: yorgunluğu kuralı. İstemcideki `kAiConsentVersion` ile elle senkron.
AI_CONSENT_VERSION = 1


def _ai_local_store():
    """Firestore yokken AI onayının yerel dosyası.

    Yüz rızası dosyasından AYRI: testler bu yolu geçici dizine pinliyor
    (conftest) — paylaşılsaydı bir testin yazdığı "reddetti" kaydı sonraki
    testlerin AI uçlarını 403'e düşürürdü.
    """
    return config.CACHE_DIR / "ai_consent.json"


def _ai_local_read() -> dict[str, Any]:
    path = _ai_local_store()
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _ai_local_write(kayitlar: dict[str, Any]) -> bool:
    try:
        _ai_local_store().write_text(
            json.dumps(kayitlar, ensure_ascii=False), encoding="utf-8")
        return True
    except Exception as exc:
        logger.warning("Yerel AI onayı yazılamadı: %s", exc)
        return False


def _ai_doc(uid: str):
    client = firestore_client.get_client()
    if client is None:
        return None
    return (client.collection("users").document(uid)
            .collection("private").document("aiConsent"))


def ai_consent(uid: str) -> dict[str, Any] | None:
    """Kayıtlı AI onayı kaydı; hiç kayıt yoksa ``None``.

    Okuma hatasında FIRLATIR — ``None`` DÖNMEZ. Ayrım önemli: ``None``
    "kullanıcıya hiç sorulmadı" demek ve eski istemcilere izin veren dal
    ona bağlı (bkz. core/ai_consent.izin_karari). Okuma hatasını "kayıt
    yok"a çevirmek, onayı AÇIKÇA geri almış kullanıcının verisini bir
    Firestore hıçkırığında Gemini'ye göndermek olurdu. Kararı çağıran
    verir ve hata yolunda kapalı tarafa düşer.
    """
    doc_ref = _ai_doc(uid)
    if doc_ref is None:
        return _ai_local_read().get(uid)
    snapshot = doc_ref.get()
    if not snapshot.exists:
        return None
    return snapshot.to_dict() or None


def has_ai_consent(uid: str) -> bool:
    """Güncel sürüm için verilmiş bir onay var mı? Hata → False."""
    try:
        kayit = ai_consent(uid)
    except Exception as exc:
        logger.warning("AI onayı okunamadı (%s): %s", uid, exc)
        return False
    return ai_kaydi_gecerli(kayit)


def ai_kaydi_gecerli(kayit: Any) -> bool:
    """Kayıt GÜNCEL sürüm için verilmiş bir onay mı?

    `is True` ve int kontrolü `has_face_consent` ile aynı gerekçeyle:
    bozuk bir değer ("true" metni, bool sürüm) onay SAYILMAZ.
    """
    if not isinstance(kayit, dict) or kayit.get("granted") is not True:
        return False
    surum = kayit.get("version")
    if not isinstance(surum, int) or isinstance(surum, bool):
        return False
    return surum >= AI_CONSENT_VERSION


def _ai_yaz(uid: str, kayit: dict[str, Any]) -> bool:
    doc_ref = _ai_doc(uid)
    if doc_ref is None:
        kayitlar = _ai_local_read()
        kayitlar[uid] = kayit
        return _ai_local_write(kayitlar)
    try:
        # merge DEĞİL, tam yazım: onay/geri alma kaydı bir DURUMDUR, alan
        # alan birleşirse eski `grantedAt` geri alınmış kaydın içinde
        # kalır ve "şu an onaylı mı" okuması yanıltıcı görünür.
        doc_ref.set(kayit)
        return True
    except Exception as exc:
        logger.warning("AI onayı yazılamadı (%s): %s", uid, exc)
        return False


def grant_ai_consent(uid: str, version: int, locale: str) -> bool:
    """AI aktarım onayını kaydeder — zaman damgası + GÖSTERİLEN sürüm.

    Sürüm istemciden gelir (şartlar kabulüyle aynı ilke): ispat,
    kullanıcının GÖRDÜĞÜ metne bağlanmalı. Eski bir istemci eski metni
    göstermişse kayıt bunu söyler ve `ai_kaydi_gecerli` onu güncel
    saymaz — kullanıcıya yeni metin yeniden sorulur.
    """
    return _ai_yaz(uid, {
        "granted": True,
        "version": int(version),
        "grantedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "locale": locale,
    })


def withdraw_ai_consent(uid: str, locale: str) -> bool:
    """Onayı geri alır ya da "Şimdi değil" kararını kaydeder.

    Kayıt SİLİNMEZ, ``granted: False`` yazılır: "hiç sorulmadı" (kayıt
    yok) ile "soruldu ve hayır dedi" FARKLI durumlar. İlki eski
    istemcilere zorlama eşiği gelene kadar izin verir; ikincisi her
    sürümde ve arka plandaki sabah bildiriminde de AI'yı kapatır. Silmek,
    kullanıcının açık "hayır"ını "hiç sorulmadı"ya çevirirdi.
    """
    return _ai_yaz(uid, {
        "granted": False,
        "version": AI_CONSENT_VERSION,
        "withdrawnAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "locale": locale,
    })

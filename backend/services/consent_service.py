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
# Üçüncü taraf AI (Google Gemini) aktarım onayı — kurulumdaki ikinci kutu
# --------------------------------------------------------------------------
#
# Sahip kararı 2026-10-22: onay kurulumun ilk adımında, şartlar kutusunun
# altındaki İKİNCİ, AYRI ve ZORUNLU bir kutuyla bir kez alınır. Bu kayıt o
# kutunun İSPATIDIR, kapısı DEĞİL: hiçbir AI ucu ve bildirim yolu onu
# okumaz, hiçbir özellik onay yüzünden kapanmaz ya da kötüleşmez. 53'ten
# güncelleyen kullanıcı kutuyu hiç görmez ve onun adına kayıt YAZILMAZ —
# işaretlemediği kutunun kaydı olmaz. Bu yüzden burada okuma, geçerlilik
# kararı ve "hayır" yazan bir yol yok; geri alma yolu hesabı silmek.
#
# Şartlar kutusundan AYRI kutu ve yüz rızasından AYRI kayıt, çünkü konuları
# ayrı: bu, kişisel verinin (harita, sohbet, günlük, kişi etiketleri...)
# ÜÇÜNCÜ bir tarafa — Google'ın Gemini API'sine — gönderilmesi. Birini
# diğerinin içine gömmek GDPR Md.7(2)'nin geçersiz saydığı "paket rıza"
# olurdu.
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

#: AI aktarım onayı metninin güncel sürümü — istemci sürüm göndermezse
#: kayda yazılan varsayılan.
#:
#: Kayıt, kullanıcının GÖRDÜĞÜ metnin sürümünü taşır (istemci gönderir;
#: şartlar kabulüyle aynı ilke). Gönderilen veri KATEGORİSİ ya da sağlayıcı
#: değiştiğinde istemcideki karşılığıyla birlikte artırılır ki yeni kayıtlar
#: yeni metne bağlansın; yazım düzeltmesi artırmaz (FACE_CONSENT_VERSION ile
#: aynı rıza yorgunluğu kuralı). Sunucu eski sürümlü kaydı reddetmez ve
#: kimseye yeniden sormaz — kayıt kapı değil ispat.
AI_CONSENT_VERSION = 1


def _ai_local_store():
    """Firestore yokken AI onayının yerel dosyası.

    Yüz rızası dosyasından AYRI: o dosya kayıtları çıplak uid anahtarıyla
    tutuyor; aynı dosyaya yazılsaydı AI onayı aynı kullanıcının yüz
    rızasının ÜZERİNE yazılırdı.
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


def grant_ai_consent(uid: str, version: int, locale: str) -> bool:
    """Kurulumdaki AI onayını kaydeder — zaman damgası + GÖSTERİLEN sürüm.

    Sürüm istemciden gelir (şartlar kabulüyle aynı ilke): ispat,
    kullanıcının GÖRDÜĞÜ metne bağlanmalı. Eski bir istemci eski metni
    göstermişse kayıt bunu söyler.

    Tam yazım, merge DEĞİL: kaydın tek yazanı bu fonksiyon ve tekrarı
    (ağ hatasında yeniden deneyen istemci) aynı durumu yeniden yazar —
    zararsız. Alan alan birleşseydi ileride değişen bir kayıt biçiminin
    eski alanları yeni kaydın içinde kalırdı.
    """
    kayit = {
        "granted": True,
        "version": int(version),
        "grantedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "locale": locale,
    }
    doc_ref = _ai_doc(uid)
    if doc_ref is None:
        kayitlar = _ai_local_read()
        kayitlar[uid] = kayit
        return _ai_local_write(kayitlar)
    try:
        doc_ref.set(kayit)
        return True
    except Exception as exc:
        logger.warning("AI onayı yazılamadı (%s): %s", uid, exc)
        return False

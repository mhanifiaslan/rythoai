"""TTL önbelleği — süreç içi bellek + paylaşımlı kalıcı arka uç.

Gemini yorumları maliyet kontrolü için önbelleklenir. İki katman vardır:

1. **Bellek katmanı** — instance ömrü boyunca yaşayan küçük bir LRU. Aynı
   anahtarın arka arkaya okunması (ör. günlük burç yorumunu isteyen her
   kullanıcı) tek bir Firestore okumasına düşer.
2. **Kalıcı katman** — `config.CACHE_BACKEND` ile seçilir:
   - ``firestore``: instance'lar arasında **paylaşımlıdır**. Kullanıcıdan
     bağımsız içerikte (burç yorumu) "dönem başına tek LLM çağrısı" garantisi
     ancak bununla sağlanır; Cloud Run'ın yerel diski geçici ve instance'a
     özeldir.
   - ``file``: lokal geliştirme içindir, bağımlılık gerektirmez.

Önbellek hiçbir koşulda isteği düşürmez: kalıcı katmandaki her hata loglanır
ve önbellek yokmuş gibi devam edilir (en kötü durumda yorum yeniden üretilir).

Ama ``set`` artık SESSİZ değil: yazımın kalıcı katmana GERÇEKTEN inip
inmediğini döndürür. Fail-open korunuyor — fırlatmaz, ve mevcut
çağıranların hiçbiri dönüşü kullanmak zorunda değil. Kapanan şey
yalnızca şu: bilmeden "yazdım" demek. Bedeli ``set``in gövdesinde
ölçüldü.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import logging
import threading
import time
from collections import OrderedDict
from typing import Any

from core import config, firestore as firestore_client

logger = logging.getLogger(__name__)

#: Bellek katmanında tutulacak en fazla anahtar sayısı.
_MEMORY_MAX_ENTRIES = 512

#: key -> (value, expires_at epoch)
_memory: "OrderedDict[str, tuple[Any, float]]" = OrderedDict()
_memory_lock = threading.Lock()

def _digest(key: str) -> str:
    """Anahtarı sabit uzunlukta, dosya adı ve Firestore doküman kimliği olarak
    güvenli bir sağlamaya indirger."""
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:32]


# --------------------------------------------------------------------------
# Bellek katmanı
# --------------------------------------------------------------------------

def _memory_get(key: str) -> Any | None:
    with _memory_lock:
        entry = _memory.get(key)
        if entry is None:
            return None
        value, expires_at = entry
        if expires_at < time.time():
            _memory.pop(key, None)
            return None
        _memory.move_to_end(key)
        return value


def _memory_set(key: str, value: Any, expires_at: float) -> None:
    with _memory_lock:
        _memory[key] = (value, expires_at)
        _memory.move_to_end(key)
        while len(_memory) > _MEMORY_MAX_ENTRIES:
            _memory.popitem(last=False)


# --------------------------------------------------------------------------
# Dosya arka ucu (lokal geliştirme)
# --------------------------------------------------------------------------

def _file_get(key: str) -> tuple[Any, float] | None:
    path = config.CACHE_DIR / f"{_digest(key)}.json"
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        expires_at = float(payload["expires_at"])
        if expires_at < time.time():
            path.unlink(missing_ok=True)
            return None
        return payload["value"], expires_at
    except Exception:
        return None


def _file_set(key: str, value: Any, expires_at: float) -> bool:
    path = config.CACHE_DIR / f"{_digest(key)}.json"
    payload = {"expires_at": expires_at, "value": value}
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return True


# --------------------------------------------------------------------------
# Firestore arka ucu (üretim, instance'lar arası paylaşımlı)
# --------------------------------------------------------------------------

def _cache_doc(key: str):
    """Anahtara karşılık gelen Firestore doküman referansı; istemci yoksa ``None``."""
    client = firestore_client.get_client()
    if client is None:
        return None
    return client.collection(config.CACHE_COLLECTION).document(_digest(key))


def _firestore_get(key: str) -> tuple[Any, float] | None:
    doc_ref = _cache_doc(key)
    if doc_ref is None:
        return None
    snapshot = doc_ref.get()
    if not snapshot.exists:
        return None

    data = snapshot.to_dict() or {}
    expires_at = data.get("expiresAt")
    if expires_at is None:
        return None

    # Firestore timestamp'i timezone-aware datetime olarak döner.
    expires_epoch = expires_at.timestamp()
    if expires_epoch < time.time():
        # TTL politikası devrede olsa bile silme birkaç gün gecikebilir;
        # okuma anında da temizliyoruz.
        try:
            doc_ref.delete()
        except Exception:
            pass
        return None

    return data.get("value"), expires_epoch


def _firestore_set(key: str, value: Any, expires_at: float,
                   owner_uid: str | None = None) -> bool:
    doc_ref = _cache_doc(key)
    if doc_ref is None:
        # İstemci YOKKEN yazım atlanıyor ve bu bir hata DEĞİL — ama kalıcı
        # katman açısından sonucu hatayla birebir aynı: paylaşımlı kayıt
        # oluşmadı. Çağıranın ikisini ayırt etmesi gerekmediği için tek
        # bir "yazılmadı" hükmü dönüyor; sebep zaten log'da.
        return False
    kayit = {
        "value": value,
        "expiresAt": dt.datetime.fromtimestamp(expires_at, tz=dt.timezone.utc),
        # Hata ayıklama için: hangi mantıksal anahtarın sağlaması olduğu.
        "keyHint": key[:200],
    }
    if owner_uid:
        # Doküman kimliği anahtarın SHA-256 özeti olduğu için kayıtlar
        # kullanıcıya göre SORGULANAMAZ. Hesap silindiğinde kişiye özel
        # üretimlerin de silinmesi gerektiğinden sahiplik ayrı bir alanda
        # tutulur. Paylaşımlı kayıtlarda (burç yorumu, gökyüzü) bu alan yoktur.
        kayit["ownerUid"] = owner_uid
    doc_ref.set(kayit)
    return True


# --------------------------------------------------------------------------
# Genel API — çağıranlar arka uçtan habersizdir
# --------------------------------------------------------------------------

def _persistent_get(key: str) -> tuple[Any, float] | None:
    if config.CACHE_BACKEND == "firestore":
        return _firestore_get(key)
    return _file_get(key)


def _persistent_set(key: str, value: Any, expires_at: float,
                    owner_uid: str | None = None) -> bool:
    if config.CACHE_BACKEND == "firestore":
        return _firestore_set(key, value, expires_at, owner_uid)
    return _file_set(key, value, expires_at)


def get(key: str) -> Any | None:
    """Önbellekten değeri döndürür; yoksa veya süresi dolmuşsa ``None``."""
    value = _memory_get(key)
    if value is not None:
        return value

    try:
        entry = _persistent_get(key)
    except Exception as exc:
        logger.warning("Önbellek okunamadı (%s): %s", config.CACHE_BACKEND, exc)
        return None

    if entry is None:
        return None

    value, expires_at = entry
    _memory_set(key, value, expires_at)
    return value


def set(key: str, value: Any, ttl_seconds: int = 24 * 3600,
        owner_uid: str | None = None) -> bool:
    r"""Değeri hem bellek hem kalıcı katmana yazar; KALICI yazımı bildirir.

    Kalıcı katmandaki hata isteği düşürmez; loglanır ve ``False`` döner.
    Fail-open BİLEREK korunuyor: bir Firestore hıçkırığı, kullanıcının
    ödediği raporu düşürmemeli.

    Dönüş **yalnız kalıcı katmanı** anlatır, bellek katmanını değil —
    bellek yazımı hiç düşmez ve düşmediği için hiçbir şey kanıtlamaz:
    instance'a özeldir (max-instances 3) ve süreç ölünce gider.

    NEDEN dönüş gerekti (ölçüldü 2026-10-02): hata yutulduğu sürece
    çağıran başarıyı başarısızlıktan ayırt EDEMİYORDU ve geri-okumayla
    da ayırt edemezdi, çünkü ``get`` önce belleğe bakıp aynı süreçte
    yazılmış değeri bulur. Somut bedel burç ısıtmasında görüldü:
    ``/maintenance/horoscope-warm`` "isinan: 24" + HTTP 200 dönerken
    paylaşımlı önbelleğe hiçbir şey yazılmamış olabiliyordu — yani
    ısıtmanın TAM AMACI (sabah ilk açan beklemesin) boşa gidiyor ve
    karşılığında yalnız Gemini faturası kalıyordu.

    ⚠️ Dönüş tipi ``None``dan ``bool``a GENİŞLETİLDİ ve bu güvenliydi,
    varsayımla değil ARAMAYLA: ``cache.set``in dönüşünü kullanan hiçbir
    çağrı yeri YOK (``grep -rn '= *cache\.set|if cache\.set|not
    cache\.set|return cache\.set'`` boş döndü), yani her çağıran
    eskisi gibi fail-open kalıyor. Bu DOĞRU hâl: ``admin_service``
    geçersiz kılma, ``signal_service`` sentinel'i ya da ``sky_service``
    mesafe önbelleği yazılamadığında yapılacak bir şey yok — "yazıldı
    mı" yalnız ısıtma yolu için bir ÖLÇÜMDÜR. Dönüşü OKUYAN yeni bir
    çağıran eklenirse gerekçe de yenilenmeli.
    """
    expires_at = time.time() + ttl_seconds
    _memory_set(key, value, expires_at)
    try:
        return _persistent_set(key, value, expires_at, owner_uid)
    except Exception as exc:
        logger.warning("Önbelleğe yazılamadı (%s): %s", config.CACHE_BACKEND, exc)
        return False

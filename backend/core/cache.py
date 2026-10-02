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

Okuma tarafı aynı kusuru TERS yönden taşıyordu: ``get`` değeri döndürüyor
ama hangi katmandan geldiğini SÖYLEMİYORDU, dolayısıyla ona dayanan her
"sıcak/önbellekten" raporu yalnız *bu süreçte okunabildiğini* kanıtlıyordu.
``get_katmanli`` katmanı da döndürür; gerekçe onun gövdesinde.
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


#: ``get_katmanli`` dönüşündeki katman adları. Düz dize, enum DEĞİL: değer
#: sayaç adlarına ve log satırlarına giriyor; enum çağıran her yerde bir
#: ``.value`` daha yazdırır ve karşılığında hiçbir şey kazandırmazdı.
KATMAN_YOK = "yok"
KATMAN_BELLEK = "bellek"
KATMAN_KALICI = "kalici"


def kalici_katman_paylasimli() -> bool:
    """Kalıcı katman instance'lar ARASINDA paylaşımlı mı?

    ``KATMAN_KALICI`` tek başına "paylaşımlı" DEMEK DEĞİL ve bu ayrımı
    atlamak tam olarak kaçınılan kusuru üretirdi: ``file`` arka ucu da
    kalıcıdır ama Cloud Run'ın yerel diski instance'a özeldir ve kap
    ölünce gider. "Isındı" hükmü ancak katman kalıcı **ve** arka uç
    firestore iken doğrudur; ikisini tek kelimeye indirmek ölçüleni
    (okunabildi) yanlış adla (paylaşımlı) sunmak olurdu.
    """
    return config.CACHE_BACKEND == "firestore"


def get_katmanli(key: str) -> tuple[Any | None, str]:
    """Değeri **ve geldiği katmanı** döndürür.

    NEDEN ayrı bir işlev var (ölçüldü 2026-10-02): ``get``in dönüşü
    isabetin HANGİ katmandan geldiğini söylemiyordu, bu yüzden ona dayanan
    her "sıcak" raporu ölçtüğünden fazlasını iddia ediyordu. İki yer:

    * ``api/maintenance.py`` ısıtma sayacı ``zaten_sicak`` — gerçekte
      yalnız "BU SÜREÇTE okunabildi" demek. Bellek katmanı instance'a
      özeldir (max-instances 3) ve süreç ölünce gider; haftalık/aylık
      işler her gece koştuğu için bir önceki koşunun aynı instance'ta
      bıraktığı değeri bulmak gerçek bir olasılık. Yani "zaten sıcak"
      sayılan bir kombinasyon paylaşımlı katmanda HİÇ olmayabilir ve
      ısıtmanın tek amacı (sabah ilk açan beklemesin) ölçülmemiş kalır.
      **BAĞLANDI** (2026-10-03): ısıtma artık ``_katman_olc`` ile buraya
      geliyor ve sayaç ikiye ayrıldı (``paylasimli_sicak`` /
      ``paylasimsiz_sicak``); 503 kapısı yalnız birincisine güveniyor.
      ⚠️ İkinci ad bir KONUM değil ölçümün SINIRINI anlatıyor
      ("paylaşımlılık ölçülemedi"): ``KATMAN_YOK`` isabeti de o
      kovaya düşüyor, yani ``surec_sicak`` gibi bir ad üç durumdan
      birinde yalan olurdu — gerekçesi ``_sicaklik_adi``de.
      ⚠️ Çağrı ÜRETİMDEN ÖNCE yapılmak zorunda — aşağıdaki bellek
      terfisi yüzünden ikinci okuma her zaman ``KATMAN_BELLEK`` döner.
    * ``services/report_service.py:_cached_generate`` yanıtındaki
      ``cached: True`` — aynı sınıf iddia. Orada ``persisted`` anahtarı
      bilerek YOKTU, çünkü katman ölçülmemişti; artık ölçülebiliyor.

    ``set``in dönüşü (yazım tarafı) bu turun BİR ÖNCESİNDE kapandı; bu
    onun okuma tarafı ve ikisi aynı kusurun iki yüzüydü.

    İmza NEDEN ``get``ten ayrı: ``cache.get`` depoda ONLARCA yerden
    çağrılıyor ve dönüş şeklini demet yapmak hepsini birden kırardı —
    bu, katman ayrımının bir tur boyunca "yapılmadı" diye
    kaydedilmesinin de gerekçesiydi.

    ⚠️ Buraya sayı iki tur üst üste ÇİVİLENDİ ve ikisi de yanlış
    çıktı: önce "31 / 44", sonra "ölçüldü: 32 ve 45". Doğrulama turunda
    (2026-10-02) kağıt üzerinde değil kaynaktan yeniden sayıldı: 31
    uygulama + 13 test çağrısı. "32/45" bir YANLIŞ POZİTİFTEN geliyor —
    kaba bir ``cache.get(`` taraması ``core/device.py``deki yerel
    ``_cache`` SÖZLÜĞÜNÜN ``.get``ini de sayar, oysa o bu modül değil.
    Dersin asıl yeri sayı DEĞİL: bu sayı her turda değişiyor, yoruma
    çivilenince bayatlıyor ve bir sonraki okuyucu yanlış bir
    "ölçüldü"ye güveniyor. Gerekçeyi taşıyan şey büyüklük sırası:
    ONLARCA okuyucu var (``report_service`` tek başına 14'ünü tutuyor),
    yani demet dönüşü hepsini birden kırardı.

    İki işlev tek kod yolunu paylaşıyor (``get`` bunu sarıyor), yani
    ikisi sessizce ayrışamaz.

    Dönen katman ``KATMAN_BELLEK`` ise bu değerin kalıcı katmanda
    OLMADIĞINI göstermez — yalnız oraya BAKILMADIĞINI gösterir; bellek
    isabeti kalıcı okumayı bilerek atlıyor (maliyet kapısı). Kalıcı
    katmanda durduğunu kanıtlamak isteyen çağıran ya yazımın hükmünü
    (``set`` dönüşü) kullanır ya da belleği boşaltıp yeniden sorar.
    """
    value = _memory_get(key)
    if value is not None:
        return value, KATMAN_BELLEK

    try:
        entry = _persistent_get(key)
    except Exception as exc:
        logger.warning("Önbellek okunamadı (%s): %s", config.CACHE_BACKEND, exc)
        return None, KATMAN_YOK

    if entry is None:
        return None, KATMAN_YOK

    value, expires_at = entry
    _memory_set(key, value, expires_at)
    return value, KATMAN_KALICI


def get(key: str) -> Any | None:
    """Önbellekten değeri döndürür; yoksa veya süresi dolmuşsa ``None``.

    Katmana ihtiyacı olmayan çağıranlar için ince sarmalayıcı. Gövde
    ``get_katmanli``de TEK kopya duruyor: iki ayrı okuma yolu yazılsaydı
    (biri katmanlı, biri değil) bellek terfisi ya da TTL kapısı birinde
    değişip ötekinde kalabilirdi — ve bu fark yalnız canlıda görünürdü.
    """
    return get_katmanli(key)[0]


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

"""Önbellek yazımının BİLDİRİLMESİ (ölçüldü 2026-10-02).

`core/cache.py:set` kalıcı katman hatasını `logger.warning` ile yutuyor ve
HİÇBİR ŞEY döndürmüyordu; `services/report_service.py:_cached_generate` de bu
yüzden yazım düşse de başarı döndürüyordu. Görünür bedel burç ısıtmasındaydı:
`/api/v1/maintenance/horoscope-warm` "isinan: 24" + HTTP 200 raporlarken
paylaşımlı önbelleğe hiçbir şey yazılmamış olabiliyordu — ısıtmanın TAM AMACI
(sabah ilk açan beklemesin) sessizce boşa gidiyor, karşılığında yalnız 24
Gemini üretiminin faturası kalıyordu.

Bu dosyanın bekçileri üç şeyi birden çiviliyor:

1. **Fail-open KORUNUYOR.** `set` hâlâ fırlatmıyor ve bellek katmanı hâlâ
   doluyor — bir Firestore hıçkırığı kullanıcının ödediği raporu düşürmemeli.
2. **Ama sessiz değil.** Dönüş "kalıcı katmana yazıldı mı"yı söylüyor.
3. **Zincir kopmuyor.** `horoscope_reading` → `_cached_generate` yanıtında
   `persisted` ANAHTARI gerçekten var; ısıtma ucunun sahte fikstürü o anahtarı
   taklit ediyor ve taklidin gerçeğe uyduğu burada ölçülüyor. Bu bağ olmadan
   `test_horoscope_warm.py` kendi uydurduğu bir sözleşmeyi sınardı.

Geri-okuma NEDEN kanıt değil: `cache.get` ÖNCE belleğe bakıyor ve aynı süreçte
yazılan değeri orada buluyor. Yani "yazdım mı" sorusu okumayla cevaplanamaz —
yazımın kendisinin konuşması gerekiyordu.

## Okuma tarafı (bir sonraki turun B2 maddesi)

Aynı kusurun ÖTEKİ yüzü: `cache.get` değeri döndürüyor ama hangi KATMANDAN
geldiğini söylemiyordu. Bu yüzden ona dayanan iki rapor da ölçtüğünden
fazlasını iddia ediyordu — ısıtma ucunun `zaten_sicak` sayacı ve
`_cached_generate` yanıtındaki `cached: True` yalnızca "BU SÜREÇTE
okunabildi" demek. Bellek katmanı instance'a özeldir (max-instances 3) ve
süreç ölünce gider; ısıtmanın TEK amacı paylaşımlı katmanı doldurmak
olduğuna göre o sayaç ısıtmanın işe yaradığını kanıtlamıyordu.

`cache.get_katmanli` katmanı da döndürüyor ve aşağıdaki bekçiler üç şeyi
çiviliyor: (1) aynı süreçte yazılan değer `bellek` diye okunur — yani
geri-okuma hâlâ kanıt değil ve bu artık GÖRÜNÜR; (2) kalıcı katmandan gelen
isabet `kalici` diye adlandırılır; (3) `kalici` tek başına "paylaşımlı"
DEMEK DEĞİL (`file` arka ucu da kalıcıdır, ama instance'a özeldir) —
`kalici_katman_paylasimli()` o ayrımı ayrı tutuyor.

Tüketiciler BAĞLANDI (yeniden ölçüldü 2026-10-03; bu paragraf bir tur
boyunca "tüketiciler HENÜZ geçmedi" diyordu ve o gerekçe BAYATLAMIŞTI —
yanlış gerekçe taşıyan yorum bu depoda kusur sayılır). Ölçüm:
`grep -rn -e get_katmanli -e kalici_katman_paylasimli api core services` →
`api/maintenance.py` ısıtma yolunda `_katman_olc` ile çağırıyor ve sayaç
ikiye ayrıldı (`paylasimli_sicak` / `paylasimsiz_sicak`); 503 kapısı yalnız
birincisine güveniyor. `services/report_service.py` isabette hâlâ katman
İDDİA ETMİYOR ve bu DOĞRU hâl — gerekçesi `cache.get`in bellek terfisinde,
aşağıdaki `test_onbellek_isabetinde_persisted_IDDIA_EDILMEZ`de çivili.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_onbellek_yazim_raporu.py -q
"""
from __future__ import annotations

import datetime as dt

import pytest

from core import cache, config
from services import report_service


@pytest.fixture(autouse=True)
def temiz_bellek():
    """Bellek katmanı süreç ömürlü: testler arası sızıntı yanlış yeşil üretir."""
    cache._memory.clear()
    yield
    cache._memory.clear()


@pytest.fixture()
def dosya_arka_ucu(monkeypatch, tmp_path):
    """Kalıcı katman GERÇEKTEN yazsın — sahte değil, diske.

    `conftest`in `firestore_hermetik` pini `get_client`i None yapıyor, yani
    firestore arka ucu testte hiçbir şey yazamaz. Dosya arka ucu bu yüzden
    "yazım başarılı" dalının ölçülebildiği tek yol.
    """
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    return tmp_path


# ---------------------------------------------------------------------------
# cache.set: yazımın hükmü
# ---------------------------------------------------------------------------

def test_yazim_basariliysa_True_doner(dosya_arka_ucu):
    assert cache.set("yazildi", "deger", ttl_seconds=60) is True
    # Hüküm iddia değil ÖLÇÜM olsun: dosya gerçekten orada.
    assert list(dosya_arka_ucu.glob("*.json")), "kalıcı katmana dosya inmedi"


def test_kalici_katman_patlayinca_False_doner(dosya_arka_ucu, monkeypatch):
    """Yutulan hata artık hükme dönüşüyor.

    Onarımdan önce burada `None` dönüyordu ve çağıran başarıyı
    başarısızlıktan AYIRT EDEMİYORDU.
    """
    def patla(*a, **kw):
        raise RuntimeError("Firestore yazilamadi")

    monkeypatch.setattr(cache, "_persistent_set", patla)
    assert cache.set("patlak", "deger", ttl_seconds=60) is False


def test_patlayan_yazim_istegi_DUSURMEZ(dosya_arka_ucu, monkeypatch):
    """Fail-open bilinçli: bir Firestore hıçkırığı ödenmiş raporu düşürmemeli.

    Bu bekçi onarımın kendi doğurabileceği riski kapatıyor — `set`in hükmü
    `raise`a çevrilse yirmi çağıran bir anda kırılgan hâle gelirdi.
    """
    def patla(*a, **kw):
        raise RuntimeError("Firestore yazilamadi")

    monkeypatch.setattr(cache, "_persistent_set", patla)
    cache.set("fail-open", "deger", ttl_seconds=60)  # fırlatmamalı
    # Bellek katmanı yine dolu: aynı süreçte ikinci okuma hâlâ bedava.
    assert cache.get("fail-open") == "deger"


def test_firestore_istemcisi_yokken_yazilmadi_hukmu(monkeypatch):
    """İstemci YOKKEN yazım sessizce atlanıyordu — hata değil ama SONUÇ aynı.

    Kalıcı katman açısından kayıt oluşmadı; çağıran için fark yok. Bu dal
    canlıda gerçek bir olasılık (kimlik/izin kurulmamış bir instance) ve
    eskiden hiçbir yerde görünmezdi.

    ⚠️ Geri-okuma bu kusuru GÖSTERMEZ: `cache.get` önce belleğe bakar ve
    aynı süreçte yazılan değeri bulur. Altta o da sınanıyor, çünkü "okudum,
    demek ki yazdım" çıkarımı tam olarak bu turda yanlış çıktı.
    """
    monkeypatch.setattr(config, "CACHE_BACKEND", "firestore")
    # `conftest.firestore_hermetik` zaten `get_client`i None'a pinliyor;
    # burada açıkça yazılması bekçinin neyi ölçtüğünü okunur kılıyor.
    monkeypatch.setattr(cache.firestore_client, "get_client", lambda: None)
    assert cache.set("istemcisiz", "deger", ttl_seconds=60) is False
    assert cache.get("istemcisiz") == "deger", (
        "bellek katmanı okunuyor — yani geri-okuma yazımı kanıtlamaz")


# ---------------------------------------------------------------------------
# Firestore arka ucunun BAŞARI dalı — bir tur boyunca hiç koşmadı
# ---------------------------------------------------------------------------
#
# `_firestore_set`in `doc_ref.set(kayit)` + `return True` dalı yalnız KOD
# OKUMASIYLA doğru sayılıyordu: `conftest.firestore_hermetik` `get_client`i
# None'a pinliyor, yani üretimde kullanılan tek arka ucun yazan dalı testte
# HİÇ çalışmıyordu. Sonuç: o daldaki bir düzenleme (alan adı kayması,
# yazımı atlayıp True dönme) hiçbir yerde kırmızı olmazdı — ve bu tam
# olarak bu dosyanın kapattığı kusurun geri gelme yolu, çünkü ısıtma
# "yazıldı" hükmünü buradan okuyor.
#
# ⚠️ Sahte istemci GERÇEK Firestore'u KANITLAMAZ ve bu bekçi öyle bir iddia
# TAŞIMIYOR. Açık kalan hâl kayıtta duruyor: `doc_ref.set()` hata
# fırlatmadan ama yazmadan dönen bir istemci sürümü (ör. batch'e kuyruklayan
# bir sarmalayıcı) hâlâ `True` üretirdi; onun kanıtı ancak canlı/emülatör
# yazımıyla gelir. Burada ölçülen şey DAHA DAR: dal çalışıyor, çağrı
# yapılıyor ve hüküm o çağrıya BAĞLI.


class _SahteAnlik:
    """`doc_ref.get()` dönüşü — gerçek istemcinin snapshot sözleşmesi.

    `exists` + `to_dict()` ikilisi ZORUNLU: `_firestore_get` ikisine de
    bakıyor ve yalnız birini taşıyan bir sahte, var olmayan dokümanı
    "isabet" sayardı — yani bekçi kusuru ÖLÇMEK yerine üretirdi.
    """

    def __init__(self, kayit: dict | None):
        self._kayit = kayit
        self.exists = kayit is not None

    def to_dict(self):
        return None if self._kayit is None else dict(self._kayit)


class _SahteDoc:
    """Tek dokümanlık sahte: yazılan gövdeyi olduğu gibi tutar.

    OKUMA da gerekiyor (eklendi 2026-10-03, mutasyonla ölçüldü): sahte
    yalnız `set` taşıdığı sürece üretimde kullanılan tek arka ucun OKUYAN
    dalı (`_firestore_get`) hiçbir testte koşmuyordu. Ölçülen boşluk:
    `return data.get("value"), expires_epoch` satırı `return None`a
    çevrildiğinde — yani PAYLAŞIMLI önbellek üretimde HİÇ isabet
    etmediğinde — ilgili on test dosyası (274 test) YEŞİL kalıyordu.
    Önemi bu paketin tam merkezinde: `isinan` / `paylasimli_sicak`
    sayaçları ve `KATMAN_KALICI` hükmü bu dalın doğruluğuna dayanıyor,
    dolayısıyla "ısındı" raporu kod okumasından öteye geçmiyordu.
    """

    def __init__(self, kimlik: str, depo: dict):
        self.kimlik = kimlik
        self._depo = depo
        # Silme AYRI tutuluyor: `_firestore_get` süresi dolmuş kaydı
        # okuma anında siliyor ve o temizliğin GERÇEKTEN olduğu
        # ölçülmeli (TTL politikası günlerce gecikebiliyor).
        self.silinenler = depo.setdefault("__silinenler__", [])

    def set(self, kayit, merge=False):  # noqa: ARG002
        self._depo[self.kimlik] = dict(kayit)

    def get(self):
        return _SahteAnlik(self._depo.get(self.kimlik))

    def delete(self):
        self.silinenler.append(self.kimlik)
        self._depo.pop(self.kimlik, None)


class _SahteKoleksiyon:
    def __init__(self, ad: str, depo: dict):
        self.ad = ad
        self._depo = depo

    def document(self, kimlik: str):
        return _SahteDoc(kimlik, self._depo)


class _SahteClient:
    def __init__(self, depo: dict):
        self.depo = depo
        self.koleksiyonlar: list[str] = []

    def collection(self, ad: str):
        self.koleksiyonlar.append(ad)
        return _SahteKoleksiyon(ad, self.depo)


@pytest.fixture()
def firestore_arka_ucu(monkeypatch):
    """Yazan VE okuyan dal GERÇEKTEN koşsun: arka uç firestore + sahte
    istemci."""
    monkeypatch.setattr(config, "CACHE_BACKEND", "firestore")
    istemci = _SahteClient({})
    monkeypatch.setattr(cache.firestore_client, "get_client",
                        lambda: istemci)
    return istemci


def _kayitlar(istemci) -> dict:
    """Sahte depodaki GERÇEK kayıtlar — defter anahtarları hariç.

    `__silinenler__` sahtenin kendi defteri; kayıt sayan iddialar onu
    görmemeli, yoksa "bir doküman indi" iddiası sahtenin kendi
    muhasebesinden YANLIŞ YEŞİL alırdı.
    """
    return {k: v for k, v in istemci.depo.items()
            if not k.startswith("__")}


# ---------------------------------------------------------------------------
# Firestore arka ucunun OKUYAN dalı — bir tur boyunca hiç koşmadı
# ---------------------------------------------------------------------------
#
# Yazan dal bir tur önce çivilendi, OKUYAN dalı ise kaydın "kapalı" sayıldığı
# turda da ölçülmemişti. Mutasyonla ölçüldü (2026-10-03): `_firestore_get`in
# dönüş satırı `return None` yapıldığında — yani üretimdeki PAYLAŞIMLI
# önbellek HİÇ isabet etmediğinde — önbelleğe dokunan on test dosyası (274
# test) YEŞİL kaldı; TTL kapısının yönü (`<` → `>`) de aynı şekilde sessiz
# geçti. Bu, bu paketin kapattığı kusurun TERS yüzü: `isinan`,
# `paylasimli_sicak` ve `KATMAN_KALICI` hükümlerinin HEPSİ bu dalın
# doğruluğuna dayanıyor, dolayısıyla "ısındı" raporu kod okumasından
# öteye geçmiyordu.
#
# ⚠️ Sahte istemci GERÇEK Firestore'u KANITLAMAZ ve bu bekçiler öyle bir
# iddia taşımıyor (yazan daldaki niteleme burada da geçerli). Ölçülen şey
# daha dar: dal çalışıyor, çağrı yapılıyor, hüküm o çağrıya BAĞLI.


def test_firestore_dali_YAZDIGINI_geri_okur(firestore_arka_ucu):
    """Yazım ile okuma AYNI dokümanda buluşmak zorunda.

    Ayrı ayrı doğru iki dal (yazan `set`, okuyan `get`) birbirini
    bulamazsa önbellek HİÇ isabet etmez ve kusur hiçbir sayaçta
    görünmez: ısıtma "isinan: 24" der, her kullanıcı isteği tam LLM
    zincirini yine öder. Bu testin ölçtüğü şey `set`in dönüşü DEĞİL,
    yuvarlak yol.
    """
    cache.set("fs-okuma-1", "govde", ttl_seconds=600)
    cache._memory.clear()  # bellek terfisi kalıcı okumayı maskelemesin

    deger, katman = cache.get_katmanli("fs-okuma-1")

    assert deger == "govde", "kalıcı katmana yazılan değer geri okunamadı"
    assert katman == cache.KATMAN_KALICI


def test_firestore_okumasi_BELLEK_bos_olmadan_olculemez(firestore_arka_ucu):
    """Yukarıdaki testin `_memory.clear()` satırı KONFOR DEĞİL.

    `get_katmanli` kalıcı katmandan okuduğu değeri belleğe terfi ettiriyor
    ve bellekte duran bir değer kalıcı okumayı hiç tetiklemiyor. Bu test o
    gerekçeyi ölçüyor: bellek dolu iken aynı anahtar `KATMAN_BELLEK`
    dönüyor, yani temizlik olmadan yukarıdaki bekçi kalıcı dalı DEĞİL
    belleği ölçerdi (ve `_firestore_get` tümden bozuk olsa bile yeşil
    kalırdı).
    """
    cache.set("fs-okuma-2", "govde", ttl_seconds=600)

    assert cache.get_katmanli("fs-okuma-2")[1] == cache.KATMAN_BELLEK


def test_firestore_suresi_DOLMUS_kayit_isabet_SAYILMAZ(firestore_arka_ucu):
    """Bayat kayıt isabet sayılırsa kullanıcı DÜNÜN yorumunu okur.

    TTL kapısının YÖNÜ ölçülüyor: ters çevrildiğinde taze kayıt "dolmuş"
    sayılıp silinir ve dolmuş kayıt sunulur — ikisi de sessiz. Günlük burç
    yorumunda bunun adı "gökyüzünü takip eden AI astrolog"un dünkü
    gökyüzünü anlatmasıdır.
    """
    cache.set("fs-bayat", "dunun-yorumu", ttl_seconds=600)
    # Son kullanmayı GERİYE al: kaydı doğrudan bozuyoruz çünkü `set`
    # negatif TTL kabul etse bile o yol üretimde hiç kullanılmıyor.
    (kimlik,) = _kayitlar(firestore_arka_ucu)
    kayit = firestore_arka_ucu.depo[kimlik]
    kayit["expiresAt"] = kayit["expiresAt"] - dt.timedelta(seconds=1200)
    cache._memory.clear()

    deger, katman = cache.get_katmanli("fs-bayat")

    assert deger is None, "süresi dolmuş kayıt isabet sayıldı"
    assert katman == cache.KATMAN_YOK


def test_firestore_suresi_dolmus_kayit_OKUMA_aninda_silinir(
        firestore_arka_ucu):
    """Ters yön: "isabet sayma" yetmez, kayıt da GİTMELİ.

    Firestore'un TTL politikası silmeyi günlerce geciktirebiliyor; okuma
    anında temizlemeyen bir dal, dolmuş kayıtların koleksiyonda birikmesine
    ve her istekte yeniden okunmasına yol açar (fatura + çöp). Bu test o
    çifti kapatıyor: yalnız `return None` eklemek bekçiyi geçmez.
    """
    cache.set("fs-bayat-2", "deger", ttl_seconds=600)
    (kimlik,) = _kayitlar(firestore_arka_ucu)
    kayit = firestore_arka_ucu.depo[kimlik]
    kayit["expiresAt"] = kayit["expiresAt"] - dt.timedelta(seconds=1200)
    cache._memory.clear()

    cache.get("fs-bayat-2")

    assert firestore_arka_ucu.depo["__silinenler__"] == [kimlik]
    assert _kayitlar(firestore_arka_ucu) == {}


def test_firestore_OLMAYAN_anahtar_isabet_uretmez(firestore_arka_ucu):
    """Hiç yazılmamış anahtar "isabet" sayılırsa `None` değeri önbellekten
    gelmiş gibi sunulur, üretim HİÇ yapılmaz ve ekran boş kalır.

    ⚠️ Bu test `exists` KAPISINI ölçmüyor ve bir tur boyunca docstring'i
    öyle diyordu — ölçülünce yanlış çıktı: `if not snapshot.exists`
    satırı `if False` yapıldığında test YEŞİL kalıyor, çünkü var olmayan
    snapshot'ta `to_dict()` `None` döner, `or {}` boş sözlüğe iner ve bir
    satır aşağıdaki `expiresAt is None` kapısı aynı `None`u üretir.
    Yani `exists` burada ikinci bir katman (aynı sonucu bir okuma ucuza
    verir), yükü taşıyan kapı damga kapısıdır — onun bekçisi
    `test_firestore_son_kullanmasiz_kayit_isabet_SAYILMAZ`.
    """
    assert cache.get_katmanli("fs-hic-yazilmadi") == (None, cache.KATMAN_YOK)


def test_firestore_son_kullanmasiz_kayit_isabet_SAYILMAZ(firestore_arka_ucu):
    """Alan adı kayarsa (`expiresAt` → başka bir ad) kayıt SÜRESİZ olurdu.

    `expiresAt` yokken `None` dönmek tek doğru hâl: damgasız bir kaydı
    "taze" saymak, bir kez yazılan yorumun sonsuza dek sunulması demektir
    (TTL politikası da o alanı okuyor, yani kayıt hiç silinmez).
    """
    cache.set("fs-damgasiz", "deger", ttl_seconds=600)
    (kimlik,) = _kayitlar(firestore_arka_ucu)
    del firestore_arka_ucu.depo[kimlik]["expiresAt"]
    cache._memory.clear()

    assert cache.get_katmanli("fs-damgasiz") == (None, cache.KATMAN_YOK)


def test_firestore_dali_GERCEKTEN_yaziyor_ve_hukum_ona_bagli(
        firestore_arka_ucu):
    """`True` bir niyet değil, YAPILAN yazımın hükmü olmak zorunda.

    Mutasyon kontrolü (ölçüldü): `doc_ref.set(kayit)` satırı silinip yalnız
    `return True` bırakıldığında bu test KIRMIZI olur — eskiden hiçbir test
    olmazdı.
    """
    assert cache.set("fs-1", "deger", ttl_seconds=60) is True
    assert len(_kayitlar(firestore_arka_ucu)) == 1, (
        "hüküm True ama kalıcı katmana hiçbir doküman inmedi")
    (kayit,) = _kayitlar(firestore_arka_ucu).values()
    assert kayit["value"] == "deger"
    # Koleksiyon adı yapılandırmadan gelmeli: sabitlenirse üretim ve ısıtma
    # iki AYRI koleksiyona yazar/okur ve ikisi birbirini hiç görmez.
    assert firestore_arka_ucu.koleksiyonlar == [config.CACHE_COLLECTION]


def test_firestore_dokuman_kimligi_ANAHTARIN_ozeti(firestore_arka_ucu):
    """Yazan ve okuyan aynı dokümanı bulmak zorunda.

    Kimlik `_digest(key)` — anahtarın SHA-256 özetinin ilk 32 hanesi.
    Kayma SESSİZ olurdu: ısıtma yazar, kullanıcı isteği başka bir kimliği
    okur, her ikisi de "başarılı" görünür ve önbellek HİÇ isabet etmez
    (her istek tam LLM zincirini öder).
    """
    cache.set("fs-2", "deger", ttl_seconds=60)
    assert list(_kayitlar(firestore_arka_ucu)) == [cache._digest("fs-2")]


def test_firestore_kaydi_son_kullanmayi_UTC_tasir(firestore_arka_ucu):
    """TTL politikası `expiresAt` alanını okuyor; saat dilimsiz bir damga
    Firestore'da yerel saat sanılır ve kayıt yanlış günde silinir."""
    import datetime as dt

    cache.set("fs-3", "deger", ttl_seconds=3600)
    (kayit,) = _kayitlar(firestore_arka_ucu).values()
    son = kayit["expiresAt"]
    assert son.tzinfo is not None, "son kullanma saat dilimsiz yazıldı"
    assert son.utcoffset() == dt.timedelta(0), "UTC değil"


def test_paylasimli_kayit_SAHIPSIZ_kalir(firestore_arka_ucu):
    """Burç yorumu/gökyüzü PAYLAŞIMLI: `ownerUid` yazılırsa tek bir
    kullanıcının hesabını silmesi HERKESİN yorumunu siler."""
    cache.set("fs-4", "deger", ttl_seconds=60)
    (kayit,) = _kayitlar(firestore_arka_ucu).values()
    assert "ownerUid" not in kayit


def test_kisisel_kayit_SAHIPLI_yazilir(firestore_arka_ucu):
    """Ters yön: kişiye özel üretim hesap silindiğinde BULUNABİLİR olmalı.

    Doküman kimliği anahtarın özeti olduğu için kayıtlar kullanıcıya göre
    SORGULANAMAZ; sahiplik ayrı bir alanda tutulmak zorunda.
    """
    cache.set("fs-5", "deger", ttl_seconds=60, owner_uid="u1")
    (kayit,) = _kayitlar(firestore_arka_ucu).values()
    assert kayit["ownerUid"] == "u1"


# ---------------------------------------------------------------------------
# cache.get_katmanli: isabetin HANGİ katmandan geldiği
# ---------------------------------------------------------------------------

def test_ayni_surecte_yazilan_deger_BELLEK_diye_okunur(dosya_arka_ucu):
    """Geri-okuma paylaşımlı katmanı kanıtlamaz — ve artık bunu SÖYLÜYOR.

    `set` değeri iki katmana birden yazıyor; `get` ise önce belleğe bakıyor
    ve oradan dönüyor. Yani kalıcı katman HİÇ okunmadı. Bu dal
    ısıtma/rapor yollarının "sıcak" iddiasının kök nedeniydi: sayaç
    okunabilirliği ölçüp paylaşımlılığı iddia ediyordu.
    """
    cache.set("katman-1", "deger", ttl_seconds=60)
    deger, katman = cache.get_katmanli("katman-1")
    assert deger == "deger"
    assert katman == cache.KATMAN_BELLEK


def test_bellek_bosken_isabet_KALICI_diye_okunur(dosya_arka_ucu):
    """Kalıcı katmandan gelen isabet doğru adla sunulur.

    Bellek bilerek boşaltılıyor: canlıdaki karşılığı yeni bir instance ya
    da yeniden başlamış bir süreç — yani ısıtmanın gerçekten işe yaradığı
    tek senaryo.
    """
    cache.set("katman-2", "deger", ttl_seconds=60)
    cache._memory.clear()
    deger, katman = cache.get_katmanli("katman-2")
    assert deger == "deger"
    assert katman == cache.KATMAN_KALICI
    # Terfi korunuyor: ikinci okuma kalıcı katmanı bir daha yormaz.
    assert cache.get_katmanli("katman-2")[1] == cache.KATMAN_BELLEK


def test_isabet_yoksa_katman_YOK(dosya_arka_ucu):
    deger, katman = cache.get_katmanli("hic-yazilmadi")
    assert deger is None
    assert katman == cache.KATMAN_YOK


def test_kalici_okuma_patlarsa_YOK_doner_ve_FIRLATMAZ(dosya_arka_ucu,
                                                      monkeypatch):
    """Fail-open okuma tarafında da korunuyor.

    Önbellek hiçbir koşulda isteği düşürmez; katman eklemek bu duruşu
    değiştirmemeli — yoksa bir Firestore hıçkırığı onlarca çağrı yerini
    kırılgan hâle getirirdi.
    """
    def patla(*a, **kw):
        raise RuntimeError("Firestore okunamadi")

    monkeypatch.setattr(cache, "_persistent_get", patla)
    assert cache.get_katmanli("patlak-okuma") == (None, cache.KATMAN_YOK)


def test_get_SARMALAYICI_kalmaya_devam_ediyor(dosya_arka_ucu):
    """`cache.get`in şekli DEĞİŞMEDİ: onlarca çağrı yeri demet görmüyor.

    Katman ayrımının bir tur boyunca "yapılmadı" diye kaydedilmesinin
    gerekçesi tam buydu (`api/maintenance.py` yorumunda yazılı): dönüşü
    demet yapmak depodaki tüm okuyucuları birden kırardı.
    """
    cache.set("katman-3", {"a": 1}, ttl_seconds=60)
    assert cache.get("katman-3") == {"a": 1}
    assert cache.get("hic-yok") is None


def test_katman_ADLARI_birbirine_COKEMEZ():
    """Üç katman adı ayrı ayrı anlam taşımak ZORUNDA.

    Bu bekçi MUTASYONLA bulundu (2026-10-02, doğrulama turu): yukarıdaki
    dalların hepsi katmanı ``cache.KATMAN_*`` SABİTİYLE karşılaştırıyor,
    yani sabitin DEĞERİ bozulduğunda hiçbiri kırmızı olmuyordu. İki
    mutasyon ölçüldü ve takımın tamamı (15 test) YEŞİL kaldı:
    ``KATMAN_BELLEK = "kalici"`` — bellek isabeti ile kalıcı isabet
    AYNI adı söylüyor; ve ``KATMAN_YOK = ""`` — isabetsizliğin adı hiç
    kalmıyor.

    Neden bu sessiz bir kusur: değer bir süs değil, ``cache.py``nin kendi
    yorumunda yazdığı gibi sayaç adlarına ve log satırlarına giren ŞEYİN
    KENDİSİ. Adlar çökerse B2'nin kapattığı kusur aynen geri gelir —
    süreç-özel bellekte bulunan değer, paylaşımlı katmandan gelmiş gibi
    raporlanır ve kimse farkı göremez. Boş ad ayrıca YANLIŞ TÜRDEN bir
    tuzak: ``if katman:`` yazan bir tüketici isabetsizliği "ölçülemedi"
    diye değil hiç olmamış gibi geçirir.

    İddia bilerek DAR: adların ne OLDUĞU çivilenmiyor (yeniden
    adlandırma davranışı değiştirmez), yalnız üçünün AYRIŞABİLİR ve
    okunabilir kaldığı.
    """
    adlar = (cache.KATMAN_YOK, cache.KATMAN_BELLEK, cache.KATMAN_KALICI)
    assert len(set(adlar)) == 3, (
        f"katman adları birbirine çöktü ({adlar}): iki ayrı katman aynı"
        " adla raporlanır ve \"sıcak\" iddiası yine ölçtüğünden fazlasını"
        " söyler")
    for ad in adlar:
        assert isinstance(ad, str) and ad.strip(), (
            f"katman adı boş ({adlar}): log satırı ve sayaç adı sessizce"
            " anlamını yitirir")


def test_KALICI_tek_basina_PAYLASIMLI_demek_degil(monkeypatch):
    """"Isındı" hükmü iki koşulun İKİSİNİ birden ister.

    `file` arka ucu da kalıcıdır ama Cloud Run'da yerel disk instance'a
    özeldir ve kap ölünce gider. Katmanı "paylaşımlı" diye adlandırmak
    ölçüleni yanlış adla sunmak olurdu; ayrım ayrı bir işlevde duruyor.
    """
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    assert cache.kalici_katman_paylasimli() is False
    monkeypatch.setattr(config, "CACHE_BACKEND", "firestore")
    assert cache.kalici_katman_paylasimli() is True


# ---------------------------------------------------------------------------
# _cached_generate: hüküm yanıta giriyor
# ---------------------------------------------------------------------------

@pytest.fixture()
def uretim(monkeypatch):
    """LLM zinciri YOK: ölçülen şey yalnız `persisted` bayrağı."""
    monkeypatch.setattr(report_service.gemini_service, "generate",
                        lambda *a, **kw: "uretilen metin")
    monkeypatch.setattr(report_service.fact_guard, "enforce",
                        lambda metin, prompt, **kw: (metin, True))


def test_uretim_yazildiysa_persisted_True(dosya_arka_ucu, uretim):
    sonuc = report_service._cached_generate("ag-1", "prompt", "yedek")
    assert sonuc["persisted"] is True
    assert sonuc["text"] == "uretilen metin"


def test_uretim_yazilamadiysa_persisted_False(dosya_arka_ucu, uretim,
                                              monkeypatch):
    """Onarımdan önce bu yanıt `{"text": ..., "cached": False}` idi: metin
    üretilmiş, hiçbir yere yazılmamış ve çağıran bunu bilemiyordu."""
    monkeypatch.setattr(cache, "set", lambda *a, **kw: False)
    sonuc = report_service._cached_generate("ag-2", "prompt", "yedek")
    assert sonuc["persisted"] is False
    # Metin YİNE dönüyor: kullanıcı yazım hatasının bedelini ödemiyor.
    assert sonuc["text"] == "uretilen metin"


def test_yedege_dusen_uretim_persisted_False(dosya_arka_ucu, monkeypatch):
    """Yedek metin önbelleğe HİÇ yazılmaz; bayrak bunu da doğru söylemeli."""
    monkeypatch.setattr(report_service.gemini_service, "generate",
                        lambda *a, **kw: "")
    sonuc = report_service._cached_generate("ag-3", "prompt", "yedek metin")
    assert sonuc["fallback"] is True
    assert sonuc["persisted"] is False
    assert sonuc["text"] == "yedek metin"


def test_onbellek_isabetinde_persisted_IDDIA_EDILMEZ(dosya_arka_ucu, uretim):
    """İsabette anahtar BULUNMAZ — ölçülmeyen söylenmez.

    `cache.get` önce belleğe bakıyor, yani isabetin hangi katmandan geldiği
    ölçülmedi. `persisted: True` yazmak uydurma, `False` yazmak iftira
    olurdu; doğrusu susmaktır. Isıtma ucu zaten `cached` dalını ayrı sayıyor.
    """
    cache.set("ag-4", "hazir metin", ttl_seconds=60)
    sonuc = report_service._cached_generate("ag-4", "prompt", "yedek")
    assert sonuc["cached"] is True
    assert "persisted" not in sonuc


# ---------------------------------------------------------------------------
# Zincirin kopmadığı yer: ısıtmanın okuduğu anahtar GERÇEKTEN üretiliyor
# ---------------------------------------------------------------------------

def test_horoscope_reading_persisted_anahtarini_uretir(dosya_arka_ucu, uretim,
                                                       monkeypatch):
    """`test_horoscope_warm.py` sahte bir `horoscope_reading` kullanıyor.

    Sahte `persisted` taşıyor; GERÇEĞİ taşımasa o testler kendi uydurdukları
    bir sözleşmeyi sınardı — bu depoda "yeşil kalan bekçi yanlış güven
    üretir" dersi tam olarak böyle alındı. Bağ burada çivileniyor.
    """
    monkeypatch.setattr(report_service, "retrieve_context",
                        lambda *a, **kw: "")
    sonuc = report_service.horoscope_reading(
        "leo", "daily", {"retrogrades": [], "aspects": [],
                         "moon_phase": None}, lang="tr")
    assert sonuc["cached"] is False
    assert sonuc["persisted"] is True

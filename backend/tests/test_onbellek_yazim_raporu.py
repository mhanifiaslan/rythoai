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

⚠️ Tüketiciler HENÜZ geçmedi: `api/maintenance.py` (ısıtma sayacı) ve
`services/report_service.py` (`cached` dalı) başka paketlerin dosyası, bu
turda onlara dokunulmadı. Yani katman bilgisi ÜRETİLİYOR ama sayaç adları
hâlâ mütevazı; raporda ayrıca yazılı.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_onbellek_yazim_raporu.py -q
"""
from __future__ import annotations

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

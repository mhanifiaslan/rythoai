"""Günlük tazelik: gün bilgisi ANAHTARDA mı, PROMPT'ta mı, ikisinde de mi.

Bu dosya tek bir doktrini iki yönden tutuyor (bkz. `report_service._gun_kovasi`
üstündeki üç hâl):

* **Günlük yüzeyde** gün hem prompt'ta hem anahtarda olmalı. Biri düşerse
  hiçbir hata çıkmaz: anahtar düşerse metin donar ve dünün günü bugünmüş
  gibi servis edilir; prompt düşerse her gün aynı metnin yeni bir kopyası
  üretilir — yani jeton yanar, içerik değişmez.
* **Kimlik yüzeyinde** gün hiçbir yerde olmamalı (natal, solar return,
  progresyon, sinastri).

⚠️ **ÜÇ YÜZEY TARAF DEĞİŞTİRDİ** (sahip kararı, 2026-10-03). Firaset, BaZi ve
doğum kapısı kimlik yüzeyiydi; artık günlük. Karar aynen şuydu: *"gerçekten
günlük yap ama maliyetlerini ölçeceğiz sonra jeton miktarına karar
vereceğiz"* — yani bu dosyanın eski hâlindeki "günlüğe çekilirse
ücretlendirme kararı gerekir" uyarıları KARARA DÖNÜŞTÜ ve bekçiler ters
çevrildi. `wallet.TOKEN_COSTS` bu turda DEĞİŞMEDİ; ölçüm yapıldı, fiyatı
sahip belirleyecek.

İki yönü de tutmak şart, çünkü ikisi ayrı kusur:

1. Gün prompt'a girmezse "günlük" yüzey her gün aynı şeyi söyler.
2. Gün anahtara girmezse metin donar ve bayat bir "bugün" servis edilir.

⚠️ **"GÜNLÜK" ≠ "HER GÜN BAŞTAN"**: üç yüzeyin de gövdesi ÖLÇÜLEN ve
değişmeyen bir çekirdek (firasette cihazda hesaplanan oranlar, BaZi'de
doğumun dört sütunu, doğum kapısında sabit kapı + pasajı). O çekirdeğin
prompt'ta DURMAYA DEVAM ETTİĞİNİ ayrı bekçiler tutuyor — "sabit tabloyu
sil" diye okuyan bir sonraki tur ürünün ölçülmüş çekirdeğini atardı.

Ölçüm notları (2026-10-03, bu turda yeniden ölçüldü — devralınan ölçüm
yeniden ölçülür):

* firaset gün bloğu (transit satırı): 30 günde **30 ayrı değer**, hiçbir gün
  boş değil (Istanbul 1990 doğumu, 30 günlük efemeris taraması).
* BaZi gün sütunu (Liu Ri): 30 günde **30**; ay sütunu (Liu Yue): **2**.
* doğum kapısı: kapı+çizgi 30 günde **30** ayrı değer — her biri tam bir
  gün; kapı TEK BAŞINA 30 günlük pencerede **5-7** (bu dosyanın penceresi
  olan 2026-10-02 için **7**). Bu yüzden gün bloğuna çizgi de basılıyor;
  kapı tek başına basılsa yüzey günlük değil ~5,7 günlük olurdu.
  ⚠️ Taşıyıcı sayı pencerenin kapı sayısı DEĞİL, `GATE_SPAN`/günlük hız
  oranı (5,71 gün): pencere sayısı faza bağlı ve bir tur boyunca burada
  düz bir "6" yazılıydı — oysa bu dosyanın kendi penceresi 7 veriyor.
"""
from __future__ import annotations

import datetime as dt

import pytest

from services import prompts, report_service

#: Bekçilerin kullandığı iki ayrı gün. Aralık bilerek geniş (46 gün): gün
#: sütunu etiketi 60 günde bir aynıya dönüyor, komşu günler seçilse
#: "etiket döndü" iddiası sınır bir tesadüfe dayanırdı.
_GUN_A = dt.date(2026, 10, 2)
_GUN_B = dt.date(2026, 11, 17)


@pytest.fixture
def temiz_onbellek(tmp_path, monkeypatch):
    from core import cache, config
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    yield
    cache._memory.clear()


def _kur(monkeypatch) -> dict:
    """Prompt'u yakalar, ÜRETİM SAYISINI sayar, SORULAN ANAHTARI kaydeder.

    Sayı iddianın yarısı: "farklı gün farklı metin" ile "aynı gün ikinci
    kez bedava" aynı sayacın iki ayrı okuması.

    ``sorulan`` ayrı bir işaret: üretim sayısı anahtarın NE OLDUĞUNU
    söylemiyor, yalnız kaç kez kaçırıldığını. Anahtarın gün dönünce
    döndüğünü kanıtlamak için anahtarın kendisi gerekiyor (bkz.
    ``_iki_ayri_gunde``).
    """
    kutu: dict = {"n": 0, "ttl": [], "sorulan": [], "promptlar": []}

    def sahte_generate(prompt, **k):
        kutu["n"] += 1
        kutu["prompt"] = prompt
        kutu["promptlar"].append(prompt)
        return f"metin-{kutu['n']}"

    monkeypatch.setattr(report_service.gemini_service, "generate",
                        sahte_generate)
    monkeypatch.setattr(report_service, "retrieve_context",
                        lambda *a, **k: "")
    monkeypatch.setattr(report_service.memory_service, "memory_context",
                        lambda uid, max_chars=600: "")
    # Olgu bekçisi gerçek bir LLM turu daha isteyebiliyor; tazelik sınavının
    # konusu o değil.
    monkeypatch.setattr(report_service.fact_guard, "enforce",
                        lambda text, prompt, **k: (text, True))

    gercek_set = report_service.cache.set

    def sayan_set(key, value, ttl_seconds=24 * 3600, owner_uid=None):
        kutu["ttl"].append(ttl_seconds)
        return gercek_set(key, value, ttl_seconds=ttl_seconds,
                          owner_uid=owner_uid)

    monkeypatch.setattr(report_service.cache, "set", sayan_set)

    gercek_get = report_service.cache.get

    def sayan_get(key):
        kutu["sorulan"].append(key)
        return gercek_get(key)

    monkeypatch.setattr(report_service.cache, "get", sayan_get)
    return kutu


def _iki_ayri_gunde(monkeypatch, cagir) -> tuple[dict, list]:
    """Aynı girdiyi iki ayrı günde çağırır; sorulan anahtar kümelerini verir.

    Gün, çağrıya PARAMETREYLE veriliyor (modül saatini taklit etmekle değil):
    üç yüzeyin de imzasında ``today`` var ve gerçek yolun varsayılanını ayrı
    bir bekçi tutuyor (``*_gunu_KULLANICININ_yerel_gunu``). Önceki tur bu
    testleri `report_service.dt`yi değiştirerek kuruyordu ve o yol artık
    ÖLÇMEZ: gün sınırı `entitlements.user_local_date`ten geliyor, yani
    takvimi orada taklit etmeyen bir test üretim yolunun gününü hiç
    döndürmemiş olur.

    Anahtarlar KÜME olarak toplanıyor çünkü iki günün çağrı sayısı zorunlu
    olarak farklı: ilk gün önbellek kaçıyor (iki ayrı sorgu: yüzeyin kendi
    isabet kapısı + ``_cached_generate``), ikinci gün de kaçıyor ama küme
    bu farkı yutar, anahtarın kendisini yutmaz.
    """
    kutu = _kur(monkeypatch)
    sorulan: list[frozenset] = []
    for gun in (_GUN_A, _GUN_B):
        kutu["sorulan"].clear()
        cagir(gun)
        sorulan.append(frozenset(kutu["sorulan"]))
    return kutu, sorulan


def _gun_dondu(kutu: dict, sorulan: list, yuzey: str) -> None:
    """İki bağımsız işaret: üretim SAYISI ve sorulan ANAHTAR.

    Yalnız sayıya bakmak yetmez — anahtar aynı kalıp üretim bir şekilde iki
    kez koşsa (örn. yüzey hiç önbelleğe yazmasa) sayı yanıltırdı. Yalnız
    anahtara bakmak da yetmez: anahtar dönüp de üretim tek kalırsa metin
    dönmemiş olur.
    """
    assert sorulan[0] != sorulan[1], (
        f"{yuzey} anahtarı GÜN DÖNÜNCE DÖNMEDİ: prompt'a giren gün metne "
        f"gömülür ve önbellek ömrü boyunca 'bugün' diye servis edilir "
        f"(yasak hâl). Yüzey günlük olacaksa kova gün bloğundan türemeli.")
    assert kutu["n"] == 2, f"{yuzey}: gün döndü, metin dönmedi"


def _ayni_gun_bedava(kutu: dict, yuzey: str) -> None:
    """Aynı gün ikinci çağrı önbellekten gelmeli — maliyet kapısı."""
    assert kutu["n"] == 1, (
        f"{yuzey}: aynı girdi + aynı gün ikinci kez üretildi. Jeton yanar, "
        f"içerik değişmez — kovaya içerikten bağımsız bir şey (zaman "
        f"damgası, sayaç) girmiş olabilir.")


# ---------------------------------------------------------------------------
# Kova denkliği: anahtarın gün terimi PROMPT'a giren bloğun KENDİSİNDEN türer
# ---------------------------------------------------------------------------

def test_gun_kovasi_blogun_KENDISINDEN_turuyor():
    """Aynı blok → aynı kova, farklı blok → farklı kova; boş blok sabit.

    Bu, üç yüzeyin ortak güvencesi: anahtarın gün terimi prompt'a giren
    dizenin özeti olduğu için "prompt'ta var ama anahtarda yok" hâli
    YAPISAL olarak oluşamaz. Önceki tur aynı denkliği her yüzeyde elle
    kuruyordu; elle kurulan bir denklik dördüncü yüzeyde unutulur.
    """
    kova = report_service._gun_kovasi
    assert kova("A") == kova("A")
    assert kova("A") != kova("B")
    # Boş blok (günün olgusu yok) SABİT kova verir: olgu yokken anahtar
    # her gün dönmemeli, yoksa içeriği aynı olan metin için jeton yanar.
    assert kova("") == kova(None) == kova("")


def test_gun_blogu_OLGU_yoksa_BOS_doner():
    """`gunun_gokyuzu` damgayı TEK BAŞINA basmaz.

    Blok aynı zamanda önbellek kovası: yalnız tarih basılsa kova her gün
    dönerdi ve içeriği gün gün AYNI olan bir metin için günde 5 jeton
    yakılırdı. Üç hâl soruluyor — olgu hiç yok, olgular boş, transit var —
    çünkü ilk ikisi boş, üçüncüsü dolu dönmeli ve yalnız yokluk iddialarına
    bakmak fonksiyon her zaman "" dönse de geçerdi.
    """
    from services import chart_context
    assert chart_context.gunun_gokyuzu(None, "tr", _GUN_A) == ""
    assert chart_context.gunun_gokyuzu(
        {"elements": {"fire": 1}, "transits": [], "upcoming": []},
        "tr", _GUN_A) == ""

    dolu = chart_context.gunun_gokyuzu(
        {"transits": [{"transit": "Saturn", "natal": "Venus",
                       "aspect": "conjunction", "orb": 0.4}],
         "upcoming": []}, "tr", _GUN_A)
    assert _GUN_A.isoformat() in dolu, "olgu varken tarih damgası basılmadı"
    assert prompts.get("tr").CHART_TRANSITS_LABEL in dolu


# ---------------------------------------------------------------------------
# YAKLAŞAN KESİNLEŞMELER: MUTLAK TARİH taşıyan satırın iki yönü
# ---------------------------------------------------------------------------
#
# Bu iki bekçi ölçümle eklendi (doğrulama turu, 2026-10-03). Katmanın HİÇBİR
# yönü korunmuyordu ve kök neden tekti: hiçbir test `upcoming`i DOLU
# geçirmiyordu — üç çağrı yerinin üçünde de `[]`. Minimal mutasyonla ölçülen
# üç kör hâl:
#
#   * `render`da yaklaşan satırı `include_transits` bayrağından KOPARILDI →
#     303 test yeşil kaldı. Oysa kalıcı sayılan bir bloğa giren MUTLAK TARİH
#     ("2026-10-07: Satürn → Venüs") o bloğu tüketen metnin ömrü boyunca
#     dondurulur; önceki tur tam bu kusuru onarmıştı.
#   * `gunun_gokyuzu`da yaklaşan satırı HİÇ BASILMAZ yapıldı → yeşil. Oysa
#     o fonksiyonun tarih damgasını ZORUNLU kılan gerekçesi birebir bu
#     satır; basılmazsa gerekçe yanlışa döner ve gün bloğu iki ölçülmüş
#     olgusundan birini kaybeder.
#   * `gunun_gokyuzu`nun boşluk kapısı `not vurus and not yaklasan`dan
#     `not vurus`a indirildi → yeşil. Oysa transiti olmayıp yaklaşanı olan
#     kullanıcı (dar orb, ama bu hafta kesinleşen bir açı) gün bloğunu
#     tümden kaybeder: yüzey onun için sessizce günlük olmaktan çıkar.
#
# Çapa tek bir Türkçe kelimeye bağlı değil: iki etiket `prompts`tan okunuyor
# (iki dilde ayrı metinler) ve üçüncü bağımsız işaret satırın taşıdığı ISO
# TARİHİN kendisi — dilden tümüyle bağımsız.

#: Yaklaşan kesinleşme olgusu. Tarih bilerek gün bloğunun gününden FARKLI:
#: "mutlak tarih sızdı mı" iddiası, damganın kendi tarihiyle karışmasın.
_YAKLASAN = [{"date": "2026-10-07", "transit": "Saturn", "natal": "Venus",
              "aspect": "conjunction"}]
_VURUS = [{"transit": "Mars", "natal": "Sun", "aspect": "square",
           "orb": 0.4}]


def test_kalici_blok_MUTLAK_TARIH_tasimaz():
    """`include_transits=False` yaklaşan satırını da DÜŞÜRÜR.

    Bayrak iki satırı birden bölüyor ve ikisi AYNI sınıftan: biri bugünün
    gökyüzünü, öteki bu haftanın takvimini taşıyor. Kalıcı blok, onu tüketen
    metnin ömrü boyunca dondurulacağı için ikisinden de arınmalı.

    Üç bağımsız işaret: iki etiket (`prompts`tan, dile göre değişir) ve
    yaklaşan satırının MUTLAK TARİHİ. Varlık yönü de soruluyor —
    `include_transits=True` ikisini de BASMALI; yoksa `render`ı tümden
    boşaltan bir mutasyon da bu bekçiyi geçerdi.
    """
    from services import chart_context
    olgular = {"elements": {"fire": 1, "earth": 2, "air": 1, "water": 0},
               "transits": list(_VURUS), "upcoming": list(_YAKLASAN)}

    for lang in ("tr", "en"):
        p = prompts.get(lang)
        acik = chart_context.render(olgular, lang, include_transits=True)
        assert p.CHART_TRANSITS_LABEL in acik, f"{lang}: transit satırı yok"
        assert p.CHART_UPCOMING_LABEL in acik, f"{lang}: yaklaşan satırı yok"
        assert _YAKLASAN[0]["date"] in acik, f"{lang}: mutlak tarih yok"

        kapali = chart_context.render(olgular, lang, include_transits=False)
        assert kapali, f"{lang}: kalıcı blok tümden boşaldı"
        assert p.CHART_TRANSITS_LABEL not in kapali
        assert p.CHART_UPCOMING_LABEL not in kapali, (
            f"{lang}: yaklaşan satırı kalıcı blokta kaldı — bayrak o satırı "
            f"kesmiyor")
        assert _YAKLASAN[0]["date"] not in kapali, (
            f"{lang}: kalıcı blok MUTLAK TARİH taşıyor; o tarih metnin ömrü "
            f"boyunca dondurulur (bayat gün iddiası)")


def test_gun_blogu_YAKLASANI_TEK_BASINA_da_basar():
    """Gün bloğu yaklaşan satırını BASAR ve yaklaşan TEK BAŞINA yeter.

    İki ayrı kusuru birden tutuyor, ikisi de ölçülerek bulundu:

    1. Satır hiç basılmazsa `gunun_gokyuzu`nun tarih damgasını ZORUNLU
       kılan gerekçe ("yaklaşan satırları mutlak tarih taşıyor, model
       bugünü bilmeden onu 'yarın' diye okur") yanlışa döner.
    2. Boşluk kapısı yalnız transite bakarsa, transiti olmayıp yaklaşanı
       olan kullanıcıda blok BOŞ döner — kova sabitlenir ve yüzey o
       kullanıcı için sessizce günlük olmaktan çıkar.

    Damga ayrıca soruluyor: bloğun kendi tarihi ile yaklaşanın tarihi
    FARKLI günler, yani "tarih var" iddiası ikisini karıştırmıyor.
    """
    from services import chart_context
    for lang in ("tr", "en"):
        p = prompts.get(lang)
        yalniz = chart_context.gunun_gokyuzu(
            {"transits": [], "upcoming": list(_YAKLASAN)}, lang, _GUN_A)
        assert yalniz, (
            f"{lang}: yaklaşanı olan kullanıcıda gün bloğu BOŞ döndü — "
            f"boşluk kapısı yalnız transite bakıyor")
        assert p.CHART_UPCOMING_LABEL in yalniz,             f"{lang}: yaklaşan satırı gün bloğunda basılmıyor"
        assert _YAKLASAN[0]["date"] in yalniz,             f"{lang}: yaklaşanın MUTLAK TARİHİ gün bloğunda yok"
        assert _GUN_A.isoformat() in yalniz,             f"{lang}: bugünün damgası yok — yaklaşanın tarihi okunamaz"
        assert _GUN_A.isoformat() != _YAKLASAN[0]["date"]


# ---------------------------------------------------------------------------
# Firaset — günlük yüzey
# ---------------------------------------------------------------------------

_ORANLAR = {"upperThird": 0.26, "middleThird": 0.37, "lowerThird": 0.37,
            "widthToHeight": 0.78, "jawToCheek": 0.88}


def _kimlik_blogu(imza: str, lang: str = "tr") -> str:
    """`chart_context.render(include_transits=False)` biçiminde KALICI blok.

    Etiketler prompts'tan OKUNUYOR, elle yazılmıyor: biçimin tek doğruluk
    kaynağı orada ve iki kopya iki ayrı dilde ayrışırdı.
    """
    p = prompts.get(lang)
    return f"- {p.CHART_ELEMENT_LABEL}: {imza}"


def _gun_blogu(gun: dt.date, imza: str, lang: str = "tr") -> str:
    """`chart_context.gunun_gokyuzu` biçiminde GÜN bloğu.

    İmler (sentinel) eşleşmeyi tek bir Türkçe kelimeye bağlamamak için var:
    kimlik imi de gün imi de prompt'ta GÖRÜNMELİ ve birbirine karışmadan
    ayırt edilebilmeli.
    """
    p = prompts.get(lang)
    return "\n".join([
        f"- {p.CHART_TODAY_LABEL}: {gun.isoformat()}",
        f"- {p.CHART_TRANSITS_LABEL}: {imza}",
    ])


def test_firaset_promptu_GUN_BLOGUNU_tasir(monkeypatch, temiz_onbellek):
    """Prompt'ta hem KALICI harita hem BUGÜNE ait blok var.

    Dört bağımsız işaret: iki im (kimlik + gün), tarih damgası ve gün
    bloğunun kendi etiketi. Varlık işaretleri şart — bir önceki tur bu
    satırları prompt'tan AYIKLIYORDU ve ayıklama yokluk iddialarıyla
    sınanıyordu; yokluk iddiaları tek başına, blok tümden boşaltıldığında
    da geçerdi.
    """
    kutu = _kur(monkeypatch)
    p = prompts.get("tr")
    report_service.firasa_report(
        "u-gt-1", _ORANLAR, chart=_kimlik_blogu("KIMLIK-IMI"),
        sky=_gun_blogu(_GUN_A, "GUN-IMI"), lang="tr")
    prompt = kutu["prompt"]

    assert "KIMLIK-IMI" in prompt, "kalıcı harita prompt'tan düştü"
    assert "GUN-IMI" in prompt, "gün bloğunun içeriği prompt'ta değil"
    assert _GUN_A.isoformat() in prompt, "prompt'ta bugünün TARİHİ yok"
    assert p.CHART_TRANSITS_LABEL in prompt, "transit etiketi prompt'ta değil"


def test_firaset_ingilizce_blokta_da_gun_tasir(monkeypatch, temiz_onbellek):
    """Gün bloğu isteğin dilinde taşınır — tek dile çivili değil."""
    kutu = _kur(monkeypatch)
    p = prompts.get("en")
    report_service.firasa_report(
        "u-gt-en", _ORANLAR, chart=_kimlik_blogu("KIMLIK-IMI", "en"),
        sky=_gun_blogu(_GUN_A, "GUN-IMI", "en"), lang="en")
    prompt = kutu["prompt"]

    assert "KIMLIK-IMI" in prompt
    assert "GUN-IMI" in prompt
    assert p.CHART_TODAY_LABEL in prompt


def test_firaset_ANAHTARI_gun_donunce_DONER(monkeypatch, temiz_onbellek):
    """Aynı yüz + aynı kimlik haritası + FARKLI gün → iki ayrı üretim.

    Eski bekçi bunun TERSİNİ tutuyordu ve gerekçesi maliyetti (5 jeton/gün).
    Aritmetik yanlış değildi; yanlış olan, ürünün çekirdek vaadinin maliyet
    gerekçesiyle sessizce kapatılmasıydı.
    """
    kimlik = _kimlik_blogu("AYNI-KIMLIK")
    kutu, sorulan = _iki_ayri_gunde(
        monkeypatch,
        lambda gun: report_service.firasa_report(
            "u-gt-2", _ORANLAR, chart=kimlik,
            sky=_gun_blogu(gun, f"GOKYUZU-{gun.isoformat()}"), lang="tr"))
    _gun_dondu(kutu, sorulan, "firaset")


def test_firaset_ayni_gun_ikinci_kez_BEDAVA(monkeypatch, temiz_onbellek):
    """Aynı gün + aynı girdi → tek üretim. Günlük olmak her açılışta
    üretmek değil; ekranı gün içinde üç kez açan 15 jeton ödemez."""
    kutu = _kur(monkeypatch)
    for _ in range(3):
        report_service.firasa_report(
            "u-gt-3", _ORANLAR, chart=_kimlik_blogu("AYNI-KIMLIK"),
            sky=_gun_blogu(_GUN_A, "AYNI-GOKYUZU"), lang="tr")
    _ayni_gun_bedava(kutu, "firaset")


def test_firaset_gun_OLGUSU_yoksa_anahtar_donmez(monkeypatch,
                                                 temiz_onbellek):
    """Gün bloğu BOŞ (doğum verisi yok / efemeris düştü) → anahtar sabit.

    Yüzeyin günlüklüğü TAKVİMDEN değil OLGUDAN geliyor. Anahtara doğrudan
    bir takvim günü konsa, bugüne dair ölçülmüş hiçbir şeyi olmayan
    kullanıcı her gün aynı metnin yeni bir kopyasını ödeyerek alırdı —
    prompt'ta değişen tek şey tarih satırı olurdu ve şablon o hâlde
    "bugün" demeyi zaten yasaklıyor.
    """
    kutu = _kur(monkeypatch)
    for _ in (_GUN_A, _GUN_B):
        report_service.firasa_report(
            "u-gt-4", _ORANLAR, chart=_kimlik_blogu("AYNI-KIMLIK"),
            sky="", lang="tr")
    assert kutu["n"] == 1, (
        "günün olgusu yokken anahtar döndü: kovaya içerikten bağımsız bir "
        "takvim günü girmiş olmalı")


def test_firaset_omru_BIR_GUN(monkeypatch, temiz_onbellek):
    """Ömür kovanın gerçek ömrüyle hizalı.

    7 gündü ve yüzey kimlik sayılırken doğruydu. Gün bloğu prompt'a
    girdiği an 7 günlük ömür, en kötü hâlde 6 gün bayat bir "bugün"
    iddiasını önbellekte tutmak demek olur.
    """
    kutu = _kur(monkeypatch)
    report_service.firasa_report(
        "u-gt-5", _ORANLAR, chart="", sky=_gun_blogu(_GUN_A, "G"),
        lang="tr")
    assert kutu["ttl"] == [24 * 3600]


def test_firaset_promptu_OLCULEN_BELIRTILERI_tasir(monkeypatch,
                                                   temiz_onbellek):
    """Gün bloğu eklenirken ÖLÇÜLEN çekirdek prompt'ta kaldı mı.

    Gün doktrininin karşı kutbu. "Ölçülmeyen söylenmez"in tersi de kural:
    ölçülen SÖYLENMELİ, ve bu yüzeyin tek dayanağı cihazda hesaplanmış
    oranların belirtiye çevrilmiş hâli. "Günlük yap" bir sonraki tur
    tarafından "sabit tabloyu sil" diye okunursa ürünün ölçülmüş çekirdeği
    gider ve geriye her gün değişen bir gökyüzü yorumu kalır — yani zaten
    var olan günlük okuma.

    Bekçi ölçümle eklendi (2026-10-02): `chart` tarafı üç bekçiyle çiviliydi
    ama aynı `format` çağrısının `signs` tarafı KORUMASIZDI — `signs` sabit
    bir tireye indirildiğinde firaset + rapor + rıza takımının 78 testi
    YEŞİL kaldı.

    Çapa tek bir Türkçe kelimeye bağlı değil: satırlar
    `firasa_service.prompt_block`un kendi çıktısından okunuyor, yani
    belirti sözlüğü ya da dili değişirse bekçi onunla değişir. Satır sayısı
    ayrıca soruluyor — boş blok yokluk iddiasını boşlukta geçirirdi.
    """
    kutu = _kur(monkeypatch)
    blok = report_service.firasa_service.prompt_block(_ORANLAR, "tr")
    satirlar = [s for s in blok.splitlines() if s.strip()]
    assert len(satirlar) >= 3, "ölçüm bloğu beklenmedik biçimde boş"

    report_service.firasa_report(
        "u-gt-6", _ORANLAR, chart="", sky=_gun_blogu(_GUN_A, "G"),
        lang="tr")
    for satir in satirlar:
        assert satir in kutu["prompt"], \
            f"ölçülen belirti prompt'a girmedi: {satir}"


def test_firaset_SABIT_belirti_tablosu_hala_kullaniliyor():
    """Belirtiler SABİT tablodan geliyor, güne göre üretilmiyor.

    Ayrı bir bekçi çünkü ayrı bir kusur: yukarıdaki test bloğun prompt'a
    girdiğini sınıyor, bu test bloğun KAYNAĞINI sınıyor. Belirti cümleleri
    güne göre seçilmeye başlanırsa (örn. "bugün Mars baskın, çeneyi öne
    çıkar") ölçülen oranlar güne göre oynatılmış olur — ölçülmüş bir
    çekirdeği uydurmaya çevirmek.
    """
    from services import firasa_service
    anahtarlar = firasa_service.descriptors(_ORANLAR)
    assert anahtarlar, "ölçülen oranlardan belirti çıkmadı"
    for lang in ("tr", "en"):
        tablo = prompts.get(lang).FIRASA_SIGNS
        blok = firasa_service.prompt_block(_ORANLAR, lang)
        for anahtar in anahtarlar:
            assert anahtar in tablo, f"{lang}: {anahtar} tabloda yok"
            assert tablo[anahtar] in blok, \
                f"{lang}: belirti cümlesi tablodan gelmiyor ({anahtar})"


def test_firaset_anahtari_KIMLIK_haritasini_da_KAPSAR(monkeypatch,
                                                      temiz_onbellek):
    """Aynı oranlar + aynı gün + FARKLI kimlik haritası → iki üretim.

    Gün terimi eklenirken kimlik terimi düşmemiş olmalı: doğum saatini
    düzelten kullanıcı, o gün boyunca ESKİ haritayla üretilmiş okumayı
    görmemeli.
    """
    kutu = _kur(monkeypatch)
    for imza in ("KIMLIK-A", "KIMLIK-B"):
        report_service.firasa_report(
            "u-gt-7", _ORANLAR, chart=_kimlik_blogu(imza),
            sky=_gun_blogu(_GUN_A, "AYNI-GUN"), lang="tr")
    assert kutu["n"] == 2, "harita değişti, okuma değişmedi"


def test_firaset_gecici_SIG_dusus_iyi_okumayi_YOK_ETMEZ(monkeypatch,
                                                        temiz_onbellek):
    """Derin blok → sığ özet → derin blok: üçüncü çağrı İLK metni verir.

    Anahtarın haritayı kapsaması bir bedel getirdi ve gerekçesi bir tur
    boyunca "bu kapsama bedava" diye yazılıydı; ölçüldüğünde yanlış çıktı.
    `chart_context.chart_whisper` efemeris hesabı düşerse
    `profile_service.chart_summary` sığ özetine iniyor ve o özet derin
    bloktan farklı bir dizedir — yani DOĞUM VERİSİ HİÇ DEĞİŞMEDEN anahtar
    bir kez döner ve kullanıcı 5 jeton daha öder.

    Bedelin SINIRLI olmasının tek sebebi anahtarın içerikten türemesi:
    derin blok geri geldiğinde eski anahtar da geri geliyor. Bu bekçi tam
    o sınırı tutuyor — anahtara içerikten bağımsız bir şey (zaman damgası,
    sayaç, sıralamasız bir özet) girerse düşüş iyi okumayı kalıcı olarak
    kaybettirir. İki işaret bir arada soruluyor: üretim SAYISI ve dönen
    METİN; yalnız sayıya bakmak önbelleğin hiç tutmadığı hâli de geçirirdi.

    Gün bloğu üç çağrıda da AYNI tutuluyor: ölçülen şey haritanın düşüşü,
    günün dönüşü değil.
    """
    from services import profile_service
    kutu = _kur(monkeypatch)
    gun = _gun_blogu(_GUN_A, "AYNI-GUN")
    derin = _kimlik_blogu("KIMLIK-IMI")
    sig = profile_service.chart_summary(
        {"sunSign": "Boğa", "moonSign": "Yay", "ascendant": "Kova"},
        lang="tr")
    assert sig and sig != derin, "sığ özet ölçülemedi"

    ilk = report_service.firasa_report("u-gt-8", _ORANLAR, chart=derin,
                                       sky=gun, lang="tr")
    report_service.firasa_report("u-gt-8", _ORANLAR, chart=sig, sky=gun,
                                 lang="tr")
    assert kutu["n"] == 2, "sığ düşüş ayrı bir anahtar üretmedi"

    geri = report_service.firasa_report("u-gt-8", _ORANLAR, chart=derin,
                                        sky=gun, lang="tr")
    assert kutu["n"] == 2, "derin blok geri geldi, okuma yeniden üretildi"
    assert geri["cached"] is True
    assert geri["text"] == ilk["text"], "iyi okuma kayboldu"


# ---------------------------------------------------------------------------
# I Ching — günlük yüzey (DOĞRU çalışıyordu ve KORUMASIZDI)
# ---------------------------------------------------------------------------

_SUTUN_A = {"label": "甲子 (Jia Zi)", "cycle": 0}
_SUTUN_B = {"label": "乙丑 (Yi Chou)", "cycle": 1}
_AY = {"label": "己未 (Ji Wei)"}


def _cekim(monkeypatch, gun: dict):
    """Gün bağlamı DIŞINDA her şeyi sabit bir çekim.

    Çizgiler beslenerek sabitleniyor: rastgele atış kalsaydı iki çağrı
    arasındaki farkın gün sütunundan mı yoksa yeni bir çekimden mi geldiği
    ayırt edilemezdi.
    """
    from services import iching_service
    beslenen = iter([7, 7, 9, 8, 8, 8])
    monkeypatch.setattr(iching_service, "_cast_line_coins",
                        lambda: next(beslenen))
    cekim = iching_service.cast_iching("işim ne olacak", method="coins")
    return iching_service.enrich_cast(
        cekim, day_pillar=gun, month_pillar=_AY,
        day_master_element="wood", basis="utc")


def test_iching_gun_sutunu_PROMPTTA(monkeypatch, temiz_onbellek):
    """Çekim günü bağlamı prompt'ta — üç bağımsız işaretle.

    Tek bir Türkçe kelimeye (ya da tek bir diyakritiğe) bağlanmıyor: iki
    sütun etiketi dilden bağımsız (CN + pinyin), üçüncü işaret satırın
    kendi biçimi.
    """
    kutu = _kur(monkeypatch)
    p = prompts.get("tr")
    report_service.iching_reading("u-gt-i1", _cekim(monkeypatch, _SUTUN_A),
                                  lang="tr")
    prompt = kutu["prompt"]

    assert _SUTUN_A["label"] in prompt, "gün sütunu prompt'ta değil"
    assert _AY["label"] in prompt, "ay sütunu prompt'ta değil"
    assert p.ICHING_DAY_FMT.format(
        day=_SUTUN_A["label"], month=_AY["label"],
        basis=p.ICHING_BASIS_UTC) in prompt


def test_iching_gun_sutunu_ANAHTARDA(monkeypatch, temiz_onbellek):
    """Aynı çekim + FARKLI gün → iki ayrı üretim; aynı gün ikinci kez bedava.

    İki iddia bir arada ölçülüyor çünkü ayrı ayrı yanıltıcı: yalnız "iki
    üretim" bakılsa anahtarın her çağrıda değiştiği (yani önbelleğin hiç
    tutmadığı) hâl de geçerdi.
    """
    kutu = _kur(monkeypatch)
    report_service.iching_reading("u-gt-i2", _cekim(monkeypatch, _SUTUN_A),
                                  lang="tr")
    report_service.iching_reading("u-gt-i2", _cekim(monkeypatch, _SUTUN_A),
                                  lang="tr")
    assert kutu["n"] == 1, "aynı gün aynı çekim yeniden üretildi"

    report_service.iching_reading("u-gt-i2", _cekim(monkeypatch, _SUTUN_B),
                                  lang="tr")
    assert kutu["n"] == 2, "gün döndü, yorum dönmedi (bayat gün iddiası)"


def test_iching_omru_gunu_asmaz(monkeypatch, temiz_onbellek):
    """Prompt'ta gün bağlamı olan bir metin, o günden uzun yaşamamalı."""
    kutu = _kur(monkeypatch)
    report_service.iching_reading("u-gt-i3", _cekim(monkeypatch, _SUTUN_A),
                                  lang="tr")
    assert kutu["ttl"], "önbelleğe hiç yazılmadı"
    assert max(kutu["ttl"]) <= 24 * 3600


def test_iching_HAREKETLI_CIZGILER_anahtarda(monkeypatch, temiz_onbellek):
    """Aynı gün, aynı soru, aynı HEKSAGRAM, farklı HAREKETLİ ÇİZGİ → iki yorum.

    I Ching'in günlüklüğü iki ayağa basıyor: gün sütunu VE çekimin kendisi.
    İkinci ayak korumasızdı.

    ⚠️ Bu bekçinin ilk hâli KÖR ÇIKTI (mutasyonla ölçüldü: anahtardan
    `moving_lines` terimi silindiğinde 31 testin hepsi yeşil kaldı). Sebep:
    iki çekim farklı HEKSAGRAM veriyordu ve heksagram numarası da anahtarda
    — yani fark başka bir terimden geliyordu, ölçülen terimden değil.

    Düzeltilmiş çapa: 7 ile 9 ikisi de yang, 8 ile 6 ikisi de yin
    (`iching_service.cast_iching`). Yani [9,7,8,8,8,8] ve [7,9,8,8,8,8]
    AYNI heksagramı verir, yalnız hareketli çizgi 1 ile 2 arasında değişir.
    Hareketli çizgiler yorumun ağırlık merkezi: aynı heksagramın 1. ve 2.
    çizgisi bambaşka iki okumadır.
    """
    kutu = _kur(monkeypatch)
    from services import iching_service
    numaralar = set()
    for cizgiler in ([9, 7, 8, 8, 8, 8], [7, 9, 8, 8, 8, 8]):
        beslenen = iter(cizgiler)
        monkeypatch.setattr(iching_service, "_cast_line_coins",
                            lambda: next(beslenen))
        cekim = iching_service.cast_iching("aynı soru", method="coins")
        numaralar.add(cekim["primary"]["number"])
        report_service.iching_reading(
            "u-gt-i4",
            iching_service.enrich_cast(cekim, day_pillar=_SUTUN_A,
                                       month_pillar=_AY, basis="utc"),
            lang="tr")
    assert len(numaralar) == 1, (
        "iki çekim farklı heksagram verdi: ölçülen terim hareketli çizgi "
        "değil heksagram numarası olur ve bekçi körleşir")
    assert kutu["n"] == 2, "hareketli çizgi değişti, yorum değişmedi"


# ---------------------------------------------------------------------------
# BaZi — günlük yüzey (Liu Ri + Liu Yue)
# ---------------------------------------------------------------------------

def _bazi_cark():
    from services import bazi_service
    return bazi_service.get_bazi_chart(
        1990, 5, 12, 14, 30, city="Istanbul", gender="female")


def test_bazi_promptu_BUGUNUN_SUTUNLARINI_tasir(monkeypatch,
                                                temiz_onbellek):
    """Prompt'ta Liu Ri + Liu Yue + tarih damgası var.

    Üç bağımsız işaret ve hiçbiri Türkçe bir kelimeye bağlı değil: iki
    sütun etiketi CN + pinyin, üçüncüsü ISO tarih. Gün satırının kendisi
    de `bazi_gun_blogu`dan okunuyor, elle yazılmıyor — biçim değişirse
    bekçi onunla değişir.
    """
    from services import bazi_service
    kutu = _kur(monkeypatch)
    report_service.bazi_report("u-gt-b1", _bazi_cark(), lang="tr",
                               today=_GUN_A)
    prompt = kutu["prompt"]

    assert bazi_service.day_pillar_for_date(_GUN_A)["label"] in prompt, \
        "bugünün GÜN SÜTUNU (Liu Ri) prompt'ta değil"
    assert bazi_service.month_pillar_for_date(_GUN_A)["label"] in prompt, \
        "bugünün AY SÜTUNU (Liu Yue) prompt'ta değil"
    assert _GUN_A.isoformat() in prompt, "prompt'ta bugünün TARİHİ yok"
    assert report_service.bazi_gun_blogu("tr", _GUN_A) in prompt, \
        "gün bloğu prompt'a olduğu gibi girmedi"


def test_bazi_promptu_SABIT_dort_sutunu_korur(monkeypatch, temiz_onbellek):
    """Gün katmanı eklenirken DOĞUMUN dört sütunu prompt'ta kaldı mı.

    Ölçülmüş çekirdek bekçisi. Gün sütunu eklemek, doğum sütunlarının
    yerini almak DEĞİL: raporun gövdesi hâlâ doğumdan türüyor ve günlük
    olan yalnız kesişim bölümü. Dört sütun düşse prompt "bugün şu sütun"
    diyen içi boş bir metne dönerdi.
    """
    kutu = _kur(monkeypatch)
    cark = _bazi_cark()
    report_service.bazi_report("u-gt-b2", cark, lang="tr", today=_GUN_A)
    prompt = kutu["prompt"]

    etiketler = [(cark["pillars"][k] or {}).get("label")
                 for k in ("year", "month", "day", "hour")]
    etiketler = [e for e in etiketler if e]
    assert len(etiketler) == 4, "doğum çarkı beklenmedik biçimde eksik"
    for etiket in etiketler:
        assert etiket in prompt, f"doğum sütunu prompt'tan düştü: {etiket}"


def test_bazi_gun_sutunu_GERCEKTEN_gunluk():
    """Liu Ri 30 günde 30 ayrı etiket — ödenen jetonun karşılığı.

    Bekçi ölçümle eklendi (doğrulama turu, 2026-10-03) ve kapı+çizgi
    bekçisinin (`test_kapi_gunluk_degil_CIZGI_gunluk`) BaZi karşılığı;
    o yüzey çivilenmişken bu yüzey çivisizdi.

    Neden gerekli: `BAZI_TODAY_FMT` tarih damgasını KOŞULSUZ basıyor, yani
    kova bu yüzeyde TAKVİMDEN dönüyor ve kullanıcı ekranı her gün açarsa
    her gün 5 jeton harcanıyor. O harcamayı meşru kılan tek şey basılan
    olgunun gerçekten her gün değişmesi. Gün sütunu 60 günlük bir çevrim;
    aritmetiği kayıp etiket haftalık/aylık dönmeye başlarsa bu yüzey "her
    gün para, aynı metin" hâline geçer ve hiçbir şey kırmızıya düşmezdi.

    Ay sütunu ayrıca soruluyor: o BAĞLAM olarak basılıyor, günlüklüğü
    taşıyan terim DEĞİL — 30 günde yalnız bir Jie sınırı geçiyor.
    """
    from services import bazi_service

    gunler, aylar = set(), set()
    for i in range(30):
        g = _GUN_A + dt.timedelta(days=i)
        gunler.add(bazi_service.day_pillar_for_date(g)["label"])
        aylar.add(bazi_service.month_pillar_for_date(g)["label"])

    assert len(gunler) == 30, (
        f"Liu Ri 30 günde {len(gunler)} ayrı etiket aldı: bu yüzeyin günlük "
        f"ücretlendirilmesinin dayanağı 30/30 ölçümü")
    assert len(aylar) <= 3, (
        f"Liu Yue 30 günde {len(aylar)} ayrı etiket: ay sütunu bağlam diye "
        f"basılıyor, günlük terim olduğu iddia edilmiyor")
    # Gün sütunu etiketi 60 günlük çevrim — `bazi_gun_blogu`nun tarih
    # damgasını ZORUNLU kılan gerekçe birebir bu sayı.
    etiket = bazi_service.day_pillar_for_date(_GUN_A)["label"]
    assert bazi_service.day_pillar_for_date(
        _GUN_A + dt.timedelta(days=60))["label"] == etiket
    assert bazi_service.day_pillar_for_date(
        _GUN_A + dt.timedelta(days=30))["label"] != etiket


def test_bazi_ANAHTARI_gun_donunce_DONER(monkeypatch, temiz_onbellek):
    """Aynı çark, iki ayrı gün → iki ayrı üretim ve iki ayrı anahtar."""
    cark = _bazi_cark()
    kutu, sorulan = _iki_ayri_gunde(
        monkeypatch,
        lambda gun: report_service.bazi_report("u-gt-b3", cark, lang="tr",
                                               today=gun))
    _gun_dondu(kutu, sorulan, "BaZi")


def test_bazi_ayni_gun_ikinci_kez_BEDAVA(monkeypatch, temiz_onbellek):
    kutu = _kur(monkeypatch)
    cark = _bazi_cark()
    for _ in range(3):
        report_service.bazi_report("u-gt-b4", cark, lang="tr", today=_GUN_A)
    _ayni_gun_bedava(kutu, "BaZi")


def test_bazi_omru_BIR_GUN(monkeypatch, temiz_onbellek):
    """30 gündü; gün sütunu prompt'a girdiği an 29 gün bayat olabilir."""
    kutu = _kur(monkeypatch)
    report_service.bazi_report("u-gt-b5", _bazi_cark(), lang="tr",
                               today=_GUN_A)
    assert kutu["ttl"] == [24 * 3600]


def test_bazi_gunu_KULLANICININ_yerel_gunu(monkeypatch, temiz_onbellek):
    """``today`` verilmezse gün KULLANICININ yerel gününden gelir.

    Bekçi ayrı duruyor çünkü yukarıdaki testlerin hepsi günü parametreyle
    veriyor: varsayılan `dt.date.today()`ye (sunucunun UTC günü) kaysa
    hiçbiri kırmızıya düşmezdi. Ölçülmüş kusur: Türkiye'de kullanıcının
    günü 03:00'te dönüyor ve günlük okuma gece yarısından sonra dünkü
    metni gösteriyordu (D2). Günlük okumayla firaset/BaZi'nin "bugün"ü
    AYRIŞMAMALI.
    """
    kutu = _kur(monkeypatch)
    monkeypatch.setattr(report_service.entitlements, "user_local_date",
                        lambda uid: _GUN_B)
    report_service.bazi_report("u-gt-b6", _bazi_cark(), lang="tr")
    assert _GUN_B.isoformat() in kutu["prompt"], \
        "gün sunucunun takviminden alınmış olabilir"


# ---------------------------------------------------------------------------
# Doğum kapısı — günlük yüzey (Güneş'in bugünkü kapısı + çizgisi)
# ---------------------------------------------------------------------------

def _kapi_konumu():
    from services import birth_hexagram_service
    return birth_hexagram_service.birth_hexagram(
        year=1990, month=5, day=12, hour=14, minute=30, city="Istanbul")


def test_dogum_kapisi_promptu_BUGUNUN_KAPISINI_tasir(monkeypatch,
                                                      temiz_onbellek):
    """Prompt'ta Güneş'in bugünkü kapısı + çizgisi + tarih var."""
    kutu = _kur(monkeypatch)
    report_service.birth_hexagram_report("u-gt-h1", _kapi_konumu(),
                                         lang="tr", today=_GUN_A)
    prompt = kutu["prompt"]

    blok = report_service.gunun_kapisi("tr", _GUN_A)
    assert blok in prompt, "bugünün kapısı prompt'a olduğu gibi girmedi"
    assert _GUN_A.isoformat() in prompt, "prompt'ta bugünün TARİHİ yok"


def test_dogum_kapisi_promptu_SABIT_KAPIYI_ve_PASAJI_korur(monkeypatch,
                                                            temiz_onbellek):
    """Gün katmanı eklenirken DOĞUM kapısı ve 64'lük pasaj prompt'ta kaldı mı.

    Ölçülmüş çekirdek bekçisi. Bu yüzeyin kalıcı gövdesi doğum kapısı +
    `data/birth_gates.json`'daki pasaj; bugünün kapısı yalnız son bölüm.
    Pasaj düşse okuma 64 kapıdan birine özgü olmaktan çıkar.
    """
    kutu = _kur(monkeypatch)
    konum = _kapi_konumu()
    report_service.birth_hexagram_report("u-gt-h2", konum, lang="tr",
                                         today=_GUN_A)
    prompt = kutu["prompt"]

    pasaj = (konum.get("gate_passage") or {}).get("gate_tr")
    assert pasaj, "kapı pasajı ölçülemedi"
    assert pasaj in prompt, "DOĞUM kapısının pasajı prompt'tan düştü"
    assert str(konum["gate"]) in prompt, "doğum kapısı numarası prompt'ta yok"


def test_dogum_kapisi_ANAHTARI_gun_donunce_DONER(monkeypatch,
                                                  temiz_onbellek):
    """Aynı doğum konumu, iki ayrı gün → iki ayrı üretim ve anahtar."""
    konum = _kapi_konumu()
    kutu, sorulan = _iki_ayri_gunde(
        monkeypatch,
        lambda gun: report_service.birth_hexagram_report(
            "u-gt-h3", konum, lang="tr", today=gun))
    _gun_dondu(kutu, sorulan, "doğum kapısı")


def test_dogum_kapisi_ayni_gun_ikinci_kez_BEDAVA(monkeypatch,
                                                  temiz_onbellek):
    kutu = _kur(monkeypatch)
    konum = _kapi_konumu()
    for _ in range(3):
        report_service.birth_hexagram_report("u-gt-h4", konum, lang="tr",
                                             today=_GUN_A)
    _ayni_gun_bedava(kutu, "doğum kapısı")


def test_dogum_kapisi_omru_BIR_GUN(monkeypatch, temiz_onbellek):
    kutu = _kur(monkeypatch)
    report_service.birth_hexagram_report("u-gt-h5", _kapi_konumu(),
                                         lang="tr", today=_GUN_A)
    assert kutu["ttl"] == [24 * 3600]


def test_dogum_kapisi_gunu_KULLANICININ_yerel_gunu(monkeypatch,
                                                    temiz_onbellek):
    """``today`` verilmezse gün KULLANICININ yerel gününden gelir."""
    kutu = _kur(monkeypatch)
    monkeypatch.setattr(report_service.entitlements, "user_local_date",
                        lambda uid: _GUN_B)
    report_service.birth_hexagram_report("u-gt-h6", _kapi_konumu(),
                                         lang="tr")
    assert _GUN_B.isoformat() in kutu["prompt"]


def test_gunun_kapisi_GUN_ORTASINDAN_okunur():
    """Gün bloğu gün içinde SABİT: duvar saatine bağlı değil.

    Kritik, çünkü gün bloğu aynı zamanda önbellek kovası. "Şimdi"nin
    boylamı kullanılsa kapı/çizgi gün İÇİNDE sınır geçebilir, kova gün
    ortasında dönebilir ve aynı kullanıcı aynı gün iki üretim ödeyebilirdi.
    Çapa doğrudan hesaba bağlı: 12:00 UTC boylamından türeyen kapı+çizgi.
    """
    from services import bazi_service, birth_hexagram_service as bh
    ogle = dt.datetime(_GUN_A.year, _GUN_A.month, _GUN_A.day, 12, 0,
                       tzinfo=dt.timezone.utc)
    beklenen = bh.gate_for_longitude(bazi_service._sun_longitude(ogle))

    blok = report_service.gunun_kapisi("tr", _GUN_A)
    assert str(beklenen["gate"]) in blok
    assert str(beklenen["line"]) in blok
    # Aynı gün için iki çağrı birebir aynı dizeyi vermeli (kova kararlı).
    assert blok == report_service.gunun_kapisi("tr", _GUN_A)


def test_kapi_gunluk_degil_CIZGI_gunluk():
    """Gün bloğuna çizginin de basılması bir ÖLÇÜM kararı.

    Bu sayılar gerekçe olarak kullanıldı (bkz. `report_service.gunun_kapisi`)
    ve bu depoda yanlış gerekçe kusurdur: sabitler kayarsa gerekçe de
    yanlışa döner. Ölçüm 2026-10-03, 30 günlük tarama.
    """
    from services import bazi_service, birth_hexagram_service as bh

    kapilar, kapi_cizgi = set(), set()
    for i in range(30):
        gun = _GUN_A + dt.timedelta(days=i)
        ogle = dt.datetime(gun.year, gun.month, gun.day, 12, 0,
                           tzinfo=dt.timezone.utc)
        yer = bh.gate_for_longitude(bazi_service._sun_longitude(ogle))
        kapilar.add(yer["gate"])
        kapi_cizgi.add((yer["gate"], yer["line"]))

    assert len(kapi_cizgi) == 30, (
        "kapı+çizgi 30 günde 30 ayrı değer almıyor: bu yüzeyin günlüklüğü "
        "bu ölçüme dayanıyor")
    assert len(kapilar) <= 7, (
        "kapı tek başına günlük görünüyor: gerekçe 'kapı ~5,7 gün sürer' "
        "diyor ve bir kapı günlük dönüyorsa çark matematiği değişmiş")

    # ÇİZGİ gerçekten BASILIYOR mu: aynı kapıda kalan iki KOMŞU günün
    # blokları, TARİH DAMGASI çıkarıldıktan sonra da farklı olmalı.
    #
    # ⚠️ Bu bekçinin ilk iki hâli KÖR ÇIKTI (mutasyonla ölçüldü: biçimden
    # `{line}` silindiğinde 31 test yeşil kaldı). Birinci hâl `str(line)`ı
    # blokta arıyordu ve çizgi numarası TARİHİN içinde de geçiyor
    # ("2026-10-02" içinde "1" var). İkinci hâl iki komşu günün bloklarını
    # karşılaştırıyordu ama bloklar TARİH yüzünden zaten farklıydı — yani
    # damga, ölçülmek isteneni maskeliyordu. Üçüncü hâl damgayı çıkarıyor:
    # geriye yalnız kapı + çizgi kalıyor ve kapı ikisinde de aynı.
    def _kapi(g):
        ogle = dt.datetime(g.year, g.month, g.day, 12, 0,
                           tzinfo=dt.timezone.utc)
        return bh.gate_for_longitude(
            bazi_service._sun_longitude(ogle))["gate"]

    # ⚠️ Çapa İKİ DİLDE de koşuyor ve bu da ölçümle geldi (doğrulama turu):
    # biçim sabiti dil başına ayrı tanımlı (`BIRTH_HEXAGRAM_TODAY_FMT` hem
    # `prompts/tr` hem `prompts/en` içinde) ve bu bekçinin ilk hâli yalnız
    # "tr" soruyordu. Minimal mutasyonla ölçüldü: `{line}` YALNIZ en.py'den
    # silindiğinde 303 test yeşil kaldı — yani İngilizce kullanıcının doğum
    # kapısı yüzeyi sessizce 5,7 günlüğe döner, Türkçesi günlük kalır.
    # Parite bekçisi (`test_i18n`) bunu yakalamaz: sabit İKİ dilde de VAR,
    # yalnız içeriği ayrışıyor.
    def _damgasiz(lang, g):
        return report_service.gunun_kapisi(lang, g).replace(
            g.isoformat(), "")

    komsu = None
    for i in range(29):
        g1 = _GUN_A + dt.timedelta(days=i)
        g2 = g1 + dt.timedelta(days=1)
        if _kapi(g1) == _kapi(g2):
            komsu = (g1, g2)
            break
    assert komsu, "aynı kapıda kalan komşu iki gün bulunamadı"
    for lang in ("tr", "en"):
        assert _damgasiz(lang, komsu[0]) != _damgasiz(lang, komsu[1]), (
            f"{lang}: aynı kapıdaki iki komşu günün blokları yalnız TARİHTE "
            f"farklı, yani çizgi basılmıyor. Kova ZATEN her gün dönüyor "
            f"(damga koşulsuz basılıyor, ölçüldü), dolayısıyla jeton her "
            f"gün harcanacak; çizgi düşerse model ~5,7 gün AYNI 'bugün' "
            f"bölümünü yazar — para gider, içerik değişmez")
    # Çark sabitleri: kapı ~5,7 gün, çizgi ~0,95 gün. Günlük kovanın
    # çizgiye ihtiyaç duymasının sebebi tam bu iki sayı.
    assert bh.GATE_SPAN == pytest.approx(5.625)
    gunluk_hiz = 360.0 / 365.2422
    assert 5.5 <= bh.GATE_SPAN / gunluk_hiz <= 5.8
    assert 0.9 <= bh.LINE_SPAN / gunluk_hiz <= 1.0


# ---------------------------------------------------------------------------
# Uçtan uca KABLOLAMA: gün bloğu gerçekten taşınıyor mu
# ---------------------------------------------------------------------------
#
# Bu bekçi ayrı duruyor çünkü yukarıdaki firaset testlerinin hepsi gün
# bloğunu KENDİSİ kuruyor. `api/face_reading` `sky=` geçmeyi bıraksa (ya da
# `include_transits=False` düşse) o testlerin hiçbiri kırmızıya düşmez:
# yüzey sessizce günlük olmaktan çıkar ve kimse görmez. Bu depoda kör
# bekçinin adı budur.

try:
    from main import app as _app
    _APP_HATASI = None
except Exception as exc:  # pragma: no cover - ortama bağlı
    _app = None
    _APP_HATASI = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_HATASI is not None,
    reason=f"FastAPI uygulaması içe aktarılamadı: {_APP_HATASI}")

#: Uç bekçisinin yaklaşan-kesinleşme tarihi. Gün bloğunun GÜNÜNDEN
#: (`_GUN_B`) bilerek farklı: "mutlak tarih hangi bloğa düştü" iddiası,
#: damganın kendi tarihiyle karışmasın.
_YAKLASAN_TARIHI = "2026-11-20"

_UC_ORANLAR = {"jawToCheek": 0.80, "mouthToFaceWidth": 0.41,
               "eyeSpacing": 0.45, "symmetry": 0.98,
               "upperThird": 0.33, "middleThird": 0.33, "lowerThird": 0.34,
               "widthToHeight": 0.70, "lipFullness": 0.05}


@uygulama_gerekir
def test_firaset_UCU_gun_blogunu_AYRI_tasir(monkeypatch):
    """Uç, kalıcı bloğu ve gün bloğunu AYRI argümanlarla geçiyor mu.

    Üç bağımsız işaret soruluyor:
      1. `chart` (kalıcı) günün satırlarını TAŞIMIYOR — `include_transits`
         gerçekten False geçiyor;
      2. `sky` (gün bloğu) BOŞ DEĞİL ve bugünün tarihini taşıyor;
      3. tarih KULLANICININ yerel günü — sunucunun UTC günü değil.
    """
    from fastapi.testclient import TestClient

    from api import face_reading
    from core import device, entitlements, wallet
    from core.auth import AuthUser, get_current_user

    yakalanan: dict = {}

    _app.dependency_overrides[get_current_user] = lambda: AuthUser(
        uid="u-kablo", email="a@b.c", admin=False, auth_time=1000)
    monkeypatch.setattr(entitlements, "FORCE_PLUS", False)
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: True)
    monkeypatch.setattr(entitlements, "user_local_date", lambda uid: _GUN_B)
    monkeypatch.setattr(device, "enforce_single_device", lambda *a, **k: None)
    monkeypatch.setattr(wallet, "spender", lambda uid, ozellik, **k: None)
    monkeypatch.setattr(wallet, "refund_spend", lambda uid, ozellik: True)
    monkeypatch.setattr(face_reading.consent_service, "has_face_consent",
                        lambda uid: True)
    monkeypatch.setattr(face_reading.profile_service, "get_profile",
                        lambda uid: {"birthDate": "1990-05-12",
                                     "birthCity": "Istanbul"})
    # Olgular sabitleniyor: ölçülen şey efemeris değil KABLOLAMA.
    #
    # ⚠️ `today` da YAKALANIYOR ve bu ölçülerek eklendi (doğrulama turu,
    # 2026-10-03). `chart_facts` günü verilmezse transit önbellek kovasını
    # `dt.date.today()` ile — yani SUNUCUNUN UTC günüyle — kuruyor; damga
    # ise kullanıcının yerel gününü basıyor. UTC+3'te ikisi her gün üç saat
    # AYRIŞIYOR (21:00–24:00 UTC = 00:00–03:00 yerel) ve o pencerede ekranı
    # açan kullanıcı, damgası BUGÜN ama olguları DÜNKÜ UTC gününün
    # kovasından gelen bir metin alıyordu (transit TTL'i 36 saat) — hem
    # bayat gün iddiası hem boşa giden bir jeton. Uç artık günü BİR KEZ
    # okuyup üçüne de veriyor; bekçi tam o denkliği tutuyor.
    #
    # `upcoming` da DOLU geçiliyor: mutlak takvim tarihi taşıyan tek satır
    # o ve hangi bloğa düştüğü ayrı bir iddia (aşağıda 5. işaret).
    def sahte_olgular(uid, profile, today=None):
        yakalanan["olgu_gunu"] = today
        return {"elements": {"fire": 1, "earth": 2, "air": 1, "water": 0},
                "transits": [{"transit": "Saturn", "natal": "Venus",
                              "aspect": "conjunction", "orb": 0.4}],
                "upcoming": [{"date": _YAKLASAN_TARIHI, "transit": "Mars",
                              "natal": "Sun", "aspect": "square"}]}

    monkeypatch.setattr(face_reading.chart_context, "chart_facts",
                        sahte_olgular)

    def sahte_firasa(uid, ratios, chart="", lang=None, spend=None,
                     refund=None, sky=""):
        yakalanan["chart"] = chart
        yakalanan["sky"] = sky
        return {"text": "okuma", "cached": False}

    monkeypatch.setattr(face_reading.report_service, "firasa_report",
                        sahte_firasa)

    try:
        with TestClient(_app) as client:
            yanit = client.post("/api/v1/face/reading", json=_UC_ORANLAR)
    finally:
        _app.dependency_overrides.clear()

    assert yanit.status_code == 200, yanit.text
    p = prompts.get("tr")
    assert yakalanan["chart"], "kalıcı harita bloğu uçtan hiç geçmedi"
    assert p.CHART_TRANSITS_LABEL not in yakalanan["chart"], \
        "kalıcı blok günün transitlerini taşıyor (include_transits=False?)"
    assert yakalanan["sky"], "GÜN BLOĞU uçtan hiç geçmedi: yüzey günlük değil"
    assert p.CHART_TRANSITS_LABEL in yakalanan["sky"]
    assert _GUN_B.isoformat() in yakalanan["sky"], \
        "gün bloğundaki tarih kullanıcının yerel günü değil"
    # 4. OLGULARIN önbellek kovası ile DAMGA aynı günü görüyor mu.
    assert yakalanan["olgu_gunu"] == _GUN_B, (
        f"olguların önbellek kovası {yakalanan['olgu_gunu']!r} "
        f"gününden, damga {_GUN_B!r} gününden: ikisi ayrışırsa damga "
        f"BUGÜNÜ söylerken olgular dünkü kovadan gelir — bayat gün "
        f"iddiası, üstelik damgayla dönen anahtar için jeton da ödenir")
    # 5. MUTLAK TAKVİM TARİHİ gün bloğunda, kalıcı blokta DEĞİL.
    assert _YAKLASAN_TARIHI in yakalanan["sky"], \
        "yaklaşan kesinleşme gün bloğuna girmedi"
    assert _YAKLASAN_TARIHI not in yakalanan["chart"], (
        "kalıcı blok MUTLAK TAKVİM TARİHİ taşıyor: o tarih, bloğu "
        "tüketen metnin ömrü boyunca dondurulur")

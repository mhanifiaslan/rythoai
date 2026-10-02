"""Günlük tazelik: gün bilgisi ANAHTARDA mı, PROMPT'ta mı, ikisinde de mi.

Bu dosya tek bir doktrini iki yönden tutuyor (bkz.
``report_service._kimlik_haritasi`` üstündeki üç hâl):

* **Günlük yüzeyde** gün hem prompt'ta hem anahtarda olmalı. Biri düşerse
  hiçbir hata çıkmaz: anahtar düşerse metin donar ve dünün günü bugünmüş
  gibi servis edilir; prompt düşerse her gün aynı metnin yeni bir kopyası
  üretilir — yani jeton yanar, içerik değişmez. I Ching bugün DOĞRU
  çalışıyor ve bu doğruluk korumasızdı; buradaki iki bekçi onu çiviliyor.
* **Kimlik yüzeyinde** gün hiçbir yerde olmamalı. BaZi ve doğum kapısı
  30 gün önbellekli ve 5 jetonluk yüzeyler: prompt'a tarih/gün sütunu
  girerse ya 30 gün boyunca donmuş bir "bugün" iddiası servis edilir ya da
  anahtar günlüğe çekilip aylık hakkın (100 jeton) 1,5 katı yakılır.
  Bekçi üçüncü hâli yasaklıyor; eklemek isteyen önce buraya uğrar.

Ölçüm notu (2026-10-02): firaset prompt'u gün satırı TAŞIYORDU
(``chart_whisper`` bloğundaki "Bugün haritasına dokunan transitler" ve
TARİHLİ "Önümüzdeki 7 günün kesinleşmeleri") ama anahtarı taşımıyordu ve
ömrü 7 gündü. 30 günlük efemeris taraması: transit satırının değeri 30
günün 30'unda da farklı — yani "günü anahtara da koy" onarımı firasete
günde 5 jeton bindirirdi. Onarım bu yüzden ters yönde: gün satırları
prompt'tan ayıklandı.
"""
from __future__ import annotations

import datetime as dt

import pytest

from services import prompts, report_service


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
    dönmediğini kanıtlamak için anahtarın kendisi gerekiyor (bkz.
    ``_iki_ayri_gunde``).
    """
    kutu: dict = {"n": 0, "ttl": [], "sorulan": []}

    def sahte_generate(prompt, **k):
        kutu["n"] += 1
        kutu["prompt"] = prompt
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


# ---------------------------------------------------------------------------
# Firaset — kimlik yüzeyi: gün satırı prompt'a GİRMEZ
# ---------------------------------------------------------------------------

_ORANLAR = {"upperThird": 0.26, "middleThird": 0.37, "lowerThird": 0.37,
            "widthToHeight": 0.78, "jawToCheek": 0.88}


def _harita_blogu(kimlik_imi: str, gun_imi: str, lang: str = "tr") -> str:
    """`chart_context.render` biçiminde bir blok kurar.

    Etiketler prompts'tan OKUNUYOR, elle yazılmıyor: biçimin tek doğruluk
    kaynağı orada ve iki kopya iki ayrı dilde ayrışırdı. İmler (sentinel)
    eşleşmeyi tek bir Türkçe kelimeye bağlamamak için var — bloğun kimlik
    kısmı prompt'ta GÖRÜNMELİ, gün kısmı GÖRÜNMEMELİ ve ikisi birbirine
    karışmadan ayırt edilebilmeli.
    """
    p = prompts.get(lang)
    return "\n".join([
        f"- {p.CHART_ELEMENT_LABEL}: {kimlik_imi}",
        f"- {p.CHART_TRANSITS_LABEL}: {gun_imi}",
        f"- {p.CHART_UPCOMING_LABEL}: 2026-10-07: {gun_imi}",
    ])


def test_firaset_promptu_gun_satiri_tasimaz(monkeypatch, temiz_onbellek):
    """Prompt'ta gün satırı YOK, kimlik satırı VAR.

    Dört bağımsız işaret soruluyor; üçü yokluk, biri varlık. Varlık işareti
    şart: ayıklama bloğu tümden boşaltsa da yokluk iddiaları geçerdi.
    """
    kutu = _kur(monkeypatch)
    p = prompts.get("tr")
    blok = _harita_blogu("KIMLIK-IMI", "GUN-IMI")

    report_service.firasa_report("u-gt-1", _ORANLAR, chart=blok, lang="tr")
    prompt = kutu["prompt"]

    assert "KIMLIK-IMI" in prompt, "kimlik satırı prompt'tan düştü"
    assert "GUN-IMI" not in prompt, "gün satırının içeriği prompt'ta"
    assert p.CHART_TRANSITS_LABEL not in prompt, "transit etiketi prompt'ta"
    assert p.CHART_UPCOMING_LABEL not in prompt, "yaklaşan etiketi prompt'ta"
    # Tarih en zararlı kısım: donmuş bir metinde takvim günü iddiası.
    assert "2026-10-07" not in prompt, "prompt'ta TARİH var"


def test_firaset_promptu_ingilizce_blokta_da_ayiklanir(monkeypatch,
                                                       temiz_onbellek):
    """Ayıklama isteğin dilindeki etiketle çalışır — tek dile çivili değil."""
    kutu = _kur(monkeypatch)
    p = prompts.get("en")
    blok = _harita_blogu("KIMLIK-IMI", "GUN-IMI", lang="en")

    report_service.firasa_report("u-gt-en", _ORANLAR, chart=blok, lang="en")
    prompt = kutu["prompt"]

    assert "KIMLIK-IMI" in prompt
    assert "GUN-IMI" not in prompt
    assert p.CHART_TRANSITS_LABEL not in prompt


def test_firaset_gun_satiri_jeton_YAKMAZ(monkeypatch, temiz_onbellek):
    """Aynı oranlar + aynı kimlik + FARKLI gün satırı → tek üretim.

    Maliyet bekçisi. Firaset 5 jetonluk bir yüzey ve gün satırı ölçüldüğü
    gibi her gün değişiyor; anahtar ham bloğu kapsasaydı kullanıcı aynı
    okuma için her gün 5 jeton öderdi.
    """
    kutu = _kur(monkeypatch)
    for gun in ("GUN-1", "GUN-2", "GUN-3"):
        report_service.firasa_report(
            "u-gt-2", _ORANLAR,
            chart=_harita_blogu("AYNI-KIMLIK", gun), lang="tr")
    assert kutu["n"] == 1, "gün satırı değişince yeniden üretildi"


def test_firaset_anahtari_kimlik_haritasini_KAPSAR(monkeypatch,
                                                   temiz_onbellek):
    """Aynı oranlar + FARKLI kimlik haritası → iki ayrı üretim.

    Eski anahtar yalnız oranların özetiydi: doğum saatini düzelten
    kullanıcı, bir hafta boyunca ESKİ haritayla üretilmiş okumayı
    görüyordu — ekranda taze hesaplanmış haritanın yanında.
    """
    kutu = _kur(monkeypatch)
    report_service.firasa_report(
        "u-gt-3", _ORANLAR,
        chart=_harita_blogu("KIMLIK-A", "GUN"), lang="tr")
    report_service.firasa_report(
        "u-gt-3", _ORANLAR,
        chart=_harita_blogu("KIMLIK-B", "GUN"), lang="tr")
    assert kutu["n"] == 2, "harita değişti, okuma değişmedi"


def test_firaset_omru_bir_hafta(monkeypatch, temiz_onbellek):
    """Ömür 7 gün: anahtar prompt'un tamamını kapsadığı için bayatlık
    kaygısı yok; TTL yalnız birikmeyi ve iyileştirme gecikmesini sınırlar."""
    kutu = _kur(monkeypatch)
    report_service.firasa_report("u-gt-4", _ORANLAR, chart="", lang="tr")
    assert kutu["ttl"] == [7 * 24 * 3600]


def test_firaset_promptu_OLCULEN_BELIRTILERI_tasir(monkeypatch,
                                                   temiz_onbellek):
    """Ayıklama gün satırını atarken ÖLÇÜLENİ de atmadı mı.

    Gün doktrininin karşı kutbu. "Ölçülmeyen söylenmez"in tersi de kural:
    ölçülen SÖYLENMELİ, ve bu yüzeyin tek dayanağı cihazda hesaplanmış
    oranların belirtiye çevrilmiş hâli.

    Bekçi ölçümle eklendi (2026-10-02): `chart` tarafı üç bekçiyle çiviliydi
    ama aynı `format` çağrısının `signs` tarafı KORUMASIZDI — `signs` sabit
    bir tireye indirildiğinde firaset + rapor + rıza takımının 78 testi
    YEŞİL kaldı. Yani prompt'tan ölçümün tamamı düşebilir ve hiçbir hata
    çıkmazdı; geriye yalnız haritadan konuşan bir metin kalırdı.

    Çapa tek bir Türkçe kelimeye bağlı değil: satırlar
    `firasa_service.prompt_block`un kendi çıktısından okunuyor, yani
    belirti sözlüğü ya da dili değişirse bekçi onunla değişir. Satır sayısı
    ayrıca soruluyor — boş blok yokluk iddiasını boşlukta geçirirdi.
    """
    kutu = _kur(monkeypatch)
    blok = report_service.firasa_service.prompt_block(_ORANLAR, "tr")
    satirlar = [s for s in blok.splitlines() if s.strip()]
    assert len(satirlar) >= 3, "ölçüm bloğu beklenmedik biçimde boş"

    report_service.firasa_report("u-gt-5", _ORANLAR, chart="", lang="tr")
    for satir in satirlar:
        assert satir in kutu["prompt"], \
            f"ölçülen belirti prompt'a girmedi: {satir}"


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
    kaybettirir ve her düşüş 5 jeton yakar. İki işaret bir arada soruluyor:
    üretim SAYISI ve dönen METİN; yalnız sayıya bakmak önbelleğin hiç
    tutmadığı hâli de geçirirdi.
    """
    from services import profile_service
    kutu = _kur(monkeypatch)
    derin = _harita_blogu("KIMLIK-IMI", "GUN-IMI")
    sig = profile_service.chart_summary(
        {"sunSign": "Boğa", "moonSign": "Yay", "ascendant": "Kova"},
        lang="tr")
    assert sig and sig != derin, "sığ özet ölçülemedi"

    ilk = report_service.firasa_report("u-gt-6", _ORANLAR, chart=derin,
                                       lang="tr")
    report_service.firasa_report("u-gt-6", _ORANLAR, chart=sig, lang="tr")
    assert kutu["n"] == 2, "sığ düşüş ayrı bir anahtar üretmedi"

    geri = report_service.firasa_report("u-gt-6", _ORANLAR, chart=derin,
                                        lang="tr")
    assert kutu["n"] == 2, "derin blok geri geldi, okuma yeniden üretildi"
    assert geri["cached"] is True
    assert geri["text"] == ilk["text"], "iyi okuma kayboldu"


# ---------------------------------------------------------------------------
# I Ching — günlük yüzey: gün hem prompt'ta hem anahtarda
# ---------------------------------------------------------------------------

_GUN_A = {"label": "甲子 (Jia Zi)", "cycle": 0}
_GUN_B = {"label": "乙丑 (Yi Chou)", "cycle": 1}
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
    report_service.iching_reading("u-gt-i1", _cekim(monkeypatch, _GUN_A),
                                  lang="tr")
    prompt = kutu["prompt"]

    assert _GUN_A["label"] in prompt, "gün sütunu prompt'ta değil"
    assert _AY["label"] in prompt, "ay sütunu prompt'ta değil"
    assert p.ICHING_DAY_FMT.format(
        day=_GUN_A["label"], month=_AY["label"],
        basis=p.ICHING_BASIS_UTC) in prompt


def test_iching_gun_sutunu_ANAHTARDA(monkeypatch, temiz_onbellek):
    """Aynı çekim + FARKLI gün → iki ayrı üretim; aynı gün ikinci kez bedava.

    İki iddia bir arada ölçülüyor çünkü ayrı ayrı yanıltıcı: yalnız "iki
    üretim" bakılsa anahtarın her çağrıda değiştiği (yani önbelleğin hiç
    tutmadığı) hâl de geçerdi.
    """
    kutu = _kur(monkeypatch)
    report_service.iching_reading("u-gt-i2", _cekim(monkeypatch, _GUN_A),
                                  lang="tr")
    report_service.iching_reading("u-gt-i2", _cekim(monkeypatch, _GUN_A),
                                  lang="tr")
    assert kutu["n"] == 1, "aynı gün aynı çekim yeniden üretildi"

    report_service.iching_reading("u-gt-i2", _cekim(monkeypatch, _GUN_B),
                                  lang="tr")
    assert kutu["n"] == 2, "gün döndü, yorum dönmedi (bayat gün iddiası)"


def test_iching_omru_gunu_asmaz(monkeypatch, temiz_onbellek):
    """Prompt'ta gün bağlamı olan bir metin, o günden uzun yaşamamalı."""
    kutu = _kur(monkeypatch)
    report_service.iching_reading("u-gt-i3", _cekim(monkeypatch, _GUN_A),
                                  lang="tr")
    assert kutu["ttl"], "önbelleğe hiç yazılmadı"
    assert max(kutu["ttl"]) <= 24 * 3600


# ---------------------------------------------------------------------------
# BaZi ve doğum kapısı — kimlik yüzeyi: gün HİÇBİR YERDE
# ---------------------------------------------------------------------------

def _bugunun_isaretleri() -> tuple[str, str]:
    """(ISO tarih, bugünün gün sütunu etiketi)."""
    from services import bazi_service
    gun = dt.date.today()
    return gun.isoformat(), bazi_service.day_pillar_for_date(gun)["label"]


def _gun_iddiasi_yok(prompt: str, chart_etiketleri: tuple[str, ...]) -> None:
    """Prompt'ta bugüne ait bir damga olmadığını üç işaretle sorar.

    Gün sütunu etiketi, haritanın KENDİ sütunlarından biriyle çakışabilir
    (60'lık döngü, dört sütun); çakışmada o işaret atlanır — yoksa bekçi
    yılda birkaç gün kendiliğinden kırmızıya düşerdi ve kimse nedenini
    aramazdı.
    """
    iso, gun_etiketi = _bugunun_isaretleri()
    assert iso not in prompt, "prompt'ta bugünün TARİHİ var"
    assert prompts.get("tr").CHART_TRANSITS_LABEL not in prompt, \
        "prompt'ta bugünün transit satırı var"
    if gun_etiketi not in chart_etiketleri:
        assert gun_etiketi not in prompt, (
            "prompt'ta bugünün GÜN SÜTUNU var: gün prompt'a giriyorsa "
            "önbellek anahtarına da girmeli (üç hâl) ve o anahtar her "
            "kaçırmada 5 jeton demek")


def test_bazi_kimlik_yuzeyi_kalir(monkeypatch, temiz_onbellek):
    """BaZi prompt'unda bugün YOK, ömrü 30 gün.

    Ölçüldü: prompt'taki en küçük dönem Liu Nian (yılın sütunu) ve o da
    anahtarda. Gün katmanı (Liu Ri / Liu Yue) EKSİK — ama eksikliği
    şablonda, burada değil; şablona yer açılmadan anahtara gün koymak
    aynı prompt'tan ikinci bir metin üretip 5 jeton yakardı.
    """
    from services import bazi_service
    kutu = _kur(monkeypatch)
    chart = bazi_service.get_bazi_chart(
        1990, 5, 12, 14, 30, city="Istanbul", gender="female")
    report_service.bazi_report("u-gt-b1", chart, lang="tr")

    etiketler = tuple((chart["pillars"][k] or {}).get("label", "")
                      for k in ("year", "month", "day", "hour"))
    _gun_iddiasi_yok(kutu["prompt"], etiketler)
    assert kutu["ttl"] == [30 * 24 * 3600]


def test_dogum_kapisi_kimlik_yuzeyi_kalir(monkeypatch, temiz_onbellek):
    """Doğum kapısı prompt'unda bugün YOK, ömrü 30 gün.

    Gün katmanı eklenecekse kovası takvim günü değil KAPI: Güneş bir
    kapıda 5,625° ≈ 5,7 gün kalıyor.
    """
    from services import birth_hexagram_service
    kutu = _kur(monkeypatch)
    konum = birth_hexagram_service.birth_hexagram(
        year=1990, month=5, day=12, hour=14, minute=30, city="Istanbul")
    report_service.birth_hexagram_report("u-gt-h1", konum, lang="tr")

    _gun_iddiasi_yok(kutu["prompt"], ())
    assert kutu["ttl"] == [30 * 24 * 3600]


# ---------------------------------------------------------------------------
# Kimlik yüzeyinin ANAHTARI gün dönünce DÖNMEZ — maliyet kapısı
# ---------------------------------------------------------------------------
#
# Bu üç bekçi MUTASYONLA eklendi (2026-10-02, doğrulama turu). Üç kimlik
# yüzeyinin anahtarına da bugünün tarihi tek satırla sokuldu
# (`firasa`/`bazi`/`birthhex` özetine `dt.date.today().isoformat()`) ve
# takımın TAMAMI — 111 test, bu dosyanın 11 bekçisi dahil — YEŞİL kaldı.
#
# Yani paketin en pahalı kararı korumasızdı: "bu yüzeyleri günlüğe çekmedim,
# çünkü her kaçırma 5 jeton ve aylık hak 100" (üç yüzey birden 450 jeton/ay).
# Var olan bekçiler gün bilgisinin PROMPT'a girmesini ve HARİTA bloğunun
# anahtarda nasıl özetlendiğini tutuyordu; anahtara DOĞRUDAN bir takvim
# günü girmesini hiçbiri görmüyordu.
#
# Ölçüm notu: tersi de doğru olmalı — I Ching'in anahtarı gün dönünce
# DÖNMELİ. Onu `test_iching_gun_sutunu_ANAHTARDA` tutuyor; o bekçi bu
# üçünün aynadaki yüzü ve ikisi birlikte doktrinin iki yönünü kapatıyor.


class _SabitTakvim:
    """``report_service.dt`` yerine geçen, günü çivilenmiş takvim.

    Modül adının TAMAMI değiştiriliyor, tek bir çağrı değil: "bugünü al"ın
    iki gerçekçi yazımı var (``dt.date.today`` ve ``dt.datetime.now``) ve
    yalnız birini sabitlemek öbürünü açıkta bırakırdı. Gerçek sınıflardan
    türetiliyor ki ``isinstance`` ve karşılaştırma yolları bozulmasın.
    """

    def __init__(self, gun: dt.date) -> None:
        self.timedelta = dt.timedelta
        self.timezone = dt.timezone

        class _Gun(dt.date):
            @classmethod
            def today(cls) -> dt.date:
                return gun

        class _An(dt.datetime):
            @classmethod
            def now(cls, tz=None) -> dt.datetime:
                return dt.datetime(gun.year, gun.month, gun.day, 12, 0,
                                   tzinfo=tz)

            @classmethod
            def utcnow(cls) -> dt.datetime:
                return dt.datetime(gun.year, gun.month, gun.day, 12, 0)

        self.date = _Gun
        self.datetime = _An


def _iki_ayri_gunde(monkeypatch, cagir) -> tuple[dict, list]:
    """Aynı girdiyi iki ayrı günde çağırır; sorulan anahtar kümelerini verir.

    Girdi (harita bloğu / BaZi çarkı / kapı konumu) çağrının DIŞINDA bir kez
    kuruluyor: motorlar kendi takvimlerini kullanıyor (örn. Liu Nian), ve
    girdiyi her gün yeniden hesaplamak ölçülen şeyi — ANAHTARIN kendi gün
    kullanımını — motorun gün kullanımıyla karıştırırdı.

    Anahtarlar KÜME olarak toplanıyor çünkü iki günün çağrı sayısı zorunlu
    olarak farklı: ilk gün önbellek kaçıyor (iki ayrı sorgu: yüzeyin kendi
    isabet kapısı + ``_cached_generate``), ikinci gün ilk sorguda isabet
    edip erken dönüyor. Küme bu farkı yutar, anahtarın kendisini yutmaz.
    """
    kutu = _kur(monkeypatch)
    sorulan: list[frozenset] = []
    for gun in (dt.date(2026, 10, 2), dt.date(2026, 11, 17)):
        monkeypatch.setattr(report_service, "dt", _SabitTakvim(gun))
        kutu["sorulan"].clear()
        cagir()
        sorulan.append(frozenset(kutu["sorulan"]))
    return kutu, sorulan


def _gun_donmedi(kutu: dict, sorulan: list, yuzey: str, jeton: int) -> None:
    """İki bağımsız işaret: üretim SAYISI ve sorulan ANAHTAR.

    Yalnız sayıya bakmak yetmez — anahtar dönüp de üretim bir şekilde tek
    kalsa (örn. yüzey hiç önbelleğe yazmasa) sayı yanıltırdı. Yalnız
    anahtara bakmak da yetmez: anahtar aynı kalıp üretim yine iki kez
    koşarsa jeton yine yanar.
    """
    assert sorulan[0] == sorulan[1], (
        f"{yuzey} anahtarı GÜN DÖNÜNCE DÖNDÜ: kimlik yüzeyi günlüğe "
        f"çekilmiş demektir ve her gün {jeton} jeton yakar (aylık hak 100). "
        f"Gün gerçekten metne girecekse önce prompt şablonuna girsin ve "
        f"ücretlendirme kararı verilsin — bkz. üç hâl doktrini.")
    assert kutu["n"] == 1, f"{yuzey}: aynı girdi iki kez üretildi"


def test_firaset_ANAHTARI_gun_donunce_donmez(monkeypatch, temiz_onbellek):
    """Firaset kimlik yüzeyi: aynı yüz + aynı harita, iki ayrı gün → bir üretim."""
    blok = _harita_blogu("AYNI-KIMLIK", "GUN-IMI")
    kutu, sorulan = _iki_ayri_gunde(
        monkeypatch,
        lambda: report_service.firasa_report("u-gt-k1", _ORANLAR,
                                             chart=blok, lang="tr"))
    _gun_donmedi(kutu, sorulan, "firaset", 5)


def test_bazi_ANAHTARI_gun_donunce_donmez(monkeypatch, temiz_onbellek):
    """BaZi kimlik yüzeyi: aynı çark, iki ayrı gün → bir üretim.

    Gün KATMANI eklenirse (Liu Ri / Liu Yue) bu bekçi kırmızıya düşer ve
    düşmesi DOĞRUDUR: o an verilmesi gereken karar ücretlendirmedir.
    """
    from services import bazi_service
    chart = bazi_service.get_bazi_chart(
        1990, 5, 12, 14, 30, city="Istanbul", gender="female")
    kutu, sorulan = _iki_ayri_gunde(
        monkeypatch,
        lambda: report_service.bazi_report("u-gt-k2", chart, lang="tr"))
    _gun_donmedi(kutu, sorulan, "BaZi", 5)


def test_dogum_kapisi_ANAHTARI_gun_donunce_donmez(monkeypatch,
                                                   temiz_onbellek):
    """Doğum kapısı kimlik yüzeyi: aynı konum, iki ayrı gün → bir üretim."""
    from services import birth_hexagram_service
    konum = birth_hexagram_service.birth_hexagram(
        year=1990, month=5, day=12, hour=14, minute=30, city="Istanbul")
    kutu, sorulan = _iki_ayri_gunde(
        monkeypatch,
        lambda: report_service.birth_hexagram_report("u-gt-k3", konum,
                                                     lang="tr"))
    _gun_donmedi(kutu, sorulan, "doğum kapısı", 5)


def test_kapi_omru_kapi_suresinden_kisa_degil():
    """5,7 günlük kapı, 30 günlük ömrün içinde kalıyor mu — sayı sabiti.

    Bu sayı raporda gerekçe olarak kullanıldı; sabit değişirse gerekçe de
    yanlışa döner (bu depoda yanlış gerekçe kusurdur).
    """
    from services import birth_hexagram_service as bh
    assert bh.GATE_SPAN == pytest.approx(5.625)
    gun = bh.GATE_SPAN / (360.0 / 365.2422)
    assert 5.5 <= gun <= 5.8

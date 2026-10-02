"""Kullanıcı hafızası — sohbetten damıtılan kalıcı, şemalı olgular.

Uygulamanın "kullanıcıyı tanıması" natal veriden değil, zamanla biriken bu
katmandan gelir. Bu yüzden **ham sohbet metni saklanmaz**; yalnızca sınırlı bir
kategori kümesine oturan, kısa ve güncellenebilir olgular tutulur. Böylece hem
gizlilik yüzeyi küçük kalır hem de prompt'a enjekte edilecek bağlam öngörülebilir
boyutta olur.

Şema (Firestore: ``users/{uid}/private/memory`` tek doküman):

```
{
  "version": 1,
  "facts": [
    {"category": "work", "key": "work.transition",
     "value": "yeni bir işe geçme ihtimalini tartıyor",
     "confidence": 0.8, "updatedAt": <ts>}
  ],
  "moodTrail": [{"date": "2026-07-28", "mood": "kaygılı", "note": "..."}],
  "toneHint": "kısa ve doğrudan yanıt tercih ediyor",
  "updatedAt": <ts>
}
```

Bu modülde yalnızca **şema ve okuma/yazma API'si** vardır. Olguların sohbetten
çıkarılması Faz 4'te `prompt_composer` ile birlikte eklenecek.

Firestore erişilemezse tüm okumalar boş hafıza döner ve yazmalar sessizce
yok sayılır — hafıza katmanı hiçbir koşulda isteği düşürmez.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import logging
from typing import Any

from core import firestore as firestore_client

logger = logging.getLogger(__name__)

SCHEMA_VERSION = 1

#: Olguların oturabileceği kategoriler. Serbest kategori kabul edilmez —
#: çıkarım katmanı bu listeye uymak zorundadır.
#:
#: Sağlık bilinçli olarak yoktur: sağlık/hastalık yorumu ürünün yasak
#: alanlarındandır, dolayısıyla o veriyi saklamak da istemiyoruz.
CATEGORIES = (
    "relationship",   # ilişki durumu ve tekrar eden ilişki temaları
    "work",           # iş / kariyer bağlamı
    "family",         # aile bağlamı
    "goal",           # kullanıcının dile getirdiği hedefler
    "concern",        # tekrar eden kaygılar
    "preference",     # ton, uzunluk, hitap tercihleri
    "milestone",      # kullanıcının önemsediği tarihler
    # S-turu: kullanıcının konuşulmasını İSTEMEDİĞİ konu. "Bunu konuşmak
    # istemiyorum" bir kez söylenir ve kalıcı olmalı; her açılışta aynı
    # yaraya dokunmak "seni tanıyorum" değil, tam tersi.
    "sensitivity",
)

#: Sınırlar — hem Firestore doküman boyutu hem prompt bütçesi için.
MAX_FACTS = 40
MAX_FACT_CHARS = 240
MAX_MOOD_ENTRIES = 30
MAX_TONE_CHARS = 200

#: Kategori -> fısıltı ömrü (gün); ``None`` = ömürsüz.
#:
#: TEK KAYNAK: fısıltıya girme kapısı, sıralamadaki çürüme hızı ve budama
#: sırası — üçü de bu tablodan okur. Tek tablo olması bir TASARIM kararı
#: (ölçülmüş bir kaza değil): aynı eşiği üç yerde tutmak, birini
#: güncelleyip diğerini unutmaya açık bırakırdı.
#:
#: NEDEN kategoriye göre: ölçülen kusur şuydu — bir kez söylenen bir sıkıntı
#: ("sevgilimle kavga ettim") çıkarıcıda 0.9 güven alıyor (bkz.
#: `memory_extractor._PROMPT`: "açıkça söylediyse 0.9"), sıralama yalnız
#: güvene baktığı için fısıltının başını kapıyor ve HİÇ DÜŞMÜYORDU. Oysa
#: olguların hepsi aynı hızda eskimez:
#:
#: - ``concern`` 30 gün: kaygı bir DURUMDUR, kayıt değil. Bir ay boyunca
#:   bir daha anılmadıysa geçmiştir. Anılıyorsa her çıkarımda ``updatedAt``
#:   tazelenir ve kendiliğinden yaşamaya devam eder — yani "hâlâ konuşuyor"
#:   ile "bir kez söyledi" arasındaki farkı ölçen şey bu tablodur.
#: - ``relationship``/``work``/``family`` 180 gün: hayat bağlamı yavaş
#:   değişir ama DEĞİŞİR; altı ay önceki iş durumu bugünkü cevabın dayanağı
#:   olamaz.
#: - ``goal`` 365 gün: hedef bir niyettir; bir yıl boyunca hiç anılmayan
#:   niyeti "hâlâ istiyor" saymak uydurmadır.
#: - ``preference``/``milestone`` ömürsüz: ton tercihi ve kullanıcının
#:   önemsediği tarih zamanla yanlışlanmaz.
#: - ``sensitivity`` ömürsüz ve bu KASITLIDIR: "bunu konuşmak istemiyorum"
#:   bir YASAKTIR, bilgi değil. Ömür vermek, yasağın sessizce kalkıp aynı
#:   yaraya yeniden dokunulması olurdu.
FACT_LIFESPAN_DAYS: dict[str, int | None] = {
    "concern": 30,
    "relationship": 180,
    "work": 180,
    "family": 180,
    "goal": 365,
    "preference": None,
    "milestone": None,
    "sensitivity": None,
}

#: Ömürsüz kategorilerin sıralamadaki yarılanma süresi. Ömürsüz olmak "hiç
#: eskimez" demek DEĞİL: beş yıl önceki bir ``milestone``, dün söylenen bir
#: tercihin önüne geçmemeli. Yalnız SIRALAMAYI etkiler, hiçbir şeyi düşürmez.
KALICI_YARILANMA_GUN = 365

#: Fısıltıya girebilecek en çok olgu sayısı. ``MAX_FACTS`` (40) DEPOLAMA
#: sınırıdır; fısıltı bütçesini olgular ruh hali seyri, günlük ve ton
#: tercihiyle PAYLAŞIR ve KA9'daki "sığmayanı atla" onarımı kısa parçaları
#: kurtarıyor ama onlara yer AYIRMIYOR.
#:
#: Dilim bir ÜST SINIR, tek başına çözüm DEĞİL — ilk hâlindeki yorum
#: paylaşımı çözülmüş gibi yazıyordu, ölçüm öyle demiyordu (40 taze olgu,
#: ~40 karakterlik değerler): `max_chars=600`'de dilimsiz hâlde olgular
#: bütçenin tamamını yiyor, dilimle ruh hali seyri geri geliyor ama günlük
#: ve ton tercihi YİNE düşüyor; `report_service`'in kullandığı
#: `max_chars=400`'de dilimle bile 7 olgu bütçeyi bitiriyor ve geriye
#: hiçbir şey kalmıyor. Yani dilim en kötü hâli 40'tan 8'e indiriyordu.
#:
#: Bütçe AYIRMA artık yapıldı (`_FISILTI_PAYLARI`), yani bu dilim bugün
#: olguların PAYI içindeki satır sayısını sınırlıyor; aç bırakma kapısı
#: orada. Dilim yine de duruyor: payı büyük bir bütçede (ör. 4000) pay
#: tek başına olguları sınırlamaz ve fısıltı 40 satıra çıkabilirdi.
MAX_WHISPER_FACTS = 8

#: Fısıltı bütçesinin BİLEŞEN PAYLARI — her bileşenin GARANTİ tabanı.
#:
#: NEDEN pay gerekti (ölçüldü 2026-10-03, 40 taze olgu / 5 ruh hali / 6
#: günlük / ton ipucu): paysız hâlde `max_chars=400`'de fısıltıya **7
#: olgu ve BAŞKA HİÇBİR ŞEY** giriyordu — ruh hali seyri, günlük ve ton
#: tercihi 0 satır. `max_chars=600`'de yalnız ruh hali seyri kurtuluyordu
#: (8 olgu + 1 seyir, günlük 0, ton 0). Yani bileşenler birbirini
#: AÇLIKTAN öldürüyordu ve en ısrarlı olgu bütçenin başını yiyordu — K6
#: onarımının (sığmayanı atla) kesmeyi amaçladığı şey tam buydu, ama
#: "atla" kısa parçaları KURTARIYOR, onlara yer AYIRMIYORdu.
#:
#: Sayılar ölçülen DOĞAL orandan geliyor (bileşenlerin bütçe sınırı
#: olmadan ürettiği karakter payı: olgu %40, ruh hali %17, günlük %38,
#: ton %5) — yani pay, bileşenin gerçekten ürettiği hacme oranlı; eşit
#: dörde bölmek günlüğü ve olguları aynı kefeye koyup ikisini de keserdi.
#: Günlük %38 → %35 ve ton %5 → %8 kaydırıldı: tek satırlık ton ipucu
#: (ölçülen 52 karakter) %5 payla `max_chars=400`'de (20 karakter) HİÇ
#: sığmazdı, günlük ise altı satırlı olduğu için üç puanı kayıpsız verir.
#:
#: ⚠️ PAYIN TAM ANLAMI (yoksa bu sayılar yanlış okunur): pay ne saf taban
#: ne saf tavandır. `_paylara_bol`un ORANSAL turunda TAVAN gibi davranır
#: (bileşen payını aşan satır almaz), garanti turunda ise payına
#: BAKILMAZ, artan turunda da pay yoktur. Yani bileşenin gerçek aldığı
#: oran paydan sapabilir.
#:
#: Ölçülen sonuç (aynı sahte hafıza, onarımdan sonra) — bu sapmanın
#: büyüklüğü de görünsün diye yazıldı:
#:   `max_chars=400` → 2 olgu · 1 ruh hali seyri · 2 günlük · 1 ton
#:   `max_chars=600` → 4 olgu · 1 ruh hali seyri · 3 günlük · 1 ton
#:   `max_chars=900` → 7 olgu · 1 seyir · 1 "aradığı" · 4 günlük · 1 ton
#: 400'de olguların aldığı yer %27'dir, payı olan %40 değil: garanti turu
#: dört bileşenin İLK satırına 255 karakter harcıyor ve 400'lük bütçede
#: geri kalan oransal tura 145 karakter kalıyor. Bu, payın ihlali DEĞİL
#: bedeli — "her bileşen en az bir satır" kuralının ücreti olgulardan
#: ödeniyor ve onarımın amacı tam olarak buydu (önce 7 olgu + SIFIR
#: başka bileşen vardı).
_FISILTI_PAYLARI = {
    "olgu": 0.40,
    "ruh_hali": 0.17,
    "gunluk": 0.35,
    "ton": 0.08,
}

#: Olguların bağlanabileceği HAYAT ALANLARI (konu). Kategoriden ayrıdır:
#: kategori olgunun TÜRÜDÜR ("bu bir kaygı"), konu NEYLE ilgili olduğudur
#: ("ilişkisiyle"). Çelişki tespiti konu üzerinden çalışmak zorunda:
#: "ayrıldık" (``relationship.status``) ile "sevgilisiyle sorun yaşıyor"
#: (``concern.relationship``) aynı hayat alanını paylaşır ama kategorileri
#: de anahtarları da farklıdır — yani ``key`` birleştirmesi bu ikisini
#: ASLA karşılaştıramaz.
KONULAR = ("relationship", "work", "family")

#: Konu çelişkisinde DÜŞEN kategoriler. Yalnız ``concern``: kaygı o alandaki
#: ANLIK durumdur ve aynı alanda iki kaygı birlikte güncel olamaz.
#: ``work.transition`` ile ``work.employer`` ise iki ayrı KAYITtır, birlikte
#: yaşamaları gerekir — kural bu yüzden kategoriye bağlı, konuya değil.
CELISKIDE_DUSEN = ("concern",)

#: Sıralamada önceliği olan kategoriler. ``sensitivity`` bilgi değil
#: YASAKTIR: bütçe kırpması onu düşürürse model yasaklı konuyu açar. Bu,
#: eski bir kaygının kalmasının TAM TERSİ yönde ama aynı ağırlıkta bir
#: kusurdur, o yüzden bütçe yarışına girmiyor.
_SIRA_ONCELIGI = {"sensitivity": 1}

#: Günlük (R2-G1) sınırları. Girdiler KULLANICININ kendi cümleleridir
#: ("bugün patronumla tartıştım") — tek satır, tarih damgalı, temalı.
#: Analizin "astrolojik günlük" fikri: kullanıcı yaşadığını yazar, sohbet
#: "son bir ayda ne oldu?" sorusunu bu kayıtlar + gökyüzüyle cevaplar.
MAX_DIARY_ENTRIES = 90
MAX_DIARY_CHARS = 200

#: Günlük girişinin bağlanabileceği temalar — sinyal temalarıyla AYNI küme
#: (signal_service.THEMES); tema vermeden de yazılabilir.
DIARY_THEMES = ("career", "relationships", "inner", "finance")

_EMPTY: dict[str, Any] = {
    "version": SCHEMA_VERSION,
    "facts": [],
    "moodTrail": [],
    "toneHint": None,
    "diary": [],
}


def _doc(uid: str):
    """Kullanıcının hafıza dokümanı; Firestore yoksa ``None``.

    ``private`` alt koleksiyonu altında tutulur: istemcinin bu veriye doğrudan
    erişmesi gerekmiyor, yalnızca sunucu (Admin SDK) okur/yazar.
    """
    client = firestore_client.get_client()
    if client is None:
        return None
    return client.collection("users").document(uid).collection("private").document("memory")


def get_memory(uid: str) -> dict[str, Any]:
    """Kullanıcının hafızasını döndürür; yoksa boş şema."""
    doc_ref = _doc(uid)
    if doc_ref is None:
        return dict(_EMPTY)
    try:
        snapshot = doc_ref.get()
    except Exception as exc:
        logger.warning("Hafıza okunamadı (%s): %s", uid, exc)
        return dict(_EMPTY)

    if not snapshot.exists:
        return dict(_EMPTY)

    data = snapshot.to_dict() or {}
    return {
        "version": data.get("version", SCHEMA_VERSION),
        "facts": data.get("facts", []),
        "moodTrail": data.get("moodTrail", []),
        "toneHint": data.get("toneHint"),
        "diary": data.get("diary", []),
    }


def _simdi(simdi: dt.datetime | None = None) -> dt.datetime:
    """Şimdiki an; testler için enjekte edilebilir.

    Zaman ağırlığı eklendiği an "şu an" bir GİRDİ oldu: ömrü geçmiş bir
    olgunun fısıltıdan düştüğünü ölçmenin tek yolu, 40 gün beklemek yerine
    saati dışarıdan vermek.
    """
    return simdi or dt.datetime.now(dt.timezone.utc)


def _yas_gun(fact: dict[str, Any], simdi: dt.datetime) -> float | None:
    """Olgunun kaç günlük olduğu; tarih bilinmiyorsa ``None``.

    ``None`` "çok eski" DEĞİL "bilmiyoruz" demektir ve her yerde öyle
    davranılır: ne ömrü geçer, ne fısıltıya tarih yazılır. Ölçülmeyen
    söylenmez — tarihi olmayan bir olguya "altı ay önce" dedirtmek
    uydurma olurdu. Bu yoldan şema öncesi kayıtlar ve elle kurulmuş test
    fikstürleri geçer; ``_normalize_fact`` yazdığı her olguya tarih koyar.
    """
    ts = fact.get("updatedAt")
    if ts is None:
        return None
    try:
        if ts.tzinfo is None:
            # Yazma yolunun tamamı `_simdi()` üzerinden geçiyor, yani
            # tz-aware; naive bir damga ancak elle kurulmuş bir kayıttan
            # gelir ve UTC varsayılır.
            #
            # ⚠️ Bu satırın gerekçesi bir kez YANLIŞ yazıldı ("except
            # hafızayı TÜMDEN susturur, kapı 'hiç olgu yok' moduna
            # düşerdi") ve ölçüldüğünde tam TERSİ çıktı: aşağıdaki
            # `except` yalnız O OLGU için `None` döner, yani olgu
            # "yaşı bilinmiyor" sayılır. `_omru_gecti` bilinmeyen yaşı
            # ASLA geçmiş saymaz ve `memory_context` ona tarih yazmaz —
            # sonuç susmak değil ÖLÜMSÜZLÜK: 400 günlük bir `concern`
            # fısıltıda tarihsiz ve sonsuza dek kalır, yani paketin
            # onardığı zehirlenmenin aynısı geri döner. Varsayımın işi
            # bu yolu kapatmak. Ölçüm: naive 2026-09-01 damgası
            # varsayımla 31.0 gün + ömrü geçmiş, varsayım olmadan
            # `None` + ömrü GEÇMEMİŞ.
            ts = ts.replace(tzinfo=dt.timezone.utc)
        return max((simdi - ts).total_seconds() / 86400.0, 0.0)
    except (AttributeError, TypeError):
        return None


def _omru_gecti(fact: dict[str, Any], simdi: dt.datetime) -> bool:
    """Olgu fısıltıdan düşmeli mi? (kategorisinin ömrüne göre)"""
    omur = FACT_LIFESPAN_DAYS.get(str(fact.get("category", "")))
    if omur is None:
        return False
    yas = _yas_gun(fact, simdi)
    return yas is not None and yas > omur


def _tazelik(fact: dict[str, Any], simdi: dt.datetime) -> float:
    """Yaşa göre 1.0'dan 0'a inen çarpan (yarılanmalı çürüme).

    Yarılanma süresi kategorinin ömrünün YARISIDIR: ömrünün sonuna gelen
    olgunun ağırlığı dörde bölünmüş olur, yani düşmeden önce zaten sıranın
    arkasına geçer. Keskin eşik yerine çürüme, çünkü "29 gün taptaze,
    31 gün yok" sıçraması kullanıcıya tutarsızlık gibi hissedilirdi.
    """
    yas = _yas_gun(fact, simdi)
    if yas is None:
        return 1.0
    omur = FACT_LIFESPAN_DAYS.get(str(fact.get("category", "")))
    yarilanma = KALICI_YARILANMA_GUN if omur is None else max(omur / 2.0, 1.0)
    return 0.5 ** (yas / yarilanma)


def _etkin_agirlik(fact: dict[str, Any], simdi: dt.datetime) -> float:
    """Sıralama ağırlığı: güven × tazelik.

    Eski sıralama YALNIZ güvene bakıyordu ve çıkarıcı "kullanıcı açıkça
    söylediyse 0.9" yazdığı için bir kez açıkça söylenen her şey kalıcı bir
    BİRİNCİLİK BİLETİ alıyordu: zehir bütçenin başını yiyordu. Güven
    bilginin DOĞRULUĞUNU ölçer, GÜNCELLİĞİNİ değil — ikisini tek sayıya
    sıkıştırmak kusurun köküydü.
    """
    try:
        guven = float(fact.get("confidence", 0.0))
    except (TypeError, ValueError):
        guven = 0.0
    return guven * _tazelik(fact, simdi)


def _konu(fact: dict[str, Any]) -> str | None:
    """Olgunun hayat alanı; çıkarılamıyorsa ``None``.

    Önce modelin verdiği ``topic`` (kapalı kümeye uyuyorsa), sonra
    ANAHTARIN PARÇALARI, en sonda kategorinin kendisi denenir. Anahtarın
    parçalarına tek tek bakmak şart: alan bazen başta ("relationship.status")
    bazen sonda ("concern.relationship") duruyor, yani ad alanına bakmak
    ikisinden birini kaçırırdı.

    ``None`` dönmesi kusur değil güvenli varsayılandır: konusu bilinmeyen
    olgu yalnız kendi anahtarıyla birleşir, kimseyi geçersiz kılmaz.
    """
    topic = str(fact.get("topic", "")).strip().lower()
    if topic in KONULAR:
        return topic
    # `in` ile alt dize aramak yerine parçaya BÖLÜP eşitlik: alt dize
    # eşleşmesi yanlış pozitif üretir ("workaround" içinde "work" var).
    for parca in str(fact.get("key", "")).lower().split("."):
        if parca in KONULAR:
            return parca
    kategori = str(fact.get("category", "")).strip().lower()
    return kategori if kategori in KONULAR else None


def _deger_ozeti(value: str) -> str:
    """Değerden KARARLI bir anahtar eki üretir.

    Eskiden ``abs(builtins.hash(value))`` kullanılıyordu ve bu bir HATAYDI:
    ``PYTHONHASHSEED`` ayarlı olmadığı için CPython dize hash'ini her
    süreçte başka tohumlar. Yani aynı olgu her Cloud Run örneğinde BAŞKA
    bir anahtar alıyordu ve hafızanın tek birleştirme mekanizması ``key``
    üzerinden çalıştığı için birleşmesi gereken kayıt sessizce çoğalıyordu.
    Ölçüm ("sevgilimle kavga ettim", beş ayrı süreç): 494745 / 101280 /
    762372 / 490667 / 100350. Bu sayılar BİREBİR tekrarlanmaz ve
    tekrarlanmaması kusurun kendisidir — tohum her süreçte rastgeledir.
    İddia "değerler birbirinden FARKLI", belli bir değer iddiası değil;
    kararlılığı sınayan bekçi de bu yüzden değere değil AYNILIĞA bakıyor.

    blake2s yalnız kararlı olduğu için değil KISA olduğu için de seçildi
    (anahtar Firestore dokümanında saklanıyor). Kriptografik bir iddia
    yok; tek şart süreçler arası aynılık.

    GERİYE DÖNÜK ETKİ (üretimde bu koleksiyonda kayıt VAR): anahtar biçimi
    ``category.<6 hane>`` iken ``category.<8 hex>`` oldu. Göç betiği YOK ve
    gerekmiyor, çünkü kayıp üretmiyor: eski kayıt kendi anahtarıyla
    yaşamaya devam eder, en kötü hâlde aynı olgu BİR KEZ daha doğar ve
    o günden sonra kararlı kalır — eskiden her süreçte çoğalıyordu, yani
    bu değişiklik çoğalmayı bir kereye indiriyor. Artan eski kopyayı ömür
    kapısı ve budama temizler. Yol ayrıca SEYREK: yedek anahtar yalnız
    model ``key`` göndermediğinde kurulur ve ``memory_extractor._SCHEMA``
    ``key``i ``required`` işaretliyor. ÖLÇÜLMEYEN: üretimdeki kayıtların
    kaç tanesinin sayısal sonekli olduğu — üretim Firestore'u okunmadı.
    """
    return hashlib.blake2s(value.encode("utf-8"), digest_size=4).hexdigest()


def _normalize_fact(fact: dict[str, Any],
                    simdi: dt.datetime | None = None) -> dict[str, Any] | None:
    """Tek bir olguyu şemaya oturtur; kategorisi tanınmıyorsa ``None``."""
    category = str(fact.get("category", "")).strip().lower()
    if category not in CATEGORIES:
        return None

    value = str(fact.get("value", "")).strip()
    if not value:
        return None

    key = str(fact.get("key", "")).strip() or f"{category}.{_deger_ozeti(value)}"

    try:
        confidence = float(fact.get("confidence", 0.5))
    except (TypeError, ValueError):
        confidence = 0.5

    normalize: dict[str, Any] = {
        "category": category,
        "key": key,
        "value": value[:MAX_FACT_CHARS],
        "confidence": min(max(confidence, 0.0), 1.0),
        "updatedAt": _simdi(simdi),
    }
    # Konu, çelişki kuralının tek dayanağı; anahtar kesinleştikten SONRA
    # çıkarılır, çünkü yedek anahtar da konu taşır ("concern.a1b2c3d4"
    # taşımaz, o yüzden None kalır ve kimseyi geçersiz kılmaz).
    konu = _konu({**fact, "key": key, "category": category})
    if konu:
        normalize["topic"] = konu
    return normalize


def _prune_facts(facts: list[dict[str, Any]],
                 simdi: dt.datetime | None = None) -> list[dict[str, Any]]:
    """Sınır aşıldığında sırayla geçersiz, ömrü geçmiş ve en zayıf olguyu düşürür.

    Eski sıra YALNIZ güvene bakıyordu ve docstring'i bunu itiraf ediyordu
    ("önce düşük güvenli... olguları düşürür"): 0.9 güvenli ESKİ bir kaygı
    BUDANAMIYORDU. Artık zayıflık = güven × tazelik, yani yüksek güvenli
    eski bir olgu da budanabilir — zaten fısıltıya giremiyor, depolama
    slotunu tutmasının bir gerekçesi yok.

    Geçersiz ve ömrü geçmiş olgular ayrı ve ÖNCE gelen iki sınıf: ikisi de
    fısıltıya hiç girmiyor, dolayısıyla canlı bir olgu onların yüzünden
    düşerse hafıza bilerek yanlış kırpılmış olurdu.
    """
    if len(facts) <= MAX_FACTS:
        return facts
    an = _simdi(simdi)
    ordered = sorted(
        facts,
        key=lambda f: (
            0 if f.get("invalidatedAt") else 1,
            0 if _omru_gecti(f, an) else 1,
            _etkin_agirlik(f, an),
        ),
        reverse=True,
    )
    return ordered[:MAX_FACTS]


def _eski_mi(eski: dict[str, Any], yeni: dict[str, Any]) -> bool:
    """``eski`` gerçekten ``yeni``den önce mi yazılmış?

    Aynı çıkarım turunda gelen iki olgu AYNI damgayı taşır ve biri
    diğerini geçersiz kılmamalı: ikisi de aynı konuşmada söylendi,
    aralarında "yenisi" yok. Tarihi bilinmeyen kayıt eski SAYILIR — şema
    öncesi bir kaydın yeni bilgiyi bastırması çelişki kuralının tam tersi
    olurdu.
    """
    a, b = eski.get("updatedAt"), yeni.get("updatedAt")
    if a is None:
        return True
    if b is None:
        return False
    try:
        return a < b
    except TypeError:
        # Karşılaştırılamayan damga (biri naive) bilinmeyen sayılır.
        return True


def upsert_facts(uid: str, facts: list[dict[str, Any]],
                 simdi: dt.datetime | None = None) -> dict[str, Any]:
    """Olguları ``key`` üzerinden birleştirir (aynı anahtar güncellenir).

    Ayrıca ÇELİŞKİDE YENİSİ KAZANIR (K6-b): aynı konuda yeni bilgi gelince
    eski kaygı kaydı ÜSTÜNE YIĞILMAZ, geçersiz işaretlenir. Sahibin tarif
    ettiği zehirlenme ("biriyle bir problem yaşadın, tüm yorumları
    zehirliyor ve hiç gitmiyor") kaydın kendisinden değil, kaydın yeni
    bilgiye rağmen yaşamaya devam etmesinden geliyordu: "ayrıldık"
    dedikten sonra "sevgilisiyle sorun yaşıyor" yan yana duruyordu, çünkü
    iki kaydın anahtarı da kategorisi de farklı ve ``key`` birleştirmesi
    ikisini hiç karşılaştırmıyor.

    Şemaya uymayan olgular sessizce atılır. Güncellenmiş hafızayı döndürür.
    """
    an = _simdi(simdi)
    normalized = [n for n in (_normalize_fact(f, an) for f in facts)
                  if n is not None]
    memory = get_memory(uid)
    if not normalized:
        return memory

    by_key = {f.get("key"): f for f in memory["facts"]}
    for fact in normalized:
        konu = fact.get("topic")
        if konu:
            for eski in by_key.values():
                # `eski.get("topic")` DEĞİL `_konu(eski)`: ``topic`` alanı
                # bu turda doğdu, yani ÜRETİMDEKİ hiçbir kayıtta YOK. Alanı
                # doğrudan okumak çelişki kuralını "yalnız bu değişiklikten
                # sonra yazılmış kayıtlar" ile sınırlıyordu — oysa zehir tam
                # da eski kayıtta duruyor ve 30 günlük ömür kapısı onu ancak
                # bir ay sonra düşürüyor. ``_konu`` konuyu anahtarın
                # parçalarından da çıkarabildiği için ("concern.relationship")
                # kural ilk deploy anından itibaren eski kayıtlara da işler.
                if (eski.get("key") != fact["key"]
                        and _konu(eski) == konu
                        and str(eski.get("category")) in CELISKIDE_DUSEN
                        and not eski.get("invalidatedAt")
                        and _eski_mi(eski, fact)):
                    # SİLİNMİYOR, işaretleniyor: budama geçersizleri ilk
                    # kurban sınıfı sayıyor, yani slot zaten geri geliyor;
                    # kayıt dururken ileride "bu aşıldı" diye gösterilebilir
                    # (kullanıcıya görünen hafıza ekranı bu turda yok).
                    eski["invalidatedAt"] = an
        by_key[fact["key"]] = fact

    memory["facts"] = _prune_facts(list(by_key.values()), an)
    _write(uid, memory)
    return memory


#: Ruh hali yoğunluğu (S-turu). Tek kelimelik ruh hali yetmiyordu: "biraz
#: kaygılıyım" ile "dağılmak üzereyim" aynı satıra düşüyor ve model ikisine
#: de aynı tonda cevap veriyordu.
INTENSITIES = ("low", "medium", "high")

#: Kullanıcının o turda ARADIĞI şey. Aynı soru farklı ihtiyaçla sorulabilir:
#: "ne yapmalıyım" bazen yön ister, bazen sadece anlaşılmak.
NEEDS = ("information", "direction", "understanding", "rest")


def record_mood(uid: str, mood: str, note: str = "",
                intensity: str = "", needs: str = "") -> None:
    """Günlük ruh hali izini ekler (gün başına tek kayıt; aynı gün üzerine yazar).

    ``intensity`` ve ``needs`` (S-turu) isteğe bağlı: tanınmayan değer
    sessizce düşer — modelin uydurduğu bir etiket şemaya giremez.
    """
    mood = mood.strip()[:60]
    if not mood:
        return

    memory = get_memory(uid)
    today = dt.date.today().isoformat()
    trail = [entry for entry in memory["moodTrail"] if entry.get("date") != today]
    kayit: dict[str, Any] = {
        "date": today, "mood": mood,
        "note": note.strip()[:MAX_FACT_CHARS],
    }
    if intensity in INTENSITIES:
        kayit["intensity"] = intensity
    if needs in NEEDS:
        kayit["needs"] = needs
    trail.append(kayit)
    memory["moodTrail"] = trail[-MAX_MOOD_ENTRIES:]
    _write(uid, memory)


def set_tone_hint(uid: str, hint: str) -> None:
    """Kullanıcının tercih ettiği anlatım tonunu kaydeder."""
    memory = get_memory(uid)
    memory["toneHint"] = hint.strip()[:MAX_TONE_CHARS] or None
    _write(uid, memory)


# ---------------------------------------------------------------------------
# Günlük (R2-G1)
# ---------------------------------------------------------------------------

def add_diary_entry(uid: str, text: str, theme: str | None = None,
                    date: str | None = None) -> dict[str, Any] | None:
    """Tek satırlık günlük girişi ekler; eklenen girişi döndürür.

    Kimlik zaman damgasından türetilir (silme ucu bununla adresler).
    Metin boşsa ya da tema tanınmıyorsa None döner — uydurma tema yazılmaz.
    """
    text = text.strip()[:MAX_DIARY_CHARS]
    if not text:
        return None
    if theme is not None:
        theme = str(theme).strip().lower()
        if theme not in DIARY_THEMES:
            return None

    simdi = dt.datetime.now(dt.timezone.utc)
    giris = {
        "id": f"d{int(simdi.timestamp() * 1000)}",
        "date": date or simdi.date().isoformat(),
        "text": text,
        "theme": theme,
    }
    memory = get_memory(uid)
    memory["diary"] = (memory["diary"] + [giris])[-MAX_DIARY_ENTRIES:]
    _write(uid, memory)
    return giris


def delete_diary_entry(uid: str, entry_id: str) -> bool:
    """Girişi kimliğiyle siler; bulunamadıysa False."""
    memory = get_memory(uid)
    kalan = [g for g in memory["diary"] if g.get("id") != entry_id]
    if len(kalan) == len(memory["diary"]):
        return False
    memory["diary"] = kalan
    _write(uid, memory)
    return True


def get_diary(uid: str) -> list[dict[str, Any]]:
    """Günlük girişleri, yeniden eskiye."""
    return sorted(get_memory(uid)["diary"],
                  key=lambda g: (g.get("date") or "", g.get("id") or ""),
                  reverse=True)


def _yas_etiketi(yas_gun: float) -> str:
    """Yaşı modelin okuyabileceği göreli bir ifadeye çevirir.

    MUTLAK tarih değil GÖRELİ ifade yazılıyor: sohbet prompt'unun bugünün
    tarihini taşıdığı garanti değil, yani "2026-08-20" modele hiçbir şey
    anlatmazdı. İhtiyaç, "bu üç gün önceydi" ile "bu altı ay önceydi"
    arasındaki farkın GÖRÜNMESİ — eski fısıltı tarihi hiç yazmıyordu ve
    model bilginin dünkü mü yıllık mı olduğunu bilemiyordu.
    """
    gun = int(yas_gun)
    if gun <= 0:
        return "bugün"
    if gun == 1:
        return "dün"
    return f"{gun} gün önce"


def _ruh_hali_satiri(trail: list[dict[str, Any]], pay: int) -> str:
    """Ruh hali seyri satırı — payına sığacak kadar GİRİŞLE.

    NEDEN kırpma burada ve neden EN AZ İKİ giriş: seyir TEK bir satıra
    sıkıştığı için uzunluğu giriş sayısıyla büyüyor (ölçüldü: giriş başına
    ~30 karakter, beş girişte 152). Payına sığmayan bir satır garanti
    turunda yine içeri girerdi ve `max_chars=400`'de tek başına bütçenin
    %38'ini yerdi — yani payın anlamı kalmazdı.

    Kırpma OLUŞTAN değil SONDAN alır (en yeni girişler kalır) ve ikinin
    altına İNMEZ: "seyir" adı bir EĞİLİM iddia ediyor ve tek girişle
    gösterilen şey eğilim değil FOTOĞRAFtır — ölçüleni yanlış adla
    sunmak olurdu. İki giriş payı aşıyorsa satır yine iki girişle kurulur;
    o hâli bütçeye sığdıran şey garanti turudur.
    """
    def _yaz(e: dict[str, Any]) -> str:
        metin = f"{e['date']}: {e['mood']}"
        if e.get("intensity"):
            metin += f"({e['intensity']})"
        return metin

    def _satir(n: int) -> str:
        return "- (ruh hali seyri) " + ", ".join(
            _yaz(e) for e in trail[-n:])

    for n in range(len(trail), 1, -1):
        satir = _satir(n)
        if len(satir) <= pay:
            return satir
    return _satir(min(2, len(trail)))


def _paylara_bol(bilesenler: list[tuple[str, list[str]]],
                 max_chars: int) -> str:
    """Satırları bileşen PAYLARINA göre bütçeye yerleştirir.

    Üç tur, ve sıraları gerekçeli:

    1. **GARANTİ** — her boş olmayan bileşenin İLK satırı, bütçeye
       sığdığı sürece payına BAKILMADAN girer. Pay tek başına yetmez:
       ölçülen ton ipucu 52 karakter, `max_chars=400`'de payı 32 — payla
       sınırlı kalsaydı ton tercihi yine hiç görünmezdi. "Her bileşen en
       az bir satır" kuralını tutan tur budur.
    2. **ORANSAL** — kalan satırlar, bileşen kendi payını aşmadığı
       sürece eklenir. Pay burada TAVANdır ve en ısrarlı olgunun bütçenin
       başını yemesini kesen tur budur.
    3. **ARTAN** — paylardan artan yer, bileşen sırasıyla ve pay
       GÖZETİLMEDEN dağıtılır. Olmazsa günlüğü olmayan kullanıcının
       bütçesinin %35'i boş durur; pay aç bırakmayı önlerken israf
       üretirdi. Artanı ilk gören bileşen olgulardır (sıra önce onlar) —
       bu bilinçli: olgu, fısıltının en çok iş yapan bileşeni.

    Satırlar SEÇİM sırasına göre değil BİLEŞEN sırasına göre basılır
    (olgu → ruh hali → günlük → ton): garanti turu bileşenler arasında
    gezindiği için seçim sırası karışıktır ve fısıltının okunma sırası
    bundan etkilenmemeli.

    Tek satır tek başına bütçeden büyükse ve henüz hiçbir şey
    eklenmediyse kelime sınırından kırpılır — fısıltı hiç boş kalmasın
    (KA9'dan devralındı).
    """
    # Seçim DEĞERLE değil DİZİNLE izleniyor: iki bileşen satırı birebir
    # aynı olabilir (aynı gün iki kez yazılmış bir günlük girdisi) ve
    # değer üyeliğiyle çalışan bir kapı ikisini birden atlardı. Ayrıca
    # pay turunda sığmayan uzun bir satır atlanıp SONRAKİ kısa satır
    # girebiliyor, yani seçilenler listenin ÖNEKİ olmak zorunda değil.
    secilen: dict[str, set[int]] = {ad: set() for ad, _ in bilesenler}
    kirpik: dict[str, str] = {}
    kullanilan: dict[str, int] = {ad: 0 for ad, _ in bilesenler}
    toplam = 0

    def _ekle(ad: str, i: int, satir: str) -> None:
        nonlocal toplam
        secilen[ad].add(i)
        kullanilan[ad] += len(satir) + 1
        toplam += len(satir) + 1

    # 1. GARANTİ
    for ad, satirlar in bilesenler:
        if not satirlar:
            continue
        satir = satirlar[0]
        if toplam + len(satir) + 1 <= max_chars:
            _ekle(ad, 0, satir)
        elif toplam == 0 and max_chars > 40:
            # Kırpma kelime sınırından: boşluksuz çok uzun bir değer
            # burada neredeyse tamamen gider ve bu BİLEREK öyle —
            # anlamsız bir karakter yığını bütçeyi yemesin, kalan
            # bileşenler yine girebilsin.
            kirpik[ad] = satir[:max_chars - 1].rsplit(" ", 1)[0] + "…"
            _ekle(ad, 0, kirpik[ad])

    # 2. PAY
    for ad, satirlar in bilesenler:
        pay = int(max_chars * _FISILTI_PAYLARI[ad])
        for i, satir in enumerate(satirlar):
            if i in secilen[ad]:
                continue
            if kullanilan[ad] + len(satir) + 1 > pay:
                continue
            if toplam + len(satir) + 1 > max_chars:
                continue
            _ekle(ad, i, satir)

    # 3. ARTAN
    for ad, satirlar in bilesenler:
        for i, satir in enumerate(satirlar):
            if i in secilen[ad]:
                continue
            if toplam + len(satir) + 1 > max_chars:
                continue
            _ekle(ad, i, satir)

    return "\n".join(
        kirpik.get(ad) if i == 0 and ad in kirpik else satirlar[i]
        for ad, satirlar in bilesenler
        for i in sorted(secilen[ad])).strip()


def memory_context(uid: str, max_chars: int = 600,
                   simdi: dt.datetime | None = None) -> str:
    """Hafızayı prompt'a iliştirilebilecek kompakt bir özete indirger.

    `prompt_composer` bunu "arka plan fısıltısı" olarak kullanır; bilgi
    tabanı pasajlarında olduğu gibi modele blok halinde aktarılmaz.

    Olgu seçimi üç kapıdan geçer ve sırası önemli:
    1. geçersiz kılınmış ve ömrü geçmiş olgular HİÇ girmez (unutma),
    2. kalanlar güven × tazelik ile sıralanır (en ısrarlı değil en güncel
       olan bütçenin başını kapar),
    3. ``MAX_WHISPER_FACTS`` dilimi uygulanır.

    Bütçe bileşenler arasında PAYLARA bölünür (`_FISILTI_PAYLARI`); hangi
    kusurun kapandığı ve payların nereden geldiği orada ölçüldü.
    """
    an = _simdi(simdi)
    memory = get_memory(uid)

    uygun = [f for f in memory["facts"]
             if not f.get("invalidatedAt") and not _omru_gecti(f, an)]
    sirali = sorted(
        uygun,
        key=lambda f: (_SIRA_ONCELIGI.get(str(f.get("category")), 0),
                       _etkin_agirlik(f, an)),
        reverse=True,
    )
    olgu_satirlari: list[str] = []
    for fact in sirali[:MAX_WHISPER_FACTS]:
        etiket = str(fact.get("category"))
        yas = _yas_gun(fact, an)
        if yas is not None:
            etiket += f", {_yas_etiketi(yas)}"
        olgu_satirlari.append(f"- ({etiket}) {fact['value']}")

    # Ruh hali SEYRİ — tek fotoğraf değil eğilim (S-turu). Yoğunluk da
    # yazılıyor: modelin "üç gündür ağırlaşıyor" ile "dün biraz yorgundu"
    # arasındaki farkı görmesi, tonunu ona göre kurmasının tek yolu.
    ruh_hali_satirlari: list[str] = []
    trail = memory["moodTrail"][-5:]
    if trail:
        ruh_hali_satirlari.append(_ruh_hali_satiri(
            trail, int(max_chars * _FISILTI_PAYLARI["ruh_hali"])))
        # En son turda kullanıcının ne aradığı, tonun en güçlü ipucu.
        son = trail[-1]
        if son.get("needs"):
            ruh_hali_satirlari.append(f"- (son turda aradığı) {son['needs']}")

    # Günlük (R2-G1): son girişler sohbetin gözüne girer — "son ayda ne
    # oldu?" sorusu bu satırlar + gökyüzü verisiyle cevaplanabilir.
    gunluk_satirlari = [
        f"- (günlük {g.get('date')}) {g.get('text')}"
        for g in (memory.get("diary") or [])[-6:]]

    ton_satirlari = ([f"- (ton tercihi) {memory['toneHint']}"]
                     if memory.get("toneHint") else [])

    return _paylara_bol([
        ("olgu", olgu_satirlari),
        ("ruh_hali", ruh_hali_satirlari),
        ("gunluk", gunluk_satirlari),
        ("ton", ton_satirlari),
    ], max_chars)


def delete_memory(uid: str) -> None:
    """Kullanıcının tüm hafızasını siler.

    ⚠️ Bu fonksiyonu ÇAĞIRAN YOK ve eski docstring'i yanlış bir gerekçe
    taşıyordu ("hesap silme akışının parçasıdır"). Hesap silmede hafıza
    dokümanını silen şey `account_service._delete_user_subcollections`:
    `_SUB_COLLECTIONS` içinde ``private`` var ve ``private/memory`` o genel
    süpürmeyle gidiyor. Yani KVKK/GDPR vaadi tutuluyor, ama bu satırlar
    sayesinde değil.

    Fonksiyon duruyor çünkü hafızanın TEK silme yüzeyi bu ve bir gün
    gerekecek: şu anda kullanıcının "bunu unut" diyebileceği hiçbir uç yok
    (olgu başına silme de, hep-ya-da-hiç temizleme de). O uç eklendiğinde
    buradan geçecek.
    """
    doc_ref = _doc(uid)
    if doc_ref is None:
        return
    try:
        doc_ref.delete()
    except Exception as exc:
        logger.warning("Hafıza silinemedi (%s): %s", uid, exc)


def _write(uid: str, memory: dict[str, Any]) -> None:
    doc_ref = _doc(uid)
    if doc_ref is None:
        return
    try:
        doc_ref.set({
            "version": SCHEMA_VERSION,
            "facts": memory["facts"],
            "moodTrail": memory["moodTrail"],
            "toneHint": memory.get("toneHint"),
            "diary": memory.get("diary", []),
            "updatedAt": dt.datetime.now(dt.timezone.utc),
        })
    except Exception as exc:
        logger.warning("Hafıza yazılamadı (%s): %s", uid, exc)

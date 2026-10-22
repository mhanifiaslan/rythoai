"""Bildirim zamanlama mantığı — kime, ne zaman, kaç kez.

Bu modül **gönderim yapmaz**; yalnızca karar verir. Gönderim api/notify.py
içindedir. Ayrım bilinçli: buradaki kurallar (yerel saat, sessiz saat, tekrar
koruması) FCM'e hiç dokunmadan test edilebilmeli.

Dört kural birlikte çalışır ve dördü de kullanıcıyı korumak içindir:

1. **Yerel saat.** Bildirim kullanıcının sabahına denk gelmeli. Sunucu UTC'de
   çalışır; kullanıcının saat dilimi profilinde IANA adı olarak tutulur.
   Doğum şehri kullanılamaz — kişi doğduğu yerde yaşamıyor olabilir.
2. **Sessiz saat.** Gece bildirim göndermek, bu kategoride uygulamanın
   silinmesinin en hızlı yoludur. Varsayılan 22:00-08:00.
3. **Tekrar koruması.** Zamanlayıcı saatte bir çalışır ve yeniden deneme
   yapabilir; aynı bildirim iki kez gitmemeli. Gönderim kaydı sunucuya kapalı
   bir dokümanda tutulur.
4. **Günlük toplam tavan.** Tür başına tekrar koruması tek başına yetmez:
   her tür kendi hakkını kullanınca TOPLAM büyür ve kullanıcı bombardımana
   uğrar. Tavan `GUNLUK_PUSH_TAVANI`de ve zamanlanmış yolu da olay yolunu
   da kapsar — telefon push'un hangi alt sistemden geldiğini bilmiyor.
"""
from __future__ import annotations

import datetime as dt
import logging
import re
from dataclasses import dataclass
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from core import cache, firestore as firestore_client, i18n
from services import gemini_service, prompts

logger = logging.getLogger(__name__)

#: Saat dilimi okunamazsa kullanılacak varsayılan. Kullanıcıların büyük
#: çoğunluğu bu dilimde; yine de her profilde saat dilimi olması hedeflenir.
DEFAULT_TIMEZONE = "Europe/Istanbul"

#: Sessiz saat varsayılanları (yerel saat, 24 saatlik).
DEFAULT_QUIET_FROM = 22
DEFAULT_QUIET_TO = 8

#: Bildirim türlerinin hedef yerel saati. Zamanlayıcı saatte bir çalışır ve
#: yalnızca yerel saati bu değere eşit olan kullanıcılara gönderir.
TARGET_HOURS = {
    "daily": 9,     # sabah: günün okuması hazır
    "midday": 13,   # öğle: yalnız BUGÜN gerçekten kesinleşen olay varsa (OB3)
    "circle": 18,   # ikindi: çevresindeki biriyle bugün ölçülen şey (CV)
    "winback": 19,  # akşamüstü: sessizliğin kademeli geri çağrısı (K7)
    "checkin": 20,  # akşam: günün önemli sinyaline bağlı kişisel soru (KA4)
    "streak": 20,   # akşam: seri kırılmadan önce son hatırlatma (soru yoksa)
}

#: Zamanlayıcıdan tetiklenebilecek türler.
SCHEDULED_TYPES = tuple(TARGET_HOURS)

#: AKŞAM AİLESİ: bu türlerden bir yerel günde EN FAZLA BİRİ gider.
#:
#: Kural yeni DEĞİL, genişletildi: `checkin` ⊕ `streak` dışlaması KA4'ten
#: beri vardı ("akşam en fazla bir bildirim") ama iki tür için elle, iki
#: ayrı `if` ile yazılmıştı. `circle` (18) ve `winback` (19) aynı pencereye
#: girdiği için kural bir KÜMEYE çevrildi; ikili yazım kalsaydı her yeni
#: tür için dört yeni `if` gerekirdi ve biri unutulduğu an kullanıcı akşam
#: üç bildirim alırdı.
#:
#: Sırayı önce yerel saat belirler (18 < 19 < 20): önce koşan işaretler,
#: sonrakiler susar. Bu yüzden "circle, winback'e yol versin" kuralı bu
#: kümeyle SAĞLANAMAZ — circle her zaman önce koşar. O kapı `should_send`
#: içinde ayrıca duruyor.
#:
#: ⚠️ AMA saat TEK BAŞINA belirlemez ve bu düzeltilmiş bir gerekçedir
#: (eskiden burada "sırayı KOD DEĞİL yerel saat belirler" yazıyordu —
#: ölçüldü, yanlış): `checkin` ile `streak` AYNI saatte (20) ve aralarında
#: kararı `infra/create-scheduler.ps1`in DAKİKASI veriyor (:08 < :10).
#: Yani saatler çakıştığı an sırayı betik belirler. Ölçülen bedeli
#: (mutasyon N03): `circle` 18'den 20'ye alınırsa `checkin` :08'de
#: işaretler, `circle` :14'te bu kümeye takılır ve slot HİÇ geçmez —
#: paketin onardığı "pratikte ölü Çevrem" kusuru geri gelir. Bu yüzden
#: `circle`ın saatinin öteki üyelerden STRICT küçük olması
#: `tests/test_notify_slot_kapsamasi.py` ile çivilendi.
EVENING_FAMILY = ("circle", "winback", "checkin", "streak")

#: Bir kullanıcıya bir YEREL günde gidebilecek EN FAZLA push sayısı.
#:
#: ÖLÇÜLDÜ (2026-10-02, bu depo, gerçek `should_send` ile): bu turdan ÖNCE
#: zamanlanmış yolun tavanı **3**. Ölçüm, Scheduler işlerinin gerçek
#: dakika sırasıyla (:05 daily, :08 checkin, :10 streak, :12 midday) 24
#: yerel saat boyunca koşturularak alındı; geçenler `daily@9`,
#: `midday@13`, `checkin@20` — `streak` akşam dışlamasına takılıyor.
#: OLAY yolunda ise tavan **SONSUZ**du: `can_send_event` yalnız
#: jeton/tercih/sessiz saate bakıyor ve `/notify/reaction` hiçbir tekrar
#: korumasına tabi değildi (tek arkadaş sınırsız push attırabiliyordu).
#:
#: NEDEN 4 = 3 + 1. **3** ölçülen mevcut tavandır ve bu turda yapıya
#: çivilendi (akşam ailesi + daily + midday): yeni slotlar tavanı
#: YÜKSELTMİYOR, birbirinin YERİNE geçiyor. **+1** insan yolu için
#: ayrılmış en küçük paydır — tavan 3 olsaydı en dolu günde bir arkadaşın
#: dürtmesi sessizce düşerdi ve bu, kimsenin istemediği bir davranış
#: değişikliği olurdu.
#:
#: BEDELİ (kabul edilmiş): üç ayrı arkadaş aynı gün dürterse 2. ve 3.
#: dürtmenin PUSH'u düşer. Tepki Firestore'a yine yazılır ve uygulama
#: içindeki kutuda görünür — kaybolan şey bildirim, veri değil.
#:
#: ⚠️ Zamanlanmış tavanın 3 olduğu `test_notify_tavan.py` içinde
#: ENUMERE EDİLEREK sınanır. Yeni bir slot o sayıyı 4'e çıkarırsa test
#: kırmızı yanar ve bu sabit yeniden ÖLÇÜLMEK zorunda kalır; tahminle
#: büyütülmesin.
GUNLUK_PUSH_TAVANI = 4

#: Geri kazanım basamakları: kaç TAM gün sessizlikten sonra çalar.
#: Kullanıcı kararı K7 — kademeli 3 → 10 → 30, sonra SUSAR.
WINBACK_TIERS = (3, 10, 30)

#: Serinin hatırlatmaya değer sayılması için gereken en az gün. Tek günlük
#: seri için bildirim göndermek rahatsız edici olur; kaybedilecek bir şey yok.
#:
#: ⚠️ Bu eşik, geri kazanımın NEDEN ayrı bir tür olmak zorunda olduğunun da
#: sebebi: üç gündür girmeyenin serisi 0'dır, yani bu kapıya hiç gelemez.
#: En çok çağrılması gereken kullanıcı, `streak` yolunun yapısal olarak
#: sessiz kaldığı kullanıcıydı.
MIN_STREAK_FOR_REMINDER = 2


def _notification_doc(uid: str):
    client = firestore_client.get_client()
    if client is None:
        return None
    return (client.collection("users").document(uid)
            .collection("private").document("notifications"))


# ---------------------------------------------------------------------------
# Yerel saat
# ---------------------------------------------------------------------------

def user_timezone(profile: dict[str, Any]) -> ZoneInfo:
    """Profildeki saat dilimi; tanınmıyorsa varsayılan.

    Bilinmeyen bir dilim yüzünden istisna fırlatmak, tek bir bozuk profilin
    tüm toplu gönderimi düşürmesi demek olurdu.
    """
    ad = (profile.get("timezone") or "").strip()
    if ad:
        try:
            return ZoneInfo(ad)
        except (ZoneInfoNotFoundError, ValueError):
            logger.info("Taninmayan saat dilimi: %s", ad)
    return ZoneInfo(DEFAULT_TIMEZONE)


def local_now(profile: dict[str, Any],
              now_utc: dt.datetime | None = None) -> dt.datetime:
    """Kullanıcının yerel saati."""
    now_utc = now_utc or dt.datetime.now(dt.timezone.utc)
    if now_utc.tzinfo is None:
        now_utc = now_utc.replace(tzinfo=dt.timezone.utc)
    return now_utc.astimezone(user_timezone(profile))


# ---------------------------------------------------------------------------
# Sessiz saat
# ---------------------------------------------------------------------------

def _saat(deger: Any, varsayilan: int) -> int:
    try:
        saat = int(deger)
    except (TypeError, ValueError):
        return varsayilan
    return saat if 0 <= saat <= 23 else varsayilan


def in_quiet_hours(profile: dict[str, Any], yerel: dt.datetime) -> bool:
    """Yerel saat sessiz aralıkta mı?

    Aralık gece yarısını aşabilir (22:00-08:00). ``from == to`` sessiz saat
    yok demektir; aksi halde 24 saat sessiz olurdu ve kullanıcı hiç bildirim
    almazdı.
    """
    baslangic = _saat(profile.get("quietFrom"), DEFAULT_QUIET_FROM)
    bitis = _saat(profile.get("quietTo"), DEFAULT_QUIET_TO)
    if baslangic == bitis:
        return False

    saat = yerel.hour
    if baslangic < bitis:
        return baslangic <= saat < bitis
    # Gece yarısını aşan aralık
    return saat >= baslangic or saat < bitis


# ---------------------------------------------------------------------------
# Tekrar koruması
# ---------------------------------------------------------------------------

#: `mark_sent`in yazdığı "bu tür bugün gitti" alanlarının son eki.
#: `gunluk_push_sayisi` sayımı buna bağlıyor.
_SENT_SUFFIX = "LastSent"


def gunluk_push_sayisi(uid: str, gun: str) -> int:
    """Bu kullanıcıya bu YEREL günde kaç push gitti?

    TÜRETİLMİŞ ölçüm, ayrı bir sayaç DEĞİL: `mark_sent` her başarılı
    gönderimde `{tür}LastSent = gün` yazıyor ve her tür günde en fazla bir
    kez gidiyor (kendi tekrar koruması). Yani değeri bugüne eşit olan
    `*LastSent` alanlarının sayısı, bugün gerçekten gönderilen push
    sayısıdır. Ayrı bir sayaç alanı tutmak bir okuma-değiştir-yaz turu ve
    iki kaynağın sessizce ayrışması riski demekti; türetilmiş sayı tanım
    gereği ayrışamaz.

    Olay yolu da sayıya girer: davet/kabul `invite-{uid}`/`accept-{uid}`,
    tepki `reaction-{uid}` adıyla AYNI dokümana yazıyor.

    ⚠️ BEDELİ ÖLÇÜLDÜ ve burada yazılı duruyor, çünkü "türetilmiş sayı
    bedavadır" denmesin: bu çağrı AYNI dokümanı bir kez daha çekiyor ve
    `should_send` içinde ÖNBELLEKLENMİYOR. Hedef saatine denk gelen bir
    kullanıcı için ölçülen `private/notifications` okuma sayısı (sayım
    çağrı yerine göre ayrıştırılarak YENİDEN alındı, 2026-10-03):
    `daily`/`midday` 1 → **2**, `checkin`/`streak` 2 → **5** (3'ü akşam
    ailesi döngüsünden), `circle` **5**, `winback` **6**.
    ⚠️ `winback` için eskiden burada "5 + koşunun basamağı yeniden
    okuması = 6" yazıyordu ve ikisi de bir eksikti: akşam ailesinin 3
    okumasına ek olarak `winback_state` de aynı dokümanı çekiyor
    (4 × `already_sent` + 1 × `winback_state` + 1 × tavan = 6), koşu
    basamağı bir kez daha okuduğu için gerçek toplam **7**.
    Aynı dokümanın beşinci kez çekilmesi mantığı değiştirmiyor
    (tek koşu, tek an), yalnız okuma sayısını büyütüyor. 18 profilde
    önemsiz; hedef saatine denk gelen kullanıcı sayısı binlere çıkarsa
    tek bir anlık görüntüyü `should_send` boyunca taşımak gerekir.
    Tahminle değil ÖLÇÜLEREK karar verilsin.

    OKUMA DÜŞERSE 0 DÖNER — yani tavan AÇIK kalır. Ters seçim (okunamazsa
    kapat) daha güvenli GÖRÜNÜR ama hiçbir şey korumaz: aynı kesintide
    `already_sent` True dönüp gönderimi zaten engelliyor. Tavanı da
    kapatmak aynı kararı iki kez vermek olurdu; karşılığında bütün
    bildirimleri tek bir Firestore kesintisine bağlardı.

    ⚠️ Güvence SIRAYA DAYANMIYOR ve bu düzeltilmiş bir gerekçe (eskiden
    "bu kapıdan ÖNCE tekrar koruması geçiliyor, ancak bu sırayla güvenli"
    yazıyordu — ölçüldü, yanlış): `should_send` tekrar korumasını tavandan
    önce çağırıyor ama olay yolu TERSİNİ yapıyor (`can_send_event` tavanı
    bakar, `already_sent` çağıranda SONRA gelir — `api/notify.py` `/reaction`
    ve `_event_push`). İkisi de güvenli, çünkü gönderimden önce İKİ kapı da
    değerlendiriliyor ve kesintide kapanan kapı her iki yolda da tekrar
    korumasıdır. Sıra yalnız gerekçe adını (`zaten-gonderildi` ↔
    `gunluk-tavan`) ve okuma sayısını değiştirir.
    """
    doc = _notification_doc(uid)
    if doc is None:
        return 0
    try:
        anlik = doc.get()
    except Exception as exc:
        logger.warning("Gunluk push sayisi okunamadi (%s): %s", uid, exc)
        return 0
    if not anlik.exists:
        return 0
    return sum(1 for ad, deger in (anlik.to_dict() or {}).items()
               if ad.endswith(_SENT_SUFFIX) and deger == gun)


def son_gorulme_farki(profile: dict[str, Any],
                      yerel: dt.datetime) -> int | None:
    """Kullanıcı kaç TAM yerel gündür günlük okumayı açmadı; bilinmiyorsa None.

    `lastSeenDaily` istemcinin CİHAZ yerel gününü yazıyor
    (apps/mobile/lib/core/motivation.dart) — bu yüzden kıyas sunucunun UTC
    gününe değil kullanıcının yerel gününe karşı yapılır. UTC ile
    kıyaslamak UTC+3'te her gece bir günlük hayali sessizlik üretirdi.

    Alan YOKSA None döner ve geri kazanım bildirimi GÖNDERİLMEZ: "hiç
    okumadın" ile "üç gündür okumadın" aynı şey değil, elimizde yalnız
    ikincisini ölçecek veri var ve ölçülmeyen söylenmez.

    Negatif fark 0'a kırpılır — saat dilimi değiştiren ya da saati ileri
    alınmış bir cihaz geleceğe damga yazabilir.
    """
    ham = profile.get("lastSeenDaily")
    if not isinstance(ham, str) or not ham:
        return None
    try:
        gorulen = dt.date.fromisoformat(ham)
    except ValueError:
        return None
    return max(0, (yerel.date() - gorulen).days)


def winback_state(uid: str, profile: dict[str, Any]) -> int:
    """Bu SESSİZLİK EPİZODUNDA en son gönderilen basamak; yoksa 0.

    Basamak sayacı kullanıcı döndüğü an sıfırlanır ve bunu yapan ayrı bir
    YAZIM YOKTUR — çünkü dönüşü sunucuda gören hiçbir koşu yok: kullanıcı
    uygulamayı açar, istemci `lastSeenDaily`yi yazar, sunucu haberdar
    olmaz. Bu yüzden basamak, gönderildiği andaki `lastSeenDaily`
    DEĞERİNE çivileniyor (`winbackAnchor`). Değer değişmişse kullanıcı
    arada girmiştir; kayıt BAŞKA bir epizoda aittir ve 0 sayılır.

    Çapasız kayıt da 0 sayılır (bu sürümden önce yazılmış bir şey): hangi
    epizoda ait olduğu bilinmeyen bir basamak, 10. gün bildirimini 3.
    günü hiç görmemiş birine gönderebilirdi.

    ⚠️ `not capa` terimi EMNİYET PAYI, yük taşıyan şey değil — ölçüldü
    (mutasyon M07): terim düşürüldüğünde eşitsizlik zaten 0 döndürüyor,
    çünkü çapa yoksa `None != lastSeenDaily`. Terimin fark ettiği tek
    durum ikisinin de boş olması ve orada `winback_tier` çağrısı
    "son-giris-bilinmiyor" ile hiç basamak üretmiyor. Yani bu terimi
    yakalayan bir bekçi YAZILAMAZ; çıkarılabilir de — davranışı
    sınayan test (`test_capasiz_eski_kayit_sifir_sayilir`) ikisinde de
    yeşil kalır ve bu bir eksiklik değil, eşdeğerliğin sonucudur.
    """
    doc = _notification_doc(uid)
    if doc is None:
        return 0
    try:
        anlik = doc.get()
    except Exception as exc:
        logger.warning("Geri kazanim durumu okunamadi (%s): %s", uid, exc)
        return 0
    if not anlik.exists:
        return 0
    veri = anlik.to_dict() or {}
    capa = veri.get("winbackAnchor")
    if not capa or capa != profile.get("lastSeenDaily"):
        return 0
    try:
        return int(veri.get("winbackTier") or 0)
    except (TypeError, ValueError):
        return 0


def winback_tier(profile: dict[str, Any], yerel: dt.datetime,
                 gonderilen: int) -> tuple[int | None, str]:
    """Şimdi hangi basamak çalmalı — `(basamak, gerekçe)`.

    Kural: eşiği geçilmiş EN YÜKSEK basamak, henüz gönderilmemişse çalar.

    - 3. gün → 3. 4-9. günler SUSAR (basamak zaten gitti); aksi halde
      sessizlik boyunca her gün aynı bildirim giderdi.
    - 3. gün bir sebeple kaçırıldıysa (günlük tavan dolmuş, sessiz saat,
      jeton yok) 9. güne kadar hâlâ 3 çalar: tek yoğun gün geri çağrıyı
      sessizce öldürmemeli.
    - 10. günde 3 hiç gitmemişse 3 DEĞİL 10 çalar. Metin sessizliğin
      gerçek uzunluğuna uymak zorunda; "hişt, bugün şu var" demek on gün
      sonra yanlış ad olurdu.
    - 30'dan sonra HİÇBİR ŞEY: aday en yüksek basamaktan büyük olamaz.
      Sessizliğe saygı — kovulma değil.
    """
    fark = son_gorulme_farki(profile, yerel)
    if fark is None:
        return None, "son-giris-bilinmiyor"
    aday = max((t for t in WINBACK_TIERS if t <= fark), default=None)
    if aday is None:
        return None, "sessizlik-kisa"
    if aday <= gonderilen:
        return None, ("basamaklar-bitti" if gonderilen >= WINBACK_TIERS[-1]
                      else "basamak-gitti")
    return aday, "gonderilecek"


def winback_sent_fields(basamak: int,
                        profile: dict[str, Any]) -> dict[str, Any]:
    """Geri kazanım gönderiminin `mark_sent(extra=...)` alanları.

    Çapa, basamağın HANGİ sessizlik epizoduna ait olduğunu söyler; gerekçe
    `winback_state`te.
    """
    return {"winbackTier": int(basamak),
            "winbackAnchor": profile.get("lastSeenDaily") or ""}


def already_sent(uid: str, tur: str, gun: str) -> bool:
    """Bu tür bildirim bu yerel gün için gönderildi mi?"""
    doc = _notification_doc(uid)
    if doc is None:
        # Firestore yoksa tekrar korumasını uygulayamayız. Güvenli taraf
        # GÖNDERMEMEK: aynı bildirimi iki kez atmak, hiç atmamaktan kötüdür.
        return True
    try:
        anlik = doc.get()
    except Exception as exc:
        logger.warning("Gonderim kaydi okunamadi (%s): %s", uid, exc)
        return True
    if not anlik.exists:
        return False
    return (anlik.to_dict() or {}).get(f"{tur}LastSent") == gun


def mark_sent(uid: str, tur: str, gun: str,
              extra: dict[str, Any] | None = None) -> None:
    """Gönderim kaydı. ``extra`` (OT1): daily dalı gönderilen GÖVDEYİ ve
    odak sinyalini de yazar — ertesi günün rotasyonu ve öğle kopya
    koruması bu hafızaya bakar. Tek merge yazımı; ek tur maliyeti yok.
    """
    doc = _notification_doc(uid)
    if doc is None:
        return
    try:
        doc.set({f"{tur}LastSent": gun, **(extra or {}),
                 "updatedAt": dt.datetime.now(dt.timezone.utc)}, merge=True)
    except Exception as exc:
        logger.warning("Gonderim kaydi yazilamadi (%s): %s", uid, exc)


def _body_hash(metin: str) -> str:
    import hashlib
    return hashlib.sha256(metin.encode("utf-8")).hexdigest()[:16]


def daily_sent_fields(gun: str, govde: str, idx: int,
                      sinyal: dict[str, Any], lang: str) -> dict[str, Any]:
    """Sabah gönderiminin `mark_sent(extra=...)` alanları (OT1.1).

    ``dailyBodyLang`` (PBZ-turu): gövde hangi dilde gittiyse o. Etiket
    olmayınca dil değişen günün sabahı dünkü Türkçe cümle İngilizce
    promptun içine `avoid=` olarak giriyordu; öğle kopya koruması da
    başka dildeki sabah gövdesiyle karşılaştırıyordu.
    """
    return {
        "dailyBody": govde[:200],
        "dailyBodyHash": _body_hash(govde),
        "dailyBodyLang": lang,
        "dailyFocusFp": (f"{sinyal.get('transit')}-{sinyal.get('aspect')}"
                         f"-{sinyal.get('natal')}"),
        "dailyFocusIdx": idx,
        "dailyTheme": sinyal.get("theme") or "",
        "dailyBodyDay": gun,
    }


def last_daily_sent(uid: str) -> dict[str, Any] | None:
    """Son gönderilen sabah bildiriminin hafızası; yoksa None (OT1.1).

    Sunucuya kapalı `private/notifications` dokümanından okur — istemci
    bu alanları ne görür ne yazabilir (firestore.rules private/**).
    """
    doc = _notification_doc(uid)
    if doc is None:
        return None
    try:
        anlik = doc.get()
    except Exception as exc:
        logger.warning("Gonderim hafizasi okunamadi (%s): %s", uid, exc)
        return None
    if not anlik.exists:
        return None
    veri = anlik.to_dict() or {}
    if not veri.get("dailyBodyHash"):
        return None
    return {
        "body": veri.get("dailyBody") or "",
        "bodyHash": veri["dailyBodyHash"],
        # Etiketsiz eski kayıt (bu deploy'dan önce yazılmış) "" döner:
        # hash kıyasına girer, gövdesi prompta girmez (`_hash_kiyaslanir`).
        "lang": veri.get("dailyBodyLang") or "",
        "focusFp": veri.get("dailyFocusFp") or "",
        "focusIdx": veri.get("dailyFocusIdx"),
        "theme": veri.get("dailyTheme") or "",
        "day": veri.get("dailyBodyDay") or veri.get("dailyLastSent") or "",
    }


def _hash_kiyaslanir(hafiza: dict[str, Any], lang: str) -> bool:
    """Hafızadaki gövdeyle HASH kıyası yapılır mı (PBZ-turu).

    Etiket bugünkü dilse evet. Etiket YOKSA ("" — bu deploy'dan önce
    yazılmış kayıt) da evet: aksi halde deploy günü eski kayıtlı herkes
    için "dünün/sabahın kopyası asla" koruması sessizce kapanırdı; hash
    aynıysa metin aynıdır, dili bilinmese de. Etiket BAŞKA dilse hayır —
    karşılaştırılacak ortak metin yok.

    Bu yalnız KIYAS kararıdır. Gövdeyi prompta sokmak (`avoid=`) etiketin
    bugünkü dille tam eşitliğini ister: etiketsiz gövde hangi dilde
    bilinmez, İngilizce promptun içine Türkçe cümle girebilirdi.
    """
    return (hafiza.get("lang") or "") in ("", lang)


# ---------------------------------------------------------------------------
# Karar
# ---------------------------------------------------------------------------

#: Tür -> profildeki tercih alanı. `checkin` BİLEREK streak tercihini
#: paylaşır: ikisi de "akşam dürtmesi" ailesinden ve akşam en fazla biri
#: gider — ayrı bir anahtar mobil ayar ekranını büyütürdü. Kullanıcılar
#: ayrı kapatmak isterse `notifyCheckin` o zaman eklenir.
PREF_FIELDS = {
    "daily": "notifyDaily",
    # OB3: öğle slotu "günün okuması" ailesinden — sabahı kapatan kullanıcı
    # öğleni de istemiyordur; ayrı bir anahtar ayar ekranını büyütürdü.
    "midday": "notifyDaily",
    # CV: Çevrem slotu çevredeki insanlarla ilgili — arkadaş bildirimlerini
    # kapatan kullanıcı bunu da istemiyordur. (Bu slot daha önce öğlenin
    # yedek dalıydı ve `notifyDaily`ye bağlıydı; ⚠️ yani arkadaş
    # bildirimlerini kapatıp günlüğü açık bırakan kullanıcı çift ânı
    # bildirimini ESKİDEN ALIYORDU, artık almaz. Doğru taraf bu.)
    "circle": "notifyFriends",
    # K7: geri kazanımın varsayılan sesi gökyüzünden bir ayrıntı — yani
    # sabah bildiriminin ta kendisi. Sabahı kapatan kullanıcı "beni gökyüzü
    # için çağırma" demiştir; ömründe en fazla ÜÇ kez görülecek bir
    # bildirim için ayar ekranına dördüncü anahtar konmaz.
    "winback": "notifyDaily",
    "checkin": "notifyStreak",
    "streak": "notifyStreak",
    "friend": "notifyFriends",
}


def wants(profile: dict[str, Any], tur: str) -> bool:
    """Kullanıcı bu türü açık bırakmış mı? Alan yoksa AÇIK sayılır."""
    alan = PREF_FIELDS.get(tur)
    if alan is None:
        return False
    return profile.get(alan) is not False


def should_send(profile: dict[str, Any], tur: str,
                now_utc: dt.datetime | None = None,
                ignore_target_hour: bool = False,
                ignore_dedupe: bool = False) -> tuple[bool, str]:
    """Zamanlayıcı bu kullanıcıya şimdi göndermeli mi?

    ``(gonderilsin, gerekce)`` döner. Gerekçe loglama ve test içindir;
    "gönderilmedi" kararlarının neden alındığı görünür olmalı.

    ``ignore_target_hour`` ve ``ignore_dedupe`` yalnızca duman testi içindir
    (yayın sonrası "bildirim gerçekten gidiyor mu" kontrolü).

    **Sessiz saat ve tercih HİÇBİR bayrakla atlanmaz.** Bu ikisi kullanıcının
    açık iradesi; elinde zamanlayıcı anahtarı olan biri bile kullanıcıyı gece
    yarısı uyandıramamalı ya da kapattığı bildirimi ona gönderememeli.
    """
    if tur not in SCHEDULED_TYPES:
        return False, "bilinmeyen-tur"
    if not profile.get("fcmToken"):
        return False, "token-yok"
    if not profile.get("onboardingCompleted"):
        return False, "onboarding-tamamlanmamis"
    if not wants(profile, tur):
        return False, "tercih-kapali"

    yerel = local_now(profile, now_utc)
    if not ignore_target_hour and yerel.hour != TARGET_HOURS[tur]:
        return False, "saat-uygun-degil"
    if in_quiet_hours(profile, yerel):
        # Hedef saat sessiz aralığa denk geliyorsa kullanıcının tercihi
        # kazanır; bildirim atlanır.
        return False, "sessiz-saat"

    gun = yerel.date().isoformat()

    # KA4 → CV/K7: akşam penceresinde (yerel 18-20) EN FAZLA BİR bildirim.
    # Eskiden bu kural checkin ⊕ streak için iki elle yazılmış `if`ti;
    # `EVENING_FAMILY` aynı kuralın kümeye çevrilmiş hâli ve gerekçesi
    # orada. Sıra ters de olsa korunur (streak bir şekilde önce gittiyse
    # aynı akşam bir de soru göndermeyiz) — kural simetrik.
    if tur in EVENING_FAMILY:
        for diger in EVENING_FAMILY:
            if diger != tur and already_sent(profile["uid"], diger, gun):
                return False, f"aksam-{diger}-gitti"

    if tur == "streak":
        seri = int(profile.get("streakCount") or 0)
        if seri < MIN_STREAK_FOR_REMINDER:
            return False, "seri-kisa"
        if profile.get("lastSeenDaily") == gun:
            return False, "bugun-zaten-okudu"

    if tur == "winback":
        basamak, gerekce = winback_tier(
            profile, yerel, winback_state(profile["uid"], profile))
        if basamak is None:
            return False, gerekce

    if tur == "circle":
        # Çevrem slotu GERİ KAZANIMA YOL VERİR. İki sebep:
        #
        # 1. 10. basamak AYNI ölçümden besleniyor (`_cevre_govdesi`); ikisi
        #    birden gitse kullanıcı aynı şeyi iki kez okur ve hesap iki kez
        #    yapılır.
        # 2. Üç gündür girmeyen birine içeriğin ÜÇÜNCÜ çeşidi değil geri
        #    çağrı gerekiyor. Sessizlik boyunca Çevrem her gün çalsaydı
        #    (kendi tekrar koruması günde bire izin verir) kademeli
        #    susma kararı (K7) pratikte hiç yaşanmazdı.
        #
        # Akşam ailesi bunu SAĞLAMAZ: circle yerel 18'de, winback 19'da
        # koşuyor; aile kuralı "önce koşan kazanır" demektir ve circle her
        # zaman önce koşar. Bu yüzden kapı burada, SAATTEN bağımsız.
        #
        # Pencere basamak gitmiş olsa da kapalı kalır: fark eşiğin
        # üstündeyse kullanıcı hâlâ "dönmemiş" sayılır.
        fark = son_gorulme_farki(profile, yerel)
        if fark is not None and fark >= WINBACK_TIERS[0]:
            return False, "geri-kazanim-penceresi"

    if not ignore_dedupe and already_sent(profile["uid"], tur, gun):
        return False, "zaten-gonderildi"

    # GÜNLÜK TOPLAM TAVAN — en son kapı. Tekrar korumasından SONRA
    # duruyor ki en anlamlı gerekçe dönsün (`zaten-gonderildi`, tavan
    # dolu olsa bile). Güvenlik sıradan GELMİYOR: okuma kesintisinde
    # kapanan kapı tekrar korumasıdır ve olay yolu tam TERS sırayla aynı
    # güvenceyi veriyor (gerekçe `gunluk_push_sayisi`de, ölçülerek
    # düzeltildi).
    #
    # Duman testi bayrakları bu kapıyı AÇMAZ: `ignore_dedupe` yalnız tür
    # başına korumayı atlar. Tavan dolu bir hesaba panelden test
    # gönderilirse koşu onu atlar ve `test_send` sabit test metnine düşer —
    # operatör yine bir push görür, gerekçesi `skippedReason`da yazılı.
    if gunluk_push_sayisi(profile["uid"], gun) >= GUNLUK_PUSH_TAVANI:
        return False, "gunluk-tavan"

    return True, "gonderilecek"


# ---------------------------------------------------------------------------
# Bildirim metni
#
# Birim ekonomi kuralı burada da geçerli: bildirim metni KULLANICI BAŞINA
# üretilmez. Günlük bildirimin gövdesi (burç, gün, dil) anahtarıyla
# önbelleklenir — 12 burç x 2 dil = günde en fazla 24 LLM çağrısı, kaç
# kullanıcı olursa olsun. Seri ve arkadaş bildirimleri hiç LLM kullanmaz.
# ---------------------------------------------------------------------------

#: Bildirim satırı için üst sınır. Prompt 85 karakter istiyor; model taşarsa
#: kırpmak yerine yedek metne düşeriz (yarım cümle göstermeyiz).
MAX_PUSH_BODY = 110


def daily_push_cache_key(sign: str, gun: str, lang: str) -> str:
    return f"push-daily-{sign}-{gun}-{lang}"


def daily_push_body(sign: str, sky: dict[str, Any], lang: str,
                    gun: str | None = None) -> str:
    """Burç için günün tek satırlık bildirim metni.

    ``sign`` İngilizce burç anahtarıdır ("leo"). ``sky`` çağıran tarafından
    **dile göre yerelleştirilmiş** olarak gelir.
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    gun = gun or dt.date.today().isoformat()
    p = prompts.get(lang)
    sign_adi = p.SIGN_NAMES.get(sign, sign)

    anahtar = daily_push_cache_key(sign, gun, lang)
    onbellekten = cache.get(anahtar)
    if onbellekten is not None:
        return onbellekten

    moon = (sky or {}).get("moon_phase") or {}
    retros = ", ".join((sky or {}).get("retrogrades") or []) or p.NONE_LABEL
    prompt = p.PUSH_DAILY_PROMPT.format(
        sign=sign_adi, today=gun, moon_name=moon.get("name") or "-",
        illumination=moon.get("illumination"), retros=retros,
    )

    metin = (gemini_service.generate(prompt, lang=lang,
                                     feature="push_daily") or "").strip()
    # Model bazen tırnak içinde döndürüyor; bildirimde tırnak görünmemeli.
    metin = metin.strip('"').strip("'").strip()
    if not metin or len(metin) > MAX_PUSH_BODY:
        if metin:
            logger.info("Push satiri cok uzun (%s kar.), yedege dusuldu",
                        len(metin))
        metin = p.PUSH_DAILY_FALLBACK.format(
            sign=sign_adi, date=prompts.signal_date(lang, gun))

    # Yedek metin de önbelleklenir: aksi halde Gemini'nin sorunlu olduğu bir
    # saatte her burç için tekrar tekrar denenirdi.
    cache.set(anahtar, metin, ttl_seconds=36 * 3600)
    return metin


def _bundle_body(paket: dict[str, Any] | None, idx: int,
                 yerel: list[dict[str, Any]], lang: str,
                 uid: str = "") -> str:
    """idx'inci sinyalin gövdesi: paket cümlesi; yoksa, taşarsa ya da DİLİ
    UYMAZSA teknik satır.

    Boş dize dönerse o sinyalden gövde çıkmadı demektir (teknik satır da
    taşmış) — çağıran başka sinyale bakar ya da None döner.

    DM-turu (cihaz bulgusu "hem İngilizce hem Türkçe push"): paket cümlesi
    LLM'den gelir ve LLM'in dili SÖZ değildir. Muhafız deterministik ve
    BURADA: sabah (`signal_push`, yeniden üretim yolu dahil) ve öğle
    (`midday_push`) paket cümlesini yalnız bu fonksiyondan okur; tek nokta
    ikisini de kapatır. Teknik satır şablondur, dili kesindir — ona düşmek
    güvenli. ``uid`` yalnız log içindir.
    """
    govde = ""
    if paket and len(paket.get("insights") or []) > idx:
        govde = paket["insights"][idx]
        if not 0 < len(govde) <= prompts.get(lang).SIGNAL_INSIGHT_MAX:
            govde = ""
        elif i18n.language_conflicts(govde, lang):
            logger.warning(
                "Bildirim gövdesi dili uyuşmuyor: uid=%s lang=%s tahmin=%s "
                "— teknik satıra düşüldü",
                uid, lang, i18n.guess_language(govde))
            govde = ""
    if not govde:
        govde = yerel[idx]["technical"]
        if not 0 < len(govde) <= MAX_PUSH_BODY:
            return ""
    return govde


def signal_push(profile: dict[str, Any], lang: str,
                today: dt.date | None = None,
                onceki: dict[str, Any] | None = None
                ) -> tuple[str, str, str, int, dict[str, Any]] | None:
    """Sabah bildirimi — TEMA ÇARKLI odak sinyalinden (R2-S4 → OT-turu).

    ``(başlık, gövde, parmak_izi, idx, hafıza_alanları)`` döner. Gövde uç
    ile AYNI paylaşılan paketten; günde toplam bir LLM çağrısı korunur.

    OT-turu (cihaz bulgusu "dünkü bildirimle aynıydı"): odak artık hep
    0 değil — bugün kesinleşen varsa o, yoksa dünkü temadan SONRAKİ tema
    (`daily_focus_index`, kullanıcı kararı: "bir gün ilişki, bir gün
    mali, bir gün iç dünya"). Gövde dünkü gövdeyle AYNI çıkarsa: önce
    farklı sinyal denenir (bedava), sonra TEK yeniden üretim (dünkü
    cümle negatif örnek), o da tutmazsa geri sayımlı teknik satır —
    hiçbir yolda dünkü metnin kopyası gönderilmez.

    PBZ-turu: aynılık koruması dünkü gövde BAŞKA dilde gittiyse çalışmaz.
    Dil değişen sabah dünkü hafıza başka dildedir — hash'i karşılaştırmak
    anlamsız, gövdesini `avoid=` ile prompta sokmak ise Türkçe cümleyi
    İngilizce promptun içine koymak demek (prompts/en.py'nin kendi
    uyarısı). Etiketsiz eski kayıt (bu deploy'dan önce yazılmış) hash
    kıyasına GİRER — deploy günü koruma kapanmaz — ama gövdesi `avoid=`
    ile prompta girmez (`_hash_kiyaslanir`). Tema çarkı dilden
    bağımsızdır, o hep dünü okur.

    Üretilemezse None döner ve çağıran paylaşımlı burç satırına düşer;
    bildirim ASLA atlanmaz.
    """
    try:
        from services import signal_service
        ham = signal_service.cached_signals(profile, today=today)
        if not ham or not ham.get("signals"):
            return None
        gun = (today or dt.date.today()).isoformat()

        dun = onceki if (onceki and onceki.get("day") != gun) else None
        # Hash kıyası: aynı dil YA DA etiketsiz eski kayıt. `avoid=` ise
        # yalnız etiket bugünkü dille TAM eşitse (etiketsiz gövdenin dili
        # bilinmez; prompta girmez).
        hash_kiyaslanir = dun is not None and _hash_kiyaslanir(dun, lang)
        ayni_dil = dun is not None and dun.get("lang") == lang
        idx = signal_service.daily_focus_index(
            ham,
            prev_theme=(dun or {}).get("theme") or None,
            prev_fp=(dun or {}).get("focusFp") or None)

        uid = profile.get("uid") or ""
        paket = signal_service.cached_insight_bundle(ham, lang)
        yerel = prompts.localize_signals(lang, ham)["signals"]
        # DM-turu: dil muhafızı `_bundle_body` içinde — aşağıdaki her
        # gövde adayı (ilk seçim, farklı sinyal, yeniden üretim) oradan
        # geçer; teknik satırın kendisi şablon olduğu için burada ayrıca
        # kontrol yoktur.
        govde = _bundle_body(paket, idx, yerel, lang, uid=uid)

        # Dünle aynılık koruması (OT1.3) — sınırlı: 1 ek LLM çağrısı.
        # Başka dildeki dünkü gövdeyle kıyas yok: ortak metin yok.
        if (govde and hash_kiyaslanir
                and _body_hash(govde) == dun.get("bodyHash")):
            for aday in range(len(yerel)):
                if aday == idx:
                    continue
                aday_govde = _bundle_body(paket, aday, yerel, lang, uid=uid)
                if aday_govde and _body_hash(aday_govde) != dun["bodyHash"]:
                    idx, govde = aday, aday_govde
                    break
            else:
                # Dünkü cümle negatif örnek olarak YALNIZ aynı dilde girer.
                yeni = signal_service.insight_bundle(
                    ham, lang,
                    avoid=(dun.get("body") or "") if ayni_dil else "")
                if yeni:
                    cache.set(
                        signal_service.bundle_key(
                            signal_service.signals_fingerprint(ham), lang),
                        yeni, ttl_seconds=signal_service.BUNDLE_TTL_OK)
                    aday_govde = _bundle_body(yeni, idx, yerel, lang, uid=uid)
                    if aday_govde and _body_hash(aday_govde) != dun["bodyHash"]:
                        govde = aday_govde
                if _body_hash(govde) == dun["bodyHash"]:
                    govde = yerel[idx]["technical"]
                    if (not 0 < len(govde) <= MAX_PUSH_BODY
                            or _body_hash(govde) == dun["bodyHash"]):
                        return None
        if not govde:
            return None

        sinyal = yerel[idx]
        p = prompts.get(lang)
        iz = signal_service.signals_fingerprint(ham)
        extra = daily_sent_fields(gun, govde, idx,
                                  (ham.get("signals") or [])[idx], lang)
        return (p.PUSH_SIGNAL_TITLE.format(
                    emoji=prompts.theme_emoji(sinyal.get("theme")),
                    theme=sinyal["theme_local"]),
                govde, iz, idx, extra)
    except Exception as exc:
        logger.warning("Sinyal bildirimi uretilemedi (%s): %s",
                       profile.get("uid"), exc)
        return None


@dataclass(frozen=True)
class PushIcerik:
    """Bir bildirimin metni + gövdesinin BİÇİMİ.

    ``soru`` bu turun (SS) çekirdek ayrımı. Kullanıcının koyduğu kural
    bildirimin TÜRÜYLE değil gövdesinin biçimiyle ilgili: gövde bir
    SORUysa Rytho sohbette önce yazar ve kullanıcı cevaplar; İFADEyse
    dokunuş bugünkü gibi kullanıcının sorusunu ön-doldurur.

    Kararı ÜRETİCİ verir, çağıran değil. `notify.py` yalnız bu bayrağa
    bakar; hiçbir yerde `if type == "checkin"` yazmaz. Yeni bir soru
    biçimli bildirim eklemek tek satır: `soru=True`.

    ``ozel_ad`` metnin içine KONMUŞ karşı taraf adıdır ve yalnız koşunun
    dil ağının ölçümünden çıkarılması için taşınır (`ozel_ad_haric`).
    Burada duruyor çünkü onu bilen tek yer üretici: koşu metinden ya da
    yükten adı geri çıkaramaz. Boş varsayılan, ad taşımayan üreticilerin
    (`checkin_push`) davranışını birebir aynı bırakıyor.
    """

    baslik: str
    govde: str
    soru: bool = False
    ozel_ad: str = ""


def _bundle_in_other_language(fp: str, lang: str) -> bool:
    """Bugünün paketi ``lang`` DIŞINDA bir dilde SORULU üretilmiş mi?

    Yalnız önbellek okur. Kayıt yorum taşıyorsa o sabah push gitmiştir;
    ama akşam üretiminin tek anlamı SORU: `checkin_question` odak
    sinyaline bağlıdır (`significant_signal` — determinist, dilden
    bağımsız). Diğer dildeki paket sorusuzsa (önemli sinyal yok) yeni
    dilde üretilecek paket de sorusuz çıkar; LLM boşa yanardı. Ölçüt bu
    yüzden `insights` değil `checkin_question`.
    """
    from services import signal_service
    for diger in i18n.SUPPORTED:
        if diger == lang:
            continue
        kayit = cache.get(signal_service.bundle_key(fp, diger))
        if (kayit and not kayit.get("failed")
                and kayit.get("checkin_question")):
            return True
    return False


def checkin_push(profile: dict[str, Any], lang: str,
                 today: dt.date | None = None) -> PushIcerik | None:
    """Akşam check-in sorusu (KA4) — YALNIZ önbellekten, LLM yakmaz.

    Soru sabahki toplu üretimin son satırıdır; akşam işi yalnız okur
    (`generate_if_missing=False`). Paket yoksa ya da o gün "önemli
    sinyal" çıkmadıysa None döner — çağıran kullanıcıyı atlar ve :10'daki
    seri hatırlatması normal davranır.

    Tek istisna (PBZ-turu, dil değişen gün): paket bugünkü dilde yok ama
    BAŞKA desteklenen dilde var — yani sabah bu kullanıcıya o dilde push
    gitti, sonra dil değişti. Eskiden akşam "soru-yok" ile sessizce
    düşüyordu. Şimdi yeni dilde BİR KEZ üretilir; `cached_insight_bundle`
    önbelleğe yazdığı için aynı günün ikinci koşusu yeniden üretmez.
    Hiçbir dilde paket yoksa eskisi gibi: LLM yakılmaz, None.

    ``soru=True`` döner: gövde `checkin_question` alanından geliyor, yani
    tanım gereği bir sorudur.
    """
    try:
        from services import signal_service
        ham = signal_service.cached_signals(profile, today=today)
        if not ham or not ham.get("signals"):
            return None
        paket = signal_service.cached_insight_bundle(
            ham, lang, generate_if_missing=False)
        if paket is None and _bundle_in_other_language(
                signal_service.signals_fingerprint(ham), lang):
            paket = signal_service.cached_insight_bundle(
                ham, lang, generate_if_missing=True)
        soru = (paket or {}).get("checkin_question")
        if not soru:
            return None
        # DM-turu: soru da LLM çıktısı, dili söz değil. Yanlış dildeyse
        # akşam sorusu ATLANIR — bu bildirim isteğe bağlı, :10'daki seri
        # hatırlatması devreye girer; sohbete yanlış dilde tohum da
        # atılmamış olur. Yedek metin yok: soru biçimli şablon uydurmayız.
        if i18n.language_conflicts(soru, lang):
            logger.warning(
                "Check-in sorusu dili uyuşmuyor: uid=%s lang=%s tahmin=%s "
                "— akşam sorusu atlandı",
                profile.get("uid"), lang, i18n.guess_language(soru))
            return None
        return PushIcerik(prompts.get(lang).PUSH_CHECKIN_TITLE, soru,
                          soru=True)
    except Exception as exc:
        logger.warning("Check-in bildirimi uretilemedi (%s): %s",
                       profile.get("uid"), exc)
        return None


def midday_push(profile: dict[str, Any], lang: str,
                today: dt.date | None = None
                ) -> tuple[tuple[str, str, dict[str, str]] | None, str]:
    """Öğle ölçülü slotu (OB3 → OT1.2) — yalnız gerçekten olay varsa, LLM'siz.

    ``(yük, gerekçe)`` döner; yük None ise gerekçe "olay-yok" ya da
    "sabahla-ayni" — öğle bildirimi bir HAK değil, ölçülmüş bir olayın
    haberi ve SABAH GÖNDERİLENİN KOPYASI ASLA DEĞİL (canlıda yakalanan
    açık: bugün kesinleşen sinyal çoğunlukla sabahın odağıydı ve 13:00
    gövdesi 09:00'unkiyle bayt-aynı çıkıyordu).

    TEK KAYNAK: kullanıcının **kendi haritasında BUGÜN kesinleşen açı**
    (``days_to_exact == 0``, sabahki paylaşımlı sinyal önbelleği). Gövde
    sabah paketindeki indeks-hizalı AI cümlesi (yalnız okunur — öğle LLM
    yakmaz), yoksa dürüst teknik satır. Sabah gövdesiyle aynı çıkarsa
    aynı paketten farklı bir sinyal denenir; hiçbiri olmazsa
    (None, gerekçe).

    CV-turu: buranın ikinci bir dalı vardı — çift ânı — ve pratikte ÖLÜYDÜ.
    İki sebeple: (1) YEDEK daldı, yani kullanıcının kendi haritasında
    bugün kesinleşen bir açı varsa hiç koşmuyordu; (2) `pair_transits_cached`
    asla hesaplamıyor, yani kullanıcı o gün ilişki ekranını KENDİ
    açmadıysa önbellek boştu. Kısır döngü: bildirimle geri getirmek
    istediğin kullanıcı, bildirimin ön şartını yerine getirmemiş olandır.
    Artık kendi slotu var (`circle_push`, yerel 18:00) ve gerekirse günde
    bir hesap yapıyor.
    """
    try:
        from services import profile_service, signal_service

        today = today or dt.date.today()
        gun = today.isoformat()

        # Sabah hafızası (OT1.1): bugün gönderilen gövdenin kopyası yasak.
        # PBZ-turu: sabah gövdesi BAŞKA dilde gittiyse (dil öğlene kadar
        # değişti) karşılaştırılacak ortak metin yok; etiketsiz eski kayıt
        # yine kıyaslanır (`_hash_kiyaslanir`).
        uid = profile.get("uid") or ""
        dun = last_daily_sent(uid)
        sabah_hash = (dun or {}).get("bodyHash") \
            if ((dun or {}).get("day") == gun
                and _hash_kiyaslanir(dun or {}, lang)) else None
        sabahla_ayni = False

        # --- a) kendi haritasında bugün kesinleşen ---
        ham = signal_service.cached_signals(profile, today=today)
        sinyaller = (ham or {}).get("signals") or []
        bugunku = [i for i, s in enumerate(sinyaller)
                   if s.get("exact_on") and s.get("days_to_exact") == 0]
        if ham and bugunku:
            p = prompts.get(lang)
            yereller = prompts.localize_signals(lang, ham)["signals"]
            paket = signal_service.cached_insight_bundle(
                ham, lang, generate_if_missing=False)
            # Bugün kesinleşenler önce; hepsi sabahın kopyasıysa diğer
            # sinyaller de denenir (paket zaten elimizde, sıfır maliyet).
            for idx in bugunku + [i for i in range(len(sinyaller))
                                  if i not in bugunku]:
                # DM-turu: dil muhafızı `_bundle_body` içinde (sabahla ortak).
                govde = _bundle_body(paket, idx, yereller, lang, uid=uid)
                if not govde:
                    continue
                if sabah_hash and _body_hash(govde) == sabah_hash:
                    sabahla_ayni = True
                    continue
                yerel = yereller[idx]
                baslik = p.PUSH_MIDDAY_TITLE.format(
                    emoji=prompts.theme_emoji(yerel.get("theme")),
                    theme=yerel["theme_local"])
                veri = {"type": "daily", "route": "signal",
                        "fp": signal_service.signals_fingerprint(ham),
                        "idx": str(idx), "d": gun, "src": "midday"}
                sign = profile_service.sun_sign_key(profile)
                if sign:
                    veri["sign"] = sign
                return (baslik, govde, veri), "gonderilecek"

        return None, ("sabahla-ayni" if sabahla_ayni else "olay-yok")
    except Exception as exc:
        logger.warning("Ogle bildirimi uretilemedi (%s): %s",
                       profile.get("uid"), exc)
        return None, "olay-yok"


# ---------------------------------------------------------------------------
# Çevrem slotu (CV) ve geri kazanım gövdesi — PAYLAŞILAN çift ölçümü
# ---------------------------------------------------------------------------

def _cift_adaylari(uid: str, lang: str) -> list[tuple[Any, dict[str, str]]]:
    """(karşı taraf, FCM yükündeki hedef kimliği) çiftleri.

    Kimlik yükte TAŞINMAK ZORUNDA (BY-turu): dokununca O ilişkinin ekranı
    açılsın diye. Kimliksiz yük istemciyi yalnız Çevrem sekmesine
    bırakıyordu ("sadece uygulama açılıyor" cihaz bulgusu).
    """
    from services import circle_context, people_service, synastry_service

    adaylar: list[tuple[Any, dict[str, str]]] = []
    for friend_uid in circle_context.list_accepted_friend_uids(uid):
        cp = synastry_service.friend_counterpart(uid, friend_uid)
        if cp is not None:
            adaylar.append((cp, {"fromUid": friend_uid}))
    for kayit in people_service.list_people(uid):
        cp = synastry_service.person_counterpart(uid, kayit["id"], lang=lang)
        if cp is not None:
            adaylar.append((cp, {"pid": kayit["id"]}))
    return adaylar


def _en_iyi_vurus(uid: str, adaylar: list[tuple[Any, dict[str, str]]],
                  today: dt.date, hesapla: bool
                  ) -> tuple[tuple[Any, dict[str, str], dict[str, Any]] | None,
                             bool | None]:
    """Bugünün en anlamlı çift vuruşu.

    `((cp, kimlik, vuruş) | None, ölçüldü)` döner.

    İKİ AŞAMA ve sıra bilinçli:

    1. **Bedava tarama.** Her aday `pair_transits_cached` ile okunur (asla
       hesaplamaz). Burada bir kayıt bulunursa o çift, kullanıcının o gün
       ilişki ekranını KENDİ açtığı çifttir: hem sıfır maliyetli hem de
       ilgisi kanıtlı. Eski davranış yalnız bu aşamaydı.
    2. **Günde TEK hesap.** Hiçbir adayın kaydı yoksa bir aday hesaplanır.
       Aday GÜNDEN türetilir (`gün ordinali % aday sayısı`), yani her gün
       başkası yüzeye çıkar — bugün eşin, yarın kardeşin. Sabit indeks
       seçilseydi aynı kişi haftalarca tekrarlanırdı.

    ``ölçüldü`` üç değerli: True = ölçüm elde edilebildi (vuruş çıkmasa
    da — sakin bir gün kusur değildir), False = elde edilemedi (profil
    okunamadı / doğum verisi yok / istisna), None = aday yok, yani
    ölçülecek bir şey yoktu. Bu ayrım `RunResult.generation` dökümünü
    besliyor: "olay yok" ile "ölçemedim" aynı kovaya girerse sakin bir gün
    sahte alarm üretirdi.

    ⚠️ MALİYET (ölçüldü 2026-10-02, bu makine, ısınmış süreç):
    `astro_service.get_transits` ≈ **2 ms** (çift başına iki taraf = 2
    çağrı) ve ilk kez için `get_synastry` ≈ **3 ms** (eksenler 30 gün
    önbellekli). Yani kullanıcı başına GÜNDE ~7 ms CPU + ~2 Firestore
    okuması; LLM çağrısı YOK, para maliyeti sıfır. Soğuk süreçte ilk
    efemeris çağrısı 528 ms'dir ve koşuda BİR KEZ ödenir.
    ⚠️ ÖLÇEK SINIRI: hesap O(kullanıcı). 18 profilde ~0,13 s; 10 000
    profilde ~70 s CPU eder ve Cloud Run isteği `deploy-backend.ps1`
    tarafından `--timeout 300` ile öldürülüyor. O mertebeye yaklaşıldığında
    bu koşu bölünmek zorunda (örn. uid aralığına göre birden çok iş).
    Eşik geldiğinde yeniden ÖLÇÜLÜP karar verilsin; tahminle büyütülmesin.
    """
    from services import chart_context, synastry_service

    def _sira(v: dict[str, Any]) -> tuple[int, float]:
        return (0 if chart_context.is_slow_mover(v.get("transit")) else 1,
                float(v.get("orb") or 99.0))

    if not adaylar:
        return None, None

    en_iyi: tuple[Any, dict[str, str], dict[str, Any]] | None = None
    olctu = False
    for cp, kimlik in adaylar:
        kayit = synastry_service.pair_transits_cached(uid, cp, today=today)
        if kayit is None:
            continue
        olctu = True
        vuruslar = kayit.get("hits") or []
        if not vuruslar:
            continue
        v = vuruslar[0]  # zaten yavaş-önce + dar-orb sıralı
        if en_iyi is None or _sira(v) < _sira(en_iyi[2]):
            en_iyi = (cp, kimlik, v)

    if en_iyi is not None or not hesapla:
        return en_iyi, olctu

    cp, kimlik = adaylar[today.toordinal() % len(adaylar)]
    kayit = synastry_service.pair_transits(uid, cp, today=today)
    if kayit is None:
        return None, olctu
    vuruslar = kayit.get("hits") or []
    return ((cp, kimlik, vuruslar[0]) if vuruslar else None), True


def ozel_ad_haric(metin: str, ad: str) -> str:
    """Dil ÖLÇÜMÜ için metni özel addan arındırır — gönderilen metni DEĞİL.

    NEDEN var (ölçüldü 2026-10-03): ÖZEL AD DİL TAŞIMAZ, ama
    `i18n.guess_language` harf tabanlı karar veriyor ve karşı tarafın
    görünen adındaki tek bir Türkçe harf bütün cümlenin dilini
    belirliyordu. Ölçüm: `lang="en"` profiline giden Çevrem başlığı
    ``"🔭 Today: you and Şeyma"`` → ``guess_language`` **"mixed"** →
    `language_conflicts(..., "en")` **True** → koşunun ortak dil ağı
    push'u TAMAMEN düşürüyordu. Aynı şey gövdede de oluyordu
    (``"for Şeyma: mars → venus Trine …"`` → "tr"). Sonuç: İngilizce
    kullanan birinin Türkçe adlı bir arkadaşı/eklenen kişisi varsa o
    ilişki hakkındaki bildirim o kullanıcıya **HİÇ** ulaşmıyordu — her
    gün, sessizce, yalnız `atlanan["dil-uyusmaz"]` sayacında.

    Ağ KALDIRILMADI, yalnız ÖLÇTÜĞÜ metin arındırıldı: kaçak gövde
    (LLM/paket metni) hâlâ yakalanıyor, çünkü oradaki dil işareti addan
    değil cümlenin kendisinden geliyor. Adı çıkarmak gerçek bir kaçağı
    maskeleyemez: Türkçe işareti YALNIZ özel addan gelen bir metni
    "Türkçe" saymak zaten yanlış hükümdü.

    ⚠️ Eşleşme SÖZCÜK SINIRINDA (``\\b``): bu depoda alt dize eşleşmesi
    iki kez yanlış pozitif üretti ("ay" ⊂ "ayrıca"). Ad "Ay" olsa bile
    "ayrıca" bozulmaz. Python ``re`` Unicode modunda ``ı ğ ş ç ö ü İ``
    harflerini sözcük karakteri sayar, yani sınır Türkçe adlarda da
    doğru çalışır. Ad ``re.escape`` ile veriliyor: görünen ad kullanıcı
    girdisi, içinde düzenli ifade metakarakteri olabilir.

    Boş ad metni DEĞİŞTİRMEZ — çağıranların çoğu ad taşımıyor ve onların
    davranışı birebir aynı kalmalı.
    """
    if not metin or not ad:
        return metin
    return re.sub(r"\b" + re.escape(ad) + r"\b", " ", metin)


def circle_push(profile: dict[str, Any], lang: str,
                today: dt.date | None = None
                ) -> tuple[tuple[str, str, dict[str, str]] | None, str,
                           bool | None, str]:
    """Çevrem slotu (CV) — eklenen kişi/aile ya da arkadaşla bugünün ölçümü.

    `(yük, gerekçe, ölçüldü, karşı_ad)` döner. Dördüncü değer karşı
    tarafın GÖRÜNEN ADIDIR ve yalnız koşunun dil ağının o adı ölçümden
    çıkarması için var (`ozel_ad_haric`) — yüke girmez, push'ta
    taşınmaz. Ad burada döndürülüyor çünkü onu BİLEN tek yer burası:
    koşu `veri` sözlüğünden adı geri çıkaramaz (yükte kimlik var, ad
    yok) ve başlık şablonunu tersine çevirmek kırılgan olurdu.

    Gövde ve yük öğlenin eski yedek
    dalıyla BİREBİR aynı: ölçüm LLM'siz teknik satır, hedef o ilişkinin
    ekranı. Değişen tek şey slotun kendi saatine çıkması ve önbellek
    şartının gevşemesi (`_en_iyi_vurus`).

    `src` yükte **"midday" KALIR** ve bu bilinçli: `src` istemcinin ROTA
    anahtarı (apps/mobile/lib/core/notifications.dart — `case 'midday'`
    ilişki ekranını açar, bilinmeyen değer `default`a düşüp yalnız Çevrem
    sekmesini açar). "circle" yazsaydık bugün KURULU olan istemcilerde
    BY-turunda kapatılan "sadece uygulama açılıyor" kusuru geri gelirdi.
    İstemci yeni adı öğrenmeden önce burası değişemez.

    ⚠️ Kaybın hangi YÜKTE olduğu ölçüldü (notifications.dart
    `resolveNotificationRoute`): istemci `pid` taşıyan yükü `src`e HİÇ
    bakmadan `personRelation`a yönlendiriyor, yani kayıp YALNIZ arkadaş
    yüklerinde (`fromUid`) gerçekleşir. Yine de iki yarım kural
    yazılmıyor: adayların yarısı arkadaş ve `src`i yüke göre değiştirmek
    aynı slotun iki farklı adla gitmesi olurdu.
    """
    try:
        from services import synastry_service

        today = today or dt.date.today()
        uid = profile.get("uid") or ""
        adaylar = _cift_adaylari(uid, lang)
        secim, olctu = _en_iyi_vurus(uid, adaylar, today, hesapla=True)
        if secim is None:
            return (None, ("cevre-yok" if olctu is None else "olay-yok"),
                    olctu, "")
        cp, kimlik, v = secim
        satirlar = synastry_service.pair_transit_lines([v], cp.label, lang)
        if not satirlar or not 0 < len(satirlar[0]) <= MAX_PUSH_BODY:
            return None, "olay-yok", olctu, ""
        p = prompts.get(lang)
        return ((p.PUSH_MIDDAY_PAIR_TITLE.format(name=cp.label),
                 satirlar[0],
                 {"type": "friend", "src": "midday",
                  "d": today.isoformat(), **kimlik}),
                "gonderilecek", True, cp.label)
    except Exception as exc:
        logger.warning("Cevre bildirimi uretilemedi (%s): %s",
                       profile.get("uid"), exc)
        return None, "olay-yok", False, ""


# ---------------------------------------------------------------------------
# Geri kazanım (K7) — üç basamak, üç ton, hepsi SORU
# ---------------------------------------------------------------------------

#: Basamak → dil → {baslik, veri?, yalin}.
#:
#: NEDEN `prompts/` DEĞİL burası: bu tablo basamak kümesinin KENDİSİ.
#: `WINBACK_TIERS` ile aynı dosyada durduğu için metinsiz bir basamak ya da
#: basamaksız bir metin eklenemez — bekçi ikisini BİRDEN sorar. Metinlerin
#: hiçbiri LLM'den gelmiyor: birim maliyet sıfır ve dil KESİN, yani
#: yanlış dilde bir soru sohbete tohumlanamaz (DM-turu).
#:
#: ``veri`` o basamağın ölçülmüş ayrıntısını taşıyan biçim; ``yalin``
#: ayrıntı elde edilemediğinde gidecek, HİÇBİR ŞEY İDDİA ETMEYEN soru.
#: 30. basamakta ``veri`` yok — son çağrı veri değil zaman konuşur.
#:
#: Üç ton bilinçli olarak AYRI. Tek bir "özledik" cümlesi üç kez
#: tekrarlanırsa ikincisinde inandırıcılığını yitirir; üçü de SORU
#: biçiminde (`PushIcerik.soru=True`), yani dokunuş sohbeti o soruyla
#: açar ve cevap hafızaya düşer.
WINBACK_TEXTS: dict[int, dict[str, dict[str, str]]] = {
    # 3. gün — MERAK. Alışkanlık henüz kırılmamışken o güne ÖZGÜ bir
    # ayrıntıyla yakalar. Ayrıntı PAYLAŞILAN gökyüzünden gelir, yani
    # kullanıcı başına hesap yok.
    3: {
        "tr": {
            "baslik": "👀 Hişt, bir baksana",
            "veri": "Bugün gökyüzünde {detay} var. Sende neye denk "
                    "geliyor, bakalım mı?",
            "yalin": "Bugün gökyüzünde ne var, birlikte bakalım mı?",
        },
        "en": {
            "baslik": "👀 Psst, come have a look",
            "veri": "There is {detay} in the sky today. Want to see "
                    "where it lands for you?",
            "yalin": "What is in the sky today? Want to take a look "
                     "together?",
        },
    },
    # 10. gün — KİŞİSEL. Gökyüzü ayrıntısı on gün sonra artık yakalamıyor;
    # çevresindeki biri yakalar. Çevrem slotuyla AYNI ölçümden beslenir.
    10: {
        "tr": {
            "baslik": "🔭 Çevrenden bir not",
            "veri": "{label} ile aranızda bugün {transit} dolaşıyor. "
                    "Bakalım mı?",
            "yalin": "Çevrendekiler nasıl, sorduk mu bugün? Birlikte "
                     "bakalım mı?",
        },
        "en": {
            "baslik": "🔭 A note from your circle",
            "veri": "{transit} is moving between you and {label} today. "
                    "Want a look?",
            "yalin": "How are the people around you doing? Want to take "
                     "a look together?",
        },
    },
    # 30. gün — SON ÇAĞRI. Bundan sonra SUSAR (bkz. `winback_tier`).
    30: {
        "tr": {
            "baslik": "🌙 Son bir soru",
            "yalin": "Uzun zaman oldu, gökyüzü değişti. Bir daha bakmak "
                     "ister misin?",
        },
        "en": {
            "baslik": "🌙 One last question",
            "yalin": "It has been a long while and the sky has moved on. "
                     "Want one more look?",
        },
    },
}


def _gokyuzu_ayrintisi(sky: dict[str, Any] | None) -> str | None:
    """Bugünün gökyüzünden TEK yerelleştirilmiş ayrıntı; yoksa None.

    Ay evresi ilk tercih — her gün var ve her gün değişir; yoksa ilk
    retro. ``sky`` çağıran tarafından `prompts.localize_sky` ile
    yerelleştirilmiş gelir.

    None dönüşü `get_sky_now`un DÜŞTÜĞÜ hâldir (koşuda `ham_sky = {}`) ve
    bugüne dek tamamen sessizdi: gökyüzü servisi yanarken bildirim
    "-" ya da boş bir ayrıntıyla gidebiliyordu. Çağıran bu None'ı
    `generation` dökümüne yazar, yani kesinti durum koduna kadar çıkar.
    """
    moon = ((sky or {}).get("moon_phase") or {}).get("name")
    if moon:
        return str(moon)
    retro = (sky or {}).get("retrogrades") or []
    return str(retro[0]) if retro else None


def _cevre_govdesi(profile: dict[str, Any], lang: str,
                   sablon: dict[str, str],
                   today: dt.date | None) -> tuple[str, bool | None, str]:
    """10. basamağın gövdesi: çevresindeki biriyle bugünün ölçümü.

    `(gövde, ölçüldü, karşı_ad)` döner. Üçüncü değer aşağıdaki dil
    kapısının o adı ölçümden çıkarması için var (`ozel_ad_haric`);
    gövdenin kendisi değişmez.

    Çevrem slotuyla AYNI ölçümden beslenir (`_en_iyi_vurus`) — tek hesap,
    iki yüzey. Aynı gün ikisinin birden gitmesi mümkün değil: `should_send`
    geri kazanım penceresinde Çevrem slotunu susturuyor.
    """
    uid = profile.get("uid") or ""
    adaylar = _cift_adaylari(uid, lang)
    secim, olctu = _en_iyi_vurus(uid, adaylar, today or dt.date.today(),
                                 hesapla=True)
    if secim is None:
        return "", olctu, ""
    cp, _kimlik, v = secim
    return sablon["veri"].format(
        label=cp.label,
        transit=prompts.planet_name(lang, v.get("transit"))), True, cp.label


def winback_push(profile: dict[str, Any], lang: str, basamak: int,
                 sky: dict[str, Any] | None = None,
                 today: dt.date | None = None
                 ) -> tuple[PushIcerik, dict[str, str], bool | None]:
    """Basamağa göre geri kazanım bildirimi — `(içerik, yük, ölçüldü)`.

    **ASLA None dönmez.** Basamak çalmaya karar verildiyse bir SORU gider;
    ayrıntı elde edilemediyse iddia küçülür (``yalin``), bildirim düşmez.
    "Ölçülmeyen söylenmez" kuralı cümlenin İÇERİĞİ içindir, çağrının
    kendisi için değil.

    ``ölçüldü``: True = basamağın veri kaynağı gerçekten vardı; False =
    yoktu ve veri-siz soruya düşüldü (SESSİZ BOZULMA — koşunun
    `generation` dökümüne girer ve tamamı düşerse uç 503 döner); None =
    ölçülecek bir şey yoktu (30. basamak veri kullanmaz; 10. basamakta
    kullanıcının hiç çevresi olmayabilir). Üç değerli olması bilinçli:
    boş döküm "ölçülemedi" demek, "düştü" demek DEĞİL.

    Yükteki ``type=checkin`` istemcinin ROTA anahtarıdır, koşu türünün adı
    değil: `apps/mobile/lib/core/notifications.dart` `case 'checkin'`
    dalı soru yolunu açar (`route=chat_answer` + `cid` varsa Rytho'nun
    mesajı olarak). Gerçek köken ``src=winback`` ile yükte duruyor — bugün
    kurulu istemciler onu yok sayar, davranışları değişmez. Ad yükte
    saklanıyor ki ölçülen şey yanlış adla sunulmasın.
    """
    sablonlar = WINBACK_TEXTS[basamak]
    sablon = sablonlar.get(lang) or sablonlar[i18n.DEFAULT]
    govde = ""
    olctu: bool | None = None
    karsi_ad = ""

    if basamak == WINBACK_TIERS[0]:
        ayrinti = _gokyuzu_ayrintisi(sky)
        olctu = ayrinti is not None
        if ayrinti:
            govde = sablon["veri"].format(detay=ayrinti)
    elif basamak == WINBACK_TIERS[1]:
        govde, olctu, karsi_ad = _cevre_govdesi(profile, lang, sablon, today)

    if govde and (not 0 < len(govde) <= MAX_PUSH_BODY
                  or i18n.language_conflicts(
                      ozel_ad_haric(govde, karsi_ad), lang)):
        # Karşı tarafın ADI başka bir dilin harflerini taşıyabilir
        # ("Şeyma" + lang=en) ve koşudaki ortak dil ağı bütün push'u
        # düşürürdü — geri çağrı o kullanıcıya HİÇ ulaşmazdı. Veri-siz
        # soruya düşmek iddiayı küçültür, bildirimi öldürmez. Uzunluk de
        # aynı kapıdan: uzun bir görünen ad gövdeyi taşırabilir.
        #
        # ⚠️ AD ÖLÇÜMDEN ÇIKIYOR (`ozel_ad_haric`) ve bu YARIM kalmış bir
        # onarımın tamamlanması: yedek dal push'u kurtarıyordu ama
        # `olctu=False` yazdığı için SAHTE bir üretim düşüşü üretiyordu.
        # `_SLOT_KIRMIZI_ESIGI["winback"] = 1` ile birleşince bedeli
        # ölçülebilir: o gün kuyrukta yalnız Türkçe adlı bir arkadaşı
        # olan tek bir İngilizce kullanıcı varsa koşu `ok=0` ile biter ve
        # uç **503** döner — hiçbir şey bozuk olmadığı hâlde Scheduler
        # kırmızı yanar. Artık yalnız GERÇEK dil kaçağı yedeğe düşürüyor.
        logger.info("Geri kazanim govdesi dusuruldu (uid=%s basamak=%s "
                    "lang=%s uzunluk=%d) — yalın soruya düşüldü",
                    profile.get("uid"), basamak, lang, len(govde))
        govde = ""
        olctu = False
        # ⚠️ Bu satır EMNİYET PAYI, yük taşıyan şey DEĞİL — ölçüldü
        # (mutasyon D4-M10): düşürüldüğünde takım yeşil kalıyor, çünkü bir
        # altındaki `if not govde:` dalı `karsi_ad`ı ZATEN sıfırlıyor ve
        # `govde` burada "" yapıldığı için o dal her halde koşuyor. İkisi
        # KARŞILIKLI yedek; biri tek başına yeter. Bu terimi yakalayan bir
        # bekçi YAZILAMAZ (aynı durum `winback_state`in `not capa`
        # teriminde de ölçüldü) — "bekçisi yok" eksiklik değil,
        # eşdeğerliğin sonucu. Gerekçesi yanlış okunmasın diye yazılı
        # duruyor: burayı silen biri davranış değiştirmediğini BİLEREK
        # silsin.
        karsi_ad = ""
    if not govde:
        govde = sablon["yalin"]
        karsi_ad = ""

    gun = (today or dt.date.today()).isoformat()
    return (PushIcerik(sablon["baslik"], govde, soru=True,
                       ozel_ad=karsi_ad),
            {"type": "checkin", "route": "chat", "q": govde, "q_date": gun,
             "src": "winback", "tier": str(basamak)},
            olctu)


def streak_push(profile: dict[str, Any], lang: str) -> tuple[str, str]:
    """Seri hatırlatması — şablon, LLM yok."""
    p = prompts.get(lang)
    seri = int(profile.get("streakCount") or 0)
    return p.PUSH_STREAK_TITLE.format(days=seri), p.PUSH_STREAK_BODY


def friend_push(name: str, emoji: str, label: str,
                lang: str) -> tuple[str, str]:
    """Arkadaş tepkisi — şablon, LLM yok."""
    p = prompts.get(lang)
    return (p.PUSH_FRIEND_TITLE.format(name=name),
            p.PUSH_FRIEND_BODY.format(emoji=emoji, label=label))


def profile_language(profile: dict[str, Any]) -> str:
    """Profildeki dil; yoksa varsayılan.

    Bildirim sunucuda üretildiği için istemcinin ``Accept-Language`` başlığı
    burada yoktur — dil profile yazılır (bkz. apps/mobile/lib/core/locale.dart).
    """
    kod = (profile.get("language") or "").strip().lower()
    return kod if kod in i18n.SUPPORTED else i18n.DEFAULT


def can_send_event(profile: dict[str, Any], tur: str,
                   now_utc: dt.datetime | None = None) -> tuple[bool, str]:
    """Olay tabanlı bildirim (arkadaş tepkisi) gönderilebilir mi?

    Zamanlayıcıdan farkı: hedef saat yoktur, olay ne zaman olduysa o zaman
    gider. Ama sessiz saat yine de geçerlidir — bir arkadaşın tepkisi gece
    3'te telefonu titretmeye yetmez. Sessiz saatte bildirim DÜŞÜRÜLÜR,
    ertelenmez; tepki uygulama içindeki kutuda zaten görünüyor.

    GÜNLÜK TOPLAM TAVAN burada da geçerli. Bu yol bugüne dek HİÇBİR sayaca
    tabi değildi: ölçüldü (bu depo, 2026-10-02) — `/notify/reaction` tekrar
    koruması bile taşımıyordu, yani tek bir arkadaş aynı gün sınırsız push
    attırabiliyordu. Tavanın tek başına yetmediği de doğru: çağıran uç
    ayrıca ÇİFT BAŞINA günlük koruma uyguluyor (`already_sent`), yoksa tek
    kişi herkesin bütçesini bitirebilirdi.
    """
    if not profile.get("fcmToken"):
        return False, "token-yok"
    if not wants(profile, tur):
        return False, "tercih-kapali"
    yerel = local_now(profile, now_utc)
    if in_quiet_hours(profile, yerel):
        return False, "sessiz-saat"
    if gunluk_push_sayisi(profile.get("uid") or "",
                          yerel.date().isoformat()) >= GUNLUK_PUSH_TAVANI:
        return False, "gunluk-tavan"
    return True, "gonderilecek"

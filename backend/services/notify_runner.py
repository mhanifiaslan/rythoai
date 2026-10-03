"""Toplu bildirim koşusu (AD8) — `api/notify.run` gövdesi servis oldu.

Neden taşındı: panel iki yeni araç istiyor — "prova" (kime gidecekti,
gönderme) ve "kendime test gönder" (yalnız çağıranın uid'i, iz bırakmadan).
İkisi de zamanlayıcı koşusunun AYNI mantığıdır; uç gövdesinde kalsaydı ya
kopyalanır ya da HTTP katmanı servisten çağrılırdı. Uç ince sarmalayıcı
oldu (zamanlayıcı sırrı + aynı yanıt), mantık burada.

Sözleşme (`run_batch`):

- ``dry_run``: hesaplanır, GÖNDERİLMEZ, hiçbir kayıt yazılmaz.
- ``force``: yalnız hedef saat kontrolünü atlar.
- ``ignore_dedupe``: yalnız tekrar korumasını atlar (force ile).
- ``only_uid``: tek profil (taramasız — `users/{uid}` doğrudan okunur);
  onboarding süzgeci uygulanmaz, jeton-sahibi kıyası tek profilde anlamsız.
- ``mark``: False ise gönderim kaydı (mark_sent), koşu kaydı (notifyRuns)
  ve sohbet tohumu YAZILMAZ — test gönderimi panel sayılarını şişirmez.

**Sessiz saat ve kullanıcı tercihi hiçbir bayrakla atlanmaz.**

TAM DÜŞÜŞ (SZ-turu): koşu her şeyi kaybettiğinde `status` artık "ok"
kalmıyor, gerekçe adını alıyor (`_DUSUS_DURUMLARI`) ve uç onu 503'e
çeviriyor. Gerekçe ölçüldü: Gemini 403'ü BİR AY boyunca hiçbir yerde
kırmızı görünmedi, çünkü üretim düşünce bildirim şablon satıra düşüp
normal gidiyor — `sent` sağlıklı, durum kodu 200, Scheduler günlüğü
yeşil. Servis yalnız KARAR VERİR, fırlatmaz: panelin prova/test araçları
aynı sayıları okuyup operatöre gösterir.
"""
from __future__ import annotations

import datetime as dt
import logging
from typing import Any

from pydantic import BaseModel, Field

from core import cache
from core import firestore as firestore_client
from core import i18n
from services import (
    chat_history,
    notification_service,
    profile_service,
    prompts,
    push_service,
    signal_service,
)
from services.sky_service import get_sky_now

logger = logging.getLogger(__name__)

#: Kullanıcı taramasında tek seferde okunacak doküman sayısı. Tüm koleksiyonu
#: belleğe almak, kullanıcı sayısı büyüdüğünde instance'ı düşürürdü.
PAGE_SIZE = 500

#: Toplu koşunun türleri — api/notify.run Literal'i ile AYNI küme olmak
#: zorunda (uç bu listeyi değil kendi Literal'ini doğruluyor).
#:
#: ⚠️ Aynı küme depoda BEŞ yerde daha yaşıyordu ve bu tür eklendiğinde
#: dördü dörtte kalmıştı. Gerekçe ölçülerek GÜNCELLENDİ (2026-10-03) —
#: eskiden burada "panel ve istatistik tarafı bu kümeyi KENDİ
#: listelerinde tutuyor" yazıyordu ve bu artık YANLIŞ:
#:
#: - `services/admin_service.py` ve `services/stats_service.py` kümeyi
#:   artık ELLE tutmuyor, `_notify_turleri()` ile buradan TÜRETİYOR.
#: - `api/admin.py` `_NotifyType` elle yazılı kalmak ZORUNDA (`Literal`
#:   statik olmalı — FastAPI OpenAPI enum'unu tipten üretir), ama
#:   `tests/test_notify_turleri_tek_kaynak.py` ile bu kümeye çivili.
#: - Elle kalan ve ÇİVİSİZ tek kopya `web/rytho-admin/gorunumler/
#:   bildirimler.js` içindeki `TURLER` dizisi; bugün hâlâ dört tür
#:   taşıyor. Ölçülen iki sonuç (bu dosya o paketin değil, onarım orada
#:   yapılır): prova ve "kendine test" açılır listeleri `TURLER`den
#:   üretildiği için iki yeni slot panelden TETİKLENEMİYOR, ve koşu
#:   tablosundaki rozet `turAdi` sözlüğünde karşılık bulamayıp ham
#:   anahtarı ("circle") okunur etiket yerine gösteriyor.
#:   Koşunun kendisi etkilenmez: sayıları `notifyRuns/{gün}-{tür}`
#:   dokümanına yazar ve tamamen düştüğünde Scheduler günlüğünde 503
#:   ile kırmızı yanar.
RUN_TYPES = ("daily", "midday", "circle", "winback", "checkin", "streak")

#: Jetonsuz hesaba test isteği — uç 400'e çevirir.
NO_TOKEN_MESSAGE = "Bu hesabın push jetonu yok — mobilde bu hesapla giriş yap."

#: Bir koşuyu TAMAMEN DÜŞMÜŞ saymak için gereken en az deneme sayısı (SZ-turu).
#:
#: NEDEN eşik var: tek bir kullanıcının verisi bozuk olabilir (profilinde
#: eksik alan, biçimi tutmayan bir LLM yanıtı) ve o tek kullanıcı yüzünden
#: bütün koşuyu kırmızı yapmak YANLIŞ ALARM üretir. Yanlış alarmın bedeli
#: teorik değil, bu kusurun KÖKÜ: Gemini 403'ü bir ay boyunca YEŞİL bir
#: Scheduler günlüğünde saklandı — her saat kırmızı yanan bir iş de aynı
#: sonucu verir, çünkü okunmaz hâle gelir.
#:
#: NEDEN 3: tek denemede "hepsi düştü" ile "o tek profil bozuk" AYNI
#: gözlemdir — ayırt edilemeyen şeyden alarm üretilmez. Üçüncü denemeyle
#: ayrışır: aynı dakikada üç ayrı profilin birden bozulması, PAYLAŞILAN
#: bağımlılığın (sağlayıcı anahtarı, kota, FCM kimliği) düşmesinden daha
#: az olasıdır.
#:
#: SAYI ÖLÇÜLDÜ, varsayılmadı (Cloud Run günlüğü, 2026-09-29 → 10-02,
#: `type=daily`): zamanlayıcı saatte bir koşuyor ama günün yalnız ÜÇ
#: koşusu bir şey borçlanıyor — 06:05 UTC'de **10**, 04:05'te **5**,
#: 08:05'te **1** kuyruk; kalan 21 saatte kuyruk 0. 18 profil taranıyor,
#: gerisi "saat-uygun-degil". Yani eşik 3, günün iki büyük koşusunun
#: ikisini de kapsıyor: bir sağlayıcı kesintisi AYNI GÜN, ilk 04:05
#: koşusunda kırmızı yanar. 4 ya da 5 seçilseydi 04:05 sınırda kalırdı;
#: 10 seçilseydi yalnız tek koşu bekçili olurdu.
#:
#: BEDELİ (ölçülen, kabul edilmiş): 08:05 koşusunun kuyruğu 1'dir, yani o
#: koşu bu bekçiyle KORUNMAZ. Kayıp değil gecikme — aynı kesinti ertesi
#: 04:05'te yanar ve sayılar her koşuda yanıtta + `notifyRuns`ta durur.
#: ⚠️ Dağılım kullanıcı sayısına bağlı: kuyruklar bu aralığın altına
#: inerse eşik yeniden ÖLÇÜLÜP düşürülmeli, tahminle değiştirilmemeli.
_KIRMIZI_ESIGI = 3

#: SLOT BAŞINA kırmızı eşiği. Eksik slot varsayılana (`_KIRMIZI_ESIGI`)
#: düşer.
#:
#: NEDEN slot başına gerekti (ölçüldü 2026-10-03): yukarıdaki "3" yalnız
#: `daily` için ölçülmüştü (kuyruklar 06:05→10, 04:05→5, 08:05→1) ve o
#: sayı diğer slotlara TAŞINMIYOR. `winback`in bir koşudaki adayı,
#: sessizliği O GÜN 3/10/30. basamağa basan kullanıcılardır: `winback_tier`
#: basamağı bir kez gönderdikten sonra susuyor (`aday <= gonderilen`),
#: yani bir kullanıcı 30 günlük bir sessizlik epizodu boyunca EN FAZLA ÜÇ
#: koşuda kuyruğa giriyor.
#:
#: Gerçek `winback_tier` ile ölçüldü (18 profil, HEPSİ sessiz — yani ÜST
#: SINIR): günlük kuyruk ortalama **0.79**, en çok **2**, ve kuyruğun
#: 3'e ULAŞTIĞI gün oranı **%0**. 12 profille ortalama 0.64, en çok 2.
#: Yani `attempted >= 3` eşiği bu slotta HİÇ dolmuyordu: üretim tamamen
#: düşse bile uç 200 dönüyor ve bu turun dersi ("zamanlanmış işler bir ay
#: yeşil yalan söyledi") yeni slotlar için YARIM kalıyordu. Hiç dolmayan
#: bir eşik, bekçi değil kusurun KORUYUCUSUDUR.
#:
#: BEDELİ (ölçülen, kabul edilmiş): eşik 1'de tek bir bozuk profil koşuyu
#: kırmızı yapar. Üç şey bu bedeli sınırlıyor ve üçü de ölçülü:
#:   1. Kuyruk günlerin yarısında 0'dır (ortalama 0.79) ve `attempted==0`
#:      iken kapı HİÇ çalışmaz ("olay yok düşüş değildir").
#:   2. `winback` günde bir koşar, `daily` gibi saatte bir değil — yani
#:      yanlış alarm okunmaz hâle gelecek sıklıkta yanamaz.
#:   3. Kırmızı ancak `ok == 0` iken yanar; kuyrukta iki kişi varsa ve
#:      biri başarılıysa koşu yeşildir.
#:
#: `circle` varsayılanda (3) bırakıldı ama gerekçesi ÖLÇÜLMEMİŞ bir
#: gerekçeydi ve düzeltildi (2026-10-03): "kapısı son 3 günde görülmüş,
#: yani adayı AKTİF kullanıcılardır ve kuyruğu `daily` ile aynı büyüklük
#: sırasında" yazıyordu. İki yerden yanlış. (1) Kıyas KUYRUĞA değil
#: `generation["attempted"]`a yapılmalı — eşiği okuyan kapı o sayacı
#: okuyor. (2) `circle`ın `attempted` nüfusu `daily`nin ALT KÜMESİ DEĞİL,
#: YAPISAL OLARAK DAHA DARDIR: sayaç yalnız `olctu is not None` iken
#: artıyor ve bu "kullanıcının EN AZ BİR arkadaşı ya da eklenmiş kişisi
#: var" demek (`_cift_adaylari` boş değil) — isteğe bağlı bir sosyal
#: eylem. O oran bu depoda HİÇBİR YERDE ölçülmedi.
#: Sonuç: `circle` için eşik 1'e ÇEKİLMEDİ, çünkü ölçmeden eşik seçmek
#: `winback`te onarılan kusurun aynısını ters yönde üretir (hiç dolmayan
#: eşik yerine her gün yanan eşik) ve "ölçülmeyen söylenmez" kuralını
#: çiğner. Dürüst durum: `circle`ın üretim kapısı ÖLÇÜLMEMİŞ bir eşikle
#: duruyor ve kuyruğu 3'ün altındaysa `winback`teki kusur burada SÜRÜYOR.
#: Kapanması için gereken tek şey ölçüm: bir koşunun `generation`
#: dökümünden `attempted` dağılımı (`notifyRuns/{gün}-circle`).
#: `checkin`/`streak`/
#: `midday` buraya hiç girmiyor çünkü `generation` sayacını HİÇ
#: artırmıyorlar (LLM çağırmıyorlar: biri yazılmış soruyu okuyor, ikisi
#: şablon) — onlarda üretim kapısı tanım gereği sessizdir.
#:
#: ⚠️ Eşikler kullanıcı sayısına bağlı. `winback` kuyruğu yapısal olarak
#: "sessiz kullanıcıların %10'u" (3 basamak / 30 gün); nüfus büyüyünce bu
#: sayı büyür ve eşik yeniden ÖLÇÜLÜP yükseltilmeli, tahminle değil.
_SLOT_KIRMIZI_ESIGI = {
    "winback": 1,
}

#: Eşiği DÜŞÜRÜLEN her slotun, o eşik seçilirken ÖLÇÜLEN kuyruk tavanı.
#:
#: NEDEN gerekti: yukarıdaki "⚠️ eşik yeniden ölçülüp yükseltilmeli"
#: uyarısı DOĞRU ama hiçbir yere BAĞLI DEĞİLDİ — yorumu okuyan kimse
#: olmazsa nüfus büyüdüğünde eşik sessizce yanlışa dönüşür. Bağımsız
#: ölçüm (2026-10-03): `winback` kuyruğu 18 profille en çok **2** (3'e
#: ulaşma %0), 50 profille en çok 5 (%26), 200 profille en çok 20 (%77).
#: Yani eşik 1 BUGÜN doğru, büyüyen nüfusta YANLIŞ ALARM üretir.
#:
#: Kuyruk bu tavanı aştığı an koşu bir UYARI basıyor: kalibrasyon
#: bandının dışına çıkıldı, eşik yeniden ÖLÇÜLMELİ. Tavanı aşmak kusur
#: DEĞİL, kalibrasyonun son kullanma tarihidir — o yüzden uyarı, hata
#: değil ve durum koduna dokunmuyor.
#:
#: ⚠️ Yalnız eşiği DÜŞÜRÜLMÜŞ slotlar burada: tehlike yönü onlarda
#: BÜYÜME (küçük eşik + büyük kuyruk = gürültüye kırmızı yanma).
#: Varsayılan eşikli slotlarda tehlike yönü TERSİ (kuyruk eşiğin altına
#: inerse kapı hiç çalışmaz) ve o ayrı bir ölçüm — ikisini tek kurala
#: sıkıştırmak yanlış gerekçe olurdu.
_OLCULEN_KUYRUK_TAVANI = {
    "winback": 2,
}


def _kalibrasyon_bandi_asildi(type_: str, kuyruk: int) -> int | None:
    """Kuyruk, eşik seçilirken ölçülen tavanı aştı mı — aştıysa o tavan.

    Ölçümü OLMAYAN slot için asla konuşmaz (`None`): ölçülmeyen bir
    tavanı varsaymak "ölçülmeyen söylenmez" kuralını çiğnerdi.
    """
    tavan = _OLCULEN_KUYRUK_TAVANI.get(type_)
    if tavan is None or kuyruk <= tavan:
        return None
    return tavan


def _kirmizi_esigi(type_: str) -> int:
    """Bu slotun kırmızı eşiği.

    Tek okuma noktası: eşik iki yerde hesaplanırsa biri değişip öteki
    kalır ve 503 ile `notifyRuns.lastStatus` sessizce ayrışır — aynı
    gerekçe `tamamen_dustu`da da yazılı.
    """
    return _SLOT_KIRMIZI_ESIGI.get(type_, _KIRMIZI_ESIGI)

#: `RunResult.status` bu değerlerden birini aldıysa koşu tamamen düşmüştür.
#: Tek kaynak: uç 503 kararını `tamamen_dustu()` ile verir, panel aynı adı
#: `notifyRuns.lastStatus`ta okur.
_DUSUS_DURUMLARI = ("uretim-tamamen-dustu", "gonderim-tamamen-dustu")


def _iter_profiles():
    """Kullanıcı profillerini sayfalayarak dolaşır."""
    client = firestore_client.get_client()
    if client is None:
        return

    from google.cloud.firestore_v1.base_query import FieldFilter

    son = None
    while True:
        sorgu = (client.collection("users")
                 .where(filter=FieldFilter("onboardingCompleted", "==", True))
                 .order_by("__name__")
                 .limit(PAGE_SIZE))
        if son is not None:
            sorgu = sorgu.start_after({"__name__": son})

        sayfa = list(sorgu.stream())
        if not sayfa:
            return
        for anlik in sayfa:
            veri = anlik.to_dict() or {}
            veri["uid"] = anlik.id
            yield veri
        son = sayfa[-1].id
        if len(sayfa) < PAGE_SIZE:
            return


def _jeton_zamani(profil: dict[str, Any]) -> tuple[str, str]:
    """Jetonun bu profile en son ne zaman yazıldığı — sıralanabilir anahtar.

    Birincil `fcmTokenAt` (38+ istemci, sunucu zaman damgası); yoksa
    `lastSeenDaily` (her istemci, gün çözünürlüğü). Damgası olan profil
    olmayanı yener: damga yazan istemci jetonu EN SON almış olandır.
    """
    damga = profil.get("fcmTokenAt")
    if damga is None:
        damga_iso = ""
    elif hasattr(damga, "isoformat"):
        damga_iso = damga.isoformat()
    else:
        damga_iso = str(damga)
    return (damga_iso, str(profil.get("lastSeenDaily") or ""))


def _jeton_sahipleri(profiller: list[dict[str, Any]]) -> dict[str, str]:
    """Her cihaz jetonu için EN SON sahiplenen uid (JT-turu).

    Aynı telefonda hesap değiştirilince eski hesabın profilindeki
    `fcmToken` duruyordu (çıkış silmiyordu) — o cihaza İKİ hesabın push'u
    gidiyordu, biri Türkçe biri İngilizce (cihazda ölçüldü: sahip + test
    hesabı aynı jeton). Jeton bir cihaza aittir ve cihazda o an bir hesap
    açıktır: en son yazan kazanır, diğerleri bu koşuda atlanır ve bayat
    jetonları silinir.
    """
    sahipler: dict[str, tuple[tuple[str, str], str]] = {}
    for p in profiller:
        jeton = p.get("fcmToken")
        uid = p.get("uid")
        if not jeton or not uid:
            continue
        anahtar = _jeton_zamani(p)
        mevcut = sahipler.get(jeton)
        if mevcut is None or anahtar > mevcut[0]:
            sahipler[jeton] = (anahtar, uid)
    return {jeton: uid for jeton, (_, uid) in sahipler.items()}


def _bayat_jetonu_sil(uid: str) -> None:
    """Başka hesabın cihazına ait jetonu bu profilden söker (best-effort).

    Silinmese bir sonraki koşuda yine atlanır; silinince bu koşu bir daha
    karşılaşmaz ve `_iter_profiles` maliyeti düşer.
    """
    try:
        client = firestore_client.get_client()
        if client is None:
            return
        from google.cloud import firestore as gfs
        client.collection("users").document(uid).update(
            {"fcmToken": gfs.DELETE_FIELD, "fcmTokenAt": gfs.DELETE_FIELD})
    except Exception as exc:
        logger.warning("Bayat jeton silinemedi (%s): %s", uid, exc)


class RunResult(BaseModel):
    status: str
    type: str
    scanned: int
    queued: int
    sent: int
    failed: int
    pruned: int
    #: Neden gönderilmediğinin dökümü — sessiz düşen bildirimler görünür olmalı.
    skipped: dict[str, int]
    #: Kuyruğa giren mesajların dil dökümü (DM-turu): "hem İngilizce hem
    #: Türkçe" bulgusundan sonra hangi dilde kaç push gittiği görünür olmalı.
    languages: dict[str, int] = Field(default_factory=dict)
    #: Slotun KENDİ İÇERİK KAYNAĞININ dökümü (SZ-turu): ``attempted`` /
    #: ``ok`` / ``fallback``. Bu sayılar bugüne dek HİÇBİR YERDE yoktu ve
    #: kesintinin bir ay görünmez kalmasının sebebi buydu: kaynak düşünce
    #: koşu şablon satıra düşüp push'u normal gönderiyor, yani `sent`
    #: sağlıklı görünüyor.
    #:
    #: Kaynağın NE OLDUĞU türe göre değişir, ölçülen şey aynı: "bu push'un
    #: dayandığı veri gerçekten elde edilebildi mi".
    #:
    #: - ``daily`` → kişisel AI paketi (Gemini). Ölçülen kesinti buydu.
    #: - ``winback`` → 3. basamakta paylaşılan gökyüzü ayrıntısı,
    #:   10. basamakta çift ölçümü. ``get_sky_now`` düştüğünde koşu
    #:   `ham_sky = {}` ile devam ediyor ve bu bugüne dek TAMAMEN sessizdi.
    #: - ``circle`` → çift transit ölçümü (efemeris, LLM'siz).
    #:
    #: ``checkin``/``midday`` sabahın paketini salt OKUR
    #: (`generate_if_missing=False`) ve ``streak`` şablondur; onlarda döküm
    #: BOŞ kalır. Boş döküm "ölçülemedi" demek, "düştü" demek DEĞİL —
    #: `_dusus_gerekcesi` boş dökümü kırmızı saymaz.
    #:
    #: "OLAY YOK" da düşüş DEĞİL: sakin bir günde çift ölçümü yapılır ama
    #: vuruş çıkmaz; o kullanıcı ``ok`` sayılır ve bildirim görünür bir
    #: gerekçeyle atlanır. Ayrım olmasaydı sakin bir gün sahte alarm
    #: üretirdi (bkz. `notification_service._en_iyi_vurus`).
    generation: dict[str, int] = Field(default_factory=dict)


def _paket_uretildi(iz: str, lang: str) -> bool:
    """Bu kullanıcının kişisel AI paketi BUGÜN gerçekten üretilebildi mi?

    NEDEN bu ölçüm var: `signal_push` üretim DÜŞSE DE gövde döndürür —
    paket yoksa sinyalin şablon "teknik" satırına düşer ve push normal
    gider (`notification_service._bundle_body`). Yani koşunun kendi dönüş
    değeri bu kusuru GÖRMEZ. Çıkarım değil ÖLÇÜM (2026-10-02 06:05 UTC
    koşusu, Cloud Run günlüğü): 10 Gemini 403'ü, onlara BİREBİR eşlenen 10
    "Sinyal yorumu biçim dışı (0 satır), şablona düşüldü" satırı — yani
    hepsi `signal_service.insight_bundle` yolundan — ve ardından
    `kuyruk=10 gonderilen=10 basarisiz=0` + `"POST /notify/run" 200 OK`.

    Ölçülebilen tek iz paketin kendi önbellek kaydıdır:
    `signal_service.cached_insight_bundle` ya gerçek paketi ya da kısa
    ömürlü başarısızlık sentinel'ini (``failed: True``) yazıyor. Anahtar
    aynı parmak izinden kuruluyor (`bundle_key`) ve parmak izi bize
    `signal_push`tan GERİ DÖNÜYOR — fazladan hesap yok, fazladan LLM
    çağrısı yok, salt okuma.

    ⚠️ ADIN SINIRI: bu "paket ÜRETİLDİ" der, "AI cümlesi GÖNDERİLDİ"
    demez. `_bundle_body` cümleyi uzunluk ya da dil muhafızında düşürüp
    teknik satıra inebilir; o kullanıcı burada yine ``ok`` sayılır. Ters
    yönde yanılmaz — paket yoksa cümle de yoktur — ve bekçinin aradığı
    şey tam olarak o yön: HİÇBİR paketin üretilememesi.
    """
    kayit = cache.get(signal_service.bundle_key(iz, lang))
    return bool(kayit and not kayit.get("failed") and kayit.get("insights"))


def _dusus_gerekcesi(sonuc: RunResult) -> str | None:
    """Koşu TAMAMEN düştü mü — düştüyse gerekçe adı, düşmediyse None.

    İki ayrı tam düşüş var ve ikisi de bugüne dek 200 dönüyordu:

    1. **Üretim**: denenen her kullanıcı için o slotun İÇERİK KAYNAĞI
       düştü — `daily`de kişisel AI paketi (ölçülen kesinti, Gemini 403),
       `winback`/`circle`de gökyüzü ya da çift ölçümü. Push'lar yine
       gittiği için `sent`/`failed` sağlıklı görünür; kusuru yalnız
       `generation` gösterir. Eşik ve "olay yok düşüş değildir" ayrımı
       sayesinde sakin bir gün kırmızı yanmaz.
    2. **Gönderim**: kuyruğa giren hiçbir push ulaşmadı. FCM hiç
       kullanılamıyorsa `push_service.send` tek satır bile denemeden
       `SendResult(0, N, …)` dönüyor ve koşu buna da "ok" diyordu.

    Eşik ve "kısmi başarısızlık kırmızı DEĞİLDİR" gerekçesi
    `_KIRMIZI_ESIGI`de, slot başına sapması `_SLOT_KIRMIZI_ESIGI`de.
    Prova (`dry-run`) buraya hiç uğramaz: orada gönderim tanım gereği
    denenmez, `sent` her zaman 0 olurdu.

    ⚠️ Eşik SLOTTAN okunuyor (`sonuc.type`), sabit değil: `winback`in bir
    koşudaki kuyruğu ölçüldü (18 profil, hepsi sessiz → ortalama 0.79, en
    çok 2) ve sabit 3 eşiği o slotta HİÇ dolmuyordu — üretim tamamen
    düşse de uç 200 dönüyordu.

    Gönderim eşiği de aynı slot değerini kullanıyor ve bu BİLİNÇLİ:
    `queued` ile `attempted` aynı kuyruktan besleniyor, yani `winback`te
    gönderim kuyruğu da 0-2'dir. İki kapıya iki ayrı eşik yazılsaydı
    biri dolar öteki hiç dolmazdı.
    """
    esik = _kirmizi_esigi(sonuc.type)
    uretim = sonuc.generation
    if (uretim.get("attempted", 0) >= esik
            and uretim.get("ok", 0) == 0):
        return "uretim-tamamen-dustu"
    if sonuc.queued >= esik and sonuc.sent == 0:
        return "gonderim-tamamen-dustu"
    return None


def tamamen_dustu(sonuc: RunResult) -> str | None:
    """Uç için tek karar noktası: koşu tamamen düştüyse gerekçe adı.

    Ölçüt `_run` içinde BİR KEZ uygulanıp `status`a yazılıyor; burası
    yalnız o adı okur. İki yerde ayrı ayrı hesaplanırsa biri değişip
    diğeri kalır ve 503 ile `notifyRuns.lastStatus` sessizce ayrışır.
    """
    return sonuc.status if sonuc.status in _DUSUS_DURUMLARI else None


def _kosu_kaydet(type_: str, gun: str, sonuc: RunResult,
                 now_utc: dt.datetime) -> None:
    """Koşu sonucunu kalıcılaştırır (AP-turu) — panel "bildirim sağlığı".

    Eskiden RunResult yalnız HTTP yanıtı olarak Cloud Scheduler'a dönüp
    kayboluyordu. Doküman kimliği deterministik ``{gün}-{tür}``; zamanlayıcı
    SAATTE BİR koştuğu için sayılar Increment ile BİRİKİR (set ezseydi gün
    toplamı son saatin sayısına inerdi). Best-effort: yazım düşerse koşu
    düşmez. dry_run buraya hiç uğramaz (prova iz bırakmaz).
    """
    try:
        client = firestore_client.get_client()
        if client is None:
            return
        from google.cloud import firestore as gcf
        client.collection("notifyRuns").document(f"{gun}-{type_}").set({
            "date": gun,
            "type": type_,
            "runs": gcf.Increment(1),
            "scanned": gcf.Increment(sonuc.scanned),
            "queued": gcf.Increment(sonuc.queued),
            "sent": gcf.Increment(sonuc.sent),
            "failed": gcf.Increment(sonuc.failed),
            "pruned": gcf.Increment(sonuc.pruned),
            "skipped": {k: gcf.Increment(v) for k, v in sonuc.skipped.items()},
            # AD7: dil dökümü de birikir — rollup `notify.{tür}.languages`.
            "languages": {k: gcf.Increment(v)
                          for k, v in sonuc.languages.items()},
            # SZ-turu: üretim dökümü de birikir. Durum koduna bakan tek göz
            # Scheduler günlüğü ve o günlük yalnız SON koşuyu gösterir;
            # "bugün kaç üretim denendi, kaçı düştü" sorusu ancak burada
            # toplanırsa cevaplanabilir.
            "generation": {k: gcf.Increment(v)
                           for k, v in sonuc.generation.items()},
            "lastStatus": sonuc.status,
            "lastRunAt": now_utc,
        }, merge=True)
    except Exception as exc:
        logger.warning("Bildirim koşusu kaydedilemedi (%s/%s): %s",
                       gun, type_, exc)


def _profiller(only_uid: str | None) -> list[dict[str, Any]]:
    if only_uid:
        profil = profile_service.get_profile(only_uid)
        return [{**profil, "uid": only_uid}] if profil else []
    return list(_iter_profiles())


def _run(type: str, *, dry_run: bool, force: bool, ignore_dedupe: bool,
         only_uid: str | None, mark: bool
         ) -> tuple[RunResult, list[push_service.Message]]:
    """Koşunun gövdesi; kuyruğa giren mesajları da döner (test-send
    başlık/gövdeyi buradan gösterir)."""
    now_utc = dt.datetime.now(dt.timezone.utc)
    # Gökyüzü bir kez okunur ve tüm kullanıcılar için paylaşılır.
    try:
        ham_sky = get_sky_now()
    except Exception as exc:
        logger.warning("Bildirim icin gokyuzu alinamadi: %s", exc)
        ham_sky = {}

    mesajlar: list[push_service.Message] = []
    isaretlenecek: list[tuple[str, str]] = []  # (uid, yerel gün)
    # OT1.1: daily gönderiminin hafıza alanları (gövde + odak sinyal) —
    # başarılı gönderimden sonra mark_sent'e `extra` olarak geçer.
    ekstralar: dict[str, dict[str, Any]] = {}
    taranan = 0
    atlanan: dict[str, int] = {}
    # DM-turu: kuyruğa giren mesajların dil sayımı (özet loga ve yanıta).
    diller: dict[str, int] = {}
    # SZ-turu: kişisel AI üretiminin sayımı (bkz. RunResult.generation).
    uretim: dict[str, int] = {}
    # Dil başına yerelleştirilmiş gökyüzü; her kullanıcı için yeniden
    # hesaplamaya gerek yok.
    sky_by_lang: dict[str, dict[str, Any]] = {}

    # JT-turu: profiller bir kez okunur (≤ birkaç yüz); aynı jetonu taşıyan
    # hesaplardan yalnız en son sahiplenen alır — cihaza iki hesabın push'u
    # gitmez.
    profiller = _profiller(only_uid)
    jeton_sahibi = _jeton_sahipleri(profiller)

    for profil in profiller:
        taranan += 1
        jeton = profil.get("fcmToken")
        if jeton and jeton_sahibi.get(jeton) != profil.get("uid"):
            logger.warning(
                "Jeton başka hesapta daha yeni: uid=%s sahip=%s tur=%s — "
                "atlandı, bayat jeton siliniyor",
                profil.get("uid"), jeton_sahibi.get(jeton), type)
            atlanan["jeton-baska-hesapta"] = (
                atlanan.get("jeton-baska-hesapta", 0) + 1)
            if not dry_run:
                _bayat_jetonu_sil(profil["uid"])
            continue
        gonder, gerekce = notification_service.should_send(
            profil, type, now_utc, ignore_target_hour=force,
            ignore_dedupe=ignore_dedupe)
        if not gonder:
            atlanan[gerekce] = atlanan.get(gerekce, 0) + 1
            continue

        lang = notification_service.profile_language(profil)
        yerel = notification_service.local_now(profil, now_utc)
        gun = yerel.date().isoformat()
        # SS-turu: gövde SORU biçimliyse üretici bunu beyan eder; sohbet
        # tohumu dil kapısından SONRA atılır (aşağıda).
        soru = False
        # DM-turu dil ağının ölçümünden ÇIKARILACAK özel ad. Yalnız karşı
        # tarafın görünen adını metne koyan slotlar doldurur (`circle`);
        # boş kalınca `ozel_ad_haric` metne DOKUNMAZ, yani öteki
        # dalların davranışı birebir aynı.
        karsi_ad = ""

        if type == "daily":
            sign = profile_service.sun_sign_key(profil)
            if sign is None:
                atlanan["burc-bilinmiyor"] = atlanan.get("burc-bilinmiyor", 0) + 1
                continue
            if lang not in sky_by_lang:
                sky_by_lang[lang] = prompts.localize_sky(lang, ham_sky)
            # R2-S4 → KA-turu: sabah bildirimi kullanıcının 1 numaralı
            # sinyalinin O GÜNE ÖZGÜ AI cümlesi (uç ile paylaşılan
            # paket — günde toplam bir üretim). Üretilemezse paylaşımlı
            # burç satırına geri düşülür; bildirim asla atlanmaz.
            # `route`/`fp`/`idx`/`d`: dokununca ilgili sinyal kartının
            # dayanak sayfası açılsın diye (KA5) — eski istemci bu
            # alanları yok sayar, davranışı değişmez.
            # OT1.3: dünkü gönderimin hafızası tema çarkını döndürür ve
            # "dünle aynı metin" korumasını besler; gönderilen gövde
            # `ekstra` ile geri yazılır (öğle kopya koruması ona bakar).
            onceki = notification_service.last_daily_sent(profil["uid"])
            sinyal_push = notification_service.signal_push(
                profil, lang, today=yerel.date(), onceki=onceki)
            if sinyal_push is not None:
                baslik, govde, iz, idx, ekstra = sinyal_push
                # SZ-turu: üretim BURADA sayılır, çünkü kişisel AI paketini
                # tetikleyen çağrı bir satır yukarıda ve kuyruktaki her
                # kullanıcı için BİR üretim demek (ölçüldü: 06:05 koşusunda
                # 10 kuyruk → 10 ardışık Gemini 403).
                #
                # ⚠️ ÖLÇÜLMEYEN yol: `signal_push` None döndüğünde (sinyal
                # yok) aşağıdaki `daily_push_body` de Gemini çağırıp sessizce
                # şablona düşüyor. O düşüş BURADA SAYILMIYOR, çünkü
                # `daily_push_body` yalnız bir dize döndürüyor ve şablona mı
                # düştüğü ancak metni şablonla karşılaştırarak anlaşılırdı —
                # şablon değişince sessizce "başarı" sayan kırılgan bir
                # ölçüm olurdu. Eksikliğin bedeli sınırlı: sinyalsiz hesap
                # bildirim nüfusunun kıyısı, ve ölçülen kesinti bu yoldan
                # DEĞİL paket yolundan geçiyor.
                uretim["attempted"] = uretim.get("attempted", 0) + 1
                _anahtar = "ok" if _paket_uretildi(iz, lang) else "fallback"
                uretim[_anahtar] = uretim.get(_anahtar, 0) + 1
                veri = {"type": "daily", "sign": sign, "route": "signal",
                        "fp": iz, "idx": str(idx), "d": gun}
                ekstralar[profil["uid"]] = ekstra
            else:
                baslik = prompts.get(lang).PUSH_DAILY_TITLE
                govde = notification_service.daily_push_body(
                    sign, sky_by_lang[lang], lang, gun)
                # BY-turu: yedek yol da hedefli — dokununca günlük okuma
                # (hikâye) açılır; eskiden yalnız sekme atanıyordu.
                veri = {"type": "daily", "sign": sign,
                        "route": "story", "d": gun}
        elif type == "midday":
            # OB3 → OT1.2: öğle ölçülü slotu — yalnız BUGÜN gerçekten
            # olay varsa gider ve SABAH GÖVDESİNİN KOPYASI ASLA gitmez
            # ("sabahla-ayni" gerekçesiyle görünür atlanır). LLM yakmaz.
            ogle, gerekce = notification_service.midday_push(
                profil, lang, today=yerel.date())
            if ogle is None:
                atlanan[gerekce] = atlanan.get(gerekce, 0) + 1
                continue
            baslik, govde, veri = ogle
        elif type == "circle":
            # CV: Çevrem slotu — öğlenin eski YEDEK dalı kendi saatine
            # çıktı ve önbellek şartı gevşedi. Döküm `olctu` üzerinden
            # bağlanıyor: ölçüm elde edilemezse bu kesinti durum koduna
            # kadar çıkmalı, yoksa "gonderilen=N basarisiz=0" diyen bir
            # koşu yine bir ayı yutar.
            cevre, gerekce, olctu, karsi_ad = (
                notification_service.circle_push(
                    profil, lang, today=yerel.date()))
            if olctu is not None:
                uretim["attempted"] = uretim.get("attempted", 0) + 1
                _anahtar = "ok" if olctu else "fallback"
                uretim[_anahtar] = uretim.get(_anahtar, 0) + 1
            if cevre is None:
                atlanan[gerekce] = atlanan.get(gerekce, 0) + 1
                continue
            baslik, govde, veri = cevre
        elif type == "winback":
            # K7: kademeli geri çağrı (3 → 10 → 30, sonra susar).
            # Basamağı `should_send` zaten doğruladı; burada YENİDEN
            # okunuyor çünkü `should_send` sözleşmesi (gönderilsin mi,
            # gerekçe) ve metni seçen şey basamağın kendisi. Aynı veriden
            # aynı sonuç: iki okuma, tek karar.
            basamak, _ = notification_service.winback_tier(
                profil, yerel,
                notification_service.winback_state(profil["uid"], profil))
            if basamak is None:
                # `should_send`ten geçmiş bir profilde olmamalı; yarış
                # (kullanıcı tam o anda uygulamayı açtı) ya da Firestore
                # okuma hatası üretebilir. SESSİZCE atlanmaz.
                atlanan["basamak-kayboldu"] = (
                    atlanan.get("basamak-kayboldu", 0) + 1)
                continue
            if lang not in sky_by_lang:
                sky_by_lang[lang] = prompts.localize_sky(lang, ham_sky)
            icerik, veri, olctu = notification_service.winback_push(
                profil, lang, basamak, sky=sky_by_lang[lang],
                today=yerel.date())
            if olctu is not None:
                uretim["attempted"] = uretim.get("attempted", 0) + 1
                _anahtar = "ok" if olctu else "fallback"
                uretim[_anahtar] = uretim.get(_anahtar, 0) + 1
            baslik, govde = icerik.baslik, icerik.govde
            # Gövde SORU: aşağıdaki ortak tohum dalı sohbeti açar.
            soru = icerik.soru
            # 10. basamağın gövdesi karşı tarafın ADINI taşıyabilir; ad
            # dil ölçümünden çıkarılmalı, yoksa aşağıdaki ortak ağ
            # İngilizce bir kullanıcıya giden Türkçe adlı geri çağrıyı
            # düşürürdü (`ozel_ad_haric` gerekçesi).
            karsi_ad = icerik.ozel_ad
            # Basamak ve sessizlik epizodunun çapası gönderim kaydına
            # yazılır; sayacın dönüşte sıfırlanması buna dayanıyor.
            ekstralar[profil["uid"]] = (
                notification_service.winback_sent_fields(basamak, profil))
        elif type == "checkin":
            # KA4: günün önemli sinyaline bağlı kişisel soru — yalnız
            # sabah paketinde soru YAZILMIŞSA gider; LLM çağrılmaz.
            # Soru FCM yükünde taşınır: içeriği yalnız transit
            # satırlarından üretildiği için kişisel veri sızdırmaz.
            checkin = notification_service.checkin_push(
                profil, lang, today=yerel.date())
            if checkin is None:
                atlanan["soru-yok"] = atlanan.get("soru-yok", 0) + 1
                continue
            baslik, govde = checkin.baslik, checkin.govde
            veri = {"type": "checkin", "route": "chat",
                    "q": govde, "q_date": gun}
            soru = checkin.soru
        else:
            baslik, govde = notification_service.streak_push(profil, lang)
            # BY-turu: "okumanı açmadın" dokununca okumayı AÇAR (hikâye) —
            # yalnız {type} taşıyan eski yükün hedefi yoktu.
            veri = {"type": "streak", "route": "story", "d": gun}

        # DM-turu son emniyet ağı: hangi dalda üretilmiş olursa olsun,
        # başlık ya da gövde profil dilinin DIŞINDA görünüyorsa push
        # GİTMEZ ve görünür atlanır. Üreticiler kendi muhafızını taşır
        # (`_bundle_body`, `checkin_push`); burası kaçağı yakalayan ağ.
        # Sohbet tohumu bu kapıdan SONRA: yanlış dilde soru sohbete girmez.
        #
        # ⚠️ ÖLÇÜLEN metin, GÖNDERİLEN metin değil: karşı tarafın özel adı
        # ölçümden çıkarılıyor (`ozel_ad_haric`, gerekçesi orada). Ad
        # DİL TAŞIMAZ ama `guess_language` harf tabanlı karar veriyor ve
        # tek bir "ş" bütün başlığın dilini belirliyordu — `lang="en"`
        # kullanan birinin Türkçe adlı bir arkadaşı varsa Çevrem
        # bildirimi her gün `dil-uyusmaz` ile düşüyordu. Ağ yerinde:
        # kaçak gövdenin dil işareti addan değil cümleden gelir.
        _baslik_olcum = notification_service.ozel_ad_haric(baslik, karsi_ad)
        _govde_olcum = notification_service.ozel_ad_haric(govde, karsi_ad)
        if (i18n.language_conflicts(_govde_olcum, lang)
                or i18n.language_conflicts(_baslik_olcum, lang)):
            logger.warning(
                "Bildirim dil uyuşmazlığı, gönderilmedi: uid=%s tur=%s "
                "lang=%s baslik=%r govde=%r",
                profil["uid"], type, lang, baslik, govde)
            atlanan["dil-uyusmaz"] = atlanan.get("dil-uyusmaz", 0) + 1
            continue

        # SS-turu: gövde bir SORUysa Rytho sohbette ÖNCE yazar. Karar tür
        # adından değil üreticinin beyanından (`soru`) geliyor. `dry_run`
        # tohumlamaz: prova iz bırakmaz; `mark=False` (test gönderimi) de
        # tohumlamaz. `cid` yüke `push_service.send`'den ÖNCE girmek
        # zorunda, bu yüzden tohum döngünün içinde kalıyor.
        if soru and not dry_run and mark:
            cid = chat_history.seed_assistant_message(
                profil["uid"], govde, lang, gun)
            if cid:
                veri["route"] = "chat_answer"
                veri["cid"] = cid

        diller[lang] = diller.get(lang, 0) + 1
        mesajlar.append(push_service.Message(
            uid=profil["uid"], token=profil["fcmToken"],
            title=baslik, body=govde, data=veri,
        ))
        isaretlenecek.append((profil["uid"], gun))

    if dry_run:
        logger.info("Bildirim PROVA turu=%s taranan=%d kuyruk=%d diller=%s "
                    "atlanan=%s",
                    type, taranan, len(mesajlar), diller, atlanan)
        return RunResult(
            status="dry-run", type=type, scanned=taranan,
            queued=len(mesajlar), sent=0, failed=0, pruned=0, skipped=atlanan,
            languages=diller, generation=uretim,
        ), mesajlar

    sonuc = push_service.send(mesajlar)

    # Gönderim kaydı SONRA yazılır: önce yazsaydık ve gönderim düşseydi,
    # kullanıcı o gün bildirimi hiç almazdı. OT1.5: GEÇİCİ hatalar da
    # işaretlenmez (eskiden yalnız ölü token'lar atlanıyordu ve FCM'in
    # anlık hatası kullanıcının o gününü sessizce yakıyordu) — zamanlayıcı
    # aynı hedef saat penceresi içinde yeniden dener. Süreç gönderim ile
    # işaretleme arasında ölürse dar bir çift-gönderim penceresi kalır;
    # kabul edilmiş sınır (işlemsel FCM+Firestore yok).
    if mark:
        basarisiz_uidler = set(sonuc.failed_uids)
        for uid, gun in isaretlenecek:
            if uid not in basarisiz_uidler:
                notification_service.mark_sent(uid, type, gun,
                                               extra=ekstralar.get(uid))

    logger.info("Bildirim turu=%s taranan=%d kuyruk=%d gonderilen=%d "
                "basarisiz=%d temizlenen=%d diller=%s uretim=%s atlanan=%s",
                type, taranan, len(mesajlar), sonuc.sent, sonuc.failed,
                len(sonuc.pruned), diller, uretim, atlanan)

    yanit = RunResult(
        status="ok", type=type, scanned=taranan, queued=len(mesajlar),
        sent=sonuc.sent, failed=sonuc.failed, pruned=len(sonuc.pruned),
        skipped=atlanan, languages=diller, generation=uretim,
    )
    # Tam düşüş durumu `status`a BURADA yazılır, uçta değil: `_kosu_kaydet`
    # bir satır aşağıda ve `lastStatus` ile ucun döndüğü durum AYNI olmak
    # zorunda — panelde "ok" yazarken Scheduler'da 503 görünmesi, kusuru
    # aramayı bir tur daha geciktirirdi.
    gerekce = _dusus_gerekcesi(yanit)
    if gerekce:
        yanit.status = gerekce
        logger.error("Bildirim kosusu TAMAMEN dustu (%s): tur=%s kuyruk=%d "
                     "gonderilen=%d uretim=%s",
                     gerekce, type, yanit.queued, yanit.sent, uretim)
    # Eşik kalibrasyonunun son kullanma tarihi. `status`a DOKUNMAZ: bant
    # aşımı kusur değil, "bu eşik artık ölçülmüş değil" demek.
    _tavan = _kalibrasyon_bandi_asildi(type, yanit.queued)
    if _tavan is not None:
        logger.warning(
            "Bildirim esigi KALIBRASYON BANDI DISINDA: tur=%s kuyruk=%d > "
            "olculen tavan=%d (esik=%d). Esik YENIDEN OLCULMELI — kucuk "
            "esik + buyuyen kuyruk yanlis alarm uretir.",
            type, yanit.queued, _tavan, _kirmizi_esigi(type))
    if mark:
        _kosu_kaydet(type, now_utc.date().isoformat(), yanit, now_utc)
    return yanit, mesajlar


def run_batch(type: str, *, dry_run: bool = False, force: bool = False,
              ignore_dedupe: bool = False, only_uid: str | None = None,
              mark: bool = True) -> RunResult:
    """Toplu koşu — modül başındaki sözleşme."""
    if type not in RUN_TYPES:
        raise ValueError(f"Bilinmeyen bildirim türü: {type}")
    if ignore_dedupe and not force:
        raise ValueError("ignore_dedupe yalnizca force ile birlikte kullanilir.")
    sonuc, _ = _run(type, dry_run=dry_run, force=force,
                    ignore_dedupe=ignore_dedupe, only_uid=only_uid, mark=mark)
    return sonuc


def test_send(uid: str, type: str = "daily") -> dict[str, Any]:
    """Panel "kendime test gönder" (AD8): YALNIZ verilen uid, iz yok.

    Koşu bu hesaba bir şey kuyrukladıysa o gider (gerçek üretim yolu
    sınanmış olur); atlandıysa (deneme dışı, soru yok…) sabit
    `PUSH_TEST_TITLE/BODY` gider — jeton/kanal/dil zinciri yine görülür.
    Profil ya da jeton yoksa ValueError (uç 400): sessiz "0 gönderildi"
    operatörü yanıltırdı.
    """
    if type not in RUN_TYPES:
        raise ValueError(f"Bilinmeyen bildirim türü: {type}")
    profil = profile_service.get_profile(uid)
    if not profil or not profil.get("fcmToken"):
        raise ValueError(NO_TOKEN_MESSAGE)
    profil = {**profil, "uid": uid}
    lang = notification_service.profile_language(profil)

    sonuc, mesajlar = _run(type, dry_run=False, force=True,
                           ignore_dedupe=True, only_uid=uid, mark=False)
    if mesajlar:
        m = mesajlar[0]
        return {"sent": sonuc.sent, "failed": sonuc.failed, "lang": lang,
                "title": m.title, "body": m.body, "skippedReason": None,
                "type": type}

    p = prompts.get(lang)
    gonderim = push_service.send([push_service.Message(
        uid=uid, token=profil["fcmToken"],
        title=p.PUSH_TEST_TITLE, body=p.PUSH_TEST_BODY,
        data={"type": "test"})])
    return {"sent": gonderim.sent, "failed": gonderim.failed, "lang": lang,
            "title": p.PUSH_TEST_TITLE, "body": p.PUSH_TEST_BODY,
            "skippedReason": next(iter(sonuc.skipped), None),
            "type": type}

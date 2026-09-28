"""Zorunlu güncelleme kapısı — sunucu zorlaması + sıcak anahtar (PBZ-turu).

Neden sunucuda: eşik 34 sürümdür yalnız İSTEMCİDE duruyordu
(`/api/v1/config/app` soğuk açılışta bir kez okunur, her hatada açık) ve
sunucu eski sürümün her isteğini kabul ediyordu; açık oturum günlerce eski
sürümde kalabiliyordu. Artık `/api/v1/` altındaki her istek `X-App-Build`
başlığıyla eşiğe vurulur; küçükse 426 döner ve istemci güncelleme
ekranına kilitlenir.

Neden sıcak anahtar: `RYTHO_MIN_BUILD` her deploy'da `--set-env-vars` ile
sıfırlanıyordu ve elle `gcloud`'la verilen değer sessizce siliniyordu. Eşik
artık Firestore `config/app.minBuild` dokümanında yaşar (panel → Sistem
yazar); env yalnız isteğe bağlı TABAN — etkin eşik ikisinin büyüğüdür.

Değişmezler:

1. **Eşik okuması hiç fırlatmaz.** Firestore yok / doküman bozuk → env
   tabanı. Kapının kendisi isteği düşüremez.
2. **Memo süreç içi sözlük, `core/cache.py` DEĞİL** (K8): cache modülü
   kalıcı katmana da yazıyor; bir Firestore okumasını okuma+yazma yapardı.
3. **Başlık yoksa build = 0** (K7): amaç açık oturumu da kilitlemek; ≤34
   istemciler zaten başlık göndermiyor, "başlıksız muaf" zorlamayı boşa
   çıkarırdı.
4. **Eşik > 0 ancak o sürümü canlı görmüş bir kullanıcı varsa** (K9):
   yazım hatasıyla (350 yerine 35) herkesi kilitlemek imkânsız —
   operatörün kendi cihazı şartı sağlar. Sürüm aynası (`users/{uid}.appBuild`)
   `core.auth.get_current_user` içinde sunucu tarafından yazılır (K10).
5. **Sürüm aynası doküman YARATMAZ** (B9): `update` kullanır, `set` değil.
   Silinmiş bir hesabın jetonu bir saate kadar geçerli kaldığı için
   yaratan bir yazım silinen kullanıcıyı diriltiyordu; gerekçe
   `remember_build` içinde.
"""
from __future__ import annotations

import datetime as dt
import logging
import time
from typing import Any

from starlette.concurrency import run_in_threadpool
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

from core import config, firestore as firestore_client
from core.i18n import resolve_language
from core.messages import text

logger = logging.getLogger(__name__)

#: İstemcinin gönderdiği versionCode başlığı (pubspec `+N`).
HEADER = "x-app-build"

#: Eşik memo'sunun ömrü: panelden yazılan değer en geç bu kadar sürede
#: her instance'a ulaşır; istek başına Firestore okuması yok.
MEMO_TTL = 60

#: Sürüm aynası memo'su: aynı uid + aynı build bu süre içinde yeniden
#: yazılmaz. Sürüm değişirse (güncelleme) hemen yazılır.
BUILD_MEMO_TTL = 24 * 3600

#: Kapıdan MUAF önekler. `/api/v1/` dışındaki yollar (`/health`,
#: `/health/rag`, `/docs`) zaten dokunulmaz — panel onları çağırıyor.
#: * config/  : eşiğin kendisi buradan okunur; kilitli istemci de ulaşmalı.
#: * admin/   : panel tarayıcıdan gelir, versionCode'u yok.
#: * billing/revenuecat, notify/run, maintenance/ : RevenueCat ve Cloud
#:   Scheduler — başlık göndermeyen makine istemcileri.
#: * partners/ : ortaklık uçlarının HİÇBİRİNİ uygulama çağırmıyor —
#:   üçü de `x-app-build` göndermeyen istemcilerden geliyor. ÖLÇÜLDÜ
#:   (2026-09-28, `grep -rn "partners/" apps/mobile/lib --include=*.dart`
#:   → SIFIR sonuç; uygulamanın ortaklıkla tek teması
#:   `/billing/redeem-code`, o da bu önekte değil):
#:     - `partners/click`  → tarayıcı (`web/r/index.html`)
#:     - `partners/me`     → tarayıcı (`web/ortak/ortak.js`)
#:     - `partners/mature` → Cloud Scheduler; `create-scheduler.ps1`
#:       yalnız `Authorization` başlığı yolluyor (satır 178/186).
#:
#:   ⚠️ Bu önek bir tur boyunca YANLIŞ gerekçeyle dışarıda tutuldu
#:   ("uygulamanın ve zamanlayıcının uçlarıdır, kapının arkasında
#:   KALMALI") ve o gerekçe iki sessiz ölümü çiviliyordu. Eşik > 0
#:   yazıldığı an:
#:     - ortak panosu TAMAMEN ölür: `/me` 426 döner, `ortak.js` bunu ne
#:       403 ne 5xx gördüğü için KALICI hata bandına düşer ve ortağa
#:       "uygulamanı güncelle" der — oysa ortağın uygulaması yok.
#:     - gecelik `rytho-partner-mature` işi her gece 426 alır;
#:       `pending` hakedişler 15 gün dolsa da `qualified` olmaz ve
#:       ORTAKLARA PARA ÖDENMEZ. Zamanlayıcıda yeniden deneme yok, hata
#:       yalnız Cloud Scheduler günlüğünde durur.
#:   Kapının amacı eski UYGULAMAYI kilitlemek; tarayıcıyı ve makine
#:   istemcisini kilitlemek amacın dışında.
EXEMPT_PREFIXES = (
    "/api/v1/config/",
    "/api/v1/admin/",
    "/api/v1/billing/revenuecat",
    "/api/v1/notify/run",
    "/api/v1/maintenance/",
    "/api/v1/partners/",
)

#: Eşik memo'su: (değer, monotonic son kullanma). None = hiç okunmadı.
_memo: tuple[int, float] | None = None

#: Sürüm aynası memo'su: uid -> (build, monotonic son kullanma).
_build_memo: dict[str, tuple[int, float]] = {}

#: Ayna memo'su bu boyu aşınca süresi dolanlar atılır (bellek büyümesi).
_BUILD_MEMO_PRUNE_AT = 5000

#: Testlerin zamanı ilerletebilmesi için dolaylı saat.
_now = time.monotonic


def parse_build(raw: Any) -> int:
    """Başlık/doküman değerini versionCode'a indirger.

    None, boş, bozuk ("abc", "35.0") ya da negatif → 0. Sıfır "bilinmiyor"
    demektir ve eşik > 0 iken kilitlenir (K7).
    """
    if raw is None or isinstance(raw, bool):
        return 0
    try:
        value = int(str(raw).strip())
    except (TypeError, ValueError):
        return 0
    return value if value > 0 else 0


def reset_memo() -> None:
    """Her iki memo'yu sıfırlar — panel yazımı sonrası ve testlerde."""
    global _memo
    _memo = None
    _build_memo.clear()


# --------------------------------------------------------------------------
# Eşik: env tabanı + config/app dokümanı
# --------------------------------------------------------------------------

def read_doc() -> dict[str, Any] | None:
    """`config/app` dokümanı olduğu gibi (panel "son yazım" için).

    Firestore yoksa ya da doküman yoksa None. Fırlatabilir — çağıranlar
    (`_doc_min_build`, admin GET) kendi savunmasını kurar.
    """
    client = firestore_client.get_client()
    if client is None:
        return None
    anlik = client.collection("config").document("app").get()
    if not getattr(anlik, "exists", False):
        return None
    return anlik.to_dict() or {}


def _doc_min_build() -> int:
    """Dokümandaki eşik; her hata 0'a düşer (env tabanı geçerli kalır)."""
    try:
        veri = read_doc() or {}
        return parse_build(veri.get("minBuild"))
    except Exception as exc:
        logger.warning("config/app okunamadı; env tabanı geçerli: %s", exc)
        return 0


def _memo_hit() -> int | None:
    """Memo tazeyse değeri, değilse None — olay döngüsünde bloklamadan."""
    if _memo is not None and _now() < _memo[1]:
        return _memo[0]
    return None


def current_min_build() -> int:
    """Etkin eşik = max(env `RYTHO_MIN_BUILD`, `config/app.minBuild`).

    ASLA fırlatmaz. 60 s süreç içi memo: hata yolunda da memo yazılır ki
    düşen Firestore her istekte yeniden yoklanmasın.
    """
    global _memo
    memo = _memo_hit()
    if memo is not None:
        return memo
    value = max(parse_build(config.MIN_APP_BUILD), _doc_min_build())
    _memo = (value, _now() + MEMO_TTL)
    return value


def set_min_build(value: int, reason: str, admin_uid: str) -> None:
    """Eşiği `config/app` dokümanına yazar ve memo'yu sıfırlar.

    Firestore yoksa RuntimeError — eşik yazılamadıysa "yazıldı" denmez.
    """
    client = firestore_client.get_client()
    if client is None:
        raise RuntimeError("Firestore erişilemiyor; eşik yazılamadı.")
    client.collection("config").document("app").set({
        "minBuild": int(value),
        "reason": reason,
        "updatedBy": admin_uid,
        "updatedAt": dt.datetime.now(dt.timezone.utc),
    }, merge=True)
    reset_memo()
    logger.info("config/app.minBuild = %d (%s): %s", value, admin_uid, reason)


# --------------------------------------------------------------------------
# Sürüm aynası: users/{uid}.appBuild
# --------------------------------------------------------------------------

def build_seen_at_or_above(value: int) -> bool:
    """`appBuild >= value` olan EN AZ BİR kullanıcı görülmüş mü (K9).

    Sorgu düşerse False: doğrulanamayan eşik yükseltilmez (kapalı taraf
    güvenli — operatör tekrar dener, kimse yanlışlıkla kilitlenmez).
    """
    try:
        client = firestore_client.get_client()
        if client is None:
            return False
        from google.cloud.firestore_v1.base_query import FieldFilter

        sonuc = (client.collection("users")
                 .where(filter=FieldFilter("appBuild", ">=", int(value)))
                 .limit(1)
                 .stream())
        return any(True for _ in sonuc)
    except Exception as exc:
        logger.warning("appBuild >= %s sorgusu düştü: %s", value, exc)
        return False


def count_below(value: int) -> int | None:
    """`appBuild < value` olan kullanıcı sayısı — count() aggregation.

    Alanı olmayan (başlık göndermeyen ≤34) kullanıcılar eşitsizliğe
    GİRMEZ; onlar adminStats `builds.unknown` altında. Sayım düşerse None
    (panel "—" gösterir) — `stats_service._count` deseni.
    """
    try:
        client = firestore_client.get_client()
        if client is None:
            return None
        from google.cloud.firestore_v1.base_query import FieldFilter

        sonuc = (client.collection("users")
                 .where(filter=FieldFilter("appBuild", "<", int(value)))
                 .count().get())
        return int(sonuc[0][0].value)
    except Exception as exc:
        logger.warning("appBuild < %s sayımı düştü: %s", value, exc)
        return None


def build_remembered(uid: str, build: int) -> bool:
    """Aynı uid + aynı build memo'da taze mi — Firestore'a gitmeden."""
    kayit = _build_memo.get(uid)
    return kayit is not None and kayit[0] == build and _now() < kayit[1]


#: `users/{uid}` YOKKEN yazımı reddeden Firestore hatasının sınıf ADI
#: (`google.api_core.exceptions.NotFound`). Sınıfa ADIYLA bakılıyor,
#: sembolle değil — `push_service._olu_token` ve
#: `partner_service._kullanici_yok_mu` ile aynı desen ve aynı iki gerekçe:
#: `google.api_core` bu modülün içe aktarma yüzeyinde yok, ve sahte
#: istemcilerin tam o sınıfı fırlatmasını şart koşmak testleri kitaplığın
#: iç yapısına bağlardı.
_DOKUMAN_YOK = "NotFound"


def remember_build(uid: str, build: int) -> None:
    """`users/{uid}.appBuild` aynasını yazar — best-effort, hiç fırlatmaz.

    uid başına 24 saatte bir (sürüm değişmediyse). Başlıksız istek
    (build 0) yazmaz: "bilinmiyor" dürüstçe bilinmiyor kalır. Yazım
    düşerse memo KURULMAZ ki bir sonraki istek yeniden denesin.

    ⚠️ **`update`, `set(merge=True)` DEĞİL** (bulgu B9, ölçüldü
    2026-09-18). Firestore'da `set(merge=True)` doküman yoksa onu YARATIR.
    `delete_account` `users/{uid}`'yi siliyor ama Firebase kimlik jetonu
    bir saate kadar geçerli kalıyor; o pencerede gelen tek kimlikli istek
    (uçuşta kalmış bir çağrı, yeniden deneme, hâlâ oturumu açık ikinci bir
    cihaz) buradan geçip dokümanı `{appBuild: N}` iskeletiyle GERİ
    getiriyordu. Üretimde ölçülen iz tam bu: 19 `users` dokümanının
    yalnız 12'sinin Auth karşılığı vardı ve yetimlerin dördünde
    BAŞKA HİÇBİR ALAN olmadan `appBuild: 41` duruyordu. Sonucu: panelin
    kullanıcı sayısı şişiyor ve hukuk metninin "hesabını silersen her şey
    silinir" sözü yalan oluyordu. `update` var olmayan dokümana yazmaz —
    dirilme artık yapısal olarak imkânsız, bir kontrol listesine bağlı
    değil.

    Ayna doküman YARATMAK ZORUNDA DEĞİL: `users/{uid}`'yi oturum
    açılışında istemci doğuruyor (`language_sync._firestoreWrite`,
    `fireImmediately` dinleyicisi) ve sunucu tarafında onboarding onayı
    (`consent_service.grant_terms_consent`) da aynı dokümana yazıyor. Yeni
    kullanıcının ilk isteği o doğumun ÖNÜNE geçebilir; o istekte ayna
    yazılmaz, **memo da kurulmaz** ve bir sonraki istek yazar — gecikme
    saniyelerle sınırlı, kalıcı kayıp yok. Bu yüzden "doküman yok" UYARI
    değil `debug`: her yeni kullanıcı için bir kez düşen bir uyarı,
    ileride gerçek bir yazım arızasını arayan kişiyi yanlış ize sokardı.

    Gövdenin TAMAMI koruma altında: havuzda eşzamanlı koşar, budama
    döngüsü sırasında başka bir iş parçacığı sözlüğü değiştirebilir ya da
    `reset_memo()` temizleyebilir. Buradan sızan her hata `core/auth`'un
    genel except'inde geçerli token'ı 401'e çevirir — ayna hiçbir koşulda
    kimliği düşüremez.
    """
    try:
        if not uid or build <= 0 or build_remembered(uid, build):
            return
        client = firestore_client.get_client()
        if client is None:
            return
        try:
            client.collection("users").document(uid).update(
                {"appBuild": int(build)})
        except Exception as exc:
            if type(exc).__name__ == _DOKUMAN_YOK:
                logger.debug(
                    "Sürüm aynası atlandı (%s): users dokümanı yok — "
                    "silinmiş hesap ya da henüz doğmamış yeni kullanıcı.",
                    uid)
            else:
                logger.warning("Sürüm aynası yazılamadı (%s): %s", uid, exc)
            return
        if len(_build_memo) >= _BUILD_MEMO_PRUNE_AT:
            simdi = _now()
            # Anlık kopya üzerinde: canlı sözlükte dönerken boyu değişirse
            # "dictionary changed size during iteration" fırlar.
            for anahtar, kayit in list(_build_memo.items()):
                if kayit[1] <= simdi:
                    _build_memo.pop(anahtar, None)
        _build_memo[uid] = (build, _now() + BUILD_MEMO_TTL)
    except Exception as exc:
        logger.warning("Sürüm aynası yazılamadı (%s): %s", uid, exc)


# --------------------------------------------------------------------------
# Middleware
# --------------------------------------------------------------------------

class AppGateMiddleware(BaseHTTPMiddleware):
    """`/api/v1/` altında `X-App-Build < eşik` → 426.

    Sıra: OPTIONS → geç (preflight en içteki CORS'a ulaşmalı; ratelimit
    deseni); `/api/v1/` ile BAŞLAMIYORSA → geç (panel `/health`,
    `/health/rag`); muaf önek → geç; build < eşik → 426.

    426 gövdesi (K6): `detail` yerelleştirilmiş İNSAN metni — ≤34
    istemciler `friendlyError` ile onu olduğu gibi basıyor; makine kodu
    ayrı `code` alanında.
    """

    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        if (request.method == "OPTIONS"
                or not path.startswith("/api/v1/")
                or path.startswith(EXEMPT_PREFIXES)):
            return await call_next(request)

        min_build = _memo_hit()
        if min_build is None:
            # Memo miss: Firestore okuması bloklar; olay döngüsü durmasın
            # (core/auth doktrini).
            min_build = await run_in_threadpool(current_min_build)
        if min_build <= 0:
            return await call_next(request)

        build = parse_build(request.headers.get(HEADER))
        if build < min_build:
            lang = resolve_language(request.headers.get("accept-language"))
            return JSONResponse(
                status_code=426,
                content={
                    "status": "error",
                    "code": "update_required",
                    "detail": text("update_required", lang),
                    "min_build": min_build,
                },
            )
        return await call_next(request)

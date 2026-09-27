"""RythoAI Backend — Kozmik hesaplama ve AI yorum motoru.

Cloud Run üzerinde çalışacak şekilde tasarlanmıştır:
- CORS açık (Flutter Web dahil tüm istemciler)
- Firebase ID token doğrulama (RYTHO_DEV_MODE=0 iken zorunlu)
- /healthz canlılık ucu
"""
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from api.account import router as account_router
from api.admin import router as admin_router
from api.astrology import router as astrology_router
from api.billing import router as billing_router
from api.chat import router as chat_router
from api.config import router as config_router
from api.contacts import router as contacts_router
from api.device import router as device_router
from api.face_reading import router as face_reading_router
from api.iching import router as iching_router
from api.maintenance import router as maintenance_router
from api.notify import router as notify_router
from api.partners import router as partners_router
from api.people import router as people_router
from api.reports import router as reports_router
from api.sky import router as sky_router
from core.app_gate import AppGateMiddleware
from core.i18n import resolve_language
from core.messages import text
from core.ratelimit import RateLimitMiddleware

# Log kurulumu — Cloud Run'da SEVİYE GÖRÜNSÜN.
#
# Kapalı test denetiminde (2026-09-14) ölçüldü: düz `basicConfig`
# handler'sız çağrılınca `StreamHandler(sys.stderr)` ekliyor ve Cloud Run
# yapılandırılmamış konteyner çıktısında stderr'in TAMAMINI ERROR sayıyor.
# Sonuç: `logger.info("sohbet ilişki bağlamı reddedildi")` ile
# `logger.exception("işlenmeyen hata")` konsolda AYNI kırmızı seviyede
# görünüyordu. Gerçek hata gürültünün içinde kayboluyor ve severity'ye
# dayalı bir uyarı kurmak imkânsız hâle geliyor.
#
# `google-cloud-logging` istemcisi Python seviyesini gerçek Cloud Logging
# severity'sine çeviriyor.
#
# ⚠️ Kapı YALNIZCA Cloud Run: `K_SERVICE` orada kesin dolu, başka yerde
# yok. Bu makinede ADC kurulu olduğu için kapısız hâli testlerde de
# istemciyi ayağa kaldırıyor ve YEREL test loglarını canlı Cloud
# Logging'e göndermeye çalışıyordu ("CloudLoggingHandler shutting
# down… Failed to send 1 pending logs"). Yerelde istenen şey basit
# stderr; üretim gözlemlenebilirliği yerel gürültüye dönüşmemeli.
if os.getenv("K_SERVICE"):  # pragma: no cover - yalnız Cloud Run
    try:
        import google.cloud.logging as _gcl

        _gcl.Client().setup_logging(log_level=logging.INFO)
    except Exception:
        logging.basicConfig(level=logging.INFO)
        logging.getLogger(__name__).warning(
            "Cloud Logging kurulamadı; loglar stderr'e düşecek ve "
            "Cloud Run hepsini ERROR sayacak.")
else:
    logging.basicConfig(level=logging.INFO)

logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(_: FastAPI):
    """Kimlik bilgisi yoklamasını açılışta, arka planda başlat.

    Yoklama ilk çağrıda yapılırsa bedelini **ilk kullanıcı** öder; ölçülen
    ortamda bu 12 saniyeydi ve hem token doğrulama hem Firestore aynı bedeli
    ayrı ayrı ödüyordu. Açılışta başlatınca istek geldiğinde sonuç hazır olur.
    Açılış beklemez (bkz. `core.gcp_credentials.warm_up`).
    """
    from core import gcp_credentials
    from services import astro_service, gemini_service

    gcp_credentials.warm_up()
    # Ağır kütüphaneler (`google.genai` 624 ms, `kerykeion` 212 ms) modül
    # düzeyinden çıkarıldı: artık açılışı geciktirmiyorlar. Burada arka planda
    # ısıtılıyorlar ki bedeli ilk kullanıcı da ödemesin.
    gemini_service.warm_up()
    astro_service.warm_up()
    yield


app = FastAPI(
    title="RythoAI Cosmic Engine",
    version="2.0.0",
    description=(
        "Swiss Ephemeris tabanlı astroloji, BaZi, I Ching ve RAG destekli "
        "Gemini yorum servisi."
    ),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Zorunlu güncelleme kapısı (PBZ): `/api/v1/` altında X-App-Build < eşik
# → 426. SIRA BİLİNÇLİ: Starlette'te son eklenen ilk koşar
# (`applications.py` insert(0, …)); CORS'tan SONRA, RateLimit'ten ÖNCE
# eklenince istek `security_headers → RateLimit → AppGate → CORS → router`
# olur — 426'lar kotaya tabi kalır, preflight (OPTIONS geçirilir) en
# içteki CORS'a ulaşır. Panel aynı origin'den Hosting rewrite ile geliyor
# ve tüm yolları muaf; 426'nın CORS başlığı taşımaması sorun değil.
app.add_middleware(AppGateMiddleware)

# İstek kotası: LLM uçları 10/dk, diğerleri 60/dk (bkz. core/ratelimit.py)
app.add_middleware(RateLimitMiddleware)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    """Temel güvenlik başlıkları — API yanıtlarının tarayıcıda kötüye
    kullanılmasını zorlaştırır."""
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "no-referrer")
    response.headers.setdefault(
        "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
    )
    response.headers.setdefault("Cross-Origin-Opener-Policy", "same-origin")
    return response


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """Beklenmeyen hatalarda stack trace sızdırmadan 500 döner; ayrıntı
    yalnızca sunucu loguna yazılır.

    Metin KULLANICININ DİLİNDE. Eskiden Türkçe sabitti: İngilizce telefonu
    olan bir testçi, uygulamanın her yeri İngilizceyken tek bir Türkçe
    cümleyle karşılaşıyordu (kapalı test denetimi, 2026-09-14). Çevirisi
    `core/messages.py` içinde zaten vardı, yalnız çağrılmıyordu. Dil
    çözümü `ratelimit.py`'deki 429 yoluyla aynı iki satır.
    """
    logger.exception("İşlenmeyen hata: %s %s", request.method, request.url.path)
    lang = resolve_language(request.headers.get("accept-language"))
    return JSONResponse(
        status_code=500,
        content={"status": "error", "detail": text("internal", lang)},
    )

app.include_router(astrology_router, prefix="/api/v1/astrology", tags=["Astrology"])
# /api/v1/bazi/chart SILINDI (Revize B0): require_plus'siz, cuzdansiz, mobil
# istemcinin hic kullanmadigi bir uctu ve ucretli hesabin hesap kismini
# bedava sizdiriyordu. Chart + rapor tek yerden: /api/v1/reports/bazi.
app.include_router(iching_router, prefix="/api/v1/iching", tags=["I Ching"])
# Firaset (yüz okuma). Uç GÖRÜNTÜ ALMAZ, oran alır: tespit kullanıcının
# cihazında yapılır ve sunucuya yalnızca türetilmiş sayılar gelir. Eski
# tasarım fotoğrafı yüklüyordu ve silme adımı olsa da biyometrik veri
# sunucuya ULAŞIYORDU; şimdi ulaşmıyor.
#
# YAYIN ÖNCESİ: bu özelliğin açık rıza akışı, gizlilik politikası ve
# Play Data Safety / App Privacy beyanları tamamlanmadan mağazaya
# gitmemeli (GDPR Md.9 / KVKK md.6 / BIPA).
app.include_router(face_reading_router, prefix="/api/v1/face", tags=["Firasa"])
app.include_router(sky_router, prefix="/api/v1/sky", tags=["Sky"])
app.include_router(chat_router, prefix="/api/v1/chat", tags=["Chat"])
app.include_router(reports_router, prefix="/api/v1/reports", tags=["Reports"])
app.include_router(billing_router, prefix="/api/v1/billing", tags=["Billing"])
app.include_router(device_router, prefix="/api/v1/device", tags=["Device"])
app.include_router(contacts_router, prefix="/api/v1/contacts", tags=["Contacts"])
# Eklenen kişiler (P-turu): kullanıcının kendi girdiği eş/çocuk/yakın
# kayıtları. Yazma buradan geçiyor çünkü kontenjan Firestore kurallarında
# zorlanamaz (koleksiyon sayılamaz); okuma istemcinin kendi akışından.
app.include_router(people_router, prefix="/api/v1/people", tags=["People"])
app.include_router(maintenance_router, prefix="/api/v1/maintenance", tags=["Maintenance"])
# Bildirimler (Faz 6). Eski notify.py istemcinin serbestçe başlık/gövde
# göndermesine izin verdiği için kaldırılmıştı; yenisinde metin SUNUCUDA
# üretilir, toplu gönderim yalnızca Cloud Scheduler'ın paylaşılan anahtarıyla
# tetiklenir ve tekil gönderimde arkadaşlık sunucuda doğrulanır.
app.include_router(notify_router, prefix="/api/v1/notify", tags=["Notifications"])
# Hesap silme: mağaza zorunluluğu (Apple 5.1.1(v), Google Play). İstemci
# tarafında yapılamaz çünkü başka kullanıcıların dokümanlarındaki karşılıklı
# arkadaşlık kayıtlarına ve sunucuya kapalı koleksiyonlara dokunuyor.
app.include_router(account_router, prefix="/api/v1/account", tags=["Account"])
# Admin uçları (W5): panel /rytho-admin buradan beslenir. Her uç custom
# claim ister (require_admin); collect ayrıca scheduler sırrını kabul eder.
app.include_router(admin_router, prefix="/api/v1/admin", tags=["Admin"])
# Ortaklik: ortagin KENDI panosu (require_partner) + hakedis
# olgunlastirma (scheduler sirri VEYA owner). Admin router'indan AYRI —
# ortak yonetim uclarini goremez, yonetici de /me kapisindan gecemez.
app.include_router(partners_router, prefix="/api/v1/partners",
                   tags=["Partners"])
# Açılış yapılandırması (F3): kimliksiz — giriş ekranından ÖNCE çağrılır.
app.include_router(config_router, prefix="/api/v1/config", tags=["Config"])


@app.get("/")
def read_root():
    return {"service": "RythoAI Cosmic Engine", "version": "2.0.0", "docs": "/docs"}


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/health")
def health():
    """Canlılık ucu.

    `/healthz` *.run.app alan adlarında Google'ın ön yüzü tarafından yakalanıyor
    ve istek konteynıra hiç ulaşmıyor (dışarıdan Google'ın 404 sayfası döner).
    Dışarıdan izleme yapılacaksa bu yol kullanılmalı; `/healthz` yerel ve
    konteynır içi kontroller için duruyor.
    """
    return {"status": "ok"}


@app.get("/health/rag")
def health_rag():
    """Bilgi tabanının durumu.

    Anlamsal aramanın anahtar kelime moduna düşmesi bir kez **haftalarca**
    fark edilmedi: hiçbir yerde görünmüyordu, hata da vermiyordu. Korpus
    büyüdükçe (kitaplar) bu sessiz bozulma daha pahalı hale geliyor, çünkü
    eksik artefakt her soğuk başlatmada yeniden vektörleme faturası demek.

    Kullanıcı verisi içermez; yalnızca parça sayısı, mod ve artefakt durumu.
    """
    from services.rag_service import diagnostics

    durum = diagnostics()
    saglikli = all(d["mode"] == "vector" and d["artifact"]
                   for d in durum.values())
    return {"status": "ok" if saglikli else "degraded", "bases": durum}

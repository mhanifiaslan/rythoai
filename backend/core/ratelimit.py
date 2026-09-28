"""Bellek içi kayan pencere istek kotası (rate limiting).

Cloud Run tek instance varsayımıyla bellek içi sözlük yeterlidir; birden çok
instance açılırsa limit instance başına uygulanır (yumuşak sınır — kabul
edilebilir). Anahtar olarak Firebase ID token'ının özeti, yoksa istemci IP'si
kullanılır; token'ın kendisi bellekte tutulmaz.
"""
import hashlib
import time
from collections import deque

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

from core.i18n import resolve_language
from core.messages import text

# LLM'e giden pahalı uçlar: daha sıkı kota.
#
# ## Neden yalnızca POST (KL-turu onarımı)
#
# Bu iki önek DAHA ÖNCE metot ayrımı yapmadan sıkı kotaya giriyordu ve
# altlarındaki UCUZ uçlar da aynı kovayı yakıyordu:
#   * `DELETE /api/v1/chat/conversations/{id}` — saf Firestore silme.
#     Kullanıcı sohbet listesinde 10 konuyu arka arkaya silince 429
#     görüyordu ("konuları silerken fazla istek" bulgusu, cihazdan).
#   * `GET /api/v1/reports/iching/status` — yalnız kota sayacı okur.
#   * `GET /api/v1/reports/signals` — günlük paylaşımlı önbellek; günde
#     en fazla bir üretim, gerisi okuma.
# Dahası: ÖNBELLEKTEN servis edilen rapor okumaları da (LLM hiç
# çalışmadan, jeton hiç düşmeden) aynı kovayı yiyordu — Atlas'ta birkaç
# detay ekranı gezen ABONE kullanıcı dakikada 10'u doldurup sohbete
# sıra gelmeden "yoğun talep" duvarına çarpıyordu.
#
# Üretim yapabilen her uç POST'tur (tek istisna GET /signals ve
# GET /horoscope — ikisi de gün/dönem başına tek üretimli paylaşımlı
# önbellek). Bu yüzden kural metoda bağlandı: okuma ve silme genel
# kotaya (dakikada 60) düşer, gerçek üretim sıkı kotada kalır.
LLM_PREFIXES = ("/api/v1/reports", "/api/v1/chat")

# LLM kotasından muaf tutulan uçlar.
# Burç yorumu kullanıcıdan bağımsızdır ve paylaşımlı önbellekten servis edilir:
# dönem başına burç başına en fazla bir LLM çağrısı yapılır, gerisi önbellek
# okumasıdır. Kullanıcı burç şeridinde çiplere dokundukça saniyeler içinde
# 10 isteği geçebiliyor; ücretsiz katmanın omurgasını buna kurban etmemek için
# genel kotaya (dakikada 60) tabi tutulur.
LLM_EXEMPT_PREFIXES = ("/api/v1/reports/horoscope",)
# 10 idi: sınıflandırma hatası yüzünden ucuz istekler de buradan yiyordu ve
# meşru gezinme duvara çarpıyordu. Asıl MALİYET kapısı artık jeton cüzdanı
# (RYTHO_TOKENS_ENFORCE=1 canlı); buradaki kota kaçak döngü ve kimliksiz
# sel koruması. 20, tek kullanıcının makul en yoğun dakikasının üstünde.
LLM_LIMIT_PER_MINUTE = 20
DEFAULT_LIMIT_PER_MINUTE = 60
WINDOW_SECONDS = 60.0

# Admin paneli kovası (AD2). Panel tek bir Authorization özetiyle çalışır
# ve bir sayfa açılışı 5-8 uç çağırır; Genel Bakış + Kullanıcılar + bir
# 360 gezintisi genel kotanın 60'ını bir dakikada bitiriyordu. Ayrı kova
# (`adm:` öneki) + kendi sınırı: panel trafiği mobil kotayı, mobil
# trafik panel kotasını YEMEZ. `/admin/collect` muaf kalır (EXEMPT_PATHS;
# scheduler'ın diğer işleriyle aynı başlığı paylaşıyor).
ADMIN_PREFIX = "/api/v1/admin/"
ADMIN_LIMIT_PER_MINUTE = 240

# Ortak tıklama sayacı: KENDİ kovası (`clk:`), muafiyet DEĞİL.
#
# Uç kimliksiz olduğu için anahtar IP'ye düşer ve Türkiye'de mobil
# operatörler CGNAT kullanıyor: yüzlerce ziyaretçi TEK egress IP'sini
# paylaşabilir. Genel kovada (dakikada 60) bir tanıtım tweet'i kendi
# ölçümünü kırpardı — tıklamalar tam işe yaradığı anda düşer, ortak
# "kimse tıklamıyor" sanır ve hiçbir yerde hata görünmez. Emsal aynı
# dosyada: `/api/v1/config/app` tam bu gerekçeyle muaf edildi.
#
# Muafiyet YERİNE ayrı kova, çünkü uç herkese açık ve YAZIYOR. Ayrımın
# iki yönü de korunuyor (`adm:` emsali): tıklama seli uygulamanın mobil
# kotasını yemez, mobil trafik de tıklama sayacını kırpmaz.
#
# 600 = saniyede 10. Tek bir NAT IP'sinden tek bir uygulamanın ortak
# linkine dakikada 600'den fazla tıklama gerçek bir tanıtım değil,
# kötüye kullanımdır — ve kovanın kendisi tavan olarak kalıyor: uçtaki
# "kod gerçekten var mı" kapısı çöp dokümanı, bu kova fatura selini
# durduruyor.
CLICK_PATH = "/api/v1/partners/click"
CLICK_LIMIT_PER_MINUTE = 600

# Kota dışı tutulan hafif uçlar.
# RevenueCat webhook'u da muaftır: tüm olaylar aynı Authorization başlığıyla
# gelir, yani tek bir kovayı paylaşırlar ve yoğun anlarda abonelik olayları
# düşerdi. Uç zaten paylaşılan gizli anahtarla korunuyor.
# Zamanlayıcının toplu gönderim ucu da muaftır: tek bir Authorization başlığı
# taşıdığı için tüm çağrıları aynı kovayı paylaşır ve saatlik işler yoğun bir
# dakikada birbirini düşürebilirdi. Uç zaten paylaşılan gizli anahtarla korunuyor.
# İstatistik toplayıcı da muaftır (W5): scheduler'ın diğer uçlarıyla aynı
# Authorization başlığını (dolayısıyla aynı kovayı) paylaşır.
# Açılış yapılandırması da muaftır (PBZ): kimliksiz çağrıldığı için tüm
# istemciler NAT arkasında aynı IP kovasını paylaşabilir ve 429 istemcide
# "eşik okunamadı" sayılırdı — zorunlu güncelleme kapısı kotaya kurban
# edilmez.
EXEMPT_PATHS = {"/", "/healthz", "/health", "/docs", "/openapi.json", "/redoc",
                "/api/v1/billing/revenuecat", "/api/v1/notify/run",
                "/api/v1/admin/collect", "/api/v1/config/app"}

# Kota mesajı dile göre core/messages.py'den gelir. Burası middleware olduğu
# için FastAPI bağımlılığı kullanılamaz; başlık doğrudan okunur.


class RateLimitMiddleware(BaseHTTPMiddleware):
    """uid/IP başına dakikalık kayan pencere kotası."""

    def __init__(self, app):
        super().__init__(app)
        # anahtar -> istek zaman damgaları (kayan pencere)
        self._hits: dict[str, deque[float]] = {}
        self._last_prune = time.monotonic()

    @staticmethod
    def _client_key(request: Request, sadece_ip: bool = False) -> str:
        """Kova anahtarı: token özeti, yoksa IP.

        `sadece_ip=True` Authorization başlığını HİÇ dinlemez ve bu yalnız
        KİMLİK KAPISI OLMAYAN uçlar için doğrudur. Gerekçe ölçüldü: kimlikli
        uçlarda uydurma bir token `core/auth`ta 401'lenir, yani ayrı kova
        kazanmak bir şey kazandırmaz. Kimliksiz bir uçta ise token hiç
        doğrulanmaz — istemci her isteğe farklı bir `Authorization` yazarak
        her istekte YENİ bir kova açar ve kota hiç devreye girmez (ölçüm:
        aynı IP'den 700 istek, tek 429 yok; sabit başlıkla 601'de düşüyor).
        Herkese açık ve YAZAN bir uçta bu, tavanın hiç olmaması demektir.
        """
        auth = None if sadece_ip else request.headers.get("authorization")
        if auth:
            # Token içeriğini saklamamak için özetini kullan
            return hashlib.sha256(auth.encode()).hexdigest()[:16]
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
        return request.client.host if request.client else "anon"

    def _prune(self, now: float) -> None:
        """Boşalan kayıtları at — bellek büyümesini engelle."""
        if now - self._last_prune < 300:
            return
        self._last_prune = now
        stale = [key for key, dq in self._hits.items()
                 if not dq or now - dq[-1] > WINDOW_SECONDS]
        for key in stale:
            self._hits.pop(key, None)

    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        if request.method == "OPTIONS" or path in EXEMPT_PATHS:
            return await call_next(request)

        # Yalnızca ÜRETEBİLEN istekler sıkı kotada (yukarıdaki gerekçe):
        # okuma/silme (GET, DELETE) genel kotaya düşer.
        is_llm = (request.method == "POST"
                  and path.startswith(LLM_PREFIXES)
                  and not path.startswith(LLM_EXEMPT_PREFIXES))
        is_admin = path.startswith(ADMIN_PREFIX)
        is_click = path == CLICK_PATH
        if is_click:
            kova, limit = "clk", CLICK_LIMIT_PER_MINUTE
        elif is_admin:
            kova, limit = "adm", ADMIN_LIMIT_PER_MINUTE
        elif is_llm:
            kova, limit = "llm", LLM_LIMIT_PER_MINUTE
        else:
            kova, limit = "std", DEFAULT_LIMIT_PER_MINUTE
        # Tıklama, admin, LLM ve genel kotalar ayrı sayaçlarda tutulur.
        # Tıklama ucunda anahtar YALNIZ IP: uçta kimlik kapısı olmadığı için
        # `Authorization` doğrulanmaz ve başlığı dinlemek kotayı istemcinin
        # eline verirdi (bkz. `_client_key` gerekçesi).
        key = f"{kova}:{self._client_key(request, sadece_ip=is_click)}"

        now = time.monotonic()
        self._prune(now)
        dq = self._hits.setdefault(key, deque())
        while dq and now - dq[0] > WINDOW_SECONDS:
            dq.popleft()

        if len(dq) >= limit:
            retry_after = max(1, int(WINDOW_SECONDS - (now - dq[0])) + 1)
            lang = resolve_language(request.headers.get("accept-language"))
            return JSONResponse(
                status_code=429,
                content={"status": "error", "detail": text("rate_limited", lang)},
                headers={"Retry-After": str(retry_after)},
            )

        dq.append(now)
        return await call_next(request)

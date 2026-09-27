"""Firebase ID token doğrulama.

Üretimde (RYTHO_DEV_MODE=0) her istek `Authorization: Bearer <idToken>` başlığı
taşımak zorundadır. Lokal geliştirmede token yoksa anonim kullanıcı kabul edilir.

**Bu modül her isteğin önünde durur.** Burada saniyeler süren bir işlem
uygulamanın tamamını yavaşlatır — kullanıcı bunu "sohbet geç geliyor",
"ekran açılmıyor" diye görür, kimlik doğrulama diye değil. Cihaz testinde tam
olarak bu oldu: kimlik bilgisi çözülemediği hâlde her istek ~12 saniye deneyip
vazgeçiyordu. O yüzden buradaki iki değişmez korunmalı:

1. **Kimlik bilgisi bir kez yoklanır** (bkz. `core.gcp_credentials`), istek
   başına değil.
2. **Olay döngüsü bloklanmaz**; doğrulama iş parçacığı havuzunda koşar.
"""
import logging

from fastapi import Depends, Header, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from starlette.concurrency import run_in_threadpool

from core import app_gate, config, gcp_credentials
from core.i18n import get_language
from core.messages import text

logger = logging.getLogger(__name__)

_firebase_ready = False
_warned = False


def _init_firebase() -> bool:
    global _firebase_ready, _warned
    if _firebase_ready:
        return True

    # `firebase_admin.initialize_app()` kimlik bilgisi olmadan da BAŞARIYLA
    # döner; tembel çalışır. Eksiklik ancak ilk `verify_id_token` çağrısında,
    # uzun bir beklemenin ardından ortaya çıkardı. O yüzden önce yokluyoruz.
    #
    # `available()` beklemez ve emin olmadığında ERİŞİLEBİLİR der; yani buraya
    # düşmek için yoklamanın KESİN olumsuz sonuçlanmış olması gerekiyor.
    # Bu ayrım bir kez atlandı ve üretimde tüm istekler 401 döndü.
    if not gcp_credentials.available():
        if not _warned:
            _warned = True
            if config.DEV_MODE:
                # Geliştirme ortamı: beklenen durum, bir kez söylenir.
                logger.warning(
                    "Kimlik bilgisi yok; token doğrulama atlanıyor (DEV_MODE). "
                    "Bu bir kapı gevşetmesi değil — DEV_MODE zaten tokensiz "
                    "isteği kabul ediyor."
                )
            else:
                # Üretim: bu bir dağıtım hatası. Sessiz kalırsa her istek 401
                # döner ve sebebi loglarda görünmez.
                logger.error(
                    "Application Default Credentials çözülemedi. Token "
                    "doğrulanamayacak ve tüm istekler 401 dönecek."
                )
        return False

    try:
        import firebase_admin

        if not firebase_admin._apps:
            # Cloud Run'da Application Default Credentials kullanılır.
            firebase_admin.initialize_app(
                options={"projectId": config.GOOGLE_CLOUD_PROJECT}
            )
        _firebase_ready = True
        return True
    except Exception as exc:  # pragma: no cover
        logger.warning("Firebase Admin başlatılamadı: %s", exc)
        return False


def reset_firebase_state() -> None:
    """Yoklama önbelleğini sıfırlar — yalnızca testler için."""
    global _firebase_ready, _warned
    _firebase_ready = False
    _warned = False
    gcp_credentials.reset()


_bearer = HTTPBearer(auto_error=False)

#: Panel rolleri (AD1). Claim `{admin: true, role: 'owner'|'support'}`.
#: `admin: true` ZORUNLU; `role` yalnız onu daraltır (bkz. `_rol_coz` —
#: rolün tek başına yetki vermesi 2026-09-15'te kapatıldı).
#: `role` yoksa ama `admin: true` varsa geçiş dönemi: owner sayılır.
#: Yeni rol eklemek = buraya yazmak + `tools/set_admin.py --role`
#: seçeneğine eklemek.
ROLES = ("owner", "support")


def _rol_coz(decoded: dict) -> str | None:
    """Claim'lerden panel rolü. **`admin: true` ZORUNLU koşuldur;** rol
    yalnız onu daraltır.

    Eski sürüm BİLİNEN rolü admin bayrağından bağımsız kabul ediyordu:
    `admin` claim'i OLMAYAN ama `role: "owner"` taşıyan bir token
    `require_admin`'i de `require_owner`'ı da geçiyordu — kullanıcı
    silme, hesap kapatma, CSV dışa aktarma, sürüm eşiği dahil her şey.

    ⚠️ **Düzeltme (2026-09-15).** Bu sıkılaştırma 2026-09-14'te canlıda
    "başka bir sistemin yazdığı `role: super_admin` claim'i" görüldüğü
    gerekçesiyle yapılmıştı. O ölçüm YANLIŞTI: `firebase_admin`
    projesiz başlatılmış ve ADC'nin varsayılan projesine (`xanthixai`)
    düşülmüştü. `rhytoai` projesinde öyle bir claim YOK; tek admin
    hesabı `{admin: true, role: owner}` taşıyor ve `role` claim'i olup
    `admin` olmayan kullanıcı sıfır.

    Sıkılaştırma yine de DURUYOR, ama gerekçesi artık gözlemlenmiş bir
    olay değil, savunma derinliği: yetki kapısı ortak bir kelimeye
    ("owner") değil, yalnız `tools/set_admin.py`'nin bastığı ayırt edici
    bir bayrağa dayanmalı. Bir claim'i sızdıran/paylaşan bir yol açılırsa
    kapı kendiliğinden kapalı kalır.

    Kural tek cümle: **rol tek başına yetki vermez.** `admin: true`
    yoksa rol yok sayılır; varsa ve rol tanınmıyorsa geçiş dönemi kuralı
    sürer (rolsüz eski `admin: true` claim'i owner sayılır).
    """
    if decoded.get("admin") is not True:
        return None
    rol = decoded.get("role")
    return rol if rol in ROLES else "owner"


def _ortak_coz(decoded: dict) -> str | None:
    """Claim'lerden ortaklık kimliği (OP). `{partner: true, partnerId: ...}`

    `_rol_coz`'un aynı disiplini: **`partner: true` ZORUNLU koşul.** Tek
    başına `partnerId` taşıyan bir token yetki almaz — kapı ayırt edici
    bayrağa dayanır, taşınabilir bir kimliğe değil.

    Ortaklık claim'i `admin` YAZMAZ ve yazmamalı: ortak bir yönetici
    değildir. İkisi aynı hesapta bulunabilir (sahibin kendi test ortağı)
    ama birbirini ima etmez.
    """
    if decoded.get("partner") is not True:
        return None
    kimlik = decoded.get("partnerId")
    return str(kimlik) if kimlik else None


class AuthUser:
    def __init__(self, uid: str, email: str | None = None,
                 anonymous: bool = False, phone: str | None = None,
                 admin: bool = False, auth_time: int = 0,
                 role: str | None = None, partner_id: str | None = None):
        self.uid = uid
        self.email = email
        self.anonymous = anonymous
        #: Firebase'in DOĞRULADIĞI telefon numarası (E.164), token'dan gelir.
        #: İstemcinin beyanı değil — SMS doğrulaması Firebase'de bitmiş
        #: numara. Rehber eşleşmesinin güven zinciri buradan başlıyor.
        self.phone = phone
        #: Firebase custom claim `admin: true` (W4). Yalnızca
        #: tools/set_admin.py ile basılır; istemci kendi token'ına claim
        #: yazamaz. Yönetim uçlarının tek kapısı [require_admin].
        self.admin = admin
        #: Firebase ID token'ındaki `auth_time` (epoch sn): kullanıcının bu
        #: oturumu AÇTIĞI an. Token yenilemede değişmez; tek cihaz kilidinin
        #: "son giriş kazanır" hakemi (TC-turu K1). DEV_MODE'da 0.
        self.auth_time = auth_time
        #: Panel rolü (AD1): `owner` | `support` | None. Owner-only uçlar
        #: [require_owner] ile kapılanır; destek personeli okur ve
        #: sınırlı yazar (kredi, cihaz kilidi, bildirim provası).
        self.role = role
        #: Ortaklık kimliği (OP): claim `{partner: true, partnerId: "..."}`.
        #:
        #: ⚠️ `role` ile AYRI BİR BOYUT olması bilinçli. `"partner"`
        #: [ROLES]'a eklenseydi `require_admin`'in `user.role in ROLES`
        #: kapısını geçerdi ve bir ortak token'ı ~25 yönetim okuma ucunu
        #: (tüm kullanıcı listesi, gelir, sistem, DİĞER ortakların
        #: detayları) açardı. Ortak kapısı bu yüzden [require_partner].
        self.partner_id = partner_id


def _verify(token: str) -> dict:
    from firebase_admin import auth as fb_auth

    return fb_auth.verify_id_token(token)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    lang: str = Depends(get_language),
    x_app_build: str | None = Header(default=None),
) -> AuthUser:
    """Oturum doğrulama.

    Dil bağımlılığı yalnızca hata metni için: 401 yanıtının `detail` alanı
    istemcide doğrudan kullanıcıya gösteriliyor, o yüzden kullanıcının dilinde
    olmak zorunda.

    `x_app_build` (PBZ, K10): sürüm aynası. Her kimlikli istek buradan
    geçtiği için `users/{uid}.appBuild` en ucuz burada yazılır; panelin
    "eşiğin altında kaç kişi" sorusunu ve eşik yükseltme doğrulamasını (K9)
    besler. Kapının kendisi (426) middleware'de — burası yalnız ayna.
    """
    if credentials is not None and _init_firebase():
        try:
            # `verify_id_token` bloklayan bir çağrı: imza anahtarları süresi
            # dolduğunda (~6 saatte bir) Google'dan yeniden çekiliyor. `async`
            # bir işlevin içinde doğrudan çağrılırsa o ağ turu boyunca olay
            # döngüsü durur ve TÜM istekler bekler.
            decoded = await run_in_threadpool(_verify, credentials.credentials)
            uid = decoded["uid"]
            # Sentinel tuzağı: bu fonksiyon Depends zinciri DIŞINDAN da
            # çağrılıyor (api/admin.py collect, testler) — o yolda
            # `x_app_build` None DEĞİL, FastAPI'nin truthy `Header` nesnesi
            # olur. Yalnız gerçek başlık dizgisi işlenir. Ayna best-effort
            # ve uid başına günde bir; Firestore yazımı bloklar, havuzda.
            if isinstance(x_app_build, str):
                build = app_gate.parse_build(x_app_build)
                if build and not app_gate.build_remembered(uid, build):
                    await run_in_threadpool(app_gate.remember_build,
                                            uid, build)
            # Arama aynası (AD4): `users/{uid}.{emailLower, usernameLower,
            # nameLower, ...}` sunucu yazımlı; her kimlikli istek en ucuz
            # kanca. `ensure` uid başına 24 saatte bir ve diff-only —
            # hiç fırlatmaz; modül yoksa (henüz dağıtılmadı) sessiz.
            try:
                from services import search_mirror
                await run_in_threadpool(search_mirror.ensure, uid)
            except ImportError:
                pass
            except Exception as exc:
                logger.debug("Arama aynası atlandı (%s): %s", uid, exc)
            return AuthUser(uid=uid, email=decoded.get("email"),
                            phone=decoded.get("phone_number"),
                            admin=decoded.get("admin") is True,
                            auth_time=int(decoded.get("auth_time") or 0),
                            role=_rol_coz(decoded),
                            partner_id=_ortak_coz(decoded))
        except Exception as exc:
            logger.info("Token doğrulanamadı: %s", exc)
            if not config.DEV_MODE:
                raise HTTPException(status_code=401,
                                    detail=text("auth_invalid", lang))

    if config.DEV_MODE:
        # DEV_MODE'un anonim kullanıcısı admin DEĞİLDİR (bir numaralı
        # değişmez): geliştirme kolaylığı yönetim yetkisine dönüşemez.
        # Yerelde admin uçlarını denemek isteyen, ayrı ve AÇIK bir bayrak
        # kaldırır (RYTHO_DEV_ADMIN=1).
        # Rol de ayrı bayraktan (RYTHO_DEV_ROLE, varsayılan owner): destek
        # kapılarını yerelde denemek için `support` verilir.
        dev_rol = (config.DEV_ADMIN_ROLE
                   if config.DEV_ADMIN_ROLE in ROLES else "owner")
        return AuthUser(uid="dev-user", anonymous=True,
                        admin=config.DEV_ADMIN,
                        role=dev_rol if config.DEV_ADMIN else None)

    raise HTTPException(status_code=401, detail=text("auth_required", lang))


def require_admin(user: AuthUser = Depends(get_current_user)) -> AuthUser:
    """Yönetim uçlarının kapısı (W4/AD1): `admin: true` claim'i ŞART.

    Rol (`owner`/`support`) yetkiyi daraltır, vermez — `user.role`
    zaten yalnız admin'lerde dolu (`_rol_coz`).

    403 döner, 401 değil — kimlik geçerli ama yetki yok. Yanıt jenerik
    tutulur; ucun varlığı hakkında ipucu vermez.
    """
    if not (user.admin or user.role in ROLES):
        raise HTTPException(status_code=403, detail="Yetkisiz.")
    return user


def require_owner(user: AuthUser = Depends(require_admin)) -> AuthUser:
    """Sahip kapısı (AD1): yıkıcı/mali/yapılandırma uçları.

    Sil, devre dışı, sürüm eşiği, ortak yazımları, dışa aktarım, yeniden
    hesapla, duyuru, elle toplama. Destek rolü 403 alır — mesaj yine
    jenerik; "sahip gerekir" demek ucun varlığını ve rol modelini sızdırır.
    """
    if user.role != "owner":
        raise HTTPException(status_code=403, detail="Yetkisiz.")
    return user


def require_partner(user: AuthUser = Depends(get_current_user)) -> AuthUser:
    """Ortak kapısı (OP): ortağın KENDİ panelinin tek kapısı.

    `require_admin`'den TAMAMEN BAĞIMSIZ — üstüne binmez, `ROLES`'a
    bakmaz. Ortak yönetim panelinin hiçbir ucunu göremez; yönetici de bu
    kapıdan geçmez (kendi `partnerId`'si yoksa).

    `partnerId` claim'den gelir, İSTEKTEN DEĞİL: ortak başka bir ortağın
    kimliğini gövdede gönderip veri çekemez. Yetki sınırı bu yüzden
    yapısaldır, kontrol listesine bağlı değildir.
    """
    if not user.partner_id:
        raise HTTPException(status_code=403, detail="Yetkisiz.")
    return user

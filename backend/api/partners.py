"""Ortaklık uçları (OP-turu) — ortağın KENDİ paneli + hakediş olgunlaştırma.

Bu modül `api/admin.py`'den AYRIDIR ve bu bilinçlidir. Yönetim uçları
`require_admin`/`require_owner` ile kapılanır; buradaki ortak ucu
`require_partner` ile. İki kapı birbirine binmez:

* Ortak, yönetim panelinin hiçbir ucunu göremez.
* Yönetici de `/me` ucundan geçemez (kendi `partnerId` claim'i yoksa).

`partnerId` **claim'den** gelir, istekten değil — ortak başka bir ortağın
kimliğini gövdede gönderip veri çekemez. Sınır kontrol listesine değil,
yapıya dayanıyor.

⚠️ TEK İSTİSNA: `/click`. Onu çağıran ziyaretçi henüz oturum AÇMAMIŞ bir
yabancıdır, yani kimlik kapısı KURULAMAZ. Kapı yerine üç sınır var
(`partner_service.record_click`): kod biçimi, kodun gerçekten var olması ve
yazımın best-effort olması. Kimliksiz olduğu için kota kovası da ayrıdır
(`core/ratelimit.py`) ve sürüm kapısından muaftır (`core/app_gate.py`).
"""
from __future__ import annotations

import collections
import json
import logging
import time
import secrets as py_secrets

from fastapi import (APIRouter, Depends, Header, HTTPException, Request,
                     Response)
from fastapi.security import HTTPAuthorizationCredentials

from core import config
from core.auth import (AuthUser, get_current_user, require_admin,
                       require_owner, require_partner)
from core.i18n import get_language
from services import partner_service

router = APIRouter()
logger = logging.getLogger(__name__)

#: Tıklama gövdesinin üst sınırı (bayt). Beklenen gövde ~30 bayt; kapı
#: kimliksiz bir uca megabaytlık gövde pompalamayı ucuzlatmamak için var.
_TIKLAMA_GOVDE_SINIRI = 1024

#: Kod başına dakikalık tıklama tavanı (süreç içi).
#:
#: NEDEN IP KOVASI YETMİYOR (ölçüldü): `core/ratelimit._client_key`
#: anahtarı `x-forwarded-for`un İLK öğesinden alıyor, Google'ın yük
#: dengeleyicisi ise istemcinin gönderdiği XFF'in SONUNA ekliyor —
#: yani o ilk öğe çağıranın denetiminde. Her isteğe farklı bir XFF
#: yazan istemci her istekte yeni bir kova açar ve dakikalık tavan hiç
#: devreye girmez. Kimlikli uçlarda bunun bedeli yok (istek zaten
#: 401'leniyor); burada bedel FATURA: istek başına 1 okuma + 2
#: Firestore yazımı ve uç herkese açık.
#:
#: Bu tavan KODA bağlı, yani taşıyıcıdan (IP/başlık) bağımsız ve
#: sahtelenemez: kod gövdede ve doğrulanıyor.
#:
#: 600/dk bilinçli yüksek: gerçek bir tanıtım anını kırpmamalı.
#: Aşıldığında tıklama SAYILMAZ ama ziyaretçi etkilenmez (sayfa yanıtı
#: zaten okumuyor) — ve sessiz kalmasın diye warning düşüyor.
_KOD_TIKLAMA_TAVANI = 600
_KOD_TIKLAMA_PENCERESI = 60.0

#: kod → son pencere içindeki tıklama zaman damgaları.
_kod_vurus: dict[str, collections.deque] = collections.defaultdict(
    collections.deque)


def _kod_kotasi_musait(kod: str) -> bool:
    """Kod başına dakikalık tavan. Süreç içi — `ratelimit` ile aynı
    doktrin (Cloud Run çoklu instance'ta tavan instance başınadır ve bu
    kabul: amaç kesin bir kota değil, sınırsız faturayı kapatmak).
    """
    simdi = time.monotonic()
    vurus = _kod_vurus[kod]
    while vurus and simdi - vurus[0] > _KOD_TIKLAMA_PENCERESI:
        vurus.popleft()
    # Sözlük sınırsız büyümesin: boşalan kod kaydı atılır.
    if not vurus and len(_kod_vurus) > 5000:
        _kod_vurus.pop(kod, None)
        _kod_vurus[kod].append(simdi)
        return True
    if len(vurus) >= _KOD_TIKLAMA_TAVANI:
        logger.warning(
            "Tiklama tavani asildi, sayilmadi (kod=%s, tavan=%s/dk)",
            kod, _KOD_TIKLAMA_TAVANI)
        return False
    vurus.append(simdi)
    return True


async def _tiklama_govdesi(request: Request) -> bytes:
    """Gövdeyi EN ÇOK `_TIKLAMA_GOVDE_SINIRI` bayt okur; aşan istek kesilir.

    ⚠️ `await request.body()` DEĞİL, ve gerekçe ölçüldü: o çağrı gövdenin
    TAMAMINI belleğe alır, sınır ancak sonra bakılır. `Content-Length`
    başlığı ZORUNLU değildir (`Transfer-Encoding: chunked`) ve o hâlde
    aşağıdaki başlık kapısı hiç çalışmaz — ölçümde 2 MB'lık chunked bir
    gövde uca kadar gelip tamamen tamponlandı, yalnız yazım engellendi.
    Kimliksiz ve herkese açık bir uçta bellek maliyetini istemcinin
    seçimine bırakmak, kotanın tavan olmasını boşa çıkarır.

    Sınır aşılırsa **boş** döner: çağıran onu "kod yok" gibi ele alır,
    yani 1 KB'ı aşan istek 204 alır ama hiçbir şey yazdırmaz.
    """
    parcalar = bytearray()
    async for parca in request.stream():
        parcalar.extend(parca)
        if len(parcalar) > _TIKLAMA_GOVDE_SINIRI:
            return b""
    return bytes(parcalar)


@router.post("/click", status_code=204)
async def click(request: Request) -> Response:
    """Ortak linkinin açıldığını sayar — KİMLİKSİZ, her hâlde 204.

    Ziyaretçi oturum açmamıştır; kimlik istenemez. Yanıt her zaman gövdesiz
    204: kodun geçersiz ya da hiç var olmadığı bilgisi bile SIZDIRILMAZ
    (404 ile 204 ayrımı, kod tahmin etmeyi ucuz bir oyuna çevirirdi) ve
    telemetri ziyaretçinin mağazaya gitmesini hiçbir koşulda engellemez.

    ⚠️ GÖVDE ELLE AYRIŞTIRILIYOR, Pydantic modeliyle DEĞİL. Gerekçe
    ölçülebilir bir tuzak: `navigator.sendBeacon(url, "…")` gövdeyi
    `text/plain` içerik türüyle gönderir ve FastAPI JSON olmayan içerik
    türünde ham baytları modele vermeye çalışıp **422** döner. O hâlde
    sayaç sessizce ölürdü — sayfa hata görmez (beacon yanıtı okunmaz),
    ortak "kimse tıklamıyor" sanır. Model burada isteği düşürebilecek tek
    şeydi; kaldırıldı.

    ⚠️ GİZLİLİK: istekten YALNIZ `code` okunuyor. IP, User-Agent, çerez ve
    kimlik hiçbir yere yazılmaz — `record_click` tek bir sayaç artırır.
    Tam olmak için: kota katmanı (`core/ratelimit.py`) ziyaretçinin IP'sini
    kova anahtarı olarak BELLEKTE tutar — kota penceresi 60 sn ama budama
    beş dakikada bir koştuğu için kayıt o kadar kalabilir. Hiçbir
    kalıcı yere gitmez ve bu uca özel değildir — kimliksiz her istek öyle
    sayılıyor. "Saklanan tek şey bir sayaç" sözü kalıcı veri içindir.
    """
    # Önce başlık: gövdeyi hiç belleğe almadan reddedilebilen hâl.
    uzunluk = request.headers.get("content-length")
    if uzunluk and uzunluk.isdigit() and int(uzunluk) > _TIKLAMA_GOVDE_SINIRI:
        return Response(status_code=204)

    kod = ""
    try:
        govde = await _tiklama_govdesi(request)
        if govde:
            veri = json.loads(govde)
            if isinstance(veri, dict):
                kod = str(veri.get("code") or "")
    except Exception:
        # Bozuk JSON, eksik gövde, kopmuş bağlantı: hepsi sayılmayan bir
        # tıklama. Uç yine 204 döner — buradan 4xx dönmek, tarayıcı
        # konsoluna hata basıp ziyaretçiyi ürkütmekten başka iş yapmaz.
        kod = ""

    if kod and _kod_kotasi_musait(kod):
        # Servis ASLA fırlatmaz; dönen değer yalnız testin ölçtüğü şey.
        partner_service.record_click(kod)
    return Response(status_code=204)


@router.get("/me")
def partner_me(user: AuthUser = Depends(require_partner)):
    """Ortağın kendi panosu: huni + bakiye + kodlar + ödeme geçmişi.

    Dönen şekil `partner_service.partner_self_view` ile DAR tutulur —
    atfedilen gelir, kullanıcı kimlikleri ve diğer ortaklar dışarı
    çıkmaz. Ortağın görmesi gereken tek şey kendi performansı.
    """
    try:
        # `user.uid` ŞART: claim tek başına yetmez. `partner_self_view`
        # bağı kaynaktan doğruluyor, yani uid değiştirilmiş bir ortağın
        # ESKİ hesabındaki bayat claim bir sonraki istekte düşüyor —
        # Firebase'in bir saate kadar süren jeton gecikmesini beklemeden.
        return partner_service.partner_self_view(user.partner_id, user.uid)
    except partner_service.RedeemError as exc:
        if exc.reason in partner_service.TRANSIENT_REASONS:
            # GEÇİCİ hata KALICI yetki kaybı gibi görünmemeli. Ölçülen hâl:
            # soğuk bir Cloud Run örneğinde ADC henüz çözülmemişken
            # `core.firestore.get_client()` None döner (orada kalıcı mandal
            # BİLEREK kurulmuyor) ve servis "unavailable" fırlatır. Bu 403
            # olarak çıktığında pano zorunlu çıkış yapıp jenerik 404 basıyor;
            # ortak hesabının kapatıldığını sanıyor, F5 ile düzeliyor ve
            # olay hiçbir yerde hata olarak görünmüyor.
            #
            # Gövdedeki `code` makine-okur: istemci "tekrar dene" ile
            # "yetkin yok"u metne bakmadan ayırt edebilsin.
            logger.warning("Ortak panosu gecici olarak verilemedi (%s): %s",
                           user.partner_id, exc.reason)
            raise HTTPException(
                status_code=503,
                detail={"code": "temporarily_unavailable",
                        "reason": exc.reason},
                headers={"Retry-After": "2"})
        # KALICI hâl: claim var ama ortak kaydı yok (silinmiş ya da hiç
        # açılmamış). Jenerik 403 — "kayıt yok" demek silinmiş bir ortağa
        # sistemin şeklini anlatır.
        #
        # ⚠️ PASİF ortak buraya DÜŞMEZ (ölçüldü): `partner_detail` yalnız
        # doküman YOKKEN 404 fırlatıyor, `active: false` kontrolü hiçbir
        # yerde yok. Pasif ortak panoyu 200 ve tam veriyle görmeye devam
        # eder ve bu BİLİNÇLİ: neden kazanmadığını görmesi gerekir —
        # `active: false` alanı, duran kodları ve düşen kayıt sayısı
        # (`voidCount`) dar görünümde ona da veriliyor. Kapıyı kapatmak
        # yerine kazanmadığını göstermek, açıklanabilir olan yol.
        logger.info("Ortak panosu verilemedi (%s): %s",
                    user.partner_id, exc.reason)
        raise HTTPException(status_code=403, detail="Yetkisiz.")


@router.post("/mature")
async def mature(
    authorization: str | None = Header(default=None),
    lang: str = Depends(get_language),
):
    """Süresi dolan hakedişleri kesinleştirir — ÇİFT KAPI: sır VEYA owner.

    `Depends(get_current_user)` BİLEREK yok; gerekçesi `admin.py`'deki
    `/collect` ucuyla aynı: Cloud Scheduler'ın `Authorization` başlığı
    Bearer değil HAM sır taşır ve dependency zinciri isteği kapıya
    gelmeden 401'ler.

    İdempotent: iş durum alanı üzerinden çalışır (`pending` → `qualified`),
    `Increment` kullanmaz. İki kez koşarsa ikinci koşu aynı dokümanı
    `pending` bulamaz.

    Kaçırılan gün kendiliğinden telafi olur: sorgu "≥15 gün olmuş VE hâlâ
    beklemede" biçiminde. Zamanlayıcıda yeniden deneme yok
    (`infra/create-scheduler.ps1` bunu açıkça yazıyor), telafi bu yüzden
    sorgunun kendisine gömülü.
    """
    if not _scheduler_gecerli(authorization):
        kimlik_bilgisi = None
        if authorization and authorization.startswith("Bearer "):
            kimlik_bilgisi = HTTPAuthorizationCredentials(
                scheme="Bearer", credentials=authorization[7:])
        kullanici = await get_current_user(credentials=kimlik_bilgisi,
                                           lang=lang)
        require_owner(require_admin(kullanici))

    try:
        sayac = partner_service.mature_qualifications()
    except partner_service.RedeemError as exc:
        # Geçici sınıf 500 değil 503 (aynı ayrım `/me`de): kimlik bilgisi
        # henüz çözülmemiş bir örnek kalıcı sunucu kusuru gibi
        # raporlanmasın — zamanlayıcıda yeniden deneme yok, telafi bir
        # sonraki koşudan gelir ve o koşu aynı kayıtları bulur.
        durum = (503 if exc.reason in partner_service.TRANSIENT_REASONS
                 else exc.status)
        raise HTTPException(status_code=durum, detail=exc.reason)
    return {"status": "ok", **sayac}


def _scheduler_gecerli(authorization: str | None) -> bool:
    """Scheduler sırrı doğru mu — yoksa/uyuşmuyorsa sessizce False.

    `admin.py:_scheduler_gecerli`in ikizi. Kopya bilinçli: iki modül
    birbirine bağımlı olmasın ve kapı mantığı okunduğu yerde dursun
    (`api/maintenance.py` de aynı deseni kopyalıyor).
    """
    return bool(
        config.NOTIFY_SCHEDULER_SECRET
        and authorization
        and py_secrets.compare_digest(authorization,
                                      config.NOTIFY_SCHEDULER_SECRET)
    )

"""Zamanlanmış bakım uçları: sohbet arşivi temizliği + burç yorumu ısıtması.

Cloud Scheduler çağırır (bkz. infra/create-scheduler.ps1, `rytho-cleanup` ve
`rytho-horoscope-warm-*`). Güven modeli bildirim zamanlayıcısıyla AYNI:
paylaşılan gizli anahtar `Authorization` başlığında, anahtar tanımsızken uç
kapalı (fail-closed).

## Neden native Firestore TTL değil

TTL politikası yalnızca `conversations/{id}` dokümanını siler; `messages/*`
alt koleksiyonu YETİM kalır — sonsuza dek faturalanır ve `write: false`
kuralı yüzünden sahibi de silemez. Buradaki temizlik mesajları ÖNCE, konuyu
SONRA siler.

## Neden ısıtma BU modülde

Isıtma uçtan bakıldığında bir rapor ucu değil, bakım işidir: dönen metin
kullanılmaz, atılır. `api/reports.py` altında olsaydı sürüm kapısının
(`core/app_gate.py`) muaf önekleri arasında OLMAZDI ve eşik > 0 yazıldığı
gün zamanlayıcı 426 yiyip ısıtma SESSİZCE ölürdü — tam olarak `/partners/`
önekinde yaşanan kusur.
"""
from __future__ import annotations

import datetime as dt
import logging
import secrets
import time
from typing import Literal, get_args

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.security import HTTPAuthorizationCredentials
from starlette.concurrency import run_in_threadpool

from api.reports import SignName
from core import config, i18n
from core.auth import get_current_user, require_admin, require_owner
from core.i18n import get_language
from services import chat_history, prompts, report_service
from services.sky_service import get_sky_now

logger = logging.getLogger(__name__)
router = APIRouter()

#: Isıtılacak burçlar — TEK KAYNAK, ucun kendi tanımı (`/reports/horoscope`).
#: Burada ayrı bir liste tutulsaydı sapma SESSİZ olurdu: listeden düşen burcun
#: önbelleği soğuk kalır, o burcun ilk kullanıcısı tam zinciri yine bekler ve
#: hiçbir yerde hata görünmez. Isıtılması gereken küme, ucun kabul ettiği
#: kümenin TA KENDİSİ olmak zorunda.
BURCLAR: tuple[str, ...] = get_args(SignName)

#: Dönem — `/reports/horoscope`un kabul ettiği üçlüyle aynı. FastAPI
#: doğrulaması statik bir Literal istediği için `report_service._HOROSCOPE_TTL`
#: anahtarlarından türetilemiyor; ikisinin aynı kaldığı testle çivilenir
#: (tests/test_horoscope_warm.py).
Donem = Literal["daily", "weekly", "monthly"]

#: Döngünün KENDİNİ kesme payı (saniye).
#:
#: Gerçek duvar Cloud Scheduler'ın `--attempt-deadline 900s`ı DEĞİL —
#: `infra/deploy-backend.ps1` servisi `--timeout 300` ile dağıtıyor, yani
#: isteği 300. saniyede **Cloud Run** öldürür. Bu pay olmadan uzun bir gece
#: şöyle biterdi: istek ortada kesilir, `logger.info` satırı HİÇ basılmaz,
#: "hiçbir şey ısınmadı" 503'ü HİÇ dönmez ve Scheduler günlüğünde yalnız
#: gövdesiz bir zaman aşımı kalır — yani tam olarak görünmez ölüm.
#: Payla birlikte uç kendi duvarına çarpmadan döner ve hangi (burç/dil)
#: ikililerinin soğuk kaldığını ADIYLA söyler.
#:
#: ⚠️ 24 üretimin gerçek süresi ÖLÇÜLMEDİ (canlı Gemini gecikmesine ve
#: fact_guard'ın ikinci turuna bağlı). Bu sayı bir ölçüm değil, duvarın
#: altında kalma payıdır; ilk gerçek koşudan sonra `atlanan` sayacına
#: bakılıp ya pay ya iş bölümü ayarlanır.
_VARSAYILAN_BUTCE_SN = 240


def _simdi_utc() -> dt.datetime:
    """Dolaylı saat — `core/app_gate._now` deseninin aynısı.

    Doğrudan `dt.datetime.now` çağrılsaydı "yerel gün dönüşünden SONRA
    ısıtılıyor mu" sorusu testte ÖLÇÜLEMEZDİ; ve ölçülemeyen bir kapı,
    bir sonraki düzenlemede sessizce kayar (ısıtma koşar, dünün kovasını
    doldurur, sabah ilk açan kullanıcı yine bekler).
    """
    return dt.datetime.now(dt.timezone.utc)


def _scheduler_gecerli(authorization: str | None) -> bool:
    """Scheduler sırrı doğru mu — yoksa/uyuşmuyorsa sessizce False.

    `admin.py` ve `partners.py`deki ikizlerinin kopyası. Fırlatmaz, çünkü
    ısıtma ucunda ikinci kapı (owner claim'i) hâlâ denenecek.

    ``isascii`` kapısı ÖLÇÜLDÜ (2026-10-02): başlıklar latin-1 çözülüyor ve
    `compare_digest` ASCII olmayan DİZELERİ karşılaştırmayı reddediyor
    (`TypeError`). Son baytı 0xE9 olan bir `Authorization` yollayan
    KİMLİKSİZ istek 401 değil **500** alıyordu — gerçek kapı maskeleniyor,
    üstelik kimliksiz bir çağıran sunucu günlüğüne istediği kadar yığın izi
    yazdırabiliyor. Sır Secret Manager'da base64, yani zaten ASCII; eleme
    kaybı yok. ⚠️ Aynı kusur `admin.py` ve `partners.py` ikizlerinde DURUYOR
    (bu turun paketi dışı).
    """
    return bool(
        config.NOTIFY_SCHEDULER_SECRET
        and authorization
        and authorization.isascii()
        and secrets.compare_digest(authorization,
                                   config.NOTIFY_SCHEDULER_SECRET)
    )


def _verify_scheduler(authorization: str | None) -> None:
    """Yalnız sır kapısı: 503 (anahtar yok) / 401 (anahtar yanlış)."""
    if not config.NOTIFY_SCHEDULER_SECRET:
        logger.error("NOTIFY_SCHEDULER_SECRET tanimsiz; bakim ucu reddedildi.")
        raise HTTPException(status_code=503,
                            detail="Bakim zamanlayicisi yapilandirilmamis.")
    if not _scheduler_gecerli(authorization):
        raise HTTPException(status_code=401,
                            detail="Gecersiz zamanlayici anahtari.")


@router.post("/cleanup")
def cleanup(
    dry_run: bool = Query(default=False),
    limit: int = Query(default=300, ge=1, le=1000),
    authorization: str | None = Header(default=None),
):
    """30 gündür kullanılmayan konuşmaları mesajlarıyla siler.

    `dry_run=true` yalnızca sayar — politika değişikliklerinde "kaç konu
    gidecek" sorusuna silmeden cevap verir.
    """
    _verify_scheduler(authorization)
    try:
        sonuc = chat_history.purge_expired(limit=limit, dry_run=dry_run)
    except Exception as exc:
        logger.exception("Temizlik koşturulamadı", exc_info=exc)
        raise HTTPException(status_code=500, detail="Temizlik basarisiz.")
    return {"status": "success", "dry_run": dry_run, **sonuc}


def _isit(period: str, hedef_gun: dt.date, butce_sn: float
          ) -> tuple[dict[str, int], list[str], list[str], list[str],
                     str | None]:
    """Senkron ısıtma döngüsü: (sayaç, düşenler, atlananlar,
    yazılamayanlar, kova).

    Her burç AYRI try/except: biri patlayınca kalan 23'ü kaybetmemek için.

    SIRAYLA koşar, eşzamanlı değil: 24 üretimi paralel atmak Gemini'de
    kotaya çarpar ve bu depoda tek bir 429 daha önce sağlayıcı başına 11
    isteğe kadar yeniden deneme doğurdu (istemci tarafında ölçüldü; aynı
    kusur sunucuda da kotayı kendi besler).

    ``butce_sn`` dolunca döngü KENDİNİ keser ve kalanları `atlanan` sayar.
    Gerekçesi `_VARSAYILAN_BUTCE_SN`de: duvar 900s değil, Cloud Run'ın
    300s istek zaman aşımı. Sıralı koşunun o duvarın altında kaldığı
    ÖLÇÜLMEDİ — bu yüzden kesinti "olmayacak" varsayılmıyor, SAYILIYOR.

    Kesintinin kurbanı sırayla son dil olur (`i18n.SUPPORTED` = tr, en),
    yani önce Türkçe ısınır. Türkiye-öncelikli lansmanda bu BİLİNÇLİ:
    sıra burç-başına çevrilse kesinti her iki dilden eşit yerdi ve hiçbir
    dil tam ısınmazdı.
    """
    gokyuzu_ham = get_sky_now()
    # `toplam` denenen değil HEDEFLENEN kombinasyon sayısıdır: bütçe kesintisi
    # toplamı küçültürse "24'te 24 ısındı" gibi görünüp kesintiyi saklardı.
    sayac = {"toplam": len(BURCLAR) * len(i18n.SUPPORTED),
             "isinan": 0, "zaten_sicak": 0, "dusen": 0, "atlanan": 0,
             "yazilamayan": 0}
    dusenler: list[str] = []
    atlananlar: list[str] = []
    yazilamayanlar: list[str] = []
    kova: str | None = None
    bitis = time.monotonic() + butce_sn

    for dil in i18n.SUPPORTED:
        # Gökyüzü yükü dil başına BİR kez yerelleştirilir: hesap paylaşımlı
        # önbellekten geliyor, çeviri yanıt üretilirken yapılıyor.
        gokyuzu = prompts.localize_sky(dil, gokyuzu_ham)
        for burc in BURCLAR:
            if time.monotonic() >= bitis:
                sayac["atlanan"] += 1
                atlananlar.append(f"{burc}/{dil}")
                continue
            try:
                sonuc = report_service.horoscope_reading(
                    burc, period, gokyuzu, lang=dil, today=hedef_gun)
            except Exception as exc:
                sayac["dusen"] += 1
                dusenler.append(f"{burc}/{dil}")
                logger.warning("Burc yorumu isitilamadi (%s/%s/%s): %s",
                               burc, period, dil, exc)
                continue
            kova = sonuc.get("generated_for") or kova
            if sonuc.get("fallback"):
                # Yedek metin önbelleğe YAZILMAZ (`_cached_generate`), yani
                # fallback'e düşen bir tur HİÇBİR ŞEYİ ısıtmamıştır. Onu
                # başarı saymak, ölçülen düşüşü yanlış adla sunmak olurdu.
                sayac["dusen"] += 1
                dusenler.append(f"{burc}/{dil}")
            elif sonuc.get("cached"):
                # ⚠️ Bu dalın ölçtüğü şey "okunabildi", "PAYLAŞIMLI
                # katmanda duruyor" DEĞİL: `cache.get` önce belleğe bakar
                # ve aynı instance'ta bir önceki koşunun yazdığı değeri
                # bulabilir. Haftalık/aylık işler her gece koştuğu için bu
                # gerçek bir olasılık. Katmanı ayırt etmek `cache.get`in
                # dönüş şeklini değiştirmeyi gerektirir (depodaki TÜM
                # okuyucular); yapılmadı, bu yüzden ad mütevazı tutuldu.
                sayac["zaten_sicak"] += 1
            elif not sonuc.get("persisted"):
                # ÖLÇÜLDÜ (2026-10-02): üretim oldu ama PAYLAŞIMLI katmana
                # yazılamadı. `cache.set` kalıcı katman hatasını fail-open
                # yutuyor (bilerek — bir Firestore hıçkırığı kullanıcının
                # raporunu düşürmemeli) ve eskiden hiçbir şey SÖYLEMİYORDU:
                # bu uç "isinan: 24" + HTTP 200 dönerken yalnız BU
                # instance'ın belleği dolmuş olabiliyordu (max-instances 3).
                # Isıtmanın tek amacı paylaşımlı önbelleği doldurmak
                # olduğuna göre öyle bir tur HİÇBİR ŞEY ısıtmamıştır —
                # üstelik 24 Gemini üretiminin faturasını yazmıştır.
                #
                # `dusen`den AYRI sayılıyor çünkü çareleri bambaşka: biri
                # Gemini/kota, bu ise Firestore izni/kotası. İkisini tek
                # sayaçta toplamak ölçüleni yanlış adla sunmak olurdu.
                sayac["yazilamayan"] += 1
                yazilamayanlar.append(f"{burc}/{dil}")
            else:
                # `isinan` artık "ÜRETİLDİ **ve** kalıcı katmana YAZILDI".
                sayac["isinan"] += 1
    return sayac, dusenler, atlananlar, yazilamayanlar, kova


@router.post("/horoscope-warm")
async def horoscope_warm(
    period: Donem = Query(default="daily"),
    offset_minutes: int = Query(default=0, ge=-720, le=840),
    budget_seconds: int = Query(default=_VARSAYILAN_BUTCE_SN,
                                ge=10, le=3000),
    authorization: str | None = Header(default=None),
    lang: str = Depends(get_language),
):
    """Genel burç yorumunu ÖN-ÜRETİR; dönen metin kullanılmaz, ATILIR.

    Tek amaç paylaşımlı önbelleği doldurmak. Mimari zaten doğruydu — anahtar
    (burç, dönem, tarih kovası, dil), doküman SAHİPSİZ, TTL kova süresiyle
    hizalı (`services/report_service.py`) — eksik olan ÖN-ÜRETİMDİ. Ölçülen
    bedel: her dörtlünün İLK isteyeni şu zinciri tam tamına bekliyordu —
    RAG embedding çağrısı, Gemini üretimi (ilk deneme 2048 token, tutmazsa
    ikinci deneme) ve fact_guard uydurma yakalarsa bir LLM turu daha.
    Günlük yorumda bu, GÜNDE 24 kullanıcı eder (12 burç x 2 dil) ve bunlar
    rastgele değil SABAH İLK AÇANLARdır.

    ``offset_minutes`` NEDEN var: kova isteğin sahibinin YEREL gününe bağlı
    (`api/reports.py` -> `entitlements.user_local_date`). Sunucu UTC'de
    çalışıyor; burada `dt.date.today()` kullanılsaydı yerel günü dönmüş
    ülkeler için YANLIŞ kova ısıtılırdı — Türkiye'de (UTC+3) yerel gün
    21:00 UTC'de döner, yani 21:15'teki iş hâlâ dünün kovasını doldurur ve
    sabah ilk açan kullanıcı yine bekler. İş bu yüzden 180 geçiyor.
    Varsayılan 0 (saf UTC): tek bir ülkeyi sunucuya sessizce gömmek, elle
    tetikleyen operatörün hangi kovayı doldurduğunu bilmemesi demekti.

    ``Depends(get_current_user)`` BİLEREK yok ve kapı ÇİFT: sır VEYA owner.
    Gerekçesi `admin.py:/collect` ve `partners.py:/mature` ile aynı —
    zamanlayıcının `Authorization` başlığı Bearer değil HAM sır taşır,
    dependency zinciri isteği kapıya gelmeden 401'ler. ``lang`` yalnız o
    kapının hata metni için; ISITILAN diller istekten DEĞİL
    `i18n.SUPPORTED`ten gelir (bir istemcinin Accept-Language'ı ısıtma
    kapsamını daraltmamalı).

    ``budget_seconds`` NEDEN var: gerçek duvar Cloud Run'ın 300s istek
    zaman aşımıdır (`infra/deploy-backend.ps1`), Scheduler'ın 900s
    attempt-deadline'ı değil. Bütçe olmadan uzun bir gece hiçbir iz
    bırakmadan kesilirdi — ne log satırı ne 503. Bkz.
    `_VARSAYILAN_BUTCE_SN`.

    Döngünün kendisi ve dayanıklılık gerekçeleri `_isit` içinde.
    """
    if not _scheduler_gecerli(authorization):
        kimlik_bilgisi = None
        if authorization and authorization.startswith("Bearer "):
            kimlik_bilgisi = HTTPAuthorizationCredentials(
                scheme="Bearer", credentials=authorization[7:])
        kullanici = await get_current_user(credentials=kimlik_bilgisi,
                                           lang=lang)
        require_owner(require_admin(kullanici))

    hedef_gun = (_simdi_utc() + dt.timedelta(minutes=offset_minutes)).date()

    # Gövde İŞ PARÇACIĞINDA koşar. `horoscope_reading` ağ çağrılarını
    # SENKRON yapıyor (RAG embedding + Gemini) ve 24 üretim dakikalar
    # sürüyor; async uçta doğrudan çağrılsaydı olay döngüsü o süre boyunca
    # kilitlenir ve aynı instance'a gelen HER istek (kullanıcı trafiği,
    # health check) ısıtma bitene kadar beklerdi. Uç async kalmak ZORUNDA,
    # çünkü ikinci kapı (`get_current_user`) awaitable.
    try:
        (sayac, dusenler, atlananlar, yazilamayanlar,
         kova) = await run_in_threadpool(
            _isit, period, hedef_gun, float(budget_seconds))
    except Exception as exc:
        # Buraya yalnız döngünün DIŞINDAKİ hata düşer (gökyüzü hesabı):
        # burç başına hatalar sayaçta tutuluyor. Isıtılacak hiçbir şey
        # yokken 200 dönmek koşuyu Scheduler günlüğünde BAŞARILI gösterirdi.
        logger.exception("Isitma kosturulamadi", exc_info=exc)
        raise HTTPException(status_code=503, detail="Isitma basarisiz.")

    logger.info(
        "Burc isitmasi (%s, kova %s): %d isindi, %d zaten sicak, %d dustu, "
        "%d atlandi, %d yazilamadi",
        period, kova or hedef_gun.isoformat(), sayac["isinan"],
        sayac["zaten_sicak"], sayac["dusen"], sayac["atlanan"],
        sayac["yazilamayan"])
    if yazilamayanlar:
        # Bu satır OLMADAN kusur tamamen görünmezdi: üretim parası ödendi,
        # paylaşımlı önbellek boş kaldı, sabah ilk açan yine bekledi.
        logger.warning(
            "Isitma kalici katmana yazilamadi; %d kombinasyon paylasimli "
            "onbellege girmedi: %s",
            len(yazilamayanlar), ", ".join(yazilamayanlar))
    if atlananlar:
        # Bütçe doldu: kalanlar bu gece SOĞUK kaldı ve zamanlayıcıda yeniden
        # deneme yok. Adlarıyla loglanır — "ısıtma yavaşlıyor" sezgisi değil,
        # hangi kombinasyonun beklediği ÖLÇÜLEN bilgi olsun.
        logger.warning(
            "Isitma butcesi (%ss) doldu; %d kombinasyon soguk kaldi: %s",
            budget_seconds, len(atlananlar), ", ".join(atlananlar))

    yanit = {"status": "ok", "period": period, "bucket": kova,
             "local_date": hedef_gun.isoformat(), **sayac,
             "dusenler": dusenler, "atlananlar": atlananlar,
             "yazilamayanlar": yazilamayanlar}
    if atlananlar:
        # Yarım kalan koşu da BAŞARISIZDIR: gövde Scheduler günlüğüne
        # düşmüyor, yalnız durum kodu düşüyor. 200 dönülse yarım ısınmış bir
        # gece yeşil görünür ve bütçenin/iş bölümünün ayarlanması gerektiği
        # hiç fark edilmez. 503'ün bedeli yok — yeniden deneme yapılmıyor.
        yanit["status"] = "incomplete"
        raise HTTPException(status_code=503, detail=yanit)
    if sayac["isinan"] == 0 and sayac["zaten_sicak"] == 0:
        # Hiçbir kombinasyon sıcak değilse koşu BAŞARISIZDIR. 503 bir telafi
        # DEĞİL (zamanlayıcıda yeniden deneme yok, bkz. create-scheduler.ps1)
        # yalnız GÖRÜNÜRLÜK: aksi halde tamamen boşa koşan bir gece
        # Scheduler günlüğünde yeşil görünür ve ısıtmanın öldüğü hiç
        # fark edilmez.
        raise HTTPException(status_code=503, detail=yanit)
    return yanit

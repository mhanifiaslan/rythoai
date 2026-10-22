import logging
from typing import Literal, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field

from core import cache
from core.ai_consent import ai_katmani_acik
from core.auth import AuthUser, get_current_user
from core.entitlements import is_subscriber, user_local_date
from core.i18n import default_name, get_language
from core.messages import text
from services import astro_service, chart_context, profile_service, prompts

logger = logging.getLogger(__name__)
router = APIRouter(dependencies=[Depends(get_current_user)])


def _internal(exc: Exception, uç: str, lang: str) -> HTTPException:
    """İstisnayı loglar, kullanıcıya sabit metinle döner (bkz. api/reports.py)."""
    logger.exception("%s ucunda hata", uç, exc_info=exc)
    return HTTPException(status_code=500, detail=text("internal", lang))


class BirthData(BaseModel):
    # Boş = dile göre varsayılan hitap (`i18n.default_name`); sabit "Gezgin"
    # İngilizce kullanıcıya Türkçe ad veriyordu.
    name: str = ""
    year: int = Field(ge=1200, le=2100)
    month: int = Field(ge=1, le=12)
    day: int = Field(ge=1, le=31)
    hour: int = Field(default=12, ge=0, le=23)
    minute: int = Field(default=0, ge=0, le=59)
    city: str = "Istanbul"
    nation: Optional[str] = None
    hour_known: bool = True


class NatalChartRequest(BirthData):
    zodiac_type: Literal["Tropical", "Sidereal"] = "Tropical"


class SynastryRequest(BaseModel):
    person1: BirthData
    person2: BirthData


def _birth_kwargs(d: BirthData, lang: str) -> dict:
    return dict(
        name=d.name or default_name(lang), year=d.year, month=d.month, day=d.day,
        hour=d.hour, minute=d.minute, city=d.city, nation=d.nation,
        hour_known=d.hour_known,
    )


@router.post("/natal-chart")
def natal_chart(data: NatalChartRequest, lang: str = Depends(get_language)):
    try:
        chart = astro_service.get_natal_chart(
            **astro_service.subject_kwargs(_birth_kwargs(data, lang)),
            zodiac_type=data.zodiac_type,
            hour_known=data.hour_known,
        )
        return {"status": "success", "data": prompts.localize_chart(lang, chart)}
    except Exception as e:
        raise _internal(e, "natal-chart", lang)


@router.post("/natal-chart/svg")
def natal_chart_svg(
    data: NatalChartRequest,
    theme: str = Query("dark", pattern="^(classic|dark|dark-high-contrast|light)$"),
    lang: str = Depends(get_language),
):
    try:
        # Öğle dolgusuyla çizilen ev çarkını "senin haritan" diye sunmak
        # veri uydurmaktır. Flutter çarkı JSON'dan çizer; SVG uç eski.
        if not data.hour_known:
            raise HTTPException(
                status_code=422,
                detail=prompts.get(lang).ASTRO_NOTES["natal_hour_unknown"])
        svg = astro_service.get_natal_chart_svg(
            **astro_service.subject_kwargs(_birth_kwargs(data, lang)),
            zodiac_type=data.zodiac_type, theme=theme
        )
        return Response(content=svg, media_type="image/svg+xml")
    except Exception as e:
        raise _internal(e, "natal-chart/svg", lang)


@router.post("/transits")
def transits(data: BirthData, lang: str = Depends(get_language)):
    """Bugünün gökyüzünün BU haritaya değdiği noktalar + çapraz açılar.

    HA8: Harita İnceleme'nin bi-wheel görünümü buradan beslenir; yanıt
    artık HA1 sözleşmesiyle yerelleştirilir (kararlı anahtar + *_local).
    Not: `transiting_points[].house_no` Greenwich öznesinin artefaktıdır
    ve İSTEMCİDE atılır (ChartData.fromTransits) — transit gezegene ev
    iddia etmek "ölçülmeyen söylenmez" ihlali olurdu.
    """
    try:
        result = astro_service.get_transits(
            **astro_service.subject_kwargs(_birth_kwargs(data, lang)),
            hour_known=data.hour_known,
        )
        return {"status": "success",
                "data": prompts.localize_transits(lang, result)}
    except Exception as e:
        raise _internal(e, "transits", lang)


#: Takvim ufku: 90 → 30 gün (R5-6, kullanıcı kararı). 90 gün bir liste
#: ekranında anlamlıydı; takvim ana ekranda yatay bir şeride dönüşünce
#: kaydırılabilir uzunluk 30 güne indi. Hesap LLM'siz, maliyet yalnız CPU.
TRANSIT_CALENDAR_DAYS = 30


@router.get("/transit-calendar")
def transit_calendar(user: AuthUser = Depends(get_current_user),
                     lang: str = Depends(get_language),
                     ai: bool = True,
                     x_app_build: str | None = Header(default=None)):
    """Kişisel transit takvimi (T3/R2-Z1/R5-6): 30 günün kesinleşmeleri ve
    istasyonları, tema + ton etiketiyle.

    Jeton YOK — LLM çağrısı olmayan ham hesap. Doğum verisi istekten değil
    PROFİLDEN gelir: takvim "senin haritan" iddiasında olduğu için yalnızca
    gerçekten girilmiş doğum kaydıyla üretilir (chart_context kuralı).
    Önbellek doğum verisine anahtarlı ve dilden bağımsız: aynı doğum
    bilgisine sahip herkes aynı ham takvimi paylaşır, adlar yanıt anında
    isteğin dilinde kurulur. Tema/ton (sinyal kartlarıyla aynı tablolar)
    determinist olduğu için önbelleğe zenginleştirilmiş HALİ girer.

    ## Ücretsiz katman (R5-6)

    Uç artık `require_plus` ARKASINDA DEĞİL. Gerekçe ürünün kendi kuralı:
    **hesap bedava, yorum paralı.** Takvimin tarihleri ve temaları hesabın
    kendisi — LLM'siz, zaten 24 saat önbellekli. Ücretsiz kullanıcı gerçek
    tarihleri ve gerçek temaları görür; kilitli olan tek şey OKUMADIR
    (`line` gündelik cümlesi ve `technical` dayanak satırı çıkarılır,
    olaya `locked: true` eklenir).

    Bu, uydurma bir teaser değil: gösterilen tarih doğru, tema doğru;
    eksik olan yalnızca yorum. Abonede davranış aynen bugünkü gibi.
    """
    try:
        profile = profile_service.get_profile(user.uid)
        if not chart_context.has_birth_data(profile):
            raise HTTPException(status_code=400,
                                detail=text("birth.missing", lang))
        birth = profile_service.birth_kwargs(profile, lang=lang)
        saat_biliniyor = bool(str(profile.get("birthTime") or "").strip())

        from services import predict_service, signal_service
        # Anahtarda BUGÜN de var: pencere takvim gününe sabitlenir; yalnız
        # TTL olsaydı gece 23:50'de dolan kayıt ertesi günü dünkü
        # pencereyle karşılardı. Sinyal sürümü de anahtarda: tema/ton
        # tabloları değişince 24 saatlik eski kayıt servis edilmesin.
        import datetime as dt
        anahtar = ("transit-cal-{calc}-s{sig}-{gun_sayisi}"
                   "-{year}{month:02d}{day:02d}"
                   "-{hour:02d}{minute:02d}-{city}-{nation}-{hk}"
                   "-{bugun}").format(
            calc=predict_service.PREDICT_CALC_VERSION,
            sig=signal_service.SIGNAL_CALC_VERSION,
            gun_sayisi=TRANSIT_CALENDAR_DAYS, hk=saat_biliniyor,
            bugun=dt.datetime.now(dt.timezone.utc).date().isoformat(),
            **{k: birth[k] for k in ("year", "month", "day", "hour",
                                     "minute", "city", "nation")})
        cal = cache.get(anahtar)
        if cal is None:
            cal = predict_service.transit_calendar(
                **astro_service.subject_kwargs(birth),
                hour_known=saat_biliniyor,
                days=TRANSIT_CALENDAR_DAYS)
            # Tema/ton: natal olgular önbellekli (chart_facts, 180 gün);
            # üretilemezse olaylar temasız kalır — takvim yine çalışır.
            #
            # `today=` ŞART: verilmezse kova sunucunun UTC gününden kurulur
            # ve Türkiye'de (UTC+3) 00:00-03:00 arası kullanıcının DÜNÜNE
            # düşer — yani gün dönmüşken bir önceki günün transitleri
            # "bugün" diye okunur. Aynı onarım `api/chat.py` ve
            # `api/face_reading.py`de yapılmıştı; burası atlanmıştı.
            natal = chart_context.chart_facts(
                user.uid, profile,
                today=user_local_date(user.uid))
            cal = {**cal, "events": signal_service.enrich_events(
                cal.get("events") or [], natal)}
            cache.set(anahtar, cal, ttl_seconds=24 * 3600)

        # Yorum (Ç-turu): YALNIZCA abonede, önbellekten AYRI ve DİL BAZLI.
        #
        # Ham `cal` (yukarıdaki `anahtar`) dilden bağımsız ve paylaşımlı —
        # yorum metni orada YAŞAYAMAZ, çünkü TR/EN aynı ham takvimi
        # paylaşıyor. Sinyal kartlarındaki `signals-insight-{fp}-{lang}`
        # deseninin birebir aynısı: ayrı anahtar, biçim-dışı çıktı da
        # (boş sözlük) önbelleklenir ki her istekte LLM yeniden yorulmasın.
        #
        # Ücretsiz kullanıcıda bu blok HİÇ ÇALIŞMAZ — boşuna harcama yok.
        # U06: olay satırları (transit ↔ natal açıları) Gemini'ye gider;
        # AI onayı yoksa yorum atlanır, olaylar yorumsuz ama kilitsiz döner.
        if is_subscriber(user.uid) and ai_katmani_acik(user.uid, x_app_build,
                                                       ai):
            fp = signal_service.calendar_fingerprint(cal.get("events") or [])
            yorum_anahtari = f"calendar-insight-{fp}-{lang}"
            yorumlar = cache.get(yorum_anahtari)
            if yorumlar is None:
                yorumlar = signal_service.calendar_insights(
                    cal.get("events") or [], lang) or {}
                # Biçim-dışı (boş) sonuç KISA ömürle yazılır (KA3, R9-1
                # emsali): 24 saat olsaydı tek biçim hatası günün tamamını
                # yorumsuz kilitlerdi; 1 saatte kendine gelir.
                cache.set(yorum_anahtari, yorumlar,
                          ttl_seconds=24 * 3600 if yorumlar else 3600)
            if yorumlar:
                def _yorumu_isle(o: dict) -> dict:
                    fp_o = signal_service.event_fingerprint(o)
                    return {**o, "line": yorumlar[fp_o]} if fp_o in yorumlar else o
                cal = {**cal, "events": [
                    _yorumu_isle(o) for o in (cal.get("events") or [])]}

        yerel = prompts.localize_transit_calendar(lang, cal)
        if not is_subscriber(user.uid):
            yerel = _takvimi_kilitle(yerel)
        return {"status": "success", "data": yerel}
    except HTTPException:
        raise
    except Exception as e:
        raise _internal(e, "transit-calendar", lang)


#: Ücretsiz katmanda olaydan ÇIKARILAN alanlar — ikisi de yorumdur:
#: `line` gündelik cümle, `technical` dayanak satırı.
_KILITLI_ALANLAR = ("line", "technical")


def _takvimi_kilitle(yerel: dict) -> dict:
    """Ücretsiz kullanıcı için okumayı çıkarır, ÖLÇÜMÜ bırakır.

    Kalan: tarih, olay türü, tema ve ton. Bunlar hesabın kendisi ve
    ürünün kuralı gereği ücretsiz. Giden: yorum cümleleri.

    `locked: true` YALNIZCA okuması OLABİLECEK olaya konur. İstasyonların
    (retro dönüşleri) hiçbir katmanda gündelik cümlesi yok — onları da
    kilitli işaretlemek "Rytho+ ile açılır" diyip abonelikte de
    açılmayan bir şey vaat etmek olurdu (cihaz turu, 1.5.1+18).

    Koşul BİLEREK `line` değil `theme` varlığına bakar (Ç-turu). Yorum
    metni artık YALNIZ abonede üretiliyor — ücretsiz kullanıcının olay
    sözlüğünde `line` zaten hiç yok. Koşul eskisi gibi `line`'a
    bağlansaydı ücretsiz kullanıcı kilit rozetini TAMAMEN kaybederdi
    (bugün her açı-kesinleşmesi otomatik `line` aldığı için bu fark
    görünmüyordu). `theme`, "bu olay TÜRÜNÜN bir okuması olabilir mi"
    sorusuna cevap verir — metnin o an üretilip üretilmediğinden bağımsız.
    """
    def olay(o: dict) -> dict:
        if not o.get("theme"):
            return o
        temiz = {k: v for k, v in o.items() if k not in _KILITLI_ALANLAR}
        temiz["locked"] = True
        return temiz

    return {**yerel, "events": [olay(o) for o in (yerel.get("events") or [])]}


@router.post("/synastry")
def synastry(req: SynastryRequest, lang: str = Depends(get_language)):
    """İki doğum verisinden sinastri (HA9: sinastri ÇARKININ veri kaynağı).

    Gövde iki tarafın doğum verisini İSTEMCİDEN alır — bu uç yalnız
    kullanıcının KENDİ girdiği verilerle (kendi profili + Çevrem kişisi)
    çağrılır; arkadaş verisi istemcide olmadığı için buradan geçemez
    (reports.py dyad kuralı bozulmaz).
    """
    try:
        result = astro_service.get_synastry(
            _birth_kwargs(req.person1, lang), _birth_kwargs(req.person2, lang)
        )
        return {"status": "success",
                "data": prompts.localize_synastry(lang, result)}
    except Exception as e:
        raise _internal(e, "synastry", lang)


@router.post("/synastry/svg")
def synastry_svg(
    req: SynastryRequest,
    theme: str = Query("dark", pattern="^(classic|dark|dark-high-contrast|light)$"),
    lang: str = Depends(get_language),
):
    try:
        svg = astro_service.get_synastry_svg(
            _birth_kwargs(req.person1, lang), _birth_kwargs(req.person2, lang), theme=theme
        )
        return Response(content=svg, media_type="image/svg+xml")
    except Exception as e:
        raise _internal(e, "synastry/svg", lang)

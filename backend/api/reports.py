"""Yorum/rapor uçları: hesaplama + RAG + Gemini + önbellek tek çağrıda."""
import datetime as dt
import logging
from typing import Literal, Optional

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

from core.auth import AuthUser, get_current_user
from core.i18n import default_name, get_language
from core.messages import text
from core.entitlements import require_plus
from core.ai_consent import ai_katmani_acik, ai_onayi_zorunlu
from core import entitlements, wallet
from services import (astro_service, bazi_service, birth_hexagram_service,
                      chart_context, notification_service, people_service,
                      profile_service, prompts, report_service,
                      signal_service)
from services.bazi_service import get_bazi_chart
from services.iching_service import cast_iching, enrich_cast
from services.sky_service import get_sky_now

logger = logging.getLogger(__name__)
router = APIRouter()


def _internal(exc: Exception, uç: str, lang: str) -> HTTPException:
    """İstisnayı sunucuda loglar, kullanıcıya sabit bir metinle döner.

    Uçlar eskiden `detail=str(e)` döndürüyordu: istemci `detail` alanını
    doğrudan ekrana bastığı için kullanıcı Python istisna metni görüyordu ve
    sunucunun iç yapısı dışarı sızıyordu.
    """
    logger.exception("%s ucunda hata", uç, exc_info=exc)
    return HTTPException(status_code=500, detail=text("internal", lang))


# İngilizce burç anahtarı -> Türkçe ad (Koç→Balık sırası korunur).
SIGN_TR = {
    "aries": "Koç", "taurus": "Boğa", "gemini": "İkizler", "cancer": "Yengeç",
    "leo": "Aslan", "virgo": "Başak", "libra": "Terazi", "scorpio": "Akrep",
    "sagittarius": "Yay", "capricorn": "Oğlak", "aquarius": "Kova",
    "pisces": "Balık",
}

SignName = Literal[
    "aries", "taurus", "gemini", "cancer", "leo", "virgo",
    "libra", "scorpio", "sagittarius", "capricorn", "aquarius", "pisces",
]


class BirthData(BaseModel):
    # Boş = dile göre varsayılan hitap (`i18n.default_name`); sabit "Gezgin"
    # İngilizce kullanıcıya Türkçe ad veriyordu.
    name: str = ""
    year: int = Field(ge=1900, le=2100)
    month: int = Field(ge=1, le=12)
    day: int = Field(ge=1, le=31)
    hour: int = Field(default=12, ge=0, le=23)
    minute: int = Field(default=0, ge=0, le=59)
    city: str = "Istanbul"
    nation: Optional[str] = None
    # "unspecified" = kullanıcı belirtmek istemedi. Varsayılan "female" idi
    # ve BaZi şans sütunlarının YÖNÜNÜ sessizce kadın kuralıyla
    # hesaplatıyordu — ölçülmemiş bir cinsiyetten ölçülmüş gibi yön
    # çıkıyordu. ⚠️ Eski kayıtlarda duran "female" ile gerçekten kadın
    # olan ayırt EDİLEMEZ; onlar bilinen cinsiyet sayılır.
    gender: str = "unspecified"

    # Doğum saati gerçekten biliniyor mu (Revize B1). `hour`'ı Optional
    # yapmak yerine ayrı bayrak: bu şema natal/sinastri uçlarıyla PAYLAŞIMLI
    # ve Batı haritası saatsiz ev hesabı ayrı bir ürün kararı. BaZi bayrağı
    # False görünce saat sütununu HİÇ kurmaz; diğer uçlar 12:00'la sürer.
    hour_known: bool = True


class IChingReportRequest(BaseModel):
    # None = soru verilmedi; varsayılan metin İSTEĞİN DİLİNDE uçta doldurulur
    # (Revize İ0). Şemadaki Türkçe sabit ("Geleceğim") İngilizce prompt'a
    # sızıyordu. Uzunluk sınırı da yeni: soru prompt'a ham giriyor.
    question: str | None = Field(default=None, max_length=280)
    method: Literal["coins", "yarrow"] = "coins"


class SynastryReportRequest(BaseModel):
    person1: BirthData
    person2: BirthData


class DyadRequest(BaseModel):
    friend_uid: str = Field(min_length=1, max_length=128)


class RelationshipRequest(BaseModel):
    """İlişkinin karşı tarafı: ya bir Rytho arkadaşı ya eklenen bir kişi.

    İkisi de verilirse `friend_uid` kazanır (eski istemciler yalnız onu
    gönderiyor); hiçbiri verilmezse 400.
    """

    friend_uid: str | None = Field(default=None, max_length=128)
    person_id: str | None = Field(default=None, max_length=128)


def _natal_kwargs(d: BirthData, lang: str) -> dict:
    return dict(name=d.name or default_name(lang), year=d.year, month=d.month, day=d.day,
                hour=d.hour, minute=d.minute, city=d.city, nation=d.nation,
                hour_known=d.hour_known)


@router.get("/horoscope/{sign}")
def horoscope(
    sign: SignName,
    period: Literal["daily", "weekly", "monthly"] = "daily",
    user: AuthUser = Depends(get_current_user),
    lang: str = Depends(get_language),
):
    """Burç bazlı genel yorum — ücretsiz katmanın omurgası.

    Kullanıcıdan bağımsızdır: yorum (burç, dönem, tarih kovası) anahtarıyla
    paylaşımlı önbellekte tutulur, yani dönem başına burç başına en fazla bir
    LLM çağrısı yapılır. Kullanıcı sayısı arttıkça maliyet artmaz.

    Kimlik doğrulaması istemci tarafında zaten mevcut (anonim Firebase oturumu
    dahil) ve ucu kötüye kullanıma karşı korur; abonelik gerektirmez.
    """
    sky = prompts.localize_sky(lang, get_sky_now())
    # Gün kovası isteğin sahibinin yerel gününden (D2): sunucu UTC'de ve
    # gece yarısından sonra kullanıcı dünkü yorumu görüyordu.
    report = report_service.horoscope_reading(
        sign, period, sky, lang=lang,
        today=entitlements.user_local_date(user.uid))
    return {"status": "success", "data": {
        "sign": sign,
        "sign_tr": SIGN_TR[sign],
        "sign_name": prompts.sign_name(lang, sign),
        "lang": lang,
        "period": period,
        "reading": report["text"],
        "cached": report.get("cached", False),
        "fallback": report.get("fallback", False),
        # Burç yorumu jeton harcamaz, yani bu hep False gelir — yine de
        # SABİT yazılmıyor, üretimden okunuyor: istemci "iade edildi"
        # cümlesini her LLM ucunda aynı sözleşmeden kuruyor; tek bir uçta
        # alanın yokluğu o sözleşmeyi istemcide özel dala böler.
        "refunded": report.get("refunded", False),
        "generated_for": report.get("generated_for"),
        "moon_phase": sky["moon_phase"],
        "retrogrades": sky["retrogrades"],
    }}


@router.get("/signals")
def signals(user: AuthUser = Depends(get_current_user),
            lang: str = Depends(get_language),
            ai: bool = True,
            x_app_build: str | None = Header(default=None)):
    """Kişisel sinyaller (R2-S1) — ana ekranın proaktif kartları.

    Jeton YOK. Ham sinyaller LLM'siz hesaptır ve transit takvimi gibi doğum
    verisine anahtarlı PAYLAŞIMLI önbellekte tutulur (aynı doğum verisi =
    aynı gökyüzü = aynı sinyaller). Tek cümlelik yorum katmanı ("insight")
    KA-turu'ndan beri HERKESE üretilir (kullanıcı kararı: "hazır cümle
    asla olmasın; herkese AI") — abonelik kapısı YOK. Yorumlar + akşam
    check-in sorusu TEK LLM çağrısıyla yazılır ve sinyal parmak izine
    anahtarlı PAYLAŞILAN pakete girer; sabah bildirimi de aynı paketi
    okur — günde en fazla bir çağrı/harita/dil (birim ekonomi kuralı).

    Doğum verisi yoksa 400 DEĞİL boş liste döner: ana ekran yeni kullanıcıya
    hata değil "haritanı tamamla" kartı göstermeli.
    """
    try:
        profile = profile_service.get_profile(user.uid)
        ham = signal_service.cached_signals(
            profile, today=entitlements.user_local_date(user.uid))
        if ham is None:
            return {"status": "success",
                    "data": {"signals": [], "reason": "birth_missing"}}

        soru = None
        # U06: yorum katmanı sinyal satırlarını (transit ↔ natal açıları)
        # Gemini'ye gönderir. Onay yoksa katman ATLANIR, hata dönmez —
        # sinyallerin kendisi LLM'siz hesap ve ücretsiz kalır. `ai=0` onay
        # ekranlı istemcinin "henüz karar yok" işaretidir (bkz.
        # core/ai_consent.py dosya başı).
        if ham.get("signals") and ai_katmani_acik(user.uid, x_app_build, ai):
            paket = signal_service.cached_insight_bundle(ham, lang)
            if paket:
                ham = {**ham, "signals": [
                    {**s, "insight": y}
                    for s, y in zip(ham["signals"], paket["insights"])]}
                soru = paket.get("checkin_question")

        yerel = prompts.localize_signals(lang, ham)
        # Mobil derin bağlantı eşleşmesi (KA5) parmak iziyle yapılır;
        # soru, bildirime dokunmadan uygulamayı açan kullanıcıya da
        # akşam yüzeyinde gösterilebilsin diye yanıtta taşınır.
        if ham.get("signals"):
            yerel["fingerprint"] = signal_service.signals_fingerprint(ham)
        if soru:
            yerel["checkin_question"] = soru
        return {"status": "success", "data": yerel}
    except HTTPException:
        raise
    except Exception as e:
        raise _internal(e, "signals", lang)


@router.post("/daily")
def daily(data: BirthData,
          user: AuthUser = Depends(require_plus("personal_daily")),
          _ai: None = Depends(ai_onayi_zorunlu),
          lang: str = Depends(get_language)):
    """Kisiye ozel gunluk okuma — Rytho+ .

    Ucretsiz katmanin gunluk icerigi /horoscope'tur: o, kullanicidan bagimsiz
    ve paylasimli onbellekten servis edilir. Buradaki okuma ise kullanicinin
    natal haritasiyla uretildigi icin kullanici basina bir LLM cagrisi
    gerektirir; abonelik siniri tam olarak bu maliyet farkindan geciyor.
    """
    try:
        natal = astro_service.get_natal_chart(
            **astro_service.subject_kwargs(_natal_kwargs(data, lang)),
            hour_known=data.hour_known)
        sky = prompts.localize_sky(lang, get_sky_now())
        # birth: bugünün transitlerinin haritaya değdiği noktalar da okumaya
        # girsin (Revize R8) — ek LLM çağrısı yok, hesap yerel efemeris.
        report = report_service.daily_reading(
            user.uid, natal, sky, lang=lang, birth=_natal_kwargs(data, lang),
            today=entitlements.user_local_date(user.uid))
        return {"status": "success", "data": {
            "reading": report["text"], "cached": report.get("cached", False),
            # Yedek metin okuma gibi DONMEZ (gz-2): istemci bunu gorup
            # "simdi uretemedik" der. /horoscope'taki satirin aynisi.
            # Gunluk okuma jeton harcamaz — `refunded` burada False gelir.
            "fallback": report.get("fallback", False),
            "refunded": report.get("refunded", False),
            "sun_sign": natal["sun_sign"], "moon_sign": natal["moon_sign"],
            "ascendant": natal["ascendant"],
            "moon_phase": sky["moon_phase"],
            "retrogrades": sky["retrogrades"],
        }}
    except HTTPException:
        # Cuzdan 402'si dahil kasitli HTTP hatalari 500'e sarilmasin.
        raise
    except Exception as e:
        raise _internal(e, "daily", lang)


@router.post("/natal")
def natal(data: BirthData,
          user: AuthUser = Depends(require_plus("natal_report")),
          _ai: None = Depends(ai_onayi_zorunlu),
          lang: str = Depends(get_language)):
    try:
        chart = astro_service.get_natal_chart(
            **astro_service.subject_kwargs(_natal_kwargs(data, lang)),
            hour_known=data.hour_known)
        # Token düşümü önbellek kaçırıldığında, LLM çağrısından hemen önce
        # (bkz. _cached_generate): aynı rapora ikinci bakış ücretsiz.
        report = report_service.natal_report(
            user.uid, chart, lang=lang,
            spend=wallet.spender(user.uid, "natal", lang=lang),
            refund=lambda: wallet.refund_spend(user.uid, "natal"))
        return {"status": "success", "data": {
            "chart": prompts.localize_chart(lang, chart),
            # Yedek metin rapor gibi DONMEZ (gz-2); jeton iadesi de soylenir.
            "fallback": report.get("fallback", False),
            "refunded": report.get("refunded", False),
            "report": report["text"],
        }}
    except HTTPException:
        # Cuzdan 402'si dahil kasitli HTTP hatalari 500'e sarilmasin.
        raise
    except Exception as e:
        raise _internal(e, "natal", lang)


@router.post("/bazi")
def bazi(data: BirthData,
         user: AuthUser = Depends(require_plus("bazi")),
         _ai: None = Depends(ai_onayi_zorunlu),
         lang: str = Depends(get_language)):
    try:
        chart = get_bazi_chart(
            year=data.year, month=data.month, day=data.day,
            # Saat bilinmiyorsa None: motor saat sütununu HİÇ kurmaz
            # (12:00 varsaymak öğle doğumu uydurmaktı — Revize B1).
            hour=data.hour if data.hour_known else None,
            minute=data.minute, city=data.city, nation=data.nation,
            gender=data.gender, name=data.name or default_name(lang),
        )
        report = report_service.bazi_report(
            user.uid, chart, lang=lang,
            spend=wallet.spender(user.uid, "bazi", lang=lang),
            refund=lambda: wallet.refund_spend(user.uid, "bazi"))
        # Ekranda gosterilen element/hayvan/On Tanri adlari da dile gore.
        return {"status": "success", "data": {
            "chart": prompts.localize_bazi(lang, chart),
            # Yedek metin rapor gibi DONMEZ (gz-2). BaZi'de bayraklar
            # HARITAYLA BIRLIKTE gider: harita deterministik hesap, yalniz
            # yorum uretilemedi — sekme haritayi cizip yorumun yerine durust
            # cumleyi koyuyor.
            "fallback": report.get("fallback", False),
            "refunded": report.get("refunded", False),
            "report": report["text"],
        }}
    except HTTPException:
        # Cuzdan 402'si dahil kasitli HTTP hatalari 500'e sarilmasin.
        raise
    except Exception as e:
        raise _internal(e, "bazi", lang)


@router.post("/iching")
def iching(req: IChingReportRequest,
           user: AuthUser = Depends(require_plus("iching")),
           _ai: None = Depends(ai_onayi_zorunlu),
           lang: str = Depends(get_language)):
    """I Ching Rytho+ kapısında (V2, 2026-08-12 kullanıcı kararı).

    Eski model gunde 1 ucretsiz cekilis + 2 token idi; urun karari kadim
    bilgelik modullerini (BaZi ile ayni desen) tamamen premium'a aldi.
    Gunluk ucretsiz ritual geri istenirse: require_plus -> get_current_user
    + metered_callbacks(user, "iching", FREE_ICHING_PER_DAY) donusu yeterli.
    Cihaz kilidi require_plus icinde uygulanir.
    """
    # Soru kapısı (R10→R11): niyetsiz girişler jeton hakkını
    # harcamadan çevrilir. Hüküm LLM'de (kelime listesi yalnız bariz
    # durumlarda ön filtre): "beni seviyor musun" uygulamaya yöneltilmiş
    # sayılır ve Sohbet'e yönlendirilir, "beni seviyor mu" geçer.
    if req.question:
        hukum = report_service.iching_question_verdict(req.question, lang)
        if hukum != "VALID":
            raise HTTPException(
                status_code=422,
                detail=text("iching.question_chat" if hukum == "CHAT"
                            else "iching.question_invalid", lang))

    # Cüzdan: natal/bazi ile aynı desen — harcama yalnız önbellek
    # kaçırıldığında düşer, üretim hatasında iade edilir.
    spend_cb = wallet.spender(user.uid, "iching", lang=lang)
    refund_cb = lambda: wallet.refund_spend(user.uid, "iching")  # noqa: E731
    try:
        # Soru verilmediyse varsayılan metin İSTEĞİN DİLİNDE (Revize İ0).
        soru = req.question or prompts.get(lang).ICHING_DEFAULT_QUESTION
        cast = cast_iching(soru, method=req.method)

        # Çekim günü bağlamı (İ2): günün/ayın sütunları + kullanıcının Day
        # Master'ı. Klasik danışma çekimi, çekildiği günün İÇİNDE okunur.
        # Gün, kullanıcının senkronlanan saat diliminden alınır (bildirim
        # altyapısının alanı); yoksa UTC — temel beyanla taşınır.
        profile = profile_service.get_profile(user.uid)
        tz = notification_service.user_timezone(profile or {})
        bugun = dt.datetime.now(dt.timezone.utc).astimezone(tz).date()
        basis = "profile_tz" if (profile or {}).get("timezone") else "utc"
        dm_element = None
        if profile and chart_context.has_birth_data(profile):
            bazi_ozet = chart_context.bazi_facts(user.uid, profile)
            dm_element = ((bazi_ozet or {}).get("day_master")
                          or {}).get("element")
        cast = enrich_cast(
            cast,
            day_pillar=bazi_service.day_pillar_for_date(bugun),
            month_pillar=bazi_service.month_pillar_for_date(bugun),
            day_master_element=dm_element,
            basis=basis)
        report = report_service.iching_reading(user.uid, cast, lang=lang,
                                               spend=spend_cb,
                                               refund=refund_cb)
        return {"status": "success", "data": {
            "cast": prompts.localize_iching(lang, cast),
            # Yedek metin okuma gibi DÖNMEZ (gz-2): bayrak düşerse istemci
            # şablon paragrafı gerçek okuma sanır ve iade edilen jetonu
            # öğrenmez (CLAUDE.md "kullanıcı farkı anlamayan yedekler").
            # Ölçülen çekim (`cast`) yanıtta AYNEN kalır: zar atıldı, yalnız
            # yorumu üretilemedi.
            "fallback": report.get("fallback", False),
            "refunded": report.get("refunded", False),
            "report": report["text"],
        }}
    except HTTPException:
        # Cuzdan 402'si dahil kasitli HTTP hatalari 500'e sarilmasin.
        raise
    except Exception as e:
        raise _internal(e, "iching", lang)


class SolarReturnRequest(BirthData):
    #: Belirli bir SR yılı istenirse (varsayılan: aktif yıl).
    target_year: int | None = Field(default=None, ge=1900, le=2100)


@router.post("/solar-return")
def solar_return(data: SolarReturnRequest,
                 user: AuthUser = Depends(require_plus("solar_return")),
                 _ai: None = Depends(ai_onayi_zorunlu),
                 lang: str = Depends(get_language)):
    """Yıl haritası (T1): aktif güneş dönüşü + LLM yıl okuması.

    Harita, kayıtlıysa kullanıcının YAŞADIĞI şehre kurulur (D3): yıl
    haritası doğum gününde bulunulan yere kurulur ve konum Yükselen'i
    tamamen değiştirir. Şehir istekten değil PROFİLDEN okunur — "senin
    haritan" iddiası kullanıcının kaydına dayanmalı (chart_context kuralı).
    """
    try:
        from services import predict_service
        profil = profile_service.get_profile(user.uid) or {}
        sr = predict_service.solar_return(
            data.name or default_name(lang), data.year, data.month, data.day,
            data.hour, data.minute, data.city, data.nation,
            hour_known=data.hour_known, target_year=data.target_year,
            relocation_city=(profil.get("residenceCity") or "").strip() or None,
            relocation_nation=profil.get("residenceNation"))
        report = report_service.solar_return_report(
            user.uid, sr, lang=lang,
            spend=wallet.spender(user.uid, "solar_return", lang=lang),
            refund=lambda: wallet.refund_spend(user.uid, "solar_return"))
        return {"status": "success", "data": {
            "solar_return": prompts.localize_chart(lang, sr),
            # Yedek metin yıl okuması gibi DÖNMEZ (gz-2); bayrak düşerse
            # istemci şablon metni rapor sanır ve iadeyi öğrenmez. Ölçülen
            # yıl haritası (`solar_return`) yanıtta AYNEN kalır.
            "fallback": report.get("fallback", False),
            "refunded": report.get("refunded", False),
            "report": report["text"],
        }}
    except HTTPException:
        raise
    except Exception as e:
        raise _internal(e, "solar-return", lang)


@router.post("/progressions")
def progressions(data: BirthData,
                 user: AuthUser = Depends(require_plus("progressions")),
                 _ai: None = Depends(ai_onayi_zorunlu),
                 lang: str = Depends(get_language)):
    """İç Takvim (T2): ikincil progresyon + solar arc + LLM okuması."""
    try:
        from services import predict_service
        prog = predict_service.secondary_progressions(
            data.name or default_name(lang), data.year, data.month, data.day,
            data.hour, data.minute, data.city, data.nation,
            hour_known=data.hour_known)
        hits = predict_service.solar_arc_hits(
            data.name or default_name(lang), data.year, data.month, data.day,
            data.hour, data.minute, data.city, data.nation,
            hour_known=data.hour_known)
        report = report_service.progressions_report(
            user.uid, prog, hits, lang=lang,
            spend=wallet.spender(user.uid, "progressions", lang=lang),
            refund=lambda: wallet.refund_spend(user.uid, "progressions"))
        return {"status": "success", "data": {
            "progressions": prompts.localize_progressions(lang, prog, hits),
            # Yedek metin okuma gibi DÖNMEZ (gz-2); bayrak düşerse istemci
            # şablon metni rapor sanır ve iadeyi öğrenmez. Ölçülen
            # progresyon ve solar arc vuruşları yanıtta AYNEN kalır.
            "fallback": report.get("fallback", False),
            "refunded": report.get("refunded", False),
            "report": report["text"],
        }}
    except HTTPException:
        raise
    except Exception as e:
        raise _internal(e, "progressions", lang)


@router.post("/birth-hexagram")
def birth_hexagram(data: BirthData,
                   user: AuthUser = Depends(require_plus("birth_hexagram")),
                   _ai: None = Depends(ai_onayi_zorunlu),
                   lang: str = Depends(get_language)):
    """Doğum Heksagramı — GÜNLÜK yüzey, kalıcı ÇEKİRDEK (Revize İ5).

    Çekim değil: doğum anındaki Güneş boylamının 64 kapı çarkındaki yeri.
    Gövde kalıcı (sabit kapı + 64 pasajdan biri); GÜNLÜK olan son bölüm —
    Güneş'in bugün aynı çarkta durduğu kapının doğum kapısıyla kesişimi.
    Ömür ve anahtarın gün terimi `report_service.birth_hexagram_report`da;
    tek kaynak orası, buraya SAYI yazılmaz (yazılan sayı bayatlar).

    Rytho+ + 5 token DEĞİŞMEDİ (sahip kararı, 2026-10-03): yüzey günlüğe
    çekildi, fiyatı ölçüm sonrası sahip belirleyecek.

    ⚠️ Bu docstring iki tur boyunca yüzeyi KİMLİK katmanı sayıyor ve
    ömrünü BİR AY diye yazıyordu; ölçüldüğünde ikisi de yanlış çıktı
    (2026-10-03). Yanlış gerekçe bu depoda kusurdur ve bu ikisinin
    bedeli somut: burayı okuyup yüzeyi kimlik sanan bir sonraki tur ya
    gün katmanını "yanlışlıkla eklenmiş" diye kaldırır, ya ömrü geri
    alır, ya da "kalıcı" varsayımına dayanan bir ön-ısıtma/paylaşımlı
    önbellek ekler — üçü de yüzeyi sessizce kimliğe döndürür.
    Bekçi: `tests/test_gunluk_tazelik.py`
    (`test_dogum_kapisi_UCUNUN_docstringi_OLCULEN_omurle_CELISMEZ`).
    """
    try:
        konum = birth_hexagram_service.birth_hexagram(
            year=data.year, month=data.month, day=data.day,
            hour=data.hour if data.hour_known else None,
            minute=data.minute, city=data.city, nation=data.nation,
        )
        report = report_service.birth_hexagram_report(
            user.uid, konum, lang=lang,
            spend=wallet.spender(user.uid, "birth_hexagram", lang=lang),
            refund=lambda: wallet.refund_spend(user.uid, "birth_hexagram"))
        return {"status": "success", "data": {
            "position": {
                "gate": konum["gate"],
                "line": konum["line"] if konum["hour_known"] else None,
                "longitude": konum["longitude"],
                "hour_known": konum["hour_known"],
                "alternate_gate": konum.get("alternate_gate"),
            },
            "hexagram": prompts.localize_hexagram(lang, konum["hexagram"]),
            "alternate_hexagram": prompts.localize_hexagram(
                lang, konum["alternate_hexagram"])
            if konum.get("alternate_hexagram") else None,
            # Kapı pasajı (İ8): ekran "Kapının Dokusu" kartını buradan kurar.
            "gate_text": (konum.get("gate_passage") or {}).get(
                "gate_en" if lang == "en" else "gate_tr"),
            # Yedek metin okuma gibi DÖNMEZ (gz-2); bayrak düşerse istemci
            # şablon metni rapor sanır ve iadeyi öğrenmez. Ölçülen kapı,
            # çizgi ve sabit kapı pasajı (`position`, `hexagram`,
            # `gate_text`) yanıtta AYNEN kalır — düşen yalnız gün kesişimi.
            "fallback": report.get("fallback", False),
            "refunded": report.get("refunded", False),
            "report": report["text"],
        }}
    except HTTPException:
        raise
    except Exception as e:
        raise _internal(e, "birth_hexagram", lang)


@router.get("/iching/status")
def iching_status(user: AuthUser = Depends(get_current_user)):
    """Çekim hakkı durumu — SALT OKUR, hak düşmez (Revize İ6).

    V2 (2026-08-12): İching Rytho+ kapısına alındı; günlük ücretsiz hak
    kalktı. Alan adları geriye dönük korunur (eski istemciler okuyor):
    `free_limit/free_remaining` artık hep 0 — rozet aboneye token
    bedelini, abone olmayana kilidi gösterir.
    """
    return {"status": "success", "data": {
        "free_limit": 0,
        "free_remaining": 0,
        "token_cost": wallet.TOKEN_COSTS["iching"],
        "subscriber": entitlements.is_subscriber(user.uid),
    }}


@router.post("/dyad")
def dyad(req: RelationshipRequest,
         user: AuthUser = Depends(require_plus("dyad")),
         _ai: None = Depends(ai_onayi_zorunlu),
         lang: str = Depends(get_language)):
    """İkinizin BUGÜNE özgü ilişki dinamiği.

    Karşı taraf bir Rytho arkadaşı (`friend_uid`) ya da kullanıcının
    eklediği bir kişi (`person_id`) olabilir — bkz. `/relationship`.

    İstemci yalnızca kimlik gönderir; doğum verisini sunucu okur ve
    yanıtta **döndürmez**. Böylece arkadaşın doğum tarihi/saati/yeri
    hiçbir zaman karşı istemciye ulaşmaz. (Eklenen kişide veri zaten
    kullanıcının kendisinin, ama simetri için aynı yol kullanılıyor.)
    """
    from services import synastry_service

    if req.friend_uid:
        if req.friend_uid == user.uid:
            raise HTTPException(status_code=400,
                                detail=text("dyad.self", lang))
        if not profile_service.are_friends(user.uid, req.friend_uid):
            raise HTTPException(status_code=403,
                                detail=text("dyad.not_friends", lang))
        karsi = synastry_service.friend_counterpart(user.uid, req.friend_uid)
    elif req.person_id:
        karsi = synastry_service.person_counterpart(user.uid, req.person_id,
                                                    lang)
    else:
        raise HTTPException(status_code=400,
                            detail=text("dyad.profile_missing", lang))

    me = profile_service.get_profile(user.uid)
    if not me or karsi is None:
        raise HTTPException(status_code=404,
                            detail=text("dyad.profile_missing", lang))

    synastry = astro_service.get_synastry(
        profile_service.birth_kwargs(me, lang=lang), karsi.birth)
    sky = prompts.localize_sky(lang, get_sky_now())
    # GT5: çifte özgü BUGÜN prompt'a girer — "günlük" okuma artık gerçekten
    # çift için günlük (eskiden tek günlük girdi herkese aynı Ay evresiydi).
    # Uç kurar, servis biçimler; ölçüm düşerse okuma bugünsüz üretilir.
    cift_satirlar = ""
    try:
        gunluk = synastry_service.pair_transits(
            user.uid, karsi, today=entitlements.user_local_date(user.uid))
        cift_satirlar = "\n".join(
            "- " + s for s in synastry_service.pair_transit_lines(
                (gunluk or {}).get("hits") or [], karsi.label, lang))
    except Exception as exc:
        logger.warning("Dyad çift transiti üretilemedi (%s): %s",
                       user.uid, exc)
    # Bedeli İSTEYEN taraf öder; arkadaş aynı gün içinde aynı okumayı
    # önbellekten ücretsiz görür (anahtar çift bazlı).
    report = report_service.dyad_reading(
        user.uid, karsi.key,
        me.get("displayName") or default_name(lang), karsi.label,
        synastry, sky, lang=lang,
        spend=wallet.spender(user.uid, "dyad", lang=lang),
        refund=lambda: wallet.refund_spend(user.uid, "dyad"),
        pair_transits=cift_satirlar,
    )

    return {"status": "success", "data": {
        "reading": report["text"],
        "cached": report.get("cached", False),
        "fallback": report.get("fallback", False),
        # İkili dinamik jeton harcar; yedekte iade edilir ve bu SÖYLENİR.
        # `fallback` bir tur boyunca tek başına taşınıyordu: istemci
        # "şimdi üretemedik" diyebiliyor ama bakiyenin neden yükseldiğini
        # açıklayamıyordu (CLAUDE.md "kullanıcı farkı anlamayan yedekler").
        "refunded": report.get("refunded", False),
        "generated_for": report.get("generated_for"),
        # Yalnızca türetilmiş, hassas olmayan alanlar döner — ham doğum verisi asla.
        "friend_sun_sign": prompts.sign_from_point(
            lang, synastry["person2"].get("sun")),
        "my_sun_sign": prompts.sign_from_point(
            lang, synastry["person1"].get("sun")),
    }}


@router.post("/relationship")
def relationship(req: RelationshipRequest,
                 user: AuthUser = Depends(get_current_user),
                 lang: str = Depends(get_language),
                 ai: bool = True,
                 x_app_build: str | None = Header(default=None)):
    """İlişki eksenleri (R2-L1) — nitel okuma, sayısal puan YOK.

    Karşı taraf iki türden biri olabilir (P-turu):

    * **Rytho arkadaşı** (`friend_uid`) — karşılıklı arkadaşlık ŞART;
      arkadaşın ham doğum verisi istemciye hiçbir zaman gitmez.
    * **Eklenen kişi** (`person_id`) — kullanıcının kendi girdiği eş,
      çocuk, yakın. Yetki kapısı arkadaşlık değil SAHİPLİK: kayıt
      çağıranın kendi ağacından okunur, başkasının person_id'si orada
      bulunamaz (`people_service.get_person`).

    Eklenen kişide eksen ADLARI ilişki türüne göre değişir — çocuğuyla
    "Çekim" değil "Yakınlık ve bakım" yazar; ölçüm aynı kalır.

    Mevcut ``/synastry`` ucu iki kişinin doğum verisini İSTEMCİDEN alıyor;
    arkadaş için kullanılamaz — arkadaşın doğum tarihi/saati/yeri istemciye
    hiçbir zaman gitmemeli (dyad ucundaki kural). Burada istemci yalnız
    arkadaşın kimliğini gönderir, iki profili de sunucu okur ve yanıtta ham
    doğum verisi DÖNMEZ: yalnız eksen seviyeleri ve dayanak açılar.

    **Ölçüm ücretsiz, yorum Rytho+** (1.6.0). Eksenler, seviyeler ve
    dayanak açılar herkese açık — bunlar LLM'siz hesap. Yorum artık hazır
    cümle tablosundan değil AI'dan geliyor (`relationship_reading`) ve
    aboneye özel; ücretsiz kullanıcıya `reading_locked: true` döner.
    Takvim ucundaki kalıbın aynısı: gördüğü ölçüm gerçek, eksik olan
    yalnızca yorum.

    Jeton düşülmez: okuma çift başına bir kez üretilip 30 gün saklanır.
    """
    from services import synastry_service

    if req.friend_uid:
        if req.friend_uid == user.uid:
            raise HTTPException(status_code=400,
                                detail=text("dyad.self", lang))
        if not profile_service.are_friends(user.uid, req.friend_uid):
            raise HTTPException(status_code=403,
                                detail=text("dyad.not_friends", lang))
        karsi = synastry_service.friend_counterpart(user.uid, req.friend_uid)
    elif req.person_id:
        # Yetki kapısı SAHİPLİK: kayıt çağıranın kendi ağacından okunur,
        # başkasının person_id'si orada bulunamaz — bu yüzden ayrı bir
        # 403 kontrolüne gerek yok, `None` zaten "senin değil" demektir.
        karsi = synastry_service.person_counterpart(user.uid, req.person_id,
                                                    lang)
        if karsi is None and not people_service.get_person(user.uid,
                                                           req.person_id):
            raise HTTPException(status_code=404,
                                detail=text("people.missing", lang))
    else:
        raise HTTPException(status_code=400,
                            detail=text("dyad.profile_missing", lang))

    me = profile_service.get_profile(user.uid)
    if not me:
        raise HTTPException(status_code=404,
                            detail=text("dyad.profile_missing", lang))
    if karsi is None or not chart_context.has_birth_data(me):
        # Varsayılan doğum verisiyle hesaplanan ilişkiyi "sizin haritanız"
        # diye sunmak veri uydurmaktır (chart_context kuralı).
        return {"status": "success",
                "data": {"axes": [], "reason": "birth_missing"}}

    try:
        # Hesap + önbellek yardımcıda (R4-2): sohbet fısıltısı da aynı
        # kaydı kullanır — aynı ikili için tek hesap.
        eksenler = synastry_service.axes_for(user.uid, karsi)
        if eksenler is None:
            return {"status": "success",
                    "data": {"axes": [], "reason": "birth_missing"}}

        veri = prompts.localize_relationship_axes(lang, eksenler,
                                                  karsi.relation)

        # GT3: bugünün çifte özgü gökyüzü — ÖLÇÜMDÜR ve abonelik dalından
        # ÖNCE eklenir: ücretsiz katman da görür ("hesap bedava, yorum
        # paralı"). Ölçüm düşerse yanıt today'siz döner, ekran şeridi
        # gizler — uç düşmez.
        try:
            gunluk = synastry_service.pair_transits(
                user.uid, karsi,
                today=entitlements.user_local_date(user.uid))
            if gunluk is not None:
                veri["today"] = prompts.localize_pair_transits(
                    lang, gunluk, karsi.label)
        except Exception as exc:
            logger.warning("Çift transit ölçümü üretilemedi (%s): %s",
                           user.uid, exc)

        abone = entitlements.is_subscriber(user.uid)
        # U06: yorum iki tarafın adını/etiketini ve eksenlerini Gemini'ye
        # gönderir. Onay yoksa eksenler (LLM'siz ölçüm) yine döner, yorum
        # yerine `reading_ai_off` — kilit rozeti DEĞİL: abonelik almak onu
        # açmaz, yalnız onay açar; `reading_locked` demek yanlış çare
        # göstermek olurdu.
        if abone and not ai_katmani_acik(user.uid, x_app_build, ai):
            veri = {**veri, "reading_ai_off": True}
        elif abone:
            okuma = report_service.relationship_reading(
                user.uid, karsi.key,
                me.get("displayName") or "?",
                karsi.label, eksenler, lang=lang,
                relation=karsi.relation)
            # Her eksen KENDİ cümlesini taşır: kart boş kalmamalı, kullanıcı
            # "neyi soracağım?" durumuna düşmemeli (cihaz turu bulgusu).
            # Cümleyi model o çift için yazar; hazır tablo yok.
            satirlar = okuma.get("axis_lines") or {}
            veri = {**veri, "axes": [
                {**e, **({"line": satirlar[e["axis"]]}
                         if satirlar.get(e["axis"]) else {})}
                for e in veri.get("axes") or []
            ]}
            # Ana tema ayrı; biçim tutmadıysa tam metin tek blok döner.
            veri["reading"] = okuma.get("theme") or (
                "" if satirlar else okuma["text"])
            # Yedek metin okuma gibi DÖNMEZ (gz-2): `okuma` sözlüğü bayrağı
            # `_cached_generate`den taşıyordu ama uç onu atıyordu; istemci
            # şablon paragrafı o çiftin okuması sanıyordu. Eksenler ve
            # dayanak açılar ölçümdür, yanıtta AYNEN kalır.
            #
            # `refunded` SABİT False: bu uç JETONSUZ (çift başına tek
            # üretim, 30 gün). Üretimden okumak da False verirdi; sabit
            # olması, "jetonun iade edildi" cümlesinin burada HİÇ
            # kurulamayacağını okuyana söyler (emsal:
            # test_jeton_harcamayan_ucta_iade_CUMLESI_KURULMAZ).
            veri["fallback"] = okuma.get("fallback", False)
            veri["refunded"] = False
        else:
            veri = {**veri, "reading_locked": True}
        return {"status": "success", "data": veri}
    except HTTPException:
        raise
    except Exception as e:
        raise _internal(e, "relationship", lang)


@router.post("/synastry")
def synastry(req: SynastryReportRequest,
             user: AuthUser = Depends(require_plus("synastry")),
             _ai: None = Depends(ai_onayi_zorunlu),
             lang: str = Depends(get_language)):
    try:
        result = astro_service.get_synastry(
            _natal_kwargs(req.person1, lang), _natal_kwargs(req.person2, lang)
        )
        report = report_service.synastry_report(
            user.uid, result, lang=lang,
            spend=wallet.spender(user.uid, "synastry", lang=lang),
            refund=lambda: wallet.refund_spend(user.uid, "synastry"))
        return {"status": "success", "data": {
            "synastry": result,
            # Yedek metin rapor gibi DÖNMEZ (gz-2); bayrak düşerse istemci
            # şablon metni rapor sanır ve iadeyi öğrenmez. Ölçülen sinastri
            # açıları (`synastry`) yanıtta AYNEN kalır.
            "fallback": report.get("fallback", False),
            "refunded": report.get("refunded", False),
            "report": report["text"],
        }}
    except HTTPException:
        # Cuzdan 402'si dahil kasitli HTTP hatalari 500'e sarilmasin.
        raise
    except Exception as e:
        raise _internal(e, "synastry", lang)

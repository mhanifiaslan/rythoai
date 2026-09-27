"""Firaset ucu — **görüntü almaz, oran alır**.

Bu uç baştan yazıldı. Eskisi bir `UploadFile` kabul ediyor, sunucuda
MediaPipe ile 468 landmark çıkarıyor ve fotoğrafı geçici dosyaya yazıyordu.
Silme adımı vardı ama tasarımın kendisi yanlıştı: **biyometrik veri sunucuya
ulaşıyordu.**

Şimdi tespit kullanıcının cihazında yapılıyor ve buraya yalnızca türetilmiş
oranlar geliyor. Bunun üç sonucu var:

* Sunucu hiçbir aşamada biyometrik veri işlemiyor, saklamıyor, loglamıyor.
* Ağ üzerinde fotoğraf gitmiyor.
* İmajda MediaPipe/OpenCV gerekmiyor (soğuk başlatma ve imaj boyutu).

Gelen sayılar kişiyi tanımaya yaramaz: "alın/çene yükseklik oranı 0.94"
milyonlarca insanda aynıdır.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from core import wallet
from core.ai_consent import ai_onayi_zorunlu
from core.auth import AuthUser, get_current_user
from core.entitlements import require_plus
from core.i18n import get_language
from core.messages import text
from services import (
    chart_context,
    consent_service,
    profile_service,
    report_service,
)

logger = logging.getLogger(__name__)

router = APIRouter()


class FaceRatios(BaseModel):
    """İstemcinin cihazında hesaplanan oranlar.

    Sınırlar hem doğrulama hem **kapı**: aralık dışı bir değer ya bozuk bir
    tespitten ya da elle uydurulmuş bir istekten gelir. İkisinde de okuma
    üretmek, olmayan bir ölçüme dayanarak konuşmak olurdu.
    """

    # --- Genişliğe bölünenler: her zaman gelir ---
    #
    # Bunlar yüz genişliğine oranlanıyor ve saç çizgisinden BAĞIMSIZ.
    jawToCheek: float = Field(ge=0.2, le=2)
    mouthToFaceWidth: float = Field(ge=0.05, le=1.5)
    eyeSpacing: float = Field(ge=0.05, le=1.5)
    symmetry: float = Field(ge=0, le=1)

    # --- Yüksekliğe bölünenler: İSTEĞE BAĞLI ---
    #
    # Hepsi `yüz yüksekliği = çene − saç çizgisi` paydasına bağlı ve saç
    # çizgisi her yüzde ölçülemiyor (kâkül, şapka, güvenilmez maske). İstemci
    # ölçemediğinde bu alanları HİÇ göndermiyor.
    #
    # Zorunlu olmaları gerçek bir kusur üretti: istemci alanları göndermeyi
    # bıraktığında uç 422 döndü ve kullanıcı çekimden sonra "beklenmeyen bir
    # sorun" ekranı gördü. Sözleşmenin iki ucu birlikte değişmeliydi.
    #
    # Alanın YOKLUĞU bilgi taşıyor: "bu eksen ölçülemedi". Varsayılan 0
    # vermek "ölçtüm ve sıfır çıktı" demek olurdu — bkz. hareket alanları.
    #: 1 = üst bölge saç çizgisinden değil KAFATASI TEPESİNDEN ölçüldü.
    #: Kel ya da tıraşlı kafada saç çizgisi geri getirilemiyor; ölçüm
    #: yapılabiliyor ama okuma nereden ölçüldüğünü söylemek zorunda.
    foreheadFromCrown: float | None = Field(default=None, ge=0, le=1)

    upperThird: float | None = Field(default=None, ge=0, le=1)
    middleThird: float | None = Field(default=None, ge=0, le=1)
    lowerThird: float | None = Field(default=None, ge=0, le=1)
    widthToHeight: float | None = Field(default=None, ge=0.2, le=3)
    lipFullness: float | None = Field(default=None, ge=0, le=0.5)

    # --- Hareket (sıcak–soğuk ekseni) ---
    #
    # Bu üçü İSTEĞE BAĞLI ve olmaması bir eksiklik değil, bir BİLGİ:
    # istemci ölçümü güvenilir bulmadıysa alanları hiç göndermiyor ve
    # sunucu "bu eksen ölçülemedi" diye okuyor. Varsayılan 0 vermek
    # "ölçtüm ve sıfır çıktı" demek olurdu; o yalan olurdu ve modeli
    # "hareketsiz" diye yorumlamaya iterdi.
    motionRate: float | None = Field(default=None, ge=0, le=5)
    stillness: float | None = Field(default=None, ge=0, le=5)
    motionSeconds: float | None = Field(default=None, ge=0, le=120)


@router.post("/reading")
def firasa_reading(
    ratios: FaceRatios,
    user: AuthUser = Depends(require_plus("firasa")),
    lang: str = Depends(get_language),
    # U06: oranlar + harita özeti Gemini'ye gider. Biyometrik rızadan AYRI
    # bir onay — biri işlemenin kendisine, öbürü üçüncü tarafa aktarıma.
    _ai: None = Depends(ai_onayi_zorunlu),
):
    """Yüz oranlarından firaset okuması — Rytho+.

    Abonelik sınırı maliyet farkından geçiyor: okuma kullanıcıya özel
    üretiliyor, yani kullanıcı başına bir LLM çağrısı. Aynı oranlar için
    sonuç bir hafta önbellekte tutulur; kullanıcı ekranı her açtığında
    yeniden üretilmez.
    """
    # Rıza kapısı yetkiden SONRA, işlemeden ÖNCE.
    #
    # Bu kontrol sunucuda olmak zorunda: istemcide onay kutusu göstermek
    # kullanıcıyı bilgilendirir ama işlemeyi engellemez. İspat yükü bizde ve
    # "istemci onay aldı" denetimde bir şey ifade etmez.
    if not consent_service.has_face_consent(user.uid):
        raise HTTPException(status_code=403,
                            detail=text("face_consent_required", lang))

    try:
        # Üç bölge oranı toplamı 1 civarında olmalı. Değilse tespit bozuk
        # demektir; uydurma bir okuma üretmektense reddetmek doğru.
        #
        # Kontrol yalnızca ÜÇÜ DE geldiğinde yapılıyor. Yokluk bir bozukluk
        # değil, "saç çizgisi ölçülemedi" demek; onu 422 ile reddetmek
        # ölçülebilen öbür eksenleri de çöpe atardı.
        ucu = (ratios.upperThird, ratios.middleThird, ratios.lowerThird)
        if all(v is not None for v in ucu):
            if not (0.85 <= sum(ucu) <= 1.15):
                raise HTTPException(status_code=422,
                                    detail=text("face_invalid_ratios", lang))
        elif any(v is not None for v in ucu):
            # Kısmi gönderim tutarsız: üçü bir bütün.
            raise HTTPException(status_code=422,
                                detail=text("face_invalid_ratios", lang))

        profile = profile_service.get_profile(user.uid)
        # Harita varsa okumaya girer: firaset tek başına da çalışır ama
        # haritayla birlikte kişiye özgü olur.
        chart = chart_context.chart_whisper(user.uid, profile, lang=lang)

        # `exclude_none`: gönderilmeyen hareket alanları sözlüğe HİÇ girmesin.
        # `heat_lean` alanın YOKLUĞUNU "ölçülemedi" diye okuyor; None olarak
        # taşımak da işe yarardı ama yokluk niyeti daha net ifade ediyor.
        rapor = report_service.firasa_report(
            user.uid, ratios.model_dump(exclude_none=True),
            chart=chart, lang=lang,
            spend=wallet.spender(user.uid, "face", lang=lang),
            refund=lambda: wallet.refund_spend(user.uid, "face"))
        return {"status": "success", "reading": rapor["text"],
                "cached": rapor.get("cached", False),
                # Yedek metin firaset okumasi gibi DONMEZ (gz-2): burada
                # LLM paragrafinin DISINDA gosterilecek bir sey yok, o yuzden
                # istemci "simdi uretemedik, jetonun iade edildi" der.
                "fallback": rapor.get("fallback", False),
                "refunded": rapor.get("refunded", False)}
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Firaset okumasi uretilemedi", exc_info=exc)
        raise HTTPException(status_code=500, detail=text("internal", lang))


# ---------------------------------------------------------------------------
# Rıza
# ---------------------------------------------------------------------------
#
# Rıza uçları **abonelik istemez** ve bu bilinçli: rızayı geri almak, ödeme
# durumundan bağımsız olarak her zaman mümkün olmalı. Aboneliği biten birinin
# rızasını geri alamaması, geri alma hakkını ödemeye bağlamak olurdu.


@router.get("/consent")
def consent_status(user: AuthUser = Depends(get_current_user)):
    """Kullanıcının güncel rıza durumu.

    ``version`` istemciye de veriliyor: rıza metni sürümü ilerlediğinde
    istemci bunu görüp yeniden sormalı.
    """
    return {
        "granted": consent_service.has_face_consent(user.uid),
        "version": consent_service.FACE_CONSENT_VERSION,
    }


@router.post("/consent")
def grant_consent(user: AuthUser = Depends(get_current_user),
                  lang: str = Depends(get_language)):
    """Biyometrik işleme rızasını kaydeder.

    Zaman damgası ve sürümle birlikte saklanıyor; "ne zaman, neye rıza
    gösterildi" sorusunun cevabı olmadan kayıt bir işe yaramaz.
    """
    if not consent_service.grant_face_consent(user.uid):
        raise HTTPException(status_code=500, detail=text("internal", lang))
    return {"status": "success", "granted": True,
            "version": consent_service.FACE_CONSENT_VERSION}


@router.delete("/consent")
def withdraw_consent(user: AuthUser = Depends(get_current_user),
                     lang: str = Depends(get_language)):
    """Rızayı geri alır ve **üretilmiş okumaları siler**.

    İkisi ayrılamaz: rızayı geri alıp veriyi bırakmak, geri almayı anlamsız
    kılar. Silme yalnızca firaset okumalarını kapsıyor — kullanıcının natal
    raporuna, BaZi'sine ya da günlük okumasına dokunmuyor. Rızayı geri almak
    yüz okumadan vazgeçmektir, hesabı silmek değil.
    """
    if not consent_service.withdraw_face_consent(user.uid):
        raise HTTPException(status_code=500, detail=text("internal", lang))
    silinen = consent_service.delete_face_readings(user.uid)
    return {"status": "success", "granted": False, "deletedReadings": silinen}

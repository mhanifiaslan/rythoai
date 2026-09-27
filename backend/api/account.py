"""Hesap uçları — silme, rıza, telefon eşleme, günlük.

Silme mağaza zorunluluğudur (Apple 5.1.1(v), Google Play). İstemci tarafında
Firestore kurallarıyla yapılamaz: kullanıcı BAŞKA kullanıcıların dokümanlarına
(karşılıklı arkadaşlık kaydı, gönderdiği tepkiler) ve sunucuya kapalı
koleksiyonlara (hafıza, abonelik, önbellek) dokunamaz. Bu yüzden sunucuda.

Günlük (R2-G1) de burada: kayıtlar hafıza dokümanında (``private/memory``)
yaşar — istemci o dokümanı doğrudan okuyamaz, uçlar tek kapıdır. Hesap
silindiğinde hafızayla birlikte günlük de silinir (mevcut akış).
"""
from __future__ import annotations

import logging

from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field, field_validator

from core import app_gate
from core.auth import AuthUser, get_current_user
from core.i18n import get_language
from core.messages import text
from services import (account_service, consent_service, feedback_service,
                      memory_service, phone_service)

logger = logging.getLogger(__name__)
router = APIRouter()


class DeleteResult(BaseModel):
    status: str
    #: Neyin kaç adet silindiği. İstemci göstermez; destek ve test için.
    deleted: dict[str, int]


@router.delete("/me", response_model=DeleteResult)
def delete_me(user: AuthUser = Depends(get_current_user),
              lang: str = Depends(get_language)) -> DeleteResult:
    """Oturum açmış kullanıcının hesabını ve tüm verisini siler.

    Yalnızca **kendi** hesabını siler: hedef kimlik gövdeden değil, doğrulanmış
    oturumdan alınır. İstemcinin uid göndermesine izin verilseydi, geçerli bir
    oturumu olan herkes başkasının hesabını silebilirdi.

    Geri alınamaz. Onay akışı istemcide (Profil > Hesabı sil).
    """
    if user.anonymous:
        # Geliştirme modundaki anonim kullanıcı; silinecek gerçek hesap yok.
        raise HTTPException(status_code=400, detail=text("auth_required", lang))

    try:
        sayim = account_service.delete_account(user.uid)
    except Exception as exc:
        logger.exception("Hesap silinemedi (%s)", user.uid, exc_info=exc)
        raise HTTPException(status_code=500, detail=text("internal", lang))

    return DeleteResult(status="deleted", deleted=dict(sayim))


class ConsentRequest(BaseModel):
    #: İstemcinin GÖSTERDİĞİ metin sürümü — kayıt bunu tutar (eski istemci
    #: eski metni göstermiş olabilir; ispat gördüğü şeye bağlanmalı).
    version: int = consent_service.TERMS_CONSENT_VERSION


@router.post("/consent")
def record_consent(req: ConsentRequest,
                   user: AuthUser = Depends(get_current_user),
                   lang: str = Depends(get_language)):
    """Kullanım şartları + gizlilik kabulünü kaydeder (O3).

    Sihirbazın karşılama adımı çağırır. Google/Apple girişlerinde bugüne
    dek HİÇBİR onay kutusu yoktu; bu uç her sağlayıcı için ispatlanabilir
    clickwrap kaydı üretir. Uçlarda ZORLANMAZ — eski kullanıcılar
    kilitlenmez, kayıt yalnız tutulur.
    """
    if not consent_service.grant_terms_consent(user.uid, req.version, lang):
        raise HTTPException(status_code=500, detail=text("internal", lang))

    # OT6: deneme hoş geldin jetonu — onboarding bitişinde bir kez.
    # Defter kimliği hesap başına sabit (idempotent): yasal metin sürümü
    # yükselince yeniden onay veren ESKİ kullanıcı ikinci kez alamaz;
    # `in_trial` kapısı da yalnız yeni hesaplara açar. Jeton yazılamazsa
    # onay kaydı yine başarılıdır — deneme jetonu bir ek, onayın kendisi
    # değil.
    from core import entitlements, wallet
    try:
        if entitlements.in_trial(user.uid):
            wallet.credit_promo(user.uid, wallet.TRIAL_PROMO_CODE,
                                wallet.TRIAL_TOKENS)
    except Exception as exc:
        logger.warning("Deneme jetonu yazilamadi (%s): %s", user.uid, exc)

    # AD4: sihirbaz bitiminde profil (ad/e-posta/kullanıcı adı) artık
    # yazılmış — arama aynası ilk kez burada dolar. Best-effort, hiç
    # fırlatmaz; kimlik yolundaki günlük kanca (core/auth) yedeğidir.
    from services import search_mirror
    search_mirror.ensure(user.uid)

    return {"status": "success",
            "version": consent_service.TERMS_CONSENT_VERSION}


class AiConsentRequest(BaseModel):
    #: İstemcinin GÖSTERDİĞİ onay metni sürümü (şartlar kabulüyle aynı
    #: ilke: ispat, kullanıcının gördüğü metne bağlanır).
    version: int = Field(default=consent_service.AI_CONSENT_VERSION,
                         ge=1, le=1000)


@router.get("/ai-consent")
def ai_consent_status(user: AuthUser = Depends(get_current_user),
                      lang: str = Depends(get_language)):
    """AI aktarım onayının durumu (U06).

    Kayıt istemciye kapalı `private/` altında durduğu için istemci onu
    Firestore'dan okuyamaz; tek kaynak bu uç. `decided`, "hiç sorulmadı"
    ile "soruldu, hayır dedi"yi ayırır — istemci ikisinde de onay
    ekranını gösterir ama bu ayrım destek ve test için görünür kalmalı.

    Okuma hatası 500'e sarılır, "onay yok"a ÇEVRİLMEZ: istemci hata
    görünce son bildiği değere düşer; "yok" görseydi onaylı kullanıcıya
    ekranı yeniden gösterir ve AI'yı sebepsiz kapatırdı.
    """
    try:
        kayit = consent_service.ai_consent(user.uid)
    except Exception as exc:
        logger.warning("AI onayı okunamadı (%s): %s", user.uid, exc)
        raise HTTPException(status_code=500, detail=text("internal", lang))
    return {
        "granted": consent_service.ai_kaydi_gecerli(kayit),
        "decided": isinstance(kayit, dict) and "granted" in kayit,
        "version": consent_service.AI_CONSENT_VERSION,
    }


@router.post("/ai-consent")
def grant_ai_consent(req: AiConsentRequest,
                     user: AuthUser = Depends(get_current_user),
                     lang: str = Depends(get_language)):
    """AI aktarım onayını kaydeder (zaman damgası + gösterilen sürüm)."""
    if not consent_service.grant_ai_consent(user.uid, req.version, lang):
        raise HTTPException(status_code=500, detail=text("internal", lang))
    return {"status": "success",
            "granted": req.version >= consent_service.AI_CONSENT_VERSION,
            "version": consent_service.AI_CONSENT_VERSION}


@router.delete("/ai-consent")
def withdraw_ai_consent(user: AuthUser = Depends(get_current_user),
                        lang: str = Depends(get_language)):
    """Onayı geri alır ya da "Şimdi değil"i kaydeder (``granted: False``).

    Abonelik İSTEMEZ — yüz rızası uçlarıyla aynı gerekçe: geri alma hakkı
    ödeme durumuna bağlanamaz. Üretilmiş okumalar SİLİNMEZ: onlar zaten
    üretilmiş metinler, geri alma bundan sonraki aktarımı durdurur; silme
    istenirse hesap silme ve konu silme yolları duruyor.
    """
    if not consent_service.withdraw_ai_consent(user.uid, lang):
        raise HTTPException(status_code=500, detail=text("internal", lang))
    return {"status": "success", "granted": False,
            "version": consent_service.AI_CONSENT_VERSION}


@router.post("/phone/sync")
def sync_phone(user: AuthUser = Depends(get_current_user),
               lang: str = Depends(get_language)):
    """Doğrulanmış telefonu eşleme dizinine kaydeder (Revize R2).

    Numara İSTEMCİDEN ALINMAZ: Firebase Phone Auth doğrulaması bitmiş numara
    ID token'ının `phone_number` claim'inde gelir. Gövdesiz bir uç — istemci
    yalnızca "bağladım, kaydet" der.
    """
    if not user.phone:
        # Token'da numara yok: istemci bağlamayı bitirmeden çağırmış ya da
        # token henüz tazelenmemiş (istemci linkten sonra getIdToken(true)
        # çağırmalı).
        raise HTTPException(status_code=400,
                            detail=text("phone.not_verified", lang))
    try:
        sonuc = phone_service.sync_phone(user.uid, user.phone)
    except phone_service.PhoneTakenError:
        raise HTTPException(status_code=409,
                            detail=text("phone.taken", lang))
    except Exception as exc:
        logger.exception("Telefon kaydı yazılamadı (%s)", user.uid,
                         exc_info=exc)
        raise HTTPException(status_code=500, detail=text("internal", lang))

    return {"status": "success", **sonuc}


class PhoneAttempt(BaseModel):
    """Telefon doğrulama denemesinin teşhis kaydı.

    `masked` MASKELİ numaradır ("+90532***4567") — ham numara buraya da,
    Firestore'a da girmez. İstemci beyanına güvenilir çünkü kayıt yalnız
    teşhis amaçlıdır: hiçbir yetki, hak ya da eşleşme bu alandan türemez.
    Yine de istemciye GÜVENMİYORUZ: alan Firestore'a yazılırken
    `phone_service._maske_kirp` son haneleri atıyor ("+90532***"), çünkü
    sahadaki eski sürümler tam maskeyi göndermeye devam ediyor.
    """

    stage: str = Field(max_length=16)
    iso2: str = Field(default="", max_length=2)
    masked: str = Field(default="", max_length=24)
    code: str | None = Field(default=None, max_length=64)


@router.post("/phone/attempt")
def phone_attempt(body: PhoneAttempt,
                  user: AuthUser = Depends(get_current_user)):
    """SMS denemesini kaydeder — ateşle-unut, asla hata döndürmez.

    Google, SMS'i kabul edip faturalandırdığı hâlde teslim edilmediğinde
    hiçbir iz bırakmıyor (teslim makbuzu yayınlamıyor). Bu uç, en azından
    BİZİM tarafımızda "hangi kullanıcı, hangi ülkeye, hangi maskeli
    numaraya, hangi aşamada" sorusunu cevaplanabilir kılıyor.
    """
    phone_service.record_attempt(
        user.uid, body.stage, body.iso2, body.masked, body.code)
    return {"status": "success"}


# ---------------------------------------------------------------------------
# Günlük (R2-G1)
# ---------------------------------------------------------------------------

class DiaryEntryRequest(BaseModel):
    text: str = Field(min_length=1, max_length=memory_service.MAX_DIARY_CHARS)
    #: signal_service.THEMES kümesinden; verilmezse temasız kayıt.
    theme: str | None = Field(default=None, max_length=20)


@router.get("/diary")
def diary(user: AuthUser = Depends(get_current_user),
          lang: str = Depends(get_language)):
    """Günlük girişleri, yeniden eskiye. LLM yok, jeton yok."""
    try:
        return {"status": "success",
                "data": {"entries": memory_service.get_diary(user.uid),
                         "themes": list(memory_service.DIARY_THEMES)}}
    except Exception as exc:
        logger.exception("Günlük okunamadı (%s)", user.uid, exc_info=exc)
        raise HTTPException(status_code=500, detail=text("internal", lang))


@router.post("/diary")
def add_diary(req: DiaryEntryRequest,
              user: AuthUser = Depends(get_current_user),
              lang: str = Depends(get_language)):
    """Tek satırlık giriş ekler; giriş sohbetin hafıza fısıltısına da girer.

    Böylece "son bir ayda ne oldu?" sorusuna Rytho, kullanıcının KENDİ
    kayıtları + o günlerin gökyüzüyle cevap verebilir — analizdeki
    "astrolojik günlük" fikrinin çekirdeği.
    """
    try:
        giris = memory_service.add_diary_entry(
            user.uid, req.text, theme=req.theme)
    except Exception as exc:
        logger.exception("Günlük yazılamadı (%s)", user.uid, exc_info=exc)
        raise HTTPException(status_code=500, detail=text("internal", lang))
    if giris is None:
        raise HTTPException(status_code=400, detail=text("internal", lang))
    return {"status": "success", "data": giris}


@router.delete("/diary/{entry_id}")
def delete_diary(entry_id: str,
                 user: AuthUser = Depends(get_current_user),
                 lang: str = Depends(get_language)):
    """Girişi siler. Günlük kullanıcının kendi sesi — silmek de onun hakkı."""
    try:
        silindi = memory_service.delete_diary_entry(user.uid, entry_id)
    except Exception as exc:
        logger.exception("Günlük silinemedi (%s)", user.uid, exc_info=exc)
        raise HTTPException(status_code=500, detail=text("internal", lang))
    if not silindi:
        raise HTTPException(status_code=404, detail=text("internal", lang))
    return {"status": "success"}


# ---------------------------------------------------------------------------
# Geri bildirim (GB-turu)
# ---------------------------------------------------------------------------

class FeedbackRequest(BaseModel):
    """Hata / öneri / diğer. Metin kırpılmış hâliyle 1..2000; boşluktan
    ibaret metin 422 — boş kayıt panelde gürültüdür."""

    type: Literal["bug", "suggestion", "other"]
    text: str = Field(min_length=1, max_length=feedback_service.MAX_TEXT)
    #: İstemcinin o an açık olduğu ekranın adı (rota) — teşhis için.
    screen: str | None = Field(default=None,
                               max_length=feedback_service.MAX_SCREEN)

    @field_validator("text")
    @classmethod
    def _bos_olamaz(cls, deger: str) -> str:
        deger = deger.strip()
        if not deger:
            raise ValueError("Metin boş olamaz.")
        return deger


@router.post("/feedback")
def submit_feedback(req: FeedbackRequest,
                    user: AuthUser = Depends(get_current_user),
                    lang: str = Depends(get_language),
                    x_app_build: str | None = Header(default=None),
                    x_device_platform: str | None = Header(default=None)):
    """Geri bildirimi `feedback/{autoId}` dokümanına yazar.

    Bağlam (build, platform, dil) gövdeden değil BAŞLIKLARDAN okunur —
    istemci beyanı değil, Dio interceptor'ının her isteğe eklediği
    değerler. Sınır: uid başına günde 10 (429 + `feedback.limit`).
    """
    build = app_gate.parse_build(x_app_build) or None
    try:
        fid = feedback_service.submit(
            user.uid, type_=req.type, text=req.text, screen=req.screen,
            app_build=build, platform=x_device_platform, language=lang)
    except feedback_service.LimitError:
        raise HTTPException(status_code=429,
                            detail=text("feedback.limit", lang))
    except Exception as exc:
        logger.exception("Geri bildirim yazılamadı (%s)", user.uid,
                         exc_info=exc)
        raise HTTPException(status_code=500, detail=text("internal", lang))
    return {"status": "ok", "id": fid}

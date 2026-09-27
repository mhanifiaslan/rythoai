"""Admin uçları (W5 → AD-turu): panelin tek veri kapısı.

Panel (/rytho-admin) Firestore'a hiç dokunmaz — her veri buradan geçer ve
her uç en az `require_admin` (custom claim / rol) ister; yıkıcı, mali ve
yapılandırma uçları `require_owner`. Tek istisna `collect`: gecelik Cloud
Scheduler işi claim taşıyamayacağı için scheduler sırrı da geçerli
(bkz. api/notify.py `_verify_scheduler` deseni — ÇİFT KAPI).

## Denetim izi (AD3)

Yazan her eylem `adminAudit`'e düşer. Yıkıcı/mali eylemler ÖN-İZLİDİR:
önce `phase: intent` kaydı yazılır (yazılamazsa **503, eylem yapılmaz**),
eylem biter, aynı doküman `phase: done` ile tamamlanır. Böylece "iz yok
ama hesap silinmiş" durumu imkânsızlaşır; yarım kalan eylem de izde
`intent` olarak görünür.

## Rol haritası

| Uç | Kapı |
|---|---|
| okumalar, kredi, cihaz kilidi, auth-link, bildirim prova/test | admin (owner+support) |
| sil, devre dışı, eşik, ortak yazımları, dışa aktarım, yeniden hesapla, duyuru, collect | owner |
"""
from __future__ import annotations

import csv
import datetime as dt
import io
import logging
import secrets as py_secrets
from typing import Any, Iterable, Iterator, Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel, Field

from core import app_gate, config, device, firestore as firestore_client
from core import wallet
from core.auth import (AuthUser, get_current_user, require_admin,
                       require_owner)
from core.i18n import get_language
from services import admin_service, partner_service, stats_service

logger = logging.getLogger(__name__)
router = APIRouter()

_AUDIT_YAZILAMADI = "Denetim izi yazılamadı; işlem yapılmadı."
_GUN_DESENI = r"^\d{4}-\d{2}-\d{2}$"


# ---------------------------------------------------------------------------
# Denetim izi
# ---------------------------------------------------------------------------

def _audit(user: AuthUser, action: str, target_uid: str | None = None,
           params: dict[str, Any] | None = None, *,
           zorunlu: bool = False, phase: str | None = None) -> str | None:
    """Denetim izi: admin'in YAZAN eylemleri kalıcı kayda düşer.

    Döndürdüğü doküman kimliğiyle `_audit_tamamla` aynı kaydı günceller.
    `zorunlu=False`: best-effort (rutin yazımlar). `zorunlu=True`: iz
    yazılamazsa 503 — çağıran eylemi HİÇ yapmaz (fail-closed). Salt-okur
    uçlar audit'lenmez (gürültü).
    """
    try:
        client = firestore_client.get_client()
        if client is None:
            raise RuntimeError("Firestore erişilemiyor.")
        kayit: dict[str, Any] = {
            "adminUid": user.uid,
            "adminEmail": getattr(user, "email", None),
            "adminRole": getattr(user, "role", None),
            "action": action,
            "targetUid": target_uid,
            "params": params or {},
            "at": dt.datetime.now(dt.timezone.utc),
        }
        if phase:
            kayit["phase"] = phase
        ref = client.collection("adminAudit").document()
        ref.set(kayit)
        # Sahte istemcilerde `id` olmayabilir; iz yazıldı, kimlik yoksa
        # tamamlama atlanır — yazım başarısı buna bağlanmaz.
        return getattr(ref, "id", None)
    except Exception as exc:
        logger.warning("Denetim izi yazılamadı (%s): %s", action, exc)
        if zorunlu:
            raise HTTPException(status_code=503, detail=_AUDIT_YAZILAMADI)
        return None


def _audit_tamamla(iz_id: str | None, ek: dict[str, Any]) -> None:
    """Ön-izi tamamlar (best-effort merge): `phase: done|failed` + ek."""
    if not iz_id:
        return
    try:
        client = firestore_client.get_client()
        if client is None:
            return
        client.collection("adminAudit").document(iz_id).set(
            {**ek, "doneAt": dt.datetime.now(dt.timezone.utc)}, merge=True)
    except Exception as exc:
        logger.warning("Denetim izi tamamlanamadı (%s): %s", iz_id, exc)


def _basarisiz(iz_id: str | None, exc: BaseException) -> None:
    """Ön-izli eylem düştü: iz `failed` kalır, hata olduğu gibi yükselir."""
    _audit_tamamla(iz_id, {"phase": "failed", "error": str(exc)[:300]})


# ---------------------------------------------------------------------------
# Kimlik
# ---------------------------------------------------------------------------

@router.get("/me")
def me(user: AuthUser = Depends(require_admin)):
    """Panelin rol teyidi: claim'den okunan rolü sunucu söyler."""
    return {"status": "ok", "uid": user.uid, "email": user.email,
            "role": user.role}


# ---------------------------------------------------------------------------
# İstatistik toplama + okumalar
# ---------------------------------------------------------------------------

def _scheduler_gecerli(authorization: str | None) -> bool:
    """Scheduler sırrı doğru mu — yoksa/uyuşmuyorsa sessizce False.

    notify.py'deki `_verify_scheduler`dan farkı: burada hata FIRLATMAZ,
    çünkü ikinci kapı (admin claim) hâlâ denenecek.
    """
    return bool(
        config.NOTIFY_SCHEDULER_SECRET
        and authorization
        and py_secrets.compare_digest(authorization,
                                      config.NOTIFY_SCHEDULER_SECRET)
    )


@router.post("/collect")
async def collect(
    date: str | None = Query(default=None, pattern=_GUN_DESENI),
    authorization: str | None = Header(default=None),
    lang: str = Depends(get_language),
):
    """Günün istatistiklerini toplar — ÇİFT KAPI: scheduler sırrı VEYA owner.

    `Depends(get_current_user)` BİLEREK yok: scheduler'ın başlığı Bearer
    değil ham sır taşır ve dependency zinciri isteği kapıya gelmeden 401'lerdi
    (üretimde yaşandı). Sıra: önce sır denenir; tutmazsa başlık Bearer olarak
    ayrıştırılıp admin claim'i + owner rolü aranır.

    İdempotent: aynı günün tekrarı dokümanı ezer, birikmez.
    """
    kullanici: AuthUser | None = None
    if not _scheduler_gecerli(authorization):
        kimlik_bilgisi = None
        if authorization and authorization.startswith("Bearer "):
            kimlik_bilgisi = HTTPAuthorizationCredentials(
                scheme="Bearer", credentials=authorization[7:])
        kullanici = await get_current_user(credentials=kimlik_bilgisi,
                                           lang=lang)
        require_owner(require_admin(kullanici))

    tarih = dt.date.fromisoformat(date) if date else None
    try:
        dokuman = stats_service.collect(tarih)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    if kullanici is not None:
        # Yalnız admin kapısından geçen elle tetikleme iz bırakır;
        # scheduler'ın gecelik koşusu rutindir, denetim izi değil.
        _audit(kullanici, "stats.collect", params={"date": dokuman["date"]})
    return {"status": "ok", "date": dokuman["date"],
            "durationMs": dokuman["durationMs"]}


@router.get("/stats")
def stats(days: int = Query(default=30, ge=1, le=365),
          user: AuthUser = Depends(require_admin)):
    """Son N günün hazır adminStats dokümanları (yeniden eskiye)."""
    return {"status": "ok", "days": stats_service.read_days(days)}


@router.get("/live")
def live(user: AuthUser = Depends(require_admin)):
    """Hafif canlı satır: bugünkü doküman var mı + bugünkü kayıt sayısı.

    Ağır tarama YOK — gecelik collect'in işi; burada yalnız tek doküman
    okuması ve tek count() var.
    """
    client = firestore_client.get_client()
    if client is None:
        raise HTTPException(status_code=500, detail="Firestore erişilemiyor.")

    bugun = dt.datetime.now(dt.timezone.utc).date().isoformat()
    anlik = client.collection("adminStats").document(bugun).get()
    bugunku: dict[str, Any] | None = (anlik.to_dict()
                                      if getattr(anlik, "exists", False)
                                      else None)

    gun_bas = dt.datetime.combine(dt.date.fromisoformat(bugun), dt.time.min,
                                  tzinfo=dt.timezone.utc)
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter
        yeni_kayit = (client.collection("users")
                      .where(filter=FieldFilter("createdAt", ">=", gun_bas))
                      .count().get())
        bugun_yeni = int(yeni_kayit[0][0].value)
    except Exception:
        bugun_yeni = -1

    return {"status": "ok", "today": bugunku, "newUsersToday": bugun_yeni,
            "serverTime": dt.datetime.now(dt.timezone.utc).isoformat()}


_Env = Literal["PRODUCTION", "SANDBOX"]
_ECON_DAYS = (30, 90)
_USAGE_DAYS = (7, 30, 90)


def _gun_secenegi(days: int, secenekler: tuple[int, ...]) -> int:
    if days not in secenekler:
        raise HTTPException(
            status_code=422,
            detail=f"days şunlardan biri olmalı: {', '.join(map(str, secenekler))}")
    return days


@router.get("/revenue")
def revenue(days: int = Query(default=30, ge=1, le=365),
            env: _Env = Query(default="PRODUCTION"),
            user: AuthUser = Depends(require_admin)):
    """Gelir özeti — adminStats rollup'ından (tarama YOK, AD7)."""
    try:
        return {"status": "ok", **admin_service.revenue_summary(days, env)}
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/revenue/events")
def revenue_events(env: _Env = Query(default="PRODUCTION"),
                   type: str | None = Query(default=None, max_length=40),
                   limit: int = Query(default=50, ge=1, le=100),
                   cursor: str | None = Query(default=None, max_length=512),
                   user: AuthUser = Depends(require_admin)):
    """Abonelik zaman çizelgesi: revenueEvents (env, [type], at DESC), cursor."""
    try:
        return {"status": "ok",
                **admin_service.revenue_events(env, type, limit, cursor)}
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/economics")
def economics(days: int = Query(default=30),
              env: _Env = Query(default="PRODUCTION"),
              user: AuthUser = Depends(require_admin)):
    """Rollup birleştirmesi (adminEconomics) — 30 | 90 gün, önbellekli."""
    days = _gun_secenegi(days, _ECON_DAYS)
    try:
        return {"status": "ok", **admin_service.economics(days, env)}
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


class RecomputeRequest(BaseModel):
    """Kapsayıcı gün aralığı (YYYY-MM-DD); servis ≤90 günü ve kilidi tutar."""
    from_: str = Field(alias="from", pattern=_GUN_DESENI)
    to: str = Field(pattern=_GUN_DESENI)

    model_config = {"populate_by_name": True}


@router.post("/economics/recompute")
def economics_recompute(req: RecomputeRequest,
                        user: AuthUser = Depends(require_owner)):
    """Geçmiş günlerin rollup'ını canlı taramayla yeniden üretir (owner).

    Servis kilitlidir: eşzamanlı ikinci istek RuntimeError("busy") → 409.
    """
    try:
        bas = dt.date.fromisoformat(req.from_)
        son = dt.date.fromisoformat(req.to)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=f"Geçersiz tarih: {exc}")
    if son < bas:
        raise HTTPException(status_code=400,
                            detail="Bitiş, başlangıçtan önce olamaz.")
    try:
        sonuc = stats_service.recompute(bas, son)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        if str(exc) == "busy":
            raise HTTPException(status_code=409,
                                detail="Yeniden hesaplama zaten sürüyor.")
        raise HTTPException(status_code=500, detail=str(exc))
    _audit(user, "stats.recompute",
           params={"from": req.from_, "to": req.to})
    return {"status": "ok", "result": sonuc}


@router.get("/usage")
def usage(days: int = Query(default=30),
          user: AuthUser = Depends(require_admin)):
    """AI kullanım kırılımı — adminStats rollup'ından; 7 | 30 | 90 gün."""
    days = _gun_secenegi(days, _USAGE_DAYS)
    try:
        return {"status": "ok", **admin_service.usage_summary(days)}
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/attention")
def attention(user: AuthUser = Depends(require_admin)):
    """Dikkat zili: başarısız push, fatura sorunu, biten deneme, eşik altı,
    devre dışı, bayat rollup — sayaçlar + kısa listeler."""
    try:
        return {"status": "ok", "items": admin_service.attention()}
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/notify-runs")
def notify_runs(days: int = Query(default=7, ge=1, le=30),
                user: AuthUser = Depends(require_admin)):
    try:
        return {"status": "ok", "runs": admin_service.notify_runs(days)}
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ---------------------------------------------------------------------------
# Bildirim araçları (AD8) — destek de kullanır
# ---------------------------------------------------------------------------

_NotifyType = Literal["daily", "midday", "checkin", "streak"]


class NotifyDryRunRequest(BaseModel):
    type: _NotifyType = "daily"
    force: bool = False


class NotifyTestSendRequest(BaseModel):
    type: _NotifyType = "daily"


def _notify_runner():
    try:
        from services import notify_runner
    except ImportError:
        raise HTTPException(status_code=503,
                            detail="Bildirim koşucusu bu sürümde yok.")
    return notify_runner


@router.post("/notify/dry-run")
def notify_dry_run(req: NotifyDryRunRequest,
                   user: AuthUser = Depends(require_admin)):
    """Prova: kim kuyruğa girerdi, hangi dilde — GÖNDERİM YOK, iz yok."""
    kosucu = _notify_runner()
    try:
        sonuc = kosucu.run_batch(req.type, dry_run=True, force=req.force)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    _audit(user, "notify.dry_run",
           params={"type": req.type, "force": req.force})
    return {"status": "ok",
            "result": sonuc.model_dump() if hasattr(sonuc, "model_dump")
            else sonuc}


@router.post("/notify/test-send")
def notify_test_send(req: NotifyTestSendRequest,
                     user: AuthUser = Depends(require_admin)):
    """Kendine test bildirimi — YALNIZ çağıranın uid'i; LastSent
    işaretlenmez. Jeton yoksa servis ValueError → 400 açık mesaj."""
    kosucu = _notify_runner()
    try:
        sonuc = kosucu.test_send(uid=user.uid, type=req.type)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    _audit(user, "notify.test_send", target_uid=user.uid,
           params={"type": req.type})
    return {"status": "ok", "result": sonuc}


# ---------------------------------------------------------------------------
# Kullanıcılar (AD4/AD6/AD9)
# ---------------------------------------------------------------------------

class CreditCreate(BaseModel):
    """Elle kredi: tutar pozitif, gerekçe ZORUNLU (denetim + defter)."""
    amount: int = Field(gt=0, le=5000)
    reason: str = Field(min_length=3, max_length=300)


_Plan = Literal["free", "trial", "plus"]


def _csv_yaniti(sutunlar: Iterable[str], satirlar: Iterable[dict[str, Any]],
                dosya_adi: str, iz_id: str | None) -> StreamingResponse:
    """UTF-8 BOM'lu CSV akışı (Excel Türkçe karakterleri BOM'suz bozar).

    Satırlar tembel üretilir; akış bittiğinde ön-iz `done` ve satır
    sayısıyla tamamlanır.
    """
    sutunlar = list(sutunlar)

    def _akis() -> Iterator[str]:
        tampon = io.StringIO()
        yazici = csv.DictWriter(tampon, fieldnames=sutunlar,
                                extrasaction="ignore", lineterminator="\r\n")
        yield "﻿"
        yazici.writeheader()
        yield tampon.getvalue()
        tampon.seek(0)
        tampon.truncate(0)
        adet = 0
        try:
            for satir in satirlar:
                yazici.writerow(satir)
                adet += 1
                yield tampon.getvalue()
                tampon.seek(0)
                tampon.truncate(0)
        except Exception as exc:
            _basarisiz(iz_id, exc)
            raise
        _audit_tamamla(iz_id, {"phase": "done", "rows": adet})

    return StreamingResponse(
        _akis(), media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{dosya_adi}"'})


@router.get("/users/export.csv")
def users_export(plan: _Plan | None = Query(default=None),
                 language: str | None = Query(default=None, max_length=8),
                 platform: str | None = Query(default=None, max_length=16),
                 disabled: bool | None = Query(default=None),
                 activeSince: str | None = Query(default=None,
                                                 pattern=_GUN_DESENI),
                 user: AuthUser = Depends(require_owner)):
    """Kullanıcı CSV'si (owner, ön-izli). fcmToken / doğum verisi ASLA."""
    if firestore_client.get_client() is None:
        raise HTTPException(status_code=500, detail="Firestore erişilemiyor.")
    suzgec = {"plan": plan, "language": language, "platform": platform,
              "disabled": disabled, "activeSince": activeSince}
    iz = _audit(user, "export.users", params={"filters": suzgec},
                zorunlu=True, phase="intent")
    satirlar = admin_service.users_csv_rows(
        plan=plan, language=language, platform=platform, disabled=disabled,
        active_since=activeSince)
    gun = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d")
    return _csv_yaniti(admin_service.USERS_CSV_COLUMNS, satirlar,
                       f"rytho-kullanicilar-{gun}.csv", iz)


@router.get("/revenue/export.csv")
def revenue_export(days: int = Query(default=30, ge=1, le=365),
                   env: _Env = Query(default="PRODUCTION"),
                   user: AuthUser = Depends(require_owner)):
    """Gelir olayları CSV'si (owner, ön-izli)."""
    if firestore_client.get_client() is None:
        raise HTTPException(status_code=500, detail="Firestore erişilemiyor.")
    iz = _audit(user, "export.revenue", params={"days": days, "env": env},
                zorunlu=True, phase="intent")
    satirlar = admin_service.revenue_csv_rows(days=days, env=env)
    gun = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d")
    return _csv_yaniti(admin_service.REVENUE_CSV_COLUMNS, satirlar,
                       f"rytho-gelir-{env.lower()}-{gun}.csv", iz)


@router.get("/users")
def users(q: str = Query(default="", max_length=120),
          alan: Literal["eposta", "kullanici", "ad"] = Query(default="ad"),
          plan: _Plan | None = Query(default=None),
          language: str | None = Query(default=None, max_length=8),
          platform: str | None = Query(default=None, max_length=16),
          disabled: bool | None = Query(default=None),
          activeSince: str | None = Query(default=None, pattern=_GUN_DESENI),
          belowBuild: int | None = Query(default=None, ge=1, le=100000),
          sort: Literal["createdAt", "lastSeenDaily", "streakCount"] = Query(
              default="createdAt"),
          limit: int = Query(default=50, ge=1, le=100),
          cursor: str | None = Query(default=None, max_length=512),
          user: AuthUser = Depends(require_admin)):
    """Kullanıcı listesi: arama modu (önek aralığı) / süzgeç modu; cursor.

    Servisin ValueError'u (yasak süzgeç birleşimi, bozuk imleç) 400.
    """
    try:
        sonuc = admin_service.list_users(
            q=q, alan=alan, plan=plan, language=language, platform=platform,
            disabled=disabled, active_since=activeSince,
            below_build=belowBuild, sort=sort, limit=limit, cursor=cursor)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    return {"status": "ok", **sonuc}


@router.get("/users/{uid}")
def user_detail(uid: str, user: AuthUser = Depends(require_admin)):
    try:
        detay = admin_service.user_360(uid)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    if detay is None:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
    return {"status": "ok", **detay}


@router.post("/users/{uid}/credit")
def user_credit(uid: str, req: CreditCreate,
                user: AuthUser = Depends(require_admin)):
    """Cüzdana admin kredisi — destek aracı ("paket geldi, bakiye gelmedi").

    Yalnız POZİTİF tutar: düşüm ayrı bir iştir ve bilerek yok (yanlışlıkla
    kullanıcı bakiyesi silinmesin). Defter + denetim izi birlikte yazılır.
    """
    try:
        wallet.credit_admin(uid, req.amount, req.reason, user.uid)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    _audit(user, "user.credit", target_uid=uid,
           params={"amount": req.amount, "reason": req.reason})
    return {"status": "ok", "wallet": wallet.get_wallet(uid)}


class AuthLinkRequest(BaseModel):
    kind: Literal["verify", "reset"]


@router.post("/users/{uid}/auth-link")
def user_auth_link(uid: str, req: AuthLinkRequest,
                   user: AuthUser = Depends(require_admin)):
    """Firebase e-posta doğrulama / şifre sıfırlama bağlantısı üretir.

    E-posta GÖNDERİLMEZ — destek bağlantıyı kullanıcıya kendi kanalından
    iletir (kapsam dışı: e-posta gönderimi). Bağlantı denetim izine
    YAZILMAZ: tek kullanımlık bir yetki belgesidir; izde yalnız türü kalır.
    """
    try:
        from firebase_admin import auth as fb_auth
        hesap = fb_auth.get_user(uid)
        eposta = getattr(hesap, "email", None)
        if not eposta:
            raise HTTPException(status_code=400,
                                detail="Kullanıcının e-postası yok.")
        if req.kind == "verify":
            link = fb_auth.generate_email_verification_link(eposta)
        else:
            link = fb_auth.generate_password_reset_link(eposta)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500,
                            detail=f"Bağlantı üretilemedi: {exc}")
    _audit(user, "user.auth_link", target_uid=uid, params={"kind": req.kind})
    return {"status": "ok", "kind": req.kind, "link": link}


class DisableRequest(BaseModel):
    disabled: bool
    reason: str = Field(min_length=3, max_length=300)


class DeleteRequest(BaseModel):
    #: Yazılı onay: panel formu "SIL" yazdırır — kaza tek tıkla olamaz.
    confirm: str
    reason: str = Field(min_length=3, max_length=300)


@router.post("/users/{uid}/disable")
def user_disable(uid: str, req: DisableRequest,
                 user: AuthUser = Depends(require_owner)):
    """Hesabı devre dışı bırakır/açar (Firebase Auth `disabled`) — owner.

    Devre dışı hesap oturum AÇAMAZ; mevcut token'lar da revoke edilir
    (yenileme anında düşer). Verisi durur — silme ayrı ve daha ağır iş.
    Ön-izli: iz yazılamazsa 503 ve kimlik DOKUNULMAZ. `authDisabled`
    aynası (AD4) best-effort yazılır ki liste süzgeci görsün.
    """
    if uid == user.uid:
        raise HTTPException(status_code=400,
                            detail="Kendi hesabını devre dışı bırakamazsın.")
    eylem = "user.disable" if req.disabled else "user.enable"
    iz = _audit(user, eylem, target_uid=uid, params={"reason": req.reason},
                zorunlu=True, phase="intent")
    try:
        from firebase_admin import auth as fb_auth
        fb_auth.update_user(uid, disabled=req.disabled)
        if req.disabled:
            fb_auth.revoke_refresh_tokens(uid)
    except Exception as exc:
        _basarisiz(iz, exc)
        raise HTTPException(status_code=500, detail=f"Kimlik güncellenemedi: {exc}")
    try:
        client = firestore_client.get_client()
        if client is not None:
            client.collection("users").document(uid).set(
                {"authDisabled": bool(req.disabled)}, merge=True)
    except Exception as exc:
        logger.warning("authDisabled aynası yazılamadı (%s): %s", uid, exc)
    _audit_tamamla(iz, {"phase": "done"})
    return {"status": "ok", "disabled": req.disabled}


@router.delete("/users/{uid}")
def user_delete(uid: str, req: DeleteRequest,
                user: AuthUser = Depends(require_owner)):
    """Hesabı TAMAMEN siler — mobil 'Hesabı sil' ile aynı boru
    (account_service.delete_account: veri önce, kimlik en son). Owner.

    Üç emniyet: yazılı onay ("SIL") + kendini silme yasağı + ön-iz
    (iz yazılamazsa 503, hesap DURUR). İz silinen hesabın e-postasını da
    saklar — silindikten sonra başka yerde kalmaz.
    """
    if req.confirm != "SIL":
        raise HTTPException(status_code=400,
                            detail='Onay metni "SIL" olmalı.')
    if uid == user.uid:
        raise HTTPException(status_code=400,
                            detail="Kendi hesabını buradan silemezsin.")
    from services import account_service
    try:
        detay = admin_service.user_360(uid) or {}
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    eposta = (detay.get("profile") or {}).get("email")
    iz = _audit(user, "user.delete", target_uid=uid,
                params={"reason": req.reason, "email": eposta},
                zorunlu=True, phase="intent")
    try:
        rapor = account_service.delete_account(uid)
    except RuntimeError as exc:
        _basarisiz(iz, exc)
        raise HTTPException(status_code=500, detail=str(exc))
    _audit_tamamla(iz, {"phase": "done"})
    return {"status": "ok", "report": getattr(rapor, "__dict__", str(rapor))}


@router.post("/users/{uid}/device/release")
def user_device_release(uid: str, user: AuthUser = Depends(require_admin)):
    """Cihaz kilidini sıfırlar (TC-turu kaçış kapısı).

    "Hesabın başka cihazda açıldı" kapısından çıkamayan kullanıcı için:
    kayıt cihazdan bağımsız silinir, bir sonraki korumalı isteği yapan
    cihaz sessizce sahiplenir. Gerekçe istenmez — eylem geri alınabilir
    (kullanıcı yeniden sahiplenir); denetim izi yeter.
    """
    try:
        released = device.force_release(uid)
    except Exception as exc:
        raise HTTPException(status_code=500,
                            detail=f"Cihaz kaydı silinemedi: {exc}")
    _audit(user, "device.release", target_uid=uid)
    return {"status": "ok", "released": released}


# ---------------------------------------------------------------------------
# Denetim izi okuma (AD3)
# ---------------------------------------------------------------------------

@router.get("/audit")
def audit(action: str | None = Query(default=None, max_length=60),
          adminUid: str | None = Query(default=None, max_length=128),
          targetUid: str | None = Query(default=None, max_length=128),
          from_: str | None = Query(default=None, alias="from",
                                    pattern=_GUN_DESENI),
          to: str | None = Query(default=None, pattern=_GUN_DESENI),
          limit: int = Query(default=50, ge=1, le=200),
          cursor: str | None = Query(default=None, max_length=512),
          user: AuthUser = Depends(require_admin)):
    """Süzgeçli, cursor'lu denetim izi. `to` KAPSAYICI gün (gün sonuna
    kadar); bozuk imleç 400."""
    bas = son = None
    if from_:
        bas = dt.datetime.combine(dt.date.fromisoformat(from_), dt.time.min,
                                  tzinfo=dt.timezone.utc)
    if to:
        son = dt.datetime.combine(dt.date.fromisoformat(to) + dt.timedelta(days=1),
                                  dt.time.min, tzinfo=dt.timezone.utc)
    try:
        sonuc = admin_service.audit_list(
            action=action, admin_uid=adminUid, target_uid=targetUid,
            start=bas, end=son, limit=limit, cursor=cursor)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    return {"status": "ok", **sonuc}


# ---------------------------------------------------------------------------
# Geri bildirim (GB-turu) — destek de okur, işaretler, yanıtlar
# ---------------------------------------------------------------------------

_FeedbackStatus = Literal["new", "in_review", "closed"]
_FeedbackType = Literal["bug", "suggestion", "other"]


class FeedbackPatch(BaseModel):
    """Durum ve/veya not; ikisi de boşsa 400 (boş yazım iz bırakmasın)."""
    status: _FeedbackStatus | None = None
    note: str | None = Field(default=None, max_length=1000)


class FeedbackReply(BaseModel):
    text: str = Field(min_length=1, max_length=500)


@router.get("/feedback")
def feedback_list(status: _FeedbackStatus | None = Query(default=None),
                  type: _FeedbackType | None = Query(default=None),
                  limit: int = Query(default=50, ge=1, le=100),
                  cursor: str | None = Query(default=None, max_length=512),
                  user: AuthUser = Depends(require_admin)):
    """Geri bildirim listesi: eşitlik süzgeçleri, createdAt DESC, cursor."""
    try:
        sonuc = admin_service.feedback_list(status=status, type_=type,
                                            limit=limit, cursor=cursor)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    return {"status": "ok", **sonuc}


@router.get("/feedback/{fid}")
def feedback_detail(fid: str, user: AuthUser = Depends(require_admin)):
    try:
        kayit = admin_service.feedback_get(fid)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    if kayit is None:
        raise HTTPException(status_code=404, detail="Geri bildirim bulunamadı.")
    return {"status": "ok", "item": kayit}


@router.patch("/feedback/{fid}")
def feedback_patch(fid: str, req: FeedbackPatch,
                   user: AuthUser = Depends(require_admin)):
    """Durum değişikliği ve/veya iç not; iz `feedback.update`."""
    not_metni = (req.note or "").strip()
    if not req.status and not not_metni:
        raise HTTPException(status_code=400,
                            detail="Durum ya da not gerekli.")
    try:
        kayit = admin_service.feedback_update(
            fid, status=req.status, note=not_metni or None,
            admin_uid=user.uid, admin_email=user.email)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    if kayit is None:
        raise HTTPException(status_code=404, detail="Geri bildirim bulunamadı.")
    _audit(user, "feedback.update", target_uid=kayit.get("uid"),
           params={"fid": fid, "status": req.status,
                   "hasNote": bool(not_metni)})
    return {"status": "ok", "item": kayit}


@router.post("/feedback/{fid}/reply")
def feedback_reply(fid: str, req: FeedbackReply,
                   user: AuthUser = Depends(require_admin)):
    """Kullanıcıya yanıt: doküman `reply` + push (jeton varsa). Sessiz
    saat uygulanmaz — doğrudan insan yanıtı. İz `feedback.reply`."""
    try:
        sonuc = admin_service.feedback_reply(
            fid, text=req.text, admin_uid=user.uid, admin_email=user.email)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    if sonuc is None:
        raise HTTPException(status_code=404, detail="Geri bildirim bulunamadı.")
    _audit(user, "feedback.reply",
           target_uid=(sonuc.get("item") or {}).get("uid"),
           params={"fid": fid, "pushSent": sonuc["pushSent"]})
    return {"status": "ok", **sonuc}


# ---------------------------------------------------------------------------
# Sistem + duyuru (AD10)
# ---------------------------------------------------------------------------

@router.get("/system")
def system(user: AuthUser = Depends(require_admin)):
    """Sağlık, rollup tazeliği, scheduler, indeks yoklaması, build, config."""
    try:
        return {"status": "ok", **admin_service.system_info()}
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


class NoticeRequest(BaseModel):
    """Panel bandı: boş metin duyuruyu kaldırır. Mobil bunu OKUMAZ."""
    text: str = Field(default="", max_length=300)
    level: Literal["info", "warn"] = "info"


@router.post("/config/notice")
def config_notice(req: NoticeRequest,
                  user: AuthUser = Depends(require_owner)):
    """`config/app.notice` yazar (owner). `api/config.py` dokunulmaz —
    mobil açılış yapılandırması bu alanı taşımaz."""
    client = firestore_client.get_client()
    if client is None:
        raise HTTPException(status_code=500, detail="Firestore erişilemiyor.")
    metin = req.text.strip()
    if metin:
        deger: Any = {"text": metin, "level": req.level,
                      "updatedAt": dt.datetime.now(dt.timezone.utc),
                      "updatedBy": user.uid}
    else:
        from google.cloud.firestore_v1 import DELETE_FIELD
        deger = DELETE_FIELD
    try:
        client.collection("config").document("app").set({"notice": deger},
                                                        merge=True)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Duyuru yazılamadı: {exc}")
    _audit(user, "config.notice",
           params={"text": metin, "level": req.level,
                   "cleared": not metin})
    return {"status": "ok", "notice": None if not metin else
            {"text": metin, "level": req.level}}


# ---------------------------------------------------------------------------
# Zorunlu güncelleme eşiği (PBZ) — sıcak anahtar `config/app.minBuild`
# ---------------------------------------------------------------------------

class MinBuildRequest(BaseModel):
    """Eşik: 0 = kapı kapalı; gerekçe ZORUNLU (denetim izi)."""
    min_build: int = Field(ge=0, le=100000)
    reason: str = Field(min_length=3, max_length=300)


def _min_build_durumu() -> dict[str, Any]:
    esik = app_gate.current_min_build()
    try:
        dokuman = app_gate.read_doc()
    except Exception as exc:
        logger.warning("config/app okunamadı: %s", exc)
        dokuman = None
    return {
        "min_build": esik,
        "env_floor": config.MIN_APP_BUILD,
        "doc": dokuman,
        # Eşik kapalıyken sayım anlamsız ve bir aggregation okuması boşa.
        "below_min_live": app_gate.count_below(esik) if esik > 0 else 0,
    }


@router.get("/min-build")
def min_build_status(user: AuthUser = Depends(require_admin)):
    """Etkin eşik + env tabanı + doküman + canlı "eşiğin altında" sayısı.

    `min_build` = max(env, doküman); panel ikisini ayrı gösterir ki
    "0 yazdım ama hâlâ 40" durumu env tabanına bağlansın.
    """
    return {"status": "ok", **_min_build_durumu()}


@router.post("/min-build")
def min_build_set(req: MinBuildRequest,
                  user: AuthUser = Depends(require_owner)):
    """Eşiği yazar (K9 doğrulaması, owner): `min_build > 0` ise
    `appBuild >= min_build` olan EN AZ BİR kullanıcı canlı görülmüş olmalı.

    Yazım hatasıyla (350 yerine 35) herkesi kilitlemek böyle imkânsızlaşır;
    operatörün kendi cihazında açtığı yeni sürüm şartı sağlar. Sıfır (geri
    alma) her zaman kabul — kilidi açmanın önkoşulu olmaz. Ön-izli.
    """
    if firestore_client.get_client() is None:
        raise HTTPException(status_code=500, detail="Firestore erişilemiyor.")
    if req.min_build > 0 and not app_gate.build_seen_at_or_above(req.min_build):
        raise HTTPException(
            status_code=400,
            detail="Eşiğin üstünde hiç kullanıcı görülmedi — önce yeni "
                   "sürümü bir cihazda aç.")
    iz = _audit(user, "config.min_build",
                params={"min_build": req.min_build, "reason": req.reason},
                zorunlu=True, phase="intent")
    try:
        app_gate.set_min_build(req.min_build, req.reason, user.uid)
    except RuntimeError as exc:
        _basarisiz(iz, exc)
        raise HTTPException(status_code=500, detail=str(exc))
    _audit_tamamla(iz, {"phase": "done"})
    return {"status": "ok", **_min_build_durumu()}


# ---------------------------------------------------------------------------
# Ortaklar (W7) — okuma admin, yazımlar owner
# ---------------------------------------------------------------------------

class PartnerCreate(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    contact: str = Field(default="", max_length=160)
    sharePercent: float = Field(default=0, ge=0, le=90)
    notes: str = Field(default="", max_length=500)
    #: Kazanılan abone başına ödül (₺). ORTAK BAŞINA ayarlanır — kodda
    #: sabit değil. Tavan `sharePercent`'inkiyle aynı gerekçe: bu alan
    #: gerçek para ödemesi üretiyor ve fazladan yazılmış bir sıfır
    #: panelde göze çarpmaz.
    rewardTry: float = Field(default=30.0, gt=0,
                             le=partner_service.MAX_REWARD_TRY)
    #: Ortağın kendi Firebase hesabı. Hem kendi panosunu görmesi hem
    #: kendi kodunu kullanamaması bu bağa dayanır.
    uid: str | None = Field(default=None, max_length=128)


class PartnerPatch(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=80)
    contact: str | None = Field(default=None, max_length=160)
    sharePercent: float | None = Field(default=None, ge=0, le=90)
    active: bool | None = None
    notes: str | None = Field(default=None, max_length=500)
    #: ⚠️ Değişiklik YALNIZ bundan sonraki kazanımlara uygulanır: tutar
    #: hakediş anında `partnerQualifications` dokümanına kopyalanıyor.
    rewardTry: float | None = Field(default=None, gt=0,
                                    le=partner_service.MAX_REWARD_TRY)
    uid: str | None = Field(default=None, max_length=128)
    payoutCurrency: str | None = Field(default=None, min_length=3,
                                       max_length=3)
    taxId: str | None = Field(default=None, max_length=64)
    iban: str | None = Field(default=None, max_length=40)
    minPayoutTry: float | None = Field(default=None, ge=0, le=100000)


class CodeCreate(BaseModel):
    #: Boş bırakılırsa okunaklı rastgele kod üretilir.
    code: str | None = Field(default=None, max_length=24)
    bonusTokens: int = Field(default=0, ge=0, le=5000)
    maxRedemptions: int | None = Field(default=None, ge=1)
    #: ISO tarih (YYYY-MM-DD) — gün sonu UTC kabul edilir.
    expiresAt: str | None = Field(default=None, pattern=_GUN_DESENI)


class PayoutCreate(BaseModel):
    #: Pozitif = ortağa ödendi, NEGATİF = geri alındı (düzeltme).
    #:
    #: Negatif kayıt bilinçli olarak serbest: kesinleşmiş bir hakediş
    #: sonradan iade edilirse geçmişi sessizce değiştirmek yerine
    #: düzeltme kaydı açılır — ortağın gördüğü bakiye açıklanabilir
    #: kalır. Sunucu ayrıca bakiyeden fazla POZİTİF ödemeyi reddeder
    #: ve negatif kayıtta gerekçe zorunludur (partner_service.add_payout).
    amount: float = Field(ge=-100000, le=100000)
    currency: str = Field(default="TRY", min_length=3, max_length=3)
    note: str = Field(default="", max_length=300)


def _servis_hatasi(e: partner_service.RedeemError) -> HTTPException:
    return HTTPException(status_code=e.status, detail=e.reason)


@router.get("/partners")
def partners(user: AuthUser = Depends(require_admin)):
    return {"status": "ok", "partners": partner_service.list_partners()}


@router.post("/partners")
def create_partner(req: PartnerCreate,
                   user: AuthUser = Depends(require_owner)):
    try:
        ortak = partner_service.create_partner(
            req.name, req.contact, req.sharePercent, req.notes,
            reward_try=req.rewardTry, uid=req.uid)
    except partner_service.RedeemError as e:
        raise _servis_hatasi(e)
    _audit(user, "partner.create", params={"name": req.name})
    return {"status": "ok", "partner": ortak}


@router.patch("/partners/{partner_id}")
def patch_partner(partner_id: str, req: PartnerPatch,
                  user: AuthUser = Depends(require_owner)):
    try:
        partner_service.update_partner(
            partner_id, req.model_dump(exclude_none=True))
    except partner_service.RedeemError as e:
        raise _servis_hatasi(e)
    _audit(user, "partner.update",
           params={"partnerId": partner_id,
                   **req.model_dump(exclude_none=True)})
    return {"status": "ok"}


@router.get("/partners/{partner_id}")
def partner_detail(partner_id: str,
                   user: AuthUser = Depends(require_admin)):
    try:
        return {"status": "ok", **partner_service.partner_detail(partner_id)}
    except partner_service.RedeemError as e:
        raise _servis_hatasi(e)


@router.post("/partners/{partner_id}/codes")
def create_code(partner_id: str, req: CodeCreate,
                user: AuthUser = Depends(require_owner)):
    son = None
    if req.expiresAt:
        son = dt.datetime.combine(dt.date.fromisoformat(req.expiresAt),
                                  dt.time.max, tzinfo=dt.timezone.utc)
    try:
        kod = partner_service.create_code(
            partner_id, req.code, req.bonusTokens, req.maxRedemptions, son)
    except partner_service.RedeemError as e:
        raise _servis_hatasi(e)
    _audit(user, "partner.code",
           params={"partnerId": partner_id, "code": kod.get("code"),
                   "bonusTokens": req.bonusTokens})
    return {"status": "ok", "code": kod}


@router.post("/partners/{partner_id}/payouts")
def add_payout(partner_id: str, req: PayoutCreate,
               user: AuthUser = Depends(require_owner)):
    """Hakediş ödemesi kaydı (owner, ön-izli — mali işlem)."""
    iz = _audit(user, "partner.payout",
                params={"partnerId": partner_id, "amount": req.amount,
                        "currency": req.currency},
                zorunlu=True, phase="intent")
    try:
        odeme = partner_service.add_payout(
            partner_id, req.amount, req.currency, req.note)
    except partner_service.RedeemError as e:
        _basarisiz(iz, e)
        raise _servis_hatasi(e)
    _audit_tamamla(iz, {"phase": "done"})
    return {"status": "ok", "payout": odeme}

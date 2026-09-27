"""Ortaklık uçları (OP-turu) — ortağın KENDİ paneli + hakediş olgunlaştırma.

Bu modül `api/admin.py`'den AYRIDIR ve bu bilinçlidir. Yönetim uçları
`require_admin`/`require_owner` ile kapılanır; buradaki ortak ucu
`require_partner` ile. İki kapı birbirine binmez:

* Ortak, yönetim panelinin hiçbir ucunu göremez.
* Yönetici de `/me` ucundan geçemez (kendi `partnerId` claim'i yoksa).

`partnerId` **claim'den** gelir, istekten değil — ortak başka bir ortağın
kimliğini gövdede gönderip veri çekemez. Sınır kontrol listesine değil,
yapıya dayanıyor.
"""
from __future__ import annotations

import logging
import secrets as py_secrets

from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from core import config
from core.auth import (AuthUser, get_current_user, require_admin,
                       require_owner, require_partner)
from core.i18n import get_language
from services import partner_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/me")
def partner_me(user: AuthUser = Depends(require_partner)):
    """Ortağın kendi panosu: huni + bakiye + kodlar + ödeme geçmişi.

    Dönen şekil `partner_service.partner_self_view` ile DAR tutulur —
    atfedilen gelir, kullanıcı kimlikleri ve diğer ortaklar dışarı
    çıkmaz. Ortağın görmesi gereken tek şey kendi performansı.
    """
    try:
        return partner_service.partner_self_view(user.partner_id)
    except partner_service.RedeemError as exc:
        # Claim var ama ortak kaydı silinmiş/pasifse: jenerik 403.
        # "Kayıt yok" demek, silinmiş bir ortağa sistemin şeklini anlatır.
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
        raise HTTPException(status_code=exc.status, detail=exc.reason)
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

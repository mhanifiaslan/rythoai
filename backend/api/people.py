"""Eklenen kişiler — eş, çocuk, ebeveyn, yakın (P-turu).

## Neden sunucudan yazılıyor

Kayıt `users/{uid}/people/{id}` altında ve Firestore kuralında **okuma
sahibe açık, yazma kapalı** (sohbet arşiviyle aynı desen). Sebep kontenjan:
kaç kişi eklenebileceği bir ürün gerçeğidir ve istemcide zorlanamaz —
Firestore kuralları koleksiyon sayamaz. Bu yüzden ekleme/silme buradan
geçer, okuma istemcinin kendi akışından.

## Yanıtta ne YOK

Kişinin adı. Sunucu onu hiç bilmiyor (bkz. services/people_service.py
dosya başı): etiket cihazda yaşıyor, burada yalnız `relation` var.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from core.auth import AuthUser, get_current_user
from core.i18n import get_language
from core.messages import text
from services import circle_context, people_service

logger = logging.getLogger(__name__)
router = APIRouter()


class PersonRequest(BaseModel):
    """Kişinin doğum verisi. Ad alanı BİLİNÇLİ OLARAK YOK."""

    relation: str = Field(default="other", max_length=32)
    #: "YYYY-MM-DD"
    birth_date: str = Field(min_length=10, max_length=10)
    #: "HH:MM" ya da None/boş — **bilinmiyor** demektir, 12:00 varsayılmaz.
    birth_time: str | None = Field(default=None, max_length=5)
    birth_city: str = Field(min_length=1, max_length=120)
    #: ISO-2 ülke kodu (şehir seçiciden).
    birth_nation: str | None = Field(default=None, max_length=2)
    #: "unspecified" = belirtilmedi. Varsayılan "female" idi ve kişinin
    #: BaZi şans sütunlarının yönü kadın kuralıyla hesaplanıyordu —
    #: ölçülmemiş cinsiyetten ölçülmüş gibi yön. ⚠️ Eski kayıtlardaki
    #: "female" ile gerçekten kadın olan ayırt EDİLEMEZ; bilinen sayılır.
    gender: str = Field(default="unspecified", max_length=16)

    def to_fields(self) -> dict:
        """Firestore alan adlarına çevirir (doğrulama serviste)."""
        return {
            "relation": self.relation,
            "birthDate": self.birth_date,
            "birthTime": self.birth_time,
            "birthCity": self.birth_city,
            "birthNation": self.birth_nation,
            "gender": self.gender,
        }


def _liste(uid: str) -> dict:
    kisiler = people_service.list_people(uid)
    return {
        "people": kisiler,
        "used": len(kisiler),
        "limit": people_service.slot_limit(uid),
        "relations": list(people_service.RELATIONS),
    }


@router.get("")
def list_people(user: AuthUser = Depends(get_current_user)):
    """Kişiler + kontenjan durumu.

    İstemci listeyi Firestore akışından da okuyor; bu uç kontenjanı
    (`limit`) bildirmek için var — abonelik durumu istemcide anlık
    değişebiliyor ve "kaç kişi ekleyebilirim" sorusunun cevabı sunucunun.
    """
    return {"status": "success", "data": _liste(user.uid)}


@router.post("")
def create_person(req: PersonRequest,
                  user: AuthUser = Depends(get_current_user),
                  lang: str = Depends(get_language)):
    """Kişi ekler. Kontenjan doluysa 402 + ``X-Paywall-Reason: people``."""
    kayit = people_service.create_person(user.uid, req.to_fields(), lang=lang)
    circle_context.invalidate(user.uid)
    return {"status": "success", "data": {"person": kayit, **_liste(user.uid)}}


@router.patch("/{person_id}")
def update_person(person_id: str, req: PersonRequest,
                  user: AuthUser = Depends(get_current_user),
                  lang: str = Depends(get_language)):
    """Doğum verisini düzeltir; Büyük Üçlü rozetleri birlikte tazelenir.

    Kontenjan BURADA sorulmaz: var olan bir kaydı düzeltmek yeni yer
    açmıyor. Aboneliği biten kullanıcı 10 kişisini düzeltmeye devam eder,
    yalnız yenisini ekleyemez — elindeki veriyi rehin almak olurdu.
    """
    kayit = people_service.update_person(user.uid, person_id,
                                         req.to_fields(), lang=lang)
    circle_context.invalidate(user.uid)
    return {"status": "success", "data": {"person": kayit}}


@router.delete("/{person_id}")
def delete_person(person_id: str,
                  user: AuthUser = Depends(get_current_user),
                  lang: str = Depends(get_language)):
    if not people_service.delete_person(user.uid, person_id):
        raise HTTPException(status_code=404, detail=text("people.missing", lang))
    circle_context.invalidate(user.uid)
    return {"status": "success", "data": _liste(user.uid)}

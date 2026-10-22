"""Rehber eşleşmesi — hash tabanlı, durumsuz, karşılıklı (Revize R3).

## Gizlilik sözleşmesi

* İstemci rehberdeki numaraları CİHAZDA E.164'e çevirir ve SHA-256'lar;
  sunucuya YALNIZCA hash listesi gelir. Ham numara ne ağdan geçer ne de
  burada görülür.
* Hash listesi SAKLANMAZ: eşleştir, sonucu dön, at. Loglara yalnızca adet
  yazılır. "Kullanıcının sosyal grafiğini biriktirmiyoruz" cümlesinin
  teknik karşılığı bu ucun durumsuzluğudur.
* **Karşılıklılık**: eşleşme yalnızca İKİ TARAF da `contactMatch` ayarını
  açmışsa döner. Tek taraflı açık ayar, kapalı tarafı görünür yapmaz —
  aksi telefon numarası bilinen herkesin uygulamadaki varlığını ifşa
  etmek olurdu.

## Neden sunucuda

Eşleşme dizini (`phoneHashes`) istemciye tamamen kapalı. Açık olsaydı bir
istemci rastgele numara hash'leriyle "bu numara Rytho'da mı" taraması
yapabilirdi (enumeration). Sunucu üzerinden geçince hem karşılıklılık
şartı uygulanabiliyor hem de istek kimlikli ve hız sınırlı.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from core import firestore as firestore_client
from core.auth import AuthUser, get_current_user
from core.i18n import get_language
from core.messages import text
from services import profile_service

logger = logging.getLogger(__name__)
router = APIRouter()

#: Tek istekte kabul edilen en fazla hash. Ortalama rehber ~500 kişi;
#: 2000 pratik tavanın üstü ve kötüye kullanım taramasını pahalılaştırır.
MAX_HASHES = 2000


class MatchRequest(BaseModel):
    hashes: list[str] = Field(max_length=MAX_HASHES)


def _kullanici(client, uid: str) -> dict:
    try:
        anlik = client.collection("users").document(uid).get()
        return (anlik.to_dict() or {}) if anlik.exists else {}
    except Exception:
        return {}


@router.post("/match")
def match(req: MatchRequest,
          user: AuthUser = Depends(get_current_user),
          lang: str = Depends(get_language)):
    """Rehber hash'lerini kayıtlı kullanıcılarla eşleştirir.

    Dönen kartlar `publicProfiles` içeriğidir — arkadaş listesinde zaten
    görünen türetilmiş alanlar; doğum verisi ASLA.
    """
    client = firestore_client.get_client()
    if client is None:
        raise HTTPException(status_code=503, detail=text("internal", lang))

    # Çağıranın kendi ayarı açık olmalı: kapalıyken istemci bu ucu hiç
    # çağırmaz; çağıran varsa istemci hatası ya da kötüye kullanım.
    ben = _kullanici(client, user.uid)
    if not ben.get("contactMatch"):
        raise HTTPException(status_code=403,
                            detail=text("contacts.disabled", lang))

    hashes = list(dict.fromkeys(h.strip().lower() for h in req.hashes if h))
    if not hashes:
        return {"status": "success", "matches": []}

    # Dizin okuması: doküman kimliği hash'in kendisi — sorgu değil get_all.
    # Eşleşen uid'in HANGİ hash'ten geldiği izlenir: istemci "bu kişi = bu
    # app kullanıcısı" eşlemesini kurup rehberini aktif/pasif ayırabilsin
    # (I-turu). Hash zaten istemcinin kendi gönderdiği değer; geri dönmesi
    # yeni bir mahremiyet açığı DEĞİL.
    refs = [client.collection("phoneHashes").document(h) for h in hashes]
    uid_hash: dict[str, str] = {}
    try:
        for anlik in client.get_all(refs):
            if not anlik.exists:
                continue
            uid = (anlik.to_dict() or {}).get("uid")
            if uid and uid != user.uid:
                # anlik.id doküman kimliği = hash.
                uid_hash.setdefault(uid, anlik.id)
    except Exception as exc:
        logger.warning("Rehber eşleşmesi dizin okuması düştü: %s", exc)
        raise HTTPException(status_code=500, detail=text("internal", lang))

    # Karşılıklılık + herkese açık kart.
    #
    # J-turu istisnası: KABUL EDİLMİŞ arkadaşlık, contactMatch'ten daha
    # güçlü bir karşılıklı rızadır — arkadaşın ayarı kapalı olsa bile
    # eşleşme döner. Gerekçe: (1) kişi çağırana ZATEN görünür (arkadaş
    # listesi), (2) numara zaten çağıranın rehberinde, (3) dönmezse
    # istemci arkadaşı "uygulamada yok" sanıp DAVET öneriyordu (iç test
    # bulgusu). are_friends çift taraflı doğrular (H2) — tek taraflı
    # uydurma burada da işlemez.
    kartlar = []
    for uid, eslesen_hash in uid_hash.items():
        karsi = _kullanici(client, uid)
        if (not karsi.get("contactMatch")
                and not profile_service.are_friends(user.uid, uid)):
            continue  # karşı taraf kapalı ve arkadaş değil: görünmez
        # U17: karşı taraf çağıranı engellediyse kartı (ad, foto, burç)
        # engellenene gösterilmez. Kural davet kenarını zaten reddediyor;
        # bu kapı olmasa engellenen kişi engelleyenin uygulamada olduğunu
        # ve kartını rehberinden görmeye devam ederdi.
        if profile_service.has_blocked(uid, user.uid):
            continue
        try:
            kart_anlik = client.collection("publicProfiles").document(uid).get()
        except Exception:
            continue
        if not kart_anlik.exists:
            continue
        kart = kart_anlik.to_dict() or {}
        kartlar.append({
            "uid": uid,
            "hash": eslesen_hash,
            "displayName": kart.get("displayName"),
            "username": kart.get("username"),
            "sunSign": kart.get("sunSign"),
            "photoUrl": kart.get("photoUrl"),
        })

    # Ham liste burada ölür: hiçbir hash kalıcı yazılmadı.
    logger.info("Rehber eşleşmesi: uid=%s girdi=%d eşleşme=%d",
                user.uid, len(hashes), len(kartlar))
    return {"status": "success", "matches": kartlar}

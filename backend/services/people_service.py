"""Kullanıcının kendi eklediği kişiler — eş, çocuk, ebeveyn, yakın (P-turu).

## Arkadaştan farkı

Arkadaş katmanı KARŞILIKLI RIZAYA dayanır: iki taraf da Rytho kullanıcısıdır,
davet kabul edilir, ve kimsenin ham doğum verisi karşı tarafın istemcisine
gitmez (bkz. profile_service dosya başı). Buradaki kişi ise **kullanıcı
değildir**: rızası alınamaz, hesabı yoktur, tepki gönderemez.

Bu yüzden iki nesne birbirine benzetilmez. Kişide seri, "bugün okudu mu" ve
dürtme YOKTUR — olmayan bir etkileşimi çizmek yalan olurdu.

## Adı neden burada yok

Doküman `displayName` TAŞIMAZ ve taşımamalı. Üçüncü bir kişinin kimliği
(ad + doğum tarihi + doğum yeri) rızası alınmadan sunucuya yazılmaz; bu
rehber tarafındaki duruşun aynısıdır (bkz. api/contacts.py: rehber adları
sunucuya hiç çıkmaz). Etiket CİHAZDA yaşar; sunucunun gördüğü tek kimlik
işareti ``relation`` alanıdır ve AI kişiyi "eşin" / "çocuğun" diye anar.

Bunun bedeli var ve bilinçli: telefonu değişen kullanıcı doğum verisini
kaybetmez ama etiketleri yeniden yazar.

## Kontenjan neden sunucuda

İstemciye güvenilmez ve asıl mesele maliyet: jetonlu her yüzeyin üst sınırını
aylık jeton hakkı zaten çiziyor (bkz. core/wallet.py), ama ilişki AI okuması
Plus'ta JETONSUZ üretiliyor — çift başına bir üretim + 30 gün önbellek. Kişi
sayısı sınırsız olsaydı bu yüzeyin tavanı da olmazdı. Kontenjan, jetonsuz
yüzeylerin matematiksel emniyetidir.
"""
from __future__ import annotations

import datetime as dt
import logging
import re
from typing import Any

from fastapi import HTTPException

from core import entitlements, firestore as firestore_client
from core.entitlements import PAYWALL_STATUS
from core.i18n import DEFAULT as DEFAULT_LANG
from core.messages import text
from services import profile_service

logger = logging.getLogger(__name__)

#: Kişi türleri. Küme KAPALI: serbest metin bir tür adı olarak sunucuya
#: giremez (uygulamanın genelindeki "serbest metin yok" duruşu) ve tür
#: doğrudan eksen adlarını ve AI'nın çerçevesini belirlediği için
#: tanınmayan bir değer sessizce yanlış sunuma yol açardı.
RELATIONS: tuple[str, ...] = (
    "partner",   # eş / sevgili
    "child",     # çocuk
    "parent",    # anne / baba
    "sibling",   # kardeş
    "friend",    # arkadaş (Rytho'da olmayan)
    "work",      # iş ilişkisi
    "other",
)

#: Kontenjan. Ücretsizdeki TEK kişi bilinçli: eşini ekleyip dört ekseni
#: ölçülmüş görüp yorumu kilitli bulmak, ürünün üretebileceği en dürüst
#: paywall'dır — gösterilen ölçüm gerçektir, eksik olan yalnız yorumdur.
FREE_PERSON_SLOTS = 1
PLUS_PERSON_SLOTS = 10

_TARIH_DESENI = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_SAAT_DESENI = re.compile(r"^\d{1,2}:\d{2}$")

#: Firestore'a yazılabilecek alanlar. Beyaz liste: istemciden gelen fazla
#: alan (ör. bir yerden sızmış `displayName`) dokümana GİRMEZ.
_YAZILABILIR = ("relation", "birthDate", "birthTime", "birthCity",
                "birthNation", "gender", "sunSign", "moonSign", "ascendant")


def _koleksiyon(uid: str):
    client = firestore_client.get_client()
    if client is None:
        return None
    return client.collection("users").document(uid).collection("people")


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def slot_limit(uid: str) -> int:
    """Bu kullanıcının kaç kişi ekleyebileceği."""
    return (PLUS_PERSON_SLOTS if entitlements.is_subscriber(uid)
            else FREE_PERSON_SLOTS)


# ---------------------------------------------------------------------------
# Okuma
# ---------------------------------------------------------------------------

def list_people(uid: str) -> list[dict[str, Any]]:
    """Kullanıcının kişileri (en eskiden yeniye). Ad TAŞIMAZ."""
    kol = _koleksiyon(uid)
    if kol is None:
        return []
    try:
        kayitlar = []
        for anlik in kol.stream():
            veri = anlik.to_dict() or {}
            veri["id"] = anlik.id
            kayitlar.append(veri)
    except Exception as exc:
        logger.warning("Kişiler okunamadı (%s): %s", uid, exc)
        return []
    kayitlar.sort(key=lambda k: str(k.get("createdAt") or ""))
    return kayitlar


def get_person(uid: str, person_id: str) -> dict[str, Any] | None:
    """Tek kişi — **sahiplik doğrulamasının tek yolu.**

    ``None`` dönmesi "bu kişi bu kullanıcının değil" demektir: kayıt
    çağıranın kendi ağacından okunuyor, başkasının person_id'si burada
    hiçbir zaman bulunamaz.
    """
    kol = _koleksiyon(uid)
    if kol is None:
        return None
    try:
        anlik = kol.document(person_id).get()
    except Exception as exc:
        logger.warning("Kişi okunamadı (%s/%s): %s", uid, person_id, exc)
        return None
    if not getattr(anlik, "exists", False):
        return None
    veri = anlik.to_dict() or {}
    veri["id"] = anlik.id
    return veri


def birth_kwargs(person: dict[str, Any], *,
                 name: str = "Gezgin") -> dict[str, Any]:
    """Kişi kaydını astro_service'in beklediği doğum verisine çevirir.

    Alan adları kullanıcı profiliyle BİREBİR aynı tutulduğu için dönüşüm
    `profile_service.birth_kwargs`'in kendisidir — iki dönüşümün zamanla
    ayrışması (saat-bilinmiyor kuralı gibi ince bir yerde) sessiz bir
    doğruluk hatası olurdu.

    ``name`` prompt'ta görünen addır; çağıran buraya kişinin GERÇEK adını
    değil, dile çevrilmiş ilişki etiketini verir ("eşin") — sunucu zaten
    adı bilmiyor.
    """
    kwargs = profile_service.birth_kwargs(person)
    kwargs["name"] = name
    return kwargs


# ---------------------------------------------------------------------------
# Yazma
# ---------------------------------------------------------------------------

def _dogrula(alanlar: dict[str, Any], lang: str) -> dict[str, Any]:
    """İstemciden geleni süzer ve biçimini doğrular; hatalıysa 400."""
    relation = str(alanlar.get("relation") or "other")
    if relation not in RELATIONS:
        raise HTTPException(status_code=400,
                            detail=text("people.invalid", lang))

    birth_date = str(alanlar.get("birthDate") or "").strip()
    if not _TARIH_DESENI.match(birth_date):
        raise HTTPException(status_code=400,
                            detail=text("people.invalid", lang))
    try:
        dt.date(*(int(p) for p in birth_date.split("-")))
    except ValueError:
        raise HTTPException(status_code=400,
                            detail=text("people.invalid", lang))

    # Saat YOKSA alan hiç yazılmaz. "12:00 varsayalım" ile "bilinmiyor"
    # arasındaki fark burada korunur; birth_kwargs hour_known'ı alanın
    # VARLIĞINDAN türetiyor (bkz. profile_service.birth_kwargs).
    ham_saat = str(alanlar.get("birthTime") or "").strip()
    birth_time: str | None = None
    if ham_saat:
        if not _SAAT_DESENI.match(ham_saat):
            raise HTTPException(status_code=400,
                                detail=text("people.invalid", lang))
        saat, dakika = (int(p) for p in ham_saat.split(":"))
        if not (0 <= saat <= 23 and 0 <= dakika <= 59):
            raise HTTPException(status_code=400,
                                detail=text("people.invalid", lang))
        birth_time = f"{saat:02d}:{dakika:02d}"

    sehir = str(alanlar.get("birthCity") or "").strip()
    if not sehir:
        raise HTTPException(status_code=400,
                            detail=text("people.invalid", lang))

    ulke = str(alanlar.get("birthNation") or "").strip().upper() or None
    # "unspecified" (belirtmek istemiyorum) kayda OLDUĞU GİBİ girer: BaZi
    # motoru bu değerde şans dönemlerinin yönünü HESAPLAMAZ (ölçülmeyen
    # söylenmez). Eski hâl beyaz liste dışını sessizce "female" yapıyordu —
    # api/people.py varsayılanı değişince bile kayıt yine kadın çıkıyordu
    # (D0'da ölçüldü; Pydantic varsayılanı kaydı korumuyor).
    cinsiyet = str(alanlar.get("gender") or "unspecified").strip()
    if cinsiyet not in ("female", "male", "other", "unspecified"):
        cinsiyet = "unspecified"

    temiz: dict[str, Any] = {
        "relation": relation,
        "birthDate": birth_date,
        "birthCity": sehir[:120],
        "gender": cinsiyet,
    }
    if birth_time:
        temiz["birthTime"] = birth_time
    if ulke:
        temiz["birthNation"] = ulke
    return temiz


def _buyuk_uclu(kayit: dict[str, Any]) -> dict[str, Any]:
    """Kişi için Büyük Üçlü rozetlerini hesaplar.

    Hesap düşerse rozet YAZILMAZ (silinir) — birth_record.dart'taki kuralın
    sunucu tarafı: bayat/yanlış burç göstermektense hiç göstermemek doğru.
    Kayıt yine de oluşur; okumalar zaten ham doğum verisinden hesaplanıyor.
    """
    try:
        from services import astro_service

        harita = astro_service.get_natal_chart(
            **astro_service.subject_kwargs(
                profile_service.birth_kwargs(kayit)),
            hour_known=bool(kayit.get("birthTime")))
    except Exception as exc:
        logger.info("Kişi haritası hesaplanamadı, rozet yazılmıyor: %s", exc)
        return {}

    rozetler = {}
    for alan, anahtar in (("sunSign", "sun_sign"), ("moonSign", "moon_sign"),
                          ("ascendant", "ascendant")):
        deger = harita.get(anahtar)
        if deger:
            rozetler[alan] = deger
    return rozetler


def create_person(uid: str, alanlar: dict[str, Any], *,
                  lang: str = DEFAULT_LANG) -> dict[str, Any]:
    """Kişi ekler; kontenjan dolmuşsa 402 (people) fırlatır."""
    temiz = _dogrula(alanlar, lang)

    kol = _koleksiyon(uid)
    if kol is None:
        raise HTTPException(status_code=503, detail=text("internal", lang))

    abone = entitlements.is_subscriber(uid)
    limit = PLUS_PERSON_SLOTS if abone else FREE_PERSON_SLOTS
    mevcut = len(list_people(uid))
    if mevcut >= limit:
        # Yarış penceresi bilinçli açık bırakıldı (consume_quota'daki aynı
        # yumuşaklık): eşzamanlı iki istek 11. kişiyi yaratabilir. Bunun
        # bedeli ayda ~$0,002; transaction içinde koleksiyon saymanın
        # karmaşıklığı buna değmiyor.
        #
        # Metin aboneye göre değişir: kontenjanı dolan aboneye "Rytho+ al"
        # demek anlamsız olurdu.
        raise HTTPException(
            status_code=PAYWALL_STATUS,
            detail=text("people.limit_plus" if abone else "people.limit_free",
                        lang, limit=limit),
            headers={"X-Paywall-Reason": "people"},
        )

    temiz.update(_buyuk_uclu(temiz))
    temiz["createdAt"] = _now()
    temiz["updatedAt"] = _now()

    ref = kol.document()
    ref.set(temiz)
    logger.info("Kişi eklendi: uid=%s tür=%s (%d/%d)",
                uid, temiz["relation"], mevcut + 1, limit)
    return {**temiz, "id": ref.id}


def update_person(uid: str, person_id: str, alanlar: dict[str, Any], *,
                  lang: str = DEFAULT_LANG) -> dict[str, Any]:
    """Kişinin doğum verisini düzeltir; rozetler birlikte tazelenir."""
    if get_person(uid, person_id) is None:
        raise HTTPException(status_code=404, detail=text("people.missing", lang))

    temiz = _dogrula(alanlar, lang)
    rozetler = _buyuk_uclu(temiz)

    kol = _koleksiyon(uid)
    if kol is None:
        raise HTTPException(status_code=503, detail=text("internal", lang))

    # Rozetler ya birlikte tazelenir ya silinir; saat kaldırıldıysa
    # `birthTime` de dokümandan düşmeli — merge kullanılmıyor, doküman
    # bütün olarak yeniden yazılıyor.
    yeni = {alan: temiz[alan] for alan in _YAZILABILIR if alan in temiz}
    yeni.update(rozetler)
    yeni["updatedAt"] = _now()
    kol.document(person_id).set(yeni)
    return {**yeni, "id": person_id}


def delete_person(uid: str, person_id: str) -> bool:
    """Kişiyi siler. Dönen değer: kayıt gerçekten var mıydı."""
    kol = _koleksiyon(uid)
    if kol is None:
        return False
    if get_person(uid, person_id) is None:
        return False
    kol.document(person_id).delete()
    logger.info("Kişi silindi: uid=%s", uid)
    return True


def delete_all(uid: str) -> int:
    """Hesap silinirken çağrılır — kişiler kullanıcıyla birlikte gider."""
    kol = _koleksiyon(uid)
    if kol is None:
        return 0
    silinen = 0
    try:
        for anlik in kol.stream():
            anlik.reference.delete()
            silinen += 1
    except Exception as exc:
        logger.warning("Kişiler silinemedi (%s): %s", uid, exc)
    return silinen

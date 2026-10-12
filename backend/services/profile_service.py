"""Kullanıcı profili okuma — sunucu tarafı.

Arkadaş katmanının gizlilik kuralı şudur: **bir kullanıcının ham doğum verisi
(tarih, saat, şehir) hiçbir zaman başka bir istemciye gönderilmez.** Doğum
tarihi + saati + yeri kimlik doğrulama sorularında kullanılan hassas bir
üçlüdür; yalnızca ondan türetilen yorum paylaşılır.

Bu yüzden ikili (dyad) okuma istemciden iki doğum verisi almaz; istemci sadece
arkadaşın kimliğini gönderir ve sunucu her iki profili buradan okur.
"""
from __future__ import annotations

import logging
from typing import Any

from core import firestore as firestore_client
from core.i18n import default_name
from services import prompts

logger = logging.getLogger(__name__)

_DEFAULT_DATE = "2000-01-01"
_DEFAULT_TIME = "12:00"


def _user_doc(uid: str):
    client = firestore_client.get_client()
    if client is None:
        return None
    return client.collection("users").document(uid)


def get_profile(uid: str) -> dict[str, Any] | None:
    """Kullanıcının Firestore profilini döndürür; yoksa ``None``."""
    doc_ref = _user_doc(uid)
    if doc_ref is None:
        return None
    try:
        snapshot = doc_ref.get()
    except Exception as exc:
        logger.warning("Profil okunamadı (%s): %s", uid, exc)
        return None
    return snapshot.to_dict() if snapshot.exists else None


def birth_kwargs(profile: dict[str, Any],
                 lang: str | None = None) -> dict[str, Any]:
    """Firestore profilini astro_service'in beklediği doğum verisine çevirir.

    İstemcideki `birthPayload` (apps/mobile/lib/core/api.dart) ile aynı
    dönüşümdür; alanlar eksikse aynı varsayılanlara düşer.
    """
    birth_date = profile.get("birthDate") or _DEFAULT_DATE
    birth_time = profile.get("birthTime") or _DEFAULT_TIME
    try:
        year, month, day = (int(p) for p in birth_date.split("-"))
        hour, minute = (int(p) for p in birth_time.split(":")[:2])
    except (ValueError, AttributeError):
        year, month, day = (int(p) for p in _DEFAULT_DATE.split("-"))
        hour, minute = 12, 0

    hour_known = bool(str(profile.get("birthTime") or "").strip())
    return {
        # Ad yoksa dile göre hitap (`i18n.default_name`); `lang` verilmeyen
        # servis çağrıları (sinyal, sinastri, çevre) varsayılan dile düşer.
        "name": profile.get("displayName") or default_name(lang),
        "year": year, "month": month, "day": day,
        "hour": hour, "minute": minute,
        "city": profile.get("birthCity") or "Istanbul",
        "nation": profile.get("birthNation"),
        "hour_known": hour_known,
    }


def chart_summary(profile: dict[str, Any] | None,
                  lang: str | None = None) -> str:
    """Sohbete iliştirilecek kompakt harita özeti.

    Sohbet ucu daha önce bu bilgiyi HİÇ almıyordu: istemci yalnızca mesaj ve
    geçmiş gönderiyor, persona da "doğum bilgisi sohbette geçiyorsa dokundur"
    diyordu. Sonuç olarak Rytho, kullanıcı kendi burcunu söylemediği sürece
    haritasından habersiz konuşuyordu — kişiselleştirmenin en temel parçası
    eksikti.

    Ham doğum verisi (tarih/saat/şehir) BURAYA GİRMEZ; yalnızca ondan
    türetilmiş konumlar. Modelin doğum tarihini bilmesine gerek yok.
    """
    if not profile:
        return ""

    # Etiketler ve burç adları isteğin dilinde. Profildeki değer Türkçe ve
    # sembollü ("Kova ♒") tutuluyor (mobil eşleştirmesi buna bağlı), bu yüzden
    # gösterilecek ada burada çevrilir.
    p = prompts.get(lang)
    satirlar = []
    ucler = [
        (p.PLANET_NAMES["Sun"], _yerel_burc(lang, profile.get("sunSign"))),
        (p.PLANET_NAMES["Moon"], _yerel_burc(lang, profile.get("moonSign"))),
        (p.PLANET_NAMES["Ascendant"],
         _yerel_burc(lang, profile.get("ascendant"))),
    ]
    buyuk_uclu = ", ".join(f"{ad}: {deger}" for ad, deger in ucler if deger)
    if buyuk_uclu:
        satirlar.append(f"- {buyuk_uclu}")

    if profile.get("wuXingElement"):
        satirlar.append(f"- {p.WU_XING_LABEL}: {profile['wuXingElement']}")
    if profile.get("mizac"):
        satirlar.append(f"- {p.TEMPERAMENT_LABEL}: {profile['mizac']}")

    return "\n".join(satirlar)


#: Türkçe burç adı -> dilden bağımsız anahtar. Profildeki değer sembol de
#: içerebildiği için ("Kova ♒") önek eşleşmesi yapılır.
_BURC_ANAHTARLARI = {
    "Koç": "aries", "Boğa": "taurus", "İkizler": "gemini", "Yengeç": "cancer",
    "Aslan": "leo", "Başak": "virgo", "Terazi": "libra", "Akrep": "scorpio",
    "Yay": "sagittarius", "Oğlak": "capricorn", "Kova": "aquarius",
    "Balık": "pisces",
}


def sun_sign_key(profile: dict[str, Any] | None) -> str | None:
    """Profildeki güneş burcunun dilden bağımsız anahtarı ("leo").

    Profilde değer Türkçe ve sembollü tutuluyor ("Kova ♒"); bildirim metni
    burç anahtarıyla önbelleklendiği için burada anahtara çevrilir.
    Tanınmazsa ``None`` döner — uydurma bir burçla bildirim göndermektense
    hiç göndermemek doğru.
    """
    if not profile:
        return None
    metin = str(profile.get("sunSign") or "").strip()
    if not metin:
        return None
    for ad, anahtar in _BURC_ANAHTARLARI.items():
        if metin == ad or metin.startswith(f"{ad} "):
            return anahtar
    return None


def _yerel_burc(lang: str | None, deger: Any) -> str:
    """Profildeki Türkçe burç değerini isteğin diline çevirir."""
    if not deger:
        return ""
    metin = str(deger).strip()
    for ad, anahtar in _BURC_ANAHTARLARI.items():
        if metin == ad or metin.startswith(f"{ad} "):
            return prompts.sign_name(lang, anahtar)
    return metin


def _friend_status(owner_uid: str, other_uid: str) -> str | None:
    """`users/{owner}/friends/{other}` dokümanının status'ü (yoksa None)."""
    doc_ref = _user_doc(owner_uid)
    if doc_ref is None:
        return None
    try:
        snapshot = doc_ref.collection("friends").document(other_uid).get()
    except Exception as exc:
        logger.warning("Arkadaşlık okunamadı (%s-%s): %s",
                       owner_uid, other_uid, exc)
        return None
    if not snapshot.exists:
        return None
    return (snapshot.to_dict() or {}).get("status")


def has_pending_invite(from_uid: str, to_uid: str) -> bool:
    """`from_uid` → `to_uid` yönünde BEKLEYEN bir davet var mı? (OB2)

    Davet push'unun spam kapısı: rules yalnız gerçek davet akışının
    `users/{to}/friends/{from} = incoming` kenarını kurmasına izin
    veriyor — kenar yoksa push da yok. Tek taraflı okuma yeter, çünkü
    doğrulanan şey davetin VARLIĞI, arkadaşlık yetkisi değil.
    """
    return _friend_status(to_uid, from_uid) == "incoming"


def are_friends(uid: str, other_uid: str) -> bool:
    """İki kullanıcı arasında **kabul edilmiş** arkadaşlık var mı?

    İkili okuma pahalı (LLM) ve kişiseldir; arkadaş olmayan biri hakkında
    üretilmesi hem bütçe hem gizlilik açığıdır. Bu yüzden uç bunu doğrular.

    ÇİFT TARAFLI doğrulama (H2 güvenlik onarımı): eskiden yalnız çağıranın
    kendi `friends/{other}` dokümanına bakılıyordu. Ama firestore.rules
    kullanıcının KENDİ ağacına yazmasına izin verdiği için saldırgan bu
    dokümana tek taraflı `accepted` yazıp arkadaş olmayan biri hakkında
    ikili okuma ürettirebiliyordu (+ onaysız dürtme/bildirim). Artık
    HER İKİ dokümanın da accepted olması şart; gerçek kabul iki tarafı da
    accepted yaptığı için meşru arkadaşlık etkilenmez.
    """
    return (_friend_status(uid, other_uid) == "accepted"
            and _friend_status(other_uid, uid) == "accepted")

"""Sohbetin "çevre" fısıltısı (KA6): model kullanıcının yakınlarını BİLSİN.

Cihaz bulgusu: kullanıcı eşini/çocuğunu eklediği hâlde sohbet bunlardan
tamamen habersizdi — `people_service` sohbet ucunda import bile edilmiyordu
ve sistem promptu Çevrem'den söz etmiyordu. Kullanıcının istediği duruş:
"seni ve çevreni bilen ama gerekli hâlde detaya inen bir astrolog" — yani
her turda KOMPAKT bir çevre listesi (bu modül), derin ilişki ölçümü ise
yalnız ilgili olduğunda (`api/chat.py`'deki bağlam zinciri).

Gizlilik değişmezi: eklenen kişilerin GERÇEK ADI sunucuda hiç yok (cihazda
kalır, P-turu kararı) — listede ilişki etiketi ("eşin") ve burçlar geçer.
Arkadaşların görünen adı zaten sunucuda (publicProfiles); en fazla birkaç
arkadaş, yalnız ad + Güneş burcu olarak anılır.
"""
from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)

#: Fısıltının üst sınırı — roster arka plan bilgisidir, prompt'u işgal etmez.
MAX_CIRCLE_CHARS = 400

#: Listeye giren en fazla arkadaş sayısı.
MAX_FRIENDS = 5

#: Önbellek ömrü. Kişi ekleme/silme `invalidate` ile anında düşürür;
#: arkadaş kabulü için 6 saatlik tazelik yeterli.
CIRCLE_TTL = 6 * 3600


def _anahtar(uid: str, lang: str | None) -> str:
    return f"circle-{uid}-{lang or 'tr'}"


def invalidate(uid: str) -> None:
    """Kişi eklendi/silindi ya da bir arkadaş hesabını sildi — her iki
    dilin kaydı düşer.

    `core.cache`'te silme API'si bilerek yok (tek çağıran biz olurduk);
    1 saniyelik TTL ile boş değer yazmak aynı işi görür: kayıt bir saniye
    içinde paylaşımlı kalıcı katmandan ve BU instance'ın belleğinden düşer,
    bir sonraki sohbet turu taze listeyi kurar.

    ⚠️ Sınır: BAŞKA bir instance listeyi daha önce okuduysa kendi bellek
    kopyası, kalıcı kayıttan aldığı bitiş anına kadar (en çok
    `CIRCLE_TTL`) yaşar — `cache.get_katmanli` terfide o anı kopyalıyor ve
    buradan erişilemez. Yani düşürme bu instance ve kalıcı katman için
    kesin, diğerleri için değil.
    """
    from core import cache
    for lang in ("tr", "en"):
        try:
            cache.set(_anahtar(uid, lang), "", ttl_seconds=1, owner_uid=uid)
        except Exception as exc:
            logger.info("Çevre önbelleği düşürülemedi (%s): %s", uid, exc)


def list_accepted_friend_uids(uid: str, limit: int = MAX_FRIENDS
                              ) -> list[str]:
    """Kabul edilmiş arkadaşların kimlikleri (en fazla `limit`).

    Tek taraflı okuma YETER: bu liste yalnız fısıltı içindir ve karşı
    tarafın adı/burcu zaten herkese açık profilde. Yetki gerektiren işler
    (dyad, ilişki okuması) çift taraflı `are_friends` ile korunmaya
    devam eder.
    """
    from core import firestore as firestore_client
    client = firestore_client.get_client()
    if client is None:
        return []
    try:
        kol = (client.collection("users").document(uid)
               .collection("friends"))
        return [anlik.id for anlik in kol.stream()
                if (anlik.to_dict() or {}).get("status") == "accepted"
                ][:limit]
    except Exception as exc:
        logger.warning("Arkadaş listesi okunamadı (%s): %s", uid, exc)
        return []


def _kisi_satiri(kayit: dict[str, Any], lang: str | None) -> str:
    from services import profile_service, prompts
    p = prompts.get(lang)
    etiket = prompts.relation_label(lang, kayit.get("relation"))
    burclar = []
    for alan, nokta in (("sunSign", "Sun"), ("moonSign", "Moon"),
                        ("ascendant", "Ascendant")):
        yerel = profile_service._yerel_burc(lang, kayit.get(alan))
        if yerel:
            burclar.append(f"{p.PLANET_NAMES[nokta]} {yerel}")
    satir = f"- {etiket}: " + (", ".join(burclar) if burclar else "?")
    if not str(kayit.get("birthTime") or "").strip():
        satir += f" ({p.CIRCLE_NO_HOUR})"
    return satir


#: Akraba/ilişki kelimeleri -> kişi türü (KA6). Normalize edilmiş alt-dize
#: eşleşmesi (bkz. `prompt_composer.normalize` — Türkçe İ/ı düzeltmesiyle).
#: Küme DAR ve çekirdek: yanlış pozitif (yanlış kişinin ölçümünü iliştirmek)
#: eksik eşleşmeden kötüdür; genişletme loglardan beslenir.
RELATION_KEYWORDS: dict[str, dict[str, tuple[str, ...]]] = {
    "tr": {
        "partner": ("eşim", "kocam", "karım", "sevgilim", "nişanlım",
                    "partnerim"),
        "child": ("oğlum", "kızım", "çocuğum", "evladım"),
        "parent": ("annem", "babam", "anam"),
        "sibling": ("kardeşim", "ablam", "abim", "ağabeyim"),
        "work": ("patronum", "müdürüm", "iş arkadaşım", "şefim"),
    },
    "en": {
        "partner": ("my wife", "my husband", "my partner", "my girlfriend",
                    "my boyfriend", "my fiance", "my fiancee", "my spouse"),
        "child": ("my son", "my daughter", "my child", "my kid"),
        "parent": ("my mother", "my mom", "my father", "my dad"),
        "sibling": ("my brother", "my sister", "my sibling"),
        "work": ("my boss", "my manager", "my coworker", "my colleague"),
    },
}


def match_relation(message: str, lang: str | None = None) -> str | None:
    """Mesaj bir yakını anıyorsa kişi türünü döndürür; yoksa None.

    Tek kelimelik anahtarlar KELİME BAŞI ile eşleşir, alt-dize ile DEĞİL:
    "kardeşimle" içinde "eşim" geçer ve düz `in` araması kardeş sorusunu
    partnere bağlardı (Türkçe alt-dizi tuzağı — testle sabitlendi).
    Kelime başı eşleşmesi Türkçe ekleri de karşılar ("eşimle", "eşime").
    Boşluklu anahtarlar ("my wife") alt-dize ile aranır.
    """
    import re
    from services.prompt_composer import normalize
    metin = normalize(message)
    kelimeler_kumesi = re.split(r"[^\wçğıöşü]+", metin)
    tablo = RELATION_KEYWORDS.get(lang if lang in RELATION_KEYWORDS
                                  else "tr", {})
    for tur, kelimeler in tablo.items():
        for k in kelimeler:
            if " " in k:
                if k in metin:
                    return tur
            elif any(kelime.startswith(k) for kelime in kelimeler_kumesi):
                return tur
    return None


def person_for_relation(uid: str, relation: str) -> str | None:
    """Bu türde doğum verili TAM BİR kişi varsa kimliği; yoksa None.

    Birden çok kişi aynı türdeyse TAHMİN EDİLMEZ (yanlış kişinin ölçümünü
    iliştirmek, hiç iliştirmemekten kötü) — çağıran yalnız roster'la
    yetinir ve INFO loglar; kullanıcı adıyla sorarsa istemci ad eşlemesi
    kimliği zaten gönderir.
    """
    from services import people_service
    adaylar = [k for k in people_service.list_people(uid)
               if (k.get("relation") or "other") == relation
               and str(k.get("birthDate") or "").strip()]
    if len(adaylar) == 1:
        return adaylar[0]["id"]
    if len(adaylar) > 1:
        logger.info("Akraba eşleşmesi belirsiz (%s, %s): %d aday — yalnız "
                    "roster verildi", uid, relation, len(adaylar))
    return None


#: Tema tetikli tali bağlam (KA6/3): günün sinyal temaları ilişkiye
#: değiyorsa bu öncelik sırasıyla bir kişinin ölçümü iliştirilir.
THEME_RELATION_PRIORITY = ("partner", "parent", "child", "sibling")


def priority_person(uid: str) -> str | None:
    """Öncelik sırasındaki ilk türden, doğum verili tek kişi."""
    for tur in THEME_RELATION_PRIORITY:
        kimlik = person_for_relation(uid, tur)
        if kimlik:
            return kimlik
    return None


def circle_whisper(uid: str, lang: str | None = None) -> str:
    """Kompakt çevre listesi; çevre boşsa boş string (fısıltı hiç girmez).

    Önbellekli (kullanıcı+dil, 6 saat): kişiler nadiren değişir ve
    arkadaş profillerini her sohbet turunda okumak gereksiz.
    """
    from core import cache
    anahtar = _anahtar(uid, lang)
    mevcut = cache.get(anahtar)
    if mevcut is not None:
        return mevcut

    from services import people_service, profile_service, prompts
    p = prompts.get(lang)
    satirlar: list[str] = []
    try:
        kisiler = people_service.list_people(uid)
    except Exception as exc:
        logger.warning("Çevre kişileri okunamadı (%s): %s", uid, exc)
        kisiler = []
    for kayit in kisiler:
        satirlar.append(_kisi_satiri(kayit, lang))

    arkadas_adlari: list[str] = []
    for fuid in list_accepted_friend_uids(uid):
        arkadas = profile_service.get_profile(fuid) or {}
        ad = arkadas.get("displayName") or arkadas.get("username")
        if not ad:
            continue
        burc = profile_service._yerel_burc(lang, arkadas.get("sunSign"))
        arkadas_adlari.append(f"{ad} ({burc})" if burc else str(ad))
    if arkadas_adlari:
        satirlar.append(p.CIRCLE_FRIENDS_LABEL + " "
                        + ", ".join(arkadas_adlari))

    metin = "\n".join(satirlar)[:MAX_CIRCLE_CHARS]
    cache.set(anahtar, metin, ttl_seconds=CIRCLE_TTL, owner_uid=uid)
    return metin

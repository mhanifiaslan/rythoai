"""Rapor / Prompt Mühendisliği Servisi.

Ham hesaplama çıktıları (astroloji, BaZi, yüz, I Ching, gökyüzü) doğrudan
LLM'e verilmez; burada yapılandırılmış prompt şablonlarına dönüştürülür,
RAG bağlamı eklenir, Gemini'ye gönderilir ve sonuç kullanıcı+gün bazında
önbelleklenir (maliyet kontrolü).
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import logging
from typing import Any, Callable

from core import cache, entitlements, i18n
from services import (
    chart_context,
    chart_query,
    fact_guard,
    firasa_service,
    gemini_service,
    memory_service,
    prompts,
)
from services.rag_service import retrieve_context

logger = logging.getLogger(__name__)


def _memory_block(memory: str, lang: str | None = None) -> str:
    """Hafıza bağlamını prompt'a iliştirilebilir bir bloğa çevirir.

    Hafıza boşsa hiçbir başlık yazılmaz — boş bir "KULLANICI HAKKINDA" başlığı
    modeli bilmediği şeyler uydurmaya davet eder.
    """
    memory = (memory or "").strip()
    if not memory:
        return ""
    return prompts.get(lang).MEMORY_BLOCK.format(memory=memory)


def _cached_generate(cache_key: str, prompt: str, fallback: str,
                     ttl_seconds: int = 24 * 3600,
                     lang: str | None = None,
                     owner_uid: str | None = None,
                     spend: Callable[[], None] | None = None,
                     refund: Callable[[], None] | None = None,
                     facts: dict[str, Any] | None = None,
                     feature: str | None = None) -> dict[str, Any]:
    """Üretimi önbellekli çalıştırır.

    ``owner_uid`` KİŞİYE ÖZEL üretimlerde verilir (günlük okuma, natal, BaZi,
    I Ching, sinastri, ikili dinamik). Önbellek dokümanının kimliği anahtarın
    özeti olduğu için kayıtlar kullanıcıya göre sorgulanamaz; hesap
    silindiğinde bu üretimlerin de silinebilmesi sahiplik alanına bağlı.

    Burç yorumu ve gökyüzü PAYLAŞIMLI olduğu için sahipsizdir — tek bir
    kullanıcının hesabını silmesi herkesin yorumunu silmemeli.

    ``spend`` token düşümüdür ve YALNIZCA önbellek kaçırıldığında, LLM
    çağrısından hemen önce çalışır: aynı rapora ikinci bakış ücretsizdir,
    çünkü sunucuya da maliyeti yoktur. Ücret ile maliyet aynı çizgide
    durursa kullanıcıya "neden yine ücret?" sorusu hiç doğmaz. Üretim
    fallback'e düşerse ``refund`` çağrılır — kullanıcı almadığı şeye ödemez.
    ``spend`` 402 fırlatabilir; o durumda LLM çağrısı hiç yapılmaz.

    Üretim yolunda yanıta ``persisted`` girer: metnin PAYLAŞIMLI
    (kalıcı) önbellek katmanına gerçekten yazılıp yazılmadığı. Gerekçe
    ``cache.set``in gövdesinde ölçüldü.
    """
    cached = cache.get(cache_key)
    if cached is not None:
        # ``persisted`` burada BİLEREK yok: ``cache.get`` önce belleğe
        # bakıyor, yani isabetin hangi katmandan geldiği ÖLÇÜLMEDİ.
        # Ölçülmeyen söylenmez — var olmayan anahtar, yanlış anahtardan
        # iyidir.
        return {"text": cached, "cached": True}

    if spend is not None:
        spend()

    text = gemini_service.generate(prompt, lang=lang,
                                   feature=feature, uid=owner_uid)
    if text:
        def yeniden(duzelti: str) -> str | None:
            return gemini_service.generate(duzelti, lang=lang,
                                           feature=feature, uid=owner_uid)
        text, grounded = fact_guard.enforce(
            text, prompt, lang=lang, regenerate=yeniden, facts=facts)

        # Önbellek ÖMRÜ bekçinin hükmüne BAĞLANMAZ — bilerek.
        #
        # Bekçi metinden iddia çıkarırken yakınlık kullanıyor, dilbilgisi
        # değil. Ölçüldü: aynı natal haritasıyla üç ayrı üretimde DOĞRU
        # raporlar da her seferinde 2-3 "uydurma" işareti aldı ve işaret
        # kümesi koşudan koşuya değişti (bir kez "Uranüs Yengeç", bir kez
        # "Ay Boğa"). Yani sinyal, ücretli bir raporun önbelleğini
        # kısaltacak kadar güvenilir değil.
        #
        # Kısa ömür verilirse sonuç şu olurdu: kullanıcı 5 jeton öder,
        # rapor bir saat sonra düşer, Atlas'ı açar, yine 5 jeton öder —
        # üstelik raporda gerçek bir hata olmadan. Bekçinin asıl faydası
        # zaten YENİDEN ÜRETİM: hata varsa modele iade edilip düzeltiliyor.
        # `ungrounded` yanıtta ve logda kalır (gözlem için), ücretlendirmeyi
        # etkilemez.
        # Yazım hatası isteği DÜŞÜRMEZ (fail-open, bkz. ``cache.set``)
        # ama artık SESSİZ de değil: paylaşımlı katmana yazılamayan bir
        # üretim, ısıtma yolunda "ısındı" SAYILMAMALI.
        kalici_yazildi = cache.set(cache_key, text,
                                   ttl_seconds=ttl_seconds,
                                   owner_uid=owner_uid)
        return {"text": text, "cached": False,
                "persisted": bool(kalici_yazildi),
                **({} if grounded else {"ungrounded": True})}
    # `refunded` ISTEMCININ durust cumlesini kurmasi icin (gz-2): jeton
    # harcamayan uclarda (gunluk okuma) "jetonun iade edildi" demek YALAN
    # olurdu, bu yuzden bayrak istemcide sabitlenmiyor — buradan geliyor.
    #
    # ⚠️ Bayrak "geri cagri GECILDI mi"yi DEGIL "iade YAZILDI mi"yi
    # soylemeli. Eskisi `refund is not None` idi ve iade yazimi dusup
    # `logger.warning` ile yutuldugunda ekranda YINE "jetonun iade edildi"
    # yaziyordu: odemis kullaniciya yalan bir soz, ustelik bakiyesi eksik.
    # `refund_spend` artik bakiye artisini GERCEKTEN yazdiysa True donuyor.
    iade_edildi = bool(refund()) if refund is not None else False
    # Yedek metin önbelleğe HİÇ yazılmaz; ``persisted`` burada bir hata
    # bildirimi değil, ölçülen hâlin kendisi — ve ısıtma yolu zaten
    # ``fallback``ı başarı saymıyor.
    return {"text": fallback, "cached": False, "fallback": True,
            "persisted": False, "refunded": iade_edildi}


def daily_reading(user_id: str, natal: dict[str, Any], sky: dict[str, Any],
                  lang: str | None = None,
                  birth: dict[str, Any] | None = None,
                  today: dt.date | None = None) -> dict[str, Any]:
    """Kişiye özel günlük kozmik yorum: natal harita x güncel gökyüzü.

    ``birth`` verilirse bugünün gökyüzünün HARİTAYA değdiği noktalar da
    prompt'a girer (Revize R8). Eskiden yalnızca genel gökyüzü (retrolar +
    gökyüzü geneli açılar) veriliyordu; transit-natal kesişimi — "bugün
    Satürn SENİN Güneşine kare" — sohbete gidiyor ama günlük okumaya
    gitmiyordu. Oysa kişisel günlük okumanın kişisel kısmı tam da bu.
    Ek LLM çağrısı YOK: transit hesabı yerel efemeris, önbellek anahtarı
    değişmedi.
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)
    # Gün, KULLANICININ yerel günü (D2). Sunucu UTC'de çalışıyor ve burada
    # `dt.date.today()` vardı: Türkiye'de gece yarısıyla 03:00 arasında
    # okuma hâlâ dünkü metni gösteriyordu.
    today = (today or entitlements.user_local_date(user_id)).isoformat()
    # Dil önbellek anahtarına girer; aksi halde İngilizce kullanıcı Türkçe
    # üretilmiş yorumu görür.
    cache_key = f"daily-{user_id}-{today}-{lang}"

    # Önbellek isabeti prompt kurulumundan ÖNCE denetlenir (horoscope_reading
    # ile aynı gerekçe): bu satırın altında bir RAG araması — yani her
    # istekte ücretli bir embedding çağrısı — var. Aynı gün ikinci kez açılan
    # okuma, düzeltmeden önce o çağrıyı BOŞUNA yapıyordu.
    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True}

    # Burç adları da dile göre: "Aslan" yazan bir İngilizce prompt modeli
    # Türkçeye kaydırıyor.
    yerel_harita = prompts.localize_chart(lang, natal)
    sun_sign = yerel_harita.get("sun_sign_local") or natal.get("sun_sign")
    moon_sign = yerel_harita.get("moon_sign_local") or natal.get("moon_sign")
    ascendant = (yerel_harita.get("ascendant_local")
                 or natal.get("ascendant") or p.NONE_LABEL)

    placements = " · ".join(
        f"{pt.get('name_local') or pt.get('name')}: "
        f"{pt.get('sign_local') or pt.get('sign_tr') or pt.get('sign')}"
        + (f" {pt['position']}°" if pt.get("position") is not None else "")
        + (f" ({p.HOUSE_FMT.format(house=pt['house_no'])})"
           if pt.get("house_no") else "")
        for pt in yerel_harita.get("points") or natal.get("points") or []
    ) or "-"

    # Bugünün gökyüzünün haritaya değdiği noktalar (Revize R8). Efemeris
    # düşerse okuma düşmez — transitsiz devam edilir; eski davranış buydu.
    transits = ""
    upcoming = ""
    if birth:
        try:
            olgular = chart_context.transit_facts(birth)
            transits = chart_context.transit_lines(olgular["hits"], lang)
            # YAKLAŞANLAR (T3): 7 gün içinde kesinleşen ilk iki transit.
            upcoming = chart_context.upcoming_lines(
                olgular.get("upcoming") or [], lang)
        except Exception as exc:
            logger.warning("Günlük okuma transitsiz: %s", exc)

    # Sorgu korpusun dilinde kurulur (chart_query gerekçesi): eski sabit
    # şablon TR korpusta İngilizce dolgu kelimeleriyle arıyordu.
    rag = retrieve_context(
        " ".join(filter(None, [
            chart_query.topic_seed("timing", lang),
            chart_query.topic_seed("temperament", lang),
            f"{sun_sign or ''} {moon_sign or ''}".strip(),
            transits,
        ])),
        lang=lang,
    )
    # Kullanıcı hafızası: günlük okumayı gerçekten kişisel yapan şey natal
    # harita değil (o herkes için sabit), zamanla biriken bu bağlam.
    memory = memory_service.memory_context(user_id, max_chars=400)

    retros = ", ".join(sky.get("retrogrades", [])) or "-"
    # HA1: yerelleştirme kararlı anahtarların üzerine yazmıyor; prompt
    # metni *_local alanlarından kurulur (alan yoksa kararlı anahtara
    # düşülür — elle kurulmuş test fikstürleri ve eski şekiller).
    aspects = "; ".join(
        f"{a.get('p1_local') or a['p1']}-{a.get('p2_local') or a['p2']} "
        f"{a.get('aspect_local') or a['aspect']}"
        for a in sky.get("aspects", [])[:5]
    )
    moon = prompts.localize_moon_phase(lang, sky.get("moon_phase"))

    prompt = p.DAILY.format(
        sun_sign=sun_sign, moon_sign=moon_sign,
        ascendant=ascendant, placements=placements, today=today,
        moon_name=moon.get("name"), moon_emoji=moon.get("emoji"),
        illumination=moon.get("illumination"), retros=retros, aspects=aspects,
        transits=transits or "-",
        upcoming=upcoming or "-",
        rag=rag, memory=_memory_block(memory, lang),
    )
    fallback = p.DAILY_FALLBACK.format(
        moon_name=moon.get("name") or "-",
        sun_sign=sun_sign or "-",
        ascendant=ascendant or "-",
    )
    return _cached_generate(cache_key, prompt, fallback, lang=lang,
                            owner_uid=user_id, facts=natal, feature="daily")


#: Dönem -> önbellek TTL'i. Anahtar tarih kovası içerdiği için TTL'in tek
#: görevi eski dosyaların diskte birikmesini önlemek; kova süresiyle hizalıdır.
_HOROSCOPE_TTL = {
    "daily": 24 * 3600,
    "weekly": 7 * 24 * 3600,
    "monthly": 31 * 24 * 3600,
}

def _horoscope_bucket(period: str, today: dt.date) -> str:
    """Önbellek tarih kovası: günlük YYYY-MM-DD, haftalık ISO yıl-hafta, aylık YYYY-MM."""
    if period == "weekly":
        iso = today.isocalendar()
        return f"{iso.year}-W{iso.week:02d}"
    if period == "monthly":
        return today.strftime("%Y-%m")
    return today.isoformat()


def horoscope_cache_key(sign: str, period: str, bucket: str, lang: str) -> str:
    """Burç yorumu önbellek anahtarı — kullanıcıdan bağımsız, dile bağlı.

    Dil anahtara girmek zorunda: girmezse İngilizce kullanıcı, aynı burç ve
    dönem için daha önce Türkçe üretilmiş yorumu görür.
    """
    return f"horoscope-{sign}-{period}-{bucket}-{lang}"


def horoscope_reading(sign: str, period: str, sky: dict[str, Any],
                      lang: str | None = None,
                      today: dt.date | None = None) -> dict[str, Any]:
    """Burç bazlı günlük/haftalık/aylık yorum.

    Kullanıcıdan BAĞIMSIZ önbelleklenir: anahtar (burç, dönem, tarih kovası,
    dil). Böylece dil x burç x dönem başına LLM'e en fazla 1 kez gidilir;
    sonraki tüm kullanıcılar aynı dönem içinde önbellekten okur.

    ``today`` isteğin sahibinin yerel günüdür (D2) ve önbelleği KİŞİSEL
    yapmaz: anahtara giren şey gün değil tarih KOVASI, ve dünyada aynı anda
    en fazla iki kova canlıdır. Yeni Zelanda'daki kullanıcı kendi gününü,
    Türkiye'deki kendi gününü okur; ikisi de aynı kovadaki herkesle aynı
    metni paylaşır.
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)
    today = today or dt.date.today()
    bucket = _horoscope_bucket(period, today)
    cache_key = horoscope_cache_key(sign, period, bucket, lang)

    # Önbellek isabeti en sık yoldur (dil x burç x dönem başına tek üretim,
    # geri kalan tüm istekler isabet). Bu yüzden prompt kurulmadan ÖNCE
    # bakılır: aksi halde her istekte RAG araması (ve embedding API çağrısı)
    # boşuna yapılırdı.
    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True, "generated_for": bucket}

    sign_name = p.SIGN_NAMES.get(sign, sign)
    period_name = p.PERIOD_NAMES.get(period, p.PERIOD_NAMES["daily"])
    length = p.PERIOD_LENGTHS.get(period, p.PERIOD_LENGTHS["daily"])

    retros = ", ".join(sky.get("retrogrades", [])) or "-"
    # HA1: *_local alanları (bkz. daily_reading'deki not).
    aspects = "; ".join(
        f"{a.get('p1_local') or a['p1']}-{a.get('p2_local') or a['p2']} "
        f"{a.get('aspect_local') or a['aspect']}"
        for a in sky.get("aspects", [])[:5]
    ) or "-"
    moon = prompts.localize_moon_phase(lang, sky.get("moon_phase"))
    # Gökyüzü/arketip tohumu + yerel burç adı (H1): eskiden 'temperament'
    # tohumu kullanılıyordu ve korpustaki burç→mizaç tablosunu (safravi...)
    # genel yoruma taşıyordu — kişiye özel veri olmadan mizaç uydurmaktı.
    # Genel yorum artık mizaç ÇEKMEZ.
    rag = retrieve_context(
        f"{chart_query.topic_seed('horoscope', lang)} {sign_name}",
        lang=lang)

    prompt = p.HOROSCOPE.format(
        sign=sign_name, period=period_name, period_upper=period_name.upper(),
        length=length, today=today.isoformat(),
        moon_name=moon.get("name"), moon_emoji=moon.get("emoji"),
        illumination=moon.get("illumination"), retros=retros, aspects=aspects,
        rag=rag,
    )
    fallback = p.HOROSCOPE_FALLBACK.format(
        sign=sign_name, period=period_name,
        moon_name=moon.get("name") or "-",
    )
    result = _cached_generate(
        cache_key, prompt, fallback,
        ttl_seconds=_HOROSCOPE_TTL.get(period, 24 * 3600), lang=lang,
        feature="horoscope",
    )
    result["generated_for"] = bucket
    return result


def dyad_key_for(pair_key: str, today: dt.date) -> str:
    """İkili okuma önbellek anahtarı — hazır ikili kimliğinden (P-turu).

    İki arkadaş aynı günü aynı metinle görmeli: hem tek üretim yapılır hem
    de aralarında konuşulabilecek ortak bir şey oluşur. Bu SİMETRİ artık
    burada değil, `synastry_service.Counterpart.key` üretilirken sağlanıyor
    (arkadaşta sıralı ikili) — çünkü karşı taraf bir arkadaş da olabilir,
    kullanıcının eklediği bir kişi de.

    Burada TEKRAR sıralamak simetriyi BOZARDI: "a" kullanıcısı için
    `sorted(("a", "a-b"))` ile "b" kullanıcısı için `sorted(("b", "a-b"))`
    farklı anahtar üretir, yani iki arkadaş aynı günü iki kez ürettirir ve
    **ikisi de 3 jeton öder**. Arkadaş yolunda üretilen dize eski
    `dyad_cache_key`'inkiyle birebir aynı: mevcut kayıtlar duruyor.
    """
    return f"dyad-{pair_key}-{today.isoformat()}"


def dyad_reading(uid_a: str, pair_key: str, name_a: str, name_b: str,
                 synastry: dict[str, Any], sky: dict[str, Any],
                 lang: str | None = None,
                 spend: Callable[[], None] | None = None,
                 refund: Callable[[], None] | None = None,
                 today: dt.date | None = None,
                 pair_transits: str = "") -> dict[str, Any]:
    """İki arkadaş için GÜNLÜK ikili dinamik okuması.

    Kalıcı bir uyum skoru üretilmez. Gerekçe iki katlı: skor ölçüm değil
    gelenektir (ürünün dürüstlük ilkesi), ve geri alınamaz bir damga gerçek
    ilişkilere zarar verir. Bunun yerine bugüne özgü, yarın değişebilecek bir
    dinamik anlatılır.

    Gün, İSTEYEN tarafın yerel günü (D2). Çift bazlı anahtarın iki ucu
    farklı dilimlerdeyse bir taraf ötekinden birkaç saat önce yeni okumaya
    geçer — kabul edilen bir kayma; alternatifi, iki profili de okuyup
    "ortak gün" uydurmaktı.
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)
    today = today or entitlements.user_local_date(uid_a)
    cache_key = dyad_key_for(pair_key, today)

    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True, "generated_for": today.isoformat()}

    yerel_sinastri = prompts.localize_synastry(lang, synastry)
    # İlk 6 artık "en ÖNEMLİ 6": `_aspects_list` kaynakta öneme göre
    # sıralıyor (1.6.0). Eskiden kerykeion'un gezegen sırasıydı ve modele
    # her çiftte aynı karakterde bir liste gidiyordu — önce Güneş, sonra
    # Ay, orb'u 7°'ye varan geniş açılar; dar orb'lu asıl temaslar hiç
    # ulaşmıyordu.
    aspects = "\n".join(
        f"- {a['p1_local']} ({name_a}) {a['aspect_local']} {a['p2_local']} "
        f"({name_b}) orb {a['orbit']}°"
        for a in yerel_sinastri.get("aspects", [])[:6]
    ) or p.NO_ASPECTS

    # Ölçülen eksenler de prompta girer: ham açı listesi modele "ne
    # ölçtük" demiyor, yalnız "ne var" diyor. Seviye/ton zemini olmadan
    # model her çift için kendi genel çerçevesini kuruyordu.
    eksen_ozeti = ""
    try:
        from services import synastry_service
        eksenler = prompts.localize_relationship_axes(
            lang, synastry_service.relationship_axes(synastry))
        eksen_ozeti = "\n".join(
            f"- {e['axis_local']}: {e['level_local']} · {e['tone_local']}"
            for e in eksenler.get("axes") or [])
    except Exception as exc:  # ölçüm çıkmazsa okuma yine üretilir
        logger.warning("Dyad eksen özeti üretilemedi: %s", exc)

    moon = prompts.localize_moon_phase(lang, sky.get("moon_phase"))
    retros = ", ".join(sky.get("retrogrades", [])) or p.NONE_LABEL
    # İlişki + zamanlama tohumları isteğin dilinde (Revize R8).
    rag = retrieve_context(
        f"{chart_query.topic_seed('relationship', lang)} "
        f"{chart_query.topic_seed('timing', lang)}",
        lang=lang)

    prompt = p.DYAD.format(
        name_a=name_a, name_b=name_b, today=today.isoformat(),
        moon_name=moon.get("name"), moon_emoji=moon.get("emoji"),
        illumination=moon.get("illumination"), retros=retros,
        aspects=aspects, axes=eksen_ozeti or p.NO_ASPECTS, rag=rag,
        # GT5: çifte özgü BUGÜN — eskiden okumanın tek günlük girdisi
        # herkese aynı Ay evresi + retro listesiydi; "günlük" okuma
        # aslında çift için günlük değildi (cihaz bulgusu).
        pair_transits=pair_transits or p.PAIR_NO_TRANSITS,
    )
    fallback = p.DYAD_FALLBACK.format(
        name_a=name_a, name_b=name_b, moon_name=moon.get("name") or "-")
    # Okuma iki kişiye ait ama sahiplik tek alan; isteyen taraf yazılır.
    # Zaten 24 saatlik ömrü var, kalan taraf için de kısa sürede düşer.
    result = _cached_generate(cache_key, prompt, fallback,
                              ttl_seconds=24 * 3600, lang=lang,
                              owner_uid=uid_a, spend=spend, refund=refund,
                              feature="dyad")
    result["generated_for"] = today.isoformat()
    return result


def relationship_reading(uid: str, pair_key: str, me_name: str,
                         friend_name: str, axes: dict[str, Any],
                         lang: str | None = None,
                         relation: str | None = None) -> dict[str, Any]:
    """İlişkinin ÖLÇÜLEN yapısının AI okuması (1.6.0).

    ## Neden LLM

    Bu metin daha önce `SYNASTRY_AXIS_LINES` tablosundan geliyordu: eksen
    başına hazır cümle, yalnız eksen × ton ile anahtarlı, tüm üründe 16
    cümle. Ölçüldü — 15 çiftin 15'i FARKLI ölçüm üretiyor ama yalnız 12'si
    farklı metin görüyordu; üç çift dört cümlenin dördünü de birebir aynı
    okuyordu. Kullanıcının bulgusu buydu: "tüm arkadaşlarla aynı cevaplar".

    Ürün kararı (kullanıcı): *"neye dayandığını AI yorumlamalı, asla
    varyant olarak yazılmış hazır cevaplar olmamalı."*

    ## Girdi ölçümdür

    Modele dört eksenin seviyesi/tonu ve o çifte özgü dayanak açılar
    (gezegen + açı + orb) verilir. Ham doğum verisi GİRMEZ — arkadaşın
    doğum tarihi/saati/yeri hiçbir katmanda taşınmaz (dyad kuralı).
    Prompt "yalnız verilen açılardan konuş" kısıtını taşır.

    ## Önbellek

    Anahtar ÇİFTE özeldir ve simetriktir; girdisi natal veridir, yani
    doğum bilgisi değişmedikçe sonuç değişmez. 30 gün. Bu paylaşımlı bir
    kalıp değil, o çiftin kendi okumasıdır — başkasının metni kimseye
    gösterilmez. Amaç: aynı analizi iki kez ürettirmemek ve ekranın
    anında açılması.

    Jeton düşülmez: çift başına tek üretim + 30 gün ömür, maliyet ihmal
    edilebilir. Kapı abonelik (çağıran uçta).
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)

    # `pair_key` çağırandan gelir (P-turu): arkadaşta sıralı ikili — yani
    # anahtar DEĞİŞMEDİ, mevcut kayıtlar duruyor — eklenen kişide sahibe
    # özel ve doğum özetli kimlik.
    #
    # v2: önbellekten gelen yanıt ARTIK ayrıştırılıyor (aşağıya bak).
    # Sürüm artırıldı ki eski kayıtlar — kartları boş bırakanlar —
    # kendiliğinden düşsün. Bu okuma jetonsuz; tazelenmesi kimseye
    # ücret yazmaz.
    cache_key = (f"rel-reading-v2-{axes.get('calc_version')}-{pair_key}-{lang}")
    cached = cache.get(cache_key)
    if cached is not None:
        # ÖNBELLEK YOLU DA AYRIŞTIRIR.
        #
        # Buradaki erken dönüş eksen cümlelerini taşımıyordu ve kusur tam
        # olarak şöyle görünüyordu: ilk açılışta kartlar dolu (üretim
        # yolundan geçiliyor), İKİNCİ açılıştan itibaren boş — üstelik
        # önbellek 30 gün olduğu için o çift kalıcı olarak boş kalıyordu.
        # Cihazda "bazı arkadaşlarda önce dolu geldi sonra yine boş geldi"
        # diye görüldü.
        return {"text": cached, "cached": True,
                **parse_relationship_reading(cached)}

    yerel = prompts.localize_relationship_axes(lang, axes, relation)
    satirlar = []
    for e in yerel.get("axes") or []:
        baslik = (f"- {e['axis_local']}: {e['level_local']} · "
                  f"{e['tone_local']}")
        kanitlar = [
            f"{b['p1_local']} {b['aspect_local']} {b['p2_local']} "
            f"(orb {b['orb']}°)"
            for b in (e.get("basis") or [])
        ]
        # Dayanak yoksa bunu AÇIKÇA yaz: model "ölçülmedi" diyebilsin diye
        # bilgi eksikliğinin kendisi de girdidir.
        satirlar.append(
            baslik + (" — " + "; ".join(kanitlar) if kanitlar
                      else f" — {p.NO_ASPECTS}"))

    # İlişki türü çerçevesi (P-turu): ölçüm aynı kalır, AI'nın dili
    # türe göre kısıtlanır — çocuğuyla "çekim" konuşulmaz.
    prompt = p.RELATIONSHIP.format(
        me=me_name, friend=friend_name, axes="\n".join(satirlar),
        frame=prompts.relation_frame(lang, relation))
    fallback = p.RELATIONSHIP_FALLBACK.format(friend=friend_name)

    sonuc = _cached_generate(cache_key, prompt, fallback,
                             ttl_seconds=30 * 24 * 3600, lang=lang,
                             owner_uid=uid, feature="relationship")
    cozum = parse_relationship_reading(sonuc["text"])

    # Biçimi tutmayan üretim 30 GÜN KİLİTLENMESİN.
    #
    # Model `communication:` gibi anahtarları atlarsa eksen cümlesi
    # çıkmıyor ve kartlar boş kalıyor. Bunu bir ay boyunca saklamak, tek
    # bir kötü üretimi o çift için kalıcı hale getirirdi. Kısa ömür verip
    # bir sonraki açılışta yeniden denemek daha ucuz: bu okuma jetonsuz.
    if not cozum.get("axis_lines") and not sonuc.get("fallback"):
        cache.set(cache_key, sonuc["text"], ttl_seconds=3600,
                  owner_uid=uid)
        logger.warning("İlişki okuması biçimi tutmadı; kısa ömürle "
                       "saklandı (%s)", cache_key)
    return {**sonuc, **cozum}


#: Eksen anahtarları model çıktısında AYNEN beklenir — dilden bağımsız
#: olsun diye İngilizce anahtar, metin isteğin dilinde.
_OKUMA_ANAHTARLARI = ("communication", "emotional", "attraction", "bond",
                      "theme")


def parse_relationship_reading(text: str) -> dict[str, Any]:
    """Modelin `anahtar: cümle` çıktısını eksen sözlüğüne çevirir.

    ## Neden eksen bazlı

    İlk sürümde okuma TEK BLOK dönüyordu ve eksen kartlarında hiçbir
    cümle kalmamıştı: kullanıcı dört boş kart ve dört "Rytho'ya sor"
    gördü — "neyi soracak!". Kartın işi merak uyandırmak; o yüzden her
    eksenin kendi tek cümlelik ipucu olmalı. Hazır tablo yine YOK:
    cümleleri o çift için model yazıyor.

    Ayrıştırma HOŞGÖRÜLÜ: model biçimi tutturamazsa sözlük boş döner ve
    çağıran katman tam metni tek blok olarak gösterir. Uydurma cümle
    üretilmez — biçim hatasında eksik kalmak, yanlış şey göstermekten
    iyidir.
    """
    eksenler: dict[str, str] = {}
    tema = ""
    aktif: str | None = None
    for ham in (text or "").split("\n"):
        satir = ham.strip().lstrip("-*• ").strip()
        if not satir:
            aktif = None
            continue
        anahtar = None
        if ":" in satir:
            aday = satir.split(":", 1)[0].strip().lower()
            # `**communication**` gibi süslemeleri de tanı.
            aday = aday.strip("*_# ").strip()
            if aday in _OKUMA_ANAHTARLARI:
                anahtar = aday
        if anahtar:
            deger = satir.split(":", 1)[1].strip().strip("*_ ").strip()
            if anahtar == "theme":
                tema = deger
            else:
                eksenler[anahtar] = deger
            aktif = anahtar
        elif aktif:
            # Cümle alt satıra taşmışsa devamını ekle.
            if aktif == "theme":
                tema = (tema + " " + satir).strip()
            else:
                eksenler[aktif] = (eksenler[aktif] + " " + satir).strip()
    return {"axis_lines": eksenler, "theme": tema}


#: Natal rapor önbelleği: Güneş+Yükselen yetmez — saat düzeltilip ikisi
#: aynı kalsa 30 gün eski rapor servis edilirdi (denetim).
NATAL_REPORT_VERSION = "3"


def _natal_cache_digest(natal: dict[str, Any]) -> str:
    """Hesaplanmış haritanın önbellek özeti — ham doğum verisi yok."""
    parcalar = [
        f"{pt.get('name')}:{pt.get('abs_position')}:{pt.get('house_no')}"
        for pt in natal.get("points") or []
    ]
    asc = natal.get("asc") or {}
    parcalar.append(f"asc:{asc.get('sign')}:{asc.get('position')}")
    parcalar.append(f"hk:{natal.get('hour_known', True)}")
    ham = "|".join(parcalar)
    return hashlib.sha256(ham.encode("utf-8")).hexdigest()[:16]


def natal_report(user_id: str, natal: dict[str, Any],
                 lang: str | None = None,
                 spend: Callable[[], None] | None = None,
                 refund: Callable[[], None] | None = None) -> dict[str, Any]:
    """Derinlemesine doğum haritası raporu (kullanıcı başına bir kez, 30 gün önbellek)."""
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)
    cache_key = (f"natal-report-v{NATAL_REPORT_VERSION}-{user_id}-"
                 f"{_natal_cache_digest(natal)}-{lang}")

    # İsabette embedding çağrısını atla (bkz. daily_reading'deki gerekçe).
    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True}

    # Harita adları isteğin diline çevrilir: koşulsuz `_tr` seçmek İngilizce
    # prompt'a Türkçe gezegen ve burç adları sokuyordu.
    yerel = prompts.localize_chart(lang, natal)
    sun_sign = yerel.get("sun_sign_local") or natal.get("sun_sign")
    moon_sign = yerel.get("moon_sign_local") or natal.get("moon_sign")
    ascendant = (yerel.get("ascendant_local") or natal.get("ascendant")
                 or p.NONE_LABEL)

    points = "\n".join(
        f"- {pt['name_local']}: {pt['sign_local']} {pt['position']}°"
        + (f" ({p.HOUSE_FMT.format(house=pt.get('house_no') or pt.get('house'))}"
           f"{', ' + p.RETROGRADE_LABEL if pt.get('retrograde') else ''})"
           if (pt.get("house_no") or pt.get("house")) else
           (f" ({p.RETROGRADE_LABEL})" if pt.get("retrograde") else ""))
        for pt in yerel.get("points", [])[:12]
    )
    aspects = "\n".join(
        f"- {a['p1_local']} {a['aspect_local']} {a['p2_local']} (orb {a['orbit']}°"
        f"{', ' + a['movement_local'] if a.get('movement_local') else ''})"
        for a in yerel.get("aspects", [])[:10]
    )
    # Beyanlar (T0): varsa prompt'a ayrı blok — model belirsizliği bilerek
    # konuşur (ör. şehir çözülemedi → Yükselen yaklaşık).
    beyanlar = yerel.get("disclosure_texts") or []
    disclosures = ("\n" + p.DISCLOSURES_LABEL + "\n"
                   + "\n".join(f"- {b}" for b in beyanlar) + "\n"
                   ) if beyanlar else ""

    # Denge + deklinasyon (T4). Sıfır sayımlar da yazılır: eksik element
    # astrolojik bir ifadedir (chart_context.render ile aynı kural).
    el_dagilimi = natal.get("element_distribution") or {}
    elements = ", ".join(
        f"{p.ELEMENT_NAMES[e]} {el_dagilimi.get(e, 0)}"
        for e in ("fire", "earth", "air", "water")) if el_dagilimi else "-"
    nit_dagilimi = natal.get("modality_distribution") or {}
    modalities = ", ".join(
        f"{p.MODALITY_NAMES[m]} {nit_dagilimi.get(m, 0)}"
        for m in ("cardinal", "fixed", "mutable")) if nit_dagilimi else "-"
    stelliums = " · ".join(
        p.CHART_STELLIUM_FMT.format(
            house=p.HOUSE_FMT.format(house=y["house"]), count=y["count"])
        for y in natal.get("stelliums") or []) or "-"
    declinations = "\n".join(
        f"- {d['p1_local']} {d['type_local']} {d['p2_local']} "
        f"(Δ {d['delta']}°)"
        for d in yerel.get("declination_aspects") or []) or "-"
    # Sorgu haritadan ve isteğin dilinde (Revize R8): burçlar + en sıkı açı.
    # Eski sabit şablon TR korpusta İngilizce dolgu kelimeleriyle arıyordu.
    en_siki = next(iter(yerel.get("aspects", [])), None)
    rag = retrieve_context(
        " ".join(filter(None, [
            chart_query.topic_seed("temperament", lang),
            chart_query.topic_seed("self", lang),
            f"{sun_sign or ''} {moon_sign or ''} {ascendant or ''}".strip(),
            (f"{en_siki['p1_local']} {en_siki['aspect_local']} "
             f"{en_siki['p2_local']}") if en_siki else "",
        ])),
        lang=lang,
    )

    prompt = p.NATAL.format(
        sun_sign=sun_sign, moon_sign=moon_sign,
        ascendant=ascendant, points=points, aspects=aspects, rag=rag,
        elements=elements, modalities=modalities, stelliums=stelliums,
        declinations=declinations, disclosures=disclosures,
    )
    fallback = p.NATAL_FALLBACK.format(
        sun_sign=sun_sign, moon_sign=moon_sign, ascendant=ascendant,
    )
    return _cached_generate(cache_key, prompt, fallback,
                            ttl_seconds=30 * 24 * 3600, lang=lang,
                            owner_uid=user_id, spend=spend, refund=refund,
                            facts=natal, feature="natal")


def solar_return_report(user_id: str, sr: dict[str, Any],
                        lang: str | None = None,
                        spend: Callable[[], None] | None = None,
                        refund: Callable[[], None] | None = None
                        ) -> dict[str, Any]:
    """Solar return (yıl haritası) okuması (T1). 90 gün önbellek.

    Anahtar dönüş anına ve hesap sürümüne bağlı: aynı SR yılı içinde aynı
    yorum servis edilir; yeni dönüş geldiğinde anahtar kendiliğinden değişir.
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)
    # Konum anahtara girer (D3): harita başka bir şehre kurulunca Yükselen
    # ve evler tamamen değişir — eski rapor artık o haritayı anlatmıyor.
    cache_key = (f"solar-return-{user_id}"
                 f"-{str(sr.get('return_at_utc'))[:10]}"
                 f"-{(sr.get('location') or {}).get('city') or '-'}"
                 f"-{sr.get('calc_version')}-{lang}")
    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True}

    yerel = prompts.localize_chart(lang, sr)
    sr_ay = prompts.sign_name_from_code(lang, sr.get("sr_moon_sign"))
    asc = sr.get("sr_ascendant")
    sr_asc = (f"{prompts.sign_name_from_code(lang, asc['sign'])} "
              f"{asc['position']}°") if asc else "-"
    sr_ev = str(sr.get("sr_sun_house") or "-")

    points = "\n".join(
        f"- {pt['name_local']}: {pt['sign_local']} {pt['position']}°"
        f"{', ' + p.RETROGRADE_LABEL if pt.get('retrograde') else ''}"
        for pt in yerel.get("points", [])[:12])
    aspects = "\n".join(
        f"- {a['p1_local']} {a['aspect_local']} {a['p2_local']} "
        f"(orb {a['orbit']}°)"
        for a in yerel.get("aspects", [])[:10])
    beyanlar = yerel.get("disclosure_texts") or []
    disclosures = ("\n" + p.DISCLOSURES_LABEL + "\n"
                   + "\n".join(f"- {b}" for b in beyanlar) + "\n"
                   ) if beyanlar else ""

    rag = retrieve_context(
        p.SOLAR_RETURN_RAG_QUERY.format(sr_moon=sr_ay, sr_asc=sr_asc),
        lang=lang)

    prompt = p.SOLAR_RETURN.format(
        return_at=sr.get("return_at_local"),
        next_return_at=sr.get("next_return_at_local"),
        sr_asc=sr_asc, sr_sun_house=sr_ev, sr_moon=sr_ay,
        points=points, aspects=aspects, disclosures=disclosures, rag=rag)
    fallback = p.SOLAR_RETURN_FALLBACK.format(
        return_at=sr.get("return_at_local"), sr_moon=sr_ay)
    return _cached_generate(cache_key, prompt, fallback,
                            ttl_seconds=90 * 24 * 3600, lang=lang,
                            owner_uid=user_id, spend=spend, refund=refund,
                            facts=sr, feature="solar_return")


def progressions_report(user_id: str, prog: dict[str, Any],
                        hits: list[dict[str, Any]],
                        lang: str | None = None,
                        spend: Callable[[], None] | None = None,
                        refund: Callable[[], None] | None = None
                        ) -> dict[str, Any]:
    """İkincil progresyon "iç mevsim" okuması (T2). 30 gün önbellek.

    Progres Ay ~2.5 ayda burç değiştirir; anahtar ay hassasiyetinde
    (as_of'un yıl-ay kısmı) — aynı takvim ayında aynı yorum servis edilir,
    TTL bayat kalıntıyı süpürür.
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)
    cache_key = (f"progressions-{user_id}"
                 f"-{str(prog.get('as_of'))[:7]}"
                 f"-{prog.get('calc_version')}-{lang}")
    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True}

    yerel = prompts.localize_progressions(lang, prog, hits)
    ay = yerel.get("prog_moon") or {}
    gunes = yerel.get("prog_sun") or {}
    ev = ay.get("natal_house")
    ay_evi = (f" ({p.PROGRESSIONS_HOUSE_LABEL.format(house=ev)})"
              if ev else "")
    asc = yerel.get("prog_asc")
    mc = yerel.get("prog_mc")
    asc_metin = (f"{asc['sign_local']} {asc['position']}°" if asc else "-")
    mc_metin = (f"{mc['sign_local']} {mc['position']}°" if mc else "-")

    vurgu_satirlari = "\n".join(
        f"- {h['directed_local']} {h['aspect_local']} {h['natal_local']}"
        f" — {h['exact_on'][:7]}"
        for h in yerel.get("solar_arc_hits") or []) or "-"
    beyanlar = yerel.get("disclosure_texts") or []
    disclosures = ("\n" + p.DISCLOSURES_LABEL + "\n"
                   + "\n".join(f"- {b}" for b in beyanlar) + "\n"
                   ) if beyanlar else ""

    rag = retrieve_context(
        p.PROGRESSIONS_RAG_QUERY.format(
            prog_moon_sign=ay.get("sign_local", ""),
            prog_phase=ay.get("phase_local", "")),
        lang=lang)

    doldur = dict(
        prog_moon_sign=ay.get("sign_local", "-"),
        prog_moon_pos=ay.get("position", "-"),
        prog_moon_house=ay_evi,
        prog_phase=ay.get("phase_local", "-"),
        prog_moon_next=ay.get("next_sign_at", "-"),
        prog_sun_sign=gunes.get("sign_local", "-"),
        prog_sun_pos=gunes.get("position", "-"),
        prog_sun_years=gunes.get("next_sign_in_years", "-"),
        solar_arc=prog.get("solar_arc_deg", "-"),
        prog_asc=asc_metin, prog_mc=mc_metin,
    )
    prompt = p.PROGRESSIONS.format(
        **doldur, hits=vurgu_satirlari, disclosures=disclosures, rag=rag)
    fallback = p.PROGRESSIONS_FALLBACK.format(
        prog_moon_sign=doldur["prog_moon_sign"],
        prog_phase=doldur["prog_phase"],
        prog_moon_next=doldur["prog_moon_next"])
    return _cached_generate(cache_key, prompt, fallback,
                            ttl_seconds=30 * 24 * 3600, lang=lang,
                            owner_uid=user_id, spend=spend, refund=refund,
                            feature="progressions")


def firasa_report(user_id: str, ratios: dict[str, Any],
                  chart: str = "", lang: str | None = None,
                  spend: Callable[[], None] | None = None,
                  refund: Callable[[], None] | None = None) -> dict[str, Any]:
    """Yüz ORANLARINDAN firaset okuması.

    Bu fonksiyon eski `face_report`'un yerini aldı. Eskisinin üç sorunu vardı
    ve üçü de bu projede başka yerlerde kapatılan kusur sınıflarındandı:

    * **Sunucu görüntü alıyordu.** Artık almıyor: tespit kullanıcının
      cihazında yapılıyor, buraya yalnızca oranlar geliyor.
    * **Prompt Türkçeye sabitliydi** (`lang` parametresi yoktu), yani
      İngilizce kullanıcı Türkçe kurallarla üretilmiş metin alıyordu.
    * **Yağcılık talimatı taşıyordu:** "Yorum pozitif psikoloji çerçevesinde
      olsun: her özellik güç + gelişim alanı." Bu, ürünün "pohpohlama yok"
      ilkesinin tam tersi. Yerini geleneğin kendi sınırı aldı: tek belirti
      hüküm vermez, belirti kader değildir, amaç ayıklamak değil dengelemek.

    Ayrıca eskisi tahmini yaş ve duygu da prompt'a koyuyordu; ikisi de
    biyometrik çıkarım ve ikisi de artık üretilmiyor.
    """
    p = prompts.get(lang)

    # Önbellek anahtarı oranların kendisiyle: aynı yüz aynı okumayı alır,
    # her açılışta yeni bir LLM çağrısı yapılmaz.
    ozet = json.dumps(
        {k: ratios.get(k) for k in sorted(ratios)}, sort_keys=True)
    cache_key = (f"firasa-{user_id}-{lang}-"
                 f"{hashlib.sha256(ozet.encode()).hexdigest()[:16]}")

    # İsabette embedding çağrısını atla (bkz. daily_reading'deki gerekçe).
    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True}

    belirtiler = firasa_service.prompt_block(ratios, lang)
    rag = retrieve_context(
        p.FIRASA_RAG_QUERY, top_k=3, lang=lang)

    prompt = p.FIRASA.format(signs=belirtiler, chart=chart or "—", rag=rag)
    return _cached_generate(cache_key, prompt, p.FIRASA_FALLBACK,
                            ttl_seconds=7 * 24 * 3600,
                            lang=lang, owner_uid=user_id,
                            spend=spend, refund=refund, feature="face")


def bazi_report(user_id: str, bazi: dict[str, Any],
                lang: str | None = None,
                spend: Callable[[], None] | None = None,
                refund: Callable[[], None] | None = None) -> dict[str, Any]:
    """BaZi haritasından kader analizi raporu."""
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)
    # Anahtar HARİTANIN TAMAMINDAN (Revize B0). Eski anahtar yalnızca gün
    # sütununu taşıyordu: kullanıcı cinsiyetini ya da doğum saatini/şehrini
    # değiştirse de gün sütunu aynı kaldığı sürece 30 gün boyunca eski rapor
    # dönüyordu — üstelik ekranda taze hesaplanan sütunların yanında.
    # calc_version da girer: hesap davranışı değişince eski metinler düşer.
    ozet = "|".join([
        # Saat sütunu bilinmeyen doğumda None'dır (B1) — "-" temsil eder ve
        # saatli/saatsiz haritalar ayrı önbellek kayıtları alır.
        *((bazi["pillars"][k] or {}).get("label", "-")
          for k in ("year", "month", "day", "hour")),
        bazi.get("gender", ""),
        # Liu Nian rapora giriyor (B6): yıl sütunu değişince (Li Chun)
        # eski yılın "içinde bulunulan dönem" bölümü servis edilmesin.
        (bazi.get("current_year_pillar") or {}).get("label", "-"),
        str(bazi.get("calc_version", "1")),
    ])
    cache_key = (f"bazi-report-v2-{user_id}-"
                 f"{hashlib.sha256(ozet.encode()).hexdigest()[:16]}-{lang}")

    # İsabette embedding çağrısını atla (bkz. daily_reading'deki gerekçe).
    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True}

    # Element, hayvan ve On Tanri adlari hesap motorunda anahtar olarak
    # duruyor; prompt'a girmeden once istegin diline cevrilir.
    bazi = prompts.localize_bazi(lang, bazi)

    pillars = " | ".join(f"{k}: {v['label']}"
                         for k, v in bazi["pillars"].items() if v)
    # Gizli kökler kompakt: "day: Hai→Ren,Jia" (B6).
    hidden = " | ".join(
        f"{k}: {v['branch']['pinyin']}→"
        + ",".join(h["pinyin"] for h in v["branch"].get("hidden", []))
        for k, v in bazi["pillars"].items() if v)
    branch_gods = ", ".join(
        f"{k}={v['branch']['ten_god']['name']}"
        for k, v in bazi["pillars"].items()
        if v and v["branch"].get("ten_god"))
    # Takvim yıllı şans satırı (B5): "1993-2003 (3-12): JiaShen (Pian Cai)".
    luck = "; ".join(
        f"{lp['from_year']}-{lp['to_year']} ({lp['from_age']}-{lp['to_age']}): "
        f"{lp['label']} ({lp['ten_god']['name']})"
        for lp in bazi.get("luck_pillars", [])[:4]
    )

    # Güç hükmü satırları (B3→B6). Dayanak dökümü kompakt kodlarla:
    # "month_command:40p(+)" — model listeden gerekçelendirir, dışına
    # çıkması şablon kuralıyla yasak.
    s = bazi.get("strength") or {}
    strength_basis = "; ".join(
        f"{c.get('source', '?')}:{c['points']}p"
        f"({'+' if c.get('side') == 'support' else '−'})"
        for c in (s.get("components") or [])[:5])
    climate = ""
    if s.get("climate_element_name"):
        climate = p.BAZI_CLIMATE_FMT.format(
            element=s["climate_element_name"])
    shen_sha = "; ".join(
        f"{y['name']} [{y['pillar']}] — {y['meaning']}"
        for y in bazi.get("shen_sha") or []) or p.NONE_LABEL

    ls = bazi.get("luck_start") or {}
    luck_start = p.BAZI_LUCK_START_FMT.format(
        years=ls.get("years", "?"), months=ls.get("months", "?"),
        date=ls.get("date", "?"))
    idx = bazi.get("current_luck_index")
    aktif = (bazi.get("luck_pillars") or [None])[idx] if idx is not None else None
    current_luck = (f"{aktif['label']} ({aktif['from_year']}-{aktif['to_year']}, "
                    f"{aktif['ten_god']['name']})") if aktif else p.NONE_LABEL
    cy = bazi.get("current_year_pillar") or {}
    current_year = (f"{cy.get('year', '')} {cy.get('label', '')} "
                    f"({(cy.get('ten_god') or {}).get('name', '')})").strip()

    # Beyanlar: harita notları + güç hesabının kapsam beyanı.
    notlar = list(bazi.get("notes") or [])
    kapsam = s.get("scope_note_key")
    if kapsam and kapsam in p.BAZI_NOTES:
        notlar.append(p.BAZI_NOTES[kapsam])
    # Sorgu bazi + mizaç tohumlarından (B6): B7 doktrin bölümleri gelince
    # doğrudan onlara, gelmeden en yakın gerçek karşılığa (element/mizaç)
    # yönelir. Hüküm adı da girer — "güçlü/zayıf" bölümleri ayrışsın.
    rag = retrieve_context(
        " ".join(filter(None, [
            chart_query.topic_seed("bazi", lang),
            chart_query.topic_seed("temperament", lang),
            str(bazi["day_master"].get("element") or ""),
            str(s.get("verdict_name") or ""),
        ])),
        lang=lang,
    )

    prompt = p.BAZI.format(
        pillars=pillars, hidden=hidden,
        day_master=bazi["day_master"]["description"],
        zodiac_animal=bazi["zodiac_animal"],
        elements=bazi["element_distribution"], dominant=bazi["dominant_element"],
        missing=bazi.get("missing_elements") or p.NONE_LABEL,
        ten_year=bazi["ten_gods"]["year"]["name"],
        ten_month=bazi["ten_gods"]["month"]["name"],
        # Saat bilinmeyen doğumda saat Tanrısı yok (B1) — "-" ve prompt'a
        # giren beyan, modelin saat sütunu hakkında konuşmasını engeller.
        ten_hour=(bazi["ten_gods"].get("hour") or {}).get("name", "-"),
        branch_gods=branch_gods or "-",
        verdict=s.get("verdict_name", "-"),
        ratio=s.get("ratio", "-"),
        season_state=s.get("season_state_name", "-"),
        strength_basis=strength_basis or "-",
        favorable=", ".join(s.get("favorable_names") or []) or p.NONE_LABEL,
        unfavorable=", ".join(s.get("unfavorable_names") or [])
        or p.NONE_LABEL,
        climate=climate,
        shen_sha=shen_sha,
        luck=luck, luck_start=luck_start,
        current_luck=current_luck, current_year=current_year or "-",
        notes="\n".join(f"- {n}" for n in notlar) or "-",
        rag=rag,
    )
    fallback = p.BAZI_FALLBACK.format(
        element=bazi["day_master"]["element"],
        polarity=bazi["day_master"]["polarity"],
        dominant=bazi["dominant_element"],
        verdict=s.get("verdict_name", "-"),
    )
    return _cached_generate(cache_key, prompt, fallback,
                            ttl_seconds=30 * 24 * 3600, lang=lang,
                            owner_uid=user_id, spend=spend, refund=refund,
                            feature="bazi")


#: Soru kapısının olası hükümleri (R11). VALID dışındakiler çekimi durdurur.
ICHING_QUESTION_VERDICTS = ("VALID", "CHAT", "INVALID")


def iching_question_verdict(question: str, lang: str | None = None) -> str:
    """Soru kâhine sorulabilir mi — LLM hükmü (R11).

    R10'daki sabit kelime listesi "beni seviyor musun" (uygulamaya
    yöneltilmiş) ile "beni seviyor mu" (klasik kehanet sorusu) arasındaki
    farkı göremezdi ve selam içermeyen saçma girişlere bile "selam"
    mesajı basıyordu. Karar artık modelde; liste yalnız bariz durumlarda
    LLM çağrısını kesen ücretsiz ön filtre.

    Hükümler: VALID (çekime uygun) / CHAT (uygulamaya-asistana yöneltilmiş)
    / INVALID (selamlaşma, rastgele harfler, niyetsiz metin). Sınıflandırıcı
    erişilemezse VALID varsayılır — ritüel, altyapı hıçkırığına kurban
    edilmez; prompt'taki anlamsız-soru kuralı son ağ olarak durur.
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    from services.iching_service import question_is_meaningful
    if not question_is_meaningful(question):
        return "INVALID"

    # Aynı soru tekrar denenirse model tekrar çağrılmaz (maliyet + spam).
    anahtar = "iching-soru-" + hashlib.sha256(
        f"{question}|{lang}".encode()).hexdigest()[:16]
    onbellek = cache.get(anahtar)
    if onbellek in ICHING_QUESTION_VERDICTS:
        return onbellek

    ham = gemini_service.extract_json(
        prompts.get(lang).ICHING_QUESTION_GATE.format(question=question),
        feature="iching_verdict",
        schema={
            "type": "object",
            "properties": {"verdict": {
                "type": "string", "enum": list(ICHING_QUESTION_VERDICTS)}},
            "required": ["verdict"],
        })
    verdict = "VALID"
    if ham:
        try:
            aday = str(json.loads(ham).get("verdict", "")).strip().upper()
            if aday in ICHING_QUESTION_VERDICTS:
                verdict = aday
        except (ValueError, AttributeError):
            pass
    cache.set(anahtar, verdict, ttl_seconds=24 * 3600)
    return verdict


def iching_reading(user_id: str, cast: dict[str, Any],
                   lang: str | None = None,
                   spend: Callable[[], None] | None = None,
                   refund: Callable[[], None] | None = None) -> dict[str, Any]:
    """I Ching çekimini kullanıcının sorusuna bağlayan yorum."""
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)
    # Heksagram metinleri veri katmanında iki dilde tutuluyor; burada isteğin
    # diline indirgenir (name_local / judgment / image).
    yerel = prompts.localize_iching(lang, cast)
    primary = yerel["primary"]
    # Anahtar ÖZETLE ve YÖNTEMLE (Revize İ0). Eski anahtarda method yoktu:
    # aynı soru + aynı heksagram + aynı hareketli çizgilerle yarrow çeken
    # kullanıcı, coins ile üretilmiş yorumu görüyordu — oysa prompt yöntemi
    # metne yazıyor. Ham soru da anahtara gömülmekten kurtuldu.
    from services.iching_service import ICHING_CALC_VERSION
    baglam = yerel.get("context") or {}
    gun_etiketi = (baglam.get("day_pillar") or {}).get("label", "")
    ozet = "|".join([
        str(primary["number"]),
        cast.get("question", "")[:48],
        "-".join(map(str, cast.get("moving_lines", []))),
        cast.get("method", ""),
        # Gün etiketi anahtara girer (İ4): gün bağlamı prompt'ta —
        # gece yarısı sınırında dünün bağlamı servis edilmesin.
        gun_etiketi,
        ICHING_CALC_VERSION,
    ])
    cache_key = (f"iching-v2-{user_id}-"
                 f"{hashlib.sha256(ozet.encode()).hexdigest()[:16]}-{lang}")

    # İsabette embedding çağrısını atla (bkz. daily_reading'deki gerekçe).
    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True}

    transformed_text = ""
    if yerel.get("transformed"):
        t = yerel["transformed"]
        transformed_text = p.ICHING_TRANSFORMED.format(
            number=t["number"], name_tr=t["name_local"], name=t["name"],
            judgment=t["judgment"],
        )

    # --- Hareketli çizgi METİNLERİ (İ4) — yorumun ağırlık merkezi ---
    moving = cast.get("moving_lines") or []
    metinler = primary.get("line_texts") or []
    parcalar = [p.ICHING_LINE_FMT.format(n=n, text=metinler[n - 1])
                for n in moving if 0 < n <= len(metinler)]
    if len(moving) == 6 and primary.get("all_lines"):
        parcalar.append(
            f"{p.ICHING_ALL_LINES_LABEL}: {primary['all_lines']}")
    moving_texts = "\n  ".join(parcalar) or "-"

    # --- Trigramlar: ad + element + aile (İ1 atributları) ---
    def _trig(t: dict[str, Any]) -> str:
        aile = p.TRIGRAM_FAMILY_NAMES.get(t.get("family") or "", "")
        return f"{t['name']} ({t['element']}" + (f", {aile})" if aile else ")")

    nukleer = yerel.get("nuclear") or {}
    nuclear_line = (f"#{nukleer['number']} {nukleer['name_local']}: "
                    f"{nukleer['judgment']}") if nukleer else "-"

    # --- Liu Yao özeti (İ3) ---
    liu = yerel.get("liu_yao") or {}
    ly_lines = liu.get("lines") or []
    palace = liu.get("palace", "-")
    palace_element = p.BAZI_ELEMENTS.get(liu.get("palace_element") or "",
                                         liu.get("palace_element") or "-")
    shi_ying = "-"
    if ly_lines and liu.get("shi") and liu.get("ying"):
        shi_c = ly_lines[liu["shi"] - 1]
        ying_c = ly_lines[liu["ying"] - 1]
        shi_ying = p.ICHING_SHI_YING_FMT.format(
            shi=liu["shi"], shi_rel=shi_c.get("relative_name", ""),
            shi_branch=shi_c.get("branch", ""),
            ying=liu["ying"], ying_rel=ying_c.get("relative_name", ""),
            ying_branch=ying_c.get("branch", ""))

    # --- Çekim günü bağlamı (İ2) + boşluk/çarpışma işaretleri ---
    day_context = "-"
    if gun_etiketi:
        bos = ", ".join(str(c["position"]) for c in ly_lines
                        if c.get("void"))
        carpisan = ", ".join(str(c["position"]) for c in ly_lines
                             if c.get("clash"))
        ekler = ""
        if bos:
            ekler += p.ICHING_VOID_FMT.format(lines=bos)
        if carpisan:
            ekler += p.ICHING_CLASH_FMT.format(lines=carpisan)
        day_context = p.ICHING_DAY_FMT.format(
            day=gun_etiketi,
            month=(baglam.get("month_pillar") or {}).get("label", "-"),
            basis=p.ICHING_BASIS_UTC
            if baglam.get("basis") == "utc" else "") + ekler

    # --- Danışanla bağ (İ2): Day Master ↔ trigram ilişkileri ---
    dm_line = "-"
    iliskiler = baglam.get("trigram_relation_names") or {}
    if iliskiler and baglam.get("day_master_element"):
        dm_line = p.ICHING_DM_FMT.format(
            element=p.BAZI_ELEMENTS.get(baglam["day_master_element"],
                                        baglam["day_master_element"]),
            lower=iliskiler.get("lower", "-"),
            upper=iliskiler.get("upper", "-"))

    # Kullanıcı hafızası: soru genelde kişisel — bağlam okumaya değer katar.
    memory = memory_service.memory_context(user_id, max_chars=400)

    rag = retrieve_context(
        p.ICHING_RAG_QUERY.format(name=primary["name_local"]), lang=lang)

    prompt = p.ICHING.format(
        question=cast.get("question"),
        method=p.ICHING_METHOD_NAMES.get(cast.get("method") or "",
                                         cast.get("method") or ""),
        number=primary["number"], name_tr=primary["name_local"],
        name=primary["name"], name_cn=primary["name_cn"],
        unicode=primary["unicode"], judgment=primary["judgment"],
        image=primary["image"],
        lower=_trig(primary["lower_trigram"]),
        upper=_trig(primary["upper_trigram"]),
        nuclear=nuclear_line,
        moving_texts=moving_texts,
        transformed=transformed_text,
        palace=palace, palace_element=palace_element, shi_ying=shi_ying,
        day_context=day_context, dm_line=dm_line,
        rag=rag, memory=_memory_block(memory, lang),
    )
    fallback = (
        f"#{primary['number']} {primary['name_local']} {primary['unicode']}: "
        f"{primary['judgment']}"
    )
    return _cached_generate(cache_key, prompt, fallback, ttl_seconds=3600,
                            lang=lang, owner_uid=user_id,
                            spend=spend, refund=refund, feature="iching")


def birth_hexagram_report(user_id: str, konum: dict[str, Any],
                          lang: str | None = None,
                          spend: Callable[[], None] | None = None,
                          refund: Callable[[], None] | None = None,
                          ) -> dict[str, Any]:
    """Doğum heksagramından karakter okuması (İ5).

    Çekim değil kimlik katmanı: natal raporla aynı sınıf (30 gün önbellek,
    isabette embedding turu atlanır). Saatsiz doğumun sınır beyanı prompt'a
    girer — model iki adaydan birini kesinmiş gibi sunamaz.
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)

    ozet = "|".join([
        str(konum["gate"]),
        str(konum.get("line") if konum.get("hour_known") else "-"),
        str(konum.get("alternate_gate") or "-"),
        konum.get("wheel_version", "1"),
    ])
    cache_key = (f"birthhex-{user_id}-"
                 f"{hashlib.sha256(ozet.encode()).hexdigest()[:16]}-{lang}")

    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True}

    hexagram = prompts.localize_hexagram(lang, konum["hexagram"])
    metinler = hexagram.get("line_texts") or []
    saatli = konum.get("hour_known", True)
    cizgi = konum.get("line") or 0

    notlar: list[str] = []
    if konum.get("alternate_gate"):
        alt = prompts.localize_hexagram(lang, konum["alternate_hexagram"])
        notlar.append(p.BIRTH_HEXAGRAM_BOUNDARY_NOTE.format(
            gate=f"#{konum['gate']} {hexagram['name_local']}",
            alternate=f"#{konum['alternate_gate']} {alt['name_local']}"))
    if not saatli:
        notlar.append(p.BIRTH_HEXAGRAM_LINE_UNKNOWN)

    # Çizgi metni yalnız saat biliniyorsa iddia edilir (sınır dürüstlüğü).
    line_text = "-"
    if saatli and 0 < cizgi <= len(metinler):
        line_text = metinler[cizgi - 1]

    rag = retrieve_context(
        p.BIRTH_HEXAGRAM_RAG_QUERY.format(name=hexagram["name_local"]),
        lang=lang)

    # Kapı pasajı (İ8): Rytho'nun kapıya özgü karakter aktarımı.
    pasaj = konum.get("gate_passage") or {}
    gate_text = pasaj.get("gate_en" if lang == "en" else "gate_tr") or "-"

    prompt = p.BIRTH_HEXAGRAM.format(
        longitude=konum.get("longitude", "?"),
        gate=konum["gate"],
        line=cizgi if saatli else "-",
        name_tr=hexagram["name_local"], name=hexagram["name"],
        name_cn=hexagram["name_cn"], unicode=hexagram["unicode"],
        judgment=hexagram["judgment"], image=hexagram["image"],
        line_text=line_text,
        gate_text=gate_text,
        lower=hexagram["lower_trigram"]["name"],
        upper=hexagram["upper_trigram"]["name"],
        notes="\n".join(f"- {n}" for n in notlar) or "-",
        rag=rag,
    )
    fallback = p.BIRTH_HEXAGRAM_FALLBACK.format(
        gate=konum["gate"], name_tr=hexagram["name_local"],
        unicode=hexagram["unicode"], judgment=hexagram["judgment"])
    return _cached_generate(cache_key, prompt, fallback,
                            ttl_seconds=30 * 24 * 3600, lang=lang,
                            owner_uid=user_id, spend=spend, refund=refund,
                            feature="birth_hexagram")


def synastry_report(user_id: str, synastry: dict[str, Any],
                    lang: str | None = None,
                    spend: Callable[[], None] | None = None,
                    refund: Callable[[], None] | None = None) -> dict[str, Any]:
    """İki kişi arasındaki kozmik uyum raporu.

    Sinastri skoru hesaplanıyor ama prompt'a GİRMİYOR ve rapora yazdırılmıyor:
    ilişkiyi tek sayıya indirgemek ürünün dürüstlük ilkesiyle çelişiyor ve
    ikili dinamikte de aynı gerekçeyle yasak.
    """
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    p = prompts.get(lang)
    yerel = prompts.localize_synastry(lang, synastry)
    p1, p2 = yerel["person1"], yerel["person2"]
    cache_key = f"synastry-{user_id}-{p1['name']}-{p2['name']}-{lang}"

    # İsabette embedding çağrısını atla (bkz. daily_reading'deki gerekçe).
    cached = cache.get(cache_key)
    if cached is not None:
        return {"text": cached, "cached": True}

    aspects = "\n".join(
        f"- {a['p1_local']} ({p1['name']}) {a['aspect_local']} {a['p2_local']} "
        f"({p2['name']}) orb {a['orbit']}°"
        for a in yerel.get("aspects", [])[:8]
    ) or p.NO_ASPECTS
    # Sorgu isteğin dilinde ve İKİ haritadan (Revize R8): ilişki tohumu +
    # iki Güneş + en sıkı sinastri açısı.
    #
    # Bu satır adına ancak şimdi uyuyor: liste eskiden SIRASIZDI ve "ilk
    # eleman" kerykeion'un gezegen sırasındaki ilk açıydı, en sıkısı değil
    # (1.6.0 turu bulgusu). `_aspects_list` artık kaynakta öneme göre
    # sıralıyor.
    en_siki = next(iter(yerel.get("aspects", [])), None)
    rag = retrieve_context(
        " ".join(filter(None, [
            chart_query.topic_seed("relationship", lang),
            f"{p1['sun']['sign_local']} {p2['sun']['sign_local']}",
            (f"{en_siki['p1_local']} {en_siki['aspect_local']} "
             f"{en_siki['p2_local']}") if en_siki else "",
        ])),
        lang=lang)

    prompt = p.SYNASTRY.format(
        name1=p1["name"], sun1=p1["sun"]["sign_local"],
        moon1=p1["moon"]["sign_local"],
        name2=p2["name"], sun2=p2["sun"]["sign_local"],
        moon2=p2["moon"]["sign_local"],
        aspects=aspects, rag=rag,
    )
    fallback = p.SYNASTRY_FALLBACK.format(
        name1=p1["name"], sun1=p1["sun"]["sign_local"],
        name2=p2["name"], sun2=p2["sun"]["sign_local"],
    )
    return _cached_generate(cache_key, prompt, fallback,
                            ttl_seconds=7 * 24 * 3600, lang=lang,
                            owner_uid=user_id, spend=spend, refund=refund,
                            feature="synastry")

import logging
from typing import List

from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException
from pydantic import BaseModel

from core import device, entitlements
from core.auth import AuthUser, get_current_user
from core.entitlements import FREE_CHAT_PER_DAY
from core.wallet import charge_metered, refund_spend
from core.i18n import get_language
from core.messages import text
from services import (
    chart_context,
    chat_history,
    chart_query,
    gemini_service,
    memory_extractor,
    memory_service,
    notification_service,
    persona_guard,
    profile_service,
    prompts,
    safety_rules,
    sky_service,
)
from services.prompt_composer import compose_chat_message, should_use_rag
from services.rag_service import retrieve_passages
from services.safety_rules import forbidden_topic
from services.sky_service import get_sky_now

logger = logging.getLogger(__name__)
router = APIRouter()


class ChatMessageItem(BaseModel):
    sender: str  # USER | AI
    text: str


class ChatRequest(BaseModel):
    history: List[ChatMessageItem] = []
    message: str
    #: Sürdürülen konunun kimliği; boşsa yeni konu açılır ve yanıtta döner.
    conversation_id: str | None = None
    #: R4-2: soru bir ARKADAŞ bağlamındaysa arkadaşın kimliği. Sunucu
    #: arkadaşlığı doğrular ve ölçülen ilişki eksenlerini fısıltı olarak
    #: prompt'a ekler — istemciye ham doğum verisi HİÇ dönmez.
    friend_uid: str | None = None
    #: P-turu: soru EKLENEN BİR KİŞİ bağlamındaysa o kişinin kimliği.
    #: Yetki kapısı arkadaşlık değil sahipliktir; fısıltı kişiyi adıyla
    #: değil ilişkisiyle anar ("eşin") — sunucu adı zaten bilmiyor.
    person_id: str | None = None
    #: KA-turu: konuşmanın nereden açıldığı ("checkin" = akşam sorusuna
    #: cevap). Hafıza çıkarıcı bunun tek mesajlık cevabını da işler —
    #: normalde ≥2 kullanıcı mesajı bekler ve check-in cevabı kaybolurdu.
    source: str | None = None


def _sky_summary(lang: str, profile: dict | None = None) -> str:
    """Bugünün gökyüzünün kompakt özeti; hata durumunda boş döner.

    Gökyüzü sohbetin çalışması için zorunlu değil — alınamazsa sohbet
    haritasız/gökyüzsüz ama çalışır durumda devam eder.

    Etiketler dile bağlı: bu blok prompt'a giriyor ve İngilizce bir prompt'un
    içinde Türkçe etiketler modelin dili karıştırmasına yol açıyordu.

    ``profile`` yalnızca **saat dilimi** için kullanılır: günün yöneticisi
    kullanıcının yerel tarihine bağlıdır ve gökyüzü yükü UTC'de hesaplanıp
    tüm kullanıcılarla paylaşıldığı için oraya gömülemez.
    """
    # try TÜM gövdeyi kapsar (KA8): eskiden yalnız `get_sky_now()`
    # korunuyordu; biçimleme satırlarından fırlayan bir istisna dış
    # yakalayıcıya taşıp sohbeti 500 ile düşürürdü — gökyüzü sohbetin
    # çalışması için zorunlu değil.
    try:
        sky = prompts.localize_sky(lang, get_sky_now())

        p = prompts.get(lang)
        moon = sky.get("moon_phase") or {}
        retros = ", ".join(sky.get("retrogrades", [])) or p.NONE_LABEL
        # HA1: yerelleştirme artık kararlı anahtarların ÜZERİNE yazmıyor;
        # LLM'e giden metin *_local alanlarından kurulur (dil izolasyonu;
        # alan yoksa kararlı anahtara düşülür).
        aspects = "; ".join(
            f"{a.get('p1_local') or a['p1']}-{a.get('p2_local') or a['p2']} "
            f"{a.get('aspect_local') or a['aspect']}"
            for a in (sky.get("aspects") or [])[:3]
        )

        satirlar = [
            p.SKY_MOON.format(name=moon.get("name"),
                              illumination=moon.get("illumination")),
            p.SKY_RETROS.format(retros=retros),
        ]
        if aspects:
            satirlar.append(p.SKY_ASPECTS.format(aspects=aspects))

        # Marifetname katmanı: korpusa girdiği hâlde motorda karşılığı
        # olmayan iki bilgi buradan geliyor. Karşılığı olmasaydı model
        # bunlar hakkında dayanaksız konuşurdu.
        yerel_gun = notification_service.local_now(profile or {}).date()
        satirlar.append(p.SKY_DAY_RULER.format(
            planet=prompts.planet_name(lang,
                                       sky_service.day_ruler(yerel_gun))))
        menzil = sky.get("moon_mansion") or {}
        if menzil:
            satirlar.append(p.SKY_MOON_MANSION.format(
                number=menzil.get("number"), name=menzil.get("name")))

        return "\n".join(satirlar)
    except Exception as exc:
        logger.warning("Gökyüzü alınamadı: %s", exc)
        return ""


def _engellenen_turu_kaydet(background: BackgroundTasks, uid: str,
                            hazir_konu, mesaj: str, reply: str, lang: str,
                            kategori: str) -> None:
    """Kapıda engellenen turu arşive yazar — ÖLÇÜLEBİLSİN diye (P-turu).

    Engellenen turlar `write_turn`dan ÖNCE dönüyordu, yani Firestore'a
    HİÇ yazılmıyordu. Ölçüldü (2026-10-10): 498 mesajlık üretim korpusunda
    kayıtlı engel SIFIR — oysa sahibi ekranda alakasız finans/sağlık
    reddini görmüştü. Konu kalıplarının yanlış pozitifleri ("hissediyorum"
    içinde "hisse") ancak kayıtlı turdan ölçülür; kayıt yoksa kusur
    görünmez ve bir daha onarılamaz.

    YALNIZ yasak-alan kapısı için: kriz turu BİLEREK arşivlenmez — "yaşamak
    istemiyorum" cümlesinin kullanıcının kendi geçmişinde 30 gün durması,
    hafıza çıkarıcının da o turda koşmaması kararıyla aynı yerden gelir
    (kriz anı kişiselleştirme sinyali değil, kayıt malzemesi de değil).
    Sıklığı log satırı ("Kriz işareti") ölçer.
    """
    if hazir_konu is None:
        return
    background.add_task(chat_history.write_turn, uid, hazir_konu, mesaj,
                        reply, lang, blocked=kategori)


@router.post("")
@router.post("/")
def chat(request: ChatRequest, background: BackgroundTasks,
         user: AuthUser = Depends(get_current_user),
         lang: str = Depends(get_language),
         x_device_id: str | None = Header(default=None),
         x_device_platform: str | None = Header(default=None)):
    """Sohbet: ucretsiz katmanda gunde [FREE_CHAT_PER_DAY] mesaj; abonede
    aylik token hakkindan, hak bitince satin alinan paketten harcanir.

    Bedel LLM cagrisindan ONCE dusulur; aksi halde hata donen istekler de
    kullaniciya bedava mesaj kazandirirdi. LLM yanit uretemezse iade edilir.
    """
    # KRİZ KAPISI — her şeyden önce (S-turu).
    #
    # Yasak alan kapısından ÖNCE gelir ve ondan farklı çalışır: orada konu
    # VE cevap talebi birlikte aranıyor, burada tek işaret yeter. Sebep
    # basit — krizde olan kişi soru sormaz.
    #
    # Ölçülmüştü: "artık yaşamak istemiyorum" hiçbir kapıya takılmadan
    # astroloji modeline gidiyordu.
    #
    # Model çağrılmaz, jeton düşmez, kota yenmez ve hafızaya "mood"
    # yazılmaz: kriz anı bir kişiselleştirme sinyali değil.
    #
    # Konu hedefi ve kırpılmış mesaj KAPILARDAN ÖNCE hazırlanır (P-turu):
    # engellenen tur da arşive yazılacak (`_engellenen_turu_kaydet`) ve
    # bunun için konu kimliği lazım. `prepare` tek doküman okuması ve
    # bedava; HARCAMA (`charge_metered`) kapıların arkasında kalmaya
    # devam ediyor — reddedilen soru hak yemez.
    mesaj_metni = chat_history.clip_message(request.message)

    # SS4b — yayın günü tuzağı. Güncellenmemiş istemci `cid`'yi bilmez:
    # akşam sorusunu giriş kutusuna yazar ve `conversation_id: null` ile
    # gönderir. O tur SUNUCUDA tohumun içine yönlendirilmezse kullanıcı
    # başına günde İKİ neredeyse aynı konuşma oluşur (biri cevaplanmış,
    # biri yetim tohum). Eski istemci zaten gereken işareti gönderiyor:
    # `source == "checkin"` + kimlik yok. Yeni istemci `cid` gönderdiği
    # için buraya hiç düşmez.
    hedef_konu = request.conversation_id
    if not hedef_konu and request.source == "checkin":
        hedef_konu = chat_history.seed_conversation_id(
            entitlements.user_local_date(user.uid).isoformat())

    hazir_konu = chat_history.prepare(user.uid, hedef_konu)

    if safety_rules.crisis_signal(request.message):
        logger.info("Kriz işareti: yanıt destek metnine yönlendirildi")
        reply = text("crisis.support", lang)
        # Arşiv YOK (bkz. _engellenen_turu_kaydet) ve konu kimliği de
        # dönmez: rezerve edilen kimliğe hiçbir şey yazılmadı, istemci onu
        # taşısaydı bir sonraki mesaj hiç var olmayan bir konuya bağlanırdı.
        return {"status": "success", "reply": reply, "blocked": "crisis"}

    # Yasak alan kapısı kotadan ÖNCE: reddedilen bir soru kullanıcının günlük
    # hakkını yemez.
    blocked = forbidden_topic(request.message, lang=lang)
    if blocked is not None:
        kategori, reply = blocked
        logger.info("Yasak alan reddedildi: %s", kategori)
        _engellenen_turu_kaydet(background, user.uid, hazir_konu,
                                mesaj_metni, reply, lang, kategori)
        # `conversation_id` ŞART (K'nin dikişi): tur bu kimliğe arşivlendi;
        # istemci kimliği öğrenmezse bir sonraki mesajı `cid: null` ile
        # gönderir, YENİ bir konu açılır ve engellenen tur tek-turluk
        # yetim konu olarak 20 konu tavanına sayılıp gerçek bir konuyu
        # sildirebilir (`_evict_oldest_if_needed`).
        return {"status": "success", "reply": reply, "blocked": kategori,
                "conversation_id": (hazir_konu.conversation_id
                                    if hazir_konu else None)}

    # Tek cihaz kilidi (yalnızca ücretli abonede etkili) HARCAMADAN önce:
    # 409 alan istek token da yakmamalı.
    device.enforce_single_device(user.uid, x_device_id,
                                 auth_time=user.auth_time,
                                 platform=x_device_platform, lang=lang)

    # Ücretsiz günlük hak + token cüzdanı tek kapıda (Revize R1). Abone
    # cüzdanından harcar; ücretsiz kullanıcı önce günlük hakkını yer, sonra
    # varsa satın alınmış paketten. Sohbet ÖNBELLEKSİZ tek uç olduğu için
    # harcama peşin; LLM yanıt veremezse aşağıda iade edilir.
    token_harcandi = charge_metered(user, "chat", FREE_CHAT_PER_DAY, lang=lang)

    # Konu hedefi yukarıda SENKRON çözüldü (yanıt kimliği döndürmek
    # zorunda), mesaj yazımı arka planda (kullanıcı Firestore'u beklemez).
    # Kırpma 422 yerine: uzun yazan kullanıcının mesajını reddetmek yerine
    # kısaltıyoruz.

    try:
        # Prompt geçmişi tavanlı (K4): son 12 mesaj × 1.200 karakter —
        # arşiv kırpması değil, yalnız LLM'e giden girdinin maliyet sınırı.
        history = [
            {"sender": m.sender,
             "text": chat_history.clip_for_prompt(m.text)}
            for m in request.history[-chat_history.PROMPT_HISTORY_MESSAGES:]
        ]

        # Profil bir kez okunur, iki yerde kullanılır: haritayı prompt'a
        # iliştirmek ve bilgi tabanı sorgusunu kurmak.
        profile = profile_service.get_profile(user.uid)
        # `today=` ŞART: `chart_facts` transit önbelleğinin KOVASINI bu
        # tarihten kuruyor. Verilmezse kova sunucunun UTC gününden kurulur
        # ve UTC+3 kullanıcısı yerel 00:00–03:00 arasında ÖNCEKİ günün
        # kovasını okur (TTL 36 saat, yani kova gerçekten hayatta olur).
        # Sohbette bunun bedeli sessiz: model o transit satırını "bugün"
        # diye anlatır. Aynı onarım `api/face_reading.py`de yapılmıştı;
        # burası atlanmıştı.
        facts = (chart_context.chart_facts(
            user.uid, profile,
            today=entitlements.user_local_date(user.uid))
            if profile else None)

        # Seçici RAG: selamlaşma/duygu/kısa onay turlarında korpus araması
        # (ve embedding çağrısı) atlanır; kadim bilgi soran mesajlarda en
        # fazla 2 kırpılmış pasaj "arka plan fısıltısı" olarak eklenir.
        #
        # Arama artık kullanıcının CÜMLESİYLE değil, cümlenin konusu +
        # haritanın o konuyla ilgili faktörleriyle yapılıyor. "İşimle ilgili
        # ne yapmalıyım?" diye aramak kadim metinde hiçbir şeye denk gelmez;
        # "meslek, statü + Satürn 10. evde + Güneş Kare Mars" gelir.
        # SS2b: tohuma verilen cevap çoğu zaman iki kelimedir ("kötü
        # geçti"). Kapılar YALNIZ kullanıcı mesajına baksaydı RAG kapanır
        # ve sorgu boşalırdı — oysa konu bellidir, çünkü soruyu biz sorduk.
        # Bu yüzden yalnız TOHUM CEVABI turunda kapıların gördüğü metne
        # soru da katılır. Mesajın kendisi (prompt'a ve arşive giden)
        # DEĞİŞMEZ.
        #
        # ⚠️ HAM `request.message` DEĞİL `mesaj_metni` (kırpılmış) — ölçüldü:
        # ham metinle 240.000 karakterlik tek bir mesaj `build_query`
        # üzerinden embedding çağrısına 239.999 karakter olarak giriyordu,
        # yani istek başına sınırsız girdi token = sınırsız para. Kırpılmış
        # metni kullanmak aynı zamanda TUTARLI olan: modelin gördüğü,
        # arşive yazılan ve korpusta aranan metin artık AYNI metin —
        # modelin hiç görmeyeceği bir cümleyle korpus aramak, cevabı
        # göremediği bir soruya göre getirmek olurdu.
        #
        # Kriz ve yasak alan kapıları (yukarıda) BİLEREK ham metne bakar:
        # onlar bedava (saf CPU) ve 2.000. karakterden sonra yazılmış bir
        # kriz işaretini kaçırmak kabul edilemez. Kırpma yalnız PARA
        # ÖDENEN yollara uygulanır.
        tohum_soru = (hazir_konu.seed_question if hazir_konu else None) or ""
        tohum_bekliyor = bool(hazir_konu and hazir_konu.seed_pending
                              and tohum_soru)
        kapi_metni = (f"{tohum_soru} {mesaj_metni}" if tohum_bekliyor
                      else mesaj_metni)

        passages = []
        if should_use_rag(kapi_metni, lang):
            sorgu = chart_query.build_query(kapi_metni, facts, lang=lang)
            # RD3: kullanıcının konusu + GERÇEK harita faktörleri getirmeyi
            # kişiselleştirir — aynı soruda farklı haritalar farklı
            # pasajlar çeker (metadata'lı yeniden sıralama).
            passages = retrieve_passages(
                sorgu, top_k=2, lang=lang,
                boost=chart_query.boost_hints(kapi_metni, facts,
                                              lang=lang))

        # Kullanıcı hafızası: "seni tanıyor" hissinin kaynağı burası. Okuma
        # ucuz (tek Firestore dokümanı) ve RAG'den bağımsız olarak her turda
        # yapılır — kullanıcı hakkında bilinenler her mesajda geçerlidir.
        # `lang=` ŞART: fısıltının İÇ etiketleri (`(ruh hali seyri)`,
        # `(günlük …)`, `(ton tercihi)`, `(work, 3 gün önce)`) bu
        # parametreyle dile düşüyor. Verilmezse Türkçeye düşer ve
        # İngilizce bir prompt, İngilizce başlığının altında Türkçe
        # etiketli satırlar taşır.
        memory = memory_service.memory_context(user.uid, lang=lang)

        # Kullanıcının haritası. Uzun süre yalnızca Güneş/Ay/Yükselen
        # geçiyordu; artık ev yerleşimleri, element dengesi, doğum açıları ve
        # bugün haritaya dokunan transitler de geliyor — cevabın "herkese
        # uyan" olmaktan çıkması bu ayrıntılara bağlı. Efemeris hesabı
        # önbellekli, LLM maliyeti yok.
        # BaZi fısıltısı yalnızca Rytho+ sohbetinde (Revize B8): BaZi
        # ücretli üründür; abone olmayanın prompt'una girmez — dürüst
        # kapı. Abonede "Day Master'ım ne?" deterministik veriyle yanıtlanır.
        chart = chart_context.chart_whisper(
            user.uid, profile, lang=lang, facts=facts,
            include_bazi=entitlements.is_subscriber(user.uid))

        # Bugünün gökyüzü paylaşımlı önbellekten gelir (kullanıcı başına
        # maliyeti yok) ve sohbetin "şu an" ile bağını kurar.
        sky = _sky_summary(lang, profile)

        # ETKİN bağlam (KA7): istekten gelen kimlik ÖNCELİKLİ; yoksa konu
        # dokümanına yapışmış bağlam geri yüklenir — listeden yeniden
        # açılan konuşma "eşin" bağlamını kaybetmesin. İkisi de varsa
        # KİŞİ kazanır (tek ilişki yuvası var; kişi daha spesifik).
        etkin_person = request.person_id or (
            hazir_konu.person_id if hazir_konu else None)
        etkin_friend = request.friend_uid or (
            hazir_konu.friend_uid if hazir_konu else None)

        # KA6: açık bağlam yoksa mesajın kendisi bir yakını anıyor mu?
        # ("eşimle aram nasıl?" ana sekmeden soruluyordu ve SIFIR kişi
        # bağlamıyla gidiyordu — cihaz bulgusu.) Eşleşme deterministik
        # kelime tablosuyla; aynı türde birden çok kişi varsa TAHMİN YOK.
        from services import circle_context
        if not etkin_person and not etkin_friend:
            tur = circle_context.match_relation(mesaj_metni, lang)
            if tur:
                etkin_person = circle_context.person_for_relation(
                    user.uid, tur)
                if etkin_person:
                    logger.info("Sohbet kişi bağlamı kelimeden eşleşti "
                                "(%s, %s)", user.uid, tur)

        # İlişki fısıltısı (R4-2): bağlam varsa ölçülen eksenler prompt'a
        # girer. Doğrulanamazsa SESSİZCE atlanır ve loglanır — sohbet
        # düşmez, model yalnız kullanıcının kendi haritasıyla cevaplar.
        relationship = ""
        if etkin_person:
            # Sahiplik kapısı `person_counterpart` içinde: kayıt çağıranın
            # kendi ağacından okunuyor, başkasının kişisi None döner.
            try:
                from services import synastry_service
                karsi = synastry_service.person_counterpart(
                    user.uid, etkin_person, lang)
                if karsi is None:
                    logger.info("Sohbet kişi bağlamı atlandı: kayıt yok ya "
                                "da sahibi değil (%s)", user.uid)
                    etkin_person = None
                else:
                    relationship = synastry_service.whisper_for(
                        user.uid, karsi, lang)
            except Exception as exc:
                logger.warning("Kişi fısıltısı üretilemedi (%s/%s): %s",
                               user.uid, etkin_person, exc)
        elif etkin_friend and etkin_friend != user.uid:
            if profile_service.are_friends(user.uid, etkin_friend):
                try:
                    from services import synastry_service
                    relationship = synastry_service.relationship_whisper(
                        user.uid, etkin_friend, lang)
                except Exception as exc:
                    logger.warning("İlişki fısıltısı üretilemedi (%s→%s): %s",
                                   user.uid, etkin_friend, exc)
            else:
                logger.info("Sohbet ilişki bağlamı reddedildi: arkadaş "
                            "değil (%s→%s)", user.uid, etkin_friend)
                etkin_friend = None

        # KA6: çevre listesi her turda — model kullanıcının yakınlarını
        # BİLİR (tür + burçlar; ad sunucuda yok) ama sayıp dökmez.
        circle = ""
        try:
            circle = circle_context.circle_whisper(user.uid, lang)
        except Exception as exc:
            logger.warning("Çevre fısıltısı üretilemedi (%s): %s",
                           user.uid, exc)

        # KA6/3 — tema tetikli tali bağlam: bugün gökyüzü ilişki temasına
        # ağır basıyorsa ve açık bir kişi bağlamı yoksa, öncelikli yakının
        # ölçümü İLİŞTİRİLİR ("iç mevsimde aileyle ilgili süreç görünüyorsa
        # aile bilgileriyle analiz yapabilmeli" — kullanıcı isteği).
        # Eksenler LLM'siz ve önbellekli; maliyet yalnız CPU.
        if not relationship and circle:
            try:
                from services import signal_service, synastry_service
                ham_sinyaller = signal_service.cached_signals(
                    profile, today=entitlements.user_local_date(user.uid))
                temalar = {s.get("theme") for s in
                           (ham_sinyaller or {}).get("signals") or []}
                if "relationships" in temalar:
                    oncelikli = circle_context.priority_person(user.uid)
                    if oncelikli:
                        karsi = synastry_service.person_counterpart(
                            user.uid, oncelikli, lang)
                        if karsi is not None:
                            relationship = synastry_service.whisper_for(
                                user.uid, karsi, lang)
                            logger.info("Tema tetikli kişi bağlamı eklendi "
                                        "(%s)", user.uid)
            except Exception as exc:
                logger.info("Tema tetikli bağlam kurulamadı (%s): %s",
                            user.uid, exc)

        message = compose_chat_message(mesaj_metni, passages,
                                       memory=memory, chart=chart, sky=sky,
                                       relationship=relationship,
                                       circle=circle,
                                       seed_question=tohum_soru,
                                       seed_pending=tohum_bekliyor,
                                       lang=lang)
        if message == mesaj_metni:
            # Hiçbir fısıltı kurulamadı — "sadece burcumu biliyor"
            # şikâyetinin en ağır hâli. Sessiz kalmasın (KA8).
            logger.info("Sohbet SIFIR fısıltıyla gitti (%s)", user.uid)

        # Persona fısıltısı (P-turu): mesaj bir görev delege ediyorsa
        # ("sunum hazırlar mısın") ya da doğum tarihi taşıyorsa modele
        # ÖNCEDEN söylenir — kusuru çıktıda yakalayıp yeniden üretmek bir
        # LLM turu, burada söylemek bedava. `compose_chat_message`in
        # ARDINDAN iliştirilir (o modül başka paketin); yer mesajın hemen
        # üstü — en yakın yer, en ağır yer.
        message = persona_guard.attach(message, mesaj_metni, lang=lang)

        reply = gemini_service.chat(history, message, lang=lang,
                                    feature="chat", uid=user.uid)
        if reply is None:
            # Kullanıcı almadığı yanıta ödemez.
            if token_harcandi:
                refund_spend(user.uid, "chat")
            reply = text("llm_unavailable", lang)
        else:
            # Prompt'ta olmayan konum/açı cevapta kalmasın (derinleştirme
            # planındaki uydurma denetimi). Yeniden üretim aynı turda;
            # jeton ikinci kez düşülmez.
            from services import fact_guard
            def yeniden(duzelti: str) -> str | None:
                # Bekçi yeniden üretimi de "chat" — aynı turun maliyeti.
                return gemini_service.chat(history, duzelti, lang=lang,
                                           feature="chat", uid=user.uid)
            # `facts=` ŞART (KA8): verilmeyince bekçi dayanağı prompt
            # METNİNDEN yeniden çıkarıyordu — R8'in kapattığı kırılganlık.
            # Sonuç: doğru konumlar "uydurma" damgası yiyip boşa yeniden
            # üretime ve modeli spesifiklikten kaçıran düzeltmelere yol
            # açıyordu.
            reply, _ = fact_guard.enforce(
                reply, message, lang=lang, regenerate=yeniden, facts=facts)
            # Persona bekçisi OLGU bekçisinden SONRA (P-turu): olgu
            # bekçisinin yeniden ürettiği metin de kayabilir ve ikinci
            # üretim de kirliyse kullanıcıya giden şey modelin metni DEĞİL
            # sabit cümledir — "sunum taslağı hazırlayabilirim" bir kez
            # ekrana çıktı, bir daha çıkmaz. Olgu bekçisi aynı dalda metni
            # döndürüyor (rapor yüzeyleri için doğru); sohbet için değil.
            # Her iki bekçi de aynı turun kapanışını kullanır: jeton ikinci
            # kez düşülmez, en kötü hâlde tur üç LLM çağrısı tutar.
            # `message=`/`history=` ŞART: üçüncü-kişi bekçisi yalnız sohbete
            # doğum verisi girdiğinde bakar (bu mesaj ya da prompt geçmişi);
            # verilmezse kullanıcının KENDİ haritasını anlatan doğru cevap
            # sabit cümleyle ezilirdi (kapanış probunda ölçüldü).
            reply, _ = persona_guard.enforce(
                reply, message, lang=lang, regenerate=yeniden,
                circle=circle, relationship=relationship,
                message=mesaj_metni,
                history=" ".join(m["text"] for m in history))
        # Olgu çıkarımı yanıttan SONRA, arka planda: kullanıcı ikinci bir LLM
        # çağrısını beklemez. Kendi içinde kotalı ve hataya dayanıklı.
        #
        # ⚠️ Burada da `mesaj_metni` (kırpılmış), ham `request.message`
        # DEĞİL. Ölçüldü: ham metinle çıkarım prompt'u 240.010 karaktere
        # çıkıyordu — `history` kalemleri `clip_for_prompt`le bağlı olduğu
        # hâlde SON mesaj bağsızdı, yani kotanın tek koruduğu şey çağrı
        # SAYISIydı, boyu değil. İki zarar birden: o çağrının girdi
        # token'ı ve bağlam penceresini aşıp çıkarımın düşmesi — kota
        # yenmiş, olgu yazılmamış olur. Ayrıca çıkarım artık ARŞİVLENEN
        # metinle aynı metinden çalışıyor (`write_turn` da `mesaj_metni`).
        background.add_task(
            memory_extractor.extract_and_store, user.uid, history,
            mesaj_metni, source=request.source,
            # SS6: tohum cevabı ayrıcalığı istemci beyanından DEĞİL,
            # konu dokümanından gelir (bkz. memory_extractor docstring).
            seed_answer=tohum_bekliyor,
        )

        # Arşiv yazımı da arka planda (Revize R4). Hafıza çıkarıcı AYNEN
        # duruyor: damıtılmış olgular ile ham arşiv farklı işler görüyor —
        # biri "seni tanıyorum", öteki "kaldığın yerden devam".
        if hazir_konu is not None:
            background.add_task(
                chat_history.write_turn, user.uid, hazir_konu,
                mesaj_metni, reply, lang,
                etkin_friend if not etkin_person else None, etkin_person,
            )

        return {"status": "success", "reply": reply,
                "conversation_id": (hazir_konu.conversation_id
                                    if hazir_konu else None)}
    except Exception as e:
        logger.exception("Sohbet ucunda hata", exc_info=e)
        raise HTTPException(status_code=500, detail=text("internal", lang))


@router.delete("/conversations/{conversation_id}")
def delete_conversation(conversation_id: str,
                        user: AuthUser = Depends(get_current_user),
                        lang: str = Depends(get_language)):
    """Konuyu mesajlarıyla siler.

    Uçtan, çünkü istemci `conversations` altına YAZAMAZ (rules) — silme de
    bir yazımdır. Yalnızca kendi konuları: yol kimliği değil, doğrulanmış
    oturum kimliği kullanılır.
    """
    try:
        silinen = chat_history.delete_conversation(user.uid, conversation_id)
    except Exception as exc:
        logger.exception("Konu silinemedi (%s)", user.uid, exc_info=exc)
        raise HTTPException(status_code=500, detail=text("internal", lang))
    return {"status": "success", "deleted_messages": silinen}


# `/moderate` ucu KALDIRILDI (Revize R0).
#
# Docstring'i "istemci çağırır" diyordu ama hiçbir istemci çağırmıyordu:
# sosyal katman serbest metin içermiyor (hazır tepkiler), moderasyona konu
# içerik yok. Buna karşılık uç kotasız ve `require_plus`'sız bir LLM
# çağrısıydı — kimliği doğrulanmış herhangi bir istemci 60 istek/dk hızında
# bütçe yakabilirdi. Ölü VE masraflı kodun kotalanmış hâli değil, yokluğu
# doğrudur. Sosyal serbest metin bir gün gelirse denetim, çağıranın kendi
# ucunda kota arkasında kurulmalı.

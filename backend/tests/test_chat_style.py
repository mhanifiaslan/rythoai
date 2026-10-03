"""Sohbet stili testleri: seçici RAG, kısa yanıt, API şeması.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_chat_style.py -q
"""
import os

import pytest
from fastapi.testclient import TestClient

from core import config
from main import app
from services import gemini_service, prompt_composer


@pytest.fixture(autouse=True)
def _kota_sifirla(monkeypatch):
    """Aynı süreçte koşan diğer test dosyalarının (test_hardening) kota
    testlerini etkilememek için rate-limit sayaçlarını temizler.

    Günlük ücretsiz sohbet hakkı da YAMALANIR (RD-turu bulgusu): bu makinede
    ADC varsa testler GERÇEK Firestore'daki dev-user kota dokümanını
    tüketiyor ve dosyadaki ~8 sohbet çağrısı 5'lik günlük hakkı aşınca
    son testler 402 ile düşüyordu — üstelik yalnız ADC'li makinelerde
    (testin sonucu ortama bağlıydı). Kota mantığının kendi testleri
    entitlements tarafında; burada konu sohbet DAVRANIŞI.
    """
    from core import entitlements
    monkeypatch.setattr(entitlements, "consume_quota",
                        lambda uid, key, limit, tz=None: True)
    yield
    mw = app.middleware_stack
    while mw is not None:
        if hasattr(mw, "_hits"):
            mw._hits.clear()
        mw = getattr(mw, "app", None)


def test_yonlendirici_sezgileri():
    # Selamlaşma / duygu / kısa onay: RAG atlanmalı
    assert not prompt_composer.should_use_rag("selam")
    assert not prompt_composer.should_use_rag("Merhaba, nasılsın?")
    assert not prompt_composer.should_use_rag("bugün biraz keyifsizim")
    assert not prompt_composer.should_use_rag("tamam, teşekkürler")
    # Kadim bilgi soruları: RAG kullanılmalı
    assert prompt_composer.should_use_rag("Merkür retrosu beni nasıl etkiler?")
    assert prompt_composer.should_use_rag("BaZi haritamda Day Master ne anlama geliyor?")
    assert prompt_composer.should_use_rag("Yükselenim Terazi, bu ne demek?")


def test_selamlasmada_rag_cagrilmaz(monkeypatch):
    """Selamlaşma mesajında ne RAG araması ne embedding çağrısı yapılmalı."""
    called = {"rag": False}

    def fake_retrieve(query, top_k=2, **k):
        called["rag"] = True
        return []

    monkeypatch.setattr("api.chat.retrieve_passages", fake_retrieve)
    monkeypatch.setattr(gemini_service, "chat",
                        lambda history, msg, **k: "Selam sana da!")

    with TestClient(app) as client:
        response = client.post("/api/v1/chat", json={"history": [], "message": "selam"})
        assert response.status_code == 200
        assert not called["rag"]


def test_bilgi_sorusunda_rag_cagrilir_ve_kirpilir(monkeypatch):
    """Bilgi sorusunda RAG çağrılır; pasajlar kırpılıp fısıltı olarak eklenir."""
    captured = {}
    long_passage = {"doc": "d", "title": "t", "text": "x" * 2000, "score": 0.9}

    monkeypatch.setattr("api.chat.retrieve_passages",
                        lambda q, top_k=2, **k: [long_passage] * 3)

    def fake_chat(history, msg, **k):
        captured["msg"] = msg
        return "Kısa dostane yanıt."

    monkeypatch.setattr(gemini_service, "chat", fake_chat)

    with TestClient(app) as client:
        response = client.post(
            "/api/v1/chat",
            json={"history": [], "message": "Merkür retrosu beni nasıl etkiler?"},
        )
        assert response.status_code == 200

    msg = captured["msg"]
    assert "ARKA PLAN FISILTISI" in msg

    # Kırpmanın ölçüsü PASAJLARIN kendisidir, prompt'un tamamı değil.
    #
    # Bu iddia eskiden `len(msg)` üzerindeydi ve sabit persona etiketleriyle
    # değişken pasaj içeriğini aynı bütçede topluyordu. Sonuç: etiketlere
    # bilinçli olarak bir cümle eklemek (harita fısıltısına "spesifik ol",
    # kaynak fısıltısına "kaynağın ahlaki yargısını aktarma") kırpma testini
    # kırıyordu — oysa kırpma kusursuz çalışıyordu. Test artık yalnızca
    # kendi konusunu ölçüyor.
    pasaj_satirlari = [s for s in msg.splitlines() if s.startswith("- x")]
    assert len(pasaj_satirlari) == 2, "en fazla 2 pasaj eklenmeli"
    for satir in pasaj_satirlari:
        # "- " öneki, iç kaynak etiketi (RD5, ≤64 kr) ve kırpma "…"
        # haricinde sınıra uymalı.
        assert len(satir) <= prompt_composer.MAX_PASSAGE_CHARS + 64, (
            f"pasaj kırpılmamış: {len(satir)} karakter")


def test_olgu_bekcisi_hesaplanmis_haritayi_alir(monkeypatch):
    """KA8: `enforce`'a `facts` GEÇİRİLMELİ. Verilmeyince bekçi dayanağı
    prompt metninden yeniden çıkarıyordu (R8'in kapattığı kırılganlık) ve
    doğru konumlar "uydurma" damgası yiyip boşa yeniden üretime yol
    açıyordu."""
    from services import fact_guard

    yakalanan = {}

    def sahte_enforce(reply, message, lang=None, regenerate=None, **k):
        # `facts` yalnız gerçekten geçirildiyse k'ya düşer — eski imzayla
        # çağrı yakalanan'ı boş bırakır ve test kırılır.
        yakalanan.update(k)
        return reply, False

    monkeypatch.setattr(fact_guard, "enforce", sahte_enforce)
    monkeypatch.setattr(gemini_service, "chat",
                        lambda history, msg, **k: "yanıt")
    with TestClient(app) as client:
        r = client.post("/api/v1/chat",
                        json={"history": [], "message": "bugün nasılım?"})
        assert r.status_code == 200
    # Profilsiz test kullanıcısında facts None olabilir; kritik olan
    # PARAMETRENİN geçirilmesi — anahtar yakalanmadıysa çağrı eski imzada.
    assert "facts" in yakalanan


def test_akraba_kelimesi_kisi_fisiltisini_bağlar(monkeypatch):
    """KA6: ana sekmeden "eşimle aram nasıl?" sorusu artık bağlamsız
    gitmez — sunucu akraba kelimesinden kişiyi çözer ve ölçülen ilişki
    fısıltısını iliştirir."""
    from services import circle_context, synastry_service

    monkeypatch.setattr(circle_context, "person_for_relation",
                        lambda uid, tur: "p1" if tur == "partner" else None)
    monkeypatch.setattr(circle_context, "circle_whisper",
                        lambda uid, lang=None: "- eşin: Güneş Terazi")
    monkeypatch.setattr(
        synastry_service, "person_counterpart",
        lambda uid, pid, lang=None: object())
    monkeypatch.setattr(
        synastry_service, "whisper_for",
        lambda uid, karsi, lang, max_chars=600:
            "Kişi: eşin (Terazi)\n- İletişim: Güçlü · akıcı")

    yakalanan = {}

    def sahte_chat(history, msg, **k):
        yakalanan["msg"] = msg
        return "yanıt"

    monkeypatch.setattr(gemini_service, "chat", sahte_chat)
    with TestClient(app) as client:
        r = client.post("/api/v1/chat", json={
            "history": [], "message": "Eşimle aram nasıl olacak?"})
        assert r.status_code == 200
    msg = yakalanan["msg"]
    assert "İLİŞKİ ÖLÇÜMÜ" in msg
    assert "İletişim: Güçlü" in msg
    assert "ÇEVRESİ" in msg  # roster da her turda giriyor


def test_cevre_fisiltisi_her_turda(monkeypatch):
    """KA6: kişi anılmayan sohbette bile model çevreyi BİLİR (tali yorum
    için); derin ölçüm ise iliştirilmez."""
    from services import circle_context

    monkeypatch.setattr(circle_context, "circle_whisper",
                        lambda uid, lang=None: "- çocuğun: Güneş Koç")
    yakalanan = {}

    def sahte_chat(history, msg, **k):
        yakalanan["msg"] = msg
        return "yanıt"

    monkeypatch.setattr(gemini_service, "chat", sahte_chat)
    with TestClient(app) as client:
        r = client.post("/api/v1/chat",
                        json={"history": [], "message": "bugün nasılım?"})
        assert r.status_code == 200
    assert "çocuğun: Güneş Koç" in yakalanan["msg"]
    assert "İLİŞKİ ÖLÇÜMÜ" not in yakalanan["msg"]


def test_api_semasi_degismedi(monkeypatch):
    """İstek/yanıt şeması korunmalı — istemci sözleşmesi.

    `conversation_id` Revize R4 ile eklendi (sohbet arşivi): istemci dönen
    kimliği izleyip sonraki turlarda geri gönderiyor. Alanın DÜŞMESİ artık
    sözleşme kırılmasıdır; bu test o günden beri üç alanı birden koruyor.
    """
    monkeypatch.setattr(gemini_service, "chat",
                        lambda history, msg, **k: "test yanıtı")

    with TestClient(app) as client:
        response = client.post(
            "/api/v1/chat",
            json={
                "history": [{"sender": "USER", "text": "merhaba"},
                            {"sender": "AI", "text": "selam"}],
                "message": "nasılsın",
            },
        )
        assert response.status_code == 200
        body = response.json()
        assert set(body.keys()) == {"status", "reply", "conversation_id"}
        assert body["status"] == "success"
        assert isinstance(body["reply"], str)


# ---------------------------------------------------------------------------
# Maliyet kapilari: ucun ham `request.message`'i PARA ODENEN yollara
# vermedigi civilenir.
# ---------------------------------------------------------------------------

def test_cikarima_giden_mesaj_BAGLI(monkeypatch):
    """Olgu cikarimina giden mesaj KIRPILMIS olmali.

    `ChatRequest.message` bir Pydantic `str` ve uzunluk siniri YOK; ucun
    tek bagi `chat_history.clip_message` (2.000). Olculdu (48-turu
    raporunun yanlis anlasilan maddesi): o bag YALNIZ composer'a ve arsive
    uygulaniyordu, cikarima HAM metin gidiyordu ve `_conversation_text`
    240.000 karakterlik bir mesajla 240.010 karakterlik bir LLM prompt'u
    uretiyordu. `history` kalemleri `clip_for_prompt`le bagliydi, yani
    bagsiz olan tek sey SON mesajdi.

    Gunluk kota (DAILY_EXTRACTIONS) cagri SAYISINI sinirlar, BOYUNU
    sinirlamaz; ustelik bagam penceresini asan prompt cikarimi dusurur ve
    kullanicinin o gunluk hakki yenmis olur.

    Bekci UZUNLUGA degil KIRPILMIS KAYNAGA bakiyor: `clip_message`
    tavaninin kendi bekcisi `test_chat_prompt_disiplini.py`de (gevsek ust
    sinir), burada olculen sey ucun o kapidan GECIRIP GECIRMEDIGI.
    """
    from services import memory_extractor

    yakalanan = {}

    def sahte_cikar(uid, history, last_message, **k):
        yakalanan["mesaj"] = last_message
        return None

    monkeypatch.setattr(memory_extractor, "extract_and_store", sahte_cikar)
    monkeypatch.setattr(gemini_service, "chat",
                        lambda history, msg, **k: "yanit")

    uzun = "Merkur retrosu hakkinda " * 10_000
    with TestClient(app) as client:
        r = client.post("/api/v1/chat",
                        json={"history": [], "message": uzun})
        assert r.status_code == 200

    from services import chat_history
    assert "mesaj" in yakalanan, "cikarim arka plan isi hic kurulmadi"
    assert len(yakalanan["mesaj"]) <= chat_history.MAX_MESSAGE_CHARS, (
        f"cikarima {len(yakalanan['mesaj'])} karakter gitti — ham mesaj "
        f"LLM prompt'una bagsiz giriyor")


@pytest.mark.parametrize("tohum", (False, True))
def test_korpus_sorgusuna_giden_mesaj_BAGLI(monkeypatch, tohum):
    """Korpus sorgusu da KIRPILMIS metinden kurulmali.

    `chart_query.build_query` mesajin kendisini sorgunun ONUNE koyuyor ve
    sonuc `retrieve_passages` ile EMBEDDING cagrisina gidiyor. Olculdu:
    ham metinle 240.000 karakterlik bir mesaj sorguyu 239.999 karaktere
    cikariyordu — ve bu yolda cikarimdaki gibi gunluk bir kota YOK, her
    turda tetikleniyor.

    Ikinci (ve asil) gerekce TUTARLILIK: modelin gordugu metin kirpilmis
    olandir. Modelin hic gormeyecegi bir cumleyle korpus aramak, cevabi
    goremedigi bir soruya gore getirmek olurdu.

    ⚠️ IKI DAL BIRDEN olculuyor ve bu bir KOR BEKCI onarimidir (N2,
    dogrulama turunda minimal mutasyonla olculdu): `kapi_metni` IKI
    DALLI bir ifade (`f"{tohum_soru} {mesaj_metni}" if tohum_bekliyor
    else mesaj_metni`) ve bekci yalniz TOHUMSUZ dali kosturuyordu —
    tohum dalini ham `request.message`a geri alan mutasyon 107/107
    YESIL geciyordu. Tohum dali uretimde gercek bir yol (KA9 aksam
    sorusunun cevabi, `source == "checkin"`) ve ayni embedding
    cagrisina gidiyor, yani bagsiz kalirsa ayni parayi odetir.
    """
    from services import chat_history

    yakalanan = {}

    def sahte_getir(sorgu, top_k=2, **k):
        yakalanan["sorgu"] = sorgu
        return []

    monkeypatch.setattr("api.chat.retrieve_passages", sahte_getir)
    monkeypatch.setattr(gemini_service, "chat",
                        lambda history, msg, **k: "yanit")

    if tohum:
        # Tohum dali ancak `seed_pending` + `seed_question` birlikteyken
        # kosuyor; ikisi KONU DOKUMANINDAN gelir, istemci beyanindan
        # DEGIL (bkz. memory_extractor docstring), bu yuzden sahte konu
        # `prepare` duzeyinde kuruluyor.
        monkeypatch.setattr(
            chat_history, "prepare",
            lambda uid, requested_id: chat_history.PreparedConversation(
                conversation_id="c1", create=False, title_prefix=None,
                message_count=0, seed_question="Bugun nasil gecti?",
                seed_pending=True))

    # RAG'in tetiklenmesi icin alan terimi SART (`should_use_rag`).
    uzun = "Merkur retrosu beni nasil etkiler " * 8_000
    with TestClient(app) as client:
        r = client.post("/api/v1/chat",
                        json={"history": [], "message": uzun})
        assert r.status_code == 200

    assert "sorgu" in yakalanan, "RAG hic cagrilmadi — bekci olcmuyor"
    # Sorgu mesajin USTUNE konu tohumu + harita faktoru ekleyebilir; bu
    # yuzden tam esitlik degil, mesaj payinin bagli oldugu olculuyor.
    # Tohum dalinda tohum SORUSU da onde duruyor, yani payi `MAX_SEED`
    # kadar genis: 600 (`prompt_composer.MAX_SEED_CHARS`) ikisini de
    # kapsiyor ve 240.000'in yaninda hala dar bir kapi.
    assert len(yakalanan["sorgu"]) <= chat_history.MAX_MESSAGE_CHARS + 600, (
        f"korpus sorgusu {len(yakalanan['sorgu'])} karakter (tohum="
        f"{tohum}) — ham mesaj embedding cagrisina bagsiz giriyor")


def test_harita_olgulari_KULLANICININ_yerel_gununden(monkeypatch):
    """`chart_facts` cagrisi `today=` tasimali.

    `chart_facts` transit onbelleginin KOVASINI bu tarihten kuruyor
    (`chart_context`: anahtarda `{gun}`). Verilmezse kova sunucunun UTC
    gununden kurulur ve UTC+3 kullanicisi yerel 00:00-03:00 arasinda
    ONCEKI gunun kovasini okur — TTL 36 saat oldugu icin o kova gercekten
    hayatta olur. Bedeli sessiz: model o transit satirini "bugun" diye
    anlatir, hicbir hata cikmaz.

    Ayni onarim `api/face_reading.py`de yapilmisti; sohbet atlanmisti.

    ⚠️ Olculen sey UCUN KENDI cagrisi, yani TUR BASINA ILK cagri. Ikinci
    bir cagri daha var ve o BASKA BIR PAKETIN dosyasinda:
    `chart_context.chart_whisper` kendisine `facts` verilmezse
    `chart_facts(uid, profile)` diye TARIHSIZ cagiriyor
    (`services/chart_context.py`). Sohbette o dala normalde girilmez
    (uc `facts`i veriyor) ve girildiginde `chart_facts` dogum verisi
    kapisindan None donup kova da kurmuyor — yani uretim zarari yok, ama
    cagrilarin TUMUNU olcen bir bekci bu yuzden kirmizi kalirdi ve
    gerekcesi yanlis okunurdu. Rapora yazildi, onarilmadi (dosya
    sahipligi disinda).
    """
    import datetime as dt

    from core import entitlements
    from services import chart_context, profile_service

    cagrilar = []

    monkeypatch.setattr(profile_service, "get_profile",
                        lambda uid: {"birthDate": "1990-01-01"})
    monkeypatch.setattr(entitlements, "user_local_date",
                        lambda uid: dt.date(2026, 3, 14))
    monkeypatch.setattr(chart_context, "chart_facts",
                        lambda uid, profile, today=None:
                            cagrilar.append(today) or None)
    monkeypatch.setattr(gemini_service, "chat",
                        lambda history, msg, **k: "yanit")

    with TestClient(app) as client:
        r = client.post("/api/v1/chat",
                        json={"history": [], "message": "bugun nasilim?"})
        assert r.status_code == 200

    assert cagrilar, "chart_facts hic cagrilmadi — bekci olcmuyor"
    assert cagrilar[0] == dt.date(2026, 3, 14), (
        f"chart_facts gunu {cagrilar[0]!r} ile cagrildi — kullanicinin "
        f"yerel gunu gecirilmiyor (sunucunun UTC gunune dusuyor)")


@pytest.mark.parametrize("dil", ("tr", "en"))
def test_hafiza_fisiltisi_OTURUMUN_DILINDE(monkeypatch, dil):
    """Hafiza fisiltisinin etiketleri OTURUMUN dilinde olmali.

    `memory_context` uzun sure dil parametresi ALMIYORDU: blok BASLIGI
    (`prompts.WHISPER_MEMORY`) dile gore geliyordu ama ICERIGIN etiketleri
    sabit Turkceydi, yani Ingilizce bir prompt Ingilizce basligin altinda
    "(ton tercihi)" ve "(ruh hali seyri)" satirlari tasiyordu.

    Bekci UCTAN UCA: `memory_context`e "lang gecti mi" diye bakmiyor,
    modele GERCEKTEN giden prompt'u okuyor. Argument-gecti bekcisi
    `memory_context`in o argumani KULLANMADIGI hali yesil gecirirdi.

    Capa `prompts` modullerinden OKUNUYOR, tek Turkce kelimeye bagli
    degil: etiket metni degisirse bekci yine dogru seyi olcer.

    ⚠️ IKI DIL BIRDEN olculuyor ve bu bir KOR BEKCI onarimidir (N1,
    dogrulama turunda minimal mutasyonla olculdu): bekci yalniz EN
    yonunu olcerken `api/chat.py`de `lang=lang` yerine `lang="en"`
    yazilmasi 107/107 YESIL geciyordu — yani onarilan kusurun AYNASI
    (Turkce oturumun Ingilizce etiket almasi) hic olculmuyordu. Tek
    yonlu bir dil iddiasi, dili SABITLEYEN mutasyonu gormez; yonu
    `memory_service` duzeyinde olcen `test_memory.py` bekcisi de ucun
    TELINI gormez (fonksiyonu dogrudan cagiriyor).
    """
    from services import memory_service, prompts

    monkeypatch.setattr(memory_service, "get_memory", lambda uid: {
        "facts": [], "moodTrail": [], "diary": [],
        "toneHint": "kisa ve dogrudan yanit tercih ediyor",
    })
    yakalanan = {}
    monkeypatch.setattr(gemini_service, "chat",
                        lambda history, msg, **k:
                            yakalanan.update(msg=msg) or "answer")

    with TestClient(app) as client:
        r = client.post("/api/v1/chat",
                        json={"history": [], "message": "how am i today?"},
                        headers={"Accept-Language": dil})
        assert r.status_code == 200

    msg = yakalanan["msg"]
    bu = prompts.get(dil)
    oteki = prompts.get("en" if dil == "tr" else "tr")
    assert f"({bu.MEM_TONE})" in msg, (
        f"{dil}: ton etiketi prompt'ta yok; hafiza blogu: "
        f"{[s for s in msg.splitlines() if s.startswith('- (')]}")
    assert f"({oteki.MEM_TONE})" not in msg, (
        f"{dil}: prompt'ta OTEKI dilin ton etiketi duruyor "
        f"({oteki.MEM_TONE!r}) — dil sabitlenmis olabilir")


@pytest.mark.skipif(
    os.getenv("RYTHO_CANLI_LLM") != "1" or not config.GEMINI_API_KEY,
    reason="Canlı LLM izni yok (RYTHO_CANLI_LLM=1 gerekir)")
def test_canli_yanit_kisa_ve_sohbet_havasinda():
    """Canlı Gemini ile tek örnek: yanıt makul kısalıkta ve markdown'sız.

    ⚠️ KAPI "anahtar var mı" DEĞİL, AÇIK İZİN. Eski hâli
    `skipif(not config.GEMINI_API_KEY)` idi ve bu bir kalkan değil yokluk
    kontrolüydü: geliştirici makinesinde `.env` üzerinden anahtar VARDIR,
    yani test her zaman koşuyordu. Bedeli ölçüldü — 48-turunda bir ajan bu
    dosyayı dört kez koşturup üretim kotasından ~4 sohbet çağrısı harcadı,
    hem de üretim projesinin `Lightning dunning` reddi aldığı gün. Kota
    gerçek paradır. Hermetiklik artık `conftest.gemini_hermetik`'te
    varsayılan; bu işaret o pinin bilinçli çıkış yolu.

    ## Eşik neden 700'den 900'e çıktı (48-turu)

    Uzunluk kuralı K4 ile KONUYA GÖRE oldu: "Merkür retrosu ne demek?" bir
    KAVRAM sorusudur ve prompt'un kendi üst sınırı o kutu için 8 cümle.
    Deponun ölçümüyle (4 cümle ~85 token, 3,6 karakter/token) 8 cümle
    ~610 karakter — yani 700, kuralın İZİN VERDİĞİ bir yanıtı kırmızıya
    düşürebiliyordu. Eşik prompt'un sınırından türetilmeli, yoksa test
    ürünün kendi kararını yalanlar.

    900, 8 cümlelik yanıtın üstünde ama "makale" tarifinin (12+ cümle)
    altında kalır; yani testin asıl işi — şikâyetin kendisini yakalamak —
    duruyor. ⚠️ Bu iddia 48-turunda KOŞULMADI: tur boyunca canlı model
    çağrısı yapılmadı (üretim kotası gerçek para), eşik ölçülmüş
    karakter/cümle oranından türetildi.
    """
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/chat",
            json={"history": [], "message": "Merkür retrosu ne demek?"},
        )
        assert response.status_code == 200
        reply = response.json()["reply"]
        assert 0 < len(reply) < 900, f"Yanıt çok uzun ({len(reply)}): {reply[:200]}"
        assert "##" not in reply
        assert "**" not in reply

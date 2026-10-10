"""Persona bekçisi: Rytho yetki alanında kalır, sohbet hesaplamaz.

Fikstürler ÜRETİMDEN (2026-10-10, konuşma ssFpW7dgpeHkD37GGLwj, salt
okuma): tur 9 (kendiliğinden teklif), tur 12 (görev talebi), tur 13
(görev üstlenme + bilgi toplama), tur 31 (üçüncü kişiye Güneş/Ay
yakıştırma). Hiçbir test canlı LLM çağırmaz — `regenerate` sahte,
`gemini_service.chat` yamalı; Gemini kotası üretim projesinde gerçek para.

Her işaret için AYRI minimal fikstür var: Aysun turları birden çok işareti
birden taşıyor (tur 13 hem teklif hem bilgi toplama) ve tek bir kalıbı
bozan mutasyon öteki işaret yüzünden yeşil kalırdı — bekçi kör olurdu.

Çalıştırma:
    .venv\\Scripts\\python.exe -m pytest tests/test_persona_guard.py -q
"""
from __future__ import annotations

import io
import tokenize
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from main import app
from services import fact_guard, gemini_service, persona_guard, prompts

#: Üretim fikstürleri (model çıktısı, birebir).
TUR9 = ("Bunu duymak güzel. Hazırlık aşamasında kafana takılan bir detay "
        "olursa ya da sunumun havasını nasıl tasarlayacağını düşünürsen, "
        "buradayım.")
TUR12 = "sen sunum hazırlayabilir misin"
TUR13 = ("Sana ilham verecek harika bir sunum taslağı ve akış planı "
         "hazırlayabilirim elbette. Hangi konuda konuşacağınızı, "
         "öğrencilerin yaş grubunu ve ne kadar süreniz olduğunu anlatman "
         "yeterli.")
TUR31 = ("Ayşe Öykü, Güneş'i Boğa burcunda ve Ay'ı Akrep burcunda doğmuş; "
         "bu ona hem kararlılık hem derinlik verir.")


@pytest.fixture(autouse=True)
def _kota_sifirla(monkeypatch):
    """`test_chat_style` ile aynı sebep: uç testleri günlük ücretsiz hakkı
    yemesin, rate-limit sayaçları öteki dosyalara taşmasın."""
    from core import entitlements
    monkeypatch.setattr(entitlements, "consume_quota",
                        lambda uid, key, limit, tz=None: True)
    yield
    mw = app.middleware_stack
    while mw is not None:
        if hasattr(mw, "_hits"):
            mw._hits.clear()
        mw = getattr(mw, "app", None)


# ---------------------------------------------------------------------------
# 1. Giriş: görev talebi
# ---------------------------------------------------------------------------

def test_aysun_tur12_gorev_talebi():
    assert persona_guard.task_request(TUR12, "tr")


@pytest.mark.parametrize("mesaj", (
    "bana bir e-posta yazar mısın",
    "ödevimi yapar mısın lütfen",
    "bunu ingilizceye çevirir misin",
    "internette araştırır mısın bunu",
    "can you make me a presentation for tomorrow",
    "could you help me with my essay",
    "please translate this text for me",
))
def test_gorev_talebi_iki_dilde(mesaj):
    assert persona_guard.task_request(mesaj, "tr")


@pytest.mark.parametrize("mesaj", (
    # Yük paylaşımı / karar sorusu — görev DEĞİL; persona karşılar.
    "Sunumu yetiştirirsem mutlu olurum, ne yapmalıyım?",
    "akşam sunum var yetiştiremiyorum ne yapmalıyım",
    "what should I do, I have a presentation tonight",
    # "yaz" mevsimdir; "bana" talep işareti olsa bile nesne yok.
    "bu yaz ne olacak bana?",
    # Astrolojik nesne: Rytho'nun kendi işi.
    "haritamı yazar mısın",
    "could you look at my chart",
    "sana bir şey sorayım, yükselenim ne?",
    "Bugün çok kötü hissediyorum, geçecek mi?",
    "Eşimle aram nasıl olacak?",
))
def test_yuk_paylasimi_ve_astroloji_gorev_degil(mesaj):
    """Yanlış pozitifin bedeli yanlış bir "alanım değil" cümlesi; kalıplar
    bu yüzden dar — darlık burada çivili."""
    assert not persona_guard.task_request(mesaj, "tr")


# ---------------------------------------------------------------------------
# 1b. Giriş: doğum verisi
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("mesaj, beklenen", (
    ("29/04/2010 istanbul", True),
    ("17/01/2012", True),
    ("29 nisan 2010 doğumlu kızım", True),
    ("born on march 3, 1990 in london", True),
    ("1990 doğumluyum", True),
    ("karabük/Safranbolu", False),
    ("bugün nasılım", False),
    ("saat 10.30 gibi", False),
))
def test_dogum_verisi_tanima(mesaj, beklenen):
    assert persona_guard.birth_data_in_message(mesaj) is beklenen


def test_fisilti_mesajin_hemen_ustune():
    """Fısıltı KULLANICI MESAJI etiketinin hemen üstüne girer — mesaja
    yakınlık ağırlık demek (`prompt_composer` sıra sözleşmesi)."""
    p = prompts.get("tr")
    kurulu = f"HARİTA\n- Güneş: Koç\n\n{p.USER_MESSAGE_LABEL}: {TUR12}"
    cikti = persona_guard.attach(kurulu, TUR12, "tr")
    assert p.PERSONA_WHISPER_TASK in cikti
    assert cikti.index(p.PERSONA_WHISPER_TASK) > cikti.index("HARİTA")
    assert cikti.index(p.PERSONA_WHISPER_TASK) < cikti.index(
        f"{p.USER_MESSAGE_LABEL}: {TUR12}")
    assert cikti.endswith(TUR12)


def test_fisilti_yoksa_mesaj_degismez():
    assert persona_guard.attach("selam", "selam", "tr") == "selam"


@pytest.mark.parametrize("dil", ("tr", "en"))
def test_fisilti_burc_adi_tasimaz(dil):
    """Fısıltı prompt'a giriyor ve olgu bekçisi prompt'tan DAYANAK
    çıkarıyor: fısıltıda gezegen+burç çifti dursa, uydurulmuş bir konum
    "prompt'ta var" sayılırdı. Fısıltı burç adı taşımaz."""
    p = prompts.get(dil)
    for ad in ("PERSONA_WHISPER_TASK", "PERSONA_WHISPER_BIRTH",
               "PERSONA_RETRY_TASK", "PERSONA_RETRY_THIRD_PARTY"):
        assert fact_guard.extract_claims(getattr(p, ad)) == set(), ad


# ---------------------------------------------------------------------------
# 2. Çıkış: kayma
# ---------------------------------------------------------------------------

def test_aysun_tur13_gorev_ustlenme():
    assert persona_guard.drifted(TUR13, "tr")


def test_aysun_tur9_kendiliginden_teklif():
    assert persona_guard.drifted(TUR9, "tr")


def test_teklif_fiili_tek_basina_yeter():
    """Tur 13'ün yalnız TEKLİF yarısı (bilgi toplama sorusu yok)."""
    assert persona_guard.drifted(
        "Harika bir sunum taslağı hazırlayabilirim elbette.", "tr")


def test_bilgi_toplama_tek_basina_yeter():
    """Tur 13'ün yalnız BİLGİ TOPLAMA yarısı (teklif fiili yok)."""
    assert persona_guard.drifted(
        "Sunum için hangi konuda konuşacağını anlatman yeterli.", "tr")


@pytest.mark.parametrize("yanit", (
    "I can draft a presentation outline for you — just tell me the topic.",
    "Sure — here's your outline:\n1. Intro\n2. Body\n3. Close",
    "If you want, I can help you structure the presentation, just let me "
    "know the topic.",
))
def test_ingilizce_kayma(yanit):
    assert persona_guard.drifted(yanit, "en")


@pytest.mark.parametrize("yanit", (
    # Dost cümleleri: "buradayım" ve "yardımcı olabilirim" tek başına kusur
    # değil — tasarlama/hazırlama fiili yoksa.
    "Sunum gerginliğin için buradayım; bugün gökyüzü ifade tarafını biraz "
    "sıkıştırıyor, derin bir nefes yeter. ✨",
    "Bu gerginlikle başa çıkmanda yardımcı olabilirim; önce bir nefes al.",
    "Sunumun için gergin olman çok normal; bugün Ay ifade alanına "
    "dokunuyor.",
    "Hangi konuda konuşmak istersin?",
    "Planlarını haritanla birlikte düşünmene yardımcı olabilirim.",
    "Venüs Terazi'de ilişkiyi kolaylaştırır.",
))
def test_dost_cumlesi_kayma_degil(yanit):
    assert not persona_guard.drifted(yanit, "tr")


# ---------------------------------------------------------------------------
# 2b. Çıkış: üçüncü kişi
# ---------------------------------------------------------------------------

def test_aysun_tur31_bos_cevrede_uydurma():
    assert persona_guard.third_party_claims(TUR31, "29/04/2010 istanbul",
                                            circle="", relationship="")


def test_cevrede_adiyla_duran_arkadas_mesru():
    """Çevre listesi "Ad (Burç)" yazar: o burcu sunucu hesapladı."""
    # Doğum verisi girilmiş (kapı açık) — yine de çevredeki ad meşru.
    assert not persona_guard.third_party_claims(
        TUR31, "29/04/2010 istanbul",
        circle="- Arkadaşları: Ayşe Öykü (Boğa)", relationship="")


def test_yalniz_gunes_iddiasi_da_yakalanir():
    """Tek yıldızlı minimal fikstür — tur 31 iki yıldız taşıyor ve tek
    kalıbı bozan mutasyonu öteki kurtarırdı."""
    assert persona_guard.third_party_claims(
        "Ahmet'in Güneş'i Oğlak burcunda, pratik biri.",
        "Ahmet 12/03/1990 doğumlu", "", "")


def test_ingilizce_ucuncu_kisi():
    assert persona_guard.third_party_claims(
        "Ayşe's Sun is in Taurus and her Moon in Scorpio.",
        "Ayşe was born on 29/04/2010", "", "")


@pytest.mark.parametrize("yanit", (
    # 2. tekil iyelik: kullanıcının KENDİ Güneş'i — meşru (harita fısıltıda).
    "Senin Güneş'in Boğa'da, Ay'ın Akrep'te.",
    "Bugün Güneş'in Boğa'da olması sana sağlam bir zemin veriyor.",
    "Your Sun is in Taurus.",
    # Cümle başı bağlacı ad değildir; astroloji sözlüğü de değildir.
    "Ancak, Güneş'i Boğa'da olan biri için bu dönem zor.",
    "Boğa Güneş'i sana sabır verir.",
    # Ad var, burç yok: benzetme, iddia değil.
    "Ayşe'nin Güneş'i parlıyor bugün.",
))
def test_kullanicinin_kendisi_ve_sozluk_ucuncu_kisi_degil(yanit):
    # Kapı AÇIK (doğum verisi var) ki dedektörün kendisi ölçülsün; kapalı
    # kapı bu dizgileri zaten geçirir ve testi kör bırakırdı (harness'ta
    # ölçüldü).
    assert not persona_guard.third_party_claims(
        yanit, "12/03/1990 Ankara doğumlu", "", "")


# ---------------------------------------------------------------------------
# 3. enforce
# ---------------------------------------------------------------------------

def test_enforce_temiz_metne_dokunmaz():
    cagri = []
    metin, temiz = persona_guard.enforce(
        "Bugün ifade tarafın biraz sıkışık; bir nefes yeter.", "prompt",
        lang="tr", regenerate=lambda p: cagri.append(p) or "x")
    assert temiz is True and not cagri


def test_enforce_ikinci_uretim_temizse_onu_dondurur():
    temiz_metin = "Bu benim alanım değil; ama bugün ifade tarafın sıkışık."
    cagri = []

    def uret(p):
        cagri.append(p)
        return temiz_metin

    metin, temiz = persona_guard.enforce(TUR13, "prompt", lang="tr",
                                         regenerate=uret)
    assert temiz is True and metin == temiz_metin
    assert len(cagri) == 1
    assert prompts.get("tr").PERSONA_RETRY_TASK in cagri[0]


def test_enforce_ikinci_uretim_de_kirliyse_sabit_cumle():
    """Kusurlu metin kullanıcıya GİTMEZ — ne ilk ne ikinci üretim.
    `fact_guard.enforce`'tan ayrılan nokta tam bu."""
    cagri = []

    def uret(p):
        cagri.append(p)
        return TUR13  # ikinci üretim de aynı kusuru taşıyor

    metin, temiz = persona_guard.enforce(TUR13, "prompt", lang="tr",
                                         regenerate=uret)
    assert temiz is False
    assert metin == prompts.get("tr").PERSONA_FALLBACK_TASK
    assert "hazırlayabilirim" not in metin
    assert len(cagri) == 1, "yeniden üretim TEK sefer"


def test_enforce_ucuncu_kisi_sabit_cumlesi_oncelikli():
    """Uydurulmuş veri, görev kaymasından ağırdır: ikisi birdense
    üçüncü-kişi cümlesi döner."""
    kirli = TUR31 + " " + TUR13
    metin, temiz = persona_guard.enforce(kirli, "prompt", lang="tr",
                                         regenerate=lambda p: kirli,
                                         message="29/04/2010 istanbul")
    assert temiz is False
    assert metin == prompts.get("tr").PERSONA_FALLBACK_THIRD_PARTY


def test_enforce_regenerate_yoksa_dogrudan_sabit_cumle():
    metin, temiz = persona_guard.enforce(TUR13, "prompt", lang="en")
    assert temiz is False
    assert metin == prompts.get("en").PERSONA_FALLBACK_TASK


@pytest.mark.parametrize("dil", ("tr", "en"))
def test_sabitler_iki_dilde_var(dil):
    p = prompts.get(dil)
    for ad in ("PERSONA_WHISPER_TASK", "PERSONA_WHISPER_BIRTH",
               "PERSONA_RETRY_TASK", "PERSONA_RETRY_THIRD_PARTY",
               "PERSONA_FALLBACK_TASK", "PERSONA_FALLBACK_THIRD_PARTY"):
        assert getattr(p, ad, "").strip(), f"{dil}: {ad} boş"


# ---------------------------------------------------------------------------
# 4. Uç kabloları (api/chat.py)
# ---------------------------------------------------------------------------

_CHAT_PY = Path(__file__).resolve().parents[1] / "api" / "chat.py"


def _yorumsuz(kaynak: str) -> str:
    """Yorum belirteçlerini SİLER, kodun kendisine dokunmaz — bir şeyin
    VARLIĞINI arayan bekçi, onu ANLATAN yorumu görmemeli (CLAUDE.md §5,
    iki kez patladı). Belirteçleri yeniden birleştirmek değil, yorumun
    yerini boşaltmak: `fact_guard.enforce(` bitişik kalmalı."""
    satirlar = kaynak.splitlines(keepends=True)
    for tok in tokenize.generate_tokens(io.StringIO(kaynak).readline):
        if tok.type == tokenize.COMMENT:
            satir, bas = tok.start
            _, son = tok.end
            satirlar[satir - 1] = (satirlar[satir - 1][:bas]
                                   + satirlar[satir - 1][son:])
    return "".join(satirlar)


def test_uc_persona_bekcisini_olgu_bekcisinden_sonra_cagirir():
    kaynak = _yorumsuz(_CHAT_PY.read_text(encoding="utf-8"))
    olgu = kaynak.find("fact_guard.enforce(")
    persona = kaynak.find("persona_guard.enforce(")
    assert olgu >= 0, "olgu bekçisi kablosu kopmuş"
    assert persona >= 0, "persona bekçisi uçta kablolu değil"
    assert olgu < persona, "persona bekçisi olgu bekçisinden SONRA çağrılmalı"
    assert "persona_guard.attach(" in kaynak, "giriş fısıltısı kablolu değil"


def test_uc_engellenen_turu_blocked_ile_yazar_kaynak():
    """Yasak-alan turu arşivlenir ve konu kimliği döner; KRİZ turu
    BİLEREK arşivlenmez (kullanıcının geçmişinde durmasın) ve kimlik de
    dönmez (yazılmamış rezerve kimlik, bir sonraki mesajı yetim bırakırdı)."""
    kaynak = _yorumsuz(_CHAT_PY.read_text(encoding="utf-8"))
    assert "blocked=kategori" in kaynak
    assert kaynak.count("_engellenen_turu_kaydet(") == 2, (
        "tanım + yasak alan: kriz dalı arşive YAZMAZ")
    kriz = kaynak[kaynak.find("crisis_signal(request.message)"):
                  kaynak.find('"blocked": "crisis"')]
    assert "_engellenen_turu_kaydet(" not in kriz
    assert "conversation_id" not in kriz
    yasak = kaynak[kaynak.find("blocked = forbidden_topic("):
                   kaynak.find('"blocked": kategori')]
    assert "_engellenen_turu_kaydet(" in yasak
    assert '"blocked": kategori,' in kaynak and (
        '"conversation_id": (hazir_konu.conversation_id' in kaynak), (
        "engellenen yanıt konu kimliğini döndürmeli — yoksa yetim konu")


def test_uc_persona_bekcisine_mesaj_ve_gecmis_gecer():
    """Üçüncü-kişi kapısı doğum verisini bu mesaj VE prompt geçmişinde
    arar; uç ikisini de geçirmezse kapı hiç açılmaz ya da hep kapalı kalır."""
    kaynak = _yorumsuz(_CHAT_PY.read_text(encoding="utf-8"))
    cagri = kaynak[kaynak.find("persona_guard.enforce("):]
    cagri = cagri[:cagri.find(")") + 1]
    assert "message=mesaj_metni" in cagri
    assert "history=" in cagri


_TUR17_KENDI_HARITASI = (
    "Eşinle arandaki o tatlı ve akıcı iletişim enerjisi, şu sıralar seni "
    "duygusal anlamda çok güzel besliyor olmalı. Haritanda Güneş'inin Yay "
    "burcundaki Jüpiter ile yaptığı o geniş açının getirdiği neşe, eşinin Yay "
    "burcu doğasıyla birleştiğinde aranızda doğal bir neşe yaratıyor.")
_TUR31_COCUK = ("Ayşe Öykü, Güneş'i Boğa burcunda ve Ay'ı Akrep burcunda olan, "
                "son derece kararlı bir çocuk.")


def test_ucuncu_kisi_kapisi_dogum_verisi_yokken_kapali():
    """Ölçülen yanlış pozitif (kapanış probu): kullanıcının KENDİ haritasını
    anlatan yanıtta cümle başındaki "Haritanda" ad sanılıyor ve doğru cevap
    sabit cümleyle eziliyordu. Doğum verisi girilmemişse bekçi bakmaz."""
    assert persona_guard.third_party_claims(
        _TUR17_KENDI_HARITASI, message="Aşk hayatı ❤️") is False
    # Aynı yanıt, doğum verisi girilmiş olsa bile ad sayılmaz:
    assert persona_guard._ad_mi("Haritanda") is None
    # Kapının KENDİSİ: gerçek bir adlı iddia bile doğum verisi girilmemişse
    # bekçiyi açmaz (ölçülen tek uydurma kaynağı sohbete yazılan tarih;
    # tarihsiz soruda model zaten doğum verisi istiyor — tur 29/39).
    assert persona_guard.third_party_claims(
        "Ahmet'in Güneş'i Oğlak burcunda, pratik biri.",
        message="Ahmet nasıl biri?") is False


def test_ucuncu_kisi_kapisi_dogum_verisiyle_acilir_ve_gecmisle_tasinir():
    assert persona_guard.third_party_claims(
        _TUR31_COCUK, message="29/04/2010 istanbul") is True
    # Tarih bir önceki turda girildi, bu tur "evet lütfen": uydurma geçmişle
    # taşınır (ölçüldü: aynı konuşmada tarihsiz 3 turda daha adlı burç).
    assert persona_guard.third_party_claims(
        _TUR31_COCUK, message="evet lütfen",
        history="peki ayşe Öykü için neler olacak 29/04/2010 istanbul") is True
    assert persona_guard.third_party_claims(
        _TUR31_COCUK, message="evet lütfen", history="nasıl bir adım") is False


@pytest.mark.parametrize("yanit", (
    # Tek işaretli minimal fikstürler: tur 13 üç işaret birden taşıyor,
    # tek kalıbı bozan mutasyonu ötekiler kurtarıyordu (harness'ta ölçüldü).
    "Sana bir sunum taslağı hazırlayabilirim.",
    "Hangi konuda konuşacağını anlatman yeterli, slayt akışını kurarız.",
))
def test_gorev_kaymasi_tek_isaretle_de_yakalanir(yanit):
    assert persona_guard.drifted(yanit, "tr")


def test_uc_kirli_yaniti_kullaniciya_gondermez(monkeypatch):
    """Model iki kez de görev üstlenirse ekrana sabit cümle gider."""
    cagrilar = []

    def sahte_chat(history, msg, **k):
        cagrilar.append(msg)
        return TUR13

    monkeypatch.setattr(gemini_service, "chat", sahte_chat)
    with TestClient(app) as client:
        r = client.post("/api/v1/chat", json={"history": [], "message": TUR12})
        assert r.status_code == 200
    assert r.json()["reply"] == prompts.get("tr").PERSONA_FALLBACK_TASK
    assert len(cagrilar) == 2, "bir üretim + TEK yeniden üretim"
    # Giriş fısıltısı da ilk prompt'ta: modele kusurdan ÖNCE söylendi.
    assert prompts.get("tr").PERSONA_WHISPER_TASK in cagrilar[0]
    assert prompts.get("tr").PERSONA_RETRY_TASK in cagrilar[1]


def test_uc_engellenen_turu_arsive_yazar(monkeypatch):
    """Yasak alan kapısında dönen tur `write_turn(blocked=…)` ile yazılır —
    kapının yanlış pozitifleri ancak kayıtlı turdan ölçülür."""
    from services import chat_history

    yazilan = {}

    def sahte_write_turn(uid, prepared, user_text, ai_text, lang,
                         friend_uid=None, person_id=None, blocked=None):
        yazilan.update(user_text=user_text, ai_text=ai_text, blocked=blocked)

    monkeypatch.setattr(chat_history, "write_turn", sahte_write_turn)
    monkeypatch.setattr(
        chat_history, "prepare",
        lambda uid, requested_id: chat_history.PreparedConversation(
            "c1", True, None, 0))
    monkeypatch.setattr(gemini_service, "chat",
                        lambda history, msg, **k: pytest.fail(
                            "engellenen tur modele gitmemeli"))
    with TestClient(app) as client:
        r = client.post("/api/v1/chat",
                        json={"history": [], "message":
                              "Should I buy bitcoin now?"})
        assert r.status_code == 200
        assert r.json()["blocked"] == "finans"
    assert yazilan.get("blocked") == "finans"
    assert yazilan["user_text"] == "Should I buy bitcoin now?"
    assert yazilan["ai_text"] == r.json()["reply"]


def test_uc_engellenen_tur_arsive_blocked_ile_gider_ve_kimlik_doner(monkeypatch):
    """Yasak-alan turu `write_turn(..., blocked=<kategori>)` ile arşivlenir
    ve yanıt rezerve edilen konu kimliğini taşır (yetim konu olmasın)."""
    from services import chat_history

    cagri = []

    def sahte_write_turn(uid, prepared, user_text, ai_text, lang,
                         friend_uid=None, person_id=None, blocked=None):
        cagri.append((prepared.conversation_id, user_text, ai_text, blocked))

    monkeypatch.setattr(chat_history, "write_turn", sahte_write_turn)
    monkeypatch.setattr(
        chat_history, "prepare",
        lambda uid, requested_id: chat_history.PreparedConversation(
            "c1", True, None, 0))
    with TestClient(app) as client:
        r = client.post("/api/v1/chat",
                        json={"history": [], "message":
                              "Should I buy bitcoin now?"})
        assert r.status_code == 200
        govde = r.json()
        assert govde["blocked"] == "finans"
        assert govde["conversation_id"] == "c1"
    assert cagri == [("c1", "Should I buy bitcoin now?", govde["reply"],
                      "finans")]


def test_uc_kriz_turu_arsive_gitmez_ve_kimlik_donmez(monkeypatch):
    """Kriz metni kullanıcının geçmişinde durmaz; yazılmamış kimlik de
    istemciye verilmez."""
    from services import chat_history

    cagri = []
    monkeypatch.setattr(chat_history, "write_turn",
                        lambda *a, **k: cagri.append((a, k)))
    monkeypatch.setattr(
        chat_history, "prepare",
        lambda uid, requested_id: chat_history.PreparedConversation(
            "c1", True, None, 0))
    with TestClient(app) as client:
        r = client.post("/api/v1/chat",
                        json={"history": [], "message":
                              "artık yaşamak istemiyorum"})
        assert r.status_code == 200
        govde = r.json()
        assert govde["blocked"] == "crisis"
        assert "conversation_id" not in govde
    assert not cagri

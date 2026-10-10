"""Yasak alan kapısı testleri.

En kritik kısım yanlış pozitifler: duygu paylaşan kullanıcıyı duvara
çarptırmak, yasak soruyu cevaplamaktan daha büyük bir hata olur.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_safety_rules.py -q
"""
import pytest
from fastapi.testclient import TestClient

from core import entitlements
from services import gemini_service
from services.safety_rules import _RULES, forbidden_topic

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulaması içe aktarılamadı: {_APP_IMPORT_ERROR}",
)


# --------------------------------------------------------------------------
# Yakalanması GEREKENLER
# --------------------------------------------------------------------------

@pytest.mark.parametrize("mesaj,beklenen", [
    ("Kanserim geçecek mi?", "saglik"),
    ("Bu ilacı bırakmalı mıyım", "saglik"),
    ("ameliyatım iyi geçecek mi", "saglik"),
    ("Hamile kalır mıyım?", "hamilelik"),
    ("çocuğum olacak mı", "hamilelik"),
    ("Ne zaman öleceğim", "olum"),
    ("kaç yıl yaşarım", "olum"),
    ("Bu hisseyi alsam mı?", "finans"),
    ("bitcoin yükselecek mi", "finans"),
    ("altın alır mıyım şimdi", "finans"),
])
def test_ongoru_talepleri_yakalanir(mesaj, beklenen):
    sonuc = forbidden_topic(mesaj)
    assert sonuc is not None, f"yakalanmali: {mesaj}"
    assert sonuc[0] == beklenen


# --------------------------------------------------------------------------
# Yakalanmaması GEREKENLER (yanlış pozitif)
# --------------------------------------------------------------------------

@pytest.mark.parametrize("mesaj", [
    # Duygu paylaşımı — teselli arayan kullanıcı engellenmemeli
    "Annem hasta, çok üzgünüm bugün",
    "Babam kanserden vefat etti, zor bir dönem",
    "Depresyondayım ve kimseyle konuşamıyorum",
    "Bugün çok yorgunum, içim daralıyor",
    # Kendine yatırım — finans değil
    "Kendime yatırım yapmalı mıyım bu dönemde",
    "İşimde yükselmek için ne yapmalıyım",
    # Genel sorular
    "Merkür retrosu ilişkimi nasıl etkiler",
    "Yükselen burcum ne anlama geliyor",
    "Bu hafta aşk hayatımda ne var",
    "Ay evresi bugün neyi tetikliyor",
])
def test_normal_mesajlar_engellenmez(mesaj):
    assert forbidden_topic(mesaj) is None, f"engellenmemeli: {mesaj}"


def test_bos_mesaj():
    assert forbidden_topic("") is None


# --------------------------------------------------------------------------
# İngilizce kapı
#
# Kalıplar yalnızca Türkçe olduğu sürece uygulamayı İngilizce kullanan biri
# için kapı hiç yoktu: "will my cancer get better?" doğrudan modele gidiyordu.
# Dahi kötüsü, dili değiştirmek kapıyı aşmanın yolu oluyordu.
# --------------------------------------------------------------------------

@pytest.mark.parametrize("mesaj,beklenen", [
    ("Will my cancer get better?", "saglik"),
    ("Should I stop taking this medication?", "saglik"),
    ("Will my surgery go well", "saglik"),
    ("Will I get pregnant this year?", "hamilelik"),
    ("Am I going to conceive soon", "hamilelik"),
    ("When will I die", "olum"),
    ("How long do I have to live", "olum"),
    ("Should I buy this stock?", "finans"),
    ("Will bitcoin go up", "finans"),
    ("Is it a good time to buy gold", "finans"),
])
def test_ingilizce_ongoru_talepleri_yakalanir(mesaj, beklenen):
    sonuc = forbidden_topic(mesaj, lang="en")
    assert sonuc is not None, f"yakalanmali: {mesaj}"
    assert sonuc[0] == beklenen


@pytest.mark.parametrize("mesaj", [
    # Duygu paylaşımı — talep işareti yok
    "My mother is sick and I feel awful today",
    "I lost my father to cancer last year",
    "I have been depressed and cannot talk to anyone",
    # Aşırı geniş kalıpların yakalayacağı masum sorular
    "Will things get better for me?",
    "Should I invest more time in this relationship?",
    "Will he share his feelings with me",
    # Genel sorular
    "What does Mercury retrograde mean for my relationship",
    "Will this week be good for love",
    "How does the moon phase affect me today",
])
def test_ingilizce_normal_mesajlar_engellenmez(mesaj):
    assert forbidden_topic(mesaj, lang="en") is None, f"engellenmemeli: {mesaj}"


def test_dil_degistirerek_kapi_asilamaz():
    """Kapı mesajı TÜM dillerin kalıplarına karşı sınar.

    Arayüz dili Türkçeyken İngilizce yazmak (ya da tersi) engeli aşmamalı;
    yalnızca dönen yanıtın dili kullanıcının diline göre değişir.
    """
    tr_arayuz = forbidden_topic("Will my cancer get better?", lang="tr")
    assert tr_arayuz is not None
    assert tr_arayuz[0] == "saglik"
    assert "hekim" in tr_arayuz[1].lower(), "yanıt kullanıcının dilinde olmalı"

    en_arayuz = forbidden_topic("Kanserim geçecek mi?", lang="en")
    assert en_arayuz is not None
    assert en_arayuz[0] == "saglik"
    assert "doctor" in en_arayuz[1].lower(), "yanıt kullanıcının dilinde olmalı"


def test_desteklenmeyen_dil_varsayilana_duser():
    sonuc = forbidden_topic("Kanserim geçecek mi?", lang="de")
    assert sonuc is not None
    assert "hekim" in sonuc[1].lower()


@pytest.mark.parametrize("mesaj", [
    "İlacı bırakmalı mıyım",
    "İYİLEŞECEK MİYİM ACABA HASTALIĞIM",
    "Hisse alır mıyım",
])
def test_buyuk_harf_ve_noktali_i_ile_de_yakalanir(mesaj):
    """Python'da "İ".lower() birleşen noktalı bir i üretir; normalizasyon bunu
    hesaba katmazsa büyük harfle yazan kullanıcı kapıdan sızar."""
    assert forbidden_topic(mesaj) is not None, f"yakalanmali: {mesaj}"


# --------------------------------------------------------------------------
# Uç davranışı
# --------------------------------------------------------------------------

@uygulama_gerekir
def test_yasak_soru_llm_e_gitmez(monkeypatch):
    """Kapı LLM'den önce durmalı: model çağrılmamalı."""
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: False)
    monkeypatch.setattr(gemini_service, "chat",
                        lambda h, m: pytest.fail("yasak soruda LLM çağrılmamalı"))

    with TestClient(app) as client:
        response = client.post("/api/v1/chat",
                               json={"message": "Hamile kalır mıyım?"},
                               headers={"Authorization": "Bearer test-yasak"})

    assert response.status_code == 200
    govde = response.json()
    assert govde["blocked"] == "hamilelik"
    assert "hekim" in govde["reply"].lower()


@uygulama_gerekir
def test_yasak_soru_gunluk_kotayi_yemez(monkeypatch):
    """Reddedilen soru kullanıcının ücretsiz hakkından düşmemeli."""
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: False)
    monkeypatch.setattr(entitlements, "consume_quota",
                        lambda *a: pytest.fail("yasak soruda kota düşülmemeli"))

    with TestClient(app) as client:
        response = client.post("/api/v1/chat",
                               json={"message": "Bu hisseyi alsam mı?"},
                               headers={"Authorization": "Bearer test-kota2"})

    assert response.status_code == 200
    assert response.json()["blocked"] == "finans"


# --------------------------------------------------------------------------
# Persona talimatı — dürüstlük kuralları yerinde mi
# --------------------------------------------------------------------------

def test_persona_pohpohlamayi_yasaklar():
    """Eski talimat 'her zorluğu umut veren dille anlat' diyordu; bu, ürünün
    'yağcılık yok' ilkesiyle çelişiyordu."""
    for talimat in (gemini_service.SYSTEM_INSTRUCTION,
                    gemini_service.CHAT_SYSTEM_INSTRUCTION):
        metin = talimat.upper()
        assert "POHPOHLAMA YOK" in metin
        assert "umut veren bir dille anlat" not in talimat


def test_persona_yasak_alanlari_sayar():
    # Not: Python'da "İ".lower() iki kodpuanlı "i + U+0307" üretir, bu yüzden
    # içinde İ geçen kelimelerle (TARİHLİ, KESİN) küçük harf karşılaştırması
    # yapılmıyor; İ içermeyen ayırt edici kelimeler kullanılıyor.
    for talimat in (gemini_service.SYSTEM_INSTRUCTION,
                    gemini_service.CHAT_SYSTEM_INSTRUCTION):
        alt = talimat.lower()
        assert "hamile" in alt
        assert "ölüm" in alt
        assert "hukuki" in alt
        assert "kehanet" in alt
        assert "pencere" in alt, "tarih yerine 'pencere' dili önerilmeli"


def test_persona_yuz_okumayi_iddia_etmez():
    """Yüz okuma v1 kapsamı dışında; olmayan bir yeteneği vaat etmemeli."""
    assert "yüz okuma" not in gemini_service.CHAT_SYSTEM_INSTRUCTION.lower()


# --------------------------------------------------------------------------
# K-turu: alt dize → kelime sınırı
#
# Kapı bir tur boyunca ALT DİZEYLE çalıştı ve bedeli ölçüldü (2026-10-10):
# "hisse" "hissediyorum"u, "altin" "altında"yı, "olurum" "mutlu olurum"u,
# "\bsick\b" "sick of my job"u yakaladı. Dördü de sıradan cümle, dördü de
# kullanıcıya sorulmamış bir çekince döndürdü — sahibin "alakasız yere
# maddi konularda tavsiye veremem diyor" şikâyeti buydu. Engellenen tur
# arşive yazılmadığı için korpusta kayıt SIFIRDI; kusur ekranda görüldü.
# --------------------------------------------------------------------------

@pytest.mark.parametrize("mesaj", [
    "Bugün çok kötü hissediyorum, geçecek mi?",
    "Bu transitin altında ne zaman rahatlarım?",
    "Sunumu yetiştirirsem mutlu olurum, ne yapmalıyım?",
    "Akşam sunum var yetiştiremiyorum ne yapmalıyım",
    "İş yerinde altın gibi bir fırsat var, kabul etsem mi?",
    "Böyle devam ederse ne yaşarım bilmiyorum",
    "I'm sick of my job, will it change?",
    # altın/gold bir ARAÇ değil, önce bir kelime — takı finans değil.
    "Will my gold earrings bring luck?",
    "Kendimi çok yalnız hissediyorum",
    # Soru eki sınırsızken "kendi**mi**" talep sayılıyordu; bu bir duygu
    # paylaşımı, "hasta" geçse de engellenmemeli.
    "Kendimi hasta hissediyorum",
    # 3. kişi/duygu cümlesi: "hastane" bilerek kalıpta yok.
    "Hastaneye gittim annem iyi mi olacak",
    # Katlama çakışması: "olur muyum" ≠ "ölür müyüm".
    "Zengin olur muyum?",
    # "ömrümün aşkı" bir ömür sorusu değil.
    "Ömrümün aşkını ne zaman bulacağım",
    # Deyimler.
    "Kısır döngüden ne zaman çıkarım",
    "Bebeğim beni seviyor mu",
    "Yastığın altına koysam mı",
    # Yas: "vefat etti" geçmiş, kehanet değil.
    "Babam vefat etti, ne zaman toparlanırım",
    # "olumlu" ≠ "ölüm".
    "Olumlu bir dönem mi olacak",
])
def test_kelime_sinirina_bagli_yanlis_pozitifler_gecer(mesaj):
    assert forbidden_topic(mesaj) is None, f"engellenmemeli: {mesaj}"


@pytest.mark.parametrize("mesaj,beklenen", [
    ("Hisselerimi satsam mı?", "finans"),
    ("Eurolarımı satsam mı", "finans"),
    ("Fonlarımı bozdursam mı", "finans"),
    ("Altın fiyatı yükselecek mi", "finans"),
    ("Altınlarımı satsam mı", "finans"),
    ("Dolar yükselecek mi?", "finans"),
    ("Should I buy bitcoin now?", "finans"),
    ("Kanserim geçecek mi?", "saglik"),
    ("Ne zaman öleceğim?", "olum"),
    ("Kaç yıl ömrüm kaldı", "olum"),
    # Aksanlı kalıp: katlanmış metinde "olur muyum" ile çakışırdı.
    ("Kazada ölür müyüm?", "olum"),
    ("Bebeğim olacak mı", "hamilelik"),
])
def test_kelime_sinirina_ragmen_dogru_pozitifler_kalir(mesaj, beklenen):
    """Kalıplar daraltılırken gerçek sorular kaçmamalı — sınır iki yöne
    de çalışır."""
    sonuc = forbidden_topic(mesaj)
    assert sonuc is not None, f"yakalanmali: {mesaj}"
    assert sonuc[0] == beklenen


#: Konu kalıplarının HİÇBİRİNİN eşleşmemesi gereken tuzak kelimeler —
#: normalize edilmiş (ASCII, küçük harf) biçimleriyle. Her kalıp ayrı ayrı
#: derlenip sınanır: bir kural ileride yeniden genişlerse bekçi hangi
#: kuralın geriye gittiğini adıyla söyler.
_TUZAK_KELIMELER = [
    "hissediyorum",
    "altinda",
    "altina",
    "mutlu olurum",
    "ne yasarim",
    "sick of my job",
    "olumlu",
    "hastaneye",
    "kisir dongu",
    "i'm a cancer",
    "my cancer moon",
    "ill be fine",
    "silent treatment",
    "dying to know",
    "scared to death",
    "gold earrings",
    "a few dollars left",
    "update my portfolio",
    "fund my project",
    "stock up",
]


@pytest.mark.parametrize("tuzak", _TUZAK_KELIMELER)
def test_kaliplar_tuzak_kelimelere_takilmaz(tuzak):
    """Alt dize regresyon bekçisi: konu kalıpları doğrudan derlenmiş hâliyle
    sınanır (talep işareti olmadan), yani `forbidden_topic`in darlığı bu
    testi KURTARAMAZ — kalıbın kendisi temiz olmalı."""
    for rule in _RULES:
        for dil, kalip in rule.konu.items():
            assert kalip.search(tuzak) is None, (
                f"{rule.kategori}/{dil} kalıbı '{tuzak}' üzerinde eşleşti")


def test_burc_olarak_cancer_saglik_degil():
    """Bu bir astroloji uygulaması: "Cancer" önce bir burç. Hastalık yalnız
    bağlamıyla ("my cancer", "have cancer", "breast cancer")."""
    assert forbidden_topic("I'm a Cancer, will this week be good for me?",
                           lang="en") is None
    assert forbidden_topic("Will my Cancer moon make me too emotional?",
                           lang="en") is None
    sonuc = forbidden_topic("Will my cancer get better?", lang="en")
    assert sonuc is not None and sonuc[0] == "saglik"


def test_soru_eki_kelime_basina_bagli():
    """`_SORU_TR` başında `\\b` yoksa "kendimi/ismi/resmi" talep sayılır."""
    from services.safety_rules import _TALEP
    for kelime in ("kendimi", "ismi", "resmi", "elimi"):
        assert _TALEP["tr"].search(kelime) is None, kelime
    assert _TALEP["tr"].search("gececek mi") is not None
    assert _TALEP["tr"].search("birakmali miyim") is not None


# --------------------------------------------------------------------------
# Ret metni: sıcak bir sınır beyanı, "tavsiye veremem" refleksi değil
# --------------------------------------------------------------------------

@pytest.mark.parametrize("rule", _RULES, ids=lambda r: r.kategori)
def test_ret_metni_sinir_beyani_ve_haritaya_kopru(rule):
    """Her kategori, iki dilde: yetkin olduğu alanı söyler ("benim alanım"
    / "my ground"), haritaya köprü kurar ("istersen" / "if you'd like") ve
    "veremem/can't give" refleksi taşımaz. Lifestyle ürünü: Rytho bilge
    bir dost, bir uyarı levhası değil."""
    # `str.lower()` Türkçe bilmez: "İstersen".lower() "i" + U+0307 verir ve
    # "istersen" alt dizesi bulunmaz (CLAUDE.md §5). İ elle katlanır.
    tr = rule.yanit["tr"].replace("İ", "i").replace("I", "ı").lower()
    en = rule.yanit["en"].lower()
    assert "benim alanım" in tr, rule.kategori
    assert "istersen" in tr, rule.kategori
    assert "my ground" in en, rule.kategori
    assert "if you'd like" in en, rule.kategori
    for yasak in ("veremem", "tavsiye", "yapamam"):
        assert yasak not in tr, f"{rule.kategori}: '{yasak}' refleksi"
    for yasak in ("can't give", "cannot give", "can't advise", "advice"):
        assert yasak not in en, f"{rule.kategori}: '{yasak}' refleksi"

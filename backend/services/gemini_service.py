"""Gemini LLM istemcisi — Cosmic Confidant personası.

Tüm LLM çağrıları bu modülden geçer. RAG bağlamı ve yapılandırılmış hesaplama
verileri report_service tarafından prompt'a gömülür; burası yalnızca model
iletişimi ve persona yönetiminden sorumludur.
"""
from __future__ import annotations

import logging
import time

from core import config, i18n
from services import prompts, usage_service

logger = logging.getLogger(__name__)

_client = None
_client_kuruldu = False


def _get_client():
    """İstemciyi ilk ihtiyaç anında kurar.

    `from google import genai` açılıştaki **en pahalı tek kalem**: ölçümde
    624 ms, `import main`'in toplam 1,6 saniyesinin üçte biri. Modül düzeyinde
    yapılınca her soğuk başlatma bunu ödüyordu ve Cloud Run'da soğuk başlatma
    kullanıcının gördüğü "bekliyor bekliyor" hâlinin ta kendisi.

    Sonuç önbelleklenir — başarısızlık da. Anahtar yoksa ya da istemci
    kurulamıyorsa her çağrıda yeniden denemek anlamsız.

    Bedeli ilk isteğin ödememesi için `warm_up()` açılışta arka planda çağrılır.
    """
    global _client, _client_kuruldu
    if _client_kuruldu:
        return _client
    _client_kuruldu = True
    if not config.GEMINI_API_KEY:
        return None
    try:
        from google import genai

        _client = genai.Client(api_key=config.GEMINI_API_KEY)
    except Exception as exc:  # pragma: no cover
        logger.warning("GenAI istemcisi başlatılamadı: %s", exc)
    return _client


def warm_up() -> None:
    """İstemciyi arka planda hazırlar — açılışta çağrılır, açılışı bekletmez."""
    import threading

    threading.Thread(target=_get_client, daemon=True, name="genai-warmup").start()

#: Geriye dönük uyum ve varsayılan dil için. Diller `services/prompts`
#: altında; persona metinleri artık orada tutuluyor.
SYSTEM_INSTRUCTION = prompts.get(i18n.DEFAULT).SYSTEM_INSTRUCTION
CHAT_SYSTEM_INSTRUCTION = prompts.get(i18n.DEFAULT).CHAT_SYSTEM_INSTRUCTION

# Görünür yanıt için gereken bütçe DEĞİL — bu, düşünme dahil TOPLAM çıktı
# tavanı. Ayrım S-turu'nda pahalıya öğrenildi (aşağıdaki gerekçeye bakın).
#
# Ölçüm: tipik 4 cümlelik Türkçe yanıt ~85 token (3,6 karakter/token), 6
# cümlelik ~146. Yani görünür metin için 300 fazlasıyla yeterliydi; sorun
# görünür metinde değil, ONUNLA AYNI BÜTÇEDEN yiyen düşünmedeydi.
#
# ## 1200 → 600 (48-turu) ve tavanın NE OLMADIĞI
#
# Tavan bir HEDEF değil, kesilme kalkanıdır: modeli uzun yazdıran şey tavan
# değil prompt'tur ve uzunluk kuralı bu turda prompt'ta bağlayıcı hâle
# getirildi (`prompts/tr.py`, TEK KONU + konuya göre üst sınır). Yani 1200'ü
# düşürmek uzunluk sorununu ÇÖZMEZ; yalnız artık gereksiz kalan payı geri
# alır.
#
# 1200'ün gerekçesi, yazıldığı gün doğruydu ama BUGÜN GEÇERSİZ: o gün model
# `gemini-flash-latest` takma adıydı ve `thinking_budget: 0` uygulanmıyordu
# (6 çağrının 3'ünde 190-286 token düşünmeye gidiyordu), tavan da onun için
# yükseltilmişti. Model o turda sabitlendi — `core/config.py`'deki ölçüm:
# `gemini-3.5-flash` 4 çağrının **0'ında** kesildi ve **0 token** düşündü.
# Düşünme sızıntısı modelin PİNİYLE kapandı; tavanla değil.
#
# 600 şu iki ölçümden çıkarıldı (ikisi de bu depoda yazılı):
#   * Üst sınır artık 8 cümle (prompt). 4 cümle ~85, 6 cümle ~146 token →
#     cümle başına ~24; 8 cümle ~195. Görünür metin için 600, en uzun
#     yanıtın 3 katı.
#   * `GEMINI_MODEL` ortam değişkeniyle düşünme sızdıran bir modele
#     dönülürse: ölçülen en kötü sızıntı 286 token; 286 + 195 = 481 < 600.
#     Yani 600, pin kaybolsa bile kesmez. Bu yüzden 400 DEĞİL: 400'de o
#     ikinci özellik kaybolurdu ve sızıntı sessizce kesilmeye dönerdi.
# Üçüncü savunma yerinde duruyor: tavan yine tutmazsa `finish_reason`
# denetimi kesik metni kullanıcıya göstermez, sıradaki varyant (2048,
# düşünme tamamen açık) devreye girer.
CHAT_MAX_OUTPUT_TOKENS = 600
CHAT_TEMPERATURE = 0.85

# Düşünme (thinking) kapatma varyantları, tercih sırasıyla.
#
# ## Neden bu liste değişti (S-turu)
#
# Cihaz bulgusu: "sohbet bazen yarıda kesiliyor, başlamadan bitebiliyor."
# Aynı soru üretimdeki ayarla 6 kez soruldu — **3'ü kesildi**. Kesilenlerde
# düşünme 300 token'ın 284'ünü yiyip geriye 10-12 token bırakıyordu ve
# cümle kelime ortasında bitiyordu ("Gökyüzünde bugün zih").
#
# Kök neden: `gemini-flash-latest` bir TAKMA AD ve arkasındaki model kaydı.
# O takma ad üzerinde ölçülen davranış:
#   * `thinking_level: "minimal"` → 400 INVALID_ARGUMENT (desteklenmiyor).
#     Yani bu varyant her soğuk başlangıçta bir çağrıyı boşa harcıyordu.
#   * `thinking_budget: 0` → kabul ediliyor ama UYGULANMIYOR; 6 çağrının
#     3'ünde ~190-286 token düşünmeye gitti.
#
# Bu yüzden: 400 veren varyant KALDIRILDI ve tavan, düşünme kontrolü yine
# kayarsa bile görünür metnin sığacağı kadar yükseltildi.
#
# ⚠️ YUKARIDAKİ İKİ MADDE ARTIK BU KURULUMUN TEŞHİSİ DEĞİL (düzeltildi,
# 48-turu). Tarihçe olarak duruyor çünkü varyant listesinin şeklini o
# ölçüm belirledi — ama sebebini açıkladığı model artık kullanılmıyor:
# `core/config.py` modeli `gemini-3.5-flash`'a SABİTLEDİ ve orada ölçülen
# davranış bunun TERSİ — 4 çağrının 0'ı kesildi, 0 token düşünme, yani
# `thinking_budget: 0` uygulanıyor. Takma ad gerekçesini bugünün gerekçesi
# sanmak yanlış olur: düşünme sızıntısını kapatan şey bu dosyadaki tavan
# değil, o dosyadaki MODEL PİNİ'dir.
#
# Liste yine iki katmanlı duruyor, ama görevi değişti: artık "takma ad
# kayarsa" değil, "`GEMINI_MODEL` ile pin DIŞINA çıkılırsa" savunması.
# Üçüncü katman her hâlde yerinde: `finish_reason` denetimi kesik metnin
# kullanıcıya ulaşmasını engeller.
_CHAT_CONFIG_VARIANTS: tuple[dict, ...] = (
    {"thinking_config": {"thinking_budget": 0},
     "max_output_tokens": CHAT_MAX_OUTPUT_TOKENS},
    # Düşünme hiç kapatılamıyorsa: bütçeyi iyice aç. Ölçümde en pahalı
    # model 499 token düşünüp 102 token yazdı; 2048 ikisine de yeter.
    {"max_output_tokens": 2048},
)

#: Çalıştığı bilinen varyant hatırlanır; her istekte baştan denenmez.
#:
#: Eskiden bu bir modül global'iydi ve `range(_preferred_variant, ...)` ile
#: yalnız İLERİ gidiyordu: bir kez 1'e kayınca 0'a bir daha dönmüyordu.
#: Sözlük hem geri dönüşe açık hem de niyeti okunur kılıyor.
_variant_state: dict[str, int] = {"preferred": 0}


def is_available() -> bool:
    return _get_client() is not None


def _read_response(response) -> tuple[str, bool]:
    """Yanıttan (metin, kesildi_mi) çıkarır.

    ## Neden ayrı bir okuyucu var

    `response.text` kesilmiş bir yanıtta da metin döndürür — hem de hata
    vermeden. S-turu'nda ölçüldü: `finish_reason=MAX_TOKENS` iken elde
    kalan 10-12 token kullanıcıya TAM YANIT olarak gösteriliyordu ve
    cümle kelime ortasında bitiyordu. Kesilmeyi görmenin tek yolu
    `finish_reason`'a bakmak; metnin kendisi bunu söylemiyor.

    `response.text` erişimi parça yokken istisna da atabilir (SDK sürümüne
    göre); bu yüzden sarmalanıyor — sohbet bir okuma hatası yüzünden
    düşmemeli.
    """
    kesildi = False
    try:
        aday = (response.candidates or [None])[0]
        sebep = str(getattr(aday, "finish_reason", "") or "")
        kesildi = sebep.endswith("MAX_TOKENS")
    except Exception:
        pass

    try:
        metin = (response.text or "").strip()
    except Exception as exc:
        logger.info("Yanıt metni okunamadı: %s", exc)
        metin = ""
    return metin, kesildi


#: Kesilen bir raporun yeniden denendiği bütçe. Natal rapor 400-500 kelime
#: (~900 çıktı token'ı) ve üstüne düşünme biniyor; 8192 ikisine de rahat
#: yeter ve yalnızca kesilme görüldüğünde kullanılır.
_REPORT_RETRY_TOKENS = 8192


def generate(prompt: str, temperature: float = 0.9,
             lang: str | None = None, *,
             feature: str | None = None, uid: str | None = None) -> str | None:
    """Tek atımlık üretim. Başarısız olursa None döner (çağıran fallback verir).

    Persona dile göre seçilir: İngilizce yorum Türkçe persona ile üretilirse
    ton ve dil karışır.

    **Kesilme burada da denetlenir (S-turu).** Bu yol raporları üretiyor ve
    raporun bedeli 5 jeton: yarım kalmış bir metni "rapor" diye teslim
    etmek hem kalitesiz hem de karşılığı alınmamış bir ücret olur.
    Kesilme görülürse bir kez geniş bütçeyle denenir; yine keserse None
    döner ve çağıran (`_cached_generate`) jetonu İADE eder.
    """
    client = _get_client()
    if client is None:
        return None

    temel = {
        "system_instruction": prompts.get(lang).SYSTEM_INSTRUCTION,
        "temperature": temperature,
        # KA3: düşünme burada da kapatılır — S-turu'nda sohbet için
        # ölçülen ders (düşünme bütçeyi yiyip metni kesiyordu) bu yola
        # yarım uygulanmıştı: `chat()` kapatıyor, `generate()` kapatmıyordu.
        # Ayar yine yok sayılırsa ilk denemenin 2048'lik tavanı görünür
        # metne yeter; o da kesilirse geniş bütçeli deneme devreye girer.
        "thinking_config": {"thinking_budget": 0},
    }
    for deneme, ek in enumerate(({"max_output_tokens": 2048},
                                 {"max_output_tokens": _REPORT_RETRY_TOKENS})):
        try:
            basla = time.monotonic()
            response = client.models.generate_content(
                model=config.GEMINI_MODEL, contents=prompt,
                config={**temel, **ek},
            )
            # Her GERÇEK çağrı ayrı kayıt — kesilme retry'ı da faturalanır.
            usage_service.record(feature or "generate", config.GEMINI_MODEL,
                                 response,
                                 int((time.monotonic() - basla) * 1000),
                                 uid=uid)
            metin, kesildi = _read_response(response)
            if metin and not kesildi:
                return metin
            if kesildi:
                logger.warning(
                    "Üretim KESİLDİ (MAX_TOKENS, %d karakter, deneme %d, "
                    "model=%s)", len(metin), deneme, config.GEMINI_MODEL)
                continue
            logger.info("Üretim boş metin döndürdü (deneme %d)", deneme)
            return None
        except Exception as exc:
            # Kota (429) ile agir hatayi ayirmak icin yigin izi de gerekli:
            # yedek metin artik istemcide HATA ya da "yorum uretilemedi"
            # (gz-2), yani bu satir "kullanici urunu goremedi" anlamina
            # geliyor.
            logger.exception("Gemini üretim hatası: %s", exc)
            return None
    return None


def extract_json(prompt: str, schema: dict | None = None, *,
                 feature: str | None = None, uid: str | None = None) -> str | None:
    """Persona'sız, düşük sıcaklıkta yapılandırılmış üretim.

    Olgu çıkarımı gibi işler için: Rytho personası (sıcak, edebi, "sen" dili)
    burada zararlıdır — istenen şey yorum değil, veri. Bu yüzden
    ``SYSTEM_INSTRUCTION`` uygulanmaz ve sıcaklık düşük tutulur.
    """
    client = _get_client()
    if client is None:
        return None
    try:
        cfg: dict = {"temperature": 0.1, "response_mime_type": "application/json"}
        if schema is not None:
            cfg["response_schema"] = schema
        basla = time.monotonic()
        response = client.models.generate_content(
            model=config.GEMINI_MODEL, contents=prompt, config=cfg
        )
        usage_service.record(feature or "extract_json", config.GEMINI_MODEL,
                             response,
                             int((time.monotonic() - basla) * 1000), uid=uid)
        if response and response.text:
            return response.text.strip()
    except Exception as exc:
        logger.warning("Yapılandırılmış üretim hatası: %s", exc)
    return None


def chat(history: list[dict], user_message: str,
         lang: str | None = None, *,
         feature: str = "chat", uid: str | None = None) -> str | None:
    """Çok turlu sohbet. history: [{'sender': 'USER'|'AI', 'text': ...}]

    Persona kuralları her turda mesaja gömülmez; system_instruction olarak
    tek yerden verilir.

    Sıradaki varyanta ÜÇ durumda geçilir:
      1. istisna (ör. ayar bu modelde desteklenmiyor → 400),
      2. boş metin (bütçenin tamamı düşünmeye gitmiş),
      3. **kesilmiş metin** (`finish_reason=MAX_TOKENS`) — S-turu'nda
         eklendi. Eskiden kesik metin başarı sayılıp kullanıcıya
         gösteriliyordu; cihazda "yarıda kesiliyor" diye görüldü.

    Hiçbir varyant tam bir yanıt üretemezse **kesik metin dönmez**: None
    döner ve çağıran dürüst bir mesaj gösterir. Yarım cümle göstermek,
    "şu an yanıt üretemedim" demekten daha kötü bir deneyim.
    """
    client = _get_client()
    if client is None:
        return None

    contents = []
    for msg in history[-20:]:
        role = "user" if msg.get("sender") == "USER" else "model"
        # SS-turu: `contents` "model" rolüyle BAŞLAYAMAZ. Rytho'nun ilk
        # sözüyle açılan konuşmalarda (akşam check-in'i) geçmişin ilk —
        # bazen tek — kalemi asistan mesajıdır. Baştaki asistan kalemleri
        # atlanır; soru zaten prompt'a WHISPER_SEED_* ile giriyor, yani
        # bağlam kaybolmuyor. Koruma ucuz, alternatifi pahalı: geçersiz
        # istek üç yapılandırma varyantını da yakar, `chat` None döner ve
        # kullanıcının jetonu iade edilir.
        if not contents and role != "user":
            continue
        contents.append({"role": role, "parts": [{"text": msg.get("text", "")}]})
    contents.append({"role": "user", "parts": [{"text": user_message}]})

    baslangic = _variant_state["preferred"]
    # Tercih edilen varyanttan başla, sonra baştakileri de dene: tercih
    # geçici bir aksaklıkla kaymışsa geri dönebilmeli.
    sira = list(range(baslangic, len(_CHAT_CONFIG_VARIANTS))) + \
        list(range(0, baslangic))

    for idx in sira:
        cfg = {
            "system_instruction": prompts.get(lang).CHAT_SYSTEM_INSTRUCTION,
            "temperature": CHAT_TEMPERATURE,
            **_CHAT_CONFIG_VARIANTS[idx],
        }
        try:
            basla = time.monotonic()
            response = client.models.generate_content(
                model=config.GEMINI_MODEL, contents=contents, config=cfg,
            )
            # İstisnayla düşen varyantta response yok → kayıt da yok
            # (faturalanmadı sayılır); dönen her yanıt ise paradır.
            usage_service.record(feature, config.GEMINI_MODEL, response,
                                 int((time.monotonic() - basla) * 1000),
                                 uid=uid)
            metin, kesildi = _read_response(response)
            if metin and not kesildi:
                _variant_state["preferred"] = idx
                return metin
            if kesildi:
                # Sessiz kalmamalı: bu, bir ayarın artık tutmadığının
                # ilk işareti ve tek görünür yeri burası.
                logger.warning(
                    "Sohbet varyantı %d KESİLDİ (MAX_TOKENS, %d karakter); "
                    "model=%s — sıradaki denenecek",
                    idx, len(metin), config.GEMINI_MODEL)
            else:
                logger.info("Sohbet varyantı %d boş metin döndürdü, "
                            "sıradaki denenecek", idx)
        except Exception as exc:
            logger.info("Sohbet varyantı %d başarısız (%s), sıradaki denenecek",
                        idx, exc)
    logger.warning("Tüm sohbet yapılandırma varyantları başarısız oldu "
                   "(model=%s)", config.GEMINI_MODEL)
    return None


# `moderate()` KALDIRILDI (Revize R0): tek çağıranı, hiçbir istemcinin
# kullanmadığı kotasız `/chat/moderate` ucuydu — ayrıntı api/chat.py'de.

"""Sohbetten şemalı olgu çıkarımı — uygulamanın kullanıcıyı tanıma mekanizması.

Konuşmadan yalnızca `memory_service.CATEGORIES` içindeki kapalı kümeye
oturan kısa olgular damıtılır; prompt'a enjekte edilecek bağlam böylece
öngörülebilir boyutta kalır.

NOT (Revize R4): Bu dosyanın eski "Ham sohbet metni SAKLANMAZ" duruşu ürün
kararıyla revize edildi — konuşmalar artık konu bazlı arşivleniyor
(`chat_history.py`, 30 gün kullanılmayan silinir, gizlilik politikası
güncellendi). Bu çıkarıcı DEĞİŞMEDİ ve arşivin yerini tutmaz: arşiv
"kaldığın yerden devam", buradaki olgular "seni tanıyorum" — iki ayrı iş.

**Maliyet kontrolü:** çıkarım kullanıcı başına ek bir LLM çağrısıdır. Her
mesajda çalıştırılırsa sohbetin maliyeti ikiye katlanır. Bu yüzden iki şart
birlikte aranır: konuşmanın anlamlı bir uzunluğa gelmesi ve o gün daha önce
çıkarım yapılmamış olması. Böylece aktif kullanıcı başına günde en fazla bir
ek çağrı olur.
"""
from __future__ import annotations

import json
import logging
from typing import Any

from core import entitlements
from services import gemini_service, memory_service

logger = logging.getLogger(__name__)

#: Çıkarımın tetiklenmesi için konuşmada en az kaç kullanıcı mesajı olmalı.
#: Kısa "merhaba" turlarından olgu çıkarmaya çalışmak boşa çağrıdır.
#: 3 → 2 (KA9): eşik 3'ken her yeni konunun ilk İKİ mesajı hiç işlenmiyor
#: ve günde 1 kota ile çoğu kullanıcının hafızası boş kalıyordu — "beni
#: tanımıyor" şikâyetinin ölçülen parçalarından biri.
MIN_USER_TURNS = 2

#: Günlük çıkarım hakkı (kullanıcı başına). Kota altyapısı entitlements'ta.
DAILY_EXTRACTIONS = 1

#: Modelin döndürmesi gereken şema. response_schema ile zorlanır; yine de
#: dönen veri `memory_service` tarafından ayrıca doğrulanır — modele güvenip
#: şemasız yazmak, hafızayı serbest metin çöplüğüne çevirir.
_SCHEMA = {
    "type": "object",
    "properties": {
        "facts": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "category": {"type": "string", "enum": list(memory_service.CATEGORIES)},
                    "key": {"type": "string"},
                    "value": {"type": "string"},
                    "confidence": {"type": "number"},
                    # Konu = olgunun HAYAT ALANI, kategoriden ayrı. Çelişki
                    # tespiti bunun üzerinden çalışıyor: "ayrıldık" ile
                    # "sevgilisiyle sorun yaşıyor" aynı konuyu paylaşır ama
                    # kategorileri farklı. `required` DEĞİL ve olmamalı:
                    # model vermezse `memory_service._konu` anahtarın
                    # parçalarından çıkarır, çıkaramazsa konu None kalır ve
                    # o olgu kimseyi geçersiz kılmaz. Zorunlu kılmak modeli
                    # konu UYDURMAYA zorlardı ve yanlış konu, yanlış kaydı
                    # geçersiz kılmak demek.
                    "topic": {"type": "string",
                              "enum": list(memory_service.KONULAR)},
                },
                "required": ["category", "key", "value"],
            },
        },
        "mood": {"type": "string"},
        # Yoğunluk ve ihtiyaç (S-turu). Tek kelimelik ruh hali yetmiyordu:
        # "biraz kaygılıyım" ile "dağılmak üzereyim" aynı satıra düşüyor ve
        # model ikisine de aynı tonda cevap veriyordu.
        "intensity": {"type": "string", "enum": ["low", "medium", "high"]},
        # Kullanıcının o an ARADIĞI şey. Aynı soru farklı ihtiyaçla
        # sorulabilir: "ne yapmalıyım" bazen yön ister, bazen sadece
        # anlaşılmak.
        "needs": {"type": "string",
                  "enum": ["information", "direction", "understanding",
                           "rest"]},
    },
    "required": ["facts"],
}

_PROMPT = """\
GÖREV: Aşağıdaki konuşmadan kullanıcı hakkında KALICI olgular çıkar.

KURALLAR:
- Yalnızca kullanıcının KENDİSİ hakkında söylediği, ilerideki konuşmalarda
  işine yarayacak kalıcı bilgileri al.
- Geçici ayrıntıları ALMA (bugün yağmur yağmış, kahve içmiş gibi).
- Kullanıcının sorduğu soruları olgu sayma; yalnızca anlattıklarını.
- Astroloji verisi (burcu, yükseleni) ALMA — o zaten profilde var.
- Sağlık durumu, tanı veya ilaç bilgisi ALMA. Bu veriyi hiç tutmuyoruz.
- Her olgu en fazla bir cümle olsun.
- `key` sabit ve yeniden kullanılabilir bir anahtar olsun (ör. "work.transition",
  "relationship.status"); böylece aynı olgu sonradan güncellenebilir.
- MEVCUT ANAHTARLAR aşağıda verildiyse, aynı konudaki güncel bilgiyi YENİ bir
  anahtar uydurmak yerine o anahtara yaz. Yeni anahtar uydurmak eski kaydı
  silmez, YANINA koyar; iki çelişen kayıt birlikte yaşar.
- `topic`: olgunun hangi hayat alanıyla ilgili olduğu ({konular}). Emin
  değilsen boş bırak. Kategoriden ayrıdır: "sevgilimle kavga ettim" kategori
  olarak kaygıdır, konu olarak ilişkidir.
- `confidence`: bilginin DOĞRULUK derecesi — kullanıcı açıkça söylediyse 0.9,
  ima ettiyse 0.5. Önem ya da aciliyet DEĞİL: bir şeyin yüksek güvenle
  söylenmiş olması onu kalıcı kılmaz.
- Çıkarılacak kalıcı bir şey yoksa boş liste döndür. Uydurma.
- `mood`: kullanıcının bu konuşmadaki baskın ruh hali, tek kelime. Belirsizse
  boş bırak.
- `intensity`: o ruh halinin şiddeti — low (hafif değinmiş), medium (belirgin
  ve konuşmanın merkezinde), high (taşıyamadığını söylüyor). Ruh hali yoksa
  boş bırak. ABARTMA: sıradan bir yorgunluk "high" değildir.
- `needs`: kullanıcının bu turda ARADIĞI şey —
  information (bilgi/açıklama), direction (yön/karar desteği),
  understanding (anlaşılmak, dinlenmek), rest (yalnızca boşalmak, cevap
  beklemiyor). Emin değilsen boş bırak.

- `sensitivity` kategorisi: kullanıcı bir konunun konuşulmasını İSTEMEDİĞİNİ
  söylerse bunu kalıcı olarak kaydet ("babasından söz edilmesini istemiyor"
  gibi). Bu kategori bir yasak listesidir, merak listesi değil.

KATEGORİLER: {kategoriler}

MEVCUT ANAHTARLAR: {anahtarlar}

KONUŞMA:
{konusma}
"""


def _conversation_text(history: list[dict[str, Any]], last_message: str) -> str:
    parts = []
    for item in history[-12:]:
        who = "Kullanıcı" if str(item.get("sender", "")).upper() == "USER" else "Rytho"
        text = str(item.get("text", "")).strip()
        if text:
            parts.append(f"{who}: {text}")
    parts.append(f"Kullanıcı: {last_message.strip()}")
    return "\n".join(parts)


def _user_turns(history: list[dict[str, Any]]) -> int:
    return sum(1 for i in history if str(i.get("sender", "")).upper() == "USER")


def should_extract(history: list[dict[str, Any]]) -> bool:
    """Konuşma olgu çıkarımına değecek kadar ilerledi mi?"""
    return _user_turns(history) + 1 >= MIN_USER_TURNS


def extract_and_store(uid: str, history: list[dict[str, Any]],
                      last_message: str,
                      source: str | None = None,
                      seed_answer: bool = False) -> dict[str, Any] | None:
    """Konuşmadan olgu çıkarıp hafızaya yazar. Arka planda çağrılmak üzeredir.

    Hiçbir hata isteği etkilemez: çıkarım en iyi çaba (best effort) bir
    zenginleştirmedir, sohbetin çalışması ona bağlı değildir.

    ``source == "checkin"`` (KA9): akşam sorusuna verilen TEK mesajlık
    cevap da işlenir — tur eşiği atlanır ve kota +1 açılır. Aksi hâlde
    ürünün kendi sorduğu sorunun cevabı ("Bugün nasıl geçti?" → "Kötü,
    işten kötü haber aldım") hafızaya hiç düşmezdi; oysa bu, döngünün
    bütün amacı.

    ``seed_answer`` (SS-turu): aynı ayrıcalık, ama SUNUCUNUN kendi
    bilgisinden. `source` çıplak bir istemci beyanıdır (`ChatRequest`),
    yani herkes kota yükseltmesi isteyebilir; `seed_answer` ise konu
    dokümanında Rytho'nun cevaplanmamış sorusu DURDUĞU için doğrudur.
    Yeni istemci bu yolu kullanır; `source == "checkin"` geriye uyum
    için olduğu gibi kalır.
    """
    try:
        checkin = source == "checkin" or seed_answer
        if not checkin and not should_extract(history):
            return None

        # Günlük çıkarım kotası: aktif kullanıcı başına en fazla bir ek
        # çağrı; check-in günlerinde bir fazlası.
        kota = DAILY_EXTRACTIONS + (1 if checkin else 0)
        if not entitlements.consume_quota(uid, "memory_extract", kota):
            return None

        # Mevcut anahtarlar prompt'a giriyor: model aynı konuda YENİ bir
        # anahtar uydurduğunda `upsert_facts` birleştirme yapamıyor ve iki
        # çelişen kayıt yan yana yaşıyordu ("üstüne yığılma"). Konu bazlı
        # geçersizleme bunu arkadan temizliyor ama yalnız `concern` için;
        # anahtarın yeniden kullanılması kökten çözüyor. Ek maliyet bir
        # Firestore okuması (aynı doküman biraz sonra `upsert_facts`
        # içinde yine okunuyor) — LLM maliyeti sıfır.
        # Aşağıdaki ``[:40]`` tavanı ``memory_service.MAX_FACTS``i AYNALAR
        # ve normal akışta ULAŞILAMAZ (budama dokümanı 40'ın üstüne
        # çıkarmıyor). Elle bozulmuş ya da budamadan önce okunmuş bir
        # dokümanın prompt'u şişirmesine karşı duruyor; bu yüzden onun
        # bekçisi de yok — ulaşılamayan dalın testi olmaz.
        anahtarlar = [str(f.get("key")) for f
                      in memory_service.get_memory(uid).get("facts", [])
                      if f.get("key") and not f.get("invalidatedAt")]
        prompt = _PROMPT.format(
            kategoriler=", ".join(memory_service.CATEGORIES),
            konular=", ".join(memory_service.KONULAR),
            anahtarlar=", ".join(anahtarlar[:40]) or "-",
            konusma=_conversation_text(history, last_message),
        )
        raw = gemini_service.extract_json(prompt, schema=_SCHEMA,
                                          feature="memory_extract", uid=uid)
        if not raw:
            return None

        data = json.loads(raw)
        facts = data.get("facts") or []
        if not isinstance(facts, list):
            return None

        memory = memory_service.upsert_facts(uid, facts)

        mood = str(data.get("mood") or "").strip()
        if mood:
            memory_service.record_mood(
                uid, mood,
                intensity=str(data.get("intensity") or "").strip().lower(),
                needs=str(data.get("needs") or "").strip().lower())

        logger.info("Hafıza güncellendi: uid=%s olgu=%d", uid, len(facts))
        return memory
    except Exception as exc:
        logger.warning("Olgu çıkarımı başarısız (%s): %s", uid, exc)
        return None

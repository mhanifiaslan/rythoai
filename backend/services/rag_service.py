"""RAG (Retrieval-Augmented Generation) bilgi tabanı servisi.

`knowledge/corpus/{dil}` altındaki metinler parçalanır, Gemini embedding
API'siyle vektörlenir ve kosinüs benzerliğiyle aranır. Bulunan pasajlar LLM
prompt'una bağlam olarak eklenir.

API anahtarı ya da vektör yoksa TF benzeri anahtar kelime skorlamasına düşer —
servis hiçbir koşulda hata fırlatmaz, en kötü durumda boş bağlam döner.

## Bu katman 12 parça için yazılmıştı, kitap için yeniden kuruldu

Korpus dil başına ~9 KB ve 12-13 parçayken aşağıdaki dördü de görünmüyordu.
Gerçek bir kamu malı klasik (~900 parça) eklendiğinde dördü birden kırılıyor:

1. **Parçalama.** Bölme yalnızca ``##`` başlıklarındandı. Bir kitap bölümü tek
   parçada binlerce kelime olur; embedding o parçanın ORTALAMASINI alır ve
   arama körelir. Artık boyut sınırlı, cümle sınırında, örtüşmeli.
2. **Embedding önbelleği.** Anahtar TÜM korpusun sağlamasıydı: tek dosyaya tek
   satır eklemek 900 parçanın tamamını yeniden vektörletirdi. Artık her parça
   kendi metninin sağlamasıyla anahtarlanıyor — değişmeyen parça yeniden
   vektörlenmez.
3. **Çalışma zamanında vektörleme.** Önbellek `config.CACHE_DIR`'daydı ve o
   Cloud Run'da GEÇİCİ disk. 900 parçada her soğuk başlatma 900 embedding
   çağrısı demekti: gecikme, fatura, ve ilk isteklerde aramanın sessizce
   anahtar kelime moduna düşmesi. Vektörler artık derleme zamanında üretilip
   `knowledge/embeddings/{dil}.json` olarak imaja gömülüyor
   (`scripts/build_embeddings.py`).
4. **Arama.** Kosinüs saf Python'du ve her sorguda tüm parçalar üzerinde
   dönüyordu: 900 parça × 3.072 boyut ≈ 2,8 milyon çarpma, sohbet başına
   saniyeler. Artık normalize edilmiş tek bir numpy matrisi ve tek `matmul`.

Bir de gözlemlenebilirlik: anlamsal aramanın anahtar kelimeye düşmesi bir kez
haftalarca fark edilmedi. `diagnostics()` artık kapsama oranını da veriyor ve
eksik kapsama ERROR olarak loglanıyor.
"""
from __future__ import annotations

import hashlib
import json
import logging
import re
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from core import config, i18n

logger = logging.getLogger(__name__)

#: Parça üst sınırı. Embedding tek bir vektöre indirgediği için uzun metin
#: ayrıntıyı ortalamada eritir; kısa parça ise bağlamı kaybeder.
MAX_CHUNK_CHARS = 1100
#: Bundan kısa gövdeler parça sayılmaz (başlık artığı, boş bölüm).
MIN_CHUNK_CHARS = 40
#: Ardışık parçalar arasındaki örtüşme. Bir cümlenin tam ortasından bölünmesi
#: anlamı öldürür; örtüşme sınırdaki cümlenin iki parçada da bulunmasını sağlar.
CHUNK_OVERLAP_CHARS = 120

#: Tek istekte kaç metin vektörlenecek.
_EMBED_BATCH_SIZE = 32

#: Sorgu vektörü LRU'su (instance ömrü boyunca).
_QUERY_CACHE_MAX = 128

#: Anlamsal aramada bir pasajın "ilgili" sayılması için gereken en düşük
#: kosinüs skoru.
#:
#: Ölçülerek konuldu ve kitap korpusuyla YENİDEN ölçüldü (RD4,
#: scripts/calibrate_rag.py — 2026-08-28, 1.253 TR / 1.255 EN parça):
#: gerçek üretim sorgu biçimleri (mesaj + tohum + harita faktörleri ve
#: rapor tohum kombinasyonları) TR'de 0,635–0,780, EN'de 0,629–0,853
#: skor alıyor; alakasız sorular ("wifi şifremi nasıl sıfırlarım",
#: "yarın hava yağmurlu mu") 0,46–0,589'da kalıyor. 0,62 iki kümenin
#: arasında: en dar kenarlar sinastri TR 0,635 (+0,015) ve alakasız
#: tavan 0,589 (−0,031). ÇIPLAK tek tohum ("Evlilik, ortaklık, bağ")
#: 0,52'ye düşebilir ama üretimde hiçbir sorgu çıplak tek tohum değil.
#: Sohbette ikinci savunma hattı zaten var: should_use_rag alakasız kısa
#: mesajları getirmeye hiç göndermez.
#:
#: Eşik olmadan alakasız bir soruda en yakın pasaj yine dönüyordu: model
#: kadim bir metni ilgisiz bir konuya bağlamaya çalışıyor ve cevap
#: zorlama çıkıyordu. Kaynak yoksa kaynaksız cevap vermek daha dürüst.
#:
#: YALNIZCA vektör modunda uygulanır. Anahtar kelime modunun skoru tamamen
#: farklı bir ölçekte (örtüşen kelime sayısı / sorgu uzunluğu) ve orada bu
#: eşik her şeyi elerdi.
_MIN_RELEVANCE = 0.62

#: Bölüm çeşitliliği için aday havuzu top_k'nın kaç katı olsun.
#:
#: 4 katı yetmedi: uzun bir bölüm (ör. "The Quality of Employment") tek başına
#: 8+ parçaya bölünüyor ve havuzun tamamını doldurabiliyor — çeşitlilik kuralı
#: seçecek farklı bölüm bulamayınca aynı bölümden iki parça dönüyordu.
#: Skorlar zaten tüm parçalar için hesaplı; havuzu genişletmenin maliyeti
#: vektör modunda yalnızca argpartition, kelime modunda partition + eşik +
#: havuzun lexsort'u (`_kelime_sirasi`). İkincisinde havuz eşitlerle
#: büyüyebilir — hiçbir parça eşleşmezse bütün korpus (1.253) havuza girer —
#: ve o en kötü hâl bile 0,13 ms; aramanın tamamı 0,39 ms (ölçüldü
#: 2026-10-22, Apple Silicon). İki modda da ihmal edilebilir.
_DIVERSITY_POOL = 12


def embedding_files(lang: str) -> tuple[Path, Path]:
    """Dilin vektör artefaktı — derleme zamanında üretilir, imaja gömülür.

    İki dosya, ve bu bilinçli: vektörler JSON'a yazılsaydı 900 parça × 3.072
    boyut ≈ **55 MB** metin ederdi (her float ~20 karakter). Aynı veri
    float32 ``.npy`` olarak ~11 MB. Depo ve imaj boyutu arasındaki fark
    beş kat.

    - ``{dil}.json``: model adı, boyut ve parça kimlikleri (sıra = matris satırı)
    - ``{dil}.npy``:  (n, dim) float32 matris

    Dil başına ayrı: tek dosya olsaydı bir dilin korpusu değiştiğinde
    diğerinin vektörleri de boşa düşerdi.
    """
    base = config.KNOWLEDGE_DIR / "embeddings"
    return base / f"{lang}.json", base / f"{lang}.npy"


def read_artifact(lang: str) -> dict[str, np.ndarray]:
    """Artefaktı ``chunk_id -> vektör`` sözlüğü olarak okur.

    Değerler matrisin satırlarına bakan **görünümlerdir**; kopya çıkarılmaz,
    900 parçada bu 11 MB'lık bir farktır.
    """
    meta_path, vec_path = embedding_files(lang)
    if not (meta_path.exists() and vec_path.exists()):
        return {}
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        matris = np.load(vec_path)
    except Exception as exc:
        logger.warning("Vektör artefaktı okunamadı (%s): %s", lang, exc)
        return {}

    if meta.get("model") != config.EMBEDDING_MODEL:
        # Model değiştiyse eski vektörler karşılaştırılabilir değil: aynı
        # uzayda olmayan iki vektörün kosinüsü anlamsızdır.
        logger.warning(
            "Vektör artefaktı '%s' modeliyle üretilmiş, şu an '%s' "
            "kullanılıyor; artefakt yok sayılıyor.",
            meta.get("model"), config.EMBEDDING_MODEL)
        return {}

    ids = meta.get("ids") or []
    if len(ids) != len(matris):
        logger.error("Vektör artefaktı bozuk (%s): %d kimlik, %d satır.",
                     lang, len(ids), len(matris))
        return {}
    return {kimlik: matris[i] for i, kimlik in enumerate(ids)}


def write_artifact(lang: str, vektorler: dict[str, np.ndarray]) -> None:
    """Artefaktı diske yazar (derleme betiği ve yerel geliştirme için)."""
    meta_path, vec_path = embedding_files(lang)
    ids = list(vektorler)
    matris = (np.asarray([vektorler[k] for k in ids], dtype=np.float32)
              if ids else np.zeros((0, 0), dtype=np.float32))
    meta_path.parent.mkdir(parents=True, exist_ok=True)
    np.save(vec_path, matris)
    meta_path.write_text(json.dumps({
        "model": config.EMBEDDING_MODEL,
        "dim": int(matris.shape[1]) if ids else 0,
        "count": len(ids),
        "ids": ids,
    }), encoding="utf-8")


@dataclass
class Chunk:
    doc: str
    title: str
    text: str
    embedding: list[float] | None = None
    keywords: set[str] = field(default_factory=set)
    #: Kaynak künyesi (kitap, yazar, çevirmen, lisans). Atıf ve lisans
    #: savunması bunsuz mümkün değil; ticari bir üründe gerekli.
    source: dict[str, str] = field(default_factory=dict)
    #: Metnin sağlaması. Vektör önbelleği buna göre anahtarlanır: metin
    #: değişmedikçe vektör yeniden üretilmez, parça yer değiştirse bile.
    chunk_id: str = ""
    # -- RD-turu: kitap korpusu (JSONL) meta alanları; md parçalarında boş --
    #: Gömülecek metin. Kitap korpusunda `text`ten AYRIDIR (TR başlık +
    #: anahtar kelimeler + gövde); boşsa `text` gömülür — md yolu değişmez
    #: ve eski chunk_id'ler bayt aynı kalır (artımlı gömme korunur).
    embed_text: str = ""
    #: Konu etiketleri (finance, career, marriage...) — sohbet konusu
    #: eşleşmesinde boost için.
    topics: tuple[str, ...] = ()
    #: Parçanın andığı gezegen/burç/ev varlıkları — kullanıcının GERÇEK
    #: yerleşimleriyle eşleşince boost (kişiselleştirilmiş getirme).
    planets: frozenset = frozenset()
    signs: frozenset = frozenset()
    houses: frozenset = frozenset()
    #: Kaynağın otorite ağırlığı (3-5) — beraberlik bozucu.
    authority: int = 0


def _chunk_id(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:24]


def _embed_source(c: Chunk) -> str:
    """Parçanın GÖMÜLECEK metni — kitap korpusunda ayrı, md'de `text`."""
    return c.embed_text or c.text


def _tokenize(text: str) -> set[str]:
    return {w for w in re.findall(r"[a-zçğıöşü]{3,}",
                                  text.lower().replace("ı", "i"))}


# --------------------------------------------------------------------------
# Korpus yükleme ve parçalama
# --------------------------------------------------------------------------

def _corpus_dir(lang: str) -> Path:
    """Dilin korpus dizini; yoksa varsayılan dile düşer.

    Yeni bir dil eklenip korpusu henüz yazılmadığında sistem boş bağlamla
    değil, varsayılan dilin korpusuyla çalışır — kalite düşer ama özellik
    çalışmaya devam eder.
    """
    base = config.KNOWLEDGE_DIR / "corpus"
    hedef = base / lang
    if hedef.is_dir():
        return hedef
    yedek = base / i18n.DEFAULT
    if yedek.is_dir():
        logger.warning("'%s' korpusu yok; '%s' korpusuna düşülüyor.",
                       lang, i18n.DEFAULT)
        return yedek
    return base


_FRONT_MATTER = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def _parse_front_matter(text: str) -> tuple[dict[str, str], str]:
    """Dosya başındaki ``---`` bloğunu künye olarak okur.

    Basit ``anahtar: değer`` biçimi; YAML bağımlılığı eklemeye değmez.
    Künye kitap dosyaları için zorunlu (lisans kaydı), kendi yazdığımız
    sentez dosyaları için isteğe bağlı.
    """
    m = _FRONT_MATTER.match(text)
    if not m:
        return {}, text
    kunye: dict[str, str] = {}
    for satir in m.group(1).splitlines():
        if ":" not in satir:
            continue
        anahtar, _, deger = satir.partition(":")
        anahtar, deger = anahtar.strip(), deger.strip()
        if anahtar and deger:
            kunye[anahtar] = deger
    return kunye, text[m.end():]


#: Cümle sonu. Kısaltmalar (Md., vb.) yanlış bölmeye yol açabilir ama
#: sonuç yalnızca parça sınırını kaydırır — anlam kaybı yaratmaz.
_SENTENCE_END = re.compile(r"(?<=[.!?…])\s+")


def _sentences(text: str) -> list[str]:
    return [c for c in _SENTENCE_END.split(text.strip()) if c]


def _hard_wrap(cumle: str) -> list[str]:
    """Tek başına üst sınırı aşan cümleyi kelime sınırında böler.

    Nadir ama gerçek: kaynak metinlerde noktalama olmadan uzayan pasajlar var.
    Bölünmezse tek bir dev parça bütün aramayı çarpıtır.
    """
    parcalar, kalan = [], cumle
    while len(kalan) > MAX_CHUNK_CHARS:
        kesme = kalan.rfind(" ", 0, MAX_CHUNK_CHARS)
        if kesme <= 0:
            kesme = MAX_CHUNK_CHARS
        parcalar.append(kalan[:kesme].strip())
        kalan = kalan[kesme:].strip()
    if kalan:
        parcalar.append(kalan)
    return parcalar


def _split_body(body: str) -> list[str]:
    """Gövdeyi boyut sınırlı, örtüşmeli parçalara böler."""
    if len(body) <= MAX_CHUNK_CHARS:
        return [body]

    parcalar: list[str] = []
    tampon: list[str] = []
    uzunluk = 0

    def bosalt() -> None:
        nonlocal tampon, uzunluk
        if tampon:
            parcalar.append(" ".join(tampon).strip())
        tampon, uzunluk = [], 0

    for cumle in _sentences(body):
        for parca in (_hard_wrap(cumle) if len(cumle) > MAX_CHUNK_CHARS
                      else [cumle]):
            if uzunluk + len(parca) + 1 > MAX_CHUNK_CHARS and tampon:
                bosalt()
                # Örtüşme: önceki parçanın kuyruğu yeni parçanın başına gelir.
                kuyruk = parcalar[-1][-CHUNK_OVERLAP_CHARS:]
                bosluk = kuyruk.find(" ")
                if bosluk > 0:
                    kuyruk = kuyruk[bosluk + 1:]
                # Kuyruk da bütçeye dahildir. Noktalamasız uzun bir pasaj
                # sert bölündüğünde parçanın kendisi zaten üst sınıra yakın
                # olur; kuyruğu eklemek sınırı aşardı. O durumda örtüşmeden
                # vazgeçilir — sınırı korumak örtüşmeden önce gelir.
                if kuyruk and len(kuyruk) + len(parca) + 1 <= MAX_CHUNK_CHARS:
                    tampon.append(kuyruk)
                    uzunluk = len(kuyruk)
            tampon.append(parca)
            uzunluk += len(parca) + 1

    bosalt()
    return [p for p in parcalar if p]


#: Kitap korpusu (RD-turu): dil-nötr JSONL dosyaları — her kayıtta EN ve
#: TR metin birlikte durur, yükleyici dile göre alan seçer.
_BOOKS_DIR_NAME = "books"

#: Konusu TAMAMEN bu kümeden oluşan parça korpusa GİRMEZ (kullanıcı
#: kararı, RD-turu): ölüm/sağlık hükümleri ürünün yasak alanı. Karışık
#: etiketli parçalar (ör. career+death) girer; prompt katmanındaki
#: yasak-alan kuralı (WHISPER_RAG v2) sızıntıyı orada keser.
_SAFETY_DROP_TOPICS = frozenset({"death", "health"})

#: Gömme girdisi savunma tavanı (~1.700 token). Korpusun en büyük embed
#: metni ~6.6K kr — bugün sınır aşılmıyor; bu, gelecekteki bir kitap
#: eklemesinin gömme API'sini sessizce kırmasına karşı emniyet.
_MAX_EMBED_CHARS = 7000

#: Yeniden sıralama ekleri (RD3). Kosinüs ölçeği ~0.6-0.85; ekler bir
#: yakın-beraberliği çevirebilecek ama iyi eşleşmiş bir parçayı konu
#: dışı bir parçaya YENİLETMEYECEK kadar küçük tutulur. Eşik HAM skora
#: uygulandığı için boost alakasızı geri getiremez.
_BOOST_TOPIC = 0.03
_BOOST_PLANET = 0.02
_BOOST_HOUSE = 0.02
_BOOST_SIGN = 0.01
_BOOST_AUTHORITY = 0.002   # × authority (3-5) → +0.006..+0.010
_BOOST_CAP = 0.08

_HOUSE_RE = re.compile(r"^(\d{1,2})(st|nd|rd|th)\s+House$", re.IGNORECASE)


def _normalize_house(raw: object) -> int | None:
    """Korpusun "10th House" biçimini motorun ev numarasına çevirir."""
    m = _HOUSE_RE.match(str(raw).strip())
    if not m:
        return None
    n = int(m.group(1))
    return n if 1 <= n <= 12 else None


def _load_book_chunks(lang: str) -> list[Chunk]:
    """`knowledge/corpus/books/*.jsonl` kitap parçalarını yükler (RD1).

    Kayıt şeması `docs/rag_corpus/README.md`'de. Dil başına seçim:
    tr → ``text_tr`` + ``embedding_text_tr``, en → ``text`` +
    ``embedding_text``. ``doc = source_id``, ``title = heading`` —
    (doc, title) çeşitlilik anahtarı bölüm bazında çalışır ve iki Lilly
    kitabı ayrışır.
    """
    books_dir = config.KNOWLEDGE_DIR / "corpus" / _BOOKS_DIR_NAME
    chunks: list[Chunk] = []
    if not books_dir.is_dir():
        return chunks
    tr_mi = (lang or i18n.DEFAULT) != "en"

    for jl in sorted(books_dir.glob("*.jsonl")):
        try:
            satirlar = jl.read_text(encoding="utf-8").splitlines()
        except Exception as exc:
            logger.warning("Kitap korpusu okunamadı (%s): %s", jl.name, exc)
            continue
        for satir in satirlar:
            satir = satir.strip()
            if not satir:
                continue
            try:
                kayit = json.loads(satir)
            except ValueError:
                logger.warning("Bozuk JSONL satırı atlandı (%s)", jl.name)
                continue
            m = kayit.get("metadata") or {}
            metin = str(kayit.get("text_tr" if tr_mi else "text") or "").strip()
            embed = str(kayit.get("embedding_text_tr" if tr_mi
                                  else "embedding_text") or "").strip()
            if len(metin) < MIN_CHUNK_CHARS:
                continue
            konular = tuple(str(t) for t in (m.get("topic") or [])
                            if isinstance(t, (str, int)))
            # Güvenlik süzgeci: konusu YALNIZ ölüm/sağlık olan parça girmez.
            if konular and set(konular) <= _SAFETY_DROP_TOPICS:
                continue
            if not embed:
                embed = metin
            if len(embed) > _MAX_EMBED_CHARS:
                kesme = embed.rfind(" ", 0, _MAX_EMBED_CHARS)
                embed = embed[:kesme if kesme > 0 else _MAX_EMBED_CHARS]
            evler = frozenset(
                n for n in (_normalize_house(h)
                            for h in (m.get("entity_house") or []))
                if n is not None)
            chunks.append(Chunk(
                doc=str(m.get("source_id") or jl.stem),
                title=str(m.get("heading") or "").strip() or jl.stem,
                text=metin,
                keywords=_tokenize(embed),
                source={k: str(m.get(k)) for k in (
                    "source", "author", "translator", "license",
                    "source_url", "school", "school_tr", "era", "era_tr",
                    "tradition") if m.get(k)},
                chunk_id=_chunk_id(embed),
                embed_text=embed,
                topics=konular,
                planets=frozenset(str(p) for p in
                                  (m.get("entity_planet") or [])),
                signs=frozenset(str(s) for s in
                                (m.get("entity_sign") or [])),
                houses=evler,
                authority=int(m.get("authority_weight") or 0),
            ))
    return chunks


def _load_chunks(lang: str) -> list[Chunk]:
    corpus_dir = _corpus_dir(lang)
    chunks: list[Chunk] = _load_book_chunks(lang)
    if not corpus_dir.exists():
        logger.warning("Korpus dizini bulunamadı: %s", corpus_dir)
        return chunks

    for md_file in sorted(corpus_dir.glob("*.md")):
        ham = md_file.read_text(encoding="utf-8")
        kunye, govde = _parse_front_matter(ham)

        sections = re.split(r"(?m)^##\s+", govde)
        doc_title = md_file.stem
        if sections and sections[0].strip():
            ilk = sections[0].strip().lstrip("# ").splitlines()
            if ilk:
                doc_title = ilk[0]
        # Künyedeki kitap adı dosya başlığından önce gelir: aynı kitabın
        # bölümleri ayrı dosyalara bölündüğünde başlık tutarlı kalır.
        kitap = kunye.get("book") or doc_title

        for section in sections[1:]:
            lines = section.strip().splitlines()
            if not lines:
                continue
            title = lines[0].strip()
            body = "\n".join(lines[1:]).strip()
            if len(body) < MIN_CHUNK_CHARS:
                continue

            parcalar = _split_body(body)
            for i, parca in enumerate(parcalar):
                # Başlık her parçaya iliştirilir: parça tek başına
                # vektörlendiği için hangi bölümden geldiğini kendi
                # içinde taşımalı, yoksa bağlamsız bir metin gömülür.
                etiket = f"{kitap} — {title}"
                if len(parcalar) > 1:
                    etiket += f" ({i + 1}/{len(parcalar)})"
                metin = f"{etiket}\n{parca}"
                chunks.append(Chunk(
                    doc=md_file.stem, title=title, text=metin,
                    keywords=_tokenize(metin), source=kunye,
                    chunk_id=_chunk_id(metin),
                ))
    return chunks


# --------------------------------------------------------------------------
# Bilgi tabanı
# --------------------------------------------------------------------------

def _as_contents(texts: list[str]) -> list[dict]:
    """Metin listesini, her metin AYRI bir Content olacak şekilde paketler.

    Bu, göründüğü kadar önemsiz değil: ``embed_content(contents=[...str])``
    çağrısında SDK düz string listesini TEK bir Content'in birden fazla parçası
    sayar ve **tek bir embedding** döndürür. Sonuç sessiz bir bozulmadır —
    korpusun yalnızca ilk parçası vektörlenir, arama da anahtar kelime
    örtüşmesine düşer ve hiçbir yerde hata görünmez.
    """
    return [{"parts": [{"text": text}]} for text in texts]


def _kelime_sirasi(skorlar: np.ndarray, chunks: list[Chunk],
                   havuz: int) -> np.ndarray:
    """Anahtar-kelime modunun aday sırası — eşitlik her makinede aynı bozulur.

    Bu modda skorun paydası (sorgu uzunluğu + 1) bütün parçalar için aynı,
    yani skor yalnız ORTAK KELİME ADEDİNİ taşıyor ve eşitlik istisna değil
    kural: aile tohumu + "Babamla aram hiç düzelmeyecek mi" sorgusunda en
    yüksek skorda 10 parça eşit (ölçüldü 2026-10-22). Eski yol onları
    `argpartition` + kararsız `argsort` ile seçiyordu ve NumPy'nin bu ikisinde
    eşitliği nasıl bozduğu işlemcinin SIMD yoluna bağlı: x86_64'te (top_k=3)
    "Baba ve Anne" bölümü sonuçtaydı, Apple Silicon'da üç sonucun ikisi OCR'lı
    kitap parçasıydı (biri korpus sırasında i=320: OCR başlığı "APHORISMS
    RELATING TO DECUMBITURES", gövdesi George Redway yayınevinin kitap
    kataloğu).

    Eşit onun yedisi korpusta `parents_family` etiketli kitap parçası, üçü
    aile doktrini. Etiket içeriği garanti etmiyor: i=320 etiketli ama gövdesi
    o katalog. Yedi kitap parçasının beşi eşitliğe ancak embed metninin
    başındaki `[Anahtar kelimeler: …]` satırı sayesinde ulaşıyor (i=320'de
    dört ortak kelimenin ikisi gövdede; i=712 ve i=1064'te "aile", "anne",
    "baba"nın üçü de gövdede yok). Skor bu on parçayı ayırmıyor; gereken
    şey sabit bir sıra, ve hangi eşitin öne geçeceği bir TERCİH. Tercih:
    `len(keywords)` az olan önde — kitap parçasında embed metninin (başlık +
    `[Anahtar kelimeler: …]` satırı + gövde), md parçasında etiket satırı +
    gövdenin benzersiz kelime sayısı. Yani eşitliği yaratan anahtar satırı
    da sayıya giriyor. Gerekçesi ölçüldü:

    - Pasaj prompta KESİLEREK giriyor: sohbette 1.200
      (`prompt_composer.MAX_PASSAGE_CHARS`), raporda 2.000 karakter
      (`_MAX_CONTEXT_PASSAGE_CHARS`). Eşit yedi kitap parçası 2.052–4.144
      karakter, iki yolda da kesik girer; üç doktrin parçası 726–1.048
      karakter, bütün girer.
    - Aynı SAYIDA (dört) ortak kelime — kümeler değil, on eşit altı farklı
      dörtlü paylaşıyor — `len(keywords)` 68–96 olan doktrinde metnin daha
      büyük payı, 202–401 olan kitap parçasında daha küçük payı. BM25'in
      uzunluk düzeltmesiyle aynı gerekçe — ama skora girmiyor, yalnız
      eşitliği bozuyor; eşit olmayan iki parçanın sırası değişmez.

    Bu sıra hangi metnin daha İYİ olduğunu ölçmüyor. `len(keywords)`
    uzunluğun VEKİLİ ve prompt kesiminden FARKLI bir metni ölçüyor: kesim
    `text`in karakter sayısına bakar, kitap parçasının `text`i ise başlık ve
    anahtar satırını taşımaz. Bu eşitlikte ikisi aynı yönü gösteriyor:
    kitap parçalarında `len(keywords)` 202–401 (yalnız gövde 168–373) ve
    `text` 2.052–4.144 karakter; doktrinde `len(keywords)` 68–96 ve `text`
    726–1.048 karakter — iki grup her iki ölçüde de ayrık. Her eşitlikte
    öyle olacağı ölçülmedi.

    `authority` BİLEREK anahtar değil: md doktrin parçalarında alan hiç
    yazılmıyor (0 "puanlanmamış" demek, "düşük" değil). Öne konsaydı eşit
    yedi kitap parçasının hepsi 5 olduğu için üç sonucun üçü de kitaptan
    gelir, aile sorusuna aile doktrini hiç dönmezdi.

    Son anahtar korpus sırası: kelime sayısı da eşitse sonuç yine sabit.

    Havuz sınırı eşitleri kesmez: `havuz`'uncu skorla eşit olan HER parça
    alınır. `np.partition`'ın o konuma koyduğu DEĞER benzersizdir (sıra
    istatistiği); oraya hangi İNDEKSİN düştüğü değil — eşik o yüzden
    değerden kuruluyor.
    """
    # Kırpma burada da şart: havuz korpusu aşınca `sinir` negatif olur ve
    # np.partition onu SONDAN sayar. n < havuz < 2n'de (havuz − n)'inci en
    # büyük değer eşik olur ve havuz sessizce o kadara daralır; havuz = 2n'de
    # rastlantıyla doğru çıkar; havuz > 2n'de ValueError (ölçüldü, n=4).
    havuz = min(havuz, len(skorlar))
    if havuz <= 0:
        return np.empty(0, dtype=np.intp)
    sinir = len(skorlar) - havuz
    esik = np.partition(skorlar, sinir)[sinir]
    aday = np.flatnonzero(skorlar >= esik)
    kelime = np.fromiter((len(chunks[i].keywords) for i in aday),
                         dtype=np.int64, count=len(aday))
    # lexsort SON verilen anahtarı birincil sayar.
    return aday[np.lexsort((aday, kelime, -skorlar[aday]))]


class _KnowledgeBase:
    """Tek bir dilin bilgi tabanı.

    Diller ayrı örneklerde tutulur: korpus, vektörler ve sorgu önbelleği dile
    özgüdür. Tek örnekte karıştırılsaydı İngilizce bir sorgu Türkçe pasajlarla
    skorlanır ve yorum kalitesi düşerdi.
    """

    def __init__(self, lang: str = i18n.DEFAULT):
        self.lang = lang
        self._chunks: list[Chunk] | None = None
        #: (n, dim) float32, satırları L2-normalize. Kosinüs = tek matmul.
        self._matrix: np.ndarray | None = None
        self._query_cache: OrderedDict[str, np.ndarray] = OrderedDict()

    # -- embedding ---------------------------------------------------------

    def _embed_texts(self, texts: list[str]) -> list[list[float]] | None:
        """Metinleri vektörler; hepsi başarılı olmazsa ``None`` döner.

        Kısmi sonuç DÖNDÜRÜLMEZ: eksik vektörle devam etmek, aramanın sessizce
        anahtar kelime moduna düşmesi anlamına gelir ve bu dışarıdan görünmez.
        """
        if not config.GEMINI_API_KEY or not texts:
            return None
        try:
            from google import genai

            client = genai.Client(api_key=config.GEMINI_API_KEY)
            vectors: list[list[float]] = []
            for start in range(0, len(texts), _EMBED_BATCH_SIZE):
                batch = texts[start:start + _EMBED_BATCH_SIZE]
                result = client.models.embed_content(
                    model=config.EMBEDDING_MODEL, contents=_as_contents(batch)
                )
                vectors.extend(e.values for e in result.embeddings)

            if len(vectors) != len(texts):
                logger.error(
                    "Embedding sayısı uyuşmuyor: %d metin istendi, %d vektör "
                    "döndü. Arama anahtar kelime moduna düşecek.",
                    len(texts), len(vectors),
                )
                return None
            return vectors
        except Exception as exc:
            logger.warning("Embedding üretilemedi: %s", exc)
            return None

    # -- yükleme -----------------------------------------------------------

    def _ensure_loaded(self) -> list[Chunk]:
        if self._chunks is not None:
            return self._chunks

        chunks = _load_chunks(self.lang)
        self._chunks = chunks
        if not chunks:
            return chunks

        vektorler = read_artifact(self.lang)
        eksik = [c for c in chunks if c.chunk_id not in vektorler]

        if eksik:
            # Bu satırın ÜRETİMDE görünmesi bir kusurdur: artefakt korpusla
            # uyumsuz demektir ve her soğuk başlatma embedding faturası
            # çıkarır. Derleme betiği çalıştırılmamış olabilir.
            logger.error(
                "Vektör artefaktı korpusla uyumsuz (%s): %d/%d parça eksik. "
                "scripts/build_embeddings.py çalıştırılmalı.",
                self.lang, len(eksik), len(chunks))
            yeni = self._embed_texts([_embed_source(c) for c in eksik])
            if yeni:
                for chunk, emb in zip(eksik, yeni):
                    vektorler[chunk.chunk_id] = np.asarray(emb,
                                                           dtype=np.float32)
                try:
                    write_artifact(self.lang, vektorler)
                except Exception as exc:
                    logger.warning("Vektör artefaktı yazılamadı: %s", exc)

        self._build_matrix(chunks, vektorler)
        return chunks

    def _build_matrix(self, chunks: list[Chunk],
                      vektorler: dict[str, np.ndarray]) -> None:
        """Vektörleri korpus sırasında tek bir normalize matrise toplar.

        Parça başına Python listesi TUTULMAZ: 900 parça × 3.072 boyut liste
        olarak ~80 MB, float32 matris olarak ~11 MB eder. İkisini birden
        tutmanın anlamı yok, bu yüzden `Chunk.embedding` doldurulmuyor.
        """
        if any(c.chunk_id not in vektorler for c in chunks):
            self._matrix = None
            return
        try:
            matris = np.asarray([vektorler[c.chunk_id] for c in chunks],
                                dtype=np.float32)
        except ValueError:
            # Farklı boyutlu vektörler (model değişimi artığı) — kosinüs
            # hesaplanamaz, anahtar kelime moduna düşülür.
            logger.error("Vektör boyutları tutarsız (%s); anahtar kelime "
                         "moduna düşülüyor.", self.lang)
            self._matrix = None
            return
        if matris.ndim != 2 or matris.shape[1] == 0:
            self._matrix = None
            return
        normlar = np.linalg.norm(matris, axis=1, keepdims=True)
        normlar[normlar == 0] = 1.0
        self._matrix = matris / normlar

    def _embed_query(self, query: str) -> np.ndarray | None:
        """Sorgu vektörünü LRU önbellek üzerinden üretir (normalize)."""
        key = " ".join(query.lower().split())
        if key in self._query_cache:
            self._query_cache.move_to_end(key)
            return self._query_cache[key]
        embs = self._embed_texts([query])
        if not embs:
            return None
        vec = np.asarray(embs[0], dtype=np.float32)
        norm = float(np.linalg.norm(vec))
        if norm == 0:
            return None
        vec = vec / norm
        self._query_cache[key] = vec
        if len(self._query_cache) > _QUERY_CACHE_MAX:
            self._query_cache.popitem(last=False)
        return vec

    # -- arama -------------------------------------------------------------

    def semantic_ready(self) -> bool:
        """Korpusun tamamı vektörlendi mi?

        Kısmi vektörle kosinüs araması yapılamaz: embedding'i olmayan parçalar
        skorlamaya giremez ve sonuçlar sessizce çarpıtılır. Ya hepsi ya hiçbiri.
        """
        chunks = self._ensure_loaded()
        return bool(chunks) and self._matrix is not None \
            and len(self._matrix) == len(chunks)

    def search(self, query: str, top_k: int = 3,
               boost: dict | None = None) -> list[dict]:
        """Arama + metadata'lı yeniden sıralama (RD3).

        ``boost`` = ``{"topics": set, "planets": set, "houses": set,
        "signs": set}`` — sohbet katmanı kullanıcının GERÇEK harita
        faktörlerini geçirir; eşleşen parçalar küçük ekler alır. Sıra
        önemli: alaka eşiği HAM kosinüse uygulanır (boost alakasız bir
        parçayı diriltemez), ekler sonra biner. Anahtar-kelime yedeğinde
        boost yok (farklı skor ölçeği). Ölüm/sağlık konularına boost
        yapısal olarak imkânsız — konu haritası onları hiç üretmez
        (chart_query._CHAT_TO_CORPUS_TOPICS).
        """
        chunks = self._ensure_loaded()
        if not chunks:
            return []

        skorlar = None
        taban = 0.0
        vektor_modu = False
        if self.semantic_ready():
            q = self._embed_query(query)
            if q is not None and len(q) == self._matrix.shape[1]:
                skorlar = self._matrix @ q
                taban = _MIN_RELEVANCE
                vektor_modu = True

        if skorlar is None:
            q_tokens = _tokenize(query)
            bolen = len(q_tokens) + 1
            skorlar = np.asarray(
                [len(q_tokens & c.keywords) / bolen for c in chunks],
                dtype=np.float32)

        # Aday havuzu top_k'dan geniş tutulur çünkü aşağıda bölüm çeşitliliği
        # uygulanıyor.
        havuz = min(max(top_k * _DIVERSITY_POOL, top_k), len(chunks))
        if vektor_modu:
            # Tam sıralama gereksiz: argpartition O(n). Kelime modundaki
            # eşitlik sorunu burada yapısal değil: skor sürekli bir kosinüs
            # ve korpusta özdeş iki vektör yok (TR 1.253, EN 1.255 satırın
            # hepsi benzersiz, ölçüldü 2026-10-22).
            aday = np.argpartition(-skorlar, havuz - 1)[:havuz]
            aday = aday[np.argsort(-skorlar[aday])]
        else:
            aday = _kelime_sirasi(skorlar, chunks, havuz)
        aday = [i for i in aday if float(skorlar[i]) > taban]

        if vektor_modu and aday:
            skorlar = skorlar.astype(np.float32).copy()
            b = boost or {}
            b_konu = set(b.get("topics") or ())
            b_gezegen = set(b.get("planets") or ())
            b_ev = set(b.get("houses") or ())
            b_burc = set(b.get("signs") or ())
            for i in aday:
                c = chunks[i]
                ek = 0.0
                if b_konu and b_konu & set(c.topics):
                    ek += _BOOST_TOPIC
                if b_gezegen and b_gezegen & c.planets:
                    ek += _BOOST_PLANET
                if b_ev and b_ev & c.houses:
                    ek += _BOOST_HOUSE
                if b_burc and b_burc & c.signs:
                    ek += _BOOST_SIGN
                # Otorite her zaman küçük bir öncelik verir (beraberlik
                # bozucu ölçek): 5/5 kaynak +0.010, 3/5 +0.006.
                ek += _BOOST_AUTHORITY * c.authority
                if ek:
                    skorlar[i] += min(ek, _BOOST_CAP)
            aday.sort(key=lambda i: -float(skorlar[i]))

        # Bölüm çeşitliliği: kitap korpusu geldiğinde ilk iki sonucun ikisi de
        # AYNI bölümden çıkıyordu (uzun bölümler çok parçaya bölündüğü için
        # komşu parçalar benzer skor alıyor). Prompt bütçesi 2 pasaj; ikisini
        # de aynı bölüme harcamak bağlamın yarısını çöpe atmak demek.
        secilen: list[int] = []
        gorulen: set[tuple[str, str]] = set()
        for i in aday:
            anahtar = (chunks[i].doc, chunks[i].title)
            if anahtar not in gorulen:
                gorulen.add(anahtar)
                secilen.append(i)
            if len(secilen) == top_k:
                break
        # Yeterli farklı bölüm yoksa kalan yerler en yüksek skorlularla dolar.
        if len(secilen) < top_k:
            for i in aday:
                if i not in secilen:
                    secilen.append(i)
                if len(secilen) == top_k:
                    break

        return [{"doc": chunks[i].doc, "title": chunks[i].title,
                 "text": chunks[i].text, "score": round(float(skorlar[i]), 3),
                 "source": chunks[i].source,
                 "topics": list(chunks[i].topics),
                 "authority": chunks[i].authority}
                for i in secilen]

    def diagnostics(self) -> dict:
        chunks = self._ensure_loaded()
        return {
            "lang": self.lang,
            "mode": "vector" if self.semantic_ready() else "keyword",
            "chunks": len(chunks),
            "vectors": 0 if self._matrix is None else int(len(self._matrix)),
            "dim": 0 if self._matrix is None else int(self._matrix.shape[1]),
            "model": config.EMBEDDING_MODEL,
            "artifact": all(p.exists() for p in embedding_files(self.lang)),
        }


#: Dil -> bilgi tabanı. Tembel kurulur; her dilin korpusu ilk istekte yüklenir.
_bases: dict[str, _KnowledgeBase] = {}

#: Varsayılan dilin tabanı. Dil parametresi geçmeyen çağrılar ve testler bunu
#: kullanır.
knowledge_base = _KnowledgeBase(i18n.DEFAULT)
_bases[i18n.DEFAULT] = knowledge_base


def base_for(lang: str | None) -> _KnowledgeBase:
    """Dilin bilgi tabanını döndürür (tembel kurulum)."""
    lang = lang if lang in i18n.SUPPORTED else i18n.DEFAULT
    if lang not in _bases:
        _bases[lang] = _KnowledgeBase(lang)
    return _bases[lang]


def search_mode(lang: str | None = None) -> str:
    """Aramanın hangi modda çalıştığı — teşhis için.

    Bu bilginin dışa açık olması önemli: anlamsal aramanın anahtar kelimeye
    düşmesi daha önce hiçbir yerde görünmüyordu ve haftalarca fark edilmedi.
    """
    return "vector" if base_for(lang).semantic_ready() else "keyword"


def diagnostics() -> dict:
    """Desteklenen her dil için bilgi tabanı durumu."""
    return {kod: base_for(kod).diagnostics() for kod in i18n.SUPPORTED}


#: Rapor bağlamında pasaj başına tavan (RD6). Kitap parçaları ~3.3-6.4K
#: karakter; kırpılmasa top_k=3 rapor girdisini üçe katlardı.
_MAX_CONTEXT_PASSAGE_CHARS = 2000


def retrieve_context(query: str, top_k: int = 3, lang: str | None = None) -> str:
    """Sorguya en uygun kadim metin pasajlarını prompt bağlamı olarak döndürür."""
    results = base_for(lang).search(query, top_k=top_k)
    if not results:
        return ""
    parts = []
    for r in results:
        metin = r["text"]
        if len(metin) > _MAX_CONTEXT_PASSAGE_CHARS:
            kesme = metin.rfind(" ", 0, _MAX_CONTEXT_PASSAGE_CHARS)
            metin = metin[:kesme if kesme > 0
                          else _MAX_CONTEXT_PASSAGE_CHARS] + "…"
        parts.append(f"[Kaynak: {r['doc']} / {r['title']}]\n{metin}")
    return "\n\n---\n\n".join(parts)


def retrieve_passages(query: str, top_k: int = 2,
                      lang: str | None = None,
                      boost: dict | None = None) -> list[dict]:
    """Sohbet için ham pasaj listesi (prompt_composer kırpar ve harmanlar).

    ``boost``: kullanıcının konu + gerçek harita faktörleri
    (`chart_query.boost_hints`) — kişiselleştirilmiş getirme (RD3).
    """
    return base_for(lang).search(query, top_k=top_k, boost=boost)

"""Merkezi yapılandırma — tüm ortam değişkenleri buradan okunur."""
import logging
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

BACKEND_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = BACKEND_DIR.parent

GEMINI_API_KEY: str | None = os.getenv("GEMINI_API_KEY")
GOOGLE_CLOUD_PROJECT: str = os.getenv("GOOGLE_CLOUD_PROJECT", "rhytoai")
GOOGLE_CLOUD_LOCATION: str = os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1")

# Profil fotoğraflarının durduğu Cloud Storage kovası. Ad AÇIKÇA verilmek
# zorunda: uygulama `storageBucket` seçeneği olmadan başlatılıyor (bkz.
# core/firestore.py) ve `storage.bucket()` o durumda kova adı isteyip
# fırlatıyor. Hesap silme bu kovadan `avatars/{uid}/` önekini temizler.
STORAGE_BUCKET: str = os.getenv(
    "RYTHO_STORAGE_BUCKET", f"{GOOGLE_CLOUD_PROJECT}.firebasestorage.app")

# 1 => Firebase token yoksa da isteklere izin ver (lokal gelistirme)
DEV_MODE: bool = os.getenv("RYTHO_DEV_MODE", "1") == "1"

# 1 => DEV_MODE'un anonim "dev-user"i admin sayilir (W4). AYRI bayrak,
# bilerek: DEV_MODE tek basina yonetim yetkisi VEREMEZ — verseydi her yerel
# calistirma admin uclarini acardi. Uretimde ASLA 1 olmamali.
DEV_ADMIN: bool = os.getenv("RYTHO_DEV_ADMIN", "0") == "1"
# DEV_ADMIN açıkken dev-user'in panel rolü (AD1): owner | support. Destek
# kapılarını (403 bekleyen uçları) yerelde denemek için "support" verilir.
DEV_ADMIN_ROLE: str = os.getenv("RYTHO_DEV_ROLE", "owner")

# SABİT SÜRÜM — takma ad DEĞİL (S-turu).
#
# Varsayılan `gemini-flash-latest` idi ve bu bir takma ad: arkasındaki model
# haber vermeden değişiyor. Değişti de. Ölçülen sonuç: `thinking_budget: 0`
# artık uygulanmıyor, `thinking_level: "minimal"` ise 400 veriyor. Aynı soru
# 6 kez soruldu, **3'ü** düşünme bütçeyi yiyip kesildi ve kullanıcıya yarım
# cümle gösterildi. Yani bir gece içinde, biz hiçbir şey değiştirmeden,
# sohbetin yarısı bozuldu.
#
# Aday karşılaştırması (aynı soru, aynı ayar, 4'er çağrı):
#
#     gemini-flash-latest   2/4 kesik   ort. 191 token boşa düşünme
#     gemini-3.7-flash      2/4 kesik   ort. 196 token boşa düşünme
#     gemini-3.5-flash      0/4 kesik   0 düşünme   en düşük gecikme
#
# `gemini-3.5-flash` düşünme kontrolüne uyan tek aday. Yan fayda maliyet:
# düşünme token'ları ÇIKTI fiyatından faturalanıyor ($2,50/M), yani boşa
# düşünme sohbet turu başına ~%24 ek gider demekti.
#
# Model yükseltmesi artık BİLİNÇLİ bir karar: `GEMINI_MODEL` ortam
# değişkeniyle denenir, ölçülür, sonra varsayılan değiştirilir.
GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-3.5-flash")
EMBEDDING_MODEL: str = os.getenv("EMBEDDING_MODEL", "gemini-embedding-2")

# Bilgi tabanı dizini: Docker imajında /app/knowledge, lokalde repo kökü.
_knowledge_env = os.getenv("KNOWLEDGE_DIR", "").strip()
if _knowledge_env:
    KNOWLEDGE_DIR = Path(_knowledge_env)
elif (BACKEND_DIR / "knowledge").exists():
    KNOWLEDGE_DIR = BACKEND_DIR / "knowledge"
else:
    KNOWLEDGE_DIR = REPO_DIR / "knowledge"

CACHE_DIR = Path(os.getenv("RYTHO_CACHE_DIR", str(BACKEND_DIR / "cache")))
CACHE_DIR.mkdir(parents=True, exist_ok=True)

# Önbellek arka ucu: "firestore" | "file".
# Cloud Run'da instance diski geçici ve instance'lar arası paylaşımsızdır; burç
# yorumu gibi kullanıcıdan bağımsız içerikler ancak paylaşımlı bir arka uçla
# "tüm kullanıcılar için tek LLM çağrısı" garantisini verebilir.
# Varsayılan DEV_MODE'a bağlanır: lokalde dosya, üretimde Firestore.
CACHE_BACKEND: str = os.getenv(
    "RYTHO_CACHE_BACKEND", "file" if DEV_MODE else "firestore"
).strip().lower()

# Firestore önbellek koleksiyonu. Bu koleksiyona `expiresAt` alanı üzerinden
# native TTL politikası tanımlanmalıdır; aksi halde süresi dolan dokümanlar
# yalnızca okuma anında temizlenir.
CACHE_COLLECTION: str = os.getenv("RYTHO_CACHE_COLLECTION", "aiCache")

GEONAMES_USERNAME: str | None = os.getenv("GEONAMES_USERNAME")

# RevenueCat webhook'u icin paylasilan gizli anahtar. RevenueCat panelinde
# webhook'a "Authorization" basligi olarak tanimlanir. Tanimsizsa webhook ucu
# tum istekleri reddeder — abonelik durumu yazan tek yol bu oldugu icin
# dogrulamasiz calismasina izin verilmez.
REVENUECAT_WEBHOOK_SECRET: str | None = os.getenv("REVENUECAT_WEBHOOK_SECRET")

# Cloud Scheduler'in toplu bildirim ucunu tetiklerken tasidigi paylasilan
# gizli anahtar. Tanimsizken uc 503 doner: acik birakmak, herkesin tum
# kullanicilara bildirim gonderebilmesi demek olurdu.
NOTIFY_SCHEDULER_SECRET: str | None = os.getenv("NOTIFY_SCHEDULER_SECRET")


def _int_env(ad: str, varsayilan: int) -> int:
    """Bozuk değerde varsayılana düşer — sürüm kapısı FAIL-OPEN kalmalı:
    yanlış yazılmış bir env yüzünden tüm kullanıcıları kilitlemek,
    kapının önleyeceği her sorundan daha kötüdür."""
    try:
        return int(os.getenv(ad, str(varsayilan)))
    except ValueError:
        return varsayilan


# Zorunlu güncelleme kapısı (F3): istemci versionCode'u bundan KÜÇÜKSE
# uygulama güncelleme ekranına kilitlenir. 0 = kimse engellenmez.
# Kalıcı değer infra/deploy-backend.ps1'deki --set-env-vars satırında —
# gcloud ile elle verilen değer bir sonraki deploy'da silinir.
MIN_APP_BUILD: int = _int_env("RYTHO_MIN_BUILD", 0)


def _fiyat_env(ad: str, varsayilan: dict) -> dict:
    """Fiyat haritasını okur. JSON olmayan biçimi de kabul eder.

    ⚠️ Canlıda ölçülen tuzak (2026-09-14): `deploy-backend.ps1`
    `--set-env-vars` satırına `{"rytho_plus_monthly":4.4}` yazıyor ama
    Cloud Run'a `{rytho_plus_monthly:4.4}` olarak iniyor — gcloud'un
    argüman ayrıştırıcısı çift tırnakları soyuyor. Sonuç GEÇERLİ JSON
    değil; `json.loads` düşüyor, varsayılana (0.0) geri dönülüyor ve
    **panel MRR'ı sessizce 0 gösteriyordu.** Hiçbir yerde hata yok,
    çünkü burada bozuk değer bilerek yutuluyor.

    Onarım gürültü çıkarmak değil, biçimi genişletmek: tırnakları
    soyulmuş hâl de, düpedüz `anahtar=değer;anahtar=değer` de okunur.
    Kabul edilen üç biçim:

        {"rytho_plus_monthly": 4.4}     JSON (asıl)
        {rytho_plus_monthly:4.4}        tırnakları soyulmuş (gcloud)
        rytho_plus_monthly=4.4          düz çift (birden fazlası `;` ile)

    Bozuk girdide yine varsayılana düşülür — MRR bir gösterge, kapı
    değil; yanlış yazılmış bir env yüzünden toplayıcı düşmemeli. Ama
    artık WARNING yazılır: sessiz sıfır bir daha bir turu yakmasın.
    """
    import json

    ham = os.getenv(ad, "").strip()
    if not ham:
        return dict(varsayilan)

    try:
        veri = json.loads(ham)
        if isinstance(veri, dict):
            return {str(k): float(v) for k, v in veri.items()}
    except (ValueError, TypeError):
        pass  # Aşağıdaki gevşek ayrıştırıcı denenir.

    # Gevşek yol: süslü parantezleri at, çiftleri `,` `;` ile ayır,
    # anahtar/değeri `:` ya da `=` ile böl, tırnakları sil.
    govde = ham.strip().lstrip("{").rstrip("}")
    cikti: dict[str, float] = {}
    for parca in govde.replace(";", ",").split(","):
        parca = parca.strip()
        if not parca:
            continue
        for ayrac in (":", "="):
            if ayrac in parca:
                anahtar, _, deger = parca.partition(ayrac)
                anahtar = anahtar.strip().strip("\"'")
                try:
                    cikti[anahtar] = float(deger.strip().strip("\"'"))
                except ValueError:
                    cikti = {}
                break
        else:
            cikti = {}
        if not cikti and parca:
            break

    if cikti:
        return cikti

    logging.getLogger(__name__).warning(
        "%s çözümlenemedi (%r) — fiyatlar varsayılana düştü, panel MRR'ı "
        "0 gösterecek.", ad, ham)
    return dict(varsayilan)


# Abonelik ürünlerinin USD fiyatı (AD7) — panelin MRR tahmini. Mağaza
# fiyatı bölgeye göre değiştiği için sunucuya "liste fiyatı" olarak
# elle girilir (docs/konsol-gorevleri.md §3c); RevenueCat raporu esastır.
# Yıllık ürün MRR'a /12 ile girer (stats_service). Varsayılan 0: fiyat
# girilmeden panel MRR'ı 0 gösterir — uydurma sayı yok.
SUBSCRIPTION_PRICES_USD: dict[str, float] = _fiyat_env(
    "RYTHO_SUB_PRICES_USD",
    {"rytho_plus_monthly": 0.0, "rytho_plus_yearly": 0.0})

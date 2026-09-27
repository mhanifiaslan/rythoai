"""Admin paneli veri servisi (AP-turu → AD-turu) — kullanıcı listesi,
Kullanıcı 360, gelir/kullanım rollup okumaları, dikkat listesi.

Toplama mantığı burada, uçlar (api/admin.py) ince kalır — partner_service
emsali. Her fonksiyon Admin SDK ile okur (kurallar atlanır; istemci bu
koleksiyonlara zaten tamamen kapalı).

## Ölçek doktrini (AD-turu)

Panel binlerce kullanıcıda da AÇILIŞTA TARAMA YAPMAZ:

* Kullanıcı listesi Firestore sorgusudur (arama aynası öneki ya da
  eşitlik süzgeçleri) + `core.cursor` imleciyle sayfalanır; tavan 100.
* Kullanıcı 360 sınırlı okur: son 50 gelir olayı, son 30 kullanım kaydı,
  toplamlar `private/usageTotals` + `private/revenueTotals` dokümanından,
  ortak edinme maliyeti `partnerQualifications/{uid}` TEK dokümanından
  (kimlik uid olduğu için sorgu değil doğrudan okuma).
* Ekonomi / gelir / kullanım özetleri `adminEconomics` ve `adminStats`
  rollup'larından birleştirilir (stats_service); canlı tarama yalnız
  sahibin "yeniden hesapla"sında.

## Mahremiyet çizgisi (Kullanıcı 360)

Sayılar evet, İÇERİK hayır: sohbet mesajları, hafıza olguları ve günlük
metinleri bu servisten ASLA dönmez — yalnız adetleri döner. `fcmToken`
değeri de dönmez (`hasPush` bool'a iner): panelin işine token değil
"push alabiliyor mu" yarar ve token bir yetenek anahtarıdır.
"""
from __future__ import annotations

import datetime as dt
import logging
import os
from typing import Any

from core import app_gate, cache, config
from core import cursor as cursor_codec
from core import firestore as firestore_client
from core import wallet
from services import search_mirror, stats_service
from services.stats_service import _count, _iter_users

logger = logging.getLogger(__name__)

#: Liste satırına giren profil alanları — ham doğum saati/dakikası gibi
#: alanlar listede gereksiz; 360 detayında profil zaten tam döner.
_LIST_FIELDS = ("displayName", "email", "username", "plan", "language",
                "platform", "appBuild", "createdAt", "lastSeenDaily",
                "streakCount", "authDisabled", "onboardingCompleted")

_SORT_FIELDS = {"createdAt", "lastSeenDaily", "streakCount"}

#: Arama alanı (panel adı) -> ayna alanı (services/search_mirror).
_SEARCH_FIELDS = {"eposta": "emailLower", "kullanici": "usernameLower",
                  "ad": "nameLower"}

#: Tek sayfada dönen en fazla satır — daha fazlası imleçle.
LIST_LIMIT_MAX = 100

#: Ekonomi tablosunda ad ad dönen en fazla kullanıcı.
ECONOMICS_TOP_N = 200

#: Ekonomi birleşiminin önbellek ömrü (saniye) — rollup gecede bir kez
#: değişir, panel 10 dakikalık bayatlığı kaldırır.
ECON_CACHE_TTL = 600

#: Mağaza kesintisi tahmini (Play/App Store standart %15 küçük işletme
#: oranı). Panelde her yerde "tahmini" etiketiyle sunulur — gerçek
#: hakediş mağaza raporundan gelir.
STORE_CUT = 0.15

#: Ortak (affiliate) ödülünün varsayılan USD/₺ kuru. Değer uydurma DEĞİL:
#: `docs/maliyet-calismasi.md` başındaki kur varsayımıyla (1 USD ≈ 42 ₺)
#: birebir aynı — iki yerde iki farklı kur, iki farklı marj demek olurdu.
USD_TRY_DEFAULT = 42.0

#: Kurun kabul edilen bandı. Bu bir TAHMİN aralığı değil YAZIM HATASI
#: kapısıdır — gerekçesi `partner_service.MAX_REWARD_TRY` tavanıyla birebir
#: aynı: alan gerçek para hesabına giriyor ve yanlış yazılmış bir basamak
#: hiçbir ekranda göze çarpmıyor.
#:
#: NEDEN 5 ve 200: sınırlar belgedeki varsayımın (42) bir büyüklük
#: mertebesi altı ve üstü seçildi — kur uygulamanın var olduğu dönemde hiç
#: 30'un altına inmedi, 200 ise belgedeki 40-45 duyarlılık bandının ve
#: makul bir yakın vade tahmininin çok üstünde. Yani gerçek bir değer
#: kaybı (60, 80, hatta 120) bandan GEÇER — kapıya yalnız iki bilinen
#: yazım hatası takılır: 42 yerine "4,2" (ondalık ayracı kayması) ve 42
#: yerine "420" (fazladan sıfır). Bant bunları geçirseydi ₺30 ödül panelde
#: $7,14 ya da $0,07 olarak düşülür, sahibi kârlı programı zararlı ya da
#: bedava sanardı — iki yönde de hiçbir yerde hata görünmeden.
USD_TRY_MIN = 5.0
USD_TRY_MAX = 200.0


def _kur_oku() -> float:
    """`RYTHO_USD_TRY` → USD/₺ kuru; sayıya çevrilemezse 0.0 ("bilinmiyor").

    NEDEN kur KODA SABİT DEĞİL: ortak ödülü ₺, gelir ve AI maliyeti $
    cinsinden ölçülüyor; ikisini çıkarmak için kur ŞART. Kuru kaynağa
    gömmek onu deploy'a kilitler ve kur oynadığında panel marjı sessizce
    yanlışa kayar — hiçbir yerde hata görünmez.

    Kalıcılık: bu env `infra/deploy-backend.ps1`'in `--set-env-vars`
    satırında ARTIK VAR (varsayılan değeriyle, 2026-09-27). Satır mevcut
    değişkenleri TÜMÜYLE değiştirdiği için gcloud'la ELLE verilen kur bir
    sonraki deploy'da yine SESSİZCE silinir — `RYTHO_MIN_BUILD` yarasının
    aynısı. Kuru kalıcı değiştirmenin tek yolu o satırı düzenlemektir;
    "env ile ezilir" yalnız TEK deploy dönemi için doğrudur.

    Üç farklı girdi, üç farklı sonuç — ayrım kasıtlı:

    * **Boş env** bozuk DEĞİL, yalnız "ayarlanmadı"dır → belgedeki
      varsayım (`USD_TRY_DEFAULT`).
    * **Sayıya çevrilemeyen ya da pozitif olmayan değer** hiçbir okumayla
      kur DEĞİLDİR → 0.0, yani panelde "—". Burada varsayılana düşmek
      (`config._int_env`'in fail-open davranışı) YANLIŞ olurdu: sürüm
      kapısı fail-open olmak zorundadır çünkü yanlış bir env tüm
      kullanıcıları kilitleyebilir; burada risk ters yönde — kimsenin
      niyet etmediği bir kurla hesaplanmış sayıyı "marj" adıyla sunmak,
      "—" göstermekten daha kötüdür (ölçülmeyen söylenmez).
    * **Bandın (`USD_TRY_MIN`..`USD_TRY_MAX`) dışındaki pozitif değer**
      bir kur yazma DENEMESİDİR, yalnız basamağı kaymıştır → uyarı logu +
      varsayılan. Operatörün ne demek istediği belli olduğu için burada
      belgelenmiş varsayım "—"den iyi bir cevaptır; ölçülmeyen bir şey de
      söylenmiş olmaz, çünkü varsayım belgede yazılı.
    """
    ham = os.getenv("RYTHO_USD_TRY", "").strip()
    if not ham:
        return USD_TRY_DEFAULT
    try:
        # Virgüllü ondalık (Türkçe klavye alışkanlığı) da kabul: "42,5".
        kur = float(ham.replace(",", "."))
    except ValueError:
        logger.warning("RYTHO_USD_TRY çözümlenemedi (%r) — ortak maliyeti ve "
                       "marj panelde '—' gösterilecek.", ham)
        return 0.0
    if kur <= 0:
        logger.warning("RYTHO_USD_TRY pozitif değil (%r) — ortak maliyeti ve "
                       "marj panelde '—' gösterilecek.", ham)
        return 0.0
    # Bant kontrolü pozitiflik kapısından SONRA: "kur değil" (0, negatif)
    # ile "kur ama basamağı kaymış" (4,2 / 420) iki ayrı olgudur ve iki
    # ayrı sonuç doğurur. Sıra bozulursa 0 ve negatif değerler de
    # varsayılana düşer, yani ölçülmemiş bir marj ölçülmüş gibi sunulur.
    if not (USD_TRY_MIN <= kur <= USD_TRY_MAX):
        logger.warning("RYTHO_USD_TRY makul bandın dışında (%r; kabul edilen "
                       "%.0f-%.0f) — yazım hatası varsayılıyor, kur %.1f "
                       "kullanılacak.", ham, USD_TRY_MIN, USD_TRY_MAX,
                       USD_TRY_DEFAULT)
        return USD_TRY_DEFAULT
    return kur


#: Marj hesabında kullanılan kur. Modül yüklenirken bir kez okunur
#: (Cloud Run env'i deploy'da sabitlenir); testler bunu doğrudan
#: monkeypatch eder, emsal `ECONOMICS_TOP_N`.
USD_TRY = _kur_oku()

#: Rollup bu kadar saatten eskiyse "bayat" (gecelik iş kaçmış demektir).
ROLLUP_STALE_HOURS = 30

#: economics() tarafından kullanılan önbellek anahtarları — recompute
#: sonrası temizlenmek için (core.cache anahtar sayamaz).
_ECON_CACHE_KEYS: set[str] = set()


def _client():
    client = firestore_client.get_client()
    if client is None:
        raise RuntimeError("Firestore erişilemiyor.")
    return client


def _ts(value: Any) -> float:
    try:
        return value.timestamp()
    except AttributeError:
        return float(value or 0) if isinstance(value, (int, float)) else 0.0


def _satir(uid: str, veri: dict[str, Any]) -> dict[str, Any]:
    """Liste satırı: yalnız `_LIST_FIELDS` + türetilmiş bool'lar. fcmToken
    ASLA — `hasPush`a iner."""
    satir = {alan: veri.get(alan) for alan in _LIST_FIELDS}
    satir["uid"] = uid
    satir["hasPush"] = bool(veri.get("fcmToken"))
    satir["authDisabled"] = bool(veri.get("authDisabled"))
    # Panel rozeti `onboardingCompleted === false` arıyor; alan onboarding'in
    # SON adımında yazıldığı için akışı yarım bırakan kullanıcıda HİÇ yok ve
    # ham `null` rozeti sessizce düşürüyordu — oysa operatöre gösterilmesi
    # gereken tam o kullanıcı (yokluk = yarım).
    satir["onboardingCompleted"] = veri.get("onboardingCompleted") is True
    return satir


def _sayfa(sorgu, limit: int, imlec_deger) -> tuple[list, str | None]:
    """`limit+1` okur; fazla satır varsa son GÖSTERİLEN satırdan imleç.

    `imlec_deger(anlik)` → imlecin değer listesi. İmleç ham sayfanın
    konumundan üretilir; sayfa içi süzgeçler onu değiştirmez (aksi halde
    süzülen satırların ötesi atlanırdı).
    """
    anliklar = list(sorgu.stream())
    sonraki = None
    if len(anliklar) > limit:
        anliklar = anliklar[:limit]
        sonraki = cursor_codec.encode(imlec_deger(anliklar[-1]))
    return anliklar, sonraki


def _tarih_str(value: Any) -> str:
    if hasattr(value, "isoformat"):
        return value.isoformat()[:10]
    return str(value)[:10]


def list_users(q: str = "", alan: str = "ad", plan: str | None = None,
               language: str | None = None, platform: str | None = None,
               disabled: bool | None = None, active_since: Any = None,
               below_build: int | None = None, sort: str = "createdAt",
               limit: int = 50, cursor: str | None = None) -> dict[str, Any]:
    """Kullanıcı listesi — iki mod, tek imleç (AD4).

    **Arama modu** (`q` dolu): ayna alanında önek aralığı
    (`>= nq`, `< nq + '\\uf8ff'`), `order_by(alan)`; eşitlik süzgeçleri
    SAYFA İÇİNDE uygulanır (Firestore aralık + eşitlik her kombinasyona
    indeks isterdi). Sayfa süzülünce boş dönebilir ama `nextCursor`
    dolu kalır — panel "daha fazla"ya devam eder.

    **Süzgeç modu**: eşitlikler (`plan`, `language`, `platform`,
    `authDisabled==true`) + `order_by(sort DESC, __name__ DESC)`.
    `active_since` → `lastSeenDaily >= tarih` ve sıralama
    `lastSeenDaily`'ye ZORLANIR; `below_build` → `appBuild < n`, sıralama
    `appBuild`'e zorlanır ve DİĞER süzgeçLERLE YASAK (her kombinasyon
    ayrı composite indeks isterdi) → ValueError (uç 400).

    `limit` 1..100'e kırpılır. Bozuk imleç ValueError.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    if alan not in _SEARCH_FIELDS:
        raise ValueError("Bilinmeyen arama alanı.")
    if sort not in _SORT_FIELDS:
        raise ValueError("Bilinmeyen sıralama.")
    limit = max(1, min(int(limit or 50), LIST_LIMIT_MAX))
    imlec = cursor_codec.decode(cursor) if cursor else None
    q = (q or "").strip()
    client = _client()
    users = client.collection("users")

    if active_since is not None:
        active_since = _tarih_str(active_since)
    if below_build is not None:
        below_build = int(below_build)

    def esitlik_uyar(veri: dict[str, Any]) -> bool:
        if plan and veri.get("plan") != plan:
            return False
        if language and veri.get("language") != language:
            return False
        if platform and veri.get("platform") != platform:
            return False
        if disabled is True and veri.get("authDisabled") is not True:
            return False
        if active_since and str(veri.get("lastSeenDaily") or "") < active_since:
            return False
        if below_build is not None:
            sb = app_gate.parse_build(veri.get("appBuild"))
            if not (0 < sb < below_build):
                return False
        return True

    if q:
        ayna = _SEARCH_FIELDS[alan]
        nq = search_mirror.normalize(q)
        sorgu = (users.where(filter=FieldFilter(ayna, ">=", nq))
                 .where(filter=FieldFilter(ayna, "<", nq + ""))
                 .order_by(ayna))
        if imlec:
            sorgu = sorgu.start_after(imlec)
        anliklar, sonraki = _sayfa(
            sorgu.limit(limit + 1), limit,
            lambda a: [(a.to_dict() or {}).get(ayna), a.id])
        satirlar = [_satir(a.id, a.to_dict() or {}) for a in anliklar
                    if esitlik_uyar(a.to_dict() or {})]
        return {"users": satirlar, "nextCursor": sonraki, "mode": "search"}

    if below_build is not None and any(
            x is not None and x is not False
            for x in (plan, language, platform, disabled, active_since)):
        raise ValueError("belowBuild diğer süzgeçlerle birlikte kullanılamaz.")

    sorgu = users
    for alan_adi, deger in (("plan", plan), ("language", language),
                            ("platform", platform)):
        if deger:
            sorgu = sorgu.where(filter=FieldFilter(alan_adi, "==", deger))
    if disabled is True:
        # Yalnız `true`: alanı olmayan eski dokümanlar `==false`a düşmez;
        # "devre dışı değil" = süzgeç yok (sabit karar).
        sorgu = sorgu.where(filter=FieldFilter("authDisabled", "==", True))
    if active_since:
        sorgu = sorgu.where(filter=FieldFilter("lastSeenDaily", ">=",
                                               active_since))
        sort = "lastSeenDaily"
    if below_build is not None:
        sorgu = sorgu.where(filter=FieldFilter("appBuild", "<", below_build))
        sort = "appBuild"
    sorgu = (sorgu.order_by(sort, direction="DESCENDING")
             .order_by("__name__", direction="DESCENDING"))
    if imlec:
        sorgu = sorgu.start_after(imlec)
    anliklar, sonraki = _sayfa(
        sorgu.limit(limit + 1), limit,
        lambda a: [(a.to_dict() or {}).get(sort), a.id])
    satirlar = [_satir(a.id, a.to_dict() or {}) for a in anliklar]
    return {"users": satirlar, "nextCursor": sonraki, "mode": "filter"}


def _private_doc(client, uid: str, ad: str) -> dict[str, Any] | None:
    """`users/{uid}/private/{ad}`; doküman yoksa None, okunamazsa None."""
    try:
        anlik = (client.collection("users").document(uid)
                 .collection("private").document(ad).get())
        return (anlik.to_dict() or {}) if getattr(anlik, "exists", False) else None
    except Exception as exc:
        logger.warning("private/%s okunamadı (%s): %s", ad, uid, exc)
        return None


def _env_net(toplamlar: dict[str, Any] | None, env: str) -> float:
    kova = (toplamlar or {}).get(env) or {}
    return round(float(kova.get("grossUsd") or 0)
                 - float(kova.get("refundsUsd") or 0), 4)


def _ortak_maliyeti(client, uid: str) -> tuple[float, float, str | None]:
    """Bu kullanıcının ortak edinme maliyeti → (USD, ₺, hakediş durumu).

    Kaynak `partnerQualifications/{uid}` — doküman kimliği UID olduğu için
    TEK okuma yeter, sorgu gerekmez (partner_service bunu bilinçli böyle
    kurdu: "kullanıcı başına tek ödül" yapısal garanti).

    NEDEN `pending` de sayılıyor: ödül tutarı hakediş ânında dokümana
    DONDURULMUŞ gerçek bir ₺ yükümlülüktür; `pending` yalnız 15 günlük
    iade penceresinin dolmasını bekler. Saymazsak her atıflı abone
    hayatının ilk 15 gününde olduğundan kârlı görünür — üstelik sahibin
    o aboneye tam o günlerde baktığı pencerede. `void` ASLA sayılmaz:
    orada yükümlülük gerçekten ortadan kalkmıştır (iade/erken sona erme).

    Kur bilinmiyorsa USD değeri −1 döner: ₺ yükümlülük VAR ama dolara
    çevrilemiyor demektir ve çağıran marjı da −1'e (panelde "—") düşürür.
    ₺ tutarı yine ham hâliyle döner — ölçülen sayı, çevrilemese de
    kendi birimiyle dürüsttür. Okuma düşerse ya da `rewardTry`
    çözümlenemezse İKİSİ de −1'dir: orada ₺ tutarı da ölçülmemiştir.
    """
    try:
        anlik = client.collection("partnerQualifications").document(uid).get()
    except Exception as exc:
        # Okuma düşerse 360 düşmez; maliyet "bilinmiyor" olur.
        logger.warning("partnerQualifications okunamadı (%s): %s", uid, exc)
        return -1.0, -1.0, None
    if not getattr(anlik, "exists", False):
        return 0.0, 0.0, None
    veri = anlik.to_dict() or {}
    durum = str(veri.get("status") or "pending")
    if durum == "void":
        return 0.0, 0.0, durum
    try:
        odul_try = float(veri.get("rewardTry") or 0)
    except (TypeError, ValueError):
        # Çözümlenemeyen tutar "sıfır maliyet" DEĞİLDİR: hakediş dokümanı
        # var, yani yükümlülük var; yalnız tutarı okunamıyor. 0 dönmek
        # marjı olduğundan yüksek gösterir ve hiçbir yerde hata görünmez —
        # "bilinmiyor" sentinel'i (−1, panelde "—") dürüst olanıdır.
        # Somut senaryo: Firestore'da elle düzeltilen bir kayıtta
        # `rewardTry: "30,00"` (Türkçe ondalık, dize).
        logger.warning("partnerQualifications/%s rewardTry çözümlenemedi "
                       "(%r) — maliyet 'bilinmiyor'.",
                       uid, veri.get("rewardTry"))
        return -1.0, -1.0, durum
    if odul_try <= 0:
        return 0.0, 0.0, durum
    if USD_TRY <= 0:
        return -1.0, round(odul_try, 2), durum
    return round(odul_try / USD_TRY, 4), round(odul_try, 2), durum


def user_360(uid: str) -> dict[str, Any] | None:
    """Tek kullanıcının destek görünümü; kullanıcı yoksa None (AD6).

    Sınırlı okuma: gelir olayları `uid + at DESC` 50 (tüm türler →
    `timeline`; parasal olanlar ayrıca `revenueEvents`), kullanım TEK
    sorgu 30, toplamlar rollup dokümanlarından (`usageTotals`,
    `revenueTotals`); rollup yoksa ekonomi alanları −1 (panel "—").
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    client = _client()

    anlik = client.collection("users").document(uid).get()
    if not getattr(anlik, "exists", False):
        return None
    profil = anlik.to_dict() or {}
    profil["uid"] = uid
    profil["hasPush"] = bool(profil.pop("fcmToken", None))
    # 360'taki rozet de `=== false` arıyor: alan yoksa anahtar hiç gelmez ve
    # "onboarding yarım" yanmaz.
    profil["onboardingCompleted"] = profil.get("onboardingCompleted") is True

    # Kimlik tarafı bayrağı: ayna alanı varsa (AD4, backfill/disable ucu
    # yazar) Firebase Auth'a gidilmez; yoksa canlı okunur, o da düşerse
    # None — panel "?" gösterir.
    if "authDisabled" not in profil:
        try:
            from firebase_admin import auth as fb_auth
            profil["authDisabled"] = bool(fb_auth.get_user(uid).disabled)
        except Exception:
            profil["authDisabled"] = None

    subscription = _private_doc(client, uid, "subscription") or {}
    quota = _private_doc(client, uid, "quota") or {}
    attribution = _private_doc(client, uid, "attribution") or {}
    usage_totals = _private_doc(client, uid, "usageTotals")
    revenue_totals = _private_doc(client, uid, "revenueTotals")

    device_ham = _private_doc(client, uid, "device") or {}
    device = {k: device_ham.get(k)
              for k in ("platform", "claimedAt", "lastSeenAt")}
    # Kimlik MASKELİ (son 6): panel "kilit var mı, ne zamandan beri"
    # sorusuna cevap verir; tam kimlik başlık olarak taklit edilebilir,
    # dönmez. Sıfırlama: POST /admin/users/{uid}/device/release.
    kimlik = device_ham.get("deviceId")
    device["deviceId"] = f"…{str(kimlik)[-6:]}" if kimlik else None

    # Bildirim META'sı: gövde/soru metinleri (dailyBody vb.) DÖNMEZ.
    notif_ham = _private_doc(client, uid, "notifications") or {}
    notifications = {k: v for k, v in notif_ham.items()
                     if k.endswith("LastSent") or k == "dailyTheme"}

    cuzdan = wallet.get_wallet(uid)

    ledger: list[dict[str, Any]] = []
    try:
        sorgu = (client.collection("users").document(uid)
                 .collection("private").document("wallet")
                 .collection("ledger")
                 .order_by("at", direction="DESCENDING").limit(50))
        for kayit in sorgu.stream():
            veri = kayit.to_dict() or {}
            veri["id"] = kayit.id
            ledger.append(veri)
    except Exception as exc:
        logger.warning("Ledger okunamadı (%s): %s", uid, exc)

    # Zaman çizelgesi: parasal + parasal olmayan son 50 olay (composite
    # indeks uid+at; yoksa boş kalır, 360 düşmez).
    zaman_cizelgesi: list[dict[str, Any]] = []
    try:
        for kayit in (client.collection("revenueEvents")
                      .where(filter=FieldFilter("uid", "==", uid))
                      .order_by("at", direction="DESCENDING")
                      .limit(50).stream()):
            veri = kayit.to_dict() or {}
            veri["id"] = kayit.id
            zaman_cizelgesi.append(veri)
    except Exception as exc:
        logger.warning("revenueEvents okunamadı (%s): %s", uid, exc)
    gelir = [o for o in zaman_cizelgesi if o.get("monetary") is not False]

    kullanim: list[dict[str, Any]] = []
    kullanim_sayfa: dict[str, Any] = {"calls": 0, "estCostUsd": 0.0,
                                      "byFeature": {}}
    try:
        sorgu = (client.collection("usageEvents")
                 .where(filter=FieldFilter("uid", "==", uid))
                 .order_by("at", direction="DESCENDING").limit(30))
        for kayit in sorgu.stream():
            veri = kayit.to_dict() or {}
            kullanim.append(veri)
            kullanim_sayfa["calls"] += 1
            kullanim_sayfa["estCostUsd"] = round(
                kullanim_sayfa["estCostUsd"]
                + float(veri.get("estCostUsd") or 0), 6)
            oz = str(veri.get("feature") or "unknown")
            kullanim_sayfa["byFeature"][oz] = (
                kullanim_sayfa["byFeature"].get(oz, 0) + 1)
    except Exception as exc:
        # Composite indeks henüz kurulmadıysa buraya düşer — 360 düşmez.
        logger.warning("usageEvents okunamadı (%s): %s", uid, exc)

    # Telefon doğrulama denemeleri (SMS-turu). "SMS gelmiyor" başvurusu
    # geldiğinde ilk bakılacak yer burası: hangi ülkeye, hangi maskeli
    # numaraya, hangi aşamada. Composite indeks yoksa sessizce boş kalır.
    telefon: list[dict[str, Any]] = []
    try:
        for kayit in (client.collection("phoneAttempts")
                      .where(filter=FieldFilter("uid", "==", uid))
                      .order_by("at", direction="DESCENDING")
                      .limit(20).stream()):
            telefon.append(kayit.to_dict() or {})
    except Exception as exc:
        logger.warning("phoneAttempts okunamadı (%s): %s", uid, exc)

    sayilar = {
        "conversations": _count(client.collection("users").document(uid)
                                .collection("conversations")),
        "friends": -1,
    }
    try:
        sayilar["friends"] = _count(
            client.collection("users").document(uid).collection("friends")
            .where(filter=FieldFilter("status", "==", "accepted")))
    except Exception:
        pass

    # Kullanıcı ekonomisi (AD6): rollup dokümanlarından — tarama YOK.
    # Rollup yoksa −1: "0" ile "bilinmiyor" panelde ayrışır (backfill
    # betikleri tamamlar).
    if revenue_totals is None:
        gelir_prod = gelir_sandbox = -1.0
    else:
        gelir_prod = _env_net(revenue_totals, "PRODUCTION")
        gelir_sandbox = _env_net(revenue_totals, "SANDBOX")
    if usage_totals is None:
        maliyet, cagri = -1.0, -1
    else:
        maliyet = round(float(usage_totals.get("estCostUsd") or 0), 6)
        cagri = int(usage_totals.get("calls") or 0)
    # Ortak edinme maliyeti (OP13): atıflı bir abone ortağa GERÇEK bir ₺
    # ödemesi doğurur. Düşülmediği sürece marj olduğundan yüksek çıkar ve
    # sahibi fiyat/pazarlama kararını o sayıyla verir — sessiz bir kusur,
    # çünkü hiçbir yerde hata görünmez. Kapsam uyuyor: `revenueTotals` da,
    # ödül de kullanıcının ÖMÜR BOYU toplamıdır (ödül kullanıcı başına bir
    # kez doğar), yani iki taraf aynı pencereye bakıyor.
    ortak_usd, ortak_try, ortak_durum = _ortak_maliyeti(client, uid)
    marj = (round(gelir_prod * (1 - STORE_CUT) - maliyet - ortak_usd, 4)
            if gelir_prod >= 0 and maliyet >= 0 and ortak_usd >= 0 else -1.0)
    ekonomi = {
        "revenueUsd": round(gelir_prod, 2) if gelir_prod >= 0 else -1,
        "sandboxUsd": round(gelir_sandbox, 2) if gelir_sandbox >= 0 else -1,
        "aiCostUsd": maliyet,
        "calls": cagri,
        "marginUsd": marj,
        "storeCutRate": STORE_CUT,
        # Ortak maliyeti AYRI alan: panel neyin düşüldüğünü gösterebilsin,
        # yoksa marjdaki fark açıklanamaz bir eksilme olarak görünür.
        # ₺ tutarı da dönüyor çünkü ölçülen birim odur — dolara çevrilmiş
        # hâl bir TÜRETMEdir ve hangi kurla türetildiği söylenmeden
        # sunulmamalı (`usdTryRate`).
        "partnerCostUsd": ortak_usd,
        "partnerRewardTry": ortak_try,
        "partnerStatus": ortak_durum,
        "usdTryRate": USD_TRY if USD_TRY > 0 else -1,
    }

    return {
        "profile": profil,
        "subscription": subscription,
        "wallet": cuzdan,
        "ledger": ledger,
        "quota": quota,
        "attribution": attribution,
        "device": device,
        "notifications": notifications,
        "revenueEvents": gelir,
        "timeline": zaman_cizelgesi,
        "usage": {"recent": kullanim, **kullanim_sayfa,
                  "totals": usage_totals},
        "revenueTotals": revenue_totals,
        "phoneAttempts": telefon,
        "economics": ekonomi,
        "counts": sayilar,
    }


# ---------------------------------------------------------------------------
# Rollup okumaları (AD7): adminEconomics + adminStats — tarama YOK
# ---------------------------------------------------------------------------

def _kullanici_adlari(client, uidler: list[str]) -> dict[str, dict[str, Any]]:
    """`users` get_all ile toplu ad/e-posta; düşerse boş (satır uid'li kalır)."""
    if not uidler:
        return {}
    try:
        refs = [client.collection("users").document(u) for u in uidler]
        sonuc: dict[str, dict[str, Any]] = {}
        for anlik in client.get_all(refs):
            if getattr(anlik, "exists", False):
                veri = anlik.to_dict() or {}
                sonuc[anlik.id] = {"displayName": veri.get("displayName"),
                                   "email": veri.get("email")}
        return sonuc
    except Exception as exc:
        logger.warning("Kullanıcı adları okunamadı: %s", exc)
        return {}


def _economics_docs(client, days: int) -> list[dict[str, Any]]:
    sorgu = (client.collection("adminEconomics")
             .order_by("date", direction="DESCENDING")
             .limit(max(1, min(int(days), 365))))
    return [a.to_dict() or {} for a in sorgu.stream()]


def clear_economics_cache() -> None:
    """recompute sonrası: bilinen anahtarlar süresi dolmuş yazılır
    (core.cache silme sunmaz; sıfır ömürlü yazım aynı işi görür)."""
    anahtarlar = set(_ECON_CACHE_KEYS)
    for d in (7, 30, 90, 180, 365):
        for env in stats_service.ENVIRONMENTS:
            anahtarlar.add(f"adm-econ-{d}-{env}")
    for anahtar in anahtarlar:
        try:
            cache.set(anahtar, None, ttl_seconds=-1)
        except Exception:
            pass
    _ECON_CACHE_KEYS.clear()


def economics(days: int = 90, env: str = "PRODUCTION") -> dict[str, Any]:
    """Kullanıcı bazlı gelir/maliyet/marj tablosu — rollup birleşimi (AD7).

    `adminEconomics/{gün}` dokümanları (son `days` gün) bellekte
    toplanır; top-200 satır + `others` toplamda. `env` hangi ortamın
    gelirinin marja gireceğini seçer; iki ortam da satırda görünür
    (`revenueUsd` = PRODUCTION, `sandboxUsd` = SANDBOX). 600 s önbellek.

    Kâr formülü TAHMİNİDİR ve dürüstçe etiketlenir:
    marj = gelir × (1 − mağaza kesintisi) − tahmini AI maliyeti.

    ⚠️ Bu TABLONUN marjı ortak (affiliate) edinme maliyetini İÇERMEZ —
    yalnız Kullanıcı 360 içerir (`partnerCostUsd`). Buraya koymanın tek
    yolu 200 satır için 200 ayrı `partnerQualifications` okuması ya da
    rollup'ı (stats_service) yazarken toplamaktır; birincisi yukarıdaki
    ölçek doktrinini çiğner, ikincisi bu dosyanın işi değil. Yani bu
    tablodaki marj atıflı abonelerde OLDUĞUNDAN YÜKSEKTİR ve tek
    kullanıcının gerçek marjı 360'tan okunur.
    """
    env = str(env or "PRODUCTION").upper()
    anahtar = f"adm-econ-{int(days)}-{env}"
    onbellek = cache.get(anahtar)
    if isinstance(onbellek, dict):
        return onbellek

    client = _client()
    dokumanlar = _economics_docs(client, days)

    birlesik: dict[str, dict[str, float]] = {}
    digerleri = {"r": 0.0, "rs": 0.0, "c": 0.0, "n": 0, "t": 0}
    paylasimli = {"c": 0.0, "n": 0}
    for dok in dokumanlar:
        for uid, k in (dok.get("users") or {}).items():
            kova = birlesik.setdefault(uid, {"r": 0.0, "rs": 0.0, "c": 0.0,
                                             "n": 0, "t": 0})
            for alan in kova:
                kova[alan] = round(kova[alan] + (k.get(alan) or 0), 6)
        for alan in digerleri:
            digerleri[alan] = round(
                digerleri[alan] + ((dok.get("others") or {}).get(alan) or 0), 6)
        for alan in paylasimli:
            paylasimli[alan] = round(
                paylasimli[alan] + ((dok.get("shared") or {}).get(alan) or 0), 6)

    def gelir_secimi(k: dict[str, float]) -> float:
        return k["r"] if env == "PRODUCTION" else k["rs"]

    satirlar: list[dict[str, Any]] = []
    for uid, k in birlesik.items():
        g = gelir_secimi(k)
        satirlar.append({
            "uid": uid,
            "displayName": None,
            "email": None,
            "revenueUsd": round(k["r"], 2),
            "sandboxUsd": round(k["rs"], 2),
            "storeCutUsd": round(g * STORE_CUT, 2) if g > 0 else 0.0,
            "aiCostUsd": round(k["c"], 4),
            "calls": int(k["n"]),
            "tokensSpent": int(k["t"]),
            "marginUsd": round(g * (1 - STORE_CUT) - k["c"], 4),
        })
    satirlar.sort(key=lambda s: (s["marginUsd"], s["aiCostUsd"]), reverse=True)
    satirlar = satirlar[:ECONOMICS_TOP_N]
    adlar = _kullanici_adlari(client, [s["uid"] for s in satirlar])
    for s in satirlar:
        s.update(adlar.get(s["uid"], {}))

    toplam_r = round(sum(k["r"] for k in birlesik.values()) + digerleri["r"], 2)
    toplam_rs = round(sum(k["rs"] for k in birlesik.values()) + digerleri["rs"], 2)
    toplam_c = round(sum(k["c"] for k in birlesik.values()) + digerleri["c"]
                     + paylasimli["c"], 4)
    secili = toplam_r if env == "PRODUCTION" else toplam_rs
    sonuc = {
        "days": int(days),
        "env": env,
        "users": satirlar,
        "totals": {
            "revenueUsd": toplam_r,
            "sandboxUsd": toplam_rs,
            "storeCutUsd": round(max(secili, 0) * STORE_CUT, 2),
            "aiCostUsd": toplam_c,
            "sharedAiCostUsd": round(paylasimli["c"], 4),
            "marginUsd": round(secili * (1 - STORE_CUT) - toplam_c, 4),
            "storeCutRate": STORE_CUT,
            "calls": int(sum(k["n"] for k in birlesik.values())
                         + digerleri["n"] + paylasimli["n"]),
            "tokensSpent": int(sum(k["t"] for k in birlesik.values())
                               + digerleri["t"]),
            "usersCounted": len(birlesik),
        },
        "coverage": {
            "daysFound": len(dokumanlar),
            "oldest": dokumanlar[-1].get("date") if dokumanlar else None,
        },
    }
    cache.set(anahtar, sonuc, ttl_seconds=ECON_CACHE_TTL)
    _ECON_CACHE_KEYS.add(anahtar)
    return sonuc


def _topla(hedef: dict[str, dict[str, Any]],
           kaynak: dict[str, dict[str, Any]] | None) -> None:
    for ad, kova in (kaynak or {}).items():
        h = hedef.setdefault(ad, {"gross": 0.0, "count": 0})
        h["gross"] = round(h["gross"] + float(kova.get("gross") or 0), 4)
        h["count"] += int(kova.get("count") or 0)


def revenue_summary(days: int = 90, env: str = "PRODUCTION") -> dict[str, Any]:
    """Gelir özeti adminStats günlerinden (AD7) — tarama YOK.

    Ortam başına gün serisi, ürün/mağaza/ülke kırılımı, olay sayıları,
    brüt/iade toplamı; MRR/aktif abone/deneme/kohortlar EN SON günün
    fotoğrafından. `byEnv` taşımayan eski dokümanlar 0 katkı yapar.
    """
    env = str(env or "PRODUCTION").upper()
    gunler = stats_service.read_days(days)

    by_day: list[dict[str, Any]] = []
    by_product: dict[str, dict[str, Any]] = {}
    by_store: dict[str, dict[str, Any]] = {}
    by_country: dict[str, dict[str, Any]] = {}
    event_counts: dict[str, int] = {t: 0 for t in stats_service.EVENT_TYPES}
    brut = iade = 0.0
    for dok in reversed(gunler):  # eskiden yeniye
        kova = ((dok.get("revenue") or {}).get("byEnv") or {}).get(env) or {}
        g = float(kova.get("gross") or 0)
        r = float(kova.get("refunds") or 0)
        by_day.append({"date": dok.get("date"), "gross": round(g, 2),
                       "refunds": round(r, 2),
                       "count": int(kova.get("count") or 0)})
        brut += g
        iade += r
        _topla(by_product, kova.get("byProduct"))
        _topla(by_store, kova.get("byStore"))
        _topla(by_country, kova.get("byCountry"))
        for tur, n in (kova.get("eventCounts") or {}).items():
            event_counts[tur] = event_counts.get(tur, 0) + int(n or 0)

    son = gunler[0] if gunler else {}
    subs = son.get("subs") or {}
    return {
        "days": int(days),
        "env": env,
        "byDay": by_day,
        "byProduct": by_product,
        "byStore": by_store,
        "byCountry": by_country,
        "eventCounts": event_counts,
        "grossUsd": round(brut, 2),
        "refundsUsd": round(iade, 2),
        "mrrUsd": float(subs.get("mrrUsd") or 0),
        "mrrByProduct": subs.get("mrrByProduct") or {},
        "activeSubs": int(subs.get("active") if subs.get("active") is not None
                          else -1),
        "trialing": int(subs.get("trialing", subs.get("trial", 0)) or 0),
        "trialExpiring3d": int(subs.get("trialExpiring3d") or 0),
        "cohorts": son.get("cohorts") or {},
        "asOf": son.get("date"),
    }


def revenue_events(env: str = "PRODUCTION", event_type: str | None = None,
                   limit: int = 50, cursor: str | None = None) -> dict[str, Any]:
    """Ham gelir/abonelik olayları sayfası: `environment ==` [+ `eventType
    ==`] + `at DESC, __name__ DESC` + imleç `[at, id]` (AD7)."""
    from google.cloud.firestore_v1.base_query import FieldFilter

    env = str(env or "PRODUCTION").upper()
    limit = max(1, min(int(limit or 50), LIST_LIMIT_MAX))
    imlec = cursor_codec.decode(cursor) if cursor else None
    client = _client()
    sorgu = (client.collection("revenueEvents")
             .where(filter=FieldFilter("environment", "==", env)))
    if event_type:
        sorgu = sorgu.where(filter=FieldFilter("eventType", "==",
                                               str(event_type).upper()))
    sorgu = (sorgu.order_by("at", direction="DESCENDING")
             .order_by("__name__", direction="DESCENDING"))
    if imlec:
        sorgu = sorgu.start_after(imlec)
    anliklar, sonraki = _sayfa(
        sorgu.limit(limit + 1), limit,
        lambda a: [(a.to_dict() or {}).get("at"), a.id])
    olaylar = []
    for a in anliklar:
        veri = a.to_dict() or {}
        veri["id"] = a.id
        olaylar.append(veri)
    return {"events": olaylar, "nextCursor": sonraki, "env": env}


def usage_summary(days: int = 30) -> dict[str, Any]:
    """AI kullanımının gün/özellik/model kırılımı — adminStats'tan (AD7).

    usageEvents TARANMAZ. `topUsers` en son adminEconomics dokümanının
    maliyete göre ilk 20'si (rollup → 360 bağlantısı). Çıktı token'ları
    düşünme token'larını içerir (ikisi de çıktı fiyatından faturalanır).
    """
    gunler = stats_service.read_days(days)
    by_day: dict[str, dict[str, Any]] = {}
    by_feature: dict[str, dict[str, Any]] = {}
    by_model: dict[str, dict[str, Any]] = {}
    toplam = {"calls": 0, "estCostUsd": 0.0, "promptTokens": 0,
              "outputTokens": 0}
    for dok in reversed(gunler):
        ai = dok.get("ai") or {}
        cagri = max(0, int(ai.get("callsToday") or 0))
        maliyet = max(0.0, float(ai.get("estCostToday") or 0))
        by_day[str(dok.get("date"))] = {"calls": cagri,
                                        "estCostUsd": round(maliyet, 6)}
        toplam["calls"] += cagri
        toplam["estCostUsd"] = round(toplam["estCostUsd"] + maliyet, 6)
        for oz, n in (ai.get("byFeature") or {}).items():
            kova = by_feature.setdefault(oz, {"calls": 0, "estCostUsd": 0.0,
                                              "promptTokens": 0,
                                              "outputTokens": 0})
            kova["calls"] += int(n or 0)
        for oz, bedel in (ai.get("costByFeature") or {}).items():
            kova = by_feature.setdefault(oz, {"calls": 0, "estCostUsd": 0.0,
                                              "promptTokens": 0,
                                              "outputTokens": 0})
            kova["estCostUsd"] = round(kova["estCostUsd"] + float(bedel or 0), 6)
        for oz, tk in (ai.get("tokensByFeature") or {}).items():
            kova = by_feature.setdefault(oz, {"calls": 0, "estCostUsd": 0.0,
                                              "promptTokens": 0,
                                              "outputTokens": 0})
            kova["promptTokens"] += int(tk.get("prompt") or 0)
            kova["outputTokens"] += int(tk.get("output") or 0)
            toplam["promptTokens"] += int(tk.get("prompt") or 0)
            toplam["outputTokens"] += int(tk.get("output") or 0)
        for md, mk in (ai.get("byModel") or {}).items():
            kova = by_model.setdefault(md, {"calls": 0, "estCostUsd": 0.0})
            kova["calls"] += int(mk.get("calls") or 0)
            kova["estCostUsd"] = round(kova["estCostUsd"]
                                       + float(mk.get("cost") or 0), 6)

    ustler: list[dict[str, Any]] = []
    try:
        client = _client()
        son = _economics_docs(client, 1)
        kullanicilar = (son[0].get("users") or {}) if son else {}
        sirali = sorted(kullanicilar.items(),
                        key=lambda kv: float(kv[1].get("c") or 0), reverse=True)[:20]
        adlar = _kullanici_adlari(client, [uid for uid, _ in sirali])
        for uid, k in sirali:
            ustler.append({"uid": uid, "aiCostUsd": round(float(k.get("c") or 0), 6),
                           "calls": int(k.get("n") or 0),
                           **adlar.get(uid, {"displayName": None, "email": None})})
    except Exception as exc:
        logger.warning("topUsers okunamadı: %s", exc)

    return {"days": int(days), "byDay": by_day, "byFeature": by_feature,
            "byModel": by_model, "totals": toplam, "topUsers": ustler,
            # Panel jeton bedellerini buradan gösterir — sunucu gerçeği,
            # panel hiçbir bedeli hardcode etmez.
            "costs": dict(wallet.TOKEN_COSTS)}


# ---------------------------------------------------------------------------
# Dikkat listesi (AD7): panel zili
# ---------------------------------------------------------------------------

def attention() -> list[dict[str, Any]]:
    """Operatörün bugün bakması gereken sayılar; her kalem kendi
    try'ında — biri düşerse listeden düşer, zil susmaz.

    Kalemler: bugün başarısız push, 7 günde ödeme sorunu, 3 gün içinde
    biten deneme, eşiğin altındaki istemci, devre dışı hesap, bayat
    rollup (>30 saat). Sıfır olan kalem listelenmez.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    simdi = dt.datetime.now(dt.timezone.utc)
    kalemler: list[dict[str, Any]] = []

    def ekle(tur: str, sayi: int, rota: str, seviye: str) -> None:
        if sayi and sayi > 0:
            kalemler.append({"tur": tur, "sayi": int(sayi), "rota": rota,
                             "seviye": seviye})

    try:
        client = _client()
    except RuntimeError:
        return kalemler

    try:
        bugun = simdi.date().isoformat()
        basarisiz = 0
        for tur in ("daily", "midday", "checkin", "streak"):
            anlik = client.collection("notifyRuns").document(f"{bugun}-{tur}").get()
            if getattr(anlik, "exists", False):
                basarisiz += int((anlik.to_dict() or {}).get("failed") or 0)
        ekle("failedPushesToday", basarisiz, "#/bildirimler", "uyari")
    except Exception as exc:
        logger.warning("attention/push: %s", exc)

    gunler: list[dict[str, Any]] = []
    try:
        gunler = stats_service.read_days(7)
        # Yalnız PRODUCTION: sandbox ödeme sorunu test artığıdır; panel de
        # varsayılan olarak PRODUCTION gösterir.
        sorun = 0
        for dok in gunler:
            kova = ((dok.get("revenue") or {}).get("byEnv") or {}).get("PRODUCTION") or {}
            sorun += int((kova.get("eventCounts") or {}).get("BILLING_ISSUE") or 0)
        ekle("billingIssues7d", sorun, "#/gelir", "uyari")
    except Exception as exc:
        logger.warning("attention/billing: %s", exc)

    try:
        uc_gun = simdi + dt.timedelta(days=3)
        n = _count(client.collection_group("private")
                   .where(filter=FieldFilter("isTrial", "==", True))
                   .where(filter=FieldFilter("expiresAt", ">=", simdi))
                   .where(filter=FieldFilter("expiresAt", "<", uc_gun)))
        ekle("trialsExpiring3d", n, "#/kullanicilar?plan=trial", "bilgi")
    except Exception as exc:
        logger.warning("attention/trial: %s", exc)

    try:
        esik = app_gate.current_min_build()
        if esik > 0:
            n = app_gate.count_below(esik)
            ekle("belowMin", int(n or 0), "#/sistem", "bilgi")
    except Exception as exc:
        logger.warning("attention/build: %s", exc)

    try:
        n = _count(client.collection("users")
                   .where(filter=FieldFilter("authDisabled", "==", True)))
        ekle("disabledTotal", n, "#/kullanicilar?disabled=true", "bilgi")
    except Exception as exc:
        logger.warning("attention/disabled: %s", exc)

    try:
        n = _count(client.collection("feedback")
                   .where(filter=FieldFilter("status", "==", "new")))
        ekle("newFeedback", n, "#/geribildirim?status=new", "bilgi")
    except Exception as exc:
        logger.warning("attention/feedback: %s", exc)

    try:
        son = gunler[0] if gunler else None
        if son is None:
            gunler = stats_service.read_days(1)
            son = gunler[0] if gunler else None
        damga = (son or {}).get("generatedAt")
        saat = ((simdi.timestamp() - _ts(damga)) / 3600
                if damga is not None else ROLLUP_STALE_HOURS * 24)
        if saat > ROLLUP_STALE_HOURS:
            ekle("rollupStale", int(saat), "#/sistem", "hata")
    except Exception as exc:
        logger.warning("attention/rollup: %s", exc)

    return kalemler


def notify_runs(days: int = 7) -> list[dict[str, Any]]:
    """notifyRuns dokümanları — `date` ALANINA göre tersten (adminStats
    dersi: `__name__` DESC otomatik indekslenmiyor)."""
    client = _client()
    kayitlar: list[dict[str, Any]] = []
    try:
        sorgu = (client.collection("notifyRuns")
                 .order_by("date", direction="DESCENDING")
                 .limit(days * 4 + 8))
        for anlik in sorgu.stream():
            veri = anlik.to_dict() or {}
            veri["id"] = anlik.id
            kayitlar.append(veri)
    except Exception as exc:
        logger.warning("notifyRuns okunamadı: %s", exc)
    return kayitlar


def audit_list(*, action: str | None = None, admin_uid: str | None = None,
               target_uid: str | None = None,
               start: dt.datetime | None = None,
               end: dt.datetime | None = None,
               limit: int = 50, cursor: str | None = None) -> dict[str, Any]:
    """Denetim izi sayfası (AD3): eşitlik süzgeçleri + `at` aralığı +
    `at DESC, __name__ DESC` sıralama + cursor.

    `limit+1` okunur: fazla satır varsa `nextCursor` = son satırın
    `[at, id]` çifti (core.cursor). İmleç bozuksa ValueError — uç 400'e
    çevirir. Sorgu düşerse (composite indeks eksik → FailedPrecondition)
    RuntimeError: sessiz boş liste "iz yok" gibi okunur ve yanıltır.
    """
    from core import cursor as cursor_mod
    from google.cloud.firestore_v1.base_query import FieldFilter

    client = _client()
    sorgu = client.collection("adminAudit")
    for alan, deger in (("action", action), ("adminUid", admin_uid),
                        ("targetUid", target_uid)):
        if deger:
            sorgu = sorgu.where(filter=FieldFilter(alan, "==", deger))
    if start is not None:
        sorgu = sorgu.where(filter=FieldFilter("at", ">=", start))
    if end is not None:
        sorgu = sorgu.where(filter=FieldFilter("at", "<", end))
    sorgu = (sorgu.order_by("at", direction="DESCENDING")
             .order_by("__name__", direction="DESCENDING"))
    if cursor:
        degerler = cursor_mod.decode(cursor)  # ValueError yukarı
        if len(degerler) != 2 or not isinstance(degerler[0], dt.datetime):
            raise ValueError("Geçersiz imleç.")
        sorgu = sorgu.start_after(degerler)
    sorgu = sorgu.limit(limit + 1)

    kayitlar: list[dict[str, Any]] = []
    try:
        for anlik in sorgu.stream():
            veri = anlik.to_dict() or {}
            veri["id"] = anlik.id
            kayitlar.append(veri)
    except Exception as exc:
        logger.warning("adminAudit okunamadı: %s", exc)
        raise RuntimeError(f"Denetim izi okunamadı: {exc}") from exc

    sonraki = None
    if len(kayitlar) > limit:
        kayitlar = kayitlar[:limit]
        son = kayitlar[-1]
        sonraki = cursor_mod.encode([son.get("at"), son["id"]])
    return {"entries": kayitlar, "nextCursor": sonraki}


# ---------------------------------------------------------------------------
# Geri bildirim (GB-turu) — okuma/işaretleme admin (destek dahil)
# ---------------------------------------------------------------------------

#: Liste satırına giren alanlar; `notes` listeye girmez (`noteCount`a
#: iner), detay tam dokümanı döner.
_FEEDBACK_LIST_FIELDS = ("uid", "type", "text", "screen", "appBuild",
                         "platform", "language", "createdAt", "status",
                         "reply", "updatedAt")


def _feedback_satir(anlik, adlar: dict[str, dict[str, Any]]) -> dict[str, Any]:
    veri = anlik.to_dict() or {}
    satir = {alan: veri.get(alan) for alan in _FEEDBACK_LIST_FIELDS}
    satir["id"] = anlik.id
    satir["noteCount"] = len(veri.get("notes") or [])
    satir["user"] = adlar.get(str(veri.get("uid") or "")) or {
        "displayName": None, "email": None}
    return satir


def feedback_list(status: str | None = None, type_: str | None = None,
                  limit: int = 50, cursor: str | None = None) -> dict[str, Any]:
    """Geri bildirim sayfası: `status ==` / `type ==` + `createdAt DESC,
    __name__ DESC` + imleç `[createdAt, id]`. Bozuk imleç ValueError;
    sorgu düşerse (indeks yok) RuntimeError — sessiz boş liste yanıltır.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    limit = max(1, min(int(limit or 50), LIST_LIMIT_MAX))
    client = _client()
    sorgu = client.collection("feedback")
    if status:
        sorgu = sorgu.where(filter=FieldFilter("status", "==", status))
    if type_:
        sorgu = sorgu.where(filter=FieldFilter("type", "==", type_))
    sorgu = (sorgu.order_by("createdAt", direction="DESCENDING")
             .order_by("__name__", direction="DESCENDING"))
    if cursor:
        degerler = cursor_codec.decode(cursor)  # ValueError yukarı
        if len(degerler) != 2 or not isinstance(degerler[0], dt.datetime):
            raise ValueError("Geçersiz imleç.")
        sorgu = sorgu.start_after(degerler)
    try:
        anliklar, sonraki = _sayfa(
            sorgu.limit(limit + 1), limit,
            lambda a: [(a.to_dict() or {}).get("createdAt"), a.id])
    except Exception as exc:
        logger.warning("feedback okunamadı: %s", exc)
        raise RuntimeError(f"Geri bildirim okunamadı: {exc}") from exc
    uidler = sorted({str((a.to_dict() or {}).get("uid") or "")
                     for a in anliklar} - {""})
    adlar = _kullanici_adlari(client, uidler)
    return {"items": [_feedback_satir(a, adlar) for a in anliklar],
            "nextCursor": sonraki}


def feedback_get(fid: str) -> dict[str, Any] | None:
    """Tam doküman (+ `id`, `noteCount`, `user`); yoksa None."""
    client = _client()
    anlik = client.collection("feedback").document(fid).get()
    if not getattr(anlik, "exists", False):
        return None
    veri = anlik.to_dict() or {}
    adlar = _kullanici_adlari(client, [str(veri.get("uid") or "")])
    satir = _feedback_satir(anlik, adlar)
    satir["notes"] = list(veri.get("notes") or [])
    return satir


def feedback_update(fid: str, *, status: str | None = None,
                    note: str | None = None, admin_uid: str,
                    admin_email: str | None = None) -> dict[str, Any] | None:
    """Durumu değiştirir ve/veya not ekler; yoksa None. Not `{at,
    adminUid, adminEmail, text}` — notlar dokümanın içinde liste (panel
    detayda okur; ayrı alt koleksiyon gereksiz)."""
    client = _client()
    ref = client.collection("feedback").document(fid)
    anlik = ref.get()
    if not getattr(anlik, "exists", False):
        return None
    veri = anlik.to_dict() or {}
    simdi = dt.datetime.now(dt.timezone.utc)
    degisim: dict[str, Any] = {"updatedAt": simdi}
    if status:
        degisim["status"] = status
    metin = (note or "").strip()
    if metin:
        degisim["notes"] = list(veri.get("notes") or []) + [
            {"at": simdi, "adminUid": admin_uid, "adminEmail": admin_email,
             "text": metin}]
    ref.set(degisim, merge=True)
    return feedback_get(fid)


def feedback_reply(fid: str, *, text: str, admin_uid: str,
                   admin_email: str | None = None) -> dict[str, Any] | None:
    """Yanıtı yazar ve kullanıcının GÜNCEL jetonuna push gönderir.

    Doğrudan insan yanıtı: sessiz saat / tercih kapısı UYGULANMAZ —
    kullanıcı bunu kendisi istedi. Jeton yoksa yanıt yine kaydedilir,
    `pushSent` False — ama o kullanıcı yanıtı HİÇ görmez: uygulamada
    `reply` alanını okuyan ekran yok, tek kanal push gövdesi ve o gövde
    `notification_service.MAX_PUSH_BODY` (110) karakterde kırpılıyor.
    Panelin giriş sınırı bu yüzden 110. Durum `new` ise
    `in_review`e geçer; `closed` dokunulmaz. Yoksa None.
    """
    from services import notification_service, prompts, push_service

    client = _client()
    ref = client.collection("feedback").document(fid)
    anlik = ref.get()
    if not getattr(anlik, "exists", False):
        return None
    veri = anlik.to_dict() or {}
    uid = str(veri.get("uid") or "")
    metin = text.strip()

    profil_anlik = client.collection("users").document(uid).get()
    profil = (profil_anlik.to_dict() or {}) if getattr(
        profil_anlik, "exists", False) else {}
    token = profil.get("fcmToken")
    gonderildi = False
    if token:
        lang = notification_service.profile_language(profil)
        govde = metin
        if len(govde) > notification_service.MAX_PUSH_BODY:
            govde = govde[:notification_service.MAX_PUSH_BODY - 1].rstrip() + "\u2026"
        try:
            sonuc = push_service.send([push_service.Message(
                uid=uid, token=token,
                title=prompts.get(lang).PUSH_FEEDBACK_REPLY_TITLE,
                body=govde, data={"type": "feedback", "fid": fid})])
            gonderildi = sonuc.sent > 0
        except Exception as exc:
            logger.warning("Geri bildirim pushu düştü (%s): %s", fid, exc)

    simdi = dt.datetime.now(dt.timezone.utc)
    yanit = {"text": metin, "at": simdi, "adminUid": admin_uid,
             "adminEmail": admin_email, "pushSent": gonderildi}
    degisim: dict[str, Any] = {"reply": yanit, "updatedAt": simdi}
    if veri.get("status") == "new":
        degisim["status"] = "in_review"
    ref.set(degisim, merge=True)
    return {"reply": yanit, "pushSent": gonderildi,
            "item": feedback_get(fid)}


# ---------------------------------------------------------------------------
# CSV dışa aktarım satırları (AD9) — yalnız owner ucu çağırır
# ---------------------------------------------------------------------------

#: Kullanıcı dışa aktarımının sütunları. `fcmToken` (yetenek anahtarı) ve
#: doğum verisi (birthDate/birthTime/birthPlace…) BURADA YOKTUR ve
#: eklenmez: CSV panelden çıkıp e-postada/masaüstünde dolaşır.
USERS_CSV_COLUMNS = ("uid", "email", "username", "displayName", "plan",
                     "language", "platform", "appBuild", "createdAt",
                     "lastSeenDaily", "streakCount", "hasPush",
                     "authDisabled", "onboardingCompleted")

#: Gelir olayı dışa aktarımının sütunları.
REVENUE_CSV_COLUMNS = ("id", "at", "uid", "eventType", "monetary",
                       "productId", "store", "price",
                       "priceInPurchasedCurrency", "currency",
                       "countryCode", "isTrial", "partnerId")


def _csv_deger(deger: Any) -> Any:
    """Tarihler ISO, None boş; gerisi olduğu gibi (csv modülü dizgiler)."""
    if deger is None:
        return ""
    if isinstance(deger, dt.datetime):
        return deger.isoformat()
    return deger


def users_csv_rows(*, plan: str | None = None, language: str | None = None,
                   platform: str | None = None, disabled: bool | None = None,
                   active_since: str | None = None):
    """`_iter_users` sayfalarını bellekte süzerek CSV satırları üretir.

    Tam tarama BİLEREK: dışa aktarım owner'ın nadir ve açık isteğidir,
    liste ucundaki sorgu/indeks kısıtlarına bağlanmaz. `disabled` yalnız
    True süzer (alanı olmayan eski dokümanlar `==False`'a düşmez —
    sabit karar). `active_since` `lastSeenDaily >= YYYY-MM-DD` (dizgi
    kıyası, alan zaten ISO gün).
    """
    client = _client()
    for veri in _iter_users(client):
        if plan and veri.get("plan") != plan:
            continue
        if language and veri.get("language") != language:
            continue
        if platform and veri.get("platform") != platform:
            continue
        if disabled is True and veri.get("authDisabled") is not True:
            continue
        if active_since and str(veri.get("lastSeenDaily") or "") < active_since:
            continue
        satir = {alan: _csv_deger(veri.get(alan)) for alan in USERS_CSV_COLUMNS}
        satir["hasPush"] = bool(veri.get("fcmToken"))
        yield satir


def revenue_csv_rows(*, days: int = 30, env: str = "PRODUCTION"):
    """`revenueEvents` (environment == env, at >= başlangıç, at DESC)."""
    from google.cloud.firestore_v1.base_query import FieldFilter

    client = _client()
    baslangic = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)
    sorgu = (client.collection("revenueEvents")
             .where(filter=FieldFilter("environment", "==", env))
             .where(filter=FieldFilter("at", ">=", baslangic))
             .order_by("at", direction="DESCENDING"))
    for anlik in sorgu.stream():
        veri = anlik.to_dict() or {}
        veri["id"] = anlik.id
        yield {alan: _csv_deger(veri.get(alan)) for alan in REVENUE_CSV_COLUMNS}


# ---------------------------------------------------------------------------
# Sistem sayfası (AD10)
# ---------------------------------------------------------------------------

#: Süreç başlangıcı — panel "bu instance ne zamandır ayakta" gösterir.
_PROCESS_STARTED_AT = dt.datetime.now(dt.timezone.utc)

#: Bildirim koşu türleri (api/notify.py `run(type=...)`).
_NOTIFY_TYPES = ("daily", "midday", "checkin", "streak")


def _index_probes(client) -> list[dict[str, Any]]:
    """Panelin dayandığı composite sorgular; her biri `limit(1)` ile
    yoklanır. FailedPrecondition (indeks yok/derleniyor) → ok:false; başka
    hata → ok:null (bilinmiyor). Hiçbiri fırlatmaz."""
    from google.cloud.firestore_v1.base_query import FieldFilter

    def _q(ad):
        return client.collection(ad)

    def _es(ad, alan, deger, sira):
        return (_q(ad).where(filter=FieldFilter(alan, "==", deger))
                .order_by(sira, direction="DESCENDING"))

    adaylar = [
        ("adminAudit(action, at DESC)",
         lambda: _es("adminAudit", "action", "x", "at")),
        ("adminAudit(adminUid, at DESC)",
         lambda: _es("adminAudit", "adminUid", "x", "at")),
        ("adminAudit(targetUid, at DESC)",
         lambda: _es("adminAudit", "targetUid", "x", "at")),
        ("revenueEvents(uid, at DESC)",
         lambda: _es("revenueEvents", "uid", "x", "at")),
        ("revenueEvents(environment, at DESC)",
         lambda: _es("revenueEvents", "environment", "PRODUCTION", "at")),
        ("revenueEvents(environment, eventType, at DESC)",
         lambda: _q("revenueEvents")
         .where(filter=FieldFilter("environment", "==", "PRODUCTION"))
         .where(filter=FieldFilter("eventType", "==", "RENEWAL"))
         .order_by("at", direction="DESCENDING")),
        ("usageEvents(uid, at DESC)",
         lambda: _es("usageEvents", "uid", "x", "at")),
        ("phoneAttempts(uid, at DESC)",
         lambda: _es("phoneAttempts", "uid", "x", "at")),
        ("users(plan, createdAt DESC)",
         lambda: _es("users", "plan", "plus", "createdAt")),
        ("users(plan, lastSeenDaily DESC)",
         lambda: _es("users", "plan", "plus", "lastSeenDaily")),
        ("users(plan, streakCount DESC)",
         lambda: _es("users", "plan", "plus", "streakCount")),
        ("users(language, createdAt DESC)",
         lambda: _es("users", "language", "tr", "createdAt")),
        ("users(platform, lastSeenDaily DESC)",
         lambda: _es("users", "platform", "android", "lastSeenDaily")),
        ("users(authDisabled, createdAt DESC)",
         lambda: _es("users", "authDisabled", True, "createdAt")),
        ("feedback(status, createdAt DESC)",
         lambda: _es("feedback", "status", "new", "createdAt")),
        ("feedback(type, createdAt DESC)",
         lambda: _es("feedback", "type", "bug", "createdAt")),
        ("feedback(uid, createdAt DESC)",
         lambda: _es("feedback", "uid", "x", "createdAt")),
    ]
    sonuc: list[dict[str, Any]] = []
    for ad, kur in adaylar:
        try:
            list(kur().limit(1).stream())
            sonuc.append({"name": ad, "ok": True})
        except Exception as exc:
            tip = type(exc).__name__
            ok = False if "FailedPrecondition" in tip else None
            sonuc.append({"name": ad, "ok": ok, "error": str(exc)[:200]})
    return sonuc


def _son_dokuman(client, koleksiyon: str) -> dict[str, Any] | None:
    """`date` alanına göre en yeni doküman (adminStats emsali) — yoksa None."""
    try:
        for anlik in (client.collection(koleksiyon)
                      .order_by("date", direction="DESCENDING")
                      .limit(1).stream()):
            veri = anlik.to_dict() or {}
            veri.setdefault("date", anlik.id)
            return veri
    except Exception as exc:
        logger.warning("%s okunamadı: %s", koleksiyon, exc)
    return None


def _rag_ozeti() -> dict[str, Any]:
    """main.health_rag mantığının özeti; import/çalışma düşerse
    `healthy: None` (panel '?' gösterir)."""
    try:
        from services.rag_service import diagnostics
        durum = diagnostics()
        saglikli = all(d.get("mode") == "vector" and d.get("artifact")
                       for d in durum.values())
        return {"healthy": bool(saglikli),
                "bases": {dil: {"mode": d.get("mode"),
                                "chunks": d.get("chunks"),
                                "artifact": d.get("artifact")}
                          for dil, d in durum.items()}}
    except Exception as exc:
        logger.warning("RAG özeti alınamadı: %s", exc)
        return {"healthy": None}


def _fcm_saglikli() -> bool:
    try:
        from services import push_service
        return push_service._get_messaging() is not None
    except Exception:
        return False


def system_info() -> dict[str, Any]:
    """Sistem sayfası (AD10): sağlık, rollup tazeliği, scheduler son koşu,
    indeks yoklaması, build, yapılandırma. Firestore yoksa sağlık false ve
    kalan bölümler boş — uç düşmez."""
    import os

    from core import app_gate, config

    client = firestore_client.get_client()
    firestore_ok = False
    rollups: dict[str, Any] = {"lastStatsDate": None, "lastStatsAt": None,
                               "lastStatsMs": None, "lastEconomicsDate": None}
    notify: dict[str, Any] = {t: {"lastRunAt": None, "lastStatus": None}
                              for t in _NOTIFY_TYPES}
    stats_run: dict[str, Any] = {"lastRunAt": None}
    indexes: list[dict[str, Any]] = []
    dokuman: dict[str, Any] = {}

    if client is not None:
        try:
            dokuman = app_gate.read_doc() or {}
            firestore_ok = True
        except Exception as exc:
            logger.warning("config/app okunamadı: %s", exc)

        son_stats = _son_dokuman(client, "adminStats")
        if son_stats:
            rollups["lastStatsDate"] = son_stats.get("date")
            rollups["lastStatsAt"] = son_stats.get("generatedAt")
            rollups["lastStatsMs"] = son_stats.get("durationMs")
            stats_run["lastRunAt"] = son_stats.get("generatedAt")
        son_eko = _son_dokuman(client, "adminEconomics")
        if son_eko:
            rollups["lastEconomicsDate"] = son_eko.get("date")

        # Bildirim koşuları: bugün, yoksa dün — {gün}-{tür} deterministik id.
        bugun = dt.datetime.now(dt.timezone.utc).date()
        gunler = (bugun.isoformat(), (bugun - dt.timedelta(days=1)).isoformat())
        for tur in _NOTIFY_TYPES:
            for gun in gunler:
                try:
                    anlik = (client.collection("notifyRuns")
                             .document(f"{gun}-{tur}").get())
                except Exception as exc:
                    logger.warning("notifyRuns/%s-%s okunamadı: %s",
                                   gun, tur, exc)
                    break
                if getattr(anlik, "exists", False):
                    veri = anlik.to_dict() or {}
                    notify[tur] = {"lastRunAt": veri.get("lastRunAt"),
                                   "lastStatus": veri.get("lastStatus"),
                                   "date": gun}
                    break

        indexes = _index_probes(client)

    return {
        "health": {"firestore": firestore_ok, "fcm": _fcm_saglikli(),
                   "rag": _rag_ozeti()},
        "rollups": rollups,
        "scheduler": {"notify": notify, "stats": stats_run},
        "indexes": indexes,
        "build": {"revision": os.getenv("K_REVISION"),
                  "service": os.getenv("K_SERVICE"),
                  "startedAt": _PROCESS_STARTED_AT},
        "config": {"minBuild": app_gate.current_min_build(),
                   "envFloor": config.MIN_APP_BUILD,
                   "notice": dokuman.get("notice")},
    }

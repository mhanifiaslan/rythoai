r"""Üçüncü taraf AI (Google Gemini) aktarım onayı — U06, Apple 5.1.2(i).

Korunan değişmezler:

1. **Kayıt sunucuda, sürümlü, geri alınabilir.** Onay ve geri alma ayrı
   kayıt durumlarıdır; "Şimdi değil" de bir kayıttır (``granted: False``).
2. **Zorlama varsayılan KAPALI.** Onay ekranı olmayan yayındaki Android
   paketleri tek deploy'la kırılmamalı; eşik (`aiConsentMinBuild`) ancak
   onay ekranlı paket çıktıktan sonra yükseltilir.
3. **Açık "hayır" eşikten bağımsızdır.** Ekranı görüp reddetmiş kullanıcının
   verisi "zorlama kapalıydı" diye gönderilirse ekran yalan olur.
4. **Hesap AI'sız da çalışır.** Yumuşak uçlar (sinyaller, takvim, ilişki)
   onay yokken hata değil, yorumsuz yanıt döner.

Çalıştırma:  .venv/bin/python -m pytest tests/test_ai_consent.py -q
"""
from __future__ import annotations

import inspect

import pytest
from fastapi.testclient import TestClient

from core import ai_consent, cache, config, entitlements
from core.auth import AuthUser, get_current_user
from services import consent_service

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover - ortama bagli
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulamasi ice aktarilamadi: {_APP_IMPORT_ERROR}",
)

UID = "ai-onay-uid"
VERDI = {"granted": True, "version": consent_service.AI_CONSENT_VERSION}
REDDETTI = {"granted": False, "version": consent_service.AI_CONSENT_VERSION}


@pytest.fixture
def kullanici():
    app.dependency_overrides[get_current_user] = lambda: AuthUser(
        uid=UID, email="a@b.c")
    yield
    app.dependency_overrides.clear()


def _esik(monkeypatch, deger: int) -> None:
    monkeypatch.setattr(config, "AI_CONSENT_MIN_BUILD", deger)
    ai_consent.reset_memo()


# --------------------------------------------------------------------------
# Karar tablosu (saf)
# --------------------------------------------------------------------------

def test_verilmis_guncel_onay_her_surumde_izin():
    for build, esik in ((0, 0), (46, 46), (100, 46)):
        assert ai_consent.izin_karari(VERDI, build, esik) is True


def test_acik_hayir_esik_kapaliyken_de_izin_vermez():
    """Zorlama kapalı + eski istemci (build 0) bile olsa açık "hayır"
    kazanır — eşik yalnız HİÇ SORULMAMIŞ kullanıcıyı korur."""
    assert ai_consent.izin_karari(REDDETTI, 0, 0) is False
    assert ai_consent.izin_karari(REDDETTI, 45, 0) is False
    assert ai_consent.izin_karari(REDDETTI, 99, 46) is False


def test_kayit_yokken_zorlama_kapaliysa_izin():
    """Varsayılan: eşik 0 → onay ekranı olmayan paketler çalışmaya devam."""
    assert ai_consent.izin_karari(None, 45, 0) is True
    assert ai_consent.izin_karari(None, 0, 0) is True


def test_kayit_yokken_esik_ustundeki_surum_reddedilir():
    assert ai_consent.izin_karari(None, 46, 46) is False
    assert ai_consent.izin_karari(None, 50, 46) is False


def test_kayit_yokken_esik_altindaki_surum_gecer():
    """Eski paketin onay ekranı yok; reddetmek kullanıcıyı çaresiz
    bırakırdı."""
    assert ai_consent.izin_karari(None, 45, 46) is True
    assert ai_consent.izin_karari(None, 0, 46) is True


def test_eski_surum_onayi_guncel_sayilmaz():
    eski = {"granted": True, "version": consent_service.AI_CONSENT_VERSION - 1}
    assert consent_service.ai_kaydi_gecerli(eski) is False
    assert ai_consent.izin_karari(eski, 46, 46) is False


def test_bozuk_kayit_onay_sayilmaz():
    for bozuk in ({"granted": "true", "version": 1},
                  {"granted": True, "version": True},
                  {"granted": True, "version": "1"},
                  {"granted": True}, "granted", 1):
        assert consent_service.ai_kaydi_gecerli(bozuk) is False, bozuk


# --------------------------------------------------------------------------
# Eşik
# --------------------------------------------------------------------------

def test_esik_varsayilan_kapali():
    assert ai_consent.current_min_build() == 0


def test_esik_env_tabanindan_okunur(monkeypatch):
    _esik(monkeypatch, 50)
    assert ai_consent.current_min_build() == 50


def test_esik_config_dokumanindan_okunur(monkeypatch):
    """Asıl anahtar Firestore `config/app.aiConsentMinBuild` — env her
    deploy'da sıfırlanıyor (app_gate dosya başı)."""
    from core import app_gate
    monkeypatch.setattr(app_gate, "read_doc",
                        lambda: {"minBuild": 40, "aiConsentMinBuild": 52})
    ai_consent.reset_memo()
    assert ai_consent.current_min_build() == 52


def test_esik_dokumani_okunamazsa_kapali(monkeypatch):
    from core import app_gate

    def patla():
        raise RuntimeError("firestore yok")

    monkeypatch.setattr(app_gate, "read_doc", patla)
    ai_consent.reset_memo()
    assert ai_consent.current_min_build() == 0


def test_onay_ekransiz_surumu_kapsayan_esik_yukari_cekilir(monkeypatch):
    """46 yerine 4 yazılırsa zorlama yayındaki bütün paketleri kapsardı."""
    _esik(monkeypatch, 4)
    assert ai_consent.current_min_build() == \
        ai_consent.ONAY_EKRANSIZ_SON_BUILD + 1
    # 45 kapsanmaz: onay ekranı 1.16.0+45'te YOK.
    assert ai_consent.izin_karari(None, 45,
                                  ai_consent.current_min_build()) is True


# --------------------------------------------------------------------------
# Kayıt (yerel depo — conftest pinli geçici dosya)
# --------------------------------------------------------------------------

def test_kayit_yokken_none():
    assert consent_service.ai_consent(UID) is None
    assert consent_service.has_ai_consent(UID) is False


def test_verme_ve_geri_alma_kaydi():
    assert consent_service.grant_ai_consent(UID, 1, "tr") is True
    kayit = consent_service.ai_consent(UID)
    assert kayit["granted"] is True and kayit["version"] == 1
    assert kayit["locale"] == "tr" and "grantedAt" in kayit
    assert consent_service.has_ai_consent(UID) is True

    assert consent_service.withdraw_ai_consent(UID, "en") is True
    kayit = consent_service.ai_consent(UID)
    # Silinmez, "hayır" olarak işaretlenir — "hiç sorulmadı"ya dönmez.
    assert kayit is not None and kayit["granted"] is False
    assert "withdrawnAt" in kayit and "grantedAt" not in kayit
    assert consent_service.has_ai_consent(UID) is False


def test_okuma_hatasi_izin_vermez(monkeypatch):
    """Kaydı okuyamazsak açık "hayır"ı göremeyiz → kapalı taraf."""
    def patla(uid):
        raise RuntimeError("firestore hıçkırığı")

    monkeypatch.setattr(consent_service, "ai_consent", patla)
    assert ai_consent.izin_var(UID, 0) is False
    assert consent_service.has_ai_consent(UID) is False


def test_firestoreda_kayit_private_altinda_tam_yazimla_durur(monkeypatch):
    """`users/{uid}` alanı DEĞİL: yeni sunucu alanı firestore.rules
    hasOnly listesine girmezse istemcinin tüm profil yazımları düşer."""
    yazilan: dict = {}

    class Doc:
        def __init__(self, yol):
            self.yol = yol

        def collection(self, ad):
            return Koleksiyon(self.yol + [ad])

        def set(self, veri, merge=False):
            yazilan["yol"] = "/".join(self.yol)
            yazilan["veri"] = veri
            yazilan["merge"] = merge

    class Koleksiyon:
        def __init__(self, yol):
            self.yol = yol

        def document(self, ad):
            return Doc(self.yol + [ad])

    class Istemci:
        def collection(self, ad):
            return Koleksiyon([ad])

    from core import firestore as firestore_client
    monkeypatch.setattr(firestore_client, "get_client", lambda: Istemci())
    assert consent_service.grant_ai_consent(UID, 1, "tr") is True
    assert yazilan["yol"] == f"users/{UID}/private/aiConsent"
    assert yazilan["merge"] is False


def test_firestore_kurallari_degismedi():
    """Bu kayıt için kural değişikliği GEREKMEMELİ: `private/` zaten
    istemciye kapalı. Kullanıcı dokümanına `aiConsent` alanı eklenirse bu
    test hatırlatır: o yol hasOnly listesi + değişmezlik ister."""
    from pathlib import Path
    kurallar = (Path(__file__).resolve().parent.parent.parent
                / "infra" / "firestore.rules").read_text(encoding="utf-8")
    bas = kurallar.index("match /private/{document=**}")
    assert "allow read, write: if false;" in kurallar[bas:bas + 120]


# --------------------------------------------------------------------------
# Uçlar: kayıt / durum / geri alma
# --------------------------------------------------------------------------

@pytest.mark.skipif(app is None, reason="uygulama yok")
def test_durum_ver_geri_al_uclari(kullanici):
    with TestClient(app) as client:
        durum = client.get("/api/v1/account/ai-consent").json()
        assert durum == {"granted": False, "decided": False,
                         "version": consent_service.AI_CONSENT_VERSION}

        yanit = client.post("/api/v1/account/ai-consent",
                            json={"version": 1})
        assert yanit.status_code == 200 and yanit.json()["granted"] is True
        assert client.get("/api/v1/account/ai-consent").json()["granted"]

        yanit = client.delete("/api/v1/account/ai-consent")
        assert yanit.status_code == 200 and yanit.json()["granted"] is False
        durum = client.get("/api/v1/account/ai-consent").json()
        assert durum["granted"] is False and durum["decided"] is True


@pytest.mark.skipif(app is None, reason="uygulama yok")
def test_durum_okunamazsa_500_onay_yok_DEMEZ(kullanici, monkeypatch):
    """"Yok" demek onaylı kullanıcıya ekranı sebepsiz yeniden gösterirdi;
    istemci 500'de son bildiği değere düşer."""
    def patla(uid):
        raise RuntimeError("firestore yok")

    monkeypatch.setattr(consent_service, "ai_consent", patla)
    with TestClient(app) as client:
        assert client.get("/api/v1/account/ai-consent").status_code == 500


def test_onay_uclari_abonelik_istemez():
    from api import account
    for fn in (account.ai_consent_status, account.grant_ai_consent,
               account.withdraw_ai_consent):
        kaynak = inspect.getsource(fn)
        assert "require_plus" not in kaynak, fn.__name__


# --------------------------------------------------------------------------
# Zorlama
# --------------------------------------------------------------------------

#: Tamamen AI olan uçlar — her birinde bağımlılık olmalı. Yollar
#: yönlendiriciye GÖRE (önek main.py'de: /api/v1/reports, /api/v1/face).
AI_UCLARI = {
    ("reports", "POST", "/daily"),
    ("reports", "POST", "/natal"),
    ("reports", "POST", "/bazi"),
    ("reports", "POST", "/iching"),
    ("reports", "POST", "/solar-return"),
    ("reports", "POST", "/progressions"),
    ("reports", "POST", "/birth-hexagram"),
    ("reports", "POST", "/dyad"),
    ("reports", "POST", "/synastry"),
    ("face_reading", "POST", "/reading"),
}


def _bagimliliklar(dependant) -> set:
    toplam = {getattr(d, "call", None) for d in dependant.dependencies}
    for alt in dependant.dependencies:
        toplam |= _bagimliliklar(alt)
    return toplam


def test_her_ai_ucunda_onay_bagimliligi_var():
    import importlib
    from fastapi.routing import APIRoute
    bulunan = set()
    for modul in {m for m, _, _ in AI_UCLARI}:
        router = importlib.import_module(f"api.{modul}").router
        for rota in router.routes:
            if not isinstance(rota, APIRoute):
                continue
            for yontem in rota.methods:
                if (modul, yontem, rota.path) in AI_UCLARI:
                    assert ai_consent.ai_onayi_zorunlu in _bagimliliklar(
                        rota.dependant), rota.path
                    bulunan.add((modul, yontem, rota.path))
    assert bulunan == AI_UCLARI


def test_sohbet_onayi_kriz_kapisindan_sonra_harcamadan_once():
    """Kriz metni modele gitmeden döner — onay yok diye 403 görmemeli.
    Harcama ve RAG gömme çağrısı (mesaj Gemini embedding'e gider) onay
    kapısının ALTINDA kalmalı."""
    from api import chat
    kaynak = inspect.getsource(chat.chat)
    kapi = kaynak.index("ai_consent.izin_var(")
    assert kaynak.index("crisis_signal(") < kapi
    assert kaynak.index("forbidden_topic(") < kapi
    assert kapi < kaynak.index("charge_metered(")
    assert kapi < kaynak.index("retrieve_passages(")


def test_bagimlilik_varsayilan_esikte_gecer():
    ai_consent.ai_onayi_zorunlu(AuthUser(uid=UID), "tr", None)
    ai_consent.ai_onayi_zorunlu(AuthUser(uid=UID), "tr", "60")


def test_bagimlilik_esik_ustunde_kayitsiz_403_ve_isaret(monkeypatch):
    _esik(monkeypatch, 50)
    with pytest.raises(Exception) as hata:
        ai_consent.ai_onayi_zorunlu(AuthUser(uid=UID), "en", "50")
    assert hata.value.status_code == 403
    assert hata.value.headers == {"X-Ai-Consent": "required"}
    assert "Gemini" in hata.value.detail
    # Eski paket (başlık yok ya da eşik altı) geçer.
    ai_consent.ai_onayi_zorunlu(AuthUser(uid=UID), "en", None)
    ai_consent.ai_onayi_zorunlu(AuthUser(uid=UID), "en", "49")


def test_bagimlilik_onay_verilince_gecer(monkeypatch):
    _esik(monkeypatch, 50)
    consent_service.grant_ai_consent(UID, 1, "tr")
    ai_consent.ai_onayi_zorunlu(AuthUser(uid=UID), "tr", "50")


def test_bagimlilik_acik_hayirda_esik_kapaliyken_de_403():
    consent_service.withdraw_ai_consent(UID, "tr")
    with pytest.raises(Exception) as hata:
        ai_consent.ai_onayi_zorunlu(AuthUser(uid=UID), "tr", None)
    assert hata.value.status_code == 403


@pytest.mark.skipif(app is None, reason="uygulama yok")
def test_sohbet_ucu_uctan_uca_403(kullanici, monkeypatch):
    """Açık "hayır" + başlık yok: sohbet modele gitmeden 403 döner ve
    istemcinin onay sayfasını açacağı işaret başlıkta."""
    from api import chat
    cagrildi = {"n": 0}

    def sayac(*a, **k):
        cagrildi["n"] += 1
        return "cevap"

    monkeypatch.setattr(chat.gemini_service, "chat", sayac)
    consent_service.withdraw_ai_consent(UID, "tr")
    with TestClient(app) as client:
        yanit = client.post("/api/v1/chat",
                            json={"message": "Bugün nasıl bir gün?",
                                  "history": []})
    assert yanit.status_code == 403, yanit.text
    assert yanit.headers.get("x-ai-consent") == "required"
    assert cagrildi["n"] == 0


# --------------------------------------------------------------------------
# Yumuşak uçlar: hesap kalır, yorum katmanı atlanır
# --------------------------------------------------------------------------

def test_ai_katmani_istemci_ai0_derse_kayda_bakmadan_kapali(monkeypatch):
    def patla(uid):
        raise AssertionError("ai=0 iken kayıt okunmamalı")

    monkeypatch.setattr(consent_service, "ai_consent", patla)
    assert ai_consent.ai_katmani_acik(UID, None, False) is False


@pytest.fixture
def sahte_takvim(monkeypatch):
    from api import astrology
    from services import (chart_context, predict_service, profile_service,
                          signal_service)
    monkeypatch.setattr(entitlements, "FORCE_PLUS", False)
    monkeypatch.setattr(profile_service, "get_profile",
                        lambda uid: {"birthTime": "14:30"})
    monkeypatch.setattr(chart_context, "has_birth_data", lambda p: True)
    monkeypatch.setattr(profile_service, "birth_kwargs", lambda p: {
        "name": "t", "year": 1990, "month": 5, "day": 12,
        "hour": 14, "minute": 30, "city": "Istanbul", "nation": "TR"})
    monkeypatch.setattr(predict_service, "transit_calendar", lambda **kw: {
        "events": [{"type": "aspect_exact", "date": "2026-08-20",
                    "transit": "Mars", "natal": "Venus", "aspect": "trine",
                    "orb": 0.4, "theme": "relationships",
                    "tone": "support"}],
        "active_now": []})
    monkeypatch.setattr(chart_context, "chart_facts", lambda uid, p: {})
    monkeypatch.setattr(signal_service, "enrich_events",
                        lambda olaylar, natal: olaylar)
    sayac = {"n": 0}

    def sahte_yorum(events, lang):
        sayac["n"] += 1
        return {signal_service.event_fingerprint(events[0]): "Cümle."}

    monkeypatch.setattr(signal_service, "calendar_insights", sahte_yorum)
    bellek: dict = {}
    monkeypatch.setattr(cache, "get", lambda k: bellek.get(k))
    monkeypatch.setattr(cache, "set",
                        lambda k, v, ttl_seconds=None: bellek.update({k: v}))
    monkeypatch.setattr(astrology, "is_subscriber", lambda uid: True)
    return sayac


@uygulama_gerekir
def test_takvim_ai0_yorum_uretmez_olaylar_kalir(kullanici, sahte_takvim):
    with TestClient(app) as client:
        yanit = client.get("/api/v1/astrology/transit-calendar?ai=0")
    assert yanit.status_code == 200
    olaylar = yanit.json()["data"]["events"]
    # `line` şablon satırı olarak (LLM'siz) yine gelebilir; AI cümlesi GELMEZ.
    assert olaylar and olaylar[0].get("line") != "Cümle."
    # Kilit rozeti de YOK: abonelik almak onu açmaz, yalnız onay açar.
    assert "locked" not in olaylar[0]
    assert sahte_takvim["n"] == 0


@uygulama_gerekir
def test_takvim_acik_hayirda_yorum_uretmez(kullanici, sahte_takvim):
    consent_service.withdraw_ai_consent(UID, "tr")
    with TestClient(app) as client:
        yanit = client.get("/api/v1/astrology/transit-calendar")
    assert yanit.status_code == 200
    assert sahte_takvim["n"] == 0


@uygulama_gerekir
def test_takvim_eski_istemci_davranisi_degismez(kullanici, sahte_takvim):
    """Parametresiz, kayıtsız, eşik kapalı: bugünkü Android paketi."""
    with TestClient(app) as client:
        yanit = client.get("/api/v1/astrology/transit-calendar")
    assert yanit.json()["data"]["events"][0].get("line") == "Cümle."
    assert sahte_takvim["n"] == 1


@pytest.fixture
def sahte_sinyal(monkeypatch):
    from services import profile_service, signal_service
    monkeypatch.setattr(profile_service, "get_profile", lambda uid: {})
    ham = {"signals": [{"transit": "Mars", "natal": "Venus",
                        "aspect": "trine", "theme": "relationships"}],
           "generated_for": "2026-08-20"}
    monkeypatch.setattr(signal_service, "cached_signals",
                        lambda profile, today=None: dict(ham))
    sayac = {"n": 0}

    def paket(h, lang, generate_if_missing=True):
        sayac["n"] += 1
        return {"insights": ["Yorum."], "checkin_question": "Soru?"}

    monkeypatch.setattr(signal_service, "cached_insight_bundle", paket)
    from services import prompts
    monkeypatch.setattr(prompts, "localize_signals",
                        lambda lang, h: {"signals": list(h["signals"])})
    monkeypatch.setattr(signal_service, "signals_fingerprint",
                        lambda h: "iz")
    return sayac


@uygulama_gerekir
def test_sinyaller_ai0_paket_okumaz(kullanici, sahte_sinyal):
    with TestClient(app) as client:
        yanit = client.get("/api/v1/reports/signals?ai=0")
    assert yanit.status_code == 200, yanit.text
    veri = yanit.json()["data"]
    assert veri["signals"] and "insight" not in veri["signals"][0]
    assert "checkin_question" not in veri
    assert sahte_sinyal["n"] == 0


@uygulama_gerekir
def test_sinyaller_onayliyken_yorumlu(kullanici, sahte_sinyal):
    consent_service.grant_ai_consent(UID, 1, "tr")
    with TestClient(app) as client:
        veri = client.get("/api/v1/reports/signals").json()["data"]
    assert veri["signals"][0]["insight"] == "Yorum."
    assert sahte_sinyal["n"] == 1


# --------------------------------------------------------------------------
# Sabah / akşam bildirimi (zamanlanmış koşu — başlık yok, sürüm aynası var)
# --------------------------------------------------------------------------

def test_bildirim_izni_surum_aynasini_kullanir(monkeypatch):
    from services import notification_service as ns
    assert ns.ai_izinli({"uid": UID, "appBuild": 45}) is True
    assert ns.ai_izinli({"uid": UID, "appBuild": 46}) is False
    consent_service.grant_ai_consent(UID, 1, "tr")
    assert ns.ai_izinli({"uid": UID, "appBuild": 46}) is True


def test_arka_plan_karari_esikten_bagimsiz_ve_siki():
    """Eşik KAPALIYKEN (0) bile kayıtsız yeni sürüm/iOS kullanıcısının
    haritası arka planda Gemini'ye gitmez — gizlilik metni "AI işlemeye
    izin verdiysen" diyor. Yalnız ekransız eski paket (<= 45) kayıtsız
    izinli; aynası olmayan (0) sürümü bilinmediği için izinli değil."""
    son = ai_consent.ONAY_EKRANSIZ_SON_BUILD
    assert ai_consent.arka_plan_karari(None, son) is True
    assert ai_consent.arka_plan_karari(None, 43) is True
    assert ai_consent.arka_plan_karari(None, son + 1) is False
    assert ai_consent.arka_plan_karari(None, 100) is False
    assert ai_consent.arka_plan_karari(None, 0) is False
    assert ai_consent.arka_plan_karari(REDDETTI, son) is False
    assert ai_consent.arka_plan_karari(VERDI, 0) is True
    assert ai_consent.arka_plan_karari(VERDI, 100) is True
    eski = {"granted": True, "version": consent_service.AI_CONSENT_VERSION - 1}
    assert ai_consent.arka_plan_karari(eski, 100) is False


def test_bildirim_esik_kapaliyken_karar_vermemis_yeni_surume_ai_yok(
        monkeypatch, sahte_sinyal):
    """Onay sayfasını görüp karar vermeden uygulamayı kapatan 46+ kullanıcı:
    varsayılan eşik 0 iken de sabah bildirimi teknik satır, paket okunmaz."""
    from services import notification_service as ns
    from services import signal_service
    _esik(monkeypatch, 0)
    monkeypatch.setattr(signal_service, "daily_focus_index",
                        lambda ham, prev_theme=None, prev_fp=None: 0)
    monkeypatch.setattr(ns.prompts, "localize_signals", lambda lang, h: {
        "signals": [{"technical": "Mars üçgen Venüs", "theme": "relationships",
                     "theme_local": "İlişkiler"}]})
    sonuc = ns.signal_push({"uid": UID, "appBuild": 46}, "tr")
    assert sonuc is not None and sonuc[1] == "Mars üçgen Venüs"
    assert sahte_sinyal["n"] == 0
    assert ns.checkin_push({"uid": UID, "appBuild": 46}, "tr") is None
    assert sahte_sinyal["n"] == 0


def test_arka_plan_kaydi_okunamazsa_izin_yok(monkeypatch):
    def patla(uid):
        raise RuntimeError("firestore yok")
    monkeypatch.setattr(consent_service, "ai_consent", patla)
    assert ai_consent.arka_plan_izni_var(UID, 45) is False


def test_sabah_bildirimi_hayir_diyene_paket_okumaz(monkeypatch, sahte_sinyal):
    from services import notification_service as ns
    from services import signal_service
    monkeypatch.setattr(signal_service, "daily_focus_index",
                        lambda ham, prev_theme=None, prev_fp=None: 0)
    monkeypatch.setattr(ns.prompts, "localize_signals", lambda lang, h: {
        "signals": [{"technical": "Mars üçgen Venüs", "theme": "relationships",
                     "theme_local": "İlişkiler"}]})
    consent_service.withdraw_ai_consent(UID, "tr")
    sonuc = ns.signal_push({"uid": UID}, "tr")
    assert sonuc is not None, "bildirim yine gider — teknik satırla"
    assert sonuc[1] == "Mars üçgen Venüs"
    assert sahte_sinyal["n"] == 0


def test_aksam_sorusu_hayir_diyene_gitmez(sahte_sinyal):
    from services import notification_service as ns
    consent_service.withdraw_ai_consent(UID, "tr")
    assert ns.checkin_push({"uid": UID}, "tr") is None
    assert sahte_sinyal["n"] == 0

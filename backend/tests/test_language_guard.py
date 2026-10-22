"""Bildirim dil muhafızı (DM-turu): yanlış dilde push ASLA gitmez.

Cihaz bulgusu: "hem İngilizce hem Türkçe" bir push. Kompozisyon kodu tek
dilli; ama sabah/öğle gövdesi ve akşam sorusu LLM'den geliyor ve LLM'in
dili söz değil. Muhafız DETERMİNİSTİK ve üretimden SONRA çalışır: Türkçe
harf + işlev sözcüğü sezgisi. Kararsızlık (None) hiçbir zaman çelişki
sayılmaz — kısa başlıklar ve nötr metinler yüzünden bildirim düşmez.

Üç katman, üçü de burada sınanır:

1. `i18n.guess_language` / `language_conflicts` — saf fonksiyon.
2. Üretici muhafızları — `_bundle_body` (sabah + öğle) ve `checkin_push`.
3. `notify_runner` (notify.run gövdesi) son emniyet ağı + `diller=` gözlemlenebilirliği.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_language_guard.py -q
"""
from __future__ import annotations

import datetime as dt
import logging

import pytest
from fastapi.testclient import TestClient

from core import cache, config, i18n
from services import prompts
from services import notification_service as ns

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulamasi ice aktarilamadi: {_APP_IMPORT_ERROR}",
)


@pytest.fixture(autouse=True)
def temiz_onbellek(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    cache._memory.clear()
    yield
    cache._memory.clear()


def profil(**alanlar):
    """Bildirim almaya uygun asgari profil (test_notifications ile aynı)."""
    temel = {
        "uid": "u1",
        "fcmToken": "token-1",
        "onboardingCompleted": True,
        "timezone": "Europe/Istanbul",
        "language": "tr",
        "sunSign": "Aslan ♌",
        "streakCount": 5,
    }
    temel.update(alanlar)
    return temel


SAHTE_GOKYUZU = {
    "moon_phase": {"key": "full_moon", "name": "Dolunay", "illumination": 98},
    "retrogrades": ["Satürn"],
}


def _tek_sinyal_ham():
    return {"generated_for": "2026-06-15", "signals": [
        {"transit": "Saturn", "natal": "Moon", "aspect": "Square",
         "orb": 0.3, "theme": "inner", "active": True,
         "exact_on": "2026-06-18", "days_to_exact": 3,
         "movement": "applying"}]}


def _iki_sinyal_ham(gunler: int = 0, tarih: str = "2026-06-15"):
    """2. sinyal bugün kesinleşir (öğle dalı + check-in odağı)."""
    return {"generated_for": tarih, "signals": [
        {"transit": "Jupiter", "natal": "Sun", "aspect": "Trine",
         "orb": 2.1, "theme": "career", "active": True,
         "movement": "applying"},
        {"transit": "Saturn", "natal": "Moon", "aspect": "Square",
         "orb": 0.3, "theme": "inner", "active": True,
         "exact_on": tarih, "days_to_exact": gunler}]}


# --------------------------------------------------------------------------
# 1. Saf tahmin
# --------------------------------------------------------------------------

TR_CUMLELER = [
    # Aksansız yazılmış Türkçe: tek bir Türkçe harf yok, yalnız işlev
    # sözcükleri ("bu", "daha") karar verir.
    "Bu sabah biraz daha sakin ol",
    "Sen ve ben bir olduk, ama bu daha yeni",
    "Bugün içinde ne kapandı?",
    "Satürn, natal Ay ile kare açısını 3 gün sonra kesinleştiriyor.",
    "Kariyer tarafında bir kapı aralanıyor.",
    "Bugün okumanı henüz açmadın. Seriyi sürdürmek birkaç saniye alır.",
]

EN_CUMLELER = [
    "You haven't opened today's reading yet. Keeping the streak takes seconds.",
    "Saturn perfects its square to your natal Moon in 3 days.",
    "What closed inside you today?",
    "The door is open and the timing is right.",
    "This is a day to slow down with your feelings.",
    "Career opens a door today, and you are ready for it.",
]

#: Kararsız kalması GEREKEN metinler: kısa, nötr, tek isabetli.
BELIRSIZ = [
    "...", "42", "OK", "", "Rytho",
    "🔮 Rytho merak ediyor",   # TR başlık, Türkçe harfsiz, işlev sözcüksüz
    "🔥 5-day streak",         # EN başlık, tek isabet bile yok
    "🔮 Rytho is curious",     # EN başlık, tek isabet ("is") — yetmez
    "Mars trine Venus",
]


@pytest.mark.parametrize("metin", TR_CUMLELER)
def test_turkce_cumleler_tr_tahmin_edilir(metin):
    assert i18n.guess_language(metin) == "tr"


@pytest.mark.parametrize("metin", EN_CUMLELER)
def test_ingilizce_cumleler_en_tahmin_edilir(metin):
    assert i18n.guess_language(metin) == "en"


@pytest.mark.parametrize("metin", BELIRSIZ)
def test_kisa_ve_notr_metinler_kararsiz(metin):
    assert i18n.guess_language(metin) is None


def test_alt_dizi_esleme_yok():
    """"bu" "bugünkü"nün, "it" "little"ın içinde sayılmaz — sözcük sınırı."""
    assert i18n.guess_language("Bugunku okuman hazir") is None
    assert i18n.guess_language("a little bit of wit") is None


def test_noktali_buyuk_i_turkce_sayilir():
    """Noktalı I tuzağı: Python lower() 'İ'yi iki karaktere böler; harf
    kontrolü lower()'dan ÖNCE koştuğu için 'İçin' hep Türkçe."""
    assert i18n.guess_language("İçin") == "tr"
    assert "İ" in i18n.TURKCE_HARFLER


@pytest.mark.parametrize("metin,lang,beklenen", [
    (TR_CUMLELER[2], "tr", False),
    (TR_CUMLELER[2], "en", True),
    (TR_CUMLELER[0], "en", True),      # aksansız Türkçe de yakalanır
    (EN_CUMLELER[2], "tr", True),
    (EN_CUMLELER[2], "en", False),
    ("...", "tr", False),              # kararsız → asla çelişki
    ("...", "en", False),
    (TR_CUMLELER[2], "fr", False),     # desteklenmeyen dil → asla çelişki
    (EN_CUMLELER[2], "", False),
])
def test_language_conflicts_dogruluk_tablosu(metin, lang, beklenen):
    assert i18n.language_conflicts(metin, lang) is beklenen


@pytest.mark.parametrize("lang", i18n.SUPPORTED)
def test_sablonlar_kendi_dilinde_celismez(lang):
    """Muhafız şablonları ASLA düşürmemeli: her dilin push başlık/gövde
    şablonları ve teknik satırı kendi diliyle çelişmez. Gövde şablonları
    (seri, teknik satır) ayrıca DOĞRU tahmin edilir — emniyet ağı bunları
    görür."""
    p = prompts.get(lang)
    tema = p.SIGNAL_THEME_NAMES["inner"]
    basliklar = [
        p.PUSH_DAILY_TITLE, p.PUSH_CHECKIN_TITLE,
        p.PUSH_STREAK_TITLE.format(days=5),
        p.PUSH_SIGNAL_TITLE.format(emoji="🌙", theme=tema),
        p.PUSH_MIDDAY_TITLE.format(emoji="🌙", theme=tema),
        p.PUSH_MIDDAY_PAIR_TITLE.format(name="Ada"),
    ]
    govdeler = [
        p.PUSH_STREAK_BODY,
        p.PUSH_DAILY_FALLBACK.format(
            sign=prompts.sign_name(lang, "leo"),
            date=prompts.signal_date(lang, "2026-06-15")),
        prompts.localize_signals(lang, _tek_sinyal_ham())["signals"][0]
        ["technical"],
        prompts.localize_signals(lang, _iki_sinyal_ham())["signals"][1]
        ["technical"],
    ]
    for metin in basliklar + govdeler:
        assert not i18n.language_conflicts(metin, lang), (lang, metin)
    for metin in govdeler:
        assert i18n.guess_language(metin) == lang, (lang, metin)


# --------------------------------------------------------------------------
# 2. Üretici muhafızları
# --------------------------------------------------------------------------

def test_signal_push_ingilizce_paket_teknik_satira_duser(monkeypatch, caplog):
    """Sabah: paket cümlesi İngilizce, profil dili Türkçe → gövde TÜRKÇE
    teknik satır olur (şablon, dili kesin); yeniden üretim YOK (LLM'e
    dönmek aynı riski tekrarlar) ve uyarı uid taşır."""
    from services import signal_service

    ham = _tek_sinyal_ham()
    monkeypatch.setattr(signal_service, "cached_signals",
                        lambda p, today=None: ham)
    monkeypatch.setattr(
        signal_service, "cached_insight_bundle",
        lambda h, lang, generate_if_missing=True: {
            "insights": ["Saturn asks for a quiet review of what you carry."],
            "checkin_question": None})
    sayac = {"n": 0}

    def sahte_uretim(h, lang, avoid=None):
        # Sayaçla ölçülür — raise olsaydı signal_push'un try/except'i
        # yutar, None döner ve test yanlış nedenle kırılırdı.
        sayac["n"] += 1
        return {"insights": ["Regenerated."], "checkin_question": None}

    monkeypatch.setattr(signal_service, "insight_bundle", sahte_uretim)

    with caplog.at_level(logging.WARNING):
        sonuc = ns.signal_push(profil(), "tr", today=dt.date(2026, 6, 15))
    assert sonuc is not None
    _baslik, govde, _iz, _idx, extra = sonuc
    assert "3 gün sonra" in govde                 # TR teknik satır
    assert i18n.guess_language(govde) == "tr"
    assert extra["dailyBodyLang"] == "tr"
    assert sayac["n"] == 0
    uyarilar = [r.getMessage() for r in caplog.records
                if "Bildirim gövdesi dili uyuşmuyor" in r.getMessage()]
    assert uyarilar and "uid=u1" in uyarilar[0] and "tahmin=en" in uyarilar[0]

    # Karşı kontrol: Türkçe paket cümlesi olduğu gibi gider, uyarı yok.
    caplog.clear()
    monkeypatch.setattr(
        signal_service, "cached_insight_bundle",
        lambda h, lang, generate_if_missing=True: {
            "insights": ["Satürn taşıdıklarını sessizce gözden geçirmeni istiyor."],
            "checkin_question": None})
    with caplog.at_level(logging.WARNING):
        sonuc = ns.signal_push(profil(), "tr", today=dt.date(2026, 6, 15))
    assert sonuc is not None
    assert sonuc[1] == "Satürn taşıdıklarını sessizce gözden geçirmeni istiyor."
    assert not any("dili uyuşmuyor" in r.getMessage() for r in caplog.records)


def test_signal_push_turkce_paket_ingilizce_profilde_teknik_satira_duser(
        monkeypatch):
    """Ters yön: İngilizce kullanıcıya Türkçe cümle de gitmez."""
    from services import signal_service

    ham = _tek_sinyal_ham()
    monkeypatch.setattr(signal_service, "cached_signals",
                        lambda p, today=None: ham)
    monkeypatch.setattr(
        signal_service, "cached_insight_bundle",
        lambda h, lang, generate_if_missing=True: {
            "insights": ["Bugün içinde bir kapanış var."],
            "checkin_question": None})
    sonuc = ns.signal_push(profil(language="en"), "en",
                           today=dt.date(2026, 6, 15))
    assert sonuc is not None
    assert i18n.guess_language(sonuc[1]) == "en"
    assert "Saturn" in sonuc[1] and "3 days" in sonuc[1]


def test_midday_ingilizce_paket_teknik_satira_duser(monkeypatch):
    """Öğle aynı `_bundle_body`'den okur: İngilizce paket + Türkçe profil
    → bugün kesinleşen sinyalin TÜRKÇE teknik satırı, indeks korunur."""
    from services import signal_service

    ham = _iki_sinyal_ham(gunler=0)
    monkeypatch.setattr(signal_service, "cached_signals",
                        lambda p, today=None: ham)
    monkeypatch.setattr(
        signal_service, "cached_insight_bundle",
        lambda h, lang, generate_if_missing=True: {
            "insights": ["Career opens a door today, and you are ready.",
                         "Something inside you is closing today."],
            "checkin_question": None})
    monkeypatch.setattr(ns, "last_daily_sent", lambda uid: None)

    sonuc, gerekce = ns.midday_push(profil(), "tr",
                                    today=dt.date(2026, 6, 15))
    assert sonuc is not None and gerekce == "gonderilecek"
    _baslik, govde, veri = sonuc
    assert veri["idx"] == "1"
    assert "bugün kesinleştiriyor" in govde
    assert i18n.guess_language(govde) == "tr"


def test_checkin_ingilizce_soru_none_doner(monkeypatch, caplog):
    """Akşam sorusu isteğe bağlı: yanlış dildeyse None ('soru-yok' →
    seri hatırlatması devreye girer). Soru için şablon yedek uydurulmaz."""
    from services import signal_service

    ham = _iki_sinyal_ham(gunler=0)
    monkeypatch.setattr(signal_service, "cached_signals",
                        lambda p, today=None: ham)
    monkeypatch.setattr(
        signal_service, "cached_insight_bundle",
        lambda h, lang, generate_if_missing=True: {
            "insights": ["Kariyer cümlesi.", "İç dünya cümlesi."],
            "checkin_question": "What closed inside you today?"})

    with caplog.at_level(logging.WARNING):
        assert ns.checkin_push(profil(), "tr",
                               today=dt.date(2026, 6, 15)) is None
    uyarilar = [r.getMessage() for r in caplog.records
                if "Check-in sorusu dili uyuşmuyor" in r.getMessage()]
    assert uyarilar and "uid=u1" in uyarilar[0] and "lang=tr" in uyarilar[0]

    # Karşı kontrol: Türkçe soru olduğu gibi, soru=True.
    monkeypatch.setattr(
        signal_service, "cached_insight_bundle",
        lambda h, lang, generate_if_missing=True: {
            "insights": ["Kariyer cümlesi.", "İç dünya cümlesi."],
            "checkin_question": "Bugün içinde ne kapandı?"})
    sonuc = ns.checkin_push(profil(), "tr", today=dt.date(2026, 6, 15))
    assert sonuc is not None and sonuc.soru is True
    assert sonuc.govde == "Bugün içinde ne kapandı?"


# --------------------------------------------------------------------------
# 3. notify.run son emniyet ağı + diller=
# --------------------------------------------------------------------------

def _kosu_ortami(monkeypatch, gonderilen: list):
    from services import notify_runner
    from services import push_service

    monkeypatch.setattr(config, "NOTIFY_SCHEDULER_SECRET", "dogru")
    monkeypatch.setattr(notify_runner, "get_sky_now", lambda: SAHTE_GOKYUZU)
    monkeypatch.setattr(notify_runner.firestore_client, "get_client", lambda: None)
    monkeypatch.setattr(ns, "already_sent", lambda uid, tur, gun: False)
    monkeypatch.setattr(ns, "mark_sent",
                        lambda uid, tur, gun, extra=None: None)

    def sahte_gonder(mesajlar):
        gonderilen.extend(mesajlar)
        return push_service.SendResult(sent=len(mesajlar), failed=0,
                                       pruned=[], failed_uids=[])

    monkeypatch.setattr(push_service, "send", sahte_gonder)


def _kos(client, ek: str = ""):
    return client.post(f"/api/v1/notify/run?type=streak&force=true{ek}",
                       headers={"Authorization": "dogru"})


@uygulama_gerekir
def test_kosu_dil_uyusmazligini_atlar_ve_sayar(monkeypatch, caplog):
    """Şablon İngilizceye ZORLANIR (üretici muhafızı olmayan streak dalı),
    profil dili Türkçe: son ağ push'u düşürür, `dil-uyusmaz` sayar, uyarı
    uid/tur/lang taşır ve özet satırı `diller=` içerir."""
    from services import notify_runner

    gonderilen: list = []
    _kosu_ortami(monkeypatch, gonderilen)
    monkeypatch.setattr(notify_runner, "_iter_profiles",
                        lambda: iter([profil(quietFrom=0, quietTo=0)]))
    monkeypatch.setattr(
        ns, "streak_push",
        lambda p, lang: ("🔥 5 günlük serin",
                         prompts.get("en").PUSH_STREAK_BODY))

    with caplog.at_level(logging.INFO), TestClient(app) as client:
        yanit = _kos(client)
    assert yanit.status_code == 200
    govde = yanit.json()
    assert govde["queued"] == 0 and govde["sent"] == 0
    assert govde["skipped"]["dil-uyusmaz"] == 1
    assert govde["languages"] == {}
    assert gonderilen == []
    kayitlar = [r.getMessage() for r in caplog.records]
    uyari = [k for k in kayitlar
             if "Bildirim dil uyuşmazlığı, gönderilmedi" in k]
    assert uyari and "uid=u1" in uyari[0] and "tur=streak" in uyari[0] \
        and "lang=tr" in uyari[0]
    assert any(k.startswith("Bildirim turu=streak") and "diller={}" in k
               for k in kayitlar)


@uygulama_gerekir
def test_kosu_dogru_dilde_diller_sayar(monkeypatch, caplog):
    """Karşı kontrol: doğru dilde şablon gider, `languages` ve özet
    satırındaki `diller=` dili sayar; prova satırı da aynı sayımı taşır."""
    from services import notify_runner

    gonderilen: list = []
    _kosu_ortami(monkeypatch, gonderilen)
    monkeypatch.setattr(
        notify_runner, "_iter_profiles",
        lambda: iter([profil(quietFrom=0, quietTo=0),
                      profil(uid="u2", fcmToken="token-2", language="en",
                             quietFrom=0, quietTo=0)]))

    with caplog.at_level(logging.INFO), TestClient(app) as client:
        yanit = _kos(client)
    govde = yanit.json()
    assert govde["queued"] == 2 and govde["sent"] == 2
    assert govde["languages"] == {"tr": 1, "en": 1}
    assert "dil-uyusmaz" not in govde["skipped"]
    assert [m.uid for m in gonderilen] == ["u1", "u2"]
    kayitlar = [r.getMessage() for r in caplog.records]
    assert any(k.startswith("Bildirim turu=streak")
               and "diller={'tr': 1, 'en': 1}" in k for k in kayitlar)

    # Prova: gönderim yok ama sayım ve `diller=` aynı.
    caplog.clear()
    gonderilen.clear()
    monkeypatch.setattr(
        notify_runner, "_iter_profiles",
        lambda: iter([profil(quietFrom=0, quietTo=0)]))
    with caplog.at_level(logging.INFO), TestClient(app) as client:
        yanit = _kos(client, "&dry_run=true")
    govde = yanit.json()
    assert govde["status"] == "dry-run" and govde["queued"] == 1
    assert govde["languages"] == {"tr": 1}
    assert gonderilen == []
    kayitlar = [r.getMessage() for r in caplog.records]
    assert any(k.startswith("Bildirim PROVA turu=streak")
               and "diller={'tr': 1}" in k for k in kayitlar)


@uygulama_gerekir
def test_kosu_checkin_yanlis_dilde_sohbete_tohum_atmaz(monkeypatch):
    """Son ağ sohbet tohumundan ÖNCE: üretici muhafızı atlansa bile
    (checkin_push sahte) yanlış dilde soru ne sohbete yazılır ne push
    olur."""
    from services import notify_runner

    gonderilen: list = []
    _kosu_ortami(monkeypatch, gonderilen)
    monkeypatch.setattr(notify_runner, "_iter_profiles",
                        lambda: iter([profil(quietFrom=0, quietTo=0)]))
    monkeypatch.setattr(
        ns, "checkin_push",
        lambda p, lang, today=None: ns.PushIcerik(
            prompts.get("tr").PUSH_CHECKIN_TITLE,
            "What closed inside you today?", soru=True))
    tohumlar: list = []
    monkeypatch.setattr(
        notify_runner.chat_history, "seed_assistant_message",
        lambda uid, text, lang, gun: tohumlar.append(text) or "cid-1")

    with TestClient(app) as client:
        yanit = client.post("/api/v1/notify/run?type=checkin&force=true",
                            headers={"Authorization": "dogru"})
    assert yanit.status_code == 200
    assert yanit.json()["skipped"]["dil-uyusmaz"] == 1
    assert tohumlar == [] and gonderilen == []


# ---------------------------------------------------------------------------
# Karışık (iki dilli) metin — cihazda görülen "hem İngilizce hem Türkçe"
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("metin", [
    "Bugün the sky is with you ve senin için açık.",
    "İlişkilerinde bir kapı aralanıyor and you are the one to open it today.",
    "Sabah sakin ol ve dinle; bugün this is your day and the sky is with you.",
])
def test_karisik_metin_mixed_ve_her_dille_celisir(metin):
    assert i18n.guess_language(metin) == "mixed"
    assert i18n.language_conflicts(metin, "tr") is True
    assert i18n.language_conflicts(metin, "en") is True


@pytest.mark.parametrize("metin", [
    "Bugün senin için the gün.",          # tek İngilizce sözcük — Türkçe
    "Bugün işine odaklan; it senin.",     # "it" Türkçe'de de var, sayılmaz
])
def test_tek_tuk_ingilizce_sozcuk_turkceyi_bozmaz(metin):
    assert i18n.guess_language(metin) == "tr"
    assert i18n.language_conflicts(metin, "tr") is False

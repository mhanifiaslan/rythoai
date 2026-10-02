"""Sistem sayfası + panel duyurusu (AD10).

Değişmezler:
- `system_info`: sağlık (firestore/fcm/rag), rollup tazeliği (adminStats /
  adminEconomics `date` DESC), scheduler son koşu (notifyRuns bugün→dün),
  indeks yoklaması (FailedPrecondition → ok:false, başka hata → ok:null),
  build (K_REVISION/K_SERVICE/startedAt), config (minBuild/envFloor/notice).
  Firestore yokken düşmez: health.firestore false, listeler boş.
- `POST /admin/config/notice` (owner): metin → `config/app.notice`
  {text, level, updatedAt, updatedBy}; boş metin alanı SİLER; >300 / kötü
  level 422; iz `config.notice`; support 403. `api/config.py` dokunulmaz.
"""
from __future__ import annotations

import datetime as dt

import pytest
from fastapi.testclient import TestClient

from core import app_gate, config
from core import firestore as firestore_client
from services import admin_service, notify_runner
from main import app
from test_admin_audit import FailedPrecondition, SahteFirestore  # noqa: F401

_SIMDI = dt.datetime.now(dt.timezone.utc)
_BUGUN = _SIMDI.date().isoformat()
_DUN = (_SIMDI.date() - dt.timedelta(days=1)).isoformat()


@pytest.fixture()
def depo(monkeypatch):
    sahte = SahteFirestore({
        "adminStats/2026-09-10": {"date": "2026-09-10",
                                  "generatedAt": _SIMDI - dt.timedelta(days=2),
                                  "durationMs": 900},
        "adminStats/2026-09-11": {"date": "2026-09-11",
                                  "generatedAt": _SIMDI - dt.timedelta(days=1),
                                  "durationMs": 1200},
        "adminEconomics/2026-09-09": {"date": "2026-09-09"},
        f"notifyRuns/{_BUGUN}-daily": {"date": _BUGUN, "type": "daily",
                                       "lastStatus": "ok",
                                       "lastRunAt": _SIMDI},
        f"notifyRuns/{_DUN}-daily": {"date": _DUN, "type": "daily",
                                     "lastStatus": "eski",
                                     "lastRunAt": _SIMDI - dt.timedelta(days=1)},
        f"notifyRuns/{_DUN}-midday": {"date": _DUN, "type": "midday",
                                      "lastStatus": "failed",
                                      "lastRunAt": _SIMDI - dt.timedelta(hours=20)},
        "config/app": {"minBuild": 35, "notice": {"text": "Bakım", "level": "warn"}},
        "users/u1": {"appBuild": 40, "plan": "plus"},
    })
    monkeypatch.setattr(firestore_client, "get_client", lambda: sahte)
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(config, "DEV_ADMIN", True)
    monkeypatch.setattr(config, "DEV_ADMIN_ROLE", "owner")
    monkeypatch.setattr(config, "MIN_APP_BUILD", 10)
    monkeypatch.setattr(admin_service, "_rag_ozeti",
                        lambda: {"healthy": True, "bases": {}})
    monkeypatch.setattr(admin_service, "_fcm_saglikli", lambda: True)
    monkeypatch.setenv("K_REVISION", "rytho-00042-abc")
    monkeypatch.setenv("K_SERVICE", "rytho-backend")
    app_gate.reset_memo()
    yield sahte
    app_gate.reset_memo()


def test_system_info_sekli(depo):
    depo.bozuk_indeksler.add(("users", "streakCount"))
    bilgi = admin_service.system_info()

    assert bilgi["health"] == {"firestore": True, "fcm": True,
                               "rag": {"healthy": True, "bases": {}}}
    assert bilgi["rollups"]["lastStatsDate"] == "2026-09-11"
    assert bilgi["rollups"]["lastStatsMs"] == 1200
    assert bilgi["rollups"]["lastStatsAt"] == _SIMDI - dt.timedelta(days=1)
    assert bilgi["rollups"]["lastEconomicsDate"] == "2026-09-09"

    bildirim = bilgi["scheduler"]["notify"]
    # Küme TEK KAYNAKTAN okunuyor, elle sayılmıyor: aynı gerçeğin altı
    # kopyası vardı ve bu test BEŞİNCİSİYDİ. 48-turunda `RUN_TYPES`a
    # `circle`/`winback` eklendiğinde dördü dörtte kaldı; panel iki yeni
    # slotu hiç göstermiyordu. Kopyalar türetilmeye çevrildi — bu satırın
    # da elle yazılı kalması, onarımın kendisini kırmızıya düşürürdü.
    assert set(bildirim) == set(notify_runner.RUN_TYPES)
    assert bildirim["daily"] == {"lastRunAt": _SIMDI, "lastStatus": "ok",
                                 "date": _BUGUN}          # bugün, dün değil
    assert bildirim["midday"]["lastStatus"] == "failed"   # dünden düştü
    assert bildirim["midday"]["date"] == _DUN
    assert bildirim["checkin"] == {"lastRunAt": None, "lastStatus": None}
    assert bilgi["scheduler"]["stats"]["lastRunAt"] == _SIMDI - dt.timedelta(days=1)

    indeksler = {i["name"]: i for i in bilgi["indexes"]}
    assert len(indeksler) >= 10
    assert indeksler["users(plan, streakCount DESC)"]["ok"] is False
    assert "indeks yok" in indeksler["users(plan, streakCount DESC)"]["error"]
    assert indeksler["users(plan, createdAt DESC)"]["ok"] is True
    assert indeksler["adminAudit(action, at DESC)"]["ok"] is True
    assert indeksler["revenueEvents(environment, eventType, at DESC)"]["ok"] is True

    assert bilgi["build"]["revision"] == "rytho-00042-abc"
    assert bilgi["build"]["service"] == "rytho-backend"
    assert isinstance(bilgi["build"]["startedAt"], dt.datetime)
    assert bilgi["config"] == {"minBuild": 35, "envFloor": 10,
                               "notice": {"text": "Bakım", "level": "warn"}}


def test_system_info_baska_hata_ok_null(depo, monkeypatch):
    """FailedPrecondition dışındaki hata 'bilinmiyor' (null) — panel
    'indeks yok' demesin."""
    gercek = depo.collection

    def kirik(ad):
        if ad == "phoneAttempts":
            raise ConnectionError("ağ")
        return gercek(ad)
    monkeypatch.setattr(depo, "collection", kirik)
    bilgi = admin_service.system_info()
    indeksler = {i["name"]: i for i in bilgi["indexes"]}
    assert indeksler["phoneAttempts(uid, at DESC)"]["ok"] is None


def test_system_info_firestore_yokken_dusmez(depo, monkeypatch):
    monkeypatch.setattr(firestore_client, "get_client", lambda: None)
    monkeypatch.setattr(admin_service, "_fcm_saglikli", lambda: False)
    monkeypatch.setattr(admin_service, "_rag_ozeti", lambda: {"healthy": None})
    app_gate.reset_memo()
    bilgi = admin_service.system_info()
    assert bilgi["health"] == {"firestore": False, "fcm": False,
                               "rag": {"healthy": None}}
    assert bilgi["rollups"] == {"lastStatsDate": None, "lastStatsAt": None,
                                "lastStatsMs": None, "lastEconomicsDate": None}
    assert bilgi["indexes"] == []
    assert bilgi["config"]["notice"] is None
    assert bilgi["config"]["minBuild"] == 10   # env tabanı


def test_rag_ozeti_gercek_mantik(monkeypatch):
    import services.rag_service as rag

    monkeypatch.setattr(rag, "diagnostics", lambda: {
        "tr": {"mode": "vector", "chunks": 10, "artifact": True},
        "en": {"mode": "keyword", "chunks": 3, "artifact": False}})
    ozet = admin_service._rag_ozeti()
    assert ozet["healthy"] is False
    assert ozet["bases"]["en"] == {"mode": "keyword", "chunks": 3,
                                   "artifact": False}

    def patlar():
        raise RuntimeError("korpus yok")
    monkeypatch.setattr(rag, "diagnostics", patlar)
    assert admin_service._rag_ozeti() == {"healthy": None}


def test_system_ucu(depo):
    with TestClient(app) as client:
        yanit = client.get("/api/v1/admin/system")
    assert yanit.status_code == 200
    govde = yanit.json()
    assert govde["status"] == "ok"
    assert govde["health"]["firestore"] is True
    assert govde["build"]["revision"] == "rytho-00042-abc"
    assert govde["config"]["minBuild"] == 35
    assert isinstance(govde["build"]["startedAt"], str)


def test_system_ucu_destek_okur(depo, monkeypatch):
    monkeypatch.setattr(config, "DEV_ADMIN_ROLE", "support")
    with TestClient(app) as client:
        assert client.get("/api/v1/admin/system").status_code == 200


# ---------------------------------------------------------------------------
# Duyuru
# ---------------------------------------------------------------------------

def test_notice_yazar_ve_iz_birakir(depo):
    with TestClient(app) as client:
        yanit = client.post("/api/v1/admin/config/notice",
                            json={"text": "  Yarın bakım var  ", "level": "warn"})
    assert yanit.status_code == 200
    assert yanit.json()["notice"] == {"text": "Yarın bakım var", "level": "warn"}
    duyuru = depo.docs["config/app"]["notice"]
    assert duyuru["text"] == "Yarın bakım var"
    assert duyuru["level"] == "warn"
    assert duyuru["updatedBy"] == "dev-user"
    assert isinstance(duyuru["updatedAt"], dt.datetime)
    assert depo.docs["config/app"]["minBuild"] == 35   # merge — eşik durdu
    izler = depo.izler()
    assert [i["action"] for i in izler] == ["config.notice"]
    assert izler[0]["params"] == {"text": "Yarın bakım var", "level": "warn",
                                  "cleared": False}


def test_notice_bos_metin_siler(depo):
    with TestClient(app) as client:
        yanit = client.post("/api/v1/admin/config/notice", json={"text": ""})
    assert yanit.status_code == 200
    assert yanit.json()["notice"] is None
    assert "notice" not in depo.docs["config/app"]
    assert depo.docs["config/app"]["minBuild"] == 35
    assert depo.izler()[0]["params"]["cleared"] is True


@pytest.mark.parametrize("govde", [
    {"text": "x" * 301},
    {"text": "x", "level": "panic"},
    {"level": "info", "text": 5},
])
def test_notice_sema_422(depo, govde):
    with TestClient(app) as client:
        assert client.post("/api/v1/admin/config/notice", json=govde).status_code == 422
    assert depo.docs["config/app"]["notice"]["text"] == "Bakım"
    assert depo.izler() == []


def test_notice_destege_403(depo, monkeypatch):
    monkeypatch.setattr(config, "DEV_ADMIN_ROLE", "support")
    with TestClient(app) as client:
        assert client.post("/api/v1/admin/config/notice",
                           json={"text": "x"}).status_code == 403
    assert depo.docs["config/app"]["notice"]["text"] == "Bakım"


def test_notice_firestore_yokken_500(depo, monkeypatch):
    monkeypatch.setattr(firestore_client, "get_client", lambda: None)
    with TestClient(app) as client:
        assert client.post("/api/v1/admin/config/notice",
                           json={"text": "x"}).status_code == 500


def test_attention_liste_items_altinda(depo, monkeypatch):
    """Denetim bulgusu: servis LİSTE döner; `{**liste}` her çağrıda 500
    veriyordu ve zil sessizce boş kalıyordu. Yanıt `items` altında."""
    monkeypatch.setattr(admin_service, "attention", lambda: [
        {"tur": "failedPushesToday", "sayi": 6, "rota": "#/bildirimler",
         "seviye": "hata"}])
    with TestClient(app) as client:
        yanit = client.get("/api/v1/admin/attention")
    assert yanit.status_code == 200
    assert yanit.json()["items"][0]["sayi"] == 6

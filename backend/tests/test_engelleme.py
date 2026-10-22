"""Engelleme UYGULANIYOR mu? (U17, App Store Guideline 1.2)

Kusur: "Engelle" `users/{uid}/blocked/{hedef}` kaydını yazıyordu ama o
kaydı OKUYAN hiçbir şey yoktu. Engellenen kişi yeni arkadaşlık isteği
atabiliyor, alıcıya davet push'u düşüyordu; inceleyici bunu engellemenin
işlemediği diye okur. Üç kapı sabitleniyor:

1. firestore.rules — friends create'in İKİ dalı da engel kaydına bakar:
   counterpart (`incoming`) alıcının listesine — engellenen davet atamaz;
   sahip (`outgoing`) gönderenin listesine `existsAfter` ile — engelleyen
   de engellediğine davet atamaz, meğer engeli aynı batch'te silsin.
   Emülatör koşum düzeneği yok; test_face_consent'teki gibi statik bekçi:
   yorumlar atılır (bekçi kuralı ANLATAN yorumu görüp geçmesin), koruma
   ilgili dalın İÇİNDE aranır.
2. /notify/invite ve /notify/reaction — alıcı göndereni engellediyse push
   atlanır.
3. /contacts/match — engelleyenin kartı engellenene dönmez.

Çalıştırma:
    .venv/bin/python -m pytest -q -p no:cacheprovider tests/test_engelleme.py
"""
from __future__ import annotations

import pathlib
import re
import types

import pytest
from fastapi.testclient import TestClient

from core import config
from services import notification_service as ns
from services import profile_service, push_service

from _sahte_firestore import SahteFirestore

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover - ortama bağlı
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulaması içe aktarılamadı: {_APP_IMPORT_ERROR}",
)

_KOK = pathlib.Path(__file__).resolve().parents[2]


# --------------------------------------------------------------------------
# 1. Kurallar (statik)
# --------------------------------------------------------------------------

def _kurallar_yorumsuz() -> str:
    """Kural dosyası, `//` yorumları atılmış ve boşlukları teke inmiş.

    Dosyada `//` yalnız yorum açar (yollar tek eğik çizgili). Yorum
    atılmazsa korumayı ANLATAN bir yorum satırı, koruma silinse bile
    bekçiyi geçirirdi.
    """
    metin = (_KOK / "infra" / "firestore.rules").read_text(encoding="utf-8")
    satirlar = [s.split("//", 1)[0] for s in metin.splitlines()]
    return " ".join(" ".join(satirlar).split())


def _ifade(kurallar: str, eslesme: str, izin: str) -> str:
    """`eslesme` bloğundaki `allow <izin>:` ifadesi (`;`e kadar)."""
    bas = kurallar.index(eslesme)
    izin_bas = kurallar.index(f"allow {izin}:", bas)
    return kurallar[izin_bas:kurallar.index(";", izin_bas)]


_ENGEL_KORUMASI = re.compile(
    r"\(\s*counterpart\(\)\s*&&\s*request\.resource\.data\.status\s*==\s*"
    r"'incoming'\s*&&\s*!exists\(/databases/\$\(database\)/documents/users/"
    r"\$\(uid\)/blocked/\$\(request\.auth\.uid\)\)\s*\)")


def test_kural_engellenen_gelen_davet_kenari_kuramaz():
    """Koruma counterpart dalının İÇİNDE, doğru yönde olmalı.

    Yol `users/{uid}/friends/{otherUid}`: `uid` davetin ALICISI,
    `request.auth.uid` gönderen. `blocked/$(uid)` ile ters yazılsa kural
    derlenir ama alıcının değil GÖNDERENİN listesine bakar — engelleyen
    kişi davet atamaz, engellenen atmaya devam eder.
    """
    create = _ifade(_kurallar_yorumsuz(), "match /friends/{otherUid}",
                    "create")
    assert _ENGEL_KORUMASI.search(create), (
        "friends create'in 'incoming' dalında engel kapısı yok ya da yönü "
        "ters: engellenen kişi yeni davet kenarı kurabilir (U17).\n" + create)
    # 'incoming' yazabilen TEK dal korumalı dal olmalı; korumasız ikinci
    # bir `|| (counterpart() && ... 'incoming')` kapıyı delerdi.
    assert create.count("'incoming'") == 1, create


_ENGELLEYEN_KORUMASI = re.compile(
    r"\(\s*isOwner\(uid\)\s*&&\s*request\.resource\.data\.status\s*==\s*"
    r"'outgoing'\s*&&\s*!existsAfter\(/databases/\$\(database\)/documents/"
    r"users/\$\(uid\)/blocked/\$\(otherUid\)\)\s*\)")


def test_kural_engelleyen_engelledigine_davet_atamaz():
    """İkinci yön (U17 incelemesi): A, B'yi engelledikten sonra B'ye davet
    atabiliyordu; B kabul edince ikisi `accepted` arkadaş olurdu ve engel
    kaydı dururken B dürtme atabilirdi.

    Burada `uid` davetin GÖNDERENİ (sahip dalı), yani gönderenin kendi
    listesine bakılır. `exists` DEĞİL `existsAfter` olmalı: istemci "engeli
    kaldır + davet et"i tek batch'te yazıyor ve batch kuralları `exists`
    ile yazım ÖNCESİ durumu görür — `exists` yazılsa kural derlenir ama
    meşru engel kaldırma daveti de düşerdi.
    """
    create = _ifade(_kurallar_yorumsuz(), "match /friends/{otherUid}",
                    "create")
    assert _ENGELLEYEN_KORUMASI.search(create), (
        "friends create'in 'outgoing' dalında engelleyen kapısı yok, yönü "
        "ters ya da existsAfter değil (U17).\n" + create)
    # 'outgoing' yazabilen TEK dal korumalı dal olmalı.
    assert create.count("'outgoing'") == 1, create


def test_kural_durtme_kabul_edilmis_arkadaslik_istiyor():
    """Dürtme için ayrı engel kuralı YOK — bu testin sabitlediği şart
    sayesinde gerekmiyor: create alıcının ağacında `accepted` kenar ister
    ve engelleme iki kenarı da siler. Şart gevşerse engellenen kişi
    dürtme atabilir hâle gelir ve U17 sessizce yeniden açılır."""
    create = _ifade(_kurallar_yorumsuz(), "match /nudges/{nudgeId}",
                    "create")
    assert ("get(/databases/$(database)/documents/users/$(uid)/friends/"
            "$(request.auth.uid)).data.status == 'accepted'") in create, create


def test_kural_engel_kaydi_yeniden_yazilabilir():
    """İstemci engeli kenar silimiyle tek batch'te yazar. Zaten engelli
    birine `set` motor için update'tir; update kapalıyken batch'in tamamı
    düşer ve arkadaşlık kenarları da silinmezdi."""
    kurallar = _kurallar_yorumsuz()
    acilis = "match /blocked/{targetUid} {"
    bas = kurallar.index(acilis) + len(acilis)
    blok = kurallar[bas:kurallar.index("}", bas)]
    izinler = re.search(r"allow ([a-z, ]+): if isOwner\(uid\)", blok)
    assert izinler, blok
    assert {"read", "create", "update", "delete"} <= {
        s.strip() for s in izinler.group(1).split(",")}, blok


# --------------------------------------------------------------------------
# 2. has_blocked
# --------------------------------------------------------------------------

def _depoya_bagla(monkeypatch, depo: SahteFirestore) -> None:
    """Yalnız profile_service sahte depodan okusun; uygulamanın geri
    kalanı (kapı, kimlik aynası) conftest pininde — Firestore yok."""
    monkeypatch.setattr(profile_service, "_user_doc",
                        lambda uid: depo.collection("users").document(uid))


def test_has_blocked_kaydi_okur(monkeypatch):
    depo = SahteFirestore({"users/alici/blocked/gonderen": {"at": 1}})
    _depoya_bagla(monkeypatch, depo)

    assert profile_service.has_blocked("alici", "gonderen") is True
    # Yön önemli: alıcının listesi gönderenin listesi değil.
    assert profile_service.has_blocked("gonderen", "alici") is False
    assert profile_service.has_blocked("alici", "baskasi") is False


def test_has_blocked_okuma_duserse_engelli_sayar(monkeypatch):
    """Yanlış 'engelli değil' engelleyene engellediğinden push düşürür;
    yanlış 'engelli' yalnız bir bildirimi kaçırtır."""
    class _Dusen:
        def collection(self, ad):
            raise RuntimeError("firestore yok")

    monkeypatch.setattr(profile_service, "_user_doc", lambda uid: _Dusen())
    assert profile_service.has_blocked("alici", "gonderen") is True


def test_has_blocked_firestore_yoksa_engel_yok():
    # conftest pini: get_client None. Davet kenarı da okunamaz, uç
    # zaten 403'te durur — burada True dönmek hiçbir şeyi korumazdı.
    assert profile_service.has_blocked("alici", "gonderen") is False


# --------------------------------------------------------------------------
# 3. /notify/invite
# --------------------------------------------------------------------------

def _davet_deposu(engel_yolu: str | None) -> SahteFirestore:
    """Gerçek bir davet: alıcının ağacında `incoming` kenar var (kural
    dağıtılmadan önce kurulabilen durum)."""
    ortak = {"fcmToken": "token-1", "onboardingCompleted": True,
             "timezone": "Europe/Istanbul", "language": "tr",
             "quietFrom": 0, "quietTo": 0}
    docs = {
        "users/alici": {**ortak, "displayName": "Alici"},
        "users/dev-user": {**ortak, "displayName": "Gonderen"},
        "users/alici/friends/dev-user": {"status": "incoming"},
        "users/dev-user/friends/alici": {"status": "outgoing"},
    }
    if engel_yolu:
        docs[engel_yolu] = {"at": 1}
    return SahteFirestore(docs)


def _davet_gonder(monkeypatch, depo: SahteFirestore,
                  yol: str = "/api/v1/notify/invite",
                  govde: dict | None = None) -> tuple[dict, list]:
    _depoya_bagla(monkeypatch, depo)
    monkeypatch.setattr(config, "DEV_MODE", True)
    monkeypatch.setattr(ns, "already_sent", lambda uid, tur, gun: False)
    isaretlenen: list = []
    monkeypatch.setattr(ns, "mark_sent",
                        lambda uid, tur, gun: isaretlenen.append(uid))
    giden: list = []

    def sahte_send(mesajlar):
        giden.extend(mesajlar)
        return types.SimpleNamespace(sent=len(mesajlar), failed=0, pruned=[])

    monkeypatch.setattr(push_service, "send", sahte_send)
    with TestClient(app) as client:
        yanit = client.post(yol,
                            json=govde or {"friend_uid": "alici"},
                            headers={"Authorization": "Bearer test"})
    assert yanit.status_code == 200, yanit.text
    return yanit.json(), giden + isaretlenen


@uygulama_gerekir
def test_davet_pushu_engelleyene_gitmez(monkeypatch):
    govde, iz = _davet_gonder(
        monkeypatch, _davet_deposu("users/alici/blocked/dev-user"))
    assert govde == {"status": "skipped", "reason": "engelli"}
    assert iz == [], "push gönderildi ya da tekrar koruması işaretlendi"


@uygulama_gerekir
def test_davet_pushu_engel_yoksa_gider(monkeypatch):
    """Yukarıdaki testin eşi: aynı depo, engel kaydı yok → push gider.
    Böylece atlamanın sebebinin engel olduğu (sessiz saat, tercih ya da
    token değil) ölçülüyor."""
    govde, iz = _davet_gonder(monkeypatch, _davet_deposu(None))
    assert govde == {"status": "ok", "sent": 1}
    assert len(iz) == 2  # bir mesaj + bir tekrar koruması işareti


@uygulama_gerekir
def test_davet_pushu_gonderenin_kendi_engeline_bakmaz(monkeypatch):
    """Yön: GÖNDERENİN listesindeki alıcı pushu kesmez — o davetin
    sahibinin kendi kararı. Argümanlar ters çevrilirse bu test düşer."""
    govde, _ = _davet_gonder(
        monkeypatch, _davet_deposu("users/dev-user/blocked/alici"))
    assert govde["status"] == "ok"


# --------------------------------------------------------------------------
# 4. /notify/reaction
# --------------------------------------------------------------------------

def _arkadas_deposu(engel_yolu: str | None) -> SahteFirestore:
    """KABUL EDİLMİŞ arkadaşlık + (isteğe bağlı) engel kaydı BİRLİKTE.

    Kural dağıtılmadan önce gerçekten oluşabilen hâl: eski pakette
    engelleyen davet kapısı yoktu; engellediğini yeniden davet edip
    arkadaş olan kullanıcının engel kaydı yerinde kalır.
    """
    depo = _davet_deposu(engel_yolu)
    depo.collection("users").document("alici").collection(
        "friends").document("dev-user").set({"status": "accepted"})
    depo.collection("users").document("dev-user").collection(
        "friends").document("alici").set({"status": "accepted"})
    return depo


_TEPKI = {"friend_uid": "alici", "reaction": "hug"}


@uygulama_gerekir
def test_tepki_pushu_engelleyene_gitmez(monkeypatch):
    govde, iz = _davet_gonder(
        monkeypatch, _arkadas_deposu("users/alici/blocked/dev-user"),
        yol="/api/v1/notify/reaction", govde=_TEPKI)
    assert govde == {"status": "skipped", "reason": "engelli"}
    assert iz == [], "push gönderildi ya da tekrar koruması işaretlendi"


@uygulama_gerekir
def test_tepki_pushu_engel_yoksa_gider(monkeypatch):
    """Eş test: aynı arkadaşlık, engel kaydı yok → push gider."""
    govde, iz = _davet_gonder(monkeypatch, _arkadas_deposu(None),
                              yol="/api/v1/notify/reaction", govde=_TEPKI)
    assert govde == {"status": "ok", "sent": 1}
    assert len(iz) == 2


@uygulama_gerekir
def test_tepki_pushu_gonderenin_kendi_engeline_bakmaz(monkeypatch):
    govde, _ = _davet_gonder(
        monkeypatch, _arkadas_deposu("users/dev-user/blocked/alici"),
        yol="/api/v1/notify/reaction", govde=_TEPKI)
    assert govde["status"] == "ok"


# --------------------------------------------------------------------------
# 5. /contacts/match
# --------------------------------------------------------------------------

def _rehber_deposu(monkeypatch, ek: dict) -> None:
    docs = {
        "users/dev-user": {"contactMatch": True},
        "phoneHashes/h-deniz": {"uid": "u-deniz"},
        "users/u-deniz": {"contactMatch": True},
        "publicProfiles/u-deniz": {"displayName": "Deniz",
                                   "username": "deniz"},
        **ek,
    }
    depo = SahteFirestore(docs)
    monkeypatch.setattr("api.contacts.firestore_client.get_client",
                        lambda: depo)
    monkeypatch.setattr(config, "DEV_MODE", True)


def _eslesmeler() -> list:
    with TestClient(app) as client:
        yanit = client.post("/api/v1/contacts/match",
                            json={"hashes": ["h-deniz"]},
                            headers={"Authorization": "Bearer test"})
    assert yanit.status_code == 200, yanit.text
    return yanit.json()["matches"]


@uygulama_gerekir
def test_rehber_engelleyenin_kartini_engellenene_gostermez(monkeypatch):
    _rehber_deposu(monkeypatch, {"users/u-deniz/blocked/dev-user": {"at": 1}})
    assert _eslesmeler() == []


@uygulama_gerekir
def test_rehber_engel_yoksa_kart_doner(monkeypatch):
    _rehber_deposu(monkeypatch, {})
    assert [k["uid"] for k in _eslesmeler()] == ["u-deniz"]


@uygulama_gerekir
def test_rehber_cagiranin_kendi_engeli_karti_gizlemez(monkeypatch):
    """Koruma engelleyen içindir; engelleyenin kendi rehberinde kişi
    görünmeye devam eder (gizlense istemci onu 'uygulamada yok' sanıp
    davet önerirdi)."""
    _rehber_deposu(monkeypatch, {"users/dev-user/blocked/u-deniz": {"at": 1}})
    assert [k["uid"] for k in _eslesmeler()] == ["u-deniz"]

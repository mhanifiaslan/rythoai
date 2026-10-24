"""Push yükü ve ölü jeton budaması bekçileri (iOS bildirim turu, 2026-10-24).

İkisi de yalnız iPhone'da, yalnız canlıda görünen kusurlar; derleme ve
geri kalan takım yeşil kalır.

**Yük.** iOS'ta arka plandaki uygulamanın bildirimini işletim sistemi
çizer ve bunun için mesajda `notification` (APNs `alert`) bloğu olmalı:
Apple'a göre uyarısız (content-available) bildirim ekranda hiçbir şey
göstermez. Ses de `apns.payload.aps.sound` ile gelir. Görünür push için
Info.plist'teki arka plan kipi GEREKMİYOR (gerekçe
`apps/mobile/ios/Runner/Info.plist` yorumunda) — yani görünürlüğü taşıyan
şey bu yük ve onu bugüne kadar hiçbir test tutmuyordu.

**Budama.** `send` ölü jetonu profilden siler (`_prune_token`). FCM'in
THIRD_PARTY_AUTH_ERROR'ı (firebase_admin `ThirdPartyAuthError`) jetonun
değil APNs anahtarının hatası: Firebase'de anahtar yüklü değilse ya da
yanlışsa her iOS gönderimi bunu alır. Ölü jeton sayılsaydı eksik bir
anahtar tek koşuda bütün iOS kullanıcılarının jetonunu silerdi; anahtar
düzeltildikten sonra da o kullanıcılara bildirim gitmezdi — jeton ancak
uygulama onu yeniden yazınca (açılışta `syncNotificationContext`)
döner.

**Eşleşme sınıf ADIYLA oluyor (ölçüldü 2026-10-24, firebase_admin
7.5.0).** `send`'in ilk dalı `exception.cause.code`'a bakıyor, ama gerçek
istisnada `cause` bir `requests.HTTPError` ve `code` niteliği yok; ad
`type(...).__name__`'e düşüyor ("THIRDPARTYAUTHERROR", "UNREGISTEREDERROR")
ve `_DEAD_TOKEN_ERRORS`'taki dizelerin hiçbiri bir sınıf adıyla eşleşmiyor.
Budamayı fiilen `_olu_token` yapıyor. Bu yüzden istisnalar elle uydurulmaz:
firebase_admin'in KENDİ hata işleyicisine FCM biçimli bir hata gövdesi
verilir ve dönen nesne kullanılır — `send_each`'in `SendResponse`'a
koyduğu nesnenin aynısı. Sahte bir `code` niteliği ilk dalı yapay olarak
eşleştirir ve bekçi gerçek akışı değil kendi uydurmasını sınardı.

Dış dünyaya çıkış yok: `_get_messaging` gerçek modülün `send*` dışındaki
her şeyini veren bir vekille değiştirilir (`initialize_app` ve ağ hiç
çağrılmaz); Firestore paylaşımlı sahteyle (conftest `firestore_hermetik`
pininin çıkış yolu).
"""
from __future__ import annotations

import json

import pytest
import requests
from firebase_admin import _utils
from firebase_admin import messaging as gercek_messaging

from core import firestore as firestore_client
from services import push_service
from _sahte_firestore import SahteFirestore


class _KayitliMesajlasma:
    """Gerçek `firebase_admin.messaging`; yalnız `send_each` ağa çıkmaz.

    Mesaj sınıfları GERÇEK: yükü kuran kod gerçek doğrulamadan geçer ve
    kodlanmış biçimi gerçek kodlayıcıdan okunur. `send*` adlı başka bir
    çağrı (ör. `send_each_for_multicast`'e dönüş) sahtelenmediği için
    burada patlar; ağa sessizce gitmez.
    """

    def __init__(self, yanit_uret):
        self.gonderilen: list = []
        self._uret = yanit_uret

    def __getattr__(self, ad):
        if ad.startswith("send"):
            raise AssertionError(f"sahtelenmemiş gönderim çağrısı: {ad}")
        return getattr(gercek_messaging, ad)

    def send_each(self, mesajlar, dry_run=False):  # noqa: ARG002
        self.gonderilen.extend(mesajlar)
        return gercek_messaging.BatchResponse(
            [self._uret(i) for i in range(len(mesajlar))])


def _basari(_i):
    return gercek_messaging.SendResponse({"name": "projects/p/messages/1"},
                                         None)


def _fcm_hatasi(fcm_kodu: str, http: int, durum: str):
    """FCM v1 hata gövdesinden firebase_admin'in KENDİ ürettiği istisna."""
    yanit = requests.Response()
    yanit.status_code = http
    yanit.headers["content-type"] = "application/json"
    yanit._content = json.dumps({"error": {
        "code": http, "message": "bekci", "status": durum,
        "details": [{
            "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
            "errorCode": fcm_kodu}]}}).encode()
    hata = requests.exceptions.HTTPError("bekci", response=yanit)
    return _utils.handle_platform_error_from_requests(
        hata, gercek_messaging._MessagingService._build_fcm_error_requests)


def _mesaj(uid: str, token: str, baslik: str = "Bugün",
           govde: str = "Gökyüzü seninle") -> push_service.Message:
    return push_service.Message(uid=uid, token=token, title=baslik,
                                body=govde, data={"route": "/sky"})


@pytest.fixture
def depo(monkeypatch):
    d = SahteFirestore({f"users/u{i}": {"fcmToken": f"t{i}"}
                        for i in range(1, 4)})
    monkeypatch.setattr(firestore_client, "get_client", lambda: d)
    return d


def _vekil_kur(monkeypatch, yanit_uret) -> _KayitliMesajlasma:
    vekil = _KayitliMesajlasma(yanit_uret)
    monkeypatch.setattr(push_service, "_get_messaging", lambda: vekil)
    return vekil


# ------------------------------------------------------------------- yük

def test_her_mesaj_gorunur_bildirim_ve_ses_tasir(monkeypatch, depo):
    """Kodlanmış (FCM'e giden) biçim okunur: nesne niteliği değil, kabloya
    çıkan yük. Her mesaj — partinin ilki değil hepsi."""
    vekil = _vekil_kur(monkeypatch, _basari)
    girdiler = [_mesaj(f"u{i}", f"t{i}", f"başlık {i}", f"gövde {i}")
                for i in range(1, 4)]

    sonuc = push_service.send(girdiler)

    assert sonuc.sent == 3 and sonuc.failed == 0, sonuc
    assert len(vekil.gonderilen) == len(girdiler)
    for girdi, fcm in zip(girdiler, vekil.gonderilen):
        yuk = gercek_messaging._MessagingService.encode_message(fcm)
        assert yuk.get("token") == girdi.token
        assert yuk.get("notification") == {
            "title": girdi.title, "body": girdi.body}, (
            f"{girdi.uid}: notification bloğu yok ya da eksik — iOS'ta "
            f"arka plandaki uygulamaya bildirim GÖRÜNMEZ: {yuk}")
        aps = yuk.get("apns", {}).get("payload", {}).get("aps", {})
        assert aps.get("sound"), (
            f"{girdi.uid}: apns.payload.aps.sound yok — iOS bildirimi "
            f"sessiz düşer: {yuk}")


# ---------------------------------------------------------------- budama

@pytest.mark.parametrize("fcm_kodu, http, durum, sinif, budanir", [
    # APNs anahtarı/ortamı hatası: jeton SAĞLAM, budanmaz.
    ("THIRD_PARTY_AUTH_ERROR", 401, "UNAUTHENTICATED",
     gercek_messaging.ThirdPartyAuthError, False),
    # Eski adı; firebase_admin aynı sınıfa eşliyor.
    ("APNS_AUTH_ERROR", 401, "UNAUTHENTICATED",
     gercek_messaging.ThirdPartyAuthError, False),
    # Gerçekten ölü jeton: budanır.
    ("UNREGISTERED", 404, "NOT_FOUND",
     gercek_messaging.UnregisteredError, True),
    ("SENDER_ID_MISMATCH", 403, "PERMISSION_DENIED",
     gercek_messaging.SenderIdMismatchError, True),
])
def test_olu_jeton_budamasi_gercek_istisnayla(monkeypatch, depo, fcm_kodu,
                                              http, durum, sinif, budanir):
    istisna = _fcm_hatasi(fcm_kodu, http, durum)
    # Önkoşul: bekçinin dayandığı şekil. Bu iki satır kızarırsa
    # firebase_admin hatayı başka biçimde taşımaya başlamış demektir ve
    # push_service'in eşleşmesi yeniden ölçülmeli.
    assert type(istisna) is sinif, type(istisna)
    assert isinstance(istisna.cause, requests.exceptions.HTTPError)

    _vekil_kur(monkeypatch,
               lambda _i: gercek_messaging.SendResponse(None, istisna))
    sonuc = push_service.send([_mesaj("u1", "t1")])

    assert sonuc.sent == 0 and sonuc.failed == 1
    assert sonuc.failed_uids == ["u1"], "başarısız gönderim sayılmalı"
    if budanir:
        assert sonuc.pruned == ["u1"]
        assert depo.docs["users/u1"]["fcmToken"] is None
    else:
        assert sonuc.pruned == [], (
            f"{fcm_kodu} jetonu BUDADI: eksik APNs anahtarı tek koşuda "
            "bütün iOS jetonlarını siler")
        assert depo.docs["users/u1"]["fcmToken"] == "t1"
        assert depo.yazimlar == [], depo.yazimlar


def test_karisik_partide_yalniz_olu_jeton_budanir(monkeypatch, depo):
    """Yanıt sırası girdi sırasıyla aynı (send'in sözü): anahtar hatası
    alan kullanıcı ile ölü jetonlu kullanıcı karışmamalı."""
    yanitlar = [
        gercek_messaging.SendResponse({"name": "projects/p/messages/1"}, None),
        gercek_messaging.SendResponse(
            None, _fcm_hatasi("THIRD_PARTY_AUTH_ERROR", 401,
                              "UNAUTHENTICATED")),
        gercek_messaging.SendResponse(
            None, _fcm_hatasi("UNREGISTERED", 404, "NOT_FOUND")),
    ]
    _vekil_kur(monkeypatch, lambda i: yanitlar[i])

    sonuc = push_service.send([_mesaj(f"u{i}", f"t{i}") for i in range(1, 4)])

    assert (sonuc.sent, sonuc.failed) == (1, 2)
    assert sonuc.failed_uids == ["u2", "u3"]
    assert sonuc.pruned == ["u3"]
    assert depo.docs["users/u2"]["fcmToken"] == "t2"
    assert depo.docs["users/u3"]["fcmToken"] is None


# ------------------------------------------------------------------- pin

def test_pin_sahtelenmemis_send_fcm_e_ulasmaz(monkeypatch, depo):
    """conftest `push_hermetik` pininin BEYANI ölçülür: `send`i ya da
    `_get_messaging`i sahtelemeyen bir test gerçek FCM istemcisine HİÇ
    ulaşmaz (davranışsal; kaynak eşleşmesi değil — pin yarın başka bir
    satıra taşınsa da bu soru aynı kalır).

    Kaydedici gerçek modülün `send_each`inin ve `initialize_app`ın yerine
    konur: ulaşılırsa pin delik demektir. Para da bildirim de çıkmaz —
    kaydedici ağa gitmiyor."""
    import firebase_admin

    ulasilan = []
    monkeypatch.setattr(gercek_messaging, "send_each",
                        lambda *a, **k: ulasilan.append("send_each"))
    monkeypatch.setattr(firebase_admin, "initialize_app",
                        lambda *a, **k: ulasilan.append("initialize_app"))

    sonuc = push_service.send([_mesaj("u1", "t1")])

    assert ulasilan == [], f"pin delik: gerçek FCM yoluna ulaşıldı {ulasilan}"
    # Üretimin "FCM kullanılamıyor" dalı: hepsi başarısız, jeton silinmez.
    assert (sonuc.sent, sonuc.failed, sonuc.pruned) == (0, 1, [])
    assert depo.docs["users/u1"]["fcmToken"] == "t1"

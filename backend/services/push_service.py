"""FCM gönderimi — tek sorumluluğu bildirimleri iletmek.

Kime/ne zaman kararı notification_service'te; bu modül yalnızca gönderir ve
gönderemediklerini raporlar. Ayrım sayesinde zamanlama mantığı FCM'e hiç
dokunmadan test edilebiliyor.

**Geçersiz token temizliği burada yapılır.** Uygulama silindiğinde token
ölür ama Firestore'da kalır; temizlenmezse her toplu gönderimde ölü
token'lara denenir, kota ve süre boşa gider.
"""
from __future__ import annotations

import logging
from typing import Any, NamedTuple

from core import config, firestore as firestore_client

logger = logging.getLogger(__name__)

#: FCM'in tek çağrıda kabul ettiği en fazla token sayısı.
FCM_BATCH_SIZE = 500

#: Android bildirim kanalı. İstemcide tanımlı kanalla AYNI olmak zorunda
#: (apps/mobile/lib/core/notifications.dart, `_kChannel`). Eşleşmezse Android
#: bildirimi varsayılan kanala düşürür ve ekranın üstünde belirmez.
ANDROID_CHANNEL_ID = "rytho_default"

#: Token'ın artık geçersiz olduğunu gösteren hata kodları. Bunlar dışındaki
#: hatalar geçici sayılır ve token silinmez.
#:
#: ⚠️ firebase_admin 7.5.0'da bu küme HİÇ eşleşmiyor (mutasyonla ölçüldü
#: 2026-10-24, test_push_yuku): `exception.cause` bir `requests.HTTPError`
#: ve `code` niteliği yok; kod yerine sınıf adı (`UNREGISTEREDERROR` gibi)
#: kalıyor. Budamayı fiilen `_olu_token`'ın SINIF ADI eşlemesi yapıyor.
#: Küme, `cause`'un kod taşıdığı bir SDK sürümüne karşı zararsız bir yedek
#: olarak duruyor (öyle bir sürüm ölçülmedi). `THIRD_PARTY_AUTH_ERROR`
#: (APNs anahtarı eksik/yanlış) BİLEREK yok: o hata jetonun değil
#: yapılandırmanın kusuru; budansaydı eksik anahtar bütün iOS jetonlarını
#: sessizce silerdi.
_DEAD_TOKEN_ERRORS = {
    "UNREGISTERED",
    "INVALID_ARGUMENT",
    "SENDER_ID_MISMATCH",
}

_messaging = None


def _get_messaging():
    """firebase_admin.messaging modülü; başlatılamazsa ``None``.

    Başlatma core.auth ile aynı uygulamayı paylaşır (firebase_admin tek bir
    varsayılan app tutar), bu yüzden burada ayrıca initialize edilmez.
    """
    global _messaging
    if _messaging is not None:
        return _messaging
    try:
        import firebase_admin
        from firebase_admin import messaging

        if not firebase_admin._apps:
            firebase_admin.initialize_app(
                options={"projectId": config.GOOGLE_CLOUD_PROJECT})
        _messaging = messaging
        return _messaging
    except Exception as exc:  # pragma: no cover
        logger.warning("FCM baslatilamadi: %s", exc)
        return None


class Message(NamedTuple):
    """Tek bir kullanıcıya gidecek bildirim."""

    uid: str
    token: str
    title: str
    body: str
    #: İstemcinin dokunma sonrası nereye gideceğini bilmesi için.
    data: dict[str, str]


class SendResult(NamedTuple):
    sent: int
    failed: int
    #: Token'ı ölmüş kullanıcılar — kayıtları temizlendi.
    pruned: list[str]
    #: Gönderimi BAŞARISIZ olan tüm kullanıcılar (ölü token + geçici hata
    #: + parti hatası). OT1.5: çağıran bunları "gönderildi" saymamalı —
    #: eskiden yalnız `pruned` atlanıyordu ve geçici bir FCM hatası
    #: kullanıcının o gününü sessizce yakıyordu.
    failed_uids: list[str]


def _prune_token(uid: str) -> None:
    """Ölü token'ı profilden siler."""
    client = firestore_client.get_client()
    if client is None:
        return
    try:
        client.collection("users").document(uid).update({"fcmToken": None})
    except Exception as exc:
        logger.warning("Olu token silinemedi (%s): %s", uid, exc)


def send(messages: list[Message]) -> SendResult:
    """Bildirimleri 500'lük partiler hâlinde gönderir.

    ``send_each`` kullanılır ve parti tavanı 500'dür (SDK'nın sınırı).
    firebase_admin 7.5.0'da ``send_each`` mesaj başına AYRI bir FCM v1 HTTP
    isteği atar, partiyi eşzamanlı gönderir (iş parçacığı havuzu; kaynakta
    okundu 2026-10-24) — yani 5000 kullanıcı 5000 istektir, "10 istek"
    değil. Yanıt sırası girdi sırasıyla aynıdır (``executor.map`` sırayı
    korur); hataları bu sayede doğru kullanıcıya bağlarız.
    """
    if not messages:
        return SendResult(0, 0, [], [])

    messaging = _get_messaging()
    if messaging is None:
        logger.error("FCM kullanilamiyor; %d bildirim gonderilemedi",
                     len(messages))
        return SendResult(0, len(messages), [], [m.uid for m in messages])

    gonderilen = basarisiz = 0
    temizlenen: list[str] = []
    basarisiz_uidler: list[str] = []

    for i in range(0, len(messages), FCM_BATCH_SIZE):
        parti = messages[i:i + FCM_BATCH_SIZE]
        # Kanal kimligi istemcideki kanalla AYNI olmak zorunda
        # (apps/mobile/lib/core/notifications.dart). Farkli olsaydi Android
        # bildirimi varsayilan kanala dusurur ve ekranin ustunde belirmezdi.
        #
        # Oncelik "high": "normal" oncelikli bildirimler cihaz uyku modundayken
        # toplanip geciktirilebiliyor. Gunluk okuma bildirimi sabah 09:00'da
        # anlamli; ogleden sonra gelmesi degerini kaybettirir.
        fcm_mesajlari = [
            messaging.Message(
                token=m.token,
                notification=messaging.Notification(title=m.title, body=m.body),
                data=m.data,
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        channel_id=ANDROID_CHANNEL_ID),
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(sound="default")),
                ),
            )
            for m in parti
        ]

        try:
            yanit = messaging.send_each(fcm_mesajlari)
        except Exception as exc:
            logger.exception("FCM parti gonderimi basarisiz", exc_info=exc)
            basarisiz += len(parti)
            basarisiz_uidler.extend(m.uid for m in parti)
            continue

        for mesaj, sonuc in zip(parti, yanit.responses):
            if sonuc.success:
                gonderilen += 1
                continue
            basarisiz += 1
            basarisiz_uidler.append(mesaj.uid)
            kod = getattr(getattr(sonuc.exception, "cause", None), "code", None)
            kod = kod or type(sonuc.exception).__name__
            if str(kod).upper() in _DEAD_TOKEN_ERRORS or _olu_token(sonuc):
                _prune_token(mesaj.uid)
                temizlenen.append(mesaj.uid)
            else:
                logger.info("Bildirim gonderilemedi (%s): %s",
                            mesaj.uid, sonuc.exception)

    return SendResult(gonderilen, basarisiz, temizlenen, basarisiz_uidler)


def _olu_token(sonuc: Any) -> bool:
    """firebase_admin sürümleri hatayı farklı sınıflarda taşıyor."""
    istisna = getattr(sonuc, "exception", None)
    if istisna is None:
        return False
    ad = type(istisna).__name__
    return ad in ("UnregisteredError", "SenderIdMismatchError")

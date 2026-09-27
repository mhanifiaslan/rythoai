"""Üçüncü taraf AI (Google Gemini) aktarım onayının SUNUCU kapısı — U06.

Apple 5.1.2(i): kişisel veri üçüncü taraf bir AI'ya gitmeden ÖNCE
kullanıcıdan uygulama içinde açık izin alınmalı. İzin ekranı istemcide
(`apps/mobile/lib/core/ai_consent.dart`); bu modül iki şeyi yapar:

1. **Karar** (`izin_karari`) — saf fonksiyon, kayıt + sürüm + eşikten
   izin çıkarır. Uçlar ve sabah bildirimi aynı kararı kullanır.
2. **Zorlama** — AI uçlarında 403 (`ai_onayi_zorunlu`) ya da yumuşak
   uçlarda AI katmanını atlama (`ai_katmani_acik`).

## Neden eşikli (aiConsentMinBuild)

Bugün yayında olan Android paketlerinde onay ekranı YOK. Sunucu "kayıt
yoksa reddet" deseydi o paketlerdeki her kullanıcının sohbeti, raporları
ve yüz okuması tek deploy'la kapanırdı — ve kullanıcı onayı verecek bir
ekran da bulamazdı. Bu yüzden "hiç sorulmadı" (kayıt yok) durumu YALNIZ
`X-App-Build >= eşik` olan isteklerde reddedilir; eşik onay ekranlı
Android paketi yayınlandıktan SONRA yükseltilir (U29, `minBuild` ile aynı
operasyon deseni). Varsayılan 0 = zorlama kapalı.

## Eşik neyi KAPSAMAZ

Kullanıcının AÇIK "hayır"ı (geri alma ya da "Şimdi değil" → kayıtta
``granted: False``) eşikten BAĞIMSIZ her sürümde ve sabah bildiriminde
geçerlidir. Eşik yalnız eski istemcileri korumak için var; onay ekranını
görüp reddetmiş birinin verisini "zorlama kapalıydı" diye göndermek,
ekranın kendisini yalan yapardı.

Onay ekranlı istemci, kullanıcı henüz karar vermemişken yumuşak uçlara
(`/reports/signals`, `/astrology/transit-calendar`, `/reports/relationship`)
`ai=0` gönderir — eşik kapalıyken de ilk açılıştaki ana ekran isteği
kullanıcının haritasını Gemini'ye göndermesin diye.
"""
from __future__ import annotations

import logging
import time
from typing import Any

from fastapi import Depends, Header, HTTPException

from core import app_gate, config
from core.auth import AuthUser, get_current_user
from core.i18n import get_language
from core.messages import text

logger = logging.getLogger(__name__)

#: 403 yanıtındaki makine işareti. `detail` kullanıcıya olduğu gibi basılan
#: İNSAN metni (eski istemciler `friendlyError` ile gösteriyor); istemcinin
#: onay sayfasını açma kararı bu başlığa bakar — metne gömülemez
#: (`X-Paywall-Reason` ile aynı desen).
HEADER = "X-Ai-Consent"
HEADER_REQUIRED = "required"

#: Eşik memo'sunun ömrü — `app_gate.MEMO_TTL` ile aynı gerekçe: panelden
#: ya da konsoldan yazılan değer en geç bu kadar sürede her instance'a
#: ulaşır, istek başına Firestore okuması yok.
MEMO_TTL = 60

#: Onay ekranını KESİNLİKLE taşımayan son sürüm: ekran 1.16.0+45'ten sonra
#: eklendi. Eşik bunun altına yazılırsa (ör. 46 yerine 4) zorlama
#: yayındaki bütün eski paketleri kapsardı — `app_gate`'in K9 bekçisinin
#: bu kapıdaki karşılığı. 0 < eşik <= bu değer ise eşik bir sonraki
#: sürüme çekilir. Doğru eşiği seçmek yine operatörün işi: onay ekranlı
#: kodu İÇEREN ilk paketin numarası (Windows dalı birleştirmeden 46
#: çıkarırsa 46 da ekransızdır).
ONAY_EKRANSIZ_SON_BUILD = 45

_memo: tuple[int, float] | None = None

#: Testlerin zamanı ilerletebilmesi için dolaylı saat.
_now = time.monotonic


def reset_memo() -> None:
    global _memo
    _memo = None


def _doc_esik() -> int:
    """`config/app.aiConsentMinBuild`; her hata 0 (env tabanı geçerli)."""
    try:
        veri = app_gate.read_doc() or {}
        return app_gate.parse_build(veri.get("aiConsentMinBuild"))
    except Exception as exc:
        logger.warning("config/app okunamadı; AI onay eşiği env: %s", exc)
        return 0


def current_min_build() -> int:
    """Etkin zorlama eşiği = max(env, `config/app.aiConsentMinBuild`).

    ASLA fırlatmaz; 0 = zorlama kapalı. Okuma hatası 0'a düşer: eşiği
    okuyamadığımız an ESKİ istemcileri kilitlemek, bu eşiğin var olma
    sebebini tersine çevirirdi. Açık "hayır" kaydı eşikten bağımsız
    olduğu için bu yön gizlilik açığı DOĞURMAZ.
    """
    global _memo
    if _memo is not None and _now() < _memo[1]:
        return _memo[0]
    deger = max(app_gate.parse_build(config.AI_CONSENT_MIN_BUILD), _doc_esik())
    if 0 < deger <= ONAY_EKRANSIZ_SON_BUILD:
        logger.warning("AI onay eşiği %d onay ekranı olmayan sürümleri "
                       "kapsıyor; %d'ye çekildi", deger,
                       ONAY_EKRANSIZ_SON_BUILD + 1)
        deger = ONAY_EKRANSIZ_SON_BUILD + 1
    _memo = (deger, _now() + MEMO_TTL)
    return deger


def izin_karari(kayit: Any, build: int, esik: int) -> bool:
    """Bu isteğin verisi Gemini'ye gidebilir mi? Saf fonksiyon.

    * güncel sürüm için ``granted: True`` → evet;
    * ``granted: False`` (geri alındı / "Şimdi değil") → HAYIR, sürüm ve
      eşik ne olursa olsun;
    * kayıt yok, bozuk ya da eski sürüm onayı → yalnız eşik bu isteğin
      sürümünü kapsıyorsa (``esik > 0 and build >= esik``) hayır; aksi
      hâlde onay ekranı olmayan eski istemcidir, izin verilir.
    """
    from services import consent_service

    if consent_service.ai_kaydi_gecerli(kayit):
        return True
    if isinstance(kayit, dict) and kayit.get("granted") is False:
        return False
    return not (esik > 0 and build >= esik)


def izin_var(uid: str, build: int) -> bool:
    """`izin_karari`nın kayıt okuyan hâli. Okuma hatası → HAYIR.

    Kaydı okuyamadığımızda kullanıcının açık "hayır"ını göremeyiz; o an
    izin vermek, reddetmiş birinin verisini göndermek olabilirdi.
    Firestore'un düştüğü an AI uçları zaten profil okuyamadığı için
    çalışmıyor — kapalı taraf fiilen ek bir kesinti yaratmıyor.
    """
    from services import consent_service

    try:
        kayit = consent_service.ai_consent(uid)
    except Exception as exc:
        logger.warning("AI onayı okunamadı (%s): %s", uid, exc)
        return False
    return izin_karari(kayit, build, current_min_build())


def reddet(lang: str) -> HTTPException:
    """AI uçlarının ortak 403'ü — işaret başlıkta, insan metni detail'de."""
    return HTTPException(status_code=403,
                         detail=text("ai_consent_required", lang),
                         headers={HEADER: HEADER_REQUIRED})


def ai_onayi_zorunlu(user: AuthUser = Depends(get_current_user),
                     lang: str = Depends(get_language),
                     x_app_build: str | None = Header(default=None)) -> None:
    """Tamamen AI olan uçların bağımlılığı: izin yoksa 403.

    `get_current_user` FastAPI'nin istek içi bağımlılık önbelleğinden
    gelir — `require_plus` ile birlikte kullanıldığında kimlik iki kez
    doğrulanmaz.
    """
    if not izin_var(user.uid, app_gate.parse_build(x_app_build)):
        raise reddet(lang)


def ai_katmani_acik(uid: str, x_app_build: str | None,
                    istemci_izni: bool = True) -> bool:
    """Yumuşak uçlar için: AI katmanı üretilsin mi?

    Hesap (sinyaller, takvim, eksenler) AI'sız da doğru ve ücretsiz; bu
    uçlar onay yokken HATA DÖNMEZ, yalnız yorum katmanını atlar.
    `istemci_izni` onay ekranlı istemcinin `ai=0` parametresidir — o
    False iken kayıt hiç okunmaz.
    """
    if not istemci_izni:
        return False
    return izin_var(uid, app_gate.parse_build(x_app_build))

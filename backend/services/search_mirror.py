"""Kullanıcı arama aynası (AD4): `users/{uid}` üzerinde sunucu yazımlı
küçük harf alanları — `emailLower`, `usernameLower`, `nameLower`.

## Neden

Panel binlerce kullanıcı arasında e-posta/kullanıcı adı/ad ile ANINDA
bulmalı. Firestore önek sorgusu (`>= q`, `< q + '\\uf8ff'`) büyük/küçük
harf duyarlı ve Türkçe I/İ tuzağına açık (bkz. hafıza notu: noktalı I).
Bu yüzden arama alanı ayrı bir normalize edilmiş kopyada tutulur; ayrı
bir arama koleksiyonu REDDEDİLDİ — süzgeçler zaten `users`'ta, tek
imleçle sayfalanır.

## Değişmezler

* `ensure` HİÇ FIRLATMAZ: kimlik yolundan (get_current_user) çağrılır;
  ayna hiçbir koşulda oturumu düşüremez (`app_gate.remember_build` dersi).
* Yalnız FARKLI alanlar yazılır: binlerce istekte gereksiz yazım yok; uid
  başına 24 saatlik süreç içi memo (profil özeti sağlaması değişince hemen
  yazılır).
* **Yazım `update`, `set` DEĞİL — ayna doküman YARATMAZ** (B9).
  `app_gate.remember_build` ile PAYLAŞILAN kural; gerekçesi `ensure`
  içinde ve orada.
* Alanlar istemciye KAPALI: rules `sunucuAlanlariDegismedi()` bekçisi.
"""
from __future__ import annotations

import hashlib
import logging
import time
import unicodedata
from typing import Any

from core import firestore as firestore_client

logger = logging.getLogger(__name__)

#: Aynı uid + aynı özet bu süre içinde yeniden yazılmaz/okunmaz.
MEMO_TTL = 24 * 3600

#: Memo bu boyu aşınca süresi dolanlar atılır (bellek büyümesi).
_MEMO_PRUNE_AT = 5000

#: uid -> (özet, monotonic son kullanma)
_memo: dict[str, tuple[str, float]] = {}

#: Testlerin zamanı ilerletebilmesi için dolaylı saat.
_now = time.monotonic

#: Profil alanı -> ayna alanı.
FIELDS = {"email": "emailLower", "username": "usernameLower",
          "displayName": "nameLower"}


def normalize(s: Any) -> str:
    """NFKC → İ→i, I→ı → casefold → strip.

    Türkçe noktalı/noktasız I casefold'dan ÖNCE çözülür: "İ".casefold()
    "i̇" (i + birleşen nokta) verir ve "istanbul" önekiyle eşleşmez;
    "I".casefold() "i" verir ve "ışık" kaybolur.
    """
    if s is None:
        return ""
    metin = unicodedata.normalize("NFKC", str(s))
    metin = metin.replace("İ", "i").replace("I", "ı")
    return metin.casefold().strip()


def compute(profil: dict[str, Any] | None) -> dict[str, str]:
    """Profilden ayna alanlarını türetir (alan yoksa boş dizgi)."""
    profil = profil or {}
    return {ayna: normalize(profil.get(kaynak))
            for kaynak, ayna in FIELDS.items()}


def reset_memo() -> None:
    _memo.clear()


def _ozet(degerler: dict[str, str]) -> str:
    ham = "\x1f".join(degerler[a] for a in sorted(degerler))
    return hashlib.sha1(ham.encode("utf-8")).hexdigest()


def _memo_taze(uid: str, ozet: str) -> bool:
    kayit = _memo.get(uid)
    return kayit is not None and kayit[0] == ozet and _now() < kayit[1]


def _memo_yaz(uid: str, ozet: str) -> None:
    if len(_memo) >= _MEMO_PRUNE_AT:
        simdi = _now()
        for anahtar, kayit in list(_memo.items()):
            if kayit[1] <= simdi:
                _memo.pop(anahtar, None)
    _memo[uid] = (ozet, _now() + MEMO_TTL)


def ensure(uid: str, profil: dict[str, Any] | None = None) -> bool:
    """Ayna alanlarını gerekiyorsa yazar; yazıldıysa True.

    `profil` verilmezse `users/{uid}` okunur (doküman yoksa yazım YOK —
    anonim RevenueCat kimlikleri gibi hayalet kullanıcı üretilmez).
    Memo profil VERİLDİĞİNDE özetle, verilmediğinde yalnız uid ile
    kıyaslanır: profil yoksa okumayı da 24 saatte bire indirmek amaçtır.

    ⚠️ **Yazım `update`, `set(merge=True)` DEĞİL** (B9, ölçüldü
    2026-09-28). Yukarıdaki "doküman yoksa yazım YOK" okuması TEK BAŞINA
    yetmiyor: okuma ile yazım ARASINDA bir pencere var. Silinen hesabın
    kimlik jetonu bir saate kadar geçerli kalıyor, yani `get` dokümanı
    GÖRÜRKEN araya `delete_account` girebiliyor; `set(merge=True)` o
    noktada dokümanı geri YARATIRDI. `update` var olmayan dokümana yazmaz
    — dirilme yapısal olarak imkânsız.

    Bu kapı sayesinde B9'un GENİŞ yolu (jeton penceresinin tamamı) burada
    hiç açılmadı; diriltme `app_gate.remember_build`ten geliyordu ve
    üretimde ölçülen yetim dokümanlarda yalnız `appBuild` vardı, ayna
    alanları YOKTU. Bulgu kaydı iki aynayı da aynı biçimde suçluyordu; o
    kısım yanlıştı. Kural yine de İKİSİNDE birden geçerli olmalı: paylaşan
    tek kural olmadan biri sessizce diriltmeye devam eder.

    Doküman yaratma sorumluluğu aynanın DEĞİL: `users/{uid}` oturum
    açılışında istemcide (`language_sync._firestoreWrite`) ve onboarding
    onayında sunucuda (`consent_service.grant_terms_consent`) doğuyor.
    Yeni kullanıcının aynası bu yüzden kaybolmaz: doğumdan önce gelen
    çağrı memo KURMADAN döner, doğumdan sonraki ilk çağrı yazar.
    """
    try:
        if not uid:
            return False
        if profil is None:
            kayit = _memo.get(uid)
            if kayit is not None and _now() < kayit[1]:
                return False
            client = firestore_client.get_client()
            if client is None:
                return False
            anlik = client.collection("users").document(uid).get()
            if not getattr(anlik, "exists", False):
                return False
            profil = anlik.to_dict() or {}
        else:
            client = None

        istenen = compute(profil)
        ozet = _ozet(istenen)
        if _memo_taze(uid, ozet):
            return False

        fark = {alan: deger for alan, deger in istenen.items()
                if profil.get(alan) != deger}
        if not fark:
            _memo_yaz(uid, ozet)
            return False

        client = client or firestore_client.get_client()
        if client is None:
            return False
        client.collection("users").document(uid).update(fark)
        _memo_yaz(uid, ozet)
        return True
    except Exception as exc:
        logger.warning("Arama aynası yazılamadı (%s): %s", uid, exc)
        return False

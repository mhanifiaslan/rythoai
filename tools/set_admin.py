"""Firebase custom claim `{admin: true, role: owner|support}` basar/kaldirir
(W4 + AD1).

Admin paneli (/rytho-admin) yetkisi BU claim'den gelir; panelde ayri bir
kullanici listesi yoktur. Claim yalnizca buradan, yerel makinede servis
hesabi kimligiyle basilir — uygulama ici hicbir yol claim yazamaz.

Roller:
    owner   — her sey: sil, devre disi, surum esigi, ortak yazimlari,
              disa aktarim, yeniden hesapla, duyuru, elle toplama.
    support — okur + sinirli yazar (kredi, cihaz kilidi, auth linki,
              bildirim provasi / kendine test).
`role` tasimayan eski `admin:true` claim'i sunucuda owner sayilir (gecis);
yine de bir kez `--role owner` ile yeniden basmak temiz olur.

Kullanim (repo kokunden):
    backend/.venv/Scripts/python tools/set_admin.py --email aslan.mh@gmail.com
    backend/.venv/Scripts/python tools/set_admin.py --email ... --role support
    backend/.venv/Scripts/python tools/set_admin.py --uid <uid>
    backend/.venv/Scripts/python tools/set_admin.py --email ... --revoke

Ortaklik claim'i (OP) — AYRI bir boyut, `admin` YAZMAZ:
    ... --email ortak@ornek.com --partner <partnerId>
    ... --email ortak@ornek.com --partner <partnerId> --revoke
Ortagin uid'i ayrica panelden `partners/{id}.uid` alanina yazilmali;
kendi kodunu kullanamama kapisi (redeem) o bagi kullaniyor.

Kimlik: GOOGLE_APPLICATION_CREDENTIALS servis hesabi anahtari ya da
`gcloud auth application-default login` (proje: rhytoai).

NOT: Claim, kullanicinin MEVCUT oturumuna hemen yansimaz — ID token
yenilenince (<=1 saat) ya da cikis/giris yapinca gecerli olur.
"""
from __future__ import annotations

import argparse
import sys

import firebase_admin
from firebase_admin import auth

ROLLER = ("owner", "support")


def main() -> int:
    p = argparse.ArgumentParser(description="Rytho admin claim yonetimi")
    kimlik = p.add_mutually_exclusive_group(required=True)
    kimlik.add_argument("--email", help="Hedef kullanicinin e-postasi")
    kimlik.add_argument("--uid", help="Hedef kullanicinin uid'i")
    p.add_argument("--role", choices=ROLLER, default="owner",
                   help="Panel rolu (varsayilan: owner)")
    p.add_argument("--partner", metavar="PARTNER_ID",
                   help=("Ortaklik claim'i bas: {partner:true, partnerId:...}."
                         " admin YAZMAZ — ortak yonetici degildir."))
    p.add_argument("--revoke", action="store_true",
                   help="admin + role claim'lerini kaldir (varsayilan: bas)")
    p.add_argument("--project", default="rhytoai")
    args = p.parse_args()

    firebase_admin.initialize_app(options={"projectId": args.project})

    kullanici = (auth.get_user_by_email(args.email) if args.email
                 else auth.get_user(args.uid))

    mevcut = dict(kullanici.custom_claims or {})
    print(f"Hedef : {kullanici.uid}")
    print(f"E-posta: {kullanici.email}")
    print(f"Mevcut claim'ler: {mevcut or '-'}")
    if args.revoke:
        islem = "ortaklik KALDIR" if args.partner else "admin KALDIR"
    elif args.partner:
        islem = f"ORTAK BAS (partnerId={args.partner}) — admin YAZILMAZ"
    else:
        islem = f"admin BAS (role={args.role})"
    print(f"Islem : {islem}")

    # Yanlis hesaba basilmasin: hedef ekrana yazildi, onay istenir.
    onay = input("Onayliyor musun? (evet/hayir): ").strip().lower()
    if onay != "evet":
        print("Vazgecildi.")
        return 1

    # Ortaklik AYRI BIR BOYUT: `admin`/`role` ile birlikte yazilmaz ve
    # birlikte kaldirilmaz. Sebep core/auth.py'de: "partner" ROLES'a
    # eklenseydi require_admin kapisini gecer ve ortak token'i butun
    # yonetim okuma uclarini acardi.
    if args.partner:
        if args.revoke:
            mevcut.pop("partner", None)
            mevcut.pop("partnerId", None)
        else:
            mevcut["partner"] = True
            mevcut["partnerId"] = str(args.partner)
    elif args.revoke:
        mevcut.pop("admin", None)
        mevcut.pop("role", None)
    else:
        mevcut["admin"] = True
        mevcut["role"] = args.role
    auth.set_custom_user_claims(kullanici.uid, mevcut or None)

    print("Tamam. Claim, kullanicinin ID token'i yenilenince (<=1 saat) ya da"
          " cikis/giris sonrasi gecerli olur.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

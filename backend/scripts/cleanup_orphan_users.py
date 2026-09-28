"""Yetim `users/{uid}` dokümanları: Firebase Auth karşılığı OLMAYAN kayıtlar.

Bulgu B9'un ARTIĞI. Kusurun kendisi kodda kapatıldı (`app_gate.remember_build`
ve `search_mirror.ensure` artık `update` kullanıyor, yani var olmayan dokümanı
YARATMIYOR), ama o kusurun ÜRETİMDE bıraktığı dokümanlar kendiliğinden
gitmez. Ölçüm (2026-09-18, `rhytoai`): `users` koleksiyonunda 19 doküman,
yalnız 12'sinin Auth karşılığı var; yetim 7'nin dördü `{appBuild: 41}`
iskeleti, kalan üçü `dev-user`/`u1`/`u2` (testlerin üretime sızdığı ayrı
olay; bkz. `tests/conftest.py` `firestore_hermetik`).

Bu betik SİLME KARARINI VERMEZ, kararı GÖRÜNÜR KILAR: prova kipinde her
adayın uid'sini, taşıdığı alan adlarını ve alt koleksiyonu olup olmadığını
basar. Silme yalnız `--apply` ile ve yalnız aşağıdaki üç emniyetten geçen
dokümanlarda olur.

## Emniyetler (üçü de ölçülmüş bir zararın karşılığı)

1. **Auth listesi okunamazsa HİÇBİR ŞEY silinmez.** `list_users` düşerse
   ya da boş dönerse her kullanıcı "yetim" görünür ve betik 12 GERÇEK
   hesabın profilini silerdi. Boş liste de hata sayılır: canlı projede en
   az bir hesap (sahibin kendisi) vardır, boş liste "okuyamadım" demenin
   sessiz hâlidir.
2. **Alt koleksiyonu olan doküman silinmez, RAPOR edilir.** Firestore'da
   üst dokümanı silmek alt koleksiyonları silmez; `users/{uid}` çıplak
   `delete` ile gidince `private/**`, `friends/**`, `chats/**` yerinde
   kalır ve `collection_group` sorgularına görünmeye devam eder. Böyle bir
   doküman gerçek bir silme ister: panelin "Hesabı sil" ucu
   (`account_service.delete_account`, veri önce kimlik en son).
3. **Prova varsayılan** (`_ortak` doktrini): `--apply` verilmeden hiçbir
   yazım/silme yapılmaz.

    python scripts/cleanup_orphan_users.py            # prova
    python scripts/cleanup_orphan_users.py --apply    # siler
"""
from __future__ import annotations

import logging
from typing import Any, Callable, Iterable

from _ortak import arg_ayristirici, istemci  # noqa: E402

logger = logging.getLogger("cleanup_orphan_users")
BETIK = "cleanup_orphan_users"


def _ozet(incelenen: int, silinecek: int, apply: bool,
          **ek: Any) -> dict[str, Any]:
    """`_ortak.ozet`in aynısı ama SİLME kelimesiyle.

    `ozet` sayıyı "yazılacak/yazılan" diye adlandırıyor; bu betik yazmıyor
    SİLİYOR ve geri alınamaz bir işlemi yanlış adla raporlamak operatörü
    yanıltır (depo kuralı: ölçülen, yanlış adla sunulmaz). Şekil aynı
    kalıyor ki testler diğer betiklerdekiyle aynı biçimde bakabilsin.
    """
    anahtar = "silinen" if apply else "silinecek"
    sonuc = {"betik": BETIK, "incelenen": incelenen, anahtar: silinecek,
             "apply": apply, **ek}
    kip = "SİLİNDİ" if apply else "PROVA (silme yok; --apply ile uygula)"
    print(f"[{BETIK}] incelenen={incelenen} {anahtar}={silinecek} — {kip}"
          + (f" | {ek}" if ek else ""))
    return sonuc


def auth_uidleri() -> set[str] | None:
    """Firebase Auth'taki TÜM uid'ler; okunamazsa None.

    None ile boş kümeyi ayırmak bu betiğin en önemli ayrımı: ikisi de
    "hiçbir uid görmedim" ama biri arıza, diğeri veri. Karıştıran bir
    sürüm gerçek hesapları silerdi (bkz. dosya başı, emniyet 1).
    """
    try:
        from firebase_admin import auth as fb_auth
        sonuc: set[str] = set()
        sayfa = fb_auth.list_users()
        while sayfa:
            for kullanici in sayfa.users:
                sonuc.add(kullanici.uid)
            sayfa = sayfa.get_next_page()
        return sonuc
    except Exception as exc:
        logger.error("Auth listesi alınamadı; silme YAPILMAYACAK: %s", exc)
        return None


def _alt_koleksiyonlar(client, uid: str) -> list[str]:
    """`users/{uid}` altındaki alt koleksiyon adları (yoksa boş liste).

    Ayrı ve enjekte edilebilir: `collections()` gerçek istemcinin yüzeyi ve
    paylaşılan sahte Firestore'da yok. Sahteyi bu betik için genişletmek
    onu tüm testlerin ortak yüzeyinde değiştirmek olurdu.
    """
    try:
        ref = client.collection("users").document(uid)
        return [getattr(k, "id", str(k)) for k in ref.collections()]
    except Exception as exc:
        # Bilinmiyor = VAR sayılır: emin olmadığımız dokümanı silmek,
        # arkasında görünmez bir alt ağaç bırakma riski demek.
        logger.warning("Alt koleksiyonlar okunamadı (%s): %s", uid, exc)
        return ["<okunamadı>"]


def calistir(client, *, auth_uids: set[str] | None, apply: bool = False,
             alt_koleksiyonlar: Callable[[Any, str], Iterable[str]] | None =
             None) -> dict[str, Any]:
    """Yetimleri bulur, raporlar ve `apply` ise çıplak olanları siler."""
    if auth_uids is None:
        raise SystemExit("Auth listesi okunamadı — silme yapılmadı "
                         "(ADC/izin?). Emniyet 1.")
    if not auth_uids:
        raise SystemExit("Auth listesi BOŞ döndü. Canlı projede en az bir "
                         "hesap olur; bu 'okuyamadım'ın sessiz hâli. "
                         "Silme yapılmadı. Emniyet 1.")

    from services.stats_service import _iter_users
    alt = alt_koleksiyonlar or _alt_koleksiyonlar

    incelenen = silinecek = 0
    korunan: list[str] = []
    for veri in _iter_users(client):
        incelenen += 1
        uid = veri.pop("uid")
        if uid in auth_uids:
            continue
        altlar = sorted(alt(client, uid))
        alanlar = sorted(veri)
        if altlar:
            korunan.append(uid)
            print(f"  KORUNDU {uid}: alt koleksiyon {altlar} — çıplak silme "
                  f"alt ağacı bırakır; panelin 'Hesabı sil' ucunu kullan. "
                  f"alanlar={alanlar}")
            continue
        silinecek += 1
        print(f"  YETİM   {uid}: alanlar={alanlar}")
        if apply:
            client.collection("users").document(uid).delete()

    return _ozet(incelenen, silinecek, apply,
                 auth=len(auth_uids), korunan=len(korunan))


def main(argv: list[str] | None = None) -> int:
    args = arg_ayristirici(__doc__.split("\n")[0]).parse_args(argv)
    client = istemci()
    calistir(client, auth_uids=auth_uidleri(), apply=args.apply)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

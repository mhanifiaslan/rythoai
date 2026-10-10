# -*- coding: utf-8 -*-
r"""Üretim sohbet arşivinin SALT OKUMA ölçeri — B11.

Dört kusur sınıfı için taban sayısı üretir: persona kayması (model görev
yardımcısına dönüyor), kapı yanlış pozitifi, sorulmadan çekince ve
sohbete yazılan doğum tarihinden harita uydurma. `users/{uid}/
conversations/{id}/messages` ağacını dolaşır, her USER→AI turunu
sınıflandırır, özet tablo + sınıf başına en fazla 5 örnek basar.

HİÇBİR ŞEY YAZMAZ. Bekçisi `backend/tests/test_eval_genericness.py::
TestSohbetOlcer`: kaynakta `.set(` / `.update(` / `.delete(` / `add(`
çağrısı yok (ast ile — yorumlar düğüm değil) ve sahte depoda `yazimlar`
boş.

## Neden proje ADIYLA bağlanıyor

`firebase_admin.initialize_app(options={"projectId": "rhytoai"})`.
gcloud'un varsayılan projesi başka bir projeye düşebiliyor (CLAUDE.md
§2) ve o hâlde ölçüm sessizce YANLIŞ projeyi okur — bu depoda bir kez
yanlış bir "panelde hiç admin yok" blocker'ı üretti.

## Neden kapı engelleri sayılamıyor

`api/chat.py` kriz ve yasak-konu kapıları `write_turn`dan ÖNCE dönüyor;
engellenen tur Firestore'a hiç yazılmıyor. `blocked` sayacı K ajanının
alanı kayda girince dolar; bugün 0 "engel yok" DEĞİL "kayıt yok" demek.
Ölçülmeyen söylenmez — tablo bunu açıkça yazar.

## Sınıflar (kalıplar `backend/scripts/eval_genericness.py`'de, TEK tanım)

  [B] bugünkü `safety_rules.forbidden_topic` engellerdi — kayıtlı
      kullanıcı mesajları kapıdan GEÇMİŞ mesajlardır; bugün yakalanan
      her biri ya kapının o günden beri genişlediğini ya da bir yanlış
      pozitifi gösterir ("hissediyorum" → finans, "altında" → finans).
  [A] görev talebi (kullanıcı) · görev-yardımı biçimli cevap (model)
  [C] çekince taşıyan cevap · bunlardan SORULMADAN (bağlam = kullanıcı
      mesajı + ilk turda varsa Rytho'nun tohum sorusu; para/sağlık/hukuk
      anmıyor)
  [D] doğum tarihi yazılan tur · ardından yerleşim atayan cevap.
      Cevaptaki AD ölçülmüyor: Türkçe metinde kişi adı tespiti güvenilir
      değil, güvenilmeyen şey sayılmaz.

## Taban — bu araçla, 2026-10-10, üretim `rhytoai`, tam tarama

  kullanıcı 32 (konuşması olan 18) · konuşma 122 (tohum 50) · mesaj 498
  (kullanıcı 224 / model 274) · USER→AI turu 224 · `blocked` 0 (kayıt yok)
  [B] kapı engellerdi 0 — HEAD'deki ESKİ kapıyla da 0, ve bu yapısal:
      kayıtlı mesajlar kapıdan GEÇMİŞ mesajlardır, kapının yanlış
      pozitifi korpusta görünemez. Beş yanlış pozitif ("hissediyorum" →
      hisse, "altında" → altın, "olurum" → ölüm, "sick of", "gold
      earrings") yalnız PROBE ile ölçüldü (B11-B) ve aynı turda onarıldı.
  [A] görev talebi 1 · görev-yardımı cevap 2 (ikisi aynı konuşma:
      tur 9 kendiliğinden teklif, tur 13 "taslak … hazırlayabilirim")
  [C] çekince 1 · sorulmadan 0 (teki gerçek sağlık sorusu: "sağlığım ile
      ilgili neler yaşayacağım" → "sınırlarımın dışında … bir hekime").
      Bir de DOLAYLI kanıt var: bir kullanıcı
      "sorduğum soru ve verdiğin cevabı incele" dedi ve model "önceki
      cevabımda finansal konulardan bahsettiğim için haklı olarak
      şaşırdın … agresiflik hissiyle ilgili sorunu kaçırdım" diye özür
      diledi — sorulmadan çekincenin kullanıcıya nasıl göründüğü bu.
  [D] doğum tarihi 4 · yerleşim atayan 3
  [bekçi] persona_guard aynı turlarda: task_request 1 · drifted 2 ·
      third_party_claims 6 = ölçerin 3'ü + AYNI konuşmada 3 tur daha.
      Fark ölçerin değil ölçünün: bekçi tarih şartı aramıyor, AD + burç
      çiftine bakıyor — ve o üç tur, uydurulan yerleşimin tarih OLMADAN
      yeniden kullanılması ("Ayşe Öykü'nün Güneş'inin Boğa…", "Eşinin
      burcu Yay olduğu için…"; üçüncüsü "Haritanda Güneş'inin Yay…"
      kullanıcının kendi haritası olabilir, ölçülmedi). Yani uydurma
      geçmişle TAŞINIYOR; tarih turu sayan ölçü alt sınırdır.

Kullanım (depo kökünden; ADC: `gcloud auth application-default login`):
    backend/.venv/Scripts/python.exe tools/sohbet_olc.py
    ... --limit 200            (en fazla N mesaj tara)
    ... --uid <uid>            (tek kullanıcı)
    ... --since 2026-10-01     (createdAt >= gün, UTC)
"""
from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import importlib.util
import sys
from pathlib import Path
from typing import Any

KOK = Path(__file__).resolve().parents[1]
BACKEND = KOK / "backend"
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

# cp1254 konsolu: kullanıcı mesajları emoji taşıyor ve strict kip ilk
# emojide programı düşürür — hem de tarama bittikten sonra, yani okuma
# yapılmış ve ölçüm kaybedilmiş olur (eval_genericness ile aynı gerekçe).
for _akis in (sys.stdout, sys.stderr):
    try:
        _akis.reconfigure(errors="replace")
    except (AttributeError, ValueError):  # pragma: no cover - ortama bağlı
        pass

PROJE = "rhytoai"
#: Sınıf başına basılan örnek sayısı — rapor bir dökümü değil, bir ölçüm.
ORNEK_TAVANI = 5
#: Örnek metni: 140 karakter yeter, kullanıcı metni başka bir yere
#: kopyalanmaz.
METIN_KARAKTER = 140
#: Kullanıcı kimliği kısaltılır; rapor kimseyi işaret etmek için değil.
KISA_UID = 6


def _olcer():
    """`backend/scripts/eval_genericness` — persona kalıplarının TEK tanımı.

    `sys.modules`a bakılır: testler modülü zaten yüklemiş olabilir ve
    ikinci bir kopya dataclass çözümlemesini bozar
    (`test_eval_genericness` başındaki not).
    """
    modul = sys.modules.get("eval_genericness")
    if modul is None:
        yol = BACKEND / "scripts" / "eval_genericness.py"
        spec = importlib.util.spec_from_file_location("eval_genericness", yol)
        assert spec and spec.loader
        modul = importlib.util.module_from_spec(spec)
        sys.modules["eval_genericness"] = modul
        spec.loader.exec_module(modul)
    return modul


def _istemci():
    """Firestore istemcisi — PROJE ADIYLA, varsayılan projeye güvenmeden.

    `firebase_admin` BURADA içe aktarılır, modül düzeyinde değil: testler
    aracı sahte depoyla koşturuyor ve modülün yüklenmesi tek başına ADC
    çözümlemesine girmemeli.
    """
    import firebase_admin
    from firebase_admin import firestore

    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={"projectId": PROJE})
    return firestore.client()


def kisalt(uid: str) -> str:
    return uid if len(uid) <= KISA_UID else uid[:KISA_UID] + "…"


def kirp(metin: str) -> str:
    tek = " ".join((metin or "").split())
    if len(tek) <= METIN_KARAKTER:
        return tek
    return tek[:METIN_KARAKTER - 1] + "…"


@dataclasses.dataclass
class Ornek:
    uid: str
    konu: str
    etiket: str
    metin: str


#: (sınıf anahtarı, rapor satırı). Sıra rapor sırası.
SINIFLAR = (
    ("kapi-engellerdi", "[B] bugunku kapi engellerdi (kullanici mesaji)"),
    ("gorev-talebi", "[A] gorev talebi (kullanici)"),
    ("gorev-yardimi", "[A] gorev-yardimi bicimli cevap (model)"),
    ("cekince", "[C] cekince tasiyan cevap"),
    ("cekince-sorulmadan", "[C]   ...bunlardan SORULMADAN"),
    ("dogum-tarihi", "[D] dogum tarihi yazilan tur"),
    ("ucuncu-kisi", "[D]   ...ardindan yerlesim atayan cevap"),
)


@dataclasses.dataclass
class Rapor:
    #: Taranan kullanıcı dokümanı — "konuşması olan" ile AYRI sayılır;
    #: ikisini tek sayıya indirmek ya kullanıcıyı ya sohbeti yanlış sayar.
    kullanici_toplam: int = 0
    kullanici: int = 0
    konusma: int = 0
    tohum: int = 0
    mesaj: int = 0
    kullanici_mesaji: int = 0
    model_mesaji: int = 0
    tur: int = 0
    blocked: dict[str, int] = dataclasses.field(default_factory=dict)
    kapi_kategorileri: dict[str, int] = dataclasses.field(default_factory=dict)
    sayac: dict[str, int] = dataclasses.field(default_factory=dict)
    ornekler: dict[str, list[Ornek]] = dataclasses.field(default_factory=dict)
    #: `services.persona_guard` aynı turlarda ne diyor (bkz. `_bekci`).
    bekci_var: bool = False
    bekci: dict[str, int] = dataclasses.field(default_factory=dict)
    bekci_hata: dict[str, str] = dataclasses.field(default_factory=dict)

    def kaydet(self, sinif: str, uid: str, konu: str, etiket: str,
               metin: str) -> None:
        self.sayac[sinif] = self.sayac.get(sinif, 0) + 1
        liste = self.ornekler.get(sinif)
        if liste is None:
            liste = []
            self.ornekler[sinif] = liste
        if len(liste) < ORNEK_TAVANI:
            liste.append(Ornek(kisalt(uid), kisalt(konu), etiket, kirp(metin)))


def _bekci():
    """`services.persona_guard` varsa modülü, yoksa None.

    Ölçer ile bekçi AYRI kalıplar taşır ve bu bilerek: bekçinin
    kaçırdığını ancak bağımsız bir ölçer görebilir — ölçer bekçinin
    kendi dedektörünü çağırsaydı tam olarak bekçinin kör olduğu yerde kör
    olurdu. Araç ikisini yan yana basar; aradaki fark, bekçinin üretim
    korpusundaki açığıdır (ya da ölçerin yanlış pozitifi — örnekler
    bunun için basılıyor).
    """
    try:
        from services import persona_guard
    except ImportError:
        return None
    return persona_guard


def _bekci_say(rapor: Rapor, bekci: Any, kullanici: str, cevap: str) -> None:
    """Bekçinin üç çıkışını aynı tura uygular; düşen çağrı GİZLENMEZ."""
    cagrilar = (
        ("task_request", lambda: bekci.task_request(kullanici)),
        ("drifted", lambda: bekci.drifted(cevap)),
        ("third_party_claims",
         lambda: bekci.third_party_claims(cevap, kullanici)),
    )
    for ad, cagri in cagrilar:
        try:
            sonuc = cagri()
        except Exception as exc:  # noqa: BLE001 - ölçüm, raporda görünür
            rapor.bekci_hata[ad] = repr(exc)[:120]
            continue
        if sonuc:
            rapor.bekci[ad] = rapor.bekci.get(ad, 0) + 1


def _siniflandir(rapor: Rapor, uid: str, konu: str, kullanici: str,
                 cevap: str, baglam: str, ev: Any,
                 bekci: Any = None) -> None:
    """Tek bir USER→AI turunu dört sınıfa vurur."""
    from services import safety_rules

    if bekci is not None:
        _bekci_say(rapor, bekci, kullanici, cevap)

    kapi = safety_rules.forbidden_topic(kullanici)
    if kapi is not None:
        kategori = kapi[0]
        rapor.kapi_kategorileri[kategori] = (
            rapor.kapi_kategorileri.get(kategori, 0) + 1)
        rapor.kaydet("kapi-engellerdi", uid, konu, kategori, kullanici)

    talep = ev._gorev_talebi(kullanici)
    if talep:
        rapor.kaydet("gorev-talebi", uid, konu, " + ".join(talep), kullanici)
    yardim = ev._gorev_yardimi(cevap)
    if yardim:
        rapor.kaydet("gorev-yardimi", uid, konu, ", ".join(yardim), cevap)

    cekince = ev._cekince(cevap)
    if cekince:
        rapor.kaydet("cekince", uid, konu, ", ".join(cekince), cevap)
        if ev._sorulmadan_cekince(cevap, baglam):
            rapor.kaydet("cekince-sorulmadan", uid, konu, kirp(baglam), cevap)

    if ev._DOGUM_TARIHI.search(ev._katla(kullanici)):
        rapor.kaydet("dogum-tarihi", uid, konu, "", kullanici)
        yerlesim = ev._ucuncu_kisi_yerlesimi(cevap, kullanici)
        if yerlesim:
            rapor.kaydet("ucuncu-kisi", uid, konu, ", ".join(yerlesim), cevap)


def tara(client: Any, limit: int | None = None, uid: str | None = None,
         since: dt.datetime | None = None) -> Rapor:
    """Ağacı dolaşır, sayar, SINIFLANDIRIR — okuma dışında hiçbir şey.

    Konuşma başına mesajlar `createdAt` sırasıyla okunur ki USER→AI
    eşlemesi doğru olsun: sırasız okumada bir cevap bir önceki sorunun
    yerine bir sonrakine bağlanır ve "sorulmadan çekince" sayacı sahte
    pozitif üretir.

    `since` yalnız mesaj damgasına bakar; konu dokümanının `updatedAt`i
    değil — eski bir konuya dün yazılan tur da bugünün ölçümüne girer.
    """
    ev = _olcer()
    bekci = _bekci()
    rapor = Rapor(bekci_var=bekci is not None)
    kullanicilar = client.collection("users")
    kaynak = [kullanicilar.document(uid).get()] if uid else list(
        kullanicilar.stream())
    for anlik in kaynak:
        rapor.kullanici_toplam += 1
        konular = list(kullanicilar.document(anlik.id)
                       .collection("conversations").stream())
        if not konular:
            continue
        rapor.kullanici += 1
        for konu in konular:
            veri = konu.to_dict() or {}
            rapor.konusma += 1
            tohum_sorusu = (veri.get("seedQuestion")
                            if veri.get("openedBy") == "rytho" else None)
            if tohum_sorusu:
                rapor.tohum += 1
            bekleyen: str | None = None
            ilk_tur = True
            mesajlar = (konu.reference.collection("messages")
                        .order_by("createdAt").stream())
            for m in mesajlar:
                v = m.to_dict() or {}
                zaman = v.get("createdAt")
                if isinstance(zaman, dt.datetime) and zaman.tzinfo is None:
                    zaman = zaman.replace(tzinfo=dt.timezone.utc)
                if since is not None and zaman is not None and zaman < since:
                    continue
                rapor.mesaj += 1
                if "blocked" in v:
                    etiket = str(v.get("blocked"))
                    rapor.blocked[etiket] = rapor.blocked.get(etiket, 0) + 1
                metin = str(v.get("text") or "")
                if v.get("sender") == "USER":
                    rapor.kullanici_mesaji += 1
                    bekleyen = metin
                else:
                    rapor.model_mesaji += 1
                    if bekleyen is not None:
                        rapor.tur += 1
                        baglam = bekleyen
                        if ilk_tur and tohum_sorusu:
                            baglam = f"{bekleyen} {tohum_sorusu}"
                        _siniflandir(rapor, anlik.id, konu.id, bekleyen,
                                     metin, baglam, ev, bekci)
                        bekleyen = None
                        ilk_tur = False
                if limit is not None and rapor.mesaj >= limit:
                    return rapor
    return rapor


def raporla(rapor: Rapor, baslik: str) -> None:
    cizgi = "=" * 72
    print(cizgi)
    print(f"SOHBET OLCUMU — {baslik}")
    print(cizgi)
    print(f"kullanici (taranan)        : {rapor.kullanici_toplam}"
          f"   (konusmasi olan: {rapor.kullanici})")
    print(f"konusma                    : {rapor.konusma}"
          f"   (tohum / Rytho acti: {rapor.tohum})")
    print(f"mesaj                      : {rapor.mesaj}"
          f"   (kullanici {rapor.kullanici_mesaji} / model "
          f"{rapor.model_mesaji}; USER->AI turu {rapor.tur})")
    # "0" tek basina "engel yok" diye okunur; oysa engellenen tur hic
    # kaydedilmiyor (write_turn oncesi donus). Sayi yanina sebebi yazilir.
    blocked_not = (str(rapor.blocked) if rapor.blocked
                   else "(kayit yok — engel write_turn oncesi donuyor, "
                        "olculemez)")
    print(f"'blocked' alani tasiyan    : {sum(rapor.blocked.values())}"
          f"   {blocked_not}")
    print("-" * 72)
    for anahtar, satir in SINIFLAR:
        ek = ""
        if anahtar == "kapi-engellerdi" and rapor.kapi_kategorileri:
            ek = f"   {rapor.kapi_kategorileri}"
        print(f"{satir:<48}: {rapor.sayac.get(anahtar, 0)}{ek}")
    print("-" * 72)
    if rapor.bekci_var:
        b = rapor.bekci
        print("[bekci] services.persona_guard, ayni turlarda: "
              f"task_request {b.get('task_request', 0)} | "
              f"drifted {b.get('drifted', 0)} | "
              f"third_party_claims {b.get('third_party_claims', 0)}"
              "   (olcerle fark = bekcinin acigi ya da olcerin yanlis "
              "pozitifi; ornekler asagida)")
        for ad, hata in rapor.bekci_hata.items():
            print(f"[bekci]   /!\\ {ad} cagrisi dustu: {hata}")
    else:
        print("[bekci] services.persona_guard YOK — kiyas yapilamadi")
    print("-" * 72)
    print(f"ORNEKLER (en fazla {ORNEK_TAVANI}/sinif; uid kisaltilmis, "
          f"metin {METIN_KARAKTER} karakter)")
    for anahtar, satir in SINIFLAR:
        ornekler = rapor.ornekler.get(anahtar) or []
        if not ornekler:
            continue
        print(f"\n{satir}")
        for o in ornekler:
            etiket = f" {o.etiket} |" if o.etiket else ""
            print(f"   {o.uid}/{o.konu} {etiket} \"{o.metin}\"")
    print(cizgi)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--limit", type=int, default=None,
                    help="En fazla bu kadar mesaj tara.")
    ap.add_argument("--uid", default=None, help="Tek kullanici.")
    ap.add_argument("--since", default=None,
                    help="YYYY-MM-DD — bu gunden (UTC) eski mesajlar atlanir.")
    args = ap.parse_args(argv)

    since = None
    if args.since:
        since = dt.datetime.combine(dt.date.fromisoformat(args.since),
                                    dt.time.min, tzinfo=dt.timezone.utc)
    suzgec = ", ".join(s for s in (
        f"limit {args.limit}" if args.limit else "",
        f"uid {kisalt(args.uid)}" if args.uid else "",
        f"since {args.since}" if args.since else "") if s)
    rapor = tara(_istemci(), limit=args.limit, uid=args.uid, since=since)
    raporla(rapor, f"uretim ({PROJE}), SALT OKUMA — "
                   f"{dt.date.today().isoformat()}"
                   + (f" [{suzgec}]" if suzgec else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

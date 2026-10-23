"""Gizlilik politikasının DÖRT kopyası tek tarihi ve aynı bölümleri taşır.

NEDEN bu bekçi var (ölçüldü 2026-10-02): politika dört yerde yaşıyor —
uygulama içi `legal_texts.dart` (TR gövdesi + EN gövdesi) ve web
(`web/legal/gizlilik.html` + `web/en/legal/privacy.html`). Kopyalar
AYRIŞMIŞTI: uygulama "2 Ağustos 2026", web "5 Ağustos 2026" diyordu ve
ayrışma yalnız tarihte değildi — webde "Abonelik ve tek cihaz" ile
"Bildirimler" bölümleri HİÇ yoktu. Hiçbir test düşmedi, çünkü
`test_honesty` yalnız KULLANIM ŞARTLARININ dört kopyasını çiviliyor;
gizlilik politikası bekçisizdi. Sonuç: kullanıcının okuduğu beyan hangi
yüzeyden baktığına göre değişiyordu ve bu iki ay görünmedi.

BEŞİNCİ kopya KALDIRILDI (karar verildi 2026-10-02). Bir tur boyunca
`docs/legal/gizlilik-politikasi.md` beş kopyanın en bayatıydı: tarihi
"5 Ağustos 2026", ve DÖRT bölümü hiç yoktu — h ("Çevrem"), i ("Abonelik ve
tek cihaz"), j ("Bildirimler"), k ("Ortak bağlantısı tıklamaları").
Çivilenmemesinin sebebi teknik değil karar eksikliğiydi: HTML'i besleyen bir
KAYNAK mı bayat bir ARTIK mı belirsizdi.

Karar ölçümle verildi: hiçbir kod, HTML, betik ya da belge o dosyaya
referans VERMİYORDU (arandı), yani kaynak değil artıktı. Metni kaldırıldı,
yerine kanonik üç yolu gösteren bir yönlendirme kondu. Kök neden bir yazım
hatası değil KOPYA SAYISI: bir hukuk metninin beş kopyası varsa dördü bir
gün ayrışır. Üçü zorunlu (mobil / web TR / web EN farklı teknolojiler ve
birleştirilemiyor); dördüncüsü için gerekçe yoktu.

O dosyanın yönlendirme olarak KALDIĞI `test_besinci_kopya_geri_dogmaz` ile
çivili — aksi hâlde metin bir gün sessizce geri yazılır ve bu bekçi onu
görmez.

Bekçi bilerek KIRILGAN DEĞİL:

* **Tarih dize olarak karşılaştırılamaz** — biçim kopyalar arasında
  kasten farklı ("2 October 2026" ile "October 2, 2026"). Karşılaştırılan
  şey GÜN: ay adı sayıya çevrilip (yıl, ay, gün) üçlüsü kıyaslanır.
* **Bölümler için tam metin değil kısa çapa aranır.** Çapa ölçütü: bölüm
  silinirse ya da anlamı kayarsa çapa düşsün.
* **Yorumlar eşleşmeden ÖNCE atılır** — HTML `<!-- -->` ve Dart satır
  yorumları birden. Bu bekçi bir şeyin VARLIĞINI arıyor, yani onu
  ANLATAN bir yorum yanlış POZİTİF üretir: bölüm silinip yerine
  "bildirimler web'de anlatılıyor" diye bir yorum bırakılsa bekçi
  susardı. Aynı tuzak bu depoda iki kez patladı (bkz. CLAUDE.md §5) ve
  mutasyon sınavında (M3) burada da doğrulandı.

⚠️ **Çapa ve niteleyici DOSYADA değil BÖLÜMDE/CÜMLEDE aranır.** Bunun
gerekçesi ölçüldü (2026-10-02 mutasyon sınavı) ve iki kez aynı sınıftan
kusur çıktı — dosya kapsamlı arama, yakalaması gereken gerilemeyi
GÖRMEDİ:

* **M4:** niteleyici "kalıcı" dosyanın herhangi bir yerinde aranıyordu.
  O sözcük TR sayfasında dört kez geçiyor, dolayısıyla asıl iddiayı
  taşıyan cümleden silindiğinde ("bu ölçümün kalıcı kaydına" → "bu
  ölçümün kaydına") bekçi YEŞİL kaldı. Dart kopyasında kırmızı olması
  tasarım değil kazaydı: "KALICI" orada tesadüfen bir kez geçiyor.
* **M3b:** "doğum haritandan" çapası da dosya kapsamlıydı; aynı ifade
  "Yapay zeka ile işleme" bölümünde de geçtiği için BİLDİRİM bölümündeki
  beyan burçlu hâline döndürüldüğünde bekçi yine YEŞİL kaldı.

Bu yüzden her çapa kendi bölümünün gövdesinde, her niteleyici de
iddiayı taşıyan cümlenin içinde aranır.
"""
from __future__ import annotations

import html
import json
import re
from pathlib import Path

import pytest

_KOK = Path(__file__).resolve().parents[2]

_DART = "apps/mobile/lib/features/profile/legal_texts.dart"
_WEB_TR = "web/legal/gizlilik.html"
_WEB_EN = "web/en/legal/privacy.html"

#: Ay adı -> ay numarası. TR adları dosyada nasıl yazıldıysa öyle; Türkçe
#: `lower()` bozuk olduğu için küçültme HİÇ yapılmıyor (CLAUDE.md §5:
#: `"İ".lower()` iki kod noktası üretir ve eşleşme sessizce kayar).
_AYLAR = {
    "Ocak": 1, "Şubat": 2, "Mart": 3, "Nisan": 4, "Mayıs": 5, "Haziran": 6,
    "Temmuz": 7, "Ağustos": 8, "Eylül": 9, "Ekim": 10, "Kasım": 11,
    "Aralık": 12,
    "January": 1, "February": 2, "March": 3, "April": 4, "May": 5,
    "June": 6, "July": 7, "August": 8, "September": 9, "October": 10,
    "November": 11, "December": 12,
}

_AY_KALIBI = "|".join(sorted(_AYLAR, key=len, reverse=True))

#: "2 Ekim 2026" / "2 October 2026" (gün önce) ya da "October 2, 2026"
#: (ay önce). İki biçim de meşru: biri uygulama, biri web.
_GUN_ONCE = re.compile(rf"(\d{{1,2}})\s+({_AY_KALIBI})\s+(\d{{4}})")
_AY_ONCE = re.compile(rf"({_AY_KALIBI})\s+(\d{{1,2}}),\s*(\d{{4}})")


def _oku(yol: str) -> str:
    """Dosyanın HAM kaynağı — yorumlar dahil."""
    dosya = _KOK / yol
    assert dosya.exists(), (
        f"{yol} yok — taşındıysa bu bekçi güncellenmeli, yoksa yayındaki "
        f"bir gizlilik kopyası bekçisiz kalır")
    return dosya.read_text(encoding="utf-8")


def _yorumsuz(yol: str, ham: str) -> str:
    """Yorumları atar — bkz. modül başlığındaki gerekçe.

    Dart tarafında yalnız SATIR BAŞINDAKİ `//` ve `///` atılır. Gerekçe:
    dize gövdesinin içinde de "//" geçebilir (bir URL) ve onu yorum sanıp
    kesmek, bekçiyi okuduğu metnin yarısından mahrum bırakırdı. Satır
    boşluğa çevrilir, satır sonu KORUNUR: bölüm ayıklaması satır yapısına
    bakıyor.
    """
    if yol.endswith(".dart"):
        return re.sub(r"(?m)^[ \t]*//.*$", " ", ham)
    return re.sub(r"<!--.*?-->", " ", ham, flags=re.S)


def _sadelestir(yol: str, parca: str) -> str:
    """Kaynak parçasını OKUNAN metne çevirir.

    Dart'ta ardışık dize parçaları birleştirilir (`'a ' 'b'` → `'a b'`):
    parçalanma satır genişliğinin eseri, metnin değil. Birleştirilmezse
    "tek bir bayt" gibi bir çapa iki parçaya bölündüğü an bekçi sessizce
    kör olurdu — satır sarmak metni değiştirmemeli.

    Dize içindeki `\\n` kaçışı (paragraf arası) boşluğa çevrilir. Çevrilmezse
    "…gönderilmez).\\n\\nSohbette" gibi bir paragraf sınırında noktadan
    sonra boşluk gelmez, `_cumleler` orayı bölemez ve iki paragrafın
    cümleleri TEK cümle sayılır — cümle kapsamlı bir bekçi (ör. "onay
    cümlesi sağlayıcı adı taşımaz") öteki paragraftaki sağlayıcı adına
    takılıp yanlış KIRMIZI, ya da aradığı çapayı öteki paragrafta bulup
    yanlış YEŞİL verirdi.
    """
    if yol.endswith(".dart"):
        parca = re.sub(r"'[ \t]*\r?\n[ \t]*'", "", parca)
        parca = parca.replace("\\'", "'")
        parca = parca.replace("\\n", " ")
    else:
        parca = re.sub(r"<[^>]+>", " ", parca)
    return re.sub(r"\s+", " ", parca).strip()


def _bolum(yol: str, baslik: str) -> str:
    """[baslik] bölümünün OKUNAN gövdesi; bölüm yoksa testi düşürür.

    Bölüm sınırı iki kopyada farklı taşınıyor: Dart'ta `(başlık, gövde)`
    çifti, HTML'de `<h3>` ile bir sonraki başlık arası. Gövdeyi ayıklamak
    çapayı dosya kapsamlı aramadan kurtarıyor — aynı ifadenin BAŞKA bir
    bölümde geçmesi, bu bölümdeki beyanın yerini tutmasın (M3b).
    """
    ham = _yorumsuz(yol, _oku(yol))
    if yol.endswith(".dart"):
        kalip = re.compile(
            rf"\n    '{re.escape(baslik)}',\n(.*?)\n  \),", re.S)
    else:
        kalip = re.compile(
            rf"<h3>[^<]*{re.escape(baslik)}</h3>(.*?)(?=<h[23])", re.S)
    eslesme = kalip.search(ham)
    assert eslesme, (
        f"{yol}: '{baslik}' bölümü YOK. Gizlilik politikasının dört "
        f"kopyası aynı bölümleri taşımak zorunda — tam bu ayrışma iki ay "
        f"görünmedi (webde 'Abonelik ve tek cihaz' ile 'Bildirimler' hiç "
        f"yoktu). Bölüm bilerek kaldırıldıysa DÖRT kopyadan da "
        f"kaldırılmalı ve bu bekçi güncellenmeli.")
    return _sadelestir(yol, eslesme.group(1))


def _cumleler(duz: str) -> list[str]:
    """Nokta + boşlukta böler — iddia ile niteleyicisini aynı kapta tutmak için."""
    return re.split(r"(?<=\.)\s", duz)


def _tarih(metin: str) -> tuple[int, int, int]:
    """Metindeki İLK tarihi (yıl, ay, gün) olarak döndürür."""
    eslesme = _GUN_ONCE.search(metin)
    if eslesme:
        gun, ay, yil = eslesme.group(1), eslesme.group(2), eslesme.group(3)
    else:
        eslesme = _AY_ONCE.search(metin)
        assert eslesme, f"Tarih bulunamadı: {metin[:120]!r}"
        ay, gun, yil = eslesme.group(1), eslesme.group(2), eslesme.group(3)
    return int(yil), _AYLAR[ay], int(gun)


def _dart_sabiti(kaynak: str, ad: str) -> str:
    kalip = re.compile(rf"const String {re.escape(ad)} = '([^']*)';")
    eslesme = kalip.search(kaynak)
    assert eslesme, f"{ad} sabiti bulunamadı — adı mı değişti?"
    return eslesme.group(1)


def _web_tarih_satiri(yol: str) -> str:
    """`<p class="tarih">…</p>` gövdesi — etiketler boşluğa çevrilmiş."""
    metin = _yorumsuz(yol, _oku(yol))
    eslesme = re.search(r'<p class="tarih">(.*?)</p>', metin, flags=re.S)
    assert eslesme, f'{yol}: <p class="tarih"> bulunamadı'
    return re.sub(r"<[^>]+>", " ", eslesme.group(1))


def test_besinci_kopya_geri_dogmaz():
    """`docs/legal/gizlilik-politikasi.md` POLİTİKA METNİ tutmaz.

    O dosya bir tur boyunca beş kopyanın en bayatıydı (tarihi "5 Ağustos
    2026", dört bölümü eksik) ve hiçbir yerden referans edilmiyordu. Metni
    kaldırıldı, yerine kanonik üç yolu gösteren yönlendirme kondu.

    Bu bekçi olmadan karar ÇÜRÜR: bir gün biri (ya da bir ajan) o dosyaya
    politika metnini geri yazar, yukarıdaki üç kopya bekçisi onu GÖRMEZ
    (listede yok) ve ayrışma sıfırdan başlar.

    ⚠️ İLK HÂLİ KÖRDÜ ve mutasyon onu yakaladı: tek çapa `"Son güncelleme:"`
    idi, yani ASCII yazılmış bir `"Son guncelleme"` ya da tarih satırı HİÇ
    olmayan bir politika gövdesi sessizce geçiyordu. CLAUDE.md §5'teki Türkçe
    eşleştirme tuzağının aynısı: tek diyakritikli çapaya güvenilmez.
    Bu yüzden ÜÇ bağımsız işaret birden sorulur — biçim (uzunluk), tarih
    beyanı (iki yazımla), ve hukuk gövdesine özgü atıflar. Bir gövde üçünden
    en az birini kaçamaz: politika metni hem uzundur hem tarih taşır hem
    KVKK/GDPR'a atıf yapar.
    """
    yol = "docs/legal/gizlilik-politikasi.md"
    metin = _oku(yol)

    satir = len(metin.splitlines())
    assert satir <= 80, (
        f"{yol}: {satir} satır — yönlendirme bu kadar uzun olmaz, "
        "politika metni geri yazılmış olabilir")

    for capa in ("güncelleme", "guncelleme"):
        assert capa not in metin.lower(), (
            f"{yol}: tarih beyanı doğmuş ({capa!r}) — beşinci kopya yeniden "
            "doğdu ve hangi kopyanın güncel olduğu yine gizlenir")

    for capa in ("6698", "KVKK", "GDPR"):
        assert capa not in metin, (
            f"{yol}: hukuk gövdesine özgü atıf var ({capa!r}) — bu dosya "
            "politika METNİ tutmaz, yalnız nerede olduğunu söyler")

    for kanonik in (_WEB_TR, _WEB_EN, _DART):
        assert kanonik in metin, f"{yol}: kanonik yolu göstermiyor ({kanonik})"


def test_dort_kopya_ayni_gunu_gosterir():
    """Dört kopya da aynı günü söylemek ZORUNDA.

    Değişmiş bir politikayı eski tarihle sunmak yanlış beyandır; iki ayrı
    tarih ise hangi kopyanın güncel olduğunu GİZLER.
    """
    dart = _oku(_DART)
    gunler = {
        f"{_DART} (tr)": _tarih(_dart_sabiti(dart, "kLegalLastUpdatedTr")),
        f"{_DART} (en)": _tarih(_dart_sabiti(dart, "kLegalLastUpdatedEn")),
        _WEB_TR: _tarih(_web_tarih_satiri(_WEB_TR)),
        _WEB_EN: _tarih(_web_tarih_satiri(_WEB_EN)),
    }
    assert len(set(gunler.values())) == 1, (
        "Gizlilik politikasının kopyaları farklı tarih gösteriyor: "
        f"{gunler} — metin değiştiyse DÖRT yerin hepsi güncellenmeli "
        f"(legal_texts.dart'ta iki sabit, iki web sayfası)."
    )


#: Dört kopyanın hepsinde durması gereken bölümler, (dosya, başlık).
#: Dart dosyası İKİ kopya taşıyor: TR gövdesi ve EN gövdesi.
#:
#: Liste tam da ayrışmanın yakalandığı yerden geliyor: webde "Abonelik ve
#: tek cihaz" ile "Bildirimler" HİÇ yoktu, "Ortak bağlantısı tıklamaları"
#: ise hiçbir kopyada yoktu (ortaklık programı canlıya alınırken
#: politikaya işlenmemişti).
#:
#: ⚠️ `docs/legal/gizlilik-politikasi.md` bilerek YOK — gerekçesi modül
#: başlığında (karar verilmemiş bir kopyayı çivilemek bekçiyi kırmızı
#: doğurur).
_ZORUNLU_BOLUMLER = (
    (_WEB_TR, "Abonelik ve tek cihaz"),
    (_DART, "Abonelik ve tek cihaz"),
    (_WEB_EN, "Subscription and single device"),
    (_DART, "Subscription and single device"),
    (_WEB_TR, "Bildirimler"),
    (_DART, "Bildirimler"),
    (_WEB_EN, "Notifications"),
    (_DART, "Notifications"),
    (_WEB_TR, "Ortak bağlantısı tıklamaları"),
    (_DART, "Ortak bağlantısı tıklamaları"),
    (_WEB_EN, "Affiliate link clicks"),
    (_DART, "Affiliate link clicks"),
)


@pytest.mark.parametrize("yol,baslik", _ZORUNLU_BOLUMLER)
def test_bolum_dort_kopyada_da_var(yol, baslik):
    """Bölümün VARLIĞI — bu turun varlık sebebi (bkz. modül başlığı)."""
    assert _bolum(yol, baslik), f"{yol}: '{baslik}' bölümünün gövdesi boş"


#: (dosya, bölüm, çapa). Çapalar bölümün ANLAMINI taşıyor: biri düşerse
#: beyan kaymıştır.
#:
#: ⚠️ "kendi haritası" çapaları bilinçli: bildirim gövdeleri kullanıcının
#: KENDİ haritasındaki günün sinyalinden üretiliyor
#: (`services/notification_service.py` — `signal_push` doğrudan profilden,
#: `midday_push` `days_to_exact == 0` olan kendi açısından, `checkin_push`
#: aynı paketten okuyor; yalnız `streak_push`/`friend_push` şablon, ve
#: sinyal çıkmayan günde `daily_push_body` burç satırına düşülüyor).
#: Politika bir tur boyunca tersini — "burcunuza göre hazırlanır, kişiye
#: özel değildir" — yazıyordu. Bildirim gövdesi gerçekten şablona
#: çevrilirse bu çapa DÜŞMELİ ki politikanın da geri alınması gerektiği
#: görünsün.
_BILDIRIM_CAPALARI = (
    (_WEB_TR, "Bildirimler", "Europe/Istanbul"),
    (_WEB_TR, "Bildirimler", "doğum haritanızdan"),
    (_DART, "Bildirimler", "Europe/Istanbul"),
    (_DART, "Bildirimler", "doğum haritandan"),
    (_WEB_EN, "Notifications", "Europe/Istanbul"),
    (_WEB_EN, "Notifications", "your own birth"),
    (_DART, "Notifications", "Europe/Istanbul"),
    (_DART, "Notifications", "your own birth"),
)


@pytest.mark.parametrize("yol,baslik,capa", _BILDIRIM_CAPALARI)
def test_bildirim_bolumu_olculen_hali_anlatir(yol, baslik, capa):
    govde = _bolum(yol, baslik)
    assert capa in govde, (
        f"{yol} '{baslik}': beyan kaymış — {capa!r} bölümün GÖVDESİNDE "
        f"bulunamadı. Bildirim gövdesi hâlâ kullanıcının kendi "
        f"haritasından üretiliyorsa (bkz. services/notification_service.py) "
        f"bu beyan dört kopyada da durmak zorunda. Not: aynı ifadenin "
        f"başka bir bölümde geçmesi yetmez (mutasyon M3b)."
    )


#: Mutlak iddianın taşıyıcısı: "ona ait tek bir bayt yoktur". Bu cümle
#: niteleyicisiz kaldığı an yanlış beyan olur.
_MUTLAK = ("tek bir bayt", "single byte")

#: Kabul edilen niteleyiciler — KELİME BAŞINA bağlı (CLAUDE.md §5: alt
#: dize eşleşmesi yanlış pozitif üretir). Büyük harfli biçimler uygulama
#: içi metnin vurgulama yöntemi.
_NITELEYICI = re.compile(r"\b(kalıcı|KALICI|persistent|PERSISTENT)")

#: (dosya, bölüm, geçici istisnanın çapası). Yalnız mutlak cümleyi
#: yumuşatmak yetmez: ölçülen şey (IP'nin kota katmanında bellekte
#: tutulduğu) SÖYLENMELİ, yoksa beyan eksik kalır.
_TIKLAMA_BOLUMLERI = (
    (_WEB_TR, "Ortak bağlantısı tıklamaları", "sunucu belleğinde"),
    (_DART, "Ortak bağlantısı tıklamaları", "sunucu belleğinde"),
    (_WEB_EN, "Affiliate link clicks", "server memory"),
    (_DART, "Affiliate link clicks", "server memory"),
)


@pytest.mark.parametrize("yol,baslik,istisna", _TIKLAMA_BOLUMLERI)
def test_tiklama_bolumu_IP_iddiasini_MUTLAK_yazmaz(yol, baslik, istisna):
    """"IP tutulmaz" mutlak biçimde yazılamaz — ölçüldü.

    Kota katmanı tıklama ucunda ziyaretçinin IP'sini sayaç anahtarı olarak
    BELLEKTE tutuyor (`core/ratelimit._client_key`, `sadece_ip=True`;
    pencere 60 sn, budama 300 sn). `api/partners.py` bunu kendi
    docstring'inde (satır 132-135) zaten beyan ediyor. Politika yalnız
    KALICI kayıt için "yok" diyebilir; mutlak cümle yanlış beyan olur.

    Niteleyici, mutlak iddiayı taşıyan CÜMLEDE aranır — dosyada değil.
    Gerekçe modül başlığında: dosya kapsamlı arama mutasyon sınavında
    (M4) asıl gerilemeyi kaçırdı.
    """
    govde = _bolum(yol, baslik)

    mutlak_cumleler = [c for c in _cumleler(govde)
                       if any(m in c for m in _MUTLAK)]
    assert mutlak_cumleler, (
        f"{yol} '{baslik}': tıklama ölçümünün kapsamını anlatan cümle "
        f"({' / '.join(_MUTLAK)}) yok. Metin ne söylediğini kaybetmiş; "
        f"beyan bilerek değiştiyse bu bekçi de güncellenmeli.")

    for cumle in mutlak_cumleler:
        assert _NITELEYICI.search(cumle), (
            f"{yol} '{baslik}': IP iddiası KALICI kayıtla "
            f"sınırlandırılmamış. Kota katmanı IP'yi bellekte tutuyor "
            f"(core/ratelimit._client_key), yani mutlak 'IP yazılmaz' "
            f"cümlesi yanlış beyandır. Niteliksiz cümle: {cumle!r}")

    assert istisna in govde, (
        f"{yol} '{baslik}': geçici istisna anlatılmamış ({istisna!r} yok). "
        f"Mutlak cümleyi yumuşatmak yetmez — ölçülen şey (IP'nin kota "
        f"katmanında bellekte tutulduğu) SÖYLENMELİ.")


# ---------------------------------------------------------------------------
# Aynı mutlak iddia KAYNAK YORUMLARINDA (48-turu bulgusu)
# ---------------------------------------------------------------------------
#
# NEDEN burada: yukarıdaki mekanizma (_MUTLAK + _NITELEYICI) yalnız DÖRT
# KULLANICI METNİNE bakıyordu. Oysa aynı sınıf kusur bir kez kaynak
# yorumunda yaşandı: `partner_service.py` gizlilik çizgisini MUTLAK
# yazıyordu ("ziyaretçiye ait tek bir bayt bile yazılmaz") ve o gerekçe
# yanlıştı — kota katmanı ziyaretçinin IP'sini kova anahtarı olarak
# BELLEKTE tutuyor. Düzeltildi, ama hiçbir bekçi görmedi: iddiayı geri
# MUTLAK yazmak tüm takımı YEŞİL bırakırdı.
#
# ⚠️ Bu bekçi BAŞKA BİR PAKETİN kaynağını OKUYOR, yazmıyor. Ölçtüğü şey bir
# BEYAN (yorum), davranış değil — yani kod yeniden düzenlendiğinde değil,
# BEYAN kaydığında kızarır.

#: Kaynaktaki üç tırnaklı gövdeler. İddianın bir yarısı yorumda
#: (`partner_service.py`), öteki yarısı docstring'de (`api/partners.py`)
#: yaşıyor; ikisi de taranmak zorunda, yoksa bekçi yarım olur.
_DOCSTRING = re.compile(r'"""(.*?)"""', re.S)

#: Satır başındaki yorum işareti (`#` ya da `#:`).
_YORUM_ISARETI = re.compile(r"^\s*#:?\s?")

#: Alıntı span'i. Alıntılar eşleşmeden ÖNCE atılır ve bu, CLAUDE.md
#: kuralının TERS YÖNÜ: "bir şeyin YOKLUĞUNU arayan bekçi, onu ANLATAN
#: yorumu görmemeli". `partner_service.py` eski MUTLAK cümleyi
#: ALINTILAYARAK "o gerekçe yanlıştı" diyor; alıntı atılmazsa bu bekçi
#: doğduğu an KIRMIZI doğar ve onu yeşile çekmenin tek yolu düzeltmenin
#: KAYDINI silmek olurdu — yani bekçi, kendisini doğuran kusurun
#: hatırasını yok etmeye zorlardı.
_ALINTILI = re.compile(r'"[^"]*"')


def _prose_bloklari(kaynak: str) -> list[str]:
    """Kaynaktaki PROSE'u mantıksal bloklar hâlinde verir.

    Kod GÖVDESİ taranmıyor: ölçülen şey bir BEYAN, çalışan davranış değil.

    NEDEN satır satır DEĞİL blok blok: aranan iddia iki yorum satırına
    bölünmüş durumda ve kapanış tırnağı öteki satırda (ölçüldü,
    `partner_service.py`). Satır satır bakan bir denetim alıntıyı yarım
    görür, tırnağı eşleştiremez ve ANLATIYI BEYAN sanır — yani tam da
    kaçınılan yanlış pozitifi üretir.
    """
    bloklar = [re.sub(r"\s+", " ", govde)
               for govde in _DOCSTRING.findall(kaynak)]
    kume: list[str] = []
    for satir in kaynak.split("\n"):
        if re.match(r"^\s*#", satir):
            kume.append(_YORUM_ISARETI.sub("", satir).strip())
        elif kume:
            bloklar.append(" ".join(kume))
            kume = []
    if kume:
        bloklar.append(" ".join(kume))
    return bloklar


def _niteliksiz_mutlak(bloklar: list[str]) -> list[str]:
    """Niteleyicisiz MUTLAK cümleler. Alıntı ATILMIŞ hâlde ölçülür."""
    bulunan: list[str] = []
    for blok in bloklar:
        for cumle in _cumleler(_ALINTILI.sub(" ", blok)):
            if not any(mutlak in cumle for mutlak in _MUTLAK):
                continue
            if not _NITELEYICI.search(cumle):
                bulunan.append(cumle)
    return bulunan


#: (kaynak, ölçülmüş istisnayı anlatan çapalar). Çapa TEK bir Türkçe
#: kelimeye bağlanmıyor; her dosyadan birkaç BAĞIMSIZ işaret birden
#: isteniyor (modül adı · ölçülen çağrı · belleğin adı). Biri yeniden
#: yazılırsa ötekiler durur, yani bekçi bir üslup değişikliğiyle değil
#: BEYANIN kaymasıyla kızarır. Büyük/küçük harf ÇEVRİLMİYOR: `lower()`
#: Türkçe bilmez (CLAUDE.md §5) ve burada gereği de yok — çapalar dize
#: literali olarak aranıyor.
_KAYNAK_BEYANLARI = (
    ("backend/services/partner_service.py",
     ("core/ratelimit.py", "sadece_ip=True", "BELLEĞİNDEKİ")),
    ("backend/api/partners.py",
     ("core/ratelimit.py", "BELLEKTE")),
)


@pytest.mark.parametrize("yol,capalar", _KAYNAK_BEYANLARI)
def test_kaynak_yorumu_IP_iddiasini_MUTLAK_yazmaz(yol, capalar):
    """Gizlilik çizgisini anlatan KAYNAK yorumu da niteleyici taşır.

    Politika metni için geçerli olan şey kaynak yorumu için de geçerlidir:
    kota katmanı IP'yi bellekte tutuyor, yani mutlak "tek bir bayt bile
    yazılmaz" cümlesi YANLIŞ BEYANDIR. Fark şu ki politika metnini
    kullanıcı okur, yorumu bir SONRAKİ geliştirici okur ve yanlış gerekçeye
    dayanarak karar verir — CLAUDE.md bu yüzden yanlış gerekçeyi KUSUR
    sayıyor.
    """
    tam = _KOK / yol
    assert tam.exists(), (
        f"{yol} yok: bu bekçi bir BEYANI çiviliyor ve çapasını kaybetti. "
        f"Modül taşındıysa çapa yeniden nişanlanmalı — sessizce atlanmaz.")
    kaynak = tam.read_text(encoding="utf-8")

    niteliksiz = _niteliksiz_mutlak(_prose_bloklari(kaynak))
    assert not niteliksiz, (
        f"{yol}: gizlilik çizgisi MUTLAK yazılmış. Kota katmanı tıklama "
        f"ucunda ziyaretçinin IP'sini kova anahtarı olarak BELLEKTE "
        f"tutuyor (core/ratelimit._client_key, sadece_ip=True), yani "
        f"niteleyicisiz cümle yanlış beyandır. Niteliksiz: {niteliksiz!r}")

    eksik = [capa for capa in capalar if capa not in kaynak]
    assert not eksik, (
        f"{yol}: ölçülmüş istisna artık anlatılmıyor ({eksik!r} yok). "
        f"Mutlak cümleyi yumuşatmak YETMEZ — ölçülen şey SÖYLENMELİ, "
        f"yoksa bir sonraki okuyan 'hiçbir yere yazılmıyor' diye anlar.")


def test_kaynak_denetiminin_DISI_var():
    """Mekanizma gerçekten ısırıyor mu — MİNİMAL mutasyonla ölçülüyor.

    NEDEN gerekli: yukarıdaki bekçi iki katmanlı (alıntı atılır, sonra
    niteleyici istenir) ve ikisinden biri kör olsa test yine YEŞİL kalırdı.
    Bu depoda üç paket "mutasyonların hepsi kırmızı" dedi; minimal
    mutasyonla sınandığında 8, 11 ve 2 kör bekçi çıktı.

    Mutasyon BELLEKTE ve TEK TERİM: çıkarılan şey yalnız ALINTI
    TIRNAKLARI, yani cümle "eskiden böyle yazılmıştı" anlatısı olmaktan
    çıkıp BEYAN oluyor. Diske yazılmıyor çünkü `partner_service.py` bu
    turda başka bir paketin dosyası ve yedi ajan aynı depoda çalışıyor —
    geçici bir mutasyon onların yazısını ezebilirdi. Tırnakların YERİ
    dosyadan ölçülüyor, elle yazılmış satır düzenine bağlanmıyor.
    """
    kaynak = (_KOK / "backend/services/partner_service.py").read_text(
        encoding="utf-8")
    bloklar = _prose_bloklari(kaynak)

    alintililar = [alinti for blok in bloklar
                   for alinti in _ALINTILI.findall(blok)
                   if any(mutlak in alinti for mutlak in _MUTLAK)]
    assert alintililar, (
        "ön koşul tutmuyor: kaynak eski MUTLAK iddiayı ALINTILAYARAK "
        "anlatmıyor. O anlatı kalktıysa bu ölçüm de anlamsız — mutasyonun "
        "değiştireceği terim yok.")
    assert not _niteliksiz_mutlak(bloklar), (
        "ön koşul tutmuyor: kaynak bugün zaten niteliksiz (üstteki bekçi "
        "kırmızı olmalı)")

    mutant = [blok.replace('"', "") for blok in bloklar]
    assert _niteliksiz_mutlak(mutant), (
        "denetim KÖR: alıntı tırnakları kalktığında bile niteleyicisiz "
        "MUTLAK cümle görmüyor. Yani üstteki bekçi bir şey ölçmüyor ve "
        "gerekçe geri MUTLAK yazılsa yeşil kalırdı.")


# ---------------------------------------------------------------------------
# "Yapay zeka ile işleme" — onay modeli DÖRT kopyada aynı (2026-10-22)
# ---------------------------------------------------------------------------
#
# Sahip kararı 2026-10-22: yapay zeka aktarım onayı YALNIZ kurulumun ilk
# adımında, şartlar kutusundan AYRI ve ZORUNLU ikinci bir kutuyla alınır;
# ayrı onay sayfası, Profil > Gizlilik'teki anahtar ve onaya bağlı kapanan
# özellik YOK, geri alma yolu hesap silme. U06 turu politikaya o sayfayı,
# o anahtarı ve "izin yoksa kapalı kalır" cümlelerini yazmıştı. Dört
# kopyadan biri eski hâlde kalırsa kullanıcı, baktığı yüzeye göre farklı
# bir onay modeli okur — bu dosyanın varlık sebebi olan ayrışmanın aynısı.
# Sahip kararı 2026-10-23: kutu ve onay cümlesi sağlayıcı ADI taşımaz
# ("üçüncü taraf yapay zeka hizmetleri"), sağlayıcıyı politikanın geri
# kalanı adıyla anar — bkz. aşağıdaki "sağlayıcıdan bağımsız onay" bölümü.
#
# Bölüm HTML'de `<h2>` (madde 2), Dart'ta `(başlık, gövde)` çifti; çapalar
# BÖLÜMDE aranır (M3b gerekçesi modül başlığında). HTML varlıkları
# çözülür: "Profil &gt; Gizlilik" çözülmeden aranırsa geri dönüşü
# görünmez.


def _ai_bolumu(yol: str, baslik: str) -> str:
    """Yapay zeka bölümünün OKUNAN gövdesi (HTML'de madde 2, `<h2>`)."""
    if yol.endswith(".dart"):
        return _bolum(yol, baslik)
    ham = _yorumsuz(yol, _oku(yol))
    eslesme = re.search(
        rf"<h2>[^<]*{re.escape(baslik)}[^<]*</h2>(.*?)(?=<h2)", ham, re.S)
    assert eslesme, f"{yol}: '{baslik}' (madde 2) bölümü YOK"
    return html.unescape(_sadelestir(yol, eslesme.group(1)))


#: (dosya, başlık, bölümde durması gereken çapalar). Çapalar kararın
#: parçaları: sağlayıcının adı, kutunun AYRI ve ZORUNLU oluşu, kurulumun
#: onaysız TAMAMLANMAMASI, geri alma yolu ve BaZi isteminin taşıdığı doğum
#: saati. Geri alma yolundaki menü adları sözlükten (`tabProfile` >
#: `accountSection` > `deleteAccount`); Dart tarafı bunu
#: `legal_texts_test.dart`ta ARB'den kurup karşılaştırıyor.
#:
#: ⚠️ Kutu çapaları İFADE düzeyinde. Bir tur boyunca webde tek kelimeydi
#: ("zorunlu" / "mandatory") ve kör olduğu mutasyonla ölçüldü (2026-10-23):
#: "ondan ayrı, zorunlu olmayan bir kutuyla" ya da "zorunlu değil" yazılsa
#: kelime yine geçtiği için bekçi YEŞİL kalıyordu — yani tam da korunan
#: kararın tersi ("onaysız da kurulur") okunurken.
_AI_CAPALARI = (
    (_DART, "Yapay zeka ile işleme",
     ("Gemini API", "Google LLC", "AYRI ve ZORUNLU", "kurulum tamamlanmaz",
      "Profil > Hesap > Hesabı sil", "doğum saatin")),
    (_DART, "AI processing",
     ("Gemini API", "Google LLC", "SEPARATE, MANDATORY",
      "Setup cannot be completed", "Profile > Account > Delete account",
      "birth time")),
    (_WEB_TR, "Yapay zeka ile işleme",
     ("Gemini API", "Google LLC", "ayrı ve zorunlu", "kurulum tamamlanmaz",
      "Profil → Hesap → Hesabı sil", "doğum saatiniz")),
    (_WEB_EN, "AI processing",
     ("Gemini API", "Google LLC", "separate, mandatory",
      "Setup cannot be completed", "Profile → Account → Delete account",
      "birth time")),
)

#: Kaldırılan modelin cümleleri — dört kopyanın yapay zeka bölümünde
#: HİÇBİRİ durmaz. "Profil > Gizlilik" yüz okuma rızası için hâlâ doğru
#: (o bölümde durur), bu yüzden arama dosyada değil BU bölümde.
#:
#: İkinci yarı U06'nın ANAHTAR KELİMESİZ cümleleri ("uygulama içinde AYRI
#: … iznini isteriz", "Geri aldığın andan itibaren gönderim durur"). İlk
#: yarı yalnız "Profil > Gizlilik" gibi menü adlarını tanıyordu; mutasyonla
#: ölçüldü (2026-10-23) ki menü adı silinip cümle bırakılınca — yani
#: olmayan bir "uygulama içi izin" ve "geri alınca gönderim durur" vaadi
#: okunurken — bekçi YEŞİL kalıyordu. Web TR'de U06 aynı cümleyi küçük
#: harfle ve "siz" ekiyle yazmıştı, iki yazım da burada.
#: "zorunlu değil" / "not mandatory" de burada: kutunun zorunluluğunu
#: tersine çeviren cümle. Dosya kapsamlı aranamaz — telefon bölümündeki
#: "doğrulamak zorunlu değildir" meşru.
_ESKI_AI_MODELI = (
    "Profil > Gizlilik", "Profile > Privacy",
    "kapalı kalır", "stay off",
    "İzin vermez", "If you do not give it",
    "yeniden verebilir", "give this permission again",
    "İzin verdiğinde", "İzin verdiğinizde", "Once you allow it",
    "uygulama içinde AYRI", "uygulama içinde ayrı",
    "Geri aldığın andan", "geri aldığın andan",
    "Geri aldığınız andan", "geri aldığınız andan",
    "inside the app", "from the moment you withdraw",
    "zorunlu değil", "ZORUNLU DEĞİL", "not mandatory", "NOT MANDATORY",
)


@pytest.mark.parametrize("yol,baslik,capalar", _AI_CAPALARI)
def test_yapay_zeka_bolumu_onay_modelini_dort_kopyada_anlatir(
        yol, baslik, capalar):
    govde = _ai_bolumu(yol, baslik)
    eksik = [capa for capa in capalar if capa not in govde]
    assert not eksik, (
        f"{yol} '{baslik}': {eksik!r} bölümde yok. Sahip kararı "
        f"2026-10-22: onay kurulumun ilk adımında ayrı ve zorunlu kutuyla "
        f"alınır, geri alma yolu hesap silme; BaZi istemi doğum saatini "
        f"taşıyor. Dört kopya aynı modeli anlatmak zorunda.")


@pytest.mark.parametrize("yol,baslik",
                         [(yol, baslik) for yol, baslik, _ in _AI_CAPALARI])
def test_yapay_zeka_bolumu_kaldirilan_onay_modelini_tasimaz(yol, baslik):
    govde = _ai_bolumu(yol, baslik)
    donen = [eski for eski in _ESKI_AI_MODELI if eski in govde]
    assert not donen, (
        f"{yol} '{baslik}': kaldırılan onay modeli geri gelmiş {donen!r}. "
        f"Ayrı onay sayfası, Profil > Gizlilik anahtarı ve onaya bağlı "
        f"kapanan özellik yok (sahip kararı 2026-10-22); metin olmayan bir "
        f"anahtarı vaat ederdi.")


#: Bildirim bölümünün U06 cümleleri: "AI izni yoksa teknik satır gider,
#: akşam sorusu gitmez". Onaya bağlı bir bildirim kapısı artık yok.
_ESKI_BILDIRIM_KAPISI = (
    "iznin varsa", "İznin yoksa", "izniniz varsa", "İzniniz yoksa",
    "yapay zeka izniniz", "teknik satır",
    "allowed AI processing", "If you have not", "technical line",
)


@pytest.mark.parametrize("yol,baslik", [
    (_DART, "Bildirimler"), (_WEB_TR, "Bildirimler"),
    (_DART, "Notifications"), (_WEB_EN, "Notifications"),
])
def test_bildirim_bolumu_onaya_bagli_kapi_anlatmaz(yol, baslik):
    govde = _bolum(yol, baslik)
    donen = [eski for eski in _ESKI_BILDIRIM_KAPISI if eski in govde]
    assert not donen, (
        f"{yol} '{baslik}': onaya bağlı bildirim kapısı anlatılıyor "
        f"{donen!r} — o kapı kaldırıldı (sahip kararı 2026-10-22).")


@pytest.mark.parametrize("yol", [_DART, _WEB_TR, _WEB_EN])
def test_alt_isleyici_satiri_gemini_icin_izin_kosulu_koymaz(yol):
    """U06'nın alt işleyici satırı Gemini'yi "yalnızca izin verdiğinizde"
    diye niteliyordu; onaya bağlı bir kapı kalmadığı için o nitelik artık
    olmayan bir davranışı anlatır."""
    metin = html.unescape(_sadelestir(yol, _yorumsuz(yol, _oku(yol))))
    for eski in ("yalnızca izin verdiğinizde", "only with your permission"):
        assert eski not in metin, f"{yol}: {eski!r} geri gelmiş"


def test_bazi_istemi_dogum_saatini_tasir_politika_bunu_soyler():
    """53'ün "doğum tarihin/saatin değil" iddiası KODA aykırıydı — ölçülür.

    `_bazi_notes` gerçek güneş zamanı beyanını doğumun DUVAR SAATİYLE
    (`birth_local`ın SS:DD kısmı) kuruyor ve beyan BAZI istemine
    `{notes}` olarak giriyor; şans sütunu satırı takvim yılı + yaş
    aralığı taşıyor, doğum yılı ikisinin farkı. Kod bunu bırakırsa burası
    düşer ve dört kopyadaki "doğum saatin / birth time" beyanı yeniden
    okunur — fazla söyleyen metin de ölçülmeyen beyandır.
    """
    from services import prompts

    tr = prompts.get("tr")
    notlar = prompts._bazi_notes(tr, {
        "birth_local": "1990-05-12T13:30:00+03:00",
        "solar_time": "1990-05-12T12:22:00+03:00",
        "tst_offset_minutes": -68,
    })
    assert any("13:30" in n for n in notlar), notlar
    assert "{notes}" in tr.BAZI and "{luck}" in tr.BAZI
    rapor = (_KOK / "backend/services/report_service.py").read_text(
        encoding="utf-8")
    assert "lp['from_year']" in rapor and "lp['from_age']" in rapor


# ---------------------------------------------------------------------------
# Sağlayıcıdan bağımsız onay + ölçülerek düzeltilen beyanlar (2026-10-23)
# ---------------------------------------------------------------------------
#
# NEDEN ayrı bir bölüm: sahip kararı 2026-10-23 (K1) kurulum kutusunu
# sağlayıcı adından ayırdı — "bugün Gemini yarın başka bir hizmet olur";
# kutu "üçüncü taraf yapay zeka hizmetleri" der ve sağlayıcıyı bu
# politikaya bırakır. Politika ise bugünkü sağlayıcıyı ADIYLA anmaya devam
# etmek zorunda (App Store 5.1.2(i): verinin kime gittiği açıkça yazılır).
# İki iddia birbirine bağlı ve ikisi AYRI çivilenir: onay cümlesi adı
# taşırsa sağlayıcı değiştiği gün yalana döner; bölümün geri kalanı adı
# taşımazsa kutunun "kullanılan hizmet Gizlilik Politikası'nda yazar" sözü
# boşa düşer. Kutunun kendisi `legal_texts_test.dart`ta (ARB'yi o okuyor).
#
# Aynı turda dört kopyada ölçülerek düzeltilen beyanlar da burada
# çivileniyor (arkadaşın haritasından türeyen veri, Yıl Haritası'nın 90
# günlük önbelleği, I Ching soru kapısı, yaşadığın şehir, yurt dışı
# aktarım). Her birinin KOD dayanağı da okunur: kod değişip metin aynı
# kalırsa — ya da tersi — burası düşer ve beyan yeniden okunur.

#: Kopya -> (dosya, Dart sabiti ya da None, dil). Dart dosyası iki kopya
#: taşıyor; web kopyalarında bölüm sınırı başlık etiketidir.
_KOPYALAR = {
    "uygulama TR": (_DART, "kPrivacyPolicyTr", "tr"),
    "uygulama EN": (_DART, "kPrivacyPolicyEn", "en"),
    "web TR": (_WEB_TR, None, "tr"),
    "web EN": (_WEB_EN, None, "en"),
}
_KOPYA_ADLARI = tuple(_KOPYALAR)

#: Kopya başına bölüm başlıkları — TAM eşitlikle aranır. Alt dize yetmez:
#: web EN'de "b) Birth data" ile "h) Birth data of people you add" ikisi
#: de "Birth data" taşıyor ve eşleşme sırası değiştiği gün bekçi yanlış
#: bölümü okurdu. Başlık değişirse bekçi "bölüm YOK" diye düşer — bilerek.
_BASLIKLAR = {
    "uygulama TR": {"ai": "Yapay zeka ile işleme",
                    "aktarim": "Alt işleyiciler",
                    "saklama": "Saklama süresi",
                    "dogum": "Doğum verisi",
                    "yuz": "Yüz okuma"},
    "uygulama EN": {"ai": "AI processing",
                    "aktarim": "Sub-processors",
                    "saklama": "Retention",
                    "dogum": "Birth data",
                    "yuz": "Face reading"},
    "web TR": {"ai": "2. Yapay zeka ile işleme (Google Gemini)",
               "aktarim": "3. Alt işleyiciler",
               "saklama": "4. Saklama süreleri",
               "dogum": "b) Doğum verisi",
               "yuz": "c) Yüz okuma (firaset) ölçümleri"},
    "web EN": {"ai": "2. AI processing (Google Gemini)",
               "aktarim": "3. Sub-processors",
               "saklama": "4. Retention",
               "dogum": "b) Birth data",
               "yuz": "c) Face reading (physiognomy) measurements"},
}


def _politika_bolumleri(kopya: str) -> list[tuple[str, str]]:
    """Kopyanın BÜTÜN bölümleri, (başlık, OKUNAN gövde) olarak.

    `_bolum` tek bir başlığı arıyor; "X şu bölüm DIŞINDA hiçbir yerde
    geçmez" diyen bir bekçi ise bölümlerin tamamını gezmek zorunda. Dart'ta
    yalnız istenen sabitin listesi okunur — aynı dosyadaki kullanım
    şartları da `(başlık, gövde)` çifti taşıyor ve onları politika sanmak
    bekçiyi şartlardaki bir cümleye takardı. Başlıksız (`null`) girdiler ve
    webde ilk başlıktan önceki giriş paragrafı boş başlıkla dahil: "bütün
    politika" diyen kural orayı da kapsamalı.
    """
    yol, sabit, _ = _KOPYALAR[kopya]
    ham = _yorumsuz(yol, _oku(yol))
    bolumler: list[tuple[str, str]] = []
    if sabit is not None:
        bas = ham.index(f"const LegalSections {sabit} = [")
        blok = ham[bas:ham.index("\n];", bas)]
        for m in re.finditer(
                r"\n  \(\n    (null|'(?:[^'\\]|\\.)*'),\n(.*?)\n  \),",
                blok, re.S):
            baslik = ("" if m.group(1) == "null"
                      else m.group(1)[1:-1].replace("\\'", "'"))
            bolumler.append((baslik, _sadelestir(yol, m.group(2))))
    else:
        govde = ham[ham.index("<main"):ham.index("</main>")]
        parcalar = re.split(r"(<h[23]>.*?</h[23]>)", govde, flags=re.S)
        bolumler.append(("", html.unescape(_sadelestir(yol, parcalar[0]))))
        for i in range(1, len(parcalar) - 1, 2):
            bolumler.append((
                html.unescape(_sadelestir(yol, parcalar[i])),
                html.unescape(_sadelestir(yol, parcalar[i + 1]))))
    # Ayıklayıcı biçimi kaybederse liste boşalır ve "hiçbir bölümde
    # geçmez" diyen her bekçi boş listeye bakıp YEŞİL kalır.
    assert len(bolumler) >= 15, (
        f"{kopya}: yalnız {len(bolumler)} bölüm ayıklandı — kaynağın "
        f"biçimi değişmiş olabilir, ayıklayıcı güncellenmeli.")
    return bolumler


def _govde(kopya: str, anahtar: str) -> str:
    baslik = _BASLIKLAR[kopya][anahtar]
    for b, g in _politika_bolumleri(kopya):
        if b == baslik:
            return g
    raise AssertionError(
        f"{kopya}: '{baslik}' bölümü YOK. Başlık değiştiyse _BASLIKLAR "
        f"güncellenmeli; bölüm kalktıysa dört kopyadan da kalkmalı.")


def _dil(kopya: str) -> str:
    return _KOPYALAR[kopya][2]


def _kaynak(yol: str) -> str:
    dosya = _KOK / yol
    assert dosya.exists(), f"{yol} yok — beyanın kod dayanağı kayboldu"
    return dosya.read_text(encoding="utf-8")


def _arb(dil: str) -> dict:
    return json.loads(_kaynak(f"apps/mobile/lib/l10n/app_{dil}.arb"))


#: Sağlayıcı adları — onay cümlesinde HİÇBİRİ geçmez. Liste bugünkü
#: sağlayıcıyla sınırlı değil: K1'in gerekçesi "yarın başka bir hizmet
#: olur", yani yarının adı da o cümleye girmemeli.
_SAGLAYICI_ADLARI = ("Gemini", "Google", "Claude", "Anthropic", "OpenAI",
                     "GPT")

#: Kopya -> (kutuyu anlatan çapa, sağlayıcıdan bağımsız hedef, adım,
#: kurulumun onaysız tamamlanmadığını söyleyen cümle).
_ONAY = {
    "uygulama TR": ("AYRI ve ZORUNLU",
                    "üçüncü taraf yapay zeka hizmetlerine",
                    "ilk kurulum adımında",
                    "İki kutu da işaretlenmeden kurulum tamamlanmaz."),
    "web TR": ("ayrı ve zorunlu",
               "üçüncü taraf yapay zeka hizmetlerine",
               "ilk kurulum adımında",
               "İki kutu da işaretlenmeden kurulum tamamlanmaz."),
    "uygulama EN": ("SEPARATE, MANDATORY",
                    "third-party AI services",
                    "first step of the app's initial setup",
                    "Setup cannot be completed unless both boxes are "
                    "ticked."),
    "web EN": ("separate, mandatory",
               "third-party AI services",
               "first step of the app's initial setup",
               "Setup cannot be completed unless both boxes are ticked."),
}


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_onay_cumlesi_saglayicidan_bagimsiz(kopya):
    """Onay CÜMLESİ hedefi "üçüncü taraf yapay zeka hizmetleri" diye anar,
    sağlayıcı adını taşımaz (K1, 2026-10-23).

    Cümle kapsamlı ve bilerek: aynı bölüm sağlayıcıyı adıyla anmak ZORUNDA
    (bkz. `test_politika_bugunku_saglayiciyi_adiyla_anar`), yani bölüm
    kapsamlı bir "Gemini geçmez" araması kurulamaz.
    """
    capa, hedef, adim, _ = _ONAY[kopya]
    cumleler = [c for c in _cumleler(_govde(kopya, "ai")) if capa in c]
    assert len(cumleler) == 1, (
        f"{kopya}: kutuyu anlatan cümle ({capa!r}) {len(cumleler)} kez "
        f"bulundu, tam bir kez olmalı.")
    cumle = cumleler[0]
    assert hedef in cumle and adim in cumle, (
        f"{kopya}: onay cümlesi, kurulumun ilk adımındaki kutunun "
        f"{hedef!r} aktarım için olduğunu söylemiyor: {cumle!r}")
    adlar = [ad for ad in _SAGLAYICI_ADLARI if ad in cumle]
    assert not adlar, (
        f"{kopya}: onay cümlesi sağlayıcı adı taşıyor {adlar!r}. K1: kutu "
        f"ve onay cümlesi sağlayıcıdan bağımsız — sağlayıcı değişince cümle "
        f"yalana döner. Ad bölümün geri kalanında durur: {cumle!r}")


#: K2 (sahip kararı 2026-10-23): TR sahibin metni birebir, EN anlamca
#: birebir. Uygulama ve web AYNI dizeyi taşır — ayrışırsa hangisinin
#: bağlayıcı olduğu belirsizleşir.
_GECIS = {
    "tr": ("Bu ayrı kutu 1.20.0+54 sürümüyle eklendi. Daha önce kurulumu "
           "tamamlayan hesaplar, Gemini aktarımını anlatan önceki Gizlilik "
           "Politikası'nı kabul ederek devam etti."),
    "en": ("This separate checkbox was added in version 1.20.0+54. "
           "Accounts that completed setup earlier continued by accepting "
           "the previous Privacy Policy, which described the transfer to "
           "Gemini."),
}


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_gecis_cumlesi_onay_cumlesinin_hemen_ardinda(kopya):
    """Eski hesaplar için geçiş cümlesi (K2) dört kopyada, onay modelini
    anlatan cümlelerin HEMEN ardında.

    Yeri de çivili, çünkü cümle "Bu ayrı kutu" diye başlıyor: başka bir
    paragrafa kayarsa "bu"nun hangi kutuyu gösterdiği kaybolur. 53'ten
    gelen hesap kurulumu bu kutu olmadan tamamladı ve onun adına onay kaydı
    YAZILMIYOR — politikanın o hesaba ne dediğini taşıyan tek cümle bu.
    """
    tamamlanmaz = _ONAY[kopya][3]
    gecis = _GECIS[_dil(kopya)]
    govde = _govde(kopya, "ai")
    assert gecis in govde, (
        f"{kopya}: geçiş cümlesi (K2) yok ya da kelimesi kaymış: {gecis!r}")
    assert f"{tamamlanmaz} {gecis}" in govde, (
        f"{kopya}: geçiş cümlesi onay modelinin hemen ardında değil — "
        f"{tamamlanmaz!r} ile arasına başka bir şey girmiş.")


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_politika_bugunku_saglayiciyi_adiyla_anar(kopya):
    """Kutunun sağlayıcı adı TAŞIMAMASI bir söze dayanıyor: "Kullanılan
    hizmet Gizlilik Politikası'nda yazar". O söz yalnız politika bugünkü
    sağlayıcıyı şirketiyle, hizmet adıyla ve alt işleyici satırında andığı
    sürece doğru; App Store 5.1.2(i) de verinin kime gittiğinin açıkça
    yazılmasını istiyor. Onay cümlesinin adsızlaşması bu adı bölümden
    silmeye ruhsat değil."""
    ai = _govde(kopya, "ai")
    for ad in ("Google LLC", "Gemini API"):
        assert ad in ai, f"{kopya}: yapay zeka bölümü {ad!r} demiyor"
    assert "Gemini API" in _govde(kopya, "aktarim"), (
        f"{kopya}: alt işleyiciler Gemini API'yi saymıyor")


#: "Profil > Gizlilik" menü yolu — webde ok imiyle de yazılıyor.
_GIZLILIK_MENUSU = re.compile(r"Profile?\s*(?:>|→)\s*(?:Gizlilik|Privacy)")

#: Yapay zekanın anılışı, dile göre. EN'de "AI" KELİME olarak aranır: alt
#: dize olarak büyük harfli başka sözcüklere takılırdı (CLAUDE.md §5).
_YAPAY_ZEKA = {"tr": re.compile(r"yapay zeka|gemini", re.I),
               "en": re.compile(r"\bAI\b|Gemini")}


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_gizlilik_menusu_yapay_zekayla_yalniz_yuz_okumada(kopya):
    """"Profil > Gizlilik" yapay zekayla aynı bölümde YALNIZ yüz okumada
    anılabilir.

    Neden bütün politika: U06 modeli (Profil > Gizlilik'te yapay zeka
    anahtarı) yalnız yapay zeka bölümünde aranıyordu. Aynı cümle bildirim
    ya da saklama bölümüne taşınsa — kullanıcıya olmayan bir anahtarı vaat
    ederek — o bekçi görmezdi. Yüz okuma istisna: rızası gerçekten Profil >
    Gizlilik'ten geri alınıyor ve yorumu yapay zeka yazıyor.
    """
    yuz = _BASLIKLAR[kopya]["yuz"]
    bolumler = _politika_bolumleri(kopya)
    assert any(b == yuz for b, _ in bolumler), f"{kopya}: '{yuz}' bölümü YOK"
    ihlal = [b or "(başlıksız)" for b, g in bolumler
             if b != yuz and _GIZLILIK_MENUSU.search(g)
             and _YAPAY_ZEKA[_dil(kopya)].search(g)]
    assert not ihlal, (
        f"{kopya}: {ihlal!r} bölümü 'Profil > Gizlilik'i yapay zekayla "
        f"birlikte anıyor. Yapay zeka onayının Profil > Gizlilik'te bir "
        f"anahtarı YOK (sahip kararı 2026-10-22); geri alma yolu hesap "
        f"silme.")


#: Yapay zeka bölümünde sayılan özellik adları EKRANDAKİ adlarla, ARB'den.
#: Bir tur boyunca dört kopya "İç Takvim / Inner Calendar" diyordu; ekran
#: (`innerCalendarTitle`) "İç mevsim / Inner season" — kullanıcı politikada
#: okuduğu özelliği uygulamada bulamıyordu. İkinci alan: ad cümle içinde
#: küçük harfle mi başlar. Küçültme yalnız ASCII ilk harfte yapılır;
#: Türkçe `lower()` "İ"yi bozar (CLAUDE.md §5).
_OZELLIK_ADLARI = (("solarReturnTitle", False),
                   ("innerCalendarTitle", False),
                   ("birthHexagramTitle", False),
                   ("natalLockedTitle", True))

#: Ekrandan kalkmış adlar — politikanın HİÇBİR yerinde durmaz.
_ESKI_OZELLIK_ADLARI = ("İç Takvim", "Inner Calendar", "natal rapor",
                        "natal report")


def _ekrandaki_ad(dil: str, anahtar: str, kucuk: bool) -> str:
    ad = _arb(dil)[anahtar]
    if kucuk:
        assert ad[:1].isascii(), (
            f"{anahtar}: ilk harf ASCII değil, Türkçe küçültme bozar")
        ad = ad[:1].lower() + ad[1:]
    return ad


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_ozellik_adlari_ekrandakiyle_ayni(kopya):
    ai = _govde(kopya, "ai")
    for anahtar, kucuk in _OZELLIK_ADLARI:
        ad = _ekrandaki_ad(_dil(kopya), anahtar, kucuk)
        assert ad in ai, (
            f"{kopya}: ekrandaki ad {ad!r} ({anahtar}) yapay zeka "
            f"bölümünde yok — politika ekranda olmayan bir adı sayıyor.")
    tum = " ".join(g for _, g in _politika_bolumleri(kopya))
    eski = [a for a in _ESKI_OZELLIK_ADLARI if a in tum]
    assert not eski, f"{kopya}: ekrandan kalkmış ad geri gelmiş {eski!r}"


#: Önbellek ömrü 30 günü bulan kişisel okuma -> politikadaki adı. ARB
#: anahtarı (ekrandaki ad) ya da, ekran başlığı cümle olduğu için
#: ("Rytho'nun ilişki okuması") elle yazılmış ad.
_UZUN_OMURLU_OKUMA = {
    "solar_return": ("solarReturnTitle", False),
    "natal": ("natalLockedTitle", True),
    "progressions": ("innerCalendarTitle", False),
    "relationship": {"tr": "ilişki okuması", "en": "relationship reading"},
}

#: `ttl_seconds=` ardından yalnız sayı ve çarpım, sonra çağrının geri
#: kalanı kapanış parantezine kadar (`feature="..."` orada). Sabit adıyla
#: verilen ömürler (`_HOROSCOPE_TTL`) eşleşmez ve bu doğru: burç yorumu
#: paylaşımlı, kişisel veri taşımıyor.
_TTL_CAGRISI = re.compile(r"ttl_seconds=([\d *]+?)\s*(,[^)]*)?\)", re.S)


def _kisisel_onbellek_omurleri() -> dict[str, float]:
    """`report_service`teki her önbellek ömrü, gün cinsinden, özellik
    adına göre (özelliksiz yazımlar `?` altında en büyüğüyle)."""
    kaynak = _kaynak("backend/services/report_service.py")
    omurler: dict[str, float] = {}
    for m in _TTL_CAGRISI.finditer(kaynak):
        saniye = 1
        for carpan in m.group(1).split("*"):
            saniye *= int(carpan)
        ozellik = re.search(r'feature="(\w+)"', m.group(2) or "")
        ad = ozellik.group(1) if ozellik else "?"
        omurler[ad] = max(omurler.get(ad, 0), saniye / 86400)
    return omurler


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_saklama_onbellek_suresi_koddaki_omurle_ayni(kopya):
    """"Yapay zeka yanıt önbelleği en fazla 30 gün" YANLIŞTI — ölçüldü
    (2026-10-23): Yıl Haritası 90 gün tutuluyor (`solar_return_report`,
    `ttl_seconds=90 * 24 * 3600`). Süre elle yazılmış bir sayıyla değil
    KODDAN okunarak karşılaştırılır: bir ömür uzatıldığı gün politika
    sessizce yalana dönmesin. 30 günü bulan her okuma adıyla ve süresiyle
    yazılı olmak zorunda; daha kısalar "diğerleri daha kısa" altında.
    """
    dil = _dil(kopya)
    omurler = _kisisel_onbellek_omurleri()
    assert omurler.get("solar_return"), (
        "ön koşul tutmuyor: report_service'te Yıl Haritası ömrü okunamadı "
        "— ölçüm kör, bu bekçi bir şey sınamıyor")
    saklama = _govde(kopya, "saklama")
    parcalar = re.split(r"[;.]", saklama)
    birim = "gün" if dil == "tr" else "days"
    for ozellik, gun in omurler.items():
        if gun < 30:
            continue
        etiket = _UZUN_OMURLU_OKUMA.get(ozellik)
        assert etiket is not None, (
            f"report_service: {ozellik!r} {gun:g} gün önbellekte kalıyor ama "
            f"politikada adı yok — _UZUN_OMURLU_OKUMA'ya ekle ve dört "
            f"kopyanın saklama bölümüne süresiyle yaz.")
        ad = (etiket[dil] if isinstance(etiket, dict)
              else _ekrandaki_ad(dil, *etiket))
        assert any(ad in p and f"{gun:g} {birim}" in p for p in parcalar), (
            f"{kopya}: saklama bölümü {ad!r} için {gun:g} {birim} demiyor "
            f"(koddaki ömür). Bölüm: {saklama!r}")
    kisa = "diğerleri daha kısa" if dil == "tr" else "all others shorter"
    assert kisa in saklama, f"{kopya}: {kisa!r} yok"
    for eski in ("en fazla 30 gün", "at most 30 days"):
        assert eski not in saklama, f"{kopya}: yanlış ömür geri geldi"


#: Yurt dışı aktarım cümlesi dört kopyada AYNI anlamda. Bir tur boyunca
#: uygulama TR "Türkiye ve AB dışına", uygulama EN "outside the EU and the
#: United Kingdom" (Türkiye'siz) diyordu, webde hiç yoktu.
_AKTARIM = {"tr": "Türkiye, Avrupa Birliği ve Birleşik Krallık dışına",
            "en": "outside Turkey, the European Union and the United "
                  "Kingdom"}

#: Ölçülmemiş yer iddiaları: Firestore'un ve Gemini'nin işleme yeri
#: depodan ölçülemiyor; ölçülen tek yer Cloud Run bölgesi. "Veriler
#: ağırlıklı olarak us-central1'de işlenir" bu yüzden kalktı.
_OLCULMEMIS_YER = ("ağırlıklı olarak", "primarily")


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_yurt_disi_aktarim_cumlesi_olculen_bolgeye_dayanir(kopya):
    govde = _govde(kopya, "aktarim")
    assert "Cloud Run" in govde and "us-central1" in govde, (
        f"{kopya}: aktarım cümlesi ölçülen bölgeyi (Cloud Run, "
        f"us-central1) anmıyor")
    assert _AKTARIM[_dil(kopya)] in govde, (
        f"{kopya}: yurt dışı aktarım cümlesi öteki kopyalardan ayrışmış — "
        f"beklenen {_AKTARIM[_dil(kopya)]!r}")
    yer = [y for y in _OLCULMEMIS_YER if y in govde]
    assert not yer, f"{kopya}: ölçülmemiş yer iddiası {yer!r}"
    # Dayanak: dağıtım betiğinin kendisi. Bölge değişirse burası düşer.
    assert '$REGION = "us-central1"' in _kaynak("infra/deploy-backend.ps1")


#: (yapay zeka listesindeki ifade, veri bölümündeki ifade).
_YASANAN_SEHIR = {
    "uygulama TR": ("doğum şehrin ve yaşadığın şehir", "yaşadığın şehri"),
    "web TR": ("doğum şehriniz ve yaşadığınız şehir", "yaşadığınız şehir"),
    "uygulama EN": ("your birth city and the city you live in",
                    "the city you live in"),
    "web EN": ("your birth city and the city you live in",
               "the city you live in"),
}


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_yasadigin_sehir_toplanan_ve_gonderilen_veri_olarak_yazili(kopya):
    """Yaşadığın şehir (`users/{uid}.residenceCity`) Profil'den yazılıyor,
    Yıl Haritası'nı o şehre kurduruyor ve "Yıl haritan {city} için kuruldu
    … Doğum yerin {birth_city}" beyanıyla İKİ şehir adı da isteme giriyor.
    Politika bunu hiçbir kopyada anmıyordu: ne toplanan veri olarak ne de
    yapay zekaya giden veri olarak.
    """
    ai_ifade, veri_ifade = _YASANAN_SEHIR[kopya]
    assert ai_ifade in _govde(kopya, "ai"), (
        f"{kopya}: yapay zeka listesi {ai_ifade!r} demiyor")
    assert veri_ifade in _govde(kopya, "dogum"), (
        f"{kopya}: doğum verisi bölümü yaşadığın şehri anmıyor")
    from services import prompts

    notu = prompts.get("tr").ASTRO_NOTES["sr_relocated"]
    assert "{city}" in notu and "{birth_city}" in notu, notu
    assert 'profil.get("residenceCity")' in _kaynak("backend/api/reports.py")
    assert "'residenceCity': _controller.text.trim()" in _kaynak(
        "apps/mobile/lib/features/profile/residence_dialog.dart")


#: Arkadaşın haritasından TÜREYEN veri — (ad yedeği, sinastri, çift
#: transiti).
_ARKADAS_VERISI = {
    "tr": ("görünen ad yoksa kullanıcı adı", "(sinastri)",
           "o gün ikinizin haritasına değen transitler"),
    "en": ("or their usernames if they have no display name", "(synastry)",
           "the transits touching either of your charts that day"),
}


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_arkadasin_haritasindan_tureyen_veri_yazili(kopya):
    """Politika arkadaştan yalnız "görünen adı ve burcu" gidiyor diyordu.
    Ölçülen (2026-10-23): ikili dinamik istemi iki haritanın açılarını
    adlarıyla ve o gün ikisine değen transitleri taşıyor (`dyad_reading`,
    `pair_transits=`); sohbet fısıltısı eksenleri, dayanak açısını ve
    günün çift transitlerini taşıyor (`whisper_for`); görünen ad yoksa
    KULLANICI ADI gidiyor (`friend_counterpart`, `circle_context`).
    """
    for ifade in _ARKADAS_VERISI[_dil(kopya)]:
        assert ifade in _govde(kopya, "ai"), (
            f"{kopya}: yapay zeka listesi {ifade!r} demiyor")
    sinastri = _kaynak("backend/services/synastry_service.py")
    assert 'friend.get("displayName") or friend.get("username")' in sinastri
    assert "gunluk = pair_transits(uid, other)" in sinastri
    assert ('arkadas.get("displayName") or arkadas.get("username")'
            in _kaynak("backend/services/circle_context.py"))
    assert ("pair_transits=pair_transits or p.PAIR_NO_TRANSITS"
            in _kaynak("backend/services/report_service.py"))


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_i_ching_soru_kapisi_amac_olarak_yazili(kopya):
    """I Ching sorusu çekimden ÖNCE ayrıca yapay zekaya gidiyor: uygun mu,
    sohbete mi yöneltilmiş, anlamsız mı (`iching_question_verdict`). Bu
    bir okuma üretmiyor, yani "metinleri üretmek için gönderilir" cümlesi
    onu kapsamıyordu — amaç listesinde ayrıca durmak zorunda."""
    ifade = "çekime uygun" if _dil(kopya) == "tr" else "suits a casting"
    assert ifade in _govde(kopya, "ai"), (
        f"{kopya}: I Ching soru kapısı amaç olarak yazılı değil")
    assert ('feature="iching_verdict"'
            in _kaynak("backend/services/report_service.py"))
    assert ("report_service.iching_question_verdict(req.question, lang)"
            in _kaynak("backend/api/reports.py"))


_SILME_SONRASI = {"tr": ("yeni gönderim olmaz", "yapay zeka hizmetlerine"),
                  "en": ("nothing new is sent", "AI services")}


@pytest.mark.parametrize("kopya", _KOPYA_ADLARI)
def test_hesap_silme_sonrasi_cumlesi_saglayicidan_bagimsiz(kopya):
    """"Hesabın silindiğinde … yeni gönderim olmaz" sağlayıcı adı taşımaz
    (K1): onay sağlayıcıdan bağımsız alındıysa geri alınması da öyle
    anlatılır. Cümlenin DOĞRULUĞU ayrıca arkadaşların çevre önbelleğinin
    hesap silmede temizlenmesine bağlı (backend tarafı) — orada silinen
    kişinin adı birkaç saat daha bir arkadaşın sohbet istemine girebilirdi.
    """
    capa, hedef = _SILME_SONRASI[_dil(kopya)]
    cumleler = [c for c in _cumleler(_govde(kopya, "ai")) if capa in c]
    assert len(cumleler) == 1, (
        f"{kopya}: hesap silme sonrasını anlatan cümle ({capa!r}) "
        f"{len(cumleler)} kez bulundu")
    cumle = cumleler[0]
    assert hedef in cumle, f"{kopya}: {hedef!r} yok: {cumle!r}"
    adlar = [ad for ad in _SAGLAYICI_ADLARI if ad in cumle]
    assert not adlar, f"{kopya}: cümle sağlayıcı adı taşıyor {adlar!r}"

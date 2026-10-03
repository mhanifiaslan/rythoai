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
    """
    if yol.endswith(".dart"):
        parca = re.sub(r"'[ \t]*\r?\n[ \t]*'", "", parca)
        parca = parca.replace("\\'", "'")
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

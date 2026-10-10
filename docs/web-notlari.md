# Web yüzeyi notları — gerekçeler HTML'den buraya taşındı

Bu belge `web/` altındaki herkese açık sayfaların **neden öyle** olduğunu
tutar. 2026-10-10'a kadar bu gerekçeler sayfaların kendi HTML yorumlarında
yaşıyordu ve "kaynağı görüntüle" diyen herkese açıktı: `web/index.html` 25
satırlık tek blokta dört `.dart`/`.py` dosya adı, `web/ortaklik.html` 19
blok / 60 satır, `web/r/index.html` bayat bir satır numarası. Metin
**kaybolmadı**, buraya taşındı; HTML'de yalnız tek satırlık işaretler kaldı
(`<!-- ---------- X ---------- -->` ya da bu belgeye işaret eden tek satır).
Bekçi: `backend/tests/test_web_yorum.py` — yorum tek satır olmak ve kaynak
dosyası / `:satır` anmamak zorunda.

> **Satır numaraları hakkında.** Eski yorumlardan biri `paywall_screen.dart:329`
> diyordu; ölçüldü (2026-10-10): o satır bir fayda satırının `Row` düzeni,
> kod girme alanının kullanılmama kararı 429'da. Satır taşınır, gerekçe
> kalır — bu belgede kaynak dosyalara satır değil **ad** ile işaret edilir.

Ölçüm tarihi: **2026-10-10**. Dal: `yuz-okuma-cihaz-usti-olcum`.

---

## 1. Ortak kabuk — `web/assets/rytho.css`

### CTA degradesi `--cta-gradient` (yeni) ve `--primary-gradient` ayrımı

Beyaz metin `--primary-gradient`in magenta ucunda (`#E64ACF`) **3,36:1**
ölçüldü; AA eşiği 4,5. Uygulama aynı ölçümle `ctaGradient`e geçmişti
(`RythoColors.ctaGradient`, `GoldButton` docstring'i, sahip kararı K5),
web geçmemişti. `--cta-gradient` o degradenin aynası: duraklar
`#7B2FF7 / #AE29FF / #D11DB6`, beyaz üstünde **5,85 / 4,60 / 4,60**.
Metin taşıyan her yüzey (`.buton`, mobil menü CTA'sı, hesap işlemi
düğmesi) bu degradeyi kullanır; süs yüzeyleri `--primary-gradient`te kalır.
Bekçi `test_web_stil.py::test_cta_degradesinin_her_duragi_AA` durakları
WCAG formülüyle **yeniden ölçer** ve düğmenin bu token'ı kullandığını da
ister (token doğru, düğme primary'ye dönmüş hâl yakalanır).

### CTA köşesi: web hap (999 px), uygulama 18 dp

`GoldButton` `BorderRadius.circular(18)` taşır; web `.buton` hap. Fark
bilinçli pazarlama yüzeyi kararı: web düğmesi mağaza rozetleriyle aynı
satırda duruyor ve hap o satırın dili. Birleştirilecekse iki taraf birden
değişir; `rytho.css`teki `.buton` yorumu bu kararı taşır.

### "Yakında" hapı — `.rozet.yakinda`

İki ana sayfada App Store "düğmesi" `href="#"` + `aria-disabled` bir `<a>`
idi. `aria-disabled` için tek satır CSS yoktu: görünüşte normal bir ikincil
düğme, tıklayınca sayfa başına atlıyordu. Davet sayfası aynı deseni daha
önce "çalışmayan düğme, çevrilmemiş metinden kötü ilk izlenim" diye
kaldırmıştı. Karar: bağlantı olmayan şey bağlantı gibi işaretlenmez —
`<span class="rozet yakinda">App Store · yakında</span>`, düğmeyle aynı
yükseklikte (ızgara hizası bozulmasın), kontur ve renk bilerek sönük.
Punto ve dolgu düğmeyle birebir (15 px / 13×22) ki yükseklik her yazı tipi
metriğinde eşit kalsın; tarayıcıda ölçüldü, ikisi de 51,25 px. Seçici
`.magaza .rozet.yakinda` — `.kahraman .rozet` aynı özgüllükte ve 620 px
altı bloğunda daha sonra geldiği için hap telefonda 11 px punto ve 20 px
alt boşluk alıyordu (ölçüldü, ilk yazımda tam bu oldu).
Bekçi: `test_web_seo.py::test_hicbir_sayfada_olu_baglanti_yok` (15 sayfada
`href="#"` sıfır **ve** hap tanımlı+kullanımda).

### Dokunma hedefleri 44 px

Hamburger 40×40 → 44×44, `.buton.kucuk` 40 → 44, `.dil-sec` pili 44'e
hizalandı (üç öğe aynı header satırında; biri 44 olup ötekiler kalınca
satır eğri durur). Hesap işlemi sayfasında "göster/gizle" düğmesi 12,5 px
metin + 6/8 px dolgu idi → `min-width/min-height: 44px`; şifre girdisi
15 → **16 px**, çünkü iOS Safari 16 px altındaki girdiye odaklanınca
sayfayı yakınlaştırır ve geri almaz. Bekçi:
`test_web_stil.py::test_dokunma_hedefleri_44px`.

### Yazı tipi bağlantısı render'ı kilitlemez

Google Fonts `<link>`'i düz `rel="stylesheet"` idi: CSS inene kadar ilk
boya bekliyor. Desen: `media="print" onload="this.media='all'"` + aynı
adresli `<noscript>` yedeği. `display=swap` zaten vardı, yani son görünüm
aynı; yalnız ilk boya öne çekildi. Görsel ajanın alanı (preload/img/video)
bilerek dokunulmadı; bu bağlantı CSS'tir. Bekçi:
`test_web_stil.py::test_yazi_tipi_baglantisi_renderi_kilitlemez`.

### Çıplak renk yok, satır içi stil yalnız `--i:N`

`rytho.css` 3. satırı "sayfalar çıplak renk yazmaz" diyordu; `:root` dışında
12 çıplak hex vardı. Yeni token'lar: `--ink-void` (hero penceresinin dibi,
mobil palette karşılığı yok), `--bezel-top/--bezel-bottom` (iki maket iki
ayrı ton taşıyordu, `#1A1024` / `#1D1229`, kanal başına ≤ 3/255 fark — tek
çifte indirildi), `--kure-fill`, `--band-gradient`, `--on-gradient`.
Satır içi stiller sınıfa döndü: `.bolum-bas(.sik/.dar)`, `.ham-veri`,
`.not-kucuk`, `.panel.vurgulu`, `.panel-not`, `.panel-metin`,
`.bolum-baslik.kucuk`, `.indir-bandi.tek`, `.sss .bolum-baslik`,
`footer .marka-blok p`. Üç bölüm-başı boşluğu (52/44/40) ölçülmüş bir ritim
**değil**, sayfalardan birebir taşındı; birleştirme ayrı bir karar.
`rgba(...)` literalleri bilerek kapsam dışı: 58 tanesi var, çoğu token'ın
alfa varyantı; hex bekçisi onları saymaz. Bekçi: `test_web_stil.py`
(`:root` dışı hex sıfır — rytho.css ve 15 sayfanın kendi CSS'i; `style=""`
yalnız `--i:N`).

### Dört küçük sayfa kabuğa geçti

Davet (`/i/`), ortak bağlantısı (`/r/`), hesap işlemi (`/auth/action/`) ve
404 `rytho.css`i hiç yüklemiyor, sistem fontuyla ve **eski paletle**
(`#EFE7DA` / `#F2C14E` / `#7B4BC9→#C8479B`) çiziliyordu; not metinleri
12–12,5 px ve zeminde 3,97:1 / 4,79:1. Hepsi artık kabuğa bağlı: renk
token'dan, düğme `.buton`, not metni ≥ 13 px ve `--parchment-dim`
(zeminde ≥ 7:1). Sayfa içi `<style>` yalnız düzen taşır. Davet ve 404'e
`.dil-sec` pili (`?lang=`) eklendi: otomatik dil seçimi yanlış düştüğünde
ziyaretçinin bir çıkışı olsun. `/r/` dışarıda: Android dalı anında
yönlendiriyor, pilin görüleceği an yok.

### `rytho.css?v=3`

Kabuğun bu turdaki değişiklikleri sınıf ekliyor; sayfalar `?v=3` ister.
Bu turda dokunulmayan iki sayfa (`web/en/partners.html`, `web/ortak/`)
`?v=2` ile kaldı — yeni sınıf kullanmadıkları için bozulmaz, yalnız önbellek
dolana kadar eski `.buton` degradesini çizer.

---

## 2. Ana sayfa — plan kartındaki bedel cümlesi (`web/index.html`, `web/en/index.html`)

Bedel cümlesi iki kez daraltıldı, ikisi de ölçümle:

1. Bedeli HARCAMADAN ÖNCE gösteren tek ekran İ Ching (`iching_tab` rozeti);
   derin raporlar, ikili okuma ve sohbet göstermiyor — yani "uygulama bedeli
   önceden gösterir" sınıfı bir cümle siteye **yazılamaz**. Yazılabilen tek
   şey mağaza ekranındaki bedel satırıdır (`token_store_screen` →
   `tokenCostsNote`, abone kapısının DIŞINDA, herkese görünür). Bu sınırı
   `test_honesty.py::TestJetonIddialari` tutuyor; AAB 50 yayıldığında bedel
   gösterimi değişirse önce o bekçi, sonra bu cümle güncellenir.
2. Bu gerekçenin eski hâli YANLIŞ kaldı ve düzeltildi (ölçüldü 2026-10-03):
   "o satır elle yazılmış bir l10n dizesi, `/wallet`in costs haritasından
   türemiyor" yazıyordu. Türüyor — satır `bedelSatiri(l10n.tokenCostsNote,
   cuzdan.costs)` ile kuruluyor, l10n dizesi yalnızca ŞABLON. Cümledeki
   "güncel" sıfatının geri YAZILMAMA gerekçesi başka ve hâlâ geçerli: sunucu
   ayrı dağıtılıyor, yani harita okunamazsa (ya da paket eskiyse) satır
   şablonun kendi sayılarıyla çizilir ve o sayılar bir backend dağıtımından
   sonra bayatlayabilir.
3. Tekrar okuma SÜRESİZ bedava DEĞİL: harcama yalnız önbellek kaçırıldığında
   işliyor (`report_service._cached_generate`) ve önbellek ömürlü (yüz okuma
   7, derin raporlar 30, yıl haritası 90 gün). Ömür dolunca yeniden ÜRETİM
   olur ve bedel düşer — bu yüzden cümle süre değil "yeni üretim" üzerine
   kuruldu.

İngilizce sayfa aynı gerekçeyi taşır; "current/up-to-date" sıfatı aynı
sebeple yazılmıyor.

---

## 3. Ortaklık sayfası (`web/ortaklik.html`)

İngilizce ikizi `web/en/partners.html` aynı tek satırlık işaretleri taşır;
gerekçeler yalnız burada (dalga kapanışında temizlendi, 2026-10-10).

**"pay" sözcüğü bilerek yok.** Türkçede yüzde payı çağrıştırır, oysa model
sabit tutar (`partners/{id}.rewardTry`) ve yüzde hesabı kodda kullanım dışı.
Paylaşım kartında gövde metni görünmediği için `<title>` ve açıklamadaki
adın tek başına doğru olması gerekiyor.

**x-default TR'yi gösterir.** Ürün TR-öncelikli; uygulamada da desteklenmeyen
dil `kSupportedLocales.first` = tr'ye düşüyor.

**Sayfaya hiçbir rakam yazılmaz.** Tutar ortak başına ayarlanıyor
(`partners/{id}.rewardTry`); sabit bir rakam farklı tutar anlaşılan ortağa
karşı yanlış beyan olurdu. Aynı gerekçeyle kazanç vaadi de yok: gelir,
getirilen kişilerin abone olup olmamasına bağlı.

**"Kullanıcıya kredi ya da indirim vermez" cümlesinin kapı bağı.** Cümlenin
niyet beyanı değil yapısal kısıt olması, sıfır dışı `bonusTokens` kabul
etmeyen bir kapıya bağlı: kod oluşturma ucu (`api/admin.py`, `CodeCreate`)
ve servis (`partner_service.create_code`). Alan veri modelinde uyuyor
durumda kalır — hedef "promo kredi vermiyoruz" değil, "veremiyoruz".
⚠️ ÖLÇÜLDÜ 2026-09-28: o kapı ağaçta HENÜZ YOKTU — uç `bonusTokens` için
`ge=0, le=5000` kabul ediyordu ve `partner_service.redeem` içindeki
`bonus > 0` dalı `wallet.credit_promo` çağırıyordu. Yani cümle o an yalnızca
niyet beyanıydı; aynı iddia kullanım şartlarının dört kopyasında da yazılı.
Okuyan ÖNCE ÖLÇSÜN: kapı inmişse cümle yapısaldır, hâlâ inmemişse
düzeltilecek yer sayfa değil, uçtur.

**"Kendi hesabın" maddesinin sınırı.** "Uç bunu reddeder" iddiası TEK bir
bağa dayanıyor: `partner_service.redeem`, `partners/{partnerId}.uid` alanını
kodu giren uid ile karşılaştırıp 403 `self_referral` atıyor (ölçüldü). SINIR:
`uid` alanı boş kalmış bir ortak kaydında karşılaştırma hiç eşleşmez ve kapı
sessizce geçilir — ortak kendi kodunu kendi hesabında kullanabilir. Bu yüzden
ortak oluştururken uid zorunlu tutulur; zorunluluk kalkarsa ya da uid'siz
eski kayıtlar varsa cümle o kayıtlar için geçersizdir. Ziyaretçi için gürültü
olduğundan sayfa metnine yazılmadı.

**Android koşulu bölümü saklanamaz.** Ortak iPhone kullanıcısına bağlantı
atıp hiçbir şey kazanmayınca sistemi bozuk sanar; asıl sebep Play Install
Referrer'ın iOS'ta bir dengi olmaması.

**Panonun adresi yazılmıyor.** Giriş arkasında duran özel bir yüzey ve hiçbir
yerden linklenmiyor (kendi sayfasındaki noindex + `firebase.json`daki
`/ortak/**` başlığı bu kararın kanıtı). ⚠️ Sayfadaki "girişle açılan bir
ortak panosu" maddesi o yüzeye bağlıdır — yayından kalkarsa madde ölçülmeyen
bir şeyi anlatır hâle gelir ve silinmelidir.

**Dil kuralı ortağa da geçer.** Ortağın ağzından çıkan cümle de bizim
beyanımız sayılır: mağaza metinlerindeki yasak dil kuralı
(`docs/store-launch.md`) aynen ortağa geçer.

---

## 4. Davet sayfası (`web/i/`)

**noindex.** `/i/**` yeniden yazımı sınırsız sayıda URL'yi bu tek sayfaya
düşürüyor; hepsi aynı başlığı taşıdığı için indekslenirlerse kopya içerik
olurlar. `robots.txt` bunu çözmez: `Disallow` taramayı durdurur,
indekslemeyi değil — Google noindex'i görebilmek için sayfayı çekebilmeli
(bekçi `test_web_seo.py`).

**Kuruluysa açılmaz.** Uygulama kuruluysa işletim sistemi bu sayfayı hiç
açmaz, doğrudan uygulamaya gider (Android App Links / iOS Universal Links).
Sayfa yalnızca uygulama KURULU DEĞİLSE görünür — yani yeni testçinin
gördüğü ilk yüzey.

**App Store düğmesi yok.** "App Store'dan indir" düğmesi hiçbir yere
gitmiyordu (`href="#"`) ve Android'de de görünüyordu. Çalışmayan bir
düğme, çevrilmemiş metinden daha kötü bir ilk izlenim.

**Dil.** Asıl sinyal `navigator.language`: davet bağlantısı (`inviteLinkFor`)
bilerek `?lang=` taşımıyor, çünkü GÖNDERENİN dili alıcının dili değil.
`?lang=` elle QA ve sayfadaki dil pili için okunuyor.

---

## 5. Ortak bağlantısı sayfası (`web/r/`)

**noindex.** Davet sayfasıyla aynı gerekçe.

**Kuruluysa açılmaz.** `AndroidManifest`teki `/r/` intent-filter; sayfa
yalnızca uygulama kurulu değilse görünür.

**Kod kullanıcıya hiç gösterilmez, bilinçli.** Uygulamada kod girme alanı
yok (`paywall_screen`, A2 kararı — "şimdilik kullanılmıyor"). Kodu ekranda
gösterip "kurulumdan sonra gir" demek, girilecek bir yer olmadığı için
düpedüz yanlış yönlendirme olurdu — sayfanın ilk hâli tam bunu yapıyordu.
Android'de kod mağaza bağlantısında (`referrer=utm_campaign`) taşınıyor;
kullanıcının yazması gerekmiyor.

**Mağaza düğmesi JS'siz de gerçek adrese gider.** `href="#"` idi ve JS
koşmazsa ölü kalıyordu; artık statik Play adresi, JS yalnız `referrer`
ekler.

JS içindeki gerekçeler (tıklama pingi, `sendBeacon` sırası) yerinde kaldı:
`test_web_seo.py::_r_sayfasi_kodu` o sırayı yorumları atarak ölçüyor.

---

## 6. Hesap işlemi sayfası (`web/auth/action/`)

Firebase Auth eylem sayfası (`mode=resetPassword | verifyEmail |
recoverEmail`). Firebase Console > Authentication > Templates > Action URL
bu sayfaya çevrilidir; e-postadaki bağlantı buraya
`?mode=...&oobCode=...&lang=...` ile gelir. Yapılandırma Hosting'in ayrılmış
URL'lerinden gelir (`/__/firebase/init.js`) — anahtar gömülmez; yönetim
paneliyle aynı desen. Şifre kuralı mobil `auth_service.validatePassword`
ile birebir aynıdır: en az 8 karakter + {harf, rakam, sembol}
sınıflarından en az ikisi.

**App Check.** Bu sayfanın tüm çağrıları (`verifyPasswordResetCode`,
`applyActionCode`, `confirmPasswordReset`) identitytoolkit'e gidiyor ve o
servis ZORLANIYOR (2026-09-26); App Check kimliği olmadan şifre sıfırlama
çalışmaz. Kurulum `web/assets/appcheck.js`.

**Kart GlassPanel reçetesi:** blur yok (tasarım sistemi kuralı; eski sayfa
`backdrop-filter: blur(6px)` çiziyordu).

---

## 7. 404

Marka tonunda; admin dahil eşleşmeyen HER yol buraya düşer ve sayfa hiçbir
yol hakkında bilgi vermez. Tek dilliydi — İngilizce tarayıcıdaki ziyaretçi
Türkçe bir 404 görüyor ve "ana sayfaya dön" onu Türkçe köke götürüyordu;
artık davet sayfasının dil deseniyle EN metin ve `/en/` kökü.

---

## 8. Bu turda dokunulmayan sayfa KALMADI (2026-10-10)

Dalga sırasında `web/en/partners.html` ve `web/ortak/index.html` başka
ajanın dosyasıydı ve bekçiler onları `xfail(strict=True)` ile taşıdı;
kapanışta ikisi de temizlendi, xfail sözlükleri boşaltıldı (mekanizma
duruyor). Ölçülen borç şuydu: EN ortaklık sayfasında 7 çok satırlı yorum +
11 satır içi stil + kilitleyen font bağlantısı + `?v=2`; panoda 6 çok satırlı
yorum (üçü `.js` adı anıyor) + font bağlantısı + `?v=2`.

## 9. Ortak panosu (`web/ortak/`)

**noindex iki kemerli.** Sayfadaki `<meta name="robots">` ikinci kemer;
birincisi `firebase.json`'daki `/ortak/**` `X-Robots-Tag` başlığı (yönetim
paneliyle aynı girdi). Pano hiçbir yerden linklenmez, adres ortağa elden
verilir.

**Metinler `data-i18n` ile `ortak.js`'teki `SOZLUK`'tan dolar (tr/en).**
HTML'deki Türkçe, JS çalışmadan önceki tek kare; `lang` de JS'te seçilen dile
çekilir. Dil sırası: `?lang=` → `navigator.language` → tr. Ortak kaydında dil
alanı yok; elle QA `?lang=en` ile.

**Canlı gökyüzü.** `starfield.js` `#yildizlar`'ı bulur;
`prefers-reduced-motion`'da tek statik kare çizer.

**Atlama bağlantısı yalnız pano açıkken var.** Hedef `#pano-govde` giriş ya
da jenerik ekranda yoktur; bağlantı o anda gösterilse klavye kullanıcısı
Tab+Enter'da gizli bir öğeye atlar ve odak sayfanın başına düşer. `goster()`
bu yüzden bağlantıyı panoyla birlikte açıp kapatır.

**Jenerik görünüm claim'siz HERKESE.** Giriş yapmış hesabın ortak erişimi
olup olmadığını ele vermez (yönetim panelindeki sahte-404 deseninin aynısı).
Sayfanın VARLIĞINI gizlemez: çıkış yapan aynı adreste giriş kartını görür ve
`<title>` panoyu adıyla anıyor. `/api/v1/partners/me` 403 dönerse de buraya
düşülür.

**App Check sırası.** `identitytoolkit` zorlanıyor (2026-09-26); jetonsuz
giriş reddediliyor. App Check betiği `init.js`'den ÖNCE yüklenmez, SONRA
kurulur (`/assets/ry-auth.js`, örnek başına).

**429 toast'ı panonun dilinde.** `ry-api.js` kendi bastığı 429 uyarısında
`RY.hataMetni`'yi (varsa) kullanır; `ortak.js` dil bilen haritasını oraya
kaydeder, yönetim paneli kaydetmediği için modülün Türkçesini alır. Bekçi:
`backend/tests/test_web_ortak.py`.

## 10. Görseller (`tools/web_gorsel_optimize.py`)

Ana sayfa görselleri PNG'den WebP'ye (1x/2x `<picture>`), video
`preload="none"`, poster = hero WebP. Hero arka planı ≤980 px'te CSS'ten
okunuyor; `image-set(webp, png)` AYRI `background-image` bildirimiyle
(kısayola yazılsaydı anlamayan tarayıcı rengi de düşürürdü) ve mobil preload
aynı WebP'yi gösteriyor — ikisini `test_web_varlik_butcesi` bağlar. PNG'ler
kayıplı küçültülmedi (256 renk kuantizasyonu nebulayı görünür lekeliyor,
ölçüldü); hero PNG yalnız kayıpsız sıkıştırıldı. Köken damgası WebP EXIF'inde;
ekran görüntüsü yeniden yakalanınca araç yeniden koşulur, yoksa bekçi kırmızı.
Bütçe: tek görsel ≤300 KB, sayfa ≤3 MB.

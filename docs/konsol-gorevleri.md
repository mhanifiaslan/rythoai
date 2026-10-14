# Konsol görevleri — senin yapman gerekenler (Revize R9)

Bu dosya, Revize 2 turunda kodun DIŞINDA kalan ve konsollardan elle
yapılması gereken işlerin adım adım listesi. Her bölümün başında hangi
özelliğin buna bağlı olduğu yazıyor: yapılmadan o özellik üretimde
çalışmaz.

Sunucu tarafı hazır ve yayında: cüzdan uçları, webhook'un paket/iade
işleme sırası, tek cihaz kilidi, telefon eşleme, rehber eşleşmesi, sohbet
arşivi + gece 03:20 temizlik cron'u (`rytho-cleanup`) ve `aiCache` TTL
politikası kuruldu. Aşağıdakiler sende.

## 0. KAPALI TEST SIRASI (KT-turu, 2026-08-30) — buradan yürü

> **GÜNCELLEME (2026-09-15, kapalı test denetimi).** On boyutlu bir
> denetim koştu; 100 doğrulanmış bulgu çıktı. Kod, hukuk metinleri, web
> sitesi, izinler ve Firestore indeksleri düzeltildi ve dağıtıldı.
> **Sende iki YENİ zorunlu adım var (aşağıda 0a, 0b); −1 doğrulandı ve
> iş çıkarmıyor.** Ayrıntılı gerekçeler: bu turun commit'i.

**Her turda kod da dağıtılır.** §0 bir konsol listesidir ama kod tarafı
kendiliğinden canlıya çıkmaz. AAB üretmeden önce şu üçü koşulmuş olmalı,
bu sırayla: `firebase deploy --only firestore:rules,firestore:indexes` →
`infra/deploy-backend.ps1` → `firebase deploy --only hosting`. Doğrulama:
panel → Sistem → indeks yoklaması yeşil, `/health` 200, `/health/rag`
vector modda.

---

### −1. Panel yetkisi — **DOĞRULANDI, İŞ YOK (2026-09-15)**

`rhytoai` projesinde tek admin hesabı var ve doğru:
`{admin: true, role: owner}`. `role` claim'i olup `admin` olmayan
kullanıcı **sıfır**. Toplam 54 kullanıcı.

Gerekirse yeniden basma komutu (onay ister, "evet" yaz):

```
backend/.venv/Scripts/python tools/set_admin.py --email aslan.mh@gmail.com --role owner
```

Araç MEVCUT claim'leri korur; yalnız `admin` ve `role` ekler. Claim
çıkış/giriş sonrası ya da en geç 1 saatte geçerli olur.

> ⚠️ **Düzeltme.** 2026-09-14 denetiminde buraya "projede hiç yönetici
> yok, panelin her ucu 403 döner" diye yazılmıştı. **O ölçüm yanlıştı.**
> `firebase_admin` projesiz başlatılmış ve ADC'nin varsayılan projesine
> (`xanthixai`) düşülmüştü; okunan `role: super_admin` / `orgIds` /
> `orgRoles` claim'leri O projeye ait. Ders `arac-konumlari` notunda
> zaten yazılıydı ve yine de atlandı: **Firebase Admin SDK her zaman
> `options={"projectId": "rhytoai"}` ile başlatılır.**
>
> Yetki kapısındaki sıkılaştırma (rol tek başına yetki vermez) DURUYOR —
> gerekçesi artık gözlemlenmiş bir olay değil, savunma derinliği.

### 0-GÜVENLİK. Bot hesap akını — SENDE ÜÇ İŞ VAR (2026-09-15)

**Ne oldu.** Firebase Auth'ta 54 hesap vardı; 39'u bot. Desen belli:
`adsoyad.NNNNN@gmail.com` (üretilmiş İngilizce ad-soyad + 5 hane), hepsi
yalnız Google sağlayıcılı, hepsi açıldığı gün bir kez giriş yapmış.

**Nasıl girdiler.** Uygulamadan DEĞİL. Hiçbirinin Firestore profili yok;
sunucumuz her kimlikli istekte `users/{uid}` dokümanına dokunuyor, yani
API'mize bir kez bile gelselerdi kayıt düşerdi. Doğrudan Google'ın kimlik
ucuna vurmuşlar. Mümkün, çünkü:

| Ayar | Durumu (ölçüldü) |
|---|---|
| Android API anahtarı paket + SHA kısıtı | YOK |
| Browser anahtarı referrer kısıtı | YOK |
| İki anahtarda da `identitytoolkit` erişimi | AÇIK |
| App Check zorlaması | KAPALI |

⚠️ **Anahtar kısıtlaması burada tek başına yetmez:** Android kısıtı
paket + SHA-1 ile çalışır, ama SHA-1 parmak izimiz App Links için
`/.well-known/assetlinks.json` ile ZATEN yayında. Başlıklar taklit
edilebilir. Gerçek çözüm App Check.

**Kod tarafında yapıldı (1.15.8+43):** `firebase_app_check` eklendi,
`main.dart` açılışta Play Integrity ile etkinleştiriyor (debug'da debug
sağlayıcı). Token ÜRETİLİYOR ama henüz ZORUNLU değil — sıra bilinçli:
önce bu sürüm yayılır, sonra zorlama açılır. Ters sırada eski paketler
kilitlenirdi.

**39 bot hesap SİLİNDİ** (2026-09-15, kullanıcı onayıyla). Silmeden önce
her biri için üç şart yeniden okundu: kapalı + üretilmiş e-posta deseni +
yalnız Google sağlayıcı. Eleme sıfır, hata sıfır. Firestore'da verileri
zaten yoktu. Projede şimdi 15 hesap var, hepsi gerçek ve aktif.

#### Senin yapacakların

1. **App Check'i tanıt** — Firebase Console → App Check → Apps →
   Android uygulamasını seç → **Play Integrity** → Save.
2. **Zorlamayı AÇ, ama 1.15.8+43 testçilere ULAŞTIKTAN SONRA** —
   App Check → APIs → `Firebase Authentication` ve `Cloud Firestore`
   → Enforce. Erken açarsan eski paketi olan testçiler giremez.
3. **API anahtarlarını kısıtla** — Google Cloud Console → APIs &
   Services → Credentials:
   - *Android key (auto created by Firebase)* → Application
     restrictions → Android apps → paket `ai.rytho` + **iki SHA-1
     birden** (debug anahtarın VE Play App Signing SHA-1'i). Play
     SHA-1'ini unutursan mağazadan inen paket giriş yapamaz.
   - *Browser key (auto created by Firebase)* → HTTP referrers →
     `rytho.app/*`, `rhytoai.web.app/*`, `rhytoai.firebaseapp.com/*`.

Bot hesapları silmek istersen söyle; şu an yalnız kapalılar.
Geri alma listesi Claude'da duruyor.

### 0a. Firebase Auth istek günlüğünü AÇ

`monitoring.requestLogging` canlıda **boş**. SMS-turu planı bunu "turun
tek en önemli maddesi" diye işaretlemişti; yapılmamış. Kapalı testte bir
testçi "giriş yapamıyorum" ya da "SMS gelmiyor" derse yine kör kalırız —
geçen sefer teşhis bir oturum sürmüştü.

Firebase Console → Authentication → Settings → **User activity /
request logging** → aç. Doğrulama:
`gcloud logging read 'protoPayload.serviceName="identitytoolkit.googleapis.com"' --project=rhytoai`
artık satır döndürmeli (bugün sıfır dönüyor).

### 0b. Kurmaca test numarasını gözden geçir

Firebase Auth'ta `+905542732455` → sabit kod `356625` olarak kayıtlı bir
**kurmaca** numara var. O numaraya ASLA gerçek SMS gitmez. Senin test
numaran değilse SİL — bir testçinin eline geçerse "kod gelmiyor" der ve
sebebi hiçbir yerde görünmez.

Ayrıca SMS bölge listesi yalnız **TR**. Testçilerden biri TR dışındaysa
hem konsoldaki listeyi hem `phone_verify_screen.dart:73`
`_smsBolgeleri` sabitini BİRLİKTE genişlet; yalnız birini değiştirmek
işe yaramaz.

---

SENİN sıran (sıra ÖNEMLİ — 1 yapılmadan AAB üretme):

> **Tıkla-tıkla sürüm (kullanıcı için):** aynı sıra, ekran adları ve
> kopyalanabilir değerlerle birlikte artifact olarak yayınlandı
> (2026-08-30). Bu bölüm mühendislik kaydıdır; oradaki metinler
> (mağaza açıklamaları, sürüm notu) buradan türetildi.

0. ~~Firebase'e Play imzası~~ **DOĞRULANDI — ZATEN TAM (2026-08-30):**
   `firebase apps:android:sha:list` ile canlı liste okundu; Play App
   Signing'in HEM SHA-1'i (9e12f5f1…) HEM SHA-256'sı (ffef27a1… —
   assetlinks'tekiyle birebir) kayıtlı (B1 onarımında, 2026-08-12).
   Denetimdeki "eksik" işareti yereldeki bayat google-services.json'dan
   kaynaklanan yanlış alarmdı — dosyayı yenilemek isteğe bağlı hijyen,
   işlev için gerekmez (mağaza paketinde Google girişi + SMS çalışıyor).
1. **Play↔RevenueCat servis kimliği DOĞRULA** (RevenueCat → Project
   settings → Apps → Service Credentials "valid" mi). B2'de kurulmuştu;
   yeniden yüklenirse **36 saate kadar** yayılma penceresi var —
   "Invalid credentials" o pencerede NORMALDİR, anahtar yenilenmez.
   Bu yüzden sıranın başında: saat işlerken diğer adımlar sürebilir.
2. **Ürünler** (§2): Play'de 3 tek-seferlik ürün + `rytho_plus_monthly`
   abonelik (base plan `monthly`, **OFFER/DENEME EKLENMEZ** — KT kararı:
   deneme sunucuda; 3+3 çakışması ve otomatik-ücretlendirme beklentisi
   yaratma). Hepsi **Activate** edilmeli, yoksa RevenueCat import'u boş
   döner. Not: Play'de "consumable" kutusu YOK — tüketilebilirlik
   istemci tarafında (RevenueCat SDK) hallediliyor.
   **KDV tuzağı:** Play girilen fiyata %20 ekler. Alıcının ₺59,99/
   ₺155,99/₺419,99 görmesi için girilecek: ₺49,99 / ₺129,99 / ₺349,99.
   Abonelikte ₺149,99 girilir → ₺179,99 görünür (B3 kararı).
3. **RevenueCat**: ürünleri import et → `RhytoAI Pro` yetkisine
   **yalnız** aboneliği bağla (jeton paketleri yetkisiz) → **OFFERING
   KUR**: `default` teklifi + `$rc_monthly` paketi + Current işaretle.
   **Offering olmadan paywall BOŞ açılır** — `subscription.dart:184`
   `Purchases.getOfferings()` → `offerings.current` okuyor. Jeton
   paketleri `getProducts(kTokenPackIds)` ile doğrudan çekiliyor,
   onlar için Offering GEREKMEZ (`wallet.dart:95-101`).
4. **Webhook** (§2c): kuruluysa yalnız **Environment** alanını kontrol
   et — sandbox DA seçili olmalı, yoksa kapalı testteki satın almalar
   hiç düşmez. Authorization = secret'ın HAM değeri (Bearer YOK;
   `billing.py:174` `compare_digest` birebir eşitlik arıyor).
5. **License testing**: Play Console **hesap seviyesi** → Settings →
   License testing → testçi e-postaları. Üç şart birden: hesap bu
   listede + kapalı test testçi listesinde + opt-in bağlantısını açmış.
   Yenileme hızlanır (aylık ≈ 5 dk, en fazla 6 yenileme).
6. **Uygulama içeriği** (Policy and programs → App content) — 10 form,
   kapalı testte hepsi ZORUNLU. Veri güvenliği `store-privacy-labels.md`
   §3'ten satır satır; **veri silme URL'si Data safety formunun İÇİNDE**
   (`…/legal/hesap-silme.html`); **AD_ID AYRI bir bölüm** → **HAYIR**
   (2026-09-18: izin manifest'ten kaldırıldı; "evet" demek mağaza
   listesine "reklam kimliği kullanıyor" yazdırırdı).
   **⚠️ "Reklam kimliği beyanı eksik" hatası izinsiz bundle'da da SÜRERSE**
   (2026-09-20'de ölçüldü, iki gün kaybettirdi): Play kontrolü kanaldaki
   TÜM aktif/askıdaki bundle'lara bakıyor, yalnız yeni yüklenene değil.
   Kanal durdurulup devam ettirilince AD_ID'li eski 43 önce canlanıyor,
   44 sonra yerine geçiyor; kontrol ikisini birden görüyor ve eski
   bundle silinemiyor. Kod suçlanmadan ÖNCE 10 saniyelik deney: formda
   **Evet** → kaydet. Evet'te AD_ID'siz sürüm yalnız uyarılır (atlanabilir),
   Hayır'da AD_ID'li bundle varsa engellenir; Evet'te gönder düğmesi
   açılıp Hayır'da hata dönüyorsa suçlu kanaldaki eski bundle'dır.
   Çıkış: Evet → gönder (yeni bundle eskiyi devre dışı bırakır) → sonra
   Hayır → gönder. Yine hata → başka kanalda (Dahili test) eski bundle
   aktif; **Sürüm → Uygulama paketi gezgini** hangi bundle'ın nerede
   durduğunu gösterir. Sürüm kodu 44 AD_ID'yi kaldıran commit'le aynı
   commit'te doğdu (`f8babfe`), yani AD_ID'li bir 44 var olamaz; 43
   (`8e10294`) izni `firebase_analytics`'ten taşıyordu.
   Health apps formu herkese zorunlu
   (→ "sağlıkla ilgili değil"); hedef kitle 13+; reklam yok.
7. **Mağaza kaydı**: görseller (512 ikon · 1024×500 · ≥2 ekran
   görüntüsü, GERÇEK harita/gökyüzü verisiyle) + kısa/uzun açıklama
   (artifact'te hazır metin; "iyileştirir/tedavi/şifa" ve kesin kehanet
   dili YASAK).
8. **Kapalı test kanalı**: Test and release → Testing → Closed testing →
   Create track → AAB yükle → sürüm notu → Start rollout → testçi
   listesi → **opt-in bağlantısı** (yalnız sürüm Published olunca çıkar).
   **12 testçi / 14 gün kuralı:** 13 Kasım 2023 sonrası açılmış KİŞİSEL
   hesaplar için ÜRETİME çıkış şartı (kapalı testi engellemez) — testçi
   listesini 12+ kurmak baştan zaman kazandırır.
9. **Doğrulama**: ilk gerçek satın almada webhook'u panel → Sistem
   (Denetim izi) ve Ekonomi sekmesinden gör (test-raporu B2 kapanışı);
   senaryo 113-115'i koş. Yanlış ürün kimliği `billing.unknown_pack`
   olarak denetim izine düşer.
10. **Hukuk onayı** (bir hukukçuya metinler) + **Swiss Ephemeris lisans
    kararı** — kapalı test de dağıtımdır (production-checklist şartı).

---

## 1. Firebase: Telefon sağlayıcısını aç (R2 — SMS doğrulama)

**DURUM (2026-08-07): DÖRT ADIM DA TAMAMLANDI** — Phone sağlayıcısı
açık, SMS region policy'de Türkiye, Blaze aktif, **SHA-256 eklendi**
(debug anahtarı `4E:29:8B:F0:...:DF:70`; Phone Auth Android'de Play
Integrity doğrulaması için SHA-256 ister — yalnız SHA-1 yetmez).

Kalan işler:
- ~~Sihirbazın telefon adımını açmak~~ **YAPILDI (OT4, 1.12.0+28):**
  `RYTHO_PHONE_STEP` bayrağı silindi; adım herkese görünür ve "Sonra"
  ile atlanabilir.
- **Play'e yüklerken**: Play App Signing'in mağaza imza anahtarının
  SHA-256'sı da Firebase'e eklenmeli (Play Console → Setup → App
  integrity → App signing key certificate) — yoksa mağazadan inen
  sürümde SMS düşer (W10/yayın turu).
- İstersen **Phone numbers for testing** bölümüne kendi numaranı sabit
  bir kodla ekle — mağaza incelemesi için de işe yarar.

Not: SMS gönderimi Blaze planında ücretlidir (Türkiye ~0,01-0,05 USD/SMS).

## 1a. Firebase: SMS teşhisi (SMS-turu, 2026-09-08 canlı olayı)

**Olay:** bir kullanıcı kayıt sihirbazının telefon adımında SMS alamadı.
Ölçüldü (Cloud Monitoring): `SendVerificationCode` **200** döndü, SMS
`region TR / +90 / tier 2` olarak **faturalandı**, `blocked_sms_count`
**0**, kota aşımı yok, Blaze açık, App Check zorlanmıyor. Yani kopma
Google'dan SONRA — **operatör teslimatı**. Google teslim makbuzu
yayınlamıyor, o hop bizden görünmüyor.

Asıl sorun teşhisin ZOR olmasıydı. Sırasıyla:

- [ ] **Auth istek günlüğünü AÇ** — Firebase Console → Authentication →
      Settings → *User activity / request logging* (Identity Platform
      `monitoring.requestLogging`). **Şu an KAPALI**: Cloud Logging'de tek
      satır auth kaydı yok, teşhis Monitoring metriklerinden dolaylı
      yapıldı. Açıldıktan sonra doğrula:
      `gcloud logging read 'protoPayload.serviceName="identitytoolkit.googleapis.com"' --project=rhytoai`
      artık satır dönmeli. **Bu listedeki en yüksek kaldıraçlı madde.**
- [ ] **Test numarasını gözden geçir** — Authentication → Sign-in method →
      Phone → *Phone numbers for testing*: `+905542732455` → `356625`
      kayıtlı. Gerçek görünümlü bir TR numarası; o numaraya **asla SMS
      gitmez**. Seninse kalsın, değilse sil.
- [ ] **SMS bölge listesi kararı** — şu an `allowlistOnly: ["TR"]`.
      Uygulamadaki ülke seçici tüm dünyayı sunuyordu; istemciye
      `_smsBolgeleri = {'TR'}` kapısı kondu (boşa gönderim + boşa ücret
      olmasın). **Listeyi konsolda genişletirsen `phone_verify_screen.dart`
      içindeki kümeyi de güncelle** — iki yer aynı gerçeği söylemeli.
- [ ] **(İsteğe bağlı)** Daha çok ülkeye açılmadan önce reCAPTCHA
      Enterprise'ı etkinleştir (SMS toll-fraud koruması). Şu an kapalı.

⚠️ `gcloud config` aktif projesi **`xanthixai`** — telefon/SMS ile ilgili
her komutta `--project=rhytoai` şart, yoksa sessizce yanlış projeye
bakılır.

Kod tarafında kapatılanlar (aynı tur): tekrar gönderme jetonu artık
saklanıyor ve 60 sn geri sayımlı "Kodu tekrar gönder" düğmesi var
(eskiden tek çare "numarayı değiştir"di — o YENİ doğrulama başlatır ve
Firebase'in kötüye kullanım korumasını tetikler); `verifyPhoneNumber`
try/catch'e alındı (sonsuz spinner); `00532…` gibi girişler artık doğru
derleniyor; her deneme maskeli olarak `phoneAttempts`'e yazılıp panelde
Kullanıcı 360'ta görünüyor.

## 1b. Firebase: e-posta şablon dili (OT2 — şifre sıfırlama)

Kod tarafı hazır (1.12.0+28): uygulama `setLanguageCode` ile Firebase'e
kullanıcının dilini bildiriyor ve şifre panosu gerçek hataları
gösteriyor. Konsolda ELLE doğrulanacak tek şey:

- Firebase Console → Authentication → Templates → **Password reset**
  (ve **Email address verification**): şablonların Türkçe sürümü var mı,
  gönderen adı "Rytho" mu bak; gerekirse şablon metnini Türkçeleştir.
  `setLanguageCode` yalnız Firebase'in HAZIR dil şablonları arasından
  seçim yapar — özel metin yazdıysan dil başına ayrı düzenlenir.

## 1c. Firebase: e-posta eylem URL'i → markalı sayfa (ŞS — şifre sayfası)

**DURUM: BEKLİYOR — alan adı alınınca yapılacak (kullanıcı kararı,
2026-08-29).** Alan adı alındığı gün sıra: Customize domain → DNS
doğrulaması → aşağıdaki 1-2. adımlar.

Kod tarafı hazır ve YAYINDA: `https://rhytoai.web.app/auth/action`
markalı eylem sayfası deploy edildi (şifre + tekrar, canlı kural
listesi, mobil `validatePassword` ile birebir aynı politika, TR/EN,
`verifyEmail`/`recoverEmail` modları da karşılanıyor). Bağlantının
Firebase'in varsayılan `rhytoai.firebaseapp.com` sayfası yerine BURAYA
düşmesi için konsolda TEK elle adım gerekiyor (CLI/API'den yapılamıyor):

**ENGEL TESPİT EDİLDİ (2026-08-29):** hem konsol ("An error occurred
updating action URL") hem Identity Toolkit API'si
(`PATCH .../config?updateMask=notification.sendEmail.callbackUri`)
aynı sunucu hatasını veriyor: **`EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED`
(400)**. Bu, Firebase'in kimlik-avı önleme kısıtı: e-posta şablonu
özelleştirmesi (Action URL dahil) alan adı sahipliği kanıtlanmadan
bu projede kapalı. Belgelenmemiş; hata koduyla ölçüldü.

Kilidi açan yol: **Templates → kalem → "Customize domain"** akışıyla
kendi alan adını DNS kayıtlarıyla (TXT/CNAME) doğrulamak (≤24 saat).
Alan adı henüz yok (W10'da zaten planlıydı); alınıp doğrulanınca:

1. Templates → Password reset → **Customize action URL** →
   `https://rhytoai.web.app/auth/action` → Save. (Tüm şablonlara
   birden uygulanır; `mode`/`oobCode`/`lang` parametrelerini Firebase
   ekler.) Konsol yine reddederse API komutu bu dosyanın geçmişinde.
2. Doğrulama: "Şifremi unuttum" e-postasındaki bağlantı
   `rhytoai.web.app/auth/action` açmalı — iki şifre alanı + Rytho
   tasarımı (test-raporu senaryo 109).

Alternatif (paralel yürütülebilir): Firebase Support'a talep —
proje `rhytoai`, Blaze, hata kodu `EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED`,
istenen Action URL. Bu adım yapılana kadar eski `firebaseapp.com`
tek-input sayfası görünmeye devam eder (akış ÇALIŞIYOR — kilit yalnız
görünüm/güven tarafında). Markalı sayfa yayında ve hazır bekliyor.

## 2. RevenueCat: 3 token paketi + entitlement adı (R1 — token ekonomisi)

Yapılmadan: Token mağazası ekranı paketleri listeleyemez ("ürün
bulunamadı") ve satın alma yapılamaz. Sunucudaki miktarlar SABİT:
`small=50 · medium=100 · large=200` kredi (2026-10-14; eski 100/300/1000) — mağazadaki ürün kimlikleri
birebir şu olmalı:

    rytho_tokens_small
    rytho_tokens_medium
    rytho_tokens_large

### 2a. Play Console

1. play.google.com/console → uygulama → **Para kazanma → Ürünler →
   Uygulama içi ürünler → Ürün oluştur**.
2. Ürün kimliği: `rytho_tokens_small` · ad: **"50 AI Kredisi"** ·
   fiyat: ₺80 (2026-10-14).
3. Aynısını `rytho_tokens_medium` ("100 AI Kredisi", ₺140) ve
   `rytho_tokens_large` ("200 AI Kredisi", ₺250) için tekrarla.
   ⚠️ **"Token"/"Jeton" YAZILMAZ** — kullanıcıya gösterilen sözlükten
   R2-F2 kararıyla çıkarıldı, uygulama "AI kredisi" diyor. Ad alanı
   makbuza basılıyor ve satın alma kaydında kalan tek metin odur;
   ayrıca paket kimliği tanınmazsa `product.title` uygulamanın İÇİNDE
   görünüyor. Bu belge bir tur boyunca "100 Token" yazdırıyordu,
   `docs/store-launch.md` ise aynı alana "100 AI Kredisi" — iki belge
   aynı Console alanına iki ayrı metin yazdırıyordu. Dört ürünün TAM
   adı (TR+EN) kanonik olarak `docs/store-launch.md`'deki tabloda.
4. Üçünü de **Etkinleştir**.

### 2b. App Store Connect

1. appstoreconnect.apple.com → uygulama → **Uygulama İçi Satın Almalar**.
2. **+ → Sarf Edilebilir (Consumable)** — Product ID'ler yukarıdakiyle
   BİREBİR aynı olmalı. Üç ürünü de oluştur, fiyat basamaklarını seç,
   yerelleştirilmiş ad/açıklama gir.

### 2c. RevenueCat paneli

1. app.revenuecat.com → proje → **Products** → **+ New** ile üç ürünü de
   ekle ve ilgili mağaza ürünlerine bağla.
2. Bu üç ürünü HİÇBİR entitlement'a BAĞLAMA: bunlar aboneliğe değil
   cüzdana gidiyor; krediyi webhook'taki `NON_RENEWING_PURCHASE` olayı
   ürün kimliğinden veriyor.
3. **Entitlement kimliği: `RhytoAI Pro`** (M1'de ÇÖZÜLDÜ, 2026-08-07):
   mobil kodun varsayılanı panele hizalandı — dart-define'sız derleme
   de artık `RhytoAI Pro` yetkisine bakar. Panelde kimliği DEĞİŞTİRME;
   abonelik ürünü (`rytho_plus_monthly`) bu entitlement'a bağlanır.
4. **Webhook** (kuruluysa atla): Project settings → Integrations →
   Webhooks → URL:
   `https://rytho-backend-770582338651.us-central1.run.app/api/v1/billing/revenuecat`
   Authorization başlığına Secret Manager'daki
   `REVENUECAT_WEBHOOK_SECRET` değerini yaz.

## 3. Gerçek RevenueCat API anahtarları (#17 — yayın öncesi şart)

`dart_defines.local.json` hâlâ `test_` anahtarları taşıyorsa gerçek satın
alma çalışmaz:

1. RevenueCat → **Project settings → API keys**.
2. **Public app-specific API keys** bölümünden Google (goog_...) ve
   Apple (appl_...) anahtarlarını kopyala.
3. `apps/mobile/dart_defines.local.json` içinde
   `REVENUECAT_ANDROID_KEY` ve `REVENUECAT_IOS_KEY` değerlerini değiştir.
   (Dosya gitignore'da; anahtarlar repoya girmez.)

## 3b. Test kilidi: RYTHO_FORCE_PLUS — **KALDIRILDI (2026-08-07, M3)**

R10'da verilen `RYTHO_FORCE_PLUS=1` üretimden kaldırıldı (rev 00046):
`/billing/status` artık GERÇEK abonelik durumunu döner; paywall gerçek
haliyle görünür. Test hesabına Rytho+ gerektiğinde yol: Play lisanslı
test hesabıyla ücretsiz satın alma (iç test kanalı).

Tekrar gerekirse (yalnız geçici test için):
`gcloud run services update rytho-backend --region us-central1
--project rhytoai --update-env-vars RYTHO_FORCE_PLUS=1` — ama bir
sonraki `deploy-backend.ps1` çalışması bunu sessizce siler (betikteki
--set-env-vars uyarısına bak).

~~Kapanış listesinde kalan: `RYTHO_TOKENS_ENFORCE` hâlâ 0~~ —
**AÇILDI (K5, 2026-08-13).** `infra/deploy-backend.ps1:98`
`--set-env-vars` satırında kalıcı olarak `RYTHO_TOKENS_ENFORCE=1`;
canlı Cloud Run ortamında da doğrulandı (2026-09-14). Jeton harcaması
gerçekten uygulanıyor: bakiye yetmezse 402 + `X-Paywall-Reason: tokens`.

## 3c. Web sitesi + gizli admin paneli (W0–W9 ile kuruldu)

- **Tanıtım sitesi:** https://rhytoai.web.app (TR) + /en/ (EN). Hukuki
  metinler: /legal/gizlilik.html · /legal/kullanim.html (+ EN) — mağaza
  formlarına bu URL'ler verilecek. **Yayın öncesi hukuk metinlerine insan
  onayı gerekiyor** (mühendislik taslağı).
- **Admin paneli:** https://rhytoai.web.app/rytho-admin — sitede link YOK,
  arama motorlarına kapalı. Google ile girilir; yetki `admin:true` custom
  claim'inden gelir (aslan.mh@gmail.com'a basıldı). Yeni admin eklemek:
  `backend/.venv/Scripts/python tools/set_admin.py --email <eposta>`
  (claim ≤1 saat / çıkış-giriş sonrası yansır).
  **TUZAK (2026-08-29'da yaşandı):** claim Firebase Auth KULLANICI
  kaydında yaşar — mobilde "Hesabı sil" testi yapıp hesabı yeniden
  kurarsan claim SİLİNİR ve panel seni sahte-404'e atar ("giriş
  yapamıyorum" gibi görünür). Çözüm: set_admin.py ile yeniden bas.
- **Roller (AD1, Panel v3):** claim artık `{admin:true, role:'owner'|'support'}`.
  `role` taşımayan eski `admin:true` sunucuda owner sayılır (geçiş) —
  yine de bir kez yeniden bas:
  `backend/.venv/Scripts/python tools/set_admin.py --email aslan.mh@gmail.com --role owner`
  Destek personeli: `... --role support` (okur; kredi, cihaz kilidi,
  auth-link, bildirim provası/kendine test yazar). Owner-only: sil, devre
  dışı, sürüm eşiği, ortak yazımları, CSV dışa aktarım, yeniden hesapla,
  duyuru, elle "Topla". `--revoke` iki claim'i de kaldırır. Yerelde
  destek kapılarını denemek: `RYTHO_DEV_ADMIN=1 RYTHO_DEV_ROLE=support`.
  Rol teyidi: `GET /api/v1/admin/me` → `{uid, email, role}`. Admin
  çağrıları artık ayrı kotada (240/dk, `/admin/collect` muaf).
- **`RYTHO_SUB_PRICES_USD` (AD7, Cloud Run env):** MRR hesabı ürün
  fiyatını mağazadan değil buradan okur (RevenueCat aylık fiyat raporu
  elle). JSON sözlük, `productId → aylık USD`; örnek:
  `RYTHO_SUB_PRICES_USD={"rytho_plus_monthly":4.99,"rytho_plus_yearly":3.33}`
  (yıllık ürün 12'ye bölünmüş aylık karşılığıyla yazılır). Boşsa MRR 0
  görünür — panelde "fiyat tablosu yok" uyarısı. `infra/deploy-backend.ps1`
  env listesine eklenir; değişince yeniden deploy gerekir.
- **`RYTHO_STORAGE_BUCKET` (2026-09-18, normalde GEREKMEZ):** hesap silme
  artık Cloud Storage'daki `avatars/{uid}/` önekini de temizliyor — daha
  önce profil fotoğrafı kovada kalıyordu ve `infra/storage.rules` gereği
  girişli her kullanıcı onu okuyabiliyordu. Kova adı AÇIKÇA veriliyor
  çünkü uygulama `storageBucket` seçeneği olmadan başlatılıyor; varsayılan
  `{proje}.firebasestorage.app` = `rhytoai.firebasestorage.app` ve canlı
  kovayla birebir uyuşuyor, yani **elle ayar gerekmiyor.** Kova bir gün
  taşınır ya da yeniden adlandırılırsa bu env'i ver; verilmezse silme
  fotoğrafı atlar (log'da "Bulut depolama dosyalari silinemedi" uyarısı
  görünür) ama kimlik silme YİNE tamamlanır.
- **Denetim izi fail-closed (AD3):** sil / devre dışı / eşik / hakediş
  ödemesi / dışa aktarım önce `adminAudit`'e `phase:intent` yazar;
  yazılamazsa **503 "Denetim izi yazılamadı; işlem yapılmadı."** ve eylem
  hiç yapılmaz. Panelde bu mesajı görürsen Firestore'a bak, tekrar dene.
- **Panel girişi OAuth adımı (AP onarımı, 2026-08-29):** Chrome COOP'u
  çapraz-origin popup'ı kırdığı için panel `authDomain` artık
  `rhytoai.web.app` (same-origin işleyici). Bunun çalışması için OAuth
  web istemcisine web.app işleyicisi eklendi (Console'dan elle —
  API'si yok): Cloud Console → APIs & Services → Credentials →
  "Web client (auto created by Google Service)" → Authorized redirect
  URIs'e `https://rhytoai.web.app/__/auth/handler`, Authorized
  JavaScript origins'e `https://rhytoai.web.app`. Yapılmazsa Google
  "Hata 400: redirect_uri_mismatch" verir. İleride ÖZEL alan adı
  bağlanırsa aynı adım o alan için tekrarlanır (app.js'te uygunluk
  bekçisi var — yalnız varsayılan Hosting alanlarında devrede).
- **Panel v2 (AP-turu, 2026-08-29):** baştan tasarlandı — yan menü + 6
  bölüm: Genel Bakış (KPI + eğriler), Kullanıcılar (aramalı liste +
  Kullanıcı 360: abonelik/cüzdan/kullanım/bildirim + zaman çizelgesi +
  ZORUNLU gerekçeli elle jeton kredisi), Ekonomi (gelir + jeton akışı +
  salt-okur bedel tablosu), AI Kullanımı (çağrı/token/maliyet
  telemetrisi), Ortaklar (+pasifleştir), Sistem (bildirim sağlığı +
  denetim izi). Yeni sunucu koleksiyonları: `usageEvents` (LLM çağrısı
  başına token/maliyet), `notifyRuns` (koşu sonuçları), `adminAudit`
  (yazan admin eylemleri), cüzdan defterine `debit`/`spend_refund`/
  `admin` kayıtları. Yeni uçlar `/admin/users*`, `/admin/usage`,
  `/admin/notify-runs`, `/admin/audit`. İndeks: usageEvents(uid,at)
  composite + ledger.at collection-group override (deploy edildi).
  Mahremiyet çizgisi: panel sohbet/hafıza İÇERİĞİNİ ve fcmToken
  değerini ASLA görmez — yalnız sayılar.
- **Panel v2.1 (AP2, aynı gün):** işletme K/Z katmanı + kullanıcı
  yönetimi. `/admin/economics` kullanıcı bazlı gelir/AI-maliyet/marj
  (marj = gelir × 0,85 − AI, "tahmini" etiketli); Genel Bakış'ta marj
  panosu + bugün şeridi + sayaç/çizim animasyonları; Ekonomi'de
  sıralanabilir K/Z tablosu. Yönetim eylemleri (hepsi gerekçeli +
  denetim izli): hesap devre dışı bırak/aç (`/admin/users/{uid}/disable`
  — token'lar revoke edilir), hesabı sil (`DELETE /admin/users/{uid}`,
  yazılı "SIL" onayı, mobil silme borusunun aynısı), şifre sıfırlama
  e-postası (istemci SDK). Kendi hesabında devre dışı/sil YASAK.
  Girişte e-posta+şifre formu da var (yetki yine claim'den).
- **İstatistikler:** her gece 23:40 UTC `rytho-stats` işi `adminStats/`
  dokümanını üretir; panel Genel Bakış'tan "Topla" ile elle de tetiklenir.
  Saat UTC gününün SONU: uç tarih almazsa BUGÜNÜ topluyor ve gün penceresi
  `[00:00, +1 gün)` olduğu için sabaha karşı koşan iş günün yalnız ilk
  saatlerini görürdü (DAU ~0, gelir/AI/jeton serileri boş) — üstelik
  `rollupStale` `generatedAt`e baktığı için doküman TAZE sayılıp zil de
  çalmıyordu. Bedeli günün son 20 dakikası: gelir/olay bölümleri Ekonomi'deki
  "Yeniden hesapla" ile geri doldurulabilir, DAU (`lastSeenDaily == gün`)
  KAPANMAZ.
- **Ortak kodları:** panel > Ortaklar: ortak ekle → kod üret (bonus jeton +
  kullanım limiti). Her hesapta TEK kod. Kod girildikten SONRAKİ
  satın almalar ortağa atfedilir; hakediş = atfedilen brüt × pay yüzdesi.
  **Mağaza fiyat indirimi buradan yapılamaz** — gerekiyorsa RevenueCat
  Offering / Play promo kodu konsoldan elle.
  **NOT (2026-08-07, A2):** mobil girişler KALDIRILDI (Profil satırı +
  paywall linki + dialog) — jeton-bonusu modeli şimdilik kullanılmıyor.
  Backend (`/billing/redeem-code`, partner_service) ve panel Ortaklar
  ekranı çalışır durumda DURUYOR; ileride farklı bir ödül/atıf modeli
  tasarlanırsa zemin hazır, yalnız mobil arayüz yeniden kurulur.
- **Deploy komutları:** site `firebase deploy --only hosting` · indeksler
  `firebase deploy --only firestore:indexes` · backend infra/deploy betiği.
- Alan adı bağlanınca: Hosting'e özel alan adı + deep_links.dart
  `kInviteHost` + AndroidManifest host + sitemap/canonical/OG URL'leri
  (bkz. plan W10).

## 4. Mağaza veri güvenliği formları (R2/R3/R4/R5 sonrası güncelleme)

Yapılmadan: form ile uygulamanın gerçek davranışı çelişir; iki mağaza da
bunu tespit ederse yayından kaldırma sebebi.

Tek doğru kaynak repo'da hazır: **`docs/store-privacy-labels.md`** —
satır satır bu dosyadan aktar. Bu turda DEĞİŞEN beyanlar:

- **Telefon numarası** (isteğe bağlı): App functionality; ham numara
  saklanmaz, yalnızca SHA-256 özeti.
- **Rehber**: yalnızca ayar AÇIKKEN, yalnızca numara özetleri, sunucuda
  SAKLANMAZ (geçici işleme). Ad/soyad okunmaz.
- **Sohbet arşivi**: konuşmalar artık hesapta saklanıyor (30 gün
  kullanılmayan silinir) — "Messages" beyanı güncellenmeli.
- **Galeriden yüz okuma**: görüntü toplanmıyor (cihazda işlenir,
  kopya silinir) — "Photos" beyanı YİNE GEREKMEZ; sadece açıklama
  metinlerinde galeri yolunun geçtiğinden emin ol.

Adımlar:
1. Play Console → **Politika → Uygulama içeriği → Veri güvenliği** →
   formu yukarıdaki değişikliklerle güncelle → gönder.
2. App Store Connect → **Uygulama Gizliliği** → aynı güncellemeler.

## 5. Kuruldu — dokunman gerekmiyor (kayıt için)

- `aiCache.expiresAt` Firestore TTL politikası (gcloud ile kuruldu;
  konsoldan görmek istersen: Firestore → TTL sekmesi).
- `rytho-cleanup` Cloud Scheduler işi (her gece 03:20 UTC, 30 günlük
  konuşma temizliği) — elle tetiklendi ve doğrulandı.
- `rytho-notify-daily` / `rytho-notify-streak` işleri güncellendi.
- Backend revizyon 00027 yayında; Firestore kuralları ve collection-group
  indeksi deploy edildi.

## 6. Zorunlu güncelleme anahtarı (PBZ, 1.15.0+35)

Kod tarafı hazır: eşik artık **sunucuda zorlanıyor** — `/api/v1/`
altındaki her istek `X-App-Build` başlığıyla eşiğe vurulur, küçükse
**426** + yerelleştirilmiş `detail` (`backend/core/app_gate.py`,
`AppGateMiddleware`). **Sıcak anahtar** Firestore `config/app.minBuild`
dokümanında yaşar; `RYTHO_MIN_BUILD` env'i deploy betiğinden ÇIKARILDI
(her deploy'da 0'a sıfırlanıyordu) ve artık yalnız isteğe bağlı TABAN:
etkin eşik = **max(env, doküman)**. Panel yazımı 60 sn içinde her
instance'a yansır (süreç içi memo), deploy gerektirmez, sonraki deploy
da silmez. Başlık göndermeyen istek **0 sayılır** (K7): eşik > 0 iken
açık oturumdaki ≤34 istemciler de ilk istekte kilitlenir — bilinçli.

**Sıra (BOZMA):** rules → backend → AAB 35 mağazada → eşik.

1. `firebase deploy --only firestore:rules` — `users.appBuild` (sunucu
   yazımlı sürüm aynası) `hasOnly` listesine girdi ve `appBuildDegismedi()`
   ile değişmez. Deploy edilmezse 35'in İLK kimlikli isteğinden sonra
   istemcinin tüm profil yazımları permission-denied ile düşer
   (faceConsent/platform vakasının aynısı — merge'de motor SONUÇ
   dokümana bakar).
2. `infra/deploy-backend.ps1` — kapı + `/api/v1/admin/min-build` uçları.
3. `infra/build-aab.ps1` → 1.15.0+35 Play'e. Başlığı gönderen İLK
   derleme bu; ≤34 hiç göndermiyor.
4. **35'i kendi cihazında aç ve bir kez giriş yap** — ayna
   `users/{uid}.appBuild = 35` ilk kimlikli istekte yazılır.
5. Eşik: **panel → Sistem → "Zorunlu güncelleme"** → yeni eşik + gerekçe
   → onay. Denetim izinde `config.min_build` satırı düşer.

**Sunucu > 0'ı ancak o sürümü canlı görmüşse kabul eder (K9):** `users`
içinde `appBuild ≥ eşik` olan en az bir kullanıcı yoksa **400**
"Eşiğin üstünde hiç kullanıcı görülmedi — önce yeni sürümü bir cihazda
aç." Yani 4. adım atlanırsa 5. adım reddedilir; yazım hatasıyla (350)
herkesi kilitlemek de böyle imkânsız. Sıfır (geri alma) her zaman kabul.

**Alternatif (panel düşükse) — Admin SDK, K9 doğrulamasını ATLAR,
sayıyı iki kez kontrol et:**

    backend/.venv/Scripts/python -c "import datetime as dt, firebase_admin; from firebase_admin import firestore; firebase_admin.initialize_app(options={'projectId': 'rhytoai'}); firestore.client().collection('config').document('app').set({'minBuild': 35, 'reason': 'elle (konsol)', 'updatedBy': 'konsol', 'updatedAt': dt.datetime.now(dt.timezone.utc)}, merge=True)"

`config/{doc}` için kural YOK = istemciye kapalı; Admin SDK kuralları
atladığı için yalnız sunucu/konsol okur-yazar. `gcloud config` aktif
projesi `xanthixai` — ADC'nin `rhytoai`'ye baktığından emin ol.

**Doğrulama (canlı, `B=https://rytho-backend-770582338651.us-central1.run.app`):**

    curl -si $B/api/v1/config/app
      → 200 · {"min_build": 35} · Cache-Control: no-store (kota + kapı muaf)
    curl -si -H "X-App-Build: 34" $B/api/v1/reports/iching/status
      → 426 · {"status":"error","code":"update_required","detail":"Rytho'nun bu sürümü…","min_build":35}
    curl -si -H "X-App-Build: 34" -H "Accept-Language: en" $B/api/v1/reports/iching/status
      → 426 · detail İngilizce
    curl -si -H "X-App-Build: 35" $B/api/v1/reports/iching/status
      → 401 (kapıdan GEÇTİ, token yok — kilit değil; token'la 200)
    curl -si $B/api/v1/reports/iching/status
      → 426 (başlıksız = 0; ≤34 bilerek kilitli)
    curl -si $B/health
      → 200 (/api/v1/ dışı — kapı dokunmaz, panel çağırıyor)

Panel → Sistem: "Etkin eşik" 35, "Env tabanı" 0, "Eşiğin altında
(canlı)" N, "Bilinmiyor (≤34)" M, sürüm tablosu; Denetim izinde
`config.min_build`. `deploy-backend.ps1` yeniden koşunca eşik KORUNUR
(betik artık env'i yazmıyor). Cihaz (35): uygulama açıkken eşik 36 →
ilk istekte ForceUpdateScreen, geri tuşu geçmez; uçak modu + bilinen
eşik → kilit; eşik 0 → normal (test-raporu 33/115/120-122).

**Geri alma:** panelden eşik **0** + gerekçe (K9 şartı yok, anında).
Env tabanı tanımlıysa o taban kalır — kontrol:
`gcloud run services describe rytho-backend --region us-central1 --project rhytoai --format "value(spec.template.spec.containers[0].env)"`;
kaldırmak için `--remove-env-vars RYTHO_MIN_BUILD` (deploy betiği artık
tanımlamadığı için bir sonraki deploy da siler).

## 7. Cihaz kilidi sıfırlama (TC-turu, 1.15.1+36)

Kilit artık **sunucu hakemli** ("son giriş kazanır", Firebase token'daki
`auth_time`): yeni cihazda giriş yapan abone soru görmeden çalışır; eski
cihaz ilk korumalı istekte "Hesabın başka bir cihazda açıldı" kapısını
görür ("Bu cihazda kullan" / "Çıkış yap"). Çıkış kaydı serbest bırakır
(`DELETE /device/claim`, yalnız sahipse). Kilit yalnız **ücretli** abonede;
3 günlük deneme muaf.

**Konsol işi yok — kaçış kapısı panelde:** kullanıcı kapıdan çıkamıyorsa
(eski sürüm istemci, bozuk cihaz saati vb.) Panel → Kullanıcılar → 360 →
"Cihaz kilidi" kartı → **Cihaz kilidini sıfırla** (`confirm`). Kayıt
silinir, bir sonraki korumalı isteği yapan cihaz sessizce sahiplenir;
Denetim izinde `device.release`. Kart kimliği maskeli gösterir (son 6).

**Doğrulama (canlı, `B` yukarıdaki gibi, `T` geçerli ID token):**

    curl -si -X DELETE -H "Authorization: Bearer $T" -H "X-Device-Id: baska" $B/api/v1/device/claim
      → 200 · {"status":"success","released":false}   (sahip değil — kayıt durur)
    curl -si -H "Authorization: Bearer $T" -H "X-Device-Id: baska" $B/api/v1/device/status
      → 200 · {"locked":true,"claimed":true,"this_device":false,"other":{"platform":"android","claimedAt":"…"}}

Firestore kuralı DEĞİŞMEDİ (`private/**` istemciye kapalı); doküman
`users/{uid}/private/device` — Admin SDK ile elle silmek de aynı etkiyi
verir, ama denetim izi düşmez; paneli kullan.

# Mac'e devir ve iOS başlangıcı

Bu belge, depoyu bir Mac'e taşıyıp iOS sürecini başlatmak içindir. Her
madde ya ölçülerek bulundu ya da bir kez zarar verdi. Windows makinesinde
**her şey çalışıyor**; buradaki listede yazanlar Mac'te *ek olarak* gereken
şeyler.

Ölçüm tarihi: **2026-09-26**, güncelleme **2026-10-22** (aşağıdaki
"Bugünkü durum" kutusu ve 4.10). Dal: `yuz-okuma-cihaz-usti-olcum`.

> **Bugünkü durum (2026-10-22, Windows'tan ölçüldü):**
> - Android **1.20.0+53** derlendi (AAB, 6 kapı OK). Play'de **açık test
>   (yalnız Türkiye)** incelemede; **üretim erişimi verildi** (2026-10-17),
>   üretim kanalı henüz açılmadı. Sürüm kodları 48/50/52 YANMIŞ; sıradaki
>   Android kodu **54**. iOS'un `CFBundleVersion`'ı Android'den bağımsızdır
>   ama `pubspec.yaml` `version` ikisini birden besler — iOS'ta numarayı
>   yükseltirken Android'in yanmış kodlarına dikkat.
> - Backend Cloud Run rev **00112-dtj**; istatistik özeti saatlik
>   (`rytho-stats`), Çevrem/geri kazanım bildirim işleri kurulu.
> - Gemini faturası **ön ödemeli**: bakiye sıfırlanırsa tüm AI anında durur
>   (CLAUDE.md "CANLI KESİNTİ 2").
> - Ortak panosu `rytho.app/affiliate/` (eski `/ortak/` 301), varsayılan dil EN.
> - iOS'ta yapılacak ilk ürün işi: **ortak (affiliate) bağlantısının iOS'ta
>   da sayılması** — bkz. **4.10**.

> **Mac durumu (2026-10-22, Mac'ten ölçüldü):**
> - Mac'in iOS/App Store işi (`ios-hazirlik`, 2026-09-26/27, 16 commit,
>   15'i push edilmemişti) bu dala **birleşti**: `8d6f67b`. U-kimlikli
>   kayıt `docs/ios-uyum-denetimi.md`'de (55 kayıt + birleşme notları).
>   Bu belgenin 4.2/4.4/4.8 maddeleri o işe göre güncellendi.
> - **U56:** Windows'un D3'te eklediği `app_settings` 8.0+ iOS'ta yalnız
>   Swift Package Manager destekliyor, depo ise U25 gereği CocoaPods'ta;
>   birleşmiş dal iOS için derlenmiyordu. Sahip kararıyla **7.0.0'a
>   sabitlendi**: iOS simülatör derlemesi geçti ve uygulama açıldı (giriş
>   ekranı, ölçüldü). ⚠️ **Android derlemesi 7.0.0 ile ÖLÇÜLMEDİ** — §6.
> - Bu Mac: Xcode 26.6 seçili, Flutter 3.44.7, CocoaPods 1.17.0. İmza
>   sertifikası **0**, bağlı iPhone **yok** (sahip: haftaya). `firebase`,
>   `gcloud`, `pwsh`, Java ve tam Android SDK **kurulu değil**.
> - 4.10 kodu hazır (`31ee208`): **deploy edilmedi, cihazda ölçülmedi.**
> - ⚠️ **Hosting deploy'u BEKLET** (hangi makineden olursa olsun). Birleşmiş
>   `web/legal/` gizlilik metni U06'nın onay ekranını anlatıyor ("uygulama
>   içinde ayrı ve açık izninizi isteriz"). Canlıdaki Android 1.20.0+53'te o
>   ekran YOK — onay ekranlı ilk paket (Android 54+ ya da iOS) yayınlanmadan
>   deploy edilirse politika canlı uygulama için yanlış beyan olur. Canlıda
>   ölçülen (2026-10-22): AASA hâlâ `TEAMID` + yalnız `/i/*`, gizlilik
>   sayfası 17 Ekim.
Uzak depo: `https://github.com/mhanifiaslan/rythoai.git`
(GitHub deposu `rhytoai` → `rythoai` olarak yeniden adlandırılmış; eski
adres hâlâ yönlendiriyor ama **yeni adresi kullan** — yönlendirme kalıcı
bir garanti değil ve `git push` her seferinde uyarı basıyor.)

---

## 1. Mac'e kurulacaklar

| Araç | Sürüm | Not |
|---|---|---|
| Xcode | **26.6** (17F113) | **Yalnız macOS**. Tam Xcode gerekir. **Xcode 27 derleyemiyor** (§7) — 26.6 yan yana kurulur ve `xcode-select` ona çevrilir |
| CocoaPods | güncel | `sudo gem install cocoapods` ya da `brew install cocoapods` |
| Flutter | **3.44.7 stable** (Dart 3.12.2) | `pubspec` `sdk: ^3.12.0`. Farklı minör sürüm kilit dosyasını oynatır |
| Python | **3.11 ŞART** | 3.12'de `pyswisseph` kurulmuyor. venv: `backend/.venv` |
| JDK | 17 | Android tarafını Mac'te de derleyeceksen |
| PowerShell | `brew install --cask powershell` | `infra/*.ps1` betikleri `pwsh` ile koşar |
| gcloud + firebase CLI | güncel | Her komutta `--project rhytoai` |

Xcode'u kurduktan sonra bir kez aç ve lisansı kabul et; aksi hâlde
`pod install` anlaşılmaz bir hatayla düşer.

---

## 2. Git'in TAŞIMADIĞI dosyalar — elle kopyalanır

Bunlar `.gitignore`'da. Biri eksikken derleme **sessizce** bozuk çıkar:
komut başarılı olur, kusur ancak cihazda ya da mağazada görülür.

| Dosya | Eksikse ne olur |
|---|---|
| `apps/mobile/dart_defines.local.json` | Paket RevenueCat anahtarsız çıkar; cihazda **tüm satın almalar** "kullanılamıyor" der. **Derleme BAŞARILI görünür.** |
| `apps/mobile/android/key.properties` | Yayın imzası kurulmaz. İçindeki `storeFile` **mutlak yol** — Mac'teki keystore yoluna göre düzeltilir |
| Keystore (`rytho-upload.jks`) | **Yeri doldurulamaz.** Kaybolursa uygulama bir daha güncellenemez. Güvenli bir yoldan taşı, e-postayla değil |
| `backend/.env` | Yerel backend anahtarları. Örneği git'te: `backend/.env.example` |

`google-services.json` git'te **var** — onu taşıma. Segmentasyon modeli
(16 MB) git'te yok ama tek komutla iner:
`apps/mobile/scripts/fetch_models.ps1` (pwsh ile). **O dosya yokken
`flutter test` hiç başlamaz** ("Failed to build asset bundle").

`dart_defines.local.json` taşındıktan sonra **içindeki
`REVENUECAT_IOS_KEY` değerini kontrol et** — şu an `test_` önekli, yani
RevenueCat Test Store anahtarı, App Store anahtarı değil (madde 6.7).

---

## 3. Klonlama ve ilk koşu

```bash
git clone https://github.com/mhanifiaslan/rythoai.git
cd rythoai
git checkout yuz-okuma-cihaz-usti-olcum
```

Sonra 2. bölümdeki dosyaları yerlerine koy. Ardından:

```bash
cd apps/mobile
flutter pub get
pwsh scripts/fetch_models.ps1     # segmentasyon modeli (16 MB)
flutter analyze                   # beklenen: No issues found
flutter test                      # beklenen (2026-10-19): 1528 test geçer
```

Backend:

```bash
cd backend
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m pytest -q     # beklenen (2026-10-19): 2756 passed, 2 skipped
```

**Mac'te ölçülen (2026-10-22, Apple Silicon):** saf `33bb9f4`'te
`flutter test` **1528/1528**; `pytest` **2755 geçti, 2 atlandı, 1 kaldı** —
`test_rag_coverage[tr-family-Babamla…]`: kelime modunda en yüksek skorda 10
parça EŞİTTİ ve üç sonuç NumPy'nin işlemci mimarisine bağlı eşitlik bozmasıyla
seçiliyordu (x86_64'te geçiyordu). Birleşme (`8d6f67b`) sonrası: `flutter
test` **1668/1668**, `pytest` **2795 + 2 atlandı + aynı 1**. Eşitlik artık
platformdan bağımsız bozuluyor (`4c64335`, rag-esitlik) ve U17 de girdi
(`b061ec0`): **`flutter test` 1707/1707, `pytest` 2831 geçti + 2 atlandı, 0
kaldı** (2026-10-22, Mac). `flutter analyze` Mac'te `build/**` dışlanmazsa
864 sahte hata sayar (§7; dışlama birleşmeyle geldi).

Betikler macOS'a hazır (ölçüldü): `infra/deploy-backend.ps1` venv düzenini
iki platformda da buluyor (`Scripts/python.exe` → `bin/python`),
`infra/build-aab.ps1` flutter'ı önce PATH'ten arıyor. Ama
`infra/store-screenshots.py`, `infra/store-graphics.py` ve `ads/` altındaki
betikler **sabit Windows yolu taşıyor** (`D:\...`, `C:\Windows\Fonts`,
ffmpeg yolu) — bunlar mağaza görseli ve reklam üretimi içindir, derleme
yolunda değildir; Mac'te kullanılacaksa yolları parametreleştirilmeli.

---

## 4. iOS: sıralı yol haritası

Sıra **bağımlılık sırasıdır**, önem sırası değil. Her adım bir öncekini
gerektiriyor; atlanırsa sonraki adım anlaşılmaz bir hatayla düşer.

### 4.1 — Apple Developer Program üyeliği · **SEN**
Yıllık ücretli. Bunsuz ne imzalama ne TestFlight ne App Store Connect var.
Üyelikten çıkan **Team ID** (10 karakter) üç yerde birden lazım: Xcode
imzalama, `apple-app-site-association`, ve entitlements profili.

**Durum (2026-10-22):** Team ID **`292WJ9TP74`** depoda (pbxproj + AASA,
`c3dca0e`). Üyelik **ücretli ve etkin** (sahip teyidi, 2026-10-22) —
Associated Domains (Universal Link) ücretsiz kişisel takımda açılamazdı.

### 4.2 — Firebase'de iOS kaydı · ✅ **BİTTİ** (2026-09-26)

`ai.rytho` bundle'ıyla kaydedildi ve **`GoogleService-Info.plist` depoda**:
`apps/mobile/ios/Runner/GoogleService-Info.plist`. Android'in
`google-services.json`'ı da git'te — aynı düzen. Mac'te taşınacak bir şey
yok, `git pull` yeter.

✅ **Xcode hedefine EKLENDİ** (Mac, 2026-09-26). `project.pbxproj`
klasör-senkronlu grup kullanmadığı için (`objectVersion = 54`) diskte durmak
yetmiyordu; Runner'ın Copy Bundle Resources'ına CocoaPods'un `xcodeproj`
kütüphanesiyle eklendi. **Ölçüldü:** derlenen `Runner.app` içinde
`GoogleService-Info.plist` var ve `BUNDLE_ID = ai.rytho`.

Bunsuz uygulama **ilk karede çöker**: `main.dart:78` `Firebase.initializeApp()`
seçeneksiz çağrılıyor ve depoda `firebase_options.dart` yok, yani
yapılandırmanın tek kaynağı bu dosya.

**Bir kez yanlış kaydedildi ve bu öğretici bir kazaydı:** bundle `app.rytho`
girilmişti (`ai` yerine `app`). İnen plist de o kimliği taşıyordu ve
`FirebaseApp.configure()` uyuşmazlığı **hata değil uyarı** ile geçiyor —
yani uygulama "çalışıyor" görünürken App Check, Google girişi, push ve
Crashlytics tek tek sessizce bozulurdu. Kayıt silinip yeniden açıldı.
Bekçi: `backend/tests/test_ios_config.py` artık bundle kimliğini beş
dosyada birden bağlıyor.

### 4.3 — Google ile giriş · ✅ **BİTTİ** (2026-09-26)

`Info.plist`'e `CFBundleURLTypes` (REVERSED_CLIENT_ID) ve `GIDClientID`
eklendi; ikisi de `GoogleService-Info.plist`'ten **okunarak** yazıldı, elle
kopyalanmadı. URL şeması yalnız `Info.plist`'ten okunabiliyor — Dart'tan
verilemez; kayıtlı olmasaydı Google tarayıcıda oturumu açar ama uygulamaya
dönemezdi ve giriş yarıda kalırdı.

`main.dart:133`'teki `GoogleSignIn.instance.initialize(serverClientId: …)`
**değiştirilmedi**: eklenti (`google_sign_in_ios` 6.3.0,
`FLTGoogleSignInPlugin.m:22`) iOS istemci kimliğini doğrudan
`GoogleService-Info.plist`'ten okuyor, ayrıca `GIDClientID` de yazılı.

**iOS API anahtarı kısıtlandı:** bundle `ai.rytho`, 27 API hedefi korunarak.
Kayıt açılınca doğan anahtarın bundle listesi **boş** geliyordu — dün
Android ve Browser anahtarları için kapattığımız bot yolunun aynısı.

### 4.4 — İmzalama · ✅ **pbxproj'de** · **SEN (Xcode hesabı)**
✅ `c3dca0e` (2026-09-27): `DEVELOPMENT_TEAM = 292WJ9TP74` ve
`CODE_SIGN_STYLE = Automatic` altı yapılandırma girdisinde (ölçüldü
2026-10-22). **Kalan:** Xcode → Settings → Accounts'ta takımın Apple
kimliği. Bu Mac'te imza sertifikası **0** (`security find-identity -v -p
codesigning`, 2026-10-22); otomatik imza ilk cihaz derlemesinde sertifikayı
ve profili kendisi kurar — iPhone geldiğinde.

### 4.5 — Yetenekler (Capabilities) · **SEN (Xcode'da)**
Apple Developer portalında App ID üzerinde de **açık olmalı**, yalnız
entitlements dosyası yetmez:
- **Sign in with Apple** (App Store Guideline 4.8 gereği zorunlu)
- **Push Notifications**
- **Associated Domains**

Depo tarafı hazır: `Runner.entitlements` (Debug/Profile) ve
`RunnerRelease.entitlements` (Release) ikisi de yazıldı ve `pbxproj`
Release bloğu ikincisine bakıyor.

⚠️ İkisi **yalnız `aps-environment` değerinde** farklı: `development` ve
`production`. Bu ayrım bilinçli ve sessiz bir tuzağı kapatıyor — tek dosya
kullanılıp `development` kalsaydı üretim paketi **sandbox** APNs jetonu
alır, sunucu üretim APNs'ine gönderir ve bildirim hiçbir yere düşmezdi:
TestFlight'ta çalışır, mağazada ölür. Dosyalardan biri değişirse
**diğeri de aynı şekilde değişmeli**.

### 4.6 — APNs anahtarı · **SEN**
Apple Developer → Keys → yeni **APNs Auth Key** (.p8) oluştur, Firebase
Console → Project Settings → Cloud Messaging → iOS bölümüne yükle
(Key ID + Team ID ile birlikte). Bunsuz FCM iOS'a bildirim gönderemez.

### 4.7 — RevenueCat iOS anahtarı ve IAP ürünleri · **SEN**
`dart_defines.local.json`'daki `REVENUECAT_IOS_KEY` şu an
`test_...` önekli — **RevenueCat Test Store** anahtarı, satın almaları
simüle eder. Gerçek App Store anahtarı `appl_...` ile başlar.

App Store Connect'te ürünler **Play'dekilerden ayrı** oluşturulur. Kimlikler
kodda sabit, **değiştirme**:
`rytho_plus_monthly` · `rytho_tokens_small` · `rytho_tokens_medium` ·
`rytho_tokens_large`. Görünen adlar `docs/store-launch.md`'de tabloyla hazır.
RevenueCat'te abonelik `RhytoAI Pro` entitlement'ına bağlanır (paketler
bağlanmaz) — panel adıyla **birebir** aynı olmalı.

### 4.8 — `apple-app-site-association` · ✅ **depoda** (2026-09-27) · **yayın bekliyor**
`web/.well-known/apple-app-site-association` içinde
`"appID": "292WJ9TP74.ai.rytho"` — gerçek Team ID (Membership details'ten
sahip doğruladı; kayıt e-postasındaki Enrollment ID aynı biçimde ama
FARKLI bir şey). Aynı değer pbxproj'de `DEVELOPMENT_TEAM`; ikisinin
ayrışması `backend/tests/test_ios_config.py`'de bekçili. **Kalan:**
`firebase deploy --only hosting --project rhytoai` — sahibe SORULUR; bu
Mac'te `firebase` CLI yok. Yayın olmadan davet bağlantıları iOS'ta
uygulamayı açmaz, tarayıcıya düşer.

Entitlements tarafı hazır: `applinks:rytho.app` **ve**
`applinks:rhytoai.web.app` ikisi de yazılı (sahadaki eski davet bağlantıları
ikincisini taşıyor).

✅ `/r/*` (ortak bağlantısı) da eklendi: `"paths": ["/i/*", "/r/*"]`
(`31ee208`, 4.10). Bekçi `test_aasa_android_app_links_yollarini_kapsiyor`:
AndroidManifest'in her App Links yol öneki AASA'da da olmalı — eski boşluk
tam bu ayrışmaydı ve hiçbir test kırmızı değildi.

### 4.9 — App Store Connect kaydı ve `APPSTORE_APP_ID` · **SEN**
Kayıt açılınca **sayısal uygulama kimliği** doğar. Onu
`dart_defines.local.json`'a `APPSTORE_APP_ID` olarak yaz.

Boş bırakılırsa zorunlu güncelleme ekranı iOS'ta mağaza düğmesi
**göstermez** ve dürüst bir mesaj verir. Bu bilinçli: uydurma bir kimlikle
kurulan bağlantı mağazada "uygulama bulunamadı" açar ve kullanıcı o
ekranda gerçekten kilitli kalır (bekçi:
`test/force_update_screen_test.dart`).

### 4.10 — Ortak (affiliate) bağlantısı iOS'ta · ✅ **kod** (`31ee208`) · ⏳ **deploy + cihaz ölçümü**

Ortaklık programı canlı ve bugün **yalnız Android'de sayıyor**. Ölçülen
durum (2026-10-22):

| Parça | Android | iOS (kod, `31ee208`) |
|---|---|---|
| Kurulu uygulamada `rytho.app/r/KOD` | App Links → `deep_links.dart` → `POST /api/v1/billing/redeem-code` | AASA `/r/*` → Universal Link → **aynı** `deep_links.dart` yolu. Yayın ve cihaz ölçümü bekliyor |
| Kurulu DEĞİLKEN tıklama → kurulum | `web/r/index.html` Play'e `&referrer=`; `partner_referrer.dart` Install Referrer | App Store'da dengi YOK → "kur, hesabını aç, bağlantıya bir kez daha dokun" (aşağıda) |
| `/r/` sayfasının iPhone metni | — | `APPSTORE_ID` boşken **bugünkü** cümle: "Ortak bağlantısı şimdilik yalnız Android kurulumlarında sayılıyor" |

**Sahip kararı (2026-10-22): "bir kez daha dokun".** Parmak izi eşleştirme
yok. Profesyonel seçenekler tartıldı: Branch'in "NativeLink"i (pano; iOS 16+
"Yapıştırılsın mı?" izni sorar), Apple Custom Product Page (ortak başına bir
mağaza sayfası, en çok 70, her biri incelemeden geçer; "Aç" derin bağlantısı
iOS 18+, yeni kurulumda da çalıştığını Apple açıkça yazmıyor), App Store
teklif kodları (kullanıcıya kod yazdırıp indirim verir — programın iki
kuralını bozar). Hiçbiri seçilmedi.

**Nasıl çalışıyor:**
- Kurulu uygulamada bağlantı uygulamayı açar ve kod mevcut yoldan sayılır.
  ⚠️ O yol **oturum ister** (`deep_links.dart`: 401 terminal sayılmaz) —
  sayfa metni bu yüzden "kur, **hesabını aç**, sonra dokun" diyor.
- `/r/` sayfası iPhone'da App Store bağlantısı ve **"Uygulamada aç"**
  düğmesi gösterir. Düğme KARŞI host'a gider (`rytho.app` ↔
  `rhytoai.web.app`): Universal Link aynı alan adı içinde tetiklenmez.
  Uygulama kurulu değilse sayfa orada `?tekrar=1` ile açılır ve tıklama
  İKİNCİ kez sayılmaz.
- Bekçiler (`test_web_seo.py`): dalın `APPSTORE_ID`'ye kapılı olması,
  `?tekrar=1`'de ping olmaması, düğme hedefinin `applinks:` listesinde ve
  sayfadan farklı host olması. Dördü de mutasyonla kırmızı ölçüldü. Yedi
  senaryo (masaüstü, iPhone kimliksiz/kimlikli, iki host, tekrar, Android,
  geçersiz kod) JavaScriptCore'da sahte DOM ile koşturuldu.

**Yayın günü listesi** — uygulama App Store'da YAYINLANIP cihazda
ölçülmeden YAPILMAZ. Hosting her deploy'da `web/`'i tümden değiştirdiği için
erken yazılan bir metin herhangi bir makinenin ilk deploy'unda canlıya
çıkardı:
1. `web/r/index.html` → `APPSTORE_ID` (App Store Connect'in sayısal kimliği).
2. `web/ortaklik.html` (iPhone paragrafı) ve `web/en/partners.html`
   (aynısı) — "iPhone'dan gelen bağlantı sayılmaz" → "ikinci dokunuşta sayılır".
3. `web/affiliate/ortak.js` iPhone dipnotları (TR + EN + kod yorumu):
   **güncellenir, kaldırılmaz** — ikinci dokunuşu yapmayan hâlâ sayılmaz,
   dönüşüm oranının böleninde iPhone tıklamaları duruyor.
4. Yönetim paneli `web/rytho-admin/gorunumler/ortaklar.js` ("iOS ve
   masaüstü" dipnotu) ve `web/index.html` / `web/en/index.html`
   "iPhone'da ne zaman?" SSS'i.
5. `docs/ortaklik-programi.md` §8 "Durum" satırı.

**Cihazda ölçülecek (iPhone gelince):**
1. Notlar'a `https://rytho.app/r/TESTKOD` yaz, dokun → uygulama açılır,
   `users/{uid}/private/attribution` yazılır (oturum açıkken).
2. Safari'de `rytho.app/r/TESTKOD` → "Uygulamada aç" (karşı host) →
   uygulama açılır mı?
3. Instagram / WhatsApp uygulama içi tarayıcısından dokunuş — Universal
   Link'i açmayabilirler; ölçülmeden hiçbir şey söylenmez.
4. Apple'ın AASA önbelleği:
   `https://app-site-association.cdn-apple.com/a/v1/rytho.app` deploy'dan
   sonra güncellenmeyebilir; önce oradan oku.

Kurallar (Android'de ölçülenlerle aynı kalmalı): kullanıcı **kod yazmaz**,
kullanıcıya ödül **yok**, ortak kendi kodunu kendi hesabında kullanamaz,
sayılan şey **"bağlantıyı kullanan"** (kuran değil). Sunucu tarafı
(`partner_service.redeem`) platformdan bağımsız.

---

## 5. Depo tarafında BİTMİŞ olanlar

Mac'te bunları yeniden yapma, yapıldı ve testten geçti:

- **`GoogleService-Info.plist`** depoda (`ios/Runner/`), bundle
  `ai.rytho` doğrulanmış ve Runner hedefinde — pakete giriyor (4.2).
- **CocoaPods entegrasyonu** (`pod install`, `Podfile.lock` depoda) ve
  **imzasız cihaz derlemesi** Mac'te geçti (2026-09-26, Xcode 26.6).
- **Google girişi** `Info.plist`'e bağlandı; iOS API anahtarı `ai.rytho`
  ile kısıtlandı (4.3).
- **`ios/Podfile`** yazıldı, `platform :ios, '15.5'` **açık**. Flutter'ın
  şablonunda bu satır yorumlu gelir ve o yüzden `pod install` şu hatayla
  düşerdi: *"platform of the target Runner (iOS 13.0) is not compatible
  with google_mlkit_face_detection which has a minimum requirement of
  iOS 15.5"*. 15.5 keyfî değil, paketlerin dayattığı taban.
- **Deployment target 15.5** — `pbxproj`'de üç yapılandırmada da.
- **App Check Apple sağlayıcısı** — `main.dart` artık `providerApple`
  geçiyor (`AppleAppAttestProvider`, debug'da `AppleDebugProvider`).
  Zorlama 2026-09-26'da açıldığı için bu olmadan iOS paketi Firestore ve
  Auth'a **hiç bağlanamazdı**.
- **`aps-environment`** + `UIBackgroundModes/remote-notification` (4.5).
- **`ITSAppUsesNonExemptEncryption = false`** — yoksa App Store Connect
  her TestFlight yüklemesinde ihracat sorusunu yeniden sorar.
- **`STRIP_STYLE = non-global`** — `tflite_flutter` README'sinin uyardığı
  arşiv kusuru: Xcode sembolleri soyunca `flutter build ipa` sonrası
  çalışma anında "symbol not found" ile patlıyor.
- **Zorunlu güncelleme** artık platforma göre dallanıyor. **Abonelik
  yönetimi** ise aboneliğin ALINDIĞI mağazayı açıyor: RevenueCat yetkisinin
  `store` alanı, bilinmiyorsa çalışan platform (U47).
- **Mağaza metinleri** — dört kullanıcı dizesi "Google Play" yazmıyor
  artık. Türkçe ek uyumu yüzünden yer tutucu kullanılamadı ("Play'**de**"
  ama "App Store'**da**"), bu yüzden mağaza adı metinden çıkarıldı.
  Satın alma hata metinleri de artık iki platformda doğru: Mac U46'da iOS'a
  ayrı anahtarlar açmıştı ("Google hesabı" ve "test kanalı" diyen iki metin
  yüzünden); Windows'un D7'si o iki metni platformdan bağımsız yeniden
  yazdığı için birleşmede (`8d6f67b`) iOS kopyaları kaldırıldı. Kalan tek
  platform dalı `purchaseNotAllowed` (iOS'ta çaresi Ekran Süresi).

---

## 6. Bitmemiş, Mac'te yapılacak kod işleri

- ⏳ **U56 — `app_settings` iOS derlemesini durduruyordu** (ölçüldü
  2026-10-22; sahip kararıyla 7.0.0'a sabitlendi, iOS simülatör derlemesi
  geçti). **Kalan: Windows'ta `infra/build-aab.ps1` ile Android derlemesi**
  ve cihazda kamera reddi + izin kapısı "Ayarları aç". `flutter build ios --simulator`: *"The following plugin(s)
  are only compatible with Swift Package Manager: app_settings"*. 8.0.0
  CocoaPods desteğini bıraktı; depoda `pubspec.yaml`
  `enable-swift-package-manager: false` (U25: SPM + Pods Google
  kütüphanelerini iki kez bağlıyordu). Kullanım iki yerde:
  `face_capture_screen.dart` (kamera reddi "Ayarları aç") ve
  `widgets/izin_kapisi.dart`. Son CocoaPods sürümü **7.0.0**; API 7→9
  değişmedi. 8.x'teki Android değişiklikleri AGP 9 derleme uyumluluğu ve
  proje AGP **9.0.1**'de (`builtInKotlin=false`, `newDsl=false`) — 7.0.0'ın
  Android'de derlendiği bu Mac'te ÖLÇÜLEMEDİ (Java yok). Risk: 7.0.0'ın
  `android/build.gradle`'ı `kotlinOptions` kullanıyor; Kotlin 2.2'den beri
  bu DSL "hata" düzeyinde kullanımdan kalktı, proje 2.3.20'de. Dosya Groovy
  — Kotlin'in düzeyini zorlamayabilir, ama ancak bir derleme söyler.
  Düşerse yol: eklentiyi kaldırıp iOS'ta `uygulamaAyarlariniAc`, Android'de
  küçük bir yerel çağrı.
- ✅ **`InfoPlist.strings` bağlı** (U27, `54130b9`): `en` + `tr` varyant
  grubu Copy Bundle Resources'ta, `knownRegions` `(en, Base, tr)` — ölçüldü
  2026-10-22. İngilizce cihaz İngilizce izin metni görür.
- **Bildirim delegesi — ÇÖZÜLDÜ, `AppDelegate.swift`'e satır EKLENMEZ**
  (`docs/ios-uyum-denetimi.md` U14). Soru kaynak okumasıyla yanıtlandı:
  AppDelegate delege atamadığı için delegeyi `firebase_messaging` alıyor;
  `flutter_local_notifications` `willPresent` hiç almıyor. README'nin
  istediği `UNUserNotificationCenter.current().delegate` satırı eklenirse
  `FlutterAppDelegate` `willPresent`'i iki eklentiye de iletir ve ikisi
  de aynı, **bir kez** çağrılması gereken tamamlayıcıyı çağırır (denetimin
  beklediği sonuç çift banner; cihazda ölçülmedi).
  Ön plan push'unu iOS'ta artık FCM kendisi gösteriyor
  (`setForegroundNotificationPresentationOptions`,
  `lib/core/notifications.dart` `iosOnPlanSunumunuAc`); yerel bildirimle
  gösterim yalnız Android'de. Bekçi: `test/bildirim_ios_test.dart`
  AppDelegate'te `UNUserNotificationCenter` geçmediğini sabitliyor. Kalan
  yalnız cihaz doğrulaması (APNs anahtarı gerekli, U08): uygulama açıkken
  test push'u → banner → dokunuş rotası.

---

## 7. macOS'a özgü tuzaklar

- **`pod install` Xcode lisansı kabul edilmeden düşer.** Xcode'u bir kez
  aç, lisansı kabul et.
- **`flutter build ipa` yalnız macOS'ta çalışır** — imzalama ve arşivleme
  Apple araçlarına bağlı. Windows'tan iOS paketi üretilemez.
- **Simülatörde çalışmayan iki şey var:** TFLite (tflite_flutter README'si
  söylüyor) ve App Attest. İkisi de **gerçek cihaz** ister. Yüz okuma ve
  App Check'i simülatörde test etmeye çalışma.
- **`gcloud`'un varsayılan projesi kayabiliyor.** Her komutta
  `--project rhytoai` yaz; yoksa komutlar **sessizce yanlış projeye**
  gider. Bu bir kez yanlış bir "panelde hiç admin yok" blocker'ı ürettirdi.
- **Satır sonları.** Depo (index) her şeyi **LF** saklıyor; CRLF yalnız
  Windows çalışma kopyasında `core.autocrlf` yüzünden görünür. Mac'te
  `autocrlf` ayarsız bırakılır ve dosyalar LF gelir (ölçüldü:
  `git ls-files --eol apps/mobile/ios` hepsi `i/lf w/lf`). Mac'te
  `autocrlf=true` yapma — o zaman hayalet diff burada başlar.
- **Xcode 27 bu depoyu DERLEYEMİYOR** (ölçüldü 2026-09-26, Xcode 27.0
  27A266a). İki bağımsız kırılma: (1) Swift 6.4, `purchases-ios` 5.67.1'i
  (`purchases_flutter` 9.16.1 üzerinden) reddediyor —
  `PaywallColor.swift:56` "Invalid redeclaration of synthesized memberwise
  init"; (2) Xcode 27'nin `lipo`'su `-verify_arch`'a birden çok mimari
  verilince argümanı dosya sanıyor ve Flutter 3.44.7'nin simülatör
  derlemesi "does not contain architectures" ile düşüyor. Çözüm olarak
  **Xcode 26.6 (17F113) yan yana kuruldu**: `/Applications/Xcode-26.app`.
  Alternatif `purchases_flutter` 10.x'e majör atlamaktı; Android'i de
  etkileyeceği için seçilmedi.
- **`DEVELOPER_DIR` YETMEZ, `xcode-select` şart.** `objective_c` paketinin
  native-assets kancası SDK'yı `xcrun --show-sdk-path` ile soruyor
  (`hook/build.dart:183`) ve Flutter kancaya `DEVELOPER_DIR`'ı geçirmiyor.
  Sonuç: derleyici Xcode 26'dan, SDK Xcode 27'den gelir ve bağlama
  "unknown architecture … libSystem.B.tbd" ile düşer. Doğrusu:
  `sudo xcode-select -s /Applications/Xcode-26.app/Contents/Developer`.
  Xcode'u değiştirdikten sonra `.dart_tool/hooks_runner` ve `build/ios`
  silinir.
- **Xcode'un yolunda boşluk ya da Türkçe harf olmasın.** Finder'da
  kopyalanınca "Xcode kopyası.app" oluyor; adını `Xcode-26.app` yap.
- **Simülatörde uygulama AÇILIR, yüz okuma açılmaz.** ML Kit arm64
  simülatör dilimi taşımıyor ve iOS 26+ Apple Silicon simülatörleri arm64
  zorunlu tutuyor. `e4789d4` bunu yalnız simülatör derlemesinde çözdü:
  ML Kit çerçeveleri simülatör bağlamasından çıkar, yerine
  `SimulatorStubs/MLKitSimulatorStubs.m` aynı sınıfları ve kanal adlarını
  verir ve çağrıya açık bir `SIMULATORDE_YOK` hatası döner (sessiz "yüz
  yok" değil). Cihaz derlemesi DEĞİŞMEZ. Ölçülen (2026-09-26): giriş ekranı
  açıldı, App Check **debug jetonuyla** giriş çalıştı — jeton simülatör
  kurulumuna bağlı, sıfırlanan simülatörde Firebase App Check'e yeniden
  eklenir. (Burada eskiden "uygulama simülatörde HİÇ çalışmaz" yazıyordu;
  `e4789d4` onu onardı ama notu güncellemedi — bayat bulundu 2026-10-22.)
  Yüz okuma, App Attest, push ve Universal Link yalnız **cihazda**.
- **`flutter analyze` Mac'te `build/`'i taramasın.** Flutter burada SPM
  için eklenti kaynaklarını `build/ios/SourcePackages`'a indiriyor;
  dışlanmazsa üçüncü taraf testlerinden 864 sahte hata sayılıyordu.
  `analysis_options.yaml`'da `analyzer: exclude: [build/**]`.
- **CocoaPods UTF-8 ister:** kabuğun yerel ayarı UTF-8 değilse her `pod`
  çağrısı uyarı basar — `export LANG=en_US.UTF-8` (ölçüldü 2026-10-22).
- **CocoaPods ve Homebrew:** `brew install cocoapods` (sistem ruby 2.6
  yeni CocoaPods'u kaldırmaz). `powershell` cask'ı kaldırılmış; yalnız
  `powershell@preview` var ya da GitHub'dan `.pkg`. Model indirmek için
  pwsh şart değil — `fetch_models.ps1`'deki URL'yi `curl` ile çekmek aynı.

---

## 8. Mac'teki Claude'a söylenecek ilk şey

`CLAUDE.md` her oturumda otomatik okunuyor, yani temel bilgi zaten
yüklenir. Bu belgeyi ayrıca göstermek gerekir:

> Bu depoyu Windows'tan yeni taşıdım, iOS sürecini başlatacağız.
> `docs/mac-devir.md`'yi oku — Mac kurulumu ve iOS yol haritası orada.
> Önce 3. bölümdeki doğrulamayı koş (`flutter analyze`, `flutter test`,
> `pytest`) ve bana sonucu söyle; beklenen değerler belgede yazılı.
> Sonra 4. bölümdeki sırayı takip edeceğiz, ben hesap işlerini yapacağım.
> İlk ürün işi 4.10: ortak bağlantısının iOS'ta Universal Link ile
> sayılması; ertelenmiş atıf için seçeneği bana sor.

(Sahibin bu tur için yazdırdığı tam ilk mesaj oturum kaydında; özü yukarıda.)

**Hiçbir şeyi hatırladığını sanma, ölç.** Bu depoda notların bayatladığı
iki kez yakalandı ve ikisi de yanlış yöne saatler harcattı.

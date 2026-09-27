# Mac'e devir ve iOS başlangıcı

Bu belge, depoyu bir Mac'e taşıyıp iOS sürecini başlatmak içindir. Her
madde ya ölçülerek bulundu ya da bir kez zarar verdi. Windows makinesinde
**her şey çalışıyor**; buradaki listede yazanlar Mac'te *ek olarak* gereken
şeyler.

Ölçüm tarihi: **2026-09-26**. Dal: `yuz-okuma-cihaz-usti-olcum`.
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
flutter test                      # beklenen: 574 test geçer
```

Backend:

```bash
cd backend
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m pytest -q     # beklenen: 1590 test geçer
```

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

### 4.4 — İmzalama · **SEN (Xcode'da)**
`project.pbxproj`'de `DEVELOPMENT_TEAM` anahtarı **hiç yok** ve Runner
hedefinde `CODE_SIGN_STYLE` yok; imza kimliği eski biçimde
(`"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Developer"`). Xcode'da
Runner → Signing & Capabilities → Team seç; Xcode gerekli anahtarları
kendisi yazar. **Bunu Xcode'a yaptır**, elle pbxproj düzenleme.

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

### 4.8 — `apple-app-site-association` · **SEN (Team ID gelince)**
`web/.well-known/apple-app-site-association` içinde
`"appID": "TEAMID.ai.rytho"` — **`TEAMID` yer tutucu**. Gerçek Team ID
yazılıp `firebase deploy --only hosting --project rhytoai` ile yayınlanır.
Bunsuz davet bağlantıları iOS'ta uygulamayı açmaz, tarayıcıya düşer.

Entitlements tarafı hazır: `applinks:rytho.app` **ve**
`applinks:rhytoai.web.app` ikisi de yazılı (sahadaki eski davet bağlantıları
ikincisini taşıyor).

### 4.9 — App Store Connect kaydı ve `APPSTORE_APP_ID` · **SEN**
Kayıt açılınca **sayısal uygulama kimliği** doğar. Onu
`dart_defines.local.json`'a `APPSTORE_APP_ID` olarak yaz.

Boş bırakılırsa zorunlu güncelleme ekranı iOS'ta mağaza düğmesi
**göstermez** ve dürüst bir mesaj verir. Bu bilinçli: uydurma bir kimlikle
kurulan bağlantı mağazada "uygulama bulunamadı" açar ve kullanıcı o
ekranda gerçekten kilitli kalır (bekçi:
`test/force_update_screen_test.dart`).

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
  ⚠️ Burada eskiden "mağaza metinleri nötr" yazıyordu ve iki satın alma
  hata metni için YANLIŞTI: `purchaseAlreadyOwned` "Google hesabı",
  `purchaseItemUnavailable` "test kanalı" diyor (U46). Artık
  `storeErrorText` iOS'ta ayrı anahtarlara gidiyor; Android metinleri bayt
  bayt duruyor.

---

## 6. Bitmemiş, Mac'te yapılacak kod işleri

- **`en.lproj/InfoPlist.strings` bağlanmalı.** Dosya
  `apps/mobile/ios/Runner/en.lproj/` altında **hazır** ama Xcode projesine
  bağlı değil: Copy Bundle Resources'ta yok ve `knownRegions` yalnız
  `(en, Base)`. Windows'tan pbxproj'e variant-group cerrahisi yapmak
  projeyi hiç açılmaz hâle getirebilirdi, o yüzden yapılmadı.
  Xcode'da: Info.plist seç → File Inspector → Localize → Türkçe ekle.
  Şu an `developmentRegion = en` ama Info.plist metinleri **Türkçe**, yani
  İngilizce cihaz Türkçe izin diyaloğu görüyor. Türkiye-öncelikli
  lansmanda kabul edilebilir; **dünyaya açılmadan önce** düzeltilmeli.
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
- **Uygulama iOS 26+ simülatörde HİÇ çalışmaz.** ML Kit (yüz okuma) arm64
  simülatör dilimi taşımıyor; Flutter `EXCLUDED_ARCHS[sdk=iphonesimulator*]
  = arm64` yazıyor ama iOS 26+ Apple Silicon simülatörleri arm64 zorunlu
  tutuyor. Test yolu **gerçek cihaz**. (TFLite ve App Attest de zaten
  cihaz istiyordu.)
- **`flutter analyze` Mac'te `build/`'i taramasın.** Flutter burada SPM
  için eklenti kaynaklarını `build/ios/SourcePackages`'a indiriyor;
  dışlanmazsa üçüncü taraf testlerinden 864 sahte hata sayılıyordu.
  `analysis_options.yaml`'da `analyzer: exclude: [build/**]`.
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

**Hiçbir şeyi hatırladığını sanma, ölç.** Bu depoda notların bayatladığı
iki kez yakalandı ve ikisi de yanlış yöne saatler harcattı.

# iOS uyum ve App Store hazırlık denetimi — 2026-09-26

Bu belge, iOS'un Android'le eşliğini (parite) ve App Store'a çıkışa hazırlığını ölçen denetimin **kalıcı, denetlenebilir kaydıdır**. Mac (iOS) ve Windows (Android) Claude oturumlarının ikisi de işi buradan izler. Kayıt silinmez; yalnız durumu değişir (bkz. "Nasıl güncellenir").

- **Tarih / dal / taban:** 2026-09-26 · `ios-hazirlik` · `e4789d4` ("Uygulama iOS simülatöründe açılır"). **Kanıttaki satır numaraları bu commit'e göredir.** Kapanan kayıtlarda kanıt tarihsel kayıttır; satırlar sonradan kaymış olabilir.
- **Yöntem:** 7 alan — `dart-platform`, `native-config`, `auth-identity`, `purchases`, `push-deeplinks`, `backend-platform`, `review-compliance`. Her alanda bir **bulucu** ve her bulguyu kaynağı yeniden açarak sınayan **şüpheci bir doğrulayıcı**; üstüne alanların arasına düşeni arayan bir **eksik avcısı**. 7 × 2 + 1 = **15 ajan**, tamamı **salt okunur** (denetim depoya yazmadı).
- **Sonuç:** 67 doğrulanmış bulgu (66 ONAYLANDI, 1 BELİRSİZ), **çürütülen yok**; eksik avcısından 7 ek bulgu. Alanlar arası kopyalar birleştirilince **55 kayıt**: 7 RET · 2 BOZUK · 12 YÜKSEK · 20 ORTA · 14 DÜŞÜK. Belge yazılırken `54130b9` ve `4ba7d9d` 10 kaydı kapattı (U03, U10, U12, U13, U25, U26, U27, U42, U43, U44).
- **Düzeltme metinleri** doğrulayıcının düzeltmelerini zaten içerir (ör. "whiteOutlined koyu zeminde yanlış", "mağazaya deneme ekleme", "iptal başarısızsa silmeyi engelleme").
- Bu denetim, CLAUDE.md §7'de anılan ve `docs/mac-devir.md`'ye işlenen 63 ajanlı envanter denetiminden **ayrıdır**.
- **Yollar:** Dart ve iOS yolları `apps/mobile/` altındadır (`lib/…`, `ios/…`, `test/…`); diğerleri depo köküne göredir.
- **Hazırlık turu (2026-10-23, Mac, HEAD `ba6108b`):** dört ölçüm (imza-hesap-cihaz, uyum kaydı, imzasız Release derlemesi, canlı bağımlılıklar) + eksik avcısı; depoya kod yazılmadı. Sonuç: U52 kapandı (kod `eed33c7`'de kapanmıştı, kayıt bayattı); U01, U02, U06, U08, U10, U15, U17, U18, U21, U22, U25, U26, U27, U29, U37, U41, U53, U55'e **"Ek (ölçüldü 2026-10-23)"** notları düşüldü — eski satırlar silinmedi. Yeni U numarası açılmadı; yeni eksiklerin çoğu mevcut kayıtlara Ek olarak girdi. İstisnalar: "iOS anahtarını boşalt" bulgusu (U05 Düzeltme 3 zaten kapsıyordu, o tur Ek düşülmedi; 2026-10-24'te U05 Ek'ine girdi), Gemini Auto-reload (`docs/mac-devir.md` §4 C12, iOS'a özgü değil) ve `/openapi.json` açıklığı (kayda girmedi; `docs/mac-devir.md` §4 "Sahibin kararları"). Sahibin sıralı adımları (cihazda Debug → iç TestFlight → App Store incelemesi) `docs/mac-devir.md` §4 Aşama A/B/C'de. U05'e bu turda dokunulmadı. *(Düzeltme 2026-10-24: burada "her yeni eksik mevcut bir kayda oturdu" yazıyordu.)*
- **Çürütme + U05 turu (2026-10-24, Mac):** U05 `⏳ açık (kısmen)` — kod ağı ve `infra/build-ipa.sh` `09bbe23` (iki tur tek commit), konsol ve ilk imzalı IPA kaldı. U06 Ek'i sahip kararına göre düzeltildi (açık karar yok; kalan yalnız riskin kayda yazılması). U08 Ek'inin App Check belirtisi koda göre düzeltildi (`activate()` iOS'ta düşmez). U52 `⏳ açık (kısmen)`'a döndü (Düzeltme'nin lisans kaydı maddesi yapılmadı). U17 Ek'indeki deploy atfı CLAUDE.md §7 sırasına bağlandı.
- **Konsol araştırması düzeltmeleri (2026-10-24, Mac; Apple/Firebase belgeleri + pod kaynağı, konsol ölçülmedi):** U08 (APNs anahtarı ortam başına; Firebase'de development/production ayrı; App Attest TestFlight'tan önce cihazda `--profile` ile; yol Security → App Check), U15 ("A5" etiketi), U22 (Email Sources yolu), U53 (Mac'te App Attest yok) ve "Doğrulanmış olanlar"daki APNs ortamı satırı düzeltildi. Hiçbir kaydın durumu değişmedi.

**Lejant**

- **Önem:** RET = App Review reddi getirir · BOZUK = özellik iOS'ta çalışmaz · YÜKSEK · ORTA · DÜŞÜK.
- **Sahip:** kod = depoda düzeltilir · hesap = sahibin konsol/hesap işi · ikisi = ikisi birden.
- **Aşama:** A1 hesap (konsol işleri) · A2 iOS kod (yalnız iOS native ya da iOS korumalı Dart) · A3 ortak kod (platformlar arası Dart, backend, kurallar, web) · A4 mağaza (metaveri, ekran görüntüsü, inceleme notları, gizlilik etiketi) · A5 test (cihaz/TestFlight doğrulaması) · Sonra (bilerek ertelendi).
- **Durum:** ⏳ açık · ✅ kapandı + commit.

---

## Sahibin kararları

Denetimden sonra sahibin verdiği kararlar. Bazı kayıtları kapatır, bazılarında düzeltmenin yönünü belirler.

1. **Yalnız iPhone** — `TARGETED_DEVICE_FAMILY = 1`. iPad bulguları bu kararla kapanır (U10; U07, U32, U44'ün iPad parçaları). ⚠️ **Tek yönlü kapı:** iPad'i destekleyen bir sürüm bir kez yayınlanınca sonraki sürümler iPad'i bırakamaz (ASC, öncekinden az cihaz destekleyen paketi reddeder). Karar bu yüzden ilk yayından ÖNCE verildi; ilk yayından sonra "iPad'i kaldır" yönünde geri alınamaz. Yalnız iPhone uygulaması iPad'de uyumluluk kipinde çalışır. *(Not 2026-10-23: son cümle Apple'ın davranışını anlatıyor; Rytho'nun uyumluluk kipinde **doğru çalıştığı ölçülmedi** — 12 iPad simülatörünün hiçbirinde kurulmadı. Bkz. U10 ek.)* *(→ 2026-10-24: iPad (A16, iOS 27.0) simülatörüne kuruldu ve açıldı (2026-10-23 20:53, giriş yok); doğru çalıştığı hâlâ ölçülmedi.)*
2. **Yalnız Türkiye** — v1 bölgesi Türkiye. ABD yaş doğrulama yasaları ve AB DSA'nın yayın yükümlülükleri kapsam dışı (U41 → Sonra). İnceleyici yine İngilizce cihazla bakabilir; İngilizce izin metinleri bu yüzden gerekli kalır (U27).
3. **Gerçek iPhone yok** — App Attest (simülatörde çalışmaz) ve kamera ile yüz okuma (ML Kit ve TFLite simülatörde dışlı) **ilk kez App Review'da görülecek**. Kabul edilen risk (U09, U21). *(Değişti — not 2026-10-23: sahip 2026-10-22'de iPhone'un "haftaya" geleceğini söyledi (`docs/mac-devir.md` Mac durumu kutusu). Bugün bağlı cihaz yok — `xcrun devicectl list devices` yalnız simülatör, ölçüldü. Cihaz gelince bu karar ve U21 planı yeniden yazılır; sıralı cihaz adımları `docs/mac-devir.md` §4 Aşama A.)*
4. **AI onayı iki platformda** — 5.1.2(i) onayı ortak Dart'ta, Android'de de görünür (U06). 2026-10-23: sayfa değil, kurulumun ilk adımındaki ikinci zorunlu kutu (U06 kaydının başındaki not).
5. **Ortak kodu Mac yazar, Windows yayınlar** — A3 değişiklikleri Mac'te (`ios-hazirlik`) yazılır; Android paketi Windows'ta `infra/build-aab.ps1` ile çıkar. Kayıtlardaki **Android güvenliği** satırları Windows oturumu içindir.
6. **Abonelik cihaz kilidi: platform başına bir cihaz** — bir iPhone + bir Android aynı anda (U32).

---

## Özet tablo

| Kimlik | Önem | Sahip | Başlık | Aşama |
|---|---|---|---|---|
| U01 | RET | hesap | ⏳ Firebase'de Apple sağlayıcısı kapalı | A1 hesap |
| U02 | RET | hesap | ⏳ ASC + RevenueCat IAP önkoşulları, ilk gönderim paketi | A1 hesap |
| U03 | RET | kod | ✅ `NSMicrophoneUsageDescription` eksik (ITMS-90683) | A2 iOS kod |
| U04 | RET | kod | ✅ Apple ile Giriş düğmesi HIG'e aykırı | A2 iOS kod |
| U05 | RET | ikisi | ⏳ iOS yayın kapısı yok; `test_` anahtarı açılışta çöker (kısmen `09bbe23`: kod ağı + `build-ipa.sh`) | A2 iOS kod |
| U06 | RET | ikisi | ✅ Üçüncü taraf AI için uygulama içi onay yok (5.1.2(i)) | A3 ortak kod |
| U07 | RET | ikisi | ⏳ App Store boyutunda ekran görüntüsü yok | A4 mağaza |
| U08 | BOZUK | hesap | ⏳ iOS push konsol önkoşulları (APNs, App Attest kaydı) | A1 hesap |
| U09 | BOZUK | kod | ✅ Yüz okuma geometrisi iOS karesinde yanlış | A2 iOS kod |
| U10 | YÜKSEK | ikisi | ✅ iPad desteği açıktı — tek yönlü kapı | A2 iOS kod |
| U11 | YÜKSEK | kod | ✅ Bildirim izni girişten hemen sonra soruluyor | A2 iOS kod |
| U12 | YÜKSEK | kod | ✅ Uygulama gizlilik manifesti yok | A2 iOS kod |
| U13 | YÜKSEK | kod | ✅ `FlutterDeepLinkingEnabled` açık: davet Safari'ye sekiyor | A2 iOS kod |
| U14 | YÜKSEK | kod | ✅ Ön planda gelen push iOS'ta kayboluyor | A2 iOS kod |
| U15 | YÜKSEK | ikisi | ⏳ Hesap silmede SIWA jetonu iptal edilmiyor | A2 iOS kod |
| U16 | YÜKSEK | kod | ⏳ App Store iadeleri webhook'ta yok sayılıyor | A3 ortak kod |
| U17 | YÜKSEK | kod | ⏳ Engelleme uygulanmıyor (1.2) | A3 ortak kod |
| U18 | YÜKSEK | ikisi | ⏳ Review notları yanlış/eskimiş | A4 mağaza |
| U19 | YÜKSEK | ikisi | ⏳ 4.3(b) "fal" kategorisi savunması | A4 mağaza |
| U20 | YÜKSEK | ikisi | ⏳ App Privacy etiket planı eksik | A4 mağaza |
| U21 | YÜKSEK | ikisi | ⏳ TestFlight cihaz doğrulama planı yok | A5 test |
| U22 | ORTA | hesap | ⏳ Hide My Email aktarıcısına gönderici kaydı yok | A1 hesap |
| U23 | ORTA | kod | ✅ Kamera izni reddi arıza sayılıyor | A2 iOS kod |
| U24 | ORTA | kod | ✅ Ses efektleri sessiz anahtarını yok sayıyor | A2 iOS kod |
| U25 | ORTA | kod | ✅ Google kütüphaneleri iki kez bağlı (Pods + SwiftPM) | A2 iOS kod |
| U26 | ORTA | kod | ✅ Crashlytics dSYM yüklemesi yok | A2 iOS kod |
| U27 | ORTA | kod | ✅ Türkçe yerelleştirme ve izin metinleri | A2 iOS kod |
| U28 | ORTA | ikisi | ⏳ Gizlilik politikası metni Android çerçeveli | A3 ortak kod |
| U29 | ORTA | ikisi | ⏳ `min_build` iki platformda tek eşik | A3 ortak kod |
| U30 | ORTA | kod | ✅ App Check / Auth hataları iz bırakmıyor | A3 ortak kod |
| U31 | ORTA | kod | ✅ Apple girişinde "hesap başka yöntemle var" genel hata | A3 ortak kod |
| U32 | ORTA | kod | ⏳ Tek cihaz kilidi 3.1.2(a) ile çelişiyor | A3 ortak kod |
| U33 | ORTA | kod | ✅ Satın alma hata eşlemesinde iOS kodları eksik | A3 ortak kod |
| U34 | ORTA | ikisi | ⏳ Davet ve web sayfaları yalnız Google Play | A3 ortak kod |
| U35 | ORTA | kod | ⏳ Hesap silme sayfası yalnız Play iptalini anlatıyor | A3 ortak kod |
| U36 | ORTA | kod | ⏳ Paralel Android geliştirmeye karşı iOS bekçisi yok | A3 ortak kod |
| U37 | ORTA | ikisi | ⏳ UGC yüzeyi ve yaş derecelendirmesi | A4 mağaza |
| U38 | ORTA | ikisi | ⏳ Review notlarında yüz okuma ve TR telefon kapısı yok | A4 mağaza |
| U39 | ORTA | ikisi | ⏳ Giriş duvarının gerekçesi notlarda yok | A4 mağaza |
| U40 | ORTA | ikisi | ⏳ Apple ile açılan hesap Android'e giremiyor | Sonra |
| U41 | ORTA | hesap | ⏳ AB DSA tacir beyanı ve bölge seçimi | Sonra |
| U42 | DÜŞÜK | kod | ✅ App Attest yetkisi eksik | A2 iOS kod |
| U43 | DÜŞÜK | ikisi | ✅ IDFA destekli Analytics yığını | A2 iOS kod |
| U44 | DÜŞÜK | kod | ✅ Paylaşım kartı Fotoğraflar'a kaydedilemiyor | A2 iOS kod |
| U45 | DÜŞÜK | kod | ✅ Yeniden kurulumda anahtar zinciri oturumu yaşıyor | A2 iOS kod |
| U46 | DÜŞÜK | kod | ✅ Satın alma hata metinleri Google/Play diyor | A3 ortak kod |
| U47 | DÜŞÜK | kod | ✅ "Aboneliği yönet" kaynak mağazaya bakmıyor | A3 ortak kod |
| U48 | DÜŞÜK | kod | ✅ Sayısal klavye kapatılamıyor | A3 ortak kod |
| U49 | DÜŞÜK | kod | ✅ Sosyal giriş iptali hata gösteriyor | A3 ortak kod |
| U50 | DÜŞÜK | kod | ⏳ 426 metni "Google Play" diyor | A3 ortak kod |
| U51 | DÜŞÜK | kod | ⏳ Admin "iOS" filtresi eşleşmiyor | A3 ortak kod |
| U52 | DÜŞÜK | kod | ⏳ Yazı tipleri çalışma anında indiriliyor (kısmen `eed33c7`: lisans kaydı kaldı) | A3 ortak kod |
| U53 | DÜŞÜK | hesap | ⏳ Apple silicon Mac / Vision Pro erişilebilirliği | A4 mağaza |
| U54 | DÜŞÜK | kod | ⏳ FCM `getToken` APNs jetonundan önce (belirsiz) | A5 test |
| U55 | DÜŞÜK | kod | ⏳ Xcode 27 SDK tabanı borcu | Sonra |
| U56 | BOZUK | kod | ⏳ `app_settings` iOS derlemesini durduruyor (yalnız SwiftPM) | A3 ortak kod |

**Aşama dağılımı:** A1 4 · A2 19 · A3 19 · A4 8 · A5 2 · Sonra 3.

### Kaynak dizini (74 bulgu → 55 kayıt)

Her kaynak bulgunun hangi kayda girdiği. "(kısım)" = bulgu iki kayda bölündü.

- **dart-platform (14):** `face-ios-frame-geometry` U09 · `siwa-button-not-hig` U04 · `camera-permission-denied-ios` U23 · `ios-notif-prompt-at-signin` U11 · `apple-token-not-revoked-on-delete` U15 · `fcm-gettoken-before-apns` U54 · `min-build-gate-platform-agnostic` U29 · `ios-audio-session-ignores-silent-switch` U24 · `privacy-text-android-framed-idfa` U28 + U43 (kısım) · `store-error-wording-google` U46 · `manage-subscription-cross-store` U47 · `ipad-share-origin-and-save-image` U44 + U10 (kısım) · `ios-numeric-keyboard-no-dismiss` U48 · `social-signin-cancel-shows-error` U49
- **native-config (11):** `missing-microphone-usage-description` U03 · `no-app-privacy-manifest-static-sdks-uncovered` U12 · `flutter-deep-linking-not-disabled` U13 · `ipad-support-enabled-one-way-door` U10 · `duplicate-google-libs-cocoapods-and-spm` U25 · `firebase-analytics-idfa-ios-vs-android` U43 · `crashlytics-dsym-upload-missing` U26 · `ios-notification-prompt-fires-at-login` U11 · `localization-tr-missing-infoplist-strings-trap` U27 · `app-attest-entitlement-and-mac-availability` U42 + U53 (kısım) · `missing-photo-library-add-usage` U44
- **auth-identity (10):** `apple-provider-not-enabled-in-firebase` U01 · `apple-token-revocation-missing` U15 · `apple-button-not-hig-compliant` U04 · `auth-appcheck-failures-invisible` U30 · `min-build-gate-not-per-platform` U29 · `apple-account-exists-different-credential` U31 · `apple-private-relay-email-not-registered` U22 · `apple-signin-android-parity` U40 · `ios-keychain-session-survives-reinstall` U45 · `app-attest-entitlement-missing` U42
- **purchases (6):** `ios-release-test-key-crash-no-build-gate` U05 · `asc-revenuecat-ios-prereqs-undocumented` U02 · `single-device-lock-vs-3-1-2a` U32 · `purchase-error-mapping-ios-codes` U33 · `android-specific-purchase-copy-on-ios` U46 · `manage-subscription-ignores-origin-store` U47
- **push-deeplinks (5):** `ios-foreground-push-dropped` U14 · `ios-permission-prompt-at-login` U11 · `ios-flutter-deeplinking-not-disabled` U13 · `invite-landing-page-play-only` U34 · `ios-push-console-prereqs` U08
- **backend-platform (9):** `revenuecat-refund-event-never-sent` U16 · `siwa-token-revocation-missing` U15 · `min-build-shared-across-platforms` U29 · `no-ios-release-gate` U05 · `store-screenshots-play-only-ipad-required` U07 + U10 (kısım) · `web-store-links-play-only` U34 · `web-deletion-page-play-only-cancel` U35 · `update-required-message-names-google-play` U50 · `admin-platform-filter-case-mismatch` U51
- **review-compliance (12):** `third-party-ai-consent-5-1-2-i` U06 · `iap-first-submission-bundle` U02 · `block-not-enforced` U17 · `siwa-token-revocation` U15 · `review-notes-inaccurate` U18 · `spam-4-3b-fortune-telling` U19 · `privacy-label-apple-incomplete` U20 · `ugc-surface-and-age-rating` U37 · `purpose-strings-accuracy-localization` U27 · `analytics-adid-stack-ios` U43 + U28 (kısım) · `store-screenshots-ipad` U07 + U10 (kısım) · `invite-landing-play-only` U34
- **eksik avcısı (7):** `no-real-device-verification-plan` U21 · `review-notes-omit-face-reading-and-phone-gate` U38 · `login-wall-5-1-1-v-justification` U39 · `asc-dsa-trader-and-territory-decisions` U41 · `no-ios-build-guard-for-parallel-android-dev` U36 · `google-fonts-runtime-fetch` U52 · `xcode27-sdk-floor-liability` U55

---

## RET — App Review reddi

### U01 — Firebase Auth'ta Apple sağlayıcısı kapalı; iOS yol haritasında adımı yok
⏳ açık · RET · hesap · A1 hesap · kaynak: `apple-provider-not-enabled-in-firebase`

**Kanıt** — `docs/production-checklist.md:236` "Apple'i etkinlestir" maddesi işaretsiz; `docs/mac-devir.md` §4 (4.1–4.9) sağlayıcıyı açan bir adım içermiyor, §4.5 yalnız App ID yeteneğini anıyor.

**Etki** — Sağlayıcı kapalıyken iOS'taki her Apple girişi `operation-not-allowed` ile düşer. App Review, sunulan Apple girişini her zaman dener (4.8); bozuk düğme 2.1 (App Completeness) reddi demektir.

**Düzeltme** — Firebase Console → Authentication → Sign-in method → Apple → Etkin; yerel iOS girişi için yalnız bu anahtar yeter. Services ID ve "OAuth code flow configuration" (Team ID, Key ID, .p8) yalnız web/Android akışları ve jeton iptali için gerekir; Firebase'in iptal belgesi ikisini de istediğinden U15 ile aynı oturumda doldurulur. Bitince `production-checklist.md` maddesi işaretlenir.

**Ek (ölçüldü 2026-10-23)** — Yol haritası boşluğu kapandı: adım artık `docs/mac-devir.md` §4 **Aşama A4**'te (cihazda Debug testinin önkoşulu; iptal yarısı C7). O ana kadar §4'te yoktu (`grep -i "sign-in method" docs/mac-devir.md` boştu). Konsol durumu bu Mac'ten **ölçülemedi** (`firebase`/`gcloud` yok); `production-checklist.md` maddesi hâlâ işaretsiz. Kayıt ⏳ açık kalır.

### U02 — App Store Connect + RevenueCat IAP önkoşulları hiçbir runbook'ta yok; IAP'ler ilk sürümle gönderilmeli
⏳ açık · RET · hesap · A1 hesap · kaynak: `asc-revenuecat-ios-prereqs-undocumented`, `iap-first-submission-bundle`

**Kanıt** — `docs/mac-devir.md:175-185` (§4.7) yalnız anahtarı ve ürün kimliklerini anıyor; Paid Apps Agreement, abonelik grubu, In-App Purchase Key, IAP'lerin ilk sürümle gönderilmesi ve EULA metaverisi yok. `docs/store-launch.md:390-395` KT kararı: mağazaya deneme konmaz, 3 günlük deneme sunucuda ve kartsız. Simülatörde "Satın alma tamamlanamadı" zaten görüldü.

**Etki** — Bir adım atlanırsa: (a) offerings/ürünler boş ya da `configurationError` döner, inceleyici fiyat yerine hata görür → 2.1 / 3.1.2 reddi; (b) In-App Purchase Key yoksa StoreKit 2 işlemleri RevenueCat'e hiç yazılmaz, webhook tetiklenmez, backend Rytho+ ya da kredi açmaz; (c) 'RhytoAI Pro' yetkisine App Store ürünü bağlı değilse kullanıcı öder ama `purchaseEntitlementMissing` görür; (d) Kullanım Koşulları (EULA) bağlantısı yoksa otomatik yenilenen abonelik 3.1.2 ile reddedilir.

**Düzeltme** (sıralı; `docs/mac-devir.md` §4.7'ye de işlenmeli)
1. Paid Apps Agreement, vergi ve banka bilgileri etkin.
2. Abonelik grubu + `rytho_plus_monthly`. **Tanıtım teklifi ya da ücretsiz deneme EKLEME** — sunucu denemesiyle 3+3 gün çakışır, hukuk metinleriyle çelişir.
3. Üç consumable: `rytho_tokens_small/medium/large`. RevenueCat'te yalnız offering'e bağlanır, yetkiye değil.
4. Dört IAP'nin dördü de ilk sürüm gönderimine iliştirilir, her biri inceleme ekran görüntüsüyle.
5. RevenueCat'te App Store uygulaması (`ai.rytho`) → `appl_` anahtarı `dart_defines.local.json` `REVENUECAT_IOS_KEY`'e. Test Store (`test_`) ürünleri ve offering'leri taşınmaz: App Store ürünleri içe aktarılıp Current offering'in `$rc_monthly` paketine eklenir; consumable'lar ürün kimliğiyle erişilebilir olmalı (`wallet.dart` kimlikle çekiyor).
6. In-App Purchase Key (.p8 + Key ID + Issuer ID) SDK v5 için **zorunlu**; App Store Connect API anahtarı isteğe bağlı (ürün içe aktarma).
7. Metaveri: Kullanım Koşulları bağlantısı App Description'da ya da ASC EULA alanında, Gizlilik Politikası URL'si kendi alanında (uygulama içi bağlantılar zaten var).
8. Sandbox ya da TestFlight satın alma testi.

**Ek (ölçüldü 2026-10-23)** — Sekiz adımın hiçbiri kapanmış görünmüyor: `dart_defines.local.json`'da `REVENUECAT_IOS_KEY` hâlâ `test_` önekli (32 karakter) ve `APPSTORE_APP_ID` anahtarı hiç yok; konsollar ölçülemedi. Adımlar tam konsol yollarıyla `docs/mac-devir.md` §4 **B3** (Paid Apps + vergi + banka), **B4** (App Store Connect "New App" formu: iOS, ad, birincil dil, bundle `ai.rytho`, SKU; App Information'da kategori, içerik hakları — bu form hiçbir belgede yoktu, `SKU`/`Primary Language`/`Content Rights` araması 0; Copyright ve Support URL sürüm sayfasında, **C8** — 2026-10-24'e dek burada telif App Information'a yazılmıştı), **B5** (abonelik grubu + üç consumable), **B6** (In-App Purchase Key → RevenueCat → `appl_`; ürün içe aktarma için adım 6'daki App Store Connect API anahtarı), **C2** (ilk sürüme iliştirme, sandbox) ve **C5** (EULA). Etki (a)–(d) değişmedi; (a)'ya ek ölçüm: `test_` anahtarı 2026-10-23'teki imzasız Release paketinde `App.framework/App` içinde bulundu, yani bugün alınan her Release paketi açılışta bilerek çöker (U05). → 2026-10-24: U05 kod ağı (`09bbe23`) sonrası bu paket çökmez, satın alma kapalı çıkar; `infra/build-ipa.sh` onu durdurur (U05 ek). Gerçek `appl_` anahtarı yine bu kaydın işi.
Üç karar bu kayda bağlandı, hiçbiri belgelerde yoktu (ölçüldü): **(i) EULA** — `web/legal/kullanim.html` ve `web/en/legal/terms.html`'de "EULA" ya da Apple standart EULA bağlantısı yok; adım 7'nin iki yolu (standart EULA + açıklamada Koşullar bağlantısı / Koşullar'ı özel EULA yapmak — ikincisi hukuk metni, sahip onayı). **(ii) Fiyat noktası ve App Store Small Business Program** — `docs/maliyet-calismasi.md` ve `docs/konsol-gorevleri.md` fiyatı yalnız Play mantığıyla kuruyor ("Console'a KDV hariç gir"); Apple fiyat noktaları alıcıya görünen vergi dahil tutardır ve %15 oranı ayrı başvuru ister — ikisi de Apple belgesine dayanır, ölçülmedi. **(iii) Aile Paylaşımı** — abonelikte açılıp açılmayacağı; Apple belgesine göre açıldıktan sonra kapatılamaz (ölçülmedi), tek cihaz kilidiyle (U32) birlikte düşünülür; depoda Aile Paylaşımı yalnız Ask to Buy bağlamında geçiyor (U33). Üçü de `docs/mac-devir.md` §4 "Sahibin kararları" tablosunda.

**Android güvenliği** — Yalnız konsol işi.

### U03 — `NSMicrophoneUsageDescription` eksik
✅ kapandı — `54130b9` · RET · kod · A2 iOS kod · kaynak: `missing-microphone-usage-description`

**Kanıt** — `ios/Runner/Info.plist:9-17` yalnız rehber, kamera ve fotoğraf kütüphanesi anahtarlarını taşıyor. Android'de `android/app/src/main/AndroidManifest.xml:30-31` RECORD_AUDIO'yu `tools:node="remove"` ile söküyor; iOS'ta eklentinin kod referansını sökmenin karşılığı yok. Mikrofon API referansları hem `camera_avfoundation` hem `audioplayers`'tan geliyor.

**Etki** — App Store Connect işleme sırasında ikiliyi statik tarar ve ITMS-90683 verir; mesajın kendisi, API hiç çağrılmasa bile amaç metninin zorunlu olduğunu söyler. Böyle paketler geçersiz sayılır, TestFlight'a hiç ulaşmaz.

**Düzeltme** — Info.plist'e anahtar; tek çare bu. Yükleme taraması için yalnız Info.plist önemli; İngilizce satır `en.lproj/InfoPlist.strings` Xcode'a bağlanınca etkili olur (U27). `54130b9`: anahtar Info.plist'te ve en/tr varyantlarında.

### U04 — Apple ile Giriş düğmesi HIG'e uymuyor
✅ kapandı · RET · kod · A2 iOS kod · kaynak: `siwa-button-not-hig`, `apple-button-not-hig-compliant`

**Kanıt** — `lib/features/auth/login_screen.dart:519-528`: Apple girişi `GoldButton(text: l10n.signInWithApple, filled: false)` — altın çerçeveli metin düğmesi, Apple logosu yok. `:515-518`'deki yorum logoyu "metin tek başına kurala uygun" gerekçesiyle bilerek dışarıda bırakıyor; bu bulguyla o gerekçe çürüdü, yorum da düzeltilir. `lib/l10n/app_tr.arb:724` "Apple ile giriş" bir HIG başlığı değil; EN (`app_en.arb:724`, "Sign in with Apple") zaten uygun.

**Etki** — App Review düğmeyi HIG'e göre denetler: Apple logosu, "Sign in with Apple / Continue with Apple" başlığı, siyah / beyaz / beyaz-çerçeve stili. Temalı, logosuz altın çerçeve 4.0 Design (ve 4.8) ile sıkça reddedilir; bir inceleme turu kaybettirir. Formun altında durduğu için küçük iPhone'larda kaydırma gerektirebilir.

**Düzeltme**
- Yalnız `if (appleSignInAvailable)` içinde `sign_in_with_apple` 8.1.0'ın `SignInWithAppleButton`'ı (logoyu `apple_logo_painter` ile çizer): `style: SignInWithAppleButtonStyle.white`, koyu mürekkep zemin üstünde. **`whiteOutlined` önerisi yanlış:** HIG beyaz-çerçeveyi koyu/doygun zeminde açıkça yasaklıyor.
- `height: 52` (Google düğmesiyle eşit; HIG tabanı 30 pt yükseklik / 140 pt genişlik, önerilen 44 pt), `borderRadius: BorderRadius.circular(18)` (GoldButton ile eş), `text: l10n.signInWithApple`.
- `onPressed` zorunlu ve null olamaz, widget'ın meşgul durumu yok: `_busy` iken `IgnorePointer` + `Opacity` ile sar ya da `_appleBusy` iken Stack üstünde spinner göster.
- `app_tr.arb` → "Apple ile Giriş Yap" (ya da "Apple ile Devam Et"); `flutter gen-l10n`, yeniden üretilen `app_localizations_tr.dart` da commit edilir.
- Google'ın üstünde kalır. iPhone SE (3. nesil) simülatöründe metin ölçeği 1.3 ile bakılır; katlama altındaysa sosyal blok yalnız iOS'ta formun üstüne taşınır.

Kapandı: `[iOS] U04 U15 U31 U45 U48 U49: giris ve hesap silme akisi` — `login_screen.dart` `_AppleGirisDugmesi`: `SignInWithAppleButton` white / 52 / `circular(18)`, logo paketin `AppleLogoPainter`'ı, yalnız `appleSignInAvailable` dalında ve Google'ın üstünde; TR başlık "Apple ile Giriş Yap" (EN değişmedi). Meşgul durumu `IgnorePointer` + soluklaştırma + sağ kenarda `CupertinoActivityIndicator`; `onPressed: null` seçilmedi çünkü `CupertinoButton` dolguyu gri devre dışı rengine boyuyor. Başlık puntosu paket tarafından yüksekliğin %43'ü olarak veriliyor; sistem yazı ölçeği düğmeye uygulanmıyor (`MediaQuery.withNoTextScaling`). Yanlış gerekçeli eski yorum ("metin tek başına kurala uygun") düzeltildi; Google için logosuzluk gerekçesi korundu. Ölçüldü (`test/giris_ios_test.dart`): iOS'ta stil/yükseklik/yarıçap/başlık/logo ve Google'ın üstünde durduğu; Android'de Apple düğmesi hiç yok; meşgulken gösterge çıkıyor, ikinci dokunuş akış başlatmıyor, Google düğmesi kilitli.
Kalan: A5 — iPhone SE (3. nesil) + 1,3 yazı ölçeğinde düğmenin katlama üstünde kaldığına simülatörde bakılır.

**Android güvenliği** — Değişiklik `appleSignInAvailable` (yalnız iOS) dalında.

### U05 — iOS yayın kapısı yok: `test_` anahtarlı paket açılışta çöker
⏳ açık (kısmen — `09bbe23`) · RET · ikisi · A2 iOS kod · kaynak: `ios-release-test-key-crash-no-build-gate`, `no-ios-release-gate`

**Kanıt** — `infra/` altında yalnız Android'in `build-aab.ps1`'i var. `docs/mac-devir.md:177-179`: `REVENUECAT_IOS_KEY` şu an `test_…` (RevenueCat Test Store). `lib/core/subscription.dart:50-51` `billingConfigured` iki anahtardan BİRİ doluysa true; `:110-119` `initBilling` iOS'ta `kRevenueCatIosKey`'i seçip `Purchases.configure` çağırıyor — `test_` anahtarı release'te RevenueCat bilerek çöktürür, `initBilling`'deki try/catch bunu yakalayamaz. `docs/mac-devir.md:146`: pbxproj'de `DEVELOPMENT_TEAM` yok; `web/.well-known/apple-app-site-association:6`: `"TEAMID.ai.rytho"`.

**Etki** — `dart_defines.local.json` (ya da son `flutter` komutunun `Generated.xcconfig`'i) `test_` anahtarı taşırken yapılan her Release/TestFlight/App Store paketi ilk ekranda bilerek çöker: TestFlight testçisi açamaz, App Review açılış çökmesiyle reddeder (2.1). Dart-define'sız Xcode derlemesinde ikinci kip: paywall geliştirici dizesini gösterir ("Bu derlemede abonelik anahtarları tanımlı değil"). Android kapısının yakaladığı öteki sessiz hatalar da iOS'ta yakalanmıyor: eksik `APPSTORE_APP_ID` (mağaza düğmesiz güncelleme ekranı), development `aps-environment`, AASA yer tutucusu (davetler uygulamayı açmaz), simülatör ML Kit taslaklarının cihaz paketine sızması, çift Google framework'leri.

**Düzeltme**
1. Konsol (U02): RevenueCat App Store uygulaması + `appl_` anahtarı → `REVENUECAT_IOS_KEY`; ASC kaydı açılınca `APPSTORE_APP_ID`.
2. `infra/build-ipa.sh` — bash (Mac'te pwsh garanti değil), `build-aab.ps1`'in aynası:
   - `xcodebuild -version` 26.x olmalı.
   - `REVENUECAT_IOS_KEY` `appl_` ile başlar (boş ya da `test_` → dur); `APPSTORE_APP_ID` sayısal; `RYTHO_PLUS_ENTITLEMENT` dolu.
   - pbxproj'de `DEVELOPMENT_TEAM` var (Xcode'da takım seçilince yazılır); AASA appID == `${DEVELOPMENT_TEAM}.ai.rytho` ve `TEAMID` literali kalmamış. `backend/tests/test_ios_config.py` da `TEAMID`'de düşecek şekilde sıkılaştırılır.
   - Derleme: `flutter build ipa --release --dart-define-from-file=dart_defines.local.json`; `--export-options-plist` yalnız `ExportOptions.plist` (method app-store-connect) commit edilince.
   - Derleme sonrası: `ios/Flutter/Generated.xcconfig`'teki `DART_DEFINES` base64 çözülüp `test_` içermediği doğrulanır (.xcarchive xcconfig taşımaz). `Runner.app` üstünde: `appl_` baytları `Frameworks/App.framework/App`'te; `codesign -d --entitlements :-` → `aps-environment=production`, `get-task-allow` false, applesignin ve associated-domains var; `MLKitSimulatorStubs` sembolü yok; GoogleService-Info `BUNDLE_ID == ai.rytho`; izin metni listesi beklenenle aynı.
   - Asla otomatik yükleme. CLAUDE.md §4'e doktrin satırı.
   - Xcode Organizer şartsa önce `flutter build ios --config-only --release --dart-define-from-file=dart_defines.local.json` — `Generated.xcconfig` gerçek anahtarı taşısın.
3. Kod güvenlik ağı — `initBilling`'den yalnızca dönmek YETMEZ; kapı platforma özgü olmalı ve her çağrı yeri ona uymalı:
   ```dart
   String get _aktifRcAnahtari => defaultTargetPlatform == TargetPlatform.iOS
       ? kRevenueCatIosKey : kRevenueCatAndroidKey;
   bool get billingConfigured => _aktifRcAnahtari.isNotEmpty &&
       !(!kDebugMode && _aktifRcAnahtari.startsWith('test_'));
   ```
   `initBilling` `_aktifRcAnahtari`'nı kullanır. Bu tek değişiklik logIn/getOfferings/purchase'ı yapılandırılmamış SDK'dan korur (hepsi zaten `billingConfigured` arkasında), boş iOS anahtarı çökmesini giderir ve release/profile'daki `test_`'i paywall'ın "satın alma kullanılamıyor" durumuna çevirir. İsteğe bağlı: `test_` koşulunda Crashlytics non-fatal.

**Ek (2026-10-24) — kısmen kapandı: `09bbe23`** — Kod yarısı Mac'te iki turda yazıldı ve ölçüldü (ilk yazım + aşağıdaki çürütme bulgularının düzeltmesi); iki tur bu dala tek commit olarak girdi. O ağaçta tam takım: `flutter analyze` temiz, `flutter test` 1759/1759, pytest 2983 geçti / 2 atlandı.
- **Kod ağı (Düzeltme 3)** — `lib/core/subscription.dart` `rcEtkinAnahtar(platform, yayinDerlemesi, androidAnahtari, iosAnahtari)` platforma özgü: iOS yalnız iOS anahtarına, Android yalnız Android anahtarına bakar; başka platformda anahtar yok. Yayın derlemesinde (Release + Profile, `kReleaseMode || kProfileMode` — Podfile Profile'ı `:release`'e eşliyor, DEBUG ikisinde de tanımsız) `test_` önekli anahtar = **yapılandırılmamış**: `Purchases.configure` hiç çağrılmaz, `billingConfigured` false. `billingConfigured` ve `initBilling` aynı seçiciden (`_etkinRcAnahtari`, iki sabitin tek okuyucusu) okuyor — ikisinin ayrı karar verdiği "yapılandırıldı deyip configure etmeyen" hâl kalktı. Düzeltme'nin taslağına ek olarak `ensureBillingIdentity`'nin ilk satırı kapı (`SatinAlmaYapilandirilmamis` → `purchaseErrorText` → `l10n.billingUnavailable`, "Satın alma şu an kullanılamıyor"): "Satın alımları geri yükle" düğmesi paywall'da ve Abonelik ekranında her zaman görünür ve kapısızdı; yapılandırılmamış SDK'da PurchasesHybridCommon 17.55.1 `CommonFunctionality.swift:18-22` `sharedInstance` `fatalError` veriyor (`appUserID`, `logIn`, `restorePurchases` oradan geçiyor). Yani yalnız `configure`'u atlamak çöküşü bu düğmeye taşırdı; kapı o yolu kapatıyor. Satın alma, paket alımı ve geri yükleme üçü de bu kapıdan geçiyor. Debug'da `test_` çalışmaya devam eder (Test Store simülasyonu). Bekçi `test/satin_alma_yapilandirma_test.dart`.
- **`infra/build-ipa.sh` (Düzeltme 2)** — bash 3.2 + gömülü `/usr/bin/python3`, `build-aab.ps1`'in aynası. Kipler: **tam** (ön kapılar → `flutter build ipa --release --dart-define-from-file` → paket + imza kapıları), **`--kuru`** (yalnız ön kapılar, derleme yok), **`--yalniz-denetle <.app|.ipa>`** (yalnız paket kapıları). Hiçbir şeyi yüklemez. İmzasız .app'te imza kapıları **"ATLANDI (imzasız)"** der, GEÇTİ değil; tam kipte ve `--yalniz-denetle <.ipa>`'da imza zorunlu, imzasız IPA KALDI (çıkış 1). İzin kümesi eşitlikle denetleniyor ve mikrofon BEKLENİYOR (U03). Derleme numarası kapısı Android'in yanmış kodlarını (17/41/43/44/46/48/50/52/53), belirsiz 51'i (ayrı mesaj) ve 54 altını reddediyor — taban gizlilik metnindeki "1.20.0+54" cümlesinden; sahip kararı değil (aşağıda Kalan). Test: `backend/tests/test_build_ipa.py`. CLAUDE.md §4 doktrin satırı 2026-10-24'te yazıldı.
- **Ölçüldü (2026-10-23):** sahte `appl_` anahtarlı gerçek imzasız Release derlemesinde (`flutter build ios --release --no-codesign`, Runner.app 140,0 MB) `--yalniz-denetle` → 6 paket kapısı GEÇTİ, `paket-derleme-numarasi` KALDI (pubspec 53), 3 imza kapısı ATLANDI. Sahte `test_` anahtarlı ikinci derlemede `paket-test-anahtari-yok` KALDI. Çürütme turu ana kopyadaki gerçek `test_` anahtarlı imzasız Release paketinde (`ba6108b`) aynı kipi koştu: `paket-test-anahtari-yok` ve `paket-derleme-numarasi` KALDI, çıkış 1.
- **Ölçülmedi:** `test_` anahtarlı Release/Profile paketinin cihazda gerçekten çökmediği (cihaz yok; Flutter release/profile'ı simülatörde koşturmuyor; iddia Pods kaynağı okumasına dayanıyor). Tam kip gerçek araçla hiç koşmadı (yalnız sahte `flutter` ile). İmza kapıları yalnız sahte `codesign` ve gerçek macOS uygulamalarıyla sınandı — ilk imzalı IPA ölçülmedi.
- **Çürütme turunun bulguları (2026-10-24) — beşi de 2. turda kapandı (`09bbe23`, kapanışlar maddenin sonunda):** çağrı yeri kapılarını (`billingIdentityProvider`, `offeringsProvider`, `tokenPacksProvider`) hiçbir test tutmuyor — üç kapı ayrı ayrı silindiğinde tam takım yeşil kaldı; izin kapısı `NS…UsageDescription` kalıbına uymayan fazladan anahtarı (ör. `NFCReaderUsageDescription`) geçiriyor; baş/son boşluklu define değeri GEÇTİ alıyor (uygulama ham değeri okur); Android anahtarı `test_` iken paket kapısının gerekçesi iOS için yanlış; imzasız `.ipa`'da `--yalniz-denetle` çıkış 0 veriyor. **Kapanış:** çağrı yeri kapıları `test/satin_alma_yapilandirma_test.dart`'ta davranış (MethodChannel kaydedicisi: kanal HİÇ çağrı almıyor) + kaynak bekçisiyle tutuluyor; izin kalıbı `[A-Za-z]*UsageDescription(Dictionary)?`; baş/son boşluklu değer KALDI (`--dart-define-from-file` kırpmıyor, ölçüldü); yeni ön kapı `revenuecat-android-anahtari`, paket kapısının mesajı iki olasılığı adlandırıyor (sahte `test_` Android anahtarı imzasız Release'te `App.framework/App` içinde 0 kez, ölçüldü); imzasız `.ipa` artık çıkış 1. Ek: Crashlytics dSYM fazı imzasız derlemede yüklemiyor.
- **Mutasyon turu (2026-10-24, kendi çalışma kopyalarında, ajan sonrası ana kopyada yeniden koşuldu):** `infra/build-ipa.sh` + `test_ios_config` 11/11 mutasyon KIRMIZI (jeton kapısının beşi dahil). Dart çağrı yeri bekçisinde istenen 22 mutasyon KIRMIZI (7 kapı × sil / her zaman geçer, `rcEtkinAnahtar` `test_` dalı, kayıtsız yeni çağrı, dört yerde kapıyı çağrının altına kaydırma); ek sondada DÖRT YEŞİL çıktı — kapı `/* */` ya da satır sonu `//` yorumuna alınınca veya parantezsiz `if (false)` gövdesine konunca kaynak bekçisi "kapı var" sayıyordu (`purchasePackage`, `purchaseTokenPack`, `yetkiToplayiciProvider`'ın bu dosyada davranış testi yok). Onarım (`886b098`): bekçi yorumları dize-duyarlı atıyor (`_yorumsuz`, iç içe blok yorum dahil) ve kapının bir deyimin başında durmasını istiyor; dördü yeniden koşuldu, dördü KIRMIZI; üç yeni tuzak testi (34/34). Kalan sınır: metin bekçisi her hileyi kapatmaz — iki satın alma işlevi için kanal kaydeden davranış testi yok.
- **App Check debug jetonu kapısı (2026-10-24, `13c92c8`):** `paket-appcheck-jetonu-yok` — define dosyasındaki `APP_CHECK_DEBUG_TOKEN` paketin hiçbir dosyasında geçmemeli (değer basılmaz). Aynı define dosyası yayın derlemesine de veriliyor; jeton yalnız `kDebugMode` dalında okunuyor ve imzasız Release paketinde 0 kez geçtiği ölçüldü (aynı paketteki pozitif kontroller — yetki kimliği ve `kServerClientId` — 1'er kez).
- **Kalan:** konsol — U02 (gerçek `appl_` anahtarı → `REVENUECAT_IOS_KEY`) ve App Store Connect kaydı (→ `APPSTORE_APP_ID`, `docs/mac-devir.md` 4.9 / §4 B4); ilk imzalı IPA ölçümü (imza kapıları: `aps-environment`, `get-task-allow`, yetkiler); derleme numarası kararı (öneri iOS en az 54 — `docs/mac-devir.md` §4 B8; sahip kararı verilmedi, betik bugün öneriyi kapı olarak kodluyor). Sıra `docs/mac-devir.md` §4 B7.

**Android güvenliği** — Android anahtarı değişmez; Android release zaten `test_` taşıyamaz (`build-aab.ps1` reddeder); debug etkilenmez; Android betiğine dokunulmaz.

### U06 — Üçüncü taraf AI'ya (Google Gemini) veri gönderimi için uygulama içi açık onay yok — 5.1.2(i)
✅ kapandı · RET · ikisi · A3 ortak kod · kaynak: `third-party-ai-consent-5-1-2-i`

**⚠️ MODEL DEĞİŞTİ — sahip kararı (2026-10-22/23).** Bu kaydın aşağısı (onay sayfası, kapılar, eşik, Profil anahtarı) Eylül'de Mac'te kurulan modeli anlatır ve **artık yürürlükte değil**. Android'e birleşince sahip sürtünmenin (her açılışta soran sayfa, "Şimdi değil" sonrası kapanan özellikler, şablona düşen bildirim) kendisine sorulmadığını söyledi; Eylül'deki tek kayıtlı karar "ekran iki platformda"ydı. Bugünkü model: kurulumun ilk adımında şartlar kutusunun altında AYRI ve ZORUNLU ikinci kutu, ikisi işaretlenmeden Devam açılmaz; kutu metni sağlayıcı adı taşımaz ("bugün Gemini yarın Claude"), sağlayıcı gizlilik politikasında adıyla; hiçbir özellik onaya bağlı değil; Profil'deki anahtar yok, geri alma = hesabı silmek; 53'ten gelen hesap hiçbir şey görmez, adına kayıt yazılmaz (politikada geçiş cümlesi). Sunucu: yalnız `POST /api/v1/account/ai-consent`, ilk onay anı korunur; `core/ai_consent.py`, `aiConsentMinBuild`, 403 / `ai=0` / teknik satır kapıları ve GET/DELETE uçları silindi (`9078708`, `68040a9` ve izleyen düzeltme commit'i). App Review notu (U18): "Üçüncü taraf yapay zekaya aktarım için açık onay, kurulumun ilk adımındaki ayrı ve zorunlu kutuyla alınır; sağlayıcı ve gönderilen veriler gizlilik politikasında."

**Kanıt** — `lib/` ve `backend/`'de AI onayı durumu ya da ekranı yok (`aiConsent` / `ai_consent` araması boş); Gemini'ye aktarım yalnız gizlilik politikasında anlatılıyor (`lib/features/profile/legal_texts.dart:213`). Günlük okuma, sohbet, raporlar, yüz okuma ve günlük — her çekirdek özellik kişisel veriyi Gemini'ye gönderiyor.

**Etki** — AI sağlayıcısını adıyla anan, gönderilen veriyi listeleyen ve ilk aktarımdan önce izin isteyen ayrı bir ekran yoksa Apple 5.1.2(i) ile reddediyor. Şu an **en olası kesin red**.

**Düzeltme**
- Onay ekranı, onay verilene kadar HER açılışta ya da her AI özelliği açılışında gösterilir; "bir kez gösterildi" diye hatırlanmaz (forumdaki vaka `hasSeenConsent` kısayolu kaldırılana kadar reddedildi).
- İnceleme demo hesabında onay önceden verilmiş OLMAMALI — inceleyici ekranı görmeli.
- "Şimdi değil" AI özelliklerini kapatabilir; ama ekran, verinin yine de gönderildiğini iddia etmemeli.
- App Review notlarına ekran ve geri alma yeri yazılır (U18).
- Sunucu zorlaması `backend/core/app_gate.py` üzerinden `X-App-Build` ile kapılanır ki bugünkü Android kapalı test paketleri çalışsın; `minBuild` ancak onay arayüzlü Android paketi yayınlandıktan SONRA yükseltilir (U29).

Kapandı: `[ORTAK] U06: Gemini aktarimi icin uygulama ici AI onayi` — Önce ölçüldü (backend'de her `gemini_service` / `genai` çağrısı prompt argümanlarıyla okundu): giden veri = haritadan hesaplanan bilgiler (konum/ev/açı/transit/BaZi; Yıl Haritasında güneş dönüşü tarihi ve `sr_relocated` beyanındaki iki şehir adı), sohbet mesajı + son 12 mesaj (ayrıca RAG gömme sorgusu ve `memory_extractor`), I Ching sorusu, hafıza bloğu (sohbetten damıtılan olgular, ruh hâli seyri, son 6 günlük notu), adın (dyad/ilişki `me.displayName`), arkadaşların görünen adı + burcu (dyad, ilişki, sohbet çevre fısıltısı), eklenen kişinin yalnız yakınlık etiketi + haritası, yüz oranları + harita özeti. Genel burç yorumu ve burç bazlı push satırı kişisel veri taşımıyor → kapı dışı. **İstemci:** `lib/core/ai_consent.dart` — onay sayfası (sağlayıcı adıyla, beş veri kategorisi, amaç, reddin neyi kapattığı, gizlilik bağlantısı; "Kabul ediyorum" / "Şimdi değil"), `aiOnayProvider` (sunucu `GET /account/ai-consent` asıl kaynak, `SharedPreferences` önbelleği yalnız ağ yokken), "gördü" bayrağı YOK. Sayfa her açılışta (AppShell; tanıtım paywall'ı ve bildirim izni onu bekler) ve AI özelliği açılışında gelir: sohbet (ekran açılışı + gönderim), I Ching çekimi, yüz okuma (biyometrik rızadan ÖNCE, ayrı). Sağlayıcıyla yüklenen okumalar (günlük, natal, BaZi, Yıl Haritası, İç Takvim, Doğum Heksagramı) `aiOnayiGerektir` ile istek atmadan `AiOnayiGerekli` fırlatır ve ekran hata değil "yapay zeka kapalı" kartı gösterir (tek dokunuşla sayfa); ikili okuma ve ilişki yorumu da aynı kartı gösterir, eksenler/tepkiler çalışır. Sinyaller, transit takvimi ve ilişki ucu onaysız `ai=0` gönderir (hesap gelir, yorum sunucuda hiç üretilmez — ilk açılışta karar verilmeden ana ekran isteği de veri göndermez). Sunucunun işaretli 403'ü (`X-Ai-Consent: required`) interceptor'da sayfayı açar. Geri alma/yeniden verme: Profil > Gizlilik > "Yapay zeka (Google Gemini)" anahtarı (açma yönü sayfadan geçer). **Sunucu:** `users/{uid}/private/aiConsent` (kural değişikliği gerekmez — `users/{uid}` alanı olsaydı `hasOnly` listesi ve dağıtım sırası tuzağı dördüncü kez kurulurdu), `GET/POST/DELETE /api/v1/account/ai-consent`, `AI_CONSENT_VERSION = 1` ↔ `kAiConsentVersion`. Zorlama `core/ai_consent.py`: tam AI uçlarında (`reports/daily,natal,bazi,iching,solar-return,progressions,birth-hexagram,dyad,synastry`, `face/reading`, sohbet — kriz/yasak alan kapılarından sonra, harcamadan önce) 403; yumuşak uçlarda yorum katmanı atlanır; sabah/akşam bildirimi `appBuild` aynasıyla eşiksiz, daha sıkı kararı verir (bkz. düzeltme turu; onaysıza paket okunmaz, teknik satır gider; akşam sorusu gitmez). **Eşik:** `config/app.aiConsentMinBuild` (+ env `RYTHO_AI_CONSENT_MIN_BUILD`), varsayılan 0 = KAPALI; kayıt yoksa yalnız `X-App-Build >= eşik` reddedilir; 0 < eşik ≤ 53 yazılırsa 54'e çekilir (ilk yazımda 45/46'ydı — aşağıdaki 2026-10-22 düzeltmesi). Açık "hayır" (`granted: false`) eşikten bağımsız her sürümde geçerli. Hukuki: uygulama içi gizlilik (TR+EN) "Yapay zeka ile işleme" bölümü aynı kategorilerle yeniden yazıldı, "bildirimler kişiye özel değildir" ve "doğum tarihin/saatin değil" yanlış iddiaları kaldırıldı; `web/legal/gizlilik.html` + `web/en/legal/privacy.html` eşlendi, alt işleyicilere Gemini API eklendi. Ölçüldü: `test/ai_onay_test.dart` (+18: "Şimdi değil" sonrası sayfa ikinci açılışta YİNE geliyor, onaylıyken hiç gelmiyor, geri alınınca yeniden geliyor, kayıt yazılamazsa onay sayılmıyor, sağlayıcı onaysız istek atmıyor ve onayla kendiliğinden kuruluyor, `ai=0` yalnız onaysızken), `backend/tests/test_ai_consent.py` (+36: karar tablosu, eşik/taban, kayıt/geri alma, her AI ucunda bağımlılık, sohbette kapı sırası, 403 + başlık, yumuşak uçlarda LLM çağrısı sıfır, bildirim yolları).
(GEÇERSİZ 2026-10-23 — eşik ve bu App Review talimatı kalktı, yukarıdaki not.) Operasyon (sahibin işi): onay ekranlı kodu İÇEREN ilk Android paketi yayınlanıp kullanıcılar geçtikten SONRA Firestore `config/app` dokümanına `aiConsentMinBuild: <o paketin versionCode'u>` yazılır; o ana kadar eski paketlerde kayıt yoksa AI çalışmaya devam eder (yeni pakette istemci kapısı zaten istek atmıyor). İnceleme demo hesabında onay VERİLMEMİŞ olmalı; App Review notlarına sayfanın her açılışta geldiği ve geri alma yeri (Profil > Gizlilik) yazılır (U18).
Düzeltme turu: `[ORTAK] U06 inceleme: geri tusu reddi kaydediliyor, arka plan bildirimi esiksiz` — (1) Android geri tuşu `isDismissible: false`a rağmen sayfayı kapatıyordu (sonuç null); "veri gönderilmiyor" mesajı çıkıyor ama sunucuya `granted: false` yazılmıyordu. Artık null sonuç "Şimdi değil" gibi kaydediliyor (düğme `false` döndürüp kaydı kendisi yaptığı için çift yazım yok). (2) Arka plan bildirimi (`signal_push` / `midday_push` / `checkin_push`) artık uçlardaki eşikli `izin_karari`yı DEĞİL `arka_plan_karari`yı kullanıyor: geçerli onay → evet; açık hayır → hayır; kayıt yok → yalnız sürüm aynası `0 < appBuild <= ONAY_EKRANSIZ_SON_BUILD` (onay ekranı olmayan paket; yazıldığında 45, bugün 53) ise evet. Eşik 0 iken de, sayfayı görüp karar vermeden çıkan yeni sürüm ve iOS kullanıcısının haritası sabah Gemini'ye gitmiyor — gizlilik metninin "AI işlemeye izin verdiysen" cümlesi bu yolda eşikten bağımsız doğru. Aynası olmayan profil (0) izinli sayılmıyor; ekransız bir 46 çıkarsa bedeli yalnız teknik satır. Ölçüldü: `test/ai_onay_test.dart` +1 (geri tuşu → `geriAlSayisi == 1`, sonra düğme → 2; eski kodda 0 döndüğü ölçülerek doğrulandı), `test_ai_consent.py` +3 (karar tablosu, eşik 0'da 46 kullanıcısına sabah teknik satır + akşam sorusu yok ve paket okunmuyor, kayıt okunamazsa hayır). AI satırının kendisini sınayan dört bildirim test dosyasına onay pini eklendi.
Yayın sırası (sahibin işi): güncellenen web gizlilik politikası (`web/legal/gizlilik.html`, `web/en/legal/privacy.html`) "uygulama içinde ayrıca izin istiyoruz" diyor; bu cümle onay ekranı olmayan Android paketleri (≤ 53) için eşik yükseltilene kadar DOĞRU DEĞİL — o paketlerde kayıtsız kullanıcının uç istekleri ve sabah satırı Gemini'ye gitmeye devam ediyor. Hosting dağıtımı onay ekranlı Android paketinin (ya da iOS'un) yayınıyla aynı güne konur ve `aiConsentMinBuild` o paket yayına çıkıp kullanıcılar geçer geçmez yazılır; ikisinin arasındaki süre politikanın eski paketler için doğru olmadığı geçiş penceresidir.

(TARİHÇE — sabit ve bekçisi 2026-10-23'te modülle birlikte silindi.) Düzeltme (2026-10-22, birleşmeden sonra Mac'te ölçüldü): `ONAY_EKRANSIZ_SON_BUILD` 45 → **53**. Sabit, Mac sıradaki Android paketini 46 sanırken yazılmıştı; oysa onay ekranı Android dalına ancak `8d6f67b` ile girdi ve Windows 46…53'ü ekransız yayınladı (`33bb9f4`'te `ai_consent.dart` yok, sürüm 1.20.0+53; 52 ve 53 açık testte). 45'te kalsaydı U17'nin şart koştuğu backend deploy'u yayındaki 46–53 kullanıcılarının BÜTÜNÜNÜN sabah cümlesini teknik satıra düşürür, akşam sorusunu keserdi — onay verecek ekranları da yoktu; 46–53 arası yazılan bir eşik ise onlarda sohbeti kilitlerdi. Yukarıdaki "ekransız bir 46 çıkarsa bedeli yalnız teknik satır" değerlendirmesi tek bir sapkın paket için yapılmıştı, sekiz sürümün tamamı için değil. Bekçi: `test_ai_consent.py::test_yayindaki_ekransiz_android_surumleri_eski_istemci_sayilir` (45'te kırmızı görüldü). Onay ekranlı ilk Android paketi **54** olacak; `aiConsentMinBuild` o yüzden 54 yazılır.

**Android güvenliği** — Sahibin kararı: ekran iki platformda. Sunucu zorlaması build numarasıyla kademelendiği için eski Android paketleri kırılmaz.

**Birleşme notu (2026-10-22, `8d6f67b`; TARİHÇE — 2026-10-23'ten beri hiçbir çağrı onaya kapılı değil)** — Windows'un 27 Eylül'den sonra eklediği AI yüzeyleri için kapsam yeniden ölçüldü. Sunucu: kişisel veri taşıyan her Gemini çağrısı kapılı (sohbet, rapor uçlarının hepsi, takvim yorumu, ilişki, sabah/öğle paketi, akşam sorusu); kapı dışı yalnız burç bazlı genel yorum ve bildirim satırı (kişisel veri yok). İstemci: AI ucu çağıran her yer kapılı. Windows'un ortak okuma kabına (`OkumaKabi`) tek koruma dalı eklendi: `OkumaHata(AiOnayiGerekli)` → onay kartı; ilişki ucunun `reading_ai_off`ı aynı temsile çevrildi. Sohbet kapısı Windows'un P-turu akışına yerleşti (kriz/yasak alan kapılarından sonra, cihaz kilidi ve harcamadan önce). Gizlilik politikası (dört kopya) ve onay ekranı metni öğle bildirimini, akşam sorusunu ve takvim yorum satırlarını da sayıyor.

**Ek (ölçüldü 2026-10-23; 2026-10-24'te sahip kararına göre düzeltildi) — yeni modelin kalan riski** — Kod kapalı ve doğru yerde: `onboarding_wizard.dart:113` (`'welcome' => riza && aiRiza`), ikinci kutu `:690-694`; kutu metni (`app_tr.arb:10`) sağlayıcıyı adlandırmıyor, ad yalnız gizlilik politikasında (`legal_texts.dart:274` / `:686`, "Gemini API"). **Sahip kararı (CLAUDE.md §7, 2026-10-22/23):** kutu sağlayıcı adını bilerek taşımaz ("bugün Gemini yarın Claude"), sağlayıcıyı gizlilik politikası adıyla anar; 53'ten gelen hesaplara bir şey sorulmaz, politika geçiş cümlesiyle anlatır. Bu kararın bilinen 5.1.2(i) riski: bu kaydın kendi Etki satırı Apple'ın "sağlayıcıyı adıyla anan ayrı ekran" beklediğini yazıyor, ve Android ≤ 53'te kurulumu bitmiş bir hesap iOS'a girince kutuyu hiç görmüyor. **Sahip kararı 2026-10-24: risk kabul edildi** — kutu adsız kalır; Apple itiraz ederse o gün yeniden konuşulur. Kutuya ad eklemek ya da eski hesaplara bir şey göstermek bu kararı değiştirmektir; yalnız sahip yeniden açabilir (onay akışını değiştiren her şey önce sahibe sorulur, CLAUDE.md §7). *(Düzeltme 2026-10-24: bu Ek'in ilk hâli "kutuya sağlayıcı adının eklenmesi" ve "eski hesaplar için tek seferlik bilgilendirme"yi açık seçenek diye sunuyor, verilmiş kararı anmıyordu.)* İnceleme yanı: kurulumu bitmiş demo hesapla giren inceleyici kutuyu hiç görmez (U18 ek). Ayrıca canlı backend'de kanıt ucu yok — `POST /api/v1/account/ai-consent` → 404 (bkz. `docs/mac-devir.md` §4 "Deploy bağımlılıkları" 1 — kurallar + backend birlikte, CLAUDE.md §7 adım 3'teki sayımdan sonra).

### U07 — App Store boyutunda ekran görüntüsü yok
⏳ açık · RET · ikisi · A4 mağaza · kaynak: `store-screenshots-play-only-ipad-required`, `store-screenshots-ipad`

**Kanıt** — Tek hat `infra/store-screenshots.py` → `store/play/` altında 1080x1920 Play kareleri. `ios/Runner.xcodeproj/project.pbxproj:498, 629, 682` — `TARGETED_DEVICE_FAMILY = "1,2"`: iPad açıkken 13" iPad görüntüleri de zorunluydu (U10 ile kapandı).

**Etki** — ASC 1080x1920 kabul etmez; 6.9" iPhone görüntüleri olmadan sürüm gönderilemez. Android durum/gezinme çubuğu taşıyan kareler 2.3.3/2.3.10 riskidir: görüntüler uygulamayı iOS'ta göstermeli, başka platformun arayüzünü içermemeli.

**Düzeltme** — iPhone 17 Pro Max simülatöründen (1320x2868, 6.9") `xcrun simctl io booted screenshot`; yalnız iOS arayüzü, asla Android karesi değil; demo hesap, gerçek hesaplanmış haritalar (U19). `infra/store-screenshots.py` App Store tuvali için parametrelenir (yol ve boyut) ya da Mac uyumlu ayrı bir profil `store/app-store/`'a yazar; ham simülatör kareleri doğrudan da yüklenebilir. Yükleme ASC'de, sahibin işi. iPad görüntüsü gerekmez (U10).

---

## BOZUK — özellik iOS'ta çalışmaz

### U08 — iOS push için konsol önkoşulları (APNs anahtarı, App Attest kaydı)
⏳ açık · BOZUK · hesap · A1 hesap · kaynak: `ios-push-console-prereqs`

**Kanıt** — `docs/mac-devir.md:170-173` (§4.6) APNs anahtarı sahibin işi olarak açık. `lib/main.dart:120-122` release'te `AppleAppAttestProvider` kullanıyor ve App Check zorlaması Firestore'da AÇIK (CLAUDE.md §6): App Attest kaydı yoksa istemci `users/{uid}.fcmToken`'ı yazamaz.

**Etki** — Hiçbir push türü (günlük, check-in, seri, arkadaş, geri bildirim) iOS cihaza ulaşmaz — simülatörde de TestFlight'ta da. Anahtar yüklense bile App Attest kaydı yoksa TestFlight'ta jeton hiç yazılmaz.

**Düzeltme** (sahip, sırayla)
1. developer.apple.com → Keys → + → APNs → Configure: Environment = "Sandbox & Production", Key Restriction = "Team Scoped (All Topics)" ya da `ai.rytho`'ya konu-bağlı. .p8 **yalnız bir kez** indirilir; Key ID ve Team ID not edilir. *(Düzeltme 2026-10-24: Apple'ın güncel belgesine göre ekip anahtarları Sandbox YA DA Production ile sınırlı, ortam başına en çok 2; "Sandbox & Production" yalnız MEVCUT anahtarlar için destekleniyor ve Apple ortama özel anahtar öneriyor. Ekranda seçenek yoksa iki anahtar (Sandbox + Production) açılır; yeni anahtarda seçeneğin sunulup sunulmadığı ölçülemedi. `docs/mac-devir.md` §4 A5.)*
2. Firebase Console (rhytoai) → Project settings → Cloud Messaging → Apple app configuration (`ai.rytho`) → APNs Authentication Key → .p8 + Key ID + Team ID. *(Düzeltme 2026-10-24: tek alan değil — Firebase belgesi (2026-10-22, bölüm adı "iOS app configuration") development ve production anahtarını ayrı sayıyor: "development key, production key, or both", en az biri şart. Eksik ortamın jetonlarına gönderim sessiz değil: FCM `THIRD_PARTY_AUTH_ERROR` (401) döner, panel testi "Gönderim başarısız" gösterir.)*
3. Identifiers → `ai.rytho`: Push Notifications, Associated Domains, Sign In with Apple — ve `54130b9` yorumuna göre App Attest — AÇIK.
4. Firebase iOS uygulamasında Team ID dolu mu bakılır; sonra App Check → `ai.rytho` → App Attest sağlayıcısı kaydedilir (debug token simülatörde zaten kullanılıyor). Kod tarafı U42. App Attest simülatörde çalışmaz, yalnız TestFlight'ta doğrulanır. *(Düzeltme 2026-10-24: "yalnız TestFlight'ta" yanlış — Apple'a göre yetki `production` iken geliştirme imzalı derleme de üretim App Attest sunucularını kullanır; kayıttan sonra cihazda `flutter run --profile --dart-define-from-file=dart_defines.local.json` ile TestFlight'tan önce denenir. Debug App Attest kullanmaz (`AppleDebugProvider`); `--release` önerilmez (aps production yüzünden geliştirme imzasında düşebilir). `docs/mac-devir.md` §4 B2.)*
5. Simülatör (Debug, sandbox jeton): giriş → `users/{uid}.fcmToken` yazıldı mı → panelden "kendime test gönder" (`notify_runner.test_send`) → banner (uygulama ön plandayken ancak U14'ten sonra). *(Ek 2026-10-24: derleme `flutter run --dart-define-from-file=dart_defines.local.json` ile — define'sız Debug kayıtsız bir App Check debug jetonu üretir, giriş ve `fcmToken` yazımı App Check yüzünden düşer ve suç APNs anahtarına atılır; `docs/mac-devir.md` §4 A6–A7.)*
6. TestFlight (Release, production): tekrar. Cloud Run günlüklerinde auth hatasıyla `failed` dönüyorsa anahtarın ortamı ya da kısıtı yanlıştır.

**Ek (ölçüldü 2026-10-23)** — Bir adım eksikti (4a — debug jetonu), cihaz testinin önünde; sıralı ve tam yollu hâli `docs/mac-devir.md` §4 (A2, A5, A6, B1, B2). *(Düzeltme 2026-10-24: burada "İki adım eksikti" yazıyordu ve ilki 3a'ydı; oysa adım 3 App Attest'i zaten sayıyor.)*
- **Adım 3'ün App Attest yeteneği** U08'de vardı ("`54130b9` yorumuna göre"), ama `docs/mac-devir.md` §4.5 yalnız üç yetenek sayıyordu; orada dördüncü olarak eklendi (§4 A2). Entitlements iki dosyada da `com.apple.developer.devicecheck.appattest-environment = production` taşıyor (`Runner.entitlements:53-54`, `RunnerRelease.entitlements:53-54`). Yol: developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → `ai.rytho` → Capabilities → App Attest. App ID'de kapalıysa profil yetkiyi taşımaz ve imza düşer.
- **4a — Gerçek cihazda Debug için App Check debug jetonu.** Debug derlemesi `AppleDebugProvider` kullanıyor (`main.dart:177-181`); eklenti her kurulum için yeni jeton üretip yalnız konsola basıyor (`FirebaseAppCheckPlugin.swift:318-325`, "Firebase App Check Debug Token: …"); şemada sabit jeton yok (`Runner.xcscheme`'de `FIRAAppCheckDebugToken` geçmiyor). Yol: Firebase Console → Security → App Check → Apps → `ai.rytho` (iOS) → ⋮ → Manage debug tokens → Add debug token (2026-10-24: "Security" katmanı eklendi — Firebase belgesi App Check'i o grubun altında veriyor). Eklenmezse zorlama açık olduğu için giriş, Firestore ve Storage reddedilir. Belirti App Check'e özgü bir hata DEĞİL: iOS'ta `activate()` yalnız sağlayıcıyı kaydeder ve düşmez; kayıtsız jeton ancak jeton değişiminde reddedilir. Kullanıcı App Check'e özgü bir mesaj görmez: giriş genel "Bir şeyler ters gitti. Tekrar dene." metniyle düşer (`authFailed`; simülatörde ölçüldü 2026-10-24) — yanlış şifre metninden ("Giriş yapılamadı. Şifren hatalı olabilir…") farklı, ama başka beklenmedik hatalardan ayırt edilemez; Firestore/Storage'da izin hatası çıkar (`core/app_check_izi.dart:3-16`). Debug'da tek iz Xcode konsoludur; Release/TestFlight'ta Crashlytics'e `app-check-token` kaydı düşer (U30). *(Düzeltme 2026-10-24: burada "`activate()` hatası yutulduğundan uygulama giriş ekranında sessizce kalır" yazıyordu — `main.dart:188-190`'daki catch bu durumda hiç çalışmaz.)* Adım 4'teki "debug token simülatörde zaten kullanılıyor" iddiası bu Mac'ten **ölçülemedi**; doğru olsa bile o jeton simülatör kurulumuna bağlı, cihaza geçmez. Jeton gizli bir değerdir — depoya ve sohbete yazılmaz. *(2026-10-24: sabit jeton — `dart_defines.local.json`'da `APP_CHECK_DEBUG_TOKEN` doluysa her Debug kurulumu o jetonu kullanır ve Firebase'e bir kez eklenir; simülatörde ölçüldü (kayıtsızken `exchangeDebugToken` 403, kayıtlıyken 200 ve giriş), aynı define'la derlenen cihaz Debug'ı da aynı jetonu taşır — cihazda ölçülmedi. Adım 4'teki iddia artık bu yolla ölçüldü. `docs/mac-devir.md` §4 A6.)*
- **Adım 4'ün Team ID yolu:** Firebase Console → Project settings → General → Your apps → iOS `ai.rytho` → Team ID = `292WJ9TP74`; ardından App Check → Apps → `ai.rytho` → App Attest → Save. Kayıt yoksa Release/Profile/TestFlight paketi jeton alamaz ve giriş yapılamaz; cihazda `flutter run --release` de giriş ekranında kalır. *(Düzeltme 2026-10-24: yol Security → App Check → Apps sekmesi; Team ID alanı yanındaki düzenleme simgesiyle değişiyor (simgenin adı ölçülmedi). Belirti "giriş ekranında kalır" değil, büyük olasılıkla genel "Bir şeyler ters gitti" (debug jetonu reddinde ölçülen sınıf; App Attest için ölçülmedi). Cihaz denemesi `--release` ile DEĞİL yalnız `--profile` ile yapılır: Release `RunnerRelease.entitlements`'taki `aps-environment = production` yüzünden geliştirme profiliyle imzada düşebilir (ölçülmedi); Profile `Runner.entitlements`'ı kullanır. `docs/mac-devir.md` §4 B1–B2.)*
- Durum: konsolun hiçbir adımı ölçülemedi (`firebase`/`gcloud` yok, hesap girişi yok). Paket tarafı hazır: `aps-environment` iki dosyada ayrı, `UIBackgroundModes = [remote-notification]` (derlenen Info.plist'te ölçüldü). Kayıt ⏳ açık kalır.

### U09 — Yüz okuma kamera geometrisi Android sensör karesini varsayıyor
✅ kapandı · BOZUK · kod · A2 iOS kod · kaynak: `face-ios-frame-geometry`

**Kanıt** — `lib/features/face/face_detection.dart:90-101` `rotatedImageSize` sensör açısı 90/270 ise genişlik ile yüksekliği yer değiştiriyor; `:107-119` `cameraRotationDegrees` ve `:121-128` `_rotation` açıyı sensör yönelimine göre hesaplıyor. `lib/features/face/face_capture_screen.dart:926-927` ön kamerada `mirrored: true`; `lib/features/face/face_segmentation.dart:528` saç çizgisi maskesi aynı açıyı kullanıyor. Galeri yolu (`face_still.dart`) etkilenmiyor.

**Etki** — Gerçek iPhone'da ML Kit dik ve aynalanmış bir BGRA kare alır (ör. 480x640) ve koordinatları o uzayda döndürür. Uygulama onları yer değiştirmiş 640x480 "döndürülmüş" boyutla karşılaştırıyor — bir zamanlar Android deklanşörünü hiç açtırmayan hatanın aynısı. Saç çizgisi maskesi landmark'lara göre 90° dönük kalır: alın / San Ting ölçümü düşer ya da yanlış çıkar. Tarama noktaları iki kez aynalanıp yüzün yanlış tarafına düşer. Simülatörde görülemez (ML Kit ve TFLite orada dışlı) ve sahibin iPhone'u yok: ilk kez TestFlight'ta ya da App Review'da görünür. Yüz okumayı bitiremeyen inceleyici 2.1 ile reddedebilir.

**Düzeltme**
- iOS'ta `rotatedImageSize` → `Size(image.width, image.height)`, `cameraRotationDegrees` → 0, `mirrored = false`. Dallanma `defaultTargetPlatform` üzerinden, ki testler geçersiz kılabilsin.
- Yatayda da doğru kalır: `camera_avfoundation` cihaz dönünce akış tamponunu yeniden yönlendiriyor, yani ham tampon boyutu her zaman ML Kit'in koordinat uzayıdır.
- `InputImageMetadata.rotation`'a dokunulmaz (iOS onu yok sayar).
- `test/scan_mapping_test.dart` yanına iOS geçersiz kılma testleri.
- Tek gerçek doğrulama cihazda: deklanşör açılıyor, alın ölçülüyor, noktalar iki lenste de yüzün üstünde. Sahibin kararıyla bu ilk kez App Review'da görülebilir — kabul edilen risk.

Kapandı: `[iOS] U09 U23: yuz okuma kare geometrisi ve izin reddi` — Kanıt eklenti kaynağından yeniden okundu (`pubspec.lock` sürümleri): `camera_avfoundation` 0.9.23+2 `DefaultCamera.swift` video bağlantısını ön kamerada `isVideoMirrored = true` kuruyor ve `videoOrientation`'ı cihaz yönüne çeviriyor; akış karesi ve önizleme dokusu aynı tampon; her kamera `sensorOrientation: 90` (sabit); `google_mlkit_commons` 0.11.1 `bytesToVisionImage` `rotation`'ı hiç okumuyor. `face_detection.dart`: tek anahtar `_kareDikVeAynali` (`defaultTargetPlatform == iOS`) — iOS'ta `rotatedImageSize` ham `Size(width, height)`, `cameraRotationDegrees` 0 (segmentasyon maskesi de böylece ham tampon uzayında), yeni `taramaNoktalariAynalanir` iOS'ta iki lenste `false`; `face_capture_screen.dart` aynalama bayrağını ondan alıyor. `InputImageMetadata.rotation`'a dokunulmadı. Düzeltmeye bir ek: iOS'ta `lockCaptureOrientation(portraitUp)` — eklenti tamponu arayüz kilidine bakmadan FİZİKSEL yöne çeviriyor; kilit olmasa yan tutuşta tampon yataya döner, önizleme dikey kutuda bükülür ve noktalar kareyle örtüşmezdi. Kilit düşerse akış durmaz, `kamera-yon-kilidi` diye bildirilir. Galeri yolu (`face_still.dart`) bu yardımcıların hiçbirini çağırmıyor — etkilenmediği doğrulandı. Ölçüldü (`test/scan_mapping_test.dart`, +8): Android'de ön/arka boyut, derece (270/90) ve aynalama eskisiyle aynı; iOS'ta 480x640 tampon takas edilmiyor, iki lenste derece 0 ve `sourcePixel` birebir, aynalama yok; iOS ön kamerada tamponun sol yarısındaki nokta ekranda solda, Android'de karşı tarafta.
Kalan: A5 (U21) — gerçek iPhone'da deklanşörün açıldığı, alının ölçüldüğü ve noktaların iki lenste de yüzün üstüne düştüğü görülmeli. Cihazda ölçülmedi (sahibin 3. kararı: ilk kez TestFlight / App Review'da).

**Android güvenliği** — Değişiklik iOS dalında; Android hesaplaması aynen kalır.

### U56 — `app_settings` 8.0+ iOS'ta yalnız SwiftPM: birleşmiş dal iOS için derlenmiyor
⏳ açık · BOZUK · kod · A3 ortak kod · kaynak: birleşme sonrası ölçüm (2026-10-22)

**Kanıt** — `8d6f67b` (`ios-hazirlik` → `yuz-okuma-cihaz-usti-olcum`) sonrası `LANG=en_US.UTF-8 flutter build ios --simulator --debug`: *"The following plugin(s) are only compatible with Swift Package Manager: app_settings"* ve derleme durur. `pubspec.yaml` `app_settings: ^9.0.0` (Windows, D3 `b9b81c7`, 2026-10-10); `enable-swift-package-manager: false` (bu denetimin U25'i, `4ba7d9d`). Eklentinin değişiklik günlüğü: 8.0.0 "BREAKING: Drop CocoaPods support for iOS and macOS"; son CocoaPods sürümü 7.0.0; `openAppSettings` API'si 7→9 değişmedi. 8.0.1–8.0.3'ün Android değişiklikleri AGP 9 derleme uyumluluğu; proje AGP 9.0.1 (`android.builtInKotlin=false`, `android.newDsl=false`). Kullanım: `lib/features/face/face_capture_screen.dart` (kamera reddi "Ayarları aç") ve `lib/widgets/izin_kapisi.dart`. `flutter test` (1668) ve `flutter analyze` yeşil — kusur yalnız iOS derlemesinde görünür.

**Etki** — iOS paketi hiç üretilemez: simülatör, TestFlight, App Store. İki makinenin kararı çakıştı: Mac U25'te Google kütüphanelerinin iki kez bağlanmasını SPM'i kapatarak çözdü, Windows iki hafta sonra SPM'e geçmiş bir eklenti ekledi; ikisi ayrı dallardaydı.

**Düzeltme** — sahip kararı bekliyor. Seçenekler: (a) `app_settings: 7.0.0`'a sabitlemek — iOS'ta CocoaPods var; Android derlemesi AGP 9.0.1 altında Mac'te ÖLÇÜLEMEDİ (Java yok), Windows `infra/build-aab.ps1` ile ölçmeli. (b) Eklentiyi kaldırmak — iOS'ta mevcut `uygulamaAyarlariniAc` (`app-settings:`, U23); Android için ayrı bir yol (yerel kod ya da başka eklenti) gerekir ve cihazda ölçülmeli. (c) SPM'i açmak — U25'i geri getirir, önerilmez.

**Android güvenliği** — (a) Android paketinin bağımlılığını düşürür; yayın öncesi Windows'ta derlenip cihazda kamera reddi + bildirim izni kapısı ölçülür.

**Karar ve durum (2026-10-22)** — sahip (a)'yı seçti: `app_settings: 7.0.0` (pubspec'te gerekçesiyle). Ölçülen: `flutter build ios --simulator --debug` geçti (`Podfile.lock`'a yalnız `app_settings` podu eklendi), uygulama iPhone 17 Pro / iOS 26.5 simülatöründe açıldı ve giriş ekranı çizildi; `flutter test` 1668/1668, `analyze` temiz. **Kalan:** Android derlemesi 7.0.0 ile (AGP 9.0.1 + Kotlin 2.3.20; eklentinin `kotlinOptions`'ı risk) — Windows `infra/build-aab.ps1`; cihazda "Ayarları aç" iki yüzeyde.

---

## YÜKSEK

### U10 — iPad desteği açıktı: tek yönlü kapı
✅ kapandı — `54130b9` · YÜKSEK · ikisi · A2 iOS kod · kaynak: `ipad-support-enabled-one-way-door`; iPad kısımları: `store-screenshots-play-only-ipad-required`, `store-screenshots-ipad`, `ipad-share-origin-and-save-image`

**Kanıt** — `ios/Runner.xcodeproj/project.pbxproj:498, 629, 682` üç yapılandırmada `TARGETED_DEVICE_FAMILY = "1,2"`. `ios/Runner/Info.plist:111-116` iPhone'da yatayı da açıyor (yön kilidi yok); `:117` `UISupportedInterfaceOrientations~ipad` dört yön.

**Etki** — iPad açıkken ASC 13" iPad görüntüsü olmadan gönderimi kabul etmez; inceleyici iPad'de test edebilir (dikey öncelikli yerleşimler, yatayda yüz kamerası, Split View; 2.4.1) — sahibin iPad'i yok. iPad'i destekleyen bir sürüm bir kez yayınlanınca sonraki paketler iPad'i bırakamaz.

**Düzeltme** (sahibin kararı: yalnız iPhone)
- Runner hedefi → General → Supported Destinations → yalnız iPhone → `TARGETED_DEVICE_FAMILY = 1`. iPad'de uyumluluk kipinde çalışır; iPad görüntüsü gerekmez, paylaşım sayfası orada düz sayfa açılır. `UISupportedInterfaceOrientations~ipad` silinebilir; iPhone yatayının bilinçli olup olmadığına karar verilir.
- `54130b9`: üç yapılandırmada `TARGETED_DEVICE_FAMILY = 1`, **yalnız dikey** yön, `~ipad` listesi kaldırıldı; derlenen `Runner.app`'te `UIDeviceFamily=[1]` ölçüldü (commit mesajı).
- Bu kararla kapanan iPad parçaları: U07 (iPad görüntüleri), U32 (iPhone+iPad eşzamanlı abonelik senaryosu), U44 (iPad'de paylaşım balonu konumu).

**Ek (ölçüldü 2026-10-23)** — Karar kodda duruyor: imzasız Release paketinde `UIDeviceFamily = [1]`, yalnız dikey; `TARGETED_DEVICE_FAMILY = 1` üç yapılandırmada. Ama "iPad'de uyumluluk kipinde çalışır" cümlesi **ölçülmemiş bir iddia**: bu Mac'teki 12 iPad simülatörünün (iOS 26.5 ve 27.0) hiçbirinde Rytho kurulu değil. *(→ 2026-10-24: iPad (A16, iOS 27.0) simülatörüne kuruldu ve açıldı — 2026-10-23 20:53, yani bu ölçümden SONRA; giriş yok, gezinti sonucu kayıtlı değil.)* İnceleyici iPhone uygulamasını iPad'de açabilir (2.4.1). Kalan: A5 — bir iPad simülatöründe giriş, kurulum, klavye, paylaşım sayfası ve kamera izni akışı (kamera simülatörde yok) gezilir (`docs/mac-devir.md` §4 C11).

### U11 — iOS bildirim izni girişten hemen sonra soruluyor
✅ kapandı · YÜKSEK · kod · A2 iOS kod · kaynak: `ios-notif-prompt-at-signin`, `ios-notification-prompt-fires-at-login`, `ios-permission-prompt-at-login`

**Kanıt** — `lib/core/notifications.dart:294` `iOS: DarwinInitializationSettings()`: varsayılan `request*Permission: true`, yani `flutter_local_notifications`'ın `initialize()`'ı iOS'ta sistem diyaloğunu açıyor. Planlanan yol `:171-190` `ensureNotificationPermissionAsked` → `FirebaseMessaging.requestPermission()` (onboarding `_BildirimAdimi`, `lib/features/onboarding/onboarding_wizard.dart:735`); `Analytics.notificationPermission` `:190`'da.

**Etki** — Sistem bildirim diyaloğu ilk girişin hemen ardından, bağlamsız ve onboarding değeri anlatmadan çıkar. iOS yalnız bir kez sorar; refleks "İzin Verme" kalıcıdır ve push'a dayalı elde tutma döngüsü zarar görür. Zamanlanmış `ensureNotificationPermissionAsked` etkisizleşir; `Analytics.notificationPermission` ise diyalog göstermeyen bir `requestPermission` sonucunu onboarding sorusu gibi kaydeder — metrik çarpılır. Android 13+ etkilenmez: orada eklenti açık istek ister.

**Düzeltme** — `notifications.dart:294`: `iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false)`. `defaultPresent*` bayrakları varsayılanda (true) kalır ki ön plan yerel bildirimleri görünsün. Tek izin isteği `ensureNotificationPermissionAsked` olur. Test: uygulamayı simülatörden sil, giriş yap → diyalog yok; onboarding'i bitir → diyalog `_BildirimAdimi`'nda.

Kapandı: `[iOS] U11 U14 U24 U30 U54: bildirim izni, on plan push, ses oturumu, App Check izi` — `notifications.dart` `yerelBildirimAyarlari`: Darwin `requestAlert/Badge/SoundPermission: false`, `defaultPresent*` varsayılanda; kurulum artık bu sabiti kullanıyor. Kaynakta ölçülen: flutter_local_notifications 22.2.0 `FlutterLocalNotificationsPlugin.m` `initialize:` bayrakları okuyup `requestPermissionsImpl`'e veriyor, o da hepsi kapalıysa diyalog açmadan dönüyor. Tek istek yolu `ensureNotificationPermissionAsked` (onboarding `_BildirimAdimi` ve Gökyüzü'ndeki ilk değer anı). `defaultPresent*` gerekçesi düzeltildi: iOS'ta ön plan sunumuna bu eklenti değil, bildirim merkezi delegesi firebase_messaging karar veriyor (U14) — bayraklar yalnız varsayılanda bırakıldı. Ölçüldü (`test/bildirim_ios_test.dart`): ayar nesnesinde altı `request*` bayrağı kapalı, beş sunum bayrağı açık; kanala giden `initialize` argümanlarında altı `request*` anahtarı `false` ve `requestPermissions` çağrısı yok; kaynak bekçisi kurulumun bu sabiti kullandığını ve varsayılan `DarwinInitializationSettings()`'in geri gelmediğini sabitliyor.
Kalan: A5 — simülatörde uygulamayı sil, giriş yap → diyalog yok; onboarding'i bitir → diyalog `_BildirimAdimi`'nda.

**Android güvenliği** — Darwin ayarları Android'de yok sayılır.

### U12 — Uygulama düzeyinde `PrivacyInfo.xcprivacy` yok
✅ kapandı — `54130b9` · YÜKSEK · kod · A2 iOS kod · kaynak: `no-app-privacy-manifest-static-sdks-uncovered`

**Kanıt** — Tabanda `ios/Runner/PrivacyInfo.xcprivacy` yok. TFLite ve ML Kit Runner'a statik bağlanıyor ve gerekçe isteyen API'ler kullanıyor; uygulama paketinde onları kapsayan manifest yok. `docs/store-privacy-labels.md:100` Identifiers'ı yalnız "User ID" sayıyor.

**Etki** — Yüklemede ITMS-91053 ("Missing API declaration … Runner") gelebilir (FileTimestamp, SystemBootTime, UserDefaults); öteki paket manifestleri aynı kategorileri beyan ettiği için toplamın kabulü belirsiz. Beyansız yüklemeler Mayıs 2024'ten beri engelleniyor. Ayrıca arşivden üretilen gizlilik raporu ML Kit'in toplanan-veri beyanlarını (Device ID, tanılama; bağlantısız) atlar; etiket eksik bir rapordan doldurulur.

**Düzeltme**
- Xcode'da File > New > File > App Privacy, hedef Runner (Copy Bundle Resources'a girsin); `NSPrivacyTracking=false`, `NSPrivacyTrackingDomains=[]`.
- Gerçekten eksik tek beyan `NSPrivacyAccessedAPICategoryDiskSpace` + `E174.1` (MLKitCommon'un kendi manifestinin aynası). FileTimestamp `C617.1`, SystemBootTime `35F9.1`, UserDefaults `CA92.1` da zararsız ve Runner'ı kendini anlatan hâle getirir.
- ML Kit'in manifesti DeviceID, OtherDiagnosticData, PerformanceData, OtherUserContent beyan ediyor (hepsi bağlantısız); bunların etikette "Not Linked" olarak açıklanması kararı U20'de.
- Archive sonrası Organizer > Generate Privacy Report ile DiskSpace'in göründüğü doğrulanır (A5).
- `54130b9`: dört gerekçe beyan edildi, izleme yok; `NSPrivacyCollectedDataTypes` bilerek boş — envanterin tek kaynağı App Privacy etiketi (U20).

### U13 — `FlutterDeepLinkingEnabled` kapatılmamış: davet linki Navigator'a da itiliyor
✅ kapandı (iOS) — `54130b9` · YÜKSEK · kod · A2 iOS kod · kaynak: `flutter-deep-linking-not-disabled`, `ios-flutter-deeplinking-not-disabled`

**Kanıt** — Tabandaki `ios/Runner/Info.plist`'te `FlutterDeepLinkingEnabled` yok (app_links'in iOS kurulum şartı). `lib/main.dart:133-134` release'te her yakalanmamış hatayı `fatal: true` kaydediyor. Davetleri `app_links` işliyor (`lib/core/deep_links.dart`); Flutter derin bağlantısına dayanan adlandırılmış rota yok.

**Etki** — `https://rytho.app/i/<kullanıcı>` uygulamayı açtığında (soğuk ya da ılık) app_links daveti doğru saklar; motor AYRICA `/i/<kullanıcı>`'yı Navigator'a iter. Release'te `WidgetsApp._onUnknownRoute`'tan null-check hatası çıkar ve her davette Crashlytics'e FATAL yazılır — iOS çökmesiz oranı şişer. Çatı bağlantıyı "işlenmedi" saydığından iOS motoru URL'yi `openURL` ile sisteme geri verir: kullanıcı Safari'de yalnız "Google Play'den indir" sunan sayfaya seker (U34). Yol yerel motor ve çatı kaynaklarından izlendi, cihazda koşturulmadı. Android'de de bayrak yok (ılık linkte sahte fatal), ama sisteme geri verme olmadığı için sekme yok.

**Düzeltme**
1. `ios/Runner/Info.plist`: `<key>FlutterDeepLinkingEnabled</key><false/>`. — `54130b9`'da yapıldı.
2. Ana rotayı döndüren bir `onUnknownRoute` EKLENMEZ: her linkte mevcut `_Gate`'in (ve tüm alt ağacının) üstüne ikinci bir `_Gate` iter. Dart bekçisi istenirse kendini hemen kapatan bir rota (`addPostFrameCallback` içinde `maybePop`, gövde `SizedBox.shrink()`); daha iyisi yalnız yerel kapatmalara güvenmek.
3. Android (kendi dalında, isteğe bağlı): `MainActivity` içine `<meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>` — sahte fatal'ları keser.
4. AASA TEAMID düzelince (A5): `xcrun simctl openurl booted https://rytho.app/i/<kullanıcı>`, soğuk ve ılık. Beklenen: Çevrem sekmesi davetle açılır, Safari açılmaz, konsolda "Could not find a generator for route" yok.

### U14 — Uygulama açıkken gelen push iOS'ta hiç görünmüyor
✅ kapandı · YÜKSEK · kod · A2 iOS kod · kaynak: `ios-foreground-push-dropped`

**Kanıt** — `lib/core/notifications.dart:555` `FirebaseMessaging.onMessage.listen(_showForeground)`; `_showForeground` (`:315`) yerel bildirim gönderiyor. Bildirim merkezi delegesi `firebase_messaging`'de; eklenti kaynakları okununca `flutter_local_notifications`'ın hiç geri çağrı almadığı kesinleşti. `docs/mac-devir.md:253-258` (§6) ve CLAUDE.md §7 bu delege sorusunu "cihazda ölçülecek" diye açık bırakıyor — bu bulgu soruyu kaynak okumasıyla yanıtlıyor.

**Etki** — Rytho ön plandayken FCM mesajı `onMessage`'a verir, Dart yerel bildirim gönderir; iOS sunumu delegeye (firebase_messaging) sorar ve "none" alır. Banner sessizce atılır, Bildirim Merkezi'ne de düşmez. Uygulama açıkken gelen arkadaş tepkileri, davetler, günlük/check-in push'ları iOS'ta kaybolur; Android bunları heads-up gösterir.

**Düzeltme** (A seçeneği, en az hareketli parça; `handleNotificationTaps()` içinde)
1. `if (defaultTargetPlatform == TargetPlatform.iOS) await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);` (ayar NSUserDefaults'ta kalıcı).
2. `:555` → `FirebaseMessaging.onMessage.listen((m) { if (defaultTargetPlatform != TargetPlatform.iOS) _showForeground(m); });` — iOS banner'ı yerel olarak FCM gösterir.
3. Bu banner'lara dokunma zaten `didReceiveNotificationResponse` → `onMessageOpenedApp` → `_bildirimAcildi` (`:580-586`) yolundan geliyor; yönlendirme değişmez.
- AppDelegate delege satırı (B seçeneği) EKLENMEZ: `FlutterPluginAppLifeCycleDelegate.mm:471-477` `willPresent`'i İKİ eklentiye de iletir, ikisi aynı completionHandler'ı çağırır; A ile birlikte bildirim iki kez görünür.
- Ardından `docs/mac-devir.md` §6 ve CLAUDE.md §7 güncellenir: delege sorusu çözüldü.
- Test (simülatör, Debug; APNs anahtarı U08): uygulama açık → panelden test push (`backend/services/notify_runner.py:432`, `type=test`) → banner görünmeli → dokun, rotayı kontrol et.

Kapandı: `[iOS] U11 U14 U24 U30 U54: bildirim izni, on plan push, ses oturumu, App Check izi` — A seçeneği aynen: `handleNotificationTaps` önce `iosOnPlanSunumunuAc()` (yalnız iOS; `setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true)`; hata yutuluyor: fırlatsaydı arkasındaki ön plan dinleyicisi ve dokunuş yolları hiç kurulmazdı, hata da kimsenin beklemediği Future'dan yayında FATAL diye düşerdi), sonra `onMessage.listen(onPlanMesajiniIsle)` — iOS'ta yerel bildirim yok, Android'de `_showForeground` aynen. AppDelegate'e delege satırı eklenmedi. Kaynakta ölçülen (firebase_messaging 16.4.3 `FLTFirebaseMessagingPlugin.m`): `willPresentNotification` kayıtlı seçeneği FCM olmayan bildirime de uyguluyor — iOS'ta yerel bildirim de gönderilseydi iki banner çıkardı; `didReceiveNotificationResponse` yalnız `gcm.message_id` taşıyan dokunuşu `onMessageOpenedApp`'e veriyor (soğuk açılışta `getInitialMessage`), yani FCM banner'ına dokunuş `_bildirimAcildi`'ye arka plan push'uyla aynı yoldan geliyor, yerel bir banner'a dokunuş ise hiçbir yere gitmezdi. İki eklentinin sunum seçenekleri ayrı `NSUserDefaults` anahtarlarında (`flutter_firebase_messaging_presentation_options` / `flutter_local_notifications_presentation_options`). `docs/mac-devir.md` §6'daki delege maddesi "çözüldü" diye güncellendi; CLAUDE.md §7'deki aynı not proje talimat dosyası olduğu için bu turda değiştirilmedi, sahibe bırakıldı. Ölçüldü (`test/bildirim_ios_test.dart`): iOS'ta sunum seçenekleri üçü de `true` ve bir kez, Android'de hiç; ayar fırlatırsa yutuluyor; iOS'ta ön plan mesajı yerel gösterimi çağırmıyor, Android'de aynı mesajla çağırıyor; kaynak bekçileri kurulum sırasını, `onMessageOpenedApp` / `getInitialMessage` bağlantısını ve AppDelegate'te `UNUserNotificationCenter` yokluğunu (yorumlar atılarak) sabitliyor.
Kalan: A5 — APNs anahtarı (U08) yüklendikten sonra yukarıdaki test: uygulama açık → panelden test push → banner → dokun, rota.

**Android güvenliği** — Android'de `_showForeground` aynen çağrılır; değişiklikler iOS dalında.

### U15 — Hesap silmede Sign in with Apple jetonu iptal edilmiyor
⏳ açık (kısmen — `[iOS] U04 U15 U31 U45 U48 U49: giris ve hesap silme akisi`) · YÜKSEK · ikisi · A2 iOS kod · kaynak: `apple-token-not-revoked-on-delete`, `apple-token-revocation-missing`, `siwa-token-revocation-missing`, `siwa-token-revocation`

**Kanıt** — `lib/features/profile/delete_account.dart:44-73`: `_delete` doğrudan `DELETE /api/v1/account/me` (`:52`) ve `signOutEverywhere()` (`:59`) çağırıyor, Apple jetonu iptali yok; 401'de `deleteAccountReauth` (`:69`). Backend Auth kullanıcısını Admin SDK ile siliyor (`backend/services/account_service.py:273-349`); Apple tarafındaki yetki yerinde kalıyor.

**Etki** — Hesabını silen Apple kullanıcısı Ayarlar → Apple Kimliği → "Apple ile Giriş" altında Rytho'ya bağlı kalır, Apple yetkisi geçerli kalır; Apple ile yeniden girişte eski yetki sessizce döner (ad/e-posta gelmez). Apple'ın hesap silme rehberi SIWA'lı uygulamalardan jeton iptali bekliyor; inceleyiciler 5.1.1(v) altında Firebase kullanıcısını silip Apple yetkisini bırakan uygulamaları reddetti ya da takip sorusu sordu.

**Düzeltme**
- Kapı: `defaultTargetPlatform == TargetPlatform.iOS` (ya da `appleSignInAvailable`) VE `currentUser.providerData` içinde `apple.com`.
- Sıra: Apple sayfası (`SignInWithApple.getAppleIDCredential`, nonce ile) → aynı kimlik bilgisiyle `currentUser.reauthenticateWithCredential(OAuthProvider('apple.com').credential(idToken, rawNonce))` — `auth_time` tazelenir, mevcut 401 `deleteAccountReauth` yolu kalkar → `FirebaseAuth.instance.revokeTokenWithAuthorizationCode(cred.authorizationCode)` → `DELETE /account/me` → `signOutEverywhere`.
- İptal Firebase kullanıcısı HÂLÂ varken yapılır (backend silmeden önce). Yetki kodu tek kullanımlık ve ~5 dk geçerli; iptalden hemen önce istenir.
- İptal çağrısı başarısız olursa (OAuth code flow ayarı eksik, ağ hatası) silme ENGELLENMEZ — 5.1.1(v) silmenin çalışmasını şart koşar. `FirebaseCrashlytics.instance.recordError(reason: 'apple-revoke')` ile kaydedilip silmeye devam edilir.
- Kullanıcı Apple sayfasını kapatırsa (`SignInWithAppleAuthorizationException`, `canceled`) **kaynaklar ayrışıyor**: `apple-token-not-revoked-on-delete` ve `apple-token-revocation-missing` silmeyi durdurmayı, `siwa-token-revocation-missing` ve `siwa-token-revocation` iptali atlayıp silmeye devam etmeyi söylüyor. Karar kodlamada verilir ve buraya yazılır.
  - **Karar (sahibin onayladığı plan, çelişki çözüldü):** kullanıcının Apple sayfasını KAPATMASI (`canceled`) silmeyi DURDURUR — kullanıcı geri adım atmıştır; sunucuya istek gitmez, sayfada nedenini anlatan TR/EN metin (`deleteAccountAppleCanceled`) görünür. Başka HER hata (Apple sayfası `unknown`, yeniden doğrulamada `user-mismatch`, ağ, eksik OAuth code flow) `apple-revoke` diye Crashlytics'e yazılır ve silme SÜRER.
- Konsol (A1, U01 ile aynı oturum): Apple Developer → Keys → Sign in with Apple etkin anahtar; Services ID (yoksa); Firebase Console → Auth → Apple'da Services ID + OAuth code flow (Team ID, Key ID, .p8). Bunlar yoksa iptal çağrısı düşer.

Kısmen kapandı: `[iOS] U04 U15 U31 U45 U48 U49: giris ve hesap silme akisi` — `auth_service.dart` `appleYetkisiniIptalEt`: kapı iOS + `apple.com`; Apple sayfası (nonce, kapsam yok) → `reauthenticateWithCredential` (aynı ham nonce) → `revokeTokenWithAuthorizationCode`; `delete_account.dart` bunu `DELETE /account/me`'den önce çağırıyor. Yeniden doğrulama başarısızsa iptal KOŞMAZ (başka bir Apple Kimliğinin yetkisi iptal edilmesin). Düzeltmedeki bir gerekçe ölçümle düzeltildi: `backend/api/account.py` `delete_me` yakın giriş şartı koymuyor (Admin SDK `delete_user`), 401 yalnız `core/auth.py`'de jeton doğrulanamayınca dönüyor — yeniden doğrulama 401 yolunu "kaldırmaz", o yol geçersiz jeton için yerinde kaldı; istemcideki "yakın zamanda giriş" yorumu da düzeltildi. Ölçüldü (`test/apple_yetki_iptali_test.dart`, 11): Android'de ve Apple'sız hesapta hiçbir adım koşmuyor; sıra sayfa → doğrulama → iptal ve nonce özeti eşleşiyor; kapatma → vazgeçildi, kayıt yok; `unknown`, `user-mismatch` ve iptal hatası → kayıt + silme sürüyor; sayfada kapatma sunucuya DELETE göndermiyor, başarısız iptal göndermeye devam ediyor.
Kalan: yukarıdaki konsol maddesi (hesap işi; o yapılmadan iptal çağrısı düşer ve yalnız Crashlytics'te `apple-revoke` görünür). Sahibin iletisi (2026-09-27): e-postayla gelen kimlik `292WJ9TP74` — Team ID olduğu Apple Developer → Membership'te doğrulanmalı. Konsol bitince A5: TestFlight'ta Apple hesabıyla sil → Ayarlar → Apple Kimliği → "Apple ile Giriş" listesinde Rytho kalmamalı. *(Düzeltme 2026-10-24: buradaki "A5" bu kaydın lejantındaki test aşamasıdır (cihaz/TestFlight doğrulaması); `docs/mac-devir.md` §4 **A5 = APNs anahtarı**, oraya gidilmez. Bu doğrulamanın aşama adımı `docs/mac-devir.md` §4 **A8** "Hesap silme + Apple yetkisi iptali" (ayrı test hesabıyla, cihazda); konsol önkoşulu §4 C7.)*
**Ek (ölçüldü 2026-10-23)** — `292WJ9TP74`'ün Team ID olduğu yerelde iki kaynakla tutarlı: Xcode'un kayıtlı takımı ve anahtar zincirindeki geliştirme sertifikasının OU'su bu değer (Membership sayfası okunmadı). Konsol maddesinin tam yolu `docs/mac-devir.md` §4 **C7** (A4 ile aynı oturumda yapılabilir). Konsol durumu ölçülemedi; kayıt ⏳ açık (kısmen) kalır.

**Android güvenliği** — Yol iOS + `apple.com` kapısının arkasında; Android değişmez.

### U16 — Backend, RevenueCat'in hiç göndermediği `REFUND` olayını bekliyor
⏳ açık · YÜKSEK · kod · A3 ortak kod · kaynak: `revenuecat-refund-event-never-sent`

**Kanıt** — `backend/api/billing.py:447-455`: paket dalı yalnız `NON_RENEWING_PURCHASE` (kredi) ve `REFUND` (`wallet.debit_refund`, `:451-453`) tanıyor; gerisi "Paket ürününde beklenmeyen olay" (`:455`) diye düşüyor. `:37` `REFUND`'ı `_DEACTIVATING_EVENTS`'e, `:42` `CANCELLATION`'ı "yenilenmeyecek" kümesine koyuyor.

**Etki** — iOS kullanıcısı iadeyi geliştirici onayı olmadan doğrudan Apple'dan alabilir (reportaproblem.apple.com); RevenueCat bunu `CANCELLATION` + `cancel_reason=CUSTOMER_SUPPORT` olarak bildirir. `rytho_tokens_*` için webhook bunu atar; kullanıcı iadeden sonra kredileri tutar — al, harca, iade iste: bedava kredi yolu. İade gelir defterine parasal REFUND olarak da girmez, admin geliri şişkin görünür. `rytho_plus_monthly`'de iade `active=True/willRenew=False` yazılır; erişim ancak RevenueCat `expiration_at_ms`'i iade anına çekerse biter. `REFUND_REVERSED` (yalnız App Store) de yok sayılıyor. Aynı boşluk Android'de de var; ama Apple iadeleri daha sık ve geliştiricinin söz hakkı yok.

**Düzeltme** (`backend/api/billing.py`)
- Paket dalı: `NON_RENEWING_PURCHASE` üründe RevenueCat `CANCELLATION`'ı YALNIZ iade için gönderir → `event_type in ("REFUND", "CANCELLATION")` her `cancel_reason`'da iade: `wallet.debit_refund(uid, product_id, event_id)`, ardından `_record_revenue_event(event, "REFUND", uid)`.
- `REFUND_REVERSED`: ayrı defter anahtarıyla (ör. `reversal-{event_id}`) yeniden kredi — `credit_pack`'in defter anahtarı ilk satın almayla çakışmamalı.
- Abonelik dalı: `CANCELLATION` ve `cancel_reason` (büyük harfe çevrilmiş) `CUSTOMER_SUPPORT` ise `revenueEvents`'e `eventType "REFUND"`, `monetary=True`; aynı `event.id` doküman kimliği, çift kayıt yok. `_bump_revenue_totals` zaten `abs(price)` kullanıyor — doğru, RevenueCat'in iade fiyatı negatif olabilir. `expiration_at_ms` yoksa ya da `<= now` ise `active=False`.
- Sabit `"REFUND"` dalları zararsız takma ad olarak kalır.
- Testler gerçek yüklerle yeniden yazılır (paket ve abonelik için `type CANCELLATION` + `cancel_reason CUSTOMER_SUPPORT`). Güvenmeden önce gerçek şekil RevenueCat test olayı ya da sandbox iadesiyle doğrulanır.

**Android güvenliği** — Play iade yolu aynı olay şeklini kullanıyor; o da düzelir.

### U17 — "Kullanıcıyı engelle" kaydediliyor ama uygulanmıyor; gelen istek engellenemiyor (1.2)
⏳ açık (kısmen — `[ORTAK] U17: engelleme uygulaniyor, gelen istek engellenebiliyor`, `[ORTAK] U17 inceleme: engelleyen davet kapisi, gelen kutusu suzgeci, notr davet hatasi`, `[ORTAK] U17 inceleme 2: kabul ve tepki kurali, sessiz tepki silimi, engel yaniti sizmiyor`, `[ORTAK] U17 inceleme 3: yan kanal kapandi, yorum ayiklayici tek gecis, filtre ve tekillestirme bekcisi`) · YÜKSEK · kod · A3 ortak kod · kaynak: `block-not-enforced`

**Kanıt** — `lib/features/friends/friends_screen.dart:1063-1065` engelleme `removeFriend` + `blockUser` yapıyor, yalnız kabul edilmiş arkadaşın sayfasında. `lib/core/friends.dart:237-242` `sendFriendRequest` iki kenarı tek batch'te yazıyor. `infra/firestore.rules:224-247` `friends` counterpart create dalı (`:237`) `blocked`'a (`:176`) bakmıyor; `backend/api/notify.py:262` `/invite` push'u engeli denetlemiyor.

**Etki** — Engellemeyi deneyen inceleyici, engellenen kullanıcının yeni arkadaşlık isteği ve push gönderebildiğini görür. Kullanıcı adıyla birini bulan yabancı saldırgan bir görünen adla istek atabilir; alıcı kabul etmeden bildiremez de engelleyemez de. İkisi de 1.2'yi düşürür; Koşullar'daki söz tutulmuyor.

**Düzeltme**
- Nudge'lar için yeni kural gerekmez: nudge create kuralı zaten `users/{uid}/friends/{sender}.status == 'accepted'` istiyor ve engelleme önce `removeFriend` çağırıyor.
- `friends` counterpart create dalına `&& !exists(/databases/$(database)/documents/users/$(uid)/blocked/$(request.auth.uid))`. İki kenar tek batch'te yazıldığı için engellenen gönderici temiz bir hata alır — eski Android paketlerinde de.
- `/invite`: hedef göndereni engellediyse push atlanır.
- İstek kutucuğuna Engelle + Bildir: `blockUser`'dan önce `removeFriend(uid)` (iki kenarın batch silinmesi; `counterpart()` delete kuralı izin veriyor).
- Engellenenler listesi (engeli kaldırma), bildirim görünümü ya da uyarısı, 24 saat taahhüdü.

Kısmen kapandı: `[ORTAK] U17: engelleme uygulaniyor, gelen istek engellenebiliyor` — Mac taslağının (aşağıdaki durum notu) NİYETİ birleşmiş tabanda (`b803216`) güncel kalıplarla yeniden yazıldı; stash körlemesine uygulanmadı. **Kural** (`infra/firestore.rules`): `friends` create'in counterpart dalı `&& !exists(/databases/$(database)/documents/users/$(uid)/blocked/$(request.auth.uid))` — `uid` davetin ALICISI, yani alıcının listesine bakılıyor; `'incoming'` yazabilen tek dal bu. `blocked` bloğunda `update` açıldı: engelleme kenar silimiyle tek batch'te yazıldığı için zaten engelli birine yeniden `set` update sayılır ve update kapalıyken batch'in tamamı düşerdi. Dürtme için ayrı kural yok (Düzeltme'deki gerekçe; şart bekçiyle çivili). **Sunucu:** `profile_service.has_blocked(sahip, hedef)` — okuma düşerse ENGELLİ sayar (yalnız isteğe bağlı şeyleri keser: yanlış "engelli" bir bildirimi kaçırtır, yanlış "engelli değil" engelleyene push düşürür); `/notify/invite` alıcı göndereni engellediyse `200 {"status": "skipped", "reason": "engelli"}` (kural dağıtılmadan kurulmuş kenar için); `/contacts/match` engelleyenin kartını engellenene döndürmez (engelleyenin kendi rehberinde kişi görünmeye devam eder). **İstemci:** `lib/core/safety.dart` `kullaniciyiEngelle` — iki arkadaşlık kenarı + engel kaydı TEK batch (eskiden `removeFriend` + `blockUser` iki çıplak `await`ti, hata yutuluyordu; biri düşse ya engelsiz silme ya kenarları duran engel kalırdı). `engellenenlerProvider` (`publicProfiles` kartıyla; kart yoksa satır adsız ama çizilir) okuyucusu OLMAYAN `blockedUsersProvider`ın yerine geçti — o sağlayıcı "akış ve mesajlar bu kümeye göre filtrelenir" diyordu ve hiçbir yer onu okumuyordu. `friends_screen.dart` `GelenIstekKarti`: ⋯ → Engelle / Şikayet et (ikon-tek düğmenin ekran okuyucu adı `semanticLabel`); `showFriendSafetySheet` iki yerden açılıyor, "Arkadaşlıktan çıkar" yalnız kabul edilmiş arkadaşta; engelleme `onayla` (yıkıcı) kapısından geçiyor ve sonucu söylüyor (başarı/hata SnackBar). Profil > Gizlilik > **Engellenenler** (`lib/features/profile/blocked_users_screen.dart`): liste `AsyncBolum` ile (yüklenemeyen liste "kimse yok" DEMİYOR), engeli kaldırma `onayla` ile (yıkıcı değil — geri dönüşü var), arkadaşlığı geri getirmez. **Yanlış beyan düzeltildi:** `blockUserConfirmBody` "{name} seni bulamaz … Bunu Çevrem ayarlarından geri alabilirsin" diyordu — ikisi de yanlıştı: kullanıcı adıyla arama (`usernames` + `publicProfiles` `get`) engellenene KAPANMIYOR ve geri alma yeri hiç yoktu. Yeni metin TR+EN yalnız uygulananı söylüyor (istek/tepki gönderemez, arkadaşlık ya da bekleyen istek silinir, geri alma Profil > Gizlilik > Engellenenler). Ölçüldü: `backend/tests/test_engelleme.py` (12: kural bekçisi yorumları atarak korumayı `incoming` dalının İÇİNDE ve doğru yönde arıyor, `'incoming'` yazan tek dal, dürtmenin `accepted` şartı, `blocked` update izni; `has_blocked` yön + okuma düşünce; davet push'u ve rehber için engelli/engelsiz/ters yön eş testleri), `apps/mobile/test/engelleme_test.dart` (17: istek menüsü, onay, vazgeç, yazım düşünce mesaj, şikayet, kabul edilmiş arkadaşta aynı yol, Engellenenler listesi/kaldırma/boş/hata, Gizlilik'ten erişim, 320 dp × 1,3 taşma, tek-batch kaynak bekçisi). Mutasyon: backend 8/8 (kapı silindi, kural yönü ters, `update` kapalı, davet/rehber kapısı yok ya da ters, okuma düşünce engelsiz), Dart 13/13. `flutter analyze` temiz, `flutter test` 1685/1685, pytest 2811 geçti / 1 düştü / 2 atlandı — düşen bu işle ilgisiz bilinen istisna `test_rag_coverage[tr-…-Baba]` (arm64 platform eşitliği, ayrı oturumda).
İnceleme turu: `[ORTAK] U17 inceleme: engelleyen davet kapisi, gelen kutusu suzgeci, notr davet hatasi` — Bağımsız inceleme (Mac oturumu, üç inceleyici) çekirdeği doğruladı, çürütülemeyen bulguları giderildi. (1) **Engelleyen, engellediğine davet atabiliyordu:** kural yalnız ALICININ listesine bakıyordu; A, B'yi engelleyip B'ye davet atar, B kabul ederse `users/A/blocked/B` dururken iki kenar `accepted` olur, B dürtme atar (`nudges` yalnız `accepted` istiyor), `/notify/reaction` A'ya push düşürür, B A'nın Engellenenler listesinde kalır ve onay/Engellenenler metinleri yanlışa döner. Kural: sahip (`outgoing`) dalına `&& !existsAfter(/databases/$(database)/documents/users/$(uid)/blocked/$(otherUid))` — `existsAfter`, çünkü batch kuralları `exists` ile yazım ÖNCESİ durumu görür ve aynı batch'te silinen engeli hâlâ var sayardı. İstemci: `davetEngelKapisi` (`lib/core/safety.dart`) engellediğin kişiye davette sorar ("Bu kişiyi engellemişsin" — `onayla`, yıkıcı değil); evet → `sendFriendRequest(engeliKaldir: true)` engel silimini iki kenarla TEK batch'te yazar. Engel okunamazsa düz davet denenir, engel KALDIRILMAZ. İki çağıran da kapıdan geçiyor (`_AddFriendSheet._send`, `contacts_screen.dart` `_AktifSatir._ekle`). Sunucu: `/notify/reaction` de `has_blocked` bakıyor — kural dağıtılmadan önce kurulmuş "engel + `accepted`" hâli (eski pakette engelleyen tarafta kapı yoktu) dağıtımdan sonra da yerinde kalır. (2) **Gelen kutusu:** engellenenin engelden önceki tepkileri "Bir arkadaşın · …" diye kalıyordu (`myNudgesProvider` süzmüyordu, kenar silindiği için ad yedeğe düşüyordu). `gorunurTepkiler` kutuyu `engellenenKimliklerProvider`a göre süzüyor (eski veri dahil; liste yokken hiçbirini göstermiyor); listede olmayan göndericinin adı nötr "Bir Rytho kullanıcısı" (`aFriend` kalktı — arkadaşlık bitmiş ya da liste gelmemiş olabilir). (3) **Nötr davet hatası:** kurala çarpan davet `friendlyError` ile "Beklenmeyen bir sorun… biraz sonra tekrar dene" diyordu, o deneme hiç tutmaz. `davetHataMetni` `permission-denied`ı "Davet gönderilemedi." yapıyor (TR+EN; engeli ele vermez, tekrar önermez); iki çağıranda da. (4) Yanlış gerekçeli iki yorum (`blocked_users_screen.dart`): `bosMu` gerekçesi (hata dalı her durumda `ErrorCard` çiziyor; gerçek gerekçe boş listenin sessiz kalmaması) ve "SettingsRow dolguları" (dikey `sm`'di, `md`'ye eşitlendi). (5) Bekçiler: Dart yorum ayıklayıcı önce `/* */` bloklarını siler, her satırı `//`dan keser — yalnız `//` ile BAŞLAYAN satırı atmak tek-batch bekçisini satır sonu ve blok yorumla kandırılabilir bırakıyordu; "eski iki adımlı engelleme" bekçisi asıl geri dönüşü (engellemeden önce `removeFriend`) engelleme dalında arıyor; `engellenenlerProvider` dönüşümü saf `engellenenleriKur`a çıktı (kartı okunamayan kişi listede kalır, en yeni üstte — ikisi de artık ölçülü). Ölçüldü: `backend/tests/test_engelleme.py` 16 (+4: engelleyen kapısı `existsAfter` + yön + tek `outgoing` dalı; tepki push'u engelli/engelsiz/ters yön), `apps/mobile/test/engelleme_test.dart` 30 (+13: davet kapısı dört hâl, `davetHataMetni`, `gorunurTepkiler`, `engellenenleriKur`, çağıran/batch/gelen kutusu kaynak bekçileri). Mutasyon: backend 5/5 (`exists`'e dönüş, kapı silindi, yön ters, tepki kapısı yok/ters), Dart 18/18 (satır sonu ve blok yorum hileleri, `removeFriend` geri dönüşü, engel silimi batch dışı, soru atlandı, "tekrar dene" metni, süzgeç yok, nötr ad yok, kart hatası listeyi düşürüyor, sıralama ters). `flutter analyze` temiz, `flutter test` 1698/1698, pytest 2815 geçti / 1 düştü / 2 atlandı (düşen yine yalnız bilinen `test_rag_coverage[tr-…-Baba]`).
İnceleme turu 2: `[ORTAK] U17 inceleme 2: kabul ve tepki kurali, sessiz tepki silimi, engel yaniti sizmiyor` — İkinci doğrulama yedi düzeltmeyi onayladı, düzeltmelerin getirdiği yeni kusurları buldu; hepsi giderildi. (1) **Gizli tepkiler pencereyi dolduruyordu:** `myNudgesProvider` son 20 tepkiyi okuyor; engellenenin tepkileri yalnız gizlenince o pencerede kalıcı yer tutuyor, dokunarak da silinemiyor ve daha eski meşru tepkilere bir daha ulaşılamıyordu. Artık sahibin silme izniyle (kural `nudges` `allow read, delete: if isOwner(uid)`) EN İYİ ÇABAYLA siliniyorlar: engelleme anında `kullaniciyiEngelle` commit'ten sonra `fromUid == hedef` okuyup siliyor (`_engellenenTepkileriniSil`, `unawaited`); kalanları gelen kutusu (`GelenKutusu`, `listenManual` + `fireImmediately` — kutu liste zaten yüklüyken açılsa da) `tepkileriAyir(...).engellenenden` ile siliyor. Süzgeç ikinci hat olarak duruyor. Kural: `nudges` create'e `&& !exists(/databases/$(database)/documents/users/$(uid)/blocked/$(request.auth.uid))` — dağıtımdan önce kurulmuş "engel + `accepted`" hâlinde tepki YAZIMI da kesiliyor (önceki turun "dürtme için ayrı kural gerekmez" gerekçesi bu hâli kapsamıyordu). (2) **Engel API'de sızıyordu:** `/notify/invite` ve `/notify/reaction` engellenen göndericinin KENDİ isteğine `{"status": "skipped", "reason": "engelli"}` dönüyordu — "Engellendiği ona bildirilmez" sözü protokol düzeyinde bozuktu. Artık `_ENGEL_YANITI = {"status": "ok", "sent": 0}`: engel yokken FCM'in mesajı teslim edemediği sıradan hâlle birebir aynı gövde (gerçekten hiçbir push gitmedi); "engelli" ayrımı yalnız sunucu günlüğünde. (3) **Kabul engele bakmıyordu:** dağıtımdan önce bekleyen davet, dağıtımdan sonra engel dururken kabul edilebilirdi. Kural `update`: sahip kabulünde `!exists(.../users/$(uid)/blocked/$(otherUid))` (yazan alıcı, kendi listesinde göndereni arar), karşı taraf kabulünde `!exists(.../users/$(uid)/blocked/$(request.auth.uid))` (yazılan ağacın sahibi = daveti gönderen, kendi listesinde yazanı arar); kabul batch'i iki kenarı birlikte yazdığı için iki yön de kapalı. İstemci: `gelenIstekleriSuz` engellediklerinin isteklerini gelen istekler bölümünden düşürüyor; engel listesi bilinmiyorsa liste OLDUĞU GİBİ (tümünü gizlemek meşru istekleri sessizce kaybettirirdi; eski istek zaten kabul edilemez). (4) **Sessiz kapanma:** engel listesi okunamayınca (`rythoRetry` iki denemeden sonra hatada durur) gelen kutusu oturum boyu açıklamasız kayboluyordu. Kapalı kalıyor ama "Tepkiler yüklenemedi. · Tekrar dene" satırı gösteriyor (TR+EN, `ref.invalidate`); yorum düzeltildi. (5) Belge: kayıt `⏳ açık (kısmen …)`a çevrildi — şikayet görünümü panel KODU işi ve eksik (aşağıdaki Kalan (4)). (6) Bayat yorumlar: `kullaniciyiEngelle` engel kaydının okuyucularını sayıyla değil güncel listeyle anıyor; kuraldaki "dürtme için ayrı kapı gerekmiyor" kaldırıldı. (7) Kural bekçisi `/* */` bloklarını da atıyor ve dize literallerini tırnak türünden bağımsız sayıyor — korumalı dal blok yoruma alınıp canlı dal korumasız ve çift tırnakla yazılınca iki kural testi de geçiyordu. Ölçüldü: `backend/tests/test_engelleme.py` 20 (+4: kabulün iki dalı, tepki yazımı kapısı, engel yanıtının FCM düşüşünden ayırt edilemezliği ×2 uç; "gönderenin kendi engeline bakmaz" testleri `sent: 1`e sıkılaştı — engelli yanıtı da `ok`), `apps/mobile/test/engelleme_test.dart` 36 (+6: `GelenKutusu` engellenenin tepkisini gizleyip siliyor, kutu sonradan açılınca da siliyor, dokunuş dikişten, yüklenirken kapalı ve silmiyor, okunamazsa hata satırı + tekrar dene, dar ekran; `tepkileriAyir`, `gelenIstekleriSuz`, Çevrem bağlantı bekçisi). Mutasyon: backend 11/11 (blok yorum + çift tırnak hilesi ×2, kabul dalları kapısız/ters ×4, tepki yazımı kapısız/ters, yanıt engeli ele veriyor, yanıt FCM düşüşünden ayırt edilebilir, günlükte ayrım yok), Dart 12/12 (silim yok, `fireImmediately` kapalı, hata satırı yok, tekrar dene yanlış sağlayıcı, yüklenirken süzgeçsiz, dokunuş dikiş dışı, istekler süzülmüyor, nötr ad yok, ayrım boş, istek süzgeci bilinmeyende hepsini gizliyor ya da giden kenarı düşürüyor, engellemede silim yok). `flutter analyze` temiz, `flutter test` 1704/1704, pytest 2819 geçti / 1 düştü / 2 atlandı (düşen yine yalnız bilinen `test_rag_coverage[tr-…-Baba]`).
İnceleme turu 3: `[ORTAK] U17 inceleme 3: yan kanal kapandi, yorum ayiklayici tek gecis, filtre ve tekillestirme bekcisi` — Üçüncü doğrulama ikinci turu onayladı; kalan küçük kusurlar giderildi. (1) **Bekçisiz filtre:** `_engellenenTepkileriniSil`deki `.where('fromUid', isEqualTo: hedefUid)` silinse sorgu TÜM tepkileri döndürür, her engellemede meşru tepkiler sessizce silinirdi ve takım yeşil kalıyordu; kaynak bekçisi sorguyu, `catch (_)`yu ve gövdede `throw`/`rethrow` olmamasını arıyor (çağrı `unawaited` — fırlayan hata yakalanmamış hata olurdu). (2) **Yan kanal:** engel kapısı `can_send_event` (sessiz saat, token yok, tercih kapalı, günlük tavan) ve `already_sent`'ten ÖNCE duruyordu; sıradan yol gece `skipped` dönerken engelli yol `ok/sent:0` dönüyor, engel tek çağrıyla ayırt ediliyordu. Kapı artık bu atlamaların hepsinden SONRA, gönderimden hemen önce — FCM düşüşüyle aynı noktada (tepkide `already_sent`'ten sonra; davet ve kabulde `_event_push` içinde, aynı yerde). `mark_sent` yazılmıyor. (3) **Kural bekçisi:** önce `/* */` sonra `//` silmek, `//` yorumu içindeki `/*`ın ondan sonraki CANLI kodu saklamasına izin veriyordu; iki tür artık tek geçişte, soldan sağa (`//[^\n]*|/\*.*?\*/`) — Dart bekçisi de aynı biçimde. Tepki kapısı bekçisi `||` yokluğunu da istiyor (`&&` → `||` değişikliği yeşil kalıyordu). (4) **Tekilleştirme bekçisi:** gelen kutusunun `_silinenler` kapısı kaldırılınca takım yeşildi; silici her çağrıda fırlatırken akış aynı tepkiyi üç kez yayınlıyor, beklenen tek silim. (5) **Metin:** satır artık "Tepkiler gösterilemedi." / "Couldn't show reactions." ve tepki akışı okunamayınca da çıkıyor (eskiden tepki akışı hatası boş liste sayılıp kutu sessizce kayboluyordu); "Tekrar dene" iki sağlayıcıyı da yeniden kurar. (6) Yorumlar: dürtme bekçisinin docstring'i (`accepted` şartı H2'yi korur, engelleneni engel kapısı tutar), kuraldaki ve testteki "ikinci yön" karşı-olgusu (bugün: kabul edilemeyen sarkık davet + push) ve `kullaniciyiEngelle` okuyucu listesine Engellenenler ekranı. Ölçüldü: `test_engelleme.py` 26 (+6: yan kanal × {sessiz saat, token yok, zaten gönderildi} × {davet, tepki}), `engelleme_test.dart` 39 (+3: silim sorgusu bekçisi, tekilleştirme, tepki akışı hatası + tekrar dene). Mutasyon: backend 4/4 (kapı atlamaların önünde ×2, satır yorumundaki `/*` korumasız dalı saklıyor, `&&` → `||`), Dart 6/6 (filtresiz silim, hata yutulmuyor, tekilleştirme yok, tepki akışı hatası sessiz, tekrar dene tepki akışını kurmuyor, satır yorumundaki `/*` ikinci yazımı saklıyor). `flutter analyze` temiz, `flutter test` 1707/1707, pytest 2825 geçti / 1 düştü / 2 atlandı (düşen yine yalnız bilinen `test_rag_coverage[tr-…-Baba]`).
Kalan: (1) **Kural dağıtımı — sahibin işi:** `firebase deploy --only firestore:rules --project rhytoai`. Kural depoda durdukça koruma DEĞİL; canlıdaki Android 53'ün onay metni ("davet gönderemez") dağıtıma kadar yanlış. Eski paketlerin yazdığı engel kayıtları aynı yolda (`users/{uid}/blocked/{hedef}`), yani dağıtım anında onlar da uygulanmaya başlar; engellenen göndericinin batch'i `permission-denied` ile düşer (bu kodda `davetHataMetni` "Davet gönderilemedi." der; engellendiği söylenmez). Aynı dağıtımla engelleyen de engellediğine davet atamaz; ≤ 53 paketlerde Engellenenler ekranı ve soru kapısı yok, o kullanıcı kendi paketinin hata cümlesini görür — yeni pakete geçince engeli kaldırıp davet edebilir. Hosting beklemesinden (`docs/mac-devir.md` üst kutu) bağımsızdır — `--only firestore:rules`. (2) **Backend dağıtımı — sahibin işi:** `infra/deploy-backend.ps1`; Engellenenler notundaki "rehber önerilerinde seni görmez" ancak bundan sonra doğru — kural + backend, bu metni taşıyan paketten ÖNCE. (3) A5 — iki hesapla cihazda: engellenen davet atamıyor ("Davet gönderilemedi.") ve push gelmiyor, rehber eşleşmesinde kart yok; engelleyen engellediğine davet atınca soru çıkıyor, onaylarsa engel kalkıp davet gidiyor; engellenenin eski tepkisi gelen kutusunda yok ve siliniyor (pencereyi doldurmuyor); engellenenin tepki göndermesi kuralda düşüyor; engel kaldırılınca davet yeniden atılabiliyor. (4) **İşlevsel eksik — kaydı AÇIK tutan:** şikayetlerin görünümü ya da uyarısı. `reports` yalnız Firebase konsolundan okunuyor; panel `social.reportsOpen` sayısını bile okumuyor (ölçüldü). Bu panel KODU işi — U37 Düzeltme'sinde açık madde; o bitince U17 kapanır. Şikayete 24 saat içinde dönüş taahhüdü U18 Düzeltme'sinde açık madde (sahip kararı; söz uygulamaya ve Koşullar'a yazılmadı).

**Ek (ölçüldü 2026-10-23, canlı)** — Canlı backend'in `/openapi.json`'ında (89 yol) `POST /api/v1/account/ai-consent` yok (kimliksiz → 404; var olan `/account/consent` → 401). `has_blocked`'ı getiren beş commit'in (`804e71d`, `a261005`, `508abfa`, `aa48fdf`, `b061ec0`) hepsinin ağacında `account.py` o yolu taşıyor; yani canlı backend U17 öncesi kod ve `notify.py` / `contacts.py`'deki engel kapıları canlıda yok (çıkarım — revizyonun commit'i `gcloud`suz ölçülemedi). Canlı Firestore kuralları kimliksiz ölçülemedi; `infra/firestore.rules` `e8cc253`'ten (canlı hosting'in ağacı) bu yana 61 satır eklendi, 6 silindi. Kalan (1)–(2)'nin sırası ve önündeki salt okuma sayım: CLAUDE.md §7 "Android 54'e giden sıra" adım 3–4; iOS tarafı `docs/mac-devir.md` §4 "Deploy bağımlılıkları" 1 (kurallar + backend birlikte, sayımdan sonra; B için önerilir, C'den önce zorunlu — 2026-10-24'e dek burada "madde 2" yazıyordu, liste tekleşti). Kayıt ⏳ açık (kısmen) kalır.

**Android güvenliği** — Ortak ve sunucu değişiklikleri iki platforma birden uygulanır; yeni kural eski Android paketlerinde de temiz hata verir. **Yayın sırası:** bu kodu taşıyan Android paketinden ÖNCE `firebase deploy --only firestore:rules --project rhytoai` ve `infra/deploy-backend.ps1` gelir. Kural dağıtılmadan yeni paketin yeniden engellemesi (zaten engelli birine `set` = `blocked` `update`) eski kurala çarpar ve "Engelleme kaydedilemedi" der; Engellenenler notu ("istek ya da tepki gönderemez", "rehber önerilerinde seni görmez") ve onay metni ancak iki dağıtımdan sonra doğru olur.

**Durum notu (2026-10-22)** — Mac'te commit'lenmemiş bir TASLAK vardı, yerel stash'te: `stash@{0}` "U17 taslak (ios-hazirlik, 2026-10-22)". İçeriği: friends counterpart create dalında engel kapısı, `/notify/invite` ve `/contacts/match` atlaması (`profile_service.has_blocked`), gelen istek kutucuğunda Engelle/Şikayet, Profil > Gizlilik > Engellenenler ekranı; backend 12/12. Birleşmeden ÖNCEKİ tabana yazılmıştı. → Birleşmiş koda yeniden yazıldı, bkz. yukarıdaki "Kapandı". Stash silinmedi.

### U18 — Hazır App Review notları yanlış ya da eskimiş; demo planı cihaz kilidini atlıyor
⏳ açık · YÜKSEK · ikisi · A4 mağaza · kaynak: `review-notes-inaccurate`

**Kanıt** — `docs/store-review-notes.md:44-45` (§2.2) ve `:125` "Ham transkript saklanmıyor / Raw transcripts are never stored" diyor (aynı iddia `docs/store-privacy-labels.md:82`'de); `:153` "A single monthly auto-renewing subscription" (consumable'lar yok); `:137-139` demo hesap planı tek cihaz kilidini anmıyor.

**Etki** — İnceleyiciler notları davranışla karşılaştırır. Yanlış bir iddia ("transkript saklanmaz", "tek abonelik") 4.3 savunmasını zayıflatır ve 2.1/5.1 takip sorularını tetikleyebilir. Cihaz çakışması kapısı ya da boş arkadaş sekmesi "incelenemedi" reddine yol açabilir.

**Düzeltme**
- Notlar yeniden yazılır; yanlış transkript iddiası `store-review-notes.md:45`, `:125` ve `store-privacy-labels.md:82`'de de düzeltilir; satın almalar bölümü abonelik + consumable'larla güncellenir.
- Cihaz kilidi: yeni cihazda giriş otomatik devralır; daha önce kullanılan cihaza dönüşte "Bu cihazda kullan" düğmesi çıkar. Ortam izin listesi isteğe bağlı: inceleme sırasında takılan kilidi `POST /admin/users/{uid}/device/release` (`backend/api/admin.py:653`) temizler. Demo hesap inceleme boyunca başka yerde açık olmamalı (U32).
- Güvenmeden önce RevenueCat promosyon yetkisinin, `get_subscription()`'ın okuduğu aktif abonelik kaydını gerçekten yazdığı doğrulanır (`backend/core/entitlements.py:70-94`).
- Eklenecek bölümler: AI onayı (U06: kurulumdaki ikinci zorunlu kutu; not metni U06 kaydının başında), yüz okuma ve telefon (U38), hesap zorunluluğu gerekçesi (U39).
- (U17'den devir, 2026-10-22) **Şikayete 24 saat içinde dönüş taahhüdü** — 1.2'nin istediği "zamanında yanıt" sözü inceleme notlarında ve Koşullar'da yok. Söz SAHİP KARARIDIR: uygulamaya ya da Koşullar'a 24 saat yazılmadan önce sahip, şikayetleri o sürede gerçekten okuyabileceğine karar verir (bugün şikayetler panelde hiç görünmüyor — U37). Karar verilince notlara ve Koşullar'a (TR+EN) aynı süre yazılır.

**Ek (ölçüldü 2026-10-23)** — `docs/store-review-notes.md` en son `328d380` (2026-08-30) ile değişmiş; Kanıt'taki yanlışlar duruyor (`:125` transkript, `:153` tek abonelik) ve yenileri ölçüldü: `:137` `<E-POSTA>` / `<PAROLA>` yer tutucusu; `:150` "Profile → Delete account" — gerçek yol Profil → Hesap → Hesabı sil (`profile_screen.dart:290` → `account_screen.dart:313`); `:138` "The account already has completed onboarding" — yeni U06 modelinde onay kutusu YALNIZ kurulumda görünüyor, yani kurulumu bitmiş demo hesapla giren inceleyici 5.1.2(i) kutusunu hiç görmez. Demo hesap iOS paketiyle kurulumdan **geçirilerek** açılmalı ve notlara "onay kutusunu görmek için Apple ile yeni bir hesap açın" yönlendirmesi yazılmalı. Demo hesap SMS'siz kurulabilir: uygulamada e-posta/parola girişi var (`login_screen.dart` `_submitEmail`), e-posta doğrulaması girişi kilitlemiyor. App Store Connect yolu ve sıra `docs/mac-devir.md` §4 **C9**.

### U19 — 4.3(b): "fal" doygun kategori; mağaza kaydı ve notlar farkı kanıtlamalı
⏳ açık · YÜKSEK · ikisi · A4 mağaza · kaynak: `spam-4-3b-fortune-telling`

**Kanıt** — Guideline 4.3(b) "fortune telling"i doygun kategori olarak adıyla anıyor; mevcut savunma `docs/store-review-notes.md` §1–3'te.

**Etki** — Astroloji/burç AI uygulamaları ilk gönderimde sıkça 4.3(b) ile reddediliyor. Ayırt edici bir kayıt ve not olmadan inceleme, kod kalitesinden bağımsız olarak spam reddiyle bitebilir.

**Düzeltme** — Ad "Rytho" + falcılığı değil hesaplamayı vurgulayan alt başlık (ör. "Birth chart & live sky"); birincil kategori Lifestyle; anahtar kelimelerde "fortune/fal" doldurması yok. Ekran görüntüleri gerçek hesaplanmış haritalardan (Atlas harita çarkı, canlı gökyüzü, BaZi sütunları, arkadaş ikilisi), her altyazı neyin hesaplandığını söyler (U07). Düzeltilmiş notlar (U18) + 60–90 sn simülatör videosu. Reddedilirse değiştirmeden yeniden gönderilmez; Resolution Center'da dosya düzeyinde kanıtla (efemeris, güvenlik kapısı testleri) yanıt verilir.

### U20 — Apple App Privacy etiket planı kodun topladığı veri türlerini eksik sayıyor
⏳ açık · YÜKSEK · ikisi · A4 mağaza · kaynak: `privacy-label-apple-incomplete`

**Kanıt** — `docs/store-privacy-labels.md:100` Identifiers'ı yalnız "User ID" sayıyor; §1/§2 aşağıdaki türlerin bir kısmını atlıyor. ML Kit'in kendi manifesti DeviceID ve tanılama beyan ediyor (U12); `54130b9` `NSPrivacyCollectedDataTypes`'ı bilerek bu etikete bıraktı.

**Etki** — Yanlış "beslenme etiketi" App Store gizlilik beyanı kurallarını çiğner; incelemede ya da yayından sonra işaretlenebilir ve uygulamanın kendi gizlilik politikasıyla çelişir.

**Düzeltme** — ASC App Privacy:
- Tracking: hepsi HAYIR. Data Linked to You: Contact Info → Name, Email Address, Phone Number (isteğe bağlı) — App Functionality. User Content → Photos or Videos (avatar), Customer Support (geri bildirim), Other User Content (AI sohbet arşivi, günlük notları, damıtılmış hafıza, hazır tepkiler) — App Functionality + Product Personalization. Identifiers → User ID (Firebase uid; RevenueCat app_user_id=uid) ve Device ID (rastgele cihaz kimliği, FCM jetonu, Analytics örnek kimliği) — App Functionality + Analytics. Purchases → Purchase History (abonelik durumu, cüzdan defteri) — App Functionality. Usage Data → Product Interaction (Firebase Analytics olayları; uid anahtarlı sunucu `usageEvents`) — Analytics. Other Data → doğum tarihi/saati/yeri, cinsiyet, saat dilimi, dil, eklenen kişilerin doğum verisi, yüzden türetilen oranlar — App Functionality + Personalization.
- Data Not Linked: Diagnostics → Crash Data, Performance Data (Crashlytics).
- Contacts: özetler geçici kaldıkça (`backend/api/contacts.py:130`) atlanır; karar belgelenir.
- ML Kit'in Device ID + tanılama beyanlarının "Not Linked" açıklanması burada karara bağlanır (U12). IDFA yığını `4ba7d9d` ile söküldü (U43); cevaplar yine Google'ın Firebase veri açıklama rehberiyle karşılaştırılır.
- Sonra `docs/store-privacy-labels.md` §1/§2 güncellenir ki iki mağaza aynı şeyi söylesin.

### U21 — TestFlight cihaz doğrulama planı yok; engelleyicilerin çoğu yalnız gerçek cihazda koşuyor
⏳ açık · YÜKSEK · ikisi · A5 test · kaynak: `no-real-device-verification-plan` (eksik avcısı)

**Kanıt** — `docs/production-checklist.md:148` tek iOS test maddesi: "iOS derlemesi (macOS gerektirir) + TestFlight". `docs/mac-devir.md:268-270` TFLite ve App Attest'in simülatörde çalışmadığını söylüyor; `ios/SimulatorStubs/MLKitSimulatorStubs.m:20` yüz algılamayı simülatörde taslakla değiştiriyor; `lib/main.dart:120-122` App Attest yolunu sahibin debug/simülatör koşularında hiç çalıştırmıyor; `backend/api/face_reading.py:96` yüz okuma için Plus istiyor.

**Etki** — Onaylı engelleyicilerin çoğu yalnız fiziksel cihazdaki Release derlemesinde görünür: zorlama açıkken App Attest girişi; yüz kamerası geometrisi ve TFLite saç çizgisi; APNs push (ön plan, arka plan, kapalı); universal link (soğuk/ılık); StoreKit sandbox satın alma/restore ve Plus'ı ya da krediyi açan webhook; hesap silmede SIWA iptali; kamera izni reddi; paylaşım sayfasında "Resmi Kaydet". Yapılandırılmış bir TestFlight turu yoksa ilk gerçek cihaz koşusu App Review olur; tek bir çökme ya da çıkmaz bir red turuna mal olur.

**Sahibin kararı** — Gerçek iPhone yok; App Attest ve kamera yüz okuma ilk kez App Review'da görülecek (kabul edilen risk). Plan, iPhone'u olan bir iç testçi bulunduğu an uygulanır.

**Düzeltme**
1. ASC → Users and Access: iPhone'u olan 2–3 kişi kullanıcı olarak (herhangi bir rol). TestFlight INTERNAL grubu: işlendikten dakikalar sonra ulaşır, Beta App Review yok (dış grup ister).
2. Cihaz kapsamı: güncel iOS'lu bir Face ID iPhone + küçük/eski bir iPhone (SE sınıfı, iOS 16/17); birinde cihaz dili TR, ötekinde EN. iPad yok (U10).
3. Her testçiye KENDİ Rytho hesabı (tek cihaz kilidi paylaşılan hesabı engeller). Plus: TestFlight sandbox satın alma (ücretlendirilmez) ya da admin yetkisi.
4. "What to Test"e yukarıdaki her madde numaralı liste olarak; beklenen sonuçlar yazılı (ör. `users/{uid}.fcmToken` yazıldı, `revenueEvents` satırı oluştu, silmeden sonra uygulama Apple Kimliği > Apple ile Giriş'te listelenmiyor). Ek satırlar: U12 Privacy Report, U13 `simctl openurl`, U44 "Resmi Kaydet".
5. 1. turdan önce: dSYM yüklemesi (U26), App Attest kaydı ve APNs anahtarı (U08), RevenueCat `appl_` anahtarı ve IAP'ler (U02). Yoksa tur yalnız bilinen engelleyicileri yeniden keşfeder.
6. Crashlytics, Xcode Organizer > Crashes ve TestFlight geri bildirim ekran görüntüleri izlenir; her satır geçmeden App Review'a gönderilmez.

**Ek (ölçüldü 2026-10-23)** — Sahibin 3. kararı değişti (iPhone "haftaya"); plan iPhone gelince yeniden yazılır. Bugünkü sıralı cihaz/TestFlight/inceleme adımları `docs/mac-devir.md` §4 Aşama A/B/C. Plana dört yeni satır:
- **Arşiv önkoşulları yok.** Bu Mac'te provizyon profili 0 (iki profil dizini de yok), Apple Distribution sertifikası 0, `~/Library/Developer/Xcode/Archives` yok; bağlı cihaz yok, takımda kayıtlı cihaz ölçülemedi. Otomatik imza takımda cihaz yokken arşiv için profil üretemez (Xcode'un bilinen davranışı — burada ölçülmedi); cihaz bağlanınca kaydolur (§4 A3, B9). Daha erken yükleme gerekirse portalda bir UDID elle kaydedilir.
- **İç ve dış grup ayrımı.** Sahibin kendi iPhone'u için İÇ test yeterli (hesap sahibi iç testçidir, Beta App Review yok). Dış grup açılacaksa TestFlight → Test Information (beta açıklaması, geri bildirim e-postası, iletişim, demo hesap, "What to Test") gerekir ve ilk dış derleme Beta App Review'dan geçer — bu bilgiler hiçbir belgede yok (`Beta App` bu belgede yalnız madde 1'de geçiyordu).
- **iOS 27 gezinti sonucu kayıtlı değil.** `xcrun simctl list runtimes` → iOS 26.5 ve 27.0 kurulu; bu ölçüm anında Rytho yalnız iki iOS 26.5 simülatöründeydi (iPhone 17 Pro, iPhone 17). → 2026-10-24 (ölçüldü, simülatör veri kabından): Rytho'nun simülatör derlemesi 1.20.0 (53) iOS 27.0'da iki simülatöre kuruldu ve açıldı — iPhone 18 Pro (2026-10-24 01:06; tercihlerde şartlar onayı, tanıtım paywall'ı ve bildirim izni bayrakları var, yani kurulum akışı geçildi) ve iPad (A16) (2026-10-23 20:53; yalnız açılış bayrakları, giriş yok). Gezilen ekranların görsel/işlev sonucu kayıtlı değil. İnceleme güncel iOS'ta yapılır. Telefon iOS 27'deyse Xcode 26.6'nın (iPhoneOS 26.5 SDK) o cihaza kurup hata ayıklayıp ayıklayamadığı da ölçülmedi; Xcode 27 depoyu derlemiyor (U55).
- **iPad uyumluluk kipi:** iPad (A16, iOS 27.0) simülatöründe yalnız açılış ölçüldü (2026-10-23 20:53, giriş yok); doğru çalıştığı ölçülmedi (U10 ek).
- Madde 5'in "RevenueCat `appl_` anahtarı" şartı bugün karşılanmıyor: `test_` önekli anahtar 2026-10-23'teki imzasız Release paketinde bulundu ve o paket açılışta bilerek çöker (U02 ek, U05). (2026-10-24: U05 kod ağı `09bbe23` sonrası çökmez, satın alma kapalı çıkar ve `infra/build-ipa.sh` paketi durdurur; şart yine karşılanmıyor — StoreKit testi `appl_` ister.) Debug kip (`flutter run`) `test_` anahtarıyla çökmez ama satın almalar yalnız RevenueCat Test Store simülasyonudur, StoreKit sandbox değil.

**Android güvenliği** — Süreç ve konsol işi; kod ve Android derlemesi değişmez.

---

## ORTA

### U22 — Hide My Email: Firebase Auth göndericisi Apple'ın özel e-posta aktarıcısına kayıtlı değil
⏳ açık · ORTA · hesap · A1 hesap · kaynak: `apple-private-relay-email-not-registered`

**Kanıt** — Firebase Auth e-postaları varsayılan göndericiden (`noreply@rhytoai.firebaseapp.com`) çıkıyor; iOS yol haritasında (`docs/mac-devir.md` §4) aktarıcı kaydı adımı yok.

**Etki** — Hide My Email seçen Apple kullanıcısı sonradan "Şifremi unuttum" ya da doğrulama kullanırsa e-posta hiç gelmez: Apple'ın aktarıcısı kayıtsız göndericiden gelen postayı düşürür. Şifre yoluna muhtaç olan (ör. Android'e geçmek isteyen) kullanıcı kilitlenir.

**Düzeltme** — Apple Developer → Certificates, Identifiers & Profiles → Services → Sign in with Apple for Email Communication → `noreply@rhytoai.firebaseapp.com`. Firebase e-posta şablonunun alan adı `rytho.app`'e taşınınca özel gönderici alan adı da (SPF/DKIM ile) eklenir.

**Ek (2026-10-23)** — Yol haritası boşluğu kapandı: adım `docs/mac-devir.md` §4 **C7**'de. Portal durumu ölçülemedi; kayıt ⏳ açık kalır.

**Ek (2026-10-24)** — Düzeltme'deki yol kısalmıştı. Apple'ın yolu: Services → Sign in with Apple for Email Communication → Configure → **Email Sources** → `+` → adres → Next → Register. Kaydedilen adres Firebase → Authentication → Templates'teki **From** alanıyla birebir aynı olmalı (büyük olasılıkla `noreply@rhytoai.firebaseapp.com`; konsolda okunmadı). Kayıttan sonra tablodaki SPF sütununda "pass" beklenmesi bir çıkarım: `rhytoai.firebaseapp.com`'un SPF kaydı var (DNS, 2026-10-24) ama Firebase postasının Return-Path'i ölçülmedi; sahibin DNS işi yok. Gerçek kanıt Hide My Email'li hesaba şifre sıfırlama postasının ulaşması. `docs/mac-devir.md` §4 C7 adım 4.

### U23 — iOS'ta kamera izni reddi donanım arızası sayılıyor
✅ kapandı · ORTA · kod · A2 iOS kod · kaynak: `camera-permission-denied-ios`

**Kanıt** — `lib/features/face/face_capture_screen.dart:285-295`: `CameraException` yalnız `e.code.contains('Permission')` ise izin reddi sayılıyor; iOS'un `CameraAccessDeniedWithoutPrompt` kodu uymuyor → hata katmanı + `_arizaBildir` (Crashlytics). `:224-229` izin katmanında `resumed` otomatik yeniden deneme; `test/face_ariza_kanit_test.dart:67` yüklemi kaynak metniyle sabitliyor. Rehberde `lib/features/friends/contacts_screen.dart:104-110` "Tekrar dene" yalnız sağlayıcıyı geçersiz kılıyor.

**Etki** — iOS kamera iznini yalnız bir kez sorar. "İzin Verme"den sonra her deneme anında `CameraAccessDeniedWithoutPrompt` ile düşer: ekran izin mesajı yerine "yüz algılama başarısız" gösterir, "Yeniden çek" sonsuza dek döner, her deneme Crashlytics'e non-fatal yazar. Ayarlar'dan dönüş de otomatik yeniden denemez. Rehberde aynı çıkmaz: "Tekrar dene" bir daha sormaz.

**Düzeltme** — İki yerde de (rapor koşulu ve durum koşulu) yüklem `e.code.contains('Permission') || e.code.startsWith('CameraAccess')`; `test/face_ariza_kanit_test.dart:67` güncellenir. iOS'ta `izinYok` katmanına Ayarlar düğmesi: `launchUrl(Uri.parse('app-settings:'))` (`UIApplication.openSettingsURLString`). iOS, Ayarlar'da kamera izni değişince uygulamayı sonlandırır; iOS'ta `resumed` yeniden denemesi gerekmez. Rehbere isteğe bağlı aynı iOS'a özgü Ayarlar düğmesi.

Kapandı: `[iOS] U09 U23: yuz okuma kare geometrisi ve izin reddi` — `face_capture_screen.dart` `kameraIzniReddi(kod)`: rapor koşulu ve durum koşulu artık TEK yüklemden (`final izinReddi = kameraIzniReddi(e.code)`), ikisi ayrışamaz. `CameraAccess` öneki (`CameraAccessDenied`, `…DeniedWithoutPrompt`, `…Restricted` — `CameraPermissionManager.swift`) yalnız iOS'ta ret sayılıyor. iOS'ta izin katmanında asıl eylem `FilledButton` "Ayarlar'ı aç" (`app-settings:`, `core/ayarlar_kisayolu.dart`; `url_launcher_ios` 6.4.1 `canOpenURL` sormadan `UIApplication.open` ile açıyor, `LSApplicationQueriesSchemes` gerekmiyor), "Tekrar dene" ikincil `TextButton`. Katman `YuzKameraEngeli` olarak ayrıldı ki kamerasız test edilebilsin. Rehberde (`contacts_screen.dart`) aynı: iOS'ta "Ayarlar'ı aç" asıl, "Tekrar dene" ikincil; Android kartı değişmedi. `resumed` yeniden denemesi olduğu gibi bırakıldı: iOS'ta ikinci deneme diyalogsuz düştüğü için döngü kurulamıyor. Yeni l10n: `openSystemSettings` (TR "Ayarlar'ı aç" / EN "Open Settings"). Ölçüldü: `test/face_ariza_kanit_test.dart` kaynak bekçisi tek yüklemi ve ham `contains('Permission')`'ın yokluğunu sabitliyor; `test/kamera_izni_ios_test.dart` (12) — iOS'ta üç `CameraAccess` kodu ret, `IOError`/`VideoError`/`Error` arıza; Ayarlar düğmesi `app-settings:` açıyor, açılış fırlatırsa hata yutuluyor (yutulmasa `PlatformDispatcher.onError` üzerinden Crashlytics'e sahte FATAL giderdi); yüz ve rehber ekranında iOS'ta Ayarlar + ikincil yeniden deneme, Android'de eski tek düğme.
Düzeltmeden sapma: yüklem iki platformda ORTAK değil. Denetimin "Android güvenliği" satırı yanlış öncüle dayanıyordu — `camera_android_camerax` 0.6.30'un ret kodu da `CameraAccessDenied` (`CameraPermissionsManager.java`), `Permission` içermiyor. Önek Android'e de uygulansaydı Android reddi izin katmanına düşer ve oradaki `resumed` yeniden denemesi diyaloğu tekrar tekrar açabilirdi (Android ilk retten sonra yeniden SORABİLİYOR: 11+'da bir kez daha, 7–10'da "Bir daha sorma"ya dek); cihazda ölçülmeden Android'e taşınmadı. Android'de ret bugün de arıza sayılıyor ve Crashlytics'e yazılıyor — Windows oturumu için açık kalem, izlendiği yer **`docs/test-raporu.md` B11** (döngü riski ve önce ölçülecekler orada).

**Android güvenliği** — Android'de mevcut yeniden deneme kalır (app_settings ya da permission_handler eklenmedikçe); `Permission` içeren Android kodları aynı dala düşmeye devam eder.

**Birleşme notu (2026-10-22, `8d6f67b`)** — Windows aynı kusuru D6'da iki platform için birden onarmıştı (`_hataKatmani`: "Ayarları aç" gerçekten ayarları açar, dönüşte kendiliğinden yeniden dener). Birleşmede o sürüm kaldı; Mac'in yalnız-iOS katmanı `YuzKameraEngeli` ve onun widget testleri çıktı. `kameraIzniReddi` (iOS'un `CameraAccess*` kodları) ve rehber kartı kaldı. ⚠️ Windows'un katmanı `app_settings` kullanıyor — U56.

### U24 — UI ses efektleri iOS'ta sessiz anahtarını yok sayıyor ve müziği kesiyor
✅ kapandı · ORTA · kod · A2 iOS kod · kaynak: `ios-audio-session-ignores-silent-switch`

**Kanıt** — `lib/core/sound.dart:17` `_ensureLoaded`, `:46` `AudioPlayer()`; `lib/`'de hiç `setAudioContext` yok → audioplayers'ın varsayılan iOS oturumu (playback, karıştırmasız).

**Etki** — iPhone'da mesaj gönderme/beğeni "tık" sesleri Zil/Sessiz anahtarı sessizdeyken de çalar. Her ses karıştırılamayan bir playback oturumu açar ve arka plandaki Spotify / Apple Music'i durdurur. iOS alışkanlıklarını çiğner; TestFlight testçilerinden ilk gelecek şikâyetlerden biri.

**Düzeltme** — Bir kez, ör. `SoundFx._ensureLoaded` içinde: `if (defaultTargetPlatform == TargetPlatform.iOS) await AudioPlayer.global.setAudioContext(AudioContext(iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient, options: const {})));`. `ambient` zaten karıştırır; yanına `mixWithOthers` eklemek yapıcıdaki assert'e takılır (`audioplayers_platform_interface` 7.2.0 `audio_context.dart:177-184`) — `options` boş kalır.

Kapandı: `[iOS] U11 U14 U24 U30 U54: bildirim izni, on plan push, ses oturumu, App Check izi` — `sound.dart` `_iosOturumunuHazirla`: iOS'ta ilk çalıştan ÖNCE bir kez `AudioPlayer.global.setAudioContext(SoundFx.iosSesBaglami)` (`ambient`, `options` boş). Kurulum, Düzeltme'nin önerdiği gibi `_ensureLoaded`'a DEĞİL ayrı bir bayrağa bağlandı: `_ensureLoaded` `_loaded`'ı tercihleri okumadan önce true yapıyor ve hiç geri almıyor, yani oraya konan kurulumun tek hakkı olurdu — düşen tek bir AVAudioSession çağrısı süreci ömür boyu `playback`'te bırakır, yeniden denenmezdi. Ayrı bayrak aynı zamanda kurulumu `loadEnabled` / `setEnabled` sırasından bağımsız kılıyor (`setEnabled` de `_loaded`'ı true yapıyor; bugün Profil ekranı `initState`'te `loadEnabled`'ı anahtardan önce çağırdığı için bu sıra uygulamada ters dönmüyor). Eşzamanlı ilk çalışlar tek kurulumu paylaşıyor. Kurulum düşerse o ses çalınmıyor, sonraki çalış yeniden deniyor — varsayılan `playback` ile çalmak kusurun kendisi. Kaynakta ölçülen: audioplayers_darwin 6.5.0 eklenti kaydında `playback` uyguluyor (`AudioplayersDarwinPlugin.swift` `globalContext.apply()`) ve çalış sırasında oturumu etkinleştiriyor; iOS'ta bağlam globaldir. Uygulamada başka ses kaynağı yok (kamera `enableAudio: false`). Ölçüldü (`test/ses_oturumu_ios_test.dart`, 7): bağlam `ambient` + boş seçenek; iOS'ta kurulum ilk çalıştan önce ve bir kez, eşzamanlı ilk çalışlarda da tek; `setEnabled` → `like` sırasında da kuruluyor (sıra bağımsızlığı bekçisi); kurulum düşünce ses susuyor, ikinci çalış yeniden deneyip çalıyor; sesler kapalıyken hiçbir şey yok; Android'de bağlama hiç dokunulmuyor ve çalış sırası aynı.
Gerekçe düzeltildi: `[iOS] U24 inceleme: ses oturumu bayraginin yanlis gerekcesi duzeltildi` — ilk commit'in gövdesi ve yorumu ayrı bayrağı "Profil'deki anahtar yolu bağlamı hiç kurmazdı" diye gerekçelendiriyordu; yanlış, çünkü o ekran `initState`'te `loadEnabled` → `_ensureLoaded`'ı çağırıyor (`profile_sections.dart`) ve `_loaded` kullanıcı dokunmadan true oluyor. Kod değişmedi; asıl gerekçe yukarıda (yeniden deneme).
Kalan: A5 — gerçek iPhone'da: Sessiz anahtarı açıkken mesaj gönder → ses yok; Apple Music çalarken beğeni → müzik durmuyor (simülatörde Zil/Sessiz anahtarı yok).

**Android güvenliği** — iOS koşulu Android'i garanti olarak değişmez bırakır.

### U25 — Google kütüphaneleri iki kez bağlanıyor (CocoaPods + SwiftPM)
✅ kapandı — `4ba7d9d` · ORTA · kod · A2 iOS kod · kaynak: `duplicate-google-libs-cocoapods-and-spm`

**Kanıt** — GoogleDataTransport, GoogleUtilities, GTMSessionFetcher, FBLPromises ve nanopb hem CocoaPods dinamik framework'ü (ML Kit için) hem SwiftPM statik kütüphanesi (Firebase için) olarak bağlanıyor. SwiftPM tarafı: `ios/Runner.xcodeproj/project.pbxproj:61, :256` (`FlutterGeneratedPluginSwiftPackage`), `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

**Etki** — ObjC çalışma zamanı "Class X is implemented in both … Which one is used is undefined" uyarır. İki bağımsız GDTCOR kaydedici ve yükleme koordinatörü aynı olay deposunda çalışır; iki FBLPromise ve GUL kopyası bir arada durur. Sürümler şu an eşit olduğu için genelde çalışır; ama tanımsız davranıştır — yarışlı olay yüklemesi ya da teşhisi zor çökmeler; bir taraf yükselince kötüleşir. Tek başına App Review reddi değil.

**Düzeltme** — Yalnız CocoaPods'a geçiş, şu çekincelerle:
1. Firebase, RevenueCat, GoogleSignIn ve öteki eklentiler pod'a taşınır → Xcode 26.6 ile simülatör duman testi ve imzasız cihaz derlemesi yeniden. Podfile'daki `ml_kit_simulatorden_cikar` OTHER_LDFLAGS cerrahisinin hâlâ çalıştığı kontrol edilir: toplu xcconfig çok daha fazla `-framework` bayrağı taşıyacak.
2. `flutter clean` sonrası `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` silinir, `FlutterGeneratedPluginSwiftPackage` paket başvurusu kaldırılır (pbxproj `:61`, `:256`).
3. Seçim `docs/mac-devir.md`'ye yazılır — Crashlytics dSYM betiği yolu (U26) ve Analytics reklam-kimliksiz anahtarı (U43) buna bağlı.
- `4ba7d9d`: `pubspec.yaml`'da `enable-swift-package-manager: false`, eski SwiftPM `Package.resolved` kilitleri kaldırıldı; `FlutterGeneratedPluginSwiftPackage` başvurusu bağımlılığı olmadığı için zararsız diye bırakıldı. Ölçüldü: simülatörde "implemented in both" = 0, App Check hatası yok. **Kalan (belge):** seçim `docs/mac-devir.md`'ye yazılır.
- **Ek (ölçüldü 2026-10-23)** — "Kalan (belge)" karşılanmış: `docs/mac-devir.md` Mac durumu kutusu ve §6'nın U56 maddesi seçimi gerekçesiyle anıyor ("depo ise U25 gereği CocoaPods'ta"; "`enable-swift-package-manager: false` (U25: SPM + Pods Google kütüphanelerini iki kez bağlıyordu)"), CLAUDE.md §7 de aynı. Seçimin bugünkü bedeli Release derleme çıktısında görünüyor: dört eklenti SPM desteklemiyor uyarısı (U55 ek).

**Android güvenliği** — Ayar ortak `pubspec.yaml`'da ama yalnız iOS/macOS okur (commit notu). Windows oturumu onu silmemeli: silinirse iOS'ta çift kopya geri gelir.

### U26 — Crashlytics dSYM yükleme adımı yok; yerel iOS çökmeleri sembolsüz kalır
✅ kapandı — `4ba7d9d` · ORTA · kod · A2 iOS kod · kaynak: `crashlytics-dsym-upload-missing`

**Kanıt** — `ios/Runner.xcodeproj/project.pbxproj:290-360` shell betik fazları yalnız Pods ve `xcode_backend.sh`; Crashlytics yükleme betiği yok. `flutterfire configure` hiç koşulmadı (`lib/firebase_options.dart` yok). Release ayarları hazır: `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` (`:482`, `:664`), `ENABLE_USER_SCRIPT_SANDBOXING = NO` (`:485`, `:610`, `:667`).

**Etki** — Yerel iOS çökmeleri (flutter_contacts/UIScene, kamera, ML Kit, TFLite, RevenueCat) Crashlytics'te "Missing dSYM" ile sembolsüz görünür. Sahibin cihazı olmadığı ve TestFlight çökme raporlarına bağlı olduğu için iOS'ta önemli. Dart hataları etkilenmez.

**Düzeltme**
- A yolu `flutterfire configure --platforms=ios`: diff gözden geçirilir — elle doğrulanmış `ai.rytho` değerli `ios/Runner/GoogleService-Info.plist`'i yeniden yazabilir (bkz. `ios/Runner/Info.plist:18-32` yorumu) ve `lib/firebase_options.dart` üretir; `android/`'e dokunmasına izin verilmez.
- B yolu (daha az riskli): elle Run Script fazı.
- Yol SwiftPM/CocoaPods kararına (U25) göre seçilir; ilk `flutter build ipa`'da Crashlytics konsolunda yüklenen dSYM UUID'si kontrol edilir.
- `4ba7d9d`: B yolu — "Crashlytics dSYM yukle" Run Script fazı (Debug'da atlanır). Ölçüldü: imzasız Release derlemede "Validation succeeded. Symbol uploading will proceed in the background." **Kalan (A5):** ilk gerçek `flutter build ipa` / TestFlight sonrası Crashlytics konsolunda dSYM UUID'si.
- **Ek (ölçüldü 2026-10-23)** — Faz Debug dışındaki HER derlemede koşuyor, yalnız ölçüm için alınan imzasız derlemelerde de: `ba6108b`'deki `flutter build ios --release --no-codesign` etkinlik günlüğünde "Running upload-symbols in Build Phase mode" ve "Validation succeeded…" var, yani upload-symbols koştu (arka plan yüklemesi başlatıldı). Deploy değil ama dışa giden bir yükleme; ölçüm derlemesi alan oturum bunu bilmeli. Sembolün konsola ulaştığı ölçülmedi (erişim yok). → **2026-10-24, `09bbe23`:** faz `CODE_SIGNING_ALLOWED=NO` iken (imzasız ölçüm derlemesi) `run`'dan önce atlıyor; onarım sonrası imzasız Release etkinlik günlüğünde "yukleme ATLANDI", upload-symbols 0 kez. İmzalı yayın yolu yine yükler. Bekçi `backend/tests/test_ios_config.py` (U05 Ek'i ile aynı kapanış).

### U27 — Türkçe yerelleştirme eksik; `InfoPlist.strings` tuzağı; rehber metni gerçeği eksik anlatıyor
✅ kapandı — `54130b9` · ORTA · kod · A2 iOS kod · kaynak: `localization-tr-missing-infoplist-strings-trap`, `purpose-strings-accuracy-localization`

**Kanıt** — `ios/Runner.xcodeproj/project.pbxproj:250-252` `knownRegions = (en, Base)`, `CFBundleLocalizations` yok; l10n şablonu `app_tr.arb` (Türkçe öncelikli). `ios/Runner/Info.plist:9-10` rehber metni "rehberin sunucuya gönderilmez" diyor, oysa eşleşme için SHA-256 özetleri gönderiliyor (saklanmadan, `backend/api/contacts.py`). `docs/mac-devir.md:249` (§6) "Info.plist seç → … → Localize" diyor.

**Etki** — (1) App Store ürün sayfası yalnız İngilizce listeler. (2) iOS uygulamanın dilini `en` çözer; Türkçe cihazda süreç içi sistem arayüzü (paylaşım sayfası, fotoğraf seçici vb.) İngilizce kalır. (3) **Tuzak:** §6'daki plan gibi yalnız `en.lproj/InfoPlist.strings` bağlanıp `tr` eklenmezse Türkçe cihaz `en.lproj`'a düşer ve İNGİLİZCE izin diyaloğu görür — niyetin tersi. (4) İngilizce inceleyici Türkçe sistem istemleri görüyor; rehber istemi cihazdan çıkanı eksik anlatıyor. İkisi de yinelenen 5.1.1 red nedeni.

**Düzeltme**
- Xcode'da Project > Info > Localizations'a Türkçe. YALNIZ `InfoPlist.strings` en + tr varyantlarıyla yerelleştirilir, Info.plist ASLA. `tr` varyantı Türkçe metinleri tekrarlar; `NSMicrophoneUsageDescription` ve `NSPhotoLibraryAddUsageDescription` iki varyantta da.
- `CFBundleLocalizations = [tr, en]` (Flutter'ın iOS i18n belgesi ister); knownRegions'a `tr`.
- Rehber metni iki dilde: numaralar eşleşme için tek yönlü özetlenip gönderilir ve saklanmaz.
- Düşük öncelik: `NSPhotoLibraryUsageDescription` profil fotoğrafı yüklemesini de kapsasın (PHPicker şu an göstermese de).
- `docs/mac-devir.md` §6 düzeltilir: "Info.plist'i yerelleştir" yazmasın.
- `54130b9`: knownRegions `tr`, `CFBundleLocalizations`, en/tr `InfoPlist.strings` varyant grubu Runner'a bağlı, rehber metni düzeltildi, yeni anahtarlar iki varyantta. **Kalan (belge / isteğe bağlı):** `docs/mac-devir.md` §6 metni; fotoğraf kütüphanesi metninin profil fotoğrafını da kapsaması.
- **Ek (ölçüldü 2026-10-23)** — Belge kalanı karşılanmış: `docs/mac-devir.md` §6 artık "✅ `InfoPlist.strings` bağlı" diyor, "Info.plist'i yerelleştir" ya da "Localize" geçmiyor. İmzasız Release paketinde `en.lproj/InfoPlist.strings` ve `tr.lproj/InfoPlist.strings` var, ikisi de aynı beş anahtarı taşıyor; `CFBundleLocalizations = [tr, en]`. İsteğe bağlı kalan duruyor ve gerekçesi güçlendi: `NSPhotoLibraryUsageDescription` (Info.plist ve iki varyant) yalnız yüz okumayı anıyor ve "hiçbir yere gönderilmez ve saklanmaz" diyor; aynı seçici profil fotoğrafı için de kullanılıyor ve o fotoğraf Storage'a yükleniyor. iOS 14+'ta PHPicker izin istemediği için metin bugün görünmüyor (U27 Kanıt'ı); görünürse yanlış beyan olur.

### U28 — Uygulama içi gizlilik politikası Android çerçeveli (reklam kimliği; Apple ile Giriş yok)
⏳ açık · ORTA · ikisi · A3 ortak kod · kaynak: `privacy-text-android-framed-idfa` (metin kısmı), `analytics-adid-stack-ios` (metin kısmı)

**Kanıt** — `lib/features/profile/legal_texts.dart:139-142` (TR) ve `:458-461` (EN): "Android'in reklam kimliğini (Advertising ID) KULLANMAZ: bu izin uygulama paketinden çıkarıldı…"; iOS karşılığı yok. "Hesap bilgileri" (`:33`) / "Account information" (`:335`) Apple ile Giriş'ten gelen ad ve e-postayı anmıyor.

**Etki** — iOS için politika bir güvenceyi (reklam kimliği yok) yalnız Android terimleriyle veriyor ve başka bir platformu adıyla anıyor; iOS ikilisi ise varsayılan olarak Apple'ın AdSupport yolunu bağlıyor (U43). Etiket ve politika iOS ikilisinin yaptığıyla eşleşmeli; 5.1.1/5.1.2 uyuşmazlığı ya da kafa karıştıran bir etiket anketi olası.

**Düzeltme** — Metin platform-nötr (TR+EN): Android Advertising ID / iOS IDFA; izleme yok. "Hesap bilgileri"ne Apple ile Giriş: ad ve e-posta, muhtemelen özel aktarıcı (relay) adresi. (Web gizlilik sayfası Apple ile Giriş'i zaten anıyor.) ASC App Privacy'de izleme yok (U20). IDFA yığını `4ba7d9d` ile iOS paketinden de söküldü (U43), yani "reklam kimliği kullanılmaz" güvencesi artık iki platform için doğru yazılabilir.

**Android güvenliği** — Ortak metin; Android'de de nötr ifade görünür, anlam değişmez.

### U29 — Zorunlu güncelleme eşiği (`min_build`) iki platform için tek sayı
⏳ açık · ORTA · ikisi · A3 ortak kod · kaynak: `min-build-gate-platform-agnostic`, `min-build-gate-not-per-platform`, `min-build-shared-across-platforms`

**Kanıt** — `backend/core/app_gate.py:143` `current_min_build()` = max(env `RYTHO_MIN_BUILD`, `config/app.minBuild`); `:267` `AppGateMiddleware` platforma bakmadan 426 döndürüyor; `:180` `build_seen_at_or_above` ve `:202` `count_below` platform ayırmıyor. `lib/core/app_config.dart:63-79` `fetchMinBuild` `/api/v1/config/app`'i çıplak `Dio` ile çağırıyor (interceptor yok → `X-Device-Platform` yok) ve değeri `minBuildSeen`'e (`:40`) önbelleğe alıyor: istemci kendini de kilitliyor.

**Etki** — Android başka makineden kendi temposuyla çıkıyor (+46, +47…); iOS paketleri App Review / TestFlight döngüsü yüzünden geride. Sahip Android'e özgü bir nedenle `minBuild`'i yükseltirse her iOS kullanıcısı ve incelemedeki paket her istekte 426 ve ForceUpdateScreen alır — App Store'da daha yeni paket yokken. `APPSTORE_APP_ID` boşken o ekranda mağaza düğmesi bile yok. İncelemede anında 2.1 reddi; canlıda Apple yeni paketi onaylayana dek tam kilit: bir Android kararından doğan tam iOS kesintisi.

**Düzeltme**
1. İstemci: `fetchMinBuild`'e `kDevicePlatformHeader: devicePlatform()` başlığı. **İLK iOS paketinde** olmalı.
2. Backend: `current_min_build(platform)` — `p = (hdr or '').strip().lower()`; `'ios'` → `config/app.minBuildIos` (varsayılan 0 = kapı kapalı), diğer her şey ve başlıksız istek → mevcut `minBuild` / `RYTHO_MIN_BUILD`. `AppGateMiddleware` ve `GET /config/app` ikisi de kullanır. Büyük/küçük harf duyarsız (`device_session` `'iOS'`, başka yerler `'ios'` yolluyor).
3. `build_seen_at_or_above` / `count_below` `platform ==` + `appBuild >=` sorgusuna geçerse Firestore bileşik dizini (platform ASC, appBuild ASC) `infra/firestore.indexes.json`'a eklenip dağıtılır — dizin yoksa sorgu fırlatır ve mevcut kod `False` döner (kapalı başarısız olur).
4. Panelde iOS eşiği alanı. `APPSTORE_APP_ID` ASC kaydı açılır açılmaz doldurulur (U02).
- **İşletme kuralı, bu yayınlanana dek:** `minBuild`, App Store'da canlı ve onaylı en yeni iOS paketinin üstüne ASLA çıkarılmaz.

**Ek (ölçüldü 2026-10-23)** — Platform başlığı ve `minBuildIos` hâlâ yok (`app_gate.py` `current_min_build()` parametresiz; `app_config.dart` `fetchMinBuild` çıplak `Dio`). Canlı eşik 0 (`GET /api/v1/config/app` → `{"min_build": 0}`), yani bugün iOS paketine 426 riski yok. **Yeni yüz: derleme numarası çakışması.** Bugünkü pubspec `1.20.0+53` iOS paketini `1.20.0 (53)` yapıyor (imzasız Release'te `CFBundleVersion = 53` ölçüldü). Android'de 53 canlı ve onay kutusunu taşımıyor; HEAD'den derlenen iOS 53 taşıyor. Sunucunun `appBuild` aynası ve eşiği platform ayırmadığı için ileride Android adına `minBuild = 54` yazılırsa kutuyu zaten taşıyan iOS 53 de kilitlenir. Ayrıca gizlilik metni kutuyu "1.20.0+54 sürümüyle eklendi" diye anıyor (`web/legal/gizlilik.html:224`, `legal_texts.dart:282` / `:694`). Öneri: ilk iOS yüklemesi en az 54, pubspec Android 54 ile aynı commit'te — karar sahibin (`docs/mac-devir.md` §4 **B8**). Bu öneri madde 1'in ("İLK iOS paketinde" platform başlığı) yerini tutmaz.

**Android güvenliği** — Başlıksız istek ve `android` bugünkü anahtara düşer; Android davranışı değişmez.

### U30 — iOS release'te App Check ve Auth hataları iz bırakmıyor
✅ kapandı · ORTA · kod · A3 ortak kod · kaynak: `auth-appcheck-failures-invisible`

**Kanıt** — `lib/main.dart:105-126`: `FirebaseAppCheck.instance.activate` hatası `catch (e)` ile yalnız `debugPrint` ediliyor (`:125`); Crashlytics işleyicileri `:130-137`'de sonradan kuruluyor.

**Etki** — Gerçek cihaz sinyali yalnız TestFlight testçileri. Zorlama açıkken her App Attest sorunu (uygulama kayıtsız, Firebase'de Team ID yok, sandbox ortamı, attestation hatası) yalnız genel "Bir şeyler ters gitti. Tekrar dene." (`authFailed`) ya da Firestore izin hatası olarak görünür; App Check'i başka beklenmedik hatalardan ayıracak Crashlytics izi yok. *(Düzeltme 2026-10-24: burada "Giriş yapılamadı" yazıyordu — o metin yanlış şifrenin (`useGoogleInstead`); App Check reddi `authErrorText`'in `default` dalına düşer, simülatörde ölçüldü.)*

**Düzeltme** — `main.dart` catch'i `catch (e, st)` olur ve yalnız `!kDebugMode && !kIsWeb` iken Crashlytics'e kaydeder; Crashlytics `Firebase.initializeApp`'ten hemen sonra kullanılabilir, işleyiciler kurulmadan kaydetmek çalışır. Release'e özgü `getToken` yoklaması "ateşle ve unut" (`unawaited`) — açılış asla gecikmez.

Kapandı: `[iOS] U11 U14 U24 U30 U54: bildirim izni, on plan push, ses oturumu, App Check izi` — yeni `lib/core/app_check_izi.dart`. `main.dart`'ta `activate` catch'i `catch (e, iz)` → `appCheckEtkinlestirmeHatasi` (reason `app-check-activate`, non-fatal). `activate` başarılıysa iOS yayında `unawaited(appCheckJetonunuYokla(FirebaseAppCheck.instance.getToken))`: düşen ya da boş jeton reason `app-check-token` ile kaydediliyor; yoklama asla fırlatmıyor. Kayıt kanalı yalnız `!kDebugMode && !kIsWeb`; Crashlytics işleyicileri kurulmadan `recordError` çalışıyor. Kaynakta ölçülen: iOS'ta `activate` yalnız sağlayıcıyı kaydediyor (firebase_app_check 0.4.5+2 `FirebaseAppCheckPlugin.swift`; Firebase uygulaması bulunamazsa düşer, başka hiçbir şey denemez) — App Attest arızası ancak jeton alınırken görünür, yoklamasız düzeltme iOS'ta neredeyse hiç iz üretmezdi. AppCheckCore `GACAppCheck.m` eşzamanlı jeton isteklerini tek istekte birleştiriyor (`ongoingRetrieveOrRefreshTokenPromise`), yoklama Firestore'un isteğinin yanında ikinci attestation doğurmaz. Ölçüldü (`test/app_check_izi_test.dart`, 13): yoklama yalnız iOS + yayın (Android, debug, web kapalı); düşen ve boş jeton kaydediliyor, gelen jeton kaydedilmiyor; senkron fırlatma da yutuluyor; varsayılan kanal debug'da Crashlytics'e dokunmuyor (Firebase kurulu değilken fırlatmadı); etkinleştirme hatası kendi nedeni ve yığınıyla; kaynak bekçileri `main.dart`'ta catch'in yığınla kaydettiğini, yoklamanın `unawaited` olduğunu ve `activate`'ten sonra, `runApp`'ten önce kurulduğunu sabitliyor.
Düzeltmeden sapma: jeton yoklaması yalnız iOS. Android'de yoklama yeni bir Play Integrity isteği demek (günlük kotalı); Android SDK'sında eşzamanlı istek birleşmesi burada doğrulanamadı ve Android davranışı Windows oturumunun. Android'de değişen tek şey: yayında `activate` hatası artık Crashlytics'e non-fatal yazılıyor.
Kalan: A5 — ilk TestFlight kurulumunda Crashlytics'te `app-check-token` / `app-check-activate` kaydı aranır; kayıt yoksa ve giriş çalışıyorsa App Attest jetonu alınmıştır.

**Android güvenliği** — Ortak kod; Android'de de yalnız release kaydı ekler.

### U31 — Apple girişi, Google ya da şifreyle kayıtlı e-postada genel hata veriyor
✅ kapandı · ORTA · kod · A3 ortak kod · kaynak: `apple-account-exists-different-credential`

**Kanıt** — `lib/core/auth_service.dart:152-173` `authErrorText`'te `account-exists-with-different-credential` yok (yalnız `phone_verify_screen.dart:267` ele alıyor); varsayılan `authFailed`.

**Etki** — Tipik geçiş: Google ile (x@gmail.com) kayıt olmuş Android kullanıcısı iOS'ta en üstteki Apple düğmesine basar, aynı e-postayı paylaşır. Firebase'in varsayılan "e-posta başına tek hesap" ayarıyla `account-exists-with-different-credential` fırlar; kullanıcı yalnız "Giriş yapılamadı" görür, Google'ı kullanması gerektiğine dair ipucu yok. (Proje e-posta başına çok hesaba izin veriyorsa kullanıcı sessizce ikinci, boş bir hesap alır — daha kötü.)

**Düzeltme** — Yeni durum `authErrorText`'e (giriş ve öteki çağıranlar paylaşsın), TR+EN arb anahtarları, `flutter gen-l10n`. Açık kullanıcı onayı olmadan otomatik bağlama YOK: Firebase'in Apple belgesi, Apple hesaplarını başka verilere bağlamadan önce Apple'ın açık onay istediğini not ediyor.

Kapandı: `[iOS] U04 U15 U31 U45 U48 U49: giris ve hesap silme akisi` — `authErrorText`'e `account-exists-with-different-credential` → `authAccountExistsOtherMethod` (TR+EN): hesabın başka yöntemle var olduğunu söyler ve üç yöntemi sayar, hangisi olduğunu iddia etmez (Firebase söylemiyor); otomatik bağlama yok. Ölçüldü (`test/giris_ios_test.dart`): birim eşlemesi ve iOS giriş ekranında Apple akışından gelen hatanın bu metinle gösterildiği.

**Android güvenliği** — Ortak hata eşlemesi; Android'de de aynı durum doğru mesajı alır.

### U32 — Rytho+ aynı anda tek cihazda: 3.1.2(a) ile çelişiyor
⏳ açık · ORTA · kod · A3 ortak kod · kaynak: `single-device-lock-vs-3-1-2a`

**Kanıt** — `backend/core/device.py:67` `DEVICE_CONFLICT_STATUS = 409`. Sınır Koşullar'da açıkça yazılı: `lib/features/profile/legal_texts.dart:56-57` ("Abonelik ve tek cihaz") ve `:359-360` (EN).

**Etki** — İki cihaz kullanan abone (ya da iki cihazda test eden inceleyici) ikincisinde 409 "hesap başka cihazda açık" kapısına takılır ve aboneliği her seferinde geri almak zorunda kalır. İnceleyici kısıtı hem uygulamada hem hukuk metninde bulup 3.1.2(a)'yı gösterebilir. Kesin red değil, risk: abonelik her cihazda çalışıyor, yalnız aynı anda değil.

**Sahibin kararı** — Platform başına bir cihaz (bir iPhone + bir Android aynı anda).

**Düzeltme** — Kilit platform başına yuvaya bölünür; mevcut tek-talep dokümanı geriye uyumluluk için 1. yuva olarak okunur. Karar gereği Koşullar metni (TR+EN) yeni kurala göre güncellenir. İnceleme işletimi: demo hesap inceleme boyunca başka yerde açık olmamalı. `docs/store-review-notes.md`'ye: ücretli hesap platform başına bir etkin cihazla sınırlı, "Bu cihazda kullan" ile taşınır, deneme hesapları kısıtlı değil.

**Android güvenliği** — Kuralı yalnız gevşetir.

### U33 — Satın alma hata eşlemesinde iOS için önemli kodlar eksik
✅ kapandı · ORTA · kod · A3 ortak kod · kaynak: `purchase-error-mapping-ios-codes`

**Kanıt** — `lib/core/purchase_errors.dart:61-85` `storeErrorText`: `paymentPendingError` ve `configurationError` varsayılana (`purchaseFailed` + kayıt) düşüyor; `purchaseNotAllowedError` "birkaç dakika sonra tekrar dene" diyen `purchaseStoreProblem`'e eşleniyor (`:74-76`). `lib/features/profile/subscription_screen.dart:89-96` `_restore` hatayı eşleyiciyi atlayıp `friendlyError` ile gösteriyor.

**Etki** — iOS'ta Ask to Buy (Aile Paylaşımı çocuk hesabı) ve ek onay isteyen ödemeler `paymentPendingError` verir: kullanıcı "Satın alma tamamlanamadı" görür, oysa satın alma sonradan gerçekleşebilir; Crashlytics'e gürültü. Ekran Süresi'nde "Uygulama İçi Satın Alma: İzin Verme" varken `purchaseNotAllowedError` birkaç dakika sonra denemeyi söyler — asla işe yaramaz. Abonelik ekranında restore hataları genel "beklenmeyen hata" gösterir.

**Düzeltme**
1. `paymentPendingError` → yeni `purchasePending` (TR: "Ödemen onay bekliyor; onaylanınca Rytho+/krediler otomatik açılır."); kaydedilmez. Paywall `_buy` (`paywall_screen.dart:96`) ve kredi mağazası `_buy` (`token_store_screen.dart:56`) bunu nötr bilgi olarak (macenta hata metni değil) gösterir ve `subscriptionProvider`/`walletProvider`'ı geçersiz kılar ki sonraki webhook açsın.
2. `purchaseNotAllowedError` kendi anahtarına, `defaultTargetPlatform`'a göre: iOS "Bu cihazda uygulama içi satın alma kapalı (Ayarlar › Ekran Süresi)."; Android mevcut `purchaseStoreProblem` metnini bayt bayt korur ya da nötr "Mağaza hesabını/uygulamasını kontrol et".
3. `configurationError` → `billingNoPackages`; `magazaHatasiKaydedici` çağrısı KALIR (çizim yolunda `magazaVeyaAgHatasi` ile tekilleştiriliyor).
4. `_restore`: PlatformException dalında `friendlyError(e, l10n)` yerine `storeErrorText(e, l10n)`.
5. Yeni anahtarlar `app_tr.arb` + `app_en.arb`.

Kapandı: `[iOS] U33 U46 U47: satin alma hata eslemesi, magaza metinleri, abonelik yonetimi` — `purchase_errors.dart` `storeErrorText`: `paymentPendingError` → `purchasePending`, kaydedilmez; `purchaseNotAllowedError` iOS'ta `purchaseNotAllowedIos` (Ekran Süresi), Android'de `purchaseStoreProblem` bayt bayt; `configurationError` → `billingNoPackages` + kayıt (çizim yolunda kod başına bir kez). Kodların iOS kaynağı RevenueCat 5.67.1 kaynağında okundu (`ios/Pods/RevenueCat`): bekleyen ödeme StoreKit 1 `.deferred` (`PurchasesOrchestrator`) ve StoreKit 2 `.pending`'den (`StoreKit2TransactionListener`); kısıt `paymentNotAllowed` / `clientInvalid` / `cloudServicePermissionDenied` / SK2 `purchaseNotAllowed`'dan; kurulum hatası iOS'ta asıl `getOfferings`'ten — teklifteki ürünlerin hiçbiri App Store Connect'ten gelmezse (`OfferingsManager`). Yani paywall'ın hata kartı eskiden henüz satın alma yokken "Satın alma tamamlanamadı" diyordu. Paywall `_buy` bekleyen ödemeyi macenta `_error` yerine ayrı `_bilgi` alanında nötr renkle gösteriyor, kredi mağazası bilgi snack'iyle; ikisi de `odemeOnayiBekleniyor` ile önbelleği düşürüyor (paywall abonelik + cüzdan; kredi mağazası yalnız cüzdan, çünkü abonelik sağlayıcısını düşürmek ona bağlı ücretli sağlayıcıları da yeniden kurar). Abonelik ekranı `_restore` PlatformException'ı `storeErrorText`'ten geçiriyor. Test dikişleri: `paketSatinAliciProvider`, `krediPaketiSatinAliciProvider`, `geriYukleyiciProvider`. Ölçüldü (`test/magaza_ios_uyum_test.dart`): iki platformda bekleyen ödeme metni ve kayıtsızlık; kurulum hatası metni + kayıt (satın alma yolunda her deneme, çizim yolunda bir kez); iOS kısıt metni, Android eski metin; paywall'da bekleyen ödeme macenta değil ve abonelik sağlayıcısı yeniden kuruluyor, gerçek mağaza hatası hâlâ macenta; kredi mağazasında cüzdan yeniden kuruluyor, abonelik kurulmuyor; abonelik ekranında ağ hatası artık `authNetwork` (eskiden `errorGeneric`). Mutasyonla: paywall'dan geçersiz kılma silinince ve kredi mağazası aboneliği de düşürünce ilgili iki test düştü.
Ölçülen sınır: geçersiz kılma onayı BEKLEMEZ. İki sağlayıcı da paywall açıkken altta duran Gökyüzü ekranında izleniyor (kredi çipi, kilitli şeritler), yani çağrı onları hemen yeniden okutur ve sunucu o an "abone değil" der. Düzeltme metnindeki "ki sonraki webhook açsın" bu çağrıyla gerçekleşmiyor: sonradan gelen onay ekrana bir sonraki tazelemede (Gökyüzü'nde çek-yenile, geri yükleme, yeniden açılış) yansır; sunucu kapısı webhook'la kendiliğinden kalkar.
Kalan: A5 — gerçek iPhone'da sandbox Ask to Buy (Aile Paylaşımı çocuk test hesabı): paywall nötr bilgi göstermeli, Crashlytics'te `store-purchase: 20` olmamalı. İsteğe bağlı: onayın açık ekrana kendiliğinden yansıması istenirse `Purchases.addCustomerInfoUpdateListener` + sunucu yoklaması; dinleyici eklenir eklenmez son bilinen müşteri bilgisiyle çağrılıyor (purchases_flutter 9.16.1), yani bir değişiklik tabanı gerekir.

**Android güvenliği** — Mevcut durumlar aynen kalır; Android davranışı yalnız iyileşir.

### U34 — Davet ve web sayfaları yalnız Google Play'e bağlanıyor
⏳ açık · ORTA · ikisi · A3 ortak kod · kaynak: `invite-landing-page-play-only`, `web-store-links-play-only`, `invite-landing-play-only`

**Kanıt** — `web/i/index.html:72-79` yalnız "Google Play'den indir" sunuyor (yorum iOS'u kapsam dışı sayıyor); `web/auth/action/index.html:209` yalnız Play; `web/index.html:100, :334` ve `web/en/index.html:99, :337` App Store düğmeleri `href="#" aria-disabled="true"`.

**Etki** — iOS kullanıcısı `https://rytho.app/i/<kullanıcı>`'yı uygulaması olmayan iPhone'lu arkadaşına paylaşır; arkadaş iOS'ta çıkmaz sokak olan bir Play düğmesi görür. Davet sosyal büyüme döngüsü; iOS davetlileri kaybolur. E-posta doğrulama ya da şifre sıfırlama sonrası iPhone'da da aynısı. Lansmandan sonra açılış sayfası iOS'u hâlâ "yakında" diye anar; App Store metaverisinde kullanılan site inceleyiciye iOS sürümünün olmadığını söyler. İnceleme engelleyicisi değil, parite boşluğu.

**Düzeltme** (`APPSTORE_APP_ID` gerekir — U02)
- `web/i/index.html` ve `web/auth/action/index.html`: iOS algılama `/iPhone|iPad|iPod/.test(navigator.userAgent)` ya da iPadOS için `navigator.platform==='MacIntel' && navigator.maxTouchPoints>1`. iOS'ta düğme `https://apps.apple.com/app/id<ID>`, metin "App Store'dan indir" / "Download on the App Store"; ötekilerde Play kalır. Uygulama canlı olana dek "iOS yakında" notu.
- `/i/` ve açılış sayfalarına Safari Smart App Banner: `<meta name="apple-itunes-app" content="app-id=<ID>, app-argument=https://rytho.app/i/...">` (yalnız uygulama App Store'da canlıyken görünür).
- Onaydan sonra `web/index.html` + `web/en/index.html`'deki devre dışı App Store düğmeleri ve SSS metni gerçek URL'ye; "iOS hazırlanıyor" metni kalkar.
- `backend/tests/test_davet_sayfasi.py`: UA dalına izin verir, ama `href="#"` olmadığını ve App Store URL'sinin sayısal kimlik taşıdığını doğrular.
- `APPSTORE_APP_ID` → `dart_defines.local.json`. Dağıtım AASA TEAMID düzeltmesiyle birlikte: `firebase deploy --only hosting --project rhytoai`.

**Android güvenliği** — Play bağlantısı iOS dışındaki herkes için aynen kalır.

### U35 — Herkese açık hesap silme sayfası aboneliği yalnız Google Play'de iptal etmeyi anlatıyor
⏳ açık · ORTA · kod · A3 ortak kod · kaynak: `web-deletion-page-play-only-cancel`

**Kanıt** — `web/legal/hesap-silme.html:55` ve `web/en/legal/delete-account.html:54`: "Google Play aboneliklerinden iptal etmelisiniz".

**Etki** — Gizlilik politikasından ve mağaza kayıtlarından bu sayfaya gelen iOS Rytho+ abonesi aboneliği Google Play'de arar, bulamaz ve Apple tarafından ücretlendirilmeye devam eder: şikâyet ve iade talebi; Apple'ın silme rehberiyle çelişki.

**Düzeltme** — Cümle iki mağazayı da kapsar, iki dosyada: TR örnek "iPhone'da Ayarlar → Apple Kimliği → Abonelikler (https://apps.apple.com/account/subscriptions), Android'de Google Play → Abonelikler"; EN karşılığı. Hosting yeniden dağıtılır.

### U36 — Paralel Android geliştirmesine karşı otomatik iOS bekçisi yok
⏳ açık · ORTA · kod · A3 ortak kod · kaynak: `no-ios-build-guard-for-parallel-android-dev` (eksik avcısı)

**Kanıt** — Depo kökünde `.github/` yok, `infra/`'da yalnız `build-aab.ps1`. `apps/mobile/pubspec.yaml:47, :59` şapkalı aralıklar (`purchases_flutter: ^9.10.4`, `camera: ^0.11.2`): Windows'ta `flutter pub upgrade` `pubspec.lock`'u değiştirir, ama `ios/Podfile.lock` ve iki `Package.resolved` yalnız Mac'te tazelenir. `backend/tests/test_ios_config.py` bundle kimliği, Google URL şeması, aps ayrımı, Podfile/pbxproj hedefi, ihracat bayrağı ve STRIP_STYLE'ı denetliyor; eklenti başına izin metni kapsamını ve derlenebilirliği değil. `.gitignore:67` tflite modelini izlemiyor; temiz checkout derlemesi modeli önce indirmeli.

**Etki** — Android tarafındaki bir değişiklik derlenip Play'e çıkarken iOS'u kırabilir; bu ancak Mac bir sonraki derlemede — belki iOS gönderim günü — görülür. Örnekler: iOS kodu kamera/mikrofon/konum/fotoğraf API'sine başvuran ama Info.plist anahtarı olmayan yeni eklenti (yüklemede ITMS-90683 ya da çalışırken TCC çökmesi); iOS tabanını 15.5'in üstüne çeken ya da Xcode 27 isteyen bir eklenti sürümü; yalnız Android'de kullanılan bir Dart API'si. Ortak pubspec sürümü (+N) iki platformun build numarası artışlarını da koordine etmeyi gerektirir; bunlar `min_build` kapısını da besler.

**Düzeltme**
1. Windows'ta zaten koşan `backend/tests/test_ios_config.py` genişletilir: `pubspec.yaml`'daki gözden geçirilmiş bağımlılıklar gerektirdikleri Info.plist anahtarlarına eşlenir — camera → `NSCameraUsageDescription` + `NSMicrophoneUsageDescription`; image_picker → `NSPhotoLibraryUsageDescription`; flutter_contacts → `NSContactsUsageDescription`; share_plus → `NSPhotoLibraryAddUsageDescription`. Gözden geçirilmemiş bir bağımlılık görünce düşer; Android makinesi iOS etkisini işaretlemeye zorlanır.
2. İsteğe bağlı: `master`/`ios-hazirlik`'e push'ta GitHub Actions macOS işi — Xcode 26.x seçer, tflite modelini `scripts/fetch_models.ps1`'deki URL'den indirir, CI dart-define'larıyla `flutter build ios --release --no-codesign`.
3. CLAUDE.md kuralı: Android makinesi Mac derleme kontrolü olmadan `flutter pub upgrade` koşmaz ve eklenti eklemez; `Podfile.lock` ve `Package.resolved` yalnız Mac'te güncellenir.
4. Build numaraları: iki makinede de HER mağaza yüklemesinden önce pubspec `+N` artırılır, asla yeniden kullanılmaz. Düz tamsayı kalır — `lib/core/app_config.dart:53` `int.tryParse(buildNumber)` yapıyor; noktalı bir CFBundleVersion 0 okunur.

**Android güvenliği** — Test, CI ve süreç; test yalnız dosya okur, Android derlemesi değişmez.

### U37 — Görünen ad ve profil fotoğrafı UGC; belgeler "UGC yok" ve artık olmayan 12+ derecesini planlıyor
⏳ açık · ORTA · ikisi · A4 mağaza · kaynak: `ugc-surface-and-age-rating`

**Kanıt** — `docs/store-launch.md:158` "1.2 — UGC: Uygulanmıyor"; `docs/store-privacy-labels.md:147` "Other user-generated content? HAYIR"; `:220` ve `docs/production-checklist.md:175` App Store 12+. Uygulama onboarding'de 13+ beyanı istiyor.

**Etki** — Yaş derecelendirmesi anketi yanlış cevaplanır (2.3.6); başka kullanıcıların profil fotoğrafını ve adını gören inceleyici 1.2'yi (filtreleme, EULA'da sıfır tolerans) uygulayabilir. Beyan edilen derece uygulamadaki 13+ sözüyle de uyuşmaz.

**Düzeltme** — Yaş anketi: Messaging and Chat = Evet. User-Generated Content: Apple'ın "geniş dağıtım" tanımıyla "Hayır" savunulabilir — gerekçe yazılır; ama "Evet"in bedeli yok (4+'da izinli). Social Media = Hayır. Ardından yaş derecesi geçersiz kılmasıyla Koşullar'a uyan 13+. 1.2 için değerli sağlamlaştırma (engelleyici değil): ad kara listesi, bildirimde admin'in ad/fotoğrafı sıfırlaması, Koşullar "Davranış" bölümünde sıfır tolerans maddesi (TR+EN). Hâlâ 12+ diyen belgeler güncellenir.
- (U17'den devir, 2026-10-22) **Şikayet görünümü ya da uyarısı:** `reports` koleksiyonu yalnız sahibin Firebase konsolundan okunuyor; istatistik işi `reports` koleksiyonunun toplam SAYISINI üretiyor (`backend/services/stats_service.py` `social.reportsOpen` — adına rağmen "açık" ayrımı yok, çözülme durumu tutulmuyor) ama panel o alanı HİÇ okumuyor (`web/rytho-admin/` içinde `reportsOpen`/`social` geçmiyor — ölçüldü 2026-10-22); yani panelde ne sayı ne içerik var, yeni şikayette uyarı da yok. 1.2'nin "zamanında yanıt" şartı (ve U18'deki 24 saat sözü) şikayetin fark edilmesine bağlı: panelde şikayet listesi (şikayet eden, hedef, sebep, tarih) ve/veya yeni şikayette sahibe bildirim.

**Ek (ölçüldü 2026-10-23)** — Kanıt'taki 12+ hâlâ iki belgede (`store-privacy-labels.md:220`, `production-checklist.md:175`); Koşullar'da (`legal_texts.dart`) "sıfır tolerans / zero tolerance" geçmiyor; panelde şikâyet görünümü yok (`web/rytho-admin/gorunumler/` altında yok, `stats_service.py` `reportsOpen` üretiyor ama panel okumuyor). `docs/store-launch.md` "Apple App Store" tablosundaki "1.2 — UGC: Uygulanmıyor" satırı bu kayda göre düzeltildi (eski metni tarihiyle yanında). Yaş anketinin App Store Connect yolu `docs/mac-devir.md` §4 **C4**.

### U38 — Review notları yüz okumayı ve yalnız TR telefon kapısını anmıyor
⏳ açık · ORTA · ikisi · A4 mağaza · kaynak: `review-notes-omit-face-reading-and-phone-gate` (eksik avcısı)

**Kanıt** — `docs/store-review-notes.md:141-152` önerilen gezinti: Sky, Atlas, Oracle/BaZi, Chat, Bildirimler, Hesap silme — yüz okuma ve telefon/rehber yok. `backend/api/face_reading.py:96, :111, :140`: Plus şartı, biyometrik onay kontrolü, yüz oranlarının `report_service.firasa_report(...)` ile LLM'e gitmesi; Guideline 5.1.2(vi) yüz haritalama araçlarından toplanan verinin pazarlama, reklam ya da kullanım temelli veri madenciliği için kullanılmasını yasaklıyor. `lib/features/profile/phone_verify_screen.dart:73, :111-112` `_smsBolgeleri = {'TR'}` → `phoneRegionUnsupported` (`app_en.arb:874`, yalnız +90); `lib/core/contact_match.dart:209-214` doğrulanmış telefon yoksa `telefonYok`. `docs/konsol-gorevleri.md:258-261` Firebase Auth test telefon numarasını kaydediyor.

**Etki** — İnceleyici kullanıcının yüzünü analiz eden bir kamera özelliği bulur, notlarda açıklama yok: böyle uygulamalar genelde 2.1 bilgi talebi alır (hangi yüz verisi, nasıl kullanılıyor, paylaşılıyor mu, ne kadar tutuluyor) — bir tur daha. Türkiye dışındaki inceleyici arkadaş eşleşmesini denerken +90 SMS adımında durur ve özelliği "çalışmıyor" diye bildirebilir (2.1).

**Düzeltme**
- `docs/store-review-notes.md` §3'e (ve ASC App Review Information notlarına) "Face reading" paragrafı: algılama cihazda (ML Kit + TFLite); hiçbir görüntü cihazdan çıkmaz; ayrı biyometrik onaydan sonra TLS üzerinden yalnız yuvarlanmış geometrik oranlar gider; oranlar yalnız o okumayı onayda adı geçen AI sağlayıcısıyla üretmek için kullanılır; kimlik tespiti, reklam ya da veri madenciliği yok (5.1.2(vi)); saklama süresi (`report_service`'in ne sakladığına bakılıp yazılır).
- Gezintiye yüz okuma adımı: Plus ister, demo hesapta var.
- Telefon satırı: doğrulama isteğe bağlı ve yalnız rehber eşleşmesi için; SMS yalnız +90; test numarası ve kodu ASC notlar alanına (herkese açık belgelere DEĞİL).
- Metin U18'deki düzeltilmiş notlarla hizalanır.

### U39 — Giriş duvarının gerekçesi notlarda yok (5.1.1(v) Account Sign-In)
⏳ açık · ORTA · ikisi · A4 mağaza · kaynak: `login-wall-5-1-1-v-justification` (eksik avcısı)

**Kanıt** — `lib/main.dart:279` `if (user == null) return const LoginScreen();`: canlı gökyüzü ve efemeris içeriği dahil her şey girişin arkasında. `docs/store-review-notes.md:110-163` (§3) 4.3 farkını, satın almaları ve silmeyi anlatıyor; zorunlu kaydın gerekçesi yok.

**Etki** — Burç/astroloji uygulamaları "hesaba dayanmayan özellik için kayıt şartı" reddinin sık hedefi. Rytho'nun gerçek hesap özellikleri var (sunucuda doğum haritası ve hafıza, cihazlar arası abonelik ve kredi cüzdanı, arkadaş katmanı), yani savunulabilir; ama notlar söylemezse inceleyici genel görünen içeriğin önünde yalnız bir giriş duvarı görür.

**Düzeltme** — Asgari: notlara kısa "Why an account is required" paragrafı — doğum haritası, damıtılmış hafıza ve okumalar kullanıcı başına sunucuda saklanıp cihazlar arası eşitlenir; Rytho+ ve kredi cüzdanı sunucuda, iPhone ve Android'de çalışır; arkadaş/uyum katmanı kimlik ister; AI kullanımı hesap başına kota ve kötüye kullanım denetimli; Apple ile Giriş bunu tek dokunuş yapar. İsteğe bağlı, daha güçlü: girişten önce sınırlı misafir önizlemesi (ör. bugünün canlı gökyüzü). Ürün değişikliği — iki platform için birlikte karar.

**Android güvenliği** — Yalnız not değişikliği kodsuz. Misafir önizlemesi ortak Dart'a dokunur: bayrak arkasında ve birleştirmeden önce Android'de test.

### U40 — iOS'ta Apple ile açılan hesap Android'de giremiyor
⏳ açık · ORTA · ikisi · Sonra · kaynak: `apple-signin-android-parity`

**Kanıt** — `lib/core/auth_service.dart:28-29` Apple girişi yalnız iOS'ta. `useGoogleInstead` (`app_tr.arb:742`, `app_en.arb:742`) Android'de de "Google/Apple ile açılmış olabilir — aşağıdaki düğmeleri dene" diyor, oysa orada Apple düğmesi yok. İkinci giriş yolu ekleme `linkPassword` ile mevcut (`auth_service.dart:200-214`).

**Etki** — Ürün iki platformda tek hesap (devralmalı tek cihaz kilidi cihaz değiştirmek için yapıldı). iOS'ta Apple ile — özellikle Hide My Email ile — kayıt olan kullanıcının Android'de aynı hesaba yolu yok: Apple düğmesi yok, şifre yok, aktarıcı adresi bilinmiyor. Yeni boş hesap açar ya da desteğe yazar.

**Düzeltme** — Kısa vade (Android'e güvenli, öne çekilebilir): iOS korumalı "şifre bağla" dürtmesi; Android'de `useGoogleInstead` var olmayan Apple düğmelerini anmasın ya da platforma duyarlı olsun. Uzun vade — **ertelendi:** Android'de Apple ile Giriş; Services ID ve dönüş URL'si ister, Android makinesinde yapılır.

### U41 — AB DSA tacir beyanı ve v1 bölge seçimi için runbook yok
⏳ açık · ORTA · hesap · Sonra · kaynak: `asc-dsa-trader-and-territory-decisions` (eksik avcısı)

**Kanıt** — Apple'ın DSA tacir sayfası: AB'de dağıtım yapılmasa bile tacir durumu beyan edilmeli; doğrulanınca bilgiler AB ürün sayfasında yayınlanır. Apple haberi (23 Aralık 2025): Texas SB2420 duraklatıldı; yaş araçları 2026'da yürürlüğe giren Utah ve Louisiana yasalarına yönelik. `docs/mac-devir.md:93-207` (§4.1–4.9) DSA ya da bölge adımı içermiyor; depodaki tek DSA anışı `docs/store-review-notes.md:75` (moderasyon bağlamı).

**Etki** — Uygulama abonelik ve kredi sattığı için sahip "tacir"dir. Bireysel hesapta Apple her AB ürün sayfasında bir adres (ya da posta kutusu), telefon ve e-posta yayınlar — gönderim anında doğaçlanmamalı. ABD'de dağıtım Utah/Louisiana yaş doğrulama yükümlülükleri getirebilir; henüz değerlendirilmedi.

**Sahibin kararı** — Yalnız Türkiye: ABD yaş yasaları kapsam dışı; AB'de yayınlanacak iletişim bilgisinin hazırlığı AB'ye açılana dek ertelendi. Kaynağa göre tacir durumu sorusu AB dışı dağıtımda da cevaplanır; o soru ASC kurulumunda yanıtlanır.

**Düzeltme** (AB'ye açılırken)
1. ASC > Business: tacir durumu; `legal_texts.dart` `kLegalContact` ile tutarlı posta kutusu ya da iş adresi, ayrı destek telefonu ve e-postası. Apple doğrular, günler sürebilir — erken başlanır.
2. Pricing and Availability: bölgeler bilinçli seçilir; ABD eklenecekse yaş doğrulama yükümlülükleri değerlendirilir ya da ABD ertelenir.
3. İki adım `docs/mac-devir.md` §4'e "SEN" maddeleri olarak.

**Ek (2026-10-23)** — Madde 3 yapıldı: tacir sorusu `docs/mac-devir.md` §4 **B3**'te (App Store Connect → Business; AB dışı dağıtımda da cevaplanır), bölge seçimi **C6**'da (Pricing and Availability → yalnız Türkiye). AB'de yayınlanacak iletişim bilgisinin hazırlığı sahibin kararıyla ertelenmiş kalır. App Store Connect ölçülemedi; kayıt ⏳ açık kalır.

---

## DÜŞÜK

### U42 — App Attest yetkisi iki entitlements dosyasında da yok
✅ kapandı — `54130b9` · DÜŞÜK · kod · A2 iOS kod · kaynak: `app-attest-entitlement-missing`, `app-attest-entitlement-and-mac-availability` (yetki kısmı)

**Kanıt** — Tabanda `ios/Runner/Runner.entitlements` ve `RunnerRelease.entitlements` `aps-environment`, `applesignin` ve `associated-domains` taşıyor; `com.apple.developer.devicecheck.appattest-environment` yok.

**Etki** — TestFlight ve App Store paketleri etkilenmez (Apple production ortamını zorlar); bugünkü bir hatanın nedeni bu değil. Ama geliştirme ya da ad hoc imzalı bir Release/Profile paketi gerçek cihaza kurulursa (ör. ödünç telefona Xcode'dan) sandbox'a karşı attest eder; Firebase o jetonları reddeder ve zorlama açıkken giriş ve Firestore nedeni belirsiz biçimde düşer. Proje Firebase'in belgelenmiş kurulumundan da sapıyordu.

**Düzeltme** — Xcode → Runner → Signing & Capabilities → + App Attest; `com.apple.developer.devicecheck.appattest-environment = production` İKİ dosyada (dosyalar `aps-environment` dışında aynı kalır — `test_ios_config.py` bunu şart koşuyor). Debug `AppleDebugProvider` kullanır, anahtarın orada etkisi yok. App Check'te App Attest kaydından önce Firebase iOS uygulamasında Team ID dolu olmalı (U08). `54130b9`: iki dosyada production, `test_ios_config.py` geçti.

### U43 — iOS paketi IDFA destekli Firebase Analytics yığınını bağlıyor
✅ kapandı — `4ba7d9d` · DÜŞÜK · ikisi · A2 iOS kod · kaynak: `firebase-analytics-idfa-ios-vs-android`, `analytics-adid-stack-ios`, `privacy-text-android-framed-idfa` (derleme kısmı)

**Kanıt** — `firebase_analytics` 12.4.5 `ios/firebase_analytics.podspec:7-9`: `$FirebaseAnalyticsWithoutAdIdSupport` tanımlı değilse tam `FirebaseAnalytics` (IdentitySupport + AdsOnDeviceConversion) bağlanıyor. Android AD_ID iznini bilerek kaldırdı (`legal_texts.dart:139-142`); gizlilik belgeleri "reklam kimliği yok / cihaz kimliği yok" diyor.

**Etki** — Aynı ürün kararında iki platform ayrışıyor: iOS ikilisi Android'in söktüğü IDFA okuyan kodu ve Google Ads dönüşüm kodunu taşıyor. ATT istemi olmadığı için IDFA çalışma anında sıfır döner; ama gönderilen ikili politika ve etiketteki duruşla eşleşmiyor — etiket uyuşmazlığı ya da incelemede soru (5.1.2), üstelik kullanılmayan ikili ağırlığı. İlk sürümden önce isteğe bağlı.

**Düzeltme** — Bağımlılık yöneticisi seçimine (U25) bağlı:
- Yalnız CocoaPods: `ios/Podfile`'ın en üstüne `$FirebaseAnalyticsWithoutAdIdSupport = true`.
- SwiftPM: SwiftPM her çözümlemede ortam değişkenini görmeli — `FIREBASE_ANALYTICS_WITHOUT_ADID=true flutter build ipa` (ya da Xcode değişkeni dışa aktarmış bir kabuktan açılır); önce paket önbellekleri bir kez temizlenir (`build/ios/SourcePackages`, DerivedData). Xcode arayüzünden alınan arşivler kabuk değişkenini görmez. Kırılgan: CocoaPods geçişiyle birlikte yapılır ya da ertelenir.
- Doğrulama: `FirebaseAnalyticsCore` çözülüyor; `GoogleAppMeasurementIdentitySupport`, `GoogleAdsOnDeviceConversion` ve AdSupport `.app`'ten gitmiş.
- ASC App Privacy cevapları "yalnız User ID" varsayımıyla değil, Google'ın Firebase veri açıklama rehberiyle karşılaştırılır (U20).
- `4ba7d9d`: CocoaPods yolu (U25) + Podfile'da kalıcı `$FirebaseAnalyticsWithoutAdIdSupport = true` (Xcode arşivinde de geçerli). Ölçüldü: cihaz ikilisinde `ASIdentifierManager` başvurusu 0, IdentitySupport / AdsOnDeviceConversion çerçevesi 0. Kalan: ASC cevapları U20'de.

### U44 — Paylaşım kartı Fotoğraflar'a kaydedilemiyor; iPad'de paylaşım balonu konumsuz
✅ kapandı — `54130b9` · DÜŞÜK · kod · A2 iOS kod · kaynak: `missing-photo-library-add-usage`, `ipad-share-origin-and-save-image`

**Kanıt** — Tabandaki `ios/Runner/Info.plist`'te `NSPhotoLibraryAddUsageDescription` yok; `lib/features/share/share_card.dart:461-462` `SharePlus.instance.share(ShareParams(files: …))` `sharePositionOrigin` vermiyor.

**Etki** — iOS'ta paylaşım sayfasının "Resmi Kaydet" seçeneği görünmez; paylaşım kartını hikâyeye koymadan önce Fotoğraflar'a kaydetmek en yaygın yol. Android'de paylaşım hedefleriyle kaydetme çalışıyor — parite boşluğu; çökme ya da red yok. iPad'de balon düğmeden kopuk, ekran ortasında açılırdı (share_plus 13.3.0 ile çökme değil).

**Düzeltme** — Info.plist'e `NSPhotoLibraryAddUsageDescription`, İngilizce satır `InfoPlist.strings`'e (U27). `sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size` yalnız iPhone kararıyla (U10) gereksiz: iPad'de uyumluluk kipinde paylaşım düz sayfa. `54130b9`: anahtar TR ve en/tr varyantlarında. Paylaşım sayfasında "Resmi Kaydet"in göründüğü A5'te doğrulanır (U21).

### U45 — iOS'ta Firebase oturumu yeniden kurulumdan sağ çıkıyor, cihaz kimliği çıkmıyor
✅ kapandı · DÜŞÜK · kod · A2 iOS kod · kaynak: `ios-keychain-session-survives-reinstall`

**Kanıt** — Cihaz kimliği SharedPreferences'ta rastgele 128 bit (`lib/core/device_id.dart:3, :36, :53`) ve uygulama silinince gider; Firebase oturumu iOS'ta silmeden sağ çıkıyor. `lib/main.dart:154` `runApp`'ten önce yeniden kurulum işareti yok.

**Etki** — Android'de olmayan iOS'a özgü davranış: silip yeniden kuran abone uygulamayı zaten girişli açar — yeni cihaz kimliği, eski `auth_time` — ve DeviceConflictScreen'de başka bir cihazın (kendi eski kurulumunun) hesabı tuttuğunu görür. "Bu cihazda kullan" ile düzelir ama kafa karıştırır. Çıkış yapılmış olmayı bekleyerek silenler de otomatik girişli açılır.

**Düzeltme** — Yalnız iOS (`defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb`), `runApp`'ten önce: SharedPreferences işareti yoksa ve `currentUser != null` ise doğrudan `FirebaseAuth.instance.signOut()`. `signOutEverywhere` DEĞİL — o gezgin kapsayıcısına ve backend serbest bırakmaya uzanır. Sonra işaret yazılır, kullanıcı girişli olmasa da.

Kapandı: `[iOS] U04 U15 U31 U45 U48 U49: giris ve hesap silme akisi` — `core/device_id.dart` `iosYenidenKurulumOturumunuKapat`, `main`'de `runApp`'ten önce. Düzeltmeden iki sapma: (1) yeniden kurulumun izi "işaret yok" değil "depo BOMBOŞ" — yalnız işarete bakılsaydı işaretten önceki sürümden güncelleyen her iOS kullanıcısı bir kez çıkarılırdı; (2) işaret çıkıştan ÖNCE yazılır, yazılamazsa çıkış yapılmaz — her açılışta çıkış imkânsız. Çıkış doğrudan `FirebaseAuth.signOut()`. Ölçüldü (`test/yeniden_kurulum_test.dart`, 6): boş depo + oturum → tek çıkış, sonraki açılışlarda yok; eski depo → çıkış yok ama işaret yazılıyor; oturumsuz ilk kurulum → sonraki girişler korunuyor; fırlatan çıkış açılışı düşürmüyor ve tekrarlanmıyor; Android'de ne çıkış ne depo yazımı.
Kalan: A5 — simülatörde girişli iken sil + yeniden kur: uygulama giriş ekranında açılmalı; ikinci açılışta oturum korunmalı.

**Android güvenliği** — iOS korumalı; Android değişmez.

### U46 — Mağaza hata metinleri iOS'ta Google hesabını ve Play test kanalını anıyor
✅ kapandı · DÜŞÜK · kod · A3 ortak kod · kaynak: `store-error-wording-google`, `android-specific-purchase-copy-on-ios`

**Kanıt** — `lib/l10n/app_tr.arb:916-917` / `app_en.arb:916-917`: `purchaseAlreadyOwned` "Bu Google hesabında…", `purchaseItemUnavailable` "Test kanalına katılan hesabın…"; `lib/core/purchase_errors.dart:64-70` ikisini platforma bakmadan döndürüyor. `docs/mac-devir.md:238-240`'taki "Mağaza metinleri nötr … 'Google Play' yazmıyor artık" iddiası bu iki anahtar için yanlış.

**Etki** — `productNotAvailableForPurchaseError`'ın iOS'ta en olası anı App Review'dur (IAP'ler henüz onaysızken): inceleyici Android "test kanalı" talimatı okur; iOS satın alma akışında "Google hesabı" kafa karıştırır. Google ile Giriş uygulamada meşru olduğu için red riski küçük, ama gerçek parite boşluğu; TestFlight testçilerini de şaşırtır.

**Düzeltme** — `purchaseAlreadyOwned` iki ARB'de mağaza-nötr: "Bu mağaza hesabında zaten etkin bir abonelik var — satın alımların geri yükleniyor…". `purchaseItemUnavailable` ya nötr ("Ürün şu an mağazada bulunamadı; mağaza hesabını kontrol edip tekrar dene") ya da `storeErrorText` içinde `defaultTargetPlatform` ile seçilen iOS'a özgü anahtar. `flutter gen-l10n`; `mac-devir.md:238-240` iddiası düzeltilir.

Kapandı: `[iOS] U33 U46 U47: satin alma hata eslemesi, magaza metinleri, abonelik yonetimi` — Nötr metin yerine platform dalı seçildi, böylece Android'in test kanalı ipucu (Erkan vakası) bayt bayt kaldı. `storeErrorText` iOS'ta üç yeni anahtara gidiyor: `purchaseAlreadyOwnedIos` ("Bu Apple Hesabında zaten etkin bir abonelik var." — "geri yükleniyor…" ibaresi yok, çünkü geri yüklemeyi yalnız paywall kendiliğinden başlatıyor ve o dal bu metni göstermiyor), `purchaseItemUnavailableIos` (App Store, hesap talimatı yok: RevenueCat bu kodu StoreKit'in "ürün bu mağazada/şu an satılmıyor" hatalarından üretiyor) ve U33'ün `purchaseNotAllowedIos`'u. Paywall'daki "Play hesabında" yorumu mağaza-nötr yapıldı. `docs/mac-devir.md` §5'teki "Mağaza metinleri nötr" iddiası düzeltildi. Ölçüldü (`test/magaza_ios_uyum_test.dart`): iOS'ta `PurchasesErrorCode`'un TÜM değerleri TR ve EN'de gezildi, hiçbir metin kelime başına bağlı `Google` / `Play` / "test kanal" / "test track" içermiyor; Android'de dört kodun metni eskisiyle aynı ve test kanalı ipucu duruyor.

**Android güvenliği** — Platform dalı seçilirse Android'in test kanalı ipucu bayt bayt korunur.

**Birleşme notu (2026-10-22, `8d6f67b`)** — Windows'un D7'si "zaten satın alınmış" ve "ürün yok" metinlerini platformdan bağımsız yeniden yazmıştı ("Bu hesapta…", "Bu ürün şu anda mağazada sunulmuyor…"); iki kusur orada da kapanmış. `purchaseAlreadyOwnedIos` ve `purchaseItemUnavailableIos` kaldırıldı. Asıl bekçi ("iOS'ta hiçbir mağaza kodu Google/Play/test kanalı anmaz") kaldı ve geçiyor; kalan tek platform dalı `purchaseNotAllowedIos`.

### U47 — "Aboneliği yönet" aboneliğin alındığı mağazaya bakmıyor
✅ kapandı · DÜŞÜK · kod · A3 ortak kod · kaynak: `manage-subscription-cross-store`, `manage-subscription-ignores-origin-store`

**Kanıt** — `lib/features/profile/subscription_screen.dart:41-54` `storeSubscriptionUri` yalnız çalışan platforma göre dallanıyor (iOS → Apple abonelikleri, öteki → Play).

**Etki** — Hesap RevenueCat ve sunucu üzerinden iki platformda ortak; Android'de abone olup iPhone'da giren kullanıcı orada da Rytho+. "Aboneliği yönet" Apple sayfasını açar, abonelik orada yok, iptal yolunu bulamaz (tersi Android'de). Red riski değil (inceleyiciler App Store'dan abone olur), ama gerçek parite ve destek sorunu.

**Düzeltme** — İki yol, ikisi de iki platformu düzeltir: (a) `(await Purchases.getCustomerInfo()).managementURL` (RevenueCat kaynak mağazayı bilir); null (etkin mağaza aboneliği yok) ya da hatada `storeSubscriptionUri(productId)`'ye düşülür. (b) Backend modeline ve istemciye eklemeli `store` alanı: `APP_STORE` → Apple URL; `PLAY_STORE` → sku'lu Play URL; `PROMOTIONAL`/`STRIPE`/null → çalışan platform.

Kapandı: `[iOS] U33 U46 U47: satin alma hata eslemesi, magaza metinleri, abonelik yonetimi` — (a) ile (b)'nin ortası, yalnız istemcide: `subscription.dart` `abonelikKaynakMagazasi` RevenueCat müşteri bilgisinde etkin Rytho+ yetkisinin `EntitlementInfo.store`'unu okuyor (3 sn sınırı, hata yutuluyor, mağaza anahtarı yoksa hiç sorulmuyor); `subscription_screen.dart` `aboneligiYonetAdresi`: `appStore`/`macAppStore` → Apple sayfası, `playStore` → sku'lu Play sayfası, bilinmeyen/promosyon/test mağazası → `storeSubscriptionUri` (çalışan platform, eski davranış). `managementURL` yerine `store`: Play dalı mevcut sku'lu adresi (M1) kullanmaya devam ediyor ve kaynak bilinmeyince ne açılacağı kodda açık; `managementURL` ise iki platformda birden etkin abonelik varsa cihazın mağazasını gösteriyor (purchases_flutter belgesi). Backend değişmedi — webhook `store`u zaten yazıyor ama `/billing/status` döndürmüyor; (b) yeni bir deploy isterdi. İki adresin web yüzü HTTP düzeyinde ölçüldü (2026-09-27): Play adresi Google girişine, Apple adresi Android tarayıcı kimliğiyle `account.apple.com/account/manage/section/subscriptions`a yönleniyor. Sorgu sürerken ikinci dokunuş yok sayılıyor (`_yonetimAciliyor`). Geri yükleme doğrulandı: paywall'da ve Abonelik ekranında (ücretsiz ve abone görünümünde) "Satın alımları geri yükle" var; eklenecek bir şey yoktu. Ölçüldü (`test/magaza_ios_uyum_test.dart`): Play aboneliği iOS'ta sku'lu Play adresi (`:monthly` eki kırpılmış), App Store aboneliği Android'de Apple adresi, dört bilinmeyen kaynak iki platformda çalışan platformun adresi; `abonelikKaynakMagazasi` yetkinin mağazasını dönüyor, yetki yoksa / sorgu düşerse / anahtar yoksa / 3 sn'de cevap yoksa null; geri yükleme düğmesi üç ekran durumunda bekçide.
İnceleme düzeltildi: `[iOS] U47 inceleme: abonelik yonetimi ekran testi ve anahtarsiz yol bekcisi` — ilk commit'te düzeltmenin kendisi (`_manage`) hiçbir testte koşmuyordu: `musteriBilgisiGetiriciProvider` dikiş diye eklenmiş ama hiçbir test onu ezmiyordu ve `_manage` eski `storeSubscriptionUri`'ye dönse 694 test yeşil kalırdı. `SubscriptionScreen`'e `adresAcici` dikişi eklendi (`ForceUpdateScreen.launcher` deseni). Ayrıca "anahtar yoksa null" bekçisi yanlış gerekçeyle geçiyordu: işlev her hatayı yutup null döndüğü için kapı sökülse de sonuç null'du; artık yakalama dalının `debugPrint` izinin OLMADIĞINA bakıyor. Ölçüldü (`test/magaza_ios_uyum_test.dart`, +5): iOS'ta Play kaynaklı abonelik "Aboneliği yönet"te sku'lu Play adresini, Android'de App Store kaynaklı abonelik Apple adresini `externalApplication` kipinde açıyor; kaynak okunamazsa çalışan platformun adresi; sorgu sürerken ikinci dokunuş tek açılış. Mutasyonla: `_manage` `storeSubscriptionUri`'ye döndürülünce iki (eski `launchUrl` çağrısıyla dört) ekran testi, `_yonetimAciliyor` kapısı silinince ikinci dokunuş testi, anahtar kapısı silinince anahtarsız yol bekçisi düştü (`MissingPluginException` izi).
Kalan: A5 — Android'de alınmış abonelikle iPhone'da "Aboneliği yönet" Play sayfasını açmalı (girişten sonraki sayfa cihazda denenmedi).

**Android güvenliği** — Eski istemciler yeni alanı yok sayar.

### U48 — Telefon ve SMS kodu alanlarında iOS klavyesi kapatılamıyor
✅ kapandı · DÜŞÜK · kod · A3 ortak kod · kaynak: `ios-numeric-keyboard-no-dismiss`

**Kanıt** — Kod alanı `lib/features/profile/phone_verify_screen.dart:344-347` (`TextInputType.number`), telefon alanı `lib/widgets/phone_number_field.dart:254` (`TextInputType.phone`); `phone_verify_screen.dart:319` `ListView`'da `keyboardDismissBehavior` yok.

**Etki** — iPhone'da sayı tuş takımında Bitti/Return yok, sistem geri düğmesi de yok. Klavye açık kalır ve alanın altındaki "Kod gönder" / "Doğrula" düğmelerini örter; kullanıcı kaydırabileceğini tahmin etmek zorunda. Android'de geri tuşu var.

**Düzeltme** — İki TextField'a `onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus()` ve/veya `:319` ListView'a `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`.

Kapandı: `[iOS] U04 U15 U31 U45 U48 U49: giris ve hesap silme akisi` — `widgets/phone_number_field.dart` `sayiKlavyesiDisDokunus` (iOS'ta `onTapOutside` → odağı bırak) telefon ve SMS kodu alanlarında; `sayiKlavyesiKaydirmaDavranisi` (iOS'ta `onDrag`) doğrulama ekranının ListView'ında. Düzeltmeden sapma: ortak ekleme yerine iOS korumalı — Android'de ikisi de null, yani Flutter varsayılanı (mobilde dokunmayla odak bırakılmaz, kaydırma klavyeye dokunmaz) aynen kalır. Ölçüldü (`test/sayi_klavyesi_test.dart`, 6): iOS'ta alan dışına dokunmak odağı bırakıyor, Android'de bırakmıyor; ListView iOS'ta `onDrag`, Android'de null.

**Android güvenliği** — iOS korumalı (`defaultTargetPlatform`); Android bayt bayt aynı.

### U49 — Apple/Google giriş sayfasını kapatmak "giriş başarısız" gösteriyor ve Crashlytics'e yazıyor
✅ kapandı · DÜŞÜK · kod · A3 ortak kod · kaynak: `social-signin-cancel-shows-error`

**Kanıt** — `lib/features/auth/login_screen.dart:102-129` `_runSocial`'ın genel `catch`'i (`:110`) iptali de yakalıyor: `recordError('social-signin: …')` (`:122-124`) ve `authFailed` snack'i.

**Etki** — iOS'ta Apple sayfasını kapatmak normal bir eylem. Kullanıcı (ve inceleyici) hata snack'i görür; Crashlytics gerçek hataları gizleyen sahte "social-signin" kayıtlarıyla dolar.

**Düzeltme** — Genel catch'ten önce `SignInWithAppleAuthorizationException` (`code == canceled`) ve `GoogleSignInException` (`code == canceled`) yakalanır; sessizce dönülür ya da nötr "Giriş iptal edildi" gösterilir, Crashlytics'e yazılmaz. Dikkat: bazı cihaz ve simülatörlerde iCloud hesabı yokken kapatma `AuthorizationErrorCode.unknown` (1000) olarak gelir — o kod bastırılmaz.

Kapandı: `[iOS] U04 U15 U31 U45 U48 U49: giris ve hesap silme akisi` — `auth_service.dart` `girisIptalEdildi`; `_runSocial` iptalde sessiz döner (nötr mesaj da yok: hata olmadı, düğmenin boşa dönmesi yeterli), Crashlytics'e yazmaz. Kodda ölçülen tuzak: google_sign_in_android 7.2.15 Credential Manager'ın `GetCredentialCancellationException`'ını `GoogleSignInExceptionCode.canceled`'a çeviriyor; B1'in "[16] Account reauth failed" hatası bu sınıfla gelebildiği için yalnız koda bakan süzgeç B1 mesajını yutardı — süzgeç önce reauth metnine bakıyor (`googleYenidenDogrulamaGerekli`). Apple `unknown` (1000) bastırılmıyor. Ortak düzeltme: Android'de Google iptali de sessiz. Ölçüldü (`test/giris_ios_test.dart`): Apple/Google iptali snack göstermiyor; Apple `unknown` hâlâ `authFailed`; iptal koduyla gelen [16] hatası `authReauthNeeded` gösteriyor. Süzgeç satırı söküldüğünde iki iptal testinin düştüğü de denendi.

**Android güvenliği** — Google iptali Android'de de sessizleşir; genel catch'teki "[16] reauth" dalı (B1) aynen kalır.

**Birleşme notu (2026-10-22, `8d6f67b`)** — Windows da iptali ayrı onarmıştı (`socialHataSonucu`); o yapı kaldı ama Mac'in ölçtüğü sıra uygulandı: reauth İPTALDEN ÖNCE (Credential Manager "[16]"yı iptal koduyla bildirebiliyor; tersi B1'i sessizce yutardı). `girisIptalEdildi` artık `isAuthCancelled` üzerine kurulu, iki kopya ayrışmasın diye.

### U50 — 426 `update_required` metni "Google Play'den güncelle" diyor
⏳ açık · DÜŞÜK · kod · A3 ortak kod · kaynak: `update-required-message-names-google-play`

**Kanıt** — `backend/core/messages.py:327-331` TR "…Google Play'den…", EN "…from Google Play."; `backend/core/app_gate.py:302` bu metni 426 gövdesinde döndürüyor.

**Etki** — Sunucu güncelleme dayattığında iOS kullanıcısı kısa süre Google Play'i anan bir hata görebilir. Uygulama içinde başka mobil platformu anmak 2.3.10 ile çelişir. Metin yalnız kapı etkinken göründüğü için red olası değil.

**Düzeltme** — Backend metni istemci ARB'si gibi mağaza-nötr (`docs/mac-devir.md` §5 "Mağaza metinleri nötr"): TR "Rytho'nun bu sürümü artık desteklenmiyor — uygulamayı mağazadan güncelle." EN "…update it from your app store." Eski metni doğrulayan test güncellenir.

### U51 — Admin panelindeki "iOS" kullanıcı filtresi hiç eşleşmiyor
⏳ açık · DÜŞÜK · kod · A3 ortak kod · kaynak: `admin-platform-filter-case-mismatch`

**Kanıt** — `web/rytho-admin/gorunumler/kullanicilar.js:313` filtre `deger: 'ios'`; uygulama `defaultTargetPlatform.name` ile `'iOS'` saklıyor (`lib/core/device_session.dart:47`).

**Etki** — iOS lansmanından sonra kullanıcı listesi, CSV dışa aktarımı ve platform filtresi sıfır iOS kullanıcısı döner; platform analitiği ve kohort görünümleri iOS'u eksik sayar; geri bildirim ile kullanıcı verisi platforma göre birleştirilemez.

**Düzeltme** — Asgari: `kullanicilar.js:313` → `{ deger: 'iOS', … }`. Daha sağlam, sunucu tarafı: `admin_service` gelen platformu Firestore eşitliğinden ve bellek içi karşılaştırmadan önce normalleştirir (`{'ios': 'iOS'}.get(p.lower(), p)`). Saklanan cihaz kayıtları ya da `X-Device-Other-Platform` küçültülmez — `device_conflict_screen.dart:90-93` "Ios" basardı. `geribildirim.js` değişmez.

### U52 — UI yazı tipleri çalışma anında Google'dan indiriliyor
⏳ açık (kısmen `eed33c7`) — işlevsel kusur kapandı, Düzeltme'nin lisans kaydı maddesi yapılmadı · DÜŞÜK · kod · A3 ortak kod · kaynak: `google-fonts-runtime-fetch` (eksik avcısı) *(Durum tarihçesi: 2026-10-23'e dek `⏳ açık`; 2026-10-23'te `✅ kapandı — eed33c7` yazıldı ve lisans kaydı "Kalan"a indirildi; 2026-10-24'te bu satıra döndü — "Nasıl güncellenir" kuralına göre "Kalan" yalnız A5, belge ya da isteğe bağlı iş içindir, oysa lisans kaydı Düzeltme'de zorunlu madde olarak yazılı.)*

**Kanıt** — `lib/theme/rytho_theme.dart:79, 85, 91, 99` `GoogleFonts.sora/manrope/jetBrainsMono`; `lib/`'de `GoogleFonts.config.allowRuntimeFetching = false` yok (yalnız `test/chart_wheel_test.dart:66`); pubspec'te paketlenmiş yazı tipi yok. `google_fonts` 6.3.3 `google_fonts_base.dart:110-112` yükleme future'ına hata işleyicisi bağlamıyor, `:206` indirme hatasında `rethrow` ediyor; `lib/main.dart:133-134` işlenmemiş async hatayı `fatal: true` kaydediyor.

**Etki** — Ağsız ilk açılışta (ya da fonts.gstatic.com engelliyse) tüm arayüz — paylaşım kartları dahil — marka yazı tipleri yerine SF Pro ile çizilir. Başarısız her yazı tipi varyantı işlenmemiş async hata olarak Crashlytics'e FATAL düşer, TextStyle başına yeniden denendiği için tekrar tekrar — sahibin TestFlight'ta izlediği çökme oranı şişer. Her yeni kurulum Google'ın yazı tipi CDN'ine bağlanıyor; gizlilik politikası bunu anmıyor. Android'de de aynı.

**Düzeltme** — Kullanılan Sora, Manrope ve JetBrains Mono ağırlıkları (hepsi OFL) google_fonts'un beklediği dosya adlarıyla `assets/google_fonts/`'a indirilir ve pubspec assets'e eklenir. `main()`'de `runApp`'ten önce `GoogleFonts.config.allowRuntimeFetching = false;`. OFL lisansları `LicenseRegistry.addLicense` ile kaydedilir. Paket ~1–2 MB büyür.

Kısmen kapandı: `eed33c7` (Windows, D1–D2 dalgası, "fontlar pakette") — kayıt birleşmeden sonra bayat kaldı, 2026-10-23 hazırlık turunda yeniden ölçüldü: `lib/main.dart:101` (`ba6108b`'de `:95`) `GoogleFonts.config.allowRuntimeFetching = false;` `runApp`'ten önce, gerekçesiyle (bayrak kapalıyken eksik bir ağırlık ağa düşmez, fırlatır — testte görünür); `pubspec.yaml:151-169` (gerekçe yorumu 151-161, sekiz `.ttf` girdisi 162-169; satır 150 yüz okumanın `.tflite` modeli — 2026-10-24'e dek burada yanlışlıkla "150-168" yazıyordu) Sora 600/700, Manrope 400/500/600/700, JetBrains Mono 400/700 `.ttf` dosyaları `assets/google_fonts/` altında, `google_fonts`'un aradığı `<Aile>-<Ağırlık>.ttf` adıyla, tek tek listelenmiş; bekçi `test/font_paketi_test.dart` her (aile, ağırlık) çiftini dosyaya bağlıyor ve bütçeyi (≤ 1 MB) tutuyor. Düzeltmenin iki ana parçası (paketleme, çalışma anı indirmesinin kapanması) yerinde: ağsız açılışta marka fontu çizilir ve indirme hatası FATAL üretemez.
Kaydı AÇIK tutan (lisans gösterimi; kusurun işlevine dokunmuyor ama Düzeltme'de zorunlu madde): Düzeltme'nin "OFL lisansları `LicenseRegistry.addLicense` ile kaydedilir" maddesi yapılmadı — `lib/`'de `LicenseRegistry` geçmiyor (ölçüldü 2026-10-23); tam lisans metinleri yalnız `docs/legal/fonts/` altında (`OFL-Sora.txt`, `OFL-Manrope.txt`, `OFL-JetBrainsMono.txt`, `OFL-NotoSansSymbols.txt`) ve pakete girmiyor. Paketteki sekiz `.ttf`'nin `name` tablosu ise lisans bildirimini (nameID 13: "This Font Software is licensed under the SIL Open Font License, Version 1.1…") ve lisans adresini (nameID 14) taşıyor (aynı gün, tablo okunarak ölçüldü). Bunun OFL'nin dağıtım şartına yetip yetmediği hukuki bir değerlendirme — burada yapılmadı; uygulamanın lisans sayfasında görünmesi için kayıt gerekir. Mağaza reddi değil.

**Android güvenliği** — Aynı dosyalar iki platformda aynı çizilir; Android yalnız indirmeyi bırakır. Birleştirmeden sonra Windows'ta golden ve widget testleri (zaten indirmeyi kapatıyorlar) koşulur.

### U53 — Apple silicon Mac (ve Vision Pro) erişilebilirliği varsayılan açık
⏳ açık · DÜŞÜK · hesap · A4 mağaza · kaynak: `app-attest-entitlement-and-mac-availability` (Mac kısmı)

**Kanıt** — ASC iPhone/iPad uygulamalarını varsayılan olarak Apple silicon Mac'lerde sunar; uygulamanın App Check'i App Attest'e dayanıyor ve zorlama açık.

**Etki** — Mac'te App Attest (ve kamera/ML Kit) kullanılamayabilir: kullanıcı uygulamayı kurup App Check'i hiç geçemeyebilir.

**Düzeltme** — ASC > Pricing and Availability: App Check orada doğrulanmadıkça v1 için "iPhone and iPad Apps on Apple Silicon Macs" işareti kaldırılır; sunuluyorsa Apple Vision Pro erişilebilirliği de kaldırılır.

**Ek (2026-10-23)** — Yol haritası boşluğu kapandı: adım `docs/mac-devir.md` §4 **C6**'da (bölge seçimiyle aynı ekranda). App Store Connect ölçülemedi; kayıt ⏳ açık kalır.

**Ek (2026-10-24)** — Etki'deki "kullanılamayabilir" fazla yumuşak. Apple'ın `DCAppAttestService.isSupported` belgesine göre Mac'te değer **false** — Apple silicon'da çalışan iOS ve iPadOS uygulamaları dahil; AppCheckCore desteklenmeyen durumda jeton vermiyor (`GACAppAttestProvider.m`). Zorlama açıkken Mac kullanıcısı giriş yapamaz; Mac erişimi açık kalacaksa kapatmak (ya da `isSupported`'a bakan özel bir DeviceCheck yedeği) "önerilir" değil gerekli. Eklentinin yedekli varyantı yalnız iOS sürümüne bakıyor, Mac'i kurtarmaz. Açık nokta: WWDC26 macOS 27'de App Attest desteğinden söz ediyor; Mac'te çalışan iOS uygulaması için belgelenmedi — belirsizlik. Vision Pro'da "Designed for iPad" için `isSupported` belgelenmedi. Karar sahibin (öneri kapat): `docs/mac-devir.md` §4 C6.

### U54 — iOS'ta FCM `getToken`, APNs jetonundan önce çağrılınca düşüyor
⏳ açık (kısmen) · DÜŞÜK · kod · A5 test · kaynak: `fcm-gettoken-before-apns` (doğrulayıcı: **BELİRSİZ**)

**Kanıt** — `lib/core/notifications.dart:102` `syncNotificationContext`, `:114` `getToken()`, `:122-124` hata yalnız `debugPrint`. Geç gelen APNs jetonu `onTokenRefresh` + `ensureAPNSTokenSetting` ile yine yazılıyor (bkz. Doğrulanmış olanlar) — belirsizlik buradan.

**Etki** — İlk kurulum/girişte `fcmToken`/`fcmTokenAt` sık sık `users/{uid}`'ye yazılmayabilir; sabah bildirimi ve arkadaş tepkisi push'ları `onTokenRefresh` tetiklenene ya da sonraki açılışa dek o cihaza ulaşmaz — sessizce.

**Düzeltme** — Önce ölçülür: ilk TestFlight kurulumundan sonra Firestore'da `fcmToken`'a bakılır. Gerekirse yalnız sağlamlaştırma: iOS'ta `getAPNSToken()` null ise `getToken` sessizce atlanır, `onTokenRefresh`'e güvenilir. Yoklama gerekmez.

Kısmen: `[iOS] U11 U14 U24 U30 U54: bildirim izni, on plan push, ses oturumu, App Check izi` — sağlamlaştırma yapıldı: `notifications.dart` `cihazFcmJetonu`; iOS'ta `getAPNSToken()` null ise `getToken` hiç çağrılmıyor, `null` dönülüyor ve `syncNotificationContext` sessizce geçiyor; Android'de APNs sorulmuyor. Kaynakta ölçülen: firebase_messaging_platform_interface 4.9.2 `_APNSTokenCheck` bu durumda `getToken`'da `apns-token-not-set` fırlatıyordu — olağan bir ilk kurulum anı hata yolundan geçiyordu. Ölçüldü (`test/bildirim_ios_test.dart`): iOS'ta APNs yokken FCM jetonu istenmiyor; APNs varken jeton dönüyor; Android'de APNs hiç sorulmuyor; kaynak bekçisi senkron yolunun bu kapıdan geçtiğini ve doğrudan `getToken()` çağrısı kalmadığını sabitliyor.
Kalan: TestFlight'ta fcmToken yazıldığı ölçülecek.

### U55 — Depo Xcode 27 ile derlenmiyor; Apple asgari SDK'yı her bahar yükseltiyor
⏳ açık · DÜŞÜK · kod · Sonra · kaynak: `xcode27-sdk-floor-liability` (eksik avcısı)

**Kanıt** — `docs/mac-devir.md:279-288`: Xcode 27 depoyu derleyemiyor (purchases-ios 5.67.1 Swift 6.4'te kırık; Flutter 3.44.7'nin simülatör `lipo -verify_arch` adımı kırık); `purchases_flutter` 10.x Android'i etkilediği için seçilmedi. Apple: 28 Nisan 2026'dan beri yüklemeler Xcode 26+ ile derlenmeli (önceki tabanlar Nisan 2024'te Xcode 15, Nisan 2025'te Xcode 16).

**Etki** — Bugün hiçbir şey engellenmiyor. Apple tabanı Xcode 27'ye çektiğinde — büyük olasılıkla Nisan 2027 civarı — `purchases_flutter` majör yükseltmesi (Android'in de aldığı ortak Dart API değişikliği) ve lipo sorununu aşan bir Flutter yükseltmesi olmadan acil düzeltmeler dahil hiçbir iOS güncellemesi çıkamaz. İkisi iki makine arasında koordine edilmeli.

**Düzeltme** — `docs/mac-devir.md` ve production-checklist'e tarihli madde: "Xcode 27 hazırlığı, 2027 1. çeyrek". Swift 6.4'ü düzelten bir `purchases_flutter` 9.x yaması izlenir; yoksa 10.x geçişi + Flutter yükseltmesi Apple duyurusundan çok önce, iki platformda doğrulanan ortak bir dalda planlanır. Her Flutter stable sürümünden sonra Xcode 27 ile yeniden denenir.

**Ek (ölçüldü 2026-10-23)** — Yükleme tabanı bugün karşılanıyor: `xcode-select -p` → `/Applications/Xcode-26.app`, Xcode 26.6 (17F113), SDK iPhoneOS 26.5. Aynı ailede ikinci bir gelecek kırılımı ölçüldü: `ba6108b`'deki Release derlemesi dört eklenti için "This will become an error in a future version of Flutter" uyarısı veriyor — `flutter_contacts`, `google_mlkit_commons`, `google_mlkit_face_detection`, `tflite_flutter` Swift Package Manager desteklemiyor. Depo bilerek CocoaPods'ta (U25, U56); bugün engel değil, ama Flutter yükseltmesinden önce bu dört eklentinin SPM durumu kontrol edilir. Ayrıca iOS 27 çalışma ortamında uygulama o gün hiç koşmamıştı (U21 ek). *(→ 2026-10-24: iOS 27.0 iPhone 18 Pro ve iPad (A16) simülatörlerine kuruldu ve açıldı; gezinti sonucu kayıtlı değil.)*

**Android güvenliği** — Şimdilik yalnız planlama; nihai `purchases_flutter` 10.x yükseltmesi birleşmeden önce Android'de (Play Billing) test edilir.

---

## Doğrulanmış olanlar

Denetçilerin bakıp **sorun bulmadığı** yerler — kapsamın kanıtı. Kopyalar birleştirildi. Liste taban (`e4789d4`) durumunu anlatır; SwiftPM'e dair maddeler `4ba7d9d`'deki CocoaPods geçişinden öncedir.

**Kimlik ve giriş**
- Apple girişi yalnız iOS'ta (`auth_service.dart:28-29`, test `auth_service_test.dart:53-66`), Google'ın üstünde ve aynı 52 pt yükseklikte (4.8). Nonce akışı doğru: `Random.secure()` ham nonce Firebase'e, SHA-256'sı Apple'a. Apple adı ilk girişte yakalanıyor, `displayName` boşsa yazılıyor; kimse ad/e-postayı yeniden sormuyor.
- `com.apple.developer.applesignin` iki entitlements dosyasında, `CODE_SIGN_ENTITLEMENTS` üç yapılandırmada; arşiv Release → `RunnerRelease.entitlements` (production). Google Sign-In v7: `GIDClientID` ve `REVERSED_CLIENT_ID` şeması GoogleService-Info ile eşleşiyor, `serverClientId` yalnız web istemcisi; google_sign_in_ios, firebase_auth ve sign_in_with_apple UIScene altında çalışıyor, hiçbiri `AppDelegate.window`'a bağlı değil.
- Telefon doğrulama iOS'ta `fatalError`'a düşmez: REVERSED_CLIENT_ID şeması kayıtlı ve SDK onu geri dönüş şeması olarak kullanıyor (sessiz push doğrulaması APNs anahtarına bağlı, U08). App Check: `activate()` `runApp`'ten önce bekleniyor; release'te App Attest, debug'da debug sağlayıcı; 15.5 tabanı App Attest'in iOS 14 şartını aşıyor.
- Backend kimlik doğrulaması sağlayıcıdan ve platformdan bağımsız (`core/auth.py` yalnız `verify_id_token`); Cloud Run API App Check doğrulamıyor, yani App Attest kaydından önce de iOS'ta çalışır; `firestore.rules` sağlayıcıya ya da `email_verified`'a bakmıyor. E-posta/şifre akışları nötr; `linkPassword` Hide My Email kullanıcısına e-postayı düzenletiyor.
- Cihaz kimliği SharedPreferences'ta rastgele 128 bit — donanım ya da reklam kimliği değil, ATT gerekmez. `X-Device-Platform` 'iOS' gönderiyor, backend olduğu gibi saklıyor; çakışma ekranı devralma ve çıkış sunuyor (demo hesap çıkmaza girmez).
- Hesap silme uygulama içinde bulunabilir (Profil → Hesap → Hesabı sil), yazılı onaylı, mağaza aboneliğinin ayrıca iptal edilmesi gerektiğini mağaza-nötr dille söylüyor; backend veriyi, Storage'ı, kullanıcı adını ve Auth kullanıcısını Admin SDK ile gerçekten siliyor (yakın giriş şartı yok).

**Satın alma**
- RevenueCat iOS'ta platform anahtarını seçiyor (`subscription.dart:113-115`). Ürün kimlikleri istemci, backend ve belgelerde aynı (`rytho_tokens_small/medium/large`, `rytho_plus_monthly`); `planDisplayName` iki platformun kimlik biçimini tanıyor; istemcide Play'e özgü kimlik yok.
- Consumable kredisi App Store'da çalışır: `NON_RENEWING_PURCHASE` ürün kimliğiyle yönleniyor, `event.id` anahtarlı idempotent defter; bilinmeyen ürün kimliği ERROR + `adminAudit` olarak görünür; paket iadesi aboneliğe dokunmuyor.
- Sandbox olayları kabul ediliyor (TestFlight ve App Review için şart); webhook sırrı yoksa 503 ile kapalı kalıyor, karşılaştırma sabit zamanlı. TRANSFER (farklı Apple ID ile geri yükleme) aboneliği ve cüzdanı taşıyor; RevenueCat kimliği satın alma ve restore'dan önce Firebase uid'ye bağlanıyor; sunucu tek doğruluk kaynağı, 'RhytoAI Pro' yetki adı panelle aynı.
- Paywall 3.1.2 açıklaması tam: başlık, plan, mağaza `priceString`, otomatik yenileme ve iptal, Restore (paywall ve abonelik ekranında), Koşullar + Gizlilik bağlantıları, kapatma düğmesi. Mağaza denemesi olmadığı için sahte "X gün ücretsiz" iddiası yok; `purchaseCancelledError` sessiz.
- 3.1.1: fiyatların hepsi mağazadan; satın alınan kredi hiç yanmaz ve kullanıcıya söyleniyor; kredi mağazası ücretsiz kullanıcıyı satın almadan önce uyarıyor; ortak kod kullanım arayüzü kaldırıldı, harici ödeme bağlantısı yok; sunucu tarafı 3 günlük deneme IAP atlatması değil.
- Android'e özgü yükseltme/proration kodu yok; satın alma sonrası sunucu beklemesi 15 sn bütçeli. iOS abonelik yönetimi bağlantısı doğru (`apps.apple.com/account/subscriptions`); zorunlu güncelleme iOS dalı `APPSTORE_APP_ID` boşken düğmeyi gizliyor; yalnız `launchUrl` kullanıldığı için `LSApplicationQueriesSchemes` gerekmez.
- Uygulama içi hukuk metinleri mağaza-nötr; barındırılan Koşullar ve Gizlilik URL'leri var; web hukuk sayfaları App Store faturalamasını ve Apple ile Giriş'i anıyor; admin gelir görünümü `APP_STORE`'u eşliyor.

**Push ve derin bağlantılar**
- Tek FCM yükü üreticisi `push_service.py`: her mesajda `notification` bloğu + `aps.sound` — arka planda/kapalıyken iOS'ta görünür; yalnız-veri mesajı yok; Android'e özgü alanları APNs yok sayar. Veri yükleri string, ayrılmış anahtar yok; rota çözümü platformdan bağımsız.
- Ölü jeton budaması `THIRD_PARTY_AUTH_ERROR`'ı içermiyor — APNs anahtarı eksikken iOS jetonları toplu silinmez. Pazarlama push'u yok (4.5.4); tür başına anahtarlar ve sessiz saatler var.
- APNs ortamı tutarlı (eklenti DEBUG'da Sandbox etiketliyor; Debug → development, Release → production). `UIBackgroundModes` yalnız `remote-notification`; swizzling açık; `IS_GCM_ENABLED=true`; tabanda swizzler tek kopyaydı. *(Düzeltme 2026-10-24, pod kaynağı okunarak: gerekçe eksikti. Swizzling açıkken ortamı ilk koyan FIRMessaging vekili ve türü gömülü provizyon profilinden okuyor (`FIRMessagingRemoteNotificationsProxy.m`, `GULAppDelegateSwizzler.m`); eklentinin DEBUG etiketli çağrısı aynı jeton için yok sayılıyor (`FIRMessagingTokenManager.m`), etiket yalnız APNs jetonu FIRMessaging hazır olmadan gelirse etkili. Satır Profile'ı da saymıyordu: Profile development yetkisiyle ama DEBUG tanımı olmadan derlenen pod'larla çıkıyor — o kenar durumda eklenti sandbox jetonunu production diye etiketler; push'u Profile'da ölçmek bu yüzden güvenilir değil (koddan, ölçülmedi), push Debug'da ölçülür.)*
- firebase_messaging 16.4.3 ve app_links 7.2.1 UIScene destekli; `getInitialMessage` ve `onMessageOpenedApp` soğuk/ılık bağlı; ilk bağlantının çift teslimi idempotent. Geç gelen APNs jetonu yine `fcmToken`'a ulaşıyor (`onTokenRefresh` + `ensureAPNSTokenSetting`); çıkışta jeton temizliği ve saat dilimi (IANA) platformdan bağımsız.
- AASA canlıda iki ana makinede 200, `application/json`, yönlendirmesiz; Apple CDN ikisini de çekmiş; tek sorun bilinen `TEAMID`. Yol eşliği Android intent-filter'larıyla aynı (`/i/`); `test_ios_config.py` yalnız `.ai.rytho"` sonekini denetliyor, TEAMID değişimi testi kırmaz.
- Özel URL şeması yalnız Google REVERSED_CLIENT_ID; Android'de özel şema yok, taşınacak şey yok. Davet paylaşım metninde Play sözü yok. "Bildirimler kapalı" bandı iOS 18+ Ayarlar düzenine uyuyor.

**Yerel yapılandırma**
- Info.plist'te rehber, kamera ve fotoğraf kütüphanesi anahtarları var; `ImageSource.camera` ya da video yok. LAContext yalnız GoogleSignIn'de (biyometrik istem yok) → `NSFaceIDUsageDescription` gerekmez; CMMotionManager izin istemez. Konum, ses kaydı, Face ID, hareket ya da arka plan getirme API'si kullanılmıyor.
- `ITSAppUsesNonExemptEncryption=false` doğru (yalnız işletim sistemi TLS'i; SHA-256 özetleme muaf). Sürüm bağlaması pubspec'le tutuyor (derlenen Info.plist 1.16.0 (45)); `CFBundleDisplayName` 'Rytho'.
- AppIcon tam, 21 PNG'nin hiçbirinde alfa yok (1024 pazarlama ikonu dahil); başlatma ekranı koyu `#0B0710`, iki platformda beyaz parlama yok. SwiftPM Firebase framework'lerinin `MinimumOSVersion=100.0` değeri Firebase'in bilinçli düzeltmesi (firebase-ios-sdk #12476).
- Flutter.framework ve eklentiler kendi gizlilik manifestlerini taşıyor; boşluk yalnız TFLite/ML Kit ve uygulamanın kendisiydi (U12). `STRIP_STYLE = non-global` üç yapılandırmada (tflite_flutter arşiv şartı); armv7 cihaz derlemesinden hariç (google_mlkit şartı).
- Simülatör ML Kit hilesi `[sdk=iphonesimulator*]` kapsamlı, `MLKitSimulatorStubs.m` `#if TARGET_OS_SIMULATOR` içinde — cihaz ve arşiv etkilenmez. GoogleService-Info.plist `BUNDLE_ID=ai.rytho`, `PROJECT_ID=rhytoai`, Resources fazında.
- UIScene yolu motorca destekleniyor; `AppDelegate.window`'u okuyan tek eklenti flutter_contacts (yamalı); share_plus `connectedScenes`, image_picker kendi penceresini kullanıyor. Release/Profile'da `dwarf-with-dsym` ve `ENABLE_USER_SCRIPT_SANDBOXING = NO` (U26 için uygun).
- Xcode 26.6 bugünkü yükleme tabanını karşılıyor; 15.5 dağıtım hedefi yeterli. `build/ios/iphoneos`'taki 275 MB paket DEBUG derlemesi; gerçek varlıklar (tflite 16 MB, ML Kit kaynakları 9.6 MB) boyut sınırını zorlamıyor — release boyutu `flutter build ipa --analyze-size` ile bir kez ölçülmeli.

**Dart platform davranışı**
- Kamera görüntü biçimi platforma doğru (Android nv21, iOS bgra8888); segmentasyon BGRA adımını algılıyor; TFLite yalnız CPU, Android'e özgü delege yok.
- Galeri yüz yolu nötr (EXIF iki platformda uygulanıyor); image_picker iOS 14+'ta PHPicker (izin istemi yok), HEIC yeniden kodlanıyor, seçilen kopya siliniyor. Avatar yükleme de iOS'a uygun (JPEG → PNG, `storage.rules` ile uyumlu).
- Rehber: iOS 18 sınırlı erişim "verildi" sayılıyor; `normalizeE164` iOS'un U+00A0 boşluklarını temizliyor. Geri gezinme: iOS'ta `CupertinoPageTransitionsBuilder` (kaydırarak geri), itilen her ekranda AppBar ya da kapatma; `PopScope(canPop:false)` ekranları kök kapı ekranları.
- Güvenli alanlar doğru; metin ölçeği yalnız üstten 1.3'te kırpılıyor; Reduce Motion animasyonları kapatıyor; koyu tema koyu durum çubuğu ve koyu klavye veriyor; SMS kodu otomatik doldurma (`oneTimeCode`), giriş alanları AutofillGroup içinde.
- Dosya depolama iOS kurallarına uygun (yalnız `getTemporaryDirectory`); programatik pano okuma, uygulama içi değerlendirme istemi ve arb'lerde 'beta'/'yakında' yok. Firebase Dynamic Links ya da ActionCodeSettings kullanılmıyor; Auth reCAPTCHA Enterprise kapalı → iOS reCAPTCHA anahtarı gerekmez. Android'de taşınacak özel native kod yok (MainActivity çıplak FlutterActivity).

**Backend ve App Review uyumu**
- API taban adresi HTTPS ana makine adı → ATS istisnası yok, IPv6/NAT64'te çalışır (2.5.5). Hiçbir uç bilinmeyen ya da iOS platformunu reddetmiyor; `X-Device-Platform` isteğe bağlı; iOS build numarası `X-App-Build`'e Android gibi akıyor (canlı eşik bugün 0). Play'e özgü satın alma doğrulaması yok; RevenueCat webhook'u tek yazma yolu.
- Koşullar ve gizlilik: onboarding'de tüm giriş yöntemleri için açık onay kutusu + 13+ beyanı; e-posta kaydında yaş kutusu; gizlilik politikası uygulama içinden erişilebilir; ASC URL'leri için web sürümleri var.
- 1.4.1: "tıbbi, hukuki ya da finansal tavsiye değildir" uyarıları; deterministik kriz ve yasak konu kapısı LLM'den önce. 1.2: yayımlanmış iletişim bilgisi (`kLegalContact`) uygulama içinde ve web altbilgisinde; kullanıcılar birbirine serbest metin gönderemiyor (nudge'lar kurallarla kapalı küme); `reports` istemci için yalnız-oluştur.
- Rehber (5.1.1 / 5.1.2(iv)): varsayılan kapalı, OS izninden önce açıklamalı opt-in; yalnız SHA-256 özetler gidiyor, isimler cihazda; sunucu opt-in istiyor ve özetleri saklamıyor; rehbere toplu mesaj yok.
- Yüz okuma: görüntü baytı gönderilmiyor, yalnız oranlar; ayrı, geri alınabilir, sunucuda zorlanan biyometrik onay. 5.1.2 izleme: ATT gerektiren SDK uygulama kodunda kullanılmıyor; RevenueCat yalnız uid; Crashlytics'e kullanıcı kimliği yok; Analytics olaylarında kişisel veri yok. Bildirim izni zorunlu değil; ret akışı engellemiyor.

---

## Nasıl güncellenir

- **Durum satırı:** her kaydın başlığının altındaki `⏳ açık`, kusur depoda giderilip Mac'te ölçülebildiği kadar doğrulanınca `✅ kapandı — <commit>` olur; Düzeltme'nin sonuna commit'in ne yaptığı ve neyin ölçüldüğü yazılır. Geriye yalnız cihaz doğrulaması (A5), belge ya da isteğe bağlı iş kaldıysa **Kalan:** diye anılır; düzeltmenin işlevsel bir parçası eksikse kayıt `⏳ açık (kısmen <commit>)` kalır. Özet tablodaki başlığın önündeki işaret de aynı anda değiştirilir.
- **Kayıt silinmez.** Kod gerekmeden kapanan kayıt (karar, konsol işi, ölçümle geçersiz çıkan bulgu) `✅ kapandı — <tarih>, <gerekçe>` ile kapanır.
- **Kanıt satırları tabana (`e4789d4`) göredir ve değiştirilmez;** yeni kanıt gerekirse commit'iyle birlikte ayrı satır olarak eklenir.
- **Commit mesajında kimlik:** ör. `[iOS] U14: ön plan push'u iOS'ta FCM gösterir` — `git log --grep U14` kaydın geçmişini verir.
- **Yeni bulgu** tablonun sonuna sıradaki numarayla (U56…) eklenir; mevcut numaralar asla yeniden dağıtılmaz. (2026-10-23: U56 kullanıldı, sıradaki **U57**. Önce mevcut bir kayda oturup oturmadığına bakılır — 2026-10-23 turunun yeni eksiklerinin çoğu mevcut kayıtlara "Ek" olarak girdi; istisnalar belgenin başındaki hazırlık turu satırında. 2026-10-24'e dek burada "hepsi" yazıyordu.)
- **İki makine:** A3 kayıtları Mac'te yazılır; Windows oturumu Android paketini çıkarmadan önce ilgili kayıtların **Android güvenliği** satırını okur. A1/A4 sahibin işidir; yapıldığında sahibin sözü ya da ölçüm kanıt olarak yazılır — "ölçülmeyen söylenmez".

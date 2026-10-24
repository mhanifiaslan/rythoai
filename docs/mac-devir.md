# Mac'e devir ve iOS başlangıcı

Bu belge, depoyu bir Mac'e taşıyıp iOS sürecini başlatmak içindir. Her
madde ya ölçülerek bulundu ya da bir kez zarar verdi. Windows makinesinde
**her şey çalışıyor**; buradaki listede yazanlar Mac'te *ek olarak* gereken
şeyler.

Ölçüm tarihi: **2026-09-26**, güncelleme **2026-10-22** (aşağıdaki
"Bugünkü durum" kutusu ve 4.10) ve **2026-10-23** (Mac'te hazırlık
denetimi: dört ölçüm + eksik avcısı, HEAD `ba6108b`; §4 sahibin üç
aşamasına göre yeniden sıralandı, "Mac durumu" kutusu düzeltildi) ve
**2026-10-24** (o belgenin çürütme turu: deploy sırası CLAUDE.md §7'ye
bağlandı, App Check belirtisi koda göre düzeltildi, ölçülemeyen konsol
durumları "ölçülemedi" diye işaretlendi; U05'in kod yarısı `09bbe23`) ve
yine **2026-10-24** (konsol araştırması: A2/A4/A5/B1/B2/C6/C7 yolları
Apple ve Firebase belgelerine göre, 4.5'in APNs gerekçesi, 4.10'un test
kodu ve yayın günü listesi; konsol durumları yine ölçülmedi).
Dal: `yuz-okuma-cihaz-usti-olcum`.

> **Bugünkü durum (2026-10-22, Windows'tan ölçüldü):**
> - Android **1.20.0+53** derlendi (AAB, 6 kapı OK). Play'de **açık test
>   (yalnız Türkiye)** incelemede; **üretim erişimi verildi** (2026-10-17),
>   üretim kanalı henüz açılmadı. Sürüm kodları 48/50/52 YANMIŞ; sıradaki
>   Android kodu **54**. iOS'un `CFBundleVersion`'ı Android'den bağımsızdır
>   ama `pubspec.yaml` `version` ikisini birden besler — iOS'ta numarayı
>   yükseltirken Android'in yanmış kodlarına dikkat.
> - Backend Cloud Run rev **00112-dtj**; istatistik özeti saatlik
>   (`rytho-stats`), Çevrem/geri kazanım bildirim işleri kurulu.
>   ⚠️ (Mac'ten kimliksiz ölçüldü 2026-10-23) Canlı `/openapi.json`'daki
>   89 yolda `POST /api/v1/account/ai-consent` YOK (404; var olan
>   `/account/consent` → 401). Yani canlı kod Mac birleşmesinden
>   (`8d6f67b`) önceki Windows hattı — U17'nin sunucu kapıları da canlıda
>   değil. Bu bir çıkarım: revizyonun commit'i `gcloud`suz ölçülemedi.
> - Gemini faturası **ön ödemeli**: bakiye sıfırlanırsa tüm AI anında durur
>   (CLAUDE.md "CANLI KESİNTİ 2").
> - Ortak panosu `rytho.app/affiliate/` (eski `/ortak/` 301), varsayılan dil EN.
> - iOS'ta yapılacak ilk ürün işi: **ortak (affiliate) bağlantısının iOS'ta
>   da sayılması** — bkz. **4.10**.

> **Mac durumu (2026-10-22, Mac'ten ölçüldü; 2026-10-23'te yeniden ölçülüp
> düzeltildi — düzeltilen satırlar yerinde, eskisi silinmeden):**
> - **Hazırlık hükmü (2026-10-23):** gerçek iPhone'da Debug testi, iç
>   TestFlight ve App Store incelemesi — üçü de bugün **hazır değil**;
>   kod tarafı büyük ölçüde hazır, kalanların çoğu sahibin konsol işi ve
>   üç deploy (kurallar + backend birlikte, hosting). Kod işleri de var:
>   U05'in kalanı (kod yarısı `09bbe23`; §4 B7), §4 C13 ve U17
>   şikâyet görünümü, U18 notları, U37 Koşullar maddesi. Sıralı adımlar §4
>   (Aşama A/B/C).
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
>   → **"İmza sertifikası 0" BAYAT — ölçüldü 2026-10-23:** `security
>   find-identity -v -p codesigning` → **1** geçerli kimlik, `Apple
>   Development: Mehmet Hanifi Aslan` (sertifika OU = `292WJ9TP74`,
>   geçerlilik 2026-10-22 07:18 GMT → 2027-10-22). "0" notu `63cccf4`'te
>   (2026-10-22 11:26 +0300) yazıldı; sertifikanın `notBefore`'u 10:18
>   +0300. Ölçüm büyük olasılıkla sertifikadan önce alındı, ama ölçüm anı
>   kayıtlı olmadığı için kesin değil (aracı WWDR sertifikası eksikken de
>   `find-identity` "0 valid identities" döner — dışlanmadı). Xcode'da
>   **ücretli takım hesabı ekli** (`IDEProvisioningTeamByIdentifier`:
>   `292WJ9TP74`, `teamType=Individual`, `isFreeProvisioningTeam=0`). Bu
>   Mac'te hâlâ **0** (aynı gün ölçüldü): Apple Distribution sertifikası,
>   yerel provizyon profili (iki profil dizini de yok), bağlı cihaz
>   (`xcrun devicectl list devices` yalnız simülatör — bu komut portaldaki
>   cihaz kaydını göstermez), `~/Library/Developer/Xcode/Archives`.
>   Takımda kayıtlı cihaz ve App Store Connect kaydı **ölçülemedi** (portal
>   ve hesap girişi yok). Araçlar aynı: `firebase`, `gcloud`, `pwsh` yok.
>   *(Düzeltme 2026-10-24: bu satır "bağlı ya da kayıtlı cihaz 0" diyordu
>   ve "0" ölçümünün sertifikadan önce alındığını kesin bilgi gibi
>   yazıyordu.)*
> - **İmzasız Release derlemesi geçti** (ölçüldü 2026-10-23, `ba6108b`):
>   `flutter build ios --release --no-codesign
>   --dart-define-from-file=dart_defines.local.json` → çıkış 0, Runner.app
>   139,8 MB, `ai.rytho` **1.20.0 (53)**, yalnız arm64, simülatör taslağı
>   (`SIMULATORDE_YOK`, `MLKitSimulatorStub`) pakette 0, ML Kit + TFLite +
>   16 MB model pakette, `flutter analyze` temiz. ⚠️ Aynı derleme `test_`
>   önekli RevenueCat anahtarını pakete gömdü ve hiçbir yerde durmadı
>   (Aşama B). → U05 yayın kapısı `infra/build-ipa.sh` (`09bbe23`) bu
>   paketi durduruyor: çürütme turunda aynı artefakta `--yalniz-denetle`
>   koşuldu, `paket-test-anahtari-yok` ve `paket-derleme-numarasi` (53)
>   KALDI, çıkış 1 (ölçüldü 2026-10-23, U05'in çürütme turu).
>   ⚠️ Yan etki (ölçüldü 2026-10-23, `ba6108b`): Crashlytics dSYM fazı
>   o gün Debug dışındaki HER derlemede koşuyordu — bu imzasız ölçüm
>   derlemesinde de upload-symbols koştu ("Validation succeeded…";
>   sembolün rhytoai'ye ulaştığı ölçülemedi; U26). → `09bbe23`'ten beri
>   faz `CODE_SIGNING_ALLOWED=NO` iken (imzasız derleme) atlanıyor;
>   bekçi `backend/tests/test_ios_config.py`.
> - 4.10 kodu hazır (`31ee208`): **deploy edilmedi, cihazda ölçülmedi.**
> - ⚠️ **Hosting deploy'u BEKLET** (hangi makineden olursa olsun). Birleşmiş
>   `web/legal/` gizlilik metni yapay zeka onayının kurulumun ilk adımındaki
>   ayrı ve zorunlu kutuyla alındığını söylüyor (sahip kararı 2026-10-22/23;
>   U06'nın onay sayfası kalktı, bkz. CLAUDE.md §7). Canlıdaki Android
>   1.20.0+53'te o kutu YOK — kutulu ilk paket (Android 54 ya da iOS)
>   yayınlanmadan deploy edilirse politika canlı uygulama için yanlış beyan olur. Canlıda
>   ölçülen (2026-10-22): AASA hâlâ `TEAMID` + yalnız `/i/*`, gizlilik
>   sayfası 17 Ekim. **Yeniden ölçüldü 2026-10-23 — aynı**, üstüne: Apple'ın
>   AASA önbelleği (`app-site-association.cdn-apple.com/a/v1/rytho.app`,
>   `www.rytho.app`, `rhytoai.web.app`) de aynı bayat gövdeyi veriyor
>   (`X-Cache: hit-stale`); canlı hosting = `e8cc253` (2026-10-19, `last-modified`
>   + beş dosyanın o ağaçla bayt bayt eşliği). Kilidin seçenekleri §4
>   "Deploy bağımlılıkları ve hosting kilidi".

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
(Düzeltme 2026-10-23: doğru atıf **4.7** ve §4 Aşama B6 — "6.7" diye bir
madde yok. Ölçüldü 2026-10-23: dosyada yalnız üç anahtar var —
`REVENUECAT_ANDROID_KEY` `goog_`, `REVENUECAT_IOS_KEY` `test_`,
`RYTHO_PLUS_ENTITLEMENT`; `APPSTORE_APP_ID` hiç yok, bkz. 4.9. 2026-10-24:
dördüncü anahtar `APP_CHECK_DEBUG_TOKEN` eklendi — Firebase'de kayıtlı
sabit Debug jetonu, sırdır; dosya taşınırken o da taşınır, örnekten
yeniden kurulmaz, bkz. §4 A6. `APPSTORE_APP_ID` hâlâ yok.)

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

**2026-10-23'ten beri sıra üç aşamadır** — sahibin sorusu buydu:
**A)** gerçek iPhone'da debug testi, **B)** iç TestFlight, **C)** App Store
incelemesi. Her adım tam konsol yolunu, neyi açtığını ve yapılmazsa ne
olduğunu söyler. "Ölçüldü" yazmayan bir konsol durumu **ölçülemedi**
demektir: bu Mac'te hesap girişi yapılmadı, `firebase`/`gcloud`/`pwsh` yok.
Kanıtın kaynağı 2026-10-23 hazırlık denetimi (dört ölçüm + eksik avcısı,
HEAD `ba6108b`) ve depo; kayıt kimlikleri (U…) `docs/ios-uyum-denetimi.md`.

Eski **4.1–4.10 aşağıda ayrıntı ve tarihçe olarak duruyor**; aşama
adımları onlara işaret eder. Numaraları değiştirilmez: başka belgeler ve
bekçilerin gerekçeleri onları adıyla anıyor (ör. `test_ios_config.py`,
`test_web_seo.py` → "mac-devir 4.10"; uyum kaydı → "§4.7").

### Bugünkü hüküm (ölçüldü 2026-10-23; 2026-10-24'te düzeltildi)

*(Düzeltme 2026-10-24: B satırı "App Store Connect kaydı yok … kayıtlı
cihaz yok" diyordu — ikisi de ölçülemedi; backend deploy'u da B'nin engeli
sayılıyordu, oysa aşağıdaki Öneri A + C onu beklemiyor. `test_` anahtarının
çökmesi U05 kod ağıyla değişti.)*

| Aşama | Hazır mı | Kalan engel |
|---|---|---|
| **A** — cihazda Debug | **Hayır** — kod tarafı büyük ölçüde hazır | iPhone bağlı değil, provizyon profili 0; üç konsol adımı (App ID yetenekleri, Firebase'de Apple sağlayıcısı, APNs). App Check debug jetonu sabit ve Firebase'de kayıtlı (A6; simülatörde ölçüldü, cihazda ölçülmedi). Universal Link canlı AASA bayat olduğu için ölçülemez |
| **B** — iç TestFlight | **Hayır** | Gerçek `appl_` anahtarı yok (bugünkü `test_`: U05 kod ağıyla Release açılışta çökmez ama satın alma kapalı çıkar, `infra/build-ipa.sh` paketi durdurur); U05'in kalanı (ilk imzalı IPA, derleme numarası kararı); App Store Connect kaydı ölçülemedi (yerelde `APPSTORE_APP_ID` yok); App Attest kaydı ölçülemedi; dağıtım sertifikası bu Mac'te yok; takımda kayıtlı cihaz ölçülemedi. **Engel değil, önerilir:** kurallar + backend deploy'u ("Deploy bağımlılıkları" 1) — yapılmazsa onay kaydı satırı "bekliyor" kalır |
| **C** — App Store incelemesi | **Hayır** | IAP + sözleşmeler, inceleme notları, gizlilik etiketi, yaş derecesi, 6,9" ekran görüntüleri, EULA kararı; canlı gizlilik metni eski (hosting kilidi); kurallar + backend deploy'u (engellemenin sunucu kapıları canlıda değil — çıkarım; canlı kurallar ölçülemedi); iOS 27 ve iPad uyumluluk kipinde gezinti sonucu kayıtlı değil (iki simülatöre kuruldu ve açıldı, C11) |

### Aşama A — gerçek iPhone'da debug testi (`flutter run`, Debug kip)

Kod tarafı ölçüldü: imzasız Release derlemesi geçti (üst kutu),
`backend/tests/test_ios_config.py` 13/13 (HEAD, 2026-10-24; `ba6108b`'de 7 — `09bbe23` Crashlytics fazı bekçilerini ekledi), imza ayarları üç yapılandırmada
`DEVELOPMENT_TEAM = 292WJ9TP74` + `Automatic` + `ai.rytho`, dört yetki iki
entitlements dosyasında ve iki dosya yalnız `aps-environment`'ta ayrışıyor.
Eksik olan cihaz ve konsol.

**A1 — iPhone'u bağla · SEN**
- Kablo → telefonda "Bu bilgisayara güven" → Xcode → Window → Devices and
  Simulators'ta telefonun görünmesini bekle → (iOS 16+) Ayarlar →
  Gizlilik ve Güvenlik → **Geliştirici Modu** → aç → telefon yeniden
  başlar → açılışta "Aç" + parola. Menü genelde cihaz Xcode'a bir kez
  bağlanıp görüldükten sonra belirir; iOS 15.5–15.x'te bu menü yok,
  gerekmez. iOS en az 15.5 (ML Kit tabanı). (Apple'ın davranışı, burada
  ölçülmedi — cihaz yok.)
- Yapılmazsa: cihaza hiçbir şey kurulamaz. Bugün `xcrun devicectl list
  devices` yalnız üç simülatör gösteriyor (ölçüldü 2026-10-23).
- ⚠️ Telefon **iOS 27**'deyse Xcode 26.6 (iPhoneOS 26.5 SDK) ile kurulum
  ve hata ayıklama **ölçülmedi**; Xcode 27 bu depoyu derleyemiyor (§7). Bu
  Mac'te Xcode 27'nin bıraktığı kişiselleştirilmiş DDI duruyor (CoreDevice
  299.6). Flutter 3.44.7'nin Debug (JIT) kipinin iOS 26+ fiziksel cihazda
  çalışması da ölçülmedi. Debug düşerse test Profile kipe kayar; o da
  B1–B2 (App Attest) ister. Ayrı, anahtarsız bir dart-define dosyası
  artık gerekmez: U05 kod ağıyla (`09bbe23`) Profile'da `test_` anahtarı
  yapılandırılmaz ve satın alma "kullanılamıyor" der (kodda doğrulandı,
  cihazda ölçülmedi — A7).

**A2 — App ID üzerinde dört yetenek · SEN**
- developer.apple.com → Account → Certificates, Identifiers & Profiles →
  Identifiers → `ai.rytho` → Capabilities: **Sign in with Apple**, **Push
  Notifications**, **Associated Domains**, **App Attest** → Save. App ID
  yoksa `+` → App IDs → App → Explicit Bundle ID `ai.rytho` ile açılır.
  Cihaz gerekmez; yani iPhone gelmeden yapılabilir ve B4'ün (App Store
  Connect kaydı) önkoşuludur.
- Kutuların ayrıntısı (Apple yardım sayfaları, 2026-10-24; ekranda
  doğrulanmadı): Sign in with Apple kutusu → yanındaki **Configure**
  (portalda Edit görünebilir) → **Enable as a primary App ID** →
  pencerede Save; aynı penceredeki "Server-to-Server Notification
  Endpoint" boş kalabilir (zorunluluğu yalnız Kore merkezli
  geliştiricilerde; backend'de böyle bir uç yok — karar sahibin, öneri
  boş). Push'un yanındaki Configure sertifika içindir; `.p8` anahtar
  kullanıldığı için dokunulmaz. App Attest'in ek ayarı yok. Sonra sağ
  üstte Save → uyarı çıkarsa Confirm. Apple'a göre değişen App ID onu
  içeren profilleri geçersiz kılar; otomatik imza yeniden üretir.
  Sign in with Apple'ın **primary** ayarı C7'nin önkoşulu: anahtarın ve
  Services ID'nin "Primary App ID" listesi yalnız bunu açılmış App ID'yi
  gösterir.
- Açar: provizyon profili bu yetkileri taşır. Entitlements dördünü de
  istiyor (`Runner.entitlements` ve `RunnerRelease.entitlements` :18-54).
- Yapılmazsa: profil eksik yetkiyi taşımaz ve imza düşer. **App Attest bu
  listede bugüne dek yoktu** — 4.5 üç yetenek sayıyordu; eklendi
  2026-10-23.
- Durum: **ölçülemedi** (portal). Otomatik imzanın eksik yeteneği
  kendiliğinden açıp açmadığı ilk cihaz derlemesinde görülür.

**A3 — Cihaz kaydı ve geliştirme profili · SEN (Xcode'da)**
- `apps/mobile/ios/Runner.xcworkspace` → Runner hedefi → Signing &
  Capabilities → Team `292WJ9TP74`, "Automatically manage signing" açık →
  Xcode'un "Register Device" ve profil önerileri onaylanır.
- Yapılmazsa: imzalı cihaz derlemesi yok. Bugün iki profil dizini de yok
  (ölçüldü 2026-10-23). Aynı kayıt B9'u da açar: takımda cihaz yokken
  otomatik imzalı arşiv alınamaz.

**A4 — Firebase Auth'ta Apple sağlayıcısı (U01) · SEN**
- Firebase Console (rhytoai) → Authentication → Sign-in method → Add new
  provider → **Apple** → Enable → Save. Yerel iOS girişi için yalnız bu
  anahtar yeter; Services ID ve OAuth code flow alanları jeton iptali
  içindir (C7) ve aynı oturumda doldurulabilir. Dayanak (2026-10-24):
  Firebase belgesine göre yalnız Apple platformuna dağıtılan uygulamada
  Services ID, Team ID, anahtar ve Key ID boş kalabilir — giriş için
  Save yeter; hesap silmede Apple yetkisi iptali için yetmez (Firebase
  iOS belgesinin jeton iptali bölümü iki alanı da istiyor → C7). Girişin
  cihazda çalışması için A2'deki Sign in with Apple yeteneği de açık
  olmalı.
- Yapılmazsa: cihazda Apple ile giriş `operation-not-allowed` ile düşer;
  incelemede 4.8 + 2.1 reddi (U01).
- Durum: **ölçülemedi.** Bu adım §4'te hiç yoktu (`grep -i "sign-in
  method"` boştu, ölçüldü 2026-10-23).

**A5 — APNs anahtarı (U08) · SEN**
- Önce bak: Keys listesinde APNs anahtarı ve Firebase'de yüklü anahtar
  var mı (Apple ekip anahtarını ortam başına en çok 2 veriyor; gereksiz
  anahtar sınırı doldurur).
- developer.apple.com → Certificates, Identifiers & Profiles → Keys → `+`
  → Key Name → YALNIZ **Apple Push Notifications service (APNs)** →
  Configure → Environment listesine bak; Key Restriction "Team Scoped
  (All Topics)" (ya da yalnız `ai.rytho`; U08 adım 1) → Save → Continue
  → Confirm → Download → Done. `.p8` **yalnız bir kez** iner, Key ID not
  edilir. Apple'ın güncel belgesine göre ekip anahtarları **Sandbox YA DA
  Production** ile sınırlı, ortam başına en çok 2; iki ortamda çalışan
  anahtar yalnız MEVCUT olanlar için destekleniyor ve Apple ortama özel
  anahtar öneriyor. Belgeyle uyumlu yol iki anahtar: "Rytho APNs Sandbox"
  (Sandbox) ve "Rytho APNs Production" (Production). Listede "Sandbox &
  Production" görünürse tek anahtar da bir seçenek — ekranda doğrulanır,
  belgeyle değil; yeni anahtarda sunulup sunulmadığı ölçülemedi. Karar
  sahibin. Apple ile Giriş bu anahtara eklenmez (C7'de ayrı anahtar;
  öneri).
- Firebase Console → ⚙ → Project settings → Cloud Messaging → Apple app
  configuration (`ai.rytho`; Firebase belgesinde "iOS app configuration")
  → APNs Authentication Key. Firebase belgesi (2026-10-22) development
  ve production anahtarını AYRI sayıyor ("development key, production
  key, or both" — en az biri şart). İki anahtar açıldıysa Sandbox olan
  development, Production olan production yerine; her biri `.p8` + Key
  ID + Team ID `292WJ9TP74` → Upload. Tek çift-ortam anahtarının iki
  yere de yüklenip yüklenemeyeceği ekranda görülür (çıkarım, ölçülmedi).
  Ayrıntı 4.6.
- Yapılmazsa: cihaza hiçbir push gelmez (U14'ün ön plan banner'ı dahil);
  uygulamanın açılmasını engellemez. Firebase belgesine göre telefon
  doğrulamasının sessiz push yolu da çalışmaz ve reCAPTCHA'ya düşer
  (ölçülmedi). Yalnız bir ortamın anahtarı yüklenirse öteki ortamın
  jetonları düşer: Sandbox yarısı eksikse Debug/simülatör, Production
  yarısı eksikse TestFlight/App Store. Bu sessiz DEĞİL: FCM
  `THIRD_PARTY_AUTH_ERROR` (401) döner ve panelin "Kendime test gönder"i
  "Gönderim başarısız" gösterir; sessiz kalan yalnız toplu koşulardaki
  INFO düzeyindeki "Bildirim gonderilemedi" günlük satırı
  (`push_service.py:163`).
- Durum: **ölçülemedi**; paket tarafı hazır (`aps-environment`,
  `UIBackgroundModes = remote-notification`).

**A6 — App Check debug jetonu · `APP_CHECK_DEBUG_TOKEN` doluysa yapılmış; boşsa SEN (ilk koşudan hemen sonra)**
- **Güncel (2026-10-24): sabit jeton.** `dart_defines.local.json`'a
  `APP_CHECK_DEBUG_TOKEN` (bir UUID) yazılırsa Debug derlemesi her
  kurulumda o jetonu kullanır (`main.dart` `kAppCheckDebugToken` →
  `AppleDebugProvider(debugToken:)`); Firebase'e bir kez eklenir, silip
  yeniden kurmak jetonu değiştirmez. Bu Mac'in dosyasında var ve
  Firebase'de kayıtlı — simülatörde ölçüldü: kayıtsızken
  `exchangeDebugToken` 403, kayıtlıyken 200 ve giriş çalıştı. Aynı
  dosyayla derlenen cihaz Debug'ı da aynı jetonu taşır; cihazda
  ölçülmedi. Jeton yayın paketine girmez (imzasız Release'te 0 kez,
  ölçüldü; `infra/build-ipa.sh` `paket-appcheck-jetonu-yok` kapısı her
  yayında yeniden ölçer). Aşağıdaki iki madde define BOŞKEN geçerli.
- İlk `flutter run` (A7) konsola `Firebase App Check Debug Token: …`
  satırını basar; eklenti her kurulum için yeni jeton üretiyor
  (`FirebaseAppCheckPlugin.swift:318-325`). Firebase Console → Security →
  App Check → Apps → `ai.rytho` (iOS) → ⋮ → **Manage debug tokens** → Add
  debug token → yapıştır → uygulamayı yeniden başlat. (App Check sol
  menüde Security grubunun altında — Firebase belgesi 2026-10-22.)
- ⚠️ Jeton gizli bir değerdir: depoya, sohbete, ekran görüntüsüne girmez.
  Uygulama silinip yeniden kurulunca değişir ve yeniden eklenir. Şemada
  sabit jeton yok (`Runner.xcscheme`'de `FIRAAppCheckDebugToken` ortam
  değişkeni yok, ölçüldü 2026-10-23).
- Yapılmazsa: zorlama Auth + Firestore + Storage'da açık (CLAUDE.md, son
  ölçüm 2026-10-10) ve Debug derlemesi `AppleDebugProvider` kullanıyor
  (`main.dart:177-181`) → kayıtsız jetonla giriş, Firestore ve Storage
  reddedilir. Belirti App Check'e özgü bir hata DEĞİL: iOS'ta
  `activate()` yalnız sağlayıcıyı kaydeder ve düşmez; kayıtsız jeton
  ancak jeton değişiminde reddedilir. Kullanıcı App Check'e özgü bir
  mesaj görmez: giriş genel "Bir şeyler ters gitti. Tekrar dene."
  metniyle düşer (`authFailed`; simülatörde ölçüldü 2026-10-24) — yanlış
  şifre metninden ("Giriş yapılamadı. Şifren hatalı olabilir…") farklı,
  ama başka beklenmedik hatalardan ayırt edilemez; Firestore/Storage'da
  izin hatası çıkar (`core/app_check_izi.dart:3-16`). Debug'da tek iz Xcode konsoludur;
  Release/TestFlight'ta Crashlytics'e `app-check-token` kaydı düşer
  (U30). Simülatörün kendi ürettiği jeton cihaza geçmez; sabit jeton
  (yukarıdaki ilk madde) ise define dosyasıyla birlikte geçer. *(Düzeltme 2026-10-24: burada "`activate()`
  hatası yutulduğu için belirti sessiz giriş ekranı" yazıyordu; kod
  tersini söylüyor — `main.dart:188-190`'daki catch bu durumda hiç
  çalışmaz.)*

**A7 — Derle ve koş · birlikte**
- `cd apps/mobile && LANG=en_US.UTF-8 flutter run
  --dart-define-from-file=dart_defines.local.json` (Debug; simülatör de
  açıksa `-d <cihaz kimliği>` ile telefon seçilir), ardından —
  define'da `APP_CHECK_DEBUG_TOKEN` boşsa — A6.
- `test_` anahtarıyla Debug **çökmez** (RevenueCat'in Test Store kapısı
  `#if !DEBUG` altında); satın almalar yalnız RevenueCat Test Store
  simülasyonudur, StoreKit sandbox değil — gerçek satın alma testi B'de.
- ⚠️ (2026-10-23 hâli, `ba6108b`) Bu aşamada Release/Profile cihaz
  denemesi YAPILMAZ: `test_` anahtarı açılışta bilerek çöker (B6). "Yalnız
  iOS anahtarını boşalt" çaresi de güvenli değil: `billingConfigured` iki
  anahtardan birinin doluluğuna bakıyor (`subscription.dart:53-54`) ve
  Android anahtarı yüzünden true kalır; `initBilling` iOS'ta configure
  etmeden döner ama `billingIdentityProvider` (`:139`) girişte yine
  `Purchases.logIn` çağırır, yani yapılandırılmamış SDK'ya gider (yerel
  tarafın çöküp çökmediği ölçülmedi; Dart `try/catch` yerel çökmeyi
  yakalamaz). Zorunluysa İKİ anahtarın da boş olduğu ayrı bir dart-define
  dosyası + B1–B2.
- **Güncel (2026-10-24, U05 kod ağı `09bbe23`):** yukarıdaki tavsiye
  gereksizleşti. `rcEtkinAnahtar` yalnız çalışılan platformun anahtarına
  bakıyor; Release + Profile'da `test_` önekli anahtar yapılandırılmamış
  sayılıyor — `Purchases.configure` hiç çağrılmaz, `billingConfigured`
  false. "Satın alımları geri yükle" düğmesi de kapılı:
  `ensureBillingIdentity` ilk satırda durur ve "Satın alma şu an
  kullanılamıyor" der (yapılandırılmamış SDK PurchasesHybridCommon
  17.55.1 `CommonFunctionality.swift:18-22`'de `fatalError` veriyor).
  Yani `test_` anahtarlı Profile/Release cihaz derlemesi çökmez, ayrı bir
  anahtarsız dart-define dosyası gerekmez; yine B1–B2 (App Attest) ister.
  Kodda doğrulandı, cihazda ölçülmedi. U05'in çürütme turu (2026-10-24,
  mutasyonla) çağrı yeri kapılarını (`billingIdentityProvider`,
  `offeringsProvider`, `tokenPacksProvider`) hiçbir testin tutmadığını
  ölçtü; 2. tur bekçiyi kurdu (`test/satin_alma_yapilandirma_test.dart`,
  aynı commit `09bbe23`).

**A8 — Cihazda ölçülecekler · birlikte**
- U21'in A5 satırlarından Debug'da ölçülebilenler (Release'e bağlı olanlar
  — StoreKit sandbox, Crashlytics dSYM ve App Check izleri — B10'da):
  giriş (e-posta, Google, Apple); kurulumdaki iki
  kutu; bildirim izninin soru ânı (U11: girişte değil, ilk anlamlı anda);
  push (A5'ten sonra — ön plan, arka plan, kapalı, dokunuş rotası);
  Firestore'da `fcmToken` (U54); yüz okuma (deklanşör açılıyor mu, alın
  ölçülüyor mu, noktalar iki lenste yüzün üstünde mi — U09); kamera reddi
  + "Ayarları aç" (U56, `app_settings` 7.0.0); telefon doğrulaması;
  "Resmi Kaydet" (U44); Sessiz anahtar + Apple Music (U24); silip yeniden
  kurunca giriş ekranı (U45); Apple düğmesinin iPhone SE + 1,3 yazı
  ölçeğinde görünmesi (U04).
- **Hesap silme + Apple yetkisi iptali (U15'in tek doğrulaması; önkoşul
  C7)** — AYRI bir test hesabıyla (gerçek veri silinmesin): Apple ile
  giriş → Profil → Hesap → Hesabı sil → açılan Apple sayfasını onayla →
  silme bitince iPhone Ayarlar → adın → "Apple ile Giriş" (Sign in with
  Apple) listesinde **Rytho kalmamalı** (menünün tam yeri iOS sürümüne
  göre değişebilir, ölçülmedi). Kalıyorsa iptal düşmüştür: Debug'da tek
  iz Xcode konsolundaki "Apple yetkisi iptal edilemedi" satırı
  (`auth_service.dart:281`), yayında Crashlytics `apple-revoke`. Apple
  girişi testinde tuzak (U31): Apple Kimliğinin e-postası Rytho'da Google
  ya da şifreyle kayıtlıysa ve "e-postamı paylaş" seçilirse giriş
  `account-exists-with-different-credential` ile düşer — yapılandırma
  kusuru değil; Hide My Email ya da Rytho'da kullanılmamış bir Apple
  Kimliği seçilir. *(Ek 2026-10-24: silme/iptal denemesi hiçbir aşama
  adımında yoktu.)*
- **Deploy'a bağlı, "bekliyor" işaretlenir:** Universal Link `/i/` ve
  `/r/` (canlı AASA bayat — hosting kilidi), `users/{uid}/private/aiConsent`
  kaydı (canlıda uç yok) ve engelleme — ikisi de "Deploy bağımlılıkları"
  1'e (kurallar + backend birlikte) bağlı.
- Simülatörde görülen hiçbir şey (giriş ekranının açılması dahil) cihaz
  sonucu sayılmaz.

### Aşama B — iç TestFlight (Release, App Attest, StoreKit sandbox)

**B1 — Firebase iOS uygulamasında Team ID · SEN**
- Firebase Console → ⚙ → Project settings → General → Your apps → iOS
  `ai.rytho` → **Team ID** alanının yanındaki düzenleme simgesi (simgenin
  adı belgede yok, ölçülmedi) → `292WJ9TP74` → Save. Doluysa ve aynıysa
  dokunulmaz. App Attest kaydının önkoşulu (U42, U08).
- Durum: **ölçülemedi.**

**B2 — App Check'te App Attest kaydı (U08) · SEN**
- Firebase Console → **Security** → App Check → Apps sekmesi → `ai.rytho`
  (iOS) → **App Attest** → Token time-to-live varsayılan (1 saat)
  bırakılır → Save. Android satırına ve APIs sekmesindeki "Enforced"
  ayarlarına dokunulmaz. Önce B1; App ID'de App Attest yeteneği açık
  olmalı (A2). Bugün dağıtılmış iOS paketi olmadığı için kimseyi
  etkilemez; ilk cihaz/TestFlight denemesinden ÖNCE yapılır.
- Yapılmazsa: Release, Profile, TestFlight ve inceleme paketi
  `AppleAppAttestProvider` (`main.dart:181`) ile jeton alamaz; zorlama
  açık olduğu için **giriş yapılamaz**. Belirti büyük olasılıkla genel
  "Bir şeyler ters gitti" (debug jetonu reddinde ölçülen sınıf — A6; App
  Attest için ölçülmedi). *(Düzeltme 2026-10-24: burada "cihazda
  `flutter run --release` denemesi de giriş ekranında kalır" yazıyordu —
  hem belirti hem kip yanlıştı.)*
- **Cihaz denemesi TestFlight'tan ÖNCE yapılabilir:** Apple'ın belgesine
  göre yetki `production` iken geliştirme imzalı derleme de üretim App
  Attest sunucularını kullanır; Firebase yalnız üretim jetonunu kabul
  eder. A1 + A3'ten sonra Terminal'de `cd apps/mobile && LANG=en_US.UTF-8
  flutter run --profile -d <cihaz kimliği>
  --dart-define-from-file=dart_defines.local.json`; sırayla e-postayla
  giriş, profilin yüklenmesi (Firestore), avatar yükleme (Storage).
  Yalnız **`--profile`**: Debug App Attest'e hiç gitmez
  (`AppleDebugProvider`); `--release` önerilmez — Release
  `RunnerRelease.entitlements`'ı (`aps-environment = production`)
  kullanıyor ve geliştirme profiliyle imzada düşebilir (B9, ölçülmedi);
  Profile `Runner.entitlements`'ı kullanır (aps development, App Attest
  production). Kayıttan önce denenip hata alındıysa ayarlardan sonra
  uygulama tamamen kapatılıp açılır: AppCheckCore reddin ardından
  bekleme süresini bellekte tutuyor, yeniden başlatma sıfırlar (koddan).
  Profile'da `kDebugMode` false olduğu için jeton yoklaması ve
  Crashlytics kaydı çalışır: `app-check-token` izi bu denemede de
  aranabilir (koddan).
- Doğrulama: Profile cihaz denemesinde ya da ilk TestFlight kurulumunda
  giriş çalışıyor ve Crashlytics'te `app-check-token` /
  `app-check-activate` kaydı yok (U30).
- Ölçülmedi: yalnız Firebase'in geliştirme imzalı + `appattest-environment
  = production` jetonunu kabulü (Apple yarısı belgeyle cevaplı: üretim
  sunucuları) — cihazda, kayıttan sonra görülür. *(Düzeltme 2026-10-24:
  madde iki yarıyı da "ölçülemedi" sayıyordu.)*

**B3 — Paid Apps sözleşmesi, vergi, banka (U02 adım 1) · SEN**
- App Store Connect → **Business** (eski adı Agreements, Tax, and
  Banking) → Paid Apps → sözleşmeyi kabul et → vergi formları → banka
  hesabı. AB DSA **tacir durumu** sorusu da burada cevaplanır (U41 — AB
  dışı dağıtımda da soruluyor).
- Yapılmazsa: uygulama içi satın alma ürünleri satışa çıkmaz; teklifler
  boş ya da `configurationError` döner, paywall fiyat yerine hata gösterir
  (U02 etki a).

**B4 — App Store Connect uygulama kaydı (4.9) · SEN — iPhone'u beklemez**
- App Store Connect → Apps → `+` → **New App**: Platforms **iOS** · Name
  **Rytho** (adın boşta olduğu ölçülemedi) · Primary Language (bölge
  yalnız Türkiye; öneri Türkçe) · Bundle ID **`ai.rytho`** (listede
  görünmesi için App ID portalda kayıtlı olmalı — A2) · SKU serbest metin
  (ör. `rytho-ios`) · User Access: Full Access.
- Ardından App Information: birincil kategori **Lifestyle** (U19);
  Content Rights "üçüncü taraf içerik var ve haklar mevcut" (RAG korpusu
  kamu malı — `docs/rag_corpus/README.md:32`). Copyright ve Support URL
  bu ekranda değil, sürüm sayfasında (C8). *(Düzeltme 2026-10-24: burada
  "telif satırı" App Information'a yazılmıştı.)*
- Doğan sayısal **Apple ID** → `dart_defines.local.json` `APPSTORE_APP_ID`.
- Yapılmazsa: TestFlight'a yükleme yapılamaz. `APPSTORE_APP_ID` boşken
  zorunlu güncelleme ekranı iOS'ta mağaza düğmesi göstermez
  (`force_update_screen.dart:51`) — eksiklik ancak yayından sonra görünür.
  Bu formun ayrıntıları hiçbir belgede yoktu (ölçüldü 2026-10-23: `SKU`,
  `Primary Language`, `Content Rights` araması 0).

**B5 — Abonelik grubu ve ürünler (U02 adım 2-4) · SEN**
- App Store Connect → uygulama → Monetization → **Subscriptions** →
  Subscription Group (yerelleştirilmiş görünen ad) → `rytho_plus_monthly`.
  **Tanıtım teklifi ya da ücretsiz deneme EKLENMEZ** — sunucu denemesiyle
  3+3 gün çakışır (`docs/store-launch.md` "Kalan konsol işleri" 1).
- Monetization → **In-App Purchases** → `+` Consumable ×3:
  `rytho_tokens_small`, `rytho_tokens_medium`, `rytho_tokens_large`.
  Görünen adlar sözlükle aynı (`docs/store-launch.md` "Mağaza ürün adları"
  tablosu); her ürüne inceleme ekran görüntüsü (paywall, kredi mağazası).
  Kimlikler kodda sabit, değişmez (4.7).
- Fiyat noktası ve Aile Paylaşımı: aşağıdaki "Sahibin kararları".

**B6 — RevenueCat App Store uygulaması ve `appl_` anahtarı (U02 adım 5-6) · SEN**
- App Store Connect → Users and Access → Integrations → **In-App
  Purchase** → anahtar üret (`.p8` + Key ID + Issuer ID).
- RevenueCat → proje → Apps → `+` App Store → bundle `ai.rytho` →
  In-App Purchase Key'i yükle → API keys → `appl_…` →
  `dart_defines.local.json` `REVENUECAT_IOS_KEY`. Ürünleri içe aktar;
  `rytho_plus_monthly` → `RhytoAI Pro` yetkisi + Current offering'in
  `$rc_monthly` paketi; consumable'lar yetkiye bağlanmaz (4.7).
- Ürünleri içe aktarmak **ayrı bir App Store Connect API anahtarı** ister
  (U02 adım 6): Users and Access → Integrations → App Store Connect API →
  Team Keys → `.p8` + Key ID + Issuer ID → RevenueCat'e yüklenir. Bu
  anahtar yoksa `rytho_plus_monthly` ve üç consumable RevenueCat'e
  kimlikleriyle elle eklenir. (Konsol menü adları ekranda doğrulanmadı.)
- Yapılmazsa (2026-10-23 hâli, `ba6108b`): `test_` anahtarlı Release paketi
  **açılışta BİLEREK çöker** — RevenueCat 5.67.1
  `Configuration.swift:471-495`, `#if !DEBUG` altında Test Store anahtarı
  → uyarı penceresi + `fatalError`; `initBilling` arayüzden önce
  çağrılıyor (`ba6108b`'de `main.dart:198`; HEAD'de `:221`). Anahtar 2026-10-23'teki imzasız Release
  paketinde `App.framework/App` içinde bulundu (ölçüldü). **U05 kod ağı
  (`09bbe23`) sonrası:** uygulama Release/Profile'da `test_` anahtarıyla
  `configure` etmez; çökme yerine satın alma kapalı çıkar ve
  `infra/build-ipa.sh` böyle bir paketi `revenuecat-ios-anahtari` (ön
  kapı) ve `paket-test-anahtari-yok` (paket kapısı) ile durdurur (B7).
  SDK'nın Test Store çökmesi değişmedi; değişen, uygulamanın ona
  girmemesi. In-App Purchase Key yoksa StoreKit 2 işlemleri RevenueCat'e
  yazılmaz, webhook tetiklenmez, Rytho+ ve kredi açılmaz (U02 etki b).

**B7 — iOS yayın kapısı: `infra/build-ipa.sh` · kod (U05) + birlikte**
- IPA **ASLA** düz `flutter build ipa` ile değil, `infra/build-ipa.sh`
  ile üretilir (CLAUDE.md §4). Kod `09bbe23` (iki tur tek commit); kapıların
  tam listesi ve durumu U05 kaydında. Kipler (depo kökünden):
  - `infra/build-ipa.sh --kuru` — yalnız ön kapılar, derleme yok: Xcode
    26.x, define dosyası var, `REVENUECAT_IOS_KEY` `appl_`,
    `REVENUECAT_ANDROID_KEY` `test_` önekli değil, `APPSTORE_APP_ID`
    sayısal, yetki adı, pbxproj takımı ↔ AASA, derleme numarası. B4 (kimlik), B6
    (`appl_`) ve B8 (numara) bitmeden KALDI der — beklenen.
  - `infra/build-ipa.sh` (tam kip) — ön kapılar → `flutter build ipa
    --release --dart-define-from-file` → paket ve imza kapıları. Hiçbir
    şeyi yüklemez. B9'daki önerilen yol.
  - `infra/build-ipa.sh --yalniz-denetle <.app|.ipa>` — yalnız paket
    kapıları: imzasız ölçüm ve Organizer'dan dışa aktarılan IPA için.
  İmzasız .app'te imza kapıları "ATLANDI (imzasız)" der, GEÇTİ değil;
  .ipa'da ve tam kipte imza zorunlu, imzasız IPA KALDI (çıkış 1).
- Ölçülen (2026-10-23): sahte `appl_` anahtarlı gerçek imzasız Release
  derlemesinde 6 paket kapısı geçti, derleme numarası (53) kapısı KALDI,
  3 imza kapısı ATLANDI. **Ölçülmedi:** tam kip gerçek araçla hiç koşmadı
  (yalnız sahte `flutter` ile sınandı) ve imzalı IPA (dağıtım sertifikası
  yok) — ilk imzalı IPA'da imza kapıları ölçülür.
- Kapısız arşiv alınmaz: 2026-10-23'teki imzasız Release derlemesi `test_`
  anahtarıyla hiçbir engele takılmadan "başarılı" çıktı — Android'de
  1.5.0+17'nin düz komutla çıkmasıyla aynı sınıf kusur (CLAUDE.md §4).
  Xcode'un kendi Product → Archive yolu betiğin kapılarından geçmez; o yol
  seçilirse arşivden ÖNCE `--kuru`, dışa aktarılan IPA'ya
  `--yalniz-denetle` koşulur (ikincisi yalnız paket kapılarıdır; Xcode
  sürümü, `APPSTORE_APP_ID`, yetki adı ve takım ↔ AASA ön kapılarını
  koşmaz).

**B8 — Derleme numarası · KARAR (öneri: iOS 54'ten başlar)**
- Bugünkü pubspec `1.20.0+53` → iOS paketi `1.20.0 (53)` çıkıyor
  (ölçüldü: imzasız Release'te `CFBundleVersion = 53`).
- Öneri: ilk iOS yüklemesi **en az 54**. Gerekçe: (1) gizlilik metni "Bu
  ayrı kutu **1.20.0+54** sürümüyle eklendi" diyor
  (`web/legal/gizlilik.html:224`, `web/en/legal/privacy.html:231`,
  `legal_texts.dart:282` ve `:694`) — kutuyu taşıyan iOS 53 için cümle
  yanlış olur; (2) Android'de en az 17/41/43/44/46/48/50/52/53 kullanıldı
  (51'in yüklenip yüklenmediği bilinmiyor — CLAUDE.md §6; 53 canlı ve
  kutusuz). App Store Connect'in derleme numaraları Play'den bağımsızdır;
  çakışma sunucuda: `appBuild` aynası ve `minBuild` eşiği platform
  ayırmıyor (U29) — 53'le yüklenen iOS, ileride Android için `minBuild =
  54` yazıldığında kutuyu zaten taşıdığı hâlde kilitlenir. *(Düzeltme
  2026-10-24: burada "Android'in kullanılmış kodları 48/50/52/53"
  yazıyordu — liste eksikti ve gerekçe Apple kısıtı gibi okunuyordu.)*
- Uygulama: pubspec `+53` → `+54` tek commit'te ve Android 54 ile aynı
  değişiklik (CLAUDE.md §7 "Android 54'e giden sıra" adım 2); hangi makine
  önce yaparsa push eder. **Karar sahibin, henüz verilmedi.** Not:
  `infra/build-ipa.sh` (`09bbe23`) bu öneriyi bugün kapı olarak kodluyor
  (`RYTHO_EN_DUSUK_KOD=54`; yanmış liste 17/41/43/44/46/48/50/52/53, 51
  belirsiz — ayrı mesajla reddediliyor) — sahip başka bir numaraya karar
  verirse betik de değişir. ⚠️ iOS 54 Android 54 ile AYNI commit'ten
  çıkacaksa, Android 54 yüklendiğinde 54 `RYTHO_YANMIS_KODLAR`'a EKLENMEZ
  (aynı içerik; eklenirse kapı iOS 54'ü durdurur). Farklı commit'ten
  çıkacaksa iOS, Android'in kullandığı koddan farklı bir sayı alır.

**B9 — Dağıtım imzası ve arşiv · SEN (Xcode'da)**
- Önkoşul A3: takımda kayıtlı cihaz yokken otomatik imza arşiv için
  profil üretemez (Xcode'un bilinen "Your team has no devices…" davranışı —
  burada ölçülmedi). Daha erken yüklemek gerekirse portalda Devices → `+`
  ile bir UDID kaydedilir.
- Dağıtım sertifikası bu Mac'te **yok** (`security find-certificate -a -c
  "Apple Distribution"` boş, ölçüldü 2026-10-23). Organizer → Distribute
  App → App Store Connect yolu otomatik imzayla oluşturur; ya da Xcode →
  Settings → Accounts → takım → Manage Certificates → `+` → Apple
  Distribution. Bireysel hesabın sahibi buna yetkili.
- Önerilen yol: `infra/build-ipa.sh` tam kip (B7) — `flutter build ipa`
  arşivi ve dışa aktarımı yapar, kapılar IPA'nın üstünde koşar
  (`apps/mobile/build/ios/ipa/`); IPA Transporter ile ya da
  `apps/mobile/build/ios/archive/` altındaki arşiv Organizer'da açılarak
  yüklenir (B10). Bu yol gerçek imzayla hiç koşmadı (ölçülmedi).
- Xcode'un kendi yolu seçilirse: arşivden önce `infra/build-ipa.sh
  --kuru` (ön kapılar; `--yalniz-denetle` onları koşmaz) ve `flutter build ios
  --config-only --release --dart-define-from-file=dart_defines.local.json`
  (Generated.xcconfig gerçek anahtarı taşısın — U05 kaydındaki not), sonra
  Xcode → Product → Archive (hedef "Any iOS Device"); dışa aktarılan IPA'ya
  `infra/build-ipa.sh --yalniz-denetle <ipa>`.
- ⚠️ İlk imzalı Release'te ölçülecek (ölçülmedi): Release
  `RunnerRelease.entitlements`'ı (`aps-environment = production`)
  kullanıyor, otomatik imza ise önce geliştirme profiliyle imzalıyor;
  Xcode "doesn't match the entitlements file's value for the
  aps-environment entitlement" ile durabilir. Durursa aday çare Release'i
  `Runner.entitlements`'a bağlamak (Apple'a göre dışa aktarma dağıtım
  profiliyle yeniden imzalayıp production'a çevirir — çıkarım, ölçülmedi)
  ve `test_ios_config.py`'deki iki-dosya bekçisini buna göre değiştirmek;
  durmazsa dosyalara dokunulmaz.
  Entitlements imzasız derlemede gömülmüyor; imzalı pakette `codesign -d
  --entitlements :- Runner.app` ile okunur. *(Düzeltme 2026-10-24: burada
  "development kalırsa üretim arşivi sandbox jetonu alır" gerekçesinin
  yeniden ölçüleceği yazıyordu; Apple belgesi ve FCM SDK kaynağı ortamın
  profilden geldiğini söylüyor, gerekçe yanlış — 4.5.)*

**B9a — B10'dan önce: kurallar + backend deploy'u · SEN (onay; önerilir,
TestFlight'ın engeli değil)** — aşağıdaki "Deploy bağımlılıkları" madde 1.
Önce CLAUDE.md §7 "Android 54'e giden sıra" adım 3'teki salt okuma sayım;
backend tek başına öne alınmaz. B10'dan önce yapılırsa ilk iOS kurulumunda
onay kaydının yazıldığı ölçülür; yapılmazsa TestFlight sürer, onay kaydı
satırı "bekliyor" kalır. *(Düzeltme 2026-10-24: bu adım "B11 —
TestFlight'tan ÖNCE backend deploy'u" adıyla B10'un arkasındaydı ve
sayımı atlıyordu.)*

**B10 — Yükle ve iç gruba ver · SEN**
- Organizer → Distribute App → App Store Connect → Upload. App Store
  Connect → uygulama → TestFlight → Internal Testing → `+` grup → sahibin
  hesabı. Hesap sahibi iç testçidir; iç grupta **Beta App Review yok**.
  `ITSAppUsesNonExemptEncryption = false` olduğu için şifreleme sorusu
  çıkmaz (ölçüldü: derlenen Info.plist).
- İlk kurulumdan sonra doğrula (U21 madde 5-6): giriş çalışıyor;
  Crashlytics'te bu derlemenin dSYM UUID'si var (U26) ve `app-check-token`
  / `app-check-activate` kaydı yok (U30); StoreKit sandbox satın alma ve
  geri yükleme (C2).
- Dış grup açılacaksa TestFlight → **Test Information** (beta açıklaması,
  geri bildirim e-postası, iletişim, demo hesap, "What to Test", gizlilik
  politikası URL'si — Apple belgesine göre dış test için gerekli,
  ölçülmedi) doldurulur ve ilk dış derleme Beta App Review'dan geçer. Bu
  bilgiler hiçbir belgede yok (açık iş, U21). Gizlilik URL'si hosting
  kilidine bağlı (C1): dış grup kilit çözülmeden açılırsa Beta App Review
  17 Ekim tarihli eski metni görür.

(B11 — "TestFlight'tan ÖNCE backend deploy'u" — 2026-10-24'te B9a'ya
taşındı ve kurallarla birleştirildi.)

### Aşama C — App Store incelemesi

**C1 — Hosting kilidi ve canlı gizlilik URL'si · KARAR** — aşağıdaki
"Deploy bağımlılıkları ve hosting kilidi". Gönderimde App Store Connect'e
verilen Gizlilik Politikası URL'si uygulama içi metinle **aynı tarihi ve
aynı veri listesini** göstermeli. Bugün canlı 17 Ekim, uygulama içi 23
Ekim (ölçüldü 2026-10-23: canlı TR metinde "kutu" ve "kurulum" 0 kez,
depoda 4 ve 3; Gemini alt işleyici satırı ve ABD aktarım cümlesi canlıda
yok).

**C2 — Satın almalar ilk sürümle (U02 adım 4, 7, 8) · SEN**
- Sürüm sayfası → In-App Purchases and Subscriptions → dört ürün
  iliştirilir. Kullanım Koşulları bağlantısı açıklamada ya da EULA
  alanında (C5). Sandbox satın alma + geri yükleme TestFlight'ta denenir;
  Ask to Buy (U33).

**C3 — App Privacy etiketi (U20) · SEN + belge**
- Önce `docs/store-privacy-labels.md` §2 U20 listesine göre düzeltilir:
  Apple bölümünde Phone Number, Photos or Videos, Customer Support ve
  Device ID yok, :82'deki transkript iddiası yanlış, belge 2026-09-18'den
  beri değişmedi (ölçüldü). U20 listesine ek olarak yeni gizlilik
  metninin saydığı üç tür: yaşanan şehir, arkadaşla ortak harita verisi
  ve I Ching soru kapısı (CLAUDE.md §7 "Android 54'e giden sıra" adım 7;
  U20 bu verilerden eski). Etiket deploy edilecek metinle karşılaştırılarak
  doldurulur. Sonra App Store Connect → uygulama → **App Privacy** → Get
  Started; izleme hiçbir maddede yok.

**C4 — Yaş derecelendirmesi (U37) · KARAR + SEN**
- App Store Connect → uygulama → App Information → **Age Rating** → Edit:
  Messaging and Chat = Evet; UGC cevabı gerekçesiyle; hedef 13+.
  Belgelerdeki 12+ (`store-privacy-labels.md:220`,
  `production-checklist.md:175`) düzeltilir; Koşullar'a (TR+EN) sıfır
  tolerans maddesi — hukuk metni, önce sahibe sorulur.

**C5 — EULA · KARAR**
- App Store Connect → uygulama → App Information → **License Agreement**.
  (a) Apple'ın standart EULA'sı kalır, açıklamaya Kullanım Koşulları
  bağlantısı yazılır — en kısa yol. (b) Koşullar özel EULA olarak girilir;
  o zaman Apple'ın asgari maddeleri Koşullar'a (TR+EN) eklenir — hukuk
  metni, sahip onayı.
- Ölçüldü 2026-10-23: `web/legal/kullanim.html` ve
  `web/en/legal/terms.html`'de "EULA" ya da Apple standart EULA bağlantısı
  yok. Otomatik yenilenen abonelikte Koşullar bağlantısı yoksa 3.1.2
  reddi gelir (U02 etki d).

**C6 — Pricing and Availability (U41, U53) · SEN**
- App Store Connect → uygulama → **Pricing and Availability**: bölge
  yalnız Türkiye; "iPhone and iPad Apps on Apple Silicon Macs" ve Apple
  Vision Pro işaretleri aşağıdaki KARAR'a göre (öneri: kaldırmak; U53).
  Fiyat: "Sahibin kararları".
- **Mac / Vision Pro erişimi · KARAR (öneri: ikisi de kapatılır).**
  Apple'ın `DCAppAttestService.isSupported` belgesine göre Mac'te değer
  **false** — Apple silicon'da çalışan iOS uygulamaları DAHİL; AppCheckCore
  bu durumda jeton vermez, yani zorlama açıkken Mac kullanıcısı giriş
  yapamaz. Eklentinin yedekli (DeviceCheck) varyantı yalnız iOS sürümüne
  bakıyor (`FirebaseAppCheckPlugin.swift:333-338`), Mac'i kurtarmaz; açık
  tutmanın tek yolu `isSupported`'a bakan özel bir yedek (yerel kod +
  Firebase'de DeviceCheck kaydı + DeviceCheck `.p8`). Vision Pro'da
  "Designed for iPad" için `isSupported` belgelenmedi; WWDC26 macOS 27'de
  App Attest desteğinden söz ediyor ama Mac'te çalışan iOS uygulaması için
  belgelenmedi — ikisi de belirsiz. Yol (önkoşul B4; ekranda
  doğrulanmadı): Pricing and Availability → "iPhone and iPad Apps on
  Apple Silicon Mac" → Apple Silicon Mac Availability → "Make this app
  available" işaretini kaldır; "iPhone and iPad Apps on Apple Vision Pro"
  → "Make this app available on Apple Vision Pro" işaretini kaldır → Save.
  **Karar sahibin.** *(Ek 2026-10-24: U53 bunu "kullanılamayabilir" diye
  yumuşak anlatıyordu.)*

**C7 — Apple yetkisi iptali ve Hide My Email (U15, U22) · SEN**
- developer.apple.com → Keys → `+` → **Sign in with Apple** (Primary App
  ID `ai.rytho`) → `.p8`; Identifiers → `+` → Services IDs; Firebase →
  Authentication → Sign-in method → Apple → Services ID + OAuth code flow
  configuration (Team ID, Key ID, private key). A4 ile aynı oturumda
  yapılabilir. Yapılmazsa hesap silmede Apple yetkisi iptali düşer, yalnız
  Crashlytics'te `apple-revoke` görünür (U15).
- Certificates, Identifiers & Profiles → Services → **Sign in with Apple
  for Email Communication** → Configure → `noreply@rhytoai.firebaseapp.com`.
  Yapılmazsa Hide My Email seçen kullanıcıya şifre sıfırlama ve doğrulama
  postası ulaşmaz (U22).
- **Tam sıra ve yollar (Apple + Firebase belgeleri, 2026-10-24; ekranda
  doğrulanmadı, konsol durumu ölçülmedi).** *(Düzeltme 2026-10-24:
  yukarıdaki iki madde Services ID'nin yapılandırmasını ve e-posta
  kaynağının "Email Sources" adımını atlıyordu — yalnız kimliği
  oluşturulmuş Services ID'de Apple ile Giriş açık değildir.)*
  0. Önce A2: `ai.rytho`'da Sign in with Apple **primary** olmalı; yoksa
     aşağıdaki "Primary App ID" listeleri boş gelir.
  1. **Anahtar:** Keys → `+` → Key Name (ör. "Rytho Sign in with Apple")
     → **Sign in with Apple** kutusu → yanındaki Configure → Primary App
     ID `ai.rytho` → Save → Continue → Confirm → Download → Done. `.p8`
     **yalnız bir kez** iner (kaybolursa anahtar iptal edilip yenisi
     açılır); sayfadaki 10 karakterlik **Key ID not edilir** (Firebase'e
     girilecek). Bir birincil App ID'ye en çok iki anahtar. APNs
     anahtarından ayrı tutulması öneri (Apple'a göre iptal edilen anahtar
     onu kullanan bütün servisleri bozar; karar sahibin). Dosya depo
     klasörüne konmaz (`.gitignore` `*.p8`).
  2. **Services ID:** Identifiers → `+` → Services IDs → Continue →
     Description ("Rytho Sign in") · Identifier (öneri `ai.rytho.signin`;
     bundle ID'den FARKLI olmalı — karar sahibin) → Continue → Register →
     listede (sağ üstteki filtre: Services IDs) bu kimliği aç → **Sign in
     with Apple** kutusu → **Configure** → Primary App ID `ai.rytho` →
     Website URLs: Domains and Subdomains `rhytoai.firebaseapp.com`,
     Return URLs `https://rhytoai.firebaseapp.com/__/auth/handler` →
     Next → Done → Continue → Save. Firebase iOS belgesi Return URL
     kaydını adım sayıyor; belgeye göre gerekli, Firebase'in iPhone'dan
     gelen yetki kodunu iptal ederken Services ID'yi kullanıp kullanmadığı
     ölçülmedi.
  3. **Firebase:** Authentication → Sign-in method → Apple satırı →
     Services ID (2'deki kimlik) → OAuth code flow configuration: Apple
     team ID `292WJ9TP74`, Key ID (1), Private key (`.p8`'in tüm içeriği;
     BEGIN/END satırlarıyla yapıştırmak yaygın pratik, resmi belgede
     yazmıyor) → Save.
  4. **E-posta kaynağı:** Certificates, Identifiers & Profiles → Services
     → Sign in with Apple for Email Communication → Configure → **Email
     Sources** → `+` → adres → Next → Register. Adres Firebase →
     Authentication → Templates'teki **From** alanıyla BİREBİR aynı olmalı
     (büyük olasılıkla `noreply@rhytoai.firebaseapp.com`; konsolda
     okunmadı — SMTP settings'te özel sunucu varsa o adres). Alan adı
     değil ADRES kaydedilir (`firebaseapp.com` Google'ın). Kayıttan sonra
     tablodaki SPF sütununda "pass" beklenir — bu bir **çıkarım**:
     `rhytoai.firebaseapp.com`'un SPF kaydı var (`v=spf1
     redirect=_spf.google.com`, DNS 2026-10-24), ama Apple'ın teslim
     kuralı zarf göndericisinin SPF'ine ya da DKIM `d=` eşleşmesine bakar
     ve Firebase postasının Return-Path'i ölçülmedi. Sahibin DNS'te
     yapacağı bir şey yok. Gerçek kanıt Hide My Email'li bir hesaba
     şifre sıfırlama postasının ulaşması.
  Doğrulama: A8'deki silme + iptal denemesi.

**C8 — Ekran görüntüleri ve metaveri (U07, U19) · SEN + Mac**
- 6,9" (1320x2868) iPhone 17 Pro Max simülatöründen; yalnız iOS arayüzü,
  demo hesap, gerçek hesaplanmış haritalar. Ham simülatör yakalamaları
  `store/app-store/raw/` altında (git dışı, `.gitignore`; 2026-10-24,
  demo hesap): 24 kare + 53 sn ham video + temas sayfası. Yüklenecek
  nihai kareler henüz yok (sahip Higgsfield'da düzenleyecek). Ad, alt başlık (30), anahtar kelimeler (100), tanıtım metni;
  `docs/store-launch.md` metinleri Play biçiminde. TestFlight için
  gerekmez.
- Sürüm sayfası: **Copyright** (ör. "2026 Mehmet Hanifi Aslan" — takım
  Individual), **Support URL** `https://rytho.app` (TR) /
  `https://rytho.app/en/` (TR sayfası canlıda 200 ve iletişim bağlantısı
  taşıyor — hazırlık denetimi, ölçüldü 2026-10-23; EN sayfası depoda aynı
  bağlantıyı taşıyor, `web/en/index.html`), açıklama, anahtar kelimeler.
  Support URL gönderim için zorunlu; bu adım §4'te yoktu. (Alanların
  sürüm sayfasında olduğu App Store Connect düzenine dayanır, ekranda
  doğrulanmadı.)

**C9 — App Review Information ve demo hesap (U18, U38, U39, U32) · SEN + belge**
- Sürüm sayfası → **App Review Information**: ad, telefon, e-posta, demo
  hesap (e-posta/parola — SMS gerekmez), notlar. Demo hesap iOS paketiyle
  **kurulumdan geçirilerek** açılır ve Rytho+ verilir; inceleme boyunca
  başka cihazda açık tutulmaz (tek cihaz kilidi, U32).
- Notlar bayat (`docs/store-review-notes.md` son değişiklik 2026-08-30):
  "Raw transcripts are never stored" yanlış, "A single monthly …
  subscription" yanlış (üç kredi paketi var), `<E-POSTA>`/`<PAROLA>` yer
  tutucusu duruyor, silme yolu "Profile → Delete account" (gerçek yol
  Profil → Hesap → Hesabı sil), "already has completed onboarding" yeni
  modelde onay kutusunu inceleyiciden saklar. Yüz okuma, giriş gerekçesi
  ve cihaz kilidi paragrafları yok.

**C10 — Engelleme canlıda (U17) · SEN (onay)** — "Deploy bağımlılıkları"
madde 1 (kurallar + backend birlikte, salt okuma sayımından sonra; B9a'da
yapılmadıysa C'den önce ZORUNLU). Şikâyet görünümü panel kodu işi (U17
Kalan 4, U37).

**C11 — iOS 27 ve iPad uyumluluk kipi · Mac (kuruldu ve açıldı; gezinti sonucu kayıtlı değil)**
- iOS 27: bu Mac'te iOS 26.5 ve 27.0 simülatör çalışma ortamları kurulu.
  2026-10-23 ölçümünde Rytho yalnız iki iOS 26.5 simülatöründeydi; o
  ölçüm sonraki kurulumlardan ÖNCE alındı → 2026-10-24 (ölçüldü, simülatör veri kabından): Rytho'nun simülatör derlemesi 1.20.0 (53) iOS 27.0'da iki simülatöre kuruldu ve açıldı — iPhone 18 Pro (2026-10-24 01:06; tercihlerde şartlar onayı, tanıtım paywall'ı ve bildirim izni bayrakları var, yani kurulum akışı geçildi) ve iPad (A16) (2026-10-23 20:53; yalnız açılış bayrakları, giriş yok). Gezilen ekranların görsel/işlev sonucu kayıtlı değil. Yani
  Xcode 26.6 derlemesi iOS 27.0 simülatörüne kurulup açılabiliyor.
  İnceleme güncel iOS'ta yapılır. Simülatör derlemesi bir iOS 27.0
  simülatörüne kurulup açılış, giriş, kurulum, paywall, çark, sohbet ve
  paylaşım gezilir; Xcode 26.6'nın o çalışma ortamını kullanıp kullanamadığı
  da o anda ölçülür.
- iPad: `TARGETED_DEVICE_FAMILY = 1`, ama inceleyici iPhone uygulamasını
  iPad'de uyumluluk kipinde açabilir (2.4.1). "iPad'de uyumluluk kipinde
  çalışır" (U10) için ölçülen yalnız açılış: iPad (A16, iOS 27.0)
  simülatörüne kuruldu ve açıldı (2026-10-23 20:53, giriş yok); doğru
  çalıştığı ölçülmedi. Bir iPad simülatöründe giriş, kurulum, klavye,
  paylaşım sayfası ve kamera izni akışı gezilir (kamera simülatörde yok).
- Simülatör sonucu cihaz sonucu sayılmaz; A8 satırları geçmeden gönderim
  yapılmaz.

**C12 — İnceleme süresince yapay zeka ayakta · SEN**
- AI Studio → Billing → **Auto-reload** açık (ya da inceleme penceresine
  yetecek bakiye). Yapılmazsa bakiye 0'da her Gemini çağrısı 402 alır ve
  inceleyici okumada ya da sohbette hata görür (2.1); 2026-10-17'de ~2 sa
  kesinti oldu (CLAUDE.md "CANLI KESİNTİ 2"). Durum **ölçülemedi**;
  açıldığına dair kayıt yok. Aynı risk B'deki testçiler için de geçerli.

**C13 — Kayıtlarda açık kalan kod ve metin işleri** — U28 (uygulama içi
gizlilik metni Android çerçeveli), U32 (cihaz kilidi platform başına), U35
(silme sayfası yalnız Play iptalini anlatıyor), U16 (App Store paket
iadesi — RevenueCat'in paket `CANCELLATION`'ı — yok sayılıyor → bedava
kredi yolu; düzeltme + backend deploy, iOS satışı başlamadan önce),
U05'in kalanı (B7). Yayın sonrası parite: U34, U50, U51, U36. U06 burada
açık iş DEĞİL: modelin kendisi sahip kararı ("Sahibin kararları"). Bu
modelin 5.1.2(i) riski de sahip kararıyla kabul edildi (2026-10-24; kutu
adsız kalır, Apple itiraz ederse yeniden konuşulur). *(Düzeltme
2026-10-24: U06 burada "kutu sağlayıcıyı adlandırmıyor, eski hesaplar onay
vermiyor — karar" diye açık karar gibi duruyordu; U16 ve parite kalemleri
yoktu.)*

### Deploy bağımlılıkları ve hosting kilidi

Bu Mac'ten hiçbiri yapılamıyor (`gcloud`, `firebase`, `pwsh` yok — ölçüldü
2026-10-23); hepsi **sahip onayı** ister. Sıranın Windows yarısı CLAUDE.md
§7 "Android 54'e giden sıra"; buradaki madde 1 onun adım 3–4'ünün
kendisidir, ayrı bir iOS deploy'u değil.

1. **Kurallar + backend (birlikte; U17 + AI onay ucu)** — ÖNCE CLAUDE.md §7
   "Android 54'e giden sıra" adım 3'teki üretimde SALT OKUMA sayım
   (`users/X/blocked/Y` olup iki kenarı da `accepted` olan çiftler; sayı
   sıfır değilse karar sahibin). Sonra `firebase deploy --only
   firestore:rules --project rhytoai` ve `infra/deploy-backend.ps1`
   (adım 4). **Backend tek başına öne alınmaz:** yeni backend
   `has_blocked` kapılarıyla (`notify.py:259`, `:342`, `contacts.py:118`)
   o çiftlerde 53 kullanıcısının tepki ve rehber eşleşmesini de keser.
   Hosting kilidinden **bağımsız**.
   - Canlı durum: `POST /api/v1/account/ai-consent` → **404** (ölçüldü
     2026-10-23); canlı backend U17 sunucu kapılarını taşımıyor (çıkarım,
     üst kutu); canlı kurallar ölçülemedi. Deploy'dan sonra kimliksiz aynı
     yoklama 401 dönmeli.
   - **B için önerilir, engel değil (B9a):** B10'dan önce yapılırsa ilk
     iOS kurulumunda onay kaydı ölçülür. Yapılmazsa TestFlight sürer ama
     A8/B'deki onay kaydı satırı "bekliyor" kalır; istemci hatayı yutup
     bekleyen bayrağı yalnız o cihazda tutuyor (`ai_consent.dart:82-88`),
     yani o arada kurulum yapıp uygulamayı silen test hesaplarının
     kanıtı kalıcı kaybolur — bunu sahip kabul eder.
   - **C için zorunlu (C10):** yapılmazsa uygulama içi engelleme sözü
     canlıda doğru değil (1.2) ve inceleme hesabının onay kanıtı yazılmaz.
2. **Hosting** — `firebase deploy --only hosting --project rhytoai`. Bugün
   kilitli (üst kutu): AASA (cihaz testi için hemen gerekli) ve yeni
   gizlilik metni (inceleme anında gerekli) **aynı deploy'da**. Canlı =
   `e8cc253`; `e8cc253` → HEAD `web/` farkı yedi dosya (AASA,
   `legal/gizlilik.html`, `en/legal/privacy.html`, `r/index.html`,
   `index.html` ×2, `rytho-admin/sozluk.js`). Yapılmazsa Universal Link
   iPhone'da uygulamayı açmaz (Safari'ye düşer; TestFlight'ta da) ve
   gizlilik URL'si iOS paketinin davranışını anlatmaz. Deploy sonrası Apple
   CDN adresi yeniden okunur, `292WJ9TP74.ai.rytho` görülmeden cihazda
   bağlantı denenmez; cihaz AASA'yı kurulumda çektiği için uygulama silinip
   yeniden kurulur.

*(Düzeltme 2026-10-24: bu liste üç maddeydi — "1. Backend … B'den önce",
"2. Firestore kuralları, ardından madde 1", "3. Hosting". Backend tek başına
öne alınıyor, CLAUDE.md §7 adım 3'teki sayım atlanıyordu; üstelik belge
backend deploy'unu bir yerde B'nin engeli, bir yerde "kurallardan sonra",
bir yerde Öneri A + C'de hiç yapılmayan bir adım sayıyordu. Üçü tek dile
çekildi: kurallar + backend birlikte, sayımdan sonra; B için önerilir, C
için zorunlu.)*

**Hosting kilidinin seçenekleri** (aşama harfleriyle karıştırma; karar
sahibin):
- **Seçenek A — önce Android 54.** CLAUDE.md §7 sırasının adım 1–6'sı
  Windows'ta; hosting 54'ün yayın günü; iOS incelemeye ondan sonra girer.
  Hukuk metni değişmez, özel ağaç gerekmez; bedeli iOS incelemesinin
  Android'i beklemesi.
- **Seçenek B — yalnız AASA (+ `/r/`).** Hosting `web/`'i tümden
  değiştirdiği için tek dosya yayınlanamaz: `legal/gizlilik.html` ve
  `en/legal/privacy.html` `e8cc253` hâlinde tutulmuş geçici bir ağaçtan
  deploy edilir. Universal Link cihaz testini ve TestFlight'taki
  bağlantıları hemen açar, gizlilik beklemesini bozmaz; ayrı bir dağıtım
  adımı ve sahip onayı ister.
- **Seçenek C — iOS iç TestFlight'ta bekler.** İç grupta Beta App Review
  yok, gizlilik URL'si incelenmez (iç grupta inceleme olmamasından
  çıkarım; ölçülmedi — dış grup açılırsa geçerli değil, B10); hosting 54
  ile çıkar, inceleme ondan sonra. Bu sürede Universal Link ölçülemez (B
  ile birleştirilebilir).
- **Seçenek D — metni platformdan bağımsız yaz.** Gizlilik metni "şu
  sürümden itibaren" (iOS ve Android 54) diye yeniden yazılıp hemen deploy
  edilir. Hukuk metni değişikliği: CLAUDE.md §7 kuralı gereği önce sahibe
  sorulur; 53'ün yeni kullanıcıları için beyan riski sahibin
  değerlendirmesi.
- **Öneri: A + C.** Cihaz testi ve iç TestFlight Android 54'ü beklemeden
  ilerler: Universal Link satırı "bekliyor" kalır; onay kaydı satırı da,
  kurallar + backend (madde 1 — CLAUDE.md §7 adım 3–4, Windows sırasında
  54'ü yüklemeden önce) B10'dan önce yapılmadıysa "bekliyor" kalır.
  İnceleme gönderimi hosting'den sonra yapılır; ne hukuk metni ne özel
  deploy ağacı gerekir. Universal Link'in TestFlight'ta ölçülmesi
  istenirse B eklenir. **Karar sahibin.**

### Sahibin kararları (üç aşamanın içinden)

| Karar | Adım | Öneri / not |
|---|---|---|
| Hosting kilidi | yukarıda | Seçenek A + C |
| Derleme numarası | B8 | Öneri (karar verilmedi): iOS en az 54; pubspec Android 54 ile aynı commit'te. `infra/build-ipa.sh` öneriyi bugün kapı olarak kodluyor |
| EULA | C5 | Apple standart EULA + açıklamada Koşullar bağlantısı |
| Fiyat noktası | B5, C6 | Apple fiyat noktaları alıcıya görünen, vergi dahil tutardır; Play'in "Console'a KDV hariç gir" kuralı (CLAUDE.md §6) Apple'a taşınamaz — Apple belgesine dayanır, ölçülmedi. Play'de alıcı ₺239,99 görüyor (CLAUDE.md, `priceInPurchasedCurrency 239.99`); eşit görünmesi için ona en yakın Apple noktası. `docs/maliyet-calismasi.md`'ye Apple satırı (net farklı) |
| Small Business Program | C6 | developer.apple.com → App Store Small Business Program → Enroll (bireysel hesap). %15 oranı başvuru ister — Apple belgesi, ölçülmedi. Belgelerde hiç geçmiyordu (ölçüldü) |
| Aile Paylaşımı | B5 | Abonelik ürünündeki Family Sharing anahtarı. Apple belgesine göre bir kez açılınca kapatılamaz (ölçülmedi); tek cihaz kilidiyle (U32) birlikte düşünülür. Belgelerde karar yok (ölçüldü: yalnız Ask to Buy bağlamında geçiyor) |
| Satıcı adı | B4 | Takım türü Individual (ölçüldü) — mağazada satıcı olarak kişi adı görünür; Apple politikasından çıkarım, mağaza sayfasında ölçülmedi |
| U06'nın kalan riski | C13 | **Sahip kararı verildi** (CLAUDE.md §7, 2026-10-22/23): kutu sağlayıcı adını bilerek taşımaz, 53'ten gelen hesaplara bir şey sorulmaz, politika geçiş cümlesiyle anlatır. Bu modelin bilinen 5.1.2(i) riski (Apple sağlayıcıyı adıyla anan ekran bekleyebilir; Android ≤ 53'te kurulumu bitmiş hesap iOS'ta kutuyu görmez): **Sahip kararı 2026-10-24: risk kabul edildi** — kutu adsız kalır; Apple itiraz ederse o gün yeniden konuşulur. Kutuya ad eklemek modeli değiştirmektir, yalnız sahip yeniden açabilir. *(Düzeltme 2026-10-24: burada "kutuya sağlayıcı adı mı, yoksa riskin kayda yazılması mı; eski hesaplar" diye açık karar gibi duruyordu.)* |
| Yaş / UGC | C4 | 13+, Messaging and Chat = Evet |
| Mac / Vision Pro erişimi | C6 | Öneri: ikisi de kapatılır — Apple'a göre Mac'te App Attest yok (`isSupported` false, iOS-on-Mac dahil), zorlama açıkken Mac kullanıcısı giriş yapamaz; açık kalırsa özel DeviceCheck yedeği gerekir (2026-10-24) |
| Apple anahtarları | A5, C7 | APNs: belgeyle uyumlu yol ortama özel iki anahtar; ekranda "Sandbox & Production" çıkarsa tek anahtar da seçenek. Apple ile Giriş anahtarı APNs'ten ayrı (öneri). Services ID adı (öneri `ai.rytho.signin`) (2026-10-24) |
| Şikâyete 24 saat sözü | C10 | U18: söz sahibin kararı. Şikâyetler bugün yalnız Firebase konsolundan okunuyor (panelde görünüm yok, U37); sahip o sürede okuyabileceğine karar verirse notlara ve Koşullar'a (TR+EN) yazılır. *(Düzeltme 2026-10-24: burada "panelde görünüm yokken verilmez" yazıyordu — kayıtlarda böyle bir kural yok, karar sahibin.)* |
| `/openapi.json` ve `/docs` herkese açık | — | Üretimde kimliksiz 200, admin uçları dahil 89 yol (hazırlık denetimi, ölçüldü 2026-10-23). iOS'u engellemiyor. Kapatılırsa canlı rota ölçümü (bu belgedeki `/ai-consent` 404 gibi) `gcloud run revisions describe` ile yapılır. Karar sahibin |

### Açık işler (ölçüldü 2026-10-23; bu turdan önce ne §4'te ne ilgili kayıtta adım olarak vardı)

- Dış TestFlight grubu için Test Information ve Beta App Review bilgileri
  — hiçbir belgede yok (B10; U21'e not düşüldü).
- App Store Connect "New App" formu ve App Information alanları —
  belgelerde yoktu (B4; U02'ye not).
- iOS 27 ve iPad uyumluluk kipi gezintisi — iki simülatöre kuruldu ve
  açıldı (2026-10-23/24), gezinti sonucu kayıtlı değil (C11; U21 ve U10'a
  not).
- Release/Profile cihaz testi için güvenli anahtar yolu yok: "yalnız iOS
  anahtarını boşalt" yetmiyor (A7). Kod çaresi U05'in Düzeltme 3'ünde; bu
  bulgu U05 kaydına bu turda işlenmedi (kayıt ayrı bir işin konusu).
  → **Kapandı (kodda; buraya 2026-10-24'te işlendi):** U05 kod ağı
  `09bbe23` — `test_` anahtarlı Release/Profile derlemesi `configure`
  etmez, satın alma "kullanılamıyor" der; kodda doğrulandı, cihazda
  ölçülmedi. U05 kaydına Ek olarak işlendi.
- Kayıtlı cihaz ve dağıtım sertifikası yokken arşiv alınamaz (B9; U21'e
  not).
- Derleme numarası çakışması (B8; U29'a not).
- Dört eklenti Swift Package Manager desteklemiyor: `flutter_contacts`,
  `google_mlkit_commons`, `google_mlkit_face_detection`, `tflite_flutter`
  (Release derleme çıktısı: "This will become an error in a future version
  of Flutter"). Bugün engel değil; Flutter yükseltmesinden önce bakılır
  (U55'e not).
- ~~Crashlytics sembol fazı ölçüm derlemelerinde de dışa yükleme
  yapıyor~~ → kapandı (`09bbe23`): faz imzasız derlemede atlanıyor,
  imzalı Release/arşiv yine yükler; bekçi `test_ios_config.py` (U26).

---

**Ayrıntı ve tarihçe — 4.1…4.10.** Sıra artık yukarıdaki aşamalarda;
buradaki "SEN" etiketleri aşama adımlarına işaret eder.

### 4.1 — Apple Developer Program üyeliği · **SEN**
Yıllık ücretli. Bunsuz ne imzalama ne TestFlight ne App Store Connect var.
Üyelikten çıkan **Team ID** (10 karakter) üç yerde birden lazım: Xcode
imzalama, `apple-app-site-association`, ve entitlements profili.

**Durum (2026-10-22):** Team ID **`292WJ9TP74`** depoda (pbxproj + AASA,
`c3dca0e`). Üyelik **ücretli ve etkin** (sahip teyidi, 2026-10-22) —
Associated Domains (Universal Link) ücretsiz kişisel takımda açılamazdı.
**Ek (ölçüldü 2026-10-23):** Xcode'un kayıtlı takımı `292WJ9TP74`,
`teamType = Individual`, `isFreeProvisioningTeam = 0`; anahtar zincirindeki
geliştirme sertifikasının OU'su aynı Team ID. Bu takımın varlığını ve
ücretsiz olmadığını gösterir; üyeliğin bitiş tarihi portaldan okunmadı.
Bireysel hesapta mağazada satıcı adı olarak kişi adı görünür (Apple
politikasından çıkarım, ölçülmedi — §4 "Sahibin kararları").

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

**Düzeltme (ölçüldü 2026-10-23) — yukarıdaki "Kalan" ve "0" bayat:**
Xcode → Settings → Accounts'ta takım hesabı **ekli** (ücretli,
`Individual`) ve anahtar zincirinde **1** geçerli `Apple Development`
kimliği var (OU `292WJ9TP74`, 2026-10-22 07:18 GMT → 2027-10-22). "0"
ölçümü büyük olasılıkla sertifika oluşmadan önce alındı; ölçüm anı kayıtlı
olmadığı için kesin değil (üst kutu). Hâlâ eksik: **Apple
Distribution** sertifikası (`security find-certificate -a -c "Apple
Distribution"` boş), **provizyon profili** (iki profil dizini de yok),
takımda **kayıtlı cihaz** (ölçülemedi; bağlı cihaz yok). Kalan adımlar
§4 A3 (cihaz + profil) ve B9 (dağıtım imzası + arşiv).

### 4.5 — Yetenekler (Capabilities) · **SEN (Xcode'da)**
Apple Developer portalında App ID üzerinde de **açık olmalı**, yalnız
entitlements dosyası yetmez:
- **Sign in with Apple** (App Store Guideline 4.8 gereği zorunlu)
- **Push Notifications**
- **Associated Domains**
- **App Attest** — *eklendi 2026-10-23.* Liste bu güne kadar üç yetenek
  sayıyordu, oysa iki entitlements dosyası da
  `com.apple.developer.devicecheck.appattest-environment = production`
  taşıyor (`54130b9`, U42; bugün `Runner.entitlements:85-86`, ölçüldü
  2026-10-24). App ID'de kapalıysa profil bu yetkiyi taşımaz ve imza
  düşer. Bu yeteneğe dayanan şey App Attest yetkisini taşıyan paketin
  İMZASI ve geliştirme imzalı cihaz denemesi (§4 A2, B2); TestFlight/App
  Store dağıtımında Apple yetkinin değerini yok sayıp production
  kullanır. *(Düzeltme 2026-10-24: burada "Release/TestFlight'ın App Check
  jetonu da buna dayanıyor" yazıyordu.)*

Portal durumu (App ID var mı, dört yetenek açık mı) bu Mac'ten
**ölçülemedi** (2026-10-23).

Depo tarafı hazır: `Runner.entitlements` (Debug/Profile) ve
`RunnerRelease.entitlements` (Release) ikisi de yazıldı ve `pbxproj`
Release bloğu ikincisine bakıyor.

⚠️ İkisi **yalnız `aps-environment` değerinde** farklı: `development` ve
`production`. Dosyalardan biri değişirse **diğeri de aynı şekilde
değişmeli** (`test_ios_config.py` bunu şart koşuyor). Bu paragrafın eski
gerekçesi — "tek dosya kullanılıp `development` kalsaydı üretim paketi
**sandbox** APNs jetonu alır, sunucu üretim APNs'ine gönderir ve bildirim
hiçbir yere düşmezdi: TestFlight'ta çalışır, mağazada ölür" — **yanlış**
(aşağıdaki not).

⚠️ **Bu gerekçe henüz ÖLÇÜLMEDİ (not 2026-10-23).** Apple belgesi
`aps-environment` değerinin Xcode tarafından profile göre yazıldığını
söylüyor ve dışa aktarma dağıtım profiliyle yeniden imzalıyor; doğruysa
yukarıdaki "sandbox jetonu alır" gerekçesi yanlış olabilir. Ayrıca
Release yapılandırması `production` isterken otomatik imza arşivi önce
geliştirme profiliyle imzalıyor — ilk imzalı Release ya da arşiv
"doesn't match the entitlements file's value for the aps-environment
entitlement" ile düşebilir. İkisi de ilk imzalı Release'te ölçülür
(§4 B9); o zamana dek dosyalar olduğu gibi kalır.
→ **Gerekçe yarısı belgeyle cevaplandı (2026-10-24):** Apple'ın
`aps-environment` belgesine göre dağıtım profiliyle imzalanan paket —
TestFlight DAHİL — production kullanır; TestFlight ile mağaza aynı
ortamda, "biri çalışır öteki ölür" oluşamaz. FCM de ortamı yetki
dosyasından değil (olağan yolda) SDK'nın gömülü profilden okuyup jetonla
bildirdiği sandbox bayrağından seçiyor (pod kaynağı: `FIRMessagingUtilities.m`
App Store ve TestFlight'ı production sayıyor; `FIRMessagingTokenManager.m`).
İstisna: APNs jetonu FIRMessaging hazır olmadan gelirse eklentinin derleme
zamanı DEBUG etiketi geçer — Profile'da push testi güvenilmez.
Ölçülmemiş kalan yalnız imza yarısı: iki dosyanın gerçekten gerekip
gerekmediği ve Release'in geliştirme imzasıyla düşüp düşmediği (§4 B9).

### 4.6 — APNs anahtarı · **SEN**
Apple Developer → Keys → yeni **APNs Auth Key** (.p8) oluştur, Firebase
Console → Project Settings → Cloud Messaging → iOS bölümüne yükle
(Key ID + Team ID ile birlikte). Bunsuz FCM iOS'a bildirim gönderemez.
Tam yol ve sıra: §4 A5. Durum 2026-10-23'te bu Mac'ten **ölçülemedi**.
**Ek (2026-10-24):** "tek anahtar, tek alan" değil — Apple ekip
anahtarlarını Sandbox ya da Production ile sınırlıyor (ortam başına en
çok 2), Firebase de development ve production anahtarını ayrı yerlere
alıyor (en az biri şart; eksik ortam `THIRD_PARTY_AUTH_ERROR` verir).
Ayrıntı §4 A5.

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

**Ek (2026-10-23):** Bu madde Paid Apps sözleşmesini, abonelik grubunu,
In-App Purchase Key'i, ürünlerin ilk sürümle gönderilmesini ve EULA'yı
anmıyordu (U02). Sıralı ve tam yollu hâli §4 B3, B5, B6, C2, C5. `test_`
anahtarının Release'te açılışta BİLEREK çöktüğü ölçüldü (anahtar
derlenmiş pakette, RevenueCat `Configuration.swift:471-495`) — §4 B6.
2026-10-24: U05 kod ağı (`09bbe23`) sonrası uygulama bu anahtarla
Release/Profile'da `configure` etmiyor; yayın kapısı `infra/build-ipa.sh`
(§4 B7).

### 4.8 — `apple-app-site-association` · ✅ **depoda** (2026-09-27) · **yayın bekliyor**
`web/.well-known/apple-app-site-association` içinde
`"appID": "292WJ9TP74.ai.rytho"` — gerçek Team ID (Membership details'ten
sahip doğruladı; kayıt e-postasındaki Enrollment ID aynı biçimde ama
FARKLI bir şey). Aynı değer pbxproj'de `DEVELOPMENT_TEAM`; ikisinin
ayrışması `backend/tests/test_ios_config.py`'de bekçili. **Kalan:**
`firebase deploy --only hosting --project rhytoai` — sahibe SORULUR; bu
Mac'te `firebase` CLI yok. Yayın olmadan davet bağlantıları iOS'ta
uygulamayı açmaz, tarayıcıya düşer.

**Canlı (ölçüldü 2026-10-23, kimliksiz GET):** `rytho.app`,
`www.rytho.app` ve `rhytoai.web.app` üçü de 200, `application/json`,
yönlendirmesiz, 141 bayt — biçim doğru, içerik bayat:
`{"appID": "TEAMID.ai.rytho", "paths": ["/i/*"]}`. Apple'ın önbelleği
(`app-site-association.cdn-apple.com/a/v1/<alan>`) üç alanda da aynı
gövdeyi veriyor (`X-Cache: hit-stale`). Depodaki `292WJ9TP74` ve `/r/*`
(`c3dca0e`, `31ee208`) hiç yayınlanmadı. Yayın hosting kilidine bağlı —
seçenekler §4 "Deploy bağımlılıkları ve hosting kilidi".

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

**Ek (2026-10-23):** Kaydın açılıp açılmadığı ölçülemedi (App Store
Connect'e giriş yok); yerelde `dart_defines.local.json`'da
`APPSTORE_APP_ID` anahtarı yok (ölçüldü). *(Düzeltme 2026-10-24: burada
"Kayıt hâlâ açılmadı" yazıyordu; tek kanıt yerel anahtarın yokluğuydu.)*
"Kayıt aç" tek cümlesinin ardındaki form (platform, ad, birincil dil, bundle, SKU, kategori, içerik
hakları) §4 B4'te; kayıt cihaz gerektirmez, yalnız App ID'nin portalda
kayıtlı olmasını ister (A2). Canlı zorunlu güncelleme eşiği bugün 0
(`GET /api/v1/config/app` → `min_build: 0`, ölçüldü 2026-10-23), yani
kimlik yokken iOS paketi kilitlenmez; eşik yükseltilirse düğmesiz ekran
riski U29.

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
   Aynı dosyada masaüstü/iPad metni (`diger` / `digerNot`, TR ve EN:
   "iOS sürümü hazırlanıyor", "yalnız Android kurulumlarında sayılıyor")
   yayından sonra da masaüstü ve iPad ziyaretçisine gösterilir —
   güncellenir. `/i/` davet sayfasına App Store düğmesi (U34; bugün yalnız
   Play). Deploy'dan sonra Safari'de `rytho.app/r/<KOD>` → "Uygulamada
   aç" testi (aşağıdaki cihaz listesinin 2. maddesi). *(Ek 2026-10-24:
   bu üçü listede yoktu.)*
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
0. **Test kodu GERÇEK olmalı** (koddan doğrulandı 2026-10-24). Uydurma
   kod (`TESTKOD`) sunucuda 404 `not_found` alır ve atıf yazılmaz; daha
   kötüsü istemci 401 DIŞINDAKİ her 4xx'i — 404, kendi kodunun 403'ü,
   ikinci kodun 409'u, pasif/süresi geçmiş/dolmuş kodun 400'ü — VE
   başarıyı **kurulum başına** kalıcı sayıp bayrağı yakar
   (`partner_referrer.dart` `_gonder`); aynı kurulumda sonraki deneme
   sessizce atlanır. Kod: `rytho.app/rytho-admin` → Ortaklar → Yeni ortak
   ("Giriş hesabı" uid'i iPhone'da KULLANILMAYACAK başka bir hesabın) →
   ortağın detay sayfası → Ortak bağlantısı → Kod üret ("Kullanım limiti"
   planlanan deneme sayısı, "Son gün" yakın bir tarih — panelde kodu
   kapatan düğme yok, ortağı pasifleştirmek kodu durdurmuyor). Üretim
   veritabanına yazar; ayrı test ortağı mı gerçek ortak mı, karar sahibin
   (gerçek ortağın "bağlantıyı kullanan" sayacı kalıcı artar). **Kural:
   her yeni atıf denemesi = temiz kurulum (uygulamayı sil, yeniden kur) +
   daha önce kod kullanmamış yeni hesap (ortağın kendisi değil).**
   Oturumsuz dokunuş denenecekse başarılı atıftan ÖNCE yapılır (401
   bayrağı yakmaz; başarı yakar).
1. Notlar'a `https://rytho.app/r/<GERÇEK_KOD>` yaz, dokun → uygulama
   açılır, `users/{uid}/private/attribution` yazılır (oturum açıkken).
   ⚠️ Debug derlemede yalnız uygulama `flutter run` ile AÇIKKEN dene:
   uygulama kapalıyken bağlantıyla açılış Debug'da çalışmaz (app_links
   7.2.1 Debug'da kendini kaydetmiyor; Flutter iOS JIT). Kapalı uygulama
   yolu Profile/TestFlight'ta sınanır. Notlar'da uzun basınca "Safari'de
   aç"ı SEÇME — o alan adı için varsayılan Safari olur.
   *(Düzeltme 2026-10-24: bu madde ve 2. madde `TESTKOD` ile test
   öneriyordu — yukarıdaki 0.)*
2. Safari'de `rytho.app/r/<GERÇEK_KOD>` → "Uygulamada aç" (karşı host) →
   uygulama açılır mı? ⚠️ **Ancak YAYIN GÜNÜ yapılabilir:** düğme
   `APPSTORE_ID` boşken gizli (`web/r/index.html` iPhone dalı) ve
   yukarıdaki yayın günü listesi kimliği App Store yayınından önce
   yazdırmıyor — iki kural bu testi "iPhone gelince" değil yayın günü
   yapılabilir kılıyor.
3. Instagram / WhatsApp uygulama içi tarayıcısından dokunuş — Universal
   Link'i açmayabilirler; ölçülmeden hiçbir şey söylenmez.
4. Apple'ın AASA önbelleği:
   `https://app-site-association.cdn-apple.com/a/v1/rytho.app` deploy'dan
   sonra güncellenmeyebilir; önce oradan oku. Apple'a göre CDN dosyayı
   "24 saat içinde" çeker ve elle tazeleme yolu yok (TN3155); cihaz AASA'yı
   kurulumda indirir, sonra yaklaşık haftada bir bakar — yeni gövde
   CDN'de görülünce uygulama **silinip yeniden kurulur**. CDN'i atlamanın
   resmi yolu TN3155'in geliştirici kipi: `applinks:rytho.app?mode=developer`
   — yalnız geliştirme imzalı pakette ve cihazda Settings → Developer →
   Associated Domains Development açıkken; cihaz AASA'yı doğrudan siteden
   çeker. Hosting deploy'unu gereksiz kılmaz, App Store gönderiminden
   ÖNCE kaldırılır (çıkarım: Apple'ın Associated Domains belgesi "yalnız
   geliştirme profiliyle imzalı uygulama geliştirici kipini kullanabilir"
   diyor; kip adı ve kaldırma kuralı TN3155'te yazmıyor). Depoda bedeli
   var ve YEŞİL kalan yol yok: sonek yalnız Debug/Profile dosyasına
   eklenirse `test_ios_config.py` (iki dosya `aps-environment` dışında
   ayrışmış), iki dosyaya birden eklenirse `test_web_seo.py` (`/r/`
   sayfasının "Uygulamada aç" hedefi RunnerRelease'in applinks listesini
   okuyor) kızarır — deneme bilinçli bir kırmızıyla yapılır. *(Ek
   2026-10-24.)*

**Canlı (ölçüldü 2026-10-23):** `/r/` sayfası `e8cc253` sürümünde (11.587
bayt; depodaki 14.531) — iPhone'da "iOS sürümü hazırlanıyor" diyor,
"Uygulamada aç" düğmesi yok (canlıda 0, depoda 5 geçiş). AASA'da `/r/*`
yok (4.8). Yani 4.10'un hiçbir parçası canlıda değil; cihaz ölçümü
hosting kilidini bekliyor (§4).

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
  Birleşmiş dalda yeniden ölçüldü: imzasız **Release** cihaz derlemesi
  `ba6108b`'de geçti (2026-10-23; ayrıntı üst kutu).
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
  Apple araçlarına bağlı. Windows'tan iOS paketi üretilemez. Mağaza paketi
  düz komutla değil `infra/build-ipa.sh` ile çıkar (§4 B7, CLAUDE.md §4).
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
  Gerçek cihazda da aynı kural (not 2026-10-23): Debug derlemesi her
  kurulumda yeni bir debug jetonu basar ve o jeton Firebase'e eklenmeden
  giriş/Firestore/Storage reddedilir; simülatörün jetonu cihaza geçmez
  (§4 A6). *(2026-10-24: `APP_CHECK_DEBUG_TOKEN` define'ı doluysa jeton
  sabittir ve aynı define'la derlenen her Debug kurulumuna — simülatör ya
  da cihaz — aynı jeton gider; simülatörde ölçüldü, cihazda ölçülmedi.)*
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

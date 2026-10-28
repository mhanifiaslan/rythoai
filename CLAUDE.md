# RythoAI — Claude için proje notları

Bu dosya her oturumda otomatik okunur. Amacı: **makineler arasında taşınmayan
bilgiyi** taşımak. Buradaki her madde ya ölçülerek bulundu ya da bir kez
canlıda zarar verdi; hiçbiri teorik değil.

Ürün: doğum haritanı bilen ve gökyüzünü her gün takip eden kişisel AI astrolog.
Flutter mobil + FastAPI backend (Cloud Run) + bağımlılıksız vanilla-JS admin
panel. Firebase projesi **`rhytoai`**, paket adı **`ai.rytho`**.

---

## 1. Yazım dili ve yorum doktrini

Kod içindeki **yorumlar, değişken/fonksiyon adları ve test adları TÜRKÇE**
yazılır. Kullanıcıya görünen metinler `l10n` üzerinden TR+EN.

Yorum **NE yaptığını değil NEDEN öyle olduğunu** anlatır. "Bu döngü listeyi
gezer" değersizdir; "bu kapı şu yüzden var, olmasaydı şu sessizce bozulurdu"
değerlidir. Bir yorumun gerekçesi yanlışsa yorum **kusurdur** — bu depoda iki
kez yanlış gerekçe düzeltildi.

**Ölçülmeyen söylenmez.** Ürünün çekirdek ilkesi: hesaplanmamış bir şey
kullanıcıya söylenmez, beyan edilmez, metne girmez. Tersi de geçerli —
**ölçülen, yanlış adla sunulmaz**.

---

## 2. Ortam (makineye bağlı — kendi makinende doğrula)

| Şey | Gereklilik |
|---|---|
| Python | **3.11 ŞART.** 3.12'de `pyswisseph` kurulmuyor. venv: `backend/.venv` |
| Flutter | `3.44.7 stable` / Dart `3.12.2`; pubspec `sdk: ^3.12.0` |
| JDK | 17 (Android Gradle) |
| Android SDK | **cmdline-tools kurulu olmalı** — eksikken AAB derlemesi yanıltıcı bir "strip" hatası veriyor |
| gcloud / firebase | her komutta proje bayrağı: `--project rhytoai` |

`gcloud`'un varsayılan projesi başka bir projeye düşerse elle çalıştırdığın
komutlar **sessizce yanlış projeye** gider. Bu bir kez yanlış bir "panelde hiç
admin yok" blocker'ı ürettirdi.

Betikler PowerShell (`.ps1`). ⚠️ **Windows'ta `pwsh` YOK** — bu makinede
kurulu olan Windows PowerShell **5.1** (`powershell.exe`) ve `pwsh`
PowerShell 7'nin komutu. Betik doğrudan çağrılır:
`.\infra\deploy-backend.ps1`. `pwsh infra/...` yazmak
`CommandNotFoundException` verir — bu bir kez gerçekten verdi, çünkü
`pwsh` aşağıdaki macOS satırından Windows'a taşındı. Çalıştırma politikası
`CurrentUser = RemoteSigned`, depo dosyaları sorunsuz koşuyor.

macOS'ta `pwsh` gerekir: `brew install --cask powershell`.

---

## 3. Git'in TAŞIMADIĞI dosyalar

Yeni bir makineye geçerken bunlar elle kopyalanır. Biri eksikken derleme
**sessizce** bozuk çıkar:

| Dosya | Eksikse ne olur |
|---|---|
| `apps/mobile/dart_defines.local.json` | Paket RevenueCat anahtarsız çıkar; cihazda **tüm satın almalar** "kullanılamıyor" der. Derleme BAŞARILI görünür. iOS Debug'da sabit App Check jetonu (`APP_CHECK_DEBUG_TOKEN`, 2026-10-24) da onunla gider: örnekten yeniden kurulursa her kurulumda yeni jeton üretilir ve giriş "Bir şeyler ters gitti" ile düşer (§7). |
| `apps/mobile/android/key.properties` | Yayın imzası kurulmaz. İçindeki `storeFile` mutlak yol — makineye göre düzeltilir. |
| Keystore (`rytho-upload.jks`) | **Yeri doldurulamaz.** Kaybolursa uygulama bir daha güncellenemez. |
| `backend/.env` | Yerel backend anahtarları. |

`google-services.json` git'te **var**. Segmentasyon modeli (16 MB) git'te yok
ama tek komutla iner (`apps/mobile/scripts/fetch_models.ps1`); **o dosya
yokken `flutter test` hiç başlamaz** ("Failed to build asset bundle").

---

## 4. Asla atlanmayan kapılar

**AAB ASLA düz `flutter build appbundle` ile üretilmez.** Her zaman
`infra/build-aab.ps1`. Betikte beş kapı var ve hepsi sessiz hatalar için:
RevenueCat anahtarı gerçekten pakette mi, `test_` önekli anahtar değil mi,
imza debug'a düşmüş mü, kullanılmayan izin geri gelmiş mi (mağaza listesinde
"Mikrofon" yazardı ve gizlilik metnimizi yalanlardı), kamera zorunlu mu.
(2026-10-10'dan beri altıncısı da var: R8 optimizasyonu, AAB'nin
`r8.json`'undan — §6; betiğin kaynağında okundu 2026-10-24.)

Bir kez 1.5.0+17 düz komutla üretildi: derleme başarılı, testler yeşil, imza
doğru — kusur ancak mağaza ekranında görüldü.

**IPA ASLA düz `flutter build ipa` ile değil, `infra/build-ipa.sh` ile**
(macOS, bash; U05, `09bbe23`). İmzasız ölçüm için `--yalniz-denetle
<.app>` (imza kapıları ATLANDI der, GEÇTİ değil); `--yalniz-denetle <.ipa>`
ve tam kip dağıtım imzası ister, imzasız IPA'da imza kapıları KALDI, çıkış 1.
Derlemesiz ön kontrol için `--kuru`. Aynı sınıfın iOS hâli
ölçüldü (2026-10-23): `test_` önekli RevenueCat anahtarıyla imzasız Release
derlemesi hiçbir engele takılmadan "başarılı" çıktı. Betik hiçbir şeyi
yüklemez. Xcode'un
kendi Archive yolu kapılardan geçmez — o yol seçilirse arşivden ÖNCE
`--kuru`, dışa aktarılan IPA'ya `--yalniz-denetle` koşulur: ikincisi yalnız
paket kapılarıdır, Xcode sürümü / `APPSTORE_APP_ID` / takım ↔ AASA ön
kapılarını koşmaz. Ayrıntı `docs/mac-devir.md` §4 B7.

**Dağıtım:** backend `infra/deploy-backend.ps1`, hosting
`firebase deploy --only hosting --project rhytoai`.

---

## 5. Tekrar eden tuzaklar

**Testler üretime yazabiliyordu.** `conftest.py`'de üç autouse pin var
(`kapi_hermetik`, `depolama_hermetik`, `firestore_hermetik`). Sebep ölçüldü:
üretimde `users/dev-user` dokümanı bulundu, içinde o gün yazılmış bir
`termsConsent` vardı — `RYTHO_DEV_MODE` varsayılanı `"1"` ve makinede ADC var.
Pin sonrası takım süresi **214 sn → 83 sn** düştü.
**Kural: dış dünyaya çıkan her yeni istemci için `conftest`'e ayrı pin.**

**Türkçe metin eşleştirme.** `str.lower()` Türkçe bilmez (`"İ".lower()` →
`"i" + U+0307`). Alt dizi eşleşmesi yanlış pozitif üretir: "il**iş**kimde"
içinde "iş" var; ham `feedback` araması `HapticFeedback`'e takılıyor; ham
`['reply']` sohbet cevabına takılıyor. Eşleşmeyi **kelime başına ya da dize
literaline** bağla. ⚠️ Yasak-alan KAPISI bir tur boyunca tam bunu yaptı
(S1, 2026-10-10): "**hisse**diyorum" → finans reddi, "**altın**da" →
finans, "mutlu **olurum**" → ölüm, "**sick of** my job" → sağlık,
"kendi**mi**" → soru eki. Engellenen tur kaydedilmediği için korpusta
görünmedi; yalnız ekranda ve probe ile ölçüldü. Kural: kapı kalıpları
`\b` + KAPALI ek listesi, bir de doğrudan-kalıp tuzak-kelime bekçisi
(`test_kaliplar_tuzak_kelimelere_takilmaz`).

**Bir şeyin YOKLUĞUNU arayan bekçi, onu ANLATAN yorumu görmemeli.** İki kez
patladı: build kapısı kendi manifest yorumuna takıldı, davet sayfası testi
kendi HTML yorumuna. Eşleşmeden **önce yorumları at**.

**PowerShell kaynak dosyaya DOKUNMAZ.** Windows'ta ANSI kod sayfası cp1254;
`Get-Content`/`Set-Content` UTF-8 kaynağı bozuyor (`GÖKYÜZÜ` → `GÃ–KYÃœZÃœ`)
ve `flutter analyze` bunu fark etmiyor. Satır düzenlemesi için Python
(`io.open(..., encoding='utf-8')`).

**Git Bash heredoc'u ters bölü yiyor.** Sınırlayıcı tırnaklı olsa bile
(`cat > dosya <<'SON'`) bir kaçış katmanı düşüyor: kaynakta iki ters bölü
yazsan diske bir tane iniyor. Bu oturumda **altı kez** oldu ve en sinsisi
şuydu: bir Windows yolundaki ters bölü + `a` ikilisi ASCII **BEL** (0x07)
karakterine dönüştü ve dosyaya **görünmez bir kontrol baytı** yazdı —
`Read` aracı bile onu göstermedi, yalnız `repr()` yakaladı. Bir başkası
`build` + ters bölü + `app` yolunu `buildpp` yaptı, bir başkası Python
docstring'inde geçersiz-kaçış uyarısı üretti. Altıncısı tam da **bu
paragrafı yazarken** oldu.

Kural: **ters bölü içeren dosyayı heredoc ile yazma.** Write/Edit aracını
kullan (dizeyi olduğu gibi geçirir) ya da Python'da `chr(92)` ile kur. Yol
örneği gereken docstring'i ham dize yap (`r` önekli üç tırnak).

**`core.autocrlf=true`.** Dosyaların çoğu CRLF. İçeriği LF yazarsan tek
satırlık düzeltme 1000+ satırlık hayalet diff'e döner. Yazarken dosyanın
kendi satır sonunu koru.

**"İŞARET İLERİ GİTTİ" ≠ "YENİ DÖNEM BAŞLADI".** Aylık hak tazelemesi üç
yerde (`wallet.py` `reset_allowance` + iki tembel tazeleme) dönem işaretinin
ilerlemesini yeni dönem sanıp hakkı **üzerine yazıyordu**. `_ACTIVATING_EVENTS`
yalnız dönem başlarında gelmiyor: `SUBSCRIPTION_EXTENDED`, `UNCANCELLATION`,
`PRODUCT_CHANGE` dönem **ortasında** düşüyor. Elinde 287 hak olan kullanıcı
100'e iniyordu. 300 → 100 inişinden ÖNCE görünmezdi (300'ü yine 300 yapıyordu,
hediye) — **tavan düştüğü an kayıp üretti.** Kural: tazeleme hakkı yalnız
YUKARI çeker (`max`), asla azaltmaz.

**TARİH UYDURMA.** Son kullanma taşımayan olayda `billing.py` "şimdi + 35 gün"
yazıyordu ve gerekçesi *"bir sonraki RENEWAL gerçek tarihi yazar"* diye
çivilenmişti. Tam tersini yapıyordu: uydurulan işaret gerçek dönem sonundan
ileride kaldığı için bir sonraki yenilemenin tarihi ondan **geride** kalıyor,
idempotency kapısı düşmüyor ve kullanıcı o dönemin hakkını **hiç almıyordu**.
Çözüm: tarih uydurma, hakkı ver ve işareti **taşıma**; idempotency'yi ayrı bir
bayrakla kur (`allowanceGrantedWithoutExpiry`) — yoksa tekrarlanan olay
harcanmış hakkı geri doldurur (bedava hak musluğu).

**OKUYUCUSU OLMAYAN ŞEYİ ISITMA.** Burç ön-üretimi haftalık/aylık kovalar için
de kurulmuştu (hem de adlarına rağmen `* * *` ile her gece): 48 LLM üretimi,
**okuyucusu sıfır** — `period` gönderen tek istemci satırı yok. Bekçi
"üç dönem de ısıtılsın" diye yazılırsa bu kusuru **korur**; doğru değişmez
**"ısıtılan her dönem istemciden istenebilir olmalı"** ve iki yöne de çalışır
(yüzey açıldığı gün işi eklemeyi hatırlatır).

**BİR HUKUK METNİNİN BEŞ KOPYASI VARSA DÖRDÜ AYRIŞIR.** Gizlilik politikası
beş yerde yaşıyordu; `docs/legal/gizlilik-politikasi.md` hiçbir yerden
referans edilmiyordu ve iki ay bayat kaldı (dört bölüm eksik). Metni
kaldırıldı, yönlendirmeye çevrildi, `test_besinci_kopya_geri_dogmaz` ile
çivilendi. Üç kopya zorunlu (mobil / web TR / web EN birleştirilemiyor),
dördüncüsünün gerekçesi yok.

**`flutter test` PARALEL koşunca `build/test_cache` bozuluyor** (ölçüldü
2026-10-10, D4 dalgası). İki ajan aynı anda `flutter test` koşturdu; tek
artımlı derleme önbelleği (`apps/mobile/build/test_cache/build/*.cache.dill.track.dill`)
iki süreçten yazılınca SDK İÇİNDEN sahte `NoSuchMethodError:
RenderEditable.promptRectRange` üretti — `TextField(autofocus: true)` olan
her testte, proje kodu sıfırken bile. SDK 3.44.7 kaynağında o getter yok.
Çare: `rm -rf apps/mobile/build/test_cache`. Kural: **"SDK içinde eksik
getter/method" hatası görülürse kod suçlanmadan önce önbellek silinir.**

**`StreamController.onCancel`'dan iç `cancel()` Future'ını DÖNDÜRME**
(ölçüldü D5, 9 dakikalık test askısı): Dart'ın kök bölgedeki `_nullFuture`'ına
`whenComplete` zinciri kuruluyor, dış akışın `done`'u sahte-zamanlı testte
hiç gelmiyor ve `cancel()` askıda kalıyor. Aynı sebeple `testWidgets`
gövdesinde bitmiş aboneliğe `await cancel()` YAZMA (`unawaited`);
`StreamController.close()` dinleyicisiz asla tamamlanmaz (tearDown'da kapat).

**`Tooltip` semantik `label` DEĞİL `tooltip` alanıdır**: ikon-tek
`IconButton`'a ekran okuyucu adı vermek için `Icon(semanticLabel:)` şart;
`find.bySemanticsLabel` tooltip metnini BULMAZ (ölçüldü D5).

**`animateToPage` sıfır süreyi REDDEDER** (`scroll_activity.dart:705`
assert `duration > Duration.zero`): `kapili(context, …)` hareket azaltmada
`Duration.zero` döndürdüğü için `animateToPage(duration: kapili(...))`
7/7 testi düşürdü. Sıfırda `jumpToPage`'e dallanmak ŞART; sihirbazdaki
`_sayfayaGit` bunu yapıyor, ortak yardımcı `widgets/motion.dart`'a D5'te
taşınır (ikinci kopya `sign_story_screen.dart:113`).

**Riverpod:** `FutureProvider` varsayılan `isAutoDispose = false` — yutulan
bir hata **oturum boyunca** önbellekte kalır. Ayrıca `apiProvider`'ın
interceptor'larından `apiProvider`'ı izleyen bir sağlayıcıya dokunmak
`CircularDependencyError` fırlatır (bkz. bulgu B10).

**Oturum kapanınca basılı rota ÜSTTE kalır** (iPad'de ölçüldü 2026-10-28):
`_Gate` kökü giriş sayfasına çevirir ama `Navigator.push` ile açılmış
sayfa yerinde durur — Hesap sayfasından silince ekranda silinmiş hesabın
adı ve "Hesabı sil" düğmesi kaldı. `GateRootGuard` (`core/gate_guard.dart`)
oturumun AÇIK→KAPALI kenarını da dinleyip yığını köke indiriyor; çıkışın
her yolu oradan geçer, ekran ekran bırakılsaydı her yeni çıkış yolu aynı
kusuru taşırdı. Onarımdan sonra iPad'de silme doğrudan giriş sayfasına
döndü (sahip, iki kez).

---

## 6. Bugünkü durum (2026-10-10)

Dal: `yuz-okuma-cihaz-usti-olcum`. Sürüm **1.20.0+53** (pubspec, 2026-10-18; 52 yandı — üç kanalda).
D0–D8 + S1 + cihaz turu 1 + cihaz turu 2 (paylaşım) kodda ve commit'li.
52'ye çekildi çünkü 51'in Console'a yüklenip yüklenmediği bilinmiyordu —
yanmış koda çarpmak yüklemeyi durdurur, atlanan kod zarar vermez.
**52 YANDI ve üç kanalda** (sahip, 2026-10-17): dahili → kapalı → **açık
test (yalnız Türkiye)**. Üretim erişimi 2026-10-17'de verildi; üretim
kanalı henüz "Etkin değil". Sıradaki kod **53**.

**Cihaz turu 2 (2026-10-16):** (1) günlük düğmesi başlığın EN SAĞINA
(bakiye hapının sağı). (2) **Paylaşımda veri kaybı:** rapor kartı uzun
metni tek görsele sığdırmak için KESİYORDU — eski bilinçli kural ("kart
raporun yerine geçmez, ona davet eder") sahip kararıyla tersine döndü:
rapor artık sayfalara bölünür (`ReportShareCard.sayfalar`, cümle
sınırından, punto sabit 36, tavan 10 sayfa, tavan aşılırsa son sayfa "…"),
tüm sayfalar tek paylaşımda (`shareRenderedCards`). Çark kartı yalnız
çarkı taşıyordu, ekrandaki konum tablosu yoktu — kartın altına eklendi
(`_KonumTablosu`, `FittedBox.scaleDown` ile ikili çarkta da taşmaz).
Ölçüldü: çarkın KENDİSİ kartta sadeleşmiyordu (aynı katmanlar), kayıp
tablodaydı. (3) Telefonda eski paket adı/fiyatı: Play önbelleği + açık
kalan uygulama oturumu — kod kusuru değil.

⚠️ **Sürüm kodu 50 YANDI** (2026-10-14): sahip D8 derlemesini (`0b687bb`,
cihaz turu ÖNCESİ) dahili teste yükleyip kapalı teste yükseltti; Console iki
kanalda da 50 gösteriyor. Cihaz turu düzeltmeleri (`34e754c`) o pakette
YOK — kod 51'e çekildi, AAB 51 `infra/build-aab.ps1` ile üretildi. Sıradaki
adımlar dışa dönük ve SAHİP onayı ister: `infra/deploy-backend.ps1` (D8'in
`default_name` değişikliği canlıda değil — rev 00109 S1+D0'da kaldı) →
AAB 51 dahili teste → kapalı/üretime yükseltme → üretim başvurusu formu
(cevaplar oturum kaydında). 49'luk AAB yalnız ölçüm artefaktıydı.

⚠️ **Play "DEX optimizasyonu %0" uyarısı KAPANDI (kaynakta, 2026-10-10)** —
Console'un kendi ölçümü ancak 50 yüklenince değişir. Kök: RevenueCat Amazon
modülünün consumer kuralındaki tek `-dontoptimize` BÜTÜN uygulamanın
optimizasyonunu kapatıyordu; küçültme/karartma açıktı, derleme başarılı,
testler yeşil — kusur yalnız AAB'nin `BUNDLE-METADATA/com.android.tools/
r8.json`'unda görünüyordu (`noOptimizationPercentage: 100.0`). Onarım
`keepRules { ignoreFrom(...) }` + `proguard-rules.pro`'da modülün diğer üç
kuralı; `build-aab.ps1` altıncı kapı r8.json'u okuyor; ölçülen sonrası
**%37,53** (kalan `-keep`'li sınıflar, eşik 75). Aynı turda `main()` her
Android sürümünde `edgeToEdge` açıyor (ikinci Play uyarısı). Bekçi
`backend/tests/test_android_build_config.py`. ⚠️ Cihazda ölçülecek: R8
optimizasyonu ilk kez açık — bildirim, Google girişi, satın alma/geri
yükleme, yüz okuma (ML Kit + TFLite), sohbet; ve çubukların içerikle çakışıp
çakışmadığı.
Backend rev **00110-7q7** — 2026-10-14 dağıtıldı (`6a7406f`: D8 dil-duyarlı
varsayılan ad + paket adetleri **50/100/200**), trafiğin %100'ü, iki adreste
`/health` **200**, ilk 15 dk ERROR/5xx yok. Deploy logundan BAĞIMSIZ
doğrulandı: `gcloud run services describe` + curl + Cloud Build'in KENDİ
kaynak paketi indirilip `backend/core/wallet.py` okundu (50/100/200,
`Traveler`). ⚠️ O pakette `find` önce `.claude/worktrees/` altındaki ESKİ
bir `wallet.py`'yi (100/300/1000) buldu — doğrulamada yol tam yazılır.
`.claude/` artık `.gcloudignore`'da. Önceki 00109-vdx (10-10) S1+D0'dı.
Play fiyatları (sahip, 2026-10-14): Console'a **KDV HARİÇ** girildi —
abonelik ₺200 → alıcı ₺240, paketler ₺80/140/250 → alıcı ₺96/168/300 (Play
%20 ekler, B3). Net: abonelik ~₺170 ≈ $4,05, başabaş ~7-9 abone.

**Kapalı testteki son sürüm 48 (1.18.0)** — 4 Ekim 20:29'da sunuldu, kanal
Etkin, 172 ülke/bölge (Console ekranından ölçüldü 2026-10-10). Yani **48
YANMIŞ**; sıradaki kod 49 ve `pubspec.yaml` ona ayarlandı. ⚠️ 49'un serbest
olduğu Console'un **kapalı test** sayfasından okundu; dahili testte daha
yüksek bir kod durursa yükleme "sürüm kodu daha önce kullanıldı" der ve
artırmak gerekir — o sayfaya bakılmadan bilinemez.

### 1.20.0+50 turu — "onar + tekleştir" (başladı 2026-10-10)

Sahip kararı: bu bir **lifestyle** uygulaması; görsel kimlik korunur, aynı
kavram için TEK bileşen kalır. Plan dosyası
`~/.claude/plans/google-do-rulamas-gelince-kalan-humble-journal.md` (9 dalga,
~300 iş kalemi, 8 sahip kararı). Kesintide kaldığı yerden devam için:

| Dalga | Durum | Commit |
|---|---|---|
| D0 backend + sözlük ("kredi" tek kelime, `fallback` 6 uçta, BaZi `unspecified`, "sınırsız" gitti) | ✅ pytest 2384, 31/31 mutasyon | `410737a` |
| D1–D2 fontlar pakette + `RythoGlyphs` + token/hareket/tema eklemeleri | ✅ Flutter 882, 10/10 mutasyon | `eed33c7` |
| BaZi fısıltı önbellek anahtarı cinsiyet | ✅ | `d954948` |
| D3 paylaşılan bileşenler (4 ajan paralel; `OkumaKabi`, `acPaywall`, `ozellik_katalogu`, `IzinKapisi`…) | ✅ Flutter 1033, 57/57 mutasyon | `b9b81c7` |
| D8-web (App Store hapı, 4 sayfa rytho.css, yorum temizliği, WebP 11,7 MB→0,6 MB, ortak EN) | ✅ pytest 2541, 31+3 mutasyon | `2be3512` |
| D4 giriş+onboarding (6 adım, önseçim yok, saat uydurulmaz, giriş sükûneti, iptal hata değil) | ✅ Flutter 1103, 48/48 mutasyon | `c16a99d` |
| D5 ana ekran+profil (tek "Bugün", AsyncBolum, ~~günlük satırı altta~~ → K7 cihazda GERİ ALINDI, kabuk niyeti, hikâye sükûneti, çıkış onaylı, abonelik "—", saat uydurulmaz) | ✅ Flutter 1194, 70 mutasyon | `3dfe7a3` |
| D6 derinlik (OkumaKabi 9 yüzey, çark çizgi dili + salt önizleme, Çevrem/kişi onayları, sohbet hata balonu + 402 tek yol) | ✅ Flutter 1441, 89/89 mutasyon | `707dd4a` |
| D7 para (bedel kapısı 4 ekran — cüzdan yüklenirken geçmez; yıllık K8 ölçülmüş rozet; abonelik üç hâl + K2; mağaza tek düğme; `purchaseErrorText` tek kapı; rozet 10 yüzey; 429 notu) — ajansız, tek elden | ✅ Flutter 1500+, backend 2749, 33/33 mutasyon | `1531471` |
| D8 cırcır bekçileri (hareket/token/l10n — dosya başına ÖLÇÜLEN tavan), 58 ölü ARB anahtarı, ✨ 15→5, EN çoğul, Plaque/dock/TypingDots/ErrorCard/GlassSegments.margin, backend varsayılan ad dile göre, belgeler, pubspec 1.20.0+50 | ✅ Flutter 1545, backend 2751, 12/12 mutasyon | `0b687bb` |
| **S1 sohbet personası** (plan dışı, sahip şikâyeti 2026-10-10; yalnız backend — kapı `\b`, yetki alanı, `persona_guard`, `tools/sohbet_olc.py`) | ✅ pytest 2750, 66+7 mutasyon · ✅ CANLI rev 00109 | `5da5ed2` |

### Cihaz turu 1 (2026-10-14) — K7 geri alındı

Sahip AAB 50 öncesi derlemeyi cihazda açtı, dört bulgu: (1) **günlük
satırı okumanın altında GÖRÜNMÜYOR** — K7 kararı masada doğru, ekranda
yanlıştı; düğme sağ üste döndü, ikon-tek düğmenin adı `semanticLabel` +
`Tooltip` ile (K7'nin asıl itirazı "neye gittiği belli değil"di, o sorun
etiketle çözüldü, yer değiştirmekle değil). (2) **"Rytho'ya sor" düğme gibi
görünmüyordu** — çıplak lila metinden lila konturlu hapa (altın CTA değil:
sohbet kapısı satış değil). (3) **Alt sayfalar "soğuk"** — kabuk rengi/biçimi
aynı, üst kenar ışığı + lila tutamak + dayanak başlığında altın glif.
(4) **Profil hâlâ yoğun** — seri kartı kalktı (rozet burç çiplerinin
yanında), "Doğum ve kimlik" Hesap'a girdi: beş karttan üç.

**Ders:** yerleşim kararı (K7 gibi) ancak CİHAZDA kapanır; bekçi testleri
kararın kodda durduğunu kanıtlar, görünür olduğunu değil. Kararı değiştiren
tur bekçiyi de tersine çevirir (`sky_hiyerarsi_test` "günlük BAŞLIKTA").

### S1 — sohbet personası kayması (ölçüldü 2026-10-10, üretim Firestore salt okuma)

Sahip şikâyeti: Rytho bir yerden sonra "normal AI chat" gibi sunum hazırlamaya
başlıyor; bazen sorulmadan "maddi konularda tavsiye veremem" diyor. Ölçüm
(32 kullanıcı / 122 konuşma / 498 mesaj + şikâyetteki kullanıcının 76 mesajlık
konuşması) DÖRT ayrı kusur verdi:

- **A — yetki alanı yok.** `CHAT_SYSTEM_INSTRUCTION`'da "görev yardımı
  yapma" cümlesi hiç yoktu; model önce KENDİLİĞİNDEN teklif etti ("sunumun
  havasını tasarlamak istersen buradayım"), sonra "sunum hazırlar mısın" →
  "taslak ve akış planı hazırlayabilirim elbette".
- **B — yasak-alan kapısı ALT DİZE eşleşiyor** (`safety_rules.py`):
  "**hisse**diyorum" → finans reddi, "**altın**da" → finans, "mutlu
  **olurum**" → ölüm, "sick of my job" → sağlık. Hepsi bu makinede koşturularak
  ölçüldü. ⚠️ Engellenen turlar `write_turn`'dan ÖNCE dönüyor → Firestore'da
  İZ YOK; "korpusta 0 engel" demek "hiç olmadı" demek DEĞİL.
- **C — sorulmadan çekince:** kayıtlı cevaplarda 1/498 (gerçek sağlık
  sorusu). Görülenler B'nin ürünü + ürünün kendi para çipleri/gece soruları
  temayı açınca modelin NEVER listesine refleks çekince eklemesi.
- **D — HESAPLANMAMIŞ HARİTA UYDURMA (en ağır):** sohbete yazılan doğum
  tarihlerinin 3/4'üne model Güneş/Ay burcu uydurdu ("29/04/2010 istanbul" →
  "Güneş'i Boğa, Ay'ı Akrep"). Sohbet hiçbir şey hesaplamaz; kişi haritası
  yalnız Çevrem'de hesaplanır. `fact_guard` bunu yakalamadı ve yeniden üretimde
  de uydurma kalırsa metni yine kullanıcıya gönderiyor (`grounded=False`
  yalnız önbelleği etkiliyor).

Onarım S1 dalgasında (K kapı+kayıt, P yetki alanı+`persona_guard`+üçüncü
kişi, E ölçer `tools/sohbet_olc.py`). Yayılım: yalnız backend
(`infra/deploy-backend.ps1`), AAB gerekmez.

⚠️ **Üçüncü-kişi bekçisi kapanış probunda YANLIŞ POZİTİF verdi** ve bu
sınıf en tehlikelisi: kullanıcının KENDİ haritasını anlatan doğru yanıt
("Haritanda Güneş'inin Yay burcundaki Jüpiter…") cümle başındaki büyük
harfli sıradan kelime yüzünden "adlı iddia" sayıldı; ikinci üretim de aynı
doğru cümleyi kurunca kullanıcıya doğru cevap yerine SABİT "Çevrem'e ekle"
cümlesi gidecekti. Kural: bekçi yalnız sohbete DOĞUM VERİSİ girdiğinde
bakar (bu mesaj ya da prompt geçmişi — uydurma tarihsiz sonraki turlara
geçmişle taşınıyor, ölçüldü). "Bir bekçinin yanlış pozitifi, koruduğu
kusurdan ağırsa bekçi daralır." Kriz turu BİLEREK arşivlenmez (kullanıcının
geçmişinde durmasın); yasak-alan turu arşivlenir ve `conversation_id`
döner (yoksa yetim konu 20 konu tavanına sayılıp gerçek konuyu sildirirdi).

⚠️ **Dalga kapanış ritüeli** (üç kez işe yaradı): tam takım → ajanların
`dokunmadigim_ama_gerekli` alanlarını TAM metin oku (dikişler orada; D0'da
üç kırmızı ve bir ürün kusuru oradan çıktı) → ajan mutasyonlarını kendi
harness'ınla koştur (`tools/mutasyon_dart.py`, `tools/mutasyon_backend.py` —
ikisi de `<workflow_output.json> [ajan,ajan]` alır) →
commit. Ajan "kendim denedim" dese de ölçüm değildir.

⚠️ **`google_fonts` `fontFamilyFallback`'i ÜZERİNE YAZAR**
(`google_fonts_base.dart:116-119`): parametre olarak vermek işe yaramaz,
`RythoText._glifli` dönüşten SONRA `.copyWith` ile ekliyor. Glif fontu
kapsamı iddia edilmez, `tools/font_paketi_uret.py` ölçer; `℞` bilinen açık.

⚠️ **Ağırlık ölçümü üçlü ifadeyi kaçırdı**: `w: a ? w700 : w500` — yalnız
ilk literali alan ölçüm Manrope-500'ü pakete koymadı; `allowRuntimeFetching
=false` ile cihazda FIRLARDI. `font_paketi_test` her `w:` ifadesinin HER
dalını literal ister.

### İki kanalın bağlaşımı (ölçüldü 2026-10-10, backend yarısı KAPANDI)

İki dağıtım kanalı ayrı ayrı bayatlamıştı ve **birbirine bağlıydı**.
Backend gönderildi; Play yarısı duruyor.

| Kanal | Önceki canlı | Şimdi | Durum |
|---|---|---|---|
| Cloud Run | rev 00107 = `2d0bfeb` (10-03) | rev **00109** = `5da5ed2` (S1 + D0) | ✅ gönderildi |
| Play | AAB 48 = `36d250a` (10-03 04:46 UTC) | AAB 49 diskte | ⏳ yüklenmedi |

**Bağlaşım, ölçülmüş — ve sırayı bu belirledi:** istasyon kartının anlam
cümlesi SUNUCUDA üretiliyor (`prompts/tr.py` `STATION_PLANET_THEMES` ×
`STATION_PHASE_LINES`). İstemci yalnız `line`/`technical` alanlarını
basıyor. Eski sunucu istasyona `line` YAZMIYOR ve istemci o durumda
`calendar_strip.dart:351-363` dalına düşüp `transit_local — type_local`
basıyor — yani **tam olarak şikâyet edilen "Plüton — ileri harekete dönüş"
satırı.** Yalnız AAB gönderilseydi ikinci şikâyet (dayanak sayfası, tamamen
istemci tarafı) onarılmış, birinci şikâyet **hiç dokunulmamış** görünürdü.
**Kural: önce backend, sonra paket.**

⚠️ **Sürüm kodu 48 YANMIŞ** — dahili teste yüklendi, yeni derleme artırmak
zorunda. Hangi kodun serbest olduğu **depodan bilinemez**, yalnız Console'un
kanal sayfası söyler (bu notun bir önceki hâli tam bu yüzden yanıltmıştı).

Sıra: `infra/deploy-backend.ps1` → `infra/build-aab.ps1` (düz
`flutter build appbundle` ASLA) → Console'dan kanal yükseltme.

⚠️ **Bu notun eski hâli yanlıştı** ve tam da tehlikeli yönde: *"46 Play'e
henüz yüklenmedi — sürüm kodu hâlâ serbest, yeniden derlerken artırma"*
diyordu. Console gerçeği tersini gösterdi. Kod artırıldığı için zarar
görülmedi, ama o nota uyan biri **"sürüm kodu daha önce kullanıldı"**
duvarına çarpardı. Ders: **bir sürüm kodunun serbest olduğu depodan
bilinemez** — yalnız Console'un kanal sayfası söyler.

### Üç yüzey artık GERÇEKTEN günlük (2026-10-03) — ve bedeli 5'te kaldı

Yüz okuma, BaZi ve doğum kapısı kimlik yüzeyinden günlük yüzeye geçti.
**Tasarımın merkezi ayrımı:** "günlük yap" ≠ "her gün baştan üret". Ölçülmüş
sabit çekirdek (yüz oranları → belirti tablosu, doğumun dört sütunu, 64 sabit
kapı pasajı) KALDIRILMADI; prompt kalıcı olanı ve bugüne ait olanı **ayrı
başlıklar** altında veriyor. Günlük olan şey, çekirdeğin o günle KESİŞİMİ.
Bu paragrafı silen bir sonraki tur, ürünün ölçülmüş çekirdeğini atar.

Anahtar–prompt denkliği **yapısal**: `_gun_kovasi(gun_blogu)` anahtarın gün
terimini prompta GİREN BLOĞUN KENDİSİNDEN türetiyor, yani "gün promptta ama
anahtarda değil" (yasak hâl) oluşamıyor ve tersi bedava geliyor — günün
olgusu dönmediğinde anahtar da dönmüyor, jeton yanmıyor.

⚠️ **"Günlük" adını hak ettiren ölçüm:** doğum kapısı TEK BAŞINA günlük
değil — `GATE_SPAN` 5,625° yani bir kapı ~5,71 gün, 30 günde yalnız 6 ayrı
değer. Kapı+**çizgi** 30/30. Çizgi basılmasaydı yüzey "günlük" adıyla
sunulurken 5,7 günlük olurdu. BaZi'de günlüklüğü taşıyan terim **Liu Ri**
(30/30); Liu Yue 2/30, yalnız bağlam.

**Bedel 5'te KALDI (sahip kararı, 2026-10-03).** Gerekçesi ölçüldü ve
tutarlı: ağır kullanıcı 100'lük hakkı **6,67 günde** bitirir (15 jeton/gün,
sohbet/İ Ching/ikili hiç sayılmadan — eskiden aynı üç yüzey ~31 jeton/ay
istiyordu, 14,3 kat) AMA o duvara **yalnız Plus aboneleri** çarpıyor (üçü de
`require_plus`) ve paketler **yalnız aboneye** satılıyor (K2). Yani duvara
çarpan kişi, paketi alabilen kişiyle aynı — K1'in kurduğu ekonomi bu.
Marj kısıt DEĞİLDİ: hak tavanı yüzünden ağır kullanıcı ~$0,054/ay'ı geçemiyor
(abonelik neti ~$4,05 — görünen ₺240, 2026-10-14). Ayrıntı ve bedel tablosu
`docs/maliyet-calismasi.md`. ⚠️ Ölçülecek tek şey **yeni harcama hızı**;
eski 7 jeton/gün ölçümü bu değişiklikten ÖNCEYE ait.

⚠️ **Girdinin en büyük kalemi bir tur boyunca HİÇ ölçülmemişti:** RAG pasaj
bloğu ~6.224 karakter (~1.730 token) — yüz okumanın girdisinin %55'i, doğum
kapısının %61'i. Parçaların %85,5'i 2.000 karakter tavanını aşıyor. Yani
"prompt şu kadar" diyen eski sayılar **alt sınırdı**; gerçek girdi ~2,5 katı.

⚠️ **Bu üç yüzeyin önbelleği KİŞİYE ÖZEL** (anahtar `user_id` taşıyor), yani
maliyet kullanıcı sayısıyla ÇARPILIYOR: 1.000 ağır kullanıcı = ~$54/ay. Burç
yorumu bunun tersi — anahtarı kullanıcıdan bağımsız, doküman sahipsiz, filo
toplamı ~$1,2/ay ve kullanıcı sayısından BAĞIMSIZ. İki sınıfı karıştırmak
maliyet tahminini mertebe yanlış yapar.

### Bu bir LIFESTYLE uygulaması (sahip kararı, 2026-10-10)

Sahibin tarifi: *"Rytho'da teknik ifadeler ve teknik bir kart düzeni var,
bu bir lifestyle uygulaması, dolayısıyla daha anlaşılırdan isteyenler için
daha teknik bir yapıya gidilmeli."* Bu bir üslup tercihi değil **yerleşim
kuralı** ve her yeni yüzeye uygulanır.

**AYRIM, bu turun belkemiği — karıştırılırsa ürün ya ölçümünü ya dilini
kaybeder:**

| | Karar |
|---|---|
| Ölçüm **DİSİPLİNİ** (eşitlikte baskınlık söylenmez, saatsizde ev çizilmez, orbu ölçülmemiş açı lider olamaz) | **KORUNUR, dokunulmaz** |
| Disiplinin **REKLAMI** (ekrana basılan *"ölçülmeyen söylenmez"*, *"bu sayfa önce ANLAMI sonra ÖLÇÜMÜ gösterir"*) | **KALDIRILDI** |

Yani: **dayanağı GÖSTER, disiplini ÖVME.** Hiçbir ölçüm bloğu silinmedi —
yalnız sıra tersine döndü: ne olduğu önce, nasıl ölçüldüğü sonra, en altta
"Rytho'ya sor".

⚠️ **"Ölçüm" ile "ad" aynı şey DEĞİL ve bu ayrım iki ekranda yerleşimi
belirledi.** Doğum kapısının 56 px'lik glifi ve İ Ching'in çekim glifi bir
ölçüm değil **konunun kendisi** — İ Ching'de kullanıcı onu kendi eliyle
üretti (soruyu yazdı, çekimi yaptı, çizgiler tek tek indi). O yüzden o iki
ekranda glif ÖNDE kaldı, okuma hemen altına geldi; panelin **içindeki**
ölçümler (mono Güneş boylamı, trigram+element, nükleer heksagram, gün
sütunu) aşağıdaki dayanak bölümüne indi. Okumayı glifin üstüne koymak,
kullanıcının yaptığı işi sayfadan aşağı itmek olurdu.

**Bekçi:** `anlam_once_bes_ekran_test.dart` (17 test). Dördünde **gerçek
yerleşim** ölçülüyor (`getTopLeft().dy` karşılaştırması); İ Ching'de
kaynaktan çivileniyor çünkü `_HexagramView` özel ve ona ulaşmak çekimin
tamamını koşturmak demek — sınır beyanı testin içinde yazılı.

⚠️ **dy bekçisi tek başına KÖR:** yalnız "okuma ŞU ölçümün üstünde" diyor,
anlamın **üstüne adı bilinmeyen YENİ bir blok** eklemek takımı yeşil
bırakır. Aynı boşluk `anlam_once_test`te Harita İnceleme için bir kez
yakalanmıştı; ikinci bağımsız işaret (`children: [` ile okuma arasında
izinli kalemlerden başka bir şey kalmaması) o yüzden kuruldu.

**"Rytho'ya sor" tek yerde** (`RythoyaSor`, `atlas_widgets.dart`) ve etiket
`l10n.signalAsk`ten okunuyor — beş kopyanın dördü ayrışır. Tohum sohbeti
**o soruyla** açar ama **göndermez** (`chat_screen.dart` doktrini); otomatik
gönderim hem kullanıcının ağzına soru koyar hem jeton musluğu olur.

(`bazi_tab.dart` `missing_elements` hoşgörüsüz cast'i D6'da KAPANDI —
`(chart['missing_elements'] as List?) ?? const []`; eski not burada iki tur
"onarılmadı" diye durdu.)

### ⚠️ CANLI KESİNTİ: Gemini 403 "Lightning dunning decision is deny"

Bu bölüm bir kez gün kaybettirdi ve **ölçme yöntemi** asıl değerli kısım.

Belirti: Cloud Run'da `403 PERMISSION_DENIED`, mesaj
*"Lightning dunning decision is deny for project: projects/770582338651"*
(= `rhytoai`). Kaynak `gemini_service.py` `generate_content` VE
`rag_service.py` `embed_content` — **iki yüzey**, biri atlanırsa teşhis eksik
kalır.

**EPİZODİK, kalıcı değil** (ölçüldü 2026-10-02): epizot 1
`09-02T12:23Z → 09-03T04:17Z` (~16 saat, **kendi kendine geçti**), sonra
**27 gün sıfır red**, sonra epizot 2 `10-01T21:59:59Z → ~10-02T12:00Z`
(~14 saat, **o da kendi kendine geçti**). İkisi de **ay başına** denk
geliyor — aylık otomatik çekimin düşüp sonra tutması desenine uyuyor. Yani
"kalıcı bir risk bayrağı" değil, fatura döngüsü.

⚠️ **1 KASIM'DA ÜÇÜNCÜSÜ BEKLENİR.** Desen iki kez tuttu; kalıcı çözüm tek
seferlik ödeme değil **güvenilir bir kart ya da ikinci bir yedek ödeme
yöntemi**. Bunu yapmadan geçen her ay başı yeni bir ~15 saatlik kesinti
riski taşıyor.

**Red PROJE düzeyinde, anahtar kısıtı DEĞİL.** Kanıt: fatura da kota da
gerektirmeyen `models.list` bile 403 veriyor. Anahtarın tek kısıtı
`apiTargets = generativelanguage.googleapis.com`, istemci kısıtı yok ve
`updateTime` **2026-07-23** — yani 09-26 kısıtlama turunda ona dokunulmamış.
Anahtar kısıtı olsaydı mesaj *"Requests from … are blocked"* olurdu.

⚠️ **"Aynı anahtar yerelde çalışıyor" çelişkisi ÇÖZÜLDÜ ve dersi değerli.**
Teşhis sırasında aynı anahtar (SHA-256 ile doğrulandı: `.env` ile Secret
Manager **AYNI**) bu makineden `models.list`'e 10/10 başarılıyken Cloud Run
403 alıyordu. "Çağıran ortama duyarlı red" gibi görünüyordu — **değildi**:
red o dakikalarda zaten kalkmıştı ve Cloud Run 11:54'ten sonra **hiç deneme
yapmamıştı** (kuyruk boştu). Yani iki ortamı karşılaştırmak yanlış soruydu.
Doğru hamle **üretimden tek bir çağrı tetiklemek** oldu
(`gcloud scheduler jobs run rytho-horoscope-warm-daily`) ve 12:35'te
`generateContent` + `batchEmbedContents` **200** döndü.
**Ders: "A ortamında çalışıyor, B'de çalışmıyor" demek için ikisinde de AYNI
ANDA deneme yapılmış olmalı. Deneme yokluğu kanıt değildir.**

**BAŞARI SAYISI LOGDAN ÖLÇÜLEMEZ** — `generate()` başarı yolunda hiçbir satır
basmıyor. Doğru ölçü Firestore `usageEvents`: her DÖNEN çağrı bir doküman,
`day` alanı UTC gün anahtarı. Ölçülen: 09-30 → 81, 10-01 → 59, 10-02 kesinti
sırasında **0**, kesinti bitince aynı gün **22** (18'i burç ısıtması).
"Logda hata yok" ≠ "çalışıyor"; "logda hata var" da ≠ "hâlâ bozuk".

Sahibin yapması gereken sırayla: (1) fatura hesabı
`01156B-3E95EE-A8BB8F` → İşlemler/Belgeler/Ödeme yöntemi, başarısız çekim ya
da süresi geçmiş kart; (2) `pay.google.com` ödeme profili; (3) ödeme sorunu
yoksa `discuss.ai.google.dev` Gemini API kategorisinde **manuel inceleme
talebi** — Google'ın kendi forumunda aynı mesajla onlarca vaka var ve
birkaçında **ödeme yapmak tek başına yetmemiş**. YAPMA: anahtar üretmek,
kısıt gevşetmek, API'yi kapatıp açmak, faturayı söküp bağlamak — hiçbiri
işe yaramıyor (ölçüldü + forum kaydı).

### ⚠️ CANLI KESİNTİ 2: fatura hesabı ÖN ÖDEMELİYE çevrildi (2026-10-17)

Google fatura hesabını (`01156B-3E95EE-A8BB8F`) sahibe sormadan **ön
ödemeli** yaptı; bakiye 0 olduğu an her Gemini çağrısı
`402 RESOURCE_EXHAUSTED — Your prepayment credits are depleted` aldı.
Ölçüldü: ilk red **01:31Z**, son **03:22Z** (10 günlük logda başka yok),
66 başarısız çağrı; sahip AI Studio → Billing'den ₺1.000 yükledi,
**03:26Z'de üretimde ilk başarılı `daily` çağrısı** (`usageEvents`).
Bu 403 "dunning"ten AYRI bir sınıf: artık risk ay başı çekim değil,
**bakiyenin sıfıra inmesi** — o an kesinti anında ve tam.

- Ölçülen gider: son 30 gün `estCostUsd` toplamı **~$2,2** (2.060 çağrı,
  ~69/gün). Embedding ve aynı fatura hesabındaki **ikinci proje
  `steameuradio`** bu sayıda YOK ama aynı bakiyeden düşer.
- Önlem: **otomatik yeniden yükleme** (Auto-reload) — kapalıyken her
  sıfırlanma bir kesinti. Uyarı bandı ("0$'ın üzerinde bakiye gerekir")
  bakiye doluyken de durur; "tekrar yükle" demek DEĞİL.
- Kesintide üretilen yedekler: sinyal paketi 1 sa önbellekli (kendini
  onarır), push satırı **36 sa** (o günün burç satırları şablonda kalır).

### "Astroloğa gerek bırakma" turu (2026-10-18) — dört yüzey sözle

Sahip cihazda: "Toprak 2/8 iyi mi kötü mü?", "Ay ☍ Plüton 0° ne?", İç
Mevsim/Yıl Haritası "makale gibi". Onarım YALNIZ ölçülmüş veri × sabit
metin (`features/atlas/anlam_cevirici.dart`, sıfır LLM): açı satırı önce
rol×tür cümlesi + güç sözü (derece dayanakta), alt sayfada iki gezegenin
rolü; Kişilik'te düzey sözü + "8 ana noktadan 2 tanesi" + baskın nitelik;
İç Mevsim ve Yıl Haritası'nda önce YOLCULUK (`widgets/yolculuk.dart`),
okuma KATLI (hazır değilse açık — yoksa "Tekrar dene" katta saklanır,
bekçi yakaladı), ölçüm en altta. ⚠️ Lifestyle turunun "okuma önde" kararı
bu iki ekranda TERSİNE döndü; `anlam_once_bes_ekran_test` buna göre.
Backend: saatsiz yıl haritasında `points[].house_no` ve köşe açıları artık
gitmiyor (öğlene göre ev ölçülmüş gibi görünürdü). Minör açılara cümle
bilinçli YOK. Kalan: ilerlemiş Ay'ın sonraki ikinci geçişi ve burca
giriş tarihi hesaplanmadı (tahmin edilmedi).

### Panel + site turu (2026-10-17) — gelir "kendiliğinden gelmiyordu"

Ölçülen kök: `rytho-stats` gecede BİR kez (23:40 UTC) koşuyordu → bugünün
geliri panelde ertesi geceye kadar yoktu, sahip "Yeniden hesapla"ya tarih
girip basıyordu; 23:40–24:00 olayları o güne hiç girmiyordu; `read_days`
"son N DOKÜMAN" döndüğü için eksik gün pencereyi geriye uzatıyordu; panel
varsayılanı PRODUCTION iken satın almaların HEPSİ SANDBOX'tı (gelir hep 0).
Onarım: iş SAATLİK (`zamanlanmis_kosu` + dünün damgaya bağlı kapanışı),
pencere takvim, bayatlık eşiği 2 sa (zil = sayfa, bekçili). Panel
(`web/rytho-admin/`) tek Türkçe sözlük (`sozluk.js`), yarışsız yönlendirici,
tek dönem seçici, sessiz URL kalıcılığı. ⚠️ Canlıya almak için
`infra/create-scheduler.ps1` KOŞMALI — aynı koşu canlıda HİÇ olmayan
`rytho-notify-circle` ve `rytho-notify-winback` işlerini de kurar (betikte
2026-10-03'ten beri tanımlı, Scheduler'da yok: iki bildirim türü hiç
gitmedi). ⚠️ `rytho.css` panelde de yükleniyor: sitenin çıplak `.uyari`
kuralı panelin `uyari` SEVİYE sınıfını bozuyordu — site kuralları artık
`.uyarilar` kabına bağlı. Ölçülen ek: abonelik olayı `priceInPurchasedCurrency
239.99` — B3 (Play %20 KDV ekler) DOĞRULANDI.

### ⚠️ Zamanlanmış işler bir AY boyunca YEŞİL yalan söyledi

Asıl kusur 403 değil; 403 olabilir. Asıl kusur **30 gün hiçbir yerde kırmızı
görünmemesi**. Zincir ölçüldü: 10 Gemini 403 → 10 *"Sinyal yorumu biçim dışı
(0 satır), şablona düşüldü"* → paket şablon satırına düşüyor → push **normal
gidiyor** → `gonderilen=10 basarisiz=0` → `POST /notify/run 200 OK`.
Yani `sent` sağlıklı, Scheduler günlüğü temiz, ürünün çekirdek vaadi
(kişiye özgü AI cümlesi) ölü ve kullanıcı her sabah şablon alıyor.

Onarıldı: `RunResult.generation` (`attempted/ok/fallback`), tam düşüşte uç
**503** dönüyor ve aynı ad `notifyRuns.lastStatus`'a yazılıyor. Eşik 3 ve
değeri ölçülmüş (günün yalnız üç koşusu bir şey borçlanıyor).

⚠️ **Yanıltıcı log sınıfı:** `generate()`'in `None`'ı bir yerde `""`e
cebirleniyor ve 403 **biçim hatası** olarak loglanıyor. O satırı okuyan
yanlış gerekçeye varır (`signal_service`, `calendar_insights`).

⚠️ **RAG sessizce bozuluyor:** embedding reddinde `search()` anlamsal aramadan
**kelime örtüşmesine** geriliyor (`rag_service.py:655-672`), hata yüzeye
çıkmıyor. Red kalktıktan sonra da bu yolun bozuk kalması fark edilmez.

⚠️ **Kullanıcı farkı anlamayan yedekler** (en kötü sınıf): uç `fallback`
bayrağı dönüyor ama istemci OKUMUYOR → **burç yorumu** (`providers.dart`,
ücretsiz katmanın omurgası) ve **ikili dinamik** şablon metni gerçek rapor
gibi gösteriyor. Altı uç bayrağı hiç döndürmüyor (iching, solar-return,
progressions, birth-hexagram, relationship, synastry). Jeton **iade
ediliyor**, yani para kaybı yok — ama bakiye açıklamasız yükselirken ekranda
"rapor" duruyor. Bildirim yedeği **36 saat** önbellekli, yani iyileşmeden
sonra kendini onarmıyor.

**Kapalı test yürüyor** (Alpha kanalı, 172 ülke/bölge). Kapalı testteki son
sürüm **46 (1.17.0)** — 30 Eylül 22:24'te sunuldu (ölçüldü 2026-10-03).

**Kanallar arası yükseltme KAYNAK kanalın sayfasından başlar.** Bir kez
karıştırıldı: kapalı testin sayfasında ⋮ → "Sürümü yükselt" açıldı ve
seçenekler yalnız **Açık test / Üretim** çıktı — çünkü yükseltme yalnız
YUKARI gider ve o sayfa kapalı testin KENDİ sürümünü taşıyor. Dahili
testteki bir paketi kapalı teste almak için menü **İç test** sayfasındaki o
sürümün satırında açılır: ⋮ → Sürümü yükselt → **Kapalı test**.

⚠️ **Üretim yolundaki tek kritik madde: testçi sayısı.** 12 testçi / 14 gün
sayacı, testçiler **opt-in bağlantısını açıp "Testçi ol"a basana kadar
başlamaz**; listeye e-posta eklemek hiçbir şey saymaz. Kök neden ölçüldü
(2026-09-26): sayaç 0'dı çünkü bağlantı **hiç dağıtılmamıştı** — sahibi de
o sayfayı ilk kez o gün gördü. Bağlantı:
`https://play.google.com/apps/testing/ai.rytho`

⚠️ **"HTTP 200" bu sayfa için HİÇBİR ŞEY KANITLAMAZ** (2026-09-28, ölçüldü).
Bu notun eski hâli bağlantıyı "canlı (HTTP 200)" diye kaydediyordu ve o
çıkarım yanlıştı: kimliksiz `curl` **Google giriş sayfasına** yönleniyor ve
o sayfa 200 dönüyor (`<title>Sign in - Google Accounts</title>`). Oturum
açılmış bir tarayıcıda ise sayfa yine **200** döndürüp gövdesinde
*"App not available — a testing version of this app hasn't been published
yet or isn't available for this account"* yazabiliyor. Yani durum kodu
değil **gövde** okunur; opt-in sayfasının çalıştığını kanıtlayan tek şey
sayfada "Testçi ol / Become a tester" düğmesinin GÖRÜNMESİDİR.

⚠️ **Sahibin kendi hesabı TESTÇİ DEĞİL** (2026-09-28, iki kez zaman yedi).
Testçiler bir Google Grubu üzerinden eklendi ve sahip o grubun üyesi değil;
geliştirici olmak testçi yapmıyor. Sonuç: opt-in sayfası sahibe
"App not available" diyor ve Console'daki opt-in kutusu da ona görünmüyor.
Link bozuk sanılıp aranmasın — **gruptaki bir hesapla** açılır. Sahip kendi
cihazında denemek isterse yol kapalı test değil **dahili test** kanalıdır.

Üç sessiz kopma noktası: testçi bağlantıyı **listedeki Google hesabıyla**
açmalı (telefonda ikinci hesap varsa Play varsayılanı seçer ve kayıt
tutmaz); **dahili testten kurulu olması saymaz**, yine basması gerekir;
ve 14 gün boyunca **kayıtlı kalmalı** — "testten ayrıl" sayıyı düşürür ve
sayaç geriler.

**App Check zorlaması AÇILDI** (2026-09-26). Ölçülen durum — **üç servisin
ÜÇÜ de ENFORCED** (yeniden ölçüldü 2026-10-10):

| Servis | `updateTime` |
|---|---|
| `identitytoolkit.googleapis.com` | `2026-09-26T08:50:52Z` |
| `firestore.googleapis.com` | `2026-09-26T08:51:11Z` |
| `firebasestorage.googleapis.com` | `2026-09-26T09:32:55Z` |

Sorgu:
`GET firebaseappcheck.googleapis.com/v1/projects/rhytoai/services/{servis}`
— ADC ile çağırırken `x-goog-user-project: rhytoai` başlığı ŞART, yoksa
kota projesi hatası döner.

⚠️ **Bu notun eski hâli iki hafta yanlış kaldı** ve hatanın cinsi öğretici:
*"`firebasestorage.googleapis.com` **UNENFORCED** (kalan tek servis)"*
yazıyordu ve bunu "Konsol borcu" listesinde açık iş olarak taşıyordu.
Ölçüm 08:50'de alınmış, Storage 09:32'de zorlanmış — yani **ölçüm 42
dakika erken alındı ve bir daha tekrarlanmadı.** `updateTime` son değişiklik
anıdır; bir servisin bugün elle açılıp açılmadığı oradan okunur. Ders:
aynı turda yapılan işlerin HEPSİ bitmeden alınan ölçüm, "ölçüldü" damgası
taşıdığı için bir daha sorgulanmıyor.

⚠️ **İNDİRME BAĞLANTILARI App Check'ten MUAF — ölçüldü (2026-10-10), ve
ölçme yöntemi asıl değerli kısım.** Avatar OKUMA yolu Storage SDK'sından
HİÇ geçmiyor: `avatar_editor.dart:59` `getDownloadURL()` ile aldığı URL'yi
Firestore'a `photoUrl` olarak yazıyor, üç ekran (`profile_screen.dart:105`,
`sky_screen.dart:660`, `contacts_screen.dart:299`) onu **çıplak
`NetworkImage`** ile çekiyor. O istek `dart:io` HTTP'si, App Check jetonu
taşımıyor ve **hiçbir paket sürümünde taşıyamaz**. Buna rağmen çalışıyor:

- geçerli indirme jetonuyla, App Check jetonu **olmadan** → **HTTP 200**,
  515.625 baytlık PNG tam geliyor;
- **aynı URL, indirme jetonu yanlış** → **401 `"Firebase App Check token
  is invalid."`**

İkinci hâl birincisini kanıtlıyor: uç App Check'i gerçekten zorluyor, ama
geçerli bir indirme jetonu isteği kapıdan muaf geçiriyor. **Tek bir 200
yetmezdi** — "muaf" ile "zorlama hiç çalışmıyor" ancak bu iki hâl yan yana
konunca ayrılıyor.

⚠️ Bunun **bedeli** de yazılı olsun: aynı URL `infra/storage.rules`'taki
`allow read: if request.auth != null` kuralını da aşıyor. Yani avatar
bağlantısı eline geçen herkes onu çekebilir. Önceden var olan tasarım,
indirme bağlantılarının doğası — ama "Storage kuralları koruyor" diye
yazılırsa yanlış gerekçe olur.

⚠️ **Bir gün bu yol kapanırsa çözümü YENİ PAKET DEĞİL.** Jetonsuz bir
isteği jetonlu yapmanın tek yolu okumayı SDK'ya taşımak (`ref.getData()`
ya da backend üzerinden vekil); yeni bir AAB o satırlar değişmedikçe
aynı jetonsuz GET'i atar.

⚠️ **App Check bekçisi: çağrı VE iki platformun yayın sağlayıcısı
tutuluyor** (kaynakta okundu ve mutasyonla ölçüldü 2026-10-24). `activate()` artık
`main.dart:153`; hata yine **yutuluyor** (uygulama jetonsuz devam eder),
ama yayında Crashlytics'e `app-check-activate` yazılıyor (U30) ve
`test/app_check_izi_test.dart` çağrının varlığını, sırasını (activate →
jeton yoklaması → `runApp`) ve catch'i tutuyor — satır silinirse kızarır.
Sağlayıcı seçimi de artık tutuluyor: üçlü ifadelerin YAYIN dalı
(`AppleAppAttestProvider`, `AndroidPlayIntegrityProvider`) başka bir
sağlayıcıya dönerse Debug/simülatör/emülatör debug sağlayıcıyla çalıştığı
için hiçbir şey görünmez, ama Firebase'de planlanan kayıtlar yalnız bunlar
(iOS: `docs/mac-devir.md` §4 B2) olduğu için yayın paketi giriş yapamaz.
`test/app_check_izi_test.dart` iki dalı da TAM eşitlikle çiviliyor
(derinlik sayan üçlü ayrıştırıcı); iç içe üçlü, DeviceCheck, ters dallar ve
debug dalına `??` kuyruğu ayrı ayrı denendi, hepsi kırmızı. İlk sürümün
açgözlü deseni iç içe üçlüyü yutup yeşil kalıyordu (çürütme turu). *(Düzeltme 2026-10-24: burada "HİÇBİR bekçisi
yok … satır tamamen silinse ne test fark eder" yazıyordu; bayattı.)*

Kapsamın kaynağı **servis kaydı değil ÖRNEK KİMLİĞİ** — koddan doğrulandı:
`FirebaseAppCheckPlugin.kt:46-48` sağlayıcı fabrikasını
`FirebaseAppCheck.getInstance(FirebaseApp.getInstance(appName))` üzerine
kuruyor, imzada servis adı geçmiyor. Mobilde **tek** `FirebaseApp` örneği
var (`main.dart:80`), `instanceFor` ve adlandırılmış ikinci örnek hiç yok —
yani Storage için ayrı bir etkinleştirme ne gerekiyor ne de mümkün.
Web'deki "örnek başına" tuzağı mobilde **maddi olarak yok**; oradan buraya
taşınan bir kaygı yanlış gerekçe olur.

Backend zorlamadan **etkilenmiyor** ve sebebi kova ayrılığı DEĞİL: tek
Storage yolu hesap silme (`account_service.py:243-266`), Admin SDK /
servis hesabı kimliğiyle ve `storage.googleapis.com`'a gidiyor — zorlanan
kapı `firebasestorage.googleapis.com`. ⚠️ O çağrı **best-effort**: engellense
hiçbir yerde kırmızı görünmez, uç yine `200 deleted` döner. Tek sinyali
`logger.warning` satırı ve silme raporunda `storageFiles` alanının HİÇ
olmaması olur.

App Check 1.15.8+43'te eklendi, yani **43 öncesi derlemeler artık
çalışmıyor**. Açıldığı an üç hesap 43'ün altındaydı (`erkandndr@gmail.com`
sürümü bilinmiyor, `yhykbr1984@gmail.com` ve `mhanifiaslan@yandex.com`
41); sahibin kararı: yeniden kursunlar.

**Web yüzeyleri App Check kullanıyor** (2026-09-26, ölçüldü). Zorlama
açılınca panel girişi ve şifre sıfırlama sayfası TAMAMEN kapanmıştı —
mobilde App Check 43'ten beri vardı ama webde hiç yoktu. Ortak kurulum
`web/assets/appcheck.js`. Üç incelik:

- Sağlayıcı **reCAPTCHA ENTERPRISE**, v3 değil: klasik reCAPTCHA
  kullanımdan kalktı, Firebase Console o formu artık doldurtmuyor. v3
  Firebase'e GİZLİ anahtar verdiriyordu; Enterprise yalnız SİTE anahtarını
  alıyor (paylaşılan sır yok). Site anahtarı herkese açıktır, depoda durur.
- App Check **örnek başınadır**. Panel, giriş penceresini same-origin
  yapmak için ikinci bir Firebase örneği (`'yonetim'`) kuruyor; yalnız
  birini etkinleştirmek diğerinin isteklerini jetonsuz bırakır.
- reCAPTCHA anahtarının izinli alan adları arasında
  **`rhytoai.firebaseapp.com` ŞART** — `authDomain` o ve giriş işleyicisi
  orada çalışıyor. Aynı alan adı Browser API anahtarının referrer
  listesinde de olmalı.

Doğrulama (tarayıcıda, uçtan uca): panelde `signInWithEmailAndPassword`
→ `auth/invalid-credential`, şifre sayfasında `applyActionCode` →
`auth/invalid-action-code`. İkisi de **App Check hatası değil**, yani kapı
aşılıyor.

**API anahtarları kısıtlandı** (2026-09-26): Android anahtarı → paket
`ai.rytho` + Firebase'de kayıtlı 5 SHA-1; Browser anahtarı → `rytho.app`,
`www.rytho.app`, `rhytoai.web.app`, `rhytoai.firebaseapp.com`. Bot kapısı
buydu ve kapandığı ölçüldü: kısıtsız istek artık
`Requests from this Android client application <empty> are blocked`.

**Alan adı taşınırken Firebase Auth yetkili alan listesi taşınmamıştı**
(ölçüldü 2026-09-26). Listede yalnız `rhytoai.firebaseapp.com`,
`rhytoai.web.app` ve iki ölü önizleme kanalı vardı; `rytho.app` yoktu ve
panelde Google ile giriş `auth/unauthorized-domain` ile düşüyordu. Hata
`authDomain`'den değil, **sayfanın kendi ana makinesinden** gelir — panel
`rytho.app`'te varsayılan örneği kullanıyor (`app.js`: `uygun` yalnız
`.web.app`/`.firebaseapp.com` için true), yani kod değişikliği gerekmedi.
`rytho.app` + `www.rytho.app` eklendi. ⚠️ Alan listesi **TAM DEĞİŞİMLE**
yazılır — PATCH gövdesine mevcut girdiler de konmazsa eski ana makinelerden
giriş kapanır:
`PATCH identitytoolkit.googleapis.com/admin/v2/projects/rhytoai/config?updateMask=authorizedDomains`

**Ortaklık (affiliate) programı CANLI** (OP-turu, 2026-09-27/28). Ayrıntı
`docs/ortaklik-programi.md`; buraya yalnız **makineler arası taşınmayan**
kısım yazıldı:

- Model: kullanıcıya ödül **YOK**; ortak, getirdiği kişinin **ilk**
  aboneliğinde sabit ₺ kazanır (`partners/{id}.rewardTry`, ortak başına,
  tavan 500). 15 gün sonra kesinleşir.
- Ortağın panosu `rytho.app/affiliate/` (2026-10-19'a kadar `/ortak/`; eski
  adres 301 ile yönlenir; varsayılan dil EN, menüden TR) — **hiçbir yerden linklenmez**, adres
  ortağa elden verilir; pano **tr/en** (2026-10-10: `?lang=` → tarayıcı dili
  → tr, elle QA `?lang=en`). Girebilmesi için custom claim şart ve o claim artık
  **panelden** basılıyor (Ortak erişimi → Erişimi aç). `tools/set_admin.py
  --partner` kurtarma yolu olarak duruyor.
- ⚠️ Claim **anında geçerli olmaz**: ortağın ID jetonu yenilenene kadar (en
  çok 1 saat ya da çıkış/yeniden giriş) eski hâl sürer. Bunu bilmeden test
  eden "açtım ama giremiyor" der. Claim'i olmayan hesap panoda "yetkin yok"
  DEĞİL **"böyle bir sayfa yok"** görür (panelin varlığı ele verilmesin).
- ⚠️ `/api/v1/partners/` öneki **sürüm kapısından muaf** ve öyle kalmalı:
  üç ucu da `x-app-build` göndermeyen istemciler çağırıyor (tarayıcı ×2,
  Cloud Scheduler). Bir tur boyunca muaf DEĞİLDİ ve gerekçesi yanlış bir
  yorumla çivilenmişti — eşik > 0 yazıldığı an ortak panosu ölür ve gecelik
  olgunlaştırma 426 yiyip **ortaklara para ödenmezdi**.
- Etiket iki kez yanlış kondu: sayılan şey "gelen" de "kuran" da değil,
  **"bağlantıyı kullanan"**. `redemptionCount` tek satırdan artıyor ve oraya
  iki yol ulaşıyor (kurulum + Install Referrer, VE kurulu uygulamada
  `/r/` derin bağlantısı); ikincisinde kurulum hiç olmaz.
- Tıklama sayacı herkese açık bir **yazan** uç: kapılar kod varlığı + kod
  başına dakikalık tavan. IP kovası tek başına yetmez — `x-forwarded-for`un
  ilk öğesi çağıranın denetiminde.

**Panele girebilen tek hesap:** `aslan.mh@gmail.com`, rol `owner`, üç giriş
yöntemi kayıtlı (google.com · password · phone). Paneldeki şifre **Firebase
Auth hesabının** şifresidir, Google hesabının değil — unutulursa "Şifreni mi
unuttun?" akışı kullanılır. Yetki `tools/set_admin.py` ile basılan custom
claim'den gelir, panelde kullanıcı listesi yoktur.

**Google Search Console doğrulandı** (2026-09-26, uçtan uca ölçüldü):
`web/googleb6af2cb19834337d.html`, üç ana makinede de 53 bayt birebir.
Google doğrulamayı periyodik tekrar okur ve Hosting her deploy'da `web/`
klasörünü **tamamen** değiştirir — dosya depodan çıkarsa başka bir makineden
yapılan ilk deploy onu siler ve mülk **sessizce** doğrulanmamışa döner.
Bekçi: `backend/tests/test_web_seo.py`. Aynı dosya dört şeyi daha sabitliyor:
sitemap beyanının ana makinesi, sitemap'in tüm indekslenebilir sayfaları
listelemesi, `x-default` hreflang, ve davet sayfası çifti — `/i/` **noindex
taşımalı ama taranabilir kalmalı**, çünkü `Disallow` indekslemeyi durdurmaz
ve Google noindex'i görebilmek için sayfayı çekebilmek zorundadır.

**B9 ve B10 KAPANDI** (2026-09-28, 1.17.0+46). İkisinin de kaydındaki
teşhis kısmen YANLIŞTI ve bu bir ders: bulgu notu bir hipotezdir, onarımdan
önce yeniden ölçülür.

- **B9** — "iki ayna da doküman yaratıyor" deniyordu; `search_mirror.ensure`
  doğduğu günden beri `exists` kapısı taşıyor. Tek suçlu
  `app_gate.remember_build`'di (`set(merge=True)` → `update`, iki satır).
  Kaydın "silinmiş uid ile yaratılmamış uid ayırt edilmeli" şartı da
  gereksiz çıktı — dokümanı doğurma işi aynanın değil.
- **B10** — "ödemiş kullanıcıya paywall"ın sebebi kayıtta yazan Riverpod
  halkası DEĞİLDİ (o düzeltme hiç uygulanmamış, kod yolu yok). Gerçek
  sebep `people_service.py` kontenjan 402'si: istemci `X-Paywall-Reason`
  başlığını "tokens mı değil mi" diye ikiye indiriyordu, Plus abonesi 11.
  kişiyi eklerken satış ekranı görüyordu.
- Onarımın kendi doğurduğu risk de kapatıldı: cüzdan tazelemesi artık her
  turda koştuğu için tek bir 429, dolu cüzdanı **0** gösterirdi.
  `WalletStatus.bilinmiyor` → ekranlar "—" çiziyor.

**Konsol borcu:** Play Console ürün adları hâlâ uygulamanın sözlüğüne
uymuyor (makbuzda "1000 Jeton", uygulamada "1000 kredi") — girilecek tam
metin `docs/store-launch.md`'de tabloyla hazır. Kapalı test sekmesindeki
**geri bildirim URL'si/e-postası boş**.
(App Check borcu KAPANDI — Storage da 2026-09-26'dan beri ENFORCED, bkz.
yukarıdaki tablo. Borç listesinde iki hafta yanlış durdu.)
(API anahtarı kısıtlaması borç DEĞİL artık — yukarıda kapatıldı.)

**Geliştirici adı — çözülmemiş çelişki.** Play'in kendi opt-in sayfası
(2026-09-26 ekran görüntüsü) daveti gönderen tarafı İKİ yerde **"Rhyto AI"**
diye adlandırıyor: uygulama adının altındaki gri satırda ve "… has invited
you to a testing program …" cümlesinde. Sahibi ise Console'daki alanın
**"Rytho"** okuduğunu söylüyor; `rytho.app` ve paket adı `ai.rytho` zaten
doğru. **Play bu ismi Firebase'den ALMAZ** — yani `rhytoai` proje kimliği
bunun açıklaması değil, öyle sanmak yanlış gerekçe olur.

Dışarıdan ölçülemedi: uygulama üretimde olmadığı için geliştirici sayfası
(`/store/apps/dev?id=5423180944698765`) 404 dönüyor, opt-in sayfası da
girişin arkasında. Tek kanıt o ekran görüntüsü.

Ad Console'da İKİ ayrı yerde duruyor — **Geliştirici hesabı → Hesap
ayrıntıları → *Geliştirici adı*** ve **Geliştirici sayfası**. Hangisi
yanlışsa o düzeltilir; ikisi de doğruysa opt-in sayfasındaki isim
propagasyon gecikmesidir. **Ayarlar sayfasında DEĞİL** (orada yalnız bağlı
hizmetler, e-posta listeleri ve para kazanma var) — bir kez orada arandı.

**Mağaza görselleri bayat olabilir** — `store/play/` kareleri ham cihaz
yakalamalarından üretiliyor, yani koddaki metin düzeltmesi kareye
yansımaz. `shot-1-sky.png` düzeltilmiş bir kusuru göstermeye devam
ediyor. Kural: **piksel elle düzenlenmez**, ya kadraj ya yeniden yakalama.

### Play Console tuzakları (ölçüldü, gün kaybettirdi)

**UYGULAMA FİYATI ≠ RYTHO+** (2026-10-22, ölçüldü). Mağaza sayfası "Satın
al — ₺179,99" gösteriyordu: uygulama ÜCRETLİ listelenmişti (eski abonelik
fiyatı uygulama fiyatına girilmiş). Bir kullanıcı (operatör faturasıyla)
uygulamayı satın aldı ve Rytho+ alamadı — sipariş türü "Ücretli uygulama",
RevenueCat'e HİÇ gitmez; Plus yalnız `rytho_plus_monthly` aboneliğinden
(RevenueCat → webhook) gelir. Sahip kararı: model **ücretsiz indirme +
abonelik**; Console'da Uygulama fiyatlandırması → Ücretsiz (geri alınamaz).
Teşhis sırası: kullanıcı belgesinde `private/subscription` yok + `revenueEvents`
0 → Console sipariş türüne bak. Aynı gün ilk GERÇEK abonelik (PRODUCTION,
₺239,99, 2026-10-21) sürüm 53'te sorunsuz işlendi — satın alma hattı sağlam.

**"Reklam kimliği beyanı eksik" hatası ETKİN TÜM KANALLARA bakar.** İzni
44'te kaldırdık ama hata sürdü: **dahili test** hâlâ 41'deydi ve o pakette
AD_ID vardı. Kapalı testi temizlemek yetmedi. 10 saniyelik teşhis: formda
**Evet** → kaydet. Evet'te AD_ID'siz sürüm yalnız uyarılır, Hayır'da
AD_ID'li paket varsa **engellenir**; Evet'te gönder açılıp Hayır'da hata
dönüyorsa suçlu bir kanalda duran eski pakettir. Kod suçlanmadan önce bu
yapılır.

**Sürüm kodu uygulama genelinde benzersizdir, kanal başına değil.** Aynı
AAB'yi ikinci bir kanala **yükleyemezsin** ("sürüm kodu daha önce
kullanıldı"). Kanallar arası taşıma **yalnız yukarı** çalışır:
dahili → kapalı → üretim, "Sürümü yükselt" ile.

**Hedef kanalda taslak sürüm varsa yükseltme kapalı kalır**
("Kanalın zaten taslak bir sürümü var"). Ya taslağı sil, ya da taslağı
düzenleyip paketi **kitaplıktan** seç (yeniden yükleme değil, o yüzden
"kod kullanıldı" hatası vermez).

### Derleme ortamı tuzakları (2026-09-25)

**Flutter, JAVA_HOME'u değil Android Studio'nun JBR'sini kullanabiliyor.**
`JAVA_HOME` Adoptium 17'yi gösterirken derleme JBR **21** ile koşuyordu.
`flutter doctor -v` hangi Java'yı kullandığını söyler; sabitlemek için
`flutter config --jdk-dir="<jdk17 yolu>"`.

**Gradle'ın JVM'i çökebiliyor** (`EXCEPTION_ACCESS_VIOLATION`). Çökme
GC'de DEĞİL `MethodHandleNatives.resolve`'daydı ve hem JBR 21'de hem
Temurin 17'de tekrarladı — yani JDK satıcısı değildi. `flutter clean`
sonrası tekrarlamadı. Çökme günlüğü `apps/mobile/android/hs_err_pid*.log`;
**çöken iş parçacığına bak**, "GC" görünce bellek sanma.

## 7. iOS durumu

**Tam envanter ve sıralı yol haritası: `docs/mac-devir.md`.** Burada yalnız
özet ve tuzaklar var. Denetim 2026-09-26, 63 ajan, 54 onaylanmış bulgu.

iOS derlemesi/imzalaması/yüklemesi **yalnız macOS**'ta yapılabilir.

**Depoda BİTTİ** (2026-09-26): `ios/Podfile` (`platform :ios, '15.5'`
açık) · deployment target 15.5 · App Check Apple sağlayıcısı
(`providerApple`) · `aps-environment` Debug/Release ayrı iki entitlements
dosyasıyla · `UIBackgroundModes/remote-notification` ·
`ITSAppUsesNonExemptEncryption` · `STRIP_STYLE = non-global` · zorunlu
güncelleme ve abonelik yönetiminde iOS dalı · mağaza-nötr metinler.

**Firebase iOS kaydı AÇILDI** (2026-09-26): bundle `ai.rytho`,
`GoogleService-Info.plist` depoda (`ios/Runner/`), Google girişi
`Info.plist`'e bağlandı (`CFBundleURLTypes` + `GIDClientID`, ikisi de
plist'ten okunarak), iOS API anahtarı `ai.rytho` ile kısıtlandı (27 API
hedefi korunarak). Plist Runner hedefine **eklendi** (Mac, 2026-09-26) ve
derlenen `Runner.app` içinde olduğu ölçüldü.

**Mac ortamı (2026-09-26):** Xcode 27 bu depoyu derleyemiyor (RevenueCat
Swift 6.4'te kırık + `lipo` değişikliği); **Xcode 26.6 yan yana kurulu**
(`/Applications/Xcode-26.app`) ve `xcode-select` ona bakmalı —
`DEVELOPER_DIR` tek başına yetmiyor. Uygulama simülatörde **açılır**
(`e4789d4`: ML Kit yalnız simülatör derlemesinden çıkarıldı, çağrıya açık
`SIMULATORDE_YOK` hatası döner); yüz okuma, App Attest, push ve Universal
Link yalnız cihazda. Ayrıntı: `docs/mac-devir.md` §7.

**Mac'in iOS işi 2026-10-22'de bu dala birleşti** (`8d6f67b`;
`ios-hazirlik` artık izlenmez). U-kimlikli App Store uyum kaydı
`docs/ios-uyum-denetimi.md` (55 kayıt + birleşme notları). ⚠️ Ders: o iş
dört hafta push edilmeden Mac'te kaldı ve Windows habersiz ilerledi —
belgeler "TEAMID yer tutucu", "imza yok" diyordu, 29 dosyada çakışma
çıktı. **İki makinede çalışırken iş push edilmeden "bitti" sayılmaz.**

⚠️ **Hosting deploy'u BEKLET** (2026-10-22; gerekçe 2026-10-23'te
yenilendi): birleşmiş `web/legal/` gizlilik metni yapay zeka onayının
kurulumun ilk adımındaki AYRI ve ZORUNLU kutuyla alındığını söylüyor;
canlıdaki Android 1.20.0+53'te o kutu yok. Kutulu ilk paket (Android 54 ya
da iOS) yayınlanmadan `firebase deploy --only hosting` canlı uygulama için
yanlış beyan yayınlar. Ayrıntı `docs/mac-devir.md` üst kutu. Kilit iOS'u
iki yerden tutuyor (2026-10-23): AASA (cihazda Universal Link — canlı ve
Apple CDN hâlâ `TEAMID` + yalnız `/i/*`) ve gizlilik URL'si (inceleme).
Seçenekler A–D: `docs/mac-devir.md` §4 "Deploy bağımlılıkları ve hosting
kilidi". **Sahip kararı 2026-10-24: A + C** — hosting Android 54'ün yayın
günü deploy edilir; iOS o güne dek iç TestFlight'ta bekler, Universal Link
o zamana kadar ölçülmez. Aynı gün: Mac/Vision Pro erişimi KAPATILACAK
(App Store Connect kaydı açılınca, C6; App Attest Mac'te yok) ve bağlantı
testi AYRI bir test ortağıyla yapılacak (§4 4.10).

⚠️ **Yapay zeka onayı = kurulumda ikinci kutu, KAPI YOK** (sahip kararı
2026-10-22/23). Mac'in U06'sı (her açılışta soran onay sayfası, "Şimdi
değil" sonrası kapanan özellikler, sunucuda 403 ve şablona düşen bildirim,
Profil'de geri alma anahtarı, `aiConsentMinBuild` eşiği) Android'e
birleşince sahip "uygulamamın kullanımını zorlaştırıyorsun, bana danışmadan
politikalarımı değiştiremezsin" dedi; Eylül'deki tek kayıtlı karar "ekran
iki platformda"ydı, sürtünme hiç sorulmamıştı. Hepsi kaldırıldı. Bugünkü
model: şartlar kutusunun altında ayrı, zorunlu ikinci kutu; ikisi
işaretlenmeden Devam açılmaz. Kutu metni sağlayıcı adı TAŞIMAZ ("bugün
Gemini yarın Claude"); sağlayıcıyı gizlilik politikası adıyla anar —
sağlayıcı değişirse yalnız politikanın dört kopyası değişir. Geri alma =
hesabı silmek. Bu modelin Apple 5.1.2(i) riski (inceleyici sağlayıcıyı
adıyla anan ekran isteyebilir) sahip kararıyla KABUL EDİLDİ (2026-10-24):
kutu adsız kalır, Apple itiraz ederse o gün yeniden konuşulur. 53'ten güncelleyen hesap hiçbir şey görmez, adına kayıt
yazılmaz; politikadaki geçiş cümlesi onları anlatır. Kanıt `POST
/api/v1/account/ai-consent` → `users/{uid}/private/aiConsent`; sunucu ilk
onay anını korur. ⚠️ `kTermsConsentVersion`/`kAiConsentVersion` metin
değişti diye ARTIRILMAZ: bayrak anahtarı sürümü taşıdığı için artış mevcut
hesaplar adına kayıt yazdırır. **Kural: onay/izin akışını, özellik kısıtını
ya da hukuk metnini değiştiren her şey — mağaza uyumu gerekçesiyle bile —
önce sahibe sorulur.**

⚠️ **Android 54'e giden sıra** (2026-10-23, Mac'ten yazıldı; adımlar Windows'un):
1. `git pull`.
2. pubspec `+53` → `+54`, sonra `infra/build-aab.ps1`. `app_settings`
   7.0.0 ile Android derlemesi henüz ÖLÇÜLMEDİ.
3. Deploy'dan ÖNCE üretimde SALT OKUMA sayım: `users/X/blocked/Y` kaydı
   olup X–Y arasında iki kenarı da `accepted` olan çiftler. 53'te engeli
   kaldıracak ekran yoktu, tek "barışma" yolu yeniden eklemekti; yeni
   kurallar ve backend bu çiftlerde 53 kullanıcısının tepkisini ve rehber
   eşleşmesini sessizce keser. Sayı sıfır değilse karar sahibin.
4. 54'ü yüklemeden ÖNCE: `firebase deploy --only firestore:rules --project
   rhytoai` + `infra/deploy-backend.ps1` (U17 kuralı ve sunucusu, AI onay
   kanıt ucu). Ters sırada 54'ün Engellenenler ekranındaki sözler yanlış
   olur ve aradaki dönemde kurulum yapanların onay kanıtı kalıcı
   kaybolabilir (bayrak yalnız o cihazda yaşar).
5. 54 cihazda: kurulumun ilk adımında iki kutu, biri işaretliyken Devam
   kapalı; kurulum bitince Firestore'da `users/{uid}/private/aiConsent`
   oluşuyor; 53'ten güncelleyen cihazda hiçbir şey sorulmuyor; iki hesapla
   engelleme (davet, tepki, Engellenenler, rehber önerisi).
6. 54 yayına çıktığı gün hosting deploy'u (gizlilik metni + AASA `/r/*`).
7. Konsol: Play Veri güvenliği ve App Privacy formlarını yeni gizlilik
   metniyle karşılaştır (`docs/store-privacy-labels.md` yaşadığın şehri,
   arkadaşla ortak harita verisini ve I Ching soru kapısını saymıyor).

⚠️ **Kayıt bir kez `app.rytho` diye açıldı** (`ai` yerine `app`). İnen
plist o kimliği taşıyordu ve `FirebaseApp.configure()` uyuşmazlığı **hata
değil UYARI** ile geçiyor: uygulama "çalışıyor" görünürken App Check (App
Attest kimliğe bağlı), Google girişi, push ve Crashlytics tek tek sessizce
bozulurdu. Firebase bundle kimliğini **düzenlettirmiyor** — kayıt silinip
yeniden açıldı. Bekçi: `backend/tests/test_ios_config.py`, kimliği beş
dosyada birden bağlıyor (pbxproj ×3, gradle, AASA, plist).

**U56 (2026-10-22):** birleşmiş dal iOS için derlenmiyordu (aşağıdaki
`app_settings` tuzağı); 7.0.0'a sabitlendi, iOS simülatör derlemesi geçti.
⚠️ Android derlemesi 7.0.0 ile henüz ÖLÇÜLMEDİ (Windows, `build-aab.ps1`).
**Hesap işleri:** üyelik ücretli ve etkin (sahip teyidi) ·
Xcode'da takım hesabı (bu Mac'te imza sertifikası 0) · APNs anahtarı ·
gerçek `appl_` RevenueCat anahtarı (şu anki `test_` önekli) · App Store
Connect kaydı ve IAP ürünleri · Firebase'de Apple sağlayıcısı (U01) ·
Apple ile Giriş anahtarı, Services ID ve e-posta kaynağı kaydı (U15/U22)
· Firebase iOS uygulamasında Team ID + App Check'te App Attest kaydı
(U08). Tam yollar `docs/mac-devir.md` §4 A2, A4, A5, B1, B2, C7.
→ **Sahip beyanı 2026-10-24: A2, A4, A5, B1, B2 ve C7'nin anahtar/Services
ID/OAuth yarısı YAPILDI** (APNs anahtarı "Sandbox & Production", Firebase'de
iki satıra da aynı anahtar). Konsol ekranları görülmedi; cihaz çoğunu
DOLAYLI doğruladı (iPad, Profile, geliştirme imzası, 2026-10-27/28): App
Attest kabul edildi — temiz kurulumda giriş, Firestore okuma/yazma, yüz
okuma (B1/B2); geliştirme profili A2'nin dört yetkisini taşıyor (portal
görülmedi; sahip mi otomatik imza mı açtı, bilinmiyor); Apple ile Giriş
çalıştı (A4; U01 onarımından SONRA, bkz. iOS tuzakları); silmeden sonra
Rytho Ayarlar'daki Apple ile Giriş listesinden kalktı (C7 anahtar yarısı,
U15; iki silmede — ama yeniden girişte Apple'ın ilk-kez sayfası dönmedi,
açık, bkz. iOS tuzakları); Apple sayfası kapatılınca hesap silinmedi ve
kullanım sürdü. Ölçülmedi: cihazda push (A5), Universal Link, StoreKit,
dağıtım imzası, U22 gönderici kaydı (sahibin yapıp yapmadığı bilinmiyor).
Kalanlar: App Store Connect kaydı + IAP, `appl_` anahtarı. *(Ek 2026-10-24: Apple ile Giriş ve App Attest
önkoşulları bu listede yoktu.)* Team ID `292WJ9TP74` (2026-09-27): AASA'ya
ve pbxproj'e yazıldı (`CODE_SIGN_STYLE = Automatic`); AASA `/i/*` + `/r/*`
taşıyor, hosting yayını bekliyor.
→ **"İmza sertifikası 0" BAYAT (ölçüldü 2026-10-23):** anahtar zincirinde
1 `Apple Development` kimliği (OU `292WJ9TP74`, 2026-10-22 → 2027-10-22),
Xcode'da ücretli takım hesabı ekli (`Individual`). Bu Mac'te hâlâ 0
(`security find-identity`, 2026-10-28): Apple Distribution sertifikası.
Artık VAR: USB'li iPad ve takımdaki kaydı (`flutter run --profile`
otomatik imzayla kaydetti; portal görülmedi, profilden okundu) — "iOS
Team Provisioning Profile: ai.rytho" (geliştirme, 2026-10-27 → 2027-10-27,
1 cihaz = bu iPad; aps development, applesignin, associated-domains,
appattest). App Store Connect kaydı **ölçülemedi** (hesap girişi yok).
*(Düzeltme 2026-10-28: burada yerel provizyon profili ve bağlı cihaz da
"0", takımda kayıtlı cihaz "ölçülemedi" yazıyordu; iPad turuyla
bayatladı.)*

**Hazırlık hükmü (2026-10-23, Mac, `ba6108b`; cihaz yarısı 2026-10-27/28):**
gerçek cihazda geliştirme testi BAŞLADI (iPad, Profile; iPhone ve cihazda
Debug ölçülmedi); iç TestFlight ve App Store incelemesi **hazır değil**.
*(Düzeltme 2026-10-28: burada "gerçek iPhone'da Debug testi … üçü de hazır
değil" yazıyordu.)* Kod
tarafı büyük ölçüde hazır (imzasız Release derlemesi geçti, 1.20.0 (53));
kalan: sahibin konsol işleri, üç deploy (kurallar + backend BİRLİKTE ve
yukarıdaki sıranın adım 3 sayımından sonra — backend `/ai-consent` canlıda
404; hosting/AASA `e8cc253`'te) ve kod işleri. TestFlight'ın önünde U05
(iOS yayın kapısı; kod yarısı `09bbe23`, 2026-10-23/24 — kalan konsol, ilk
imzalı IPA, derleme numarası kararı); incelemenin önünde U17 şikâyet
görünümü, U18 inceleme notları, U16 (App Store paket iadesi yok sayılıyor
→ bedava kredi yolu; düzeltme + backend deploy, iOS satışı başlamadan
önce), U28, U32, U35 ve U37 Koşullar maddesi (tam liste `docs/mac-devir.md`
§4 C13).
*(Düzeltme 2026-10-24: burada "kalan sahibin konsol işleri + üç deploy"
yazıyordu; kod işleri düşmüştü.)* Sıralı sahip adımları, tam konsol yolları, hosting kilidinin seçenekleri (sahip kararı A + C, 2026-10-24) ve
derleme numarası önerisi (iOS en az 54): **`docs/mac-devir.md` §4 Aşama
A/B/C.** Konsol ekranlarının hiçbiri bu Mac'ten görülmedi; cihazın
DOLAYLI sonuçları (2026-10-27/28) yukarıdaki sahip beyanı satırında.

### iOS tuzakları (ölçüldü)

**`platform :ios` şablonda YORUMLU gelir.** Flutter, Podfile yoksa
şablondan üretir ama o satır kapalıdır; CocoaPods hedefi pbxproj'deki
değerden okur ve `google_mlkit_face_detection` 15.5 isterken 13.0 görüp
düşer. Yani "Podfile yok" tek başına doğru teşhis DEĞİLDİ — dosya
üretilse bile sorun çözülmezdi. Podfile artık depoda ve satır açık.

**15.5 keyfî değil**, paketlerin dayattığı tabandır: ML Kit 15.5,
Firebase 15.0. Düşürmek ancak yüz okumayı iOS'ta kapatmakla mümkün.

**`aps-environment` iki dosyada — gerekçesi YANLIŞ yazılmıştı.**
`Runner.entitlements` (development; Debug + Profile) ve
`RunnerRelease.entitlements` (production; Release) ayrı, pbxproj Release
bloğu ikincisine bakıyor, ikisi **yalnız o değerde** farklı. Eski gerekçe
("Release arşivi `development` çıkarsa SANDBOX jetonu alır, sunucu üretim
APNs'ine gönderir — TestFlight'ta çalışır, mağazada ölür") iki yerden
çöktü (Apple belgesi + pod kaynağı, okundu 2026-10-24): Xcode
`aps-environment` değerini provizyon profiline göre yazar ve dağıtım
profiliyle imzalanan paket — TestFlight DAHİL — production kullanır, yani
TestFlight ile mağaza aynı ortamda, biri çalışıp öteki ölemez; FCM de
ortamı (olağan yolda, swizzling açık) yetki dosyasından değil, SDK'nın
gömülü profilden okuyup jetonla bildirdiği sandbox bayrağından seçer
(`FIRMessagingUtilities.m`, `FIRMessagingTokenManager.m`); APNs jetonu
FIRMessaging hazır olmadan gelirse eklentinin derleme zamanı DEBUG etiketi
geçer, Profile'da sandbox jetonu production etiketlenebilir — Profile'da
push testi güvenilmez. İki dosyanın gerçekten gerekip gerekmediği
— ya da Release'in geliştirme imzasıyla "doesn't match … aps-environment"
ile düşüp düşmediği — ilk imzalı Release'te ölçülür (`docs/mac-devir.md`
§4 B9); o zamana dek dosyalar olduğu gibi kalır.

**Dosyayı `Runner/` altına kopyalamak pakete SOKMAZ.** `project.pbxproj`
klasör-senkronlu grup kullanmıyor (`objectVersion = 54`,
`PBXFileSystemSynchronizedRootGroup` yok) ve Copy Bundle Resources'ta
yalnız dört girdi vardı. `GoogleService-Info.plist` eklendi (beşinci
girdi); `InfoPlist.strings` `en` + `tr` varyant grubu olarak bağlandı (U27,
`54130b9`; `knownRegions` `(en, Base, tr)`, ölçüldü 2026-10-22) — İngilizce
cihaz İngilizce izin metni görür.

**`AppDelegate`'e bildirim delegesi EKLENMEZ** (U14, kaynak okumasıyla):
delegeyi `firebase_messaging` alıyor; README'nin istediği satır eklenirse
`willPresent` iki eklentiye birden gider. Ön plan push'unu iOS'ta FCM
kendisi gösteriyor (`notifications.dart` `iosOnPlanSunumunuAc`); bekçi
`test/bildirim_ios_test.dart`. Kalan yalnız cihaz doğrulaması.

**`app_settings` 8.0+ iOS'ta yalnız Swift Package Manager** (U56, ölçüldü
2026-10-22). Depo SPM'i bilerek kapalı tutuyor (`pubspec.yaml`
`enable-swift-package-manager: false`; U25: SPM + Pods Google
kütüphanelerini iki kez bağlıyordu) ve Flutter bu durumda derlemeyi
"only compatible with Swift Package Manager" diye DURDURUYOR. `flutter
test` ve `analyze` yeşil kalır — kusur yalnız `flutter build ios`ta
görünür. Yeni bir eklenti eklerken iOS'ta podspec'i var mı bak.

**Simülatörde çalışmayan ikili:** TFLite ve App Attest. İkisi de gerçek
cihaz ister. iPad'de ikisi de ÇALIŞTI (Profile, geliştirme imzası,
2026-10-27/28): ML Kit yüz algılama + TFLite segmentasyon (sahip gözlemi;
günlükte TFLite çalışma zamanı ve XNNPACK CPU delegesi), App Attest kabul
edildi (dolaylı: temiz kurulumda giriş ve Firestore çalıştı). Dağıtım
imzalı pakette ölçülmedi. Günlükte iki kez ML Kit `CCTClearcutUploader`
çoklu örnek uyarısı (pil) — incelenmedi.

**Gerçek cihazda App Check iki ayrı konsol adımı ister** (kaynaktan
ölçüldü 2026-10-23): Debug `AppleDebugProvider` kullanır. Define dosyasında
`APP_CHECK_DEBUG_TOKEN` YOKSA eklenti HER kurulumda yeni bir debug jetonu
basar — Firebase → Security → App Check → Apps → `ai.rytho` → Manage debug tokens'a eklenmeden
giriş/Firestore/Storage reddedilir (şemada sabit jeton yok).
**2026-10-24'ten beri sabit jeton var:** `APP_CHECK_DEBUG_TOKEN` doluysa
(`main.dart` `kAppCheckDebugToken`) her Debug kurulumu o jetonu kullanır ve
Firebase'e bir kez eklenir. Simülatörde ölçüldü: kayıtsızken
`exchangeDebugToken` 403 ve giriş "Bir şeyler ters gitti", kayıtlıyken 200
ve giriş çalıştı. Aynı define dosyasıyla derlenen cihaz Debug'ına da aynı
jeton gider — cihazda ölçülmedi. Jeton sırdır (depoya, sohbete yazılmaz);
imzasız Release paketinde 0 kez geçtiği ölçüldü ve `infra/build-ipa.sh`
paket kapısı her yayın paketinde yeniden ölçer. Release/Profile/TestFlight
`AppleAppAttestProvider` kullanır — Firebase iOS uygulamasında Team ID +
App Check'te App Attest kaydı + App ID'de App Attest yeteneği ister.
Belirti App Check'e özgü bir hata DEĞİL: iOS'ta `activate()` yalnız
sağlayıcıyı kaydeder ve düşmez; kayıtsız jeton ancak jeton değişiminde
reddedilir. Kullanıcı App Check'e özgü bir mesaj görmez: giriş genel "Bir
şeyler ters gitti. Tekrar dene." metniyle düşer (`authFailed`; simülatörde
ölçüldü 2026-10-24) — yanlış şifre metninden ("Giriş yapılamadı. Şifren
hatalı olabilir…") farklı, ama başka beklenmedik hatalardan ayırt edilemez;
Firestore/Storage'da izin hatası çıkar (`core/app_check_izi.dart`). Debug'da tek
iz Xcode konsoludur; Release/TestFlight'ta Crashlytics'e `app-check-token`
kaydı düşer (U30). Teşhisi `activate()` hatasında ARAMA — `main.dart`'taki
catch bu durumda hiç çalışmaz. *(Düzeltme 2026-10-24: burada "`activate()`
hatası yutulduğu için belirti sessiz giriş ekranı" yazıyordu; yanlış
gerekçeydi.)*

**`test_` RevenueCat anahtarı Release/Profile'da açılışta BİLEREK çöker**
(RevenueCat 5.67.1 `Configuration.swift:471-495`, `#if !DEBUG` →
`fatalError`; anahtar derlenmiş pakette bulundu, 2026-10-23). İmzasız
Release derlemesi bununla "başarılı" çıkıyor — Android'deki 1.5.0+17
sınıfı. Debug çökmez ama satın almalar Test Store simülasyonudur. "Yalnız
iOS anahtarını boşalt" çaresi YETMEZ: `billingConfigured` iki anahtardan
birine bakıyor, Android anahtarı onu true tutar ve giriş yolu
yapılandırılmamış SDK'ya `logIn` gönderir (U05).
→ **U05 kod ağı (`09bbe23`, 2026-10-23/24) sonrası:** `rcEtkinAnahtar` yalnız
çalışılan platformun anahtarına bakar; Release + Profile'da `test_` =
yapılandırılmamış, `configure` hiç çağrılmaz; `ensureBillingIdentity` ilk
satırda kapı (geri yükleme düğmesi kapısızdı ve yapılandırılmamış SDK'da
PurchasesHybridCommon 17.55.1 `CommonFunctionality.swift:18-22`
`fatalError` yoluna gidiyordu). Yani `test_` anahtarlı Release/Profile
artık çökmez, satın alma "kullanılamıyor" der; ayrı anahtarsız define
dosyası gerekmez (kodda doğrulandı; `test_` önekli iOS anahtarlı define
dosyasıyla derlenen **Profile** paketi iPad'de açıldı ve kullanıldı,
çökmedi — 2026-10-27/28; Release ve satın alma ekranının "kullanılamıyor"
demesi ölçülmedi). Sessizliği
`infra/build-ipa.sh` durdurur (§4). `Purchases.*` çağıran her yer
`billingConfigured` kapısının arkasında DURMAK ZORUNDA; bunu
`test/satin_alma_yapilandirma_test.dart` tutuyor (kanal kaydedicisiyle
davranış + kaynak bekçisi: kayıtsız yeni çağrı, alta kayan, yoruma
alınan ya da parantezsiz `if` gövdesine konan kapı KIRMIZI — U05 2. tur +
2026-10-24 mutasyon turu; 1. turun çürütmesi kapıları hiçbir testin
tutmadığını mutasyonla ölçmüştü).

**Apple kimliği genel `OAuthProvider` ile KURULMAZ** (U01, iPad'de ölçüldü
2026-10-27/28): `OAuthProvider('apple.com').credential(...)` signInMethod
`oauth` taşır, firebase_auth 6.5.6 iOS eklentisi onu genel dala yollar ve
HER deneme `invalid-credential` "Invalid OAuth response from apple.com"
alır. Ekranda "E-posta veya şifre hatalı." yazıyordu — şifre formunun hata
haritası sosyal girişe de uygulanıyordu, kusur şifre hatası kılığındaydı.
Doğrusu `AppleAuthProvider.credentialWithIDToken`; giriş ve silme öncesi
yeniden doğrulama (o da genel kimliği kullanıyordu) tek kurucudan geçer
(`appleKimligi`, `core/auth_service.dart`). Onarımdan sonra iPad'de Apple
ile giriş birden çok kez yeni hesap açtı. Sosyal girişte şifre formunda
başka anlam taşıyan kodlar (`invalid-credential`, `wrong-password`,
`user-not-found`, `operation-not-allowed`) artık genel "Bir şeyler ters
gitti"ye iner (`sosyalGirisHataMetni`); arıza kodları (`invalid-credential`,
`operation-not-allowed`, `internal-error`, `unknown`) yayında Crashlytics'e
`social-signin-firebase` diye yazılır.

**`flutter build ios` cihazı takıma KAYDETMEZ** (ölçüldü 2026-10-27):
"Your team has no devices" ile düşer; `flutter run --profile -d <cihaz>`
otomatik imzayla cihazı kaydedip geliştirme profilini üretir. Önce cihazda
Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu açılır — kapalıyken
xcodebuild "Unable to find a destination" der. Uygulama iPad'de iPhone
uyumluluk penceresinde açılır (`TARGETED_DEVICE_FAMILY = 1`, üç
yapılandırmada): orada görülen yerleşim iPad yerleşimi değildir.

**Firebase `revokeToken`'ın hatasız dönmesi Apple'da iptal DEĞİL** (U15):
Firebase REST belgesine göre tekrar eden istek yok sayılıp hemen döner,
Apple `/auth/revoke` önceden geçersizlenmiş jetona da 200 verir. Ölçü
Ayarlar → [ad] → Oturum Açma ve Güvenlik → Apple ile Giriş listesi (ya da
account.apple.com, Apple'ın iptal e-postası). ⚠️ Açık: silmeden sonra
yeniden girişte Apple'ın ilk-kez sayfası (ad + e-posta paylaş/gizle)
DÖNMEDİ, kısa "Devam" çıktı; TN3194 dönmesini ima ediyor, gecikmeye dair
kaynak bulunamadı. ⚠️ Açık: yeniden doğrulama onarımından önceki bir
pakette Apple sayfası bir kez `AuthorizationErrorCode.unknown` (1000)
döndü ve hesap silinmedi; kod 1000'de silmeyi SÜRDÜRÜR, nedeni ölçülmedi
(sunucu günlüğü bu Mac'ten okunamıyor).

**Günlükte bir satırın YOKLUĞU ancak o koşuda başka `flutter:` satırları
görünüyorsa kanıttır** (ölçüldü 2026-10-27/28): bir koşuda `flutter run`
uygulamayı Xcode otomasyonuyla başlattı ("Xcode is taking longer than
expected to start debugging") ve `print` çıktısı günlüğe HİÇ düşmedi.
Cihaz ekran görüntüsü `xcrun devicectl device capture screenshot --device
<cihaz> --destination <dosya.png>` ile; `flutter screenshot` "not
supported" der.

**Bu bölümde iki kez bayat not yakalandı** (2026-09-26): "associated-domains
hâlâ `rhytoai.web.app` diyor" yazıyordu — oysa `Runner.entitlements` iki
alan adını birden taşıyor, önceki bir turda düzeltilmiş ve not
güncellenmemişti. İkincisi yukarıdaki Podfile gerekçesiydi. 2026-10-22'de
üç tane daha: "uygulama simülatörde hiç açılmaz" (`e4789d4` onarmıştı),
"`en.lproj` hâlâ bağlı değil" (U27 bağlamıştı), "bildirim delegesi
cihazda ölçülecek" (U14 kaynaktan çözmüştü). 2026-10-23'te iki tane daha:
"bu Mac'te imza sertifikası 0" (ölçüm büyük olasılıkla sertifika oluşmadan
önce alınmış ve bir daha tekrarlanmamıştı — ölçüm anı kayıtlı değil; App
Check `updateTime` dersinin aynısı) ve uyum kaydında "U52 açık" (`eed33c7`
işlevsel kusuru kapatmıştı; lisans kaydı maddesi hâlâ eksik, kayıt
2026-10-24'ten beri `⏳ açık (kısmen)`). 2026-10-24'te o turun kendi
belgesinde üç tane daha yakalandı: ölçülmemiş konsol durumları ("kayıtlı
cihaz 0", "ASC kaydı yok") ölçülmüş gibi yazılmıştı, App Check belirtisinin
gerekçesi kodla çelişiyordu, backend deploy'u sayımı atlayıp öne
alınmıştı. **Bu bölümdeki hiçbir iddiaya ölçmeden güvenme.**

---

## 8. Belgeler

`docs/mac-devir.md` — **Mac kurulumu ve iOS yol haritası** (yeni makineye
geçerken ÖNCE bu okunur) ·
`docs/ios-uyum-denetimi.md` — App Store uyum kaydı (U01…U56) ·
`docs/test-raporu.md` — senaryo listesi ve bulgular (B1…B10) ·
`docs/konsol-gorevleri.md` — Firebase/Play/Cloud konsol işleri ·
`docs/store-launch.md` — mağaza metni, yasak dil, görsel borçları ·
`docs/maliyet-calismasi.md` — birim maliyetler ve marj ·
`docs/ozellikler.md` — ücretsiz/Plus tarifesi (koddan sapmamalı) ·
`docs/design/design-system.md` — hareket ve tipografi doktrini.

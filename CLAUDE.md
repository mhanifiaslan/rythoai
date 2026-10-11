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
| `apps/mobile/dart_defines.local.json` | Paket RevenueCat anahtarsız çıkar; cihazda **tüm satın almalar** "kullanılamıyor" der. Derleme BAŞARILI görünür. |
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

Bir kez 1.5.0+17 düz komutla üretildi: derleme başarılı, testler yeşil, imza
doğru — kusur ancak mağaza ekranında görüldü.

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
`` + KAPALI ek listesi, bir de doğrudan-kalıp tuzak-kelime bekçisi
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

---

## 6. Bugünkü durum (2026-10-10)

Dal: `yuz-okuma-cihaz-usti-olcum`. Sürüm **1.19.0+49**, AAB **üretildi**
(`10-10 19:53`, 114,0 MiB, **altı** kapı da OK — D3 ve R8 onarımı içeriyor)
ama **Play'e HENÜZ YÜKLENMEDİ**; plan tek büyük sürüm **1.20.0+50**, 49'luk
AAB yalnız ölçüm artefaktı.

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
Backend rev **00109-vdx** — `10-10` akşam dağıtıldı (S1 sohbet personası +
D0 `fallback`/sözlük/BaZi `unspecified` CANLI), trafiğin %100'ü, `/health`
**200** (`gcloud run services describe` + curl ile deploy logundan BAĞIMSIZ
doğrulandı). Bir önceki 00108 (`10-10` sabah) D0 ÖNCESİYDİ.

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
| D5 ana ekran+profil (tek "Bugün", AsyncBolum, günlük satırı altta, kabuk niyeti, hikâye sükûneti, çıkış onaylı, abonelik "—", saat uydurulmaz) | ✅ Flutter 1194, 70 mutasyon | `3dfe7a3` |
| D6 derinlik (OkumaKabi 9 yüzey, çark çizgi dili + salt önizleme, Çevrem/kişi onayları, sohbet hata balonu + 402 tek yol) | ✅ Flutter 1441, 89/89 mutasyon | `707dd4a` |
| D7 para · D8 cırcır+l10n+belge | bekliyor | — |
| **S1 sohbet personası** (plan dışı, sahip şikâyeti 2026-10-10; yalnız backend — kapı ``, yetki alanı, `persona_guard`, `tools/sohbet_olc.py`) | ✅ pytest 2750, 66+7 mutasyon · ✅ CANLI rev 00109 | `5da5ed2` |

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
(abonelik neti $3,00). Ayrıntı ve bedel tablosu
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

⚠️ `bazi_tab.dart:230` `chart['missing_elements'] as List` **hoşgörüsüz
cast**: alan gelmezse `Null is not a List` fırlar ve BaZi sekmesinin
TAMAMI çöker. Yıl Haritası aynı riski bir üretim olayından sonra hoşgörülü
ayrıştırmayla kapatmış (`solar_return_screen.dart:69-71`), BaZi kapatmamış.
Ölçüldü ama onarılmadı — bu turun kapsamı yerleşimdi.

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

⚠️ **App Check'in depoda HİÇBİR bekçisi yok.** `main.dart:108`
`activate()` çağrısı try/catch ile **yutuluyor**; kurulum düşse uygulama
jetonsuz devam eder ve üç servis de zorlandığı için sessizce kapanır.
Satır tamamen silinse ne test ne `infra/build-aab.ps1` kapısı fark eder.

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
- Ortağın panosu `rytho.app/ortak/` — **hiçbir yerden linklenmez**, adres
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
hedefi korunarak). **Ama plist Xcode hedefine hâlâ eklenmedi** — diskte
durduğu hâlde pakete girmiyor, bkz. aşağıdaki tuzak.

⚠️ **Kayıt bir kez `app.rytho` diye açıldı** (`ai` yerine `app`). İnen
plist o kimliği taşıyordu ve `FirebaseApp.configure()` uyuşmazlığı **hata
değil UYARI** ile geçiyor: uygulama "çalışıyor" görünürken App Check (App
Attest kimliğe bağlı), Google girişi, push ve Crashlytics tek tek sessizce
bozulurdu. Firebase bundle kimliğini **düzenlettirmiyor** — kayıt silinip
yeniden açıldı. Bekçi: `backend/tests/test_ios_config.py`, kimliği beş
dosyada birden bağlıyor (pbxproj ×3, gradle, AASA, plist).

**Kalan engelleyiciler hesap işidir, kod değil:** Apple Developer üyeliği →
Team ID · imzalama · APNs anahtarı · gerçek `appl_` RevenueCat anahtarı
(şu anki `test_` önekli) · AASA'daki `TEAMID` yer tutucusu · App Store
Connect kaydı ve IAP ürünleri.

### iOS tuzakları (ölçüldü)

**`platform :ios` şablonda YORUMLU gelir.** Flutter, Podfile yoksa
şablondan üretir ama o satır kapalıdır; CocoaPods hedefi pbxproj'deki
değerden okur ve `google_mlkit_face_detection` 15.5 isterken 13.0 görüp
düşer. Yani "Podfile yok" tek başına doğru teşhis DEĞİLDİ — dosya
üretilse bile sorun çözülmezdi. Podfile artık depoda ve satır açık.

**15.5 keyfî değil**, paketlerin dayattığı tabandır: ML Kit 15.5,
Firebase 15.0. Düşürmek ancak yüz okumayı iOS'ta kapatmakla mümkün.

**`aps-environment` tek dosyada tutulamaz.** Release arşivi `development`
değeriyle çıkarsa cihaz SANDBOX jetonu alır, sunucu üretim APNs'ine
gönderir ve bildirim hiçbir yere düşmez — TestFlight'ta çalışır, mağazada
ölür. Bu yüzden `Runner.entitlements` (development) ve
`RunnerRelease.entitlements` (production) ayrı; pbxproj Release bloğu
ikincisine bakıyor. İkisi **yalnız o değerde** farklı kalmalı.

**Dosyayı `Runner/` altına kopyalamak pakete SOKMAZ.** `project.pbxproj`
klasör-senkronlu grup kullanmıyor (`objectVersion = 54`,
`PBXFileSystemSynchronizedRootGroup` yok) ve Copy Bundle Resources'ta
yalnız dört girdi var. `GoogleService-Info.plist` ve
`en.lproj/InfoPlist.strings` **Xcode'da hedefe eklenmeli**.

**`developmentRegion = en` ama izin metinleri Türkçe** — yani İngilizce
cihaz Türkçe izin diyaloğu görüyor. Türkiye-öncelikli lansmanda kabul;
dünyaya açılmadan önce düzeltilmeli. İngilizce metinler
`ios/Runner/en.lproj/InfoPlist.strings`'te **hazır ama bağlı değil**.

**`AppDelegate`'e bildirim delegesi körlemesine eklenmedi.**
`flutter_local_notifications` README'si istiyor ama `firebase_messaging` de
aynı delegeyi sahipleniyor; hangisinin kazandığı yalnız cihazda ölçülür.
Ölçmeden eklemek push'u onarmak yerine bozabilirdi.

**Simülatörde çalışmayan ikili:** TFLite ve App Attest. İkisi de gerçek
cihaz ister.

**Bu bölümde iki kez bayat not yakalandı** (2026-09-26): "associated-domains
hâlâ `rhytoai.web.app` diyor" yazıyordu — oysa `Runner.entitlements` iki
alan adını birden taşıyor, önceki bir turda düzeltilmiş ve not
güncellenmemişti. İkincisi yukarıdaki Podfile gerekçesiydi. **Bu bölümdeki
hiçbir iddiaya ölçmeden güvenme.**

---

## 8. Belgeler

`docs/mac-devir.md` — **Mac kurulumu ve iOS yol haritası** (yeni makineye
geçerken ÖNCE bu okunur) ·
`docs/test-raporu.md` — senaryo listesi ve bulgular (B1…B10) ·
`docs/konsol-gorevleri.md` — Firebase/Play/Cloud konsol işleri ·
`docs/store-launch.md` — mağaza metni, yasak dil, görsel borçları ·
`docs/maliyet-calismasi.md` — birim maliyetler ve marj ·
`docs/ozellikler.md` — ücretsiz/Plus tarifesi (koddan sapmamalı) ·
`docs/design/design-system.md` — hareket ve tipografi doktrini.

# Rytho Mağaza Yayın Rehberi

Bu doküman; Android imzalama, Play Console iç test, App Check, mağaza
politika notları, monetizasyon ve bildirim altyapısını içerir. **Buradaki adımların çoğu
konsol/hesap işlemi gerektirir ve uygulama sahibi tarafından yapılmalıdır.**

## 1. Android imzalama anahtarı

Yükleme anahtarını üret (bir kez; dosyayı ASLA repoya koyma, yedeğini al):

```powershell
keytool -genkey -v -keystore c:\keys\rytho-upload.jks -storetype JKS `
  -keyalg RSA -keysize 2048 -validity 10000 -alias rytho-upload
```

`apps/mobile/android/key.properties` oluştur (bu dosya .gitignore'da olmalı):

```properties
storePassword=<parola>
keyPassword=<parola>
keyAlias=rytho-upload
storeFile=c:/keys/rytho-upload.jks
```

`app/build.gradle.kts` release bloğu imzalamaya BAĞLI (2026-08-07'den
beri kurulu; `key.properties` yoksa build-aab.ps1 artık THROW eder —
KT4 kapısı). Referans yapılandırma:

```kotlin
signingConfigs {
    create("release") {
        val props = java.util.Properties()
        file("../key.properties").inputStream().use { props.load(it) }
        keyAlias = props.getProperty("keyAlias")
        keyPassword = props.getProperty("keyPassword")
        storeFile = file(props.getProperty("storeFile"))
        storePassword = props.getProperty("storePassword")
    }
}
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
    }
}
```

App Bundle üretimi: **`infra/build-aab.ps1`** — düz `flutter build appbundle --release` KULLANILMAZ. 2026-08-16'da 1.5.0+17 öyle üretildi ve satın almalar sessizce öldü: RevenueCat anahtarı `--dart-define-from-file` ile giriyor, düz komut onu geçirmiyor. Betik ayrıca imzayı, yetki kimliğini, kullanılmayan izinleri ve kameranın zorunlu olmadığını paketten doğruluyor

## 2. Play Console iç test adımları

1. https://play.google.com/console → geliştirici hesabı aç (25 USD, tek sefer).
2. "Uygulama oluştur" → ad: Rytho, dil: Türkçe, tür: Uygulama, ücretsiz
   (uygulama içi satın alma var).
3. **Uygulama içeriği** bölümü:
   - Gizlilik politikası URL'si. Metin uygulama içinde
     (`apps/mobile/lib/features/profile/legal_texts.dart`) ama mağaza bir URL
     ister — bir web adresinde yayınlanmalı (Firebase Hosting yeterli).
   - **Veri güvenliği formu:** `docs/store-privacy-labels.md` §3'teki tabloyu
     birebir gir. Konum yok, biyometrik veri yok. DİKKAT: rehber erişimi
     "yok" DEĞİL — isteğe bağlı rehber eşleşmesi VAR (yalnız numara
     özetleri, saklanmaz; labels §1'e bak). Veri silme URL'si:
     `https://rytho.app/legal/hesap-silme.html`.
   - İçerik derecelendirmesi anketi: Teen/13+ hedefleniyor
     (`docs/store-privacy-labels.md` §5).
4. **Test → İç test** → yeni sürüm → `.aab` yükle → test kullanıcısı
   e-postalarını ekle → yayınla.
5. Play App Signing'i kabul et (Google imzalama anahtarını yönetir; senin
   ürettiğin anahtar "upload key" olur).

## 2b. Kapalı test (closed testing) — KT-turu kontrol listesi

İç testten farkı: daha geniş testçi havuzu, "Uygulama içeriği" bölümünün
TAMAMI zorunlu, ve üretim davranışının birebir provası. Sıra:

1. **ÖNCE Firebase imzaları** (yapılmadan mağaza paketinde Google girişi
   ve SMS ÖLÜR): Play Console → Setup → App integrity → **App signing key
   certificate**'ın SHA-1 VE SHA-256'sını kopyala → Firebase Console →
   Project settings → Android app → ikisini de ekle →
   **google-services.json'u yeniden indir** ve
   `apps/mobile/android/app/`'e koy → AAB'yi bundan SONRA üret.
2. **Ürünler**: yukarıdaki "Kalan konsol işleri" 1-4 (abonelik
   DENEMESİZ + 3 paket + RevenueCat bağlama + webhook).
3. **License testing**: Play Console → Settings → License testing →
   testçi e-postaları. Bu hesaplar test kartıyla öder (gerçek tahsilat
   yok) ve abonelik yenilemesi dakikalara hızlanır (aylık ≈ 5 dk) —
   yenileme/iade senaryoları böyle koşulur.
4. **Uygulama içeriği** (hepsi zorunlu): Veri güvenliği formu
   (labels §3 + veri silme URL'si `…/legal/hesap-silme.html` +
   **AD_ID beyanı**: **HAYIR** — izin 2026-09-18'de manifest'ten
   kaldırıldı; uygulamada reklam yok, "evet" demek mağaza listesine
   "reklam kimliği kullanıyor" yazdırırdı), İçerik derecelendirme
   anketi, Hedef kitle 13+, "Reklam içermiyor" beyanı, Gizlilik
   politikası URL'si.
5. **Mağaza kaydı varlıkları**: 512×512 ikon, 1024×500 feature graphic,
   en az 2 telefon ekran görüntüsü, kısa/uzun açıklama.
6. **Test → Kapalı test** → kanal oluştur → AAB yükle → testçi listesi
   ya da Google Grubu ekle → sürüm notu (şablon aşağıda) → yayınla →
   katılım bağlantısını testçilere gönder.
7. Yayın sonrası ilk gün: Panel → Sistem'de webhook/bildirim sağlığı;
   `revenueEvents`'e ilk gerçek kayıt düştüğünde test-raporu B2 kapanır.

Sürüm notu şablonu (kanal başına kopyala/uyarla):

```
Rytho kapalı test {SÜRÜM}
• Yeni: {1-3 madde, kullanıcı diliyle}
• Düzeltme: {varsa}
Bilinen sınırlar: deneme 3 gün, kart istemez.
Sorun görürsen uygulama içinden yaz: Profil → Geri bildirim.
Panelden okuyup yanıtlıyoruz; yanıt telefonuna bildirim olarak gelir.
```

## 3. Firebase App Check (Play Integrity)

**Kod tarafı BİTTİ (1.15.8+43, 2026-09-15).** `firebase_app_check`
eklendi; `main.dart` açılışta Play Integrity ile etkinleştiriyor
(hata ayıklamada debug sağlayıcı, istisna yutuluyor — App Check
kurulamazsa uygulama yine açılır).

**Neden aciliyet kazandı:** Firebase Auth ucu internete açık ve API
anahtarı gizli değil; üstelik Android anahtarını paket + SHA-1 ile
kısıtlamak burada zayıf kalır, çünkü SHA-1 parmak izimiz App Links için
`/.well-known/assetlinks.json` ile ZATEN yayında. Bir bot çiftliği bunu
kullanıp uygulamayı hiç kurmadan 39 hesap açtı (hiçbirinin Firestore
profili yoktu: sunucumuza tek istek bile gelmemiş, doğrudan Google'ın
kimlik ucuna vurulmuştu). Hesaplar silindi.

Konsol tarafı — SIRA ÖNEMLİ:

1. Firebase Console → rhytoai → **App Check** → Apps → Android
   uygulaması (`ai.rytho`) → sağlayıcı **Play Integrity** → Save.
2. ⚠️ **Zorlamayı hemen AÇMA.** Önce 1.15.8+43 (ya da üstü) testçilerin
   telefonuna inmeli. App Check → APIs ekranında her servis için
   "verified / unverified" istek sayısı görünür; unverified sıfıra
   yaklaşınca aç. Erken açarsan eski paketi olan testçiler giremez.
3. Hazır olunca **Enforce**: `Firebase Authentication` ve
   `Cloud Firestore`.
4. API anahtarlarını da kısıtla (ayrı ve tamamlayıcı iş): Google Cloud
   Console → Credentials → *Android key* → paket `ai.rytho` + **iki
   SHA-1 birden** (debug ve Play App Signing); *Browser key* → HTTP
   referrers `rytho.app/*`, `rhytoai.web.app/*`,
   `rhytoai.firebaseapp.com/*`. Play SHA-1'ini unutursan mağazadan inen
   paket giriş yapamaz.
5. Backend doğrulaması istenirse `firebase_admin.app_check.verify_token`
   ile bir middleware eklenebilir (ayrı iş, henüz yapılmadı).

## 4. Mağaza politika notları

Ayrıntılı savunma ve inceleme notu: **`docs/store-review-notes.md`**.
Burada yalnızca konsol tarafını ilgilendiren özet var.

### Apple App Store

| Kural | Durum |
|---|---|
| **4.3 — Spam / duplicate** | En yüksek risk. Ayırt edici unsurlar ve kanıtları `store-review-notes.md` §2'de; inceleme notu §3'te kopyalanabilir hâlde. |
| **5.1.1(v) — Hesap silme** | Karşılanıyor: Profil → Hesabı sil. |
| **1.2 — UGC** | Uygulanmıyor: kullanıcılar arası **serbest metin yok**, yalnızca 12 maddelik kapalı tepki kümesi (`core/friends.dart kReactions`). Kullanıcının KENDİNE yazdığı sohbet/günlük metni vardır ama başka kullanıcıya gösterilmez. |
| **5.3.1 — Kumar/piyango** | Uygulanmıyor. I Ching para atma animasyonu bir kehanet ritüelidir; ödül, bahis veya şans oyunu mekaniği yok. Açıklamada netleştir. |
| **3.1.1 — Uygulama içi satın alma** | Tek aylık abonelik, harici ödeme bağlantısı yok. |

- iOS derlemesi macOS gerektirir; TestFlight için Apple Developer Program
  (99 USD/yıl).
- Mağaza açıklamasında **sağlık iddiası ("iyileştirir", "şifa") ve kesin
  kehanet dili kullanılmamalı.**

### Mağaza metinleri (KT-turu'nda yazıldı — hazır, kopyalanabilir)

**Kısa açıklama** (Play sınırı 80 karakter; bu 60):

```
Gerçek gökyüzü hesabıyla çalışan kişisel astroloji rehberin.
```

**Uzun açıklama:**

```
Rytho, doğum haritanı gerçek astronomik verilerle hesaplayan ve gökyüzünü
her gün senin için takip eden kişisel bir rehberdir.

NELER VAR
• Doğum haritan: çark, 14 nokta, evler ve açılar — Swiss Ephemeris
  hesabıyla, hazır şablonla değil.
• Şu an gökyüzünde: ay evresi, retrolar, günün açıları.
• Günlük okuma: haritanı bugünün gökyüzüyle birleştiren kişisel yorum.
• Sohbet: haritanı bilen ve konuştuklarınızı hatırlayan bir rehber.
• Çevren: eşini, çocuğunu, yakınlarını ekle; aranızdaki ölçülebilir bağı gör.
• Diğer gelenekler: BaZi (Çin dört sütun), I Ching ve firaset.

ÜCRETSİZ KULLANIM
Günlük burç yorumları, canlı gökyüzü, doğum haritası çarkın ve
yerleşimlerin, arkadaş listesi, seri ve hazır tepkiler, günde 5 sohbet
mesajı ve bir kişi ekleme hakkı — hesap açman yeterli.

RYTHO+ (aylık)
Kişiye özel günlük okuma, tam natal rapor, yıl haritası, iç takvim, BaZi,
I Ching, yüz okuma, 10 kişilik çevre kontenjanı ve ayda 100 AI kredisi.
Yeni hesaplar ilk 3 gün tüm Rytho+ özelliklerini kart bilgisi vermeden
dener; deneme bitince otomatik ücretlendirme olmaz.

DÜRÜSTLÜK
Ölçülmeyen söylenmez: doğum saatini bilmiyorsan yükselen burcun
hesaplanmaz ve bu sana açıkça söylenir. Yorumlar eğlence ve kişisel
içgörü amaçlıdır; tıbbi, hukuki, finansal veya psikolojik tavsiye
niteliği taşımaz. Uygulamada reklam yoktur.
```

Bu metinler yasak kelime taramasından geçti: "iyileştirir/tedavi/şifa" ve
kesin kehanet dili YOK; deneme cümlesi sunucu-denemesi gerçeğiyle uyumlu
(otomatik ücretlendirme İMA EDİLMİYOR); ücretsiz katman listesi koddaki
kapılarla birebir (I Ching Plus'ta — "günde 1 çekim" YAZILMADI).

### Mağaza metinleri — İngilizce (KL-turu)

Türkçenin çevirisi DEĞİL, aynı disiplinle yeniden yazılmış hâli: sağlık
iddiası ("heal/cure/treat") yok, kesin kehanet dili yok, deneme cümlesi
sunucu denemesini anlatıyor (otomatik ücretlendirme ima edilmiyor),
ücretsiz katman listesi koddaki kapılarla birebir.

> **Play'in "Yapay zeka ile çevirileri içe aktarın" düğmesini KULLANMA.**
> Makine çevirisi "ölçülmeyen söylenmez" cümlesini ve deneme ifadesini
> kolayca kaydırır; beyan ile kodun ayrışması kaldırılma sebebidir.

**App name:** `Rytho AI` (dillerde aynı — marka tutarlılığı)

**Short description** (Play sınırı 80; bu 64):

```
Your personal astrology guide, powered by real sky calculations.
```

**Full description:**

```
Rytho calculates your birth chart from real astronomical data and follows
the sky for you, every day.

WHAT'S INSIDE
• Your birth chart: the wheel, 14 points, houses and aspects — computed
  with Swiss Ephemeris, not filled in from a template.
• Sky right now: moon phase, retrogrades, today's aspects.
• Daily reading: your chart combined with today's sky, written for you.
• Chat: a guide that knows your chart and remembers what you talked about.
• Your circle: add your partner, your child, the people close to you, and
  see the measurable connection between you.
• Other traditions: BaZi (Chinese four pillars), I Ching and face reading.

FREE
Daily horoscopes, the live sky, your birth chart wheel and placements,
your friends list, streaks and quick reactions, 5 chat messages a day and
one person in your circle — an account is all it takes.

RYTHO+ (monthly)
Your personal daily reading, the full natal report, solar return, inner
calendar, BaZi, I Ching, face reading, a 10-person circle and 100 AI
credits a month. New accounts get all Rytho+ features for the first 3
days without entering card details; when the trial ends nothing is
charged automatically.

HONESTY
What isn't measured isn't said: if you don't know your birth time, your
rising sign is not calculated and you are told so plainly. Readings are
for entertainment and personal insight; they are not medical, legal,
financial or psychological advice. There are no ads in this app.
```

### Yasak dil — kazanç vaadi (OP-turu)

Sağlık iddiası ve kesin kehanet dilinin yanına **üçüncü bir yasak** eklendi.
Kapsamı mağaza metinleriyle sınırlı değil: ortaklık programını anlatan her
yüzey de buna tabidir — `web/ortaklik.html`, `web/en/partners.html` ve ortak
adayına yazılan e-posta.

**Yasak ifadeler:** "Ayda X TL kazan", "pasif gelir", "kolay para", "gelir
garanti edilir", "kesin kazanç", "herkes kazanıyor" ve bunların İngilizce
karşılıkları ("passive income", "easy money", "guaranteed earnings").

Gerekçe iki katmanlı ve ikisi de ölçülebilir:

1. **Beyan yanlış olur.** Kazanç, getirilen kişilerin abone olup olmamasına
   bağlıdır ve bu sayı önceden bilinemez. "Ölçülmeyen söylenmez" ilkesi,
   ürün metni ile ortaklık metni arasında ayrım yapmaz.
2. **Ödül tutarı ortak başına ayarlanır** (`partners/{id}.rewardTry`). Sayfaya
   tek bir rakam yazmak, farklı tutar anlaşılan ortağa karşı **yanlış
   beyandır**. Bu yüzden iki tanıtım sayfasında da hiçbir rakam yok; tutar
   "anlaşmada belirlenir" diye geçiyor.

Hukuki taraf ayrıca var: gelir taahhüdü yanıltıcı ticari uygulama sayılabilir
ve para kazandırma vaadi olan bir program mağaza politikalarında da ayrı
incelenir. İtibari tarafı ise geri dönüşsüz — bir kez "kolay para" diye
duyulan program, sonradan dürüst anlatılsa bile o adla hatırlanır.

Doğru dil, sayfadan BİREBİR: *"Kazanılan her abone için tek bir sabit tutar
ödenir."* · *"Tutar anlaşmada belirlenir ve kaydına yazılır."* · *"Kazanç,
getirdiğin kişilerin abone olup olmamasına bağlıdır; önceden bir tutar
taahhüt edilmez."*

Aynı gerekçe bir sözcüğü de dışarıda bırakıyor: **"pay"**. Türkçede yüzde
payını çağrıştırıyor, oysa ödül sabit tutar — yüzde hesabı (`sharePercent`)
kodda kullanım dışı. Sayfanın ilk hâli başlıkta ve iki paylaşım
açıklamasında "pay" diyordu; paylaşım kartında gövde metni görünmediği için
ortak yalnız o adı okuyup abonelik fiyatından bir yüzde bekleyebilirdi.

> ⚠️ Bu kuralı bir bekçiyle zorlarsan taramayı **`web/` altındaki sayfalara**
> bağla, bu dosyaya değil: yukarıdaki paragraf yasak ifadelerin kendisini
> içeriyor ve tarama buraya girerse bekçi kendi gerekçesine takılır. Depoda
> bu tuzağa iki kez düşüldü (build kapısı kendi manifest yorumuna, davet
> sayfası testi kendi HTML yorumuna).

### Mağaza görselleri (KL-turu — üretildi)

`store/play/` altında, hepsi uygulamanın KENDİ varlıklarından türetildi
(marka sapması olmasın diye):

| Dosya | Ölçü | Kaynak |
|---|---|---|
| `app-icon-512.png` | 512×512 | `assets/icon/app_icon.png` — launcher ikonunun aynısı |
| `feature-graphic-tr.png` | 1024×500 | işaret + `rytho_theme.dart` paleti |
| `feature-graphic-en.png` | 1024×500 | aynısının İngilizcesi |

Üretici betik: `infra/store-graphics.py` (yeniden çalıştırılabilir).
Yazı tipi Montserrat (Sora'nın geometrik karşılığı — Sora kurulu değil).

**Ekran görüntüsü tuzağı:** Play "16:9 veya 9:16" oranı istiyor; tipik
telefon ekran görüntüsü 1080×2400, yani **9:20** — olduğu gibi yüklenirse
REDDEDİLİR. Ham kareler 1080×1920 zemine oturtulmalı.

**⚠️ Ekran görüntüleri BAYAT olabilir (2026-09-18 denetimi).** `store/play/`
altındaki beş kare 7 Eylül'de çekilmiş ham CİHAZ yakalamalarından üretiliyor
(`store/play/raw/`), yani ekrandaki metin piksele gömülü: koddaki bir metin
düzeltmesi kompozit yeniden üretilse bile kareye YANSIMAZ. Bugüne kadar iki
kare yakalandıktan sonra düzeltilen bir kusuru gösteriyordu:

| Kare | Gösterdiği kusur | Durum |
|---|---|---|
| `shot-4-circle.png` | seri rozeti "🔥 **1 days**" (İngilizce ARB'de `streakDays` düz `{count} days`ti) | Kod ICU plural'a geçti. Kare KADRAJLA düzeltildi: kırpım 240→470, rozet çerçeve dışında kaldı ve asıl konu (arkadaş listesi) öne çıktı. |
| `shot-1-sky.png` | "In your sky today ✦ Nearest exactness: September…" sağdan KIRPILIYOR | Kod düzeltildi (`widgets/common.dart` `SectionHeader` artık `Row`+`Spacer` değil `Wrap`+`spaceBetween`). Kare hâlâ eski hâli gösteriyor; kadrajla kurtarılamaz çünkü kırpılan satır telefon çerçevesinin İÇİNDE. **Yeni cihaz yakalaması gerekiyor.** |

Kural: **piksel ELLE DÜZENLENMEZ** — mağaza karesi gerçek bir yakalama
olmalı; metni sonradan resme yazmak savunulamaz. Çare ya kadraj (kusur
çerçeve dışına alınabiliyorsa) ya da yeniden yakalama.

Sonraki AAB bir cihaza kurulduğunda: `store/play/raw/` kareleri yeniden
çekilir (`adb shell screenrecord`/`screencap`, Git Bash'te
`MSYS_NO_PATHCONV=1`), sonra `python infra/store-screenshots.py` koşulur ve
`shot-4`'ün kırpımı 470'ten 240'a geri alınabilir.

### Google Play

- Kategori: **Yaşam Tarzı** (KL-turu kararı — kategori standardı;
  Sağlık/Tıp ASLA seçilmez, `safety_rules` sağlık sorularını reddettiği
  için beyanla çelişirdi). Etiketler: Yıldız Falı, Kişisel gelişim,
  Yaşam Tarzı, Eğlence.
- İçerik derecelendirmesinde astroloji/fal içeriğini doğru beyan et; yanlış
  beyan kaldırma sebebidir.
- Sosyal özellik beyanı: kullanıcılar arası etkileşim **var ama sınırlı**
  (sabit tepki kümesi), kullanıcı üretimi içerik paylaşımı **yok**. Şikayet
  ve engelleme akışları yine de mevcut (`apps/mobile/lib/core/safety.dart`).
- Veri güvenliği formunda **hesap silmenin uygulama içinden yapılabildiğini**
  işaretle — Play bunu ayrıca soruyor.

## 5. Monetizasyon (uygulandı — Revize R1: abonelik + kredi)

Altyapı **kodda mevcut**: RevenueCat (`purchases_flutter`) + webhook ile
sunucu tarafı yetkilendirme + kredi cüzdanı (`backend/core/wallet.py`).

| Katman | İçerik |
|---|---|
| **Ücretsiz** | Burç yorumu (**yalnız günlük** — haftalık/aylık ucu istemciden erişilemiyor, bkz. not), gerçek gökyüzü, günde 5 sohbet mesajı, doğum haritası çarkı ve yerleşimleri, arkadaş listesi, seri ve hazır tepkiler, **1 kişi ekleme** (harita + ilişki ÖLÇÜMÜ; yorum kilitli). **Yeni hesap ilk 3 gün tüm Rytho+ özelliklerini kartsız dener** (+30 karşılama kredisi, tek sefer — OT6). |
| **Rytho+** (aylık; **yıllık** ürün Console'da açıldığı an paket teklifte GÖRÜNÜR — kod `kOfferedPackageTypes=[monthly, annual]`, aylık önseçili, yıllığın yanında yalnız ölçülmüş "%N tasarruf" rozeti, K8) | Kişiye özel günlük okuma + **10 kişi kontenjanı** (eş, çocuk, yakın) + **aylık 100 kredi** hakkı. Krediyle: sohbet (1), I Ching (2), ikili dinamik (3), natal/BaZi/sinastri/yüz okuma (5). Aylık hak dönem sonunda yenilenir, DEVRETMEZ. |
> **Not (1.7.0):** ücretsiz katmandan "günde 1 I Ching çekimi" SİLİNDİ — kod `require_plus("iching")` diyor, yani I Ching Rytho+ içinde. Mağaza metninin koda uymayan tek satırı buydu.

| **Kredi paketleri** (consumable) | `rytho_tokens_small` 50 · `rytho_tokens_medium` 100 · `rytho_tokens_large` 200 (₺80 / ₺140 / ₺250; 2026-10-14, eski 100/300/1000). Tekrar tekrar alınabilir, bakiye aya DEVREDER. ⚠️ **Yalnız aboneye satılır** (K2) — abone olmayana kredi mağazasında hiç gösterilmez (ölçüldü: `token_store_screen.dart` aboneliği ÜÇ hâlli okuyor ve `!abone` dalında paket listesi yerine `_PaketlerPlusaOzel` çiziliyor). Gerekçe: `charge_metered` tüm depoda tek yerden çağrılıyor (`api/chat.py`), yani abone olmayanın aldığı kredinin TEK kullanım yolu "günün 6. sohbet mesajı"; ekranın kendi bedel listesinde sayılan I Ching, ikili dinamik ve derin raporlar `require_plus` arkasında. Mağaza, parasını alıp karşılığını büyük ölçüde vermediği bir ürün gösteriyordu. ⚠️ Denemedeki kullanıcı ABONE SAYILIR ve paket onun için ayrıca anlamlıdır: `get_wallet` denemeye `allowance: 0` veriyor, yani yalnız `purchased` bakiyesinden harcıyor. |

> ⚠️ **Yukarıdaki üç tablo satırı da koddan ölçüldü (2026-10-02), elle
> yazılmadı.** Aylık hak sayısı ÜÇ yük taşıyan yerde birbirinden bağımsız
> duruyor: sunucu sabiti `backend/core/wallet.py`
> `MONTHLY_TOKEN_ALLOWANCE` (**100**), uygulamanın paywall'da gösterdiği
> dize `app_tr.arb`/`app_en.arb` `benefitChatTitle`, ve Play Console'a
> ELLE kopyalanan bu belgedeki mağaza metni. İlk ikisi 100'e inerken bu
> belge **300** yazmaya devam etti ve hiçbir test düşmedi; mağaza metnini
> tutan yer burası olduğu için fark edilmemesi yanlış sayının mağaza
> listesine girmesi demekti. Üçünü birbirine bağlayan bekçi:
> `backend/tests/test_belge_tarifesi.py` (mutasyonla sınandı).
>
> ⚠️ **Haftalık/aylık burç yorumu VAAT EDİLEMEZ.** Sunucu ucu üç `period`
> değeri kabul ediyor (`api/reports.py` `daily|weekly|monthly`) ama
> uygulama hiçbirini göndermiyor — `lib/` genelinde `period=` sıfır kez
> geçiyor, `providers.dart` düz `/reports/horoscope/{burç}` çağırıyor.
> Hesap var, ona açılan kapı yok; ayrıntı `docs/ozellikler.md` §3.

Kurallar:
- Kredi yalnızca **yeni üretimde** düşer; önbellekten tekrar okuma ücretsiz.
- LLM yanıt üretemezse bedel iade edilir.
- Kilit sunucuda: 402 + (kredi bitiminde) `X-Paywall-Reason: tokens` başlığı;
  istemci başlığa göre paywall ya da kredi mağazası açar.
- `RYTHO_TOKENS_ENFORCE=1` — CANLI (K5 kapanışı; kuru çalışma dönemi
  bitti). Denemedeki kullanıcı günlük ücretsiz hakkını KORUR (KT2).

### Yayın bölgesi: ÖNCE TÜRKİYE (2026-09-20 kararı)

Uygulama **yalnız Türkiye'de** yayınlanır; ürün olgunlaşınca dünyaya açılır.
Gerekçe teknik: telefon doğrulaması Firebase'de `allowlistOnly: ["TR"]` ile
sınırlı ve istemcide `phone_verify_screen.dart` `_smsBolgeleri = {'TR'}`
kapısı var. +90 dışı bir numarada SMS **hiç gönderilmiyor**, dürüst mesaj
çıkıyor (`phoneRegionUnsupported`) — yani dünyaya açılsa kayıt akışı
diğer ülkelerde yarım kalırdı.

Dünyaya açarken yapılacaklar (hepsi ayrı iş):
Firebase SMS bölge listesini genişlet **ve** `_smsBolgeleri` kümesini
birlikte güncelle (iki yer aynı gerçeği söylemeli) · reCAPTCHA Enterprise'ı
aç (SMS toll-fraud) · Play ülke listesi · fiyatlandırma/para birimi ·
hukuk metinlerinin dil/yetki alanı.

### Mağaza ürün adları uygulamanın SÖZLÜĞÜNE uymalı

Play Console'daki ürün adı ve temel plan kimliği **makbuza basılıyor** ve
kullanıcının satın alma kaydında kalan tek metin o. 2026-09-20'de test
makbuzları okundu, bugünkü adlar şunlar:

| Makbuzda görünen | Uygulama ne diyor | Durum |
|---|---|---|
| `Test: Aylık Plus` | `paywallTitle` = **"Rytho+"**, plan adı **"Aylık"** | marka adı eksik |
| `Test: 1000 Jeton` | `tokenPackAmount` = **"{count} kredi"**, ekran **"Kredi Mağazası"** | **"Jeton" yanlış kelime** |

"Jeton" kullanıcıya gösterilen sözlükten R2-F2 kararıyla çıkarıldı ("AI
kredisi"). Makbuzda durması, uygulamanın hiç kullanmadığı bir kelimeyle
ödeme kaydı bırakmak demek.

Play Console → Kazanç sağlama → Ürünler'de düzeltilecek (ad alanı;
kimlikler `rytho_plus_monthly`, `rytho_tokens_*` **DEĞİŞMEZ** — kimlik
değişirse mevcut satın almalar kopar):

| Ürün kimliği | Ad (TR) | Ad (EN) |
|---|---|---|
| `rytho_plus_monthly` | Rytho+ Aylık | Rytho+ Monthly |
| `rytho_tokens_small` | 50 AI Kredisi | 50 AI Credits |
| `rytho_tokens_medium` | 100 AI Kredisi | 100 AI Credits |
| `rytho_tokens_large` | 200 AI Kredisi | 200 AI Credits |

⚠️ Uygulama normalde KENDİ adlarını çiziyor (`paywall_screen.dart` plan
adını `l10n.planMonthly`'den, `token_store_screen.dart` miktarı
`l10n.tokenPackAmount`'tan alır) — ama ikisinin de **yedek dalı
`product.title`**, yani mağaza adı. Paket kimliği tanınmazsa Play
Console'daki metin uygulamanın İÇİNDE görünür. Bu yüzden iki taraf da
aynı sözlüğü konuşmalı.

### Kalan konsol işleri — uygulama sahibinin

1. **App Store Connect** ve **Play Console**'da abonelik ürününü oluştur:
   kimlik `rytho_plus_monthly`. **MAĞAZA DENEMESİ EKLEME (KT kararı):**
   3 günlük deneme SUNUCU tarafında zaten var (kartsız, hesap yaşına
   bağlı — OT6); mağazaya da deneme koymak 3+3 gün çakışması, paywall
   geri sayımıyla çelişki ve "otomatik ücretlendirme" beklentisi
   yaratırdı. Hukuk metinleri sunucu-denemesi diline göre yazıldı.
2. Aynı konsollarda ÜÇ **consumable** ürün oluştur — kimlikler birebir:
   `rytho_tokens_small`, `rytho_tokens_medium`, `rytho_tokens_large`
   (önerilen fiyatlar: $1,99 / $4,99 / $12,99). RevenueCat'te bu ürünleri
   içeri aktar; entitlement'a BAĞLAMA (consumable — webhook cüzdana yükler).
3. RevenueCat panelinde abonelik ürününü `RhytoAI Pro` yetkisine bağla.
   Yetki kimliği koddaki `RYTHO_PLUS_ENTITLEMENT` ile birebir aynı olmalı;
   farklıysa satın alma sonrası yetki açılmaz.
3b. **OFFERING KUR — atlanırsa paywall BOŞ açılır.** `Product catalog →
   Offerings` → `default` teklifi → `$rc_monthly` paketi → içine
   `rytho_plus_monthly` → teklifi **Current** yap. Gerekçe kodda:
   `apps/mobile/lib/core/subscription.dart:184` `Purchases.getOfferings()`
   → `offerings.current?.availablePackages` okuyor; teklif yoksa liste
   boş döner. **Kredi paketleri için Offering GEREKMEZ** — onlar
   `wallet.dart:95-101`'de `Purchases.getProducts(kTokenPackIds,
   productCategory: nonSubscription)` ile doğrudan kimlikle çekiliyor.
4. RevenueCat webhook'unu şu adrese kur:
   `https://<cloud-run-url>/api/v1/billing/revenuecat`
   Authorization başlığına Secret Manager'daki `REVENUECAT_WEBHOOK_SECRET`
   değerini **ham hâliyle** yaz (Bearer öneki YOK — `billing.py:174`
   `compare_digest` birebir eşitlik arıyor). Anahtar tanımsızken uç 503
   döner ve **hiçbir kullanıcı abone olarak işaretlenemez** — bu bilinçli.
   **Environment: production VE sandbox** seçili olmalı; kapalı testteki
   lisanslı satın almalar sandbox sayılır ve yalnız-production ayarıyla
   hiç düşmez.
5. `test_` önekli RevenueCat anahtarlarını gerçek anahtarlarla değiştir
   (`apps/mobile/dart_defines.local.json`; dosya .gitignore'da).

> RevenueCat **TRANSFER** olayı işleniyor: kullanıcı oturum açmadan satın alma
> yaparsa kayıt anonim kimliğe gider, sonradan giriş yapınca devredilir.
> Devir işlenmeseydi ödeme yapmış kullanıcı kilitli kalırdı.

## 6. Bildirim altyapısı (uygulandı)

Cloud Scheduler saatte bir toplu gönderim ucunu tetikler; kime gideceğine
sunucu karar verir (yerel saat + sessiz saat + tercih + tekrar koruması).

Kurulum tek komut:

```powershell
cd infra
./create-scheduler.ps1
./deploy-backend.ps1
```

Betik gizli anahtarı üretir, servis hesabına okuma izni verir ve iki saatlik
işi kurar. **Anahtarı döndürmek için:** `$env:RYTHO_ROTATE_SCHEDULER_SECRET=1`
ile çalıştır.

Duman testi (yayın sonrası "gerçekten gidiyor mu"):

```powershell
$A = gcloud secrets versions access latest --secret NOTIFY_SCHEDULER_SECRET --project rhytoai
curl -X POST -H "Authorization: $A" "<url>/api/v1/notify/run?type=daily&dry_run=true"
```

`dry_run` hiçbir şey göndermez ve kaydetmez; kime gideceğini ve neden
atlandığını döner. Gerçek bir test gönderimi için `force=true` (hedef saati
atlar) ve gerekirse `ignore_dedupe=true` eklenir. **Sessiz saat ve kullanıcı
tercihi hiçbir bayrakla atlanmaz.**

## 7. Yayın öncesi kritik hatırlatmalar

- **Swiss Ephemeris ticari lisansı**: kerykeion/pyswisseph AGPLv3'tür; kapalı
  kaynak mağaza yayını ÖNCESİ Astrodienst AG'den ticari lisans alınmalı
  (~750 CHF, tek seferlik): https://www.astro.com/swisseph/
  Kod bu maddeyi kapatamaz; lisans satın alınmadan checklist işareti
  konulmamalı.
- Hukuki metinler bir web adresinde yayınlanmalı (mağaza formları URL ister).
- Hukuki metinler **bir hukukçuya baktırılmalı** — mühendislik taslağıdır.
- ~~release bloğu debug anahtarıyla imzalıyor~~ — **ÇÖZÜLDÜ.**
  `app/build.gradle.kts:60-68` `key.properties` varsa gerçek release
  yapılandırmasını kullanıyor, yoksa debug'a düşüyor. `infra/build-aab.ps1`
  bu düşüşü ARTEFAKTTAN yakalıyor: `key.properties` yoksa derleme hiç
  başlamıyor, bittikten sonra da keytool ile imza "Android Debug" mı diye
  ölçülüyor. 2026-09-18'de doğrulandı.
- Cloud Run `--max-instances 3`; lansman trafiğine göre gözden geçir.
- Tam kontrol listesi: `docs/production-checklist.md`

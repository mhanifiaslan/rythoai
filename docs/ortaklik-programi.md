# Ortaklık (affiliate) programı

Bu belge ortaklık programının **neden böyle** olduğunu tutar. Her madde ya
kaynak okunarak doğrulandı ya da bir kez zarar verme ihtimali ölçülüp
kapatıldı. Teorik anlatım yok; her iddianın yanında `dosya:satır` var ve
o satırlar bu belge yazılırken tek tek okundu.

Ölçüm tarihi: **2026-09-27**. Dal: `yuz-okuma-cihaz-usti-olcum`.

> **Satır numaraları hakkında.** Kaynak dosyalar için satır verildi, TEST
> dosyaları için **test adı** verildi. Sebep ölçüldü: bu belge yazılırken
> `test_web_seo.py` içindeki ortak deseni testi 129'dan 135'e kaydı, çünkü
> aynı dosyada paralel bir değişiklik vardı. Test adı taşınmaz, satır
> taşınır — bayat bir satır numarası, gerekçesi yanlış bir yorumla aynı
> sınıf kusurdur.

> Backend'in canlıda hangi revizyonda olduğu **bu belgede ölçülmedi**; tur
> notu rev 00100 diyor. Sayıya güvenmeden önce
> `gcloud run services describe --project rhytoai` ile doğrula.

---

## 1. Model — ve kullanıcıya ödül neden YOK

Ortak, getirdiği kullanıcının **ilk aboneliği** başına sabit bir ₺ tutar
kazanır. Tutar ortak başına ayarlanır (`partners/{id}.rewardTry`), tavan
₺500. Jeton paketi, deneme, yenileme ve SANDBOX alımları **ödül
üretmez**. Hakediş satın almadan **15 gün** sonra kesinleşir. Ortak kendi
kodunu kendi hesabında kullanamaz.

**Kullanıcı ödülü yok, çünkü ödüllendirilecek bir eylem kalmadı.** İndirim
ya da bonus jeton yalnızca kullanıcıya kodu **elle yazdırmak** için
gerekliydi. Kod artık Android'de Play Install Referrer ile kendiliğinden
geliyor (`apps/mobile/lib/core/partner_referrer.dart:51`) — kullanıcı
hiçbir şey yazmıyor, hiçbir şeye dokunmuyor. Motive edilecek eylem yokken
ödül vermek, para karşılığı hiçbir şey satın almamak olurdu.

Bu tek karar mağaza tarafını **komple siliyor**: Play Console'da teklif
(offer) tanımlanmıyor, RevenueCat'te Offering/Targeting kurulmuyor,
paywall'a kod alanı geri gelmiyor. Uygulamadaki kod girişi zaten A2
kararıyla kaldırılmıştı ve yorumu yerinde duruyor:
`apps/mobile/lib/features/paywall/paywall_screen.dart:329`.

⚠️ Bu yüzden `web/r/` sayfası kodu **kullanıcıya hiç göstermez**. Turun
içinde bir kez tersi yapıldı — sayfa kodu ekranda gösteriyor ve
"kurulumdan sonra girişe yaz" diyordu; uygulamada girilecek yer olmadığı
için bu düpedüz yanlış yönlendirmeydi. Düzeltildi ve gerekçesi sayfanın
kendi içine yazıldı (`web/r/index.html:63-68`). Ürünün çekirdek ilkesi
burada ihlal edilmişti: **var olmayan bir adım kullanıcıya tarif edilmez.**

`sharePercent` alanı dokümanda ve kodda **duruyor ama kullanılmıyor**
(`backend/services/partner_service.py:71`, tek desteklenen model `fixed`).
Panelde de gösterilmiyor: hesaba girmeyen bir sayıyı "pay %20" diye
yazmak, ölçülmeyeni söylemek olur.

---

## 2. Veri modeli

Alan adları `backend/services/partner_service.py:3-15` başlığındaki
sözleşmeden ve gerçek yazım çağrılarından alındı. Hepsini **yalnız Admin
SDK** yazar; `infra/firestore.rules` içinde bu yollar için **hiç kural
yok** ve gerekmiyor — Firestore'da eşleşmeyen yol varsayılan kapalıdır.

| Yol | Alanlar |
|---|---|
| `partners/{partnerId}` | `name`, `contact`, `active`, `notes`, `createdAt`, `uid`, `rewardModel`, `rewardTry`, `sharePercent`, `payoutCurrency`, `taxId`, `iban`, `minPayoutTry` |
| `partnerCodes/{KOD}` | `partnerId`, `bonusTokens`, `maxRedemptions`, `redemptionCount`, `expiresAt`, `active`, `createdAt` |
| `users/{uid}/private/attribution` | `code`, `partnerId`, `at` — **tek sefer** |
| `partnerQualifications/{uid}` | `partnerId`, `code`, `eventId`, `productId`, `purchasedAt`, `maturesAt`, `status`, `rewardTry`, `createdAt`, `maturedAt`, `voidReason`, `voidedAt` |
| `partners/{id}/payouts/{n}` | `amount`, `currency`, `at`, `note` |

İki ölçülmüş incelik:

* `create_partner` (`partner_service.py:393`) **taxId / iban / minPayoutTry
  yazmaz** — bunlar yalnız `update_partner`'ın izin listesinden geçer
  (`partner_service.py:431`). Yani yeni ortak kaydı açıldığında ödeme
  bilgileri **yok**, sonradan panelden girilir. Eksikliği hiçbir kapı fark
  etmez.
* `partnerQualifications` alan listesi modül başlığında `createdAt` ve
  `voidedAt` olmadan yazılı; gerçek yazımlar ikisini de koyuyor
  (`partner_service.py:263-273`, `partner_service.py:297-298`,
  `partner_service.py:359-361`). Başlık **eksik**, yanlış değil — şema
  değişince ikisini de güncelle.

`users/{uid}/private/**` istemciye tamamen kapalı
(`infra/firestore.rules:203`), yani atıf dokümanına uygulama dokunamaz;
tek yazma yolu `POST /api/v1/billing/redeem-code`
(`backend/api/billing.py:161`).

---

## 3. Doküman kimliği neden `uid`

`partnerQualifications` dokümanının kimliği **uid**'dir
(`backend/services/partner_service.py:219`). Bu, "kullanıcı başına tek
ödül" kuralını **sorguyla değil yapıyla** garanti eder.

Alternatif — rastgele kimlik + "bu uid'in kaydı var mı" sorgusu — üç yerde
sessizce kaybediyordu: webhook tekrarı yarışta iki kayıt açabilir, ikinci
abonelik ikinci ödül doğurur, farklı bir ortak aynı kullanıcı için ayrı
kayıt açabilir. Kimliğin uid olması bunların **hepsini** aynı anda imkânsız
kılıyor, çünkü yazım `.create()` ile yapılıyor (`partner_service.py:263`) ve
var olan dokümanda `AlreadyExists` atıp sessizce geçiyor
(`partner_service.py:277-280`).

Bedeli bilinçli: aynı kullanıcı için **hiçbir koşulda** ikinci hakediş
açılamaz. İkinci bir ödül modeli (ör. yenileme başına) gerekirse bu
koleksiyon kullanılamaz, yenisi gerekir.

---

## 4. Ödül kuralı — beş koşul, beş ayrı zarar kapısı

Kaynak: `backend/api/billing.py:420-465` (`_ortaklik_hakedisi`). Beşi
**birden** gerekir; biri gevşerse kayıp sessizdir — panel "hakediş"
gösterir, sahip öder, yanlış olduğu ancak mutabakatta anlaşılır.

1. **`environment == "PRODUCTION"`.** Canlıda 1756 SANDBOX olayı var
   (`partner_service.py:516-518` aynı gerekçeyi panel toplamları için de
   yazıyor). Süzülmezse ortağa **sahte gelirden gerçek para** ödenir.
2. **Olay türü `INITIAL_PURCHASE` ya da `TRIAL_CONVERTED`**
   (`partner_service.py:94`). `INITIAL_PURCHASE` tek başına yetmez:
   mağaza denemesi açılırsa denemeden ödeyen abone `TRIAL_CONVERTED` ile
   gelir ve yalnız ilkine bakan kural onu **kaçırır** — ortak kazandığı
   aboneyi hiç göremez. `RENEWAL` kümede yok, yani yenileme ödül
   doğurmaz. Jeton paketleri yalnızca `NON_RENEWING_PURCHASE` olarak
   geldiği için bu küme onları **kendiliğinden** dışarıda bırakıyor;
   ürün listesi tutmak gerekmiyor (tutulsaydı yeni paket eklendiğinde
   liste bayatlar ve paket satışı ödül üretmeye başlardı).
3. **`monetary is True`.** Parasal olmayan olaylar aynı deftere
   `price=0, monetary=false` ile giriyor (`billing.py:56`); süzgeç
   olmasa iptal/ödeme sorunu gibi kayıtlar ödül doğururdu.
4. **`period_type` `TRIAL` DEĞİL.** Bu 3. koşulun tekrarı değil,
   **ayrı** bir kapı: `period_type=TRIAL` olan bir `INITIAL_PURCHASE`
   hem `monetary=True` hem `isTrial=True` gelir
   (`billing.py:438-440`). Yani **`monetary` tek başına para geçtiğini
   KANITLAMAZ.** Bu koşul olmasa mağaza denemesi başlatan her kullanıcı
   ödül doğurur, denemeyi iptal edenler için de para ödenmiş olurdu.
5. **Atıf var** (`partner_id` dolu). Atıf `revenueEvents` yazılırken
   `users/{uid}/private/attribution`'dan okunuyor
   (`billing.py:373-377`); yoksa organik satın almadır ve kimseye
   ödenmez.

Hakediş yazımı **asla fırlatmaz** (`partner_service.py:228-229`): para
zaten alındı, ortaklık ikincil bir defterdir ve onun hatası satın alma
borusunu düşürmemeli.

---

## 5. `CANCELLATION` neden void ETMİYOR

İptal eden hakediş kümesi yalnız `{REFUND, EXPIRATION}`
(`partner_service.py:105`). `CANCELLATION` **bilerek dışarıda**.

RevenueCat'te `CANCELLATION` "otomatik yenilemeyi kapattı" demektir,
**para iadesi değil** (`billing.py:39-42` aynı ayrımı erişim tarafı için
yapıyor): kullanıcı ödediği dönemin sonuna kadar erişimini sürdürür ve o
ayın parası bizde kalır. Ortak o aboneyi gerçekten kazandı; iptali ceza
saymak ortağa haksızlık olurdu.

`EXPIRATION` ise 15 günlük pencere **içinde** anormaldir — aylık abonelik
30 gün sürer. O pencerede erken sona erme pratikte iade ya da tahsilat
hatasıdır, o yüzden void eder.

`qualified` olmuş hakedişe **dokunulmaz** (`partner_service.py:295-296`).
Geçmişi sessizce değiştirmek, ortağın gördüğü bakiyeyi açıklamasız oynatmak
olurdu; düzeltme panelden **negatif ödeme kaydıyla** yapılır ve negatif
kayıt gerekçesiz yazılamaz (`partner_service.py:578-580`).

---

## 6. Güvenlik — `"partner"` neden ROLES'a EKLENMEDİ

`backend/core/auth.py:94` → `ROLES = ("owner", "support")`. Ortaklık
buraya **eklenmedi**, ayrı bir claim boyutu olarak duruyor
(`{partner: true, partnerId: "..."}`, `auth.py:171-178`).

Gerekçe ölçüldü: `require_admin` kapısı `user.admin or user.role in ROLES`
diyor (`auth.py:269`). `"partner"` ROLES'a eklenseydi bir ortak token'ı bu
kapıyı **geçerdi**. Ölçüldü: `api/admin.py` 37 router girişi taşıyor ve
`/collect` dışındaki **36'sı** doğrudan `require_admin`/`require_owner`
bağımlılığıyla kapılı (`/collect` scheduler sırrı VEYA owner çifte
kapısını kullanıyor, `admin.py:141-164`). Yani tek bir claim satırı tüm
kullanıcı listesini, geliri, sistem ayarlarını ve **diğer ortakların
detaylarını** açardı. Rol modeli "yetkiyi daraltmak" için tasarlandı,
vermek için değil — bir rol eklemek sessizce yetki **vermek** olurdu.

Ortak kapısı bu yüzden bağımsız: `require_partner` (`auth.py:286-297`)
`require_admin`'in üstüne binmez, ROLES'a bakmaz. `partnerId` **claim'den**
gelir, istekten değil (`api/partners.py:33`), yani ortak gövdede başka bir
ortağın kimliğini gönderip veri çekemez. Sınır kontrol listesine değil
**yapıya** dayanıyor.

Claim'i basan araç `tools/set_admin.py --partner <partnerId>`
(`set_admin.py:53`) ve ortaklık ile admin **birlikte yazılmaz, birlikte
kaldırılmaz** (`set_admin.py:86-96`); onay ekranı işlemi "ORTAK BAS … —
admin YAZILMAZ" diye yazdırıyor (`set_admin.py:72`).

Ortağın gördüğü veri `partner_self_view` ile **daraltılıyor**
(`partner_service.py:613-642`): atfedilen gelir, kullanıcı kimlikleri ve
diğer ortaklar dışarı çıkmaz. `/me` ucu ortak kaydı **silinmişse** jenerik
403 döner, "kayıt yok" demez (`api/partners.py:43-47`) — silinmiş bir
ortağa sistemin şeklini anlatmamak için.

⚠️ **PASİF ortak 403 ALMIYOR** (ölçüldü 2026-09-27; bu belgenin ilk hâli
`api/partners.py:43` yorumuna güvenip "silinmiş/pasifse 403" yazıyordu ve
yanlıştı). `partner_detail` yalnızca doküman **yok**ken `not_found`
fırlatıyor (`partner_service.py:480-482`); `active: false` kontrolü hiçbir
yerde yok. Yani `active` false'a çekilen bir ortak kendi panosunu 200 ile
görmeye devam eder — yalnız yanıttaki `active` alanı false olur. Kapatılıp
kapatılmayacağı **karar konusu**: panoyu okumak zarar vermiyor, ama
"programdan çıkarıldı" ile "panoyu hâlâ görüyor" aynı anda doğru.

---

## 7. İstemci — iki geliş yolu, tek bayrak

Kaynak: `apps/mobile/lib/core/partner_referrer.dart`.

1. **Kurulum yolu.** Ortak `https://rytho.app/r/KOD` paylaşır. Uygulama
   kurulu değilse link tarayıcıda açılır, sayfa Play'e `&referrer=` ile
   yönlendirir (`web/r/index.html:123-128`), Play o dizeyi kurulumdan sonra
   uygulamaya verir ve `ensurePartnerReferrer` (`partner_referrer.dart:51`)
   kodu `utm_campaign` alanından okuyup (`partner_referrer.dart:38`) uca
   gönderir.
2. **Kurulu uygulama yolu.** Play devreye hiç girmez; işletim sistemi linki
   doğrudan uygulamaya verir (`AndroidManifest.xml:174`, `/r/`
   intent-filter) ve `applyPartnerCode` (`partner_referrer.dart:83`)
   çağrılır (`apps/mobile/lib/core/deep_links.dart:152`).

İkisi **aynı SharedPreferences bayrağını** paylaşır
(`partner_referrer.dart:46`), yani aynı cihazda iki kez denenmez.

**Bayrak SÜRÜMSÜZ** ve bu `consent.dart`'tan ayrılan tek yer
(`partner_referrer.dart:40-45`): kabul kaydı şartlar sürümü değişince
yeniden alınmalı, atıf ise hesap başına **ömürlük tek**. Bayrağı sürümlemek,
bir gün sürüm artınca herkesin zaten kullanılmış kodu yeniden göndermesine
ve **409 seline** yol açardı.

**4xx terminaldir, 401 hariç** (`partner_referrer.dart:97-118`).
`consent.dart` deseni buraya körlemesine kopyalanamaz: o uç idempotent 200
döner, bu uç ikinci çağrıda 409 `already_redeemed` verir. Kopyalansaydı atfı
**zaten olan** her kullanıcı her açılışta bir 409 isteği atardı — App
Check'in arkasında sessiz, kalıcı bir çöp yük. 401 istisnası ise şu ölçülmüş
durumdan geliyor: atıf **uid başına** yazılır, yani oturumsuz gönderilen kod
hiçbir hesaba bağlanmaz; bayrağı orada yakmak kullanıcı giriş yaptıktan
**sonraki** meşru denemeyi de kapatırdı. `/r/` bağlantısına girişsiz dokunan
kurulu uygulama tam bu hâle düşüyor.

Install Referrer okunamazsa bayrak **yazılmaz**
(`partner_referrer.dart:60-65`), bir sonraki açılış yeniden dener. Referrer
okunup içinde kod **yoksa** bayrak yazılır (`partner_referrer.dart:68-73`):
organik kurulum terminal bir cevaptır.

Üçüncü parti atıf SDK'sı (Branch vb.) **bilerek alınmadı**
(`partner_referrer.dart:20-23`): kendi Android belgesi `AD_ID` izni istiyor,
`infra/build-aab.ps1` o izni bulunca yayını durduruyor ve izin gizlilik
politikamızdaki "reklam kimliğini KULLANMAZ" cümlesini yalan yapardı.

---

## 8. Kabul edilen sınırlar (gizlenmeyecek)

Bunlar **kusur değil**, bilinen ve kabul edilmiş boşluklardır. Gizlenirse
bir gün "neden bu ortak hiç kazanmıyor" sorusu kök nedensiz kalır.

**iOS'ta atıf YOK.** Play Install Referrer'ın iOS'ta dengi yoktur ve bu
Apple'ın bilinçli kararı: `AdServices` yalnız Apple Search Ads içindir ve
yükünde serbest alan yok; `ct=`/`pt=` yalnız App Store Connect
analitiğinde görünür, uygulama okuyamaz; Universal Link uygulama kurulu
değilken hiçbir şey saklamaz; SKAdNetwork/AdAttributionKit toplu reklam
ölçümüdür, kod taşıyamaz (`partner_referrer.dart` başlığı).

Seçilen yol (sahip kararı, 2026-10-22; `docs/mac-devir.md` 4.10):
**kurulu uygulamada Universal Link** — `apple-app-site-association`
`/r/*` taşıyor, bağlantı uygulamayı açar ve mevcut `deep_links.dart` yolu
kodu aynı `redeem-code` ucuna yazar (oturum şart). **Kurulum öncesi** için
`/r/` sayfası iPhone'da "kur, hesabını aç, bağlantıya bir kez daha dokun"
der ve karşı host'a giden bir "Uygulamada aç" düğmesi gösterir; ikinci
dokunuşu yapmayan sayılmaz. Custom Product Page (ortak başına mağaza
sayfası, en çok 70, her biri incelemeden geçer) ve pano okuma bilerek
seçilmedi; parmak izi eşleştirme hiç düşünülmedi.

⚠️ **Durum (2026-10-22): kod hazır, cihazda ÖLÇÜLMEDİ, canlıda değil.**
iPhone dalı `APPSTORE_ID` boşken kapalı — uygulama App Store'da yokken
sayfa bugünkü cümleyi söylemeye devam ediyor: "Ortak bağlantısı şimdilik
yalnız Android kurulumlarında sayılıyor". Panolardaki iPhone dipnotları da
yayın gününe kadar doğru; o gün GÜNCELLENİR, kaldırılmaz (ikinci dokunuşu
yapmayan hâlâ sayılmaz).

**`/r/` yalnız `rytho.app` ana makinesinde yakalanıyor.** `/i/` iki ana
makineye birden bağlı (`rytho.app` **ve** `rhytoai.web.app`,
`AndroidManifest.xml:144-153`) ama `/r/` yalnız birine
(`AndroidManifest.xml:174`). Yani `rhytoai.web.app/r/KOD` bağlantısı kurulu
uygulamada **tarayıcıda açılır**, uygulamaya düşmez — ve o yol kurulum
akışına girer, atıf yine oluşur ama "kurulu uygulama" kısayolu çalışmaz.
Ortaklara **her zaman `rytho.app/r/`** verilmeli. (Bu ayrım ANDROID'e
özel: iOS'ta AASA iki ana makineden de sunuluyor ve `Runner.entitlements`
ikisini de taşıyor; `/r/` sayfasının "Uygulamada aç" düğmesi tam da
karşı ana makineye gittiği için çalışır — Universal Link aynı alan adı
içinde tetiklenmez.)

**TRANSFER boşluğu.** Anonim satın alma → sonradan giriş senaryosunda
`INITIAL_PURCHASE` **anonim kimlik altına** yazılır; gerçek uid yalnızca
`monetary=False` bir `TRANSFER` kaydı alır (`billing.py:269`). İki kapı
birden kapanıyor: `TRANSFER` ödül doğuran küme içinde değil
(`partner_service.py:94`) ve `monetary=False` üçüncü koşula takılıyor.
Ayrıca atıf **devredilmiyor** — `_handle_transfer` (`billing.py:215-277`)
abonelik kaydını ve cüzdanı taşıyor, `private/attribution`'a
dokunmuyor. Sonuç: **bu sınıf ödül ÜRETMEZ.** Uygulama satın alma
öncesi `Purchases.logIn(uid)` çağırdığı için sınıf pratikte dar, ama
kapatılmadı.

**Zamanlanmış işte yeniden deneme YOK.** `rytho-partner-mature` işi her gün
02:30'da koşuyor (`infra/create-scheduler.ps1:157`) ve betik işlere
`--max-retry-attempts` **vermiyor** (`create-scheduler.ps1:129`), yani Cloud
Scheduler varsayılanı (`retryCount=0`) geçiyor. Telafi bu yüzden **sorguya
gömülü**: sorgu "`status == pending` VE `maturesAt <= şimdi`" biçiminde
(`partner_service.py:349-352`), yani kaçırılan bir gün kendiliğinden
kapanır. İdempotans da durum alanından gelir, `Increment`'ten değil — iki
kez koşan iş aynı dokümanı ikinci kez `pending` bulamaz.

**"Programdan çıkarılırsa kesinleşmemiş hakedişler düşer" KODDA YOK.**
Hukuk metni (madde 9 / section 9) bunu taahhüt ediyor ama hiçbir kod yolu
uygulamıyor (ölçüldü 2026-09-27): ortağı pasifleştirmek yalnız YENİ
hakedişi engelliyor (`partner_service.py:246-248`), mevcut `pending`
kayıtlara dokunmuyor; olgunlaştırma sorgusu da yalnız `status` ve
`maturesAt`'a bakıyor (`partner_service.py:349-352`), ortağın `active`
alanına bakmıyor. Yani kötüye kullanım yüzünden pasifleştirilen bir ortağın
bekleyen hakedişleri 15 gün sonra **kendiliğinden `qualified` olur** ve
panelde `earnedTry`/`balanceTry`'a girer — sahip o tutarı ödenecek borç
olarak görür. Taahhüdü şu an **elle** yerine getirmek gerekir (panelden
negatif ödeme kaydı, `partner_service.py:578-580`). Sessiz olan taraf bu:
hiçbir yerde uyarı çıkmıyor.

**İade taraması düşerse hakediş beklemede kalır**
(`partner_service.py:321-326`), kesinleşmez. Para ödemesi tek yönlüdür;
şüphede beklemek doğru taraf.

---

## 9. İşletme

* **`rewardTry` ortak başına panelden** ayarlanır
  (`web/rytho-admin/gorunumler/ortaklar.js:145`, `ortaklar.js:317`);
  varsayılan ₺30 yalnızca bir başlangıç noktası.
* **Tavan ₺500** ve bu bir **yazım hatası kapısıdır**
  (`partner_service.py:77`): 30 yerine 3000 yazılırsa her kazanılan abone
  abonelik fiyatının on katına mal olur ve bunu fark ettirecek hiçbir
  sinyal yoktur. Panel aynı sayıyı kendi sabitinde tutuyor
  (`ortaklar.js:61`, `ODUL_TAVANI = 500`) — **iki kopya, bekçisiz**. Biri
  değişirse panel geçerli bir tutarı reddeder ya da sunucu panelin kabul
  ettiği tutarı 400'ler.
* **Tutar hakediş anında DONDURULUR** (`partner_service.py:263-273`,
  `rewardTry` dokümana kopyalanır). Panelden ödül değişince geçmiş hakediş
  **yeniden fiyatlanmaz**. Kodun önceki hâli anlık `sharePercent` hesabı
  yapıyordu ve tam tersini — ödenmiş dönemleri bile — yeniden
  fiyatlandırıyordu.
* **Pasif ortak yeni hakediş kazanmaz**, geçmişi durur
  (`partner_service.py:246-248`).
* **Ödeme defteri bakiyeyi aşamaz** (`partner_service.py:581-585`):
  bakiyeden fazla pozitif ödeme `exceeds_balance` ile düşer. Defter gerçek
  para transferinin aynasıdır; aynanın bakiyeyi aşması ya yanlış tutarı ya
  iptal edilmiş bir hakedişi gösterir.

---

## 10. Kod deseni — dört kopya, ikisi bağlı

| Yer | Desen |
|---|---|
| `backend/services/partner_service.py:67` | `^[A-Z0-9_-]{4,24}$` |
| `web/r/index.html:80` | `^[A-Z0-9_-]{4,24}$` |
| `apps/mobile/lib/core/partner_referrer.dart:33` | `^[A-Z0-9_-]{4,24}$` |
| `web/rytho-admin/gorunumler/ortaklar.js:380` | `^[A-Za-z0-9_-]{4,24}$` |

⚠️ **Dördü birebir aynı DEĞİL** (ölçüldü). Panel formundaki kopya
`A-Za-z` — küçük harfi de kabul ediyor. Bu **kasıtlı ve doğru**: panel
kodu kullanıcının yazdığı gibi gönderiyor, sunucu `normalize_code`
(`partner_service.py:117-121`) ile büyütüyor, alanın yardım metni de
"küçük girilse de BÜYÜK saklanır" diyor. Panelde `A-Z` olsaydı geçerli bir
kod formda reddedilirdi.

Bekçiler:

* `backend/tests/test_web_seo.py` →
  `test_ortak_baglanti_sayfasi_backend_ile_ayni_kod_desenini_kullaniyor`
  — **sayfa ↔ backend**: sayfadaki `var DESEN = /…/;` dizesini
  `partner_service._KOD_DESENI.pattern` ile birebir karşılaştırır. Ayrıca
  `utm_campaign=`, `&referrer=` ve `noindex` varlığını sabitler.
* `apps/mobile/test/partner_referrer_test.dart` → `desen backend ve
  sayfayla aynı sözleşmeyi taşır` — **istemci kopyası**:
  `kOrtakKodDeseni.pattern` dize literaline pinlenir. Yani backend'i
  import etmez, aynı literale bağlanır.
* **Panel kopyasını bağlayan test YOK.** Hiçbir bekçi `ortaklar.js`
  desenini okumuyor. Panelde sessizce ayrışabilir; iyi haber, ayrışma
  yönü zararsız tarafta (form daha gevşek).

---

## 11. Hukuk metni

"Ortaklık programı" maddesi iki dile de eklendi:
`web/legal/kullanim.html` (madde 9) ve `web/en/legal/terms.html`
(section 9); ikisinde de "İletişim / Contact" 10'a kaydı, diğer madde
numaraları **değişmedi**.

**"Son güncelleme" tarihi de değişti** (5 Ağustos 2026 → 27 Eylül 2026, iki
dilde). İlk hâlinde atlanmıştı: madde eklenip tarih eski kalırsa sayfa,
metnin Ağustos'tan beri değişmediğini **beyan eder** ve o beyan yanlıştır.
Gizlilik sayfalarının tarihi DEĞİŞMEDİ, çünkü içerikleri değişmedi.

⚠️ **Şartların DÖRT kopyası var, ikisi bu turda güncellendi** (ölçüldü
2026-09-27):

| Kopya | Ortaklık maddesi |
|---|---|
| `web/legal/kullanim.html` | **VAR** (madde 9) |
| `web/en/legal/terms.html` | **VAR** (section 9) |
| `docs/legal/kullanim-sartlari.md` | **YOK** — hâlâ 9 bölüm, 9'u İletişim |
| `apps/mobile/lib/features/profile/legal_texts.dart` (`kTermsOfUseTr/En`) | **YOK** |

`docs/legal/*.md` dosyalarına hiçbir kod, betik ya da test referans
vermiyor (arandı) — yani HTML'i besleyen bir kaynak mı, bayat bir artık mı
belirsiz. Kaynaksa: birisi HTML'i o markdown'dan yeniden üretirse ortaklık
maddesi **sessizce silinir**. Bu dosya bu paketin bildirilen dosya
listesinde olmadığı için dokunulmadı; kararı sahibi verir (ya markdown
güncellenir ya "artık kaynak değil" diye işaretlenir).

Uygulama içi kopya ayrı bir karar: madde ortağı bağlıyor, uygulama
kullanıcısını değil, ve `kTermsConsentVersion` (`apps/mobile/lib/core/consent.dart:20`) 1'de
duruyor — yani mevcut kullanıcılardan yeniden kabul İSTENMİYOR. Bilinçli
sayılabilir ama **ölçülmüş bir çelişki var**: uygulama içi şartlar
"2 Ağustos 2026", web "27 Eylül 2026" diyor ve ikisi aynı belge adını
taşıyor. İki kopyayı bağlayan test de yok
(`apps/mobile/test/legal_texts_test.dart` yalnız gizlilik metnini kodla
karşılaştırıyor).

⚠️ **Katılım cümlesi bir kez yanlış yazıldı ve ölçümle düzeltildi.** İlk
hâli "herkese açık bir başvuru yoktur" diyordu; oysa paralel yürüyen
ortaklık sayfası (`web/ortaklik.html`, başka bir pakete ait) e-postayla
başvuru yolunu **açıkça tarif ediyor** ("Başvurular elle
değerlendiriliyor"). Hukuk metni ile açılış sayfası aynı konuda iki farklı
şey söylüyordu. Doğru ve iki sayfada da geçerli olan ifade: **başvuru ya da
davet üzerine, kabulümüz ve ayrı bir anlaşmayla** katılım — başvurmak tek
başına hak vermez. Ortaklık sayfası bir gün "anında katıl" derse bu cümle
yeniden yanlış olur.

Madde **sayı yazmıyor** (ne ödül tutarı ne ödeme eşiği) — tutar ortak
anlaşmasında belirlenir ve `rewardTry` ortak başına değişebilir. Metne
sayı girmek, bir ortağın tutarı değiştiğinde hukuk metnini yalan yapardı.

⚠️ **Bu madde hukukçu onayı BEKLİYOR.** Mevcut sayfaların hiçbirinde
hukukçu onayı notu yoktu, dolayısıyla korunacak bir not da yoktu; bu satır
o boşluğun kaydıdır. Vergi yükümlülüğü, ödeme eşiği ve fesih halinde
kesinleşmemiş hakedişin düşmesi maddeleri **iş kararı olarak** yazıldı,
hukuki görüş alınmadı.

⚠️ **Ölçülmüş bekçi boşluğu:** `backend/tests/test_honesty.py:72-76`
listesindeki yayına çıkan sayfalar arasında **`web/en/legal/terms.html`
YOK** (TR karşılığı `web/legal/kullanim.html` listede var). Yani İngilizce
şartlar sayfasında yasak pazarlama dili (ör. "unlimited chat") bekçisiz
geçer. Bu belge o dosyaya sahip olmadığı için düzeltilmedi; listeye
eklenmesi ayrı bir iş.

---

## 12. Nereye bakılır

| Soru | Dosya |
|---|---|
| Ödül ne zaman doğar / iptal olur | `backend/api/billing.py:420` |
| Hakediş yaşam döngüsü, tavan, olgunlaşma | `backend/services/partner_service.py` |
| Ortağın kendi panosu ve kapısı | `backend/api/partners.py`, `backend/core/auth.py:286` |
| Yönetim panelindeki ortak görünümü | `web/rytho-admin/gorunumler/ortaklar.js` |
| Kodun cihaza gelişi | `apps/mobile/lib/core/partner_referrer.dart` |
| Ortak bağlantısı sayfası | `web/r/index.html` |
| Günlük olgunlaştırma işi | `infra/create-scheduler.ps1:157` |
| Senaryolar | `docs/test-raporu.md` (143-148) |

## Pano dili (2026-10-10)

Ortak panosu (`rytho.app/affiliate/`, eski `/ortak/` 301 ile yönlenir) en/tr: sıra `?lang=` → ortağın menüden seçtiği dil (tarayıcıda saklı) → en (2026-10-19, sahip kararı).
Ortak kaydında dil alanı yok; elle QA `?lang=en` ile. Sunucunun `detail`
metni olduğu gibi geçer (dili sunucu seçer). Bekçi `backend/tests/test_web_ortak.py`.

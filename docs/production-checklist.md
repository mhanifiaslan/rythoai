# Üretim Yayın Kontrol Listesi

Bu liste **v1 kapsamına** göre yazıldı. Kapsam dışı bırakılanlar burada da
yok: gönderi akışı, birebir mesajlaşma, takip ilişkileri.
Gerekçeler: `docs/store-review-notes.md`.

**Yüz okuma artık kapsam İÇİNDE.** Bir dönem çıkarılmıştı (sunucuda görüntü
işleme gerektiriyordu); şimdi tamamen cihaz üstünde çalışıyor — görüntü
telefondan çıkmıyor, diske bile yazılmıyor. Gizlilik beyanları
`docs/store-privacy-labels.md` içinde güncellendi.

İşaretli maddeler **kodda doğrulanabilir**. İşaretsiz olanların çoğu
konsol/hesap işlemi gerektirir ve uygulama sahibinin işidir.

---

## 1. Lisans ve hukuk

- [ ] **Swiss Ephemeris ticari lisansı** — kerykeion/pyswisseph AGPLv3.
      Kapalı kaynak mağaza yayını öncesi Astrodienst AG'den ticari lisans
      alınmalı (~750 CHF, tek seferlik): https://www.astro.com/swisseph/
      **→ Yayından önce zorunlu, uygulama sahibinin işi. Kod bu kutuyu
      kapatamaz; lisans satın alınmadan işaretlenmemeli.**
- [x] Gizlilik politikası ve kullanım şartları **iki dilde, uygulama içinde**
      (`apps/mobile/lib/features/profile/legal_texts.dart`; Profil → Hakkında
      ve satın alma ekranından erişilebilir)
- [x] Metinler gerçek ürünü anlatıyor: bildirim katmanı, kullanıcı hafızası,
      abonelik, arkadaş katmanı ve **yüz okuma** yazılı; kaldırılan
      özellikler (gönderi, DM) metinlerden çıkarıldı
- [x] Gizlilik politikasında yüz okuma bölümü var (TR + EN) ve iddiaları
      kodla test edilerek bağlanmış
      (`apps/mobile/test/legal_texts_test.dart`)
- [ ] **Hukukçu incelemesi** — metinler mühendislik taslağıdır; KVKK/GDPR
      açısından yayın öncesi gözden geçirilmeli
- [ ] Hukuki metinleri bir web adresinde yayınla (mağaza formları URL ister;
      Firebase Hosting yeterli)
- [x] Gizlilik etiketleri beyanı hazır (`docs/store-privacy-labels.md`)
- [ ] Beyan iki konsola girildi

## 2. Güvenlik

- [x] Firebase Auth ID token doğrulaması (üretimde `RYTHO_DEV_MODE=0`;
      401 canlıda doğrulandı)
- [x] Firestore kuralları deploy edildi. `users/{uid}` **yalnızca sahibine
      okunabilir** (doğum verisi içerir); arkadaşların gördüğü alanlar ayrı
      `publicProfiles/{uid}` kartında
- [x] `users/{uid}/private/**` istemciye tamamen kapalı (hafıza, abonelik,
      bildirim gönderim kaydı) — yalnızca Admin SDK erişir
- [x] Gemini anahtarı, RevenueCat webhook anahtarı ve bildirim zamanlayıcı
      anahtarı Secret Manager'da
- [x] Rate limiting (`backend/core/ratelimit.py`) — LLM uçları 10/dk,
      diğerleri 60/dk
- [x] Ham istisna metni kullanıcıya sızmıyor (`core/messages.py`); güvenlik
      başlıkları yayında
- [x] Toplu bildirim ucu yalnızca paylaşılan zamanlayıcı anahtarıyla çalışıyor
- [x] Firebase App Check **kod tarafı** (1.15.8+43): `firebase_app_check`
      eklendi, `main.dart` açılışta Play Integrity ile etkinleştiriyor
      (debug'da debug sağlayıcı; istisna yutuluyor)
- [ ] App Check **konsolu ve zorlaması** — uygulama sahibinde; adımlar
      `docs/store-launch.md` §3. Sıra önemli: önce sağlayıcı tanıtılır,
      yeni sürüm testçilere yayılır, SONRA Enforce açılır. Erken açmak
      eski paketi olan testçileri kilitler
- [ ] API anahtarı kısıtlaması (Android: paket + iki SHA-1; Browser:
      referrer) — App Check'i tamamlayan ikinci kapı
- [x] **Zorunlu güncelleme kapısı sunucuda** (PBZ, 1.15.0+35): `/api/v1/`
      altındaki istekler `X-App-Build` taşır, eşiğin altı 426 alır
      (`core/app_gate.py`). Eşik `config/app.minBuild`'den okunur; canlı
      değeri şu an 0 (kimse engellenmiyor) ve ancak yeni sürüm mağazada
      yayıldıktan sonra yükseltilir (K9 doğrulaması bunu zorlar)
- [x] **Tek cihaz kilidi** (TC, 1.15.1+36): Rytho+ aynı anda tek cihazda;
      hakem Firebase ID token'ındaki `auth_time` ("son giriş kazanır").
      Çıkış cihazı serbest bırakır (`DELETE /device/claim`)
- [x] **Rol ayrımı ve fail-closed denetim izi** (AD1/AD3): `owner` /
      `support`; yıkıcı uçlarda ön-iz yazılamazsa işlem YAPILMAZ (503).
      `admin: true` claim'i zorunlu koşul — rol tek başına yetki vermez
      (2026-09-15'te sıkılaştırıldı)
- [ ] Cloud Run soğuk başlatma / maliyet dengesi gözden geçir

## 3. Hesap ve veri hakları

- [x] **Uygulama içi hesap silme** (Apple 5.1.1(v) / Play zorunluluğu) —
      Profil → Hesabı sil. Ne silineceği ve ne silinmeyeceği yazılı, yazarak
      onay isteniyor
- [x] Silme tüm yayılımı kapsıyor: alt koleksiyonlar, **karşı taraftaki
      arkadaşlık kayıtları**, gönderilen tepkiler, kullanıcı adı rezervasyonu,
      herkese açık kart, kişiye özel yapay zeka üretimleri, Firebase kimliği
      ve — 2026-09-15'te eklendi — `users/{uid}` ağacının DIŞINDAKİ uid'li
      kayıtlar: `usageEvents`, `phoneAttempts`, `feedback`
      (`backend/services/account_service.py`, bekçi:
      `tests/test_account_deletion.py`)
- [x] Silinmeyen iki kayıt YAZILI: `revenueEvents` (mali belge, 5 yıl) ve
      `adminAudit` (denetim izi). Üç hukuk metninde de adıyla geçiyor;
      `apps/mobile/test/legal_texts_test.dart` bunu zorluyor
- [x] Şikayet kayıtları bilinçli olarak korunuyor (başkalarının güvenliği) —
      gizlilik metninde ve silme onayında yazılı

## 4. Ürün ilkeleri (kodda korunuyor)

- [x] Hiçbir gök verisi uydurulmuyor; her konum Swiss Ephemeris ile hesaplanıyor
- [x] Yasak alan kapısı (sağlık/hamilelik/ölüm/finans) **iki dilde** çalışıyor
      ve modele hiç gitmiyor
- [x] Persona yağcılık yapmıyor; testle korunuyor
- [x] Kullanıcılar arası **serbest metin yok** — kapalı tepki kümesi
- [x] Kalıcı uyum skoru yok; ikili dinamik günlük

## 5. Birim ekonomi

- [x] Ücretsiz katman paylaşımlı önbellekten okuyor: burç yorumu dil × burç ×
      dönem başına tek LLM çağrısı
- [x] Bildirim metni burç başına üretiliyor — günde en fazla 24 çağrı,
      kullanıcı sayısından bağımsız
- [x] Kişiye özel uçlar abonelik veya günlük kotayla korunuyor
      (`backend/core/entitlements.py`)
- [ ] Önbellek isabet oranını canlıda izle (maliyet öngörüsü buna bağlı)

## 6. Çok dillilik

- [x] TR + EN: arayüz, backend yorumları, hata metinleri, bildirimler
- [x] Hesap motorları dilden bağımsız anahtar döndürüyor; ad isteğin dilinde
      çözülüyor
- [x] Dil sızıntısı muhafızı (`backend/tests/test_language_isolation.py`)
- [x] Mobil sabit metin tarayıcısı (`apps/mobile/tool/scan_hardcoded_strings.py`)

## 7. Bildirimler

- [x] Cloud Scheduler → saatlik toplu gönderim; yerel saat, sessiz saat,
      tercih ve tekrar koruması
- [x] Yüksek öncelikli Android kanalı; uygulama ön plandayken de gösteriliyor
- [x] Saat dilimi ve dil profile yazılıyor (`flutter_timezone`)
- [x] Geçersiz token ilk başarısız gönderimde temizleniyor
- [x] Cihazda gerçek push doğrulandı
- [ ] Canlıda ilk gerçek sabah gönderimini izle (log: `api.notify`)

## 8. Kalite

- [x] Crashlytics bağlı (debug/web'de devre dışı)
- [x] **Uygulama içi geri bildirim kanalı** (GB, 1.15.4+39): Profil →
      Geri bildirim → sunucu → panel sekmesi → push ile yanıt. Kapalı
      testin asıl geri bildirim yolu bu; harici kanal gerekmiyor
- [x] Backend test takımı — 300+ test
- [x] Analytics olay şeması temiz (kapalı test denetiminde doğrulandı,
      2026-09-14): `apps/mobile/lib/core/analytics.dart` kaldırılmış
      özelliklerin olaylarını (`post_published`, `user_followed`,
      `channel_subscribed`, `face_analyzed`) artık taşımıyor; yerine
      onboarding hunisi, abonelik dönüşümü ve bildirim olayları var.
      Dosyanın kendi kuralı: "burada yalnızca var olan akışların
      olayları durur" ve "olaylara kişisel veri girmez"
- [ ] iOS derlemesi (macOS gerektirir) + TestFlight
- [x] Android imzalama anahtarı üretildi (`key.properties`, 2026-08-07;
      build.gradle.kts release bloğu bağlı, build-aab.ps1 KT4'te imzayı
      doğruluyor); Play Console iç test kanalı canlı — sıradaki adım
      kapalı test (`docs/store-launch.md` §2b)
- [ ] Yük testi: rapor uçları LLM'e bağlı

## 9. Monetizasyon

- [x] Freemium abonelik, **yalnızca aylık** (RevenueCat)
- [x] Satın alma ekranında: plan adı, fiyat, deneme koşulu, otomatik yenileme
      ve iptal bilgisi, Gizlilik ve Şartlar bağlantıları, içgörü ibaresi
- [x] Paywall ilk değerden sonra açılıyor; abone olmayan kullanıcı için
      kilitli uçlara istek atılmıyor
- [x] RevenueCat kimliği Firebase oturumuna bağlı; TRANSFER olayı işleniyor
- [ ] **Gerçek mağaza ürünleri** — Play Console tarafı, uygulama sahibinin
      işi. Deneme MAĞAZAYA KONMAZ (KT kararı): 3 günlük deneme sunucu
      tarafında (OT6) — mağaza denemesi eklemek 3+3 çakışması yaratır
- [x] `REVENUECAT_ANDROID_KEY` gerçek (`goog_` önekli) anahtar; build-aab
      `test_` görürse artık THROW eder (iOS anahtarı iOS turunda)

## 10. Mağaza inceleme

- [ ] Test hesabı hazır (onboarding tamam + Rytho+ yetkisi)
- [ ] İnceleme notu yapıştırıldı (`docs/store-review-notes.md` §3)
- [ ] Ekran görüntülerinde gerçek harita/gökyüzü görünüyor — 4.3 savunmasının
      görsel karşılığı
- [ ] Yaş derecelendirmesi: App Store 12+, Play Teen
- [ ] Mağaza açıklamasında sağlık iddiası veya kesin kehanet dili yok

## 11. Ürün işleri — ÜÇÜ DE BİTTİ (2026-09-15'te doğrulandı)

Bu bölüm bir dönem "henüz yapılmamış" diye duruyordu ve kendi §12'siyle
çelişiyordu. Kapalı test denetiminde üçünün de kodda bittiği doğrulandı:

- [x] Dışa paylaşım kartı — `features/share/share_card.dart` (`_renderCard`,
      ekran dışı PNG üretimi; R5'te rapor/yıl kartlarına genişledi)
- [x] Davet bağlantısı deep-link'i — App Links ile, Dynamic Links'siz
      (§12: assetlinks release imzasıyla doğrulandı, `/i/{kullanıcı}` canlı)
- [x] Rehber eşleştirme — `core/contact_match.dart` + `api/contacts.py`,
      varsayılan KAPALI ve karşılıklı rıza şartlı

## 12. Davet baglantisi (App Links / Universal Links)

- [x] Firebase Hosting yayinda: `https://rhytoai.web.app`
- [x] `/.well-known/assetlinks.json` (Android dogrulama) — 200, JSON tipi
- [x] `/i/{kullanici}` karsilama sayfasi (uygulama kurulu degilse magazaya)
- [x] Manifest intent-filter + `android:autoVerify="true"`
- [x] Uygulama baglantiyi yakaliyor, kullanici adi arkadas ekleme kutusuna
      doluyor; gecersiz ad reddediliyor
- [x] **Release imza parmak izi eklendi** (680d0bb, 2026-08-12):
      `assetlinks.json` 4 parmak izi taşıyor — debug + Play App Signing
      GERÇEK imzası (cihazdaki APK'dan apksigner ile okundu) + Play
      Console'dan kopyalanan ve EŞLEŞMEDİĞİ kanıtlanan iki eski kayıt
      (CC:95…, AE:3F… — zararsız, temizlenebilir). Magazadan inen pakette
      App Links doğrulanıyor.
- [x] **iOS Team ID eklendi** (`c3dca0e`, 2026-09-27): AASA
      `292WJ9TP74.ai.rytho` tasiyor (`/i/*` + `/r/*`). Kalan is Team ID
      yazmak DEGIL: hosting deploy'u (kilitli — `docs/mac-devir.md` §4
      "Deploy bagimliliklari ve hosting kilidi") ve ardindan Apple CDN'in
      yeni govdeyi cekmesi (canli AASA ve CDN 2026-10-24'te hala
      `TEAMID` + yalniz `/i/*`). *(Duzeltme 2026-10-24: bu madde
      "TEAMID gercek Team ID ile degistirilmeli" diye acik duruyordu.)*
- [ ] **iOS Universal Links canlida:** hosting deploy'u (kilitli,
      `docs/mac-devir.md` §4) yapildi VE Apple CDN yeni govdeyi cekti —
      canli AASA ve `app-site-association.cdn-apple.com/a/v1/rytho.app`
      `292WJ9TP74.ai.rytho` + `/r/*` veriyor. Bu kutu isaretlenene kadar
      iOS'ta `/i/` ve `/r/` baglantilari uygulamayi ACMAZ.
- [x] Kendi alan adi alindi: `rytho.app` (2026-09-15), `kInviteHost =
      'rytho.app'` (`core/deep_links.dart`). *(Duzeltme 2026-10-24: madde
      "alinirsa" diye acik duruyordu.)*

## 13. Giris ekrani

- [x] Apple ile Giris (Guideline 4.8) — yalnizca iOS'ta gorunur, nonce ile
      yeniden oynatma korumasi, Apple'in ilk giriste dondurdugu ad yakalaniyor
- [x] Hukuki metinlere TIKLANABILIR baglanti (Kullanim Sartlari + Gizlilik)
- [x] Kayitta 13 yas beyani
- [x] Kayittan sonra e-posta dogrulama baglantisi gonderiliyor
- [x] Sifre kurali: 8 karakter + harf/rakam-sembol karisimi (eski kural
      Firebase'in alt siniri 6 idi ve "123456"yi geciriyordu)
- [x] Sifre sifirlamada kullanici sayimi sizintisi kapatildi — sonuc ne
      olursa olsun ayni notr mesaj
- [x] Saglayici cakismasi cikmazi: sifreyle giris basarisiz olunca her iki
      olasilik birden soyleniyor
- [x] Sosyal girisler formun ALTINDA, iOS'ta Apple ustte
- [x] autofillHints + AutofillGroup (sifre yoneticileri artik taniyor)
- [x] Odak zinciri (klavye "Sonraki" tusu calisiyor)
- [x] Sekme degisince form ve hatalar temizleniyor
- [x] Eszamanli giris engellendi
- [x] ios/Runner/Runner.entitlements: applesignin + associated-domains
- [ ] **Apple Developer hesabi — ERTELENDI (2026-08-01 karari).** Uyelik
      satin alinmadi; iOS yayini kendi turunda yapilacak. Bu Android'i
      ETKILEMEZ: Apple dugmesi yalnizca iOS'ta gorunuyor, Android derlemesi
      ve testler bundan bagimsiz calisiyor. Kod ve entitlements hazir,
      yalnizca konsol ayarlari eksik. Hesap acilinca yapilacaklar:
      1. App ID (`ai.rytho`) uzerinde "Sign in with Apple" yetenegini AC.
      2. Firebase Console > Authentication > Sign-in method > Apple'i etkinlestir;
         Service ID, Team ID ve Key (.p8) gir.
      3. Xcode > Runner > Signing & Capabilities > "Sign in with Apple" ekle
         (entitlements dosyasi hazir, Xcode'un projeye baglamasi gerekiyor).
      4. `web/.well-known/apple-app-site-association` icindeki TEAMID'yi
         gercek Team ID ile degistir ve hosting'i yeniden deploy et.
      Bu adimlar tamamlanmadan Apple dugmesi iOS'ta gorunur ama calismaz.
      → **BAYAT (2026-10-24).** Uyelik ucretli ve etkin (sahip teyidi,
      2026-10-22; CLAUDE.md §7) — "ERTELENDI" artik dogru degil. Adim 3
      gereksiz: pbxproj `CODE_SIGN_ENTITLEMENTS`'i uc yapilandirmada zaten
      bagliyor (Debug/Profile `Runner.entitlements`, Release
      `RunnerRelease.entitlements`). Adim 4 depoda yapildi (`292WJ9TP74`,
      `c3dca0e`); kalan yalniz hosting yayini (kilitli, §12). Adim 2'de
      Services ID'nin Return URL yapilandirmasi eksikti. Guncel, tam yollu
      sira `docs/mac-devir.md` §4: A2 (App ID'de Sign in with Apple,
      primary), A4 (Firebase'de Apple saglayicisi — giris icin yalniz
      Enable + Save yeter), C7 (Apple ile Giris anahtari, Services ID +
      Return URL, Firebase'de OAuth code flow, e-posta kaynagi — hesap
      silmede yetki iptali ve Hide My Email icin). Konsol durumlarinin
      hicbiri olculmedi; bu madde konsol isleri bitince isaretlenir.
      → **2026-10-28 (iPad, gelistirme imzali Profile):** Apple ile Giris
      calisti — saglayici acik (A4; U01 kapandi), once bir KOD kusuru
      onarildi (U57). Silmede Apple yetkisi iptali Ayarlar'daki listeyle
      olculdu (C7, U15; ilk-kez sayfasinin donmemesi acik). Kalan: e-posta
      kaynagi kaydi (U22) olculmedi — madde o yuzden isaretsiz.

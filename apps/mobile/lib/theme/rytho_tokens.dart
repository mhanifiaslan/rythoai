/// Tasarım token'ları — boşluk, yarıçap, süre ve tip rolleri.
///
/// ## Neden var
///
/// Bu dosyadan önce hiçbiri sabit değildi ve sonuç ölçülebilirdi:
///
/// * 40'tan fazla farklı font boyutu; 12.5, 13.5, 14.5, 9.5 gibi yarım punto
///   varyasyonlar her ekranda yeniden uydurulmuştu.
/// * Üç ayrı "kart" yarıçapı dolaşıyordu: `GlassPanel` 22, `_OracleCard` 20,
///   `PromoBanner` 24. Aynı ekranda yan yana duruyorlardı.
/// * `SizedBox` boşlukları 2'den 72'ye kadar 20 farklı değer alıyordu.
///
/// Tutarsızlık burada bir zevk meselesi değil: kullanıcı "dağınık, insanı
/// yoran bir yapı" diye tarif etti. Göz, hizalanmayan kenarları ve tutmayan
/// ritmi bilinçaltında gürültü olarak okuyor.
///
/// ## Nasıl kullanılır
///
/// Yeni kod **çıplak sayı yazmaz**. Var olan ekranlar dokunuldukça geçirilir;
/// hepsini tek seferde değiştirmek 40'tan fazla çağrı yerini aynı anda riske
/// atmak olurdu.
library;

import 'package:flutter/widgets.dart';

import 'rytho_theme.dart';

/// Marka sözcükleri — çevrilmez, tek yerden okunur.
///
/// Ölçüldü (2026-10-10): `'RYTHO'` 6 dosyada, `'Rytho+'` 4 dosyada,
/// `'Rytho AI'` 1 dosyada literal olarak yazılıydı. Marka adı ARB'ye
/// konmaz (çeviri konusu değil) ama literal de olmaz — beş kopyanın dördü
/// ayrışır (CLAUDE.md §5).
const kMarka = 'Rytho';

/// Logo yazısı (büyük harf): giriş başlığı, paylaşım kartı, açılış.
const kMarkaYazi = 'RYTHO';

/// Abonelik ürününün adı — mağaza listelemesiyle aynı.
const kPlusAdi = 'Rytho+';

/// Logo yazısı (wordmark). BÜYÜK harf tasarım kararı, Türkçe büyütme
/// tuzağı değil (ASCII). Giriş ve açılış ekranı üç kopya taşıyordu.
const kMarkaAdi = 'RYTHO';

/// Boşluk ölçeği. Dörtün katları — ara değer yok.
abstract final class RythoSpace {
  /// Hairline ayrım: ikon ile metin arası, rozet iç dolgusu. Ölçüldü:
  /// kodda 15 yerde `2` literali vardı ve hepsi bu anlamdaydı; ölçekte
  /// karşılığı olmadığı için literal kalıyorlardı.
  static const xxs = 2.0;

  /// Sıkı gruplama: bir etiketle değeri arası.
  static const xs = 4.0;

  /// İlişkili öğeler arası.
  static const sm = 8.0;

  /// Kart içi öğeler arası — en sık kullanılan.
  static const md = 12.0;

  /// Kart içi kenar boşluğu ve ekran yatay kenarı.
  static const lg = 16.0;

  /// Bölümler arası.
  static const xl = 24.0;

  /// Büyük ayrım — ekran üstü/altı nefes payı.
  static const xxl = 32.0;

  /// Alt gezinme çubuğunun kapladığı yer. Liste sonlarına bu eklenir,
  /// yoksa son kart dock'un altında kalıyor.
  static const dockClearance = 130.0;
}

/// Köşe yarıçapları.
abstract final class RythoRadius {
  /// İlerleme çubukları, ince şeritler, tutamak. Ölçüldü: 2/4/5/6
  /// literalleri hep bu anlamdaydı.
  static const xs = 4.0;

  /// Küçük öğeler: çip, rozet, küçük buton.
  static const sm = 12.0;

  /// Giriş alanları, ikincil yüzeyler.
  static const md = 16.0;

  /// **Kartlar.** Tek kart yarıçapı budur; `GlassPanel` varsayılanı.
  static const card = 22.0;

  /// Hap biçimi (tam yuvarlak uçlar).
  static const pill = 999.0;
}

/// Animasyon süreleri.
///
/// Kod tabanında 120/260/280/320/360/380/800/1600 ms serbestçe dolaşıyordu.
/// Aynı ekranda 320 ve 380 ms yan yana çalışınca göz senkronsuzluk görüyor.
abstract final class RythoMotion {
  /// Dokunma tepkisi, çip seçimi — kullanıcı beklemesin.
  static const fast = Duration(milliseconds: 160);

  /// Standart geçiş: kart açılması, durum değişimi.
  static const base = Duration(milliseconds: 260);

  /// Giriş animasyonu, sayfa açılışı.
  static const slow = Duration(milliseconds: 380);

  /// Tören anları: reveal, kutlama — "özel bir şey oluyor" süresi.
  static const slower = Duration(milliseconds: 600);

  /// Listede kademeli giriş için öğe başına gecikme.
  static const stagger = Duration(milliseconds: 70);

  // --- Ölçülüp adlandırılan süreler (D2) ---
  //
  // Aşağıdakiler kodda zaten vardı ama çıplaktı (66 satır/36 dosya); kaynak
  // bekçisi "çıplak süre sıfır" diyebilsin diye adlandırıldı. Değerler
  // DEĞİŞTİRİLMEDİ — ölçüldüğü gibi.

  /// Dokunma basma tepkisi: `Pressable`/`GoldButton` ölçek animasyonu.
  static const press = Duration(milliseconds: 120);

  /// Sayfa geçişi (`FadeThroughRoute`).
  static const route = Duration(milliseconds: 350);

  /// Sürekli nefes döngüsü (dock merkez düğmesi). Beyaz listedeki tek
  /// sürekli döngülerden; `reduceMotion`'da durur.
  static const breath = Duration(milliseconds: 3000);

  /// Çark taraması (`ChartWheel` giriş süpürmesi).
  static const sweep = Duration(milliseconds: 1400);

  /// Yazıyor noktaları döngüsü (`TypingDots`).
  static const typing = Duration(milliseconds: 900);

  /// İskelet parıltısı (`SkeletonPanel`).
  static const shimmer = Duration(milliseconds: 1200);

  /// Kutlama/rozet belirmesi (`StreakBadge`, `PlusLockedCard` tek atış).
  static const celebrate = Duration(milliseconds: 400);

  /// Usturlap tam tur (`AstrolabeSpinner`).
  static const spinnerTur = Duration(seconds: 4);

  /// Yıldız alanı tam tur (`CosmicScaffold`).
  static const yildizTur = Duration(seconds: 120);

  /// Bekleme sahnesinde iki aşama metni arası (`StagedWaiting`).
  static const asamaAraligi = Duration(milliseconds: 2600);

  // Eğriler (R12-A0): yeni eğri icat edilmedi — kod tabanında fiilen
  // kazanmış üç eğri adlandırıldı. Yeni kod eğriyi buradan alır.

  /// Giriş/kayma: fadeIn + slide zincirlerinin eğrisi.
  static const enter = Curves.easeOutCubic;

  /// Rozet/balon/kutlama: hafif taşmalı canlılık.
  static const pop = Curves.easeOutBack;

  /// Dokunma tepkisi: basma/bırakma.
  static const settle = Curves.easeOut;
}

/// Tip **rolleri** — boyut değil, iş.
///
/// `RythoText.body(13.5)` yazmak yerine `RythoType.body` yazılır. Boyut bir
/// gün değişirse tek yerden değişir; daha önemlisi, çağrı yerinde "bu metin
/// ne işe yarıyor" sorusunun cevabı görünür olur.
abstract final class RythoType {
  // --- Başlıklar (Sora) ---

  /// Ekranın tek büyük başlığı.
  static TextStyle get screenTitle => RythoText.display(22);

  /// Bölüm başlığı — "Bugün senin için", "Şu an".
  static TextStyle get sectionTitle => RythoText.display(19);

  /// Kart başlığı.
  static TextStyle get cardTitle => RythoText.display(16);

  /// Alt sayfa başlığı (dayanak sayfası, kişi/açı sayfaları).
  static TextStyle get sheetTitle => RythoText.display(17, w: FontWeight.w600);

  /// Ekranın tek büyük değeri: dönüş tarihi, progres Ay burcu, heksagram
  /// adı. Ölçüldü: 24/26/28/30/32 beş ayrı boyut aynı rolü taşıyordu.
  static TextStyle get hero => RythoText.display(28);

  /// Küçük kahraman: kart içi büyük değer.
  static TextStyle get heroSmall => RythoText.display(24);

  // --- Gövde (Manrope) ---

  /// Okuma metni — uzun paragraflar. Satır yüksekliği okunurluk için açık.
  static TextStyle get reading => RythoText.body(15, height: 1.65);

  /// Standart gövde.
  static TextStyle get body =>
      RythoText.body(14, height: 1.55);

  /// İkincil gövde — açıklama, alt metin.
  static TextStyle get bodyDim =>
      RythoText.body(13, color: RythoColors.parchmentDim, height: 1.5);

  /// Küçük yardımcı metin.
  static TextStyle get caption =>
      RythoText.body(12, color: RythoColors.parchmentDim, height: 1.45);

  // --- Etiket (Manrope, aralıklı) ---

  /// Buton metni.
  static TextStyle get button => RythoText.label(13);

  /// Kart üstü küçük etiket, bölüm rozeti.
  static TextStyle get label =>
      RythoText.label(11, color: RythoColors.parchmentDim);

  // --- Veri (JetBrains Mono) ---

  /// Derece, saat, koordinat.
  static TextStyle get data => RythoText.mono(12);

  /// Küçük veri.
  static TextStyle get dataSmall =>
      RythoText.mono(11, color: RythoColors.parchmentDim);

  /// Büyük veri: dört sütun gövdesi, derece vurgusu.
  static TextStyle get dataLarge => RythoText.mono(14);

  // --- Çark ressamı (JetBrains Mono) ---
  //
  // Ölçüldü: ressam 6,5–8,5 px arası beş çıplak boyut kullanıyordu ve
  // yakınlaştırılamayan 248 px çarkta derece etiketi 6,8 px çiziliyordu.
  // İki taban: etiket ve mikro. Mikro bile 8'in altına inmez; çark küçük
  // ve yakınlaştırma yokken derece etiketleri HİÇ çizilmez (gizlenir).

  /// Ev numarası, AS/MC köşe adı.
  static TextStyle get chartLabel => RythoText.mono(9);

  /// Derece etiketi, retro işareti.
  static TextStyle get chartMicro => RythoText.mono(8);
}

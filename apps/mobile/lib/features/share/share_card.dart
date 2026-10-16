import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/tr_metin.dart' show trBuyuk;
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart' show kMarkaYazi;
import '../../widgets/chart/chart_data.dart';
import '../../widgets/chart/chart_palette.dart' show ringGlyphColor;
import '../../widgets/chart/chart_positions.dart' show MiniGlyphPainter;
import '../../widgets/chart/chart_wheel.dart';
import '../../theme/rytho_glyphs.dart' show kPlanetTextGlyphs;
import '../../widgets/nebula_widgets.dart' show signDisplayName;
import '../../widgets/chart/wheel_painter.dart' show WheelAspectFilter;

/// Üç kartın ortak zemini — aynı tuval, aynı degrade; ayrışırsa paylaşılan
/// kartlar aynı uygulamadan çıkmış gibi durmaz.
///
/// Tema tokeni (`RythoColors.shareGradient`) BİLEREK YOK ve bu degrade
/// burada kalır: tek tüketicisi bu dosya ve kart uygulamanın DIŞINA gidiyor
/// — ekran temasından bağımsız, her zaman bu koyu üç durak. Temaya taşımak
/// "tema değişirse kart da değişsin" demek olurdu; paylaşılan görsel
/// tanınır kalmalı, uygulamanın o günkü yüzeyini yansıtmamalı.
const BoxDecoration _kKartZemini = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF13091F), Color(0xFF241038), Color(0xFF0B0713)],
  ),
);

/// 1080×1920 tuvalin dolguları — üç kart aynı üst/alt payı kullanır;
/// yatay pay metin kartlarında 96, çark kartında çarktan türer.
const double _kTuvalYanPay = 96;
const double _kTuvalUstPay = 150;
const double _kTuvalAltPay = 110;

/// Devam sayfasının kısa başlığı ve konum tablosunun puntoları — 1080 px
/// tuval ölçeği (ekran rolleri `RythoType` 390 dp ekran içindir).
const double _kDevamBaslik = 40;
const double _kTabloGlif = 30;
const double _kTabloAd = 28;
const double _kTabloOlcum = 24;
const EdgeInsets _kTuvalDolgu = EdgeInsets.fromLTRB(
    _kTuvalYanPay, _kTuvalUstPay, _kTuvalYanPay, _kTuvalAltPay);

/// Marka satırı: paylaşan kişi uygulamayı tanıtıyor. Ayırt edici iddia da
/// burada — "gerçek gökyüzü hesabıyla". Üç kartta TEK kopya; marka yazısı
/// `kMarkaYazi`dan (rytho_tokens), literal değil.
class _MarkaSatiri extends StatelessWidget {
  const _MarkaSatiri();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(children: [
      Text(kMarkaYazi, style: RythoText.label(44, color: RythoColors.gold)),
      const SizedBox(width: 20),
      Expanded(
        child: Text(l10n.shareCardTagline,
            style: RythoText.body(32, color: RythoColors.parchmentDim)),
      ),
    ]);
  }
}

/// Günlük yorumun dışa paylaşılabilir görsel kartı.
///
/// Kategorinin en güçlü büyüme kanalı: sosyal graf gerektirmez, moderasyon
/// yükü sıfırdır (paylaşılan metni kullanıcı yazmaz, uygulama üretir) ve
/// paylaşan kişi uygulamayı kendi çevresine tanıtır.
///
/// **Gizlilik kuralı: ham doğum verisi karta GİRMEZ.** Kartta yalnızca burç,
/// tarih, yorumdan bir alıntı ve o günün ay evresi var. Doğum tarihi/saati/
/// yeri hassas bir üçlüdür; kullanıcı bunu paylaştığını fark etmeden
/// paylaşmamalı.
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.signName,
    required this.signGlyph,
    required this.reading,
    required this.dateLabel,
    this.moonEmoji,
    this.moonName,
  });

  final String signName;
  final String signGlyph;
  final String reading;
  final String dateLabel;
  final String? moonEmoji;
  final String? moonName;

  /// Instagram story oranı (9:16). Diğer uygulamalar bunu sorunsuz kırpar.
  static const double width = 1080;
  static const double height = 1920;

  /// Metin alanının genişliği ve yüksekliği (dolgu düşülmüş hâliyle).
  static const double _textWidth = width - _kTuvalYanPay * 2;
  static const double _textHeight = 900;

  /// Yorumun sığdırılacağı yazı boyutu aralığı.
  static const double _maxFontSize = 52;
  static const double _minFontSize = 26;

  /// Gövde metninin stili. Ölçüm ve çizim AYNI stili kullanmak zorunda;
  /// aksi halde sığdığı hesaplanan metin ekranda taşar.
  static TextStyle bodyStyle(double size) =>
      RythoText.body(size, height: 1.5);

  /// Metin verilen boyutta alana sığıyor mu?
  ///
  /// [styleBuilder] enjekte edilebilir: uygulamada gerçek yazı tipi kullanılır,
  /// testte ağ erişimi olmadığı için yedek stil verilir. Sığdırma MANTIĞI
  /// yazı tipi kaynağından bağımsız olmalı.
  static bool fitsAt(
    String text,
    double fontSize, {
    double maxWidth = _textWidth,
    double maxHeight = _textHeight,
    TextStyle Function(double)? styleBuilder,
  }) {
    final painter = TextPainter(
      text: TextSpan(
          text: text, style: (styleBuilder ?? bodyStyle)(fontSize)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.height <= maxHeight;
  }

  /// Yorumu **kesmeden** karta sığdıran yazı boyutunu bulur.
  ///
  /// Önceki yaklaşım metni kırpıyordu. Cümle sınırından kesmek yarım cümleyi
  /// önlüyordu ama asıl sorunu çözmüyordu: 90-130 kelimelik bir okumadan
  /// birkaç cümle göstermek, paylaşılan şeyin eksik olması demek. Okumayı
  /// bölmek yerine yazıyı küçültüyoruz — kart dışa açılan yüz, orada eksik
  /// bir metin uygulamanın kendisini eksik gösterir.
  ///
  /// İkili arama: en büyük sığan boyut bulunur. Ölçüm gerçek yazı tipiyle
  /// yapıldığı için tahmin değil.
  static double fittedFontSize(
    String text, {
    double maxWidth = _textWidth,
    double maxHeight = _textHeight,
    double maxSize = _maxFontSize,
    double minSize = _minFontSize,
    TextStyle Function(double)? styleBuilder,
  }) {
    if (text.trim().isEmpty) return maxSize;

    bool sigar(double boyut) => fitsAt(text, boyut,
        maxWidth: maxWidth, maxHeight: maxHeight, styleBuilder: styleBuilder);

    if (sigar(maxSize)) return maxSize;

    var alt = minSize;
    var ust = maxSize;
    // 0.5 punto çözünürlük gözle fark edilmez; 8 tur yeter.
    for (var i = 0; i < 8; i++) {
      final orta = (alt + ust) / 2;
      if (sigar(orta)) {
        alt = orta;
      } else {
        ust = orta;
      }
    }
    return alt;
  }

  /// En küçük boyutta bile sığmayan metin için son çare kırpma.
  ///
  /// Normal bir günlük yorumda (90-130 kelime) buraya HİÇ girilmez; bu yol
  /// yalnızca beklenmedik uzunluktaki bir metnin kartı taşırmasını engeller.
  /// Kırpma yine cümle sınırından yapılır.
  static String clampToSentence(String text, int maxChars) {
    final temiz = text.trim();
    if (temiz.length <= maxChars) return temiz;

    final kesit = temiz.substring(0, maxChars);
    var son = -1;
    for (final isaret in ['. ', '! ', '? ', '.\n']) {
      final i = kesit.lastIndexOf(isaret);
      if (i > son) son = i;
    }
    if (son > maxChars ~/ 3) return kesit.substring(0, son + 1).trim();

    final bosluk = kesit.lastIndexOf(' ');
    return '${kesit.substring(0, bosluk > 0 ? bosluk : maxChars).trim()}…';
  }

  /// Karta girecek metin: kural olarak **TAM okuma**.
  ///
  /// Yalnızca en küçük yazı boyutunda bile sığmayan olağandışı uzunlukta bir
  /// metin kırpılır. Normal bir günlük yorumda buraya hiç girilmez.
  static String bodyText(String reading,
      {TextStyle Function(double)? styleBuilder}) {
    final temiz = reading.trim();
    if (temiz.isEmpty) return temiz;

    if (fitsAt(temiz, _minFontSize, styleBuilder: styleBuilder)) return temiz;

    // Sığan en uzun kırpmayı ikili aramayla bul. Orantı tahmini (yükseklik
    // oranı × karakter sayısı) uzun metinlerde şişiyor ve kart yine taşıyordu.
    var alt = 0;
    var ust = temiz.length;
    while (alt < ust) {
      final orta = (alt + ust + 1) ~/ 2;
      if (fitsAt(clampToSentence(temiz, orta), _minFontSize,
          styleBuilder: styleBuilder)) {
        alt = orta;
      } else {
        ust = orta - 1;
      }
    }
    return clampToSentence(temiz, alt);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: _kKartZemini,
        child: Padding(
          padding: _kTuvalDolgu,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateLabel,
                  style: RythoText.mono(34, color: RythoColors.parchmentDim)),
              const SizedBox(height: 56),
              Row(children: [
                // Burç glifi glif fontundan: ailesiz TextStyle sistem
                // fontuna düşüyordu ve ♈–♓ Emoji_Presentation=Yes olduğu
                // için kartta RENKLİ emoji çıkıyordu (rytho_glyphs.dart).
                Text(signGlyph,
                    style: RythoText.glyph(116, color: RythoColors.goldBright)),
                const SizedBox(width: 28),
                Expanded(
                  child: Text(trBuyuk(signName),
                      style: RythoText.display(84)),
                ),
              ]),
              const SizedBox(height: 64),
              // Okuma KESİLMEZ: sığmıyorsa yazı küçülür. Sabit bir boyutla
              // kesmek, paylaşılan şeyin eksik olması demekti.
              Expanded(
                child: Builder(builder: (_) {
                  final metin = bodyText(reading);
                  // Çizim, ölçümle AYNI stil üreticisini kullanır; ayrışırsa
                  // sığdığı hesaplanan metin kartta taşar.
                  return Text(metin, style: bodyStyle(fittedFontSize(metin)));
                }),
              ),
              if (moonName != null) ...[
                Text('${moonEmoji ?? ''} $moonName'.trim(),
                    style: RythoText.body(36,
                        color: RythoColors.parchmentDim)),
                const SizedBox(height: 40),
              ],
              const _MarkaSatiri(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uzun bir okumanın (tam natal rapor, yıl haritası) paylaşılabilir kartı.
///
/// Günlük kartından farkı: raporun BAŞLIĞI ve ölçülen üç rozet üstte durur,
/// metin bunların altında akar. Rozetler kartın omurgası — paylaşan kişi
/// "benim haritamdan çıkan şey bu" diyebilsin diye.
///
/// **Aynı gizlilik kuralı geçerli: ham doğum verisi karta GİRMEZ.** Rozetler
/// hesaplanmış sonuçlardır (Güneş burcu, yıl evi, Yükselen); doğum tarihi,
/// saati ve yeri hiçbir zaman yazılmaz. Tarih satırı raporun ÜRETİM ya da
/// geçerlilik tarihidir, doğum tarihi değildir.
class ReportShareCard extends StatelessWidget {
  const ReportShareCard({
    super.key,
    required this.title,
    required this.body,
    required this.dateLabel,
    this.badges = const [],
    this.glyph,
    this.sayfaNo = 1,
    this.sayfaSayisi = 1,
  });

  final String title;

  /// Bu kartın sırası ve toplam — rapor birden çok karta bölünür
  /// ([sayfalar]); ilk kart başlık ve rozetleri taşır, sonrakiler devamı.
  final int sayfaNo;
  final int sayfaSayisi;

  /// Rapor metni — markdown işaretlerinden ARINDIRILMIŞ hâlde verilmeli
  /// (`markdownToPlain`); karta `###` basmak bu turun düzelttiği kusurun ta
  /// kendisi olurdu.
  final String body;

  final String dateLabel;

  /// (etiket, değer) çiftleri — en fazla üçü çizilir.
  final List<(String, String)> badges;

  /// Başlığın yanındaki büyük sembol (burç glifi, ☀︎ vb.).
  final String? glyph;

  static const double width = ShareCard.width;
  static const double height = ShareCard.height;

  static const double _textWidth = width - _kTuvalYanPay * 2;

  /// Rapor puntosu — her sayfada AYNI. Tek sayfaya sığdırmak için küçülen
  /// punto (eski `fittedFontSize`) sayfalar arasında boy farkı yapardı.
  static const double punto = 36;

  /// İlk sayfanın metin alanı: rozet varsa daralır (rozet satırı + çizgi).
  static double ilkYukseklik({required bool rozetli}) =>
      980.0 - (rozetli ? 190 : 0);

  /// Devam sayfalarının metin alanı: tarih + kısa başlık satırından sonra
  /// kalan yer (1920 − 150 − 110 dolgu − ~300 başlık/marka). Ölçüm
  /// [ShareCard.fitsAt] ile, yazı tipi gerçek.
  static const double devamYukseklik = 1300;

  /// Bir rapor en çok bu kadar karta bölünür; paylaşım sayfası ve hikâye
  /// akışı için makul tavan. Aşan kısım son kartta "…" ile biter.
  static const int azamiSayfa = 10;

  /// Raporu KESMEDEN sayfalara böler (sahip kararı 2026-10-16: "paylaşınca
  /// verilerin çoğu siliniyor, bu doğru değil").
  ///
  /// Eski kural tam tersiydi: "kırpma istisna değil KURAL — kart raporun
  /// yerine geçmez, ona davet eder" ve uzun bir natal raporun yalnız ilk
  /// paragrafları karta giriyordu. Şimdi her sayfa cümle sınırından kesilir
  /// (cümle yoksa kelime sınırından), metin kaybolmaz; yalnız [azamiSayfa]
  /// aşılırsa son sayfa "…" ile biter.
  static List<String> sayfalar(String body,
      {required bool rozetli,
      TextStyle Function(double)? styleBuilder}) {
    var kalan = body.trim();
    final sonuc = <String>[];
    while (kalan.isNotEmpty) {
      final yukseklik =
          sonuc.isEmpty ? ilkYukseklik(rozetli: rozetli) : devamYukseklik;
      bool sigar(String s) => ShareCard.fitsAt(s, punto,
          maxWidth: _textWidth, maxHeight: yukseklik,
          styleBuilder: styleBuilder);
      if (sigar(kalan)) {
        sonuc.add(kalan);
        break;
      }
      if (sonuc.length == azamiSayfa - 1) {
        // Tavan: kalan metin sığmıyor. "…" AÇIKÇA eklenir — cümle
        // sınırından kesen `clampToSentence` işaret koymuyor ve okuyan
        // kartın eksik olduğunu bilmezdi.
        final kesim = kesimNoktasi(kalan, _sigan(kalan, sigar, ekBosluk: 2));
        sonuc.add('${kalan.substring(0, kesim).trimRight()} …');
        break;
      }
      final kesim = kesimNoktasi(kalan, _sigan(kalan, sigar));
      sonuc.add(kalan.substring(0, kesim).trim());
      kalan = kalan.substring(kesim).trim();
    }
    return sonuc;
  }

  /// [sigar] doğru kalan en uzun önek uzunluğu (ikili arama; kesim noktası
  /// ayrıca cümle sınırına çekilir). [ekBosluk]: "…" için pay.
  static int _sigan(String metin, bool Function(String) sigar,
      {int ekBosluk = 0}) {
    var alt = 1;
    var ust = metin.length;
    while (alt < ust) {
      final orta = (alt + ust + 1) ~/ 2;
      if (sigar(metin.substring(0, kesimNoktasi(metin, orta)))) {
        alt = orta;
      } else {
        ust = orta - 1;
      }
    }
    return (alt - ekBosluk).clamp(1, metin.length);
  }

  /// [azami] karakterden önceki son cümle sonu; yoksa son boşluk; o da
  /// yoksa [azami]. Önek döner — "…" EKLEMEZ (sayfa bölmede metin
  /// kaybolmasın diye; `clampToSentence` kesip "…" koyar).
  static int kesimNoktasi(String metin, int azami) {
    if (azami >= metin.length) return metin.length;
    final kesit = metin.substring(0, azami);
    var son = -1;
    for (final isaret in ['. ', '! ', '? ', '.\n', '\n\n']) {
      final i = kesit.lastIndexOf(isaret);
      if (i > son) son = i;
    }
    if (son > azami ~/ 3) return son + 1;
    final bosluk = kesit.lastIndexOf(' ');
    return bosluk > 0 ? bosluk : azami;
  }

  @override
  Widget build(BuildContext context) {
    final ilk = sayfaNo == 1;
    final rozetler = ilk ? badges.take(3).toList() : const <(String, String)>[];
    final metin = body;
    final sayfaEki = sayfaSayisi > 1 ? '  ·  $sayfaNo/$sayfaSayisi' : '';

    if (!ilk) {
      return SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: _kKartZemini,
          child: Padding(
            padding: _kTuvalDolgu,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$dateLabel$sayfaEki',
                    style: RythoText.mono(34, color: RythoColors.parchmentDim)),
                const SizedBox(height: 32),
                Text(title,
                    style: RythoText.display(_kDevamBaslik,
                        color: RythoColors.goldBright)),
                const SizedBox(height: 40),
                Expanded(
                  child: Text(metin, style: ShareCard.bodyStyle(punto)),
                ),
                const _MarkaSatiri(),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: _kKartZemini,
        child: Padding(
          padding: _kTuvalDolgu,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$dateLabel$sayfaEki',
                  style: RythoText.mono(34, color: RythoColors.parchmentDim)),
              const SizedBox(height: 48),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                if (glyph != null) ...[
                  // Çağıranlar ✦ / burç glifi / 🌞 geçiriyor: glif fontu
                  // ilk ikisini taşır, taşımadığını (emoji) Skia sistem
                  // fontundan tamamlar — ailesiz stilden farkı, glifin
                  // emojiye DÜŞMEMESİ.
                  Text(glyph!,
                      style: RythoText.glyph(96, color: RythoColors.goldBright)),
                  const SizedBox(width: 28),
                ],
                Expanded(
                  child: Text(trBuyuk(title),
                      style: RythoText.display(66)),
                ),
              ]),
              if (rozetler.isNotEmpty) ...[
                const SizedBox(height: 52),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (etiket, deger) in rozetler)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(trBuyuk(etiket),
                                style: RythoText.label(26,
                                    color: RythoColors.parchmentDim)),
                            const SizedBox(height: 12),
                            Text(deger,
                                style: RythoText.body(38,
                                    w: FontWeight.w700,
                                    color: RythoColors.goldBright)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 44),
                Container(height: 1, color: RythoColors.parchmentDim.withValues(alpha: 0.25)),
              ],
              const SizedBox(height: 48),
              Expanded(
                child: Text(metin, style: ShareCard.bodyStyle(punto)),
              ),
              const _MarkaSatiri(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartı görüntüye çevirip paylaşım sayfasını açar.
///
/// Kart ekranda gösterilmiyor; ekran dışında çizilip PNG'ye alınıyor.
/// Kullanıcıyı önce bir önizleme ekranına götürmek fazladan adım olurdu —
/// paylaşım sayfası zaten önizleme gösteriyor.
Future<bool> shareReadingCard(
  BuildContext context, {
  required String signName,
  required String signGlyph,
  required String reading,
  required String dateLabel,
  String? moonEmoji,
  String? moonName,
}) =>
    shareRenderedCard(
      context,
      ShareCard(
        signName: signName,
        signGlyph: signGlyph,
        reading: reading,
        dateLabel: dateLabel,
        moonEmoji: moonEmoji,
        moonName: moonName,
      ),
      const Size(ShareCard.width, ShareCard.height),
    );

/// Rapor/yıl haritası kartını paylaşır. [body] markdown'dan arındırılmış
/// düz metin olmalı (`markdownToPlain`).
Future<bool> shareReportCard(
  BuildContext context, {
  required String title,
  required String body,
  required String dateLabel,
  List<(String, String)> badges = const [],
  String? glyph,
}) {
  final sayfalar = ReportShareCard.sayfalar(body, rozetli: badges.isNotEmpty);
  return shareRenderedCards(
    context,
    [
      for (var i = 0; i < sayfalar.length; i++)
        ReportShareCard(
          title: title,
          body: sayfalar[i],
          dateLabel: dateLabel,
          badges: badges,
          glyph: glyph,
          sayfaNo: i + 1,
          sayfaSayisi: sayfalar.length,
        ),
    ],
    const Size(ReportShareCard.width, ReportShareCard.height),
  );
}

/// Çarkın paylaşım kartı (Harita İnceleme): aynı 9:16 tuval, çark 900 px.
///
/// NEDEN ayrı bir kart: chart_inspector 700×740'lık özel bir kare kuruyordu —
/// öteki iki kartla ne oranı ne zemini ne marka satırını paylaşıyordu;
/// Instagram hikâyesi o kareyi yan boşluklarla ortalıyor, çark ekranın
/// yarısında kalıyordu. Üç kart artık aynı tuvali, aynı zemini
/// (`_kKartZemini`) ve aynı marka satırını (`_MarkaSatiri`) kullanır.
///
/// **Aynı gizlilik kuralı:** çarkta doğum tarihi/saati/yeri YOK, yalnız
/// hesaplanmış konumlar. Halka lejantı hangi halkanın kime ait olduğunu
/// söyler (natal / transit / partner); kişi adı çağıranın verdiği başlıkta.
class ChartShareCard extends StatelessWidget {
  const ChartShareCard({
    super.key,
    required this.data,
    required this.title,
    this.filter = WheelAspectFilter.all,
    this.maxOrb = 8.0,
    this.showMinors = false,
  });

  final ChartData data;
  final String title;

  /// Çark ayarları Harita İnceleme'den olduğu gibi geçer: kullanıcı ekranda
  /// hangi açı süzgecini görüyorsa kartta da onu görür.
  final WheelAspectFilter filter;
  final double maxOrb;
  final bool showMinors;

  static const double width = ShareCard.width;
  static const double height = ShareCard.height;

  /// Çark çapı — tuvalin %83'ü. Daha büyüğü kenar dolgusunu yer; daha
  /// küçüğü telefonda (1080 → ~390 dp) glifleri Harita İnceleme'deki gömülü
  /// çarkın altına düşürür.
  static const double wheelSize = 900;

  /// Yatay dolgu çarktan türer (90 px): ShareCard'ın 96'sı çarkı 888'e
  /// sığdıramazdı.
  static const double _yatayDolgu = (width - wheelSize) / 2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: _kKartZemini,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              _yatayDolgu, _kTuvalUstPay, _yatayDolgu, _kTuvalAltPay),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trBuyuk(title), style: RythoText.display(66)),
              const SizedBox(height: 48),
              Center(
                child: ChartWheel(
                  data: data,
                  size: wheelSize,
                  interactive: false,
                  // Süpürme YOK: renderCard tek kare yakalar, progress≈0'da
                  // boş kare çıkardı (ChartWheel.animate gerekçesi).
                  animate: false,
                  filter: filter,
                  maxOrb: maxOrb,
                  showMinors: showMinors,
                ),
              ),
              const SizedBox(height: 40),
              // Halka lejantı — chart_inspector'daki rozetlerin kart ölçeği;
              // renk çarkla AYNI kuraldan (`ringGlyphColor`) ki lejant
              // çizilen halkayla aynı rengi söylesin.
              Wrap(spacing: 40, runSpacing: 16, children: [
                _HalkaRozeti(
                    renk: ringGlyphColor(data, 0),
                    metin: l10n.chartLegendInner(data.rings.first.label)),
                if (data.isBiWheel)
                  _HalkaRozeti(
                      renk: ringGlyphColor(data, 1),
                      metin: l10n.chartLegendOuter(data.rings[1].label)),
              ]),
              const SizedBox(height: 28),
              // Konum tablosu (sahip, 2026-10-16: "paylaşınca verilerin
              // çoğu siliniyor"): kart yalnız çarkı taşıyordu, ekrandaki
              // tablo — gezegen, burç, derece, ev, R — kartta yoktu ve
              // altta ~450 px boş kalıyordu. Ölçek `FittedBox.scaleDown`:
              // ikili çarkta (26 satır) da TAŞMAZ, küçülür.
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: wheelSize,
                      child: _KonumTablosu(data: data),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _MarkaSatiri(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartın konum tablosu — `ChartPositionsTable`ın 1080 px tuval ölçeği.
/// Tek halkada iki sütun (sıra korunarak bölünür), ikili çarkta halka başına
/// bir sütun. Açılar (AS/MC) tabloda yok — ekrandaki tabloyla aynı kural.
class _KonumTablosu extends StatelessWidget {
  const _KonumTablosu({required this.data});

  final ChartData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget satir(ChartPoint p, int halka) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(
              width: 44,
              child: kPlanetTextGlyphs.containsKey(p.name)
                  ? Text(kPlanetTextGlyphs[p.name]!,
                      style: RythoText.glyph(_kTabloGlif,
                          color: ringGlyphColor(data, halka)))
                  : CustomPaint(
                      size: const Size(28, 28),
                      painter: MiniGlyphPainter(
                          p.name, ringGlyphColor(data, halka))),
            ),
            Expanded(
              flex: 2,
              child: Text(p.localName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RythoText.body(_kTabloAd)),
            ),
            // Değer KESİLMEZ, gerekirse küçülür: "Yengeç 23°58' · 9 · R"
            // ölçümün kendisi; adı kısaltmak kabul, ölçümü kesmek değil.
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '${signDisplayName(l10n, p.signIndex)} '
                  '${formatDegree(p.degreeInSign)}'
                  '${p.houseNo != null ? ' · ${p.houseNo}' : ''}'
                  '${p.retrograde ? ' · R' : ''}',
                  style: RythoText.mono(_kTabloOlcum, color: RythoColors.lilac),
                ),
              ),
            ),
          ]),
        );

    final sutunlar = <List<Widget>>[];
    if (data.isBiWheel) {
      for (var r = 0; r < data.rings.length; r++) {
        sutunlar.add([
          for (final p in data.rings[r].points.where((p) => !p.isAngle))
            satir(p, r),
        ]);
      }
    } else {
      final noktalar =
          data.rings.first.points.where((p) => !p.isAngle).toList();
      final yari = (noktalar.length + 1) ~/ 2;
      sutunlar
        ..add([for (final p in noktalar.take(yari)) satir(p, 0)])
        ..add([for (final p in noktalar.skip(yari)) satir(p, 0)]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sutunlar.length; i++) ...[
          if (i > 0) const SizedBox(width: 40),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sutunlar[i],
            ),
          ),
        ],
      ],
    );
  }
}

class _HalkaRozeti extends StatelessWidget {
  const _HalkaRozeti({required this.renk, required this.metin});

  final Color renk;
  final String metin;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(shape: BoxShape.circle, color: renk),
      ),
      const SizedBox(width: 16),
      Text(metin, style: RythoText.body(32, color: RythoColors.parchmentDim)),
    ]);
  }
}

/// Çark kartını paylaşır (Harita İnceleme'nin `_paylas`ının varisi).
Future<bool> shareChartCard(
  BuildContext context, {
  required ChartData data,
  required String title,
  WheelAspectFilter filter = WheelAspectFilter.all,
  double maxOrb = 8.0,
  bool showMinors = false,
}) =>
    shareRenderedCard(
      context,
      ChartShareCard(
        data: data,
        title: title,
        filter: filter,
        maxOrb: maxOrb,
        showMinors: showMinors,
      ),
      const Size(ChartShareCard.width, ChartShareCard.height),
    );

/// Herhangi bir widget'ı PNG'ye çevirip paylaşım sayfasını açar.
///
/// HI-turu'nda dışa açıldı (eski `_paylas`): Harita İnceleme çark
/// görüntüsünü de bu boru hattıyla paylaşıyor.
Future<bool> shareRenderedCard(
        BuildContext context, Widget kart, Size boyut) =>
    shareRenderedCards(context, [kart], boyut);

/// Birden çok kartı tek paylaşımda gönderir (sayfalanmış rapor).
Future<bool> shareRenderedCards(
    BuildContext context, List<Widget> kartlar, Size boyut) async {
  final l10n = AppLocalizations.of(context);
  final mediaQuery = MediaQuery.of(context);
  final locale = Localizations.localeOf(context);

  try {
    final dizin = await getTemporaryDirectory();
    final damga = DateTime.now().millisecondsSinceEpoch;
    final dosyalar = <XFile>[];
    for (var i = 0; i < kartlar.length; i++) {
      final bayt = await renderCard(kartlar[i],
          size: boyut, mediaQuery: mediaQuery, locale: locale);
      final dosya = File('${dizin.path}/rytho-$damga-${i + 1}.png');
      await dosya.writeAsBytes(bayt);
      dosyalar.add(XFile(dosya.path));
    }

    // Görselin yanındaki metin kullanıcının dilinde tanıtım cümlesi: logo
    // yazısı (`kMarkaYazi`) tek başına paylaşım sayfasında bağlamsız bir
    // "RYTHO" bırakıyordu; alan kişinin uygulamayı ne yaptığını okusun.
    await SharePlus.instance.share(
      ShareParams(files: dosyalar, text: l10n.shareText),
    );
    return true;
  } catch (e) {
    debugPrint('Paylaşım kartı oluşturulamadı: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.shareFailed)));
    }
    return false;
  }
}

/// Widget'ı ekrana bağlamadan PNG'ye çevirir.
///
/// `RepaintBoundary`'yi ekranda gösterip yakalamak, kartı kullanıcıya bir an
/// için göstermek demek olurdu. Bunun yerine ayrı bir render ağacı kurulup
/// tek karede çiziliyor.
///
/// [size] kartın mantıksal boyutu; her kart kendi oranını getirebilsin diye
/// parametre (eskiden `ShareCard` ölçüleri gömülüydü).
Future<Uint8List> renderCard(
  Widget card, {
  required Size size,
  required MediaQueryData mediaQuery,
  required Locale locale,
}) async {
  final repaintBoundary = RenderRepaintBoundary();
  final view = WidgetsBinding.instance.platformDispatcher.views.first;

  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(
      alignment: Alignment.center,
      child: repaintBoundary,
    ),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      devicePixelRatio: 1.0,
    ),
  );

  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();

  final buildOwner = BuildOwner(focusManager: FocusManager());
  final element = RenderObjectToWidgetAdapter<RenderBox>(
    container: repaintBoundary,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: mediaQuery,
        child: Localizations(
          locale: locale,
          delegates: AppLocalizations.localizationsDelegates.toList(),
          child: card,
        ),
      ),
    ),
  ).attachToRenderTree(buildOwner);

  buildOwner
    ..buildScope(element)
    ..finalizeTree();
  pipelineOwner
    ..flushLayout()
    ..flushCompositingBits()
    ..flushPaint();

  final image = await repaintBoundary.toImage(pixelRatio: 1.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('Kart PNG olarak alınamadı.');
  return data.buffer.asUint8List();
}

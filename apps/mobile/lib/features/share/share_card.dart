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
import '../../widgets/chart/chart_wheel.dart';
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
  });

  final String title;

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

  @override
  Widget build(BuildContext context) {
    final rozetler = badges.take(3).toList();
    // Metin alanı rozet sayısına göre daralır; sabit bir yükseklik
    // varsaymak rozetsiz kartta boşluk, üç rozetlide taşma üretirdi.
    final metinYuksekligi = 980.0 - (rozetler.isEmpty ? 0 : 190);
    final metin = _sigdir(body, metinYuksekligi);

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
                child: Text(metin,
                    style: ShareCard.bodyStyle(ShareCard.fittedFontSize(
                      metin,
                      maxWidth: _textWidth,
                      maxHeight: metinYuksekligi,
                      maxSize: 42,
                    ))),
              ),
              const _MarkaSatiri(),
            ],
          ),
        ),
      ),
    );
  }

  /// Rapor günlük yorumdan KAT KAT uzun; en küçük punto bile yetmez. Bu
  /// yüzden burada kırpma istisna değil KURAL — kart raporun yerine geçmez,
  /// ona davet eder. Kırpma yine cümle sınırından yapılır.
  static String _sigdir(String metin, double yukseklik) {
    final temiz = metin.trim();
    if (temiz.isEmpty) return temiz;

    bool sigar(String s) => ShareCard.fitsAt(s, 30,
        maxWidth: _textWidth, maxHeight: yukseklik);
    if (sigar(temiz)) return temiz;

    var alt = 0;
    var ust = temiz.length;
    while (alt < ust) {
      final orta = (alt + ust + 1) ~/ 2;
      if (sigar(ShareCard.clampToSentence(temiz, orta))) {
        alt = orta;
      } else {
        ust = orta - 1;
      }
    }
    return ShareCard.clampToSentence(temiz, alt);
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
}) =>
    shareRenderedCard(
      context,
      ReportShareCard(
        title: title,
        body: body,
        dateLabel: dateLabel,
        badges: badges,
        glyph: glyph,
      ),
      const Size(ReportShareCard.width, ReportShareCard.height),
    );

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
              const Spacer(),
              const _MarkaSatiri(),
            ],
          ),
        ),
      ),
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
    BuildContext context, Widget kart, Size boyut) async {
  final l10n = AppLocalizations.of(context);
  final mediaQuery = MediaQuery.of(context);
  final locale = Localizations.localeOf(context);

  try {
    final bayt = await renderCard(kart,
        size: boyut, mediaQuery: mediaQuery, locale: locale);

    final dizin = await getTemporaryDirectory();
    final dosya = File('${dizin.path}/rytho-${DateTime.now()
        .millisecondsSinceEpoch}.png');
    await dosya.writeAsBytes(bayt);

    // Görselin yanındaki metin kullanıcının dilinde tanıtım cümlesi: logo
    // yazısı (`kMarkaYazi`) tek başına paylaşım sayfasında bağlamsız bir
    // "RYTHO" bırakıyordu; alan kişinin uygulamayı ne yaptığını okusun.
    await SharePlus.instance.share(
      ShareParams(files: [XFile(dosya.path)], text: l10n.shareText),
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

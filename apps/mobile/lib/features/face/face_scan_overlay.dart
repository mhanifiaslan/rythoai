/// Kamera üstündeki kılavuz ve tarama katmanı.
///
/// İki ayrı iş yapar ve ikisi ayrı sınıf:
///
/// * [FaceGuidePainter] — çekimden ÖNCE. Yüz ovali kılavuzu; kadraja göre
///   renk değiştirir, hazır olduğunda kilitlenir.
/// * [FaceScanPainter] — çekimden SONRA. Tarama çizgisi, ardından tespit
///   edilen noktaların yüze oturması.
///
/// Animasyondaki noktalar **gerçek tespit sonucundan** gelir. Sahte nokta
/// oynatmak, uygulamanın kendi hesabı hakkında yalan söylemesi olurdu; oysa
/// ürünün ilkesi hesaplananı yorumlanandan ayırmak.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/rytho_theme.dart';
import 'face_geometry.dart';

/// Tarama paleti — **uygulamanın kendi paletinden** türetilir.
///
/// İlk denemede camgöbeği/turkuaz bir bilim kurgu paleti kullanılmıştı;
/// teknik olarak hoş ama ekran uygulamaya ait görünmüyordu. Rytho'nun kimliği
/// mor-lila-magenta; sinematik his renkten değil **hareketten ve karanlıktan**
/// geliyor, o yüzden palet markaya çekildi.
class ScanPalette {
  const ScanPalette._();

  /// Arayan/beklerken — sönük, nötr.
  static const searching = RythoColors.parchmentDim;

  /// Hazır — kilitlenme rengi (olumlu).
  static const locked = RythoColors.celadon;

  /// Uyarı — kullanıcının düzeltmesi gereken bir şey var.
  static const warn = RythoColors.gold;

  /// Tarama çizgisi ve noktalar.
  static const beam = RythoColors.lilac;
  static const node = RythoColors.goldBright;

  /// Kılavuz dışının karartması. Zemin renginin koyu ucundan geliyor ki
  /// kamera görüntüsü uygulamanın içine gömülü hissettirsin.
  static const vignette = Color(0xCC0B0710);
}

// ---------------------------------------------------------------------------
// Çekim öncesi: kılavuz
// ---------------------------------------------------------------------------

class FaceGuidePainter extends CustomPainter {
  FaceGuidePainter({
    required this.quality,
    required this.pulse,
    required this.lockProgress,
  });

  final FrameQuality quality;

  /// 0..1 arası sürekli nabız; "arıyor" hâlinde kılavuzu canlı tutar.
  final double pulse;

  /// 0..1; yüz hazır konuma geldiğinde çerçevenin dolma oranı.
  final double lockProgress;

  /// Köşe yumuşatması — sabit piksel DEĞİL, orana bağlı: sabit değer küçük
  /// ekranda "dörtgen", büyükte "kutu" gösterirdi.
  static const double _kYaricapOrani = 0.11;

  /// Köşe ayracının kenar boyunca uzunluğu (çerçeve genişliğinin oranı).
  static const double _kAyracOrani = 0.17;

  @override
  void paint(Canvas canvas, Size size) {
    final kutu = guideFrame(size);
    final yaricap = kutu.width * _kYaricapOrani;
    final rrect = RRect.fromRectAndRadius(kutu, Radius.circular(yaricap));
    final renk = _renk(quality);

    // Dışarısı karartılır: kullanıcının gözü otomatik olarak çerçevenin
    // içine gider. Kılavuzu çizip ortamı aydınlık bırakmak, kadrajı
    // hissettirmiyor.
    final disari = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(disari, Paint()..color = ScanPalette.vignette);

    final yol = Path()..addRRect(rrect);

    // İnce sürekli hat: çerçevenin gövdesi. Sönük — asıl vurgu köşelerde.
    canvas.drawPath(
      yol,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = renk.withValues(alpha: 0.32),
    );

    // Köşe ayraçları: kadrajın teknik/optik hissi buradan geliyor. Eskiden
    // çerçevenin DIŞINDA duran ayrı "pençeler"di; hatla hizasızdılar.
    // Artık hattın kendisinden çıkıyor ve yuvarlatılmış köşeyi izliyorlar.
    _koseAyraclari(canvas, kutu, yaricap, renk);

    // Nabız: hat boyunca dolaşan kısa bir ışık. Eskisi 42 parçalı dönen
    // kesikli ovaldi; dörtgende yay matematiği anlamsız ve kesikli hat
    // sabit görünüyordu.
    if (lockProgress <= 0) _tarayanIsik(canvas, yol, renk);

    // Kilit: hazır olunca hat çerçeveyi baştan sona doldurur.
    if (lockProgress > 0) _kilitHatti(canvas, yol);
  }

  /// Kılavuz çerçevesi — kadrajın ortasında, dikey olarak biraz yukarıda.
  ///
  /// Geometri `face_geometry.dart`'tan geliyor: çizilen çerçeve ile kalite
  /// kontrolünün beklediği hedef **aynı işlevden** çıkmalı. Ayrı hesaplar
  /// kullanınca kılavuz bir yeri gösterip kontrol başka yere bakmıştı.
  /// (Kaynak işlevin adı tarihsel; döndürdüğü değer baştan beri bir `Rect`.)
  static Rect guideFrame(Size size) => guideOvalOnScreen(size);

  static Color _renk(FrameQuality q) => switch (q) {
        FrameQuality.ready => ScanPalette.locked,
        FrameQuality.noFace => ScanPalette.searching,
        _ => ScanPalette.warn,
      };

  /// Dört köşede, yuvarlatılmış dönüşü izleyen L ayraçlar.
  void _koseAyraclari(Canvas canvas, Rect kutu, double r, Color renk) {
    final uzunluk = kutu.width * _kAyracOrani;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = renk;

    // sx/sy: köşeden çerçevenin içine doğru yön (±1).
    void ayrac(Offset kose, double sx, double sy) {
      // Köşe yayının merkezi, köşeden içeri r kadar kaçık.
      final merkez = kose.translate(r * sx, r * sy);
      final yay = Rect.fromCircle(center: merkez, radius: r);
      canvas.drawPath(
        Path()
          // Yatay kenar: yayın bittiği yerden dışarı doğru.
          ..moveTo(merkez.dx + uzunluk * sx, kose.dy)
          ..lineTo(merkez.dx, kose.dy)
          // Yuvarlatılmış dönüş.
          ..arcTo(yay, -math.pi / 2 * sy, -math.pi / 2 * sx * sy, false)
          // Dikey kenar.
          ..lineTo(kose.dx, merkez.dy + uzunluk * sy),
        paint,
      );
    }

    ayrac(kutu.topLeft, 1, 1);
    ayrac(kutu.topRight, -1, 1);
    ayrac(kutu.bottomLeft, 1, -1);
    ayrac(kutu.bottomRight, -1, -1);
  }

  /// Hat boyunca dolaşan kısa parlak parça — "arıyor" hâlinin canlılığı.
  void _tarayanIsik(Canvas canvas, Path yol, Color renk) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = renk.withValues(alpha: 0.9);

    for (final olcum in yol.computeMetrics()) {
      final toplam = olcum.length;
      final boy = toplam * 0.13;
      final bas = (pulse % 1.0) * toplam;
      if (bas + boy <= toplam) {
        canvas.drawPath(olcum.extractPath(bas, bas + boy), paint);
      } else {
        // Başa sarma: iki parça hâlinde çizilir.
        canvas.drawPath(olcum.extractPath(bas, toplam), paint);
        canvas.drawPath(olcum.extractPath(0, bas + boy - toplam), paint);
      }
    }
  }

  /// Kilit hattı: çerçeve tepeden başlayıp baştan sona dolar.
  void _kilitHatti(Canvas canvas, Path yol) {
    final oran = lockProgress.clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = ScanPalette.locked;

    for (final olcum in yol.computeMetrics()) {
      canvas.drawPath(olcum.extractPath(0, olcum.length * oran), paint);
    }
  }

  @override
  bool shouldRepaint(FaceGuidePainter old) =>
      old.quality != quality ||
      old.pulse != pulse ||
      old.lockProgress != lockProgress;
}

// ---------------------------------------------------------------------------
// Çekim sonrası: tarama ve nokta yerleşmesi
// ---------------------------------------------------------------------------

/// Tarama animasyonunun aşamaları ve zamanlaması.
///
/// Toplam süre tespit süresinden **bağımsız** tutuldu. Tespit ~100 ms sürüyor;
/// animasyonu ona bağlamak göz kırpması kadar kısa, anlaşılmaz bir geçiş
/// verirdi. Buradaki süreler okunabilirlik için seçildi, oyalama için değil —
/// tespit zaten bitmiş durumda ve noktalar gerçek.
class ScanTiming {
  const ScanTiming._();

  /// Tarama çizgisinin yüzü baştan aşağı geçmesi.
  static const beam = Duration(milliseconds: 1100);

  /// Noktaların tek tek oturması.
  static const nodes = Duration(milliseconds: 1300);

  /// Bağ çizgilerinin çekilmesi ve kapanış.
  static const mesh = Duration(milliseconds: 900);

  static Duration get total => beam + nodes + mesh;
}

/// Yumuşatma eğrileri.
///
/// İlk sürümde her şey doğrusaldı ve ucuz duruyordu: gerçek hiçbir şey sabit
/// hızla başlayıp sabit hızla durmaz. Tarama çizgisi hızlanıp yavaşlıyor,
/// noktalar yerine otururken hafifçe aşıyor.
const _kBeamCurve = Curves.easeInOutCubic;
const _kNodeCurve = Curves.easeOutBack;

/// Tespit noktalarını GÖRÜNTÜ uzayından EKRAN uzayına taşır.
///
/// İki dönüşüm var ve ikisi de gerekli:
///
/// 1. **`BoxFit.cover`.** Önizleme ekrana kırpılarak oturuyor; noktalar aynı
///    ölçek ve aynı ortalama ile taşınmazsa yüzün yanında belirirler.
/// 2. **Aynalama.** Ön kamera önizlemesi ayna gibi gösteriliyor (CameraX
///    bunu varsayılan yapıyor) ama ML Kit koordinatları aynalanMAMIŞ sensör
///    uzayında geliyor. Cihaz testinde noktalar "yüzün solunda" çıktı;
///    sebebi buydu. Bu Android'e özgü: iOS'ta ML Kit zaten aynalı tamponu
///    görüyor ve bayrak orada `false` gelmeli (bkz. face_detection.dart,
///    `taramaNoktalariAynalanir`).
///
/// Aynalamanın kadrajlama kontrolünü etkilemediğini not etmek gerekiyor:
/// merkeze uzaklık aynalamada değişmiyor, yalnızca işareti dönüyor. Bu yüzden
/// kılavuz doğru çalışırken noktalar yanlış yerdeydi — kusur sessizdi.
List<Offset> mapScanPoints({
  required List<Offset> points,
  required Size imageSize,
  required Size screenSize,
  required bool mirrored,
}) {
  if (imageSize.width < 1 || imageSize.height < 1) return const [];
  final olcek = math.max(screenSize.width / imageSize.width,
      screenSize.height / imageSize.height);
  final dx = (screenSize.width - imageSize.width * olcek) / 2;
  final dy = (screenSize.height - imageSize.height * olcek) / 2;
  return [
    for (final p in points)
      Offset(
        mirrored
            ? screenSize.width - (p.dx * olcek + dx)
            : p.dx * olcek + dx,
        p.dy * olcek + dy,
      ),
  ];
}

class FaceScanPainter extends CustomPainter {
  FaceScanPainter({
    required this.lines,
    required this.progress,
    required this.imageSize,
    required this.mirrored,
  });

  /// Tespit edilen hatlar — GÖRÜNTÜ uzayında, **kontur kontur ayrılmış.**
  ///
  /// Düz liste değil: ağ çizgileri yalnızca aynı kontur içinde anlamlı.
  final List<List<Offset>> lines;

  /// 0..1 arası toplam ilerleme.
  final double progress;

  /// Noktaların ait olduğu görüntünün boyutu; ekrana ölçeklemek için.
  final Size imageSize;

  /// Önizleme aynalanmış mı (ön kamera).
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty || imageSize.width < 1 || imageSize.height < 1) return;

    final ekranHatlari = [
      for (final hat in lines)
        mapScanPoints(
          points: hat,
          imageSize: imageSize,
          screenSize: size,
          mirrored: mirrored,
        ),
    ];
    final ekranNoktalari = [for (final h in ekranHatlari) ...h];
    if (ekranNoktalari.isEmpty) return;
    final t = progress.clamp(0.0, 1.0);

    final beamPay = ScanTiming.beam.inMilliseconds / ScanTiming.total.inMilliseconds;
    final nodePay = ScanTiming.nodes.inMilliseconds / ScanTiming.total.inMilliseconds;

    final beamT = (t / beamPay).clamp(0.0, 1.0);
    final nodeT = ((t - beamPay) / nodePay).clamp(0.0, 1.0);
    final meshT = ((t - beamPay - nodePay) / (1 - beamPay - nodePay))
        .clamp(0.0, 1.0);

    // Çizim sırası derinlik kuruyor: en arkada karartma, sonra ağ, sonra
    // noktalar, en önde ışık. Tersi olsaydı ışık noktaların altında kalır ve
    // katmanlar yassı görünürdü.
    _karartma(canvas, size, ekranNoktalari, t);
    if (meshT > 0) _mesh(canvas, ekranHatlari, meshT);
    if (nodeT > 0) _noktalar(canvas, ekranNoktalari, nodeT);
    if (beamT > 0 && beamT < 1) _beam(canvas, size, _kBeamCurve.transform(beamT));
  }

  /// Yüz dışını hafifçe karartır ve tarama ilerledikçe açar.
  ///
  /// Kadrajın "incelendiği" hissi buradan geliyor; ışık bandı tek başına
  /// ekranın üstünden geçen bir çizgi gibi duruyordu.
  void _karartma(Canvas canvas, Size size, List<Offset> noktalar, double t) {
    if (noktalar.isEmpty) return;
    final merkez = noktalar.fold(Offset.zero, (a, b) => a + b) /
        noktalar.length.toDouble();
    var yaricap = 0.0;
    for (final p in noktalar) {
      yaricap = math.max(yaricap, (p - merkez).distance);
    }
    // Tarama biterken karartma çözülür: dikkat yüze çekilir, sonra bırakılır.
    final guc = (0.55 * (1 - Curves.easeIn.transform(t.clamp(0.0, 1.0)) * 0.55))
        .clamp(0.0, 1.0);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            ScanPalette.vignette.withValues(alpha: guc),
          ],
          stops: const [0.55, 1.0],
        ).createShader(
            Rect.fromCircle(center: merkez, radius: yaricap * 2.6)),
    );
  }

  /// Tarama çizgisi: yüzü yukarıdan aşağı geçen ışık bandı.
  ///
  /// Üç katman: geniş ve sönük bir hâle, ince ve parlak bir çizgi, çizginin
  /// hemen arkasında kalan bir iz. Tek düz çizgi "çizilmiş" duruyordu; ışığın
  /// hacmi olduğunu gösteren şey hâle ve iz.
  void _beam(Canvas canvas, Size size, double t) {
    final y = size.height * t;
    const yukseklik = 160.0;
    final bant = Rect.fromLTWH(0, y - yukseklik * 0.75, size.width, yukseklik);

    canvas.drawRect(
      bant,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ScanPalette.beam.withValues(alpha: 0.0),
            ScanPalette.beam.withValues(alpha: 0.30),
            ScanPalette.beam.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.78, 1.0],
        ).createShader(bant)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // Parlak çekirdek — kenarlara doğru sönüyor ki çizgi kadrajı kesmesin.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..strokeWidth = 1.6
        ..shader = LinearGradient(
          colors: [
            ScanPalette.beam.withValues(alpha: 0.0),
            ScanPalette.node.withValues(alpha: 0.95),
            ScanPalette.beam.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2)),
    );
  }

  /// Noktalar sırayla oturur; her biri küçük bir halkayla "kenetlenir".
  ///
  /// Nokta yerine otururken hafifçe büyüyüp geri çekiliyor ([_kNodeCurve]) ve
  /// kenetlenme halkası dışarı doğru açılıp sönüyor. Hepsinin aynı anda
  /// belirmesi ya da sabit boyutta durması, ölçümün gerçekten o an yapıldığı
  /// hissini vermiyordu.
  void _noktalar(Canvas canvas, List<Offset> noktalar, double t) {
    final gorunen = (noktalar.length * t).ceil();
    final dolgu = Paint()..color = ScanPalette.node;
    final hale = Paint()
      ..color = ScanPalette.node.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final halka = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var i = 0; i < gorunen && i < noktalar.length; i++) {
      final p = noktalar[i];
      // Son oturan noktanın kenetlenme halkası açık, öncekiler sönmüş.
      final yas = (gorunen - i) / math.max(noktalar.length * 0.18, 1);
      final canli = (1 - yas).clamp(0.0, 1.0);
      final yerlesme =
          _kNodeCurve.transform((1 - canli).clamp(0.0, 1.0)).clamp(0.0, 1.4);

      canvas.drawCircle(p, 2.6 * yerlesme, hale);
      canvas.drawCircle(p, 1.7 * yerlesme, dolgu);
      if (canli > 0) {
        canvas.drawCircle(
            p,
            3 + 11 * (1 - canli),
            halka..color = ScanPalette.beam.withValues(alpha: 0.65 * canli));
      }
    }
  }

  /// Kontur hatlarını çizer — "ağ" hissi.
  ///
  /// Her hat KENDİ içinde bağlanıyor. Önceki sürümde bütün noktalar tek bir
  /// listeye diziliyor ve aralarındaki bağ, iki nokta arasındaki UZAKLIĞA
  /// bakılarak koparılıyordu. Bu bir sezgiydi: eşik kimi yüzde tutuyor,
  /// kimi yüzde kaşın sonundan gözün başına çizgi çekiyordu. Kullanıcı bunu
  /// "sınırları rastgele olmuş gibi" diye tarif etti ve haklıydı.
  ///
  /// Hangi noktanın hangi hatta ait olduğu tespit anında zaten belli
  /// (bkz. `scanNodes`); tahmin etmeye gerek yok.
  void _mesh(Canvas canvas, List<List<Offset>> hatlar, double t) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ScanPalette.beam.withValues(alpha: 0.32 * t);

    final yol = Path();
    for (final hat in hatlar) {
      if (hat.length < 2) continue;
      // Her hat kendi payınca çiziliyor ki hepsi aynı anda tamamlansın;
      // sırayla çizmek uzun ovali bitirip kalanları son ana sıkıştırıyordu.
      final adet = math.max(2, (hat.length * t).ceil());
      yol.moveTo(hat.first.dx, hat.first.dy);
      for (var i = 1; i < adet && i < hat.length; i++) {
        yol.lineTo(hat[i].dx, hat[i].dy);
      }
    }
    canvas.drawPath(yol, paint);
  }

  @override
  bool shouldRepaint(FaceScanPainter old) =>
      old.progress != progress ||
      old.lines != lines ||
      old.mirrored != mirrored;
}

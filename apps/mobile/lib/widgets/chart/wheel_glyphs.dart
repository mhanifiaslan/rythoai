/// Vektör glifler (HI-turu HA4) — font tuzağına karşı.
///
/// ♈-♓ (U+2648-2653) Unicode'da `Emoji_Presentation=Yes` taşır: birçok
/// Android cihazda burç halkası RENKLİ EMOJİ karikatürlerine dönüşür ve
/// VS15 (︎) Skia'da güvenilir değildir. ⚷ (Kiron) ve ⚸ (Lilith) ise
/// birçok fontta hiç yoktur. Bu küme bu yüzden VEKTÖR Path olarak çizilir
/// (star_burst ressamı emsali) — cihazdan bağımsız, markaya uygun,
/// degrade/kalınlık kontrolü ressamda. (⚹ altmışlık D6'da metin glifine
/// geçti — çarkta hiç çizilmiyordu, tek tüketicisi tablo hücresiydi.)
///
/// ⚠️ Gezegen glifleri "güvenli metin kümesi" DEĞİLDİ — bu dosyanın eski
/// gerekçesi yanlıştı ve mağaza karesiyle ölçüldü (shot-2-chart.png: ♀
/// mor-pembe, ♂ turkuaz emoji). Manrope'ta ♀♂ yok; Skia emoji fontuna
/// düşüyordu. Metin glifleri artık `theme/rytho_glyphs.dart`'ta ve her
/// `RythoText` stili `RythoGlyphs` fontunu yedek zincirinde taşıyor.
///
/// Tüm path'ler 1×1 birim karede, ÇİZGİ (stroke) olarak tasarlandı;
/// [signGlyphPath] hedef boyuta ölçekleyip merkeze taşır.
library;

import 'dart:typed_data';
import 'dart:ui';

import '../../theme/rytho_glyphs.dart' show kPlanetTextGlyphs;

// Tablolar tek kaynaktan; buradan dışa açılması eski çağıranlar için.
export '../../theme/rytho_glyphs.dart'
    show kPlanetTextGlyphs, kAspectTextGlyphs;

Path _unit(void Function(Path p) cizim) {
  final p = Path();
  cizim(p);
  return p;
}

/// 12 burç glifi — birim karede sadeleştirilmiş ama tanınır formlar.
final List<Path> _signPaths = [
  // ♈ Koç: iki dışa kıvrık boynuz + gövde.
  _unit((p) => p
    ..moveTo(0.50, 0.92)
    ..lineTo(0.50, 0.42)
    ..cubicTo(0.50, 0.14, 0.16, 0.10, 0.14, 0.38)
    ..moveTo(0.50, 0.42)
    ..cubicTo(0.50, 0.14, 0.84, 0.10, 0.86, 0.38)),
  // ♉ Boğa: daire gövde + üstte açık hilal boynuz.
  _unit((p) => p
    ..addOval(Rect.fromCircle(center: const Offset(0.50, 0.62),
        radius: 0.26))
    ..moveTo(0.22, 0.10)
    ..cubicTo(0.28, 0.34, 0.72, 0.34, 0.78, 0.10)),
  // ♊ İkizler: iki dikey + üst/alt yay.
  _unit((p) => p
    ..moveTo(0.34, 0.22)
    ..lineTo(0.34, 0.78)
    ..moveTo(0.66, 0.22)
    ..lineTo(0.66, 0.78)
    ..moveTo(0.16, 0.14)
    ..cubicTo(0.38, 0.26, 0.62, 0.26, 0.84, 0.14)
    ..moveTo(0.16, 0.86)
    ..cubicTo(0.38, 0.74, 0.62, 0.74, 0.84, 0.86)),
  // ♋ Yengeç: kilitli 6-9.
  _unit((p) => p
    ..addOval(Rect.fromCircle(center: const Offset(0.31, 0.36),
        radius: 0.13))
    ..moveTo(0.18, 0.36)
    ..cubicTo(0.18, 0.16, 0.58, 0.10, 0.82, 0.24)
    ..addOval(Rect.fromCircle(center: const Offset(0.69, 0.64),
        radius: 0.13))
    ..moveTo(0.82, 0.64)
    ..cubicTo(0.82, 0.84, 0.42, 0.90, 0.18, 0.76)),
  // ♌ Aslan: küçük halka + yele kıvrımı.
  _unit((p) => p
    ..addOval(Rect.fromCircle(center: const Offset(0.30, 0.66),
        radius: 0.13))
    ..moveTo(0.40, 0.58)
    ..cubicTo(0.34, 0.24, 0.72, 0.14, 0.72, 0.44)
    ..cubicTo(0.72, 0.62, 0.60, 0.72, 0.62, 0.84)
    ..cubicTo(0.64, 0.92, 0.76, 0.92, 0.80, 0.84)),
  // ♍ Başak: üç bacaklı m + içe dönen kuyruk.
  _unit((p) => p
    ..moveTo(0.14, 0.30)
    ..cubicTo(0.20, 0.20, 0.28, 0.24, 0.28, 0.34)
    ..lineTo(0.28, 0.72)
    ..moveTo(0.28, 0.34)
    ..cubicTo(0.34, 0.22, 0.44, 0.24, 0.44, 0.36)
    ..lineTo(0.44, 0.72)
    ..moveTo(0.44, 0.36)
    ..cubicTo(0.50, 0.24, 0.62, 0.24, 0.62, 0.38)
    ..lineTo(0.62, 0.66)
    ..cubicTo(0.62, 0.84, 0.44, 0.90, 0.36, 0.84)
    ..moveTo(0.62, 0.56)
    ..cubicTo(0.78, 0.56, 0.84, 0.68, 0.76, 0.92)),
  // ♎ Terazi: tepe yayı + iki çizgi.
  _unit((p) => p
    ..moveTo(0.14, 0.58)
    ..lineTo(0.36, 0.58)
    ..cubicTo(0.32, 0.30, 0.68, 0.30, 0.64, 0.58)
    ..lineTo(0.86, 0.58)
    ..moveTo(0.14, 0.78)
    ..lineTo(0.86, 0.78)),
  // ♏ Akrep: m + ok kuyruk.
  _unit((p) => p
    ..moveTo(0.12, 0.30)
    ..cubicTo(0.18, 0.20, 0.26, 0.24, 0.26, 0.34)
    ..lineTo(0.26, 0.72)
    ..moveTo(0.26, 0.34)
    ..cubicTo(0.32, 0.22, 0.42, 0.24, 0.42, 0.36)
    ..lineTo(0.42, 0.72)
    ..moveTo(0.42, 0.36)
    ..cubicTo(0.48, 0.24, 0.58, 0.24, 0.58, 0.38)
    ..lineTo(0.58, 0.62)
    ..cubicTo(0.58, 0.76, 0.68, 0.80, 0.84, 0.72)
    ..moveTo(0.84, 0.72)
    ..lineTo(0.74, 0.62)
    ..moveTo(0.84, 0.72)
    ..lineTo(0.78, 0.86)),
  // ♐ Yay: çapraz ok + kiriş.
  _unit((p) => p
    ..moveTo(0.20, 0.80)
    ..lineTo(0.78, 0.22)
    ..moveTo(0.50, 0.22)
    ..lineTo(0.78, 0.22)
    ..lineTo(0.78, 0.50)
    ..moveTo(0.30, 0.46)
    ..lineTo(0.54, 0.70)),
  // ♑ Oğlak: V + halka kuyruk.
  _unit((p) => p
    ..moveTo(0.14, 0.24)
    ..lineTo(0.34, 0.60)
    ..lineTo(0.50, 0.24)
    ..lineTo(0.50, 0.66)
    ..cubicTo(0.50, 0.88, 0.78, 0.92, 0.80, 0.70)
    ..cubicTo(0.82, 0.52, 0.60, 0.50, 0.58, 0.66)),
  // ♒ Kova: iki zikzak dalga.
  _unit((p) => p
    ..moveTo(0.12, 0.40)
    ..lineTo(0.28, 0.28)
    ..lineTo(0.44, 0.40)
    ..lineTo(0.60, 0.28)
    ..lineTo(0.76, 0.40)
    ..lineTo(0.88, 0.30)
    ..moveTo(0.12, 0.68)
    ..lineTo(0.28, 0.56)
    ..lineTo(0.44, 0.68)
    ..lineTo(0.60, 0.56)
    ..lineTo(0.76, 0.68)
    ..lineTo(0.88, 0.58)),
  // ♓ Balık: iki dış yay + orta çubuk.
  _unit((p) => p
    ..moveTo(0.30, 0.12)
    ..cubicTo(0.06, 0.38, 0.06, 0.62, 0.30, 0.88)
    ..moveTo(0.70, 0.12)
    ..cubicTo(0.94, 0.38, 0.94, 0.62, 0.70, 0.88)
    ..moveTo(0.22, 0.50)
    ..lineTo(0.78, 0.50)),
];

/// Eşölçekli büyütme + taşıma matrisi (sütun-öncelikli 4x4).
Float64List _scaleTranslate(double s, double tx, double ty) =>
    Float64List.fromList([
      s, 0, 0, 0,
      0, s, 0, 0,
      0, 0, 1, 0,
      tx, ty, 0, 1,
    ]);

/// Burç glifi: [size]×[size] kutuya ölçekli, [center] merkezli path.
Path signGlyphPath(int signIndex, Offset center, double size) =>
    _signPaths[signIndex % 12].transform(_scaleTranslate(
        size, center.dx - size / 2, center.dy - size / 2));

/// Özel glifler: Kiron ⚷ / Lilith ⚸ — çarkın 13 px bandında çizgi
/// kalınlığı ressamda kontrol edilsin diye vektör. Altmışlık ⚹ artık
/// burada DEĞİL: açı glifi çarkta basılmaz, tablo hücresi metin glifini
/// basar (`kAspectTextGlyphs`, gerekçesi `rytho_glyphs.dart`'ta).
Path specialGlyphPath(String name, Offset center, double size) {
  final Path birim;
  switch (name) {
    case 'Chiron':
      // Anahtar formu: üstte K çatalı, altta halka.
      birim = _unit((p) => p
        ..addOval(Rect.fromCircle(center: const Offset(0.50, 0.74),
            radius: 0.18))
        ..moveTo(0.50, 0.56)
        ..lineTo(0.50, 0.08)
        ..moveTo(0.50, 0.34)
        ..lineTo(0.76, 0.10)
        ..moveTo(0.50, 0.34)
        ..lineTo(0.76, 0.52));
    case 'Mean_Lilith':
    case 'Lilith':
      // Hilal + altında haç.
      birim = _unit((p) => p
        ..moveTo(0.62, 0.10)
        ..cubicTo(0.28, 0.16, 0.28, 0.52, 0.62, 0.58)
        ..cubicTo(0.44, 0.48, 0.44, 0.20, 0.62, 0.10)
        ..moveTo(0.50, 0.58)
        ..lineTo(0.50, 0.92)
        ..moveTo(0.34, 0.76)
        ..lineTo(0.66, 0.76));
    default:
      birim = Path();
  }
  return birim.transform(_scaleTranslate(
      size, center.dx - size / 2, center.dy - size / 2));
}

/// Ada göre: metin glifi varsa null döner (metinle çizilecek), yoksa
/// vektör path (Kiron/Lilith).
Path? planetGlyphPathOrNull(String name, Offset center, double size) {
  if (kPlanetTextGlyphs.containsKey(name)) return null;
  return specialGlyphPath(name, center, size);
}


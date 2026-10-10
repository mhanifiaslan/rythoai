// Kontrast bekçisi (D2, sahip kararı K5).
//
// Ölçüldü: `GoldButton`'un beyaz metni `primaryGradient`'ın magenta ucunda
// 3,36:1 — AA eşiği (normal metin) 4,5. Çözüm görsel kimliği değiştirmeden
// YALNIZ metin taşıyan yüzeyler için koyulaştırılmış `ctaGradient`: her
// durak yalnız L ekseninde, ≥ 4,6 tutana kadar indirildi (ton/doygunluk
// sabit). Bu test o sayıları sabitler; `primaryGradient`'ın AA altı kaldığını
// da BİLEREK sabitler — biri onu "düzeltirse" ctaGradient'ın var olma
// sebebi kaybolur ve ayrım kayar.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/theme/rytho_theme.dart';

/// WCAG 2.x göreli parlaklık.
double _luminance(Color c) {
  double lin(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double kontrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const beyaz = Colors.white;

  test('ctaGradient her durakta beyaz metinle ≥ 4,5:1 (AA)', () {
    for (final durak in RythoColors.ctaGradient.colors) {
      expect(kontrast(durak, beyaz), greaterThanOrEqualTo(4.5),
          reason: '#${durak.toARGB32().toRadixString(16)} beyazla '
              '${kontrast(durak, beyaz).toStringAsFixed(2)}:1');
    }
  });

  test('ctaGradient tonu korunur: ilk durak primaryGradient ile aynı', () {
    // Koyulaştırma violet'e dokunmadı (5,85:1 zaten geçiyordu); kimlik
    // sınırı: degrade yine violet'ten başlar.
    expect(RythoColors.ctaGradient.colors.first, RythoColors.violet);
    expect(RythoColors.ctaGradient.colors.length,
        RythoColors.primaryGradient.colors.length);
  });

  test('primaryGradient AA ALTINDA kalır — ctaGradient bu yüzden var', () {
    // Dekoratif degrade metin taşımaz; onu koyulaştırmak kimliği
    // değiştirirdi (K5). Bu iddia bilerek sabit: magenta ucu beyazla < 4,5.
    expect(kontrast(RythoColors.magenta, beyaz), lessThan(4.5));
  });

  test('metin renkleri ink zemin üstünde ≥ 4,5:1', () {
    for (final (ad, renk) in [
      ('parchment', RythoColors.parchment),
      ('parchmentDim', RythoColors.parchmentDim),
      ('lilac', RythoColors.lilac),
      ('madder', RythoColors.madder),
      ('caution', RythoColors.caution),
      ('gold', RythoColors.gold),
      ('celadon', RythoColors.celadon),
    ]) {
      for (final zemin in [RythoColors.ink, RythoColors.inkLight, RythoColors.inkLighter]) {
        expect(kontrast(renk, zemin), greaterThanOrEqualTo(4.5),
            reason: '$ad / #${zemin.toARGB32().toRadixString(16)}: '
                '${kontrast(renk, zemin).toStringAsFixed(2)}:1');
      }
    }
  });

  test('onGradient beyazdır — degrade üstü metnin tek rengi', () {
    expect(RythoColors.onGradient, Colors.white);
  });
}

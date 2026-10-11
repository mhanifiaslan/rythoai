// `formatDegree` bekçisi (D6) — 29°60' kusuru ve burç sınırı kararı.
//
// Eski kopya `floor(derece) + round(dakika)` idi: 12,9999 → "12°60'"
// (olmayan dakika). Tek tanım chart_data.dart'ta; konum tablosu ve
// ressamın zoom≥2 etiketi onu çağırır.
//
// Sınır kararı (gerekçesi chart_data.dart'ta): 29,9999 → "29°59'", "30°00'"
// DEĞİL — burç adı sunucunun `sign` kodundan gelir ve formatlayıcı onunla
// çelişemez ("Balık 30°00'" yok, o 0° Koç).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/widgets/chart/chart_data.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('formatDegree', () {
    test('olağan değer: derece + iki haneli dakika', () {
      expect(formatDegree(12.5), "12°30'");
      expect(formatDegree(0.0), "0°00'");
      expect(formatDegree(5.25), "5°15'");
    });

    test('dakika 60a yuvarlanınca dereceye TAŞAR (eski kusur: 12°60\')',
        () {
      expect(formatDegree(12.9999), "13°00'");
      expect(formatDegree(0.9999), "1°00'");
    });

    test('burç sınırı: 29,9999 → 29°59\' — burç adıyla çelişmez', () {
      expect(formatDegree(29.9999), "29°59'");
      expect(formatDegree(29.99), "29°59'");
      // Sınırın hemen altı normal yuvarlanır.
      expect(formatDegree(29.49), "29°29'");
    });

    test('aralık dışı girdi burcun içine kelepçelenir', () {
      expect(formatDegree(30.0), "29°59'");
      expect(formatDegree(-0.5), "0°00'");
    });
  });

  group('kaynak: tek tanım', () {
    test('konum tablosu ve ressam kendi dakika hesabını tutmuyor', () {
      for (final yol in const [
        'lib/widgets/chart/chart_positions.dart',
        'lib/widgets/chart/wheel_painter.dart',
      ]) {
        final k = _yorumsuz(yol);
        expect(k, contains('formatDegree('), reason: '$yol: tek tanım yok');
        expect(k, isNot(contains('* 60).round()')),
            reason: '$yol: eski dakika kopyası geri gelmiş (29°60\' yolu)');
      }
    });
  });
}

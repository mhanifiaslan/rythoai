// Mağazadaki bedel satırı SUNUCUDAN gelir; bilinmiyorsa ÇİZİLMEZ (D7).
//
// Önceki hâl (`bedelSatiri`, bulgu B1): ARB şablonu "1 · 2 · 3 · 5" sayılarını
// taşıyor, işlev onları KONUMA göre sunucu sayılarıyla değiştiriyordu — bir tur
// boyunca İ Ching ile ikili dinamiğin bedellerini yer değiştirmiş gösterdi ve
// ön koşul tutmayınca şablonun KENDİ sayılarını (bayat olabilen) çiziyordu.
// `tokenCostsNote` artık yer tutuculu (`{chat} {iching} {dyad} {deep}`):
// cümlede rakam yok, rakam yoksa cümle de yok.
//
// Sunucu tarafı: `backend/tests/test_honesty.py::TestJetonIddialari` kabloyu
// (`bedelNotu(l10n, …costs)`) ve yer tutucuların etiket yanında durduğunu
// çiviliyor; derin raporların tek bedelde anlaşması da orada ölçülüyor.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/paywall/token_store_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';

AppLocalizations _l10n(String dil) => lookupAppLocalizations(Locale(dil));

/// Şablonun kendi sayılarına benzemesin diye alışılmadık bedeller.
const _kSunucu = {
  'chat': 7,
  'iching': 9,
  'dyad': 11,
  'natal': 13,
  'bazi': 13,
  'synastry': 13,
  'face': 13,
};

void main() {
  group('bedelNotu — saf işlev', () {
    test('tam harita: cümle sunucu sayılarıyla, iki dilde', () {
      for (final dil in ['tr', 'en']) {
        final not = bedelNotu(_l10n(dil), _kSunucu);
        expect(not, isNotNull, reason: dil);
        expect(not, _l10n(dil).tokenCostsNote(7, 9, 11, 13), reason: dil);
        for (final sayi in ['7', '9', '11', '13']) {
          expect(not, contains(sayi), reason: '$dil: $sayi');
        }
        // Eski şablonun derleme sayıları ekrana SIZMAZ.
        expect(RegExp(r'\b[1235]\b').hasMatch(not!), isFalse, reason: dil);
      }
    });

    test('bedel OKUNAMADIYSA satır yok — bayat ya da uydurma sayı değil', () {
      expect(bedelNotu(_l10n('tr'), const {}), isNull);
    });

    test('tek tek anılan bir özellik haritada yoksa satır yok', () {
      final eksik = Map<String, int>.from(_kSunucu)..remove('iching');
      expect(bedelNotu(_l10n('tr'), eksik), isNull);
    });

    test('derin raporlar tek bedelde anlaşmıyorsa özet kurulamaz → satır yok',
        () {
      final ayrisik = Map<String, int>.from(_kSunucu)..['face'] = 4;
      expect(bedelNotu(_l10n('tr'), ayrisik), isNull);
    });

    test('yalnız üç anılan özellik, derin rapor hiç yok → özet kurulamaz', () {
      expect(bedelNotu(_l10n('tr'), const {'chat': 1, 'iching': 2, 'dyad': 3}),
          isNull);
    });
  });
}

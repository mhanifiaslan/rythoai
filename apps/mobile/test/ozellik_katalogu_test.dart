// Özellik kataloğu SUNUCUYLA BİREBİR — iki sözlükle de.
//
// Katalogdaki sunucu adları elle yazılı; sunucu tarafı ayrı dağıtılıyor.
// Ayrışma sessiz olur: `BedelRozeti` yanlış anahtarla `costs`a bakar, null
// görür ve HİÇ çizilmez (ölçülmeyen söylenmez kuralı burada yanlış
// anahtarı da gizler); `X-Paywall-Feature` eşleşmez, paywall hangi
// özellikten gelindiğini bilmez. Bu bekçi iki sunucu dosyasını DİSKTEN
// okur: `backend/core/wallet.py` `TOKEN_COSTS` ve `require_plus("…")`
// çağrıları (`core/entitlements.py` + `api/`).
//
// Yorum satırları eşleşmeden ÖNCE atılıyor (CLAUDE.md §5): wallet.py'nin
// yorumları başka anahtarlardan söz ediyor.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/paywall/ozellik_katalogu.dart';
import 'package:rytho/l10n/app_localizations_en.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('#'))
    .join('\n');

/// `TOKEN_COSTS` sözlüğünün anahtarları — blok `{ … }` arasından.
Set<String> _bedelAnahtarlari() {
  final kaynak = _yorumsuz('../../backend/core/wallet.py');
  final basla = kaynak.indexOf('TOKEN_COSTS: dict[str, int] = {');
  expect(basla, greaterThanOrEqualTo(0),
      reason: 'wallet.py TOKEN_COSTS tanımı bulunamadı — ad değiştiyse '
          'bekçi de taşınmalı');
  final bitis = kaynak.indexOf('}', basla);
  final blok = kaynak.substring(basla, bitis);
  return RegExp(r'"([a-z_]+)":\s*\d+')
      .allMatches(blok)
      .map((m) => m.group(1)!)
      .toSet();
}

/// `require_plus("…")` adları — kapı tanımı ve tüm API dosyaları.
Set<String> _kapiAdlari() {
  final dosyalar = <String>[
    '../../backend/core/entitlements.py',
    ...Directory('../../backend/api')
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.py')),
  ];
  final desen = RegExp(r'require_plus\("([a-z_]+)"\)');
  return {
    for (final yol in dosyalar)
      for (final m in desen.allMatches(_yorumsuz(yol))) m.group(1)!,
  };
}

void main() {
  final tr = AppLocalizationsTr();
  final en = AppLocalizationsEn();

  group('sunucu eşitliği (diskten)', () {
    test('TOKEN_COSTS anahtarları == katalog sunucuAdi kümesi', () {
      final sunucu = _bedelAnahtarlari();
      expect(sunucu, isNotEmpty, reason: 'ayrıştırıcı boş döndü');
      final katalog = {
        for (final o in PlusOzellik.values)
          if (o.sunucuAdi != null) o.sunucuAdi!,
      };
      expect(katalog, sunucu,
          reason: 'sunucuda olup katalogda olmayan bedel: '
              '${sunucu.difference(katalog)}; katalogda olup sunucuda '
              'olmayan: ${katalog.difference(sunucu)}');
    });

    test('require_plus adları == katalog kapiAdi kümesi', () {
      final sunucu = _kapiAdlari();
      expect(sunucu, isNotEmpty, reason: 'ayrıştırıcı boş döndü');
      final katalog = {
        for (final o in PlusOzellik.values)
          if (o.kapiAdi != null) o.kapiAdi!,
      };
      expect(katalog, sunucu,
          reason: 'sunucuda olup katalogda olmayan kapı: '
              '${sunucu.difference(katalog)}; katalogda olup sunucuda '
              'olmayan: ${katalog.difference(sunucu)}');
    });

    test('iki sözlük gerçekten ayrışıyor — tek alana indirgenemez', () {
      // Bekçinin varlık gerekçesi: yüz okuma bedelde `face`, kapıda
      // `firasa`. Bu test düşerse sunucu iki adı eşitlemiş demektir ve
      // katalog sadeleşebilir.
      expect(PlusOzellik.face.sunucuAdi, 'face');
      expect(PlusOzellik.face.kapiAdi, 'firasa');
      expect(PlusOzellik.natal.sunucuAdi, 'natal');
      expect(PlusOzellik.natal.kapiAdi, 'natal_report');
    });
  });

  group('bul', () {
    test('iki sözlükten de bulur', () {
      expect(PlusOzellik.bul('firasa'), PlusOzellik.face);
      expect(PlusOzellik.bul('face'), PlusOzellik.face);
      expect(PlusOzellik.bul('personal_daily'), PlusOzellik.daily);
      expect(PlusOzellik.bul('chat'), PlusOzellik.chat);
    });

    test('tanımadığı ad ve null → null', () {
      expect(PlusOzellik.bul('yok'), isNull);
      expect(PlusOzellik.bul(null), isNull);
    });
  });

  group('emoji', () {
    test('Doğum Kapısı VS16 ile — tek biçim', () {
      // VS16'sız `☯` Android'de tek renk metin glifi; yanındaki renkli
      // emojilerle hizası tutmuyordu.
      expect(PlusOzellik.birthHexagram.emoji, '☯️');
      for (final o in PlusOzellik.values) {
        expect(o.emoji, isNot('☯'), reason: '$o VS16\'sız');
        expect(o.emoji, isNotEmpty);
      }
    });
  });

  group('metinler', () {
    test('her üyenin başlığı ve gövdesi iki dilde de dolu', () {
      for (final o in PlusOzellik.values) {
        for (final l10n in [tr, en]) {
          expect(o.baslik(l10n).trim(), isNotEmpty, reason: '$o başlık');
          expect(o.kilitGovdesi(l10n).trim(), isNotEmpty,
              reason: '$o gövde');
        }
      }
    });
  });
}

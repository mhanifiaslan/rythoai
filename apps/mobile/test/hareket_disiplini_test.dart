// Hareket disiplini CIRCIRI (D8): çıplak süreler yalnız AŞAĞI iner,
// `.animate(` zinciri olan her dosya hareket azaltma kapısından geçer,
// eski `blok(`/`gecikme()` stagger kopyaları sıfır.
//
// Tavanlar ÖLÇÜLEN sayılardır (2026-10-12, yorumsuz kaynak), hedef değil:
// bir dosyada sayı yükselirse test kırmızı olur, düşerse tavan buraya
// indirilir. "Sıfıra inmeli" hedefi doğru ama sıfırı bugünden iddia etmek
// bekçiyi doğduğu gün kırmızı yapardı. Allowlist GEREKÇELİ: ağ zaman aşımı,
// yoklama aralığı, geri sayım gibi süreler hareket DEĞİL — token'a
// girmezler, dosya başına tavanla tutulurlar.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Iterable<File> _dartDosyalari() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.replaceAll(r'\', '/').contains('/l10n/'));

String _yol(File f) => f.path.replaceAll(r'\', '/');

/// `Duration(milliseconds: N)`, `Duration(seconds: N)`, `N.ms`, `N.seconds`.
final _ciplakSure =
    RegExp(r'Duration\((?:milliseconds|seconds): \d|\b\d+\.(?:ms|seconds)\b');

/// Dosya başına tavan — ölçülen değer. Gerekçe sütunu: sürenin sınıfı.
const _sureTavani = <String, int>{
  'lib/core/api.dart': 2, // ağ zaman aşımı
  'lib/core/app_config.dart': 2, // uzak yapılandırma tazeleme
  'lib/core/device_session.dart': 1, // kilit yenileme
  'lib/core/notifications.dart': 1, // jeton eşitleme
  'lib/core/providers.dart': 1, // profil akışı zaman aşımı
  'lib/core/subscription.dart': 13, // yoklama merdiveni + kaynak mağaza sınırı (U47)
  'lib/features/auth/forgot_password_screen.dart': 1, // geri sayım
  'lib/features/face/face_capture_screen.dart': 4, // kamera sahnesi
  'lib/features/face/face_reading_flow.dart': 1, // okuma zaman aşımı
  'lib/features/face/face_scan_overlay.dart': 3, // tarama çizgisi
  'lib/features/face/face_segmentation.dart': 3, // model zaman aşımı
  'lib/features/friends/friend_detail_screen.dart': 1, // dürtme bekleme
  'lib/features/onboarding/constellation_progress.dart': 2, // yıldız dizisi
  'lib/features/onboarding/onboarding_wizard.dart': 2, // kayıt zaman aşımı
  'lib/features/paywall/paywall_screen.dart': 3, // sabırsızlık + kutlama
  'lib/features/profile/phone_verify_screen.dart': 1, // geri sayım
  'lib/main.dart': 3, // açılış perdesi
  'lib/theme/rytho_tokens.dart': 15, // token tanımlarının KENDİSİ
  'lib/widgets/big_three_reveal.dart': 3, // perde koreografisi
  'lib/widgets/city_search_field.dart': 1, // debounce
  'lib/widgets/coin_toss.dart': 2, // kinematik periyot
  'lib/widgets/common.dart': 2, // sarsıntı + iskelet
  'lib/widgets/cosmic_scaffold.dart': 1, // yıldız alanı dönüşü
  'lib/widgets/fade_through_route.dart': 1, // rota süresi (token'a eş)
  'lib/widgets/frame_sequence.dart': 1, // kare süresi
  'lib/widgets/kota_bekleme.dart': 1, // geri sayım
  'lib/widgets/star_burst.dart': 1, // parçacık ömrü
};

void main() {
  group('çıplak süre cırcırı', () {
    test('dosya başına tavan aşılmaz; listede olmayan dosyada SIFIR', () {
      final asanlar = <String>[];
      for (final f in _dartDosyalari()) {
        final yol = _yol(f);
        final n = _ciplakSure.allMatches(_yorumsuz(yol)).length;
        final tavan = _sureTavani[yol] ?? 0;
        if (n > tavan) asanlar.add('$yol: $n > $tavan');
      }
      expect(asanlar, isEmpty,
          reason: 'yeni çıplak süre: RythoMotion token\'ı ya da '
              'gerekçeli tavan (hareket değilse)');
    });

    test('tavan tablosu bayat değil: her girdi hâlâ o sayıda', () {
      // Sayı düştüyse tavan da düşer — cırcır yalnız aşağı çalışır.
      final bayat = <String>[];
      for (final girdi in _sureTavani.entries) {
        final f = File(girdi.key);
        if (!f.existsSync()) {
          bayat.add('${girdi.key}: dosya yok');
          continue;
        }
        final n = _ciplakSure.allMatches(_yorumsuz(girdi.key)).length;
        if (n < girdi.value) bayat.add('${girdi.key}: $n < ${girdi.value}');
      }
      expect(bayat, isEmpty, reason: 'tavanı ölçülen değere indir');
    });

    test('toplam ölçülen tavanı aşmaz', () {
      var toplam = 0;
      for (final f in _dartDosyalari()) {
        toplam += _ciplakSure.allMatches(_yorumsuz(_yol(f))).length;
      }
      // 71 → 74 (2026-10-22): Mac'in iOS birleşmesi üç AĞ zaman aşımı
      // getirdi (U06 onay ×2, U47 kaynak mağaza) — hareket değil, dosya
      // tavanlarında gerekçeleriyle. 74 → 72 (aynı gün): U06'nın onay
      // sayfası ve durum sağlayıcısı kalktı (sahip kararı: onay yalnız
      // kurulumda), iki zaman aşımı onlarla gitti.
      expect(toplam, lessThanOrEqualTo(72));
    });
  });

  group('hareket kapıları', () {
    test('`.animate(` olan her dosya `reduceMotion(` içerir', () {
      final kapisiz = <String>[];
      for (final f in _dartDosyalari()) {
        final k = _yorumsuz(_yol(f));
        if (k.contains('.animate(') && !k.contains('reduceMotion(')) {
          kapisiz.add(_yol(f));
        }
      }
      expect(kapisiz, isEmpty,
          reason: 'hareket azaltma açıkken bu dosyanın animasyonu durmaz');
    });

    test('eski stagger kopyaları (`blok(`, `gecikme()`) sıfır', () {
      final kopya = RegExp(r'\bblok\(|\bgecikme\(\)');
      for (final f in _dartDosyalari()) {
        expect(kopya.hasMatch(_yorumsuz(_yol(f))), isFalse,
            reason: '${_yol(f)}: RythoReveal tek yol');
      }
    });
  });
}

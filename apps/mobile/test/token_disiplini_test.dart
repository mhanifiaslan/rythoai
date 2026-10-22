// Token disiplini CIRCIRI (D8): yazı boyu, köşe, renk ve ham `TextStyle`
// literalleri yalnız AŞAĞI iner.
//
// Tavanlar ÖLÇÜLEN sayılar (2026-10-12, yorumsuz kaynak). Tema ve palet
// dosyaları tanım yeridir, orada literal olması doğaldır; `share_card`
// 1080 px tuvalin kendi sabitlerini taşır. Bunlar allowlist'te dosya
// başına tavanla tutulur; listede olmayan dosyada yeni literal kırmızı.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Iterable<String> _dartDosyalari() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f.path.replaceAll(r'\', '/'))
    .where((p) => p.endsWith('.dart') && !p.contains('/l10n/'));

/// `BorderRadius.circular(<literal>)` — `RythoRadius.*` değil.
final _koseLiteral = RegExp(r'BorderRadius\.circular\(\s*\d');
const _koseTavani = <String, int>{
  'lib/core/safety.dart': 1,
  'lib/features/atlas/atlas_detail_screens.dart': 2, // pill (999)
  'lib/features/face/face_capture_screen.dart': 1,
  'lib/features/friends/reaction_sheet.dart': 2,
  'lib/features/onboarding/onboarding_wizard.dart': 1,
  'lib/features/oracle/bazi_tab.dart': 1,
  'lib/features/profile/profile_screen.dart': 1,
  'lib/theme/rytho_theme.dart': 4, // tema tanımı
  'lib/widgets/atlas_widgets.dart': 1, // GoldButton → RythoRadius.button
  'lib/widgets/nebula_widgets.dart': 1,
  'lib/widgets/phone_number_field.dart': 2,
};

/// `Color(0x…)` — `RythoColors.*` değil.
final _renkLiteral = RegExp(r'Color\(0x');
const _renkTavani = <String, int>{
  'lib/theme/rytho_theme.dart': 36, // paletin kendisi
  'lib/widgets/chart/chart_palette.dart': 16, // çark paleti (tanım yeri)
  'lib/features/share/share_card.dart': 3, // tuval sabitleri
  'lib/widgets/coin_toss.dart': 3,
  'lib/widgets/cosmic_scaffold.dart': 1,
  'lib/widgets/glass.dart': 1, // dock zemini (D3 notu)
  'lib/features/face/face_scan_overlay.dart': 1,
};

/// Ham `TextStyle(` kurucu — `RythoText.*`/`RythoType.*` değil.
final _hamStil = RegExp(r'(?<![A-Za-z_.])TextStyle\(');
const _stilTavani = <String, int>{
  'lib/core/safety.dart': 1,
  'lib/features/auth/device_conflict_screen.dart': 1,
  'lib/features/auth/force_update_screen.dart': 1,
  'lib/features/friends/reaction_sheet.dart': 1,
  'lib/features/onboarding/onboarding_wizard.dart': 2,
  'lib/features/profile/diary_screen.dart': 1,
  'lib/features/sky/sign_story_screen.dart': 1,
  'lib/theme/rytho_theme.dart': 2, // rol tanımları
  'lib/widgets/big_three_reveal.dart': 1,
  'lib/widgets/city_search_field.dart': 1,
  'lib/widgets/common.dart': 1,
  'lib/widgets/cosmic_scaffold.dart': 1,
  'lib/widgets/nebula_widgets.dart': 1,
  'lib/widgets/phone_number_field.dart': 1,
};

/// `RythoText.<kurucu>(<sayı>` — boyut literali; rol (`RythoType.*`) değil.
final _yaziLiteral =
    RegExp(r'RythoText\.(?:body|display|label|mono|glyph|emoji)\(\s*\d');

void _cirCir(String ad, RegExp rx, Map<String, int> tavanlar) {
  test('$ad: dosya başına tavan; listede olmayan dosyada sıfır', () {
    final asanlar = <String>[];
    for (final yol in _dartDosyalari()) {
      final n = rx.allMatches(_yorumsuz(yol)).length;
      final tavan = tavanlar[yol] ?? 0;
      if (n > tavan) asanlar.add('$yol: $n > $tavan');
    }
    expect(asanlar, isEmpty, reason: '$ad literali geri geldi');
  });

  test('$ad: tavan tablosu bayat değil', () {
    final bayat = <String>[];
    for (final g in tavanlar.entries) {
      if (!File(g.key).existsSync()) {
        bayat.add('${g.key}: dosya yok');
        continue;
      }
      final n = rx.allMatches(_yorumsuz(g.key)).length;
      if (n < g.value) bayat.add('${g.key}: $n < ${g.value}');
    }
    expect(bayat, isEmpty, reason: 'tavanı ölçülen değere indir');
  });
}

void main() {
  _cirCir('köşe', _koseLiteral, _koseTavani);
  _cirCir('renk', _renkLiteral, _renkTavani);
  _cirCir('ham TextStyle', _hamStil, _stilTavani);

  test('yazı boyu literali toplamı ölçülen tavanı aşmaz (358)', () {
    // Dosya başına değil toplam: 58 dosyaya yayılmış ve `RythoType`
    // rollerine göç dosya dosya değil satır satır ilerliyor.
    var toplam = 0;
    for (final yol in _dartDosyalari()) {
      toplam += _yaziLiteral.allMatches(_yorumsuz(yol)).length;
    }
    expect(toplam, lessThanOrEqualTo(358));
    // Bayatlık: düştüyse tavan iner.
    expect(toplam, greaterThanOrEqualTo(340),
        reason: 'tavan 358 iken ölçüm $toplam — tavanı indir');
  });
}

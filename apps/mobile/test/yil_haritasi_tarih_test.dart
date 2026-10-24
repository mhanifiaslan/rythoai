// Yıl Haritası tarihleri — dönüş anının YEREL günü, kullanıcının dilinde.
//
// Ölçülen kusur (mağaza çekimi 2026-10-24, demo hesap): aynı ekranda yıl
// çubuğu "2026-01-09", dönüş kartı "2026-01-10 00:03" yazıyordu. Sebep:
// kart `return_at_local` dizgesini kesiyordu, çubuk ise
// `DateTime.tryParse` sonucunu `toIso8601String()` ile kesiyordu — Dart
// ofsetli ISO'yu UTC'ye çevirir, çubuk UTC gününü basıyordu.
//
// Hangisi doğru, hesapla ölçüldü (backend `predict_service.solar_return`,
// demo doğumu 1997-01-09 22:00 İstanbul, hedef yıl 2026):
//   return_at_utc        2026-01-09T21:03:35+00:00
//   return_at_local      2026-01-10T00:03:35+03:00   ← haritanın kurulduğu yer
//   next_return_at_local 2027-01-10T05:46:04+03:00
// Yıl, haritanın kurulduğu yerin saatiyle 10 Ocak'ta açılıyor. UTC günü
// (9 Ocak) o yerde hiç yaşanmadı.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/core/wallet.dart' show WalletStatus, walletProvider;
import 'package:rytho/features/atlas/solar_return_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_en.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/okuma_kabi.dart' show OkumaKabi;

Widget _sar(Locale dil) => ProviderScope(
      // Bedel kapısı cüzdanı izliyor: `unknown` → kapı sorulmaz (emsal
      // anlam_once_bes_ekran_test).
      overrides: [
        walletProvider.overrideWith((_) async => WalletStatus.unknown),
        raporKapisiProvider.overrideWithValue(PlusHali.abone),
        solarReturnProvider.overrideWith((ref) async => {
              'report': 'Yılın okuması.',
              'solar_return': {
                'return_at_utc': '2026-01-09T21:03:35+00:00',
                'return_at_local': '2026-01-10T00:03:35+03:00',
                'next_return_at_local': '2027-01-10T05:46:04+03:00',
                'sr_moon_local': 'Terazi',
                'sr_moon_sign': 'Lib',
                'disclosure_texts': <String>[],
              },
            }),
      ],
      child: MaterialApp(
        locale: dil,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildRythoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const SolarReturnScreen(),
      ),
    );

/// `pumpAndSettle` yok: yıldız alanı sürekli animatör.
Future<void> _yerles(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 1500));
}

/// `ListView` tembel: dönüş kartı sayfanın dibinde.
void _uzunYuzey(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  for (final (dil, l10n, acilis, sonraki) in [
    (const Locale('tr'), AppLocalizationsTr() as AppLocalizations,
        '10 Ocak 2026', '10 Ocak 2027'),
    (const Locale('en'), AppLocalizationsEn() as AppLocalizations,
        '10 January 2026', '10 January 2027'),
  ]) {
    testWidgets('${dil.languageCode}: çubuk ve kart AYNI yerel günü, '
        'kullanıcının dilinde yazar', (tester) async {
      _uzunYuzey(tester);
      await tester.pumpWidget(_sar(dil));
      await _yerles(tester);

      // Çubuğun sol ucu + dönüş kartı: ikisi de açılış günü.
      expect(find.text(acilis), findsNWidgets(2),
          reason: 'çubuk ile kart farklı gün söylüyor');
      expect(find.text(sonraki), findsOneWidget, reason: 'çubuğun sağ ucu');
      expect(find.text('00:03'), findsOneWidget, reason: 'dönüş saati');
      expect(find.text(l10n.solarReturnNext('$sonraki 05:46')),
          findsOneWidget);
      // UTC günü (9 Ocak) o yerde hiç yaşanmadı; ham ISO da ekrana çıkmaz.
      expect(find.textContaining('2026-01-09'), findsNothing,
          reason: 'UTC günü basılıyor');
      expect(find.textContaining(RegExp(r'\d{4}-\d{2}-\d{2}')), findsNothing,
          reason: 'ham ISO tarih ekranda');

      // Paylaşım kartının tarihi de aynı gün, aynı dil.
      await tester.tap(find.text(l10n.readingFullToggle));
      await _yerles(tester);
      final kap = tester.widget<OkumaKabi>(find.byType(OkumaKabi));
      expect(kap.paylasim?.dateLabel, acilis);
    });
  }
}

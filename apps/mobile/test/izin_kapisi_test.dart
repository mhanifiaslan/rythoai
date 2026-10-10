// Bildirim izni kapısı ve "izin sistemde kapalı" bandı bekçileri.
//
// Band yalnız OS izni REDDEDİLMİŞKEN çıkar ve ayarlara giden düğme taşır;
// izin verilmişken hiçbir şey çizmez. Kapı: seçim null → hiçbir segment
// dolgulu değil (seçilmeyen beyan edilmez); dokunuş bool verir.
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/notifications.dart' show osBildirimDurumuProvider;
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/izin_kapisi.dart';

final _tr = AppLocalizationsTr();

Widget _sar(Widget child, {AuthorizationStatus? durum}) => ProviderScope(
      overrides: [
        if (durum != null)
          osBildirimDurumuProvider.overrideWith((ref) async => durum),
      ],
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildRythoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(body: Column(children: [child])),
      ),
    );

int _dolguluSegment(WidgetTester tester) => tester
    .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
    .where((c) => (c.decoration as BoxDecoration?)?.color != null)
    .length;

/// Sağlayıcının geleceği bir mikro görevde çözülür: tek kare yetmez.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  group('IzinKapaliBandi', () {
    testWidgets('OS izni reddedilmiş → band + ayarlar düğmesi', (tester) async {
      await tester.pumpWidget(
          _sar(const IzinKapaliBandi(), durum: AuthorizationStatus.denied));
      await _bekle(tester);

      expect(find.text(_tr.notifPermissionOffTitle), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, _tr.settings), findsOneWidget,
          reason: 'yol tarifi değil, ayarlara giden düğme');
    });

    testWidgets('OS izni verilmiş → hiçbir şey', (tester) async {
      await tester.pumpWidget(_sar(const IzinKapaliBandi(),
          durum: AuthorizationStatus.authorized));
      await _bekle(tester);

      expect(find.text(_tr.notifPermissionOffTitle), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('durum henüz bilinmiyor → hiçbir şey (bilinmeyen ret değil)',
        (tester) async {
      await tester.pumpWidget(_sar(const IzinKapaliBandi(),
          durum: AuthorizationStatus.notDetermined));
      await _bekle(tester);

      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('IzinKapisi', () {
    testWidgets('seçim null → hiçbir segment dolgulu değil', (tester) async {
      await tester.pumpWidget(_sar(IzinKapisi(secim: null, onSec: (_) {})));
      await tester.pump();

      expect(find.text(_tr.wizardNotifyAllow), findsOneWidget);
      expect(find.text(_tr.wizardLater), findsOneWidget);
      expect(_dolguluSegment(tester), 0);
    });

    testWidgets('"Sonra" → false, "Haber ver" → true; seçim dolgu alır',
        (tester) async {
      bool? secim;
      await tester
          .pumpWidget(_sar(IzinKapisi(secim: true, onSec: (v) => secim = v)));
      await tester.pump();

      expect(_dolguluSegment(tester), 1);
      await tester.tap(find.text(_tr.wizardLater));
      expect(secim, isFalse);
      await tester.tap(find.text(_tr.wizardNotifyAllow));
      expect(secim, isTrue);
    });
  });
}

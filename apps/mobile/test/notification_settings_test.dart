// Bildirim ayarları bekçileri (D5 §6).
//
// Ölçülen kusurlar (2026-10-10): OS izni reddedilmişken band yol tarifi
// veriyordu (düğme yok); sayfa başlığı ile plaka etiketi aynı sözcüktü
// (çift "Bildirimler"); sessiz saat seçicileri aynı `helpText`i taşıyordu
// (iki kadran, hangisi bitiş?); dakika sessizce atılıyordu (21:40 → 21:00,
// kullanıcı görmüyordu); Switch renkleri temaya rağmen elle verilmişti.
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/notifications.dart' show osBildirimDurumuProvider;
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/profile/notification_settings.dart';
import 'package:rytho/features/profile/profile_sections.dart'
    show NotificationSettingsScreen;
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/izin_kapisi.dart' show IzinKapaliBandi;

final _tr = AppLocalizationsTr();

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Widget _uygulama(Widget home) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    );

Future<void> _ekran(WidgetTester tester, Widget home,
    {AuthorizationStatus durum = AuthorizationStatus.authorized}) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileProvider.overrideWith(
          (ref) => Stream.value({'quietFrom': 22, 'quietTo': 8})),
      osBildirimDurumuProvider.overrideWith((ref) async => durum),
    ],
    child: _uygulama(home),
  ));
  // Sağlayıcı gelecekleri mikro görevde çözülür: tek kare yetmez.
  await tester.pump();
  await tester.pump();
  await tester.pump(RythoMotion.base);
}

void main() {
  group('OS izni bandı', () {
    testWidgets('reddedilmiş → IzinKapaliBandi + ayarlar düğmesi',
        (tester) async {
      await _ekran(tester, const Scaffold(body: NotificationSettings()),
          durum: AuthorizationStatus.denied);

      expect(find.byType(IzinKapaliBandi), findsOneWidget);
      expect(find.text(_tr.notifPermissionOffTitle), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, _tr.settings), findsOneWidget,
          reason: 'yol tarifi değil, ayarlara giden düğme');
    });

    testWidgets('verilmiş → band çizilmez', (tester) async {
      await _ekran(tester, const Scaffold(body: NotificationSettings()));
      expect(find.text(_tr.notifPermissionOffTitle), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('sessiz saat yuvarlama — saf', () {
    test('sessizSaatYuvarla 21:40 → 21', () {
      expect(sessizSaatYuvarla(const TimeOfDay(hour: 21, minute: 40)), 21);
      expect(sessizSaatYuvarla(const TimeOfDay(hour: 8, minute: 0)), 8);
    });

    test('not: tam saatlerde null; dakika varsa yazılan aralık', () {
      expect(
          sessizSaatNotu(_tr, const TimeOfDay(hour: 22, minute: 0),
              const TimeOfDay(hour: 8, minute: 0)),
          isNull);
      expect(
          sessizSaatNotu(_tr, const TimeOfDay(hour: 21, minute: 40),
              const TimeOfDay(hour: 8, minute: 0)),
          _tr.quietHoursRoundedNote(_tr.quietHoursRange('21', '08')));
    });

    test('yuvarlama iki ucu eşitlerse not "Kapalı" der (sunucu kuralı)', () {
      expect(
          sessizSaatNotu(_tr, const TimeOfDay(hour: 21, minute: 40),
              const TimeOfDay(hour: 21, minute: 10)),
          _tr.quietHoursRoundedNote(_tr.quietHoursOff));
    });
  });

  group('sessiz saat seçimi', () {
    testWidgets('iki seçici farklı helpText (Başlangıç / Bitiş); dakika '
        'yuvarlanır, yazılır ve SnackBar söyler', (tester) async {
      final basliklar = <String>[];
      final yazilan = <(String, Object?)>[];
      final cevaplar = [
        const TimeOfDay(hour: 21, minute: 40),
        const TimeOfDay(hour: 8, minute: 0),
      ];
      await _ekran(
        tester,
        Scaffold(
          body: NotificationSettings(
            saatSec: (context, baslangic, helpText) async {
              basliklar.add(helpText);
              return cevaplar.removeAt(0);
            },
            yaz: (alan, deger) async => yazilan.add((alan, deger)),
          ),
        ),
      );

      await tester.tap(find.text(_tr.quietHours));
      await tester.pump();
      await tester.pump(RythoMotion.base);

      expect(basliklar, [_tr.quietHoursFrom, _tr.quietHoursTo],
          reason: 'iki kadran iki ayrı başlık taşımalı');
      expect(basliklar.toSet().length, 2);
      expect(yazilan, [('quietFrom', 21), ('quietTo', 8)]);
      expect(
          find.text(_tr.quietHoursRoundedNote(_tr.quietHoursRange('21', '08'))),
          findsOneWidget,
          reason: 'atılan dakika söylenir');
    });

    testWidgets('tam saatlerde SnackBar YOK; ilk seçici iptal → hiçbir şey '
        'yazılmaz', (tester) async {
      final yazilan = <(String, Object?)>[];
      var cagri = 0;
      await _ekran(
        tester,
        Scaffold(
          body: NotificationSettings(
            saatSec: (context, baslangic, helpText) async {
              cagri++;
              return cagri == 1 ? null : const TimeOfDay(hour: 7, minute: 0);
            },
            yaz: (alan, deger) async => yazilan.add((alan, deger)),
          ),
        ),
      );

      await tester.tap(find.text(_tr.quietHours));
      await tester.pump();
      await tester.pump(RythoMotion.base);
      expect(cagri, 1, reason: 'ilk seçici iptal edilince ikincisi açılmaz');
      expect(yazilan, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('satır değeri aralığı gösterir: 22:00 – 08:00', (tester) async {
      await _ekran(tester, const Scaffold(body: NotificationSettings()));
      expect(find.text(_tr.quietHoursRange('22', '08')), findsOneWidget);
    });
  });

  group('tek başlık, tema rengi', () {
    testWidgets('sayfada "Bildirimler" bir kez (AppBar); plaka etiketi yok',
        (tester) async {
      await _ekran(tester, const NotificationSettingsScreen());
      expect(find.text(_tr.notifications), findsOneWidget);
    });

    testWidgets('üç Switch; hiçbiri elle renk taşımaz (tema switchTheme)',
        (tester) async {
      await _ekran(tester, const Scaffold(body: NotificationSettings()));
      final anahtarlar = tester.widgetList<Switch>(find.byType(Switch));
      expect(anahtarlar.length, 3);
      for (final s in anahtarlar) {
        expect(s.activeThumbColor, isNull);
        expect(s.activeTrackColor, isNull);
      }
    });

    test('kaynak: _PermissionBanner ve _Toggle yok; helpText iki anahtar',
        () {
      final k = _yorumsuz('lib/features/profile/notification_settings.dart');
      expect(k, isNot(contains('_PermissionBanner')));
      expect(k, isNot(contains('class _Toggle')));
      expect(k, isNot(contains('activeThumbColor')));
      expect(k, contains('l10n.quietHoursFrom'));
      expect(k, contains('l10n.quietHoursTo'));
      expect(k, isNot(contains('helpText: l10n.quietHours,')));
      expect(k, isNot(contains('label: l10n.notifications')));
    });
  });
}

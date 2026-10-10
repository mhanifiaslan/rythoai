// Günlük ekranı bekçileri (D5 §6).
//
// Ölçülen kusurlar: tema çipleri yalnız emoji taşıyordu (🪙 uygulamada üç
// anlamda: kredi / İ Ching / finans — etiketsiz çip hangisi olduğunu
// söylemiyordu) ve çip görünümü üçüncü elle kopyaydı; kaydet düğmesi
// Material `FilledButton` idi (tek CTA dili `GoldButton`, K5); silme onayı
// kendi `AlertDialog`ını kuruyordu.
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/features/profile/diary_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:rytho/widgets/basis_sheet.dart' show kThemeIcons, kThemeLabel;
import 'package:rytho/widgets/nebula_widgets.dart' show SuggestionChip;

final _tr = AppLocalizationsTr();

class _SahteAdapter implements HttpClientAdapter {
  _SahteAdapter({this.govde = '{"status":"ok","data":{"entries":[]}}'});

  final String govde;
  final List<RequestOptions> istekler = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istekler.add(options);
    return ResponseBody.fromString(govde, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Future<void> _ekran(WidgetTester tester, {_SahteAdapter? adapter}) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))
    ..httpClientAdapter = adapter ?? _SahteAdapter();
  tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiProvider.overrideWithValue(dio)],
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const DiaryScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump(RythoMotion.base);
}

String _cipMetni(String tema) => '${kThemeIcons[tema]} ${kThemeLabel(_tr, tema)}';

void main() {
  group('tema çipleri', () {
    testWidgets('dört çip ETİKETLİ (Kariyer / İlişkiler / İç dünya / Para), '
        'SuggestionChip', (tester) async {
      await _ekran(tester);

      expect(find.byType(SuggestionChip), findsNWidgets(kThemeIcons.length));
      expect(find.textContaining(_tr.diaryThemeCareer), findsOneWidget);
      expect(find.textContaining(_tr.diaryThemeRelationships), findsOneWidget);
      expect(find.textContaining(_tr.diaryThemeInner), findsOneWidget);
      expect(find.textContaining(_tr.diaryThemeFinance), findsOneWidget);
    });

    testWidgets('dokunuş seçer, ikinci dokunuş kaldırır', (tester) async {
      await _ekran(tester);
      final kariyer = find.widgetWithText(SuggestionChip, _cipMetni('career'));

      expect(tester.widget<SuggestionChip>(kariyer).selected, isFalse);
      await tester.tap(kariyer);
      await tester.pump(RythoMotion.press);
      expect(tester.widget<SuggestionChip>(kariyer).selected, isTrue);
      // Diğerleri seçilmedi.
      expect(
          tester
              .widget<SuggestionChip>(
                  find.widgetWithText(SuggestionChip, _cipMetni('finance')))
              .selected,
          isFalse);
      await tester.tap(kariyer);
      await tester.pump(RythoMotion.press);
      expect(tester.widget<SuggestionChip>(kariyer).selected, isFalse);
    });

    test('kThemeLabel: dört anahtar ARB\'den; bilinmeyen olduğu gibi', () {
      expect(kThemeLabel(_tr, 'career'), _tr.diaryThemeCareer);
      expect(kThemeLabel(_tr, 'relationships'), _tr.diaryThemeRelationships);
      expect(kThemeLabel(_tr, 'inner'), _tr.diaryThemeInner);
      expect(kThemeLabel(_tr, 'finance'), _tr.diaryThemeFinance);
      expect(kThemeLabel(_tr, 'yeni'), 'yeni');
      // İkon tablosuyla aynı küme: biri genişleyip diğeri kalmasın.
      for (final t in kThemeIcons.keys) {
        expect(kThemeLabel(_tr, t), isNot(t), reason: '$t etiketsiz');
      }
    });
  });

  group('kaydet', () {
    testWidgets('GoldButton; boş metinde kapalı, metinle açık; POST tema ile',
        (tester) async {
      final adapter = _SahteAdapter(
          govde:
              '{"status":"ok","data":{"entries":[],"id":"d1","text":"x","date":"2026-10-10"}}');
      await _ekran(tester, adapter: adapter);

      expect(find.byType(FilledButton), findsNothing);
      final kaydet = find.widgetWithText(GoldButton, _tr.diarySave);
      expect(kaydet, findsOneWidget);
      expect(tester.widget<GoldButton>(kaydet).onPressed, isNull,
          reason: 'boş metin kaydedilmez; düğme bunu söylemeli');

      await tester.enterText(find.byType(TextField), 'Bugün terfi aldım.');
      tester.widget<TextField>(find.byType(TextField)).controller?.selection =
          const TextSelection.collapsed(offset: -1);
      await tester.pump();
      expect(tester.widget<GoldButton>(kaydet).onPressed, isNotNull);

      await tester.tap(find.widgetWithText(SuggestionChip, _cipMetni('career')));
      await tester.pump(RythoMotion.press);
      await tester.tap(kaydet);
      await tester.pump();
      await tester.pump(RythoMotion.base);

      final post = adapter.istekler.where((i) => i.method == 'POST').single;
      expect(post.path, '/api/v1/account/diary');
      expect(post.data, {'text': 'Bugün terfi aldım.', 'theme': 'career'});
    });
  });

  group('kaynak', () {
    test('FilledButton ve AlertDialog yok; onayla ve kThemeLabel var', () {
      final k = _yorumsuz('lib/features/profile/diary_screen.dart');
      expect(k, isNot(contains('FilledButton(')));
      expect(k, isNot(contains('AlertDialog(')));
      expect(k, contains('onayla('));
      expect(k, contains('kThemeLabel(l10n, tema)'));
      expect(k, contains('SuggestionChip('));
    });
  });
}

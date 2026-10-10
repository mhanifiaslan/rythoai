// Hesap silme sayfası bekçileri (D5 §6).
//
// Ölçülen kusur: onay sözcüğü `toUpperCase()` ile karşılaştırılıyordu —
// Türkçe klavyede "sil" → "SIL" ≠ "SİL", düğme açıklamasız kapalı
// kalıyordu. İkincisi: yıkıcı düğme mor degradeliydi (davet eden parıltı);
// üçüncüsü: 401'de "çıkış yapıp yeniden gir" metni vardı ama çıkışın kapısı
// yoktu. Dördüncüsü: alt sayfa kabuğu elle yazılmış ikinci kopyaydı.
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/features/profile/delete_account.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;

final _tr = AppLocalizationsTr();

/// Sabit yanıt veren sahte sunucu (feedback_screen_test ile aynı desen).
class _SahteAdapter implements HttpClientAdapter {
  _SahteAdapter({this.durum = 200, this.govde = '{"status":"ok"}'});

  final int durum;
  final String govde;
  final List<RequestOptions> istekler = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istekler.add(options);
    return ResponseBody.fromString(govde, durum, headers: {
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

Future<void> _sayfa(WidgetTester tester,
    {_SahteAdapter? adapter, Future<void> Function()? cikis}) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))
    ..httpClientAdapter = adapter ?? _SahteAdapter();
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
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
      home: Scaffold(
        body: SingleChildScrollView(
          child: DeleteAccountSheet(cikis: cikis ?? () async {}),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Onay alanına yazar. Seçim temizlenir: test ortamında seçim tutamaçları
/// `errorText` değişince çizilirken `RenderEditable` null'a düşüyor
/// (feedback_screen_test'te ölçülmüş test-ortamı kusuru, ürün değil).
Future<void> _yaz(WidgetTester tester, String metin) async {
  await tester.enterText(find.byType(TextField), metin);
  tester.widget<TextField>(find.byType(TextField)).controller?.selection =
      const TextSelection.collapsed(offset: -1);
  await tester.pump();
}

GoldButton _silDugmesi(WidgetTester tester) => tester.widget<GoldButton>(
    find.widgetWithText(GoldButton, _tr.deleteAccountAction));

void main() {
  group('onay sözcüğü klavye düzeninden bağımsız', () {
    testWidgets('"sil" / "SİL" / "SIL" hepsi düğmeyi açar; "sel" açmaz',
        (tester) async {
      await _sayfa(tester);
      expect(_silDugmesi(tester).onPressed, isNull, reason: 'boşken kapalı');

      for (final g in ['sil', 'SİL', 'SIL', ' Sil ']) {
        await _yaz(tester, g);
        expect(_silDugmesi(tester).onPressed, isNotNull, reason: g);
      }
      await _yaz(tester, 'sel');
      expect(_silDugmesi(tester).onPressed, isNull);
    });
  });

  group('yıkıcı düğme', () {
    testWidgets('destructive: degrade yok, madder dolgu', (tester) async {
      await _sayfa(tester);
      await _yaz(tester, 'SİL');

      final dugme = _silDugmesi(tester);
      expect(dugme.destructive, isTrue);
      final dekor = tester
          .widget<Container>(find.descendant(
              of: find.byWidget(dugme), matching: find.byType(Container)))
          .decoration! as BoxDecoration;
      expect(dekor.gradient, isNull, reason: 'yıkıcı eylem degrade almaz');
      expect(dekor.color, RythoColors.madder);
    });
  });

  group('sunucu yanıtı', () {
    testWidgets('200 → DELETE /api/v1/account/me, sonra çıkış', (tester) async {
      final adapter = _SahteAdapter();
      var cikis = 0;
      await _sayfa(tester, adapter: adapter, cikis: () async => cikis++);
      await _yaz(tester, 'SİL');
      await tester.tap(find.widgetWithText(GoldButton, _tr.deleteAccountAction));
      await tester.pump();
      await tester.pump(RythoMotion.base);

      final istek = adapter.istekler.single;
      expect(istek.method, 'DELETE');
      expect(istek.path, '/api/v1/account/me');
      expect(cikis, 1, reason: 'sunucu sildi, yerel oturum da kapanmalı');
    });

    testWidgets('401 → yeniden giriş metni + ÇIKIŞ eylemi (onaysız); '
        'silme düğmesi çekilir', (tester) async {
      final adapter = _SahteAdapter(
          durum: 401, govde: '{"status":"error","detail":"reauth"}');
      var cikis = 0;
      await _sayfa(tester, adapter: adapter, cikis: () async => cikis++);
      await _yaz(tester, 'SİL');
      await tester.tap(find.widgetWithText(GoldButton, _tr.deleteAccountAction));
      await tester.pump();
      await tester.pump(RythoMotion.base);

      expect(find.text(_tr.deleteAccountReauth), findsOneWidget);
      expect(cikis, 0, reason: '401 tek başına çıkış yapmaz');
      final cikisDugmesi = find.widgetWithText(GoldButton, _tr.signOut);
      expect(cikisDugmesi, findsOneWidget, reason: 'metnin yanında eylem');
      expect(find.widgetWithText(GoldButton, _tr.deleteAccountAction),
          findsNothing, reason: 'ikinci deneme yine 401 alır');

      await tester.tap(cikisDugmesi);
      await tester.pump();
      await tester.pump(RythoMotion.base);
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'kullanıcı zaten onay sözcüğünü yazdı; ikinci soru yok');
      expect(cikis, 1);
    });

    testWidgets('diğer hata → genel metin, düğme kilitli kalmaz',
        (tester) async {
      await _sayfa(tester,
          adapter: _SahteAdapter(durum: 500, govde: '{"status":"error"}'));
      await _yaz(tester, 'SİL');
      await tester.tap(find.widgetWithText(GoldButton, _tr.deleteAccountAction));
      await tester.pump();
      await tester.pump(RythoMotion.base);

      expect(find.text(_tr.deleteAccountFailed), findsOneWidget);
      expect(_silDugmesi(tester).busy, isFalse);
      expect(_silDugmesi(tester).onPressed, isNotNull);
    });
  });

  group('kaynak', () {
    test('kabuk showRythoSheet; showModalBottomSheet ve toUpperCase YOK',
        () {
      final k = _yorumsuz('lib/features/profile/delete_account.dart');
      expect(k, contains('showRythoSheet<void>('));
      expect(k, isNot(contains('showModalBottomSheet')));
      expect(k, isNot(contains('toUpperCase(')));
      expect(k, contains('onayKelimesiEslesiyor('));
      expect(k, contains('onayliCikis(context, onay: false'));
    });
  });
}

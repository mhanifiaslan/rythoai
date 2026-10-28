// Hesap silme sayfası bekçileri (D5 §6).
//
// Ölçülen kusur: onay sözcüğü `toUpperCase()` ile karşılaştırılıyordu —
// Türkçe klavyede "sil" → "SIL" ≠ "SİL", düğme açıklamasız kapalı
// kalıyordu. İkincisi: yıkıcı düğme mor degradeliydi (davet eden parıltı);
// üçüncüsü: 401'de "çıkış yapıp yeniden gir" metni vardı ama çıkışın kapısı
// yoktu. Dördüncüsü: alt sayfa kabuğu elle yazılmış ikinci kopyaydı.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/auth_service.dart' show AppleIptalSonucu;
import 'package:rytho/features/profile/delete_account.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/alt_sayfa.dart' show showRythoSheet;
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

/// Yanıtı (durum koduyla) elle bırakılan sahte sunucu: silme sürerken
/// ekranı ölçmek için.
class _BekleyenAdapter implements HttpClientAdapter {
  final cevap = Completer<int>();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final durum = await cevap.future;
    return ResponseBody.fromString('{"status":"x"}', durum, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Üretimdeki yığın: kök → basılı Hesap sayfası → silme alt sayfası.
Future<void> _hesaptanAc(WidgetTester tester,
    {required HttpClientAdapter adapter,
    Iterable<String> saglayicilar = const [],
    Future<AppleIptalSonucu> Function(void Function() onayVerildi)?
        appleIptali,
    Future<void> Function()? cikis}) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))
    ..httpClientAdapter = adapter;
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
      home: Builder(
        builder: (kokBaglam) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(kokBaglam).push(MaterialPageRoute(
              builder: (hesapBaglam) => Scaffold(
                body: TextButton(
                  onPressed: () => showRythoSheet<void>(
                    hesapBaglam,
                    klavyeyeUy: true,
                    enableDrag: false,
                    builder: (_) => DeleteAccountSheet(
                        saglayicilar: saglayicilar,
                        appleIptali: appleIptali,
                        cikis: cikis ?? () async {}),
                  ),
                  child: const Text('hesap-sil'),
                ),
              ),
            )),
            child: const Text('kok-hesap'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('kok-hesap'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('hesap-sil'));
  await tester.pumpAndSettle();
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

  group('silme sonrası ve sırasında (iPad, 2026-10-28)', () {
    testWidgets('200 → alt sayfa VE altındaki Hesap sayfası kapanır, kök '
        'görünür', (tester) async {
      var cikis = 0;
      await _hesaptanAc(tester,
          adapter: _SahteAdapter(), cikis: () async => cikis++);
      await _yaz(tester, 'SİL');
      await tester.tap(find.widgetWithText(GoldButton, _tr.deleteAccountAction));
      await tester.pumpAndSettle();

      expect(cikis, 1);
      expect(find.byType(DeleteAccountSheet), findsNothing);
      expect(find.text('hesap-sil'), findsNothing,
          reason: 'silinen hesabın Hesap sayfası girişin üstünde kalıyordu');
      expect(find.text('kok-hesap'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('silme sürerken "siliniyor" yazar; bitince yazı da gider',
        (tester) async {
      final adapter = _BekleyenAdapter();
      await _hesaptanAc(tester, adapter: adapter);
      await _yaz(tester, 'SİL');
      expect(find.text(_tr.deleteAccountInProgress), findsNothing);

      await tester.tap(find.widgetWithText(GoldButton, _tr.deleteAccountAction));
      await tester.pump();
      await tester.pump(RythoMotion.base);
      expect(find.text(_tr.deleteAccountInProgress), findsOneWidget,
          reason: 'sayfa silme boyunca aynı kalıyor ve donmuş okunuyordu');

      adapter.cevap.complete(200);
      await tester.pumpAndSettle();
      expect(find.text(_tr.deleteAccountInProgress), findsNothing);
    });

    testWidgets('hata dönünce "siliniyor" yazısı kalmaz', (tester) async {
      await _hesaptanAc(tester,
          adapter: _SahteAdapter(durum: 500, govde: '{"status":"error"}'));
      await _yaz(tester, 'SİL');
      await tester.tap(find.widgetWithText(GoldButton, _tr.deleteAccountAction));
      await tester.pumpAndSettle();

      expect(find.text(_tr.deleteAccountFailed), findsOneWidget);
      expect(find.text(_tr.deleteAccountInProgress), findsNothing);
      expect(find.text('hesap-sil'), findsOneWidget,
          reason: 'silinmedi: kullanıcı Hesap sayfasında kalır');
    });

    // Uyarının kapısı ÜRETİMDEKİ kapı (`appleHesabaBagli`): platform ve
    // sağlayıcılar gerçek girdi, sayfaya hazır bir bool verilmiyor.
    testWidgets('iOS + Apple bağlı: onay ÖNCEDEN söylenir', (tester) async {
      await _hesaptanAc(tester,
          adapter: _SahteAdapter(), saglayicilar: const ['apple.com']);
      expect(find.text(_tr.deleteAccountAppleNotice), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('iOS ama Apple bağlı değil: uyarı yok', (tester) async {
      await _hesaptanAc(tester,
          adapter: _SahteAdapter(),
          saglayicilar: const ['google.com', 'password']);
      expect(find.text(_tr.deleteAccountAppleNotice), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Android + apple.com: uyarı yok (adım yalnız iOS)',
        (tester) async {
      await _hesaptanAc(tester,
          adapter: _SahteAdapter(), saglayicilar: const ['apple.com']);
      expect(find.text(_tr.deleteAccountAppleNotice), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('Apple onayı beklenirken "siliniyor" YOK; onaydan sonra var',
        (tester) async {
      final onayKapisi = Completer<void>();
      final iptalKapisi = Completer<void>();
      await _hesaptanAc(tester,
          adapter: _SahteAdapter(),
          saglayicilar: const ['apple.com'],
          appleIptali: (onayVerildi) async {
            await onayKapisi.future;
            onayVerildi();
            await iptalKapisi.future;
            return AppleIptalSonucu.iptalEdildi;
          });
      await _yaz(tester, 'SİL');
      await tester.tap(find.widgetWithText(GoldButton, _tr.deleteAccountAction));
      await tester.pump();
      expect(find.text(_tr.deleteAccountInProgress), findsNothing,
          reason: 'Apple onayı beklenirken henüz hiçbir şey silinmiyor');
      // Meşgulken düğmede yazı yerine dönen işaret var; türüyle bulunur.
      expect(tester.widget<GoldButton>(find.byType(GoldButton)).busy, isTrue);

      onayKapisi.complete();
      await tester.pump();
      expect(find.text(_tr.deleteAccountInProgress), findsOneWidget,
          reason: 'onaydan sonra iptal + silme ağda; sayfa donmuş okunmasın');

      iptalKapisi.complete();
      await tester.pumpAndSettle();
      expect(find.text('kok-hesap'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('silme uçarken dışarı dokunmak sayfayı KAPATMAZ; hata '
        'görünür', (tester) async {
      final adapter = _BekleyenAdapter();
      await _hesaptanAc(tester, adapter: adapter);
      await _yaz(tester, 'SİL');
      await tester.tap(find.widgetWithText(GoldButton, _tr.deleteAccountAction));
      await tester.pump();

      // Karartılmış alan (sayfa ekranın altında, içerik kısa).
      await tester.tapAt(const Offset(20, 20));
      // pumpAndSettle değil: düğmedeki dönen işaret silme boyunca döner.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DeleteAccountSheet), findsOneWidget,
          reason: 'kapansa hata ve 401 çaresi hiç gösterilmezdi');

      adapter.cevap.complete(500);
      await tester.pumpAndSettle();
      expect(find.text(_tr.deleteAccountFailed), findsOneWidget);
    });

    testWidgets('silme başlamadan dışarı dokunmak sayfayı kapatır',
        (tester) async {
      await _hesaptanAc(tester, adapter: _SahteAdapter());
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteAccountSheet), findsNothing);
      expect(find.text('hesap-sil'), findsOneWidget);
    });

    testWidgets('401 → çıkış: sayfa VE Hesap sayfası kapanır', (tester) async {
      var cikis = 0;
      await _hesaptanAc(tester,
          adapter: _SahteAdapter(
              durum: 401, govde: '{"status":"error","detail":"reauth"}'),
          cikis: () async => cikis++);
      await _yaz(tester, 'SİL');
      await tester.tap(find.widgetWithText(GoldButton, _tr.deleteAccountAction));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GoldButton, _tr.signOut));
      await tester.pumpAndSettle();

      expect(cikis, 1);
      expect(find.text('hesap-sil'), findsNothing);
      expect(find.text('kok-hesap'), findsOneWidget);
    });
  });

  group('kabuk', () {
    test('silme sayfası sürükleyerek kapanmaz (sürükleme PopScope\'a '
        'sormaz)', () {
      final k = _yorumsuz('lib/features/profile/delete_account.dart');
      final ac = k.substring(k.indexOf('Future<void> showDeleteAccountSheet'));
      expect(ac, contains('enableDrag: false'));
      expect(k, contains('PopScope(canPop: !_busy'));
    });
  });
}

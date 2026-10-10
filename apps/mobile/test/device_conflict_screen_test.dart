// Cihaz çakışması kapısı bekçileri (TC-turu K6).
//
// Eski ekranın tek eylemi "giriş ekranına dön"dü; oturum zaten kapalı
// olduğu için devralma 401'e çarpıyor, geri tuşu da `_soruldu` bayrağını
// sıfırlamadan çıkarıyordu. Yeni sözleşme: (1) geri tuşu geçmez; (2) metinler
// l10n'dan, diğer cihazın platformu ve YEREL saati gövdede; (3) "Bu cihazda
// kullan" kimlikli claim → başarıda kapı açılır ve 409'la düşmüş Rytho+
// sağlayıcıları tazelenir, başarısızlıkta SÖYLENİR; (4) "Oturumu kapat"
// (profildeki çıkışla AYNI anahtar `signOut`, D4) çıkış yoluna gider, claim
// atmaz; (5) diğer cihaz bilgisi hiç yoksa gövde "—" tireleriyle değil
// bilgisiz cümleyle (`deviceConflictBodyUnknown`) kurulur.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/device_session.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/auth/device_conflict_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';

/// Sabit yanıt veren sahte sunucu; istekleri saklar.
class _SahteAdapter implements HttpClientAdapter {
  _SahteAdapter({this.durum = 200, this.govde = '{"claimed":true}'});

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

/// Rytho+ uçlarına POST atan sağlayıcılar (core/providers.dart) — devralma
/// sonrası HEPSİ yeniden kurulmalı; 409'lu eski sonuç önbellekte kalmasın.
final _plusSaglayicilar = <String, FutureProvider<Map<String, dynamic>?>>{
  'daily': dailyReadingProvider,
  'natal': natalReportProvider,
  'bazi': baziReportProvider,
  'birth_hexagram': birthHexagramProvider,
  'solar_return': solarReturnProvider,
  'progressions': innerCalendarProvider,
};

/// Sağlayıcı kuruluş sayacı.
class _Sayac {
  final Map<String, int> kurulum = {};

  void say(String ad) => kurulum[ad] = (kurulum[ad] ?? 0) + 1;
}

final _kAn = DateTime.utc(2026, 9, 12, 10);

/// Kap: sahte Dio + sayaçlı sağlayıcılar + kapalı kapı. Sağlayıcılar kabukta
/// olduğu gibi CANLI tutulur; dinleyici olmadan tazeleme gözlenemez.
ProviderContainer _kap(_SahteAdapter adapter, _Sayac sayac,
    {DeviceConflict? cakisma}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))
    ..httpClientAdapter = adapter;
  final kap = ProviderContainer(overrides: [
    apiProvider.overrideWithValue(dio),
    for (final e in _plusSaglayicilar.entries)
      e.value.overrideWith((_) async {
        sayac.say(e.key);
        return null;
      }),
  ]);
  addTearDown(kap.dispose);
  kap.read(deviceConflictProvider.notifier).state =
      cakisma ?? DeviceConflict(platform: 'android', claimedAt: _kAn);
  for (final p in _plusSaglayicilar.values) {
    kap.listen(p, (_, _) {});
  }
  return kap;
}

/// reduceMotion AÇIK sarılır (force_update_screen_test ile aynı gerekçe:
/// yıldız alanı sonsuz döngü, `pumpAndSettle` yasak).
Widget _sar(ProviderContainer kap, Widget child) => UncontrolledProviderScope(
      container: kap,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child,
          ),
        ),
      ),
    );

/// ARB'deki metin — üretilen sınıftan okunur ki metin değişince test
/// kırılmasın ama anahtar silinirse derleme kırılsın.
AppLocalizations _tr() => lookupAppLocalizations(const Locale('tr'));

/// Düğmeye dokunup Dio hattının gerçek olay döngüsünde bitmesini bekler
/// (sahte zamanda ilerlemez — app_gate_test ile aynı gerekçe).
Future<void> _dokun(WidgetTester tester, String metin) async {
  await tester.runAsync(() async {
    await tester.tap(find.text(metin));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
  // SnackBar girişi.
  await tester.pump(const Duration(milliseconds: 300));
}

/// Tazelemeyi zamanlayıcıdan bağımsız gözle: kirli sağlayıcı okununca
/// yeniden kurulur, temiz olan önbellekten döner.
Map<String, int> _kurulumlar(ProviderContainer kap, _Sayac sayac) {
  for (final p in _plusSaglayicilar.values) {
    kap.read(p);
  }
  return Map.of(sayac.kurulum);
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('geri tuşu geçmez: PopScope canPop false, ekran kapsamın İÇİNDE',
      (tester) async {
    await tester.pumpWidget(
        _sar(_kap(_SahteAdapter(), _Sayac()), const DeviceConflictScreen()));
    // `find.byType(PopScope)` jenerik parametreyle eşleşmez; `is` ile.
    final kapsam = find.byWidgetPredicate((w) => w is PopScope);
    expect(kapsam, findsOneWidget);
    expect((tester.widget(kapsam) as PopScope).canPop, isFalse,
        reason: 'kök rotada geri tuşu uygulamayı arka plana atıp "kapı '
            'geçildi" hissi verirdi');
    expect(
        find.descendant(
            of: kapsam, matching: find.text(_tr().deviceConflictTitle)),
        findsOneWidget);
  });

  testWidgets('metinler l10n\'dan: başlık, gövde (platform + YEREL saat), '
      'iki eylem', (tester) async {
    await tester.pumpWidget(
        _sar(_kap(_SahteAdapter(), _Sayac()), const DeviceConflictScreen()));
    final l10n = _tr();
    final saat = DateFormat('d MMMM HH:mm', 'tr').format(_kAn.toLocal());
    expect(find.text(l10n.deviceConflictTitle), findsOneWidget);
    expect(find.text(l10n.deviceConflictBody('Android', saat)), findsOneWidget,
        reason: 'kullanıcı hangi cihazın ne zaman aldığını görmeli');
    expect(find.text(l10n.deviceConflictUseHere), findsOneWidget);
    expect(find.text(l10n.signOut), findsOneWidget,
        reason: 'profildeki çıkışla AYNI anahtar; "Çıkış yap" ikiliği bitti');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('diğer cihaz bilgisi yoksa gövde BİLGİSİZ cümle, "—" tireleri '
      'yok — kapı yine kapalı', (tester) async {
    await tester.pumpWidget(_sar(
        _kap(_SahteAdapter(), _Sayac(), cakisma: const DeviceConflict()),
        const DeviceConflictScreen()));
    final l10n = _tr();
    expect(find.text(l10n.deviceConflictBodyUnknown), findsOneWidget,
        reason: '"— cihazında — saatinde" diye okunuyordu; bilinmeyen '
            'söylenmez');
    expect(find.text(l10n.deviceConflictBody('—', '—')), findsNothing);
    expect(find.text(l10n.deviceConflictUseHere), findsOneWidget,
        reason: 'bilgi yok diye kapı açılmaz');
  });

  testWidgets('yalnız saat bilinmiyorsa ÖLÇÜLEN platform atılmaz',
      (tester) async {
    await tester.pumpWidget(_sar(
        _kap(_SahteAdapter(), _Sayac(),
            cakisma: const DeviceConflict(platform: 'android')),
        const DeviceConflictScreen()));
    final l10n = _tr();
    expect(find.text(l10n.deviceConflictBody('Android', '—')), findsOneWidget,
        reason: 'bilgisiz cümleye düşmek eldeki platformu atardı');
    expect(find.text(l10n.deviceConflictBodyUnknown), findsNothing);
  });

  testWidgets('"Bu cihazda kullan": kimlikli POST /device/claim → kapı açılır, '
      'Rytho+ sağlayıcıları tazelenir', (tester) async {
    final adapter = _SahteAdapter(govde: '{"claimed":true}');
    final sayac = _Sayac();
    final kap = _kap(adapter, sayac);
    await tester.pumpWidget(_sar(kap, const DeviceConflictScreen()));
    expect(_kurulumlar(kap, sayac).values, everyElement(1),
        reason: 'kabuktaki gibi bir kez kurulu');

    await _dokun(tester, _tr().deviceConflictUseHere);

    final istek = adapter.istekler.single;
    expect(istek.method, 'POST');
    expect(istek.path, '/api/v1/device/claim');
    expect((istek.data as Map)['platform'], defaultTargetPlatform.name);
    expect(kap.read(deviceConflictProvider), isNull, reason: 'kapı açılır');
    expect(_kurulumlar(kap, sayac), {
      for (final k in _plusSaglayicilar.keys) k: 2,
    }, reason: '409 ile düşen sonuç önbellekte kalırsa ana ekran devralmadan '
            'sonra da "hata" gösterir');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('claimed:false → kapı KAPALI kalır, SnackBar söyler, '
      'sağlayıcılara dokunulmaz', (tester) async {
    final sayac = _Sayac();
    final kap = _kap(_SahteAdapter(govde: '{"claimed":false}'), sayac);
    await tester.pumpWidget(_sar(kap, const DeviceConflictScreen()));

    await _dokun(tester, _tr().deviceConflictUseHere);

    expect(kap.read(deviceConflictProvider), isNotNull);
    expect(find.text(_tr().deviceConflictClaimFailed), findsOneWidget,
        reason: 'sessiz kalan düğme, çıkışı olmayan ekranda "bozuldu" demektir');
    expect(_kurulumlar(kap, sayac).values, everyElement(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('claim fırlatırsa (500) da söylenir; kapı kapalı kalır',
      (tester) async {
    final sayac = _Sayac();
    final kap = _kap(_SahteAdapter(durum: 500, govde: '{"detail":"x"}'), sayac);
    await tester.pumpWidget(_sar(kap, const DeviceConflictScreen()));

    await _dokun(tester, _tr().deviceConflictUseHere);

    expect(kap.read(deviceConflictProvider), isNotNull);
    expect(find.text(_tr().deviceConflictClaimFailed), findsOneWidget);
    expect(_kurulumlar(kap, sayac).values, everyElement(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Oturumu kapat" → çıkış kancası; claim atılmaz',
      (tester) async {
    var cikis = 0;
    final adapter = _SahteAdapter();
    final kap = _kap(adapter, _Sayac());
    await tester.pumpWidget(
        _sar(kap, DeviceConflictScreen(signOut: () async => cikis++)));

    await _dokun(tester, _tr().signOut);

    expect(cikis, 1);
    expect(adapter.istekler, isEmpty);
  });
}

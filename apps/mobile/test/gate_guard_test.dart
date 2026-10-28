// Kapı bekçisi (TC-turu denetim bulgusu): 426/409 kapısı `_Gate`'in `home`
// alt ağacını değiştirir; üstte basılı bir rota (sohbet, yüz okuma, kehanet)
// varsa yeni ekran onun ALTINDA kalır ve "Bu cihazda kullan" düğmesine
// ulaşılamazdı. `GateRootGuard` kapı kapandığı an yığını köke indirir.
//
// Üçüncü kapı oturumun kapanması (iPad, 2026-10-28): hesap Hesap
// sayfasından silinince giriş sayfası kökte kuruluyor, Hesap sayfası
// üstünde kalıyordu.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/app_config.dart' show mustForceUpdateProvider;
import 'package:rytho/core/device_session.dart';
import 'package:rytho/core/gate_guard.dart';
import 'package:rytho/core/providers.dart' show authStateProvider;

/// Zorunlu güncelleme kapısının test anahtarı; gerçek sağlayıcı açılış
/// okuması + PackageInfo ister.
final _zorla = StateProvider<bool>((_) => false);

const _kok = Key('kok');
const _basili = Key('basili');

/// Oturum akışına konacak sahte kullanıcı; bekçi yalnız null olup
/// olmadığına bakıyor, diğer üyeler `noSuchMethod`a düşer.
class _SahteKullanici implements User {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _Harness {
  _Harness() : key = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> key;
  late final ProviderContainer kap;

  /// Oturum akışı; gerçek sağlayıcı `FirebaseAuth.instance` ister.
  final oturum = StreamController<User?>.broadcast();

  Widget build() {
    kap = ProviderContainer(overrides: [
      mustForceUpdateProvider.overrideWith((ref) => ref.watch(_zorla)),
      authStateProvider.overrideWith((_) => oturum.stream),
    ]);
    return UncontrolledProviderScope(
      container: kap,
      child: GateRootGuard(
        navigatorKey: key,
        child: MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: Text('kök', key: _kok)),
        ),
      ),
    );
  }

  Future<void> bas(WidgetTester tester) async {
    key.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('basılı', key: _basili))));
    await tester.pumpAndSettle();
    expect(find.byKey(_basili), findsOneWidget);
    expect(find.byKey(_kok), findsNothing);
  }
}

void main() {
  testWidgets('409 kapısı kapanınca basılı rota iner, kök görünür',
      (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await h.bas(tester);

    h.kap.read(deviceConflictProvider.notifier).state =
        DeviceConflict(platform: 'iOS', claimedAt: DateTime.utc(2026, 9, 12));
    await tester.pumpAndSettle();

    expect(find.byKey(_basili), findsNothing);
    expect(find.byKey(_kok), findsOneWidget);
  });

  testWidgets('426 kapısı kapanınca da iner', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await h.bas(tester);

    h.kap.read(_zorla.notifier).state = true;
    await tester.pumpAndSettle();

    expect(find.byKey(_basili), findsNothing);
    expect(find.byKey(_kok), findsOneWidget);
  });

  testWidgets('üstteki diyalog da iner (kapı ekranı hiçbir şeyin altında '
      'kalmaz)', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    showDialog<void>(
        context: h.key.currentContext!,
        builder: (_) => const AlertDialog(content: Text('diyalog')));
    await tester.pumpAndSettle();
    expect(find.text('diyalog'), findsOneWidget);

    h.kap.read(deviceConflictProvider.notifier).state = const DeviceConflict();
    await tester.pumpAndSettle();

    expect(find.text('diyalog'), findsNothing);
    expect(find.byKey(_kok), findsOneWidget);
  });

  testWidgets('yalnız KAPANIŞ kenarı: kapı zaten kapalıyken bayrağın '
      'yeniden yazılması yığına dokunmaz', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    h.kap.read(deviceConflictProvider.notifier).state =
        const DeviceConflict(platform: 'android');
    await tester.pumpAndSettle();
    await h.bas(tester);

    // Uçuştaki ikinci 409'un başka bir başlıkla yazılması gibi.
    h.kap.read(deviceConflictProvider.notifier).state =
        const DeviceConflict(platform: 'iOS');
    await tester.pumpAndSettle();

    expect(find.byKey(_basili), findsOneWidget);
  });

  testWidgets('basılı rota yokken kapanış zararsız', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());

    h.kap.read(deviceConflictProvider.notifier).state = const DeviceConflict();
    await tester.pumpAndSettle();

    expect(find.byKey(_kok), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kapı açılınca (devralma başarılı) yığına dokunulmaz',
      (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    h.kap.read(deviceConflictProvider.notifier).state = const DeviceConflict();
    await tester.pumpAndSettle();
    h.kap.read(deviceConflictProvider.notifier).state = null;
    await tester.pumpAndSettle();
    await h.bas(tester);

    // Açılışın kendisi hiçbir şeyi indirmemeli; rota durur.
    expect(find.byKey(_basili), findsOneWidget);
  });

  group('oturum kapanınca', () {
    testWidgets('açık → kapalı: basılı rota iner, kök (giriş) görünür',
        (tester) async {
      final h = _Harness();
      // Sıra LIFO: önce konteyner atılır (akış aboneliği iptal), sonra akış
      // kapanır. Konteyner atılmadan `close()` beklenince test askıda
      // kaldı (ölçüldü): Riverpod 3 dinleyicisi kalmayan aboneliği iptal
      // etmez, DURAKLATIR (`element.dart`) ve `done` hiç teslim edilmez.
      addTearDown(h.oturum.close);
      await tester.pumpWidget(h.build());
      addTearDown(h.kap.dispose);
      h.oturum.add(_SahteKullanici());
      await tester.pumpAndSettle();
      await h.bas(tester);

      h.oturum.add(null);
      await tester.pumpAndSettle();

      expect(find.byKey(_basili), findsNothing,
          reason: 'silinen hesabın Hesap sayfası girişin üstünde kalıyordu');
      expect(find.byKey(_kok), findsOneWidget);
    });

    testWidgets('soğuk açılış (yükleme → çıkışlı) yığına dokunmaz',
        (tester) async {
      final h = _Harness();
      addTearDown(h.oturum.close);
      await tester.pumpWidget(h.build());
      addTearDown(h.kap.dispose);
      await h.bas(tester);

      h.oturum.add(null);
      await tester.pumpAndSettle();

      expect(find.byKey(_basili), findsOneWidget);
    });

    testWidgets('oturum açıkken yeniden yayın (aynı ya da başka kullanıcı) '
        'yığına dokunmaz', (tester) async {
      final h = _Harness();
      addTearDown(h.oturum.close);
      await tester.pumpWidget(h.build());
      addTearDown(h.kap.dispose);
      h.oturum.add(_SahteKullanici());
      await tester.pumpAndSettle();
      await h.bas(tester);

      h.oturum.add(_SahteKullanici());
      await tester.pumpAndSettle();

      expect(find.byKey(_basili), findsOneWidget);
    });
  });
}

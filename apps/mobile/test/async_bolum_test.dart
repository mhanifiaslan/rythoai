// `AsyncBolum` — sayfa içi asenkron bölümün üç hâli AYRI çizilir.
//
// Ölçülen kusur: ana ekranda sinyal ve takvim bölümleri `provider.value ??
// []` okuyup boşsa kendini gizliyordu; hata da `value == null` olduğu için
// AYNI yoldan geçiyordu. "Bugün sinyal yok" ile "yükleme düştü" ekranda
// ayırt edilemiyor, kullanıcı düşen isteği yeniden deneyemiyordu.
//
// Bu dosya üç hâli ve iki kapıyı sabitler: hata = hata kartı + tekrar dene;
// aşağı çekme tazelemesinde iskelet flaşı yok; boş veri = hiçbir şey.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/common.dart';
import 'package:rytho/widgets/glass.dart';

import 'dar_ekran_test.dart' show darEkranda, tasmaYok;

final _tr = AppLocalizationsTr();

/// Hata kartı girişte sarsılır (flutter_animate); `disableAnimations` onu
/// hiç kurdurmaz — ölçülen şey hangi hâlin çizildiği.
Widget _sar(Widget child) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('tr'), Locale('en')],
      theme: buildRythoTheme(),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

Widget _bolum(AsyncValue<List<int>> durum,
        {VoidCallback? onRetry,
        bool Function(List<int>)? bosMu,
        String? ekranKodu}) =>
    AsyncBolum<List<int>>(
      durum: durum,
      onRetry: onRetry ?? () {},
      bosMu: bosMu,
      ekranKodu: ekranKodu,
      iskeletYuksekligi: 120,
      veri: (v) => Text('veri:${v.length}'),
    );

void main() {
  testWidgets('yükleniyor: verilen yükseklikte iskelet', (tester) async {
    await tester.pumpWidget(_sar(_bolum(const AsyncLoading())));
    final iskelet = tester.widget<SkeletonPanel>(find.byType(SkeletonPanel));
    expect(iskelet.height, 120,
        reason: 'iskelet bölümün gerçek hacmini taklit etmeli');
    expect(find.byType(ErrorCard), findsNothing);
    expect(find.textContaining('veri:'), findsNothing);
  });

  testWidgets('hata: boş durumla AYNI DEĞİL — hata kartı ve tekrar dene',
      (tester) async {
    var denendi = 0;
    await tester.pumpWidget(_sar(_bolum(
        AsyncError(StateError('düştü'), StackTrace.empty),
        onRetry: () => denendi++)));

    expect(find.byType(ErrorCard), findsOneWidget,
        reason: '"bugün sinyal yok" ile "yükleme düştü" ayırt edilmeli');
    expect(find.byType(SkeletonPanel), findsNothing);
    // Ham hata metni değil, dürüst cümle (friendlyError).
    expect(find.text(_tr.errorGeneric), findsOneWidget);
    expect(find.textContaining('düştü'), findsNothing);

    await tester.tap(find.text('Tekrar dene'));
    expect(denendi, 1, reason: 'kullanıcı düşen isteği yeniden deneyebilmeli');
  });

  testWidgets('bildir düğmesi yalnız ekran kodu verilince', (tester) async {
    final hata = AsyncError<List<int>>(StateError('x'), StackTrace.empty);
    await tester.pumpWidget(_sar(_bolum(hata)));
    expect(find.text(_tr.feedbackReportThisScreen), findsNothing,
        reason: 'bölüm hatası ekranın tamamı değil; her geçici düşüşte '
            'bildir çağrısı gürültü');

    await tester.pumpWidget(_sar(_bolum(hata, ekranKodu: 'sky')));
    expect(find.text(_tr.feedbackReportThisScreen), findsOneWidget);
  });

  testWidgets('veri: gövde çizilir', (tester) async {
    await tester.pumpWidget(_sar(_bolum(const AsyncData([1, 2, 3]))));
    expect(find.text('veri:3'), findsOneWidget);
    expect(find.byType(SkeletonPanel), findsNothing);
    expect(find.byType(ErrorCard), findsNothing);
  });

  testWidgets('boş veri: bölüm kendini gizler, gövde hiç kurulmaz',
      (tester) async {
    var kuruldu = 0;
    await tester.pumpWidget(_sar(AsyncBolum<List<int>>(
      durum: const AsyncData([]),
      onRetry: () {},
      bosMu: (v) => v.isEmpty,
      veri: (v) {
        kuruldu++;
        return const Text('gövde');
      },
    )));
    expect(find.text('gövde'), findsNothing);
    expect(kuruldu, 0);
    expect(find.byType(ErrorCard), findsNothing,
        reason: 'boş veri hata değildir');
  });

  testWidgets('aşağı çekme tazelemesinde iskelet FLAŞLAMAZ', (tester) async {
    // Gerçek sağlayıcı üzerinden: `container.refresh` eldeki veriyi taşıyan
    // bir AsyncLoading üretir (Riverpod'un tazeleme hâli; elle kurmak
    // paketin iç API'sini ister). Veri ekranda kalmalı; iskelet gelirse
    // düzen her tazelemede zıplar.
    final cevaplar = <Completer<List<int>>>[];
    final saglayici = FutureProvider<List<int>>((ref) {
      final c = Completer<List<int>>();
      cevaplar.add(c);
      return c.future;
    });
    await tester.pumpWidget(ProviderScope(
      child: _sar(Consumer(
        builder: (context, ref, _) => _bolum(ref.watch(saglayici),
            onRetry: () => ref.invalidate(saglayici)),
      )),
    ));
    // İlk yükleme: iskelet.
    expect(find.byType(SkeletonPanel), findsOneWidget);

    cevaplar.single.complete([1, 2]);
    await tester.pump();
    expect(find.text('veri:2'), findsOneWidget);

    final kap = ProviderScope.containerOf(tester.element(find.byType(Consumer)));
    kap.refresh(saglayici);
    await tester.pump();
    expect(cevaplar.length, 2, reason: 'tazeleme yeni bir istek açar');
    expect(find.text('veri:2'), findsOneWidget,
        reason: 'eldeki veri yeni veri gelene kadar ekranda kalır');
    expect(find.byType(SkeletonPanel), findsNothing);

    cevaplar.last.complete([1, 2, 3]);
    // Ölçüldü: tazeleme sonrası cevap mikro görevle DEĞİL sıfır süreli
    // bir zamanlayıcıyla yayılıyor; süresiz `pump` onu görmüyor.
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('veri:3'), findsOneWidget);
  });

  testWidgets('hata kartı 320 dp × 1,3 ölçekte taşmaz', (tester) async {
    await darEkranda(
        tester,
        _bolum(AsyncError(StateError('x'), StackTrace.empty),
            ekranKodu: 'sky'));
    tasmaYok(tester);
  });
}

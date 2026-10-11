// Konu listesi üç hâl bekçileri (D6): iskelet / hata+tekrar / satır.
//
// Ölçülen kusur: hata kartında "Tekrar dene" YOKTU. `conversationsProvider`
// bir akış sağlayıcısı; Firestore dinleyicisi bir kez düşünce kendiliğinden
// yeniden bağlanmıyor ve kullanıcı ekranı kapatıp açmadan konularına
// ulaşamıyordu. Satır da kendi `GlassPanel+Row`uydu: başlık tek satıra
// kırpılıp ellipsis alıyordu — konu başlığının ayırt edici kısmı sondadır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/conversations.dart';
import 'package:rytho/features/chat/conversation_list_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/common.dart' show ErrorCard;
import 'package:rytho/widgets/glass.dart' show SkeletonList, SkeletonPanel;
import 'package:rytho/widgets/liste_satiri.dart';

import 'dar_ekran_test.dart' show darEkranda, tasmaYok;

Conversation _konu(String id, {String? baslik}) => Conversation(
      id: id,
      title: baslik ?? 'Konu $id',
      updatedAt: DateTime(2026, 9, 13, 10),
    );

Widget _ekran(Stream<List<Conversation>> Function(Ref) akis) => ProviderScope(
      overrides: [conversationsProvider.overrideWith(akis)],
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildRythoTheme(),
        // Yıldız alanı ve kademeli giriş SÜREKLİ animatör; ölçülen şey
        // yerleşim.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const ConversationListScreen(),
      ),
    );

Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('yüklenirken tek iskelet bileşeni, dört satır', (tester) async {
    // Hiç değer vermeyen akış: sağlayıcı `loading`de kalır.
    final kontrol = StreamController<List<Conversation>>();
    addTearDown(kontrol.close);
    await tester.pumpWidget(_ekran((_) => kontrol.stream));
    await _bekle(tester);

    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byType(SkeletonPanel), findsNWidgets(4));
  });

  testWidgets('hata → ErrorCard + Tekrar dene akışı YENİDEN kurar',
      (tester) async {
    var kurulum = 0;
    await tester.pumpWidget(_ekran((_) {
      kurulum++;
      return Stream<List<Conversation>>.error(StateError('firestore düştü'));
    }));
    await _bekle(tester);

    final kart = find.byType(ErrorCard);
    expect(kart, findsOneWidget);
    expect(tester.widget<ErrorCard>(kart).onRetry, isNotNull,
        reason: 'akış sağlayıcısı kendiliğinden yeniden bağlanmaz; '
            'tek çıkış elle tazeleme');
    expect(kurulum, 1);

    await tester.tap(find.text('Tekrar dene'));
    await _bekle(tester);
    expect(kurulum, 2, reason: 'Tekrar dene sağlayıcıyı tazelemedi');
  });

  testWidgets('satır ListeSatiri: başlık iki satır, ellipsis YOK',
      (tester) async {
    await tester.pumpWidget(
        _ekran((_) => Stream.value([_konu('a'), _konu('b')])));
    await _bekle(tester);

    expect(find.byType(ListeSatiri), findsNWidgets(2));
    final baslik = tester.widget<Text>(find.text('Konu a'));
    expect(baslik.maxLines, 2);
    expect(baslik.overflow, isNot(TextOverflow.ellipsis),
        reason: 'konu başlığının ayırt edici kısmı sondadır; "…" onu keser');
    // Tarih alt satırda.
    expect(find.textContaining('13 Eyl'), findsNWidgets(2));
  });

  testWidgets('uzun başlık 320 dp × 1,3 yazı ölçeğinde taşmaz, sarar',
      (tester) async {
    const uzun = 'Mars karşıtlığı ve iş görüşmemdeki gerginlik hakkında';
    await darEkranda(
      tester,
      SizedBox(
        height: 640,
        child: ProviderScope(
          overrides: [
            conversationsProvider.overrideWith(
                (ref) => Stream.value([_konu('a', baslik: uzun)])),
          ],
          child: const ConversationListScreen(),
        ),
      ),
      olcek: kMaxTextScale,
    );
    await _bekle(tester);

    tasmaYok(tester, neden: 'konu satırı dar ekranda taşıyor');
    expect(find.text(uzun), findsOneWidget);
  });
}

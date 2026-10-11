// Arkadaş çıkarma / engelleme ONAYLI (D6).
//
// Ölçülen kusur: güvenlik menüsündeki "Arkadaşlıktan çıkar" ve "Engelle"
// tek dokunuşla iki tarafın kenarını siliyordu — geri dönüşü olmayan
// eylem, onay sorusu olmadan. Artık menü yalnız SEÇİMİ döndürür, eylem
// sayfa kapandıktan sonra `onayla` kapısından geçer; vazgeçince hiçbir
// şey olmaz (Firestore'a dokunulmaz — bu test tam da o yüzden
// koşabiliyor: onay verilseydi `removeFriend` gerçek veritabanı isterdi).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/friends.dart';
import 'package:rytho/features/friends/friends_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;

import 'cevrem_harness.dart';

final _tr = AppLocalizationsTr();

const _arkadas = Friend(
    uid: 'u1', status: FriendStatus.accepted, displayName: 'Zeynep');

/// Düğmeye basınca menüyü açan ve dönüşünü kaydeden kök.
class _Kok extends StatefulWidget {
  const _Kok();

  @override
  State<_Kok> createState() => _KokState();
}

class _KokState extends State<_Kok> {
  bool? sonuc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final s = await showFriendSafetySheet(context, _arkadas);
            setState(() => sonuc = s);
          },
          child: const Text('menü'),
        ),
      ),
    );
  }
}

Future<void> _menuyuAc(WidgetTester tester) async {
  await tester.pumpWidget(sar(const _Kok()));
  await tester.tap(find.text('menü'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('çıkarma: menü seçimi onay sorar; vazgeçince false döner',
      (tester) async {
    await _menuyuAc(tester);
    expect(find.text(_tr.removeFriend), findsOneWidget);

    await tester.tap(find.text(_tr.removeFriend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Onay diyaloğu: gövde arkadaşın adını taşır, onay düğmesi yıkıcı
    // (madder GoldButton) — iki düğme aynı ağırlıkta olamaz.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(_tr.removeFriendConfirmBody('Zeynep')), findsOneWidget);
    expect(find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(GoldButton)),
        findsOneWidget);
    final onay = tester.widget<GoldButton>(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(GoldButton)));
    expect(onay.destructive, isTrue);

    await tester.tap(find.text(_tr.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
    final kok = tester.state<_KokState>(find.byType(_Kok));
    expect(kok.sonuc, isFalse, reason: 'vazgeçiş arkadaşı çıkarmış sayıldı');
  });

  testWidgets('engelleme: aynı kapı, kendi cümlesiyle', (tester) async {
    await _menuyuAc(tester);
    await tester.tap(find.text(_tr.blockUser));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(_tr.blockUserConfirmBody('Zeynep')), findsOneWidget);

    await tester.tap(find.text(_tr.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.state<_KokState>(find.byType(_Kok)).sonuc, isFalse);
  });

  testWidgets('menüyü dışarı dokunarak kapatmak hiçbir eylem değildir',
      (tester) async {
    await _menuyuAc(tester);
    // Sayfanın dışına dokun (üst boşluk).
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.state<_KokState>(find.byType(_Kok)).sonuc, isFalse);
  });

  testWidgets('kartsız arkadaş menüde dilin yedek adıyla anılır',
      (tester) async {
    // Kart yoksa `Friend.ad` l10n yedeğini verir (`'Gezgin'` artık modelde
    // değil); onay gövdesi o adı taşır.
    late AppLocalizations l10n;
    await tester.pumpWidget(sar(Builder(builder: (c) {
      l10n = AppLocalizations.of(c);
      return const SizedBox();
    })));
    const kartsiz = Friend(uid: 'u2', status: FriendStatus.accepted);
    expect(kartsiz.ad(l10n), l10n.defaultUserName);
    expect(kartsiz.name, isEmpty,
        reason: 'veri katmanı yedek sözcük taşımaz — çeviri işi');
  });
}

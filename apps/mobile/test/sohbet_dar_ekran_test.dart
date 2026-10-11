// Sohbet ekranı 320 dp × 1,3 yazı ölçeği taşma bekçisi (D6).
//
// `ChatScreen` konu kimliği OLMADAN monte edilir: `_seed` yalnız var olan
// konu açılırken `FirebaseAuth`a dokunuyor; boş ekran + öneri bandı + giriş
// satırı Firebase'siz çizilir. Bakiye çipi `walletProvider`ı okur — "—"
// hâliyle (bilinmiyor) sağlanır. Balon ve hata satırı ayrıca ölçülür:
// bunlar ağ ister, ekran içinde üretilemez.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/chat/chat_screen.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/widgets/common.dart' show ErrorCard;
import 'package:rytho/widgets/token_chip.dart';

import 'dar_ekran_test.dart' show darEkranda, tasmaYok;

Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('boş sohbet ekranı taşmaz; çip TokenChip', (tester) async {
    await darEkranda(
      tester,
      SizedBox(
        height: 640,
        child: ProviderScope(
          overrides: [
            walletProvider.overrideWith((_) async => WalletStatus.unknown),
          ],
          child: const ChatScreen(),
        ),
      ),
      olcek: kMaxTextScale,
    );
    await _bekle(tester);

    tasmaYok(tester, neden: 'sohbet boş durumu dar ekranda taşıyor');
    expect(find.byType(TokenChip), findsOneWidget);
    expect(find.text('—'), findsOneWidget,
        reason: 'okunamayan bakiye sıfır değil');
    // AppBar başlığı + boş durum başlığı: ikisi de `chatTitle`, literal yok.
    expect(find.text('Rytho AI'), findsNWidgets(2));
  });

  testWidgets('uzun Rytho balonu ve kullanıcı balonu taşmaz', (tester) async {
    await darEkranda(
      tester,
      const Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SohbetBalonu(
            text: '## Bugün\n\nMars **karşıtlığı** iş görüşmendeki '
                'gerginliği büyütebilir; nefesini say.\n\n- sabah sakin\n'
                '- öğleden sonra kararlı',
            mine: false,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: SohbetBalonu(
            text: 'Bugünkü iş görüşmemde nasıl davranmalıyım sence?',
            mine: true,
          ),
        ),
      ]),
      olcek: kMaxTextScale,
    );
    tasmaYok(tester, neden: 'balon dar ekranda taşıyor');
  });

  testWidgets('hata satırı (ErrorCard) uzun metinle taşmaz', (tester) async {
    await darEkranda(
      tester,
      ErrorCard(
        message: 'Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.',
        onRetry: () {},
        reportable: false,
      ),
      olcek: kMaxTextScale,
    );
    tasmaYok(tester, neden: 'hata satırı dar ekranda taşıyor');
    expect(find.text('Tekrar dene'), findsOneWidget);
  });
}

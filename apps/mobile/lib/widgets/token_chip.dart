/// Jeton bakiye hapı (U1) — ekonominin kalıcı göstergesi.
///
/// Duolingo'nun mücevher sayacı modeli: bakiye ana ekranda her an
/// görünür, dokununca yönetim ekranı (Abonelik ve Jetonlar) açılır.
/// Sohbetin AppBar çipiyle aynı görsel dil; buradaki fark kalıcı bir
/// giriş noktası olması. Bakiye 0'ken de GÖRÜNÜR — kaybolan sayaç,
/// bittiğini en çok bilmesi gereken anda kullanıcıyı bilgisiz bırakır.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/wallet.dart';
import '../features/profile/subscription_screen.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'nebula_widgets.dart';

class TokenChip extends ConsumerWidget {
  const TokenChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuzdan = ref.watch(walletProvider).value ?? WalletStatus.none;
    return Pressable(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const SubscriptionScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: RythoColors.inkLight,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: RythoColors.glassStroke),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('🪙', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          // Bakiye değişince yumuşak geçiş (satın alma anı görülsün).
          AnimatedSwitcher(
            duration: RythoMotion.base,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            // Okunamadıysa sayı yerine "—": sıfır yazmak "jetonun bitti"
            // demektir ve kullanıcı dolu cüzdanla mağazaya gider.
            child: Text(cuzdan.bilinmiyor ? '—' : '${cuzdan.total}',
                key: ValueKey(cuzdan.bilinmiyor ? -1 : cuzdan.total),
                style: RythoText.mono(12.5,
                    color: RythoColors.goldBright)),
          ),
        ]),
      ),
    );
  }
}

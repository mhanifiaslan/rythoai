/// Jeton bakiye hapı (U1) — ekonominin TEK kalıcı göstergesi.
///
/// Duolingo'nun mücevher sayacı modeli: bakiye ana ekranda her an görünür,
/// dokununca mağaza açılır. Bakiye 0'ken de GÖRÜNÜR — kaybolan sayaç,
/// bittiğini en çok bilmesi gereken anda kullanıcıyı bilgisiz bırakır.
///
/// ## Neden tek çip
/// Ölçüldü (2026-10-10): sohbetin AppBar'ında ikinci bir çip vardı ve iki
/// çip üç yerde ayrışmıştı — simge (🪙 / ✦), hedef (abonelik ekranı /
/// mağaza), düşük bakiye eşiği (yok / elle 30). Bu dosya tek çip; sohbetteki
/// kalkıyor (D6).
///
/// ## Simge neden emoji değil
/// `🪙` üç anlamda kullanılıyordu: kredi (bu çip), İ Ching (karo ve kilit
/// kartı) ve finans teması. Aynı resim üç şey derse hiçbirini demez; kredi
/// dili `toll_rounded` ikonuyla konuşur (`BedelRozeti` de aynısını çizer).
///
/// ## Üç hâl
/// * Yükleniyor → iskelet hap. "0" ASLA: sıfır "jetonun bitti" demek, 198
///   jetonlu kullanıcı yüklenme anında mağazaya yönlenirdi (B10 dersi).
/// * Okunamadı (`bilinmiyor`) → "—", düşük bakiye rengi YOK.
/// * Okundu → sayı; `dusuk` ise bakır (hakkın %10'u, `WalletStatus.dusuk`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/wallet.dart';
import '../features/paywall/token_store_screen.dart';
import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'fade_through_route.dart';
import 'glass.dart' show SkeletonPanel;
import 'motion.dart';
import 'nebula_widgets.dart';

/// Hap yüksekliği — iskelet ve dolu hâl AYNI kutuyu kaplar; yüklenme
/// bitince başlık satırı zıplamaz.
const double _kYukseklik = 32;

/// İskelet genişliği: "100 kredi" tipik metninin kapladığı yer.
const double _kIskeletGenislik = 64;

class TokenChip extends ConsumerWidget {
  const TokenChip({super.key, this.compact = false});

  /// Yalnız sayı, birim sözcüğü yok (dar başlıklar).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `.value`: tazeleme turunda (harcama sonrası sayaç artınca) önceki
    // cüzdan korunur — her mesajdan sonra iskelete düşen bir hap, sohbeti
    // yanıp sönen bir sayaca çevirirdi.
    final cuzdan = ref.watch(walletProvider).value;
    if (cuzdan == null) return _iskelet();

    final l10n = AppLocalizations.of(context);
    final metin = cuzdan.bilinmiyor
        ? cuzdan.bakiyeYazisi(cuzdan.total)
        : compact
            ? '${cuzdan.total}'
            : l10n.tokenBalanceChip(cuzdan.total);
    final renk = cuzdan.dusuk ? RythoColors.copper : RythoColors.goldBright;

    // Semantik düğüm `Pressable`dan (D7): dıştan sarılan
    // `Semantics(excludeSemantics: true)` içerideki düğmenin dokunma
    // eylemini de atıyordu — ekran okuyucu etiketi duyuyor ama "çift
    // dokun" diyemiyordu (takvim şeridinde ölçüldü, `hasTapAction`).
    // İçerik `ExcludeSemantics` ile susturulur, etiket tek düğümde kalır.
    return Pressable(
      semanticLabel: cuzdan.bilinmiyor
          ? cuzdan.bakiyeYazisi(cuzdan.total)
          : l10n.tokenBalanceChip(cuzdan.total),
      // Hedef TEK: mağaza. Abonelik ekranı profilden; bakiyeyi gören
      // kullanıcının ilk ihtiyacı doldurmak, abonelik yönetmek değil.
      onTap: () => Navigator.of(context).push(
          FadeThroughRoute(builder: (_) => const TokenStoreScreen())),
      child: ExcludeSemantics(
        child: Container(
          height: _kYukseklik,
          padding: const EdgeInsets.symmetric(horizontal: RythoSpace.md),
          decoration: BoxDecoration(
            color: RythoColors.inkLight,
            borderRadius: BorderRadius.circular(RythoRadius.pill),
            border: Border.all(color: RythoColors.glassStroke),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.toll_rounded,
                size: 13, color: RythoColors.goldBright),
            const SizedBox(width: RythoSpace.xs),
            // Bakiye değişince yumuşak geçiş (satın alma anı görülsün).
            AnimatedSwitcher(
              duration: kapili(context, RythoMotion.base),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Text(metin,
                  key: ValueKey(cuzdan.bilinmiyor ? -1 : cuzdan.total),
                  style: RythoType.dataSmall.copyWith(color: renk)),
            ),
          ]),
        ),
      ),
    );
  }

  /// Yüklenirken hap boyutunda iskelet — sayı yok, simge yok.
  Widget _iskelet() => const SizedBox(
        width: _kIskeletGenislik,
        height: _kYukseklik,
        child: SkeletonPanel(height: _kYukseklik, margin: EdgeInsets.zero),
      );
}

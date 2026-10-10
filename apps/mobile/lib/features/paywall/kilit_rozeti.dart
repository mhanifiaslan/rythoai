/// Altın kilit rozeti — Plus kilidinin TEK görünümü.
///
/// ## Neden var
/// Ölçüldü (2026-10-10): kilit üç ayrı biçimde çiziliyordu — `PlusLockedCard`
/// altın diskli `lock_rounded` 14 + tek atış shimmer; Atlas karosu çıplak
/// `lock_rounded` 13 soluk gri; kilit kartının başında da varsayılan `🔒`
/// emojisi. Aynı anlam üç dilde konuşunca göz "bu da kilit mi" diye durur.
/// Rozet burada tek yerde; kullanım yeri yalnız boyutu seçer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/motion.dart';

class KilitRozeti extends StatelessWidget {
  const KilitRozeti({
    super.key,
    this.size = 14,
    this.animate = true,
    this.kucuk = false,
  });

  /// İkon boyutu; [kucuk] açıkken yok sayılır.
  final double size;

  /// Girişte bir kez parlasın mı (tek atış ölçek + shimmer). Sürekli döngü
  /// BİLEREK yok: beş kullanım yerinde aynı anda nefes alan rozet ekranı
  /// ucuzlatır. `reduceMotion` açıkken zaten kurulmaz.
  final bool animate;

  /// Karo köşesi için 12 px, animasyonsuz. Küçük rozetin parlaması dört
  /// karoda aynı anda dört kıvılcım demek — dikkat dağıtır, bilgi katmaz.
  final bool kucuk;

  @override
  Widget build(BuildContext context) {
    final boyut = kucuk ? 12.0 : size;
    final Widget disk = Container(
      padding: const EdgeInsets.all(RythoSpace.xs),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: RythoColors.gold.withValues(alpha: 0.12),
      ),
      child:
          Icon(Icons.lock_rounded, size: boyut, color: RythoColors.goldBright),
    );
    if (!animate || kucuk || reduceMotion(context)) return disk;
    return disk
        .animate()
        .scale(
            begin: const Offset(0.7, 0.7),
            end: const Offset(1, 1),
            duration: RythoMotion.celebrate,
            curve: RythoMotion.pop)
        .then()
        // Parıltı `slower` (600 ms): eski 800 ms'nin adlandırılmış karşılığı
        // yok; tören süresi ona en yakın token.
        .shimmer(
            duration: RythoMotion.slower,
            color: RythoColors.goldBright.withValues(alpha: 0.35));
  }
}

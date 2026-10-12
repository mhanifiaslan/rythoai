/// 429 bekleme notu — sunucunun söylediği süre bitene kadar geri sayar.
///
/// ## Neden var
/// `core/api.dart` 429'un `Retry-After`ını [kotaBeklemeProvider]a yazıyordu
/// ama hiçbir yüzey okumuyordu: kullanıcı hatayı SnackBar'da bir kez görüp
/// sonra kör dövüşüyordu — her denemesi yeni bir 429, yani kotayı kendi
/// besliyordu. Bu not sunucunun söylediği süreyi ekranda tutar ve süre
/// dolunca KENDİ KENDİNE kalkar.
///
/// Süre UYDURULMAZ: başlıksız 429'da sağlayıcı `null` kalır ve not hiç
/// çizilmez (`friendlyError` o hâlde genel cümleyi söyler).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart' show kotaBeklemeProvider;
import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';

/// Kalan saniye — ya da `null` (bekleme yok / dolmuş).
///
/// Saf; `simdi` dışarıdan gelir ki testte saat ilerletilebilsin. Dolmuş
/// bekleme `null`: "0 sn sonra tekrar dene" diye bir not olmaz.
int? kotaKalanSaniye(DateTime? bitis, DateTime simdi) {
  if (bitis == null) return null;
  final kalan = bitis.difference(simdi).inSeconds;
  return kalan > 0 ? kalan : null;
}

class KotaBeklemeNotu extends ConsumerStatefulWidget {
  const KotaBeklemeNotu({super.key});

  @override
  ConsumerState<KotaBeklemeNotu> createState() => _KotaBeklemeNotuState();
}

class _KotaBeklemeNotuState extends ConsumerState<KotaBeklemeNotu> {
  Timer? _sayac;

  @override
  void dispose() {
    _sayac?.cancel();
    super.dispose();
  }

  /// Saniyede bir yeniden çizim — yalnız bekleme VARKEN; sayaç süre dolunca
  /// kendini kapatır (boşta çalışan periyodik zamanlayıcı bırakılmaz).
  void _sayacKur(bool gerekli) {
    if (gerekli && _sayac == null) {
      _sayac = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!gerekli && _sayac != null) {
      _sayac!.cancel();
      _sayac = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kalan =
        kotaKalanSaniye(ref.watch(kotaBeklemeProvider), DateTime.now());
    _sayacKur(kalan != null);
    if (kalan == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          RythoSpace.lg, 0, RythoSpace.lg, RythoSpace.xs),
      child: Text(
        l10n.retryAfterSeconds(kalan),
        style: RythoType.caption.copyWith(color: RythoColors.copper),
        textAlign: TextAlign.center,
      ),
    );
  }
}

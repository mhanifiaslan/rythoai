import 'package:flutter/material.dart';

import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/glass.dart';
import '../../widgets/nebula_widgets.dart' show Pressable;
import 'kilit_rozeti.dart';
import 'ozellik_katalogu.dart';
import 'paywall_acilis.dart';

/// Rytho+ kilitli içerik kartı.
///
/// Kilitli bir ekrana girildiğinde ücretli uca istek ATILMAZ; onun yerine bu
/// kart gösterilir ve paywall ancak kullanıcı dokununca açılır. Sunucudan 402
/// dönüp paywall'ın kendiliğinden açılması, kullanıcının o ekrana her
/// girişinde yüzüne satış ekranı fırlatmak demek olurdu.
class PlusLockedCard extends StatelessWidget {
  const PlusLockedCard({
    super.key,
    required this.title,
    required this.description,
    this.ozellik,
    this.emoji,
    this.centered = false,
  }) : assert(ozellik != null || emoji != null,
            'kilit kartı emojisini katalogdan ya da çağırandan alır; '
            'varsayılan kilit emojisi kalktı — kilit anlamını rozet taşıyor');

  final String title;
  final String description;

  /// Katalog üyesi: emoji buradan, paywall'a da hangi özellikten gelindiği
  /// bu üyeyle taşınır. Verilmezse [emoji] zorunlu.
  final PlusOzellik? ozellik;

  /// Katalog dışı emoji — [ozellik] verilmeyen çağrı yerleri için köprü.
  /// Eski varsayılan `🔒` BİLEREK yok: kart zaten altın kilit rozeti
  /// taşıyor, başta ikinci bir kilit aynı şeyi iki dilde söylüyordu
  /// (`KilitRozeti` gerekçesi).
  final String? emoji;

  /// Tüm ekranı kaplayan boş durumlarda ortalanır (Atlas, BaZi gibi).
  final bool centered;

  @override
  Widget build(BuildContext context) {
    // Pressable (R12-C3): dokununca ölçek + haptik — kilitli kart artık
    // "basılabilir" hissettiriyor. Rota türünü `acPaywall` seçer: bu bir
    // DOKUNUŞ, fade-through (R12-B2).
    final card = Pressable(
      onTap: () => acPaywall(context,
          kaynak: PaywallKaynak.kilitKarti, ozellik: ozellik),
      child: GlassPanel(
        child: Row(children: [
          Text(emoji ?? ozellik!.emoji, style: RythoText.emoji(20)),
          const SizedBox(width: RythoSpace.md),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: RythoType.cardTitle),
              const SizedBox(height: RythoSpace.xs),
              Text(description, style: RythoType.caption),
            ]),
          ),
          // Tek atış parıltı (R12-C3): girişte bir kez; sürekli döngü
          // bilerek yok (`KilitRozeti.animate`).
          const KilitRozeti(),
          const SizedBox(width: RythoSpace.xs),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: RythoColors.parchmentDim),
        ]),
      ),
    );

    if (!centered) return card;
    return Center(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [card]),
      ),
    );
  }
}

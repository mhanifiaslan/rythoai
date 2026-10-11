import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/api.dart';
import '../../core/friends.dart';
import '../../core/sound.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../widgets/nebula_widgets.dart' show Pressable;
import 'friend_detail_screen.dart' show reactionLabel;

/// Tepki alt-sayfası (R3-4): arkadaş satırından KART AÇILMADAN tepki.
///
/// Cihaz bulgusu: "tepki göndermek için illaki kartı açmak gerekmesin."
/// Sayfa kapalı kümedeki tepkileri ızgarada gösterir; seçim ANINDA
/// gönderilir (iyimser his: ses dokunuşta, ağ turu arkada — friend_detail
/// _react akışıyla aynı ilke). Firestore yazımı + push tetiği ayrı ayrı:
/// push düşse bile tepki arkadaşın gelen kutusunda görünür.
Future<void> showReactionSheet(
    BuildContext context, WidgetRef ref, Friend friend) {
  final l10n = AppLocalizations.of(context);
  final dio = ref.read(apiProvider);
  final messenger = ScaffoldMessenger.of(context);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: RythoColors.inkLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(color: RythoColors.glassStroke),
    ),
    builder: (sheetContext) => SafeArea(
      // Alt sayfanın tavanı ekranın 9/16'sı; büyük yazı ölçeğinde tepki
      // çipleri birkaç satıra yayılınca içerik bu tavanı aşıyor ve DİKEY
      // taşma oluyordu (bekçi: test/dar_ekran_ekranlar_test.dart).
      // `SingleChildScrollView`: sığmayan kısım kaydırılır, kırpılmaz.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: RythoColors.glassStroke,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // `friend.name` kartsız arkadaşta BOŞ döner (D6: 'Gezgin' modelden
          // çıktı, yedek sözcük l10n'de) — başlık yedekli adla kurulur.
          Text(l10n.reactionSheetTitle(friend.ad(l10n)),
              style: RythoText.display(15, w: FontWeight.w600)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final entry in kReactions.entries)
                Pressable(
                  onTap: () {
                    // Sayfa hemen kapanır, his dokunuşta; gönderim arkada.
                    SoundFx.like();
                    Navigator.of(sheetContext).pop();
                    _gonder(dio, messenger, l10n, friend, entry.key);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: RythoColors.glassFill,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: RythoColors.glassStroke),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(entry.value,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      // Tepki adı dile bağlı ve esnemiyordu; çip `Wrap`
                      // içinde gevşek kısıt aldığından uzun adda kendi
                      // satırından taşıyordu.
                      Flexible(
                        child: Text(reactionLabel(l10n, entry.key),
                            style: RythoText.body(12.5)),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ]),
        ),
      ),
    ),
  );
}

Future<void> _gonder(Dio dio, ScaffoldMessengerState messenger,
    AppLocalizations l10n, Friend friend, String key) async {
  try {
    await sendReaction(friend.uid, key);
    Analytics.reactionSent(key);
    await notifyReaction(dio, friend.uid, key);
    messenger.showSnackBar(
        SnackBar(content: Text(l10n.reactionSent(kReactions[key]!))));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, l10n))));
  }
}

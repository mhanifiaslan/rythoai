/// Konu listesi — sohbetin yeni giriş kapısı (Revize R4).
///
/// Kullanıcının isteği birebir: "mesajlar konu konu en yeniden eskiye göre
/// sıralanmalı, kaldığı yerden devam edebilmeli veyahut yeni bir konu ile
/// yeni mesajlaşmalar yapılabilmeli." Karta dokun → kaldığı yerden;
/// "+" → yeni konu. Konu 30 gün kullanılmazsa sunucu temizler.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart' show apiProvider, friendlyError;
import '../../core/conversations.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/liste_satiri.dart';
import '../../widgets/motion.dart';
import 'chat_screen.dart';

/// FAB'ın liste üzerinde kapladığı dikey alan.
///
/// Düğme yüksekliği (dokunma hedefi tabanı) + `Scaffold`'un FAB kenar payı
/// + bir nefes. Liste alt boşluğuna EKLENİR: son kart düğmenin altında
/// kalırsa kullanıcı o konuya hiç dokunamaz.
const double _fabAlani =
    kMinInteractiveDimension + RythoSpace.xl + RythoSpace.lg;

class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  void _ac(BuildContext context, {String? conversationId}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(conversationId: conversationId),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final konular = ref.watch(conversationsProvider);

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.chatTitle)),
      // Yeni konu eylemi sağ üstten ALT-SAĞA indi (cihaz bulgusu: sağ üst
      // köşedeki ikona uzanmak için telefonu ikinci ele almak gerekiyordu).
      // Sağ üstteki ikon KALDIRILDI, kopyalanmadı: aynı eylem iki yerde
      // dururken göz yine önce yukarıyı bulur, şikâyet sürerdi.
      //
      // Düğme YALNIZ dolu listede çıkar. Boş durumda ekranın ortasındaki
      // `GoldButton` zaten tek ve net eylem; ikisi birden aynı ekranda iki
      // birincil CTA demek olurdu.
      floatingActionButton: konular.maybeWhen<Widget?>(
        data: (liste) => liste.isEmpty
            ? null
            : YeniKonuFab(onPressed: () => _ac(context)),
        orElse: () => null,
      ),
      body: SafeArea(
        child: konular.when(
          // Satır iskeletleri (R12-B3): liste geleceği yerde liste hacmi —
          // tek iskelet bileşeni, dört eşit satır.
          loading: () => const SkeletonList(
              heights: [64, 64, 64, 64],
              padding: EdgeInsets.only(top: RythoSpace.md)),
          // Akış sağlayıcısı hatada DURUR: Firestore dinleyicisi düşünce
          // kendiliğinden yeniden bağlanmaz. Tek çıkış elle tazeleme —
          // "Tekrar dene"siz hata kartı kullanıcıyı ekranı kapatıp açmaya
          // mahkûm ediyordu.
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(RythoSpace.xl),
            child: ErrorCard(
              message: friendlyError(e, l10n),
              onRetry: () => ref.invalidate(conversationsProvider),
              screen: 'chat',
            ),
          ),
          data: (liste) => liste.isEmpty
              ? EmptyState(
                  emoji: '✦',
                  title: l10n.chatEmptyTitle,
                  description: l10n.chatEmptyBody,
                  action: GoldButton(
                    text: l10n.newConversation,
                    onPressed: () => _ac(context),
                  ),
                )
              : ListView.builder(
                  // Alt boşluk FAB'ı da hesaba katar; yoksa son satır
                  // düğmenin altında kalırdı.
                  padding: const EdgeInsets.fromLTRB(RythoSpace.lg,
                      RythoSpace.sm, RythoSpace.lg,
                      RythoSpace.xxl + _fabAlani),
                  itemCount: liste.length,
                  itemBuilder: (_, i) {
                    final konu = liste[i];
                    // Kademeli giriş (R12-C3); uzun listede stagger borcu
                    // birikmesin diye gecikme 8. satırda sabitlenir.
                    return RythoReveal(
                        index: i.clamp(0, 7),
                        child: Dismissible(
                      key: ValueKey(konu.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: RythoSpace.xl),
                        decoration: BoxDecoration(
                          color: RythoColors.madder.withValues(alpha: 0.25),
                          borderRadius:
                              BorderRadius.circular(RythoRadius.card),
                        ),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: RythoColors.madder),
                      ),
                      // Silme SUNUCUDAN; başarısızsa kart geri gelir —
                      // ekrandan kaybolup arşivde yaşamaya devam eden bir
                      // konu, "sildim sanmıştım" sürprizi doğururdu.
                      confirmDismiss: (_) async {
                        try {
                          await deleteConversation(
                              ref.read(apiProvider), konu.id);
                          return true;
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text(friendlyError(e, l10n))));
                          }
                          return false;
                        }
                      },
                      // Tek liste satırı (`ListeSatiri`): başlık iki
                      // satıra sarar, ELLIPSIS YOK — konu başlığının
                      // ayırt edici kısmı çoğu zaman sondaydı ve "…"
                      // tam onu kesiyordu.
                      child: ListeSatiri(
                        leading: Text('✦',
                            style: RythoText.glyph(18,
                                color: RythoColors.lilac)),
                        title: konu.title,
                        subtitle: konu.updatedAt != null
                            ? DateFormat(
                                    'd MMM · HH:mm',
                                    Localizations.localeOf(context)
                                        .toLanguageTag())
                                .format(konu.updatedAt!)
                            : null,
                        margin:
                            const EdgeInsets.only(bottom: RythoSpace.md),
                        onTap: () =>
                            _ac(context, conversationId: konu.id),
                      ),
                    ));
                  },
                ),
        ),
      ),
    );
  }
}

/// Alt-sağdaki genişletilmiş "yeni konu" düğmesi — başparmak bölgesi.
///
/// Uygulamanın hareket dilinde: degrade dolgu, hap biçimi, ölçülü magenta
/// parıltı, basınca 0,96 ölçek ve orta şiddette haptic (`GoldButton` /
/// `Pressable` deseninin aynısı; oradaki hafif dokunuşun bir tık üstü,
/// çünkü bu düğme bir ekran açıyor).
///
/// Material'ın `FloatingActionButton`'ı KULLANILMADI: kendi dolgusunu,
/// yükseltisini ve gölgesini tema üzerinden dayatıyor, ikisi de token
/// kümesinin dışında kalıyordu. Konumlandırmayı yine `Scaffold` yapıyor
/// (`CosmicScaffold.floatingActionButton` → `endFloat`): alt güvenli alan,
/// klavye ve SnackBar için kayma hesabı orada zaten doğru ve sağ-sol
/// yönlü dillerde kendiliğinden yer değiştiriyor.
///
/// Kaydırırken GİZLENMEZ: bu ekranda listeler kısa (sunucu 20 konu
/// döndürüyor), gizlemenin maliyeti — kullanıcının düğmeyi geri getirmek
/// için ters yöne kaydırması — faydasından büyük.
class YeniKonuFab extends StatefulWidget {
  const YeniKonuFab({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<YeniKonuFab> createState() => _YeniKonuFabState();
}

class _YeniKonuFabState extends State<YeniKonuFab> {
  bool _basili = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Reduce-motion: basma tepkisi KALIR — dokunuşun karşılığını görmek
    // bir süs değil, geri bildirim. Düşen yalnızca ara kareler: ölçek
    // anında oturur, animasyon kurulmaz.
    final sabit = reduceMotion(context);
    return Semantics(
      button: true,
      label: l10n.newConversation,
      // İçerideki `Text` ayrı bir düğüm açmasın: ekran okuyucu tek düğme
      // duyar, etiketi iki kez okumaz.
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _basili = true),
        onTapCancel: () => setState(() => _basili = false),
        onTapUp: (_) {
          setState(() => _basili = false);
          HapticFeedback.mediumImpact();
          widget.onPressed();
        },
        child: AnimatedScale(
          scale: _basili ? 0.96 : 1.0,
          duration: sabit ? Duration.zero : RythoMotion.fast,
          curve: RythoMotion.settle,
          child: Container(
            // Dokunma hedefi tabanı: yazı ölçeği küçükken bile 48 dp'nin
            // altına inmez.
            constraints:
                const BoxConstraints(minHeight: kMinInteractiveDimension),
            padding: const EdgeInsets.symmetric(
                horizontal: RythoSpace.xl, vertical: RythoSpace.md),
            decoration: BoxDecoration(
              gradient: RythoColors.primaryGradient,
              borderRadius: BorderRadius.circular(RythoRadius.pill),
              border: Border.all(color: RythoColors.glassStroke),
              boxShadow: const [
                BoxShadow(
                    color: RythoColors.magentaGlow,
                    blurRadius: 22,
                    spreadRadius: -4),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_rounded,
                  size: 20, color: RythoColors.parchment),
              const SizedBox(width: RythoSpace.sm),
              // Etiket esner: 320 dp × 1,3 yazı ölçeğinde sarar, taşmaz.
              Flexible(
                child: Text(l10n.newConversation, style: RythoType.button),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

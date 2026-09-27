/// Token mağazası — üç paket, tekrar tekrar alınabilir.
///
/// ## Paywall'dan farkı
///
/// Paywall "abone ol" der; burası "bakiyeni doldur" der. Sunucu 402'nin
/// yanında `X-Paywall-Reason: tokens` gönderirse kullanıcı BURAYA gelir:
/// abonelik sorunu yok, yalnızca token bitti — ona abonelik satmaya
/// çalışmak yanlış teşhis olurdu.
///
/// Adetler sunucu gerçeğidir (backend `TOKEN_PACKS`); bu ekran adetleri
/// bilir ama YALNIZCA göstermek için — bakiyeye ne yükleneceğine webhook
/// karar verir. Fiyat metni mağazadan gelir (para birimi/vergi yerelleşmesi
/// mağazanın işi).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/api.dart' show friendlyError;
import '../../core/purchase_errors.dart';
import '../../core/subscription.dart';
import '../../core/wallet.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';

/// Gösterim adetleri — sunucudaki `TOKEN_PACKS` ile aynı tutulmalı.
/// Yanlışsa kullanıcı yanlış vaat görür ama yanlış bakiye ALMAZ
/// (yükleme sunucuda).
const Map<String, int> kPackDisplayAmounts = {
  'rytho_tokens_small': 100,
  'rytho_tokens_medium': 300,
  'rytho_tokens_large': 1000,
};

class TokenStoreScreen extends ConsumerStatefulWidget {
  const TokenStoreScreen({super.key, this.reason});

  /// Sunucunun 402 `detail` metni — kullanıcının dilinde, olduğu gibi
  /// gösterilir.
  final String? reason;

  @override
  ConsumerState<TokenStoreScreen> createState() => _TokenStoreScreenState();
}

class _TokenStoreScreenState extends ConsumerState<TokenStoreScreen> {
  String? _busyProductId;

  Future<void> _buy(StoreProduct product) async {
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    setState(() => _busyProductId = product.identifier);
    try {
      await ref.read(krediPaketiSatinAliciProvider)(ref, product);
      if (!mounted) return;
      mesajci.showSnackBar(
          SnackBar(content: Text(l10n.tokenPurchaseDone)));
    } on PlatformException catch (e) {
      // Kullanıcının vazgeçmesi hata değil; sessiz geçilir. Diğer mağaza
      // hataları l10n'a çevrilir (ham İngilizce metin ekrana çıkmaz).
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code != PurchasesErrorCode.purchaseCancelledError && mounted) {
        if (odemeOnayBekliyor(e)) {
          // Onay bekleyen ödeme (U33) hata değil: metin kaydedilmeden
          // gösterilir. Abonelik önbelleği düşürülmez — kredi alımı onu
          // değiştirmez (bkz. odemeOnayiBekleniyor).
          odemeOnayiBekleniyor(ref, abonelik: false);
          mesajci.showSnackBar(SnackBar(content: Text(l10n.purchasePending)));
        } else {
          mesajci.showSnackBar(
              SnackBar(content: Text(storeErrorText(e, l10n))));
        }
      }
    } catch (e) {
      if (mounted) {
        mesajci.showSnackBar(SnackBar(content: Text(friendlyError(e, l10n))));
      }
    } finally {
      if (mounted) setState(() => _busyProductId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cuzdan = ref.watch(walletProvider).value ?? WalletStatus.none;
    final paketler = ref.watch(tokenPacksProvider);

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.tokenStoreTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.lg, RythoSpace.md, RythoSpace.lg, RythoSpace.xxl),
          children: [
            if (widget.reason != null && widget.reason!.isNotEmpty)
              GlassPanel(
                margin: const EdgeInsets.only(bottom: RythoSpace.md),
                child: Text(widget.reason!, style: RythoType.bodyDim),
              ),

            // Mevcut bakiye — iki kova AYRI gösterilir: hangisinin
            // devredip hangisinin yanacağını kullanıcı bilmeli.
            GlassPanel(
              glow: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.tokenBalanceLabel, style: RythoType.label),
                  const SizedBox(height: RythoSpace.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Satın alma sonrası yoklama bakiyeyi büyütür; büyük
                      // sayı yumuşak geçsin ki "kredi geldi" anı görülsün
                      // (madde 12 — süre RythoMotion'dan).
                      // 34 punto sayı + birim adı esnemiyordu: büyük yazı
                      // ölçeğinde dört haneli bakiye birimi ekran dışına
                      // itiyordu. İkisi de `Flexible` — sayı kırpılmaz.
                      Flexible(
                        child: AnimatedSwitcher(
                          duration: RythoMotion.base,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(scale: anim, child: child),
                          ),
                          child: Text('${cuzdan.total}',
                              key: ValueKey(cuzdan.total),
                              style: RythoText.display(34)),
                        ),
                      ),
                      const SizedBox(width: RythoSpace.sm),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(l10n.tokenUnit, style: RythoType.bodyDim),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RythoSpace.sm),
                  LabelValueRow(
                      label: l10n.tokenAllowanceRow,
                      value: '${cuzdan.allowance}'),
                  LabelValueRow(
                      label: l10n.tokenPurchasedRow,
                      value: '${cuzdan.purchased}'),
                  const SizedBox(height: RythoSpace.xs),
                  Text(l10n.tokenRolloverNote, style: RythoType.caption),
                ],
              ),
            ),

            SectionHeader(l10n.tokenPacksHeader),
            // Ücretsiz katman uyarısı — satın alma düğmelerinin ÜSTÜNDE.
            //
            // Kapalı test denetiminde (2026-09-14) bulundu: bu ekran
            // aboneliği hiç izlemiyordu ve alt satırdaki bedel listesi
            // ("I Ching 2 · ikili dinamik 3 · derin raporlar 5") abonelik
            // şartından tek kelime etmiyordu. Oysa o uçların HEPSİ
            // `require_plus` arkasında; ücretsiz kullanıcının krediyi
            // gerçekten harcayabildiği tek yer sohbet (`chat.py` →
            // `charge_metered`). Yani ₺419,99'luk 1000 kredilik paketi
            // alan ücretsiz kullanıcı, listede yazan her şeyde 402
            // görürdü. Kredi yanmıyor (sonradan abone olunca kullanılır)
            // ama satış anındaki vaat yanlıştı.
            const _UcretsizKatmanUyarisi(),
            paketler.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(RythoSpace.xl),
                child: Center(child: AstrolabeSpinner()),
              ),
              // Mağaza hatası artık BURAYA da düşüyor (sağlayıcı yutmuyor)
              // ve çeviri paywall'la AYNI kapıdan geçiyor: `friendlyError`
              // PlatformException'ı tanımadığı için ağ hatasında "beklenmeyen
              // sorun" diyordu, paywall doğru metni gösterirken.
              error: (e, _) => ErrorCard(
                message: magazaVeyaAgHatasi(e, l10n),
                onRetry: () => ref.invalidate(tokenPacksProvider),
              ),
              data: (urunler) => urunler.isEmpty
                  ? EmptyState(
                      emoji: '🛰️',
                      title: l10n.tokenPacksUnavailable,
                      description: l10n.tokenPacksUnavailableBody,
                    )
                  : Column(children: [
                      for (final urun in urunler)
                        _PackTile(
                          product: urun,
                          amount: kPackDisplayAmounts[urun.identifier],
                          busy: _busyProductId == urun.identifier,
                          enabled: _busyProductId == null,
                          onBuy: () => _buy(urun),
                        ),
                    ]),
            ),

            const SizedBox(height: RythoSpace.md),
            Text(l10n.tokenCostsNote, style: RythoType.caption),
          ],
        ),
      ),
    );
  }
}

/// Ücretsiz katmanda kredinin ne İŞE YARADIĞINI satın almadan ÖNCE söyler.
///
/// Abonede hiç çizilmez: onun için liste zaten doğru. Abonelik durumu
/// henüz yüklenmemişse de çizilmez — yanlış anda "abone değilsin" demek,
/// hiçbir şey dememekten kötü.
class _UcretsizKatmanUyarisi extends ConsumerWidget {
  const _UcretsizKatmanUyarisi();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final abonelik = ref.watch(subscriptionProvider).value;
    if (abonelik == null || abonelik.active) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: RythoSpace.md),
      padding: const EdgeInsets.all(RythoSpace.md),
      decoration: BoxDecoration(
        color: RythoColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(RythoRadius.md),
        border: Border.all(color: RythoColors.gold.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 18, color: RythoColors.gold),
        const SizedBox(width: RythoSpace.sm),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.tokenFreeTierWarnTitle, style: RythoText.body(13.5)),
                const SizedBox(height: 2),
                Text(l10n.tokenFreeTierWarnBody,
                    style: RythoText.body(11.5,
                        color: RythoColors.parchmentDim)),
              ]),
        ),
      ]),
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.product,
    required this.amount,
    required this.busy,
    required this.enabled,
    required this.onBuy,
  });

  final StoreProduct product;
  final int? amount;
  final bool busy;
  final bool enabled;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: RythoSpace.md),
      child: Row(children: [
        const Text('🪙', style: TextStyle(fontSize: 26)),
        const SizedBox(width: RythoSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                amount != null
                    ? l10n.tokenPackAmount(amount!)
                    : product.title,
                style: RythoType.cardTitle,
              ),
              const SizedBox(height: 2),
              Text(product.priceString, style: RythoType.dataSmall),
            ],
          ),
        ),
        SizedBox(
          width: 120,
          child: GoldButton(
            text: l10n.tokenBuy,
            busy: busy,
            onPressed: enabled ? onBuy : null,
          ),
        ),
      ]),
    );
  }
}

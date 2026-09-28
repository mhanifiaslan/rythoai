/// Abonelik ve Jetonlar ekranı (A1).
///
/// ## Neden var
///
/// Backend plan/yenileme/deneme ve tam cüzdan durumunu baştan beri
/// döndürüyordu (`/billing/status` + `/billing/wallet`) ama hiçbir ekran
/// göstermiyordu: kullanıcı "Rytho+ üyeliğim var mı, ne zaman yenilenir,
/// kaç jetonum kaldı" sorularını uygulama içinden cevaplayamıyordu.
/// TokenStoreScreen'e kalıcı bir menü girişi bile yoktu (yalnız 402
/// interceptor'ı ve sohbet çipi açıyordu). Bu ekran ikisini tek çatıda
/// toplar; profil satırından açılır.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart' show friendlyError;
import '../../core/subscription.dart';
import '../../core/wallet.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../paywall/paywall_screen.dart';
import '../paywall/token_store_screen.dart';

/// Mağazanın abonelik yönetimi sayfası. `sku` boşsa genel abonelikler
/// sayfası açılır — kullanıcıyı hiçbir durumda çıkmaz sokakta bırakmayız.
///
/// iOS'ta Apple'ın sabit adresi kullanılır: ürün kimliği ALMAZ ve App Store
/// kaydı olmadan da çalışır. Platform ayrımı olmadan bu fonksiyon iOS'ta
/// Play sayfasını açıyordu — abonelik iptali oradan İMKÂNSIZ ve bu, mağaza
/// kuralı ihlali sayılır (kullanıcı aboneliğini yönetebilmeli).
Uri storeSubscriptionUri(String? productId) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return Uri.parse('https://apps.apple.com/account/subscriptions');
  }
  const paket = 'ai.rytho';
  // Play webhook'u ürün kimliğini "urun:base_plan" biçiminde gönderebilir
  // (rytho_plus_monthly:monthly). Play'in sku parametresi base-plan eki
  // tanımaz — ':' öncesi kırpılır, yoksa "Yönet" sayfası açılmaz (M1).
  final sku = (productId ?? '').split(':').first;
  return Uri.parse(sku.isEmpty
      ? 'https://play.google.com/store/account/subscriptions'
      : 'https://play.google.com/store/account/subscriptions'
          '?sku=$sku&package=$paket');
}

/// Bilinen ürün kimliğini insan diline çevirir; bilinmeyene ham kimlik.
///
/// Kimlik listesi RevenueCat panelindeki ürünlerle elle senkron —
/// `kTokenPackIds` (wallet.dart) ile aynı disiplin.
String planDisplayName(AppLocalizations l10n, String? productId) {
  if (productId == null || productId.isEmpty) return 'Rytho+';
  final id = productId.toLowerCase();
  if (id.contains('month')) return l10n.subPlanMonthly;
  if (id.contains('year') || id.contains('annual')) return l10n.subPlanYearly;
  return productId;
}

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() =>
      _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _restoreBusy = false;

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    setState(() => _restoreBusy = true);
    try {
      final ok = await restorePurchases(ref);
      if (!mounted) return;
      mesajci.showSnackBar(SnackBar(
          content: Text(
              ok ? l10n.subRestoreDone : l10n.noActiveSubscription)));
    } on PlatformException catch (e) {
      if (mounted) {
        mesajci.showSnackBar(SnackBar(content: Text(friendlyError(e, l10n))));
      }
    } catch (e) {
      if (mounted) {
        mesajci.showSnackBar(SnackBar(content: Text(friendlyError(e, l10n))));
      }
    } finally {
      if (mounted) setState(() => _restoreBusy = false);
    }
  }

  Future<void> _manage(String? productId) async {
    // Dış tarayıcıya çıkar: Play aboneliği uygulama içinden yönetilemez,
    // mağaza kuralı gereği iptal/duraklatma oranın işi.
    await launchUrl(storeSubscriptionUri(productId),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final abonelik =
        ref.watch(subscriptionProvider).value ?? SubscriptionStatus.none;
    final cuzdan = ref.watch(walletProvider).value ?? WalletStatus.none;
    // KT3: sunucu denemesi "aktif" döner ama mağaza ürünü YOKTUR.
    // Denemedeki kullanıcı satın alma akışına ulaşabilmeli (aksi halde
    // ilk 3 gün paywall hiçbir yerden açılamıyordu) ve "Aboneliği yönet"
    // gibi Play'de karşılığı olmayan düğmeler görmemeli.
    final magazaAbonesi = abonelik.active &&
        (abonelik.productId != null && abonelik.productId!.isNotEmpty);
    final denemede = abonelik.active && !magazaAbonesi;
    final dil = Localizations.localeOf(context).toLanguageTag();
    String tarih(DateTime t) => DateFormat('d MMMM yyyy', dil).format(t);

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.subscriptionScreenTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.lg, RythoSpace.md, RythoSpace.lg, RythoSpace.xxl),
          children: [
            // ---------- PLAN KARTI ----------
            GlassPanel(
              glow: abonelik.active,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.subPlanLabel, style: RythoType.label),
                  const SizedBox(height: RythoSpace.sm),
                  Row(children: [
                    Text(abonelik.active ? '✦' : '✧',
                        style: const TextStyle(
                            fontSize: 22, color: RythoColors.goldBright)),
                    const SizedBox(width: RythoSpace.sm),
                    Expanded(
                      child: Text(
                          abonelik.active
                              ? planDisplayName(l10n, abonelik.productId)
                              : l10n.subPlanFree,
                          style: RythoText.display(22)),
                    ),
                  ]),
                  const SizedBox(height: RythoSpace.sm),
                  if (denemede) ...[
                    // Sunucu denemesi: dürüst durum satırı + satın alma
                    // yolu AÇIK (deneme, satışın önsözü — duvarı değil).
                    LabelValueRow(
                        label: l10n.subStatusLabel,
                        value: l10n.subStatusTrial),
                    const SizedBox(height: RythoSpace.xs),
                    Text(
                        (abonelik.trialDaysLeft ?? 0) <= 1
                            ? l10n.trialBannerLastDay
                            : l10n.trialBannerDays(
                                abonelik.trialDaysLeft ?? 0),
                        style: RythoType.bodyDim),
                    const SizedBox(height: RythoSpace.md),
                    GoldButton(
                      text: l10n.subGoPlus,
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const PaywallScreen(),
                              fullscreenDialog: true)),
                    ),
                  ] else if (abonelik.active) ...[
                    if (abonelik.isTrial == true)
                      LabelValueRow(
                          label: l10n.subStatusLabel,
                          value: l10n.subStatusTrial),
                    // Yenilenme/bitiş TEK satırda ve dürüst dille:
                    // otomatik yenileme kapalıysa "yenilenir" DENMEZ.
                    if (abonelik.expiresAt != null)
                      LabelValueRow(
                        label: abonelik.willRenew == false
                            ? l10n.subEndsLabel
                            : l10n.subRenewsLabel,
                        value: tarih(abonelik.expiresAt!),
                      ),
                    const SizedBox(height: RythoSpace.md),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _manage(abonelik.productId),
                          child: Text(l10n.subManage,
                              style: RythoText.body(13,
                                  color: RythoColors.parchment)),
                        ),
                      ),
                    ]),
                  ] else ...[
                    Text(l10n.subPlanFreeBody, style: RythoType.bodyDim),
                    const SizedBox(height: RythoSpace.md),
                    GoldButton(
                      text: l10n.subGoPlus,
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const PaywallScreen(),
                              fullscreenDialog: true)),
                    ),
                  ],
                  // Geri yükleme her iki durumda da görünür (mağaza kuralı;
                  // cihaz değiştiren abone "ücretsiz" görünümüne düşebilir).
                  const SizedBox(height: RythoSpace.xs),
                  Center(
                    child: TextButton(
                      onPressed: _restoreBusy ? null : _restore,
                      child: Text(l10n.restorePurchases,
                          style: RythoText.body(12.5,
                              color: RythoColors.parchmentDim)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: RythoSpace.md),

            // ---------- JETON KARTI ----------
            // Bakiye bloğu TokenStoreScreen'dekiyle aynı dil: iki kova
            // ayrı gösterilir — hangisinin devredip hangisinin dönem
            // sonunda tazeleneceğini kullanıcı bilmeli.
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.tokenBalanceLabel, style: RythoType.label),
                  const SizedBox(height: RythoSpace.sm),
                  // 34 punto bakiye + birim adı esnemiyordu: büyük yazı
                  // ölçeğinde dört haneli bakiye birimi ekran dışına
                  // itiyordu. İkisi de `Flexible` — sayı kırpılmaz.
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Flexible(
                      // Okunamadıysa "—" (WalletStatus.bilinmiyor).
                      child: Text(
                          cuzdan.bilinmiyor ? '—' : '${cuzdan.total}',
                          style: RythoText.display(34)),
                    ),
                    const SizedBox(width: RythoSpace.sm),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(l10n.tokenUnit, style: RythoType.bodyDim),
                      ),
                    ),
                  ]),
                  const SizedBox(height: RythoSpace.sm),
                  // KT3: "0/300" yalnız GERÇEK mağaza abonesinde anlamlı;
                  // denemede/ücretsizde yanıltıcı bir eksiklik gibi
                  // görünüyordu (aylık hak abonelikle gelir).
                  if (magazaAbonesi) ...[
                    LabelValueRow(
                        label: l10n.subMonthlyAllowanceRow,
                        value:
                            '${cuzdan.allowance} / ${cuzdan.monthlyAllowance}'),
                    if (cuzdan.allowanceResetsAt != null)
                      LabelValueRow(
                          label: l10n.subAllowanceResetsRow,
                          value: tarih(cuzdan.allowanceResetsAt!)),
                  ],
                  LabelValueRow(
                      label: l10n.tokenPurchasedRow,
                      value: '${cuzdan.purchased}'),
                  const SizedBox(height: RythoSpace.xs),
                  Text(l10n.tokenRolloverNote, style: RythoType.caption),
                  const SizedBox(height: RythoSpace.md),
                  GoldButton(
                    text: l10n.subBuyTokens,
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const TokenStoreScreen())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

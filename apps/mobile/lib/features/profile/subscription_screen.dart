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
///
/// ## Üç hâl (D7)
/// Durum `?? SubscriptionStatus.none` ile okunuyordu: yüklenirken ve okuma
/// DÜŞTÜĞÜNDE aboneye "Ücretsiz" diyordu — plan kartı, "Rytho+'a geç"
/// düğmesi, hepsi. Şimdi yükleniyor → iskelet, okunamadı → `ErrorCard`
/// (tazeleme elle; sağlayıcı auto-dispose değil, ekranı kapatıp açmak
/// bayat sonucu kurtarmaz), okundu → kart.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/purchase_errors.dart' show purchaseErrorText;
import '../../core/subscription.dart';
import '../../core/wallet.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../paywall/paywall_acilis.dart';
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
  if (productId == null || productId.isEmpty) return kPlusAdi;
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
    } catch (e) {
      // Tek kapı (D7): eski hâl `friendlyError` idi ve PlatformException'ı
      // tanımadığı için mağazanın ağ hatasında "beklenmeyen sorun" diyordu.
      if (mounted) {
        mesajci.showSnackBar(SnackBar(
            content: Text(purchaseErrorText(e, l10n, abonelik: true))));
      }
    } finally {
      if (mounted) setState(() => _restoreBusy = false);
    }
  }

  Future<void> _manage(String? productId) async {
    // Dış tarayıcıya çıkar: Play aboneliği uygulama içinden yönetilemez,
    // mağaza kuralı gereği iptal/duraklatma oranın işi.
    //
    // Sonuç OKUNUR (D7): `launchUrl` açamayınca `false` döner ya da
    // fırlatır; eski hâl ikisini de yutuyordu ve düğme "basınca hiçbir
    // şey olmuyor" hissi veriyordu. Kullanıcıya yol söylenir: mağaza
    // uygulamasının kendi abonelikler sayfası.
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    var acildi = false;
    try {
      acildi = await launchUrl(storeSubscriptionUri(productId),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      acildi = false;
    }
    if (!acildi && mounted) {
      mesajci.showSnackBar(SnackBar(content: Text(l10n.subManageOpenFailed)));
    }
  }

  void _plusaGec() => acPaywall(context, kaynak: PaywallKaynak.abonelikEkrani);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final durum = ref.watch(subscriptionProvider);

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.subscriptionScreenTitle)),
      body: SafeArea(
        child: switch (durum) {
          // ÜÇ HÂL: iskelet / tazeleme yolu / kart. `isLoading` ÖNCE: tazeleme
          // turunda eski değer taşınırken de "biliniyor" sayılmaz.
          AsyncValue(isLoading: true) => const SkeletonList(),
          AsyncValue(:final value?) when !value.okunabildi => Center(
              child: ErrorCard(
                message: l10n.errorGeneric,
                onRetry: () => ref.invalidate(subscriptionProvider),
              ),
            ),
          AsyncValue(:final value?) => _govde(context, l10n, value),
          _ => Center(
              child: ErrorCard(
                message: l10n.errorGeneric,
                onRetry: () => ref.invalidate(subscriptionProvider),
              ),
            ),
        },
      ),
    );
  }

  Widget _govde(
      BuildContext context, AppLocalizations l10n, SubscriptionStatus abonelik) {
    // `.value ?? unknown` (D7): yüklenirken "0" DEĞİL "—". Eski `?? none`
    // bakiye kartında sıfır gösteriyordu — sıfır "bitti" demek.
    final cuzdan = ref.watch(walletProvider).value ?? WalletStatus.unknown;
    // KT3: sunucu denemesi "aktif" döner ama mağaza ürünü YOKTUR.
    // Denemedeki kullanıcı satın alma akışına ulaşabilmeli (aksi halde
    // ilk 3 gün paywall hiçbir yerden açılamıyordu) ve "Aboneliği yönet"
    // gibi Play'de karşılığı olmayan düğmeler görmemeli.
    final magazaAbonesi = abonelik.active &&
        (abonelik.productId != null && abonelik.productId!.isNotEmpty);
    final denemede = abonelik.active && !magazaAbonesi;
    final dil = Localizations.localeOf(context).toLanguageTag();
    String tarih(DateTime t) => DateFormat('d MMMM yyyy', dil).format(t);

    return ListView(
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
              const SizedBox(height: RythoSpace.xs),
              Row(children: [
                Text(abonelik.active ? '✦' : '✧',
                    style: RythoText.glyph(22, color: RythoColors.goldBright)),
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
                GoldButton(text: l10n.subGoPlus, onPressed: _plusaGec),
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
                // Abonede "Yönet" İKİNCİL (`filled: false`): ekranın tek
                // dolu düğmesi aşağıdaki "Kredi paketi al" — kullanıcının
                // bu ekranda yapacağı asıl iş bakiyeyi doldurmak, iptal
                // etmek değil.
                GoldButton(
                    text: l10n.subManage,
                    filled: false,
                    onPressed: () => _manage(abonelik.productId)),
              ] else ...[
                Text(l10n.subPlanFreeBody, style: RythoType.bodyDim),
                const SizedBox(height: RythoSpace.md),
                GoldButton(text: l10n.subGoPlus, onPressed: _plusaGec),
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
                  // Okunamadıysa "—" (WalletStatus.bilinmiyor); dökümün
                  // her satırı aynı işlevden geçer (`bakiyeYazisi`).
                  child: Text(cuzdan.bakiyeYazisi(cuzdan.total),
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
              // KT3: "0 / tavan" satırı yalnız GERÇEK mağaza abonesinde
              // anlamlı; denemede/ücretsizde yanıltıcı bir eksiklik gibi
              // görünüyordu (aylık hak abonelikle gelir).
              //
              // Tavan SAYISI buraya yazılmaz: `cuzdan.monthlyAllowance`
              // sunucudan gelir ve 300'den 100'e indi. Yoruma gömülen
              // sayı bir sonraki değişiklikte sessizce yanlış olur —
              // bu yorum tam o yüzden bir tur boyunca "0/300" diyordu.
              if (magazaAbonesi) ...[
                LabelValueRow(
                    label: l10n.subMonthlyAllowanceRow,
                    value: '${cuzdan.bakiyeYazisi(cuzdan.allowance)} / '
                        '${cuzdan.bakiyeYazisi(cuzdan.monthlyAllowance)}'),
                if (cuzdan.allowanceResetsAt != null)
                  LabelValueRow(
                      label: l10n.subAllowanceResetsRow,
                      value: tarih(cuzdan.allowanceResetsAt!)),
              ],
              LabelValueRow(
                  label: l10n.tokenPurchasedRow,
                  value: cuzdan.bakiyeYazisi(cuzdan.purchased)),
              const SizedBox(height: RythoSpace.xs),
              Text(l10n.tokenRolloverNote, style: RythoType.caption),
              // "Kredi paketi al" YALNIZ aboneye (K2): paketler aboneye
              // satılıyor (`token_store_screen.dart` gerekçesi); abone
              // olmayana düğme göstermek onu "paketler aboneye özel"
              // panelinden geri döndürmek olurdu. Denemede İKİNCİL
              // ağırlık: o kartın dolu düğmesi "Rytho+'a geç".
              if (abonelik.active) ...[
                const SizedBox(height: RythoSpace.md),
                GoldButton(
                  text: l10n.subBuyTokens,
                  filled: magazaAbonesi,
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const TokenStoreScreen())),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

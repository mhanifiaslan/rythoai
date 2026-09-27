import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, PlatformException;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/analytics.dart';
import '../../core/purchase_errors.dart';
import '../../core/sound.dart';
import '../../core/subscription.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart' show ErrorCard;
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';
import '../../widgets/star_burst.dart';
import '../profile/legal_page.dart';

/// RYTHO+ paywall.
///
/// Mağaza kuralları gereği bu ekranda şunlar **görünür olmak zorunda**:
/// fiyat, yenileme dönemi, denemenin ne zaman ücrete döneceği, iptalin nasıl
/// yapılacağı ve "Satın alımları geri yükle" seçeneği. Bunlar süsleme değil,
/// eksikse inceleme reddi sebebidir.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.reason});

  /// Kilitli uçtan dönen açıklama ("… Rytho+ aboneliğine dahildir").
  final String? reason;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Package? _selected;
  bool _busy = false;
  String? _error;

  /// Hata OLMAYAN mağaza cevabı — bugün yalnız onay bekleyen ödeme (U33).
  ///
  /// [_error]dan ayrı tutulur çünkü o macenta boyanıyor ve kullanıcıya
  /// "olmadı, yeniden dene" diyor; bekleyen ödemede yeniden denemek aynı
  /// ürün için ikinci bir onay isteği açar.
  String? _bilgi;

  /// Bekleyiş uzarsa çıkış yolu açılır.
  ///
  /// Mağaza çağrısı hiç dönmezse `finally` de çalışmıyor ve kullanıcı sonsuz
  /// bir dönen halkada kalıyordu — cihaz testinde bildirilen "ödeme adımını
  /// geçemiyorum" buydu. Çağrıya zaman aşımı KOYULMADI bilerek: kullanıcı o
  /// sırada mağazanın kendi ekranında şifre giriyor olabilir ve akışı yarıda
  /// kesmek daha kötü. Bunun yerine bekleyişten **çıkış** veriliyor.
  Timer? _sabirsizlik;
  bool _uzunSuruyor = false;

  static const Duration _kCikisSuresi = Duration(seconds: 10);

  void _mesguliyet(bool mesgul) {
    _sabirsizlik?.cancel();
    if (mesgul) {
      _sabirsizlik = Timer(_kCikisSuresi, () {
        if (mounted && _busy) setState(() => _uzunSuruyor = true);
      });
    }
    if (!mounted) return;
    setState(() {
      _busy = mesgul;
      if (!mesgul) _uzunSuruyor = false;
    });
  }

  @override
  void dispose() {
    _sabirsizlik?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // `reason` yalnızca kilitli bir uçtan 402 dönünce dolu gelir; boşsa
    // paywall ilk değerden sonra kendiliğinden açılmıştır. İkisini ayırmak,
    // hangi girişin dönüştüğünü ölçmenin tek yolu.
    Analytics.paywallShown(widget.reason == null ? 'intro' : 'locked');
  }

  /// Faydalar dile göre üretildiği için const olamaz.
  List<(String, String, String)> _benefits(AppLocalizations l10n) => [
        ('🌙', l10n.benefitDailyTitle, l10n.benefitDailyBody),
        ('🗺️', l10n.benefitNatalTitle, l10n.benefitNatalBody),
        ('💞', l10n.benefitDyadTitle, l10n.benefitDyadBody),
        ('💬', l10n.benefitChatTitle, l10n.benefitChatBody),
        ('🀄', l10n.benefitBaziTitle, l10n.benefitBaziBody),
      ];

  Future<void> _buy() async {
    final package = _selected;
    if (package == null) return;
    setState(() {
      _error = null;
      _bilgi = null;
    });
    _mesguliyet(true);
    // Huninin orta adimi: bu olay olmadan "paywall calismiyor" ile "magaza
    // akisi dusuyor" ayirt edilemez.
    Analytics.purchaseStarted();
    try {
      final ok = await ref.read(paketSatinAliciProvider)(ref, package);
      if (ok) Analytics.purchaseCompleted();
      if (ok && mounted) {
        await _kutla();
        if (mounted) Navigator.of(context).pop(true);
      } else if (!ok && mounted) {
        // Satın alma cihazda bitti ama beklenen yetki (entitlement)
        // müşteri kaydında görünmüyor — tipik nedeni panelde ürünün
        // yanlış/eksik entitlement'a bağlanması. Eskiden bu dal SESSİZDİ:
        // kullanıcı parayı öder, ekran tepkisiz kalırdı (M1 onarımı).
        setState(() => _error =
            AppLocalizations.of(context).purchaseEntitlementMissing);
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        // Vazgeçmek hata değil.
      } else if (odemeOnayBekliyor(e)) {
        // Ask to Buy / ek onay: hata değil, bilgi (bkz. [_bilgi]).
        if (mounted) {
          odemeOnayiBekleniyor(ref);
          setState(
              () => _bilgi = AppLocalizations.of(context).purchasePending);
        }
      } else if (code == PurchasesErrorCode.productAlreadyPurchasedError) {
        // Mağaza hesabında abonelik zaten var (tipik: sunucu kaydı henüz
        // eşitlenmemiş ya da abonelik başka app-kimliğinde). Kullanıcıyı
        // çıkmaza sokma: kendiliğinden geri yükle — abonelik hangi
        // kimlikteyse bu hesaba çekilir (G-turu, iç test bulgusu).
        if (mounted) await _restore();
      } else if (mounted) {
        setState(() => _error =
            storeErrorText(e, AppLocalizations.of(context)));
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = AppLocalizations.of(context).purchaseFailed);
      }
    } finally {
      if (mounted) _mesguliyet(false);
    }
  }

  /// Satın alma kutlaması (R12-C1): dönüşümün en pahalı anı eskiden sessiz
  /// bir ekran kapanışıydı. 1.4 saniyelik perde — yıldız patlaması + Rytho+
  /// mührü + ses + haptik; sonra ekran kapanır. Sabırsızlık çıkışına
  /// dokunulmadı: kutlama yalnız BAŞARIDA oynar.
  Future<void> _kutla() {
    SoundFx.purchase();
    HapticFeedback.mediumImpact();
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'plus-kutlama',
      barrierColor: RythoColors.ink.withValues(alpha: 0.88),
      transitionDuration: RythoMotion.base,
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (_, _, _) => const _PlusCelebration(),
    );
  }

  Future<void> _restore() async {
    setState(() => _bilgi = null);
    _mesguliyet(true);
    try {
      final ok = await ref.read(geriYukleyiciProvider)(ref);
      Analytics.purchasesRestored(found: ok);
      if (!mounted) return;
      if (ok) {
        await _kutla();
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() =>
            _error = AppLocalizations.of(context).noActiveSubscription);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() =>
            _error = storeErrorText(e, AppLocalizations.of(context)));
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = AppLocalizations.of(context).purchaseFailed);
      }
    } finally {
      if (mounted) _mesguliyet(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offerings = ref.watch(offeringsProvider);
    final l10n = AppLocalizations.of(context);

    return CosmicScaffold(
      appBar: AppBar(
        title: Text(l10n.paywallTitle),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 22),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        if (widget.reason != null)
          GlassPanel(
            child: Text(widget.reason!,
                style: RythoText.body(14, color: RythoColors.goldBright)),
          ),
        // OT6: sunucu taraflı deneme aktifse dürüst geri sayım — kullanıcı
        // "zaten her şey açıkken" neden paywall gördüğünü anlamalı (davet
        // buraya jeton mağazasından ya da geri sayım merakından gelebilir).
        Builder(builder: (context) {
          final durum = ref.watch(subscriptionProvider).value;
          final kalan = durum?.trialDaysLeft;
          if (kalan == null) return const SizedBox.shrink();
          return GlassPanel(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.trialBannerTitle,
                      style: RythoText.body(14.5, w: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      kalan <= 1
                          ? l10n.trialBannerLastDay
                          : l10n.trialBannerDays(kalan),
                      style: RythoText.body(12.5,
                          color: RythoColors.parchmentDim)),
                ]),
          );
        }),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(l10n.paywallHeadline, style: RythoText.display(26)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text(
            l10n.paywallBody,
            style: RythoText.body(13.5, color: RythoColors.parchmentDim),
          ),
        ),
        for (final (i, benefit) in _benefits(l10n).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(benefit.$1, style: const TextStyle(fontSize: 19)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(benefit.$2, style: RythoText.body(14.5, w: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(benefit.$3,
                          style: RythoText.body(12.5,
                              color: RythoColors.parchmentDim)),
                    ]),
              ),
            ]),
          )
              .animate(delay: Duration(milliseconds: 60 * i))
              .fadeIn(duration: 320.ms)
              .slideX(begin: 0.05, curve: Curves.easeOutCubic),
        const SectionDivider(),
        offerings.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: AstrolabeSpinner()),
          ),
          // Mağaza/ağ hatası artık YUTULMUYOR (bkz. core/subscription.dart
          // `offeringsProvider`): çevrilmiş metin + yeniden deneme. Tazeleme
          // ELLE isteniyor çünkü sağlayıcı auto-dispose DEĞİL — hatalı sonuç
          // oturum boyunca önbellekte kalır, ekranı kapatıp açmak kurtarmaz.
          error: (e, _) => ErrorCard(
            message: magazaVeyaAgHatasi(e, l10n),
            onRetry: () => ref.invalidate(offeringsProvider),
          ),
          data: (packages) {
            if (packages.isEmpty) return _unavailable(l10n);
            _selected ??= _defaultPackage(packages);
            // Tek plan varsa seçim yapılacak bir şey yok; radyo düğmesi
            // göstermek kullanıcıya sahte bir karar sunar.
            final tekPlan = packages.length == 1;
            return Column(children: [
              for (final package in packages)
                _PlanTile(
                  package: package,
                  selected: identical(package, _selected) ||
                      package.identifier == _selected?.identifier,
                  showRadio: !tekPlan,
                  onTap: () => setState(() => _selected = package),
                ),
            ]);
          },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(_error!,
                style: RythoText.body(12.5, color: RythoColors.magenta)),
          ),
        if (_bilgi != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(_bilgi!,
                style: RythoText.body(12.5, color: RythoColors.parchment)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: GoldButton(
            text: _selected == null
                ? l10n.paywallChoosePlan
                : l10n.paywallContinue,
            busy: _busy,
            onPressed: _selected == null ? null : _buy,
          ),
        ),
        // Bekleyiş uzarsa çıkış yolu. Sonsuz dönen bir halka, kullanıcıya
        // uygulamanın bozuk olduğunu söyler; bir düğme ise ne yapacağını.
        if (_uzunSuruyor)
          Center(
            child: TextButton(
              onPressed: () => _mesguliyet(false),
              child: Text(l10n.cancel,
                  style: RythoText.label(12.5, color: RythoColors.goldBright)),
            ),
          ),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _restore,
            child: Text(l10n.restorePurchases,
                style: RythoText.label(12, color: RythoColors.parchmentDim)),
          ),
        ),
        // Ortak kodu girişi KALDIRILDI (A2): jeton-bonusu/atıf modeli
        // şimdilik kullanılmıyor. Backend (/billing/redeem-code + admin
        // Ortaklar paneli) bilinçli olarak duruyor — ileride farklı bir
        // ödül modeli tasarlanırsa zemin hazır.
        // Mağaza kuralı: iptal ve yenileme koşulları satın alma ekranında
        // açıkça yazmalı.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Text(
            l10n.subscriptionTerms,
            style: RythoText.body(11.5, color: RythoColors.parchmentDim),
            textAlign: TextAlign.center,
          ),
        ),
        // Ne satın aldığının dürüst tarifi. Ürünün "yağcılık yok" ilkesinin
        // para istenen ekrandaki karşılığı: burada abartmak, uygulamanın
        // geri kalanındaki dürüstlüğü de değersizleştirirdi. Mağaza
        // incelemesinde de aranan ibare.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            l10n.insightDisclaimer,
            style: RythoText.body(11, color: RythoColors.parchmentDim),
            textAlign: TextAlign.center,
          ),
        ),
        // Yasal bağlantı satırı esnemeyen bir `Row`du: "Kullanım Şartları
        // · Gizlilik Politikası" dar ekranda tek satıra sığmıyor, sağ uç
        // kırpılıyordu. `Wrap` sığmayanı ortalı biçimde alt satıra indirir.
        // ⚠️ `Wrap` gevşek kısıtta büzülür; ortalama için tam genişlik.
        SizedBox(
            width: double.infinity,
            child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LegalPage(
                    title: l10n.termsOfUse,
                    sections: termsOfUseSections(
                        Localizations.localeOf(context).languageCode)))),
            child: Text(l10n.termsOfUse, style: RythoText.label(11)),
          ),
          Text('·', style: RythoText.label(11, color: RythoColors.parchmentDim)),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LegalPage(
                    title: l10n.privacyPolicy,
                    sections: privacyPolicySections(
                        Localizations.localeOf(context).languageCode)))),
            child: Text(l10n.privacyPolicy, style: RythoText.label(11)),
          ),
        ])),
      ]),
    );
  }

  /// Varsayılan seçili paket.
  ///
  /// Kapsam kararı: **yalnızca aylık sunuluyor** (bkz. core/subscription.dart,
  /// kOfferedPackageTypes). Yıllığı tercih eden eski mantık kaldırıldı —
  /// sunulmayan bir paketi varsayılan seçmeye çalışıyordu.
  Package _defaultPackage(List<Package> packages) {
    for (final package in packages) {
      if (package.packageType == PackageType.monthly) return package;
    }
    return packages.first;
  }

  /// Mağaza sorunsuz yanıtladı ama gösterilecek paket YOK.
  ///
  /// Hata metni buraya artık GİRMEZ: mağaza/ağ hatası `error:` dalına düşüyor.
  /// Ayrım pahalı bir bulgunun karşılığı — "Mağazada tanımlı paket
  /// bulunamadı" cümlesi ağ sorununda yanlış teşhisti ve kullanıcıyı
  /// bekleyecek bir şey olmadığına inandırıyordu.
  Widget _unavailable(AppLocalizations l10n) => GlassPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.billingUnavailable, style: RythoText.display(16)),
          const SizedBox(height: 6),
          Text(
            billingConfigured
                ? l10n.billingNoPackages
                : l10n.billingNotConfigured,
            style: RythoText.body(12.5, color: RythoColors.parchmentDim),
          ),
        ]),
      );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.package,
    required this.selected,
    required this.onTap,
    this.showRadio = true,
  });

  final Package package;
  final bool selected;
  final VoidCallback onTap;
  final bool showRadio;

  bool get _isAnnual => package.packageType == PackageType.annual;

  /// Deneme süresi varsa "3 gün ücretsiz, sonra X" — mağaza kuralı gereği
  /// denemenin ne zaman ücrete döndüğü satın alma ekranında yazmak zorunda.
  ///
  /// İki kaynak denenir (M1): `introductoryPrice` (eski model) boşsa
  /// Play'in modern teklif modelindeki ücretsiz faz
  /// (`defaultOption.freePhase`). Google Play'de deneme bir base-plan
  /// TEKLİFİDİR ve intro alanı null kalabiliyor — yedek olmadan ibare
  /// sessizce kaybolur (inceleme reddi sebebi).
  static String _priceLine(AppLocalizations l10n, StoreProduct product) {
    var sayi = 0;
    PeriodUnit? birim;

    final intro = product.introductoryPrice;
    if (intro != null) {
      sayi = intro.periodNumberOfUnits;
      birim = intro.periodUnit;
    } else {
      final donem = product.defaultOption?.freePhase?.billingPeriod;
      if (donem != null) {
        sayi = donem.value;
        birim = donem.unit;
      }
    }
    if (birim == null || sayi <= 0) return product.priceString;

    final unit = switch (birim) {
      PeriodUnit.day => l10n.unitDay,
      PeriodUnit.week => l10n.unitWeek,
      PeriodUnit.month => l10n.unitMonth,
      PeriodUnit.year => l10n.unitYear,
      _ => l10n.unitDay,
    };
    return l10n.trialThenPrice(sayi, unit, product.priceString);
  }

  @override
  Widget build(BuildContext context) {
    final product = package.storeProduct;
    final l10n = AppLocalizations.of(context);
    final title = switch (package.packageType) {
      PackageType.annual => l10n.planAnnual,
      PackageType.weekly => l10n.planWeekly,
      PackageType.monthly => l10n.planMonthly,
      _ => product.title,
    };

    return GlassPanel(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      glow: selected,
      onTap: onTap,
      child: Row(children: [
        if (showRadio) ...[
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: selected ? RythoColors.gold : RythoColors.parchmentDim,
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // Plan adı esnemiyordu; uzun adda (veya rozet varken) satır
              // taşıyordu. `Flexible` adın sarmasına izin verir.
              Flexible(child: Text(title, style: RythoText.display(17))),
              if (_isAnnual) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: RythoColors.gold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(l10n.bestValue,
                      style: RythoText.label(9, color: RythoColors.goldBright)),
                ),
              ],
            ]),
            const SizedBox(height: 2),
            Text(_priceLine(l10n, product),
                style: RythoText.body(12.5, color: RythoColors.parchmentDim)),
          ]),
        ),
      ]),
    );
  }
}

/// Kutlama perdesi: kendini 1.4 saniyede kapatır — kullanıcıdan etkileşim
/// istemez, akışı yalnızca bir nefes geciktirir.
class _PlusCelebration extends StatefulWidget {
  const _PlusCelebration();

  @override
  State<_PlusCelebration> createState() => _PlusCelebrationState();
}

class _PlusCelebrationState extends State<_PlusCelebration> {
  Timer? _kapanis;

  @override
  void initState() {
    super.initState();
    _kapanis = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _kapanis?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sabit = reduceMotion(context);
    Widget muhur = Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
      decoration: BoxDecoration(
        gradient: RythoColors.primaryGradient,
        borderRadius: BorderRadius.circular(RythoRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(
              color: RythoColors.goldGlow, blurRadius: 36, spreadRadius: 2),
        ],
      ),
      child: Text('Rytho+',
          style: RythoText.display(24, w: FontWeight.w700)),
    );
    if (!sabit) {
      muhur = muhur
          .animate()
          .fadeIn(duration: RythoMotion.base)
          .scale(
              begin: const Offset(0.2, 0.2),
              end: const Offset(1, 1),
              duration: const Duration(milliseconds: 500),
              curve: RythoMotion.pop);
    }
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Stack(alignment: Alignment.center, children: [
          if (!sabit) const StarBurst(size: 300, particles: 56),
          muhur,
        ]),
      ),
    );
  }
}

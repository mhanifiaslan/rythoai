import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, PlatformException;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/analytics.dart';
import '../../core/purchase_errors.dart';
import '../../core/sound.dart';
import '../../core/subscription.dart';
import '../../core/wallet.dart';
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
import 'bedel_rozeti.dart';
import 'ozellik_katalogu.dart';
import 'paywall_acilis.dart';

/// RYTHO+ paywall.
///
/// Mağaza kuralları gereği bu ekranda şunlar **görünür olmak zorunda**:
/// fiyat, yenileme dönemi, denemenin ne zaman ücrete döneceği, iptalin nasıl
/// yapılacağı ve "Satın alımları geri yükle" seçeneği. Bunlar süsleme değil,
/// eksikse inceleme reddi sebebidir.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({
    super.key,
    required this.kaynak,
    this.reason,
    this.ozellik,
  });

  /// Kilitli uçtan dönen açıklama ("… Rytho+ aboneliğine dahildir").
  final String? reason;

  /// Hangi yüzeyden açıldı — analitik etiketi buradan. ZORUNLU: etiketi
  /// `reason`dan türeten eski iki değerli kural D7'de silindi, çünkü
  /// kaynak taşımayan çağrı yeri kalmadı (`acPaywall` tek giriş).
  final PaywallKaynak kaynak;

  /// Hangi özelliğin kilidine basıldı — `null`: genel giriş. Doluysa
  /// başlığın üstünde "{özellik} için Rytho+" etiketi çizilir: 402
  /// köprüsü bunu sunucunun `X-Paywall-Feature` başlığından taşıyor.
  final PlusOzellik? ozellik;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

/// Yıllık paketin aylığa göre tasarrufu, yüzde — ya da `null`.
///
/// ÖLÇÜLMEYEN SÖYLENMEZ: iki fiyat aynı para biriminde değilse, biri sıfır
/// ya da eksikse, yıllık 12 aylıktan ucuz DEĞİLSE rozet yok. Sayı
/// mağazanın söylediği iki fiyattan türetilir, elle yazılmaz (K8:
/// "yalnız ölçülmüş %N tasarruf").
int? yillikTasarrufYuzdesi(
    {required StoreProduct aylik, required StoreProduct yillik}) {
  if (aylik.currencyCode != yillik.currencyCode) return null;
  if (aylik.price <= 0 || yillik.price <= 0) return null;
  final yuzde = ((1 - yillik.price / (aylik.price * 12)) * 100).round();
  return yuzde > 0 ? yuzde : null;
}

/// Yıllık fiyatın aylık eşdeğeri, mağazanın para birimiyle biçimli.
///
/// Fiyat METNİ bölünemez ("₺1.499,99"), sayı bölünür ve aynı para
/// birimiyle yeniden biçimlenir. Para birimi kodu yoksa eşdeğer de yok.
String? aylikEsdeger(StoreProduct yillik, String dil) {
  if (yillik.price <= 0 || yillik.currencyCode.isEmpty) return null;
  try {
    return NumberFormat.simpleCurrency(locale: dil, name: yillik.currencyCode)
        .format(yillik.price / 12);
  } catch (_) {
    return null;
  }
}

/// Plan satırının fiyat cümlesi.
///
/// Deneme süresi varsa "3 gün ücretsiz, sonra X" — mağaza kuralı gereği
/// denemenin ne zaman ücrete döndüğü satın alma ekranında yazmak zorunda.
///
/// İki kaynak denenir (M1): `introductoryPrice` (eski model) boşsa
/// Play'in modern teklif modelindeki ücretsiz faz
/// (`defaultOption.freePhase`). Google Play'de deneme bir base-plan
/// TEKLİFİDİR ve intro alanı null kalabiliyor — yedek olmadan ibare
/// sessizce kaybolur (inceleme reddi sebebi).
///
/// Birim başına AYRI anahtar (`trialThenPriceDays/Weeks/…`): İngilizce
/// çoğul "1 weeks free" diyordu; tek şablon + birim adı çoğulu
/// bilemez. Bilinmeyen birimde deneme İDDİA EDİLMEZ, düz fiyat yazılır
/// (eski hâl `_ => unitDay` ile "gün" uyduruyordu). Denemesiz: fiyat +
/// dönem (`priceWithPeriod`), dönem paket türünden; bilinmeyen türde
/// yalnız fiyat — dönem de uydurulmaz.
String fiyatSatiri(
    AppLocalizations l10n, StoreProduct product, PackageType tur) {
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
  final fiyat = product.priceString;
  if (birim != null && sayi > 0) {
    final satir = switch (birim) {
      PeriodUnit.day => l10n.trialThenPriceDays(sayi, fiyat),
      PeriodUnit.week => l10n.trialThenPriceWeeks(sayi, fiyat),
      PeriodUnit.month => l10n.trialThenPriceMonths(sayi, fiyat),
      PeriodUnit.year => l10n.trialThenPriceYears(sayi, fiyat),
      _ => null,
    };
    if (satir != null) return satir;
  }
  final donemAdi = switch (tur) {
    PackageType.weekly => l10n.unitWeek,
    PackageType.monthly => l10n.unitMonth,
    PackageType.annual => l10n.unitYear,
    _ => null,
  };
  return donemAdi == null ? fiyat : l10n.priceWithPeriod(fiyat, donemAdi);
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Package? _selected;
  bool _busy = false;
  String? _error;

  /// Bekleyiş uzarsa EKRANDAN çıkış yolu açılır — meşguliyetten değil.
  ///
  /// Mağaza çağrısı hiç dönmezse `finally` de çalışmıyor ve kullanıcı sonsuz
  /// bir dönen halkada kalıyordu — cihaz testinde bildirilen "ödeme adımını
  /// geçemiyorum" buydu. Çağrıya zaman aşımı KOYULMADI bilerek: kullanıcı o
  /// sırada mağazanın kendi ekranında şifre giriyor olabilir ve akışı yarıda
  /// kesmek daha kötü.
  ///
  /// ⚠️ Bu çıkış bir dönem `_mesguliyet(false)` çağırıyordu ve ÖLÇÜLEN iki
  /// sonucu vardı (1.17.0+45): (a) uçuştaki `Purchases.purchase` iptal
  /// EDİLMİYOR — iptal kanalı yok — ama spinner durduğu için ekran BİTMİŞ
  /// görünüyordu; sonra kutlama perdesi beklenmedik bir anda inip ekranı
  /// kapatıyordu. (b) `GoldButton`un kuralı `enabled = onPressed != null &&
  /// !busy`, yani bayrak düşünce düğme YENİDEN BASILABİLİR hale geliyor ve
  /// kullanıcı İKİNCİ KEZ satın alıyordu.
  ///
  /// Bu yüzden `_busy` artık yalnız `finally` indiriyor. Onuncu saniyede
  /// değişen şey METİN; çıkış ise ekranı POP ediyor, bayrağı değil. Ekranı
  /// kapatmak güvenli çünkü sonucu ekran değil kalıcı toplayıcı topluyor
  /// (bkz. core/subscription.dart `yetkiToplayiciProvider`).
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
    // Etiket kaynaktan: hangi yüzeyin dönüştürdüğü ancak böyle ölçülür.
    Analytics.paywallShown(widget.kaynak.etiket);
    // Anahtarsız derleme GELİŞTİRİCİ kusurudur, kullanıcı cümlesi değil:
    // ekran "mağazada paket yok" der, kusur Crashlytics'e gider. Eski hâl
    // "Bu derlemede abonelik anahtarları tanımlı değil" cümlesini
    // kullanıcıya okutuyordu (`billingNotConfigured`, silindi).
    if (!billingConfigured) gelistiriciKusuruBildir('billing-not-configured');
  }

  /// Faydalar — her satır katalog üyeleriyle anılır.
  ///
  /// Liste bir dönem BEŞ satırdı ve son turların eklediği her Plus özelliği
  /// bu ekranda YOKTU: yüz okuma, Yıl Haritası, İç Takvim, Doğum Kapısı,
  /// I Ching ve on kişilik çevre. Yanlış beyan değildi ama para istenen
  /// ekranda anlatılmayan özellik, satılmayan özelliktir.
  ///
  /// Her satırın karşılığı sunucuda ÖLÇÜLDÜ, tahminle yazılmadı:
  /// `api/face_reading.py` → `require_plus("firasa")`;
  /// `api/reports.py` → `solar_return` / `progressions` / `birth_hexagram` /
  /// `iching` / `synastry` hepsi `require_plus`; kontenjan
  /// `services/people_service.py` → ücretsiz 1, Plus 10.
  ///
  /// Emoji ve bedel KATALOGDAN (D7): satır başındaki simge karo ve kilit
  /// kartıyla aynı üyeden geliyor (`☯` ↔ `☯️` ayrışması ölçülmüştü), bedel
  /// rozeti cüzdanın `costs` haritasından — satır birden çok özelliği
  /// anıyorsa yalnız hepsi aynı bedeldeyken tek sayı (`BedelRozeti.ortak`).
  List<(List<PlusOzellik>, String, String)> _benefits(
          AppLocalizations l10n, WalletStatus? cuzdan) =>
      [
        ([PlusOzellik.daily], l10n.benefitDailyTitle, l10n.benefitDailyBody),
        ([PlusOzellik.natal], l10n.benefitNatalTitle, l10n.benefitNatalBody),
        ([PlusOzellik.dyad], l10n.benefitDyadTitle, l10n.benefitDyadBody),
        ([PlusOzellik.chat], _sohbetBasligi(l10n, cuzdan), l10n.benefitChatBody),
        (
          [PlusOzellik.bazi, PlusOzellik.synastry],
          l10n.benefitBaziTitle,
          l10n.benefitBaziBody
        ),
        ([PlusOzellik.face], l10n.benefitFaceTitle, l10n.benefitFaceBody),
        (
          [
            PlusOzellik.solarReturn,
            PlusOzellik.progressions,
            PlusOzellik.birthHexagram,
          ],
          l10n.benefitTimingTitle,
          l10n.benefitTimingBody
        ),
        ([PlusOzellik.iching], l10n.benefitIchingTitle, l10n.benefitIchingBody),
        ([PlusOzellik.people], l10n.benefitPeopleTitle, l10n.benefitPeopleBody),
      ];

  /// "Ayda {N} AI kredisi" — N SUNUCUDAN (`monthly_allowance`), elle değil.
  ///
  /// Eski satır ARB'de "Ayda 100 AI kredisi" diye sabitti ve hak 300'den
  /// 100'e inerken bir tur boyunca eski sayıyı söyledi; backend bekçisi onu
  /// yakalıyordu ama cihazdaki kurulu paketi yakalayamazdı. Cüzdan
  /// okunamadıysa sayısız başlık: "Aylık AI kredisi" — ölçülmeyen söylenmez.
  static String _sohbetBasligi(AppLocalizations l10n, WalletStatus? cuzdan) {
    final hak = cuzdan == null || cuzdan.bilinmiyor
        ? null
        : cuzdan.monthlyAllowance;
    return hak == null || hak <= 0
        ? l10n.benefitChatTitleUnknown
        : l10n.benefitChatTitleCount(hak);
  }

  Future<void> _buy() async {
    final package = _selected;
    if (package == null) return;
    // Çift satın almanın YAPISAL kapısı. Düğmenin `busy` kuralına güvenmek
    // yetmiyordu: `GoldButton` yalnız çizim anındaki bayrağa bakıyor ve
    // onuncu saniyedeki eski çıkış o bayrağı indiriyordu. Kapı burada,
    // arayüzden bağımsız duruyor.
    if (_busy) return;
    setState(() => _error = null);
    _mesguliyet(true);
    // Huninin orta adimi: bu olay olmadan "paywall calismiyor" ile "magaza
    // akisi dusuyor" ayirt edilemez.
    Analytics.purchaseStarted();
    try {
      final satinAl = ref.read(paketSatinAliciProvider) ?? purchasePackage;
      final sonuc = await satinAl(ref, package);
      if (sonuc != SatinAlmaSonucu.yetkiYok) Analytics.purchaseCompleted();
      if (sonuc == SatinAlmaSonucu.yetkiYok) {
        // Satın alma cihazda bitti ama beklenen yetki (entitlement)
        // müşteri kaydında görünmüyor — tipik nedeni panelde ürünün
        // yanlış/eksik entitlement'a bağlanması. Eskiden bu dal SESSİZDİ:
        // kullanıcı parayı öder, ekran tepkisiz kalırdı (M1 onarımı).
        if (mounted) {
          setState(() => _error =
              AppLocalizations.of(context).purchaseEntitlementMissing);
        }
      } else if (mounted) {
        // Sunucu bütçe içinde yetkiyi görmediyse akış KESİLMEZ (o karar
        // bilinçli, bkz. subscription.purchasePackage) ama kullanıcıya
        // söylenen cümle gerçeğe uyar: "alındı, yansıması sürebilir".
        // Ölçülmeyen söylenmez — "aboneliğin açıldı" burada ölçülmemişti.
        final gecikti = sonuc == SatinAlmaSonucu.sunucuGecikti;
        final mesajci = ScaffoldMessenger.of(context);
        final bekleyenMetin =
            AppLocalizations.of(context).purchasePendingServer;
        await _kutla();
        if (!mounted) return;
        if (gecikti) {
          mesajci.showSnackBar(SnackBar(content: Text(bekleyenMetin)));
        }
        Navigator.of(context).pop(true);
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        // Vazgeçmek hata değil.
      } else if (code == PurchasesErrorCode.productAlreadyPurchasedError) {
        // Play hesabında abonelik zaten var (tipik: sunucu kaydı henüz
        // eşitlenmemiş ya da abonelik başka app-kimliğinde). Kullanıcıyı
        // çıkmaza sokma: kendiliğinden geri yükle — abonelik hangi
        // kimlikteyse bu hesaba çekilir (G-turu, iç test bulgusu).
        if (mounted) await _restore(zincirli: true);
      } else if (mounted) {
        setState(() => _error = purchaseErrorText(
            e, AppLocalizations.of(context),
            abonelik: true));
      }
    } catch (e) {
      // Tek kapı: ağ/zaman aşımı `friendlyError`dan geçer, "beklenmeyen
      // sorun" yerine bağlantı cümlesi görünür.
      if (mounted) {
        setState(() => _error = purchaseErrorText(
            e, AppLocalizations.of(context),
            abonelik: true));
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

  /// [zincirli] = çağrı [_buy]ın "zaten satın alınmış" dalından geliyor.
  ///
  /// Kapı `_busy`ye bakıyor çünkü kullanıcının çift basmasının bir faydası
  /// yok. Ama o dal tam da MEŞGULKEN çağırıyor ([_buy]ın `finally`si henüz
  /// koşmadı) ve KOŞULSUZ bir kapı kurtarma yolunu SESSİZCE öldürürdü:
  /// Play hesabında aboneliği zaten olan kullanıcı "Devam"a basıyor,
  /// mağaza `productAlreadyPurchasedError` dönüyor, geri yükleme HIÇ
  /// koşmuyor ve o dal hata metni de YAZMIYOR — ekran sessizce boşa
  /// dönüyor, abonelik kapalı kalıyor. Çift basımı engellemek kullanıcının
  /// düğmesi için doğru, kendi hata dalımız için yanlıştı.
  Future<void> _restore({bool zincirli = false}) async {
    if (_busy && !zincirli) return;
    _mesguliyet(true);
    try {
      final ok = await restorePurchases(ref);
      Analytics.purchasesRestored(found: ok);
      if (!mounted) return;
      if (ok) {
        await _kutla();
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() =>
            _error = AppLocalizations.of(context).noActiveSubscription);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = purchaseErrorText(
            e, AppLocalizations.of(context),
            abonelik: true));
      }
    } finally {
      if (mounted) _mesguliyet(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offerings = ref.watch(offeringsProvider);
    final l10n = AppLocalizations.of(context);
    // `.value`: tazeleme turunda önceki cüzdan korunur; rozetler yanıp
    // sönmez. Okunamadıysa rozetler ve sayılı sohbet başlığı susar.
    final cuzdan = ref.watch(walletProvider).value;
    final ozellik = widget.ozellik;
    final dil = Localizations.localeOf(context).toLanguageTag();

    // Geri tuşu ödeme UÇARKEN geçmez.
    //
    // `PopScope` depoda üç yerde vardı (onboarding sihirbazı, zorunlu
    // güncelleme, cihaz çakışması) ve ödeme ekranları o listede YOKTU —
    // oysa kaza ile kapanmasının bedeli en yüksek ekran burası. `canPop`
    // yalnız sistem/geri jestini ve `maybePop`u kesiyor; aşağıdaki
    // "ekranı kapat" düğmesi DOĞRUDAN `pop` çağırdığı için o kasıtlı
    // çıkış açık kalıyor. Ayrım bilinçli: kaza kapanıyor, karar geçiyor.
    return PopScope(
      canPop: !_busy,
      child: CosmicScaffold(
      appBar: AppBar(
        title: Text(l10n.paywallTitle),
        // Simge rotaya göre (`tamEkranDiyalogMu`): kesinti yolu diyalog
        // (✕), dokunuş yolu fade-through (←). Sabit ✕ dokunuşla gelen
        // kullanıcıya "bir şey araya girdi" diyordu.
        leading: IconButton(
          icon: Icon(
              tamEkranDiyalogMu(context)
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
              size: 22),
          // Meşgulken kapatma düğmesi de ölü: `_busy` kapısı burada
          // HİÇ YOKTU ve ödeme uçarken tek dokunuşla ekran kapanıyordu.
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
      ),
      body: ListView(
          padding: const EdgeInsets.only(bottom: RythoSpace.xxl),
          children: [
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
                  const SizedBox(height: RythoSpace.xxs),
                  Text(
                      kalan <= 1
                          ? l10n.trialBannerLastDay
                          : l10n.trialBannerDays(kalan),
                      style: RythoText.body(12.5,
                          color: RythoColors.parchmentDim)),
                ]),
          );
        }),
        // Bağlam etiketi: hangi kilitten gelindi. `X-Paywall-Feature`
        // bir tur boyunca sunucudan gelip istemcide hiç okunmuyordu.
        if (ozellik != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.lg, RythoSpace.md, RythoSpace.lg, 0),
            child: Text(l10n.paywallForFeature(ozellik.baslik(l10n)),
                style: RythoType.label.copyWith(color: RythoColors.goldBright)),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(RythoSpace.lg,
              ozellik == null ? RythoSpace.md : RythoSpace.xs, RythoSpace.lg,
              RythoSpace.xs),
          child: Text(l10n.paywallHeadline, style: RythoText.display(26)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.lg, 0, RythoSpace.lg, RythoSpace.lg),
          child: Text(
            l10n.paywallBody,
            style: RythoText.body(13.5, color: RythoColors.parchmentDim),
          ),
        ),
        // Satırlar SÜKÛNETLE gelir: eski `.animate().fadeIn().slideX()`
        // zinciri dokuz satırı 60 ms arayla kaydırıyordu ve hareket azaltma
        // kapısından geçmiyordu (D5 sükûnet doktrini; `RythoReveal` tek yol).
        for (final (i, benefit) in _benefits(l10n, cuzdan).indexed)
          RythoReveal(
            index: i,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: RythoSpace.lg, vertical: RythoSpace.sm),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(benefit.$1.first.emoji, style: RythoText.emoji(19)),
                    const SizedBox(width: RythoSpace.md),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                  child: Text(benefit.$2,
                                      style: RythoText.body(14.5,
                                          w: FontWeight.w700))),
                              const SizedBox(width: RythoSpace.sm),
                              BedelRozeti.ortak(benefit.$1, kucuk: true),
                            ]),
                            const SizedBox(height: RythoSpace.xxs),
                            Text(benefit.$3,
                                style: RythoText.body(12.5,
                                    color: RythoColors.parchmentDim)),
                          ]),
                    ),
                  ]),
            ),
          ),
        const SectionDivider(),
        offerings.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: RythoSpace.xxl),
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
            final aylik = _paket(packages, PackageType.monthly);
            return Column(children: [
              for (final package in packages)
                _PlanTile(
                  package: package,
                  aylik: aylik,
                  dil: dil,
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
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.lg, RythoSpace.sm, RythoSpace.lg, 0),
            // Hata rengi TEK: `madder` (eski `magenta`, marka rengiydi —
            // hata, davet rengiyle söylenmez).
            child: Text(_error!,
                style: RythoText.body(12.5, color: RythoColors.madder)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.lg, RythoSpace.lg, RythoSpace.lg, RythoSpace.sm),
          child: GoldButton(
            text: _selected == null
                ? l10n.paywallChoosePlan
                : l10n.paywallContinue,
            busy: _busy,
            onPressed: _selected == null ? null : _buy,
          ),
        ),
        // Beklerken EKRANDA METİN.
        //
        // Ürünün en pahalı 15 saniyesi 22 piksellik bir halkaya emanetti
        // (`AstrolabeSpinner`): kullanıcı ne olup bittiğini bilmiyordu ve
        // "bitti mi, takıldı mı" sorusunu ekran cevaplamıyordu. Onuncu
        // saniyede metin SERTLEŞİYOR ve çıkış yolu açılıyor — ama meşguliyet
        // düşmüyor, yani düğme yeniden basılabilir hale GELMİYOR.
        if (_busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.xl, RythoSpace.xs, RythoSpace.xl, 0),
            child: Text(
              _uzunSuruyor ? l10n.purchaseWaitingLong : l10n.purchaseWaitingStore,
              style: RythoText.body(12.5, color: RythoColors.parchmentDim),
              textAlign: TextAlign.center,
            ),
          ),
        // Bekleyiş uzarsa ÇIKIŞ — ekrandan, meşguliyetten değil. Sonucu
        // kalıcı toplayıcı yakaladığı için buradan çıkmak satın almayı
        // kaybettirmiyor; eskiden bu düğme `_mesguliyet(false)` çağırıp
        // ikinci satın almanın kapısını açıyordu.
        if (_uzunSuruyor)
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.purchaseLeaveScreen,
                  style: RythoText.label(12.5, color: RythoColors.goldBright)),
            ),
          ),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _restore,
            child: Text(l10n.restorePurchases,
                style: RythoText.label(12.5, color: RythoColors.parchmentDim)),
          ),
        ),
        // Ortak kodu girişi KALDIRILDI (A2): jeton-bonusu/atıf modeli
        // şimdilik kullanılmıyor. Backend (/billing/redeem-code + admin
        // Ortaklar paneli) bilinçli olarak duruyor — ileride farklı bir
        // ödül modeli tasarlanırsa zemin hazır.
        // Mağaza kuralı: iptal ve yenileme koşulları satın alma ekranında
        // açıkça yazmalı.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.xl, RythoSpace.sm, RythoSpace.xl, RythoSpace.sm),
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
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.xl, 0, RythoSpace.xl, RythoSpace.sm),
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
      ),
    );
  }

  static Package? _paket(List<Package> packages, PackageType tur) {
    for (final p in packages) {
      if (p.packageType == tur) return p;
    }
    return null;
  }

  /// Varsayılan seçili paket: AYLIK (K8).
  ///
  /// Yıllık teklifte olsa da önseçili değil — daha pahalı peşin ödemeyi
  /// varsayılan yapmak, kullanıcının kararını onun yerine vermek olur;
  /// yıllığın lehine konuşan tek şey ölçülmüş tasarruf rozeti.
  Package _defaultPackage(List<Package> packages) =>
      _paket(packages, PackageType.monthly) ?? packages.first;

  /// Mağaza sorunsuz yanıtladı ama gösterilecek paket YOK.
  ///
  /// Hata metni buraya artık GİRMEZ: mağaza/ağ hatası `error:` dalına düşüyor.
  /// Ayrım pahalı bir bulgunun karşılığı — "Mağazada tanımlı paket
  /// bulunamadı" cümlesi ağ sorununda yanlış teşhisti ve kullanıcıyı
  /// bekleyecek bir şey olmadığına inandırıyordu.
  Widget _unavailable(AppLocalizations l10n) => GlassPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.billingUnavailable, style: RythoText.display(16)),
          const SizedBox(height: RythoSpace.xs),
          Text(
            l10n.billingNoPackages,
            style: RythoText.body(12.5, color: RythoColors.parchmentDim),
          ),
        ]),
      );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.package,
    required this.aylik,
    required this.dil,
    required this.selected,
    required this.onTap,
    this.showRadio = true,
  });

  final Package package;

  /// Teklifteki aylık paket — yıllığın tasarruf rozeti ona göre ölçülür.
  final Package? aylik;
  final String dil;
  final bool selected;
  final VoidCallback onTap;
  final bool showRadio;

  bool get _isAnnual => package.packageType == PackageType.annual;

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
    // Rozet YALNIZ ölçülmüşse: "EN İYİ DEĞER" eski sabit rozeti yıllığa
    // koşulsuz basılıyordu — fiyatlar ne derse desin (K8 ile gitti).
    final tasarruf = _isAnnual && aylik != null
        ? yillikTasarrufYuzdesi(
            aylik: aylik!.storeProduct, yillik: product)
        : null;
    final aylikKarsiligi = _isAnnual ? aylikEsdeger(product, dil) : null;

    return GlassPanel(
      margin: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: RythoSpace.xs),
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
          const SizedBox(width: RythoSpace.md),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // Plan adı esnemiyordu; uzun adda (veya rozet varken) satır
              // taşıyordu. `Flexible` adın sarmasına izin verir.
              Flexible(child: Text(title, style: RythoText.display(17))),
              if (tasarruf != null) ...[
                const SizedBox(width: RythoSpace.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RythoSpace.sm, vertical: RythoSpace.xxs),
                  decoration: BoxDecoration(
                    color: RythoColors.gold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(RythoRadius.pill),
                  ),
                  child: Text(l10n.annualSavingsBadge(tasarruf),
                      style: RythoText.label(9, color: RythoColors.goldBright)),
                ),
              ],
            ]),
            const SizedBox(height: RythoSpace.xxs),
            Text(fiyatSatiri(l10n, product, package.packageType),
                style: RythoText.body(12.5, color: RythoColors.parchmentDim)),
            if (aylikKarsiligi != null)
              Text(l10n.annualPerMonth(aylikKarsiligi),
                  style: RythoText.body(11.5, color: RythoColors.parchmentDim)),
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

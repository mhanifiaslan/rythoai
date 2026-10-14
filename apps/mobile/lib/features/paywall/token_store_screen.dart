/// Token mağazası — üç paket, tekrar tekrar alınabilir.
///
/// ## Paywall'dan farkı
///
/// Paywall "abone ol" der; burası "bakiyeni doldur" der. Sunucu 402'nin
/// yanında `X-Paywall-Reason: tokens` gönderirse kullanıcı BURAYA gelir:
/// abonelik sorunu yok, yalnızca token bitti — ona abonelik satmaya
/// çalışmak yanlış teşhis olurdu.
///
/// Adetler sunucu gerçeğidir (backend `TOKEN_PACKS`); cüzdan yanıtı
/// `packs` haritasıyla onları taşıyor (`WalletStatus.packs`), eski sunucu
/// göndermezse `kPackDisplayAmounts` yedeği. Bu ekran adetleri YALNIZCA
/// göstermek için bilir — bakiyeye ne yükleneceğine webhook karar verir.
/// Fiyat metni mağazadan gelir (para birimi/vergi yerelleşmesi mağazanın
/// işi).
///
/// ## Paketler YALNIZ aboneye gösterilir
///
/// Sahibin kararı (K2) ve gerekçesi sunucuda ölçüldü: `charge_metered` TÜM
/// depoda tek yerden çağrılıyor (`api/chat.py`), beş jetonluk raporların
/// hepsi `require_plus` arkasında. Yani abone olmayan birinin satın aldığı
/// kredinin tek kullanım senaryosu "günün 6. sohbet mesajı" — ekranın alt
/// satırındaki bedel listesi ise I Ching, ikili dinamik ve derin raporları
/// sayıyor. Mağaza parasını alıp karşılığını vermediği bir ürün
/// gösteriyordu; artık göstermiyor.
///
/// Deneme (trial) kullanıcısı ABONE SAYILIR ve bu doğru: `/billing/status`
/// gövdesindeki `active`, sunucudaki `is_subscriber` ile birebir aynı
/// (`core/entitlements.py` — deneme tüm Plus kapılarını açıyor). Paket onun
/// için ayrıca ANLAMLI, çünkü `get_wallet` denemedeki kullanıcıya
/// `allowance: 0` veriyor (`core/wallet.py`) ve raporlar `wallet.spender`
/// ile doğrudan cüzdandan harcıyor — yani denemedeki kullanıcı YALNIZ
/// `purchased` bakiyesinden harcar.
///
/// ## Tek düğme (D7)
/// Üç paket üç dolu düğme taşıyordu — ekranda üç "Satın al". Şimdi paket
/// seçilir (radyo, paywall'daki plan seçimiyle aynı dil), altta TEK dolu
/// düğme fiyatı söyler ("Satın al — ₺99,99"); seçimle açılan yer kredi
/// başına fiyata gitti, yani üç paketi karşılaştırmanın ölçüsü ekranda.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

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
import 'paywall_acilis.dart';

/// Gösterim adetleri — YEDEK: sunucu `packs` göndermiyorsa (eski rev).
/// Sunucudaki `TOKEN_PACKS` ile aynı tutulmalı. Yanlışsa kullanıcı yanlış
/// vaat görür ama yanlış bakiye ALMAZ (yükleme sunucuda).
const Map<String, int> kPackDisplayAmounts = {
  'rytho_tokens_small': 50,
  'rytho_tokens_medium': 100,
  'rytho_tokens_large': 200,
};

/// Paketin adedi: önce sunucu (`packs`), yoksa yedek tablo, o da yoksa
/// `null` (adet uydurulmaz, başlık mağazanın ürün adı olur).
int? paketAdedi(WalletStatus cuzdan, String urunKimligi) =>
    cuzdan.packs[urunKimligi] ?? kPackDisplayAmounts[urunKimligi];

/// Kredi başına fiyat, mağazanın para birimiyle — ya da `null`.
///
/// Fiyat METNİ bölünemez; sayı bölünür ve aynı para birimiyle yeniden
/// biçimlenir. Adet ya da para birimi bilinmiyorsa satır yok.
String? krediBasinaFiyat(StoreProduct urun, int? adet, String dil) {
  if (adet == null || adet <= 0) return null;
  if (urun.price <= 0 || urun.currencyCode.isEmpty) return null;
  try {
    return NumberFormat.simpleCurrency(locale: dil, name: urun.currencyCode)
        .format(urun.price / adet);
  } catch (_) {
    return null;
  }
}

/// Mağazadaki bedel satırı — sayılar SUNUCUDAN gelen `costs` haritasından;
/// bilinmiyorsa satır HİÇ çizilmez (`null`).
///
/// NEDEN (ölçüldü): bedel gerçeğinin kanonik kaynağı sunucudaki
/// `core/wallet.py` `TOKEN_COSTS` tablosu ve o tablo `/billing/wallet`
/// yanıtının `costs` alanıyla ekrana kadar GELİYOR. Eski satır elle yazılmış
/// bir çeviri dizesiydi (`tokenCostsNote` "1 · 2 · 3 · 5"), yani bedel
/// gerçeğinin İKİNCİ kaynağı; ara çözüm (`bedelSatiri`) şablondaki sayıları
/// KONUMA göre sunucu sayılarıyla değiştiriyordu ve bir tur boyunca İ Ching
/// ile ikili dinamiğin bedellerini yer değiştirmiş gösterdi. D7'de ARB
/// girdisi yer tutuculu oldu (`{chat} {iching} {dyad} {deep}`) — konum
/// eşleştirmesi ve şablonun kendi sayıları diye bir şey kalmadı.
///
/// Sessiz pencere hâlâ geçerli ve bu işlevin varlık sebebi: sunucu ayrı
/// dağıtılır (backend rev ↔ sürüm kodu), kurulu paketin derlenmiş cümlesi
/// eski rakamı söyleyemez çünkü rakam cümlede YOK, sunucudan gelir.
///
/// Dördüncü sayı ("derin raporlar ve yüz okuma") tek özellik değil, geri
/// kalanların ÖZETİ; özet ancak hepsi aynı bedeldeyken doğru — değilse
/// cümle kurulamaz ve `null` döner (uydurma özet, bayat sayıdan kötü).
/// Aynı şartı sunucu tarafında `backend/tests/test_honesty.py` arıyor.
String? bedelNotu(AppLocalizations l10n, Map<String, int> bedeller) {
  final chat = bedeller['chat'];
  final iching = bedeller['iching'];
  final dyad = bedeller['dyad'];
  if (chat == null || iching == null || dyad == null) return null;
  final digerleri = {
    for (final girdi in bedeller.entries)
      if (!const {'chat', 'iching', 'dyad'}.contains(girdi.key)) girdi.value
  };
  if (digerleri.length != 1) return null;
  return l10n.tokenCostsNote(chat, iching, dyad, digerleri.first);
}

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

  /// Seçili paketin kimliği; liste gelince en küçük paket önseçilir
  /// (paywall'da aylık önseçili — aynı kural: en düşük taahhüt).
  String? _seciliKimlik;

  Future<void> _buy(StoreProduct product) async {
    // Çift satın almanın YAPISAL kapısı — `enabled` bayrağına ek olarak.
    // Düğme kuralı yalnız çizim anındaki bayrağa bakıyor; kapı burada,
    // arayüzden bağımsız duruyor (paywall'daki `_buy` ile aynı gerekçe).
    if (_busyProductId != null) return;
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    setState(() => _busyProductId = product.identifier);
    try {
      final satinAl = ref.read(jetonSatinAliciProvider) ?? purchaseTokenPack;
      final yuklendi = await satinAl(ref, product);
      if (!mounted) return;
      // "Paket yüklendi" cümlesi eskiden dönen değere BAKMADAN söyleniyordu
      // ve bütçe dolmuş bir turda yanlıştı: bakiye henüz yüklenmemişti.
      // Ölçülen söylenir — ölçülmeyen değil.
      mesajci.showSnackBar(SnackBar(
          content: Text(yuklendi
              ? l10n.tokenPurchaseDone
              : l10n.purchasePendingServer)));
    } on PlatformException catch (e) {
      // Kullanıcının vazgeçmesi hata değil; sessiz geçilir.
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return;
      // Tüketilebilir pakette "zaten satın alınmış" = ilk alım hâlâ yolda
      // (Play tüketilmeden ikinci kez satmaz): bakiye yeniden sorulur,
      // kullanıcıya "işleniyor" denir — abonelik cümlesi değil.
      if (code == PurchasesErrorCode.productAlreadyPurchasedError) {
        ref.invalidate(walletProvider);
      }
      if (mounted) {
        mesajci.showSnackBar(SnackBar(
            content: Text(purchaseErrorText(e, l10n, abonelik: false))));
      }
    } catch (e) {
      if (mounted) {
        mesajci.showSnackBar(SnackBar(
            content: Text(purchaseErrorText(e, l10n, abonelik: false))));
      }
    } finally {
      if (mounted) setState(() => _busyProductId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // `?? unknown` (D7): yüklenirken "0" DEĞİL "—"; eski `?? none` bakiye
    // kartında sıfır gösteriyordu — sıfır "bitti" demek.
    final cuzdan = ref.watch(walletProvider).value ?? WalletStatus.unknown;
    final paketler = ref.watch(tokenPacksProvider);
    final mesgul = _busyProductId != null;
    final dil = Localizations.localeOf(context).toLanguageTag();

    // Abonelik ÜÇ HALLİ okunuyor: biliniyor-abone / biliniyor-değil /
    // BİLİNMİYOR. `paywallKarariVerilebilir` tam bunun için var (yükleniyor
    // ya da okuma düştü → karar bir sonraki tura kalır). Bilinmiyorken
    // paketleri gizlemek de göstermek de yanlış olurdu: biri aboneye
    // satılacak ürünü saklar, öteki abone olmayana karşılığı olmayan bir
    // bakiye satar.
    final abonelikDurumu = ref.watch(subscriptionProvider);
    final kararVerilebilir = paywallKarariVerilebilir(abonelikDurumu);
    final abone = abonelikDurumu.value?.active ?? false;

    // Geri tuşu ödeme UÇARKEN geçmez (paywall ile aynı gerekçe); bu ekranın
    // AppBar'ı bir dönem hiç özelleştirilmemişti, yani varsayılan geri
    // düğmesi meşguliyeti hiç bilmiyordu.
    return PopScope(
      canPop: !mesgul,
      child: CosmicScaffold(
      appBar: AppBar(
        title: Text(l10n.tokenStoreTitle),
        // Simge rotaya göre: bu ekran hem tam-ekran diyalog olarak (402
        // köprüsü, `core/api.dart`) hem normal sayfa olarak (Sohbet,
        // Abonelik) açılıyor. Sabit bir simge, girişlerin yarısında yanlış
        // şekli gösterirdi (`tamEkranDiyalogMu`, paywall ile ortak).
        leading: IconButton(
          icon: Icon(
              tamEkranDiyalogMu(context)
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
              size: 22),
          onPressed: mesgul ? null : () => Navigator.maybePop(context),
        ),
      ),
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
                          // Okunamadıysa "—" (WalletStatus.bilinmiyor).
                          child: Text(cuzdan.bakiyeYazisi(cuzdan.total),
                              key: ValueKey(
                                  cuzdan.bilinmiyor ? -1 : cuzdan.total),
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
                  // Döküm de aynı işlevden: toplam "—" iken alt satırların
                  // "0" demesi aynı kartta iki ayrı gerçek olurdu.
                  LabelValueRow(
                      label: l10n.tokenAllowanceRow,
                      value: cuzdan.bakiyeYazisi(cuzdan.allowance)),
                  LabelValueRow(
                      label: l10n.tokenPurchasedRow,
                      value: cuzdan.bakiyeYazisi(cuzdan.purchased)),
                  const SizedBox(height: RythoSpace.xs),
                  Text(l10n.tokenRolloverNote, style: RythoType.caption),
                ],
              ),
            ),

            SectionHeader(l10n.tokenPacksHeader),

            // Üç yol, üç hâl için. Sıra önemli: "bilinmiyor" ÖNCE sorulur,
            // yoksa `active` varsayılanı (`false`) bilinmeyen durumu
            // "abone değil" diye okur — bu tam olarak ilkacilis-2'de
            // yanan ayrım.
            if (!kararVerilebilir)
              _AbonelikKarariBekliyor(yukleniyor: abonelikDurumu.isLoading)
            else if (!abone)
              const _PaketlerPlusaOzel()
            else
              paketler.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(RythoSpace.xl),
                  child: Center(child: AstrolabeSpinner()),
                ),
                // Mağaza hatası artık BURAYA da düşüyor (sağlayıcı yutmuyor)
                // ve çeviri paywall'la AYNI kapıdan geçiyor: `friendlyError`
                // PlatformException'ı tanımadığı için ağ hatasında
                // "beklenmeyen sorun" diyordu, paywall doğru metni
                // gösterirken.
                error: (e, _) => ErrorCard(
                  message: magazaVeyaAgHatasi(e, l10n),
                  onRetry: () => ref.invalidate(tokenPacksProvider),
                ),
                data: (urunler) {
                  if (urunler.isEmpty) {
                    return EmptyState(
                      emoji: '🛰️',
                      title: l10n.tokenPacksUnavailable,
                      description: l10n.tokenPacksUnavailableBody,
                    );
                  }
                  // Önseçim en küçük paket; seçili kimlik listede yoksa
                  // (mağaza listesi değişti) yine en küçüğe döner.
                  final secili = urunler.cast<StoreProduct?>().firstWhere(
                          (u) => u!.identifier == _seciliKimlik,
                          orElse: () => null) ??
                      urunler.first;
                  return Column(children: [
                    for (final urun in urunler)
                      _PackTile(
                        product: urun,
                        amount: paketAdedi(cuzdan, urun.identifier),
                        dil: dil,
                        selected: identical(urun, secili),
                        onTap: mesgul
                            ? null
                            : () => setState(
                                () => _seciliKimlik = urun.identifier),
                      ),
                    const SizedBox(height: RythoSpace.xs),
                    // TEK dolu düğme, fiyat üstünde: kullanıcı neye
                    // bastığını düğmede okur (üç ayrı "Satın al" gitti).
                    GoldButton(
                      text: l10n.storeBuyWithPrice(secili.priceString),
                      busy: _busyProductId == secili.identifier,
                      onPressed: mesgul ? null : () => _buy(secili),
                    ),
                  ]);
                },
              ),

            const SizedBox(height: RythoSpace.md),
            // Bedeller SUNUCUDAN: `cuzdan.costs` boşken (bakiye henüz
            // okunmadı ya da okunamadı) satır HİÇ çizilmez — ölçülmeyen
            // söylenmez; bkz. [bedelNotu].
            if (bedelNotu(l10n, cuzdan.costs) case final not?)
              Text(not, style: RythoType.caption),
          ],
        ),
      ),
      ),
    );
  }
}

/// Abonelik durumu henüz BİLİNMİYOR.
///
/// Yükleniyorsa iskelet: paketlerin HACMİ görünür, karar görünmez. Okuma
/// DÜŞTÜYSE iskelet yetmez — sonsuza kadar yüklenen bir ekran, kullanıcıya
/// uygulamanın bozuk olduğunu söyler. O hâlde elle tazeleme sunuluyor,
/// çünkü `subscriptionProvider` auto-dispose DEĞİL: ekranı kapatıp açmak
/// bayat sonucu kurtarmaz.
class _AbonelikKarariBekliyor extends ConsumerWidget {
  const _AbonelikKarariBekliyor({required this.yukleniyor});

  final bool yukleniyor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (yukleniyor) {
      return const Column(children: [
        SkeletonPanel(height: 84, margin: EdgeInsets.only(bottom: RythoSpace.md)),
        SkeletonPanel(height: 84, margin: EdgeInsets.only(bottom: RythoSpace.md)),
        SkeletonPanel(height: 84, margin: EdgeInsets.only(bottom: RythoSpace.md)),
      ]);
    }
    return ErrorCard(
      message: AppLocalizations.of(context).errorGeneric,
      onRetry: () => ref.invalidate(subscriptionProvider),
    );
  }
}

/// Abone OLMAYANA paket yerine gösterilen panel (karar K2).
///
/// İki şeyi birlikte söylüyor, çünkü kullanıcının iki sorusu var: "neden
/// paket yok" ve "elimdeki kredi ne işe yarıyor". İkincisi eskiden ayrı bir
/// uyarı kutusuydu (`_UcretsizKatmanUyarisi`) ve satın alma düğmelerinin
/// üstünde dururdu; düğmeler kalkınca uyarının "almadan önce oku" işi de
/// bitti ama METNİ hâlâ doğru — bakiyesi olan ücretsiz kullanıcı onu
/// okumak zorunda. Bu yüzden iki panel teke indi.
class _PaketlerPlusaOzel extends StatelessWidget {
  const _PaketlerPlusaOzel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: RythoSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.tokenPacksPlusOnlyTitle, style: RythoType.cardTitle),
        const SizedBox(height: RythoSpace.xs),
        Text(l10n.tokenPacksPlusOnlyBody, style: RythoType.bodyDim),
        const SizedBox(height: RythoSpace.md),
        Text(l10n.tokenFreeTierWarnTitle, style: RythoText.body(13.5)),
        const SizedBox(height: RythoSpace.xxs),
        Text(l10n.tokenFreeTierWarnBody,
            style: RythoText.body(11.5, color: RythoColors.parchmentDim)),
        const SizedBox(height: RythoSpace.md),
        // Dokunuş yolu: fade-through, kaynak `token_store` (`acPaywall`
        // tek giriş; eski düz MaterialPageRoute kaynak etiketi taşımıyordu).
        GoldButton(
          text: l10n.tokenPacksSeePlus,
          onPressed: () =>
              acPaywall(context, kaynak: PaywallKaynak.magaza),
        ),
      ]),
    );
  }
}

/// Paket satırı: seçilebilir, düğmesiz (satın alma düğmesi listenin altında
/// TEK). Kredi başına fiyat satırı karşılaştırmanın ölçüsü — adet
/// bilinmiyorsa satır yok.
class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.product,
    required this.amount,
    required this.dil,
    required this.selected,
    required this.onTap,
  });

  final StoreProduct product;
  final int? amount;
  final String dil;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final birimFiyat = krediBasinaFiyat(product, amount, dil);
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: RythoSpace.md),
      glow: selected,
      onTap: onTap,
      child: Row(children: [
        Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 20,
          color: selected ? RythoColors.gold : RythoColors.parchmentDim,
        ),
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
              const SizedBox(height: RythoSpace.xxs),
              Text(product.priceString, style: RythoType.dataSmall),
              if (birimFiyat != null)
                Text(l10n.pricePerCredit(birimFiyat),
                    style: RythoType.caption),
            ],
          ),
        ),
      ]),
    );
  }
}

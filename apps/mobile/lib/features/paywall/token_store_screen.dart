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
import 'paywall_screen.dart';

/// Gösterim adetleri — sunucudaki `TOKEN_PACKS` ile aynı tutulmalı.
/// Yanlışsa kullanıcı yanlış vaat görür ama yanlış bakiye ALMAZ
/// (yükleme sunucuda).
const Map<String, int> kPackDisplayAmounts = {
  'rytho_tokens_small': 100,
  'rytho_tokens_medium': 300,
  'rytho_tokens_large': 1000,
};

/// Bedel satırının şablonunda sayıların GEÇTİĞİ SIRA — tek tek anılan
/// özellikler. Dördüncü sayı ("derin raporlar ve yüz okuma") tek bir
/// özellik değil, geri kalanların ÖZETİ; o yüzden listede yok.
/// ⚠️ SIRA ŞABLONDAN OKUNUR, alfabetik ya da sunucudaki tanım sırası
/// DEĞİL. Bir tur boyunca `['chat', 'dyad', 'iching']` yazıyordu ve bu
/// dosyanın kendi docstring'i ("sırayla sohbet · I Ching · ikili") tam
/// tersini söylüyordu — yani yorum doğruydu, sabit yanlıştı. Sonuç
/// ekranda İ Ching ile ikili dinamiğin bedelleri YER DEĞİŞMİŞ görünüyordu
/// (2 ve 3 takas). Bedeli tek kaynağa bağlamak için yazılan kod, tam da
/// kullanıcıya yanlış sayı gösteren bir yalan üretiyordu.
const List<String> _kBedelSirasi = ['chat', 'iching', 'dyad'];

/// Mağazadaki bedel satırı — sayılar SUNUCUDAN gelen `costs` haritasından.
///
/// NEDEN (ölçüldü): bedel gerçeğinin kanonik kaynağı sunucudaki
/// `core/wallet.py` `TOKEN_COSTS` tablosu ve o tablo `/billing/wallet`
/// yanıtının `costs` alanıyla ekrana kadar GELİYOR — [WalletStatus.costs]
/// onu ayrıştırıyordu ama hiçbir yüzey kullanmıyordu. Ekranda görünen
/// rakamlar elle yazılmış bir çeviri dizesiydi (`tokenCostsNote`), yani
/// bedel gerçeğinin İKİNCİ bir kaynağı vardı.
///
/// ⚠️ Bu notun ilk hâli ayrışmanın "SESSİZ" olduğunu yazıyordu ve o
/// gerekçe YANLIŞTI — ölçüldü (2026-10-02, mutasyon): `TOKEN_COSTS`
/// içinde `chat` 1→4 yapılınca
/// `backend/tests/test_honesty.py::TestJetonIddialari
/// ::test_magazadaki_bedel_satiri_koddaki_bedellerle_ayni` KIRMIZI oluyor;
/// o bekçi iki ARB dosyasındaki her sayıyı kendi etiketinin yanında
/// çivilemiş durumda. Yani depoda ayrışma sessiz DEĞİL.
///
/// Sessiz olan şey başka ve onarımın gerçek gerekçesi bu: o bekçi HEAD'i
/// ölçüyor, CİHAZDAKİ PAKETİ ölçemez. Sunucu ayrı dağıtılıyor (backend
/// rev ↔ sürüm kodu bağımsız), yani `TOKEN_COSTS` bir backend dağıtımıyla
/// değiştiği an kurulu uygulamanın DERLENMİŞ cümlesi eski rakamı
/// söylemeye devam eder ve bunu hiçbir test göremez — mağaza ekranı,
/// kullanıcının harcamadan önce bedeli okuduğu yüzey olduğu için de
/// yanlış sayı doğrudan para kararını etkiler. Satırı sunucudan üretmek
/// bu pencereyi kapatıyor.
///
/// NEDEN burada biçimlendirme (dize parametrelendirmek yerine):
/// `tokenCostsNote` bugün parametresiz bir cümle ve `lib/l10n/` üretilen
/// paylaşımlı dosyalar — doğru çözüm ARB girdisini yer tutuculu hale
/// getirmek ve bu tur onu ÖNERİYOR. O girdi gelene kadar satır şablonun
/// sayılarını sunucudan gelenlerle değiştirerek kuruluyor; yer tutucular
/// eklendiğinde bu işlev DÜŞER, çağıran doğrudan
/// `l10n.tokenCostsNote(chat: …, …)` der.
///
/// EŞLEŞTİRME KONUMA bağlı ve bu BİLİNÇLİ bir risk: şablondaki sayılar
/// sırayla sohbet · I Ching · ikili · derin özeti. Sıra iki ARB dosyasında
/// da bu ve `backend/tests/test_honesty.py` her sayıyı kendi etiketinin
/// yanında çivilemiş durumda. Yine de eşleşme ÖLÇÜLMEDEN uygulanmıyor: üç
/// ön koşulun biri tutmazsa (şablonda tam dört sayı yok · haritada tek tek
/// anılan özellikler yok · geri kalan özellikler tek bir bedelde
/// anlaşmıyor) satır HİÇ dokunulmadan döner. O hâlde ekranda derlemenin
/// kendi tablosu görünür — uydurma bir sayı değil, yalnızca sunucu yeniden
/// dağıtıldıysa bayatlayabilecek bir sayı.
String bedelSatiri(String sablon, Map<String, int> bedeller) {
  final sayilar = <int>[];
  for (final ad in _kBedelSirasi) {
    final deger = bedeller[ad];
    if (deger == null) return sablon;
    sayilar.add(deger);
  }

  // Şablon derin raporları TEK sayıyla özetliyor; özet ancak geri kalan
  // TÜM özellikler aynı bedeldeyken doğru. Özellik ADLARI burada
  // sayılmıyor (haritanın kendisinden türetiliyor): sunucuya yeni bir
  // rapor eklendiğinde istemcide güncellenmesi gereken bir liste daha
  // olmasın. Aynı şartı sunucu tarafında `test_honesty.py` da arıyor.
  final digerleri = {
    for (final girdi in bedeller.entries)
      if (!_kBedelSirasi.contains(girdi.key)) girdi.value
  };
  if (digerleri.length != 1) return sablon;
  sayilar.add(digerleri.first);

  final yerler = RegExp(r'\d+').allMatches(sablon).toList();
  if (yerler.length != sayilar.length) return sablon;

  final cikti = StringBuffer();
  var son = 0;
  for (var i = 0; i < yerler.length; i++) {
    cikti.write(sablon.substring(son, yerler[i].start));
    cikti.write(sayilar[i]);
    son = yerler[i].end;
  }
  cikti.write(sablon.substring(son));
  return cikti.toString();
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
      // Kullanıcının vazgeçmesi hata değil; sessiz geçilir. Diğer mağaza
      // hataları l10n'a çevrilir (ham İngilizce metin ekrana çıkmaz).
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code != PurchasesErrorCode.purchaseCancelledError && mounted) {
        mesajci.showSnackBar(
            SnackBar(content: Text(storeErrorText(e, l10n))));
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
    final mesgul = _busyProductId != null;

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
        // şekli gösterirdi.
        leading: IconButton(
          icon: Icon(
              _tamEkranDiyalog(context)
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
                          child: Text(
                              cuzdan.bilinmiyor ? '—' : '${cuzdan.total}',
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
                            enabled: !mesgul,
                            onBuy: () => _buy(urun),
                          ),
                      ]),
              ),

            const SizedBox(height: RythoSpace.md),
            // Bedeller SUNUCUDAN: `cuzdan.costs` boşken (bakiye henüz
            // okunmadı ya da okunamadı) şablon olduğu gibi çizilir —
            // bkz. [bedelSatiri].
            Text(bedelSatiri(l10n.tokenCostsNote, cuzdan.costs),
                style: RythoType.caption),
          ],
        ),
      ),
      ),
    );
  }
}

/// Ekran tam-ekran diyalog olarak mı açıldı?
///
/// `core/api.dart` 402 köprüsü `fullscreenDialog: true` ile açıyor, Sohbet
/// ve Abonelik ekranları ise düz `MaterialPageRoute` ile. Flutter'ın kendi
/// mantığı AppBar'ın OTOMATİK düğmesinde yaşıyor; düğmeyi meşguliyete
/// bağlamak için elle koyduğumuz an o mantığı da elle taşımak gerekti.
bool _tamEkranDiyalog(BuildContext context) {
  final rota = ModalRoute.of(context);
  return rota is PageRoute && rota.fullscreenDialog;
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
        const SizedBox(height: 2),
        Text(l10n.tokenFreeTierWarnBody,
            style: RythoText.body(11.5, color: RythoColors.parchmentDim)),
        const SizedBox(height: RythoSpace.md),
        GoldButton(
          text: l10n.tokenPacksSeePlus,
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PaywallScreen())),
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

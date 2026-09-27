/// Token cüzdanının istemci tarafı.
///
/// ## Model (sunucuyla birebir — bkz. backend/core/wallet.py)
///
/// * `allowance` — abonelikle gelen aylık hak; dönem sonunda yenilenir,
///   DEVREDİLMEZ.
/// * `purchased` — satın alınan paket bakiyesi; aya devreder, hiç yanmaz.
///
/// İstemci hiçbir bakiyeyi KENDİSİ hesaplamaz: tek gerçek
/// `GET /billing/wallet`. Paket adetleri bile sunucuda; buradaki ürün
/// kimlikleri yalnızca mağazadan fiyat çekmek için.
///
/// ## Satın alma yolu
///
/// Paketler consumable: RevenueCat → mağaza → webhook → sunucu cüzdana
/// yükler. Yani satın almanın bitmesiyle bakiyenin sunucuda görünmesi
/// arasında saniyeler olabilir — abonelikteki `_waitForServerEntitlement`
/// yarışının aynısı. Aynı çare uygulanır: kısa aralıklarla yokla, bütçe
/// dolarsa sessizce çık (ödeme cihazda gerçekleşti; kullanıcıyı ödeme
/// ekranına geri göndermek yanlış olur).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'api.dart';
import 'subscription.dart' show billingConfigured, ensureBillingIdentity;

/// Mağazadaki consumable ürün kimlikleri. Sunucudaki `TOKEN_PACKS` ile aynı
/// olmak zorunda; adetler BURADA TUTULMAZ (istemciye güvenilmez).
const List<String> kTokenPackIds = [
  'rytho_tokens_small',
  'rytho_tokens_medium',
  'rytho_tokens_large',
];

/// Sunucudaki cüzdan durumu.
class WalletStatus {
  const WalletStatus({
    required this.allowance,
    required this.purchased,
    required this.monthlyAllowance,
    this.allowanceResetsAt,
    this.costs = const {},
  });

  final int allowance;
  final int purchased;
  final int monthlyAllowance;
  final DateTime? allowanceResetsAt;

  /// Özellik -> token bedeli ("bu okuma 5 token" göstergeleri buradan).
  final Map<String, int> costs;

  int get total => allowance + purchased;

  static const none = WalletStatus(
      allowance: 0, purchased: 0, monthlyAllowance: 0);

  factory WalletStatus.fromJson(Map<String, dynamic> json) {
    final resets = json['allowance_resets_at'] as String?;
    return WalletStatus(
      allowance: (json['allowance'] as num?)?.toInt() ?? 0,
      purchased: (json['purchased'] as num?)?.toInt() ?? 0,
      monthlyAllowance: (json['monthly_allowance'] as num?)?.toInt() ?? 0,
      allowanceResetsAt: resets == null ? null : DateTime.tryParse(resets),
      costs: (json['costs'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          const {},
    );
  }
}

/// Cüzdan durumu — sunucudan.
///
/// Hata durumunda sıfır cüzdan: sağlayıcı hata durumuna GİRMEZ
/// (subscriptionProvider ile aynı duruş). Bakiye göstergesi çizilemedi diye
/// ekran kızarmamalı; sunucu zaten her harcamada gerçeği söylüyor.
final walletProvider = FutureProvider<WalletStatus>((ref) async {
  final dio = ref.watch(apiProvider);
  try {
    final response = await dio.get('/api/v1/billing/wallet');
    return WalletStatus.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  } catch (e) {
    debugPrint('Cüzdan okunamadı: $e');
    return WalletStatus.none;
  }
});

/// Mağazadan ürünleri getiren işlev — TEST DİKİŞİ
/// ([offeringsProvider]'ın `TeklifGetirici`si ile aynı gerekçe).
typedef UrunGetirici = Future<List<StoreProduct>> Function(
    List<String> kimlikler);

/// `null` = üretim yolu.
final urunGetiriciProvider = Provider<UrunGetirici?>((_) => null);

/// Mağazadaki token paketleri (fiyat metinleri mağazadan gelir).
///
/// Sıra [kTokenPackIds] sırasıyla döner: küçükten büyüğe.
///
/// Hata YUTULMAZ ([offeringsProvider] ile aynı gerekçe): boş liste oturum
/// boyunca önbellekte kalıyor ve kullanıcı yeniden deneme düğmesi OLMAYAN bir
/// boşluk görüyordu — `ErrorCard(onRetry: …)` dalı erişilemezdi.
final tokenPacksProvider = FutureProvider<List<StoreProduct>>((ref) async {
  final getirici = ref.watch(urunGetiriciProvider);
  if (getirici == null && !billingConfigured) return const [];
  final products = getirici == null
      ? await Purchases.getProducts(
          kTokenPackIds,
          productCategory: ProductCategory.nonSubscription,
        )
      : await getirici(kTokenPackIds);
  products.sort((a, b) => kTokenPackIds
      .indexOf(a.identifier)
      .compareTo(kTokenPackIds.indexOf(b.identifier)));
  return products;
});

/// Paket satın alır ve sunucu bakiyeyi görene kadar bekler.
///
/// `true` = ödeme tamamlandı (bakiye sunucuda henüz görünmese bile).
Future<bool> purchaseTokenPack(WidgetRef ref, StoreProduct product) async {
  final onceki = ref.read(walletProvider).value?.purchased ?? 0;

  // Kimlik garantisi: anonim kimliğe inen satın alma sunucuda yetim kalır
  // (bkz. subscription.ensureBillingIdentity — Feyza vakası).
  await ensureBillingIdentity();
  await Purchases.purchase(PurchaseParams.storeProduct(product));

  // Webhook'un cüzdana yüklemesini bekle — abonelikteki desenle aynı bütçe.
  const gecikmeler = [
    Duration(milliseconds: 400),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 4),
  ];
  for (final gecikme in gecikmeler) {
    ref.invalidate(walletProvider);
    try {
      final durum = await ref
          .read(walletProvider.future)
          .timeout(const Duration(seconds: 6));
      if (durum.purchased > onceki) return true;
    } catch (_) {
      // Yoklama düşerse beklemeyi sürdür; satın alma hatası değil.
    }
    await Future<void>.delayed(gecikme);
  }
  ref.invalidate(walletProvider);
  return true;
}

/// Kredi paketi satın alma işlevi — TEST DİKİŞİ (`PaketSatinAlici` ile aynı
/// gerekçe: kredi mağazasının mağaza hata dalları ancak `Purchases.purchase`
/// fırlatınca koşuyor ve o eklenti `flutter test` içinde çağrılamaz).
typedef KrediPaketiSatinAlici = Future<bool> Function(
    WidgetRef ref, StoreProduct urun);

final krediPaketiSatinAliciProvider =
    Provider<KrediPaketiSatinAlici>((_) => purchaseTokenPack);

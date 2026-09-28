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

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
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
    this.bilinmiyor = false,
  });

  final int allowance;
  final int purchased;
  final int monthlyAllowance;
  final DateTime? allowanceResetsAt;

  /// Özellik -> token bedeli ("bu okuma 5 token" göstergeleri buradan).
  final Map<String, int> costs;

  /// Bakiye OKUNAMADI — sıfır DEĞİL, BİLİNMİYOR.
  ///
  /// Ayrım B10 onarımının doğurduğu bir riski kapatıyor. Tazeleme artık
  /// her sohbet/rapor/firaset turundan sonra koşuyor, yani tek bir geçici
  /// hata (20 sn zaman aşımı, 429) eskiden neredeyse erişilemeyen bu dala
  /// düşüyor. Sıfır göstermek "jetonun bitti" demektir: 198 jetonu olan
  /// kullanıcı bakiyesinin tükendiğini sanıp mağazaya gider. Ekranlar bu
  /// bayrakta sayı yerine "—" çiziyor — ölçülmeyen söylenmez.
  final bool bilinmiyor;

  int get total => allowance + purchased;

  static const none = WalletStatus(
      allowance: 0, purchased: 0, monthlyAllowance: 0);

  /// Okuma düştü. `none` ile aynı sayıları taşır ama [bilinmiyor] true.
  static const unknown = WalletStatus(
      allowance: 0, purchased: 0, monthlyAllowance: 0, bilinmiyor: true);

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

/// Cüzdanın tazelenmesini tetikleyen SAYAÇ (bulgu B10).
///
/// Harcamayı gören yer `apiProvider`'ın interceptor'ı, ama oradan doğrudan
/// `ref.invalidate(walletProvider)` demek ÇALIŞMA ANINDA
/// `CircularDependencyError` fırlatır: [walletProvider] gövdesinde
/// `ref.watch(apiProvider)` yapıyor, interceptor da `apiProvider`'ın KENDİ
/// ref'ini taşıyor. Açık tür bildirimi bunu KURTARMAZ — o yalnız derleyicinin
/// `top_level_cycle` hatasını kapatır, çalışma anındaki halkayı değil.
///
/// Bu sağlayıcı hiçbir şeyi İZLEMEZ; halkanın bir ucu bu yüzden kopuk kalıyor:
/// interceptor yazar, [walletProvider] okur. Depoda aynı desen 426 ve 409
/// kapıları için zaten var (`forceUpdateProvider`, `deviceConflictProvider`).
///
/// Bayrak DEĞİL sayaç: `bool` ikinci harcamada `true`→`true` olurdu, Riverpod
/// "değişmedi" sayar ve bakiye bir daha tazelenmezdi; bayrağı geri indirecek
/// kimse de yok.
final cuzdanTazelemeProvider = StateProvider<int>((_) => 0);

/// Bu istek sunucuda bakiyeyi DEĞİŞTİRMİŞ olabilir mi?
///
/// İstemci hiçbir bakiyeyi kendisi hesaplamaz (bu dosyanın ilk kuralı); bu
/// işlev yalnızca "bakiyeyi yeniden SORMAK gerekir mi" sorusunu cevaplar.
/// Yanılma yönü bilinçli: fazladan bir `GET /billing/wallet` tek bir Firestore
/// okumasıdır, bayat bakiye ise kullanıcıya gösterilen YANLIŞ SAYIDIR.
///
/// Liste sunucudaki harcama uçlarının aynası (`core/wallet.TOKEN_COSTS` →
/// `api/reports.py`, `api/chat.py`, `api/face_reading.py`). `/reports/` ÖNEK
/// olarak yazıldı, böylece yeni bir rapor ucu kendiliğinden kapsanır. Jeton
/// YÜKLEYEN yol da burada: ortak kodunu giren kullanıcının bakiyesi de o an
/// değişiyor ve o yol da hiç tazelemiyordu.
///
/// `/billing/wallet` listede DEĞİL ve olmamalı: cüzdanın kendi okuması sayacı
/// artırırsa istek sonsuza dönerdi. Bugün ayrıca GET olduğu için de geçmez —
/// iki kapı bilerek üst üste.
bool cuzdanDegismisOlabilir(RequestOptions istek) {
  if (istek.method.toUpperCase() != 'POST') return false;
  // Sorgu dizesi atılıyor: `?x=1` eklenen bir uç eşleşmeyi kaybetmesin.
  final yol = Uri.parse(istek.path).path;
  return yol.startsWith('/api/v1/reports/') ||
      yol == '/api/v1/chat' ||
      yol == '/api/v1/chat/' ||
      yol == '/api/v1/face/reading' ||
      yol == '/api/v1/billing/redeem-code';
}

/// Cüzdan durumu — sunucudan.
///
/// Hata durumunda sıfır cüzdan: sağlayıcı hata durumuna GİRMEZ
/// (subscriptionProvider ile aynı duruş). Bakiye göstergesi çizilemedi diye
/// ekran kızarmamalı; sunucu zaten her harcamada gerçeği söylüyor.
final walletProvider = FutureProvider<WalletStatus>((ref) async {
  // Harcama sayacı İZLENİYOR (bulgu B10): rapor/sohbet/firaset turundan
  // sonra bakiye yeniden okunur. Eskiden okunmuyordu ve bu sağlayıcı
  // autoDispose olmadığı için ilk değer OTURUM BOYUNCA önbellekte
  // kalıyordu — sohbetin AppBar çipi, aynı ekranda harcanan jetonu hiç
  // görmüyordu.
  ref.watch(cuzdanTazelemeProvider);
  final dio = ref.watch(apiProvider);
  try {
    final response = await dio.get('/api/v1/billing/wallet');
    return WalletStatus.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  } catch (e) {
    debugPrint('Cüzdan okunamadı: $e');
    // `none` DEĞİL `unknown`: ikisi de sıfır taşır ama biri "bakiyen yok"
    // diye okunur. Bkz. [WalletStatus.bilinmiyor].
    return WalletStatus.unknown;
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

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'subscription.dart';

/// Okunamamış abonelik durumunu ön plana dönüşte YENİDEN sorar.
///
/// ## Neden var
///
/// `SubscriptionStatus.bilinmiyor` hâli TERMİNAL'di ve bu ölçüldü:
/// [abonelikDurumunuOku] geniş bir yakalamayla `bilinmiyor` DÖNDÜRÜYOR,
/// yani Riverpod için başarılı bir `AsyncData` — hata DEĞİL. Riverpod
/// hatasız bir sağlayıcıyı kendiliğinden yenilemez ve `subscriptionProvider`
/// auto-dispose değil, yani ekranı kapatıp açmak da kurtarmaz. Sonuç: tek
/// bir zaman aşımı ya da 429, yedi yüzeyi (Gökyüzü kişisel kart, BaZi,
/// İ Ching, Doğum Heksagramı, İç Takvim, Yıl Haritası ve Atlas'ın dört
/// karosu) OTURUM BOYUNCA iskelette bırakıyordu. İskelet "veri geliyor"
/// der; hiçbir istek yolda değildir — kilit kartından farklı ama aynı
/// sınıf bir yalan, üstelik çıkışı yok: o iskeletlerde ne hata kartı ne
/// tekrar dene var.
///
/// [abonelikDurumunuOku] içindeki TEK yeniden deneme bunu hafifletti ama
/// kapatmadı: iki deneme de düşerse hâl yine terminal. Kullanıcının elinde
/// kalan tek kurtarma yolu ana ekranda aşağı çekmekti ve BaZi / İ Ching /
/// Atlas içinde kalan kullanıcının bunu bilmesinin yolu yok.
///
/// ## Neden BU mekanizma
///
/// Niçin ön plana dönüş: ağ kesintisinin bittiği an ile kullanıcının
/// uygulamaya dönüşü pratikte aynı olay (uçak modundan çıkmak, tünelden
/// çıkmak, Wi-Fi'ye bağlanmak). `UpdateGateObserver` aynı kancayı aynı
/// gerekçeyle kullanıyor.
///
/// Niçin `ref.invalidate` ve var olan `yetkiDegisimProvider` sayacı DEĞİL:
/// o sayacın adı "yetki DEĞİŞTİ" demek ve onu burada artırmak YANLIŞ bir
/// gerekçe olurdu — hiçbir yetki değişmedi, yalnız cevap okunamadı. Sayaç
/// ayrıca cüzdan tazelemesini de tetikliyor, yani bedeli iki istek olurdu.
///
/// Niçin KOŞULLU: durum okunabildiyse hiçbir şey yapılmaz. Koşulsuz
/// tazeleme her ön plana dönüşte bir `/billing/status` demekti — sağlıklı
/// yolda bedava olan bir onarım, sağlıklı yolu pahalılaştırırdı.
///
/// Niçin tavan YOK: istek yalnız ÖNCEKİ okuma düşmüşken atılıyor ve her
/// ön plana dönüşte en fazla bir kez. Sunucu sürekli düşüyorsa kullanıcı
/// zaten uygulamayı açıp kapatıyor demektir; Riverpod'un kendi retry'ı ise
/// sağlayıcı başına 11 isteğe çıkıyor (ölçüldü, ayrı bir turda onarıldı) —
/// aradaki fark tam olarak bu.
///
/// ⚠️ Kapsamadığı hâl, bilerek: ekranda hâlâ "tekrar dene" düğmesi YOK.
/// İskeletler sessiz kalmaya devam ediyor; kapatılan şey hâlin TERMİNAL
/// olması. Düğme, `PlusHali`nin "cevap yolda" ile "cevap okunamadı"yı
/// tek değere indirmesini çözmeyi gerektiriyor (dördüncü hâl) ve o yedi
/// ekranı birden değiştirir.
class AbonelikKurtarmaGozcusu extends ConsumerStatefulWidget {
  const AbonelikKurtarmaGozcusu({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AbonelikKurtarmaGozcusu> createState() =>
      _AbonelikKurtarmaGozcusuState();
}

class _AbonelikKurtarmaGozcusuState
    extends ConsumerState<AbonelikKurtarmaGozcusu> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!abonelikDurumuKurtarilmali(ref.read(subscriptionProvider))) return;
    ref.invalidate(subscriptionProvider);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Ön plana dönüşte abonelik durumu yeniden sorulmalı mı — SAF karar.
///
/// Saf tutulmasının nedeni depodaki yerleşik gerekçe: sağlayıcıyı
/// koşturmak sahte bir Firebase `User`ı isterdi ([abonelikDurumunuOku] ve
/// `plusHaliniOku` aynı yüzden ayrı).
///
/// Üç hâl ayrı ayrı soruluyor ve ÜÇÜ DE gerekli:
///  * `isLoading`: istek YOLDA. Tazelemek onu iptal edip baştan başlatır,
///    yani ilk çizimi geciktirir ve isteği ikiye çıkarır.
///  * `hasError`: Riverpod zaten kendi yeniden denemesini koşturuyor
///    (`rythoRetry`); üstüne binmek istek selini besler.
///  * `okunabildi`: TEK gerçek tetikleyici. `false` ise cevap gelmiş ama
///    okunamamış ve o hâl kendiliğinden hiç değişmez.
bool abonelikDurumuKurtarilmali(AsyncValue<SubscriptionStatus> durum) {
  if (durum.isLoading || durum.hasError) return false;
  final deger = durum.value;
  if (deger == null) return false;
  return !deger.okunabildi;
}

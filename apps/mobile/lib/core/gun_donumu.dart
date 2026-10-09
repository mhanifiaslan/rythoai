import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

/// Yerel takvim gününün anahtarı — `2026-10-03`.
///
/// NEDEN yerel saat ve UTC DEĞİL: sunucu günlük yüzeyleri kullanıcının
/// `timezone` alanına göre üretiyor (BaZi'nin Liu Ri'si, günün kapısı,
/// günlük okuma) ve kullanıcı "bugün" derken telefonunun takvimini
/// kastediyor. UTC anahtarı UTC+3'te gece yarısı ile 03:00 arasında yanlış
/// gün söylerdi — yani tam da gün dönümünün kaçırıldığı pencerede.
///
/// NEDEN `DateFormat` değil elle doldurma: `intl`in biçimlendiricisi
/// yerelden etkilenir (bu depoda bir kez tarihler yanlış dile düştü) ve bu
/// dize kullanıcıya HİÇ gösterilmiyor — yalnız önbellek anahtarı. Yerelden
/// bağımsız olması bir özellik, eksik değil.
String gunAnahtari(DateTime an) =>
    '${an.year.toString().padLeft(4, '0')}-'
    '${an.month.toString().padLeft(2, '0')}-'
    '${an.day.toString().padLeft(2, '0')}';

/// GÜNLÜK sağlayıcıların önbellek anahtarı.
///
/// NEDEN bu sağlayıcı var: günlük raporlar (`dailyReadingProvider`,
/// `baziReportProvider`, `birthHexagramProvider`) düz `FutureProvider` ve
/// Riverpod'da varsayılan `isAutoDispose = false` — yani sonuç OTURUM
/// BOYUNCA istemci önbelleğinde kalıyordu. Sunucu gün dönünce yeni metin
/// üretebilecek durumdayken ekran dünkü metni göstermeye devam ediyordu:
/// ölçülen belirti "akşam aç, arka plana al, gece yarısını geç, sekmeye
/// dön → dünkü metin". Kullanıcıya göre üç yüzey GÜNLÜK OLMADI.
///
/// NEDEN `autoDispose` DEĞİL — ve bu ayrım bedel taşıyor: `autoDispose`
/// sekmeden her çıkışta sonucu atar, yani aynı günde sekmeye her dönüş yeni
/// bir üretim isteği demek olurdu. Günlük raporlar JETONLU; `autoDispose`
/// onarım değil, bir jeton musluğu olurdu. Doğru değişmez şu: önbellek
/// GÜN İÇİNDE yaşar, gün dönünce ölür.
///
/// NEDEN `family` DEĞİL: anahtarı `family`ye taşımak her çağıran ekranın
/// anahtarı kendi başına hesaplamasını gerektirirdi (üç ekran, üç kopya) ve
/// kopyalar ayrışırdı. Tek bir yazıcı ([GunDonumuGozcusu]) ve tek bir
/// okunan değer var.
final gunAnahtariProvider =
    StateProvider<String>((_) => gunAnahtari(DateTime.now()));

/// Ön plana dönüşte yerel günün değiştiğini fark eden gözcü.
///
/// NEDEN yaşam döngüsü ve zamanlayıcı DEĞİL: gece yarısına kurulan bir
/// `Timer` arka planda askıya alınıyor ve uyandığında kaç gün geçtiğini
/// bilmiyor; ayrıca süreç boyunca bir zamanlayıcı daha taşımak demek.
/// Ölçülen senaryo zaten ön plana DÖNÜŞ (`UpdateGateObserver` aynı kancayı
/// aynı gerekçeyle kullanıyor) — uygulama arka plandayken ekranda
/// gösterilen bir şey yok.
///
/// ⚠️ KAPSAMADIĞI hâl, bilerek ve ölçülmemiş olarak burada yazılı:
/// uygulama ÖN PLANDA tutulurken gece yarısı geçerse bu kanca hiç ateşlenmez
/// ve ekran bir sonraki ön plana dönüşe kadar dünkü metni gösterir. Kapatmak
/// için zamanlayıcı gerekirdi; o pencerenin gerçek hayatta ne kadar
/// yaşandığı ÖLÇÜLMEDİ, o yüzden bedeli ödenmedi.
///
/// [now] yalnız test için: gerçek ağaçta `DateTime.now` kullanılır.
class GunDonumuGozcusu extends ConsumerStatefulWidget {
  const GunDonumuGozcusu({super.key, required this.child, this.now});

  final Widget child;
  final DateTime Function()? now;

  @override
  ConsumerState<GunDonumuGozcusu> createState() => _GunDonumuGozcusuState();
}

class _GunDonumuGozcusuState extends ConsumerState<GunDonumuGozcusu>
    with WidgetsBindingObserver {
  DateTime _simdi() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ⚠️ AÇILIŞTA YAZIM YOK — ve bu bilinçli.
    //
    // Burada bir zamanlar `_bak()` çağrılıyordu; gerekçesi "sağlayıcının
    // varsayılanı gerçek `DateTime.now`u okuyor, test saati enjekte
    // edildiğinde ikisi ayrışır" idi. Yani ÜRETİM KODU, YALNIZ TESTİN
    // enjeksiyonunu uzlaştırmak için sağlayıcıya yazıyordu.
    //
    // Bedeli ölçüldü (yığın izi): `_bak` → `initState` → `_firstBuild`,
    // üstünde bir `ProxyElement.update` zinciri. `initState` ağacın kurulumu
    // SIRASINDA koşar — build dışı DEĞİLDİR — ve oradan `StateProvider`a
    // yazmak `Tried to modify a provider while the widget tree was building`
    // fırlatır. Gözcü bir yeniden kurulum sırasında monte edildiğinde patlıyordu;
    // ilk açılışta sessiz kalması kusuru gizliyordu.
    //
    // ⚠️ `scheduleMicrotask`a ERTELEMEK ÇÖZÜM DEĞİL: ölçüldü, sağlayıcıyı
    // İKİNCİ kez kurduruyor — yani bu dosyanın var olma sebebi olan jeton
    // musluğunu kendi eliyle açıyor (bkz. yukarıda `autoDispose` gerekçesi).
    //
    // Doğru yer varsayılanın kendisi: üretimde `gunAnahtariProvider`ın
    // varsayılanı ZATEN `gunAnahtari(DateTime.now())`, yani uzlaştırılacak
    // bir fark yok. Test sahte saatini `ProviderScope` override'ıyla verir —
    // enjeksiyon testin işi, üretim kodunun değil.
    //
    // `_bak()` asıl işinde duruyor: ön plana DÖNÜŞTE (aşağıda), ki orası
    // build dışıdır ve yazım güvenlidir.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _bak();
  }

  /// Anahtar yalnız GERÇEKTEN değiştiyse yazılır.
  ///
  /// Koşulsuz yazmak `StateProvider`ı aynı değerle de bildirirdi ve günlük
  /// sağlayıcılar ön plana her dönüşte yeniden kurulurdu: sekme değiştirip
  /// geri gelmek jeton harcatan bir üretim isteği demek olurdu. Kapı tam
  /// olarak bunu kesiyor.
  void _bak() {
    final bugun = gunAnahtari(_simdi());
    final notifier = ref.read(gunAnahtariProvider.notifier);
    if (notifier.state == bugun) return;
    notifier.state = bugun;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

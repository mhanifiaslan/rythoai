import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider;

import '../features/shell/app_shell.dart' show shellTabProvider;
import 'api.dart' show apiProvider;
import 'partner_referrer.dart';
import 'providers.dart';

/// Gelen bağlantıların yakalanması — İKİ tür.
///
/// * `/i/{kullanıcıadı}` → **davet**: arkadaş ekleme sayfasını açar.
/// * `/r/{KOD}` → **ortak (affiliate) kodu**: sessizce sunucuya yazılır,
///   ekran değiştirmez (bkz. [partnerCodeFromLink], `partner_referrer.dart`).
///
/// İkisi aynı host kümesini paylaşıyor ve yalnız ilk yol parçasıyla
/// ayrılıyor; bu yüzden her iki ayrıştırıcının diğerinin yolunu REDDETTİĞİ
/// testle sabitlendi (`partner_referrer_test.dart`).
///
/// **İki alan adı: biri üretir, ikisi de çözülür.**
///
/// Kendi alan adı (`rytho.app`) 2026-09-15'te bağlandı. Yeni bağlantılar
/// YALNIZ onunla üretilir, ama eski Firebase Hosting adresi
/// (`rhytoai.web.app`) çözülmeye devam eder ve edecek:
///
/// * Eski adresle paylaşılmış davetler elden ele dolaşıyor olabilir;
///   bir gün sonra ölmeleri kullanıcının hatası değil bizim olurdu.
/// * `rhytoai.web.app` Firebase'in varsayılan adresi olarak yaşamaya
///   devam ediyor, kapatılamıyor.
/// * Mağazadaki eski paket hâlâ eski host'u dinliyor; yeni adres onda
///   tarayıcıda açılır ve karşılama sayfası mağazaya yönlendirir.
///
/// AndroidManifest de İKİ `intent-filter` taşır; biri silinirse o host
/// için App Links doğrulaması düşer ve bağlantı tarayıcıda açılır.
///
/// Firebase Dynamic Links Ağustos 2025'te kapandı. Yerine platformların
/// kendi mekanizmaları kullanılıyor:
/// - Android **App Links**: `/.well-known/assetlinks.json` ile doğrulanır.
/// - iOS **Universal Links**: `/.well-known/apple-app-site-association`.
///
/// Doğrulama tamamlandığında bağlantı uygulamayı DOĞRUDAN açar; uygulama
/// kurulu değilse tarayıcıda karşılama sayfası görünür ve mağazaya yönlendirir.
const String kInviteHost = 'rytho.app';

/// Çözülen host'lar. Yeni bağlantılar [kInviteHost] ile üretilir; bu küme
/// yalnızca GELEN bağlantıyı tanımak için.
const Set<String> kInviteHosts = {'rytho.app', 'rhytoai.web.app'};

/// Davet bağlantısı. Kopyalanıp paylaşılan metin bu.
String inviteLinkFor(String username) =>
    'https://$kInviteHost/i/${Uri.encodeComponent(username)}';

/// Bağlantıdan çıkarılan kullanıcı adı; davet değilse ``null``.
///
/// Ayrı ve saf bir fonksiyon: bağlantı ayrıştırma en kolay bozulan yer ve
/// platform olmadan test edilebilmeli.
String? usernameFromInviteLink(Uri uri) {
  if (!kInviteHosts.contains(uri.host)) return null;

  // `pathSegments` yüzde kodlamasını ZATEN çözer. Bir kez daha çözmek hem
  // yanlış (`%2520` boşluğa döner) hem tehlikeli: bozuk kodlama içeren bir
  // bağlantıda `decodeComponent` istisna fırlatıyor ve paylaşılan hatalı bir
  // bağlantı uygulamayı düşürüyordu.
  final List<String> parcalar;
  try {
    parcalar = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  } catch (e) {
    debugPrint('Bağlantı ayrıştırılamadı: $e');
    return null;
  }
  if (parcalar.length < 2 || parcalar.first != 'i') return null;

  final username = parcalar[1].trim().toLowerCase();
  // Kural kontrolü: bağlantı dışarıdan gelir, içerdiği değere güvenilmez.
  // Geçersiz bir ad arkadaş ekleme kutusuna doldurulmamalı.
  if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username)) return null;
  return username;
}

/// Ortak bağlantısından (`https://rytho.app/r/KOD`) çıkarılan kod; değilse
/// ``null``.
///
/// Bu yol YALNIZ uygulama zaten kuruluyken iş görür (Android'de App Links
/// `/r/` intent-filter'ı, iOS'ta Universal Link — AASA `/r/*`). Kurulu
/// değilken link tarayıcıda açılır ve platformlar AYRILIR:
/// - Android: `web/r/index.html` Play'e `&referrer=` ile yönlendirir, kod
///   kurulumdan sonra Install Referrer'dan okunur (`partner_referrer.dart`).
/// - iPhone: sayfa Play'e YÖNLENDİRMEZ, Install Referrer'ın dengi yok.
///   App Store kimliği tanımlıyken "kur, hesabını aç, bağlantıya bir kez
///   daha dokun" der ve kod o ikinci dokunuşta BU yoldan sayılır (oturum
///   ister; 401 terminal sayılmaz). Kimlik boşken sayfa kodun taşınamadığını
///   yazar — o kurulum hiç sayılmaz.
/// Sayılan her yol aynı uca çıkar.
///
/// Desen ve büyük harfe çevirme `partner_referrer.dart` ile paylaşılıyor —
/// backend `partner_service._KOD_DESENI` ve sayfanın kendi kopyası ile
/// birlikte dört yerin birebir aynı kalması gerekiyor; `test_web_seo.py`
/// sayfa ile backend'i, `partner_referrer_test.dart` istemci tarafını bağlar.
String? partnerCodeFromLink(Uri uri) {
  if (!kInviteHosts.contains(uri.host)) return null;

  final List<String> parcalar;
  try {
    parcalar = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  } catch (e) {
    debugPrint('Bağlantı ayrıştırılamadı: $e');
    return null;
  }
  if (parcalar.length < 2 || parcalar.first != 'r') return null;

  final kod = parcalar[1].trim().toUpperCase();
  if (!kOrtakKodDeseni.hasMatch(kod)) return null;
  return kod;
}

/// Bekleyen davet: bağlantı yakalandı, arkadaş ekleme sayfası henüz açılmadı.
///
/// Ayrı bir durum olarak tutuluyor çünkü bağlantı uygulama açılırken de
/// gelebilir — o anda kullanıcı henüz oturum açmamış veya onboarding
/// tamamlanmamış olabilir. Davet, kullanıcı hazır olana kadar bekler.
class PendingInvite extends StateNotifier<String?> {
  PendingInvite() : super(null);

  void set(String username) => state = username;

  /// Ele alındı; tekrar açılmasın.
  void clear() => state = null;
}

final pendingInviteProvider =
    StateNotifierProvider<PendingInvite, String?>((_) => PendingInvite());

/// Bağlantı dinleyicisini kurar.
///
/// [billingIdentityProvider] ve [notificationSyncProvider] ile aynı desen:
/// izlenmezse hiç kurulmaz.
final deepLinkProvider = Provider<void>((ref) {
  final appLinks = AppLinks();

  void ele(Uri? uri) {
    if (uri == null) return;

    // Ortak kodu ÖNCE denenir. Yollar çakışmıyor (`/i/` ve `/r/`), ama
    // sıranın açık olması üçüncü bir yol eklendiğinde kazayla yutulmasını
    // önler. Bekleyen-niyet deseni KULLANILMIYOR: davet bir EKRAN açmak
    // ister (arkadaş sekmesi), ortak kodu ise sessiz bir sunucu kaydıdır —
    // kullanıcıyı başka sekmeye atlatmak sebebi görünmeyen bir sıçrama olur.
    final ortakKod = partnerCodeFromLink(uri);
    if (ortakKod != null) {
      // Ateşle-unut: `applyPartnerCode` asla fırlatmaz. Oturum yoksa uç
      // 401 döner ve o durum BİLEREK terminal sayılmaz — kullanıcı giriş
      // yapıp bağlantıya yeniden dokunduğunda kod işlenir. (Kodu cihazda
      // bekletmiyoruz: atıf uid başına yazılıyor ve hesabı olmayan
      // kullanıcıya bağlanacak bir şey yok.)
      applyPartnerCode(ref.read(apiProvider), ortakKod);
      return;
    }

    final username = usernameFromInviteLink(uri);
    if (username == null) {
      debugPrint('Tanınmayan bağlantı: $uri');
      return;
    }
    // Kendi davetini açmak anlamsız; sessizce yok say.
    ref.read(pendingInviteProvider.notifier).set(username);
    // Arkadaşlar sekmesine geç ki davet nerede ele alınacaksa orada görünsün.
    ref.read(shellTabProvider.notifier).state = 2;
  }

  // Uygulama kapalıyken gelen bağlantı.
  appLinks.getInitialLink().then(ele).catchError((Object e) {
    debugPrint('Açılış bağlantısı okunamadı: $e');
    return null;
  });

  // Uygulama açıkken gelen bağlantı.
  final abonelik = appLinks.uriLinkStream.listen(
    ele,
    onError: (Object e) => debugPrint('Bağlantı akışı hatası: $e'),
  );
  ref.onDispose(abonelik.cancel);
});

/// Bekleyen daveti ele alınabilir mi?
///
/// Oturum açılmamış ya da onboarding bitmemişse davet bekletilir: kullanıcı
/// adı kutusunu doldurup kaydolmamış birine göstermek işe yaramaz.
bool inviteReady(WidgetRef ref) {
  if (FirebaseAuth.instance.currentUser == null) return false;
  final profile = ref.read(profileProvider).value;
  return profile != null && profile['onboardingCompleted'] == true;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/discovery.dart';
import '../../core/motivation.dart';
import '../../core/providers.dart';
import '../../core/sound.dart';
import '../../core/subscription.dart'
    show
        introPaywallShown,
        markIntroPaywallShown,
        paywallKarariVerilebilir,
        subscriptionProvider;
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';
import '../../widgets/nebula_widgets.dart';
import '../../widgets/reading_card.dart';
import '../../widgets/star_burst.dart';
import '../../widgets/token_chip.dart';
import '../shell/app_shell.dart' show shellTabProvider;
import '../paywall/paywall_screen.dart';
import '../paywall/ozellik_katalogu.dart';
import '../paywall/plus_locked_card.dart';
import 'calendar_strip.dart';
import 'sign_story_screen.dart';
import 'sky_now_screen.dart';
import '../../widgets/basis_sheet.dart';
import '../chat/chat_screen.dart';
import '../../core/api.dart' show friendlyError;
import '../profile/diary_screen.dart' show DiaryScreen;
import '../../core/notifications.dart'
    show ensureNotificationPermissionAsked, pendingNotificationProvider;
import '../../l10n/app_localizations.dart';

/// Ana ekranın ÖN-ÇEKECEĞİ burç anahtarları (P2-2).
///
/// Dönen liste bilerek **tek elemanlı**: yalnız kullanıcının kendi burcu.
/// Halkada o burç zaten en başta duruyor (aşağıdaki `signOrder`) ve
/// kullanıcının kendi burcu, hakkında bir şey ÖLÇÜLEBİLEN tek burç —
/// dokunma dağılımı ölçülmedi, o yüzden "çoğu dokunuş buraya" diye bir
/// gerekçe YAZILMIYOR. Kalanlar dokunulunca çekilir.
///
/// ⚠️ On iki burcu birden ön-çekmek on iki PARALEL LLM tetiği demek olurdu.
/// Yorum sunucuda dönem başına burç başına bir kez üretiliyor; soğuk
/// önbellekte on iki eşzamanlı çağrı hem kotayı hem maliyeti bir kullanıcının
/// tek açılışına yıkar. Kalan on bir burç dokunulduğunda çekilir.
///
/// Burç bilinmiyorsa (profilde `sunSign` yok, doğum verisi eksik) liste BOŞ:
/// hesaplanmamış bir şey için istek atılmaz.
List<String> onCekilecekBurclar(int kullaniciBurcIndeksi) =>
    kullaniciBurcIndeksi < 0 || kullaniciBurcIndeksi >= kSignKeys.length
        ? const []
        : [kSignKeys[kullaniciBurcIndeksi]];

/// GÖKYÜZÜ — **bugün** ekranı.
///
/// ## Yeniden kurgulandı
///
/// Önceki hâli ~1500 px uzunluğundaydı ve kullanıcı tarifi şuydu: "tamamen
/// karışık bir yer". Sebebi, bir bakışta görülecek şeyle üç dakika okunacak
/// şeyin aynı seviyede, tek kaydırma sütununda durmasıydı.
///
/// Üç şey akıştan çıktı:
///
/// * **Burç yorumu** → hikâye okuyucusu ([SignStoryScreen]). Şerit zaten
///   hikâye halkası gibi görünüyordu; artık öyle davranıyor.
/// * **Gökyüzü çarkı** → [SkyNowScreen]. Akışta tek satırlık özet kaldı.
/// * **Tanıtım bandı** → silindi. Satış mesajı [PlusLockedCard]'da, yani
///   kullanıcının kilitli içeriğe baktığı yerde duruyor.
///
/// Kalan yapı iki bölüm: bugün senin için · şu an. (Araçlar Atlas'a
/// taşındı — Revize R6, madde 11.)
class SkyScreen extends ConsumerStatefulWidget {
  const SkyScreen({super.key});

  @override
  ConsumerState<SkyScreen> createState() => _SkyScreenState();
}

class _SkyScreenState extends ConsumerState<SkyScreen> {
  int? _selectedSign;
  bool _streakTouched = false;
  bool _introPaywallHandled = false;

  /// Seri BU oturumda büyüdüyse yeni sayı (R12-C1) — rozet vurgusu bir kez
  /// oynar. Null: kutlanacak bir şey yok.
  int? _streakYeni;

  /// Keşif halkası BU oturumda 3/3'e ulaştı (OB4) — yıldız patlaması bir
  /// kez oynar.
  bool _kesifKutlama = false;

  /// Hikâyesi ön-çekilmiş burç indeksi (P2-2). Bu ekran profilin her
  /// yayınında yeniden çiziliyor; bayrak olmasa aynı istek her karede
  /// yeniden kurulurdu.
  int? _onCekilenBurc;

  /// Kullanıcının kendi burcunun hikâyesini ekran açılırken ister (P2-2).
  ///
  /// ÖLÇÜLEN kusur: halka ana ekranda istek BİLE atmıyordu. [ZodiacChip] düz
  /// bir `StatelessWidget` ve gövdesinde tek `ref.watch` yok; istek ancak
  /// [SignStoryScreen] inşa edilince doğuyor. Yani halkaya dokunurken
  /// görülen bekleyiş "yavaş yükleme" değil, HİÇ BAŞLAMAMIŞ bir yüklemeydi.
  ///
  /// İstek `build` içinden değil kare SONUNDAN kurulur: sağlayıcıyı çizim
  /// sırasında kurmak bir yan etki ve bu ekran sık yeniden çiziliyor.
  /// Sağlayıcı auto-dispose DEĞİL (Riverpod varsayılanı), yani bir kez
  /// kurulması yeter — hikâye ekranı açıldığında yanıt önbellekte hazır.
  ///
  /// ⚠️ Aynı sebeple önbelleğe YALNIZ BAŞARI konur: auto-dispose olmayan bir
  /// sağlayıcıda, kimsenin görmediği bir hata oturum boyunca kalır
  /// (CLAUDE.md §5). Ön-çekme düşerse izini siler; yoksa kullanıcı halkaya
  /// dokunduğunda hikâye ekranı İSTEK ATMADAN hata kartı çizerdi — oysa
  /// ön-çekme olmasaydı o dokunuş taze bir istek atardı, yani hızlandırmak
  /// için eklenen şey tek başına bir gerileme olurdu. Döngü riski yok:
  /// [_onCekilenBurc] ön-çekmeyi burç başına bir kez kuruyor ve dinleyicisi
  /// olmayan bir sağlayıcı geçersizleştirildiğinde kendiliğinden koşmaz.
  void _onCekBurcHikayesi(int burcIndeksi) {
    if (_onCekilenBurc == burcIndeksi) return;
    final anahtarlar = onCekilecekBurclar(burcIndeksi);
    if (anahtarlar.isEmpty) return;
    _onCekilenBurc = burcIndeksi;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final anahtar in anahtarlar) {
        ref.read(signHoroscopeProvider(anahtar).future).then((_) {},
            onError: (Object _) {
          if (!mounted) return;
          ref.invalidate(signHoroscopeProvider(anahtar));
        });
      }
    });
  }

  String _greeting(AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return l10n.greetingMorning;
    if (hour >= 12 && hour < 18) return l10n.greetingDay;
    if (hour >= 18 && hour < 23) return l10n.greetingEvening;
    return l10n.greetingNight;
  }

  /// Günlük seri: profil geldiğinde bir kez işlenir.
  ///
  /// R12-C1: dönen sayı artık atılmıyor — seri BÜYÜDÜYSE rozet vurgusu +
  /// mini yıldız patlaması + ses. Sıfırlanma (5→1) kutlanmaz; bugünkü
  /// ikinci açılış aynı sayıyı döndürür ve sessiz kalır.
  void _touchStreak(Map<String, dynamic> profile) {
    if (_streakTouched) return;
    _streakTouched = true;
    // OB4: günün gökyüzünü açmak keşif halkasının ilk dilimi.
    ref.read(discoveryProvider.notifier).mark(DiscoveryTask.daily);
    final onceki = (profile['streakCount'] as num?)?.toInt() ?? 0;
    DailyStreak.touch(profile).then<void>((yeni) {
      if (!mounted || yeni <= onceki) return;
      SoundFx.streak();
      setState(() => _streakYeni = yeni);
    }).catchError((_) {});
  }

  /// Tanıtım paywall'ı: hesap ömründe **bir kez**, kullanıcı ilk değerini
  /// gördükten sonra.
  ///
  /// Onboarding biter bitmez göstermek erken terk oranını artırıyor; hiç
  /// göstermemek ise kilitli karta dokunmayan kullanıcıya Rytho+'ın varlığını
  /// hiç duyurmuyor. Bu yüzden tetikleyici, ücretsiz günlük yorumun ekrana
  /// gelmesidir.
  ///
  /// Yorum paylaşımı akıştan hikâye okuyucusuna taşındı — paylaşılacak metnin
  /// tamamı orada görünüyor (bkz. sign_story_screen.dart).

  /// İlk değer ekrana geldikten sonraki tek seferlik akış.
  ///
  /// Sıra önemli: paywall gösterilecekse bildirim izni BU AÇILIŞTA
  /// istenmez. Kullanıcıyı arka arkaya iki modalla karşılamak ikisinin de
  /// reddedilme olasılığını artırır; bildirim izni bir sonraki açılışta
  /// sorulur ve o zaman tek başına görünür.
  void _maybeShowIntroPaywall() {
    if (_introPaywallHandled) return;
    _introPaywallHandled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Karar ancak GERCEK bir cevapla verilir; iki eksik hal de bekler:
      // (KT3) saglayici HALA YUKLENIYOR — `.value` null doner ve eski
      // `?? false` bunu "abone degil" sayiyordu; (ilkacilis-2) yukleme bitti
      // ama istek DUSTU — genis catch `AsyncData(none)` uretiyordu, yani
      // "abone degil" ile "bilmiyorum" ayirt edilemiyordu. Ikisinde de
      // abonenin/denemedekinin yuzune paywall aciliyor ve hesap omrundeki
      // TEK gosterim bosa yaniyordu. Bu acilista hic gosterme (bayrak
      // YAKILMAZ); bir sonraki acilis gercek cevapla karar verir.
      final durum = ref.read(subscriptionProvider);
      if (!paywallKarariVerilebilir(durum)) {
        await ensureNotificationPermissionAsked();
        return;
      }
      final abone = durum.value?.active ?? false;
      final paywallGosterilecek =
          !abone && !(await introPaywallShown());

      if (paywallGosterilecek) {
        await markIntroPaywallShown();
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const PaywallScreen(),
          fullscreenDialog: true,
        ));
        return;
      }

      // Bildirim izni: kullanıcı ilk değeri gördü, artık neyin bildirimini
      // alacağını biliyor. OT3: bayrak istekten SONRA yazılır (ortak
      // yardımcı) — eski sıra, diyaloğu kapatan kullanıcıya bir daha hiç
      // sorulmaması demekti.
      await ensureNotificationPermissionAsked();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final daily = ref.watch(dailyReadingProvider);
    // ÜÇ DURUMLU kapı (P2): `daily`nin `null`ı artık YALNIZ "abone değil"
    // demek. "Henüz bilmiyorum" hâli AYRI çizilir — kilit değil iskelet.
    final plusKapisi = ref.watch(raporKapisiProvider);
    final profile = ref.watch(profileProvider).value ?? {};
    if (profile.isNotEmpty) _touchStreak(profile);

    // OB4: 3/3 kutlaması — günde bir (bayrak notifier'da). Ses + snackbar
    // burada, halka üstündeki yıldız patlaması _kesifKutlama ile çizimde.
    final kesif = ref.watch(discoveryProvider);
    ref.listen(discoveryProvider, (once, simdi) {
      if (!simdi.justCompleted || _kesifKutlama) return;
      ref.read(discoveryProvider.notifier).ackCelebration();
      setState(() => _kesifKutlama = true);
      SoundFx.success();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.discoveryComplete)));
    });

    final sunSign = profile['sunSign'] as String?;
    final userSignIndex = signIndexOf(sunSign);
    _onCekBurcHikayesi(userSignIndex);
    final selected = _selectedSign ?? (userSignIndex >= 0 ? userSignIndex : 0);
    final streak = (profile['streakCount'] as num?)?.toInt() ?? 0;

    // Burç şeridi: kullanıcının burcu önde, kalanı sırayla.
    final signOrder = [
      if (userSignIndex >= 0) userSignIndex,
      for (var i = 0; i < 12; i++)
        if (i != userSignIndex) i,
    ];

    var stagger = 0;
    Duration next() => Duration(milliseconds: 70 * stagger++);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: RythoColors.magenta,
          backgroundColor: RythoColors.inkLight,
          onRefresh: () async {
            // BEKLENİR: `invalidate` anında dönüyordu, dolayısıyla halka
            // hemen kayboluyor ve kullanıcı "olmadı" sanıp arka arkaya
            // çekiyordu — her çekiş dört isteği yeniden ateşliyordu.
            // Beklemek hem dürüst geri bildirim hem istek selinin freni.
            await Future.wait([
              // signalsProvider bu kaynaktan türetiliyor; kaynak tazelenir.
              ref.refresh(signalsDataProvider.future),
              ref.refresh(dailyReadingProvider.future),
              // Abonelik durumu da tazelensin: satın alma sonrası webhook
              // sunucuya islenene kadar kisa bir gecikme olabiliyor.
              ref.refresh(subscriptionProvider.future),
              // Takvim şeridi de tazelensin: sunucu penceresi gün dönümünde
              // kayıyor ve abonelik değişince kilit satırları açılıyor.
              ref.refresh(transitCalendarProvider.future),
            ]).catchError((_) => const <Object?>[]);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: RythoSpace.dockClearance),
            children: [
              const SizedBox(height: RythoSpace.sm),
              _Header(
                greeting: _greeting(l10n),
                name: profile['displayName'] ?? l10n.defaultUserName,
                photoUrl: profile['photoUrl'],
                onAvatarTap: () =>
                    ref.read(shellTabProvider.notifier).state = 3,
              ).animate(delay: next()).fadeIn(duration: 360.ms).slideY(
                  begin: 0.08, curve: Curves.easeOutCubic),
              const SizedBox(height: RythoSpace.lg),

              // Burç şeridi — HİKÂYE halkası. Dokunma tam ekran okuyucu açar.
              // Yeri SABİT: her zaman başlığın hemen altında, sosyal medya
              // durum çubuğu gibi. Hiçbir bölüm (sinyaller dahil) bunu aşağı
              // itmez — R2-S6'da bir kez itilmişti, geri alındı.
              //
              // Eskiden bu şerit bir "seçici"ydi: dokunulunca 200 px aşağıdaki
              // bölümün metni değişiyordu, arada da alakasız bir tanıtım bandı
              // duruyordu. Görünüşü hikâye, davranışı sekme filtresiydi.
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: RythoSpace.lg),
                  itemCount: signOrder.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: RythoSpace.md),
                  itemBuilder: (_, i) => ZodiacChip(
                    signIndex: signOrder[i],
                    selected: signOrder[i] == selected,
                    onTap: () => _openStory(signOrder, i),
                  ),
                ),
              ).animate(delay: next()).fadeIn(duration: 360.ms).slideY(
                  begin: 0.08, curve: Curves.easeOutCubic),

              // Takvim şeridi (R5-6) — burç şeridinin HEMEN ALTINDA, aynı
              // ölçü diliyle. "Önündeki 30 gün" artık Atlas'ın içinde
              // aranan bir liste değil, ana ekranda duran bir zaman
              // çizgisi. Ücretsiz hesapta da görünür: tarih ve tema
              // gerçek, kilitli olan yalnız okuma.
              const SizedBox(height: RythoSpace.sm),
              const CalendarStrip()
                  .animate(delay: next())
                  .fadeIn(duration: 360.ms)
                  .slideY(begin: 0.08, curve: Curves.easeOutCubic),

              // ---------- SİNYALLER (R2-S3) ----------
              // "Rytho bugün senin için fark etti": sorulmadan konuşan
              // astrolog. Bölüm kendi kendini gizler (veri yok / hata /
              // doğum kaydı eksik) — ana ekran sinyalsiz de ayakta durur.
              const _SignalsSection()
                  .animate(delay: next())
                  .fadeIn(duration: 360.ms)
                  .slideY(begin: 0.06, curve: Curves.easeOutCubic),

              // ---------- BUGÜN SENİN İÇİN ----------
              // Seri rozeti başlıktan buraya indi (R2-S3): motivasyon
              // sinyaller, seri yan ürün — "neden her gün açayım"ın cevabı
              // artık rozet değil, gökyüzünün bugün söyledikleri.
              SectionHeader(
                l10n.todaysInsight,
                // `SectionHeader`'ın ek bilgisi kendi içinde de esnemeliydi:
                // tarih + keşif halkası + seri rozeti esnemeyen bir `Row`du
                // ve üçü birden dar ekranda kendi satırından taşıyordu.
                // `Wrap` gerektiğinde rozetleri alt satıra indirir.
                trailing: Wrap(
                    spacing: RythoSpace.sm,
                    runSpacing: RythoSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                  Text(
                    // Tarih biçimi de dile bağlı: sabit 'tr_TR' İngilizce
                    // arayüzde Türkçe ay adı gösteriyordu.
                    DateFormat('d MMMM',
                            Localizations.localeOf(context).toLanguageTag())
                        .format(DateTime.now()),
                    style: RythoType.dataSmall,
                  ),
                  _DiscoveryRing(state: kesif, celebrate: _kesifKutlama),
                  _StreakRozet(streak: streak, celebrate: _streakYeni),
                ]),
              ).animate(delay: next()).fadeIn(duration: 360.ms),

              // Genel burç kartı BURADAN KALKTI (R3-2, cihaz bulgusu):
              // hikâye halkasındaki metnin aynısıydı — aynı sayfada iki kez
              // durması "tekrarlı bilgi" şikayetinin kaynağıydı. Genel yorum
              // artık YALNIZ halkada; içgörü başlığı kişiye özel okumanın.
              //
              // Rytho+: kişiye özel okuma. Abone değilse istek atılmaz;
              // kilitli kart gösterilir ve paywall ancak dokununca açılır.
              //
              // Abonelik cevabı GELMEDEN kilit kartı çizmek, parasını ödemiş
              // kullanıcıya her açılışta "abone değilsin" demekti. İskelet
              // okumanın HACMİNİ gösterir, hükmünü vermez — ne kilit ne
              // içerik. Tersi de yapılmadı: "yükleniyorsa abone varsay"
              // abone olmayana bir an kilitsiz kart gösterirdi.
              if (plusKapisi == PlusHali.bilinmiyor)
                const SkeletonPanel(height: 132)
              else
                daily.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(RythoSpace.xl),
                    child: Center(child: AstrolabeSpinner()),
                  ),
                  error: (e, _) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
                    child: ErrorCard(
                      message: friendlyError(e, l10n),
                      onRetry: () => ref.invalidate(dailyReadingProvider),
                    ),
                  ),
                  data: (data) {
                    // Kullanıcı ilk değerini gördü (kilitli kart da değer
                    // anlatır): tanıtım paywall'ı buradan tetiklenir —
                    // eskiden genel burç kartındaydı, kart kalktı (R3-2).
                    _maybeShowIntroPaywall();
                    return data == null
                        ? PlusLockedCard(
                            // Katalog üyesi: emoji buradan gelir ve
                            // paywall hangi özellikten açıldığını bilir.
                            ozellik: PlusOzellik.daily,
                            title: l10n.personalReadingLocked,
                            description: userSignIndex < 0
                                ? l10n.personalReadingLockedBody
                                : l10n.personalReadingLockedBodyWithSign(
                                    signDisplayName(l10n, userSignIndex)),
                          )
                        : ReadingCard(
                            label: () {
                              // Sunucu burç adını Türkçe döndürüyor; ekrana
                              // ham basmak İngilizce arayüzde "Oğlak" yazdırıyordu.
                              final gunes =
                                  localizedSignName(l10n, data['sun_sign'] as String?);
                              final ay =
                                  localizedSignName(l10n, data['moon_sign'] as String?);
                              final yukselen =
                                  localizedSignName(l10n, data['ascendant'] as String?);
                              final parcalar = <String>[
                                if (gunes.isNotEmpty) '☀️ $gunes',
                                if (ay.isNotEmpty) '🌙 $ay',
                                if (yukselen.isNotEmpty) '⬆️ $yukselen',
                              ];
                              return parcalar.join(' · ');
                            }(),
                            title: l10n.personalReadingTitle,
                            body: data['reading'] ?? '',
                            glow: true,
                          )
                            .animate(delay: next())
                            .fadeIn(duration: 380.ms)
                            .slideY(begin: 0.06, curve: Curves.easeOutCubic)
                            .then()
                            .shimmer(
                                duration: 900.ms,
                                color: RythoColors.gold
                                    .withValues(alpha: 0.12));
                  },
                ),

              // "ŞU AN" bölümü Atlas'a taşındı (R3-2): gökyüzü durumu
              // haritanın yanında yaşar; bu ekran "bugün senin için"
              // anlatısına odaklandı.

              // GÜNLÜĞÜM kartı BURADAN KALKTI (1.5.1+18 cihaz turu): akışın
              // en dibinde, kaydırılmadan görünmeyen bir yerde duruyordu —
              // "yeri olmamış". Günlük artık başlığın sağ üst köşesinde
              // sabit bir düğme (bkz. _Header): ekranın en görünür, hiç
              // kaymayan noktası. Sohbet oraya ikinci bir kapıya ihtiyaç
              // duymuyordu, dock'un merkezinde zaten duruyor.
            ],
          ),
        ),
      ),
    );
  }

  /// Burç hikâyesini tam ekran açar.
  void _openStory(List<int> order, int index) {
    if (index < 0) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SignStoryScreen(order: order, initialIndex: index),
      fullscreenDialog: true,
    ));
  }
}

/// Seri rozeti + kutlama (R12-C1, R2-S3'te başlıktan bölüm başlığına indi).
///
/// Kutlama: rozet 1→1.25→1 şişer (pop), arkasında 12 kıvılcımlık mini
/// patlama. Profildeki sayı Firestore turundan henüz dönmediyse yeni sayı
/// [celebrate]'ten gösterilir; kullanıcı artışı ANINDA görür.
class _StreakRozet extends StatelessWidget {
  const _StreakRozet({required this.streak, this.celebrate});

  final int streak;

  /// Seri bu oturumda büyüdüyse yeni sayı. Null: vurgu yok.
  final int? celebrate;

  @override
  Widget build(BuildContext context) {
    final rozet = StreakBadge(count: celebrate ?? streak);
    if (celebrate == null || reduceMotion(context)) return rozet;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: OverflowBox(
            maxWidth: 100,
            maxHeight: 100,
            child: const StarBurst(size: 100, particles: 12),
          ),
        ),
        rozet
            .animate(key: ValueKey('seri-$celebrate'))
            .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.25, 1.25),
                duration: const Duration(milliseconds: 250),
                curve: RythoMotion.pop)
            .then()
            .scale(
                begin: const Offset(1, 1),
                end: const Offset(0.8, 0.8),
                duration: const Duration(milliseconds: 250),
                curve: RythoMotion.settle),
      ],
    );
  }
}

/// Günlük keşif halkası (OB4) — üç dilim: gökyüzü · sohbet · çevre.
///
/// Dolmuş dilim altın, boş dilim cam çizgisi. 3/3'te bir kez yıldız
/// patlamasıyla kutlanır ([celebrate]; ses ve snackbar SkyScreen'de).
/// Cihaz-yerel bir ritüel göstergesidir; dokunulmaz, yalnız anlatır
/// (Tooltip). [reduceMotion] kutlama animasyonunu kapatır.
class _DiscoveryRing extends StatelessWidget {
  const _DiscoveryRing({required this.state, this.celebrate = false});

  final DiscoveryState state;
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final halka = Tooltip(
      message: l10n.discoveryRingTooltip,
      child: SizedBox(
        width: 26,
        height: 26,
        child: CustomPaint(
          painter: _DiscoveryRingPainter(
            mask: state.mask,
            done: RythoColors.goldBright,
            empty: RythoColors.glassStroke,
          ),
          child: state.complete
              ? const Center(
                  child: Text('✦',
                      style:
                          TextStyle(fontSize: 9, color: RythoColors.goldBright)))
              : null,
        ),
      ),
    );
    if (!celebrate || reduceMotion(context)) return halka;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        const Positioned.fill(
          child: OverflowBox(
            maxWidth: 100,
            maxHeight: 100,
            child: StarBurst(size: 100, particles: 12),
          ),
        ),
        halka
            .animate(key: const ValueKey('kesif-33'))
            .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.25, 1.25),
                duration: const Duration(milliseconds: 250),
                curve: RythoMotion.pop)
            .then()
            .scale(
                begin: const Offset(1, 1),
                end: const Offset(0.8, 0.8),
                duration: const Duration(milliseconds: 250),
                curve: RythoMotion.settle),
      ],
    );
  }
}

class _DiscoveryRingPainter extends CustomPainter {
  const _DiscoveryRingPainter(
      {required this.mask, required this.done, required this.empty});

  final int mask;
  final Color done;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final merkez = Offset(size.width / 2, size.height / 2);
    final yaricap = size.width / 2 - 2;
    const dilim = 2 * math.pi / 3;
    const bosluk = 0.30; // radyan — dilimler ayrışsın
    for (var i = 0; i < 3; i++) {
      final boya = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = (mask & (1 << i)) != 0 ? done : empty;
      canvas.drawArc(
        Rect.fromCircle(center: merkez, radius: yaricap),
        -math.pi / 2 + i * dilim + bosluk / 2,
        dilim - bosluk,
        false,
        boya,
      );
    }
  }

  @override
  bool shouldRepaint(_DiscoveryRingPainter old) =>
      old.mask != mask || old.done != done || old.empty != empty;
}

/// Üst şerit: degrade halkalı avatar + selamlama + jeton hapı + sohbet ikonu.
class _Header extends StatelessWidget {
  const _Header({
    required this.greeting,
    required this.name,
    required this.photoUrl,
    required this.onAvatarTap,
  });

  final String greeting;
  final String name;
  final String? photoUrl;

  /// Avatara dokunuş — Profil sekmesine geçiş (U1).
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        // Avatar dokunulabilir (U1): Profil sekmesine götürür — en
        // tanıdık desen (üstteki avatar = profil kapısı).
        Pressable(
          onTap: onAvatarTap,
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RythoColors.primaryGradient,
            ),
            child: CircleAvatar(
              radius: 23,
              backgroundColor: RythoColors.inkLight,
              backgroundImage:
                  photoUrl != null ? NetworkImage(photoUrl!) : null,
              child: photoUrl == null
                  ? Text('☽', style: RythoText.display(18))
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting,
                style: RythoText.body(12.5, color: RythoColors.parchmentDim)),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RythoText.display(18, w: FontWeight.w600)),
          ]),
        ),
        // Jeton hapı (U1): ekonomi ana ekranda her an görünür; dokununca
        // Abonelik ve Jetonlar açılır (Duolingo mücevher sayacı modeli).
        const TokenChip(),
        const SizedBox(width: 10),
        // GÜNLÜĞÜM. Buradaki düğme eskiden sohbete gidiyordu — ama sohbet
        // dock'un MERKEZİNDE zaten duruyor; aynı hedefe ikinci bir kapı
        // başlıkta yer harcıyordu. Günlüğün ise sabit bir kapısı yoktu:
        // akışın içinde bir karttı ve kaydırılmadan görünmüyordu.
        //
        // Günlük stratejik: kullanıcı yaşantısını not ettikçe okumalar
        // kişiselleşiyor. O yüzden ekranın en sabit, en görünür köşesini
        // o alıyor (cihaz turu kararı, 1.5.1+18).
        Pressable(
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiaryScreen())),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: RythoColors.primaryGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
                bottomRight: Radius.circular(15),
                bottomLeft: Radius.circular(5),
              ),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22)),
              boxShadow: const [
                BoxShadow(color: RythoColors.magentaGlow, blurRadius: 14),
              ],
            ),
            child: const Icon(Icons.auto_stories_rounded,
                size: 19, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

// `_DiaryQuickCard` KALDIRILDI (1.5.1+18): günlük girişi akıştaki bir
// karttan başlığın sağ üst köşesindeki sabit düğmeye taşındı. Kart
// ekranın dibinde kalıyor ve kaydırılmadan görünmüyordu; günlük gibi
// her gün tekrarlanacak bir ritüelin kapısı kaymayan bir yerde durmalı.

class _SignalsSection extends ConsumerStatefulWidget {
  const _SignalsSection();

  @override
  ConsumerState<_SignalsSection> createState() => _SignalsSectionState();
}

class _SignalsSectionState extends ConsumerState<_SignalsSection> {
  /// KA5: sabah bildirimi niyeti bir kez işlenir — sinyaller yüklendiğinde
  /// ilgili kartın "Neye dayanıyor?" sayfası kendiliğinden açılır.
  void _dailyNiyetiIsle(List<Map<String, dynamic>> sinyaller) {
    final niyet = ref.read(pendingNotificationProvider);
    if (niyet == null || niyet.type != 'daily') return;
    // BY-turu: bu ekran YALNIZ route=signal tüketir; route'suz/story
    // daily'yi merkezî tüketici (AppShell._niyetIsle) günlük okumaya
    // yönlendirir — burada dokunulmaz ki yarış çıkmasın.
    if (niyet.data['route'] != 'signal') return;
    if (sinyaller.isEmpty) return;
    ref.read(pendingNotificationProvider.notifier).clear();

    final bugun = DateTime.now().toIso8601String().substring(0, 10);
    if ((niyet.data['d'] ?? '') != bugun) return; // bayat: yalnız sekme

    // Parmak izi eşleşmesi: sinyaller bildirimden beri değiştiyse (nadir)
    // yanlış kartı açmak yerine 1 numaralı karta düşülür — asla yanlış
    // dayanak gösterilmez, en kötü durumda "bugünün ilk kartı" açılır.
    final veri = ref.read(signalsDataProvider).value ?? const {};
    final fp = veri['fingerprint'] as String? ?? '';
    var indeks = int.tryParse(niyet.data['idx'] ?? '0') ?? 0;
    if (fp.isEmpty || fp != (niyet.data['fp'] ?? '') ||
        indeks < 0 || indeks >= sinyaller.length) {
      indeks = 0;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sinyalDayanaginiAc(context, sinyaller[indeks]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sinyaller = ref.watch(signalsProvider).value ?? const [];
    // Niyet dinleyicisi sinyaller HAZIRKEN tetiklenmeli; hem ilk yükleme
    // (bildirimle soğuk açılış) hem sıcak dokunma bu yoldan geçer.
    ref.listen(pendingNotificationProvider, (previous, next) {
      if (next != null && next.type == 'daily') {
        final guncel = ref.read(signalsProvider).value ?? const [];
        if (guncel.isNotEmpty) _dailyNiyetiIsle(guncel);
      }
    });
    if (sinyaller.isNotEmpty &&
        ref.read(pendingNotificationProvider)?.type == 'daily') {
      _dailyNiyetiIsle(sinyaller);
    }
    if (sinyaller.isEmpty) return const SizedBox.shrink();

    // En yakın kesinleşme: kartlarda tarih zaten geçiyor; bu satır güne
    // tek bakışta çapa atar ("bu hafta ne zaman önemli").
    final tarihler = [
      for (final s in sinyaller)
        if (s['exact_on_local'] is String &&
            (s['exact_on_local'] as String).isNotEmpty)
          (exactOn: s['exact_on'] as String? ?? '',
           local: s['exact_on_local'] as String),
    ]..sort((a, b) => a.exactOn.compareTo(b.exactOn));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l10n.signalsSection,
          trailing: tarihler.isEmpty
              ? null
              : Text('✦ ${l10n.signalUpcoming(tarihler.first.local)}',
                  style: RythoType.dataSmall
                      .copyWith(color: RythoColors.gold)),
        ),
        for (final sinyal in sinyaller) _SignalCard(sinyal: sinyal),
        const SizedBox(height: RythoSpace.sm),
      ],
    );
  }
}

/// Sinyal dayanağı sayfasını açan TEK yol — kart dokunuşu VE sabah
/// bildirimi buradan geçer.
///
/// İki giriş yolu ayrı ayrı yazılmıştı ve bildirim yolu `onAsk`i
/// GEÇİRMİYORDU; `basis_sheet` düğmeyi koşullu çizdiği için bildirimden
/// gelen kullanıcı sohbet kapısını HİÇ görmüyordu (ölçüldü). Çağrıyı tek
/// yere indirmek o sapmayı yapısal olarak imkânsız kılıyor: üçüncü bir
/// giriş yolu eklenirse düğme bedava geliyor.
void _sinyalDayanaginiAc(BuildContext context, Map<String, dynamic> sinyal) {
  final l10n = AppLocalizations.of(context);
  // Sayfaya karttaki CÜMLE de gider (R3-1): kullanıcı "neye dayanıyor"
  // sorusunu abone yorumuna sorduysa sayfa o cümleyle açılmalı.
  final insight = sinyal['insight'] as String?;
  final kartCumlesi = (insight != null && insight.isNotEmpty)
      ? insight
      : (sinyal['headline'] as String? ?? '');
  showSignalBasisSheet(
    context,
    {...sinyal, 'card_text': kartCumlesi},
    onAsk: () {
      Navigator.of(context).pop();
      // R4-1 / K2: soru O SİNYALE ÖZELDİR — karttaki cümle + dayanağı
      // birlikte gider, model kullanıcının okuduğu cümleyi açar ve
      // "başka konu" hissi oluşmaz.
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
            initialText: l10n.signalAskPrefill(
                kartCumlesi, (sinyal['technical'] as String?) ?? '')),
      ));
    },
  );
}

/// Tek sinyal kartı: tema çipi + başlık cümlesi + (varsa) abone yorumu +
/// "Neden?" — dokunuş dayanak alt-sayfasını açar (R2-S2).
class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.sinyal});

  final Map<String, dynamic> sinyal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tema = sinyal['theme'] as String? ?? 'inner';

    // Kartın metni GÜNDELİK dildedir (R2-S6). Abonede LLM yorumu, ücretsiz
    // katmanda tema+ton şablonu — ikisi de "hayatında ne oluyor" anlatır.
    // "Kiron natal Venüs ile üçgen" cümlesi buradan kalktı; teknik dayanak
    // "Neye dayanıyor?" sayfasında, kendi başlığı altında duruyor.
    final insight = sinyal['insight'] as String?;
    final metin = (insight != null && insight.isNotEmpty)
        ? insight
        : (sinyal['headline'] as String? ?? '');
    final zaman = sinyal['timing_local'] as String?;

    return GlassPanel(
      margin: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: 5),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
      onTap: () => _sinyalDayanaginiAc(context, sinyal),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Tema başlığı: kullanıcı bir bakışta "bu kariyer mi ilişki mi"
        // sorusunu cevaplayabilmeli — ikon + büyük ad, silik değil.
        Row(children: [
          Text(kThemeIcons[tema] ?? '✦',
              style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(sinyal['theme_local'] as String? ?? '',
                style: RythoText.display(13.5,
                    w: FontWeight.w700, color: RythoColors.lilac)),
          ),
          if (zaman != null && zaman.isNotEmpty)
            // Zamanlama etiketi ("15 Eylül günü netleşiyor") uzun ve dile
            // bağlı: dar ekranda tema adıyla birlikte satırı taşırıyordu.
            // Flexible + sağa hizalı iki satır: tema adı da etiketi de
            // okunur kalır, kart genişlemez.
            Flexible(
              child: Text(zaman,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  style: RythoType.dataSmall
                      .copyWith(color: RythoColors.gold)),
            ),
        ]),
        const SizedBox(height: 7),
        Text(metin, style: RythoText.body(13.5, height: 1.45)),
        const SizedBox(height: 8),
        Text('${l10n.signalWhy} →',
            style: RythoText.body(11.5,
                color: RythoColors.parchmentDim, w: FontWeight.w600)),
      ]),
    );
  }
}


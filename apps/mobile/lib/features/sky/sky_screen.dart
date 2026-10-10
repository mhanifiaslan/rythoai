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
import '../../widgets/liste_satiri.dart';
import '../../widgets/motion.dart';
import '../../widgets/nebula_widgets.dart';
import '../../widgets/reading_card.dart';
import '../../widgets/star_burst.dart';
import '../../widgets/token_chip.dart';
import '../shell/app_shell.dart' show shellTabProvider;
import '../paywall/paywall_acilis.dart';
import '../paywall/ozellik_katalogu.dart';
import '../paywall/plus_locked_card.dart';
import 'calendar_strip.dart';
import 'sign_story_screen.dart';
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

/// Keşif halkasındaki dilim sayısı — "1/3" etiketinin paydası.
const int kKesifDilimi = 3;

/// GÖKYÜZÜ — **bugün** ekranı.
///
/// ## Omurga (D5, yukarıdan aşağıya)
///
/// 1. Başlık: avatar · selam + ad · bakiye hapı.
/// 2. Burç şeridi — hikâye halkası, dokunma tam ekran okuyucu açar.
/// 3. TEK "Bugün" başlığı: tarih · keşif halkası (n/3) · seri rozeti.
/// 4. Takvim şeridi (önündeki 30 gün).
/// 5. Sinyaller — alt etiket, bölüm başlığı DEĞİL.
/// 6. Kişiye özel okuma ya da kilit kartı.
/// 7. "Günlüğüm · Bugünü not et" satırı.
///
/// ## Neden bu sıra
///
/// Önceki hâlde "bugün" ÜÇ kez başlık oluyordu: sinyaller bölümünün kendi
/// `SectionHeader`ı ("Bugün gökyüzünde senin için"), içgörü başlığı
/// ("Bugünün İçgörüsü") ve her ikisinin sağındaki tarih. Aynı sayfada üç
/// "bugün" okuyan kullanıcı sayfayı üç ayrı bölüm sanıyordu; oysa hepsi
/// aynı günün anlatısı. Artık tek başlık var ve altındaki her şey (takvim,
/// sinyaller, okuma) onun gövdesi. Sinyallerin kendi etiketi kaldı ama
/// başlık rolünden alt etiket rolüne indi.
///
/// Günlük düğmesi başlıktan okumanın ALTINA indi (sahip kararı K7):
/// başlıkta ikon-tek bir düğme olarak neye gittiği belli olmuyordu;
/// okumanın altında "Günlüğüm · Bugünü not et" satırı hem adını hem
/// eylemini söylüyor ve okuduktan sonra not etme ritüeline denk geliyor.
///
/// ## Önceki yeniden kurgu (R3)
///
/// * **Burç yorumu** → hikâye okuyucusu ([SignStoryScreen]).
/// * **Gökyüzü çarkı** → Atlas. Akışta tek satırlık özet kaldı.
/// * **Tanıtım bandı** → silindi. Satış mesajı [PlusLockedCard]'da.
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
        // Kesinti sınıfı (kullanıcı istemedi, ekran ona geldi): rota türünü
        // ve analitik etiketini tek kapı seçer.
        await acPaywall(context, kaynak: PaywallKaynak.tanitim);
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
              // Kademeli giriş tek yoldan: `RythoReveal(index:)`. Eski
              // `next()` sayacı yedi kopyanın yedincisiydi ve hareket
              // azaltmayı okumuyordu.
              RythoReveal(
                index: 0,
                slide: 0.08,
                child: _Header(
                  greeting: _greeting(l10n),
                  name: profile['displayName'] ?? l10n.defaultUserName,
                  photoUrl: profile['photoUrl'],
                  onAvatarTap: () =>
                      ref.read(shellTabProvider.notifier).state = 3,
                ),
              ),
              const SizedBox(height: RythoSpace.lg),

              // Burç şeridi — HİKÂYE halkası. Dokunma tam ekran okuyucu açar.
              // Yeri SABİT: her zaman başlığın hemen altında, sosyal medya
              // durum çubuğu gibi. Hiçbir bölüm (sinyaller dahil) bunu aşağı
              // itmez — R2-S6'da bir kez itilmişti, geri alındı.
              //
              // Eskiden bu şerit bir "seçici"ydi: dokunulunca 200 px aşağıdaki
              // bölümün metni değişiyordu, arada da alakasız bir tanıtım bandı
              // duruyordu. Görünüşü hikâye, davranışı sekme filtresiydi.
              RythoReveal(
                index: 1,
                slide: 0.08,
                child: SizedBox(
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
                ),
              ),

              // ---------- TEK "BUGÜN" BAŞLIĞI ----------
              // Altındaki takvim, sinyaller ve okuma bu başlığın gövdesi.
              // Seri rozeti ve keşif halkası burada: motivasyon sinyaller,
              // seri yan ürün — "neden her gün açayım"ın cevabı artık rozet
              // değil, gökyüzünün bugün söyledikleri.
              RythoReveal(
                index: 2,
                slide: 0,
                child: SectionHeader(
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
                          // Tarih biçimi de dile bağlı: sabit 'tr_TR'
                          // İngilizce arayüzde Türkçe ay adı gösteriyordu.
                          // Mono değil caption: bu bir tarih cümlesi, bir
                          // derece değeri değil.
                          DateFormat(
                                  'd MMMM',
                                  Localizations.localeOf(context)
                                      .toLanguageTag())
                              .format(DateTime.now()),
                          style: RythoType.caption,
                        ),
                        _DiscoveryRing(state: kesif, celebrate: _kesifKutlama),
                        _StreakRozet(streak: streak, celebrate: _streakYeni),
                      ]),
                ),
              ),

              // Takvim şeridi (R5-6) — "Önündeki 30 gün". Ücretsiz hesapta
              // da görünür: tarih ve tema gerçek, kilitli olan yalnız okuma.
              // Yükleme/hata/boş hâllerini kendi içinde ayırır (AsyncBolum).
              const RythoReveal(
                index: 3,
                slide: 0.08,
                child: CalendarStrip(),
              ),

              // ---------- SİNYALLER (R2-S3) ----------
              // "Rytho bugün senin için fark etti": sorulmadan konuşan
              // astrolog. Boş veri bölümü gizler; hata ARTIK gizlenmez —
              // kart + tekrar dene (G1).
              const RythoReveal(index: 4, child: _SignalsSection()),

              // ---------- KİŞİYE ÖZEL OKUMA ----------
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
                        : _KisiselOkuma(data: data);
                  },
                ),

              // ---------- GÜNLÜĞÜM (K7) ----------
              // Okumanın ALTINDA: başlıktaki ikon-tek düğme neye gittiğini
              // söylemiyordu; bu satır adını ve eylemini söylüyor ve
              // "okudum, şimdi not edeyim" anına denk geliyor. Sohbet ayrı
              // bir kapı istemiyor — dock'un merkezinde duruyor.
              RythoReveal(
                index: 5,
                child: ListeSatiri(
                  margin: const EdgeInsets.symmetric(
                      horizontal: RythoSpace.lg, vertical: RythoSpace.sm),
                  leading: const Icon(Icons.auto_stories_rounded,
                      size: 22, color: RythoColors.lilac),
                  title: l10n.diaryTitle,
                  subtitle: l10n.diaryRowSubtitle,
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DiaryScreen())),
                ),
              ),
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

/// Abonenin kişiye özel okuması: giriş + tek atış altın parıltı.
///
/// Parıltı DÖNGÜ DEĞİL (bir kez süpürür) ve hareket azaltmada hiç
/// kurulmaz; giriş `RythoReveal`den gelir — eski zincir çıplak süreli ve
/// kapısızdı.
class _KisiselOkuma extends StatelessWidget {
  const _KisiselOkuma({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Sunucu burç adını Türkçe döndürüyor; ekrana ham basmak İngilizce
    // arayüzde "Oğlak" yazdırıyordu.
    final gunes = localizedSignName(l10n, data['sun_sign'] as String?);
    final ay = localizedSignName(l10n, data['moon_sign'] as String?);
    final yukselen = localizedSignName(l10n, data['ascendant'] as String?);
    final parcalar = <String>[
      if (gunes.isNotEmpty) '☀️ $gunes',
      if (ay.isNotEmpty) '🌙 $ay',
      if (yukselen.isNotEmpty) '⬆️ $yukselen',
    ];
    final kart = ReadingCard(
      label: parcalar.join(' · '),
      title: l10n.personalReadingTitle,
      body: data['reading'] ?? '',
      glow: true,
    );
    return RythoReveal(
      index: 0,
      child: reduceMotion(context)
          ? kart
          : kart.animate().shimmer(
              delay: RythoMotion.slow,
              duration: RythoMotion.sweep,
              color: RythoColors.gold.withValues(alpha: 0.12)),
    );
  }
}

/// Seri rozeti + kutlama (R12-C1, R2-S3'te başlıktan bölüm başlığına indi).
///
/// Kutlama sahnesi `Kutlama`da (tek tanım); profildeki sayı Firestore
/// turundan henüz dönmediyse yeni sayı [celebrate]'ten gösterilir —
/// kullanıcı artışı ANINDA görür. Anahtar yeni sayıyı taşır: aynı oturumda
/// ikinci artış da kutlanır.
class _StreakRozet extends StatelessWidget {
  const _StreakRozet({required this.streak, this.celebrate});

  final int streak;

  /// Seri bu oturumda büyüdüyse yeni sayı. Null: vurgu yok.
  final int? celebrate;

  @override
  Widget build(BuildContext context) {
    return Kutlama(
      key: ValueKey('seri-${celebrate ?? 0}'),
      celebrate: celebrate != null,
      child: StreakBadge(count: celebrate ?? streak),
    );
  }
}

/// Günlük keşif halkası (OB4) — üç dilim: gökyüzü · sohbet · çevre.
///
/// Dolmuş dilim altın, boş dilim cam çizgisi; yanında "n/3" sayacı —
/// halka tek başına "kaçta kaç" sorusunu yalnız gören göze cevaplıyordu,
/// sayı ekran okuyucuya da söylüyor. 3/3'te bir kez yıldız patlamasıyla
/// kutlanır ([celebrate]; ses ve snackbar SkyScreen'de). Cihaz-yerel bir
/// ritüel göstergesidir; dokunulmaz, yalnız anlatır (Tooltip).
class _DiscoveryRing extends StatelessWidget {
  const _DiscoveryRing({required this.state, this.celebrate = false});

  final DiscoveryState state;
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dolu = [
      for (var i = 0; i < kKesifDilimi; i++)
        if (state.mask & (1 << i) != 0) i,
    ].length;
    final halka = SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(
        painter: _DiscoveryRingPainter(
          mask: state.mask,
          done: RythoColors.goldBright,
          empty: RythoColors.glassStroke,
        ),
        child: state.complete
            ? Center(
                child: Text('✦',
                    style: RythoText.glyph(9, color: RythoColors.goldBright)))
            : null,
      ),
    );
    return Tooltip(
      message: l10n.discoveryRingTooltip,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Kutlama(
          key: const ValueKey('kesif-33'),
          celebrate: celebrate,
          child: halka,
        ),
        const SizedBox(width: RythoSpace.xs),
        Text('$dolu/$kKesifDilimi', style: RythoType.caption),
      ]),
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

/// Üst şerit: degrade halkalı avatar + selamlama + bakiye hapı.
///
/// Günlük düğmesi buradan KALKTI (K7): ikon-tek bir degrade kare, neye
/// gittiği okunmadan "bir şey" vaat ediyordu. Günlük artık okumanın
/// altında adıyla duruyor.
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
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
      child: Row(children: [
        // Avatar dokunulabilir (U1): Profil sekmesine götürür — en
        // tanıdık desen (üstteki avatar = profil kapısı). İkon-tek yüzey:
        // ekran okuyucu sekmenin adını duyar.
        Pressable(
          onTap: onAvatarTap,
          semanticLabel: l10n.tabProfile,
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
        const SizedBox(width: RythoSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting, style: RythoType.caption),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RythoText.display(18, w: FontWeight.w600)),
          ]),
        ),
        // Bakiye hapı (U1): ekonomi ana ekranda her an görünür; dokununca
        // mağaza açılır (Duolingo mücevher sayacı modeli).
        const TokenChip(),
      ]),
    );
  }
}

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

  /// HAZIR sinyaller — yalnız veri hâlinde; yükleniyor ve hata boş sayılır.
  /// Niyet tüketimi içindir: hata ile boş aynı görünsün diye DEĞİL (o kusur
  /// G1'di ve çizim artık `AsyncBolum`dan geçiyor), yalnız "bildirimin
  /// kartı var mı" sorusu için.
  static List<Map<String, dynamic>> _hazirSinyaller(
          AsyncValue<List<Map<String, dynamic>>> durum) =>
      switch (durum) {
        AsyncData(:final value) => value,
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final durum = ref.watch(signalsProvider);
    // Niyet dinleyicisi sinyaller HAZIRKEN tetiklenmeli; hem ilk yükleme
    // (bildirimle soğuk açılış) hem sıcak dokunma bu yoldan geçer.
    ref.listen(pendingNotificationProvider, (previous, next) {
      if (next != null && next.type == 'daily') {
        final guncel = _hazirSinyaller(ref.read(signalsProvider));
        if (guncel.isNotEmpty) _dailyNiyetiIsle(guncel);
      }
    });
    final sinyaller = _hazirSinyaller(durum);
    if (sinyaller.isNotEmpty &&
        ref.read(pendingNotificationProvider)?.type == 'daily') {
      _dailyNiyetiIsle(sinyaller);
    }

    // Üç hâl ayrı (G1): iskelet / hata kartı + tekrar dene / veri. Tekrar
    // dene KAYNAĞI geçersiz kılar — sinyaller `signalsDataProvider`dan
    // türetiliyor, türevi tek başına tazelemek aynı düşmüş cevabı okurdu.
    return AsyncBolum<List<Map<String, dynamic>>>(
      durum: durum,
      onRetry: () => ref.invalidate(signalsDataProvider),
      iskeletYuksekligi: 118,
      bosMu: (s) => s.isEmpty,
      veri: (s) => _SinyalListesi(sinyaller: s),
    );
  }
}

/// Sinyal kartları ve üstlerindeki alt etiket.
///
/// Etiket `SectionHeader` DEĞİL: sayfanın tek başlığı "Bugün" (bkz.
/// [SkyScreen]); bu satır onun altındaki bir alt bölümün adı ve etiket
/// rolünde çizilir. Sağında en yakın önemli gün: kartlarda tarih zaten
/// geçiyor, bu satır güne tek bakışta çapa atar.
class _SinyalListesi extends StatelessWidget {
  const _SinyalListesi({required this.sinyaller});

  final List<Map<String, dynamic>> sinyaller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
        Padding(
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.xl, RythoSpace.md, RythoSpace.xl, RythoSpace.xs),
          // `Wrap` + tam genişlik: dar ekranda önemli gün alt satıra iner,
          // kısaltılmaz (SectionHeader ile aynı gerekçe).
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: RythoSpace.md,
              runSpacing: RythoSpace.xs,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(l10n.signalsSection, style: RythoType.label),
                if (tarihler.isNotEmpty)
                  Text('✦ ${l10n.signalUpcoming(tarihler.first.local)}',
                      style: RythoType.caption
                          .copyWith(color: RythoColors.gold)),
              ],
            ),
          ),
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
      // R4-1 / K2: soru O SİNYALE ÖZELDİR — karttaki cümle gider, model
      // kullanıcının okuduğu cümleyi açar ve "başka konu" hissi oluşmaz.
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
            // {technical} tohumdan düştü (D5): kullanıcının ağzına "orb 0.4°"
            // konuyordu; dayanak dayanak sayfasında, sohbet tohumunda değil.
            initialText: l10n.signalAskPrefill(kartCumlesi)),
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
          horizontal: RythoSpace.lg, vertical: RythoSpace.xs),
      padding: const EdgeInsets.all(RythoSpace.md),
      onTap: () => _sinyalDayanaginiAc(context, sinyal),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Tema başlığı: kullanıcı bir bakışta "bu kariyer mi ilişki mi"
        // sorusunu cevaplayabilmeli — ikon + büyük ad, silik değil.
        Row(children: [
          Text(kThemeIcons[tema] ?? '✦', style: RythoText.emoji(15)),
          const SizedBox(width: RythoSpace.sm),
          Expanded(
            child: Text(sinyal['theme_local'] as String? ?? '',
                style: RythoText.display(13.5,
                    w: FontWeight.w700, color: RythoColors.lilac)),
          ),
          if (zaman != null && zaman.isNotEmpty)
            // Zamanlama etiketi ("15 Eylül günü netleşiyor") uzun ve dile
            // bağlı: dar ekranda tema adıyla birlikte satırı taşırıyordu.
            // Flexible + sağa hizalı iki satır: tema adı da etiketi de
            // okunur kalır, kart genişlemez. Caption, mono değil: bir
            // tarih cümlesi, ölçüm değeri değil.
            Flexible(
              child: Text(zaman,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  style: RythoType.caption.copyWith(color: RythoColors.gold)),
            ),
        ]),
        const SizedBox(height: RythoSpace.sm),
        Text(metin, style: RythoType.body),
        const SizedBox(height: RythoSpace.sm),
        // Oklu davet: takvim gün kartıyla AYNI yazım ve ölçü.
        Text('${l10n.signalWhy} →',
            style: RythoType.caption.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

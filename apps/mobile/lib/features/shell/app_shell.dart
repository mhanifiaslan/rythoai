import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/api.dart' show apiProvider;
import '../../core/consent.dart' show ensureConsentRecorded;
import '../../core/partner_referrer.dart' show ensurePartnerReferrer;
import '../../core/friends.dart' show FriendStatus, friendsProvider;
import '../../core/notifications.dart'
    show
        NotificationRoute,
        NotificationRouteKind,
        PendingNotification,
        pendingNotificationProvider,
        resolveNotificationRoute;
import '../../core/people.dart' show peopleProvider;
import '../../theme/rytho_tokens.dart' show RythoMotion;
import '../../widgets/motion.dart' show kapili;
import '../../widgets/nebula_widgets.dart' show signIndexOf;
import '../friends/relationship_screen.dart' show RelationshipScreen;
import '../sky/sign_story_screen.dart' show SignStoryScreen;
import '../../core/providers.dart'
    show OnboardOutcome, justOnboardedProvider, profileProvider;
import '../../widgets/big_three_reveal.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/glass.dart';
import '../atlas/atlas_screen.dart';
import '../chat/chat_screen.dart';
import '../chat/conversation_list_screen.dart';
import '../friends/friends_screen.dart';
import '../profile/profile_screen.dart';
import '../sky/sky_screen.dart';

/// Bildirim niyeti ŞİMDİ tüketilebilir mi — saf karar (D5).
///
/// Ölçülen kusur: `_niyetIsle` niyeti önce temizleyip SONRA listeyi
/// `provider.value ?? const []` ile okuyordu. Soğuk açılışta (bildirime
/// dokunup uygulamayı açmak) arkadaş akışı henüz ilk değerini vermemiş
/// oluyor, liste boş geliyor, döngü hiçbir şeyi eşlemiyor — ve niyet
/// TÜKETİLMİŞ olduğu için bir daha denenmiyordu. Kullanıcı öğle
/// bildirimine dokunuyor, yalnız Çevrem sekmesi açılıyordu.
///
/// Karar burada, veriyle ilgisi olmayan rotalar (sekme, sohbet) hemen
/// tüketilir; veri isteyen rotalar o veri HAZIR olana kadar bekler
/// (`AppShell` hazır olunca yeniden dener). "Hazır" = sağlayıcı bir değer
/// yaydı (`hasValue`); boş liste de bir değerdir ve o zaman eşleşmeyen
/// niyet dürüstçe düşer.
///
/// `signalSheet` burada ASLA tüketilmez: onu SkyScreen tüketir (sinyaller
/// yüklü olmalı ve dayanak sayfası orada açılır).
bool niyetTuketilebilir(
  NotificationRoute rota, {
  required bool profilHazir,
  required bool arkadaslarHazir,
  bool kisilerHazir = true,
}) =>
    switch (rota.kind) {
      NotificationRouteKind.signalSheet => false,
      NotificationRouteKind.dailyStory => profilHazir,
      NotificationRouteKind.friendRelation => arkadaslarHazir,
      NotificationRouteKind.personRelation => kisilerHazir,
      NotificationRouteKind.rythoAsks ||
      NotificationRouteKind.checkinChat ||
      NotificationRouteKind.circleTab ||
      NotificationRouteKind.homeTab =>
        true,
    };

/// Aktif sekme — ekranlar (örn. promo banner) sekme değiştirebilsin diye
/// Riverpod üzerinden paylaşılır. 0: Gökyüzü, 1: Atlas, 2: Arkadaşlar, 3: Profil.
///
/// Eski "Meclis" sekmesinin yerini Arkadaşlar aldı: gönderi akışı, kanallar ve
/// DM (serbest metinli kullanıcı içeriği) kaldırıldı; yerine serbest metin
/// içermeyen arkadaş katmanı geldi — seri görünürlüğü, kapalı kümeden hazır
/// tepkiler ve günlük ikili dinamik.
final shellTabProvider = StateProvider<int>((_) => 0);

/// Ana kabuk: yıldız alanı zemin + 4 sekme + merkez degrade AI butonu
/// (Rytho sohbetini açar). Kehanet araçlarına ana ekran kartlarından gidilir.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Şimdiye kadar açılmış sekmeler (tembel kurulum — bkz. build).
  final Set<int> _gorulen = {};

  /// Veri bekleyen niyetin tek seferlik dinleyicisi (bkz.
  /// [niyetTuketilebilir]). `build`de sürekli `ref.listen` DEĞİL: arkadaş
  /// ve kişi akışlarını her açılışta kurmak, kullanıcı o sekmeye hiç
  /// girmese de iki Firestore dinleyicisi demek — tembel sekme kurulumunun
  /// (bkz. build) tam tersi. Dinleyici yalnız bekleyen bir niyet varken
  /// yaşar ve ilk değerde kendini kapatır.
  ProviderSubscription<AsyncValue<Object?>>? _bekleyenNiyet;

  @override
  void dispose() {
    _bekleyenNiyet?.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Tek cihaz kilidi artık BURADA sorulmaz (TC-turu K8): açılıştaki
    // devralma sorusu `SkyScreen`'in ilk `POST /reports/daily`'siyle
    // yarışıp kaybediyordu. Hakem sunucu ("son giriş kazanır"); çakışma
    // `_Gate` kapısında gösterilir (bkz. core/device_session.dart).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _buyukUcluPerdesi();
      // KT2: kabul kaydı onboarding'de düşmüşse burada telafi edilir
      // (bayraklı — başarı sonrası bir daha ağa çıkmaz).
      ensureConsentRecorded(ref.read(apiProvider));
      // OP: ortak bağlantısıyla gelindiyse Play Install Referrer'daki kod
      // hesaba bağlanır. `main.dart`'ta DEĞİL burada: kullanıcı oturumu
      // açılmış olmalı (uç kimlik istiyor) ve ayrıca `main.dart` şu sıra
      // iOS tarafında da düzenleniyor — çakışma yüzeyini açmamak için.
      // Android dışında kendiliğinden hiçbir şey yapmaz.
      ensurePartnerReferrer(ref.read(apiProvider));
      // Soğuk açılış: niyet dinleyiciden ÖNCE yazılmış olabilir.
      final bekleyen = ref.read(pendingNotificationProvider);
      if (bekleyen != null) _niyetIsle(bekleyen);
    });
  }

  /// Onboarding'in finali (R12-B1): kullanıcı doğum verisini az önce verdiyse
  /// Büyük Üçlü perdesi burada açılır — onboarding ekranında açılamaz, çünkü
  /// `onboardingCompleted` yazımı iner inmez `_Gate` o ekranı söker.
  void _buyukUcluPerdesi() {
    final sonuc = ref.read(justOnboardedProvider);
    if (sonuc == null) return;
    ref.read(justOnboardedProvider.notifier).state = null;
    final profil = ref.read(profileProvider).value ?? const {};
    final gunes = profil['sunSign'] as String?;
    final ay = profil['moonSign'] as String?;
    final yukselen = profil['ascendant'] as String?;
    // Harita hesaplanamadıysa perde açılmaz — yalan rozet göstermeme
    // kuralı (core/birth_record.dart). Ama artık SESSİZ değil (O3):
    // kullanıcı verisinin kaydedildiğini ve haritanın sonra çizileceğini
    // duyar; rozetlerin yokluğu açıklanamayan bir davranış olmaktan çıkar.
    if (sonuc == OnboardOutcome.chartMissing ||
        gunes == null ||
        ay == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              // İlk kayıt "güncellendi" DEMEZ: bu kullanıcının ilk doğum
              // kaydı, güncelleme değil (D4 bulgusu; anahtar D5'te eklendi,
              // tüketicisi D8'e kadar bağlanmamıştı).
              Text(AppLocalizations.of(context).onboardingSavedNoChart)));
      return;
    }
    showBigThreeReveal(context, sun: gunes, moon: ay, ascendant: yukselen);
  }

  /// Bildirim niyetinin MERKEZİ tüketicisi (BY-turu).
  ///
  /// Cihaz bulgusu: "öğle bildirimine tıkladım, sadece uygulama açıldı."
  /// Karar saf `resolveNotificationRoute`ta; burada yalnız uygulanır.
  /// Tek istisna `signalSheet`: sinyaller yüklü olmalı, onu SkyScreen
  /// tüketir — burada NİYETE DOKUNULMAZ.
  void _niyetIsle(PendingNotification niyet) {
    final rota = resolveNotificationRoute(niyet.data);
    if (rota.kind == NotificationRouteKind.signalSheet) return;
    if (!mounted) return;

    // Veri isteyen rota, verisi gelmeden TÜKETİLMEZ (ölçülmüş kusur, bkz.
    // niyetTuketilebilir): niyet yerinde kalır, ilgili akış ilk değerini
    // verince buraya yeniden gelinir.
    //
    // Yalnız GEREKEN akış okunur: `ref.read` sağlayıcıyı kurar ve arkadaş /
    // kişi akışları Firestore dinleyicisi demek. Her bildirim dokunuşunda
    // ikisini birden kurmak, tembel sekme kurulumunun (bkz. build) tam
    // tersi olurdu; kısa devre `||` yalnız rotanın istediği akışa dokunur.
    final arkadasGerek = rota.kind == NotificationRouteKind.friendRelation;
    final kisiGerek = rota.kind == NotificationRouteKind.personRelation;
    if (!niyetTuketilebilir(
      rota,
      profilHazir: ref.read(profileProvider).hasValue,
      arkadaslarHazir: !arkadasGerek || ref.read(friendsProvider).hasValue,
      kisilerHazir: !kisiGerek || ref.read(peopleProvider).hasValue,
    )) {
      _veriGelinceYenidenDene(switch (rota.kind) {
        NotificationRouteKind.friendRelation => friendsProvider,
        NotificationRouteKind.personRelation => peopleProvider,
        _ => profileProvider,
      });
      return;
    }
    _bekleyenNiyet?.close();
    _bekleyenNiyet = null;
    ref.read(pendingNotificationProvider.notifier).clear();

    switch (rota.kind) {
      case NotificationRouteKind.rythoAsks:
        _rythoSorduNiyeti(rota);
      case NotificationRouteKind.checkinChat:
        _checkinNiyeti(rota);
      case NotificationRouteKind.dailyStory:
        // "Okuman hazır / okumanı açmadın" → okumanın KENDİSİ açılır.
        // Yükte burç varsa o, yoksa kullanıcının burcu öne alınır.
        final profil = ref.read(profileProvider).value ?? const {};
        var burc = signIndexOf(rota.sign);
        if (burc < 0) burc = signIndexOf(profil['sunSign'] as String?);
        if (burc < 0) burc = 0;
        final sira = [burc, for (var i = 0; i < 12; i++) if (i != burc) i];
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SignStoryScreen(order: sira, initialIndex: 0),
          fullscreenDialog: true,
        ));
      case NotificationRouteKind.friendRelation:
        // Öğle çift ânı / kabul: o ilişkinin ekranı ("Bugün aranıza
        // dokunan gökyüzü" tam bildirimin içeriği). Liste HAZIR (yukarıdaki
        // kapı); eşleşme yoksa (arkadaşlık bitmiş) Çevrem sekmesi zaten
        // seçili — orada kal.
        for (final f in ref.read(friendsProvider).requireValue) {
          if (f.uid == rota.friendUid && f.status == FriendStatus.accepted) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RelationshipScreen(friend: f)));
            break;
          }
        }
      case NotificationRouteKind.personRelation:
        for (final k in ref.read(peopleProvider).requireValue) {
          if (k.id == rota.personId) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RelationshipScreen.forPerson(person: k)));
            break;
          }
        }
      case NotificationRouteKind.circleTab:
      case NotificationRouteKind.homeTab:
        // Sekme dokunuş anında zaten atandı (tabForNotification); davet
        // isteği / tepki kutusu o sekmenin en üstünde.
        break;
      case NotificationRouteKind.signalSheet:
        break; // yukarıda elendi
    }
  }

  /// Bekleyen niyeti, [kaynak] ilk değerini verince yeniden dener.
  ///
  /// Tek seferlik: ilk değerde (ya da değersiz hatada) kendini kapatır.
  /// Hata hâlinde niyet DÜŞÜRÜLÜR — liste hiç gelmeyecekse "sessizce o
  /// sekmede kal" en dürüst sonuç; bekleyen niyeti sonsuza dek tutmak, bir
  /// sonraki bildirim dokunuşunu bugünkü yükle karıştırırdı.
  void _veriGelinceYenidenDene(
      ProviderListenable<AsyncValue<Object?>> kaynak) {
    _bekleyenNiyet?.close();
    _bekleyenNiyet = ref.listenManual<AsyncValue<Object?>>(kaynak,
        (onceki, sonraki) {
      if (!sonraki.hasValue && !sonraki.hasError) return;
      _bekleyenNiyet?.close();
      _bekleyenNiyet = null;
      if (!mounted) return;
      final niyet = ref.read(pendingNotificationProvider);
      if (niyet == null) return;
      if (sonraki.hasValue) {
        _niyetIsle(niyet);
      } else {
        ref.read(pendingNotificationProvider.notifier).clear();
      }
    });
  }

  /// RYTHO SORDU (SS-turu): soru zaten sohbette Rytho'nun mesajı olarak
  /// duruyor; dokunuş o konuşmayı açar ve kullanıcı CEVAPLAR.
  ///
  /// `initialText` GEÇMEZ — soru kullanıcının ağzına konmaz. Bayat tarih
  /// kapısı da ARANMAZ: konuşma kalıcı, dünkü bildirime dokunmak da o
  /// konuşmayı açmalı. `seedFallback`, arşiv yazımı henüz görünmüyorsa
  /// (ya da konu temizlendiyse) ekranın boş kalmaması için.
  void _rythoSorduNiyeti(NotificationRoute rota) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
              conversationId: rota.conversationId,
              seedFallback: rota.question,
            )));
  }

  /// Akşam check-in bildirimi (KA5): dokunma sohbeti SORUYLA açar.
  /// Soru bayatsa (dünün bildirimi bugün açıldı) yalnız konu listesi
  /// açılır — dünkü soruyu bugün sormak yanıltıcı olur.
  void _checkinNiyeti(NotificationRoute rota) {
    final soru = rota.question ?? '';
    final gun = rota.questionDate ?? '';
    final bugun = DateTime.now().toIso8601String().substring(0, 10);
    if (soru.isNotEmpty && gun == bugun) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatScreen(initialText: soru, source: 'checkin')));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const ConversationListScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bekleyen bildirim niyeti: uygulama hangi hâlde olursa olsun
    // (soğuk/sıcak) buradan işlenir. Tek istisna route=signal daily'si —
    // onu SkyScreen tüketir (sinyaller yüklü olmalı).
    ref.listen<PendingNotification?>(pendingNotificationProvider,
        (previous, next) {
      if (next != null && mounted) _niyetIsle(next);
    });
    final index = ref.watch(shellTabProvider);
    final l10n = AppLocalizations.of(context);
    // Etiketler dile göre üretildiği için const olamaz.
    final tabs = [
      (icon: Icons.home_outlined, activeIcon: Icons.home_rounded,
       label: l10n.tabSky),
      (icon: Icons.donut_large_outlined, activeIcon: Icons.donut_large_rounded,
       label: l10n.tabAtlas),
      (icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded,
       label: l10n.tabFriends),
      (icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded,
       label: l10n.tabProfile),
    ];
    // Sekme ilk kez görüldüğünde kurulur, sonra Stack'te ASILI KALIR
    // (geri dönünce durum ve kaydırma yeri korunur — Stack'in asıl sebebi).
    // Dördünü birden açılışta kurmak, kullanıcı hiç girmediği sekmeler için
    // de ağ isteği ateşliyordu: soğuk açılışta ~14 istek, ikisi LLM'e giden
    // rapor POST'u. Kotayı besleyen ikinci döngü buydu.
    _gorulen.add(index);

    return CosmicScaffold(
      extendBody: true,
      body: Stack(children: [
        for (var i = 0; i < 4; i++)
          if (_gorulen.contains(i))
            IgnorePointer(
              ignoring: index != i,
              // Sekme geçişi örtük animatör: `reduceMotion` yalnız
              // `.animate()` zincirlerini kapatıyordu, bu 280 ms kapısız
              // oynuyordu (ölçüldü, motion.dart). Süre token'dan, kapıdan.
              child: AnimatedOpacity(
                opacity: index == i ? 1 : 0,
                duration: kapili(context, RythoMotion.route),
                curve: Curves.easeOutCubic,
                child: AnimatedSlide(
                  offset: index == i ? Offset.zero : const Offset(0, 0.012),
                  duration: kapili(context, RythoMotion.route),
                  curve: Curves.easeOutCubic,
                  child: const [
                    SkyScreen(),
                    AtlasScreen(),
                    FriendsScreen(),
                    ProfileScreen(),
                  ][i],
                ),
              ),
            ),
      ]),
      bottomNavigationBar: CosmicDock(
        items: tabs,
        index: index,
        onChanged: (i) => ref.read(shellTabProvider.notifier).state = i,
        // Sohbet artık KONU listesine açılır (Revize R4): kaldığı yerden
        // devam ya da yeni konu — AI uygulamalarındaki desen.
        onCenterTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ConversationListScreen()),
        ),
      ),
    );
  }
}

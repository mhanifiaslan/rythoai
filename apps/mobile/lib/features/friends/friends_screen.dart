import 'dart:async' show unawaited;
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/api.dart' show apiProvider, friendlyError;
import '../../core/contact_match.dart';
import '../../core/deep_links.dart';
import '../../core/friends.dart';
import '../../core/people.dart';
import '../../core/providers.dart';
import '../../core/safety.dart';
import '../../core/subscription.dart' show aboneAynasiProvider;
import '../../core/tr_metin.dart' show trBuyuk;
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/alt_sayfa.dart' show showRythoSheet;
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart' show EmptyState, ErrorCard;
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/liste_satiri.dart';
import '../../widgets/motion.dart' show RythoReveal;
import '../../widgets/nebula_widgets.dart';
import '../../widgets/onay.dart' show onayla;
import '../paywall/ozellik_katalogu.dart' show PlusOzellik;
import '../paywall/paywall_acilis.dart' show PaywallKaynak, acPaywall;
import '../people/person_detail_screen.dart' show PersonDetailScreen;
import '../people/person_form_screen.dart'
    show PersonFormScreen, relationIcon, relationLabel;
import '../profile/account_screen.dart' show AccountScreen;
import '../profile/diary_screen.dart' show DiaryScreen;
import 'contacts_screen.dart' show ContactsScreen;
import 'friend_detail_screen.dart' show FriendDetailScreen, reactionLabel;
import 'reaction_sheet.dart' show showReactionSheet;
import 'relationship_screen.dart' show RelationshipScreen;

/// Geri bildirim kanalındaki ekran kodu (`FeedbackScreen.screen`).
const String kCevremEkranKodu = 'circle';

/// Kontenjan sayacı + (varsa) aşım beyanı — SAF, test edilebilir.
///
/// Abonelik düşünce `used > limit` olur ve eski satır "4/1 kişi" basıyordu:
/// ölçülen sayı yanlış adla sunuluyordu (sayaç "kullanılan/tavan" demektir,
/// 4/1 bir oran değil). Sayaç tavana kelepçelenir; fazlası ayrı cümleyle
/// söylenir ("kontenjanın 1; 4 kişi kayıtlı"). Sayı gizlenmez, adı düzelir.
({String sayac, String? asim}) kontenjanBeyani(AppLocalizations l10n,
    {required int used, required int limit}) {
  return (
    sayac: l10n.peopleSlots(min(used, limit), limit),
    asim: used > limit ? l10n.peopleSlotsOver(limit, used) : null,
  );
}

/// Kişi formu açılmadan ÖNCE kontenjan kapısı.
///
/// NEDEN formdan önce (B10 sonrası ölçüldü): kontenjan dolu kullanıcı formu
/// doldurup "Kaydet"e basınca sunucu 402 dönüyor, interceptor Plus
/// aboneye bile satış ekranı açıyor, form açık kalıyor ve kişi çıkarmaya
/// giden bir yol yok. Sunucu zaten `used/limit` veriyor; kapı burada.
/// `limit == 0` bilinmiyor demektir (yük gelmedi) — kapı KAPANMAZ, karar
/// sunucuya bırakılır.
bool kisiKontenjaniDolu(({int used, int limit})? kontenjan) =>
    kontenjan != null &&
    kontenjan.limit > 0 &&
    kontenjan.used >= kontenjan.limit;

/// ARKADAŞLAR — serbest metin içermeyen sosyal katman.
///
/// Görünen her şey türetilmiş veridir: seri, burç ve "bugün okumasını yaptı
/// mı". Arkadaşın doğum verisi hiçbir zaman istemciye gelmez. Etkileşim
/// yalnızca [kReactions] içindeki kapalı kümeden seçilen hazır tepkilerdir;
/// yazı kutusu bilinçli olarak yoktur.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).value;
    final friendsAsync = ref.watch(friendsProvider);
    final username = profile?['username'] as String?;
    final invite = ref.watch(pendingInviteProvider);

    // Davet bağlantısıyla açıldıysa ekleme sayfasını kullanıcı adı dolu
    // olarak aç. Bağlantı uygulama açılırken de gelebildiği için burada
    // ele alınıyor: bu noktada oturum ve onboarding tamamlanmış oluyor.
    _handlePendingInvite(context, ref, username, invite);

    return CosmicScaffold(
      appBar: AppBar(
        // "Arkadaşlar" → "Çevrem" (P-turu): sayfa artık İKİ FARKLI nesne
        // barındırıyor — karşılıklı onayla eklenen Rytho arkadaşları ve
        // kullanıcının kendi girdiği kişiler (eş, çocuk, yakın).
        title: Text(l10n.circleTitle),
        actions: [
          // Görünür, dolgulu düğme (Revize R6). Eski hâli AppBar varsayılan
          // renkli IconButton'dı ve kullanıcı adı yokken disabled-griydi —
          // "görünmez" şikayetinin iki sebebi. Devre dışı bırakmak yerine
          // dokununca SEBEBİ söylüyor: görünmez düğme değil, açıklayan düğme.
          Padding(
            padding: const EdgeInsets.only(right: RythoSpace.md),
            child: Pressable(
              semanticLabel: l10n.addChooserTitle,
              // Artık doğrudan kullanıcı adı sayfası açmaz: iki ekleme yolu
              // var ve gizlilik anlamları farklı, seçimi kullanıcı yapmalı.
              onTap: () => _showAddChooser(context, ref, username),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: RythoColors.inkLighter,
                  border: Border.all(
                      color: RythoColors.lilac.withValues(alpha: 0.55)),
                ),
                child: const Icon(Icons.person_add_alt_1_rounded,
                    size: 20, color: RythoColors.parchment),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
          padding: const EdgeInsets.only(bottom: RythoSpace.dockClearance),
          children: [
        if (username == null)
          // Davet bekliyorsa panel bunu en üstte söyler: eski hâlde niyet
          // sessizce bekliyor, kullanıcı hiçbir şey görmüyordu.
          _UsernameSetupPanel(davetBekliyor: invite != null)
        else
          _MyCardPanel(
            username: username,
            streakCount: (profile?['streakCount'] as num?)?.toInt() ?? 0,
          ),
        _InboxPanel(friends: friendsAsync.value ?? const []),
        // Rehber önerileri (Revize R3 → F1): panel artık HER ZAMAN mount —
        // ayar kapalıysa/telefon doğrusuzsa/izin yoksa sessiz boşluk yerine
        // yol gösteren kart çizer. Sonuçlar bellekte yaşar; ne istemci ne
        // sunucu listeyi saklar.
        _ContactsEntry(ayarAcik: profile?['contactMatch'] == true),
        friendsAsync.when(
          loading: () => const SkeletonPanel(height: 96),
          error: (e, _) => ErrorCard(
            message: friendlyError(e, l10n),
            screen: kCevremEkranKodu,
            onRetry: () => ref.invalidate(friendsProvider),
          ),
          // Boş durum yalnız İKİ liste de boşken çizilir; kişileri olan
          // ama arkadaşı olmayan kullanıcıya "hiç kimsen yok" demek
          // yanlış olurdu.
          data: (friends) => _FriendsList(
              friends: friends,
              boslugoster: (ref.watch(peopleProvider).value ?? []).isEmpty),
        ),
        // Eklenen kişiler AYRI bölüm (P-turu): satır anatomisi de farklı —
        // tepki, seri ve "bugün okudu" YOK, çünkü karşı tarafta kimse yok.
        const _PeopleSection(),
      ]),
    );
  }
}

/// Kullanıcı adı henüz alınmamışsa: arkadaşların seni bulabilmesi için gerekli.
class _UsernameSetupPanel extends StatefulWidget {
  const _UsernameSetupPanel({this.davetBekliyor = false});

  /// Bağlantıdan gelen bir davet kullanıcı adını bekliyor mu — panel bunu
  /// söyler ve eylem düğmesi alanı odaklar.
  final bool davetBekliyor;

  @override
  State<_UsernameSetupPanel> createState() => _UsernameSetupPanelState();
}

class _UsernameSetupPanelState extends State<_UsernameSetupPanel> {
  final _controller = TextEditingController();
  final _odak = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _odak.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await claimUsername(_controller.text);
    } on UsernameException catch (e) {
      if (mounted) setState(() => _error = usernameErrorText(l10n, e.error));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Veri katmanı kod döndürür, metni burada çözüyoruz.
  static String usernameErrorText(AppLocalizations l10n, UsernameError e) =>
      switch (e) {
        UsernameError.empty => l10n.usernameEmpty,
        UsernameError.invalid => l10n.usernameInvalid,
        UsernameError.taken => l10n.usernameTaken,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassPanel(
      label: l10n.usernameLabel,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.davetBekliyor) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.mail_outline_rounded,
                size: 18, color: RythoColors.goldBright),
            const SizedBox(width: RythoSpace.sm),
            Expanded(
                child: Text(l10n.inviteNeedsUsername, style: RythoType.body)),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _odak.requestFocus,
              child: Text(l10n.inviteNeedsUsernameAction,
                  style: RythoType.button),
            ),
          ),
          const SizedBox(height: RythoSpace.sm),
        ],
        Text(l10n.usernameHeadline, style: RythoType.sectionTitle),
        const SizedBox(height: RythoSpace.xs + RythoSpace.xxs),
        Text(l10n.usernameBody, style: RythoType.caption),
        const SizedBox(height: RythoSpace.md + RythoSpace.xxs),
        TextField(
          controller: _controller,
          focusNode: _odak,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 20,
          style: RythoText.body(15),
          decoration: InputDecoration(
            prefixText: '@',
            hintText: l10n.usernameHint,
            counterText: '',
            errorText: _error,
            hintStyle: RythoText.body(15, color: RythoColors.parchmentDim),
          ),
        ),
        const SizedBox(height: RythoSpace.md),
        GoldButton(text: l10n.claimUsername, busy: _busy, onPressed: _submit),
      ]),
    );
  }
}

/// Rehber ekranına KOMPAKT giriş (I-turu). Eski hâli büyük açıklama
/// kartları/uzun liste çiziyordu ("çok büyük" şikâyeti). Artık tek satır:
/// başlık + duruma göre alt yazı (N kişi uygulamada / aç / doğrula) +
/// ok. Dokununca tam ekran [ContactsScreen] açılır (aktif/pasif + davet).
class _ContactsEntry extends ConsumerWidget {
  const _ContactsEntry({required this.ayarAcik});

  final bool ayarAcik;

  void _ac(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ContactsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    String altYazi;
    VoidCallback onTap;

    if (!ayarAcik) {
      altYazi = l10n.contactsFindEnable;
      onTap = () async {
        await setContactMatch(true);
        ref.invalidate(profileProvider);
        ref.invalidate(contactMatchesProvider);
        if (context.mounted) _ac(context);
      };
    } else {
      final sonuc = ref.watch(contactMatchesProvider);
      altYazi = switch (sonuc) {
        AsyncData(:final value) => switch (value.blocker) {
            ContactMatchBlocker.telefonYok => l10n.contactsFindVerifyPhone,
            ContactMatchBlocker.izinYok => l10n.contactMatchPermTitle,
            null => l10n.contactsFindActive(value.active.length),
          },
        _ => '…',
      };
      onTap = () => _ac(context);
    }

    return ListeSatiri(
      margin: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: RythoSpace.sm),
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: RythoColors.inkLight,
          border: Border.all(color: RythoColors.glassStroke),
        ),
        child: const Icon(Icons.contacts_outlined,
            size: 19, color: RythoColors.parchment),
      ),
      title: l10n.contactsFindEntry,
      subtitle: altYazi,
      onTap: onTap,
    );
  }
}

/// SEN kartı — TEK SATIR (R3-4, cihaz bulgusu: "koca koca kartlar var").
///
/// @ad + seri rozeti solda; sağda üç küçük ikon: kullanıcı adını düzenle,
/// davet bağlantısını kopyala, Günlüğüm. Seri görünürlük anahtarı buradan
/// KALKTI — zaten Profil → Gizlilik'te duruyor (aynı Firestore alanı);
/// bir gizlilik ayarının sosyal ekranda yer kaplaması gerekmiyor.
class _MyCardPanel extends StatelessWidget {
  const _MyCardPanel({
    required this.username,
    required this.streakCount,
  });

  final String username;
  final int streakCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget ikon(String tooltip, IconData icon, VoidCallback onTap) =>
        IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 18, color: RythoColors.lilac),
          onPressed: onTap,
        );

    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: RythoSpace.md, vertical: RythoSpace.sm),
      child: Row(children: [
        Expanded(
          child: Text('@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RythoText.display(16, w: FontWeight.w600)),
        ),
        StreakBadge(count: streakCount),
        const SizedBox(width: RythoSpace.xs),
        // Kullanıcı adı bir dönem yalnızca BİR KEZ yazılabiliyordu; düzeltme
        // yolu bu ikon (AccountScreen).
        ikon(l10n.edit, Icons.edit_outlined, () {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountScreen()));
        }),
        ikon(l10n.copyInviteLink, Icons.link_rounded, () async {
          await Clipboard.setData(
              ClipboardData(text: inviteLinkFor(username)));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.inviteLinkCopied)));
          }
        }),
        // Günlüğüm (R3-4): "kişi kendisiyle ilgili günlükleri kendi
        // kartından takip edebilsin" — Profil listesinden buraya taşındı.
        ikon(l10n.profileDiaryRow, Icons.edit_note_rounded, () {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiaryScreen()));
        }),
      ]),
    );
  }
}

/// Bana gelen hazır tepkiler. Dokununca okundu sayılır ve silinir.
class _InboxPanel extends ConsumerWidget {
  const _InboxPanel({required this.friends});

  final List<Friend> friends;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // U17: engellediklerimin tepkileri süzülür (eski tepkiler dahil).
    final nudges = gorunurTepkiler(ref.watch(myNudgesProvider).value ?? const [],
        ref.watch(engellenenKimliklerProvider).value);
    if (nudges.isEmpty) return const SizedBox.shrink();

    // Gönderen listede yoksa NÖTR ad: tepkiyi yalnız kabul edilmiş arkadaş
    // atabilir ama o arkadaşlık sonradan bitmiş olabilir (çıkarma) ya da
    // liste henüz gelmemiştir. "Bir arkadaşın" ikisinde de yanlış bir beyan
    // olurdu.
    String nameOf(String? uid) {
      for (final friend in friends) {
        if (friend.uid == uid) return friend.ad(l10n);
      }
      return l10n.someRythoUser;
    }

    return GlassPanel(
      label: l10n.inboxLabel,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final nudge in nudges.take(6))
          if (kReactions[nudge['reaction']] case final emoji?)
            InkWell(
              borderRadius: BorderRadius.circular(RythoRadius.sm),
              onTap: () => dismissNudge(nudge['id'] as String),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: RythoSpace.sm),
                child: Row(children: [
                  Text(emoji, style: RythoText.emoji(18)),
                  const SizedBox(width: RythoSpace.sm + RythoSpace.xxs),
                  Expanded(
                    child: Text(
                      '${nameOf(nudge['fromUid'] as String?)} · '
                      '${reactionLabel(l10n, nudge['reaction'] as String)}',
                      style: RythoText.body(13.5),
                    ),
                  ),
                  const Icon(Icons.close_rounded,
                      size: 16, color: RythoColors.parchmentDim),
                ]),
              ),
            ),
      ]),
    );
  }
}

class _FriendsList extends StatelessWidget {
  const _FriendsList({required this.friends, this.boslugoster = true});

  final List<Friend> friends;

  /// Kişi listesi de boş mu? Değilse buradaki boş durum çizilmez.
  final bool boslugoster;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (friends.isEmpty) {
      if (!boslugoster) return const SizedBox.shrink();
      return EmptyState(
        emoji: '🛰️',
        title: l10n.noFriendsYet,
        description: l10n.noFriendsBody,
      );
    }

    final incoming =
        friends.where((f) => f.status == FriendStatus.incoming).toList();
    final accepted =
        friends.where((f) => f.status == FriendStatus.accepted).toList();
    final outgoing =
        friends.where((f) => f.status == FriendStatus.outgoing).toList();

    return Column(children: [
      if (incoming.isNotEmpty) ...[
        const SectionDivider(),
        _sectionTitle(l10n.incomingRequests),
        for (final friend in incoming) GelenIstekKarti(friend: friend),
      ],
      if (accepted.isNotEmpty) ...[
        const SectionDivider(),
        // "Arkadaşların" → "Rytho'daki arkadaşların": aşağıda ikinci bir
        // bölüm var ve ikisi farklı şeyler (P-turu).
        _sectionTitle(l10n.circleFriendsSection),
        for (final (i, friend) in accepted.indexed)
          RythoReveal(index: i, child: _FriendTile(friend: friend)),
      ],
      if (outgoing.isNotEmpty) ...[
        const SectionDivider(),
        _sectionTitle(l10n.pendingInvites),
        for (final friend in outgoing) _PendingTile(friend: friend),
      ],
    ]);
  }

  // Bölüm başlığı bir AD, ölçüm değil: etiket rolü (mono veri rolüydü).
  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.xl, RythoSpace.xs, RythoSpace.xl, RythoSpace.xxs),
        child: Text(text, style: RythoType.label),
      );
}

/// Arkadaş satırı — SLİM (R3-4, cihaz bulgusu: "az bilgi çok yer").
///
/// Baş harf avatarı + ad + tek satır durum; sağda İKİ eylem ikonu:
/// ⚡ tepki (KART AÇILMADAN — dokununca tepki sayfası, seçim anında
/// gider) ve 🪐 ilişki (dört eksenli okuma). Satırın kendisi arkadaş
/// detayını ("bugün aranızda") açar. Kap `ListeSatiri` (beş satır sınıfının
/// tek varisi): başlıkta ellipsis yok, iki satıra sarar.
class _FriendTile extends ConsumerWidget {
  const _FriendTile({required this.friend});

  final Friend friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ad = friend.ad(l10n);
    final durum = friend.streakVisible
        ? (friend.readToday ? l10n.readToday : l10n.notReadToday)
        : l10n.streakHidden;
    final altSatir = [
      if (friend.sunSign != null) localizedSignName(l10n, friend.sunSign),
      durum,
    ].join(' · ');

    return ListeSatiri(
      margin: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: RythoSpace.xs),
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: RythoColors.lilac.withValues(alpha: 0.16),
        // Baş harf Türkçe kuralla ("ilayda" → "İ"); `characters` ilk
        // öğeyi tam alır (emoji/birleşik harf yarım kalmaz).
        child: Text(trBuyuk(ad.characters.first),
            style: RythoText.display(14, color: RythoColors.lilac)),
      ),
      title: ad,
      subtitle: altSatir,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        // Tepki: kart açılmadan, iki dokunuş (⚡ → seçim).
        IconButton(
          tooltip: l10n.sendReaction,
          visualDensity: VisualDensity.compact,
          icon: Text('⚡', style: RythoText.emoji(16)),
          onPressed: () => showReactionSheet(context, ref, friend),
        ),
        // İlişki eksenleri (R2-L1) satırdan tek dokunuş uzakta.
        IconButton(
          tooltip: l10n.relationshipOpen,
          visualDensity: VisualDensity.compact,
          icon: Text('🪐', style: RythoText.emoji(15)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RelationshipScreen(friend: friend))),
        ),
      ]),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FriendDetailScreen(friend: friend))),
    );
  }
}

/// Gelen davet satırı: ⋯ (Engelle / Şikayet et) · Yoksay · Kabul et.
///
/// Kabul artık geri bildirim veriyor: düğme meşgul olur, sonuç SnackBar'la
/// söylenir. Eski hâli ateşle-unut idi — hata yutuluyor, kullanıcı
/// dokunuşun bir şey yaptığını ancak liste yenilenince anlıyordu.
/// Yoksay onaysız: davet yıkıcı değil, karşı taraf yeniden gönderebilir.
///
/// ⋯ düğmesi neden var (U17, App Store 1.2): Engelle ve Şikayet et yalnız
/// KABUL EDİLMİŞ arkadaşın sayfasındaydı. Kullanıcı adıyla istek atan bir
/// yabancıyı alıcı kabul etmeden ne engelleyebiliyor ne şikayet
/// edebiliyordu — "Yoksay" kenarı siliyordu ama gönderen hemen yeniden
/// atabiliyordu. Kabul etmek, bildirebilmenin bedeli olmamalı.
class GelenIstekKarti extends ConsumerStatefulWidget {
  const GelenIstekKarti({super.key, required this.friend});

  final Friend friend;

  @override
  ConsumerState<GelenIstekKarti> createState() => _GelenIstekKartiState();
}

class _GelenIstekKartiState extends ConsumerState<GelenIstekKarti> {
  bool _busy = false;

  Future<void> _kabul() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final dio = ref.read(apiProvider);
    final ad = widget.friend.ad(l10n);
    setState(() => _busy = true);
    try {
      await acceptFriendRequest(widget.friend.uid);
      // Kabul push'u (OB2): Firestore yazımı bitince daveti GÖNDERENE
      // haber ver. UI beklemez; push bir ek, kabulün kendisi değil.
      unawaited(notifyInviteAccepted(dio, widget.friend.uid));
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.friendAcceptedSnack(ad))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, l10n))));
    } finally {
      // Kabul edilen satır akış yenilenince yerini arkadaş satırına
      // bırakır — bu durum artık yaşamıyor olabilir.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassPanel(
      margin: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: RythoSpace.xs + 1),
      // Ad + iki düğme esnemeyen bir `Row`du: kullanıcı adının uzunluğu
      // bizim denetimimizde değil, üstelik "Yoksay" + sabit 104 px "Kabul
      // et" dar ekranda tek başına satırı dolduruyordu. `Wrap`: sığdığında
      // ad solda düğmeler sağda (eski görünüm), sığmadığında düğmeler alt
      // satıra iner. `SizedBox`: Wrap gevşek kısıtta büzülür.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: RythoSpace.sm,
          runSpacing: RythoSpace.xs + RythoSpace.xxs,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(widget.friend.ad(l10n), style: RythoType.cardTitle),
            Wrap(
              spacing: RythoSpace.xs,
              runSpacing: RythoSpace.xs,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: l10n.requestMoreActions,
                  visualDensity: VisualDensity.compact,
                  // Tooltip ekran okuyucuya AD vermez (semantik `tooltip`
                  // alanı); ikon-tek düğmenin adı `semanticLabel`dan gelir.
                  icon: Icon(Icons.more_horiz_rounded,
                      size: 20,
                      color: RythoColors.parchmentDim,
                      semanticLabel: l10n.requestMoreActions),
                  onPressed: _busy
                      ? null
                      : () => showFriendSafetySheet(context, ref, widget.friend),
                ),
                TextButton(
                  onPressed: _busy ? null : () => removeFriend(widget.friend.uid),
                  child: Text(l10n.ignore,
                      style:
                          RythoText.label(12, color: RythoColors.parchmentDim)),
                ),
                SizedBox(
                  width: 104,
                  child: GoldButton(
                      text: l10n.accept, busy: _busy, onPressed: _kabul),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Gönderilmiş, yanıt bekleyen davet.
class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.friend});

  final Friend friend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListeSatiri(
      margin: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: RythoSpace.xs),
      leading: const Icon(Icons.hourglass_top_rounded,
          size: 20, color: RythoColors.parchmentDim),
      title: friend.ad(l10n),
      subtitle: l10n.pending,
      trailing: IconButton(
        tooltip: l10n.withdrawInvite,
        icon: const Icon(Icons.close_rounded, size: 18),
        onPressed: () => removeFriend(friend.uid),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Arkadaş ekleme
// ---------------------------------------------------------------------------

/// Bekleyen daveti ekleme sayfasını açarak ele alır.
///
/// Kullanıcı adı YOKKEN niyet TEMİZLENMEZ: panel daveti söyler
/// (`_UsernameSetupPanel.davetBekliyor`), ad alınınca profil akışı yeniden
/// kurar ve bu kapı sayfayı açar. Burada temizlemek daveti kaybederdi.
///
/// Kendi davetini açmak anlamsız olduğu için sessizce yok sayılır — kullanıcı
/// kendi bağlantısını test ederken hata mesajıyla karşılaşmamalı.
void _handlePendingInvite(
    BuildContext context, WidgetRef ref, String? myUsername, String? invite) {
  if (invite == null || myUsername == null) return;

  // Durum değişikliği build sırasında yapılamaz.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    ref.read(pendingInviteProvider.notifier).clear();
    if (invite == myUsername) return;
    _showAddFriendSheet(context, myUsername, prefill: invite);
  });
}

/// Kişi formuna giden TEK kapı: önce kontenjan, sonra form.
Future<void> _kisiEkle(BuildContext context, WidgetRef ref) async {
  final kontenjan = ref.read(personSlotsProvider).value;
  if (kisiKontenjaniDolu(kontenjan)) {
    // Abone değilse daha çok kişi abonelikle gelir → satış ekranı (dokunuş
    // yolu, kesinti değil). Aboneyse ya da ayna bilinmiyorsa kontenjan
    // gerçekten dolu demektir → cümle; satış ekranı B10'un kusuruydu
    // (ödemiş kullanıcıya paywall). Sunucu 402'sindeki `paywallHedefi`
    // kuralının aynısı.
    if (ref.read(aboneAynasiProvider) == false) {
      await acPaywall(context,
          kaynak: PaywallKaynak.kilitKarti, ozellik: PlusOzellik.people);
      return;
    }
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            l10n.peopleSlotsOver(kontenjan!.limit, kontenjan.used))));
    return;
  }
  await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PersonFormScreen()));
}

/// "+" düğmesinin açtığı SEÇİM sayfası (P-turu).
///
/// Eskiden düğme doğrudan kullanıcı adı sayfasını açıyordu. Artık iki
/// ekleme yolu var ve **gizlilik anlamları farklı**: Rytho arkadaşı
/// karşılıklı onaydır ve karşı tarafın ham doğum verisi asla görülmez;
/// eklenen kişi ise kullanıcının kendi girdiği veridir. Bu farkı bir
/// açılır menüye gömmek yerine seçim anında yazıyoruz.
Future<void> _showAddChooser(
    BuildContext context, WidgetRef ref, String? myUsername) {
  final l10n = AppLocalizations.of(context);
  return showRythoSheet<void>(
    context,
    baslik: l10n.addChooserTitle,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(
          RythoSpace.lg, RythoSpace.lg, RythoSpace.lg, RythoSpace.lg),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _EkleSecenegi(
          icon: Icons.alternate_email_rounded,
          title: l10n.addChooserFriend,
          body: l10n.addChooserFriendBody,
          onTap: () {
            Navigator.of(sheetContext).pop();
            if (myUsername == null) {
              // Devre dışı düğme yerine SEBEBİ söyleyen düğme (R6).
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.addFriendNeedsUsername)));
              return;
            }
            _showAddFriendSheet(context, myUsername);
          },
        ),
        const SizedBox(height: RythoSpace.md),
        _EkleSecenegi(
          icon: Icons.person_add_alt_rounded,
          title: l10n.addChooserPerson,
          body: l10n.addChooserPersonBody,
          onTap: () {
            Navigator.of(sheetContext).pop();
            _kisiEkle(context, ref);
          },
        ),
      ]),
    ),
  );
}

class _EkleSecenegi extends StatelessWidget {
  const _EkleSecenegi({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      tone: GlassTone.raised,
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: RythoColors.lilac),
        const SizedBox(width: RythoSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(title, style: RythoText.body(15, w: FontWeight.w700)),
            const SizedBox(height: RythoSpace.xs),
            Text(body, style: RythoType.caption),
          ]),
        ),
      ]),
    );
  }
}

/// EKLENEN KİŞİLER bölümü — arkadaş satırından bilinçli olarak FARKLI.
///
/// Tepki ikonu, seri rozeti ve "bugün okudu" YOK: karşı tarafta bir
/// kullanıcı yok. Olmayan etkileşimi çizmek, ürünün "ölçülmeyen
/// söylenmez" duruşunun arayüz tarafındaki karşılığını çiğnemek olurdu.
class _PeopleSection extends ConsumerWidget {
  const _PeopleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final kisiler = ref.watch(peopleProvider).value ?? const <Person>[];
    final kontenjan = ref.watch(personSlotsProvider).value;

    if (kisiler.isEmpty) {
      return GlassPanel(
        tone: GlassTone.raised,
        margin: const EdgeInsets.fromLTRB(
            RythoSpace.xl, RythoSpace.xl + RythoSpace.xs, RythoSpace.xl, 0),
        onTap: () => _kisiEkle(context, ref),
        child: Row(children: [
          const Icon(Icons.favorite_rounded,
              size: 20, color: RythoColors.lilac),
          const SizedBox(width: RythoSpace.md),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.circleEmptyTitle,
                      style: RythoText.body(14.5, w: FontWeight.w700)),
                  const SizedBox(height: RythoSpace.xxs + 1),
                  Text(l10n.circleEmptyBody, style: RythoType.caption),
                ]),
          ),
        ]),
      );
    }

    final beyan = kontenjan == null || kontenjan.limit <= 0
        ? null
        : kontenjanBeyani(l10n, used: kontenjan.used, limit: kontenjan.limit);

    return Column(children: [
      const SectionDivider(),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.xl, RythoSpace.xs, RythoSpace.xl, RythoSpace.xxs),
        // `Row` + `Spacer` ile iki esnemeyen metin: uzun bölüm başlığı +
        // kontenjan sayacı dar ekranda satırı taşırıyordu (SectionHeader
        // ile aynı kusur sınıfı). `Wrap` sığdığında aynı görünür, aksi
        // hâlde sayaç alt satıra iner. `SizedBox`: Wrap gevşek kısıtta
        // büzülür ve `spaceBetween` yayacak boşluk bulamaz.
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: RythoSpace.md,
            runSpacing: RythoSpace.xxs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(l10n.circlePeopleSection, style: RythoType.label),
              if (beyan != null) Text(beyan.sayac, style: RythoType.label),
            ],
          ),
        ),
      ),
      // Aşım beyanı: sayı gizlenmez, adı düzelir (bkz. `kontenjanBeyani`).
      if (beyan?.asim case final asim?)
        Padding(
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.xl, RythoSpace.xs, RythoSpace.xl, RythoSpace.xs),
          child: Text(asim,
              style: RythoType.caption.copyWith(color: RythoColors.caution)),
        ),
      for (final (i, kisi) in kisiler.indexed)
        RythoReveal(index: i, child: _PersonTile(person: kisi)),
    ]);
  }
}

/// Kişi satırı: tür ikonu + etiket + burç. Satırın kendisi kişi ekranını
/// açar; sağda chevron (`ListeSatiri` varsayılanı). Eski 🪐/`public`
/// ikonu düğme DEĞİLDİ — dokunulmaz bir ikon, eylem vaat ediyordu.
class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ad = person.label ?? relationLabel(l10n, person.relation);

    return ListeSatiri(
      margin: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: RythoSpace.xs),
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: RythoColors.lilac.withValues(alpha: 0.18),
        ),
        child: Icon(relationIcon(person.relation),
            size: 17, color: RythoColors.lilac),
      ),
      title: ad,
      subtitle: person.sunSign != null
          ? localizedSignName(l10n, person.sunSign)
          : relationLabel(l10n, person.relation),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PersonDetailScreen(person: person))),
    );
  }
}

Future<void> _showAddFriendSheet(BuildContext context, String myUsername,
    {String? prefill}) {
  final l10n = AppLocalizations.of(context);
  // Kabuk tek (`showRythoSheet`): klavye dolgusu sayfanın kendi
  // context'inden okunur (`klavyeyeUy`) — eski kopya dıştaki context'ten
  // okuyup 0 kalıyordu ve giriş alanı klavyenin altında gizleniyordu.
  return showRythoSheet<void>(
    context,
    baslik: l10n.addFriend,
    klavyeyeUy: true,
    builder: (_) => _AddFriendSheet(myUsername: myUsername, prefill: prefill),
  );
}

class _AddFriendSheet extends ConsumerStatefulWidget {
  const _AddFriendSheet({required this.myUsername, this.prefill});

  final String myUsername;

  /// Davet baglantisindan gelen kullanici adi; kutu dolu acilir.
  final String? prefill;

  @override
  ConsumerState<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<_AddFriendSheet> {
  final _controller = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefill != null) _controller.text = widget.prefill!;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    // l10n ve messenger await ÖNCESİ alınır: sonrasında context artık
    // güvenilir değil (use_build_context_synchronously).
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final dio = ref.read(apiProvider);

    setState(() {
      _busy = true;
      _message = null;
    });
    // Kullanıcı adı ASCII'ye zorlanmış (`kUsernamePattern`): `toLowerCase`
    // burada DOĞRU araç, `trKucuk` değil — "ISIK" → "ısık" geçersiz ad
    // üretirdi. turkce_harf_test allowlist gerekçesi bu satır.
    final username = _controller.text.trim().toLowerCase();
    try {
      if (username == widget.myUsername) {
        setState(() => _message = l10n.cannotAddSelf);
        return;
      }
      final uid = await uidForUsername(username);
      if (uid == null) {
        setState(() => _message = l10n.userNotFound(username));
        return;
      }
      if (!mounted) return;
      // U17: engellediğin kişiye davet ancak engeli kaldırarak gider.
      final karar = await davetEngelKapisi(context, ref, uid, '@$username');
      if (karar == DavetKarari.vazgec) return;
      await sendFriendRequest(uid,
          engeliKaldir: karar == DavetKarari.engeliKaldirVeGonder);
      // Davet push'u (OB2): kenarlar yazıldıktan SONRA — sunucu gerçek
      // `incoming` kenarını doğruluyor. Ateşle-unut; UI beklemez.
      unawaited(notifyInvite(dio, uid));
      Analytics.friendInviteSent();
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.inviteSent(username))));
    } catch (e) {
      if (mounted) setState(() => _message = davetHataMetni(e, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          RythoSpace.lg, RythoSpace.md, RythoSpace.lg, RythoSpace.xl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _controller,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 20,
          style: RythoText.body(15),
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(
            prefixText: '@',
            hintText: l10n.usernameHint,
            counterText: '',
            errorText: _message,
            hintStyle: RythoText.body(15, color: RythoColors.parchmentDim),
          ),
        ),
        const SizedBox(height: RythoSpace.md),
        GoldButton(text: l10n.sendInvite, busy: _busy, onPressed: _send),
        const SizedBox(height: RythoSpace.sm + RythoSpace.xxs),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(
                ClipboardData(text: inviteLinkFor(widget.myUsername)));
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.link_rounded, size: 18),
          label: Text(l10n.shareInviteInstead, style: RythoText.label(12)),
        ),
      ]),
    );
  }
}

/// Güvenlik menüsündeki seçim — sayfa yalnız SEÇİMİ döndürür, eylem
/// sayfa kapandıktan sonra ve onaydan geçerek yapılır.
enum _GuvenlikSecimi { cikar, engelle, sikayet }

/// Arkadaş / istek menüsü: çıkarma, engelleme, şikâyet.
///
/// İki yerden açılır: arkadaş detayının ⋮ düğmesi ve gelen istek
/// kutucuğunun ⋯ düğmesi ([GelenIstekKarti]). Engelleme ikisinde de aynı
/// yoldan geçer ([kullaniciyiEngelle]: kenarlar + engel kaydı tek batch).
/// "Arkadaşlıktan çıkar" yalnız kabul edilmiş arkadaşta: gelen istekte o
/// iş "Yoksay"ın ve o adla sunulursa yanlış ad olur.
///
/// `true` döner: arkadaş çıkarıldı ya da engellendi (çağıran ekranı
/// kapatır). Çıkarma ve engelleme ONAYLI (`onayla`, yıkıcı): eski hâli
/// tek dokunuşla iki tarafın kenarını siliyordu — geri dönüşü olmayan
/// eylem, onay sorusu olmadan.
Future<bool> showFriendSafetySheet(
    BuildContext context, WidgetRef ref, Friend friend) async {
  final l10n = AppLocalizations.of(context);
  final ad = friend.ad(l10n);
  // İkisi de İLK `await`ten önce alınır: engel inince istek kutucuğu
  // listeden düşer; o noktada `ref` artık kullanılamaz, `context` de
  // yaşamıyor olabilir.
  final engelle = ref.read(engelleyiciProvider);
  final mesajci = ScaffoldMessenger.of(context);
  final secim = await showRythoSheet<_GuvenlikSecimi>(
    context,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.only(bottom: RythoSpace.sm),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (friend.status == FriendStatus.accepted)
          ListTile(
            leading: const Icon(Icons.person_remove_rounded, size: 20),
            title: Text(l10n.removeFriend, style: RythoType.body),
            onTap: () =>
                Navigator.of(sheetContext).pop(_GuvenlikSecimi.cikar),
          ),
        ListTile(
          leading: const Icon(Icons.block_rounded, size: 20),
          title: Text(l10n.blockUser, style: RythoType.body),
          onTap: () =>
              Navigator.of(sheetContext).pop(_GuvenlikSecimi.engelle),
        ),
        ListTile(
          leading: const Icon(Icons.flag_outlined, size: 20),
          title: Text(l10n.reportUser, style: RythoType.body),
          onTap: () =>
              Navigator.of(sheetContext).pop(_GuvenlikSecimi.sikayet),
        ),
      ]),
    ),
  );
  if (secim == null || !context.mounted) return false;

  switch (secim) {
    case _GuvenlikSecimi.cikar:
      final tamam = await onayla(
        context,
        title: l10n.removeFriendConfirmTitle,
        body: l10n.removeFriendConfirmBody(ad),
        confirmLabel: l10n.removeFriend,
        destructive: true,
      );
      if (!tamam) return false;
      await removeFriend(friend.uid);
      return true;
    case _GuvenlikSecimi.engelle:
      final tamam = await onayla(
        context,
        title: l10n.blockUserConfirmTitle,
        body: l10n.blockUserConfirmBody(ad),
        confirmLabel: l10n.blockUser,
        destructive: true,
      );
      if (!tamam) return false;
      // Eskiden iki çıplak `await`ti (`removeFriend` + `blockUser`): yazım
      // düşünce hata yakalanmıyor, kullanıcı hiçbir şey görmüyor ve
      // engellediğini sanıyordu. Sonuç artık SÖYLENİR.
      try {
        await engelle(friend.uid);
      } catch (_) {
        mesajci.showSnackBar(SnackBar(content: Text(l10n.blockFailed)));
        return false;
      }
      mesajci.showSnackBar(SnackBar(content: Text(l10n.userBlockedSnack(ad))));
      return true;
    case _GuvenlikSecimi.sikayet:
      showReportSheet(context, targetType: 'user', targetId: friend.uid);
      return false;
  }
}

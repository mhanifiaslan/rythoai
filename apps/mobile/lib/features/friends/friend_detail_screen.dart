import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/api.dart';
import '../../core/discovery.dart';
import '../../core/friends.dart';
import '../../core/okuma_durumu.dart';
import '../../core/sound.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/liste_satiri.dart';
import '../../widgets/motion.dart';
import '../../widgets/nebula_widgets.dart' show Pressable, localizedSignName;
import '../../widgets/okuma_kabi.dart';
import '../../widgets/star_burst.dart';
import '../chat/chat_screen.dart' show ChatScreen;
import '../paywall/bedel_rozeti.dart';
import '../paywall/ozellik_katalogu.dart';
import 'friends_screen.dart' show showFriendSafetySheet;
import 'relationship_screen.dart';

/// Geri bildirim kanalındaki ekran kodu (`FeedbackScreen.screen` kapalı
/// kümesi): arkadaş ekranı Çevrem sekmesinin altında yaşar.
const String kArkadasEkranKodu = 'circle';

/// Kutlama görünür kalma süresi — hareket token'ı DEĞİL, ölçülmüş bir UX
/// bekleme süresi: seçim kalıcı kalınca ikinci dürtme için ekrandan çıkıp
/// girmek gerekiyordu (iç test bulgusu); `celebrate` (400 ms) patlamanın
/// süresi, bu ise kullanıcının kutlamayı GÖRDÜĞÜ süre.
const Duration kTepkiKutlamaSuresi = Duration(milliseconds: 1200);

/// Arkadaş detayı: bugüne özgü ikili dinamik + hazır tepki gönderme.
///
/// Kalıcı bir uyum skoru **bilinçli olarak gösterilmez**: skor ölçüm değil
/// gelenektir ve geri alınamaz bir damga gerçek ilişkilere zarar verir.
/// Okuma her gün yenilenir ve iki taraf da aynı metni görür.
class FriendDetailScreen extends ConsumerStatefulWidget {
  const FriendDetailScreen({super.key, required this.friend});

  final Friend friend;

  @override
  ConsumerState<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends ConsumerState<FriendDetailScreen> {
  /// Okumanın durumu — `fallback` bayrağı yalnız `okumaDurumuFromYanit`te
  /// okunur. Eski hâli `reading as String?` idi ve şablon paragrafı rapor
  /// gibi gösteriyordu (jeton iadesi de hiç söylenmiyordu).
  OkumaDurumu _durum = const OkumaYukleniyor();
  String? _sentReaction;

  @override
  void initState() {
    super.initState();
    // OB4: çevreden birine bakmak keşif halkasının üçüncü dilimi.
    ref.read(discoveryProvider.notifier).mark(DiscoveryTask.circle);
    // ⚠️ Bedel (dyad, 3 kredi) burada OTOMATİK harcanıyor — dokunuşsuz.
    // Harcama öncesi onay kapısı (`kOnayEsigi`) D7 kararı; rozet
    // (`BedelRozeti`) bedeli en azından görünür kılıyor.
    _loadDyad();
  }

  Future<void> _loadDyad() async {
    setState(() => _durum = const OkumaYukleniyor());
    try {
      final dio = ref.read(apiProvider);
      final response = await dio.post('/api/v1/reports/dyad',
          data: {'friend_uid': widget.friend.uid});
      if (!mounted) return;
      final veri = response.data['data'] is Map
          ? Map<String, dynamic>.from(response.data['data'] as Map)
          : null;
      final durum = okumaDurumuFromYanit(veri, alan: 'reading');
      setState(() => _durum = durum);
      // Analitik yalnız GERÇEK üretimde: şablon düşüşü "rapor üretildi"
      // sayılırsa sayaç bir ay boyunca yeşil yalan söyler (CLAUDE.md §6).
      if (durum is OkumaHazir) Analytics.reportGenerated('dyad');
    } catch (e) {
      if (mounted) setState(() => _durum = OkumaHata(e));
    }
  }

  Future<void> _react(String key) async {
    // Ses + kıvılcım iyimser: gönderim başarısız olursa seçim zaten geri
    // alınıyor; tepki anı dokunuşta hissedilmeli, sunucu turundan sonra
    // değil (R12-C2).
    SoundFx.like();
    setState(() => _sentReaction = key);
    final dio = ref.read(apiProvider);
    try {
      await sendReaction(widget.friend.uid, key);
      Analytics.reactionSent(key);
      // Bildirimi tetikle. Başarısız olsa bile tepki gönderilmiş sayılır;
      // arkadaş uygulamayı açtığında gelen kutusunda görecek.
      await notifyReaction(dio, widget.friend.uid, key);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)
                .reactionSent(kReactions[key]!))));
      }
      // Kutlama görünsün, sonra çipler yeniden açılsın — kilit yalnız
      // gönderim anlığı içindir (bkz. `kTepkiKutlamaSuresi`).
      await Future<void>.delayed(kTepkiKutlamaSuresi);
      if (mounted) setState(() => _sentReaction = null);
    } catch (e) {
      if (mounted) {
        setState(() => _sentReaction = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e, AppLocalizations.of(context)))));
      }
    }
  }

  Future<void> _guvenlikMenusu() async {
    final gitti = await showFriendSafetySheet(context, ref, widget.friend);
    // Çıkarılan/engellenen arkadaşın ekranında kalmak, artık var olmayan
    // bir ilişkiyi göstermek olurdu.
    if (gitti && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final friend = widget.friend;
    final ad = friend.ad(l10n);
    return CosmicScaffold(
      appBar: AppBar(
        title: Text(ad),
        actions: [
          IconButton(
            // ⚠️ Menünün kendi adı için ARB anahtarı yok (çıkar/engelle/
            // şikâyet = gizlilik eylemleri); kalemlerden birinin adını
            // bütüne vermek ekran okuyucuyu yanıltırdı, "Gizlilik" üçünü
            // de kapsıyor. D8 ARB turunda `friendMenuTooltip` ister.
            tooltip: l10n.privacy,
            icon: const Icon(Icons.more_vert, size: 20),
            onPressed: _guvenlikMenusu,
          ),
        ],
      ),
      body: ListView(
          padding: const EdgeInsets.only(bottom: RythoSpace.xxl),
          children: [
        GlassPanel(
          label: l10n.friendLabel,
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ad, style: RythoText.display(20)),
                    if (friend.username != null) ...[
                      const SizedBox(height: RythoSpace.xxs),
                      Text('@${friend.username}',
                          style: RythoText.body(12.5,
                              color: RythoColors.parchmentDim)),
                    ],
                    const SizedBox(height: RythoSpace.sm),
                    if (friend.streakVisible)
                      Text(
                        friend.readToday
                            ? l10n.readTodayDone
                            : l10n.notReadToday,
                        style: RythoText.body(12.5,
                            color: friend.readToday
                                ? RythoColors.goldBright
                                : RythoColors.parchmentDim),
                      )
                    else
                      Text(l10n.streakHiddenByFriend,
                          style: RythoText.body(12.5,
                              color: RythoColors.parchmentDim)),
                  ]),
            ),
            if (friend.sunSign != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: RythoSpace.md, vertical: RythoSpace.sm),
                decoration: BoxDecoration(
                  color: RythoColors.lilac.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(RythoRadius.pill),
                  border: Border.all(
                      color: RythoColors.lilac.withValues(alpha: 0.3)),
                ),
                child: Text(localizedSignName(l10n, friend.sunSign),
                    style: RythoText.label(11.5, color: RythoColors.lilac)),
              ),
          ]),
        ),
        _DyadPanel(
          durum: _durum,
          onTekrarDene: _loadDyad,
          // Bağlamlı sohbet (R4-2): bu arkadaş hakkında soru — sunucu
          // ilişki eksenlerini fısıldar, cevap İKİ KİŞİYE özel olur. Tohum
          // ÖN-DOLDURUR, göndermez; eski boş kutu sohbeti boş açıyordu.
          onSor: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChatScreen(
                  friendUid: friend.uid,
                  initialText: l10n.askAboutFriendPrefill(ad)))),
        ),
        // İlişki eksenleri (R2-L1): günlük ikili okuma "bugün"ü anlatır,
        // bu giriş ilişkinin KALICI zeminini açar. Skor yok — dört eksende
        // nitel okuma + dayanağı.
        ListeSatiri(
          leading: Text('🪐', style: RythoText.emoji(18)),
          title: l10n.relationshipOpen,
          subtitle: l10n.relationshipOpenSubtitle,
          subtitleLines: 2,
          margin: const EdgeInsets.symmetric(
              horizontal: RythoSpace.lg, vertical: RythoSpace.xs),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RelationshipScreen(friend: friend))),
        ),
        const SectionDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.xl, RythoSpace.xs, RythoSpace.xl, RythoSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.sendReaction, style: RythoType.sheetTitle),
            const SizedBox(height: RythoSpace.xs),
            Text(l10n.sendReactionBody, style: RythoType.caption),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
          child: Wrap(
            spacing: RythoSpace.sm,
            runSpacing: RythoSpace.sm,
            children: [
              for (final entry in kReactions.entries)
                // Seçilen çipin üstünde 8 kıvılcımlık mini patlama
                // (R12-C2): sosyal katmanın tek etkileşimi eskiden yalnız
                // renk değişimi + SnackBar'dı.
                if (_sentReaction == entry.key && !reduceMotion(context))
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: OverflowBox(
                          maxWidth: 90,
                          maxHeight: 90,
                          child: const StarBurst(size: 90, particles: 8),
                        ),
                      ),
                      _ReactionChip(
                        emoji: entry.value,
                        label: reactionLabel(l10n, entry.key),
                        selected: true,
                        onTap: null,
                      ),
                    ],
                  )
                else
                  _ReactionChip(
                    emoji: entry.value,
                    label: reactionLabel(l10n, entry.key),
                    selected: _sentReaction == entry.key,
                    onTap:
                        _sentReaction == null ? () => _react(entry.key) : null,
                  ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Hazır tepki etiketleri dile göre çözülür.
///
/// Anahtarlar (`streak`, `shine` ...) Firestore kuralında da geçtiği için
/// sabittir; yalnızca gösterilen metin değişir.
String reactionLabel(AppLocalizations l10n, String key) => switch (key) {
      'streak' => l10n.reactionStreak,
      'thinking_of_you' => l10n.reactionThinkingOfYou,
      'shine' => l10n.reactionShine,
      'keep_going' => l10n.reactionKeepGoing,
      'congrats' => l10n.reactionCongrats,
      'same_frequency' => l10n.reactionSameFrequency,
      'good_night' => l10n.reactionGoodNight,
      'check_today' => l10n.reactionCheckToday,
      'hug' => l10n.reactionHug,
      'luck' => l10n.reactionLuck,
      'coffee' => l10n.reactionCoffee,
      'miss' => l10n.reactionMiss,
      _ => key,
    };

/// "Bugün aranızda" paneli — okumanın KABI `OkumaKabi` (tek kap, dokuz
/// yüzey). Paylaşım BİLEREK yok: ikili okuma üçüncü bir kişi hakkında
/// (sahip kararı). Hazır dalda altta günlük geçerlilik notu.
class _DyadPanel extends StatelessWidget {
  const _DyadPanel({
    required this.durum,
    required this.onTekrarDene,
    required this.onSor,
  });

  final OkumaDurumu durum;
  final VoidCallback onTekrarDene;
  final VoidCallback onSor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassPanel(
      label: l10n.dyadLabel,
      glow: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Bedel rozeti: okuma otomatik harcıyor, en azından bedeli söyler.
        // Cüzdan bilinmiyorsa rozet kendini çizmez (ölçülmeyen söylenmez).
        const Align(
          alignment: Alignment.centerRight,
          child: BedelRozeti(PlusOzellik.dyad, kucuk: true),
        ),
        OkumaKabi(
          durum: durum,
          ekranKodu: kArkadasEkranKodu,
          onTekrarDene: onTekrarDene,
          onSor: onSor,
          beklemeAsamalari: [l10n.onboardingStage1],
        ),
        if (durum is OkumaHazir) ...[
          const SizedBox(height: RythoSpace.md),
          Text(l10n.dyadDisclaimer, style: RythoType.caption),
        ],
      ]),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: RythoSpace.md, vertical: RythoSpace.sm),
        decoration: BoxDecoration(
          color: selected
              ? RythoColors.gold.withValues(alpha: 0.18)
              : RythoColors.glassFill,
          borderRadius: BorderRadius.circular(RythoRadius.pill),
          border: Border.all(
            color: selected
                ? RythoColors.gold.withValues(alpha: 0.5)
                : RythoColors.glassStroke,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: RythoText.emoji(15)),
          const SizedBox(width: RythoSpace.xs),
          // Çip etiketi (ilişki türü) dile bağlı ve esnemiyordu; çip
          // `Wrap` içinde gevşek kısıt aldığı için uzun etiket kendi
          // satırından taşıyordu. `Flexible` sarmasına izin verir.
          Flexible(
            child: Text(label,
                style: RythoText.label(12,
                    color: selected
                        ? RythoColors.goldBright
                        : RythoColors.parchment)),
          ),
        ]),
      ),
    );
  }
}

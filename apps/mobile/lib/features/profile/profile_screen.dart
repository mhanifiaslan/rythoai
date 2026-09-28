import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_service.dart' show signOutEverywhere;

import '../../theme/rytho_tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart' show SkeletonPanel;
import 'account_screen.dart';
import 'birth_record_screen.dart';
import 'feedback_screen.dart';
import 'avatar_editor.dart';
import 'profile_sections.dart';
import 'residence_dialog.dart';
import 'sign_in_methods_screen.dart';
import 'subscription_screen.dart';
import '../../core/providers.dart';
import '../../core/subscription.dart';
import '../../core/wallet.dart';
import '../../theme/rytho_theme.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/nebula_widgets.dart';
import '../../l10n/app_localizations.dart';

/// SİCİL — kendi profilin: kimlik, günlük seri ve **altı ayar satırı**.
///
/// ## Yeniden kurgulandı
///
/// Önceki hâl ~1400 px'di: yedi kart ve satır içine serpiştirilmiş on dört
/// kontrol. Kullanıcının tarifi "aşağı doğru uzayan bir liste" idi ve önerisi
/// de doğruydu — "aynı kategoriler bir başlıkta toplanılarak tıklanınca alt
/// seçenekler çıkabilir".
///
/// Gruplama aslında **vardı**; sorun tek seviyeli olmasıydı. Yedi başlık
/// hepsi açık hâlde alt alta duruyordu, yani gruplama hiçbir şey gizlemiyor,
/// yalnızca araya başlık koyuyordu. Şimdi her grup kendi sayfasında
/// (bkz. profile_sections.dart).
///
/// Bu ekran yalnızca kullanıcının kendisine gösterilir; `users/{uid}` dokümanı
/// doğum verisi içerdiği için Firestore'da da yalnızca sahibine okunabilir.
/// Arkadaşların gördüğü alanlar ayrı bir karttan gelir (`publicProfiles/{uid}`).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Bildirim izni buradan İSTENMİYOR: profil ekranını açmak izin sormak için
  // yanlış an. İzin, kullanıcı ilk değeri gördükten sonra ana ekranda
  // isteniyor (bkz. core/notifications.dart ve sky_screen).

  @override
  Widget build(BuildContext context) {
    final profilAsync = ref.watch(profileProvider);
    final profile = profilAsync.value ?? {};
    final user = FirebaseAuth.instance.currentUser;
    final l10n = AppLocalizations.of(context);

    // Profil henüz yüklenmediyse iskelet (R12-B3): eskiden bu ekran boş
    // haritayla ("yok" gibi görünen alanlarla) açılıyordu.
    if (profilAsync.isLoading && profile.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l10n.profileTitle)),
        body: ListView(
            padding: const EdgeInsets.only(top: 20, bottom: 110),
            children: const [
              SkeletonPanel(height: 140),
              SkeletonPanel(height: 84),
              SkeletonPanel(height: 220),
            ]),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 110),
          children: [
        const SizedBox(height: 12),
        Center(
          // Avatar dokunulabilir (U1): galeriden seç → konumlandır/
          // yakınlaştır → yükle. Küçük kalem rozeti dokunulabilirliği
          // İLAN eder — rozetsiz avatar "sadece resim" okunur.
          child: Pressable(
            onTap: _fotoDegistir,
            child: Stack(children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RythoColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                        color: RythoColors.magentaGlow, blurRadius: 26),
                  ],
                ),
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: RythoColors.inkLight,
                  backgroundImage: profile['photoUrl'] != null
                      ? NetworkImage(profile['photoUrl'])
                      : null,
                  child: profile['photoUrl'] == null
                      ? Text('☽', style: RythoText.display(28))
                      : null,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: RythoColors.inkLighter,
                    shape: BoxShape.circle,
                    border: Border.all(color: RythoColors.glassStroke),
                  ),
                  child: const Icon(Icons.edit_rounded,
                      size: 12, color: RythoColors.goldBright),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
              profile['displayName'] ??
                  user?.displayName ??
                  l10n.defaultUserName,
              style: RythoText.display(26)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(user?.email ?? '',
              style: RythoText.mono(11, color: RythoColors.parchmentDim)),
        ),
        const SizedBox(height: 14),
        Center(
          child: Wrap(spacing: 8, children: [
            for (final badge in [
              if (profile['sunSign'] != null)
                (
                  emoji: '☀️',
                  text: localizedSignName(l10n, profile['sunSign'] as String?)
                ),
              if (profile['moonSign'] != null)
                (
                  emoji: '🌙',
                  text: localizedSignName(l10n, profile['moonSign'] as String?)
                ),
              if (profile['ascendant'] != null)
                (
                  emoji: '⬆️',
                  text: localizedSignName(l10n, profile['ascendant'] as String?)
                ),
            ])
              Builder(builder: (_) {
                // Profildeki değerler sembol içeriyor ("Kova ♒"), birebir
                // eşleşme tutmaz — rozet rengi bu yüzden hep varsayılana
                // düşüyordu.
                final signIndex = signIndexOf(badge.text);
                final color = signIndex >= 0
                    ? RythoColors.signColors[signIndex]
                    : RythoColors.lilac;
                // Firestore'daki değer Türkçe ("Kova ♒"); rozet metni arayüz
                // diline çevrilir, tanınmazsa geldiği gibi gösterilir.
                final ad = signIndex >= 0
                    ? signDisplayName(l10n, signIndex)
                    : badge.text;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${badge.emoji} $ad',
                      style: RythoText.body(12, w: FontWeight.w700)),
                );
              }),
          ]),
        ),
        // Takipçi/takip sayaçları kaldırıldı: tek yönlü takip yerine karşılıklı
        // arkadaşlık modeli kullanılıyor (bkz. features/friends).
        // Günlük seri kartı 🔥
        Plaque(
          label: l10n.dailyStreak,
          child: Row(children: [
            const Text('🔥', style: TextStyle(fontSize: 30)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.streakDays(
                          (profile['streakCount'] as num?)?.toInt() ?? 0),
                      style: RythoText.display(20),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.streakBody,
                      style: RythoText.body(12,
                          color: RythoColors.parchmentDim),
                    ),
                  ]),
            ),
            StreakBadge(
                count: (profile['streakCount'] as num?)?.toInt() ?? 0),
          ]),
        ),
        // ---------- İKİ SEVİYELİ AYARLAR ----------
        //
        // Önceki hâl: yedi kart ve satır içine serpiştirilmiş on dört
        // kontrol, ~1400 px. Gruplama vardı ama TEK SEVİYELİYDİ — her grup
        // açıktı, hepsi aynı anda görünüyordu. Gruplamanın işe yaraması için
        // kapanabilmesi gerekiyor.
        //
        // Doğum kaydı ve hesap ayrıca DÜZELTİLEBİLİR oldu; daha önce ikisi
        // de bir kez yazılıp kilitleniyordu.
        // R3-5: tek uzun liste → BAŞLIKLI GRUPLAR (cihaz bulgusu: "profil
        // çok kalabalık, benzer işlevler aynı başlık altında toplansın").
        // Günlüğüm satırı buradan KALKTI — Arkadaşlar'daki SEN kartında.
        // Hesap silme de Hesap ekranının içine taşındı (mağaza "gömülü
        // olmamalı" kuralı bozulmaz: Hesap tek dokunuş uzakta ve satır
        // orada açıkça görünür).
        _grupBaslik(l10n.profileSectionIdentity),
        Plaque(
          padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
          child: Column(children: [
            SettingsRow(
              icon: Icons.cake_outlined,
              title: l10n.birthRecord,
              subtitle: l10n.birthRecordRowSubtitle,
              value: profile['birthDate'] as String?,
              onTap: () => _ac(const BirthRecordScreen()),
            ),
            const Divider(height: 1, indent: RythoSpace.lg),
            // Yaşanan şehir (D3): doğum şehrinden AYRI durur — natal
            // haritanın verisi o, bu ise yıl haritasının kurulacağı yer.
            SettingsRow(
              icon: Icons.location_city_outlined,
              title: l10n.residenceCityTitle,
              subtitle: l10n.residenceCityRowSubtitle,
              value: profile['residenceCity'] as String?,
              onTap: () => showResidenceDialog(context, ref),
            ),
          ]),
        ),
        _grupBaslik(l10n.profileSectionAccount),
        Plaque(
          padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
          child: Column(children: [
            SettingsRow(
              icon: Icons.person_outline_rounded,
              title: l10n.accountSection,
              value: profile['username'] != null
                  ? '@${profile['username']}'
                  : profile['displayName'] as String?,
              onTap: () => _ac(const AccountScreen()),
            ),
            const Divider(height: 1, indent: RythoSpace.lg),
            // Giriş yöntemleri (F4): şifre atama + Google bağlama.
            SettingsRow(
              icon: Icons.key_outlined,
              title: l10n.signInMethodsRow,
              value: signInMethodsSummary(user, l10n),
              onTap: () => _ac(const SignInMethodsScreen()),
            ),
          ]),
        ),
        _grupBaslik(l10n.profileSectionPrefs),
        Plaque(
          padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
          child: Column(children: [
            SettingsRow(
              icon: Icons.notifications_none_rounded,
              title: l10n.notifications,
              onTap: () => _ac(const NotificationSettingsScreen()),
            ),
            const Divider(height: 1, indent: RythoSpace.lg),
            SettingsRow(
              icon: Icons.lock_outline_rounded,
              title: l10n.privacy,
              onTap: () => _ac(const PrivacySettingsScreen()),
            ),
            const Divider(height: 1, indent: RythoSpace.lg),
            SettingsRow(
              icon: Icons.tune_rounded,
              title: l10n.languageAndSounds,
              onTap: () => _ac(const AppearanceSettingsScreen()),
            ),
            const Divider(height: 1, indent: RythoSpace.lg),
            // GB-turu: uygulama içi geri bildirim kanalı. Mağaza yorumu
            // ve e-posta dışında, kullanıcının bize tek dokunuşla
            // ulaşabildiği yer burası; yanıt bildirim olarak döner.
            SettingsRow(
              icon: Icons.forum_outlined,
              title: l10n.profileFeedback,
              onTap: () => _ac(const FeedbackScreen()),
            ),
          ]),
        ),
        _grupBaslik('Rytho+'),
        Plaque(
          padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
          child: Column(children: [
            // Abonelik + kredi bilgisi (A1): plan, yenilenme, bakiye —
            // hepsi tek ekranda.
            SettingsRow(
              icon: Icons.workspace_premium_outlined,
              title: l10n.profileSubscriptionRow,
              value: _abonelikOzeti(ref, l10n),
              onTap: () => _ac(const SubscriptionScreen()),
            ),
            const Divider(height: 1, indent: RythoSpace.lg),
            SettingsRow(
              icon: Icons.info_outline_rounded,
              title: l10n.about,
              onTap: () => _ac(const AboutScreen()),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: GoldButton(
            text: l10n.signOut,
            // KT4: satır içi çıkış signOutEverywhere'i atlıyordu — cihaz
            // devralma sorusu bayrağı sıfırlanmıyor, aynı süreçte yeniden
            // giren kullanıcı soru yerine doğrudan 409 duvarı görüyordu.
            onPressed: signOutEverywhere,
          ),
        ),
        // "Gönderilerin" bölümü kaldırıldı: kullanıcı üretimi serbest metin
        // v1 kapsamı dışında. Yerine Faz 5'te arkadaş katmanı (seri, hazır
        // tepkiler, günlük ikili dinamik) gelecek.
        const SizedBox(height: 24),
      ]),
    );
  }

  void _ac(Widget sayfa) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => sayfa));

  /// Grup başlığı (R3-5): plakaların üstünde küçük mono etiket.
  Widget _grupBaslik(String metin) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 2),
        child: Text(metin.toUpperCase(),
            style: RythoText.mono(10.5, color: RythoColors.parchmentDim)),
      );

  Future<void> _fotoDegistir() async {
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    try {
      final ok = await changeAvatar(context);
      if (ok && mounted) {
        mesajci.showSnackBar(
            SnackBar(content: Text(l10n.avatarUpdated)));
      }
    } catch (_) {
      // Yükleme/ağ hatası: sessiz kalmak "bastım, olmadı" bırakır.
      if (mounted) {
        mesajci.showSnackBar(
            SnackBar(content: Text(l10n.avatarChangeFailed)));
      }
    }
  }

  /// Satır değeri: "Rytho+ · 320 🪙" / "Ücretsiz · 12 🪙".
  ///
  /// İki sağlayıcı da hata durumunda sessiz varsayılana düşer
  /// (SubscriptionStatus.none / WalletStatus.none) — satır hiçbir zaman
  /// patlamaz, en kötü "Ücretsiz · 0 🪙" görünür.
  String _abonelikOzeti(WidgetRef ref, AppLocalizations l10n) {
    final abonelik =
        ref.watch(subscriptionProvider).value ?? SubscriptionStatus.none;
    final cuzdan = ref.watch(walletProvider).value ?? WalletStatus.none;
    final plan = abonelik.active ? 'Rytho+' : l10n.subPlanFree;
    // Okunamadıysa sayı yerine "—" (WalletStatus.bilinmiyor).
    final bakiye = cuzdan.bilinmiyor ? '—' : '${cuzdan.total}';
    return '$plan · $bakiye 🪙';
  }
}

// `_row` ve `_FaceConsentRow` KALDIRILDI (Tasarım A4). Etiket-değer
// satırı `LabelValueRow`'a, rıza satırı da gizlilik alt sayfasına
// taşındı (bkz. profile_sections.dart).

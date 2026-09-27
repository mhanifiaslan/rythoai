/// Profilin alt sayfaları: gizlilik, dil ve sesler, hakkında, bildirimler.
///
/// ## Neden ayrıldılar
///
/// Profil ~1400 px'di: yedi kart ve satır içine serpiştirilmiş **on dört**
/// kontrol tek kaydırma sütununda duruyordu. Kullanıcının tarifi:
///
/// > "Profil sayfası yine aşağı doğru uzayan bir liste gibi, aynı kategoriler
/// > bir başlıkta toplanılarak tıklanınca alt seçenekler çıkabilir."
///
/// Gruplama zaten vardı ama **tek seviyeliydi**: her grup açıktı, hepsi aynı
/// anda görünüyordu. Gruplamanın işe yaraması için kapanabilmesi gerekiyor.
///
/// Profil artık altı satır; her satır kendi sayfasını açıyor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai_consent.dart' show aiOnayProvider, aiOnayiIste;
import '../../core/api.dart' show apiProvider, friendlyError;
import '../../core/friends.dart' show setContactMatch, setStreakVisible;
import '../../core/locale.dart';
import '../../core/providers.dart';
import '../../core/sound.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../face/face_consent.dart';
import 'legal_page.dart';
import 'notification_settings.dart';

/// Alt sayfaların ortak iskeleti.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CosmicScaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(
              top: RythoSpace.sm, bottom: RythoSpace.xxl),
          children: children,
        ),
      ),
    );
  }
}

/// Bildirimler — var olan panel kendi sayfasında.
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: AppLocalizations.of(context).notifications,
      children: const [NotificationSettings()],
    );
  }
}

/// Gizlilik — arkadaşlara ne göründüğü ve biyometrik rıza.
///
/// Tüm görünürlük ayarları varsayılan olarak **kapalıdır** ve yalnızca
/// buradan açılır.
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).value ?? {};

    return SettingsPage(
      title: l10n.privacy,
      children: [
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
          child: Column(children: [
            SettingsRow(
              icon: Icons.local_fire_department_outlined,
              title: l10n.streakVisibleSetting,
              subtitle: l10n.streakVisibleSettingBody,
              trailing: Switch(
                value: profile['streakVisible'] == true,
                activeThumbColor: RythoColors.magenta,
                activeTrackColor: RythoColors.violet.withValues(alpha: 0.5),
                onChanged: (v) => setStreakVisible(v),
              ),
            ),
            const Divider(height: 1, indent: RythoSpace.lg),
            // Rehber eşleşmesi (Revize R3) — varsayılan KAPALI.
            // Numaralar cihazda hash'lenir; karşılıklılık sunucuda aranır.
            SettingsRow(
              icon: Icons.contacts_outlined,
              title: l10n.contactMatchSetting,
              subtitle: l10n.contactMatchSettingBody,
              trailing: Switch(
                value: profile['contactMatch'] == true,
                activeThumbColor: RythoColors.magenta,
                activeTrackColor: RythoColors.violet.withValues(alpha: 0.5),
                onChanged: (v) => setContactMatch(v),
              ),
            ),
            const Divider(height: 1, indent: RythoSpace.lg),
            // Biyometrik rıza. Verildiği kadar kolay geri alınabilmeli
            // (GDPR Md.7/3) — bu yüzden diğer gizlilik ayarlarıyla aynı
            // yerde ve aynı biçimde duruyor, ayrı bir menüye gömülü değil.
            const FaceConsentRow(),
            const Divider(height: 1, indent: RythoSpace.lg),
            // U06: AI aktarım onayı. Apple 5.1.2(i) ve GDPR Md.7(3): verildiği
            // kadar kolay geri alınabilmeli — yüz rızasıyla aynı yerde.
            const AiConsentRow(),
          ]),
        ),
      ],
    );
  }
}

/// Dil ve sesler.
///
/// Dil seçimi arayüz metinlerini **ve** backend'in ürettiği yorumların
/// dilini birlikte belirler (`Accept-Language` ile taşınır).
class AppearanceSettingsScreen extends ConsumerStatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  ConsumerState<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState
    extends ConsumerState<AppearanceSettingsScreen> {
  bool _sesler = true;

  @override
  void initState() {
    super.initState();
    SoundFx.loadEnabled().then((v) {
      if (mounted) setState(() => _sesler = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SettingsPage(
      title: l10n.languageAndSounds,
      children: [
        SectionHeader(l10n.language),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
          child: Column(children: [
            for (final secim in <(String, Locale?)>[
              (l10n.languageSystem, null),
              (l10n.languageTurkish, const Locale('tr')),
              (l10n.languageEnglish, const Locale('en')),
            ])
              Builder(builder: (_) {
                final secili = ref.watch(localeProvider)?.languageCode ==
                    secim.$2?.languageCode;
                return SettingsRow(
                  title: secim.$1,
                  onTap: () => ref.read(localeProvider.notifier).set(secim.$2),
                  trailing: Icon(
                    secili
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: secili
                        ? RythoColors.magenta
                        : RythoColors.parchmentDim,
                  ),
                );
              }),
          ]),
        ),
        SectionHeader(l10n.sounds),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
          child: SettingsRow(
            icon: Icons.music_note_outlined,
            title: l10n.sounds,
            trailing: Switch(
              value: _sesler,
              activeThumbColor: RythoColors.magenta,
              activeTrackColor: RythoColors.violet.withValues(alpha: 0.5),
              onChanged: (v) {
                setState(() => _sesler = v);
                SoundFx.setEnabled(v);
                if (v) SoundFx.like();
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Hakkında — künye, efemeris atfı ve hukuki metinler.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dil = Localizations.localeOf(context).languageCode;

    return SettingsPage(
      title: l10n.about,
      children: [
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.aboutBody, style: RythoType.bodyDim),
              const SizedBox(height: RythoSpace.md),
              Text(l10n.ephemerisCredit, style: RythoType.dataSmall),
            ],
          ),
        ),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
          child: Column(children: [
            SettingsRow(
              title: l10n.privacyPolicy,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LegalPage(
                    title: l10n.privacyPolicy,
                    sections: privacyPolicySections(dil)),
              )),
            ),
            const Divider(height: 1, indent: RythoSpace.lg),
            SettingsRow(
              title: l10n.termsOfUse,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LegalPage(
                    title: l10n.termsOfUse, sections: termsOfUseSections(dil)),
              )),
            ),
          ]),
        ),
      ],
    );
  }
}

/// Biyometrik rıza satırı.
///
/// Açma yönü **kapalı**: rıza ancak metnini gösteren ekrandan alınır. Geri
/// alma buradan yapılabilir ve tek dokunuşluk mesafededir.
class FaceConsentRow extends ConsumerWidget {
  const FaceConsentRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final riza = ref.watch(faceConsentProvider);
    final verildi = riza.value?.granted ?? false;

    return SettingsRow(
      icon: Icons.face_retouching_natural_outlined,
      title: l10n.faceConsentSetting,
      subtitle:
          verildi ? l10n.faceConsentSettingOn : l10n.faceConsentSettingOff,
      trailing: Switch(
        value: verildi,
        activeThumbColor: RythoColors.magenta,
        activeTrackColor: RythoColors.violet.withValues(alpha: 0.5),
        onChanged: !verildi
            ? null
            : (_) async {
                final onay = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(l10n.faceConsentWithdrawTitle),
                    content: Text(l10n.faceConsentWithdrawBody),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(l10n.cancel)),
                      TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(l10n.faceConsentWithdrawConfirm)),
                    ],
                  ),
                );
                if (onay != true || !context.mounted) return;
                try {
                  final silinen =
                      await withdrawFaceConsent(ref.read(apiProvider));
                  ref.invalidate(faceConsentProvider);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(l10n.faceConsentWithdrawn(silinen))));
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e, l10n))));
                }
              },
      ),
    );
  }
}

/// AI aktarım onayı satırı (U06).
///
/// Yüz rızası satırından farkı: AÇMA yönü de burada çalışır — ama doğrudan
/// değil, onay sayfası üzerinden. Anahtar sayfayı açar; onay ancak
/// sağlayıcıyı ve gönderilen veriyi sayan metin görüldükten sonra verilir.
/// Kapatma onay diyaloğuyla, tek dokunuş mesafesinde.
class AiConsentRow extends ConsumerWidget {
  const AiConsentRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final durum = ref.watch(aiOnayProvider);
    final verildi = durum.value ?? false;

    return SettingsRow(
      icon: Icons.auto_awesome_outlined,
      title: l10n.aiConsentSetting,
      subtitle: verildi ? l10n.aiConsentSettingOn : l10n.aiConsentSettingOff,
      trailing: Switch(
        value: verildi,
        activeThumbColor: RythoColors.magenta,
        activeTrackColor: RythoColors.violet.withValues(alpha: 0.5),
        // Durum okunurken anahtar kilitli: yükleniyorken "kapalı" görünüp
        // dokunulunca onaylı kullanıcıya sayfayı yeniden açmasın.
        onChanged: durum.isLoading
            ? null
            : (acilsin) async {
                if (acilsin) {
                  await aiOnayiIste(context, ref);
                  return;
                }
                final onay = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(l10n.aiConsentWithdrawTitle),
                    content: Text(l10n.aiConsentWithdrawBody),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(l10n.cancel)),
                      TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(l10n.aiConsentWithdrawConfirm)),
                    ],
                  ),
                );
                if (onay != true || !context.mounted) return;
                try {
                  await ref.read(aiOnayProvider.notifier).geriAl();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.aiConsentWithdrawn)));
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e, l10n))));
                }
              },
      ),
    );
  }
}

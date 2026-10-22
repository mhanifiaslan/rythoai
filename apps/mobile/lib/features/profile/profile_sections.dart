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
import '../../widgets/onay.dart' show onayla;
import '../face/face_consent.dart';
import 'blocked_users_screen.dart' show EngellenenlerEkrani;
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

/// Gizlilik — arkadaşlara ne göründüğü, biyometrik rıza, engellenenler.
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
                onChanged: (v) => setContactMatch(v),
              ),
            ),
            const Divider(height: 1, indent: RythoSpace.lg),
            // Biyometrik rıza. Verildiği kadar kolay geri alınabilmeli
            // (GDPR Md.7/3) — bu yüzden diğer gizlilik ayarlarıyla aynı
            // yerde ve aynı biçimde duruyor, ayrı bir menüye gömülü değil.
            //
            // Yapay zeka (Google Gemini) onayının anahtarı burada YOK (sahip
            // kararı 2026-10-22): onay kurulumun ilk adımında ayrı, zorunlu
            // bir kutuyla bir kez alınır ve hiçbir özellik ona kapılı
            // değil — "kapalı" konumdaki bir anahtar gönderimi durdurmaz,
            // yani ekranda yalan söylerdi. Geri alma yolu hesabı silmek
            // (gizlilik metni bunu söyler).
            const FaceConsentRow(),
          ]),
        ),
        // U17: engellenenler ve engeli kaldırma. Anahtar değil, alt sayfa —
        // yukarıdaki üç anahtarın sayısını sabitleyen bekçi
        // (profile_sections_test) bu yüzden etkilenmez.
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
          child: SettingsRow(
            icon: Icons.block_rounded,
            title: l10n.blockedUsersTitle,
            subtitle: l10n.blockedUsersRowSubtitle,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const EngellenenlerEkrani())),
          ),
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
        onChanged: !verildi
            ? null
            : (_) async {
                // Onay sorusu TEK kalıp (`onayla`): bu satır eskiden kendi
                // `AlertDialog`ını kuruyordu — üç kopya üç düğme diline
                // gidiyordu. Yıkıcı DEĞİL: geri alma GDPR Md.7/3 gereği
                // vermek kadar kolay olmalı; kırmızı düğme hakkı kullanmayı
                // tehlikeli gösterirdi.
                final onay = await onayla(
                  context,
                  title: l10n.faceConsentWithdrawTitle,
                  body: l10n.faceConsentWithdrawBody,
                  confirmLabel: l10n.faceConsentWithdrawConfirm,
                );
                if (!onay || !context.mounted) return;
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

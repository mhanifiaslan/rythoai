import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import 'legal_texts.dart';

export 'legal_texts.dart'
    show LegalSections, privacyPolicySections, termsOfUseSections;

/// Hangi hukuk metni.
enum LegalDoc { terms, privacy }

/// Hukuk metnini açar — ÜÇ çağıranın tek kapısı.
///
/// NEDEN: giriş ekranı, sihirbazın karşılama adımı ve profil üç ayrı yoldan
/// `LegalPage` kuruyordu; sihirbaz dili `ingilizce ? en : tr` sabitleriyle
/// seçiyor, ötekiler `*Sections(dil)` sarmalını çağırıyordu. Dil seçimi
/// zaten `legal_texts.dart`'ta tek yerde; başlık + bölüm eşlemesi de tek
/// yerde dursun ki yarın bir dil daha eklenince üç çağıran değil bir
/// fonksiyon değişsin.
void openLegal(BuildContext context, LegalDoc doc) {
  final l10n = AppLocalizations.of(context);
  final dil = Localizations.localeOf(context).languageCode;
  final (baslik, bolumler) = switch (doc) {
    LegalDoc.terms => (l10n.termsOfUse, termsOfUseSections(dil)),
    LegalDoc.privacy => (l10n.privacyPolicy, privacyPolicySections(dil)),
  };
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => LegalPage(title: baslik, sections: bolumler),
  ));
}

/// Sade cam panelli hukuki metin görüntüleyici.
/// Metinler dile göre `legal_texts.dart` içinden gelir.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.title, required this.sections});

  final String title;

  /// (başlık | null, gövde) çiftleri — başlıksız girdiler düz paragraftır.
  final List<(String?, String)> sections;

  @override
  Widget build(BuildContext context) {
    return CosmicScaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (heading, body) in sections) ...[
                  if (heading != null) ...[
                    const SizedBox(height: 14),
                    Text(heading.toUpperCase(),
                        style: RythoText.mono(11,
                            color: RythoColors.goldBright)),
                    const SizedBox(height: 6),
                  ],
                  Text(body,
                      style: RythoText.body(13.5,
                          height: 1.6, color: RythoColors.parchmentDim)),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

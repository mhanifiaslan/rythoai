/// Uygulama içi geri bildirim (GB-turu).
///
/// Kullanıcının bize ulaşabildiği tek yer mağaza yorumuydu; oradan ne
/// cihaz ne sürüm ne de hangi ekranda olduğu öğreniliyordu, yanıt da
/// verilemiyordu. Bu ekran üç şeyi sabitler:
///
/// 1. Gövde küçük ve kapalı kümeli: `type` (bug/suggestion/other), `text`
///    (10..2000) ve isteğe bağlı `screen` (sabit ekran kodu). Sürüm, cihaz
///    ve dil zaten her istekte başlıkla gider (`X-App-Build`, `X-Device-*`,
///    `Accept-Language`) — burada tekrar yazılmaz, kullanıcıya söylenir.
/// 2. Yanıt bildirimle döner (`type=feedback`); dokunuş yalnız uygulamayı
///    açar (bkz. core/notifications.dart).
/// 3. Hata metni sunucunun `detail`'idir (429 günlük tavan dahil) —
///    `friendlyError` ile; ham DioException hiç ekrana çıkmaz.
///
/// Giriş animasyonu YOK (D5): bu bir ayar sayfası, sahne değil — kademeli
/// belirme burada kullanıcıyı formun gelmesini bekletiyordu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/api.dart' show apiProvider, friendlyError;
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/nebula_widgets.dart' show SuggestionChip;
import '../../widgets/onay.dart' show onayla;

/// Sunucu sözleşmesindeki tür kodları — segment sırasıyla aynı.
const List<String> kFeedbackTypes = ['bug', 'suggestion', 'other'];

/// Ekran kodları (sözleşme: `screen` ≤ 60 karakter, serbest). Kapalı küme
/// bilinçli: sunucu tarafında sayılabilsin, kullanıcı yazmak zorunda
/// kalmasın.
const List<String> kFeedbackScreens = [
  'sky',
  'atlas',
  'chat',
  'circle',
  'oracle',
  'profile',
  'other',
];

/// Gönder düğmesinin açıldığı en kısa metin.
const int kFeedbackMinChars = 10;

/// Sunucunun kabul ettiği en uzun metin.
const int kFeedbackMaxChars = 2000;

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key, this.screen});

  /// Hangi ekrandan açıldığı ([kFeedbackScreens] kodu); listede yoksa
  /// seçim boş kalır ve kullanıcı kendisi seçer.
  final String? screen;

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _metin = TextEditingController();
  int _tur = 0;
  String? _ekran;
  bool _mesgul = false;
  bool _gonderildi = false;

  @override
  void initState() {
    super.initState();
    final s = widget.screen;
    if (s != null && kFeedbackScreens.contains(s)) _ekran = s;
    _metin.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _metin.dispose();
    super.dispose();
  }

  String get _temiz => _metin.text.trim();

  bool get _gonderilebilir =>
      _temiz.length >= kFeedbackMinChars && _temiz.length <= kFeedbackMaxChars;

  /// Yazılmış ama gönderilmemiş metin var mı. Geri tuşu bunu sormadan
  /// atmaz: uzun bir hata tarifi yazan kullanıcı yanlışlıkla geri basınca
  /// hepsini kaybediyordu (plan §6). Gönderildiyse form zaten yok.
  bool get _kirli => !_gonderildi && _temiz.isNotEmpty;

  Future<void> _gonder() async {
    if (!_gonderilebilir || _mesgul) return;
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    setState(() => _mesgul = true);
    final tur = kFeedbackTypes[_tur];
    try {
      await ref.read(apiProvider).post(
        '/api/v1/account/feedback',
        data: {
          'type': tur,
          'text': _temiz,
          // Anahtar HİÇ gitmesin: sunucu `screen: null`u boş dize sanmasın.
          if (_ekran != null) 'screen': _ekran,
        },
      );
      Analytics.feedbackSent(tur);
      if (!mounted) return;
      setState(() => _gonderildi = true);
    } catch (e) {
      // 429 (günlük tavan) dahil: `detail` kullanıcının dilinde geliyor.
      if (!mounted) return;
      mesajci.showSnackBar(SnackBar(content: Text(friendlyError(e, l10n))));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  /// Geri tuşu kirli formda önce sorar; onaylanırsa çıkar.
  ///
  /// Soru metni `feedbackClose` ("Kapat"): bu durum için ayrı bir ARB
  /// anahtarı yok (ARB bu dalgada kilitli); "Kapat?" + Vazgeç/Kapat yine
  /// de metni sormadan atmaz.
  Future<void> _geriSoruldu(bool didPop, Object? _) async {
    if (didPop) return;
    final gezgin = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    // Ödünç "Kapat" etiketi gitti (D5 dikişi): vazgeçmek yazılanı
    // kaybeder, o yüzden yıkıcı düğme ve ne kaybedileceğini söyleyen gövde.
    final tamam = await onayla(
      context,
      title: l10n.feedbackDiscardTitle,
      body: l10n.feedbackDiscardBody,
      confirmLabel: l10n.discard,
      destructive: true,
    );
    if (tamam) gezgin.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: !_kirli,
      onPopInvokedWithResult: _geriSoruldu,
      child: CosmicScaffold(
        appBar: AppBar(title: Text(l10n.feedbackTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(
                top: RythoSpace.md, bottom: RythoSpace.xxl),
            children: _gonderildi ? _tesekkur(l10n) : _form(l10n),
          ),
        ),
      ),
    );
  }

  List<Widget> _form(AppLocalizations l10n) {
    final uzunluk = _temiz.length;
    final kisa = uzunluk > 0 && uzunluk < kFeedbackMinChars;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.xl, 0, RythoSpace.xl, RythoSpace.lg),
        child: Text(l10n.feedbackLead, style: RythoType.bodyDim),
      ),
      GlassSegments(
        labels: [
          l10n.feedbackTypeBug,
          l10n.feedbackTypeSuggestion,
          l10n.feedbackTypeOther,
        ],
        index: _tur,
        onChanged: (i) => setState(() => _tur = i),
      ),
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.feedbackScreenLabel, style: RythoType.label),
            const SizedBox(height: RythoSpace.sm),
            Wrap(
              spacing: RythoSpace.sm,
              runSpacing: RythoSpace.sm,
              children: [
                // Seçilebilir çip TEK bileşen (`SuggestionChip.selected`):
                // buradaki `_EkranCipi` kopyası ve günlüğün çipleri aynı
                // görünümü ayrı ayrı elle yazıyordu.
                for (final kod in kFeedbackScreens)
                  SuggestionChip(
                    text: _ekranAdi(l10n, kod),
                    selected: _ekran == kod,
                    // Aynı çipe ikinci dokunuş seçimi kaldırır: alan
                    // isteğe bağlı, "hiçbiri" de geçerli bir cevap.
                    onTap: () => setState(
                        () => _ekran = _ekran == kod ? null : kod),
                  ),
              ],
            ),
            const SizedBox(height: RythoSpace.lg),
            TextField(
              controller: _metin,
              minLines: 4,
              maxLines: 8,
              maxLength: kFeedbackMaxChars,
              textCapitalization: TextCapitalization.sentences,
              style: RythoText.body(15),
              decoration: InputDecoration(
                hintText: l10n.feedbackHint,
                hintStyle:
                    RythoText.body(15, color: RythoColors.parchmentDim),
                helperText: kisa ? l10n.feedbackTooShort : null,
                helperStyle: RythoText.body(12, color: RythoColors.madder),
                counterStyle:
                    RythoText.mono(10.5, color: RythoColors.parchmentDim),
              ),
            ),
            const SizedBox(height: RythoSpace.sm),
            Text(l10n.feedbackPrivacy, style: RythoType.caption),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.lg, RythoSpace.md, RythoSpace.lg, 0),
        child: GoldButton(
          text: l10n.feedbackSend,
          busy: _mesgul,
          onPressed: _gonderilebilir ? _gonder : null,
        ),
      ),
    ];
  }

  List<Widget> _tesekkur(AppLocalizations l10n) {
    return [
      GlassPanel(
        glow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('✦',
                  style:
                      RythoText.display(22, color: RythoColors.goldBright)),
              const SizedBox(width: RythoSpace.sm),
              Expanded(
                child: Text(l10n.feedbackThanksTitle,
                    style: RythoText.display(17)),
              ),
            ]),
            const SizedBox(height: RythoSpace.md),
            Text(l10n.feedbackThanksBody, style: RythoType.bodyDim),
            const SizedBox(height: RythoSpace.xl),
            GoldButton(
              text: l10n.feedbackClose,
              filled: false,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    ];
  }

  /// Ekran kodu → sekmenin kendi adı. `circle` için `tabFriends`: çip
  /// "Çevrem" derken dock sekmesi "Arkadaşlar" yazıyordu ve kullanıcı
  /// hangi ekranı seçtiğini sekmeden doğrulayamıyordu (ölçüldü).
  String _ekranAdi(AppLocalizations l10n, String kod) => switch (kod) {
        'sky' => l10n.tabSky,
        'atlas' => l10n.tabAtlas,
        'chat' => l10n.feedbackScreenChat,
        'circle' => l10n.tabFriends,
        'oracle' => l10n.feedbackScreenOracle,
        'profile' => l10n.tabProfile,
        _ => l10n.feedbackScreenOther,
      };
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/basis_sheet.dart' show kThemeIcons, kThemeLabel;
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/nebula_widgets.dart';
import '../../widgets/onay.dart' show onayla;

/// GÜNLÜĞÜM (R2-G1): tek satırlık, tarih damgalı kayıtlar.
///
/// "Astrolojik günlük" fikri (analiz maddeleri 13-14): kullanıcı yaşadığını
/// tek cümleyle bırakır; kayıtlar sohbetin hafıza fısıltısına girer ve
/// "son ayda ne oldu?" sorusu bu kayıtlar + o günlerin gökyüzüyle
/// cevaplanır. Ham sohbet metni saklanmaz; buradaki her satır kullanıcının
/// KENDİ yazdığı cümledir ve tek tek silinebilir.
class DiaryScreen extends ConsumerStatefulWidget {
  const DiaryScreen({super.key});

  @override
  ConsumerState<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends ConsumerState<DiaryScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _entries = const [];
  String? _theme;
  String? _error;
  bool _busy = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Kaydet düğmesi metne göre açılıp kapanır; dinleyici olmadan boş
    // metinde "açık ama basınca hiçbir şey olmayan" bir düğme kalıyordu.
    _controller.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiProvider);
      final response = await dio.get('/api/v1/account/diary');
      final data = Map<String, dynamic>.from(response.data['data']);
      if (!mounted) return;
      setState(() => _entries = [
            for (final e in (data['entries'] as List? ?? const []))
              Map<String, dynamic>.from(e as Map),
          ]);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = friendlyError(e, AppLocalizations.of(context)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final metin = _controller.text.trim();
    if (metin.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final dio = ref.read(apiProvider);
      final response = await dio.post('/api/v1/account/diary',
          data: {'text': metin, if (_theme != null) 'theme': _theme});
      final giris =
          Map<String, dynamic>.from(response.data['data'] as Map);
      if (!mounted) return;
      setState(() {
        _entries = [giris, ..._entries];
        _controller.clear();
        _theme = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e, AppLocalizations.of(context)))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> giris) async {
    final l10n = AppLocalizations.of(context);
    // Onay sorusu TEK kalıp (`onayla`): buradaki elle kurulmuş `AlertDialog`
    // kopyası kalktı. Onay etiketi Material'ın "Tamam"ı: silmeye özel bir
    // ARB anahtarı yok (ARB bu dalgada kilitli), eski hâl de onu kullanıyordu.
    final onay = await onayla(
      context,
      title: l10n.diaryDeleteTitle,
      confirmLabel: MaterialLocalizations.of(context).okButtonLabel,
    );
    if (!onay || !mounted) return;
    try {
      final dio = ref.read(apiProvider);
      await dio.delete('/api/v1/account/diary/${giris['id']}');
      if (!mounted) return;
      setState(() =>
          _entries = _entries.where((e) => e['id'] != giris['id']).toList());
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.diaryDeleted)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e, l10n))));
      }
    }
  }

  String _tarih(BuildContext context, String? iso) {
    if (iso == null || iso.length < 10) return iso ?? '';
    final t = DateTime.tryParse(iso);
    if (t == null) return iso;
    return DateFormat(
            'd MMMM', Localizations.localeOf(context).toLanguageTag())
        .format(t);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final yazilabilir = _controller.text.trim().isNotEmpty && !_saving;

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.diaryTitle)),
      body: Column(children: [
        // Giriş alanı: tek satır + isteğe bağlı tema çipi + kaydet.
        GlassPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            TextField(
              controller: _controller,
              maxLength: 200,
              maxLines: 2,
              minLines: 1,
              style: RythoText.body(14),
              decoration: InputDecoration(
                hintText: l10n.diaryHint,
                hintStyle:
                    RythoText.body(13, color: RythoColors.parchmentDim),
                counterText: '',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: RythoSpace.sm),
            // Tema çipleri `Wrap` içinde: sayıları artınca ya da büyük yazı
            // ölçeğinde alt satıra inerler. Çip TEK bileşen
            // (`SuggestionChip.selected`) ve ETİKETLİ: yalnız emoji taşıyan
            // eski çipte 🪙 üç anlama geliyordu (kredi / İ Ching / finans).
            Wrap(spacing: RythoSpace.sm, runSpacing: RythoSpace.sm, children: [
              for (final tema in kThemeIcons.keys)
                SuggestionChip(
                  text: '${kThemeIcons[tema]} ${kThemeLabel(l10n, tema)}',
                  selected: _theme == tema,
                  onTap: () => setState(
                      () => _theme = _theme == tema ? null : tema),
                ),
            ]),
            const SizedBox(height: RythoSpace.md),
            // Kaydet çiplerin ALTINDA, tam genişlik: eski Material
            // `FilledButton` çiplerle aynı satırı paylaşıyor, dar ekranda
            // taşıyor ve uygulamanın tek CTA dilinin (`GoldButton`, K5)
            // dışındaydı.
            GoldButton(
              text: l10n.diarySave,
              busy: _saving,
              onPressed: yazilabilir ? _save : null,
            ),
          ]),
        ),
        Expanded(
          child: _busy
              ? const Center(child: AstrolabeSpinner())
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RythoSpace.lg),
                      child: ErrorCard(message: _error!, onRetry: _load),
                    )
                  : _entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(RythoSpace.xl),
                          child: Text(l10n.diaryEmpty,
                              style: RythoText.body(13,
                                  color: RythoColors.parchmentDim,
                                  height: 1.5)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _entries.length + 1,
                          itemBuilder: (context, i) {
                            if (i == _entries.length) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 8, 20, 8),
                                child: Text(l10n.diaryFootnote,
                                    style: RythoText.body(11,
                                        color: RythoColors.parchmentDim,
                                        height: 1.4)),
                              );
                            }
                            final e = _entries[i];
                            return _GirisSatiri(
                              tarih: _tarih(
                                  context, e['date'] as String?),
                              ikon: kThemeIcons[e['theme']],
                              metin: e['text'] as String? ?? '',
                              onDelete: () => _delete(e),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

class _GirisSatiri extends StatelessWidget {
  const _GirisSatiri({
    required this.tarih,
    required this.metin,
    required this.onDelete,
    this.ikon,
  });

  final String tarih;
  final String metin;
  final String? ikon;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 76,
          child: Text(tarih,
              style:
                  RythoText.mono(10.5, color: RythoColors.parchmentDim)),
        ),
        if (ikon != null) ...[
          Text(ikon!, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
        ],
        Expanded(child: Text(metin, style: RythoText.body(13.5))),
        Pressable(
          onTap: onDelete,
          semanticLabel: MaterialLocalizations.of(context).deleteButtonTooltip,
          child: const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.close,
                size: 14, color: RythoColors.parchmentDim),
          ),
        ),
      ]),
    );
  }
}

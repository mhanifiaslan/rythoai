import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai_consent.dart' show AiOnayKapaliKarti, aiOnayProvider;
import '../../core/api.dart';
import '../../core/discovery.dart';
import '../../core/friends.dart';
import '../../core/people.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/markdown_text.dart';
import '../../widgets/nebula_widgets.dart';
import '../chat/chat_screen.dart';
import '../paywall/plus_locked_card.dart';
import '../people/person_form_screen.dart' show relationLabel;

/// İLİŞKİ — iki haritanın dört eksende nitel okuması (R2-L1).
///
/// Kategori standardı bir uyum PUANIDIR ("82/100"); Rytho onu bilinçli
/// göstermez (bkz. friend_detail_screen: kalıcı skor damgası). Bunun yerine
/// her eksen iki şey söyler: bağ ne kadar belirgin (seviye) ve ne nitelikte
/// (akıcı / karışık / zorlayıcı). Her eksenin altında dayanağı duran gerçek
/// açılar var — "ölçülmeyen söylenmez"in ilişki tarafındaki karşılığı.
///
/// Hesap ücretsizdir (LLM yok); derin yorum arkadaş ekranındaki günlük ikili
/// okumada ve Rytho AI'da kalır.
class RelationshipScreen extends ConsumerStatefulWidget {
  /// Rytho arkadaşıyla ilişki.
  const RelationshipScreen({super.key, required Friend this.friend})
      : person = null;

  /// Kullanıcının kendi eklediği kişiyle ilişki (P-turu).
  ///
  /// Ekran aynı ekran: ölçüm, kartlar ve kilit satırı birebir korunur.
  /// Değişen tek şey karşı tarafın kim olduğu — ve eksen ADLARI, çünkü
  /// onları sunucu ilişki türüne göre yolluyor (çocukla "çekim" yazmaz).
  const RelationshipScreen.forPerson({super.key, required Person this.person})
      : friend = null;

  final Friend? friend;
  final Person? person;

  @override
  ConsumerState<RelationshipScreen> createState() =>
      _RelationshipScreenState();
}

class _RelationshipScreenState extends ConsumerState<RelationshipScreen> {
  List<Map<String, dynamic>> _axes = const [];
  String? _footnote;
  String? _reason;
  String? _error;
  bool _busy = true;

  /// İlişkinin AI okuması (1.6.0). Ölçüm herkese açık; yorum Rytho+.
  String? _reading;
  bool _readingLocked = false;

  /// U06: abone ama AI aktarım onayı yok — eksenler (LLM'siz ölçüm) gelir,
  /// yorum yerine onay kartı. Kilit kartı DEĞİL: abonelik onu açmaz.
  bool _readingAiOff = false;

  /// Bugün aranıza dokunan gökyüzü (GT-turu) — LLM'siz günlük ölçüm;
  /// ücretsiz katmanda da görünür ("hesap bedava, yorum paralı").
  Map<String, dynamic>? _today;

  @override
  void initState() {
    super.initState();
    // OB4: çevreden birine bakmak keşif halkasının üçüncü dilimi.
    ref.read(discoveryProvider.notifier).mark(DiscoveryTask.circle);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiProvider);
      // U06: onay yoksa `ai=0` — sunucu yorumu hiç üretmez (adlar ve
      // eksenler Gemini'ye gitmez), ölçümü yine döndürür.
      final onay = await ref
          .read(aiOnayProvider.future)
          .catchError((Object _) => false);
      final response = await dio.post('/api/v1/reports/relationship',
          queryParameters: onay ? null : const {'ai': '0'},
          data: widget.friend != null
              ? {'friend_uid': widget.friend!.uid}
              : {'person_id': widget.person!.id});
      final data = Map<String, dynamic>.from(response.data['data']);
      if (!mounted) return;
      setState(() {
        _axes = [
          for (final a in (data['axes'] as List? ?? const []))
            Map<String, dynamic>.from(a as Map),
        ];
        _footnote = data['footnote'] as String?;
        _reason = data['reason'] as String?;
        _reading = data['reading'] as String?;
        _readingLocked = data['reading_locked'] == true;
        _readingAiOff = data['reading_ai_off'] == true;
        _today = data['today'] is Map
            ? Map<String, dynamic>.from(data['today'] as Map)
            : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = friendlyError(e, AppLocalizations.of(context)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Karşı tarafın ekranda görünen adı. Eklenen kişide etiket CİHAZDAN
  /// gelir; sunucu o adı bilmiyor ve bilmesi de gerekmiyor.
  String _karsiAd(AppLocalizations l10n) => widget.friend?.name ??
      widget.person!.label ??
      relationLabel(l10n, widget.person!.relation);

  void _ask(String axisLocal) {
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        // R4-2: bağlam sunucuda kurulur — model bu sohbette ölçülen
        // eksenleri görür, genel cevaba düşmez. Kişi yolunda kapı
        // arkadaşlık değil sahipliktir (P-turu).
        friendUid: widget.friend?.uid,
        personId: widget.person?.id,
        initialText: l10n.relationshipAskPrefill(
            _karsiAd(l10n), axisLocal.toLowerCase()),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget govde;
    if (_busy) {
      govde = const Padding(
        padding: EdgeInsets.all(RythoSpace.xl),
        child: Center(child: AstrolabeSpinner()),
      );
    } else if (_error != null) {
      govde = Padding(
        padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
        child: ErrorCard(message: _error!, onRetry: _load),
      );
    } else if (_reason == 'birth_missing' || _axes.isEmpty) {
      // Doğum kaydı eksikse VARSAYILAN veriyle harita kurup "sizin
      // ilişkiniz" demek veri uydurmak olurdu; dürüstçe söylenir.
      govde = Padding(
        padding: const EdgeInsets.all(RythoSpace.lg),
        child: Text(l10n.relationshipBirthMissing,
            style: RythoText.body(13.5, color: RythoColors.parchmentDim)),
      );
    } else {
      var stagger = 0;
      govde = Column(children: [
        // GT4: BUGÜNÜN çifte özgü ölçümü — eksenlerin ÜSTÜNDE, çünkü
        // eksenler zemin, bu şerit gündür. Ücretsiz katman da görür.
        if (_today != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.lg, 0, RythoSpace.lg, RythoSpace.sm),
            child: _TodayPanel(
              today: _today!,
              onAsk: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    friendUid: widget.friend?.uid,
                    personId: widget.person?.id,
                    initialText:
                        l10n.relationshipTodayAskPrefill(_karsiAd(l10n)),
                  ),
                ));
              },
            ),
          )
              .animate(delay: Duration(milliseconds: 70 * stagger++))
              .fadeIn(duration: 360.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
        for (final eksen in _axes)
          _AxisCard(
            eksen: eksen,
            onAsk: () => _ask(eksen['axis_local'] as String? ?? ''),
          )
              .animate(delay: Duration(milliseconds: 70 * stagger++))
              .fadeIn(duration: 360.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
        // İlişkinin ANA TEMASI: kartlar ekseni tek tek açar, bu bölüm
        // hepsini toplar. Model biçimi tutturamadığı ender durumda
        // sunucu tam metni buraya koyar — kart cümlesi uydurulmaz.
        if (_reading != null && _reading!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(RythoSpace.lg,
                RythoSpace.md, RythoSpace.lg, 0),
            child: GlassPanel(
              label: l10n.relationshipReadingTitle,
              child: MarkdownText(_reading!,
                  baseStyle: RythoText.body(13.5, height: 1.55)),
            ),
          ).animate(delay: Duration(milliseconds: 70 * stagger++))
              .fadeIn(duration: 380.ms),
        if (_readingAiOff)
          Padding(
            padding: const EdgeInsets.only(top: RythoSpace.sm),
            child: AiOnayKapaliKarti(onGranted: _load),
          ),
        if (_readingLocked)
          Padding(
            padding: const EdgeInsets.fromLTRB(RythoSpace.lg,
                RythoSpace.md, RythoSpace.lg, 0),
            child: PlusLockedCard(
              emoji: '💞',
              title: l10n.relationshipReadingTitle,
              description: l10n.relationshipReadingLocked,
            ),
          ),
        if (_footnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.lg, RythoSpace.sm, RythoSpace.lg, 0),
            child: Text(_footnote!,
                style: RythoText.body(11.5,
                    color: RythoColors.parchmentDim, height: 1.4)),
          ),
      ]);
    }

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.relationshipTitle(_karsiAd(l10n)))),
      // GT4: günlük şerit geldiğine göre ekran artık "bugüne" bağlı —
      // aşağı çekince tazelenir (sky_screen deseni).
      body: RefreshIndicator(
        color: RythoColors.magenta,
        backgroundColor: RythoColors.inkLight,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 40),
          children: [const SizedBox(height: RythoSpace.sm), govde],
        ),
      ),
    );
  }
}

/// "Bugün aranıza dokunan gökyüzü" şeridi (GT-turu) — friend_detail'deki
/// `_DyadPanel` kabuğunun ölçüm hali. Satırlar SUNUCUDA yerelleştirilmiş
/// gelir (`text`); destekleyici açı lila, zorlayıcı bakır (dayanak satırı
/// idiomu). Boş günde dürüst "sakin gün" satırı — panel gizlenmez, çünkü
/// "ölçüldü ve bugün bir şey yok" da bir bilgidir.
class _TodayPanel extends StatelessWidget {
  const _TodayPanel({required this.today, required this.onAsk});

  final Map<String, dynamic> today;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hits = [
      for (final v in (today['hits'] as List? ?? const []))
        Map<String, dynamic>.from(v as Map),
    ];
    return GlassPanel(
      label: l10n.relationshipTodayLabel,
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hits.isEmpty)
            Text(l10n.relationshipTodayQuiet,
                style: RythoText.body(12.5,
                    color: RythoColors.parchmentDim, height: 1.5))
          else
            for (final v in hits)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• ${v['text'] ?? ''}',
                    style: RythoText.mono(11.5,
                        color: v['supportive'] == true
                            ? RythoColors.lilac
                            : RythoColors.copper)),
              ),
          const SizedBox(height: 6),
          Pressable(
            onTap: onAsk,
            child: Text('✦ ${l10n.signalAsk} →',
                style: RythoText.body(12.5,
                    color: RythoColors.goldBright, w: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Eksen anahtarı -> ikon. Anahtarlar sunucudaki synastry_service.AXES ile
/// aynı.
const _kAxisIcons = {
  'communication': '💬',
  'emotional': '🌊',
  'attraction': '🔥',
  'bond': '🪨',
};

/// Ton -> renk. Zorlayıcı ton KIRMIZI değil bakır: "kötü" demiyoruz,
/// "emek istiyor" diyoruz (metinler de öyle yazılmış).
Color _toneColor(String? tone) => switch (tone) {
      'flowing' => RythoColors.goldBright,
      'mixed' => RythoColors.lilac,
      'challenging' => RythoColors.copper,
      _ => RythoColors.parchmentDim,
    };

class _AxisCard extends StatefulWidget {
  const _AxisCard({required this.eksen, required this.onAsk});

  final Map<String, dynamic> eksen;
  final VoidCallback onAsk;

  @override
  State<_AxisCard> createState() => _AxisCardState();
}

class _AxisCardState extends State<_AxisCard> {
  bool _acik = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final e = widget.eksen;
    final anahtar = e['axis'] as String? ?? '';
    final seviye = e['level'] as String? ?? 'quiet';
    final dayanak = [
      for (final b in (e['basis'] as List? ?? const []))
        Map<String, dynamic>.from(b as Map),
    ];

    return GlassPanel(
      margin: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: 5),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(_kAxisIcons[anahtar] ?? '✦',
              style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(e['axis_local'] as String? ?? '',
                style: RythoText.display(13.5,
                    w: FontWeight.w700, color: RythoColors.lilac)),
          ),
          // Seviye + ton çipi. Sayı YOK — bilinçli.
          // Çip esnemiyordu: sunucudan gelen "seviye · ton" metni uzun
          // olabiliyor ve soldaki `Expanded` sıfıra inse bile satırı
          // taşırıyordu. `Flexible` çipin daralıp metni sarmasına izin verir.
          Flexible(
              child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _toneColor(e['tone'] as String?).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: _toneColor(e['tone'] as String?)
                      .withValues(alpha: 0.34)),
            ),
            child: Text(
              seviye == 'quiet'
                  ? (e['level_local'] as String? ?? '')
                  : '${e['level_local']} · ${e['tone_local']}',
              style: RythoText.label(10.5,
                  color: _toneColor(e['tone'] as String?)),
            ),
          )),
        ]),
        // Kartın ipucu cümlesi. Kaynağı değişti: eskiden eksen × ton ile
        // anahtarlı 16 cümlelik hazır tablodan geliyordu ve iki arkadaş
        // birebir aynı dört cümleyi okuyabiliyordu; artık o çift için
        // MODEL yazıyor (bkz. report_service.relationship_reading).
        //
        // Kartta cümle bulunması şart: bir ara kaldırılmıştı ve geriye
        // dört boş başlık + dört "Rytho'ya sor" kaldı — kullanıcı neyi
        // soracağını bilemedi. İpucu merakı açar, detay soruyla gelir.
        if ((e['line'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(e['line'] as String,
              style: RythoText.body(13.5, height: 1.45)),
        ],
        if (dayanak.isNotEmpty) ...[
          const SizedBox(height: 8),
          Pressable(
            onTap: () => setState(() => _acik = !_acik),
            child: Text(
                '${l10n.relationshipBasisTitle} ${_acik ? '▴' : '▾'}',
                style: RythoText.body(11.5,
                    color: RythoColors.parchmentDim, w: FontWeight.w600)),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _acik
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                for (final b in dayanak)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${b['p1_local']} ${b['aspect_local']} '
                      '${b['p2_local']} · ${b['orb']}°',
                      style: RythoText.mono(11.5,
                          color: (b['supportive'] == true)
                              ? RythoColors.lilac
                              : RythoColors.copper),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (seviye != 'quiet') ...[
          const SizedBox(height: 8),
          Pressable(
            onTap: widget.onAsk,
            child: Text('✦ ${l10n.signalAsk} →',
                style: RythoText.body(11.5,
                    color: RythoColors.lilac, w: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }
}

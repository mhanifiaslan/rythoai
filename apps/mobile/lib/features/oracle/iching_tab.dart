
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dio/dio.dart';

import '../../core/ai_consent.dart' show aiOnayiIste;
import '../../core/analytics.dart';
import '../../core/api.dart';
import '../../core/sound.dart';
import '../../core/subscription.dart' show subscriptionProvider;
import '../../core/wallet.dart';
import '../paywall/plus_locked_card.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/coin_toss.dart';
import '../../widgets/motion.dart';
import '../../widgets/nebula_widgets.dart';

/// Çekim hakkı durumu (İ6): "bugünkü hak 1/1" rozeti — kota yalnız 402'de,
/// yani hak BİTİNCE görünür oluyordu. Salt-okur uç, hak düşmez.
final ichingStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(apiProvider);
  final yanit = await dio.get('/api/v1/reports/iching/status');
  return Map<String, dynamic>.from(yanit.data['data'] as Map);
});

/// Sunucunun satır değerlerini (ALTTAN ÜSTE 6/7/8/9, `iching_service.py`
/// `line_values`) iniş klibi varyantına çevirir: k = değer − 6 = logo yüzü
/// yukarı para sayısı (logo yüzü = "3"/yazı; 6 = üç ters yüz, 9 = üç logo).
/// Sunucu paraların sırasını değil toplamı döndürür → dört klip yeter, API
/// değişmez (K2). Sıra korunur: i. iniş alttan i. çizgiyi çizer. 6..9 dışı
/// `ArgumentError` — sunucu sözleşmesi bozulmuş demektir.
List<int> landingVariants(List<int> lineValues) => [
      for (final v in lineValues)
        switch (v) {
          6 => 0,
          7 => 1,
          8 => 2,
          9 => 3,
          _ => throw ArgumentError.value(v, 'lineValues', '6..9 bekleniyordu'),
        },
    ];

/// I Ching: soru sor → gerçek olasılık dağılımıyla çekim → heksagram +
/// hareketli çizgiler + Rytho yorumu.
class IChingTab extends ConsumerStatefulWidget {
  const IChingTab({super.key});

  @override
  ConsumerState<IChingTab> createState() => _IChingTabState();
}

class _IChingTabState extends ConsumerState<IChingTab> {
  // Keepalive karışımı KALKTI (R10): ekran artık TabBarView içinde değil,
  // kendi sayfasında — sayfa yığındayken state zaten yaşıyor.
  final _controller = TextEditingController();
  String _method = 'coins';
  bool _busy = false;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    // Para dokuları önbelleğe: ilk çekimde disk gecikmesi yok.
    CoinTextures.precache();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _cast() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final question = _controller.text.trim();
    if (question.isEmpty) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.iChingQuestionRequired)));
      return;
    }
    // Soru kapısı (R10→R11): bariz niyetsiz girişler istek atılmadan
    // çevrilir. Esas hüküm sunucuda LLM'de (iching_question_verdict);
    // burası yalnız gereksiz gidiş-dönüşü keser. Sunucunun 422 mesajı
    // (geçersiz metin / Sohbet'e yönlendirme) friendlyError ile aynen
    // gösterilir.
    if (!_meaningfulQuestion(question)) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.iChingQuestionInvalid)));
      return;
    }
    // U06: soru ve hüküm Gemini'de yazılır — onay yoksa çekim YAPILMAZ.
    if (!await aiOnayiIste(context, ref) || !mounted) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    SoundFx.cast();
    // Başarıda _busy BURADA düşmez (PBZ): paralar inerken (~5 s) buton
    // meşgul kalır, çift çekim olmaz; CastScene.onFinished düşürür. Hata
    // yolunda sahne havadan düşer.
    var basarili = false;
    try {
      final dio = ref.read(apiProvider);
      final response = await dio.post('/api/v1/reports/iching',
          data: {'question': question, 'method': _method});
      setState(() => _result = Map<String, dynamic>.from(response.data['data']));
      basarili = true;
      Analytics.ichingCast(_method);
      // Abone çekimi cüzdandan 2 token düşer; sohbetteki bakiye çipi
      // bayat kalmasın (İ0). Kota rozeti de tazelensin (İ6).
      ref.invalidate(walletProvider);
      ref.invalidate(ichingStatusProvider);
    } on DioException catch (e) {
      // 402'de interceptor zaten paywall'ı açıyor; arkasına bir de
      // SnackBar basmak aynı mesajı iki kez göstermekti (İ0).
      if (mounted && e.response?.statusCode != 402) {
        messenger.showSnackBar(
            SnackBar(content: Text(friendlyError(e, l10n))));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(friendlyError(e, l10n))));
      }
    } finally {
      if (mounted && !basarili) setState(() => _busy = false);
    }
  }

  /// Yanıttaki satır değerleri (alttan üste); yanıt yokken null → paralar
  /// havada.
  static List<int>? _lineValues(Map<String, dynamic>? result) {
    if (result == null) return null;
    final cast = result['cast'];
    if (cast is! Map) return const [];
    return List<int>.from(cast['line_values'] as List? ?? const []);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // V2: İ Ching Rytho+ kapısında (BaZi ile aynı desen). Abone değilken
    // ücretli uca istek atılmaz; kilit kartı paywall'a götürür.
    final plus =
        ref.watch(subscriptionProvider).value?.active ?? false;
    if (!plus) {
      return PlusLockedCard(
        emoji: '🪙',
        title: l10n.iChingLockedTitle,
        description: l10n.iChingLockedBody,
        centered: true,
      );
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
      Text(l10n.iChingSubtitle, style: RythoText.display(28)),
      const SizedBox(height: 8),
      Text(
        l10n.iChingIntro,
        style: RythoText.body(13.5, color: RythoColors.parchmentDim),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _controller,
        style: RythoText.body(15),
        // Sunucu şemasıyla hizalı sınır (İ0): soru prompt'a ham giriyor.
        maxLength: 280,
        decoration: InputDecoration(
          hintText: l10n.iChingQuestionHint,
          counterText: '',
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        for (final m in [
          ('coins', l10n.iChingMethodCoins),
          ('yarrow', l10n.iChingMethodYarrow)
        ]) ...[
          Expanded(
            // Pressable (İ6): basılınca ölçeklenir + haptik — çıplak
            // GestureDetector bunların ikisini de vermiyordu. Süreler
            // RythoMotion token'larından.
            child: Pressable(
              onTap: () => setState(() => _method = m.$1),
              child: AnimatedContainer(
                duration: RythoMotion.base,
                curve: Curves.easeOutCubic,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient:
                      _method == m.$1 ? RythoColors.primaryGradient : null,
                  color: _method == m.$1 ? null : RythoColors.inkLight,
                  border: Border.all(
                      color: _method == m.$1
                          ? Colors.white.withValues(alpha: 0.2)
                          : RythoColors.glassStroke),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(m.$2,
                    style: RythoText.label(12,
                        color: _method == m.$1
                            ? Colors.white
                            : RythoColors.parchmentDim)),
              ),
            ),
          ),
          if (m.$1 == 'coins') const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 16),
      GoldButton(text: l10n.iChingCastAction, busy: _busy, onPressed: _cast),
      // Bedel rozeti (İ6→V2): ekran artık yalnız aboneye açık; rozet çekim
      // başına token bedelini ÖNCEDEN gösterir (bedel yalnız 402'de görünür
      // olmasın diye).
      Consumer(builder: (context, ref, _) {
        final durum = ref.watch(ichingStatusProvider).value;
        if (durum == null) return const SizedBox(height: 8);
        final metin =
            l10n.iChingQuotaTokens(durum['token_cost'] as int? ?? 2);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(
            child: Text(metin,
                style:
                    RythoText.mono(10.5, color: RythoColors.parchmentDim)),
          ),
        );
      }),
      // Paralar → çizgiler nedenselliği (R12-C2 → PBZ): eskiden paralar
      // sonuç gelince sönüp heksagramla değişiyordu; hangi paranın nasıl
      // düştüğü hiç görünmüyordu. Şimdi CastScene atışı OYNATIR: yanıt
      // gelince altı iniş sırayla düşer (k = logo yüzü sayısı = değer − 6),
      // her iniş alttan bir çizgiyi çizer; bitince aynı switcher hücresinde
      // sonuç büyüyerek gelir.
      AnimatedSwitcher(
        duration: reduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 400),
        switchInCurve: RythoMotion.enter,
        switchOutCurve: RythoMotion.settle,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(begin: 0.85, end: 1.0).animate(anim),
            child: child,
          ),
        ),
        child: _busy
            ? Padding(
                key: const ValueKey('firlat'),
                padding: const EdgeInsets.only(top: 24),
                child: CastScene(
                  lineValues: _lineValues(_result),
                  onFinished: () {
                    if (mounted) setState(() => _busy = false);
                  },
                ),
              )
            : _result != null
                ? Column(key: const ValueKey('sonuc'), children: [
                    const SectionDivider(),
                    _HexagramView(result: _result!)
                        .animate(delay: 150.ms)
                        .fadeIn(duration: 500.ms)
                        .slideY(begin: 0.04, curve: Curves.easeOutCubic),
                  ])
                : const SizedBox.shrink(key: ValueKey('bos')),
      ),
      const SizedBox(height: 32),
    ]);
  }
}

/// Soru kutusuna niyet yerine yazılan tipik doldurmalar — sunucudaki
/// `_DOLGU_KELIMELER` listesinin aynası (iching_service.py). Karşılaştırma
/// küçük harfle; noktasız-I varyantları iki ayrı girdi olarak duruyor.
const _dolguKelimeler = {
  'merhaba', 'selam', 'selamlar', 'hello', 'hi', 'hey', 'naber',
  'nasılsın', 'nasilsin', 'iyi', 'misin', 'test', 'deneme', 'asdf',
  'qwerty', 'abc', 'ok', 'tamam', 'evet', 'hayır', 'hayir',
};

/// Soru gerçek bir niyet taşıyor mu — dolgu kelimeler ayıklandıktan sonra
/// en az iki kelime kalmalı. Günde tek çekim hakkı selamla harcanmasın.
bool _meaningfulQuestion(String question) {
  final kelimeler = question
      .toLowerCase()
      .replaceAll('̇', '') // İ küçülünce kalan birleşik nokta
      .split(RegExp(r"[^\p{L}\p{N}']+", unicode: true));
  final anlamli =
      kelimeler.where((k) => k.isNotEmpty && !_dolguKelimeler.contains(k));
  return anlamli.length >= 2;
}

enum _CastPhase { airborne, landing, done }

/// Çekim sahnesi durum makinesi (PBZ 1.2 → PZ2):
///
/// | Faz | Sahne | Geçiş |
/// |---|---|---|
/// | airborne | [CoinToss] havada döngü + "paralar havada" | [lineValues] gelince varyantlar hesaplanır, kare bitince iniş başlar |
/// | landing(i) | [CoinToss] `logoUp = k_i`, `toss = i` + sağda canlı glif (6 yuva, `revealed` kadar dolu) + "düşüyor i+1/6" | temas anında [onLand]; `onLanded` → `revealed = i+1` → sonraki |
/// | done | son poz tutulur | i=5 bitince [onFinished] BİR kez |
///
/// - Paralar kodla sürülür (bkz. widgets/coin_toss.dart): iniş o anki açıdan
///   KESİNTİSİZ başlar — eski klip düzenindeki "döngü sınırını bekle" ve
///   2,5 s emniyet zamanlayıcısı yok.
/// - Tepsiye dokunma iniş sırasında `done`'a atlar (ritüel atlanabilir;
///   görünür etiket yok).
/// - reduce-motion: hareket yok; her iniş anında son pozuna geçer → çizgiler
///   anında dolar (giriş animasyonu kurulmaz). Clink yalnız İLK inişte:
///   altı iniş ~6 karede bittiğinden altı clink üst üste binip tek gürültü
///   olurdu. Hareketli sahnede clink her atışın TEMAS anında.
/// - Üst geri çağrılar (`onFinished` / `onLand`) build fazından ÇAĞRILMAZ:
///   yanıt `didChangeDependencies` / `didUpdateWidget` içinde emilir, oradan
///   doğrudan üst `setState` framework assertion'ıdır. O yollardan çıkan
///   geçişler kare bitince (post-frame, mounted korumalı) uygulanır.
///
/// Public: reduce-motion ve iniş sırası testten sürülür
/// (`iching_cast_test.dart`).
class CastScene extends StatefulWidget {
  const CastScene({
    super.key,
    required this.lineValues,
    required this.onFinished,
    this.onLand = SoundFx.coinLand,
  });

  /// Sunucu yanıtı — alttan üste 6/7/8/9; null iken paralar havada.
  final List<int>? lineValues;

  /// Altı iniş bitince (ya da atlanınca) bir kez.
  final VoidCallback onFinished;

  /// Her iniş klibi BAŞINDA (reduce-motion'da yalnız ilkinde) — varsayılan
  /// metalik "clink"; test sayaç verir.
  final Future<void> Function() onLand;

  @override
  State<CastScene> createState() => CastSceneState();
}

/// Public: testler `revealed` / `isLanding` / `isDone` okur.
class CastSceneState extends State<CastScene> {
  _CastPhase _faz = _CastPhase.airborne;
  List<int>? _bekleyen; // iniş varyantları (k); yanıt gelince dolar
  int _inis = 0; // şu anki iniş indeksi (alttan)
  int _acilan = 0; // çizilen çizgi sayısı (alt yuvalardan)
  bool _hazir = false;

  @visibleForTesting
  int get revealed => _acilan;

  @visibleForTesting
  bool get isLanding => _faz == _CastPhase.landing;

  @visibleForTesting
  bool get isDone => _faz == _CastPhase.done;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Yanıt daha monte edilirken elde olabilir; reduceMotion için context
    // gerektiğinden initState yerine burada (bir kez).
    if (_hazir) return;
    _hazir = true;
    final degerler = widget.lineValues;
    if (degerler != null) _emdir(degerler);
  }

  @override
  void didUpdateWidget(CastScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final degerler = widget.lineValues;
    if (degerler != null && _bekleyen == null) _emdir(degerler);
  }

  /// Yanıt geldi: varyantlar hesaplanır, iniş kare bitince başlar.
  ///
  /// `didChangeDependencies` / `didUpdateWidget` içinden — yani build
  /// fazından — çağrılır. Üst widget'a geri çağrı (`onFinished` / `onLand`)
  /// buradan DOĞRUDAN yapılamaz: `_IChingTabState.setState` build sırasında
  /// atada "setState() called during build" assertion'ıyla düşer. Bu yüzden
  /// hemen sonuç veren iki yol (boş varyant → bit; reduce-motion → in) kare
  /// bitince uygulanır; zamanlayıcı zaten sonra çalışır.
  void _emdir(List<int> degerler) {
    List<int> varyantlar;
    try {
      varyantlar = landingVariants(degerler);
    } on ArgumentError catch (e) {
      // Sunucu sözleşmesi bozuk (6..9 dışı): sahne kilitlenmesin, bit.
      debugPrint('CastScene: $e');
      varyantlar = const [];
    }
    _bekleyen = varyantlar;
    if (varyantlar.isEmpty) {
      _kareSonra(_bitir);
      return;
    }
    // Kesintisiz geçiş: sahne o anki açıdan iner, sınır beklenmez.
    _kareSonra(_inisBasla);
  }

  /// Build fazından üst geri çağrıya giden geçişler için: kare bitince,
  /// hâlâ monteyse. Geçişlerin kendi faz korumaları var.
  void _kareSonra(VoidCallback gecis) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) gecis();
    });
  }

  void _inisBasla() {
    if (!mounted || _faz != _CastPhase.airborne) return;
    setState(() {
      _faz = _CastPhase.landing;
      _inis = 0;
    });
    // Statik sahnede foley yalnız burada, BİR kez; hareketli sahnede
    // CoinToss temas anında çalar (build'deki onContact).
    if (reduceMotion(context)) widget.onLand();
  }

  /// İniş bitti: alttan bir çizgi daha, sonra sıradaki iniş.
  void _indi() {
    if (_faz != _CastPhase.landing) return;
    final bekleyen = _bekleyen!;
    final sonraki = _inis + 1;
    if (sonraki >= bekleyen.length) {
      setState(() => _acilan = bekleyen.length);
      _bitir();
      return;
    }
    setState(() {
      _acilan = sonraki;
      _inis = sonraki;
    });
  }

  /// Tepsiye dokunma: kalan inişler atlanır, çizgiler tamamlanır.
  void _atla() {
    if (_faz != _CastPhase.landing) return;
    setState(() => _acilan = _bekleyen?.length ?? 0);
    _bitir();
  }

  void _bitir() {
    if (_faz == _CastPhase.done) return;
    setState(() => _faz = _CastPhase.done);
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final degerler = widget.lineValues ?? const <int>[];
    // Yanıt yokken 6 boş yuva: glif yerini korur, iniş başlayınca dolar.
    final cizgiler = degerler.isEmpty
        ? List<int>.filled(6, 1)
        : [for (final v in degerler) v.isOdd ? 1 : 0];
    final hareketli = [
      for (var i = 0; i < degerler.length; i++)
        if (degerler[i] == 6 || degerler[i] == 9) i + 1,
    ];
    final bekleyen = _bekleyen;
    final inisVar = bekleyen != null && bekleyen.isNotEmpty &&
        _faz != _CastPhase.airborne;
    final azalt = reduceMotion(context);
    // TEK CoinToss örneği: havadan inişe ve atıştan atışa poz sürekliliği
    // korunur; `toss` değişince yeni atış başlar (aynı k art arda gelse de).
    final Widget sahne = CoinToss(
      logoUp: inisVar ? bekleyen[_inis] : null,
      toss: _inis,
      // Foley temas anında (hareketli sahne); statik sahnede _inisBasla.
      onContact: azalt ? null : widget.onLand,
      onLanded: _indi,
    );
    final etiket = _faz == _CastPhase.airborne
        ? l10n.iChingCoinsInAir
        : l10n.iChingCoinsLanding(
            _faz == _CastPhase.done ? _acilan : _inis + 1);

    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Pressable(
            onTap: _faz == _CastPhase.landing ? _atla : null,
            child: SizedBox(height: 72, child: Center(child: sahne)),
          ),
        ),
        const SizedBox(width: 16),
        _HexagramGlyph(
          lines: cizgiler,
          moving: hareketli,
          values: degerler,
          revealedCount: _acilan,
        ),
      ]),
      const SizedBox(height: 12),
      Text(etiket,
          style: RythoText.mono(12, color: RythoColors.parchmentDim)),
    ]);
  }
}

/// Çekim sonucu sahnesi (İ6): BaZi sekmesiyle aynı Plaque dilinde —
/// çift glif, hüküm/imge metinleri, hareketli çizgi pasajları, Liu Yao
/// dökümü ve gün bağlamı. Eski hâli yalnız ad + LLM yorumu gösteriyordu;
/// hüküm ve imge sunucudan geldiği hâlde ekrana hiç çıkmıyordu.
class _HexagramView extends StatelessWidget {
  const _HexagramView({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cast = Map<String, dynamic>.from(result['cast']);
    final primary = Map<String, dynamic>.from(cast['primary']);
    final transformed = cast['transformed'] != null
        ? Map<String, dynamic>.from(cast['transformed'])
        : null;
    final nuclear = cast['nuclear'] != null
        ? Map<String, dynamic>.from(cast['nuclear'])
        : null;
    final liuYao = cast['liu_yao'] != null
        ? Map<String, dynamic>.from(cast['liu_yao'])
        : null;
    final context_ = cast['context'] != null
        ? Map<String, dynamic>.from(cast['context'])
        : null;
    final lines = List<int>.from(cast['lines'] ?? []);
    final values = List<int>.from(cast['line_values'] ?? []);
    final moving = List<int>.from(cast['moving_lines'] ?? []);
    final lineTexts =
        List<String>.from(primary['line_texts'] as List? ?? const []);
    final lower = Map<String, dynamic>.from(primary['lower_trigram'] ?? {});
    final upper = Map<String, dynamic>.from(primary['upper_trigram'] ?? {});

    var sira = 0;
    Duration gecikme() => Duration(milliseconds: 140 * sira++);
    Widget blok(Widget w) => w
        .animate(delay: gecikme())
        .fadeIn(duration: 380.ms)
        .slideY(begin: 0.06, curve: Curves.easeOutCubic);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      blok(Plaque(
        margin: const EdgeInsets.symmetric(vertical: 8),
        label: l10n.iChingHexagramLabel(primary['number']),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Çizgiler çekim sahnesinde (CastScene) iniş iniş çizildi;
            // burada tamamı hazır durur.
            _HexagramGlyph(lines: lines, moving: moving, values: values),
            if (transformed != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 18, color: RythoColors.parchmentDim),
              ),
              _HexagramGlyph(
                  lines: List<int>.from(cast['lines'] ?? [])
                      .asMap()
                      .entries
                      .map((e) =>
                          moving.contains(e.key + 1) ? 1 - e.value : e.value)
                      .toList(),
                  moving: const []),
            ],
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${primary['name_local'] ?? primary['name_tr']}',
                        style: RythoText.display(24)),
                    Text('${primary['name']} ${primary['name_cn']}',
                        style: RythoText.body(12.5,
                            color: RythoColors.parchmentDim)),
                    if (transformed != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.iChingTransformedTo(
                            transformed['name_local'] ??
                                transformed['name_tr'],
                            transformed['number']),
                        style: RythoText.mono(11.5,
                            color: RythoColors.copper),
                      ),
                    ],
                  ]),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
              l10n.iChingTrigramsLabel(
                  '${lower['name'] ?? ''} (${lower['element'] ?? ''})',
                  '${upper['name'] ?? ''} (${upper['element'] ?? ''})'),
              style: RythoText.body(11.5, color: RythoColors.parchmentDim)),
          if (nuclear != null)
            Text(
                l10n.iChingNuclearLabel(
                    nuclear['name_local'] ?? nuclear['name_tr'] ?? '',
                    nuclear['number'] as int),
                style:
                    RythoText.body(11.5, color: RythoColors.parchmentDim)),
          if (moving.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(l10n.iChingLegend,
                style: RythoText.mono(10, color: RythoColors.parchmentDim)),
          ],
        ]),
      )),
      blok(Plaque(
        margin: const EdgeInsets.symmetric(vertical: 8),
        label: l10n.iChingJudgmentTitle,
        child: Text(primary['judgment'] ?? '',
            style: RythoText.body(14, color: RythoColors.parchment)),
      )),
      blok(Plaque(
        margin: const EdgeInsets.symmetric(vertical: 8),
        label: l10n.iChingImageTitle,
        child: Text(primary['image'] ?? '',
            style: RythoText.body(13.5, color: RythoColors.parchmentDim)),
      )),
      // Hareketli çizgi METİNLERİ — okumanın ağırlık merkezi (İ1 verisi).
      if (moving.isNotEmpty && lineTexts.length == 6)
        blok(Plaque(
          label: l10n.iChingMovingTitle,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final n in moving)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:
                                  RythoColors.copper.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(l10n.iChingLineLabel(n),
                                style: RythoText.mono(10,
                                    color: RythoColors.copper)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(lineTexts[n - 1],
                                style: RythoText.body(13,
                                    color: RythoColors.parchment)),
                          ),
                        ]),
                  ),
              ]),
        )),
      if (liuYao != null)
        blok(Plaque(
          label: l10n.iChingLiuYaoTitle,
          child: _LiuYaoTable(l10n: l10n, liuYao: liuYao, moving: moving),
        )),
      if ((context_?['day_pillar']?['label'] as String?)?.isNotEmpty ??
          false)
        blok(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
              l10n.iChingDayLabel(context_!['day_pillar']['label'] as String),
              style: RythoText.mono(10.5, color: RythoColors.parchmentDim)),
        )),
      blok(const SectionDivider()),
      blok(MarginNote(
          title: l10n.iChingOracleNote, text: result['report'] ?? '')),
    ]);
  }
}

/// Liu Yao dökümü: alttan üste 6 satır — dal+gövde, akraba, işaretler.
class _LiuYaoTable extends StatelessWidget {
  const _LiuYaoTable(
      {required this.l10n, required this.liuYao, required this.moving});
  final AppLocalizations l10n;
  final Map<String, dynamic> liuYao;
  final List<int> moving;

  @override
  Widget build(BuildContext context) {
    final satirlar =
        List<Map<String, dynamic>>.from(liuYao['lines'] as List? ?? const []);
    final shi = liuYao['shi'] as int?;
    final ying = liuYao['ying'] as int?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          l10n.iChingPalaceLabel(
              '${liuYao['palace'] ?? ''}', shi ?? 0, ying ?? 0),
          style: RythoText.body(11.5, color: RythoColors.parchmentDim)),
      const SizedBox(height: 8),
      // Alttan üste — glifle aynı yön.
      for (final c in satirlar.reversed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(
              width: 22,
              child: Text('${c['position']}',
                  style: RythoText.mono(10,
                      color: c['position'] == shi
                          ? RythoColors.goldBright
                          : RythoColors.parchmentDim)),
            ),
            SizedBox(
              width: 76,
              child: Text('${c['stem'] ?? ''}${c['branch'] ?? ''}',
                  style: RythoText.mono(11,
                      color: (c['void'] == true)
                          ? RythoColors.parchmentDim
                          : RythoColors.parchment)),
            ),
            Expanded(
              child: Text('${c['relative_name'] ?? c['relative'] ?? ''}',
                  style: RythoText.body(11.5,
                      color: RythoColors.parchmentDim)),
            ),
            // Etiketler (shi/ying/boşluk/çatışma) esnemeyen çiplerdi ve üçü
            // birden çıkabiliyor; soldaki `Expanded` sıfıra inse bile 22+76
            // px sabit sütunlarla birlikte satır taşıyordu. `Flexible` +
            // `Wrap`: dar ekranda etiketler alt satıra iner.
            Flexible(
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                alignment: WrapAlignment.end,
                children: [
                  if (c['position'] == shi)
                    _tag('shi', RythoColors.goldBright)
                  else if (c['position'] == ying)
                    _tag('ying', RythoColors.lilac),
                  if (c['void'] == true)
                    _tag(l10n.iChingVoidTag, RythoColors.parchmentDim),
                  if (c['clash'] == true)
                    _tag(l10n.iChingClashTag, RythoColors.copper),
                ],
              ),
            ),
          ]),
        ),
    ]);
  }

  Widget _tag(String metin, Color renk) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: renk.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(metin, style: RythoText.mono(8.5, color: renk)),
      );
}

/// Heksagram çizimi: 6 çizgi alttan üste; hareketli çizgiler bakır renkte
/// ve ucunda klasik işaret taşır — ○ eski yang (9), × eski yin (6).
///
/// ⚠️ Yön: `lines`/`values` ALTTAN ÜSTE indekslidir, Column ise
/// `for i = 5..0` ile üstten aşağı çizer. [revealedCount] ALT yuvaları
/// doldurur (i < revealedCount görünür) — iniş i alttan i. çizgidir; ters
/// indekslenirse yanlış çizgi animasyon alır.
class _HexagramGlyph extends StatelessWidget {
  const _HexagramGlyph({
    required this.lines,
    required this.moving,
    this.values = const [],
    this.revealedCount,
  });
  final List<int> lines;
  final List<int> moving;

  /// 6/7/8/9 değerleri — işaret seçimi için; boşsa işaret çizilmez.
  final List<int> values;

  /// Alttan kaç çizgi görünür; null → hepsi (`lines.length`). Görünmeyen
  /// çizgi yerini korur (yuva) — glif iniş boyunca zıplamaz. Sabit stagger
  /// KALKTI (PBZ): çizgi, kendi inişi bitince belirir.
  final int? revealedCount;

  @override
  Widget build(BuildContext context) {
    final gorunen = revealedCount ?? lines.length;
    final azalt = reduceMotion(context);
    return Column(
      children: [
        for (var i = lines.length - 1; i >= 0; i--)
          _satir(i, i < gorunen, azalt),
      ],
    );
  }

  Widget _satir(int i, bool gorunur, bool azalt) {
    final cizgi = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 64,
          height: 6,
          child: lines[i] == 1
              ? Container(color: _color(i + 1))
              : Row(children: [
                  Expanded(child: Container(color: _color(i + 1))),
                  const SizedBox(width: 14),
                  Expanded(child: Container(color: _color(i + 1))),
                ]),
        ),
        SizedBox(
          width: 14,
          child: Text(_isaret(i),
              textAlign: TextAlign.center,
              style: RythoText.mono(9, color: RythoColors.copper)),
        ),
      ]),
    );
    // Örtük animasyon: baştan görünür çizgi (sonuç sahnesi) hiç animasyon
    // almaz; iniş sırasında açılan çizgi kısa fade ile gelir, reduce-motion
    // açıkken anında.
    return AnimatedOpacity(
      opacity: gorunur ? 1 : 0,
      duration: azalt ? Duration.zero : RythoMotion.base,
      curve: RythoMotion.enter,
      child: cizgi,
    );
  }

  String _isaret(int i) {
    if (i >= values.length || !moving.contains(i + 1)) return '';
    return values[i] == 9 ? '○' : '×';
  }

  Color _color(int lineNo) =>
      moving.contains(lineNo) ? RythoColors.copper : RythoColors.gold;
}

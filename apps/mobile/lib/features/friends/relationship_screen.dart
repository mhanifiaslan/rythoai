import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai_consent.dart' show AiOnayiGerekli, aiOnayProvider;
import '../../core/api.dart';
import '../../core/discovery.dart';
import '../../core/friends.dart';
import '../../core/okuma_durumu.dart';
import '../../core/people.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';
import '../../widgets/nebula_widgets.dart';
import '../../widgets/okuma_kabi.dart';
import '../chat/chat_screen.dart';
import '../paywall/ozellik_katalogu.dart';
import '../paywall/plus_locked_card.dart';
import '../people/person_form_screen.dart' show relationLabel;

/// Geri bildirim kanalındaki ekran kodu (`FeedbackScreen.screen` kapalı
/// kümesi): ilişki ekranı Çevrem sekmesinin altında yaşar.
const String kIliskiEkranKodu = 'circle';

/// Destekleyici / zorlayıcı satırın öneki — yalnız renk yetmiyordu
/// (renk körlüğünde iki satır aynı okunuyor). ▴/▾ glif fontunda ÖLÇÜLÜ
/// (`assets/fonts/RythoGlyphs.codepoints.txt`: U+25B4, U+25BE); ▲/▼
/// (U+25B2/U+25BC) orada YOK, tofu üretirdi.
String dayanakOneki({required bool destekleyici}) =>
    destekleyici ? '▴' : '▾';

/// Sunucu yanıtından okumanın durumu.
///
/// `reading_locked` ayrı bir bayrak: `okumaDurumuFromYanit`in 1. kuralı
/// (`veri == null → kilitli`) buraya uymuyor, çünkü bu uç ölçümü herkese
/// verip yalnız yorumu kilitliyor — yük hiç null değil. Kilit önce, gerisi
/// tek fonksiyondan (`fallback` bayrağını okuyan TEK nokta). `refunded`
/// bu uçta hep false (jetonsuz uç) → iade cümlesi doğru olarak çıkmaz.
///
/// `reading_ai_off` (U06): abone ama AI aktarım onayı yok; sunucu eksenleri
/// verir, yorumu üretmez. Kilit DEĞİL — abonelik onu açmaz, yalnız onay
/// açar; kilit kartı yanlış çare gösterirdi. İstemci kapısının fırlattığı
/// aynı [AiOnayiGerekli] ile temsil edilir: onay kartını `OkumaKabi` tek
/// yerden çiziyor, ekranın ayrıca bir bayrak taşıması gerekmiyor.
OkumaDurumu iliskiOkumaDurumu(Map<String, dynamic> data) {
  if (data['reading_locked'] == true) return const OkumaKilitli();
  if (data['reading_ai_off'] == true) {
    return const OkumaHata(AiOnayiGerekli());
  }
  return okumaDurumuFromYanit(data, alan: 'reading');
}

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
  /// Kilit/şablon/hazır ayrımı `iliskiOkumaDurumu`nda.
  OkumaDurumu _okuma = const OkumaKilitli();

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
        _okuma = iliskiOkumaDurumu(data);
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
  String _karsiAd(AppLocalizations l10n) => widget.friend?.ad(l10n) ??
      widget.person!.label ??
      relationLabel(l10n, widget.person!.relation);

  void _sohbet(String tohum) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        // R4-2: bağlam sunucuda kurulur — model bu sohbette ölçülen
        // eksenleri görür, genel cevaba düşmez. Kişi yolunda kapı
        // arkadaşlık değil sahipliktir (P-turu).
        friendUid: widget.friend?.uid,
        personId: widget.person?.id,
        initialText: tohum,
      ),
    ));
  }

  /// Eksen adı sunucudan YERELLEŞMİŞ gelir ve tırnak içinde geçer;
  /// dönüşüm yok. Eski `toLowerCase()` "İletişim"i `i̇letişim`e
  /// (i + U+0307) çeviriyordu.
  void _ask(String axisLocal) {
    final l10n = AppLocalizations.of(context);
    _sohbet(l10n.relationshipAskPrefill(_karsiAd(l10n), axisLocal));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget govde;
    if (_busy) {
      govde = const Column(children: [
        SkeletonPanel(height: 120),
        SkeletonPanel(height: 110),
        SkeletonPanel(height: 110),
      ]);
    } else if (_error != null) {
      govde = Padding(
        padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
        child: ErrorCard(
            message: _error!, screen: kIliskiEkranKodu, onRetry: _load),
      );
    } else if (_reason == 'birth_missing' || _axes.isEmpty) {
      // Doğum kaydı eksikse VARSAYILAN veriyle harita kurup "sizin
      // ilişkiniz" demek veri uydurmak olurdu; dürüstçe söylenir.
      govde = Padding(
        padding: const EdgeInsets.all(RythoSpace.lg),
        child: Text(l10n.relationshipBirthMissing, style: RythoType.bodyDim),
      );
    } else {
      var sira = 0;
      govde = Column(children: [
        // GT4: BUGÜNÜN çifte özgü ölçümü — eksenlerin ÜSTÜNDE, çünkü
        // eksenler zemin, bu şerit gündür. Ücretsiz katman da görür.
        if (_today != null)
          RythoReveal(
            index: sira++,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  RythoSpace.lg, 0, RythoSpace.lg, RythoSpace.sm),
              child: _TodayPanel(
                today: _today!,
                onAsk: () => _sohbet(
                    l10n.relationshipTodayAskPrefill(_karsiAd(l10n))),
              ),
            ),
          ),
        for (final eksen in _axes)
          RythoReveal(
            index: sira++,
            child: _AxisCard(
              eksen: eksen,
              onAsk: () => _ask(eksen['axis_local'] as String? ?? ''),
            ),
          ),
        // İlişkinin ANA TEMASI: kartlar ekseni tek tek açar, bu bölüm
        // hepsini toplar. Model biçimi tutturamadığı ender durumda
        // sunucu tam metni buraya koyar — kart cümlesi uydurulmaz.
        // Kap tek (`OkumaKabi`): kilitte katalog kartı, şablonda dürüst
        // cümle + tekrar dene; paylaşım BİLEREK yok (üçüncü kişi hakkında,
        // sahip kararı).
        RythoReveal(
          index: sira++,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.lg, RythoSpace.md, RythoSpace.lg, 0),
            child: OkumaKabi(
              durum: _okuma,
              ekranKodu: kIliskiEkranKodu,
              baslik: l10n.relationshipReadingTitle,
              onTekrarDene: _load,
              onSor: () =>
                  _sohbet(l10n.askAboutFriendPrefill(_karsiAd(l10n))),
              kilit: PlusLockedCard(
                ozellik: PlusOzellik.dyad,
                title: PlusOzellik.dyad.baslik(l10n),
                description: PlusOzellik.dyad.kilitGovdesi(l10n),
              ),
            ),
          ),
        ),
        if (_footnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.lg, RythoSpace.sm, RythoSpace.lg, 0),
            child: Text(_footnote!, style: RythoType.caption),
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
          padding: const EdgeInsets.only(bottom: RythoSpace.xxl),
          children: [const SizedBox(height: RythoSpace.sm), govde],
        ),
      ),
    );
  }
}

/// "Bugün aranıza dokunan gökyüzü" şeridi (GT-turu) — friend_detail'deki
/// `_DyadPanel` kabuğunun ölçüm hali. Satırlar SUNUCUDA yerelleştirilmiş
/// gelir (`text`); destekleyici açı ▴ lila, zorlayıcı ▾ bakır (dayanak
/// satırı idiomu). Boş günde dürüst "sakin gün" satırı — panel gizlenmez,
/// çünkü "ölçüldü ve bugün bir şey yok" da bir bilgidir.
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
            Text(l10n.relationshipTodayQuiet, style: RythoType.caption)
          else
            for (final v in hits)
              Padding(
                padding: const EdgeInsets.only(bottom: RythoSpace.xs),
                child: _DayanakSatiri(
                  metin: v['text'] as String? ?? '',
                  destekleyici: v['supportive'] == true,
                ),
              ),
          const SizedBox(height: RythoSpace.xs),
          RythoyaSor(onTap: onAsk),
        ],
      ),
    );
  }
}

/// Dayanak/bugün satırı: önek (▴ destekleyici / ▾ zorlayıcı) + renk.
/// İki işaret birden: renk tek başına renk körlüğünde ayırt edilmiyordu.
class _DayanakSatiri extends StatelessWidget {
  const _DayanakSatiri({required this.metin, required this.destekleyici});

  final String metin;
  final bool destekleyici;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${dayanakOneki(destekleyici: destekleyici)} $metin',
      style: RythoText.mono(11.5,
          color: destekleyici ? RythoColors.lilac : RythoColors.copper),
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

  /// Açılır bölme: hareket açıkken boy geçişi, azaltılmışken çıplak çocuk.
  Widget _dayanakBolmesi(BuildContext context, Widget cocuk) =>
      reduceMotion(context)
          ? cocuk
          : AnimatedSize(
              alignment: Alignment.topCenter,
              duration: RythoMotion.base,
              curve: RythoMotion.enter,
              child: cocuk,
            );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final e = widget.eksen;
    final anahtar = e['axis'] as String? ?? '';
    final seviye = e['level'] as String? ?? 'quiet';
    final ikon = _kAxisIcons[anahtar];
    final dayanak = [
      for (final b in (e['basis'] as List? ?? const []))
        Map<String, dynamic>.from(b as Map),
    ];

    return GlassPanel(
      margin: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: RythoSpace.xs),
      padding: const EdgeInsets.fromLTRB(
          RythoSpace.md, RythoSpace.md, RythoSpace.md, RythoSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Eksen ikonu renkli emoji (bilinçli); bilinmeyen eksende glif.
          if (ikon != null)
            Text(ikon, style: RythoText.emoji(15))
          else
            Text('✦', style: RythoText.glyph(15, color: RythoColors.lilac)),
          const SizedBox(width: RythoSpace.sm),
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
            padding: const EdgeInsets.symmetric(
                horizontal: RythoSpace.sm + RythoSpace.xxs,
                vertical: RythoSpace.xs),
            decoration: BoxDecoration(
              color: _toneColor(e['tone'] as String?).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(RythoRadius.pill),
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
          const SizedBox(height: RythoSpace.sm),
          Text(e['line'] as String, style: RythoType.body),
        ],
        if (dayanak.isNotEmpty) ...[
          const SizedBox(height: RythoSpace.xs),
          // Açma satırı: ikon chevron, metin satır içi ▴/▾ DEĞİL — o iki
          // glif artık dayanak satırlarının destekleyici/zorlayıcı önekini
          // taşıyor; aynı kartta iki anlam taşıyamaz. Dikey dolgu dokunma
          // hedefini ≥ 44 px'e çıkarır (eski 11.5 px çıplak metindi).
          Pressable(
            onTap: () => setState(() => _acik = !_acik),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(
                      vertical: RythoSpace.sm + RythoSpace.xxs),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(l10n.relationshipBasisTitle,
                    style: RythoText.body(11.5,
                        color: RythoColors.parchmentDim,
                        w: FontWeight.w600)),
                const SizedBox(width: RythoSpace.xxs),
                Icon(
                    _acik
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: RythoColors.parchmentDim),
              ]),
            ),
          ),
          // Koşullu çocuk (dayanak sayfasıyla aynı dil, basis_sheet
          // gerekçesi): `AnimatedCrossFade` kapalı dalı da monte ediyordu.
          // ⚠️ Hareket azaltmada `AnimatedSize` SIFIR SÜREYLE DEĞİL, HİÇ
          // kurulmaz: sıfır sürede denetleyici kendi `performLayout`ı
          // içinde biter ve `markNeedsLayout` fırlatır ("mutated in its own
          // performLayout" — ölçüldü, iliski_ekrani_test). `kapili` bu
          // animatöre uymuyor; kapı dalla kurulur.
          _dayanakBolmesi(
            context,
            !_acik
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: RythoSpace.xs),
                      for (final b in dayanak)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: RythoSpace.xxs),
                          child: _DayanakSatiri(
                            metin: '${b['p1_local']} ${b['aspect_local']} '
                                '${b['p2_local']} · ${b['orb']}°',
                            destekleyici: b['supportive'] == true,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
        if (seviye != 'quiet') ...[
          const SizedBox(height: RythoSpace.xs),
          RythoyaSor(onTap: widget.onAsk),
        ],
      ]),
    );
  }
}

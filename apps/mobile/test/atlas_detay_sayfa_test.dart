// D6 bekçileri — Atlas detay sayfaları ve alt sayfaları: tek kabuk
// (`showRythoSheet`), tek ölçüm satırı (`OlcumSatiri`), tek glif tablosu,
// tek element paleti, büyük harf dönüşümü yok, retro işareti çarkla aynı
// harf, her sayfanın sonunda sohbet kapısı.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/atlas/atlas_detail_screens.dart';
import 'package:rytho/features/chat/chat_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show RythoyaSor;

final _tr = AppLocalizationsTr();

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// İtilen ve kapanan rotaları toplar; sohbete gidildiği ROTADAN doğrulanır
/// (`ChatScreen` çizdirilirse Firebase ister — emsal bes_ekran testi).
/// Alt sayfa testlerinde dokunuştan sonra HİÇ pump yapılmaz: bir kare bile
/// itilen sohbet rotasını kurar. Kapanış da aynı sebeple rotadan okunur
/// (`cikanlar`), ağaçtan değil.
class _RotaGozcusu extends NavigatorObserver {
  final itilenler = <Route<dynamic>>[];
  final cikanlar = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    itilenler.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    cikanlar.add(route);
  }
}

Widget _sar(Widget home, _RotaGozcusu gozcu) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [gozcu],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    );

Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Son itilen rotadan `ChatScreen`in tohumunu okur (ağaç monte edilmez).
String? _tohum(WidgetTester tester, _RotaGozcusu gozcu) {
  final rota = gozcu.itilenler.last;
  expect(rota, isA<MaterialPageRoute<dynamic>>());
  final widget = (rota as MaterialPageRoute<dynamic>)
      .builder(tester.element(find.byType(Navigator).first));
  expect(widget, isA<ChatScreen>());
  return (widget as ChatScreen).initialText;
}

final _mars = <String, dynamic>{
  'name': 'Mars',
  'name_tr': 'Mars',
  'name_local': 'Mars',
  'sign': 'Vir',
  'sign_tr': 'Başak',
  'position': 12.3,
  'house_no': 6,
  'speed': 0.52,
};

void main() {
  group('sohbet kapısı — sayfa ve alt sayfa, tohum sayfaya özel', () {
    testWidgets('Gezegenler: dizinin sonunda, tohum planetsAskPrefill',
        (tester) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final gozcu = _RotaGozcusu();
      await tester.pumpWidget(_sar(AtlasPlanetsScreen(points: [_mars]), gozcu));
      await _bekle(tester);

      final sor = find.byType(RythoyaSor);
      expect(sor, findsOneWidget);
      // Dipnotun ALTINDA: okuma ve dayanak görüldükten sonra.
      expect(tester.getTopLeft(find.text(_tr.planetsFootnote)).dy,
          lessThan(tester.getTopLeft(sor).dy));
      await tester.tap(sor);
      expect(_tohum(tester, gozcu), _tr.planetsAskPrefill);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Açılar: tohum aspectsAskPrefill', (tester) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final gozcu = _RotaGozcusu();
      await tester.pumpWidget(_sar(
          const AtlasAspectsScreen(aspects: [
            {
              'p1': 'Sun', 'p1_tr': 'Güneş', 'p2': 'Mars', 'p2_tr': 'Mars',
              'aspect': 'square', 'aspect_tr': 'Kare', 'orbit': 1.5,
            },
          ]),
          gozcu));
      await _bekle(tester);
      await tester.tap(find.byType(RythoyaSor));
      expect(_tohum(tester, gozcu), _tr.aspectsAskPrefill);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('nokta alt sayfası: sayfa kapanır, tohum noktanın ADI',
        (tester) async {
      final gozcu = _RotaGozcusu();
      await tester.pumpWidget(_sar(
          Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                  onPressed: () => showPointSheet(c, _mars),
                  child: const Text('ac')),
            ),
          ),
          gozcu));
      await tester.tap(find.text('ac'));
      await _bekle(tester);
      expect(find.text(_tr.pointSheetFootnote), findsOneWidget);
      final sor = find.byType(RythoyaSor);
      expect(sor, findsOneWidget, reason: 'alt sayfada sohbet kapısı yok');
      // Kapı dipnotun altında — dayanak okunduktan sonra.
      expect(tester.getTopLeft(find.text(_tr.pointSheetFootnote)).dy,
          lessThan(tester.getTopLeft(sor).dy));

      final altSayfa = gozcu.itilenler.last;
      await tester.tap(sor);
      expect(_tohum(tester, gozcu), _tr.pointAskPrefill('Mars'));
      // Alt sayfa kapandı: sohbetten dönünce açık kalmaz. Kapanış rotadan
      // okunur — kapanış animasyonunu pump'lamak sohbeti de kurardı.
      expect(gozcu.cikanlar, [altSayfa], reason: 'alt sayfa kapanmadı');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('açı alt sayfası: tohum açının ÇİFTİ', (tester) async {
      final gozcu = _RotaGozcusu();
      const aci = {
        'p1': 'Sun', 'p1_tr': 'Güneş', 'p2': 'Mars', 'p2_tr': 'Mars',
        'aspect': 'square', 'aspect_tr': 'Kare', 'orbit': 1.5,
        'movement': 'applying', 'movement_local': 'Yaklaşıyor',
      };
      await tester.pumpWidget(_sar(
          Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                  onPressed: () => showAspectSheet(c, aci),
                  child: const Text('ac')),
            ),
          ),
          gozcu));
      await tester.tap(find.text('ac'));
      await _bekle(tester);
      final altSayfa = gozcu.itilenler.last;
      await tester.tap(find.byType(RythoyaSor));
      expect(_tohum(tester, gozcu), _tr.aspectAskPrefill('Güneş — Mars'));
      expect(gozcu.cikanlar, [altSayfa], reason: 'alt sayfa kapanmadı');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('kaynak: kopyalar gitti', () {
    final k = _yorumsuz('lib/features/atlas/atlas_detail_screens.dart');

    /// Bir sınıfın gövdesi: `class <ad>` ile bir sonraki üst düzey
    /// `class ` arasındaki metin.
    String sinif(String ad) {
      final bas = k.indexOf('class $ad');
      expect(bas, isNonNegative, reason: '$ad yok');
      final son = k.indexOf(RegExp(r'^class ', multiLine: true), bas + 1);
      return son < 0 ? k.substring(bas) : k.substring(bas, son);
    }

    test('alt sayfa kabuğu tek (showRythoSheet), tutamak kopyası yok', () {
      expect(k, isNot(contains('showModalBottomSheet')));
      expect(k.split('showRythoSheet<void>(').length - 1, 3,
          reason: 'üç alt sayfa da kabuktan geçmeli');
      expect(k, isNot(contains('class _SheetTutamak')));
      // Yalnız alt sayfa gövdeleri: sayfa iskeleti (`_DetayIskelet`) kendi
      // Scaffold'unda güvenli alanı meşru kuruyor.
      for (final ad in ['_PointSheet', '_DagilimSheet', '_AspectSheet']) {
        expect(sinif(ad), isNot(contains('SafeArea(')),
            reason: '$ad: kabuk güvenli alanı zaten veriyor; çift dolgu');
      }
    });

    test('ölçüm satırı tek (OlcumSatiri), büyük harf dönüşümü yok', () {
      expect(k, isNot(contains('class _OlcumSatiri')));
      expect(k, contains('OlcumSatiri('));
      expect(k, isNot(contains('.toUpperCase()')),
          reason: 'Türkçe bilmeyen büyük harf geri gelmiş');
    });

    test('retro işareti çarkla aynı harf; ℞ yok', () {
      expect(k, isNot(contains('℞')));
      expect(k, contains("${r'${retro ? '}' R' : ''}"));
    });

    test('glif tablosu ve element paleti tek kaynaktan', () {
      expect(k, isNot(contains('_kPlanetEmojis')));
      expect(k, contains('kPlanetTextGlyphs'));
      expect(k, contains('kExtraPointGlyphs'));
      expect(k, contains('RythoText.glyph(15)'));
      expect(k, contains('kElementTints['));
      expect(k, isNot(contains('Color(0xFF5AC8FA)')),
          reason: 'element rengi ikinci kez elle yazılmış');
    });

    test('her sayfa ve alt sayfa kendi tohumunu taşıyor', () {
      for (final anahtar in const [
        'planetsAskPrefill',
        'traitsAskPrefill',
        'aspectsAskPrefill',
        'pointAskPrefill(',
        'aspectAskPrefill(',
      ]) {
        expect(k, contains(anahtar), reason: '$anahtar tohumu yok');
      }
      // Alt sayfadan sohbete giden yol Navigator'ı KAPATMADAN ÖNCE alır.
      expect(k, contains('final nav = Navigator.of(context);'));
    });
  });
}

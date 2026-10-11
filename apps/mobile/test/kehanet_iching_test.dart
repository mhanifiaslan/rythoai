// D6 bekçileri — İ Ching: yöntem seçici durum göstergesi (degrade değil),
// iniş atlanabilirliği GÖRÜNÜR, shi/ying çevrili, bedel tek kaynaktan,
// Türkçe küçültme `trKucuk`, hareket tek yoldan.
//
// `_HexagramView` özel ve çekimin tamamını ister; okuma kabı oradaki
// sıra `anlam_once_bes_ekran_test`te kaynaktan çivili. Burada CastScene
// gerçek ağaçta (public), gerisi kaynak.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/oracle/iching_tab.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/nebula_widgets.dart' show Pressable;

final _tr = AppLocalizationsTr();

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Widget _sar(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('tr')],
      locale: const Locale('tr'),
      home: MediaQuery(
        data: const MediaQueryData(),
        child: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

void main() {
  testWidgets('iniş sırasında "atlamak için dokun" GÖRÜNÜR, öncesinde ve '
      'sonrasında değil', (tester) async {
    var bitti = 0;
    Widget sahne(List<int>? degerler) => _sar(CastScene(
          lineValues: degerler,
          onFinished: () => bitti++,
          onLand: () async {},
        ));

    // Havada: dokunma işe yaramaz, etiket de yok.
    await tester.pumpWidget(sahne(null));
    expect(find.text(_tr.iChingTapToSkip), findsNothing);

    // Yanıt geldi: kare bitince iniş; etiket şimdi görünür.
    await tester.pumpWidget(sahne(const [7, 7, 7, 7, 7, 7]));
    await tester.pump();
    final st = tester.state<CastSceneState>(find.byType(CastScene));
    expect(st.isLanding, isTrue);
    expect(find.text(_tr.iChingTapToSkip), findsOneWidget,
        reason: 'atlama bir jest olarak kodda, ekranda sessiz');

    // Dokununca biter; etiket kalkar (dokunmanın artık işi yok).
    await tester.tap(find.byType(Pressable));
    await tester.pump();
    expect(st.isDone, isTrue);
    expect(bitti, 1);
    expect(find.text(_tr.iChingTapToSkip), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
  });

  group('kaynak', () {
    final k = _yorumsuz('lib/features/oracle/iching_tab.dart');

    test('yöntem seçici GlassSegments.compact; degrade yok', () {
      expect(k, contains('GlassSegments('));
      expect(k, contains('compact: true'));
      expect(k, isNot(contains('primaryGradient')),
          reason: 'durum göstergesi eylem gibi çiziliyor');
      expect(k, isNot(contains('Colors.white')));
    });

    test('shi/ying çevrili', () {
      expect(k, contains('l10n.iChingShiTag'));
      expect(k, contains('l10n.iChingYingTag'));
      expect(k, isNot(contains("_tag('shi'")));
      expect(k, isNot(contains("_tag('ying'")));
    });

    test('bedel tek kaynaktan (BedelRozeti); token_cost ikinci kaynak değil',
        () {
      expect(k, contains('BedelRozeti(PlusOzellik.iching)'));
      expect(k, isNot(contains('ichingBedeli(durum)')),
          reason: 'rozet durum ucunun token_cost alanını okumaya dönmüş');
    });

    test('Türkçe küçültme trKucuk; elle U+0307 ayıklaması yok', () {
      expect(k, contains('trKucuk('));
      expect(k, isNot(contains('.toLowerCase()')));
      expect(k, isNot(contains("replaceAll('̇'")));
    });

    test('hareket tek yoldan: animate/blok/çıplak süre yok', () {
      expect(k, isNot(contains('.animate(')));
      expect(k, isNot(contains('blok(')));
      expect(k, isNot(contains('Duration(milliseconds: 400)')));
      expect(k, contains('kapili(context, RythoMotion.celebrate)'));
      expect(k, contains('RythoReveal('));
    });

    test('okuma kabı tekrar dene ile: aynı soruyla yeni çekim', () {
      final govde = k.substring(k.indexOf('class _HexagramView'));
      expect(govde, contains('onTekrarDene: onTekrarDene'));
      expect(k, contains('_HexagramView(result: _result!, onTekrarDene: _cast)'));
    });
  });
}

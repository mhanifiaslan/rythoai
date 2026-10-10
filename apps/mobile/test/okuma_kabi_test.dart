// OkumaKabi bekçileri — `fallback` bayrağını ÇİZEN tek widget.
//
// Ölçülen kusur: dokuz okuma yüzeyinin beşi bayrağı okumuyor, sunucunun
// şablon paragrafı rapor gibi duruyor ve paylaşım kartına bile basılıyordu.
// Kap bunu YAPISAL olarak kapatır: üretilemedi dalında paylaş YOK, tekrar
// dene VAR, okuma metni (MarginNote) YOK; hazır dalında paylaş + Rytho'ya
// sor; yükleniyor dalı aşama sahnesi. İade cümlesi sunucunun bayrağından —
// istemcide varsayım yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/okuma_durumu.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show MarginNote, RythoyaSor;
import 'package:rytho/widgets/common.dart' show ErrorCard;
import 'package:rytho/widgets/motion.dart' show StagedWaiting;
import 'package:rytho/widgets/okuma_kabi.dart';

final _tr = AppLocalizationsTr();

Widget _sar(Widget child) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      // Usturlap sürekli animatör, hata kartı giriş sarsıntısı: ölçülen şey
      // yerleşim, hareket değil (emsal: yeni_konusma_fab_test).
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

const _tarif = PaylasimTarifi(title: 'Yıl Haritası', dateLabel: '2026');

/// Her dalda AYNI kap: bir dalın çizdiği şey öteki dala sızmıyor mu, bunu
/// ancak tüm kapılar verilmişken ölçebiliriz.
OkumaKabi _kap(OkumaDurumu durum) => OkumaKabi(
      durum: durum,
      ekranKodu: 'test',
      baslik: 'Okuma',
      onTekrarDene: () {},
      onSor: () {},
      paylasim: _tarif,
      beklemeAsamalari: const ['Aşama 1'],
      kilit: const Text('KİLİT'),
    );

void main() {
  testWidgets(
      'üretilemedi: paylaş YOK, tekrar dene VAR, okuma metni YOK; iade cümlesi',
      (tester) async {
    await tester.pumpWidget(_sar(_kap(const OkumaUretilemedi(iadeli: true))));
    await tester.pump();

    expect(find.text(_tr.shareReading), findsNothing,
        reason: 'şablon kart olamaz — paylaşım yapısal olarak yok');
    expect(find.byType(RythoyaSor), findsNothing);
    expect(find.byType(MarginNote), findsNothing,
        reason: 'üretilmemiş metin rapor yerine geçmez');
    expect(find.byType(ErrorCard), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text(_tr.reportUnavailableRefunded), findsOneWidget);
  });

  testWidgets('üretilemedi iadesiz: iade cümlesi YOK (jetonsuz uçta yalan olurdu)',
      (tester) async {
    await tester.pumpWidget(_sar(_kap(const OkumaUretilemedi(iadeli: false))));
    await tester.pump();

    expect(find.text(_tr.reportUnavailable), findsOneWidget);
    expect(find.text(_tr.reportUnavailableRefunded), findsNothing);
  });

  testWidgets("hazır: okuma metni + paylaş + Rytho'ya sor", (tester) async {
    await tester.pumpWidget(_sar(_kap(const OkumaHazir('Bugün sabır günü.'))));
    await tester.pump();

    expect(find.byType(MarginNote), findsOneWidget);
    expect(find.text(_tr.shareReading), findsOneWidget);
    expect(find.byType(RythoyaSor), findsOneWidget);
    expect(find.byType(ErrorCard), findsNothing);
  });

  testWidgets('hazır ama kapılar verilmemiş: metin tek başına', (tester) async {
    await tester.pumpWidget(_sar(const OkumaKabi(
      durum: OkumaHazir('Bugün sabır günü.'),
      ekranKodu: 'test',
    )));
    await tester.pump();

    expect(find.byType(MarginNote), findsOneWidget);
    expect(find.text(_tr.shareReading), findsNothing);
    expect(find.byType(RythoyaSor), findsNothing);
  });

  testWidgets('yükleniyor: aşama sahnesi, verilen metinle', (tester) async {
    await tester.pumpWidget(_sar(_kap(const OkumaYukleniyor())));
    await tester.pump();

    expect(find.byType(StagedWaiting), findsOneWidget);
    expect(find.text('Aşama 1'), findsOneWidget);
    expect(find.byType(MarginNote), findsNothing);

    // Sahnenin aşama zamanlayıcısı test bitince askıda kalmasın: kap sökülür.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(RythoMotion.asamaAraligi);
  });

  testWidgets('hata: hata kartı + tekrar dene, paylaş YOK', (tester) async {
    await tester.pumpWidget(_sar(_kap(OkumaHata(StateError('ağ')))));
    await tester.pump();

    expect(find.byType(ErrorCard), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text(_tr.shareReading), findsNothing);
  });

  testWidgets('kilitli: çağıranın verdiği kilit kartı', (tester) async {
    await tester.pumpWidget(_sar(_kap(const OkumaKilitli())));
    await tester.pump();

    expect(find.text('KİLİT'), findsOneWidget);
    expect(find.byType(MarginNote), findsNothing);
  });
}

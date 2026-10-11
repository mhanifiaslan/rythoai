// D6 bekçileri — yüz okuma: okuma kabı, ekran kodu, kamera reddi.
//
// Ölçülen hâl: okuma `GlassPanel(Text(snap.data ?? ''))` ile çiziliyordu —
// boş metin BOŞ PANEL; `fetchFirasaReading` bayrağı kendi mekanizmasıyla
// okuyup fırlatıyordu; hata kartının ekran kodu 'atlas'tı (yüz okuma
// kehanet ailesinde — bildirim yanlış ekrana düşüyordu); kamera reddinde
// "Ayarları aç" etiketli düğme yalnız YENİDEN DENİYORDU, ayar açmıyordu.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/features/face/face_capture_screen.dart';
import 'package:rytho/features/face/face_geometry.dart';
import 'package:rytho/features/face/face_motion.dart';
import 'package:rytho/features/face/face_reading_flow.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show MarginNote, RythoyaSor;
import 'package:rytho/widgets/motion.dart' show StagedWaiting;
import 'package:rytho/widgets/okuma_kabi.dart' show PaylasKapisi;

final _tr = AppLocalizationsTr();

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

class _SahteAdapter implements HttpClientAdapter {
  _SahteAdapter(this.govde);

  /// null → yanıt HİÇ gelmez (bekleme sahnesi ölçülür).
  final String? govde;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    final g = govde;
    if (g == null) return Completer<ResponseBody>().future;
    return Future.value(ResponseBody.fromString(g, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    }));
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_SahteAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://test.invalid'))
      ..httpClientAdapter = adapter;

FaceCaptureResult _cekim({bool tekKare = false}) => FaceCaptureResult(
      const FaceRatios(
        upperThird: 0.33,
        middleThird: 0.33,
        lowerThird: 0.34,
        widthToHeight: 0.70,
        jawToCheek: 0.80,
        mouthToFaceWidth: 0.41,
        lipFullness: 0.05,
        eyeSpacing: 0.45,
        symmetry: 0.98,
      ),
      MotionMetrics.empty,
      singleFrame: tekKare,
    );

Future<void> _kur(WidgetTester tester, String? govde,
    {double genislik = 420,
    double olcek = 1.0,
    bool tekKare = false}) async {
  tester.view.physicalSize = Size(genislik, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiProvider.overrideWithValue(_dio(_SahteAdapter(govde)))],
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(olcek), disableAnimations: true),
        child: child!,
      ),
      home: FaceReadingScreen(result: _cekim(tekKare: tekKare)),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

const _hazir = '{"status":"success","reading":"Gerçek firaset okuması: '
    'yüzünün orta üçlüsü uzun.","cached":false,"fallback":false}';

void main() {
  group('okuma kabı', () {
    testWidgets('hazır okuma: metin + paylaş + Rytho\'ya sor', (tester) async {
      await _kur(tester, _hazir, tekKare: true);
      expect(find.byType(MarginNote), findsOneWidget);
      expect(find.textContaining('Gerçek firaset okuması'), findsOneWidget);
      expect(find.byType(PaylasKapisi), findsOneWidget);
      expect(find.byType(RythoyaSor), findsOneWidget);
      // Geleneğin sınırı ve tek-kare beyanı okumanın ÜSTÜNDE.
      expect(find.text(_tr.faceReadingHint), findsOneWidget);
      expect(find.text(_tr.faceStillSingleFrameNote), findsOneWidget);
      expect(tester.getTopLeft(find.text(_tr.faceReadingHint)).dy,
          lessThan(tester.getTopLeft(find.byType(MarginNote)).dy));
    });

    testWidgets('boş metin: boş panel DEĞİL, üretilemedi', (tester) async {
      await _kur(tester, '{"status":"success","reading":"","cached":false}');
      expect(find.byType(MarginNote), findsNothing,
          reason: 'boş metin okuma gibi çizildi');
      expect(find.text(_tr.reportUnavailable), findsOneWidget);
      expect(find.text(_tr.retry), findsOneWidget);
      expect(find.byType(PaylasKapisi), findsNothing);
    });

    testWidgets('bekleme sahneli: aşama metni kabın içinden', (tester) async {
      await _kur(tester, null);
      expect(find.byType(StagedWaiting), findsOneWidget);
      expect(find.text(_tr.faceWaitStage1), findsOneWidget);
      // Sahnenin zamanlayıcısı testi kirletmesin.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('320 dp × 1,3: taşma yok', (tester) async {
      await _kur(tester, _hazir,
          genislik: 320, olcek: kMaxTextScale, tekKare: true);
      expect(tester.takeException(), isNull);
      expect(find.byType(PaylasKapisi), findsOneWidget);
    });
  });

  group('kaynak', () {
    test('okuma akışı: ekran kodu oracle, aşamalar ve tohum kapta', () {
      final k = _yorumsuz('lib/features/face/face_reading_flow.dart');
      expect(k, contains("ekranKodu: 'oracle'"));
      expect(k, isNot(contains("'atlas'")),
          reason: 'bildirim yanlış ekrana düşer');
      expect(k, contains('beklemeAsamalari:'));
      expect(k, contains('faceWaitStage3'));
      expect(k, contains('faceAskPrefill'));
      expect(k, isNot(contains('class _FirasaWaiting')),
          reason: 'bekleme sahnesinin ikinci kopyası geri gelmiş');
      // Okuma ekranının gövdesi: rıza formu (aynı dosya) kendi panelini
      // meşru kullanıyor; yasak olan OKUMANIN panelle çizilmesi.
      final okuma = k.substring(k.indexOf('class _FaceReadingScreenState'));
      expect(okuma, isNot(contains('GlassPanel(')),
          reason: 'okuma kabın dışında panelle çiziliyor');
    });

    test('kamera reddi: Ayarları aç GERÇEKTEN ayarları açar, yeniden dene ayrı',
        () {
      final k = _yorumsuz('lib/features/face/face_capture_screen.dart');
      final bas = k.indexOf('Widget _hataKatmani(');
      expect(bas, isNonNegative);
      final govde = k.substring(bas);
      expect(govde, contains('AppSettings.openAppSettings()'),
          reason: '"Ayarları aç" düğmesi ayar açmıyor');
      // Her iki eylem de izin reddi dalında: ayarlara git + el ile dene.
      final red = govde.substring(govde.indexOf('_Asama.izinYok) ...['));
      expect(red, contains('l10n.faceOpenSettings'));
      expect(red, contains('l10n.retry'));
      expect(red, contains('onPressed: _yenidenDene'));
      // Eski tuzak: "Ayarları aç" etiketi yeniden deneme düğmesinde.
      expect(
          govde,
          isNot(contains('onPressed: _yenidenDene,\n'
              '                  child: Text(_asama == _Asama.izinYok')));
    });

    test('kılavuz nabzı kapılı; çıplak TextStyle yok', () {
      final k = _yorumsuz('lib/features/face/face_capture_screen.dart');
      expect(k, contains('_nabziKapila()'));
      expect(k, contains('reduceMotion(context)'));
      expect(k, isNot(contains(')..repeat();')),
          reason: 'kapısız sonsuz döngü geri gelmiş');
      expect(k, contains('duration: RythoMotion.breath'));
      expect(k, isNot(contains('const TextStyle(')),
          reason: 'ham TextStyle: rol tipografisi dışında yazı');
    });

    test('face_capture: arıza bildirim çapaları korunuyor', () {
      // İzin dalı değişirken Crashlytics teşhisi dokunulmadı
      // (face_ariza_kanit_test'in iddiası); burada ikinci bir işaret.
      final k = _yorumsuz('lib/features/face/face_capture_screen.dart');
      expect(k, contains('} on CameraException catch (e, iz) {'));
      expect(k, contains("if (!e.code.contains('Permission'))"));
    });
  });
}

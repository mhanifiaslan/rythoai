// gz-2 bekçileri (istemci yarısı): ÜRETİLMEYEN YORUM rapor yerine geçmez —
// ama ÖLÇÜLEN çıktı da silinmez.
//
// Gemini kotası dolduğunda sunucu hazır bir paragrafı `fallback: true` ile
// döndürüyor ve harcanan jetonu iade ediyor. İstemci bunu okuma gibi
// gösterirse kullanıcı üç cümleyi ÜRÜN sanır ("rapor çok yüzeysel" bize model
// şikâyeti olarak döner), iadeyi hiç öğrenmez ve `report_generated` sayacı
// "üretildi" der.
//
// İkinci yarısı da en az onun kadar önemli ve ilk yamada TERS gitmişti: BaZi
// haritası (dört sütun, Day Master, güç hükmü, şans dönemleri) LLM ürünü
// DEĞİL, deterministik hesap ve ücreti ödendi. Sağlayıcı fırlatırsa ekran
// `data` dalına hiç girmez ve ölçülmüş, doğru çıktının tamamı kullanıcıdan
// saklanır. Bu dosya iki yönü birlikte tutuyor: yorum yerine dürüst cümle,
// haritanın yerinde kalması.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` turu flutter_riverpod 3'te misc.dart'tan geliyor.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/face/face_api.dart';
import 'package:rytho/features/face/face_capture_screen.dart';
import 'package:rytho/features/face/face_geometry.dart';
import 'package:rytho/features/face/face_motion.dart';
import 'package:rytho/features/face/face_reading_flow.dart';
import 'package:rytho/features/oracle/bazi_tab.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_en.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/main.dart' show rythoRetry;
import 'package:rytho/widgets/atlas_widgets.dart' show MarginNote;
import 'package:rytho/widgets/common.dart' show ErrorCard;
import 'package:rytho/features/profile/feedback_screen.dart'
    show kFeedbackScreens;

final _tr = AppLocalizationsTr();
final _en = AppLocalizationsEn();

/// Kaynak bekçilerinin BİR ŞEYİN YOKLUĞUNU ararken kendi açıklama yorumuna
/// takılmaması için: tam satır yorumları ve `///` belgeleri atılır.
///
/// Bu tuzak bu depoda gerçekten patladı — bir kaynak bekçisi, kaldırılan
/// deseni ANLATAN yoruma bakıp yanlış pozitif verdi.
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

// ---------------------------------------------------------------------------
// Sahte uç
// ---------------------------------------------------------------------------

class _SahteAdapter implements HttpClientAdapter {
  _SahteAdapter(this.govde);

  final String govde;
  int istekSayisi = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istekSayisi++;
    return ResponseBody.fromString(govde, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_SahteAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://test.invalid'))
      ..httpClientAdapter = adapter;

/// Oranlar bu testin konusu değil; uç sahte.
FaceCaptureResult _cekim() => const FaceCaptureResult(
      FaceRatios(
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
    );

Widget _sar(Widget govde, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(body: govde),
      ),
    );

/// Animasyonlar (flutter_animate) sürekli koşuyor — `pumpAndSettle` dönmez.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

// ---------------------------------------------------------------------------
// BaZi: ölçülmüş harita. Alanlar `get_bazi_chart` + `localize_bazi`
// çıktısından alındı; yalnız sekmenin OKUDUĞU kalemler bırakıldı.
// ---------------------------------------------------------------------------

Map<String, dynamic> _sutun(String stem, String branch, String hayvan) => {
      'stem': {'cn': stem, 'element': 'Ahşap'},
      'branch': {
        'cn': branch,
        'animal': hayvan,
        'hidden': [
          {'pinyin': 'Wu'},
        ],
      },
    };

Map<String, dynamic> _harita() => {
      'zodiac_animal': 'Köpek',
      'day_master': {'description': 'Yang Ahşap'},
      'pillars': {
        'year': _sutun('甲', '戌', 'Köpek'),
        'month': _sutun('壬', '申', 'Maymun'),
        'day': _sutun('戊', '子', 'Sıçan'),
        'hour': _sutun('丙', '辰', 'Ejder'),
      },
      'ten_gods': {
        'year': {'name': 'Jie Cai'},
        'month': {'name': 'Shi Shen'},
        'hour': {'name': 'Pian Yin'},
      },
      'strength': {
        'ratio': 0.62,
        'verdict_name': 'GÜÇLÜ GÖVDE',
        'season_state_name': 'Wang',
        'favorable_names': ['Metal'],
        'unfavorable_names': ['Ahşap'],
        'components': [
          {'side': 'support', 'points': 12, 'source': 'root:day:Toprak'},
        ],
      },
      'notes': ['Gerçek güneş saati düzeltmesi: −77 dakika.'],
      'element_distribution': {'Ahşap': 2.4, 'Toprak': 3.1},
      'missing_elements': ['Ateş'],
      'shen_sha': [
        {'name': 'Tian Yi', 'pillar': 'gün', 'meaning': 'Gökyüzü yardımı'},
      ],
      'luck_pillars': [
        {
          'from_year': 2000,
          'to_year': 2010,
          'from_age': 6,
          'to_age': 16,
          'stem': {'cn': '甲'},
          'branch': {'cn': '戌'},
          'ten_god': {'name': 'Jie Cai'},
        },
      ],
      'current_luck_index': 0,
      'luck_start': {'years': 6, 'months': 2, 'date': '2000-10-01'},
      'current_year_pillar': {
        'label': '甲辰',
        'ten_god': {'name': 'Jie Cai'},
      },
    };

/// Kotanın döndürdüğü hazır paragraf — ekranda ASLA görünmemeli.
const _hazirParagraf = 'Bugun gokyuzu sakin, kendine iyi bak.';

Map<String, dynamic> _baziYanit({required bool yedek}) => {
      'chart': _harita(),
      'report': yedek ? _hazirParagraf : 'GERÇEK BaZi raporu.',
      if (yedek) ...{'fallback': true, 'refunded': true},
    };

void main() {
  // -------------------------------------------------------------------------
  group('friendlyError', () {
    test('jeton iade edildiyse KULLANICIYA SÖYLENİR', () {
      const hata = RaporUretilemedi(jetonIadeEdildi: true);
      expect(friendlyError(hata, _tr), _tr.reportUnavailableRefunded);
      expect(friendlyError(hata, _tr), contains('iade'));
    });

    test('jeton harcanmayan uçta iade CÜMLESİ YOK (yalan olurdu)', () {
      expect(friendlyError(const RaporUretilemedi(), _tr),
          _tr.reportUnavailable);
      expect(friendlyError(const RaporUretilemedi(), _tr),
          isNot(contains('iade')));
    });

    test('İngilizce arayüzde Türkçe metin ÇIKMAZ', () {
      // Bu yamanın en büyük riski: gövdeye gömülü Türkçe geri düşüş.
      const iadeli = RaporUretilemedi(jetonIadeEdildi: true);
      expect(friendlyError(iadeli, _en), _en.reportUnavailableRefunded);
      expect(friendlyError(iadeli, _en), isNot(contains('jeton')));
      expect(friendlyError(const RaporUretilemedi(), _en),
          isNot(contains('Okumayı')));
    });

    test('yeni istisna öbür dalları BOZMUYOR', () {
      expect(friendlyError(StateError('x'), _tr), _tr.errorGeneric);
    });
  });

  // -------------------------------------------------------------------------
  group('rythoRetry', () {
    test('yedek metni otomatik yeniden DENEMEZ', () {
      // Sunucu 200 döndü: ağ hatası değil. Otomatik deneme kotayı besler ve
      // her tur bir jeton düş/iade turudur.
      expect(rythoRetry(0, const RaporUretilemedi()), isNull);
      expect(rythoRetry(0, const RaporUretilemedi(jetonIadeEdildi: true)),
          isNull);
    });

    test('gerçek geçici hatalar hâlâ denenir', () {
      expect(
          rythoRetry(
              0,
              DioException(
                  requestOptions: RequestOptions(path: '/x'),
                  response: Response(
                      requestOptions: RequestOptions(path: '/x'),
                      statusCode: 500))),
          isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  group('fetchFirasaReading', () {
    test('fallback bayraklı yanıt okuma DÖNDÜRMEZ, fırlatır', () async {
      await expectLater(
        fetchFirasaReading(
            _dio(_SahteAdapter('{"status":"success","reading":"Hazir para'
                'graf.","cached":false,"fallback":true,"refunded":true}')),
            _cekim()),
        throwsA(isA<RaporUretilemedi>()
            .having((e) => e.jetonIadeEdildi, 'jetonIadeEdildi', isTrue)),
      );
    });

    test('normal yanıt aynen döner', () async {
      final metin = await fetchFirasaReading(
          _dio(_SahteAdapter('{"status":"success","reading":"Gerçek okuma.",'
              '"cached":false,"fallback":false}')),
          _cekim());

      expect(metin, 'Gerçek okuma.');
    });
  });

  // -------------------------------------------------------------------------
  group('sağlayıcılar yedek metni "üretildi" diye SAYMAZ', () {
    // Sağlayıcıları koşturmak Firebase oturumu ister; sabitlenen şey SIRA:
    // bayrak kontrolü sayaçtan ÖNCE gelmeli. Eşleşme dize literaline bağlı
    // (ham 'daily' başka yerlere takılır) ve yorumlar atılıyor.
    final kaynak = _yorumsuz('lib/core/providers.dart');

    for (final uc in ['daily', 'natal']) {
      test('$uc: bayrak Analytics\'ten önce fırlatır', () {
        final post = kaynak.indexOf("'/api/v1/reports/$uc'");
        expect(post, isNonNegative);
        final firlat = kaynak.indexOf('throw RaporUretilemedi', post);
        final sayac = kaynak.indexOf("Analytics.reportGenerated('$uc')", post);
        expect(firlat, isNonNegative, reason: 'yedek metin rapor gibi dönüyor');
        expect(sayac, isNonNegative);
        expect(firlat, lessThan(sayac),
            reason: 'yedek metin "üretildi" sayılırsa ölçüm de yalan söyler');
      });
    }

    test('bazi: FIRLATMAZ ama sayacı da ARTIRMAZ', () {
      // Harita ölçülmüş veri: fırlatmak onu da silerdi (aşağıdaki widget
      // bekçisi bunu çiziyor). Sayaç yine de susmak zorunda.
      final post = kaynak.indexOf("'/api/v1/reports/bazi'");
      expect(post, isNonNegative);
      final sonrasi = kaynak.substring(post, kaynak.indexOf('});', post));
      expect(sonrasi, isNot(contains('throw RaporUretilemedi')),
          reason: 'fırlatmak ölçülmüş BaZi haritasını da götürür');
      expect(
          sonrasi,
          contains("if (veri['fallback'] != true) "
              "Analytics.reportGenerated('bazi')"),
          reason: 'yedek metin "üretildi" sayılırsa ölçüm yalan söyler');
    });
  });

  // -------------------------------------------------------------------------
  group('BaZi sekmesi: harita KALIR, yorumun yerine dürüst cümle gelir', () {
    testWidgets('yedek metinde harita çizilir, paragraf GÖRÜNMEZ',
        (tester) async {
      await tester.pumpWidget(_sar(const BaziTab(), overrides: [
        // P2: sekme artık ÜÇ DURUMLU kapıdan geçiyor ve kapı açık
        // olmadan ücretli sağlayıcı hiç okunmuyor. Bu grubun iddiası
        // "abone ve cevap geldi" hâlinde ne çizildiği — kapı o yüzden
        // açık kurulur (üç hâlin ayrımı plus_kapisi_test.dart'ta).
        raporKapisiProvider.overrideWithValue(PlusHali.abone),
        baziReportProvider.overrideWith((ref) async => _baziYanit(yedek: true)),
      ]));
      await _bekle(tester);

      // 1) ÖLÇÜLEN çıktı yerinde: dört sütun, Day Master satırı, güç hükmü.
      expect(find.text('戊'), findsWidgets, reason: 'gün gövdesi kayboldu');
      expect(find.text('GÜÇLÜ GÖVDE'), findsOneWidget,
          reason: 'güç hükmü LLM ürünü değil; silinmemeli');
      expect(find.textContaining('Köpek'), findsWidgets);

      // 2) Üretilmeyen yorumun yerinde dürüst cümle + çıkış yolu var.
      await tester.scrollUntilVisible(find.byType(ErrorCard), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(find.text(_tr.reportUnavailableRefunded), findsOneWidget);
      expect(find.text(_tr.retry), findsOneWidget);

      // 3) Hazır paragraf hiçbir yerde YOK.
      expect(find.byType(MarginNote), findsNothing,
          reason: 'üretilmeyen paragraf rapor gibi duruyor');
      expect(find.textContaining(_hazirParagraf), findsNothing);
    });

    testWidgets('GERÇEK hatada da çıkış yolu var', (tester) async {
      // Bu sekmede aşağı çekme YOK: düz metin kullanıcıyı uygulamayı yeniden
      // açmaya zorluyordu. Yedek metin artık `data` dalına gittiği için bu
      // dal yalnız gerçek hataları (ağ, 500) karşılıyor — çıkışsızlık aynı.
      await tester.pumpWidget(_sar(const BaziTab(), overrides: [
        // P2: sekme artık ÜÇ DURUMLU kapıdan geçiyor ve kapı açık
        // olmadan ücretli sağlayıcı hiç okunmuyor. Bu grubun iddiası
        // "abone ve cevap geldi" hâlinde ne çizildiği — kapı o yüzden
        // açık kurulur (üç hâlin ayrımı plus_kapisi_test.dart'ta).
        raporKapisiProvider.overrideWithValue(PlusHali.abone),
        baziReportProvider.overrideWith((ref) async => throw StateError('x')),
      ]));
      await _bekle(tester);

      expect(find.byType(ErrorCard), findsOneWidget);
      expect(find.text(_tr.retry), findsOneWidget, reason: 'çıkış yolu yok');
    });

    testWidgets('normal raporda yorum kalemi AYNEN durur', (tester) async {
      // Ters yön: yama iyi durumu da susturmuş olmasın.
      await tester.pumpWidget(_sar(const BaziTab(), overrides: [
        // P2: sekme artık ÜÇ DURUMLU kapıdan geçiyor ve kapı açık
        // olmadan ücretli sağlayıcı hiç okunmuyor. Bu grubun iddiası
        // "abone ve cevap geldi" hâlinde ne çizildiği — kapı o yüzden
        // açık kurulur (üç hâlin ayrımı plus_kapisi_test.dart'ta).
        raporKapisiProvider.overrideWithValue(PlusHali.abone),
        baziReportProvider
            .overrideWith((ref) async => _baziYanit(yedek: false)),
      ]));
      await _bekle(tester);

      await tester.scrollUntilVisible(find.byType(MarginNote), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(find.textContaining('GERÇEK BaZi raporu.'), findsOneWidget);
      expect(find.byType(ErrorCard), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('Firaset: dürüst cümlenin arkasında GERÇEKTEN bir yol var', () {
    testWidgets('hata kartındaki tekrar dene okumayı YENİDEN İSTER',
        (tester) async {
      final adapter = _SahteAdapter('{"status":"success","reading":"Hazir '
          'paragraf.","cached":false,"fallback":true,"refunded":true}');
      await tester.pumpWidget(_sar(
        FaceReadingScreen(result: _cekim()),
        overrides: [apiProvider.overrideWithValue(_dio(adapter))],
      ));
      await _bekle(tester);

      expect(find.text(_tr.reportUnavailableRefunded), findsOneWidget);
      expect(adapter.istekSayisi, 1);

      // `late final` future yeniden kurulamıyordu: metin "tekrar dene" diyor
      // ama tek çıkış ekrandan çıkıp YÜZÜ BAŞTAN ÇEKMEKTİ.
      await tester.tap(find.text(_tr.retry));
      await _bekle(tester);
      expect(adapter.istekSayisi, 2, reason: 'tekrar dene isteği kurmuyor');
    });

    test('kaynakta yeniden kurulabilir future var', () {
      final kaynak = _yorumsuz('lib/features/face/face_reading_flow.dart');
      expect(kaynak, isNot(contains('late final Future<String> _okuma')),
          reason: 'sabit future yeniden kurulamaz; tekrar dene yalan olur');
      expect(kaynak, contains('onRetry: _tekrarDene'));
    });
  });

  // -------------------------------------------------------------------------
  group('Atlas natal satırı: dürüst cümle EKRANA GELİR', () {
    // `_FullReportRow` özel bir sınıf ve AtlasScreen Firestore akışlarına
    // bağlı; sabitlenen şey hata dalının hata NESNESİNİ kullanması. Eskiden
    // `error: (_, _) =>` sabit bir alt satır gösteriyordu, yani
    // `RaporUretilemedi` oraya düştüğünde kullanıcı ne "şu an üretemedik" ne
    // "jetonun iade edildi" görüyordu.
    final kaynak = _yorumsuz('lib/features/atlas/atlas_screen.dart');

    test('hata dalı hata NESNESİNİ kullanıyor', () {
      expect(kaynak, contains('subtitle: friendlyError(e, l10n)'),
          reason: 'hata nesnesi atılıyor; dürüst cümle ekrana gelmiyor');
      expect(kaynak, isNot(contains('subtitle: l10n.atlasReportRetry')),
          reason: 'sabit alt satır dürüst cümlenin yerini alıyor');
      // Kusurun kendisi tek satırdı: `error: (_, _) =>` hata nesnesini
      // BAĞLAMIYOR, yani hangi hata olduğu ekrana hiç ulaşmıyordu.
      expect(kaynak, isNot(contains('error: (_, _) => _AtlasRow(')));
      expect(kaynak, contains('error: (e, _) => _AtlasRow('));
    });

    test('alt satır iade cümlesini KIRPMIYOR', () {
      // Tek satır + ellipsis tam da söylenmesi gereken yeri kesiyordu.
      expect(kaynak, contains('subtitleLines: 3'));
      expect(kaynak, contains('maxLines: subtitleLines'));
    });
  });

  // -------------------------------------------------------------------------
  test('hata kartlarının ekran kodu KAPALI KÜMEDEN', () {
    // `screen` kümede değilse `FeedbackScreen` onu sessizce düşürüyor —
    // 'bazi' yazmak bildirimi ekransız bırakırdı.
    for (final dosya in [
      'lib/features/oracle/bazi_tab.dart',
      'lib/features/face/face_reading_flow.dart',
    ]) {
      final kodlar = RegExp(r"screen: '([a-z_]+)'")
          .allMatches(_yorumsuz(dosya))
          .map((m) => m.group(1)!)
          .toList();
      expect(kodlar, isNotEmpty, reason: '$dosya: ekran kodu yok');
      for (final k in kodlar) {
        expect(kFeedbackScreens, contains(k), reason: '$dosya: $k düşürülür');
      }
    }
  });
}

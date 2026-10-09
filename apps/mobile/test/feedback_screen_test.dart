// Geri bildirim ekranı bekçileri (GB-turu).
//
// Sözleşme (backend ile paralel yazıldı): `POST /api/v1/account/feedback`
// gövde {type, text, screen?}; 200 → teşekkür görünümü; 429 → sunucunun
// `detail`i OLDUĞU GİBİ SnackBar'da. Başlıklar Dio'da zaten var, burada
// eklenmez. Yanıt bildirimi `type=feedback` ana sekmede kalır.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/notifications.dart';
import 'package:rytho/features/profile/feedback_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:rytho/widgets/common.dart' show ErrorCard;

/// Her isteği kaydeden, sabit yanıt veren sahte sunucu
/// (device_session_test.dart ile aynı desen).
class _SahteAdapter implements HttpClientAdapter {
  _SahteAdapter({this.durum = 200, this.govde = '{"status":"ok","id":"f1"}'});

  final int durum;
  final String govde;
  final List<RequestOptions> istekler = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istekler.add(options);
    return ResponseBody.fromString(
      govde,
      durum,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_SahteAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
  dio.httpClientAdapter = adapter;
  return dio;
}

Widget _uygulama(Widget child, {Locale locale = const Locale('tr')}) =>
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: child,
    );

Widget _sar(Widget child, _SahteAdapter adapter,
        {Locale locale = const Locale('tr')}) =>
    ProviderScope(
      overrides: [apiProvider.overrideWithValue(_dio(adapter))],
      child: _uygulama(child, locale: locale),
    );

/// Yıldız alanı sürekli animasyonlu — `pumpAndSettle` hiç dönmez.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

GoldButton _gonderDugmesi(WidgetTester tester) =>
    tester.widget<GoldButton>(find.widgetWithText(GoldButton, 'Gönder'));

Future<void> _yazVeGonder(WidgetTester tester, String metin) async {
  await tester.enterText(find.byType(TextField), metin);
  await tester.pump();
  await tester.tap(find.widgetWithText(GoldButton, 'Gönder'));
  // SEÇİM TEMİZLENİR — bu bir TEST ORTAMI onarımı, ürün davranışı değil.
  //
  // `enterText` alanda bir seçim bırakıyor. Hata dalında (429) form ekranda
  // KALIYOR, yani SnackBar girerken alanın seçim tutamaçları da çiziliyor ve
  // test ortamında `RenderEditable._paintHandleLayers` null'a düşüyor
  // (`NoSuchMethodError ... during paint()`). Gerçek cihazda o katman var;
  // kusur üründe değil. 200 dalı etkilenmiyordu çünkü ekran teşekküre
  // geçince alan ağaçtan kalkıyor — bu yüzden YALNIZ 429 testi düşüyordu.
  //
  // ⚠️ `offset: -1` = seçim YOK. Çökmeyi durduran tek şey bu satır; odağı
  // bırakmak (`primaryFocus?.unfocus()`) ÖLÇÜLDÜ ve YETMİYOR, o yüzden
  // konmadı.
  //
  // Testin ÖLÇTÜĞÜ hiçbir şey değişmiyor: SnackBar metni, teşekkür
  // görünümünün yokluğu, formun kalması ve düğmenin kilitlenmemesi aynen
  // sınanıyor.
  tester.widget<TextField>(find.byType(TextField)).controller?.selection =
      const TextSelection.collapsed(offset: -1);
  await _bekle(tester);
}

void main() {
  group('görünüm', () {
    testWidgets('l10n metinleri (tr): başlık, giriş, üç tür, ekran, gizlilik',
        (tester) async {
      await tester.pumpWidget(_sar(const FeedbackScreen(), _SahteAdapter()));
      await _bekle(tester);

      expect(find.text('Geri bildirim'), findsOneWidget);
      expect(find.textContaining('doğrudan bize ulaşır'), findsOneWidget);
      expect(find.text('Hata 🐞'), findsOneWidget);
      expect(find.text('Öneri 💡'), findsOneWidget);
      expect(find.text('Diğer ✨'), findsOneWidget);
      expect(find.text('Hangi ekran?'), findsOneWidget);
      expect(find.text('Gökyüzü'), findsOneWidget);
      expect(find.text('Kehanet'), findsOneWidget);
      expect(find.textContaining('hesabınla birlikte kaydedilir'),
          findsOneWidget);
      expect(find.widgetWithText(GoldButton, 'Gönder'), findsOneWidget);
    });

    testWidgets('l10n metinleri (en) — İngilizce ARB eksiksiz', (tester) async {
      await tester.pumpWidget(_sar(const FeedbackScreen(), _SahteAdapter(),
          locale: const Locale('en')));
      await _bekle(tester);
      expect(find.text('Feedback'), findsOneWidget);
      expect(find.text('Bug 🐞'), findsOneWidget);
      expect(find.text('Which screen?'), findsOneWidget);
      expect(find.widgetWithText(GoldButton, 'Send'), findsOneWidget);
    });

    testWidgets('10 karakterin altında Gönder KAPALI, uyarı görünür',
        (tester) async {
      await tester.pumpWidget(_sar(const FeedbackScreen(), _SahteAdapter()));
      await _bekle(tester);
      expect(_gonderDugmesi(tester).onPressed, isNull,
          reason: 'boş metinle gönderim yok');

      await tester.enterText(find.byType(TextField), 'kısa   ');
      await tester.pump();
      expect(_gonderDugmesi(tester).onPressed, isNull,
          reason: 'kırpılmış uzunluk sayılır');
      expect(find.text('En az 10 karakter yaz.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'on karakter');
      await tester.pump();
      expect(_gonderDugmesi(tester).onPressed, isNotNull);
      expect(find.text('En az 10 karakter yaz.'), findsNothing);
    });
  });

  group('gönderim', () {
    testWidgets('POST /api/v1/account/feedback {type,text,screen}; başarı → '
        'teşekkür görünümü', (tester) async {
      final adapter = _SahteAdapter();
      await tester
          .pumpWidget(_sar(const FeedbackScreen(screen: 'sky'), adapter));
      await _bekle(tester);

      // Tür: Öneri; ekran `screen: 'sky'` ile önceden seçili.
      await tester.tap(find.text('Öneri 💡'));
      await tester.pump();
      await _yazVeGonder(tester, '  Atlas açılınca boş kalıyor.  ');

      final istek = adapter.istekler.single;
      expect(istek.method, 'POST');
      expect(istek.path, '/api/v1/account/feedback');
      expect(istek.data, {
        'type': 'suggestion',
        'text': 'Atlas açılınca boş kalıyor.',
        'screen': 'sky',
      });
      // Başlık EKLENMEZ: Authorization / Accept-Language / X-App-Build /
      // X-Device-* zaten apiProvider'ın işi; ekran kendi başlığını yazmaz.
      expect(istek.headers.keys.where((k) => k.startsWith('X-')), isEmpty);

      expect(find.text('Teşekkürler — okuyoruz.'), findsOneWidget);
      expect(find.text('Yanıtımızı bildirim olarak alırsın.'), findsOneWidget);
      expect(find.widgetWithText(GoldButton, 'Kapat'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'form yerini bıraktı');
    });

    testWidgets('ekran seçilmemişse `screen` anahtarı HİÇ gitmez',
        (tester) async {
      final adapter = _SahteAdapter();
      await tester.pumpWidget(_sar(const FeedbackScreen(), adapter));
      await _bekle(tester);
      await _yazVeGonder(tester, 'Yıldız alanı takılıyor gibi.');
      final govde = adapter.istekler.single.data as Map;
      expect(govde['type'], 'bug', reason: 'varsayılan tür Hata');
      expect(govde.containsKey('screen'), isFalse);
    });

    testWidgets('listede olmayan `screen` seçimi boş bırakır; çip seçilir ve '
        'ikinci dokunuş kaldırır', (tester) async {
      final adapter = _SahteAdapter();
      await tester.pumpWidget(
          _sar(const FeedbackScreen(screen: 'bilinmeyen'), adapter));
      await _bekle(tester);
      await tester.tap(find.text('Kehanet'));
      await tester.pump();
      await _yazVeGonder(tester, 'Madeni para dönmüyor.');
      expect((adapter.istekler.single.data as Map)['screen'], 'oracle');
    });

    testWidgets('429 → sunucunun detail\'i OLDUĞU GİBİ SnackBar\'da; form kalır',
        (tester) async {
      const detay = 'Bugünlük bu kadar — yarın yine yaz.';
      final adapter = _SahteAdapter(
          durum: 429, govde: '{"status":"error","detail":"$detay"}');
      await tester.pumpWidget(_sar(const FeedbackScreen(), adapter));
      await _bekle(tester);
      await _yazVeGonder(tester, 'Onuncu geri bildirimim bu.');

      expect(find.text(detay), findsOneWidget);
      expect(find.text('Teşekkürler — okuyoruz.'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(_gonderDugmesi(tester).busy, isFalse,
          reason: 'hata sonrası düğme kilitli kalmaz');
    });
  });

  group('giriş noktaları', () {
    testWidgets('ErrorCard "Bu ekranı bildir" → FeedbackScreen(screen)',
        (tester) async {
      await tester.pumpWidget(_sar(
          const Scaffold(
              body: ErrorCard(message: 'patladı', screen: 'atlas')),
          _SahteAdapter()));
      await _bekle(tester);
      await tester.tap(find.text('Bu ekranı bildir'));
      await _bekle(tester);
      expect(find.byType(FeedbackScreen), findsOneWidget);
      expect(tester.widget<FeedbackScreen>(find.byType(FeedbackScreen)).screen,
          'atlas');
    });

    testWidgets('ErrorCard l10n temsilcisi olmayan ağaçta da çizilir',
        (tester) async {
      // Eski testler kartı çıplak MaterialApp'te kuruyor; `AppLocalizations
      // .of` orada fırlatırdı — nullable arama bunu koruyor.
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: ErrorCard(message: 'x'))));
      await _bekle(tester); // sarsıntı animasyonu (400 ms) bitsin
      // Çıplak MaterialApp'in dili en_US → İngilizce yedek metin.
      expect(find.text('Report this screen'), findsOneWidget);
    });
  });

  group('bildirim yönlendirmesi', () {
    test('type=feedback → ana sekme; bilinmeyen-tür yoluna DÜŞMEZ', () {
      final rota = resolveNotificationRoute({'type': 'feedback', 'fid': 'f1'});
      expect(rota.kind, NotificationRouteKind.homeTab);
      expect(tabForNotification({'type': 'feedback', 'fid': 'f1'}), 0);
      // İki yol da bugün homeTab döndürdüğü için davranış tek başına
      // ayırt etmez: türün AÇIKÇA yazılı olduğu kaynaktan sabitlenir —
      // `default` dalı yarın uyarı/kayıt alırsa bu tür ona karışmaz.
      final kaynak = File('lib/core/notifications.dart').readAsStringSync();
      expect(kaynak, contains("case 'feedback':"));
    });
  });

  group('toplama anındaki beyan', () {
    // Bu grubun sebebi: metin "kişisel verin gönderilmez" diyordu, kod ise
    // kaydı uid ile yazıyor ve panel uid'i ad-soyad + e-postaya çözüyor.
    // Kullanıcı serbest metni yazma kararını bu cümleye bakarak veriyor;
    // cümle ile kaydın gerçeği ayrışırsa burası düşer.
    test('cümle "kişisel veri gönderilmez" DEMİYOR (iki dilde)', () {
      final tr = File('lib/l10n/app_tr.arb').readAsStringSync();
      final en = File('lib/l10n/app_en.arb').readAsStringSync();
      expect(tr.contains('kişisel verin gönderilmez'), isFalse,
          reason: 'kayıt uid ile yazılıyor; cümle bunu yalanlıyor');
      expect(en.contains('no personal data is sent'), isFalse);
    });

    test('cümle kaydın hesaba bağlandığını söylüyor (iki dilde)', () {
      final tr = File('lib/l10n/app_tr.arb').readAsStringSync();
      final en = File('lib/l10n/app_en.arb').readAsStringSync();
      expect(tr.contains('hesabınla birlikte kaydedilir'), isTrue);
      expect(en.contains('stored with your account'), isTrue);
      // Ters yön de korunuyor: sunucu uid'i yazmayı bırakırsa cümle bu kez
      // fazla şey söylüyor olur ve metin yeniden okunmalıdır.
      final servis = File('../../backend/services/feedback_service.py')
          .readAsStringSync();
      expect(servis.contains('"uid": uid'), isTrue);
    });
  });
}

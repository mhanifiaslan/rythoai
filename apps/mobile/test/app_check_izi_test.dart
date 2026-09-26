// App Check izi bekçileri (K3-bildirim turu: U30).
//
// Zorlama açıkken App Check'in düşmesi kullanıcıya yalnız "Giriş
// yapılamadı" ya da izin hatası olarak görünüyor; yayında Crashlytics'e
// hiçbir şey gitmiyordu. iOS'ta App Attest arızası `activate()`'te değil
// ancak jeton alınırken ortaya çıkıyor — bu yüzden bir de jeton yoklaması
// var. İki değişmez: yoklama açılışı ASLA bekletmez ve ASLA fırlatmaz.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/app_check_izi.dart';

/// Satır sonu normalize edilir ve TAM SATIR yorumları atılır: yoklamayı
/// anlatan bir yorum, kodda olmayan bir çağrıyı "var" gösteremesin.
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

class _Kayit {
  final hatalar = <Object>[];
  final nedenler = <String>[];
  final izler = <StackTrace>[];

  void call(Object hata, StackTrace iz, String neden) {
    hatalar.add(hata);
    izler.add(iz);
    nedenler.add(neden);
  }
}

void main() {
  late _Kayit kayit;

  setUp(() {
    kayit = _Kayit();
    appCheckKaydedici = kayit.call;
  });

  tearDown(appCheckKaydediciyiSifirla);

  group('yoklama kimde koşar', () {
    test('yalnız iOS yayın derlemesi', () {
      expect(
          appCheckYoklamasiYapilir(
              hataAyiklama: false, web: false, platform: TargetPlatform.iOS),
          isTrue);
    });

    test('Android yayında koşmaz — Android davranışı değişmedi', () {
      expect(
          appCheckYoklamasiYapilir(
              hataAyiklama: false,
              web: false,
              platform: TargetPlatform.android),
          isFalse);
    });

    test('debug ve web koşmaz', () {
      expect(
          appCheckYoklamasiYapilir(
              hataAyiklama: true, web: false, platform: TargetPlatform.iOS),
          isFalse);
      expect(
          appCheckYoklamasiYapilir(
              hataAyiklama: false, web: true, platform: TargetPlatform.iOS),
          isFalse);
    });

    test('bu test koşusu debug: varsayılan parametreler kapalı', () {
      // kDebugMode testte true; yayın koşulu parametreyle ölçülüyor.
      expect(appCheckYoklamasiYapilir(platform: TargetPlatform.iOS), isFalse);
    });
  });

  group('jeton yoklaması', () {
    test('jeton gelirse iz yok', () async {
      await appCheckJetonunuYokla(() async => 'jeton');
      expect(kayit.hatalar, isEmpty);
    });

    test('düşen jeton, kendi hatası ve iziyle kaydedilir', () async {
      final hata = PlatformException(
          code: 'app-attest', message: 'The attestation was rejected');
      await appCheckJetonunuYokla(() async => throw hata);
      expect(kayit.hatalar, [same(hata)]);
      expect(kayit.nedenler, ['app-check-token']);
    });

    test('boş jeton da kaydedilir — istek jetonsuz giderdi', () async {
      await appCheckJetonunuYokla(() async => null);
      await appCheckJetonunuYokla(() async => '');
      expect(kayit.nedenler, ['app-check-token', 'app-check-token']);
      expect(kayit.hatalar, everyElement(isA<StateError>()));
    });

    test('kaydedici fırlatmaz; senkron fırlatan jeton çağrısı da yutulur',
        () async {
      await expectLater(
          appCheckJetonunuYokla(() => throw StateError('kanal yok')),
          completes);
      expect(kayit.nedenler, ['app-check-token']);
    });

    test('debug kanalı Crashlytics\'e dokunmaz', () async {
      // Firebase testte kurulu değil: varsayılan kanal kDebugMode'u
      // atlasaydı FirebaseCrashlytics.instance burada fırlatırdı.
      appCheckKaydediciyiSifirla();
      await expectLater(
          appCheckJetonunuYokla(() async => throw StateError('attest')),
          completes);
    });
  });

  test('etkinleştirme hatası kendi nedeniyle kaydedilir', () {
    final iz = StackTrace.current;
    appCheckEtkinlestirmeHatasi(StateError('activate'), iz);
    expect(kayit.nedenler, ['app-check-activate']);
    expect(kayit.izler.single, same(iz));
  });

  group('main.dart bağlantısı', () {
    final kaynak = _yorumsuz('lib/main.dart');

    test('activate hatası yığınıyla kaydediliyor', () {
      expect(
          kaynak,
          contains('} catch (e, iz) {\n'
              '    appCheckEtkinlestirmeHatasi(e, iz);\n'
              '  }'));
      expect(kaynak, isNot(contains("debugPrint('App Check etkinleştirilemedi")),
          reason: 'yalnız debugPrint yayında iz bırakmaz');
    });

    test('yoklama ateşle-unut: açılış beklemez', () {
      expect(
          kaynak,
          contains('if (appCheckYoklamasiYapilir()) {\n'
              '      unawaited(appCheckJetonunuYokla('
              'FirebaseAppCheck.instance.getToken));\n'
              '    }'));
      expect(kaynak, isNot(contains('await appCheckJetonunuYokla')));
    });

    test('yoklama activate\'ten SONRA, runApp\'ten ÖNCE kuruluyor', () {
      final etkinlestir = kaynak.indexOf('FirebaseAppCheck.instance.activate(');
      final yoklama = kaynak.indexOf('appCheckJetonunuYokla(');
      final uygulama = kaynak.indexOf('runApp(');
      expect(etkinlestir, greaterThan(0));
      expect(yoklama, greaterThan(etkinlestir));
      expect(uygulama, greaterThan(yoklama));
    });
  });
}

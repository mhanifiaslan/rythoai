// iOS yeniden kurulum oturumu bekçileri (U45).
//
// iOS Firebase oturumunu anahtar zincirinde tutar ve uygulama silinince
// anahtar zinciri gitmez; SharedPreferences (ve içindeki cihaz kimliği)
// gider. Yeniden kuran abone kendi eski kurulumuyla cihaz çakışmasına
// düşüyordu. Düzeltme tek seferlik bir çıkış — ve asıl tehlike onun
// TEKRARLAMASI: işaret yazılmazsa her açılış kullanıcıyı çıkarırdı; eski
// sürümden güncelleyen kullanıcıyı çıkarmak da aynı derecede yanlış olurdu.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/device_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cikis {
  int sayi = 0;
  Future<void> call() async => sayi++;
}

Future<bool> _calistir(_Cikis cikis, {bool oturum = true}) =>
    iosYenidenKurulumOturumunuKapat(
        oturumVar: () => oturum, cikis: cikis.call);

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('yeniden kurulum (boş depo + oturum): bir kez çıkış', () async {
      SharedPreferences.setMockInitialValues({});
      final cikis = _Cikis();
      expect(await _calistir(cikis), isTrue);
      expect(cikis.sayi, 1);
    });

    test('ikinci açılışta TEKRAR çıkış yok — işaret yazıldı', () async {
      SharedPreferences.setMockInitialValues({});
      final cikis = _Cikis();
      await _calistir(cikis);
      // Kullanıcı yeniden giriş yaptı; bir sonraki açılış.
      expect(await _calistir(cikis), isFalse);
      expect(await _calistir(cikis), isFalse);
      expect(cikis.sayi, 1);
    });

    test('işaretten ÖNCEKİ sürümden güncelleyen kullanıcı çıkarılmaz',
        () async {
      // Deposu sağlam: cihaz kimliği ve dil tercihi duruyor.
      SharedPreferences.setMockInitialValues({
        'rythoDeviceId': '0123456789abcdef0123456789abcdef',
        'locale': 'tr',
      });
      final cikis = _Cikis();
      expect(await _calistir(cikis), isFalse);
      expect(cikis.sayi, 0);
      // İşaret yine de yazıldı: denetim bir daha koşmaz.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('rythoKurulumGoruldu'), isTrue);
    });

    test('ilk kurulum, oturum yok: çıkış yok, sonraki girişler korunur',
        () async {
      SharedPreferences.setMockInitialValues({});
      final cikis = _Cikis();
      expect(await _calistir(cikis, oturum: false), isFalse);
      // Kullanıcı ilk açılışta giriş yaptı; ikinci açılışta oturum var.
      expect(await _calistir(cikis), isFalse);
      expect(cikis.sayi, 0);
    });

    test('çıkış fırlatsa da açılış düşmez ve tekrar denenmez', () async {
      SharedPreferences.setMockInitialValues({});
      var deneme = 0;
      Future<void> bozukCikis() async {
        deneme++;
        throw StateError('keychain');
      }

      expect(
          await iosYenidenKurulumOturumunuKapat(
              oturumVar: () => true, cikis: bozukCikis),
          isFalse);
      expect(
          await iosYenidenKurulumOturumunuKapat(
              oturumVar: () => true, cikis: bozukCikis),
          isFalse);
      expect(deneme, 1);
    });
  });

  test('Android: ne çıkış ne depo yazımı', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final cikis = _Cikis();
    expect(await _calistir(cikis), isFalse);
    expect(cikis.sayi, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty, reason: 'Android deposuna dokunuldu');
  });
}

// App Check izi bekçileri (K3-bildirim turu: U30).
//
// Zorlama açıkken App Check'in düşmesi kullanıcıya yalnız genel "Bir
// şeyler ters gitti" (`authFailed`; simülatörde ölçüldü 2026-10-24) ya da
// izin hatası olarak görünüyor; yayında Crashlytics'e hiçbir şey
// gitmiyordu. iOS'ta App Attest arızası `activate()`'te değil ancak jeton
// alınırken ortaya çıkıyor — bu yüzden bir de jeton yoklaması var. İki
// değişmez: yoklama açılışı ASLA bekletmez ve ASLA fırlatmaz.
//
// Sağlayıcı seçimi de burada çivili ('yayın dalı' testleri, iki platform):
// yayın dalı App Attest / Play Integrity'den başka bir sağlayıcıya dönerse
// simülatör, emülatör ve Debug bunu GÖSTERMEZ (hepsi debug sağlayıcıda);
// kusur ilk Profile/Release cihaz derlemesinde, en geç mağaza paketinde
// görünür.
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

/// [cagri] (açılış parantezi dahil, ör. `activate(`) ile başlayan İLK
/// çağrının [ad] adlı argümanı, boşlukları atılmış hâlde; yoksa `null`.
///
/// Argümanlar parantez/köşeli/süslü DERİNLİĞİ sayılarak bölünür: iç içe
/// bir çağrının aynı adlı argümanı ya da çağrının DIŞINDAKİ bir metin
/// eşleşmeye karışmasın. Dizeler ayrıştırılmaz (bu çağrıda dize yok):
/// dengesiz parantezli bir dize bölmeyi bozar ve argüman bulunamaz — bekçi
/// sessizce yeşil kalmaz, kırmızıya döner.
String? _adliArguman(String kaynak, String cagri, String ad) {
  final bas = kaynak.indexOf(cagri);
  if (bas < 0) return null;
  final argumanlar = <String>[];
  var derinlik = 0;
  var parca = StringBuffer();
  for (var i = bas + cagri.length; i < kaynak.length; i++) {
    final c = kaynak[i];
    if (c == '(' || c == '[' || c == '{') derinlik++;
    if (c == ')' || c == ']' || c == '}') {
      if (derinlik == 0) {
        argumanlar.add(parca.toString());
        break;
      }
      derinlik--;
    }
    if (c == ',' && derinlik == 0) {
      argumanlar.add(parca.toString());
      parca = StringBuffer();
      continue;
    }
    parca.write(c);
  }
  for (final a in argumanlar) {
    final s = a.replaceAll(RegExp(r'\s'), '');
    if (s.startsWith('$ad:')) return s.substring(ad.length + 1);
  }
  return null;
}

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

    // Neden kaynak bekçisi: yayın dalı yalnız `kDebugMode == false` iken
    // koşar; testte, simülatörde ve Debug cihazda HİÇ koşmaz. Dal
    // `AppleDeviceCheckProvider`'a dönse (ya da `providerApple` silinip
    // paket varsayılanı DeviceCheck'e düşse) yayın paketi Firebase'den
    // DeviceCheck kanıtıyla jeton ister; kurulum planı yalnız App Attest'i
    // kaydediyor (docs/mac-devir.md §4; DeviceCheck kaydı kendi .p8
    // anahtarını ister ve planda yok — konsol durumu depodan ölçülemez).
    // Kayıtsız sağlayıcıyla jeton alınamaz ve zorlanan üç servis iOS'u
    // reddeder — bunu gösteren ilk yer cihazdaki Profile/Release derlemesi
    // (`kDebugMode` orada da false), en geç TestFlight.
    // `providerApple` tamamen silinirse Debug da DeviceCheck'e düşer ve
    // simülatörde görünür; görünmeyen tek hâl yayın dalının değişmesi.
    //
    // Yayın dalı TAM eşitlikle çivilenir, desenle değil: ilk sürümün
    // `AppleDebugProvider\(.*\)` deseni açgözlüydü ve yayın dalına konan
    // İÇ İÇE bir üçlüyü (`… : kReleaseMode ? const
    // AppleDeviceCheckProvider() : const AppleAppAttestProvider()`) de
    // yutup yeşil kalıyordu — TestFlight/App Store DeviceCheck'e döner,
    // Profile App Attest'te kalırdı (çürütme turu, 2026-10-24).
    test('Apple yayın dalı App Attest, debug dalı debug sağlayıcı', () {
      final ifade = _adliArguman(
          kaynak, 'FirebaseAppCheck.instance.activate(', 'providerApple');
      expect(ifade, isNotNull,
          reason: 'activate çağrısında providerApple yok: paket sessizce '
              'AppleDeviceCheckProvider kullanır (firebase_app_check '
              '0.4.5+2, firebase_app_check.dart:110)');
      final dallar = _ucluDallar(ifade!);
      expect(dallar, isNotNull, reason: 'providerApple üçlü değil: $ifade');
      expect(dallar!.kosul, 'kDebugMode', reason: ifade);
      // Dallar ters çevrilirse yayın paketi debug sağlayıcıyla çıkar ve
      // define dosyasındaki KAYITLI sabit jeton pakete girer: Firebase onu
      // reddetmez, jetonu bulan herkes App Check'i aşar. `infra/build-ipa.sh`
      // `paket-appcheck-jetonu-yok` kapısı bunu pakette yakalar, düz
      // `flutter build ipa` yakalamaz — bu test daha erken yakalar.
      expect(_tekCagri(dallar.dogru, 'AppleDebugProvider('), isTrue,
          reason: 'debug dalı tek bir AppleDebugProvider(...) değil: '
              '${dallar.dogru}');
      expect(dallar.yanlis, 'constAppleAppAttestProvider()',
          reason: 'yayın dalı tam olarak const AppleAppAttestProvider() '
              'olmalı: ${dallar.yanlis}');
    });

    // Aynı boşluk Android'de de vardı ve canlı platform o: yayın dalı
    // Play Integrity'den başka bir sağlayıcıya dönse Debug ve emülatör
    // bunu göstermez (ikisi de debug sağlayıcıda); kusur ancak Play'den
    // kurulan pakette görünür ve zorlanan üç servis Android'i de reddeder.
    test('Android yayın dalı Play Integrity, debug dalı debug sağlayıcı', () {
      final ifade = _adliArguman(
          kaynak, 'FirebaseAppCheck.instance.activate(', 'providerAndroid');
      expect(ifade, isNotNull,
          reason: 'activate çağrısında providerAndroid yok');
      final dallar = _ucluDallar(ifade!);
      expect(dallar, isNotNull, reason: 'providerAndroid üçlü değil: $ifade');
      expect(dallar!.kosul, 'kDebugMode', reason: ifade);
      expect(dallar.dogru, 'constAndroidDebugProvider()', reason: ifade);
      expect(dallar.yanlis, 'constAndroidPlayIntegrityProvider()',
          reason: 'yayın dalı tam olarak const AndroidPlayIntegrityProvider() '
              'olmalı: ${dallar.yanlis}');
    });

    // Ayrıştırıcının kendi tuzakları: bekçi kör olmasın.
    test('üçlü ayrıştırıcı iç içe üçlüyü ve ?? / ?. işlecini doğru böler',
        () {
      final d = _ucluDallar('kDebugMode?A(x?y:z):kReleaseMode?B():C()')!;
      expect(d.kosul, 'kDebugMode');
      expect(d.dogru, 'A(x?y:z)');
      expect(d.yanlis, 'kReleaseMode?B():C()',
          reason: 'yayın dalındaki iç içe üçlü bütün kalmalı ki tam eşitlik '
              'onu reddetsin');
      final n = _ucluDallar('a??b?c?.d:e')!;
      expect(n.kosul, 'a??b');
      expect(n.dogru, 'c?.d');
      expect(n.yanlis, 'e');
      expect(_ucluDallar('constAppleAppAttestProvider()'), isNull);
      expect(_tekCagri('AppleDebugProvider(debugToken:a?null:a)',
          'AppleDebugProvider('), isTrue);
      expect(_tekCagri('AppleDebugProvider()??X()', 'AppleDebugProvider('),
          isFalse);
    });
  });
}

/// Boşlukları atılmış bir üçlü ifadeyi DERİNLİK 0'daki `?` ve onun eşi
/// olan `:` noktasından böler; üçlü değilse `null`. `??` ve `?.` üçlü
/// sayılmaz; doğru daldaki iç içe üçlüler `?`/`:` sayacıyla atlanır, yanlış
/// dal ise ilk eşleşen `:`'den sonrasının TAMAMIDIR — yayın dalına konan iç
/// içe bir üçlü bütün kalır ve tam eşitlik onu reddeder.
({String kosul, String dogru, String yanlis})? _ucluDallar(String s) {
  var derinlik = 0;
  var soru = -1;
  var bekleyen = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '(' || c == '[' || c == '{') derinlik++;
    if (c == ')' || c == ']' || c == '}') derinlik--;
    if (derinlik != 0) continue;
    if (c == '?') {
      final sonraki = i + 1 < s.length ? s[i + 1] : '';
      final onceki = i > 0 ? s[i - 1] : '';
      if (sonraki == '?' || sonraki == '.' || onceki == '?') continue;
      if (soru < 0) {
        soru = i;
      } else {
        bekleyen++;
      }
    } else if (c == ':' && soru >= 0) {
      if (bekleyen > 0) {
        bekleyen--;
      } else {
        return (
          kosul: s.substring(0, soru),
          dogru: s.substring(soru + 1, i),
          yanlis: s.substring(i + 1),
        );
      }
    }
  }
  return null;
}

/// [ifade] tam olarak TEK bir `[cagri]...)` çağrısı mı: açılış parantezinin
/// eşi ifadenin son karakteri olmalı (ardında `?? X()` gibi bir kuyruk
/// kalmasın).
bool _tekCagri(String ifade, String cagri) {
  if (!ifade.startsWith(cagri)) return false;
  var derinlik = 0;
  for (var i = cagri.length - 1; i < ifade.length; i++) {
    final c = ifade[i];
    if (c == '(' || c == '[' || c == '{') derinlik++;
    if (c == ')' || c == ']' || c == '}') {
      derinlik--;
      if (derinlik == 0) return i == ifade.length - 1;
    }
  }
  return false;
}

// Yapay zeka onayı GERÇEK istemci zincirinde kapı değil (sahip kararı
// 2026-10-22: hiçbir özellik onaya kapılı değil).
//
// `ai_onay_test.dart` aynı şeyi `apiProvider`ı sade bir Dio ile ezerek
// ölçüyor; o ölçüm interceptor zincirini HİÇ koşturmaz. Onay kapısı en
// kolay oraya konurdu — `apiProvider` her isteğin geçtiği tek boğaz ve
// zincirin parçaları başka dosyalardan geliyor (`app_config`,
// `device_session`), yani api.dart'a bakan kaynak bekçisi o dosyalara
// konan bir kapıyı görmez. Burada `apiProvider` kendi interceptor'larıyla
// kurulur, yalnız ağ bağdaştırıcısı (`httpClientAdapter`) sahtedir:
// istek bağdaştırıcıya ULAŞIYORSA hiçbir halka onu durdurmamıştır.
//
// Onaysız hâl: SharedPreferences boş (kurulumda borçlanmış bayrak yok),
// sunucuda kayıt yok — 1.20.0+53'ten gelen kullanıcının hâli.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
// firebase_core'un KENDİ platform arayüzünün test yardımcısı: zincirin
// kimlik halkası `FirebaseAuth.instance.currentUser` okuyor ve Firebase
// kurulmadan o satır istisna atar. Pubspec'e ayrı bağımlılık olarak
// yazılmadı: sürümünü firebase_core sabitliyor, ikinci bir kısıt
// firebase_core yükseltmesinde çözümlemeyi kilitleyebilirdi.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/app_config.dart' show kAppBuildHeader;
import 'package:rytho/core/device_session.dart' show kDevicePlatformHeader;
import 'package:rytho/core/providers.dart'
    show PlusHali, dailyReadingProvider, profileProvider, raporKapisiProvider;
import 'package:shared_preferences/shared_preferences.dart';

const _onayYolu = '/api/v1/account/ai-consent';

/// İstekleri kaydeden sahte ağ; gövde yola göre [govdeler]den, yoksa `{}`.
class _Ag implements HttpClientAdapter {
  _Ag([this.govdeler = const {}]);

  final Map<String, Object> govdeler;
  final List<RequestOptions> istekler = [];

  List<RequestOptions> yola(String yol) =>
      istekler.where((i) => i.path == yol).toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istekler.add(options);
    var govde = '{}';
    for (final e in govdeler.entries) {
      if (options.path.contains(e.key)) govde = jsonEncode(e.value);
    }
    return ResponseBody.fromString(govde, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Derleme numarası da gerçek sağlayıcıdan (`appBuildProvider`) okunur;
    // test ortamında eklenti kanalı yok, değer buradan gelir ve başlıkta
    // ölçülür.
    PackageInfo.setMockInitialValues(
      appName: 'Rytho',
      packageName: 'ai.rytho',
      version: '1.20.0',
      buildNumber: '54',
      buildSignature: '',
    );
  });

  /// GERÇEK `apiProvider`; ezilen yalnız aboneliğin ve profilin kaynağı
  /// (Firestore ve RevenueCat ağı), zincirin hiçbir halkası değil.
  (ProviderContainer, Dio, _Ag) kur(_Ag ag) {
    final k = ProviderContainer(overrides: [
      raporKapisiProvider.overrideWithValue(PlusHali.abone),
      profileProvider.overrideWith((ref) => Stream.value({
            'onboardingCompleted': true,
            'birthDate': '1990-03-07',
            'birthTime': '04:30',
            'birthCity': 'İstanbul',
          })),
    ]);
    addTearDown(k.dispose);
    final dio = k.read(apiProvider)..httpClientAdapter = ag;
    return (k, dio, ag);
  }

  /// Zincirin gerçekten koştuğunun izi: her halka kendi başlığını koydu.
  /// İz olmasaydı "istek gitti" ölçümü zinciri atlayan bir yoldan da
  /// geçebilirdi.
  void zincirdenGecti(RequestOptions istek) {
    expect(istek.headers[kAppBuildHeader], '54');
    expect(istek.headers['X-Device-Id'], isA<String>());
    expect(istek.headers[kDevicePlatformHeader], isA<String>());
    expect(istek.headers['Accept-Language'], isA<String>());
  }

  test('günlük okuma gerçek zincirden onaysız ağa ÇIKAR ve okuma döner',
      () async {
    final (k, _, ag) = kur(_Ag({
      '/reports/daily': {
        'data': {'reading': 'Bugün gökyüzü sakin.'},
      },
    }));
    k.listen(profileProvider, (_, _) {});
    await k.read(profileProvider.future);
    k.listen(dailyReadingProvider, (_, _) {});
    final veri = await k.read(dailyReadingProvider.future);

    expect(veri?['reading'], 'Bugün gökyüzü sakin.');
    final gunluk = ag.yola('/api/v1/reports/daily');
    expect(gunluk, hasLength(1));
    zincirdenGecti(gunluk.single);
    expect(ag.yola(_onayYolu), isEmpty,
        reason: 'zincir onay durumunu sormaz');
  });

  test('sohbet isteği gerçek zincirden onaysız ağa ÇIKAR', () async {
    final (_, dio, ag) = kur(_Ag({
      '/chat': {'reply': 'Merhaba.'},
    }));
    final yanit = await dio.post('/api/v1/chat',
        data: {'history': <Object>[], 'message': 'Merhaba'});

    expect(yanit.statusCode, 200);
    expect(yanit.data, {'reply': 'Merhaba.'});
    final sohbet = ag.yola('/api/v1/chat');
    expect(sohbet, hasLength(1));
    zincirdenGecti(sohbet.single);
    expect(ag.istekler, hasLength(1),
        reason: 'zincir araya başka bir istek (onay sorgusu) sokmaz');
  });
}

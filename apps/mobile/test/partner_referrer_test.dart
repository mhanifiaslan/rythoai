// Ortaklık atfı — istemci yarısı bekçileri (OP11-OP12).
//
// Zincir İKİ yoldan aynı uca çıkıyor ve ikisi de sessizce bozulabilir:
//
//   1. KURULUM: ortak linki → tarayıcı (`web/r/index.html`) → Play
//      `&referrer=` → Install Referrer → POST /billing/redeem-code
//   2. KURULU UYGULAMA: ortak linki → App Links (`/r/` intent-filter) →
//      POST /billing/redeem-code
//
// Burada sabitlenenler: kod deseni, `/r/` ile `/i/` yollarının birbirini
// YUTMAMASI, tek-gönderim garantisi ve hangi hatanın TERMİNAL hangisinin
// ERTELENEBİLİR olduğu. Son madde en kırılganı: 409 terminal sayılmazsa
// atfı olan her kullanıcı her açılışta çöp istek atar; 401 terminal
// sayılırsa giriş yaptıktan sonraki meşru deneme sessizce ölür.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/deep_links.dart';
import 'package:rytho/core/partner_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bayrak adı BİLEREK literal: `partner_referrer.dart`'ta özel (private) ve
/// SÜRÜMSÜZ. Bir gün sürümlenirse bu test düşer — düşmesi gerekir, çünkü
/// sürüm artışı sahadaki herkesin kullanılmış kodunu yeniden göndermesine
/// ve 409 seline yol açar.
const _kBayrak = 'partner-referrer-islendi';

/// `play_install_referrer` eklentisinin kanalı (paketin kendi sabiti).
const _kKanal = 'com.chunkytofustudios.play_install_referrer';

const _kUc = '/api/v1/billing/redeem-code';

class _SahteAdapter implements HttpClientAdapter {
  _SahteAdapter({this.durum = 200, this.govde = '{"status":"ok"}'});

  final int durum;
  final String govde;
  final List<RequestOptions> istekler = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istekler.add(options);
    return ResponseBody.fromString(govde, durum, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_SahteAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
  dio.httpClientAdapter = adapter;
  return dio;
}

Future<bool?> _bayrak() async =>
    (await SharedPreferences.getInstance()).getBool(_kBayrak);

/// Eklentinin döndürdüğü yükün tam şekli — alanlardan biri eksik ya da
/// `null` olursa `ReferrerDetails` kurucusu tip hatasıyla düşer.
Map<String, Object?> _referrerYuku(String? ham) => <String, Object?>{
      'installReferrer': ham,
      'referrerClickTimestampSeconds': 0,
      'installBeginTimestampSeconds': 0,
      'referrerClickTimestampServerSeconds': 0,
      'installBeginTimestampServerSeconds': 0,
      'installVersion': '1.16.0',
      'googlePlayInstantParam': false,
    };

void _kanaliKur(Future<Object?> Function() yanit) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel(_kKanal), (_) async => yanit());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(_kKanal), null);
  });

  group('kod deseni ve referrer ayıklama', () {
    test('desen backend ve sayfayla aynı sözleşmeyi taşır', () {
      // 4-24, BÜYÜK harf + rakam + alt çizgi + tire. Dördüncü kopya
      // `web/r/index.html`'de; onu backend'e bağlayan bekçi
      // backend/tests/test_web_seo.py.
      expect(kOrtakKodDeseni.pattern, r'^[A-Z0-9_-]{4,24}$');
      expect(kOrtakKodDeseni.hasMatch('ORTAK123'), isTrue);
      expect(kOrtakKodDeseni.hasMatch('AB-CD_1'), isTrue);
      expect(kOrtakKodDeseni.hasMatch('ABC'), isFalse);
      expect(kOrtakKodDeseni.hasMatch('A' * 25), isFalse);
      expect(kOrtakKodDeseni.hasMatch('ortak123'), isFalse);
      expect(kOrtakKodDeseni.hasMatch('ORTAK 123'), isFalse);
    });

    test('sayfanın ürettiği referrer dizesinden kodu çıkarır', () {
      expect(
        ortakKodunuAyikla('utm_source=rytho_partner&utm_medium=affiliate'
            '&utm_campaign=ORTAK123'),
        'ORTAK123',
      );
    });

    test('organik kurulumda kod YOK', () {
      // Play'in kendi dizesi. Bu TERMİNAL bir cevap — aşağıdaki
      // `ensurePartnerReferrer` testi bayrağın yazıldığını sabitler.
      expect(
        ortakKodunuAyikla('utm_source=google-play&utm_medium=organic'),
        isNull,
      );
    });

    test('küçük harf gelen kod büyütülür, yüzde kodlaması çözülür', () {
      expect(ortakKodunuAyikla('utm_campaign=ortak123'), 'ORTAK123');
      expect(ortakKodunuAyikla('utm_campaign=AB%2DCD'), 'AB-CD');
    });

    test('boş, bozuk ve desene uymayan girdiler null', () {
      expect(ortakKodunuAyikla(null), isNull);
      expect(ortakKodunuAyikla(''), isNull);
      expect(ortakKodunuAyikla('utm_campaign='), isNull);
      expect(ortakKodunuAyikla('utm_campaign=ABC'), isNull);
      expect(ortakKodunuAyikla('utm_campaign=abc!def'), isNull);
      expect(ortakKodunuAyikla('kod=ORTAK123'), isNull);
    });
  });

  group('bağlantı ayrıştırma: /r/ ile /i/ birbirini yutmaz', () {
    test('ortak bağlantısından kod çıkar', () {
      expect(partnerCodeFromLink(Uri.parse('https://rytho.app/r/ORTAK123')),
          'ORTAK123');
      expect(partnerCodeFromLink(Uri.parse('https://rytho.app/r/ortak123')),
          'ORTAK123');
    });

    test('eski Firebase adresi de çözülür', () {
      expect(
          partnerCodeFromLink(
              Uri.parse('https://rhytoai.web.app/r/ORTAK123')),
          'ORTAK123');
    });

    test('davet bağlantısı ortak SAYILMAZ', () {
      expect(partnerCodeFromLink(Uri.parse('https://rytho.app/i/mhaslan')),
          isNull);
    });

    test('ortak bağlantısı davet SAYILMAZ', () {
      // Çift yönlü bekçi: iki ayrıştırıcı aynı host kümesini paylaşıyor,
      // biri gevşerse diğerinin yolunu sessizce yutar.
      expect(
          usernameFromInviteLink(Uri.parse('https://rytho.app/r/ORTAK123')),
          isNull);
    });

    test('yabancı host, eksik ve geçersiz kod null', () {
      expect(partnerCodeFromLink(Uri.parse('https://example.com/r/ORTAK123')),
          isNull);
      expect(partnerCodeFromLink(Uri.parse('https://rytho.app/r/')), isNull);
      expect(partnerCodeFromLink(Uri.parse('https://rytho.app/r/abc!')),
          isNull);
    });
  });

  group('applyPartnerCode (kurulu uygulama yolu)', () {
    test('kodu uca gönderir ve bayrağı yazar', () async {
      SharedPreferences.setMockInitialValues({});
      final adapter = _SahteAdapter();
      await applyPartnerCode(_dio(adapter), 'ortak123');

      final istek = adapter.istekler.single;
      expect(istek.method, 'POST');
      expect(istek.path, _kUc);
      // Sunucu deseni büyük harf bekliyor — normalizasyon istemcide.
      expect((istek.data as Map)['code'], 'ORTAK123');
      expect(await _bayrak(), isTrue);
    });

    test('geçersiz kod ne istek atar ne bayrak yakar', () async {
      // Bayrağı yakmak burada zararlı olurdu: bozuk bir linke dokunmak,
      // sonraki GEÇERLİ linki de sessizce öldürürdü.
      SharedPreferences.setMockInitialValues({});
      final adapter = _SahteAdapter();
      await applyPartnerCode(_dio(adapter), 'abc');
      expect(adapter.istekler, isEmpty);
      expect(await _bayrak(), isNull);
    });

    test('ikinci çağrı no-op: bayrak varsa istek atılmaz', () async {
      SharedPreferences.setMockInitialValues({_kBayrak: true});
      final adapter = _SahteAdapter();
      await applyPartnerCode(_dio(adapter), 'ORTAK123');
      expect(adapter.istekler, isEmpty);
    });

    test('409 already_redeemed TERMİNAL: bayrak yazılır', () async {
      SharedPreferences.setMockInitialValues({});
      final adapter = _SahteAdapter(
          durum: 409, govde: '{"code":"already_redeemed"}');
      await applyPartnerCode(_dio(adapter), 'ORTAK123');
      expect(adapter.istekler, hasLength(1));
      // `consent.dart` deseni burada kopyalanırsa bu iddia düşer ve
      // sahada her açılışta bir çöp 409 isteği başlar.
      expect(await _bayrak(), isTrue);
    });

    test('401 ERTELENEBİLİR: oturum açılınca yeniden denenir', () async {
      SharedPreferences.setMockInitialValues({});
      final adapter =
          _SahteAdapter(durum: 401, govde: '{"detail":"unauthorized"}');
      await applyPartnerCode(_dio(adapter), 'ORTAK123');
      expect(adapter.istekler, hasLength(1));
      expect(await _bayrak(), isNull);
    });

    test('5xx ERTELENEBİLİR', () async {
      SharedPreferences.setMockInitialValues({});
      final adapter = _SahteAdapter(durum: 503, govde: '{"detail":"x"}');
      await applyPartnerCode(_dio(adapter), 'ORTAK123');
      expect(await _bayrak(), isNull);
    });
  });

  group('ensurePartnerReferrer (kurulum yolu)', () {
    test('Android DIŞINDA hiç çalışmaz', () async {
      // iOS'ta Install Referrer'ın dengi YOK; eklenti orada fırlatıyor.
      // Kapı platformda: bayrak bile okunmaz.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      SharedPreferences.setMockInitialValues({});
      final adapter = _SahteAdapter();
      var kanalCagrisi = 0;
      _kanaliKur(() async {
        kanalCagrisi++;
        return _referrerYuku('utm_campaign=ORTAK123');
      });

      await ensurePartnerReferrer(_dio(adapter));

      expect(kanalCagrisi, 0);
      expect(adapter.istekler, isEmpty);
      expect(await _bayrak(), isNull);
    });

    test('referrer kod taşıyorsa gönderir ve bayrağı yazar', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      final adapter = _SahteAdapter();
      _kanaliKur(() async => _referrerYuku(
          'utm_source=rytho_partner&utm_medium=affiliate'
          '&utm_campaign=ORTAK123'));

      await ensurePartnerReferrer(_dio(adapter));

      expect((adapter.istekler.single.data as Map)['code'], 'ORTAK123');
      expect(await _bayrak(), isTrue);
    });

    test('organik kurulum: istek YOK ama bayrak yazılır', () async {
      // Referrer okundu ve içinde kod yok — bu TERMİNAL bir cevap.
      // Bayrak yazılmazsa organik kuran herkes her açılışta eklentiyi
      // yeniden yoklar.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      final adapter = _SahteAdapter();
      _kanaliKur(
          () async => _referrerYuku('utm_source=google-play&utm_medium=organic'));

      await ensurePartnerReferrer(_dio(adapter));

      expect(adapter.istekler, isEmpty);
      expect(await _bayrak(), isTrue);
    });

    test('eklenti/Play Services hazır değilse bayrak YAZILMAZ', () async {
      // Geçici hata: bir sonraki açılış yeniden dener. Bayrağı yakmak
      // atfı kalıcı olarak kaybettirirdi.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      final adapter = _SahteAdapter();
      _kanaliKur(() async =>
          throw PlatformException(code: 'FEATURE_NOT_SUPPORTED'));

      await ensurePartnerReferrer(_dio(adapter));

      expect(adapter.istekler, isEmpty);
      expect(await _bayrak(), isNull);
    });

    test('bayrak varsa eklenti hiç yoklanmaz', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({_kBayrak: true});
      final adapter = _SahteAdapter();
      var kanalCagrisi = 0;
      _kanaliKur(() async {
        kanalCagrisi++;
        return _referrerYuku('utm_campaign=ORTAK123');
      });

      await ensurePartnerReferrer(_dio(adapter));

      expect(kanalCagrisi, 0);
      expect(adapter.istekler, isEmpty);
    });
  });
}

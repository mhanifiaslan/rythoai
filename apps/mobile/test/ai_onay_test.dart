import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/ai_consent.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/providers.dart'
    show
        PlusHali,
        dailyReadingProvider,
        profileProvider,
        raporKapisiProvider,
        signalsDataProvider;
import 'package:rytho/features/onboarding/onboarding_wizard.dart';
import 'package:rytho/features/profile/legal_texts.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_en.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:shared_preferences/shared_preferences.dart';

/// Yapay zeka (Google Gemini) aktarım onayı — sahip kararı 2026-10-22.
///
/// Korunan değişmezler:
///
/// 1. Onay YALNIZ kurulumun ilk adımında, şartlar kutusunun altındaki AYRI
///    ve zorunlu ikinci kutuyla alınır; iki kutu işaretlenmeden "Devam"
///    açılmaz, biri yetmez.
/// 2. Kurulum bitince kanıt (`POST /account/ai-consent`) bir kez gider;
///    düşerse AppShell açılışında yeniden denenir, başarıdan sonra bir daha
///    gitmez.
/// 3. Kutuyu hiç görmemiş kullanıcı (1.20.0+53'ten güncelleyen) HİÇ istek
///    atmaz — adına kayıt yazılmaz. Bayrak hesaba bağlı: aynı cihazdaki
///    başka bir hesap onu kullanamaz.
/// 4. Kurulum dışında hiçbir yerde sorulmaz ve hiçbir özellik onaya kapılı
///    değil: onay kaydı ya da sağlayıcısı olmadan günlük okuma ve sinyal
///    istekleri gider, sohbet gönderimi kapısız.

final _tr = AppLocalizationsTr();
final _en = AppLocalizationsEn();

const _onayYolu = '/api/v1/account/ai-consent';

/// İstekleri kaydeden sahte sunucu. [durumlar] sıradaki isteklerin durum
/// kodları (tükenince 200); gövde yola göre [govdeler]den, yoksa `{}`.
class _Sunucu implements HttpClientAdapter {
  _Sunucu({List<int>? durumlar, Map<String, Object>? govdeler})
      : _durumlar = [...?durumlar],
        _govdeler = govdeler ?? const {};

  final List<int> _durumlar;
  final Map<String, Object> _govdeler;
  final List<RequestOptions> istekler = [];

  List<RequestOptions> yola(String yol) =>
      istekler.where((i) => i.path == yol).toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istekler.add(options);
    final durum = _durumlar.isEmpty ? 200 : _durumlar.removeAt(0);
    var govde = '{}';
    for (final e in _govdeler.entries) {
      if (options.path.contains(e.key)) govde = jsonEncode(e.value);
    }
    return ResponseBody.fromString(govde, durum, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Sunucu sunucu) =>
    Dio(BaseOptions(baseUrl: 'https://test.invalid'))
      ..httpClientAdapter = sunucu;

/// Kaynak bekçileri kendi açıklama yorumlarına takılmasın (CLAUDE.md §5:
/// bir şeyin YOKLUĞUNU arayan bekçi onu anlatan yorumu görmemeli).
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Iterable<String> _libDosyalari() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f.path.replaceAll(r'\', '/'))
    .where((p) => p.endsWith('.dart') && !p.contains('/l10n/'));

/// [bas] imzasından [son] imzasına kadarki kaynak dilimi.
String _dilim(String kaynak, String bas, String son) {
  final i = kaynak.indexOf(bas);
  expect(i, greaterThan(-1), reason: '$bas bulunamadı');
  final j = kaynak.indexOf(son, i);
  expect(j, greaterThan(i), reason: '$son, $bas\'tan sonra olmalı');
  return kaynak.substring(i, j);
}

Widget _sihirbaz() => ProviderScope(
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildRythoTheme(),
        // Takımyıldız nabzı sonsuz animatör; ölçülen şey kapının kuralı.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const OnboardingWizard(),
      ),
    );

bool _devamAcik(WidgetTester tester) =>
    tester.widget<GoldButton>(find.byType(GoldButton)).onPressed != null;

Future<void> _kutu(WidgetTester tester, int i) async {
  final hedef = find.byType(Checkbox).at(i);
  await tester.ensureVisible(hedef);
  await tester.pump();
  await tester.tap(hedef);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Kurulum: iki ayrı zorunlu kutu', () {
    testWidgets('iki kutu işaretlenmeden Devam kapalı; biri yetmez',
        (tester) async {
      await tester.pumpWidget(_sihirbaz());
      await tester.pump();

      expect(find.byType(Checkbox), findsNWidgets(2),
          reason: 'yapay zeka onayı şartlar kutusundan AYRI bir kutu');
      expect(find.text(_tr.wizardConsentLabel), findsOneWidget);
      expect(find.text(_tr.wizardAiConsentLabel), findsOneWidget);
      // Şartlar kutusunun ALTINDA.
      expect(tester.getTopLeft(find.text(_tr.wizardAiConsentLabel)).dy,
          greaterThan(tester.getTopLeft(find.text(_tr.wizardConsentLabel)).dy));
      expect(_devamAcik(tester), isFalse);

      await _kutu(tester, 0);
      expect(_devamAcik(tester), isFalse, reason: 'yalnız şartlar yetmez');

      await _kutu(tester, 0);
      await _kutu(tester, 1);
      expect(_devamAcik(tester), isFalse, reason: 'yalnız yapay zeka yetmez');

      await _kutu(tester, 0);
      expect(_devamAcik(tester), isTrue);

      // Biri geri alınınca kapı yeniden kapanır.
      await _kutu(tester, 1);
      expect(_devamAcik(tester), isFalse);
    });

    testWidgets('onay bir kez sorulur: sonraki adımda kutu yok',
        (tester) async {
      await tester.pumpWidget(_sihirbaz());
      await tester.pump();
      await _kutu(tester, 0);
      await _kutu(tester, 1);
      await tester.tap(find.byType(GoldButton));
      await tester.pump();
      await tester.pump();
      expect(find.text(_tr.wizardDateTitle), findsOneWidget);
      expect(find.text(_tr.wizardAiConsentLabel), findsNothing);
    });

    test('kutu metni sahibin cümlesi, birebir (TR + EN)', () {
      expect(
          _tr.wizardAiConsentLabel,
          "Yorumlarımın ve sohbet yanıtlarımın üretilmesi için harita "
          "bilgilerimin, mesajlarımın ve paylaştığım diğer verilerin Google "
          "Gemini'ye (üçüncü taraf yapay zeka) gönderilmesine izin "
          'veriyorum.');
      expect(
          _en.wizardAiConsentLabel,
          'I allow my chart data, messages and other data I share to be '
          'sent to Google Gemini (third-party AI) so my readings and chat '
          'replies can be generated.');
    });
  });

  group('Kayıt: kurulumda bir kez, düşerse AppShell yeniden dener', () {
    test('kurulum bitince POST /account/ai-consent BİR KEZ, sürümle',
        () async {
      final sunucu = _Sunucu();
      await aiOnayiKurulumdaVerildi(_dio(sunucu), uid: 'u1');

      expect(sunucu.istekler, hasLength(1));
      final istek = sunucu.istekler.single;
      expect(istek.method, 'POST');
      expect(istek.path, _onayYolu);
      expect(istek.data, {'version': kAiConsentVersion});

      // Sonraki açılış (AppShell): kayıt yerinde, bir daha ağa çıkılmaz.
      await ensureAiConsentRecorded(_dio(sunucu), uid: 'u1');
      expect(sunucu.istekler, hasLength(1));
    });

    test('kayıt düşerse kurulum DÜŞMEZ; açılışta yeniden dener, başarıdan '
        'sonra bir daha atmaz', () async {
      final sunucu = _Sunucu(durumlar: [500, 503]);
      // Hata dışarı sızmaz — sızsaydı `_bitir`in catch'i kurulumu düşürürdü.
      await aiOnayiKurulumdaVerildi(_dio(sunucu), uid: 'u1');
      expect(sunucu.yola(_onayYolu), hasLength(1));

      await ensureAiConsentRecorded(_dio(sunucu), uid: 'u1'); // 503
      expect(sunucu.yola(_onayYolu), hasLength(2));
      await ensureAiConsentRecorded(_dio(sunucu), uid: 'u1'); // 200
      expect(sunucu.yola(_onayYolu), hasLength(3));
      await ensureAiConsentRecorded(_dio(sunucu), uid: 'u1');
      await ensureAiConsentRecorded(_dio(sunucu), uid: 'u1');
      expect(sunucu.yola(_onayYolu), hasLength(3),
          reason: 'başarıdan sonra bayrak silinmeli');
    });

    test('bayrağı olmayan kullanıcı (53\'ten gelen) HİÇ POST atmaz',
        () async {
      final sunucu = _Sunucu();
      for (var i = 0; i < 3; i++) {
        await ensureAiConsentRecorded(_dio(sunucu), uid: 'u53');
      }
      await ensureAiConsentRecorded(_dio(sunucu), uid: null);
      expect(sunucu.istekler, isEmpty,
          reason: 'kutuyu işaretlemeyenin adına kayıt yazılmaz');
    });

    test('bayrak HESABA bağlı: aynı cihazdaki başka hesap onu kullanamaz',
        () async {
      final sunucu = _Sunucu(durumlar: [500]);
      await aiOnayiKurulumdaVerildi(_dio(sunucu), uid: 'u1'); // düştü
      expect(sunucu.istekler, hasLength(1));

      // u1 çıktı, kutuyu hiç görmemiş u2 girdi.
      await ensureAiConsentRecorded(_dio(sunucu), uid: 'u2');
      expect(sunucu.istekler, hasLength(1),
          reason: 'istek u2\'nin kimliğiyle gider ve ona kayıt yazardı');

      // u1 geri dönünce borcu hâlâ duruyor.
      await ensureAiConsentRecorded(_dio(sunucu), uid: 'u1');
      expect(sunucu.istekler, hasLength(2));
    });

    test('kaynak: _bitir kaydı şartlar kaydından HEMEN sonra, kutuya bağlı '
        've kullanıcının kimliğiyle borçlanır', () {
      final govde = _dilim(
          _yorumsuz('lib/features/onboarding/onboarding_wizard.dart'),
          'Future<void> _bitir() async {',
          'Future<void> _tarihSec()');
      final sartlar = govde.indexOf('await ensureConsentRecorded(');
      final ai = govde.indexOf('if (_aiRiza) {\n'
          '        await aiOnayiKurulumdaVerildi(ref.read(apiProvider), '
          'uid: user.uid);\n'
          '      }');
      final dogum = govde.indexOf('saveBirthRecord(');
      expect(sartlar, greaterThan(-1));
      expect(ai, greaterThan(sartlar),
          reason: 'yapay zeka kaydı yok ya da kutuya bağlı değil');
      expect(dogum, greaterThan(ai));
      // Aradaki tek ifade: şartlar kaydı ile yapay zeka kaydı arasında
      // başka bir adım yok.
      final ara = govde.substring(sartlar, ai);
      expect(';'.allMatches(ara), hasLength(1));
    });

    test('kaynak: AppShell açılışı ensureConsentRecorded\'ın yanında, '
        'oturumdaki hesabın kimliğiyle dener', () {
      final acilis = _dilim(
          _yorumsuz('lib/features/shell/app_shell.dart'),
          'void initState() {',
          'void _buyukUcluPerdesi()');
      expect(acilis, contains('ensureConsentRecorded(ref.read(apiProvider));\n'
          '      ensureAiConsentRecorded(ref.read(apiProvider),\n'
          '          uid: ref.read(authStateProvider).value?.uid);'));
      // Açılış sırası 1.20.0+53'teki gibi: Büyük Üçlü perdesi doğrudan
      // oynar, önüne ya da arkasına bir onay sorusu girmez (tanıtım
      // paywall'ı ve bildirim izni ikinci şansı onu beklemez).
      expect(acilis, contains('if (!mounted) return;\n'
          '      _buyukUcluPerdesi();\n'));
    });
  });

  group('Kapı YOK: hiçbir özellik onaya bağlı değil', () {
    /// Abone, kurulumu bitmiş profil — onay kaydı, onay sağlayıcısı ya da
    /// bayrak YOK (53'ten gelen kullanıcının hâli).
    ProviderContainer kap(_Sunucu sunucu) {
      final k = ProviderContainer(overrides: [
        apiProvider.overrideWithValue(_dio(sunucu)),
        raporKapisiProvider.overrideWithValue(PlusHali.abone),
        profileProvider.overrideWith((ref) => Stream.value({
              'onboardingCompleted': true,
              'birthDate': '1990-03-07',
              'birthTime': '04:30',
              'birthCity': 'İstanbul',
            })),
      ]);
      addTearDown(k.dispose);
      return k;
    }

    /// Profil önce DİNLENİR, sonra ilk değeri beklenir ki okuma sağlayıcısı
    /// kurulurken kurulumu bitmiş profili görsün. Dinlemeden yalnız
    /// `read(.future)` ile beklenen akış bu kurulumda hiç değer vermedi
    /// (ölçüldü: 30 sn zaman aşımı, kap sökülürken "disposed during loading
    /// state").
    Future<void> profilHazir(ProviderContainer k) async {
      k.listen(profileProvider, (_, _) {});
      await k.read(profileProvider.future);
    }

    test('günlük okuma isteği onaysız GİDER ve okuma döner', () async {
      final sunucu = _Sunucu(govdeler: {
        '/reports/daily': {
          'data': {'reading': 'Bugün gökyüzü sakin.'},
        },
      });
      final k = kap(sunucu);
      await profilHazir(k);
      k.listen(dailyReadingProvider, (_, _) {});
      final veri = await k.read(dailyReadingProvider.future);

      expect(veri?['reading'], 'Bugün gökyüzü sakin.');
      final gunluk = sunucu.yola('/api/v1/reports/daily');
      expect(gunluk, hasLength(1));
      expect(gunluk.single.method, 'POST');
      expect(gunluk.single.queryParameters, isEmpty);
      expect(sunucu.yola(_onayYolu), isEmpty,
          reason: 'okuma onay durumunu sormaz');
    });

    test('sinyaller ai=0 OLMADAN istenir (yorum katmanı kısılmaz)', () async {
      final sunucu = _Sunucu(govdeler: {
        '/reports/signals': {
          'data': {'signals': []},
        },
      });
      final k = kap(sunucu);
      await profilHazir(k);
      k.listen(signalsDataProvider, (_, _) {});
      await k.read(signalsDataProvider.future);

      final sinyal = sunucu.yola('/api/v1/reports/signals');
      expect(sinyal, hasLength(1));
      expect(sinyal.single.queryParameters, isEmpty);
    });

    test('ai_consent.dart yalnız kurulum ve AppShell\'den kullanılır', () {
      // Sohbet, I Ching, yüz okuma, Atlas, BaZi, ilişki, profil — hiçbiri
      // onay modülünü içe aktarmıyorsa hiçbiri onayla kapılanamaz.
      final kullananlar = {
        for (final yol in _libDosyalari())
          if (_yorumsuz(yol).contains("core/ai_consent.dart'")) yol,
      };
      expect(kullananlar, {
        'lib/features/onboarding/onboarding_wizard.dart',
        'lib/features/shell/app_shell.dart',
      });
    });

    test('onay modülü kanıttan ibaret: sayfa, sağlayıcı, GET/DELETE yok', () {
      final k = _yorumsuz('lib/core/ai_consent.dart');
      for (final yasak in [
        'Widget',
        'showModalBottomSheet',
        'Provider',
        '.get(',
        '.delete(',
        'Exception',
      ]) {
        expect(k, isNot(contains(yasak)), reason: yasak);
      }
      expect('.post('.allMatches(k), hasLength(1));
    });

    test('kapının izleri lib\'de yok: ai=0, X-Ai-Consent 403, reading_ai_off',
        () {
      final izler = <String>[];
      for (final yol in _libDosyalari()) {
        final k = _yorumsuz(yol);
        for (final iz in [
          "'ai': '0'",
          'x-ai-consent',
          'X-Ai-Consent',
          'reading_ai_off',
        ]) {
          if (k.contains(iz)) izler.add('$yol: $iz');
        }
        if (yol != 'lib/core/ai_consent.dart' && k.contains(_onayYolu)) {
          izler.add('$yol: $_onayYolu');
        }
      }
      expect(izler, isEmpty);
    });

    test('sohbet gönderimi kapısız: _send doğrudan _gonder\'e iner', () {
      final k = _yorumsuz('lib/features/chat/chat_screen.dart');
      final gonderim =
          _dilim(k, 'Future<void> _send([String? preset]) async {',
              'Future<void> _tekrarDene(');
      // Tek bekleme gönderimin kendisi: araya bir soru/kapı girerse ikinci
      // bir `await` belirir.
      expect('await '.allMatches(gonderim), hasLength(1));
      expect(gonderim, contains('await _gonder(mesaj);'));
      final acilis = _dilim(k, 'void initState() {', 'void _onTextChanged()');
      expect(acilis, isNot(contains('showModalBottomSheet')));
    });
  });

  group('Hukuki metin onay ekranıyla tutarlı', () {
    String bolum(LegalSections s, String baslik) =>
        s.firstWhere((b) => b.$1 == baslik).$2;

    test('gizlilik politikası Gemini\'yi ve veri kategorilerini adlandırır',
        () {
      final tr = bolum(kPrivacyPolicyTr, 'Yapay zeka ile işleme');
      final en = bolum(kPrivacyPolicyEn, 'AI processing');
      for (final metin in [tr, en]) {
        expect(metin, contains('Gemini'));
        expect(metin, contains('Google LLC'));
        expect(metin, contains('BaZi'));
        expect(metin, contains('I Ching'));
      }
      expect(tr, contains('günlük notların'));
      expect(tr, contains('Profil > Gizlilik'));
      expect(en, contains('journal notes'));
      expect(en, contains('Profile > Privacy'));
    });

    test('eski yanlış iddialar geri gelmedi', () {
      final tr = bolum(kPrivacyPolicyTr, 'Bildirimler');
      final en = bolum(kPrivacyPolicyEn, 'Notifications');
      // Sabah bildirimi haritaya değen transitten yazılıyor — "kişiye özel
      // değildir" demek ölçülene aykırıydı.
      expect(tr.contains('kişiye özel değildir'), isFalse);
      expect(en.contains('not individually personalised'), isFalse);
      // Yıl Haritası güneş dönüşü anını gönderiyor; "doğum tarihin değil"
      // mutlak iddiası yanlıştı.
      expect(bolum(kPrivacyPolicyTr, 'Yapay zeka ile işleme')
          .contains('doğum tarihin/saatin değil'), isFalse);
    });
  });
}

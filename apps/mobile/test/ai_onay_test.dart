import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/ai_consent.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/city_directory.dart' show CityPick;
import 'package:rytho/core/providers.dart'
    show
        OnboardOutcome,
        PlusHali,
        baziReportProvider,
        birthHexagramProvider,
        dailyReadingProvider,
        innerCalendarProvider,
        justOnboardedProvider,
        natalReportProvider,
        profileProvider,
        raporKapisiProvider,
        signalsDataProvider,
        solarReturnProvider;
import 'package:rytho/features/onboarding/onboarding_wizard.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_en.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:shared_preferences/shared_preferences.dart';

/// Yapay zeka aktarım onayı — sahip kararları 2026-10-22 ve 2026-10-23.
///
/// Korunan değişmezler:
///
/// 1. Onay YALNIZ kurulumun ilk adımında, şartlar kutusunun altındaki AYRI
///    ve zorunlu ikinci kutuyla alınır; iki kutu işaretlenmeden "Devam"
///    açılmaz, biri yetmez. Kurulumu bitiren ikinci yol (hata bildirimindeki
///    "Tekrar dene") da aynı şartı arar. Kutu metni sağlayıcı adı taşımaz.
/// 2. Kanıt (`POST /account/ai-consent`) kurulum GERÇEKTEN bittikten (doğum
///    kaydı yazıldıktan) sonra bir kez gider; düşerse AppShell açılışında
///    yeniden denenir, başarıdan sonra bir daha gitmez.
/// 3. Kutuyu hiç görmemiş kullanıcı (1.20.0+53'ten güncelleyen) HİÇ istek
///    atmaz — adına kayıt yazılmaz. Bayrak hesaba bağlı: aynı cihazdaki
///    başka bir hesap onu kullanamaz.
/// 4. Kurulum dışında hiçbir yerde sorulmaz ve hiçbir özellik onaya kapılı
///    değil: onay kaydı ya da sağlayıcısı olmadan rapor ve sinyal istekleri
///    gider, sohbet gönderimi kapısız. Aynı şeyin GERÇEK interceptor
///    zinciriyle ölçümü `ai_onay_api_zinciri_test.dart`ta.

final _tr = AppLocalizationsTr();
final _en = AppLocalizationsEn();

const _onayYolu = '/api/v1/account/ai-consent';
const _onayModulu = 'lib/core/ai_consent.dart';
const _sihirbazYolu = 'lib/features/onboarding/onboarding_wizard.dart';
const _kabukYolu = 'lib/features/shell/app_shell.dart';

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

/// Dosyanın `ai_consent.dart` içe aktarımındaki `show` listesi; `show`
/// yoksa (modülün tamamı açılıyorsa) `null`.
Set<String>? _onayShowListesi(String yol) {
  final aktarimlar = RegExp(
          r'''import\s+['"][^'"]*ai_consent\.dart['"]\s*([^;]*);''')
      .allMatches(_yorumsuz(yol))
      .toList();
  expect(aktarimlar, hasLength(1), reason: '$yol modülü tek kez almalı');
  final show =
      RegExp(r'^show\s+([\w\s,]+)$').firstMatch(aktarimlar.single[1]!.trim());
  if (show == null) return null;
  return show[1]!
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
}

/// Biçimlendirilmiş Dart kaynağının üst düzey adları (sınıf, fonksiyon,
/// getter, değişken). Üst düzey bildirim 0. sütunda başlar; gövde ve devam
/// satırları girintili, kapanışlar `}`/`)` ile başlar.
Set<String> _ustDuzeyAdlar(String kaynak) {
  final adlar = <String>{};
  final tur = RegExp(r'^(?:(?:abstract|sealed|base|final|interface|mixin)\s+)*'
      r'(?:class|enum|typedef|mixin|extension\s+type|extension)\s+(\w+)');
  for (final satir in kaynak.split('\n')) {
    if (satir.isEmpty || RegExp(r'^[\s})\]@]').hasMatch(satir)) continue;
    if (RegExp(r'^(?:import|export|library|part)\b').hasMatch(satir)) {
      continue;
    }
    // Adsız eklenti dışarı ad açmaz.
    if (RegExp(r'^extension\s+on\b').hasMatch(satir)) continue;
    final t = tur.firstMatch(satir);
    if (t != null) {
      adlar.add(t[1]!);
      continue;
    }
    // Bildirimin adı: ilk `(`, `=`, `;` ya da `{`dan önceki son tanımlayıcı;
    // tür parametreleri (`Future<void>`, `Map<String, int>`) önce atılır.
    var bas = satir.split(RegExp(r'[(=;{]')).first;
    for (var once = ''; once != bas;) {
      once = bas;
      bas = bas.replaceAll(RegExp(r'<[^<>]*>'), '');
    }
    final son = RegExp(r'(\w+)\s*$').firstMatch(bas);
    if (son != null) adlar.add(son[1]!);
  }
  return adlar;
}

/// Seçiciler diyalog açmadan sabit değer döndürür (`sihirbaz_adimlar_test`
/// deseni): ölçülen şey kapı, seçicinin görünümü değil.
final _seciciler = SihirbazSeciciler(
  tarih: (_, _) async => DateTime(1990, 3, 7),
  saat: (_, _) async => const TimeOfDay(hour: 4, minute: 30),
  sehir: (_, _) async => const CityPick(
      name: 'Kahramanmaraş', nation: 'TR', admin1: 'Kahramanmaraş'),
);

Widget _sihirbaz({ProviderContainer? kap}) {
  final uygulama = MaterialApp(
    locale: const Locale('tr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildRythoTheme(),
    // Takımyıldız nabzı sonsuz animatör; ölçülen şey kapının kuralı.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: OnboardingWizard(seciciler: _seciciler),
  );
  return kap == null
      ? ProviderScope(child: uygulama)
      : UncontrolledProviderScope(container: kap, child: uygulama);
}

bool _devamAcik(WidgetTester tester) =>
    tester.widget<GoldButton>(find.byType(GoldButton)).onPressed != null;

Future<void> _dokun(WidgetTester tester, Finder hedef) async {
  await tester.ensureVisible(hedef);
  await tester.pump();
  await tester.tap(hedef);
  await tester.pump();
  await tester.pump();
}

Future<void> _kutu(WidgetTester tester, int i) =>
    _dokun(tester, find.byType(Checkbox).at(i));

Future<void> _devam(WidgetTester tester) =>
    _dokun(tester, find.byType(GoldButton));

/// Karşılamadan son adıma: iki kutu, tarih, saat, yer, "belirtmedim",
/// "Şimdi değil" (OS izni sorulmasın — test ortamında eklenti yok).
Future<void> _sonAdimaGit(WidgetTester tester) async {
  await _kutu(tester, 0);
  await _kutu(tester, 1);
  await _devam(tester);
  await _dokun(tester, find.text(_tr.birthDate));
  await _devam(tester);
  await _dokun(tester, find.text(_tr.birthTime));
  await _devam(tester);
  await _dokun(tester, find.text(_tr.onboardingCity));
  await _devam(tester);
  await _dokun(tester, find.text(_tr.genderUnspecified));
  await _devam(tester);
  await _dokun(tester, find.text(_tr.wizardNotifyNotNow));
  expect(find.text(_tr.wizardFinish), findsOneWidget);
  expect(_devamAcik(tester), isTrue);
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
      // Sahip kararı 2026-10-23: sağlayıcı ADI YOK ("bugün Gemini yarın
      // başkası") — kutu kapsayıcı dille izin ister, hizmetin adını
      // Gizlilik Politikası'na bırakır. Not çıkarma ve diğer yapay zeka
      // özellikleri de amaç olarak sayılıyor.
      expect(
          _tr.wizardAiConsentLabel,
          'Yorumlarımın ve sohbet yanıtlarımın üretilmesi, sohbetlerimden '
          'beni hatırlamaya yarayan notların çıkarılması ve uygulamadaki '
          'diğer yapay zeka özellikleri için harita bilgilerimin, '
          'mesajlarımın ve paylaştığım diğer verilerin üçüncü taraf yapay '
          'zeka hizmetlerine gönderilmesine izin veriyorum. Kullanılan '
          "hizmet Gizlilik Politikası'nda yazar.");
      expect(
          _en.wizardAiConsentLabel,
          'I allow my chart data, messages and other data I share to be '
          'sent to third-party AI services to generate my readings and chat '
          'replies, to extract notes from my chats that help remember me, '
          "and for the app's other AI features. The service in use is named "
          'in the Privacy Policy.');
    });

    test('onay bağlamında sağlayıcı adı geçmez (kod ve yorum)', () {
      // Kutu sağlayıcıyı anmıyorsa onu çağıran kod da anmamalı: yorumda
      // kalan "Gemini" bir sonraki turu metni geri yazmaya davet ederdi.
      // Ad yalnız Gizlilik Politikası'nda yaşar (legal_texts.dart, kapsam
      // dışı). Kelime sınırı: `signGemini` (İkizler burcu) eşleşmez.
      final ad = RegExp(r'\bGemini\b');
      for (final yol in [
        _onayModulu,
        _sihirbazYolu,
        _kabukYolu,
        'lib/features/profile/profile_sections.dart',
      ]) {
        expect(ad.hasMatch(File(yol).readAsStringSync()), isFalse,
            reason: yol);
      }
    });
  });

  group('"Tekrar dene" kapıyı atlayamaz', () {
    bool f({
      int adimSirasi = -1,
      bool riza = true,
      bool aiRiza = true,
      bool tarihVar = true,
      bool saatBiliniyor = true,
      TimeOfDay? saat = const TimeOfDay(hour: 4, minute: 30),
      String? sehir = 'Kahramanmaraş',
      String? cinsiyet = 'unspecified',
      bool? bildirim = false,
    }) =>
        sihirbazBitirebilir(
          adimSirasi:
              adimSirasi < 0 ? kOnboardingSteps.length - 1 : adimSirasi,
          riza: riza,
          aiRiza: aiRiza,
          tarih: tarihVar ? DateTime(1990, 3, 7) : null,
          saatBiliniyor: saatBiliniyor,
          saat: saat,
          sehir: sehir,
          cinsiyet: cinsiyet,
          bildirimSecimi: bildirim,
        );

    test('son adımda ve altı adımın hepsi geçerliyken açık', () {
      expect(f(), isTrue);
      expect(f(saatBiliniyor: false, saat: null), isTrue,
          reason: '"bilmiyorum" de bir karar');
    });

    test('iki kutudan biri kalkınca kapalı — son adımda olsa bile', () {
      expect(f(aiRiza: false), isFalse,
          reason: 'yapay zeka onayı olmadan kurulum bitmez');
      expect(f(riza: false), isFalse);
    });

    test('son adımda değilken kapalı', () {
      for (var i = 0; i < kOnboardingSteps.length - 1; i++) {
        expect(f(adimSirasi: i), isFalse, reason: 'adım $i');
      }
    });

    test('geri gidilip boşaltılan HER adım kapıyı kapatır', () {
      expect(f(tarihVar: false), isFalse);
      expect(f(saat: null), isFalse);
      expect(f(sehir: '  '), isFalse);
      expect(f(cinsiyet: null), isFalse);
      expect(f(bildirim: null), isFalse);
    });

    testWidgets('kutu kaldırılınca "Tekrar dene" kurulumu bitiremez: yazım '
        'yolu hiç başlamaz, geri gitmek bildirimi kaldırır', (tester) async {
      final sunucu = _Sunucu();
      final kap = ProviderContainer(
          overrides: [apiProvider.overrideWithValue(_dio(sunucu))]);
      addTearDown(kap.dispose);
      // Yazım yolunun İLK izi Büyük Üçlü bayrağı (`chartOk`, yazımdan önce
      // konur): kapı açıksa her deneme onu kurar, hata dalı geri indirir.
      final perde = <OnboardOutcome?>[];
      kap.listen(justOnboardedProvider, (_, s) => perde.add(s));

      await tester.pumpWidget(_sihirbaz(kap: kap));
      await tester.pump();
      await _sonAdimaGit(tester);

      // İlk deneme: yazım yolu açıldı ve test ortamında (Firebase yok)
      // oturum okumasında düştü → sebepli hata + "Tekrar dene".
      await _devam(tester);
      expect(perde, [OnboardOutcome.chartOk, null]);
      expect(find.byType(SnackBarAction), findsOneWidget);
      final tekrarDene =
          tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;

      // Kullanıcı karşılamaya geri gider — bekleyen bildirim kalkar.
      for (var i = 0; i < kOnboardingSteps.length - 1; i++) {
        await _dokun(tester, find.byIcon(Icons.arrow_back_rounded));
      }
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_tr.wizardWelcomeTitle), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing,
          reason: 'eylemli SnackBar kendiliğinden kapanmaz; geri giderken '
              'kalkmalı');

      // Yapay zeka kutusunu kaldırır; düğme kapanır.
      await _kutu(tester, 1);
      expect(_devamAcik(tester), isFalse);

      // Ekranda kalmış (ya da yarışla basılmış) "Tekrar dene".
      perde.clear();
      tekrarDene();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(perde, isEmpty,
          reason: 'işaretsiz kutuyla yazım yolu başladı');
      expect(find.byType(SnackBar), findsNothing,
          reason: 'ikinci deneme yapıldı ve düştü');
      expect(sunucu.istekler, isEmpty, reason: 'ağa çıkıldı');
      expect(tester.takeException(), isNull);
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
      // Hata dışarı sızmaz — sızsaydı `_bitir`in catch'i tamamlanmış
      // kurulumu hata dalına düşürürdü.
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

    test('kaynak: _bitir kaydı doğum kaydı BAŞARIYLA döndükten SONRA, '
        'kutuya bağlı, kurulumun başında alınan istemciyle borçlanır', () {
      final govde = _dilim(_yorumsuz(_sihirbazYolu),
          'Future<void> _bitir() async {', 'Future<void> _tarihSec()');
      final istemci = govde.indexOf('final dio = ref.read(apiProvider);');
      final dogum = govde.indexOf('final sonuc = await saveBirthRecord(');
      final ai = govde.indexOf('if (_aiRiza) {\n'
          '        await aiOnayiKurulumdaVerildi(dio, uid: user.uid);\n'
          '      }');
      final perde =
          govde.indexOf('if (sonuc == BirthSaveResult.savedWithoutChart)');
      // Kurulum yazımının `try`ı: başarı yolu "done" ile kapanır.
      final hata =
          govde.indexOf("Analytics.onboardingStep('done');\n    } catch (e) {");

      // İstemci ilk beklemeden ÖNCE, sihirbaz takılıyken alınır; bekleme
      // sonrası `ref.read` sökülmüş sihirbazda StateError fırlatır.
      expect(istemci, greaterThan(-1));
      expect(istemci, lessThan(govde.indexOf('await ')));
      expect('ref.read(apiProvider)'.allMatches(govde), hasLength(1));

      expect(dogum, greaterThan(-1));
      expect(ai, greaterThan(dogum),
          reason: 'yapay zeka kaydı doğum kaydından önce ya da kutuya bağlı '
              'değil');
      // Aradaki tek ifade doğum kaydının kendisi: kurulum biter bitmez.
      expect(';'.allMatches(govde.substring(dogum, ai)), hasLength(1));
      // `ref` kullanan perde dalından önce ve `try` içinde.
      expect(perde, greaterThan(ai));
      expect(hata, greaterThan(perde));
    });

    test('kaynak: _bitir\'in ilk ifadesi kapı — bayraktan, yazımdan ve '
        'Firebase\'den önce', () {
      final govde = _dilim(_yorumsuz(_sihirbazYolu),
          'Future<void> _bitir() async {', 'Future<void> _tarihSec()');
      final ifadeler = govde
          .substring('Future<void> _bitir() async {'.length)
          .trim()
          .split(';');
      expect(ifadeler.first, 'if (_busy || !_bitirebilir) return');
      expect(
          govde,
          contains('ScaffoldMessenger.of(context).showSnackBar(SnackBar(\n'
              '          content: Text(friendlyError(e, l10n)),\n'
              '          action: SnackBarAction(label: l10n.retry, '
              'onPressed: _bitir),'));
      final geri = _dilim(_yorumsuz(_sihirbazYolu), 'void _geri() {',
          'Future<void> _bitir() async {');
      expect(geri, contains('ScaffoldMessenger.of(context)'
          '.hideCurrentSnackBar();'));
    });

    test('kaynak: AppShell açılışı ensureConsentRecorded\'ın yanında, '
        'oturumdaki hesabın kimliğiyle dener', () {
      final acilis = _dilim(
          _yorumsuz(_kabukYolu),
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

    // Günlük okumanın kardeşleri: aynı `require_plus` sınıfı, aynı profil
    // kapısı. Bir gün onay kapısı yalnız birine konursa yalnız o düşer.
    for (final (ad, saglayici, yol) in [
      ('natal rapor', natalReportProvider, '/api/v1/reports/natal'),
      ('BaZi', baziReportProvider, '/api/v1/reports/bazi'),
      (
        'doğum heksagramı',
        birthHexagramProvider,
        '/api/v1/reports/birth-hexagram'
      ),
      ('Yıl Haritası', solarReturnProvider, '/api/v1/reports/solar-return'),
      (
        'İç Takvim (progresyon)',
        innerCalendarProvider,
        '/api/v1/reports/progressions'
      ),
    ]) {
      test('$ad isteği onaysız GİDER ve rapor döner', () async {
        final sunucu = _Sunucu(govdeler: {
          yol.replaceFirst('/api/v1', ''): {
            'data': {'rapor': ad},
          },
          // İç Takvim'in jetonsuz ikinci ucu.
          '/astrology/transit-calendar': {
            'data': {'events': <Object>[]},
          },
        });
        final k = kap(sunucu);
        await profilHazir(k);
        k.listen(saglayici, (_, _) {});
        final veri = await k.read(saglayici.future);

        expect(veri, isNotNull, reason: 'sağlayıcı istek atmadan döndü');
        final istek = sunucu.yola(yol);
        expect(istek, hasLength(1));
        expect(istek.single.method, 'POST');
        expect(istek.single.queryParameters, isEmpty);
        expect(sunucu.yola(_onayYolu), isEmpty,
            reason: 'rapor onay durumunu sormaz');
      });
    }

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

    test('ai_consent.dart\'ı yalnız kurulum ve AppShell içe aktarır; ikisi '
        'de tek adı açar; modülün genel API\'si üç ad', () {
      // Sohbet, I Ching, yüz okuma, Atlas, BaZi, ilişki, profil — hiçbiri
      // onay modülünü içe aktarmıyorsa hiçbiri onayla kapılanamaz.
      // Eşleşme DOSYA ADIYLA: `core/` içinden göreli `'ai_consent.dart'`
      // ya da `package:` yolu da yakalanır.
      final yolDizesi = RegExp(r'''['"](?:[^'"\n]*/)?ai_consent\.dart['"]''');
      final aktaranlar = {
        for (final yol in _libDosyalari())
          if (yol != _onayModulu && yolDizesi.hasMatch(_yorumsuz(yol))) yol,
      };
      expect(aktaranlar, {_sihirbazYolu, _kabukYolu});
      // AppShell yalnız borcu öder; kayıt BORÇLANDIRAMAZ (53 kullanıcısı
      // kutuyu hiç görmedi).
      expect(_onayShowListesi(_kabukYolu), {'ensureAiConsentRecorded'});
      expect(_onayShowListesi(_sihirbazYolu), {'aiOnayiKurulumdaVerildi'});
      // Yeni bir genel ad (ör. "onay verdi mi" sorgusu) modülü kapıya
      // çevirmenin ilk adımı olurdu.
      expect(
          _ustDuzeyAdlar(_yorumsuz(_onayModulu))
              .where((a) => !a.startsWith('_'))
              .toSet(),
          {'kAiConsentVersion', 'aiOnayiKurulumdaVerildi',
            'ensureAiConsentRecorded'});
    });

    test('aiOnayiKurulumdaVerildi yalnız sihirbazda ve TAM BİR KEZ çağrılır',
        () {
      // Bayrağı koyan tek fonksiyon bu: AppShell ya da başka bir yüzey onu
      // çağırabilseydi kutuyu hiç görmemiş (53'ten gelen) birinin adına
      // kayıt yazılırdı.
      final anan = <String>{
        for (final yol in _libDosyalari())
          if (yol != _onayModulu &&
              _yorumsuz(yol).contains('aiOnayiKurulumdaVerildi'))
            yol,
      };
      expect(anan, {_sihirbazYolu});
      final govde = _yorumsuz(_sihirbazYolu)
          .split('\n')
          .where((s) => !s.startsWith('import '))
          .join('\n');
      expect('aiOnayiKurulumdaVerildi'.allMatches(govde), hasLength(1),
          reason: 'içe aktarım dışında tek anılış: çağrının kendisi');
      expect('aiOnayiKurulumdaVerildi('.allMatches(govde), hasLength(1));
      // Modül onu yalnız TANIMLAR, içeriden çağırmaz.
      expect('aiOnayiKurulumdaVerildi'.allMatches(_yorumsuz(_onayModulu)),
          hasLength(1));
    });

    test('wizardAiConsentLabel yalnız sihirbazda, tek kutuda kullanılır', () {
      // Onayın başka yerde sorulmasının (AppShell diyaloğu, sohbet gönderim
      // diyaloğu) ilk adımı bu metni ikinci bir ekrana koymaktır.
      final kullanan = <String, int>{
        for (final yol in _libDosyalari())
          if (_yorumsuz(yol).contains('wizardAiConsentLabel'))
            yol: 'wizardAiConsentLabel'.allMatches(_yorumsuz(yol)).length,
      };
      expect(kullanan, {_sihirbazYolu: 1});
      // Cümle ikinci bir anahtara kopyalanıp oradan da sorulamasın.
      for (final (dil, metin) in [
        ('tr', _tr.wizardAiConsentLabel),
        ('en', _en.wizardAiConsentLabel),
      ]) {
        final arb = jsonDecode(File('lib/l10n/app_$dil.arb').readAsStringSync())
            as Map<String, dynamic>;
        expect(
            arb.entries.where((e) => e.value == metin).map((e) => e.key),
            ['wizardAiConsentLabel'],
            reason: dil);
      }
    });

    test('api.dart interceptor zincirine onay kapısı konamaz', () {
      // `apiProvider` her isteğin geçtiği tek boğaz: oraya konan bir onay
      // okuması sohbet dahil bütün yapay zeka yüzeylerini sessizce
      // kapılardı. 33bb9f4'teki (Play'deki 53) api.dart'ta da bu üçünün
      // hiçbiri yoktu (ölçüldü), yani yasak daraltılmadan tam: bayrak
      // deposu (SharedPreferences), "onay" ve "consent" adı. `Onay`
      // camelCase sınırını da yakalar (`aiOnayi`).
      final k = _yorumsuz('lib/core/api.dart');
      for (final (ad, kalip) in [
        ('SharedPreferences', RegExp('SharedPreferences|shared_preferences')),
        ('consent', RegExp('consent', caseSensitive: false)),
        ('onay', RegExp(r'(?<![A-Za-zÇĞİÖŞÜçğıöşü])onay|Onay')),
      ]) {
        expect(kalip.hasMatch(k), isFalse, reason: '$ad api.dart\'a girdi');
      }
    });

    test('onay modülü kanıttan ibaret: sayfa, sağlayıcı, GET/DELETE yok', () {
      final k = _yorumsuz(_onayModulu);
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
        if (yol != _onayModulu && k.contains(_onayYolu)) {
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
}

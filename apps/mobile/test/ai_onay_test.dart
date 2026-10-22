import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/ai_consent.dart';
import 'package:rytho/core/api.dart' show friendlyError;
import 'package:rytho/features/profile/legal_texts.dart';
import 'package:rytho/features/profile/profile_sections.dart'
    show AiConsentRow;
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/main.dart' show rythoRetry;
import 'package:shared_preferences/shared_preferences.dart';

/// U06 — üçüncü taraf AI (Google Gemini) aktarım onayı, Apple 5.1.2(i).
///
/// Korunan değişmezler:
///
/// 1. Onay verilene kadar sayfa HER istekte yeniden gelir — "bir kez
///    gösterildi" bayrağı YOK (Apple'ın reddettiği `hasSeenConsent`
///    kısayolu tam olarak buydu).
/// 2. "Şimdi değil" AI'yı kapatır ve kararı sunucuya yazmayı dener; yazım
///    düşse de uygulama çökmez.
/// 3. Onay verildiyse sayfa hiç açılmaz; geri alınınca yeniden açılır.
/// 4. Onay kaydedilemediyse onay VERİLMİŞ SAYILMAZ (ispatsız aktarım yok).

class _SahteDepo implements AiOnayDeposu {
  _SahteDepo({this.sunucu = false});

  bool sunucu;
  bool durumHatasi = false;
  bool verHatasi = false;
  bool geriAlHatasi = false;
  int durumSayisi = 0;
  final List<int> verilenSurumler = [];
  int geriAlSayisi = 0;

  @override
  Future<bool> durum() async {
    durumSayisi++;
    if (durumHatasi) throw StateError('ag yok');
    return sunucu;
  }

  @override
  Future<void> ver(int surum) async {
    if (verHatasi) throw StateError('yazilamadi');
    verilenSurumler.add(surum);
    sunucu = true;
  }

  @override
  Future<void> geriAl() async {
    geriAlSayisi++;
    if (geriAlHatasi) throw StateError('yazilamadi');
    sunucu = false;
  }
}

AppLocalizations _tr() => lookupAppLocalizations(const Locale('tr'));

ProviderContainer _kap(_SahteDepo depo, {String? uid = 'u1'}) {
  // Uygulamanın kendi yeniden deneme politikası: AiOnayiGerekli DENENMEZ
  // (Riverpod varsayılanı 10 kez dener ve bekleyen okuma hiç bitmez).
  final kap = ProviderContainer(retry: rythoRetry, overrides: [
    aiOnayHesabiProvider.overrideWithValue(uid),
    aiOnayDeposuProvider.overrideWithValue(depo),
  ]);
  addTearDown(kap.dispose);
  return kap;
}

/// Tek düğmeli ekran: dokununca [aiOnayiIste] çağrılır, sonuç kaydedilir.
class _Tetik extends ConsumerWidget {
  const _Tetik(this.sonuclar);

  final List<bool> sonuclar;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => sonuclar.add(await aiOnayiIste(context, ref)),
            child: const Text('AI ozelligini ac'),
          ),
        ),
      );
}

Widget _sar(ProviderContainer kap, Widget child) => UncontrolledProviderScope(
      container: kap,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: child,
      ),
    );

/// Dokunup kararın yerleşmesini bekler. Sahte zamanda: sahte depo ve
/// SharedPreferences sahtesi mikro görevlerle biter; gerçek olay döngüsü
/// (`runAsync`) GoogleFonts'un ağdan font çekme denemesini gerçek kılar ve
/// hatası teste sızar.
Future<void> _dokun(WidgetTester tester, Finder hedef) async {
  // Sayfa uzun: düğmeler küçük test yüzeyinde kaydırma alanının altında
  // kalabiliyor — görünür olmayan hedefe dokunuş sessizce boşa düşer.
  await tester.ensureVisible(hedef);
  await tester.pump();
  await tester.tap(hedef);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _yerles(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _ac(WidgetTester tester) =>
    _dokun(tester, find.text('AI ozelligini ac'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    aiOnayKapisiniSifirla();
  });

  group('Kapı: onay yokken sayfa HER seferinde gelir', () {
    testWidgets('Şimdi değil → false, ikinci açılışta sayfa YİNE gelir',
        (tester) async {
      final depo = _SahteDepo();
      final kap = _kap(depo);
      final sonuclar = <bool>[];
      await tester.pumpWidget(_sar(kap, _Tetik(sonuclar)));

      await _ac(tester);
      expect(find.text(_tr().aiConsentTitle), findsOneWidget);
      await _dokun(tester, find.text(_tr().aiConsentNotNow));
      expect(sonuclar, [false]);
      expect(find.text(_tr().aiConsentTitle), findsNothing);
      // Dostça mesaj: veri gönderilmiyor.
      expect(find.text(_tr().aiConsentDeclinedSnack), findsOneWidget);
      // Karar sunucuya "hayır" olarak yazıldı (sabah bildirimi de AI'sız).
      expect(depo.geriAlSayisi, 1);

      await _ac(tester);
      expect(find.text(_tr().aiConsentTitle), findsOneWidget,
          reason: '"bir kez gösterildi" bayrağı olmamalı');
      await _dokun(tester, find.text(_tr().aiConsentNotNow));
      expect(sonuclar, [false, false]);
      expect(depo.verilenSurumler, isEmpty);
    });

    testWidgets('sayfa sağlayıcıyı ve gönderilen veriyi adıyla sayar',
        (tester) async {
      final kap = _kap(_SahteDepo());
      await tester.pumpWidget(_sar(kap, _Tetik(<bool>[])));
      await _ac(tester);
      final l10n = _tr();
      for (final metin in [
        l10n.aiConsentIntro,
        l10n.aiConsentDataChart,
        l10n.aiConsentDataChat,
        l10n.aiConsentDataMemory,
        l10n.aiConsentDataPeople,
        l10n.aiConsentDataFace,
        l10n.aiConsentPurpose,
        l10n.aiConsentDeclineInfo,
        l10n.aiConsentPrivacyLink,
        l10n.aiConsentAgree,
        l10n.aiConsentNotNow,
      ]) {
        expect(find.text(metin), findsOneWidget, reason: metin);
      }
      expect(l10n.aiConsentIntro, contains('Gemini'));
      expect(l10n.aiConsentIntro, contains('Google'));
    });

    testWidgets('geri tuşu Şimdi değil gibi KAYDEDİLİR, bir kez',
        (tester) async {
      // Android geri tuşu `isDismissible: false`a rağmen sayfayı kapatır
      // (sonuç null). Kaydedilmeseydi "veri gönderilmiyor" mesajı çıkar ama
      // sunucu açık "hayır"ı hiç öğrenmezdi.
      final depo = _SahteDepo();
      final kap = _kap(depo);
      final sonuclar = <bool>[];
      await tester.pumpWidget(_sar(kap, _Tetik(sonuclar)));
      await _ac(tester);
      expect(find.text(_tr().aiConsentTitle), findsOneWidget);

      await tester.binding.handlePopRoute();
      await _yerles(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(_tr().aiConsentTitle), findsNothing);
      expect(sonuclar, [false]);
      expect(depo.geriAlSayisi, 1);
      expect(depo.verilenSurumler, isEmpty);
      expect(kap.read(aiOnayProvider).value, isFalse);
      expect(find.text(_tr().aiConsentDeclinedSnack), findsOneWidget);

      // "Şimdi değil" düğmesi kaydı kendisi yapar; null yolu onu ikinci
      // kez yazmamalı.
      await _ac(tester);
      await _dokun(tester, find.text(_tr().aiConsentNotNow));
      expect(sonuclar, [false, false]);
      expect(depo.geriAlSayisi, 2);
    });

    testWidgets('Şimdi değil kaydı sunucuya yazılamasa da çökmez',
        (tester) async {
      final depo = _SahteDepo()..geriAlHatasi = true;
      final kap = _kap(depo);
      final sonuclar = <bool>[];
      await tester.pumpWidget(_sar(kap, _Tetik(sonuclar)));
      await _ac(tester);
      await _dokun(tester, find.text(_tr().aiConsentNotNow));
      expect(sonuclar, [false]);
      expect(kap.read(aiOnayProvider).value, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('Kapı: onay verilince geçer, geri alınınca yine sorar', () {
    testWidgets('Kabul ediyorum → sürümle kaydedilir, sonra sayfa gelmez',
        (tester) async {
      final depo = _SahteDepo();
      final kap = _kap(depo);
      final sonuclar = <bool>[];
      await tester.pumpWidget(_sar(kap, _Tetik(sonuclar)));

      await _ac(tester);
      await _dokun(tester, find.text(_tr().aiConsentAgree));
      expect(sonuclar, [true]);
      expect(depo.verilenSurumler, [kAiConsentVersion]);
      expect(kap.read(aiOnayProvider).value, isTrue);

      await _ac(tester);
      expect(find.text(_tr().aiConsentTitle), findsNothing);
      expect(sonuclar, [true, true]);
    });

    testWidgets('sunucuda onay varsa sayfa HİÇ açılmaz', (tester) async {
      final kap = _kap(_SahteDepo(sunucu: true));
      final sonuclar = <bool>[];
      await tester.pumpWidget(_sar(kap, _Tetik(sonuclar)));
      await _ac(tester);
      expect(find.text(_tr().aiConsentTitle), findsNothing);
      expect(sonuclar, [true]);
    });

    testWidgets('geri alınınca sonraki açılışta sayfa yeniden gelir',
        (tester) async {
      final depo = _SahteDepo(sunucu: true);
      final kap = _kap(depo);
      final sonuclar = <bool>[];
      await tester.pumpWidget(_sar(kap, _Tetik(sonuclar)));
      kap.read(aiOnayProvider.notifier);
      await _yerles(tester);
      kap.read(aiOnayProvider.notifier).geriAl();
      await _yerles(tester);
      expect(depo.sunucu, isFalse);
      expect(kap.read(aiOnayProvider).value, isFalse);

      await _ac(tester);
      expect(find.text(_tr().aiConsentTitle), findsOneWidget);
    });

    testWidgets('kayıt yazılamazsa onay VERİLMİŞ SAYILMAZ, hata sayfada',
        (tester) async {
      final depo = _SahteDepo()..verHatasi = true;
      final kap = _kap(depo);
      final sonuclar = <bool>[];
      await tester.pumpWidget(_sar(kap, _Tetik(sonuclar)));
      await _ac(tester);
      await _dokun(tester, find.text(_tr().aiConsentAgree));
      expect(find.text(_tr().aiConsentSaveFailed), findsOneWidget);
      expect(find.text(_tr().aiConsentTitle), findsOneWidget);
      expect(kap.read(aiOnayProvider).value, isFalse);
      expect(sonuclar, isEmpty, reason: 'sayfa hâlâ açık, karar yok');
    });
  });

  group('Durum', () {
    test('hesap yoksa onay yok, sunucuya gidilmez', () async {
      final depo = _SahteDepo(sunucu: true);
      final kap = _kap(depo, uid: null);
      expect(await kap.read(aiOnayProvider.future), isFalse);
      expect(depo.durumSayisi, 0);
    });

    test('sunucuya ulaşılamazsa SON BİLİNEN karar, o da yoksa kapalı',
        () async {
      final depo = _SahteDepo()..durumHatasi = true;
      expect(await _kap(depo).read(aiOnayProvider.future), isFalse);

      SharedPreferences.setMockInitialValues(
          {'ai-consent-v$kAiConsentVersion-u1': true});
      expect(await _kap(depo).read(aiOnayProvider.future), isTrue);
      // Önbellek HESABA bağlı: başka hesap bu onayı devralmaz.
      expect(await _kap(depo, uid: 'u2').read(aiOnayProvider.future),
          isFalse);
    });

    test('sunucu cevabı önbelleğin ÖNÜNE geçer', () async {
      SharedPreferences.setMockInitialValues(
          {'ai-consent-v$kAiConsentVersion-u1': true});
      final depo = _SahteDepo(sunucu: false);
      expect(await _kap(depo).read(aiOnayProvider.future), isFalse,
          reason: 'başka cihazda geri alınmış onay burada da kapanmalı');
    });

    test('AI sağlayıcısı onay yokken AiOnayiGerekli, verilince kurulur',
        () async {
      final depo = _SahteDepo();
      final kap = _kap(depo);
      var istek = 0;
      final rapor = FutureProvider<String>((ref) async {
        await aiOnayiGerektir(ref);
        istek++;
        return 'okuma';
      });
      kap.listen(rapor, (_, _) {});
      await expectLater(kap.read(rapor.future),
          throwsA(isA<AiOnayiGerekli>()));
      expect(istek, 0, reason: 'onay yokken istek ATILMAMALI');

      await kap.read(aiOnayProvider.notifier).ver();
      expect(await kap.read(rapor.future), 'okuma');
      expect(istek, 1);
    });

    test('yumuşak uçlara onay yokken ai=0, varken parametre YOK', () async {
      final depo = _SahteDepo();
      final kap = _kap(depo);
      final parametre = FutureProvider<Map<String, dynamic>?>(
          (ref) => aiSorguParametresi(ref));
      kap.listen(parametre, (_, _) {});
      expect(await kap.read(parametre.future), {'ai': '0'});
      await kap.read(aiOnayProvider.notifier).ver();
      expect(await kap.read(parametre.future), isNull,
          reason: 'onaylı istek eski istemcininkiyle bayt bayt aynı');
    });
  });

  group('Hata eşlemesi', () {
    DioException yanit(int kod, {String? isaret}) => DioException(
          requestOptions: RequestOptions(path: '/api/v1/chat'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/chat'),
            statusCode: kod,
            headers: Headers.fromMap({
              if (isaret != null) kAiConsentHeader: [isaret],
            }),
          ),
        );

    test('işaretli 403 AI onay hatasıdır, işaretsiz 403 değildir', () {
      expect(aiOnayHatasiMi(const AiOnayiGerekli()), isTrue);
      expect(aiOnayHatasiMi(yanit(403, isaret: 'required')), isTrue);
      expect(aiOnayHatasiMi(yanit(403)), isFalse,
          reason: 'yüz rızası / arkadaşlık 403\'ü onay sayfası açmamalı');
      expect(aiOnayHatasiMi(yanit(402, isaret: 'required')), isFalse);
      expect(aiOnayHatasiMi(StateError('x')), isFalse);
    });

    test('friendlyError onay durumunu dürüst cümleyle söyler', () {
      expect(friendlyError(const AiOnayiGerekli(), _tr()),
          _tr().aiConsentOffBody);
    });
  });

  group('Ayarlar satırı (geri alınabilirlik)', () {
    testWidgets('kapalıyken anahtar onay SAYFASINI açar, doğrudan açmaz',
        (tester) async {
      final depo = _SahteDepo();
      final kap = _kap(depo);
      await tester.pumpWidget(
          _sar(kap, const Scaffold(body: Material(child: AiConsentRow()))));
      await _yerles(tester);
      expect(find.text(_tr().aiConsentSettingOff), findsOneWidget);

      await _dokun(tester, find.byType(Switch));
      expect(find.text(_tr().aiConsentTitle), findsOneWidget);
      expect(depo.verilenSurumler, isEmpty,
          reason: 'metin görülmeden onay yazılmamalı');
      await _dokun(tester, find.text(_tr().aiConsentAgree));
      expect(find.text(_tr().aiConsentSettingOn), findsOneWidget);
    });

    testWidgets('açıkken anahtar onaylı diyalogla geri alır', (tester) async {
      final depo = _SahteDepo(sunucu: true);
      final kap = _kap(depo);
      await tester.pumpWidget(
          _sar(kap, const Scaffold(body: Material(child: AiConsentRow()))));
      await _yerles(tester);
      expect(find.text(_tr().aiConsentSettingOn), findsOneWidget);

      await _dokun(tester, find.byType(Switch));
      expect(find.text(_tr().aiConsentWithdrawBody), findsOneWidget);
      await _dokun(tester, find.text(_tr().aiConsentWithdrawConfirm));
      expect(depo.geriAlSayisi, 1);
      expect(depo.sunucu, isFalse);
      expect(find.text(_tr().aiConsentSettingOff), findsOneWidget);
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

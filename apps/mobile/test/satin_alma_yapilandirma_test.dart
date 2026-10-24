// Satın alma yapılandırma kapısı (U05 kod ağı): platform × kip × önek.
//
// Kapatılan iki kusur (gerekçe `lib/core/subscription.dart`
// `rcEtkinAnahtar`):
//  1. Eski kapı iki anahtardan BİRİ doluysa "yapılandırıldı" diyordu. iOS
//     anahtarı boş, Android anahtarı doluyken `configure` hiç çağrılmıyor
//     ama `Purchases.*` çağrıları yapılıyordu — iOS'ta yapılandırılmamış
//     SDK yerel `fatalError` veriyor.
//  2. Yayın derlemesinde `test_` anahtarı RevenueCat'i BİLEREK çöktürüyor;
//     artık `configure` hiç çağrılmıyor ve kullanıcı "kullanılamıyor" görür.
//
// SINIR BEYANI: kararın girdileri (`kReleaseMode`, `kProfileMode`,
// dart-define anahtarları) derleme anı sabiti; `flutter test` onları
// değiştiremez. Bu yüzden KARAR saf işlevden tabloyla, ÜRETİM BAĞLANTISI
// (getter'ın hangi sabitleri hangi parametreye verdiği) kaynaktan sınanıyor.
//
// "Çökmez" sözünün ikinci ayağı ÇAĞRI YERLERİ: yapılandırılmamış derlemede
// her `Purchases.*` çağrısı `billingConfigured` kapısının arkasında durmak
// zorunda. Çürütme turu (2026-10-24) üç kapıyı (billingIdentityProvider,
// offeringsProvider, tokenPacksProvider) tek tek silip TAM takımı yeşil
// gördü. Bu dosya onları iki yoldan tutuyor: SDK kanalına giden çağrıyı
// kaydeden davranış bekçisi ve lib/'deki her `Purchases.*` çağrısını bir
// kapı kaydına bağlayan kaynak bekçisi.
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart' show authStateProvider;
import 'package:rytho/core/purchase_errors.dart';
import 'package:rytho/core/subscription.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/profile/subscription_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';

AppLocalizations _tr() => lookupAppLocalizations(const Locale('tr'));

/// purchases_flutter 9.16.1'in TEK yöntem kanalı (`lib/purchases_flutter.dart`
/// `_channel`). `Purchases.*` çağrılarının yerel SDK'ya giden hepsi buradan
/// geçiyor; yalnız dinleyici ekle/çıkar Dart tarafında kalıyor.
const _kRcKanali = MethodChannel('purchases_flutter');

/// Kanala giden her çağrıyı kaydeder; yanıt `null`.
///
/// Yanıtın içeriği önemsiz: soru "çağrı GİTTİ Mİ". iOS'ta yapılandırılmamış
/// SDK'ya giden tek çağrı yerel `fatalError` (PurchasesHybridCommon 17.55.1
/// `CommonFunctionality.swift:18-22`); testte çöküş yok, iz var.
List<MethodCall> _kanaliKaydet() {
  final kayit = <MethodCall>[];
  final haberci =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  haberci.setMockMethodCallHandler(_kRcKanali, (cagri) async {
    kayit.add(cagri);
    return null;
  });
  addTearDown(() => haberci.setMockMethodCallHandler(_kRcKanali, null));
  return kayit;
}

/// Oturum akışına konacak sahte Firebase kullanıcısı: kimlik bağlama
/// yalnız `uid`ye bakıyor. Diğer üyeler `noSuchMethod`a düşer.
class _SahteKullanici implements User {
  _SahteKullanici(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Gerçek zamanlayıcıyla birkaç tur bekler: kimlik bağlama `Future(...)`
/// içinde koşuyor (Timer.run), mikro görev boşaltmak yetmez.
Future<void> _olaylarAksin() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

/// `Purchases.*` çağrısı taşıyabilen TEK üst düzey bildirimler ve her
/// birinin kapısı (`<lib yolu>::<ad>` → kapı dizesi).
///
/// Neden kayıt: yayında `test_` anahtarı ve anahtarsız derleme `configure`
/// ETMİYOR; çökmezlik artık her çağrının kapı arkasında durmasına bağlı.
/// Kayıtsız bir bildirimde `Purchases.*` belirirse, kapı silinirse ya da
/// çağrının ALTINA kayarsa bekçi kırmızı verir.
///
/// Kapı dizesi boşlukları teke indirilmiş kaynakta, bildirimin EN DIŞ
/// bloğunda (süslü parantez derinliği 1) ve ilk `Purchases.` çağrısından
/// ÖNCE aranır — iç bir dalda duran kapı çağrıyı korumaz.
/// `await ensureBillingIdentity();` kapı sayılır: o işlevin kendi kapısı da
/// bu kayıtta. `initBilling` `billingConfigured`ın TANIMINI
/// (`_etkinRcAnahtari`) doğrudan okuyor; anlamı aynı kapı.
/// `yetkiToplayiciProvider`daki dinleyici ekle/çıkar yerel SDK'ya gitmiyor
/// (yalnız Dart kümesi) ama yine de kapılı ve kayıtta: istisna listesi
/// tutmak, bir gün yerel bir çağrının o istisnanın arkasına saklanmasına
/// kapı açardı.
const _kapiKaydi = <String, String>{
  'lib/core/subscription.dart::initBilling':
      'final key = _etkinRcAnahtari; if (key == null) return;',
  'lib/core/subscription.dart::billingIdentityProvider':
      'if (!billingConfigured) return;',
  'lib/core/subscription.dart::yetkiToplayiciProvider':
      'if (kurucu == null && !billingConfigured) return;',
  'lib/core/subscription.dart::offeringsProvider':
      'if (getirici == null && !billingConfigured) return const [];',
  'lib/core/subscription.dart::abonelikKaynakMagazasi':
      'if (getirici == null && !billingConfigured) return null;',
  'lib/core/subscription.dart::ensureBillingIdentity':
      'if (!billingConfigured) throw const SatinAlmaYapilandirilmamis();',
  'lib/core/subscription.dart::purchasePackage':
      'await ensureBillingIdentity();',
  'lib/core/subscription.dart::restorePurchases':
      'await ensureBillingIdentity();',
  'lib/core/wallet.dart::tokenPacksProvider':
      'if (getirici == null && !billingConfigured) return const [];',
  'lib/core/wallet.dart::purchaseTokenPack': 'await ensureBillingIdentity();',
};

/// Yerel SDK çağrısı biçimi: `Purchases.` + üye adı. "Restore Purchases."
/// gibi bir cümle sonu eşleşmesin diye noktadan sonra harf isteniyor;
/// `restorePurchases(` ise sözcük sınırı yüzünden zaten dışarıda.
final _purchasesCagrisi = RegExp(r'\bPurchases\.[A-Za-z_]');

/// Üst düzey bildirimin adı; tanınmazsa ilk satırın kendisi döner (kayıtta
/// olmayacağı için kırmızıya düşer — sessizce geçmez).
String _bildirimAdi(String ilkSatir) {
  for (final desen in [
    RegExp(r'^(?:final|const|var|late)\s+(?:[\w<>?,\s]+?\s+)?(\w+)\s*='),
    RegExp(r'\bget\s+(\w+)'),
    RegExp(r'^(?:abstract\s+|sealed\s+|final\s+|base\s+)*'
        r'(?:class|enum|mixin|extension|typedef)\s+(\w+)'),
    RegExp(r'(\w+)\s*(?:<[^<>()]*>)?\s*\('),
  ]) {
    final m = desen.firstMatch(ilkSatir);
    if (m != null) return m.group(1)!;
  }
  return ilkSatir.trim();
}

/// Kaynağı üst düzey bildirimlere böler: `dart format` gövdeleri
/// girintiliyor, yani SÜTUN 0'da başlayan her satır yeni bir bildirim.
/// Kapanış satırları (`}`, `)`, `]`) önceki bildirime aittir. Tam satır
/// yorumlar ÖNCE atılır — bir çağrıyı ANLATAN yorum çağrı sayılmasın
/// (CLAUDE.md §5). Gövde boşlukları teke indirilmiş döner.
List<({String ad, String govde})> _ustDuzeyBildirimler(String kaynak) {
  final satirlar = kaynak
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((s) => !s.trimLeft().startsWith('//'));
  final sonuc = <({String ad, String govde})>[];
  String? ad;
  var govde = StringBuffer();
  void kapat() {
    final bitenAd = ad;
    if (bitenAd != null) {
      sonuc.add((
        ad: bitenAd,
        govde: govde.toString().replaceAll(RegExp(r'\s+'), ' '),
      ));
    }
  }

  for (final satir in satirlar) {
    final yeni = satir.isNotEmpty &&
        !satir.startsWith(RegExp(r'[\s})\]]'));
    if (yeni) {
      kapat();
      ad = _bildirimAdi(satir);
      govde = StringBuffer();
    }
    govde.writeln(satir);
  }
  kapat();
  return sonuc;
}

/// Kapı denetimi — saf işlev, bilerek: aynı işlev hem gerçek lib/'e hem
/// sahte kaynaklara uygulanıyor, yani bekçinin KÖR olmadığı (kapısız
/// çağrıyı gerçekten yakaladığı) kendi içinde ölçülüyor.
List<String> _kapiDenetimi(
    Map<String, String> dosyalar, Map<String, String> kayit) {
  final sorunlar = <String>[];
  final gorulen = <String>{};
  for (final MapEntry(key: yol, value: kaynak) in dosyalar.entries) {
    for (final b in _ustDuzeyBildirimler(kaynak)) {
      final ilk = _purchasesCagrisi.firstMatch(b.govde);
      if (ilk == null) continue;
      final anahtar = '$yol::${b.ad}';
      gorulen.add(anahtar);
      final kapi = kayit[anahtar];
      if (kapi == null) {
        sorunlar.add('$anahtar: Purchases.* çağrısı KAYITSIZ — '
            'billingConfigured kapısı denetlenmiyor');
        continue;
      }
      final k = b.govde.indexOf(kapi);
      if (k < 0) {
        sorunlar.add('$anahtar: kapı YOK ($kapi)');
        continue;
      }
      if (k > ilk.start) {
        sorunlar.add('$anahtar: kapı ilk Purchases çağrısından SONRA');
        continue;
      }
      final once = b.govde.substring(0, k);
      final derinlik =
          '{'.allMatches(once).length - '}'.allMatches(once).length;
      if (derinlik != 1) {
        sorunlar.add('$anahtar: kapı en dış blokta değil (derinlik '
            '$derinlik) — iç daldaki kapı çağrıyı korumaz');
      }
    }
  }
  for (final anahtar in kayit.keys) {
    if (!gorulen.contains(anahtar)) {
      sorunlar.add('$anahtar: kayıtta var ama Purchases çağrısı bulunamadı '
          '(kayıt bayat ya da tarayıcı KÖR)');
    }
  }
  return sorunlar;
}

// Biçimce gerçek anahtarlara benzeyen SAHTE değerler (önek + 27 karakter).
const _goog = 'goog_SahteAndroidAnahtari00000';
const _appl = 'appl_SahteIosAnahtariOlcum0000';
const _testAndroid = 'test_SahteAndroidTestStore0000';
const _testIos = 'test_SahteIosTestStoreAnahtar0';

String? _karar(TargetPlatform platform,
        {required bool yayin, String android = '', String ios = ''}) =>
    rcEtkinAnahtar(
        platform: platform,
        yayinDerlemesi: yayin,
        androidAnahtari: android,
        iosAnahtari: ios);

/// ba6108b'deki karar, BİREBİR (subscription.dart eski :53-54 ve :113-122)
/// — "Android davranışı değişmedi" iddiasının ölçü çubuğu.
bool _eskiYapilandirildi(String android, String ios) =>
    android.isNotEmpty || ios.isNotEmpty;

String? _eskiConfigureAnahtari(TargetPlatform p, String android, String ios) {
  if (!_eskiYapilandirildi(android, ios)) return null;
  final key = p == TargetPlatform.iOS ? ios : android;
  return key.isEmpty ? null : key;
}

/// Yorumlar atılmış, boşlukları teke indirilmiş kaynak: bekçi bir şeyi
/// ANLATAN yorumu görüp geçmemeli (CLAUDE.md §5).
String _kod(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n')
    .replaceAll(RegExp(r'\s+'), ' ');

int _say(String metin, String aranan) => aranan.allMatches(metin).length;

void main() {
  // Kanal kaydedici `TestDefaultBinaryMessengerBinding` istiyor; düz
  // `test()` gövdeleri onu kendiliğinden kurmaz.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('karar tablosu (rcEtkinAnahtar)', () {
    for (final yayin in [false, true]) {
      final kip = yayin ? 'yayın' : 'debug';

      test('$kip: iOS YALNIZ iOS anahtarına bakar', () {
        expect(_karar(TargetPlatform.iOS, yayin: yayin, ios: _appl), _appl);
        expect(
            _karar(TargetPlatform.iOS,
                yayin: yayin, android: _goog, ios: _appl),
            _appl);
        // Eski kusurun TAM kendisi: Android anahtarı dolu, iOS boş.
        expect(_karar(TargetPlatform.iOS, yayin: yayin, android: _goog),
            isNull,
            reason: 'iOS anahtarı boşken yapılandırılmış sayılırsa '
                'Purchases.* yapılandırılmamış SDK\'ya gider (iOS: '
                'fatalError)');
      });

      test('$kip: Android YALNIZ Android anahtarına bakar', () {
        expect(
            _karar(TargetPlatform.android, yayin: yayin, android: _goog),
            _goog);
        expect(
            _karar(TargetPlatform.android,
                yayin: yayin, android: _goog, ios: _appl),
            _goog);
        expect(_karar(TargetPlatform.android, yayin: yayin, ios: _appl),
            isNull);
      });

      test('$kip: iOS ve Android dışında anahtar YOK', () {
        for (final p in [
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.fuchsia,
        ]) {
          expect(_karar(p, yayin: yayin, android: _goog, ios: _appl), isNull,
              reason: '$p için tanımlı bir RevenueCat anahtarı yok');
        }
      });

      test('$kip: boş anahtar her platformda yapılandırılmamış', () {
        expect(_karar(TargetPlatform.iOS, yayin: yayin), isNull);
        expect(_karar(TargetPlatform.android, yayin: yayin), isNull);
      });
    }

    test('test_ anahtarı DEBUG\'da çalışır (Test Store), iki platformda', () {
      expect(_karar(TargetPlatform.iOS, yayin: false, ios: _testIos),
          _testIos);
      expect(
          _karar(TargetPlatform.android, yayin: false, android: _testAndroid),
          _testAndroid);
    });

    test('test_ anahtarı YAYINDA yapılandırılmamış sayılır, iki platformda',
        () {
      expect(_karar(TargetPlatform.iOS, yayin: true, ios: _testIos), isNull,
          reason: 'RevenueCat #if !DEBUG altında Test Store anahtarıyla '
              'BİLEREK fatalError veriyor; configure hiç çağrılmamalı');
      expect(
          _karar(TargetPlatform.android, yayin: true, android: _testAndroid),
          isNull);
    });

    test('yalnız ÖNEK test_ sayılır, içinde geçmesi değil', () {
      const icindeTest = 'appl_icinde_test_gecen0000000';
      expect(_karar(TargetPlatform.iOS, yayin: true, ios: icindeTest),
          icindeTest);
      expect(kRcTestStoreOneki, 'test_',
          reason: 'RevenueCat 5.67.1 Configuration.swift:420 ile aynı önek');
    });
  });

  group('Android davranışı', () {
    test('build-aab.ps1\'in kabul ettiği her Android durumunda karar '
        'ESKİSİYLE AYNI', () {
      // build-aab.ps1 yalnız yayın AAB'si üretir ve Android anahtarının
      // DOLU ve `test_` önekli OLMAMASINI ister. iOS anahtarına bakmaz —
      // onun her hâli tabloda.
      for (final yayin in [false, true]) {
        for (final ios in ['', _appl, _testIos]) {
          final yeni = _karar(TargetPlatform.android,
              yayin: yayin, android: _goog, ios: ios);
          expect(yeni,
              _eskiConfigureAnahtari(TargetPlatform.android, _goog, ios),
              reason: 'yayin=$yayin ios=$ios: configure anahtarı değişti');
          expect(yeni != null, _eskiYapilandirildi(_goog, ios),
              reason: 'yayin=$yayin ios=$ios: billingConfigured değişti');
        }
      }
      // Debug'da test_ anahtarı da eskisi gibi (Test Store geliştirmesi).
      for (final ios in ['', _appl, _testIos]) {
        expect(
            _karar(TargetPlatform.android,
                yayin: false, android: _testAndroid, ios: ios),
            _eskiConfigureAnahtari(
                TargetPlatform.android, _testAndroid, ios));
      }
    });

    test('değişen İKİ Android durumu da build-aab.ps1\'in REDDETTİĞİ durum',
        () {
      // (a) Android anahtarı boş, iOS dolu: eski kapı "yapılandırıldı"
      // deyip configure ETMİYORDU — tutarsız hâl. Yeni: ikisi de "yok".
      expect(_eskiYapilandirildi('', _appl), isTrue);
      expect(_eskiConfigureAnahtari(TargetPlatform.android, '', _appl),
          isNull);
      expect(_karar(TargetPlatform.android, yayin: true, ios: _appl), isNull);
      // (b) Yayın + test_ Android anahtarı: eskisi configure ediyordu.
      expect(
          _eskiConfigureAnahtari(TargetPlatform.android, _testAndroid, ''),
          _testAndroid);
      expect(
          _karar(TargetPlatform.android, yayin: true, android: _testAndroid),
          isNull);

      // İki durumu da yayın betiği reddediyor; betikten bu kapılar
      // sökülürse "Android'de zararsız" gerekçesi düşer ve bu test onu
      // söyler. PowerShell yorumları atılarak okunur.
      final betik = File('../../infra/build-aab.ps1')
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .split('\n')
          .where((s) => !s.trimLeft().startsWith('#'))
          .join('\n');
      expect(betik, contains(r'if (-not $androidKey) {'),
          reason: '(a): anahtarsız Android yayını reddedilmiyor');
      expect(betik, contains(r'if ($androidKey.StartsWith("test_")) {'),
          reason: '(b): test_ anahtarlı Android yayını reddedilmiyor');
    });
  });

  group('üretim bağlantısı (kaynaktan)', () {
    final kod = _kod('lib/core/subscription.dart');

    test('iki anahtar sabiti YALNIZ tek seçicide okunur', () {
      // Bildirim + seçici = 2. Üçüncü bir okuma kapıyı atlamak demek
      // (eski billingConfigured ve initBilling tam olarak buydu).
      expect(_say(kod, 'kRevenueCatIosKey'), 2);
      expect(_say(kod, 'kRevenueCatAndroidKey'), 2);
      expect(
          kod,
          contains('String? get _etkinRcAnahtari => rcEtkinAnahtar( '
              'platform: defaultTargetPlatform, '
              'yayinDerlemesi: kReleaseMode || kProfileMode, '
              'androidAnahtari: kRevenueCatAndroidKey, '
              'iosAnahtari: kRevenueCatIosKey, );'),
          reason: 'Profile da DEBUG\'sız (Podfile Profile → :release); '
              'yalnız kReleaseMode yetmez');
    });

    test('billingConfigured ve initBilling AYNI seçiciyi kullanır', () {
      expect(kod,
          contains('bool get billingConfigured => _etkinRcAnahtari != null;'));
      expect(
          kod,
          contains('Future<void> initBilling() async { '
              'final key = _etkinRcAnahtari; if (key == null) return;'));
      expect(_say(kod, 'Purchases.configure('), 1);
      expect(kod, contains('Purchases.configure(PurchasesConfiguration(key))'));
    });

    test('lib/ içinde anahtarları başka okuyan ya da configure eden yok', () {
      final yabancilar = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.replaceAll(r'\', '/').endsWith('core/subscription.dart')) {
          continue;
        }
        final k = _kod(f.path);
        if (k.contains('kRevenueCatIosKey') ||
            k.contains('kRevenueCatAndroidKey') ||
            k.contains("'REVENUECAT_") ||
            k.contains('Purchases.configure(')) {
          yabancilar.add(f.path);
        }
      }
      expect(yabancilar, isEmpty);
    });

    test('satın alma kimliği kapısı Firebase\'den ÖNCE', () {
      expect(
          kod,
          contains('Future<void> ensureBillingIdentity() async { '
              'if (!billingConfigured) throw const '
              'SatinAlmaYapilandirilmamis();'));
    });
  });

  group('lib/ içindeki her Purchases.* çağrısı kapılı (kaynaktan)', () {
    test('gerçek kaynakta kapısız çağrı yok, kayıt bayat değil', () {
      final dosyalar = <String, String>{};
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        dosyalar[f.path.replaceAll(r'\', '/')] = f.readAsStringSync();
      }
      expect(_kapiDenetimi(dosyalar, _kapiKaydi), isEmpty,
          reason: 'yeni bir Purchases.* çağrısı ya _kapiKaydi\'na kapısıyla '
              'girmeli ya da billingConfigured arkasına alınmalı');
    });

    // Bekçinin KÖR olmadığı, sahte kaynaklarla kendi içinde ölçülüyor:
    // aynı işlev, aynı kayıt biçimi.
    const yol = 'lib/x.dart';
    const kayit = {'$yol::kapili': 'if (!billingConfigured) return;'};

    test('tuzak: kapılı doğru örnek temiz geçer', () {
      expect(
          _kapiDenetimi({
            yol: 'void kapili() {\n'
                '  if (!billingConfigured) return;\n'
                '  Purchases.logOut();\n'
                '}\n',
          }, kayit),
          isEmpty);
    });

    test('tuzak: kayıtsız yeni çağrı yeri KIRMIZI', () {
      final sorun = _kapiDenetimi({
        yol: 'void kapili() {\n'
            '  if (!billingConfigured) return;\n'
            '  Purchases.logOut();\n'
            '}\n'
            '\n'
            'final yeniProvider = FutureProvider<void>((ref) async {\n'
            '  await Purchases.getOfferings();\n'
            '});\n',
      }, kayit);
      expect(sorun, [contains('$yol::yeniProvider: Purchases.* çağrısı KAYITSIZ')]);
    });

    test('tuzak: kapı çağrının ALTINDA ya da iç dalda ise KIRMIZI', () {
      expect(
          _kapiDenetimi({
            yol: 'void kapili() {\n'
                '  Purchases.logOut();\n'
                '  if (!billingConfigured) return;\n'
                '}\n',
          }, kayit),
          [contains('SONRA')]);
      expect(
          _kapiDenetimi({
            yol: 'void kapili(bool x) {\n'
                '  if (x) {\n'
                '    if (!billingConfigured) return;\n'
                '  }\n'
                '  Purchases.logOut();\n'
                '}\n',
          }, kayit),
          [contains('derinlik 2')]);
    });

    test('tuzak: kapısı silinmiş kayıtlı bildirim ve bayat kayıt KIRMIZI',
        () {
      expect(
          _kapiDenetimi({
            yol: 'void kapili() {\n'
                '  Purchases.logOut();\n'
                '}\n',
          }, kayit),
          [contains('kapı YOK')]);
      // Çağrıyı ANLATAN yorum çağrı sayılmaz; kayıt o yüzden bayat kalır.
      expect(
          _kapiDenetimi({
            yol: 'void kapili() {\n'
                '  // Purchases.logOut() burada çağrılmıyor.\n'
                '}\n',
          }, kayit),
          [contains('kayıt bayat')]);
    });
  });

  group('yapılandırılmamış derlemede SDK kanalına HİÇ çağrı gitmez', () {
    // Davranış bekçisi: sağlayıcılar GERÇEK gövdeleriyle (dikiş/getirici
    // YOK) koşturulur ve purchases_flutter kanalına giden her çağrı
    // kaydedilir. Kapı silinirse kanal kaydında `logIn`/`getOfferings`/
    // `getProductInfo` belirir — iOS'ta o çağrı yapılandırılmamış SDK'da
    // yerel `fatalError` olurdu.
    //
    // Sınır beyanı: `yetkiToplayiciProvider`daki dinleyici ekle/çıkar yerel
    // SDK'ya gitmiyor (yalnız Dart kümesi), yani bu kayıt onu göremez; o
    // kapıyı yukarıdaki kaynak bekçisi tutuyor.

    test('önkoşul: test ortamında billingConfigured false', () {
      expect(billingConfigured, isFalse);
    });

    test('billingIdentityProvider: oturum açılıp kapanırken logIn/logOut '
        'gitmez', () async {
      final kanal = _kanaliKaydet();
      // Yayın akışı: dinleyicisizken kapatmak da hemen biter (tek
      // dinleyicili denetleyicinin `close()`u dinleyicisiz ASLA
      // tamamlanmaz — CLAUDE.md §5).
      final oturum = StreamController<User?>.broadcast();
      addTearDown(oturum.close);
      final kap = ProviderContainer(
        overrides: [authStateProvider.overrideWith((_) => oturum.stream)],
        retry: (_, _) => null,
      );
      addTearDown(kap.dispose);

      kap.listen(billingIdentityProvider, (_, _) {});
      await _olaylarAksin();
      oturum.add(null);
      await _olaylarAksin();
      oturum.add(_SahteKullanici('olcum-uid'));
      await _olaylarAksin();
      oturum.add(null);
      await _olaylarAksin();

      expect(kanal.map((c) => c.method), isEmpty,
          reason: 'kapı silinirse oturum akışı logIn ve logOut gönderir '
              '(fireImmediately + uid değişimi)');
    });

    test('offeringsProvider: getiricisiz okunur, kanala gitmez', () async {
      final kanal = _kanaliKaydet();
      final kap = ProviderContainer(retry: (_, _) => null);
      addTearDown(kap.dispose);
      final sonuc = await kap
          .read(offeringsProvider.future)
          .then<Object>((v) => v, onError: (Object e) => e);
      expect(kanal.map((c) => c.method), isEmpty,
          reason: 'paywall açılınca Purchases.getOfferings yapılandırılmamış '
              'SDK\'ya giderdi');
      expect(sonuc, isA<List<Object?>>().having((l) => l, 'liste', isEmpty));
    });

    test('tokenPacksProvider: getiricisiz okunur, kanala gitmez', () async {
      final kanal = _kanaliKaydet();
      final kap = ProviderContainer(retry: (_, _) => null);
      addTearDown(kap.dispose);
      final sonuc = await kap
          .read(tokenPacksProvider.future)
          .then<Object>((v) => v, onError: (Object e) => e);
      expect(kanal.map((c) => c.method), isEmpty,
          reason: 'kredi mağazası açılınca Purchases.getProducts '
              'yapılandırılmamış SDK\'ya giderdi');
      expect(sonuc, isA<List<Object?>>().having((l) => l, 'liste', isEmpty));
    });

    test('abonelikKaynakMagazasi ve ensureBillingIdentity: kanala gitmez',
        () async {
      final kanal = _kanaliKaydet();
      expect(await abonelikKaynakMagazasi(null), isNull);
      await expectLater(ensureBillingIdentity(),
          throwsA(isA<SatinAlmaYapilandirilmamis>()));
      expect(kanal.map((c) => c.method), isEmpty);
    });
  });

  group('yapılandırılmamış derlemede satın alma yolu çökmez', () {
    test('test ortamı anahtarsız (önkoşul)', () {
      expect(billingConfigured, isFalse);
    });

    test('ensureBillingIdentity SDK\'ya ve Firebase\'e dokunmadan reddeder',
        () async {
      // Kapı yoksa ilk çağrı FirebaseAuth.instance olur ve testte
      // `[core/no-app]` fırlatır — tür farkı iki yolu ayırıyor.
      await expectLater(ensureBillingIdentity(),
          throwsA(isA<SatinAlmaYapilandirilmamis>()));
    });

    test('hata metni: "satın alma şu an kullanılamıyor"', () {
      final l10n = _tr();
      for (final abonelik in [true, false]) {
        expect(
            purchaseErrorText(const SatinAlmaYapilandirilmamis(), l10n,
                abonelik: abonelik),
            l10n.billingUnavailable);
      }
    });

    testWidgets('Abonelik ekranı: "Geri yükle" kullanılamıyor der',
        (tester) async {
      // Düğme mağaza kuralı gereği HER ZAMAN görünür; üretim geri
      // yükleyicisi (dikiş YOK) ile basılır. Kapı sökülürse ilk çağrı
      // FirebaseAuth'a gider ve metin "beklenmeyen sorun" olur.
      final l10n = _tr();
      final kanal = _kanaliKaydet();
      tester.view.physicalSize = const Size(1200, 12000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        overrides: [
          subscriptionProvider
              .overrideWith((_) => Future.value(SubscriptionStatus.none)),
          walletProvider.overrideWith((_) => Future.value(WalletStatus.none)),
        ],
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildRythoTheme(),
          home: const SubscriptionScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text(l10n.restorePurchases));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(l10n.billingUnavailable), findsOneWidget);
      // Ekran meşgul durumda takılı kalmadı: düğme yeniden basılabilir.
      final dugme = tester.widget<TextButton>(
          find.widgetWithText(TextButton, l10n.restorePurchases));
      expect(dugme.onPressed, isNotNull);
      // Ekran açılıp geri yüklemeye basılırken SDK kanalına tek çağrı yok.
      expect(kanal.map((c) => c.method), isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}

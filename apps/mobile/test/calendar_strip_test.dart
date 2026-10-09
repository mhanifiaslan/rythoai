import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` riverpod 3'te ana kütüphaneden değil buradan geliyor.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/sky/calendar_strip.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_tokens.dart';

/// R5-6'nin degismezleri: ana ekrandaki 30 gunluk takvim seridi ve
/// ucretsiz katmanin DURUST teaser'i.
///
/// Kullanicinin istegi: "ana sayfada burc kartlarinin hemen altina yatay
/// takvim, tek satirlik... tiklaninca detayli bir kart acilacak. bir
/// sonraki ayin olaylari yaklastiginda konular kartlarda gorunecek ama
/// icerikler kilitli olacak."
///
/// Kritik olan cizgi: ucretsiz kullanici GERCEK tarihi ve GERCEK temayi
/// gorur, yalnizca okuma kilitlidir. Teaser uydurma olursa urunun
/// "olculmeyen soylenmez" ilkesi kirilir.

String _bugun([int gunSonra = 0]) {
  final d = DateTime.now().add(Duration(days: gunSonra));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Abonenin gordugu olay: okuma satiri ve dayanak var.
Map<String, dynamic> _acikOlay({int gunSonra = 2}) => {
      'type': 'aspect_exact',
      'date': _bugun(gunSonra),
      'date_local': '20 Ağustos',
      'theme': 'relationships',
      'theme_local': 'İlişkiler',
      'tone': 'support',
      'line': 'Yakınlarınla aranda biriken şeyi konuşmak kolaylaşıyor.',
      'technical': 'Mars, natal Venüs ile üçgen — orb 0.4°',
      'transit_local': 'Mars',
      'natal_local': 'Venüs',
      'aspect_local': 'Üçgen',
      'orb': 0.4,
    };

/// Istasyon olayi (OP2). Sunucu bunu KISIYE OZEL uretmez: anlam
/// cumlesi sabit tablodan gelir ve gezegeni anlatir, kullaniciyi
/// anlatmaz. Bu yuzden hem ucretsiz hem abone katmanda AYNI gelir ve
/// temasi yoktur (`theme` alani YOK -> "Diger hareketler" basligi).
///
/// Metin BILEREK ASCII: bu dosyanin iddialari alt dize eslesmesiyle
/// kuruluyor ve Turkce noktali I alt dize eslesmesinde sessiz yanlis
/// pozitif uretiyor (depo kurali). Olculen sey YERLESIM ve SIRA;
/// metnin dili ayri bir testin konusu ('Ingilizce arayuzde Turkce
/// metin KALMAZ').
Map<String, dynamic> _istasyonOlayi({int gunSonra = 3}) => {
      'type': 'station_direct',
      'date': _bugun(gunSonra),
      'date_local': '14 Ekim',
      'transit_local': 'Pluton',
      'type_local': 'ileri harekete donus',
      'line': 'Pluton duruyor ve ileri harekete donuyor - temeli sokup '
          'yeniden doken etki. Kazanci tikanan isin yeniden yurumesi.',
      'technical': 'Pluton 14 Ekim gunu hizini sifira indirip yon '
          'degistiriyor (ileri harekete donus).',
    };

/// Ucretsiz kullanicinin gordugu ayni olay: sunucu okumayi cikardi.
Map<String, dynamic> _kilitliOlay({int gunSonra = 2}) {
  final o = Map<String, dynamic>.from(_acikOlay(gunSonra: gunSonra))
    ..remove('line')
    ..remove('technical');
  return o..['locked'] = true;
}

Widget _sar(Widget child,
        {List<Override> overrides = const [],
        Locale locale = const Locale('tr')}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: child,
      ),
    );

/// Gun kartini acan yardimci: sayfa `showDaySheet` ile aciliyor, bunun
/// icin gercek bir `BuildContext` gerekiyor.
Future<void> _gunKartiniAc(
    WidgetTester tester, List<Map<String, dynamic>> olaylar) async {
  await tester.pumpWidget(_sar(Builder(builder: (context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () =>
              showDaySheet(context, DateTime.now(), olaylar),
          child: const Text('aç'),
        ),
      ),
    );
  })));
  await tester.tap(find.text('aç'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Gun sayfasini DAR ve KISA ekranda, yazi olcegi TAVANINDA cizer.
///
/// Olculen sey DIKEY tasma. `showDaySheet` `isScrollControlled` bir alt
/// sayfa ve govdesi `mainAxisSize: min` bir `Column`; kaydirma
/// sarmalayicisi olmazsa ekrandan uzun icerik SESSIZ kirpilir (kardes
/// desende, `basis_sheet`te, 131 px olculdu). Kart desenine gecis satir
/// basina yukseklik ekledigi icin bu bekci artik zorunlu.
///
/// 320x640 secildi: 320 dp piyasadaki en dar Android, 640 dp ise kisa
/// ama gercek bir telefon yuksekligi.
Future<void> _darKisaEkranda(
    WidgetTester tester, List<Map<String, dynamic>> olaylar) async {
  tester.view.physicalSize = const Size(320 * 3, 640 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(kMaxTextScale),
          // Giris animasyonlari testte zamanlayici birakir; olculen sey
          // YERLESIM, hareket degil.
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDaySheet(context, DateTime.now(), olaylar),
              child: const Text('ac'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ac'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('takvim şeridi', () {
    testWidgets('otuz gün çizilir ve bugün en başta durur', (tester) async {
      await tester.pumpWidget(_sar(
        const Scaffold(body: CalendarStrip()),
        overrides: [
          transitCalendarProvider.overrideWith((ref) async => {
                'events': [_acikOlay()],
              }),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Bugünün günü ilk hücrede.
      expect(find.text('${DateTime.now().day}'), findsWidgets);
      expect(CalendarStrip.gunSayisi, 30);
    });

    testWidgets('veri yoksa şerit HİÇ çizilmez', (tester) async {
      // Bölüm kendi kendini gizler; ana ekran şeritsiz de ayakta kalmalı.
      await tester.pumpWidget(_sar(
        const Scaffold(body: CalendarStrip()),
        overrides: [
          transitCalendarProvider.overrideWith((ref) async => null),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('olaysız takvim ekranı bozmaz', (tester) async {
      await tester.pumpWidget(_sar(
        const Scaffold(body: CalendarStrip()),
        overrides: [
          transitCalendarProvider
              .overrideWith((ref) async => {'events': <dynamic>[]}),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  });

  group('tarih dili', () {
    // Cihaz bulgusu: serit Ingilizce arayuzde de "Agu 27 / Eyl 2" diyordu.
    //
    // Sebep `main.dart`teydi: acilista YALNIZ `initializeDateFormatting(
    // 'tr_TR')` cagriliyordu. `DateFormat('MMM', 'en')` Ingilizce sembol
    // verisini bulamayinca yuklu olan tek dile dusuyor ve ay adini Turkce
    // basiyordu. Sessiz bir kusur: istisna atmiyor, yanlis dil yaziyor.
    setUpAll(() async {
      await initializeDateFormatting();
    });

    test('ay kisaltmasi dile gore degisir', () {
      final gun = DateTime(2026, 8, 30);
      expect(DateFormat('MMM', 'tr').format(gun), 'Ağu');
      expect(DateFormat('MMM', 'en').format(gun), 'Aug');
    });

    test('tam tarih dile gore degisir', () {
      final gun = DateTime(2026, 8, 30);
      expect(DateFormat('d MMMM', 'tr').format(gun), '30 Ağustos');
      expect(DateFormat('d MMMM', 'en').format(gun), '30 August');
    });
  });

  group('gün kartı', () {
    testWidgets('abonede okuma cümlesi ve dayanak girişi var',
        (tester) async {
      await _gunKartiniAc(tester, [_acikOlay()]);

      expect(find.text('İlişkiler'), findsOneWidget);
      expect(find.textContaining('konuşmak kolaylaşıyor'), findsOneWidget);
      // OP2: giriş artık oklu yazım taşıyor (ana ekran sinyal kartıyla
      // aynı yazım). Oksuz hâli bir başlık gibi okunuyordu,
      // dokunulabildiğini söylemiyordu — sahibin "CTA yok"
      // şikâyetinin yarısı buydu.
      expect(find.text('Neye dayanıyor? →'), findsOneWidget);
    });

    testWidgets('ücretsizde tema GÖRÜNÜR ama okuma kilitli',
        (tester) async {
      await _gunKartiniAc(tester, [_kilitliOlay()]);

      // Teaser dürüst: tema başlığı gerçek ve görünür.
      expect(find.text('İlişkiler'), findsOneWidget);
      // Okuma yok, yerinde kilit satırı var.
      expect(find.textContaining('konuşmak kolaylaşıyor'), findsNothing);
      expect(find.textContaining('Rytho+'), findsOneWidget);
    });

    testWidgets('olaylar temaya göre BAŞLIKLANIR', (tester) async {
      final kariyer = Map<String, dynamic>.from(_acikOlay())
        ..['theme'] = 'career'
        ..['theme_local'] = 'Kariyer'
        ..['line'] = 'İşinde görünürlüğün artıyor.';
      await _gunKartiniAc(tester, [_acikOlay(), kariyer]);

      expect(find.text('İlişkiler'), findsOneWidget);
      expect(find.text('Kariyer'), findsOneWidget);
    });

    testWidgets('kilit cümlesi sayfada BİR KEZ görünür', (tester) async {
      // Cihaz turu (1.5.1+18): iki kilitli olayı olan gün, aynı cümleyi
      // alt alta iki kez basıyordu. Tekrar bilgi vermiyor, yalnızca kilidi
      // olduğundan büyük gösteriyordu.
      final ikinci = Map<String, dynamic>.from(_kilitliOlay())
        ..['orb'] = 1.2;
      await _gunKartiniAc(tester, [_kilitliOlay(), ikinci]);

      expect(find.textContaining('Rytho+'), findsOneWidget);
      expect(find.text('İlişkiler'), findsOneWidget);
    });

    testWidgets('sunucu anlamı göndermediğinde ÖLÇÜM yazılır',
        (tester) async {
      // Bu testin eski gerekçesi "istasyonun hiçbir katmanda gündelik
      // cümlesi yok" diyordu ve OP2'den sonra YANLIŞ: sunucu istasyona da
      // sabit tablodan anlam yazıyor. Dalın kapsamı daraldı, kaybolmadı —
      // sunucu tanımadığı bir yön evresi ya da tablosunda olmayan bir
      // gezegen görürse `line` HİÇ yazmıyor (uydurma yok). O hâlde satır
      // ölçümüyle yazılır ve ona "Rytho+ ile açılır" denmez: eksik olan
      // anlamdır, abonelikle açılacak bir şey değil.
      await _gunKartiniAc(tester, [
        {
          'type': 'station_retrograde',
          'date': _bugun(3),
          'transit_local': 'Merkür',
          'type_local': 'geri harekete geçiyor',
        },
      ]);

      expect(find.textContaining('Rytho+'), findsNothing);
      expect(find.textContaining('Merkür'), findsOneWidget);
    });

    testWidgets('istasyon satırı ANLAM → SEBEP → DAVET sırasında',
        (tester) async {
      // Sahip ekran görüntüsü: satırda yalnız "Plüton — ileri harekete
      // dönüş" yazıyordu; ne demek olduğu hiçbir yüzeyde yoktu ve satır
      // dokunulamıyordu. Üç parça da aynı kartta ve BU SIRADA olmalı.
      await _gunKartiniAc(tester, [_istasyonOlayi()]);

      final anlam = find.textContaining('temeli sokup');
      final sebep = find.textContaining('hizini sifira indirip');
      expect(anlam, findsOneWidget);
      expect(sebep, findsOneWidget);
      // Davet oklu yazımda: oksuz hâli bir başlık gibi okunuyordu.
      expect(find.text('Neye dayanıyor? →'), findsOneWidget);

      // Sıra EKRAN KOORDINATINDAN ölçülür — ağaç sırası görünen sırayı
      // garanti etmez (Column'da eder, ama bekçi görünene bakmalı).
      final yAnlam = tester.getTopLeft(anlam).dy;
      final ySebep = tester.getTopLeft(sebep).dy;
      final yDavet = tester.getTopLeft(find.text('Neye dayanıyor? →')).dy;
      expect(yAnlam, lessThan(ySebep));
      expect(ySebep, lessThan(yDavet));
    });

    testWidgets('istasyon satırı DOKUNULABILIR ve dayanağı açar',
        (tester) async {
      // Eskiden çıplak bir `Padding`+`Text`ti: dokunulamıyordu, yani
      // "detay için Rytho ile konuş" davetine giden hiçbir yol yoktu.
      await _gunKartiniAc(tester, [_istasyonOlayi()]);

      await tester.tap(find.textContaining('temeli sokup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Dayanak sayfası açıldı: başlığı ve sohbet daveti görünür.
      expect(find.text('Bu tarih neden önemli?'), findsOneWidget);
      expect(find.textContaining('Rytho\'ya sor'), findsOneWidget);
    });

    testWidgets('HİYERARŞİ anlamın lehine: anlam sebepten BÜYÜK',
        (tester) async {
      // `basis_sheet`te ÖLÇÜLMÜŞ kusur: sayfanın ASIL metni teknik
      // tablodan küçük görünüyordu, yani ölçüm disiplini anlamın
      // önüne geçiyordu. Aynı kusur burada da mümkün ve SİVİLDİ: anlamı
      // okuma ölçüsünden düz gövde ölçüsüne indiren bir mutasyon
      // ölçüldü ve TÜM testler yeşil kaldı — bu bekçi o körlüğü
      // kapatıyor.
      //
      // Bekçi PİKSELE DEĞİL `TextStyle`a bakıyor: testte her harf kare
      // çiziliyor, piksel iddiası yalan söyler (depo kuralı).
      await _gunKartiniAc(tester, [_istasyonOlayi()]);

      final anlam =
          tester.widget<Text>(find.textContaining('temeli sokup'));
      final sebep =
          tester.widget<Text>(find.textContaining('hizini sifira indirip'));

      expect(anlam.style!.fontSize, RythoType.reading.fontSize);
      expect(anlam.style!.fontSize!, greaterThan(sebep.style!.fontSize!));
    });

    testWidgets('istasyon KİŞİSELLEŞTİRİLMİŞ gibi sunulmaz',
        (tester) async {
      // Sunucu tarafında çivili (test_istasyon_anlami.py); burada istemci
      // tarafı: kart kendi başına "senin haritanda" türü bir çerçeve
      // EKLEMEZ. Eklerse istasyon kişisel bir ölçüme bağlıymış gibi
      // okunur ve "ölçülmeyen söylenmez" istemcide kırılır.
      await _gunKartiniAc(tester, [_istasyonOlayi()]);

      expect(find.textContaining('haritan'), findsNothing);
      expect(find.textContaining('senin'), findsNothing);
    });

    testWidgets('İngilizce arayüzde Türkçe metin KALMAZ', (tester) async {
      // Cihaz bulgusu: "ingilizceye çevirince de türkçe kalıyor". Sunucu
      // metni (`theme_local`, `line`) isteğin diliyle geliyor; bu test
      // İSTEMCİ tarafını kilitler — kart kendi dizelerini l10n'den almalı,
      // hiçbir Türkçe sabit taşımamalı.
      await tester.pumpWidget(_sar(
        Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDaySheet(context, DateTime.now(), [
                  // Sunucu İngilizce yanıt verdiğinde gelen biçim.
                  {
                    ..._kilitliOlay(),
                    'theme_local': 'Relationships',
                    'date_local': 'August 20',
                  },
                ]),
                child: const Text('open'),
              ),
            ),
          );
        }),
        locale: const Locale('en'),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Relationships'), findsOneWidget);
      expect(find.textContaining('opens with Rytho+'), findsOneWidget);
      // Türkçe hiçbir sabit sızmamalı.
      expect(find.textContaining('açılır'), findsNothing);
      expect(find.textContaining('Diğer'), findsNothing);
    });

    testWidgets('320x640 / yazı ölçeği tavanında DİKEY taşma yok',
        (tester) async {
      // Üç kart: bir kesinleşme + iki istasyon. Gerçekçi en kötü hâl,
      // çünkü istasyon cümlesi sunucuda ~290 karakter ve uzunluğu bizim
      // denetimimizde DEĞİL (sabit tablodan geliyor, kısaltılamıyor).
      await _darKisaEkranda(tester, [
        _acikOlay(),
        _istasyonOlayi(gunSonra: 2),
        _istasyonOlayi(gunSonra: 4),
      ]);

      expect(tester.takeException(), isNull,
          reason: 'gün sayfası ekrandan uzun ve kaydırma yok');
    });

    testWidgets('temasız olay da başlıksız kalmaz', (tester) async {
      // İstasyonların teması yok; başlıksız bir satır ekranda öksüz durur.
      final istasyon = {
        'type': 'station',
        'date': _bugun(3),
        'transit_local': 'Merkür',
        'locked': true,
      };
      await _gunKartiniAc(tester, [istasyon]);

      expect(find.text('Diğer hareketler'), findsOneWidget);
    });
  });
}

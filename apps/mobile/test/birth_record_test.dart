import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/birth_record.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/profile/birth_record_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;

/// Dogum kaydinin iki degismezi.
///
/// ## 1. Bayat Buyuk Uclu birakilmaz
///
/// `sunSign` / `moonSign` / `ascendant` profilde ONBELLEKLENMIS degerler.
/// Kullanici dogum tarihini duzeltir de harita cagrisi basarisiz olursa,
/// dokumanda *yeni tarih* ile *eski burclar* yan yana kalir. Hata cikmaz,
/// ekran calisir — sadece yalan soyler. Bu tam olarak bu projede tekrar
/// tekrar yakalanan sessiz kusur turu.
///
/// Silmek guvenli: okumalar bu alanlardan degil ham dogum verisinden
/// hesaplaniyor (`birthPayload`), ilk basarili cagrida geri geliyorlar.
///
/// ## 2. Degismeyen form kaydedilmez
///
/// `sameAs` kaydet butonunun etkinligini belirliyor. Yanlis olursa ya
/// gereksiz ag cagrisi olur ya da kullanici degisikligini kaydedemez.
///
/// ## 3. 12:00 uydurulmaz (D5)
///
/// Profil duzeltme ekrani saati bilinmeyen kaydi acarken `12:00`
/// uyduruyor, kullanici kutuyu kaldirip saat secmeden kaydedince o saat
/// gercek gibi gidiyordu. `_saat` artik null olabilir ve Kaydet
/// `dogumSaatiGecerli` kapisindan gecer; cinsiyet varsayilani `female`
/// degil `unspecified` (secilmeyen beyan edilmez).

final _tr = AppLocalizationsTr();

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// Ekrani profil akisi override'iyla pompalar (Firebase yok).
Future<void> _ekran(WidgetTester tester, Map<String, dynamic> profil) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileProvider.overrideWith((ref) => Stream.value(profil)),
    ],
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const BirthRecordScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump(RythoMotion.base);
}

GoldButton _kaydet(WidgetTester tester) =>
    tester.widget<GoldButton>(find.widgetWithText(GoldButton, _tr.save));

BirthRecord _ornek({
  DateTime? tarih,
  String saat = '04:30',
  String sehir = 'Ankara',
  String cinsiyet = 'male',
}) =>
    BirthRecord(
      date: tarih ?? DateTime(1988, 3, 7),
      time: saat,
      city: sehir,
      gender: cinsiyet,
    );

void main() {
  group('bayat Buyuk Uclu', () {
    test('harita gelmezse burclar SILINIR, eski deger kalmaz', () {
      final veri = birthWriteData(_ornek(), uid: 'u1', chart: null);

      // Kritik: string DEGIL. Bir string kalsaydi eski burc yeni tarihle
      // yan yana durur ve kimse fark etmezdi.
      expect(veri['sunSign'], isA<FieldValue>());
      expect(veri['moonSign'], isA<FieldValue>());
      expect(veri['ascendant'], isA<FieldValue>());

      // Dogum verisi yine de yazilir — kullanici duzeltmesini kaybetmez.
      expect(veri['birthDate'], '1988-03-07');
      expect(veri['birthTime'], '04:30');
    });

    test('harita gelirse burclar tazelenir', () {
      final veri = birthWriteData(_ornek(), uid: 'u1', chart: const {
        'sun_sign': 'Balik ♓',
        'moon_sign': 'Aslan ♌',
        'ascendant': 'Kova ♒',
      });

      expect(veri['sunSign'], 'Balik ♓');
      expect(veri['moonSign'], 'Aslan ♌');
      expect(veri['ascendant'], 'Kova ♒');
    });

    test('harita eksik alanla gelirse o alan SILINIR', () {
      // Backend bir alani dondurmezse de bayat deger birakmamaliyiz.
      final veri = birthWriteData(_ornek(),
          uid: 'u1', chart: const {'sun_sign': 'Balik ♓'});

      expect(veri['sunSign'], 'Balik ♓');
      expect(veri['moonSign'], isA<FieldValue>());
      expect(veri['ascendant'], isA<FieldValue>());
    });
  });

  group('tarih bicimi', () {
    test('tek haneli ay ve gun sifirla doldurulur', () {
      expect(_ornek(tarih: DateTime(2001, 1, 5)).dateText, '2001-01-05');
    });

    test('profilden okuma: bozuk tarih varsayilan verir, cokmez', () {
      final k = BirthRecord.fromProfile({'birthDate': 'bilmemne'});
      expect(k.dateText, '2000-01-01');
    });

    test('profilden okuma: gercek deger korunur', () {
      final k = BirthRecord.fromProfile({
        'birthDate': '1988-03-07',
        'birthTime': '04:30',
        'birthCity': 'Ankara',
        'gender': 'male',
      });
      expect(k.dateText, '1988-03-07');
      expect(k.time, '04:30');
      expect(k.city, 'Ankara');
      expect(k.gender, 'male');
    });

    test('profil bossa saat BILINMIYOR sayilir', () {
      // Revize B1: eski davranis 12:00 varsayip ogle dogumu uyduruyordu.
      // Artik null = "saat bilinmiyor"; sunucu BaZi'de saat sutununu hic
      // kurmaz ve bunu okumada beyan eder.
      final k = BirthRecord.fromProfile(null);
      expect(k.time, isNull);
      expect(k.city, 'Istanbul');
    });

    test('profil bossa cinsiyet `unspecified` — `female` uydurulmaz', () {
      // D0: sunucu uydurmuyor, istemci uyduruyordu. Cinsiyet yazmamis
      // kullanici formu acinca "kadin" secili goruyor ve kaydedince o
      // beyan gidiyordu.
      expect(BirthRecord.fromProfile(null).gender, 'unspecified');
      expect(BirthRecord.fromProfile({'gender': 'male'}).gender, 'male');
    });

    test('saatAyristir: HH:mm → TimeOfDay; null/bozuk → null (12:00 degil)',
        () {
      expect(saatAyristir('04:30'), const TimeOfDay(hour: 4, minute: 30));
      expect(saatAyristir('23:59'), const TimeOfDay(hour: 23, minute: 59));
      expect(saatAyristir(null), isNull);
      expect(saatAyristir('bozuk'), isNull);
      expect(saatAyristir('25:00'), isNull);
      // saatMetni ile gidis-donus.
      expect(saatMetni(saatAyristir('07:05')), '07:05');
    });
  });

  group('duzeltme ekrani — saat kapisi', () {
    const saatsiz = <String, dynamic>{
      'birthDate': '1988-03-07',
      'birthCity': 'Ankara',
      'gender': 'male',
    };

    testWidgets('saatsiz kayit: kutu isaretli, saat "—"; kutu kaldirilip '
        'saat secilmeyince Kaydet KAPALI; kutu geri gelince ACIK',
        (tester) async {
      await _ekran(tester, saatsiz);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue,
          reason: 'saat yoksa "bilmiyorum" isaretli acilir');
      expect(find.text('12:00'), findsNothing, reason: '12:00 uydurulmaz');
      expect(_kaydet(tester).onPressed, isNull, reason: 'degisiklik yok');

      // Baska bir alani degistir ki "degisti" tek basina kapiyi acsin:
      // kapinin ETKISI ancak degismis formda gorunur.
      await tester.tap(find.text(_tr.genderFemale));
      await tester.pump(RythoMotion.base);
      expect(_kaydet(tester).onPressed, isNotNull,
          reason: 'cinsiyet degisti, saat bilinmiyor → kaydedilebilir');

      // Kutuyu kaldir: "biliyorum" dendi ama saat secilmedi.
      await tester.tap(find.byType(Checkbox));
      await tester.pump(RythoMotion.base);
      expect(find.text('12:00'), findsNothing);
      expect(_kaydet(tester).onPressed, isNull,
          reason: 'eski hal burada ACIKTI ve 12:00 gidiyordu');

      await tester.tap(find.byType(Checkbox));
      await tester.pump(RythoMotion.base);
      expect(_kaydet(tester).onPressed, isNotNull);
    });

    testWidgets('saatli kayit: 04:30 gorunur; kutu isaretlenince "—" ve '
        'Kaydet acik (saat silindi = degisiklik)', (tester) async {
      await _ekran(tester, {...saatsiz, 'birthTime': '04:30'});
      expect(find.text('04:30'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(_kaydet(tester).onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump(RythoMotion.base);
      expect(find.text('04:30'), findsNothing);
      expect(find.text(_tr.wizardTimeUnknownNote), findsOneWidget,
          reason: 'kaybi soyleyen not (Yukselen ve evler) burada da');
      expect(_kaydet(tester).onPressed, isNotNull);
    });

    testWidgets('cinsiyet yazilmamis kayit: hicbir segment secili DEGIL',
        (tester) async {
      await _ekran(tester, {'birthDate': '1988-03-07', 'birthCity': 'Ankara'});
      // `unspecified` segmenti seçili: kullanıcı "Belirtmedim" görür,
      // "Kadın" değil. Seçili segment = dolgulu AnimatedContainer'ın metni.
      final dolgulu = find.byWidgetPredicate((w) =>
          w is AnimatedContainer &&
          (w.decoration as BoxDecoration?)?.color != null);
      expect(dolgulu, findsOneWidget);
      expect(
          find.descendant(
              of: dolgulu, matching: find.text(_tr.genderUnspecified)),
          findsOneWidget,
          reason: 'secili segment "Belirtmedim" olmali, "Kadin" degil');
    });

    test('kaynak: 12:00 yalniz seçicinin acilis konumu; female uydurulmaz; '
        'form parcalari TEK dil', () {
      final ekran = _yorumsuz('lib/features/profile/birth_record_screen.dart');
      final cekirdek = _yorumsuz('lib/core/birth_record.dart');
      final onIki = ekran
          .split('\n')
          .where((s) => s.contains('TimeOfDay(hour: 12'))
          .toList();
      expect(onIki, hasLength(1), reason: '12:00 tek yerde: seçici açılışı');
      expect(onIki.single, contains('initialTime:'));
      expect(ekran, contains('dogumSaatiGecerli('));
      expect(ekran, isNot(contains("?? 'female'")));
      expect(cekirdek, isNot(contains("?? 'female'")));
      expect(ekran, isNot(contains('_AlanSatiri')));
      expect(ekran, isNot(contains('GestureDetector(')));
      for (final parca in ['SecimSatiri(', 'CinsiyetSecici(', 'SaatBilinmiyorKutusu(']) {
        expect(ekran, contains(parca), reason: '$parca dogum_formu\'ndan');
      }
    });
  });

  group('degisiklik tespiti', () {
    test('ayni kayit degismis sayilmaz', () {
      expect(_ornek().sameAs(_ornek()), isTrue);
    });

    test('sehirdeki bosluk fark yaratmaz', () {
      // Aksi hâlde imlecin biraktigi bir bosluk "degisti" sayilir ve
      // gereksiz bir harita hesabi tetiklerdi.
      expect(_ornek(sehir: '  Ankara ').sameAs(_ornek()), isTrue);
    });

    test('saat degisince degismis sayilir', () {
      expect(_ornek(saat: '05:30').sameAs(_ornek()), isFalse);
    });

    test('tarih degisince degismis sayilir', () {
      expect(_ornek(tarih: DateTime(1988, 3, 8)).sameAs(_ornek()), isFalse);
    });

    test('cinsiyet degisince degismis sayilir', () {
      expect(_ornek(cinsiyet: 'female').sameAs(_ornek()), isFalse);
    });
  });
}

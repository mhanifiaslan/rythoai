// "Bu sinyal nereden geliyor?" alt-sayfasinin bekcileri (OP5-turu).
//
// Bu sayfanin BUGUNE KADAR HIC widget testi yoktu (olculdu: depodaki
// testlerde `showSignalBasisSheet` / `basisSheetTitle` / `basisFootnote` /
// `card_text` icin SIFIR eslesme). Yeniden siralanmasiyla birlikte bes
// davranis civilendi: tekrarin yoklugu, katlanir bolmenin VARSAYILAN
// KAPALI dogmasi, sira (anlam ustte / sohbet kapisi altta), kaydirma
// sarmalayicisi ve her IKI giris yolunun sohbet kapisini beslemesi.
// Artinda bir altinci grup var ("Token ve kapi") ve o TASARIMLA DEGIL
// MUTASYONLA kazanildi -- gerekcesi kendi yorumunda.
//
// Sahip bulgusu (cihaz ekran goruntusu): sayfada AYNI YORUM IKI KEZ
// yaziliydi, aralarinda teknik tablo, en altta da kendi kendine reklam
// gibi duran bir dipnot. Kok neden olculdu: `sky_screen` `card_text`i
// `insight`e esitliyor, `basis_sheet` ise `card_text`i USTTE,
// `insight`i ALTTA "Rytho'nun yorumu" kutusunda basiyordu.
//
// ⚠️ Silinmesi gereken ALTTAKI kutuydu, ustteki paragraf DEGIL: ustteki
// bilincli bir cihaz bulgusudur (R3-1 — kullanici hangi cumleye "neden"
// diye sorduysa sayfa O CUMLEYLE acilir). Asagidaki ilk bekci bu yuzden
// "yorum ekranda TEK KEZ" diyor, "yorum yok" demiyor.
//
// ⚠️ Bu dosya GORSEL iddia kurmaz. Flutter testinde her harf punto
// genisliginde KARE cizilir; piksel/renk/ekran-goruntusu kaniti yalan
// soyler. Olculen sey YAPIDIR: widget varligi/yoklugu ve siralama (dy).
//
// ⚠️ Capalar bilerek cesitli ve hicbiri tek bir Turkce kelimeye bagli
// degil: iddialar ya kod tanimlayicisina, ya l10n dizesinin KENDISINE
// (elle yazilmis kopyasina degil), ya da yapisal sayima dayali.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/basis_sheet.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

/// En dar hedef cihaz (Android 320 dp) — emsal: `dar_ekran_test`.
const double kDarGenislik = 320;
const double kDarYukseklik = 480;

/// Sunucunun GERCEK teknik satiri (backend `test_signals` ile civili dize).
const _kTeknik = 'Satürn, natal Ay ile Kare açısını 2 gün sonra '
    '(18 Ağustos) kesinleştiriyor.';

/// Abone yorumu — gundelik dilde, teknik satirdan FARKLI.
const _kYorum = 'Bu hafta sınırlarını yeniden çizmek isteyeceksin; '
    'direnç geçici.';

/// Tek sinyal sozlugu.
///
/// `card_text`i cagiranlarin kurdugu gibi kurar: yorum varsa o, yoksa
/// `headline`. `headline`in `technical`e esit olmasi UYDURMA DEGIL sunucu
/// davranisidir (`backend/services/prompts`: `insan = teknik`, bekcisi
/// `backend/tests/test_signals.py::test_kart_yedegi_durust_teknik_satir`).
Map<String, dynamic> _sinyal({String? yorum}) {
  final kart = (yorum != null && yorum.isNotEmpty) ? yorum : _kTeknik;
  return {
    'headline': _kTeknik,
    // Null-aware oge: `yorum` yoksa `insight` ANAHTARI HIC GIRMEZ. Bos
    // dize yazmakla ayni sey degil -- sunucu da alani atliyor ve
    // `basis_sheet` "alan yoksa satiri atla" kuralini o hal uzerinde
    // calistiriyor.
    'insight': ?yorum,
    'card_text': kart,
    'technical': _kTeknik,
    'transit_local': 'Satürn',
    'movement_local': 'yaklaşıyor',
    'natal_local': 'Ay',
    'natal_sign_local': 'Yengeç',
    'natal_house': 4,
    'aspect_local': 'Kare',
    'orb': 1.2,
    'exact_on_local': '18 Ağustos',
  };
}

/// Alt-sayfayi GERCEKTEN acar: `showModalBottomSheet` bir `Navigator`
/// ister, dolayisiyla sayfa dogrudan `pumpWidget`e verilemez.
Future<void> _sayfaAc(
  WidgetTester tester, {
  String? yorum = _kYorum,
  bool sorKapisi = true,
  double genislik = 420,
  double yukseklik = 900,
  double olcek = 1.0,
  bool azaltilmisHareket = false,
}) async {
  tester.view.physicalSize = Size(genislik * 3, yukseklik * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = olcek;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(MaterialApp(
    locale: const Locale('tr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('tr'), Locale('en')],
    theme: buildRythoTheme(),
    // `MaterialApp.builder`in cocugu NAVIGATOR'un kendisi, o yuzden
    // buradaki `MediaQuery` modal rotalari da kapsar; alt-sayfa ayri bir
    // rota oldugu icin `home`un icine konan bir override onu GORMEZDI.
    builder: azaltilmisHareket
        ? (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            )
        : null,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSignalBasisSheet(context, _sinyal(yorum: yorum),
              onAsk: sorKapisi ? () {} : null),
          child: const Text('ac'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ac'));
  // Modal gecisi süreli: `pumpAndSettle` yerine adimli bekleme (depo
  // kurali — sonsuz animator barindiran agaclarda settle donmez).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Katlanir bolmenin basligi: `signalWhy` + ok. Dize elle yazilmaz,
/// l10n'un KENDISINDEN okunur.
Finder get _katlanirBaslik => find.textContaining(_tr.signalWhy);

/// Katlanir bolmenin kendisi. `tester.widget<T>` birden fazla eslesmede
/// FIRLATIR, yani bu capa teklige kendiliginden bagli — agaca ikinci bir
/// `AnimatedSize` girerse bekci sessizce yanlis widget'i okumaz, patlar.
Finder get _bolme => find.byType(AnimatedSize);

Future<void> _bolmeyiAc(WidgetTester tester) async {
  await tester.tap(_katlanirBaslik);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

double _dy(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  group('Tekrar: ayni cumle iki kez basilmaz', () {
    testWidgets('abone yorumu ekranda TEK KEZ gecer', (tester) async {
      await _sayfaAc(tester);
      // Eski sayfada bu dize hem ustte (`card_text`) hem altta
      // ("Rytho'nun yorumu" kutusu, `insight`) basiliyordu.
      expect(find.text(_kYorum), findsOneWidget);
      // Katlanir bolme acilinca da ikinci bir kopya DOGMAZ.
      await _bolmeyiAc(tester);
      expect(find.text(_kYorum), findsOneWidget);
    });

    testWidgets('yorum YOKKEN olcum cumlesi de tek kez gecer',
        (tester) async {
      // Tekrarin ikinci hali: `insight` bossa `card_text` `headline`a
      // duser ve sunucuda `headline == technical`. Yani okuma slotu ZATEN
      // olcum cumlesidir; ayrica bir kaynak satiri basmak ayni dizeyi
      // ikilerdi.
      await _sayfaAc(tester, yorum: null);
      expect(find.text(_kTeknik), findsOneWidget);
      await _bolmeyiAc(tester);
      expect(find.text(_kTeknik), findsOneWidget);
    });

    testWidgets('yorum ve olcum FARKLIYKEN ikisi de gorunur',
        (tester) async {
      // Disiplin korunuyor: dayanak gizlenmiyor, yalnizca tekrar bitti.
      await _sayfaAc(tester);
      expect(find.text(_kYorum), findsOneWidget);
      expect(find.text(_kTeknik), findsOneWidget);
    });
  });

  group('Teknik katman: ayni sayfada, VARSAYILAN KAPALI (K1)', () {
    testWidgets('ilk acilista olcum satirlari ve dipnot YOK',
        (tester) async {
      await _sayfaAc(tester);
      expect(_katlanirBaslik, findsOneWidget,
          reason: 'katlanir bolmenin kapisi gorunmuyor');
      // Satir ETIKETLERI `_Satir` icinde buyuk harfe cevriliyor.
      expect(find.text(_tr.basisSky.toUpperCase()), findsNothing);
      expect(find.text(_tr.basisAspect.toUpperCase()), findsNothing);
      expect(find.text(_tr.basisOrb.toUpperCase()), findsNothing);
      // Kaynak dipnotu da bolmenin ICINDE: dayanagi SORAN gorur, herkese
      // basilmaz (sahip karari — disiplinin reklami kalkar).
      expect(find.text(_tr.basisFootnote), findsNothing);
    });

    testWidgets('dokununca aciliyor ve satirlar geliyor', (tester) async {
      await _sayfaAc(tester);
      await _bolmeyiAc(tester);
      expect(find.text(_tr.basisSky.toUpperCase()), findsOneWidget);
      expect(find.text(_tr.basisNatal.toUpperCase()), findsOneWidget);
      expect(find.text(_tr.basisAspect.toUpperCase()), findsOneWidget);
      expect(find.text(_tr.basisOrb.toUpperCase()), findsOneWidget);
      expect(find.text(_tr.basisExact.toUpperCase()), findsOneWidget);
      // Olculen degerler de geliyor — etiketler bos kabuk degil.
      expect(find.text('1.2°'), findsOneWidget);
      expect(find.textContaining(_tr.basisHouse(4)), findsOneWidget);
      expect(find.text(_tr.basisFootnote), findsOneWidget);
    });

    testWidgets('tekrar dokununca kapaniyor', (tester) async {
      await _sayfaAc(tester);
      await _bolmeyiAc(tester);
      await _bolmeyiAc(tester);
      expect(find.text(_tr.basisSky.toUpperCase()), findsNothing);
      expect(find.text(_tr.basisFootnote), findsNothing);
    });
  });

  group('Sira: anlam ustte, sohbet kapisi EN ALTTA', () {
    testWidgets('yorum katlanir bolmenin USTUNDE', (tester) async {
      await _sayfaAc(tester);
      expect(_dy(tester, find.text(_kYorum)),
          lessThan(_dy(tester, _katlanirBaslik)));
    });

    testWidgets('"Rytho\'ya sor" dipnotun ve bolmenin ALTINDA',
        (tester) async {
      await _sayfaAc(tester);
      final sor = find.textContaining(_tr.signalAsk);
      expect(sor, findsOneWidget);
      expect(_dy(tester, sor), greaterThan(_dy(tester, _katlanirBaslik)),
          reason: 'birincil eylem alt kenarda olmali (design-system §9c)');
      await _bolmeyiAc(tester);
      expect(_dy(tester, sor),
          greaterThan(_dy(tester, find.text(_tr.basisFootnote))),
          reason: 'dipnot acilinca dugme yine en altta kalmali');
    });

    testWidgets('onAsk gecmezse dugme hic cizilmez', (tester) async {
      // Dugmenin kosullu olmasi kendisi bir kusur DEGIL; kusur onu
      // besleyen cagri yolunun `onAsk` gecirmemesiydi (asagidaki kaynak
      // bekcisi onu civiliyor).
      await _sayfaAc(tester, sorKapisi: false);
      expect(find.textContaining(_tr.signalAsk), findsNothing);
    });
  });

  group('Kaydirma: bolum eklendi, sessiz kirpilma riski kapatildi', () {
    testWidgets('sayfa bir kaydirma sarmalayicisinin icinde',
        (tester) async {
      await _sayfaAc(tester);
      expect(
          find.ancestor(
              of: find.text(_tr.basisSheetTitle),
              matching: find.byType(SingleChildScrollView)),
          findsOneWidget,
          reason: 'kardes sayfada 131 px SESSIZ kirpilma olculmustu');
    });

    testWidgets('320x480 / yazi olcegi tavaninda tasma yok — kapali',
        (tester) async {
      await _sayfaAc(tester,
          genislik: kDarGenislik,
          yukseklik: kDarYukseklik,
          olcek: kMaxTextScale);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320x480 / yazi olcegi tavaninda tasma yok — acik',
        (tester) async {
      await _sayfaAc(tester,
          genislik: kDarGenislik,
          yukseklik: kDarYukseklik,
          olcek: kMaxTextScale);
      await _bolmeyiAc(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Sohbet kapisi HER IKI giris yolunda da gecer', () {
    // Kusur yapisaldi: `sky_screen` sayfayi IKI yerden aciyordu (kart
    // dokunusu + sabah bildirimi niyeti) ve bildirim yolu `onAsk`
    // GECIRMIYORDU. `basis_sheet` dugmeyi kosullu cizdigi icin
    // bildirimden gelen kullanici sohbet kapisini HIC gormuyordu.
    //
    // Onarim cagriyi TEK yardimciya indirdi. Bekci bu yuzden cagri
    // SAYISINI olcuyor: ikinci bir ciplak cagri geri dogarsa kirmizi
    // olur. Capa `showSignalBasisSheet` tanimlayicisi — Turkce kelime
    // degil.
    String yorumsuz(String yol) => File(yol)
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((s) => !s.trimLeft().startsWith('//'))
        .join('\n');

    test('sky_screen sayfayi TEK yerden aciyor ve onAsk geciyor', () {
      final k = yorumsuz('lib/features/sky/sky_screen.dart');
      expect(RegExp(r'showSignalBasisSheet\(').allMatches(k).length, 1,
          reason: 'ikinci bir cagri yolu onAsk\'i atlayabilir');
      final cagri = RegExp(
              r'showSignalBasisSheet\((?:[^()]|\([^()]*\))*onAsk:',
              dotAll: true)
          .hasMatch(k);
      expect(cagri, isTrue, reason: 'tek cagri onAsk gecirmiyor');
      // Bildirim yolu da ayni yardimciyi cagirmali.
      expect(k.contains('_sinyalDayanaginiAc(context, sinyaller[indeks])'),
          isTrue,
          reason: 'bildirim niyeti ortak yoldan gecmiyor');
    });

    test('takvim yolu kendi onAsk\'ini geciriyor', () {
      // Ucuncu giris yolu (takvim gunu) baska bir pakette; burada yalniz
      // dugmenin oradan da beslendigi dogrulaniyor.
      final k = yorumsuz('lib/features/sky/calendar_strip.dart');
      expect(
          RegExp(r'showSignalBasisSheet\((?:[^()]|\([^()]*\))*onAsk:',
                  dotAll: true)
              .hasMatch(k),
          isTrue);
    });
  });

  // Asagidaki uc bekci MUTASYONLA kazanildi, tasarimla degil: ilk turda
  // `RythoType.reading` -> `RythoText.body(13, lilac)` ve
  // `reduceMotion(context) ? Duration.zero :` -> ciplak `RythoMotion.base`
  // mutasyonlarinin IKISI DE YESIL gecti. Yani hiyerarsi karari ve
  // erisilebilirlik kapisi CIVISIZDI; o iki gerileme sessiz olurdu.
  //
  // Iddia yine GORSEL DEGIL — punto, renk, piksel okunmuyor. Widget'in
  // TASIDIGI token nesnesi karsilastiriliyor (`TextStyle` ve `Duration`
  // deger esitligi tasir). Token'in kendi tanimi degisirse iki taraf
  // birlikte kayar: bekci yalnizca token KULLANILMAYI BIRAKTIGINDA
  // kirmizi olur, ki civilenmek istenen tam olarak bu.
  group('Token ve kapi', () {
    testWidgets('yorum OKUMA token\'iyla ciziliyor', (tester) async {
      await _sayfaAc(tester);
      expect(tester.widget<Text>(find.text(_kYorum)).style, RythoType.reading,
          reason: 'sayfanin ASIL metni govde puntosuna dusmus — hiyerarsi '
              'anlamin aleyhine');
    });

    testWidgets('katlanir bolme reduce-motion kapisindan geciyor',
        (tester) async {
      await _sayfaAc(tester, azaltilmisHareket: true);
      expect(tester.widget<AnimatedSize>(_bolme).duration, Duration.zero,
          reason: 'vestibuler rahatsizlik bir sus tercihi degil '
              '(widgets/motion.dart)');
    });

    testWidgets('kapi kapaliyken sure TOKEN\'dan geliyor', (tester) async {
      // Ustteki bekci TEK BASINA yetmez: ciplak yazilmis bir
      // `Duration(milliseconds: 220)` de kapi acikken `Duration.zero`
      // dondurulebilir. Ciplak sure/egri yasagi (design-system.md:155)
      // ancak kapi KAPALIYKEN degerin token oldugu gorulerek olculur.
      await _sayfaAc(tester);
      expect(tester.widget<AnimatedSize>(_bolme).duration, RythoMotion.base);
    });
  });
}

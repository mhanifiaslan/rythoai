// 48-turu bekcileri: ANLAM once, OLCUM sonra.
//
// Sahibin tarifi: "acilar, elementler, sinastriler ONCE TEKNIK DETAY
// veriyor... kullanicilar camasir makinesi kilavuzu muamelesi yapiyor."
//
// Urun bunu kendi metninde ITIRAF etmiyordu, YANLIS BEYAN ediyordu: nokta
// alt-sayfasinin dipnotu (`pointSheetFootnote`) "Altindaki iki cumle, o
// gezegenin klasik anlami ile bulundugu ev alanini birlestirir" diyordu ve
// o iki cumle hicbir zaman birlestirilmiyordu — yan yana basiliyordu.
// (Bu dosyanin ilk yaziminda dipnot "bu satirlar olcumdur, kendisi yorum
// degildir" diye alintilanmisti; o cumle depoda HIC olmadi. Yanlis gerekce
// kusurdur, duzeltildi.) Asagidaki bekciler iki seyi civiliyor:
//
//  1. Her yuzeyde anlam cumlesi olcumun USTUNDE. Iddia GORSEL DEGIL
//     YAPISAL: piksel/renk iddiasi kurulmuyor, yalniz widget sirasi
//     (dy) ve varlik/yokluk olculuyor. Flutter testinde her harf KARE
//     cizilir, yani metinli kanit karesi ya da piksel karsilastirmasi
//     YALAN SOYLER — bu dosya hicbirini yapmiyor.
//  2. Iki sabit cumle artik YAN YANA BASILMIYOR, birlesiyor. 14 gezegen
//     metni ile 12 ev metni ikiser ikiser secildigi icin 168 yerlesimin
//     tamami 26 dizeden ikisiyle anlatiliyordu: teknik bilgi carpilmiyor,
//     TOPLANIYORDU.
//
// ⚠️ Capalar BILEREK cesitli: tek bir Turkce kelimeye guvenen bekci
// kordur (bu depoda "guncelleme" capasi ASCII yazimla gecildi). Her
// iddia ya bir kod tanimlayicisina, ya bir l10n dizesinin KENDISINE
// (elle yazilmis kopyasina degil), ya da bagimsiz birkac isarete bagli.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/atlas/atlas_detail_screens.dart';
import 'package:rytho/features/atlas/chart_inspector_screen.dart'
    show ChartInspectorMode, liderGorunurAci, natalAnlamYuku;
import 'package:rytho/l10n/app_localizations.dart';
// Yazı ölçeği tavanı UYGULAMADAN okunur, elle 1.3 yazılmaz: tavan
// değişirse bekçi onunla birlikte değişsin (emsal: dar_ekran_test).
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/widgets/chart/chart_data.dart';
import 'package:rytho/widgets/chart/wheel_painter.dart'
    show WheelAspectFilter;

final _tr = lookupAppLocalizations(const Locale('tr'));
final _en = lookupAppLocalizations(const Locale('en'));

/// Kaynak bekcisi BIR SEYIN YOKLUGUNU ararken kendi aciklama yorumuna
/// takilmasin: tam satir yorumlari ve `///` belgeleri atilir.
///
/// Bu tuzak bu depoda gercekten patladi (build kapisi kendi manifest
/// yorumuna, davet sayfasi testi kendi HTML yorumuna takildi). Burada da
/// gerekli: `_AnlamKatmani`'nin belgesi `natalReportProvider` adini
/// GECIYOR ve asagidaki bekci tam o adin KODDA olmadigini ariyor.
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Widget _sar(Widget child, {String dil = 'tr'}) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(dil),
      home: child,
    );

/// Yildiz alani ve `AstrolabeSpinner` surekli animasyonlu —
/// `pumpAndSettle` hicbir zaman donmez.
///
/// 600 ms: detay iskeleti bloklari `RythoReveal(index:)` ile kademeli
/// acar ve flutter_animate gecikmeyi `Future.delayed` ile kurar — 8. blok
/// 7 × 70 = 490 ms sonra baslar. 400 ms'lik bekleme D6'da sohbet kapisi
/// eklenince (7. blok) "A Timer is still pending" ile dusuyordu; urun
/// hatasi degil, bekleme gecikmenin tavanini asmali.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// `GradillegentProgressBar` benzeri cubuklar her satiri gecikmeyle
/// baslatir; beklenmezse agac sokulurken zamanlayici acik kalir ve test
/// "A Timer is still pending" diye duser — urun hatasi degil.
Future<void> _cubuklariBekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
}

/// Alt-sayfayi gercekten acar (dokunusla), cunku `showModalBottomSheet`
/// bir `Navigator` ister.
Future<void> _sayfaAc(
    WidgetTester tester, void Function(BuildContext) ac) async {
  await tester.pumpWidget(_sar(Scaffold(
    body: Builder(
      builder: (context) => TextButton(
          onPressed: () => ac(context), child: const Text('ac')),
    ),
  )));
  await tester.tap(find.text('ac'));
  await _bekle(tester);
}

double _dy(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

/// `liderGorunurAci` icin en kucuk gercek veri: halka sayisi + aci listesi.
///
/// `halka: 2` cift halkaliyi (bi-wheel/sinastri) kurar — `isBiWheel`
/// yalnizca `rings.length > 1`e bakiyor, nokta listesine bakmiyor.
ChartData _harita(List<ChartAspect> acilar, {int halka = 1}) => ChartData(
      rings: [
        for (var i = 0; i < halka; i++)
          ChartRing(
              kind: i == 0 ? ChartRingKind.natal : ChartRingKind.partner,
              points: const []),
      ],
      houses: const [],
      aspects: acilar,
    );

ChartAspect _aci(String kind, double orb, {int p2Ring = 0}) => ChartAspect(
    p1: 'Sun', p2: 'Mars', kind: kind, orb: orb, p2Ring: p2Ring);

/// `planetRoleText` tablosunun TAMAMI — 14 ad.
///
/// TEK kopya: liste bu dosyada uc ayri bekcide geziliyordu ve ucu de
/// "butun tablo" iddiasi kuruyor. Uc kopya ayrisirsa iddia sessizce
/// daralir (bu depoda ayni sinif bir kusur bir hukuk metninde yasandi).
const _kGezegenler = [
  'Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn',
  'Uranus', 'Neptune', 'Pluto', 'Chiron', 'Mean_Lilith',
  'True_North_Lunar_Node', 'True_South_Lunar_Node',
];

void main() {
  // -----------------------------------------------------------------
  group('yerlesim cumlesi: teknik bilgi CARPILIYOR', () {
    test('iki tablonun sozlesmesi "<Etiket>: <govde>." — iki dilde', () {
      // Birlestirme bu kalibi ayirarak calisiyor. Kalip bir cevirmen
      // tarafindan kaldirilirsa birlestirme sessizce eski hale (tam
      // cumle) duser; bu bekci o anda KIRMIZI olur ve dusus gorunur.
      for (final l10n in [_tr, _en]) {
        for (final ad in _kGezegenler) {
          expect(planetRoleText(l10n, ad), contains(':'),
              reason: '$ad rol cumlesi kalibi birakti');
        }
        for (var ev = 1; ev <= 12; ev++) {
          expect(houseAreaText(l10n, ev), contains(':'),
              reason: '$ev. ev cumlesi kalibi birakti');
        }
      }
    });

    test('cumle HAM tablo dizelerini ICERMEZ (yan yana basim bitti)', () {
      // Mutasyon capasi: biri birlestirmeyi geri alip `'$rol $alan'`
      // yazarsa sonuc ham dizeleri AYNEN tasir ve bu test duser.
      // Capa tek bir kelime DEGIL, dizenin kendisi (dilden bagimsiz).
      for (final l10n in [_tr, _en]) {
        final c = yerlesimCumlesi(l10n, 'Mars', 6)!;
        expect(c, isNot(contains(planetRoleText(l10n, 'Mars')!)));
        expect(c, isNot(contains(houseAreaText(l10n, 6)!)));
        // ... ama iki anlamin GOVDESI de iceride: birlestirme bilgi
        // kaybetmiyor. Govde = iki noktadan sonrasi, sondaki nokta yok.
        for (final tam in [
          planetRoleText(l10n, 'Mars')!,
          houseAreaText(l10n, 6)!,
        ]) {
          final govde = tam.substring(tam.indexOf(':') + 1).trim();
          expect(c, contains(govde.substring(0, govde.length - 1)));
        }
        // Gezegen etiketi cumleyi ACIYOR: cumle buyuk harfle baslasin
        // diye orada (govdeler kucuk harfli ve `toUpperCase()` Turkce
        // bilmez — `'i'` icin `'I'` verir, dogrusu `'İ'`).
        expect(c, startsWith('Mars'));
        // Ev ETIKETI ("6. ev" / "House 6") cumleden CIKTI: ayni olcum
        // bir satir altta `_OlcumSatiri` ile zaten duruyor.
        final evEtiketi = houseAreaText(l10n, 6)!.split(':').first;
        expect(c, isNot(contains(evEtiketi)),
            reason: 'ev etiketi cumlede tekrar ediyor');
      }
    });

    test('birlesme ANLAM duzeyinde: iki govde arasinda BAGLAC var', () {
      // ⚠️ B1(b)'nin cekirdek bekcisi. Onceki hal noktalama duzeyinde
      // birlestiriyordu (`"... istegin; gundelik duzen ..."`): 168 ayri
      // cumle uretiyordu ama noktali virgul iki ansiklopedi maddesini
      // AYIRIYOR, aralarinda bir ILISKI kurmuyordu — ekran hala "iki
      // liste yan yana" gibi okunuyordu.
      //
      // Olculen sey: iki yer tutucu ARASINDAKI metin. Capa hicbir dile,
      // kelimeye ya da diyakritige bagli DEGIL — yalniz "orada
      // noktalamadan baska bir sey var mi" sorusu. `'$rol; $alan.'`
      // seklinde bir geri alis bu bekciyi KIRMIZI yapar.
      for (final l10n in [_tr, _en]) {
        const rolIz = 'ROLYERI';
        const alanIz = 'ALANYERI';
        final kalip = l10n.pointPlacementSentence(rolIz, alanIz);
        expect(kalip, contains(rolIz));
        expect(kalip, contains(alanIz));
        expect(kalip.indexOf(rolIz), lessThan(kalip.indexOf(alanIz)),
            reason: 'rol, alandan sonra geliyor');

        final orta = kalip.substring(
            kalip.indexOf(rolIz) + rolIz.length, kalip.indexOf(alanIz));
        // Noktalama ve bosluklar atildiginda GERIYE HARF KALMALI.
        final harfler = orta.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
        expect(harfler.length, greaterThan(2),
            reason: 'iki govde arasinda yalniz noktalama var: "$orta"');

        // Ve o baglac uretilen cumlede GERCEKTEN duruyor.
        expect(yerlesimCumlesi(l10n, 'Mars', 6)!, contains(orta));
      }
    });

    test('168 yerlesimin hepsi AYRI cumle', () {
      // Eski hal 26 dizeden ikisini basiyordu. Birlesmis cumlelerin
      // tamaminin farkli olmasi, teknik bilginin CARPILDIGININ olcusu.
      final uretilen = <String>{};
      for (final ad in _kGezegenler) {
        for (var ev = 1; ev <= 12; ev++) {
          uretilen.add(yerlesimCumlesi(_tr, ad, ev)!);
        }
      }
      // Tablo gercekten 14 ad: sayi elle yazilmiyor, listeden geliyor.
      expect(_kGezegenler.length, 14);
      expect(uretilen.length, _kGezegenler.length * 12);
    });

    test('birlesme NOKTALAMA olarak da tek cumle', () {
      // ⚠️ Bu bekci DOGRULAMA turunda eklendi: govdenin sonundaki noktayi
      // kirpan satir KOR cikti — silindiginde 168 cumlenin tamami
      // "...istegin.; gundelik duzen..." gibi cift noktalama uretiyordu
      // ve takim YESIL kaliyordu. Birlestirmenin olcusu yalniz "iki govde
      // de iceride" degil, ortaya cikan seyin GERCEKTEN tek cumle olmasi.
      //
      // Capa dilden bagimsiz: yalniz noktalama isaretleri olculuyor,
      // hicbir Turkce kelimeye ya da diyakritige guvenilmiyor.
      for (final l10n in [_tr, _en]) {
        for (final ad in _kGezegenler) {
          for (var ev = 1; ev <= 12; ev++) {
            final c = yerlesimCumlesi(l10n, ad, ev)!;
            expect(c, endsWith('.'), reason: '$ad/$ev: cumle bitmiyor');
            // Dort bagimsiz isaret: noktali virgulun solunda noktalama
            // KALMAZ, ust uste nokta olmaz, nokta+noktali virgul olmaz,
            // bosluk+noktalama olmaz.
            for (final kirik in const ['.;', ',;', ' ;', '..', ' .', ':;']) {
              expect(c, isNot(contains(kirik)),
                  reason: '$ad/$ev: "$kirik" ciktida');
            }
            // Ev etiketi ("6. ev" / "6th house") kendi noktasini
            // tasiyabilir; o yuzden nokta SAYISI degil, govde icindeki
            // noktalama olculuyor: '—' sagindaki parcada yalniz SON
            // karakter nokta olabilir.
            final govde = c.substring(c.indexOf('—') + 1);
            expect(govde.substring(0, govde.length - 1), isNot(contains('.')),
                reason: '$ad/$ev: govdenin icinde nokta var');
          }
        }
      }
    });

    test('ev YOKSA uydurulmaz (saatsiz harita)', () {
      // Saatsiz haritada `house_no` gelmiyor. Eksik olcumun yerine bir
      // ev alani koymak urun ilkesini cigner; cumle yalniz gezegen
      // katmaniyla kalir.
      expect(yerlesimCumlesi(_tr, 'Mars', null),
          equals(planetRoleText(_tr, 'Mars')));
    });

    test('tablosuz nokta: ev cumlesi tek basina kalir', () {
      // Yukselen/MC gibi eksen noktalarinin rol cumlesi YOK.
      expect(yerlesimCumlesi(_tr, 'Ascendant', 4),
          equals(houseAreaText(_tr, 4)));
      expect(yerlesimCumlesi(_tr, 'Ascendant', null), isNull);
    });
  });

  // -----------------------------------------------------------------
  group('nokta alt-sayfasi: ilk gorunen sey SAYI DEGIL', () {
    final nokta = <String, dynamic>{
      'name': 'Mars',
      'name_tr': 'Mars',
      'name_local': 'Mars',
      'sign': 'Vir',
      'sign_tr': 'Başak',
      'position': 12.3,
      'house_no': 6,
      'speed': 0.52,
    };

    testWidgets('anlam cumlesi derecenin ve evin USTUNDE', (tester) async {
      await _sayfaAc(tester, (c) => showPointSheet(c, nokta));

      final anlam = find.text(yerlesimCumlesi(_tr, 'Mars', 6)!);
      expect(anlam, findsOneWidget);

      // Uc bagimsiz olcum satiri — hicbiri anlamin ustunde olamaz.
      for (final olcum in [
        find.text('12.30°'),
        find.text('6. ev'),
        find.text('0.520°/gün'),
      ]) {
        expect(olcum, findsOneWidget);
        expect(_dy(tester, anlam), lessThan(_dy(tester, olcum)),
            reason: 'olcum anlamin ustune cikti');
      }
      // Dayanak basligi da anlamdan SONRA.
      expect(_dy(tester, anlam),
          lessThan(_dy(tester, find.text(_tr.signalWhy))));
    });

    testWidgets('olcum satirlari KAYBOLMADI', (tester) async {
      // Sirayi tersine cevirmek olcumu gizlemek DEGILDIR: "olculmeyen
      // soylenmez"in tersi de gecerli, olculen saklanmaz.
      await _sayfaAc(tester, (c) => showPointSheet(c, nokta));
      // Etiketler `OlcumSatiri` (basis_sheet) ile BIREBIR: buyuk harfe
      // cevrilmiyor (D6) — `toUpperCase` Turkce bilmiyordu, rol
      // tipografisi etiket agirligini zaten tasiyor.
      expect(find.text(_tr.planetDegree), findsOneWidget);
      expect(find.text(_tr.planetHouse), findsOneWidget);
      expect(find.text(_tr.planetSpeed), findsOneWidget);
    });

    testWidgets('DAR ve KISA ekranda tasma yok', (tester) async {
      // Anlam katmani sayfayi bir satir uzatti ve kaydirmasiz kipte
      // 131 px tasiyordu — yani alttaki olcum satirlari dar ekranda
      // SESSIZCE kirpilirdi. Flutter testinde tasma bir istisna firlatir,
      // yani bu iddia piksel iddiasi DEGIL: "kirpilan icerik var mi".
      //
      // ⚠️ Burada bir tur "28 px" yaziyordu; kaynak dosya o sayiyi
      // duzeltirken (ayni senaryo, olculen 131 px) BU yorum guncel
      // kalmamisti. Ikinci dogrulama turunda asagidaki senaryo birebir
      // kurulup yeniden olculdu: 320x480, olcek 1.0, sarmalayici
      // kaldirildiginda 131 px.
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // En uzun kombinasyon: Ay (uc ogeli rol) + 1. ev (uc ogeli alan).
      await _sayfaAc(
          tester,
          (c) => showPointSheet(c, {
                'name': 'Moon',
                'name_tr': 'Ay',
                'name_local': 'Ay',
                'sign': 'Pis',
                'sign_tr': 'Balık',
                'position': 29.87,
                'house_no': 1,
                'speed': 13.176,
                'retrograde': true,
              }));

      expect(tester.takeException(), isNull);
      // Kirpilma olmadiginin ikinci isareti: en alttaki olcum satiri
      // gercekten agacta ve kaydirilabilir.
      expect(find.text(_tr.planetSpeed), findsOneWidget);
    });

    test('DURUSTLUK DIPNOTU basiliyor ve KONUM BEYANI tasimiyor', () {
      // B1(a). Dipnotun uc hali oldu ve bekci de iki kez degisti:
      //  1. Ilk metin YANLIS BEYAN'di ("Ustteki satirlar olcumdur.
      //     Altindaki IKI CUMLE … birlestirir") — olcum ALTTA ve cumle
      //     TEK oldugu icin iki cumlesi de yanlisti.
      //  2. Bu yuzden dipnot HIC basilmaz oldu ve onceki bekci tam o
      //     hali civiliyordu ("geri donmez"). Ama basilmamasi da kayipti:
      //     ustteki cumlenin OLCUM mu KLASIK GELENEK mi oldugu ekranda
      //     HICBIR YERDE yazmiyordu — oysa o ayrim bir urun ilkesi
      //     ("olculmeyen soylenmez"). Yani eski bekci, kapanmasi gereken
      //     bir bosluga "dogru hal" diyordu.
      //  3. Simdiki metin olculen sirayi anlatiyor ve KONUM SOZCUGU
      //     tasimiyor; bayatlamasinin sebebi tam olarak o sozcuklerdi.
      //
      // ⚠️ Eslesmeden ONCE yorumlar atiliyor: bu dosyada da, kaynakta da
      // dipnotun adini ANLATAN yorumlar var ve varligini/yoklugunu arayan
      // bir bekci onlara takilirdi (depoda bu tam iki kez patladi).
      final k = _yorumsuz('lib/features/atlas/atlas_detail_screens.dart');
      expect(k, contains('pointSheetFootnote'),
          reason: 'durustluk dipnoti ekranda basilmiyor');
      // Ikinci ve BAGIMSIZ isaret: aci sayfasinin dipnoti da KALMALI.
      expect(k, contains('aspectSheetFootnote'),
          reason: 'aci sayfasinin durustluk dipnotu dusmus');

      // Ucuncu isaret, METNIN KENDISI: konum sozcugu tasimamali.
      //
      // ⚠️ `toLowerCase()` CAGRILMIYOR: Turkce'de noktali I iki kod
      // noktasina acilir ve esleme sessizce kayar. Onun yerine her
      // sozcugun iki yazimi ELLE listelenmis.
      for (final l10n in [_tr, _en]) {
        final dipnot = l10n.pointSheetFootnote;
        for (final konum in const [
          'Üstteki', 'üstteki', 'Altındaki', 'altındaki',
          'Yukarıdaki', 'yukarıdaki', 'Aşağıdaki', 'aşağıdaki',
          'above', 'Above', 'below', 'Below',
        ]) {
          expect(dipnot, isNot(contains(konum)),
              reason: 'dipnot konuma gore konusuyor ("$konum"); '
                  'sira degisince sessizce yanlisa doner');
        }
        // Dorduncu isaret: "iki cumle" iddiasi da geri donmemeli —
        // sayfada TEK anlam cumlesi var.
        for (final sayi in const [
          'iki cümle', 'İki cümle', 'two sentences', 'Two sentences',
        ]) {
          expect(dipnot, isNot(contains(sayi)),
              reason: 'dipnot hala "iki cumle" diyor');
        }
        // Ve dipnot GERCEKTEN bir sey soylemeli: bos/kisa bir dize
        // yukaridaki dort kapinin hepsinden gecerdi.
        expect(dipnot.length, greaterThan(60));
      }
    });

    testWidgets('dipnot OLCUM satirlarinin ALTINDA', (tester) async {
      // Metin konum sozcugu tasimiyor ama sayfanin sirasi yine de
      // olculuyor: dipnot bir DIPnottur ve olcumun ustune cikarsa
      // "once anlam, sonra olcum" anlatisi gorsel olarak bozulur.
      await _sayfaAc(tester, (c) => showPointSheet(c, nokta));

      final dipnot = find.text(_tr.pointSheetFootnote);
      expect(dipnot, findsOneWidget);
      expect(_dy(tester, find.text('12.30°')),
          lessThan(_dy(tester, dipnot)),
          reason: 'dipnot olcum satirlarinin ustune cikmis');
    });

    testWidgets('ingilizce arayuzde de anlam once', (tester) async {
      await tester.pumpWidget(_sar(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                  onPressed: () => showPointSheet(context, nokta),
                  child: const Text('ac')),
            ),
          ),
          dil: 'en'));
      await tester.tap(find.text('ac'));
      await _bekle(tester);

      final anlam = find.text(yerlesimCumlesi(_en, 'Mars', 6)!);
      expect(anlam, findsOneWidget);
      expect(_dy(tester, anlam),
          lessThan(_dy(tester, find.text('12.30°'))));
    });
  });

  // -----------------------------------------------------------------
  group('aci alt-sayfasi: ilk gorunen sey ORB DEGIL', () {
    final aci = <String, dynamic>{
      'p1': 'Sun',
      'p1_tr': 'Güneş',
      'p2': 'Mars',
      'p2_tr': 'Mars',
      'aspect': 'square',
      'aspect_tr': 'Kare',
      'orbit': 1.5,
      'movement': 'applying',
      'movement_local': 'Yaklaşıyor',
    };

    testWidgets('aci anlami orbun USTUNDE', (tester) async {
      await _sayfaAc(tester, (c) => showAspectSheet(c, aci));

      final anlam = find.text(_tr.aspectMeaningSquare);
      expect(anlam, findsOneWidget);
      for (final olcum in [
        find.text('1.50°'),
        find.text(_tr.basisOrb),
        find.text(_tr.basisAspect),
      ]) {
        expect(olcum, findsOneWidget);
        expect(_dy(tester, anlam), lessThan(_dy(tester, olcum)));
      }
    });

    testWidgets('hareket cumlesi de dayanaktan once', (tester) async {
      await _sayfaAc(tester, (c) => showAspectSheet(c, aci));
      expect(_dy(tester, find.text(_tr.movementMeaningApplying)),
          lessThan(_dy(tester, find.text('1.50°'))));
      // "Neye dayaniyor?" basligi da hareket cumlesinden SONRA.
      //
      // Bu satir ikinci DOGRULAMA turunda eklendi: basligi bu sayfadan
      // silmek takimi YESIL birakiyordu (nokta sayfasinda civiliydi,
      // burada degil). Baslik anlam ile olcumu ayiran gorunur cizgi;
      // dusmesi "once anlam, sonra dayanak" sozunu sessizce bozar.
      expect(_dy(tester, find.text(_tr.movementMeaningApplying)),
          lessThan(_dy(tester, find.text(_tr.signalWhy))));
    });

    testWidgets('BUYUK YAZIDA ve dar ekranda tasma yok', (tester) async {
      // ⚠️ Bu bekci ilk halinde KORDU ve sebebi OLCULDU: 320x480'de yazi
      // olcegi 1.0 iken bu sayfa HIC tasmiyor (bes aci turu × iki
      // hareket, hepsi 0 px). Yani kaydirma sarmalayicisi kaldirilsa
      // bile test yesil kaliyordu. Tasma uygulamanin kendi yazi olcegi
      // TAVANINDA basliyor (`kMaxTextScale`): olculen 141-247 px, bu
      // senaryoda (Kare · yaklasan) 220 px.
      //
      // ⚠️ Burada bir tur "200-279 px" yaziyordu; ikinci dogrulama
      // turunda on senaryo AYRI AYRI olculdu ve yedisi 200'un altinda
      // cikti, 279 px hic gorulmedi. Donguyle olcmek yaniltiyor:
      // `RenderFlex` tasmayi render nesnesi basina BIR KEZ bildiriyor.
      //
      // Nokta ve dagilim sayfalarinin bekcileri 1.0'da zaten isiriyor
      // (131 px / 117 px olculdu — ikisi de yeniden dogrulandi); bu
      // sayfanin bekcisi olceksiz anlamsiz.
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = kMaxTextScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _sayfaAc(tester, (c) => showAspectSheet(c, aci));

      expect(tester.takeException(), isNull);
      // Kirpilmadiginin ikinci isareti: en alttaki durustluk dipnotu
      // gercekten agacta.
      expect(find.text(_tr.aspectSheetFootnote), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------
  group('dagilim alt-sayfasi: dayanak kirpilmaz', () {
    // Bu sayfa 48-turunda ust duzeye cikarildi ve ARTIK Harita
    // Inceleme'nin anlam panelinden de aciliyor; kaydirma onarimi yine
    // KOR cikti (sarmalayici kaldirildiginda takim yesildi).
    Future<void> ac(WidgetTester tester) => _sayfaAc(
          tester,
          (c) => showDagilimSheet(
            c,
            baslik: elementName(_tr, 'fire'),
            aciklama: elementLine(_tr, 'fire'),
            klasik: temperamentLine(_tr, 'fire'),
            // Sekiz uye: geleneksel yedili + Yukselen. `Wrap` dar
            // ekranda uc satira cikiyor.
            uyeler: const [
              'Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter',
              'Saturn', 'Ascendant',
            ],
            points: const [
              {'name': 'Sun', 'name_local': 'Güneş', 'sign_local': 'Koç'},
              {'name': 'Moon', 'name_local': 'Ay', 'sign_local': 'Yay'},
              {'name': 'Mars', 'name_local': 'Mars', 'sign_local': 'Aslan'},
            ],
          ),
        );

    testWidgets('DAR ve KISA ekranda tasma yok', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await ac(tester);

      expect(tester.takeException(), isNull);
      // Uc bagimsiz isaret agacta: baslik, uye etiketi ve bir cip.
      expect(find.text(_tr.traitsSheetTitle(elementName(_tr, 'fire'))),
          findsOneWidget);
      expect(find.text(_tr.traitsMembersLabel),
          findsOneWidget);
      expect(find.text(_tr.pointAscendant), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------
  group('acilar ekrani: ilk gorunen sey IZGARA DEGIL', () {
    List<Map<String, dynamic>> uc() => [
          {
            'p1': 'Sun', 'p1_tr': 'Güneş', 'p2': 'Mars', 'p2_tr': 'Mars',
            'aspect': 'square', 'aspect_tr': 'Kare', 'orbit': 6.0,
          },
          {
            'p1': 'Moon', 'p1_tr': 'Ay', 'p2': 'Venus', 'p2_tr': 'Venüs',
            'aspect': 'trine', 'aspect_tr': 'Üçgen', 'orbit': 0.4,
          },
          {
            'p1': 'Mercury', 'p1_tr': 'Merkür', 'p2': 'Saturn',
            'p2_tr': 'Satürn', 'aspect': 'sextile',
            'aspect_tr': 'Altmışlık', 'orbit': 3.0,
          },
        ];

    testWidgets('EN DAR acinin anlami en ustte', (tester) async {
      await tester.pumpWidget(_sar(AtlasAspectsScreen(aspects: uc())));
      await _bekle(tester);

      // Lider en dar orblu aci (0.4°) — Ucgen. Ekranin kendi dipnotu
      // "orb ne kadar darsa aci o kadar guclu" diyor, yani liderlik
      // olculen bir siradan geliyor.
      final anlam = find.text(_tr.aspectMeaningTrine);
      expect(anlam, findsOneWidget);
      // Kare (6.0°) lider DEGIL.
      expect(find.text(_tr.aspectMeaningSquare), findsNothing);

      // Satır artık dereceyi değil güç SÖZÜNÜ taşıyor (2026-10-18; derece
      // alt sayfanın dayanağında). 0.4° tek "çok güçlü" satır.
      for (final teknik in [
        find.text(_tr.aspectStrengthVeryStrong),
        find.text(_tr.aspectsGroupTension),
        find.text(_tr.aspectsGroupFlow),
      ]) {
        expect(teknik, findsOneWidget);
        expect(_dy(tester, anlam), lessThan(_dy(tester, teknik)),
            reason: 'teknik katman anlamin ustune cikti');
      }
    });

    testWidgets('aci yoksa COKMEZ, uydurmaz', (tester) async {
      await tester.pumpWidget(_sar(const AtlasAspectsScreen(aspects: [])));
      await _bekle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(_tr.aspectMeaningTrine), findsNothing);
    });

    testWidgets('ORBU OLCULMEMIS aci lider olamaz', (tester) async {
      // ⚠️ Bu bekci DOGRULAMA turunda eklendi. Ekranin "en dar aci" sozu
      // `_orb`un eksik orba 99 vermesine dayaniyor ve o satir KOR cikti:
      // 99 yerine 0 yazildiginda (yani olculmemis aci EN DAR sayildiginda)
      // takim YESIL kaliyordu. Oysa sonuc tam olarak urun ilkesinin
      // tersi olur: ekranin TEK anlam cumlesi, orbu hic olculmemis bir
      // acidan secilir ve dipnot ("en dar orb once") yalan soyler.
      //
      // Olculmemis aci LISTENIN BASINDA duruyor: siralama atlanirsa ya da
      // eksik orb 0 sayilirsa lider O olur.
      await tester.pumpWidget(_sar(AtlasAspectsScreen(aspects: const [
        {
          'p1': 'Sun', 'p1_tr': 'Güneş', 'p2': 'Mars', 'p2_tr': 'Mars',
          'aspect': 'conjunction', 'aspect_tr': 'Kavuşum',
          // 'orbit' BILEREK yok: sunucu bir gun bu alani atlarsa.
        },
        {
          'p1': 'Moon', 'p1_tr': 'Ay', 'p2': 'Venus', 'p2_tr': 'Venüs',
          'aspect': 'trine', 'aspect_tr': 'Üçgen', 'orbit': 3.0,
        },
      ])));
      await _bekle(tester);

      expect(tester.takeException(), isNull);
      // Lider OLCULEN aci; olculmeyenin cumlesi ekranda HIC yok.
      expect(find.text(_tr.aspectMeaningTrine), findsOneWidget);
      expect(find.text(_tr.aspectMeaningConjunction), findsNothing);
      // Ikinci bagimsiz isaret: olculmemis aci ekrandan ATILMIYOR,
      // yalniz lider olamiyor — satiri orb yerine "—" ile duruyor.
      expect(find.text('—'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------
  group('kisilik ekrani: ilk gorunen sey CUBUK DEGIL', () {
    Map<String, dynamic> harita(Map<String, int> elementler) => {
          'element_distribution': elementler,
          'modality_distribution': {'cardinal': 3, 'fixed': 4, 'mutable': 1},
          'element_members': {
            'fire': ['Sun', 'Mars', 'Ascendant'],
            'earth': ['Venus', 'Saturn'],
            'air': ['Mercury'],
            'water': ['Moon'],
          },
          'modality_members': const {},
          'points': const [],
        };

    testWidgets('baskin elementin anlami cubuklardan once', (tester) async {
      await tester.pumpWidget(_sar(AtlasTraitsScreen(
          chart: harita({'fire': 4, 'earth': 2, 'air': 1, 'water': 1}))));
      await _cubuklariBekle(tester);

      final anlam = find.text(_tr.elementFireLine);
      expect(anlam, findsOneWidget);
      expect(_dy(tester, anlam),
          lessThan(_dy(tester,
              find.text(_tr.traitsCountCaption('4', '8')).first)));
      expect(_dy(tester, anlam),
          lessThan(_dy(tester, find.text(_tr.traitsElements))));
    });

    testWidgets('TEPEDE ESITLIK varsa baskinlik SOYLENMEZ', (tester) async {
      // Olculmeyen soylenmez: iki element tepede esitse bu haritanin
      // baskin elementi yoktur. Esitlikte birini secmek, olcumun
      // soylemedigi bir seyi soylemek olurdu.
      await tester.pumpWidget(_sar(AtlasTraitsScreen(
          chart: harita({'fire': 3, 'earth': 3, 'air': 1, 'water': 1}))));
      await _cubuklariBekle(tester);

      expect(find.text(_tr.elementFireLine), findsNothing);
      expect(find.text(_tr.elementEarthLine), findsNothing);
      // Cubuklar yine duruyor — gizlenen bir sey yok.
      expect(find.text(_tr.traitsElements), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------
  group('harita inceleme: anlam katmani ILK cocuk', () {
    // Bu ekran `natalChartProvider`/`skyNowProvider`/Firestore akislarina
    // bagli; widget testi sahte bir Firebase `User`i isterdi. Bu yuzden
    // kaynaktan civileniyor — depoda emsali var (rapor_uretilemedi_test,
    // plus_kapisi_test).
    const yol = 'lib/features/atlas/chart_inspector_screen.dart';

    /// Govde: `_ChartInspectorScreenState` sinifinin ta kendisi.
    ///
    /// Sinir SART: `ChartWheel(` paylasim kartinda da geciyor ve `_Lejant(`
    /// gibi adlar kendi sinif yapicilarinda. Dilim iki SINIF BILDIRIMI
    /// arasi — prozaya degil kod tanimlayicisina bagli.
    String govde() {
      final k = _yorumsuz(yol);
      final bas = k.indexOf('class _ChartInspectorScreenState');
      final son = k.indexOf('class _AnlamKatmani');
      expect(bas, greaterThanOrEqualTo(0));
      expect(son, greaterThan(bas));
      return k.substring(bas, son);
    }

    test('anlam katmani govdede ve DORT teknik bloktan once', () {
      final g = govde();
      final anlam = g.indexOf('_AnlamKatmani(');
      expect(anlam, greaterThanOrEqualTo(0),
          reason: 'anlam katmani ekrandan dusmus');
      // Dort bagimsiz isaret: veri basligi, secim cubugu, aci izgarasi,
      // konum tablosu. Biri yer degistirse digerleri yine yakalar.
      for (final sonra in const [
        '_Baslik(',
        '_SecimCubugu(',
        '_Aspectarian(',
        'ChartPositionsTable(',
      ]) {
        final i = g.indexOf(sonra);
        expect(i, greaterThanOrEqualTo(0), reason: '$sonra kayboldu');
        expect(anlam, lessThan(i),
            reason: '$sonra anlam katmanindan once geliyor');
      }
    });

    test('anlam katmani govdenin ILK cocugu — ustune blok girmez', () {
      // ⚠️ Bu bekci IKINCI DOGRULAMA turunda eklendi ve sebebi OLCULDU:
      // yukaridaki test yalniz DORT ADLI blogun anlamdan SONRA geldigini
      // soruyor. Anlamin USTUNE adi bilinmeyen YENI bir teknik blok
      // eklemek takimin tamamini YESIL birakiyordu — ekran yine bir
      // sayiyla aciliyor, o dort isaret ise hala anlamdan sonra. Grubun
      // adi ve kodun yorumu "ILK cocuk" diyor; olculen sey o DEGILDI.
      //
      // Capa adlara degil YAPIYA bagli: yorumlar atildiktan sonra
      // `children: [` ile `_AnlamKatmani(` arasinda BOSLUKTAN baska bir
      // sey kalmamali. Sayim `ListView(`dan basliyor cunku carkin kendi
      // `Stack` `children:`i govdede ondan ONCE geciyor.
      final g = govde();
      final liste = g.indexOf('ListView(');
      expect(liste, greaterThanOrEqualTo(0), reason: 'govde ListView degil');
      final cocuklar = g.indexOf('children: [', liste);
      expect(cocuklar, greaterThan(liste), reason: 'govde listesi yok');
      final anlam = g.indexOf('_AnlamKatmani(', cocuklar);
      expect(anlam, greaterThan(cocuklar),
          reason: 'anlam katmani govde listesinde yok');
      expect(g.substring(cocuklar + 'children: ['.length, anlam).trim(),
          isEmpty,
          reason: 'anlam katmaninin USTUNE baska bir blok girmis');
    });

    test('anlam katmani LLM/Plus kaynagina BAGLANMADI', () {
      // Ucretsiz katman kurali: cark, yerlesimler ve acilar herkese acik.
      // Anlam cumlesini `/reports/natal`dan almak hem paywall hem her
      // acilista LLM maliyeti getirirdi.
      final k = _yorumsuz(yol);
      final bas = k.indexOf('class _AnlamKatmani');
      final sinif = k.substring(bas, k.indexOf('class _Baslik'));
      expect(sinif, isNot(contains('natalReportProvider')));
      expect(sinif, isNot(contains('Provider(')),
          reason: 'anlam katmani kendi istegini atmamali');
      // Olculmeyen soylenmez: hicbir dal tutmazsa hic cizilmez.
      expect(sinif, contains('SizedBox.shrink()'));
      // Anlami olmayan aci (minor) icin cumle UYDURULMAZ; bu dalin
      // onculu asagida ayrica olculuyor (`aspectMeaningText` null doner).
      expect(sinif, contains('if (cumle != null)'));
      // Iki secim kurali da DISARI cikarildi: ikisi de artik davranis
      // olarak civili (bkz. asagidaki iki grup). Ekran kendi kopyasini
      // tutmamali — iki kopya "ayni sayinin iki gerekcesi" riskidir.
      expect(sinif, contains('liderGorunurAci('));
      expect(sinif, contains('baskinElement('));
      expect(sinif, isNot(contains('.sort(')),
          reason: 'ekran kendi siralamasini/secimini yine yapiyor');
    });

    test('aci kapisi CARKIN kendi yuklemi — ikinci esik yok', () {
      // `liderGorunurAci` carkla AYNI kapiyi kullanmali: ekranin basinda
      // carkta cizilmeyen bir aciyi anlatmak, gosterilmeyen bir seyi
      // beyan etmek olurdu. Kaynaktan civili cunku "ayni kapi" iddiasi
      // davranisla degil KIMLIKLE kurulur.
      final k = _yorumsuz(yol);
      final bas = k.indexOf('ChartAspect? liderGorunurAci(');
      expect(bas, greaterThanOrEqualTo(0), reason: 'kural kayboldu');
      final govde = k.substring(bas, k.indexOf('class _AnlamKatmani'));
      expect(govde, contains('aspectVisible('));
      // Elle kurulmus ikinci bir esigin iki bagimsiz izi: mesru govde
      // yalniz `x.orb.compareTo(y.orb)` yaziyor, hicbir yerde orb'u bir
      // sayiyla KARSILASTIRMIYOR.
      expect(govde, isNot(contains('orb <')),
          reason: 'elle kurulmus ikinci bir orb esigi var');
      expect(govde, isNot(contains('orb >')),
          reason: 'elle kurulmus ikinci bir orb esigi var');
    });
  });

  // -----------------------------------------------------------------
  // Asagidaki iki grup DOGRULAMA turunda eklendi. Harita Inceleme'nin
  // anlam cumlesini secen iki kural da KOR cikti: ucu de (esitlik kapisi,
  // "en dar" yonu, capraz tercihi) tersine cevrildiginde takim YESIL
  // kaliyordu. Kurallar saf fonksiyona cikarildi ve burada civilendi.
  group('baskin element kurali', () {
    test('kesin ustunluk varsa o element', () {
      expect(baskinElement({'fire': 4, 'earth': 2, 'air': 1, 'water': 1}),
          equals('fire'));
      expect(baskinElement({'fire': 1, 'earth': 1, 'air': 1, 'water': 5}),
          equals('water'));
    });

    test('TEPEDE ESITLIK varsa baskinlik YOKTUR', () {
      // Olculmeyen soylenmez. Bu iddia KOR BEKCININ ta kendisiydi:
      // kapiyi kaldirmak takimi yesil birakiyordu.
      expect(baskinElement({'fire': 3, 'earth': 3, 'air': 1, 'water': 1}),
          isNull);
      expect(baskinElement({'fire': 2, 'earth': 2, 'air': 2, 'water': 2}),
          isNull);
      expect(baskinElement({'fire': 0, 'earth': 0, 'air': 0, 'water': 0}),
          isNull);
    });

    test('girdi SIRASI sonucu degistirmez', () {
      // `List.sort` kararli DEGIL; esitlikte null donuldugu icin bu
      // zararsiz. Kapi kalkarsa sonuc sabit siraya baglanir ve ayni
      // harita, anahtar sirasi degisince FARKLI cumle gosterebilir.
      const a = {'water': 3, 'fire': 3, 'air': 1, 'earth': 1};
      const b = {'fire': 3, 'water': 3, 'earth': 1, 'air': 1};
      expect(baskinElement(a), equals(baskinElement(b)));
      expect(baskinElement(a), isNull);
    });

    test('dagilim yoksa / eksikse COKMEZ', () {
      // Dagilimsiz eski sunucu yaniti ekranin kendi kapisinda da
      // karsilaniyor (`traitsUnavailable`); burada kural seviyesinde.
      expect(baskinElement(null), isNull);
      expect(baskinElement(const {}), isNull);
      // Eksik anahtar 0 sayilir; tek olcum varsa o kesin ustundur.
      expect(baskinElement({'air': 2}), equals('air'));
      // ⚠️ SAYI OLMAYAN deger BURADA savunulmuyor ve bu bilerek boyle:
      // `dagilim[e] as num?` cast'i bu ekranda yedi yerde birden geciyor
      // (oran satirlari, toplam, eksik element listesi). Yalniz bu kurali
      // saglamlastirmak ekranin iki satir sonra atacagi ayni hatayi
      // gizleyip YANLIS bir guven verirdi; "cast her yerde sertlestirilir"
      // ayri bir is ve raporda bulgu olarak duruyor.
    });
  });

  // -----------------------------------------------------------------
  group('lider gorunur aci kurali', () {
    const f = WheelAspectFilter.all;

    test('EN DAR aci secilir', () {
      // KOR BEKCI idi: `havuz.first` -> `havuz.last` yapildiginda, yani
      // ekranin basinda EN GENIS aci anlatildiginda takim yesildi.
      final d = _harita([
        _aci('square', 6.0),
        _aci('trine', 0.4),
        _aci('sextile', 3.0),
      ]);
      expect(liderGorunurAci(d, f, 8.0, showMinors: false)?.kind,
          equals('trine'));
    });

    test('CARKTA GORUNMEYEN aci lider olamaz', () {
      // Orb kaydiriciyi kullanici kendi kurcaliyor; cizilmeyen aciyi
      // ekranin basinda anlatmak gosterilmeyen bir seyi beyan etmektir.
      final d = _harita([_aci('square', 6.0), _aci('trine', 0.4)]);
      // 0.5 esikte yalniz ucgen gorunur.
      expect(liderGorunurAci(d, f, 0.5, showMinors: false)?.kind,
          equals('trine'));
      // 0.1 esikte hicbiri gorunmez — cumle de yok.
      expect(liderGorunurAci(d, f, 0.1, showMinors: false), isNull);
      // Filtre de ayni kapidan gecer: yalniz sert acilar istenirse
      // ucgen lider OLAMAZ.
      expect(
          liderGorunurAci(d, WheelAspectFilter.hard, 8.0,
                  showMinors: false)
              ?.kind,
          equals('square'));
    });

    test('MINOR aci kapaliyken lider olamaz', () {
      final d = _harita([_aci('quincunx', 0.2), _aci('trine', 5.0)]);
      expect(liderGorunurAci(d, f, 8.0, showMinors: false)?.kind,
          equals('trine'));
      expect(liderGorunurAci(d, f, 8.0, showMinors: true)?.kind,
          equals('quincunx'));
    });

    test('MINOR acinin anlam cumlesi YOK — uydurulmuyor', () {
      // `_AnlamKatmani`'nin `if (cumle != null)` dalinin onculu: minor
      // aciya anlam metni gelmiyor, yani lider minor oldugunda panel
      // hic cizilmez.
      expect(aspectMeaningText(_tr, 'quincunx'), isNull);
      expect(aspectMeaningText(_tr, 'trine'), isNotNull);
    });

    test('CIFT HALKALIDA capraz aci tercih edilir', () {
      // KOR BEKCI idi. "Sen & Ayse" ekraninda tek bir kisinin kendi
      // icindeki aci yanlis ozne olur — daha dar olsa bile.
      final acilar = [
        _aci('trine', 0.2), // ic halka, kendi icinde
        _aci('square', 4.0, p2Ring: 1), // capraz
      ];
      expect(liderGorunurAci(_harita(acilar, halka: 2), f, 8.0,
              showMinors: false)
          ?.kind,
          equals('square'));
      // TEK halkada capraz aci yoktur; ayni liste en dar aciyi verir.
      expect(liderGorunurAci(_harita(acilar), f, 8.0, showMinors: false)
          ?.kind,
          equals('trine'));
    });

    test('capraz aci YOKSA havuz butun gorunur acilara duser', () {
      final d = _harita([_aci('trine', 0.2), _aci('square', 4.0)], halka: 2);
      expect(liderGorunurAci(d, f, 8.0, showMinors: false)?.kind,
          equals('trine'));
    });

    test('aci yoksa null — bos ekran uydurma cumleden iyidir', () {
      expect(liderGorunurAci(_harita(const []), f, 8.0, showMinors: false),
          isNull);
    });
  });

  // -----------------------------------------------------------------
  // ⚠️ Bu grup IKINCI DOGRULAMA turunda eklendi ve sebebi olculdu: kip
  // kapisi `_ChartInspectorScreenState._natalYuk` icinde dururken KORDU —
  // kapi silindiginde takimin tamami YESIL kaliyordu. Ekranin kendisi
  // Firebase/profil saglayicilarina bagli, yani widget testi yazilamiyor;
  // kural saf fonksiyona (`natalAnlamYuku`) cikarildi ve burada davranis
  // olarak civilendi. Ayni cozum bu dosyada iki kez daha kullanildi
  // (`baskinElement`, `liderGorunurAci`).
  group('natal anlam yuku: kip kapisi', () {
    final yuk = {'element_distribution': const {'fire': 4}};

    test('natal kipte yuk gecer', () {
      expect(
          natalAnlamYuku(ChartInspectorMode.natal,
              override: yuk, saglayici: () => null),
          same(yuk));
    });

    test('natal OLMAYAN uc kipte yuk YOK', () {
      // Uc kipin hepsi tek tek: "gokyuzu disinda hepsi" gibi bir
      // genelleme yapilmiyor, enum'un uc degeri de aciktan olculuyor.
      for (final kip in const [
        ChartInspectorMode.sky,
        ChartInspectorMode.biwheel,
        ChartInspectorMode.synastry,
      ]) {
        expect(
            natalAnlamYuku(kip, override: yuk, saglayici: () => yuk), isNull,
            reason: '$kip ekraninda natal baskin element gosterilirdi');
      }
      // Enum'a yeni bir kip eklenirse bu bekci onu GORMEZ; sayi da
      // civilendi, yoksa "uc kip" iddiasi sessizce daralir.
      expect(ChartInspectorMode.values.length, 4);
    });

    test('SAGLAYICI tembel: natal olmayan kipte HIC okunmaz', () {
      // Dogrudan `ref.watch(...)` yazilsa gokyuzu/sinastri ekrani da
      // natal haritaya ABONE olur: kullanmadigi bir istek + bir yeniden
      // cizim. Kapi once, okuma sonra.
      var okundu = 0;
      natalAnlamYuku(ChartInspectorMode.sky, override: null, saglayici: () {
        okundu++;
        return null;
      });
      expect(okundu, 0);
      natalAnlamYuku(ChartInspectorMode.natal, override: null, saglayici: () {
        okundu++;
        return null;
      });
      expect(okundu, 1);
    });

    test('override yoksa saglayici okunur', () {
      expect(
          natalAnlamYuku(ChartInspectorMode.natal,
              override: null, saglayici: () => yuk),
          same(yuk));
    });
  });
}

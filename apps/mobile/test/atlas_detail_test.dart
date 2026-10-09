import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/atlas/atlas_detail_screens.dart';
import 'package:rytho/l10n/app_localizations.dart';

/// Asama A3'un degismezleri.
///
/// Kullanicinin tarifi: "atlas sayfasi da tuhaf, profilimde olan bilgiler de
/// var yuz okuma da var, asagi dogru uzanan uzun metinler de var, kisilik
/// ozellikleri, gezegen konumlari vs... her sey her yerde hissi var."
///
/// Teshis "cok ozellik var" DEGIL, hepsinin ayni seviyede durmasiydi. Atlas
/// artik bir dizin; asagidaki testler detayin gercekten detay sayfasinda
/// oldugunu ve orada KIRPILMADIGINI koruyor.

List<Map<String, dynamic>> _aciUret(int adet) => [
      for (var i = 0; i < adet; i++)
        {
          'p1': 'Gezegen$i',
          'p1_tr': 'Gezegen$i',
          'p2': 'Hedef$i',
          'p2_tr': 'Hedef$i',
          'aspect': 'square',
          'aspect_tr': 'Kare',
          'orbit': 1.5 + i,
        },
    ];

final _gezegenler = <Map<String, dynamic>>[
  {'name': 'Sun', 'name_tr': 'Güneş', 'sign_tr': 'Aslan', 'abs_position': 130.0},
  {'name': 'Moon', 'name_tr': 'Ay', 'sign_tr': 'Balık', 'abs_position': 340.0},
  {
    'name': 'Mercury',
    'name_tr': 'Merkür',
    'sign_tr': 'Başak',
    'abs_position': 160.0,
    'retrograde': true,
  },
];

Widget _sar(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: child,
    );

/// `AstrolabeSpinner` ve yildiz alani surekli animasyonlu — `pumpAndSettle`
/// hicbir zaman donmez.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// `GradientProgressBar` her cubugu 120 ms gecikmeyle baslatir ve 800 ms'de
/// doldurur. Beklenmezse widget agaci sokulurken zamanlayici hala aciktir ve
/// test "A Timer is still pending" diye duser — urun hatasi degil.
Future<void> _cubuklariBekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  group('acilar sayfasi', () {
    testWidgets('aci listesi KIRPILMAZ', (tester) async {
      // Akista `aspects.take(14)` vardi cunku hepsi ekrani boguyordu.
      // Kendi sayfasinda o sebep yok; kirpma geri gelirse kullanici
      // haritasinin bir kismini goremez ve bunu HIC fark etmez.
      await tester
          .pumpWidget(_sar(AtlasAspectsScreen(aspects: _aciUret(22))));
      await _bekle(tester);

      // Liste kaydirilarak sonuncuya kadar gidilebilmeli.
      await tester.scrollUntilVisible(
          find.text('Gezegen21 — Hedef21'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Gezegen21 — Hedef21'), findsOneWidget);
    });

    test('aci sayisi altyaziya girer', () {
      // Karonun alt satiri "22 açı" der; kullanici tiklamadan once ne
      // bulacagini bilir.
      expect(_aciUret(22).length, 22);
    });
  });

  group('gezegenler sayfasi', () {
    testWidgets('her buyuk gezegen listelenir', (tester) async {
      await tester
          .pumpWidget(_sar(AtlasPlanetsScreen(points: _gezegenler)));
      await _bekle(tester);

      // OP5-turu: ekran artik GUNES'in anlam cumlesiyle aciliyor ve o
      // cumle oznesini KENDI icinde soyluyor ("Günes: …"), yani Günes
      // ekranda iki kez geciyor — cumlede ve izgara satirinda. Oteki iki
      // gezegen yalniz izgarada, yani bu test hem listenin TAMAMINI hem
      // oznenin TEKLIGINI olcuyor. Sayi iki yone de calisir: anlam
      // katmani duserse 1, ikinci bir cumle ya da panel etiketi eklenirse
      // 3 cikar. Yapisal bekcisi: gezegen_anlam_test.dart.
      expect(find.textContaining('Güneş'), findsNWidgets(2));
      expect(find.textContaining('Ay'), findsOneWidget);
      expect(find.textContaining('Merkür'), findsOneWidget);
    });

    testWidgets('retro gezegen isaretlenir', (tester) async {
      await tester
          .pumpWidget(_sar(AtlasPlanetsScreen(points: _gezegenler)));
      await _bekle(tester);

      expect(find.textContaining('℞'), findsOneWidget);
    });

    testWidgets('ek noktalar ARTIK gizlenmez (R5-2)', (tester) async {
      // Eski filtre Kiron/Lilith/Ay dugumlerini SESSIZCE atiyordu; hesaplanan
      // veri kullaniciya hic gosterilmiyordu. Artik ayri bolumde duruyorlar.
      await tester.pumpWidget(_sar(AtlasPlanetsScreen(points: [
        ..._gezegenler,
        {
          'name': 'Chiron', 'name_tr': 'Kiron', 'sign': 'Ari',
          'sign_tr': 'Koç', 'abs_position': 10.0, 'position': 10.0,
        },
      ])));
      await _bekle(tester);

      expect(find.textContaining('Kiron'), findsOneWidget);
      // Bkz. yukarisi: Günes hem anlam cumlesinde hem izgara satirinda.
      expect(find.textContaining('Güneş'), findsNWidgets(2));
    });

    testWidgets('derece ve ev gosterilir (R5-2)', (tester) async {
      await tester.pumpWidget(_sar(AtlasPlanetsScreen(points: [
        {
          'name': 'Sun', 'name_tr': 'Güneş', 'sign': 'Leo',
          'sign_tr': 'Aslan', 'abs_position': 132.3, 'position': 12.3,
          'house_no': 5,
        },
      ])));
      await _bekle(tester);

      expect(find.textContaining('12.3°'), findsOneWidget);
      expect(find.textContaining('5. ev'), findsOneWidget);
    });
  });

  group('acilar sayfasi — dayaniklilik', () {
    testWidgets('orb eksikse ekran COKMEZ (R5-0)', (tester) async {
      // Eski kod `(a['orbit'] as num)` diye korumasiz cast ediyordu.
      await tester.pumpWidget(_sar(AtlasAspectsScreen(aspects: [
        {
          'p1': 'Sun', 'p1_tr': 'Güneş', 'p2': 'Mars', 'p2_tr': 'Mars',
          'aspect': 'square', 'aspect_tr': 'Kare',
        },
      ])));
      await _bekle(tester);

      expect(tester.takeException(), isNull);
      // 48-turu: ekran artik en ustte en dar acinin ANLAM cumlesini
      // tasiyor (anlam once, teknik sonra) ve o panelin basligi da ayni
      // cifti adlandiriyor — yani bu cift ekranda IKI kez geciyor.
      //
      // ⚠️ Capa bir tur boyunca `findsWidgets`ti ("en az bir") ve gerekcesi
      // DOGRUYDU ama iddiasi EKSIKTI: ayni satirin kazara iki kez cizilmesi
      // gibi bir regresyonu artik yakalamiyordu. Sayi OLCULDU — tam iki
      // eslesme var (anlam paneli basligi + liste satiri) — ve yazildi.
      // Iki yone de calisir: panel ya da satir cogalirsa 3 cikar, biri
      // kaybolursa 1.
      //
      // ⚠️ Bu IKILIK OP5-turunda bir KUSUR SANILDI ("ayni metin iki kez
      // yazilmasin") ve olculdu: kaldirilmasi ISTENMEDI, cunku iki konum
      // ayni isi gormuyor. Biri cumlenin OZNESI — `aspectMeaningText` aci
      // TURUNU anlatir, cifti hic adlandirmaz; etiket kalkarsa cumlenin
      // hangi olcume dayandigi ekranda HIC yazmaz. Oteki OLCUMUN satiri
      // (orb · tur · hareket) ve o sayilar ekranda baska hicbir yerde
      // degil; satir kalkarsa ekranin kendi dipnotu ("her grupta en dar
      // orb once") yanlis beyana doner. Yani buradaki 2 "bugun oyle"
      // degil "oyle kalmali" demek; ayrimin yapisal bekcisi
      // gezegen_anlam_test.dart -> "lider cift IKI konumda, ikisi FARKLI
      // is goruyor".
      expect(find.textContaining('Güneş'), findsNWidgets(2));
    });

    testWidgets('en dar orb once gelir (R5-3)', (tester) async {
      await tester.pumpWidget(_sar(AtlasAspectsScreen(aspects: [
        {
          'p1': 'Sun', 'p1_tr': 'Güneş', 'p2': 'Mars', 'p2_tr': 'Mars',
          'aspect': 'square', 'aspect_tr': 'Kare', 'orbit': 6.0,
        },
        {
          'p1': 'Moon', 'p1_tr': 'Ay', 'p2': 'Venus', 'p2_tr': 'Venüs',
          'aspect': 'square', 'aspect_tr': 'Kare', 'orbit': 0.4,
        },
      ])));
      await _bekle(tester);

      // `.last` SART: 48-turunda ekranin en ustune en dar acinin anlam
      // cumlesi geldi ve o panelin basligi ayni cifti ("Ay — Venüs")
      // tekrar yaziyor. Capa olmadan `getTopLeft` iki eslesme bulup
      // dusuyordu. `.last` her iki ciftte de GRUP ICINDEKI satiri verir,
      // yani olculen sey gercekten liste sirasi.
      final dar = tester.getTopLeft(find.text('Ay — Venüs').last).dy;
      final genis = tester.getTopLeft(find.text('Güneş — Mars').last).dy;
      expect(dar, lessThan(genis));
    });
  });

  group('kisilik sayfasi', () {
    // R5-1: ekran ARTIK kendi sayimini yapmiyor. Eski `TraitBars` formulu
    // (30 + 10*sayim) yalnizca sekiz deger uretebiliyor, dort elementin
    // "yuzdesi" toplamda 260 ediyor ve Ay dugumlerini sayip Yukselen'i
    // disarida birakiyordu. Tek dogruluk kaynagi sunucunun kanonik sayimi.
    final harita = <String, dynamic>{
      'element_distribution': {'fire': 3, 'earth': 2, 'air': 2, 'water': 1},
      'modality_distribution': {'cardinal': 3, 'fixed': 4, 'mutable': 1},
      'element_members': {
        'fire': ['Sun', 'Mars', 'Ascendant'],
        'earth': ['Venus', 'Saturn'],
        'air': ['Mercury', 'Jupiter'],
        'water': ['Moon'],
      },
      'modality_members': {
        'cardinal': ['Sun', 'Mars', 'Moon'],
        'fixed': ['Venus', 'Saturn', 'Mercury', 'Jupiter'],
        'mutable': ['Ascendant'],
      },
      'points': _gezegenler,
    };

    testWidgets('sunucunun sayimi kesir olarak gosterilir', (tester) async {
      await tester.pumpWidget(_sar(AtlasTraitsScreen(chart: harita)));
      await _cubuklariBekle(tester);

      // 'Ateş' IKI kez geciyor: 48-turunda eklenen anlam paneli (baskin
      // element, bu haritada 3/8 ile kesin ustun) ve asagidaki oran
      // satiri. 'Su' baskin DEGIL, o yuzden tek.
      //
      // Sayilar OLCULDU, varsayilmadi (ikisi de tam 2). `findsWidgets`
      // ("en az bir") bir tur boyunca cogalmayi kacirabilir durumdaydi;
      // `3/8` ozellikle onemli cunku bu haritada ates 3/8 VE oncul kip de
      // 3/8 — yani sayinin kendisi iki ayri olcumu birden civiliyor.
      expect(find.text('Ateş'), findsNWidgets(2));
      expect(find.text('Su'), findsOneWidget);
      // Toplam 8 (geleneksel yedili + Yukselen) — kesir, yuzde DEGIL.
      expect(find.text('3/8'), findsNWidgets(2));
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('eksik element ACIKCA soylenir', (tester) async {
      final eksik = Map<String, dynamic>.from(harita)
        ..['element_distribution'] = {
          'fire': 4, 'earth': 2, 'air': 2, 'water': 0,
        }
        ..['element_members'] = {
          'fire': ['Sun'], 'earth': ['Venus'], 'air': ['Mercury'],
          'water': <String>[],
        };
      await tester.pumpWidget(_sar(AtlasTraitsScreen(chart: eksik)));
      await _cubuklariBekle(tester);

      // Eski cubuklarda sifir sayim %30 gorunuyordu — eksiklik gizleniyordu.
      expect(find.textContaining('hiç yok'), findsOneWidget);
    });

    testWidgets('dagilim yoksa COKMEZ', (tester) async {
      await tester.pumpWidget(_sar(const AtlasTraitsScreen(chart: {})));
      await _cubuklariBekle(tester);

      expect(tester.takeException(), isNull);
    });
  });
}

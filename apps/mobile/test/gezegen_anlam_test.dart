// Gezegen konumları ekranının anlam katmanı + açılar ekranındaki çift
// yazımın ÖLÇÜMÜ (OP5-turu, P3 paketi).
//
// Bu ekran "anlam önce" ailesinin TEK kaçağıydı ve bekçisi de YOKTU:
// `anlam_once_test.dart` nokta sayfasını, açı sayfasını, kişilik ekranını
// ve harita incelemeyi görüyor — `AtlasPlanetsScreen` için o dosyada
// SIFIR eşleşme var (ölçüldü). Yani kaçağı koruyan şey bir yanlış gerekçe
// değil, hiç bakılmamış olmasıydı.
//
// ⚠️ Bu dosya GÖRSEL iddia kurmaz. Flutter testinde her harf punto
// genişliğinde KARE çizilir; piksel/renk/ekran-görüntüsü kanıtı yalan
// söyler (depo dersi: `flutter-test-yazi-tipi-tuzagi`). Ölçülen şey
// YAPIDIR: widget varlığı/yokluğu, sayım ve sıralama (dy).
//
// ⚠️ Çapalar bilerek çeşitli ve hiçbiri elle yazılmış tek bir Türkçe
// kelimeye bağlı değil: beklenen cümleler ÜRÜNÜN KENDİ kurucularından
// (`yerlesimCumlesi`, `planetRoleText`) türetiliyor, yani bir çeviri
// düzeltmesi bekçiyi kör bırakmıyor — hem cümle hem bekçi birlikte
// değişiyor. İddialar ayrıca iki dilde birden koşuyor.
//
// ⚠️ Hareket KAPATILIYOR (`disableAnimations`): `_DetayIskelet` her bloğu
// `RythoReveal` ile kademeli açıyor ve `slideY` KONUMU oynatıyor — yani
// animasyon sürerken ölçülen dy gerçek sıra değil, o anki karedir.
// Kapatmak hem ölçümü kesinleştiriyor hem reduce-motion yolunu koşturuyor.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/atlas/atlas_detail_screens.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/widgets/glass.dart' show GlassPanel;

final _tr = lookupAppLocalizations(const Locale('tr'));
final _en = lookupAppLocalizations(const Locale('en'));

/// Gezegen listesi. **Güneş BİLEREK sonda**: ekranın anlam cümlesi
/// "listedeki ilk nokta" seçilerek de üretilebilirdi ve o kusur Güneş
/// başta olan bir fikstürle GÖRÜNMEZDİ (sunucunun nokta sayımı Güneş'i
/// başa koyuyor, yani gerçek veri bu körlüğü maskeler).
List<Map<String, dynamic>> _noktalar({
  bool gunes = true,
  bool supheli = false,
  int? gunesEv = 5,
}) =>
    [
      {
        'name': 'Moon', 'name_tr': 'Ay', 'sign': 'Pis', 'sign_tr': 'Balık',
        'position': 10.0, 'abs_position': 340.0, 'house_no': 11,
      },
      {
        'name': 'Mercury', 'name_tr': 'Merkür', 'sign': 'Gem',
        'sign_tr': 'İkizler', 'position': 4.0, 'abs_position': 64.0,
        'house_no': 3,
      },
      if (gunes)
        {
          'name': 'Sun', 'name_tr': 'Güneş', 'sign': 'Leo',
          'sign_tr': 'Aslan', 'position': 12.3, 'abs_position': 132.3,
          // Null-aware öğe: `gunesEv` yoksa ANAHTAR HİÇ GİRMEZ (saatsiz
          // haritanın gerçek hâli), `house_no: null` girmez.
          'house_no': ?gunesEv,
          if (supheli) 'uncertain': true,
        },
    ];

Widget _sar(Widget child, {String dil = 'tr'}) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(dil),
      // `copyWith` ŞART: `MediaQueryData()` boyutu Size.zero yapar ve
      // yerleşim sessizce çöker.
      home: Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: child,
        ),
      ),
    );

/// Yıldız alanı sürekli animasyonlu — `pumpAndSettle` hiçbir zaman dönmez.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

double _dy(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

/// Rol cümlesinin ETİKETİ ("Güneş", "Sun") — elle yazılmıyor, ürünün
/// kendi tablosundan kesiliyor. Ayırıcı ASCII iki nokta, yani Türkçe
/// `toLowerCase` tuzağı yok (`_ikiyeBol` sözleşmesinin aynısı).
String _ad(AppLocalizations l10n, String nokta) =>
    planetRoleText(l10n, nokta)!.split(':').first;

void main() {
  group('anlamNoktasi — öznenin seçimi', () {
    test('Güneş listenin NERESİNDE olursa olsun bulunur', () {
      // Sıraya bağlı bir seçim, sunucunun nokta sayımı değiştiği gün
      // sessizce başka bir gezegeni anlatmaya başlar.
      expect(anlamNoktasi(_noktalar())?['name'], equals('Sun'));
      expect(
          anlamNoktasi(_noktalar().reversed.toList())?['name'],
          equals('Sun'));
    });

    test('şüpheli işaretli Güneş özne OLMAZ', () {
      // Bugün sunucu `uncertain`i yalnız Ay'a basıyor, yani bu kapı
      // gerçek veride KAPANMIYOR — fikstür olmasa kör kalırdı.
      expect(anlamNoktasi(_noktalar(supheli: true)), isNull);
    });

    test('Güneş yoksa UYDURULMAZ', () {
      expect(anlamNoktasi(_noktalar(gunes: false)), isNull);
      expect(anlamNoktasi(const []), isNull);
    });
  });

  group('gezegen konumları: ilk görünen şey IZGARA DEĞİL', () {
    testWidgets('anlam cümlesi ızgaranın ÜSTÜNDE', (tester) async {
      await tester.pumpWidget(_sar(AtlasPlanetsScreen(points: _noktalar())));
      await _bekle(tester);

      final anlam = find.text(yerlesimCumlesi(_tr, 'Sun', 5)!);
      expect(anlam, findsOneWidget);
      expect(_dy(tester, anlam),
          lessThan(_dy(tester, find.byType(PlanetGrid).first)),
          reason: 'teknik ızgara anlamın üstüne çıktı');
    });

    testWidgets('özne GÜNEŞ — listenin ilki değil', (tester) async {
      await tester.pumpWidget(_sar(AtlasPlanetsScreen(points: _noktalar())));
      await _bekle(tester);

      expect(find.text(yerlesimCumlesi(_tr, 'Sun', 5)!), findsOneWidget);
      // Listede ÖNDE duran iki nokta ekranı açmıyor.
      expect(find.text(yerlesimCumlesi(_tr, 'Moon', 11)!), findsNothing);
      expect(find.text(yerlesimCumlesi(_tr, 'Mercury', 3)!), findsNothing);
    });

    testWidgets('şüpheli Güneş cümle ÜRETMEZ, ızgara DURUR', (tester) async {
      await tester.pumpWidget(
          _sar(AtlasPlanetsScreen(points: _noktalar(supheli: true))));
      await _bekle(tester);

      expect(find.text(yerlesimCumlesi(_tr, 'Sun', 5)!), findsNothing);
      // Cümlenin düşmesi ÖLÇÜMÜ düşürmüyor: ızgara yerinde.
      expect(find.byType(PlanetGrid), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Güneş yoksa BAŞKA noktaya kaymaz', (tester) async {
      await tester.pumpWidget(
          _sar(AtlasPlanetsScreen(points: _noktalar(gunes: false))));
      await _bekle(tester);

      expect(find.text(yerlesimCumlesi(_tr, 'Moon', 11)!), findsNothing);
      expect(find.text(yerlesimCumlesi(_tr, 'Mercury', 3)!), findsNothing);
      expect(find.byType(PlanetGrid), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saatsiz harita: EV UYDURULMAZ', (tester) async {
      // `house_no` yoksa cümle yalnız gezegen rolünü söyler; uydurulmuş
      // bir ev alanı eklenmez (`yerlesimCumlesi` sözleşmesi).
      final cumle = yerlesimCumlesi(_tr, 'Sun', null)!;
      expect(cumle, equals(planetRoleText(_tr, 'Sun')));

      await tester.pumpWidget(
          _sar(AtlasPlanetsScreen(points: _noktalar(gunesEv: null))));
      await _bekle(tester);

      expect(find.text(cumle), findsOneWidget);
    });

    testWidgets('panelin ETİKETİ YOK: ad ekranda İKİ kez', (tester) async {
      // Cümle öznesini kendi içinde söylüyor ("Güneş: …") ve ızgara satırı
      // da adı yazıyor; bir panel etiketi ÜÇÜNCÜ tekrar olurdu. Sayı iki
      // yöne de çalışır: etiket eklenirse 3, anlam katmanı düşerse 1.
      await tester.pumpWidget(_sar(AtlasPlanetsScreen(points: _noktalar())));
      await _bekle(tester);

      expect(find.textContaining(_ad(_tr, 'Sun')), findsNWidgets(2));
    });

    testWidgets('anlam paneline dokunuş O NOKTANIN dayanağını açıyor',
        (tester) async {
      // DOĞRULAMA TURUNDA EKLENDİ — paketin bıraktığı kör nokta.
      // `atlas_detail_screens.dart` "Panel DOKUNULABİLİR: … kullanıcı
      // anlamdan ölçüme inebilmeli" gerekçesini yazmış, ama dokunuşu
      // ölçen hiçbir bekçi yoktu. Minimal mutasyonla kanıtlandı: (a)
      // `onTap` satırı tamamen silindiğinde ve (b) yanlış noktaya
      // (`points.first`, yani fikstürde AY) bağlandığında ilgili beş
      // test dosyasının TAMAMI yeşil kalıyordu.
      //
      // (b) daha ağır: Güneş'in cümlesine dokunan kullanıcı AY'ın
      // derecesini/evini/hızını görürdü — ürünün çekirdek ilkesinin
      // ("ölçülen, yanlış adla sunulmaz") tam karşıtı ve ekranda hiçbir
      // hata belirtisi olmadan.
      //
      // Çapa ürünün KENDİ kurucusu, elle yazılmış bir dize değil:
      // alt-sayfa da `yerlesimCumlesi` basıyor, yani DOĞRU nokta
      // açıldığında aynı cümle iki yerde durur (panel + sayfa). Yanlış
      // nokta açılsaydı Ay'ın cümlesi görünürdü ve o cümle bu ekranda
      // hiç yok — yani çapa iki yöne de çalışıyor.
      await tester.pumpWidget(_sar(AtlasPlanetsScreen(points: _noktalar())));
      await _bekle(tester);

      final gunes = yerlesimCumlesi(_tr, 'Sun', 5)!;
      // Dipnot YALNIZ alt-sayfada var; açık/kapalı ayrımının bağımsız
      // işareti bu. Önce kapalı olduğu ölçülüyor, yoksa "açtı" iddiası
      // baştan doğru görünürdü.
      expect(find.text(_tr.pointSheetFootnote), findsNothing,
          reason: 'alt-sayfa dokunmadan acik — testin baslangici kirik');

      await tester.tap(find.text(gunes));
      await _bekle(tester);

      expect(find.text(_tr.pointSheetFootnote), findsOneWidget,
          reason: 'dokunus alt-sayfayi hic acmadi (onTap dustu)');
      expect(find.text(gunes), findsNWidgets(2),
          reason: 'acilan alt-sayfa GUNES in degil');
      expect(find.text(yerlesimCumlesi(_tr, 'Moon', 11)!), findsNothing,
          reason: 'dokunus YANLIS noktanin olcumunu acti');
    });

    testWidgets('İngilizce cihazda da anlam önce', (tester) async {
      await tester.pumpWidget(
          _sar(AtlasPlanetsScreen(points: _noktalar()), dil: 'en'));
      await _bekle(tester);

      final anlam = find.text(yerlesimCumlesi(_en, 'Sun', 5)!);
      expect(anlam, findsOneWidget);
      expect(_dy(tester, anlam),
          lessThan(_dy(tester, find.byType(PlanetGrid).first)));
      expect(find.text(yerlesimCumlesi(_en, 'Moon', 11)!), findsNothing);
      expect(find.textContaining(_ad(_en, 'Sun')), findsNWidgets(2));
    });
  });

  // -------------------------------------------------------------------
  // Açılar ekranındaki çift yazımın ÖLÇÜMÜ.
  //
  // Sahibin ilkesi "aynı metin iki kez yazılmasın" ve lider çifti o
  // ekranda iki kez geçiyor. Ölçüm bunun KALDIRILMASINI söylemedi:
  // iki konum aynı işi görmüyor. Aşağıdaki iki test o ayrımı çiviliyor
  // ki bir sonraki tur "tekrar var" diye bakıp birini atmasın.
  // -------------------------------------------------------------------
  group('açı anlam cümlesi ÇİFTİ ADLANDIRMAZ', () {
    test('beş açı türünün hiçbiri gezegen adı taşımıyor', () {
      // Bu, açılar panelindeki etiketin NEDEN yüklü olduğu: etiket
      // kalkarsa cümlenin hangi ölçüme dayandığı ekranda hiç yazmaz.
      for (final tur in [
        'conjunction',
        'opposition',
        'square',
        'trine',
        'sextile',
      ]) {
        for (final l10n in [_tr, _en]) {
          final metin = aspectMeaningText(l10n, tur)!;
          expect(metin, isNot(contains(_ad(l10n, 'Sun'))), reason: tur);
          expect(metin, isNot(contains(_ad(l10n, 'Mars'))), reason: tur);
        }
      }
    });

    test('rol cümlesi ÖZNESİNİ kendi içinde söylüyor', () {
      // Ters yön: gezegen ekranındaki panelin etiketsiz olması da aynı
      // ölçünün sonucu. İki iddia birlikte durmazsa biri bayatlar.
      for (final l10n in [_tr, _en]) {
        expect(yerlesimCumlesi(l10n, 'Sun', 5)!, contains(_ad(l10n, 'Sun')));
      }
    });

    testWidgets('lider çift İKİ konumda, ikisi FARKLI iş görüyor',
        (tester) async {
      // Orb BİLEREK yok: satır orb yuvasına '—' basıyor ve bu, satırın
      // ÖLÇÜM taşıdığının bağımsız işareti oluyor.
      await tester.pumpWidget(_sar(const AtlasAspectsScreen(aspects: [
        {
          'p1': 'Sun', 'p1_tr': 'Güneş', 'p2': 'Mars', 'p2_tr': 'Mars',
          'aspect': 'square', 'aspect_tr': 'Kare',
        },
      ])));
      await _bekle(tester);

      // Ayırıcı `aspectPairLabel`in kendi biçimi ("p1 — p2").
      final cift = find.text('Güneş — Mars');
      expect(cift, findsNWidgets(2));

      // Biri ANLAMIN öznesi: cümleyi taşıyan panelin içinde.
      expect(
          find.descendant(
              of: find.widgetWithText(GlassPanel, _tr.aspectMeaningSquare),
              matching: cift),
          findsOneWidget,
          reason: 'anlam cümlesinin öznesi ekranda yazmıyor');

      // Öteki ÖLÇÜMÜN satırı: orb yuvasını taşıyan panelin içinde.
      expect(
          find.descendant(
              of: find.widgetWithText(GlassPanel, '—'), matching: cift),
          findsOneWidget,
          reason: 'grubun en dar açısı listeden düştü; dipnot '
              '("her grupta en dar orb önce") yanlış beyan olur');
    });
  });
}

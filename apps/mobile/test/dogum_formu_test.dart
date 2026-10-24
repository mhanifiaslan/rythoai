// Doğum formu parçaları ve saat kapısı bekçileri.
//
// Ölçülen kusur (birth_record_screen:60): saati bilinmeyen kayıt açılırken
// `12:00` uyduruluyor, kullanıcı "biliyorum" deyip saat seçmeden kaydedince
// uydurma saat gerçek gibi yazılıyordu. `dogumSaatiGecerli` bu kapıyı saf
// tutar. Cinsiyet seçici seçilmeyeni beyan etmez (null → sıfır dolgu);
// saat-bilinmiyor kutusu işaretliyken kaybı söyler.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/birth_record.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/dogum_formu.dart';

final _tr = AppLocalizationsTr();

Widget _sar(Widget child) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: Column(children: [child])),
    );

/// Seçili segmentin dolgusu (`GlassSegments`): dolgulu AnimatedContainer
/// sayısı = seçili segment sayısı.
int _dolguluSegment(WidgetTester tester) => tester
    .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
    .where((c) => (c.decoration as BoxDecoration?)?.color != null)
    .length;

void main() {
  group('dogumSaatiGecerli — 12:00 uydurulmaz', () {
    test('"biliyorum" dendi ama saat seçilmedi → GEÇERSİZ', () {
      expect(dogumSaatiGecerli(biliniyor: true, saat: null), isFalse);
    });

    test('"biliyorum" + saat → geçerli; "bilmiyorum" her hâlde geçerli', () {
      expect(
          dogumSaatiGecerli(
              biliniyor: true, saat: const TimeOfDay(hour: 4, minute: 30)),
          isTrue);
      expect(dogumSaatiGecerli(biliniyor: false, saat: null), isTrue);
      expect(
          dogumSaatiGecerli(
              biliniyor: false, saat: const TimeOfDay(hour: 4, minute: 30)),
          isTrue);
    });

    test('saatMetni HH:mm; null → null (12:00 değil)', () {
      expect(saatMetni(const TimeOfDay(hour: 4, minute: 5)), '04:05');
      expect(saatMetni(const TimeOfDay(hour: 23, minute: 59)), '23:59');
      expect(saatMetni(null), isNull);
    });
  });

  group('CinsiyetSecici', () {
    testWidgets('seçili null → HİÇBİR segment dolgulu değil', (tester) async {
      await tester.pumpWidget(_sar(CinsiyetSecici(secili: null, onSec: (_) {})));
      await tester.pump();

      expect(find.text(_tr.genderFemale), findsOneWidget);
      expect(_dolguluSegment(tester), 0,
          reason: 'seçilmeyen cinsiyet beyan edilmez');
    });

    testWidgets('seçili male → tek dolgu; dokunuş değeri verir', (tester) async {
      String? secilen;
      await tester.pumpWidget(
          _sar(CinsiyetSecici(secili: 'male', onSec: (g) => secilen = g)));
      await tester.pump();

      expect(_dolguluSegment(tester), 1);
      await tester.tap(find.text(_tr.genderOther));
      expect(secilen, 'other');
    });

    testWidgets('dört değer, dördüncüsü unspecified', (tester) async {
      String? secilen;
      await tester.pumpWidget(
          _sar(CinsiyetSecici(secili: null, onSec: (g) => secilen = g)));
      await tester.pump();

      expect(CinsiyetSecici.degerler,
          ['female', 'male', 'other', 'unspecified']);
      // Dördüncü etiket ARB'den (`genderUnspecified`): sabit metin köprüsü
      // kalktı, dil dalı tek yerde (l10n).
      expect(find.text(_tr.genderUnspecified), findsOneWidget);
      await tester.tap(find.text(_tr.genderMale));
      expect(secilen, 'male');
    });
  });

  group('SaatBilinmiyorKutusu', () {
    testWidgets('işaretliyken "Yükselen ve evler hesaplanmaz" notu çıkar',
        (tester) async {
      await tester.pumpWidget(
          _sar(SaatBilinmiyorKutusu(bilinmiyor: true, onChanged: (_) {})));
      await tester.pump();

      expect(find.text(_tr.birthTimeUnknown), findsOneWidget);
      expect(find.text(_tr.wizardTimeUnknownNote), findsOneWidget);
    });

    testWidgets('işaretsizken not YOK; dokunuş değeri çevirir', (tester) async {
      bool? deger;
      await tester.pumpWidget(_sar(
          SaatBilinmiyorKutusu(bilinmiyor: false, onChanged: (v) => deger = v)));
      await tester.pump();

      expect(find.text(_tr.wizardTimeUnknownNote), findsNothing);
      await tester.tap(find.byType(Checkbox));
      expect(deger, isTrue);
    });
  });

  test('sehirEtiketi: bayrak + ad; ülke yoksa ad; şehir yoksa —', () {
    final tr = String.fromCharCodes([0x1F1F9, 0x1F1F7]);
    expect(sehirEtiketi('İstanbul', 'TR'), '$tr İstanbul');
    expect(sehirEtiketi('Tripoli', null), 'Tripoli');
    expect(sehirEtiketi('Tripoli', ''), 'Tripoli');
    expect(sehirEtiketi('  ', 'TR'), '—');
    expect(sehirEtiketi(null, null), '—');
  });

  test('sehirEtiketi: GeoNames\'in "Istanbul"u Türkçe yazımla görünür', () {
    // Mağaza çekimi (2026-10-24): kurulumun yer adımı ve doğum kaydı
    // "🇹🇷 Istanbul" basıyordu. Kayıtlı değer GeoNames adı ("Istanbul") —
    // sunucunun çözdüğü anahtar; düzeltme yalnız GÖSTERİMDE.
    final tr = String.fromCharCodes([0x1F1F9, 0x1F1F7]);
    expect(sehirEtiketi('Istanbul', 'TR'), '$tr İstanbul');
  });

  testWidgets('SecimSatiri etiket + değer gösterir, dokunuş çalışır',
      (tester) async {
    var dokunuldu = 0;
    await tester.pumpWidget(_sar(SecimSatiri(
      label: 'Doğum tarihi',
      value: '7 Mart 1988',
      onTap: () => dokunuldu++,
    )));
    await tester.pump();

    expect(find.text('Doğum tarihi'), findsOneWidget);
    expect(find.text('7 Mart 1988'), findsOneWidget);
    await tester.tap(find.text('7 Mart 1988'));
    expect(dokunuldu, 1);
  });
}

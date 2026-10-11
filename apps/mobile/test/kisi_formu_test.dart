// Kişi formu bekçileri (D6): cinsiyet ÖNSEÇİMSİZ (`unspecified` dahil dört
// seçenek), form parçaları ortak (`SecimSatiri`, `SaatBilinmiyorKutusu`),
// "biliyorum" deyip saat seçmeden kaydedilmez, modelde `'female'` yok.
//
// Ölçülen kusur: `Person.gender` varsayılanı `'female'` idi ve form onu
// seçili açıyordu — kullanıcı dokunmadan geçince üçüncü bir kişi adına
// "kadın" beyan ediliyordu; düzenleme kipinde kayıtta alan YOKKEN de
// "kadın seçili" görünüyordu (risk 9).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/people.dart';
import 'package:rytho/features/people/person_form_screen.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:rytho/widgets/dogum_formu.dart';
import 'package:rytho/widgets/glass.dart' show GlassSegments;
import 'package:rytho/widgets/nebula_widgets.dart' show SuggestionChip;

import 'cevrem_harness.dart';

final _tr = AppLocalizationsTr();

const _kModelYol = 'lib/core/people.dart';
const _kFormYol = 'lib/features/people/person_form_screen.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Future<void> _kur(WidgetTester tester, {Person? existing, double olcek = 1.0})
    async {
  // `UniqueKey`: aynı testte ikinci kurulum aynı State'i yeniden
  // kullanırdı ve `late` alanlar ilk kaydın değerinde kalırdı (ölçüldü).
  await tester.pumpWidget(sar(
    PersonFormScreen(key: UniqueKey(), existing: existing),
    overrides: [
      apiProvider.overrideWithValue(sahteDio(SahteAdapter(const {}))),
    ],
    olcek: olcek,
  ));
  await tester.pump();
}

CinsiyetSecici _secici(WidgetTester tester) =>
    tester.widget<CinsiyetSecici>(find.byType(CinsiyetSecici));

GoldButton _kaydet(WidgetTester tester) =>
    tester.widget<GoldButton>(find.widgetWithText(GoldButton, _tr.save));

void main() {
  group('model', () {
    test('cinsiyet varsayılanı YOK; yük `unspecified` taşır', () {
      const kisi = Person(
          id: 'x', relation: 'child', birthDate: '2015-06-01', birthCity: 'Urfa');
      expect(kisi.gender, isNull);
      expect(kisi.toBirthPayload()['gender'], kCinsiyetBelirtilmedi);
    });

    test('dokümanda alan yoksa null kalır; varsa olduğu gibi', () {
      final yok = Person.fromDoc('x', {'relation': 'child', 'birthDate': '2015-06-01'});
      expect(yok.gender, isNull, reason: 'beyan edilmemiş alan uydurulmaz');
      final var_ = Person.fromDoc(
          'x', {'relation': 'child', 'birthDate': '2015-06-01', 'gender': 'other'});
      expect(var_.gender, 'other');
    });

    test('kaynakta `female` önseçimi yok (model + form)', () {
      for (final yol in [_kModelYol, _kFormYol]) {
        expect(_yorumsuz(yol), isNot(contains("'female'")), reason: yol);
      }
    });
  });

  group('form', () {
    testWidgets('yeni kişi: cinsiyet seçili DEĞİL, dört seçenek', (tester) async {
      uzunYuzey(tester);
      await _kur(tester);
      expect(_secici(tester).secili, isNull);
      expect(tester.widget<GlassSegments>(find.byType(GlassSegments)).index,
          isNull, reason: 'bir segment dolu görünüyor — beyan edilmemiş seçim');
      expect(find.text(_tr.genderUnspecified), findsOneWidget);

      await tester.tap(find.text(_tr.genderUnspecified));
      await tester.pump();
      expect(_secici(tester).secili, kCinsiyetBelirtilmedi);
    });

    testWidgets('düzenleme: kayıtta beyan yoksa seçili yok, varsa o',
        (tester) async {
      uzunYuzey(tester);
      const beyansiz = Person(
          id: 'p', relation: 'parent', birthDate: '1960-01-01', birthCity: 'Urfa');
      await _kur(tester, existing: beyansiz);
      expect(_secici(tester).secili, isNull);

      const erkek = Person(
          id: 'p',
          relation: 'parent',
          birthDate: '1960-01-01',
          birthCity: 'Urfa',
          gender: 'male');
      await _kur(tester, existing: erkek);
      expect(_secici(tester).secili, 'male');
    });

    testWidgets('ortak form parçaları: üç seçim satırı + saat kutusu + çipler',
        (tester) async {
      uzunYuzey(tester);
      await _kur(tester);
      expect(find.byType(SecimSatiri), findsNWidgets(3));
      expect(find.byType(SaatBilinmiyorKutusu), findsOneWidget);
      // Yeni kişide saat BİLİNMİYOR başlar ve sonucu söylenir.
      expect(find.text(_tr.wizardTimeUnknownNote), findsOneWidget);
      // İlişki türü çipleri seçili-durum dilinde (degrade değil).
      final cipler = tester.widgetList<SuggestionChip>(find.byType(SuggestionChip));
      expect(cipler.length, kRelations.length);
      expect(cipler.where((c) => c.selected).length, 1);
    });

    testWidgets('"biliyorum" deyip saat seçmeyince Kaydet kapalı',
        (tester) async {
      uzunYuzey(tester);
      await _kur(tester);
      expect(_kaydet(tester).onPressed, isNotNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(_kaydet(tester).onPressed, isNull,
          reason: 'uydurma 12:00 gerçek saat gibi kaydedilirdi');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(_kaydet(tester).onPressed, isNotNull);
    });

    testWidgets('düzenleme: kayıtlı saat olduğu gibi görünür', (tester) async {
      uzunYuzey(tester);
      const es = Person(
          id: 'p',
          relation: 'partner',
          birthDate: '1990-03-12',
          birthTime: '07:05',
          birthCity: 'Ankara',
          birthNation: 'TR');
      await _kur(tester, existing: es);
      expect(find.text('07:05'), findsOneWidget);
      expect(find.text(_tr.wizardTimeUnknownNote), findsNothing);
      expect(_kaydet(tester).onPressed, isNotNull);
    });

    testWidgets('320 dp × 1,3 taşmaz', (tester) async {
      darYuzey(tester);
      const es = Person(
          id: 'p',
          relation: 'partner',
          birthDate: '1990-03-12',
          birthTime: '07:05',
          birthCity: 'Kahramanmaraş Onikişubat',
          birthNation: 'TR',
          label: 'Ada Aslanoğulları Karahanlıoğlu');
      await _kur(tester, existing: es, olcek: darOlcek);
      tasmaYok(tester, neden: 'kişi formu üst bloğu taşıyor');
      await kaydirarakTasmaAra(tester, find.byType(ListView),
          neden: 'kişi formu dar ekranda taşıyor');
    });
  });

  group('kaynak bekçileri', () {
    test('çıplak GestureDetector ve degrade durum göstergesi yok', () {
      final k = _yorumsuz(_kFormYol);
      expect(k, isNot(contains('GestureDetector(')));
      expect(k, isNot(contains('primaryGradient')));
      expect(k, isNot(contains('Colors.white')));
      expect(k, contains('CinsiyetSecici('));
      expect(k, contains('sehirEtiketi(_sehir, _ulke)'));
    });
  });
}

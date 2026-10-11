// Kişi ekranı bekçileri (D6): ANLAM ÖNCE (cümle Büyük Üçlü'nün ve çarkın
// ÜSTÜNDE, gerçek yerleşim ölçümüyle), silme onaylı, satırlar
// `ListeSatiri`, "Rytho'ya sor" natal tohumla tek bileşen, paylaşım kartı
// ilişki etiketiyle (AD değil).
//
// Anlam cümlesi SEÇİLİR, uydurulmaz: Harita İnceleme'nin iki kuralı aynı
// saf fonksiyonlarla (`baskinElement`, `liderGorunurAci`,
// `aspectMeaningText`). Kural `kisiAnlamCumlesi`de saf — ekran ağdan
// beslendiği için burada çivili.
//
// ⚠️ Bu ekran `anlam_once_bes_ekran_test`e altıncı ekran olarak KAYDEDİLMELİ
// (o dosya bu paketin sahipliğinde değil; dy ölçümü burada).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/people.dart';
import 'package:rytho/features/atlas/chart_inspector_screen.dart';
import 'package:rytho/features/chat/chat_screen.dart';
import 'package:rytho/features/people/person_detail_screen.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show RythoyaSor;
import 'package:rytho/widgets/basis_sheet.dart' show OlcumSatiri;
import 'package:rytho/widgets/chart/chart_data.dart';
import 'package:rytho/widgets/chart/chart_wheel.dart';
import 'package:rytho/widgets/glass.dart' show GlassPanel;
import 'package:rytho/widgets/liste_satiri.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cevrem_harness.dart';

final _tr = AppLocalizationsTr();

const _kYol = 'lib/features/people/person_detail_screen.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

const _kisi = Person(
    id: 'p1',
    relation: 'partner',
    birthDate: '1990-03-12',
    birthTime: '07:05',
    birthCity: 'Ankara',
    label: 'Ada');

Map<String, dynamic> _nokta(String ad, String yerel, double boylam) => {
      'name': ad,
      'name_local': yerel,
      'abs_position': boylam,
      'position': boylam % 30,
      'sign': 'Ari',
      'house_no': 1,
      'speed': 1.0,
    };

Map<String, dynamic> _aci(String tur, double orb, {String yerel = 'üçgen'}) => {
      'p1': 'Sun',
      'p2': 'Moon',
      'aspect': tur,
      'orbit': orb,
      'p1_local': 'Güneş',
      'aspect_local': yerel,
      'p2_local': 'Ay',
    };

/// Natal yükü: Büyük Üçlü + çark + açılar + element sayımı.
Map<String, dynamic> _harita({
  Map<String, int> elementler = const {'fire': 2, 'earth': 2, 'air': 1, 'water': 1},
  List<Map<String, dynamic>>? acilar,
}) =>
    {
      'sun_sign': 'Koç',
      'moon_sign': 'Yengeç',
      'ascendant': 'Aslan',
      'points': [
        _nokta('Sun', 'Güneş', 10.0),
        _nokta('Moon', 'Ay', 130.0),
        _nokta('Venus', 'Venüs', 40.0),
        _nokta('Mars', 'Mars', 200.0),
      ],
      'houses': [
        for (var i = 0; i < 12; i++)
          {'house': i + 1, 'abs_position': (120.0 + i * 30) % 360, 'sign': 'Leo'},
      ],
      'aspects': acilar ?? [_aci('trine', 2.0)],
      'element_distribution': elementler,
      'element_members': const {'fire': ['Sun']},
    };

/// Son kurulumun sahte sunucusu: hangi uca gidildiği buradan ölçülür.
late SahteAdapter _sunucu;

Future<RotaGozcusu> _kur(WidgetTester tester, Map<String, dynamic> harita,
    {double olcek = 1.0}) async {
  SharedPreferences.setMockInitialValues({});
  final gozcu = RotaGozcusu();
  _sunucu = SahteAdapter(const {});
  await tester.pumpWidget(sar(
    const PersonDetailScreen(person: _kisi),
    overrides: [
      apiProvider.overrideWithValue(sahteDio(_sunucu)),
      personChartProvider.overrideWith((ref, kisi) async => harita),
    ],
    gozcu: gozcu,
    olcek: olcek,
  ));
  await yerles(tester);
  return gozcu;
}

double _ust(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  // Çark ressamı GoogleFonts stilleri kullanır; testte ağdan font çekme
  // denemesi izleyen teste sızıyordu (chart_wheel_test gerekçesi).
  GoogleFonts.config.allowRuntimeFetching = false;

  group('kisiAnlamCumlesi (saf)', () {
    ChartData veri(Map<String, dynamic> h) => ChartData.fromNatal(h);

    test('kesin baskın element varsa element cümlesi', () {
      final h = _harita(elementler: const {'fire': 4, 'earth': 1, 'air': 1, 'water': 0});
      final a = kisiAnlamCumlesi(_tr, h, veri(h))!;
      expect(a.element, 'fire');
      expect(a.aci, isNull);
      expect(a.cumle, isNotEmpty);
    });

    test('eşitlikte element YOK → en dar görünür majör açı', () {
      final h = _harita(acilar: [_aci('square', 4.0, yerel: 'kare'), _aci('trine', 1.0)]);
      final a = kisiAnlamCumlesi(_tr, h, veri(h))!;
      expect(a.element, isNull);
      expect(a.aci?.kind, 'trine');
      expect(a.etiket, 'Güneş üçgen Ay');
    });

    test('minör açıya cümle UYDURULMAZ', () {
      final h = _harita(acilar: [_aci('quincunx', 0.2, yerel: 'yüzelli')]);
      expect(kisiAnlamCumlesi(_tr, h, veri(h)), isNull);
    });

    test('orb dışı açı görünmez, cümle yok', () {
      final h = _harita(acilar: [_aci('trine', 9.5)]);
      expect(kisiAnlamCumlesi(_tr, h, veri(h)), isNull,
          reason: 'çarkta çizilmeyen açı ekranın başında anlatılamaz');
    });

    test('hiçbir şey ölçülemezse null — boş yer uydurma cümleden iyidir', () {
      final h = _harita(acilar: const []);
      expect(kisiAnlamCumlesi(_tr, h, veri(h)), isNull);
    });
  });

  group('ekran', () {
    testWidgets('anlam cümlesi Büyük Üçlü\'nün ve çarkın ÜSTÜNDE', (tester) async {
      uzunYuzey(tester, genislik: 480);
      final h = _harita();
      await _kur(tester, h);
      final anlam = kisiAnlamCumlesi(_tr, h, ChartData.fromNatal(h))!;

      final anlamKarti = find.byWidgetPredicate(
          (w) => w is GlassPanel && w.label == anlam.etiket);
      final ucMuhur = find.byWidgetPredicate(
          (w) => w is GlassPanel && w.label == _tr.bigThreeTitle);
      expect(anlamKarti, findsOneWidget);
      expect(find.text(anlam.cumle), findsOneWidget);
      expect(ucMuhur, findsOneWidget);
      expect(find.byType(ChartWheel), findsOneWidget);

      expect(_ust(tester, anlamKarti), lessThan(_ust(tester, ucMuhur)),
          reason: 'ölçüm (Büyük Üçlü) anlamın üstüne çıktı');
      expect(_ust(tester, ucMuhur), lessThan(_ust(tester, find.byType(ChartWheel))));
      // Ölçüm satırı tek bileşen; Büyük Üçlü üç satır.
      expect(find.byType(OlcumSatiri), findsNWidgets(3));
    });

    testWidgets('"Rytho\'ya sor" en altta, natal tohum + kişi kimliği',
        (tester) async {
      uzunYuzey(tester, genislik: 480);
      final gozcu = await _kur(tester, _harita());

      expect(find.byType(RythoyaSor), findsOneWidget);
      expect(_ust(tester, find.byType(RythoyaSor)),
          greaterThan(_ust(tester, find.byType(ListeSatiri))));

      await tester.tap(find.byType(RythoyaSor));
      final rota = gozcu.itilenler.last as MaterialPageRoute<dynamic>;
      final sohbet =
          rota.builder(tester.element(find.byType(RythoyaSor))) as ChatScreen;
      expect(sohbet.initialText, _tr.chartAskPrefillNatal('Ada'));
      expect(sohbet.personId, 'p1');
    });

    testWidgets('silme onaylı; vazgeçince hiçbir şey olmaz', (tester) async {
      uzunYuzey(tester, genislik: 480);
      await _kur(tester, _harita());
      await tester.tap(find.byTooltip(_tr.peopleRemove));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_tr.peopleRemoveConfirm), findsOneWidget);
      await tester.tap(find.text(_tr.cancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PersonDetailScreen), findsOneWidget);
      // "Hiçbir şey olmaz"ın ölçüsü sunucu: vazgeçiş silme isteği göndermez.
      // (Ekranın yerinde kalması tek başına kör — kök rota zaten pop edilemez.)
      expect(_sunucu.istekler.where((r) => r.method == 'DELETE'), isEmpty,
          reason: 'vazgeçildiği hâlde sunucuya silme gitti');
    });

    testWidgets('gömülü çark SALT ÖNİZLEME: dokunuş kişinin İnceleme\'sini açar',
        (tester) async {
      uzunYuzey(tester, genislik: 480);
      final h = _harita();
      final gozcu = await _kur(tester, h);

      final cark = tester.widget<ChartWheel>(find.byType(ChartWheel));
      expect(cark.onTap, isNotNull, reason: 'gömülü çark salt önizleme değil');
      expect(cark.onPlanetTap, isNull,
          reason: 'iki etkileşim modeli yan yana — alt-sayfa yalnız İnceleme\'de');
      expect(cark.onAspectTap, isNull);
      expect(cark.interactive, isFalse);

      // Geri çağrı DOĞRUDAN: çarka dokunmak çift-dokunuş sayacını bekletir
      // (pending timer), pompalamak ise İnceleme'yi monte eder (profil
      // akışı → Firebase). Jest → onTap sözleşmesi B'nin
      // cark_onizleme_sozlesme_test'inde; burada ölçülen, onTap'ın NEREYE
      // gittiği.
      cark.onTap!();
      final rota = gozcu.itilenler.last as MaterialPageRoute<dynamic>;
      final inceleme = rota.builder(tester.element(find.byType(ChartWheel)))
          as ChartInspectorScreen;
      expect(inceleme.mode, ChartInspectorMode.natal);
      expect(inceleme.person, _kisi, reason: 'kullanıcının değil KİŞİNİN çarkı');
      expect(inceleme.natalOverride, same(h),
          reason: 'aynı harita yeniden indirilmesin');
      expect(inceleme.titleOverride, 'Ada');
    });

    testWidgets('paylaşım AppBar\'da, ilişki satırı ListeSatiri', (tester) async {
      uzunYuzey(tester, genislik: 480);
      await _kur(tester, _harita());
      expect(find.byTooltip(_tr.shareReading), findsOneWidget);
      expect(find.byTooltip(_tr.edit), findsOneWidget);
      expect(find.widgetWithText(ListeSatiri, _tr.relationshipTitle('Ada')),
          findsOneWidget);
    });

    testWidgets('320 dp × 1,3 taşmaz', (tester) async {
      darYuzey(tester);
      await _kur(tester, _harita(), olcek: darOlcek);
      tasmaYok(tester, neden: 'kişi ekranı üst bloğu taşıyor');
      await kaydirarakTasmaAra(tester, find.byType(ListView),
          neden: 'kişi ekranı dar ekranda taşıyor');
    });
  });

  group('kaynak bekçileri', () {
    test('onay tek kapıdan; kendi AlertDialog kopyası yok', () {
      final k = _yorumsuz(_kYol);
      expect(k, isNot(contains('AlertDialog(')));
      expect(k, contains('onayla('));
      expect(k, contains('destructive: true'));
    });

    test('paylaşım kartına ilişki etiketi gider, AD gitmez', () {
      final k = _yorumsuz(_kYol);
      expect(k, contains('title: iliskiEtiketi'));
      expect(k, isNot(contains('title: ad,')));
      expect(k, contains('label: iliskiEtiketi'));
    });

    test('ilişki etiketi mono (veri) rolünde değil', () {
      expect(_yorumsuz(_kYol), isNot(contains('RythoText.mono(')));
    });

    test('gezegen alt-sayfası gömülü çarktan ÇIKTI; tek kapı İnceleme', () {
      final k = _yorumsuz(_kYol);
      expect(k, contains('onTap: incelemeyiAc'));
      expect(k, isNot(contains('onPlanetTap')),
          reason: 'gezegen alt-sayfası yalnız İnceleme\'de');
      expect(k, isNot(contains('showPointSheet')));
    });
  });
}

// İlişki ekranı bekçileri (D6): `fallback` tek noktadan, destekleyici /
// zorlayıcı satır renkten başka bir işaret taşır (▴/▾), eksen adı tohuma
// tırnakla ve DÖNÜŞÜMSÜZ girer, "Rytho'ya sor" tek bileşen.
//
// Ekran gerçek ağaç: sahte sunucu `/reports/relationship` yükünü verir.
// Tohum, itilen rotadan ChatScreen monte EDİLMEDEN okunur (harness).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/friends.dart';
import 'package:rytho/core/okuma_durumu.dart';
import 'package:rytho/features/chat/chat_screen.dart';
import 'package:rytho/features/friends/relationship_screen.dart';
import 'package:rytho/features/paywall/plus_locked_card.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show MarginNote, RythoyaSor;
import 'package:rytho/widgets/common.dart' show ErrorCard;
import 'package:rytho/widgets/glass.dart' show GlassPanel;
import 'package:shared_preferences/shared_preferences.dart';

import 'cevrem_harness.dart';

final _tr = AppLocalizationsTr();

const _kYol = 'lib/features/friends/relationship_screen.dart';
const _kGlifler = 'assets/fonts/RythoGlyphs.codepoints.txt';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

const _arkadas = Friend(
    uid: 'u1', status: FriendStatus.accepted, displayName: 'Zeynep');

Map<String, dynamic> _yuk({
  bool kilitli = false,
  bool sablon = false,
  String? okuma = 'ANA TEMA: konuşmak ikinize kolay geliyor.',
}) =>
    {
      'data': {
        'axes': [
          {
            'axis': 'communication',
            'axis_local': 'İletişim',
            'level': 'strong',
            'level_local': 'Belirgin',
            'tone': 'flowing',
            'tone_local': 'Akıcı',
            'line': 'Konuşmak ikinize kolay geliyor.',
            'basis': [
              {
                'p1_local': 'Güneş',
                'aspect_local': 'üçgen',
                'p2_local': 'Ay',
                'orb': 2.1,
                'supportive': true,
              },
              {
                'p1_local': 'Mars',
                'aspect_local': 'kare',
                'p2_local': 'Satürn',
                'orb': 3.0,
                'supportive': false,
              },
            ],
          },
          {
            'axis': 'bond',
            'axis_local': 'Bağ',
            'level': 'quiet',
            'level_local': 'Sessiz',
            'tone': null,
            'tone_local': null,
            'line': '',
            'basis': <Map<String, dynamic>>[],
          },
        ],
        'footnote': 'Dipnot.',
        'today': {
          'hits': [
            {'text': 'Venüs bugün Ay konumunuza üçgen', 'supportive': true},
            {'text': 'Mars Güneş konumunuza kare', 'supportive': false},
          ],
        },
        'reading': okuma,
        'reading_locked': kilitli,
        'fallback': sablon,
        'refunded': false,
      },
    };

Future<RotaGozcusu> _kur(WidgetTester tester, Map<String, dynamic> yuk,
    {double olcek = 1.0}) async {
  SharedPreferences.setMockInitialValues({});
  final gozcu = RotaGozcusu();
  await tester.pumpWidget(sar(
    const RelationshipScreen(friend: _arkadas),
    overrides: [
      apiProvider.overrideWithValue(sahteDio(
          SahteAdapter({'/reports/relationship': jsonEncode(yuk)}))),
    ],
    gozcu: gozcu,
    olcek: olcek,
  ));
  await yerles(tester);
  return gozcu;
}

void main() {
  group('saf kurallar', () {
    test('▴/▾ öneki glif fontunun ÖLÇÜLÜ kapsamında', () {
      final kapsam = File(_kGlifler).readAsStringSync();
      for (final destekleyici in [true, false]) {
        final onek = dayanakOneki(destekleyici: destekleyici);
        expect(onek.runes.length, 1);
        final kod =
            'U+${onek.runes.first.toRadixString(16).toUpperCase().padLeft(4, '0')}';
        expect(kapsam, contains(kod),
            reason: '$onek ($kod) glif fontunda yok — tofu üretir');
      }
      expect(dayanakOneki(destekleyici: true),
          isNot(dayanakOneki(destekleyici: false)));
    });

    test('iliskiOkumaDurumu: kilit önce, gerisi tek fonksiyondan', () {
      expect(iliskiOkumaDurumu({'reading_locked': true, 'reading': 'x'}),
          isA<OkumaKilitli>(),
          reason: 'kilitli yükte metin gelse bile çizilmez');
      expect(
          iliskiOkumaDurumu(
              {'reading_locked': false, 'reading': 'x', 'fallback': true}),
          isA<OkumaUretilemedi>().having((d) => d.iadeli, 'iadeli', isFalse),
          reason: 'jetonsuz uç: iade cümlesi YALAN olurdu');
      expect(iliskiOkumaDurumu({'reading_locked': false, 'reading': '  '}),
          isA<OkumaUretilemedi>());
      expect(iliskiOkumaDurumu({'reading_locked': false, 'reading': 'x'}),
          isA<OkumaHazir>().having((d) => d.metin, 'metin', 'x'));
    });
  });

  group('ekran', () {
    testWidgets('bugün satırları ▴/▾ önekli; dayanak açılınca da',
        (tester) async {
      uzunYuzey(tester);
      await _kur(tester, _yuk());

      expect(find.text('▴ Venüs bugün Ay konumunuza üçgen'),
          findsOneWidget);
      expect(find.text('▾ Mars Güneş konumunuza kare'), findsOneWidget);

      await tester.tap(find.text(_tr.relationshipBasisTitle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('▴ Güneş üçgen Ay · 2.1°'), findsOneWidget);
      expect(find.text('▾ Mars kare Satürn · 3.0°'), findsOneWidget);
    });

    testWidgets('"Rytho\'ya sor" tek bileşen: bugün + belirgin eksen + okuma',
        (tester) async {
      uzunYuzey(tester);
      await _kur(tester, _yuk());
      // Sessiz eksende kapı yok — soracak bir şey ölçülmedi.
      expect(find.byType(RythoyaSor), findsNWidgets(3));
      expect(find.byType(MarginNote), findsOneWidget);
    });

    testWidgets('eksen tohumu: ad tırnakta, dönüşüm YOK', (tester) async {
      uzunYuzey(tester);
      final gozcu = await _kur(tester, _yuk());

      final eksenKarti = find.ancestor(
          of: find.text('İletişim'), matching: find.byType(GlassPanel));
      await tester.tap(find.descendant(
          of: eksenKarti.first, matching: find.byType(RythoyaSor)));
      // pump YOK: rota kuruldu ama sayfası çizilmedi (Firebase istemez).
      final rota = gozcu.itilenler.last as MaterialPageRoute<dynamic>;
      final sohbet = rota.builder(tester.element(find.byType(GlassPanel).first))
          as ChatScreen;
      expect(sohbet.initialText, _tr.relationshipAskPrefill('Zeynep', 'İletişim'));
      expect(sohbet.initialText, contains('"İletişim"'));
      expect(sohbet.initialText!.codeUnits, isNot(contains(0x0307)),
          reason: 'toLowerCase İ → i + birleşik nokta üretiyordu');
      expect(sohbet.friendUid, 'u1');
    });

    testWidgets('kilitli okuma: katalog kartı, metin yok', (tester) async {
      uzunYuzey(tester);
      await _kur(tester, _yuk(kilitli: true));
      expect(find.byType(PlusLockedCard), findsOneWidget);
      expect(find.byType(MarginNote), findsNothing);
      expect(find.text(_tr.relationshipReadingLocked), findsOneWidget);
    });

    testWidgets('şablon okuma: dürüst kart + tekrar dene, metin yok',
        (tester) async {
      uzunYuzey(tester);
      await _kur(tester, _yuk(sablon: true, okuma: 'ŞABLON PARAGRAF'));
      expect(find.byType(MarginNote), findsNothing);
      expect(find.text('ŞABLON PARAGRAF'), findsNothing,
          reason: 'şablon rapor gibi gösterildi');
      expect(find.byType(ErrorCard), findsOneWidget);
      expect(find.text(_tr.reportUnavailable), findsOneWidget,
          reason: 'jetonsuz uçta iade cümlesi çıkmamalı');
    });

    testWidgets('320 dp × 1,3 taşmaz', (tester) async {
      darYuzey(tester);
      await _kur(tester, _yuk(), olcek: darOlcek);
      tasmaYok(tester, neden: 'ilişki ekranı üst bloğu taşıyor');
      await tester.tap(find.text(_tr.relationshipBasisTitle));
      await tester.pump();
      tasmaYok(tester, neden: 'dayanak satırları taşıyor');
      await kaydirarakTasmaAra(tester, find.byType(ListView),
          neden: 'ilişki ekranı dar ekranda taşıyor');
    });
  });

  group('kaynak bekçileri', () {
    test('büyük/küçük harf dönüşümü yok; satır içi ✦ kopyası yok', () {
      final k = _yorumsuz(_kYol);
      expect(k, isNot(contains('toLowerCase')));
      expect(k, isNot(contains('signalAsk')),
          reason: 'etiket yalnız RythoyaSor içinde okunur');
    });

    test('fallback tek noktadan, kilit ayrı bayraktan', () {
      final k = _yorumsuz(_kYol);
      expect(k, contains("okumaDurumuFromYanit(data, alan: 'reading')"));
      expect(k, contains("data['reading_locked'] == true"));
      expect(k, contains('ozellik: PlusOzellik.dyad'));
      expect(k, isNot(contains("emoji: '💞'")));
    });

    test('hareket: RythoReveal, kopya stagger yok; bölme kapısı dalla', () {
      final k = _yorumsuz(_kYol);
      expect(k, isNot(contains('.animate(')));
      expect(k, contains('RythoReveal('));
      // `AnimatedSize` sıfır sürede kendi yerleşiminde fırlar: kapı süre
      // değil DAL ile kurulur (reduceMotion → çıplak çocuk).
      expect(k, isNot(contains('AnimatedCrossFade(')));
      expect(k, contains('? cocuk'));
      expect(k, contains('reduceMotion(context)'));
    });
  });
}

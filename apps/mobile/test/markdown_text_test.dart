import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/widgets/markdown_text.dart';

/// R5-4'un degismezi: uretilen metin EKRANDA ham isaret gostermez.
///
/// Cihaz turunda tam rapor sayfasi "### 1. Oz Kimlik" ve "**Safravi**" diye
/// basiyordu. Metin duz `Text` ile ciziliyordu; modelin urettigi yapi hic
/// cozulmuyordu. Asagidaki testler cozucunun sozlesmesini korur.

const _ornek = '''
### 1. Öz Kimlik

Güneş'in **Aslan**'da olması, kendini gösterme ihtiyacını öne çıkarır.
Bu ihtiyaç sahne aramaz; tanınma arar.

- Ateş baskın
- Su eksik

## Yıl boyunca

Sıradan bir paragraf.
''';

void main() {
  group('bloklara ayirma', () {
    test('baslik seviyesiyle birlikte taninir', () {
      final bloklar = parseBlocks(_ornek);
      final basliklar = bloklar
          .where((b) => b.type == MarkdownBlockType.heading)
          .toList();

      expect(basliklar.length, 2);
      expect(basliklar.first.text, '1. Öz Kimlik');
      expect(basliklar.first.level, 3);
      expect(basliklar.last.level, 2);
    });

    test('madde satirlari paragraftan ayrilir', () {
      final maddeler = parseBlocks(_ornek)
          .where((b) => b.type == MarkdownBlockType.bullet)
          .map((b) => b.text)
          .toList();

      expect(maddeler, ['Ateş baskın', 'Su eksik']);
    });

    test('ardisik satirlar TEK paragrafta birlesir', () {
      // Model cumleleri satir sonuyla boluyor; her satiri ayri paragraf
      // saymak metni parcali gosterirdi.
      final paragraflar = parseBlocks(_ornek)
          .where((b) => b.type == MarkdownBlockType.paragraph)
          .toList();

      expect(paragraflar.first.text, contains('sahne aramaz'));
      expect(paragraflar.first.text, contains('Aslan'));
    });

    test('bos metin cokmez', () {
      expect(parseBlocks(''), isEmpty);
      expect(parseBlocks('\n\n   \n'), isEmpty);
    });
  });

  // Mağaza çekimi (2026-10-24, tam rapor): model "4. evdeki Güneş ve retro
  // Merkür yığılması…" diye bir CÜMLE yazdı; çözücü `\d+[.)]` önekini madde
  // imi sayıp sayıyı attı, ekranda "• evdeki Güneş…" kaldı. Aynı desen
  // gerçek numaralı listelerin de numarasını siliyordu (hepsi nokta oluyordu).
  group('sayıyla başlayan satır', () {
    const cumle = '### 2. Gezegen Vurguları: Kökler ve İçsel Sığınak\n\n'
        '4. evdeki Güneş ve retro Merkür yığılması, yaşam enerjinin '
        'büyük kısmını soy ağacına kurduğunu gösteriyor.';

    test('Türkçe sıra sayısıyla başlayan cümle paragraf kalır, sayı yutulmaz',
        () {
      final bloklar = parseBlocks(cumle);
      expect(bloklar.where((b) => b.type == MarkdownBlockType.bullet),
          isEmpty,
          reason: 'cümle madde imi sanıldı');
      expect(bloklar.last.type, MarkdownBlockType.paragraph);
      expect(bloklar.last.text, startsWith('4. evdeki Güneş'));
    });

    test('gerçek numaralı liste numarasını taşır', () {
      final maddeler = parseBlocks(
              '1. **Kariyer**: sabır ister.\n2. **Aşk**: açıklık ister.')
          .where((b) => b.type == MarkdownBlockType.bullet)
          .toList();
      expect(maddeler.map((b) => b.numara), [1, 2]);
      expect(maddeler.map((b) => b.text),
          ['**Kariyer**: sabır ister.', '**Aşk**: açıklık ister.']);
    });

    test('küçük harfle başlayan gerçek liste de liste kalır', () {
      // Sıra sayısı sezgisi (küçük harf → cümle) listeyi bölmesin: 1 ile
      // açılan ve ardışık süren dizi listedir.
      final bloklar =
          parseBlocks('1. sabah yürüyüşü\n2. akşam günlüğü\n3. erken uyku');
      expect(bloklar.map((b) => b.type),
          everyElement(MarkdownBlockType.bullet));
      expect(bloklar.map((b) => b.numara), [1, 2, 3]);
    });

    test('tire maddesi numarasız kalır', () {
      final madde = parseBlocks('- Ateş baskın').single;
      expect(madde.type, MarkdownBlockType.bullet);
      expect(madde.numara, isNull);
    });

    test('düz metinde sayı ve numara korunur', () {
      final duz = markdownToPlain('$cumle\n\n1. Kariyer\n2. Aşk');
      expect(duz, contains('4. evdeki Güneş'));
      expect(duz, contains('1. Kariyer'));
      expect(duz, contains('2. Aşk'));
      expect(duz, isNot(contains('• evdeki')));
    });

    testWidgets('ekranda cümle sayısıyla, liste numarasıyla çizilir',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(
            child: MarkdownText('$cumle\n\n1. Kariyer\n2. Aşk'))),
      ));
      await tester.pump();

      expect(find.textContaining('4. evdeki Güneş'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
    });
  });

  group('duz metne cevirme (paylasim karti)', () {
    test('isaretler soyulur, yapi korunur', () {
      final duz = markdownToPlain(_ornek);

      expect(duz, isNot(contains('#')));
      expect(duz, isNot(contains('**')));
      // `replaceAll` geri basvuru desteklemedigi icin bir ara `$1` yaziyordu.
      expect(duz, isNot(contains(r'$1')));
      expect(duz, contains('Aslan'));
      expect(duz, contains('• Ateş baskın'));
      expect(duz, contains('1. Öz Kimlik'));
    });
  });

  group('ekranda cizim', () {
    testWidgets('ham isaret GORUNMEZ', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(
            child: MarkdownText(_ornek))),
      ));
      await tester.pump();

      expect(find.textContaining('###'), findsNothing);
      expect(find.textContaining('**'), findsNothing);
      // Baslik metni kendisi duruyor — soyulan yalnizca isaret.
      expect(find.text('1. Öz Kimlik'), findsOneWidget);
    });

    testWidgets('kalin bolum w700 span olur', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('Güneş **Aslan**da.')),
      ));
      await tester.pump();

      final zengin = tester.widget<Text>(find.byType(Text).first);
      final parcalar = <InlineSpan>[];
      zengin.textSpan!.visitChildren((s) {
        parcalar.add(s);
        return true;
      });
      final kalin = parcalar.whereType<TextSpan>().where(
          (s) => s.style?.fontWeight == FontWeight.w700);
      expect(kalin.map((s) => s.text), contains('Aslan'));
    });
  });
}

// Sohbet mesaj modeli ve hata satırı bekçileri (D6).
//
// Ölçülen kusur: HER hata Rytho'nun ağzından bir balon olarak basılıyordu
// ("Bağlantı kurulamadı" mor degradede, Rytho'nun sözü gibi) ve o balon
// bir sonraki mesajla birlikte GEÇMİŞ olarak sunucuya gidiyordu — model
// kendi "cevabı" sanıp ona göre devam ediyordu. 402'de ise sunucunun
// `detail` cümlesi hem mağaza ekranı hem balon olarak iki kez düşüyor,
// kullanıcının yazdığı metin gönderimden önce silindiği için kayboluyordu.
//
// Dört ölçü: (1) `chatHistoryPayload` SAF — hata/sistem satırları tele
// çıkmaz, sözleşme `{'sender': 'USER'|'AI', 'text'}`; (2) catch gövdesi
// `rytho` türü üretmez; (3) 402 dalı metni giriş alanına geri yazar ve
// balon eklemez; (4) Rytho balonu markdown'ı çözer, uzun basışla paylaşır.
//
// `ChatScreen` MONTE EDİLMİYOR (gönderim ağ ister); kaynak bekçileri
// yorumları atarak okur — bir yorumun içindeki `_messages.add` sayılmasın.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/chat/chat_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/markdown_text.dart' show MarkdownText;

const _kYol = 'lib/features/chat/chat_screen.dart';

/// Tam satır yorumları atılır (tohum_gecer_gonderilmez_test deseni).
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// [imza]dan sonraki ilk `{` ile eşleşen `}` arasındaki blok.
String _blok(String kaynak, String imza) {
  final i = kaynak.indexOf(imza);
  expect(i, greaterThanOrEqualTo(0), reason: 'kaynakta yok: $imza');
  final bas = kaynak.indexOf('{', i + imza.length);
  var derinlik = 0;
  for (var j = bas; j < kaynak.length; j++) {
    if (kaynak[j] == '{') derinlik++;
    if (kaynak[j] == '}' && --derinlik == 0) {
      return kaynak.substring(bas, j + 1);
    }
  }
  fail('blok kapanmadı: $imza');
}

SohbetMesaji _k(String t) => SohbetMesaji(MesajTuru.kullanici, t);
SohbetMesaji _r(String t) => SohbetMesaji(MesajTuru.rytho, t);
SohbetMesaji _h(String t) => SohbetMesaji(MesajTuru.hata, t);
SohbetMesaji _s(String t) => SohbetMesaji(MesajTuru.sistem, t);

Widget _sar(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('chatHistoryPayload — saf', () {
    test('hata ve sistem satırları sunucuya GİTMEZ', () {
      final tel = chatHistoryPayload(
          [_k('soru'), _h('Bağlantı kurulamadı'), _s('Konu yüklenemedi'), _r('cevap')]);
      expect(tel, [
        {'sender': 'USER', 'text': 'soru'},
        {'sender': 'AI', 'text': 'cevap'},
      ]);
    });

    test('tel sözleşmesi USER/AI, Türkçe enum adı tele çıkmaz', () {
      final tel = chatHistoryPayload([_k('a'), _r('b')]);
      expect(tel.map((m) => m['sender']), ['USER', 'AI']);
      expect(tel.toString(), isNot(contains('kullanici')));
      expect(tel.toString(), isNot(contains('rytho')));
    });

    test('pencere: yalnız son 20 tur gider', () {
      final tel = chatHistoryPayload([for (var i = 0; i < 25; i++) _k('$i')]);
      expect(tel.length, kSohbetPenceresi);
      expect(tel.first['text'], '5');
      expect(tel.last['text'], '24');
    });

    test('pencere SÜZDÜKTEN sonra: hata satırları gerçek turları itmez', () {
      // 20 gerçek tur + 5 hata: eski (süzmesiz) kod 20'ye kırparken beş
      // gerçek turu düşürürdü.
      final tel = chatHistoryPayload([
        for (var i = 0; i < 20; i++) _k('$i'),
        for (var i = 0; i < 5; i++) _h('x'),
      ]);
      expect(tel.length, 20);
      expect(tel.first['text'], '0');
    });

    test('arşiv gönderen dizesi: AI → rytho, gerisi kullanıcı', () {
      expect(SohbetMesaji.turuCoz('AI'), MesajTuru.rytho);
      expect(SohbetMesaji.turuCoz('USER'), MesajTuru.kullanici);
      // Tanınmayan değerde emniyetli taraf: Rytho'ya söylemediği söz
      // yüklenmez.
      expect(SohbetMesaji.turuCoz('garip'), MesajTuru.kullanici);
    });

    test('sunucuyaGider yalnız kullanıcı ve Rytho', () {
      expect(_k('a').sunucuyaGider, isTrue);
      expect(_r('a').sunucuyaGider, isTrue);
      expect(_h('a').sunucuyaGider, isFalse);
      expect(_s('a').sunucuyaGider, isFalse);
    });
  });

  group('kaynak bekçisi (yorumsuz)', () {
    final k = _yorumsuz(_kYol);

    test('catch gövdesinde rytho türü YOK — hata Rytho\'nun sözü değildir',
        () {
      final bas = k.indexOf('} on DioException catch');
      final son = k.indexOf('} finally {', bas);
      expect(bas, greaterThanOrEqualTo(0));
      expect(son, greaterThan(bas));
      final yakalama = k.substring(bas, son);
      expect(yakalama, isNot(contains('MesajTuru.rytho')),
          reason: 'hata balonu Rytho balonu olarak basılıyor');
      expect(yakalama, contains('MesajTuru.hata'));
    });

    test('402 dalı: metin giriş alanına GERİ yazılır, balon EKLENMEZ', () {
      // Mağazayı interceptor açıyor; sohbetin tek işi gönderilmemiş metni
      // kaybetmemek.
      final dal = _blok(k, 'statusCode == kPaywallStatus) ');
      expect(dal, contains('_controller.text ='),
          reason: 'kullanıcının yazdığı metin 402\'de kaybolur');
      expect(dal, isNot(contains('_messages.add')),
          reason: 'sunucunun detail cümlesi balon olarak düşer (ikinci yüzey)');
    });

    test('geçmiş saf fonksiyondan kurulur, satır içi map yok', () {
      final gonder = _blok(k, 'Future<void> _gonder(');
      expect(gonder, contains('chatHistoryPayload('));
      expect(gonder, isNot(contains("'sender': m.sender")),
          reason: 'tel sözleşmesi iki yerde yaşarsa biri ayrışır');
    });

    test('hata satırı Tekrar dene taşır (ErrorCard onRetry)', () {
      final hata = k.substring(k.indexOf('case MesajTuru.hata:'),
          k.indexOf('case MesajTuru.sistem:'));
      expect(hata, contains('ErrorCard('));
      expect(hata, contains('onRetry: () => _tekrarDene('));
    });

    test('tohum düşerse sistem satırı + yeniden dene', () {
      final seed = _blok(k, 'Future<void> _seed()');
      expect(seed, contains('MesajTuru.sistem'),
          reason: 'arşiv hatası yalnız log\'a düşüyor, ekran boş kalıyor');
      expect(seed, contains('chatSeedFailed'));
      final sistem = k.substring(k.indexOf('case MesajTuru.sistem:'),
          k.indexOf('case MesajTuru.kullanici:'));
      expect(sistem, contains('_tohumuYenidenDene('));
    });

    test('Rytho cevabı: ensureVisible(alignment: 0) — cevabın BAŞI üstte',
        () {
      expect(k, contains('Scrollable.ensureVisible('));
      expect(k, contains('alignment: 0,'));
      // Hareket azaltmada süre sıfır: `kapili` kapısından geçer.
      final kaydir = _blok(k, 'void _cevabinBasinaKaydir(');
      expect(kaydir, contains('kapili(context'));
    });

    test('bakiye çipi TEK: TokenChip var, sohbetin kendi çipi yok', () {
      expect(k, contains('TokenChip('));
      expect(k, isNot(contains('_kDusukBakiye')));
      expect(k, isNot(contains('tokenBalanceChip(')),
          reason: 'çip metni yalnız token_chip.dart\'ta kurulur');
    });

    test('boş durumda marka literali yok, çıplak büyütme yok', () {
      expect(k, isNot(contains("'Rytho AI'")));
      expect(k, isNot(contains('.toUpperCase()')),
          reason: 'baş harf trBuyuk ile büyütülür (ilknur → İ)');
    });

    test('çıplak süre yok: her süre RythoMotion tokenından', () {
      expect(k, isNot(contains('Duration(milliseconds:')));
      expect(k, isNot(contains('Duration(seconds:')));
      expect(RegExp(r'\d+\.ms\b').hasMatch(k), isFalse);
      expect(k, contains('reduceMotion('));
    });
  });

  group('SohbetBalonu', () {
    testWidgets('Rytho balonu markdown\'ı çözer — ham ** görünmez',
        (tester) async {
      await tester.pumpWidget(_sar(const SohbetBalonu(
          text: 'Bugün **Ay** Boğa\'da.\n\n- sakin kal', mine: false)));
      expect(find.byType(MarkdownText), findsOneWidget);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.data ?? t.textSpan?.toPlainText() ?? '',
            isNot(contains('**')),
            reason: 'ham markdown işareti ekrana çıktı');
      }
    });

    testWidgets('kullanıcı balonu düz metin — yazdığı yıldız yıldızdır',
        (tester) async {
      await tester
          .pumpWidget(_sar(const SohbetBalonu(text: '2 * 3', mine: true)));
      expect(find.byType(MarkdownText), findsNothing);
      expect(find.text('2 * 3'), findsOneWidget);
    });

    testWidgets('uzun basış paylaşımı tetikler (yalnız Rytho balonu)',
        (tester) async {
      var sayac = 0;
      await tester.pumpWidget(_sar(SohbetBalonu(
          text: 'cevap', mine: false, onLongPress: () => sayac++)));
      await tester.longPress(find.text('cevap'));
      expect(sayac, 1);
    });

    testWidgets('paylaşım eylemi ekran okuyucuya duyurulur', (tester) async {
      final semantik = tester.ensureSemantics();
      await tester.pumpWidget(_sar(SohbetBalonu(
          text: 'cevap', mine: false, onLongPress: () {})));
      final dugum = tester.getSemantics(find.text('cevap'));
      expect(dugum.getSemanticsData().hasAction(SemanticsAction.longPress),
          isTrue,
          reason: 'görünmez jest tek başına keşfedilemez');
      semantik.dispose();
    });
  });
}

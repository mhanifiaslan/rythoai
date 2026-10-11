// Harita İnceleme D6 kaynak bekçileri.
//
// Ekran Firebase/profil sağlayıcılarına bağlı, widget testi sahte bir
// `User` isterdi (anlam_once_test emsali); bu yüzden onarımlar kaynaktan
// çivilenir. Her madde ölçülmüş bir kusurun geri dönmemesi içindir:
// hata ≠ boş, "Dış halka yükleniyor" yanlış beyanı, "Şu an Şu an gökyüzü"
// tohumu, 700×740 özel paylaşım karesi + 'RYTHO' literali, çıplak
// GestureDetector, OutlinedButton kopyası, minör lider → kaybolan panel.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';

const _yol = 'lib/features/atlas/chart_inspector_screen.dart';

/// Kaynak bekçisi bir şeyin YOKLUĞUNU ararken kendi açıklama yorumuna
/// takılmasın: tam satır yorumları ve `///` belgeleri atılır.
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// `_ChartInspectorScreenState` gövdesi (iki sınıf bildirimi arası).
String _govde() {
  final k = _yorumsuz(_yol);
  final bas = k.indexOf('class _ChartInspectorScreenState');
  final son = k.indexOf('class _AnlamKatmani');
  expect(bas, greaterThanOrEqualTo(0));
  expect(son, greaterThan(bas));
  return k.substring(bas, son);
}

void main() {
  group('hata ≠ boş', () {
    test('veri yokken ErrorCard(onRetry), SizedBox.shrink DEĞİL', () {
      final g = _govde();
      expect(g, contains('ErrorCard('));
      expect(g, contains('onRetry: _tekrarDene'));
      expect(g, isNot(contains('? const SizedBox.shrink()')),
          reason: 'hata boş gövdeye düşüyor — kullanıcı neden boş olduğunu görmez');
      // Sağlayıcının hatası TAŞINIYOR: eski üçlü yalnız value==null'a
      // bakıyordu.
      expect(g, contains('natal.error'));
      expect(g, contains('sky.error'));
      expect(g, contains('synastry.error'));
      expect(g, contains('friendlyError('));
    });

    test('ErrorCard ListView\'ın DIŞINDA — anlam-önce çapası korunur', () {
      // anlam_once_test 728-751: ilk `ListView(` → `children: [` →
      // `_AnlamKatmani(`. ErrorCard bu dizilimin içine girmemeli.
      final g = _govde();
      final hata = g.indexOf('ErrorCard(');
      final liste = g.indexOf('ListView(');
      expect(hata, lessThan(liste), reason: 'ErrorCard gövde listesine sızmış');
    });
  });

  group('bekleme metni kipe göre', () {
    test('natal/gökyüzü "Çark hazırlanıyor", dış halka yalnız çift halkalı', () {
      final g = _govde();
      expect(g, contains('l10n.chartLoading'));
      final bekleme = g.substring(g.indexOf('String _beklemeMetni('));
      final disHalka = bekleme.indexOf('l10n.chartOuterLoading');
      expect(disHalka, greaterThanOrEqualTo(0));
      // Dış halka dalı biwheel/synastry eşleşmesinin ARDINDAN gelir.
      final kip = bekleme.indexOf('ChartInspectorMode.synastry');
      expect(kip, greaterThanOrEqualTo(0));
      expect(kip, lessThan(disHalka),
          reason: '"Dış halka yükleniyor" kip kapısından geçmiyor');
    });
  });

  group('sohbet tohumu kip başına', () {
    test('tek anahtarla başlık birleştirme GİTTİ ("Şu an Şu an gökyüzü")', () {
      final g = _govde();
      expect(g, isNot(contains('chartAskPrefill(_baslik')));
      expect(g, contains('chartAskPrefillSky'));
      expect(g, contains('chartAskPrefillBiwheel'));
      expect(g, contains('chartAskPrefillSynastry('));
      expect(g, contains('chartAskPrefillNatal('));
    });

    test('ARB: gökyüzü tohumu kendi cümlesi, başlık tekrarı yok', () {
      final tr = AppLocalizationsTr();
      expect(tr.chartAskPrefillSky, isNot(contains(tr.atlasWheelSky)));
      expect(tr.chartAskPrefillSky, isNot(startsWith('Şu an Şu an')));
    });

    test('tohum ÖN-DOLDURUR: ChatScreen initialText ile açılır', () {
      final g = _govde();
      expect(g, contains('initialText: _tohum(l10n)'));
    });
  });

  group('paylaşım tek kart', () {
    test('shareChartCard; 700×740 özel kare ve RYTHO literali YOK', () {
      final k = _yorumsuz(_yol);
      expect(k, contains('shareChartCard('));
      expect(k, isNot(contains('shareRenderedCard')),
          reason: 'özel kare boru hattı geri gelmiş');
      expect(k, isNot(contains("'RYTHO'")));
      expect(k, isNot(contains('700.0')));
      expect(k, isNot(contains('_paylas(')));
    });
  });

  group('lider açı majörlerden', () {
    test('_AnlamKatmani liderGorunurAci\'yi showMinors: false ile çağırır', () {
      // Minörler açıkken en dar açı quincunx çıkınca anlam cümlesi yok
      // (uydurulmaz) ve panel KAYBOLUYORDU. Kural çağıranda; fonksiyon
      // imzası ve anlam_once_test'in `showMinors: true → quincunx`
      // bekçisi korunur.
      final k = _yorumsuz(_yol);
      final sinif = k.substring(
          k.indexOf('class _AnlamKatmani'), k.indexOf('class _Baslik'));
      expect(sinif, contains('liderGorunurAci(data, filter, maxOrb, showMinors: false)'));
      expect(sinif, isNot(contains('showMinors: showMinors')),
          reason: 'minör lider panel kaybı geri gelmiş');
    });
  });

  group('tekleştirme ve erişilebilirlik', () {
    test('"Rytho\'ya sor" tek bileşenden; OutlinedButton kopyası yok', () {
      final g = _govde();
      expect(g, contains('RythoyaSor('));
      expect(g, isNot(contains('OutlinedButton')));
      expect(g, isNot(contains("'✦")),
          reason: 'etiketin kendi kopyası doğmuş');
    });

    test('RythoyaSor gövde listesinin SON çocuğu (davet okumayı gölgelemez)',
        () {
      final g = _govde();
      final sor = g.indexOf('RythoyaSor(');
      for (final once in const [
        '_AnlamKatmani(',
        '_Aspectarian(',
        'ChartPositionsTable(',
      ]) {
        expect(g.indexOf(once), lessThan(sor), reason: '$once sor\'dan sonra');
      }
    });

    test('çarkı saran çıplak GestureDetector YOK; seçim görünür düğmeyle '
        'kaldırılır', () {
      final k = _yorumsuz(_yol);
      expect(k, isNot(contains('GestureDetector(')),
          reason: 'semantik rolü olmayan görünmez eylem geri gelmiş');
      expect(k, contains('l10n.chartSelectionClear'));
      expect(k, contains('onClear'));
    });

    test('çark boyu LayoutBuilder kısıtından; MediaQuery genişliği + clamp yok',
        () {
      final g = _govde();
      expect(g, contains('LayoutBuilder('));
      expect(g, contains('kisit.maxWidth'));
      expect(g, isNot(contains('MediaQuery.of(context).size.width')),
          reason: 'dolgu varsayımlı genişlik — 320 dp altında kırpma');
      expect(g, isNot(contains('.clamp(280.0')));
    });

    test('lejant halka rengi tek kuraldan, showMinors taşır', () {
      final k = _yorumsuz(_yol);
      final lejant = k.substring(
          k.indexOf('class _Lejant'), k.indexOf('class _SecimCubugu'));
      expect(lejant, contains('ringGlyphColor(data, 0)'));
      expect(lejant, contains('ringGlyphColor(data, 1)'));
      expect(lejant, contains('showMinors'));
      expect(lejant, contains('hareketVar:'));
    });

    test('açı tablosu sütun başlığı halka türüne bakar', () {
      final k = _yorumsuz(_yol);
      final tablo = k.substring(
          k.indexOf('class _Aspectarian'), k.indexOf('class _AspectCell'));
      expect(tablo, contains('ringGlyphColor(data, cross ? 1 : 0)'));
      expect(tablo, isNot(contains('kOuterPartnerColor')),
          reason: 'bi-wheel transit sütunu altın başlıklanıyordu');
    });
  });
}

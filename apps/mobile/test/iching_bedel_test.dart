// İ Ching çekim bedeli SUNUCUDAN okunur — elle yazılmış yedekten DEĞİL.
//
// Kapatılan kusur: rozet `l10n.iChingQuotaTokens(durum['token_cost'] as
// int? ?? 2)` yazıyordu. O `?? 2`, bedel gerçeğinin istemcideki İKİNCİ
// kopyasıydı ve hiçbir bekçi onu sunucudaki `TOKEN_COSTS['iching']`e
// bağlamıyordu — `bedel_notu_test.dart`taki B1 ile aynı sınıf kusur.
//
// Kırılma yolu: sunucu bedeli 3 yapar ve alanı göndermeyi bırakır (eski
// derleme, 503 sonrası eksik gövde, alan adı değişikliği). Rozet "2 kredi"
// der, çekim 3 düşer. Üstelik bu ekran bedeli HARCAMADAN ÖNCE gösteren TEK
// yüzey, yani sayının yanlış olmasının en pahalı yeri.
//
// Onarım yönü "yedeği doğru sayıya güncellemek" DEĞİL: ölçülmeyen
// söylenmez, alan yoksa rozet hiç çizilmez.

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/oracle/iching_tab.dart';

void main() {
  group('ichingBedeli', () {
    test('sunucu ne derse O okunur — 2 ayrıcalıklı değil', () {
      // Kusurun kalbi: eski yedek tam da 2'ydi, yani "2" döndüğünde doğru
      // ile yanlış ayırt edilemiyordu. Başka bir sayı sorulması ŞART.
      expect(ichingBedeli({'token_cost': 3}), 3);
      expect(ichingBedeli({'token_cost': 7}), 7);
      expect(ichingBedeli({'token_cost': 2}), 2);
    });

    test('alan YOKSA null — uydurma sayı basılmaz', () {
      expect(ichingBedeli({}), isNull);
      expect(ichingBedeli({'quota': 1}), isNull);
    });

    test('gövde hiç yoksa null', () {
      expect(ichingBedeli(null), isNull);
    });

    test('alan null gönderilirse null', () {
      expect(ichingBedeli({'token_cost': null}), isNull);
    });

    test('sayı OLMAYAN tür FIRLATMAZ, susar', () {
      // `as int?` kullanılsaydı bu iki gövde ekranı çökertirdi: JSON'da
      // sayılar `double` olarak da gelebiliyor ve `2.0 as int?` fırlatır.
      expect(ichingBedeli({'token_cost': '2'}), isNull);
      expect(ichingBedeli({'token_cost': 2.0}), isNull);
    });

    test('sıfır ve negatif de null — "bedava" sözü verilmez', () {
      // "0 kredi" bedava demektir; bozuk bir gövdeden bedava sözü üretmek
      // bayat bir sayıdan da kötü, çünkü kullanıcı ona göre davranır.
      expect(ichingBedeli({'token_cost': 0}), isNull);
      expect(ichingBedeli({'token_cost': -1}), isNull);
    });
  });

  // 'rozet dikişi' grubu D6'da KALDIRILDI: ekran bedeli artık tek kaynaktan
  // (`BedelRozeti(PlusOzellik.iching)`, cüzdanın `costs` alanı) okuyor;
  // `ichingBedeli(durum)` ve `/reports/iching/status` `token_cost` ikinci
  // kaynak olmaktan çıktı. Ters çapa test/kehanet_iching_test.dart'ta
  // ("bedel tek kaynaktan"). Saf işlev ve bu dosyanın üst grubu D8 ölü-kod
  // kararına kadar duruyor (backend alanının kaderiyle birlikte).
}

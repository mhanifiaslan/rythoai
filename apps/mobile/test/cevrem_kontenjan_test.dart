// Kontenjan bekçileri (D6): "4/1" basılmaz, aşım beyan edilir ve kişi
// formu kontenjan doluyken AÇILMAZ.
//
// Ölçülen kusur: abonelik düşünce sunucu `used: 4, limit: 1` döndürüyor
// ve sayaç "4/1 kişi" basıyordu — ölçülen sayı yanlış adla sunuluyordu.
// İkinci kusur (B10 sonrası): kontenjan dolu kullanıcı formu doldurup
// Kaydet'e basınca 402 alıyor, Plus aboneye satış ekranı açılıyordu ve
// kişi çıkarmaya giden yol yoktu. İki karar da saf fonksiyonda; ekran
// yalnız çizer.
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/friends/friends_screen.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';

final _tr = AppLocalizationsTr();

void main() {
  group('kontenjanBeyani', () {
    test('tavan içindeyken sayaç olduğu gibi, beyan YOK', () {
      final b = kontenjanBeyani(_tr, used: 3, limit: 10);
      expect(b.sayac, _tr.peopleSlots(3, 10));
      expect(b.asim, isNull);
    });

    test('tavan doluyken sayaç tavan/tavan, beyan YOK', () {
      final b = kontenjanBeyani(_tr, used: 10, limit: 10);
      expect(b.sayac, _tr.peopleSlots(10, 10));
      expect(b.asim, isNull, reason: 'dolu ≠ aşım; cümle uydurulmaz');
    });

    test('aşımda sayaç TAVANA kelepçeli, fazlası ayrı cümle', () {
      final b = kontenjanBeyani(_tr, used: 4, limit: 1);
      expect(b.sayac, _tr.peopleSlots(1, 1),
          reason: '"4/1" bir oran değil; sayaç kullanılan/tavan demek');
      expect(b.asim, _tr.peopleSlotsOver(1, 4));
      // Beyan hem tavanı hem gerçek sayıyı söyler — sayı gizlenmez.
      expect(b.asim, contains('1'));
      expect(b.asim, contains('4'));
    });
  });

  group('kisiKontenjaniDolu — formdan ÖNCE kapı', () {
    test('yük yoksa ya da tavan bilinmiyorsa (0) kapı KAPANMAZ', () {
      // Sunucu yükü gelmediyse karar sunucunundur; istemci uydurmaz.
      expect(kisiKontenjaniDolu(null), isFalse);
      expect(kisiKontenjaniDolu((used: 5, limit: 0)), isFalse);
    });

    test('yer varken açık', () {
      expect(kisiKontenjaniDolu((used: 0, limit: 1)), isFalse);
      expect(kisiKontenjaniDolu((used: 9, limit: 10)), isFalse);
    });

    test('dolu ve aşımda kapalı', () {
      expect(kisiKontenjaniDolu((used: 1, limit: 1)), isTrue);
      expect(kisiKontenjaniDolu((used: 4, limit: 1)), isTrue);
    });
  });
}

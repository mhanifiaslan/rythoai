// `okumaDurumuFromYanit` — fallback bayrağını okuyan TEK fonksiyonun bekçisi.
//
// Dört dal, iade bayrağı sunucudan: istemcide varsayım yok (jetonsuz uçta
// "iade edildi" yalan olurdu).
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/okuma_durumu.dart';

void main() {
  test('null yük → kilitli', () {
    expect(okumaDurumuFromYanit(null), isA<OkumaKilitli>());
  });

  test('fallback:true → üretilemedi; iade YALNIZ refunded:true ise', () {
    final a = okumaDurumuFromYanit({'report': 'şablon', 'fallback': true, 'refunded': true});
    expect(a, isA<OkumaUretilemedi>());
    expect((a as OkumaUretilemedi).iadeli, isTrue);

    final b = okumaDurumuFromYanit({'report': 'şablon', 'fallback': true});
    expect((b as OkumaUretilemedi).iadeli, isFalse,
        reason: 'refunded gelmedi → iade VARSAYILMAZ');

    final c = okumaDurumuFromYanit({'report': 'şablon', 'fallback': true, 'refunded': false});
    expect((c as OkumaUretilemedi).iadeli, isFalse);
  });

  test('boş ya da eksik metin → üretilemedi, iadesiz', () {
    expect(okumaDurumuFromYanit({'report': ''}), isA<OkumaUretilemedi>());
    expect(okumaDurumuFromYanit({'report': '   '}), isA<OkumaUretilemedi>());
    expect(okumaDurumuFromYanit({'cast': {}}), isA<OkumaUretilemedi>());
    expect((okumaDurumuFromYanit({'report': ''}) as OkumaUretilemedi).iadeli, isFalse);
  });

  test('gerçek metin → hazır; alan adı seçilebilir', () {
    final a = okumaDurumuFromYanit({'report': 'Bugün…'});
    expect(a, isA<OkumaHazir>());
    expect((a as OkumaHazir).metin, 'Bugün…');

    final b = okumaDurumuFromYanit({'reading': 'İkiniz…'}, alan: 'reading');
    expect((b as OkumaHazir).metin, 'İkiniz…');
    // Yanlış alan → metin yok → üretilemedi (sessizce hazır sayılmaz).
    expect(okumaDurumuFromYanit({'reading': 'x'}), isA<OkumaUretilemedi>());
  });

  test('fallback metin dolu olsa bile ŞABLON hazır sayılmaz', () {
    // Asıl kusur buydu: şablon paragraf "report" alanında geliyor ve
    // bayrağı okumayan ekran onu rapor gibi basıyordu.
    expect(okumaDurumuFromYanit({'report': 'Bugün gökyüzü sakin.', 'fallback': true}),
        isA<OkumaUretilemedi>());
  });
}

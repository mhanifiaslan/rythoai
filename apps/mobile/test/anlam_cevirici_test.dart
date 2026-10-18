// Ölçüm → gündelik dil çevirisinin saf bekçileri (2026-10-18).
//
// Sahip cihazda: "Ay ☍ Plüton 0°" bilmeyene bir şey söylemiyor. Çeviri
// ölçülmüş veri × sabit metin; burada eşikler ve cümle kuralı çivileniyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/tr_metin.dart';
import 'package:rytho/features/atlas/anlam_cevirici.dart';
import 'package:rytho/l10n/app_localizations_en.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';

final _tr = AppLocalizationsTr();
final _en = AppLocalizationsEn();

void main() {
  group('açı gücü orbdan', () {
    test('eşikler: <1 çok güçlü, <3 güçlü, gerisi hafif', () {
      expect(aciGucu(0.0), AciGucu.cokGuclu);
      expect(aciGucu(0.99), AciGucu.cokGuclu);
      expect(aciGucu(1.0), AciGucu.guclu);
      expect(aciGucu(2.99), AciGucu.guclu);
      expect(aciGucu(3.0), AciGucu.hafif);
      expect(aciGucu(-0.5), AciGucu.cokGuclu, reason: 'işaret yön, güç değil');
    });
    test('orb yoksa güç UYDURULMAZ', () {
      expect(aciGucu(null), isNull);
    });
  });

  group('açı cümlesi', () {
    Map<String, dynamic> aci(String p1, String p2, String tur) =>
        {'p1': p1, 'p2': p2, 'aspect': tur};

    test('iki gezegenin rolü × açı türü, Türkçe baş harf', () {
      final c = aciCumlesi(_tr, aci('Moon', 'Pluto', 'opposition'),
          turkce: true)!;
      expect(c, startsWith('Duyguların'));
      expect(c, contains(_tr.aspectSubjectPluto));
    });

    test('Türkçe baş harf i → İ, İngilizce i → I', () {
      expect(basHarfBuyuk('ilişki', turkce: true), 'İlişki');
      expect(basHarfBuyuk('inner', turkce: false), 'Inner');
    });

    test('İngilizce cümle de kurulur', () {
      expect(aciCumlesi(_en, aci('Sun', 'Saturn', 'square'), turkce: false),
          startsWith('Your sense of self'));
    });

    test('minör açıya ve tanınmayan noktaya cümle UYDURULMAZ', () {
      expect(aciCumlesi(_tr, aci('Sun', 'Moon', 'quincunx'), turkce: true),
          isNull);
      expect(aciCumlesi(_tr, aci('Sun', 'Vertex', 'trine'), turkce: true),
          isNull);
    });
  });

  group('yolculuk haritaları (Yıl Haritası, İç Mevsim)', () {
    test('yıl ilerlemesi: oran ve kaçıncı ay', () {
      final bas = DateTime.utc(2026, 5, 12);
      final son = DateTime.utc(2027, 5, 12);
      expect(yilIlerlemesi(bas, son, bas).ay, 1);
      final orta = yilIlerlemesi(bas, son, DateTime.utc(2026, 11, 12));
      expect(orta.ay, 7);
      expect(orta.oran, closeTo(0.5, 0.01));
      expect(yilIlerlemesi(bas, son, DateTime.utc(2028)).ay, 12,
          reason: 'yıl bittiyse 12. ayda kalır, 13 olmaz');
    });

    test('yılın evrenleri: en kalabalık üç ev, evsiz nokta SAYILMAZ', () {
      Map<String, dynamic> p(String ad, int? ev) =>
          {'name': ad, 'house_no': ?ev};
      final e = yilEvrenleri([
        p('Sun', 7), p('Venus', 7), p('Mars', 10), p('Moon', 4),
        p('Saturn', 10), p('Jupiter', 7), p('Pluto', 2), p('Chiron', null),
      ]);
      expect([for (final x in e) x.ev], [7, 10, 2],
          reason: 'sayı çoktan aza, eşitlikte küçük ev önce');
      expect(e.first.noktalar.length, 3);
      expect(yilEvrenleri([p('Sun', null)]), isEmpty,
          reason: 'saatsiz doğumda ev UYDURULMAZ');
    });

    test('sonraki iç iklim zodyak komşusu; Balık → Koç', () {
      expect(sonrakiBurc('Sag'), 'Cap');
      expect(sonrakiBurc('Pis'), 'Ari');
      expect(sonrakiBurc('xx'), isNull);
    });

    test('iç yolculuk: şu an → sonraki iklim → GELECEK dönüm noktaları', () {
      final d = icYolculukDuraklari(
        _tr,
        {
          'sign': 'Sag', 'sign_local': 'Yay', 'phase': 'first_quarter',
          'next_sign_at': '2027-03-04',
        },
        [
          {'directed': 'Sun', 'natal': 'Saturn', 'aspect': 'square',
           'exact_on': '2027-08-01'},
          {'directed': 'Moon', 'natal': 'Venus', 'aspect': 'trine',
           'exact_on': '2025-01-01'},
        ],
        DateTime(2026, 10, 18),
        turkce: true,
      );
      expect(d.length, 3, reason: 'geçmiş dönüm noktası şeride girmez');
      expect(d.first.simdi, isTrue);
      expect(d.first.govde, contains(_tr.progPhaseMeaningFirstQuarter));
      expect(d[1].baslik, contains(_tr.signCapricorn));
      expect(d[2].baslik, startsWith('Kimliğin'));
    });
  });

  group('denge düzeyi (Kişilik — "2/8" yerine söz)', () {
    test('0 yok, 1 az, 2-3 dengeli, 4+ güçlü', () {
      expect(dengeDuzeyi(0), DengeDuzeyi.yok);
      expect(dengeDuzeyi(1), DengeDuzeyi.az);
      expect(dengeDuzeyi(2), DengeDuzeyi.dengeli);
      expect(dengeDuzeyi(3), DengeDuzeyi.dengeli);
      expect(dengeDuzeyi(4), DengeDuzeyi.guclu);
    });

    test('baskın nitelik: kesin üstünlük ister, eşitlikte SÖYLENMEZ', () {
      expect(baskinNitelik({'cardinal': 2, 'fixed': 4, 'mutable': 2}),
          'fixed');
      expect(baskinNitelik({'cardinal': 3, 'fixed': 3, 'mutable': 2}),
          isNull);
      expect(baskinNitelik(const {}), isNull);
    });
  });
}

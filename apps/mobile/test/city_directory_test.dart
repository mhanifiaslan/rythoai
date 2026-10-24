import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:rytho/core/city_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('foldTurkish', () {
    test('noktali/noktasiz I ve aksanlar katlanir', () {
      expect(foldTurkish('İstanbul'), 'istanbul');
      expect(foldTurkish('ISPARTA'), 'isparta');
      expect(foldTurkish('Şanlıurfa'), 'sanliurfa');
      expect(foldTurkish('Kahramanmaraş'), 'kahramanmaras');
      expect(foldTurkish('Zürich'), 'zurich');
      expect(foldTurkish('  Muğla '), 'mugla');
    });
  });

  group('CityDirectory', () {
    late CityDirectory dizin;

    setUpAll(() async {
      dizin = await CityDirectory.load();
    });

    test('turkce yazimla arama nufus sirali', () {
      final sonuc = dizin.search('istanbul');
      expect(sonuc, isNotEmpty);
      expect(sonuc.first.name, 'Istanbul');
      expect(sonuc.first.nation, 'TR');
    });

    test('onek eslesmesi one gecer', () {
      final sonuc = dizin.search('ankar');
      expect(sonuc.first.name.toLowerCase(), startsWith('ankar'));
    });

    test('iki eregli admin1 ile ayrisir', () {
      final sonuc = dizin.search('eregli');
      final iller = sonuc
          .where((s) => s.nation == 'TR')
          .map((s) => s.admin1)
          .toSet();
      // Konya ve Zonguldak Ereğli'leri ayrı satır — kullanıcı ilinden seçer.
      expect(iller.length, greaterThanOrEqualTo(2));
    });

    test('bulunamayan sorgu bos liste', () {
      expect(dizin.search('xqzwv123'), isEmpty);
      // Serbest metin kaçışı UI katmanında — dizin liste dayatmaz.
    });

    test('iki harften kisa sorgu aranmaz', () {
      expect(dizin.search('a'), isEmpty);
    });
  });

  // Mağaza çekimi (2026-10-24): TR arayüzde "Istanbul" (İ yok). Kaynak
  // GeoNames cities15000'in `name` sütunu: TR kayıtlarının çoğu Türkçe
  // yazımlı (İzmir, İzmit, Küçükçekmece), İstanbul uluslararası adıyla.
  group('sehirGorunenAdi', () {
    test('Türkiye kaydının uluslararası/ASCII yazımı Türkçeye döner', () {
      expect(sehirGorunenAdi('Istanbul', 'TR'), 'İstanbul');
      expect(sehirGorunenAdi('Umraniye', 'TR'), 'Ümraniye');
      expect(sehirGorunenAdi('Canakkale', 'TR'), 'Çanakkale');
    });

    test('zaten doğru adlara dokunmaz — noktasız I Türkçede de var', () {
      // Kaba bir "baştaki I → İ" kuralı bunları bozardı.
      for (final ad in ['Isparta', 'Iğdır', 'Ilgın', 'İzmir', 'Ankara']) {
        expect(sehirGorunenAdi(ad, 'TR'), ad);
      }
    });

    test('başka ülke ve serbest metin olduğu gibi kalır', () {
      expect(sehirGorunenAdi('Munich', 'DE'), 'Munich');
      // Serbest metin kullanıcının kendi yazımı — düzeltilmez.
      expect(sehirGorunenAdi('Istanbul', ''), 'Istanbul');
      expect(sehirGorunenAdi('Istanbul', null), 'Istanbul');
    });

    test('tablo yalnız YAZIM düzeltir ve her anahtar veride yaşar', () async {
      final ham = await rootBundle.loadString('assets/data/cities.json');
      final kayitlar =
          (jsonDecode(ham) as Map<String, dynamic>)['cities'] as List;
      final trAdlari = <String>{
        for (final k in kayitlar)
          if (k[1] == 'TR') ...[k[0] as String, k[2] as String],
      };
      trYazimDuzeltmeleri.forEach((geonames, turkce) {
        // Katlanmış biçim aynı: yalnız harf işaretleri değişiyor, yer
        // değişmiyor (arama ve sunucu çözümü katlanmış adla çalışır).
        expect(foldTurkish(turkce), foldTurkish(geonames), reason: geonames);
        // Veri yenilenip ad düzelirse girdi ölü kalır — bekçi söyler.
        expect(trAdlari, contains(geonames),
            reason: '$geonames artık TR kayıtlarında yok');
      });
    });
  });
}

/// Gömülü şehir dizini (O2) — arama, tamamen offline.
///
/// Veri `assets/data/cities.json`: GeoNames cities15000 kümesinden
/// `backend/scripts/build_gazetteer.py` üretir (~34k şehir; ad, ülke,
/// il, nüfus). Koordinat/saat dilimi BURADA YOK — çözüm sunucuda, aynı
/// kümeden yapılır; mobil yalnız DOĞRU YAZIMI seçtirir. İki dosya aynı
/// betik çalışmasından çıktığı için mobilden seçilen her ad sunucuda
/// çözülür (alt küme garantisi yapısal).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Arama sonucu — seçim `birthCity`/`birthNation` olarak yazılır.
class CityPick {
  const CityPick({
    required this.name,
    required this.nation,
    required this.admin1,
  });

  final String name;

  /// ISO-2 ülke kodu (`TR`).
  final String nation;

  /// İl/eyalet adı — iki "Ereğli"yi ekranda ayırt ettiren alan.
  final String admin1;
}

class _Kayit {
  const _Kayit(this.name, this.nation, this.admin1, this.pop, this.norm);

  final String name;
  final String nation;
  final String admin1;
  final int pop;

  /// Aramanın koştuğu normalize ad ("Şanlıurfa" → "sanliurfa").
  final String norm;
}

/// Türkçe katlama: aksan ve noktalı/noktasız I farkları aramayı bozmasın.
///
/// Dart'ın `toLowerCase`'i yerel bilmez ("İ".toLowerCase() == "i̇" —
/// birleşik nokta kalır); tablo elle. Sunucudaki `_normalize` ile aynı
/// sonuca varır (NFKD yerine doğrudan harf eşleme — küme Latin olduğu
/// için yeterli).
String foldTurkish(String s) {
  const tablo = {
    'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g',
    'Ç': 'c', 'ç': 'c', 'Ö': 'o', 'ö': 'o', 'Ü': 'u', 'ü': 'u',
    'Â': 'a', 'â': 'a', 'Î': 'i', 'î': 'i', 'Û': 'u', 'û': 'u',
    'é': 'e', 'è': 'e', 'ê': 'e', 'á': 'a', 'à': 'a', 'ä': 'a',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ú': 'u', 'ù': 'u', 'ñ': 'n',
  };
  final b = StringBuffer();
  // split('') yeterli: tablo BMP karakterleri; şehir adlarında surrogate
  // çifti beklenmez, olsa da arama anahtarı olarak zararsız geçer.
  for (final ch in s.trim().split('')) {
    b.write(tablo[ch] ?? ch.toLowerCase());
  }
  return b.toString();
}

/// GeoNames `name` sütununun Türkiye kayıtlarında Türkçe harfi düşmüş
/// yazımlar → Türkçe yazım.
///
/// NEDEN var: TR kayıtlarının çoğu Türkçe yazımla geliyor (İzmir, İzmit,
/// Küçükçekmece) ama birkaçı uluslararası ya da ASCII adla — en görüneni
/// "Istanbul" (mağaza çekimi 2026-10-24: kurulumun yer adımı ve doğum
/// kaydı "🇹🇷 Istanbul" basıyordu). Liste ölçüldü: 2026-08-07 anlık
/// görüntüsünün 430 TR kaydı (224 ASCII, 206 Türkçe harfli ad) ve il
/// adları tek tek okundu.
/// Yazımından emin olunamayan iki ad (Cikcilli, Cimin) bilerek YOK —
/// yanlış "düzeltme" ASCII yazımdan kötüdür.
///
/// NEDEN veri değil gösterim: kayıtlı `birthCity` GeoNames adıdır ve
/// sunucu onu çözer; mevcut profillerde "Istanbul" yazılı. Veriyi
/// değiştirmek yeni seçimleri düzeltir ama bugünkü kayıtları düzeltmezdi.
/// İl adı (admin1) aynı tablodan geçer; "Bursa Province" türü İngilizce
/// ekler yazım değil, burada değil.
const trYazimDuzeltmeleri = <String, String>{
  'Istanbul': 'İstanbul',
  'Umraniye': 'Ümraniye',
  'Batikent': 'Batıkent',
  'Sarigerme': 'Sarıgerme',
  'İnegol': 'İnegöl',
  'Canakkale': 'Çanakkale',
};

/// Şehir ya da il adının ekranda görünen yazımı.
///
/// Yalnız Türkiye kaydı düzeltilir: tablo GeoNames'in TR kayıtlarını
/// tanır. Ülkesiz ad serbest metindir — kullanıcının kendi yazımı olduğu
/// gibi kalır. Dilden bağımsız: veri TR şehirlerini iki arayüzde de
/// Türkçe yazımla taşıyor (EN arayüz de "İzmir" görüyor); İstanbul o
/// kuralın istisnası değil.
String sehirGorunenAdi(String ad, String? ulke) =>
    ulke == 'TR' ? (trYazimDuzeltmeleri[ad] ?? ad) : ad;

/// Tek seferlik yüklenen, bellekte aranan dizin.
class CityDirectory {
  CityDirectory._(this._kayitlar);

  final List<_Kayit> _kayitlar;

  static CityDirectory? _ornek;
  static Future<CityDirectory>? _yukleniyor;

  /// Dizini yükler (ilk çağrıda ~150 ms, isolate'ta ayrıştırılır).
  static Future<CityDirectory> load() {
    if (_ornek != null) return Future.value(_ornek);
    // Aynı anda iki ekran isterse tek yükleme paylaşılır.
    return _yukleniyor ??= rootBundle
        .loadString('assets/data/cities.json')
        .then((ham) => compute(_parse, ham))
        .then((kayitlar) => _ornek = CityDirectory._(kayitlar));
  }

  static List<_Kayit> _parse(String ham) {
    final veri = jsonDecode(ham) as Map<String, dynamic>;
    final satirlar = veri['cities'] as List;
    return [
      for (final s in satirlar)
        _Kayit(s[0] as String, s[1] as String, s[2] as String,
            (s[3] as num).toInt(), foldTurkish(s[0] as String)),
    ];
  }

  /// Öneki eşleşenler önce (nüfus sıralı), sonra içeren eşleşmeler.
  ///
  /// 34k kayıtta lineer tarama tuş başına <5 ms — indeks yapısı gereksiz.
  List<CityPick> search(String sorgu, {int limit = 30}) {
    final q = foldTurkish(sorgu);
    if (q.length < 2) return const [];
    final onek = <_Kayit>[];
    final iceren = <_Kayit>[];
    for (final k in _kayitlar) {
      if (k.norm.startsWith(q)) {
        onek.add(k);
      } else if (k.norm.contains(q)) {
        iceren.add(k);
      }
    }
    int nufus(_Kayit a, _Kayit b) => b.pop.compareTo(a.pop);
    onek.sort(nufus);
    iceren.sort(nufus);
    return [
      for (final k in [...onek, ...iceren].take(limit))
        CityPick(name: k.name, nation: k.nation, admin1: k.admin1),
    ];
  }
}

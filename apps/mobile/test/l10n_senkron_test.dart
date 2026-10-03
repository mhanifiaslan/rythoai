// `.arb` ↔ ÜRETİLEN `app_localizations_*.dart` senkron bekçisi.
//
// Kapatılan kusur ölçülerek bulundu: bu iki dosya arasında HİÇBİR bekçi
// yoktu. Ölçüm şuydu — bir dürüstlük dipnotunun metnini `.arb`de değiştiren
// bir mutasyon `anlam_once_test.dart`ı HİÇ kırmızı yapmıyor, çünkü testler
// `l10n.pointSheetFootnote` okuyor, yani ÜRETİLEN dart'ı. (`feedback_screen_
// test.dart` tersine yalnız `.arb`yi okuyor; o da senkron bekçisi değil.)
//
// Kırılma yolu, sessiz olduğu için pahalı: `.arb`ye yanlış bir beyan
// yazılır, `flutter gen-l10n` KOŞTURULMAZ, depoya giren `.arb` yanlış
// metni taşır, üretilen dart eski doğru metni taşır ve o commit'te HİÇBİR
// test kırmızı olmaz. Sonraki makinede biri `gen-l10n` koşturduğu an yanlış
// beyan ekrana düşer — ve o commit de yeşildir.
//
// Yük artık taşıyıcı: ürünün "ölçülmeyen söylenmez" ilkesinin ekrandaki tek
// karşılığı bu dipnotlar ve onların bekçisi üretilen dosyaya bakıyor.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `.arb` değerini, üretilen dosyada ARANACAK Dart dize literaline çevirir.
///
/// Kaçışlar ÖLÇÜLDÜ, varsayılmadı (üretici bugün `gen-l10n`):
///   `\` → `\\` · `'` → `\'` · satır sonu → `\n` · `"` → `\"`.
/// Son kaçış şaşırtıcı: tek tırnaklı bir literalde çift tırnağın kaçışa
/// İHTİYACI YOK ama üretici yine de yazıyor. Dört anahtar (ör.
/// `purchaseEntitlementMissing`) tam bu yüzden eşleşmiyordu; kuralı
/// varsaymak bekçiyi doğduğu gün kırmızı yapardı.
///
/// Sıra ZORUNLU: ters bölü İLK değiştirilmezse sonradan eklenen kaçış
/// karakterlerinin kendisi ikinci kez kaçırılırdı.
///
/// `$` BİLEREK listede değil: bugün hiçbir düz değer `$` taşımıyor
/// (ölçüldü) ve üreticinin onu kaçırıp kaçırmadığı bilinmiyor. Varsayımla
/// eklemek, ilk `$` içeren çeviride bu bekçiyi YANLIŞ yere kırmızı yapardı.
/// `$` içeren bir değer eklenirse bu bekçi kırmızı döner ve kuralı ÖLÇMEYE
/// zorlar — doğru davranış bu.
String dartLiterali(String deger) {
  const tersBolu = r'\';
  final kacirilmis = deger
      .replaceAll(tersBolu, tersBolu + tersBolu)
      .replaceAll("'", "$tersBolu'")
      .replaceAll('"', '$tersBolu"')
      .replaceAll('\n', '${tersBolu}n');
  return "'$kacirilmis';";
}

/// Yer tutucusuz (düz) anahtarlar.
///
/// Yer tutuculu anahtarlar DIŞARIDA: üretici onları gövdesi `return`lu bir
/// METODA çeviriyor ve `{ad}` yerine `$ad` yazıyor, yani metin birebir
/// aranamaz. Onların bekçisi ayrı: `pointPlacementSentence` gibi anahtarlar
/// `anlam_once_test.dart`ta ÇIKTILARIYLA sınanıyor. Bu dosya düz metinleri
/// çiviliyor, ki dürüstlük beyanlarının tamamı o sınıfta.
Map<String, String> _duzAnahtarlar(String arbYolu) {
  final ham = jsonDecode(File(arbYolu).readAsStringSync()) as Map;
  return {
    for (final g in ham.entries)
      if (!(g.key as String).startsWith('@') &&
          g.value is String &&
          !(g.value as String).contains('{'))
        g.key as String: g.value as String,
  };
}

/// ÇEVRİLEBİLİR anahtarların TAMAMI — yer tutuculu olanlar DAHİL.
///
/// NEDEN [_duzAnahtarlar]dan ayrı bir okuyucu: metin karşılaştırması yer
/// tutuculu anahtarları haklı olarak dışarıda bırakıyor (üretici onları
/// metoda çeviriyor, metin birebir aranamaz) ama ANAHTAR KÜMESİ simetrisi
/// için o dışlama bir KÖRLÜKTÜ ve ölçüldü: `app_en.arb`den
/// `displayNameTooLong` satırını silmek simetri testini HİÇ kırmızı
/// yapmıyordu, çünkü değeri `{count}` taşıdığı için her iki kümeden de
/// atılıyordu. Kör alan 77 anahtardı — ve bu bekçinin doğduğu turda
/// eklenen anahtarın kendisi tam o 77'nin içindeydi.
///
/// Zararı sessiz: EN karşılığı olmayan bir anahtarda `gen-l10n` şablon
/// dilini (TR) kopyalıyor, yani İngilizce cihazda Türkçe cümle çıkıyor ve
/// kimse kırmızı görmüyor.
Set<String> _tumAnahtarlar(String arbYolu) {
  final ham = jsonDecode(File(arbYolu).readAsStringSync()) as Map;
  return {
    for (final g in ham.entries)
      if (!(g.key as String).startsWith('@') && g.value is String)
        g.key as String,
  };
}

void main() {
  const diller = {
    'tr': ('lib/l10n/app_tr.arb', 'lib/l10n/app_localizations_tr.dart'),
    'en': ('lib/l10n/app_en.arb', 'lib/l10n/app_localizations_en.dart'),
  };

  group('.arb ile üretilen dart AYNI metni taşıyor', () {
    diller.forEach((dil, yol) {
      test('$dil: her düz anahtarın metni üretilen dosyada BİREBİR var', () {
        final arb = _duzAnahtarlar(yol.$1);
        final uretilen = File(yol.$2).readAsStringSync();

        // Bekçinin kendisi de ölçülmüş olmalı: anahtar sayısı sıfıra
        // düşerse (ör. arb şeması değişir) bu test hiçbir şey sınamadan
        // yeşil kalırdı — depodaki en sinsi bekçi sınıfı.
        expect(arb.length, greaterThan(500),
            reason: 'düz anahtar sayısı beklenmedik biçimde düştü: '
                'bekçi boşa dönmüş olabilir');

        final ayrisan = <String>[];
        arb.forEach((anahtar, deger) {
          if (!uretilen.contains(dartLiterali(deger))) ayrisan.add(anahtar);
        });

        expect(ayrisan, isEmpty,
            reason: 'bu anahtarların .arb metni üretilen dosyada YOK — '
                '`flutter gen-l10n` koşturulmamış. Depoya giren .arb ile '
                'ekrana düşen metin AYRIŞTI: $ayrisan');
      });
    });

    test('TR ve EN anahtar kümeleri SİMETRİK — yer tutuculular DAHİL', () {
      // Tek yönlü eksik, çeviri düşen dilde şablon dilinin metnine geri
      // düşürür: İngilizce cihazda Türkçe cümle çıkar ve kimse görmez.
      //
      // Küme [_tumAnahtarlar]dan okunuyor, [_duzAnahtarlar]dan DEĞİL:
      // ikincisi yer tutuculu 77 anahtarı atıyor ve bu bekçi tam o yüzden
      // kördü (gerekçesi okuyucuda).
      final tr = _tumAnahtarlar(diller['tr']!.$1);
      final en = _tumAnahtarlar(diller['en']!.$1);

      // Bekçinin kendisi boşa dönmesin: kümeler daralırsa (şema değişir,
      // okuyucu bozulur) iki `difference` de boş çıkar ve test hiçbir şey
      // sınamadan yeşil kalırdı.
      // Eşik ÖLÇÜLEN sayıdan (847) gevşek tutuldu: amaç okuyucunun bozulup
      // boş küme döndürmesini yakalamak, normal bir anahtar temizliğinde
      // kırmızıya düşmek değil. Komşu bekçi de aynı mantıkla 500 diyor.
      expect(tr.length, greaterThan(700),
          reason: 'anahtar sayısı beklenmedik biçimde düştü');

      expect(tr.difference(en), isEmpty, reason: 'EN karşılığı yok');
      expect(en.difference(tr), isEmpty, reason: 'TR karşılığı yok');

      // Kör alanın GERÇEKTEN kapandığının bağımsız işareti: yer tutuculu
      // anahtarlar kümenin içinde olmak zorunda. Bu satır olmadan biri
      // okuyucuyu yeniden daraltsa yukarıdaki iddialar yine yeşil kalırdı.
      final yerTutuculu = tr.difference(_duzAnahtarlar(diller['tr']!.$1).keys.toSet());
      expect(yerTutuculu.length, greaterThan(50),
          reason: 'yer tutuculu anahtarlar simetri kümesine girmiyor — '
              'bekçi yine kör');
    });
  });

  group('dartLiterali kaçışları', () {
    test('ters bölü İLK kaçırılır', () {
      expect(dartLiterali(r'a\b'), r"'a\\b';");
    });

    test("apostrof kaçırılır", () {
      expect(dartLiterali("Şartları'nı"), r"'Şartları\'nı';");
    });

    test('çift tırnak da kaçırılır — üreticinin ölçülen davranışı', () {
      // Beklenen değer ÜÇ tırnaklı ham dize: tek tırnaklı ham dize kendi
      // içindeki `\"` ile sonlanıyor ve derleyici kırılıyordu (ölçüldü).
      expect(dartLiterali('bir "alıntı"'), r"""'bir \"alıntı\"';""");
    });

    test('satır sonu kaçış dizisine döner', () {
      expect(dartLiterali('bir\niki'), r"'bir\niki';");
    });
  });
}

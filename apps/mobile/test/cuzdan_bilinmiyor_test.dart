// Okunamayan bakiye SIFIR DEĞİL, BİLİNMİYOR (B10 onarımının yan riski).
//
// B10 onarımı cüzdanı her sohbet/rapor/firaset turundan sonra tazeliyor.
// Bu, eskiden neredeyse erişilemeyen bir dalı sıcak yola taşıdı:
// `walletProvider`ın catch'i hatayı yutup `WalletStatus.none` (total 0)
// dönüyordu. Tek bir geçici hata (20 sn zaman aşımı, 429) 198 jetonu olan
// kullanıcıya "0" göstermeye yetiyordu — yani "jetonun bitti" diyen bir
// yalan ve mağazaya giden yanlış bir yol.
//
// Kural: ölçülemeyen bakiye SAYI olarak sunulmaz.
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/wallet.dart';

void main() {
  test('unknown ile none AYNI SAYIYI taşır ama ayırt edilebilir', () {
    // Ayrım sayıda değil bayrakta: ikisi de 0 taşıyor, biri "bakiyen yok"
    // diğeri "okuyamadık" demek. Bayrak olmasaydı ekran ikisini
    // ayıramazdı.
    expect(WalletStatus.none.total, 0);
    expect(WalletStatus.unknown.total, 0);
    expect(WalletStatus.none.bilinmiyor, isFalse);
    expect(WalletStatus.unknown.bilinmiyor, isTrue);
  });

  test('sunucudan gelen bakiye bilinmiyor DEĞİLDİR', () {
    final w = WalletStatus.fromJson(const {
      'allowance': 12,
      'purchased': 186,
      'monthly_allowance': 300,
    });
    expect(w.total, 198);
    expect(w.bilinmiyor, isFalse);
  });

  test('sıfır bakiye "bilinmiyor" ile KARIŞTIRILMAZ', () {
    // Gerçekten sıfır olan bakiye ölçülmüş bir gerçektir ve 0 gösterilir;
    // bu testi kaldırmak, onarımı "her sıfırı gizle"ye çevirirdi.
    final w = WalletStatus.fromJson(const {
      'allowance': 0,
      'purchased': 0,
      'monthly_allowance': 300,
    });
    expect(w.total, 0);
    expect(w.bilinmiyor, isFalse);
  });

  group('bakiyeYazisi', () {
    test('bilinmiyor → "—", yoksa sayı', () {
      // Döküm satırları toplam "—" iken "0" yazıyordu — aynı kartta
      // "bilinmiyor" ve "sıfır" yan yana.
      expect(WalletStatus.unknown.bakiyeYazisi(0), '—');
      expect(WalletStatus.unknown.bakiyeYazisi(42), '—');
      expect(WalletStatus.none.bakiyeYazisi(0), '0');
      const w = WalletStatus(allowance: 7, purchased: 3, monthlyAllowance: 100);
      expect(w.bakiyeYazisi(w.total), '10');
    });
  });

  group('dusuk — eşik haktan türer', () {
    WalletStatus w(int toplam, {int hak = 100}) =>
        WalletStatus(allowance: toplam, purchased: 0, monthlyAllowance: hak);

    test('hakkın %10\'u ve altı düşük, üstü değil', () {
      // Sohbet çipi 30'u elle yazmış, "300'ün %10'u" diye gerekçelemişti;
      // hak 100'e inince sayı 30 kaldı. Eşik artık haktan: 100 → 10.
      expect(w(10).dusuk, isTrue);
      expect(w(0).dusuk, isTrue);
      expect(w(11).dusuk, isFalse);
      expect(w(15).dusuk, isFalse);
      expect(w(30).dusuk, isFalse, reason: 'eski elle yazılı eşik');
    });

    test('hak 300 iken eşik 30', () {
      expect(w(30, hak: 300).dusuk, isTrue);
      expect(w(31, hak: 300).dusuk, isFalse);
    });

    test('hak bilinmiyorken (0) taban 10', () {
      expect(w(10, hak: 0).dusuk, isTrue);
      expect(w(11, hak: 0).dusuk, isFalse);
    });

    test('bilinmiyor → ASLA düşük (total 0 olsa da)', () {
      expect(WalletStatus.unknown.dusuk, isFalse,
          reason: 'dolu cüzdanlı kullanıcı "bitmek üzere" rengi görmesin');
    });
  });

  group('packs', () {
    test('sunucunun packs alanı ayrıştırılır', () {
      final w = WalletStatus.fromJson(const {
        'allowance': 1,
        'purchased': 0,
        'monthly_allowance': 100,
        'packs': {'rytho_tokens_small': 100, 'rytho_tokens_large': 1000},
      });
      expect(w.packs, {'rytho_tokens_small': 100, 'rytho_tokens_large': 1000});
    });

    test('eski sunucu alanı göndermezse BOŞ — fırlatmaz', () {
      final w = WalletStatus.fromJson(const {
        'allowance': 1,
        'purchased': 0,
        'monthly_allowance': 100,
      });
      expect(w.packs, isEmpty);
      expect(WalletStatus.none.packs, isEmpty);
    });
  });
}

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
}

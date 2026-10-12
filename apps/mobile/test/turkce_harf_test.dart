// Türkçe büyük/küçük harf bekçileri (D2).
//
// Dart'ın toUpperCase/toLowerCase'i Türkçe bilmez ve bu dört yerde ekrana
// çıkmıştı (İKIZLER, YIL HARITASI, GÜNEŞ'IN YIL EVI, i̇letişim) + hesap
// silme onayını kilitlemişti ("SIL" ≠ "SİL"). Birim testler davranışı
// sabitler; kaynak bekçisi `lib/` altında çıplak çağrıyı allowlist'e bağlar.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/tr_metin.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('trBuyuk / trKucuk', () {
    test('noktalı ve noktasız i doğru büyür', () {
      expect(trBuyuk('ilişki'), 'İLİŞKİ');
      expect(trBuyuk('yıl haritası'), 'YIL HARİTASI');
      expect(trBuyuk("güneş'in yıl evi"), "GÜNEŞ'İN YIL EVİ");
      expect(trBuyuk('ikizler'), 'İKİZLER');
      // Dart'ın kendi davranışı — bu testin VAR OLMA sebebi:
      expect('ilişki'.toUpperCase(), isNot('İLİŞKİ'));
    });

    test('İ ve I doğru küçülür, birleşik nokta (U+0307) üremez', () {
      expect(trKucuk('İletişim'), 'iletişim');
      expect(trKucuk('ISPARTA'), 'ısparta');
      expect(trKucuk('İLİŞKİ'), 'ilişki');
      expect(trKucuk('İletişim').codeUnits, isNot(contains(0x0307)));
    });

    test('ASCII ve boş dize değişmez', () {
      expect(trBuyuk('abc'), 'ABC');
      expect(trKucuk(''), '');
    });
  });

  group('onayKelimesiEslesiyor', () {
    test('sil / SİL / SIL hepsi onay; sel değil', () {
      for (final g in ['sil', 'SİL', 'SIL', ' Sil ', 'sİl']) {
        expect(onayKelimesiEslesiyor(g, 'SİL'), isTrue, reason: g);
      }
      expect(onayKelimesiEslesiyor('sel', 'SİL'), isFalse);
      expect(onayKelimesiEslesiyor('', 'SİL'), isFalse);
    });

    test('İngilizce onay sözcüğü de çalışır', () {
      expect(onayKelimesiEslesiyor('delete', 'DELETE'), isTrue);
      expect(onayKelimesiEslesiyor('delet', 'DELETE'), isFalse);
    });
  });

  group('kaynak bekçisi: çıplak toUpperCase/toLowerCase yalnız allowlist', () {
    // ASCII olduğu KANITLI girdiler: ürün kimliği, ISO-2 kodu, HTTP metodu,
    // davet/ortak kodu, kullanıcı adı (ASCII'ye zorlanıyor). Kullanıcıya
    // görünen metin bu listede OLAMAZ; yeni bir dosya eklemek gerekçe ister.
    // ⚠️ D6/D8 göçleri bu tavanı düşürür: gösterim çağrıları kaldırılınca
    // listeden silinir. Listede olmayan dosyada çıplak çağrı → kırmızı.
    const allowlist = {
      'lib/core/tr_metin.dart', // tanımın kendisi
      'lib/core/deep_links.dart', // davet/ortak kodu (ASCII)
      'lib/core/partner_referrer.dart', // ortak kodu
      'lib/core/friends.dart', // kullanıcı adı (ASCII'ye zorlanmış)
      // Yalnız `_AddFriendSheet._send` kullanıcı adı: `kUsernamePattern`
      // ASCII dayatıyor, `trKucuk` "ISIK"ı geçersiz "ısık" yapardı. D6'da
      // gösterim çağrısı (1001 `addFriend.toUpperCase`) ve baş harf
      // (`trBuyuk`) temizlendi; bu satır kalan tek gerekçeli çağrı.
      'lib/features/friends/friends_screen.dart',
      'lib/core/wallet.dart', // HTTP metodu
      'lib/core/auth_service.dart', // e-posta normalizasyonu
      'lib/widgets/chart/chart_data.dart', // açı anahtarı (ASCII)
      'lib/core/people.dart', // kendi normalizeTr'si (tr_metin'e taşınacak)
      'lib/core/city_directory.dart', // kendi tablosu (tr_metin'e taşınacak)
      'lib/features/auth/login_screen.dart', // e-posta
      'lib/features/profile/account_screen.dart', // kullanıcı adı/e-posta
      'lib/features/profile/subscription_screen.dart', // ürün kimliği
      'lib/widgets/phone_number_field.dart', // ülke kodu
      // --- GÖSTERİM: D6/D8'de trBuyuk'a geçecek ya da kalkacak ---
      'lib/features/atlas/atlas_screen.dart',
      // device_conflict_screen.dart D8'de iki değerli eşlemeye geçti.
      // contacts_screen.dart ve relationship_screen.dart D6'da temizlendi
      // (bölüm başlığı rol tipografisi, baş harf trBuyuk, eksen adı
      // tırnaklı — dönüşüm yok).
      // delete_account.dart ve profile_screen.dart D5'te temizlendi
      // (onayKelimesiEslesiyor; grup başlığı rol tipografisine geçti).
      'lib/features/profile/legal_page.dart',
      // basis_sheet.dart D5'te temizlendi (OlcumSatiri etiketi birebir).
      'lib/widgets/city_search_field.dart',
    };
    test('listede olmayan dosyada çıplak çağrı yok', () {
      final ihlal = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final yol = f.path.replaceAll('\\', '/');
        if (!yol.endsWith('.dart') || yol.contains('/l10n/')) continue;
        final k = _yorumsuz(yol);
        if (RegExp(r'\.to(Upper|Lower)Case\(\)').hasMatch(k) &&
            !allowlist.contains(yol)) {
          ihlal.add(yol);
        }
      }
      expect(ihlal, isEmpty,
          reason: 'çıplak toUpperCase/toLowerCase: $ihlal — kullanıcı metniyse '
              'trBuyuk/trKucuk, ASCII kanıtlıysa allowlist (gerekçeyle)');
    });

    test('allowlist bayat değil: listedeki her dosya hâlâ çağrı içeriyor', () {
      // Göç bir dosyayı temizleyince satırı buradan silinmeli — tavan
      // yalnız aşağı iner.
      final bayat = allowlist.where((yol) =>
          !File(yol).existsSync() ||
          !RegExp(r'\.to(Upper|Lower)Case\(\)').hasMatch(_yorumsuz(yol)));
      expect(bayat, isEmpty, reason: 'allowlist bayat: $bayat');
    });
  });
}

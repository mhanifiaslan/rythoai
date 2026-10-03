// Görünen adın (`displayName`) uzunluk sınırı.
//
// Kapatılan kusur: ad HİÇBİR YERDE sınırlanmıyordu. İstemci yalnız
// `yeniAd.isEmpty` soruyor, `infra/firestore.rules` alanı izinli listede
// tutuyor ama boyutunu sınırlamıyor, sunucuda yazan bir yol yok.
//
// NEDEN önemli — ad kullanıcının kendi ekranında kalmıyor: arkadaş
// bildirimlerinin BAŞLIĞINA giriyor (`PUSH_MIDDAY_PAIR_TITLE`,
// `PUSH_INVITE_TITLE`) ve gövde bütçesi sunucuda ölçülü:
// `backend/services/notification_service.py` `MAX_PUSH_BODY = 110`.
// Sınır aşılınca metin KIRPILMIYOR, yedeğe düşülüyor — yani uzun bir ad
// ARKADAŞININ bildirimini sessizce yalınlaştırıyor ya da hiç göndermiyor.
// Zararı adı yazan kişi değil karşı taraf görüyor, o yüzden kendiliğinden
// hiç şikâyet edilmiyor.
//
// ⚠️ Sunucu/kural tarafı bu paketin dosyası DEĞİL: `firestore.rules`
// hâlâ boyut sınırı taşımıyor ve istemci kapısı atlatılabilir bir kapıdır
// (doğrudan Firestore yazımı). Burada kapatılan şey YALNIZ uygulamanın
// kendi yazım yolu; kural tarafı raporda açık bırakıldı.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/profile/account_screen.dart';

void main() {
  group('adCokUzun', () {
    test('sınırın TAM ÜSTÜNDE kabul, bir fazlası RET', () {
      // İki yönlü: yalnız "uzun ad reddedilir" sorulsaydı sınırı 1'e
      // çeken bir mutasyon da yeşil kalırdı.
      expect(adCokUzun('a' * kDisplayNameMaxChars), isFalse);
      expect(adCokUzun('a' * (kDisplayNameMaxChars + 1)), isTrue);
    });

    test('gerçek bir ad sınıra takılmaz', () {
      expect(adCokUzun('Mehmet Hanifi Aslan'), isFalse);
    });

    test('ölçülen kırılma uzunluğu (90 harf) REDDEDİLİYOR', () {
      expect(adCokUzun('a' * 90), isTrue);
    });

    test('boş ad bu kapıdan GEÇER — boşluk kapısı ayrı', () {
      // Tek kapıya iki iş yüklemek, hata mesajının yanlış olmasına yol
      // açardı: kullanıcı "çok uzun" okurken ad boş olurdu.
      expect(adCokUzun(''), isFalse);
    });

    test('emoji KOD NOKTASI sayılır, kod birimi değil', () {
      // `String.length` UTF-16 kod birimi sayar: 🔭 iki birim, bir kod
      // noktası. Sunucudaki bütçe Python `len()` ile, yani kod noktasıyla
      // ölçülüyor — iki taraf aynı şeyi saymalı. `length` kullanılsaydı
      // 20 emojilik bir ad sınırda sayılırken sunucuda 20 karakter yer
      // tutardı ve kapı YANLIŞ yere kapanırdı.
      expect(adCokUzun('🔭' * kDisplayNameMaxChars), isFalse);
      expect(adCokUzun('🔭' * (kDisplayNameMaxChars + 1)), isTrue);
    });
  });

  group('sınır GERÇEKTEN yazım yolunda', () {
    /// Yorumlar eşleşmeden ÖNCE atılıyor: bu dosyadaki gerekçe metinleri
    /// hem `adCokUzun`u hem `maxLength`i ANLATIYOR; atılmazsa bekçi kendi
    /// açıklamasına takılıp onarım sökülse bile yeşil kalırdı (depoda iki
    /// kez tam bu şekilde patladı).
    final kaynak = File('lib/features/profile/account_screen.dart')
        .readAsStringSync()
        .split('\n')
        .where((s) => !s.trimLeft().startsWith('//') && !s.trimLeft().startsWith('///'))
        .join('\n');

    test('kaydetme yolu sınırı SORUYOR', () {
      // Saf işlev doğru olup ÇAĞRILMAMASI bu bulgunun kendi kırılma yolu.
      expect(kaynak, contains('adCokUzun(yeniAd)'));
    });

    test('alan da sınırlı — kullanıcı hatayı görmeden duruyor', () {
      expect(kaynak, contains('maxLength: kDisplayNameMaxChars'));
    });

    test('hata metni l10n üzerinden ve SINIRI söylüyor', () {
      // Sayıyı metne gömmek, sınır değişince yalan söyleyen ikinci bir
      // kopya üretirdi (depodaki bedel satırı dersiyle aynı sınıf).
      expect(kaynak, contains('l10n.displayNameTooLong(kDisplayNameMaxChars)'));
    });
  });
}

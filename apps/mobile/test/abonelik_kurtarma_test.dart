// Okunamamış abonelik durumu TERMİNAL olmaktan çıktı.
//
// Kapatılan kusur ölçüldü: `abonelikDurumunuOku` geniş bir yakalamayla
// `SubscriptionStatus.bilinmiyor` DÖNDÜRÜYOR — yani Riverpod için başarılı
// bir `AsyncData`, hata DEĞİL. Riverpod hatasız bir sağlayıcıyı
// kendiliğinden yenilemez ve `subscriptionProvider` auto-dispose değil,
// yani ekranı kapatıp açmak da kurtarmaz. Tek bir zaman aşımı ya da 429
// yedi yüzeyi (Gökyüzü kişisel kart, BaZi, İ Ching, Doğum Heksagramı,
// İç Takvim, Yıl Haritası, Atlas'ın dört karosu) OTURUM BOYUNCA iskelette
// bırakıyordu. İskelet "veri geliyor" der; hiçbir istek yolda değildir.
//
// Bekçinin taşıdığı iddia İKİ YÖNLÜ:
//   (1) durum OKUNAMADIYSA ön plana dönüş yeniden sorar,
//   (2) durum OKUNABİLDİYSE sormaz. İkincisi bedel kapısı: koşulsuz
//       tazeleme her ön plana dönüşte bir `/billing/status` demekti, yani
//       sağlıklı yolu pahalılaştıran bir "onarım".

import 'dart:io';

import 'package:flutter/services.dart' show StringCodec;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/abonelik_kurtarma.dart';
import 'package:rytho/core/subscription.dart';

Future<void> _yasamDongusu(WidgetTester tester, String durum) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(durum),
    (_) {},
  );
  await tester.pump();
}

void main() {
  group('abonelikDurumuKurtarilmali', () {
    test('OKUNAMADI → kurtarılmalı', () {
      expect(
          abonelikDurumuKurtarilmali(
              const AsyncData(SubscriptionStatus.bilinmiyor)),
          isTrue);
    });

    test('okunabilen "abone DEĞİL" cevabı kurtarılmaz', () {
      // Kusurun ayırt edici noktası: gerçek bir olumsuz cevap ile
      // okunamamış cevap aynı şey değil. Burada ayrım yapılmazsa her abone
      // olmayan kullanıcı ön plana her dönüşte bir istek atardı.
      expect(abonelikDurumuKurtarilmali(const AsyncData(SubscriptionStatus.none)),
          isFalse);
    });

    test('okunabilen "abone" cevabı kurtarılmaz', () {
      expect(
          abonelikDurumuKurtarilmali(const AsyncData(
              SubscriptionStatus(active: true, okunabildi: true))),
          isFalse);
    });

    test('istek YOLDAYKEN kurtarılmaz — iptal edip baştan başlatırdı', () {
      expect(
          abonelikDurumuKurtarilmali(
              const AsyncLoading<SubscriptionStatus>()),
          isFalse);
    });

    test('HATA hâlinde kurtarılmaz — Riverpod kendi retry\'ını koşturuyor',
        () {
      expect(
          abonelikDurumuKurtarilmali(
              AsyncError<SubscriptionStatus>(Exception('x'), StackTrace.empty)),
          isFalse);
    });
  });

  group('AbonelikKurtarmaGozcusu', () {
    /// Sağlayıcı sayaçlı bir sahteyle değiştiriliyor: gerçeği koşturmak
    /// sahte bir Firebase `User`ı ve `/billing/status` ucu isterdi.
    Future<int Function()> kur(
        WidgetTester tester, SubscriptionStatus durum) async {
      var kurulum = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith((ref) async {
            kurulum++;
            return durum;
          }),
        ],
        child: AbonelikKurtarmaGozcusu(
          child: Consumer(
            builder: (_, ref, _) => Text(
                '${ref.watch(subscriptionProvider).value?.okunabildi}',
                textDirection: TextDirection.ltr),
          ),
        ),
      ));
      await tester.pump();
      return () => kurulum;
    }

    testWidgets('OKUNAMAMIŞ durum ön plana dönüşte YENİDEN sorulur',
        (tester) async {
      final sayac = await kur(tester, SubscriptionStatus.bilinmiyor);
      expect(sayac(), 1, reason: 'açılış okuması');

      await _yasamDongusu(tester, 'AppLifecycleState.paused');
      await _yasamDongusu(tester, 'AppLifecycleState.resumed');
      await tester.pump();

      expect(sayac(), 2,
          reason: 'bilinmiyor hâli artık TERMİNAL olmamalı');
    });

    testWidgets('OKUNABİLEN durum ön plana dönüşte sorulmaz', (tester) async {
      final sayac = await kur(tester, SubscriptionStatus.none);
      expect(sayac(), 1);

      for (var i = 0; i < 3; i++) {
        await _yasamDongusu(tester, 'AppLifecycleState.inactive');
        await _yasamDongusu(tester, 'AppLifecycleState.resumed');
        await tester.pump();
      }

      expect(sayac(), 1,
          reason: 'sağlıklı yolda ön plana dönüş istek üretmemeli');
    });

    testWidgets('arka plana GİDİŞ tek başına sormaz', (tester) async {
      final sayac = await kur(tester, SubscriptionStatus.bilinmiyor);
      await _yasamDongusu(tester, 'AppLifecycleState.paused');
      // `pumpAndSettle` ŞART, tek bir `pump` DEĞİL — bu bekçi doğduğu gün
      // KÖRDÜ ve körlüğü ölçülerek bulundu: `resumed` süzgecini (`if (state
      // != AppLifecycleState.resumed) return;`) gözcüden silen minimal
      // mutasyon testi HİÇ kırmızı yapmıyordu. Sebep Riverpod'un yeniden
      // kurma takvimi: geçersizleştirilen sağlayıcının gövdesi iki
      // `pump`tan sonra henüz koşmamış oluyor, yani sayaç "artmadı" değil
      // "henüz artmadı" durumunda ölçülüyordu.
      //
      // Süzgeç olmadan bedel gerçek: 'paused' bir mesaj ÜÇ geçiş üretiyor
      // (inactive · hidden · paused — ölçüldü) ve her biri bir
      // `/billing/status` demek olurdu; yani arka plana her gidiş üç istek.
      // Onarımın kendi gerekçesi ("ağ kesintisinin bitmesiyle kullanıcının
      // DÖNÜŞÜ aynı olay") tam da burada taşınıyor.
      await tester.pumpAndSettle();
      expect(sayac(), 1);
    });
  });

  group('gözcü DİKİŞİ', () {
    test('gerçek ağaçta kurulu — yoksa onarımın tamamı ölü', () {
      // Çapa Dart tanımlayıcısına bağlı, tek bir Türkçe kelimeye değil;
      // yorumlar eşleşmeden ÖNCE atılıyor (bu dosyadaki ve main.dart'taki
      // gerekçe metinleri gözcüyü ANLATIYOR).
      final kaynak = File('lib/main.dart')
          .readAsStringSync()
          .split('\n')
          .where((s) => !s.trimLeft().startsWith('//'))
          .join('\n');
      expect(kaynak, contains('AbonelikKurtarmaGozcusu('));
    });
  });
}

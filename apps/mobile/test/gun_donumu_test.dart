// GÜN DÖNÜMÜ bekçileri.
//
// Kapatılan kusur: günlük rapor sağlayıcıları (`dailyReadingProvider`,
// `baziReportProvider`, `birthHexagramProvider`) düz `FutureProvider` ve
// Riverpod'da varsayılan `isAutoDispose = false` — sonuç OTURUM BOYUNCA
// istemci önbeleğinde kalıyordu. Belirti ölçüldü: akşam aç, BaZi sekmesini
// gör, arka plana al, gece yarısını geç, sekmeye dön → sunucu bugünün Liu
// Ri'siyle yeni metin üretebilecek durumdayken DÜNKÜ metin ekranda duruyor.
// Kullanıcıya göre üç yüzey "günlük olmadı".
//
// Bekçinin taşıdığı İKİ YÖNLÜ iddia — biri olmadan öteki kusuru maskeler:
//   (1) gün DEĞİŞTİYSE günlük sağlayıcı yeniden kurulur,
//   (2) gün AYNIYSA kurulmaz. İkincisi jeton kapısı: günlük raporlar
//       jetonlu, ön plana her dönüşte yeniden kurmak bir jeton musluğu
//       olurdu (`autoDispose` tam bunu yapardı, o yüzden seçilmedi).

import 'dart:io';

import 'package:flutter/services.dart' show StringCodec;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/gun_donumu.dart';

/// Günlük bir sağlayıcının gün anahtarına bağlanma deseni — `providers.dart`
/// içindeki `_gunuIzle(ref)` ile BİREBİR aynı: tek bir `watch`.
///
/// NEDEN gerçek `baziReportProvider` değil: o sağlayıcı `authStateProvider`
/// üzerinden gerçek bir Firebase `User`ı ve `/reports/bazi` ucunu istiyor
/// (`abonelik_bilinmiyor_test.dart` ile aynı gerekçe: kapıyı saf parçadan
/// sınamak). Burada sınanan şey Riverpod'un yeniden kurma davranışı, ucun
/// gövdesi değil.
int _kurulum = 0;
final _gunlukSaglayici = FutureProvider<String>((ref) async {
  _kurulum++;
  return ref.watch(gunAnahtariProvider);
});

Future<void> _yasamDongusu(WidgetTester tester, String durum) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(durum),
    (_) {},
  );
  await tester.pump();
}

void main() {
  setUp(() => _kurulum = 0);

  group('gunAnahtari', () {
    test('yerel takvim gününü sıfır dolgulu yazar', () {
      expect(gunAnahtari(DateTime(2026, 10, 3, 23, 59)), '2026-10-03');
      expect(gunAnahtari(DateTime(2026, 1, 9, 0, 0)), '2026-01-09');
    });

    test('gece yarısı anahtarı İLERLETİR — saat değil GÜN sayılıyor', () {
      // Kusurun kalbi: 23:59 ile 00:01 aynı anahtarı üretirse gün dönümü
      // hiç fark edilmez.
      expect(gunAnahtari(DateTime(2026, 10, 3, 23, 59)),
          isNot(gunAnahtari(DateTime(2026, 10, 4, 0, 1))));
    });

    test('aynı günün farklı saatleri AYNI anahtar — önbellek gün içinde yaşar',
        () {
      expect(gunAnahtari(DateTime(2026, 10, 3, 0, 0)),
          gunAnahtari(DateTime(2026, 10, 3, 23, 59)));
    });

    test('UTC DEĞİL yerel okunuyor', () {
      // `toUtc()` çağrılsaydı UTC+3'te gece yarısı ile 03:00 arasındaki
      // anahtar bir gün GERİDE kalırdı — tam da gün dönümünün kaçırıldığı
      // pencere. Karşılaştırma yerel alanlarla yapılıyor.
      final an = DateTime(2026, 10, 4, 1, 30);
      expect(gunAnahtari(an),
          '${an.year}-${an.month.toString().padLeft(2, '0')}-'
          '${an.day.toString().padLeft(2, '0')}');
    });
  });

  group('GunDonumuGozcusu', () {
    testWidgets('ön plana dönüşte gün DEĞİŞTİYSE günlük sağlayıcı yeniden kurulur',
        (tester) async {
      var saat = DateTime(2026, 10, 3, 21, 0);
      await tester.pumpWidget(ProviderScope(
        child: GunDonumuGozcusu(
          now: () => saat,
          child: Consumer(
            builder: (_, ref, _) => Text(
                '${ref.watch(_gunlukSaglayici).value}',
                textDirection: TextDirection.ltr),
          ),
        ),
      ));
      await tester.pump();
      expect(_kurulum, 1, reason: 'açılış kurulumu');
      expect(find.text('2026-10-03'), findsOneWidget);

      // Gece yarısı geçildi ve kullanıcı ön plana döndü.
      saat = DateTime(2026, 10, 4, 0, 30);
      await _yasamDongusu(tester, 'AppLifecycleState.paused');
      await _yasamDongusu(tester, 'AppLifecycleState.resumed');
      await tester.pump();

      expect(_kurulum, 2, reason: 'gün dönümü sağlayıcıyı yeniden kurmalı');
      expect(find.text('2026-10-04'), findsOneWidget,
          reason: 'ekranda DÜNKÜ gün kalmamalı');
    });

    testWidgets('gün AYNIYSA yeniden kurulmaz — sekme dönüşü jeton harcatmaz',
        (tester) async {
      var saat = DateTime(2026, 10, 3, 9, 0);
      await tester.pumpWidget(ProviderScope(
        child: GunDonumuGozcusu(
          now: () => saat,
          child: Consumer(
            builder: (_, ref, _) => Text(
                '${ref.watch(_gunlukSaglayici).value}',
                textDirection: TextDirection.ltr),
          ),
        ),
      ));
      await tester.pump();
      expect(_kurulum, 1);

      // Aynı gün içinde üç kez ön plana dönüş (sekme değiştirme, bildirime
      // dokunma, telefonu kilitleyip açma).
      for (var i = 0; i < 3; i++) {
        saat = saat.add(const Duration(hours: 2));
        await _yasamDongusu(tester, 'AppLifecycleState.inactive');
        await _yasamDongusu(tester, 'AppLifecycleState.resumed');
        await tester.pump();
      }

      expect(_kurulum, 1,
          reason: 'aynı gün içinde yeniden üretim YOK — jeton musluğu olurdu');
    });

    testWidgets('arka plana GİDİŞ tek başına yeniden kurmaz', (tester) async {
      var saat = DateTime(2026, 10, 3, 9, 0);
      await tester.pumpWidget(ProviderScope(
        child: GunDonumuGozcusu(
          now: () => saat,
          child: Consumer(
            builder: (_, ref, _) => Text(
                '${ref.watch(_gunlukSaglayici).value}',
                textDirection: TextDirection.ltr),
          ),
        ),
      ));
      await tester.pump();

      // Gün döndü ama kullanıcı ön plana DÖNMEDİ: ekranda gösterilen bir
      // şey yok, istek de atılmamalı.
      saat = DateTime(2026, 10, 4, 0, 30);
      await _yasamDongusu(tester, 'AppLifecycleState.paused');
      // `pumpAndSettle` ŞART, tek bir `pump` DEĞİL — bu bekçi doğduğu gün
      // KÖRDÜ ve körlüğü ölçülerek bulundu: `resumed` süzgecini (`if (state
      // != AppLifecycleState.resumed) return;`) gözcüden silen minimal
      // mutasyon testi HİÇ kırmızı yapmıyordu. `_bak()` çağrılıyor, anahtar
      // GERÇEKTEN yazılıyor (ölçüm: "2026-10-04 vs 2026-10-03") ama
      // Riverpod'un yeniden kurma takvimi iki `pump`a sığmıyor — yani
      // sayaç "artmadı" değil "henüz artmadı" durumunda okunuyordu.
      await tester.pumpAndSettle();

      expect(_kurulum, 1);
    });
  });

  // ---------------------------------------------------------------------
  // KAYNAK bekçileri: yukarıdaki davranış testleri mekanizmayı kanıtlıyor
  // ama DİKİŞİ kanıtlamıyor.
  //
  // Ölçüldü (minimal mutasyon): `baziReportProvider`dan `_gunuIzle(ref)`
  // satırını silmek yukarıdaki yedi testi HİÇ kırmızı yapmıyor, çünkü
  // onlar kendi sahte sağlayıcısını kullanıyor (gerçek sağlayıcı sahte bir
  // Firebase `User`ı ve ucu ister). O yüzden dikiş kaynaktan okunuyor.
  //
  // Çapa tek bir Türkçe kelimeye DEĞİL Dart tanımlayıcılarına bağlı
  // (`_gunuIzle`, `gunAnahtariProvider`, `GunDonumuGozcusu`) ve eşleşmeden
  // ÖNCE yorumlar atılıyor: `birthHexagramProvider`ın docstring'i gün
  // anahtarını ANLATIYOR ve yorumlar atılmazsa bekçi kendi açıklamasına
  // takılıp onarım sökülse bile yeşil kalırdı.
  group('gün anahtarı DİKİŞİ', () {
    /// `//` yorumlarını atar — dize literali içindeki `//` korunur.
    String yorumsuz(String kaynak) => kaynak
        .split('\n')
        .where((s) => !s.trimLeft().startsWith('//'))
        .join('\n');

    /// `final <ad> = ...;` gövdesini kaba biçimde çıkarır: addan başlar,
    /// bir sonraki üst düzey `final ` tanımına kadar okur.
    String govde(String kaynak, String ad) {
      final bas = kaynak.indexOf('final $ad');
      expect(bas, isNot(-1), reason: '$ad sağlayıcısı bulunamadı');
      final son = kaynak.indexOf('\nfinal ', bas + 1);
      return kaynak.substring(bas, son < 0 ? kaynak.length : son);
    }

    late String saglayicilar;

    setUp(() {
      saglayicilar =
          yorumsuz(File('lib/core/providers.dart').readAsStringSync());
    });

    test('yardımcı GERÇEKTEN gün anahtarını izliyor', () {
      // `_gunuIzle` içi boşaltılırsa (ör. gövde `{}` olursa) aşağıdaki üç
      // iddia yine geçerdi: çağrı duruyor, izleme yok.
      expect(saglayicilar,
          contains('void _gunuIzle(Ref ref) => ref.watch(gunAnahtariProvider)'),
          reason: 'çağrı duruyor ama izleme yoksa önbellek gün dönümünü '
              'yine kaçırır');
    });

    // ⚠️ Liste bu turda İKİ anahtarla büyüdü ve büyüme kendi dersini
    // taşıyor: ilk hâli "üç günlük yüzey" diyordu, oysa ÜCRETSİZ katmanın
    // omurgası olan burç yorumu ile günün sinyal kartları da aynı sınıftaydı
    // (`FutureProvider` / `FutureProvider.family`, ikisi de varsayılan
    // `isAutoDispose = false`). Doğru değişmez sayı DEĞİL: sunucusu GÜN
    // KOVASIYLA servis eden her yüzey gün anahtarına bağlı olmalı.
    //
    // `signHoroscopeProvider` listede en pahalısı: tek kurtarma yolu yok —
    // Gökyüzü'ndeki aşağı çekme onu tazelemiyor ve iki `invalidate` çağrısı
    // da yalnız HATA dalında. Üstelik jetonsuz, yani "önbellek jeton
    // kurtarıyor" gerekçesi de yok.
    for (final ad in [
      'dailyReadingProvider',
      'baziReportProvider',
      'birthHexagramProvider',
      'signHoroscopeProvider',
      'signalsDataProvider',
    ]) {
      test('$ad gün anahtarına BAĞLI', () {
        expect(govde(saglayicilar, ad), contains('_gunuIzle(ref)'),
            reason: 'GÜNLÜK bir yüzey oturum boyunca önbellekte kalırsa '
                'kullanıcıya göre günlük OLMAZ');
      });
    }

    // İki yöne çalışan değişmez: GÜNLÜK OLMAYAN jetonlu rapor gün anahtarına
    // bağlanmamalı. Bağlanırsa her gün dönümünde yeniden üretilir ve bu,
    // kullanıcıya hiçbir yenilik vermeden jeton harcar — kimlik haritası
    // (natal) ve güneş dönüşü yılı (solar return) gün dönünce DEĞİŞMEZ.
    for (final ad in ['natalReportProvider', 'solarReturnProvider']) {
      test('$ad gün anahtarına bağlı DEĞİL — gereksiz jeton harcamaz', () {
        expect(govde(saglayicilar, ad), isNot(contains('_gunuIzle(ref)')));
      });
    }

    test('anahtar YEREL okunuyor — kaynak çapası, makineden bağımsız', () {
      // Yukarıdaki "UTC DEĞİL yerel okunuyor" davranış testi bu makinede
      // (UTC+3) gerçekten kırmızı oluyor — ölçüldü. Ama UTC ofseti SIFIR
      // olan bir makinede (CI konteyneri, bir sunucu, UTC'ye ayarlı bir
      // dizüstü) yerel ile UTC aynı şeydir, yani o test hiçbir şey
      // sınamadan yeşil kalır. Mac devri yolda ve o makinenin saat dilimi
      // bilinmiyor; bu çapa davranıştan BAĞIMSIZ bir ikinci işaret.
      expect(yorumsuz(File('lib/core/gun_donumu.dart').readAsStringSync()),
          isNot(contains('toUtc')),
          reason: 'gün anahtarı UTC\'ye çevrilirse UTC+3\'te gece yarısı ile '
              '03:00 arası bir gün GERİDE kalır — tam da gün dönümünün '
              'kaçırıldığı pencere');
    });

    test('gözcü GERÇEK ağaçta kurulu — anahtarı ilerleten tek şey o', () {
      // Bu iddia olmadan onarımın tamamı ölü olurdu: sağlayıcılar anahtarı
      // izler, anahtar hiç ilerlemez, hiçbir test kırmızı olmaz.
      expect(yorumsuz(File('lib/main.dart').readAsStringSync()),
          contains('GunDonumuGozcusu('));
    });
  });
}

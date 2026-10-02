// P2 bekçileri: Rytho+ kapısı ÜÇ durumlu — "bilmiyorum" kilit DEĞİL.
//
// Sahibin şikâyeti: "Ekran ilk açıldığında bazı alanlar KİLİTLİ duruyor,
// biraz bekleyince kilitler açılıyor." Ölçülen kök neden tek satırdı:
//
//     bool _hasPlus(Ref ref) =>
//         ref.watch(subscriptionProvider).value?.active ?? false;
//
// Yükleniyorken `.value` null, `?? false` onu "abone değil"e çeviriyordu.
// Ücretli sağlayıcılar o anda AsyncLoading'de KALMIYOR, `AsyncData(null)`
// ile tamamlanıyordu — yani ekranların `loading:` dalı hiç koşmuyor, `data:`
// dalı `null` görüp kilit kartını çiziyordu. Abonelik cevabı gelince kapı
// açılıyor ve kilit kayboluyordu: belirti birebir buydu.
//
// İki kat daha vardı ve ikisi de burada sabitleniyor:
//  1. Soğuk açılışta `authStateProvider` henüz null iken `subscriptionProvider`
//     `SubscriptionStatus.none` ile BAŞARIYLA tamamlanıyor ve
//     `none.okunabildi` TRUE — yani bu pencere aboneliğin `isLoading`'iyle
//     bile ayırt edilemiyor.
//  2. `profileProvider` yüklenirken de aynı çöküş: profil yayını gelmemişken
//     ücretli sağlayıcı `null` dönüyor ve kilit çiziliyordu.
//
// Karar SAF bir işleve çıkarıldı: sağlayıcıyı koşturmak sahte bir Firebase
// `User`ı gerektirirdi (abonelik_bilinmiyor_test ile aynı gerekçe).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` türü flutter_riverpod 3'te misc.dart'tan geliyor.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/core/subscription.dart';
import 'package:rytho/features/oracle/bazi_tab.dart';
import 'package:rytho/features/paywall/plus_locked_card.dart';
import 'package:rytho/features/sky/sky_screen.dart' show onCekilecekBurclar;
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/widgets/common.dart' show ErrorCard;
import 'package:rytho/widgets/glass.dart' show SkeletonPanel;
import 'package:rytho/widgets/nebula_widgets.dart' show kSignKeys;

/// Kaynak bekçilerinin BİR ŞEYİN YOKLUĞUNU ararken kendi açıklama yorumuna
/// takılmaması için: tam satır yorumları ve `///` belgeleri atılır.
///
/// Bu tuzak bu depoda gerçekten patladı (build kapısı kendi manifest
/// yorumuna, davet sayfası testi kendi HTML yorumuna takıldı).
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Widget _sar(Widget govde, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(body: govde),
      ),
    );

/// Animasyonlar (flutter_animate, shimmer döngüsü) sürekli koşuyor —
/// `pumpAndSettle` dönmez.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Sunucunun gerçekten cevapladığı "abone değil" — `none` ile aynı alanları
/// taşır ama ayrı bir nesne: kararın nesne kimliğine değil alanlara bakması
/// gerekiyor.
final _sunucuAboneDegil = SubscriptionStatus.fromJson({'active': false});
final _sunucuAbone = SubscriptionStatus.fromJson({'active': true});

/// "Yeniden kuruluyor ama ÖNCEKİ değeri taşıyor" hâlini GERÇEKTEN üretir.
///
/// Elle kurmanın yolu `AsyncValue.copyWithPrevious` ve o üye paket-içi
/// (`invalid_use_of_internal_member`). Bunun yerine hâl gerçek bir
/// `ProviderContainer`da doğuruluyor: değer tamamlanır, sağlayıcı
/// geçersizleştirilir ve bir sonraki okuma tam o ara hâli verir. Üretilen
/// hâlin beklenen şekli çağıranda ayrıca doğrulanıyor — kurulum tutmazsa
/// test sessizce geçmesin.
Future<AsyncValue<T>> _oncekiniTasiyanYukleniyor<T>(T onceki) async {
  final kaynak = FutureProvider<T>((ref) async => onceki);
  final kap = ProviderContainer();
  addTearDown(kap.dispose);
  await kap.read(kaynak.future);
  kap.invalidate(kaynak);
  return kap.read(kaynak);
}

void main() {
  // -------------------------------------------------------------------------
  group('plusHaliniOku — üç durum', () {
    test('oturum HENÜZ cevaplamadı: bilinmiyor', () {
      // Asıl tuzak burada: abonelik bu pencerede `AsyncData(none)` ve
      // `none.okunabildi` TRUE, yani iki eksik hâl de "bilinen cevap" gibi
      // görünüyor. Tek ayırt edici işaret auth akışının kendisi.
      expect(
          plusHaliniOku(
            oturum: const AsyncLoading<Object?>(),
            abonelik: const AsyncData(SubscriptionStatus.none),
            profil: const AsyncData<Object?>(<String, dynamic>{}),
          ),
          PlusHali.bilinmiyor);
    });

    test('oturum YOK: bilinen olumsuz cevap', () {
      expect(
          plusHaliniOku(
            oturum: const AsyncData<Object?>(null),
            abonelik: const AsyncData(SubscriptionStatus.none),
          ),
          PlusHali.aboneDegil);
    });

    test('abonelik yükleniyor: bilinmiyor (KT3)', () {
      expect(
          plusHaliniOku(
            oturum: const AsyncData<Object?>('uid'),
            abonelik: const AsyncLoading<SubscriptionStatus>(),
          ),
          PlusHali.bilinmiyor);
    });

    test('yükleniyor ama ÖNCEKİ değer taşınıyor: yine bilinmiyor', () async {
      // Oturum geldiği an abonelik sağlayıcısı yeniden kuruluyor ve Riverpod
      // önceki değeri — oturumsuz `none` — taşımaya devam ediyor. `hasValue`
      // tek başına sorulsa bu hâl "abone değil" okunur ve kilit geri gelirdi.
      final durum =
          await _oncekiniTasiyanYukleniyor(SubscriptionStatus.none);
      expect(durum.hasValue, isTrue, reason: 'tuzağın ön koşulu');
      expect(durum.isLoading, isTrue, reason: 'tuzağın ön koşulu');

      expect(
          plusHaliniOku(
            oturum: const AsyncData<Object?>('uid'),
            abonelik: durum,
            profil: const AsyncData<Object?>(<String, dynamic>{}),
          ),
          PlusHali.bilinmiyor);
    });

    test('durum okunamadı (5xx/zaman aşımı): bilinmiyor (ilkacilis-2)', () {
      expect(
          plusHaliniOku(
            oturum: const AsyncData<Object?>('uid'),
            abonelik: const AsyncData(SubscriptionStatus.bilinmiyor),
            profil: const AsyncData<Object?>(<String, dynamic>{}),
          ),
          PlusHali.bilinmiyor);
    });

    test('sunucu "abone değil" dedi: aboneDegil', () {
      expect(
          plusHaliniOku(
            oturum: const AsyncData<Object?>('uid'),
            abonelik: AsyncData(_sunucuAboneDegil),
            profil: const AsyncData<Object?>(<String, dynamic>{}),
          ),
          PlusHali.aboneDegil);
    });

    test('profil HENÜZ gelmedi: bilinmiyor (ikinci kat)', () {
      expect(
          plusHaliniOku(
            oturum: const AsyncData<Object?>('uid'),
            abonelik: AsyncData(_sunucuAbone),
            profil: const AsyncLoading<Object?>(),
          ),
          PlusHali.bilinmiyor);
    });

    test('profil yükleniyor ama önceki değer taşınıyor: bilinmiyor', () async {
      // Profil sağlayıcısı da oturum geldiğinde yeniden kuruluyor ve
      // oturumsuz yayını (`null`) taşımaya devam ediyor.
      final profil = await _oncekiniTasiyanYukleniyor<Object?>(null);
      expect(profil.hasValue, isTrue, reason: 'tuzağın ön koşulu');
      expect(profil.isLoading, isTrue, reason: 'tuzağın ön koşulu');
      expect(
          plusHaliniOku(
            oturum: const AsyncData<Object?>('uid'),
            abonelik: AsyncData(_sunucuAbone),
            profil: profil,
          ),
          PlusHali.bilinmiyor);
    });

    test('abone + profil geldi: abone', () {
      // Ters yön: düzeltme kapıyı tamamen kapatmış olmasın.
      expect(
          plusHaliniOku(
            oturum: const AsyncData<Object?>('uid'),
            abonelik: AsyncData(_sunucuAbone),
            profil: const AsyncData<Object?>({'onboardingCompleted': true}),
          ),
          PlusHali.abone);
    });

    test('profil SORULMAYAN kapı aboneyi bekletmez', () {
      // İ Ching çekimi ve Atlas karoları doğum verisi göndermiyor; profili
      // beklemek onları boşuna iskelette tutardı.
      expect(
          plusHaliniOku(
            oturum: const AsyncData<Object?>('uid'),
            abonelik: AsyncData(_sunucuAbone),
          ),
          PlusHali.abone);
    });

    test('"yükleniyorsa abone VARSAY" yapılmıyor', () {
      // Ters yöndeki yalan: abone olmayana bir an kilitsiz içerik göstermek.
      // Üç eksik hâlin hiçbiri `abone` DÖNDÜRMEZ.
      for (final eksik in <PlusHali>[
        plusHaliniOku(
            oturum: const AsyncLoading<Object?>(),
            abonelik: const AsyncData(SubscriptionStatus.none)),
        plusHaliniOku(
            oturum: const AsyncData<Object?>('uid'),
            abonelik: const AsyncLoading<SubscriptionStatus>()),
        plusHaliniOku(
            oturum: const AsyncData<Object?>('uid'),
            abonelik: const AsyncData(SubscriptionStatus.bilinmiyor)),
      ]) {
        expect(eksik, PlusHali.bilinmiyor);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('BaZi sekmesi: üç hâl AYRI çiziliyor', () {
    // Kapı bir `Provider` olduğu için üç hâl de doğrudan kurulabiliyor;
    // sahte Firebase oturumu gerekmiyor.

    testWidgets('BİLİNMİYOR: kilit kartı YOK, iskelet VAR', (tester) async {
      await tester.pumpWidget(_sar(const BaziTab(), overrides: [
        raporKapisiProvider.overrideWithValue(PlusHali.bilinmiyor),
      ]));
      await _bekle(tester);

      expect(find.byType(PlusLockedCard), findsNothing,
          reason: 'ödemiş kullanıcıya "abone değilsin" demek — şikâyetin ta '
              'kendisi');
      expect(find.byType(SkeletonPanel), findsWidgets,
          reason: 'üçüncü hâl AYRI çizilmeli: ne kilit ne içerik');
    });

    testWidgets('ABONE DEĞİL: kilit kartı çiziliyor', (tester) async {
      // Ters yön: düzeltme kilidi tamamen öldürmüş olmasın.
      await tester.pumpWidget(_sar(const BaziTab(), overrides: [
        raporKapisiProvider.overrideWithValue(PlusHali.aboneDegil),
        // Kapı kapalıyken sağlayıcı istek ATMADAN `null` döner.
        baziReportProvider.overrideWith((ref) async => null),
      ]));
      await _bekle(tester);

      expect(find.byType(PlusLockedCard), findsOneWidget);
      expect(find.byType(SkeletonPanel), findsNothing);
    });

    testWidgets('ABONE: karar sağlayıcıya geçiyor', (tester) async {
      // Kapı açıkken ekran ne kilit ne iskelet çizer; ne gösterileceğini
      // ücretli sağlayıcının cevabı söyler. "Abone + veri → içerik" legi
      // rapor_uretilemedi_test.dart'ta gerçek BaZi haritasıyla çiziliyor;
      // burada hata dalı seçildi, çünkü iddia "kapı artık karışmıyor".
      await tester.pumpWidget(_sar(const BaziTab(), overrides: [
        raporKapisiProvider.overrideWithValue(PlusHali.abone),
        baziReportProvider.overrideWith((ref) async => throw StateError('x')),
      ]));
      await _bekle(tester);

      expect(find.byType(ErrorCard), findsOneWidget);
      expect(find.byType(PlusLockedCard), findsNothing);
      expect(find.byType(SkeletonPanel), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('Kaynak bekçisi: çöken kalıp hiçbir yüzeyde kalmadı', () {
    // Kusur tek satırlık bir kalıptı ve altı sağlayıcı + yedi ekran aynı
    // kalıbı tekrarlıyordu. Kalıbın geri gelmesi sessiz olur: derleme
    // başarılı, testler yeşil, kilitler yine yanıp söner.
    const yuzeyler = [
      'lib/core/providers.dart',
      'lib/features/sky/sky_screen.dart',
      'lib/features/oracle/bazi_tab.dart',
      'lib/features/oracle/iching_tab.dart',
      'lib/features/atlas/birth_hexagram_screen.dart',
      'lib/features/atlas/inner_calendar_screen.dart',
      'lib/features/atlas/solar_return_screen.dart',
      'lib/features/atlas/atlas_screen.dart',
    ];

    for (final yol in yuzeyler) {
      test('$yol: üçüncü hâl AYRI çiziliyor', () {
        expect(_yorumsuz(yol), contains('PlusHali.bilinmiyor'),
            reason: 'bu yüzey "bilmiyorum" hâlini ayırt etmiyor');
      });
    }

    for (final yol in yuzeyler.where((y) => y != 'lib/core/providers.dart')) {
      test('$yol: abonelik DOĞRUDAN izlenmiyor', () {
        // Kural dizeye değil YOLA bağlı: aktiflik yalnız kapıdan okunur.
        // `ref.watch(subscriptionProvider)` ile okunan her yerde "cevap
        // geldi mi" sorusu ikinci kez, elle sorulmak zorunda kalıyor ve iki
        // kez atlandı. Kapının kendisi providers.dart'ta, o yüzden muaf.
        //
        // `ref.read`/`ref.refresh` kapsam DIŞI: sky_screen'in tanıtım
        // paywall'ı durumu okuyor ama kararı `paywallKarariVerilebilir`
        // kapısından geçiriyor (KT3 + ilkacilis-2 bekçileri orada).
        expect(_yorumsuz(yol), isNot(contains('ref.watch(subscriptionProvider')),
            reason: 'iki durumlu okuma geri geldi');
      });
    }

    test('ücretli sağlayıcıların kapısı TEK yerde', () {
      final kaynak = _yorumsuz('lib/core/providers.dart');
      expect(kaynak,
          contains('bool _hasPlus(Ref ref) => '
              'ref.watch(raporKapisiProvider) == PlusHali.abone;'));
      expect(kaynak, isNot(contains('.value?.active ?? false')),
          reason: 'yükleniyorken "abone değil" diyen kalıp geri geldi');
    });

    test('Atlas natal satırı: kilit rozeti KAPIYA bağlı', () {
      // Bu satırın R5-0 turunda zaten üç durumu vardı (`loading` → bekliyor,
      // `error` → tekrar dene) ama `null`ın ÜÇÜNCÜ kaynağı atlanmıştı:
      // abonelik/profil cevabı gelmeden sağlayıcı istek atmadan `null`
      // dönüyor ve satır kilitli çiziliyordu. `_AtlasRow` özel bir sınıf ve
      // AtlasScreen Firestore akışlarına bağlı, o yüzden kaynaktan
      // sabitleniyor (rapor_uretilemedi_test ile aynı desen).
      final kaynak = _yorumsuz('lib/features/atlas/atlas_screen.dart');
      expect(kaynak, contains('locked: metin == null && !bilinmiyor'));
      expect(kaynak, isNot(contains('locked: metin == null,')),
          reason: 'cevap gelmeden kilit rozeti basılıyor');
      expect(kaynak, isNot(contains('onTap: () => metin == null ? paywall()')),
          reason: 'cevap gelmeden dokunuş paywall açıyor');
    });

    test('Atlas kehanet karoları: DÖRDÜ birden kilitlenmiyor', () {
      // Yukarıdaki dosya başına bekçi bu yüzeyi KORUMUYOR: atlas_screen'de
      // iki ayrı yüzey var (natal satırı + dört karo) ve `PlusHali.bilinmiyor`
      // yalnız birinde geçse dosya bekçisi yine yeşil kalır. Kusur bu
      // oturumda gerçekten dört karoda birden duruyordu, o yüzden sınıf
      // gövdesi ayrıca sabitleniyor.
      final kaynak = _yorumsuz('lib/features/atlas/atlas_screen.dart');
      final govde =
          kaynak.substring(kaynak.indexOf('class _DivinationRow'));
      expect(govde, contains('PlusHali.bilinmiyor'),
          reason: 'dört karo cevap gelmeden kilitli çiziliyor');
      expect(govde, contains('SkeletonPanel'),
          reason: 'üçüncü hâl AYRI çizilmeli: ne kilit ne açık karo');
      expect(govde, isNot(contains('.value?.active ?? false')),
          reason: 'iki durumlu okuma geri geldi');
    });

    test('takvim serisi YALNIZ cevap yoldayken bekler', () {
      // Aynı kalıbın çift istek varyantı: `select((s) => s.value?.active ??
      // false)` yükleniyorken `false` okuyup takvimi KİLİTLİ çekiyor, gerçek
      // cevap `true` gelince ikinci kez çekiyordu. O kapı DURUYOR.
      //
      // Ama bekleme koşulu bir tur boyunca `PlusHali.bilinmiyor`a bağlıydı ve
      // o değer İKİ ayrı şeyi birbirine karıştırıyor: "cevap YOLDA" ile
      // "cevap OKUNAMADI". İkincisi TERMİNAL: `abonelikDurumunuOku` geniş
      // yakalamayla bir `AsyncData` üretiyor, yani Riverpod için hata değil ve
      // kendiliğinden hiç yenilenmiyor. Sonuç ölçüldü: `/billing/status` tek
      // bir zaman aşımına düştüğünde ÜCRETSİZ olan 30 günlük şerit ana
      // ekrandan OTURUM BOYUNCA kayboluyordu — oysa bu dosyanın kendi
      // gerekçesi (transitCalendarProvider üstü) "sorulursa ücretsiz kullanıcı
      // şeridi hiç göremez" diye tam bunu yasaklıyor.
      //
      // Doğru kapı: yalnız GERÇEKTEN yükleniyorsa bekle. Okunamadıysa istek
      // atılır ve kilit kararını zaten SUNUCU veriyor — yani istek atmak
      // "kilidi tahmin etmek" DEĞİL.
      final kaynak = _yorumsuz('lib/core/providers.dart');
      final govde = kaynak.substring(kaynak.indexOf('transitCalendarProvider ='));
      expect(govde, isNot(contains('select((s) => s.value?.active ?? false)')),
          reason: 'kilitli takvim çekilip ikinci kez tazeleniyor');
      expect(govde, contains('ref.watch(subscriptionProvider).isLoading'),
          reason: 'cevap yoldayken istek atılırsa çift istek doğar');
      expect(govde, isNot(contains('PlusHali.bilinmiyor')),
          reason: 'okunamayan durum beklemeye sebep sayılmış: tek bir zaman '
              'aşımı ÜCRETSİZ şeridi oturum boyunca yok eder');
    });
  });

  // -------------------------------------------------------------------------
  group('P2-2 burç halkası ön-çekme', () {
    // ÖLÇÜLEN kusur: halka ana ekranda istek BİLE atmıyordu. `ZodiacChip`
    // düz bir `StatelessWidget` ve gövdesinde `ref.watch` yok; istek ancak
    // `SignStoryScreen` inşa edilince doğuyor. Gecikme "yavaş yükleme"
    // değil HİÇ BAŞLAMAMIŞ bir yüklemeydi.
    test('yalnız TEK burç ön-çekilir', () {
      // On iki burcu birden çekmek on iki PARALEL LLM tetiği demek olurdu.
      final anahtarlar = onCekilecekBurclar(3);
      expect(anahtarlar, [kSignKeys[3]]);
      expect(anahtarlar, hasLength(1),
          reason: '12 burç = 12 eşzamanlı LLM çağrısı');
    });

    test('burç bilinmiyorsa HİÇ istek yok', () {
      // Doğum verisi eksikken `signIndexOf` -1 döner; hesaplanmamış bir şey
      // için istek atılmaz.
      expect(onCekilecekBurclar(-1), isEmpty);
      expect(onCekilecekBurclar(12), isEmpty, reason: 'aralık dışı');
    });

    test('her burç için anahtar doğru', () {
      for (var i = 0; i < kSignKeys.length; i++) {
        expect(onCekilecekBurclar(i), [kSignKeys[i]]);
      }
    });

    test('ön-çekme ana ekranda KURULUYOR', () {
      // Liste doğru olsa bile kimse çağırmıyorsa kusur yerinde kalır.
      final sky = _yorumsuz('lib/features/sky/sky_screen.dart');
      expect(sky, contains('_onCekBurcHikayesi(userSignIndex)'));
      expect(sky, contains('ref.read(signHoroscopeProvider(anahtar)'));
    });

    test('ön-çekme HATAYI önbellekte bırakmıyor', () {
      // Sağlayıcı auto-dispose DEĞİL: kimsenin görmediği bir hata oturum
      // boyunca kalır (CLAUDE.md §5). O hâlde kullanıcı halkaya dokununca
      // hikâye ekranı istek ATMADAN hata kartı çizer — ön-çekme olmasaydı
      // dokunuş taze bir istek atacaktı, yani hızlandırma tek başına bir
      // gerilemeye dönerdi. Bekçi düşen çekimin kendi izini sildiğini
      // sabitliyor.
      final sky = _yorumsuz('lib/features/sky/sky_screen.dart');
      expect(sky, contains('ref.invalidate(signHoroscopeProvider(anahtar))'),
          reason: 'düşen ön-çekme hatayı oturum boyunca önbellekte bırakıyor');
    });

    test('halka hâlâ kendi isteğini atmıyor (çip düz widget)', () {
      // Ön-çekme ekranda yaşıyor; çipin içine taşınırsa 12 çip 12 istek
      // atar ve P2-2'nin kaçındığı şey geri gelir.
      final cipler = _yorumsuz('lib/widgets/nebula_widgets.dart');
      expect(cipler, isNot(contains('signHoroscopeProvider')),
          reason: '12 çip = 12 istek');
    });
  });
}

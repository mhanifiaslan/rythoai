// Bedel satırı SUNUCUDAN gelir — elle yazılmış dizeden DEĞİL (bulgu B1).
//
// Ölçülen kusur: `/billing/wallet` yanıtı `costs` haritasını gönderiyor
// (sunucudaki `core/wallet.py` `TOKEN_COSTS` tablosunun aynısı),
// `WalletStatus.fromJson` onu AYRIŞTIRIYOR — ama hiçbir yüzey okumuyordu.
// Kredi Mağazası'nın altındaki bedel satırı `l10n.tokenCostsNote`, yani
// elle yazılmış bir cümleydi. Böylece bedel gerçeğinin İKİ kaynağı vardı.
//
// ⚠️ Bu başlığın ilk hâli devamında "sunucu tablosu değişir, ekran eski
// rakamı söylemeye devam eder, HİÇBİR TEST DÜŞMEZ" diyordu. O gerekçe
// YANLIŞTI ve mutasyonla ölçüldü (2026-10-02): `core/wallet.py`
// `TOKEN_COSTS` içinde `chat` 1→4 yapıldığında
// `backend/tests/test_honesty.py::TestJetonIddialari
// ::test_magazadaki_bedel_satiri_koddaki_bedellerle_ayni` KIRMIZI oluyor —
// o bekçi iki ARB dosyasındaki her sayıyı kendi etiketinin yanında
// çivilemiş durumda ("Sohbet mesajı 1", "I Ching 2", …). Depoda ayrışma
// sessiz DEĞİL, ve `bedelSatiri`nin konuma bağlı eşleştirmesinin dayanağı
// da tam olarak o bekçi.
//
// Sessiz olan şey başka: o bekçi HEAD'i ölçüyor, CİHAZDAKİ PAKETİ
// ölçemiyor. Sunucu ayrı dağıtıldığı için (`infra/deploy-backend.ps1` ↔
// sürüm kodu) `TOKEN_COSTS` bir backend dağıtımıyla değiştiği an kurulu
// uygulamanın derlenmiş cümlesi eski rakamı söylemeye devam eder.
// Onarımın kapattığı pencere bu; aşağıdaki bekçiler de bunu ölçüyor.
//
// Bekçi DÖRT bacaklı, çünkü tek bacak kör kalırdı:
//  1. Ekran: sunucu alışılmadık bedeller söylediğinde satır ONLARI çizer ve
//     elle yazılmış cümle ekranda HİÇ bulunmaz.
//  2. Saf işlev: eşleştirmenin ön koşulları tutmazsa satıra DOKUNULMAZ
//     (uydurma sayı üretmek, bayat sayıdan daha kötü).
//  3. Ön koşulun KENDİSİ: iki dilin şablonunda tam dört sayı var mı? Yoksa
//     1. bacak hâlâ yeşil kalırken ürün sessizce şablona düşmüş olurdu.
//  4. TAŞIMA halkası: `WalletStatus.fromJson` sunucunun `costs` alanını
//     gerçekten ayrıştırıyor mu? Bu bacak sonradan eklendi çünkü ölçüm
//     onun YOKLUĞUNU buldu: `fromJson`dan `costs` ayrıştırması tamamen
//     silindiğinde (mutasyon, 2026-10-02) depodaki hiçbir test kırmızı
//     olmuyordu — ekranı besleyen bekçiler haritayı doğrudan enjekte
//     ettiği için zincirin ortası ölçülmemiş kalmıştı. O halka koparsa
//     harita her zaman boş gelir, satır sessizce şablona düşer ve
//     onarımdan ÖNCEKİ hâle geri dönülür.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` türü flutter_riverpod 3'te misc.dart'tan geliyor.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show StoreProduct;
import 'package:rytho/core/subscription.dart'
    show SubscriptionStatus, subscriptionProvider;
import 'package:rytho/core/wallet.dart'
    show WalletStatus, tokenPacksProvider, walletProvider;
import 'package:rytho/features/paywall/token_store_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';

/// Metin üretilen l10n sınıfından okunuyor: cümle yeniden yazılsa bekçi
/// kırılmaz, ANAHTAR silinse derleme kırılır (magaza_hata_dali deseni).
AppLocalizations _l10n(String dil) => lookupAppLocalizations(Locale(dil));

/// Sunucunun söylediği, derlemenin tablosuna HİÇ benzemeyen bedeller.
///
/// Sayılar bilerek gerçek tablodan uzak (1/2/3/5 → 7/9/11/13) ve biri İKİ
/// HANELİ: tek haneli sayılarla eşleştirme hatası "aynı rakam" diye
/// gizlenebilirdi. Derin raporların hepsi aynı bedelde, çünkü şablon onları
/// TEK sayıyla özetliyor.
const _kSunucuBedelleri = {
  'chat': 7,
  'iching': 9,
  'dyad': 11,
  'natal': 13,
  'bazi': 13,
  'synastry': 13,
  'face': 13,
  'birth_hexagram': 13,
  'solar_return': 13,
  'progressions': 13,
};

/// Beklenen satırın BAĞIMSIZ hesabı.
///
/// Üretimdeki [bedelSatiri] elle tampon kuruyor; buradaki karşılık
/// `replaceAllMapped` ile yazıldı. İki ayrı gerçekleştirme bilerek: beklenti
/// test edilen işlevin kendisinden türetilseydi iddia totoloji olurdu
/// ("işlev kendisiyle aynı sonucu veriyor").
String _sayilariDegistir(String sablon, List<int> yeni) {
  var i = 0;
  return sablon.replaceAllMapped(RegExp(r'\d+'), (_) => '${yeni[i++]}');
}

Widget _uygulama(Widget ekran, {required List<Override> overrides}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildRythoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ekran,
      ),
    );

/// Ekranı çizer.
///
/// Yükseklik BOL: test yazı tipi her harfi punto kadar geniş kare çiziyor,
/// yani içerik gerçek cihazdan uzun ve `ListView` tembel — görünme alanına
/// hiç girmeyen çocuk AĞAÇTA OLMAZ, bedel satırı da listenin EN ALTINDA.
/// `pumpAndSettle` YASAK: yıldız alanı sonsuz döner (cosmic_scaffold).
Future<void> _ciz(WidgetTester tester, {required Map<String, int> bedeller}) async {
  tester.view.physicalSize = const Size(1200, 9000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_uygulama(const TokenStoreScreen(), overrides: [
    // Paketler YALNIZ aboneye gösteriliyor (karar K2); bedel satırı
    // listenin en altında ve kapıdan bağımsız, ama abone olmayan bir
    // kapsamda ekranın yarısı hiç çizilmiyor.
    subscriptionProvider
        .overrideWith((_) async => const SubscriptionStatus(active: true)),
    walletProvider.overrideWith((_) async => WalletStatus(
        allowance: 40, purchased: 0, monthlyAllowance: 100,
        costs: bedeller)),
    // Mağazaya hiç gidilmiyor: ölçülen şey bedel satırı.
    tokenPacksProvider.overrideWith((_) async => const <StoreProduct>[]),
  ]));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  // -------------------------------------------------------------------------
  group('ön koşul: şablonlar eşleştirilebilir durumda', () {
    // Bu grup olmasa ürün sessizce şablona düşebilirdi: `bedelSatiri` ön
    // koşul tutmazsa satırı OLDUĞU GİBİ döndürüyor (uydurma sayı üretmek
    // bayat sayıdan kötü). O hâlde ekran yine "bir şey" çizer, widget
    // bekçisi de kendi şablonuyla karşılaştırdığı için YEŞİL kalırdı.
    for (final dil in ['tr', 'en']) {
      test('$dil şablonunda TAM dört sayı var', () {
        final sablon = _l10n(dil).tokenCostsNote;
        final sayilar =
            RegExp(r'\d+').allMatches(sablon).map((m) => m.group(0)).toList();
        expect(sayilar, hasLength(4),
            reason: 'tokenCostsNote sayıları sırayla sohbet · I Ching · '
                'ikili · derin özeti olmak zorunda. Cümle yeniden '
                'yazıldıysa (ya da bir sayı eklendiyse) bedel satırı '
                'sunucudan türetilemez ve ekran derlemenin tablosuna '
                'düşer — $sayilar bulundu');
      });
    }

    test('sunucu bedelleri şablonun sayılarından FARKLI (testin kendi koşulu)',
        () {
      // Aynı sayılar olsaydı aşağıdaki widget iddiası, satır hiç
      // türetilmese de geçerdi.
      final sablon = _l10n('tr').tokenCostsNote;
      expect(_sayilariDegistir(sablon, const [7, 9, 11, 13]), isNot(sablon));
    });
  });

  // -------------------------------------------------------------------------
  group('bedelSatiri — saf işlev', () {
    test('sunucu haritası şablonun sayılarını DEĞİŞTİRİR', () {
      final sablon = _l10n('tr').tokenCostsNote;
      expect(bedelSatiri(sablon, _kSunucuBedelleri),
          _sayilariDegistir(sablon, const [7, 9, 11, 13]));
    });

    test('İngilizce şablon da türetiliyor — eşleşme kelimeye bağlı DEĞİL', () {
      // Eşleştirme konuma bağlı: dile bağlı bir çapa olsaydı EN satırı
      // sessizce şablonda kalırdı.
      final sablon = _l10n('en').tokenCostsNote;
      expect(bedelSatiri(sablon, _kSunucuBedelleri),
          _sayilariDegistir(sablon, const [7, 9, 11, 13]));
    });

    test('bedel OKUNAMADIYSA şablona dokunulmaz', () {
      // Cüzdan yüklenirken ve `WalletStatus.unknown` hâlinde harita boş.
      final sablon = _l10n('tr').tokenCostsNote;
      expect(bedelSatiri(sablon, const {}), sablon);
      expect(bedelSatiri(sablon, WalletStatus.unknown.costs), sablon);
    });

    test('tek tek anılan bir özellik haritada yoksa dokunulmaz', () {
      // Daha eski/yeni bir sunucu `dyad`ı göndermeyi bırakabilir.
      //
      // ⚠️ Bu testin ilk gerekçesi "kalan üç sayı KAYDIRILARAK yazılırdı"
      // diyordu ve mutasyon onu YALANLADI: `deger == null` dalı
      // `return sablon` yerine `continue` yapıldığında bu test YEŞİL
      // kalıyor. Sebep ölçüldü — üretimdeki şablonda tam dört sayı var,
      // adlı özellik sayısı üç; biri atlanınca toplanan sayı adedi üçte
      // kalıyor ve satırı asıl koruyan `yerler.length != sayilar.length`
      // kapısı oluyor. Yani bu test ön koşulu belgeliyor, `continue`
      // ile `return` arasındaki farkı DEĞİL; o farkı aşağıdaki test
      // ölçüyor.
      final sablon = _l10n('tr').tokenCostsNote;
      final eksik = Map<String, int>.from(_kSunucuBedelleri)..remove('dyad');
      expect(bedelSatiri(sablon, eksik), sablon);
    });

    test('eksik özellik sayı adedini TESADÜFEN tutturursa da dokunulmaz',
        () {
      // `deger == null` dalının ASIL işi burada görünüyor: üç sayılı bir
      // şablonda eksik harita, atlanan özelliğin yerine bir sonrakinin
      // sayısını yazdırabilirdi ("ikili dinamik 13" gibi uydurma bir
      // satır). Üretim şablonu bugün dört sayılı olduğu için bu dal
      // ekranda tetiklenmiyor; test onu yine de çiviliyor çünkü koruma
      // bir TESADÜFE (şablondaki sayı adedinin özellik adedinden bir
      // fazla olmasına) bağlı kalmamalı — çeviri yeniden yazıldığında o
      // tesadüf bozulur ve dal sessizce yük taşımaya başlar.
      final eksik = Map<String, int>.from(_kSunucuBedelleri)..remove('dyad');
      expect(bedelSatiri('A 1 · B 2 · C 3', eksik), 'A 1 · B 2 · C 3');
    });

    test('derin raporlar tek bedelde ANLAŞMIYORSA dokunulmaz', () {
      // Şablon onları TEK sayıyla özetliyor; biri ayrışırsa özet yalan
      // olur. Hangi sayının yazılacağını seçmek de bir uydurma olurdu.
      final sablon = _l10n('tr').tokenCostsNote;
      final ayrik = Map<String, int>.from(_kSunucuBedelleri)..['bazi'] = 99;
      expect(bedelSatiri(sablon, ayrik), sablon);
    });

    test('derin rapor HİÇ yokken dokunulmaz — özet sayısı ölçülemez', () {
      final sablon = _l10n('tr').tokenCostsNote;
      expect(bedelSatiri(sablon, const {'chat': 7, 'iching': 9, 'dyad': 11}),
          sablon);
    });

    test('şablondaki sayı adedi dörtten farklıysa dokunulmaz', () {
      // Çeviriye sayı eklenirse eşleştirme kayar; o hâlde satır olduğu gibi
      // kalır ve yukarıdaki "ön koşul" bekçisi kırmızıya döner.
      expect(bedelSatiri('a 1 b 2 c 3 d 4 e 5', _kSunucuBedelleri),
          'a 1 b 2 c 3 d 4 e 5');
      expect(bedelSatiri('yalnız 1 sayı', _kSunucuBedelleri), 'yalnız 1 sayı');
    });

    test('sayı DIŞINDAKİ her şey korunur (biçim bozulmuyor)', () {
      expect(bedelSatiri('A 1 · B 2 · C 3 · D 5 kredi.', _kSunucuBedelleri),
          'A 7 · B 9 · C 11 · D 13 kredi.');
    });
  });

  // -------------------------------------------------------------------------
  group('taşıma halkası: WalletStatus.fromJson', () {
    // Zincirin ORTASI. Sunucu ucu `backend/tests/test_belge_tarifesi.py`de
    // çivili (harita `TOKEN_COSTS` mü, yanıt modeli alanı taşıyor mu),
    // ekran ucu aşağıdaki widget bekçisinde. Aradaki ayrıştırma hiçbir
    // yerde ölçülmüyordu: ekran bekçisi haritayı `WalletStatus`a doğrudan
    // veriyor, yani `fromJson` hiç koşmuyor. Mutasyonla doğrulandı
    // (2026-10-02): `costs` ayrıştırması `fromJson`dan silindiğinde
    // `bedel_satiri` · `cuzdan_tazeleme` · `cuzdan_bilinmiyor`
    // takımlarının HEPSİ yeşil kalıyordu.

    /// `api/billing.py` `WalletStatus` yanıt modelinin ALAN ADLARIYLA
    /// birebir. Şekil elle yazılı çünkü ölçülen şey tam olarak budur:
    /// sunucunun gönderdiği anahtar adı ile istemcinin aradığı anahtar
    /// adı aynı mı. Bir kopya üretmek (ör. `WalletStatus.toJson`) iddiayı
    /// totolojiye çevirirdi.
    const sunucuGovdesi = {
      'allowance': 12,
      'purchased': 40,
      'total': 52,
      'monthly_allowance': 100,
      'allowance_resets_at': null,
      'costs': {'chat': 7, 'iching': 9, 'dyad': 11, 'natal': 13},
    };

    test('sunucunun `costs` alanı ayrıştırılıyor', () {
      final cuzdan = WalletStatus.fromJson(
          Map<String, dynamic>.from(sunucuGovdesi));
      expect(cuzdan.costs, {'chat': 7, 'iching': 9, 'dyad': 11, 'natal': 13},
          reason: 'bedel haritası sunucudan ekrana ULAŞMIYOR: mağaza satırı '
              'her zaman şablona düşer ve onarımdan önceki hâle dönülür');
    });

    test('`costs` yoksa boş harita — null DEĞİL, patlama DEĞİL', () {
      // Eski bir sunucu ya da 503 sonrası eksik gövde. Boş harita
      // `bedelSatiri`nin "dokunma" dalına düşer; null olsa ekran çizerken
      // fırlatırdı.
      final govde = Map<String, dynamic>.from(sunucuGovdesi)..remove('costs');
      expect(WalletStatus.fromJson(govde).costs, isEmpty);
    });

    test('sayılar ondalık gelse de int olarak okunuyor', () {
      // JSON sayıları `double` çözülebiliyor (`as int` doğrudan fırlatır);
      // alan `num` üzerinden okunuyor ve bu dal onu çiviliyor.
      final govde = Map<String, dynamic>.from(sunucuGovdesi)
        ..['costs'] = {'chat': 7.0};
      expect(WalletStatus.fromJson(govde).costs, {'chat': 7});
    });
  });

  // -------------------------------------------------------------------------
  group('etiket ↔ sayı bağı', () {
    // NEDEN bu grup var (ölçüldü 2026-10-02, doğrulama turu): yukarıdaki
    // iddiaların HEPSİ konuma bağlı. Beklenti de üretim de şablondaki
    // sayıları SIRAYLA işliyor, yani şablonun sırası değişirse ikisi
    // BİRLİKTE kayar ve bekçi yeşil kalırken ekranda "I Ching 1" yazar.
    // Bu kusur bu pakette bir tur boyunca GERÇEKTEN yaşandı — kod
    // tarafında: `_kBedelSirasi` `['chat', 'dyad', 'iching']` yazılıydı ve
    // ekranda 2 ile 3 yer değişmişti. Kod tarafını yukarıdaki testler
    // yakalıyor; ŞABLON tarafını (çevirinin yeniden sıralanması) hiçbir şey
    // yakalamıyordu.
    //
    // ⚠️ Şablon tarafı MUTASYONLA sınanamadı: şablon `lib/l10n/` altındaki
    // ÜRETİLEN ve PAYLAŞIMLI dosyalardan okunuyor, bu tur onlara
    // dokunmuyor. Bunun yerine denetimin kendi dişi sentetik bir şablonla
    // ölçülüyor (son test) — "ön koşulun kendisini ölç" deseni.

    /// Etiket -> özellik adı. Dize LİTERALİ olarak karşılaştırılıyor:
    /// `lower()` yok (Türkçe kıvrımı bozuk) ve alt dize aranmıyor, etiketin
    /// hemen ardındaki sayı okunuyor. Dört etiketin DÖRDÜ de burada, yani
    /// şablonun tamamı bağlı — tek bir kelimeye dayanmıyor.
    const etiketler = {
      'tr': {
        'Sohbet mesajı': 'chat',
        'I Ching': 'iching',
        'ikili dinamik': 'dyad',
        'derin raporlar ve yüz okuma': '_derin',
      },
      'en': {
        'Chat message': 'chat',
        'I Ching': 'iching',
        'daily dyad': 'dyad',
        'deep reports and face reading': '_derin',
      },
    };

    /// Satırda etiketinin yanında YANLIŞ sayı duran etiketlerin listesi.
    List<String> sapmalar(String satir, Map<String, String> harita) {
      final bulunan = <String>[];
      harita.forEach((etiket, ad) {
        final beklenen =
            ad == '_derin' ? 13 : _kSunucuBedelleri[ad];
        if (!satir.contains('$etiket $beklenen')) {
          bulunan.add('$etiket -> $beklenen bekleniyordu');
        }
      });
      return bulunan;
    }

    for (final dil in ['tr', 'en']) {
      test('$dil: her etiketin YANINDA kendi bedeli duruyor', () {
        final sablon = _l10n(dil).tokenCostsNote;
        final harita = etiketler[dil]!;

        // Çapa bacağı: etiketler şablonda GERÇEKTEN var mı? Çeviri yeniden
        // yazıldıysa bu denetim sessizce hiçbir şey ölçmez olurdu.
        for (final etiket in harita.keys) {
          expect(sablon.contains(etiket), isTrue,
              reason: '$dil şablonunda "$etiket" etiketi yok: cümle yeniden '
                  'yazıldıysa bu bekçi de güncellenir, yoksa etiket↔sayı '
                  'bağı ÖLÇÜLMEZ olur');
        }

        expect(sapmalar(bedelSatiri(sablon, _kSunucuBedelleri), harita),
            isEmpty,
            reason: 'üretilen satırda bir etiketin yanında BAŞKA özelliğin '
                'bedeli duruyor. Eşleştirme konuma bağlı; şablonun sırası '
                'ile `_kBedelSirasi` ayrıştığı an kullanıcı yanlış sayı '
                'okur (bu pakette bir tur boyunca böyleydi)');
      });
    }

    test('denetimin DİŞİ var: sırası bozuk şablonda sapma GÖRÜLÜYOR', () {
      // Şablon tarafı mutasyonu `lib/l10n/` paylaşımlı olduğu için
      // koşturulamıyor; sentetik şablon onun yerine duruyor. Burada "I
      // Ching" ikinci değil BİRİNCİ sırada, yani konuma bağlı eşleştirme
      // sohbet bedelini onun yanına yazıyor.
      const tersSablon = 'I Ching 2 · Sohbet mesajı 1 · ikili dinamik 3 · '
          'derin raporlar ve yüz okuma 5 kredi.';
      final satir = bedelSatiri(tersSablon, _kSunucuBedelleri);
      expect(satir.contains('I Ching 7'), isTrue,
          reason: 'sentetik şablon beklendiği gibi işlenmedi');
      expect(sapmalar(satir, etiketler['tr']!), isNotEmpty,
          reason: 'denetim kör: sırası bozuk bir şablonda bile sapma '
              'görmüyor, yani yukarıdaki iki test hiçbir şey ölçmüyor');
    });
  });

  // -------------------------------------------------------------------------
  group('Kredi Mağazası ekranı', () {
    testWidgets('bedel satırı SUNUCUNUN sayılarını çiziyor', (tester) async {
      final sablon = _l10n('tr').tokenCostsNote;
      await _ciz(tester, bedeller: _kSunucuBedelleri);

      expect(find.text(_sayilariDegistir(sablon, const [7, 9, 11, 13])),
          findsOneWidget,
          reason: 'satır sunucudan gelen `costs` haritasından üretilmiyor');
      expect(find.text(sablon), findsNothing,
          reason: 'elle yazılmış l10n cümlesi hâlâ ekranda: bedel gerçeğinin '
              'ikinci kaynağı duruyor ve sunucu tablosu değiştiğinde sessizce '
              'yanlışa düşer');
    });

    testWidgets('bedel okunamadıysa şablon çiziliyor — satır KAYBOLMUYOR',
        (tester) async {
      // Ters yön: onarım, cüzdan okunamadığında bedel satırını tamamen
      // silmiş olmasın. İki pazarlama sayfası "bedeller jeton mağazasında
      // yazılıdır" diyor (backend/tests/test_honesty.py onu çiviliyor) ve
      // satır yoksa o cümle dayanaksız kalır.
      await _ciz(tester, bedeller: const {});
      expect(find.text(_l10n('tr').tokenCostsNote), findsOneWidget);
    });
  });
}

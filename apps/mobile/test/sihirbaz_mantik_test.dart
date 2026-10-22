// Sihirbaz saf mantığı ve kaynak bekçileri (D4, K6).
//
// Ölçülen kusurlar (2026-10-10): cinsiyet `female` ÖNSEÇİLİYDİ (dokunmadan
// geçen "kadın" beyan ediyordu); saat 12:00 + ayrı bir `_saatSecildi`
// bayrağıyla taşınıyordu; bildirim izni seçim sorulmadan HER bitişte OS'a
// soruluyordu; kayıt `set()` zaman aşımsızdı ve hata "Kayıt başarısız."
// diye sebepsizdi; kayıt sahnesi saatsiz doğumda da "Evler hesaplanıyor"
// diyordu — sunucu saatsiz doğumda ev hesaplamaz.
//
// Kaynak bekçileri yorumları atar (`_yorumsuz`): bir şeyin YOKLUĞUNU
// arayan bekçi onu anlatan yoruma takılmasın.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/onboarding/onboarding_wizard.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';

final _tr = AppLocalizationsTr();

const _sihirbaz = 'lib/features/onboarding/onboarding_wizard.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// `_bitir` gövdesi: tanımından bir sonraki metoda kadar.
String _bitirGovdesi(String kaynak) {
  final bas = kaynak.indexOf('Future<void> _bitir() async {');
  final son = kaynak.indexOf('Future<void> _tarihSec()', bas);
  expect(bas, greaterThan(-1), reason: '_bitir bulunamadı');
  expect(son, greaterThan(bas), reason: '_tarihSec _bitir\'den sonra olmalı');
  return kaynak.substring(bas, son);
}

void main() {
  test('kOnboardingSteps: altı adım, telefon yok (K6)', () {
    expect(kOnboardingSteps,
        ['welcome', 'date', 'time', 'place', 'gender', 'notify']);
  });

  group('sihirbazIlerleyebilir', () {
    bool f(
      String adim, {
      bool riza = true,
      bool aiRiza = true,
      DateTime? tarih,
      bool saatBiliniyor = true,
      TimeOfDay? saat,
      String? sehir,
      String? cinsiyet,
      bool? bildirim,
    }) =>
        sihirbazIlerleyebilir(
          adim: adim,
          riza: riza,
          aiRiza: aiRiza,
          tarih: tarih,
          saatBiliniyor: saatBiliniyor,
          saat: saat,
          sehir: sehir,
          cinsiyet: cinsiyet,
          bildirimSecimi: bildirim,
        );

    test('welcome: iki kutu da şart — şartlar ve yapay zeka; biri yetmez',
        () {
      expect(f('welcome', riza: false), isFalse);
      expect(f('welcome', aiRiza: false), isFalse,
          reason: 'yapay zeka onayının sorulduğu tek yer; atlanabilirse '
              'hiç sorulmamış olur');
      expect(f('welcome', riza: false, aiRiza: false), isFalse);
      expect(f('welcome'), isTrue);
    });

    test('yapay zeka kutusu YALNIZ welcome adımında sayılır', () {
      // Onay bir kez sorulur: sonraki adımlar onu yeniden istemez.
      expect(f('date', aiRiza: false, tarih: DateTime(1990, 3, 7)), isTrue);
      expect(f('notify', aiRiza: false, bildirim: false), isTrue);
    });

    test('date: tarih şart', () {
      expect(f('date'), isFalse);
      expect(f('date', tarih: DateTime(1990, 3, 7)), isTrue);
    });

    test('time: "biliyorum" + saat yok → DUR; "bilmiyorum" + saat yok → geç',
        () {
      expect(f('time', saatBiliniyor: true, saat: null), isFalse,
          reason: 'seçilmemiş saat 12:00 diye yazılırdı');
      expect(f('time', saatBiliniyor: false, saat: null), isTrue);
      expect(
          f('time',
              saatBiliniyor: true,
              saat: const TimeOfDay(hour: 4, minute: 30)),
          isTrue);
    });

    test('place: boş ya da yalnız boşluk şehir geçmez', () {
      expect(f('place'), isFalse);
      expect(f('place', sehir: '   '), isFalse);
      expect(f('place', sehir: 'İstanbul'), isTrue);
    });

    test('gender: seçilmeden geçilmez; "belirtmedim" de bir seçim', () {
      expect(f('gender'), isFalse, reason: 'seçilmeyen beyan edilmez');
      expect(f('gender', cinsiyet: 'unspecified'), isTrue);
      expect(f('gender', cinsiyet: 'male'), isTrue);
    });

    test('notify: seçimsiz geçilmez; "Şimdi değil" (false) de bir karar', () {
      expect(f('notify'), isFalse);
      expect(f('notify', bildirim: false), isTrue);
      expect(f('notify', bildirim: true), isTrue);
    });

    test('bilinmeyen adım geçmez — kuralı unutulan yeni adım sessizce '
        'atlanabilir olmasın', () {
      expect(f('phone'), isFalse);
    });
  });

  group('onboardingStages', () {
    test('saat biliniyor → üç aşama, evler dahil', () {
      expect(onboardingStages(_tr, saatBiliniyor: true), [
        _tr.onboardingStage1,
        _tr.onboardingStage2,
        _tr.onboardingStage3,
      ]);
    });

    test('saat bilinmiyor → iki aşama, "Evler hesaplanıyor" YOK', () {
      final asamalar = onboardingStages(_tr, saatBiliniyor: false);
      expect(asamalar, hasLength(2));
      expect(asamalar, isNot(contains(_tr.onboardingStage2)),
          reason: 'sunucu saatsiz doğumda ev hesaplamaz; sahne '
              'hesaplanmayanı hesaplanıyor gösteremez');
      expect(asamalar, [_tr.onboardingStage1, _tr.onboardingStage3]);
    });
  });

  test('bildirimSorulmali: yalnız true sorar; null ve false sormaz', () {
    expect(bildirimSorulmali(true), isTrue);
    expect(bildirimSorulmali(false), isFalse);
    expect(bildirimSorulmali(null), isFalse);
  });

  group('kaynak bekçisi — onboarding_wizard.dart', () {
    final k = _yorumsuz(_sihirbaz);

    test('telefon adımı, _TelefonAdimi ve PhoneVerifyScreen importu yok', () {
      expect(k, isNot(contains("'phone'")));
      expect(k, isNot(contains('phone_verify_screen')));
      expect(k, isNot(contains('_TelefonAdimi')));
    });

    test('cinsiyet önseçili DEĞİL: String? _cinsiyet, female literali yok',
        () {
      expect(k, isNot(contains("_cinsiyet = 'female'")));
      expect(k, isNot(contains("'female'")),
          reason: 'değerler CinsiyetSecici.degerler\'den gelir');
      expect(k, contains('String? _cinsiyet;'));
      expect(k, contains('gender: _cinsiyet!'));
    });

    test('12:00 yalnız seçicinin AÇILIŞ konumu; _saat nullable, bayrak yok',
        () {
      expect('TimeOfDay(hour: 12'.allMatches(k), hasLength(1));
      expect(k, contains('_saat ?? const TimeOfDay(hour: 12, minute: 0)'));
      expect(k, contains('initialTime: baslangic'));
      expect(k, contains('TimeOfDay? _saat;'));
      expect(k, isNot(contains('_saatSecildi')));
      // Kayıtta saat yalnız biliniyor + seçilmişken yazılır.
      expect(k, contains('_saatBiliniyor && _saat != null ? saatMetni(_saat)'));
    });

    test('bildirim izni YALNIZ "Haber ver" dalında istenir', () {
      final govde = _bitirGovdesi(k);
      expect(
          RegExp(r'if \(bildirimSorulmali\(_bildirimSecimi\)\) \{\s*try \{\s*'
                  r'await ensureNotificationPermissionAsked\(\);')
              .hasMatch(govde),
          isTrue,
          reason: '"Şimdi değil" diyen kullanıcıya OS diyaloğu açılmamalı; '
              'bayrak yazılmayınca ana ekrandaki ikinci şans yaşar');
      // Tek çağrı yeri: import satırındaki `show` parantezsiz, sayılmaz.
      expect('ensureNotificationPermissionAsked()'.allMatches(k), hasLength(1));
    });

    test('set() zaman aşımlı; hata sebepli + Tekrar dene; "Kayıt başarısız." '
        'yok', () {
      final govde = _bitirGovdesi(k);
      expect(govde, contains('.timeout(kYazmaZamanAsimi)'));
      expect(k,
          contains('const Duration kYazmaZamanAsimi = Duration(seconds: 15);'));
      expect(govde, contains('friendlyError(e, l10n)'));
      expect(govde, contains('label: l10n.retry'));
      expect(k, isNot(contains('onboardingFailed')));
    });

    test('yerel kopyalar silindi — her kavram için tek tanım', () {
      for (final kopya in [
        '_SecimSatiri',
        '_CinsiyetSecimi',
        '_BildirimAdimi',
        '_atlanabilirAdim',
        'wizardLater',
        'LegalPage(',
        'signOutEverywhere',
        'CheckboxListTile(\n                        value: !_saatBiliniyor',
      ]) {
        expect(k, isNot(contains(kopya)), reason: '$kopya hâlâ sihirbazda');
      }
      for (final tek in [
        'SecimSatiri(',
        'CinsiyetSecici(',
        'SaatBilinmiyorKutusu(',
        'IzinKapisi(',
        'sehirEtiketi(_sehir, _ulke)',
        'openLegal(context, LegalDoc.terms)',
        'openLegal(context, LegalDoc.privacy)',
        'onayliCikis(context)',
      ]) {
        expect(k, contains(tek), reason: '$tek sihirbazda kullanılmıyor');
      }
    });

    test("'Gezgin' sabiti yok; ad l10n.defaultUserName'den (sihirbaz + ana "
        'ekran)', () {
      expect(k, isNot(contains("'Gezgin'")));
      expect(k, contains('?? l10n.defaultUserName'));
      final sky = _yorumsuz('lib/features/sky/sky_screen.dart');
      expect(sky, isNot(contains("'Gezgin'")));
      expect(sky, contains('?? l10n.defaultUserName'));
    });

    test('sayfa geçişi hareket kapılı; çıplak süre yok; tek giriş yolu '
        'RythoReveal', () {
      // Tek geçiş yolu `motion.sayfayaGit`: ileri ve geri onu çağırır;
      // sıfır süre / `jumpToPage` kararı ARTIK BURADA DEĞİL, motion.dart'ta
      // (D5: hikâye ekranıyla ortak). Yerel bir kopya geri gelirse iki ekran
      // yeniden ayrışır — `animateToPage` sıfır süreyi assert ile reddeder,
      // hareket azaltan kullanıcı ilk "Devam"da takılırdı (ölçüldü:
      // sihirbaz_adimlar_test tamamı kırmızıydı).
      expect('sayfayaGit(_sayfa, context, _adim'.allMatches(k), hasLength(2),
          reason: 'ileri ve geri');
      expect(k, isNot(contains('void _sayfayaGit(')),
          reason: 'yerel kopya motion.sayfayaGit ile tekleşti');
      expect(k, isNot(contains('jumpToPage(')));
      expect(k, isNot(contains('animateToPage(')));
      // Adlandırılmış iki sabit dışında Duration( literali yok.
      expect(RegExp(r'Duration\((milliseconds|seconds):').allMatches(k),
          hasLength(2));
      expect(k, isNot(contains('.animate(')));
      expect(k, isNot(contains('repeat(')));
    });

    test('takımyıldız: adım+1 yıldız, sonuncusu kayıt sahnesinde; '
        'Semantics "Adım i/n"', () {
      expect(k, contains('total: _toplamAdim + 1'));
      expect(k, contains('lit: _busy ? _toplamAdim + 1 : _adim + 1'));
      expect(k, contains('label: l10n.wizardStepOf(_adim + 1, _toplamAdim)'));
    });

    test('kayıt sahnesi aşamaları onboardingStages\'ten, saat bilgisiyle', () {
      expect(k, contains('onboardingStages(l10n,\n'
          '                          saatBiliniyor: _saatBiliniyor)'));
    });
  });

  group('kaynak bekçisi — komşular', () {
    test('IzinKapisi etiketleri: "Haber ver" / "Şimdi değil" (Sonra değil)',
        () {
      final k = _yorumsuz('lib/widgets/izin_kapisi.dart');
      expect(k, contains('[l10n.wizardNotifyAllow, l10n.wizardNotifyNotNow]'));
      expect(k, isNot(contains('wizardLater')));
    });

    test("CinsiyetSecici dördüncü etiket ARB'den; sabit metin köprüsü yok",
        () {
      final k = _yorumsuz('lib/widgets/dogum_formu.dart');
      expect(k, contains('l10n.genderUnspecified'));
      expect(k, isNot(contains('_belirtilmedi')));
      expect(k, isNot(contains("'Belirtmedim'")));
      expect(k, isNot(contains("'Not specified'")));
    });

    test('şehir dizini düşerse ErrorCard + tekrar dene; spinner yalnız '
        'yüklenirken', () {
      final k = _yorumsuz('lib/widgets/city_search_field.dart');
      expect(k, contains('ErrorCard('));
      expect(k, contains('onRetry: _yukle'));
      expect(k, contains('friendlyError(_hata!, l10n)'));
      expect(
          RegExp(r'_hata != null\s*\?').hasMatch(k), isTrue,
          reason: 'hata dalı spinner dalından ÖNCE gelmeli');
      expect('CircularProgressIndicator'.allMatches(k), hasLength(1));
    });
  });
}

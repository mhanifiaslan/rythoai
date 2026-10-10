// Giriş/auth yüzeylerinin KAYNAK bekçileri (D4).
//
// Davranış testlerinin göremediği şeyleri çiviler: logo "nefes"inin
// (kapısız sonsuz döngü) geri gelmemesi, yerel stagger sayacının
// (`next()`) geri gelmemesi, giriş hareketinin tek yoldan (`RythoReveal`)
// kurulması, hukuk sayfasının tek kapıdan açılması, ölü anahtarın
// (`deviceConflictSignOut`) kodda yeniden kullanılmaması.
//
// Eşleşmeden ÖNCE yorumlar atılır (CLAUDE.md: bir şeyin YOKLUĞUNU arayan
// bekçi onu ANLATAN yorumu görmemeli — iki kez patladı).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

const _login = 'lib/features/auth/login_screen.dart';
const _forgot = 'lib/features/auth/forgot_password_screen.dart';
const _conflict = 'lib/features/auth/device_conflict_screen.dart';
const _onay = 'lib/widgets/onay.dart';
const _methods = 'lib/features/profile/sign_in_methods_screen.dart';
const _bigThree = 'lib/widgets/big_three_reveal.dart';

void main() {
  group('login_screen.dart — hareket disiplini', () {
    final k = _yorumsuz(_login);

    test('kapısız sonsuz döngü (logo nefesi) YOK', () {
      // HEAD'de 425-441: `.animate(onPlay: (c) => c.repeat(reverse: true))`
      // — beyaz listede değildi, reduceMotion'ı okumuyordu.
      expect(k, isNot(contains('repeat(')));
      expect(k, isNot(contains('onPlay:')));
    });

    test('yerel stagger sayacı (next()) YOK; tek yol RythoReveal', () {
      expect(k, isNot(contains('next()')));
      expect(k, isNot(contains('.animate(')),
          reason: 'her giriş hareketi RythoReveal üzerinden; çıplak zincir '
              'reduceMotion kapısını atlar');
      // 5 giriş bloğu (marka, başlık, slogan, form, onay) 0..4 sırasıyla.
      for (var i = 0; i < 5; i++) {
        expect(k, contains('index: $i'), reason: 'RythoReveal(index: $i) yok');
      }
      expect('RythoReveal('.allMatches(k).length, 5);
    });

    test('şifre alanları SifreAlanlari; hukuk sayfası openLegal', () {
      expect(k, contains('SifreAlanlari('));
      expect(k, isNot(contains('_obscureToggle')),
          reason: 'göz düğmesinin yerel kopyası geri geldi');
      expect(k, contains('openLegal(context, LegalDoc.terms)'));
      expect(k, contains('openLegal(context, LegalDoc.privacy)'));
      expect(k, isNot(contains('LegalPage(')),
          reason: 'hukuk sayfası tek kapıdan açılır (D3)');
    });
  });

  test('forgot_password: e-posta ipucu sözlükten', () {
    final k = _yorumsuz(_forgot);
    expect(k, isNot(contains('ornek@eposta.com')));
    expect(k, contains('l10n.emailHint'));
  });

  test('ölü anahtar deviceConflictSignOut kodda kullanılmaz; çıkış tek '
      'anahtar (signOut)', () {
    // D8 anahtarı silecek; o güne kadar kimse yeniden kullanmasın.
    final kullananlar = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final yol = f.path.replaceAll('\\', '/');
      if (!yol.endsWith('.dart') || yol.contains('/l10n/')) continue;
      if (_yorumsuz(yol).contains('deviceConflictSignOut')) kullananlar.add(yol);
    }
    expect(kullananlar, isEmpty);
    expect(_yorumsuz(_conflict), contains('l10n.signOut'));
    expect(_yorumsuz(_onay), contains('confirmLabel: l10n.signOut'));
  });

  test('sign_in_methods: şifre SifreAlanlari ile, elle kural kopyası yok',
      () {
    final k = _yorumsuz(_methods);
    expect(k, contains('SifreAlanlari('));
    expect(k, isNot(contains('validatePassword(')),
        reason: 'kural tek yerde (SifreAlanlari doğrulayıcısı)');
    expect(k, isNot(contains('_sifreGizli')),
        reason: 'göz düğmesinin yerel kopyası geri geldi');
    expect(k, contains('_googleHata'));
    expect(k, contains('_sifreHata'));
  });

  test('big_three_reveal: mühür sabit genişlikte değil', () {
    final k = _yorumsuz(_bigThree);
    expect(k, isNot(contains('width: 92')));
    expect(k, contains('Expanded('));
    expect(k, contains('maxWidth: kMuhurGenisligi'));
  });
}

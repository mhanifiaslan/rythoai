// ARB hijyeni (D8): okuyucusuz anahtar YOK, ✨ yalnız beş başarı anında,
// İngilizce sayılı dizeler çoğul kalıbıyla.
//
// Ölçüldü (2026-10-12): 58 anahtarın `lib/` altında tek okuyucusu yoktu —
// kaldırılmış ekranların (telefon adımı, promo banner, hızlı günlük) ve iki
// kez yeniden yazılmış metinlerin kalıntıları; biri (`onboardingSavedNoChart`)
// D5'te eklenip hiç bağlanmamıştı. Ölü anahtar iki şeye mal oluyor: çeviri
// emeği ve "bu metin ekranda" yanılgısı — bekçiler ona çapa atabiliyor.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String dil) => json.decode(
        File('lib/l10n/app_$dil.arb').readAsStringSync())
    as Map<String, dynamic>;

Iterable<String> _anahtarlar(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@'));

String _libKaynagi() {
  final sb = StringBuffer();
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    final p = f.path.replaceAll(r'\', '/');
    if (!p.endsWith('.dart') || p.contains('/l10n/')) continue;
    sb.writeln(f.readAsStringSync());
  }
  return sb.toString();
}

/// ✨ yalnız bir EYLEMİN sonucunu kutlayan beş anahtarda — CTA, slogan,
/// segment etiketi ve durum satırından çıktı (15 → 5).
const _parilti = {
  'avatarUpdated',
  'subRestoreDone',
  'linkGoogleDone',
  'tokenPurchaseDone',
  'discoveryComplete',
};

/// `int` yer tutucusu taşıyıp çoğul kalıbı OLMAYAN İngilizce dizeler —
/// sayı bir ADET değilse (ev numarası, çizgi numarası, saniye, sıra)
/// çoğul gerekmez; listede gerekçesiyle durur.
const _cogulsuzIzinli = {
  'wizardStepOf', // "Step 2 of 6" — sıra
  'solarReturnHouseN', // ev numarası
  'birthHexagramGateLine', // kapı/çizgi numarası
  'birthHexagramGateOnly',
  'birthHexagramBoundary',
  'iChingCoinsLanding', // "{n}/6"
  'iChingNuclearLabel', // "#{n}"
  'iChingLineLabel', // çizgi numarası
  'iChingPalaceLabel',
  'baziLuckStartLabel', // "{years}y {months}m" kısaltma
  'contactsFindActive', // "{count} on Rytho" — sayı yalın
  'phoneResendIn', // "{seconds}s"
  'peopleSlots', // "{used}/{limit}"
  'forgotPasswordResendWait', // "({seconds}s)"
  'chartOrbLabel', // derece
};

void main() {
  test('her ARB anahtarının lib altında bir okuyucusu var', () {
    final kaynak = _libKaynagi();
    final olu = <String>[];
    for (final k in _anahtarlar(_arb('tr'))) {
      if (!RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(kaynak)) olu.add(k);
    }
    expect(olu, isEmpty,
        reason: 'okuyucusuz anahtar: ya bağla ya sil (iki dilde birden)');
  });

  test('TR ve EN aynı anahtar kümesi', () {
    final tr = _anahtarlar(_arb('tr')).toSet();
    final en = _anahtarlar(_arb('en')).toSet();
    expect(tr.difference(en), isEmpty, reason: 'EN eksik');
    expect(en.difference(tr), isEmpty, reason: 'TR eksik');
  });

  for (final dil in ['tr', 'en']) {
    test('$dil: ✨ yalnız beş başarı anahtarında', () {
      final arb = _arb(dil);
      final parilti = {
        for (final k in _anahtarlar(arb))
          if ((arb[k] as String).contains('✨')) k,
      };
      expect(parilti, _parilti);
    });
  }

  test('EN: int yer tutuculu dize ya çoğul kalıbı taşır ya da izinli', () {
    final en = _arb('en');
    final eksik = <String>[];
    for (final k in _anahtarlar(en)) {
      final meta = en['@$k'];
      if (meta is! Map) continue;
      final ph = meta['placeholders'];
      if (ph is! Map) continue;
      final intVar = ph.entries
          .any((e) => e.value is Map && (e.value as Map)['type'] == 'int');
      final deger = en[k] as String;
      if (intVar && !deger.contains('plural') && !_cogulsuzIzinli.contains(k)) {
        eksik.add(k);
      }
    }
    expect(eksik, isEmpty, reason: '"1 weeks" sınıfı: çoğul kalıbı ekle');
  });
}

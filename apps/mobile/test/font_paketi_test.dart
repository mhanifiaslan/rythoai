// Yazı tipi paketi bekçileri (D1): fontlar PAKETTE, ağdan çekme KAPALI, glif
// fontu uygulamanın bastığı her glifi KAPSIYOR.
//
// NEDEN: üç aile yalnız GoogleFonts.* ile açılışta fonts.gstatic.com'dan
// iniyordu (ağsız açılışta yedek font flaşı; `chart_wheel_test` bile
// `allowRuntimeFetching=false` yazmak zorunda kalmıştı). ♀/♂ ve burç glifleri
// ise Android'de renkli emojiye düşüyordu (mağaza karesinde görüldü) çünkü
// Manrope'ta yoklar. İkisinin çözümü de "doğru dosya pakette" — ve bu depoda
// "pakette" iddiası ölçülmeden söylenmez (RevenueCat anahtarı dersi).
//
// Bu dosya `tools/font_paketi_uret.py` ile AYNI politikayı taşır (bilinçli
// emoji kümesi, bilinen açıklar); biri değişince diğeri de değişir — iki yer
// olmasının sebebi birinin üretici (Python, fonttools), diğerinin CI bekçisi
// (Dart) olması.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/theme/rytho_glyphs.dart';

/// Kaynak bekçileri bir şeyin YOKLUĞUNU ararken kendi açıklama yorumuna
/// takılmasın (CLAUDE.md §5: iki kez patladı).
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// google_fonts paketinin aradığı dosya adı ekleri
/// (google_fonts_variant.dart:181-184). Başka ad SESSİZCE bulunamaz.
const _agirlikAdi = {400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold'};

/// `RythoText.<kurucu>` → (aile, varsayılan ağırlık). rytho_theme.dart ile
/// birebir; kurucu eklenirse buraya da eklenir (aksi hâlde test o kurucuyu
/// görmez — bu yüzden aşağıda "kurucu sayısı" da çivili).
const _kurucular = {
  'display': ('Sora', 700),
  'body': ('Manrope', 400),
  'mono': ('JetBrainsMono', 400),
  'label': ('Manrope', 700),
};

/// Uygulamanın BİLEREK renkli emoji olarak bastığı karakterler — sistem
/// emoji fontuna düşer, glif fontuna girmez. tools/font_paketi_uret.py
/// `BILINCLI_EMOJI` ile aynı.
const _bilincliEmoji = {
  0x2600, // ☀️ Büyük Üçlü "Güneş"
  0x2B06, // ⬆️ Büyük Üçlü "Yükselen"
  0x2615, // ☕ arkadaşlık ilişki ikonu
  0x262F, // ☯/☯️ İ Ching ikonu (D7'de tek biçime çekilir)
  0x21A9, // ↩️ retro çipi
  0x2728, 0x2764, 0x26A0, 0xFE0F, 0xFE0E, 0x200D,
};

/// Paket fontlarda OLMAYAN ve henüz değiştirilmemiş karakterler; dalga
/// kapanınca silinir ve test o karakteri bulursa kırmızı döner.
// ℞ (U+211E) D6/D7'de çarkın "R" retro işaretiyle birleşti ve ARB'den
// çıktı; liste bilerek BOŞ — yeni bir açık bulunursa gerekçesiyle girer.
const _bilinenAcik = <int, String>{};

bool _emojiMi(int kod) => kod >= 0x1F000 || _bilincliEmoji.contains(kod);

Set<int> _kapsam(String yol) => File(yol)
    .readAsLinesSync()
    .where((s) => s.startsWith('U+'))
    .map((s) => int.parse(s.substring(2), radix: 16))
    .toSet();

List<String> _dartDosyalari() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f.path.replaceAll('\\', '/'))
    .where((p) => p.endsWith('.dart') && !p.contains('/l10n/'))
    .toList();

/// `RythoText.<kurucu>(` çağrılarında istenen (aile, ağırlık) çiftleri —
/// parantez dengesiyle; gövdedeki TÜM `FontWeight.wNNN` literalleri sayılır.
///
/// NEDEN "tümü": ZodiacChip ağırlığı üçlü ifadeyle seçiyor
/// (`w: selected ? w700 : w500`). Yalnız ilk literali alan ölçüm 500'ü
/// kaçırdı ve Manrope-Medium pakete girmedi — allowRuntimeFetching=false
/// ile cihazda fırlardı. `w:` var ama literal yoksa [literalsiz] doluyor.
Set<(String, int)> _istenenAgirliklar({List<String>? literalsiz}) {
  final sonuc = <(String, int)>{};
  final cagri = RegExp(r'RythoText\.(display|body|mono|label)\(');
  final literal = RegExp(r'FontWeight\.w(\d{3})');
  for (final yol in _dartDosyalari()) {
    final s = _yorumsuz(yol);
    for (final m in cagri.allMatches(s)) {
      var i = m.end;
      var derinlik = 1;
      while (i < s.length && derinlik > 0) {
        if (s[i] == '(') derinlik++;
        if (s[i] == ')') derinlik--;
        i++;
      }
      final govde = s.substring(m.end, i);
      final (aile, varsayilan) = _kurucular[m.group(1)]!;
      final wIfade = _wIfadesi(govde);
      if (wIfade == null) {
        sonuc.add((aile, varsayilan));
        continue;
      }
      // Üçlü ifade serbest ama HER DALI literal olmalı: `c ? w700 : agirlik`
      // mutasyonu ilk sürümde yeşil kalmıştı (gövdede bir literal vardı,
      // ikinci dal değişkendi) — kör bekçi, mutasyon turunda ölçüldü.
      final dallar = wIfade.contains('?')
          ? wIfade.substring(wIfade.indexOf('?') + 1).split(':')
          : [wIfade];
      for (final dal in dallar) {
        final lit = literal.matchAsPrefix(dal.trim());
        if (lit == null || lit.end != dal.trim().length) {
          literalsiz?.add('$yol: w: $wIfade');
          continue;
        }
        sonuc.add((aile, int.parse(lit.group(1)!)));
      }
    }
  }
  return sonuc;
}

/// `w:` argümanının ifadesi — bir sonraki üst düzey `,` ya da gövde sonuna
/// kadar. Yoksa null.
String? _wIfadesi(String govde) {
  final m = RegExp(r'\bw:\s*').firstMatch(govde);
  if (m == null) return null;
  var i = m.end;
  var derinlik = 0;
  while (i < govde.length) {
    final c = govde[i];
    if (c == '(' || c == '[') derinlik++;
    if (c == ')' || c == ']') {
      if (derinlik == 0) break;
      derinlik--;
    }
    if (c == ',' && derinlik == 0) break;
    i++;
  }
  return govde.substring(m.end, i).trim();
}

void main() {
  group('ağdan çekme kapalı, dosyalar pakette', () {
    test('main() allowRuntimeFetching=false yazıyor', () {
      expect(_yorumsuz('lib/main.dart'),
          contains('GoogleFonts.config.allowRuntimeFetching = false'),
          reason: 'bayrak düşerse eksik font sessizce fonts.gstatic.com\'a gider');
    });

    test('istenen her (aile, ağırlık) için dosya VAR ve pubspec\'te', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final istenen = _istenenAgirliklar();
      expect(istenen, isNotEmpty);
      for (final (aile, agirlik) in istenen) {
        final ad = _agirlikAdi[agirlik];
        expect(ad, isNotNull, reason: '$aile w$agirlik: adı olmayan ağırlık');
        final yol = 'assets/google_fonts/$aile-$ad.ttf';
        expect(File(yol).existsSync(), isTrue,
            reason: '$yol yok — kod bu ağırlığı istiyor; '
                'tools/font_paketi_uret.py METIN_FONTLARI listesine eklenip '
                'yeniden koşturulmalı (allowRuntimeFetching=false ile FIRLATIR)');
        expect(pubspec, contains('- $yol'),
            reason: '$yol pubspec assets listesinde değil');
      }
    });

    test('RythoText çağrılarında ağırlık LİTERALLERDEN okunabiliyor', () {
      // Ağırlık bir değişkenden gelirse yukarıdaki ölçüm onu göremez ve
      // cihazda eksik dosya fırlatır. `w:` yazan her çağrı gövdesinde en az
      // bir `FontWeight.wNNN` literali olmalı (üçlü ifade serbest: ikisi de
      // literal).
      final literalsiz = <String>[];
      _istenenAgirliklar(literalsiz: literalsiz);
      expect(literalsiz, isEmpty,
          reason: 'literal olmayan ağırlık: ${literalsiz.join(' | ')}');
    });

    test('rytho_theme: DÖRT kurucu da glif fontunu yedek zincirine alıyor', () {
      final k = _yorumsuz('lib/theme/rytho_theme.dart');
      // google_fonts fallback parametresini ÜZERİNE YAZIYOR; sarmalayıcı
      // dönüşten sonra eklemeli. Sarmalanmamış kurucu = emoji'ye düşen glif.
      expect(RegExp(r'_glifli\(GoogleFonts\.').allMatches(k).length,
          _kurucular.length,
          reason: 'bir kurucu _glifli ile sarılmamış');
      expect(RegExp(r'GoogleFonts\.\w+\(').allMatches(k).length,
          _kurucular.length,
          reason: 'GoogleFonts çağrı sayısı kurucu tablosuyla uyuşmuyor — '
              'yeni kurucu eklendiyse _kurucular ve _glifli güncellenmeli');
      expect(k, contains('kRythoGlyphFont'));
      // Glif fontu adı pubspec ile aynı olmalı.
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('family: $kRythoGlyphFont'));
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('asset: assets/fonts/$kRythoGlyphFont.ttf'));
    });

    test('kapsam listeleri pakete GİRMİYOR', () {
      // Dizin olarak listelense .codepoints.txt de pakete girerdi.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('- assets/google_fonts/\n')));
      expect(pubspec, isNot(contains('- assets/fonts/\n')));
    });

    test('bütçe: font yükü ≤ 1 MB', () {
      var toplam = 0;
      for (final d in ['assets/google_fonts', 'assets/fonts']) {
        for (final f in Directory(d).listSync().whereType<File>()) {
          if (f.path.endsWith('.ttf')) toplam += f.lengthSync();
        }
      }
      expect(toplam, lessThanOrEqualTo(1024 * 1024),
          reason: 'font yükü ${toplam ~/ 1024} KB — alt küme bozulmuş olabilir');
      expect(toplam, greaterThan(200 * 1024),
          reason: 'font yükü şüpheli küçük — dosyalar boş mu?');
    });

    test('OFL lisans metinleri depoda', () {
      for (final ad in ['Sora', 'Manrope', 'JetBrainsMono', 'NotoSansSymbols']) {
        expect(File('../../docs/legal/fonts/OFL-$ad.txt').existsSync(), isTrue,
            reason: 'OFL-$ad.txt yok — paketlenen font atıfsız');
      }
    });
  });

  group('glif fontu kapsamı', () {
    final kapsam = _kapsam('assets/fonts/$kRythoGlyphFont.codepoints.txt');

    test('kRythoGlyphCodePoints listesinin her üyesi fontta', () {
      final eksik = kRythoGlyphCodePoints.where((k) => !kapsam.contains(k));
      expect(eksik, isEmpty,
          reason: 'fontta olmayan glif: '
              '${eksik.map((k) => 'U+${k.toRadixString(16).toUpperCase()}').join(', ')} '
              '— tools/font_paketi_uret.py GLIF_KODLARI ile yeniden üretilmeli');
    });

    test('tabloların her glifi listede (tablo ↔ liste ayrışmaz)', () {
      final tablodakiler = <int>{
        for (final g in kSignGlyphs) g.runes.single,
        for (final g in kPlanetTextGlyphs.values) g.runes.single,
        for (final g in kExtraPointGlyphs.values) g.runes.single,
        for (final g in kAspectTextGlyphs.values) g.runes.single,
      };
      final listede = kRythoGlyphCodePoints.toSet();
      expect(tablodakiler.difference(listede), isEmpty,
          reason: 'tabloya glif eklendi ama kRythoGlyphCodePoints\'e değil');
    });
  });

  group('uygulamanın bastığı her karakter bir paket fontta', () {
    test('ARB değerleri + Dart literalleri (yorumsuz) ⊆ kapsam ∪ emoji ∪ bilinen açık',
        () {
      final hepsi = <int>{
        ..._kapsam('assets/google_fonts/Sora.codepoints.txt'),
        ..._kapsam('assets/google_fonts/Manrope.codepoints.txt'),
        ..._kapsam('assets/google_fonts/JetBrainsMono.codepoints.txt'),
        ..._kapsam('assets/fonts/$kRythoGlyphFont.codepoints.txt'),
      };
      final kullanilan = <int>{};
      for (final p in ['lib/l10n/app_tr.arb', 'lib/l10n/app_en.arb']) {
        final veri = jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
        veri.forEach((k, v) {
          if (v is String && !k.startsWith('@')) {
            kullanilan.addAll(v.runes.where((r) => r > 127));
          }
        });
      }
      final literal = RegExp(r"'((?:[^'\\]|\\.)*)'");
      for (final yol in _dartDosyalari()) {
        for (final m in literal.allMatches(_yorumsuz(yol))) {
          kullanilan.addAll(m.group(1)!.runes.where((r) => r > 127));
        }
      }
      final acik = kullanilan
          .where((k) => !_emojiMi(k) && !hepsi.contains(k))
          .toList()
        ..sort();
      final yeni = acik.where((k) => !_bilinenAcik.containsKey(k)).toList();
      expect(yeni, isEmpty,
          reason: 'hiçbir paket fontta olmayan karakter (sistem fontuna, '
              'Android\'de emojiye düşer): '
              '${yeni.map((k) => 'U+${k.toRadixString(16).toUpperCase()} ${String.fromCharCode(k)}').join(', ')}');
      // Bilinen açık listesi bayatlamış mı: kapanan iş listeden silinmeli.
      final bayat = _bilinenAcik.keys.where((k) => !kullanilan.contains(k));
      expect(bayat, isEmpty,
          reason: '_bilinenAcik bayat — artık kullanılmıyor: '
              '${bayat.map((k) => 'U+${k.toRadixString(16).toUpperCase()}').join(', ')}');
    });
  });
}

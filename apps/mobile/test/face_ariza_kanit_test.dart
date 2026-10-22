// gz-10 bekçileri: yüz okuma arızası YAYIN derlemesinde sessiz kalmasın.
//
// Bilgi üretiliyor ve atılıyordu: segmenter sebebi titizce tutuyor
// (`lastError`/`lastTimings`) ama tek okuyucu `assert` bloğunun içindeydi —
// yayın derlemesinde hiç koşmaz. Üç hata yolu da `catch (_)` ile sebebi
// yutuyordu. Yüz okuma 12 testçinin 12 ayrı kamerası/NNAPI'si üzerinde
// koşacak en kırılgan özellik ve cihaz log'u bize kapalı (ölçüm ekrandan
// okunuyor), yani tek kanal Crashlytics.
//
// Bunlar davranış değil YAPI değişmezleri: kamera ve Firebase olmadan
// doğrulanabilecek tek yer kaynak metni (aynı desen: hata_dili_test.dart
// "Kaynak bekçisi", coin_toss_kanit_test.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Satır sonu normalize edilir (dosya CRLF) ve TAM SATIR yorumları atılır.
///
/// Bir şeyin YOKLUĞUNU arayan bekçi, onu ANLATAN yorumu görmemeli — bu depoda
/// gerçekten patlamış bir tuzak. Satır içi `//` bırakılıyor: dize
/// literallerinde de geçebiliyor.
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// `assert(() { ... }())` bloklarının gövdeleri.
///
/// Teşhis bu bloklara geri kapanırsa yayın derlemesinde yine hiç koşmaz —
/// kusurun kendisi tam olarak buydu.
List<String> _assertGovdeleri(String kaynak) {
  final govdeler = <String>[];
  var i = kaynak.indexOf('assert(() {');
  while (i >= 0) {
    final son = kaynak.indexOf('}());', i);
    govdeler.add(son < 0 ? kaynak.substring(i) : kaynak.substring(i, son));
    i = kaynak.indexOf('assert(() {', i + 1);
  }
  return govdeler;
}

void main() {
  final kaynak = _yorumsuz('lib/features/face/face_capture_screen.dart');
  final segmenter = _yorumsuz('lib/features/face/face_segmentation.dart');

  test('sebep hâlâ ÜRETİLİYOR: segmenter lastError/lastTimings tutuyor', () {
    expect(segmenter, contains('String? lastError;'));
    expect(segmenter, contains('String? lastTimings;'));
  });

  test('hata ekranına düşen hiçbir yol sebebi YUTMUYOR', () {
    // `catch (_)` başka yerlerde meşru (tek bozuk kare akışı düşürmemeli);
    // yasak olan, kullanıcıyı hata ekranına düşürüp sebebi atmak.
    expect(
        kaynak,
        isNot(contains('} catch (_) {\n      if (!mounted) return;\n'
            '      setState(() => _asama = _Asama.hata);')),
        reason: 'arıza ekranına düşen yol sebebi bildirmeden geçmemeli');
    expect(kaynak, contains("_arizaBildir(e, iz, 'kamera-kurulum')"));
    expect(kaynak, contains("_arizaBildir(e, iz, 'cekim')"));
  });

  test('izin reddi ARIZA SAYILMIYOR: kullanıcının kararı bildirilmez', () {
    expect(kaynak, contains('} on CameraException catch (e, iz) {'));
    // Rapor koşulu ve durum koşulu TEK yüklemden (U23). İki ayrı ham
    // `contains('Permission')` vardı ve iOS kodları (`CameraAccess…`) ikisini
    // de ıskalıyordu; ayrışırlarsa ret ya izin ekranında Crashlytics'e
    // yazılır ya da arıza ekranında sessiz kalır.
    expect(kaynak, contains('final izinReddi = kameraIzniReddi(e.code);'));
    expect(
        kaynak,
        contains("if (!izinReddi) {\n"
            "        _arizaBildir(e, iz, 'kamera-kurulum');"));
    expect(kaynak, contains('izinReddi ? _Asama.izinYok : _Asama.hata'));
    expect(kaynak, isNot(contains("e.code.contains('Permission')")),
        reason: 'yüklem ekranın içinde yeniden yazılırsa iki koşul ayrışır');
  });

  test('model YÜKLENEMEZSE de bildiriliyor', () {
    // Bu, `maske == null` kancasının GÖREMEDİĞİ yol: `_segmentle()`
    // `!_segmenter.ready` ile ilk satırda döner, yani yükleme düşüşü hiç
    // oraya gelmez. Sahada en olası arıza da bu.
    expect(kaynak, contains('unawaited(_segmenter.load()'),
        reason: 'load() sonucu yutuluyorsa yükleme arızası sessiz kalır');
    expect(kaynak, contains("'segmenter-yukleme'"));
  });

  test('sessiz segmentasyon düşüşü de bildiriliyor (ekran başına bir kez)',
      () {
    expect(kaynak, contains("'segmentasyon'"));
    expect(kaynak, contains('bool _segArizaBildirildi = false;'),
        reason: '700 ms\'de bir bildirim kanalı kullanışsız hale getirirdi');
    expect(kaynak, contains('if (maske == null && !_segArizaBildirildi) {'));
  });

  test('bildirim teşhis anahtarlarını taşıyor', () {
    expect(kaynak, contains('void _arizaBildir('));
    expect(kaynak, contains('crash.recordError(hata, iz'));
    for (final anahtar in [
      'face_asama',
      'face_seg_hata',
      'face_seg_sure',
      'face_sac_hata',
    ]) {
      expect(kaynak, contains("setCustomKey('$anahtar'"), reason: anahtar);
    }
  });

  test('bildirim assert DIŞINDA: yayın derlemesinde koşuyor', () {
    expect(kaynak.contains('_arizaBildir('), isTrue);
    for (final govde in _assertGovdeleri(kaynak)) {
      expect(govde, isNot(contains('_arizaBildir(')),
          reason: 'teşhis assert bloğuna geri kapandı; yayında hiç koşmaz');
    }
  });
}

import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/face/face_detection.dart';
import 'package:rytho/features/face/face_scan_overlay.dart';
import 'package:rytho/features/face/face_segmentation.dart' show sourcePixel;

/// Tarama noktalarinin GORUNTU uzayindan EKRAN uzayina tasinmasi.
///
/// Bu esleme iki kez bozuldu ve ikisinde de kusur SESSIZDI — hicbir hata
/// cikmadi, noktalar sadece yanlis yere dustu:
///
/// 1. Olcekleme icin verilen goruntu boyutu UYDURULMUSTU (`yuz kutusu x 3`).
///    Gercek kareyle ilgisi olmadigi icin noktalar rastgele bir yerde
///    beliriyordu.
/// 2. On kamera onizlemesi ayna gibi gosteriliyor (CameraX varsayilani) ama
///    ML Kit koordinatlari aynalanMAMIS sensor uzayinda geliyor. Cihazda
///    "noktalar yuzumun solunda" diye gorundu.
///
/// Ikincisinin neden gec fark edildigi onemli: **aynalamak kadrajlama
/// kontrolunu etkilemiyor.** Merkeze uzaklik aynalamada degismiyor, yalnizca
/// isareti donuyor. Yani kilavuz dogru calisirken noktalar yanlis yerdeydi.
///
/// Ucuncusu iOS'ta bekliyordu (U09): `camera_avfoundation` akis karesini
/// zaten DIK ve on kamerada zaten AYNALI veriyor, ML Kit de onu dondurmeden
/// okuyor. Android hesabi orada boyutu ters cevirir, maskeyi 90 derece
/// dondurur ve noktalari ikinci kez aynalardi. Simulatorde gorulemez (ML Kit
/// ve TFLite orada yok), o yuzden sozlesme burada sabitleniyor.

/// Yalniz boyutu tasiyan sahte kare: geometri yardimcilari pikselleri okumuyor.
class _Kare implements CameraImage {
  _Kare(this.width, this.height);

  @override
  final int width;

  @override
  final int height;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CameraDescription _kamera(CameraLensDirection yon, int sensor) =>
    CameraDescription(name: yon.name, lensDirection: yon, sensorOrientation: sensor);

void main() {
  // Dik goruntu, uzun ekran: yatayda kirpilir (BoxFit.cover).
  const goruntu = Size(480, 640);
  const ekran = Size(1080, 2340);

  group('BoxFit.cover eslemesi', () {
    test('goruntu merkezi ekran merkezine dusrer', () {
      final sonuc = mapScanPoints(
        points: [Offset(goruntu.width / 2, goruntu.height / 2)],
        imageSize: goruntu,
        screenSize: ekran,
        mirrored: false,
      );
      expect(sonuc.single.dx, closeTo(ekran.width / 2, 0.5));
      expect(sonuc.single.dy, closeTo(ekran.height / 2, 0.5));
    });

    test('dikeyde tam kaplar — ust ve alt kenar ekrana oturur', () {
      final sonuc = mapScanPoints(
        points: [const Offset(240, 0), const Offset(240, 640)],
        imageSize: goruntu,
        screenSize: ekran,
        mirrored: false,
      );
      expect(sonuc.first.dy, closeTo(0, 0.5));
      expect(sonuc.last.dy, closeTo(ekran.height, 0.5));
    });

    test('yatayda kirpilir — kenarlar ekran disina tasar', () {
      final sonuc = mapScanPoints(
        points: [const Offset(0, 320)],
        imageSize: goruntu,
        screenSize: ekran,
        mirrored: false,
      );
      expect(sonuc.single.dx, lessThan(0),
          reason: 'cover yatayda kirpiyor; sol kenar ekranin disinda kalmali');
    });

    test('bozuk goruntu boyutu cokmez', () {
      expect(
        mapScanPoints(
          points: [const Offset(1, 1)],
          imageSize: Size.zero,
          screenSize: ekran,
          mirrored: false,
        ),
        isEmpty,
      );
    });
  });

  group('aynalama', () {
    test('merkez aynalamada YERINDE kalir', () {
      // Bu, kusurun neden gec fark edildigini gosteriyor: yuz tam ortadayken
      // aynalama hicbir sey degistirmiyor.
      final duz = mapScanPoints(
        points: [Offset(goruntu.width / 2, 200)],
        imageSize: goruntu,
        screenSize: ekran,
        mirrored: false,
      );
      final ayna = mapScanPoints(
        points: [Offset(goruntu.width / 2, 200)],
        imageSize: goruntu,
        screenSize: ekran,
        mirrored: true,
      );
      expect(ayna.single.dx, closeTo(duz.single.dx, 0.5));
    });

    test('merkezden kacik nokta KARSI tarafa gecer', () {
      const nokta = Offset(120, 200); // goruntunun sol yarisi
      final duz = mapScanPoints(
        points: const [nokta],
        imageSize: goruntu,
        screenSize: ekran,
        mirrored: false,
      );
      final ayna = mapScanPoints(
        points: const [nokta],
        imageSize: goruntu,
        screenSize: ekran,
        mirrored: true,
      );

      final orta = ekran.width / 2;
      expect(duz.single.dx, lessThan(orta));
      expect(ayna.single.dx, greaterThan(orta),
          reason: 'aynalanan nokta ekran merkezinin obur tarafinda olmali');
      // Merkeze uzakliklar esit: aynalama bir kaydirma degil, yansitma.
      expect((ayna.single.dx - orta).abs(),
          closeTo((duz.single.dx - orta).abs(), 0.5));
    });

    test('dikey eksen aynalamadan ETKILENMEZ', () {
      final duz = mapScanPoints(
        points: const [Offset(120, 200)],
        imageSize: goruntu,
        screenSize: ekran,
        mirrored: false,
      );
      final ayna = mapScanPoints(
        points: const [Offset(120, 200)],
        imageSize: goruntu,
        screenSize: ekran,
        mirrored: true,
      );
      expect(ayna.single.dy, closeTo(duz.single.dy, 0.001));
    });
  });

  group('Android kare geometrisi (bu turda DEGISMEDI)', () {
    // CameraX analiz karesi yatay sensor uzayinda ve aynasiz geliyor; ML Kit
    // meta verideki aciyla diklestiriyor. Cihazda calisan hesap; bu tur ona
    // dokunmuyor.
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    final hamKare = _Kare(640, 480);

    test('on kamera: boyut ceyrek donuyor, 270 derece, noktalar aynalaniyor',
        () {
      final on = _kamera(CameraLensDirection.front, 270);
      expect(
          rotatedImageSize(
              image: hamKare, camera: on, deviceOrientationDegrees: 0),
          const Size(480, 640));
      expect(
          cameraRotationDegrees(camera: on, deviceOrientationDegrees: 0), 270);
      expect(taramaNoktalariAynalanir(CameraLensDirection.front), isTrue);
    });

    test('arka kamera: boyut ceyrek donuyor, 90 derece, aynalama yok', () {
      final arka = _kamera(CameraLensDirection.back, 90);
      expect(
          rotatedImageSize(
              image: hamKare, camera: arka, deviceOrientationDegrees: 0),
          const Size(480, 640));
      expect(
          cameraRotationDegrees(camera: arka, deviceOrientationDegrees: 0), 90);
      expect(taramaNoktalariAynalanir(CameraLensDirection.back), isFalse);
    });

    test('kamera yokken aynalama yok', () {
      expect(taramaNoktalariAynalanir(null), isFalse);
    });
  });

  group('iOS kare geometrisi (U09)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    // `camera_avfoundation` her kamerayi `sensorOrientation: 90` diye
    // bildiriyor; tampon ise zaten dik (ResolutionPreset.medium -> 480x640).
    final dikKare = _Kare(480, 640);
    final on = _kamera(CameraLensDirection.front, 90);
    final arka = _kamera(CameraLensDirection.back, 90);

    test('boyut HAM tampon boyutu — en ile boy yer degistirmiyor', () {
      for (final kamera in [on, arka]) {
        expect(
            rotatedImageSize(
                image: dikKare, camera: kamera, deviceOrientationDegrees: 0),
            const Size(480, 640),
            reason: '${kamera.lensDirection.name}: sensor 90 bildirse de '
                'tampon zaten dik; takas deklansoru hic actirmazdi');
      }
    });

    test('dondurme iki lenste de 0 — maske landmarklarla ayni uzayda', () {
      for (final kamera in [on, arka]) {
        final derece =
            cameraRotationDegrees(camera: kamera, deviceOrientationDegrees: 0);
        expect(derece, 0, reason: kamera.lensDirection.name);
        // Segmentasyon karesi ham tamponu birebir okur.
        final s = sourcePixel(
            dx: 100, dy: 300, width: 480, height: 640, degrees: derece!);
        expect((s.u, s.v), (100, 300));
      }
    });

    test('noktalar iki lenste de AYNALANMIYOR — tampon zaten aynali', () {
      expect(taramaNoktalariAynalanir(CameraLensDirection.front), isFalse);
      expect(taramaNoktalariAynalanir(CameraLensDirection.back), isFalse);
    });

    test('on kamera: tamponun sol yarisindaki nokta ekranda da SOLDA kalir',
        () {
      // Onizleme dokusu ML Kit'e verilen tamponun kendisi; ekranda nerede
      // gorunuyorsa nokta da orada olmali. Cift aynalama onu saga atardi.
      final boyut = rotatedImageSize(
          image: dikKare, camera: on, deviceOrientationDegrees: 0);
      final sonuc = mapScanPoints(
        points: const [Offset(120, 320)],
        imageSize: boyut,
        screenSize: ekran,
        mirrored: taramaNoktalariAynalanir(on.lensDirection),
      );
      expect(sonuc.single.dx, lessThan(ekran.width / 2));
    });
  });

  test('Android on kamera: ayni nokta ekranda KARSI tarafa gecer', () {
    // Karsilastirma icin: Android'de ML Kit aynasiz uzayda, onizleme aynali.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final on = _kamera(CameraLensDirection.front, 270);
    final boyut = rotatedImageSize(
        image: _Kare(640, 480), camera: on, deviceOrientationDegrees: 0);
    final sonuc = mapScanPoints(
      points: const [Offset(120, 320)],
      imageSize: boyut,
      screenSize: ekran,
      mirrored: taramaNoktalariAynalanir(on.lensDirection),
    );
    expect(sonuc.single.dx, greaterThan(ekran.width / 2));
  });
}

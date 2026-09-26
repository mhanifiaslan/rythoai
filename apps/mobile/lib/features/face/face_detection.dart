/// ML Kit ile **cihaz üstü** yüz tespiti.
///
/// Bu dosyanın tamamı cihazda çalışır ve dışarıya hiçbir şey göndermez.
/// Görüntü buradan çıkmaz; çıkan tek şey [FaceLandmarks] ve ondan türetilen
/// oranlardır.
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_geometry.dart';

/// Kontur açık bir dedektör.
///
/// `enableContours` şart: oran hesabı için yüz ovali, kaş, burun ve dudak
/// hatları gerekiyor. Yalnız `enableLandmarks` göz/burun/ağız merkezlerini
/// verir, kontur vermez — San Ting oranları çıkarılamaz.
///
/// `performanceMode: fast` bilinçli: canlı önizlemede kare başına çalışıyor
/// ve `accurate` mod telefonu ısıtacak kadar pahalı. Çekim anındaki tek
/// karede fark yaratmıyor.
FaceDetector createFaceDetector() => FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        enableClassification: false,
        enableTracking: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      ),
    );

/// Kamera karesini ML Kit'in beklediği biçime çevirir.
///
/// Platform farkı gerçek ve kaçınılmaz: Android kamerası YUV/NV21, iOS
/// BGRA8888 veriyor. Yanlış biçim verildiğinde ML Kit hata döndürmez,
/// **hiçbir yüz bulamaz** — yani kusur sessizdir ve "kamera bozuk" gibi
/// görünür.
InputImage? inputImageFromCamera({
  required CameraImage image,
  required CameraDescription camera,
  required int deviceOrientationDegrees,
}) {
  // Meta verideki açı yalnız ANDROID'de bir şey değiştirir: ML Kit'e yatay
  // sensör karesini dikleştirmesini söyleyen tek bilgi bu. iOS eklentisi onu
  // hiç okumuyor (bkz. [_kareDikVeAynali]); iOS'un geometrisi bu yüzden
  // burada değil, aşağıdaki yardımcılarda dallanıyor.
  final rotation = _rotation(camera, deviceOrientationDegrees);
  if (rotation == null) return null;

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null) return null;

  // Android'de NV21, iOS'ta BGRA8888 bekleniyor; başka bir şey gelirse
  // dönüştürmeye çalışmak yerine kareyi atlıyoruz — bozuk veriyle tespit
  // yapmaktansa o kareyi hiç işlememek doğru.
  if (format != InputImageFormat.nv21 &&
      format != InputImageFormat.bgra8888) {
    return null;
  }

  final bytes = _birlestir(image.planes);
  return InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    ),
  );
}

Uint8List _birlestir(List<Plane> planes) {
  if (planes.length == 1) return planes.first.bytes;
  final builder = BytesBuilder(copy: false);
  for (final p in planes) {
    builder.add(p.bytes);
  }
  return builder.toBytes();
}

/// Kamera akışının karesi zaten DİK ve ön kamerada zaten AYNALI mı geliyor?
///
/// iOS'ta evet, Android'de hayır — ve aşağıdaki üç yardımcının (boyut,
/// döndürme, aynalama) hepsi bu tek farka dayanıyor. Kanıt eklenti
/// kaynaklarında (sürümler `pubspec.lock`'tan):
///
/// * `camera_avfoundation` 0.9.23+2, `DefaultCamera.swift`: video çıkışının
///   bağlantısı ön kamerada `isVideoMirrored = true` ile kuruluyor ve
///   `updateOrientation()` bağlantının `videoOrientation`'ını cihaz yönüne
///   (dik tutuşta `.portrait`) çeviriyor. Akış karesi (`handleSampleBufferStreaming`)
///   ve önizleme dokusu (`copyPixelBuffer`) AYNI tampondan çıkıyor; yani
///   ekranda görülen, ML Kit'e verilenin birebir aynısı.
/// * `google_mlkit_commons` 0.11.1, `MLKVisionImage+FlutterPlugin.m`
///   `bytesToVisionImage`: meta verideki `rotation`'ı hiç okumuyor, görüntüyü
///   yönsüz kuruyor — koordinatlar HAM tampon uzayında dönüyor.
/// * `camera_avfoundation` her kamerayı `sensorOrientation: 90` diye
///   bildiriyor (`lib/src/utils.dart`, sabit). Dal olmasaydı Android hesabı
///   iOS'ta 480x640'lık dik kareyi 640x480 sanıp en ile boyu yer
///   değiştirirdi — Android'de deklanşörü hiç açtırmayan hatanın aynısı —
///   ve saç çizgisi maskesi landmark'lara göre 90° dönük kalırdı.
///
/// Android'de (CameraX) ikisi de tersi: analiz karesi yatay sensör
/// uzayında ve aynasız gelir; önizleme ise ayrıca döndürülüp aynalanarak
/// çiziliyor.
///
/// `Platform.isIOS` değil `defaultTargetPlatform`: testte değiştirilebilen
/// anahtar bu. Gerçek doğrulama yalnız cihazda (ML Kit ve TFLite
/// simülatörde yok) — denetim U09.
bool get _kareDikVeAynali => defaultTargetPlatform == TargetPlatform.iOS;

/// ML Kit'in koordinat döndürdüğü uzayın boyutu.
///
/// **Android'de ham kare boyutu bunun yerine kullanılamaz.** Kamera sensörü
/// yatay veriyor (ör. 640x480); ML Kit ise döndürme meta verisini uygulayıp
/// koordinatları DİK uzayda (480x640) döndürüyor. Ham boyutla
/// karşılaştırınca genişlik ve yükseklik yer değiştiriyor: yüz kadrajın
/// tam ortasındayken "yüzünü ortala" uyarısı çıkıyor ve deklanşör hiç
/// açılmıyordu.
///
/// iOS'ta ise tam tersine DOĞRU cevap ham boyuttur: tampon zaten dik ve ML
/// Kit onu döndürmeden okuyor (bkz. [_kareDikVeAynali]).
Size rotatedImageSize({
  required CameraImage image,
  required CameraDescription camera,
  required int deviceOrientationDegrees,
}) {
  if (_kareDikVeAynali) {
    return Size(image.width.toDouble(), image.height.toDouble());
  }
  final rotation = _rotation(camera, deviceOrientationDegrees);
  final ceyrek = rotation == InputImageRotation.rotation90deg ||
      rotation == InputImageRotation.rotation270deg;
  return ceyrek
      ? Size(image.height.toDouble(), image.width.toDouble())
      : Size(image.width.toDouble(), image.height.toDouble());
}

/// ML Kit'in koordinat uzayına varmak için ham kareye uygulanan döndürme —
/// derece cinsinden.
///
/// Segmentasyon karesi de aynı döndürmeden geçmeli, yoksa saç çizgisi
/// maskesi ile landmark'lar ayrı uzaylarda kalır (bkz.
/// `face_segmentation.dart`, `FaceSegmenter.run`). iOS'ta 0: ML Kit ham
/// tamponu döndürmeden okuyor, maske de öyle okunmalı.
int? cameraRotationDegrees({
  required CameraDescription camera,
  required int deviceOrientationDegrees,
}) {
  if (_kareDikVeAynali) return 0;
  final r = _rotation(camera, deviceOrientationDegrees);
  return switch (r) {
    InputImageRotation.rotation0deg => 0,
    InputImageRotation.rotation90deg => 90,
    InputImageRotation.rotation180deg => 180,
    InputImageRotation.rotation270deg => 270,
    null => null,
  };
}

InputImageRotation? _rotation(CameraDescription camera, int deviceDegrees) {
  // Ön kamera aynalandığı için sensör açısı ters yönde toplanır; bu
  // atlanırsa yüz bulunur ama noktalar yatay olarak yanlış yere düşer.
  final aci = camera.lensDirection == CameraLensDirection.front
      ? (camera.sensorOrientation + deviceDegrees) % 360
      : (camera.sensorOrientation - deviceDegrees + 360) % 360;
  return InputImageRotationValue.fromRawValue(aci);
}

/// Tarama noktaları ekrana taşınırken yatayda aynalanmalı mı?
///
/// Ön kamera önizlemesi iki platformda da ayna gibi görünüyor; fark ML Kit
/// koordinatlarında. Android'de koordinatlar aynasız sensör uzayında
/// geliyor ve aynalanmazsa noktalar yüzün yanına düşüyor (cihazda
/// "noktalar yüzümün solunda" diye görüldü). iOS'ta ML Kit zaten aynalı
/// tamponu görüyor: bir kez daha aynalamak noktaları ikinci kez çevirip
/// yüzün öbür yanına atardı (bkz. [_kareDikVeAynali]).
///
/// Kadraj kılavuzu bundan etkilenmiyor — merkeze uzaklık aynalamada
/// değişmez — yani bu kusur kılavuz kusursuz çalışırken bile sessiz kalır.
bool taramaNoktalariAynalanir(CameraLensDirection? yon) =>
    !_kareDikVeAynali && yon == CameraLensDirection.front;

/// ML Kit yüzünden [FaceLandmarks] çıkarır.
///
/// Kontur eksikse `null` döner: eksik noktayla oran hesaplamak, uydurulmuş
/// bir ölçüm üretmek olur.
FaceLandmarks? landmarksFromFace(Face face) {
  final oval = face.contours[FaceContourType.face]?.points;
  if (oval == null || oval.length < 12) return null;

  Offset? nokta(FaceContourType tur, [int? indeks]) {
    final p = face.contours[tur]?.points;
    if (p == null || p.isEmpty) return null;
    final i = indeks ?? p.length ~/ 2;
    if (i >= p.length) return null;
    return Offset(p[i].x.toDouble(), p[i].y.toDouble());
  }

  Offset? isaret(FaceLandmarkType tur) {
    final l = face.landmarks[tur];
    return l == null ? null : Offset(l.position.x.toDouble(), l.position.y.toDouble());
  }

  final ovalNoktalar = [
    for (final p in oval) Offset(p.x.toDouble(), p.y.toDouble()),
  ];

  // Yüz ovali saat yönünde sıralı gelir; en üst ve en alt nokta alın ve çene.
  final enUst = ovalNoktalar.reduce((a, b) => a.dy < b.dy ? a : b);
  final enAlt = ovalNoktalar.reduce((a, b) => a.dy > b.dy ? a : b);
  final enSol = ovalNoktalar.reduce((a, b) => a.dx < b.dx ? a : b);
  final enSag = ovalNoktalar.reduce((a, b) => a.dx > b.dx ? a : b);

  // Kaş sınırı için ÜST kenar değil kaşın ORTA hattı kullanılıyor.
  //
  // Klasik San Ting üst bölgeyi "saç çizgisi -> kaş" diye tanımlıyor ve
  // kastettiği şey kaşın kendisi. Yalnızca üst kenarı almak sınırı kaş
  // kalınlığı kadar yukarı kaydiriyor; bu, üst bölgeyi küçültüp orta bölgeyi
  // büyüten SISTEMATIK bir sapma. Cihazda ölçülen üst bölge sekiz ölçümde
  // 0,25-0,27 arasında oturdu (klasik ~0,33) ve bu sapma o farkın bir
  // parçası.
  //
  // Alt kenar bulunamazsa üst kenara düşülüyor: ölçüm yapmamaktansa bilinen
  // sapmayla yapmak yeğ.
  Offset? kasOrta(FaceContourType ust, FaceContourType alt) {
    final u = nokta(ust);
    if (u == null) return null;
    final a = nokta(alt);
    if (a == null) return u;
    return Offset((u.dx + a.dx) / 2, (u.dy + a.dy) / 2);
  }

  final solKas = kasOrta(
      FaceContourType.leftEyebrowTop, FaceContourType.leftEyebrowBottom);
  final sagKas = kasOrta(
      FaceContourType.rightEyebrowTop, FaceContourType.rightEyebrowBottom);
  final burunAlt = nokta(FaceContourType.noseBottom);
  final ustDudak = nokta(FaceContourType.upperLipTop);
  final altDudak = nokta(FaceContourType.lowerLipBottom);
  final agizSol = isaret(FaceLandmarkType.leftMouth);
  final agizSag = isaret(FaceLandmarkType.rightMouth);
  final gozSol = isaret(FaceLandmarkType.leftEye);
  final gozSag = isaret(FaceLandmarkType.rightEye);

  if (solKas == null ||
      sagKas == null ||
      burunAlt == null ||
      ustDudak == null ||
      altDudak == null ||
      agizSol == null ||
      agizSag == null ||
      gozSol == null ||
      gozSag == null) {
    return null;
  }

  // Çene genişliği: ovalin alt üçte birindeki en geniş yer.
  final altBolge = ovalNoktalar
      .where((p) => p.dy > enUst.dy + (enAlt.dy - enUst.dy) * 0.66)
      .toList();
  final ceneSol = altBolge.isEmpty
      ? enSol
      : altBolge.reduce((a, b) => a.dx < b.dx ? a : b);
  final ceneSag = altBolge.isEmpty
      ? enSag
      : altBolge.reduce((a, b) => a.dx > b.dx ? a : b);

  return FaceLandmarks(
    faceOval: ovalNoktalar,
    foreheadTop: enUst,
    browMid: Offset((solKas.dx + sagKas.dx) / 2, (solKas.dy + sagKas.dy) / 2),
    noseBase: burunAlt,
    chin: enAlt,
    cheekLeft: enSol,
    cheekRight: enSag,
    jawLeft: ceneSol,
    jawRight: ceneSag,
    mouthLeft: agizSol,
    mouthRight: agizSag,
    upperLip: ustDudak,
    lowerLip: altDudak,
    eyeLeft: gozSol,
    eyeRight: gozSag,
    headAngleZ: face.headEulerAngleZ ?? 0,
    headAngleY: face.headEulerAngleY ?? 0,
  );
}

/// Hareket ölçümüne girecek noktalar — kare kare aynı sırada.
///
/// **Göz konturu bilerek yok.** Göz kırpması landmark'ları çok büyük bir
/// mesafe oynatıyor ve ölçüm tamamen kırpma sıklığına iniyor; oysa aranan
/// şey ifadenin genel canlılığı.
///
/// Herhangi bir kontur eksikse `null` döner: nokta sayısı kareden kareye
/// değişirse karşılaştırma anlamsız olur.
List<Offset>? motionPoints(Face face) {
  final parcalar = <Offset>[];
  for (final tur in const [
    FaceContourType.leftEyebrowTop,
    FaceContourType.rightEyebrowTop,
    FaceContourType.upperLipTop,
    FaceContourType.lowerLipBottom,
    FaceContourType.face,
  ]) {
    final p = face.contours[tur]?.points;
    if (p == null || p.isEmpty) return null;
    for (final nokta in p) {
      parcalar.add(Offset(nokta.x.toDouble(), nokta.y.toDouble()));
    }
  }
  return parcalar;
}

/// Animasyonda çizilecek nokta kümesi — **kontur kontur ayrılmış.**
///
/// Tüm kontur noktalarını çizmek (yüzlerce) ağ değil leke veriyor; ovalden
/// seyreltilmiş bir alt küme + iç hatların anahtar noktaları hem okunur hem
/// "tarandı" hissini veriyor.
///
/// Dönüş tipi düz liste DEĞİL, çünkü ağ çizgileri yalnızca **aynı kontur
/// içinde** anlamlı. Tek listede birleştirilince kaşın sonundan gözün başına
/// çizgi çekiliyordu ve sınırlar rastgele görünüyordu. Bir ara bunu
/// noktalar arası uzaklığa bakarak ayıklamayı denedim — sezgiydi ve bazı
/// yüzlerde tutmuyordu. Hangi noktanın hangi hatta ait olduğu zaten belli;
/// tahmin etmeye gerek yok.
List<List<Offset>> scanNodes(Face face) {
  final hatlar = <List<Offset>>[];

  void ekle(FaceContourType tur, int adim) {
    final p = face.contours[tur]?.points;
    if (p == null || p.isEmpty) return;
    final hat = <Offset>[];
    for (var i = 0; i < p.length; i += adim) {
      hat.add(Offset(p[i].x.toDouble(), p[i].y.toDouble()));
    }
    if (hat.isNotEmpty) hatlar.add(hat);
  }

  ekle(FaceContourType.face, 2);
  ekle(FaceContourType.leftEyebrowTop, 2);
  ekle(FaceContourType.rightEyebrowTop, 2);
  ekle(FaceContourType.leftEye, 3);
  ekle(FaceContourType.rightEye, 3);
  ekle(FaceContourType.noseBridge, 1);
  ekle(FaceContourType.noseBottom, 2);
  ekle(FaceContourType.upperLipTop, 2);
  ekle(FaceContourType.lowerLipBottom, 2);

  return hatlar;
}

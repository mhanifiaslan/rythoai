/// Yüz okuma çekim ekranı — kılavuz, tespit ve sinematik tarama.
///
/// Akış: canlı önizleme → çerçeveleme kılavuzu → deklanşör yalnızca kadraj
/// hazırken etkin → tarama animasyonu → oranlar.
///
/// **Görüntü bu ekrandan çıkmaz — artık diske de değmiyor.** Önceki sürüm
/// deklanşöre basınca `takePicture()` çağırıyor, geçici bir dosya yazıyor,
/// onu ML Kit'e verip siliyordu. O dosya artık hiç oluşmuyor: ölçüm canlı
/// akışın son karesinden yapılıyor. Kare bellekte işleniyor, oranlar
/// çıkarılıyor ve kare atılıyor.
///
/// Yan fayda ilk baştaki asıl amaçtan çıktı: fotoğrafın koordinat uzayı
/// önizlemeninkinden farklı olduğu için tarama noktaları yüzün üstüne değil
/// başka bir yere düşüyordu. Tek uzay kullanmak hem doğru hem daha mahrem.
library;

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:app_settings/app_settings.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart' show AstrolabeSpinner;
import '../../widgets/motion.dart' show reduceMotion;
import 'face_detection.dart';
import 'face_geometry.dart';
import 'face_hairline.dart';
import 'face_motion.dart';
import 'face_segmentation.dart';
import 'face_scan_overlay.dart';
import 'face_still.dart';
import 'hairline_stabilizer.dart';

/// Çekim sonucu: durağan oranlar + hareket ölçümü.
///
/// İkisi iki ayrı ekseni besliyor. Oranlar kuru–nemli eksenini, hareket
/// sıcak–soğuk eksenini açıyor; gelenekte mizaç bu ikisinin kesişimi.
class FaceCaptureResult {
  const FaceCaptureResult(this.ratios, this.motion, {this.singleFrame = false});

  final FaceRatios ratios;
  final MotionMetrics motion;

  /// Ölçüm tek kareden mi (galeri fotoğrafı)?
  ///
  /// Kamera yolunda saç çizgisi 3+ örneğin medyanından geliyor; fotoğrafta
  /// tek örnek var. Okuma ekranı bunu kullanıcıya SÖYLÜYOR — söylemeden
  /// kabul etmek, kararlılık katmanının çözdüğü sorunu (ardışık çelişen
  /// okumalar) galeri yolundan sessizce geri getirmek olurdu.
  final bool singleFrame;

  /// Sunucuya giden yük. İkisi de yalnızca sayı.
  Map<String, double> toJson() => {
        ...ratios.toJson(),
        // Ölçüm güvenilir değilse hareket alanları HİÇ gönderilmez.
        // Sunucu "alan yoksa ölçemedim" diye okuyor; sıfır göndermek
        // "ölçtüm ve sıfır çıktı" demek olurdu ve bu yalan olurdu.
        if (motion.confident) ...motion.toJson(),
      };
}

/// Kamera kurulum hatasının kodu kullanıcının İZİN REDDİ mi?
///
/// İzin reddi ARIZA DEĞİL: Crashlytics'e yazılmaz ve ekran "yüz algılama
/// başarısız" yerine izin katmanını gösterir.
///
/// iOS kodları `Permission` içermiyor (`camera_avfoundation` 0.9.23+2,
/// `CameraPermissionManager.swift`): diyalogdaki ret `CameraAccessDenied`,
/// sonraki her deneme diyalogsuz `CameraAccessDeniedWithoutPrompt`,
/// ebeveyn/MDM kısıtı `CameraAccessRestricted`. Yalnız `Permission`'a
/// bakılırken iOS'ta ret donanım arızası sayılıyordu: "Yeniden çek" sonsuza
/// dek aynı hataya dönüyor ve her deneme Crashlytics'e sahte bir kayıt
/// yazıyordu (U23).
///
/// `CameraAccess` öneki bilerek YALNIZ iOS'ta. Android'in ret kodu da
/// `CameraAccessDenied` (`camera_android_camerax` 0.6.30,
/// `CameraPermissionsManager.java`) ama izin katmanı `resumed`'da
/// kendiliğinden yeniden deniyor ve Android ilk retten sonra izni yeniden
/// SORABİLİYOR (platform kuralı: 11+'da bir kez daha, 7–10'da "Bir daha
/// sorma" işaretlenene dek): ret orada izin katmanına düşseydi, diyalog
/// kapanınca gelen `resumed` diyaloğu yeniden açabilirdi. iOS'ta bu döngü
/// kurulamaz — ikinci deneme diyalogsuz düşer, `resumed` üretmez. Android
/// sınıflandırması cihazda ölçülmeden değiştirilmedi; bugün Android reddi
/// ARIZA sayılıyor ve Crashlytics'e yazılıyor — açık kalem
/// `docs/test-raporu.md` B11.
bool kameraIzniReddi(String kod) =>
    kod.contains('Permission') ||
    (defaultTargetPlatform == TargetPlatform.iOS &&
        kod.startsWith('CameraAccess'));

class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({super.key});

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

enum _Asama { hazirlaniyor, izinYok, onizleme, tarama, hata }

class _FaceCaptureScreenState extends State<FaceCaptureScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _kamera;
  late final FaceDetector _dedektor = createFaceDetector();

  _Asama _asama = _Asama.hazirlaniyor;
  FrameQuality _kalite = FrameQuality.noFace;

  /// Kilit birikimi: yüz üst üste kaç karedir hazır konumda.
  ///
  /// Tek karelik "hazır" ile deklanşörü açmak, kullanıcı daha yerleşmeden
  /// tetikleniyor ve kadraj bulanık çıkıyordu. Kilidin dolması ~0.5 sn sürüyor.
  double _kilit = 0;

  /// Aynı anda iki kare işlemeyi engeller. ML Kit çağrısı ~30-80 ms;
  /// kilit olmadan kuyruk birikiyor ve önizleme donuyor.
  bool _isliyor = false;

  /// Kılavuz halkasının nefesi. Döngü BURADA başlatılmaz — kapı
  /// [_nabziKapila]'da: sistem "animasyonları azalt" diyorsa halka tek
  /// karede durur (eski hâl kapısız sonsuz döngüydü, §2 hareket disiplini).
  late final AnimationController _nabiz = AnimationController(
    vsync: this,
    duration: RythoMotion.breath,
  );

  late final AnimationController _tarama = AnimationController(
    vsync: this,
    duration: ScanTiming.total,
  );

  List<List<Offset>> _noktalar = const [];
  Size _goruntuBoyutu = Size.zero;

  /// Kılavuzun çizildiği alanın ölçüsü.
  ///
  /// Kalite kontrolü bunu bilmek zorunda: oval ekran uzayında çiziliyor, yüz
  /// kutusu görüntü uzayında geliyor ve ikisi arasındaki dönüşüm ekran
  /// oranına bağlı (`BoxFit.cover`). Ölçü `LayoutBuilder`'dan alınıyor —
  /// `MediaQuery` pencerenin tamamını verir, boyanan alanı değil.
  Size? _ekranBoyutu;

  /// Kalibrasyon okuması — yalnızca hata ayıklama derlemesinde görünür.
  String? _olcum;

  /// Üç bölge oranı — okumanın dayandığı asıl sayılar (hata ayıklama).
  String? _bolgeler;

  /// Akıştan gelen SON geçerli tespit ve ait olduğu görüntünün boyutu.
  ///
  /// Çekim anında kullanılan şey bu. Ayrı bir fotoğraf çekmek, koordinatları
  /// başka bir uzaya taşıyıp noktaların yanlış yere düşmesine yol açıyordu.
  Face? _sonYuz;
  Size _sonBoyut = Size.zero;

  /// Segmentasyon modeli — saç/yüz teni ayrımı (bkz. face_segmentation.dart).
  final FaceSegmenter _segmenter = FaceSegmenter();

  /// Model ölçümünün cihazdaki süresi ve gördüğü sınıflar (hata ayıklama).
  String? _segOlcum;

  /// Segmentasyon arizasi bu ekran oturumunda bildirildi mi?
  ///
  /// Maske 700 ms'de bir uretiliyor; her dususu bildirmek Crashlytics'i
  /// kullanissiz hale getirirdi. Bir kez yeter: sebep (`lastError`) zaten
  /// ayni.
  bool _segArizaBildirildi = false;

  /// Kadraj hazırken yakalanan son ham kare — çekim anında segmentasyon için.
  CameraImage? _sonKare;

  /// Son üretilen sınıf maskesi — saç çizgisi buradan çıkıyor.
  SegmentationMask? _sonMaske;

  /// Önizleme ölçümünün son anı.
  DateTime? _sonSegAni;

  /// Önizlemede iki ölçüm arası en az bu kadar beklenir.
  ///
  /// Kamera saniyede onlarca kare üretiyor; her karede ölçmek işçiyi sürekli
  /// meşgul tutar, pili ısıtır ve hiçbir şey kazandırmaz — saç çizgisi kare
  /// kare değişen bir şey değil. Yarım saniyeden kısa aralık kullanıcının
  /// kadrajı düzeltmesini takip etmeye zaten yeter.
  static const Duration _segAraligi = Duration(milliseconds: 700);

  bool _segSirasiGeldi() {
    final son = _sonSegAni;
    if (son != null &&
        DateTime.now().difference(son) < _segAraligi) {
      return false;
    }
    _sonSegAni = DateTime.now();
    return true;
  }

  /// Saç çizgisi ölçümünün sonucu (hata ayıklama).
  String? _sacTuru;

  /// Saç çizgisini tek kareye bırakmayan kararlılık katmanı.
  final HairlineStabilizer _kararlilik = HairlineStabilizer();

  /// Son geçerli tek kare ölçümünün türü ve güveni.
  ///
  /// Medyan yalnızca KONUMU kararlı hâle getiriyor; "saç sınırı mı, kafatası
  /// tepesi mi" bilgisi ölçümün kendisinden geliyor ve okuma bunu söylemek
  /// zorunda (kel bir kafada klasik San Ting olduğu gibi geçerli değil).
  HairlineKind? _sonSacTuru;
  double? _sonSacGuveni;

  /// Son tek kare ölçümünün başarısızlık sebebi (hata ayıklama).
  String? _sonSacHatasi;

  /// Alın örtülü uyarısı gösteriliyor mu.
  ///
  /// Kullanıcı kadrajı düzeltince kendiliğinden kalkıyor: uyarının kalıcı
  /// olması, düzeltildiğini fark etmeyen bir ekran demek olurdu.
  bool _alinUyarisi = false;

  /// Hareket ölçümü önizleme boyunca birikiyor.
  ///
  /// Kullanıcı deklanşör için bilerek sabit duruyor; hareket çabukluğunu
  /// kıpırdamamaya çalışan birinde ölçmek yanlış şeyi ölçer. Bu yüzden
  /// serbest evre (kadrajı ararken) ve kilit evresi (istemsiz mikro hareket)
  /// ayrı toplanıyor.
  final MotionTracker _hareket = MotionTracker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Yorumlayıcı yüklemesi pahalı; kamera açılırken bir kez yapılıyor.
    // Sonuc YUTULMAZ (gz-10): yukleme duserse `ready` false kalir ve
    // `_segmentle()` daha ilk satirda doner — asagidaki maske==null kancasi
    // bu arizayi HIC goremez. Sahada en olasi ariza da bu ve sebebi
    // `lastError`'da duruyor; tek cikisi burasi.
    unawaited(_segmenter.load().then((yuklendi) {
      if (!yuklendi) {
        _arizaBildir(StateError('segmenter yuklenemedi'), StackTrace.current,
            'segmenter-yukleme');
      }
    }));
    _baslat();
  }

  /// Kullanıcı izin diyaloğundan dönünce **kendiliğinden** yeniden dener.
  ///
  /// Android'de izin diyaloğu açılırken ilk `initialize()` çağrısı
  /// başarısız oluyor. İlk sürümde o hata kalıcı duruma yazılıyordu ve
  /// kullanıcı izni VERDİĞİ hâlde ekranda "kamera izni verilmedi" yazısı
  /// kalıyordu — üstelik oradan çıkış da yoktu. Diyalog kapanınca uygulama
  /// `resumed` durumuna dönüyor; tekrar denemek için doğru an bu.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _asama == _Asama.izinYok) {
      _yenidenDene();
    }
  }

  /// `reduceMotion` context ister; `initState`te okunamaz, bağımlılık
  /// değişince (tercih anlık değişebilir) yeniden sorulur.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nabziKapila();
  }

  void _nabziKapila() {
    if (reduceMotion(context)) {
      _nabiz.stop();
    } else if (!_nabiz.isAnimating) {
      _nabiz.repeat();
    }
  }

  void _yenidenDene() {
    setState(() {
      _asama = _Asama.hazirlaniyor;
      _kilit = 0;
      _noktalar = const [];
    });
    _hareket.reset();
    _baslat();
  }

  /// Seçili lens yönü. Varsayılan ön: insan kendi yüzünü tarıyor. Arka
  /// kamera bilinçli bir ek (Revize R5): hem daha kaliteli sensör hem
  /// "başkasının yüzünü okuma" akışı — rıza metni her iki yol için de aynı
  /// kapıdan geçiyor.
  CameraLensDirection _yon = CameraLensDirection.front;

  /// Cihazda birden fazla lens yönü var mı — yoksa çevirme düğmesi çizilmez.
  bool _ciftLens = false;

  /// Galeri fotoğrafı işleniyor; önizleme ölçümleri duraklatılır.
  bool _galeriIsleniyor = false;

  Future<void> _baslat() async {
    try {
      final kameralar = await availableCameras();
      _ciftLens = kameralar
              .map((c) => c.lensDirection)
              .toSet()
              .intersection({CameraLensDirection.front, CameraLensDirection.back})
              .length ==
          2;
      final on = kameralar.firstWhere(
        (c) => c.lensDirection == _yon,
        orElse: () => kameralar.first,
      );

      // Yüksek çözünürlük gerekmiyor: oranlar ölçek bağımsız ve düşük
      // çözünürlük hem tespiti hızlandırıyor hem telefonu ısıtmıyor.
      final kontrolcu = CameraController(
        on,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await kontrolcu.initialize();
      if (!mounted) return;

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _iosKareyiDikKilitle(kontrolcu);
        if (!mounted) return;
      }

      _kamera = kontrolcu;
      await kontrolcu.startImageStream(_kareGeldi);
      if (!mounted) return;
      setState(() => _asama = _Asama.onizleme);
    } on CameraException catch (e, iz) {
      // Izin reddi ARIZA DEGIL — kullanicinin karari; yalniz gercek ariza
      // bildirilir. Bildirim `mounted` kontrolunden ONCE: ekran sokulmusse de
      // sebep kaybolmasin. Iki kosul AYNI yuklemi kullanir: ayrisirlarsa
      // ret ya izin ekraninda Crashlytics'e yazilir ya da ariza ekraninda
      // sessiz kalir.
      final izinReddi = kameraIzniReddi(e.code);
      if (!izinReddi) {
        _arizaBildir(e, iz, 'kamera-kurulum');
      }
      if (!mounted) return;
      setState(() => _asama = izinReddi ? _Asama.izinYok : _Asama.hata);
    } catch (e, iz) {
      _arizaBildir(e, iz, 'kamera-kurulum');
      if (!mounted) return;
      setState(() => _asama = _Asama.hata);
    }
  }

  /// iOS'ta akış karesini arayüzle aynı yönde — DİK — tutar.
  ///
  /// `camera_avfoundation` 0.9.23+2 kareyi FİZİKSEL cihaz yönüne göre
  /// çeviriyor (`UIDevice.orientationDidChangeNotification` →
  /// `videoOrientation`, arayüz kilidine bakmadan); arayüz ise yalnız dikey
  /// (Info.plist). Kilit olmasa telefon yan tutulunca tampon yataya döner,
  /// önizleme dokusu (aynı tampon) dikey kutuya sığdırılırken bükülür ve
  /// tarama noktaları ekranda gösterilen kareyle örtüşmezdi. Kilitle
  /// tampon, önizleme ve noktalar hep aynı dikey uzayda kalır — Android'le
  /// aynı varsayım (orada cihaz açısı sabit 0 veriliyor).
  ///
  /// Kilit düşerse akış DURMAZ: dik tutulan telefonda geometri kilitsiz de
  /// doğru (bkz. face_detection.dart, `_kareDikVeAynali`). Yine de sebep
  /// bildirilir; yan tutuşta bozulan bir ekranın izi kalmalı.
  Future<void> _iosKareyiDikKilitle(CameraController kontrolcu) async {
    try {
      await kontrolcu.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } on CameraException catch (e, iz) {
      _arizaBildir(e, iz, 'kamera-yon-kilidi');
    }
  }

  /// Ariza sebebini CIHAZDAN alir (gz-10).
  ///
  /// Segmenter sebebi zaten tutuyor (`lastError`, bkz. face_segmentation.dart)
  /// ama o deger yalniz `assert` icinde okunuyordu: yayin derlemesinde hicbir
  /// yere gitmiyordu. "Yuz okuma calismiyor" dendiginde model mi yuklenemedi,
  /// kare bicimi mi taninmadi, cikarim mi dustu — ayiran tek sey bu
  /// anahtarlar. Logcat secenek degil (cihaz log'u suzuluyor).
  void _arizaBildir(Object hata, StackTrace iz, String nerede) {
    if (kDebugMode) {
      debugPrint('RYTHO-FACE ariza [$nerede] $hata — '
          'seg=${_segmenter.lastError} sac=$_sonSacHatasi');
      return;
    }
    final crash = FirebaseCrashlytics.instance;
    crash.setCustomKey('face_asama', nerede);
    crash.setCustomKey('face_seg_hata', _segmenter.lastError ?? '-');
    crash.setCustomKey('face_seg_sure', _segmenter.lastTimings ?? '-');
    crash.setCustomKey('face_sac_hata', _sonSacHatasi ?? '-');
    crash.recordError(hata, iz, reason: 'face-capture', fatal: false);
  }

  Future<void> _kareGeldi(CameraImage kare) async {
    // Galeri analizi sürerken kareler işlenmez: dedektör ve segmenter tek;
    // ikisini aynı anda hem akışa hem fotoğrafa koşturmak yarış üretir.
    if (_isliyor || _galeriIsleniyor || _asama != _Asama.onizleme) return;
    _isliyor = true;
    try {
      final kamera = _kamera;
      if (kamera == null) return;

      final girdi = inputImageFromCamera(
        image: kare,
        camera: kamera.description,
        deviceOrientationDegrees: 0,
      );
      if (girdi == null) return;

      final yuzler = await _dedektor.processImage(girdi);
      if (!mounted) return;

      final yuz = yuzler.isEmpty ? null : yuzler.first;
      // Boyut ML Kit'in koordinat DÖNDÜRDÜĞÜ uzayda olmalı; ham kare boyutu
      // yatay geliyor ve karşılaştırmada genişlik/yükseklik yer değiştiriyor.
      final goruntuBoyutu = rotatedImageSize(
        image: kare,
        camera: kamera.description,
        deviceOrientationDegrees: 0,
      );

      // Çekim anında kullanılacak kare. Ayrı bir fotoğraf çekmek yerine
      // AKIŞIN kendisini saklıyoruz: koordinatlar zaten doğru uzayda.
      _sonYuz = yuz;
      _sonBoyut = goruntuBoyutu;

      // Ekran ölçüsü de veriliyor: kılavuz ovali ekran uzayında çiziliyor,
      // yüz kutusu görüntü uzayında geliyor ve önizleme `BoxFit.cover` ile
      // kırpılıyor. Ekran ölçüsü olmadan hedefin gerçek boyutu bilinemez.
      final kalite = assessFrame(
        faceBox: yuz?.boundingBox,
        previewSize: goruntuBoyutu,
        screenSize: _ekranBoyutu,
        headAngleZ: yuz?.headEulerAngleZ ?? 0,
        wasReady: _kalite == FrameQuality.ready,
      );

      // Kadraj hazırken son kareyi tut: çekim anında segmentasyon buna
      // uygulanacak. `kalite` yukarıda hesaplandığı için atama BURADA.
      if (kalite == FrameQuality.ready) _sonKare = kare;

      // Segmentasyon önizlemede de koşuyor — ama SEYREK.
      //
      // Bir dönem yalnızca çekim anında koşuyordu ve gerekçesi geçerliydi:
      // ölçüm ana isolate'ta 594 ms sürüyor, arayüz o süre boyunca donuyordu.
      // O gerekçe artık yok — çıkarım işçi isolate'ta ve ana iş parçacığı
      // hiç bloklanmıyor (bkz. face_segmentation.dart).
      //
      // Geri getirilmesinin sebebi kozmetik değil: alın ölçülemiyorsa
      // kullanıcı bunu ÇEKTİKTEN SONRA değil, ÖNCE bilmeli. Aksi hâlde poz
      // verip deklanşöre basıyor ve okumanın yarısının eksik olduğunu en
      // sonda öğreniyor.
      //
      // Ayrıca ölçülen oranların cihazda görünmesinin tek yolu bu: çekim
      // anındaki ölçüm yalnızca log'a yazılıyordu ve ekran hemen sonuç
      // sayfasına geçtiği için hiç görünmüyordu.
      if (yuz != null &&
          kalite != FrameQuality.noFace &&
          _segmenter.ready &&
          _segSirasiGeldi()) {
        // `await` YOK: kare geri çağrısını bekletmek akışı geriletir.
        // `FaceSegmenter` zaten üst üste binen istekleri kendisi eliyor.
        unawaited(_segmentle());
      }

      // Hareket ölçümü: yalnızca yüz çerçevedeyken anlamlı. Yüz yokken
      // ölçmek, tespit gürültüsünü ifade sanmak olurdu.
      if (yuz != null && kalite != FrameQuality.noFace) {
        final noktalar = motionPoints(yuz);
        if (noktalar != null) {
          _hareket.addFrame(
            points: noktalar,
            faceWidth: yuz.boundingBox.width,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            locked: _kilit >= 1.0,
          );
        }
      }

      if (kDebugMode) {
        // Kalibrasyon okuması — yalnızca hata ayıklama derlemesinde.
        // Eşikler ilk sürümde tahminle konmuştu ve tutmadı; bir daha tahmin
        // etmemek için ölçülen değer cihazda görünür olmalı.
        //
        // Üç bölge (San Ting) de burada: okumanın DAYANDIĞI sayılar bunlar.
        // Kullanıcı "alnım dar değil" dediğinde tartışılacak şey yorum değil,
        // bu üç sayı.
        final lm = yuz == null ? null : _olcumlu(yuz);
        _bolgeler = lm == null
            ? null
            : () {
                final r = computeRatios(lm);
                // Başarısızlıkta SEBEP de yazılıyor. "ÖLÇÜLEMEDİ" tek başına
                // teşhis değil: tek kare ölçümü mü düştü, örnek mi yetmedi,
                // yoksa dağılım mı geniş? Üçü ayrı sorun.
                if (!r.foreheadMeasured) {
                  return 'ÖLÇÜLEMEDİ — ${_sonSacHatasi ?? _kararlilik.debugLabel}';
                }
                return 'üst ${r.upperThird.toStringAsFixed(2)}  '
                    'orta ${r.middleThird.toStringAsFixed(2)}  '
                    'alt ${r.lowerThird.toStringAsFixed(2)}'
                    '  · ${_kararlilik.debugLabel}';
              }();
        final hedef = guideOvalInImage(
          previewSize: rotatedImageSize(
            image: kare,
            camera: kamera.description,
            deviceOrientationDegrees: 0,
          ),
          screenSize: _ekranBoyutu,
        );
        _olcum = (yuz == null || hedef.height < 1)
            ? null
            : 'doluluk ${(yuz.boundingBox.height / hedef.height).toStringAsFixed(2)}'
                ' · sapma ${((yuz.boundingBox.center - hedef.center).distance / hedef.height).toStringAsFixed(2)}';
      }

      // Kilit birikimi: hazır kaldıkça dolar, bozulunca boşalır.
      //
      // Çürüme eskiden -0.35'ti; kazanç +0.14 olduğu için TEK kötü kare iki
      // buçuk iyi kareyi siliyordu. Tespit gürültüsü kural, istisna değil:
      // halka doluyor, bir karede sıfırlanıyor ve kullanıcı "yeşilde sabit
      // tutamıyorum" diyordu. Artık kayıp kazançtan yavaş.
      final yeniKilit = kalite == FrameQuality.ready
          ? (_kilit + 0.14).clamp(0.0, 1.0)
          : (_kilit - 0.10).clamp(0.0, 1.0);

      if (kalite != _kalite || (yeniKilit - _kilit).abs() > 0.01) {
        setState(() {
          _kalite = kalite;
          _kilit = yeniKilit;
          // Kullanıcı yeniden kadraja girdiğinde uyarı kalkar.
          if (kalite != FrameQuality.ready) _alinUyarisi = false;
        });
      }
    } catch (_) {
      // Tek bir bozuk kare akışı düşürmemeli; sonraki kare denenir.
    } finally {
      _isliyor = false;
    }
  }

  /// Çekim anında bir kez segmentasyon çalıştırır.
  ///
  /// Süre `RYTHO-SEG` etiketiyle loglanıyor: ölçümü kullanıcıdan istemek
  /// yerine doğrudan cihazdan almak, hem hızlı hem yanılmasız.
  Future<void> _segmentle() async {
    final kare = _sonKare;
    final kamera = _kamera;
    if (kare == null || kamera == null || !_segmenter.ready) return;

    final bas = DateTime.now();
    final maske = await _segmenter.run(
      image: kare,
      camera: kamera.description,
      deviceOrientationDegrees: 0,
    );
    final gecen = DateTime.now().difference(bas).inMilliseconds;
    _sonMaske = maske;

    // Kararlılık örneği BURADA toplanıyor — maske üretildiği anda, 700 ms'de
    // bir, her iki derlemede de. Okuma yolunda toplamak iki kusur üretmişti:
    // sürüm derlemesinde örnek hiç birikmiyordu ve teşhis okuması durumu
    // değiştiriyordu.
    _ornekAl(maske);

    // Segmentasyon HIC istisna firlatmadan dusebiliyor (kare bicimi
    // taninmadi, cikarim zaman asimi) ve o zaman kullanici yalniz
    // "OLCULEMEDI" goruyordu; sebep `lastError`'da duruyor ama hicbir yere
    // gitmiyordu (gz-10). Ekran oturumu basina bir kez bildirilir.
    if (maske == null && !_segArizaBildirildi) {
      _segArizaBildirildi = true;
      _arizaBildir(StateError('segmentasyon uretilemedi'), StackTrace.current,
          'segmentasyon');
    }

    assert(() {
      if (maske == null) {
        debugPrint('RYTHO-SEG basarisiz ${gecen}ms — ${_segmenter.lastError}');
      } else {
        var sac = 0;
        var ten = 0;
        var arka = 0;
        for (final c in maske.classes) {
          if (c == SegClass.hair) sac++;
          if (c == SegClass.faceSkin) ten++;
          if (c == SegClass.background) arka++;
        }
        final n = maske.classes.length;
        debugPrint('RYTHO-SEG ${gecen}ms sac=${(100 * sac / n).round()}% '
            'ten=${(100 * ten / n).round()}% arka=${(100 * arka / n).round()}%');
      }
      _segOlcum = maske == null
          ? 'seg başarısız: ${_segmenter.lastError}'
          : 'seg ${gecen}ms · ${_segmenter.lastTimings}';
      return true;
    }());
  }

  /// Yeni maskeden tek kare saç çizgisi ölçüp kararlılık penceresine ekler.
  ///
  /// Başarısızlığın SEBEBİ saklanıyor. "ÖLÇÜLEMEDİ" tek başına hiçbir şey
  /// söylemiyor: tek kare ölçümü mü düştü, yoksa ölçüm var da dağılım mı
  /// geniş — ikisi çok farklı sorunlar ve ikisi de sessiz.
  void _ornekAl(SegmentationMask? maske) {
    final yuz = _sonYuz;
    if (maske == null || yuz == null) return;
    final temel = landmarksFromFace(yuz);
    if (temel == null) {
      _sonSacHatasi = 'landmark yok';
      return;
    }

    final tekKare = hairlineFromMask(
      mask: maske,
      imageSize: _sonBoyut,
      browY: temel.browMid.dy,
      chinY: temel.chin.dy,
      axisX: temel.noseBase.dx,
      faceWidth: (temel.cheekRight.dx - temel.cheekLeft.dx).abs(),
    );
    if (tekKare == null) {
      _sonSacHatasi = 'tek kare ölçümü düştü (güven düşük ya da alın örtülü)';
      return;
    }

    _sonSacTuru = tekKare.kind;
    _sonSacGuveni = tekKare.confidence;
    final eklendi = _kararlilik.add(
      hairlineY: tekKare.y,
      browY: temel.browMid.dy,
      chinY: temel.chin.dy,
    );
    _sonSacHatasi = eklendi ? null : 'geçersiz geometri';
  }

  /// Landmark'lara **ölçülen** saç çizgisini iliştirir.
  ///
  /// Ölçüm başarısızsa `hairlineY` boş kalıyor ve `computeRatios` yüksekliğe
  /// bağlı hiçbir oranı üretmiyor. Bu bilinçli: ML Kit'in yüz konturu tepesini
  /// saç çizgisi saymak, gerçek bir yüzde üst bölgeyi 0,17 gösteriyordu
  /// (klasik ~0,33) ve payda da oradan hesaplandığı için orta/alt bölgeyi de
  /// şişiriyordu. Tek yanlış nokta üç yanlış iddia üretiyordu.
  FaceLandmarks? _olcumlu(Face yuz) {
    final temel = landmarksFromFace(yuz);
    if (temel == null) return null;

    final maske = _sonMaske;
    if (maske == null) return temel;

    // TEK KAREYE GÜVENİLMİYOR — ama örnek toplama BURADA DEĞİL.
    //
    // Bir sürüm boyunca örnekler tam burada toplanıyordu ve iki ayrı kusur
    // üretti. Birincisi: burası hata ayıklama okumasının yolu, kare başına
    // çağrılıyor; sürüm derlemesinde ise yalnızca deklanşörde bir kez
    // çağrılıyor, yani üç örnek asla birikmiyor ve alın HİÇ ölçülmüyordu.
    // İkincisi: teşhis okuması durumu değiştiriyordu — ölçmek ölçüleni
    // etkilemez olmalı.
    //
    // Örnekler artık `_segmentle()` içinde, maske üretildiği anda toplanıyor
    // (700 ms'de bir, her iki derlemede de). Burası yalnızca OKUYOR.
    final y = _kararlilik.hairlineFor(
      browY: temel.browMid.dy,
      chinY: temel.chin.dy,
    );
    final sac = y == null
        ? null
        : Hairline(
            y: y,
            kind: _sonSacTuru ?? HairlineKind.hairline,
            confidence: _sonSacGuveni ?? 0,
          );
    // Log SONUCUN HESAPLANDIGI yerde. Önce `_segmentle()` içinde yazılıyordu
    // ve orası bu işlevden ÖNCE koştuğu için ilk çekimde hep boş çıkıyordu:
    // ölçüm yapılıyor ama görünmüyordu.
    assert(() {
      _sacTuru = sac == null
          ? 'saç çizgisi: ÖLÇÜLEMEDİ — ${_kararlilik.debugLabel}'
          : 'saç çizgisi: ${sac.kind.name} · ${_kararlilik.debugLabel}';
      debugPrint('RYTHO-SEG $_sacTuru');
      final r = computeRatios(FaceLandmarks(
        faceOval: temel.faceOval,
        foreheadTop: temel.foreheadTop,
        browMid: temel.browMid,
        noseBase: temel.noseBase,
        chin: temel.chin,
        cheekLeft: temel.cheekLeft,
        cheekRight: temel.cheekRight,
        jawLeft: temel.jawLeft,
        jawRight: temel.jawRight,
        mouthLeft: temel.mouthLeft,
        mouthRight: temel.mouthRight,
        upperLip: temel.upperLip,
        lowerLip: temel.lowerLip,
        eyeLeft: temel.eyeLeft,
        eyeRight: temel.eyeRight,
        hairlineY: sac?.y,
        hairlineFromCrown: sac?.kind == HairlineKind.crown,
      ));
      debugPrint('RYTHO-SEG bolgeler ust=${r.upperThird.toStringAsFixed(2)} '
          'orta=${r.middleThird.toStringAsFixed(2)} '
          'alt=${r.lowerThird.toStringAsFixed(2)} '
          'olculdu=${r.foreheadMeasured}');
      return true;
    }());
    if (sac == null) return temel;

    return FaceLandmarks(
      faceOval: temel.faceOval,
      foreheadTop: temel.foreheadTop,
      browMid: temel.browMid,
      noseBase: temel.noseBase,
      chin: temel.chin,
      cheekLeft: temel.cheekLeft,
      cheekRight: temel.cheekRight,
      jawLeft: temel.jawLeft,
      jawRight: temel.jawRight,
      mouthLeft: temel.mouthLeft,
      mouthRight: temel.mouthRight,
      upperLip: temel.upperLip,
      lowerLip: temel.lowerLip,
      eyeLeft: temel.eyeLeft,
      eyeRight: temel.eyeRight,
      headAngleZ: temel.headAngleZ,
      headAngleY: temel.headAngleY,
      hairlineY: sac.y,
      hairlineFromCrown: sac.kind == HairlineKind.crown,
    );
  }

  /// Maske alnın örtülü olduğunu mu söylüyor?
  ///
  /// Ayrım önemli: maske YOKSA (model yüklenmedi, çıkarım düştü) bu bir
  /// örtülme değil, ölçüm yapılamaması. O durumda akış devam ediyor ve üç
  /// bölge oranı gönderilmiyor. Yalnızca maske VARKEN saç çizgisi
  /// bulunamıyorsa alın örtülü sayılıyor.
  bool _alinOrtulu() {
    final maske = _sonMaske;
    final yuz = _sonYuz;
    if (maske == null || yuz == null) return false;
    final temel = landmarksFromFace(yuz);
    if (temel == null) return false;

    return hairlineFromMask(
          mask: maske,
          imageSize: _sonBoyut,
          browY: temel.browMid.dy,
          chinY: temel.chin.dy,
          axisX: temel.noseBase.dx,
          faceWidth: (temel.cheekRight.dx - temel.cheekLeft.dx).abs(),
        ) ==
        null;
  }

  /// Ön ↔ arka lens geçişi.
  ///
  /// Ölçüm durumu SIFIRLANIYOR: kararlılık örnekleri, hareket birikimi ve
  /// son maske hepsi eski lensin uzayından. Yeni lensin karelerine eski
  /// örnekleri karıştırmak, medyanın çözdüğü sorunu geri getirirdi.
  Future<void> _lensDegistir() async {
    if (_asama != _Asama.onizleme || _galeriIsleniyor) return;
    HapticFeedback.selectionClick();
    _yon = _yon == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    final eski = _kamera;
    _kamera = null;
    setState(() {
      _asama = _Asama.hazirlaniyor;
      _kilit = 0;
      _kalite = FrameQuality.noFace;
      _noktalar = const [];
      _sonYuz = null;
      _sonKare = null;
      _sonMaske = null;
      _alinUyarisi = false;
    });
    _kararlilik.clear();
    _hareket.reset();
    await eski?.dispose();
    if (!mounted) return;
    await _baslat();
  }

  /// Galeriden fotoğraf seçtirir ve kameradaki boru hattının durağan
  /// eşleniğiyle analiz eder (bkz. face_still.dart).
  ///
  /// Seçicinin uygulama önbelleğine koyduğu kopya işin sonunda SİLİNİYOR:
  /// "görüntü diske yazılmaz" sözünün galeri yolundaki karşılığı, bizim
  /// yazmadığımız kopyayı da ortada bırakmamak.
  Future<void> _galeridenSec() async {
    if (_galeriIsleniyor || _asama != _Asama.onizleme) return;
    HapticFeedback.selectionClick();

    final XFile? secim;
    try {
      secim = await ImagePicker().pickImage(source: ImageSource.gallery);
    } catch (_) {
      return; // Seçici açılamadı; kamera akışı zaten sürüyor.
    }
    if (secim == null || !mounted) return;

    setState(() => _galeriIsleniyor = true);
    try {
      final analiz = await analyzeStillImage(
        path: secim.path,
        detector: _dedektor,
        segmenter: _segmenter,
      );
      if (!mounted) return;

      final sonuc = analiz.result;
      if (sonuc == null) {
        final l10n = AppLocalizations.of(context);
        setState(() => _galeriIsleniyor = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(analiz.failure == StillFailure.noLandmarks
              ? l10n.faceStillNoLandmarks
              : l10n.faceStillNoFace),
        ));
        return;
      }

      HapticFeedback.mediumImpact();
      Navigator.of(context).pop<FaceCaptureResult>(sonuc);
    } finally {
      // Önbellek kopyasını sil — başarıda da başarısızlıkta da.
      try {
        await File(secim.path).delete();
      } catch (_) {}
    }
  }

  /// Çekim — ama **fotoğraf çekmeden**.
  ///
  /// Önceki sürüm `takePicture()` ile geçici bir dosya yazıyor, onu ML Kit'e
  /// veriyor ve siliyordu. İki sorunu vardı:
  ///
  /// 1. **Noktalar yanlış yere düşüyordu.** Ölçekleme için gereken görüntü
  ///    boyutu UYDURULUYORDU (`yüz kutusu × 3`). Gerçek fotoğraf ölçüsüyle
  ///    ilgisi yoktu, dolayısıyla noktalar yüzün üstünde değil rastgele bir
  ///    yerde beliriyordu.
  /// 2. Fotoğraf, kısa bir an için de olsa **diske yazılıyordu.**
  ///
  /// Artık canlı akışın son karesi kullanılıyor: koordinatlar zaten
  /// kadrajlama kontrolüyle aynı uzayda (`rotatedImageSize`) ve önizleme de
  /// aynı `BoxFit.cover` dönüşümüyle çiziliyor — yani noktalar yüzün üstüne
  /// oturuyor. Yan faydası: görüntü artık diske hiç değmiyor.
  Future<void> _cek() async {
    final kamera = _kamera;
    final yuz = _sonYuz;
    if (kamera == null || yuz == null || _kilit < 1.0) return;

    HapticFeedback.mediumImpact();

    try {
      // Segmentasyon TAM BURADA: tarama animasyonu başlamadan hemen önce,
      // saniyede bir değil ömürde bir kez.
      await _segmentle();
      if (!mounted) return;

      // Alın örtülüyse tarama HİÇ BAŞLAMIYOR.
      //
      // Bu, sessizce eksik veri göndermenin alternatifi. Kâkül ya da şapka
      // alnı kapattığında saç çizgisi ölçülemiyor; eskiden bu yalnızca
      // "alan gönderilmedi" olarak sonuçlanıyor ve kullanıcı hiçbir şey
      // bilmiyordu. Oysa bu düzeltilebilir bir durum — söylenmesi gerekiyor.
      if (_alinOrtulu()) {
        setState(() {
          _alinUyarisi = true;
          _kilit = 0;
        });
        return;
      }

      final lm = _olcumlu(yuz);
      if (lm == null) {
        setState(() => _asama = _Asama.hata);
        return;
      }

      setState(() {
        _asama = _Asama.tarama;
        _noktalar = scanNodes(yuz);
        _goruntuBoyutu = _sonBoyut;
      });

      // Akış durur, önizleme DONAR: noktalar donmuş kareye kilitli kalsın.
      // Canlı kalsaydı yüz oynadıkça noktalar geride kalır ve tespit yanlış
      // yapılmış gibi görünürdü.
      await kamera.stopImageStream();
      await kamera.pausePreview();

      await _tarama.forward(from: 0);
      if (!mounted) return;

      Navigator.of(context).pop<FaceCaptureResult>(
          FaceCaptureResult(computeRatios(lm), _hareket.metrics));
    } catch (e, iz) {
      _arizaBildir(e, iz, 'cekim');
      if (!mounted) return;
      setState(() => _asama = _Asama.hata);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nabiz.dispose();
    _tarama.dispose();
    _kamera?.dispose();
    _dedektor.close();
    _segmenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: RythoColors.ink,
      body: LayoutBuilder(builder: (context, kisit) {
        _ekranBoyutu = kisit.biggest;
        return _govde(l10n);
      }),
    );
  }

  Widget _govde(AppLocalizations l10n) {
    return Stack(
        fit: StackFit.expand,
        children: [
          if (_kamera?.value.isInitialized ?? false)
            _onizleme()
          else
            const ColoredBox(color: RythoColors.ink),
          if (_asama == _Asama.onizleme) _kilavuz(),
          if (_asama == _Asama.tarama) _taramaKatmani(),
          if (_asama == _Asama.hazirlaniyor)
            // Marka spinner'ı (R12-A1); deklanşördeki dolum halkası
            // (CircularProgressIndicator value'lu) kasıtlı olarak kalıyor —
            // o bir ilerleme göstergesi, bekleme göstergesi değil.
            const Center(child: AstrolabeSpinner()),
          if (_asama == _Asama.izinYok || _asama == _Asama.hata)
            _hataKatmani(l10n),
          if (_asama == _Asama.onizleme) _altBar(l10n),
          if (_asama == _Asama.tarama) _taramaMetni(l10n),
          if (_galeriIsleniyor) _galeriKatmani(l10n),
          // Kapatma düğmesi yığının EN ÜSTÜNDE.
          //
          // Önce hata katmanının altındaydı ve o katman tüm ekranı kaplayan
          // bir ColoredBox olduğu için düğmeyi örtüyordu: izin reddedilince
          // kullanıcı çıkışı olmayan bir ekranda kalıyordu. Çıkış her zaman
          // erişilebilir olmalı.
          _ustBar(l10n),
        ]);
  }

  /// Önizleme `BoxFit.cover` ile ekranı kaplar; katmandaki nokta ölçekleme
  /// de aynı dönüşümü varsayıyor (bkz. FaceScanPainter._olcekle).
  Widget _onizleme() {
    final kamera = _kamera!;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: kamera.value.previewSize?.height ?? 1,
        height: kamera.value.previewSize?.width ?? 1,
        child: CameraPreview(kamera),
      ),
    );
  }

  Widget _kilavuz() => AnimatedBuilder(
        animation: _nabiz,
        builder: (_, _) => CustomPaint(
          painter: FaceGuidePainter(
            quality: _kalite,
            pulse: _nabiz.value,
            lockProgress: _kilit,
          ),
        ),
      );

  Widget _taramaKatmani() => AnimatedBuilder(
        animation: _tarama,
        builder: (_, _) => CustomPaint(
          painter: FaceScanPainter(
            lines: _noktalar,
            progress: _tarama.value,
            imageSize: _goruntuBoyutu,
            // Android'de ön kamera önizlemesi aynalı, ML Kit koordinatları
            // aynasız: bayrak verilmezse noktalar yüzün YANINA düşüyor
            // (cihazda "noktalar yüzümün solunda" diye görüldü). iOS'ta
            // koordinatlar zaten aynalı tampondan geliyor; orada bayrak
            // noktaları ikinci kez çevirirdi. Karar tek yerde.
            mirrored: taramaNoktalariAynalanir(
                _kamera?.description.lensDirection),
          ),
        ),
      );

  Widget _ustBar(AppLocalizations l10n) => SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: RythoColors.parchment),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      );

  Widget _altBar(AppLocalizations l10n) => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tek seferde TEK yönerge. "Ortala ve yaklaş ve başını
                // düzelt" üç ayrı iş demek; kimse okumuyor.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    _alinUyarisi
                        ? l10n.faceGuideForehead
                        : _yonerge(l10n, _kalite),
                    key: ValueKey(_alinUyarisi ? 'alin' : _kalite),
                    style: RythoText.body(16, w: FontWeight.w500),
                  ),
                ),
                // Ölçüm satırları (yalnız geliştirme derlemesi): veri rolü.
                if (kDebugMode && _olcum != null) ...[
                  const SizedBox(height: RythoSpace.xs),
                  Text(_olcum!,
                      style: RythoText.mono(11,
                          color: RythoColors.parchmentDim)),
                ],
                if (kDebugMode && _bolgeler != null) ...[
                  const SizedBox(height: RythoSpace.xxs),
                  Text(_bolgeler!,
                      style: RythoText.mono(11,
                          color: RythoColors.parchmentDim)),
                ],
                if (kDebugMode && _segOlcum != null) ...[
                  const SizedBox(height: RythoSpace.xxs),
                  Text(_segOlcum!,
                      textAlign: TextAlign.center,
                      style: RythoText.mono(10, color: ScanPalette.node)),
                ],
                const SizedBox(height: 22),
                // Deklanşör ortada; yanlarında galeri ve lens çevirme.
                // İkisi de deklanşörden görsel olarak KÜÇÜK ve sönük: asıl
                // eylem çekim, bunlar alternatif yollar.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _yanDugme(
                      icon: Icons.photo_library_outlined,
                      etiket: l10n.faceGalleryButton,
                      onTap: _galeridenSec,
                    ),
                    const SizedBox(width: 34),
                    _deklansor(),
                    const SizedBox(width: 34),
                    if (_ciftLens)
                      _yanDugme(
                        icon: Icons.cameraswitch_outlined,
                        etiket: l10n.faceLensButton,
                        onTap: _lensDegistir,
                      )
                    else
                      // Simetri: lens düğmesi yoksa deklanşör kaymasın.
                      const SizedBox(width: 46),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  /// Deklanşör yanı ikincil düğme (galeri / lens çevirme).
  Widget _yanDugme({
    required IconData icon,
    required String etiket,
    required VoidCallback onTap,
  }) =>
      Semantics(
        button: true,
        label: etiket,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RythoColors.ink.withValues(alpha: 0.45),
              border: Border.all(
                  color: RythoColors.parchment.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, size: 21, color: RythoColors.parchment),
          ),
        ),
      );

  /// Galeri fotoğrafı analiz edilirken tüm ekranı kaplayan örtü.
  ///
  /// Çekimdeki tarama sahnesinin sade eşleniği: kullanıcı ~1-2 saniyelik
  /// tespit + segmentasyon süresince ne olduğunu görmeli — çıplak bir
  /// donma "uygulama takıldı" okunur.
  Widget _galeriKatmani(AppLocalizations l10n) => ColoredBox(
        color: RythoColors.ink.withValues(alpha: 0.82),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AstrolabeSpinner(),
              const SizedBox(height: 18),
              // Geniş harf aralığı tarama sahnesinin kendi dili; rol
              // gövde, aralık üstüne ekleniyor.
              Text(l10n.faceStillAnalyzing,
                  style: RythoText.body(15, w: FontWeight.w500)
                      .copyWith(letterSpacing: 1.2)),
            ],
          ),
        ),
      );

  /// Deklanşör yalnızca kilit dolduğunda etkin.
  ///
  /// Kapalıyken de görünür duruyor ve dolum halkası taşıyor: düğmenin niye
  /// çalışmadığı görünür olmalı, aksi halde uygulama bozuk sanılıyor.
  Widget _deklansor() {
    final hazir = _kilit >= 1.0;
    return Semantics(
      button: true,
      enabled: hazir,
      child: GestureDetector(
        onTap: hazir ? _cek : null,
        child: SizedBox(
          width: 78,
          height: 78,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _kilit,
                strokeWidth: 3,
                backgroundColor: RythoColors.line,
                valueColor: const AlwaysStoppedAnimation(ScanPalette.locked),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: hazir ? 58 : 48,
                height: hazir ? 58 : 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hazir
                      ? RythoColors.parchment
                      : RythoColors.parchmentDim.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tarama sırasındaki durum satırı.
  ///
  /// Önceki sürümde metin yanıp sönüyordu (`sin` ile saydamlık) ve aşama
  /// değişimi ani oluyordu — ikisi de ucuz duruyordu. Artık aşamalar
  /// birbirine çapraz geçiyor, altında ince bir ilerleme çizgisi var: hem
  /// nerede olduğu belli hem de ne kadar kaldığı.
  Widget _taramaMetni(AppLocalizations l10n) => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 52, left: 40, right: 40),
            child: AnimatedBuilder(
              animation: _tarama,
              builder: (_, _) {
                final t = _tarama.value;
                final (metin, sira) = t < 0.42
                    ? (l10n.faceScanning, 0)
                    : t < 0.85
                        ? (l10n.faceScanNodes, 1)
                        : (l10n.faceScanReading, 2);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.35),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                              parent: anim, curve: Curves.easeOutCubic)),
                          child: child,
                        ),
                      ),
                      child: Text(
                        metin,
                        key: ValueKey(sira),
                        textAlign: TextAlign.center,
                        style: RythoText.body(15, w: FontWeight.w500)
                            .copyWith(letterSpacing: 1.6),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: 132,
                      height: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(1),
                        child: LinearProgressIndicator(
                          value: t,
                          backgroundColor:
                              RythoColors.parchment.withValues(alpha: 0.14),
                          valueColor: const AlwaysStoppedAnimation(
                              ScanPalette.node),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

  Widget _hataKatmani(AppLocalizations l10n) => ColoredBox(
        color: RythoColors.ink,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _asama == _Asama.izinYok
                      ? l10n.faceCameraDenied
                      : l10n.faceDetectFailed,
                  textAlign: TextAlign.center,
                  style: RythoText.body(16),
                ),
                const SizedBox(height: RythoSpace.lg),
                // Tekrar denemek HER İKİ hata durumunda da mümkün.
                //
                // Önce yalnızca `hata` durumunda vardı; izin reddedildiğinde
                // ekranda ne düğme ne çıkış kalıyordu. Yeniden çekimde
                // hareket ölçümü de sıfırlanır — önceki denemenin kareleri
                // yeni okumaya karışmamalı.
                if (_asama == _Asama.izinYok) ...[
                  // İzin reddinde "Ayarları aç" GERÇEKTEN ayarları açar.
                  // Bir dönem bu etiketli düğme yalnız yeniden deniyordu:
                  // kalıcı reddeden kullanıcı (diyalog bir daha çıkmaz)
                  // düğmeye basıp aynı ekrana düşüyordu. Ayarlardan dönüş
                  // `didChangeAppLifecycleState` ile kendiliğinden denenir;
                  // el ile deneme yine de ikinci düğmede duruyor.
                  FilledButton(
                    onPressed: () => AppSettings.openAppSettings(),
                    child: Text(l10n.faceOpenSettings),
                  ),
                  const SizedBox(height: RythoSpace.sm),
                  TextButton(
                    onPressed: _yenidenDene,
                    child: Text(l10n.retry),
                  ),
                  const SizedBox(height: RythoSpace.sm),
                  Text(l10n.faceCameraDeniedHint,
                      textAlign: TextAlign.center, style: RythoType.bodyDim),
                ] else
                  FilledButton(
                    onPressed: _yenidenDene,
                    child: Text(l10n.faceRetake),
                  ),
              ],
            ),
          ),
        ),
      );

  static String _yonerge(AppLocalizations l10n, FrameQuality q) => switch (q) {
        FrameQuality.noFace => l10n.faceGuideNoFace,
        FrameQuality.tooFar => l10n.faceGuideTooFar,
        FrameQuality.tooClose => l10n.faceGuideTooClose,
        FrameQuality.offCentre => l10n.faceGuideOffCentre,
        FrameQuality.tilted => l10n.faceGuideTilted,
        FrameQuality.ready => l10n.faceGuideReady,
      };
}

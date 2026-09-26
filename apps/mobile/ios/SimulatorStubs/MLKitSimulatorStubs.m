// ML Kit eklentilerinin YALNIZ SİMÜLATÖR yer tutucusu.
//
// NEDEN VAR: Google ML Kit iOS ikilileri Apple Silicon simülatör dilimi
// (arm64-simulator) taşımıyor; iOS 26+ simülatörleri ise YALNIZ arm64
// çalıştırıyor. Yani ML Kit gömülü bir uygulama bu Mac'te hiçbir
// simülatörde açılamıyordu (ölçüldü 2026-09-26, Xcode 26.6).
//
// Podfile'daki post_install, simülatör derlemesinde eklentilerin gerçek
// .m dosyalarını dışlıyor ve ML Kit çerçevelerini bağlamadan çıkarıyor. O
// zaman GeneratedPluginRegistrant'ın çağırdığı iki sınıf eksik kalır; bu
// dosya onları sağlar. Kanal adları gerçek eklentilerle BİREBİR aynı —
// Dart tarafı çağırınca sessiz bir "sonuç yok" değil, AÇIK bir hata alır.
// Yüz okuma simülatörde çalışmıyor; bunu "yüz bulunamadı" gibi göstermek
// ölçülmemiş bir şeyi söylemek olurdu.
//
// Gerçek cihazda bu dosyanın içi BOŞ derlenir (TARGET_OS_SIMULATOR).

#import <TargetConditionals.h>

#if TARGET_OS_SIMULATOR

#import <Flutter/Flutter.h>

static void simulatordeYok(FlutterMethodCall *call, FlutterResult result) {
    result([FlutterError errorWithCode:@"SIMULATORDE_YOK"
                               message:@"ML Kit (yüz okuma) iOS simülatöründe çalışmaz; gerçek cihaz gerekir."
                               details:call.method]);
}

@interface GoogleMlKitCommonsPlugin : NSObject<FlutterPlugin>
@end

@implementation GoogleMlKitCommonsPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *kanal = [FlutterMethodChannel
        methodChannelWithName:@"google_mlkit_commons"
              binaryMessenger:[registrar messenger]];
    [registrar addMethodCallDelegate:[[GoogleMlKitCommonsPlugin alloc] init] channel:kanal];
}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    simulatordeYok(call, result);
}
@end

@interface GoogleMlKitFaceDetectionPlugin : NSObject<FlutterPlugin>
@end

@implementation GoogleMlKitFaceDetectionPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *kanal = [FlutterMethodChannel
        methodChannelWithName:@"google_mlkit_face_detector"
              binaryMessenger:[registrar messenger]];
    [registrar addMethodCallDelegate:[[GoogleMlKitFaceDetectionPlugin alloc] init] channel:kanal];
}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    simulatordeYok(call, result);
}
@end

#endif

// UI seslerinin iOS ses oturumu bekçileri (K3-bildirim turu: U24).
//
// audioplayers'ın iOS varsayılanı `playback`: sesler Zil/Sessiz anahtarı
// sessizdeyken de çalıyor ve her "pop" arka plandaki müziği durduruyordu.
// Düzeltme ilk çalıştan önce bir kez `ambient`. Asıl tehlikeler: bağlamın
// çalıştan SONRA kurulması (ilk ses yine müziği keser), her çalışta yeniden
// kurulması ve Android'e sızması.
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/sound.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kurulum ve çalışları TEK sırada kaydeder.
class _Kayit {
  final sira = <String>[];
  final baglamlar = <AudioContext>[];

  Future<void> kur(AudioContext baglam) async {
    sira.add('baglam');
    baglamlar.add(baglam);
  }

  Future<void> cal(String asset, double volume) async => sira.add('cal:$asset');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Kayit kayit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundFx.testIcinSifirla();
    kayit = _Kayit();
    SoundFx.baglamKurucu = kayit.kur;
    SoundFx.calici = kayit.cal;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    SoundFx.testIcinSifirla();
  });

  test('iOS bağlamı ambient, seçenekler BOŞ', () {
    final ios = SoundFx.iosSesBaglami.iOS;
    expect(ios.category, AVAudioSessionCategory.ambient);
    // mixWithOthers eklenirse AudioContextIOS yapıcısındaki assert düşer;
    // ambient zaten karıştırıyor.
    expect(ios.options, isEmpty);
  });

  test('iOS: bağlam ilk çalıştan ÖNCE, yalnız bir kez kurulur', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await SoundFx.send();
    await SoundFx.like();
    await SoundFx.send();
    expect(kayit.sira, [
      'baglam',
      'cal:message_send.wav',
      'cal:like.wav',
      'cal:message_send.wav',
    ]);
    expect(kayit.baglamlar.single, SoundFx.iosSesBaglami);
  });

  test('iOS: eşzamanlı ilk çalışlar tek kurulumu paylaşır', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await Future.wait([SoundFx.send(), SoundFx.receive(), SoundFx.like()]);
    expect(kayit.sira.where((s) => s == 'baglam'), hasLength(1));
    expect(kayit.sira.first, 'baglam');
    expect(kayit.sira.where((s) => s.startsWith('cal:')), hasLength(3));
  });

  test('iOS: anahtarla açılan seste de bağlam kurulur', () async {
    // setEnabled `_loaded`'ı çalışsız kapatıyor; kurulum ona bağlı olsaydı
    // Profil'deki anahtar yolu (profile_sections.dart: setEnabled → like)
    // bağlamı hiç kurmazdı.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await SoundFx.setEnabled(true);
    await SoundFx.like();
    expect(kayit.sira, ['baglam', 'cal:like.wav']);
  });

  test('iOS: kurulum düşerse o ses SUSAR, sonraki çalış yeniden dener',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var deneme = 0;
    SoundFx.baglamKurucu = (baglam) async {
      deneme++;
      if (deneme == 1) throw StateError('AVAudioSession');
      await kayit.kur(baglam);
    };
    await SoundFx.send();
    expect(kayit.sira, isEmpty,
        reason: 'playback oturumuyla çalmak müziği keserdi');
    await SoundFx.send();
    expect(kayit.sira, ['baglam', 'cal:message_send.wav']);
    expect(deneme, 2);
  });

  test('Android: bağlama hiç dokunulmaz, çalış aynen', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await SoundFx.send();
    await SoundFx.like();
    expect(kayit.sira, ['cal:message_send.wav', 'cal:like.wav']);
  });

  test('sesler kapalıyken ne bağlam kurulur ne çalınır', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({'soundsEnabled': false});
    await SoundFx.send();
    expect(kayit.sira, isEmpty);
  });
}

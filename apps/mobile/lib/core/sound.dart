import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Küçük, yumuşak UI sesleri — tools/generate_sounds.py ile sentezlenen
/// WAV'lar (assets/sounds/). Ses seviyesi düşük tutulur; Profil'deki
/// "Sesler" anahtarıyla kapatılabilir (shared_preferences, varsayılan açık).
class SoundFx {
  SoundFx._();

  static const _prefKey = 'soundsEnabled';
  static bool _enabled = true;
  static bool _loaded = false;

  /// iOS ses oturumu `ambient`'e çekildi mi? (U24)
  ///
  /// [_loaded]'dan AYRI, çünkü [_ensureLoaded] `_loaded`'ı tercihleri
  /// okumadan ÖNCE true yapıyor ve hiç geri almıyor: kurulum oraya
  /// bağlansaydı tek hakkı olurdu. Düşen tek bir AVAudioSession çağrısı
  /// süreci ömür boyu `playback`'te bırakırdı — müziği keser, Sessiz
  /// anahtarını çiğner, yeniden denenmez. Ayrı bayrak + düşünce
  /// [_iosOturumKurulumu]'nun sıfırlanması o yeniden denemeyi veriyor.
  /// Kurulumu [loadEnabled] / [setEnabled] hangisinin önce koştuğundan da
  /// bağımsız kılıyor ([setEnabled] de `_loaded`'ı true yapıyor); bugün Profil
  /// ekranı `initState`'te [loadEnabled]'ı anahtardan önce çağırdığı için o
  /// sıra uygulamada ters dönmüyor.
  static bool _iosOturumuHazir = false;
  static Future<void>? _iosOturumKurulumu;

  static bool get enabled => _enabled;

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  /// Senkron okuma için başlangıçta çağrılabilir.
  static Future<bool> loadEnabled() async {
    await _ensureLoaded();
    return _enabled;
  }

  /// iOS'ta UI seslerinin ses oturumu: `ambient` (U24).
  ///
  /// audioplayers_darwin 6.5.0 eklenti kaydında oturum kategorisini
  /// `playback` yapıyor (`AudioplayersDarwinPlugin.swift`,
  /// `globalContext.apply()`) ve her çalışta oturumu etkinleştiriyor.
  /// `playback`, Zil/Sessiz anahtarı sessizdeyken de çalar ve başka sesle
  /// karışmaz: bir mesaj "pop"u arka plandaki Spotify / Apple Music'i
  /// durduruyordu. `ambient` sessiz anahtarına uyar ve zaten karıştırır.
  ///
  /// `options` BOŞ kalmalı: `mixWithOthers`'ı açıkça eklemek
  /// `AudioContextIOS` yapıcısındaki assert'e takılır
  /// (audioplayers_platform_interface 7.2.0 onu yalnız
  /// playback / playAndRecord / multiRoute ile kabul ediyor).
  ///
  /// iOS ses oturumu uygulama başınadır, oynatıcı başına değil. Başka ses
  /// çalan yer yok (yüz okuma kamerası `enableAudio: false`), yani bu seçim
  /// başka bir özelliği susturmaz.
  static AudioContext get iosSesBaglami => AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const {},
        ),
      );

  static Future<void> _varsayilanBaglamKurucu(AudioContext baglam) =>
      AudioPlayer.global.setAudioContext(baglam);

  static Future<void> _varsayilanCalici(String asset, double volume) async {
    // Her çalış için kısa ömürlü oyuncu: üst üste binen sesler kesilmez.
    final player = AudioPlayer();
    player.onPlayerComplete.listen((_) => player.dispose());
    await player.play(AssetSource('sounds/$asset'), volume: volume);
  }

  /// Global ses bağlamını kuran kanal — test dikişi.
  @visibleForTesting
  static Future<void> Function(AudioContext baglam) baglamKurucu =
      _varsayilanBaglamKurucu;

  /// Tek bir sesi çalan kanal — test dikişi.
  @visibleForTesting
  static Future<void> Function(String asset, double volume) calici =
      _varsayilanCalici;

  /// Testler arası sızmayı önler; kanalları da varsayılana döndürür.
  @visibleForTesting
  static void testIcinSifirla() {
    _enabled = true;
    _loaded = false;
    _iosOturumuHazir = false;
    _iosOturumKurulumu = null;
    baglamKurucu = _varsayilanBaglamKurucu;
    calici = _varsayilanCalici;
  }

  /// iOS'ta oturumu ilk çalıştan ÖNCE bir kez `ambient`'e çeker.
  ///
  /// Kurulum düşerse bu çalış SUSAR ve sonraki çalış yeniden dener:
  /// varsayılan `playback` oturumuyla çalmak kusurun ta kendisi (müziği
  /// keser, sessiz anahtarını çiğner), eksik bir "tık" ondan ucuz.
  /// Eşzamanlı ilk çalışlar aynı kurulumu bekler, ikinci kez kurmaz.
  static Future<bool> _iosOturumunuHazirla() async {
    if (defaultTargetPlatform != TargetPlatform.iOS || _iosOturumuHazir) {
      return true;
    }
    try {
      await (_iosOturumKurulumu ??= baglamKurucu(iosSesBaglami));
      _iosOturumuHazir = true;
    } catch (e) {
      debugPrint('SoundFx iOS ses oturumu kurulamadı: $e');
      _iosOturumKurulumu = null;
    }
    return _iosOturumuHazir;
  }

  static Future<void> _play(String asset, double volume) async {
    await _ensureLoaded();
    if (!_enabled) return;
    if (!await _iosOturumunuHazirla()) return;
    try {
      await calici(asset, volume);
    } catch (e) {
      debugPrint('SoundFx çalınamadı ($asset): $e');
    }
  }

  /// Mesaj gönderildi — kısa yumuşak "pop".
  static Future<void> send() => _play('message_send.wav', 0.4);

  /// Yeni mesaj geldi — iki tonlu nazik "ding".
  static Future<void> receive() => _play('message_receive.wav', 0.4);

  /// I Ching çekimi — mistik kısa "chime".
  static Future<void> cast() => _play('cast.wav', 0.45);

  /// Beğeni — çok kısa "tick".
  static Future<void> like() => _play('like.wav', 0.3);

  /// Başarı anı (R12-C1) — C6-E6-G6 arpej.
  static Future<void> success() => _play('success.wav', 0.4);

  /// Seri artışı (R12-C1) — parlak tık + beşli.
  static Future<void> streak() => _play('streak.wav', 0.35);

  /// Satın alma kutlaması (R12-C1) — cast ailesinden dolu çift vuruş.
  static Future<void> purchase() => _play('purchase.wav', 0.45);

  /// Para inişi (PBZ) — kısa inharmonik metalik "clink"; her iniş klibi
  /// başında, altı kez.
  static Future<void> coinLand() => _play('coin_land.wav', 0.4);
}

/// Cihaz çakışması kapısı — hesap başka cihazda açıldığında (TC-turu K6).
///
/// Sunucu korumalı bir isteğe 409 + `X-Device-Conflict` döndürdü: "son giriş
/// kazanır" kuralıyla kilit başka cihaza geçmiş. `_Gate` bu ekranı kabuğun
/// YERİNE koyar (zorunlu güncelleme kapısı deseni) — navigator yığınına
/// basılmaz, diyalog üstüne diyalog binmez. Oturum AÇIK; iki eylem var,
/// ikisi de kimlikli:
///
/// * **Bu cihazda kullan** → `POST /device/claim`; başarıda kapı açılır ve
///   409 ile düşmüş Rytho+ sağlayıcıları tazelenir (eski hata önbellekte
///   kalmasın). Eski ekranın tek eylemi "giriş ekranına dön"dü ve devralma
///   oturum kapalı olduğu için 401'e çarpıyordu (B4).
/// * **Oturumu kapat** → [signOutEverywhere]: kilit bırakılır, oturum
///   kapanır. Etiket profildeki çıkışla AYNI anahtar (`signOut`): eskiden
///   burada "Çıkış yap", profilde "Oturumu kapat" yazıyordu — aynı eylem,
///   iki ad (D4).
///
/// Geri tuşu geçmez ([PopScope] `canPop: false`): kök rotada geri tuşu
/// uygulamayı arka plana atıp "kapı geçildi" hissi verirdi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart' show apiProvider;
import '../../core/auth_service.dart' show signOutEverywhere;
import '../../core/device_session.dart';
import '../../core/providers.dart' show invalidatePlusProviders;
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/motion.dart';

class DeviceConflictScreen extends ConsumerStatefulWidget {
  const DeviceConflictScreen({super.key, this.signOut});

  /// Test dikişi; üretimde [signOutEverywhere].
  final Future<void> Function()? signOut;

  @override
  ConsumerState<DeviceConflictScreen> createState() =>
      _DeviceConflictScreenState();
}

class _DeviceConflictScreenState extends ConsumerState<DeviceConflictScreen> {
  bool _mesgul = false;

  /// Kimlikli devralma. Başarıda önce sağlayıcılar tazelenir, SONRA kapı
  /// açılır: kapı açılınca `_Gate` kabuğu kurar; 409'lu eski sonuçla bir
  /// kare bile karşılaşmasın. Başarısızlık (sunucu dürüst `claimed:false`
  /// ya da ağ) SÖYLENİR — çıkışı olmayan ekranda sessiz düğme "uygulama
  /// bozuldu" demektir (ForceUpdateScreen ile aynı kural).
  Future<void> _buCihazdaKullan() async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    // Messenger/l10n await'ten ÖNCE alınır: sonra context ölmüş olabilir.
    final mesajci = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    var devralindi = false;
    try {
      devralindi = await claimThisDevice(ref.read(apiProvider));
    } catch (e) {
      debugPrint('Cihaz devralınamadı: $e');
    }
    if (!mounted) return;
    if (!devralindi) {
      setState(() => _mesgul = false);
      mesajci.showSnackBar(
          SnackBar(content: Text(l10n.deviceConflictClaimFailed)));
      return;
    }
    invalidatePlusProviders(ref);
    ref.read(deviceConflictProvider.notifier).state = null;
  }

  Future<void> _cikisYap() async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    final Future<void> Function() cikis = widget.signOut ?? signOutEverywhere;
    try {
      await cikis();
    } finally {
      // Çıkış başarılıysa `_Gate` ekranı çoktan sökmüştür.
      if (mounted) setState(() => _mesgul = false);
    }
  }

  /// Sunucudan gelen platform adı ham (`android`, `iOS`); cümlede "android
  /// cihazında" yerine "Android cihazında". Bilinmiyorsa "—".
  static String platformEtiketi(String? p) {
    if (p == null || p.isEmpty) return '—';
    // İki değerli eşleme: `toUpperCase` "ios"u "Ios" yapıyordu (D4 ölçümü).
    // Bilinmeyen değer olduğu gibi — ad uydurulmaz.
    return switch (p) {
      'android' => 'Android',
      'ios' => 'iOS',
      _ => p,
    };
  }

  /// Diğer cihazın kilidi aldığı an — kullanıcının saat dilimi ve dilinde.
  String? _yerelSaat(BuildContext context, DateTime? t) {
    if (t == null) return null;
    final dil = Localizations.localeOf(context).toLanguageTag();
    return DateFormat('d MMMM HH:mm', dil).format(t.toLocal());
  }

  /// Gövde cümlesi. İki başlık da (platform + saat) gelmediyse boşlukları
  /// "—" ile doldurmak "— cihazında — saatinde" gibi okunuyordu; bilinmeyen
  /// şey söylenmez, cümle bilgisiz hâline düşer. Yalnız biri biliniyorsa
  /// ölçülen bilgi atılmaz, eksik olan "—" kalır.
  String _govde(BuildContext context, AppLocalizations l10n,
      DeviceConflict? cakisma) {
    final platform = cakisma?.platform;
    final saat = _yerelSaat(context, cakisma?.claimedAt);
    if ((platform == null || platform.isEmpty) && saat == null) {
      return l10n.deviceConflictBodyUnknown;
    }
    return l10n.deviceConflictBody(platformEtiketi(platform), saat ?? '—');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cakisma = ref.watch(deviceConflictProvider);
    return PopScope(
      canPop: false,
      child: CosmicScaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(RythoSpace.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // Yumuşak giriş (R12-C3): kullanıcının hesabının başka cihazda
              // açıldığını öğrendiği an — sert bir kesmeyle sertleşmesin.
              children: [
                const RythoReveal(
                  slide: 0,
                  child: Text('📱',
                      style: TextStyle(fontSize: 44),
                      textAlign: TextAlign.center),
                ),
                const SizedBox(height: RythoSpace.lg),
                RythoReveal(
                  index: 1,
                  child: Text(l10n.deviceConflictTitle,
                      style: RythoText.display(22),
                      textAlign: TextAlign.center),
                ),
                const SizedBox(height: RythoSpace.md),
                RythoReveal(
                  index: 2,
                  child: Text(_govde(context, l10n, cakisma),
                      style: RythoType.bodyDim,
                      textAlign: TextAlign.center),
                ),
                const SizedBox(height: RythoSpace.xxl),
                RythoReveal(
                  index: 3,
                  child: GoldButton(
                    text: l10n.deviceConflictUseHere,
                    busy: _mesgul,
                    onPressed: _buCihazdaKullan,
                  ),
                ),
                const SizedBox(height: RythoSpace.md),
                RythoReveal(
                  index: 4,
                  child: Center(
                    child: TextButton(
                      onPressed: _mesgul ? null : _cikisYap,
                      child: Text(l10n.signOut,
                          style: RythoText.body(13,
                              color: RythoColors.parchmentDim)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

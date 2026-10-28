/// Kapı ekranlarını görünür kılan bekçi (TC-turu denetim bulgusu).
///
/// `ForceUpdateScreen` (426) ve `DeviceConflictScreen` (409) `_Gate`'in
/// `home` alt ağacında yaşar; kapı kapanınca `_Gate` yalnız o alt ağacı
/// değiştirir. Üstte basılı bir rota varken — sohbet, yüz okuma, kehanet,
/// ikili okuma: kilitli yüzeylerin çoğu `Navigator.push` ile açılır — yeni
/// ekran o rotanın ALTINDA kalır: kullanıcı satır içi hatada "Bu cihazda
/// kullan'a dokun" okur ama düğme ekranda değildir; tekrar denedikçe 409
/// yer. Eski kod çakışma ekranını tam ekran rota olarak bastığı için her
/// derinlikten görünüyordu; kapı deseni (K6) o yolu bilerek kapattı
/// (yığına basılmaz, diyalog üstüne diyalog binmez) — bu bekçi görünürlüğü
/// geri verir: kapı kapandığı an yığın köke iner, `_Gate`'in kurduğu ekran
/// öne çıkar.
///
/// Kaynak fark etmez — interceptor (426/409), açılış okuması, ön plana
/// dönüşte yeniden okuma: hepsi aynı iki sağlayıcıdan geçer. Kapı AÇILINCA
/// (devralma başarılı, eşik sıfırlandı) bir şey yapılmaz; `_Gate` kabuğu
/// kökte zaten yeniden kurar.
///
/// Üçüncü kapı OTURUMUN KAPANMASI: `_Gate` kökü giriş sayfasına çevirir,
/// basılı rota yine üstte kalır. iPad'de ölçüldü (2026-10-28): Hesap
/// sayfasından hesap silinince silme alt sayfası kapanıyor, giriş sayfası
/// kökte kuruluyordu ama ekranda silinmiş hesabın Hesap sayfası — adı,
/// "Kaydet", "Hesabı sil" — duruyordu. Çıkışın her yolu (silme, 401
/// sonrası çıkış, onboarding'den çıkış, iptal edilen oturum) buradan geçer;
/// tek tek ekranlara bırakılsaydı her yeni çıkış yolu aynı kusuru taşırdı.
library;

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart' show mustForceUpdateProvider;
import 'device_session.dart' show DeviceConflict, deviceConflictProvider;
import 'providers.dart' show authStateProvider;

class GateRootGuard extends ConsumerWidget {
  const GateRootGuard(
      {super.key, required this.navigatorKey, required this.child});

  /// Kök navigatör (`rythoNavigatorKey`); ilk rotası `_Gate`.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// Kök rota `_Gate`'in kendisi; üstündeki her şey (sayfa, diyalog, alt
  /// sayfa) iner. Kare sonrasına bırakılır: bayrak bir isteğin geri
  /// çağrısında da, bir build sırasında da değişebilir — ikisinde de
  /// navigatöre anında dokunmak güvenli değil.
  void _kokeDon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Yalnız KAPANIŞ kenarı: bayrak zaten kapalıyken yeniden yazılması
    // (uçuştaki ikinci 409, ön plan yeniden okuması) yığına dokunmaz.
    ref.listen<bool>(mustForceUpdateProvider, (onceki, simdi) {
      if (simdi && onceki != true) _kokeDon();
    });
    ref.listen<DeviceConflict?>(deviceConflictProvider, (onceki, simdi) {
      if (simdi != null && onceki == null) _kokeDon();
    });
    // Yalnız AÇIK → KAPALI kenarı: soğuk açılıştaki yükleme → çıkışlı
    // geçişte önceki değer zaten null'dır, yığına dokunulmaz.
    ref.listen<AsyncValue<User?>>(authStateProvider, (onceki, simdi) {
      if (onceki?.value != null && simdi.hasValue && simdi.value == null) {
        _kokeDon();
      }
    });
    return child;
  }
}

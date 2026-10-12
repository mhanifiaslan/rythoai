/// Paywall'ı açmanın TEK yolu — kaynak etiketi ve rota türü burada seçilir.
///
/// ## Neden var
/// Ölçüldü (2026-10-10): `PaywallScreen` dokuz yerden itiliyordu ve rota
/// türü yere göre rastgeleydi — kilit kartı `FadeThroughRoute`, Atlas
/// karosu ve takvim günü `MaterialPageRoute(fullscreenDialog: true)`,
/// mağazanın "Plus'a bak" düğmesi düz `MaterialPageRoute`. Aynı ekran bir
/// yerden aşağıdan kayarak, bir yerden sönerek geliyordu. Analitik etiketi
/// de iki değerliydi (`intro`/`locked`): hangi yüzeyin dönüştürdüğü
/// ölçülemiyordu.
///
/// ## Kesinti ve dokunuş
/// İki sınıf var ve rota türünü sınıf seçer:
/// * **Kesinti** — kullanıcı istemedi, ekran ona GELDİ (sunucu 402'si,
///   ilk değer sonrası tanıtım). Tam ekran diyalog: alttan gelir, kapatma
///   düğmesi taşır; "bu bir araya girme" dili.
/// * **Dokunuş** — kullanıcı kilide BASTI. Fade-through (R12-B2): bastığı
///   kartın devamı gibi açılır; diyalog dili burada yanlış olurdu.
///
/// D7'de son üç doğrudan çağrı yeri de (jeton mağazası, abonelik ekranı
/// ×2) buraya geçti; `PaywallScreen.kaynak` artık zorunlu ve eski iki
/// değerli etiket kuralı (`reason == null ? 'intro' : 'locked'`) silindi —
/// kaynak taşımayan çağrı yeri kalmadığı için geriye uyum kapısının
/// koruyacağı bir şey yok.
library;

import 'package:flutter/material.dart';

import '../../widgets/fade_through_route.dart';
import 'ozellik_katalogu.dart';
import 'paywall_screen.dart';

enum PaywallKaynak {
  /// Sunucu 402 döndü (`core/api.dart` interceptor'ı). Etiket eski
  /// `locked` ile aynı: analitik zaman serisi kopmasın.
  kilit402('locked', kesinti: true),

  /// İlk değer gösterildikten sonra tanıtım (`sky_screen`). Etiket eski
  /// `intro`.
  tanitim('intro', kesinti: true),

  /// Takvim gününün kilit satırı.
  takvimGunu('calendar_day'),

  /// Atlas tam rapor satırı.
  atlasRapor('atlas_report'),

  /// Atlas kehanet karosu (yüz, İ Ching, BaZi, doğum kapısı).
  atlasKaro('atlas_tile'),

  /// `PlusLockedCard`.
  kilitKarti('locked_card'),

  /// Abonelik ekranındaki "Rytho+'a geç".
  abonelikEkrani('subscription_screen'),

  /// Jeton mağazasının "paketler aboneye özel" uyarısı.
  magaza('token_store');

  const PaywallKaynak(this.etiket, {this.kesinti = false});

  /// `Analytics.paywallShown` parametresi.
  final String etiket;

  /// Kullanıcı istemeden geldi mi — rota türünü bu seçer.
  final bool kesinti;
}

/// Ekran tam-ekran diyalog olarak mı açıldı?
///
/// Para ekranları iki rotayla açılıyor: kesinti yolu (402 köprüsü,
/// tanıtım) `fullscreenDialog: true`, dokunuş yolu fade-through ya da düz
/// sayfa. Flutter'ın "diyalogsa ✕, değilse ←" mantığı AppBar'ın OTOMATİK
/// düğmesinde yaşıyor; düğmeyi meşguliyete bağlamak için elle koyduğumuz
/// an o mantığı da elle taşımak gerekti. Jeton mağazası ve satış ekranı
/// aynı soruyu soruyor — iki kopya olmasın diye burada.
bool tamEkranDiyalogMu(BuildContext context) {
  final rota = ModalRoute.of(context);
  return rota is PageRoute && rota.fullscreenDialog;
}

/// Paywall'ı açar; `true` abonelik açıldı, `false`/`null` kapatıldı.
///
/// `core/api.dart`taki `_paywallOpen` bayrağı BURADA YOK ve dokunuş yoluna
/// gelmemeli. O bayrak yeniden giriş kapısı: 402 bir KULLANICI eylemi
/// değil sunucu cevabı, aynı anda uçuştaki birden çok istek (ekran
/// açılışında üç sağlayıcı birden sorar) her biri için ayrı 402
/// döndürebilir ve bayrak olmasa her biri bir paywall iterdi. Dokunuş tek
/// bir kullanıcı niyeti — bir basış, bir rota; ikinci basış ilk rota
/// kapanmadan gelemez. Kesinti yolunu `acPaywall` ile açan çağıran, bayrağı
/// kendi tutar (bugün yalnız `api.dart`).
Future<bool?> acPaywall(
  BuildContext context, {
  required PaywallKaynak kaynak,
  PlusOzellik? ozellik,
  String? reason,
}) {
  final ekran =
      PaywallScreen(kaynak: kaynak, ozellik: ozellik, reason: reason);
  final Route<bool> rota = kaynak.kesinti
      ? MaterialPageRoute<bool>(builder: (_) => ekran, fullscreenDialog: true)
      : FadeThroughRoute<bool>(builder: (_) => ekran);
  return Navigator.of(context).push(rota);
}

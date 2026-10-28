/// Alt sayfa kabuğu — `showModalBottomSheet`in tek giriş kapısı.
///
/// NEDEN: aynı kabuk yedi yerde birebir kopyaydı (atlas_detail ×3,
/// basis_sheet, friends ×3) ve iki yerde tutamak çizimi ayrıca
/// tekrarlanıyordu. Kopyalar bir şeyi EKSİK bırakarak ayrışıyordu:
/// takvim gün kartında kaydırma sarmalayıcısı yoktu ve 320×640'ta 1162 px
/// içerik SESSİZCE kırpılıyordu (ölçüldü); arkadaş ekleme sayfasında
/// klavye dolgusu dıştaki context'ten okunuyor ve 0 kalıyordu. Kabuk tek
/// olunca bu iki kapı her sayfada kendiliğinden var.
library;

import 'package:flutter/material.dart';

import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';

/// Alt sayfayı açar; `showModalBottomSheet<T>` ile aynı dönüşü verir.
///
/// * Zemin `inkLight`, üst köşeler kart yarıçapı, kontur `glassStroke`.
/// * Üstte [SheetTutamak], varsa [baslik]; sonra [builder]ın gövdesi.
/// * [scrollable] (varsayılan): gövde `SingleChildScrollView` içinde —
///   ekrandan uzun içerik kaydırılır, kırpılmaz. Yalnız içeriği KENDİSİ
///   kaydıran sayfa (`ListView` gövdeli) `false` verir; iç içe iki
///   kaydırıcı dıştakini kilitler.
/// * [klavyeyeUy]: giriş alanı taşıyan sayfa `true` verir; alt dolgu
///   klavye kadar büyür. Dolgu SAYFANIN context'inden okunur — dıştaki
///   context klavye açılınca yeniden kurulmuyor, dolgu 0 kalıyordu.
/// * [enableDrag]: aşağı sürükleyerek kapatma. Sürükleme `PopScope`a
///   SORMADAN kapatır (SDK `bottom_sheet.dart` `onClosing` → `pop`); uçuşta
///   bir işi olan sayfa (hesap silme) onu kapatır.
///
/// `isScrollControlled` hep açık: sayfanın 9/16 tavanı kalkar, uzun içerik
/// ekranı kullanır. `useSafeArea` da açık: tavan kalkınca tam boy sayfa
/// durum çubuğunun altına girerdi.
Future<T?> showRythoSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollable = true,
  bool klavyeyeUy = false,
  bool enableDrag = true,
  String? baslik,
}) {
  return showModalBottomSheet<T>(
    context: context,
    enableDrag: enableDrag,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: RythoColors.inkLight,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(RythoRadius.card)),
      side: BorderSide(color: RythoColors.glassStroke),
    ),
    builder: (sheetContext) {
      Widget govde = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTutamak(),
          // Üst kenar ışığı (GlassPanel ile aynı dil): düz inkLight zemin +
          // gri tutamak "soğuk" okunuyordu (cihaz bulgusu, 2026-10-14).
          // Kabuk rengi/biçimi aynı; sıcaklık kenar ışığı ve lila tutamakla.
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(
                horizontal: RythoSpace.xxl, vertical: RythoSpace.sm),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                RythoColors.lilac,
                Colors.transparent,
              ]),
            ),
          ),
          if (baslik != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  RythoSpace.lg, RythoSpace.md, RythoSpace.lg, 0),
              child: Semantics(
                header: true,
                child: Text(baslik, style: RythoType.sheetTitle),
              ),
            ),
          builder(sheetContext),
        ],
      );
      if (scrollable) govde = SingleChildScrollView(child: govde);
      // Üst güvenli alan `useSafeArea` ile rotada düşüldü; burada yalnız
      // alt (ev çubuğu) kalıyor.
      govde = SafeArea(top: false, child: govde);
      if (klavyeyeUy) {
        // Kaydırıcının DIŞINDA: klavye açılınca kaydırma alanı küçülür ve
        // alan hâlâ erişilebilir kalır; içeride olsa son satır klavyenin
        // altında kalırdı.
        govde = Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: govde,
        );
      }
      return govde;
    },
  );
}

/// Alt sayfa tutamağı: 36×4 çizgi, üstte `md` nefes.
///
/// Dekoratif — ekran okuyucuya hiçbir şey söylemez, o yüzden semantikten
/// dışlanır. Üst boşluk tutamağın kendisinde: tutamak hep sayfanın ilk
/// öğesi, sayfa gövdesi kendi üst dolgusunu ayrıca verir.
class SheetTutamak extends StatelessWidget {
  const SheetTutamak({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: RythoSpace.md),
          child: Center(
            child: Container(
              width: 36,
              height: RythoSpace.xs,
              decoration: BoxDecoration(
                // Lila tutamak: gri çizgi kabuğu "sistem diyaloğu" gibi
                // gösteriyordu; vurgu rengi kabuğu uygulamanın parçası yapar.
                color: RythoColors.lilac.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(RythoRadius.xs),
              ),
            ),
          ),
        ),
      );
}

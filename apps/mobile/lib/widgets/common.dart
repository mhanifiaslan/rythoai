/// Her ekranda yeniden yazılan desenlerin ortak hâli.
///
/// Aşağıdakilerin hepsi kod tabanında birden fazla kez, birbirinden hafifçe
/// farklı biçimde tekrar yazılmıştı. Fark küçük olduğu için kimse bakıp
/// "burası tutarsız" demiyor; ama üst üste gelince kullanıcının "dağınık"
/// dediği his tam olarak bu oluyor.
///
/// * Bölüm başlığı: Gökyüzü `fromLTRB(20,14,20,6)` kullanıyordu, Arkadaşlar
///   `fromLTRB(20,4,20,2)` — aynı rol, iki ayrı ritim.
/// * Hata kartı: Gökyüzü'nde `_ErrorCard`, arkadaş detayında ayrı bir panel.
/// * Boş durum: yalnızca sohbette vardı, ötekiler düz metin gösteriyordu.
/// * Etiket-değer satırı: profilde ve yüz sekmesinde iki ayrı `_row`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
// `when` bir uzantı metodu; yalnız `AsyncValue` gösterilirse derlenmez.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart' show friendlyError;
import '../features/profile/feedback_screen.dart';
import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'glass.dart';
import 'motion.dart';

/// Bölüm başlığı — "Bugün senin için", "Şu an", "Araçlar".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;

  /// Sağ uçta küçük ikincil bilgi (tarih, sayaç).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          RythoSpace.xl, RythoSpace.lg, RythoSpace.xl, RythoSpace.sm),
      // Cihaz bulgusu: dar ekranda (360 dp) ve büyük yazı ölçeğinde uzun
      // başlık + sağdaki ek bilgi tek satıra sığmıyor, sağ taraf ekran
      // dışına taşıyordu ("Bugün gökyüzünde senin için ✦ En yak…").
      // Eski hâli `Row` + `Spacer` idi: iki çocuk da esnemiyordu.
      //
      // `Wrap` + `spaceBetween` ikisini de verir: SIĞIYORSA başlık solda,
      // ek bilgi sağda (tek satır, eski görünüm); SIĞMIYORSA ek bilgi alt
      // satıra iner ve başlık kendi içinde sarar. Ölçüm kodu gerekmez,
      // metin kısaltılmaz — kullanıcı cümlenin tamamını okur.
      //
      // ⚠️ `Wrap` gevşek kısıtta çocuklarının genişliğine BÜZÜLÜR; o hâlde
      // `spaceBetween` yayacak boşluk bulamaz ve ek bilgi başlığa yapışır.
      // `SizedBox(width: infinity)` tam genişliği verir.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: RythoSpace.md,
          runSpacing: RythoSpace.xs,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(title, style: RythoType.sectionTitle),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Hata kartı — isteğe bağlı yeniden deneme.
///
/// Hata metni `friendlyError()` ile üretilmiş olmalı; ham `DioException`
/// metnini basmak kullanıcıya HTTP durum kodu göstermek demek.
class ErrorCard extends StatelessWidget {
  const ErrorCard({
    super.key,
    required this.message,
    this.onRetry,
    this.screen,
    this.reportable = true,
  });

  final String message;
  final VoidCallback? onRetry;

  /// "Bu ekranı bildir" için ekran kodu (bkz. [FeedbackScreen.screen]);
  /// verilmezse kullanıcı ekranı formdan seçer.
  final String? screen;

  /// GB-turu: hata kartı geri bildirim kanalının EN UCUZ girişi — kullanıcı
  /// tam da sorunu gördüğü anda "bildir" diyebilir. Kapatmak isteyen ekran
  /// (ör. bildirimin kendisi düşmüşken) `false` verir.
  final bool reportable;

  @override
  Widget build(BuildContext context) {
    final ingilizce = Localizations.localeOf(context).languageCode == 'en';
    // Nullable arama: bu kart l10n temsilcisi olmayan ağaçlarda da
    // çizilebiliyor (eski testler) — `AppLocalizations.of` orada fırlatır.
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final kart = GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 18, color: RythoColors.madder),
              const SizedBox(width: RythoSpace.sm),
              Expanded(child: Text(message, style: RythoType.bodyDim)),
            ],
          ),
          if (onRetry != null || reportable) ...[
            const SizedBox(height: RythoSpace.sm),
            // İki düğme (bildir + tekrar dene) dar ekranda ve büyük yazı
            // ölçeğinde tek satıra sığmıyordu — 320 dp × 1,3'te 267 px
            // taşıyordu (bekçi: test/dar_ekran_test.dart). `Wrap` sığdığında
            // yan yana, sığmadığında alt alta dizer.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: RythoSpace.xs,
              children: [
                if (reportable)
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => FeedbackScreen(screen: screen)),
                    ),
                    child: Text(
                        l10n?.feedbackReportThisScreen ??
                            (ingilizce
                                ? 'Report this screen'
                                : 'Bu ekranı bildir'),
                        style: RythoType.button
                            .copyWith(color: RythoColors.parchmentDim)),
                  ),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    child: Text(
                        l10n?.retry ??
                            (ingilizce ? 'Try again' : 'Tekrar dene'),
                        style: RythoType.button),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
    if (reduceMotion(context)) return kart;
    // Girişte TEK küçük sarsıntı (R12-C3): hata fark edilir, panik
    // yaratmaz. Döngü yok.
    return kart
        .animate()
        .shake(hz: 3, offset: const Offset(3, 0), duration: 400.ms);
  }
}

/// Sayfa içi asenkron bölüm: yükleniyor → iskelet, hata → [ErrorCard],
/// veri → [veri], boş veri → hiçbir şey.
///
/// NEDEN: ana ekranda sinyal ve takvim bölümleri `provider.value ?? []`
/// okuyup boşsa kendini gizliyordu (sky_screen, calendar_strip). Hata da
/// `value == null` olduğu için AYNI yoldan geçiyordu — "bugün sinyal yok"
/// ile "yükleme düştü" ekranda ayırt edilemiyordu ve kullanıcı düşen bir
/// isteği yeniden deneyemiyordu. Üç hâl tek yerde ayrılınca her bölümün
/// kendi `when`ini yazıp hata dalını unutması mümkün değil.
///
/// Aşağı çekme tazelemesinde (`ref.refresh`) iskelet FLAŞLAMAZ: eldeki
/// veri yeni veri gelene kadar ekranda kalır (`skipLoadingOnRefresh`).
/// Yüklenirken boş kutu ya da iskelet görünmesi düzeni zıplatır.
class AsyncBolum<T> extends StatelessWidget {
  const AsyncBolum({
    super.key,
    required this.durum,
    required this.veri,
    required this.onRetry,
    this.iskeletYuksekligi = 96,
    this.bosMu,
    this.ekranKodu,
  });

  final AsyncValue<T> durum;

  /// Veri geldiğinde çizilecek gövde.
  final Widget Function(T) veri;

  /// Hata kartındaki "Tekrar dene" — çağıran sağlayıcıyı geçersiz kılar.
  final VoidCallback onRetry;

  /// Yükleme iskeletinin yüksekliği; bölümün gerçek hacmine yakın olmalı
  /// ki cevap gelince düzen zıplamasın.
  final double iskeletYuksekligi;

  /// Veri "boş" sayılır mı — boşsa bölüm kendini gizler (sinyal listesi
  /// boşken ana ekran bölümsüz ayakta durur). Verilmezse veri hep çizilir.
  final bool Function(T)? bosMu;

  /// "Bu ekranı bildir" için ekran kodu. VERİLİRSE bildir düğmesi açılır;
  /// verilmezse kapalı — bölüm hatası ekranın tamamı değil, her geçici
  /// düşüşte bildir çağrısı gürültü olur. Ekranını adlandıran çağıran bu
  /// kararı bilerek veriyor.
  final String? ekranKodu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return durum.when(
      skipLoadingOnRefresh: true,
      loading: () => SkeletonPanel(height: iskeletYuksekligi),
      error: (e, _) => ErrorCard(
        message: friendlyError(e, l10n),
        onRetry: onRetry,
        screen: ekranKodu,
        reportable: ekranKodu != null,
      ),
      data: (v) =>
          bosMu?.call(v) == true ? const SizedBox.shrink() : veri(v),
    );
  }
}

/// Boş durum — içerik yokluğunu AÇIKLAYAN ekran parçası.
///
/// Boş bir alan bırakmak kullanıcıya "bir şey bozuldu" hissi veriyor; ne
/// olduğunu ve ne yapabileceğini söylemek gerekiyor.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    this.description,
    this.action,
  });

  final String emoji;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // Kademeli giriş (R12-C3): amblem pop'la, metinler reveal'le gelir —
    // TEK atış; 8+ ekrandaki boş durum tek dokunuşta ısındı.
    Widget amblem = Text(emoji, style: const TextStyle(fontSize: 34));
    if (!reduceMotion(context)) {
      amblem = amblem
          .animate()
          .fadeIn(duration: RythoMotion.base)
          .scale(
              begin: const Offset(0.7, 0.7),
              end: const Offset(1, 1),
              duration: const Duration(milliseconds: 400),
              curve: RythoMotion.pop);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: RythoSpace.xl, vertical: RythoSpace.xxl),
      child: Column(
        children: [
          amblem,
          const SizedBox(height: RythoSpace.md),
          RythoReveal(
            index: 1,
            child: Text(title,
                style: RythoType.cardTitle, textAlign: TextAlign.center),
          ),
          if (description != null) ...[
            const SizedBox(height: RythoSpace.sm),
            RythoReveal(
              index: 2,
              child: Text(description!,
                  style: RythoType.bodyDim, textAlign: TextAlign.center),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: RythoSpace.lg),
            RythoReveal(index: 3, child: action!),
          ],
        ],
      ),
    );
  }
}

/// Ayar/gezinme satırı: solda başlık (+açıklama), sağda değer ve chevron.
///
/// Profil ekranının iki seviyeli hâlinin yapı taşı. Önceki hâlde 14 kontrol
/// tek sayfada satır satır duruyordu; artık her grup kendi sayfasını açıyor.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String? subtitle;

  /// Sağda gösterilen mevcut değer — ör. doğum tarihi.
  final String? value;
  final IconData? icon;
  final VoidCallback? onTap;

  /// `trailing` verilirse chevron yerine bu gösterilir (ör. `Switch`).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RythoRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: RythoSpace.lg, vertical: RythoSpace.md),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 19, color: RythoColors.lilac),
              const SizedBox(width: RythoSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: RythoType.body),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: RythoType.caption),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: RythoSpace.sm),
              // Değer (şehir, tarih, dil adı) uzun olabilir ve esnemezse
              // satırı taşırır; başlık zaten Expanded olduğu için taşma
              // sessizce sağ kenardan kırpılıyordu.
              Flexible(
                child: Text(value!,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    style: RythoType.dataSmall),
              ),
            ],
            if (trailing != null)
              trailing!
            else if (onTap != null) ...[
              const SizedBox(width: RythoSpace.xs),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: RythoColors.parchmentDim),
            ],
          ],
        ),
      ),
    );
  }
}

/// Etiket-değer satırı — salt okunur veri gösterimi.
class LabelValueRow extends StatelessWidget {
  const LabelValueRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      // `Row` + `spaceBetween` ile iki esnemeyen metin, uzun etiket/değer
      // çiftinde satırı taşırıyordu (SectionHeader ile aynı kusur sınıfı).
      // `Wrap`: sığdığında etiket solda değer sağda — eski görünüm; aksi
      // hâlde değer alt satıra iner. Hiçbir metin kırpılmaz.
      // `SizedBox`: Wrap gevşek kısıtta büzülür, spaceBetween işlemez.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: RythoSpace.md,
          runSpacing: 2,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(label, style: RythoType.bodyDim),
            Text(value, style: RythoType.data),
          ],
        ),
      ),
    );
  }
}

/// Dokuz okuma yüzeyinin TEK kabı — bir `OkumaDurumu`yu çizer.
///
/// ## Neden var
/// Ölçüldü (2026-10-10): dokuz LLM okuma yüzeyi dört ayrı kap kullanıyordu
/// (çıplak `MarginNote`, `GlassPanel` içinde `MarginNote`, `ReadingCard`,
/// ekrana özel panel) ve beşi `fallback` bayrağını HİÇ okumuyordu: sunucunun
/// şablon paragrafı rapor gibi duruyor, Yıl Haritası o şablonu paylaşım
/// kartına bile basıyordu. Bayrağı okuyan tek fonksiyon
/// `okumaDurumuFromYanit` (core/okuma_durumu.dart); onu ÇİZEN tek widget
/// burası. Dokuz ekran kendi kabını kurduğunda biri her zaman eksik kalıyor.
///
/// ## Yapısal güvence
/// Paylaşım düğmesi yalnız `OkumaHazir` dalında kurulur; `OkumaUretilemedi`
/// dalından paylaşıma giden bir yol YOK. "Şablon kart olamaz" kuralını
/// çağıranın hatırlaması değil, dalın şekli garantiler.
library;

import 'package:flutter/material.dart';

import '../core/api.dart' show RaporUretilemedi, friendlyError;
import '../core/okuma_durumu.dart';
import '../features/share/share_card.dart' show shareReportCard;
import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'atlas_widgets.dart' show MarginNote, RythoyaSor;
import 'common.dart' show ErrorCard;
import 'markdown_text.dart' show markdownToPlain;
import 'motion.dart' show StagedWaiting;
import 'nebula_widgets.dart' show Pressable;

/// Paylaşım kartının tarifi — `shareReportCard`ın girdileri.
///
/// [body] verilmezse kabın GÖSTERDİĞİ metnin markdown'dan arındırılmış hâli
/// gider: ekranda okunan ile karta basılan aynı metin olur ve karta `###`
/// basılmaz (o kusur bir kez ölçüldü, markdown_text.dart). Çağıran farklı
/// bir gövde isterse (ör. kısaltılmış özet) açıkça verir.
class PaylasimTarifi {
  const PaylasimTarifi({
    required this.title,
    required this.dateLabel,
    this.body,
    this.badges = const [],
    this.glyph,
  });

  final String title;
  final String? body;
  final String dateLabel;

  /// (etiket, değer) çiftleri — kart en fazla üçünü çizer.
  final List<(String, String)> badges;
  final String? glyph;
}

class OkumaKabi extends StatelessWidget {
  const OkumaKabi({
    super.key,
    required this.durum,
    required this.ekranKodu,
    this.baslik,
    this.onTekrarDene,
    this.onSor,
    this.paylasim,
    this.beklemeAsamalari,
    this.kilit,
  });

  final OkumaDurumu durum;

  /// Hata kartındaki "Bu ekranı bildir" için ekran kodu
  /// (`FeedbackScreen.screen`). Zorunlu: geri bildirim kanalının en ucuz
  /// girişi tam da okumanın düştüğü an ve ekran adı olmadan o bildirim
  /// kimsenin işine yaramıyor.
  final String ekranKodu;

  /// `MarginNote` başlığı.
  final String? baslik;

  /// Üretilemedi / hata dalındaki "Tekrar dene". Verilmezse düğme çıkmaz.
  final VoidCallback? onTekrarDene;

  /// "Rytho'ya sor" kapısı; yalnız hazır okumada çizilir.
  final VoidCallback? onSor;

  /// Verilirse hazır okumanın altında paylaş düğmesi çıkar. Üretilemedi
  /// dalı bu alanı HİÇ okumaz (bkz. kütüphane notu).
  final PaylasimTarifi? paylasim;

  /// Bekleme sahnesinin aşama metinleri. Verilmezse tek genel aşama.
  final List<String>? beklemeAsamalari;

  /// Kilitli hâlde çizilecek kart (`PlusLockedCard`) — çağıran verir;
  /// kap paywall'ı bilmez.
  final Widget? kilit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (durum) {
      OkumaYukleniyor() => _bekleme(l10n),
      OkumaHazir(:final metin) => _hazir(context, l10n, metin),
      OkumaUretilemedi(:final iadeli) => _hataKarti(
          l10n, RaporUretilemedi(jetonIadeEdildi: iadeli)),
      OkumaHata(:final hata) => _hataKarti(l10n, hata),
      OkumaKilitli() => kilit ?? const SizedBox.shrink(),
    };
  }

  Widget _bekleme(AppLocalizations l10n) {
    final verilen = beklemeAsamalari;
    // Uydurma yüzde yok (StagedWaiting gerekçesi); aşama verilmemişse tek
    // genel cümle — boş metin "takıldı" hissi verir.
    final asamalar = (verilen == null || verilen.isEmpty)
        ? [l10n.onboardingStage1]
        : verilen;
    return StagedWaiting(stages: asamalar);
  }

  /// Üretilemedi ve ağ hatası AYNI kartı giyer; cümle `friendlyError`dan
  /// gelir — iade bilgisi `RaporUretilemedi.jetonIadeEdildi` ile sunucudan,
  /// istemcide varsayım yok.
  Widget _hataKarti(AppLocalizations l10n, Object hata) => ErrorCard(
        message: friendlyError(hata, l10n),
        screen: ekranKodu,
        onRetry: onTekrarDene,
      );

  Widget _hazir(BuildContext context, AppLocalizations l10n, String metin) {
    final tarif = paylasim;
    final sor = onSor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarginNote(title: baslik, text: metin),
        if (tarif != null || sor != null) ...[
          const SizedBox(height: RythoSpace.sm),
          // İki kapı dar ekran + büyük yazı ölçeğinde tek satıra sığmayabilir;
          // `Wrap` sığdığında yan yana, sığmadığında alt alta dizer.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (tarif != null)
                _PaylasKapisi(
                  onTap: () => shareReportCard(
                    context,
                    title: tarif.title,
                    body: tarif.body ?? markdownToPlain(metin),
                    dateLabel: tarif.dateLabel,
                    badges: tarif.badges,
                    glyph: tarif.glyph,
                  ),
                ),
              if (sor != null) RythoyaSor(onTap: sor),
            ],
          ),
        ],
      ],
    );
  }
}

/// Paylaş kapısı — `RythoyaSor` ile aynı ağırlıkta bir DAVET: altın düğme
/// değil (o, satın alma/onay gibi birincil eylemlere ayrılmış). Dokunma
/// alanı dikey dolguyla ≥ 44 px'e çıkarılır; metin tek başına 20 px'lik bir
/// hedef bırakırdı.
class _PaylasKapisi extends StatelessWidget {
  const _PaylasKapisi({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: RythoSpace.lg, vertical: RythoSpace.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.ios_share_rounded,
                  size: 16, color: RythoColors.lilac),
              const SizedBox(width: RythoSpace.xs),
              Text(l10n.shareReading,
                  style: RythoText.body(13,
                      color: RythoColors.lilac, w: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

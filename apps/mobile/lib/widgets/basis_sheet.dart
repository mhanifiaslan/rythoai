import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'alt_sayfa.dart' show showRythoSheet;
import 'motion.dart' show reduceMotion;
import 'nebula_widgets.dart' show Pressable;

/// Tema anahtarı -> ikon. Anahtarlar sunucudaki signal_service.THEMES ile
/// aynı; sinyal kartları ve takvim günleri aynı işareti kullanır.
const kThemeIcons = {
  'career': '💼',
  'relationships': '❤️',
  'inner': '🌙',
  'finance': '🪙',
};

/// "Neden?" alt-sayfası (R2-S2): bir sinyalin DAYANAĞI.
///
/// Sıra ÖNCE ANLAM: yorum → geldiği yerin tek satırlık ifadesi → katlanmış
/// ölçüm tablosu → sohbet kapısı. Gerekçe sahip kararıdır (2026-10-03): bu
/// bir lifestyle ürünü, ölçüm disiplini KORUNUR ama her kullanıcıya
/// anlatılmaz — dayanağı SORAN kişi açar. Ölçülmemiş hiçbir satır hâlâ
/// çizilmiyor (alan yoksa satır atlanır), yani disiplin yerinde; kalkan şey
/// yalnız disiplinin reklamıydı.
///
/// Sunucu sözleşmesi: /api/v1/reports/signals yanıtındaki tek sinyal
/// (localize edilmiş alanlarıyla).
Future<void> showSignalBasisSheet(
  BuildContext context,
  Map<String, dynamic> signal, {
  VoidCallback? onAsk,
  String? title,
}) {
  // Kabuk ortak (`showRythoSheet`): zemin, köşe, tutamak ve kaydırma
  // sarmalayıcısı oradan gelir. Sarmalayıcı burada ŞART: gövde `min` bir
  // Column; katlanır bölme açıldığında içerik ekrandan uzun olabiliyor ve
  // sarmalayıcı olmadan taşma SESSİZ kırpılmaya dönüşür (kardeş desende
  // 131 px ölçüldü).
  return showRythoSheet<void>(
    context,
    builder: (_) => _BasisSheet(signal: signal, onAsk: onAsk, title: title),
  );
}

class _BasisSheet extends StatefulWidget {
  const _BasisSheet({required this.signal, this.onAsk, this.title});

  final Map<String, dynamic> signal;
  final VoidCallback? onAsk;

  /// Sayfa başlığı; verilmezse sinyal başlığı. Takvim günü aynı sayfayı
  /// "Bu tarih neden önemli?" başlığıyla kullanır (R2-Z1).
  final String? title;

  @override
  State<_BasisSheet> createState() => _BasisSheetState();
}

class _BasisSheetState extends State<_BasisSheet> {
  /// Teknik bölmenin açıklığı. VARSAYILAN KAPALI (K1): teknik katman aynı
  /// sayfada durur ama kendini dayatmaz.
  bool _acik = false;

  @override
  Widget build(BuildContext context) {
    final signal = widget.signal;
    final l10n = AppLocalizations.of(context);

    final gokyuzu = [
      signal['transit_local'] ?? signal['transit'],
      if (signal['movement_local'] != null) signal['movement_local'],
    ].whereType<String>().join(' · ');

    final natalParcalar = <String>[
      (signal['natal_local'] ?? signal['natal'] ?? '') as String,
      if (signal['natal_sign_local'] is String)
        signal['natal_sign_local'] as String,
      if (signal['natal_house'] is int)
        l10n.basisHouse((signal['natal_house'] as num).toInt()),
    ];

    final orb = signal['orb'];

    // Başlığın altında KARTTAKİ CÜMLE durur (R3-1) — kullanıcı hangi
    // cümleye "neden" sorduysa onu görür. Eski sürüm bu cümleyi sayfanın
    // ALTINDA "Rytho'nun yorumu" kutusuyla BİR KEZ DAHA basıyordu: cihaz
    // ekran görüntüsünde aynı paragraf iki kez, aralarında teknik tablo.
    // Silinen o alt kutudur, bu değil — böylece R3-1 bulgusu korunur ve
    // tekrar biter.
    final yorum = (signal['card_text'] as String?) ??
        (signal['headline'] as String? ?? '');

    // Kaynak cümlesi: ölçümün kendi ifadesi ("Satürn, natal Ay ile Kare
    // açısını ... kesinleştiriyor"). Katlanır bölmedeki ÖLÇÜM satırından
    // BURAYA terfi etti; iki yerde birden basılsa sayfa yine bir şeyi iki
    // kez yazardı.
    //
    // ⚠️ `insight` boşken sunucu `headline`ı `technical` ile AYNI döndürüyor
    // (backend/services/prompts: `insan = teknik`, test_signals ile
    // çivili). O hâlde yorum slotu ZATEN ölçüm cümlesidir; aşağıya bir kez
    // daha yazmak sahibin şikâyet ettiği tekrarın ikinci hâlidir. Eşitse
    // kaynak satırı çizilmez — dayanak katlanır bölmede durmaya devam eder.
    final teknik = signal['technical'] as String?;
    final kaynakGoster = teknik != null &&
        teknik.trim().isNotEmpty &&
        teknik.trim() != yorum.trim();

    final satirlar = <Widget>[
      OlcumSatiri(etiket: l10n.basisSky, deger: gokyuzu),
      OlcumSatiri(
          etiket: l10n.basisNatal,
          deger: natalParcalar.where((p) => p.isNotEmpty).join(' · ')),
      OlcumSatiri(
          etiket: l10n.basisAspect,
          deger: (signal['aspect_local'] ?? signal['aspect'] ?? '') as String),
      if (orb is num)
        OlcumSatiri(etiket: l10n.basisOrb, deger: '${orb.toString()}°'),
      if (signal['exact_on_local'] is String)
        OlcumSatiri(
            etiket: l10n.basisExact,
            deger: signal['exact_on_local'] as String,
            vurgu: true),
      // Kaynak dipnotu KATLANIR BÖLMENİN İÇİNDE: efemeris/orb açıklaması
      // dayanağı SORAN kişinin cevabıdır. Dışarıda dururken herkese
      // basılan bir öz-reklam gibi okunuyordu (sahip bulgusu).
      const SizedBox(height: RythoSpace.sm),
      Text(l10n.basisFootnote,
          style: RythoText.body(11.5,
              color: RythoColors.parchmentDim, height: 1.4)),
    ];

    // Güvenli alan ve tutamak kabuktan geliyor (`showRythoSheet`).
    return Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.lg, RythoSpace.md, RythoSpace.lg, RythoSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title ?? l10n.basisSheetTitle,
                style: RythoType.sheetTitle),
            const SizedBox(height: 10),
            // Okuma yüzeyinin hazır rolü: 15 / 1,65. Burada `body(13)` ile
            // çizilirken sayfanın ASIL metni teknik tablodan daha küçük
            // görünüyordu — hiyerarşi anlamın aleyhineydi.
            Text(yorum, style: RythoType.reading),
            if (kaynakGoster) ...[
              const SizedBox(height: 10),
              Text(teknik.trim(),
                  style: RythoText.mono(11.5,
                      color: RythoColors.parchmentDim)),
            ],
            const SizedBox(height: RythoSpace.md),
            Pressable(
              onTap: () => setState(() => _acik = !_acik),
              child: Text('${l10n.signalWhy} ${_acik ? '▴' : '▾'}',
                  style: RythoText.body(11.5,
                      color: RythoColors.parchmentDim, w: FontWeight.w600)),
            ),
            // Emsal (relationship_screen) burada `AnimatedCrossFade` +
            // çıplak `Duration(milliseconds: 220)` kullanıyor. İki şey
            // bilerek kopyalanmadı:
            //
            // 1. Süre/eğri çıplak yazılmadı — design-system "yeni kod
            //    çıplak süre yazmaz" diyor ve her hareketi `reduceMotion`
            //    kapısından geçirmeyi şart koşuyor.
            // 2. `AnimatedCrossFade` İKİ ÇOCUĞU DA koşulsuz monte ediyor
            //    (Flutter kaynağında okundu: görünmeyen dal yalnız
            //    `FadeTransition` opaklık 0 + `IgnorePointer` ile sarılı,
            //    ağaçtan DÜŞMÜYOR). Yani "kapalı" hâlde ölçüm satırları
            //    hâlâ kuruluyor ve yokluklarını arayan bir bekçi
            //    YAZILAMIYOR — teknik tablonun kapalıyken sızdığı bir
            //    gerileme sessiz kalırdı. `AnimatedSize` + koşullu çocuk
            //    aynı görünümü verir, kapalıyken satırlar GERÇEKTEN yok.
            AnimatedSize(
              alignment: Alignment.topCenter,
              duration:
                  reduceMotion(context) ? Duration.zero : RythoMotion.base,
              curve: RythoMotion.enter,
              child: !_acik
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [const SizedBox(height: 6), ...satirlar],
                    ),
            ),
            if (widget.onAsk != null) ...[
              const SizedBox(height: RythoSpace.md),
              // Birincil eylem ALT KENARDA — §9c'nin YERLEŞİM kuralı
              // ("en sık yapılan eylem AppBar'da değil alt kenarda",
              // cihaz hükmüyle kazanılmış). Eski sırada dipnotun ALTINDA,
              // yani kuyrukta duruyordu (git HEAD'de ölçüldü).
              //
              // ⚠️ §9c'nin BİÇİM şartı (degrade hap, 48 dp,
              // mediumImpact) bilerek uygulanmadı ve bu bir uyum iddiası
              // DEĞİL: o şart bir EKRANIN kendi eylemi için yazıldı,
              // burası bir alt sayfa. Biçim yayında olan kardeş yüzeyden
              // alındı (relationship_screen: `Pressable` + metin bağı).
              // Eski hâli `OutlinedButton.icon`du — Material teması kendi
              // rengini/gölgesini dayatır, §9c bunu zaten reddediyor.
              // Alt sayfada hangi biçimin daha iyi olduğu ÖLÇÜLMEDİ.
              Pressable(
                onTap: widget.onAsk,
                child: Text('✦ ${l10n.signalAsk} →',
                    style: RythoText.body(13,
                        color: RythoColors.lilac, w: FontWeight.w600)),
              ),
            ],
          ],
        ),
    );
  }
}

/// Ölçüm satırı: solda sabit genişlikte etiket, sağda değer.
///
/// Dayanak sayfasının ve atlas alt sayfalarının ortak satırı (atlas
/// kopyası D6'da buna geçer). Etiket BÜYÜK HARFE ÇEVRİLMEZ: eski hâl
/// `toUpperCase()` çağırıyordu ve Türkçe'de `i` → `I` düşüyordu
/// ("kesinleşme" → "KESINLEŞME"). Rol tipografisi (`RythoType.label`)
/// zaten etiket ağırlığını ve aralığını veriyor; büyük harf gerekmiyor.
///
/// Değer boşsa satır HİÇ çizilmez — ölçülmemiş alan boş etiket olarak
/// bile sunulmaz.
class OlcumSatiri extends StatelessWidget {
  const OlcumSatiri(
      {super.key,
      required this.etiket,
      required this.deger,
      this.vurgu = false});

  final String etiket;
  final String deger;

  /// Altın vurgu — kesinleşme tarihi gibi günün çapası olan değer.
  final bool vurgu;

  @override
  Widget build(BuildContext context) {
    if (deger.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(etiket, style: RythoType.label),
          ),
          const SizedBox(width: RythoSpace.sm),
          Expanded(
            child: Text(
              deger,
              style: RythoText.body(13.5,
                  color: vurgu ? RythoColors.gold : RythoColors.parchment),
            ),
          ),
        ],
      ),
    );
  }
}

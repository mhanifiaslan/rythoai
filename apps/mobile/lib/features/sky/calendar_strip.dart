import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/alt_sayfa.dart';
import '../../widgets/basis_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../widgets/nebula_widgets.dart' show Pressable;
import '../chat/chat_screen.dart';
import '../paywall/kilit_rozeti.dart';
import '../paywall/paywall_acilis.dart';

/// Ana ekrandaki **30 günlük takvim şeridi** (R5-6).
///
/// ## Neden burada
///
/// Takvim daha önce yalnız Atlas'ın içindeki bir ekranda, uzun bir olay
/// listesi olarak yaşıyordu; kullanıcı oraya ancak arayarak gidiyordu.
/// Oysa "önündeki günlerde ne var" günlük bir soru. Şerit burç şeridinin
/// hemen altında, aynı ölçü diliyle duruyor: tek satır, yatay kaydırmalı,
/// dokununca gün kartı.
///
/// ## Ücretsiz katman
///
/// Şerit ücretsiz kullanıcıya da GÖRÜNÜR. Sunucu gerçek tarihleri ve
/// gerçek temaları gönderiyor, yalnız okuma satırlarını çıkarıp olaya
/// `locked: true` koyuyor. Yani teaser uydurma değil: gördüğü gün doğru,
/// gördüğü tema doğru; eksik olan yorum. Kilit gün kartında açıklanıyor.
///
/// ## Üç hâl (D5, G2)
///
/// Eskiden `takvim.value == null` tek kapıydı: "henüz yüklenmedi", "istek
/// düştü" ve "doğum kaydı yok" üçü de aynı boşluğa düşüyordu — kullanıcı
/// düşen bir isteği yeniden deneyemiyordu ve yükleme anında şerit
/// kaybolup düzeni zıplatıyordu. [AsyncBolum] üçünü ayırır: iskelet /
/// hata kartı + tekrar dene / veri. Boş veri (doğum kaydı eksik, olay yok)
/// yine kendini gizler — ana ekran şeritsiz de ayakta durur.
class CalendarStrip extends ConsumerWidget {
  const CalendarStrip({super.key});

  /// Şeritte gösterilen gün sayısı — sunucudaki `TRANSIT_CALENDAR_DAYS`
  /// ile aynı ufuk. Sunucu daha uzun bir pencere gönderse bile şerit
  /// bu sayıda hücre çizer.
  static const int gunSayisi = 30;

  /// Şerit yüksekliği; iskelet de aynı hacmi tutar ki cevap gelince düzen
  /// zıplamasın. 66 → 72 (D5): ay etiketi 8 puntodan etiket rolüne (11)
  /// çıkınca hücre sütunu 320 dp × 1,3 ölçekte 2,8 px taştı (ölçüldü,
  /// sky_dar_ekran_test); etiketi geri küçültmek yerine hücre büyüdü.
  static const double yukseklik = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBolum<Map<String, dynamic>?>(
      durum: ref.watch(transitCalendarProvider),
      onRetry: () => ref.invalidate(transitCalendarProvider),
      iskeletYuksekligi: yukseklik,
      bosMu: (veri) => _olaylar(veri).isEmpty,
      veri: (veri) => _Serit(olaylar: _olaylar(veri)),
    );
  }

  static List<Map<String, dynamic>> _olaylar(Map<String, dynamic>? veri) =>
      List<Map<String, dynamic>>.from((veri?['events'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          const <Map<String, dynamic>>[]);

  static String _isoGun(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Veri gelmiş şerit: 30 hücre, dolu günler dokunulur.
class _Serit extends StatelessWidget {
  const _Serit({required this.olaylar});

  final List<Map<String, dynamic>> olaylar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Gün → o güne düşen olaylar. Tarih anahtarı sunucunun ISO metni;
    // yerel `DateTime` aritmetiğine çevirmek yaz saati sınırında günü
    // kaydırabilir, bu yüzden karşılaştırma METİN üzerinden.
    final gunlere = <String, List<Map<String, dynamic>>>{};
    for (final o in olaylar) {
      final g = '${o['date'] ?? ''}';
      if (g.isEmpty) continue;
      gunlere.putIfAbsent(g, () => []).add(o);
    }

    final bugun = DateTime.now();
    final gunler = [
      for (var i = 0; i < CalendarStrip.gunSayisi; i++)
        DateTime(bugun.year, bugun.month, bugun.day + i),
    ];

    // Şeridin görünür başlığı yok (burç şeridi gibi kendini anlatıyor);
    // ekran okuyucu için kap "Önündeki 30 gün" adını taşır — anahtar bir
    // tur boyunca ARB'de durup hiçbir yerden okunmuyordu.
    return Semantics(
      container: true,
      label: l10n.calendarStripTitle,
      child: SizedBox(
        height: CalendarStrip.yukseklik,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
          itemCount: gunler.length,
          separatorBuilder: (_, _) => const SizedBox(width: RythoSpace.sm),
          itemBuilder: (_, i) {
            final gun = gunler[i];
            final anahtar = CalendarStrip._isoGun(gun);
            final gununOlaylari = gunlere[anahtar] ?? const [];
            return _GunHucresi(
              gun: gun,
              bugunMu: i == 0,
              olaylar: gununOlaylari,
              onTap: gununOlaylari.isEmpty
                  ? null
                  : () => showDaySheet(context, gun, gununOlaylari),
            );
          },
        ),
      ),
    );
  }
}

/// Şeritteki tek gün.
///
/// Olaysız günler de çizilir — takvim ancak sürekli bir zaman şeridi
/// olduğunda takvimdir; yalnız dolu günleri göstermek onu bir listeye
/// geri çevirirdi. Olaysız gün soluk ve dokunulamaz; ekran okuyucuya da
/// "düğme" diye DUYURULMAZ (`enabled: false`) — eski hâl boş güne de
/// `button` bayrağı veriyor, TalkBack kullanıcısı çift dokunup hiçbir şey
/// olmadığını görüyordu.
///
/// Dolu günün adı "{tarih}, {tema}": görmeyen kullanıcı hücreye gelince
/// yalnız "12 Ekim" değil, o günün NE olduğunu da duyar. Gören kullanıcı
/// aynı bilgiyi ikondan okuyor.
class _GunHucresi extends StatelessWidget {
  const _GunHucresi({
    required this.gun,
    required this.bugunMu,
    required this.olaylar,
    this.onTap,
  });

  final DateTime gun;
  final bool bugunMu;
  final List<Map<String, dynamic>> olaylar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dolu = olaylar.isNotEmpty;
    final ikon = olaylar
        .map((o) => kThemeIcons[o['theme']])
        .whereType<String>()
        .firstOrNull;
    final tarih = _ayGun(context, gun);

    final kutu = ExcludeSemantics(
      child: Container(
        width: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RythoRadius.sm),
          color: dolu
              ? RythoColors.violet.withValues(alpha: 0.14)
              : Colors.transparent,
          border: Border.all(
            // Bugün altın halka; dolu günler soluk lila; boş günler
            // neredeyse görünmez bir çerçeve — şerit ritmi bozulmasın.
            color: bugunMu
                ? RythoColors.goldBright
                : dolu
                    ? RythoColors.lilac.withValues(alpha: 0.45)
                    : RythoColors.glassStroke,
            width: bugunMu ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Ay etiketi 8 puntoydu — bir lifestyle ekranında okunması
            // beklenen en küçük metin etiket rolünün altına inmez.
            Text(_ayKisa(context, gun),
                style: RythoType.label.copyWith(
                    color: bugunMu
                        ? RythoColors.goldBright
                        : RythoColors.parchmentDim)),
            const SizedBox(height: RythoSpace.xxs),
            Text('${gun.day}',
                style: RythoType.cardTitle.copyWith(
                    color: dolu || bugunMu
                        ? RythoColors.parchment
                        : RythoColors.parchmentDim)),
            const SizedBox(height: RythoSpace.xxs),
            // İkon satırı HER hücrede aynı yüksekliği tutar; yoksa dolu
            // ve boş günler farklı boyda çizilip şerit dalgalanır.
            SizedBox(
              height: RythoSpace.md,
              child: ikon != null
                  ? Text(ikon, style: RythoText.emoji(10))
                  : dolu
                      ? Container(
                          width: RythoSpace.xs,
                          height: RythoSpace.xs,
                          margin: const EdgeInsets.only(top: RythoSpace.xs),
                          decoration: const BoxDecoration(
                              color: RythoColors.lilac,
                              shape: BoxShape.circle),
                        )
                      : null,
            ),
          ],
        ),
      ),
    );

    if (!dolu) {
      return Semantics(label: tarih, enabled: false, child: kutu);
    }
    final temalar = {
      for (final o in olaylar)
        if (o['theme_local'] is String &&
            (o['theme_local'] as String).isNotEmpty)
          o['theme_local'] as String,
    };
    final tema = temalar.isEmpty
        ? l10n.calendarOtherEvents
        : temalar.join(', ');
    return Pressable(
      onTap: onTap,
      semanticLabel: '$tarih, $tema',
      child: kutu,
    );
  }
}

/// Gün kartı: o günün olayları **temaya göre başlıklı**.
///
/// Abonede her olay gündelik cümlesiyle ve "Neye dayanıyor?" girişiyle
/// gelir. Ücretsiz kullanıcıda tema başlığı ve tarih GÖRÜNÜR, okuma
/// satırının yerinde kilit satırı durur — gördüğü şey gerçek, göremediği
/// şey açıkça isimlendirilmiş.
///
/// Kabuk `showRythoSheet` (D3): kaydırma sarmalayıcısı oradan gelir. Bu
/// sayfa bir tur boyunca sarmalayıcısızdı ve 320×640 / yazı ölçeği
/// tavanında 1162 px içerik SESSİZCE kırpılıyordu (ölçüldü; bekçi
/// `calendar_strip_test.dart`). Kabuk tek olunca o kapı her sayfada var.
Future<void> showDaySheet(BuildContext context, DateTime gun,
    List<Map<String, dynamic>> olaylar) {
  return showRythoSheet<void>(
    context,
    // Başlık kabuğun işi (semantik `header` oradan gelir); gövde yalnız
    // olay kartlarını çizer.
    baslik: _ayGun(context, gun),
    builder: (_) => _GunSayfasi(gun: gun, olaylar: olaylar),
  );
}

class _GunSayfasi extends StatelessWidget {
  const _GunSayfasi({required this.gun, required this.olaylar});

  final DateTime gun;
  final List<Map<String, dynamic>> olaylar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Temaya göre grupla; temasız olaylar (istasyonlar) en sonda kendi
    // başlığı altında toplanır.
    final gruplar = <String, List<Map<String, dynamic>>>{};
    for (final o in olaylar) {
      gruplar.putIfAbsent('${o['theme'] ?? ''}', () => []).add(o);
    }
    final sirali = gruplar.keys.toList()
      ..sort((a, b) => a.isEmpty ? 1 : (b.isEmpty ? -1 : a.compareTo(b)));

    // Kilit satırı SAYFADA BİR KEZ çizilir. Eskiden her kilitli olay kendi
    // satırını basıyordu ve iki olaylı bir gün aynı cümleyi alt alta iki kez
    // gösteriyordu (cihaz turu, 1.5.1+18): tekrar bilgi vermiyor, yalnızca
    // kilidi olduğundan büyük gösteriyordu. Kaç olayın kilitli olduğu
    // başlıkların kendisinden zaten görülüyor.
    final kilitliSayisi =
        olaylar.where((o) => o['locked'] == true).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          RythoSpace.xl, RythoSpace.lg, RythoSpace.xl, RythoSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tema in sirali) ...[
            Row(children: [
              Text(kThemeIcons[tema] ?? '✦', style: RythoText.emoji(14)),
              const SizedBox(width: RythoSpace.sm),
              // Tema adı sunucudan gelir ve esnemiyordu; uzun adda
              // (büyük yazı ölçeğiyle birlikte) satırı taşırıyordu.
              Flexible(
                child: Text(
                    (gruplar[tema]!.first['theme_local'] as String?) ??
                        l10n.calendarOtherEvents,
                    style: RythoType.label.copyWith(color: RythoColors.lilac)),
              ),
            ]),
            const SizedBox(height: RythoSpace.sm),
            for (final o in gruplar[tema]!) _OlaySatiri(olay: o),
            const SizedBox(height: RythoSpace.md),
          ],
          if (kilitliSayisi > 0) const _KilitSatiri(),
        ],
      ),
    );
  }
}

/// Gün kartının tek kilit satırı — dokunuş paywall'ı açar.
///
/// Kilit rozeti tek kaynaktan ([KilitRozeti]); gri `lock_outline` kopyası
/// üç kilit dilinden biriydi. Paywall tek kapıdan ([acPaywall]): kaynak
/// etiketi "takvim günü" olarak sayılır ve rota türü (dokunuş → fade)
/// orada seçilir — eski `fullscreenDialog` burada "kesinti" dili
/// konuşuyordu, oysa kullanıcı kilide kendi bastı.
class _KilitSatiri extends StatelessWidget {
  const _KilitSatiri();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Pressable(
      onTap: () {
        Navigator.of(context).pop();
        acPaywall(context, kaynak: PaywallKaynak.takvimGunu);
      },
      child: GlassPanel(
        child: Row(children: [
          const KilitRozeti(),
          const SizedBox(width: RythoSpace.sm),
          Expanded(
            child: Text(l10n.calendarLockedReading, style: RythoType.bodyDim),
          ),
        ]),
      ),
    );
  }
}

/// Gün sayfasındaki tek olay satırı.
///
/// ## Sira: ANLAM → SEBEP → DAVET
///
/// Sahip cihaz ekran görüntüsüyle geldi: bu satırda yalnız
/// "Plüton — ileri harekete dönüş" yazıyordu. İki ETİKETİN tire ile
/// yapıştırılmış hâliydi (bu dosya yapıştırıyordu, sunucu böyle bir
/// cümle üretmiyordu) ve kullanıcının "bu ne demek, ne getirip ne
/// götürüyor" sorusunun cevabı ürünün HİÇBİR yüzeyinde yoktu.
///
/// Sıra bu yüzden böyle: önce ne demek olduğu (`line`), SONRA sebebi
/// olarak ölçümün kendi ifadesi (`technical`), en altta sohbete götüren
/// giriş. Tersi, ölçüm disiplinini anlamın önüne koyan hâliydi.
/// Hiyerarşi de bunu söyler: anlam okuma ölçüsünde (15/1,65), sebep
/// daha küçük ve silik — `basis_sheet`te ölçülen kusurun aynısı
/// (sayfanın ASIL metni teknik tablodan küçük görünüyordu).
class _OlaySatiri extends StatelessWidget {
  const _OlaySatiri({required this.olay});

  final Map<String, dynamic> olay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cumle = olay['line'] as String?;

    // Kilitli olay burada HİÇBİR ŞEY çizmez: kilit cümlesi sayfanın
    // sonunda bir kez duruyor.
    //
    // Okumasız dalın kapsamı OP2'de DARALDI ve eski gerekçesi ("istasyonun
    // hiçbir katmanda okuması yok") artık yanlış: sunucu istasyona da sabit
    // tablodan bir anlam cümlesi yazıyor. Dal yine de duruyor, çünkü
    // sunucu cümleyi UYDURMUYOR — tanımadığı bir yön evresi ya da
    // tablosunda olmayan bir gezegen gelirse `line` HİÇ yazılmıyor. O
    // durumda satır ölçümüyle yazılır: eksik olan anlamdır, ölçüm değil.
    if (cumle == null || cumle.isEmpty) {
      if (olay['locked'] == true) return const SizedBox.shrink();
      final teknik = olay['technical'] as String? ??
          [olay['transit_local'], olay['type_local']]
              .whereType<String>()
              .join(' — ');
      if (teknik.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: RythoSpace.sm),
        child: Text(teknik, style: RythoType.bodyDim),
      );
    }

    // Sebep satırı: istasyonda "Plüton şu gün hızını sıfıra indirip yön
    // değiştiriyor", kesinleşmede açının kendi ifadesi. İkisi de ÖLÇÜMÜN
    // adı; disiplinin reklamı değil (yani "hesaplanmış gökyüzü verisidir"
    // gibi bir övgü satırı buraya girmez). Mono yazı buradan kalktı: bu
    // bir cümle, bir derece tablosu değil — mono onu "veri" gibi
    // gösterip okumanın altında ikinci bir teknik blok kuruyordu.
    final sebep = (olay['technical'] as String?)?.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: RythoSpace.sm),
      child: GlassPanel(
        // Cam panel kendi kenar boşluğunu taşıyor; gün sayfası zaten
        // kendi iç boşluğunu veriyor ve ikisi toplanınca kart daralıyordu.
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.md, RythoSpace.md, RythoSpace.md, RythoSpace.md),
        onTap: () => _dayanak(context, olay, l10n),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cumle, style: RythoType.reading),
          if (sebep != null && sebep.isNotEmpty) ...[
            const SizedBox(height: RythoSpace.sm),
            Text(sebep, style: RythoType.caption),
          ],
          const SizedBox(height: RythoSpace.sm),
          // Oku, dokunulabildiğini söyleyen tek işaret: ana ekran sinyal
          // kartıyla (`sky_screen` `_SignalCard`) AYNI yazım. Eski hâl
          // oksuz "Neye dayanıyor?" basıyordu ve bir başlık gibi okunuyordu.
          Text('${l10n.signalWhy} →',
              style: RythoType.caption.copyWith(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  /// "Neye dayanıyor?" — sinyal kartlarıyla AYNI alt-sayfa (R2-S2).
  void _dayanak(BuildContext context, Map<String, dynamic> o,
      AppLocalizations l10n) {
    final sinyal = {
      'headline': o['line'],
      'card_text': o['line'],
      'technical': o['technical'],
      'transit_local': o['transit_local'],
      'natal_local': o['natal_local'],
      'aspect_local': o['aspect_local'],
      'orb': o['orb'],
      'exact_on_local': o['date_local'] ?? o['date'],
      if (o['natal_sign_local'] != null)
        'natal_sign_local': o['natal_sign_local'],
      'theme_local': o['theme_local'],
    };
    showSignalBasisSheet(
      context,
      sinyal,
      title: l10n.calendarWhyDate,
      onAsk: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatScreen(
              initialText: l10n.signalAskPrefill(o['line'] as String? ?? '')),
        ));
      },
    );
  }
}

/// Ay adları arayüz diliyle `intl`den gelir — ekranın başka yerinde
/// (`sky_screen` tarih satırı) zaten bu desen kullanılıyor. Ay adlarını
/// l10n anahtarı olarak taşımak dil başına 12 gereksiz dize demekti.
String _ayKisa(BuildContext context, DateTime d) =>
    DateFormat('MMM', Localizations.localeOf(context).toLanguageTag())
        .format(d);

String _ayGun(BuildContext context, DateTime d) =>
    DateFormat('d MMMM', Localizations.localeOf(context).toLanguageTag())
        .format(d);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/basis_sheet.dart';
import '../../widgets/glass.dart';
import '../chat/chat_screen.dart';
import '../paywall/paywall_screen.dart';

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
class CalendarStrip extends ConsumerWidget {
  const CalendarStrip({super.key});

  /// Şeritte gösterilen gün sayısı — sunucudaki `TRANSIT_CALENDAR_DAYS`
  /// ile aynı ufuk. Sunucu daha uzun bir pencere gönderse bile şerit
  /// bu sayıda hücre çizer.
  static const int gunSayisi = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final takvim = ref.watch(transitCalendarProvider);

    // Bölüm kendi kendini gizler: veri yok, hata, doğum kaydı eksik —
    // ana ekran şeritsiz de ayakta durmalı (sinyal bölümüyle aynı kural).
    final veri = takvim.value;
    if (veri == null) return const SizedBox.shrink();

    final olaylar = List<Map<String, dynamic>>.from(
        (veri['events'] as List?)?.map((e) =>
            Map<String, dynamic>.from(e as Map)) ??
        const <Map<String, dynamic>>[]);
    if (olaylar.isEmpty) return const SizedBox.shrink();

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
      for (var i = 0; i < gunSayisi; i++)
        DateTime(bugun.year, bugun.month, bugun.day + i),
    ];

    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
        itemCount: gunler.length,
        separatorBuilder: (_, _) => const SizedBox(width: RythoSpace.sm),
        itemBuilder: (_, i) {
          final gun = gunler[i];
          final anahtar = _isoGun(gun);
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
    );
  }

  static String _isoGun(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Şeritteki tek gün.
///
/// Olaysız günler de çizilir — takvim ancak sürekli bir zaman şeridi
/// olduğunda takvimdir; yalnız dolu günleri göstermek onu bir listeye
/// geri çevirirdi. Olaysız gün soluk ve dokunulamaz.
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
    final dolu = olaylar.isNotEmpty;
    final ikon = olaylar
        .map((o) => kThemeIcons[o['theme']])
        .whereType<String>()
        .firstOrNull;

    return Semantics(
      button: dolu,
      label: _ayGun(context, gun),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
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
              Text(_ayKisa(context, gun),
                  style: RythoText.label(8,
                      color: bugunMu
                          ? RythoColors.goldBright
                          : RythoColors.parchmentDim)),
              const SizedBox(height: 2),
              Text('${gun.day}',
                  style: RythoText.display(16,
                      color: dolu || bugunMu
                          ? RythoColors.parchment
                          : RythoColors.parchmentDim)),
              const SizedBox(height: 3),
              // İkon satırı HER hücrede aynı yüksekliği tutar; yoksa dolu
              // ve boş günler farklı boyda çizilip şerit dalgalanır.
              SizedBox(
                height: 12,
                child: ikon != null
                    ? Text(ikon, style: const TextStyle(fontSize: 10))
                    : dolu
                        ? Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: const BoxDecoration(
                                color: RythoColors.lilac,
                                shape: BoxShape.circle),
                          )
                        : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gün kartı: o günün olayları **temaya göre başlıklı**.
///
/// Abonede her olay gündelik cümlesiyle ve "Neye dayanıyor?" girişiyle
/// gelir. Ücretsiz kullanıcıda tema başlığı ve tarih GÖRÜNÜR, okuma
/// satırının yerinde kilit satırı durur — gördüğü şey gerçek, göremediği
/// şey açıkça isimlendirilmiş.
Future<void> showDaySheet(BuildContext context, DateTime gun,
    List<Map<String, dynamic>> olaylar) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RythoColors.inkLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(color: RythoColors.glassStroke),
    ),
    // Kaydırma SARMALAYICIDA. Gövde `mainAxisSize: min` bir `Column`
    // ve bu sayfa doğduğu günden beri kaydırmasızdı; içerik kısa
    // olduğu için görünmüyordu. Kart desenine geçiş satır başına
    // yükseklik ekledi ve ÖLÇÜLDÜ (320x480 değil, 320x640 / yazı
    // ölçeği tavanı): tek kartta 130 px, üç kartta 1162 px taşma.
    // Eski düz satır biçimi aynı ekranda hiç taşmıyordu, yani kusur
    // bu turda doğdu.
    //
    // Taşma ürün kodunda istisna olarak GÖRÜNMEZ — ekrandan sessizce
    // kırpılır. Kardeş desende (`basis_sheet`, aynı tür
    // `isScrollControlled` alt sayfa) bu 131 px sessiz kırpılma olarak
    // ölçülmüştü; bekçi `calendar_strip_test.dart`te.
    builder: (_) => SingleChildScrollView(
        child: _GunSayfasi(gun: gun, olaylar: olaylar)),
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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.xl, RythoSpace.lg, RythoSpace.xl, RythoSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_ayGun(context, gun), style: RythoText.display(20)),
            const SizedBox(height: RythoSpace.lg),
            for (final tema in sirali) ...[
              Row(children: [
                Text(kThemeIcons[tema] ?? '✦',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                // Tema adı sunucudan gelir ve esnemiyordu; uzun adda
                // (büyük yazı ölçeğiyle birlikte) satırı taşırıyordu.
                Flexible(
                  child: Text(
                      (gruplar[tema]!.first['theme_local'] as String?) ??
                          l10n.calendarOtherEvents,
                      style: RythoText.label(11, color: RythoColors.lilac)),
                ),
              ]),
              const SizedBox(height: RythoSpace.sm),
              for (final o in gruplar[tema]!) _OlaySatiri(olay: o),
              const SizedBox(height: RythoSpace.md),
            ],
            if (kilitliSayisi > 0) const _KilitSatiri(),
          ],
        ),
      ),
    );
  }
}

/// Gün kartının tek kilit satırı — dokunuş paywall'ı açar.
class _KilitSatiri extends StatelessWidget {
  const _KilitSatiri();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const PaywallScreen(),
          fullscreenDialog: true,
        ));
      },
      behavior: HitTestBehavior.opaque,
      child: GlassPanel(
        child: Row(children: [
          const Icon(Icons.lock_outline_rounded,
              size: 15, color: RythoColors.parchmentDim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l10n.calendarLockedReading,
                style:
                    RythoText.body(12.5, color: RythoColors.parchmentDim)),
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
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(teknik,
            style: RythoText.body(12.5, color: RythoColors.parchmentDim)),
      );
    }

    // Sebep satırı: istasyonda "Plüton şu gün hızını sıfıra indirip yön
    // değiştiriyor", kesinleşmede açının kendi ifadesi. İkisi de ÖLÇÜMÜN
    // adı; disiplinin reklamı değil (yani "hesaplanmış gökyüzü verisidir"
    // gibi bir övgü satırı buraya girmez).
    final sebep = (olay['technical'] as String?)?.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        // Cam panel kendi kenar boşluğunu taşıyor; gün sayfası zaten
        // kendi iç boşluğunu veriyor ve ikisi toplanınca kart daralıyordu.
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
        onTap: () => _dayanak(context, olay, l10n),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cumle, style: RythoType.reading),
          if (sebep != null && sebep.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(sebep,
                style:
                    RythoText.mono(11.5, color: RythoColors.parchmentDim)),
          ],
          const SizedBox(height: 9),
          // Oku, dokunulabildiğini söyleyen tek işaret: ana ekran sinyal
          // kartıyla (`sky_screen` `_SignalCard`) AYNI yazım. Eski hâl
          // oksuz "Neye dayanıyor?" basıyordu ve bir başlık gibi okunuyordu.
          Text('${l10n.signalWhy} →',
              style: RythoText.body(11.5,
                  color: RythoColors.parchmentDim, w: FontWeight.w600)),
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
              initialText: l10n.signalAskPrefill(
                  o['line'] as String? ?? '',
                  o['technical'] as String? ?? '')),
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

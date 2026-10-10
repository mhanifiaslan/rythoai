// Dar ekran + büyük yazı ölçeği taşma bekçileri — EKRANLAR turu.
//
// `dar_ekran_test.dart` ortak bileşenleri (SectionHeader, LabelValueRow,
// SettingsRow, ErrorCard) sabitliyor. Bu dosya aynı kusur sınıfının
// ekranlara ve ekranlara özel bileşenlere dağılmış hâlini sabitler:
// esnemeyen `Row` içinde yan yana duran iki metin, `Row` + `Spacer` ile
// kurulmuş etiket-değer çiftleri ve alt alta inmesi gereken düğme
// satırları.
//
// Ölçüt aynı: 320 dp genişlik × 1,3 yazı ölçeği (`kMaxTextScale`) altında
// hiçbir şey taşmamalı. Flutter taşmayı çizim anında fırlatır.
//
// ⚠️ Test yazı tipi (Ahem) HER harfi punto kadar geniş kare çizer; ölçülen
// genişlik gerçek cihazdan ~2 kat fazladır. Bu, bekçiyi bilinçli olarak
// TUTUCU yapar: burada geçen yerleşim cihazda da geçer. Bunun bedeli,
// uzun dizgilerle piksel konumu iddia EDİLEMEMESİDİR — testler yalnız
// "taştı mı?" ve "metin ekranda mı?" sorularını sorar.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/friends/reaction_sheet.dart';
import 'package:rytho/features/onboarding/onboarding_wizard.dart';
import 'package:rytho/features/sky/calendar_strip.dart';
import 'package:rytho/core/friends.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart';
import 'package:rytho/widgets/chart/chart_data.dart';
import 'package:rytho/widgets/chart/chart_positions.dart';
import 'package:rytho/widgets/reading_card.dart';

// Harness'ı bilerek PAYLAŞIYORUZ: ölçüt (320 dp × 1,3) tek yerde durmalı,
// yoksa iki dosya zamanla birbirinden ayrı düşer.
import 'dar_ekran_test.dart' show darEkranda, kDarGenislik, tasmaYok;

/// Gerçek uzunlukta Türkçe dizgiler — kısaltılmış örnek metin, kusuru
/// görünmez kılar.
const String kUzunEtiket = 'Doğum yeri ve saat dilimi';
const String kUzunDeger = 'İstanbul, Türkiye (UTC+03)';
const String kUzunTema = 'İlişkiler ve ortaklıklar';

/// Tam ekran widget'ları (kendi `Scaffold`'ıyla gelenler) için harness.
///
/// [darEkranda] gövdeyi bir `Scaffold` içine koyuyor; ekranların kendi
/// `Scaffold`'ı olduğu için burada `MediaQuery` `MaterialApp.builder`
/// üzerinden veriliyor — uygulamanın `kMaxTextScale` kelepçesiyle aynı yer.
Future<void> darEkrandaEkran(
  WidgetTester tester,
  Widget home, {
  double genislik = kDarGenislik,
  double olcek = kMaxTextScale,
}) async {
  // Yükseklik de GERÇEKÇİ olmalı: burada `MediaQuery` boyutu elle
  // verilmediği için mantıksal yükseklik `physicalSize / dpr`'dir. Kısa
  // tutmak, ölçmek istemediğimiz DİKEY taşmaları uydurur.
  tester.view.physicalSize = Size(genislik * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(olcek),
          // Giriş animasyonları testte zamanlayıcı bırakır; ölçülen şey
          // YERLEŞİM, hareket değil.
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: home,
    ),
  ));
}

/// Uzun yerel adlarla natal yük — sunucu adları dile göre uzuyor.
Map<String, dynamic> _uzunNatalJson() => {
      'points': [
        {
          'name': 'Sun',
          // Gerçek en uzun yerel adlar bunlar: düğümler ve asteroitler.
          'name_local': 'Güney Ay Düğümü',
          'abs_position': 100.0,
          'position': 10.0,
          'sign': 'Sag',
          'retrograde': true,
          'house_no': 12,
          'speed': 0.98,
        },
        {
          'name': 'Saturn',
          'name_local': 'Satürn (geri hareketli)',
          'abs_position': 305.5,
          'position': 5.5,
          'sign': 'Aqu',
          'retrograde': true,
          'house_no': 10,
          'speed': -0.05,
        },
      ],
      'houses': [
        for (var i = 0; i < 12; i++)
          {
            'house': i + 1,
            'abs_position': (40.0 + i * 30) % 360,
            'sign': 'Tau',
            'position': 10.0,
          },
      ],
      'aspects': const <Map<String, dynamic>>[],
    };

void main() {
  group('Ortak bileşenler — ekranlarda tekrar eden yapı taşları', () {
    testWidgets('GoldButton uzun etiketi DAR kutuda taşırmaz',
        (tester) async {
      // Cihaz bulgusu sınıfı: bu düğme gelen davet satırında sabit
      // `SizedBox(width: 104)` içine konuyor. Etiket esnemeyince büyük
      // yazı ölçeğinde sağdan taşıyordu.
      await darEkranda(
        tester,
        SizedBox(
          width: 104,
          child: GoldButton(text: 'Kabul et ve takibe başla', onPressed: () {}),
        ),
      );
      tasmaYok(tester, neden: 'düğme etiketi sabit genişlikli kutuyu taşırıyor');
      expect(find.text('Kabul et ve takibe başla'), findsOneWidget);
    });

    // `GradientProgressBar` bekçisi KALKTI (D3): bileşen silindi — `lib/`
    // altında sıfır çağıranı vardı, taşma bekçisi tüketicisi olmayan bir
    // widget'ı yaşatıyordu.

    testWidgets('ReadingCard "devamını oku" satırı taşmaz', (tester) async {
      await darEkranda(
        tester,
        const ReadingCard(
          title: 'Bugün gökyüzünde senin için',
          body: 'Bugün gökyüzünde belirgin bir gerilim var ve bu gerilim '
              'kararlarını hızlandırmaya çalışacak.',
          label: '☀️ Yay · 🌙 Başak · ↑ İkizler',
        ),
      );
      tasmaYok(tester, neden: 'metin + ok tek satıra sığmıyor');
    });

    testWidgets('ChartPositionsTable uzun gezegen/burç adlarında taşmaz',
        (tester) async {
      await darEkranda(
        tester,
        ChartPositionsTable(data: ChartData.fromNatal(_uzunNatalJson())),
      );
      tasmaYok(tester,
          neden: 'gezegen adı + derece dizgisi satırı taşırıyor');
      expect(find.text('Güney Ay Düğümü'), findsOneWidget);
    });
  });

  group('Etiket-değer ve düğme satırları — ekran içi desenler', () {
    testWidgets('etiket / değer + kalem satırı taşmaz', (tester) async {
      // `person_form_screen` ve `birth_record_screen` içindeki `_AlanSatiri`
      // ile AYNI yapı: `Expanded(Wrap(spaceBetween))` + sabit kalem ikonu.
      // Özel (private) sınıf olduğu için desen burada doğrulanıyor.
      await darEkranda(
        tester,
        Row(children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 2,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: const [
                Text(kUzunEtiket),
                Text(kUzunDeger),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.edit_outlined, size: 15),
        ]),
      );
      tasmaYok(tester);
      expect(find.text(kUzunEtiket), findsOneWidget);
      expect(find.text(kUzunDeger), findsOneWidget);
    });

    testWidgets('iki düğmeli kurtarma satırı alt alta iner', (tester) async {
      // `phone_verify_screen` deseni: "Kodu tekrar gönder (42)" +
      // "Numarayı değiştir".
      await darEkranda(
        tester,
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                  onPressed: () {},
                  child: const Text('Kodu tekrar gönder (42)')),
              TextButton(
                  onPressed: () {}, child: const Text('Numarayı değiştir')),
            ],
          ),
        ),
      );
      tasmaYok(tester);
      expect(find.text('Numarayı değiştir'), findsOneWidget);
    });
  });

  group('Ekran girişleri — gerçek ağaçlar', () {
    testWidgets('Gün kartı: uzun tema başlığı taşmaz', (tester) async {
      // `calendar_strip.showDaySheet` — tema adı SUNUCUDAN gelir, uzunluğu
      // bizim denetimimizde değil; ikon + ad esnemeyen bir `Row`daydı.
      await darEkrandaEkran(
        tester,
        Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDaySheet(context, DateTime.now(), [
                  {
                    'type': 'aspect_exact',
                    'date': '2026-09-13',
                    'date_local': '13 Eylül',
                    'theme': 'relationships',
                    'theme_local': kUzunTema,
                    'tone': 'support',
                    'line': 'Yakınlarınla aranda biriken şeyi konuşmak '
                        'bugün kolaylaşıyor.',
                    'technical': 'Mars, natal Venüs ile üçgen — orb 0.4°',
                    'transit_local': 'Mars',
                    'natal_local': 'Venüs',
                    'aspect_local': 'Üçgen',
                    'orb': 0.4,
                  },
                ]),
                child: const Text('aç'),
              ),
            ),
          );
        }),
      );
      await tester.tap(find.text('aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      tasmaYok(tester, neden: 'tema başlığı satırı taşırıyor');
      expect(find.text(kUzunTema), findsOneWidget);
    });

    testWidgets('Tepki sayfası: uzun tepki adları taşmaz', (tester) async {
      // `reaction_sheet` çipleri `Wrap` içinde; çipin KENDİ `Row`u
      // esnemiyordu, uzun tepki adı çipin dışına taşıyordu.
      await darEkrandaEkran(
        tester,
        Consumer(builder: (context, ref, _) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showReactionSheet(
                  context,
                  ref,
                  const Friend(
                      uid: 'u1',
                      status: FriendStatus.accepted,
                      displayName: 'Zeynep Aslanoğulları'),
                ),
                child: const Text('aç'),
              ),
            ),
          );
        }),
      );
      await tester.tap(find.text('aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      tasmaYok(tester, neden: 'tepki çipi kendi satırından taşıyor');
    });

    testWidgets('Kurulum sihirbazı ilk sayfası taşmaz', (tester) async {
      // Yasal bağlantılar ("Kullanım Şartları" + "Gizlilik Politikası")
      // esnemeyen bir `Row`daydı ve dar ekranda ikincisi kırpılıyordu.
      await darEkrandaEkran(tester, const OnboardingWizard());
      await tester.pump(const Duration(milliseconds: 600));
      tasmaYok(tester, neden: 'sihirbazın ilk sayfası dar ekranda taşıyor');
      // Bekçinin DOĞRU sayfayı ölçtüğünün kanıtı: iki yasal bağlantı da
      // burada. Sayfa sırası değişirse bu iddia düşer ve test yalancı
      // güvence vermez.
      expect(find.text('Kullanım Şartları'), findsOneWidget);
      expect(find.text('Gizlilik Politikası'), findsOneWidget);
    });
  });
}

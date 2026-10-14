// Dar ekran + büyük yazı ölçeği: ana ekran ve hikâye okuyucu GERÇEK ağaç
// olarak (D5). Ölçüt depo geneliyle aynı: 320 dp × 1,3 (`kMaxTextScale`)
// altında taşma yok — Flutter taşmayı çizim anında fırlatır.
//
// `dar_ekran_ekranlar_test.darEkrandaEkran` burada kullanılamıyor: o
// harness kök `ProviderScope`u kendisi kuruyor ve override almıyor; ana
// ekran sağlayıcısız çizilemez (Firebase ister). Harness `sky_hiyerarsi_test`
// ile ORTAK (`skyPump`), yalnız ölçü ve ölçek burada veriliyor.
//
// ⚠️ Test yazı tipi her harfi punto kadar geniş kare çizer; burada geçen
// yerleşim cihazda da geçer, tersi iddia edilmez.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/sky/sign_story_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';

import 'dar_ekran_test.dart' show kDarGenislik, tasmaYok;
import 'sky_hiyerarsi_test.dart' show ornekSinyal, skyOverrides, skyPump, tr;

/// Uzun burç yorumu — hikâye sayfası kırpmaz, tamamı akar.
const _uzunYorum = 'Bugün gökyüzünde belirgin bir gerilim var ve bu gerilim '
    'kararlarını hızlandırmaya çalışacak. Acele etme. Ay Balık burcunda '
    'ilerlerken sezgin yüksek ama ölçülerin kaygan. Akşama doğru netleşir.';

void main() {
  group('320 dp × 1,3 taşma', () {
    testWidgets('SkyScreen: kilitli okuma + sinyaller + günlük satırı',
        (tester) async {
      await skyPump(
        tester,
        genislik: kDarGenislik,
        yukseklik: 1800,
        olcek: kMaxTextScale,
        overrides: skyOverrides(
          sinyaller: () => {
            'signals': [ornekSinyal(), ornekSinyal(sira: 1)],
          },
          // Takvim şeridi de DOLU çizilsin: 46 px'lik gün hücresi, etiket
          // rolündeki ay adı (8 pt → 11 pt büyüdü) ve ikon satırı 1,3
          // ölçeğinde hücrenin 66 px'ine sığmalı — boş şerit kendini
          // gizler, ölçülmezdi.
          takvim: () => {
            'events': [
              {
                'type': 'aspect_exact',
                'date': DateTime.now()
                    .add(const Duration(days: 2))
                    .toIso8601String()
                    .substring(0, 10),
                'date_local': '12 Ekim',
                'theme': 'relationships',
                'theme_local': 'İlişkiler',
                'locked': true,
              },
            ],
          },
        ),
      );
      tasmaYok(tester, neden: 'ana ekran dar ekranda taşıyor');
      expect(find.bySemanticsLabel(tr.calendarStripTitle), findsOneWidget,
          reason: 'takvim şeridi dolu çizilmeli ki hücreler ölçülsün');
      expect(find.text(tr.todaysInsight), findsOneWidget);
      expect(find.text(tr.signalsSection), findsOneWidget);
      // Günlük başlıkta ikon-tek düğme (ipucu = adı).
      expect(find.byTooltip(tr.diaryTitle), findsOneWidget);
    });

    testWidgets('SkyScreen: abone okuması + uzun zamanlama etiketi',
        (tester) async {
      await skyPump(
        tester,
        genislik: kDarGenislik,
        yukseklik: 1800,
        olcek: kMaxTextScale,
        overrides: skyOverrides(
          kapi: PlusHali.abone,
          gunluk: () => {
            'reading': _uzunYorum,
            'sun_sign': 'Aslan',
            'moon_sign': 'Balık',
            'ascendant': 'Terazi',
          },
          sinyaller: () => {
            'signals': [
              {
                ...ornekSinyal(),
                // Sınır metni, gerçek ad değil. ÖLÇÜLDÜ: test fontu bu
                // boyutta ~7,7 px/harf; tema adı `Expanded` dışına çıkınca
                // satırın 241 px'ini aşmalı ki bekçi görsün — 24 harflik
                // "İlişkiler ve ortaklıklar" 184 px'e sığıyor ve esnemeyi
                // kaldıran mutasyon YEŞİL kalıyordu. 50 harf (~385 px) aşar.
                'theme_local':
                    'İlişkiler, ortaklıklar ve uzun süreli yakın bağlar',
                'timing_local': '15 Ekim günü, akşam saatlerinde netleşiyor',
              },
            ],
          },
        ),
      );
      tasmaYok(tester, neden: 'abone okuması dar ekranda taşıyor');
      expect(find.textContaining('Akşama doğru'), findsOneWidget);

    });

    testWidgets('SignStoryScreen: başlık satırı (ad + tarih + iki düğme) '
        've metin', (tester) async {
      tester.view.physicalSize = Size(kDarGenislik * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          signHoroscopeProvider.overrideWith(
              (ref, key) async => {'reading': '$key: $_uzunYorum'}),
        ],
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
              textScaler: const TextScaler.linear(kMaxTextScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          // En uzun burç adı: "Yay" kısa, "Akrep"/"Terazi"/"Başak" uzun —
          // Başak (5) ile.
          home: const SignStoryScreen(order: [5, 0, 1], initialIndex: 0),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      tasmaYok(tester, neden: 'hikâye başlığı dar ekranda taşıyor');
      expect(find.textContaining('virgo:'), findsOneWidget);
      // Her iki düğme de ekranda: oynat/duraklat ve kapat.
      expect(find.byType(IconButton), findsNWidgets(2));
    });
  });
}

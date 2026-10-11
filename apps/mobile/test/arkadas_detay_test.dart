// Arkadaş ekranı bekçileri (D6): ikili okuma `OkumaKabi`de — `fallback`
// tek noktadan okunur, şablon rapor gibi görünmez, paylaşım YOK (üçüncü
// kişi hakkında — sahip kararı), boş "sor" kutusu yerine tohumlu
// "Rytho'ya sor"; ilişki satırı `ListeSatiri`; model `'Gezgin'` taşımaz.
//
// Ekran gerçek ağaç: sahte sunucu `/reports/dyad` yükünü verir.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/friends.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/chat/chat_screen.dart';
import 'package:rytho/features/friends/friend_detail_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show MarginNote, RythoyaSor;
import 'package:rytho/widgets/common.dart' show ErrorCard;
import 'package:rytho/widgets/liste_satiri.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cevrem_harness.dart';

final _tr = AppLocalizationsTr();

const _kYol = 'lib/features/friends/friend_detail_screen.dart';
const _kModelYol = 'lib/core/friends.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

const _arkadas = Friend(
    uid: 'u1',
    status: FriendStatus.accepted,
    displayName: 'Zeynep',
    username: 'zeynep',
    sunSign: 'Boğa',
    streakVisible: true);

Map<String, dynamic> _yuk({
  String? okuma = 'Bugün aranızda sakin bir akış var.',
  bool sablon = false,
  bool iade = false,
}) =>
    {
      'data': {'reading': okuma, 'fallback': sablon, 'refunded': iade},
    };

Future<RotaGozcusu> _kur(WidgetTester tester, Map<String, dynamic> yuk,
    {double olcek = 1.0}) async {
  SharedPreferences.setMockInitialValues({});
  final gozcu = RotaGozcusu();
  await tester.pumpWidget(sar(
    const FriendDetailScreen(friend: _arkadas),
    overrides: [
      apiProvider.overrideWithValue(
          sahteDio(SahteAdapter({'/reports/dyad': jsonEncode(yuk)}))),
      walletProvider.overrideWith((ref) async => WalletStatus.unknown),
    ],
    gozcu: gozcu,
    olcek: olcek,
  ));
  await yerles(tester);
  return gozcu;
}

void main() {
  group('model', () {
    test("'Gezgin' modelde yok; yedek ad dilden", () {
      expect(_yorumsuz(_kModelYol), isNot(contains("'Gezgin'")));
    });

    testWidgets('kartsız arkadaş: name boş, ad(l10n) dilin yedeği', (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(sar(Builder(builder: (c) {
        l10n = AppLocalizations.of(c);
        return const SizedBox();
      })));
      const kartsiz = Friend(uid: 'u9', status: FriendStatus.accepted);
      expect(kartsiz.name, '');
      expect(kartsiz.ad(l10n), l10n.defaultUserName);
      // Kartlı arkadaşta yedek devreye girmez.
      expect(_arkadas.ad(l10n), 'Zeynep');
    });
  });

  group('ekran', () {
    testWidgets('hazır okuma: metin + tohumlu "Rytho\'ya sor" + günlük notu',
        (tester) async {
      uzunYuzey(tester);
      final gozcu = await _kur(tester, _yuk());

      expect(find.byType(MarginNote), findsOneWidget);
      expect(find.text(_tr.dyadDisclaimer), findsOneWidget);
      expect(find.byType(RythoyaSor), findsOneWidget);
      // Paylaşım kapısı YOK — ikili okuma üçüncü kişi hakkında.
      expect(find.text(_tr.shareReading), findsNothing);

      await tester.tap(find.byType(RythoyaSor));
      final rota = gozcu.itilenler.last as MaterialPageRoute<dynamic>;
      final sohbet =
          rota.builder(tester.element(find.byType(RythoyaSor))) as ChatScreen;
      expect(sohbet.initialText, _tr.askAboutFriendPrefill('Zeynep'),
          reason: 'eski kutu sohbeti BOŞ açıyordu');
      expect(sohbet.friendUid, 'u1');
    });

    testWidgets('şablon okuma: dürüst kart + iade cümlesi; metin ve not yok',
        (tester) async {
      uzunYuzey(tester);
      await _kur(tester, _yuk(okuma: 'ŞABLON', sablon: true, iade: true));
      expect(find.byType(MarginNote), findsNothing);
      expect(find.text('ŞABLON'), findsNothing);
      expect(find.text(_tr.dyadDisclaimer), findsNothing,
          reason: 'olmayan okumanın geçerlilik notu olmaz');
      expect(find.byType(ErrorCard), findsOneWidget);
      expect(find.text(_tr.reportUnavailableRefunded), findsOneWidget,
          reason: 'iade bilgisi sunucunun bayrağından');
      expect(find.byType(RythoyaSor), findsNothing);
    });

    testWidgets('ilişki satırı ListeSatiri; menü ikonu adlı', (tester) async {
      uzunYuzey(tester);
      await _kur(tester, _yuk());
      expect(find.widgetWithText(ListeSatiri, _tr.relationshipOpen),
          findsOneWidget);
      expect(find.byTooltip(_tr.privacy), findsOneWidget);
    });

    testWidgets('320 dp × 1,3 taşmaz', (tester) async {
      darYuzey(tester);
      await _kur(tester, _yuk(), olcek: darOlcek);
      tasmaYok(tester, neden: 'arkadaş ekranı üst bloğu taşıyor');
      await kaydirarakTasmaAra(tester, find.byType(ListView),
          neden: 'arkadaş ekranı dar ekranda taşıyor');
    });
  });

  group('kaynak bekçileri', () {
    test('fallback tek noktadan; analitik yalnız gerçek üretimde', () {
      final k = _yorumsuz(_kYol);
      expect(k, contains("okumaDurumuFromYanit(veri, alan: 'reading')"));
      expect(k, contains("if (durum is OkumaHazir) Analytics.reportGenerated('dyad')"));
      expect(k, isNot(contains('shareReportCard(')));
      expect(k, contains('BedelRozeti(PlusOzellik.dyad'));
    });

    test('hareket: kopya fadeIn yok, kutlama süresi adlı sabit', () {
      final k = _yorumsuz(_kYol);
      expect(k, isNot(contains('.animate(')));
      expect(k, contains('Future<void>.delayed(kTepkiKutlamaSuresi)'));
    });
  });
}

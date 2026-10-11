// Çevrem ekranı bekçileri (D6): davet paneli, kontenjan beyanı, liste
// satırı göçü, alt sayfa kabuğu, 320 dp × 1,3.
//
// Ekran GERÇEK ağaç olarak kuruluyor: sağlayıcılar (profil, arkadaşlar,
// kişiler, kontenjan, bekleyen davet) sahte değerlerle veriliyor; Firebase
// hiç dokunulmuyor. Kaynak bekçileri yalnız widget testiyle ölçülemeyen
// iddialar için (hangi bileşenin kullanıldığı, kopyanın geri gelmemesi).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/deep_links.dart';
import 'package:rytho/core/friends.dart';
import 'package:rytho/core/people.dart';
import 'package:rytho/core/providers.dart' show profileProvider;
import 'package:rytho/features/friends/friends_screen.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/liste_satiri.dart';

import 'cevrem_harness.dart';

final _tr = AppLocalizationsTr();

const _kYol = 'lib/features/friends/friends_screen.dart';
const _kRehberYol = 'lib/features/friends/contacts_screen.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

String _bugun() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

final _arkadaslar = <Friend>[
  // Baş harfi noktasız-i tuzağına düşen bir ad: `toUpperCase` "I" verirdi.
  Friend(
      uid: 'u1',
      status: FriendStatus.accepted,
      displayName: 'ilayda Aslanoğulları Karahanlıoğlu',
      sunSign: 'Yay',
      streakVisible: true,
      lastSeenDaily: _bugun()),
  const Friend(
      uid: 'u2',
      status: FriendStatus.incoming,
      username: 'ilayda_cok_uzun_kullanici'),
  const Friend(
      uid: 'u3', status: FriendStatus.outgoing, displayName: 'Mehmet'),
];

const _kisiler = <Person>[
  Person(
      id: 'p1',
      relation: 'partner',
      birthDate: '1990-01-01',
      birthCity: 'İzmir',
      label: 'Ada Aslanoğulları Karahanlıoğlu',
      sunSign: 'Koç'),
];

List<Override> _cevrem({
  String? username,
  String? davet,
  List<Friend> friends = const [],
  List<Person> people = const [],
  ({int used, int limit}) kontenjan = (used: 0, limit: 10),
}) =>
    [
      profileProvider.overrideWith((ref) => Stream.value(<String, dynamic>{
            'username': ?username,
            'streakCount': 3,
            'contactMatch': false,
          })),
      friendsProvider.overrideWith((ref) => Stream.value(friends)),
      myNudgesProvider.overrideWith((ref) => Stream.value(const [])),
      peopleProvider.overrideWith((ref) => Stream.value(people)),
      personSlotsProvider.overrideWith((ref) async => kontenjan),
      pendingInviteProvider.overrideWith((ref) {
        final p = PendingInvite();
        if (davet != null) p.set(davet);
        return p;
      }),
      apiProvider.overrideWithValue(sahteDio(SahteAdapter(const {}))),
    ];

void main() {
  group('davet paneli', () {
    testWidgets('kullanıcı adı yokken bekleyen davet panelde SÖYLENİR',
        (tester) async {
      uzunYuzey(tester);
      await tester.pumpWidget(
          sar(const FriendsScreen(), overrides: _cevrem(davet: 'ayse')));
      await yerles(tester);

      expect(find.text(_tr.inviteNeedsUsername), findsOneWidget,
          reason: 'niyet sessizce bekliyordu, kullanıcı hiçbir şey görmüyordu');
      expect(find.text(_tr.inviteNeedsUsernameAction), findsOneWidget);

      // Niyet TEMİZLENMEZ: ad alınınca sayfa açılacak (risk 11).
      final kap =
          ProviderScope.containerOf(tester.element(find.byType(FriendsScreen)));
      expect(kap.read(pendingInviteProvider), 'ayse',
          reason: 'panel dalı daveti kaybetti');

      // Eylem alanı odaklar — kullanıcı nereye yazacağını arar.
      await tester.tap(find.text(_tr.inviteNeedsUsernameAction));
      await tester.pump();
      final alan = tester.widget<TextField>(find.byType(TextField));
      expect(alan.focusNode?.hasFocus, isTrue);
    });

    testWidgets('davet yokken panel cümlesi YOK', (tester) async {
      await tester.pumpWidget(sar(const FriendsScreen(), overrides: _cevrem()));
      await yerles(tester);
      expect(find.text(_tr.inviteNeedsUsername), findsNothing);
    });
  });

  group('kontenjan', () {
    testWidgets('aşımda sayaç kelepçeli, beyan ayrı satırda', (tester) async {
      uzunYuzey(tester);
      await tester.pumpWidget(sar(const FriendsScreen(),
          overrides: _cevrem(
              username: 'ben',
              people: _kisiler,
              kontenjan: (used: 4, limit: 1))));
      await yerles(tester);

      expect(find.text(_tr.peopleSlots(4, 1)), findsNothing,
          reason: '"4/1 kişi" — ölçülen sayı yanlış adla');
      expect(find.text(_tr.peopleSlots(1, 1)), findsOneWidget);
      expect(find.text(_tr.peopleSlotsOver(1, 4)), findsOneWidget);
    });

    testWidgets('tavan içinde beyan YOK', (tester) async {
      uzunYuzey(tester);
      await tester.pumpWidget(sar(const FriendsScreen(),
          overrides: _cevrem(
              username: 'ben',
              people: _kisiler,
              kontenjan: (used: 1, limit: 10))));
      await yerles(tester);
      expect(find.text(_tr.peopleSlots(1, 10)), findsOneWidget);
      expect(find.textContaining(_tr.peopleSlotsOver(10, 1)), findsNothing);
    });
  });

  group('satırlar', () {
    testWidgets('arkadaş, bekleyen davet, kişi ve rehber girişi ListeSatiri',
        (tester) async {
      uzunYuzey(tester);
      await tester.pumpWidget(sar(const FriendsScreen(),
          overrides: _cevrem(
              username: 'ben', friends: _arkadaslar, people: _kisiler)));
      await yerles(tester);

      // Rehber girişi + kabul edilmiş arkadaş + bekleyen davet + kişi.
      expect(find.byType(ListeSatiri), findsNWidgets(4));
      // Kişi satırında dokunulmaz "dünya" ikonu yok: eylem vaat ediyordu.
      expect(find.byIcon(Icons.public_rounded), findsNothing);
      // Baş harf Türkçe: "ilayda…" → "İ" (toUpperCase "I" verirdi) —
      // avatar yalnız kabul edilmiş arkadaşta.
      expect(find.text('İ'), findsOneWidget);
      expect(find.text('I'), findsNothing,
          reason: 'noktasız I — toUpperCase geri geldi');
      // Gelen davet satırında kabul düğmesi.
      expect(find.text(_tr.accept), findsOneWidget);
    });

    testWidgets('320 dp × 1,3: uzun adlarla hiçbir satır taşmaz',
        (tester) async {
      darYuzey(tester);
      await tester.pumpWidget(sar(const FriendsScreen(),
          overrides: _cevrem(
              username: 'cok_uzun_kullanici_adi',
              friends: _arkadaslar,
              people: _kisiler,
              kontenjan: (used: 4, limit: 1)),
          olcek: darOlcek));
      await yerles(tester);
      tasmaYok(tester, neden: 'Çevrem üst bloğu taşıyor');
      await kaydirarakTasmaAra(tester, find.byType(ListView),
          neden: 'Çevrem listesi dar ekranda taşıyor');
    });
  });

  group('kaynak bekçileri', () {
    test('alt sayfa kabuğu tek: showModalBottomSheet yok, showRythoSheet ×3',
        () {
      final k = _yorumsuz(_kYol);
      expect(k, isNot(contains('showModalBottomSheet(')));
      expect('showRythoSheet<'.allMatches(k).length, 3,
          reason: 'ekleme seçici, arkadaş ekleme, güvenlik menüsü');
    });

    test('hareket: kopya stagger yok, RythoReveal var', () {
      final k = _yorumsuz(_kYol);
      expect(k, isNot(contains('.animate(')));
      expect(k, contains('RythoReveal(index: i'));
    });

    test('bölüm başlıkları etiket rolü, mono (veri) rolü yok', () {
      final k = _yorumsuz(_kYol);
      expect(k, isNot(contains('RythoText.mono(')));
      expect(k, contains('Text(text, style: RythoType.label)'));
    });

    test('onay kapısı: çıkarma ve engelleme onayla ile', () {
      final k = _yorumsuz(_kYol);
      expect(k, contains('title: l10n.removeFriendConfirmTitle'));
      expect(k, contains('title: l10n.blockUserConfirmTitle'));
    });

    test('kişi formu yalnız kontenjan kapısından açılır', () {
      // `PersonFormScreen()` kurulumu TEK yerde (`_kisiEkle`); boş durum
      // kartı ve seçici sayfa o kapıya gider.
      final k = _yorumsuz(_kYol);
      expect('const PersonFormScreen()'.allMatches(k).length, 1);
      expect('_kisiEkle(context, ref)'.allMatches(k).length,
          greaterThanOrEqualTo(2));
    });

    test('kabul düğmesi geri bildirim verir: meşgul + sonuç cümlesi', () {
      // Kabul akışı Firestore ister (widget testiyle ölçülemez); kaynaktan:
      // düğme meşgul olur, sonuç kendi cümlesiyle söylenir — eski hâli
      // ateşle-unut idi.
      final k = _yorumsuz(_kYol);
      expect(k, contains('busy: _busy, onPressed: _kabul'));
      expect(k, contains('l10n.friendAcceptedSnack(ad)'));
    });

    test('rehber: hata kartı ve Türkçe baş harf', () {
      final k = _yorumsuz(_kRehberYol);
      expect(k, contains('ErrorCard('));
      expect(k, contains('trBuyuk('));
      expect(k, isNot(contains('.toUpperCase()')));
    });
  });
}

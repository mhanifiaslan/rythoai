// U17 (App Store 1.2): engelleme UYGULANIYOR ve gelen istek de
// engellenebiliyor/şikayet edilebiliyor.
//
// Kusur: Engelle + Şikayet et yalnız KABUL EDİLMİŞ arkadaşın sayfasındaydı;
// kullanıcı adıyla istek atan bir yabancıyı alıcı kabul etmeden ne
// engelleyebiliyor ne şikayet edebiliyordu. Engel kaydı da hiçbir ekranda
// görünmüyordu — kaldırmanın yolu yoktu.
//
// İnceleme turu (aynı gün) ikinci yönü ekledi: ENGELLEYEN de engellediğine
// davet atamıyor — istemci önce soruyor, evet derse engel silimi davetle
// tek batch'te gidiyor; gelen kutusu engellenenlerin tepkilerini süzüyor;
// kurala çarpan davet nötr bir cümleyle bitiyor.
//
// Firebase kurulmadan ölçülür: yazımlar `engelleyiciProvider` /
// `engelKaldiriciProvider` / `engelKontroluProvider` dikişlerinden, liste
// `engellenenlerProvider` geçersiz kılınarak, dönüşümler saf işlevlerden.
// Batch'lerin İÇERİĞİ sahte Firestore olmadığı için kaynak bekçisiyle
// sabitlenir; kuralın kendisi backend/tests/test_engelleme.py'de.
import 'dart:async' show TimeoutException;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/ai_consent.dart' show aiOnayHesabiProvider;
import 'package:rytho/core/friends.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/core/safety.dart';
import 'package:rytho/features/face/face_consent.dart';
import 'package:rytho/features/friends/friends_screen.dart';
import 'package:rytho/features/profile/blocked_users_screen.dart';
import 'package:rytho/features/profile/profile_sections.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:rytho/widgets/common.dart' show ErrorCard;

import 'cevrem_harness.dart';

final _tr = AppLocalizationsTr();

/// Sürekli animatörler (yıldız alanı) — `pumpAndSettle` dönmez.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

const _istek = Friend(
    uid: 'u-yabanci', status: FriendStatus.incoming, displayName: 'Yabancı');

/// Yazım dikişi: çağrılan uid'leri toplar, istenirse fırlatır.
class _Kayit {
  final cagrilar = <String>[];
  bool dussun = false;

  Future<void> call(String uid) async {
    cagrilar.add(uid);
    if (dussun) throw Exception('yazım düştü');
  }
}

/// Onay diyaloğunun yıkıcı düğmesi (`onayla(destructive: true)`).
Finder _yikiciOnay() => find.descendant(
    of: find.byType(AlertDialog), matching: find.byType(GoldButton));

/// Yorumlar atılır: bekçi, aradığı yapıyı ANLATAN bir yorumu görüp
/// geçmemeli. Önce `/* … */` blokları, sonra her satır `//`dan kesilir —
/// yalnız `//` ile BAŞLAYAN satırları atmak yetmiyordu: satır sonuna
/// yorumlanmış bir `..set(…)` ya da blok yoruma alınmış kod tek-batch
/// bekçisini kandırıyordu (inceleme ölçtü). Dize içindeki `//` (URL) da
/// kesilir; bu bekçilerin baktığı satırlarda URL yok.
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((s) {
      final i = s.indexOf('//');
      return i == -1 ? s : s.substring(0, i);
    })
    .join('\n');

/// [kaynak] içinde [bas]tan başlayıp [son]a kadar (hariç) olan dilim.
String _dilim(String kaynak, String bas, String son) {
  final i = kaynak.indexOf(bas);
  expect(i, isNot(-1), reason: '"$bas" bulunamadı');
  final j = kaynak.indexOf(son, i + bas.length);
  expect(j, isNot(-1), reason: '"$son" bulunamadı');
  return kaynak.substring(i, j);
}

void main() {
  group('gelen istek kutucuğu', () {
    Future<_Kayit> kur(WidgetTester tester) async {
      final kayit = _Kayit();
      await tester.pumpWidget(sar(
        const Scaffold(body: GelenIstekKarti(friend: _istek)),
        overrides: [engelleyiciProvider.overrideWithValue(kayit.call)],
      ));
      await _bekle(tester);
      return kayit;
    }

    Future<void> menudenEngelle(WidgetTester tester) async {
      await tester.tap(find.byTooltip(_tr.requestMoreActions));
      await _bekle(tester);
      await tester.tap(find.text(_tr.blockUser));
      await _bekle(tester);
    }

    testWidgets('⋯ Engelle ve Şikayet et sunar; arkadaşlıktan çıkar YOK',
        (tester) async {
      await kur(tester);
      // İkon-tek düğmenin ekran okuyucu adı (tooltip semantik ad değil).
      expect(find.bySemanticsLabel(_tr.requestMoreActions), findsOneWidget);
      await tester.tap(find.byTooltip(_tr.requestMoreActions));
      await _bekle(tester);

      expect(find.text(_tr.blockUser), findsOneWidget);
      expect(find.text(_tr.reportUser), findsOneWidget);
      // Gelen istekte o iş "Yoksay"ın; "Arkadaşlıktan çıkar" yanlış ad olurdu.
      expect(find.text(_tr.removeFriend), findsNothing);
    });

    testWidgets('Engelle onay sorar; onaylayınca engelliyor ve söylüyor',
        (tester) async {
      final kayit = await kur(tester);
      await menudenEngelle(tester);

      expect(find.text(_tr.blockUserConfirmBody('Yabancı')), findsOneWidget);
      expect(kayit.cagrilar, isEmpty, reason: 'onaydan önce yazım yok');
      await tester.tap(_yikiciOnay());
      await _bekle(tester);

      expect(kayit.cagrilar, ['u-yabanci']);
      expect(find.text(_tr.userBlockedSnack('Yabancı')), findsOneWidget);
    });

    testWidgets('Vazgeç engellemiyor', (tester) async {
      final kayit = await kur(tester);
      await menudenEngelle(tester);
      await tester.tap(find.text(_tr.cancel));
      await _bekle(tester);

      expect(kayit.cagrilar, isEmpty);
      expect(find.text(_tr.userBlockedSnack('Yabancı')), findsNothing);
    });

    testWidgets('yazım düşerse sessiz kalmıyor', (tester) async {
      final kayit = await kur(tester);
      kayit.dussun = true;
      await menudenEngelle(tester);
      await tester.tap(_yikiciOnay());
      await _bekle(tester);

      expect(kayit.cagrilar, ['u-yabanci']);
      expect(find.text(_tr.blockFailed), findsOneWidget);
      expect(find.text(_tr.userBlockedSnack('Yabancı')), findsNothing);
    });

    testWidgets('Şikayet et kullanıcı şikayet sayfasını açıyor',
        (tester) async {
      final kayit = await kur(tester);
      await tester.tap(find.byTooltip(_tr.requestMoreActions));
      await _bekle(tester);
      await tester.tap(find.text(_tr.reportUser));
      await _bekle(tester);

      expect(find.text(_tr.reportUserTitle), findsOneWidget);
      expect(kayit.cagrilar, isEmpty, reason: 'şikayet engellemez');
    });

    testWidgets('Yoksay ve Kabul et yerinde duruyor', (tester) async {
      await kur(tester);
      expect(find.text(_tr.ignore), findsOneWidget);
      expect(find.text(_tr.accept), findsOneWidget);
    });
  });

  testWidgets('kabul edilmiş arkadaşın menüsü: çıkarma da var, engel aynı yol',
      (tester) async {
    const arkadas = Friend(
        uid: 'u-arkadas', status: FriendStatus.accepted, displayName: 'Deniz');
    final kayit = _Kayit();
    bool? sonuc;
    await tester.pumpWidget(sar(
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async =>
                sonuc = await showFriendSafetySheet(context, ref, arkadas),
            child: const Text('menü'),
          ),
        ),
      ),
      overrides: [engelleyiciProvider.overrideWithValue(kayit.call)],
    ));
    await tester.tap(find.text('menü'));
    await _bekle(tester);

    expect(find.text(_tr.removeFriend), findsOneWidget);
    await tester.tap(find.text(_tr.blockUser));
    await _bekle(tester);
    await tester.tap(_yikiciOnay());
    await _bekle(tester);
    // Arkadaş sayfası da AYNI yoldan engelliyor (tek batch) ve ekranı
    // kapatması için `true` alıyor.
    expect(kayit.cagrilar, ['u-arkadas']);
    expect(sonuc, isTrue);
  });

  group('Engellenenler ekranı', () {
    const liste = [
      EngellenenKullanici(uid: 'u-1', displayName: 'Deniz', username: 'deniz'),
      // Kartı olmayan (silinmiş/okunamayan) kişi de listede kalmalı.
      EngellenenKullanici(uid: 'u-2'),
    ];

    Future<_Kayit> kur(WidgetTester tester,
        {Stream<List<EngellenenKullanici>>? akis}) async {
      final kayit = _Kayit();
      await tester.pumpWidget(sar(
        const EngellenenlerEkrani(),
        overrides: [
          engellenenlerProvider
              .overrideWith((ref) => akis ?? Stream.value(liste)),
          engelKaldiriciProvider.overrideWithValue(kayit.call),
        ],
      ));
      await _bekle(tester);
      return kayit;
    }

    testWidgets('engellenenleri adıyla, kartı yoksa adsız listeliyor',
        (tester) async {
      await kur(tester);
      expect(find.text('Deniz'), findsOneWidget);
      expect(find.text('@deniz'), findsOneWidget);
      expect(find.text(_tr.blockedUnknownUser), findsOneWidget);
      expect(find.text(_tr.unblockUser), findsNWidgets(2));
    });

    testWidgets('Vazgeç engeli kaldırmıyor; onay kaldırıyor', (tester) async {
      final kayit = await kur(tester);

      await tester.tap(find.text(_tr.unblockUser).first);
      await _bekle(tester);
      expect(find.text(_tr.unblockConfirmTitle('Deniz')), findsOneWidget);
      await tester.tap(find.text(_tr.cancel));
      await _bekle(tester);
      expect(kayit.cagrilar, isEmpty);

      await tester.tap(find.text(_tr.unblockUser).first);
      await _bekle(tester);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text(_tr.unblockUser)));
      await _bekle(tester);
      expect(kayit.cagrilar, ['u-1']);
      expect(find.text(_tr.userUnblockedSnack('Deniz')), findsOneWidget);
    });

    testWidgets('kaldırma düşerse sessiz kalmıyor', (tester) async {
      final kayit = await kur(tester);
      kayit.dussun = true;
      await tester.tap(find.text(_tr.unblockUser).last);
      await _bekle(tester);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text(_tr.unblockUser)));
      await _bekle(tester);
      expect(kayit.cagrilar, ['u-2']);
      expect(find.text(_tr.unblockFailed), findsOneWidget);
    });

    testWidgets('boş liste boş durumu söylüyor', (tester) async {
      await kur(tester, akis: Stream.value(const []));
      expect(find.text(_tr.blockedUsersEmpty), findsOneWidget);
      expect(find.text(_tr.unblockUser), findsNothing);
    });

    testWidgets('okunamayan liste "kimse yok" DEMİYOR', (tester) async {
      // Boş liste ile yüklenemeyen liste ayrı hâller: ikincisinde "kimse
      // yok" demek, engellediği biri olan kullanıcıya yalan olurdu.
      await kur(tester, akis: Stream.error(Exception('okunamadı')));
      expect(find.byType(ErrorCard), findsOneWidget);
      expect(find.text(_tr.blockedUsersEmpty), findsNothing);
    });
  });

  testWidgets('Gizlilik sayfasından Engellenenler açılıyor', (tester) async {
    await tester.pumpWidget(sar(
      const PrivacySettingsScreen(),
      overrides: [
        // Firebase kurulmadan: hesap yok → AI onayı kapalı, ağa gidilmez.
        aiOnayHesabiProvider.overrideWithValue(null),
        profileProvider.overrideWith((ref) => Stream.value({})),
        faceConsentProvider.overrideWith(
            (ref) async => const FaceConsent(granted: false, version: 1)),
        engellenenlerProvider
            .overrideWith((ref) => Stream.value(const <EngellenenKullanici>[])),
      ],
    ));
    await _bekle(tester);

    await tester.scrollUntilVisible(find.text(_tr.blockedUsersTitle), 100);
    await tester.tap(find.text(_tr.blockedUsersTitle));
    await _bekle(tester);
    expect(find.byType(EngellenenlerEkrani), findsOneWidget);
    expect(find.text(_tr.blockedUsersEmpty), findsOneWidget);
  });

  group('dar ekran (320 dp × 1,3)', () {
    testWidgets('istek kutucuğu üçüncü düğmeyle de taşmıyor', (tester) async {
      darYuzey(tester);
      await tester.pumpWidget(sar(
        const Scaffold(
          body: GelenIstekKarti(
              friend: Friend(
                  uid: 'u',
                  status: FriendStatus.incoming,
                  displayName: 'Gökyüzü Gezgini Uzunadlı')),
        ),
        olcek: darOlcek,
      ));
      await _bekle(tester);
      tasmaYok(tester, neden: '⋯ + Yoksay + Kabul et satırı taşıyor');
      expect(find.byTooltip(_tr.requestMoreActions), findsOneWidget);
      expect(find.text(_tr.accept), findsOneWidget);
    });

    testWidgets('Engellenenler satırı uzun adla taşmıyor', (tester) async {
      darYuzey(tester);
      await tester.pumpWidget(sar(
        const EngellenenlerEkrani(),
        olcek: darOlcek,
        overrides: [
          engellenenlerProvider.overrideWith((ref) => Stream.value(const [
                EngellenenKullanici(
                    uid: 'u',
                    displayName: 'Gökyüzü Gezgini Uzunadlı',
                    username: 'gokyuzu_gezgini_20'),
              ])),
        ],
      ));
      await _bekle(tester);
      tasmaYok(tester, neden: 'ad + Engeli kaldır satırı taşıyor');
      expect(find.text(_tr.unblockUser), findsOneWidget);
    });
  });

  group('kaynak bekçisi', () {
    test('engelleme iki kenarı ve engel kaydını TEK batch\'te yazıyor', () {
      final kaynak = _yorumsuz('lib/core/safety.dart');
      final bas = kaynak.indexOf('Future<void> kullaniciyiEngelle(');
      expect(bas, isNot(-1));
      final govde = kaynak.substring(bas, kaynak.indexOf('\n}\n', bas));

      // Ayrı yazımlar olsaydı biri düşünce ya engelsiz bir silme ya da
      // kenarları duran bir engel kalırdı (dürtme yolu açık).
      expect(govde, contains(
          "..delete(kullanicilar.doc(uid).collection('friends').doc(hedefUid))"));
      expect(govde, contains(
          "..delete(kullanicilar.doc(hedefUid).collection('friends').doc(uid))"));
      expect(govde, contains('..set(_blockedRef(hedefUid)'));
      expect('await'.allMatches(govde).length, 1,
          reason: 'tek yazım: batch.commit()');
      expect(govde, contains('await batch.commit();'));
    });

    test('engelleme dalı tek yoldan: önce removeFriend YOK, dikiş var', () {
      // Asıl geri dönüş "engellemeden önce removeFriend" idi (iki ayrı
      // yazım); yalnız `blockUser(` aramak onu yakalamıyordu.
      final dal = _dilim(
          _yorumsuz('lib/features/friends/friends_screen.dart'),
          'case _GuvenlikSecimi.engelle:',
          'case _GuvenlikSecimi.sikayet:');
      expect(dal, isNot(contains('removeFriend(')));
      // `l10n.blockUser` bir metin anahtarı; yasak olan çıplak çağrı.
      expect(RegExp(r'(?<![.\w])blockUser\(').hasMatch(dal), isFalse);
      expect(dal, contains('await engelle(friend.uid);'));
      expect(_yorumsuz('lib/features/friends/friends_screen.dart'),
          contains('final engelle = ref.read(engelleyiciProvider);'));
    });

    test('engeli kaldırıp davet: engel silimi iki kenarla TEK batch', () {
      final govde = _dilim(_yorumsuz('lib/core/friends.dart'),
          'Future<void> sendFriendRequest(', '\n}\n');
      // Kural `existsAfter` ile bakıyor: silim ayrı yazım olsaydı davet
      // engel dururken reddedilirdi ya da engel boşuna kalkardı.
      expect(govde,
          contains('if (engeliKaldir) batch.delete(_engelKaydi(uid, otherUid));'));
      expect('await'.allMatches(govde).length, 1,
          reason: 'tek yazım: batch.commit()');
      expect(govde.indexOf('batch.delete(_engelKaydi'),
          lessThan(govde.indexOf('await batch.commit();')));
    });

    for (final (yol, bas) in [
      ('lib/features/friends/friends_screen.dart', 'Future<void> _send() async {'),
      ('lib/features/friends/contacts_screen.dart', 'Future<void> _ekle() async {'),
    ]) {
      test('davet çağıranı kapıdan geçiyor: $yol', () {
        final govde = _dilim(_yorumsuz(yol), bas, '\n  }\n');
        final kapi = govde.indexOf('davetEngelKapisi(');
        final davet = govde.indexOf('sendFriendRequest(');
        expect(kapi, isNot(-1), reason: 'engel sorusu yok');
        expect(kapi, lessThan(davet), reason: 'soru davetten SONRA');
        expect(govde, contains('if (karar == DavetKarari.vazgec) return;'));
        expect(govde,
            contains('engeliKaldir: karar == DavetKarari.engeliKaldirVeGonder'));
        // Kurala çarpan davet "tekrar dene" demesin.
        expect(govde, contains('davetHataMetni(e, l10n)'));
        expect(govde, isNot(contains('friendlyError(')));
      });
    }

    test('gelen kutusu engel listesine göre süzülüyor', () {
      final panel = _dilim(
          _yorumsuz('lib/features/friends/friends_screen.dart'),
          'class _InboxPanel',
          'return GlassPanel(');
      expect(
          panel.replaceAll(RegExp(r'\s+'), ''),
          contains('gorunurTepkiler(ref.watch(myNudgesProvider).value??const[],'
              'ref.watch(engellenenKimliklerProvider).value)'));
      expect(panel, contains('return l10n.someRythoUser;'));
    });
  });

  group('saf işlevler', () {
    test('engellenenleriKur: kartı okunamayan kişi adsız ama listede', () async {
      final liste = await engellenenleriKur(
        [(uid: 'u-1', at: DateTime(2026, 10, 1)), (uid: 'u-2', at: DateTime(2026, 10, 2))],
        (uid) async {
          if (uid == 'u-2') throw Exception('kart okunamadı');
          return {'displayName': 'Deniz', 'username': 'deniz'};
        },
      );
      expect(liste.map((k) => k.uid), ['u-2', 'u-1']);
      expect(liste.first.displayName, isNull);
      expect(liste.last.displayName, 'Deniz');
      expect(liste.last.username, 'deniz');
    });

    test('engellenenleriKur: zamanı inmemiş kayıt en üstte, sonra en yeni',
        () async {
      final liste = await engellenenleriKur([
        (uid: 'eski', at: DateTime(2026, 9, 1)),
        (uid: 'yeni', at: DateTime(2026, 10, 20)),
        (uid: 'simdi', at: null),
        (uid: 'orta', at: DateTime(2026, 10, 1)),
      ], (_) async => null);
      expect(liste.map((k) => k.uid), ['simdi', 'yeni', 'orta', 'eski']);
    });

    test('gorunurTepkiler: engellenenin tepkisi düşer, sıra korunur', () {
      final tepkiler = [
        {'id': '1', 'fromUid': 'a', 'reaction': 'hug'},
        {'id': '2', 'fromUid': 'engelli', 'reaction': 'miss'},
        {'id': '3', 'fromUid': 'b', 'reaction': 'shine'},
      ];
      expect(gorunurTepkiler(tepkiler, {'engelli'}).map((t) => t['id']),
          ['1', '3']);
      expect(gorunurTepkiler(tepkiler, const {}).length, 3);
    });

    test('gorunurTepkiler: engel listesi yokken hiçbiri gösterilmez', () {
      expect(
          gorunurTepkiler([
            {'id': '1', 'fromUid': 'a', 'reaction': 'hug'},
          ], null),
          isEmpty);
    });

    test('davetHataMetni: kurala çarpan davet nötr, tekrar dene demiyor', () {
      final reddedildi = FirebaseException(
          plugin: 'cloud_firestore', code: 'permission-denied');
      expect(davetHataMetni(reddedildi, _tr), _tr.inviteNotSent);
      expect(davetHataMetni(reddedildi, _tr), isNot(_tr.errorGeneric));
      // Diğer hatalar ortak süzgeçten.
      expect(
          davetHataMetni(
              FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
              _tr),
          _tr.errorGeneric);
      expect(davetHataMetni(TimeoutException('x'), _tr), _tr.errorConnection);
    });
  });

  group('davet öncesi engel kapısı', () {
    Future<DavetKarari? Function()> kur(WidgetTester tester,
        Future<bool> Function(String) kontrol) async {
      DavetKarari? sonuc;
      await tester.pumpWidget(sar(
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async =>
                  sonuc = await davetEngelKapisi(context, ref, 'u-b', 'Deniz'),
              child: const Text('davet'),
            ),
          ),
        ),
        overrides: [engelKontroluProvider.overrideWithValue(kontrol)],
      ));
      await tester.tap(find.text('davet'));
      await _bekle(tester);
      return () => sonuc;
    }

    testWidgets('engel yoksa soru yok, düz davet', (tester) async {
      final sonuc = await kur(tester, (_) async => false);
      expect(find.byType(AlertDialog), findsNothing);
      expect(sonuc(), DavetKarari.gonder);
    });

    testWidgets('engellediğin kişide sorar; vazgeç hiçbir şey yazdırmaz',
        (tester) async {
      final sonuc = await kur(tester, (_) async => true);
      expect(find.text(_tr.inviteBlockedBody('Deniz')), findsOneWidget);
      await tester.tap(find.text(_tr.cancel));
      await _bekle(tester);
      expect(sonuc(), DavetKarari.vazgec);
    });

    testWidgets('onaylarsa engel kaldırılarak davet', (tester) async {
      final sonuc = await kur(tester, (_) async => true);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(_tr.inviteBlockedConfirm)));
      await _bekle(tester);
      expect(sonuc(), DavetKarari.engeliKaldirVeGonder);
    });

    testWidgets('engel okunamazsa düz davet; engel KALDIRILMAZ',
        (tester) async {
      final sonuc = await kur(tester, (_) async => throw Exception('çevrimdışı'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(sonuc(), DavetKarari.gonder);
    });
  });
}

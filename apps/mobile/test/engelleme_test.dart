// U17 (App Store 1.2): engelleme UYGULANIYOR ve gelen istek de
// engellenebiliyor/şikayet edilebiliyor.
//
// Kusur: Engelle + Şikayet et yalnız KABUL EDİLMİŞ arkadaşın sayfasındaydı;
// kullanıcı adıyla istek atan bir yabancıyı alıcı kabul etmeden ne
// engelleyebiliyor ne şikayet edebiliyordu. Engel kaydı da hiçbir ekranda
// görünmüyordu — kaldırmanın yolu yoktu.
//
// Firebase kurulmadan ölçülür: yazımlar `engelleyiciProvider` /
// `engelKaldiriciProvider` dikişlerinden, liste `engellenenlerProvider`
// geçersiz kılınarak. Batch'in İÇERİĞİ (iki kenar + engel kaydı tek
// commit'te) sahte Firestore olmadığı için kaynak bekçisiyle sabitlenir;
// kuralın kendisi backend/tests/test_engelleme.py'de.
import 'dart:io';

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

/// `//` ile başlayan satırlar atılır: bekçi, aradığı yapıyı ANLATAN bir
/// yorumu görüp geçmemeli.
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

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

    test('arkadaş ekranı eski iki adımlı engellemeye dönmedi', () {
      final kaynak = _yorumsuz('lib/features/friends/friends_screen.dart');
      // `l10n.blockUser` bir metin anahtarı; yasak olan çıplak çağrı.
      expect(RegExp(r'(?<![.\w])blockUser\(').hasMatch(kaynak), isFalse);
      expect(kaynak, contains('ref.read(engelleyiciProvider)'));
    });
  });
}

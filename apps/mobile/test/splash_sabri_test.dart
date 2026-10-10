// Açılış sahnesinin sabrı (D5, plan §5 son madde).
//
// Ölçülen kusur: `profileProvider` güvenilmez anlık görüntüyü süzüyor
// (doğru) ama çevrimdışı TAZE kurulumda sunucudan hiç yayın gelmiyor,
// süzgeç hiçbir şey geçirmiyor, sağlayıcı sonsuza dek `loading` kalıyor ve
// `_Gate` açılış sahnesini sonsuz döndürüyor — ne hata ne "tekrar dene".
//
// Onarım: ilk yayın için 12 sn üst sınır, HATA olayı yayar, akışı
// KAPATMAZ (ağ gelince aynı dinleyici toparlar). `Stream.timeout` bilerek
// kullanılmadı: her olay arası boşluğu ölçer ve profil günlerce
// değişmediği için sağlıklı oturumu her 12 sn'de hata sahnesine düşürürdü.
// Bu dosya o iki farkı da (tek hata, akış açık) çiviliyor.
//
// Zamanlayıcı `testWidgets`in sahte saatiyle ilerletilir (`tester.pump`
// süreli); `fake_async` paketi doğrudan bağımlılık değil.
//
// ⚠️ `StreamController.close()` dinleyicisi olmayan akışta HİÇ tamamlanmaz
// (dart-lang/sdk #19095); tearDown'da kapatmak testi sonsuza dek askıda
// bırakıyordu (ölçüldü: 9 dk). Kapatma yalnız dinleyici varken, gövdede.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart';

void main() {
  group('ilkYayinZamanAsimi', () {
    testWidgets('hiç yaymayan akış süre dolunca HATA yayar, akış KAPANMAZ, '
        'sonraki değer gelir', (tester) async {
      final kaynak = StreamController<int>();
      final hatalar = <Object>[];
      final degerler = <int>[];
      var kapandi = false;
      final abonelik = ilkYayinZamanAsimi(kaynak.stream, kProfilAkisiZamanAsimi)
          .listen(degerler.add,
              onError: (Object e) => hatalar.add(e),
              onDone: () => kapandi = true);
      addTearDown(abonelik.cancel);

      await tester.pump(kProfilAkisiZamanAsimi - const Duration(seconds: 1));
      expect(hatalar, isEmpty, reason: 'süre dolmadan hata yok');

      await tester.pump(const Duration(seconds: 2));
      expect(hatalar, hasLength(1));
      expect(hatalar.single, isA<TimeoutException>());
      expect(kapandi, isFalse, reason: 'akış kapanırsa toparlanamaz');

      // Çok sonra bile İKİNCİ hata yok (Stream.timeout farkı).
      await tester.pump(const Duration(minutes: 5));
      expect(hatalar, hasLength(1));

      // Ağ geldi: aynı dinleyici değeri alır.
      kaynak.add(7);
      await tester.pump();
      expect(degerler, [7]);
      expect(kapandi, isFalse);
    });

    testWidgets('ilk yayın zamanında gelirse hata YOK — sonraki uzun '
        'sessizlik de hata üretmez', (tester) async {
      final kaynak = StreamController<int>();
      final hatalar = <Object>[];
      final degerler = <int>[];
      final abonelik = ilkYayinZamanAsimi(kaynak.stream, kProfilAkisiZamanAsimi)
          .listen(degerler.add, onError: (Object e) => hatalar.add(e));
      addTearDown(abonelik.cancel);

      await tester.pump(const Duration(seconds: 1));
      kaynak.add(1);
      await tester.pump();
      // Profil günlerce değişmez: 12 sn'lik boşluklar hata DEĞİL.
      await tester.pump(const Duration(minutes: 10));
      kaynak.add(2);
      await tester.pump();

      expect(degerler, [1, 2]);
      expect(hatalar, isEmpty,
          reason: 'ilk yayından sonraki sessizlik hata üretiyor — '
              'Stream.timeout davranışı geri geldi');
    });

    testWidgets('kaynağın kendi hatası olduğu gibi geçer; kaynak kapanınca '
        'kapanır; iptal sayacı durdurur', (tester) async {
      final kaynak = StreamController<int>();
      final hatalar = <Object>[];
      var kapandi = false;
      final abonelik = ilkYayinZamanAsimi(kaynak.stream, kProfilAkisiZamanAsimi)
          .listen((_) {},
              onError: (Object e) => hatalar.add(e),
              onDone: () => kapandi = true);

      kaynak.addError(StateError('izin yok'));
      await tester.pump();
      expect(hatalar.single, isA<StateError>());
      // Kaynak hata verdiyse zaman aşımı ayrıca üstüne binmez.
      await tester.pump(const Duration(seconds: 20));
      expect(hatalar, hasLength(1));

      unawaited(kaynak.close());
      await tester.pump();
      expect(kapandi, isTrue);
      // `await cancel()` YOK: bitmiş aboneliğin cancel'ı Dart'ın kök
      // bölgedeki hazır Future'ını döndürür, sahte saat onu hiç
      // ilerletmez ve test askıda kalır (ölçüldü: 6 dk). Beklenmeden
      // bırakılır; zamanlayıcı sayacı zaten durmuş durumda.
      unawaited(abonelik.cancel());
    });

    testWidgets('abonelik iptal edilince sayaç bekleyen zamanlayıcı bırakmaz',
        (tester) async {
      final kaynak = StreamController<int>();
      final abonelik = ilkYayinZamanAsimi(kaynak.stream, kProfilAkisiZamanAsimi)
          .listen((_) {});
      await tester.pump(const Duration(seconds: 1));
      // Beklenmez (bkz. üstteki test): iptalin yan etkisi — sayacın
      // kesilmesi — senkron.
      unawaited(abonelik.cancel());
      // Buradan sonra SÜRE İLERLETİLMEZ: sahte saat, test biterken hâlâ
      // bekleyen bir zamanlayıcıyı "A Timer is still pending" diye
      // fırlatır — iptal sayacı kesmediyse bekçi o assert'ten kırmızı olur.
      // (İlk hâli 20 sn ilerletiyordu; kesilmemiş sayaç o sürede ateşleyip
      // iz bırakmadan sönüyordu ve mutasyon YEŞİL kalıyordu — ölçüldü.)
      await tester.pump();
    });

    test('üst sınır 12 sn — Firestore çevrimdışı tespitinin üstünde', () {
      expect(kProfilAkisiZamanAsimi, const Duration(seconds: 12));
    });
  });

  group('kaynak bekçisi', () {
    String yorumsuz(String yol) => File(yol)
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((s) => !s.trimLeft().startsWith('//'))
        .join('\n');

    test('profil akışı ilk yayın sınırından geçiyor; Stream.timeout yok', () {
      final k = yorumsuz('lib/core/providers.dart');
      expect(k, contains('ilkYayinZamanAsimi(akis, kProfilAkisiZamanAsimi)'));
      expect(k, isNot(contains('.timeout(')),
          reason: 'Stream.timeout her olay arasını ölçer; sağlıklı oturumu '
              'hata sahnesine düşürür');
    });

    test('_Gate profil hatasında "tekrar dene" sağlayıcıyı geçersiz kılar', () {
      // Zaman aşımı bir hata olayı; kapı onu hata sahnesiyle karşılar ve
      // tekrar dene YENİ bir abonelik (yeni 12 sn) başlatmalı.
      final k = yorumsuz('lib/main.dart');
      expect(k,
          contains('hataSahnesi(e, () => ref.invalidate(profileProvider)'));
    });
  });
}

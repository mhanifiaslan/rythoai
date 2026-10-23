import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/profile/legal_texts.dart';

/// Gizlilik politikasinin ICERIGI ve KODLA UYUMU.
///
/// Bu dosyanin varlik sebebi su: hukuki metin, urunun ne yaptigina dair bir
/// IDDIA. Kod degisip metin ayni kalirsa iddia yalana doner ve bu, teknik bir
/// kusurdan cok daha pahaliya patlar.
///
/// Yuz okuma bolumu su uc seyi soyluyor ve ucu de kodda dogrulanabilir:
/// goruntu sunucuya gitmiyor, diske YAZILMIYOR, sunucuya yalnizca turetilmis
/// oranlar gidiyor.

String _kaynak(String yol) => File(yol).readAsStringSync();

void main() {
  group('yuz okuma bolumu', () {
    test('her iki dilde de VAR', () {
      expect(
        kPrivacyPolicyTr.any((b) => b.$1 == 'Yüz okuma'),
        isTrue,
        reason: 'Turkce politikada yuz okuma bolumu yok',
      );
      expect(
        kPrivacyPolicyEn.any((b) => b.$1 == 'Face reading'),
        isTrue,
        reason: 'Ingilizce politikada yuz okuma bolumu yok',
      );
    });

    test('rizanin geri alinabilirligini soyluyor', () {
      final tr = kPrivacyPolicyTr
          .firstWhere((b) => b.$1 == 'Yüz okuma')
          .$2;
      // Riza geri alinabilir olmak zorunda (GDPR Md.7/2) ve metin bunu
      // SOYLEMELI; uygulamada var olup metinde olmamasi eksik beyandir.
      expect(tr, contains('geri'));
      expect(tr, contains('Gizlilik'));
    });

    test('karar amacli kullanilmayacagini soyluyor', () {
      final tr =
          kPrivacyPolicyTr.firstWhere((b) => b.$1 == 'Yüz okuma').$2;
      final en =
          kPrivacyPolicyEn.firstWhere((b) => b.$1 == 'Face reading').$2;
      // Ise alim / kredi / sigorta gibi kararlarda kullanim, duzenleyici
      // tarafta en riskli alan. Metin bunu acikca disliyor.
      expect(tr.toLowerCase(), contains('işe alım'));
      expect(en.toLowerCase(), contains('employment'));
    });
  });

  group('dil yalitimi', () {
    test('Ingilizce politikada Turkce karakter yok', () {
      // Projede baska katmanlarda da uygulanan kural: dil karismasin.
      final govde = kPrivacyPolicyEn.map((b) => '${b.$1} ${b.$2}').join(' ');
      for (final harf in ['ğ', 'ş', 'ı', 'İ', 'ç', 'ö', 'ü', 'Ğ', 'Ş']) {
        expect(govde.contains(harf), isFalse,
            reason: 'Ingilizce metinde Turkce harf: $harf');
      }
    });
  });

  group('metin KODLA uyusuyor mu', () {
    test('politika "diske yazilmaz" diyor — kod fotograf CEKMIYOR', () {
      // Onceki surum `takePicture()` ile gecici bir dosya yaziyordu. O cagri
      // geri gelirse politika yalan soylemeye baslar.
      //
      // Aranan sey CAGRI kalibi (`.takePicture(`), duz metin degil: dosyanin
      // aciklama satirlari eski davranisi ANLATIYOR ve `takePicture()` sozu
      // orada gecmeye devam etmeli. Ilk surum bunu ayirt etmiyor ve kendi
      // yorumuna takiliyordu.
      final ekran =
          _kaynak('lib/features/face/face_capture_screen.dart');
      expect(ekran.contains('.takePicture('), isFalse,
          reason: 'fotograf cekiliyor ama politika "diske yazilmaz" diyor');
    });

    test('sunucuya giden alanlar oran; koordinat gonderilmiyor', () {
      final geometri = _kaynak('lib/features/face/face_geometry.dart');
      // `toJson` yalnizca oran alanlari tasimali. Ham landmark adlari
      // gecerse sunucuya kisiye ozgu bir imza gidiyor demektir.
      final baslangic = geometri.indexOf('Map<String, double> toJson()');
      final bitis = geometri.indexOf('static double _yuvarla');
      expect(baslangic, greaterThan(-1));
      final govde = geometri.substring(baslangic, bitis);
      for (final yasak in ['faceOval', 'chin', 'noseBase', 'eyeLeft']) {
        expect(govde.contains("'$yasak'"), isFalse,
            reason: '$yasak sunucuya gonderiliyor');
      }
    });
  });

  group('silme vaadi KODLA uyusuyor mu', () {
    // Kapali test denetimi (2026-09-14): politika "Hesabini sildiginde tum
    // veriler kalici olarak silinir" diyordu; oysa sunucu yalniz
    // `users/{uid}` agacini temizliyordu. Uc koleksiyon uid tasiyarak
    // disarida kaliyordu ve biri (`feedback`) kullanicinin KENDI yazdigi
    // serbest metindi. Yani vaat tutulmuyordu.
    //
    // Simdi ikisi birden dogrulaniyor: sunucu onlari siliyor VE metin
    // silinmeyenleri adiyla sayiyor. Biri degisip digeri ayni kalirsa
    // burasi duser.

    String backend(String yol) => _kaynak('../../backend/$yol');

    test('sunucu uid alanli koleksiyonlari siliyor', () {
      final kod = backend('services/account_service.py');
      for (final ad in ['usageEvents', 'phoneAttempts', 'feedback']) {
        expect(kod.contains('"$ad"'), isTrue,
            reason: '$ad silme kapsaminda degil ama metin "silinir" diyor');
      }
      expect(kod.contains('_delete_uid_documents(client, uid, sayac)'), isTrue,
          reason: 'silme fonksiyonu delete_account icinden cagrilmiyor');
    });

    test('saklanan kayitlar HER IKI dilde de adiyla yaziyor', () {
      // Yazili olmayan istisna, istisna degil ihlaldir.
      final tr = kPrivacyPolicyTr.map((b) => '${b.$1} ${b.$2}').join(' ');
      final en = kPrivacyPolicyEn.map((b) => '${b.$1} ${b.$2}').join(' ');

      expect(tr.contains('Satın alma ve iade'), isTrue,
          reason: 'TR metin saklanan mali kaydi anmiyor');
      expect(tr.contains('denetim izi'), isTrue,
          reason: 'TR metin saklanan denetim izini anmiyor');
      expect(en.toLowerCase().contains('purchase and refund'), isTrue,
          reason: 'EN metin saklanan mali kaydi anmiyor');
      expect(en.toLowerCase().contains('audit trail'), isTrue,
          reason: 'EN metin saklanan denetim izini anmiyor');
    });

    test('metin artik KOSULSUZ "her sey silinir" demiyor', () {
      // Kosulsuz cumle geri gelirse istisnalar yalan olur.
      final tr = kPrivacyPolicyTr.map((b) => b.$2).join(' ');
      final en = kPrivacyPolicyEn.map((b) => b.$2).join(' ');
      expect(tr.contains('tüm veriler kalıcı olarak silinir'), isFalse);
      expect(en.contains('all of it is permanently deleted'), isFalse);
    });
  });

  group('eklenen kişiler bölümü', () {
    // @-bahsetme (chat_screen.dart _selectMention) kişinin CİHAZDAKİ
    // etiketini mesaj gövdesine yazıyor; mesaj sunucuya gidip konu arşivine
    // yazılıyor. Metin ise "ADI sunucuya HİÇ gönderilmez" diyordu. Mutlak
    // cümle tek bir akışla bile yalana döner.
    test('mutlak "adı hiç gönderilmez" iddiası YOK', () {
      final tr = kPrivacyPolicyTr.map((b) => b.$2).join(' ');
      final en = kPrivacyPolicyEn.map((b) => b.$2).join(' ');
      expect(tr.contains('ADI sunucuya HİÇ gönderilmez'), isFalse);
      expect(en.contains('never sent to our servers'), isFalse);
    });

    test('sohbet istisnası HER İKİ dilde yazılı', () {
      final tr =
          kPrivacyPolicyTr.firstWhere((b) => b.$1 == 'Eklediğin kişiler').$2;
      final en =
          kPrivacyPolicyEn.firstWhere((b) => b.$1 == 'People you add').$2;
      expect(tr.contains('konu arşivine'), isTrue,
          reason: 'sohbette yazılan adın nereye gittiği yazılmıyor');
      expect(en.toLowerCase().contains('topic archive'), isTrue);
    });

    test('kod hâlâ adı gövdeye yazıyor — metin bu yüzden böyle', () {
      // Akış bir gün kapatılırsa metin FAZLA şey söylüyor olur: o gün burası
      // düşer ve üç beyan yeniden okunur.
      final kod = _kaynak('lib/features/chat/chat_screen.dart');
      expect(kod.contains(r"'${aday.display} '"), isTrue,
          reason: 'mention artık adı gövdeye yazmıyorsa metin daraltması '
              'gereksiz kalmış olabilir');
    });
  });

  // Sahip kararı 2026-10-22: yapay zeka aktarım onayı YALNIZ kurulumun ilk
  // adımında, şartlar kutusundan AYRI ve ZORUNLU ikinci bir kutuyla alınır;
  // ayrı onay sayfası, "Şimdi değil", Profil > Gizlilik'teki anahtar ve
  // onaya bağlı kapanan özellik YOK. Geri alma yolu hesap silme. Metin bir
  // gün eski modele (U06 sayfası) geri yazılırsa kullanıcıya olmayan bir
  // anahtarı, olmayan bir "kapalı" hâli vaat eder — bu grup o yüzden var.
  // Sahip kararı 2026-10-23: kutu ve onay cümlesi sağlayıcı ADI taşımaz
  // ("üçüncü taraf yapay zeka hizmetleri"); sağlayıcıyı politikanın geri
  // kalanı adıyla anar. Dört kopyanın (uygulama TR/EN + web TR/EN) cümle
  // düzeyindeki bekçileri `backend/tests/test_gizlilik_kopyalari.py`ta;
  // burada uygulama kopyası ve KUTUNUN KENDİSİ (ARB) duruyor.
  // Grup `ai_onay_test.dart`tan taşındı: içerik bekçisi, onay sayfasının
  // testleriyle birlikte silinmesin diye politikanın kendi dosyasında durur.
  group('yapay zeka bölümü', () {
    String bolum(LegalSections s, String baslik) =>
        s.firstWhere((b) => b.$1 == baslik).$2;
    final aiTr = bolum(kPrivacyPolicyTr, 'Yapay zeka ile işleme');
    final aiEn = bolum(kPrivacyPolicyEn, 'AI processing');

    Map<String, dynamic> arb(String dil) =>
        jsonDecode(_kaynak('lib/l10n/app_$dil.arb')) as Map<String, dynamic>;

    test('Gemini\'yi, Google LLC\'yi ve veri kategorilerini adlandırır', () {
      // Kutu sağlayıcı adı taşımıyor ve "kullanılan hizmet Gizlilik
      // Politikası'nda yazar" diyor; o söz ancak politika bugünkü
      // sağlayıcıyı şirketiyle ve hizmet adıyla andıkça doğru.
      for (final metin in [aiTr, aiEn]) {
        expect(metin, contains('Gemini API'));
        expect(metin, contains('Google LLC'));
        expect(metin, contains('BaZi'));
        expect(metin, contains('I Ching'));
      }
      expect(aiTr, contains('günlük notların'));
      expect(aiEn, contains('journal notes'));
    });

    test('onay kurulumun ilk adımında, ayrı ve zorunlu kutuyla', () {
      expect(aiTr, contains('ilk kurulum adımında'));
      expect(aiTr, contains('AYRI ve ZORUNLU'));
      expect(aiTr, contains('kurulum tamamlanmaz'));
      expect(aiTr, contains('üçüncü taraf yapay zeka hizmetlerine'));
      expect(aiEn, contains('first step of the app\'s initial setup'));
      expect(aiEn, contains('SEPARATE, MANDATORY'));
      expect(aiEn, contains('Setup cannot be completed'));
      expect(aiEn, contains('third-party AI services'));
    });

    test('kurulum kutusu sağlayıcı adı taşımaz, sağlayıcıyı politikaya '
        'bırakır', () {
      // K1 (sahip kararı 2026-10-23): "bugün Gemini yarın başka bir hizmet
      // olur". Kutu metni sağlayıcıyı adıyla anarsa sağlayıcı değiştiği gün
      // kullanıcının işaretlediği onay, verinin gittiği yeri YANLIŞ
      // söyler — ve o kutu bir daha gösterilmiyor (yalnız kurulumda), yani
      // düzeltilemez. Liste bugünkü sağlayıcıyla sınırlı değil: yarının
      // adı da kutuya girmemeli. Kutu yerine politikayı gösterir; o
      // gösterilen yerin sağlayıcıyı adıyla andığı bir üstteki testte.
      const saglayicilar = [
        'Gemini',
        'Google',
        'Claude',
        'Anthropic',
        'OpenAI',
        'GPT',
      ];
      final kutuTr = arb('tr')['wizardAiConsentLabel'] as String;
      final kutuEn = arb('en')['wizardAiConsentLabel'] as String;
      for (final ad in saglayicilar) {
        expect(kutuTr.contains(ad), isFalse,
            reason: 'TR kutu sağlayıcı adı taşıyor: $ad');
        expect(kutuEn.contains(ad), isFalse,
            reason: 'EN kutu sağlayıcı adı taşıyor: $ad');
      }
      expect(kutuTr, contains('üçüncü taraf yapay zeka hizmetlerine'));
      expect(kutuTr, contains('Gizlilik Politikası'));
      expect(kutuEn, contains('third-party AI services'));
      expect(kutuEn, contains('Privacy Policy'));
    });

    test('geri alma yolu hesap silme — menü adı ARB\'den birebir', () {
      // Yol elle yazılsaydı menü etiketi değişince metin var olmayan bir
      // düğmeyi gösterirdi; etiketler sözlükten okunup kurulur.
      final tr = arb('tr');
      final en = arb('en');
      final yolTr =
          '${tr['tabProfile']} > ${tr['accountSection']} > ${tr['deleteAccount']}';
      final yolEn =
          '${en['tabProfile']} > ${en['accountSection']} > ${en['deleteAccount']}';
      expect(aiTr, contains(yolTr));
      expect(aiEn, contains(yolEn));
      // Hesap Ekranı'nda düğme gerçekten o etiketle duruyor mu.
      expect(_kaynak('lib/features/profile/account_screen.dart'),
          contains('l10n.deleteAccount'));
    });

    test('kaldırılan onay modeli metne geri gelmedi', () {
      // Profil > Gizlilik YÜZ OKUMA rızası için hâlâ doğru (o bölümde
      // durur); yasak olan, yapay zeka bölümünde anılması. Listenin ikinci
      // yarısı U06'nın menü adı TAŞIMAYAN cümleleri: menü adı silinip
      // "uygulama içinde AYRI … iznini isteriz" / "Geri aldığın andan
      // itibaren gönderim durur" bırakılsa ilk yarı görmezdi — olmayan bir
      // uygulama içi izin ve geri alma vaadi okunurken bekçi yeşil kalırdı.
      for (final eski in [
        'Profil > Gizlilik',
        'kapalı kalır',
        'İzin vermezsen',
        'yeniden verebilir',
        'uygulama içinde AYRI',
        'Geri aldığın andan',
        'zorunlu değil',
      ]) {
        expect(aiTr.contains(eski), isFalse, reason: 'TR: "$eski" döndü');
      }
      for (final eski in [
        'Profile > Privacy',
        'stay off',
        'If you do not give it',
        'give this permission again',
        'inside the app',
        'from the moment you withdraw',
        'not mandatory',
      ]) {
        expect(aiEn.contains(eski), isFalse, reason: 'EN: "$eski" döndü');
      }
      final bildirimTr = bolum(kPrivacyPolicyTr, 'Bildirimler');
      final bildirimEn = bolum(kPrivacyPolicyEn, 'Notifications');
      for (final eski in ['iznin varsa', 'İznin yoksa', 'teknik satır']) {
        expect(bildirimTr.contains(eski), isFalse,
            reason: 'TR bildirim: "$eski" döndü');
      }
      for (final eski in [
        'allowed AI processing',
        'If you have not',
        'technical line',
      ]) {
        expect(bildirimEn.contains(eski), isFalse,
            reason: 'EN bildirim: "$eski" döndü');
      }
    });

    test('eski yanlış iddialar geri gelmedi', () {
      final bildirimTr = bolum(kPrivacyPolicyTr, 'Bildirimler');
      final bildirimEn = bolum(kPrivacyPolicyEn, 'Notifications');
      // Sabah bildirimi haritaya değen transitten yazılıyor — "kişiye özel
      // değildir" demek ölçülene aykırıydı.
      expect(bildirimTr.contains('kişiye özel değildir'), isFalse);
      expect(bildirimEn.contains('not individually personalised'), isFalse);
      // 53'ün "doğum tarihin/saatin değil" iddiası koda aykırıydı: BaZi
      // istemi doğum saatini, Yıl Haritası güneş dönüşü anını taşıyor.
      expect(aiTr.contains('doğum tarihin/saatin değil'), isFalse);
      expect(aiEn.contains('not your birth date or time'), isFalse);
    });

    test('kod BaZi istemine doğum saatini koyuyor — metin bu yüzden söylüyor',
        () {
      // `_bazi_notes` gerçek güneş zamanı beyanını doğumun DUVAR SAATİYLE
      // (`birth_local`'ın SS:DD kısmı) kuruyor ve beyan BaZi istemine
      // giriyor; şans sütunu satırı takvim yılı + yaş aralığı taşıyor (doğum
      // yılı ikisinin farkı). Kod bunu bırakırsa burası düşer ve metindeki
      // "doğum saatin" / "yaş aralıkları" beyanı yeniden okunur.
      final notlar = _kaynak('../../backend/services/prompts/__init__.py');
      expect(notlar, contains('local=yerel[11:16]'));
      final rapor = _kaynak('../../backend/services/report_service.py');
      expect(rapor, contains("lp['from_age']"));
      expect(aiTr, contains('doğum saatin'));
      expect(aiTr, contains('yaş aralıkları'));
      expect(aiEn, contains('birth time'));
      expect(aiEn, contains('age ranges'));
    });
  });
}

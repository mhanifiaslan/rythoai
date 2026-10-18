// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get atlasYearChart => 'Doğum gününden doğum gününe';

  @override
  String get atlasYearChartSubtitle => 'Yıl haritan (güneş dönüşü)';

  @override
  String get atlasInnerCalendar => 'İç mevsim';

  @override
  String get atlasInnerCalendarSubtitle => 'Progres Ay + yaşam yayı';

  @override
  String get wizardWelcomeTitle => 'Yolculuk başlıyor';

  @override
  String get wizardWelcomeBody =>
      'Birkaç adımda haritanı çizeceğiz: doğduğun an, gökyüzünün o anki hâli. Her adımda bir yıldız yanacak.';

  @override
  String get wizardConsentLabel =>
      'Kullanım Şartları\'nı ve Gizlilik Politikası\'nı okudum, kabul ediyorum. 13 yaşından büyüğüm.';

  @override
  String get wizardDateTitle => 'Hangi gün doğdun?';

  @override
  String get wizardDateBody =>
      'Gökyüzü her gün başka bir düzendeydi — seninki hangisiydi?';

  @override
  String get wizardTimeTitle => 'Saat kaçtı?';

  @override
  String get wizardTimeBody =>
      'Doğum saati Yükselen\'ini ve evlerini belirler. Bilmiyorsan sorun değil — dürüstçe onsuz hesaplarız.';

  @override
  String get wizardTimeUnknownNote =>
      'Saatsiz doğumda Yükselen ve evler hesaplanmaz; okuma gezegen düzeyinde kalır.';

  @override
  String get wizardPlaceTitle => 'Nerede doğdun?';

  @override
  String get wizardPlaceBody =>
      'Konum, gökyüzünün sana göre nasıl durduğunu belirler — ufkun neresinde ne yükseliyordu?';

  @override
  String get wizardGenderTitle => 'BaZi için bir ayrıntı';

  @override
  String get wizardGenderBody =>
      'BaZi (Dört Sütun) şans dönemlerinin yönünü cinsiyetten alır. Belirtmezsen o yön hesaplanmaz; gerisi aynı.';

  @override
  String get wizardNext => 'Devam ✦';

  @override
  String get wizardFinish => 'Haritamı çiz';

  @override
  String get wizardNotifyTitle => 'Günün okuması hazır olunca?';

  @override
  String get wizardNotifyBody =>
      'Günlük okuman ve serin için nazik bir hatırlatma gönderelim mi? Sessiz saatlerini Profil\'den ayarlayabilirsin.';

  @override
  String get wizardNotifyAllow => 'Haber ver 🔔';

  @override
  String get genderUnspecified => 'Belirtmedim';

  @override
  String get wizardNotifyNotNow => 'Şimdi değil';

  @override
  String wizardStepOf(int current, int total) {
    return 'Adım $current/$total';
  }

  @override
  String get deviceConflictBodyUnknown =>
      'Başka bir cihazda giriş yapıldı. Rytho+ aynı anda tek cihazda kullanılabilir — burada devam etmek için \"Bu cihazda kullan\"a dokun.';

  @override
  String get emailHint => 'ad@eposta.com';

  @override
  String get countrySearchHint => 'Ülke ara…';

  @override
  String get phoneSmsDisabled =>
      'SMS doğrulama şu an açık değil. Daha sonra tekrar dene.';

  @override
  String get phoneTemporarilyBlocked =>
      'Çok sayıda deneme yüzünden doğrulama geçici olarak durduruldu. Birkaç saat sonra tekrar dene.';

  @override
  String get purchaseEntitlementMissing =>
      'Ödeme tamamlandı ama abonelik doğrulanamadı. \"Satın alımları geri yükle\"yi dene; sürerse bize yaz — ödemen güvende.';

  @override
  String get purchaseWaitingStore =>
      'Mağaza ile konuşuluyor… Bu ekranı kapatma.';

  @override
  String get purchaseWaitingLong =>
      'Mağaza işlemi hâlâ sürüyor. Bu ekranı kapatsan da satın alman kaybolmaz: sonuç hesabına kendiliğinden işlenir.';

  @override
  String get purchaseLeaveScreen => 'Bu ekranı kapat';

  @override
  String get purchasePendingServer =>
      'Satın alman alındı. Hesabına yansıması birkaç saniye sürebilir.';

  @override
  String get avatarEditTitle => 'Fotoğrafı yerleştir';

  @override
  String get avatarEditHint =>
      'Sürükleyerek konumlandır, iki parmakla yakınlaştır.';

  @override
  String get avatarUpdated => 'Profil fotoğrafın güncellendi ✨';

  @override
  String get avatarChangeFailed =>
      'Fotoğraf yüklenemedi. Bağlantını kontrol edip tekrar dene.';

  @override
  String get phoneAppNotVerified =>
      'Uygulama doğrulaması başarısız oldu. Uygulamayı güncelleyip tekrar dene.';

  @override
  String get citySearchHint => 'Şehir ara…';

  @override
  String get citySearchPrompt =>
      'Doğduğun şehrin adını yazmaya başla — 34 bin şehir arasından bul.';

  @override
  String get citySearchNoResults =>
      'Listede bulunamadı — yazdığın adla da kaydedebilirsin.';

  @override
  String citySearchUseAsTyped(String query) {
    return '\"$query\" olarak kaydet';
  }

  @override
  String get residenceCityTitle => 'Yaşadığın şehir';

  @override
  String get residenceCityRowSubtitle => 'Yıl haritası buraya kurulur';

  @override
  String get residenceCityBody =>
      'Yıl haritası, doğum gününde bulunduğun yere kurulur — şehir Yükselen\'i ve evleri değiştirir. Boş bırakırsan doğum şehrin kullanılır.';

  @override
  String get solarReturnTitle => 'Yıl Haritası';

  @override
  String get solarReturnWaitStage1 => 'Güneş\'in dönüş anı hesaplanıyor…';

  @override
  String get solarReturnWaitStage2 => 'Yılın okuması yazılıyor…';

  @override
  String get solarReturnLockedBody =>
      'Güneş\'in doğum boylamına döndüğü ana kurulan yıl haritası ve Rytho\'nun yıl okuması Rytho+ ile açılır.';

  @override
  String get solarReturnMoment => 'Dönüş anı';

  @override
  String solarReturnNext(String date) {
    return 'Sonraki dönüş: $date';
  }

  @override
  String get solarReturnIdentity => 'Yılın kimliği';

  @override
  String get solarReturnAsc => 'Yıl Yükseleni';

  @override
  String get solarReturnSunHouse => 'Güneş\'in yıl evi';

  @override
  String solarReturnHouseN(int n) {
    return '$n. ev';
  }

  @override
  String get solarReturnMoon => 'Yıl Ay\'ı';

  @override
  String get solarReturnNote => 'Rytho\'nun yıl okuması';

  @override
  String get innerCalendarTitle => 'İç mevsim';

  @override
  String get innerCalendarWaitStage1 => 'Progres harita ilerletiliyor…';

  @override
  String get innerCalendarWaitStage2 => 'Progres Ay\'ın mevsimi okunuyor…';

  @override
  String get innerCalendarLockedBody =>
      'Progres Ay\'ın iç mevsimi ve yaşam yayın Rytho+ ile açılır.';

  @override
  String get innerCalendarProgMoon => 'Progres Ay — iç mevsimin';

  @override
  String innerCalendarNextSign(String date) {
    return '$date → yeni burca geçiş';
  }

  @override
  String get innerCalendarActive => 'Şu an etkin';

  @override
  String get innerCalendarArc => 'Yaşam yayı (solar arc)';

  @override
  String get innerCalendarNote => 'Rytho\'nun iç mevsim okuması';

  @override
  String get appTagline =>
      'Kadim bilgelik, hassas gökyüzü hesabıyla buluşur.\nHaritan çizilir, yolun aydınlanır.';

  @override
  String get signInWithGoogle => 'Google ile giriş';

  @override
  String get orDivider => 'ya da';

  @override
  String get signIn => 'Giriş yap';

  @override
  String get signUp => 'Üye ol';

  @override
  String get email => 'E-posta';

  @override
  String get password => 'Şifre';

  @override
  String get forgotPassword => 'Şifremi unuttum';

  @override
  String get tabSky => 'Gökyüzü';

  @override
  String get tabAtlas => 'Atlas';

  @override
  String get tabFriends => 'Arkadaşlar';

  @override
  String get tabProfile => 'Profil';

  @override
  String get greetingMorning => 'Günaydın';

  @override
  String get greetingDay => 'İyi günler';

  @override
  String get greetingEvening => 'İyi akşamlar';

  @override
  String get greetingNight => 'İyi geceler';

  @override
  String get todaysInsight => 'Bugünün İçgörüsü';

  @override
  String get skyNow => 'Şu An Gökyüzünde';

  @override
  String get iChing => 'I Ching';

  @override
  String get iChingSubtitle => 'Değişimler Kitabı';

  @override
  String get birthHexagram => 'Doğum Kapısı';

  @override
  String get birthHexagramSubtitle => '64 kapı';

  @override
  String get birthHexagramTitle => 'Doğum Heksagramı';

  @override
  String birthHexagramGateLine(int gate, int line) {
    return 'Kapı $gate · $line. çizgi';
  }

  @override
  String birthHexagramGateOnly(int gate) {
    return 'Kapı $gate';
  }

  @override
  String birthHexagramSunAt(String deg) {
    return 'Doğumda Güneş: $deg°';
  }

  @override
  String birthHexagramBoundary(int a, int b) {
    return 'Doğum saati bilinmediği için kapın $a ya da $b olabilir.';
  }

  @override
  String get birthHexagramLockedBody =>
      'Doğum anındaki Güneş\'in 64 kapı çarkındaki yeri — kalıcı karakter kapın. Rytho+ ile açılır.';

  @override
  String get birthHexagramNote => 'Rytho\'nun kapı okuması';

  @override
  String get birthHexagramGatePassage => 'Kapının Dokusu';

  @override
  String get faceReadingTileSubtitle => 'Firaset sanatı';

  @override
  String get baZi => 'BaZi';

  @override
  String get baZiSubtitle => 'Dört Sütun';

  @override
  String get personalReadingLocked => 'Sana özel günlük okuma';

  @override
  String get personalReadingLockedBody =>
      'Senin haritanla üretilen günlük yorum Rytho+ ile açılır.';

  @override
  String personalReadingLockedBodyWithSign(String sign) {
    return 'Genel $sign yorumu hikâye halkasında. Rytho+ ile bu okuma senin Ay’ını ve Yükselen’ini de hesaba katar.';
  }

  @override
  String get personalReadingTitle => 'Sana özel';

  @override
  String get natalLockedTitle => 'Doğum haritası analizi';

  @override
  String get natalLockedBody =>
      'Gezegen konumların, evlerin ve açıların derin yorumu Rytho+ ile açılır.';

  @override
  String get baziLockedTitle => 'BaZi — Dört Sütun';

  @override
  String get baziLockedBody =>
      'Day Master, On Tanrı ve şans sütunları analizi Rytho+ ile açılır.';

  @override
  String get iChingLockedTitle => 'İ Ching — Değişimler Kitabı';

  @override
  String get iChingLockedBody =>
      'Soru sor, gerçek olasılıklarla çekim yap, Rytho yorumuyla oku — Rytho+ ile açılır.';

  @override
  String get synastryLockedTitle => 'İkili çark';

  @override
  String get synastryLockedBody =>
      'İki haritanın üst üste okuması Rytho+ ile açılır.';

  @override
  String get addFriend => 'Arkadaş ekle';

  @override
  String get usernameLabel => 'KULLANICI ADI';

  @override
  String get usernameHeadline => 'Arkadaşların seni bulabilsin';

  @override
  String get usernameBody =>
      'Bir kullanıcı adı seç. Arkadaş eklemek kullanıcı adı ve davet bağlantısıyla olur; istersen Gizlilik bölümünden rehber eşleşmesini de açabilirsin.';

  @override
  String get usernameHint => 'kullaniciadi';

  @override
  String get claimUsername => 'Kullanıcı adını al';

  @override
  String get usernameInvalid =>
      '3-20 karakter; yalnızca küçük harf, rakam ve alt çizgi.';

  @override
  String get usernameEmpty => 'Kullanıcı adı boş olamaz.';

  @override
  String get usernameTaken => 'Bu kullanıcı adı alınmış, başka bir tane dene.';

  @override
  String get copyInviteLink => 'Davet bağlantısını kopyala';

  @override
  String get inviteLinkCopied => 'Davet bağlantısı kopyalandı.';

  @override
  String get shareInviteInstead => 'Bunun yerine davet bağlantımı paylaş';

  @override
  String get sendInvite => 'Davet gönder';

  @override
  String inviteSent(String username) {
    return '@$username kullanıcısına davet gönderildi.';
  }

  @override
  String userNotFound(String username) {
    return '@$username bulunamadı.';
  }

  @override
  String get cannotAddSelf => 'Kendini ekleyemezsin.';

  @override
  String get inboxLabel => 'SANA GELENLER';

  @override
  String get noFriendsYet => 'Henüz kimse yok';

  @override
  String get noFriendsBody =>
      'Bir arkadaşını kullanıcı adıyla ekle; serilerinizi görün ve her gün aranızdaki dinamiği okuyun.';

  @override
  String get incomingRequests => 'Gelen davetler';

  @override
  String get pendingInvites => 'Yanıt bekleyen davetlerin';

  @override
  String get accept => 'Kabul et';

  @override
  String get ignore => 'Yoksay';

  @override
  String get pending => 'Bekliyor';

  @override
  String get withdrawInvite => 'Daveti geri al';

  @override
  String get readToday => 'Bugün okumasını yaptı';

  @override
  String get notReadToday => 'Bugün henüz okumadı';

  @override
  String get streakHidden => 'Serisi gizli';

  @override
  String get friendLabel => 'Arkadaşın';

  @override
  String get streakHiddenByFriend => 'Serisini gizli tutuyor';

  @override
  String get readTodayDone => 'Bugünkü okumasını yaptı';

  @override
  String get dyadLabel => 'Bugün aranızda';

  @override
  String get dyadDisclaimer =>
      'Bu okuma yalnızca bugün için geçerlidir ve yarın değişir. Kalıcı bir uyum puanı vermiyoruz.';

  @override
  String get sendReaction => 'Bir tepki gönder';

  @override
  String get sendReactionBody =>
      'Hazır tepkilerden birini seç — mesaj yazma yok, sadece küçük bir selam.';

  @override
  String reactionSent(String emoji) {
    return '$emoji gönderildi.';
  }

  @override
  String get removeFriend => 'Arkadaşlıktan çıkar';

  @override
  String get blockUser => 'Engelle';

  @override
  String get reportUser => 'Şikayet et';

  @override
  String get reactionStreak => 'Seri devam';

  @override
  String get reactionThinkingOfYou => 'Seni düşündüm';

  @override
  String get reactionShine => 'Parlıyorsun';

  @override
  String get reactionKeepGoing => 'Devam et';

  @override
  String get reactionCongrats => 'Tebrikler';

  @override
  String get reactionSameFrequency => 'Aynı frekans';

  @override
  String get reactionGoodNight => 'İyi geceler';

  @override
  String get reactionCheckToday => 'Bugüne bak';

  @override
  String get paywallTitle => 'Rytho+';

  @override
  String get paywallHeadline => 'Yıldızlar herkese aynı,\nsen değilsin.';

  @override
  String get paywallBody =>
      'Ücretsiz katmanda günlük burç yorumun ve gerçek gökyüzü verisi her zaman açık kalır. Rytho+ ise yorumları senin haritanla üretir.';

  @override
  String get paywallContinue => 'Rytho+ ile devam et';

  @override
  String get paywallChoosePlan => 'Paket seç';

  @override
  String get restorePurchases => 'Satın alımları geri yükle';

  @override
  String get noActiveSubscription =>
      'Geri yüklenecek aktif bir abonelik bulunamadı.';

  @override
  String get purchaseFailed => 'Satın alma tamamlanamadı.';

  @override
  String get billingUnavailable => 'Satın alma şu an kullanılamıyor';

  @override
  String get billingNoPackages => 'Mağazada tanımlı paket bulunamadı.';

  @override
  String get planWeekly => 'Haftalık';

  @override
  String get planMonthly => 'Aylık';

  @override
  String get planAnnual => 'Yıllık';

  @override
  String paywallForFeature(String name) {
    return '$name için Rytho+';
  }

  @override
  String priceWithPeriod(String price, String unit) {
    return '$price / $unit';
  }

  @override
  String annualPerMonth(String price) {
    return 'ayda ≈ $price';
  }

  @override
  String annualSavingsBadge(int percent) {
    return '%$percent tasarruf';
  }

  @override
  String trialThenPriceDays(int count, String price) {
    return '$count gün ücretsiz, sonra $price';
  }

  @override
  String trialThenPriceWeeks(int count, String price) {
    return '$count hafta ücretsiz, sonra $price';
  }

  @override
  String trialThenPriceMonths(int count, String price) {
    return '$count ay ücretsiz, sonra $price';
  }

  @override
  String trialThenPriceYears(int count, String price) {
    return '$count yıl ücretsiz, sonra $price';
  }

  @override
  String get unitDay => 'gün';

  @override
  String get unitWeek => 'hafta';

  @override
  String get unitMonth => 'ay';

  @override
  String get unitYear => 'yıl';

  @override
  String get subscriptionTerms =>
      'Abonelik, dönem bitiminden en az 24 saat önce iptal edilmezse otomatik yenilenir. Deneme süresi varsa, süre dolmadan iptal edersen ücret alınmaz. İptali cihazının mağaza hesabı ayarlarından yapabilirsin.';

  @override
  String get benefitDailyTitle => 'Kişiye özel günlük okuma';

  @override
  String get benefitDailyBody =>
      'Natal haritan bugünün gökyüzüyle çarpışır — genel burç yorumu değil.';

  @override
  String get benefitNatalTitle => 'Derin doğum haritası raporu';

  @override
  String get benefitNatalBody =>
      'Gezegenler, evler ve açılar; tek seferlik yüzeysel özet değil.';

  @override
  String get benefitDyadTitle => 'Arkadaşlarınla günlük ikili dinamik';

  @override
  String get benefitDyadBody =>
      'Her gün yenilenen ortak okuma. Kalıcı uyum puanı yok.';

  @override
  String benefitChatTitleCount(int count) {
    return 'Ayda $count AI kredisi';
  }

  @override
  String get benefitChatTitleUnknown => 'Aylık AI kredisi';

  @override
  String get benefitChatBody =>
      'Sohbette, raporlarda ve çekimlerde dilediğin gibi harca; Rytho seni tanıdıkça konuşma derinleşir.';

  @override
  String get benefitBaziTitle => 'BaZi ve sinastri';

  @override
  String get benefitBaziBody =>
      'Dört Sütun analizi ve ikili harita karşılaştırması.';

  @override
  String get benefitFaceTitle => 'Yüz Okuma';

  @override
  String get benefitFaceBody =>
      'Yüz hatlarından firaset geleneğine göre mizaç okuması. Görüntü cihazında işlenir; sunucuya yalnız ölçülen oranlar gider.';

  @override
  String get benefitTimingTitle => 'Yıl Haritası, İç Takvim ve Doğum Kapısı';

  @override
  String get benefitTimingBody =>
      'Güneş\'in doğum boylamına döndüğü ana kurulan yıl haritan, ilerletilmiş iç takvimin ve 64 kapı çarkındaki doğum kapın.';

  @override
  String get benefitIchingTitle => 'I Ching çekimi';

  @override
  String get benefitIchingBody =>
      'Gerçek olasılıklarla atılan çekim ve hareketli çizgilerin Rytho yorumu.';

  @override
  String get benefitPeopleTitle => '10 kişilik çevre';

  @override
  String get benefitPeopleBody =>
      'Ücretsiz katmanda tek kişi eklenir; Rytho+ ile on kişiye kadar ekler, her biriyle sinastri okursun.';

  @override
  String get profileTitle => 'Sicil';

  @override
  String get settings => 'Ayarlar';

  @override
  String get sounds => 'Sesler';

  @override
  String get privacy => 'Gizlilik';

  @override
  String get streakVisibleSetting => 'Serimi arkadaşlarım görsün';

  @override
  String get streakVisibleSettingBody =>
      'Kapalıyken serin ve bugün okuyup okumadığın paylaşılmaz.';

  @override
  String get language => 'Dil';

  @override
  String get languageSystem => 'Sistem dili';

  @override
  String get languageTurkish => 'Türkçe';

  @override
  String get languageEnglish => 'English';

  @override
  String get about => 'Hakkında';

  @override
  String get aboutBody =>
      'Rytho; Batı astrolojisi, BaZi ve I Ching geleneklerini hassas efemeris hesabıyla birleştirir. Yorumlar içgörü amaçlıdır; tıbbi, hukuki veya finansal tavsiye değildir.';

  @override
  String get ephemerisCredit => 'Efemeris: Swiss Ephemeris © Astrodienst AG';

  @override
  String get privacyPolicy => 'Gizlilik Politikası';

  @override
  String get termsOfUse => 'Kullanım Şartları';

  @override
  String get signOut => 'Oturumu kapat';

  @override
  String get signOutConfirmBody =>
      'Bildirimler bu cihazda durur; yeniden girdiğinde kaldığın yerden devam edersin.';

  @override
  String streakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gün',
      one: '1 gün',
    );
    return '$_temp0';
  }

  @override
  String get birthRecord => 'Doğum Kaydı';

  @override
  String get birthDate => 'Tarih';

  @override
  String get birthTime => 'Saat';

  @override
  String get birthTimeUnknown => 'Doğum saatimi bilmiyorum';

  @override
  String get birthCity => 'Şehir';

  @override
  String get retry => 'Tekrar dene';

  @override
  String retryAfterSeconds(int n) {
    return '$n sn sonra tekrar dene';
  }

  @override
  String get delete => 'Sil';

  @override
  String get discard => 'Bırak';

  @override
  String get feedbackDiscardTitle => 'Yazdıklarını bırak';

  @override
  String get feedbackDiscardBody => 'Geri bildirim kaydedilmeyecek.';

  @override
  String get errorGeneric =>
      'Beklenmeyen bir sorun oluştu. Lütfen biraz sonra tekrar dene.';

  @override
  String get errorConnection =>
      'Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.';

  @override
  String get reportUnavailable =>
      'Okumayı şu an üretemedik. Birkaç saniye sonra tekrar dene.';

  @override
  String get reportUnavailableRefunded =>
      'Raporu şu an üretemedik; harcanan kredi iade edildi. Birkaç saniye sonra tekrar dene.';

  @override
  String get chatTitle => 'Rytho AI';

  @override
  String get chatSend => 'Gönder';

  @override
  String get chatHint => 'Geleceğinle ilgili her şeyi sor...';

  @override
  String get chatEmptyBody =>
      'Haritan, yüzün, kaderin... Aklından geçen her soruyu sor.';

  @override
  String get suggestCareer => 'Kariyer 💼';

  @override
  String get suggestLove => 'Aşk hayatı ❤️';

  @override
  String get suggestMonth => 'Bu ay beni ne bekliyor?';

  @override
  String get suggestFinance => 'Finansal şans 💰';

  @override
  String get suggestMarriage => 'Evlilik zamanı 💍';

  @override
  String get onboardingCity => 'Doğum şehri';

  @override
  String get genderFemale => 'Kadın';

  @override
  String get genderMale => 'Erkek';

  @override
  String get genderOther => 'Diğer';

  @override
  String get onboardingStage1 => 'Gökyüzü konumlanıyor';

  @override
  String get onboardingStage2 => 'Evler hesaplanıyor';

  @override
  String get onboardingStage3 => 'Haritan çiziliyor';

  @override
  String get bigThreeTitle => 'Göğün sana üç mührü';

  @override
  String get bigThreeSun => 'GÜNEŞ';

  @override
  String get bigThreeMoon => 'AY';

  @override
  String get bigThreeAscendant => 'YÜKSELEN';

  @override
  String get bigThreeAscendantUnknown => 'saat yok';

  @override
  String get bigThreeStart => 'Yolculuğa başla';

  @override
  String get profileSubscriptionRow => 'Abonelik ve krediler';

  @override
  String get subscriptionScreenTitle => 'Abonelik ve Krediler';

  @override
  String get subPlanLabel => 'PLAN';

  @override
  String get subPlanFree => 'Ücretsiz';

  @override
  String get subPlanFreeBody =>
      'Kişiye özel günlük okuma, natal rapor, BaZi, Yıl Haritası ve İç Takvim Rytho+ ile açılır.';

  @override
  String get subPlanMonthly => 'Aylık Rytho+';

  @override
  String get subPlanYearly => 'Yıllık Rytho+';

  @override
  String get subGoPlus => 'Rytho+\'a geç';

  @override
  String get subStatusLabel => 'Durum';

  @override
  String get subStatusTrial => 'Deneme sürümü';

  @override
  String get subRenewsLabel => 'Yenilenme';

  @override
  String get subEndsLabel => 'Sona erme';

  @override
  String get subManage => 'Aboneliği yönet';

  @override
  String get subManageOpenFailed =>
      'Abonelik sayfası açılamadı — mağaza uygulamasından yönetebilirsin.';

  @override
  String get subRestoreDone => 'Aboneliğin geri yüklendi ✨';

  @override
  String get subMonthlyAllowanceRow => 'Aylık hak';

  @override
  String get subAllowanceResetsRow => 'Hak tazelenir';

  @override
  String get subBuyTokens => 'Kredi paketi al';

  @override
  String get atlasWaitStage1 => 'Gezegenler yerleşiyor';

  @override
  String get atlasWaitStage2 => 'Açılar okunuyor';

  @override
  String get atlasWaitStage3 => 'Raporun yazılıyor';

  @override
  String get baziWaitStage1 => 'Dört sütun kuruluyor';

  @override
  String get baziWaitStage2 => 'Elementler tartılıyor';

  @override
  String get baziWaitStage3 => 'Kader notun yazılıyor';

  @override
  String get atlasTitle => 'Doğum Haritası Analizi';

  @override
  String get appHeadline => 'Kişisel Kozmik Zekân';

  @override
  String get authNameRequired => 'Adını yaz.';

  @override
  String get authInvalidEmail => 'Geçerli bir e-posta yaz.';

  @override
  String get authWrongCredentials => 'E-posta veya şifre hatalı.';

  @override
  String get authEmailInUse => 'Bu e-posta zaten kayıtlı. Giriş yapmayı dene.';

  @override
  String get authTooManyRequests =>
      'Çok fazla deneme yapıldı. Biraz sonra tekrar dene.';

  @override
  String get authDisabled => 'E-posta ile giriş şu an kapalı.';

  @override
  String get authNetwork => 'Bağlantı kurulamadı. İnternetini kontrol et.';

  @override
  String get authFailed => 'Bir şeyler ters gitti. Tekrar dene.';

  @override
  String get authReauthNeeded =>
      'Google hesabının bu cihazda yeniden doğrulanması gerekiyor. Telefonunun Ayarlar → Google bölümüne girip hesabını doğrula (gerekirse hesabı kaldırıp yeniden ekle), sonra tekrar dene.';

  @override
  String get displayName => 'Adın';

  @override
  String get passwordRepeat => 'Şifre (tekrar)';

  @override
  String get passwordsDoNotMatch => 'Şifreler eşleşmiyor.';

  @override
  String get nameLabel => 'Ad';

  @override
  String get signAries => 'Koç';

  @override
  String get signTaurus => 'Boğa';

  @override
  String get signGemini => 'İkizler';

  @override
  String get signCancer => 'Yengeç';

  @override
  String get signLeo => 'Aslan';

  @override
  String get signVirgo => 'Başak';

  @override
  String get signLibra => 'Terazi';

  @override
  String get signScorpio => 'Akrep';

  @override
  String get signSagittarius => 'Yay';

  @override
  String get signCapricorn => 'Oğlak';

  @override
  String get signAquarius => 'Kova';

  @override
  String get signPisces => 'Balık';

  @override
  String get atlasPlanetPositions => 'Gezegen Konumları';

  @override
  String get atlasTraits => 'Kişilik Özellikleri';

  @override
  String get atlasAspects => 'Açılar';

  @override
  String moonIllumination(Object percent) {
    return 'aydınlanma %$percent';
  }

  @override
  String moonIlluminationAsOf(String time) {
    return '$time itibarıyla — oran gün içinde değişir';
  }

  @override
  String get reportPostTitle => 'GÖNDERİYİ ŞİKAYET ET';

  @override
  String get reportUserTitle => 'KULLANICIYI ŞİKAYET ET';

  @override
  String get reportNote => 'Şikayetin ekibimiz tarafından incelenir.';

  @override
  String get reportReasonSpam => 'Spam veya yanıltıcı içerik';

  @override
  String get reportReasonHarassment => 'Hakaret veya taciz';

  @override
  String get reportReasonInappropriate => 'Uygunsuz / rahatsız edici içerik';

  @override
  String get reportReasonOther => 'Diğer';

  @override
  String get reportSubmitted =>
      'Şikayetin alındı; en kısa sürede incelenecek. Teşekkürler.';

  @override
  String get reportFailed => 'Şikayet gönderilemedi.';

  @override
  String get aFriend => 'Bir arkadaşın';

  @override
  String get iChingIntro =>
      '3000 yıllık 64 heksagram matrisi. Sorunu yaz; paralar gerçek olasılık dağılımıyla atılır, hareketli çizgiler geleceğe köprü kurar.';

  @override
  String get iChingQuestionHint => 'Sorun nedir?';

  @override
  String get iChingMethodCoins => 'Üç Para 🪙';

  @override
  String get iChingMethodYarrow => 'Civanperçemi 🌿';

  @override
  String get iChingCastAction => 'Çekimi yap';

  @override
  String get iChingQuestionRequired => 'Önce kalbindeki soruyu yaz.';

  @override
  String get iChingQuestionInvalid =>
      'Kâhin bu metinde yorumlayacağı bir soru bulamadı — niyetini kendi yaşamınla ilgili bir cümleyle yaz.';

  @override
  String get iChingCoinsInAir => 'Paralar havada...';

  @override
  String iChingCoinsLanding(int n) {
    return 'Paralar düşüyor… $n/6';
  }

  @override
  String iChingHexagramLabel(Object number) {
    return 'HEKSAGRAM $number';
  }

  @override
  String iChingTransformedTo(Object name, Object number) {
    return '→ dönüşüm: $name (#$number)';
  }

  @override
  String get iChingOracleNote => 'Rytho\'nun kehanet notu';

  @override
  String get iChingJudgmentTitle => 'Hüküm';

  @override
  String get iChingImageTitle => 'İmge';

  @override
  String get iChingMovingTitle => 'Hareketli Çizgiler';

  @override
  String get iChingLiuYaoTitle => 'Liu Yao';

  @override
  String iChingNuclearLabel(String name, int n) {
    return 'çekirdek: $name (#$n)';
  }

  @override
  String get iChingLegend =>
      '○ eski yang (9) · × eski yin (6) — dönen çizgiler';

  @override
  String get iChingShiTag => 'özne';

  @override
  String get iChingYingTag => 'karşılık';

  @override
  String get iChingTapToSkip => 'İnişi atlamak için dokun';

  @override
  String iChingLineLabel(int n) {
    return '$n. çizgi';
  }

  @override
  String iChingPalaceLabel(String name, int shi, int ying) {
    return 'Saray: $name · özne (shi) $shi. çizgi · karşılık (ying) $ying. çizgi';
  }

  @override
  String get iChingVoidTag => 'boşluk';

  @override
  String get iChingClashTag => 'çarpışma';

  @override
  String iChingDayLabel(String day) {
    return 'Çekim günü: $day';
  }

  @override
  String iChingTrigramsLabel(String lower, String upper) {
    return '$lower altında, $upper üstte';
  }

  @override
  String get baziHeadline => 'Kaderin Dört Sütunu';

  @override
  String baziChineseSign(Object animal, Object dayMaster) {
    return 'Çin burcun: $animal · $dayMaster';
  }

  @override
  String get baziFourPillars => 'Dört Sütun';

  @override
  String get baziPillarHour => 'SAAT';

  @override
  String get baziPillarDay => 'GÜN';

  @override
  String get baziPillarMonth => 'AY';

  @override
  String get baziPillarYear => 'YIL';

  @override
  String get baziElementBalance => 'Element Terazisi';

  @override
  String baziNourish(Object elements) {
    return 'Beslenecek element: $elements';
  }

  @override
  String get baziLuckDirectionUnknown =>
      'Cinsiyet belirtilmediği için şans sütunlarının yönü hesaplanmadı; iki olası dizi aşağıda.';

  @override
  String get baziLuckCandidatesLabel => 'Olası iki dizi';

  @override
  String get baziLuckPillars => 'Şans Sütunları (Da Yun)';

  @override
  String get baziStrengthTitle => 'Güç Hükmü';

  @override
  String get baziRatioLabel => 'destek oranı';

  @override
  String get baziFavorable => 'Yararlı elementler';

  @override
  String get baziUnfavorable => 'Yüke dönüşenler';

  @override
  String baziClimateNote(String element) {
    return 'Mevsim iklimi düzenleyici ister: $element';
  }

  @override
  String get baziBasisTitle => 'Hükmün dayanağı';

  @override
  String get baziSrcMonthCommand => 'Ay komutu';

  @override
  String baziSrcRoot(String pillar, String stem) {
    return '$pillar dalındaki $stem kökü';
  }

  @override
  String baziSrcStem(String pillar, String stem) {
    return '$pillar gövdesi $stem';
  }

  @override
  String get baziStarsTitle => 'Yıldızlar (Shen Sha)';

  @override
  String get baziNoStars =>
      'Bu haritada işaretli yıldız yok — yapının kendisi konuşuyor.';

  @override
  String baziLuckStartLabel(int years, int months, String date) {
    return 'İlk dönem: $years yaş $months ay ($date)';
  }

  @override
  String baziThisYear(String label, String tenGod) {
    return 'Bu yılın sütunu: $label ($tenGod)';
  }

  @override
  String get baziCurrentTag => 'şimdi';

  @override
  String baziAgeRange(Object from, Object to) {
    return '$from–$to YAŞ';
  }

  @override
  String get baziFateNote => 'Rytho\'nun kader notu';

  @override
  String get defaultUserName => 'Gezgin';

  @override
  String retrogradeChip(Object planet) {
    return '$planet retro';
  }

  @override
  String get atlasReadingNote => 'Rytho\'nun okuma notu';

  @override
  String get notifications => 'Bildirimler';

  @override
  String get notifyDaily => 'Günlük okuma';

  @override
  String get notifyDailyBody =>
      'Sabahları bugünün gökyüzü hazır olduğunda haber ver.';

  @override
  String get notifyStreak => 'Seri hatırlatması';

  @override
  String get notifyStreakBody =>
      'Akşam, serin kırılmadan önce kısa bir hatırlatma.';

  @override
  String get notifyFriends => 'Arkadaş bildirimleri';

  @override
  String get notifyFriendsBody =>
      'Davetler, kabuller ve tepkiler için haber ver.';

  @override
  String get quietHours => 'Sessiz saatler';

  @override
  String get quietHoursBody => 'Bu aralıkta bildirim gönderilmez.';

  @override
  String quietHoursRange(Object from, Object to) {
    return '$from:00 – $to:00';
  }

  @override
  String get quietHoursOff => 'Kapalı';

  @override
  String get quietHoursFrom => 'Başlangıç';

  @override
  String get quietHoursTo => 'Bitiş';

  @override
  String quietHoursRoundedNote(String range) {
    return 'Sessiz saatler tam saate yuvarlandı: $range';
  }

  @override
  String get deleteAccount => 'Hesabı sil';

  @override
  String get deleteAccountTitle => 'Hesabını silmek üzeresin';

  @override
  String get deleteAccountBody =>
      'Bu işlem geri alınamaz. Silinecekler: doğum kaydın, sohbetlerin ve onlardan çıkarılan notlar, günlük girişlerin, eklediğin kişiler, arkadaşlıkların, kullanıcı adın, sana özel üretilmiş tüm okumalar, yapay zeka kullanım kaydın, telefon doğrulama denemelerin ve gönderdiğin geri bildirimler.';

  @override
  String get deleteAccountKeeps =>
      'İkisi bilerek kalır: satın alma ve iade kayıtların (mali belge, beş yıl saklanması zorunlu) ve gönderdiğin şikayet kayıtları (başkalarının güvenliğiyle ilgili).';

  @override
  String get deleteAccountSubscription =>
      'Aboneliğin varsa uygulama mağazandan ayrıca iptal etmelisin; hesabı silmek aboneliği durdurmaz.';

  @override
  String get deleteAccountConfirmHint => 'Onaylamak için SİL yaz';

  @override
  String get deleteAccountConfirmWord => 'SİL';

  @override
  String get deleteAccountAction => 'Hesabımı kalıcı olarak sil';

  @override
  String get deleteAccountFailed => 'Hesap silinemedi. Lütfen tekrar dene.';

  @override
  String get deleteAccountReauth =>
      'Güvenlik için tekrar giriş yapman gerekiyor. Çıkış yapıp yeniden giriş yaptıktan sonra bu işlemi tekrarla.';

  @override
  String get cancel => 'Vazgeç';

  @override
  String get insightDisclaimer =>
      'Rytho gerçek gökyüzü hesabına dayanır ama yorum bir öngörü yöntemi değildir. Okumalar içgörü içindir; tıbbi, hukuki veya finansal tavsiye yerine geçmez. 13 yaş ve üzeri içindir.';

  @override
  String get shareReading => 'Paylaş';

  @override
  String get shareText =>
      'Rytho — doğum haritanı bilen, gökyüzünü her gün izleyen AI astrolog.';

  @override
  String get chatShareCardTitle => 'Rytho ile sohbetimden';

  @override
  String get chatSeedFailed => 'Konu yüklenemedi.';

  @override
  String get shareCardTagline => 'gerçek gökyüzü hesabıyla';

  @override
  String get shareFailed => 'Paylaşım kartı oluşturulamadı.';

  @override
  String get signInWithApple => 'Apple ile giriş';

  @override
  String get consentPrefix => 'Devam ederek ';

  @override
  String get consentAnd => ' ve ';

  @override
  String get consentSuffix => ' metinlerini kabul etmiş olursun.';

  @override
  String get insightNote =>
      'Yorumlar içgörü amaçlıdır; tıbbi, hukuki veya finansal tavsiye değildir.';

  @override
  String get ageConfirm => '13 yaşından büyüğüm';

  @override
  String get ageRequired =>
      'Devam etmek için yaş beyanını onaylaman gerekiyor.';

  @override
  String get passwordRuleHint => 'En az 8 karakter, harf ve rakam içermeli.';

  @override
  String get passwordTooShort => 'Şifre en az 8 karakter olmalı.';

  @override
  String get passwordTooSimple => 'Şifre harf ve rakam (veya sembol) içermeli.';

  @override
  String verificationSent(Object email) {
    return 'Doğrulama bağlantısı $email adresine gönderildi. Gelen kutunu kontrol et.';
  }

  @override
  String get useGoogleInstead =>
      'Giriş yapılamadı. Şifren hatalı olabilir ya da bu hesap Google/Apple ile açılmış olabilir — aşağıdaki düğmeleri dene.';

  @override
  String get faceReadingTitle => 'Yüz Okuma';

  @override
  String get faceGuideNoFace => 'Yüzünü çerçeveye al';

  @override
  String get faceGuideTooFar => 'Biraz yaklaş';

  @override
  String get faceGuideTooClose => 'Biraz uzaklaş';

  @override
  String get faceGuideOffCentre => 'Yüzünü ortala';

  @override
  String get faceGuideTilted => 'Başını dik tut';

  @override
  String get faceGuideReady => 'Hazır — sabit dur';

  @override
  String get faceGuideForehead => 'Alnını aç — saçını geriye al';

  @override
  String get faceScanning => 'Yüz hatların okunuyor';

  @override
  String get faceScanNodes => 'Noktalar yerleşiyor';

  @override
  String get faceScanReading => 'Firaset ile eşleştiriliyor';

  @override
  String get faceRetake => 'Yeniden çek';

  @override
  String get faceConsentTitle => 'Yüz okuma için onayın gerekiyor';

  @override
  String get faceConsentBody =>
      'Yüz okuma, kameradan aldığı kareyi ya da galeriden seçtiğin fotoğrafı CİHAZINDA işler. Görüntü sunucuya gönderilmez, hiçbir yerde saklanmaz ve işlem biter bitmez silinir (galeri yolunda uygulamaya verilen kopya silinir; asıl fotoğrafına dokunulmaz). Sunucuya yalnızca yüz hatlarından türetilen oranlar (ör. alın/çene yükseklik oranı) gider; bu sayılar kişiyi tanımaya yaramaz.';

  @override
  String get faceConsentCheckbox =>
      'Yüz görüntümün cihazımda işlenmesine onay veriyorum.';

  @override
  String get faceConsentContinue => 'Onaylıyorum ve devam et';

  @override
  String get faceConsentLearnMore => 'Gizlilik politikasını oku';

  @override
  String get faceCameraDenied =>
      'Kamera izni verilmedi. Yüz okuma için kameraya erişim gerekiyor.';

  @override
  String get faceDetectFailed =>
      'Yüz tespit edilemedi. Işığın yeterli olduğundan ve yüzünün çerçevede olduğundan emin ol.';

  @override
  String get faceReadingHint =>
      'Gelenek der ki: tek bir belirti hüküm vermez. Aşağıdaki okuma bir eğilimdir, kader değildir.';

  @override
  String get faceReadingLockedBody =>
      'Yüz hatlarından mizaç okuması Rytho+ ile açılır. Görüntü cihazında işlenir, hiçbir yere gönderilmez.';

  @override
  String get faceGalleryButton => 'Galeriden seç';

  @override
  String get faceLensButton => 'Kamerayı çevir';

  @override
  String get faceStillAnalyzing => 'Fotoğraf inceleniyor…';

  @override
  String get faceStillNoFace =>
      'Fotoğrafta yüz bulunamadı. Önden, iyi aydınlatılmış bir fotoğraf dene.';

  @override
  String get faceStillNoLandmarks =>
      'Yüz hatları seçilemedi. Yüzün tam göründüğü, önden bir fotoğraf dene.';

  @override
  String get faceStillSingleFrameNote =>
      'Bu okuma tek bir fotoğraf karesinden ölçüldü; canlı çekim daha kararlı sonuç verir.';

  @override
  String get faceWaitStage1 =>
      'Oranlar geleneğin ölçüleriyle karşılaştırılıyor…';

  @override
  String get faceWaitStage2 => 'Firaset kaynakları taranıyor…';

  @override
  String get faceWaitStage3 => 'Okuman yazılıyor…';

  @override
  String get faceConsentSetting => 'Yüz okuma rızası';

  @override
  String get faceConsentSettingOn =>
      'Verildi. Görüntü cihazında işlenir, saklanmaz.';

  @override
  String get faceConsentSettingOff =>
      'Verilmedi. Yüz okumaya girdiğinde sorulur.';

  @override
  String get faceConsentWithdrawTitle => 'Rızayı geri al';

  @override
  String get faceConsentWithdrawBody =>
      'Yüz okuma rızan geri alınacak ve şimdiye kadar üretilmiş firaset okumaların silinecek. Diğer okumaların (natal, BaZi, günlük) etkilenmez.';

  @override
  String get faceConsentWithdrawConfirm => 'Geri al ve sil';

  @override
  String faceConsentWithdrawn(int count) {
    return 'Rıza geri alındı, $count okuma silindi.';
  }

  @override
  String get faceOpenSettings => 'Ayarları aç';

  @override
  String get faceCameraDeniedHint =>
      'İzni reddettiysen, telefon ayarlarından Rytho için kamera iznini açıp buraya dönebilirsin.';

  @override
  String get birthHexagramWaitStage1 => 'Doğum anındaki Güneş konumlanıyor';

  @override
  String get birthHexagramWaitStage2 => 'Kapı ve çizgi okunuyor';

  @override
  String get readingCardReadMore => 'Okumaya devam et';

  @override
  String get save => 'Kaydet';

  @override
  String get edit => 'Düzenle';

  @override
  String get birthRecordRowSubtitle => 'Tüm okumaların temeli';

  @override
  String get languageAndSounds => 'Dil ve sesler';

  @override
  String get addFriendNeedsUsername =>
      'Önce bir kullanıcı adı almalısın — hemen aşağıdaki panelden seçebilirsin.';

  @override
  String get newConversation => 'Yeni konu';

  @override
  String get chatEmptyTitle => 'Rytho ile konuş';

  @override
  String get contactMatchSetting => 'Rehberimden arkadaş öner';

  @override
  String get contactMatchSettingBody =>
      'Numaralar telefonunda özetlenir; rehberin sunucuya gönderilmez. Yalnızca ikiniz de bu ayarı açtıysanız birbirinizi görürsünüz.';

  @override
  String get contactMatchPhoneTitle => 'Önce numaranı doğrula';

  @override
  String get contactMatchPhoneBody =>
      'Eşleşme telefon numarası üzerinden çalışır. Numaranı doğruladığında tanıdıkların seni bulabilir, sen de onları görebilirsin.';

  @override
  String get contactMatchVerifyPhone => 'Numaranı doğrula';

  @override
  String get contactMatchPermTitle => 'Rehber izni gerekiyor';

  @override
  String get contactMatchPermBody =>
      'Tanıdıklarını bulmak için rehber okuma izni gerekli. İzni reddettiysen telefonunun Ayarlar → Uygulamalar → Rytho bölümünden açabilirsin.';

  @override
  String get contactMatchRetry => 'Tekrar dene';

  @override
  String get contactMatchEmptyBody =>
      'Rehberinden kimse henüz görünmüyor. Eşleşme için arkadaşının da Rytho\'da numarasını doğrulamış ve rehber eşleşmesini açmış olması gerekir.';

  @override
  String get contactsTitle => 'Rehberin';

  @override
  String get contactsSearchHint => 'Rehberinde ara';

  @override
  String get contactsActiveSection => 'Uygulamada';

  @override
  String get contactsInviteSection => 'Rytho\'da görünmüyor';

  @override
  String get contactsInviteFootnote =>
      'Numarasını doğrulamamış arkadaşların da burada görünebilir.';

  @override
  String get contactsInvite => 'Davet et';

  @override
  String get contactsAlreadyFriend => 'Arkadaşın';

  @override
  String get contactsNoSearchResult => 'Aramayla eşleşen kişi yok.';

  @override
  String get contactsInviteNeedsUsername =>
      'Davet için önce bir kullanıcı adı al.';

  @override
  String inviteShareMessage(Object link) {
    return 'Seni Rytho\'ya davet ediyorum — kişisel kozmik zekân. Beni buradan ekleyebilirsin: $link';
  }

  @override
  String get contactsFindEntry => 'Rehberinden arkadaş bul';

  @override
  String contactsFindActive(int count) {
    return '$count kişi uygulamada';
  }

  @override
  String get contactsFindEnable => 'Rehber eşleşmesini aç';

  @override
  String get contactsFindVerifyPhone => 'Bulmak için numaranı doğrula';

  @override
  String get phoneSectionLabel => 'TELEFON';

  @override
  String get phoneNotLinked => 'Doğrulanmış numara yok';

  @override
  String get phoneVerifyAction => 'Doğrula';

  @override
  String get phoneChangeAction => 'Değiştir';

  @override
  String get phoneVerifyTitle => 'Telefonunu doğrula';

  @override
  String get phoneVerifyBody =>
      'Numaran SMS ile doğrulanır ve hesabına bağlanır. Rehber eşleşmesini açarsan arkadaşların seni bu numarayla bulabilir; numaran hiçbir zaman açık şekilde saklanmaz ve kimseyle paylaşılmaz.';

  @override
  String get phoneFieldLabel => 'Telefon numarası';

  @override
  String get phoneSendCode => 'Kod gönder';

  @override
  String get phoneCodeLabel => 'SMS kodu';

  @override
  String get phoneConfirmCode => 'Doğrula';

  @override
  String phoneCodeSentTo(String number) {
    return '$number numarasına kod gönderildi.';
  }

  @override
  String phoneWillSendTo(String number) {
    return 'Kod $number numarasına gönderilecek.';
  }

  @override
  String get phoneResend => 'Kodu tekrar gönder';

  @override
  String phoneResendIn(int seconds) {
    return 'Tekrar gönder ($seconds sn)';
  }

  @override
  String get phoneNoCodeHelp =>
      'SMS hâlâ gelmediyse operatör gecikmesi olabilir. Numaranı kontrol et, kodu tekrar gönder ya da bu adımı atlayıp sonra Profil → Giriş yöntemleri\'nden doğrula.';

  @override
  String get phoneRegionUnsupported =>
      'Şu an yalnız +90 ile başlayan numaralara kod gönderebiliyoruz.';

  @override
  String get phoneChangeNumber => 'Numarayı değiştir';

  @override
  String get phoneLinkedDone => 'Telefonun doğrulandı.';

  @override
  String get phoneInvalid => 'Numarayı ülke koduyla yaz (örn. +905xxxxxxxxx).';

  @override
  String get phoneCodeWrong => 'Kod yanlış görünüyor, tekrar dene.';

  @override
  String get phoneTakenError => 'Bu numara başka bir hesaba bağlı.';

  @override
  String get phoneTooManyTries =>
      'Çok fazla deneme yapıldı. Biraz sonra tekrar dene.';

  @override
  String get deviceConflictTitle => 'Hesabın başka bir cihazda açıldı';

  @override
  String deviceConflictBody(String platform, String time) {
    return '$platform cihazında $time itibarıyla giriş yapıldı. Rytho+ aynı anda tek cihazda kullanılabilir — burada devam etmek için \"Bu cihazda kullan\"a dokun.';
  }

  @override
  String get deviceConflictUseHere => 'Bu cihazda kullan';

  @override
  String get deviceConflictClaimFailed =>
      'Cihaz devralınamadı — bağlantını kontrol edip tekrar dene.';

  @override
  String get forceUpdateTitle => 'Yeni sürüm gerekli';

  @override
  String get forceUpdateBody =>
      'Rytho\'nun bu sürümü artık desteklenmiyor. Devam etmek için uygulamayı güncelle — yıldızlar bekliyor.';

  @override
  String get forceUpdateAction => 'Mağazada güncelle';

  @override
  String get forceUpdateStoreFailed =>
      'Mağaza açılamadı — uygulama mağazanda \"Rytho\" diye arat.';

  @override
  String get signInMethodsRow => 'Giriş yöntemleri';

  @override
  String get signInMethodsTitle => 'Giriş yöntemleri';

  @override
  String get signInMethodsBody =>
      'Hesabına birden fazla giriş yolu bağlayabilirsin: hangi yöntemle girersen gir aynı hesaba ulaşırsın.';

  @override
  String get providerPhone => 'Telefon';

  @override
  String get linkAction => 'Bağla';

  @override
  String get linkAlreadyLinked => 'Bu giriş yöntemi zaten hesabına bağlı.';

  @override
  String get linkCredentialInUse =>
      'Bu kimlik başka bir hesaba bağlı. Önce o hesaptan çözülmesi gerekir.';

  @override
  String get linkRequiresRecentLogin =>
      'Güvenlik için yakın zamanlı giriş gerekiyor: çıkış yapıp yeniden girdikten sonra tekrar dene.';

  @override
  String get linkPasswordDone =>
      'Şifre kaydedildi. Artık e-posta ve şifreyle de girebilirsin';

  @override
  String get linkGoogleDone => 'Google hesabın bağlandı ✨';

  @override
  String get setPasswordSection => 'ŞİFRE OLUŞTUR';

  @override
  String get setPasswordBody =>
      'Bir e-posta ve şifre belirlersen Google/Apple olmadan da giriş yapabilirsin.';

  @override
  String get setPasswordAction => 'Şifreyi kaydet';

  @override
  String get changePasswordSection => 'ŞİFREYİ DEĞİŞTİR';

  @override
  String get changePasswordBody =>
      'Yeni şifreni belirle. Değişiklik anında geçerli olur.';

  @override
  String get changePasswordAction => 'Şifreyi değiştir';

  @override
  String get purchaseItemUnavailable =>
      'Bu ürün şu anda mağazada sunulmuyor. Biraz sonra tekrar dene.';

  @override
  String get purchaseStoreProblem =>
      'Mağaza şu an satın almayı tamamlayamadı. Birkaç dakika sonra tekrar dene.';

  @override
  String get tokenStoreTitle => 'Kredi Mağazası';

  @override
  String get tokenBalanceLabel => 'BAKİYEN';

  @override
  String get tokenUnit => 'kredi';

  @override
  String get tokenAllowanceRow => 'Aylık hak (dönem sonunda yenilenir)';

  @override
  String get tokenPurchasedRow => 'Satın alınan (aya devreder)';

  @override
  String get tokenRolloverNote =>
      'Aylık hakkın dönem sonunda yenilenir ve devretmez; satın aldığın krediler hiç yanmaz.';

  @override
  String get tokenPacksHeader => 'Paketler';

  @override
  String tokenPackAmount(int count) {
    return '$count kredi';
  }

  @override
  String storeBuyWithPrice(String price) {
    return 'Satın al — $price';
  }

  @override
  String pricePerCredit(String price) {
    return '$price / kredi';
  }

  @override
  String tokenCost(int count) {
    return '$count kredi';
  }

  @override
  String get purchasePackRefreshing =>
      'Satın alma alındı; bakiyen yenileniyor.';

  @override
  String get purchaseAlreadyOwnedSubscription =>
      'Bu hesapta zaten etkin bir abonelik var — satın alımların geri yükleniyor…';

  @override
  String get tokenPurchaseDone => 'Paket yüklendi. İyi okumalar ✨';

  @override
  String get tokenPacksUnavailable => 'Paketler şu an listelenemiyor';

  @override
  String get tokenPacksUnavailableBody =>
      'Mağaza bağlantısı kurulamadı. Biraz sonra tekrar dene.';

  @override
  String get tokenPacksPlusOnlyTitle => 'Paketler Rytho+ abonelerine özel';

  @override
  String get tokenPacksPlusOnlyBody =>
      'Kredinin açtığı okumaların tamamı Rytho+ ile geliyor. Abonelik olmadan paket almak, sana karşılığını henüz veremeyeceğimiz bir bakiye bırakırdı; bu yüzden paketleri burada göstermiyoruz.';

  @override
  String get tokenPacksSeePlus => 'Rytho+\'a bak';

  @override
  String get tokenFreeTierWarnTitle =>
      'Ücretsiz katmanda kredi yalnızca sohbette harcanır';

  @override
  String get tokenFreeTierWarnBody =>
      '1 kredi = 1 sohbet mesajı. I Ching, ikili dinamik, derin raporlar ve yüz okuma Rytho+ aboneliğine dahildir; kredi onları açmaz. Aldığın krediler yanmaz — sonradan abone olursan hepsini kullanabilirsin.';

  @override
  String tokenCostsNote(int chat, int iching, int dyad, int deep) {
    return 'Sohbet mesajı $chat · I Ching $iching · ikili dinamik $dyad · derin raporlar ve yüz okuma $deep kredi. Kredi yalnız yeni bir rapor üretilirken düşer; hazır duran rapora yeniden bakmak hiç düşürmez.';
  }

  @override
  String chatCostNote(int count) {
    return 'Mesaj başına $count kredi';
  }

  @override
  String costConfirmTitle(int count) {
    return 'Bu okuma $count kredi';
  }

  @override
  String get costConfirmBody =>
      'Hazır duran okumaya yeniden bakmak düşürmez; yeni üretim düşer.';

  @override
  String get costConfirmContinue => 'Devam';

  @override
  String get costConfirmCancel => 'Vazgeç';

  @override
  String tokenBalanceChip(int count) {
    return '$count kredi';
  }

  @override
  String get atlasTraitsSubtitle => 'Element dağılımın';

  @override
  String get atlasPlanetsSubtitle => 'Doğduğun andaki konumlar';

  @override
  String get atlasFullReport => 'Tam rapor';

  @override
  String get atlasFullReportSubtitle => 'Rytho\'nun okuması';

  @override
  String atlasAspectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count açı',
      one: '1 açı',
      zero: 'Açı yok',
    );
    return '$_temp0';
  }

  @override
  String retrogradeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gezegen retro',
      one: '1 gezegen retro',
    );
    return '$_temp0';
  }

  @override
  String get genericError => 'Bir şeyler ters gitti. Tekrar dener misin?';

  @override
  String get birthRecordEditBody =>
      'Bu bilgiler haritanın temeli: günlük okuman, natal raporun ve sohbetin gördüğü her şey buradan hesaplanıyor. Değiştirirsen okumaların yeniden hesaplanır.';

  @override
  String get birthCityEmpty => 'Doğum şehri boş olamaz.';

  @override
  String get birthRecordSaved =>
      'Doğum kaydın güncellendi. Okumaların yeni haritana göre hesaplanacak.';

  @override
  String get birthRecordSavedNoChart =>
      'Doğum kaydın güncellendi ama haritan şu an hesaplanamadı. Burç rozetlerin bağlantı gelince geri dönecek.';

  @override
  String get onboardingSavedNoChart =>
      'Doğum bilgin kaydedildi ama haritan şu an hesaplanamadı. Burç rozetlerin bağlantı gelince gelecek.';

  @override
  String get accountSection => 'Hesap';

  @override
  String get accountSaved => 'Hesap bilgilerin güncellendi.';

  @override
  String get displayNameEmpty => 'Adın boş olamaz.';

  @override
  String displayNameTooLong(int count) {
    return 'Adın en çok $count karakter olabilir.';
  }

  @override
  String get usernameChangeNote =>
      'Değiştirirsen eski kullanıcı adın serbest kalır ve başkası alabilir.';

  @override
  String get emailChangeNote =>
      'E-posta adresin oturumunun anahtarı; değiştirmek için destekle iletişime geç.';

  @override
  String get emailNotVerified => 'E-posta adresin henüz doğrulanmadı.';

  @override
  String get emailVerifyResend => 'Doğrulama e-postasını gönder';

  @override
  String get emailVerifySent =>
      'Doğrulama e-postası gönderildi — spam klasörünü de kontrol et.';

  @override
  String get onboardingSwitchAccount => 'Farklı hesapla gir';

  @override
  String get signalsSection => 'Bugün gökyüzünde senin için';

  @override
  String get signalWhy => 'Neye dayanıyor?';

  @override
  String get signalAsk => 'Rytho\'ya sor';

  @override
  String get atlasAskPrefill =>
      'Atlas sayfamdaki okumalara bakıyorum. Bugün için en çok hangisine eğilmeliyim?';

  @override
  String get faceAskPrefill =>
      'Yüz okumamı gördüm. Bugünkü gökyüzüyle birlikte bana ne söylüyor?';

  @override
  String get planetsAskPrefill =>
      'Gezegenlerimin yerleşimine bakıyorum. En belirleyici olanını bana anlatır mısın?';

  @override
  String get traitsAskPrefill =>
      'Kişilik özelliklerime bakıyorum. Hangisi bugünlerde daha öne çıkıyor?';

  @override
  String get aspectsAskPrefill =>
      'Haritamdaki açılara bakıyorum. En çok hangisini hissederim?';

  @override
  String pointAskPrefill(String name) {
    return '$name yerleşimim hakkında konuşalım. Bu bana nasıl yansıyor?';
  }

  @override
  String aspectAskPrefill(String label) {
    return 'Haritamdaki \"$label\" açısı hakkında konuşalım. Bunu nasıl yaşarım?';
  }

  @override
  String askAboutFriendPrefill(String name) {
    return '$name ile aramızdaki dinamik hakkında konuşalım.';
  }

  @override
  String signalAskPrefill(String card) {
    return 'Bugün ana ekranımda şu sinyal var: \"$card\" Bunu benim için biraz açar mısın?';
  }

  @override
  String signalUpcoming(String date) {
    return 'Önemli gün: $date';
  }

  @override
  String get basisSheetTitle => 'Bu sinyal nereden geliyor?';

  @override
  String get basisSky => 'Gökyüzünde';

  @override
  String get basisNatal => 'Haritanda';

  @override
  String get basisAspect => 'Açı';

  @override
  String get basisOrb => 'Orb (ölçülen)';

  @override
  String get basisMovement => 'Hareket';

  @override
  String get basisExact => 'Kesinleşme';

  @override
  String basisHouse(int house) {
    return '$house. ev';
  }

  @override
  String get basisFootnote =>
      'Konumlar efemeristen gelir, açı ve orb ölçülür; yorum bu ölçümlerin üzerine kurulur.';

  @override
  String get relationshipOpen => 'İlişkiyi incele';

  @override
  String get relationshipOpenSubtitle =>
      'İki haritanız nerede kolaylaşıyor, nerede emek istiyor';

  @override
  String relationshipTitle(String name) {
    return 'Sen & $name';
  }

  @override
  String get relationshipBirthMissing =>
      'Bu okuma için ikinizin de doğum kaydı gerekiyor. Arkadaşın kaydını tamamladığında burası dolacak.';

  @override
  String get relationshipBasisTitle => 'Bu eksenin dayanağı';

  @override
  String get calendarWhyDate => 'Bu tarih neden önemli?';

  @override
  String get diaryTitle => 'Günlüğüm';

  @override
  String get profileDiaryRow => 'Günlüğüm';

  @override
  String get diaryHint => 'Bugün ne oldu? Tek cümle yeter.';

  @override
  String get diarySave => 'Kaydet';

  @override
  String get diaryEmpty =>
      'Henüz giriş yok. Önemli anları tek cümleyle bırak — sohbette \"son ayda ne oldu?\" diye sorduğunda Rytho bu kayıtları o günlerin gökyüzüyle yan yana koyar.';

  @override
  String get diaryDeleted => 'Giriş silindi.';

  @override
  String get diaryFootnote =>
      'Girişlerin yalnız sana görünür ve Rytho\'nun sohbet hafızasına girer. Hesabını silersen hepsi silinir.';

  @override
  String get diaryDeleteTitle => 'Bu girişi silmek istiyor musun?';

  @override
  String get profileSectionAccount => 'Hesap';

  @override
  String get profileSectionPrefs => 'Tercihler';

  @override
  String get feedbackTitle => 'Geri bildirim';

  @override
  String get feedbackLead =>
      'Hata, öneri ya da aklına takılan bir şey — doğrudan bize ulaşır.';

  @override
  String get feedbackTypeBug => 'Hata 🐞';

  @override
  String get feedbackTypeSuggestion => 'Öneri 💡';

  @override
  String get feedbackTypeOther => 'Diğer';

  @override
  String get feedbackScreenLabel => 'Hangi ekran?';

  @override
  String get feedbackScreenChat => 'Sohbet';

  @override
  String get feedbackScreenOracle => 'Kehanet';

  @override
  String get feedbackScreenOther => 'Diğer';

  @override
  String get feedbackHint => 'Ne oldu, ne bekliyordun? Kısa da olur.';

  @override
  String get feedbackPrivacy =>
      'Sürüm, cihaz ve dil bilgisi otomatik eklenir. Mesajın, yanıtını sana iletebilmemiz için hesabınla birlikte kaydedilir.';

  @override
  String get feedbackSend => 'Gönder';

  @override
  String get feedbackThanksTitle => 'Teşekkürler — okuyoruz.';

  @override
  String get feedbackThanksBody => 'Yanıtımızı bildirim olarak alırsın.';

  @override
  String get feedbackClose => 'Kapat';

  @override
  String get feedbackTooShort => 'En az 10 karakter yaz.';

  @override
  String get profileFeedback => 'Geri bildirim gönder';

  @override
  String get feedbackReportThisScreen => 'Bu ekranı bildir';

  @override
  String get removeFriendConfirmTitle => 'Arkadaşlıktan çıkar';

  @override
  String removeFriendConfirmBody(String name) {
    return '$name listenden çıkar; ortak okumalar kapanır. İstersen yeniden ekleyebilirsin.';
  }

  @override
  String get blockUserConfirmTitle => 'Engelle';

  @override
  String blockUserConfirmBody(String name) {
    return '$name seni bulamaz ve davet gönderemez. Bunu Çevrem ayarlarından geri alabilirsin.';
  }

  @override
  String peopleSlotsOver(int limit, int used) {
    return 'Kontenjanın $limit; $used kişi kayıtlı — yeni kişi eklemek için birini çıkar.';
  }

  @override
  String get inviteNeedsUsername =>
      'Bir davet bekliyor — önce kullanıcı adı seç.';

  @override
  String get inviteNeedsUsernameAction => 'Kullanıcı adı seç';

  @override
  String friendAcceptedSnack(String name) {
    return '$name artık arkadaşın.';
  }

  @override
  String get diaryThemeCareer => 'Kariyer';

  @override
  String get diaryThemeRelationships => 'İlişkiler';

  @override
  String get diaryThemeInner => 'İç dünya';

  @override
  String get diaryThemeFinance => 'Para';

  @override
  String get reactionHug => 'Sarıldım';

  @override
  String get reactionLuck => 'Bol şans';

  @override
  String get reactionCoffee => 'Kahve içelim';

  @override
  String get reactionMiss => 'Özledim';

  @override
  String reactionSheetTitle(String name) {
    return '$name için bir tepki seç';
  }

  @override
  String get atlasWheelNatal => 'Haritam';

  @override
  String get atlasWheelSky => 'Şu an gökyüzü';

  @override
  String get atlasWheelBiwheel => 'İkili çark';

  @override
  String get atlasSkyWheelNote =>
      'Gökyüzü şu an herkes için aynı; ev ve Yükselen konuma bağlı olduğu için bu görünümde çizilmez.';

  @override
  String get atlasHourUnknownWheelNote =>
      'Doğum saati bilinmediği için evler ve Yükselen çizilmedi; çark gezegen düzeyinde. Öğle haritası uydurulmadı.';

  @override
  String get atlasBiwheelNote =>
      'İçte doğum haritan, dış halkada şu anki gökyüzü — astrologların transit analizinde kullandığı ikili çark (bi-wheel).';

  @override
  String get atlasSectionAbout => 'Bana dair';

  @override
  String get atlasSectionTime => 'Zaman';

  @override
  String get atlasSectionOther => 'Diğer sistemler';

  @override
  String get atlasFreeChartNote =>
      'Çarkın, yerleşimlerin ve açıların ücretsiz. Rytho\'nun derin okuması Rytho+ ile açılır.';

  @override
  String relationshipAskPrefill(String name, String axis) {
    return '$name ile ilişkimizde \"$axis\" ekseni hakkında konuşalım.';
  }

  @override
  String houseN(int n) {
    return '$n. ev';
  }

  @override
  String get perDay => 'gün';

  @override
  String get planetsSectionExtra => 'Ek noktalar';

  @override
  String get planetsFootnote =>
      'Burç, derece ve ev doğum anının gerçek gökyüzünden hesaplanır (Swiss Ephemeris). Bir satıra dokun — o noktanın ne anlattığını gör.';

  @override
  String get planetDegree => 'Burçtaki derece';

  @override
  String get planetHouse => 'Ev';

  @override
  String get planetMotion => 'Hareket';

  @override
  String get planetSpeed => 'Günlük hız';

  @override
  String get planetRetrograde => 'retro';

  @override
  String get pointSheetFootnote =>
      'Derece, ev ve hız doğum anının gerçek gökyüzünden hesaplanır (Swiss Ephemeris); anlam cümlesi klasik yorum geleneğidir, sana özel değildir.';

  @override
  String pointPlacementSentence(String rol, String alan) {
    return '$rol — bunlar $alan alanında işler.';
  }

  @override
  String get pointAscendant => 'Yükselen';

  @override
  String get traitsElements => 'Element dengesi';

  @override
  String get traitsModalities => 'Nitelik dengesi';

  @override
  String get traitsSetNote =>
      'Sayıma geleneksel yedili (Güneş, Ay, Merkür, Venüs, Mars, Jüpiter, Satürn) ve Yükselen girer — sekiz nokta.';

  @override
  String get traitsTapHint =>
      'Bir satıra dokun: sayının hangi noktalardan çıktığını gör.';

  @override
  String traitsMissingElement(String elements) {
    return '$elements bu haritada hiç yok — eksik element anlamlı bir ifadedir; eksiklik zayıflık değil, bir yön işaretidir.';
  }

  @override
  String traitsSheetTitle(String name) {
    return '$name — bu sayı nereden geliyor?';
  }

  @override
  String get traitsMembersLabel => 'Bu gruba düşen noktalar';

  @override
  String get traitsNoMember => 'Bu gruba düşen nokta yok.';

  @override
  String get traitsSheetFootnote =>
      'Sayım geleneksel yedili + Yükselen üzerinden yapılır. Tek bir burçtan mizaç okunmaz; esas olan dağılımın bütünüdür.';

  @override
  String get traitsUnavailable =>
      'Dağılım verisi bu sürümde gelmedi. Uygulamayı güncelleyip tekrar dene.';

  @override
  String get elementFire => 'Ateş';

  @override
  String get elementEarth => 'Toprak';

  @override
  String get elementAir => 'Hava';

  @override
  String get elementWater => 'Su';

  @override
  String get elementFireLine =>
      'Ateş: harekete geçme, cesaret, başlatma. Baskınsa hız vardır, sabır azdır.';

  @override
  String get elementEarthLine =>
      'Toprak: somutlaştırma, süreklilik, güven. Baskınsa istikrar vardır, esneklik azdır.';

  @override
  String get elementAirLine =>
      'Hava: düşünme, konuşma, bağ kurma. Baskınsa fikir boldur, derinleşmek zordur.';

  @override
  String get elementWaterLine =>
      'Su: hissetme, sezgi, bağlanma. Baskınsa duygu derindir, sınır incedir.';

  @override
  String get temperamentFire =>
      'Klasik gelenekte ateş baskınlığına safravî mizaç denir (sıcak/kuru). Bu ad tek burçtan değil, yukarıdaki dağılımdan çıkar.';

  @override
  String get temperamentEarth =>
      'Klasik gelenekte toprak baskınlığına sevdavî mizaç denir (soğuk/kuru). Bu ad tek burçtan değil, yukarıdaki dağılımdan çıkar.';

  @override
  String get temperamentAir =>
      'Klasik gelenekte hava baskınlığına demevî mizaç denir (sıcak/nemli). Bu ad tek burçtan değil, yukarıdaki dağılımdan çıkar.';

  @override
  String get temperamentWater =>
      'Klasik gelenekte su baskınlığına balgamî mizaç denir (soğuk/nemli). Bu ad tek burçtan değil, yukarıdaki dağılımdan çıkar.';

  @override
  String get modalityCardinal => 'Öncü';

  @override
  String get modalityFixed => 'Sabit';

  @override
  String get modalityMutable => 'Değişken';

  @override
  String get modalityCardinalLine =>
      'Öncü: başlatır, yön verir, ilk adımı atar.';

  @override
  String get modalityFixedLine => 'Sabit: sürdürür, direnir, kolay vazgeçmez.';

  @override
  String get modalityMutableLine =>
      'Değişken: uyum sağlar, biçim değiştirir, dağılabilir.';

  @override
  String get aspectsGroupTension => 'Sert açılar — gerilim';

  @override
  String get aspectsGroupFlow => 'Uyumlu açılar — akış';

  @override
  String get aspectsGroupFocus => 'Kavuşumlar — yoğunlaşma';

  @override
  String get aspectsGroupOther => 'Diğer açılar';

  @override
  String get aspectsSortNote =>
      'Her grupta en dar orb önce: orb ne kadar darsa açı o kadar güçlüdür.';

  @override
  String get aspectMeaningConjunction =>
      'Kavuşum: iki gezegen aynı noktada birleşir; güçleri ayrışmaz, birlikte davranır.';

  @override
  String get aspectMeaningOpposition =>
      'Karşıt: iki gezegen karşı karşıyadır; denge ancak ikisine de yer açınca kurulur.';

  @override
  String get aspectMeaningSquare =>
      'Kare: sürtünme açısıdır; zorlar ama hareket ettirir — gelişmenin çoğu buradan çıkar.';

  @override
  String get aspectMeaningTrine =>
      'Üçgen: akış açısıdır; kolay geldiği için çoğu zaman fark edilmeden kullanılır.';

  @override
  String get aspectMeaningSextile =>
      'Altmışlık: fırsat açısıdır; kendiliğinden olmaz, elini uzatınca çalışır.';

  @override
  String get movementMeaningApplying =>
      'Yaklaşıyor: açı tam olmaya gidiyor, etkisi güçleniyor.';

  @override
  String get movementMeaningSeparating =>
      'Ayrılıyor: açı tamamlandı, etkisi sönüyor.';

  @override
  String get aspectSheetFootnote =>
      'Açı ve orb doğum anının gerçek gökyüzünden ölçülür; açıklama klasik yorum geleneğidir.';

  @override
  String get house1 =>
      '1. ev: kendini gösterme biçimin, bedenin, bıraktığın ilk izlenim.';

  @override
  String get house2 =>
      '2. ev: sahip olduklarımız, kaynakların ve değer duygun.';

  @override
  String get house3 => '3. ev: konuşma, öğrenme, kardeşler, yakın çevre.';

  @override
  String get house4 => '4. ev: kök, ev, aile, içerideki güvenli yer.';

  @override
  String get house5 => '5. ev: yaratma, oyun, aşk, kendini ifade etme.';

  @override
  String get house6 => '6. ev: gündelik düzen, iş rutini, bedenin bakımı.';

  @override
  String get house7 => '7. ev: birebir ilişkiler, ortaklık, karşındaki.';

  @override
  String get house8 => '8. ev: paylaşılan kaynaklar, dönüşüm, derin bağ.';

  @override
  String get house9 => '9. ev: anlam arayışı, inanç, uzak yerler, öğretmek.';

  @override
  String get house10 => '10. ev: kariyer, toplum önündeki duruş, hedef.';

  @override
  String get house11 => '11. ev: arkadaşlıklar, topluluk, gelecek tasarısı.';

  @override
  String get house12 => '12. ev: geri çekilme, bilinçdışı, arkada kalan.';

  @override
  String get roleSun => 'Güneş: öz kimliğin, hayat enerjin, neye yöneldiğin.';

  @override
  String get roleMoon =>
      'Ay: duygusal ihtiyacın, alışkanlıkların, kendini güvende hissetme biçimin.';

  @override
  String get roleMercury => 'Merkür: düşünme ve anlatma biçimin.';

  @override
  String get roleVenus =>
      'Venüs: neyi sevdiğin, nasıl bağ kurduğun, neye değer verdiğin.';

  @override
  String get roleMars => 'Mars: nasıl harekete geçtiğin, öfken ve isteğin.';

  @override
  String get roleJupiter =>
      'Jüpiter: büyüme alanın, iyimserliğin, anlam arayışın.';

  @override
  String get roleSaturn =>
      'Satürn: sorumluluğun, sınırın, zamanla ustalaştığın yer.';

  @override
  String get roleUranus =>
      'Uranüs: kuralı kırdığın, ani değişim getiren yönün.';

  @override
  String get roleNeptune =>
      'Neptün: hayalin, sezgin, sınırların inceldiği yer.';

  @override
  String get rolePluto => 'Plüton: dönüşüm, güç ve yeniden doğuş alanın.';

  @override
  String get roleChiron =>
      'Kiron: yaralandığın ve zamanla iyileştirmeyi öğrendiğin yer.';

  @override
  String get roleLilith => 'Lilith: uzlaşmadığın, evcilleşmeyen yanın.';

  @override
  String get roleNorthNode => 'Kuzey Ay Düğümü: geliştirmeye çağrıldığın yön.';

  @override
  String get roleSouthNode =>
      'Güney Ay Düğümü: elinde hazır olan, geride bırakman gereken.';

  @override
  String get atlasReportPreparing => 'Rytho okumanı yazıyor…';

  @override
  String get retrogradeMeaning =>
      'R retro: gezegen gökyüzünde geri gidiyor görünür. Klasik yorumda o alanda ilerleme dışa değil içe doğrudur — gözden geçirme, toparlama zamanı.';

  @override
  String get calendarLockedReading => 'Bu günün okuması Rytho+ ile açılır.';

  @override
  String get calendarOtherEvents => 'Diğer hareketler';

  @override
  String get calendarStripTitle => 'Önündeki 30 gün';

  @override
  String get storyPause => 'Duraklat';

  @override
  String get storyPlay => 'Oynat';

  @override
  String get relationshipReadingTitle => 'Rytho\'nun ilişki okuması';

  @override
  String get relationshipReadingLocked =>
      'Ölçülen eksenler ve dayanak açılar herkese açık. Bu ölçümün sizin ikinize özel yorumu Rytho+ ile açılır.';

  @override
  String get moonUncertainNote =>
      'Doğum saatin kayıtlı olmadığı için Ay\'ın burcu bir burç şaşabilir — Ay günde yaklaşık 13° yol alır.';

  @override
  String moonUncertainAlt(String alt) {
    return 'Doğum saatine göre $alt da olabilir.';
  }

  @override
  String get birthMissingTitle => 'Doğum kaydın eksik';

  @override
  String get birthMissingBody =>
      'Haritanı hesaplayabilmek için doğum tarihin ve şehrin gerekli. Bu bir Rytho+ kilidi değil — kaydı tamamladığında çark, yerleşimler ve açılar ücretsiz açılır.';

  @override
  String get birthMissingAction => 'Doğum kaydını tamamla';

  @override
  String get circleTitle => 'Çevrem';

  @override
  String get circleFriendsSection => 'Rytho\'daki arkadaşların';

  @override
  String get circlePeopleSection => 'Eklediklerin';

  @override
  String get circleEmptyTitle => 'Eşini, çocuğunu ekle';

  @override
  String get circleEmptyBody =>
      'Yakınlarının haritalarını ve aranızdaki bağı gör. Onların uygulamayı kullanmasına gerek yok.';

  @override
  String get addChooserTitle => 'Kimi ekliyorsun?';

  @override
  String get addChooserFriend => 'Rytho\'da olan biri';

  @override
  String get addChooserFriendBody =>
      'Kullanıcı adı, rehber ya da davet bağlantısıyla. Karşılıklı onay gerekir; tepki gönderebilir, serilerini görürsünüz.';

  @override
  String get addChooserPerson => 'Kendim ekleyeceğim';

  @override
  String get addChooserPersonBody =>
      'Eşin, çocuğun, bir yakının. Doğum bilgilerini sen girersin.';

  @override
  String get peopleAddTitle => 'Kişi ekle';

  @override
  String get peopleEditTitle => 'Kişiyi düzenle';

  @override
  String get peopleLabelField => 'Adı';

  @override
  String get peopleLabelHint => 'Bu kişiyi nasıl anıyorsun?';

  @override
  String get peopleLabelNote =>
      'Bu ad telefonundan çıkmaz. Sunucuda yalnız doğum bilgisi durur; Rytho bu kişiden \"eşin\", \"çocuğun\" diye söz eder.';

  @override
  String get peopleRelation => 'Yakınlık';

  @override
  String get peopleConsent =>
      'Bu kişinin doğum bilgilerini onun adına giriyorsun. Kayıt yalnız sana görünür, başka hiçbir kullanıcı erişemez ve hesabını silersen birlikte silinir.';

  @override
  String get peopleSaved => 'Kaydedildi';

  @override
  String get peopleRemove => 'Kişiyi çıkar';

  @override
  String get peopleRemoveConfirm =>
      'Bu kişi ve haritası silinsin mi? Geri alınamaz.';

  @override
  String get peopleRemoved => 'Çıkarıldı';

  @override
  String peopleSlots(int used, int limit) {
    return '$used/$limit kişi';
  }

  @override
  String get peopleHourUnknownBadge =>
      'Doğum saati bilinmiyor — Yükselen ve evler hesaplanmadı.';

  @override
  String get relationPartner => 'Eşim';

  @override
  String get relationChild => 'Çocuğum';

  @override
  String get relationParent => 'Annem/Babam';

  @override
  String get relationSibling => 'Kardeşim';

  @override
  String get relationFriend => 'Arkadaşım';

  @override
  String get relationWork => 'İş arkadaşım';

  @override
  String get relationOther => 'Yakınım';

  @override
  String get relationshipTodayLabel => 'Bugün aranıza dokunan gökyüzü';

  @override
  String get relationshipTodayQuiet =>
      'Bugün aranıza dokunan belirgin bir transit yok — sakin bir gün.';

  @override
  String relationshipTodayAskPrefill(String name) {
    return 'Bugün $name ile aramıza dokunan gökyüzünü konuşalım.';
  }

  @override
  String chatMentionAttached(String name) {
    return '$name bağlamı ekli';
  }

  @override
  String get chatMentionClearTooltip => 'Bağlamı kaldır';

  @override
  String get chatMentionEmpty =>
      'Eşleşen kişi yok — Çevrem\'den ekleyebilirsin';

  @override
  String get discoveryComplete =>
      'Günün üç keşfi tamam ✨ Yarın gökyüzü yeniden kurulur.';

  @override
  String get discoveryRingTooltip =>
      'Günün keşif halkası: gökyüzünü aç · Rytho ile konuş · çevrenden birine bak';

  @override
  String get forgotPasswordTitle => 'Şifreni sıfırla';

  @override
  String get forgotPasswordBody =>
      'Hesabının e-posta adresini yaz; sana bir sıfırlama bağlantısı gönderelim.';

  @override
  String get forgotPasswordSend => 'Bağlantıyı gönder';

  @override
  String get forgotPasswordSentTitle => 'Bağlantı yolda';

  @override
  String forgotPasswordSentBody(String email) {
    return 'Bu adres kayıtlıysa $email adresine bir sıfırlama bağlantısı gönderdik. Bağlantı kısa süreliğine geçerli.';
  }

  @override
  String get forgotPasswordSpamHint =>
      'E-posta birkaç dakika içinde gelmezse spam/gereksiz klasörüne bak.';

  @override
  String get forgotPasswordResend => 'Tekrar gönder';

  @override
  String forgotPasswordResendWait(int seconds) {
    return 'Tekrar gönder ($seconds sn)';
  }

  @override
  String get notifPermissionOffTitle => 'Bildirimler sistemde kapalı';

  @override
  String get notifPermissionOffBody =>
      'Telefonun ayarlarında Rytho bildirimlerine izin vermeden buradaki tercihler etkisiz kalır: Ayarlar → Uygulamalar → Rytho → Bildirimler.';

  @override
  String get chatOpenLabel => 'Rytho ile sohbet et';

  @override
  String get trialBannerTitle => 'Deneme süren aktif';

  @override
  String trialBannerDays(int days) {
    return 'Tüm Rytho+ özellikleri açık — $days gün kaldı.';
  }

  @override
  String get trialBannerLastDay =>
      'Tüm Rytho+ özellikleri açık — bugün son gün.';

  @override
  String chartWheelSemantics(int rings, int aspects) {
    return 'Astroloji çarkı: $rings halka, $aspects açı. Ayrıntılar aşağıdaki konum tablosunda.';
  }

  @override
  String chartLegendInner(String label) {
    return 'İç: $label';
  }

  @override
  String chartLegendOuter(String label) {
    return 'Dış: $label';
  }

  @override
  String get chartLegendYou => 'sen';

  @override
  String get chartLegendSkyNow => 'şu anki gökyüzü';

  @override
  String get chartFilterAll => 'Tümü';

  @override
  String get chartFilterMajor => 'Majör';

  @override
  String get chartFilterApplying => 'Yaklaşan';

  @override
  String get chartFilterHard => 'Sert';

  @override
  String get chartFilterSoft => 'Yumuşak';

  @override
  String get chartFilterMinors => 'Minörler';

  @override
  String chartOrbLabel(int orb) {
    return 'Orb ≤ $orb°';
  }

  @override
  String get chartHouseSystem => 'Placidus evleri · Tropikal zodyak';

  @override
  String get chartHourUnknownNote =>
      'Doğum saati bilinmediği için evler, Yükselen ve eksenler çizilmedi.';

  @override
  String get chartAspectarianTitle => 'AÇI TABLOSU';

  @override
  String get chartPositionsTitle => 'KONUMLAR';

  @override
  String get chartApplyingLetter => 'Y';

  @override
  String get chartSeparatingLetter => 'A';

  @override
  String get chartHousesYou => 'Evler: sen';

  @override
  String chartHousesOther(String name) {
    return 'Evler: $name';
  }

  @override
  String chartModeSynastry(String name) {
    return 'Sen & $name';
  }

  @override
  String chartAskPrefillNatal(String name) {
    return 'Şu an $name haritasının çarkını inceliyorum. En çok dikkat etmem gereken ne?';
  }

  @override
  String get chartAskPrefillOwn =>
      'Şu an kendi haritamın çarkını inceliyorum. En çok dikkat etmem gereken ne?';

  @override
  String get chartAskPrefillSky =>
      'Şu anki gökyüzü çarkını inceliyorum. Bugün beni en çok ne etkiliyor?';

  @override
  String get chartAskPrefillBiwheel =>
      'Haritamla bugünkü gökyüzünü üst üste inceliyorum. En çok hangi dokunuş öne çıkıyor?';

  @override
  String chartAskPrefillSynastry(String name) {
    return '$name ile ikili çarkımızı inceliyorum. Aramızda en belirleyici bağ hangisi?';
  }

  @override
  String get chartMovementLegend => 'Y yaklaşan · A ayrılan';

  @override
  String get chartLoading => 'Çark hazırlanıyor…';

  @override
  String get chartSelectionClear => 'Seçimi kaldır';

  @override
  String chartAsOf(String time) {
    return '$time itibarıyla';
  }

  @override
  String chartAskPrefill(String title) {
    return 'Şu an $title çarkını inceliyorum. Bu haritada öne çıkan neler?';
  }

  @override
  String get innerCalendarAskPrefill =>
      'İç mevsim sayfamı açtım. Progres Ay\'ımın şu dönemde ne anlattığını biraz açar mısın?';

  @override
  String get birthHexagramAskPrefill =>
      'Doğum kapımı açtım. Bu kapının karakterimde nasıl çalıştığını biraz açar mısın?';

  @override
  String get solarReturnAskPrefill =>
      'Yıl haritamı açtım. Bu yılın bana ne getirdiğini biraz açar mısın?';

  @override
  String get baziAskPrefill =>
      'BaZi haritamı açtım. Dört sütunumun ne anlattığını biraz açar mısın?';

  @override
  String iChingAskPrefill(String question) {
    return 'Kehanete şunu sordum: \"$question\" Gelen cevabı biraz açar mısın?';
  }

  @override
  String get chartShareTooltip => 'Çarkı paylaş';

  @override
  String get chartExpandTooltip => 'Harita İnceleme\'de aç';

  @override
  String get chartSelectedDetail => 'Detay →';

  @override
  String get chartOuterLoading => 'Dış halka yükleniyor…';

  @override
  String get aspectSubjectSun => 'kimliğin';

  @override
  String get aspectSubjectMoon => 'duyguların';

  @override
  String get aspectSubjectMercury => 'zihnin';

  @override
  String get aspectSubjectVenus => 'sevme biçimin';

  @override
  String get aspectSubjectMars => 'enerjin';

  @override
  String get aspectSubjectJupiter => 'büyüme isteğin';

  @override
  String get aspectSubjectSaturn => 'sorumluluk duygun';

  @override
  String get aspectSubjectUranus => 'özgürlük ihtiyacın';

  @override
  String get aspectSubjectNeptune => 'hayal gücün';

  @override
  String get aspectSubjectPluto => 'dönüşüm gücün';

  @override
  String get aspectSubjectChiron => 'eski yaran';

  @override
  String get aspectSubjectLilith => 'evcilleşmeyen yanın';

  @override
  String get aspectSubjectNorthNode => 'büyüme yönün';

  @override
  String get aspectSubjectSouthNode => 'alıştığın yanın';

  @override
  String get aspectSubjectAscendant => 'dışa görünen yüzün';

  @override
  String get aspectSubjectMidheaven => 'hedeflerin';

  @override
  String get aspectSubjectDescendant => 'ilişki arayışın';

  @override
  String get aspectSubjectImumCoeli => 'köklerin';

  @override
  String aspectSentenceConjunction(String a, String b) {
    return '$a ile $b iç içe; birlikte çalışıyorlar.';
  }

  @override
  String aspectSentenceOpposition(String a, String b) {
    return '$a ile $b karşı karşıya; ikisine de yer açınca denge kuruluyor.';
  }

  @override
  String aspectSentenceSquare(String a, String b) {
    return '$a ile $b sürtüşüyor; zorluyor ama ilerletiyor.';
  }

  @override
  String aspectSentenceTrine(String a, String b) {
    return '$a ile $b kolayca akıyor; doğal bir yetenek.';
  }

  @override
  String aspectSentenceSextile(String a, String b) {
    return '$a ile $b birbirine kapı açıyor; adım atınca çalışıyor.';
  }

  @override
  String get aspectStrengthVeryStrong => 'Çok güçlü';

  @override
  String get aspectStrengthStrong => 'Güçlü';

  @override
  String get aspectStrengthMild => 'Hafif';

  @override
  String get traitsLevelNone => 'Yok';

  @override
  String get traitsLevelLow => 'Az';

  @override
  String get traitsLevelBalanced => 'Dengeli';

  @override
  String get traitsLevelStrong => 'Güçlü';

  @override
  String traitsCountCaption(String sayi, String toplam) {
    return '$toplam ana noktadan $sayi tanesi';
  }

  @override
  String get traitsLevelNote =>
      'İyi ya da kötü yok: güçlü olan sana kolay gelen, az olan bilinçli çaba isteyen yanındır.';

  @override
  String get elementFireWord => 'tutku';

  @override
  String get elementEarthWord => 'somutluk';

  @override
  String get elementAirWord => 'fikir';

  @override
  String get elementWaterWord => 'duygu';

  @override
  String get modalityCardinalWord => 'başlatma';

  @override
  String get modalityFixedWord => 'sebat';

  @override
  String get modalityMutableWord => 'uyum';

  @override
  String get signClimateAri =>
      'başlangıç iklimi: cesaret, ilk adım, kendin için harekete geçmek.';

  @override
  String get signClimateTau =>
      'yerleşme iklimi: sakinlik, beden, kalıcı olanı kurmak.';

  @override
  String get signClimateGem =>
      'merak iklimi: öğrenmek, konuşmak, yeni bağlantılar.';

  @override
  String get signClimateCan => 'yuva iklimi: aile, korunmak, köklerine dönmek.';

  @override
  String get signClimateLeo =>
      'ışık iklimi: yaratmak, görünmek, kalpten yaşamak.';

  @override
  String get signClimateVir =>
      'düzen iklimi: toparlanmak, ince ayar, gündelik ritim.';

  @override
  String get signClimateLib => 'ilişki iklimi: denge, ortaklık, güzellik.';

  @override
  String get signClimateSco =>
      'derinlik iklimi: dönüşüm, yakınlık, gizli olanla yüzleşmek.';

  @override
  String get signClimateSag =>
      'ufuk iklimi: yolculuk, anlam arayışı, genişlemek.';

  @override
  String get signClimateCap =>
      'inşa iklimi: sorumluluk, hedef, emeğin karşılığı.';

  @override
  String get signClimateAqu =>
      'özgürlük iklimi: yenilik, topluluk, kendi yolun.';

  @override
  String get signClimatePis => 'çözülme iklimi: sezgi, hayal, bırakmak.';

  @override
  String get progPhaseMeaningNewMoon =>
      'Yeni Ay evresi: bir döngü başlıyor; tohum ekme zamanı.';

  @override
  String get progPhaseMeaningWaxingCrescent =>
      'Hilal evresi: başladığını büyütme, ilk dirençleri aşma.';

  @override
  String get progPhaseMeaningFirstQuarter =>
      'İlk dördün: karar ve eylem; yol ayrımları.';

  @override
  String get progPhaseMeaningWaxingGibbous =>
      'Şişkin Ay evresi: ince ayar, emeği olgunlaştırma.';

  @override
  String get progPhaseMeaningFullMoon =>
      'Dolunay evresi: görünür olma, meyve ve fark ediş.';

  @override
  String get progPhaseMeaningWaningGibbous =>
      'Yayan Ay evresi: öğrendiğini paylaşma.';

  @override
  String get progPhaseMeaningLastQuarter =>
      'Son dördün: elden geçirme, gereksizi bırakma.';

  @override
  String get progPhaseMeaningWaningCrescent =>
      'Kapanış evresi: dinlenme, sindirme, yeni döngüye hazırlık.';

  @override
  String get innerJourneyTitle => 'İç yolculuğun';

  @override
  String get innerJourneyNow => 'Şu an';

  @override
  String innerJourneyNowTitle(String burc) {
    return 'İç iklimin: $burc';
  }

  @override
  String innerJourneyNextWhen(String tarih) {
    return '$tarih itibarıyla';
  }

  @override
  String innerJourneyNextTitle(String burc) {
    return 'Sonraki iç iklim: $burc';
  }

  @override
  String innerJourneyMilestone(String tarih) {
    return 'Dönüm noktası · $tarih';
  }

  @override
  String get solarReturnJourneyTitle => 'Bu yılki yolculuğun';

  @override
  String solarReturnJourneyMonth(String ay) {
    return 'Yolculuğun $ay. ayındasın';
  }

  @override
  String get solarReturnRealmsTitle => 'Bu yıl en çok gezeceğin evrenler';

  @override
  String solarReturnRealmPlanets(String gezegenler) {
    return 'Burada: $gezegenler';
  }

  @override
  String get solarReturnRealmsNoTime =>
      'Doğum saatin olmadan yılın evrenleri hesaplanamıyor; yılın duygusal iklimi yine de aşağıda.';

  @override
  String get solarReturnMoonClimate => 'Yılın duygusal iklimi';

  @override
  String get readingFullToggle => 'Okumanın tamamı';
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @atlasYearChart.
  ///
  /// In tr, this message translates to:
  /// **'Doğum gününden doğum gününe'**
  String get atlasYearChart;

  /// No description provided for @atlasYearChartSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Yıl haritan (güneş dönüşü)'**
  String get atlasYearChartSubtitle;

  /// No description provided for @atlasInnerCalendar.
  ///
  /// In tr, this message translates to:
  /// **'İç mevsim'**
  String get atlasInnerCalendar;

  /// No description provided for @atlasInnerCalendarSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Progres Ay + yaşam yayı'**
  String get atlasInnerCalendarSubtitle;

  /// No description provided for @wizardWelcomeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yolculuk başlıyor'**
  String get wizardWelcomeTitle;

  /// No description provided for @wizardWelcomeBody.
  ///
  /// In tr, this message translates to:
  /// **'Birkaç adımda haritanı çizeceğiz: doğduğun an, gökyüzünün o anki hâli. Her adımda bir yıldız yanacak.'**
  String get wizardWelcomeBody;

  /// No description provided for @wizardConsentLabel.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım Şartları\'nı ve Gizlilik Politikası\'nı okudum, kabul ediyorum. 13 yaşından büyüğüm.'**
  String get wizardConsentLabel;

  /// No description provided for @wizardDateTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hangi gün doğdun?'**
  String get wizardDateTitle;

  /// No description provided for @wizardDateBody.
  ///
  /// In tr, this message translates to:
  /// **'Gökyüzü her gün başka bir düzendeydi — seninki hangisiydi?'**
  String get wizardDateBody;

  /// No description provided for @wizardTimeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Saat kaçtı?'**
  String get wizardTimeTitle;

  /// No description provided for @wizardTimeBody.
  ///
  /// In tr, this message translates to:
  /// **'Doğum saati Yükselen\'ini ve evlerini belirler. Bilmiyorsan sorun değil — dürüstçe onsuz hesaplarız.'**
  String get wizardTimeBody;

  /// No description provided for @wizardTimeUnknownNote.
  ///
  /// In tr, this message translates to:
  /// **'Saatsiz doğumda Yükselen ve evler hesaplanmaz; okuma gezegen düzeyinde kalır.'**
  String get wizardTimeUnknownNote;

  /// No description provided for @wizardPlaceTitle.
  ///
  /// In tr, this message translates to:
  /// **'Nerede doğdun?'**
  String get wizardPlaceTitle;

  /// No description provided for @wizardPlaceBody.
  ///
  /// In tr, this message translates to:
  /// **'Konum, gökyüzünün sana göre nasıl durduğunu belirler — ufkun neresinde ne yükseliyordu?'**
  String get wizardPlaceBody;

  /// No description provided for @wizardGenderTitle.
  ///
  /// In tr, this message translates to:
  /// **'BaZi için bir ayrıntı'**
  String get wizardGenderTitle;

  /// No description provided for @wizardGenderBody.
  ///
  /// In tr, this message translates to:
  /// **'BaZi (Dört Sütun) şans dönemlerinin yönünü cinsiyetten alır. Belirtmezsen o yön hesaplanmaz; gerisi aynı.'**
  String get wizardGenderBody;

  /// No description provided for @wizardNext.
  ///
  /// In tr, this message translates to:
  /// **'Devam ✦'**
  String get wizardNext;

  /// No description provided for @wizardFinish.
  ///
  /// In tr, this message translates to:
  /// **'Haritamı çiz'**
  String get wizardFinish;

  /// No description provided for @wizardNotifyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Günün okuması hazır olunca?'**
  String get wizardNotifyTitle;

  /// No description provided for @wizardNotifyBody.
  ///
  /// In tr, this message translates to:
  /// **'Günlük okuman ve serin için nazik bir hatırlatma gönderelim mi? Sessiz saatlerini Profil\'den ayarlayabilirsin.'**
  String get wizardNotifyBody;

  /// No description provided for @wizardNotifyAllow.
  ///
  /// In tr, this message translates to:
  /// **'Haber ver 🔔'**
  String get wizardNotifyAllow;

  /// No description provided for @genderUnspecified.
  ///
  /// In tr, this message translates to:
  /// **'Belirtmedim'**
  String get genderUnspecified;

  /// No description provided for @wizardNotifyNotNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi değil'**
  String get wizardNotifyNotNow;

  /// No description provided for @wizardStepOf.
  ///
  /// In tr, this message translates to:
  /// **'Adım {current}/{total}'**
  String wizardStepOf(int current, int total);

  /// No description provided for @deviceConflictBodyUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Başka bir cihazda giriş yapıldı. Rytho+ aynı anda tek cihazda kullanılabilir — burada devam etmek için \"Bu cihazda kullan\"a dokun.'**
  String get deviceConflictBodyUnknown;

  /// No description provided for @emailHint.
  ///
  /// In tr, this message translates to:
  /// **'ad@eposta.com'**
  String get emailHint;

  /// No description provided for @countrySearchHint.
  ///
  /// In tr, this message translates to:
  /// **'Ülke ara…'**
  String get countrySearchHint;

  /// No description provided for @phoneSmsDisabled.
  ///
  /// In tr, this message translates to:
  /// **'SMS doğrulama şu an açık değil. Daha sonra tekrar dene.'**
  String get phoneSmsDisabled;

  /// No description provided for @phoneTemporarilyBlocked.
  ///
  /// In tr, this message translates to:
  /// **'Çok sayıda deneme yüzünden doğrulama geçici olarak durduruldu. Birkaç saat sonra tekrar dene.'**
  String get phoneTemporarilyBlocked;

  /// No description provided for @purchaseEntitlementMissing.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme tamamlandı ama abonelik doğrulanamadı. \"Satın alımları geri yükle\"yi dene; sürerse bize yaz — ödemen güvende.'**
  String get purchaseEntitlementMissing;

  /// No description provided for @purchaseWaitingStore.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza ile konuşuluyor… Bu ekranı kapatma.'**
  String get purchaseWaitingStore;

  /// No description provided for @purchaseWaitingLong.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza işlemi hâlâ sürüyor. Bu ekranı kapatsan da satın alman kaybolmaz: sonuç hesabına kendiliğinden işlenir.'**
  String get purchaseWaitingLong;

  /// No description provided for @purchaseLeaveScreen.
  ///
  /// In tr, this message translates to:
  /// **'Bu ekranı kapat'**
  String get purchaseLeaveScreen;

  /// No description provided for @purchasePendingServer.
  ///
  /// In tr, this message translates to:
  /// **'Satın alman alındı. Hesabına yansıması birkaç saniye sürebilir.'**
  String get purchasePendingServer;

  /// No description provided for @avatarEditTitle.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğrafı yerleştir'**
  String get avatarEditTitle;

  /// No description provided for @avatarEditHint.
  ///
  /// In tr, this message translates to:
  /// **'Sürükleyerek konumlandır, iki parmakla yakınlaştır.'**
  String get avatarEditHint;

  /// No description provided for @avatarUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Profil fotoğrafın güncellendi ✨'**
  String get avatarUpdated;

  /// No description provided for @avatarChangeFailed.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf yüklenemedi. Bağlantını kontrol edip tekrar dene.'**
  String get avatarChangeFailed;

  /// No description provided for @phoneAppNotVerified.
  ///
  /// In tr, this message translates to:
  /// **'Uygulama doğrulaması başarısız oldu. Uygulamayı güncelleyip tekrar dene.'**
  String get phoneAppNotVerified;

  /// No description provided for @citySearchHint.
  ///
  /// In tr, this message translates to:
  /// **'Şehir ara…'**
  String get citySearchHint;

  /// No description provided for @citySearchPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Doğduğun şehrin adını yazmaya başla — 34 bin şehir arasından bul.'**
  String get citySearchPrompt;

  /// No description provided for @citySearchNoResults.
  ///
  /// In tr, this message translates to:
  /// **'Listede bulunamadı — yazdığın adla da kaydedebilirsin.'**
  String get citySearchNoResults;

  /// No description provided for @citySearchUseAsTyped.
  ///
  /// In tr, this message translates to:
  /// **'\"{query}\" olarak kaydet'**
  String citySearchUseAsTyped(String query);

  /// No description provided for @residenceCityTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yaşadığın şehir'**
  String get residenceCityTitle;

  /// No description provided for @residenceCityRowSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Yıl haritası buraya kurulur'**
  String get residenceCityRowSubtitle;

  /// No description provided for @residenceCityBody.
  ///
  /// In tr, this message translates to:
  /// **'Yıl haritası, doğum gününde bulunduğun yere kurulur — şehir Yükselen\'i ve evleri değiştirir. Boş bırakırsan doğum şehrin kullanılır.'**
  String get residenceCityBody;

  /// No description provided for @solarReturnTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yıl Haritası'**
  String get solarReturnTitle;

  /// No description provided for @solarReturnWaitStage1.
  ///
  /// In tr, this message translates to:
  /// **'Güneş\'in dönüş anı hesaplanıyor…'**
  String get solarReturnWaitStage1;

  /// No description provided for @solarReturnWaitStage2.
  ///
  /// In tr, this message translates to:
  /// **'Yılın okuması yazılıyor…'**
  String get solarReturnWaitStage2;

  /// No description provided for @solarReturnLockedBody.
  ///
  /// In tr, this message translates to:
  /// **'Güneş\'in doğum boylamına döndüğü ana kurulan yıl haritası ve Rytho\'nun yıl okuması Rytho+ ile açılır.'**
  String get solarReturnLockedBody;

  /// No description provided for @solarReturnMoment.
  ///
  /// In tr, this message translates to:
  /// **'Dönüş anı'**
  String get solarReturnMoment;

  /// No description provided for @solarReturnNext.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki dönüş: {date}'**
  String solarReturnNext(String date);

  /// No description provided for @solarReturnIdentity.
  ///
  /// In tr, this message translates to:
  /// **'Yılın kimliği'**
  String get solarReturnIdentity;

  /// No description provided for @solarReturnAsc.
  ///
  /// In tr, this message translates to:
  /// **'Yıl Yükseleni'**
  String get solarReturnAsc;

  /// No description provided for @solarReturnSunHouse.
  ///
  /// In tr, this message translates to:
  /// **'Güneş\'in yıl evi'**
  String get solarReturnSunHouse;

  /// No description provided for @solarReturnHouseN.
  ///
  /// In tr, this message translates to:
  /// **'{n}. ev'**
  String solarReturnHouseN(int n);

  /// No description provided for @solarReturnMoon.
  ///
  /// In tr, this message translates to:
  /// **'Yıl Ay\'ı'**
  String get solarReturnMoon;

  /// No description provided for @solarReturnNote.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'nun yıl okuması'**
  String get solarReturnNote;

  /// No description provided for @innerCalendarTitle.
  ///
  /// In tr, this message translates to:
  /// **'İç mevsim'**
  String get innerCalendarTitle;

  /// No description provided for @innerCalendarWaitStage1.
  ///
  /// In tr, this message translates to:
  /// **'Progres harita ilerletiliyor…'**
  String get innerCalendarWaitStage1;

  /// No description provided for @innerCalendarWaitStage2.
  ///
  /// In tr, this message translates to:
  /// **'Progres Ay\'ın mevsimi okunuyor…'**
  String get innerCalendarWaitStage2;

  /// No description provided for @innerCalendarLockedBody.
  ///
  /// In tr, this message translates to:
  /// **'Progres Ay\'ın iç mevsimi ve yaşam yayın Rytho+ ile açılır.'**
  String get innerCalendarLockedBody;

  /// No description provided for @innerCalendarProgMoon.
  ///
  /// In tr, this message translates to:
  /// **'Progres Ay — iç mevsimin'**
  String get innerCalendarProgMoon;

  /// No description provided for @innerCalendarNextSign.
  ///
  /// In tr, this message translates to:
  /// **'{date} → yeni burca geçiş'**
  String innerCalendarNextSign(String date);

  /// No description provided for @innerCalendarActive.
  ///
  /// In tr, this message translates to:
  /// **'Şu an etkin'**
  String get innerCalendarActive;

  /// No description provided for @innerCalendarArc.
  ///
  /// In tr, this message translates to:
  /// **'Yaşam yayı (solar arc)'**
  String get innerCalendarArc;

  /// No description provided for @innerCalendarNote.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'nun iç mevsim okuması'**
  String get innerCalendarNote;

  /// No description provided for @appTagline.
  ///
  /// In tr, this message translates to:
  /// **'Kadim bilgelik, hassas gökyüzü hesabıyla buluşur.\nHaritan çizilir, yolun aydınlanır.'**
  String get appTagline;

  /// No description provided for @signInWithGoogle.
  ///
  /// In tr, this message translates to:
  /// **'Google ile giriş'**
  String get signInWithGoogle;

  /// No description provided for @orDivider.
  ///
  /// In tr, this message translates to:
  /// **'ya da'**
  String get orDivider;

  /// No description provided for @signIn.
  ///
  /// In tr, this message translates to:
  /// **'Giriş yap'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In tr, this message translates to:
  /// **'Üye ol'**
  String get signUp;

  /// No description provided for @email.
  ///
  /// In tr, this message translates to:
  /// **'E-posta'**
  String get email;

  /// No description provided for @password.
  ///
  /// In tr, this message translates to:
  /// **'Şifre'**
  String get password;

  /// No description provided for @forgotPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifremi unuttum'**
  String get forgotPassword;

  /// No description provided for @tabSky.
  ///
  /// In tr, this message translates to:
  /// **'Gökyüzü'**
  String get tabSky;

  /// No description provided for @tabAtlas.
  ///
  /// In tr, this message translates to:
  /// **'Atlas'**
  String get tabAtlas;

  /// No description provided for @tabFriends.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaşlar'**
  String get tabFriends;

  /// No description provided for @tabProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profil'**
  String get tabProfile;

  /// No description provided for @greetingMorning.
  ///
  /// In tr, this message translates to:
  /// **'Günaydın'**
  String get greetingMorning;

  /// No description provided for @greetingDay.
  ///
  /// In tr, this message translates to:
  /// **'İyi günler'**
  String get greetingDay;

  /// No description provided for @greetingEvening.
  ///
  /// In tr, this message translates to:
  /// **'İyi akşamlar'**
  String get greetingEvening;

  /// No description provided for @greetingNight.
  ///
  /// In tr, this message translates to:
  /// **'İyi geceler'**
  String get greetingNight;

  /// No description provided for @todaysInsight.
  ///
  /// In tr, this message translates to:
  /// **'Bugünün İçgörüsü'**
  String get todaysInsight;

  /// No description provided for @skyNow.
  ///
  /// In tr, this message translates to:
  /// **'Şu An Gökyüzünde'**
  String get skyNow;

  /// No description provided for @iChing.
  ///
  /// In tr, this message translates to:
  /// **'I Ching'**
  String get iChing;

  /// No description provided for @iChingSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Değişimler Kitabı'**
  String get iChingSubtitle;

  /// No description provided for @birthHexagram.
  ///
  /// In tr, this message translates to:
  /// **'Doğum Kapısı'**
  String get birthHexagram;

  /// No description provided for @birthHexagramSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'64 kapı'**
  String get birthHexagramSubtitle;

  /// No description provided for @birthHexagramTitle.
  ///
  /// In tr, this message translates to:
  /// **'Doğum Heksagramı'**
  String get birthHexagramTitle;

  /// No description provided for @birthHexagramGateLine.
  ///
  /// In tr, this message translates to:
  /// **'Kapı {gate} · {line}. çizgi'**
  String birthHexagramGateLine(int gate, int line);

  /// No description provided for @birthHexagramGateOnly.
  ///
  /// In tr, this message translates to:
  /// **'Kapı {gate}'**
  String birthHexagramGateOnly(int gate);

  /// No description provided for @birthHexagramSunAt.
  ///
  /// In tr, this message translates to:
  /// **'Doğumda Güneş: {deg}°'**
  String birthHexagramSunAt(String deg);

  /// No description provided for @birthHexagramBoundary.
  ///
  /// In tr, this message translates to:
  /// **'Doğum saati bilinmediği için kapın {a} ya da {b} olabilir.'**
  String birthHexagramBoundary(int a, int b);

  /// No description provided for @birthHexagramLockedBody.
  ///
  /// In tr, this message translates to:
  /// **'Doğum anındaki Güneş\'in 64 kapı çarkındaki yeri — kalıcı karakter kapın. Rytho+ ile açılır.'**
  String get birthHexagramLockedBody;

  /// No description provided for @birthHexagramNote.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'nun kapı okuması'**
  String get birthHexagramNote;

  /// No description provided for @birthHexagramGatePassage.
  ///
  /// In tr, this message translates to:
  /// **'Kapının Dokusu'**
  String get birthHexagramGatePassage;

  /// No description provided for @faceReadingTileSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Firaset sanatı'**
  String get faceReadingTileSubtitle;

  /// No description provided for @baZi.
  ///
  /// In tr, this message translates to:
  /// **'BaZi'**
  String get baZi;

  /// No description provided for @baZiSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Dört Sütun'**
  String get baZiSubtitle;

  /// No description provided for @personalReadingLocked.
  ///
  /// In tr, this message translates to:
  /// **'Sana özel günlük okuma'**
  String get personalReadingLocked;

  /// No description provided for @personalReadingLockedBody.
  ///
  /// In tr, this message translates to:
  /// **'Senin haritanla üretilen günlük yorum Rytho+ ile açılır.'**
  String get personalReadingLockedBody;

  /// No description provided for @personalReadingLockedBodyWithSign.
  ///
  /// In tr, this message translates to:
  /// **'Genel {sign} yorumu hikâye halkasında. Rytho+ ile bu okuma senin Ay’ını ve Yükselen’ini de hesaba katar.'**
  String personalReadingLockedBodyWithSign(String sign);

  /// No description provided for @personalReadingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sana özel'**
  String get personalReadingTitle;

  /// No description provided for @natalLockedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Doğum haritası analizi'**
  String get natalLockedTitle;

  /// No description provided for @natalLockedBody.
  ///
  /// In tr, this message translates to:
  /// **'Gezegen konumların, evlerin ve açıların derin yorumu Rytho+ ile açılır.'**
  String get natalLockedBody;

  /// No description provided for @baziLockedTitle.
  ///
  /// In tr, this message translates to:
  /// **'BaZi — Dört Sütun'**
  String get baziLockedTitle;

  /// No description provided for @baziLockedBody.
  ///
  /// In tr, this message translates to:
  /// **'Day Master, On Tanrı ve şans sütunları analizi Rytho+ ile açılır.'**
  String get baziLockedBody;

  /// No description provided for @iChingLockedTitle.
  ///
  /// In tr, this message translates to:
  /// **'İ Ching — Değişimler Kitabı'**
  String get iChingLockedTitle;

  /// No description provided for @iChingLockedBody.
  ///
  /// In tr, this message translates to:
  /// **'Soru sor, gerçek olasılıklarla çekim yap, Rytho yorumuyla oku — Rytho+ ile açılır.'**
  String get iChingLockedBody;

  /// No description provided for @synastryLockedTitle.
  ///
  /// In tr, this message translates to:
  /// **'İkili çark'**
  String get synastryLockedTitle;

  /// No description provided for @synastryLockedBody.
  ///
  /// In tr, this message translates to:
  /// **'İki haritanın üst üste okuması Rytho+ ile açılır.'**
  String get synastryLockedBody;

  /// No description provided for @addFriend.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaş ekle'**
  String get addFriend;

  /// No description provided for @usernameLabel.
  ///
  /// In tr, this message translates to:
  /// **'KULLANICI ADI'**
  String get usernameLabel;

  /// No description provided for @usernameHeadline.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaşların seni bulabilsin'**
  String get usernameHeadline;

  /// No description provided for @usernameBody.
  ///
  /// In tr, this message translates to:
  /// **'Bir kullanıcı adı seç. Arkadaş eklemek kullanıcı adı ve davet bağlantısıyla olur; istersen Gizlilik bölümünden rehber eşleşmesini de açabilirsin.'**
  String get usernameBody;

  /// No description provided for @usernameHint.
  ///
  /// In tr, this message translates to:
  /// **'kullaniciadi'**
  String get usernameHint;

  /// No description provided for @claimUsername.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adını al'**
  String get claimUsername;

  /// No description provided for @usernameInvalid.
  ///
  /// In tr, this message translates to:
  /// **'3-20 karakter; yalnızca küçük harf, rakam ve alt çizgi.'**
  String get usernameInvalid;

  /// No description provided for @usernameEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı boş olamaz.'**
  String get usernameEmpty;

  /// No description provided for @usernameTaken.
  ///
  /// In tr, this message translates to:
  /// **'Bu kullanıcı adı alınmış, başka bir tane dene.'**
  String get usernameTaken;

  /// No description provided for @copyInviteLink.
  ///
  /// In tr, this message translates to:
  /// **'Davet bağlantısını kopyala'**
  String get copyInviteLink;

  /// No description provided for @inviteLinkCopied.
  ///
  /// In tr, this message translates to:
  /// **'Davet bağlantısı kopyalandı.'**
  String get inviteLinkCopied;

  /// No description provided for @shareInviteInstead.
  ///
  /// In tr, this message translates to:
  /// **'Bunun yerine davet bağlantımı paylaş'**
  String get shareInviteInstead;

  /// No description provided for @sendInvite.
  ///
  /// In tr, this message translates to:
  /// **'Davet gönder'**
  String get sendInvite;

  /// No description provided for @inviteSent.
  ///
  /// In tr, this message translates to:
  /// **'@{username} kullanıcısına davet gönderildi.'**
  String inviteSent(String username);

  /// No description provided for @userNotFound.
  ///
  /// In tr, this message translates to:
  /// **'@{username} bulunamadı.'**
  String userNotFound(String username);

  /// No description provided for @cannotAddSelf.
  ///
  /// In tr, this message translates to:
  /// **'Kendini ekleyemezsin.'**
  String get cannotAddSelf;

  /// No description provided for @inboxLabel.
  ///
  /// In tr, this message translates to:
  /// **'SANA GELENLER'**
  String get inboxLabel;

  /// No description provided for @noFriendsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz kimse yok'**
  String get noFriendsYet;

  /// No description provided for @noFriendsBody.
  ///
  /// In tr, this message translates to:
  /// **'Bir arkadaşını kullanıcı adıyla ekle; serilerinizi görün ve her gün aranızdaki dinamiği okuyun.'**
  String get noFriendsBody;

  /// No description provided for @incomingRequests.
  ///
  /// In tr, this message translates to:
  /// **'Gelen davetler'**
  String get incomingRequests;

  /// No description provided for @pendingInvites.
  ///
  /// In tr, this message translates to:
  /// **'Yanıt bekleyen davetlerin'**
  String get pendingInvites;

  /// No description provided for @accept.
  ///
  /// In tr, this message translates to:
  /// **'Kabul et'**
  String get accept;

  /// No description provided for @ignore.
  ///
  /// In tr, this message translates to:
  /// **'Yoksay'**
  String get ignore;

  /// No description provided for @pending.
  ///
  /// In tr, this message translates to:
  /// **'Bekliyor'**
  String get pending;

  /// No description provided for @withdrawInvite.
  ///
  /// In tr, this message translates to:
  /// **'Daveti geri al'**
  String get withdrawInvite;

  /// No description provided for @readToday.
  ///
  /// In tr, this message translates to:
  /// **'Bugün okumasını yaptı'**
  String get readToday;

  /// No description provided for @notReadToday.
  ///
  /// In tr, this message translates to:
  /// **'Bugün henüz okumadı'**
  String get notReadToday;

  /// No description provided for @streakHidden.
  ///
  /// In tr, this message translates to:
  /// **'Serisi gizli'**
  String get streakHidden;

  /// No description provided for @friendLabel.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaşın'**
  String get friendLabel;

  /// No description provided for @streakHiddenByFriend.
  ///
  /// In tr, this message translates to:
  /// **'Serisini gizli tutuyor'**
  String get streakHiddenByFriend;

  /// No description provided for @readTodayDone.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü okumasını yaptı'**
  String get readTodayDone;

  /// No description provided for @dyadLabel.
  ///
  /// In tr, this message translates to:
  /// **'Bugün aranızda'**
  String get dyadLabel;

  /// No description provided for @dyadDisclaimer.
  ///
  /// In tr, this message translates to:
  /// **'Bu okuma yalnızca bugün için geçerlidir ve yarın değişir. Kalıcı bir uyum puanı vermiyoruz.'**
  String get dyadDisclaimer;

  /// No description provided for @sendReaction.
  ///
  /// In tr, this message translates to:
  /// **'Bir tepki gönder'**
  String get sendReaction;

  /// No description provided for @sendReactionBody.
  ///
  /// In tr, this message translates to:
  /// **'Hazır tepkilerden birini seç — mesaj yazma yok, sadece küçük bir selam.'**
  String get sendReactionBody;

  /// No description provided for @reactionSent.
  ///
  /// In tr, this message translates to:
  /// **'{emoji} gönderildi.'**
  String reactionSent(String emoji);

  /// No description provided for @removeFriend.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaşlıktan çıkar'**
  String get removeFriend;

  /// No description provided for @blockUser.
  ///
  /// In tr, this message translates to:
  /// **'Engelle'**
  String get blockUser;

  /// No description provided for @reportUser.
  ///
  /// In tr, this message translates to:
  /// **'Şikayet et'**
  String get reportUser;

  /// No description provided for @reactionStreak.
  ///
  /// In tr, this message translates to:
  /// **'Seri devam'**
  String get reactionStreak;

  /// No description provided for @reactionThinkingOfYou.
  ///
  /// In tr, this message translates to:
  /// **'Seni düşündüm'**
  String get reactionThinkingOfYou;

  /// No description provided for @reactionShine.
  ///
  /// In tr, this message translates to:
  /// **'Parlıyorsun'**
  String get reactionShine;

  /// No description provided for @reactionKeepGoing.
  ///
  /// In tr, this message translates to:
  /// **'Devam et'**
  String get reactionKeepGoing;

  /// No description provided for @reactionCongrats.
  ///
  /// In tr, this message translates to:
  /// **'Tebrikler'**
  String get reactionCongrats;

  /// No description provided for @reactionSameFrequency.
  ///
  /// In tr, this message translates to:
  /// **'Aynı frekans'**
  String get reactionSameFrequency;

  /// No description provided for @reactionGoodNight.
  ///
  /// In tr, this message translates to:
  /// **'İyi geceler'**
  String get reactionGoodNight;

  /// No description provided for @reactionCheckToday.
  ///
  /// In tr, this message translates to:
  /// **'Bugüne bak'**
  String get reactionCheckToday;

  /// No description provided for @paywallTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rytho+'**
  String get paywallTitle;

  /// No description provided for @paywallHeadline.
  ///
  /// In tr, this message translates to:
  /// **'Yıldızlar herkese aynı,\nsen değilsin.'**
  String get paywallHeadline;

  /// No description provided for @paywallBody.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz katmanda günlük burç yorumun ve gerçek gökyüzü verisi her zaman açık kalır. Rytho+ ise yorumları senin haritanla üretir.'**
  String get paywallBody;

  /// No description provided for @paywallContinue.
  ///
  /// In tr, this message translates to:
  /// **'Rytho+ ile devam et'**
  String get paywallContinue;

  /// No description provided for @paywallChoosePlan.
  ///
  /// In tr, this message translates to:
  /// **'Paket seç'**
  String get paywallChoosePlan;

  /// No description provided for @restorePurchases.
  ///
  /// In tr, this message translates to:
  /// **'Satın alımları geri yükle'**
  String get restorePurchases;

  /// No description provided for @noActiveSubscription.
  ///
  /// In tr, this message translates to:
  /// **'Geri yüklenecek aktif bir abonelik bulunamadı.'**
  String get noActiveSubscription;

  /// No description provided for @purchaseFailed.
  ///
  /// In tr, this message translates to:
  /// **'Satın alma tamamlanamadı.'**
  String get purchaseFailed;

  /// No description provided for @billingUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'Satın alma şu an kullanılamıyor'**
  String get billingUnavailable;

  /// No description provided for @billingNoPackages.
  ///
  /// In tr, this message translates to:
  /// **'Mağazada tanımlı paket bulunamadı.'**
  String get billingNoPackages;

  /// No description provided for @planWeekly.
  ///
  /// In tr, this message translates to:
  /// **'Haftalık'**
  String get planWeekly;

  /// No description provided for @planMonthly.
  ///
  /// In tr, this message translates to:
  /// **'Aylık'**
  String get planMonthly;

  /// No description provided for @planAnnual.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık'**
  String get planAnnual;

  /// No description provided for @paywallForFeature.
  ///
  /// In tr, this message translates to:
  /// **'{name} için Rytho+'**
  String paywallForFeature(String name);

  /// No description provided for @priceWithPeriod.
  ///
  /// In tr, this message translates to:
  /// **'{price} / {unit}'**
  String priceWithPeriod(String price, String unit);

  /// No description provided for @annualPerMonth.
  ///
  /// In tr, this message translates to:
  /// **'ayda ≈ {price}'**
  String annualPerMonth(String price);

  /// No description provided for @annualSavingsBadge.
  ///
  /// In tr, this message translates to:
  /// **'%{percent} tasarruf'**
  String annualSavingsBadge(int percent);

  /// No description provided for @trialThenPriceDays.
  ///
  /// In tr, this message translates to:
  /// **'{count} gün ücretsiz, sonra {price}'**
  String trialThenPriceDays(int count, String price);

  /// No description provided for @trialThenPriceWeeks.
  ///
  /// In tr, this message translates to:
  /// **'{count} hafta ücretsiz, sonra {price}'**
  String trialThenPriceWeeks(int count, String price);

  /// No description provided for @trialThenPriceMonths.
  ///
  /// In tr, this message translates to:
  /// **'{count} ay ücretsiz, sonra {price}'**
  String trialThenPriceMonths(int count, String price);

  /// No description provided for @trialThenPriceYears.
  ///
  /// In tr, this message translates to:
  /// **'{count} yıl ücretsiz, sonra {price}'**
  String trialThenPriceYears(int count, String price);

  /// No description provided for @unitDay.
  ///
  /// In tr, this message translates to:
  /// **'gün'**
  String get unitDay;

  /// No description provided for @unitWeek.
  ///
  /// In tr, this message translates to:
  /// **'hafta'**
  String get unitWeek;

  /// No description provided for @unitMonth.
  ///
  /// In tr, this message translates to:
  /// **'ay'**
  String get unitMonth;

  /// No description provided for @unitYear.
  ///
  /// In tr, this message translates to:
  /// **'yıl'**
  String get unitYear;

  /// No description provided for @subscriptionTerms.
  ///
  /// In tr, this message translates to:
  /// **'Abonelik, dönem bitiminden en az 24 saat önce iptal edilmezse otomatik yenilenir. Deneme süresi varsa, süre dolmadan iptal edersen ücret alınmaz. İptali cihazının mağaza hesabı ayarlarından yapabilirsin.'**
  String get subscriptionTerms;

  /// No description provided for @benefitDailyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kişiye özel günlük okuma'**
  String get benefitDailyTitle;

  /// No description provided for @benefitDailyBody.
  ///
  /// In tr, this message translates to:
  /// **'Natal haritan bugünün gökyüzüyle çarpışır — genel burç yorumu değil.'**
  String get benefitDailyBody;

  /// No description provided for @benefitNatalTitle.
  ///
  /// In tr, this message translates to:
  /// **'Derin doğum haritası raporu'**
  String get benefitNatalTitle;

  /// No description provided for @benefitNatalBody.
  ///
  /// In tr, this message translates to:
  /// **'Gezegenler, evler ve açılar; tek seferlik yüzeysel özet değil.'**
  String get benefitNatalBody;

  /// No description provided for @benefitDyadTitle.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaşlarınla günlük ikili dinamik'**
  String get benefitDyadTitle;

  /// No description provided for @benefitDyadBody.
  ///
  /// In tr, this message translates to:
  /// **'Her gün yenilenen ortak okuma. Kalıcı uyum puanı yok.'**
  String get benefitDyadBody;

  /// No description provided for @benefitChatTitleCount.
  ///
  /// In tr, this message translates to:
  /// **'Ayda {count} AI kredisi'**
  String benefitChatTitleCount(int count);

  /// No description provided for @benefitChatTitleUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Aylık AI kredisi'**
  String get benefitChatTitleUnknown;

  /// No description provided for @benefitChatBody.
  ///
  /// In tr, this message translates to:
  /// **'Sohbette, raporlarda ve çekimlerde dilediğin gibi harca; Rytho seni tanıdıkça konuşma derinleşir.'**
  String get benefitChatBody;

  /// No description provided for @benefitBaziTitle.
  ///
  /// In tr, this message translates to:
  /// **'BaZi ve sinastri'**
  String get benefitBaziTitle;

  /// No description provided for @benefitBaziBody.
  ///
  /// In tr, this message translates to:
  /// **'Dört Sütun analizi ve ikili harita karşılaştırması.'**
  String get benefitBaziBody;

  /// No description provided for @benefitFaceTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yüz Okuma'**
  String get benefitFaceTitle;

  /// No description provided for @benefitFaceBody.
  ///
  /// In tr, this message translates to:
  /// **'Yüz hatlarından firaset geleneğine göre mizaç okuması. Görüntü cihazında işlenir; sunucuya yalnız ölçülen oranlar gider.'**
  String get benefitFaceBody;

  /// No description provided for @benefitTimingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yıl Haritası, İç Takvim ve Doğum Kapısı'**
  String get benefitTimingTitle;

  /// No description provided for @benefitTimingBody.
  ///
  /// In tr, this message translates to:
  /// **'Güneş\'in doğum boylamına döndüğü ana kurulan yıl haritan, ilerletilmiş iç takvimin ve 64 kapı çarkındaki doğum kapın.'**
  String get benefitTimingBody;

  /// No description provided for @benefitIchingTitle.
  ///
  /// In tr, this message translates to:
  /// **'I Ching çekimi'**
  String get benefitIchingTitle;

  /// No description provided for @benefitIchingBody.
  ///
  /// In tr, this message translates to:
  /// **'Gerçek olasılıklarla atılan çekim ve hareketli çizgilerin Rytho yorumu.'**
  String get benefitIchingBody;

  /// No description provided for @benefitPeopleTitle.
  ///
  /// In tr, this message translates to:
  /// **'10 kişilik çevre'**
  String get benefitPeopleTitle;

  /// No description provided for @benefitPeopleBody.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz katmanda tek kişi eklenir; Rytho+ ile on kişiye kadar ekler, her biriyle sinastri okursun.'**
  String get benefitPeopleBody;

  /// No description provided for @profileTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sicil'**
  String get profileTitle;

  /// No description provided for @settings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get settings;

  /// No description provided for @sounds.
  ///
  /// In tr, this message translates to:
  /// **'Sesler'**
  String get sounds;

  /// No description provided for @privacy.
  ///
  /// In tr, this message translates to:
  /// **'Gizlilik'**
  String get privacy;

  /// No description provided for @streakVisibleSetting.
  ///
  /// In tr, this message translates to:
  /// **'Serimi arkadaşlarım görsün'**
  String get streakVisibleSetting;

  /// No description provided for @streakVisibleSettingBody.
  ///
  /// In tr, this message translates to:
  /// **'Kapalıyken serin ve bugün okuyup okumadığın paylaşılmaz.'**
  String get streakVisibleSettingBody;

  /// No description provided for @language.
  ///
  /// In tr, this message translates to:
  /// **'Dil'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In tr, this message translates to:
  /// **'Sistem dili'**
  String get languageSystem;

  /// No description provided for @languageTurkish.
  ///
  /// In tr, this message translates to:
  /// **'Türkçe'**
  String get languageTurkish;

  /// No description provided for @languageEnglish.
  ///
  /// In tr, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @about.
  ///
  /// In tr, this message translates to:
  /// **'Hakkında'**
  String get about;

  /// No description provided for @aboutBody.
  ///
  /// In tr, this message translates to:
  /// **'Rytho; Batı astrolojisi, BaZi ve I Ching geleneklerini hassas efemeris hesabıyla birleştirir. Yorumlar içgörü amaçlıdır; tıbbi, hukuki veya finansal tavsiye değildir.'**
  String get aboutBody;

  /// No description provided for @ephemerisCredit.
  ///
  /// In tr, this message translates to:
  /// **'Efemeris: Swiss Ephemeris © Astrodienst AG'**
  String get ephemerisCredit;

  /// No description provided for @privacyPolicy.
  ///
  /// In tr, this message translates to:
  /// **'Gizlilik Politikası'**
  String get privacyPolicy;

  /// No description provided for @termsOfUse.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım Şartları'**
  String get termsOfUse;

  /// No description provided for @signOut.
  ///
  /// In tr, this message translates to:
  /// **'Oturumu kapat'**
  String get signOut;

  /// No description provided for @signOutConfirmBody.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler bu cihazda durur; yeniden girdiğinde kaldığın yerden devam edersin.'**
  String get signOutConfirmBody;

  /// No description provided for @streakDays.
  ///
  /// In tr, this message translates to:
  /// **'{count, plural, =1{1 gün} other{{count} gün}}'**
  String streakDays(int count);

  /// No description provided for @birthRecord.
  ///
  /// In tr, this message translates to:
  /// **'Doğum Kaydı'**
  String get birthRecord;

  /// No description provided for @birthDate.
  ///
  /// In tr, this message translates to:
  /// **'Tarih'**
  String get birthDate;

  /// No description provided for @birthTime.
  ///
  /// In tr, this message translates to:
  /// **'Saat'**
  String get birthTime;

  /// No description provided for @birthTimeUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Doğum saatimi bilmiyorum'**
  String get birthTimeUnknown;

  /// No description provided for @birthCity.
  ///
  /// In tr, this message translates to:
  /// **'Şehir'**
  String get birthCity;

  /// No description provided for @retry.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar dene'**
  String get retry;

  /// No description provided for @retryAfterSeconds.
  ///
  /// In tr, this message translates to:
  /// **'{n} sn sonra tekrar dene'**
  String retryAfterSeconds(int n);

  /// No description provided for @delete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get delete;

  /// No description provided for @discard.
  ///
  /// In tr, this message translates to:
  /// **'Bırak'**
  String get discard;

  /// No description provided for @feedbackDiscardTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yazdıklarını bırak'**
  String get feedbackDiscardTitle;

  /// No description provided for @feedbackDiscardBody.
  ///
  /// In tr, this message translates to:
  /// **'Geri bildirim kaydedilmeyecek.'**
  String get feedbackDiscardBody;

  /// No description provided for @errorGeneric.
  ///
  /// In tr, this message translates to:
  /// **'Beklenmeyen bir sorun oluştu. Lütfen biraz sonra tekrar dene.'**
  String get errorGeneric;

  /// No description provided for @errorConnection.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.'**
  String get errorConnection;

  /// No description provided for @reportUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'Okumayı şu an üretemedik. Birkaç saniye sonra tekrar dene.'**
  String get reportUnavailable;

  /// No description provided for @reportUnavailableRefunded.
  ///
  /// In tr, this message translates to:
  /// **'Raporu şu an üretemedik; harcanan kredi iade edildi. Birkaç saniye sonra tekrar dene.'**
  String get reportUnavailableRefunded;

  /// No description provided for @chatTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rytho AI'**
  String get chatTitle;

  /// No description provided for @chatSend.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get chatSend;

  /// No description provided for @chatHint.
  ///
  /// In tr, this message translates to:
  /// **'Geleceğinle ilgili her şeyi sor...'**
  String get chatHint;

  /// No description provided for @chatEmptyBody.
  ///
  /// In tr, this message translates to:
  /// **'Haritan, yüzün, kaderin... Aklından geçen her soruyu sor.'**
  String get chatEmptyBody;

  /// No description provided for @suggestCareer.
  ///
  /// In tr, this message translates to:
  /// **'Kariyer 💼'**
  String get suggestCareer;

  /// No description provided for @suggestLove.
  ///
  /// In tr, this message translates to:
  /// **'Aşk hayatı ❤️'**
  String get suggestLove;

  /// No description provided for @suggestMonth.
  ///
  /// In tr, this message translates to:
  /// **'Bu ay beni ne bekliyor?'**
  String get suggestMonth;

  /// No description provided for @suggestFinance.
  ///
  /// In tr, this message translates to:
  /// **'Finansal şans 💰'**
  String get suggestFinance;

  /// No description provided for @suggestMarriage.
  ///
  /// In tr, this message translates to:
  /// **'Evlilik zamanı 💍'**
  String get suggestMarriage;

  /// No description provided for @onboardingCity.
  ///
  /// In tr, this message translates to:
  /// **'Doğum şehri'**
  String get onboardingCity;

  /// No description provided for @genderFemale.
  ///
  /// In tr, this message translates to:
  /// **'Kadın'**
  String get genderFemale;

  /// No description provided for @genderMale.
  ///
  /// In tr, this message translates to:
  /// **'Erkek'**
  String get genderMale;

  /// No description provided for @genderOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get genderOther;

  /// No description provided for @onboardingStage1.
  ///
  /// In tr, this message translates to:
  /// **'Gökyüzü konumlanıyor'**
  String get onboardingStage1;

  /// No description provided for @onboardingStage2.
  ///
  /// In tr, this message translates to:
  /// **'Evler hesaplanıyor'**
  String get onboardingStage2;

  /// No description provided for @onboardingStage3.
  ///
  /// In tr, this message translates to:
  /// **'Haritan çiziliyor'**
  String get onboardingStage3;

  /// No description provided for @bigThreeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Göğün sana üç mührü'**
  String get bigThreeTitle;

  /// No description provided for @bigThreeSun.
  ///
  /// In tr, this message translates to:
  /// **'GÜNEŞ'**
  String get bigThreeSun;

  /// No description provided for @bigThreeMoon.
  ///
  /// In tr, this message translates to:
  /// **'AY'**
  String get bigThreeMoon;

  /// No description provided for @bigThreeAscendant.
  ///
  /// In tr, this message translates to:
  /// **'YÜKSELEN'**
  String get bigThreeAscendant;

  /// No description provided for @bigThreeAscendantUnknown.
  ///
  /// In tr, this message translates to:
  /// **'saat yok'**
  String get bigThreeAscendantUnknown;

  /// No description provided for @bigThreeStart.
  ///
  /// In tr, this message translates to:
  /// **'Yolculuğa başla'**
  String get bigThreeStart;

  /// No description provided for @profileSubscriptionRow.
  ///
  /// In tr, this message translates to:
  /// **'Abonelik ve krediler'**
  String get profileSubscriptionRow;

  /// No description provided for @subscriptionScreenTitle.
  ///
  /// In tr, this message translates to:
  /// **'Abonelik ve Krediler'**
  String get subscriptionScreenTitle;

  /// No description provided for @subPlanLabel.
  ///
  /// In tr, this message translates to:
  /// **'PLAN'**
  String get subPlanLabel;

  /// No description provided for @subPlanFree.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz'**
  String get subPlanFree;

  /// No description provided for @subPlanFreeBody.
  ///
  /// In tr, this message translates to:
  /// **'Kişiye özel günlük okuma, natal rapor, BaZi, Yıl Haritası ve İç Takvim Rytho+ ile açılır.'**
  String get subPlanFreeBody;

  /// No description provided for @subPlanMonthly.
  ///
  /// In tr, this message translates to:
  /// **'Aylık Rytho+'**
  String get subPlanMonthly;

  /// No description provided for @subPlanYearly.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık Rytho+'**
  String get subPlanYearly;

  /// No description provided for @subGoPlus.
  ///
  /// In tr, this message translates to:
  /// **'Rytho+\'a geç'**
  String get subGoPlus;

  /// No description provided for @subStatusLabel.
  ///
  /// In tr, this message translates to:
  /// **'Durum'**
  String get subStatusLabel;

  /// No description provided for @subStatusTrial.
  ///
  /// In tr, this message translates to:
  /// **'Deneme sürümü'**
  String get subStatusTrial;

  /// No description provided for @subRenewsLabel.
  ///
  /// In tr, this message translates to:
  /// **'Yenilenme'**
  String get subRenewsLabel;

  /// No description provided for @subEndsLabel.
  ///
  /// In tr, this message translates to:
  /// **'Sona erme'**
  String get subEndsLabel;

  /// No description provided for @subManage.
  ///
  /// In tr, this message translates to:
  /// **'Aboneliği yönet'**
  String get subManage;

  /// No description provided for @subManageOpenFailed.
  ///
  /// In tr, this message translates to:
  /// **'Abonelik sayfası açılamadı — mağaza uygulamasından yönetebilirsin.'**
  String get subManageOpenFailed;

  /// No description provided for @subRestoreDone.
  ///
  /// In tr, this message translates to:
  /// **'Aboneliğin geri yüklendi ✨'**
  String get subRestoreDone;

  /// No description provided for @subMonthlyAllowanceRow.
  ///
  /// In tr, this message translates to:
  /// **'Aylık hak'**
  String get subMonthlyAllowanceRow;

  /// No description provided for @subAllowanceResetsRow.
  ///
  /// In tr, this message translates to:
  /// **'Hak tazelenir'**
  String get subAllowanceResetsRow;

  /// No description provided for @subBuyTokens.
  ///
  /// In tr, this message translates to:
  /// **'Kredi paketi al'**
  String get subBuyTokens;

  /// No description provided for @atlasWaitStage1.
  ///
  /// In tr, this message translates to:
  /// **'Gezegenler yerleşiyor'**
  String get atlasWaitStage1;

  /// No description provided for @atlasWaitStage2.
  ///
  /// In tr, this message translates to:
  /// **'Açılar okunuyor'**
  String get atlasWaitStage2;

  /// No description provided for @atlasWaitStage3.
  ///
  /// In tr, this message translates to:
  /// **'Raporun yazılıyor'**
  String get atlasWaitStage3;

  /// No description provided for @baziWaitStage1.
  ///
  /// In tr, this message translates to:
  /// **'Dört sütun kuruluyor'**
  String get baziWaitStage1;

  /// No description provided for @baziWaitStage2.
  ///
  /// In tr, this message translates to:
  /// **'Elementler tartılıyor'**
  String get baziWaitStage2;

  /// No description provided for @baziWaitStage3.
  ///
  /// In tr, this message translates to:
  /// **'Kader notun yazılıyor'**
  String get baziWaitStage3;

  /// No description provided for @atlasTitle.
  ///
  /// In tr, this message translates to:
  /// **'Doğum Haritası Analizi'**
  String get atlasTitle;

  /// No description provided for @appHeadline.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel Kozmik Zekân'**
  String get appHeadline;

  /// No description provided for @authNameRequired.
  ///
  /// In tr, this message translates to:
  /// **'Adını yaz.'**
  String get authNameRequired;

  /// No description provided for @authInvalidEmail.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir e-posta yaz.'**
  String get authInvalidEmail;

  /// No description provided for @authWrongCredentials.
  ///
  /// In tr, this message translates to:
  /// **'E-posta veya şifre hatalı.'**
  String get authWrongCredentials;

  /// No description provided for @authEmailInUse.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta zaten kayıtlı. Giriş yapmayı dene.'**
  String get authEmailInUse;

  /// No description provided for @authTooManyRequests.
  ///
  /// In tr, this message translates to:
  /// **'Çok fazla deneme yapıldı. Biraz sonra tekrar dene.'**
  String get authTooManyRequests;

  /// No description provided for @authDisabled.
  ///
  /// In tr, this message translates to:
  /// **'E-posta ile giriş şu an kapalı.'**
  String get authDisabled;

  /// No description provided for @authNetwork.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı kurulamadı. İnternetini kontrol et.'**
  String get authNetwork;

  /// No description provided for @authFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bir şeyler ters gitti. Tekrar dene.'**
  String get authFailed;

  /// No description provided for @authReauthNeeded.
  ///
  /// In tr, this message translates to:
  /// **'Google hesabının bu cihazda yeniden doğrulanması gerekiyor. Telefonunun Ayarlar → Google bölümüne girip hesabını doğrula (gerekirse hesabı kaldırıp yeniden ekle), sonra tekrar dene.'**
  String get authReauthNeeded;

  /// No description provided for @displayName.
  ///
  /// In tr, this message translates to:
  /// **'Adın'**
  String get displayName;

  /// No description provided for @passwordRepeat.
  ///
  /// In tr, this message translates to:
  /// **'Şifre (tekrar)'**
  String get passwordRepeat;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In tr, this message translates to:
  /// **'Şifreler eşleşmiyor.'**
  String get passwordsDoNotMatch;

  /// No description provided for @nameLabel.
  ///
  /// In tr, this message translates to:
  /// **'Ad'**
  String get nameLabel;

  /// No description provided for @signAries.
  ///
  /// In tr, this message translates to:
  /// **'Koç'**
  String get signAries;

  /// No description provided for @signTaurus.
  ///
  /// In tr, this message translates to:
  /// **'Boğa'**
  String get signTaurus;

  /// No description provided for @signGemini.
  ///
  /// In tr, this message translates to:
  /// **'İkizler'**
  String get signGemini;

  /// No description provided for @signCancer.
  ///
  /// In tr, this message translates to:
  /// **'Yengeç'**
  String get signCancer;

  /// No description provided for @signLeo.
  ///
  /// In tr, this message translates to:
  /// **'Aslan'**
  String get signLeo;

  /// No description provided for @signVirgo.
  ///
  /// In tr, this message translates to:
  /// **'Başak'**
  String get signVirgo;

  /// No description provided for @signLibra.
  ///
  /// In tr, this message translates to:
  /// **'Terazi'**
  String get signLibra;

  /// No description provided for @signScorpio.
  ///
  /// In tr, this message translates to:
  /// **'Akrep'**
  String get signScorpio;

  /// No description provided for @signSagittarius.
  ///
  /// In tr, this message translates to:
  /// **'Yay'**
  String get signSagittarius;

  /// No description provided for @signCapricorn.
  ///
  /// In tr, this message translates to:
  /// **'Oğlak'**
  String get signCapricorn;

  /// No description provided for @signAquarius.
  ///
  /// In tr, this message translates to:
  /// **'Kova'**
  String get signAquarius;

  /// No description provided for @signPisces.
  ///
  /// In tr, this message translates to:
  /// **'Balık'**
  String get signPisces;

  /// No description provided for @atlasPlanetPositions.
  ///
  /// In tr, this message translates to:
  /// **'Gezegen Konumları'**
  String get atlasPlanetPositions;

  /// No description provided for @atlasTraits.
  ///
  /// In tr, this message translates to:
  /// **'Kişilik Özellikleri'**
  String get atlasTraits;

  /// No description provided for @atlasAspects.
  ///
  /// In tr, this message translates to:
  /// **'Açılar'**
  String get atlasAspects;

  /// No description provided for @moonIllumination.
  ///
  /// In tr, this message translates to:
  /// **'aydınlanma %{percent}'**
  String moonIllumination(Object percent);

  /// No description provided for @moonIlluminationAsOf.
  ///
  /// In tr, this message translates to:
  /// **'{time} itibarıyla — oran gün içinde değişir'**
  String moonIlluminationAsOf(String time);

  /// No description provided for @reportPostTitle.
  ///
  /// In tr, this message translates to:
  /// **'GÖNDERİYİ ŞİKAYET ET'**
  String get reportPostTitle;

  /// No description provided for @reportUserTitle.
  ///
  /// In tr, this message translates to:
  /// **'KULLANICIYI ŞİKAYET ET'**
  String get reportUserTitle;

  /// No description provided for @reportNote.
  ///
  /// In tr, this message translates to:
  /// **'Şikayetin ekibimiz tarafından incelenir.'**
  String get reportNote;

  /// No description provided for @reportReasonSpam.
  ///
  /// In tr, this message translates to:
  /// **'Spam veya yanıltıcı içerik'**
  String get reportReasonSpam;

  /// No description provided for @reportReasonHarassment.
  ///
  /// In tr, this message translates to:
  /// **'Hakaret veya taciz'**
  String get reportReasonHarassment;

  /// No description provided for @reportReasonInappropriate.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz / rahatsız edici içerik'**
  String get reportReasonInappropriate;

  /// No description provided for @reportReasonOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get reportReasonOther;

  /// No description provided for @reportSubmitted.
  ///
  /// In tr, this message translates to:
  /// **'Şikayetin alındı; en kısa sürede incelenecek. Teşekkürler.'**
  String get reportSubmitted;

  /// No description provided for @reportFailed.
  ///
  /// In tr, this message translates to:
  /// **'Şikayet gönderilemedi.'**
  String get reportFailed;

  /// No description provided for @aFriend.
  ///
  /// In tr, this message translates to:
  /// **'Bir arkadaşın'**
  String get aFriend;

  /// No description provided for @iChingIntro.
  ///
  /// In tr, this message translates to:
  /// **'3000 yıllık 64 heksagram matrisi. Sorunu yaz; paralar gerçek olasılık dağılımıyla atılır, hareketli çizgiler geleceğe köprü kurar.'**
  String get iChingIntro;

  /// No description provided for @iChingQuestionHint.
  ///
  /// In tr, this message translates to:
  /// **'Sorun nedir?'**
  String get iChingQuestionHint;

  /// No description provided for @iChingMethodCoins.
  ///
  /// In tr, this message translates to:
  /// **'Üç Para 🪙'**
  String get iChingMethodCoins;

  /// No description provided for @iChingMethodYarrow.
  ///
  /// In tr, this message translates to:
  /// **'Civanperçemi 🌿'**
  String get iChingMethodYarrow;

  /// No description provided for @iChingCastAction.
  ///
  /// In tr, this message translates to:
  /// **'Çekimi yap'**
  String get iChingCastAction;

  /// No description provided for @iChingQuestionRequired.
  ///
  /// In tr, this message translates to:
  /// **'Önce kalbindeki soruyu yaz.'**
  String get iChingQuestionRequired;

  /// No description provided for @iChingQuestionInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Kâhin bu metinde yorumlayacağı bir soru bulamadı — niyetini kendi yaşamınla ilgili bir cümleyle yaz.'**
  String get iChingQuestionInvalid;

  /// No description provided for @iChingCoinsInAir.
  ///
  /// In tr, this message translates to:
  /// **'Paralar havada...'**
  String get iChingCoinsInAir;

  /// No description provided for @iChingCoinsLanding.
  ///
  /// In tr, this message translates to:
  /// **'Paralar düşüyor… {n}/6'**
  String iChingCoinsLanding(int n);

  /// No description provided for @iChingHexagramLabel.
  ///
  /// In tr, this message translates to:
  /// **'HEKSAGRAM {number}'**
  String iChingHexagramLabel(Object number);

  /// No description provided for @iChingTransformedTo.
  ///
  /// In tr, this message translates to:
  /// **'→ dönüşüm: {name} (#{number})'**
  String iChingTransformedTo(Object name, Object number);

  /// No description provided for @iChingOracleNote.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'nun kehanet notu'**
  String get iChingOracleNote;

  /// No description provided for @iChingJudgmentTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hüküm'**
  String get iChingJudgmentTitle;

  /// No description provided for @iChingImageTitle.
  ///
  /// In tr, this message translates to:
  /// **'İmge'**
  String get iChingImageTitle;

  /// No description provided for @iChingMovingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hareketli Çizgiler'**
  String get iChingMovingTitle;

  /// No description provided for @iChingLiuYaoTitle.
  ///
  /// In tr, this message translates to:
  /// **'Liu Yao'**
  String get iChingLiuYaoTitle;

  /// No description provided for @iChingNuclearLabel.
  ///
  /// In tr, this message translates to:
  /// **'çekirdek: {name} (#{n})'**
  String iChingNuclearLabel(String name, int n);

  /// No description provided for @iChingLegend.
  ///
  /// In tr, this message translates to:
  /// **'○ eski yang (9) · × eski yin (6) — dönen çizgiler'**
  String get iChingLegend;

  /// No description provided for @iChingShiTag.
  ///
  /// In tr, this message translates to:
  /// **'özne'**
  String get iChingShiTag;

  /// No description provided for @iChingYingTag.
  ///
  /// In tr, this message translates to:
  /// **'karşılık'**
  String get iChingYingTag;

  /// No description provided for @iChingTapToSkip.
  ///
  /// In tr, this message translates to:
  /// **'İnişi atlamak için dokun'**
  String get iChingTapToSkip;

  /// No description provided for @iChingLineLabel.
  ///
  /// In tr, this message translates to:
  /// **'{n}. çizgi'**
  String iChingLineLabel(int n);

  /// No description provided for @iChingPalaceLabel.
  ///
  /// In tr, this message translates to:
  /// **'Saray: {name} · özne (shi) {shi}. çizgi · karşılık (ying) {ying}. çizgi'**
  String iChingPalaceLabel(String name, int shi, int ying);

  /// No description provided for @iChingVoidTag.
  ///
  /// In tr, this message translates to:
  /// **'boşluk'**
  String get iChingVoidTag;

  /// No description provided for @iChingClashTag.
  ///
  /// In tr, this message translates to:
  /// **'çarpışma'**
  String get iChingClashTag;

  /// No description provided for @iChingDayLabel.
  ///
  /// In tr, this message translates to:
  /// **'Çekim günü: {day}'**
  String iChingDayLabel(String day);

  /// No description provided for @iChingTrigramsLabel.
  ///
  /// In tr, this message translates to:
  /// **'{lower} altında, {upper} üstte'**
  String iChingTrigramsLabel(String lower, String upper);

  /// No description provided for @baziHeadline.
  ///
  /// In tr, this message translates to:
  /// **'Kaderin Dört Sütunu'**
  String get baziHeadline;

  /// No description provided for @baziChineseSign.
  ///
  /// In tr, this message translates to:
  /// **'Çin burcun: {animal} · {dayMaster}'**
  String baziChineseSign(Object animal, Object dayMaster);

  /// No description provided for @baziFourPillars.
  ///
  /// In tr, this message translates to:
  /// **'Dört Sütun'**
  String get baziFourPillars;

  /// No description provided for @baziPillarHour.
  ///
  /// In tr, this message translates to:
  /// **'SAAT'**
  String get baziPillarHour;

  /// No description provided for @baziPillarDay.
  ///
  /// In tr, this message translates to:
  /// **'GÜN'**
  String get baziPillarDay;

  /// No description provided for @baziPillarMonth.
  ///
  /// In tr, this message translates to:
  /// **'AY'**
  String get baziPillarMonth;

  /// No description provided for @baziPillarYear.
  ///
  /// In tr, this message translates to:
  /// **'YIL'**
  String get baziPillarYear;

  /// No description provided for @baziElementBalance.
  ///
  /// In tr, this message translates to:
  /// **'Element Terazisi'**
  String get baziElementBalance;

  /// No description provided for @baziNourish.
  ///
  /// In tr, this message translates to:
  /// **'Beslenecek element: {elements}'**
  String baziNourish(Object elements);

  /// No description provided for @baziLuckDirectionUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Cinsiyet belirtilmediği için şans sütunlarının yönü hesaplanmadı; iki olası dizi aşağıda.'**
  String get baziLuckDirectionUnknown;

  /// No description provided for @baziLuckCandidatesLabel.
  ///
  /// In tr, this message translates to:
  /// **'Olası iki dizi'**
  String get baziLuckCandidatesLabel;

  /// No description provided for @baziLuckPillars.
  ///
  /// In tr, this message translates to:
  /// **'Şans Sütunları (Da Yun)'**
  String get baziLuckPillars;

  /// No description provided for @baziStrengthTitle.
  ///
  /// In tr, this message translates to:
  /// **'Güç Hükmü'**
  String get baziStrengthTitle;

  /// No description provided for @baziRatioLabel.
  ///
  /// In tr, this message translates to:
  /// **'destek oranı'**
  String get baziRatioLabel;

  /// No description provided for @baziFavorable.
  ///
  /// In tr, this message translates to:
  /// **'Yararlı elementler'**
  String get baziFavorable;

  /// No description provided for @baziUnfavorable.
  ///
  /// In tr, this message translates to:
  /// **'Yüke dönüşenler'**
  String get baziUnfavorable;

  /// No description provided for @baziClimateNote.
  ///
  /// In tr, this message translates to:
  /// **'Mevsim iklimi düzenleyici ister: {element}'**
  String baziClimateNote(String element);

  /// No description provided for @baziBasisTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hükmün dayanağı'**
  String get baziBasisTitle;

  /// No description provided for @baziSrcMonthCommand.
  ///
  /// In tr, this message translates to:
  /// **'Ay komutu'**
  String get baziSrcMonthCommand;

  /// No description provided for @baziSrcRoot.
  ///
  /// In tr, this message translates to:
  /// **'{pillar} dalındaki {stem} kökü'**
  String baziSrcRoot(String pillar, String stem);

  /// No description provided for @baziSrcStem.
  ///
  /// In tr, this message translates to:
  /// **'{pillar} gövdesi {stem}'**
  String baziSrcStem(String pillar, String stem);

  /// No description provided for @baziStarsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yıldızlar (Shen Sha)'**
  String get baziStarsTitle;

  /// No description provided for @baziNoStars.
  ///
  /// In tr, this message translates to:
  /// **'Bu haritada işaretli yıldız yok — yapının kendisi konuşuyor.'**
  String get baziNoStars;

  /// No description provided for @baziLuckStartLabel.
  ///
  /// In tr, this message translates to:
  /// **'İlk dönem: {years} yaş {months} ay ({date})'**
  String baziLuckStartLabel(int years, int months, String date);

  /// No description provided for @baziThisYear.
  ///
  /// In tr, this message translates to:
  /// **'Bu yılın sütunu: {label} ({tenGod})'**
  String baziThisYear(String label, String tenGod);

  /// No description provided for @baziCurrentTag.
  ///
  /// In tr, this message translates to:
  /// **'şimdi'**
  String get baziCurrentTag;

  /// No description provided for @baziAgeRange.
  ///
  /// In tr, this message translates to:
  /// **'{from}–{to} YAŞ'**
  String baziAgeRange(Object from, Object to);

  /// No description provided for @baziFateNote.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'nun kader notu'**
  String get baziFateNote;

  /// No description provided for @defaultUserName.
  ///
  /// In tr, this message translates to:
  /// **'Gezgin'**
  String get defaultUserName;

  /// No description provided for @retrogradeChip.
  ///
  /// In tr, this message translates to:
  /// **'{planet} retro'**
  String retrogradeChip(Object planet);

  /// No description provided for @atlasReadingNote.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'nun okuma notu'**
  String get atlasReadingNote;

  /// No description provided for @notifications.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler'**
  String get notifications;

  /// No description provided for @notifyDaily.
  ///
  /// In tr, this message translates to:
  /// **'Günlük okuma'**
  String get notifyDaily;

  /// No description provided for @notifyDailyBody.
  ///
  /// In tr, this message translates to:
  /// **'Sabahları bugünün gökyüzü hazır olduğunda haber ver.'**
  String get notifyDailyBody;

  /// No description provided for @notifyStreak.
  ///
  /// In tr, this message translates to:
  /// **'Seri hatırlatması'**
  String get notifyStreak;

  /// No description provided for @notifyStreakBody.
  ///
  /// In tr, this message translates to:
  /// **'Akşam, serin kırılmadan önce kısa bir hatırlatma.'**
  String get notifyStreakBody;

  /// No description provided for @notifyFriends.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaş bildirimleri'**
  String get notifyFriends;

  /// No description provided for @notifyFriendsBody.
  ///
  /// In tr, this message translates to:
  /// **'Davetler, kabuller ve tepkiler için haber ver.'**
  String get notifyFriendsBody;

  /// No description provided for @quietHours.
  ///
  /// In tr, this message translates to:
  /// **'Sessiz saatler'**
  String get quietHours;

  /// No description provided for @quietHoursBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu aralıkta bildirim gönderilmez.'**
  String get quietHoursBody;

  /// No description provided for @quietHoursRange.
  ///
  /// In tr, this message translates to:
  /// **'{from}:00 – {to}:00'**
  String quietHoursRange(Object from, Object to);

  /// No description provided for @quietHoursOff.
  ///
  /// In tr, this message translates to:
  /// **'Kapalı'**
  String get quietHoursOff;

  /// No description provided for @quietHoursFrom.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç'**
  String get quietHoursFrom;

  /// No description provided for @quietHoursTo.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş'**
  String get quietHoursTo;

  /// No description provided for @quietHoursRoundedNote.
  ///
  /// In tr, this message translates to:
  /// **'Sessiz saatler tam saate yuvarlandı: {range}'**
  String quietHoursRoundedNote(String range);

  /// No description provided for @deleteAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabı sil'**
  String get deleteAccount;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hesabını silmek üzeresin'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu işlem geri alınamaz. Silinecekler: doğum kaydın, sohbetlerin ve onlardan çıkarılan notlar, günlük girişlerin, eklediğin kişiler, arkadaşlıkların, kullanıcı adın, sana özel üretilmiş tüm okumalar, yapay zeka kullanım kaydın, telefon doğrulama denemelerin ve gönderdiğin geri bildirimler.'**
  String get deleteAccountBody;

  /// No description provided for @deleteAccountKeeps.
  ///
  /// In tr, this message translates to:
  /// **'İkisi bilerek kalır: satın alma ve iade kayıtların (mali belge, beş yıl saklanması zorunlu) ve gönderdiğin şikayet kayıtları (başkalarının güvenliğiyle ilgili).'**
  String get deleteAccountKeeps;

  /// No description provided for @deleteAccountSubscription.
  ///
  /// In tr, this message translates to:
  /// **'Aboneliğin varsa uygulama mağazandan ayrıca iptal etmelisin; hesabı silmek aboneliği durdurmaz.'**
  String get deleteAccountSubscription;

  /// No description provided for @deleteAccountConfirmHint.
  ///
  /// In tr, this message translates to:
  /// **'Onaylamak için SİL yaz'**
  String get deleteAccountConfirmHint;

  /// No description provided for @deleteAccountConfirmWord.
  ///
  /// In tr, this message translates to:
  /// **'SİL'**
  String get deleteAccountConfirmWord;

  /// No description provided for @deleteAccountAction.
  ///
  /// In tr, this message translates to:
  /// **'Hesabımı kalıcı olarak sil'**
  String get deleteAccountAction;

  /// No description provided for @deleteAccountFailed.
  ///
  /// In tr, this message translates to:
  /// **'Hesap silinemedi. Lütfen tekrar dene.'**
  String get deleteAccountFailed;

  /// No description provided for @deleteAccountReauth.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik için tekrar giriş yapman gerekiyor. Çıkış yapıp yeniden giriş yaptıktan sonra bu işlemi tekrarla.'**
  String get deleteAccountReauth;

  /// No description provided for @cancel.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get cancel;

  /// No description provided for @insightDisclaimer.
  ///
  /// In tr, this message translates to:
  /// **'Rytho gerçek gökyüzü hesabına dayanır ama yorum bir öngörü yöntemi değildir. Okumalar içgörü içindir; tıbbi, hukuki veya finansal tavsiye yerine geçmez. 13 yaş ve üzeri içindir.'**
  String get insightDisclaimer;

  /// No description provided for @shareReading.
  ///
  /// In tr, this message translates to:
  /// **'Paylaş'**
  String get shareReading;

  /// No description provided for @shareText.
  ///
  /// In tr, this message translates to:
  /// **'Rytho — doğum haritanı bilen, gökyüzünü her gün izleyen AI astrolog.'**
  String get shareText;

  /// No description provided for @chatShareCardTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rytho ile sohbetimden'**
  String get chatShareCardTitle;

  /// No description provided for @chatSeedFailed.
  ///
  /// In tr, this message translates to:
  /// **'Konu yüklenemedi.'**
  String get chatSeedFailed;

  /// No description provided for @shareCardTagline.
  ///
  /// In tr, this message translates to:
  /// **'gerçek gökyüzü hesabıyla'**
  String get shareCardTagline;

  /// No description provided for @shareFailed.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşım kartı oluşturulamadı.'**
  String get shareFailed;

  /// No description provided for @signInWithApple.
  ///
  /// In tr, this message translates to:
  /// **'Apple ile giriş'**
  String get signInWithApple;

  /// No description provided for @consentPrefix.
  ///
  /// In tr, this message translates to:
  /// **'Devam ederek '**
  String get consentPrefix;

  /// No description provided for @consentAnd.
  ///
  /// In tr, this message translates to:
  /// **' ve '**
  String get consentAnd;

  /// No description provided for @consentSuffix.
  ///
  /// In tr, this message translates to:
  /// **' metinlerini kabul etmiş olursun.'**
  String get consentSuffix;

  /// No description provided for @insightNote.
  ///
  /// In tr, this message translates to:
  /// **'Yorumlar içgörü amaçlıdır; tıbbi, hukuki veya finansal tavsiye değildir.'**
  String get insightNote;

  /// No description provided for @ageConfirm.
  ///
  /// In tr, this message translates to:
  /// **'13 yaşından büyüğüm'**
  String get ageConfirm;

  /// No description provided for @ageRequired.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için yaş beyanını onaylaman gerekiyor.'**
  String get ageRequired;

  /// No description provided for @passwordRuleHint.
  ///
  /// In tr, this message translates to:
  /// **'En az 8 karakter, harf ve rakam içermeli.'**
  String get passwordRuleHint;

  /// No description provided for @passwordTooShort.
  ///
  /// In tr, this message translates to:
  /// **'Şifre en az 8 karakter olmalı.'**
  String get passwordTooShort;

  /// No description provided for @passwordTooSimple.
  ///
  /// In tr, this message translates to:
  /// **'Şifre harf ve rakam (veya sembol) içermeli.'**
  String get passwordTooSimple;

  /// No description provided for @verificationSent.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama bağlantısı {email} adresine gönderildi. Gelen kutunu kontrol et.'**
  String verificationSent(Object email);

  /// No description provided for @useGoogleInstead.
  ///
  /// In tr, this message translates to:
  /// **'Giriş yapılamadı. Şifren hatalı olabilir ya da bu hesap Google/Apple ile açılmış olabilir — aşağıdaki düğmeleri dene.'**
  String get useGoogleInstead;

  /// No description provided for @faceReadingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yüz Okuma'**
  String get faceReadingTitle;

  /// No description provided for @faceGuideNoFace.
  ///
  /// In tr, this message translates to:
  /// **'Yüzünü çerçeveye al'**
  String get faceGuideNoFace;

  /// No description provided for @faceGuideTooFar.
  ///
  /// In tr, this message translates to:
  /// **'Biraz yaklaş'**
  String get faceGuideTooFar;

  /// No description provided for @faceGuideTooClose.
  ///
  /// In tr, this message translates to:
  /// **'Biraz uzaklaş'**
  String get faceGuideTooClose;

  /// No description provided for @faceGuideOffCentre.
  ///
  /// In tr, this message translates to:
  /// **'Yüzünü ortala'**
  String get faceGuideOffCentre;

  /// No description provided for @faceGuideTilted.
  ///
  /// In tr, this message translates to:
  /// **'Başını dik tut'**
  String get faceGuideTilted;

  /// No description provided for @faceGuideReady.
  ///
  /// In tr, this message translates to:
  /// **'Hazır — sabit dur'**
  String get faceGuideReady;

  /// No description provided for @faceGuideForehead.
  ///
  /// In tr, this message translates to:
  /// **'Alnını aç — saçını geriye al'**
  String get faceGuideForehead;

  /// No description provided for @faceScanning.
  ///
  /// In tr, this message translates to:
  /// **'Yüz hatların okunuyor'**
  String get faceScanning;

  /// No description provided for @faceScanNodes.
  ///
  /// In tr, this message translates to:
  /// **'Noktalar yerleşiyor'**
  String get faceScanNodes;

  /// No description provided for @faceScanReading.
  ///
  /// In tr, this message translates to:
  /// **'Firaset ile eşleştiriliyor'**
  String get faceScanReading;

  /// No description provided for @faceRetake.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden çek'**
  String get faceRetake;

  /// No description provided for @faceConsentTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yüz okuma için onayın gerekiyor'**
  String get faceConsentTitle;

  /// No description provided for @faceConsentBody.
  ///
  /// In tr, this message translates to:
  /// **'Yüz okuma, kameradan aldığı kareyi ya da galeriden seçtiğin fotoğrafı CİHAZINDA işler. Görüntü sunucuya gönderilmez, hiçbir yerde saklanmaz ve işlem biter bitmez silinir (galeri yolunda uygulamaya verilen kopya silinir; asıl fotoğrafına dokunulmaz). Sunucuya yalnızca yüz hatlarından türetilen oranlar (ör. alın/çene yükseklik oranı) gider; bu sayılar kişiyi tanımaya yaramaz.'**
  String get faceConsentBody;

  /// No description provided for @faceConsentCheckbox.
  ///
  /// In tr, this message translates to:
  /// **'Yüz görüntümün cihazımda işlenmesine onay veriyorum.'**
  String get faceConsentCheckbox;

  /// No description provided for @faceConsentContinue.
  ///
  /// In tr, this message translates to:
  /// **'Onaylıyorum ve devam et'**
  String get faceConsentContinue;

  /// No description provided for @faceConsentLearnMore.
  ///
  /// In tr, this message translates to:
  /// **'Gizlilik politikasını oku'**
  String get faceConsentLearnMore;

  /// No description provided for @faceCameraDenied.
  ///
  /// In tr, this message translates to:
  /// **'Kamera izni verilmedi. Yüz okuma için kameraya erişim gerekiyor.'**
  String get faceCameraDenied;

  /// No description provided for @faceDetectFailed.
  ///
  /// In tr, this message translates to:
  /// **'Yüz tespit edilemedi. Işığın yeterli olduğundan ve yüzünün çerçevede olduğundan emin ol.'**
  String get faceDetectFailed;

  /// No description provided for @faceReadingHint.
  ///
  /// In tr, this message translates to:
  /// **'Gelenek der ki: tek bir belirti hüküm vermez. Aşağıdaki okuma bir eğilimdir, kader değildir.'**
  String get faceReadingHint;

  /// No description provided for @faceReadingLockedBody.
  ///
  /// In tr, this message translates to:
  /// **'Yüz hatlarından mizaç okuması Rytho+ ile açılır. Görüntü cihazında işlenir, hiçbir yere gönderilmez.'**
  String get faceReadingLockedBody;

  /// No description provided for @faceGalleryButton.
  ///
  /// In tr, this message translates to:
  /// **'Galeriden seç'**
  String get faceGalleryButton;

  /// No description provided for @faceLensButton.
  ///
  /// In tr, this message translates to:
  /// **'Kamerayı çevir'**
  String get faceLensButton;

  /// No description provided for @faceStillAnalyzing.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf inceleniyor…'**
  String get faceStillAnalyzing;

  /// No description provided for @faceStillNoFace.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğrafta yüz bulunamadı. Önden, iyi aydınlatılmış bir fotoğraf dene.'**
  String get faceStillNoFace;

  /// No description provided for @faceStillNoLandmarks.
  ///
  /// In tr, this message translates to:
  /// **'Yüz hatları seçilemedi. Yüzün tam göründüğü, önden bir fotoğraf dene.'**
  String get faceStillNoLandmarks;

  /// No description provided for @faceStillSingleFrameNote.
  ///
  /// In tr, this message translates to:
  /// **'Bu okuma tek bir fotoğraf karesinden ölçüldü; canlı çekim daha kararlı sonuç verir.'**
  String get faceStillSingleFrameNote;

  /// No description provided for @faceWaitStage1.
  ///
  /// In tr, this message translates to:
  /// **'Oranlar geleneğin ölçüleriyle karşılaştırılıyor…'**
  String get faceWaitStage1;

  /// No description provided for @faceWaitStage2.
  ///
  /// In tr, this message translates to:
  /// **'Firaset kaynakları taranıyor…'**
  String get faceWaitStage2;

  /// No description provided for @faceWaitStage3.
  ///
  /// In tr, this message translates to:
  /// **'Okuman yazılıyor…'**
  String get faceWaitStage3;

  /// No description provided for @faceConsentSetting.
  ///
  /// In tr, this message translates to:
  /// **'Yüz okuma rızası'**
  String get faceConsentSetting;

  /// No description provided for @faceConsentSettingOn.
  ///
  /// In tr, this message translates to:
  /// **'Verildi. Görüntü cihazında işlenir, saklanmaz.'**
  String get faceConsentSettingOn;

  /// No description provided for @faceConsentSettingOff.
  ///
  /// In tr, this message translates to:
  /// **'Verilmedi. Yüz okumaya girdiğinde sorulur.'**
  String get faceConsentSettingOff;

  /// No description provided for @faceConsentWithdrawTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rızayı geri al'**
  String get faceConsentWithdrawTitle;

  /// No description provided for @faceConsentWithdrawBody.
  ///
  /// In tr, this message translates to:
  /// **'Yüz okuma rızan geri alınacak ve şimdiye kadar üretilmiş firaset okumaların silinecek. Diğer okumaların (natal, BaZi, günlük) etkilenmez.'**
  String get faceConsentWithdrawBody;

  /// No description provided for @faceConsentWithdrawConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Geri al ve sil'**
  String get faceConsentWithdrawConfirm;

  /// No description provided for @faceConsentWithdrawn.
  ///
  /// In tr, this message translates to:
  /// **'Rıza geri alındı, {count} okuma silindi.'**
  String faceConsentWithdrawn(int count);

  /// No description provided for @faceOpenSettings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarları aç'**
  String get faceOpenSettings;

  /// No description provided for @faceCameraDeniedHint.
  ///
  /// In tr, this message translates to:
  /// **'İzni reddettiysen, telefon ayarlarından Rytho için kamera iznini açıp buraya dönebilirsin.'**
  String get faceCameraDeniedHint;

  /// No description provided for @birthHexagramWaitStage1.
  ///
  /// In tr, this message translates to:
  /// **'Doğum anındaki Güneş konumlanıyor'**
  String get birthHexagramWaitStage1;

  /// No description provided for @birthHexagramWaitStage2.
  ///
  /// In tr, this message translates to:
  /// **'Kapı ve çizgi okunuyor'**
  String get birthHexagramWaitStage2;

  /// No description provided for @readingCardReadMore.
  ///
  /// In tr, this message translates to:
  /// **'Okumaya devam et'**
  String get readingCardReadMore;

  /// No description provided for @save.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In tr, this message translates to:
  /// **'Düzenle'**
  String get edit;

  /// No description provided for @birthRecordRowSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Tüm okumaların temeli'**
  String get birthRecordRowSubtitle;

  /// No description provided for @languageAndSounds.
  ///
  /// In tr, this message translates to:
  /// **'Dil ve sesler'**
  String get languageAndSounds;

  /// No description provided for @addFriendNeedsUsername.
  ///
  /// In tr, this message translates to:
  /// **'Önce bir kullanıcı adı almalısın — hemen aşağıdaki panelden seçebilirsin.'**
  String get addFriendNeedsUsername;

  /// No description provided for @newConversation.
  ///
  /// In tr, this message translates to:
  /// **'Yeni konu'**
  String get newConversation;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rytho ile konuş'**
  String get chatEmptyTitle;

  /// No description provided for @contactMatchSetting.
  ///
  /// In tr, this message translates to:
  /// **'Rehberimden arkadaş öner'**
  String get contactMatchSetting;

  /// No description provided for @contactMatchSettingBody.
  ///
  /// In tr, this message translates to:
  /// **'Numaralar telefonunda özetlenir; rehberin sunucuya gönderilmez. Yalnızca ikiniz de bu ayarı açtıysanız birbirinizi görürsünüz.'**
  String get contactMatchSettingBody;

  /// No description provided for @contactMatchPhoneTitle.
  ///
  /// In tr, this message translates to:
  /// **'Önce numaranı doğrula'**
  String get contactMatchPhoneTitle;

  /// No description provided for @contactMatchPhoneBody.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşme telefon numarası üzerinden çalışır. Numaranı doğruladığında tanıdıkların seni bulabilir, sen de onları görebilirsin.'**
  String get contactMatchPhoneBody;

  /// No description provided for @contactMatchVerifyPhone.
  ///
  /// In tr, this message translates to:
  /// **'Numaranı doğrula'**
  String get contactMatchVerifyPhone;

  /// No description provided for @contactMatchPermTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rehber izni gerekiyor'**
  String get contactMatchPermTitle;

  /// No description provided for @contactMatchPermBody.
  ///
  /// In tr, this message translates to:
  /// **'Tanıdıklarını bulmak için rehber okuma izni gerekli. İzni reddettiysen telefonunun Ayarlar → Uygulamalar → Rytho bölümünden açabilirsin.'**
  String get contactMatchPermBody;

  /// No description provided for @contactMatchRetry.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar dene'**
  String get contactMatchRetry;

  /// No description provided for @contactMatchEmptyBody.
  ///
  /// In tr, this message translates to:
  /// **'Rehberinden kimse henüz görünmüyor. Eşleşme için arkadaşının da Rytho\'da numarasını doğrulamış ve rehber eşleşmesini açmış olması gerekir.'**
  String get contactMatchEmptyBody;

  /// No description provided for @contactsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rehberin'**
  String get contactsTitle;

  /// No description provided for @contactsSearchHint.
  ///
  /// In tr, this message translates to:
  /// **'Rehberinde ara'**
  String get contactsSearchHint;

  /// No description provided for @contactsActiveSection.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamada'**
  String get contactsActiveSection;

  /// No description provided for @contactsInviteSection.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'da görünmüyor'**
  String get contactsInviteSection;

  /// No description provided for @contactsInviteFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Numarasını doğrulamamış arkadaşların da burada görünebilir.'**
  String get contactsInviteFootnote;

  /// No description provided for @contactsInvite.
  ///
  /// In tr, this message translates to:
  /// **'Davet et'**
  String get contactsInvite;

  /// No description provided for @contactsAlreadyFriend.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaşın'**
  String get contactsAlreadyFriend;

  /// No description provided for @contactsNoSearchResult.
  ///
  /// In tr, this message translates to:
  /// **'Aramayla eşleşen kişi yok.'**
  String get contactsNoSearchResult;

  /// No description provided for @contactsInviteNeedsUsername.
  ///
  /// In tr, this message translates to:
  /// **'Davet için önce bir kullanıcı adı al.'**
  String get contactsInviteNeedsUsername;

  /// No description provided for @inviteShareMessage.
  ///
  /// In tr, this message translates to:
  /// **'Seni Rytho\'ya davet ediyorum — kişisel kozmik zekân. Beni buradan ekleyebilirsin: {link}'**
  String inviteShareMessage(Object link);

  /// No description provided for @contactsFindEntry.
  ///
  /// In tr, this message translates to:
  /// **'Rehberinden arkadaş bul'**
  String get contactsFindEntry;

  /// No description provided for @contactsFindActive.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişi uygulamada'**
  String contactsFindActive(int count);

  /// No description provided for @contactsFindEnable.
  ///
  /// In tr, this message translates to:
  /// **'Rehber eşleşmesini aç'**
  String get contactsFindEnable;

  /// No description provided for @contactsFindVerifyPhone.
  ///
  /// In tr, this message translates to:
  /// **'Bulmak için numaranı doğrula'**
  String get contactsFindVerifyPhone;

  /// No description provided for @phoneSectionLabel.
  ///
  /// In tr, this message translates to:
  /// **'TELEFON'**
  String get phoneSectionLabel;

  /// No description provided for @phoneNotLinked.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulanmış numara yok'**
  String get phoneNotLinked;

  /// No description provided for @phoneVerifyAction.
  ///
  /// In tr, this message translates to:
  /// **'Doğrula'**
  String get phoneVerifyAction;

  /// No description provided for @phoneChangeAction.
  ///
  /// In tr, this message translates to:
  /// **'Değiştir'**
  String get phoneChangeAction;

  /// No description provided for @phoneVerifyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Telefonunu doğrula'**
  String get phoneVerifyTitle;

  /// No description provided for @phoneVerifyBody.
  ///
  /// In tr, this message translates to:
  /// **'Numaran SMS ile doğrulanır ve hesabına bağlanır. Rehber eşleşmesini açarsan arkadaşların seni bu numarayla bulabilir; numaran hiçbir zaman açık şekilde saklanmaz ve kimseyle paylaşılmaz.'**
  String get phoneVerifyBody;

  /// No description provided for @phoneFieldLabel.
  ///
  /// In tr, this message translates to:
  /// **'Telefon numarası'**
  String get phoneFieldLabel;

  /// No description provided for @phoneSendCode.
  ///
  /// In tr, this message translates to:
  /// **'Kod gönder'**
  String get phoneSendCode;

  /// No description provided for @phoneCodeLabel.
  ///
  /// In tr, this message translates to:
  /// **'SMS kodu'**
  String get phoneCodeLabel;

  /// No description provided for @phoneConfirmCode.
  ///
  /// In tr, this message translates to:
  /// **'Doğrula'**
  String get phoneConfirmCode;

  /// No description provided for @phoneCodeSentTo.
  ///
  /// In tr, this message translates to:
  /// **'{number} numarasına kod gönderildi.'**
  String phoneCodeSentTo(String number);

  /// No description provided for @phoneWillSendTo.
  ///
  /// In tr, this message translates to:
  /// **'Kod {number} numarasına gönderilecek.'**
  String phoneWillSendTo(String number);

  /// No description provided for @phoneResend.
  ///
  /// In tr, this message translates to:
  /// **'Kodu tekrar gönder'**
  String get phoneResend;

  /// No description provided for @phoneResendIn.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar gönder ({seconds} sn)'**
  String phoneResendIn(int seconds);

  /// No description provided for @phoneNoCodeHelp.
  ///
  /// In tr, this message translates to:
  /// **'SMS hâlâ gelmediyse operatör gecikmesi olabilir. Numaranı kontrol et, kodu tekrar gönder ya da bu adımı atlayıp sonra Profil → Giriş yöntemleri\'nden doğrula.'**
  String get phoneNoCodeHelp;

  /// No description provided for @phoneRegionUnsupported.
  ///
  /// In tr, this message translates to:
  /// **'Şu an yalnız +90 ile başlayan numaralara kod gönderebiliyoruz.'**
  String get phoneRegionUnsupported;

  /// No description provided for @phoneChangeNumber.
  ///
  /// In tr, this message translates to:
  /// **'Numarayı değiştir'**
  String get phoneChangeNumber;

  /// No description provided for @phoneLinkedDone.
  ///
  /// In tr, this message translates to:
  /// **'Telefonun doğrulandı.'**
  String get phoneLinkedDone;

  /// No description provided for @phoneInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Numarayı ülke koduyla yaz (örn. +905xxxxxxxxx).'**
  String get phoneInvalid;

  /// No description provided for @phoneCodeWrong.
  ///
  /// In tr, this message translates to:
  /// **'Kod yanlış görünüyor, tekrar dene.'**
  String get phoneCodeWrong;

  /// No description provided for @phoneTakenError.
  ///
  /// In tr, this message translates to:
  /// **'Bu numara başka bir hesaba bağlı.'**
  String get phoneTakenError;

  /// No description provided for @phoneTooManyTries.
  ///
  /// In tr, this message translates to:
  /// **'Çok fazla deneme yapıldı. Biraz sonra tekrar dene.'**
  String get phoneTooManyTries;

  /// No description provided for @deviceConflictTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın başka bir cihazda açıldı'**
  String get deviceConflictTitle;

  /// No description provided for @deviceConflictBody.
  ///
  /// In tr, this message translates to:
  /// **'{platform} cihazında {time} itibarıyla giriş yapıldı. Rytho+ aynı anda tek cihazda kullanılabilir — burada devam etmek için \"Bu cihazda kullan\"a dokun.'**
  String deviceConflictBody(String platform, String time);

  /// No description provided for @deviceConflictUseHere.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihazda kullan'**
  String get deviceConflictUseHere;

  /// No description provided for @deviceConflictClaimFailed.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz devralınamadı — bağlantını kontrol edip tekrar dene.'**
  String get deviceConflictClaimFailed;

  /// No description provided for @forceUpdateTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni sürüm gerekli'**
  String get forceUpdateTitle;

  /// No description provided for @forceUpdateBody.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'nun bu sürümü artık desteklenmiyor. Devam etmek için uygulamayı güncelle — yıldızlar bekliyor.'**
  String get forceUpdateBody;

  /// No description provided for @forceUpdateAction.
  ///
  /// In tr, this message translates to:
  /// **'Mağazada güncelle'**
  String get forceUpdateAction;

  /// No description provided for @forceUpdateStoreFailed.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza açılamadı — uygulama mağazanda \"Rytho\" diye arat.'**
  String get forceUpdateStoreFailed;

  /// No description provided for @signInMethodsRow.
  ///
  /// In tr, this message translates to:
  /// **'Giriş yöntemleri'**
  String get signInMethodsRow;

  /// No description provided for @signInMethodsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Giriş yöntemleri'**
  String get signInMethodsTitle;

  /// No description provided for @signInMethodsBody.
  ///
  /// In tr, this message translates to:
  /// **'Hesabına birden fazla giriş yolu bağlayabilirsin: hangi yöntemle girersen gir aynı hesaba ulaşırsın.'**
  String get signInMethodsBody;

  /// No description provided for @providerPhone.
  ///
  /// In tr, this message translates to:
  /// **'Telefon'**
  String get providerPhone;

  /// No description provided for @linkAction.
  ///
  /// In tr, this message translates to:
  /// **'Bağla'**
  String get linkAction;

  /// No description provided for @linkAlreadyLinked.
  ///
  /// In tr, this message translates to:
  /// **'Bu giriş yöntemi zaten hesabına bağlı.'**
  String get linkAlreadyLinked;

  /// No description provided for @linkCredentialInUse.
  ///
  /// In tr, this message translates to:
  /// **'Bu kimlik başka bir hesaba bağlı. Önce o hesaptan çözülmesi gerekir.'**
  String get linkCredentialInUse;

  /// No description provided for @linkRequiresRecentLogin.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik için yakın zamanlı giriş gerekiyor: çıkış yapıp yeniden girdikten sonra tekrar dene.'**
  String get linkRequiresRecentLogin;

  /// No description provided for @linkPasswordDone.
  ///
  /// In tr, this message translates to:
  /// **'Şifre kaydedildi. Artık e-posta ve şifreyle de girebilirsin'**
  String get linkPasswordDone;

  /// No description provided for @linkGoogleDone.
  ///
  /// In tr, this message translates to:
  /// **'Google hesabın bağlandı ✨'**
  String get linkGoogleDone;

  /// No description provided for @setPasswordSection.
  ///
  /// In tr, this message translates to:
  /// **'ŞİFRE OLUŞTUR'**
  String get setPasswordSection;

  /// No description provided for @setPasswordBody.
  ///
  /// In tr, this message translates to:
  /// **'Bir e-posta ve şifre belirlersen Google/Apple olmadan da giriş yapabilirsin.'**
  String get setPasswordBody;

  /// No description provided for @setPasswordAction.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi kaydet'**
  String get setPasswordAction;

  /// No description provided for @changePasswordSection.
  ///
  /// In tr, this message translates to:
  /// **'ŞİFREYİ DEĞİŞTİR'**
  String get changePasswordSection;

  /// No description provided for @changePasswordBody.
  ///
  /// In tr, this message translates to:
  /// **'Yeni şifreni belirle. Değişiklik anında geçerli olur.'**
  String get changePasswordBody;

  /// No description provided for @changePasswordAction.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi değiştir'**
  String get changePasswordAction;

  /// No description provided for @purchaseItemUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün şu anda mağazada sunulmuyor. Biraz sonra tekrar dene.'**
  String get purchaseItemUnavailable;

  /// No description provided for @purchaseStoreProblem.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza şu an satın almayı tamamlayamadı. Birkaç dakika sonra tekrar dene.'**
  String get purchaseStoreProblem;

  /// No description provided for @tokenStoreTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kredi Mağazası'**
  String get tokenStoreTitle;

  /// No description provided for @tokenBalanceLabel.
  ///
  /// In tr, this message translates to:
  /// **'BAKİYEN'**
  String get tokenBalanceLabel;

  /// No description provided for @tokenUnit.
  ///
  /// In tr, this message translates to:
  /// **'kredi'**
  String get tokenUnit;

  /// No description provided for @tokenAllowanceRow.
  ///
  /// In tr, this message translates to:
  /// **'Aylık hak (dönem sonunda yenilenir)'**
  String get tokenAllowanceRow;

  /// No description provided for @tokenPurchasedRow.
  ///
  /// In tr, this message translates to:
  /// **'Satın alınan (aya devreder)'**
  String get tokenPurchasedRow;

  /// No description provided for @tokenRolloverNote.
  ///
  /// In tr, this message translates to:
  /// **'Aylık hakkın dönem sonunda yenilenir ve devretmez; satın aldığın krediler hiç yanmaz.'**
  String get tokenRolloverNote;

  /// No description provided for @tokenPacksHeader.
  ///
  /// In tr, this message translates to:
  /// **'Paketler'**
  String get tokenPacksHeader;

  /// No description provided for @tokenPackAmount.
  ///
  /// In tr, this message translates to:
  /// **'{count} kredi'**
  String tokenPackAmount(int count);

  /// No description provided for @storeBuyWithPrice.
  ///
  /// In tr, this message translates to:
  /// **'Satın al — {price}'**
  String storeBuyWithPrice(String price);

  /// No description provided for @pricePerCredit.
  ///
  /// In tr, this message translates to:
  /// **'{price} / kredi'**
  String pricePerCredit(String price);

  /// No description provided for @tokenCost.
  ///
  /// In tr, this message translates to:
  /// **'{count} kredi'**
  String tokenCost(int count);

  /// No description provided for @purchasePackRefreshing.
  ///
  /// In tr, this message translates to:
  /// **'Satın alma alındı; bakiyen yenileniyor.'**
  String get purchasePackRefreshing;

  /// No description provided for @purchaseAlreadyOwnedSubscription.
  ///
  /// In tr, this message translates to:
  /// **'Bu hesapta zaten etkin bir abonelik var — satın alımların geri yükleniyor…'**
  String get purchaseAlreadyOwnedSubscription;

  /// No description provided for @tokenPurchaseDone.
  ///
  /// In tr, this message translates to:
  /// **'Paket yüklendi. İyi okumalar ✨'**
  String get tokenPurchaseDone;

  /// No description provided for @tokenPacksUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'Paketler şu an listelenemiyor'**
  String get tokenPacksUnavailable;

  /// No description provided for @tokenPacksUnavailableBody.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza bağlantısı kurulamadı. Biraz sonra tekrar dene.'**
  String get tokenPacksUnavailableBody;

  /// No description provided for @tokenPacksPlusOnlyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Paketler Rytho+ abonelerine özel'**
  String get tokenPacksPlusOnlyTitle;

  /// No description provided for @tokenPacksPlusOnlyBody.
  ///
  /// In tr, this message translates to:
  /// **'Kredinin açtığı okumaların tamamı Rytho+ ile geliyor. Abonelik olmadan paket almak, sana karşılığını henüz veremeyeceğimiz bir bakiye bırakırdı; bu yüzden paketleri burada göstermiyoruz.'**
  String get tokenPacksPlusOnlyBody;

  /// No description provided for @tokenPacksSeePlus.
  ///
  /// In tr, this message translates to:
  /// **'Rytho+\'a bak'**
  String get tokenPacksSeePlus;

  /// No description provided for @tokenFreeTierWarnTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz katmanda kredi yalnızca sohbette harcanır'**
  String get tokenFreeTierWarnTitle;

  /// No description provided for @tokenFreeTierWarnBody.
  ///
  /// In tr, this message translates to:
  /// **'1 kredi = 1 sohbet mesajı. I Ching, ikili dinamik, derin raporlar ve yüz okuma Rytho+ aboneliğine dahildir; kredi onları açmaz. Aldığın krediler yanmaz — sonradan abone olursan hepsini kullanabilirsin.'**
  String get tokenFreeTierWarnBody;

  /// No description provided for @tokenCostsNote.
  ///
  /// In tr, this message translates to:
  /// **'Sohbet mesajı {chat} · I Ching {iching} · ikili dinamik {dyad} · derin raporlar ve yüz okuma {deep} kredi. Kredi yalnız yeni bir rapor üretilirken düşer; hazır duran rapora yeniden bakmak hiç düşürmez.'**
  String tokenCostsNote(int chat, int iching, int dyad, int deep);

  /// No description provided for @chatCostNote.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj başına {count} kredi'**
  String chatCostNote(int count);

  /// No description provided for @costConfirmTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu okuma {count} kredi'**
  String costConfirmTitle(int count);

  /// No description provided for @costConfirmBody.
  ///
  /// In tr, this message translates to:
  /// **'Hazır duran okumaya yeniden bakmak düşürmez; yeni üretim düşer.'**
  String get costConfirmBody;

  /// No description provided for @costConfirmContinue.
  ///
  /// In tr, this message translates to:
  /// **'Devam'**
  String get costConfirmContinue;

  /// No description provided for @costConfirmCancel.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get costConfirmCancel;

  /// No description provided for @tokenBalanceChip.
  ///
  /// In tr, this message translates to:
  /// **'{count} kredi'**
  String tokenBalanceChip(int count);

  /// No description provided for @atlasTraitsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Element dağılımın'**
  String get atlasTraitsSubtitle;

  /// No description provided for @atlasPlanetsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Doğduğun andaki konumlar'**
  String get atlasPlanetsSubtitle;

  /// No description provided for @atlasFullReport.
  ///
  /// In tr, this message translates to:
  /// **'Tam rapor'**
  String get atlasFullReport;

  /// No description provided for @atlasFullReportSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'nun okuması'**
  String get atlasFullReportSubtitle;

  /// No description provided for @atlasAspectsCount.
  ///
  /// In tr, this message translates to:
  /// **'{count, plural, =0{Açı yok} =1{1 açı} other{{count} açı}}'**
  String atlasAspectsCount(int count);

  /// No description provided for @retrogradeCount.
  ///
  /// In tr, this message translates to:
  /// **'{count, plural, =1{1 gezegen retro} other{{count} gezegen retro}}'**
  String retrogradeCount(int count);

  /// No description provided for @genericError.
  ///
  /// In tr, this message translates to:
  /// **'Bir şeyler ters gitti. Tekrar dener misin?'**
  String get genericError;

  /// No description provided for @birthRecordEditBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu bilgiler haritanın temeli: günlük okuman, natal raporun ve sohbetin gördüğü her şey buradan hesaplanıyor. Değiştirirsen okumaların yeniden hesaplanır.'**
  String get birthRecordEditBody;

  /// No description provided for @birthCityEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Doğum şehri boş olamaz.'**
  String get birthCityEmpty;

  /// No description provided for @birthRecordSaved.
  ///
  /// In tr, this message translates to:
  /// **'Doğum kaydın güncellendi. Okumaların yeni haritana göre hesaplanacak.'**
  String get birthRecordSaved;

  /// No description provided for @birthRecordSavedNoChart.
  ///
  /// In tr, this message translates to:
  /// **'Doğum kaydın güncellendi ama haritan şu an hesaplanamadı. Burç rozetlerin bağlantı gelince geri dönecek.'**
  String get birthRecordSavedNoChart;

  /// No description provided for @onboardingSavedNoChart.
  ///
  /// In tr, this message translates to:
  /// **'Doğum bilgin kaydedildi ama haritan şu an hesaplanamadı. Burç rozetlerin bağlantı gelince gelecek.'**
  String get onboardingSavedNoChart;

  /// No description provided for @accountSection.
  ///
  /// In tr, this message translates to:
  /// **'Hesap'**
  String get accountSection;

  /// No description provided for @accountSaved.
  ///
  /// In tr, this message translates to:
  /// **'Hesap bilgilerin güncellendi.'**
  String get accountSaved;

  /// No description provided for @displayNameEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Adın boş olamaz.'**
  String get displayNameEmpty;

  /// No description provided for @displayNameTooLong.
  ///
  /// In tr, this message translates to:
  /// **'Adın en çok {count} karakter olabilir.'**
  String displayNameTooLong(int count);

  /// No description provided for @usernameChangeNote.
  ///
  /// In tr, this message translates to:
  /// **'Değiştirirsen eski kullanıcı adın serbest kalır ve başkası alabilir.'**
  String get usernameChangeNote;

  /// No description provided for @emailChangeNote.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresin oturumunun anahtarı; değiştirmek için destekle iletişime geç.'**
  String get emailChangeNote;

  /// No description provided for @emailNotVerified.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresin henüz doğrulanmadı.'**
  String get emailNotVerified;

  /// No description provided for @emailVerifyResend.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama e-postasını gönder'**
  String get emailVerifyResend;

  /// No description provided for @emailVerifySent.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama e-postası gönderildi — spam klasörünü de kontrol et.'**
  String get emailVerifySent;

  /// No description provided for @onboardingSwitchAccount.
  ///
  /// In tr, this message translates to:
  /// **'Farklı hesapla gir'**
  String get onboardingSwitchAccount;

  /// No description provided for @signalsSection.
  ///
  /// In tr, this message translates to:
  /// **'Bugün gökyüzünde senin için'**
  String get signalsSection;

  /// No description provided for @signalWhy.
  ///
  /// In tr, this message translates to:
  /// **'Neye dayanıyor?'**
  String get signalWhy;

  /// No description provided for @signalAsk.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'ya sor'**
  String get signalAsk;

  /// No description provided for @atlasAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Atlas sayfamdaki okumalara bakıyorum. Bugün için en çok hangisine eğilmeliyim?'**
  String get atlasAskPrefill;

  /// No description provided for @faceAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Yüz okumamı gördüm. Bugünkü gökyüzüyle birlikte bana ne söylüyor?'**
  String get faceAskPrefill;

  /// No description provided for @planetsAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Gezegenlerimin yerleşimine bakıyorum. En belirleyici olanını bana anlatır mısın?'**
  String get planetsAskPrefill;

  /// No description provided for @traitsAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Kişilik özelliklerime bakıyorum. Hangisi bugünlerde daha öne çıkıyor?'**
  String get traitsAskPrefill;

  /// No description provided for @aspectsAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Haritamdaki açılara bakıyorum. En çok hangisini hissederim?'**
  String get aspectsAskPrefill;

  /// No description provided for @pointAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'{name} yerleşimim hakkında konuşalım. Bu bana nasıl yansıyor?'**
  String pointAskPrefill(String name);

  /// No description provided for @aspectAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Haritamdaki \"{label}\" açısı hakkında konuşalım. Bunu nasıl yaşarım?'**
  String aspectAskPrefill(String label);

  /// No description provided for @askAboutFriendPrefill.
  ///
  /// In tr, this message translates to:
  /// **'{name} ile aramızdaki dinamik hakkında konuşalım.'**
  String askAboutFriendPrefill(String name);

  /// No description provided for @signalAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Bugün ana ekranımda şu sinyal var: \"{card}\" Bunu benim için biraz açar mısın?'**
  String signalAskPrefill(String card);

  /// No description provided for @signalUpcoming.
  ///
  /// In tr, this message translates to:
  /// **'Önemli gün: {date}'**
  String signalUpcoming(String date);

  /// No description provided for @basisSheetTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu sinyal nereden geliyor?'**
  String get basisSheetTitle;

  /// No description provided for @basisSky.
  ///
  /// In tr, this message translates to:
  /// **'Gökyüzünde'**
  String get basisSky;

  /// No description provided for @basisNatal.
  ///
  /// In tr, this message translates to:
  /// **'Haritanda'**
  String get basisNatal;

  /// No description provided for @basisAspect.
  ///
  /// In tr, this message translates to:
  /// **'Açı'**
  String get basisAspect;

  /// No description provided for @basisOrb.
  ///
  /// In tr, this message translates to:
  /// **'Orb (ölçülen)'**
  String get basisOrb;

  /// No description provided for @basisMovement.
  ///
  /// In tr, this message translates to:
  /// **'Hareket'**
  String get basisMovement;

  /// No description provided for @basisExact.
  ///
  /// In tr, this message translates to:
  /// **'Kesinleşme'**
  String get basisExact;

  /// No description provided for @basisHouse.
  ///
  /// In tr, this message translates to:
  /// **'{house}. ev'**
  String basisHouse(int house);

  /// No description provided for @basisFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Konumlar efemeristen gelir, açı ve orb ölçülür; yorum bu ölçümlerin üzerine kurulur.'**
  String get basisFootnote;

  /// No description provided for @relationshipOpen.
  ///
  /// In tr, this message translates to:
  /// **'İlişkiyi incele'**
  String get relationshipOpen;

  /// No description provided for @relationshipOpenSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'İki haritanız nerede kolaylaşıyor, nerede emek istiyor'**
  String get relationshipOpenSubtitle;

  /// No description provided for @relationshipTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sen & {name}'**
  String relationshipTitle(String name);

  /// No description provided for @relationshipBirthMissing.
  ///
  /// In tr, this message translates to:
  /// **'Bu okuma için ikinizin de doğum kaydı gerekiyor. Arkadaşın kaydını tamamladığında burası dolacak.'**
  String get relationshipBirthMissing;

  /// No description provided for @relationshipBasisTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu eksenin dayanağı'**
  String get relationshipBasisTitle;

  /// No description provided for @calendarWhyDate.
  ///
  /// In tr, this message translates to:
  /// **'Bu tarih neden önemli?'**
  String get calendarWhyDate;

  /// No description provided for @diaryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Günlüğüm'**
  String get diaryTitle;

  /// No description provided for @profileDiaryRow.
  ///
  /// In tr, this message translates to:
  /// **'Günlüğüm'**
  String get profileDiaryRow;

  /// No description provided for @diaryHint.
  ///
  /// In tr, this message translates to:
  /// **'Bugün ne oldu? Tek cümle yeter.'**
  String get diaryHint;

  /// No description provided for @diarySave.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get diarySave;

  /// No description provided for @diaryEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz giriş yok. Önemli anları tek cümleyle bırak — sohbette \"son ayda ne oldu?\" diye sorduğunda Rytho bu kayıtları o günlerin gökyüzüyle yan yana koyar.'**
  String get diaryEmpty;

  /// No description provided for @diaryDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Giriş silindi.'**
  String get diaryDeleted;

  /// No description provided for @diaryFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Girişlerin yalnız sana görünür ve Rytho\'nun sohbet hafızasına girer. Hesabını silersen hepsi silinir.'**
  String get diaryFootnote;

  /// No description provided for @diaryDeleteTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu girişi silmek istiyor musun?'**
  String get diaryDeleteTitle;

  /// No description provided for @profileSectionAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap'**
  String get profileSectionAccount;

  /// No description provided for @profileSectionPrefs.
  ///
  /// In tr, this message translates to:
  /// **'Tercihler'**
  String get profileSectionPrefs;

  /// No description provided for @feedbackTitle.
  ///
  /// In tr, this message translates to:
  /// **'Geri bildirim'**
  String get feedbackTitle;

  /// No description provided for @feedbackLead.
  ///
  /// In tr, this message translates to:
  /// **'Hata, öneri ya da aklına takılan bir şey — doğrudan bize ulaşır.'**
  String get feedbackLead;

  /// No description provided for @feedbackTypeBug.
  ///
  /// In tr, this message translates to:
  /// **'Hata 🐞'**
  String get feedbackTypeBug;

  /// No description provided for @feedbackTypeSuggestion.
  ///
  /// In tr, this message translates to:
  /// **'Öneri 💡'**
  String get feedbackTypeSuggestion;

  /// No description provided for @feedbackTypeOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get feedbackTypeOther;

  /// No description provided for @feedbackScreenLabel.
  ///
  /// In tr, this message translates to:
  /// **'Hangi ekran?'**
  String get feedbackScreenLabel;

  /// No description provided for @feedbackScreenChat.
  ///
  /// In tr, this message translates to:
  /// **'Sohbet'**
  String get feedbackScreenChat;

  /// No description provided for @feedbackScreenOracle.
  ///
  /// In tr, this message translates to:
  /// **'Kehanet'**
  String get feedbackScreenOracle;

  /// No description provided for @feedbackScreenOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get feedbackScreenOther;

  /// No description provided for @feedbackHint.
  ///
  /// In tr, this message translates to:
  /// **'Ne oldu, ne bekliyordun? Kısa da olur.'**
  String get feedbackHint;

  /// No description provided for @feedbackPrivacy.
  ///
  /// In tr, this message translates to:
  /// **'Sürüm, cihaz ve dil bilgisi otomatik eklenir. Mesajın, yanıtını sana iletebilmemiz için hesabınla birlikte kaydedilir.'**
  String get feedbackPrivacy;

  /// No description provided for @feedbackSend.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get feedbackSend;

  /// No description provided for @feedbackThanksTitle.
  ///
  /// In tr, this message translates to:
  /// **'Teşekkürler — okuyoruz.'**
  String get feedbackThanksTitle;

  /// No description provided for @feedbackThanksBody.
  ///
  /// In tr, this message translates to:
  /// **'Yanıtımızı bildirim olarak alırsın.'**
  String get feedbackThanksBody;

  /// No description provided for @feedbackClose.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get feedbackClose;

  /// No description provided for @feedbackTooShort.
  ///
  /// In tr, this message translates to:
  /// **'En az 10 karakter yaz.'**
  String get feedbackTooShort;

  /// No description provided for @profileFeedback.
  ///
  /// In tr, this message translates to:
  /// **'Geri bildirim gönder'**
  String get profileFeedback;

  /// No description provided for @feedbackReportThisScreen.
  ///
  /// In tr, this message translates to:
  /// **'Bu ekranı bildir'**
  String get feedbackReportThisScreen;

  /// No description provided for @removeFriendConfirmTitle.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaşlıktan çıkar'**
  String get removeFriendConfirmTitle;

  /// No description provided for @removeFriendConfirmBody.
  ///
  /// In tr, this message translates to:
  /// **'{name} listenden çıkar; ortak okumalar kapanır. İstersen yeniden ekleyebilirsin.'**
  String removeFriendConfirmBody(String name);

  /// No description provided for @blockUserConfirmTitle.
  ///
  /// In tr, this message translates to:
  /// **'Engelle'**
  String get blockUserConfirmTitle;

  /// No description provided for @blockUserConfirmBody.
  ///
  /// In tr, this message translates to:
  /// **'{name} seni bulamaz ve davet gönderemez. Bunu Çevrem ayarlarından geri alabilirsin.'**
  String blockUserConfirmBody(String name);

  /// No description provided for @peopleSlotsOver.
  ///
  /// In tr, this message translates to:
  /// **'Kontenjanın {limit}; {used} kişi kayıtlı — yeni kişi eklemek için birini çıkar.'**
  String peopleSlotsOver(int limit, int used);

  /// No description provided for @inviteNeedsUsername.
  ///
  /// In tr, this message translates to:
  /// **'Bir davet bekliyor — önce kullanıcı adı seç.'**
  String get inviteNeedsUsername;

  /// No description provided for @inviteNeedsUsernameAction.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı seç'**
  String get inviteNeedsUsernameAction;

  /// No description provided for @friendAcceptedSnack.
  ///
  /// In tr, this message translates to:
  /// **'{name} artık arkadaşın.'**
  String friendAcceptedSnack(String name);

  /// No description provided for @diaryThemeCareer.
  ///
  /// In tr, this message translates to:
  /// **'Kariyer'**
  String get diaryThemeCareer;

  /// No description provided for @diaryThemeRelationships.
  ///
  /// In tr, this message translates to:
  /// **'İlişkiler'**
  String get diaryThemeRelationships;

  /// No description provided for @diaryThemeInner.
  ///
  /// In tr, this message translates to:
  /// **'İç dünya'**
  String get diaryThemeInner;

  /// No description provided for @diaryThemeFinance.
  ///
  /// In tr, this message translates to:
  /// **'Para'**
  String get diaryThemeFinance;

  /// No description provided for @reactionHug.
  ///
  /// In tr, this message translates to:
  /// **'Sarıldım'**
  String get reactionHug;

  /// No description provided for @reactionLuck.
  ///
  /// In tr, this message translates to:
  /// **'Bol şans'**
  String get reactionLuck;

  /// No description provided for @reactionCoffee.
  ///
  /// In tr, this message translates to:
  /// **'Kahve içelim'**
  String get reactionCoffee;

  /// No description provided for @reactionMiss.
  ///
  /// In tr, this message translates to:
  /// **'Özledim'**
  String get reactionMiss;

  /// No description provided for @reactionSheetTitle.
  ///
  /// In tr, this message translates to:
  /// **'{name} için bir tepki seç'**
  String reactionSheetTitle(String name);

  /// No description provided for @atlasWheelNatal.
  ///
  /// In tr, this message translates to:
  /// **'Haritam'**
  String get atlasWheelNatal;

  /// No description provided for @atlasWheelSky.
  ///
  /// In tr, this message translates to:
  /// **'Şu an gökyüzü'**
  String get atlasWheelSky;

  /// No description provided for @atlasWheelBiwheel.
  ///
  /// In tr, this message translates to:
  /// **'İkili çark'**
  String get atlasWheelBiwheel;

  /// No description provided for @atlasSkyWheelNote.
  ///
  /// In tr, this message translates to:
  /// **'Gökyüzü şu an herkes için aynı; ev ve Yükselen konuma bağlı olduğu için bu görünümde çizilmez.'**
  String get atlasSkyWheelNote;

  /// No description provided for @atlasHourUnknownWheelNote.
  ///
  /// In tr, this message translates to:
  /// **'Doğum saati bilinmediği için evler ve Yükselen çizilmedi; çark gezegen düzeyinde. Öğle haritası uydurulmadı.'**
  String get atlasHourUnknownWheelNote;

  /// No description provided for @atlasBiwheelNote.
  ///
  /// In tr, this message translates to:
  /// **'İçte doğum haritan, dış halkada şu anki gökyüzü — astrologların transit analizinde kullandığı ikili çark (bi-wheel).'**
  String get atlasBiwheelNote;

  /// No description provided for @atlasSectionAbout.
  ///
  /// In tr, this message translates to:
  /// **'Bana dair'**
  String get atlasSectionAbout;

  /// No description provided for @atlasSectionTime.
  ///
  /// In tr, this message translates to:
  /// **'Zaman'**
  String get atlasSectionTime;

  /// No description provided for @atlasSectionOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer sistemler'**
  String get atlasSectionOther;

  /// No description provided for @atlasFreeChartNote.
  ///
  /// In tr, this message translates to:
  /// **'Çarkın, yerleşimlerin ve açıların ücretsiz. Rytho\'nun derin okuması Rytho+ ile açılır.'**
  String get atlasFreeChartNote;

  /// No description provided for @relationshipAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'{name} ile ilişkimizde \"{axis}\" ekseni hakkında konuşalım.'**
  String relationshipAskPrefill(String name, String axis);

  /// No description provided for @houseN.
  ///
  /// In tr, this message translates to:
  /// **'{n}. ev'**
  String houseN(int n);

  /// No description provided for @perDay.
  ///
  /// In tr, this message translates to:
  /// **'gün'**
  String get perDay;

  /// No description provided for @planetsSectionExtra.
  ///
  /// In tr, this message translates to:
  /// **'Ek noktalar'**
  String get planetsSectionExtra;

  /// No description provided for @planetsFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Burç, derece ve ev doğum anının gerçek gökyüzünden hesaplanır (Swiss Ephemeris). Bir satıra dokun — o noktanın ne anlattığını gör.'**
  String get planetsFootnote;

  /// No description provided for @planetDegree.
  ///
  /// In tr, this message translates to:
  /// **'Burçtaki derece'**
  String get planetDegree;

  /// No description provided for @planetHouse.
  ///
  /// In tr, this message translates to:
  /// **'Ev'**
  String get planetHouse;

  /// No description provided for @planetMotion.
  ///
  /// In tr, this message translates to:
  /// **'Hareket'**
  String get planetMotion;

  /// No description provided for @planetSpeed.
  ///
  /// In tr, this message translates to:
  /// **'Günlük hız'**
  String get planetSpeed;

  /// No description provided for @planetRetrograde.
  ///
  /// In tr, this message translates to:
  /// **'retro'**
  String get planetRetrograde;

  /// No description provided for @pointSheetFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Derece, ev ve hız doğum anının gerçek gökyüzünden hesaplanır (Swiss Ephemeris); anlam cümlesi klasik yorum geleneğidir, sana özel değildir.'**
  String get pointSheetFootnote;

  /// No description provided for @pointPlacementSentence.
  ///
  /// In tr, this message translates to:
  /// **'{rol} — bunlar {alan} alanında işler.'**
  String pointPlacementSentence(String rol, String alan);

  /// No description provided for @pointAscendant.
  ///
  /// In tr, this message translates to:
  /// **'Yükselen'**
  String get pointAscendant;

  /// No description provided for @traitsElements.
  ///
  /// In tr, this message translates to:
  /// **'Element dengesi'**
  String get traitsElements;

  /// No description provided for @traitsModalities.
  ///
  /// In tr, this message translates to:
  /// **'Nitelik dengesi'**
  String get traitsModalities;

  /// No description provided for @traitsSetNote.
  ///
  /// In tr, this message translates to:
  /// **'Sayıma geleneksel yedili (Güneş, Ay, Merkür, Venüs, Mars, Jüpiter, Satürn) ve Yükselen girer — sekiz nokta.'**
  String get traitsSetNote;

  /// No description provided for @traitsTapHint.
  ///
  /// In tr, this message translates to:
  /// **'Bir satıra dokun: sayının hangi noktalardan çıktığını gör.'**
  String get traitsTapHint;

  /// No description provided for @traitsMissingElement.
  ///
  /// In tr, this message translates to:
  /// **'{elements} bu haritada hiç yok — eksik element anlamlı bir ifadedir; eksiklik zayıflık değil, bir yön işaretidir.'**
  String traitsMissingElement(String elements);

  /// No description provided for @traitsSheetTitle.
  ///
  /// In tr, this message translates to:
  /// **'{name} — bu sayı nereden geliyor?'**
  String traitsSheetTitle(String name);

  /// No description provided for @traitsMembersLabel.
  ///
  /// In tr, this message translates to:
  /// **'Bu gruba düşen noktalar'**
  String get traitsMembersLabel;

  /// No description provided for @traitsNoMember.
  ///
  /// In tr, this message translates to:
  /// **'Bu gruba düşen nokta yok.'**
  String get traitsNoMember;

  /// No description provided for @traitsSheetFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Sayım geleneksel yedili + Yükselen üzerinden yapılır. Tek bir burçtan mizaç okunmaz; esas olan dağılımın bütünüdür.'**
  String get traitsSheetFootnote;

  /// No description provided for @traitsUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'Dağılım verisi bu sürümde gelmedi. Uygulamayı güncelleyip tekrar dene.'**
  String get traitsUnavailable;

  /// No description provided for @elementFire.
  ///
  /// In tr, this message translates to:
  /// **'Ateş'**
  String get elementFire;

  /// No description provided for @elementEarth.
  ///
  /// In tr, this message translates to:
  /// **'Toprak'**
  String get elementEarth;

  /// No description provided for @elementAir.
  ///
  /// In tr, this message translates to:
  /// **'Hava'**
  String get elementAir;

  /// No description provided for @elementWater.
  ///
  /// In tr, this message translates to:
  /// **'Su'**
  String get elementWater;

  /// No description provided for @elementFireLine.
  ///
  /// In tr, this message translates to:
  /// **'Ateş: harekete geçme, cesaret, başlatma. Baskınsa hız vardır, sabır azdır.'**
  String get elementFireLine;

  /// No description provided for @elementEarthLine.
  ///
  /// In tr, this message translates to:
  /// **'Toprak: somutlaştırma, süreklilik, güven. Baskınsa istikrar vardır, esneklik azdır.'**
  String get elementEarthLine;

  /// No description provided for @elementAirLine.
  ///
  /// In tr, this message translates to:
  /// **'Hava: düşünme, konuşma, bağ kurma. Baskınsa fikir boldur, derinleşmek zordur.'**
  String get elementAirLine;

  /// No description provided for @elementWaterLine.
  ///
  /// In tr, this message translates to:
  /// **'Su: hissetme, sezgi, bağlanma. Baskınsa duygu derindir, sınır incedir.'**
  String get elementWaterLine;

  /// No description provided for @temperamentFire.
  ///
  /// In tr, this message translates to:
  /// **'Klasik gelenekte ateş baskınlığına safravî mizaç denir (sıcak/kuru). Bu ad tek burçtan değil, yukarıdaki dağılımdan çıkar.'**
  String get temperamentFire;

  /// No description provided for @temperamentEarth.
  ///
  /// In tr, this message translates to:
  /// **'Klasik gelenekte toprak baskınlığına sevdavî mizaç denir (soğuk/kuru). Bu ad tek burçtan değil, yukarıdaki dağılımdan çıkar.'**
  String get temperamentEarth;

  /// No description provided for @temperamentAir.
  ///
  /// In tr, this message translates to:
  /// **'Klasik gelenekte hava baskınlığına demevî mizaç denir (sıcak/nemli). Bu ad tek burçtan değil, yukarıdaki dağılımdan çıkar.'**
  String get temperamentAir;

  /// No description provided for @temperamentWater.
  ///
  /// In tr, this message translates to:
  /// **'Klasik gelenekte su baskınlığına balgamî mizaç denir (soğuk/nemli). Bu ad tek burçtan değil, yukarıdaki dağılımdan çıkar.'**
  String get temperamentWater;

  /// No description provided for @modalityCardinal.
  ///
  /// In tr, this message translates to:
  /// **'Öncü'**
  String get modalityCardinal;

  /// No description provided for @modalityFixed.
  ///
  /// In tr, this message translates to:
  /// **'Sabit'**
  String get modalityFixed;

  /// No description provided for @modalityMutable.
  ///
  /// In tr, this message translates to:
  /// **'Değişken'**
  String get modalityMutable;

  /// No description provided for @modalityCardinalLine.
  ///
  /// In tr, this message translates to:
  /// **'Öncü: başlatır, yön verir, ilk adımı atar.'**
  String get modalityCardinalLine;

  /// No description provided for @modalityFixedLine.
  ///
  /// In tr, this message translates to:
  /// **'Sabit: sürdürür, direnir, kolay vazgeçmez.'**
  String get modalityFixedLine;

  /// No description provided for @modalityMutableLine.
  ///
  /// In tr, this message translates to:
  /// **'Değişken: uyum sağlar, biçim değiştirir, dağılabilir.'**
  String get modalityMutableLine;

  /// No description provided for @aspectsGroupTension.
  ///
  /// In tr, this message translates to:
  /// **'Sert açılar — gerilim'**
  String get aspectsGroupTension;

  /// No description provided for @aspectsGroupFlow.
  ///
  /// In tr, this message translates to:
  /// **'Uyumlu açılar — akış'**
  String get aspectsGroupFlow;

  /// No description provided for @aspectsGroupFocus.
  ///
  /// In tr, this message translates to:
  /// **'Kavuşumlar — yoğunlaşma'**
  String get aspectsGroupFocus;

  /// No description provided for @aspectsGroupOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer açılar'**
  String get aspectsGroupOther;

  /// No description provided for @aspectsSortNote.
  ///
  /// In tr, this message translates to:
  /// **'Her grupta en dar orb önce: orb ne kadar darsa açı o kadar güçlüdür.'**
  String get aspectsSortNote;

  /// No description provided for @aspectMeaningConjunction.
  ///
  /// In tr, this message translates to:
  /// **'Kavuşum: iki gezegen aynı noktada birleşir; güçleri ayrışmaz, birlikte davranır.'**
  String get aspectMeaningConjunction;

  /// No description provided for @aspectMeaningOpposition.
  ///
  /// In tr, this message translates to:
  /// **'Karşıt: iki gezegen karşı karşıyadır; denge ancak ikisine de yer açınca kurulur.'**
  String get aspectMeaningOpposition;

  /// No description provided for @aspectMeaningSquare.
  ///
  /// In tr, this message translates to:
  /// **'Kare: sürtünme açısıdır; zorlar ama hareket ettirir — gelişmenin çoğu buradan çıkar.'**
  String get aspectMeaningSquare;

  /// No description provided for @aspectMeaningTrine.
  ///
  /// In tr, this message translates to:
  /// **'Üçgen: akış açısıdır; kolay geldiği için çoğu zaman fark edilmeden kullanılır.'**
  String get aspectMeaningTrine;

  /// No description provided for @aspectMeaningSextile.
  ///
  /// In tr, this message translates to:
  /// **'Altmışlık: fırsat açısıdır; kendiliğinden olmaz, elini uzatınca çalışır.'**
  String get aspectMeaningSextile;

  /// No description provided for @movementMeaningApplying.
  ///
  /// In tr, this message translates to:
  /// **'Yaklaşıyor: açı tam olmaya gidiyor, etkisi güçleniyor.'**
  String get movementMeaningApplying;

  /// No description provided for @movementMeaningSeparating.
  ///
  /// In tr, this message translates to:
  /// **'Ayrılıyor: açı tamamlandı, etkisi sönüyor.'**
  String get movementMeaningSeparating;

  /// No description provided for @aspectSheetFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Açı ve orb doğum anının gerçek gökyüzünden ölçülür; açıklama klasik yorum geleneğidir.'**
  String get aspectSheetFootnote;

  /// No description provided for @house1.
  ///
  /// In tr, this message translates to:
  /// **'1. ev: kendini gösterme biçimin, bedenin, bıraktığın ilk izlenim.'**
  String get house1;

  /// No description provided for @house2.
  ///
  /// In tr, this message translates to:
  /// **'2. ev: sahip olduklarımız, kaynakların ve değer duygun.'**
  String get house2;

  /// No description provided for @house3.
  ///
  /// In tr, this message translates to:
  /// **'3. ev: konuşma, öğrenme, kardeşler, yakın çevre.'**
  String get house3;

  /// No description provided for @house4.
  ///
  /// In tr, this message translates to:
  /// **'4. ev: kök, ev, aile, içerideki güvenli yer.'**
  String get house4;

  /// No description provided for @house5.
  ///
  /// In tr, this message translates to:
  /// **'5. ev: yaratma, oyun, aşk, kendini ifade etme.'**
  String get house5;

  /// No description provided for @house6.
  ///
  /// In tr, this message translates to:
  /// **'6. ev: gündelik düzen, iş rutini, bedenin bakımı.'**
  String get house6;

  /// No description provided for @house7.
  ///
  /// In tr, this message translates to:
  /// **'7. ev: birebir ilişkiler, ortaklık, karşındaki.'**
  String get house7;

  /// No description provided for @house8.
  ///
  /// In tr, this message translates to:
  /// **'8. ev: paylaşılan kaynaklar, dönüşüm, derin bağ.'**
  String get house8;

  /// No description provided for @house9.
  ///
  /// In tr, this message translates to:
  /// **'9. ev: anlam arayışı, inanç, uzak yerler, öğretmek.'**
  String get house9;

  /// No description provided for @house10.
  ///
  /// In tr, this message translates to:
  /// **'10. ev: kariyer, toplum önündeki duruş, hedef.'**
  String get house10;

  /// No description provided for @house11.
  ///
  /// In tr, this message translates to:
  /// **'11. ev: arkadaşlıklar, topluluk, gelecek tasarısı.'**
  String get house11;

  /// No description provided for @house12.
  ///
  /// In tr, this message translates to:
  /// **'12. ev: geri çekilme, bilinçdışı, arkada kalan.'**
  String get house12;

  /// No description provided for @roleSun.
  ///
  /// In tr, this message translates to:
  /// **'Güneş: öz kimliğin, hayat enerjin, neye yöneldiğin.'**
  String get roleSun;

  /// No description provided for @roleMoon.
  ///
  /// In tr, this message translates to:
  /// **'Ay: duygusal ihtiyacın, alışkanlıkların, kendini güvende hissetme biçimin.'**
  String get roleMoon;

  /// No description provided for @roleMercury.
  ///
  /// In tr, this message translates to:
  /// **'Merkür: düşünme ve anlatma biçimin.'**
  String get roleMercury;

  /// No description provided for @roleVenus.
  ///
  /// In tr, this message translates to:
  /// **'Venüs: neyi sevdiğin, nasıl bağ kurduğun, neye değer verdiğin.'**
  String get roleVenus;

  /// No description provided for @roleMars.
  ///
  /// In tr, this message translates to:
  /// **'Mars: nasıl harekete geçtiğin, öfken ve isteğin.'**
  String get roleMars;

  /// No description provided for @roleJupiter.
  ///
  /// In tr, this message translates to:
  /// **'Jüpiter: büyüme alanın, iyimserliğin, anlam arayışın.'**
  String get roleJupiter;

  /// No description provided for @roleSaturn.
  ///
  /// In tr, this message translates to:
  /// **'Satürn: sorumluluğun, sınırın, zamanla ustalaştığın yer.'**
  String get roleSaturn;

  /// No description provided for @roleUranus.
  ///
  /// In tr, this message translates to:
  /// **'Uranüs: kuralı kırdığın, ani değişim getiren yönün.'**
  String get roleUranus;

  /// No description provided for @roleNeptune.
  ///
  /// In tr, this message translates to:
  /// **'Neptün: hayalin, sezgin, sınırların inceldiği yer.'**
  String get roleNeptune;

  /// No description provided for @rolePluto.
  ///
  /// In tr, this message translates to:
  /// **'Plüton: dönüşüm, güç ve yeniden doğuş alanın.'**
  String get rolePluto;

  /// No description provided for @roleChiron.
  ///
  /// In tr, this message translates to:
  /// **'Kiron: yaralandığın ve zamanla iyileştirmeyi öğrendiğin yer.'**
  String get roleChiron;

  /// No description provided for @roleLilith.
  ///
  /// In tr, this message translates to:
  /// **'Lilith: uzlaşmadığın, evcilleşmeyen yanın.'**
  String get roleLilith;

  /// No description provided for @roleNorthNode.
  ///
  /// In tr, this message translates to:
  /// **'Kuzey Ay Düğümü: geliştirmeye çağrıldığın yön.'**
  String get roleNorthNode;

  /// No description provided for @roleSouthNode.
  ///
  /// In tr, this message translates to:
  /// **'Güney Ay Düğümü: elinde hazır olan, geride bırakman gereken.'**
  String get roleSouthNode;

  /// No description provided for @atlasReportPreparing.
  ///
  /// In tr, this message translates to:
  /// **'Rytho okumanı yazıyor…'**
  String get atlasReportPreparing;

  /// No description provided for @retrogradeMeaning.
  ///
  /// In tr, this message translates to:
  /// **'R retro: gezegen gökyüzünde geri gidiyor görünür. Klasik yorumda o alanda ilerleme dışa değil içe doğrudur — gözden geçirme, toparlama zamanı.'**
  String get retrogradeMeaning;

  /// No description provided for @calendarLockedReading.
  ///
  /// In tr, this message translates to:
  /// **'Bu günün okuması Rytho+ ile açılır.'**
  String get calendarLockedReading;

  /// No description provided for @calendarOtherEvents.
  ///
  /// In tr, this message translates to:
  /// **'Diğer hareketler'**
  String get calendarOtherEvents;

  /// No description provided for @calendarStripTitle.
  ///
  /// In tr, this message translates to:
  /// **'Önündeki 30 gün'**
  String get calendarStripTitle;

  /// No description provided for @storyPause.
  ///
  /// In tr, this message translates to:
  /// **'Duraklat'**
  String get storyPause;

  /// No description provided for @storyPlay.
  ///
  /// In tr, this message translates to:
  /// **'Oynat'**
  String get storyPlay;

  /// No description provided for @relationshipReadingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'nun ilişki okuması'**
  String get relationshipReadingTitle;

  /// No description provided for @relationshipReadingLocked.
  ///
  /// In tr, this message translates to:
  /// **'Ölçülen eksenler ve dayanak açılar herkese açık. Bu ölçümün sizin ikinize özel yorumu Rytho+ ile açılır.'**
  String get relationshipReadingLocked;

  /// No description provided for @moonUncertainNote.
  ///
  /// In tr, this message translates to:
  /// **'Doğum saatin kayıtlı olmadığı için Ay\'ın burcu bir burç şaşabilir — Ay günde yaklaşık 13° yol alır.'**
  String get moonUncertainNote;

  /// No description provided for @moonUncertainAlt.
  ///
  /// In tr, this message translates to:
  /// **'Doğum saatine göre {alt} da olabilir.'**
  String moonUncertainAlt(String alt);

  /// No description provided for @birthMissingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Doğum kaydın eksik'**
  String get birthMissingTitle;

  /// No description provided for @birthMissingBody.
  ///
  /// In tr, this message translates to:
  /// **'Haritanı hesaplayabilmek için doğum tarihin ve şehrin gerekli. Bu bir Rytho+ kilidi değil — kaydı tamamladığında çark, yerleşimler ve açılar ücretsiz açılır.'**
  String get birthMissingBody;

  /// No description provided for @birthMissingAction.
  ///
  /// In tr, this message translates to:
  /// **'Doğum kaydını tamamla'**
  String get birthMissingAction;

  /// No description provided for @circleTitle.
  ///
  /// In tr, this message translates to:
  /// **'Çevrem'**
  String get circleTitle;

  /// No description provided for @circleFriendsSection.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'daki arkadaşların'**
  String get circleFriendsSection;

  /// No description provided for @circlePeopleSection.
  ///
  /// In tr, this message translates to:
  /// **'Eklediklerin'**
  String get circlePeopleSection;

  /// No description provided for @circleEmptyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Eşini, çocuğunu ekle'**
  String get circleEmptyTitle;

  /// No description provided for @circleEmptyBody.
  ///
  /// In tr, this message translates to:
  /// **'Yakınlarının haritalarını ve aranızdaki bağı gör. Onların uygulamayı kullanmasına gerek yok.'**
  String get circleEmptyBody;

  /// No description provided for @addChooserTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kimi ekliyorsun?'**
  String get addChooserTitle;

  /// No description provided for @addChooserFriend.
  ///
  /// In tr, this message translates to:
  /// **'Rytho\'da olan biri'**
  String get addChooserFriend;

  /// No description provided for @addChooserFriendBody.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı, rehber ya da davet bağlantısıyla. Karşılıklı onay gerekir; tepki gönderebilir, serilerini görürsünüz.'**
  String get addChooserFriendBody;

  /// No description provided for @addChooserPerson.
  ///
  /// In tr, this message translates to:
  /// **'Kendim ekleyeceğim'**
  String get addChooserPerson;

  /// No description provided for @addChooserPersonBody.
  ///
  /// In tr, this message translates to:
  /// **'Eşin, çocuğun, bir yakının. Doğum bilgilerini sen girersin.'**
  String get addChooserPersonBody;

  /// No description provided for @peopleAddTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kişi ekle'**
  String get peopleAddTitle;

  /// No description provided for @peopleEditTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kişiyi düzenle'**
  String get peopleEditTitle;

  /// No description provided for @peopleLabelField.
  ///
  /// In tr, this message translates to:
  /// **'Adı'**
  String get peopleLabelField;

  /// No description provided for @peopleLabelHint.
  ///
  /// In tr, this message translates to:
  /// **'Bu kişiyi nasıl anıyorsun?'**
  String get peopleLabelHint;

  /// No description provided for @peopleLabelNote.
  ///
  /// In tr, this message translates to:
  /// **'Bu ad telefonundan çıkmaz. Sunucuda yalnız doğum bilgisi durur; Rytho bu kişiden \"eşin\", \"çocuğun\" diye söz eder.'**
  String get peopleLabelNote;

  /// No description provided for @peopleRelation.
  ///
  /// In tr, this message translates to:
  /// **'Yakınlık'**
  String get peopleRelation;

  /// No description provided for @peopleConsent.
  ///
  /// In tr, this message translates to:
  /// **'Bu kişinin doğum bilgilerini onun adına giriyorsun. Kayıt yalnız sana görünür, başka hiçbir kullanıcı erişemez ve hesabını silersen birlikte silinir.'**
  String get peopleConsent;

  /// No description provided for @peopleSaved.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedildi'**
  String get peopleSaved;

  /// No description provided for @peopleRemove.
  ///
  /// In tr, this message translates to:
  /// **'Kişiyi çıkar'**
  String get peopleRemove;

  /// No description provided for @peopleRemoveConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Bu kişi ve haritası silinsin mi? Geri alınamaz.'**
  String get peopleRemoveConfirm;

  /// No description provided for @peopleRemoved.
  ///
  /// In tr, this message translates to:
  /// **'Çıkarıldı'**
  String get peopleRemoved;

  /// No description provided for @peopleSlots.
  ///
  /// In tr, this message translates to:
  /// **'{used}/{limit} kişi'**
  String peopleSlots(int used, int limit);

  /// No description provided for @peopleHourUnknownBadge.
  ///
  /// In tr, this message translates to:
  /// **'Doğum saati bilinmiyor — Yükselen ve evler hesaplanmadı.'**
  String get peopleHourUnknownBadge;

  /// No description provided for @relationPartner.
  ///
  /// In tr, this message translates to:
  /// **'Eşim'**
  String get relationPartner;

  /// No description provided for @relationChild.
  ///
  /// In tr, this message translates to:
  /// **'Çocuğum'**
  String get relationChild;

  /// No description provided for @relationParent.
  ///
  /// In tr, this message translates to:
  /// **'Annem/Babam'**
  String get relationParent;

  /// No description provided for @relationSibling.
  ///
  /// In tr, this message translates to:
  /// **'Kardeşim'**
  String get relationSibling;

  /// No description provided for @relationFriend.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaşım'**
  String get relationFriend;

  /// No description provided for @relationWork.
  ///
  /// In tr, this message translates to:
  /// **'İş arkadaşım'**
  String get relationWork;

  /// No description provided for @relationOther.
  ///
  /// In tr, this message translates to:
  /// **'Yakınım'**
  String get relationOther;

  /// No description provided for @relationshipTodayLabel.
  ///
  /// In tr, this message translates to:
  /// **'Bugün aranıza dokunan gökyüzü'**
  String get relationshipTodayLabel;

  /// No description provided for @relationshipTodayQuiet.
  ///
  /// In tr, this message translates to:
  /// **'Bugün aranıza dokunan belirgin bir transit yok — sakin bir gün.'**
  String get relationshipTodayQuiet;

  /// No description provided for @relationshipTodayAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Bugün {name} ile aramıza dokunan gökyüzünü konuşalım.'**
  String relationshipTodayAskPrefill(String name);

  /// No description provided for @chatMentionAttached.
  ///
  /// In tr, this message translates to:
  /// **'{name} bağlamı ekli'**
  String chatMentionAttached(String name);

  /// No description provided for @chatMentionClearTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Bağlamı kaldır'**
  String get chatMentionClearTooltip;

  /// No description provided for @chatMentionEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşen kişi yok — Çevrem\'den ekleyebilirsin'**
  String get chatMentionEmpty;

  /// No description provided for @discoveryComplete.
  ///
  /// In tr, this message translates to:
  /// **'Günün üç keşfi tamam ✨ Yarın gökyüzü yeniden kurulur.'**
  String get discoveryComplete;

  /// No description provided for @discoveryRingTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Günün keşif halkası: gökyüzünü aç · Rytho ile konuş · çevrenden birine bak'**
  String get discoveryRingTooltip;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In tr, this message translates to:
  /// **'Şifreni sıfırla'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordBody.
  ///
  /// In tr, this message translates to:
  /// **'Hesabının e-posta adresini yaz; sana bir sıfırlama bağlantısı gönderelim.'**
  String get forgotPasswordBody;

  /// No description provided for @forgotPasswordSend.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantıyı gönder'**
  String get forgotPasswordSend;

  /// No description provided for @forgotPasswordSentTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı yolda'**
  String get forgotPasswordSentTitle;

  /// No description provided for @forgotPasswordSentBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu adres kayıtlıysa {email} adresine bir sıfırlama bağlantısı gönderdik. Bağlantı kısa süreliğine geçerli.'**
  String forgotPasswordSentBody(String email);

  /// No description provided for @forgotPasswordSpamHint.
  ///
  /// In tr, this message translates to:
  /// **'E-posta birkaç dakika içinde gelmezse spam/gereksiz klasörüne bak.'**
  String get forgotPasswordSpamHint;

  /// No description provided for @forgotPasswordResend.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar gönder'**
  String get forgotPasswordResend;

  /// No description provided for @forgotPasswordResendWait.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar gönder ({seconds} sn)'**
  String forgotPasswordResendWait(int seconds);

  /// No description provided for @notifPermissionOffTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler sistemde kapalı'**
  String get notifPermissionOffTitle;

  /// No description provided for @notifPermissionOffBody.
  ///
  /// In tr, this message translates to:
  /// **'Telefonun ayarlarında Rytho bildirimlerine izin vermeden buradaki tercihler etkisiz kalır: Ayarlar → Uygulamalar → Rytho → Bildirimler.'**
  String get notifPermissionOffBody;

  /// No description provided for @chatOpenLabel.
  ///
  /// In tr, this message translates to:
  /// **'Rytho ile sohbet et'**
  String get chatOpenLabel;

  /// No description provided for @trialBannerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Deneme süren aktif'**
  String get trialBannerTitle;

  /// No description provided for @trialBannerDays.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Rytho+ özellikleri açık — {days} gün kaldı.'**
  String trialBannerDays(int days);

  /// No description provided for @trialBannerLastDay.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Rytho+ özellikleri açık — bugün son gün.'**
  String get trialBannerLastDay;

  /// No description provided for @chartWheelSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Astroloji çarkı: {rings} halka, {aspects} açı. Ayrıntılar aşağıdaki konum tablosunda.'**
  String chartWheelSemantics(int rings, int aspects);

  /// No description provided for @chartLegendInner.
  ///
  /// In tr, this message translates to:
  /// **'İç: {label}'**
  String chartLegendInner(String label);

  /// No description provided for @chartLegendOuter.
  ///
  /// In tr, this message translates to:
  /// **'Dış: {label}'**
  String chartLegendOuter(String label);

  /// No description provided for @chartLegendYou.
  ///
  /// In tr, this message translates to:
  /// **'sen'**
  String get chartLegendYou;

  /// No description provided for @chartLegendSkyNow.
  ///
  /// In tr, this message translates to:
  /// **'şu anki gökyüzü'**
  String get chartLegendSkyNow;

  /// No description provided for @chartFilterAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get chartFilterAll;

  /// No description provided for @chartFilterMajor.
  ///
  /// In tr, this message translates to:
  /// **'Majör'**
  String get chartFilterMajor;

  /// No description provided for @chartFilterApplying.
  ///
  /// In tr, this message translates to:
  /// **'Yaklaşan'**
  String get chartFilterApplying;

  /// No description provided for @chartFilterHard.
  ///
  /// In tr, this message translates to:
  /// **'Sert'**
  String get chartFilterHard;

  /// No description provided for @chartFilterSoft.
  ///
  /// In tr, this message translates to:
  /// **'Yumuşak'**
  String get chartFilterSoft;

  /// No description provided for @chartFilterMinors.
  ///
  /// In tr, this message translates to:
  /// **'Minörler'**
  String get chartFilterMinors;

  /// No description provided for @chartOrbLabel.
  ///
  /// In tr, this message translates to:
  /// **'Orb ≤ {orb}°'**
  String chartOrbLabel(int orb);

  /// No description provided for @chartHouseSystem.
  ///
  /// In tr, this message translates to:
  /// **'Placidus evleri · Tropikal zodyak'**
  String get chartHouseSystem;

  /// No description provided for @chartHourUnknownNote.
  ///
  /// In tr, this message translates to:
  /// **'Doğum saati bilinmediği için evler, Yükselen ve eksenler çizilmedi.'**
  String get chartHourUnknownNote;

  /// No description provided for @chartAspectarianTitle.
  ///
  /// In tr, this message translates to:
  /// **'AÇI TABLOSU'**
  String get chartAspectarianTitle;

  /// No description provided for @chartPositionsTitle.
  ///
  /// In tr, this message translates to:
  /// **'KONUMLAR'**
  String get chartPositionsTitle;

  /// No description provided for @chartApplyingLetter.
  ///
  /// In tr, this message translates to:
  /// **'Y'**
  String get chartApplyingLetter;

  /// No description provided for @chartSeparatingLetter.
  ///
  /// In tr, this message translates to:
  /// **'A'**
  String get chartSeparatingLetter;

  /// No description provided for @chartHousesYou.
  ///
  /// In tr, this message translates to:
  /// **'Evler: sen'**
  String get chartHousesYou;

  /// No description provided for @chartHousesOther.
  ///
  /// In tr, this message translates to:
  /// **'Evler: {name}'**
  String chartHousesOther(String name);

  /// No description provided for @chartModeSynastry.
  ///
  /// In tr, this message translates to:
  /// **'Sen & {name}'**
  String chartModeSynastry(String name);

  /// No description provided for @chartAskPrefillNatal.
  ///
  /// In tr, this message translates to:
  /// **'Şu an {name} haritasının çarkını inceliyorum. En çok dikkat etmem gereken ne?'**
  String chartAskPrefillNatal(String name);

  /// No description provided for @chartAskPrefillOwn.
  ///
  /// In tr, this message translates to:
  /// **'Şu an kendi haritamın çarkını inceliyorum. En çok dikkat etmem gereken ne?'**
  String get chartAskPrefillOwn;

  /// No description provided for @chartAskPrefillSky.
  ///
  /// In tr, this message translates to:
  /// **'Şu anki gökyüzü çarkını inceliyorum. Bugün beni en çok ne etkiliyor?'**
  String get chartAskPrefillSky;

  /// No description provided for @chartAskPrefillBiwheel.
  ///
  /// In tr, this message translates to:
  /// **'Haritamla bugünkü gökyüzünü üst üste inceliyorum. En çok hangi dokunuş öne çıkıyor?'**
  String get chartAskPrefillBiwheel;

  /// No description provided for @chartAskPrefillSynastry.
  ///
  /// In tr, this message translates to:
  /// **'{name} ile ikili çarkımızı inceliyorum. Aramızda en belirleyici bağ hangisi?'**
  String chartAskPrefillSynastry(String name);

  /// No description provided for @chartMovementLegend.
  ///
  /// In tr, this message translates to:
  /// **'Y yaklaşan · A ayrılan'**
  String get chartMovementLegend;

  /// No description provided for @chartLoading.
  ///
  /// In tr, this message translates to:
  /// **'Çark hazırlanıyor…'**
  String get chartLoading;

  /// No description provided for @chartSelectionClear.
  ///
  /// In tr, this message translates to:
  /// **'Seçimi kaldır'**
  String get chartSelectionClear;

  /// No description provided for @chartAsOf.
  ///
  /// In tr, this message translates to:
  /// **'{time} itibarıyla'**
  String chartAsOf(String time);

  /// No description provided for @chartAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Şu an {title} çarkını inceliyorum. Bu haritada öne çıkan neler?'**
  String chartAskPrefill(String title);

  /// No description provided for @innerCalendarAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'İç mevsim sayfamı açtım. Progres Ay\'ımın şu dönemde ne anlattığını biraz açar mısın?'**
  String get innerCalendarAskPrefill;

  /// No description provided for @birthHexagramAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Doğum kapımı açtım. Bu kapının karakterimde nasıl çalıştığını biraz açar mısın?'**
  String get birthHexagramAskPrefill;

  /// No description provided for @solarReturnAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Yıl haritamı açtım. Bu yılın bana ne getirdiğini biraz açar mısın?'**
  String get solarReturnAskPrefill;

  /// No description provided for @baziAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'BaZi haritamı açtım. Dört sütunumun ne anlattığını biraz açar mısın?'**
  String get baziAskPrefill;

  /// No description provided for @iChingAskPrefill.
  ///
  /// In tr, this message translates to:
  /// **'Kehanete şunu sordum: \"{question}\" Gelen cevabı biraz açar mısın?'**
  String iChingAskPrefill(String question);

  /// No description provided for @chartShareTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Çarkı paylaş'**
  String get chartShareTooltip;

  /// No description provided for @chartExpandTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Harita İnceleme\'de aç'**
  String get chartExpandTooltip;

  /// No description provided for @chartSelectedDetail.
  ///
  /// In tr, this message translates to:
  /// **'Detay →'**
  String get chartSelectedDetail;

  /// No description provided for @chartOuterLoading.
  ///
  /// In tr, this message translates to:
  /// **'Dış halka yükleniyor…'**
  String get chartOuterLoading;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

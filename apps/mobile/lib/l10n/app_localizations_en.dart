// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get atlasYearChart => 'Birthday to birthday';

  @override
  String get atlasYearChartSubtitle => 'Your year chart (solar return)';

  @override
  String get atlasInnerCalendar => 'Inner season';

  @override
  String get atlasInnerCalendarSubtitle => 'Progressed Moon + life arc';

  @override
  String get wizardWelcomeTitle => 'The journey begins';

  @override
  String get wizardWelcomeBody =>
      'A few steps and your chart is drawn: the moment you were born, the sky exactly as it stood. A star lights up at every step.';

  @override
  String get wizardConsentLabel =>
      'I have read and accept the Terms of Use and Privacy Policy. I am over 13.';

  @override
  String get wizardDateTitle => 'What day were you born?';

  @override
  String get wizardDateBody =>
      'The sky arranged itself differently every single day — which one was yours?';

  @override
  String get wizardTimeTitle => 'What time was it?';

  @override
  String get wizardTimeBody =>
      'Birth time sets your Ascendant and houses. Don\'t know it? That\'s fine — we calculate honestly without it.';

  @override
  String get wizardTimeUnknownNote =>
      'Without a time, the Ascendant and houses are not computed; the reading stays at the planetary level.';

  @override
  String get wizardPlaceTitle => 'Where were you born?';

  @override
  String get wizardPlaceBody =>
      'Place decides how the sky stood from where you were — what was rising on your horizon?';

  @override
  String get wizardGenderTitle => 'One detail for BaZi';

  @override
  String get wizardGenderBody =>
      'BaZi (Four Pillars) takes the direction of its luck cycles from gender. If you don’t specify, that direction isn’t computed; everything else stays the same.';

  @override
  String get wizardNext => 'Continue ✦';

  @override
  String get wizardFinish => 'Draw my chart';

  @override
  String get wizardNotifyTitle => 'When your reading is ready?';

  @override
  String get wizardNotifyBody =>
      'Shall we send a gentle nudge for your daily reading and streak? Quiet hours can be set under Profile.';

  @override
  String get wizardNotifyAllow => 'Notify me 🔔';

  @override
  String get genderUnspecified => 'Not specified';

  @override
  String get wizardNotifyNotNow => 'Not now';

  @override
  String wizardStepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get deviceConflictBodyUnknown =>
      'You signed in on another device. Rytho+ works on one device at a time — tap \"Use on this device\" to continue here.';

  @override
  String get emailHint => 'name@example.com';

  @override
  String get countrySearchHint => 'Search for a country…';

  @override
  String get phoneSmsDisabled =>
      'SMS verification isn\'t available right now. Please try again later.';

  @override
  String get phoneTemporarilyBlocked =>
      'Verification is temporarily paused after too many attempts. Please try again in a few hours.';

  @override
  String get purchaseEntitlementMissing =>
      'Payment went through but the subscription couldn\'t be confirmed. Try \"Restore purchases\"; if it persists, contact us — your payment is safe.';

  @override
  String get purchaseWaitingStore =>
      'Talking to the store… Please don\'t close this screen.';

  @override
  String get purchaseWaitingLong =>
      'The store is still working on it. You can close this screen without losing the purchase: the result reaches your account on its own.';

  @override
  String get purchaseLeaveScreen => 'Close this screen';

  @override
  String get purchasePendingServer =>
      'Your purchase was taken. It can take a few seconds to show up in your account.';

  @override
  String get avatarEditTitle => 'Position your photo';

  @override
  String get avatarEditHint => 'Drag to position, pinch to zoom.';

  @override
  String get avatarUpdated => 'Profile photo updated ✨';

  @override
  String get avatarChangeFailed =>
      'The photo couldn\'t be uploaded. Check your connection and try again.';

  @override
  String get phoneAppNotVerified =>
      'App verification failed. Update the app and try again.';

  @override
  String get citySearchHint => 'Search for a city…';

  @override
  String get citySearchPrompt =>
      'Start typing your birth city — search across 34,000 cities.';

  @override
  String get citySearchNoResults =>
      'Not in the list — you can save it exactly as typed.';

  @override
  String citySearchUseAsTyped(String query) {
    return 'Save as \"$query\"';
  }

  @override
  String get residenceCityTitle => 'Where you live';

  @override
  String get residenceCityRowSubtitle => 'Your year chart is cast here';

  @override
  String get residenceCityBody =>
      'A solar return is cast for wherever you are on your birthday — the city changes the Ascendant and the houses. Leave it empty and your birth city is used.';

  @override
  String get solarReturnTitle => 'Year Chart';

  @override
  String get solarReturnWaitStage1 => 'Calculating the Sun\'s return moment…';

  @override
  String get solarReturnWaitStage2 => 'Writing the year\'s reading…';

  @override
  String get solarReturnLockedBody =>
      'The year chart cast for the Sun\'s exact return to your natal degree — and Rytho\'s reading of it — opens with Rytho+.';

  @override
  String get solarReturnMoment => 'Return moment';

  @override
  String solarReturnNext(String date) {
    return 'Next return: $date';
  }

  @override
  String get solarReturnIdentity => 'The year\'s identity';

  @override
  String get solarReturnAsc => 'Year Ascendant';

  @override
  String get solarReturnSunHouse => 'Sun\'s house this year';

  @override
  String solarReturnHouseN(int n) {
    return 'house $n';
  }

  @override
  String get solarReturnMoon => 'Year Moon';

  @override
  String get solarReturnNote => 'Rytho\'s year reading';

  @override
  String get innerCalendarTitle => 'Inner season';

  @override
  String get innerCalendarWaitStage1 => 'Advancing the progressed chart…';

  @override
  String get innerCalendarWaitStage2 =>
      'Reading the progressed Moon\'s season…';

  @override
  String get innerCalendarLockedBody =>
      'The progressed Moon\'s inner season and your life arc open with Rytho+.';

  @override
  String get innerCalendarProgMoon => 'Progressed Moon — your inner season';

  @override
  String innerCalendarNextSign(String date) {
    return '$date → next sign';
  }

  @override
  String get innerCalendarActive => 'Active now';

  @override
  String get innerCalendarArc => 'Arc of life (solar arc)';

  @override
  String get innerCalendarNote => 'Rytho\'s inner-season reading';

  @override
  String get appTagline =>
      'Ancient wisdom, met with precise sky calculation.\nYour chart is drawn; your path lights up.';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get orDivider => 'or';

  @override
  String get signIn => 'Sign in';

  @override
  String get signUp => 'Sign up';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get forgotPassword => 'Forgot password';

  @override
  String get tabSky => 'Sky';

  @override
  String get tabAtlas => 'Atlas';

  @override
  String get tabFriends => 'Friends';

  @override
  String get tabProfile => 'Profile';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingDay => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String get greetingNight => 'Good night';

  @override
  String get todaysInsight => 'Today\'s Insight';

  @override
  String get skyNow => 'In the Sky Right Now';

  @override
  String get iChing => 'I Ching';

  @override
  String get iChingSubtitle => 'Book of Changes';

  @override
  String get birthHexagram => 'Birth Gate';

  @override
  String get birthHexagramSubtitle => '64 gates';

  @override
  String get birthHexagramTitle => 'Birth Hexagram';

  @override
  String birthHexagramGateLine(int gate, int line) {
    return 'Gate $gate · line $line';
  }

  @override
  String birthHexagramGateOnly(int gate) {
    return 'Gate $gate';
  }

  @override
  String birthHexagramSunAt(String deg) {
    return 'Sun at birth: $deg°';
  }

  @override
  String birthHexagramBoundary(int a, int b) {
    return 'The birth hour is unknown, so your gate may be $a or $b.';
  }

  @override
  String get birthHexagramLockedBody =>
      'Where the Sun stood on the 64-gate wheel at your birth — your lasting character gate. Opens with Rytho+.';

  @override
  String get birthHexagramNote => 'Rytho\'s gate reading';

  @override
  String get birthHexagramGatePassage => 'The Gate\'s Weave';

  @override
  String get faceReadingTileSubtitle => 'The art of firasa';

  @override
  String get baZi => 'BaZi';

  @override
  String get baZiSubtitle => 'Four Pillars';

  @override
  String get personalReadingLocked => 'Your personal daily reading';

  @override
  String get personalReadingLockedBody =>
      'Your daily reading built from your own chart opens with Rytho+.';

  @override
  String personalReadingLockedBodyWithSign(String sign) {
    return 'The general $sign reading lives in the story ring. With Rytho+ this one also accounts for your Moon and Rising.';
  }

  @override
  String get personalReadingTitle => 'For you';

  @override
  String get natalLockedTitle => 'Birth chart analysis';

  @override
  String get natalLockedBody =>
      'The full reading of your placements, houses and aspects opens with Rytho+.';

  @override
  String get baziLockedTitle => 'BaZi — Four Pillars';

  @override
  String get baziLockedBody =>
      'Day Master, Ten Gods and luck pillars open with Rytho+.';

  @override
  String get iChingLockedTitle => 'I Ching — Book of Changes';

  @override
  String get iChingLockedBody =>
      'Ask a question, cast with true probabilities, read the Rytho interpretation — opens with Rytho+.';

  @override
  String get synastryLockedTitle => 'Synastry wheel';

  @override
  String get synastryLockedBody =>
      'The reading of two charts laid over each other opens with Rytho+.';

  @override
  String get addFriend => 'Add friend';

  @override
  String get usernameLabel => 'USERNAME';

  @override
  String get usernameHeadline => 'Let your friends find you';

  @override
  String get usernameBody =>
      'Pick a username. Friends are added by username or invite link; you can also enable contact matching under Privacy if you like.';

  @override
  String get usernameHint => 'username';

  @override
  String get claimUsername => 'Claim username';

  @override
  String get usernameInvalid =>
      '3-20 characters; lowercase letters, numbers and underscore only.';

  @override
  String get usernameEmpty => 'Username can\'t be empty.';

  @override
  String get usernameTaken => 'That username is taken — try another.';

  @override
  String get copyInviteLink => 'Copy invite link';

  @override
  String get inviteLinkCopied => 'Invite link copied.';

  @override
  String get shareInviteInstead => 'Share my invite link instead';

  @override
  String get sendInvite => 'Send invite';

  @override
  String inviteSent(String username) {
    return 'Invite sent to @$username.';
  }

  @override
  String userNotFound(String username) {
    return '@$username not found.';
  }

  @override
  String get cannotAddSelf => 'You can\'t add yourself.';

  @override
  String get inboxLabel => 'SENT TO YOU';

  @override
  String get noFriendsYet => 'No one here yet';

  @override
  String get noFriendsBody =>
      'Add a friend by username — see each other\'s streaks and read the dynamic between you every day.';

  @override
  String get incomingRequests => 'Incoming invites';

  @override
  String get pendingInvites => 'Invites awaiting a reply';

  @override
  String get accept => 'Accept';

  @override
  String get ignore => 'Ignore';

  @override
  String get pending => 'Pending';

  @override
  String get withdrawInvite => 'Withdraw invite';

  @override
  String get readToday => 'Has read today';

  @override
  String get notReadToday => 'Hasn\'t read yet today';

  @override
  String get streakHidden => 'Streak hidden';

  @override
  String get friendLabel => 'Your friend';

  @override
  String get streakHiddenByFriend => 'Keeps their streak private';

  @override
  String get readTodayDone => 'Has done today\'s reading';

  @override
  String get dyadLabel => 'Between you today';

  @override
  String get dyadDisclaimer =>
      'This reading holds for today only and changes tomorrow. We don\'t give a fixed compatibility score.';

  @override
  String get sendReaction => 'Send a reaction';

  @override
  String get sendReactionBody =>
      'Pick one of the ready reactions — no writing, just a small hello.';

  @override
  String reactionSent(String emoji) {
    return '$emoji sent.';
  }

  @override
  String get removeFriend => 'Remove friend';

  @override
  String get blockUser => 'Block';

  @override
  String get reportUser => 'Report';

  @override
  String get reactionStreak => 'Keep the streak';

  @override
  String get reactionThinkingOfYou => 'Thinking of you';

  @override
  String get reactionShine => 'You\'re shining';

  @override
  String get reactionKeepGoing => 'Keep going';

  @override
  String get reactionCongrats => 'Congratulations';

  @override
  String get reactionSameFrequency => 'Same frequency';

  @override
  String get reactionGoodNight => 'Good night';

  @override
  String get reactionCheckToday => 'Check today';

  @override
  String get paywallTitle => 'Rytho+';

  @override
  String get paywallHeadline =>
      'The stars are the same for everyone.\nYou are not.';

  @override
  String get paywallBody =>
      'Your daily sign reading and the real sky data stay open on the free tier, always. Rytho+ builds every reading from your own chart.';

  @override
  String get paywallContinue => 'Continue with Rytho+';

  @override
  String get paywallChoosePlan => 'Choose a plan';

  @override
  String get restorePurchases => 'Restore purchases';

  @override
  String get noActiveSubscription => 'No active subscription found to restore.';

  @override
  String get purchaseFailed => 'The purchase couldn\'t be completed.';

  @override
  String get billingUnavailable => 'Purchases aren\'t available right now';

  @override
  String get billingNoPackages => 'No packages are configured in the store.';

  @override
  String get planWeekly => 'Weekly';

  @override
  String get planMonthly => 'Monthly';

  @override
  String get planAnnual => 'Annual';

  @override
  String paywallForFeature(String name) {
    return 'Rytho+ for $name';
  }

  @override
  String priceWithPeriod(String price, String unit) {
    return '$price / $unit';
  }

  @override
  String annualPerMonth(String price) {
    return '≈ $price a month';
  }

  @override
  String annualSavingsBadge(int percent) {
    return 'Save $percent%';
  }

  @override
  String trialThenPriceDays(int count, String price) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days free, then $price',
      one: '1 day free, then $price',
    );
    return '$_temp0';
  }

  @override
  String trialThenPriceWeeks(int count, String price) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks free, then $price',
      one: '1 week free, then $price',
    );
    return '$_temp0';
  }

  @override
  String trialThenPriceMonths(int count, String price) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months free, then $price',
      one: '1 month free, then $price',
    );
    return '$_temp0';
  }

  @override
  String trialThenPriceYears(int count, String price) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years free, then $price',
      one: '1 year free, then $price',
    );
    return '$_temp0';
  }

  @override
  String get unitDay => 'day';

  @override
  String get unitWeek => 'week';

  @override
  String get unitMonth => 'month';

  @override
  String get unitYear => 'year';

  @override
  String get subscriptionTerms =>
      'Your subscription renews automatically unless cancelled at least 24 hours before the period ends. If there is a free trial and you cancel before it ends, you won\'t be charged. You can cancel in your device\'s store account settings.';

  @override
  String get benefitDailyTitle => 'A daily reading built for you';

  @override
  String get benefitDailyBody =>
      'Your natal chart collided with today\'s sky — not a generic sun-sign horoscope.';

  @override
  String get benefitNatalTitle => 'Full birth chart report';

  @override
  String get benefitNatalBody =>
      'Planets, houses and aspects — not a one-off surface summary.';

  @override
  String get benefitDyadTitle => 'Daily dynamic with your friends';

  @override
  String get benefitDyadBody =>
      'A shared reading that renews each day. No fixed compatibility score.';

  @override
  String benefitChatTitleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count AI credits a month',
      one: '1 AI credit a month',
    );
    return '$_temp0';
  }

  @override
  String get benefitChatTitleUnknown => 'Monthly AI credits';

  @override
  String get benefitChatBody =>
      'Spend them freely on chat, reports and castings; the more Rytho knows you, the deeper it goes.';

  @override
  String get benefitBaziTitle => 'BaZi and synastry';

  @override
  String get benefitBaziBody =>
      'Four Pillars analysis and chart-to-chart comparison.';

  @override
  String get benefitFaceTitle => 'Face Reading';

  @override
  String get benefitFaceBody =>
      'A temperament reading from your features, in the firasa tradition. The image is processed on your device; only the measured ratios reach the server.';

  @override
  String get benefitTimingTitle => 'Year Chart, Inner Calendar and Birth Gate';

  @override
  String get benefitTimingBody =>
      'The chart cast at the Sun\'s return to its birth longitude, your progressed inner calendar, and your gate on the wheel of 64.';

  @override
  String get benefitIchingTitle => 'I Ching castings';

  @override
  String get benefitIchingBody =>
      'Cast on true probabilities, with Rytho\'s reading of the moving lines.';

  @override
  String get benefitPeopleTitle => 'Ten people in your circle';

  @override
  String get benefitPeopleBody =>
      'The free tier holds one person; with Rytho+ you add up to ten and read synastry with each of them.';

  @override
  String get profileTitle => 'Profile';

  @override
  String get settings => 'Settings';

  @override
  String get sounds => 'Sounds';

  @override
  String get privacy => 'Privacy';

  @override
  String get streakVisibleSetting => 'Let friends see my streak';

  @override
  String get streakVisibleSettingBody =>
      'When off, neither your streak nor whether you\'ve read today is shared.';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System language';

  @override
  String get languageTurkish => 'Türkçe';

  @override
  String get languageEnglish => 'English';

  @override
  String get about => 'About';

  @override
  String get aboutBody =>
      'Rytho joins Western astrology, BaZi and the I Ching to precise ephemeris calculation. Readings are for insight; they are not medical, legal or financial advice.';

  @override
  String get ephemerisCredit => 'Ephemeris: Swiss Ephemeris © Astrodienst AG';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get termsOfUse => 'Terms of Use';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutConfirmBody =>
      'Notifications stop on this device; sign back in to pick up where you left off.';

  @override
  String streakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get birthRecord => 'Birth Record';

  @override
  String get birthDate => 'Date';

  @override
  String get birthTime => 'Time';

  @override
  String get birthTimeUnknown => 'I don\'t know my birth time';

  @override
  String get birthCity => 'City';

  @override
  String get retry => 'Try again';

  @override
  String retryAfterSeconds(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Try again in $n seconds',
      one: 'Try again in 1 second',
    );
    return '$_temp0';
  }

  @override
  String get delete => 'Delete';

  @override
  String get discard => 'Discard';

  @override
  String get feedbackDiscardTitle => 'Discard what you wrote';

  @override
  String get feedbackDiscardBody => 'Your feedback won\'t be saved.';

  @override
  String get errorGeneric =>
      'Something unexpected happened. Please try again shortly.';

  @override
  String get errorConnection =>
      'Couldn\'t connect. Check your internet and try again.';

  @override
  String get reportUnavailable =>
      'We couldn\'t produce your reading just now. Try again in a few seconds.';

  @override
  String get reportUnavailableRefunded =>
      'We couldn\'t produce your report just now — the credit you spent has been refunded. Try again in a few seconds.';

  @override
  String get chatTitle => 'Rytho AI';

  @override
  String get chatSend => 'Send';

  @override
  String get chatHint => 'Ask anything about what\'s ahead...';

  @override
  String get chatEmptyBody =>
      'Your chart, your patterns, your path — ask whatever is on your mind.';

  @override
  String get suggestCareer => 'Career 💼';

  @override
  String get suggestLove => 'Love life ❤️';

  @override
  String get suggestMonth => 'What does this month hold?';

  @override
  String get suggestFinance => 'Money and work 💰';

  @override
  String get suggestMarriage => 'Commitment 💍';

  @override
  String get onboardingCity => 'Birth city';

  @override
  String get genderFemale => 'Female';

  @override
  String get genderMale => 'Male';

  @override
  String get genderOther => 'Other';

  @override
  String get onboardingStage1 => 'Positioning the sky';

  @override
  String get onboardingStage2 => 'Calculating the houses';

  @override
  String get onboardingStage3 => 'Drawing your chart';

  @override
  String get bigThreeTitle => 'The sky\'s three seals for you';

  @override
  String get bigThreeSun => 'SUN';

  @override
  String get bigThreeMoon => 'MOON';

  @override
  String get bigThreeAscendant => 'ASCENDANT';

  @override
  String get bigThreeAscendantUnknown => 'time unknown';

  @override
  String get bigThreeStart => 'Begin the journey';

  @override
  String get profileSubscriptionRow => 'Subscription & credits';

  @override
  String get subscriptionScreenTitle => 'Subscription & Credits';

  @override
  String get subPlanLabel => 'PLAN';

  @override
  String get subPlanFree => 'Free';

  @override
  String get subPlanFreeBody =>
      'Your personalised daily reading, natal report, BaZi, Year Chart and Inner Calendar open with Rytho+.';

  @override
  String get subPlanMonthly => 'Rytho+ Monthly';

  @override
  String get subPlanYearly => 'Rytho+ Yearly';

  @override
  String get subGoPlus => 'Go Rytho+';

  @override
  String get subStatusLabel => 'Status';

  @override
  String get subStatusTrial => 'Trial';

  @override
  String get subRenewsLabel => 'Renews';

  @override
  String get subEndsLabel => 'Ends';

  @override
  String get subManage => 'Manage subscription';

  @override
  String get subManageOpenFailed =>
      'Couldn\'t open the subscription page — you can manage it from the store app.';

  @override
  String get subRestoreDone => 'Your subscription is back ✨';

  @override
  String get subMonthlyAllowanceRow => 'Monthly allowance';

  @override
  String get subAllowanceResetsRow => 'Refreshes on';

  @override
  String get subBuyTokens => 'Buy a credit pack';

  @override
  String get atlasWaitStage1 => 'Placing the planets';

  @override
  String get atlasWaitStage2 => 'Reading the aspects';

  @override
  String get atlasWaitStage3 => 'Writing your report';

  @override
  String get baziWaitStage1 => 'Raising the four pillars';

  @override
  String get baziWaitStage2 => 'Weighing the elements';

  @override
  String get baziWaitStage3 => 'Writing your fate note';

  @override
  String get atlasTitle => 'Birth Chart Analysis';

  @override
  String get appHeadline => 'Your Personal Cosmic Intelligence';

  @override
  String get authNameRequired => 'Enter your name.';

  @override
  String get authInvalidEmail => 'Enter a valid email address.';

  @override
  String get authWrongCredentials => 'Email or password is incorrect.';

  @override
  String get authEmailInUse =>
      'That email is already registered. Try signing in.';

  @override
  String get authTooManyRequests =>
      'Too many attempts. Please try again shortly.';

  @override
  String get authDisabled => 'Email sign-in is currently unavailable.';

  @override
  String get authNetwork => 'Couldn\'t connect. Check your internet.';

  @override
  String get authFailed => 'Something went wrong. Please try again.';

  @override
  String get authAccountExistsOtherMethod =>
      'An account with this email already exists, but it uses a different sign-in method. Sign in the way you first created it (Google, Apple, or email and password).';

  @override
  String get authReauthNeeded =>
      'Your Google account needs to be re-verified on this device. Open your phone\'s Settings → Google and verify the account (remove and re-add it if needed), then try again.';

  @override
  String get displayName => 'Your name';

  @override
  String get passwordRepeat => 'Password (repeat)';

  @override
  String get passwordsDoNotMatch => 'Passwords don\'t match.';

  @override
  String get nameLabel => 'Name';

  @override
  String get signAries => 'Aries';

  @override
  String get signTaurus => 'Taurus';

  @override
  String get signGemini => 'Gemini';

  @override
  String get signCancer => 'Cancer';

  @override
  String get signLeo => 'Leo';

  @override
  String get signVirgo => 'Virgo';

  @override
  String get signLibra => 'Libra';

  @override
  String get signScorpio => 'Scorpio';

  @override
  String get signSagittarius => 'Sagittarius';

  @override
  String get signCapricorn => 'Capricorn';

  @override
  String get signAquarius => 'Aquarius';

  @override
  String get signPisces => 'Pisces';

  @override
  String get atlasPlanetPositions => 'Planetary Positions';

  @override
  String get atlasTraits => 'Character Traits';

  @override
  String get atlasAspects => 'Aspects';

  @override
  String moonIllumination(Object percent) {
    return '$percent% illuminated';
  }

  @override
  String moonIlluminationAsOf(String time) {
    return 'as of $time — the figure shifts through the day';
  }

  @override
  String get reportPostTitle => 'REPORT THIS POST';

  @override
  String get reportUserTitle => 'REPORT THIS USER';

  @override
  String get reportNote => 'Our team reviews every report.';

  @override
  String get reportReasonSpam => 'Spam or misleading content';

  @override
  String get reportReasonHarassment => 'Insults or harassment';

  @override
  String get reportReasonInappropriate => 'Inappropriate or disturbing content';

  @override
  String get reportReasonOther => 'Something else';

  @override
  String get reportSubmitted =>
      'Report received — we\'ll look into it shortly. Thank you.';

  @override
  String get reportFailed => 'The report couldn\'t be sent.';

  @override
  String get aFriend => 'A friend';

  @override
  String get iChingIntro =>
      'The 64-hexagram matrix, three thousand years old. Write your question; the coins fall on real probability, and the moving lines bridge to what comes next.';

  @override
  String get iChingQuestionHint => 'What\'s on your mind?';

  @override
  String get iChingMethodCoins => 'Three Coins 🪙';

  @override
  String get iChingMethodYarrow => 'Yarrow Stalks 🌿';

  @override
  String get iChingCastAction => 'Cast';

  @override
  String get iChingQuestionRequired => 'Write your question first.';

  @override
  String get iChingQuestionInvalid =>
      'The oracle found no question to read in this text — put your intention into a sentence about your own life.';

  @override
  String get iChingCoinsInAir => 'Coins in the air...';

  @override
  String iChingCoinsLanding(int n) {
    return 'Coins landing… $n/6';
  }

  @override
  String iChingHexagramLabel(Object number) {
    return 'HEXAGRAM $number';
  }

  @override
  String iChingTransformedTo(Object name, Object number) {
    return '→ changing into: $name (#$number)';
  }

  @override
  String get iChingOracleNote => 'Rytho\'s note on the cast';

  @override
  String get iChingJudgmentTitle => 'Judgment';

  @override
  String get iChingImageTitle => 'Image';

  @override
  String get iChingMovingTitle => 'Moving Lines';

  @override
  String get iChingLiuYaoTitle => 'Liu Yao';

  @override
  String iChingNuclearLabel(String name, int n) {
    return 'core: $name (#$n)';
  }

  @override
  String get iChingLegend =>
      '○ old yang (9) · × old yin (6) — the turning lines';

  @override
  String get iChingShiTag => 'subject';

  @override
  String get iChingYingTag => 'response';

  @override
  String get iChingTapToSkip => 'Tap to skip the fall';

  @override
  String iChingLineLabel(int n) {
    return 'line $n';
  }

  @override
  String iChingPalaceLabel(String name, int shi, int ying) {
    return 'Palace: $name · subject (shi) line $shi · response (ying) line $ying';
  }

  @override
  String get iChingVoidTag => 'void';

  @override
  String get iChingClashTag => 'clash';

  @override
  String iChingDayLabel(String day) {
    return 'Day of the cast: $day';
  }

  @override
  String iChingTrigramsLabel(String lower, String upper) {
    return '$lower below, $upper above';
  }

  @override
  String get baziHeadline => 'The Four Pillars of Destiny';

  @override
  String baziChineseSign(Object animal, Object dayMaster) {
    return 'Your Chinese sign: $animal · $dayMaster';
  }

  @override
  String get baziFourPillars => 'Four Pillars';

  @override
  String get baziPillarHour => 'HOUR';

  @override
  String get baziPillarDay => 'DAY';

  @override
  String get baziPillarMonth => 'MONTH';

  @override
  String get baziPillarYear => 'YEAR';

  @override
  String get baziElementBalance => 'Elemental Balance';

  @override
  String baziNourish(Object elements) {
    return 'Element to nourish: $elements';
  }

  @override
  String get baziLuckDirectionUnknown =>
      'Gender wasn\'t specified, so the direction of the luck pillars isn\'t computed; both possible sequences are below.';

  @override
  String get baziLuckCandidatesLabel => 'Two possible sequences';

  @override
  String get baziLuckPillars => 'Luck Pillars (Da Yun)';

  @override
  String get baziStrengthTitle => 'Strength Verdict';

  @override
  String get baziRatioLabel => 'support ratio';

  @override
  String get baziFavorable => 'Favorable elements';

  @override
  String get baziUnfavorable => 'Turning into burden';

  @override
  String baziClimateNote(String element) {
    return 'The season\'s climate calls for a regulator: $element';
  }

  @override
  String get baziBasisTitle => 'Basis of the verdict';

  @override
  String get baziSrcMonthCommand => 'Month command';

  @override
  String baziSrcRoot(String pillar, String stem) {
    return '$stem root in the $pillar branch';
  }

  @override
  String baziSrcStem(String pillar, String stem) {
    return '$stem stem in the $pillar';
  }

  @override
  String get baziStarsTitle => 'Stars (Shen Sha)';

  @override
  String get baziNoStars =>
      'No marked stars in this chart — the structure itself speaks.';

  @override
  String baziLuckStartLabel(int years, int months, String date) {
    return 'First period: age ${years}y ${months}m ($date)';
  }

  @override
  String baziThisYear(String label, String tenGod) {
    return 'This year\'s pillar: $label ($tenGod)';
  }

  @override
  String get baziCurrentTag => 'now';

  @override
  String baziAgeRange(Object from, Object to) {
    return 'AGE $from–$to';
  }

  @override
  String get baziFateNote => 'Rytho\'s note on your chart';

  @override
  String get defaultUserName => 'Traveller';

  @override
  String retrogradeChip(Object planet) {
    return '$planet retrograde';
  }

  @override
  String get atlasReadingNote => 'Rytho\'s note on your chart';

  @override
  String get notifications => 'Notifications';

  @override
  String get notifyDaily => 'Daily reading';

  @override
  String get notifyDailyBody =>
      'Let me know each morning when today\'s sky is ready.';

  @override
  String get notifyStreak => 'Streak reminder';

  @override
  String get notifyStreakBody =>
      'A short evening nudge before your streak breaks.';

  @override
  String get notifyFriends => 'Friend notifications';

  @override
  String get notifyFriendsBody =>
      'Invites, accepts and reactions from friends.';

  @override
  String get quietHours => 'Quiet hours';

  @override
  String get quietHoursBody => 'No notifications are sent during this window.';

  @override
  String quietHoursRange(Object from, Object to) {
    return '$from:00 – $to:00';
  }

  @override
  String get quietHoursOff => 'Off';

  @override
  String get quietHoursFrom => 'From';

  @override
  String get quietHoursTo => 'To';

  @override
  String quietHoursRoundedNote(String range) {
    return 'Quiet hours rounded to the hour: $range';
  }

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountTitle => 'You\'re about to delete your account';

  @override
  String get deleteAccountBody =>
      'This cannot be undone. We will delete your birth record, your chats and the notes drawn from them, your journal entries, the people you added, your friendships, your username, every reading generated for you, your AI usage records, your phone verification attempts and the feedback you sent.';

  @override
  String get deleteAccountKeeps =>
      'Two things stay on purpose: your purchase and refund records (financial documents we must keep for five years) and any reports you filed (they concern other people\'s safety).';

  @override
  String get deleteAccountSubscription =>
      'If you have a subscription you must also cancel it in your app store; deleting the account does not stop the billing.';

  @override
  String get deleteAccountConfirmHint => 'Type DELETE to confirm';

  @override
  String get deleteAccountConfirmWord => 'DELETE';

  @override
  String get deleteAccountAction => 'Permanently delete my account';

  @override
  String get deleteAccountFailed =>
      'The account could not be deleted. Please retry.';

  @override
  String get deleteAccountAppleCanceled =>
      'Your account was not deleted: the Apple confirmation was closed. We ask for it so that Rytho\'s Sign in with Apple access can be removed too. To delete your account, try again and complete it.';

  @override
  String get deleteAccountReauth =>
      'For security you need to sign in again. Sign out, sign back in, and repeat this step.';

  @override
  String get cancel => 'Cancel';

  @override
  String get insightDisclaimer =>
      'Rytho is built on real ephemeris calculation, but interpretation is not a method of prediction. Readings are for insight; they are not medical, legal or financial advice. For ages 13 and up.';

  @override
  String get shareReading => 'Share';

  @override
  String get shareText =>
      'Rytho — the AI astrologer that knows your birth chart and watches the sky every day.';

  @override
  String get chatShareCardTitle => 'From my chat with Rytho';

  @override
  String get chatSeedFailed => 'Couldn\'t load the topic.';

  @override
  String get shareCardTagline => 'from real ephemeris calculation';

  @override
  String get shareFailed => 'The share card could not be created.';

  @override
  String get signInWithApple => 'Sign in with Apple';

  @override
  String get consentPrefix => 'By continuing you accept the ';

  @override
  String get consentAnd => ' and the ';

  @override
  String get consentSuffix => '.';

  @override
  String get insightNote =>
      'Readings are for insight; they are not medical, legal or financial advice.';

  @override
  String get ageConfirm => 'I am over 13 years old';

  @override
  String get ageRequired => 'Please confirm your age to continue.';

  @override
  String get passwordRuleHint =>
      'At least 8 characters, with letters and numbers.';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters.';

  @override
  String get passwordTooSimple =>
      'Password must mix letters with numbers or symbols.';

  @override
  String verificationSent(Object email) {
    return 'A verification link was sent to $email. Please check your inbox.';
  }

  @override
  String get useGoogleInstead =>
      'Sign-in failed. Your password may be wrong, or this account may have been created with Google/Apple — try the buttons below.';

  @override
  String get faceReadingTitle => 'Face Reading';

  @override
  String get faceGuideNoFace => 'Bring your face into the frame';

  @override
  String get faceGuideTooFar => 'Move a little closer';

  @override
  String get faceGuideTooClose => 'Move back a little';

  @override
  String get faceGuideOffCentre => 'Centre your face';

  @override
  String get faceGuideTilted => 'Hold your head upright';

  @override
  String get faceGuideReady => 'Ready — hold still';

  @override
  String get faceGuideForehead => 'Uncover your forehead — push your hair back';

  @override
  String get faceScanning => 'Reading your features';

  @override
  String get faceScanNodes => 'Points settling';

  @override
  String get faceScanReading => 'Matching against firasa';

  @override
  String get faceRetake => 'Retake';

  @override
  String get faceConsentTitle => 'Face reading needs your consent';

  @override
  String get faceConsentBody =>
      'Face reading processes the camera frame or a photo you pick from your gallery ON YOUR DEVICE. The image is never sent to a server, never stored anywhere, and is discarded as soon as the reading is made (on the gallery path the copy handed to the app is deleted; your original photo is untouched). Only ratios derived from your features (e.g. forehead-to-chin height) are sent; those numbers cannot identify a person.';

  @override
  String get faceConsentCheckbox =>
      'I consent to my face image being processed on my device.';

  @override
  String get faceConsentContinue => 'I consent — continue';

  @override
  String get faceConsentLearnMore => 'Read the privacy policy';

  @override
  String get faceCameraDenied =>
      'Camera permission was not granted. Face reading needs camera access.';

  @override
  String get faceDetectFailed =>
      'No face detected. Make sure the light is good and your face is inside the frame.';

  @override
  String get faceReadingHint =>
      'The tradition says: a single sign decides nothing. What follows is a tendency, not a fate.';

  @override
  String get faceReadingLockedBody =>
      'A temperament reading from your features opens with Rytho+. The image is processed on your device and never sent anywhere.';

  @override
  String get faceGalleryButton => 'Choose from gallery';

  @override
  String get faceLensButton => 'Flip camera';

  @override
  String get faceStillAnalyzing => 'Analyzing photo…';

  @override
  String get faceStillNoFace =>
      'No face found in the photo. Try a well-lit, front-facing photo.';

  @override
  String get faceStillNoLandmarks =>
      'Facial features couldn\'t be traced. Try a photo where the face is fully visible, facing forward.';

  @override
  String get faceStillSingleFrameNote =>
      'This reading was measured from a single photo frame; a live capture gives steadier results.';

  @override
  String get faceWaitStage1 =>
      'Comparing your proportions with the tradition\'s measures…';

  @override
  String get faceWaitStage2 => 'Searching the firasa sources…';

  @override
  String get faceWaitStage3 => 'Writing your reading…';

  @override
  String get faceConsentSetting => 'Face reading consent';

  @override
  String get faceConsentSettingOn =>
      'Given. The image is processed on your device and never stored.';

  @override
  String get faceConsentSettingOff =>
      'Not given. You will be asked when you open face reading.';

  @override
  String get faceConsentWithdrawTitle => 'Withdraw consent';

  @override
  String get faceConsentWithdrawBody =>
      'Your face reading consent will be withdrawn and any firasa readings produced so far will be deleted. Your other readings (natal, BaZi, daily) are not affected.';

  @override
  String get faceConsentWithdrawConfirm => 'Withdraw and delete';

  @override
  String faceConsentWithdrawn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count readings',
      one: '1 reading',
    );
    return 'Consent withdrawn, $_temp0 deleted.';
  }

  @override
  String get faceOpenSettings => 'Open settings';

  @override
  String get faceCameraDeniedHint =>
      'If you declined, you can enable camera access for Rytho in your phone settings and come back.';

  @override
  String get birthHexagramWaitStage1 => 'Placing the Sun at your birth';

  @override
  String get birthHexagramWaitStage2 => 'Reading the gate and line';

  @override
  String get readingCardReadMore => 'Keep reading';

  @override
  String get openSystemSettings => 'Open Settings';

  @override
  String get save => 'Save';

  @override
  String get edit => 'Edit';

  @override
  String get birthRecordRowSubtitle => 'The basis of every reading';

  @override
  String get languageAndSounds => 'Language and sounds';

  @override
  String get addFriendNeedsUsername =>
      'Pick a username first — you can claim one in the panel below.';

  @override
  String get newConversation => 'New topic';

  @override
  String get chatEmptyTitle => 'Talk with Rytho';

  @override
  String get contactMatchSetting => 'Suggest friends from my contacts';

  @override
  String get contactMatchSettingBody =>
      'Numbers are digested on your phone; your contacts are never uploaded. You only see each other if you\'ve both enabled this.';

  @override
  String get contactMatchPhoneTitle => 'Verify your number first';

  @override
  String get contactMatchPhoneBody =>
      'Matching works through phone numbers. Once you verify yours, people you know can find you — and you can see them.';

  @override
  String get contactMatchVerifyPhone => 'Verify your number';

  @override
  String get contactMatchPermTitle => 'Contacts permission needed';

  @override
  String get contactMatchPermBody =>
      'Reading your contacts is required to find people you know. If you denied it, you can enable it under your phone\'s Settings → Apps → Rytho.';

  @override
  String get contactMatchRetry => 'Try again';

  @override
  String get contactMatchEmptyBody =>
      'No one from your contacts is visible yet. For a match, your friend also needs to verify their number on Rytho and turn on contact matching.';

  @override
  String get contactsTitle => 'Your contacts';

  @override
  String get contactsSearchHint => 'Search your contacts';

  @override
  String get contactsActiveSection => 'On Rytho';

  @override
  String get contactsInviteSection => 'Not visible on Rytho';

  @override
  String get contactsInviteFootnote =>
      'Friends who haven\'t verified their number may also appear here.';

  @override
  String get contactsInvite => 'Invite';

  @override
  String get contactsAlreadyFriend => 'Friend';

  @override
  String get contactsNoSearchResult => 'No one matches your search.';

  @override
  String get contactsInviteNeedsUsername =>
      'Pick a username first to invite people.';

  @override
  String inviteShareMessage(Object link) {
    return 'I\'m inviting you to Rytho — your personal cosmic intelligence. Add me here: $link';
  }

  @override
  String get contactsFindEntry => 'Find friends from your contacts';

  @override
  String contactsFindActive(int count) {
    return '$count on Rytho';
  }

  @override
  String get contactsFindEnable => 'Turn on contact matching';

  @override
  String get contactsFindVerifyPhone => 'Verify your number to find them';

  @override
  String get phoneSectionLabel => 'PHONE';

  @override
  String get phoneNotLinked => 'No verified number';

  @override
  String get phoneVerifyAction => 'Verify';

  @override
  String get phoneChangeAction => 'Change';

  @override
  String get phoneVerifyTitle => 'Verify your phone';

  @override
  String get phoneVerifyBody =>
      'Your number is verified via SMS and linked to your account. If you enable contact matching, friends can find you by this number; it\'s never stored in the clear or shared with anyone.';

  @override
  String get phoneFieldLabel => 'Phone number';

  @override
  String get phoneSendCode => 'Send code';

  @override
  String get phoneCodeLabel => 'SMS code';

  @override
  String get phoneConfirmCode => 'Verify';

  @override
  String phoneCodeSentTo(String number) {
    return 'A code was sent to $number.';
  }

  @override
  String phoneWillSendTo(String number) {
    return 'The code will be sent to $number.';
  }

  @override
  String get phoneResend => 'Resend code';

  @override
  String phoneResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get phoneNoCodeHelp =>
      'If the SMS still hasn\'t arrived it may be a carrier delay. Check your number, resend the code, or skip this step and verify later from Profile → Sign-in methods.';

  @override
  String get phoneRegionUnsupported =>
      'Right now we can only send codes to numbers starting with +90.';

  @override
  String get phoneChangeNumber => 'Change number';

  @override
  String get phoneLinkedDone => 'Your phone is verified.';

  @override
  String get phoneInvalid => 'Include the country code (e.g. +15551234567).';

  @override
  String get phoneCodeWrong => 'That code doesn\'t look right — try again.';

  @override
  String get phoneTakenError => 'This number is linked to another account.';

  @override
  String get phoneTooManyTries => 'Too many attempts. Please try again later.';

  @override
  String get deviceConflictTitle => 'Your account was opened on another device';

  @override
  String deviceConflictBody(String platform, String time) {
    return 'Signed in on $platform at $time. Rytho+ works on one device at a time — tap \"Use on this device\" to continue here.';
  }

  @override
  String get deviceConflictUseHere => 'Use on this device';

  @override
  String get deviceConflictClaimFailed =>
      'Couldn\'t take over this device — check your connection and try again.';

  @override
  String get forceUpdateTitle => 'Update required';

  @override
  String get forceUpdateBody =>
      'This version of Rytho is no longer supported. Update the app to continue — the stars are waiting.';

  @override
  String get forceUpdateAction => 'Update in the store';

  @override
  String get forceUpdateStoreFailed =>
      'Couldn\'t open the store — search for \"Rytho\" in your app store.';

  @override
  String get signInMethodsRow => 'Sign-in methods';

  @override
  String get signInMethodsTitle => 'Sign-in methods';

  @override
  String get signInMethodsBody =>
      'You can attach more than one way to sign in: whichever method you use, you reach the same account.';

  @override
  String get providerPhone => 'Phone';

  @override
  String get linkAction => 'Link';

  @override
  String get linkAlreadyLinked =>
      'This sign-in method is already linked to your account.';

  @override
  String get linkCredentialInUse =>
      'This identity is linked to another account. It needs to be unlinked there first.';

  @override
  String get linkRequiresRecentLogin =>
      'For security this needs a recent sign-in: sign out, sign back in, then try again.';

  @override
  String get linkPasswordDone =>
      'Password saved. You can now sign in with email and password too';

  @override
  String get linkGoogleDone => 'Your Google account is linked ✨';

  @override
  String get setPasswordSection => 'CREATE A PASSWORD';

  @override
  String get setPasswordBody =>
      'Set an email and password to sign in without Google/Apple as well.';

  @override
  String get setPasswordAction => 'Save password';

  @override
  String get changePasswordSection => 'CHANGE PASSWORD';

  @override
  String get changePasswordBody =>
      'Set your new password. The change takes effect immediately.';

  @override
  String get changePasswordAction => 'Change password';

  @override
  String get purchaseItemUnavailable =>
      'This product isn\'t available in the store right now. Try again shortly.';

  @override
  String get purchaseStoreProblem =>
      'The store couldn\'t complete the purchase right now. Please try again in a few minutes.';

  @override
  String get purchaseNotAllowedIos =>
      'In-app purchases aren\'t allowed on this device. Check your Screen Time restrictions (Settings › Screen Time).';

  @override
  String get purchasePending =>
      'Your payment is awaiting approval; Rytho+ / credits will unlock automatically once it\'s approved.';

  @override
  String get tokenStoreTitle => 'Credit Store';

  @override
  String get tokenBalanceLabel => 'YOUR BALANCE';

  @override
  String get tokenUnit => 'credits';

  @override
  String get tokenAllowanceRow => 'Monthly allowance (renews each period)';

  @override
  String get tokenPurchasedRow => 'Purchased (rolls over)';

  @override
  String get tokenRolloverNote =>
      'Your monthly allowance renews each period and doesn\'t roll over; purchased credits never expire.';

  @override
  String get tokenPacksHeader => 'Packs';

  @override
  String tokenPackAmount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count credits',
      one: '1 credit',
    );
    return '$_temp0';
  }

  @override
  String storeBuyWithPrice(String price) {
    return 'Buy — $price';
  }

  @override
  String pricePerCredit(String price) {
    return '$price per credit';
  }

  @override
  String tokenCost(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count credits',
      one: '1 credit',
    );
    return '$_temp0';
  }

  @override
  String get purchasePackRefreshing =>
      'Purchase received; your balance is refreshing.';

  @override
  String get purchaseAlreadyOwnedSubscription =>
      'This account already has an active subscription — restoring your purchases…';

  @override
  String get tokenPurchaseDone => 'Pack added. Enjoy your readings ✨';

  @override
  String get tokenPacksUnavailable => 'Packs can\'t be listed right now';

  @override
  String get tokenPacksUnavailableBody =>
      'Couldn\'t reach the store. Please try again shortly.';

  @override
  String get tokenPacksPlusOnlyTitle => 'Packs are for Rytho+ subscribers';

  @override
  String get tokenPacksPlusOnlyBody =>
      'Everything credits unlock comes with Rytho+. Buying a pack without a subscription would leave you a balance we can\'t yet honour, so we don\'t show the packs here.';

  @override
  String get tokenPacksSeePlus => 'See Rytho+';

  @override
  String get tokenFreeTierWarnTitle =>
      'On the free tier, credits are spent only in chat';

  @override
  String get tokenFreeTierWarnBody =>
      '1 credit = 1 chat message. I Ching, the daily dyad, deep reports and face reading are part of a Rytho+ subscription; credits do not open them. Credits you buy never expire — if you subscribe later you can spend all of them.';

  @override
  String tokenCostsNote(int chat, int iching, int dyad, int deep) {
    return 'Chat message $chat · I Ching $iching · daily dyad $dyad · deep reports and face reading $deep credits. A credit is only spent when a report is newly generated; opening one that is already there spends nothing.';
  }

  @override
  String chatCostNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count credits per message',
      one: '1 credit per message',
    );
    return '$_temp0';
  }

  @override
  String costConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This reading costs $count credits',
      one: 'This reading costs 1 credit',
    );
    return '$_temp0';
  }

  @override
  String get costConfirmBody =>
      'Reopening a ready reading costs nothing; a fresh one does.';

  @override
  String get costConfirmContinue => 'Continue';

  @override
  String get costConfirmCancel => 'Not now';

  @override
  String tokenBalanceChip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count credits',
      one: '1 credit',
    );
    return '$_temp0';
  }

  @override
  String get atlasTraitsSubtitle => 'Your element balance';

  @override
  String get atlasPlanetsSubtitle => 'Positions at your birth';

  @override
  String get atlasFullReport => 'Full report';

  @override
  String get atlasFullReportSubtitle => 'Rytho\'s reading';

  @override
  String atlasAspectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count aspects',
      one: '1 aspect',
      zero: 'No aspects',
    );
    return '$_temp0';
  }

  @override
  String retrogradeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count planets retrograde',
      one: '1 planet retrograde',
    );
    return '$_temp0';
  }

  @override
  String get genericError => 'Something went wrong. Want to try again?';

  @override
  String get birthRecordEditBody =>
      'This is the foundation of your chart: your daily reading, natal report and everything the chat sees are calculated from it. Changing it recalculates your readings.';

  @override
  String get birthCityEmpty => 'Birth city can\'t be empty.';

  @override
  String get birthRecordSaved =>
      'Your birth record is updated. Readings will use your new chart.';

  @override
  String get birthRecordSavedNoChart =>
      'Your birth record is saved, but your chart couldn\'t be calculated right now. Your sign badges will come back once you\'re online.';

  @override
  String get onboardingSavedNoChart =>
      'Your birth details are saved, but your chart could not be calculated right now. Your sign badges will appear once the connection is back.';

  @override
  String get accountSection => 'Account';

  @override
  String get accountSaved => 'Your account details are updated.';

  @override
  String get displayNameEmpty => 'Your name can\'t be empty.';

  @override
  String displayNameTooLong(int count) {
    return 'Your name can be at most $count characters.';
  }

  @override
  String get usernameChangeNote =>
      'If you change it, your old username is released and someone else can take it.';

  @override
  String get emailChangeNote =>
      'Your email is the key to your sign-in; contact support to change it.';

  @override
  String get emailNotVerified => 'Your email isn\'t verified yet.';

  @override
  String get emailVerifyResend => 'Send verification email';

  @override
  String get emailVerifySent =>
      'Verification email sent — check your spam folder too.';

  @override
  String get onboardingSwitchAccount => 'Sign in with a different account';

  @override
  String get signalsSection => 'In your sky today';

  @override
  String get signalWhy => 'What\'s behind this?';

  @override
  String get signalAsk => 'Ask Rytho';

  @override
  String get atlasAskPrefill =>
      'I\'m looking at the readings on my Atlas page. Which one should I lean into today?';

  @override
  String get faceAskPrefill =>
      'I\'ve seen my face reading. What does it say together with today\'s sky?';

  @override
  String get planetsAskPrefill =>
      'I\'m looking at my planet placements. Which one shapes me the most?';

  @override
  String get traitsAskPrefill =>
      'I\'m looking at my traits. Which one stands out these days?';

  @override
  String get aspectsAskPrefill =>
      'I\'m looking at the aspects in my chart. Which one do I feel the most?';

  @override
  String pointAskPrefill(String name) {
    return 'Let\'s talk about my $name placement. How does it show up in me?';
  }

  @override
  String aspectAskPrefill(String label) {
    return 'Let\'s talk about the \"$label\" aspect in my chart. How do I live it?';
  }

  @override
  String askAboutFriendPrefill(String name) {
    return 'Let\'s talk about the dynamic between $name and me.';
  }

  @override
  String signalAskPrefill(String card) {
    return 'My home screen shows this signal today: \"$card\" Can you unpack it for me?';
  }

  @override
  String signalUpcoming(String date) {
    return 'Key day: $date';
  }

  @override
  String get basisSheetTitle => 'Where this signal comes from';

  @override
  String get basisSky => 'In the sky';

  @override
  String get basisNatal => 'In your chart';

  @override
  String get basisAspect => 'Aspect';

  @override
  String get basisOrb => 'Orb (measured)';

  @override
  String get basisMovement => 'Motion';

  @override
  String get basisExact => 'Exact on';

  @override
  String basisHouse(int house) {
    return 'house $house';
  }

  @override
  String get basisFootnote =>
      'Positions come from the ephemeris, the aspect and orb are measured; the reading is built on them.';

  @override
  String get relationshipOpen => 'Explore the relationship';

  @override
  String get relationshipOpenSubtitle =>
      'Where your two charts flow, and where they take work';

  @override
  String relationshipTitle(String name) {
    return 'You & $name';
  }

  @override
  String get relationshipBirthMissing =>
      'This reading needs both birth records. Once your friend completes theirs, this fills in.';

  @override
  String get relationshipBasisTitle => 'What this axis rests on';

  @override
  String get calendarWhyDate => 'Why does this date matter?';

  @override
  String get diaryTitle => 'My Journal';

  @override
  String get profileDiaryRow => 'My journal';

  @override
  String get diaryHint => 'What happened today? One line is enough.';

  @override
  String get diarySave => 'Save';

  @override
  String get diaryEmpty =>
      'No entries yet. Leave important moments as one-liners — when you ask \"what happened this past month?\" in chat, Rytho puts these records next to the sky of those days.';

  @override
  String get diaryDeleted => 'Entry deleted.';

  @override
  String get diaryFootnote =>
      'Your entries are visible only to you and feed Rytho\'s chat memory. Deleting your account deletes them all.';

  @override
  String get diaryDeleteTitle => 'Delete this entry?';

  @override
  String get profileSectionAccount => 'Account';

  @override
  String get profileSectionPrefs => 'Preferences';

  @override
  String get feedbackTitle => 'Feedback';

  @override
  String get feedbackLead =>
      'A bug, an idea or something on your mind — it reaches us directly.';

  @override
  String get feedbackTypeBug => 'Bug 🐞';

  @override
  String get feedbackTypeSuggestion => 'Idea 💡';

  @override
  String get feedbackTypeOther => 'Other';

  @override
  String get feedbackScreenLabel => 'Which screen?';

  @override
  String get feedbackScreenChat => 'Chat';

  @override
  String get feedbackScreenOracle => 'Oracle';

  @override
  String get feedbackScreenOther => 'Other';

  @override
  String get feedbackHint =>
      'What happened, what did you expect? Short is fine.';

  @override
  String get feedbackPrivacy =>
      'Version, device and language are added automatically. Your message is stored with your account so we can send you our reply.';

  @override
  String get feedbackSend => 'Send';

  @override
  String get feedbackThanksTitle => 'Thank you — we\'re reading.';

  @override
  String get feedbackThanksBody => 'You\'ll get our reply as a notification.';

  @override
  String get feedbackClose => 'Close';

  @override
  String get feedbackTooShort => 'Write at least 10 characters.';

  @override
  String get profileFeedback => 'Send feedback';

  @override
  String get feedbackReportThisScreen => 'Report this screen';

  @override
  String get removeFriendConfirmTitle => 'Remove friend';

  @override
  String removeFriendConfirmBody(String name) {
    return '$name leaves your list and shared readings close. You can add them again later.';
  }

  @override
  String get blockUserConfirmTitle => 'Block';

  @override
  String blockUserConfirmBody(String name) {
    return '$name won\'t be able to find you or send invites. You can undo this in Circle settings.';
  }

  @override
  String peopleSlotsOver(int limit, int used) {
    return 'Your limit is $limit; $used people are saved — remove one to add someone new.';
  }

  @override
  String get inviteNeedsUsername =>
      'An invite is waiting — pick a username first.';

  @override
  String get inviteNeedsUsernameAction => 'Pick a username';

  @override
  String friendAcceptedSnack(String name) {
    return '$name is now your friend.';
  }

  @override
  String get diaryThemeCareer => 'Career';

  @override
  String get diaryThemeRelationships => 'Relationships';

  @override
  String get diaryThemeInner => 'Inner life';

  @override
  String get diaryThemeFinance => 'Money';

  @override
  String get reactionHug => 'A hug';

  @override
  String get reactionLuck => 'Good luck';

  @override
  String get reactionCoffee => 'Coffee soon?';

  @override
  String get reactionMiss => 'Miss you';

  @override
  String reactionSheetTitle(String name) {
    return 'Pick a reaction for $name';
  }

  @override
  String get atlasWheelNatal => 'My chart';

  @override
  String get atlasWheelSky => 'Sky right now';

  @override
  String get atlasWheelBiwheel => 'Bi-wheel';

  @override
  String get atlasSkyWheelNote =>
      'The sky is the same for everyone right now; houses and the Ascendant depend on location, so they aren\'t drawn in this view.';

  @override
  String get atlasHourUnknownWheelNote =>
      'Birth time is unknown, so houses and the Ascendant were not drawn; the wheel stays at the planetary level. A noon chart was not invented.';

  @override
  String get atlasBiwheelNote =>
      'Your birth chart inside, the current sky on the outer ring — the bi-wheel astrologers use for transit analysis.';

  @override
  String get atlasSectionAbout => 'About you';

  @override
  String get atlasSectionTime => 'Time';

  @override
  String get atlasSectionOther => 'Other systems';

  @override
  String get atlasFreeChartNote =>
      'Your wheel, placements and aspects are free. Rytho\'s deep reading opens with Rytho+.';

  @override
  String relationshipAskPrefill(String name, String axis) {
    return 'Let\'s talk about the \"$axis\" axis in my relationship with $name.';
  }

  @override
  String houseN(int n) {
    return 'house $n';
  }

  @override
  String get perDay => 'day';

  @override
  String get planetsSectionExtra => 'Additional points';

  @override
  String get planetsFootnote =>
      'Sign, degree and house are computed from the real sky at your birth moment (Swiss Ephemeris). Tap a row to see what that point speaks to.';

  @override
  String get planetDegree => 'Degree in sign';

  @override
  String get planetHouse => 'House';

  @override
  String get planetMotion => 'Motion';

  @override
  String get planetSpeed => 'Daily speed';

  @override
  String get planetRetrograde => 'retrograde';

  @override
  String get pointSheetFootnote =>
      'Degree, house and speed are computed from the real sky at your birth moment (Swiss Ephemeris); the meaning sentence is classical interpretive tradition, not specific to you.';

  @override
  String pointPlacementSentence(String rol, String alan) {
    return '$rol — these play out in $alan.';
  }

  @override
  String get pointAscendant => 'Ascendant';

  @override
  String get traitsElements => 'Element balance';

  @override
  String get traitsModalities => 'Modality balance';

  @override
  String get traitsSetNote =>
      'The count uses the traditional seven (Sun, Moon, Mercury, Venus, Mars, Jupiter, Saturn) plus the Ascendant — eight points.';

  @override
  String get traitsTapHint =>
      'Tap a row to see which points the number comes from.';

  @override
  String traitsMissingElement(String elements) {
    return '$elements is entirely absent from this chart — a missing element is a meaningful statement, a direction rather than a weakness.';
  }

  @override
  String traitsSheetTitle(String name) {
    return '$name — where does this number come from?';
  }

  @override
  String get traitsMembersLabel => 'Points in this group';

  @override
  String get traitsNoMember => 'No point falls in this group.';

  @override
  String get traitsSheetFootnote =>
      'The count runs over the traditional seven plus the Ascendant. Temperament is never read from a single sign; the whole distribution is what counts.';

  @override
  String get traitsUnavailable =>
      'This version did not receive the distribution data. Update the app and try again.';

  @override
  String get elementFire => 'Fire';

  @override
  String get elementEarth => 'Earth';

  @override
  String get elementAir => 'Air';

  @override
  String get elementWater => 'Water';

  @override
  String get elementFireLine =>
      'Fire: moving, daring, starting. Where it dominates there is speed and little patience.';

  @override
  String get elementEarthLine =>
      'Earth: making solid, lasting, trustworthy. Where it dominates there is steadiness and little give.';

  @override
  String get elementAirLine =>
      'Air: thinking, speaking, connecting. Where it dominates ideas are plentiful and depth is hard.';

  @override
  String get elementWaterLine =>
      'Water: feeling, sensing, attaching. Where it dominates emotion runs deep and boundaries run thin.';

  @override
  String get temperamentFire =>
      'Classically, a fire emphasis is called a choleric temperament (hot/dry). That name comes from the distribution above, never from a single sign.';

  @override
  String get temperamentEarth =>
      'Classically, an earth emphasis is called a melancholic temperament (cold/dry). That name comes from the distribution above, never from a single sign.';

  @override
  String get temperamentAir =>
      'Classically, an air emphasis is called a sanguine temperament (hot/moist). That name comes from the distribution above, never from a single sign.';

  @override
  String get temperamentWater =>
      'Classically, a water emphasis is called a phlegmatic temperament (cold/moist). That name comes from the distribution above, never from a single sign.';

  @override
  String get modalityCardinal => 'Cardinal';

  @override
  String get modalityFixed => 'Fixed';

  @override
  String get modalityMutable => 'Mutable';

  @override
  String get modalityCardinalLine =>
      'Cardinal: begins, sets direction, takes the first step.';

  @override
  String get modalityFixedLine =>
      'Fixed: sustains, resists, does not let go easily.';

  @override
  String get modalityMutableLine =>
      'Mutable: adapts, changes shape, can scatter.';

  @override
  String get aspectsGroupTension => 'Hard aspects — tension';

  @override
  String get aspectsGroupFlow => 'Soft aspects — flow';

  @override
  String get aspectsGroupFocus => 'Conjunctions — concentration';

  @override
  String get aspectsGroupOther => 'Other aspects';

  @override
  String get aspectsSortNote =>
      'Tightest orb first in each group: the tighter the orb, the stronger the aspect.';

  @override
  String get aspectMeaningConjunction =>
      'Conjunction: two planets meet at one point; their forces do not separate, they act together.';

  @override
  String get aspectMeaningOpposition =>
      'Opposition: two planets face each other; balance comes only from making room for both.';

  @override
  String get aspectMeaningSquare =>
      'Square: the friction aspect; it presses, but it also moves you — most growth comes from here.';

  @override
  String get aspectMeaningTrine =>
      'Trine: the flow aspect; it comes easily, which is why it is often used without noticing.';

  @override
  String get aspectMeaningSextile =>
      'Sextile: the opportunity aspect; it does not happen by itself, it works when you reach for it.';

  @override
  String get movementMeaningApplying =>
      'Applying: the aspect is moving toward exact, its effect is building.';

  @override
  String get movementMeaningSeparating =>
      'Separating: the aspect has perfected, its effect is fading.';

  @override
  String get aspectSheetFootnote =>
      'Aspect and orb are measured from the real sky at your birth moment; the explanation is classical interpretive tradition.';

  @override
  String get house1 =>
      'House 1: how you show up, your body, the first impression you leave.';

  @override
  String get house2 =>
      'House 2: what you own, your resources, your sense of worth.';

  @override
  String get house3 =>
      'House 3: speaking, learning, siblings, the near circle.';

  @override
  String get house4 => 'House 4: roots, home, family, the safe place inside.';

  @override
  String get house5 => 'House 5: creating, play, love, self-expression.';

  @override
  String get house6 => 'House 6: daily order, work routine, care of the body.';

  @override
  String get house7 =>
      'House 7: one-to-one relationships, partnership, the other.';

  @override
  String get house8 => 'House 8: shared resources, transformation, deep bonds.';

  @override
  String get house9 =>
      'House 9: search for meaning, belief, far places, teaching.';

  @override
  String get house10 => 'House 10: career, public standing, the goal.';

  @override
  String get house11 =>
      'House 11: friendships, community, plans for the future.';

  @override
  String get house12 =>
      'House 12: withdrawal, the unconscious, what stays behind.';

  @override
  String get roleSun =>
      'Sun: your core identity, life energy, what you move toward.';

  @override
  String get roleMoon =>
      'Moon: your emotional need, your habits, how you feel safe.';

  @override
  String get roleMercury =>
      'Mercury: how you think and how you put it into words.';

  @override
  String get roleVenus => 'Venus: what you love, how you bond, what you value.';

  @override
  String get roleMars => 'Mars: how you act, your anger and your wanting.';

  @override
  String get roleJupiter =>
      'Jupiter: where you grow, your optimism, your search for meaning.';

  @override
  String get roleSaturn =>
      'Saturn: your responsibility, your limit, where you master with time.';

  @override
  String get roleUranus =>
      'Uranus: where you break the rule and sudden change enters.';

  @override
  String get roleNeptune =>
      'Neptune: your dreaming, your intuition, where boundaries thin out.';

  @override
  String get rolePluto =>
      'Pluto: your field of transformation, power and rebirth.';

  @override
  String get roleChiron =>
      'Chiron: where you were wounded and learned, in time, to heal.';

  @override
  String get roleLilith =>
      'Lilith: the part of you that never settles or tames.';

  @override
  String get roleNorthNode =>
      'North Node: the direction you are called to develop.';

  @override
  String get roleSouthNode =>
      'South Node: what already comes easily and must be left behind.';

  @override
  String get atlasReportPreparing => 'Rytho is writing your reading…';

  @override
  String get retrogradeMeaning =>
      'R retrograde: the planet appears to move backward. Classically, progress in that area turns inward rather than outward — a time to review and gather.';

  @override
  String get calendarLockedReading => 'This day\'s reading opens with Rytho+.';

  @override
  String get calendarOtherEvents => 'Other movements';

  @override
  String get calendarStripTitle => 'The next 30 days';

  @override
  String get storyPause => 'Pause';

  @override
  String get storyPlay => 'Play';

  @override
  String get relationshipReadingTitle => 'Rytho\'s reading of this bond';

  @override
  String get relationshipReadingLocked =>
      'The measured axes and their supporting aspects are open to everyone. Rytho\'s reading of what they mean for the two of you opens with Rytho+.';

  @override
  String get moonUncertainNote =>
      'Your birth time is not on file, so the Moon\'s sign may be off by one — the Moon travels about 13° a day.';

  @override
  String moonUncertainAlt(String alt) {
    return 'Depending on the birth time it could also be $alt.';
  }

  @override
  String get birthMissingTitle => 'Your birth record is incomplete';

  @override
  String get birthMissingBody =>
      'Your birth date and city are needed to calculate your chart. This is not a Rytho+ lock — once the record is complete, the wheel, placements and aspects open for free.';

  @override
  String get birthMissingAction => 'Complete your birth record';

  @override
  String get circleTitle => 'My circle';

  @override
  String get circleFriendsSection => 'Friends on Rytho';

  @override
  String get circlePeopleSection => 'People you added';

  @override
  String get circleEmptyTitle => 'Add your partner or child';

  @override
  String get circleEmptyBody =>
      'See the charts of the people close to you and the bond between you. They don\'t need the app.';

  @override
  String get addChooserTitle => 'Who are you adding?';

  @override
  String get addChooserFriend => 'Someone on Rytho';

  @override
  String get addChooserFriendBody =>
      'By username, contacts or an invite link. Both sides confirm; you can send reactions and see each other\'s streaks.';

  @override
  String get addChooserPerson => 'I\'ll add them myself';

  @override
  String get addChooserPersonBody =>
      'Your partner, your child, someone close. You enter their birth details.';

  @override
  String get peopleAddTitle => 'Add a person';

  @override
  String get peopleEditTitle => 'Edit person';

  @override
  String get peopleLabelField => 'Name';

  @override
  String get peopleLabelHint => 'What do you call them?';

  @override
  String get peopleLabelNote =>
      'This name never leaves your phone. Only the birth details are stored on the server; Rytho refers to them as \"your partner\", \"your child\".';

  @override
  String get peopleRelation => 'Relationship';

  @override
  String get peopleConsent =>
      'You are entering this person\'s birth details on their behalf. The record is visible only to you, no other user can reach it, and it is deleted together with your account.';

  @override
  String get peopleSaved => 'Saved';

  @override
  String get peopleRemove => 'Remove person';

  @override
  String get peopleRemoveConfirm =>
      'Delete this person and their chart? This cannot be undone.';

  @override
  String get peopleRemoved => 'Removed';

  @override
  String peopleSlots(int used, int limit) {
    return '$used/$limit people';
  }

  @override
  String get peopleHourUnknownBadge =>
      'Birth time unknown — Ascendant and houses were not calculated.';

  @override
  String get relationPartner => 'My partner';

  @override
  String get relationChild => 'My child';

  @override
  String get relationParent => 'My parent';

  @override
  String get relationSibling => 'My sibling';

  @override
  String get relationFriend => 'My friend';

  @override
  String get relationWork => 'My colleague';

  @override
  String get relationOther => 'Close to me';

  @override
  String get relationshipTodayLabel => 'Today\'s sky between you';

  @override
  String get relationshipTodayQuiet =>
      'No notable transit touches the two of you today — a quiet day.';

  @override
  String relationshipTodayAskPrefill(String name) {
    return 'Let\'s talk about today\'s sky touching me and $name.';
  }

  @override
  String chatMentionAttached(String name) {
    return 'Context attached: $name';
  }

  @override
  String get chatMentionClearTooltip => 'Remove context';

  @override
  String get chatMentionEmpty => 'No match — add people from My Circle';

  @override
  String get discoveryComplete =>
      'Today\'s three discoveries done ✨ The sky resets tomorrow.';

  @override
  String get discoveryRingTooltip =>
      'Daily discovery ring: open the sky · talk to Rytho · look at someone in your circle';

  @override
  String get forgotPasswordTitle => 'Reset your password';

  @override
  String get forgotPasswordBody =>
      'Enter your account\'s email address and we\'ll send you a reset link.';

  @override
  String get forgotPasswordSend => 'Send the link';

  @override
  String get forgotPasswordSentTitle => 'Link on its way';

  @override
  String forgotPasswordSentBody(String email) {
    return 'If this address is registered, we sent a reset link to $email. The link is valid for a short while.';
  }

  @override
  String get forgotPasswordSpamHint =>
      'If it doesn\'t arrive within a few minutes, check your spam folder.';

  @override
  String get forgotPasswordResend => 'Send again';

  @override
  String forgotPasswordResendWait(int seconds) {
    return 'Send again (${seconds}s)';
  }

  @override
  String get notifPermissionOffTitle =>
      'Notifications are off in system settings';

  @override
  String get notifPermissionOffBody =>
      'Until you allow Rytho notifications in your phone\'s settings, the preferences here have no effect: Settings → Apps → Rytho → Notifications.';

  @override
  String get chatOpenLabel => 'Chat with Rytho';

  @override
  String get trialBannerTitle => 'Your trial is active';

  @override
  String trialBannerDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
    );
    return 'All Rytho+ features unlocked — $_temp0.';
  }

  @override
  String get trialBannerLastDay =>
      'All Rytho+ features unlocked — today is the last day.';

  @override
  String chartWheelSemantics(int rings, int aspects) {
    String _temp0 = intl.Intl.pluralLogic(
      rings,
      locale: localeName,
      other: '$rings rings',
      one: '1 ring',
    );
    String _temp1 = intl.Intl.pluralLogic(
      aspects,
      locale: localeName,
      other: '$aspects aspects',
      one: '1 aspect',
    );
    return 'Astrology wheel: $_temp0, $_temp1. Details in the position table below.';
  }

  @override
  String chartLegendInner(String label) {
    return 'Inner: $label';
  }

  @override
  String chartLegendOuter(String label) {
    return 'Outer: $label';
  }

  @override
  String get chartLegendYou => 'you';

  @override
  String get chartLegendSkyNow => 'the sky right now';

  @override
  String get chartFilterAll => 'All';

  @override
  String get chartFilterMajor => 'Major';

  @override
  String get chartFilterApplying => 'Applying';

  @override
  String get chartFilterHard => 'Hard';

  @override
  String get chartFilterSoft => 'Soft';

  @override
  String get chartFilterMinors => 'Minors';

  @override
  String chartOrbLabel(int orb) {
    return 'Orb ≤ $orb°';
  }

  @override
  String get chartHouseSystem => 'Placidus houses · Tropical zodiac';

  @override
  String get chartHourUnknownNote =>
      'Birth time unknown, so houses, Ascendant and axes are not drawn.';

  @override
  String get chartAspectarianTitle => 'ASPECT GRID';

  @override
  String get chartPositionsTitle => 'POSITIONS';

  @override
  String get chartApplyingLetter => 'A';

  @override
  String get chartSeparatingLetter => 'S';

  @override
  String get chartHousesYou => 'Houses: you';

  @override
  String chartHousesOther(String name) {
    return 'Houses: $name';
  }

  @override
  String chartModeSynastry(String name) {
    return 'You & $name';
  }

  @override
  String chartAskPrefillNatal(String name) {
    return 'I\'m looking at the chart wheel for $name. What should I pay most attention to?';
  }

  @override
  String get chartAskPrefillOwn =>
      'I\'m looking at my own chart wheel. What should I pay most attention to?';

  @override
  String get chartAskPrefillSky =>
      'I\'m looking at the current sky wheel. What affects me most today?';

  @override
  String get chartAskPrefillBiwheel =>
      'I\'m looking at my chart layered with today\'s sky. Which touch stands out?';

  @override
  String chartAskPrefillSynastry(String name) {
    return 'I\'m looking at the synastry wheel with $name. Which bond defines us most?';
  }

  @override
  String get chartMovementLegend => 'A applying · S separating';

  @override
  String get chartLoading => 'Preparing the wheel…';

  @override
  String get chartSelectionClear => 'Clear selection';

  @override
  String chartAsOf(String time) {
    return 'as of $time';
  }

  @override
  String chartAskPrefill(String title) {
    return 'I\'m inspecting the $title wheel right now. What stands out in this chart?';
  }

  @override
  String get innerCalendarAskPrefill =>
      'I\'ve opened my inner season. Can you unpack what my progressed Moon is saying in this stretch?';

  @override
  String get birthHexagramAskPrefill =>
      'I\'ve opened my birth gate. Can you unpack how this gate works in my character?';

  @override
  String get solarReturnAskPrefill =>
      'I\'ve opened my solar return. Can you unpack what this year brings me?';

  @override
  String get baziAskPrefill =>
      'I\'ve opened my BaZi chart. Can you unpack what my four pillars say?';

  @override
  String iChingAskPrefill(String question) {
    return 'I asked the oracle this: \"$question\" Can you unpack the answer it gave?';
  }

  @override
  String get chartShareTooltip => 'Share the wheel';

  @override
  String get chartExpandTooltip => 'Open in Chart Inspector';

  @override
  String get chartSelectedDetail => 'Details →';

  @override
  String get chartOuterLoading => 'Loading the outer ring…';

  @override
  String get aspectSubjectSun => 'your sense of self';

  @override
  String get aspectSubjectMoon => 'your feelings';

  @override
  String get aspectSubjectMercury => 'your mind';

  @override
  String get aspectSubjectVenus => 'the way you love';

  @override
  String get aspectSubjectMars => 'your drive';

  @override
  String get aspectSubjectJupiter => 'your urge to grow';

  @override
  String get aspectSubjectSaturn => 'your sense of duty';

  @override
  String get aspectSubjectUranus => 'your need for freedom';

  @override
  String get aspectSubjectNeptune => 'your imagination';

  @override
  String get aspectSubjectPluto => 'your power to transform';

  @override
  String get aspectSubjectChiron => 'your old wound';

  @override
  String get aspectSubjectLilith => 'your untamed side';

  @override
  String get aspectSubjectNorthNode => 'your direction of growth';

  @override
  String get aspectSubjectSouthNode => 'your familiar ground';

  @override
  String get aspectSubjectAscendant => 'the face you show';

  @override
  String get aspectSubjectMidheaven => 'your aims';

  @override
  String get aspectSubjectDescendant => 'what you seek in others';

  @override
  String get aspectSubjectImumCoeli => 'your roots';

  @override
  String aspectSentenceConjunction(String a, String b) {
    return '$a and $b are fused; they act together.';
  }

  @override
  String aspectSentenceOpposition(String a, String b) {
    return '$a and $b face each other; balance comes when both get room.';
  }

  @override
  String aspectSentenceSquare(String a, String b) {
    return '$a and $b rub against each other; it pushes you, and moves you forward.';
  }

  @override
  String aspectSentenceTrine(String a, String b) {
    return '$a and $b flow easily; a natural gift.';
  }

  @override
  String aspectSentenceSextile(String a, String b) {
    return '$a and $b open doors for each other; it works once you act.';
  }

  @override
  String get aspectStrengthVeryStrong => 'Very strong';

  @override
  String get aspectStrengthStrong => 'Strong';

  @override
  String get aspectStrengthMild => 'Mild';

  @override
  String get traitsLevelNone => 'None';

  @override
  String get traitsLevelLow => 'Low';

  @override
  String get traitsLevelBalanced => 'Balanced';

  @override
  String get traitsLevelStrong => 'Strong';

  @override
  String traitsCountCaption(String sayi, String toplam) {
    return '$sayi of your $toplam key points';
  }

  @override
  String get traitsLevelNote =>
      'Nothing here is good or bad: what is strong comes easily to you, what is low asks for conscious effort.';

  @override
  String get elementFireWord => 'passion';

  @override
  String get elementEarthWord => 'grounding';

  @override
  String get elementAirWord => 'ideas';

  @override
  String get elementWaterWord => 'feeling';

  @override
  String get modalityCardinalWord => 'starting';

  @override
  String get modalityFixedWord => 'persistence';

  @override
  String get modalityMutableWord => 'adapting';

  @override
  String get signClimateAri =>
      'a climate of beginnings: courage, first steps, acting for yourself.';

  @override
  String get signClimateTau =>
      'a climate of settling: calm, the body, building what lasts.';

  @override
  String get signClimateGem =>
      'a climate of curiosity: learning, talking, new connections.';

  @override
  String get signClimateCan =>
      'a climate of home: family, shelter, returning to your roots.';

  @override
  String get signClimateLeo =>
      'a climate of light: creating, being seen, living from the heart.';

  @override
  String get signClimateVir =>
      'a climate of order: tidying up, fine-tuning, daily rhythm.';

  @override
  String get signClimateLib =>
      'a climate of relating: balance, partnership, beauty.';

  @override
  String get signClimateSco =>
      'a climate of depth: transformation, intimacy, facing what is hidden.';

  @override
  String get signClimateSag =>
      'a climate of horizons: travel, the search for meaning, expanding.';

  @override
  String get signClimateCap =>
      'a climate of building: responsibility, goals, the reward of effort.';

  @override
  String get signClimateAqu =>
      'a climate of freedom: the new, community, your own path.';

  @override
  String get signClimatePis =>
      'a climate of dissolving: intuition, imagination, letting go.';

  @override
  String get progPhaseMeaningNewMoon =>
      'New Moon phase: a cycle begins; a time to plant seeds.';

  @override
  String get progPhaseMeaningWaxingCrescent =>
      'Crescent phase: growing what you started, pushing past first resistance.';

  @override
  String get progPhaseMeaningFirstQuarter =>
      'First quarter: decision and action; forks in the road.';

  @override
  String get progPhaseMeaningWaxingGibbous =>
      'Gibbous phase: fine-tuning, letting your effort ripen.';

  @override
  String get progPhaseMeaningFullMoon =>
      'Full Moon phase: becoming visible, fruit and realisation.';

  @override
  String get progPhaseMeaningWaningGibbous =>
      'Disseminating phase: sharing what you have learned.';

  @override
  String get progPhaseMeaningLastQuarter =>
      'Last quarter: reviewing, letting go of what is no longer needed.';

  @override
  String get progPhaseMeaningWaningCrescent =>
      'Closing phase: rest, digestion, preparing for a new cycle.';

  @override
  String get innerJourneyTitle => 'Your inner journey';

  @override
  String get innerJourneyNow => 'Now';

  @override
  String innerJourneyNowTitle(String burc) {
    return 'Your inner climate: $burc';
  }

  @override
  String innerJourneyNextWhen(String tarih) {
    return 'From $tarih';
  }

  @override
  String innerJourneyNextTitle(String burc) {
    return 'Next inner climate: $burc';
  }

  @override
  String innerJourneyMilestone(String tarih) {
    return 'Turning point · $tarih';
  }

  @override
  String get solarReturnJourneyTitle => 'Your journey this year';

  @override
  String solarReturnJourneyMonth(String ay) {
    return 'You are in month $ay of the journey';
  }

  @override
  String get solarReturnRealmsTitle =>
      'The realms you\'ll travel most this year';

  @override
  String solarReturnRealmPlanets(String gezegenler) {
    return 'Here: $gezegenler';
  }

  @override
  String get solarReturnRealmsNoTime =>
      'Without your birth time the year\'s realms can\'t be computed; the year\'s emotional climate is still below.';

  @override
  String get solarReturnMoonClimate => 'The year\'s emotional climate';

  @override
  String get readingFullToggle => 'The full reading';

  @override
  String get aiConsentTitle => 'Send your data to Google Gemini?';

  @override
  String get aiConsentIntro =>
      'Your personal readings, chat replies and face reading are generated by a third-party AI service — Google\'s Gemini API. When you use these features, the following data is sent to Google:';

  @override
  String get aiConsentDataChart =>
      'Information calculated from your birth chart: planet positions, houses, aspects, transits and BaZi pillars. Some readings (e.g. the Year Chart) also include the solar return date and city names.';

  @override
  String get aiConsentDataChat =>
      'Your chat messages and the recent part of the conversation; the question you ask the I Ching.';

  @override
  String get aiConsentDataMemory =>
      'Short notes drawn from your chats to get to know you, your mood trend and your latest journal notes.';

  @override
  String get aiConsentDataPeople =>
      'Your name (in relationship readings); your friends\' display names and signs (in relationship readings and chat). For people you added, only the relationship type (e.g. \"your partner\") and their chart are sent; the name you gave them stays on your phone.';

  @override
  String get aiConsentDataFace =>
      'For face reading, ratios derived from your facial features — your photo is not sent.';

  @override
  String get aiConsentPurpose =>
      'This data is sent only to generate the reading and the reply you asked for, the personal line in your morning and midday notifications, and the evening question. General sign horoscopes are also written with AI, but none of your data goes into them.';

  @override
  String get aiConsentDeclineInfo =>
      'If you don\'t allow it, personal readings, chat and face reading stay off and this data is not sent to Gemini. Your birth chart, the sky, the calendar and friend features keep working. You can change your mind anytime under Profile > Privacy.';

  @override
  String get aiConsentPrivacyLink => 'Details in the privacy policy';

  @override
  String get aiConsentAgree => 'I agree';

  @override
  String get aiConsentNotNow => 'Not now';

  @override
  String get aiConsentDeclinedSnack =>
      'AI features are off; your data is not being sent to Gemini. You can turn them on anytime under Profile > Privacy.';

  @override
  String get aiConsentSaveFailed =>
      'Your permission couldn\'t be saved, so nothing has been sent yet. Check your connection and try again.';

  @override
  String get aiConsentOffBody =>
      'This section is generated with Google Gemini and you haven\'t allowed your data to be sent yet. Nothing is sent until you do.';

  @override
  String get aiConsentTurnOn => 'Turn on AI';

  @override
  String get aiConsentSetting => 'AI (Google Gemini)';

  @override
  String get aiConsentSettingOn =>
      'On. Your data is sent to Gemini for readings and chat.';

  @override
  String get aiConsentSettingOff =>
      'Off. Your data is not sent to Gemini; personal readings and chat don\'t work.';

  @override
  String get aiConsentWithdrawTitle => 'Withdraw AI permission';

  @override
  String get aiConsentWithdrawBody =>
      'From now on your data won\'t be sent to Gemini; personal readings, chat and face reading will turn off. Readings already generated and your chat history are not deleted by this.';

  @override
  String get aiConsentWithdrawConfirm => 'Withdraw';

  @override
  String get aiConsentWithdrawn => 'AI permission withdrawn.';
}

/// Plus özellik kataloğu — kilit kartı, bedel rozeti ve paywall'ın TEK
/// özellik sözlüğü.
///
/// ## Neden var
/// Ölçüldü (2026-10-10): aynı özellik üç yerde üç ayrı kimlikle anılıyordu.
/// `PlusLockedCard` çağrılarında emoji + ARB çifti elle yazılıyordu, Atlas
/// karolarında emoji ikinci kez, paywall fayda listesinde üçüncü kez — ve
/// üçü ayrışmıştı: I Ching karoda `🪙`, paywall'da `☯️`; Doğum Kapısı bir
/// yerde `☯` (VS16'sız, Android'de tek renk glif) öbür yerde `☯️`.
/// Sunucu adı ise hiçbir yerde yoktu: 402'nin `X-Paywall-Feature` başlığı
/// istemcide okunmuyor, bedel rozeti `costs[...]` anahtarını elle yazmak
/// zorunda kalırdı ve o anahtar yanlışsa rozet sessizce çizilmezdi.
///
/// Katalog dört kimliği tek üyede toplar: bedel anahtarı, kapı adı, emoji,
/// metin çifti. Bekçi (`test/ozellik_katalogu_test.dart`) sunucuyla
/// eşitliği DİSKTEN ölçer — `backend/core/wallet.py` `TOKEN_COSTS` ve
/// `require_plus("…")` çağrıları.
///
/// ## İki sunucu adı neden ayrı
/// Sunucu aynı özelliği iki sözlükle anıyor ve ikisi her zaman örtüşmüyor:
/// bedel tablosu `face` derken kapı `firasa`, bedel `natal` derken kapı
/// `natal_report`; günlük okumanın kapısı var (`personal_daily`) ama bedeli
/// yok; sohbetin bedeli var ama kapısı yok (ücretsiz katman kotayla).
/// Tek alana sıkıştırmak ikisinden birini yalanlamak olurdu.
library;

import '../../l10n/app_localizations.dart';

enum PlusOzellik {
  /// Kişiye özel günlük okuma — `require_plus("personal_daily")` kapısı
  /// var, `TOKEN_COSTS`ta anahtarı YOK (ölçüldü, `api/reports.py:201`):
  /// abonelikle gelir, jeton düşmez.
  daily(kapiAdi: 'personal_daily', emoji: '🌙'),

  /// Doğum haritası raporu.
  natal(sunucuAdi: 'natal', kapiAdi: 'natal_report', emoji: '🗺️'),

  /// Arkadaşla günlük ikili dinamik.
  dyad(sunucuAdi: 'dyad', kapiAdi: 'dyad', emoji: '💞'),

  /// Sohbet — ücretsiz katmanda günlük kota, abonede jeton; `require_plus`
  /// kapısı YOK.
  chat(sunucuAdi: 'chat', emoji: '💬'),

  /// BaZi dört sütun.
  bazi(sunucuAdi: 'bazi', kapiAdi: 'bazi', emoji: '🀄'),

  /// Sinastri (ikili harita karşılaştırması).
  synastry(sunucuAdi: 'synastry', kapiAdi: 'synastry', emoji: '🔗'),

  /// Yüz okuma (firaset).
  face(sunucuAdi: 'face', kapiAdi: 'firasa', emoji: '👁️'),

  /// Doğum Kapısı / heksagramı. Emoji VS16'lı (`☯️`): VS16'sız `☯`
  /// Android'de tek renk metin glifi olarak çiziliyordu, yanındaki
  /// renkli emojilerle hizası ve ağırlığı tutmuyordu.
  birthHexagram(
      sunucuAdi: 'birth_hexagram', kapiAdi: 'birth_hexagram', emoji: '☯️'),

  /// Yıl haritası (güneş dönüşü).
  solarReturn(
      sunucuAdi: 'solar_return', kapiAdi: 'solar_return', emoji: '🌞'),

  /// İç takvim (progresyonlar).
  progressions(
      sunucuAdi: 'progressions', kapiAdi: 'progressions', emoji: '🌗'),

  /// İ Ching çekimi.
  iching(sunucuAdi: 'iching', kapiAdi: 'iching', emoji: '🪙'),

  /// On kişilik çevre — kontenjan `people_service.py`'de, 402'si
  /// `X-Paywall-Reason: people` ile gelir; ne bedel tablosunda ne
  /// `require_plus` listesinde.
  people(emoji: '👥'),

  /// Transit takvimi okuması — uç herkese açık (`api/astrology.py`:
  /// "hesap bedava, yorum paralı"), kilit olay başına `locked: true`.
  transitCalendar(emoji: '🗓️');

  const PlusOzellik({this.sunucuAdi, this.kapiAdi, required this.emoji});

  /// `backend/core/wallet.py` `TOKEN_COSTS` anahtarı — `/billing/wallet`
  /// yanıtındaki `costs` haritasının anahtarı da bu. `null`: özelliğin
  /// jeton bedeli yok.
  final String? sunucuAdi;

  /// `require_plus("…")` özellik adı — 402'nin `X-Paywall-Feature`
  /// başlığında dönen ad. `null`: uç `require_plus` arkasında değil.
  final String? kapiAdi;

  /// Renkli emoji (`RythoText.emoji` ile çizilir).
  final String emoji;

  /// Sunucunun söylediği adla üyeyi bulur — iki sözlükten de.
  ///
  /// 402 başlığı (`X-Paywall-Feature`) kapı adını, cüzdan yanıtı bedel
  /// anahtarını taşıyor; çağıran hangisini tuttuğunu bilmek zorunda
  /// kalmasın.
  static PlusOzellik? bul(String? ad) {
    if (ad == null) return null;
    for (final o in values) {
      if (o.sunucuAdi == ad || o.kapiAdi == ad) return o;
    }
    return null;
  }

  /// Kilit kartı / karo başlığı.
  String baslik(AppLocalizations l10n) => switch (this) {
        daily => l10n.personalReadingLocked,
        natal => l10n.natalLockedTitle,
        dyad => l10n.relationshipReadingTitle,
        chat => l10n.benefitChatTitle,
        bazi => l10n.baziLockedTitle,
        // Sinastriye özel kilit anahtarı YOK; en yakın mevcut çift paywall
        // faydasındaki "BaZi ve sinastri". Ayrı anahtar D7'de.
        synastry => l10n.benefitBaziTitle,
        face => l10n.faceReadingTitle,
        birthHexagram => l10n.birthHexagramTitle,
        solarReturn => l10n.solarReturnTitle,
        progressions => l10n.innerCalendarTitle,
        iching => l10n.iChingLockedTitle,
        people => l10n.benefitPeopleTitle,
        transitCalendar => l10n.calendarStripTitle,
      };

  /// Kilit kartının gövdesi: özelliğin NE olduğu ve Rytho+ ile açıldığı.
  String kilitGovdesi(AppLocalizations l10n) => switch (this) {
        daily => l10n.personalReadingLockedBody,
        natal => l10n.natalLockedBody,
        dyad => l10n.relationshipReadingLocked,
        chat => l10n.benefitChatBody,
        bazi => l10n.baziLockedBody,
        synastry => l10n.benefitBaziBody,
        face => l10n.faceReadingLockedBody,
        birthHexagram => l10n.birthHexagramLockedBody,
        solarReturn => l10n.solarReturnLockedBody,
        progressions => l10n.innerCalendarLockedBody,
        iching => l10n.iChingLockedBody,
        people => l10n.benefitPeopleBody,
        transitCalendar => l10n.calendarLockedReading,
      };
}

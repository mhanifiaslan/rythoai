import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/izin_kapisi.dart' show IzinKapaliBandi;

/// Sessiz saat ucu: `TimeOfDay` → sunucunun saat çözünürlüğü (dakika atılır).
///
/// Saf ve ADLANDIRILMIŞ: dakika eskiden `_pick` içinde sessizce düşüyordu —
/// 21:40 seçen kullanıcı 21:00 yazıldığını hiçbir yerde görmüyordu.
/// Yuvarlama tek yerde; dakika varsa çağıran bunu SÖYLER ([sessizSaatNotu]).
int sessizSaatYuvarla(TimeOfDay saat) => saat.hour;

/// "22:00 – 08:00" — sunucudaki tam saat çiftinin ekrandaki yazımı.
String sessizSaatAraligi(AppLocalizations l10n, int from, int to) =>
    l10n.quietHoursRange(
        from.toString().padLeft(2, '0'), to.toString().padLeft(2, '0'));

/// Yuvarlama notu: iki uçtan biri tam saat değilse YAZILAN aralığı söyler;
/// ikisi de tam saatse null (söylenecek fark yok). Yuvarlama iki ucu
/// eşitlerse sessiz saat kapalı sayılır (sunucu kuralı) ve not bunu söyler.
String? sessizSaatNotu(
    AppLocalizations l10n, TimeOfDay baslangic, TimeOfDay bitis) {
  if (baslangic.minute == 0 && bitis.minute == 0) return null;
  final from = sessizSaatYuvarla(baslangic);
  final to = sessizSaatYuvarla(bitis);
  return l10n.quietHoursRoundedNote(
      from == to ? l10n.quietHoursOff : sessizSaatAraligi(l10n, from, to));
}

/// Saat seçici — TEST DİKİŞİ (sihirbazın `SihirbazSeciciler`i ile aynı
/// gerekçe): `showTimePicker` testte kadranla sürülemez, `helpText` ise
/// ölçülmesi gereken şey (iki seçici iki ayrı başlık taşımalı).
typedef SessizSaatSecici = Future<TimeOfDay?> Function(
    BuildContext context, TimeOfDay baslangic, String helpText);

/// Tercih yazıcı — TEST DİKİŞİ; üretimde `setNotificationPref` (Firestore).
typedef TercihYazici = Future<void> Function(String alan, Object? deger);

/// Bildirim tercihleri bölümü (Profil → Bildirimler).
///
/// Üç anahtar ve bir sessiz saat aralığı. Hepsi `users/{uid}` dokümanına
/// yazılır; toplu gönderimi yapan sunucu tam olarak aynı alanları okur
/// (backend/services/notification_service.py).
///
/// Varsayılan AÇIK: kullanıcı sistem iznini zaten verdiyse günlük okumanın
/// bildirimini istiyor demektir. Sessiz saat varsayılanı 22:00–08:00 —
/// bu kategoride gece bildirimi, uygulamanın silinmesinin en hızlı yolu.
///
/// Plakanın ETİKETİ YOK: sayfanın AppBar'ı zaten "Bildirimler" diyor ve
/// aynı sözcük plakanın üstünde ikinci kez duruyordu (ölçüldü 2026-10-10,
/// çift başlık). Satırlar `SettingsRow` — profil ve gizlilik sayfasıyla
/// aynı dil; buradaki `_Toggle` kopyası kalktı.
class NotificationSettings extends ConsumerWidget {
  const NotificationSettings({
    super.key,
    this.saatSec = _saatSec,
    this.yaz = setNotificationPref,
  });

  @visibleForTesting
  final SessizSaatSecici saatSec;

  @visibleForTesting
  final TercihYazici yaz;

  static Future<TimeOfDay?> _saatSec(
          BuildContext context, TimeOfDay baslangic, String helpText) =>
      showTimePicker(
          context: context, initialTime: baslangic, helpText: helpText);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(notificationPrefsProvider);

    return Plaque(
      padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
      child: Column(children: [
        // OS izni reddedilmişse dürüst band + ayarlara giden düğme (D3
        // `IzinKapaliBandi`); eski `_PermissionBanner` yol tarifi veriyordu.
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: RythoSpace.lg),
          child: IzinKapaliBandi(),
        ),
        SettingsRow(
          icon: Icons.wb_twilight_rounded,
          title: l10n.notifyDaily,
          subtitle: l10n.notifyDailyBody,
          trailing: Switch(
            value: prefs.daily,
            onChanged: (v) => yaz('notifyDaily', v),
          ),
        ),
        const Divider(height: 1, indent: RythoSpace.lg),
        SettingsRow(
          icon: Icons.local_fire_department_outlined,
          title: l10n.notifyStreak,
          subtitle: l10n.notifyStreakBody,
          trailing: Switch(
            value: prefs.streak,
            onChanged: (v) => yaz('notifyStreak', v),
          ),
        ),
        const Divider(height: 1, indent: RythoSpace.lg),
        SettingsRow(
          icon: Icons.favorite_outline_rounded,
          title: l10n.notifyFriends,
          subtitle: l10n.notifyFriendsBody,
          trailing: Switch(
            value: prefs.friends,
            onChanged: (v) => yaz('notifyFriends', v),
          ),
        ),
        const Divider(height: 1, indent: RythoSpace.lg),
        _QuietHours(prefs: prefs, saatSec: saatSec, yaz: yaz),
      ]),
    );
  }
}

/// Sessiz saat aralığı seçimi.
///
/// Başlangıç ve bitiş eşitse sessiz saat KAPALI sayılır — sunucu da aynı
/// kuralı uyguluyor. Eşitliği "24 saat sessiz" saymak, kullanıcının hiç
/// bildirim almaması demek olurdu ve bunu fark etmesi imkânsız olurdu.
///
/// Satır dokunulur, değer sağda (`SettingsRow.value`): eski hâl aynı
/// satıra altın bir `TextButton` koyuyordu ve dar ekranda taşıyordu;
/// profil satırlarıyla aynı dil hem taşmayı hem ikinci düğme stilini
/// kaldırır.
class _QuietHours extends StatelessWidget {
  const _QuietHours({
    required this.prefs,
    required this.saatSec,
    required this.yaz,
  });

  final NotificationPrefs prefs;
  final SessizSaatSecici saatSec;
  final TercihYazici yaz;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsRow(
      icon: Icons.bedtime_outlined,
      title: l10n.quietHours,
      subtitle: l10n.quietHoursBody,
      value: prefs.quietDisabled
          ? l10n.quietHoursOff
          : sessizSaatAraligi(l10n, prefs.quietFrom, prefs.quietTo),
      onTap: () => _sec(context),
    );
  }

  Future<void> _sec(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);

    // İki seçici iki ayrı başlık: eskiden ikisi de "Sessiz saatler" diyordu
    // ve kullanıcı ikinci kadranın bitişi mi yoksa aynı sorunun tekrarı mı
    // olduğunu bilemiyordu.
    final baslangic = await saatSec(context,
        TimeOfDay(hour: prefs.quietFrom, minute: 0), l10n.quietHoursFrom);
    if (baslangic == null || !context.mounted) return;

    final bitis = await saatSec(
        context, TimeOfDay(hour: prefs.quietTo, minute: 0), l10n.quietHoursTo);
    if (bitis == null) return;

    // Sunucu saat çözünürlüğünde çalışıyor; dakika yuvarlanır ve yuvarlama
    // SÖYLENİR — sessizce atılan dakika, kullanıcının "21:40 dedim"
    // hatırasıyla sunucunun 21:00'ini ayrıştırıyordu.
    await yaz('quietFrom', sessizSaatYuvarla(baslangic));
    await yaz('quietTo', sessizSaatYuvarla(bitis));
    final not = sessizSaatNotu(l10n, baslangic, bitis);
    if (not != null) mesajci.showSnackBar(SnackBar(content: Text(not)));
  }
}

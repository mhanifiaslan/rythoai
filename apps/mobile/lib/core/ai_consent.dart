/// Üçüncü taraf yapay zeka (Google Gemini) aktarım onayının SUNUCU kaydı.
///
/// ## Model (sahip kararı 2026-10-22)
///
/// Onay YALNIZ kurulumun ilk adımında alınır: şartlar kutusunun altındaki
/// ayrı, zorunlu ikinci kutu (`onboarding_wizard.dart`, `_KarsilamaAdimi`).
/// İki kutu da işaretlenmeden "Devam" açılmaz, yani kurulumu bitiren herkes
/// onu işaretlemiştir. Uygulamanın başka hiçbir yerinde sorulmaz, geri alma
/// anahtarı yoktur (geri alma yolu hesabı silmek — gizlilik metni) ve hiçbir
/// özellik ona kapılı değildir: istemcide kapı yok, sunucu kapıları da aynı
/// kararla kalkar (403, `ai=0`, bildirimde teknik satır).
///
/// Bu dosyada kalan tek şey KANIT: `POST /api/v1/account/ai-consent`
/// (`users/{uid}/private/aiConsent`).
///
/// ## Kayıt neden hesaba bağlı bir bayrakla
///
/// Kanıt yalnız kutuyu İŞARETLEYEN kişi için yazılır. Kurulum iki kutu
/// işaretliyken bittiğinde o hesap için "bekliyor" bayrağı konur;
/// [ensureAiConsentRecorded] YALNIZ bu bayrak varsa istek atar ve başarıda
/// bayrağı siler (bir daha ağa çıkmaz). 1.20.0+53'ten güncelleyen kullanıcı
/// kutuyu hiç görmedi — bayrağı olmadığı için onun adına ASLA kayıt
/// yazılmaz; yazılsaydı sunucuda vermediği bir onay varmış gibi dururdu.
///
/// Bayrak cihaz değil HESAP başınadır: aynı cihazda kaydı düşmüş bir hesaptan
/// çıkıp başka bir hesapla girilirse, ikinci hesap birincinin bayrağıyla
/// istek atmaz (istek oturumdaki hesabın kimliğiyle gider ve ona kayıt
/// yazardı).
///
/// Hata kurulumu DURDURMAZ: bayrak kalır, AppShell her açılışta bir kez
/// daha dener (şartlar kaydının KT2 deseni, `consent.dart`). Uç sunucuda
/// tam yazımdır, tekrar zararsız.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// Onay metninin sürümü — backend `AI_CONSENT_VERSION` ile elle senkron.
///
/// Gönderilen veri kategorisi ya da sağlayıcı değişince İKİSİ BİRLİKTE
/// artar. Metin düzeltmesi artırmaz.
const int kAiConsentVersion = 1;

String _bekliyor(String uid) => 'ai-consent-pending-v$kAiConsentVersion-$uid';

/// Kurulum iki kutu işaretliyken bitti: kaydı [uid] adına borçlanır ve hemen
/// bir kez dener. Hiçbir hata dışarı sızmaz — kurulum bu yüzden düşmez.
Future<void> aiOnayiKurulumdaVerildi(Dio dio, {required String uid}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bekliyor(uid), true);
  } catch (e) {
    debugPrint('Yapay zeka onayı bayrağı yazılamadı: $e');
  }
  await ensureAiConsentRecorded(dio, uid: uid);
}

/// Borçlanmış kaydı sunucuya yazar; bayrak yoksa HİÇBİR şey yapmaz.
///
/// [uid] oturumdaki hesap: bayrak o hesaba ait değilse istek atılmaz.
/// Hata İSTEĞİ DÜŞÜRMEZ — bir sonraki açılış yeniden dener.
Future<void> ensureAiConsentRecorded(Dio dio, {required String? uid}) async {
  if (uid == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_bekliyor(uid)) ?? false)) return;
    await dio.post('/api/v1/account/ai-consent',
        data: {'version': kAiConsentVersion});
    await prefs.remove(_bekliyor(uid));
  } catch (e) {
    debugPrint('Yapay zeka onayı kaydı ertelendi (sonraki açılışta '
        'denenecek): $e');
  }
}

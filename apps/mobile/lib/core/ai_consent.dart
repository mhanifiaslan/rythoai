/// Üçüncü taraf AI (Google Gemini) aktarım onayı — U06, Apple 5.1.2(i).
///
/// ## Neden var
///
/// Kişisel okumalar, sohbet ve yüz okuması Google'ın Gemini API'siyle
/// üretiliyor ve bunun için haritadan hesaplanan bilgiler, mesajlar, günlük
/// notları gibi kişisel veriler Google'a gidiyor. Apple 5.1.2(i) bunu
/// yapmadan ÖNCE sağlayıcıyı adıyla anan, gönderilen veriyi sayan ayrı bir
/// ekranda açık izin istiyor; gizlilik politikasında yazması yetmiyor.
///
/// ## "Bir kez gösterildi" bayrağı YOK
///
/// Onay verilene kadar ekran her açılışta ve her AI özelliği açılışında
/// yeniden gelir. Forumdaki red vakası tam olarak `hasSeenConsent`
/// kısayoluydu: ekran bir kez görülüp kapatılınca bir daha sorulmuyor,
/// veri ise gönderilmeye devam ediyordu. Burada tutulan tek şey kararın
/// KENDİSİ (sunucuda), "gördü mü" değil.
///
/// ## Kayıt nerede
///
/// Sunucuda, `users/{uid}/private/aiConsent` (istemciye kapalı — kayıt
/// uydurulamaz). İstemci durumu `GET /account/ai-consent` ile sorar ve
/// cihazda önbellekler; önbellek YALNIZ sunucuya ulaşılamadığında
/// kullanılır, sunucunun cevabının önüne geçmez.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/profile/legal_page.dart'
    show LegalPage, privacyPolicySections;
import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../widgets/atlas_widgets.dart' show GoldButton;
import '../widgets/glass.dart';
import 'api.dart' show apiProvider, rythoNavigatorKey;
import 'providers.dart' show authStateProvider;

/// Onay metninin sürümü — backend `AI_CONSENT_VERSION` ile elle senkron.
///
/// Gönderilen veri kategorisi ya da sağlayıcı değişince İKİSİ BİRLİKTE
/// artar; sunucu eski sürüm onayını geçerli saymaz ve ekran yeniden
/// sorulur. Metin düzeltmesi artırmaz (rıza yorgunluğu).
const int kAiConsentVersion = 1;

/// Sunucunun AI uçlarındaki 403'ü işaretlediği başlık (bkz.
/// backend/core/ai_consent.py). İşaret metne gömülemez: `detail` kullanıcıya
/// olduğu gibi basılan düz metin.
const String kAiConsentHeader = 'x-ai-consent';

/// AI özelliği onay olmadan açıldı — hata DEĞİL, bir durum.
///
/// Sağlayıcılar bunu fırlatır ki ekran "bir şeyler ters gitti" yerine
/// "yapay zeka kapalı, açmak ister misin?" kartını göstersin. Yeniden
/// deneme politikası bunu denemez (`rythoRetry`): durum ağla değil
/// kullanıcının kararıyla değişir.
class AiOnayiGerekli implements Exception {
  const AiOnayiGerekli();
}

/// Hata AI onayı eksikliğinden mi? İstemci kapısı ([AiOnayiGerekli]) ya da
/// sunucunun işaretli 403'ü — ikincisi, başka cihazda geri alınmış onayın
/// bu cihazda henüz bilinmediği durumdur.
bool aiOnayHatasiMi(Object? hata) {
  if (hata is AiOnayiGerekli) return true;
  if (hata is DioException) {
    final yanit = hata.response;
    return yanit?.statusCode == 403 &&
        yanit?.headers.value(kAiConsentHeader) == 'required';
  }
  return false;
}

// ---------------------------------------------------------------------------
// Durum
// ---------------------------------------------------------------------------

/// Sunucu kaydının okunup yazıldığı yer — testte sahtelenir.
abstract class AiOnayDeposu {
  /// Güncel sürüm için onay var mı? Okunamazsa FIRLATIR (önbelleğe düşülür).
  Future<bool> durum();

  Future<void> ver(int surum);

  /// Geri alma ya da "Şimdi değil" — sunucuda `granted: false`.
  Future<void> geriAl();
}

class SunucuAiOnayDeposu implements AiOnayDeposu {
  SunucuAiOnayDeposu(this._dio);

  final Dio _dio;

  @override
  Future<bool> durum() async {
    final yanit =
        await _dio.get<Map<String, dynamic>>('/api/v1/account/ai-consent');
    return yanit.data?['granted'] == true;
  }

  @override
  Future<void> ver(int surum) =>
      _dio.post('/api/v1/account/ai-consent', data: {'version': surum});

  @override
  Future<void> geriAl() => _dio.delete('/api/v1/account/ai-consent');
}

final aiOnayDeposuProvider = Provider<AiOnayDeposu>(
    (ref) => SunucuAiOnayDeposu(ref.watch(apiProvider)));

/// Onayın sahibi olan hesap. Ayrı sağlayıcı: hesap değişince durum
/// yeniden okunur (önceki hesabın onayı yenisine TAŞINMAZ) ve testler
/// Firebase kurmadan bir kimlik verebilir.
final aiOnayHesabiProvider = Provider<String?>(
    (ref) => ref.watch(authStateProvider).value?.uid);

String _onbellekAnahtari(String uid) => 'ai-consent-v$kAiConsentVersion-$uid';

/// AI aktarım onayı verildi mi?
///
/// `true` YALNIZ güncel sürüm için verilmiş sunucu kaydıyla (ya da sunucuya
/// ulaşılamazken o kaydın önbelleğiyle) olur. Okunamayan ve önbelleği
/// olmayan durum `false`tur: bilmediğimiz onayı "var" saymak, onay
/// vermemiş birinin verisini göndermek olurdu.
class AiOnayDenetleyici extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final uid = ref.watch(aiOnayHesabiProvider);
    if (uid == null) return false;
    final depo = ref.watch(aiOnayDeposuProvider);
    try {
      final verildi =
          await depo.durum().timeout(const Duration(seconds: 10));
      unawaited(_onbellegeYaz(uid, verildi));
      return verildi;
    } catch (_) {
      // Ağ yokken son bilinen karar. Önbellek de yoksa kapalı taraf.
      return await _onbellektenOku(uid) ?? false;
    }
  }

  /// Onayı sunucuya yazar. Yazılamazsa FIRLATIR ve durum DEĞİŞMEZ: ispatı
  /// sunucuda olmayan bir onayla veri göndermeye başlamak, onay kaydının
  /// var olma sebebini boşa çıkarırdı.
  Future<void> ver() async {
    await ref.read(aiOnayDeposuProvider).ver(kAiConsentVersion);
    final uid = ref.read(aiOnayHesabiProvider);
    if (uid != null) await _onbellegeYaz(uid, true);
    state = const AsyncData(true);
  }

  /// Ayarlardan geri alma. Sunucuya yazılamazsa FIRLATIR — kullanıcı
  /// "geri aldım" sanıp sunucu hâlâ onaylı bilmesin. Yerel durum yine de
  /// ÖNCE kapanır: bu cihaz bundan sonra AI isteği atmaz.
  Future<void> geriAl() async {
    await _yereldeKapat();
    await ref.read(aiOnayDeposuProvider).geriAl();
  }

  /// "Şimdi değil". Sunucu kaydı en iyi çaba: yazılamasa da bu cihaz AI
  /// isteği atmaz; kayıt, arka plandaki sabah bildiriminin de AI'sız
  /// kalması için (sunucu açık "hayır"ı eşikten bağımsız uygular).
  Future<void> simdiDegil() async {
    await _yereldeKapat();
    try {
      await ref.read(aiOnayDeposuProvider).geriAl();
    } catch (e) {
      debugPrint('AI onayı reddi sunucuya yazılamadı: $e');
    }
  }

  /// Sunucu 403 ile "onay yok" dedi: bu cihazın bildiği bayat.
  Future<void> sunucuReddetti() => _yereldeKapat();

  Future<void> _yereldeKapat() async {
    final uid = ref.read(aiOnayHesabiProvider);
    if (uid != null) await _onbellegeYaz(uid, false);
    state = const AsyncData(false);
  }

  Future<void> _onbellegeYaz(String uid, bool deger) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onbellekAnahtari(uid), deger);
    } catch (_) {}
  }

  Future<bool?> _onbellektenOku(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_onbellekAnahtari(uid));
    } catch (_) {
      return null;
    }
  }
}

final aiOnayProvider =
    AsyncNotifierProvider<AiOnayDenetleyici, bool>(AiOnayDenetleyici.new);

/// AI uçlarına istek atan sağlayıcıların ortak kapısı: onay yoksa
/// [AiOnayiGerekli] fırlatır. `watch` ile — onay verildiği an bekleyen
/// sağlayıcılar kendiliğinden yeniden kurulur, ekranda "tekrar dene"
/// gerekmez.
Future<void> aiOnayiGerektir(Ref ref) async {
  if (!await ref.watch(aiOnayProvider.future)) throw const AiOnayiGerekli();
}

/// Yumuşak uçların sorgu parametresi: onay yoksa `ai=0` (sunucu yorum
/// katmanını atlar, hesabı yine döner). Onay varken parametre gönderilmez
/// — eski istemcinin isteğiyle bayt bayt aynı kalsın.
Future<Map<String, dynamic>?> aiSorguParametresi(Ref ref) async =>
    await ref.watch(aiOnayProvider.future) ? null : const {'ai': '0'};

// ---------------------------------------------------------------------------
// Kapı
// ---------------------------------------------------------------------------

/// Açık sayfanın sonucu: iki yer aynı anda sorarsa (açılış + bildirimden
/// açılan sohbet) ikinci sayfa AÇILMAZ, ilkinin cevabını bekler.
Future<bool>? _acikSayfa;

/// Açılış sorusunun bittiği an — başka açılış modalları (tanıtım paywall'ı,
/// bildirim izni) bunu bekler ki kullanıcı üst üste iki modalla
/// karşılaşmasın.
Future<void>? _acilisSorusu;

Future<void> aiAcilisSorusuBekle() => _acilisSorusu ?? Future.value();

/// Modül durumunu sıfırlar — yalnız testler: sayfası açıkken sökülen bir
/// test ağacı `_acikSayfa`yı hiç tamamlanmayan bir future'da bırakır ve
/// sonraki testin sayfası hiç açılmaz.
@visibleForTesting
void aiOnayKapisiniSifirla() {
  _acikSayfa = null;
  _acilisSorusu = null;
}

/// Bir AI özelliği açılırken çağrılır. Onay varsa hemen `true`; yoksa onay
/// sayfasını gösterir ve kullanıcının kararını döndürür.
Future<bool> aiOnayiIste(BuildContext context, WidgetRef ref) async {
  bool verildi;
  try {
    verildi = await ref
        .read(aiOnayProvider.future)
        .timeout(const Duration(seconds: 12));
  } catch (_) {
    verildi = false;
  }
  if (verildi) return true;
  if (!context.mounted) return false;
  return showAiOnaySayfasi(context);
}

/// Uygulama açılışında (AppShell) bir kez: onay yoksa sayfa gelir. [once]
/// açılışın kendi sahnesi (Büyük Üçlü perdesi) — önce o oynar, sayfa
/// perdenin üstüne binmez.
Future<void> aiAcilisSorusu(BuildContext context, WidgetRef ref,
    {Future<void> Function()? once}) async {
  final bitti = Completer<void>();
  _acilisSorusu = bitti.future;
  try {
    if (once != null) await once();
    if (!context.mounted) return;
    await aiOnayiIste(context, ref);
  } finally {
    bitti.complete();
  }
}

/// Onay sayfasını açar; kullanıcı "Kabul ediyorum" derse `true`.
///
/// [sunucuReddetti]: sayfa sunucunun 403'ü üzerine açılıyor — bu cihazın
/// "onaylı" bilgisi bayat. Sayfa açılırken yerel durum önce KAPATILIR;
/// kapatılmasaydı "Kabul ediyorum" durumu true→true yazar, Riverpod
/// değişiklik görmez ve 403'le düşmüş sağlayıcılar hiç yeniden kurulmazdı.
Future<bool> showAiOnaySayfasi(BuildContext context,
    {bool sunucuReddetti = false}) {
  final acik = _acikSayfa;
  if (acik != null) return acik;
  final sonuc = _sayfayiAc(context, sunucuReddetti: sunucuReddetti);
  _acikSayfa = sonuc;
  return sonuc.whenComplete(() => _acikSayfa = null);
}

Future<bool> _sayfayiAc(BuildContext context,
    {required bool sunucuReddetti}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  // Sayfa kapandıktan sonra `context` sökülmüş olabilir; kap ÖNCEDEN alınır.
  final kap = ProviderScope.containerOf(context, listen: false);
  final karar = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Dışarı dokunup geçmek bir karar değil: kullanıcı iki düğmeden birini
    // seçer. `isDismissible`/`enableDrag` Android'in geri tuşunu KAPATMAZ —
    // o yol aşağıda (null sonuç) "Şimdi değil" olarak kaydedilir.
    isDismissible: false,
    enableDrag: false,
    backgroundColor: RythoColors.inkLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(color: RythoColors.glassStroke),
    ),
    builder: (_) => AiOnaySayfasi(sunucuReddetti: sunucuReddetti),
  );
  if (karar == true) return true;
  if (karar == null) {
    // Geri tuşu (ya da düğmesiz herhangi bir kapanış). "Şimdi değil" düğmesi
    // `false` döndürür ve kaydı kendisi yapar — burada yalnız null yol
    // kaydedilir, çift yazım olmaz. Kaydedilmeseydi sunucu yalnız "kayıt
    // yok" görürdü; o durum eşik yükseltilene kadar uçlarda, ekransız eski
    // pakette (sürüm aynası <= 45) arka plan bildiriminde de İZİNLİ
    // sayılıyor — aynı hesabın eski paketli bir cihazı haritayı Gemini'ye
    // göndermeyi sürdürür, hemen altındaki "verin gönderilmiyor" mesajını
    // yalanlardı. Açık "hayır" ise sunucuda eşikten bağımsız her yolda
    // geçerli.
    unawaited(kap.read(aiOnayProvider.notifier).simdiDegil());
  }
  // Dostça söylenir, suçlamadan: ne kapandı, ne çalışmaya devam ediyor,
  // nereden açılır. "Verilerin yine de gönderiliyor" izlenimi VERMEZ.
  messenger?.showSnackBar(SnackBar(content: Text(l10n.aiConsentDeclinedSnack)));
  return false;
}

/// Sunucu 403 + işaret döndü (apiProvider interceptor'ı çağırır).
///
/// Interceptor `apiProvider`ın içinde yaşıyor ve `aiOnayProvider` ona
/// bağlı; oradan bu sağlayıcıya dokunmak Riverpod halkası kurardı (bkz.
/// B10). Bu yüzden durum güncellemesi sayfanın KENDİ `ref`i ile yapılır.
void aiOnayiSunucuIstedi() {
  final navigator = rythoNavigatorKey.currentState;
  final context = navigator?.overlay?.context;
  if (context == null || _acikSayfa != null) return;
  showAiOnaySayfasi(context, sunucuReddetti: true);
}

// ---------------------------------------------------------------------------
// Sayfa
// ---------------------------------------------------------------------------

/// Onay sayfası. Sağlayıcıyı ADIYLA anar, gönderilen veriyi kategori
/// kategori sayar, ne için kullanıldığını ve reddetmenin neyi kapattığını
/// söyler. Metinlerin her cümlesi backend'de ölçülerek yazıldı (hangi
/// prompt neyi taşıyor) — gizlilik politikasının "Yapay zeka ile işleme"
/// bölümüyle birlikte değişir.
class AiOnaySayfasi extends ConsumerStatefulWidget {
  const AiOnaySayfasi({super.key, this.sunucuReddetti = false});

  /// Bkz. [showAiOnaySayfasi].
  final bool sunucuReddetti;

  @override
  ConsumerState<AiOnaySayfasi> createState() => _AiOnaySayfasiState();
}

class _AiOnaySayfasiState extends ConsumerState<AiOnaySayfasi> {
  bool _kaydediliyor = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    if (widget.sunucuReddetti) {
      // Sayfanın KENDİ ref'i: interceptor'dan bu sağlayıcıya dokunmak
      // apiProvider halkası kurardı (B10). Kare sonrası: initState bir
      // build evresidir ve orada sağlayıcı durumu değiştirmek Riverpod'da
      // hata.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(ref.read(aiOnayProvider.notifier).sunucuReddetti());
        }
      });
    }
  }

  Future<void> _kabul(AppLocalizations l10n) async {
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      await ref.read(aiOnayProvider.notifier).ver();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      // Hata sayfada kalır (yüz rızası formuyla aynı ders): SnackBar
      // kaybolup gidiyordu ve kullanıcı neden geri atıldığını anlamıyordu.
      if (mounted) {
        setState(() {
          _kaydediliyor = false;
          _hata = l10n.aiConsentSaveFailed;
        });
      }
    }
  }

  Future<void> _simdiDegil() async {
    // Sayfa hemen kapanır; kayıt arka planda (en iyi çaba).
    unawaited(ref.read(aiOnayProvider.notifier).simdiDegil());
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final veriler = [
      l10n.aiConsentDataChart,
      l10n.aiConsentDataChat,
      l10n.aiConsentDataMemory,
      l10n.aiConsentDataPeople,
      l10n.aiConsentDataFace,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.auto_awesome_rounded,
                color: RythoColors.copper, size: 28),
            const SizedBox(height: 10),
            Text(l10n.aiConsentTitle,
                style: RythoText.display(20), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            Text(l10n.aiConsentIntro,
                style: RythoText.body(13.5, height: 1.5)),
            const SizedBox(height: 10),
            GlassPanel(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final v in veriler)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('•  ',
                              style: RythoText.body(13,
                                  color: RythoColors.copper)),
                          Expanded(
                            child: Text(v,
                                style: RythoText.body(12.5,
                                    color: RythoColors.parchment,
                                    height: 1.45)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(l10n.aiConsentPurpose,
                style: RythoText.body(12.5,
                    color: RythoColors.parchmentDim, height: 1.5)),
            const SizedBox(height: 8),
            Text(l10n.aiConsentDeclineInfo,
                style: RythoText.body(12.5,
                    color: RythoColors.parchmentDim, height: 1.5)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LegalPage(
                    title: l10n.privacyPolicy,
                    sections: privacyPolicySections(
                        Localizations.localeOf(context).languageCode),
                  ),
                )),
                child: Text(l10n.aiConsentPrivacyLink),
              ),
            ),
            if (_hata != null) ...[
              Text(_hata!,
                  style: RythoText.body(12.5, color: RythoColors.madder)),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            GoldButton(
              text: l10n.aiConsentAgree,
              busy: _kaydediliyor,
              onPressed: _kaydediliyor ? null : () => _kabul(l10n),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _kaydediliyor ? null : _simdiDegil,
              child: Text(l10n.aiConsentNotNow, style: RythoText.label(12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// AI kapalıyken AI bölümünün yerine duran kart — hata kartı DEĞİL.
///
/// Kırmızı ünlem ve "tekrar dene" burada yanlış çare olurdu: tekrar
/// denemek hiçbir şeyi değiştirmez, değiştiren şey kullanıcının kararı.
/// Kart ne olduğunu söyler ve tek dokunuşla onay sayfasını açar.
class AiOnayKapaliKarti extends ConsumerWidget {
  const AiOnayKapaliKarti({super.key, this.onGranted});

  /// Onay verilince çağrılır — sağlayıcı değil ekran-yerel yükleme
  /// yapan ekranlar (ilişki, ikili okuma) yeniden yüklemek için kullanır.
  /// Sağlayıcılar onayı izlediği için kendiliğinden yeniden kurulur.
  final VoidCallback? onGranted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_awesome_outlined,
                  size: 18, color: RythoColors.copper),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.aiConsentOffBody,
                    style: RythoText.body(13,
                        color: RythoColors.parchmentDim, height: 1.45)),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                if (await aiOnayiIste(context, ref)) onGranted?.call();
              },
              child: Text(l10n.aiConsentTurnOn),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yıldız Yolu — ilk kurulum sihirbazı (O3).
///
/// Eski tek ekranlı onboarding'in yerini alır. Tasarım ilkeleri:
///
/// * **Adım başına tek soru** — bilişsel yük düşük, tamamlama yüksek.
/// * **Takımyıldız ilerleme** — her adım bir yıldız yakar; ilk yıldız
///   yanmış başlar (endowed progress). Son yıldız kayıt sahnesinde yanar:
///   takımyıldız, harita gerçekten çizilirken tamamlanır.
/// * **Anında mikro-ödül** — adım geçişinde yıldız pop'u + hafif haptik.
/// * **Dürüst atlama** — "Bilmiyorum" utandırmayan birinci sınıf seçenek;
///   neyin değişeceği bir cümleyle söylenir. Suçlayıcı dil yok. Ama hiçbir
///   ADIM atlanamaz: her adım bir karar ister ("bilmiyorum", "belirtmedim",
///   "şimdi değil" de birer karardır) — seçilmeyen şey beyan edilmez,
///   sessizce varsayılan da yazılmaz (eski akış cinsiyeti `female`
///   önseçiyor, saatsiz doğumu 12:00 yazma riski taşıyordu).
/// * **Rıza baştan** — Google/Apple girişlerinde bugüne dek hiçbir onay
///   kutusu yoktu; ilk adım açık kabul kutusuyla bu boşluğu kapatır ve
///   kabul sunucuda ispatlanabilir kayda geçer (POST /account/consent).
///   Altında AYRI ve zorunlu ikinci kutu: verilerin üçüncü taraf yapay zeka
///   hizmetlerine gönderilmesine izin (sahip kararı 2026-10-22; metin
///   sağlayıcı adı taşımaz, 2026-10-23 — hizmetin adı Gizlilik
///   Politikası'nda). Yapay zeka onayının sorulduğu TEK yer burası; kaydı
///   POST /account/ai-consent (`core/ai_consent.dart`), kurulum GERÇEKTEN
///   bittikten (doğum kaydı yazıldıktan) sonra gider.
/// * **Zirve sonda** — kayıt sırasında StagedWaiting (gerçek iş), sonra
///   mevcut Büyük Üçlü perdesi (AppShell köprüsü, R12-B1 düzeni korunur).
///
/// Telefon adımı sihirbazda DEĞİL (K6, 2026-10-10): OT4'te herkese
/// açılmıştı ama rehber eşleşmesi kurulumun işi değil — numara, ihtiyaç
/// anında Çevrem'de (`contacts_screen` JIT) ve Giriş yöntemleri'nde
/// doğrulanır; sihirbaz yalnız haritayı çizmek için gerekeni sorar.
///
/// Taslak KALICI DEĞİL (bilinçli): akış 60-90 saniye; bayat "rıza
/// işaretliydi" taslağı rıza kanıtını zayıflatırdı.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ai_consent.dart' show aiOnayiKurulumdaVerildi;
import '../../core/analytics.dart';
import '../../core/api.dart';
import '../../core/birth_record.dart';
import '../../core/city_directory.dart' show CityPick;
import '../../core/consent.dart' show ensureConsentRecorded;
// kTermsConsentVersion artık core/consent.dart'ta yaşıyor (KT2) — sürüm
// tek yerden yönetilir, AppShell'deki tekrar deneme de aynı sabiti görür.
import '../../core/providers.dart'
    show OnboardOutcome, justOnboardedProvider;
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/city_search_field.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/dogum_formu.dart';
import '../../widgets/izin_kapisi.dart';
import '../../widgets/motion.dart';
import '../../widgets/onay.dart';
import '../../core/notifications.dart'
    show ensureNotificationPermissionAsked;
import '../profile/legal_page.dart';
import 'constellation_progress.dart';

/// Sihirbaz adımları — sırası ürün sözleşmesidir ve testle sabitlidir
/// (K6: telefon çıktı; altı adımın her biri karar ister, hiçbiri
/// atlanamaz).
const List<String> kOnboardingSteps = [
  'welcome', 'date', 'time', 'place', 'gender', 'notify',
];

/// Profil dokümanının ilk yazımı için zaman aşımı.
///
/// NEDEN: Firestore `set()` çevrimdışı TAZE kurulumda (önbelleksiz, henüz
/// hiç bağlanmamış istemci) sonsuza dek bekleyebiliyor — kayıt sahnesi
/// döner, kullanıcı ne hata görür ne tekrar deneyebilir. 15 sn, zayıf
/// bağlantıda gerçek yazıma yetecek kadar uzun; "takıldı" hissinden önce
/// dürüst hatayı gösterecek kadar kısa.
const Duration kYazmaZamanAsimi = Duration(seconds: 15);

/// Kayıt sahnesinde iki aşama metni arası. Değer D2 öncesinden olduğu
/// gibi (ölçüldüğü gibi); çıplak süre adlandırıldı. `RythoMotion
/// .asamaAraligi` (2600 ms) uzun bekleyişler için — harita yazımı ondan
/// kısa sürüyor, üç aşama o aralıkla işten uzun kalırdı.
const Duration kKayitAsamaAraligi = Duration(milliseconds: 1600);

/// Adım ilerleyebilir mi — düğme durumunun TEK kaynağı, saf ve test
/// edilebilir.
///
/// Bilinmeyen adım `false`: yeni bir adım eklenip kuralı unutulursa düğme
/// kapalı kalır ve eksik ilk denemede görünür; `true` olsaydı adım sessizce
/// atlanabilir olurdu.
///
/// `welcome` İKİ kutuyu birden ister: şartlar ([riza]) ve yapay zeka
/// aktarımı ([aiRiza]). Biri yetmez — ikincisi, onayın sorulduğu tek yer
/// olduğu için atlanabilir olsaydı hiç sorulmamış olurdu.
bool sihirbazIlerleyebilir({
  required String adim,
  required bool riza,
  required bool aiRiza,
  DateTime? tarih,
  required bool saatBiliniyor,
  TimeOfDay? saat,
  String? sehir,
  String? cinsiyet,
  bool? bildirimSecimi,
}) =>
    switch (adim) {
      'welcome' => riza && aiRiza,
      'date' => tarih != null,
      'time' => dogumSaatiGecerli(biliniyor: saatBiliniyor, saat: saat),
      'place' => sehir != null && sehir.trim().isNotEmpty,
      'gender' => cinsiyet != null,
      'notify' => bildirimSecimi != null,
      _ => false,
    };

/// Kurulum bitirilebilir mi — `_bitir`in kendi kapısı, saf ve test
/// edilebilir.
///
/// NEDEN düğme kapısı ([sihirbazIlerleyebilir]) yetmiyor: o yalnız
/// BULUNULAN adıma bakar ve `_bitir`e giden ikinci bir yol var — kayıt
/// düşünce çıkan "Tekrar dene" bildirimi. Eylemli SnackBar bu SDK'da
/// kendiliğinden kapanmaz (`persist` varsayılanı `action != null`); kullanıcı
/// geri gidip yapay zeka kutusunu kaldırdıktan sonra ona basınca kurulum,
/// iki kutu işaretli olmadan yine yazılıyordu (bekçi `ai_onay_test`). Bu
/// yüzden şart: son adımda olunmalı ve altı adımın HER BİRİ (iki kutu
/// dahil) kendi kuralından geçmeli — geri gidilen adımda ne değiştiyse.
bool sihirbazBitirebilir({
  required int adimSirasi,
  required bool riza,
  required bool aiRiza,
  DateTime? tarih,
  required bool saatBiliniyor,
  TimeOfDay? saat,
  String? sehir,
  String? cinsiyet,
  bool? bildirimSecimi,
}) =>
    adimSirasi == kOnboardingSteps.length - 1 &&
    kOnboardingSteps.every((adim) => sihirbazIlerleyebilir(
          adim: adim,
          riza: riza,
          aiRiza: aiRiza,
          tarih: tarih,
          saatBiliniyor: saatBiliniyor,
          saat: saat,
          sehir: sehir,
          cinsiyet: cinsiyet,
          bildirimSecimi: bildirimSecimi,
        ));

/// Bildirim izni OS'a sorulsun mu — yalnız "Haber ver" seçildiyse.
///
/// `null` (seçilmedi) ve `false` ("Şimdi değil") ikisi de sormaz: bayrak
/// yazılmaz, ana ekrandaki ikinci şans yaşar. Eski akış seçim sormadan her
/// bitişte OS diyaloğunu açıyordu.
bool bildirimSorulmali(bool? secim) => secim == true;

/// Kayıt sahnesinin aşama metinleri.
///
/// Saatsiz doğumda "Evler hesaplanıyor" YOK: sunucu saatsiz doğumda ev ve
/// Yükselen hesaplamaz (`hour_known=false`), sahne hesaplanmayan bir şeyi
/// hesaplanıyor gösteremez. Aşamalar süs değil, gerçek işin adı.
List<String> onboardingStages(AppLocalizations l10n,
        {required bool saatBiliniyor}) =>
    [
      l10n.onboardingStage1,
      if (saatBiliniyor) l10n.onboardingStage2,
      l10n.onboardingStage3,
    ];

/// Sihirbazın açtığı üç seçici — test dikişi; üretim varsayılanı gerçek
/// seçiciler.
///
/// NEDEN: tarih ve saat Material diyaloğu, şehir ise tam ekran arama
/// (34k kayıtlık dizin, isolate'ta ayrıştırılır) açar. Widget testi
/// adımları gezerken o diyalogların KENDİ yerleşimi ölçüme karışır (dar
/// ekran bekçisi diyalogdaki taşmayı sihirbazın sanır) ve dizin isolate'ı
/// sahte-zamanda bitmez. Dikiş değeri döndürür, sihirbaz yine kendi
/// durumuna yazar — ölçülen şey sihirbazın kuralı, seçicinin görünümü değil.
class SihirbazSeciciler {
  const SihirbazSeciciler({
    this.tarih = _tarihSec,
    this.saat = _saatSec,
    this.sehir = _sehirSec,
  });

  final Future<DateTime?> Function(BuildContext context, DateTime baslangic)
      tarih;
  final Future<TimeOfDay?> Function(BuildContext context, TimeOfDay baslangic)
      saat;
  final Future<CityPick?> Function(BuildContext context, String? ilkSorgu)
      sehir;

  static Future<DateTime?> _tarihSec(
          BuildContext context, DateTime baslangic) =>
      showDatePicker(
        context: context,
        initialDate: baslangic,
        firstDate: DateTime(1930),
        lastDate: DateTime.now(),
      );

  static Future<TimeOfDay?> _saatSec(
          BuildContext context, TimeOfDay baslangic) =>
      showTimePicker(context: context, initialTime: baslangic);

  static Future<CityPick?> _sehirSec(BuildContext context, String? ilkSorgu) =>
      showCitySearch(context, initialQuery: ilkSorgu);
}

class OnboardingWizard extends ConsumerStatefulWidget {
  const OnboardingWizard({
    super.key,
    this.seciciler = const SihirbazSeciciler(),
  });

  @visibleForTesting
  final SihirbazSeciciler seciciler;

  @override
  ConsumerState<OnboardingWizard> createState() =>
      _OnboardingWizardState();
}

class _OnboardingWizardState extends ConsumerState<OnboardingWizard> {
  final _sayfa = PageController();
  int _adim = 0;

  // ---- taslak ----
  // Hiçbir alanın önseçili değeri yok: null = kullanıcı henüz karar
  // vermedi. `_saat` için 12:00 YALNIZ seçicinin açılış konumu
  // (`_saatSec`), değer değil; `_cinsiyet` için `female` önseçimi
  // dokunmadan geçeni "kadın" beyan ediyordu.
  bool _riza = false;
  // Yapay zeka aktarım onayı — şartlar kutusundan AYRI tutulur: iki ayrı
  // izin, tek bir değişkende birleşseydi biri ötekinin içine gömülürdü.
  bool _aiRiza = false;
  DateTime? _tarih;
  TimeOfDay? _saat;
  bool _saatBiliniyor = true;
  String? _sehir;
  String? _ulke;
  String? _cinsiyet;
  bool? _bildirimSecimi;
  bool _busy = false;

  static const _adimAdlari = kOnboardingSteps;

  int get _toplamAdim => _adimAdlari.length;

  @override
  void initState() {
    super.initState();
    Analytics.onboardingStep('welcome');
  }

  @override
  void dispose() {
    _sayfa.dispose();
    super.dispose();
  }

  /// Adım ilerleyebilir mi — düğme durumu buradan.
  bool get _ilerleyebilir => sihirbazIlerleyebilir(
        adim: _adimAdlari[_adim],
        riza: _riza,
        aiRiza: _aiRiza,
        tarih: _tarih,
        saatBiliniyor: _saatBiliniyor,
        saat: _saat,
        sehir: _sehir,
        cinsiyet: _cinsiyet,
        bildirimSecimi: _bildirimSecimi,
      );

  /// Kurulum bitirilebilir mi — `_bitir`in kapısı buradan.
  bool get _bitirebilir => sihirbazBitirebilir(
        adimSirasi: _adim,
        riza: _riza,
        aiRiza: _aiRiza,
        tarih: _tarih,
        saatBiliniyor: _saatBiliniyor,
        saat: _saat,
        sehir: _sehir,
        cinsiyet: _cinsiyet,
        bildirimSecimi: _bildirimSecimi,
      );

  void _ileri() {
    if (!_ilerleyebilir || _busy) return;
    HapticFeedback.lightImpact();
    if (_adim == _toplamAdim - 1) {
      _bitir();
      return;
    }
    setState(() => _adim++);
    Analytics.onboardingStep(_adimAdlari[_adim]);
    // Sayfa geçişinin tek fiili `motion.sayfayaGit`: sıfır süre → `jumpToPage`
    // (`animateToPage` sıfırı assert ile reddeder; D4'te burada ölçüldü,
    // D5'te hikâye ekranıyla ortaklaşıp motion.dart'a taşındı).
    sayfayaGit(_sayfa, context, _adim, curve: RythoMotion.enter);
  }

  void _geri() {
    if (_adim == 0 || _busy) return;
    // Bekleyen "Tekrar dene" bildirimi geri giderken kaldırılır: eylemli
    // SnackBar kendiliğinden kapanmıyor ve geri gidilen adımda bir kutu
    // kaldırılabilir. Asıl kapı `_bitir`in başında (`_bitirebilir`); bu
    // satır, o kapıya çarpacak bir düğmeyi ekranda bırakmamak için.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _adim--);
    sayfayaGit(_sayfa, context, _adim, curve: RythoMotion.enter);
  }

  Future<void> _bitir() async {
    // İki giriş yolu var ("Haritamı çiz" ve hata bildirimindeki "Tekrar
    // dene"); ikisi de bu kapıdan geçer. Kapı HİÇBİR yazımdan, bayraktan ve
    // Firebase erişiminden önce: işaretsiz bir kutuyla buraya gelen çağrı
    // geride iz bırakmaz.
    if (_busy || !_bitirebilir) return;
    final l10n = AppLocalizations.of(context);
    // İstemci BURADA, sihirbaz kesin takılıyken bir kez alınır ve kurulumun
    // bütün çağrıları onu kullanır: doğum kaydı `onboardingCompleted`ı
    // yazınca `_Gate` bu ekranı söküyor, yani `saveBirthRecord` döndüğünde
    // sihirbaz sökülmüş olabilir — Riverpod sökülmüş widget'ta `ref.read`e
    // StateError fırlatır (`consumer.dart` `_assertNotDisposed`). Yapay zeka
    // kaydı tam o noktadan SONRA gittiği için `ref`e dayanamaz.
    final dio = ref.read(apiProvider);
    setState(() => _busy = true);
    // Bildirim izni YALNIZ "Haber ver" seçildiyse OS'a sorulur. "Şimdi
    // değil" de bir karar ama OS'a değil bize verilmiş bir karar: bayrak
    // yazılmaz, ana ekrandaki ikinci şans (sky_screen, ilk değer
    // görüldükten sonra) gerçekten yaşar. Eski akış seçim sormadan her
    // bitişte diyaloğu açıyordu — "hayır" diyecek kullanıcı da OS'a
    // "hayır" diyor ve bir daha hiç sorulamıyordu. Sonuç yolculuğu ASLA
    // engellemez.
    if (bildirimSorulmali(_bildirimSecimi)) {
      try {
        await ensureNotificationPermissionAsked();
      } catch (e) {
        debugPrint('Onboarding bildirim izni istenemedi: $e');
      }
    }
    // Büyük Üçlü perdesinin bayrağı yazım ÖNCESİ konur (R12-B1):
    // onboardingCompleted iner inmez _Gate bu ekranı söküp AppShell'i
    // takıyor — sonuç o anda hazır olmalı. Hata olursa geri iner.
    ref.read(justOnboardedProvider.notifier).state = OnboardOutcome.chartOk;
    try {
      // Oturum okuması `try` İÇİNDE: dışarıdayken buradaki bir istisna
      // (boş oturumda `!`, Firebase erişim hatası) `_ileri`nin beklemediği
      // Future'da yakalanmadan kalıyor, düğme hiçbir şey söylemiyordu;
      // içeride sebepli hata + "Tekrar dene" çıkar ve `_busy` iner.
      final user = FirebaseAuth.instance.currentUser!;
      // Kimlik alanları yalnızca ilk kurulumda yazılır; doğum verisi ve
      // Büyük Üçlü ortak yoldan gider (core/birth_record.dart) — profil
      // düzeltme ekranıyla aynı kod.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'uid': user.uid,
        'displayName': user.displayName ?? l10n.defaultUserName,
        'photoUrl': user.photoURL,
        'email': user.email,
        // Kayıt damgası BURADA YOK (core/language_sync.dart `kayitDamgasi` +
        // `dogumAlanlari`): damga dokümanın DOĞDUĞU yazımda, hesabın
        // Auth'taki gerçek oluşma anıyla konuyor. Burada konsaydı akışı
        // yarım bırakan kullanıcı kayıt tarihsiz kalır ve panelin
        // `order_by("createdAt")` listesinden düşerdi; ayrıca bu blok
        // yeniden koşarsa (kurulum tekrarı) damga ileri kayıp 3 günlük
        // denemeyi yenilerdi.
      }, SetOptions(merge: true)).timeout(kYazmaZamanAsimi);

      // Kabul kaydı — düşerse kurulum DÜŞMEZ ama kayıp da KALICI değil:
      // başarı bayrakla işaretlenir, bayrak yoksa AppShell her açılışta
      // yeniden dener (KT2 — jeton + KVKK ispatı tek çağrıya rehin olmaz).
      await ensureConsentRecorded(dio);

      final sonuc = await saveBirthRecord(
        BirthRecord(
          date: _tarih!,
          // Saat yalnız "biliyorum" + gerçekten seçilmişse yazılır; aksi
          // hâlde null = bilinmiyor. 12:00 uydurması bu depoda bir kez
          // zarar verdi (birth_record.dart).
          time: _saatBiliniyor && _saat != null ? saatMetni(_saat) : null,
          city: _sehir!.trim(),
          gender: _cinsiyet!,
          nation: _ulke,
        ),
        dio: dio,
      );
      // Yapay zeka onayının kanıtı — doğum kaydı başarıyla döndükten SONRA:
      // kurulum ancak burada gerçekten bitti (`onboardingCompleted` yazıldı).
      // Önceden şartlar kaydının hemen ardındaydı; doğum yazımı düşüp
      // kullanıcı vazgeçerse ya da geri gidip kutuyu kaldırırsa, kurulumu
      // bitmemiş bir hesap için onay kaydı kalıyordu. Şartlar kaydıyla aynı
      // desen: kutuyu işaretleyen BU hesap adına borçlanır, düşerse kurulum
      // düşmez (çağrı hiçbir hatayı dışarı sızdırmaz) ve AppShell her
      // açılışta yeniden dener. Koşul bilinçli: kapı (`_bitirebilir`) iki
      // kutu olmadan buraya getirmiyor ama kayıt kapının değil kutunun
      // sonucudur. Aşağıdaki perde dalından ÖNCE: o dal `ref` kullanıyor ve
      // sihirbaz sökülmüşse fırlatabilir — kanıt o ihtimale rehin kalmasın.
      if (_aiRiza) {
        await aiOnayiKurulumdaVerildi(dio, uid: user.uid);
      }
      if (sonuc == BirthSaveResult.savedWithoutChart) {
        // AppShell köprüsü dürüst bildirimi buradan okur (O3).
        ref.read(justOnboardedProvider.notifier).state =
            OnboardOutcome.chartMissing;
      }
      Analytics.onboardingStep('done');
    } catch (e) {
      ref.read(justOnboardedProvider.notifier).state = null;
      if (mounted) {
        // Sebepli hata + aynı yerden tekrar: "Kayıt başarısız." tek başına
        // kullanıcıya ne olduğunu da ne yapacağını da söylemiyordu;
        // bağlantı hatası ile sunucu hatası aynı görünüyordu.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e, l10n)),
          action: SnackBarAction(label: l10n.retry, onPressed: _bitir),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tarihSec() async {
    final secilen = await widget.seciciler
        .tarih(context, _tarih ?? DateTime(2000, 1, 1));
    if (secilen != null) setState(() => _tarih = secilen);
  }

  Future<void> _saatSec() async {
    // 12:00 yalnız seçicinin AÇILIŞ konumu: kullanıcı seçmeden kapatırsa
    // `_saat` null kalır ve "Saat" satırı "—" gösterir. Değere dönüşmesi
    // için seçicinin bir saat DÖNDÜRMESİ gerekir.
    final baslangic = _saat ?? const TimeOfDay(hour: 12, minute: 0);
    final secilen = await widget.seciciler.saat(context, baslangic);
    if (secilen != null) {
      setState(() {
        _saat = secilen;
        _saatBiliniyor = true;
      });
    }
  }

  Future<void> _sehirSec() async {
    final secim = await widget.seciciler.sehir(context, _sehir);
    if (secim == null) return;
    setState(() {
      _sehir = secim.name;
      _ulke = secim.nation.isEmpty ? null : secim.nation;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      // Geri tuşu adım geri gider; ilk adımda hiçbir şey yapmaz (çıkış
      // yok: sihirbaz zorunlu verinin toplandığı yer).
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _geri(),
      child: CosmicScaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(children: [
                SizedBox(
                  width: 40,
                  child: _adim > 0 && !_busy
                      ? IconButton(
                          onPressed: _geri,
                          icon: const Icon(Icons.arrow_back_rounded,
                              size: 20, color: RythoColors.parchmentDim),
                        )
                      : null,
                ),
                Expanded(
                  // Takımyıldız bir resim; ekran okuyucu ilerlemeyi
                  // "Adım 2/6" diye duymalı, yoksa kullanıcı yolun
                  // neresinde olduğunu bilemez.
                  child: Semantics(
                    container: true,
                    label: l10n.wizardStepOf(_adim + 1, _toplamAdim),
                    // İlk yıldız yanmış başlar: hesabını açtın bile.
                    // Sonuncusu kayıt sahnesinde yanar — takımyıldız,
                    // harita gerçekten çizilirken tamamlanır.
                    child: ConstellationProgress(
                        total: _toplamAdim + 1,
                        lit: _busy ? _toplamAdim + 1 : _adim + 1),
                  ),
                ),
                const SizedBox(width: 40),
              ]),
            ),
            Expanded(
              child: PageView(
                controller: _sayfa,
                // Kaydırmayla adım atlanamaz — adım başına tek soru
                // ilkesi; geçiş yalnız düğmeyle.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _KarsilamaAdimi(
                    riza: _riza,
                    onRiza: (v) => setState(() => _riza = v),
                    aiRiza: _aiRiza,
                    onAiRiza: (v) => setState(() => _aiRiza = v),
                  ),
                  _AdimSayfasi(
                    emoji: '🌌',
                    baslik: l10n.wizardDateTitle,
                    govde: l10n.wizardDateBody,
                    child: SecimSatiri(
                      label: l10n.birthDate,
                      value: _tarih == null
                          ? '—'
                          : DateFormat('d MMMM yyyy',
                                  Localizations.localeOf(context)
                                      .toLanguageTag())
                              .format(_tarih!),
                      onTap: _tarihSec,
                    ),
                  ),
                  _AdimSayfasi(
                    emoji: '🕰️',
                    baslik: l10n.wizardTimeTitle,
                    govde: l10n.wizardTimeBody,
                    child: Column(children: [
                      SecimSatiri(
                        label: l10n.birthTime,
                        // Seçilmemiş saat "—": 12:00 görünseydi kullanıcı
                        // seçildi sanıp geçerdi (kapı zaten geçirmez ama
                        // ekran kapıyla aynı şeyi söylemeli).
                        value: !_saatBiliniyor ? '—' : (saatMetni(_saat) ?? '—'),
                        onTap: _saatSec,
                      ),
                      const SizedBox(height: RythoSpace.md),
                      SaatBilinmiyorKutusu(
                        bilinmiyor: !_saatBiliniyor,
                        onChanged: (v) => setState(() => _saatBiliniyor = !v),
                      ),
                    ]),
                  ),
                  _AdimSayfasi(
                    emoji: '🗺️',
                    baslik: l10n.wizardPlaceTitle,
                    govde: l10n.wizardPlaceBody,
                    child: SecimSatiri(
                      label: l10n.onboardingCity,
                      value: sehirEtiketi(_sehir, _ulke),
                      onTap: _sehirSec,
                    ),
                  ),
                  _AdimSayfasi(
                    emoji: '🌗',
                    baslik: l10n.wizardGenderTitle,
                    govde: l10n.wizardGenderBody,
                    child: CinsiyetSecici(
                      secili: _cinsiyet,
                      onSec: (g) => setState(() => _cinsiyet = g),
                    ),
                  ),
                  // Bildirim: sürpriz sistem diyaloğu yerine önce değer
                  // önerisi, sonra GÖRÜNÜR karar ("Haber ver" / "Şimdi
                  // değil"). OS'a yalnız evet'te sorulur (`_bitir`).
                  _AdimSayfasi(
                    emoji: '🔔',
                    baslik: l10n.wizardNotifyTitle,
                    govde: l10n.wizardNotifyBody,
                    child: IzinKapisi(
                      secim: _bildirimSecimi,
                      onSec: (v) => setState(() => _bildirimSecimi = v),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
              child: _busy
                  // Kayıt sırasında sahne (R12-B1): harita bu esnada
                  // GERÇEKTEN hesaplanıyor — aşamalar süs değil.
                  ? StagedWaiting(
                      stages: onboardingStages(l10n,
                          saatBiliniyor: _saatBiliniyor),
                      interval: kKayitAsamaAraligi,
                    )
                  : GoldButton(
                      // Son adımda yolculuk "Haritamı çiz"le biter; diğer
                      // adımlarda tek düğme "Devam" — "Sonra" yok, çünkü
                      // hiçbir adım atlanmaz.
                      text: _adim == _toplamAdim - 1
                          ? l10n.wizardFinish
                          : l10n.wizardNext,
                      onPressed: _ilerleyebilir ? _ileri : null,
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Karşılama + rıza (adım 0). Yolun vaadi + iki zorunlu kutu: şartlar ve
/// yapay zeka aktarımı.
class _KarsilamaAdimi extends StatelessWidget {
  const _KarsilamaAdimi({
    required this.riza,
    required this.onRiza,
    required this.aiRiza,
    required this.onAiRiza,
  });

  final bool riza;
  final ValueChanged<bool> onRiza;
  final bool aiRiza;
  final ValueChanged<bool> onAiRiza;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    var sira = 0;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 24),
        RythoReveal(
          index: sira++,
          slide: 0,
          child: Text('✨', style: const TextStyle(fontSize: 40)),
        ),
        const SizedBox(height: 12),
        RythoReveal(
          index: sira++,
          slide: 0.1,
          child:
              Text(l10n.wizardWelcomeTitle, style: RythoText.display(30)),
        ),
        const SizedBox(height: 10),
        RythoReveal(
          index: sira++,
          slide: 0,
          child: Text(l10n.wizardWelcomeBody,
              style: RythoText.body(14.5,
                  color: RythoColors.parchmentDim)),
        ),
        const SizedBox(height: 24),
        RythoReveal(
          index: sira++,
          slide: 0.06,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: RythoColors.inkLighter,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: RythoColors.glassStroke),
            ),
            // ListTile mürekkep efektini en yakın Material'e çizer; dekorlu
            // kutu altında Material yoksa debug assert'i test düşürür.
            child: Material(
              type: MaterialType.transparency,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Birinci kutu: şartlar + gizlilik + 13 yaş beyanı. Google/
                // Apple girişinde bugüne dek hiçbir kutu yoktu (O3).
                _RizaKutusu(
                  deger: riza,
                  onDegisti: onRiza,
                  metin: l10n.wizardConsentLabel,
                ),
                // İkinci kutu AYRI ve zorunlu (sahip kararı 2026-10-22):
                // verilerin üçüncü taraf yapay zeka hizmetlerine
                // gönderilmesine izin. Şartlar kutusunun cümlesine
                // eklenmedi — iki ayrı izin tek kutuda birleşseydi biri
                // ötekinin içine gömülürdü. Metin sağlayıcıyı ADLANDIRMAZ
                // (2026-10-23: hizmet değişebilir) ve adı için gizlilik
                // politikasını gösterir; yasal bağlantılar bu yüzden
                // ikisinin de altında.
                _RizaKutusu(
                  deger: aiRiza,
                  onDegisti: onAiRiza,
                  metin: l10n.wizardAiConsentLabel,
                ),
                // İki yasal bağlantı esnemeyen bir `Row`daydı: "Kullanım
                // Şartları" + "Gizlilik Politikası" dar ekranda tek satıra
                // sığmıyor, ikincisi ekran dışına taşıyordu. `Wrap`
                // sığmayanı alt satıra indirir.
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => openLegal(context, LegalDoc.terms),
                      child: Text(l10n.termsOfUse,
                          style: RythoText.body(12,
                              color: RythoColors.lilac)),
                    ),
                    TextButton(
                      onPressed: () => openLegal(context, LegalDoc.privacy),
                      child: Text(l10n.privacyPolicy,
                          style: RythoText.body(12,
                              color: RythoColors.lilac)),
                    ),
                  ],
                ),
              ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        RythoReveal(
          index: sira++,
          slide: 0,
          child: Text(l10n.insightDisclaimer,
              style:
                  RythoText.body(11, color: RythoColors.parchmentDim)),
        ),
        // KT4: sihirbaz PopScope ile kapalı ve 0. adımda geri de yok —
        // yanlış hesapla giren kullanıcı (test cihazında sık) uygulamayı
        // silmeden çıkamıyordu. Tek çıkış kapısı burada, küçük ve sakin.
        // Onaylı: tek dokunuş oturumu kapatıyordu; `onayliCikis`in
        // varsayılan çıkışı `signOutEverywhere` — eski düğmenin doğrudan
        // çağırdığı fonksiyon (cihaz kilidi, push jetonu, çakışma bayrağı
        // orada sırayla iner).
        const SizedBox(height: 16),
        RythoReveal(
          index: sira++,
          slide: 0,
          child: Center(
            child: TextButton(
              onPressed: () => onayliCikis(context),
              child: Text(l10n.onboardingSwitchAccount,
                  style: RythoText.body(12.5,
                      color: RythoColors.parchmentDim)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Karşılama adımının zorunlu onay kutusu. İki kutu AYNI bileşenden çizilir:
/// ikinci kutu ilkinin kopyası olsaydı görünüşleri (yazı, dokunma alanı,
/// hizalama) zamanla ayrışır ve ikisi aynı ağırlıkta iki karar gibi
/// durmazdı — aynı kavram için tek bileşen (D3).
class _RizaKutusu extends StatelessWidget {
  const _RizaKutusu({
    required this.deger,
    required this.onDegisti,
    required this.metin,
  });

  final bool deger;
  final ValueChanged<bool> onDegisti;
  final String metin;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
        value: deger,
        onChanged: (v) => onDegisti(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(metin,
            style: RythoText.body(13, color: RythoColors.parchment)),
      );
}

/// Ortak adım sayfası: emoji + başlık + tek cümle + giriş bileşeni.
class _AdimSayfasi extends StatelessWidget {
  const _AdimSayfasi({
    required this.emoji,
    required this.baslik,
    required this.govde,
    required this.child,
  });

  final String emoji;
  final String baslik;
  final String govde;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    var sira = 0;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 28),
        RythoReveal(
          index: sira++,
          slide: 0,
          child: Text(emoji, style: const TextStyle(fontSize: 36)),
        ),
        const SizedBox(height: 12),
        RythoReveal(
          index: sira++,
          slide: 0.1,
          child: Text(baslik, style: RythoText.display(26)),
        ),
        const SizedBox(height: 8),
        RythoReveal(
          index: sira++,
          slide: 0,
          child: Text(govde,
              style:
                  RythoText.body(14, color: RythoColors.parchmentDim)),
        ),
        const SizedBox(height: 24),
        RythoReveal(index: sira++, slide: 0.08, child: child),
      ],
    );
  }
}

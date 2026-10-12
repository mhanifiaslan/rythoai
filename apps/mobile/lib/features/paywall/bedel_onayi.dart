/// Bedel onayı — pahalı bir üretim başlamadan ÖNCE tek seferlik soru.
///
/// ## Neden var
/// Derin raporların dördü (BaZi, Yıl Haritası, İç Takvim, Doğum Kapısı)
/// ekrana GİRİLDİĞİ AN üretiliyor: sağlayıcı izlenir izlenmez istek gider
/// ve 5 kredi düşer. Kullanıcı "bir bakayım" diye girdiği ekranda, bir şeye
/// basmadan, aylık hakkının %5'ini harcamış oluyordu — ve bunu ancak bakiye
/// çipinden anlıyordu. Bedel rozeti kilit kartında ve karoda bedeli
/// söylüyor ama abone için o kartlar yok; abonenin bedeli gördüğü tek yer
/// burası.
///
/// ## Kural
/// * Eşik [kOnayEsigi]: altındaki bedeller (sohbet 1, İ Ching 2, ikili 3)
///   sorulmaz — rozet yeter, her mesajda soru sormak sohbeti öldürürdü.
/// * **Tek seferlik**, özellik başına: ilk "Devam"dan sonra bir daha
///   sorulmaz (`SharedPreferences`, `bedelOnayi_<sunucuAdi>`). Sorunun
///   amacı bilgilendirmek, her seferinde durdurmak değil.
/// * Bedel OKUNAMADIYSA sorulmaz: ölçülmeyen söylenmez — "bu okuma ? kredi"
///   diye bir soru yok; sunucu yine doğru bedeli düşer, yalnız soru
///   sorulmamış olur. Cüzdan henüz YÜKLENİYORSA ise beklenir (iskelet):
///   ilk karede geçirmek, kapının tam da kapatmak için var olduğu isteği
///   onaysız yollardı (testte ölçüldü, builder bir kez fazla çağrılıyordu).
/// * Onaylanmış hâl okunamazsa (tercih deposu bozuk) yine SORULUR: iki kez
///   sormak zararsız, sormadan harcamak kusurun kendisi.
///
/// Kapı sağlayıcıyı [builder] içinde izletir: izleme ancak onaydan sonra
/// başlar, yani istek de ancak o zaman gider. "Önce sor, sonra izle"
/// sırasını widget ağacı kuruyor — bayrakla değil.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers.dart' show PlusHali, raporKapisiProvider;
import '../../core/wallet.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart' show GoldButton;
import '../../widgets/glass.dart';
import 'bedel_rozeti.dart';
import 'ozellik_katalogu.dart';

/// Bu bedel ve üstü için onay sorulur — aylık hakkın %5'i.
///
/// Sayı HAK'tan türetilmiyor (hak sunucuda, 300'den 100'e indi): eşik bir
/// ürün kararı, "beş ve üstü derin rapordur" demek. Hak değişince yeniden
/// düşünülür, kendiliğinden kaymaz.
const int kOnayEsigi = 5;

/// Tercih anahtarı — özellik başına.
String bedelOnayAnahtari(PlusOzellik ozellik) =>
    'bedelOnayi_${ozellik.sunucuAdi}';

/// Saf karar: bu bedelle soru sorulur mu?
bool onayGerekli({required int? bedel, required bool onaylanmis}) =>
    bedel != null && bedel >= kOnayEsigi && !onaylanmis;

/// Onay okuma/yazma — TEST DİKİŞİ. `null` = `SharedPreferences`.
typedef OnayDeposu = ({
  Future<bool> Function(String anahtar) oku,
  Future<void> Function(String anahtar) yaz,
});

final onayDeposuProvider = Provider<OnayDeposu?>((_) => null);

Future<bool> _tercihtenOku(String anahtar) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(anahtar) ?? false;
  } catch (_) {
    // Okunamadıysa SORULUR (gerekçe dosya başında).
    return false;
  }
}

Future<void> _tercihYaz(String anahtar) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(anahtar, true);
  } catch (_) {
    // Yazılamadıysa bir dahaki girişte yine sorulur; harcamayı
    // engelleyen bir şey değil.
  }
}

class BedelKapisi extends ConsumerStatefulWidget {
  const BedelKapisi({super.key, required this.ozellik, required this.builder});

  final PlusOzellik ozellik;

  /// Asıl içerik — ücretli sağlayıcıyı BURADA izle; kapıdan önce değil.
  final Widget Function(BuildContext context, WidgetRef ref) builder;

  @override
  ConsumerState<BedelKapisi> createState() => _BedelKapisiState();
}

class _BedelKapisiState extends ConsumerState<BedelKapisi> {
  /// `null` = tercih henüz okunmadı.
  bool? _onaylanmis;

  @override
  void initState() {
    super.initState();
    final depo = ref.read(onayDeposuProvider);
    final oku = depo?.oku ?? _tercihtenOku;
    oku(bedelOnayAnahtari(widget.ozellik)).then((v) {
      if (mounted) setState(() => _onaylanmis = v);
    });
  }

  Future<void> _onayla() async {
    final depo = ref.read(onayDeposuProvider);
    final yaz = depo?.yaz ?? _tercihYaz;
    // Önce ekran açılır, sonra tercih yazılır: yazım beklenirken kullanıcı
    // bir kez daha "Devam"a basamasın.
    setState(() => _onaylanmis = true);
    await yaz(bedelOnayAnahtari(widget.ozellik));
  }

  @override
  Widget build(BuildContext context) {
    // Abone olmayana soru yok: ücretli sağlayıcı ona `null` döner (kilit
    // kartı), istek atılmaz, harcanacak bir şey yok.
    if (ref.watch(raporKapisiProvider) != PlusHali.abone) {
      return widget.builder(context, ref);
    }
    // Cüzdan YÜKLENİRKEN geçilmez (ölçüldü: ilk karede `.value` null →
    // bedel "bilinmiyor" sayılıp builder çağrılıyor, istek onaysız
    // gidiyordu). Yükleniyor ile okunamadı aynı şey değil: ilki bir kare
    // sonra cevap verir, ikincisi vermez. Tazeleme turunda eski değer
    // taşınır (`hasValue`), bekleme yok.
    final cuzdanDurumu = ref.watch(walletProvider);
    if (cuzdanDurumu.isLoading && !cuzdanDurumu.hasValue) {
      return const SkeletonList();
    }
    final bedel = bedelOku(cuzdanDurumu.value, widget.ozellik);
    if (bedel == null || bedel < kOnayEsigi) {
      return widget.builder(context, ref);
    }
    final onaylanmis = _onaylanmis;
    // Tercih okunana kadar iskelet — bir kare; "sor" ile "geç" arasında
    // yanlış tarafa düşmemek için.
    if (onaylanmis == null) return const SkeletonList();
    if (!onayGerekli(bedel: bedel, onaylanmis: onaylanmis)) {
      return widget.builder(context, ref);
    }
    return _OnayKarti(bedel: bedel, onDevam: _onayla);
  }
}

class _OnayKarti extends StatelessWidget {
  const _OnayKarti({required this.bedel, required this.onDevam});

  final int bedel;
  final VoidCallback onDevam;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        child: GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.costConfirmTitle(bedel), style: RythoType.cardTitle),
              const SizedBox(height: RythoSpace.xs),
              Text(l10n.costConfirmBody, style: RythoType.bodyDim),
              const SizedBox(height: RythoSpace.md),
              GoldButton(text: l10n.costConfirmContinue, onPressed: onDevam),
              const SizedBox(height: RythoSpace.xs),
              Center(
                child: TextButton(
                  // Vazgeçmek = ekranı kapatmak: kapının arkasında bu
                  // sayfanın başka bir içeriği yok.
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(l10n.costConfirmCancel,
                      style: RythoText.label(12.5,
                          color: RythoColors.parchmentDim)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

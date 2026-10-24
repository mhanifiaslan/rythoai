/// Aranabilir şehir seçici (O2).
///
/// Üç yerde aynı bileşen: sihirbazın doğum yeri adımı, profil doğum
/// kaydı, yaşanan şehir. Serbest TextField'ın yerini alır — yanlış
/// yazım kaynağında biter; ama LİSTE DAYATMAZ: aranan yer bulunamazsa
/// "yazdığım gibi kaydet" kaçışı serbest metni korur (köy doğumlular
/// kilitlenmez; sunucu bilinmeyen adı fallback + beyanla karşılar).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart' show friendlyError;
import '../core/city_directory.dart';
import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import '../widgets/common.dart' show ErrorCard;
import '../widgets/fade_through_route.dart';

/// ISO-2 ülke kodundan bayrak emojisi ("TR" → 🇹🇷) — asset yok.
String flagEmoji(String iso2) {
  if (iso2.length != 2) return '';
  final a = iso2.toUpperCase().codeUnitAt(0);
  final b = iso2.toUpperCase().codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '';
  return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
}

/// Tam ekran şehir arama sayfasını açar; seçim ya da null döner.
///
/// Serbest metin kaçışında `CityPick(nation: '', admin1: '')` döner —
/// çağıran boş nation'ı "bilinmiyor" diye yazar (birthNation silinir).
///
/// [yukle] test dikişi; üretimde [CityDirectory.load]. NEDEN: dizinin
/// düşmesi (varlık okunamadı, ayrıştırma hatası) ancak yükleyici
/// düşürülebilirse ölçülür; gerçek yükleyici isolate'ta koşar ve testte
/// düşürülemez.
Future<CityPick?> showCitySearch(
  BuildContext context, {
  String? initialQuery,
  @visibleForTesting Future<CityDirectory> Function() yukle = CityDirectory.load,
}) {
  return Navigator.of(context).push<CityPick>(FadeThroughRoute(
    builder: (_) =>
        _CitySearchScreen(initialQuery: initialQuery ?? '', yukle: yukle),
  ));
}

class _CitySearchScreen extends StatefulWidget {
  const _CitySearchScreen({required this.initialQuery, required this.yukle});

  final String initialQuery;
  final Future<CityDirectory> Function() yukle;

  @override
  State<_CitySearchScreen> createState() => _CitySearchScreenState();
}

class _CitySearchScreenState extends State<_CitySearchScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  CityDirectory? _dizin;

  /// Dizin yüklemesi düştüyse sebebi; null = düşmedi (ya da henüz
  /// yükleniyor — ikisini `_dizin` ayırır).
  Object? _hata;
  List<CityPick> _sonuclar = const [];
  Timer? _bekletme;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  /// Dizini yükler; düşerse hata kartı, kart "Tekrar dene" ile buraya
  /// döner.
  ///
  /// NEDEN: eski kod yalnız `then` bağlıyordu — yükleme düşünce `_dizin`
  /// sonsuza dek null kalıyor, ekran sonsuz spinner gösteriyordu ve
  /// kullanıcının ne hatayı görmesi ne de yeniden denemesi mümkündü.
  /// Sihirbazın şehir adımı bu ekrana kilitli: spinner "takıldı" demek,
  /// kurulum yarım demek.
  Future<void> _yukle() async {
    if (_hata != null) setState(() => _hata = null);
    try {
      final d = await widget.yukle();
      if (!mounted) return;
      setState(() => _dizin = d);
      _ara(_controller.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hata = e);
    }
  }

  @override
  void dispose() {
    _bekletme?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _ara(String q) {
    // 120 ms bekletme: her tuşta 34k kayıt taramak gerekmez; hissedilir
    // gecikme eşiğinin çok altında kalır.
    _bekletme?.cancel();
    _bekletme = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _dizin == null) return;
      setState(() => _sonuclar = _dizin!.search(q));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sorgu = _controller.text.trim();

    return Scaffold(
      backgroundColor: RythoColors.ink,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: RythoType.body,
          onChanged: _ara,
          decoration: InputDecoration(
            hintText: l10n.citySearchHint,
            border: InputBorder.none,
            hintStyle: RythoText.body(15, color: RythoColors.parchmentDim),
          ),
        ),
      ),
      // Üç hâl: hata → kart (sebep + tekrar dene), yükleniyor → spinner,
      // hazır → liste. Spinner YALNIZ yüklenirken: hata hâlinde dönmeye
      // devam etseydi kullanıcı beklemeye devam ederdi.
      body: _hata != null
          ? Padding(
              padding: const EdgeInsets.all(RythoSpace.lg),
              child: ErrorCard(
                message: friendlyError(_hata!, l10n),
                onRetry: _yukle,
              ),
            )
          : _dizin == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                for (final s in _sonuclar)
                  ListTile(
                    leading: Text(flagEmoji(s.nation),
                        style: const TextStyle(fontSize: 22)),
                    // Görünen ad Türkçe yazımlı; `pop(s)` GeoNames adını
                    // taşır — kayıt sunucunun çözdüğü anahtar kalır.
                    title: Text(sehirGorunenAdi(s.name, s.nation),
                        style: RythoText.body(15, w: FontWeight.w600)),
                    subtitle: Text(
                        [
                          if (s.admin1.isNotEmpty && s.admin1 != s.name)
                            sehirGorunenAdi(s.admin1, s.nation),
                          s.nation,
                        ].join(', '),
                        style: RythoText.body(12,
                            color: RythoColors.parchmentDim)),
                    onTap: () => Navigator.of(context).pop(s),
                  ),
                // Serbest metin kaçışı: liste dünyayı bilmek zorunda değil.
                // Sunucu bilinmeyen adı dürüst fallback+beyanla karşılıyor;
                // burada kullanıcıyı kilitlemek köy doğumluları dışlardı.
                if (sorgu.length >= 2)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined,
                        size: 20, color: RythoColors.copper),
                    title: Text(l10n.citySearchUseAsTyped(sorgu),
                        style:
                            RythoText.body(14, color: RythoColors.copper)),
                    subtitle: _sonuclar.isEmpty
                        ? Text(l10n.citySearchNoResults,
                            style: RythoText.body(12,
                                color: RythoColors.parchmentDim))
                        : null,
                    onTap: () => Navigator.of(context).pop(
                        CityPick(name: sorgu, nation: '', admin1: '')),
                  ),
                if (sorgu.length < 2)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.citySearchPrompt,
                        textAlign: TextAlign.center,
                        style: RythoText.body(13,
                            color: RythoColors.parchmentDim)),
                  ),
              ],
            ),
    );
  }
}

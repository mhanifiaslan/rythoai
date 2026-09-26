/// Ülke seçicili telefon alanı (O4).
///
/// Eskiden numara tek serbest TextField'dı ("+90 5xx..."): ülke kodu elle
/// yazılıyor, boşluklu/sıfırlı yazımlar Firebase'e ham gidiyordu. Artık
/// ülke ARAMALI tam ekran listeden seçilir (assets/data/countries.json —
/// GeoNames countryInfo, 246 ülke; bayrak ISO kodundan emoji, asset yok)
/// ve E.164 çıktı burada derlenir: boşluklar atılır, ulusal baştaki sıfır
/// kırpılır ("+90 0532..." hatası kaynağında biter).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'city_search_field.dart' show flagEmoji;
import 'fade_through_route.dart';

class Country {
  const Country(this.iso2, this.dialCode, this.nameEn, this.nameTr);

  final String iso2;
  final String dialCode;
  final String nameEn;
  final String nameTr;

  String nameFor(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'en'
          ? nameEn
          : nameTr;
}

/// countries.json — küçük (≈10 KB), ilk kullanımda bir kez yüklenir.
class CountryDirectory {
  CountryDirectory._(this.countries);

  final List<Country> countries;

  static CountryDirectory? _ornek;

  static Future<CountryDirectory> load() async {
    if (_ornek != null) return _ornek!;
    final ham = await rootBundle.loadString('assets/data/countries.json');
    final veri = jsonDecode(ham) as Map<String, dynamic>;
    return _ornek = CountryDirectory._([
      for (final c in veri['countries'] as List)
        Country(c[0] as String, c[1] as String, c[2] as String,
            c[3] as String),
    ]);
  }
}

/// E.164 derleyici: seçili ülke + ulusal numara.
///
/// Kullanıcı alışkanlıkları affedilir: boşluk/tire, baştaki sıfır
/// ("0532..."), hatta ülke kodunun ELLE tekrar yazılması ("+90 532..."
/// ya da "90532...") — hepsi aynı doğru numaraya derlenir. Bu önemli
/// çünkü Firebase yanlış derlenmiş numarayı da kabul edip "SMS
/// gönderildi" diyebiliyor; SMS hiç var olmayan numaraya gider ve
/// kullanıcının gördüğü şey "kod gelmiyor" olur.
String composeE164(Country country, String national) {
  return '+${country.dialCode}${nationalDigits(country, national)}';
}

/// Ulusal kısmın temizlenmiş hâli (ülke kodu ve baştaki sıfırlar olmadan).
///
/// Sıra ÖNEMLİ ve canlı bir hatadan öğrenildi (2026-09-08): baştaki sıfır
/// tek seferlik kırpılıyordu, bu yüzden "00532..." → "+9005321234567"
/// üretiliyordu. Bu numara E.164 sınırları içinde kaldığı için Firebase
/// onu KABUL EDİP faturalıyor, SMS ise var olmayan bir numaraya gidiyor;
/// kullanıcının gördüğü tek şey "kod gelmiyor" oluyor.
String nationalDigits(Country country, String national) {
  var n = national.replaceAll(RegExp(r'\D'), '');
  final kod = country.dialCode;
  // 1) Uluslararası çevirme öneki ("00 90 532...") — ülke kodundan ÖNCE.
  if (n.startsWith('00')) n = n.substring(2);
  // 2) Ülke kodu ulusal alana da yazıldıysa kırpılır ("90532..." → "532...")
  //    — kalan uzunluk gerçek bir ulusal numarayı andırıyorsa.
  if (n.startsWith(kod) && n.length - kod.length >= 8) {
    n = n.substring(kod.length);
  }
  // 3) Ulusal yazımın baştaki sıfırı uluslararası biçimde yer almaz.
  //    DÖNGÜ: "0532" kadar "00532" de tek doğru numaraya inmeli.
  while (n.startsWith('0')) {
    n = n.substring(1);
  }
  return n;
}

/// Ulusal numara uzunluğu bu ülke için makul mü?
///
/// Genel kural E.164: ülke kodu + ulusal en fazla 15 hane, ulusal en az 4.
/// Bilinen ülkeler için daha dar: yanlış numaraya SMS gönderip ücret
/// ödemenin ve kullanıcıyı "kod gelmiyor" ekranında bırakmanın önüne
/// geçen tek ucuz kapı bu.
bool isPlausibleNational(Country country, String digits) {
  if (digits.isEmpty) return false;
  final beklenen = _ulusalUzunluk[country.iso2];
  if (beklenen != null && !beklenen.contains(digits.length)) return false;
  // TR cep/sabit numaraları 0 ile başlamaz (o zaten kırpıldı) ve 1-9 arası.
  if (country.iso2 == 'TR' && !RegExp(r'^[2-9]').hasMatch(digits)) {
    return false;
  }
  final toplam = country.dialCode.length + digits.length;
  return digits.length >= 4 && toplam <= 15;
}

/// Yalnız sık kullanılan ülkeler; listede olmayan ülke genel E.164
/// kuralına düşer (aşırı kısıtlayıp meşru numarayı reddetmeyelim).
const Map<String, Set<int>> _ulusalUzunluk = {
  'TR': {10},
  'DE': {10, 11},
  'GB': {10},
  'US': {10},
  'CA': {10},
  'NL': {9},
  'FR': {9},
  'AZ': {9},
  'AT': {10, 11},
  'BE': {9},
  'CH': {9},
  'SE': {9},
};

/// Sayı tuş takımını kapatma yolu — yalnız iOS (U48).
///
/// iPhone'un sayı ve telefon tuş takımında "Bitti"/Return tuşu yok, sistem
/// geri tuşu da yok (`textInputAction` orada hiçbir tuş çizmez). Klavye açık
/// kalıp altındaki "Kod gönder"/"Doğrula" düğmelerini örtüyordu. Alan dışına
/// dokunmak odağı bırakır.
///
/// Android'de null döner, yani TextField'ın varsayılanı kalır: Flutter
/// mobilde dokunmayla odağı bırakmıyor ve Android'in kendi geri tuşu var —
/// davranış bayt bayt aynı.
TapRegionCallback? get sayiKlavyesiDisDokunus =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? (_) => FocusManager.instance.primaryFocus?.unfocus()
        : null;

/// Aynı gerekçe, kaydırma jesti: iOS'ta sayfayı sürüklemek klavyeyi kapatır.
/// Android'de null — ScrollView'un varsayılanı (`manual`) kalır.
ScrollViewKeyboardDismissBehavior? get sayiKlavyesiKaydirmaDavranisi =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? ScrollViewKeyboardDismissBehavior.onDrag
        : null;

/// Alanın o anki durumu: ekranın hem numarayı hem ÜLKEYİ bilmesi gerekir
/// (bölge kapısı ve uzunluk kontrolü için) — yalnız E.164 dizesi yetmiyor.
class PhoneEntry {
  const PhoneEntry({
    required this.e164,
    required this.country,
    required this.national,
  });

  const PhoneEntry.bos()
      : e164 = '',
        country = null,
        national = '';

  /// Derlenmiş E.164 ("+90532..."); ulusal alan boşsa ''.
  final String e164;
  final Country? country;

  /// Temizlenmiş ulusal haneler (ülke kodu ve baştaki sıfırlar yok).
  final String national;

  /// Bu ülke için makul uzunlukta mı — gönderim kapısı bunu kullanır.
  bool get plausible =>
      country != null && isPlausibleNational(country!, national);

  /// Kayda/telemetriye giden maskeli biçim: "+90532***4567".
  /// Tam numara ASLA sunucuya yazılmaz (phone_service.phone_hash doktrini).
  String get masked {
    if (country == null || national.length < 4) return '';
    final bas = national.substring(0, national.length > 3 ? 3 : 1);
    final son = national.substring(national.length - 4);
    return '+${country!.dialCode}$bas***$son';
  }
}

/// Ülke + ulusal numara girişi; her değişimde durumu bildirir.
class PhoneNumberField extends StatefulWidget {
  const PhoneNumberField({
    super.key,
    required this.onChanged,
    this.initialIso2 = 'TR',
  });

  final ValueChanged<PhoneEntry> onChanged;

  final String initialIso2;

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  final _ulusal = TextEditingController();
  Country? _ulke;

  @override
  void initState() {
    super.initState();
    CountryDirectory.load().then((d) {
      if (!mounted) return;
      setState(() => _ulke = d.countries.firstWhere(
            (c) => c.iso2 == widget.initialIso2,
            orElse: () => d.countries.first,
          ));
    });
  }

  @override
  void dispose() {
    _ulusal.dispose();
    super.dispose();
  }

  void _bildir() {
    final ulke = _ulke;
    final n = _ulusal.text.trim();
    if (ulke == null || n.isEmpty) {
      widget.onChanged(const PhoneEntry.bos());
      return;
    }
    final haneler = nationalDigits(ulke, n);
    widget.onChanged(PhoneEntry(
      e164: haneler.isEmpty ? '' : '+${ulke.dialCode}$haneler',
      country: ulke,
      national: haneler,
    ));
  }

  Future<void> _ulkeSec() async {
    final secim = await Navigator.of(context).push<Country>(
        FadeThroughRoute(builder: (_) => const _CountrySearchScreen()));
    if (secim != null && mounted) {
      setState(() => _ulke = secim);
      _bildir();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ulke = _ulke;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      InkWell(
        onTap: _ulkeSec,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: RythoColors.inkLighter,
            border: Border.all(color: RythoColors.glassStroke),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            ulke == null
                ? '…'
                : '${flagEmoji(ulke.iso2)} +${ulke.dialCode}',
            style: RythoText.mono(14, color: RythoColors.parchment),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: TextField(
          controller: _ulusal,
          style: RythoType.body,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          onTapOutside: sayiKlavyesiDisDokunus,
          decoration: InputDecoration(
            labelText: l10n.phoneFieldLabel,
            hintText: '5xx xxx xx xx',
          ),
          onChanged: (_) => _bildir(),
        ),
      ),
    ]);
  }
}

/// Aramalı tam ekran ülke listesi — şehir aramasıyla aynı dil.
class _CountrySearchScreen extends StatefulWidget {
  const _CountrySearchScreen();

  @override
  State<_CountrySearchScreen> createState() =>
      _CountrySearchScreenState();
}

class _CountrySearchScreenState extends State<_CountrySearchScreen> {
  final _controller = TextEditingController();
  CountryDirectory? _dizin;
  List<Country> _sonuclar = const [];

  @override
  void initState() {
    super.initState();
    CountryDirectory.load().then((d) {
      if (!mounted) return;
      setState(() {
        _dizin = d;
        _sonuclar = d.countries;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _katla(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ç', 'c')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u');

  void _ara(String q) {
    final dizin = _dizin;
    if (dizin == null) return;
    final k = _katla(q.trim());
    setState(() => _sonuclar = k.isEmpty
        ? dizin.countries
        : dizin.countries
            .where((c) =>
                _katla(c.nameTr).contains(k) ||
                _katla(c.nameEn).contains(k) ||
                c.dialCode.startsWith(k.replaceAll('+', '')))
            .toList());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: RythoColors.ink,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: RythoType.body,
          onChanged: _ara,
          decoration: InputDecoration(
            hintText: l10n.countrySearchHint,
            border: InputBorder.none,
            hintStyle:
                RythoText.body(15, color: RythoColors.parchmentDim),
          ),
        ),
      ),
      body: _dizin == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: _sonuclar.length,
              itemBuilder: (context, i) {
                final c = _sonuclar[i];
                return ListTile(
                  leading: Text(flagEmoji(c.iso2),
                      style: const TextStyle(fontSize: 22)),
                  title: Text(c.nameFor(context),
                      style: RythoText.body(15, w: FontWeight.w600)),
                  trailing: Text('+${c.dialCode}',
                      style: RythoText.mono(13,
                          color: RythoColors.parchmentDim)),
                  onTap: () => Navigator.of(context).pop(c),
                );
              },
            ),
    );
  }
}

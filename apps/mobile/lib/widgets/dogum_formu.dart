/// Doğum formu parçaları — sihirbaz, profil düzeltme ve kişi formu için
/// TEK dil.
///
/// ## Neden var
/// Ölçüldü (2026-10-10): "etiket · değer · kalem" satırı üç dosyada üç
/// kopyaydı (onboarding_wizard `_SecimSatiri`, birth_record_screen
/// `_AlanSatiri`, person_form_screen) ve dolgu/punto üçünde ayrışmıştı
/// (dikey 16/14, mono 15/14). Cinsiyet seçici iki ekranda DEGRADELİ kopyaydı:
/// bir durum göstergesine birincil düğmenin görsel ağırlığı veriliyordu
/// (`GlassSegments` gerekçesi; giriş ekranında aynı kusur kullanıcıdan
/// şikâyet almıştı). Saat-bilinmiyor kutusu yalnız sihirbazda açıklama
/// taşıyordu; profil düzeltme ekranı aynı kararı notsuz verdiriyordu.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'city_search_field.dart' show flagEmoji;
import 'glass.dart' show GlassSegments;

/// Dokununca seçici açan form satırı: solda etiket, sağda mevcut değer,
/// uçta kalem.
class SecimSatiri extends StatelessWidget {
  const SecimSatiri({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.semanticsLabel,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  /// Ekran okuyucu için "Doğum tarihi, 7 Mart 1988, düzenle" gibi tek
  /// cümle; verilmezse etiket + değer okunur.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RythoRadius.md),
        child: Container(
          padding: const EdgeInsets.all(RythoSpace.lg),
          decoration: BoxDecoration(
            color: RythoColors.inkLighter,
            border: Border.all(color: RythoColors.glassStroke),
            borderRadius: BorderRadius.circular(RythoRadius.md),
          ),
          child: Row(
            children: [
              // Etiket + değer `Row` + `Spacer` ile esnemiyordu: uzun etiket
              // ("Doğum yeri") + uzun değer ("🇹🇷 İstanbul") dar ekranda
              // kalemi dışarı itiyordu. `Expanded` içindeki `Wrap` sığdığında
              // etiketi solda değeri sağda tutar, sığmadığında değeri alt
              // satıra indirir; kalem satırda kalır.
              Expanded(
                child: Wrap(
                  spacing: RythoSpace.md,
                  runSpacing: RythoSpace.xxs,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    Text(label, style: RythoType.label),
                    Text(value, style: RythoType.dataLarge),
                  ],
                ),
              ),
              const SizedBox(width: RythoSpace.sm),
              const Icon(Icons.edit_outlined,
                  size: 15, color: RythoColors.lilac),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cinsiyet seçici — dört değer, seçili yokken HİÇBİRİ dolgulu değil.
///
/// NEDEN `secili` null olabiliyor: eski seçici `'female'` ile açılıyordu;
/// kullanıcı dokunmadan geçince "kadın" beyan edilmiş oluyordu. Ölçülmeyen
/// söylenmez — seçilmeyen de beyan edilmez. `unspecified` ise bilinçli
/// seçim: BaZi şans dönemlerini cinsiyetsiz hesaplayamaz ve okumada bunu
/// beyan eder; istemci yerine bir değer uydurmaz.
class CinsiyetSecici extends StatelessWidget {
  const CinsiyetSecici({super.key, required this.secili, required this.onSec});

  /// `female` | `male` | `other` | `unspecified`; null = henüz seçilmedi.
  final String? secili;
  final ValueChanged<String> onSec;

  /// Segment sırası = bu liste; `onSec` bu değerlerden birini verir.
  static const degerler = ['female', 'male', 'other', 'unspecified'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = secili;
    final i = s == null ? -1 : degerler.indexOf(s);
    return GlassSegments(
      compact: true,
      // Form İÇİNDE: kenar formdan gelir (sihirbazda 40 dp ölçülmüştü).
      margin: EdgeInsets.zero,
      labels: [
        l10n.genderFemale,
        l10n.genderMale,
        l10n.genderOther,
        l10n.genderUnspecified,
      ],
      index: i < 0 ? null : i,
      onChanged: (j) => onSec(degerler[j]),
    );
  }
}

/// "Doğum saatimi bilmiyorum" kutusu; işaretliyken sonucu söyler.
///
/// Not YALNIZ işaretliyken çıkar: saatsiz doğumda Yükselen ve evler
/// hesaplanmaz, okuma gezegen düzeyinde kalır. Bu kayıp kullanıcının
/// kararının SONUCU; karardan önce göstermek sihirbazın gövde metninin
/// (wizardTimeBody) işi, karardan sonra hatırlatmak bu kutunun.
class SaatBilinmiyorKutusu extends StatelessWidget {
  const SaatBilinmiyorKutusu({
    super.key,
    required this.bilinmiyor,
    required this.onChanged,
  });

  final bool bilinmiyor;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CheckboxListTile(
          value: bilinmiyor,
          onChanged: (v) => onChanged(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l10n.birthTimeUnknown, style: RythoType.body),
        ),
        if (bilinmiyor)
          Padding(
            padding: const EdgeInsets.only(left: RythoSpace.xxl + RythoSpace.sm),
            child: Text(l10n.wizardTimeUnknownNote,
                style: RythoType.caption.copyWith(color: RythoColors.caution)),
          ),
      ],
    );
  }
}

/// Şehir satırının değeri: `🇹🇷 İstanbul`; ülke bilinmiyorsa yalnız ad,
/// şehir yoksa `—` (boş değer, doldurulmuş gibi görünmesin).
String sehirEtiketi(String? sehir, String? ulke) {
  final ad = sehir?.trim() ?? '';
  if (ad.isEmpty) return '—';
  final bayrak = (ulke == null || ulke.isEmpty) ? '' : flagEmoji(ulke);
  return bayrak.isEmpty ? ad : '$bayrak $ad';
}

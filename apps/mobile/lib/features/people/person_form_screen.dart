/// Kişi ekleme / düzenleme formu (P-turu).
///
/// ## Neden doğum kaydı ekranından ayrı
///
/// Alanlar neredeyse aynı ama iki şey farklı ve ikisi de önemli:
///
/// 1. **Ad burada bir form alanı** — ve o alan telefondan çıkmıyor. Ekran
///    bunu SÖYLEMEK zorunda: kullanıcı üçüncü bir kişinin bilgisini
///    giriyor, nereye gittiğini bilme hakkı var.
/// 2. **İlişki türü** var ve dekoratif değil: eksen adlarını ve AI'nın
///    çerçevesini belirliyor (çocuğuyla "çekim" konuşulmaz).
///
/// Saat "bilmiyorum" birinci sınıf bir seçenek: eklenen kişilerin çoğunda
/// saat gerçekten bilinmiyor. Boş bırakıldığında sunucu Yükselen ve ev
/// üretmez ve bunu beyan eder (bkz. core/birth_record.dart baş yorumu).
///
/// Form parçaları (`SecimSatiri`, `CinsiyetSecici`, `SaatBilinmiyorKutusu`)
/// sihirbaz ve doğum kaydıyla ORTAK (`widgets/dogum_formu.dart`): üç kopya
/// üç ayrı dolgu/punto taşıyordu ve cinsiyet seçicisi burada `'female'`
/// önseçiliydi — kullanıcı dokunmadan geçince üçüncü bir kişi adına
/// "kadın" beyan ediliyordu.
library;

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/birth_record.dart' show dogumSaatiGecerli, saatMetni;
import '../../core/people.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/city_search_field.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/dogum_formu.dart';
import '../../widgets/glass.dart';
import '../../widgets/nebula_widgets.dart' show SuggestionChip;

/// Türün ekrandaki adı. Sunucu bu adı bilmiyor — orada yalnız anahtar var.
String relationLabel(AppLocalizations l10n, String relation) =>
    switch (relation) {
      'partner' => l10n.relationPartner,
      'child' => l10n.relationChild,
      'parent' => l10n.relationParent,
      'sibling' => l10n.relationSibling,
      'friend' => l10n.relationFriend,
      'work' => l10n.relationWork,
      _ => l10n.relationOther,
    };

/// Tür simgesi — listede kişiyi bir bakışta ayırt etmek için.
IconData relationIcon(String relation) => switch (relation) {
      'partner' => Icons.favorite_rounded,
      'child' => Icons.child_care_rounded,
      'parent' => Icons.elderly_rounded,
      'sibling' => Icons.group_rounded,
      'friend' => Icons.emoji_people_rounded,
      'work' => Icons.work_outline_rounded,
      _ => Icons.person_outline_rounded,
    };

/// Türün emoji karşılığı (OB1) — METİN bağlamları için (mention listesi
/// gibi). `relationIcon` bir IconData'dır ve string'e basılırsa
/// "IconData(U+0E25B)" görünür — cihazda tam bu görüldü. Tek-glif
/// emojiler bilerek seçildi (ZWJ dizileri bazı klavye/işletim sistemi
/// bileşimlerinde ikiye ayrılıyor).
String relationEmoji(String relation) => switch (relation) {
      'partner' => '💞',
      'child' => '🧒',
      'parent' => '🧓',
      'sibling' => '👫',
      'friend' => '🙋',
      'work' => '💼',
      _ => '✨',
    };

class PersonFormScreen extends ConsumerStatefulWidget {
  const PersonFormScreen({super.key, this.existing});

  /// Doluysa düzenleme kipi.
  final Person? existing;

  @override
  ConsumerState<PersonFormScreen> createState() => _PersonFormScreenState();
}

class _PersonFormScreenState extends ConsumerState<PersonFormScreen> {
  late final TextEditingController _ad =
      TextEditingController(text: widget.existing?.label ?? '');
  late String _tur = widget.existing?.relation ?? 'partner';
  late DateTime _tarih = _ilkTarih();

  /// Null = saat seçilmedi. Eski hâli `12:00` uyduruyordu; sunucuya
  /// sızmıyordu (bayrak null taşıyordu) ama "biliyorum" deyip saat seçmeden
  /// kaydedince o uydurma saat gerçek gibi yazılırdı. Kapı `dogumSaatiGecerli`.
  late TimeOfDay? _saat = _ilkSaat();
  late bool _saatBiliniyor = widget.existing?.birthTime != null;
  late String _sehir = widget.existing?.birthCity ?? '';
  late String? _ulke = widget.existing?.birthNation;

  /// Önseçim YOK: null hiçbir segmenti dolu göstermez. Düzenleme kipinde
  /// kayıtta beyan yoksa da null kalır (`Person.gender` belgesi).
  late String? _cinsiyet = widget.existing?.gender;
  bool _mesgul = false;

  DateTime _ilkTarih() {
    final ham = widget.existing?.birthDate;
    if (ham == null || ham.isEmpty) return DateTime(1990, 1, 1);
    final p = ham.split('-');
    if (p.length != 3) return DateTime(1990, 1, 1);
    return DateTime(int.tryParse(p[0]) ?? 1990, int.tryParse(p[1]) ?? 1,
        int.tryParse(p[2]) ?? 1);
  }

  TimeOfDay? _ilkSaat() {
    final ham = widget.existing?.birthTime;
    if (ham == null) return null;
    final p = ham.split(':');
    return TimeOfDay(
        hour: int.tryParse(p.first) ?? 12,
        minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  Future<void> _tarihSec() async {
    final secilen = await showDatePicker(
      context: context,
      initialDate: _tarih,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (secilen != null) setState(() => _tarih = secilen);
  }

  Future<void> _saatSec() async {
    final secilen = await showTimePicker(
        context: context,
        initialTime: _saat ?? const TimeOfDay(hour: 12, minute: 0));
    if (secilen != null) {
      setState(() {
        _saat = secilen;
        _saatBiliniyor = true; // saat seçmek "biliyorum" demek
      });
    }
  }

  Future<void> _sehirSec() async {
    final secim = await showCitySearch(context, initialQuery: _sehir);
    if (secim == null) return;
    setState(() {
      _sehir = secim.name;
      // Serbest metin kaçışında ülke boş döner; bayat ülke kodu bırakmak
      // aynı adlı şehirlerde yanlış çözüme yol açar.
      _ulke = secim.nation.isEmpty ? null : secim.nation;
    });
  }

  Person get _guncel => Person(
        id: widget.existing?.id ?? '',
        relation: _tur,
        label: _ad.text.trim().isEmpty ? null : _ad.text.trim(),
        birthDate: '${_tarih.year.toString().padLeft(4, '0')}-'
            '${_tarih.month.toString().padLeft(2, '0')}-'
            '${_tarih.day.toString().padLeft(2, '0')}',
        birthTime: _saatBiliniyor ? saatMetni(_saat) : null,
        birthCity: _sehir.trim(),
        birthNation: _ulke,
        gender: _cinsiyet,
      );

  /// Kaydet kapısı: "biliyorum" deyip saat seçmemiş form kaydedilmez
  /// (sihirbaz ve doğum kaydıyla aynı kural, tek fonksiyon).
  bool get _kaydedilebilir =>
      dogumSaatiGecerli(biliniyor: _saatBiliniyor, saat: _saat);

  Future<void> _kaydet() async {
    final l10n = AppLocalizations.of(context);
    final gezgin = Navigator.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    if (_sehir.trim().isEmpty) {
      mesajci.showSnackBar(SnackBar(content: Text(l10n.birthCityEmpty)));
      return;
    }
    setState(() => _mesgul = true);
    try {
      final dio = ref.read(apiProvider);
      if (widget.existing == null) {
        await createPerson(dio, _guncel, label: _ad.text);
      } else {
        await updatePerson(dio, _guncel, label: _ad.text);
      }
      if (!mounted) return;
      ref.invalidate(personSlotsProvider);
      mesajci.showSnackBar(SnackBar(content: Text(l10n.peopleSaved)));
      gezgin.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _mesgul = false);
      // KT4: 402'de interceptor ZATEN paywall açıyor — üstüne snackbar
      // basmak çift tepkiydi (iching_tab bu çakışmayı baştan engelliyordu,
      // burası engellemiyordu). Diğer hatalar friendlyError ile görünür.
      // Kontenjan dolu hâli artık buraya nadiren düşer: Çevrem, formu
      // açmadan ÖNCE kontenjanı okuyor (`friends_screen.kisiKontenjaniDolu`).
      if (e is! DioException || e.response?.statusCode != 402) {
        mesajci.showSnackBar(
            SnackBar(content: Text(friendlyError(e, l10n))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dil = Localizations.localeOf(context).toLanguageTag();
    final tarihMetni = DateFormat('d MMMM yyyy', dil).format(_tarih);
    final saatMetin = _saatBiliniyor ? (saatMetni(_saat) ?? '—') : '—';

    return CosmicScaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? l10n.peopleAddTitle
            : l10n.peopleEditTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(RythoSpace.xl, RythoSpace.md,
              RythoSpace.xl, RythoSpace.xxl),
          children: [
            // --- Ad: CİHAZDA kalır, bunu söylemek zorundayız ---
            TextField(
              controller: _ad,
              textCapitalization: TextCapitalization.words,
              style: RythoText.body(15),
              decoration: InputDecoration(
                labelText: l10n.peopleLabelField,
                hintText: l10n.peopleLabelHint,
              ),
            ),
            const SizedBox(height: RythoSpace.sm),
            Text(l10n.peopleLabelNote,
                style: RythoType.caption.copyWith(color: RythoColors.caution)),
            const SizedBox(height: RythoSpace.xl),

            // --- İlişki türü: eksen adlarını ve AI çerçevesini belirler ---
            // Seçili çip DEGRADE DEĞİL: degrade eyleme ait (K5), çip bir
            // durum gösterir; `SuggestionChip.selected` geri bildirim ve
            // günlükle aynı "seçili çip" dili.
            Text(l10n.peopleRelation, style: RythoType.label),
            const SizedBox(height: RythoSpace.sm),
            Wrap(
              spacing: RythoSpace.sm,
              runSpacing: RythoSpace.sm,
              children: [
                for (final tur in kRelations)
                  SuggestionChip(
                    text: relationLabel(l10n, tur),
                    selected: _tur == tur,
                    onTap: () => setState(() => _tur = tur),
                  ),
              ],
            ),
            const SizedBox(height: RythoSpace.xl),

            SecimSatiri(
              label: l10n.birthDate,
              value: tarihMetni,
              onTap: _tarihSec,
            ),
            const SizedBox(height: RythoSpace.md),
            SecimSatiri(
              label: l10n.birthTime,
              value: saatMetin,
              onTap: _saatSec,
            ),
            SaatBilinmiyorKutusu(
              bilinmiyor: !_saatBiliniyor,
              onChanged: (bilinmiyor) =>
                  setState(() => _saatBiliniyor = !bilinmiyor),
            ),
            const SizedBox(height: RythoSpace.md),
            SecimSatiri(
              label: l10n.onboardingCity,
              value: sehirEtiketi(_sehir, _ulke),
              onTap: _sehirSec,
            ),
            const SizedBox(height: RythoSpace.lg),

            // Dört seçenek, önseçim yok; "Belirtmedim" de bir seçimdir.
            CinsiyetSecici(
              secili: _cinsiyet,
              onSec: (v) => setState(() => _cinsiyet = v),
            ),
            const SizedBox(height: RythoSpace.xl),

            // --- Rıza beyanı: bu kişi kullanıcı değil, onayı alınamıyor ---
            GlassPanel(
              tone: GlassTone.raised,
              margin: EdgeInsets.zero,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 18, color: RythoColors.caution),
                  const SizedBox(width: RythoSpace.sm),
                  Expanded(
                    child: Text(l10n.peopleConsent, style: RythoType.caption),
                  ),
                ],
              ),
            ),
            const SizedBox(height: RythoSpace.xl),

            GoldButton(
              text: l10n.save,
              busy: _mesgul,
              onPressed: _kaydedilebilir ? _kaydet : null,
            ),
          ],
        ),
      ),
    );
  }
}

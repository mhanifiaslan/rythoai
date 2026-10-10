/// Doğum kaydını düzeltme ekranı.
///
/// ## Neden var
///
/// Doğum tarihi/saati/şehri yalnızca kurulumda bir kez yazılabiliyordu.
/// Yanlış giren kullanıcının tek çıkışı hesabı silmekti. Bu sadece bir
/// kolaylık eksiği değil, veri kalitesi kusuru: o veri günlük okumayı, natal
/// raporu, BaZi'yi ve sohbetin gördüğü haritayı besliyor. Yanlış doğum
/// verisiyle üretilen her yorum yanlış.
///
/// Ekran bilerek sade: tek iş yapar, değişikliğin neyi etkileyeceğini söyler,
/// bir şey değişmediyse kaydetmez. Form parçaları sihirbazla TEK dil
/// (`widgets/dogum_formu.dart`): satır, cinsiyet seçici ve saat kutusu
/// burada ikinci kez yazılmaz.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/birth_record.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/city_search_field.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/dogum_formu.dart';

class BirthRecordScreen extends ConsumerStatefulWidget {
  const BirthRecordScreen({super.key});

  @override
  ConsumerState<BirthRecordScreen> createState() => _BirthRecordScreenState();
}

class _BirthRecordScreenState extends ConsumerState<BirthRecordScreen> {
  BirthRecord? _baslangic;
  late DateTime _tarih;

  /// Seçilmiş saat; null = seçilmedi. 12:00 UYDURULMAZ: eski hâl saati
  /// bilinmeyen kaydı açarken `12:00` yazıyor, kullanıcı kutuyu kaldırıp
  /// saat seçmeden kaydedince o uydurma saat gerçek gibi gidiyordu
  /// (ölçüldü; `dogumSaatiGecerli` gerekçesi).
  TimeOfDay? _saat;

  /// Doğum saati biliniyor mu (Revize B1) — bilinmiyorsa null gönderilir
  /// ve BaZi saat sütununu hiç kurmaz.
  late bool _saatBiliniyor;

  final _sehir = TextEditingController();

  /// Şehir seçiciden gelen ülke kodu; serbest metin girişinde null.
  String? _ulke;
  late String _cinsiyet;
  bool _mesgul = false;

  /// Profil akışı ilk değeri getirdiğinde formu bir kez doldur. Sonraki
  /// yayınlarda doldurmayız — kullanıcının yazdığının üstüne yazmak olur.
  void _ilkDoldur(Map<String, dynamic>? profil) {
    if (_baslangic != null) return;
    final kayit = BirthRecord.fromProfile(profil);
    _baslangic = kayit;
    _tarih = kayit.date;
    _saatBiliniyor = kayit.time != null;
    _saat = saatAyristir(kayit.time);
    _sehir.text = kayit.city;
    _ulke = kayit.nation;
    _cinsiyet = kayit.gender;
  }

  BirthRecord get _guncel => BirthRecord(
        date: _tarih,
        time: _saatBiliniyor ? saatMetni(_saat) : null,
        city: _sehir.text,
        gender: _cinsiyet,
        nation: _ulke,
      );

  Future<void> _sehirSec() async {
    final secim =
        await showCitySearch(context, initialQuery: _sehir.text);
    if (secim == null) return;
    setState(() {
      _sehir.text = secim.name;
      // Serbest metin kaçışında ülke boş döner → "bilinmiyor" yazılır;
      // bayat ülke kodu bırakmak aynı adlı şehirlerde yanlış çözüm demek.
      _ulke = secim.nation.isEmpty ? null : secim.nation;
    });
  }

  bool get _degisti => _baslangic != null && !_baslangic!.sameAs(_guncel);

  /// Kaydet açık mı: bir şey değişmiş VE saat girişi tutarlı olmalı.
  ///
  /// "Biliyorum" deyip saat seçmeyen kullanıcı kaydedemez — eskiden kutu
  /// kaldırılınca Kaydet açılıyor ve uydurma 12:00 gidiyordu. Sihirbazla
  /// aynı kapı (`sihirbazIlerleyebilir` da `dogumSaatiGecerli`ye bakar).
  bool get _kaydedilebilir =>
      _degisti && dogumSaatiGecerli(biliniyor: _saatBiliniyor, saat: _saat);

  @override
  void dispose() {
    _sehir.dispose();
    super.dispose();
  }

  Future<void> _tarihSec() async {
    final secilen = await showDatePicker(
      context: context,
      initialDate: _tarih,
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
    );
    if (secilen != null) setState(() => _tarih = secilen);
  }

  Future<void> _saatSec() async {
    final secilen = await showTimePicker(
      context: context,
      // 12:00 yalnız seçicinin AÇILIŞ konumu, değer değil: kullanıcı
      // seçmeden kapatırsa `_saat` null kalır ve satır "—" gösterir
      // (sihirbazla aynı kural).
      initialTime: _saat ?? const TimeOfDay(hour: 12, minute: 0),
    );
    if (secilen != null) {
      setState(() {
        _saat = secilen;
        // Saat seçmek "biliyorum" demek.
        _saatBiliniyor = true;
      });
    }
  }

  Future<void> _kaydet() async {
    final l10n = AppLocalizations.of(context);
    final gezgin = Navigator.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    if (_sehir.text.trim().isEmpty) {
      mesajci.showSnackBar(SnackBar(content: Text(l10n.birthCityEmpty)));
      return;
    }
    setState(() => _mesgul = true);
    try {
      final sonuc =
          await saveBirthRecord(_guncel, dio: ref.read(apiProvider));
      if (!mounted) return;
      mesajci.showSnackBar(SnackBar(
        content: Text(sonuc == BirthSaveResult.ok
            ? l10n.birthRecordSaved
            // Rozetler silindi; sebebini söylemezsek açıklanamayan bir
            // kayıp olur.
            : l10n.birthRecordSavedNoChart),
      ));
      gezgin.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _mesgul = false);
      mesajci.showSnackBar(SnackBar(content: Text(friendlyError(e, l10n))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profilAsync = ref.watch(profileProvider);
    // Profil gelmeden form DOLDURULMAZ (ölçüldü, D5 testi): eski hâl ilk
    // karede null profille varsayılanları (2000-01-01, İstanbul, saatsiz)
    // yazıp bir daha dokunmuyordu — kullanıcı kendi kaydı yerine uydurma
    // değerleri görür, "değişmedi" diye kaydedemezdi. Uygulamada akış
    // genelde sıcak (kabuk izliyor); soğuk yolda usturlap, uydurma değil.
    if (_baslangic == null && profilAsync.isLoading) {
      return CosmicScaffold(
        appBar: AppBar(title: Text(l10n.birthRecord)),
        body: const Center(child: AstrolabeSpinner()),
      );
    }
    _ilkDoldur(profilAsync.value);

    final dil = Localizations.localeOf(context).toLanguageTag();
    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.birthRecord)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(RythoSpace.xl, RythoSpace.md,
              RythoSpace.xl, RythoSpace.xxl),
          children: [
            Text(l10n.birthRecordEditBody, style: RythoType.bodyDim),
            const SizedBox(height: RythoSpace.xl),
            SecimSatiri(
              label: l10n.birthDate,
              value: DateFormat('d MMMM yyyy', dil).format(_tarih),
              onTap: _tarihSec,
            ),
            const SizedBox(height: RythoSpace.md),
            SecimSatiri(
              label: l10n.birthTime,
              // Seçilmemiş saat "—": 12:00 görünseydi kullanıcı seçildi
              // sanıp geçerdi; kapı zaten geçirmez ama ekran kapıyla aynı
              // şeyi söylemeli.
              value: !_saatBiliniyor ? '—' : (saatMetni(_saat) ?? '—'),
              onTap: _saatSec,
            ),
            const SizedBox(height: RythoSpace.md),
            SaatBilinmiyorKutusu(
              bilinmiyor: !_saatBiliniyor,
              onChanged: (v) => setState(() => _saatBiliniyor = !v),
            ),
            const SizedBox(height: RythoSpace.md),
            // Serbest TextField'ın yerini aranabilir seçici aldı (O2):
            // yanlış yazım kaynağında biter, ülke kodu da kaydedilir.
            SecimSatiri(
              label: l10n.onboardingCity,
              value: sehirEtiketi(_sehir.text, _ulke),
              onTap: _sehirSec,
            ),
            const SizedBox(height: RythoSpace.lg),
            CinsiyetSecici(
              secili: _cinsiyet,
              onSec: (g) => setState(() => _cinsiyet = g),
            ),
            const SizedBox(height: RythoSpace.xxl),
            GoldButton(
              text: l10n.save,
              busy: _mesgul,
              // Değişiklik yoksa kaydetmek anlamsız bir ağ çağrısı ve
              // gereksiz bir "kaydedildi" mesajı olurdu.
              onPressed: _kaydedilebilir ? _kaydet : null,
            ),
          ],
        ),
      ),
    );
  }
}

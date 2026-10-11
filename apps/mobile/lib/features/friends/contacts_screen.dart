/// Rehber ekranı (I-turu) — telefon rehberini aktif/pasif olarak gösterir.
///
/// Kullanıcının şikâyeti: Arkadaşlar ekranındaki "REHBERİNDEN" kartı çok
/// büyüktü ve yalnız app'te olan kişileri gösteriyordu. Bu tam ekran:
/// * ÜSTTE "Uygulamada" — rehberdeki app kullanıcıları (arkadaş ekle).
/// * ALTTA "Davet et" — app'te olmayan rehber kişileri (paylaş menüsüyle
///   davet: WhatsApp/SMS/mail — kişinin kullandığı her ne ise).
/// İkisi de ada göre alfabetik; arama kutusu ikisini birden süzer; liste
/// tembel (ListView.builder) — yüzlerce kişide takılmaz.
///
/// Gizlilik: rehber ADLARI CİHAZDA kalır; sunucuya yalnız hash gitti
/// (bkz. core/contact_match.dart). Bu ekran hiçbir ad yüklemez.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/analytics.dart';
import '../../core/api.dart' show apiProvider, friendlyError;
import '../../core/city_directory.dart' show foldTurkish;
import '../../core/contact_match.dart';
import '../../core/deep_links.dart' show inviteLinkFor;
import '../../core/friends.dart';
import '../../core/providers.dart';
import '../../core/tr_metin.dart' show trBuyuk;
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart' show ErrorCard;
import '../../widgets/cosmic_scaffold.dart';
import '../../l10n/app_localizations.dart';
import '../profile/phone_verify_screen.dart' show PhoneVerifyScreen;

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _aramaCtrl = TextEditingController();
  String _arama = '';

  @override
  void dispose() {
    _aramaCtrl.dispose();
    super.dispose();
  }

  Future<void> _davetEt(String? username) async {
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    if (username == null) {
      mesajci.showSnackBar(
          SnackBar(content: Text(l10n.contactsInviteNeedsUsername)));
      return;
    }
    final metin = l10n.inviteShareMessage(inviteLinkFor(username));
    Analytics.friendInviteSent();
    await SharePlus.instance.share(ShareParams(text: metin));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sonucAsync = ref.watch(contactMatchesProvider);
    final username = ref.watch(profileProvider).value?['username'] as String?;

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.contactsTitle)),
      body: SafeArea(
        child: sonucAsync.when(
          loading: () => const Center(child: AstrolabeSpinner()),
          // Hata düz metin değil kart: kullanıcı düşen eşleşmeyi yeniden
          // deneyebilmeli (bölüm hatası tek dil — plan §3).
          error: (e, _) => ListView(children: [
            ErrorCard(
                message: friendlyError(e, l10n),
                screen: 'circle',
                onRetry: () => ref.invalidate(contactMatchesProvider)),
          ]),
          data: (sonuc) => _govde(context, l10n, sonuc, username),
        ),
      ),
    );
  }

  Widget _mesajGovde(String metin) => Center(
        child: Padding(
          padding: const EdgeInsets.all(RythoSpace.xl),
          child: Text(metin,
              textAlign: TextAlign.center,
              style: RythoText.body(13, color: RythoColors.parchmentDim)),
        ),
      );

  Widget _govde(BuildContext context, AppLocalizations l10n,
      ContactMatchResult sonuc, String? username) {
    // Engel durumları: tam ekran yol gösteren kart.
    if (sonuc.blocker == ContactMatchBlocker.telefonYok) {
      return _EngelKarti(
        baslik: l10n.contactMatchPhoneTitle,
        metin: l10n.contactMatchPhoneBody,
        eylem: l10n.contactMatchVerifyPhone,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const PhoneVerifyScreen())),
      );
    }
    if (sonuc.blocker == ContactMatchBlocker.izinYok) {
      return _EngelKarti(
        baslik: l10n.contactMatchPermTitle,
        metin: l10n.contactMatchPermBody,
        eylem: l10n.contactMatchRetry,
        onTap: () => ref.invalidate(contactMatchesProvider),
      );
    }

    // Arkadaşlık durumları: aktif kişide "ekle / arkadaşın / gönderildi".
    final friends = ref.watch(friendsProvider).value ?? const <Friend>[];
    final durumByUid = {for (final f in friends) f.uid: f.status};

    // Arama süzgeci (ada + @username duyarlı).
    final q = foldTurkish(_arama);
    bool aktifGecer(ActiveContact a) =>
        q.isEmpty ||
        foldTurkish(a.name).contains(q) ||
        foldTurkish(a.match.username ?? '').contains(q);
    bool pasifGecer(PassiveContact p) =>
        q.isEmpty || foldTurkish(p.name).contains(q);

    final aktif = sonuc.active.where(aktifGecer).toList();
    final pasif = sonuc.passive.where(pasifGecer).toList();

    // Düz liste: başlıklar + satırlar (builder tembelliği korunur).
    final ogeler = <Widget>[];
    if (aktif.isNotEmpty) {
      ogeler.add(_baslik(l10n.contactsActiveSection));
      for (final a in aktif) {
        ogeler.add(_AktifSatir(
          kisi: a,
          durum: durumByUid[a.match.uid],
        ));
      }
    }
    if (pasif.isNotEmpty) {
      ogeler.add(_baslik(l10n.contactsInviteSection));
      // Dürüstlük dipnotu (J-turu): telefonu doğrulanmamış bir arkadaş
      // teknik olarak tespit EDİLEMEZ ve burada görünebilir — ekran "bu
      // kişi kesin kullanmıyor" iddiasında bulunmaz.
      ogeler.add(Padding(
        padding: const EdgeInsets.only(bottom: RythoSpace.sm),
        child: Text(l10n.contactsInviteFootnote,
            style: RythoText.body(11, color: RythoColors.parchmentDim)),
      ));
      for (final p in pasif) {
        ogeler.add(_PasifSatir(ad: p.name, onDavet: () => _davetEt(username)));
      }
    }

    final bosMu = aktif.isEmpty && pasif.isEmpty;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.lg, RythoSpace.sm, RythoSpace.lg, RythoSpace.sm),
        child: TextField(
          controller: _aramaCtrl,
          onChanged: (v) => setState(() => _arama = v),
          style: RythoText.body(15),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: l10n.contactsSearchHint,
            isDense: true,
          ),
        ),
      ),
      Expanded(
        child: bosMu
            ? _mesajGovde(_arama.isEmpty
                ? l10n.contactMatchEmptyBody
                : l10n.contactsNoSearchResult)
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(contactMatchesProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.only(
                      left: RythoSpace.lg,
                      right: RythoSpace.lg,
                      bottom: RythoSpace.xxl),
                  itemCount: ogeler.length,
                  itemBuilder: (_, i) => ogeler[i],
                ),
              ),
      ),
    ]);
  }

  // Büyük harf dönüşümü KALKTI: `toUpperCase` Türkçe bilmez ("Rytho'da
  // görünmüyor" → "GÖRÜNMÜYOR" tamam ama "i" → "I") ve etiket rolünün
  // ağırlığı zaten yeter (§2).
  Widget _baslik(String metin) => Padding(
        padding: const EdgeInsets.only(
            top: RythoSpace.lg + RythoSpace.xxs, bottom: RythoSpace.xs + 2),
        child: Text(metin, style: RythoType.label),
      );
}

/// Tam ekran engel/yol gösterme kartı.
class _EngelKarti extends StatelessWidget {
  const _EngelKarti({
    required this.baslik,
    required this.metin,
    required this.eylem,
    required this.onTap,
  });

  final String baslik;
  final String metin;
  final String eylem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RythoSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(baslik,
                textAlign: TextAlign.center, style: RythoText.display(18)),
            const SizedBox(height: RythoSpace.sm),
            Text(metin,
                textAlign: TextAlign.center,
                style: RythoText.body(13, color: RythoColors.parchmentDim)),
            const SizedBox(height: RythoSpace.lg + RythoSpace.xxs),
            GoldButton(text: eylem, filled: false, onPressed: onTap),
          ],
        ),
      ),
    );
  }
}

/// Aktif (app'te olan) rehber kişisi satırı.
class _AktifSatir extends ConsumerStatefulWidget {
  const _AktifSatir({required this.kisi, required this.durum});
  final ActiveContact kisi;
  final FriendStatus? durum;

  @override
  ConsumerState<_AktifSatir> createState() => _AktifSatirState();
}

class _AktifSatirState extends ConsumerState<_AktifSatir> {
  bool _gonderildi = false;
  bool _mesgul = false;

  Future<void> _ekle() async {
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    final dio = ref.read(apiProvider);
    setState(() => _mesgul = true);
    try {
      await sendFriendRequest(widget.kisi.match.uid);
      // Davet push'u (OB2): kenarlar yazıldıktan sonra, ateşle-unut.
      unawaited(notifyInvite(dio, widget.kisi.match.uid));
      if (mounted) setState(() => _gonderildi = true);
    } catch (e) {
      if (mounted) {
        mesajci.showSnackBar(SnackBar(content: Text(friendlyError(e, l10n))));
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kisi = widget.kisi;
    final foto = kisi.match.photoUrl;

    Widget trailing;
    if (widget.durum == FriendStatus.accepted) {
      trailing = Text(l10n.contactsAlreadyFriend,
          style: RythoText.label(11, color: RythoColors.celadon));
    } else if (widget.durum == FriendStatus.outgoing || _gonderildi) {
      trailing = Padding(
        padding: const EdgeInsets.symmetric(horizontal: RythoSpace.sm),
        child: Icon(Icons.check_rounded, size: 18, color: RythoColors.celadon),
      );
    } else {
      trailing = TextButton(
        onPressed: _mesgul ? null : _ekle,
        child: Text(l10n.addFriend, style: RythoText.label(12)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs + 1),
      child: Row(children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: RythoColors.inkLighter,
          backgroundImage: foto != null ? NetworkImage(foto) : null,
          child: foto == null ? Text('☽', style: RythoText.display(13)) : null,
        ),
        const SizedBox(width: RythoSpace.sm + RythoSpace.xxs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kisi.name, style: RythoText.body(14, w: FontWeight.w600)),
            if (kisi.match.username != null)
              Text('@${kisi.match.username}',
                  style: RythoText.mono(11, color: RythoColors.parchmentDim)),
          ]),
        ),
        trailing,
      ]),
    );
  }
}

/// Pasif (app'te olmayan) rehber kişisi satırı — davet edilir.
class _PasifSatir extends StatelessWidget {
  const _PasifSatir({required this.ad, required this.onDavet});
  final String ad;
  final VoidCallback onDavet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Baş harf Türkçe kuralla: "ilayda" → "İ" (`toUpperCase` "I" verirdi).
    // `characters`: adın ilk öğesi bir emoji/birleşik harf olabilir;
    // `[0]` yarım bir code unit alırdı.
    final kirpik = ad.trim();
    final basHarf =
        kirpik.isNotEmpty ? trBuyuk(kirpik.characters.first) : '☽';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs + 1),
      child: Row(children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: RythoColors.inkLight,
          child: Text(basHarf,
              style: RythoText.body(14, color: RythoColors.parchmentDim)),
        ),
        const SizedBox(width: RythoSpace.sm + RythoSpace.xxs),
        Expanded(
          child: Text(ad,
              style: RythoText.body(14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        // Davet düğmesi esnemiyordu: soldaki ad `Expanded` içinde sıfıra
        // inse bile ikon + uzun düğme etiketi dar ekranda taşıyordu.
        Flexible(
          child: TextButton.icon(
            onPressed: onDavet,
            icon: const Icon(Icons.ios_share_rounded, size: 15),
            label: Text(l10n.contactsInvite, style: RythoText.label(12)),
          ),
        ),
      ]),
    );
  }
}

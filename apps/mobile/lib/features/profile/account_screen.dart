/// Hesap: görünen ad ve kullanıcı adı düzenleme.
///
/// ## Neden var
///
/// İkisi de bir kez yazılıp kilitleniyordu. Görünen ad kimlik sağlayıcıdan
/// (Google/Apple) ne geldiyse oydu; kullanıcı adı ise Arkadaşlar sekmesindeki
/// kurulum panelinden bir defa alınıyordu — panel `username == null` iken
/// gösterildiği için ikinci kez açılmıyordu. Yazım hatası yapan kullanıcının
/// düzeltme yolu yoktu.
///
/// Veri katmanı değişikliği zaten destekliyordu: `claimUsername` yeni adı
/// rezerve edip eskisini serbest bırakıyor. Eksik olan yalnızca ekrandı.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'delete_account.dart' show showDeleteAccountSheet;
import 'phone_verify_screen.dart';

import '../../core/friends.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';

/// Görünen adın üst sınırı — karakter (kod noktası) sayısı.
///
/// NEDEN bir sınır var: `displayName` hiçbir yerde sınırlanmıyordu —
/// istemci yalnız boş olup olmadığına bakıyor, `infra/firestore.rules`
/// alanı izinli listede tutuyor ama BOYUTUNU sınırlamıyor, sunucuda da
/// yazan bir yol yok. Ad kullanıcının kendi ekranında kalmıyor: arkadaş
/// bildirimlerinin BAŞLIĞINA giriyor (`PUSH_MIDDAY_PAIR_TITLE`,
/// `PUSH_INVITE_TITLE`) ve gövde bütçesi sunucuda ÖLÇÜLDÜ —
/// `notification_service.py` `MAX_PUSH_BODY = 110`. Sınır aşılınca metin
/// kırpılmıyor, YEDEĞE düşülüyor; yani 90 harflik bir ad arkadaşının
/// bildirimini sessizce yalınlaştırıyor ya da hiç göndermiyor.
///
/// NEDEN 40: üç ölçümün kesişimi. (1) Sunucu bütçesi 110 ve ada yer açan
/// başlık kalıplarının sabit kısmı en fazla ~34 karakter, yani 40 rahatça
/// içeride kalıyor. (2) Depodaki komşu alan kullanıcı adı ve onun alanı
/// `maxLength: 20` (friends_screen.dart) — 40 ondan gevşek, çünkü görünen
/// ad soyadı da taşıyor. (3) Gerçek adlar bu sınıra yaklaşmıyor; sınır
/// kullanıcıyı değil taşmayı kesiyor.
///
/// NEDEN kod noktası (`runes`) ve `String.length` DEĞİL: `String.length`
/// UTF-16 kod BİRİMİ sayar, yani emoji taşıyan bir ad iki kat uzun
/// görünür. Sunucudaki bütçe Python `len()` ile, yani kod noktasıyla
/// ölçülüyor; iki taraf aynı şeyi saymalı.
const kDisplayNameMaxChars = 40;

/// Ad sınırı aşıyor mu — saf işlev.
///
/// Ayrı tutulmasının NEDENİ: kararın bekçisi `AccountScreen`i çizmeden
/// yazılabilsin. O ağaç Firebase oturumu + profil sağlayıcısı istiyor
/// (depodaki `plusHaliniOku` ile aynı gerekçe).
bool adCokUzun(String ad) => ad.runes.length > kDisplayNameMaxChars;

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _ad = TextEditingController();
  final _kullaniciAdi = TextEditingController();
  String _ilkAd = '';
  String _ilkKullaniciAdi = '';
  bool _dolduruldu = false;
  bool _mesgul = false;
  bool _dogrulamaGonderildi = false;
  String? _hata;

  void _ilkDoldur(Map<String, dynamic>? profil) {
    if (_dolduruldu || profil == null) return;
    _dolduruldu = true;
    _ilkAd = (profil['displayName'] as String?) ?? '';
    _ilkKullaniciAdi = (profil['username'] as String?) ?? '';
    _ad.text = _ilkAd;
    _kullaniciAdi.text = _ilkKullaniciAdi;
  }

  bool get _degisti =>
      _dolduruldu &&
      (_ad.text.trim() != _ilkAd ||
          _kullaniciAdi.text.trim().toLowerCase() != _ilkKullaniciAdi);

  @override
  void dispose() {
    _ad.dispose();
    _kullaniciAdi.dispose();
    super.dispose();
  }

  String _hataMetni(UsernameError e, AppLocalizations l10n) => switch (e) {
        UsernameError.empty => l10n.usernameEmpty,
        UsernameError.invalid => l10n.usernameInvalid,
        UsernameError.taken => l10n.usernameTaken,
      };

  Future<void> _kaydet() async {
    final l10n = AppLocalizations.of(context);
    final gezgin = Navigator.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final yeniAd = _ad.text.trim();
    if (yeniAd.isEmpty) {
      setState(() => _hata = l10n.displayNameEmpty);
      return;
    }
    // Kapı `maxLength`e EK: alandaki sınır yalnız KLAVYEDEN gireni kesiyor.
    // Bu alana iki yoldan daha uzun metin gelebiliyor — yapıştırma
    // (`maxLengthEnforcement` kompozisyon sırasında geçirir) ve Firestore'da
    // zaten duran eski kayıt (`_ilkDoldur` onu olduğu gibi yazıyor). Yazım
    // kapısı olmadan sınır bir ÖNERİ olurdu.
    if (adCokUzun(yeniAd)) {
      setState(() => _hata = l10n.displayNameTooLong(kDisplayNameMaxChars));
      return;
    }
    final yeniKullaniciAdi = _kullaniciAdi.text.trim().toLowerCase();

    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      // Kullanıcı adı ÖNCE: benzersizlik çakışması burada çıkar ve bu
      // durumda hiçbir şey yazılmamış olur. Ters sırada ad yazılıp kullanıcı
      // adı reddedilseydi kısmen kaydedilmiş bir form kalırdı.
      if (yeniKullaniciAdi != _ilkKullaniciAdi &&
          yeniKullaniciAdi.isNotEmpty) {
        await claimUsername(yeniKullaniciAdi);
      }
      if (yeniAd != _ilkAd) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'displayName': yeniAd}, SetOptions(merge: true));
        // Arkadaş listesindeki kart ayrı dokümandan besleniyor.
        await syncPublicProfile();
      }
      if (!mounted) return;
      mesajci.showSnackBar(SnackBar(content: Text(l10n.accountSaved)));
      gezgin.pop();
    } on UsernameException catch (e) {
      if (!mounted) return;
      setState(() {
        _mesgul = false;
        _hata = _hataMetni(e.error, l10n);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mesgul = false;
        _hata = l10n.genericError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profil = ref.watch(profileProvider).value;
    _ilkDoldur(profil);
    final eposta = FirebaseAuth.instance.currentUser?.email;

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.accountSection)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(RythoSpace.xl, RythoSpace.md,
              RythoSpace.xl, RythoSpace.xxl),
          children: [
            TextField(
              controller: _ad,
              style: RythoType.body,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() => _hata = null),
              // Sınır ÖNCE burada görünür: kullanıcı sayacı görüp durur,
              // hata mesajını hiç görmez. Yazım kapısı `_kaydet`te duruyor
              // ve asıl taşıma yollarını (yapıştırma, eski uzun kayıt) o
              // kesiyor — bu satır tek başına yeterli DEĞİL.
              maxLength: kDisplayNameMaxChars,
              decoration: InputDecoration(labelText: l10n.displayName),
            ),
            const SizedBox(height: RythoSpace.lg),
            TextField(
              controller: _kullaniciAdi,
              style: RythoType.body,
              autocorrect: false,
              onChanged: (_) => setState(() => _hata = null),
              decoration: InputDecoration(
                labelText: l10n.usernameLabel,
                prefixText: '@',
                hintText: l10n.usernameHint,
              ),
            ),
            const SizedBox(height: RythoSpace.sm),
            Text(
                _ilkKullaniciAdi.isEmpty
                    ? l10n.usernameBody
                    : l10n.usernameChangeNote,
                style: RythoType.caption),
            if (_hata != null) ...[
              const SizedBox(height: RythoSpace.md),
              Text(_hata!,
                  style: RythoText.body(13, color: RythoColors.madder)),
            ],
            if (eposta != null) ...[
              const SizedBox(height: RythoSpace.xl),
              Text(l10n.email, style: RythoType.label),
              const SizedBox(height: RythoSpace.xs),
              Text(eposta, style: RythoType.data),
              const SizedBox(height: RythoSpace.xs),
              // E-posta kimlik doğrulamanın anahtarı; buradan değiştirilirse
              // yeniden kimlik doğrulama gerekir. Kapsam dışı, ama neden
              // düzenlenemediği söylenmeli.
              Text(l10n.emailChangeNote, style: RythoType.caption),
              // KT4: kayıtta doğrulama postası gidiyordu ama uygulamada ne
              // durum görünüyordu ne yeniden gönderme yolu vardı — snackbar
              // ekran geçişinde kayboluyordu. Kalıcı yüzeyi burası.
              if (FirebaseAuth.instance.currentUser?.emailVerified ==
                  false) ...[
                const SizedBox(height: RythoSpace.sm),
                Row(children: [
                  Expanded(
                    child: Text(l10n.emailNotVerified,
                        style: RythoText.body(12.5,
                            color: RythoColors.madder)),
                  ),
                  // Düğme esnemiyordu: soldaki uyarı `Expanded` içinde
                  // sıfıra inse bile "Tekrar gönder" + iç dolgu dar
                  // ekranda satırı taşırıyordu.
                  Flexible(
                      child: TextButton(
                    onPressed: _dogrulamaGonderildi
                        ? null
                        : () async {
                            final mesajci =
                                ScaffoldMessenger.of(context);
                            try {
                              await FirebaseAuth.instance.currentUser
                                  ?.sendEmailVerification();
                            } catch (_) {}
                            if (!mounted) return;
                            setState(() => _dogrulamaGonderildi = true);
                            mesajci.showSnackBar(SnackBar(
                                content: Text(l10n.emailVerifySent)));
                          },
                    child: Text(l10n.emailVerifyResend,
                        style: RythoType.button),
                  )),
                ]),
              ],
            ],
            // Telefon (Revize R2): doğrulanmış numara rehber eşleşmesinin
            // anahtarı. Durum yerelden okunur (FirebaseAuth.phoneNumber) —
            // Firestore'a ham numara hiç yazılmıyor.
            const SizedBox(height: RythoSpace.xl),
            Text(l10n.phoneSectionLabel, style: RythoType.label),
            const SizedBox(height: RythoSpace.xs),
            Builder(builder: (context) {
              final numara =
                  FirebaseAuth.instance.currentUser?.phoneNumber;
              return Row(children: [
                Expanded(
                  child: Text(
                    numara ?? l10n.phoneNotLinked,
                    style: numara != null
                        ? RythoType.data
                        : RythoType.bodyDim,
                  ),
                ),
                // Düğme esnemiyordu: soldaki numara `Expanded` içinde
                // sıfıra inse bile "Numarayı değiştir" dar ekranda satırı
                // taşırıyordu.
                Flexible(
                  child: TextButton(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) => const PhoneVerifyScreen()))
                        .then((_) => setState(() {})),
                    child: Text(
                        numara != null
                            ? l10n.phoneChangeAction
                            : l10n.phoneVerifyAction,
                        style: RythoType.button),
                  ),
                ),
              ]);
            }),
            const SizedBox(height: RythoSpace.xxl),
            GoldButton(
              text: l10n.save,
              busy: _mesgul,
              onPressed: _degisti ? _kaydet : null,
            ),
            // Hesap silme (R3-5): profil dibinden buraya taşındı — hesapla
            // ilgili her şey tek başlık altında. Mağaza kuralı ("gömülü
            // olmamalı") korunur: Profil → Hesap tek dokunuş ve satır
            // açıkça görünür. Yazarak-onay akışı aynı (DeleteAccountSheet).
            const SizedBox(height: RythoSpace.lg),
            Center(
              child: TextButton(
                onPressed: () => showDeleteAccountSheet(context),
                child: Text(
                  l10n.deleteAccount,
                  style:
                      RythoText.label(12, color: RythoColors.parchmentDim),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

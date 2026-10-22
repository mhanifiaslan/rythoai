import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../widgets/onay.dart' show onayla;
import 'api.dart' show friendlyError;
import 'friends.dart' show engelledimMi;
import 'providers.dart' show authStateProvider;

/// Kullanıcı güvenliği yardımcıları: şikayet (report) ve engelleme (block).
/// Şikayetler `reports` koleksiyonuna yazılır ve yalnızca konsoldan incelenir;
/// engellenenler `users/{uid}/blocked/{targetUid}` altında tutulur.

/// Şikayet sebepleri. Anahtar Firestore'a yazılır ve **dilden bağımsızdır**;
/// kullanıcıya gösterilen etiket [reportReasonLabel] ile çözülür. Etiketi
/// kaydetseydik aynı sebep dile göre iki farklı değerle birikirdi ve
/// incelemede gruplanamazdı.
const List<String> kReportReasons = [
  'spam',
  'harassment',
  'inappropriate',
  'other',
];

String reportReasonLabel(AppLocalizations l10n, String key) => switch (key) {
      'spam' => l10n.reportReasonSpam,
      'harassment' => l10n.reportReasonHarassment,
      'inappropriate' => l10n.reportReasonInappropriate,
      _ => l10n.reportReasonOther,
    };

/// Şikayeti Firestore'a yazar. targetType: 'post' | 'user'.
Future<void> submitReport({
  required String targetType,
  required String targetId,
  required String reason,
}) async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  await FirebaseFirestore.instance.collection('reports').add({
    'reporterId': uid,
    'targetType': targetType,
    'targetId': targetId,
    'reason': reason,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// Sebep seçtiren cam görünümlü şikayet sayfası (bottom sheet).
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: RythoColors.inkLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(color: RythoColors.glassStroke),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            targetType == 'post' ? l10n.reportPostTitle : l10n.reportUserTitle,
            style: RythoText.mono(11, color: RythoColors.parchmentDim),
          ),
          const SizedBox(height: 6),
          Text(l10n.reportNote,
              style: RythoText.body(12.5, color: RythoColors.parchmentDim)),
          const SizedBox(height: 10),
          for (final reason in kReportReasons)
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              leading: const Text('⚑',
                  style: TextStyle(color: RythoColors.copper, fontSize: 15)),
              title: Text(reportReasonLabel(l10n, reason),
                  style: RythoText.body(14)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                try {
                  await submitReport(
                    targetType: targetType,
                    targetId: targetId,
                    reason: reason,
                  );
                  messenger.showSnackBar(
                      SnackBar(content: Text(l10n.reportSubmitted)));
                } catch (_) {
                  messenger.showSnackBar(
                      SnackBar(content: Text(l10n.reportFailed)));
                }
              },
            ),
        ]),
      ),
    ),
  );
}

DocumentReference<Map<String, dynamic>> _blockedRef(String targetUid) {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('blocked')
      .doc(targetUid);
}

/// Kullanıcıyı engeller (U17, App Store 1.2): arkadaşlık kenarlarını İKİ
/// taraftan siler ve engel kaydını yazar — TEK batch'te.
///
/// Kayıt yalnız saklanmıyor, üç yerde okunuyor: firestore.rules (engellenen
/// yeni davet kenarı kuramaz), sunucunun davet push'u (atlanır) ve rehber
/// eşleşmesi (engelleyenin kartı engellenene dönmez). Dürtmenin ayrı kapısı
/// yok: kuralı alıcının ağacında `accepted` kenar istiyor ve buradaki silim
/// o kenarı kaldırıyor.
///
/// Neden tek batch: eskiden `removeFriend` ve ardından `blockUser` iki ayrı
/// yazımdı. İkincisi düşseydi arkadaşlık gitmiş ama engel yazılmamış olurdu
/// ve karşı taraf yeniden davet atabilirdi; sıra ters çevrilseydi engel
/// yazılıp kenarlar kalabilirdi — bekleyen istek ekranda, kabul edilmiş
/// arkadaşlık (dürtme yolu) açık. Batch hepsini birlikte yazar ya da
/// hiçbirini. Zaten engelli birine yeniden `set` kurala göre update'tir;
/// kural bu yüzden `update`'e de izin veriyor.
Future<void> kullaniciyiEngelle(String hedefUid) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw StateError('Oturum yok');
  final db = FirebaseFirestore.instance;
  final kullanicilar = db.collection('users');
  final batch = db.batch()
    ..delete(kullanicilar.doc(uid).collection('friends').doc(hedefUid))
    ..delete(kullanicilar.doc(hedefUid).collection('friends').doc(uid))
    ..set(_blockedRef(hedefUid), {'at': FieldValue.serverTimestamp()});
  await batch.commit();
}

/// Engeli kaldırır. Eski arkadaşlığı GERİ GETİRMEZ: engelleme kenarları
/// silmişti; yeniden arkadaş olmak için yeni bir davet gerekir.
Future<void> engeliKaldir(String hedefUid) => _blockedRef(hedefUid).delete();

/// Tek kullanıcı üzerinde yazım işlemi (engelle / engeli kaldır).
typedef KullaniciIslemi = Future<void> Function(String uid);

/// Engelleme işlevi — TEST DİKİŞİ: istek kutucuğunun ve arkadaş menüsünün
/// "Engelle" dalı Firebase kurulmadan ancak bununla ölçülebiliyor
/// (bkz. core/subscription.dart `paketSatinAliciProvider`).
final engelleyiciProvider =
    Provider<KullaniciIslemi>((_) => kullaniciyiEngelle);

/// Engel kaldırma işlevi — TEST DİKİŞİ ([engelleyiciProvider] gerekçesi).
final engelKaldiriciProvider = Provider<KullaniciIslemi>((_) => engeliKaldir);

/// Engellenenler listesinin bir satırı.
class EngellenenKullanici {
  const EngellenenKullanici({
    required this.uid,
    this.displayName,
    this.username,
    this.at,
  });

  final String uid;
  final String? displayName;
  final String? username;

  /// Engelleme anı; sunucu zamanı henüz inmemişse null.
  final DateTime? at;
}

/// Engellenen kullanıcılar, herkese açık kartlarıyla (Profil > Gizlilik >
/// Engellenenler).
///
/// Ad `publicProfiles/{uid}`den okunur — kural `get`'i girişli herkese
/// açıyor, `users/{uid}` ise yalnız sahibine. Satırların kuruluşu
/// [engellenenleriKur]da (saf, ölçülebilir).
///
/// Eski `blockedUsersProvider`ın (providers.dart) yerine geçti. O sağlayıcı
/// "akış ve mesajlar bu kümeye göre filtrelenir" diyordu ama hiçbir yer onu
/// okumuyordu — engel kaydının saklanıp uygulanmamasının (U17) istemcideki
/// yüzü buydu.
final engellenenlerProvider =
    StreamProvider<List<EngellenenKullanici>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const <EngellenenKullanici>[]);
  final db = FirebaseFirestore.instance;
  return _engelKoleksiyonu(user.uid).snapshots().asyncMap((snapshot) {
    final kayitlar = [
      for (final doc in snapshot.docs)
        (
          uid: doc.id,
          at: switch (doc.data()['at']) {
            final Timestamp t => t.toDate(),
            _ => null,
          },
        ),
    ];
    return engellenenleriKur(kayitlar,
        (uid) async => (await db.collection('publicProfiles').doc(uid).get())
            .data());
  });
});

/// `blocked` kayıtlarından Engellenenler satırlarını kurar — SAF: kart
/// okuyucu dışarıdan gelir, sahte Firestore olmadan ölçülür.
///
/// İki söz burada tutulur: kartı OKUNAMAYAN (silinmiş hesap, ağ hatası)
/// kişi listeden DÜŞMEZ — satır adsız çizilir, çünkü engeli kaldırma yolu
/// adı bilinmeyen kişi için de açık kalmalı; ve en yeni engel üstte —
/// zamanı henüz inmemiş (`at == null`) kayıt az önce yazılmıştır, en üste.
Future<List<EngellenenKullanici>> engellenenleriKur(
  Iterable<({String uid, DateTime? at})> kayitlar,
  Future<Map<String, dynamic>?> Function(String uid) kartOku,
) async {
  final liste = <EngellenenKullanici>[];
  for (final kayit in kayitlar) {
    Map<String, dynamic>? kart;
    try {
      kart = await kartOku(kayit.uid);
    } catch (_) {
      // Adsız satır; yukarıdaki gerekçe.
    }
    liste.add(EngellenenKullanici(
      uid: kayit.uid,
      displayName: kart?['displayName'] as String?,
      username: kart?['username'] as String?,
      at: kayit.at,
    ));
  }
  liste.sort((a, b) {
    if (a.at == null) return b.at == null ? 0 : -1;
    if (b.at == null) return 1;
    return b.at!.compareTo(a.at!);
  });
  return liste;
}

CollectionReference<Map<String, dynamic>> _engelKoleksiyonu(String uid) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('blocked');

/// Engellediğim kişilerin kimlikleri — gelen kutusu süzgeci için
/// ([gorunurTepkiler]); kart okumaz.
final engellenenKimliklerProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const <String>{});
  return _engelKoleksiyonu(user.uid)
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toSet());
});

/// Gelen kutusunda gösterilecek tepkiler: engellediklerimin tepkileri düşer.
///
/// NEDEN süzgeç, silim değil: engelleme engellenenin ESKİ tepkilerine
/// dokunmuyor (göndericiye göre silmek önce okumayı ister, batch okumaz) ve
/// kutuda "Bir arkadaşın · Seni düşündüm" gibi kalıyorlardı. Süzgeç eski veriyi
/// de, kural dağıtılmadan önce kurulmuş arkadaşlıkları da kapsar.
///
/// Engel listesi henüz YOKSA (yükleniyor, okunamadı) hiçbir tepki
/// gösterilmez: engellenenin tepkisinin bir an görünmesi, meşru tepkinin
/// bir an gecikmesinden ağırdır — tepkiler Firestore'da durur, liste
/// gelince görünür.
List<Map<String, dynamic>> gorunurTepkiler(
    List<Map<String, dynamic>> tepkiler, Set<String>? engellenenler) {
  if (engellenenler == null) return const [];
  return [
    for (final t in tepkiler)
      if (!engellenenler.contains(t['fromUid'])) t,
  ];
}

/// Davetten önce engel kararı (U17 incelemesi).
enum DavetKarari {
  /// Engel yok: düz davet.
  gonder,

  /// Engel var, kullanıcı kaldırmayı onayladı: engel silimi davetle TEK
  /// batch'te (`sendFriendRequest(engeliKaldir: true)`).
  engeliKaldirVeGonder,

  /// Engel var, kullanıcı vazgeçti: hiçbir şey yazılmaz.
  vazgec,
}

/// Engel okuma işlevi — TEST DİKİŞİ ([engelleyiciProvider] gerekçesi).
final engelKontroluProvider =
    Provider<Future<bool> Function(String uid)>((_) => engelledimMi);

/// Engellediğin kişiye davet atmadan önce sorar.
///
/// NEDEN: kural sahip dalında engel kaydına bakıyor (`existsAfter`) —
/// engelleyen, engellediğine davet atamaz. Soru olmasaydı o davet
/// `permission-denied` ile düşer ve kullanıcı nedenini bilmezdi; kendi
/// koyduğu engeli unutmuş olabilir. Kaldırma yanlış dokunuşla olmamalı:
/// onay ister ([onayla]; yıkıcı değil, geri dönüşü var).
///
/// Engel OKUNAMAZSA düz davet denenir ve engel KALDIRILMAZ: engel varsa
/// kural reddeder, kullanıcı nötr cümleyi görür ([davetHataMetni]).
/// Kaldırma yolu yalnız açık onayla açılır.
Future<DavetKarari> davetEngelKapisi(
    BuildContext context, WidgetRef ref, String hedefUid, String ad) async {
  final l10n = AppLocalizations.of(context);
  final kontrol = ref.read(engelKontroluProvider);
  bool engelli;
  try {
    engelli = await kontrol(hedefUid);
  } catch (_) {
    return DavetKarari.gonder;
  }
  if (!engelli) return DavetKarari.gonder;
  if (!context.mounted) return DavetKarari.vazgec;
  final tamam = await onayla(
    context,
    title: l10n.inviteBlockedTitle,
    body: l10n.inviteBlockedBody(ad),
    confirmLabel: l10n.inviteBlockedConfirm,
  );
  return tamam ? DavetKarari.engeliKaldirVeGonder : DavetKarari.vazgec;
}

/// Davet yazımı düşünce gösterilecek cümle.
///
/// `permission-denied` → nötr "Davet gönderilemedi.": kural dağıtılınca
/// engellenen kişinin davet batch'i bununla düşüyor ve `friendlyError` onu
/// "beklenmeyen bir sorun… biraz sonra tekrar dene"ye çeviriyordu — o
/// deneme hiç tutmaz. Cümle engeli ELE VERMEZ (engellenene engellendiği
/// söylenmez) ve tekrar denemeyi önermez. Diğer hatalar (bağlantı vb.)
/// ortak süzgeçten geçer.
String davetHataMetni(Object hata, AppLocalizations l10n) {
  if (hata is FirebaseException && hata.code == 'permission-denied') {
    return l10n.inviteNotSent;
  }
  return friendlyError(hata, l10n);
}

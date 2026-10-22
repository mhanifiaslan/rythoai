import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
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
/// açıyor, `users/{uid}` ise yalnız sahibine. Kart yoksa ya da okunamazsa
/// satır ADSIZ çizilir ama çizilir: engeli kaldırma yolu adı bilinmeyen
/// kişi için de açık kalmalı.
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
  return db
      .collection('users')
      .doc(user.uid)
      .collection('blocked')
      .snapshots()
      .asyncMap((snapshot) async {
    final liste = <EngellenenKullanici>[];
    for (final doc in snapshot.docs) {
      Map<String, dynamic>? kart;
      try {
        kart = (await db.collection('publicProfiles').doc(doc.id).get()).data();
      } catch (_) {
        // Adsız satır; yukarıdaki gerekçe.
      }
      final at = doc.data()['at'];
      liste.add(EngellenenKullanici(
        uid: doc.id,
        displayName: kart?['displayName'] as String?,
        username: kart?['username'] as String?,
        at: at is Timestamp ? at.toDate() : null,
      ));
    }
    // En yeni engel üstte. Zamanı henüz inmemiş kayıt az önce yazılmıştır.
    liste.sort((a, b) {
      if (a.at == null) return b.at == null ? 0 : -1;
      if (b.at == null) return 1;
      return b.at!.compareTo(a.at!);
    });
    return liste;
  });
});

import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../widgets/onay.dart' show onayla;
import 'api.dart' show friendlyError;
import 'friends.dart'
    show Friend, FriendStatus, dismissNudge, engelledimMi, myNudgesProvider;
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
/// Kayıt yalnız saklanmıyor, OKUNUYOR — liste sayıyla yazılmaz, büyüyor:
/// firestore.rules (davet kenarının iki dalı, kabulün iki dalı, tepki
/// yazımı), sunucu (`/notify/invite`, `/notify/reaction`,
/// `/contacts/match`) ve istemci (davet öncesi soru, gelen kutusu, gelen
/// istekler). Buradaki kenar silimi ayrıca kabul edilmiş arkadaşlığı
/// bitirir; tepki kuralı zaten `accepted` kenar istiyor.
///
/// Engellenenin bana BIRAKTIĞI tepkiler batch'e girmiyor (göndericiye göre
/// silmek önce okumayı ister, batch okumaz): commit'ten sonra en iyi
/// çabayla ayrıca siliniyor ([_engellenenTepkileriniSil]); kalan olursa
/// gelen kutusu onları süzer ve siler ([engellenenTepkileriProvider]).
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
  unawaited(_engellenenTepkileriniSil(uid, hedefUid));
}

/// Engellenenin bana bıraktığı tepkileri siler — EN İYİ ÇABA: engel zaten
/// yazıldı; bu silim düşerse gelen kutusu süzgeci tepkileri gizler ve bir
/// sonraki görüşte yeniden siler. Kural sahibin `nudges` okuma ve silmesine
/// izin veriyor.
Future<void> _engellenenTepkileriniSil(String uid, String hedefUid) async {
  try {
    final db = FirebaseFirestore.instance;
    final tepkiler = await db
        .collection('users')
        .doc(uid)
        .collection('nudges')
        .where('fromUid', isEqualTo: hedefUid)
        .get();
    if (tepkiler.docs.isEmpty) return;
    final batch = db.batch();
    for (final d in tepkiler.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  } catch (_) {
    // Yukarıdaki gerekçe: süzgeç ikinci hat.
  }
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

/// Engellediğim kişilerin kimlikleri — gelen kutusu ([tepkileriAyir]) ve
/// gelen istekler ([gelenIstekleriSuz]) için; kart okumaz.
final engellenenKimliklerProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const <String>{});
  return _engelKoleksiyonu(user.uid)
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toSet());
});

/// Gelen kutusunu ikiye ayırır — SAF: gösterilecekler ve engellediklerimden
/// kalanların doküman kimlikleri.
///
/// NEDEN yalnız süzmek yetmiyor: `myNudgesProvider` son 20 tepkiyi okuyor
/// (`orderBy(createdAt).limit(20)`). Engellenenin tepkileri yalnız
/// gizlenseydi o pencerede KALICI yer tutar, görünmedikleri için dokunarak
/// da silinemez ve daha eski meşru tepkilere bir daha ulaşılamazdı.
/// [engellenenden] bu yüzden sessizce silinir ([engellenenTepkileriProvider]).
/// Süzgeç ikinci hat olarak kalır: silim düşse ya da sürse de ekranda yok.
({List<Map<String, dynamic>> gorunur, List<String> engellenenden})
    tepkileriAyir(
        List<Map<String, dynamic>> tepkiler, Set<String> engellenenler) {
  final gorunur = <Map<String, dynamic>>[];
  final engellenenden = <String>[];
  for (final t in tepkiler) {
    if (engellenenler.contains(t['fromUid'])) {
      if (t['id'] case final String id) engellenenden.add(id);
    } else {
      gorunur.add(t);
    }
  }
  return (gorunur: gorunur, engellenenden: engellenenden);
}

/// Engellediklerimden kalan tepkilerin kimlikleri — gelen kutusu bunları
/// sessizce siler. Engel listesi henüz yoksa boş: bilinmeyen engele göre
/// hiçbir şey silinmez.
final engellenenTepkileriProvider = Provider<List<String>>((ref) {
  final engellenenler = ref.watch(engellenenKimliklerProvider).value;
  if (engellenenler == null) return const [];
  final tepkiler = ref.watch(myNudgesProvider).value ?? const [];
  return tepkileriAyir(tepkiler, engellenenler).engellenenden;
});

/// Tepki silme işlevi — TEST DİKİŞİ ([engelleyiciProvider] gerekçesi).
final tepkiSiliciProvider =
    Provider<Future<void> Function(String id)>((_) => dismissNudge);

/// Gelen istekler bölümünden engellediklerimin isteklerini düşürür — SAF.
///
/// Böyle bir istek yeni kuralla KURULAMAZ (counterpart create engel kaydına
/// bakıyor); yalnız kural dağıtımından önce kurulmuş istekler kalabilir ve
/// kabulleri de kuralda kapalı. Engel listesi YOKSA (yükleniyor,
/// okunamadı) liste OLDUĞU GİBİ döner — gelen kutusunun tersine: orada
/// görünen şey engellenenin kendi tepkisi; burada tümünü gizlemek her
/// meşru isteği sessizce kaybettirirdi, gösterilen eski bir istek ise
/// kurala çarptığı için kabul edilemez ve Yoksay/Engelle ile kaldırılabilir.
List<Friend> gelenIstekleriSuz(List<Friend> liste, Set<String>? engellenenler) {
  if (engellenenler == null || engellenenler.isEmpty) return liste;
  return [
    for (final f in liste)
      if (f.status != FriendStatus.incoming || !engellenenler.contains(f.uid))
        f,
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'providers.dart';

/// Arkadaş katmanı veri erişimi.
///
/// Tasarım kuralı: **hiçbir yerde serbest metin yok.** Kullanıcılar birbirine
/// yalnızca [kReactions] içindeki kapalı kümeden bir tepki gönderebilir.
/// Bu sayede içerik moderasyonu operasyonu gerekmez (App Store 1.2 / DSA).
///
/// Gizlilik: arkadaşın ham doğum verisi hiçbir zaman okunmaz. Liste
/// `publicProfiles/{uid}` üzerinden çalışır; oraya doğum verisi yazılmaz
/// (bkz. infra/firestore.rules).

/// Gönderilebilecek hazır tepkiler: anahtar -> emoji.
///
/// Anahtarlar Firestore kurallarındaki listeyle **birebir aynı** olmak
/// zorundadır (infra/firestore.rules) ve dile göre DEĞİŞMEZ. Gösterilen
/// etiket `reactionLabel()` ile çözülür (features/friends).
const Map<String, String> kReactions = {
  'streak': '🔥',
  'thinking_of_you': '💭',
  'shine': '✨',
  'keep_going': '💪',
  'congrats': '🎉',
  'same_frequency': '🛰️',
  'good_night': '🌙',
  'check_today': '👀',
  // R3-4 genişlemesi (kullanıcı seçimi): sıcak/sosyal tepkiler.
  'hug': '🤗',
  'luck': '🍀',
  'coffee': '☕',
  'miss': '🫶',
};

/// Arkadaşlık durumu. `outgoing`: ben davet ettim, `incoming`: bana davet
/// geldi, `accepted`: karşılıklı onaylandı.
enum FriendStatus { outgoing, incoming, accepted }

FriendStatus? _statusFromName(String? raw) {
  for (final status in FriendStatus.values) {
    if (status.name == raw) return status;
  }
  return null;
}

class Friend {
  const Friend({
    required this.uid,
    required this.status,
    this.displayName,
    this.username,
    this.sunSign,
    this.streakCount,
    this.streakVisible = false,
    this.lastSeenDaily,
  });

  final String uid;
  final FriendStatus status;
  final String? displayName;
  final String? username;
  final String? sunSign;
  final int? streakCount;
  final bool streakVisible;
  final String? lastSeenDaily;

  /// Veri katmanının adı: kart yoksa BOŞ. Ekrana basılacak ad [ad]'dan
  /// alınır — eski hâli burada `'Gezgin'` yazıyordu ve İngilizce cihazda
  /// kartsız arkadaş Türkçe bir sözcükle görünüyordu. Yedek sözcük bir
  /// çeviri işidir, modelin işi değil (`api.dart friendlyError` emsali:
  /// l10n'siz yedek metin gövdeye gömülmez).
  String get name => displayName ?? username ?? '';

  /// Ekranda görünen ad; kart yoksa dilin yedeği (`defaultUserName`).
  String ad(AppLocalizations l10n) =>
      displayName ?? username ?? l10n.defaultUserName;

  /// Arkadaş bugünkü okumasını yaptı mı? Seri gizliyse bilinmez.
  bool get readToday {
    if (!streakVisible || lastSeenDaily == null) return false;
    return lastSeenDaily == _todayKey();
  }

  Friend withCard(Map<String, dynamic>? card) {
    if (card == null) return this;
    return Friend(
      uid: uid,
      status: status,
      displayName: card['displayName'] as String?,
      username: card['username'] as String?,
      sunSign: card['sunSign'] as String?,
      streakCount: (card['streakCount'] as num?)?.toInt(),
      streakVisible: card['streakVisible'] == true,
      lastSeenDaily: card['lastSeenDaily'] as String?,
    );
  }
}

String _todayKey([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

FirebaseFirestore get _db => FirebaseFirestore.instance;
String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

CollectionReference<Map<String, dynamic>> _friendsOf(String uid) =>
    _db.collection('users').doc(uid).collection('friends');

// ---------------------------------------------------------------------------
// Kullanıcı adı
// ---------------------------------------------------------------------------

/// Kullanıcı adı kuralları: 3-20 karakter, küçük harf/rakam/alt çizgi.
final RegExp kUsernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

/// Kullanıcı adı hatası kodları. Bu katman veri katmanıdır ve `BuildContext`
/// görmez; metin yerine **kod** döndürür, arayüz [UsernameError] üzerinden
/// kendi dilinde metne çevirir (bkz. friends_screen.dart).
enum UsernameError { empty, invalid, taken }

UsernameError? validateUsername(String value) {
  final v = value.trim().toLowerCase();
  if (v.isEmpty) return UsernameError.empty;
  if (!kUsernamePattern.hasMatch(v)) return UsernameError.invalid;
  return null;
}

/// Kullanıcı adı işlemlerinin fırlattığı hata. Mesaj taşımaz — kod taşır.
class UsernameException implements Exception {
  const UsernameException(this.error);
  final UsernameError error;
}

/// Kullanıcı adını rezerve eder ve profile yazar.
///
/// Benzersizlik Firestore tarafında sağlanır: `usernames/{username}` dokümanı
/// zaten varsa `create` başarısız olur (bkz. infra/firestore.rules).
/// Eski kullanıcı adı varsa serbest bırakılır.
Future<void> claimUsername(String rawUsername) async {
  final uid = _myUid;
  if (uid == null) throw StateError('Oturum yok');
  final username = rawUsername.trim().toLowerCase();

  final error = validateUsername(username);
  if (error != null) throw UsernameException(error);

  final me = await _db.collection('users').doc(uid).get();
  final previous = me.data()?['username'] as String?;
  if (previous == username) return;

  try {
    await _db.collection('usernames').doc(username).set({
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } on FirebaseException catch (e) {
    if (e.code == 'permission-denied') {
      throw const UsernameException(UsernameError.taken);
    }
    rethrow;
  }

  await _db.collection('users').doc(uid).set(
      {'username': username}, SetOptions(merge: true));
  await syncPublicProfile();

  if (previous != null && previous.isNotEmpty) {
    // Eski adı serbest bırak; başarısız olursa kritik değil.
    try {
      await _db.collection('usernames').doc(previous).delete();
    } catch (_) {}
  }
}

/// Herkese açık profil kartını (`publicProfiles/{uid}`) günceller.
///
/// Arkadaşlar `users/{uid}` dokümanını okuyamaz (doğum verisi içerir);
/// listede görünen her şey bu karttan gelir.
Future<void> syncPublicProfile() async {
  final uid = _myUid;
  if (uid == null) return;
  final profile = (await _db.collection('users').doc(uid).get()).data();
  if (profile == null) return;

  await _db.collection('publicProfiles').doc(uid).set({
    'uid': uid,
    'displayName': profile['displayName'],
    'photoUrl': profile['photoUrl'],
    'username': profile['username'],
    'sunSign': profile['sunSign'],
    'streakCount': profile['streakCount'] ?? 0,
    'streakVisible': profile['streakVisible'] == true,
    // Seri gizliyse "bugün okudu mu" bilgisi de paylaşılmaz.
    'lastSeenDaily':
        profile['streakVisible'] == true ? profile['lastSeenDaily'] : null,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Serinin arkadaşlara görünürlüğünü açar/kapatır (varsayılan: kapalı).
Future<void> setStreakVisible(bool visible) async {
  final uid = _myUid;
  if (uid == null) return;
  await _db.collection('users').doc(uid).set(
      {'streakVisible': visible}, SetOptions(merge: true));
  await syncPublicProfile();
}

/// Rehber eşleşmesini açar/kapatır (varsayılan: KAPALI).
///
/// Bu alan karşılıklılığın yarısı: sunucu eşleşme dönerken iki tarafın da
/// açık olmasını arar — kapatmak seni ANINDA görünmez yapar.
Future<void> setContactMatch(bool enabled) async {
  final uid = _myUid;
  if (uid == null) return;
  await _db.collection('users').doc(uid).set(
      {'contactMatch': enabled}, SetOptions(merge: true));
}

// ---------------------------------------------------------------------------
// Arkadaşlık akışı
// ---------------------------------------------------------------------------

/// Kullanıcı adından kimlik çözer; bulunamazsa `null`.
Future<String?> uidForUsername(String rawUsername) async {
  final username = rawUsername.trim().toLowerCase();
  final doc = await _db.collection('usernames').doc(username).get();
  return doc.data()?['uid'] as String?;
}

/// Davet gönderir: kendi listeme `outgoing`, karşı tarafa `incoming` yazılır.
Future<void> sendFriendRequest(String otherUid) async {
  final uid = _myUid;
  if (uid == null) throw StateError('Oturum yok');
  if (otherUid == uid) throw ArgumentError('Kendini ekleyemezsin.');

  final now = FieldValue.serverTimestamp();
  final batch = _db.batch();
  batch.set(_friendsOf(uid).doc(otherUid),
      {'status': 'outgoing', 'createdAt': now, 'updatedAt': now});
  batch.set(_friendsOf(otherUid).doc(uid),
      {'status': 'incoming', 'createdAt': now, 'updatedAt': now});
  await batch.commit();
}

/// Gelen daveti kabul eder: iki taraf da `accepted` olur.
Future<void> acceptFriendRequest(String otherUid) async {
  final uid = _myUid;
  if (uid == null) throw StateError('Oturum yok');

  final now = FieldValue.serverTimestamp();
  final batch = _db.batch();
  batch.set(_friendsOf(uid).doc(otherUid),
      {'status': 'accepted', 'updatedAt': now}, SetOptions(merge: true));
  batch.set(_friendsOf(otherUid).doc(uid),
      {'status': 'accepted', 'updatedAt': now}, SetOptions(merge: true));
  await batch.commit();
}

/// Arkadaşlığı (veya daveti) iki taraftan da kaldırır.
Future<void> removeFriend(String otherUid) async {
  final uid = _myUid;
  if (uid == null) return;
  final batch = _db.batch();
  batch.delete(_friendsOf(uid).doc(otherUid));
  batch.delete(_friendsOf(otherUid).doc(uid));
  await batch.commit();
}

/// Hazır tepki gönderir. [reaction] [kReactions] anahtarlarından biri olmalı;
/// aksi halde Firestore kuralı reddeder.
Future<void> sendReaction(String toUid, String reaction) async {
  final uid = _myUid;
  if (uid == null) throw StateError('Oturum yok');
  if (!kReactions.containsKey(reaction)) {
    throw ArgumentError('Tanımsız tepki: $reaction');
  }
  await _db.collection('users').doc(toUid).collection('nudges').add({
    'fromUid': uid,
    'reaction': reaction,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// Tepkinin push bildirimini tetikler.
///
/// Firestore yazımından AYRI bir adım: bildirim gitmese bile tepki
/// kaydedilmiş olmalı ve arkadaşın gelen kutusunda görünmeli. Bu yüzden
/// hata yutuluyor — push bir ek, tepkinin kendisi değil.
///
/// Metni sunucu üretir ve arkadaşlığı sunucu doğrular; istemci yalnızca
/// "şu arkadaşa şu tepkiyi gönderdim" der.
Future<void> notifyReaction(Dio dio, String toUid, String reaction) async {
  try {
    await dio.post('/api/v1/notify/reaction',
        data: {'friend_uid': toUid, 'reaction': reaction});
  } catch (e) {
    debugPrint('Tepki bildirimi gönderilemedi: $e');
  }
}

/// Davet push'unu tetikler (OB2) — [notifyReaction] ile aynı sözleşme:
/// Firestore yazımından ayrı, ateşle-unut, hata yutulur. Sunucu davetin
/// GERÇEKTEN var olduğunu (`incoming` kenarı) kendisi doğrular.
Future<void> notifyInvite(Dio dio, String toUid) async {
  try {
    await dio.post('/api/v1/notify/invite', data: {'friend_uid': toUid});
  } catch (e) {
    debugPrint('Davet bildirimi gönderilemedi: $e');
  }
}

/// Kabul push'unu daveti GÖNDERENE tetikler (OB2). Ateşle-unut.
Future<void> notifyInviteAccepted(Dio dio, String toUid) async {
  try {
    await dio.post('/api/v1/notify/invite-accepted',
        data: {'friend_uid': toUid});
  } catch (e) {
    debugPrint('Kabul bildirimi gönderilemedi: $e');
  }
}

/// Gelen tepkiyi okundu sayıp siler.
Future<void> dismissNudge(String nudgeId) async {
  final uid = _myUid;
  if (uid == null) return;
  await _db.collection('users').doc(uid).collection('nudges').doc(nudgeId).delete();
}

// Davet bağlantısı üretimi core/deep_links.dart'a taşındı: bağlantının
// üretildiği yer ile yakalandığı yer aynı sabiti kullanmak zorunda. Buradaki
// eski hâli var olmayan bir alan adına (rytho.ai) işaret ediyordu — panoya
// kopyalanan bağlantı hiçbir yere gitmiyordu.

// ---------------------------------------------------------------------------
// Sağlayıcılar
// ---------------------------------------------------------------------------

/// Arkadaş listesi — her kayıt herkese açık profil kartıyla zenginleştirilir.
final friendsProvider = StreamProvider<List<Friend>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const <Friend>[]);

  return _friendsOf(user.uid).snapshots().asyncMap((snapshot) async {
    final friends = <Friend>[];
    for (final doc in snapshot.docs) {
      final status = _statusFromName(doc.data()['status'] as String?);
      if (status == null) continue;
      final base = Friend(uid: doc.id, status: status);
      final card = await _db.collection('publicProfiles').doc(doc.id).get();
      friends.add(base.withCard(card.data()));
    }
    friends.sort((a, b) {
      // Önce gelen davetler, sonra kabul edilmiş arkadaşlar, sonra gidenler.
      int rank(FriendStatus s) => switch (s) {
            FriendStatus.incoming => 0,
            FriendStatus.accepted => 1,
            FriendStatus.outgoing => 2,
          };
      final byStatus = rank(a.status).compareTo(rank(b.status));
      if (byStatus != 0) return byStatus;
      return (b.streakCount ?? 0).compareTo(a.streakCount ?? 0);
    });
    return friends;
  });
});

/// Bana gelen son tepkiler (okunmamış "dürtme"ler).
final myNudgesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return _db
      .collection('users')
      .doc(user.uid)
      .collection('nudges')
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

/// EKLENEN KİŞİLER — kullanıcının kendi girdiği eş, çocuk, ebeveyn, yakın.
///
/// ## Arkadaştan farkı
///
/// Arkadaş karşılıklı rızayla eklenen bir Rytho KULLANICISIDIR; bu kişi
/// değildir. Hesabı yok, tepki gönderemez, serisi olmaz. Ekranda o
/// etkileşimleri çizmek olmayan bir şeyi varmış gibi göstermek olurdu
/// (bkz. features/friends/friends_screen.dart satır anatomisi).
///
/// ## Ad neden sunucuda değil
///
/// Bu kişilerin rızası ALINAMIYOR. Ad + doğum tarihi + doğum yeri üçlüsü
/// kimlik doğrulama sorularında kullanılan hassas bir kümedir; üçüncü bir
/// kişinin bu kümesini rızası olmadan sunucuya yazmıyoruz. Doğum verisi
/// sunucuda (harita orada hesaplanıyor), **etiket cihazda**. Sunucunun
/// gördüğü tek kimlik işareti [Person.relation] ve AI kişiyi "eşin" /
/// "çocuğun" diye anıyor.
///
/// Bedeli: telefon değişince doğum verisi durur, etiketler yeniden yazılır.
/// Bu bilinçli bir takas — bkz. backend/services/people_service.py.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'providers.dart';

/// Kişi türleri. Backend `people_service.RELATIONS` ile **birebir aynı**
/// olmak zorunda; tür yalnız simge değil, ilişki eksenlerinin adını ve
/// AI'nın çerçevesini belirliyor (çocukla "çekim" ekseni gösterilmez).
const List<String> kRelations = [
  'partner',
  'child',
  'parent',
  'sibling',
  'friend',
  'work',
  'other',
];

class Person {
  const Person({
    required this.id,
    required this.relation,
    required this.birthDate,
    required this.birthCity,
    this.label,
    this.birthTime,
    this.birthNation,
    this.gender,
    this.sunSign,
    this.moonSign,
    this.ascendant,
  });

  final String id;
  final String relation;

  /// Kullanıcının verdiği ad — **yalnızca bu cihazda**. Sunucu bilmez.
  /// Boşsa arayüz ilişki türünün yerelleştirilmiş adını gösterir.
  final String? label;

  /// `YYYY-MM-DD`.
  final String birthDate;

  /// `HH:mm` ya da **null**: doğum saati bilinmiyor. Null "12:00 varsayalım"
  /// DEĞİLDİR — sunucu Yükselen/ev üretmez ve okumada bunu beyan eder
  /// (core/birth_record.dart'taki kuralın aynısı).
  final String? birthTime;

  final String birthCity;
  final String? birthNation;

  /// `female` | `male` | `other` | `unspecified` ya da **null**: beyan
  /// edilmemiş. Eski varsayılan `'female'` idi — kullanıcı dokunmadan geçince
  /// üçüncü bir kişi adına "kadın" beyan ediliyordu (ölçülmeyen söylenmez).
  /// Null ile `'unspecified'` SUNUCUYA aynı gider ama ekranda ayrışır:
  /// düzenleme kipinde null hiçbir segmenti seçili göstermez, `unspecified`
  /// kullanıcının kendi "Belirtmedim" seçimidir.
  final String? gender;

  final String? sunSign;
  final String? moonSign;
  final String? ascendant;

  bool get hourKnown => birthTime != null;

  factory Person.fromDoc(String id, Map<String, dynamic> data,
      {String? label}) {
    return Person(
      id: id,
      relation: data['relation'] as String? ?? 'other',
      label: label,
      birthDate: data['birthDate'] as String? ?? '',
      // Alanın YOKLUĞU saatin bilinmediği anlamına gelir; varsayılan konmaz.
      birthTime: data['birthTime'] as String?,
      birthCity: data['birthCity'] as String? ?? '',
      birthNation: data['birthNation'] as String?,
      // Alanın YOKLUĞU beyan edilmemiş demektir; varsayılan konmaz
      // (birthTime ile aynı kural). Eski `?? 'female'` düzenleme formunu
      // "kadın seçili" açıyordu.
      gender: data['gender'] as String?,
      sunSign: data['sunSign'] as String?,
      moonSign: data['moonSign'] as String?,
      ascendant: data['ascendant'] as String?,
    );
  }

  /// Rapor uçlarının beklediği gövde. `birthPayload` ile aynı sözleşme
  /// (core/api.dart) — kişinin ADI gönderilmez, çünkü sunucu prompt'ta
  /// ilişki etiketini kullanıyor.
  Map<String, dynamic> toBirthPayload() {
    final tarih = birthDate.split('-').map(int.parse).toList();
    final saat = (birthTime ?? '12:00').split(':').map(int.parse).toList();
    return {
      'year': tarih[0],
      'month': tarih[1],
      'day': tarih[2],
      'hour': saat[0],
      'minute': saat[1],
      'hour_known': birthTime != null,
      'city': birthCity,
      'nation': birthNation,
      // Beyan yoksa sunucuya `unspecified`: backend bu dalı D0'dan beri
      // tanıyor ve cinsiyete bağlı hesabı yapmayıp beyan ediyor.
      'gender': gender ?? kCinsiyetBelirtilmedi,
    };
  }
}

/// Sunucunun "belirtilmedi" değeri — `CinsiyetSecici.degerler` ile aynı.
const String kCinsiyetBelirtilmedi = 'unspecified';

FirebaseFirestore get _db => FirebaseFirestore.instance;

CollectionReference<Map<String, dynamic>> _peopleOf(String uid) =>
    _db.collection('users').doc(uid).collection('people');

// ---------------------------------------------------------------------------
// Etiketler — CİHAZDA
// ---------------------------------------------------------------------------

String _labelKey(String personId) => 'person-label-$personId';

Future<String?> personLabel(String personId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_labelKey(personId));
}

Future<void> setPersonLabel(String personId, String label) async {
  final prefs = await SharedPreferences.getInstance();
  final temiz = label.trim();
  if (temiz.isEmpty) {
    await prefs.remove(_labelKey(personId));
  } else {
    await prefs.setString(_labelKey(personId), temiz);
  }
}

Future<void> _forgetLabel(String personId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_labelKey(personId));
}

/// Türkçe-güvenli küçük harf: `toLowerCase` "İ"yi `i + birleşik nokta`
/// yapar ve `contains` sessizce kaçırır (bkz. backend
/// `prompt_composer.normalize` — aynı tuzağın istemci tarafı).
/// GT-turu'nda dışa açıldı: @-bahsetme süzgeci de aynı kuralı kullanır.
String normalizeTr(String s) => s.toLowerCase().replaceAll('̇', '');

String _normalize(String s) => normalizeTr(s);

/// KA6: mesaj cihazdaki kişi etiketlerinden birini (adını) anıyorsa o
/// kişinin kimliği; yoksa null.
///
/// Ad SUNUCUYA GİTMEZ — eşleşme cihazda yapılır, yalnız `person_id`
/// gönderilir; sunucu kimliği ilişki türü fısıltısına çevirir. Böylece
/// kullanıcı ana sekmeden "Ayşe'yle aram nasıl?" diye sorduğunda da doğru
/// kişinin ölçümü sohbete girer. Kısa etiketler (<3 harf) yanlış pozitif
/// riskine karşı eşleşmeye girmez.
String? matchPersonIdByLabel(String message, List<Person> people) {
  final metin = _normalize(message);
  for (final kisi in people) {
    final etiket = kisi.label?.trim();
    if (etiket == null || etiket.length < 3) continue;
    if (metin.contains(_normalize(etiket))) return kisi.id;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Yazma — SUNUCUDAN (kontenjan istemcide zorlanamaz)
// ---------------------------------------------------------------------------

Map<String, dynamic> _body(Person kisi) => {
      'relation': kisi.relation,
      'birth_date': kisi.birthDate,
      'birth_time': kisi.birthTime,
      'birth_city': kisi.birthCity,
      'birth_nation': kisi.birthNation,
      'gender': kisi.gender ?? kCinsiyetBelirtilmedi,
    };

/// Kişi ekler ve etiketi CİHAZA yazar. Kontenjan doluysa sunucu 402
/// (`X-Paywall-Reason: people`) döner ve istisna çağırana çıkar.
///
/// Sıra önemli: kimlik sunucudan gelir, etiket ancak ondan sonra
/// yazılabilir. Etiket yazımı düşerse kayıt yine de vardır — arayüz
/// ilişki türünün adını gösterir, veri kaybı olmaz.
Future<String> createPerson(Dio dio, Person kisi, {String? label}) async {
  final response = await dio.post('/api/v1/people', data: _body(kisi));
  final data = Map<String, dynamic>.from(response.data['data'] as Map);
  final id = (data['person'] as Map)['id'] as String;
  if (label != null && label.trim().isNotEmpty) {
    await setPersonLabel(id, label);
  }
  return id;
}

Future<void> updatePerson(Dio dio, Person kisi, {String? label}) async {
  await dio.patch('/api/v1/people/${kisi.id}', data: _body(kisi));
  if (label != null) await setPersonLabel(kisi.id, label);
}

Future<void> deletePerson(Dio dio, String personId) async {
  await dio.delete('/api/v1/people/$personId');
  // Etiket sunucu silmeyi onayladıktan SONRA silinir: uç düşerse kayıt
  // duruyor demektir ve etiketi önden silmek kişiyi adsız bırakırdı.
  await _forgetLabel(personId);
}

// ---------------------------------------------------------------------------
// Sağlayıcılar
// ---------------------------------------------------------------------------

/// Eklenen kişiler — Firestore akışı + cihazdaki etiketler.
final peopleProvider = StreamProvider<List<Person>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const <Person>[]);

  return _peopleOf(user.uid)
      .snapshots()
      .asyncMap((snapshot) async {
    final kisiler = <Person>[];
    for (final doc in snapshot.docs) {
      kisiler.add(Person.fromDoc(doc.id, doc.data(),
          label: await personLabel(doc.id)));
    }
    // Tür sırası: eş, çocuk, ebeveyn... (kRelations sırası) — kullanıcının
    // hayatındaki yakınlık sırasına en yakın düzen.
    kisiler.sort((a, b) {
      final byRelation = kRelations.indexOf(a.relation)
          .compareTo(kRelations.indexOf(b.relation));
      if (byRelation != 0) return byRelation;
      return (a.label ?? '').compareTo(b.label ?? '');
    });
    return kisiler;
  });
});

/// Kullanıcı ↔ Çevrem kişisi sinastrisi (HI-turu HA9) — sinastri
/// ÇARKININ veri kaynağı.
///
/// İki taraf da KULLANICININ KENDİ girdiği veridir (profil + kişi
/// kaydı); gizlilik sözleşmesi değişmez. Arkadaş sinastri çarkı BİLEREK
/// yok: arkadaşın konumları istemciye inmez (karşılıklı onay
/// mekanizmasıyla ileri tur). Yanıt points1/points2/houses1/houses2 +
/// sıralı ilk 60 çapraz açı taşır (rev 00076).
final synastryChartProvider = FutureProvider.family<Map<String, dynamic>?,
    Person>((ref, kisi) async {
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) return null;
  final dio = ref.watch(apiProvider);
  final response = await dio.post('/api/v1/astrology/synastry', data: {
    'person1': birthPayload(profile),
    'person2': kisi.toBirthPayload(),
  });
  return Map<String, dynamic>.from(response.data['data']);
});

/// Kontenjan durumu: kaç kişi eklenmiş, kaç kişiye izin var.
///
/// Sunucudan gelir çünkü sınır abonelik durumuna bağlı ve "kaç kişi
/// ekleyebilirim" sorusunun cevabı sunucunundur.
final personSlotsProvider =
    FutureProvider<({int used, int limit})>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return (used: 0, limit: 0);
  // Kişi eklenince/silinince tazelensin.
  ref.watch(peopleProvider);
  final dio = ref.watch(apiProvider);
  final response = await dio.get('/api/v1/people');
  final data = Map<String, dynamic>.from(response.data['data'] as Map);
  return (
    used: (data['used'] as num?)?.toInt() ?? 0,
    limit: (data['limit'] as num?)?.toInt() ?? 0,
  );
});

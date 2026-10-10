/// Doğum kaydının tek yazma yolu.
///
/// ## Neden ayrı bir dosya
///
/// Doğum verisi uygulamadaki **her** astroloji çıktısını besliyor: günlük
/// okuma, natal rapor, BaZi, sohbetin gördüğü harita. Bu yüzden nasıl
/// yazıldığı tek yerde durmalı — ilk kurulumda (onboarding) ve sonradan
/// düzeltmede (profil) aynı kod çalışır, yoksa iki yol zamanla ayrışır.
///
/// ## Buradaki asıl mesele: bayat Büyük Üçlü
///
/// Profilde `sunSign` / `moonSign` / `ascendant` **önbelleklenmiş** değerler.
/// Kullanıcı doğum tarihini düzeltir de harita çağrısı başarısız olursa,
/// dokümanda *yeni tarih* ile *eski burçlar* yan yana kalır. Kimse hata
/// görmez; profil çalışmaya devam eder, sadece yalan söyler.
///
/// Bu yüzden kural: **burçlar ya doğum verisiyle birlikte tazelenir ya da
/// silinir.** Rozet göstermemek, yanlış rozet göstermekten iyidir. Silmek
/// güvenli çünkü okumalar bu alanlardan değil, ham doğum verisinden
/// hesaplanıyor (`birthPayload`); ilk başarılı çağrıda kendiliğinden geri
/// gelirler.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import 'api.dart';
import 'friends.dart';

/// Saat girişi tutarlı mı: "biliyorum" dendiyse bir saat SEÇİLMİŞ olmalı.
///
/// NEDEN (ölçüldü): profil düzeltme ekranı saati bilinmeyen kaydı açarken
/// `12:00` uyduruyor, kullanıcı "biliyorum" deyip saat seçmeden kaydedince
/// o uydurma saat gerçek gibi yazılıyordu. Sihirbazdaki `_saatSecildi`
/// korumasının karşılığı orada yoktu. İki ekran da kaydet düğmesini bu
/// kapıdan geçirir; saf olduğu için test edilebilir.
bool dogumSaatiGecerli({required bool biliniyor, required TimeOfDay? saat}) =>
    !biliniyor || saat != null;

/// `TimeOfDay` → `HH:mm`; null → null (saat bilinmiyor, `BirthRecord.time`
/// ile aynı anlam). "Bilinmiyor"u `12:00`a çeviren tek satır bu depoda bir
/// kez yazıldı ve zarar verdi; dönüşüm burada, uydurma değeri olmadan.
String? saatMetni(TimeOfDay? saat) => saat == null
    ? null
    : '${saat.hour.toString().padLeft(2, '0')}:'
        '${saat.minute.toString().padLeft(2, '0')}';

/// Kullanıcının girdiği doğum anı.
class BirthRecord {
  const BirthRecord({
    required this.date,
    required this.time,
    required this.city,
    required this.gender,
    this.nation,
  });

  /// Yalnızca gün/ay/yıl anlamlı.
  final DateTime date;

  /// `HH:mm` — ya da **null**: doğum saati bilinmiyor (Revize B1).
  ///
  /// Null, "12:00 varsayalım" değildir: sunucu BaZi'de saat sütununu hiç
  /// kurmaz ve okumada bunu beyan eder. Bilinmeyeni bilinen gibi yazmak
  /// öğle doğumu uydurmaktı.
  final String? time;

  final String city;

  /// `female` | `male` | `other`.
  final String gender;

  /// ISO-2 ülke kodu (`TR`, `DE`...) — şehir seçiciden gelir (O2).
  ///
  /// null = bilinmiyor (eski kayıt ya da serbest metin girişi). Sunucu
  /// aynı adlı şehirleri (Tripoli LB/LY) bu kodla ayırt eder; yokluğunda
  /// nüfusça en büyük aday seçilir — davranış eskisiyle aynı.
  final String? nation;

  String get dateText => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Var olan profil dokümanından oku. Eksik alanlar için makul varsayılan.
  factory BirthRecord.fromProfile(Map<String, dynamic>? profile) {
    final ham = (profile?['birthDate'] as String?) ?? '';
    final parcalar = ham.split('-');
    var tarih = DateTime(2000, 1, 1);
    if (parcalar.length == 3) {
      final y = int.tryParse(parcalar[0]);
      final a = int.tryParse(parcalar[1]);
      final g = int.tryParse(parcalar[2]);
      if (y != null && a != null && g != null) tarih = DateTime(y, a, g);
    }
    return BirthRecord(
      date: tarih,
      // Varsayılan YOK: alan hiç yazılmamışsa saat bilinmiyor demektir.
      time: profile?['birthTime'] as String?,
      city: (profile?['birthCity'] as String?) ?? 'Istanbul',
      gender: (profile?['gender'] as String?) ?? 'female',
      nation: profile?['birthNation'] as String?,
    );
  }

  bool sameAs(BirthRecord other) =>
      dateText == other.dateText &&
      time == other.time &&
      city.trim() == other.city.trim() &&
      gender == other.gender &&
      nation == other.nation;
}

/// [saveBirthRecord] sonucu.
enum BirthSaveResult {
  /// Doğum verisi yazıldı, Büyük Üçlü de tazelendi.
  ok,

  /// Doğum verisi yazıldı ama harita hesaplanamadı; burç rozetleri silindi.
  /// Kullanıcıya söylenmeli — sessizce geçilirse rozetlerin kaybolması
  /// açıklanamayan bir davranış olur.
  savedWithoutChart,
}

/// Firestore'a gidecek alanları üretir. **Saf** — bu yüzden test edilebilir.
///
/// [chart] `null` ise harita hesaplanamamıştır ve Büyük Üçlü alanları
/// `FieldValue.delete()` ile işaretlenir. Dosya başındaki açıklamaya bakın:
/// bayat burç bırakmak, burcu hiç göstermemekten kötüdür.
Map<String, dynamic> birthWriteData(
  BirthRecord record, {
  required String uid,
  required Map<String, dynamic>? chart,
}) {
  return <String, dynamic>{
    'uid': uid,
    'birthDate': record.dateText,
    // Saat bilinmiyorsa alan SİLİNİR — "yok" ile "12:00" ayrımı Firestore'da
    // da korunur; birthPayload hour_known bayrağını buradan türetiyor.
    'birthTime': record.time ?? FieldValue.delete(),
    'birthCity': record.city.trim(),
    // Şehir seçiciden gelen ülke kodu; serbest metin girişinde silinir —
    // bayat ülke, bayat burç kadar yanıltıcıdır (aynı adlı şehirler).
    'birthNation': record.nation ?? FieldValue.delete(),
    'gender': record.gender,
    'onboardingCompleted': true,
    'sunSign': chart?['sun_sign'] ?? FieldValue.delete(),
    'moonSign': chart?['moon_sign'] ?? FieldValue.delete(),
    'ascendant': chart?['ascendant'] ?? FieldValue.delete(),
  };
}

/// Doğum kaydını yazar ve Büyük Üçlü'yü onunla birlikte tazeler.
///
/// Sıra önemli: harita **önce** hesaplanır, sonra tek yazımda her şey birlikte
/// gider. Böylece dokümanda hiçbir an "yeni tarih + eski burç" hâli oluşmaz.
///
/// Yazma başarısız olursa istisna fırlatır; çağıran kullanıcıya söylemeli.
Future<BirthSaveResult> saveBirthRecord(
  BirthRecord record, {
  required Dio dio,
  FirebaseFirestore? db,
  FirebaseAuth? auth,
}) async {
  final store = db ?? FirebaseFirestore.instance;
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  if (user == null) throw StateError('Oturum yok');

  Map<String, dynamic>? harita;
  try {
    final yanit = await dio.post('/api/v1/astrology/natal-chart',
        data: birthPayload({
          'birthDate': record.dateText,
          'birthTime': record.time,
          'birthCity': record.city.trim(),
          'birthNation': record.nation,
          'gender': record.gender,
          'displayName': user.displayName,
        }));
    harita = Map<String, dynamic>.from(yanit.data['data'] as Map);
  } catch (_) {
    harita = null;
  }

  await store.collection('users').doc(user.uid).set(
        birthWriteData(record, uid: user.uid, chart: harita),
        SetOptions(merge: true),
      );
  // Arkadaş listesindeki kart `sunSign` gösteriyor; o da tazelenmeli.
  await syncPublicProfile();
  return harita == null
      ? BirthSaveResult.savedWithoutChart
      : BirthSaveResult.ok;
}

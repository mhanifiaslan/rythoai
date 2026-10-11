/// Firaset okuması için sunucu çağrısı.
///
/// Gönderilen tek şey **oranlardır**. Bu dosyada `File`, `bytes`, `image`
/// ya da `MultipartFile` geçmemesi kasıtlı: yüz görüntüsünün ağa çıkmadığını
/// koda bakarak doğrulayabilmek gerekiyor.
library;

import 'package:dio/dio.dart';

import 'face_capture_screen.dart';

/// Ölçümleri uca gönderir ve yanıt gövdesini OLDUĞU GİBİ döndürür.
///
/// Hata yönetimi çağırana bırakılıyor: uygulamanın ortak `describeApiError`
/// katmanı 402'yi paywall'a çeviriyor ve firasetin de o yoldan geçmesi
/// gerekiyor (özellik Rytho+ kapsamında).
///
/// `fallback`/`refunded` bayrakları BURADA OKUNMAZ. Bir dönem okunuyor ve
/// `RaporUretilemedi` fırlatılıyordu — dokuz okuma yüzeyinden yalnız bu
/// ikisi bayrağı kendi mekanizmasıyla okuyordu ve birinin eksik kalması
/// ölçülmüş bir kusur. Tek okuyucu `okumaDurumuFromYanit(veri, alan:
/// 'reading')` (core/okuma_durumu.dart); ekran onu çağırır.
Future<Map<String, dynamic>> fetchFirasaReading(
    Dio dio, FaceCaptureResult sonuc) async {
  final yanit = await dio.post<Map<String, dynamic>>(
    '/api/v1/face/reading',
    data: sonuc.toJson(),
  );
  return Map<String, dynamic>.from(yanit.data ?? const {});
}

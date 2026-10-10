/// Türkçe büyük/küçük harf — `toUpperCase()`/`toLowerCase()`'in TEK varisi.
///
/// ## Neden var
/// Dart'ın `String.toUpperCase()` Türkçe bilmez: `"ilişki".toUpperCase()`
/// → `"ILIŞKI"` (noktasız I), `"İletişim".toLowerCase()` ise `"i̇letişim"`
/// (i + birleşik nokta U+0307). İkisi de ekrana çıkıyordu (ölçüldü):
/// paylaşım kartında "İKIZLER" ve "YIL HARITASI", yıl rozetinde
/// "GÜNEŞ'IN YIL EVI", ilişki ekseninde "i̇letişim", hesap silme onayında
/// "sil" → "SIL" ≠ "SİL" olduğu için düğme açıklamasız kapalı kalıyordu.
/// CLAUDE.md §5 Türkçe metin tuzağı bunu Python tarafı için kaydetmişti;
/// Dart tarafı aynı tuzağa dört yerde düşmüştü.
///
/// Kural: `lib/` altında çıplak `toUpperCase()`/`toLowerCase()` yalnız
/// ASCII olduğu KANITLI girdide (ürün kimliği, ISO kodu, HTTP metodu)
/// kullanılır; kullanıcı metni buradan geçer. Bekçi: `turkce_harf_test.dart`.
library;

/// Türkçe büyük harf: `i → İ`, `ı → I`, gerisi Unicode büyük harf.
String trBuyuk(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Türkçe küçük harf: `İ → i`, `I → ı`, gerisi Unicode küçük harf.
///
/// `İ`'yi ÖNCE değiştirmek şart: `toLowerCase()` onu `i + U+0307`'ye
/// açar ve o birleşik nokta sonradan temizlenemez (iching_tab bir dönem
/// tam bunu elle ayıklıyordu).
String trKucuk(String s) =>
    s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// Onay sözcüğü eşleşmesi (hesap silme "SİL" gibi): klavye düzeninden
/// bağımsız.
///
/// NEDEN noktalı/noktasız I eşitleniyor: İngilizce klavyeyle "SIL" yazan
/// kullanıcı da onaylıyor sayılır; onun niyeti "sil"dir, Türkçe düzeni
/// değil. Bu yüzden karşılaştırma `trBuyuk`tan sonra İ'yi de I'ya
/// katlıyor — yalnız BU kullanım için, genel bir küçültme değil.
bool onayKelimesiEslesiyor(String girdi, String beklenen) {
  String kanonik(String s) => trBuyuk(s.trim()).replaceAll('İ', 'I');
  return kanonik(girdi) == kanonik(beklenen);
}

/// Bir LLM okumasının ekrandaki hâli — ve `fallback` bayrağını okuyan TEK yer.
///
/// ## Neden var
/// Sunucu, üretim düşünce hazır bir şablon paragrafı `fallback: true` ve
/// (jetonlu uçta) `refunded` ile döndürüyor. Ölçüldü: dokuz okuma
/// yüzeyinin dördü bayrağı okuyordu, beşi okumuyordu — kullanıcı şablonu
/// RAPOR sanıyor, iadeyi hiç öğrenmiyor, Yıl Haritası şablonu paylaşım
/// kartına bile basıyordu. Bayrağı dokuz ekran ayrı ayrı okuduğunda
/// biri her zaman eksik kalıyor; o yüzden tek fonksiyon.
///
/// `OkumaKabi` bu durumu çizer: `Hazir` → metin + paylaş + Rytho'ya sor;
/// `Uretilemedi` → dürüst cümle (+ iade bilgisi) + tekrar dene, paylaşım
/// YAPISAL olarak yok (şablon kart olamaz).
library;

sealed class OkumaDurumu {
  const OkumaDurumu();
}

/// Cevap henüz yok.
final class OkumaYukleniyor extends OkumaDurumu {
  const OkumaYukleniyor();
}

/// Gerçek okuma.
final class OkumaHazir extends OkumaDurumu {
  const OkumaHazir(this.metin);
  final String metin;
}

/// Sunucu üretemedi (şablon döndü ya da metin boş geldi).
///
/// [iadeli]: harcanan kredi geri yazıldı mı — YALNIZ sunucunun `refunded`
/// alanından. İstemcide varsayım yok: jetonsuz uçta (ilişki ekseni) iade
/// cümlesi yalan olurdu; bazi'nin `RaporUretilemedi(jetonIadeEdildi:)`
/// doktrini aynen.
final class OkumaUretilemedi extends OkumaDurumu {
  const OkumaUretilemedi({required this.iadeli});
  final bool iadeli;
}

/// İstek düştü (ağ, 5xx, zaman aşımı).
final class OkumaHata extends OkumaDurumu {
  const OkumaHata(this.hata);
  final Object hata;
}

/// Plus gerektiriyor ya da yük yok.
final class OkumaKilitli extends OkumaDurumu {
  const OkumaKilitli();
}

/// Sunucu yanıtından durum. [alan]: okumanın anahtarı (`report` ya da
/// `reading`).
///
/// Kurallar — ölçülen sırayla:
/// 1. `veri == null` → kilitli (sağlayıcılar abone olmayana null döner).
/// 2. `fallback == true` → üretilemedi; `refunded == true` ise iadeli.
/// 3. Metin boş/null → üretilemedi, iadesiz. (Yüz okuma boş metinde boş
///    panel çiziyordu — boş metin bir okuma değildir.)
/// 4. Aksi hâlde hazır.
OkumaDurumu okumaDurumuFromYanit(Map<String, dynamic>? veri,
    {String alan = 'report'}) {
  if (veri == null) return const OkumaKilitli();
  if (veri['fallback'] == true) {
    return OkumaUretilemedi(iadeli: veri['refunded'] == true);
  }
  final metin = veri[alan];
  if (metin is! String || metin.trim().isEmpty) {
    return const OkumaUretilemedi(iadeli: false);
  }
  return OkumaHazir(metin);
}

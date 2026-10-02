# Rytho Gizlilik Politikası — KANONİK KOPYA BURADA DEĞİL

Bu dosya artık politika METNİNİ tutmuyor. Yalnızca nerede tuttuğunu söylüyor.

## Kanonik kopyalar

| Yüzey | Yol |
|---|---|
| Web (TR) | `web/legal/gizlilik.html` |
| Web (EN) | `web/en/legal/privacy.html` |
| Uygulama içi (TR + EN gövdeleri) | `apps/mobile/lib/features/profile/legal_texts.dart` |

Üçü de `backend/tests/test_gizlilik_kopyalari.py` ile çivili: aynı tarihi
taşımak ve aynı bölümleri içermek zorundalar.

## Metin niçin buradan kaldırıldı

Bu dosya politikanın **beşinci** kopyasıydı ve ölçüldüğünde (2026-10-02) en
bayatıydı: tarihi hâlâ *5 Ağustos 2026*, ve dört bölüm hiç yoktu — eklenen
kişilerin doğum verisi ("Çevrem"), abonelik ve tek cihaz, bildirimler, ortak
bağlantısı tıklamaları. Canlı kopyalar o gün *2 Ekim 2026* diyordu.

Dahası: hiçbir kod, HTML, betik ya da belge bu dosyaya **referans
vermiyordu** (ölçüldü). Yani kimseye gösterilmeyen ama `docs/legal/` altında
durduğu için okuyanı "politika bu" diye yanıltan bir metindi.

Kök neden bir yazım hatası değil **kopya sayısı**: bir hukuk metninin beş
kopyası varsa dördü bir gün ayrışır. Aynı sınıf iki ay boyunca sessizce
yaşadı (uygulama 2 Ağustos, web 5 Ağustos; webde iki bölüm hiç yoktu). Üç
kopya bir bekçiyle zorunlu — mobil, web TR, web EN farklı teknolojiler ve
birleştirilemiyor. Dördüncüsü için gerekçe yoktu.

⚠️ Buraya politika metni **geri yazılmamalı**. Metin değişikliği üç kanonik
kopyada birlikte yapılır; bekçi üçünü de aynı tarihte ve aynı bölümlerle
görmek ister.

## Kullanım şartları

`docs/legal/kullanim-sartlari.md` **kalıyor** ve bayat değil (2026-09-27).
Sebep: o metin `backend/tests/test_honesty.py` içindeki `_KOPYALAR` ile
çivili — dört dosya, beş gövde (Dart dosyası TR ve EN gövdelerini birlikte
taşıyor) — ve bu belge o dörtten biri. Yani referanssız bir kopya değil,
bekçiyle bağlı bir kopya. Aradaki tek fark bu.

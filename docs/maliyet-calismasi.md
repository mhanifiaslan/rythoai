# RythoAI Maliyet ve Fiyatlama Çalışması (K-turu, 2026-08-13)

> Tüm sayılar KODDAN ölçülmüş girdilerle (prompt boyutları, önbellek
> tasarımı, jeton tablosu) ve Gemini'nin güncel liste fiyatlarıyla
> hesaplandı. Kur varsayımı **1 USD ≈ 42 ₺** (duyarlılık: 40-45 aralığı
> sonuçları ±%7 oynatır). KDV %20, Google Play komisyonu %15
> (küçük geliştirici katmanı).

## 1. Birim maliyetler (LLM: gemini-flash-latest ≈ 2.5 Flash)

Fiyat: ~$0,30 / 1M girdi token'ı · ~$2,50 / 1M çıktı token'ı (düşünme
kapalı — gemini_service thinking_budget=0). Embedding sorgusu ihmal
edilebilir (~$0,000008/çağrı; önbellek isabetinde hiç yok).

| İş | Girdi (token) | Çıktı (token) | Maliyet/çağrı | Jeton bedeli | Jeton başına gelir* | Marj |
|---|---|---|---|---|---|---|
| Sohbet turu | ~4.000 (tavanlı en kötü ~9.000†) | ≤300 | **~$0,0020** (kötü $0,0034) | 1 | ~$0,010 | %80+ |
| Natal / BaZi / SR / Progresyon / Firasa | ~3.500 | 700-900 | **~$0,0033** | 5 | ~$0,050 | %93 |
| İching (+soru hükmü çağrısı) | ~3.500+800 | ~500 | **~$0,0030** | 2 | ~$0,020 | %85 |
| Dyad (çift başına günlük) | ~2.700 | ~200 | **~$0,0018** | 3 | ~$0,030 | %94 |
| Kişisel günlük (abone, jetonsuz) | ~3.000 | ~250 | ~$0,0015 × 30/ay = **~$0,045/ay** | — | abonelik içinde | — |
| Genel burç yorumu (paylaşımlı) | ~2.800 | ~250 | 72 üretim/gün → **~$4,5/AY TOPLAM** (kullanıcı sayısından bağımsız) | — | — | — |
| Hafıza çıkarımı (günde ≤1) | ~2.000 | ~100 | ~$0,0009 → ≤$0,03/ay/kullanıcı | — | — | — |
| Günlük push metni (paylaşımlı, burç başına) | ~1.100 | ~30 | ihmal | — | — | — |

\* Jeton başına gelir: 100'lük paketin KDV+komisyon sonrası neti
(~$1,0) / 100. †K4 tavanı sonrası (son 12 mesaj × 1.200 kr).

Önbellek çarpanı: raporlar kişi başına 24s-90g önbellekli; harcama ve
LLM çağrısı YALNIZ önbellek kaçırıldığında. İkinci okuma hem ücretsiz
hem maliyetsiz — yani yukarıdaki maliyetler kullanım başına ÜST sınır.

## 2. Gelir ve marj — abonelik

| Kalem | Değer |
|---|---|
| Tüketici fiyatı (KDV dahil, alıcının gördüğü) | **₺179,99/ay** |
| KDV −%20 | ₺149,99 |
| Google Play −%15 | **net ≈ ₺127,5 ≈ $3,0/ay** |

Abonenin aylık LLM maliyeti (senaryolar, jeton zorlaması AÇIK):

| Senaryo | Kullanım | LLM maliyeti | Brüt marj |
|---|---|---|---|
| Hafif | 50 jeton (karışık) + günlük | ~$0,15 | **~%95** |
| Orta | 150 jeton + günlük | ~$0,35 | **~%88** |
| Yoğun (tavan) | 300 jetonun TAMAMI sohbete + günlük + hafıza | **~$0,70** | **~%77** |
| Yoğun + 100'lük ek paket | +$1,0 gelir, +$0,20 maliyet | — | ek paket marjı %80 |

**Sonuç: en kötü durumda bile %77, tipikte %88-95 brüt marj.** Jeton
zorlaması (K5) bu tavanın MATEMATİKSEL garantisidir — kapalıyken tavan
yoktur ve "yoğun kullanıcı" maliyeti sınırsız büyüyebilirdi.

## 3. Jeton paketleri

| Paket | Tüketici (KDV dahil) | Net gelir | Gerçek maliyet aralığı | Marj |
|---|---|---|---|---|
| 100 jeton | ~₺59,99 | ~$1,0 | $0,07 (rapor ağırlıklı) – $0,20 (sohbet) | **%80-93** |
| 300 jeton | ~₺155,99 | ~$2,6 | $0,20-0,60 | **%77-92** |
| 1000 jeton | ~₺419,99 | ~$7,0 | $0,66-2,00 | **%71-91** |

Jeton bedelleri (1/2/3/5) maliyet oranına değil ALGILANAN değere göre
bilinçli: derin rapor sohbet turundan yalnızca %65 pahalı ama 5 kat
jeton — kullanıcı gözünde rapor "büyük iş"tir ve bu doğru fiyatlanmış
hissettirir. Değiştirmeye gerek yok.

## 4. Sabit giderler ve başabaş

| Kalem | Aylık |
|---|---|
| Cloud Run (min-instance 1, 2 vCPU/2Gi — soğuk başlatmayı öldüren bilinçli karar) | ~$25 |
| Genel burç üretimi (paylaşımlı LLM) | ~$4,5 |
| Firestore (küçük ölçek; aiCache+kullanıcı verisi) | ~$1-5 |
| SMS (Türkiye ~$0,01-0,05/adet; kayıt başına 1) | kullanıcıyla ölçeklenir, ~$0,03/yeni kullanıcı |
| NASA/GeoNames/RevenueCat (ücretsiz katman) | $0 |
| **Toplam sabit** | **~$32-35 ≈ ₺1.400** |

**Başabaş: ~11 abone.** Sonrası: her abone net ~$2,3-2,9 katkı
(senaryoya göre). 100 abonede kaba tablo: gelir ~$300, LLM ~$15-70,
sabit ~$35 → **aylık net ~$200-250 ≈ ₺8-10 bin**.

Ücretsiz kullanıcı maliyeti: günde ≤5 sohbet + 1 İching → tavan
~$0,013/gün, tipik ~$0,10-0,15/AY/aktif ücretsiz kullanıcı. 1.000
aktif ücretsiz kullanıcı ≈ $100-150/ay — dönüşüm %3+ olduğu sürece
kendini fazlasıyla öder; değilse FREE_CHAT_PER_DAY tek ayar noktasıdır.

## 5. Fiyat konumlandırması (TR pazarı)

Pazar: AI destekli benzer uygulamalar ~₺600/ay'dan satılıyor. Rytho
₺179,99'da **bilinçli penetrasyon** konumunda — pazar liderinin ~%30'u.
KARAR (kullanıcı, 2026-08-12): fiyatlar ŞİMDİLİK korunur.

Fiyat merdiveni (ileri adımlar, şimdi uygulanmaz):
1. **0-1.000 abone**: ₺179,99 koru — büyüme ve yorum/puan birikimi.
2. **1.000+ abone**: yeni abonelere ₺229-249 (Play'de mevcut abonelerin
   fiyatı korunabilir); marj zaten yüksek, artış aciliyet değil güç işi.
3. **Yıllık plan**: ₺1.499-1.699 (aylığın ~8 katı) — nakit akışı +
   kayıp (churn) azaltma. RevenueCat offering'e paket eklemek yeterli.
4. Jeton fiyatları enflasyonla birlikte yılda bir gözden geçirilir.

## 6. "Sürpriz yok" garantileri (bu turda kapatılanlar)

| Risk | Durum |
|---|---|
| "Sınırsız sohbet" vaadi vs jetonlu sohbet | ✅ K3: paywall metni "Ayda 300 jeton" oldu — vaat edilen = verilen |
| İlk alımda bakiye 0 görünmesi | ✅ K2: mobil cüzdan tazeleme + sunucu 35 günlük hak yedeği |
| Jeton düşmeden hizmet (gelir kaçağı) / tavansız maliyet | ✅ K5: RYTHO_TOKENS_ENFORCE=1 kalıcı |
| Sohbet girdisinin sınırsız büyümesi | ✅ K4: prompt geçmişi 12 mesaj × 1.200 kr tavanı |
| Önbellek kaçağı çifte harcama | ✅ (mevcut) harcama yalnız cache-miss'te; üretim hatasında iade |
| Fiyat KDV sürprizi | ✅ (B3) alıcı KDV dahil fiyatı görür; tablolar buna göre |

## 6b. R2 programının maliyet etkisi (2026-08-16)

| Yenilik | LLM maliyeti | Not |
|---|---|---|
| Sinyaller — şablon başlık (her katman) | **$0** | tema × ton tablosu, LLM yok |
| Sinyaller — abone yorumu | ~$0,0009/gün/abone | 3 sinyal TEK çağrı, 24s önbellek → ~$0,027/ay |
| Sabah bildirimi (sinyalden) | **$0** | şablon; eski paylaşımlı LLM satırı yalnız yedek |
| İlişki eksenleri (sinastri) | **$0** | efemeris hesabı, 30 gün önbellek |
| Ücretsiz temel harita (R2-F1) | **$0** | çark/yerleşim/açı hesabı zaten LLM'siz uçta |

**Sonuç: marj matematiği değişmedi.** Abone başına aylık LLM maliyeti en
kötü senaryoda ~$0,70'ten ~$0,73'e çıkıyor (%77 → %76 marj). Ücretsiz
katmana açılan harita, LLM maliyeti olmadığı için ücretsiz kullanıcı
maliyetini artırmaz; karşılığında ilk-değer ve dönüşüm beklentisi yükselir
(analiz: "kullanıcı önce 'bu uygulama bana bir şey söylüyor' demeli").

## 6c. P-turu: eklenen kişiler (Çevrem) — 2026-08-18

Kullanıcı artık eşini, çocuğunu, bir yakınını ekleyip haritalarını ve
aralarındaki bağı takip edebiliyor. Tarifeyi belirleyen tek soru şu oldu:
**hangi yüzeyin tavanı yok?**

### Jetonlu yüzeylerin tavanı ZATEN var

Aylık 300 jeton hakkı (K5 zorlaması açık) matematiksel bir üst sınır.
Kişi sayısı bu tavanı BÜYÜTEMEZ — yalnız jeton hızını artırır, ki bu
gelir lehinedir (paket satışı). Kişinin natal raporu / BaZi / yıl
haritası mevcut **5 jeton**, günlük ikili okuma **3 jeton**, kişi
bağlamlı sohbet **1 jeton** — hiçbir yeni bedel eklenmedi.

### Tavansız olan tek yüzey: ilişki AI okuması

Bu okuma Plus'ta **jetonsuz** üretiliyor (çift başına bir üretim + 30
gün önbellek). Kişi sayısı sınırsız olsaydı bu yüzeyin de tavanı olmazdı.

| Senaryo | Jetonsuz ek LLM yükü | Net gelire oranı |
|---|---|---|
| Ücretsiz kullanıcı, 1 kişi | **$0** (yorum Plus kapısında) | %0 |
| Plus, 10 kişilik kontenjan dolu | 10 × ~$0,0018 = **~$0,018/ay** | **%0,6** |
| Kontenjan OLMASAYDI, 100 kişi | ~$0,18/ay ve **üst sınır yok** | tavansız |

**Kontenjan (ücretsiz 1 / Plus 10) bu yüzeyin matematiksel emniyetidir.**
Sabit `people_service.FREE_PERSON_SLOTS` / `PLUS_PERSON_SLOTS`; aşımda
402 + `X-Paywall-Reason: people`.

### Maliyeti OLMAYAN yüzeyler

| Yüzey | LLM | Not |
|---|---|---|
| Kişinin çarkı + Büyük Üçlü + yerleşimler | **$0** | efemeris hesabı; "hesap bedava, yorum paralı" |
| İlişki ölçümü (4 eksen + dayanak açılar) | **$0** | 30 gün önbellek, doğum özetli anahtar |
| İlişki türüne göre eksen adı | **$0** | sabit tablo (`RELATION_AXIS_NAMES`) |

**Sonuç: en kötü durum marjı %77 → ~%76.** Özellik bir maliyet sorunu
değil; kontenjan durduğu sürece bedavaya yakın. Asıl beklenen etki gelir
tarafında: ücretsiz kullanıcının eklediği TEK kişi (çoğunlukla eşi) dört
ekseni ölçülmüş görüp yorumu kilitli bulur — ürünün üretebileceği en
dürüst paywall, çünkü gösterilen ölçüm gerçektir.

## 6d. Ç-turu: takvim yorumu (calendar_insights) — 2026-08-18

Kök neden: 30 günlük takvim şeridi, her açı-kesinleşmesinin gündelik
cümlesini `SIGNAL_HUMAN_LINES` (4 tema × 3 ton = 12 sabit cümle) tablosundan
seçiyordu — LLM'siz, **$0**, ama ölçülen bedeli farklı astrolojik olayların
birebir aynı cümleye düşmesiydi (bir örnek haritada bir günde üç olay aynı
cümleyi üç kez gösterdi). Onarım `signal_insights`in (§6b'deki "Sinyaller —
abone yorumu" satırı) BİREBİR AYNI desenini takvime taşıyor: `calendar_insights`
tek çağrıda tüm açı-kesinleşmelerini yazdırır — bu, **yeni bir LLM maliyeti**
demek.

| Sınır | Değer | Not |
|---|---|---|
| Tetiklenme sıklığı | **abone başına günde en fazla 1** | takvimin kendi 24s önbelleğiyle aynı ritim; `calendar-insight-{fp}-{lang}` anahtarı ayrı ve dil bazlı |
| Yığın boyutu | **≤20 olay** (`CALENDAR_INSIGHT_MAX_EVENTS`) | ölçüm: gerçek 30-90 günlük takvimlerde 3-17 açı-kesinleşmesi çıktı; 20 rahat bir tavan |
| Ücretsiz kullanıcı | **$0, değişmez** | `calendar_insights` yalnız `is_subscriber` dalında çağrılır — ücretsiz katmanda hiç tetiklenmez (Ç6 bekçisi: çağrı sayacı sıfır) |
| Biçim-dışı üretim | **$0 tekrar** | boş sözlük de önbelleklenir — LLM her istekte yeniden yorulmaz |

Büyüklük mertebesi: sinyal yorumunun (3 öğe, ~$0,0009/gün/abone) 3-17
öğeye büyütülmüş hâli — en kötü durumda (17 olay) günlük maliyet kabaca
3-6 katına çıkar (~$0,003-0,005/gün), aylık **~$0,10-0,15/abone**. Bu,
§6b'deki abone başına aylık LLM tavanını (~$0,73) ölçülebilir ama küçük
bir miktar (~%1-2) artırır; marj matematiğini bozmaz.

## 6e. KA-turu: sinyal yorumu herkese + akşam check-in sorusu — 2026-08-23

Kök neden: kart ve sabah bildirimi metni 12 cümlelik sabit tablodan
(`SIGNAL_HUMAN_LINES`) geliyordu — cihazda iki özdeş kart + herkese her
sabah birebir aynı bildirim olarak ölçüldü. **Kullanıcı kararı: yorum
HERKESE kişi başı AI** ("ücretsiz kullanıcı zaten ~3 gün kullanacak,
maliyeti göze alıyorum"); tablo silindi, son çare dürüst teknik satır.

| Sınır | Değer | Not |
|---|---|---|
| Tetiklenme | **aktif kullanıcı başına günde en fazla 1 çağrı** | uç ve sabah bildirimi AYNI paketi paylaşır (`signals-bundle-{fp}-{lang}`); kim önce çalışırsa üretir |
| Akşam sorusu | **0 ek çağrı** | check-in sorusu sabahki toplu çağrının son satırı; akşam işi yalnız önbellekten okur |
| Uyuyan kullanıcı | **$0** | üretim yalnız (a) bildirime uygun (token+tercih+doğum verisi) kullanıcıda 09:00 yerel, (b) uygulamayı açanda tetiklenir |
| Biçim hatası | kısa TTL (1 saat) | eski `[] 24 saat` zehirlenmesi kapandı; en kötü ihtimalle günde birkaç yeniden deneme |

Birim: ~600 girdi + ~150 çıktı token/çağrı (3 sinyal + soru) ≈
**~$0,0006/gün/aktif kullanıcı → ~$0,018/ay**. Abonede §6b'deki sinyal
yorumu satırının yerine geçer (aynı çağrı, +1 satır — fark ihmal).
Ücretsiz katman İLK KEZ tekrarlanan LLM maliyeti taşıyor: 1.000 günlük
aktif ücretsiz kullanıcıda ~$18/ay — kullanıcı onayıyla kabul edilmiş
dönüşüm yatırımı ("kişisel astrolog" vaadinin ücretsiz vitrini). Takvim
`line`, günlük okuma ve raporların Plus kapıları DEĞİŞMEDİ.

## 6f. RD-turu: 7 kitaplık korpus + metadata'lı getirme — 2026-08-28

7 kamu malı kitap (1.245 chunk × 2 dil; güvenlik süzgeciyle 1.199/dil)
korpusa girdi; getirme kullanıcının haritasıyla kişiselleşti.

| Kalem | Değişim | Not |
|---|---|---|
| Sohbet turu | +~125 girdi token | pasaj bütçesi 2×700→2×1.200 kr + iç kaynak etiketi (kullanıcı onayı) |
| Rapor | +~900 token en kötü | pasaj başına 2.000 kr tavan kondu — tavansız 3× olurdu |
| Gömme | tek seferlik ~2,3M token | ~$0,3; artımlı — sonraki eklemeler yalnız yeni parçalar |
| İmaj | +~29MB artefakt | bilinçli: vektörler imaja gömülü, çalışma anında sıfır gömme çağrısı |
| Getirme boost'u | **$0** | metadata karşılaştırması CPU; LLM/embedding çağrısı değişmedi |

Marj matematiği değişmedi: sohbet turu ~$0,0020 → ~$0,0021.

## 6g. GT-turu: çift-transit ölçümü + sohbette @-bahsetme — 2026-08-28

Kök neden: ilişki katmanında SIFIR tarih farkındalığı vardı — fısıltı her
gün aynı eksen satırlarını taşıyor, "günlük" ikili okumanın bugün girdisi
bile herkese aynı Ay evresiydi. Onarım LLM'siz: her çift için "bugün
aranıza dokunan gökyüzü" ölçümü (`pair_transits`).

| Kalem | Değişim | Not |
|---|---|---|
| Çift-transit ölçümü | **$0** | LLM'siz efemeris (emsal: §1 ilişki eksenleri); `pair-transits-{v}-{çift}-{gün}` 36s önbellek; hacim kişi kontenjanı (1/10) + arkadaş sayısıyla sınırlı CPU |
| Sohbet fısıltısı | +~80 girdi token | yalnız ilişki bağlamı AKTİFKEN (tavan 600→900 kr); taze AI yorumu zaten ödenen sohbet çağrısından gelir |
| Dyad okuması | **değişmedi** (3 jeton) | prompt çifte özgü "bugün" kazandı — aynı çağrı, gerçek günlük içerik |
| İlişki ekranı şeridi | **$0** | ölçüm ücretsiz katmana da görünür ("hesap bedava, yorum paralı") |
| @-bahsetme | **$0** | tamamen istemci; sunucuya yalnız mevcut kimlik alanları gider |

Marj matematiği değişmedi.

## 6h. OB-turu: davet/kabul push'ları + öğle slotu + keşif halkası + emoji — 2026-08-28

Kullanıcı isteği "uygulama bildirimlerle konuşmalı" — ama bu turun TAMAMI
LLM'siz: yeni hiçbir üretim çağrısı yok.

| Kalem | Değişim | Not |
|---|---|---|
| Davet push'u (`/notify/invite`) | **$0 LLM** | şablon metin; istek başına 2-3 Firestore okuması (`incoming` kenarı + iki profil) + 1 FCM; çift-başına-günlük tekrar koruması hacmi sınırlar |
| Kabul push'u (`/invite-accepted`) | **$0 LLM** | aynı desen; `are_friends` çift taraflı doğrulama zaten iki okuma |
| Öğle slotu (yerel 13:00) | **$0 LLM** | (a) sabahki paylaşımlı sinyal önbelleği + paket YALNIZ-OKUNUR (`generate_if_missing=False`); (b) çift ânı YALNIZ önbellekten (`pair_transits_cached` asla hesaplamaz); olaysız günde hiç gitmez — tarama maliyeti saatlik işin marjinal CPU'su |
| Keşif halkası (OB4) | **$0** | tamamen cihaz-yerel SharedPreferences; sıfır sunucu trafiği |
| Emoji geçişi (OB5) | **$0** | şablon başlıklarına sabit emoji; sohbet kuralı mevcut sistem talimatına +~30 token |

Gün içi bildirim bütçesi (kullanıcı kararı): sabah 09 + öğle 13 (yalnız
olay günleri) + akşam 20; davet/kabul olay tetikli ve bütçeye sayılmaz.
Marj matematiği değişmedi.

## 6i. OT-turu: tekrarsız bildirim + tema rotasyonu + 3 günlük deneme — 2026-08-29

Güven-kritik tur: "dünkü bildirimle aynıydı" cihaz bulgusunun beş kök
nedeni kapatıldı; LLM deltası ihmal edilebilir.

| Kalem | Değişim | Not |
|---|---|---|
| Tema rotasyonu + öğle kopya koruması + gün-farkındalıklı yedekler | **$0** | seçim/karşılaştırma mantığı; paket üretimi günde 1 çağrı olarak KALDI |
| SIGNALS_PROMPT v3 ({today} + tekrar yasağı) | ~+40 girdi token/paket | aynı tek günlük çağrının içinde |
| Dünle-aynılık yeniden üretimi | ≤1 ek flash çağrısı/harita/gün, YALNIZ bayt-aynı tekrar gününde | temp 0.9'da nadir; filo genelinde <$0.001/gün tahmini |
| SIGNAL_CALC_VERSION 3→4 | tek seferlik | deploy günü paketler bir kez tazelenir (~$0.0004/aktif harita) |
| SYNASTRY_CALC_VERSION 3→4 (_mix_hits) | tek seferlik | rel-reading çift başına bir kez yeniden üretilir (~$0.0004/çift, jetonsuz Plus yüzeyi) |
| 3 günlük deneme (OT6, kullanıcı kararı: kartsız) | yeni kullanıcı başına TEK SEFER: 30 deneme jetonu (≈$0.06 tavan) + 3 gün jetonsuz Plus yüzeyleri (ilişki yorumu ~$0.002, takvim ~$0.003, sinyal zaten herkese) | en kötü ~**$0.10/yeni kullanıcı**, tek seferlik edinim maliyeti; dönüşüm kaldıracı olarak bilinçli |
| Şifre panosu / izin akışı / telefon adımı / sohbet ikonu | **$0** | istemci + Firebase Auth |

## 6j. HI-turu: Harita İnceleme — ortak profesyonel çark — 2026-08-29

Tur TAMAMEN LLM'siz: çark çizimi istemci CPU'su; `/astrology/transits`
ve `/astrology/synastry` mevcut efemeris uçları (istek başına yerel
hesap, LLM yok). Sinastri yanıtına eklenen points/houses alanları aynı
hesabın zaten ürettiği veridir — ek maliyet sıfır. Canlı onarım (gökyüzü
açı ağı) da maliyetsiz: yalnız yerelleştirme sözleşmesi düzeldi.

## 6k. OP-turu: ortaklık programı — ortak edinme maliyeti — 2026-09-27

Ortak (affiliate) programı, getirdiği kişi ilk kez abone olduğunda ortağa
sabit bir ₺ tutar borçlandırıyor. Bu kalemin bu belgedeki tüm diğer
kalemlerden ayrıldığı yer: gelirden pay ya da altyapı gideri değil,
**kasadan çıkan doğrudan ödeme** — ve ₺ cinsinden. Kullanıcıya
ödül/indirim YOK, o yüzden gelir tarafı değişmiyor; değişen yalnız
maliyet.

| Kalem | Değer | Kaynak |
|---|---|---|
| Ödül (varsayılan, ortak başına ayarlanır) | **₺30** = ~$0,71 | `api/admin.py` `rewardTry` varsayılanı; panelde de 30 |
| Ödül tavanı (yazım hatası kapısı) | ₺500 ≈ $11,9 | `partner_service.MAX_REWARD_TRY` |
| Tetiklenme | abone başına **BİR KEZ** (ilk abonelik) | `partnerQualifications/{uid}` — kimlik uid, ikinci kayıt açılamaz |
| Ödül DOĞURMAYAN alımlar | jeton paketi · yenileme · SANDBOX/test | `REWARD_EVENT_TYPES` + `PRODUCTION` süzgeci |
| Deneme BAŞLATMA da ödül doğurmaz | ayrı kapı | `period_type == TRIAL` — `REWARD_EVENT_TYPES` bunu KAÇIRIR, çünkü denemeli bir `INITIAL_PURCHASE` hem o kümede hem `monetary=True`dır (`api/billing.py::_ortaklik_hakedisi`, 4. koşul) |
| ⚠️ Denemeden DÖNÜŞÜM ödül doğurur | `TRIAL_CONVERTED` de sayılır | yalnız `INITIAL_PURCHASE`a bakan kural onu kaçırırdı |
| Kesinleşme | satın almadan **15 gün** sonra | iade/erken sona erme penceresi; iade gelirse ödül `void` |

### Abone başına etki (bu belgedeki sayılarla)

§2'ye göre abonenin ilk ay neti **₺127,5 ≈ $3,0**, §4'e göre aylık net
katkısı **~$2,3-2,9** (senaryoya göre; LLM maliyeti düşülmüş).

| | Ortaksız | Ortaklı (₺30) |
|---|---|---|
| İlk ay net katkı | ~$2,3-2,9 | **~$1,6-2,2** |
| Sonraki her ay | ~$2,3-2,9 | ~$2,3-2,9 (**değişmez**) |
| Ödülün ilk ay netine oranı | — | ~%24 (₺30 / ₺127,5) |
| Ödülün ilk ay KATKISINA oranı | — | ~%25-31 |

**Ödül TEK SEFERLİK olduğu için marj matematiği bozulmuyor: ilk ay
içinde kendini geri ödüyor.** İkinci aydan itibaren atıflı abonenin
AYLIK katkısı ortaksız aboneyle birebir aynı; kümülatifte ise kalıcı
olarak ₺30 geride kalıyor (bir kez ödendi, geri gelmiyor). Kıyas: §6i'deki 3 günlük
deneme edinim maliyeti ~$0,10/yeni kullanıcı — ortak ödülü onun ~7 katı
ama yalnız **paraya dönmüş** kullanıcıda doğuyor, her kayıtta değil.

Tavandaki (₺500) bir ödül ~4-5 ayın net katkısını yerdi; tavan bir plan
değil yazım hatası kapısıdır (30 yerine 3000 yazılması).

### Kur: tek bir yerde adlandırılmış

Ödül ₺, gelir ve AI maliyeti $ cinsinden ölçülüyor; ikisini çıkarmak için
kur ŞART. **Bu belgenin başındaki 1 USD ≈ 42 ₺ varsayımı artık koddaki
tek kur kaynağıyla aynı**: `admin_service.USD_TRY_DEFAULT`, ortam
değişkeni `RYTHO_USD_TRY` ile ezilir. Belgedeki varsayım değişirse env de
değişir — iki yerde iki farklı kur, iki farklı marj demektir.

⚠️ **Kuru KALICI değiştirmenin tek yolu `infra/deploy-backend.ps1`
düzenlemektir, gcloud değil** (ölçüldü 2026-09-27). Gerekçe: o bayrak
(`--set-env-vars`) mevcut değişkenleri TÜMÜYLE değiştiriyor, yani elle
verilen kur bir sonraki deploy'da SESSİZCE silinir —
`RYTHO_MIN_BUILD` yarasının aynısı (34 sürüm boyunca kapı hiç
kurulmadı). Bayrak artık o satırda **YAZILI** ve varsayılan değeriyle
(`RYTHO_USD_TRY=42`, belgedeki varsayımla aynı sayı) duruyor; bir önceki
turda hiç yoktu. Kur değişecekse **üç yer birlikte** değişir: bu
belgenin başındaki varsayım · `admin_service.USD_TRY_DEFAULT` ·
deploy betiğindeki bayrak.

Son ikisinin birlikte kalması artık **bekçili**
(`test_deploy_bayragi_varsayilan_kurla_ayni_kalir`): bayrak satırdan
düşerse ya da `USD_TRY_DEFAULT`tan farklı bir sayı yazarsa test kırmızı
olur. Bekçi betiği çalıştırmaz, metin olarak okur ve **yorum satırlarını
atar** — bayrağı anlatan yorum aynı dosyada ve içinde `RYTHO_USD_TRY=42`
yazıyor; atılmazsa bayrak komuttan silinse bile bekçi yeşil kalırdı.

Kur **makul bant** kapısından geçiyor (`USD_TRY_MIN`..`USD_TRY_MAX` =
**5-200**). Bant bir tahmin aralığı değil yazım hatası kapısıdır —
`partner_service.MAX_REWARD_TRY` tavanıyla aynı gerekçe. Ölçülen iki
kırılma: `420` (fazladan sıfır) ₺30 ödülü **$0,07**'ye düşürüp programı
bedava gösteriyordu, `4,2` (ondalık ayracı kayması) **$7,14**'e çıkarıp
kârlı programı zararlı gösteriyordu; ikisi de "sayıya çevrilebiliyor ve
pozitif" olduğu için eski kapıdan geçiyordu. Bandın dışı **uyarı logu
ile varsayılana** düşer — belgedeki 40-45 duyarlılık aralığı bandın çok
içinde olduğu için gerçek bir değer kaybı (60, 80, 120) kapıya
takılmaz. Bekçi: `backend/tests/test_admin_kur_bandi.py`.

Kur çözümlenemezse ya da pozitif değilse panel marjı **−1 sentinel**
("—") gösterir; uydurma kurla hesaplanmış bir sayı "marj" adıyla
sunulmaz. "Çevrilemeyen değer" ile "basamağı kaymış değer" ayrı
davranır: birincisi hiçbir okumayla kur değildir ("—"), ikincisinde
operatörün ne demek istediği bellidir ve belgelenmiş varsayım "—"den
iyi bir cevaptır.

### Sayı nereden okunuyor

Kullanıcı 360 **yanıtı** (`admin_service.user_360` → `economics`) ortak
maliyetini marjdan düşer ve **neyi** düştüğünü ayrı alanlarla söyler:
`partnerCostUsd`, `partnerRewardTry`, `partnerStatus`, `usdTryRate`.
Alanlar yanıtta VAR ve panelin okuyucusu da YAZILDI
(`gorunumler/kullanicilar.js` → `marjCumlesi`): formül cümlesi üçüncü
terimi (`− ortak edinme maliyeti`) yazıyor, altındaki satır **neyin**
düşüldüğünü söylüyor (`$X = ₺Y ÷ kur Z · hakediş …`), ve ölçülemeyen üç
hâl (uç göndermiyor / hakediş okunamadı / kur yok) ayrı ayrı anlatılıyor.
Bu bölümün eski hâli "okuyucu henüz yazılmadı" ve "panelde bekleyen bir
yalan var — cümle iki terimli" diyordu; **ikisi de artık doğru değil**,
düzeltildi.

⚠️ Terim cümleden **ancak uç onu göndermiyorsa** çıkar: düşülmemiş bir
maliyeti düşülmüş göstermek de, düşüleni yazmamak da aynı kusurun iki
yönü. Aynı kural gelir görünümünde de uygulanıyor
(`gorunumler/gelir.js`); orada bir hâl fazla, çünkü ortak maliyeti
ölçülemediğinde marj "—" ile silinmiyor, ortak öncesi ölçülü sayı
yıldızla gösteriliyor — o yüzden cümle de o hâlde iki terimli yazılır.

Ekonomi TABLOSUNUN (top-200) marjı da **artık bu kalemi İÇERİYOR** (P4,
2026-09-28). Yol, bu bölümün önceki hâlinin "tek çıkış" dediği yoldu:
ortak ödülü gecelik rollup'a (`adminEconomics`) kullanıcı başına `p`,
günün toplamı `partnerTry` olarak **₺** cinsinden yazılıyor
(`stats_service`), `admin_service.economics` onu kurla çevirip marjdan
düşüyor. Kullanıcı başına ek okuma YOK — ölçek doktrini bozulmadı. Kur
tek yerden okunuyor (`admin_service._kur_oku`); rollup ₺ yazar, çevirmez.

⚠️ `partnerTry` ALANINI TAŞIMAYAN gün (bu ölçümden eski rollup) "ortak
maliyeti 0" değil **"BİLİNMİYOR"** sayılır ve o pencerede tablo marjı
"—" olur: eksik günde hangi kullanıcının ödülünün kayıp olduğu
bilinmediği için satır bazında kurtarılamıyor. Panel o durumda ortak
maliyeti DÜŞÜLMEMİŞ marjı yıldızla gösterir (ölçülmüş bir sayıyı "—" ile
silmek de bir kayıp) ve bantla söyler. Sahibin "Yeniden hesapla"sı
(≤90 gün) o günleri yeniden yazınca alan kendiliğinden dolar — tablonun
en uzun penceresi de 90 gün (`_ECON_DAYS = (30, 90)`), yani yeniden
hesaplama pencerenin tamamını kapatabiliyor.

⚠️ **İki ekranın ortak maliyeti aynı sayı olmak zorunda değil.** Tabloda
maliyet, hakedişi **o pencerede doğmuş** ödüllerden gelir (satın alma
tarihi pencerede; tablonun geliri de pencereye ait); Kullanıcı 360 tek
hakediş dokümanını okur, yani **ömür boyu** yükümlülüğü gösterir.
Penceresinden eski bir atıflı abone tabloda ortak maliyeti 0 ile,
360'ta −$X ile görünür. İkisi de doğru; farkı bilmeyen birini hata sanar.
Ayrıca rollup durumu **toplama ânında** fotoğraflar: satın alma gününden
sonra `void`a düşen hakediş o günün rollup'ında maliyet olarak durur
(sapma tek yönlü — marj olduğundan DÜŞÜK; düzeltmesi "Yeniden hesapla").

## 7. İzlenecek metrikler (canlıda)

**AP-turu (2026-08-29) itibarıyla bu bölümdeki tahminler CANLI ÖLÇÜMLE
doğrulanabilir:** her gerçek LLM çağrısı `usageEvents`'e token sayıları +
tahmini maliyetle yazılıyor (usage_service; girdi $0,30/M, çıktı+düşünme
$2,50/M), her jeton düşümü cüzdan defterine `debit` olarak işleniyor.
Panel → AI sekmesi günlük çağrı/maliyet eğrilerini, Ekonomi sekmesi
jeton akışını gösterir; adminStats'a `ai.estCostToday` ve
`tokens.spentTotalToday` günlük özetleri düşer. Önbellek isabetleri
usageEvents'e HİÇ girmez — "isabet = sıfır maliyet" varsayımı böylece
yapısal olarak doğru.

- aiCache isabet oranı (maliyet öngörüsünün temeli — production-checklist
  notu) ve `TOKENS kuru-çalışma` logunun SIFIRLANDIĞI (enforce kanıtı).
- Abone başına aylık jeton tüketimi dağılımı (~~adminStats'a
  eklenebilir~~ AP-turu: `tokens.spentToday` özellik kırılımıyla eklendi).
- Ücretsiz→abone dönüşüm oranı (%3 eşiği ücretsiz katman maliyetinin
  dengesi).
- Kur 45+₺/$ kalıcılaşırsa: fiyat merdiveni adım 2 öne çekilir.

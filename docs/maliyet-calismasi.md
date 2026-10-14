# RythoAI Maliyet ve Fiyatlama Çalışması (K-turu, 2026-08-13)

> Tüm sayılar KODDAN ölçülmüş girdilerle (prompt boyutları, önbellek
> tasarımı, jeton tablosu) ve Gemini'nin güncel liste fiyatlarıyla
> hesaplandı. Kur varsayımı **1 USD ≈ 42 ₺** (duyarlılık: 40-45 aralığı
> sonuçları ±%7 oynatır). KDV %20, Google Play komisyonu %15
> (küçük geliştirici katmanı).

## 1. Birim maliyetler (LLM: `gemini-3.5-flash`)

Fiyat: ~$0,30 / 1M girdi token'ı · ~$2,50 / 1M çıktı token'ı (düşünme
kapalı — gemini_service thinking_budget=0). Embedding sorgusu ihmal
edilebilir (~$0,000008/çağrı; önbellek isabetinde hiç yok).

⚠️ Model adı bu satırda bir tur boyunca **`gemini-flash-latest` ≈ 2.5 Flash**
yazıyordu ve o ad artık kodda YOK: `core/config.py` `GEMINI_MODEL`
varsayılanı S-turu'nda `gemini-3.5-flash`'e SABİTLENDİ (takma ad arkasındaki
model kaydı değişince düşünme sızıyordu). Birim fiyatlar değişmedi —
`usage_service._USD_PER_M_INPUT/_OUTPUT` aynı iki sayıyı taşıyor ve
`config.py`'deki ölçüm notu da çıktı fiyatını $2,50/M olarak anıyor.

| İş | Girdi (token) | Çıktı (token) | Maliyet/çağrı | Jeton bedeli | Jeton başına gelir* | Marj |
|---|---|---|---|---|---|---|
| Sohbet turu | ~4.000 (tavanlı en kötü ~9.000†) | ≤300 | **~$0,0021‡** (kötü $0,0034) | 1 | ~$0,010 | ~%79 |
| Natal / SR / Progresyon / Sinastri (kimlik; bu turda ÖLÇÜLMEDİ) | ~3.500 | 700-900 | **~$0,0033** | 5 | ~$0,050 | %93 |
| Firaset (yüz okuma) — **GÜNLÜK**, ölçüldü §6l | ~3.110 | 360-440 | **~$0,0020** | 5 | ~$0,050 | %96 |
| BaZi — **GÜNLÜK**, ölçüldü §6l | ~3.230 | 800-1.010 | **~$0,0035** | 5 | ~$0,050 | %93 |
| Doğum kapısı — **GÜNLÜK**, ölçüldü §6l | ~2.810 | 500-700 | **~$0,0026** | 5 | ~$0,050 | %95 |
| İching (+soru hükmü çağrısı) | ~3.500+800 | ~500 | **~$0,0030** | 2 | ~$0,020 | %85 |
| Dyad (çift başına günlük) | ~2.700 | ~200 | **~$0,0018** | 3 | ~$0,030 | %94 |
| Kişisel günlük (abone, jetonsuz) | ~3.000 | ~250 | ~$0,0015 × 30/ay = **~$0,045/ay** | — | abonelik içinde | — |
| Genel burç yorumu (paylaşımlı) | ~2.610 (ölçüldü §6l) | 240-320 | 24 üretim/gün → **~$1,2/AY TOPLAM** (kullanıcı sayısından bağımsız) | — | — | — |
| Hafıza çıkarımı (günde ≤1) | ~2.000 | ~100 | ~$0,0009 → ≤$0,03/ay/kullanıcı | — | — | — |
| Günlük push metni (paylaşımlı, burç başına) | ~1.100 | ~30 | ihmal | — | — | — |

\* Jeton başına gelir: 100'lük paketin KDV+komisyon sonrası neti
(~$1,0) / 100. †K4 tavanı sonrası (son 12 mesaj × 1.200 kr).
‡ Korpus pasajları eklendikten sonraki değer (§6f: ~$0,0020 → ~$0,0021).
Bu satır bir süre $0,0020 yazmaya devam ediyordu ve §2 tablosu da onunla
hesaplanmıştı; GEÇERLİ olan $0,0021'dir, aşağıdaki bütün türetmeler onu
kullanıyor. Bu satırın marj hücresi de aynı sebeple **%80+ → ~%79**
düzeltildi: $0,0021 ÷ $0,010 ile marj 79'dur, 80 değil — yuvarlamayla
"%80+" yazmak §3'ün "%79-93" satırıyla açık çelişki üretiyordu (iki sayı da
aynı iki girdiden türüyor).

⚠️ **"Natal / BaZi / SR / Progresyon / Firasa" tek satırı BÖLÜNDÜ** (§6l,
2026-10-03). İki sebep: (1) üç yüzey (firaset, BaZi, doğum kapısı) günlük
yüzeye geçti, yani artık KULLANIM SIKLIĞI da farklı; (2) üçü ölçüldüğünde
aralarında **1,7 kat** maliyet farkı çıktı ve tek satır bunu saklıyordu.
Ölçülen üç satır birbirinin yerine geçmez. ~$0,0033'lük eski tahmin
büyüklük mertebesinde doğrulandı ama ölçülmemiş yüzeyler (natal, solar
return, progresyon, sinastri) için HÂLÂ TAHMİN — satırda öyle yazıyor.

⚠️ **Burç yorumu satırı da düzeltildi**: "72 üretim/gün → ~$4,5/AY" diyordu
ve o sayı üç dönemin birden ısıtıldığı hâle aitti. Bugün zamanlayıcıda
yalnız bir iş var (`infra/create-scheduler.ps1`, `period=daily`) ve ısıtılan
küme 12 burç × 2 dil = **24 üretim/gün** (`api/maintenance.BURCLAR` ×
`i18n.SUPPORTED`; ikisi de sayılarak doğrulandı). §4'ün sabit gider kalemi
de bu düzeltmeyle birlikte indi.

Önbellek çarpanı: raporlar kişi başına 24s-90g önbellekli; harcama ve
LLM çağrısı YALNIZ önbellek kaçırıldığında. İkinci okuma hem ücretsiz
hem maliyetsiz — yani yukarıdaki maliyetler kullanım başına ÜST sınır.

⚠️ Tek istisna ve bu bir ALT sınır uyarısı: `fact_guard.enforce` uydurma
yakalarsa aynı üretim için **bir LLM turu daha** koşuyor
(`report_service._cached_generate` → `regenerate`), yani o çağrının maliyeti
~2 katına çıkar ve jeton bir kez düşer. Üç günlük yüzeyde bu turun ne
sıklıkta koştuğu **ÖLÇÜLMEDİ**; depodaki tek ölçüm natal raporlara ait ve
oradaki oran yüksek (`_cached_generate` yorumu: üç üretimin üçünde de 2-3
işaret, hepsi yanlış pozitif). İki katı da sonucu değiştirmiyor (§6l
senaryoları $0,06 → ~$0,11 olur, abonelik neti $3,0), o yüzden bu
belirsizlik bir fiyat gerekçesi DEĞİL — ama "maliyet şudur" diye tek sayı
yazmanın da önünde duruyor.

## 2. Gelir ve marj — abonelik

| Kalem | Değer |
|---|---|
| Tüketici fiyatı (KDV dahil, alıcının gördüğü) | **₺179,99/ay** |
| KDV −%20 | ₺149,99 |
| Google Play −%15 | **net ≈ ₺127,5 ≈ $3,0/ay** |

Abonenin aylık LLM maliyeti (senaryolar, jeton zorlaması AÇIK). **Aylık hak
2026-10-02'de 300'den 100'e indirildi (K1, gerekçe §2a); tablo yeniden
türetildi.** Türetme kuralı tek satır: jetonun en pahalı harcanma biçimi
sohbettir (1 jeton = 1 tur ≈ **$0,0021**; §1 + §6f), o yüzden "jeton ×
$0,0021" bir ÜST sınırdır — karışık kullanımda rapor jetonu başına maliyet
beşte birdir ($0,0033 ÷ 5 jeton).

| Senaryo | Kullanım | LLM maliyeti | Türetme | Brüt marj |
|---|---|---|---|---|
| Hafif | 20 jeton (karışık) + günlük | ~$0,09 | 20×0,0021 + 0,045 | **~%97** |
| Orta | 60 jeton + günlük | ~$0,17 | 60×0,0021 + 0,045 | **~%94** |
| Yoğun (jeton tavanı) | 100 jetonun TAMAMI sohbete + günlük + hafıza | **~$0,29** | 100×0,0021 + 0,045 + 0,03 | **~%90** |
| Yoğun + 100'lük ek paket | +$1,0 gelir, +$0,21 maliyet | — | 100×0,0021 | ek paket marjı **~%79** |

Marj = (net $3,0 − LLM) ÷ $3,0; net gelir yukarıdaki ₺127,5 satırından.

### Eski 300'lük hakla karşılaştırma (aynı kurala göre)

Eski 300'lük hakta "Yoğun" satırı 300×0,0021 + 0,045 + 0,03 = **~$0,70**
(marj %77) idi — bu belgenin bir önceki hâlindeki sayı ve hâlâ doğru
türetiliyor. 100'e inince aynı satır **~$0,29**'a düşüyor: maliyet tavanı
kaybolmadı, **üçte birine indi**.

### Tüm Plus yüzeyleri dahil GERÇEK tavan

Yukarıdaki satırlar, orijinal tablonun kurulduğu tabanla (jeton + günlük
okuma + hafıza) kıyaslanabilir kalsın diye aynı üç kalemi topluyor. Abonenin
jetonsuz yüzeyleri bundan fazla; **tek yerde toplanan en kötü durum**:

| Kalem | Aylık | Kaynak |
|---|---|---|
| 100 jetonun TAMAMI sohbete | $0,210 | §1 (100 × $0,0021) |
| Kişisel günlük okuma | $0,045 | §1 |
| Hafıza çıkarımı | $0,030 | §1 |
| Sinyal paketi + akşam sorusu | $0,018 | §6e |
| Takvim yorumu (en kötü, 17 olay) | $0,150 | §6d |
| İlişki okuması (10 kişilik kontenjan dolu) | $0,018 | §6c |
| **Toplam** | **~$0,47** | marj **~%84** |

**Sonuç: en kötü durumda bile ~%84, tipikte %94-97 brüt marj.** Jeton
zorlaması (K5) bu tavanın MATEMATİKSEL garantisidir — kapalıyken tavan
yoktur ve "yoğun kullanıcı" maliyeti sınırsız büyüyebilirdi. Aynı tavan
eski hakla **~$0,89 / ~%70** olurdu (0,63 + 0,261); yani 300 → 100 inişi
en kötü durum marjını **14 puan** iyileştiriyor.

⚠️ Bu tablo §6b ve §6d'de geçen "~$0,70 / ~$0,73" rakamlarının YERİNE
geçer. O iki sayı yalnız kendi bölümlerinin eklediği kalemi önceki
toplama bindiriyordu ve takvim yorumunu ($0,10-0,15) hiç içermiyordu —
yani "abone başına en kötü durum" adıyla sunulan sayı hiçbir zaman tüm
yüzeylerin toplamı değildi. En kötü durum artık **tek yerde** duruyor.

## 2a. K1: aylık hak 300 → 100 (2026-10-02)

Bu belgenin önceki hâli aylık hakkı **yalnızca bir maliyet tavanı** olarak
ele alıyordu (§6c: "matematiksel bir üst sınır"). Eksik olan şey şu: aynı
sayı **satış tavanıdır** da. Hak, kullanıcının gerçek kullanım hızının
ÜSTÜNDEYSE paket hiç satılmaz — çünkü harcama önce `allowance`tan düşer
(`backend/core/wallet.py` `_spend_txn`) ve `purchased` bakiyeye sıra hiç
gelmez.

### Ölçüm (sahip, 1.17.0+45, iki gün yoğun gerçek kullanım)

| Ölçülen | Değer |
|---|---|
| Harcanan jeton | 14 (iki günde) |
| Hız | **~7 jeton/gün ≈ 210 jeton/ay** |
| Eski aylık hak | 300 → hız hakkın **ALTINDA** |
| Parayla alınmış `purchased` bakiye | **1300 jeton, dokunulmadı** |
| Sahibin cümlesi | "bu bitmez, paketler öylece kalır" |

210 < 300 olduğu sürece paket satın almanın hiçbir sebebi yok: hak zaten
bitmiyor. §6c'nin "kişi sayısı yalnız jeton hızını artırır, **ki bu gelir
lehinedir** (paket satışı)" cümlesi tam burada kusurluydu — hız artışı
gelire ancak **hakkı aştığı noktadan sonra** dönüşür; altında kalan her
artış yalnız maliyet üretir, gelir üretmez. Ölçüm hızın hakkın üçte
ikisinde kaldığını gösterdi, yani o cümlenin varsaydığı eşik hiç geçilmiyor.

### Karar ve beklenen etki

Hak **100**'e indirildi (`wallet.MONTHLY_TOKEN_ALLOWANCE`). Aynı ölçülen
hızla (7 jeton/gün) hak **~14. günde** biter (100 ÷ 7) ve ayın kalan
yarısında kullanıcı ya durur ya paket alır. Değişen şey jeton BEDELLERİ değil
(1/2/3/5 aynı — bkz. §3 ve "yapılmayanlar"), yalnız hakkın nerede bittiği.

| | Eski (300) | Yeni (100) |
|---|---|---|
| Hakkın bittiği gün (210/ay hızda) | **hiç** | ~14. gün |
| En kötü durum LLM maliyeti (tüm yüzeyler) | ~$0,89 | **~$0,47** |
| En kötü durum marjı | ~%70 | **~%84** |
| Paket satışı doğar mı | ölçülen hızda hayır | ölçülen hızda evet |

⚠️ **K3 — değişim bir sonraki dönemden.** Kimsenin elindeki hak geri
alınmaz; mevcut dönemde 300 hak almış hesap dönem sonuna kadar 300'üyle
kalır (bekçi: `test_wallet.py::test_K3_mevcut_donemde_eski_hak_GERI_ALINMAZ`).
Bunun maliyet sonucu: geçiş döneminde tavan hâlâ eski tavandır, yani
yukarıdaki ~$0,47 **bir dönem gecikmeyle** yürürlüğe girer.

⚠️ **Sunucu tarafı kartsız deneme** (OT6, `entitlements.in_trial`) bu
değişimden etkilenmez: o yolda abonelik KAYDI hiç doğmaz, `get_wallet` ve
`_spend_txn` aylık hakkı 0'a sabitler ve 30 jetonluk karşılama bakiyesi
`purchased` kovasına yazılır (§6i, ~$0,06 tavan). Hak düşüşünü denemeye
orantılamak EDİNİM maliyetini düşürür ama denemenin "tüm özellikler"
vaadini bozardı.

⚠️ Bunu "deneme = hak 0" diye genellemek YANLIŞ olur ve bir kez öyle
yazıldı: **mağaza denemesi** (RevenueCat `period_type=TRIAL`) ayrı bir
yoldur. `TRIAL_STARTED`, `api/billing.py::_ACTIVATING_EVENTS` içindedir —
yani aktif bir abonelik kaydı yazar VE `reset_allowance` çağırır, dolayısıyla
mağaza denemesindeki kullanıcı tam aylık hakkı (artık 100) alır. Bugün
Play'de kartsız deneme kullanıldığı için bu yol canlıda boş; Play'de bir
ücretsiz deneme teklifi açılırsa deneme maliyeti 30 jetondan 100 jetonluk
hakka sıçrar (~$0,06 → ~$0,21/yeni kullanıcı) ve §6i'deki
"~$0,10/yeni kullanıcı" edinim sayısı geçersiz kalır.

## 3. Kredi paketleri

| Paket | Tüketici (KDV dahil) | Net gelir | Gerçek maliyet aralığı | Marj |
|---|---|---|---|---|
| 50 kredi | ₺80 | ~₺56,7 ≈ $1,35 | $0,03 (rapor ağırlıklı) – $0,11 (sohbet) | **%92-98** |
| 100 kredi | ₺140 | ~₺99,2 ≈ $2,36 | $0,07-0,21 | **%91-97** |
| 200 kredi | ₺250 | ~₺177,1 ≈ $4,22 | $0,13-0,42 | **%90-97** |

> 2026-10-14 (sahip kararı): adetler 100/300/1000'den 50/100/200'e, fiyatlar
> ~₺59,99/155,99/419,99'dan ₺80/140/250'ye. Gerekçe kullanım: paket aylık
> haktan büyük olmamalı, hak bitince ayı tamamlayan bir ek. Net = fiyat ÷ 1,20
> (KDV) × 0,85 (Play); kur 1 $ ≈ 42 ₺. Kredi başına ₺1,60 / 1,40 / 1,25 —
> eski ₺0,60 / 0,52 / 0,42'nin ~2,7-3 katı; marj kısıt değil, kullanıcı
> algısı izlenir (paket satış oranı).

Maliyet aralığının iki ucu: "rapor ağırlıklı" = jetonlar 5'lik raporlara
gider (jeton başına $0,0033÷5 ≈ $0,00066), "sohbet" = jetonlar tek tek
sohbete gider (jeton başına $0,0021). Sayılar §1'in birim maliyetlerinden
yeniden türetildi; önceki hâli sohbet turunu $0,0020 ile hesaplıyordu,
§6f'den beri $0,0021.

Jeton bedelleri (1/2/3/5) maliyet oranına değil ALGILANAN değere göre
bilinçli: derin rapor sohbet turundan yalnızca %65 pahalı ama 5 kat
jeton — kullanıcı gözünde rapor "büyük iş"tir ve bu doğru fiyatlanmış
hissettirir. Değiştirmeye gerek yok.

⚠️ K1 turunda bedel tablosuna (`TOKEN_COSTS`) BİLİNÇLİ OLARAK
DOKUNULMADI; planda İching 2→3 ve dyad 3→2 önerilmişti. Gerekçe ölçüm
disiplinidir: aylık hak değişimi tek başına paket satışını doğurmaya
yetiyor, aynı sürümde iki değişkeni birden oynatmak etkiyi
ÖLÇÜLEMEZ kılardı (hangi değişiklik satışı doğurdu sorusu cevapsız
kalırdı). Bedel tablosu 100'lük hakkın etkisi canlıda okunduktan sonra
ayrıca ele alınır.

## 4. Sabit giderler ve başabaş

| Kalem | Aylık |
|---|---|
| Cloud Run (min-instance 1, 2 vCPU/2Gi — soğuk başlatmayı öldüren bilinçli karar) | ~$25 |
| Genel burç üretimi (paylaşımlı LLM) | **~$1,2** (en kötü ~$2,3) |
| Firestore (küçük ölçek; aiCache+kullanıcı verisi) | ~$1-5 |
| SMS (Türkiye ~$0,01-0,05/adet; kayıt başına 1) | kullanıcıyla ölçeklenir, ~$0,03/yeni kullanıcı |
| NASA/GeoNames/RevenueCat (ücretsiz katman) | $0 |
| **Toplam sabit** | **~$27-32 ≈ ₺1.150-1.350** |

⚠️ Burç üretimi kalemi **~$4,5'ten ~$1,2'ye indi** (§6l): sayı düşmedi,
ÖLÇÜLDÜ — eski değer üç dönemin birden ısıtıldığı hâle aitti, bugün
zamanlayıcıda yalnız günlük iş var (24 üretim/gün, ölçülen birim ~$0,0016).
"En kötü ~$2,3" ikinci tarih kovasının da canlı olduğu hâl: ısıtma tek kovayı
dolduruyor, yerel günü farklı olan kullanıcılar kendi kovasını kaçırıp
üretim tetikliyor.

**Başabaş: ~9-13 abone** (§6l'deki sabit gider düzeltmesinden sonra yeniden
türetildi; K1 sonrası hâli "~11-13" diyordu ve o aralık $32-35'lik sabit
gidere dayanıyordu). Abone başına net katkı = net gelir $3,0 − LLM: hafif
senaryoda $3,0 − $0,09 = **$2,91**, yoğun senaryoda $3,0 − $0,29 = **$2,71**.
Başabaş = sabit ÷ katkı: en iyi uç $27 ÷ $2,91 ≈ 9,3 · yoğun senaryo ucu
$32 ÷ $2,71 ≈ 11,8.

⚠️ Bu iki uç §2'nin SENARYO satırlarından türüyor, yani yalnız üç kalemi
(jeton + günlük okuma + hafıza) topluyor. Belgenin kendi **en kötü durumu**
§2'deki "tüm Plus yüzeyleri dahil GERÇEK tavan" tablosudur ($0,47): katkı
$3,0 − $0,47 = **$2,53** ve başabaş $32 ÷ $2,53 ≈ **12,6 abone**. Yani
"~9-13" aralığının üst ucu zaten en kötü durumu kapsıyor; gerçek bant
**~9-13 abone**. (Pratikte her abonenin aynı anda hem 100 jetonunun
tamamını sohbete yatırması hem takvim/sinyal/ilişki yüzeylerini doyurması
beklenmez; $0,47 bir ÜST sınırdır, tahmin değil.)

100 abonede kaba tablo: gelir ~$300, LLM 100 × ($0,09…$0,29) = ~$9-29,
sabit ~$32 → **aylık net ~$239-259 ≈ ₺10 bin**; aynı hesap $0,47'lik
tavanla ~$221. (Eski 300'lük hakta ~$200-250 veriyordu; fark hakkın maliyet
tavanını daraltmasından geliyor, fiyattan değil.)

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
| "Sınırsız sohbet" vaadi vs jetonlu sohbet | ✅ K3: paywall metni kredi sayısını YAZIYOR — vaat edilen = verilen. D7'den (2026-10-12) beri sayı ARB'de DEĞİL: `benefitChatTitleCount(cuzdan.monthlyAllowance)` sunucunun `/billing/wallet` yanıtından okur, cüzdan okunamadıysa sayısız başlık. `MONTHLY_TOKEN_ALLOWANCE` değişince kurulu paket de doğru sayıyı söyler; bekçi `test_belge_tarifesi` (ARB'de sayı geri gelemez, kablo sunucuya) |
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

**Sonuç: marj matematiği değişmedi.** Bu turun eklediği tek kalem abone
başına ~$0,018-0,027/ay (sinyal yorumu) ve artık §2'nin "tüm Plus yüzeyleri
dahil GERÇEK tavan" tablosunda bir SATIR olarak duruyor. Bu paragrafın eski
hâli "en kötü senaryoda ~$0,70'ten ~$0,73'e (%77 → %76)" diyordu; o sayılar
hem 300'lük hakka hem de takvim yorumunu içermeyen bir toplama dayanıyordu,
o yüzden tek kaynak §2 oldu (bkz. oradaki uyarı). Ücretsiz
katmana açılan harita, LLM maliyeti olmadığı için ücretsiz kullanıcı
maliyetini artırmaz; karşılığında ilk-değer ve dönüşüm beklentisi yükselir
(analiz: "kullanıcı önce 'bu uygulama bana bir şey söylüyor' demeli").

## 6c. P-turu: eklenen kişiler (Çevrem) — 2026-08-18

Kullanıcı artık eşini, çocuğunu, bir yakınını ekleyip haritalarını ve
aralarındaki bağı takip edebiliyor. Tarifeyi belirleyen tek soru şu oldu:
**hangi yüzeyin tavanı yok?**

### Jetonlu yüzeylerin tavanı ZATEN var

Aylık jeton hakkı (K5 zorlaması açık) matematiksel bir üst sınır. Kişi
sayısı bu tavanı BÜYÜTEMEZ — yalnız jeton hızını artırır. Kişinin natal
raporu / BaZi / yıl haritası mevcut **5 jeton**, günlük ikili okuma
**3 jeton**, kişi bağlamlı sohbet **1 jeton** — hiçbir yeni bedel
eklenmedi.

⚠️ Bu paragrafın eski hâli hız artışını kayıtsız şartsız "gelir lehine
(paket satışı)" sayıyordu ve bu gerekçe yanlıştı: hız artışı gelire ancak
**hakkı aştığı noktadan sonra** dönüşür, altında kalan artış yalnız maliyet
üretir. Hak 300 iken ölçülen gerçek hız 210/ay'da kaldı, yani eşik hiç
geçilmedi ve paket satışı doğmadı — K1'in (§2a) kök nedeni budur. Hak 100
olduğundan beri cümle doğrudur; tarihi 2026-10-02'dir, 2026-08-18 değil.

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

**Sonuç: bu özelliğin en kötü durum marjına etkisi ~1 puan** (kontenjan
dolu Plus'ta ~$0,018/ay; §2'deki tavan tablosunda kendi satırı var). Eski
hâli "%77 → ~%76" yazıyordu; o iki yüzde 300'lük hakka aitti ve K1'den
sonra geçersiz — mutlak marj artık yalnız §2'de duruyor. Özellik bir maliyet sorunu
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
3-6 katına çıkar (~$0,003-0,005/gün), aylık **~$0,10-0,15/abone**.

⚠️ Bu paragrafın eski hâli bunu "§6b'deki tavanı (~$0,73) ~%1-2 artırır"
diyordu ve **oran hiçbir okumayla türetilemiyordu**: $0,10-0,15, $0,73'ün
%14-20'sidir. K1'den (hak 100) sonra kalem daha da ağırlaştı — takvim
yorumu artık abonenin **jetonsuz yüzeylerinin EN BÜYÜĞÜ** ve §2'deki ~$0,47
tavanın ~%21-32'si. Marj etkisi: kalem olmasa tavan ~$0,32 (marj ~%89),
kalemle ~$0,47 (~%84), yani **~5 puan**. Marj matematiğini bozmuyor ama
"küçük" değil; en çok izlenmesi gereken LLM kalemi budur (§7).

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

Marj matematiği değişmedi: sohbet turu ~$0,0020 → ~$0,0021. (§1 tablosu
artık bu değeri yazıyor — ‡ notu; iki farklı sohbet maliyeti dolaşmasın.)

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
katkısı **~$2,7-2,9** (senaryoya göre; LLM maliyeti düşülmüş). Bu aralık
K1'de (aylık hak 300 → 100, §2a) ~$2,3-2,9'dan yukarı taşındı: ortak ödülü
değişmedi, abonenin maliyet tavanı daraldı.

| | Ortaksız | Ortaklı (₺30) |
|---|---|---|
| İlk ay net katkı | ~$2,7-2,9 | **~$2,0-2,2** |
| Sonraki her ay | ~$2,7-2,9 | ~$2,7-2,9 (**değişmez**) |
| Ödülün ilk ay netine oranı | — | ~%24 (₺30 / ₺127,5) |
| Ödülün ilk ay KATKISINA oranı | — | ~%24-26 ($0,71 / $2,7-2,9) |

**Ödül TEK SEFERLİK olduğu için marj matematiği bozulmuyor: ilk ay
içinde kendini geri ödüyor.** İkinci aydan itibaren atıflı abonenin
AYLIK katkısı ortaksız aboneyle birebir aynı; kümülatifte ise kalıcı
olarak ₺30 geride kalıyor (bir kez ödendi, geri gelmiyor). Kıyas: §6i'deki 3 günlük
deneme edinim maliyeti ~$0,10/yeni kullanıcı — ortak ödülü onun ~7 katı
ama yalnız **paraya dönmüş** kullanıcıda doğuyor, her kayıtta değil.

Tavandaki (₺500 ≈ $11,9) bir ödül **~4 ayın** net katkısını yerdi
($11,9 ÷ ~$2,8); tavan bir plan değil yazım hatası kapısıdır (30 yerine
3000 yazılması). Eski hâli "~4-5 ay" diyordu ve o aralık ~$2,3-2,9
katkıya aitti.

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

## 6l. GÜ-turu: üç yüzey GERÇEKTEN GÜNLÜK oldu — ölçülen maliyet (2026-10-03)

Firaset (yüz okuma), BaZi ve doğum kapısı **kimlik yüzeyinden günlük yüzeye**
geçti: prompt artık o güne ait ayrı bir blok taşıyor, önbellek kovası o
bloktan türüyor ve TTL üçünde de **24 saate** indi (eskiden sırasıyla 7 / 30 /
30 gün — eski değerler `report_service`'in kendi yorumlarında yazılı).
**FİYAT DEĞİŞMEDİ:** `wallet.TOKEN_COSTS` üçünde de **5 jeton** ve bu turda
o dosyaya dokunulmadı. Sahibin kararı aynen şuydu — *"gerçekten günlük yap
ama maliyetlerini ölçeceğiz sonra jeton miktarına karar vereceğiz"* — yani
bu bölümün işi karar vermek değil, **kararın dayanacağı sayıyı üretmek**.

### Ne ölçüldü, nasıl (CANLI ÇAĞRI YOK)

Prompt'lar gerçek motor çıktılarıyla kuruldu (Istanbul 1990-05-12 14:30, gün
2026-10-03); `gemini_service.generate` ve `retrieve_context` sahteyle
değiştirildi ve `GEMINI_API_KEY` boşaltıldı, yani **tek bir üretim ya da
embedding çağrısı yapılmadı** (gerekçe: üretim kotası gerçek para ve proje
aynı günlerde `Lightning dunning` reddi alıyor). Dönüşümler deponun kendi
ölçümleriyle:

* **~3,6 karakter/token** — `gemini_service.py` içindeki ölçüm satırı.
* **Kelime → token**: korpus taramasıyla ölçüldü (TR ortalama kelime 6,24
  karakter → **~2,01 token/kelime**; EN 4,54 → ~1,54). Çıktı bütçeleri
  prompt'larda KELİME cinsinden yazılı, dolar hesabı token istiyor.
* Birim fiyatlar koddan: `usage_service._USD_PER_M_INPUT` = $0,30/M,
  `_USD_PER_M_OUTPUT` = $2,50/M. Model `core/config.GEMINI_MODEL` =
  `gemini-3.5-flash`; rapor yolunda çıktı tavanı 2048 (kesilirse 8192),
  düşünme kapalı.

### Girdinin yarısından çoğu KORPUS PASAJI — ve bu hiç ölçülmemişti

| Girdi kalemi (TR, karakter) | firaset | BaZi | doğum kapısı |
|---|---|---|---|
| Şablon + ölçülen çekirdek + kalıcı harita | 2.972 | 3.404 | 1.884 |
| …bunun içindeki GÜN bloğu | 268 | 62 | 43 |
| RAG pasajları (ölçüldü, aşağıda) | ~6.224 | ~6.224 | ~6.224 |
| Sistem talimatı (her çağrıda girdiye yazılır) | 2.015 | 2.015 | 2.015 |
| **Girdi token toplamı** | **~3.110** | **~3.230** | **~2.810** |

Üç yüzeyin üçü de `retrieve_context(..., top_k=3)` çağırıyor ve pasaj başına
tavan 2.000 karakter (`rag_service._MAX_CONTEXT_PASSAGE_CHARS`). Korpus
taraması (1.253 TR / 1.255 EN parça, yerel dosyadan): ham parçalar 118-5.697
karakter, **%85,5'i tavanı aşıyor**, yani kırpılmış ortanca tam tavanın
kendisi. Üç pasaj + kaynak başlıkları + ayırıcılar ≈ **6.224 karakter ≈ 1.730
token** — firasetin girdisinin **%55'i**, doğum kapısının **%61'i**.

⚠️ Önceki turun ölçümü (firaset 2.179 karakter) RAG'ı HARİÇ tutuyordu ve
"alt sınır" diye işaretlemişti; **işaret doğruydu, büyüklüğü bilinmiyordu** —
gerçek girdi iddia edilenin ~2,5 katı. İkinci sapma aynı ölçümde: firaset
blokları İMLE (tek satırlık sahte harita) kuruluyordu, oysa gerçek yolda
`chart_whisper` **698** karakterlik kalıcı blok, `gunun_gokyuzu` **268**
karakterlik gün bloğu basıyor. Yani "gün bloğunun ek maliyeti 124 karakter"
değil **268 karakter (~74 token)**. Üç yüzeyde de gün bloğu girdinin küçük
payı (%1-7): **günlüklüğün maliyeti ek GİRDİ değil, ÜRETİM SAYISI.**

⚠️ Ölçülemeyen taraf dürüstçe: RAG'ın HANGİ üç pasajı döndürdüğü
ölçülmedi — öğrenmek bir embedding çağrısı isterdi. Blok boyutu korpusun
kendi uzunluk dağılımından türetildi ve %85,5 tavana dayandığı için ortanca
= tavan. Bir yan bulgu: üç sorgunun HİÇBİRİ kullanıcıya özgü serbest metin
taşımıyor — `FIRASA_RAG_QUERY` dil başına SABİT, kapı sorgusu heksagram
adından (64 değer), BaZi sorgusu element + hüküm adından türüyor — ve sorgu
vektörleri süreç içi LRU'da tutuluyor (`_QUERY_CACHE_MAX` = 128), yani
embedding maliyeti kullanıcı sayısıyla ÖLÇEKLENMİYOR.
Aynı yapı şunu da söylüyor: **aynı ~6.200 karakter her kullanıcıya, her gün,
yeniden faturalanıyor** (girdi önbelleği indirimi beklenmiyor —
`usage_service`: "cached hep 0 bekleniyor").

### Yüzey başına birim maliyet (TR = pahalı dil)

| Yüzey | Model | Çıktı bütçesi (prompt kuralı) | Çıktı token | RAG/embedding | **Maliyet/üretim** |
|---|---|---|---|---|---|
| Firaset | `gemini-3.5-flash` | 180-220 kelime | 360-440 | var (top_k=3) | **$0,0018-0,0020** |
| BaZi | `gemini-3.5-flash` | 400-500 kelime | 800-1.010 | var (top_k=3) | **$0,0030-0,0035** |
| Doğum kapısı | `gemini-3.5-flash` | 250-350 kelime | 500-700 | var (top_k=3) | **$0,0021-0,0026** |
| **Üçü birden, bir gün** | | | | | **$0,0069-0,0081** |

İngilizcede üçü de biraz UCUZ ($0,0018 / $0,0029 / $0,0022): girdisi daha
uzun ama kelime başına token'ı düşük. Aradaki **1,7 katlık** fark tek bir
kalemden geliyor — çıktı bütçesi; girdi kalemi üçünde neredeyse aynı, çünkü
RAG ve sistem talimatı ortak.

Üretim sıklığının yapısal tavanı: **kullanıcı başına, yüzey başına, GÜNDE EN
FAZLA 1 üretim** — o da ekranı o gün açarsa. Ön-ısıtma YOK (üç fonksiyonun
tek çağıranı HTTP uçları; zamanlanmış iş yok, kaynaktan tarandı) ve harcama
yalnız önbellek kaçırıldığında işliyor, üretim yedeğe düşerse jeton iade
ediliyor (`_cached_generate`).

### Kullanıcı başına aylık maliyet — ÜÇ SENARYO

| Senaryo | Üretim/ay | İstenen jeton (ay) | 100'lük hakka göre | LLM maliyeti (ay) |
|---|---|---|---|---|
| (a) Sahibin ÖLÇÜLEN hızı ~7 jeton/gün | — (karışık) | ~210 | hak ~14. günde biter | hakkın tamamı bu üç yüzeye giderse **~$0,05**; karışıkta §2'nin tavanı geçerli |
| (b) Ağır: üç yüzeye de her gün | 90 | **450** | **hakkın 4,5 katı** · hak **6,7. günde** biter | hak tavanlı **~$0,054**; tavansız $0,21-0,24 |
| (c) Hafif: her yüzeye haftada bir | ~12,9 | ~64 | hak bitmez, geriye 36 jeton kalır | **~$0,030-0,035** |

(a) satırı §2a'daki ölçümdür (iki gün gerçek kullanım) ve ⚠️ **bu
değişiklikten ÖNCE** ölçüldü: o gün üç yüzey KİMLİKTİ, bir kez üretilip
7/30/30 gün önbellekten okunuyordu. Aynı davranış bugün daha pahalı — yüzeyi
her gün açmak günde 5 jeton demek. **Yeni hız ÖLÇÜLMEDİ**; ölçülmeyen
söylenmez, (b) onun üst sınırıdır.

"Hak tavanlı" sütunu şunu söylüyor: ağır kullanıcı 450 jeton İSTESE de
elinde 100 var, yani ayda en çok 20 üretim ödeyebiliyor. **Maliyet tarafında
risk YOK ve bu ölçümün en net sonucu budur:** en ağır kullanıcı bile aylık
hak tavanı yüzünden ~$0,06'yı geçemiyor, aboneliğin neti ise $3,0 (§2). Üç
yüzeyin günlük olması **marj matematiğini bozmuyor** — §2'deki "tüm Plus
yüzeyleri dahil GERÇEK tavan" tablosu ($0,47) zaten 100 jetonun TAMAMINI
sohbete yatıran kullanıcıyı sayıyor ve jetonun en pahalı harcanma biçimi
sohbet; bu üç yüzey jetonu sohbetten **ucuza** yakıyor (jeton başına
$0,0004-0,0007 vs $0,0021).

### ⚠️ EN ÖNEMLİ TEK SAYI: ağır kullanıcı 100 jetonu **7. GÜNDE** bitirir

100 ÷ 15 = **6,67 gün**. Üç yüzeye de her gün bakan bir abone, ayın ilk
haftası dolmadan hakkını tüketir; kalan ~23 günde ya durur ya paket alır — ve
bu hesap sohbeti, İ Ching'i, ikili okumayı HİÇ saymıyor (hepsi aynı kovadan
yiyor). Günde hakkın **%15'i** gidiyor.

Aynı üç yüzey düne kadar **~31 jeton/ay** istiyordu (firaset 7 günlük TTL ile
~4,3 üretim + BaZi 1 + kapı 1, hepsi 5 jeton); bugün **450 jeton/ay**
istiyor — **14,3 kat**. Fiyat kararının asıl konusu bu çarpandır, maliyet
değil.

İki yönlü okunmalı: bu, K1'in (§2a) aradığı şeyin ta kendisi — hak ölçülen
hızın altına indirilmişti ki `purchased` bakiyeye sıra gelsin. 14 kat, "sıra
gelir" tarafında fazlasıyla yeterli; sorusu artık **kullanıcı bunu bir vaadin
tutulması mı, bir duvarın erken gelmesi mi sayar** sorusu. O soru maliyet
tablosunda cevaplanamaz, canlı ölçümde cevaplanır (§7).

### Önbellek PAYLAŞILMIYOR — fiyat kararının gerçek dayanağı

Üç yüzeyin önbellek anahtarı `user_id` taşıyor (`firasa-v3-{uid}-…`,
`bazi-report-v3-{uid}-…`, `birthhex-v2-{uid}-…`) ve `_cached_generate`
kayıtları `owner_uid` ile yazıyor: **her kullanıcı her gün kendi üretimini
ödetiyor.** Maliyet kullanıcı sayısıyla DOĞRUSAL büyür — 1.000 ağır kullanıcı
= 1.000 × ~$0,054/ay.

Genel burç yorumu bunun TAM TERSİ: anahtarı `horoscope-{burç}-{dönem}-{tarih
kovası}-{dil}`, yani kullanıcıdan bağımsız ve doküman SAHİPSİZ. Günde **24
üretim** (12 burç × 2 dil) ve bu sayı **kullanıcı sayısından bağımsız**;
ölçülen birim ~$0,0016 → filo toplamı **~$1,2/ay**. 10 kullanıcıda da 10.000
kullanıcıda da aynı.

**Tek cümle: paylaşımlı bir yüzeyi günlük yapmak filoya SABİT bir maliyet
ekler, kişiye özel bir yüzeyi günlük yapmak kullanıcı başına ÇARPAN ekler.**
Üç yüzeyin üçü de ikinci sınıftadır ve fiyat kararı buna dayanıyor: burç
yorumu bedava verilebiliyor çünkü 12 × 2 kova herkesi doyuruyor; firaset
bedava verilemez çünkü her kullanıcı kendi kovasıdır.

### Jeton bedeli — ✅ KARAR VERİLDİ (2026-10-03): **5 jeton, değişmiyor**

Sahibin kararı: üç yüzeyin bedeli **5 jetonda kalıyor**, `TOKEN_COSTS`
değişmiyor. Aşağıdaki tablo artık bir öneri değil, kararın **dayanağı**.

**Karar niçin tutarlı** (ölçüldü, çıkarılmadı): 6,67 günlük duvar kulağa
sert geliyor ama o duvara **yalnız Plus aboneleri** çarpıyor — üç yüzeyin
üçü de `require_plus` arkasında (`api/face_reading.py:96`,
`api/reports.py:259`, `:428`), yani ücretsiz kullanıcı bu yüzeyleri hiç
görmüyor ve hakkı da yanmıyor. Paketler ise **yalnız aboneye** satılıyor
(K2, `token_store_screen.dart`). Sonuç: duvara çarpan kişi, paketi
alabilen tek kişiyle AYNI kişi. K1'in kurduğu ekonomi (hak 300 → 100,
"harca harca bitmez" şikâyeti) tam olarak bunu hedefliyordu.

⚠️ **Kayda geçen risk** (karar sahibin, ama ölçüm burada dursun): günlük
bakması beklenen bir yüzey için haftada bir duvar, kullanıcıya cimri
gelebilir ve günlük yapma işinin değerini yiyebilir. Ölçülecek şey
**yeni harcama hızı** — sahibin eski ölçülen hızı 7 jeton/gündü ve bu
değişiklikten ÖNCEYE ait. İlk kapalı test geri bildirimi bu kararın tek
gerçek sınavı; hız ölçülünce bedel yeniden açılabilir (tablo hazır).

Marj hiçbir seçenekte kısıt DEĞİLDİ: hak tavanı yüzünden ağır kullanıcı
~$0,054/ay'ı geçemiyor (abonelik neti $3,00). Yani karar bir marj kararı
değil, **hakkın ömrü** kararıydı.

Jeton başına gelir §1'in kuralıyla ~$0,010 (100'lük paketin KDV + Play
komisyonu sonrası neti ÷ 100). Marj = 1 − maliyet ÷ (bedel × $0,010).
Belgenin kendi marj bandı: sohbet turu ~%79, rapor sınıfı %93, paket satışı
%70-93 (§1, §3) — yani **%79, bu belgede bugüne kadar kabul edilmiş en düşük
marj**. Aşağıdaki hücreler ölçülen ÜST maliyetle (en kötü uç) hesaplandı.

| Yüzey | `TOKEN_COSTS` | Bugünkü bedel | Ölçülen maliyet | 1 jeton | 2 jeton | 3 jeton | 5 jeton |
|---|---|---|---|---|---|---|---|
| Firaset (yüz okuma) | `face` | **5 jeton** | $0,0020 | %80 | %90 | %93 | **%96** |
| BaZi | `bazi` | **5 jeton** | $0,0035 | %65 | %83 | %88 | **%93** |
| Doğum kapısı | `birth_hexagram` | **5 jeton** | $0,0026 | %74 | %87 | %91 | **%95** |

Aynı seçeneklerin ÖTEKİ yüzü — üç yüzeye de her gün bakan kullanıcıda 100'lük
hak kaç gün yaşar:

| Bedel (yüzey başına) | Günlük jeton | Hakkın ömrü |
|---|---|---|
| 1 jeton | 3 | 33,3 gün |
| 2 jeton | 6 | 16,7 gün |
| 3 jeton | 9 | 11,1 gün |
| **5 jeton (bugün)** | **15** | **6,7 gün** |

Öneri (karar DEĞİL, ölçümün söylediği):

* **Firaset 1-2 jeton.** Tek jetonda bile marj %80, yani belgenin kabul
  ettiği en düşük marjın (sohbet, %79) üstünde. Çıktı bütçesi üç yüzeyin en
  küçüğü (180-220 kelime) ve maliyeti ölçülen en düşük.
* **Doğum kapısı 2 jeton** (%87). 1 jetonda %74 ile bandın altına düşüyor.
* **BaZi 2-3 jeton** (%83-88). 1 jeton %65 ile bandın açıkça altında; BaZi
  400-500 kelime yazıyor, yani ölçülen en pahalı yüzey — bedelinin de en
  yüksek kalması maliyetle TUTARLI olur.
* Karma 1/3/2 (firaset/BaZi/kapı) = günde 6 jeton → hak **16,7 gün** yaşar;
  bu karmada en düşük marj firasetin **%80**'i, yani hiçbir yüzey belgenin
  kabul ettiği en düşük marjın (sohbet, %79) altına inmez.

⚠️ Bu tablo bir fiyat kararı DEĞİL; kodda hiçbir sayı değiştirilmedi. İki
satırı birlikte okumak gerekiyor: **(1)** marj hiçbir seçenekte sorun değil —
en kötü hücre %65, yani asıl kısıt maliyet DEĞİL; **(2)** 5 jeton kalırsa
yüzeyler "günlük" adını taşır ama kullanıcının ayı 7 günde biter. §3'ün kendi
kuralı burada da geçerli — bedeller maliyet oranına değil ALGILANAN değere
göre konmuştu — ve değişen şey tam da algılanan değer: aynı yüzey artık her
gün yeni bir şey söylüyor, yani "büyük iş" algısı bir kerelik bir rapordan
günlük bir alışkanlığa kaydı. §3'ün ölçüm disiplini uyarısı da geçerli: aynı
sürümde iki değişkeni birden oynatmak etkiyi ölçülemez kılar, o yüzden
bedel kararı canlı ölçümden sonra verilmeli (§7'ye metrik eklendi).

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
- **K1'in (§2a) tek doğrulama metriği: hakkın bittiği gün + paket satış
  oranı.** Hak 100'e indirildi çünkü ölçülen hız (210 jeton/ay) 300'ün
  altında kalıyordu ve `purchased` bakiyeye sıra gelmiyordu. Karar ancak
  şu iki sayı birlikte okunursa doğrulanır: (a) abonelerin kaçının
  `allowance`ı dönem bitmeden 0'a indiği, (b) o abonelerin kaçının jeton
  paketi aldığı. (a) yükselip (b) yükselmiyorsa sorun hak değil fiyat ya
  da mağaza akışıdır; `TOKEN_COSTS`a dokunmak ancak bu ölçümden sonra
  gündeme gelir (gerekçe §3 sonundaki uyarıda).
- **Takvim yorumu (§6d) kalemi.** Abonenin en büyük jetonsuz LLM
  kalemi (~$0,10-0,15/ay, tavanın ~%21-32'si); `usageEvents` kırılımında
  ayrıca izlenmeli.
- **§6l'nin tek doğrulama metriği: üç günlük yüzeyin GÜNLÜK ÜRETİM SAYISI
  ve hakkın bittiği gün.** Bedel kararı (bugün 5 jeton, öneri 1-3) ancak şu
  üç sayı birlikte okunursa verilebilir: (a) `usageEvents` kırılımında
  `face` / `bazi` / `birth_hexagram` özelliklerinin kullanıcı başına günlük
  üretim sayısı — yani kaç kullanıcı GERÇEKTEN her gün açıyor (ölçüm "ağır
  kullanıcı" senaryosunun ne kadar gerçek olduğunu söyler); (b) cüzdan
  defterindeki `debit` kayıtlarından hakkın tükendiği gün dağılımı (tahmin:
  ağır kullanıcıda 7. gün); (c) hak tükendikten sonra o kullanıcıların kaçı
  paket aldı. (a) yüksek + (c) düşükse duvar erken geliyor demektir ve
  bedel indirimi (§6l önerisi) gündeme gelir; (a) düşükse yüzeyler günlük
  olduğu hâlde günlük KULLANILMIYOR ve bedel tartışmasının konusu kalmaz.
  ⚠️ Birim maliyetler ölçülürken `fact_guard`ın ikinci LLM turu hariç
  tutuldu; aynı kırılımda özellik başına ÇAĞRI sayısı ile ÜRETİM sayısının
  oranı o turun gerçek sıklığını canlıda verir (bugün ölçülmemiş tek kalem).
- Ücretsiz→abone dönüşüm oranı (%3 eşiği ücretsiz katman maliyetinin
  dengesi).
- Kur 45+₺/$ kalıcılaşırsa: fiyat merdiveni adım 2 öne çekilir.

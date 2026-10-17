# Rytho — Nedir, Neyi Nasıl Yapar

> Bu belge **koddan çıkarıldı**, pazarlama metninden değil. Her iddianın
> arkasında çalışan bir hesap var; olmayanlar en sonda "İddia
> edilemeyecekler" başlığında açıkça listelendi.
> Sürüm: 1.17.0+46 · Tarih: 2026-10-02

---

## 1. Tek cümleyle

**Rytho, gerçek gökyüzü hesabı üzerine kurulmuş kişisel bir kendini tanıma
uygulamasıdır:** Swiss Ephemeris ile senin doğum anını hesaplar, dört ayrı
kadim sistemden (Batı astrolojisi, BaZi, İ Ching, firaset) okuma üretir ve
bunları yapay zekâyla senin diline çevirir — **ölçemediğini söylemez.**

Rakiplerden ayrıldığı yer özellik sayısı değil, **dürüstlük mimarisi**:
doğum saatin yoksa Yükselen'i uydurmaz, hesabın nasıl çıktığını gösterir,
ilişkiler için kalıcı "uyum puanı" vermez.

---

## 2. Dört sekme, dört soru

| Sekme | Cevapladığı soru |
|---|---|
| ☾ **Gökyüzü** | "Bugün ne var?" — burç yorumu + canlı gökyüzü + kişisel günlük okuma |
| ⊙ **Atlas** | "Ben kimim?" — doğum haritan, BaZi'n, kehanet araçların |
| ✦ **Sohbet** (ortadaki buton) | "Aklımdakini sorayım" — haritanı bilen AI |
| ⚭ **Arkadaşlar** / başlığı **"Çevrem"** | "Yakınlarımla ne paylaşırım?" — seri, dürtme, günlük ikili okuma, eklediğin kişiler |
| ☺ **Profil** | Doğum kaydı, abonelik, gizlilik, dil, bildirimler |

---

## 3. Gökyüzü — bugünün katmanı

**Ücretsiz olanlar (her zaman açık):**
- **Günlük burç yorumu** — 12 burç için. Hikâye okuyucusunda tam ekran,
  otomatik ilerleme (süre metnin uzunluğundan hesaplanır), yatay
  kaydırmayla burçlar arası geçiş.
- **Paylaşım kartı** — burç, tarih, yorumdan alıntı, ay evresi. Doğum
  verisi karta asla girmez.
- **Günlük seri (🔥)** — her gün okumanı açınca büyür; büyüdüğü an kutlama
  (kıvılcım + ses). Sıfırlanma **kutlanmaz** — ceza mekaniği yok.

> **Haftalık/aylık burç yorumu ERİŞİLEBİLİR DEĞİL** — belge bunu bir tur
> boyunca ücretsiz katmanın parçası diye saydı, web sitesi de aynı vaadi
> yazdı. Sunucu ucu üç `period` değeri kabul ediyor (`reports.py`
> `daily|weekly|monthly`) ama **uygulama hiçbirini göndermiyor**:
> `providers.dart` düz `/reports/horoscope/{burç}` çağırıyor ve `lib/`
> genelinde `period=` **sıfır** kez geçiyor. Yani hesap var, ona açılan
> kapı yok. Vaat metinlerden çıkarıldı; özelliği gerçekten açmak ayrı bir
> karar (istemciye dönem seçici + önbellek anahtarı gerekir).

> **"Şu an" bu ekranda DEĞİL, Atlas'ta** (R3-2, `sky_screen.dart:377`):
> gökyüzü durumu haritanın yanında yaşıyor, bu ekran "bugün senin için"
> anlatısına odaklandı. Belge bir tur boyunca onu burada listelemeye
> devam etti.

**Rytho+ ile:**
- **Kişiye özel günlük okuma** — genel burç yorumu her Kova için aynıdır;
  bu, senin natal haritanı bugünün gökyüzüyle çarpıştırır (Ay, Yükselen,
  transitler dahil).

---

## 4. Atlas — haritanın katmanı

### "Şu an" — canlı gökyüzü (ücretsiz)

R3-2'de Gökyüzü sekmesinden **buraya taşındı**: gökyüzü durumu haritanın
yanında yaşıyor. Atlas ekranı özeti (`SkyNowSummary`) gösteriyor, dokununca
tam ekran açılıyor (`sky_now_screen.dart`).

- Canlı zodyak çarkı, retro gezegenler, güncel açılar.
- **Ay evresi ve gerçek aydınlanma oranı** — Swiss Ephemeris `pheno_ut`;
  lineer yaklaşım kullanılmıyor.
- Gezegen-Dünya uzaklıkları — JPL Horizons'tan, **yalnız uzaklık
  göstergesi** için (§12b: konum/açı hesabının tamamı Swiss Ephemeris).

### Doğum haritası
- **Çark, yerleşimler, evler ve açılar ücretsizdir** (hesap, LLM yok).
  Kullanıcı ilk dakikada kendi haritasını görür.
- **14 nokta:** 10 gezegen + Chiron + Lilith + Kuzey/Güney Ay Düğümü.
  Her biri için burç, derece, ev, retro durumu, **deklinasyon** ve hız.
- **12 ev + Yükselen**, dokunulabilir natal çark. Doğum saati yoksa evler
  ve Yükselen **üretilmez** — öğle haritası "senin haritan" diye sunulmaz.
- **Açılar** — yalnız liste değil, **yaklaşıyor mu ayrılıyor mu** bilgisiyle
  (yaklaşan açı güçlenir, ayrılan söner).
- **Deklinasyon açıları** (paralel / kontra-paralel, ±0,5° orb) — tüketici
  uygulamalarında nadiren bulunur.
- Element/nitelik dengesi, **stellium** tespiti.
- **Tam rapor (Rytho+):** 400-500 kelimelik derin AI okuması.

### Zaman katmanı (Rytho+)
- **🌞 Yıl Haritası (Solar Return)** — güneş dönüşü haritası; yılın tonu.
  **Relocation destekli:** yaşadığın şehri girersen harita oraya kurulur
  (dönüş anı değişmez, evler/ASC değişir).
- **🌗 İç Takvim** — ikincil progresyon (gün-yıl kuralı): progres Ay'ın
  burcu ve evi, sonraki burç değişimi, progres lunasyon fazı; **solar arc**
  kesinleşmeleri kapalı formda çözülür. Üstüne **30 günlük transit
  takvimi**: kesinleşme günü altın, yaklaşan lila, ayrılan soluk; retro
  istasyonları da işaretli.

### Kehanet araçları (dördü de Rytho+)

> **Üçü artık GÜNLÜK yüzey** (2026-10-03): BaZi, Doğum Kapısı ve Yüz Okuma
> kimlik yüzeyiyken günlük yüzeye geçti. Üçünün de **ölçülmüş çekirdeği
> KALICI** (doğumun dört sütunu · sabit kapı ve pasajı · cihazda hesaplanan
> yüz oranları) ve değişmiyor; her gün değişen şey o çekirdeğin **bugünle
> KESİŞİMİ** — prompt kalıcı olanı ve bugüne ait olanı ayrı başlıklar
> altında veriyor, gün bölümü 2-3 cümleyle sınırlı. Teknik karşılığı:
> okuma önbelleği günde bir kez tazeleniyor (TTL 24 saat; eskiden sırasıyla
> 30 / 30 / 7 gün) ve ekran o gün açılırsa **yüzey başına günde en fazla
> bir üretim** olur — ön-ısıtma yok, ekranı açmayan kullanıcıda hiç üretim
> yok. Aynı gün ikinci bakış ücretsiz (önbellekten).
>
> **Bedeller DEĞİŞMEDİ** ve kanonik yerleri `wallet.TOKEN_COSTS`
> (bkz. §8'deki "Rapor başına bedeller burada TEKRARLANMIYOR" notu).
> Günlüklüğün ölçülen maliyeti ve bedel ÖNERİSİ
> `docs/maliyet-calismasi.md` §6l'de; **bedel kararı sahipte**.

**🀄 BaZi — Dört Sütun.** Projedeki en özgün mühendislik; hazır kütüphane
yok, sıfırdan yazıldı. **Cinsiyet belirtilmezse (`unspecified`) şans yönü
HESAPLANMAZ** (D0): sunucu iki adayı `luck_pillar_candidates` ile yollar,
sekme beyan satırıyla ikisini de gösterir — eskiden "belirtmedim" sessizce
kadın yönü sayılıyordu. Onboarding cinsiyeti önseçili değil (D4).
- Dört sütun (Li Chun yıl sınırı, güneş boylamı ay sınırı, 60'lık gün
  döngüsü, geç-Zi ekolü).
- **Gerçek Güneş Zamanı** — boylam düzeltmesi + Zaman Denklemi. İstanbul'da
  ~60-80 dakikalık fark, doğumların yaklaşık üçte birinde **saat dalını
  değiştiriyor.** Kullanıcıya "13:30 → 12:22 (−68 dk)" diye gösterilir.
- Gizli kökler (藏干) ağırlıklı, her biri kendi On Tanrı'sıyla.
- **Day Master gücü** — ay komutu, kökler, gövdeler, yakınlık; hükmün
  **puan dökümü API'de görünür** (LLM'e sordurulmaz: aynı harita iki gün
  iki farklı hüküm alırdı).
- Şans sütunları (Da Yun) + **takvim yılları** ("1993-2003"), yıllık sütun
  (Liu Nian), **5 Shen Sha yıldızı** (her bulgu hangi kuraldan geldiğini
  taşır), Kong Wang.
- **Cinsiyet belirtilmezse Da Yun'un YÖNÜ hesaplanmaz** (2026-10-10):
  yön cinsiyet + yıl polaritesine bağlı; "belirtmek istemiyorum" seçen
  kullanıcıda motor yön uydurmaz, `luck_direction_known: false` ve iki olası
  dizi (`luck_pillar_candidates`) döner, ekrana beyan satırı girer. Eski
  hâl ikili olmayan cinsiyeti sessizce kadın kuralıyla hesaplıyordu —
  "ölçülmeyen söylenmez" ihlaliydi. Kayıt formu cinsiyeti önseçili vermez.
- **Bugünün katmanı (günlük):** Liu Ri (gün sütunu) + Liu Yue (ay sütunu),
  doğumun dört sütunuyla kesişimi en fazla üç cümlede. Günlüklüğü taşıyan
  terim Liu Ri — ölçüldü: gün sütunu 30 günde 30 ayrı etiket alıyor, ay
  sütunu 2 (Jie sınırına bağlı), o yüzden ay sütunu bağlam olarak basılıyor.

**🪙 İ Ching — Değişimler Kitabı.**
- İki çekim yöntemi **gerçek olasılıklarıyla**: madeni para ve
  civanperçemi (yarrow'un asimetrik dağılımı doğru uygulanmış).
- Rastgelelik `secrets` (kriptografik), `random` değil.
- Hareketli çizgiler → dönüşen heksagram, **hu gua** (nükleer heksagram).
- **Liu Yao / Najia**: altı akraba, Shi/Ying çizgileri, saray ataması
  tablodan değil **kuraldan** üretilir (64 desen tek kuraldan çıkar).
- 64 heksagram × 384 yao pasajı, iki dilde.
- Niyetsiz sorular ("test", "asdf") çekim hakkını harcamadan geri çevrilir.

**☯ Doğum Kapısı.** Doğum anındaki Güneş'in 64 kapılı çarktaki yeri —
çekim değil: **gövdesi kalıcı kimlik katmanı**, günlük olan yalnız son
bölüm (Güneş'in bugün aynı çarkta durduğu kapı + çizgi ve onun doğum
kapısıyla konuşması). Günlük olanın "kapı + çizgi" olması ölçüm sonucu:
bir kapı ~5,7 gün sürüyor, kapı+çizgi ise her gün değişiyor — çizgi
basılmasa yüzey "günlük" değil ~5,7 günlük olurdu. Saat bilinmiyorsa ve
kapı sınırı aşılıyorsa **iki aday da bildirilir**.

**👁️ Yüz Okuma (Firaset).**
- **Fotoğraf sunucuya hiç gitmez.** Tespit cihazda (Google ML Kit + TFLite
  segmentasyon); sunucuya yalnız **oranlar** gider, kare bellekte işlenip
  atılır, diske yazılmaz.
- Ölçülenler: San Ting üç bölge oranı, çene/elmacık, ağız genişliği, dudak
  dolgunluğu, göz aralığı, simetri + **hareketlilik**.
- **Belirti üretir, hüküm değil** ("geniş alın" — "zeki" değil).
- **Bugünün katmanı (günlük):** belirtilerin kendisi KALICI — yüz oranları
  güne göre değişmez ve güne göre oynatılmaz. Her gün değişen tek şey,
  bugünün gökyüzünün aynı belirtilerin hangi tarafını sınadığı (en fazla
  iki cümle). Doğum verisi olmayan kullanıcıda bugüne dair ölçülmüş bir
  olgu yoktur, o yüzden prompt o hâlde "bugün" kelimesini **yasaklıyor** —
  yüzey o kullanıcı için günlük değildir ve olmadığı söylenir.
- Ten rengi (etnisite ölçerdi) ve ses perdesi (cinsiyete bağlı) **bilinçli
  olarak reddedildi**.
- Ayrı, sürümlü, geri alınabilir **biyometrik rıza**; rıza geri alınınca
  üretilmiş okumalar silinir.

---

## 5. Sohbet — haritanı bilen AI

- Konu bazlı arşiv (kaldığın yerden devam / yeni konu / kaydırarak sil);
  kullanılmayan konu 30 gün sonra silinir.
- **Üç katmanlı hafıza:** (1) damıtılmış olgular — kapalı 7 kategori,
  **sağlık bilinçli olarak dışarıda**; (2) ham arşiv; (3) her turda
  haritanın "fısıltısı" (natal + transit + gökyüzü + abonede BaZi).
- **Akıllı arama:** korpus taraması senin cümlenle değil, **konu + senin
  haritanın o konuyla ilgili faktörleriyle** yapılır. "İşimle ilgili ne
  yapmalıyım?" sorusu şuna dönüşür: *"Mesleğin niteliği, statü. Satürn:
  Oğlak (10. ev) · Mars: Boğa. Güneş Kare Mars. Transit Satürn → Güneş."*
- Öneri çipleri: Kariyer · Aşk hayatı · Bu ay ne getiriyor · Para ve iş ·
  Bağlanma.
- **Güvenlik kapısı:** sağlık, hamilelik, ölüm, finans tavsiyesi soruları
  LLM'e hiç gitmez — ama "annem hasta, üzgünüm" gibi paylaşımlar
  engellenmez (iki işaret birlikte aranır: yasak konu **ve** cevap talebi).
  Dil değiştirerek kapı aşılamaz.
- **Sohbet neyi YAPMAZ (B11, 2026-10-10):** Rytho bir astrolog-yoldaştır,
  genel amaçlı asistan değil. Sunum/ödev/mail/metin hazırlamaz, internette
  araştırma yapmaz, görev üstlenmez; istense de dostça yetki alanını
  söyler ve gökyüzüyle ilgili bir şey varsa onu aktarır ("akşam sunum
  var, yetiştiremiyorum" → haritadan ve günden konuşur, taslak teklif
  etmez). Sorulmamış konuda çekince eklemez ("maddi konularda tavsiye
  veremem" yalnız para sorulunca, tek cümle; para sorulunca haritadan
  tema anlatılır, yatırım yönlendirmesi yapılmaz). Sohbete yazılan doğum
  tarihinden harita ÜRETMEZ — sohbet hiçbir şey hesaplamaz; başka bir
  kişinin haritası yalnız Çevrem'de hesaplanır ve oradan sohbete gelir.
  Ölçer: `tools/sohbet_olc.py` (üretim, salt okuma) ve
  `backend/scripts/eval_genericness.py --mode persona`.

---

## 6. Arkadaşlar — serbest metinsiz sosyal katman

> **Tasarım kuralı: yazı kutusu yok.** Görünen her şey türetilmiş veridir.
> Bu, moderasyon yükünü sıfıra yakın tutar ve tacizi yapısal olarak
> imkânsızlaştırır.

- **Kullanıcı adı** (@ad) — sonradan değiştirilebilir, davet bağlantısıyla
  paylaşılır.
- **Rehber eşleşmesi** — numaralar **cihazda** hash'lenir, rehber adları
  cihazdan çıkmaz, sunucu hash listesini **saklamaz**; eşleşme
  **karşılıklıdır** (ikiniz de açmışsanız görünürsünüz). Varsayılan kapalı.
  Rehber ekranı: üstte "Uygulamada" (arkadaş ekle), altta davet edilebilir
  kişiler; arama Türkçe karakter duyarlı.
- **Hazır tepkiler / dürtme** — **12 sabit tepki** (Seri 🔥, Aklımdasın 💭,
  Parla ✨, Devam et 💪, Tebrikler 🎉, Aynı frekans 🛰️, İyi geceler 🌙,
  Bugüne bak 👀, Sarıl 🤗, Şans 🍀, Kahve ☕, Özledim 🫶). Gönderince yıldız
  patlaması + karşı tarafa bildirim. Küme ÜÇ yerde birden aynı olmak
  zorunda: `api/notify.py` `REACTION_EMOJIS`, mobil `kReactions` ve
  `infra/firestore.rules`. (R3-4'te 8'den 12'ye çıktı; belge 8'de kalmıştı.)
- **Günlük ikili okuma (dyad)** — arkadaşınla aranızdaki **bugüne özgü**
  dinamik; iki taraf da aynı metni görür. **Kalıcı uyum puanı bilinçli
  olarak yoktur** — skor hesaplanabiliyor ama kasten gösterilmiyor:
  "geri alınamaz bir damga gerçek ilişkilere zarar verir."
- **İlişki ekranı (yapısal okuma)** — dört nitel eksen (İletişim,
  Duygusal dil, Çekim, Ortak zemin): her biri seviye + ton + dayanak
  açılarıyla. Ölçüm ücretsiz; **yorumu Rytho+ ile AI yazar.**

  1.6.0'a kadar bu yorum 16 cümlelik bir tablodan seçiliyordu (eksen ×
  ton) ve seviye cümleye hiç girmiyordu. Ölçüldü: 15 çiftin 15'i farklı
  ölçüm üretiyor ama yalnız 12'si farklı metin görüyordu — üç çift dört
  cümlenin dördünü de birebir aynı okuyordu. Tablo kaldırıldı; okuma
  artık o çiftin kendi eksenlerinden ve kendi dayanak açılarından
  üretiliyor, çift başına bir kez (30 gün önbellek).
- Seri görünürlüğü kullanıcının kontrolünde; güvenlik menüsünde
  arkadaşlıktan çıkarma, engelleme, şikâyet.

### 6b. Eklediğin kişiler — eş, çocuk, yakın (P-turu)

Sayfanın **başlığı** "Çevrem" (`circleTitle`), **sekme etiketi** ise hâlâ
"Arkadaşlar" (`tabFriends`) — ikisi de kasıtlı: sekme çubuğunda tek kelime
sığıyor, başlıkta sayfanın iki nesneli gerçek kapsamı anlatılıyor. Bu belge
bir tur boyunca ikisini çelişki gibi yazmıştı; çelişki değil, iki ayrı
yüzeyin iki ayrı dizesi.

Sayfa iki farklı nesne barındırıyor ve ikisi bilinçli olarak farklı
çiziliyor.

| | Rytho arkadaşı | Eklediğin kişi |
|---|---|---|
| Rıza | karşılıklı onay | **yok** — kişi kullanıcı değil |
| Ham doğum verisi | istemciye ASLA gitmez | kullanıcının kendi verisi |
| Tepki, seri, "bugün okudu" | var | **YOK** (karşı tarafta kimse yok) |

- **Ad telefondan çıkmaz.** Sunucuya yalnız doğum bilgisi ve ilişki türü
  gider; etiket cihazda yaşar ve Rytho kişiden "eşin", "çocuğun" diye söz
  eder. Rehber tarafındaki duruşun aynısı: üçüncü bir kişinin kimliği
  rızası alınmadan sunucuya yazılmaz.
- **Kontenjan:** ücretsiz 1, Rytho+ 10. Sebep maliyet: kredi harcayan yüzeylerin
  tavanını aylık kredi hakkı çiziyor ama ilişki AI okuması Plus'ta
  kredisiz — kontenjan onun matematiksel emniyeti
  (bkz. `docs/maliyet-calismasi.md` §6c).
- **İlişki türü dekoratif değil.** "Çekim" ekseni Venüs/Mars/Plüton
  temaslarından hesaplanıyor ve bu temaslar aile haritalarında da var.
  Çocuğuyla "Çekim: güçlü" yazmak kabul edilemez; tür seçimi ekseni
  **"Yakınlık ve bakım"** diye adlandırıyor ve AI'ya romantik çerçeveyi
  yasaklıyor. **Ölçüm değişmiyor** — seviye, ton ve dayanak açılar aynı;
  değişen yalnız ad. Ölçüleni gizlemiyoruz, doğru adıyla sunuyoruz.
- **Saat "bilmiyorum" birinci sınıf seçenek** — eklenen kişilerin çoğunda
  saat gerçekten bilinmiyor. Boş bırakılırsa Yükselen ve evler
  üretilmez ve ekranda beyan edilir.

---

## 7. Profil ve hesap

Doğum kaydı düzeltme · yaşanan şehir (Yıl Haritası için) · kullanıcı adı ·
**giriş yöntemleri** (Google/Apple hesabına şifre ekleme, şifreli hesaba
Google bağlama) · bildirimler (aşağıda) · gizlilik anahtarları · **dil
(TR/EN)** — arayüz ve AI yorumlarının dili birlikte değişir · ses efektleri
· abonelik ve krediler · avatar düzenleyici (sürükle-yakınlaştır) ·
**hesap silme** (ne silinip ne silinmeyeceği tek tek yazılır, yazarak onay).

### Bildirimler — ALTI zamanlı tür, ÜÇ anahtar

Belge iki kez bayatladı: önce üç tür sayıyordu (öğle/akşam eklenince), sonra
dört (2026-10-03'te `circle` ve `winback` eklenince). Sunucunun gönderdiği
zamanlı türler `notify_runner.RUN_TYPES`; tanımları
`infra/create-scheduler.ps1`'de. ⚠️ 2026-10-17 ölçümü: canlı Cloud
Scheduler'da `rytho-notify-circle` ve `rytho-notify-winback` işleri **YOK**
— betik o tarihten beri yeniden koşturulmamış, yani bu iki tür kodda var
ama hiç gönderilmiyor. Betik koşunca kapanır.

| Tür | Ne zaman / ne | Hangi anahtar kapatır |
|---|---|---|
| `daily` | sabah günlük okuma | `notifyDaily` |
| `midday` | öğle — **yalnız bugün gerçekten olay varsa** gider; sabah gövdesinin kopyası asla | `notifyDaily` |
| `circle` | 18:00 — Çevrem'deki bir kişi ya da arkadaşla bugün ölçülen geçiş; başlıkta karşı tarafın adı/ilişki etiketi | `notifyFriends` |
| `winback` | 19:00 — 3/10/30 gün sessizlikte birer kez, sonra susar; 10. gün bir Çevrem kişisine değinebilir | `notifyDaily` |
| `checkin` | akşam — günün sinyaline bağlı kişisel soru, dokununca Sohbet açılır | `notifyStreak` |
| `streak` | seri hatırlatıcı | `notifyStreak` |

Buna EK olarak olay tetikli **arkadaş tepkisi** bildirimi var
(`notifyFriends`) — zamanlı değil, karşı taraf bastığında gider.

Yani **tür sayısı anahtar sayısına eşit değil**: `notifyDaily` üç türü
(sabah + öğle + geri kazanım), `notifyStreak` iki türü (akşam + seri),
`notifyFriends` Çevrem notunu ve arkadaş tepkisini birlikte kapatıyor
(`notification_service.py` tür→tercih eşlemesi). Ekranda üç anahtar
görünür, sunucu altı zamanlı tür gönderir. Gizlilik politikası (j) iki yeni
türü 2026-10-17'de anlatmaya başladı. **Sessiz saatler** 22:00-08:00.

> ⚠️ **İlk üç türün GÖVDESİ kullanıcının kendi haritasından gelir**, burcundan
> değil: `daily` birincil yolda `signal_push` (kendi sinyal paketindeki o güne
> özgü AI cümlesi, burç satırı yalnız YEDEK), `midday` kendi haritasında bugün
> kesinleşen açı, `checkin` aynı paketin `checkin_question` alanı. Yalnız
> `streak` ve arkadaş tepkisi sabit şablon. Bu, gizlilik politikası için
> bağlayıcı: "bildirim metinleri burcunuza göre hazırlanır, kişiye özel
> değildir" cümlesi **yanlış beyandı** ve dört kopyadan (web TR/EN, uygulama
> TR/EN) hepsinde düzeltildi (2026-10-02). Bir sonraki tur bildirim gövdesini
> şablona çevirirse politika da geri alınmalı.
>
> ⚠️ İkinci düzeltme aynı günden: **saat dilimi ve arayüz dili bildirim izni
> olmadan da yazılıyor** (`syncNotificationContext` her oturum açılışında
> koşuyor, dili ayrıca `LanguageSync` yazıyor); izne bağlı olan tek alan FCM
> jetonu. Politika bu üçünü birden "bildirimleri açtığınızda" diye koşula
> bağlıyordu.

**Onboarding — "Yıldız Yolu" sihirbazı:** 6 adım, adım başına tek soru;
takımyıldız ilerleme çubuğu her adımda bir yıldız yakar. Doğum saati için
**"Bilmiyorum" birinci sınıf seçenektir** ve sonucu dürüstçe açıklanır.
Sonunda "Büyük Üçlü" perdesi (Güneş/Ay/Yükselen açılışı).

---

## 8. Ücretsiz vs Rytho+

| Ücretsiz (hep açık) | Rytho+ |
|---|---|
| Günlük burç yorumu + hikâye + paylaşım kartı | Kişiye özel günlük okuma |
| Canlı gökyüzü ("Şu an") | Tam natal rapor (AI okuması) + 6 detay ekranı |
| Doğum haritası çarkı, yerleşimler, açılar (hesap) | Yıl Haritası (solar return) |
| Günlük seri | İç Takvim (progresyon + transit) |
| Arkadaş listesi, seri, hazır tepkiler, ilişki eksenlerinin ÖLÇÜMÜ | BaZi · İ Ching · Doğum Kapısı · Yüz Okuma (**BaZi, Doğum Kapısı ve Yüz Okuma GÜNLÜK** — §4; İ Ching çekim başına) |
| Profil, doğum kaydı, avatar, bildirimler, dil, sohbet (kredi) | Arkadaşla günlük ikili okuma |
| **1 kişi ekleme** — harita, Büyük Üçlü ve ilişki ÖLÇÜMÜ açık, yorum kilitli | **10 kişi kontenjanı** + ilişki AI yorumu (kredisiz) |

> ⚠️ Sol kolon bir tur boyunca "arkadaşlar katmanının **tamamı**" diyordu ve
> **aynı tablonun sağ kolonu** ikili okumayı Rytho+'a koyuyordu — tablo
> kendi içinde çelişiyordu. Ölçülen hâl: `/reports/dyad`
> `require_plus("dyad")` taşıyor; `/reports/relationship` ise ücretsiz ama
> abone olmayana `reading_locked: true` dönüyor (eksenler, seviyeler ve
> dayanak açılar herkese açık, **yorumu** Plus). Yani katmanın tamamı değil,
> **ölçümü** ücretsiz.

**3 günlük deneme (OT6):** yeni hesap ilk 3 gün TÜM Rytho+ yüzeylerini
kartsız kullanır ve tek seferlik **30 karşılama kredisi** alır (kalan
bakiye deneme bitince yanmaz). Deneme `is_subscriber`'ın İÇİNDEN geçtiği
için `require_plus` dahil her kapı tek noktadan açılıyor
(`entitlements.in_trial`, profil `createdAt`); paywall geri sayımı
gösterir.

**Kredi ekonomisi:** Rytho+ ayda **100 kredi** verir (devretmez); satın
alınan paketler (50/100/200 — 2026-10-14'te 100/300/1000'den indi) **hiç yanmaz**.

- **Hak 300'den 100'e indi** (K1, bu sürüm). Gerekçe ölçüldü: ~7 kredi/gün
  kullanımda 300 hiç bitmiyordu, yani parayla alınmış bakiyeye **sıra hiç
  gelmiyordu** — harcama önce aylık haktan düşüyor. Değişen şey kredi
  bedelleri değil, **hakkın nerede bittiği**.
- **K3: değişim yalnız BİR SONRAKİ dönemden.** Kimsenin elindeki hak geri
  alınmaz; mevcut dönemde 300 almış hesap dönem sonuna kadar 300'üyle
  kalır. Bekçisi var — bu sessizce bozulabilecek bir şey.
- **K2: kredi paketleri yalnız ABONEYE satılır**; abone olmayana mağazada
  hiç gösterilmez.
- **Sözlük:** kullanıcıya görünen TEK kelime **kredi** (EN *credit*).
  "Jeton"/"token" yalnız kod tanımlayıcılarında (`TOKEN_COSTS`,
  `token_store_screen.dart`, ürün kimlikleri `rytho_tokens_*`) ve push/FCM/ID
  jetonu anlamında kalır — orada standart Türkçe karşılık odur, kredi değil.
  Bekçi: `backend/tests/test_sozluk.py` (ARB değerleri, `core.messages`,
  yayındaki HTML'ler, admin paneli dize literalleri, `docs/store-launch.md`
  mağaza metni blokları).
- **Rapor başına bedeller burada TEKRARLANMIYOR.** Kanonik yer
  `wallet.TOKEN_COSTS`. Bedeli bu belgeye kopyalamak, iki yerden birinin
  sessizce bayatlaması demekti — nitekim §12b'deki pazarlama satırı tam bu
  yüzden "300 kredi" diye kaldı.
- **İstemcide bedel gerçeğinin TEK kaynağı `/wallet` `costs` haritası**
  (D7, 2026-10-12). Mağazanın bedel satırı `bedelNotu(l10n, cuzdan.costs)`
  ile kurulur — ARB şablonu yer tutuculu (`{chat} {iching} {dyad} {deep}`),
  cümlede rakam YOK, rakam yoksa cümle de yok; derin raporların özeti ancak
  hepsi aynı bedeldeyken kurulur (`bedel_notu_test`, `test_honesty`).
  Eski ara çözüm (`bedelSatiri`) şablondaki sayıları KONUMA göre
  değiştiriyordu ve bir tur boyunca İ Ching ile ikili dinamiğin bedellerini
  yer değiştirmiş gösterdi. Sunucu dağıtım penceresi hâlâ geçerli ve bu
  tasarımın sebebi: kurulu paket eski rakamı söyleyemez, çünkü rakam
  pakette değil.
- **Bedel HARCAMADAN ÖNCE on yüzeyde görünür** (`BedelRozeti`, D7): kilit
  kartı (abone olmayan "Rytho+ ile açılır"ı okurken kaç kredi olduğunu
  görür), Atlas'ın dört karosu ve tam rapor satırı, satış ekranının fayda
  satırları (çoklu satırda yalnız hepsi aynı bedeldeyse tek sayı), yüz
  okuma rıza ekranı, sohbetin boş durumu ("Mesaj başına 1 kredi"), ikili
  dinamik, İ Ching. Rozet cüzdan okunamadıysa HİÇ çizilmez — uydurma sayı
  bayat sayıdan kötü. İ Ching'in eski `token_cost` okuyucusu istemciden
  kalktı (sunucu alanı eski paketler için duruyor).
- **Onay kapısı (`BedelKapisi`, eşik 5):** BaZi, Yıl Haritası, İç Takvim ve
  Doğum Kapısı ekrana GİRİLDİĞİ AN üretiliyordu — abone "bir bakayım" diye
  girip 5 kredi harcıyordu. Şimdi sağlayıcı kapının içinde izleniyor: ilk
  "Devam"dan sonra istek gider, tek seferlik (özellik başına tercih), yalnız
  aboneye, yalnız bedel biliniyorken (cüzdan yüklenirken beklenir, okunamadıysa
  sorulmaz — ölçülmeyen söylenmez). Eşik altı bedellerde (sohbet 1, İ Ching
  2, ikili 3) yalnız rozet. Natal tam rapor (Atlas dizini açılınca üretiliyor)
  kapısız kaldı — bedeli satırda, kapı kararı sonraki tur.
  ⚠️ "Uygulama bir raporun kaça geldiğini harcamadan önce gösterir" cümlesi
  pazarlama sayfalarına **AAB 50 kanalda yayıldıktan sonra** yazılır
  (`test_honesty` ters çapası o commit'te döner); bugün yazılamaz, çünkü
  kurulu paketlerde rozet yok.

Kilitli ekranda ücretli uca **istek bile atılmaz** — kart gösterilir, ödeme
ekranı ancak dokununca açılır.

---

## 9. "Ölçülmeyen söylenmez" — dört somut kanıt

Bunlar pazarlama cümlesi değil, kodda çalışan davranışlar:

1. **Doğum saatin yoksa natal Yükselen, evler ve yıl haritası Yükseleni
   hiç üretilmez** — öğle dolgusu "senin yükselenin" diye sunulmaz.
2. **Day Master gücünün puan dökümü** API'de döner — "neden güçlü"
   sorusunun cevabı her an gösterilebilir.
3. **Her Shen Sha bulgusu hangi kuraldan geldiğini taşır** — "model
   uydurdu mu?" sorusunun cevabı çıktının içindedir.
4. **İlişki uyum skoru hesaplanır ama kasten gizlenir.**

Ayrıca motor bir varsayım yaptığında **beyan eder**: şehir çözülemediyse
"Yükselen yaklaşık", BaZi'de sütun birleşmeleri hesaba katılmıyorsa
"kapsam dışı", şans dönemi başlangıcı saatsizse "±4 ay belirsizlik".

---

## 10. Gizlilik duruşu (mağaza formu için de geçerli)

| Veri | Durum |
|---|---|
| Yüz görüntüsü | **Sunucuya hiç gitmez** — cihazda işlenir, oranlar gider, kare silinir |
| Telefon numarası | Ham hâli **saklanmaz** — yalnız SHA-256 özeti |
| Rehber | **Saklanmaz** — eşleştir, dön, at; loga yalnız adet |
| Doğum verisi | Başka kullanıcıya **asla** gitmez (ikili okumada bile sunucuda kalır) |
| Sohbet arşivi | 30 gün; istemci yazamaz, yalnız sunucu yazar |
| Hesap silme | Karşı taraftaki arkadaşlık kayıtları dahil temizlenir (şikâyet kayıtları hariç — gerekçesi gizlilik metninde) |
| Tek cihaz kilidi | Yalnız abonelerde; devralma onayla |
| Ortak bağlantısı tıklaması | Kalıcı kayıt yalnız **gün başına sayaç** — IP, User-Agent, çerez, kimlik YOK. Bu yüzden tekil ziyaretçi **ölçülemez**; sunulan ad "tıklama", "kişi" değil. ⚠️ Kota katmanı IP'yi sayaç anahtarı olarak **bellekte** tutuyor (`ratelimit._client_key`, `sadece_ip=True`; pencere 60 sn, budama 300 sn) — bu yüzden "IP tutulmaz" MUTLAK biçimde yazılamaz, politika "kalıcı kayıtta yok" der |

---

## 11. Teknik omurga

- **Efemeris:** Swiss Ephemeris (`sepl_18.se1` + `semo_18.se1`, 1800-2400),
  kerykeion 5.12.9 / pyswisseph 2.10.3.2 — sürümler sabit.
- **Konum:** offline GeoNames şehir veritabanı (~34 bin şehir) — ağa
  bağımlı değil, deterministik.
- **AI:** Google Gemini (flash), RAG korpusu **TR 1.253 / EN 1.255 parça**
  (canlıdan ölçüldü 2026-10-17, `GET /health/rag`; bu satır bir tur boyunca
  kitaplar eklenmeden önceki "240 parça"yı söyledi). Yedi kamu malı kitap
  (`knowledge/corpus/books/*.jsonl`, parçalar TR'ye aktarılmış): Lilly
  *Christian Astrology* (1647) 457 · Lilly *An Introduction to Astrology*
  (1852) 233 · Alan Leo *How to Judge a Nativity* 221 · Ptolemaios
  *Tetrabiblos* (Ashmand 1822) 160 · Bonatti & Cardan *Anima Astrologiae*
  74 · Sepharial *Astrology* 62 · Rosa Baughan *The Influence of the Stars*
  (1904) 38. Yanında dile göre ayrı yazılmış sekiz özgün doktrin dosyası
  (BaZi, Çin metafiziği, İ Ching, aile, servet, tahmin, ilm-i nücum,
  *Marifetname* aktarımı). Legge'nin 384 yao metni RAG'de değil
  `hexagrams.json`'da.
- **Telif kuralı:** eser kamu malı olsa bile **çevirisi ayrı telif taşır**
  — bu yüzden Ashmand/Legge kullanılır, Robbins/Wilhelm-Baynes kullanılmaz.
- **Sunucu:** FastAPI + Cloud Run; Firestore; RevenueCat + Google Play.

---

## 12. ⚠️ İddia EDİLEMEYECEKLER (mağaza metni yazarken dikkat)

Bunlar şu an kodda **yok**; yazılırsa yanlış beyan olur ve ürünün kendi
ilkesini çiğner:

1. **Vedik astroloji / Nakshatra / Dasha** — hesaplanmıyor. *(✅ R2-D1:
   persona, README ve korpustaki iddialar temizlendi; persona artık
   sorulursa "hesaplanmıyor" diye cevap veriyor. Bekçi test:
   test_honesty.py — geri gelemez.)*
2. **"NASA verisiyle hesaplıyoruz"** — NASA yalnızca gezegen uzaklığı
   göstergesi için; tüm konum/açı hesabı Swiss Ephemeris.
3. **"Yüzlerce kadim kitap"** — korpus yedi kitap + doktrin dosyaları (~1.250 parça/dil); dürüst tarif: *seçilmiş
   kamu malı klasikler + özgün doktrin sentezi*.
4. **"Gerçek Güneş Zamanı kullanıyoruz"** — yalnız **BaZi** için doğru;
   Batı haritasında standart saat dilimi kullanılıyor.
5. **Natal relocation** — yok (relocation yalnız Yıl Haritası'nda).
6. **BaZi'de sütun birleşmeleri (he/sanhe/chong)** — hesaplanmıyor (motor
   bunu zaten beyan ediyor).
7. **"Bilimsel ölçüm"** (firaset için) — eşikler kalibrasyon sabitidir,
   nüfus normu değil.
8. **"Mizaç hesaplıyoruz"** — bağımsız bir mizaç motoru YOK. Doğrusu:
   *mizaç ADI, ölçülen element dağılımından türetilir.* Dağılım gerçekten
   hesaplanıyor (geleneksel yedili + Yükselen; `astro_service`
   `element_distribution`), klasik ad o dağılımın baskın elementinden
   okunuyor. İki kısıt bağlayıcı: **(a)** tek burçtan mizaç okunmaz —
   H-turu'nda genel yorumdaki "safravi" tam da bu yüzden kaldırıldı;
   **(b)** mizaç yalnız **kişisel raporda** geçer, genel burç yorumunda
   asla. Uygulamada dayanağı görünür: Kişilik ekranı hangi gezegenin
   hangi elemente düştüğünü tek tek gösterir (R5-1).

---

## 12b. Pazarlama dil kılavuzu (R2-D1 — bağlayıcı)

Mağaza metni, web sitesi, tanıtım görseli, basın cümlesi — nerede olursa
olsun:

| ❌ Yazılamaz | ✅ Doğrusu |
|---|---|
| "NASA destekli / NASA onaylı astroloji" | "Astronomik efemeris verileriyle hesaplanan gökyüzü konumları" |
| "NASA verisiyle hesaplıyoruz" | "Konum/açı hesabı Swiss Ephemeris; gezegen uzaklık göstergesi NASA JPL Horizons" |
| "Uyum puanınız 82" | "İlişkinin nerede kolaylaştığını, nerede emek istediğini ölçer — puan vermez" |
| "Geleceğinizi söyler" | "Eğilimleri ve zaman pencerelerini gösterir; kesin tarihli kehanet yapmaz" |
| "Sınırsız AI" | "Ayda 100 AI kredisi" (ölçülü ve dürüst — K1'le 300'den indi) |
| "Yüzlerce kadim kitap" | "Seçilmiş kamu malı klasikler + özgün doktrin sentezi" |
| "Bilimsel yüz analizi" | "Cihaz üstü geometrik ölçüm + firaset geleneği yorumu" |

Gerekçe: NASA verisi kullanmak NASA'nın astrolojiyi doğruladığı anlamına
gelmez (Co-Star bile aynı veriyi pazarlıyor — fark yaratmaz, risk
yaratır). Rytho'nun farkı veri kaynağı değil, ZİNCİRİN kendisi: gerçek
hesap → kişisel harita → ölçülmüş transit → kaynaklı yorum → dayanağını
gösteren arayüz.

---

## 13. Konumlandırma önerisi (mağaza/tanıtım için)

> **"Yıldızlar herkese aynı. Sen değilsin."**
>
> Rytho, doğum anını gerçek gökyüzü hesabıyla çözer; dört kadim sistemin
> okumasını tek bir sese dönüştürür. Ölçebildiğini söyler, ölçemediğini
> söylemez — doğum saatini bilmiyorsan Yükselen'ini uydurmaz, ilişkilerine
> puan vermez, sana yalnızca duymak istediğini anlatmaz.

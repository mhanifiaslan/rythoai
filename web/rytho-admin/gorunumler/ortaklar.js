/* Ortaklar (W7 → AD19): affiliate liste + detay; kod üretimi, atıf,
   hakediş, ödeme. Okuma admin (owner+support), YAZIMLAR owner — düğmeler
   rol'e göre gizlenir, sunucu zaten 403'ler.

   Rotalar: #/ortaklar (liste) · #/ortaklar/{id} (detay).
   Uçlar:
   - GET   /api/v1/admin/partners → partner dokümanının TAMAMI + iki
     TÜRETİLMİŞ sayı
     [{id, name, contact, rewardTry, rewardModel, uid, active, notes,
       createdAt, sharePercent, payoutCurrency, taxId, iban, minPayoutTry,
       clicks, referredUsers}]
     ⚠️ `clicks`/`referredUsers` partner dokümanında DURMUYOR: ikisini de
     `list_partners` tek bir `partnerCodes` akışından topluyor. Toplama
     düşerse iki anahtar da yanıtta HİÇ OLMAZ (0 gelmez) — liste o hâlde
     "—" çiziyor, çünkü "ölçemedik" ile "hiç tıklama yok" aynı şey değil.
     ⚠️ `taxId`/`iban`/`minPayoutTry` alanları YALNIZ bir kez yazıldıysa
     gelir; `create_partner` üçünü de hiç yazmıyor (karar, eksiklik değil —
     gerekçesi `partner_self_view` yorumunda).
   - POST  /api/v1/admin/partners {name, contact, notes, rewardTry, uid}
     `uid` ZORUNLU (K-b) ve kapı ÜÇ katmanda birden: bu form, uçtaki
     `PartnerCreate.uid: str = Field(min_length=1, …)` ve servisteki
     `create_partner` (boşluktan oluşan uid'i 400 `uid_required` ile
     düşürür). Formdaki zorunluluk bir UX kapısı — tek kapı O DEĞİL, yani
     gevşetilirse kullanıcı gerekçesiz bir 422 görür.
   - GET   /api/v1/admin/partners/{id} → {partner, codes:[...],
       clicks, clicks30, clickSeries, conversionRate,
       referredUsers, pendingCount, qualifiedCount, voidCount,
       earnedTry, pendingTry, paidTry, balanceTry,
       payoutCurrency, payoutCurrencyMismatchCount,
       attributedGrossUsd, attributedEvents, payouts:[...],
       access:{uid, granted, email, reason}}
     ⚠️ `minPayoutTry` yanıtın KÖKÜNDE DEĞİL, `partner` içinde: uç ortak
     dokümanını olduğu gibi taşıyor. İki yerden birden okunabilir olsaydı
     panelin hangisine baktığı gözle doğrulanamazdı — tek kaynak `partner`.
   - POST  /api/v1/admin/partners/{id}/access {grant:bool} → {status, access}
     Ortağın Firebase custom claim'ini ({partner:true, partnerId}) basar ya
     da kaldırır. 400 gövdesi ÜÇ kod taşıyabilir: `no_uid`,
     `user_not_found`, `uid_taken` — üçü de ayrı ayrı çevrilir, çünkü
     hepsi operatörün YAPACAĞI şeyi değiştirir.
   - PATCH /api/v1/admin/partners/{id}
       {active|name|contact|notes|rewardTry|uid|payoutCurrency|taxId|iban
        |minPayoutTry}
     ⚠️ Uç `exclude_none` uyguluyor: GÖNDERİLMEYEN alan "dokunma" demek,
     yani bu uçtan bir alanı BOŞALTMAK mümkün değil. `minPayoutTry` için
     boşaltmanın karşılığı 0 ("alt sınır yok") ve panel formu tam bunu
     yapıyor; `taxId`/`iban` panelden hiç girilmiyor (aşağıdaki not).
   - POST  /api/v1/admin/partners/{id}/codes {code|null, bonusTokens,
     maxRedemptions|null, expiresAt|null} — panel `bonusTokens` için HEP 0
     yollar (K-a); uç alanı almaya devam ediyor, panelden sıfır dışı girilemez.
   - POST  /api/v1/admin/partners/{id}/payouts {amount, currency, note}
     (ön-izli: iz yazılamazsa 503 mesajı olduğu gibi)

   Dürüst model (OP-turu): ortak, getirdiği kullanıcının İLK aboneliği
   başına SABİT bir ₺ tutar kazanır. Kullanıcıya indirim ya da ödül YOK —
   Play Install Referrer sayesinde kullanıcı kod bile yazmıyor, yani
   ödüllendirilecek bir eylemi yok. Kredi paketleri, denemeler, SANDBOX
   alımları ve yenilemeler ödül üretmez.

   ⚠️ `sharePercent` alanı dokümanda DURUYOR ama KULLANILMIYOR — yüzde
   modeli ileride gerekirse zemin hazır olsun diye. Panelde de
   gösterilmiyor: hesaba girmeyen bir sayıyı "pay %20" diye yazmak,
   "ölçülen yanlış adla sunulmaz" kuralının ihlali olurdu (bir kez öyle
   yazıyordu).

   Para birimi ₺: hakediş TL cinsinden hesaplanıyor. `attributedGrossUsd`
   bilgi amaçlı ve $ — RevenueCat gelirini dolar raporluyor. İkisi aynı
   karta konmaz.

   ⚠️ Ürünün SATTIĞI şey kod değil BAĞLANTI. Panel bir tur boyunca yalnız
   kodu gösterdi ve sahibi paylaşılacak adresi hiçbir yerde bulamadı
   ("ortaklık linki nerede görünmüyor") — kodu kafasından `rytho.app/r/`
   önüne eklemesi gerekiyordu. Bağlantı artık her kod satırında TAM hâliyle
   duruyor; kod ikincil kalıyor çünkü mekanizma o (atıf kodla yazılıyor).

   Aynı turda ölçülen ikinci boşluk: ortağın panosu (`web/ortak/`) hiçbir
   yerden linklenmiyor ve Firebase claim'i olmadan açılmıyordu; claim
   yalnız komut satırından basılıyordu (`tools/set_admin.py --partner`).
   Yani pano pratikte ULAŞILAMAZDI. Giriş adresi ve erişim düğmesi artık
   "Ortak erişimi" modülünde.

   Tüm promise'ler yakalanır → toast. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  /* Kırıntıda kimlik yerine ad görünsün diye son görülen adlar. */
  var adOnbellek = {};

  /* Ortak bağlantısının kökü — TEK YER. Ana makine SABİT YAZILMASIN diye
     burada duruyor ve neden `rytho.app` olduğu ölçülebilir bir şeye
     dayanıyor: AndroidManifest'te `/r/` yol öneki için YALNIZ bu ana makine
     için bir intent-filter var (ölçüldü:
     apps/mobile/android/app/src/main/AndroidManifest.xml — `/i/` için iki
     host, `/r/` için yalnız rytho.app). Yani `rhytoai.web.app` ile üretilmiş
     bir ortak bağlantısı kurulu uygulamada DOĞRUDAN AÇILMAZ; tarayıcıda
     kalır. İkisi aynı sayfayı sunduğu için hata sessiz olur — bu yüzden
     bağlantı hiçbir yerde `location.origin`'den kurulmuyor: panel
     rhytoai.web.app üstünden de açılabiliyor ve o an sessizce çalışmayan
     bağlantılar üretmeye başlardı. */
  var BAGLANTI_KOKU = 'https://rytho.app/r/';

  /* Ortağın kendi panosunun adresi. Sondaki bölü ÖLÇÜLDÜ: bölüsüz istek
     301 ile bölülü adrese düşüyor (firebase.json'da cleanUrls yok), yani
     ikisi de çalışıyor — ortağa verilen adres doğrudan 200 dönen hâli
     olsun. Bu sayfaya üründe hiçbir yerden bağlantı verilmiyor (bilinçli:
     kullanıcı yüzeyinde ortak panosu diye bir kapı yok), dolayısıyla
     adresi ortağa ELDEN vermek tek yol. */
  var ORTAK_PANO_ADRESI = 'https://rytho.app/ortak/';

  /* Panoya kopyalama, üç katman. NEDEN yedek katman var: `navigator.clipboard`
     yalnız güvenli bağlamda VE izin verilmişse çalışır; reddedilirse promise
     sessizce düşer. Burada kopyalanan şey ürünün sattığı bağlantı —
     "kopyalandı" diyip kopyalamamak en kötü sonuç. Üçüncü katmanda
     kullanıcıya elle kopyalaması söylenir; bağlantı zaten ekranda TAM
     hâliyle durduğu için bu çıkmaz sokak değil. */
  function panoyaKopyala(metin, basariMetni) {
    var b = RY.b;
    var yaz = navigator.clipboard && navigator.clipboard.writeText
      ? navigator.clipboard.writeText(metin)
      : Promise.reject(new Error('pano-yok'));
    return yaz.catch(function () {
      // execCommand senkron çalışır ve seçim için DOM'da duran bir alan
      // ister; geçici alan görünmez ama `display:none` OLMAZ (seçilemez).
      var alan = document.createElement('textarea');
      alan.value = metin;
      alan.setAttribute('readonly', '');
      alan.setAttribute('aria-hidden', 'true');
      alan.style.position = 'fixed';
      alan.style.top = '0';
      alan.style.left = '-9999px';
      document.body.appendChild(alan);
      alan.select();
      var oldu = false;
      try { oldu = document.execCommand('copy'); } catch (h) { oldu = false; }
      alan.remove();
      if (!oldu) throw new Error('pano-yok');
    }).then(function () {
      b.toast(basariMetni || 'Panoya kopyalandı.', 'basari');
    }).catch(function () {
      b.toast('Pano erişimi yok — metni ekrandan elle kopyala.', 'uyari');
    });
  }

  function yol(id, ek) {
    return '/api/v1/admin/partners' + (id ? '/' + encodeURIComponent(id) : '') + (ek || '');
  }

  function durumRozeti(b, p) {
    return p.active === false ? b.rozet('Pasif', 'notr') : b.rozet('Aktif', 'aktif');
  }

  /* Ödül tutarı (₺). Sunucu tavanı partner_service.MAX_REWARD_TRY = 500;
     burada da aynı sayı duruyor ki form sunucuya boşuna gitmesin. Tavan
     bir YAZIM HATASI kapısı: 30 yerine 3000 yazılırsa her kazanılan abone
     abonelik fiyatının on katına mal olur ve bunu fark ettirecek hiçbir
     sinyal yoktur. */
  var ODUL_TAVANI = 500;

  function odul(b, p) {
    var v = Number(p && p.rewardTry);
    return isFinite(v) && v > 0 ? b.para(v, '₺') : '—';
  }

  /* uid şekil kapısı — ekleme VE düzenleme formunun ortak kopyası.
     İki formda ayrı ayrı yazılmış olsa biri güncellenip öteki kalırdı;
     "Ödülü değiştir" penceresi zaten bir kez kapısız kalmıştı, yani
     ayrışma bu dosyada teorik değil ölçülmüş bir risk.

     NEDEN şekil kontrolü de gerekiyor: en sık operatör hatası uid yerine
     E-POSTA yapıştırmak. O değer hiçbir hesapla eşleşmez, yani kendi-kodunu
     -kullanma kapısı (`partners/{id}.uid == uid`) ve ortak panosu tam
     eskisi gibi KAPALI kalır — ama liste yeşil "Bağlı" rozeti basar. Panel
     o anda ölçmediği bir bağı beyan etmiş olur, kusur da rozetin arkasında
     saklanır. Gerçek Firebase uid'i boşluk ya da @ içermez. */
  function uidDogrula(v) {
    if (/[\s@]/.test(v)) return 'Kullanıcı kimliği bekleniyor (e-posta değil).';
    return v.length >= 6 ? null : 'En az 6 karakter.';
  }

  function hataToast(h) {
    var m = RY.hataMetni(h);
    if (m) RY.b.toast(m, 'hata');
  }

  /* `access.reason` çevirisi — YALNIZ "bilinmiyor" hâlinde gösterilir.
     Üç neden üç ayrı iş demek: uid gir / uid'i düzelt / tekrar dene. */
  var ERISIM_NEDEN = {
    no_uid: 'Giriş hesabı bağlı değil — sorgulanacak bir hesap yok.',
    user_not_found: 'Bu kullanıcı kimliğiyle bir giriş hesabı yok.',
    unavailable: 'Giriş sistemi şu an okunamadı — durum ÖLÇÜLEMEDİ.'
  };

  /* POST /access 400 gövdesindeki kodlar. `RY.hataMetni` bu kodları olduğu
     gibi (`no_uid`) gösterirdi; makine kodu operatöre ne yapacağını
     söylemez. */
  var ERISIM_HATA = {
    no_uid: 'Ortağın giriş hesabı bağlı değil: önce "Ödülü değiştir" ' +
      'penceresinden kullanıcı kimliğini gir.',
    user_not_found: 'Bu kullanıcı kimliğiyle bir giriş hesabı yok — kimlik yanlış yazılmış olabilir.',
    uid_taken: 'Bu hesap BAŞKA bir ortağa bağlı. Bir giriş hesabı yalnız ' +
      'tek ortak panosu görebilir; önce öteki ortağın erişimini kapat.',
    // 500 `unavailable` da buraya giriyor: `hataMetni` gövdedeki `detail`i
    // 500 dalından ÖNCE okuduğu için operatör ham "unavailable" görürdü.
    // Son cümle sunucunun kendi gerekçesiyle aynı: geçici arıza görüp
    // `partners/{id}.uid` alanını "düzeltmeye" başlamak asıl zararı verir.
    unavailable: 'Giriş sistemi şu an okunamadı — erişim izni YAZILMADI. Birazdan ' +
      'tekrar dene; kullanıcı kimliği alanını düzeltmeye çalışma, sorun kimlikte değil.'
  };

  function erisimHataToast(h) {
    var kod = h && h.detay;
    if (kod && ERISIM_HATA[kod]) { RY.b.toast(ERISIM_HATA[kod], 'hata', { sure: 9000 }); return; }
    hataToast(h);
  }

  /* Uçtan gelen `access`ı panelin kullandığı şekle indirger.
     ⚠️ `granted` ÜÇ değerli ve null "BİLİNMİYOR" demek. Alan hiç yoksa
     (panel yeni, backend eski) sonuç da bilinmiyor OLMALI: `!d.access`
     durumunda false'a düşmek, panelin hiç ölçmediği bir şeyi "kapalı" diye
     beyan etmesi olurdu — "ölçülen yanlış adla sunulmaz" kuralının tam
     ihlali.

     `uid` yedeği YALNIZ `access` hiç gelmediğinde `partner.uid`e düşer.
     Ölçüm varken uç ne dediyse o geçerli: uç uid'i kırpıp boşsa `no_uid`
     diyor (`_erisim_durumu`), yani boşluktan oluşan bir `partners/{id}.uid`
     için `access.uid` null gelir. Yedek o durumda da devreye girerse panel
     "hesap bağlı" sanıp yalnız 400 döndürebilecek bir düğme çizerdi. */
  function erisimOku(d, p) {
    var a = (d && d.access) || null;
    var g = a ? a.granted : undefined;
    return {
      olcumVar: !!a,
      uid: (a ? a.uid : (p && p.uid)) || null,
      granted: g === true ? true : (g === false ? false : null),
      email: (a && a.email) || null,
      reason: (a && a.reason) || null
    };
  }

  /* ---------------- Huninin tepesi (tıklama) ---------------- */

  /* Uçtan gelen tıklama alanlarını panelin kullandığı şekle indirger.

     ⚠️ SAVUNMACI olmak zorunda ve gerekçe teorik değil: panel ile backend
     AYNI ANDA deploy edilmiyor. Hosting saniyeler içinde yayılıyor, Cloud
     Run revizyonu ise ayrı bir betikle çıkıyor (`infra/deploy-backend.ps1`)
     — arada YENİ PANEL + ESKİ BACKEND penceresi gerçekten yaşanıyor. O
     pencerede `clicks` alanı hiç gelmez; `Number(undefined)` NaN üretir ve
     NaN'lı bir şablon panelin tamamını okunmaz yapardı.

     `olcumVar` ile `0` arasındaki fark BİLİNÇLİ: "uç ölçüm göndermedi" ile
     "hiç tıklama olmadı" aynı şey değil. İkincisini birincisi yerine
     göstermek, panelin ölçmediği bir şeyi beyan etmesi olurdu. */
  function huniOku(d) {
    var ham = d || {};
    var varMi = ham.clicks != null || ham.clickSeries != null;
    var seri = Array.isArray(ham.clickSeries) ? ham.clickSeries : [];
    // `clicks30` yanıttan DÜŞEBİLİR (seri okuması hata verdiyse uç anahtarı
    // hiç koymuyor) — `Number(undefined)` NaN, aşağıda null'a çevriliyor.
    // `== null` ayrıca gerekiyor çünkü `Number(null)` 0 döndürüp
    // "ölçtük, sıfır" der; ölçülmeyeni sıfır diye göstermek yanlış beyan.
    var sayi30 = ham.clicks30 == null ? NaN : Number(ham.clicks30);
    var toplam = ham.clicks == null ? NaN : Number(ham.clicks);
    // `conversionRate` null GELEBİLİR ve bu bir değer: "tıklama 0, oran
    // hesaplanamaz" demek (sözleşme). 0 ile karıştırılamaz — 0 oran
    // "tıklama var, kuran yok" demektir ve ortağa söyleyeceği şey bambaşka.
    var oranHam = ham.conversionRate;
    var oran = (oranHam == null || !isFinite(Number(oranHam)))
      ? null : Number(oranHam);
    return {
      olcumVar: varMi,
      toplam: isFinite(toplam) ? toplam : 0,
      sayi30: isFinite(sayi30) ? sayi30 : null,
      seri: seri.map(function (g) { return Number((g && g.count) || 0); }),
      oran: oran
    };
  }

  /* Para birimi kodu → simge. Bilinmeyen kod OLDUĞU GİBİ yazılır: ₺ ya da $
     VARSAYMAK, ödemesi başka birimde yapılan ortağın rakamını yanlış birimle
     göstermek olurdu. (`web/ortak/ortak.js` BİLİNEN kodlar için aynı eşlemeyi
     taşıyor; ikisi ayrışırsa aynı kayıt iki ekranda iki birimle görünür.)

     TEK BİLİNÇLİ FARK boş koddur: orada varsayılan 'TRY' (ortak kendi tek
     birimini görür ve uç `payoutCurrency`yi her zaman döndürür), burada ''
     — yönetim ekranı ÖLÇÜLMEMİŞ birimi "₺" diye çizmek yerine "birim
     bilinmiyor" yazmak zorunda, çünkü karşısındaki ortak TRY olmayabilir. */
  function simge(kod) {
    var k = String(kod || '').toUpperCase();
    if (k === 'TRY') return '₺';
    if (k === 'USD') return '$';
    if (k === 'EUR') return '€';
    return k ? k + ' ' : '';
  }

  /* Ödeme ayarlarını TEK yerden okur: birim, defterdeki birim uyumsuzluğu,
     alt sınır. Üçü ayrı yerden geliyor (`d.payoutCurrency`,
     `d.payoutCurrencyMismatchCount`, `p.minPayoutTry`) ama hepsi TEK
     kararı besliyor: "bu ortağa şimdi ödeme yazılır mı".

     ⚠️ `esik` ÜÇ HÂLLİ ve üçü ayrı şey: alan YOK = anlaşmadaki alt sınır
     panele hiç girilmedi (ekran eşikten SÖZ ETMEZ), 0 = alt sınır yok,
     >0 = eşik. `p.minPayoutTry || 0` yazmak girilmemiş bir eşiği "alt
     sınır yok" diye BEYAN ederdi; ilki bilinmiyor, ikincisi bir anlaşma
     maddesi. Kapı bu yüzden `== null` ile kuruluyor, `Number()` ile değil.

     `birim` de ölçülmemiş olabilir: panel ile Cloud Run aynı anda
     yayılmıyor (bkz. `huniOku` gerekçesi), yani alanı hiç göndermeyen bir
     backend penceresi var. O hâlde null dönüyor ve ekran "—" çiziyor —
     varsayılan yazmak, ölçülmeyeni beyan etmek olurdu. */
  function odemeOku(d, p) {
    var hamEsik = p ? p.minPayoutTry : null;
    // `hamEsik === ''` kapıya EKLİ ve `== null` tek başına YETMİYOR:
    // `Number('')` 0 üretir, yani elle boşaltılmış bir alan "alt sınır yok"
    // diye BEYAN edilirdi. Ortağın panosu aynı değeri ölçülmemiş sayıyor
    // (`web/ortak/ortak.js` → `olculdu`, boş dizeyi dışlıyor); iki ekran
    // aynı kayıtta ayrışırsa biri olmayan bir anlaşma maddesini duyurur.
    var esik = (hamEsik == null || hamEsik === ''
                || !isFinite(Number(hamEsik)))
      ? null : Number(hamEsik);
    var hamBirim = d ? d.payoutCurrency : null;
    var hamUyumsuz = d ? d.payoutCurrencyMismatchCount : null;
    return {
      birim: hamBirim ? String(hamBirim).toUpperCase() : null,
      esik: esik,
      uyumsuz: (hamUyumsuz == null || !isFinite(Number(hamUyumsuz)))
        ? null : Number(hamUyumsuz)
    };
  }

  /* "Bakiye" kartının alt satırı.

     SIRA ÖNEMLİ ve gerekçesi ölçülmüş: defter karışıkken (birim
     uyumsuzluğu) `balanceTry` ödenmiş parayı ödenmemiş gösteriyor, yani o
     hâlde "eşiğe ₺X kaldı" yazmak ekrana ikinci bir yanlış sayı koymak
     olurdu. Karışık defterde söylenecek tek doğru şey, sayıya
     güvenilmemesi.

     Eşik YOKKEN eşikten HİÇ söz edilmiyor: alan girilmediyse bu ortakla
     yapılan anlaşmanın alt sınırı panele hiç yazılmamıştır ve bir sayı
     uydurmak (0 dâhil) olmayan bir kuralı tarif etmek olur. */
  function bakiyeAlt(b, d, od) {
    if (od.uyumsuz > 0) return 'defter karışık — bu sayı güvenilmez';
    var bakiye = Number(d.balanceTry);
    if (!isFinite(bakiye)) return null;
    var durum = bakiye > 0 ? 'ödeme bekliyor' : 'kapalı';
    if (od.esik == null) return durum;
    // 0 ölçülmüş bir ANLAŞMA maddesidir ("alt sınır yok"), eksik alan
    // değil — bu yüzden ayrı yazılıyor.
    if (od.esik === 0) return durum + ' · alt sınır yok';
    if (bakiye >= od.esik) {
      return 'eşik aşıldı · alt sınır ' + b.para(od.esik, '₺');
    }
    return 'eşiğe ' + b.para(od.esik - bakiye, '₺') + ' kaldı';
  }

  /* "Ödeme ayarları" modülünün gövdesi.

     NEDEN VAR: dört alan (`payoutCurrency`, `minPayoutTry`, `taxId`,
     `iban`) bir tur boyunca YALNIZ PATCH ucunda vardı — hiçbir ekran
     göstermiyor, hiçbir form yazmıyordu. Sonucu ölçüldü: yönetici ortağa
     hangi birimde ve hangi tutardan sonra ödeme yapacağını panelden
     okuyamıyor, ortağın panosu da eşikten söz edemiyordu.

     ⚠️ `taxId`/`iban` burada DEĞERİYLE değil VAR/YOK olarak duruyor ve
     panelden de girilmiyor. İki gerekçe: (1) bu panel ekran görüntüsü
     paylaşılan bir yüzey ve ortağın ödeme kimliğini bir de buraya
     çoğaltmanın karar değeri yok — "girildi mi" mutabakat için yeterli;
     (2) PATCH gövdesi denetim izine düşüyor (`api/admin.py`
     `_ortak_izi_maskele`), yani panelden girilen bir IBAN'ın maskelenmiş
     bile olsa kalıcı bir izi olurdu. Değerin kendisi Firestore'da. */
  function odemeAyariIc(b, p, od, sahip) {
    var esikDd;
    if (od.esik == null) {
      // ⚠️ OLMAYAN eşikten söz etmemenin karşılığı bu satır: "0 ₺" ya da
      // "sınır yok" YAZILMIYOR, çünkü ikisi de anlaşmanın söylemediği bir
      // şeyi beyan eder. Söylenen tek şey alanın boş olduğu.
      esikDd = b.rozet('Girilmedi', 'uyari') +
        ' <span class="dipnot">anlaşmadaki alt sınır panele yazılmadı — ' +
        'ortağın panosu da eşikten söz etmiyor</span>';
    } else if (od.esik === 0) {
      esikDd = b.rozet('Alt sınır yok', 'aktif') +
        ' <span class="dipnot">kesinleşen her tutar ödenebilir</span>';
    } else {
      esikDd = '<span class="mono">' + b.e(b.para(od.esik, '₺')) + '</span>';
    }
    var ic =
      '<dl class="alan-liste">' +
        '<dt>Ödeme birimi</dt><dd>' +
          (od.birim ? '<span class="mono">' + b.e(od.birim) + '</span>' +
            // ⚠️ TRY DIŞI birim KALICI bir yanlış sayı üretiyor ve bunu
            // söyleyen başka hiçbir yer yok: hakediş tarafı YALNIZ ₺
            // üretiyor (`rewardTry`) ama ödeme defteri ortağın biriminde
            // yazılıyor ve sunucu ikisini çıkarıyor (`partner_detail`:
            // `balanceTry = earnedTry − paidTry`). Uyumsuzluk bandı bu
            // hâlde YANMAZ, çünkü kayıtların birimi ortağın birimine EŞİT.
            // Yani ekranda tek uyarı bu satır.
            (od.birim !== 'TRY'
              ? ' ' + b.rozet('₺ ile karışıyor', 'uyari') +
                ' <span class="dipnot">hakediş yalnız ₺ üretiyor; bu ' +
                'birimde yazılan ödemeler aynı sayıda toplanıyor, yani ' +
                '"Ödenen" ve "Bakiye" iki farklı parayı karıştırıyor</span>'
              : '')
            // Alan ölçülmedi: panel yeni, backend eski olabilir. "TRY"
            // varsaymak ödemenin birimini uydurmak olurdu.
            : b.rozet('Uç döndürmedi', 'uyari')) + '</dd>' +
        '<dt>Ödeme alt sınırı</dt><dd>' + esikDd + '</dd>' +
        '<dt>Vergi kimliği</dt><dd>' +
          (p.taxId ? b.rozet('Girildi', 'aktif') : b.rozet('Yok', 'notr')) +
          '</dd>' +
        '<dt>IBAN</dt><dd>' +
          (p.iban ? b.rozet('Girildi', 'aktif') : b.rozet('Yok', 'notr')) +
          '</dd>' +
      '</dl>' +
      // Alt sınırın KİMİN kuralı olduğu yazılmak zorunda: ürün genelinde
      // bir eşik YOK ve tanıtım sayfası (web/ortaklik.html) "ödeme
      // takvimi, alt sınır ve ödeme kanalı ANLAŞMADA yazılır" diyor.
      // Buraya girilen sayı o anlaşmanın kopyasıdır, ürünün kararı değil.
      '<p class="dipnot">Alt sınır ürün genelinde <b>tanımlı değil</b>: ' +
      'tanıtım sayfası ödeme takvimi, alt sınır ve kanalın <b>anlaşmada</b> ' +
      'yazıldığını söylüyor. Buraya girilen sayı o anlaşmanın kopyasıdır ve ' +
      'ortağın panosunda <b>"eşiğe ne kadar kaldı"</b> olarak görünür — ' +
      'yani girilmemiş bir eşik ortağa hiç gösterilmez. Sunucu bu sınırı ' +
      '<b>zorlamıyor</b>: ödeme kaydını yine elle sen yazıyorsun, alan ' +
      'yalnız ortağa söz verilen tutarı ekranda tutar.</p>' +
      // Ödeme kimliği panelde neden yok — sessizlik bırakmak "unutuldu"
      // diye okunurdu ve operatör IBAN'ı aramaya devam ederdi.
      '<p class="dipnot">Vergi kimliği ve IBAN panelden <b>girilmiyor ve ' +
      'gösterilmiyor</b> (yalnız var/yok): bu ekran paylaşılabilir bir ' +
      'yüzey. Değerler veritabanında ortağın kaydında durur.</p>';
    if (!sahip) return ic;
    ic += '<div class="eylem-satir">' +
      '<button type="button" class="buton ikincil" id="ortak-odeme-ayar">' +
      b.ik('ayar', 16) + 'Birim ve alt sınırı değiştir</button></div>';
    return ic;
  }

  /* ---------------- Liste ---------------- */

  async function liste(icerik, baglam) {
    var b = RY.b;
    var veri = await RY.get(yol(), { sinyal: baglam && baglam.sinyal });
    if (baglam && !baglam.aktif()) return;
    var ortaklar = Array.isArray(veri.partners) ? veri.partners : [];
    ortaklar.forEach(function (p) { adOnbellek[p.id] = p.name; });
    var sahip = RY.sahipMi();

    var aktifSayisi = ortaklar.filter(function (p) { return p.active !== false; }).length;

    icerik.innerHTML = b.sayfaBaslik({
      baslik: 'Ortaklar',
      alt: ortaklar.length
        ? b.sayi(ortaklar.length) + ' ortak · ' + b.sayi(aktifSayisi) + ' aktif'
        : 'Ortaklık bağlantıları ve hakediş',
      eylemlerHtml: sahip
        ? '<button type="button" class="buton" id="ortak-yeni">' + b.ik('arti', 16) + 'Yeni ortak</button>'
        : ''
    }) + b.modul('Ortak listesi', '<div id="ortak-liste"></div>', '',
      { alt: 'satıra git: huni, hakediş, kodlar, ödemeler' }) +
      '<p class="dipnot">Ortak, getirdiği kullanıcının <b>ilk aboneliği</b> başına sabit ' +
      'bir ₺ tutar kazanır; kullanıcıya indirim verilmez. Kredi paketi, deneme, yenileme ve ' +
      'test alımları ödül ÜRETMEZ. Hakediş satın almadan 15 gün sonra kesinleşir (iade ' +
      'penceresi). Mağaza fiyat indirimi buradan yapılamaz — gerekiyorsa RevenueCat/Play ' +
      'konsolundan elle. <b>Tıklama kişi DEĞİL</b> (aynı kişinin iki cihazı iki ' +
      'tıklamadır) ve <b>Kullanan</b> kurulumdan sonra kod uygulanan hesap sayısıdır — ' +
      'ikisinin uzun sınırları ortak detayında yazılı. İki sütunda "—" görüyorsan sunucu o ' +
      'sayıları döndürmedi; sıfır demek değil.</p>';

    var vt = b.veriTablosu({
      kimlik: 'ortak-tablo', etiket: 'Ortaklar',
      sutunlar: [
        { ad: 'name', baslik: 'Ad', siralanir: true,
          bicim: function (p) { return b.e(p.name || '—'); } },
        { ad: 'contact', baslik: 'İletişim',
          bicim: function (p) { return '<span class="mono">' + b.e(p.contact || '—') + '</span>'; } },
        { ad: 'rewardTry', baslik: 'Ödül', hizala: 'sag', siralanir: true,
          deger: function (p) { return Number(p.rewardTry) || 0; },
          bicim: function (p) { return b.e(odul(b, p)); } },
        // Huninin ilk iki basamağı LİSTEDE. Gerekçe: bir tur boyunca
        // ortakların hiçbir performans sayısı liste ekranında yoktu ve
        // "hangi ortak çalışıyor" sorusu ancak her satır TEK TEK açılarak
        // cevaplanabiliyordu — beş ortakta beş sayfa yüklemesi. İki sayı
        // uçta zaten toplanıyor (`list_partners`), yani burada ek istek yok.
        //
        // ⚠️ `== null` kontrolü `Number()`den ÖNCE olmak zorunda ve bu
        // dosyada ölçülmüş bir tuzak (`huniOku` aynı gerekçe): toplama
        // düşerse uç anahtarı HİÇ KOYMUYOR, `Number(undefined)` NaN üretir
        // ve `p.clicks || 0` yazmak ölçülmeyeni "0 tıklama" diye beyan
        // ederdi. Yokluk "—", sıfır "0" — ikisi ayrı şey.
        { ad: 'clicks', baslik: 'Tıklama', hizala: 'sag', siralanir: true,
          deger: function (p) {
            return p.clicks == null ? null : Number(p.clicks);
          },
          bicim: function (p) {
            if (p.clicks == null) return '—';
            return '<span class="mono">' + b.sayi(Number(p.clicks)) + '</span>';
          } },
        // Etiket "Kullanan", "Gelen" DEĞİL: sayı `referredUsers`, yani
        // kodların `redemptionCount` toplamı ve o sayaç kurulumdan SONRA
        // artıyor (detay ekranındaki uzun gerekçe). Bağlantıya dokunup
        // vazgeçen kimse bu sayının içinde yok.
        { ad: 'referredUsers', baslik: 'Kullanan', hizala: 'sag', siralanir: true,
          deger: function (p) {
            return p.referredUsers == null ? null : Number(p.referredUsers);
          },
          bicim: function (p) {
            if (p.referredUsers == null) return '—';
            return '<span class="mono">' + b.sayi(Number(p.referredUsers)) +
              '</span>';
          } },
        // Hesap bağı iki şeyin ÖN KOŞULU: ortağın kendi panosunu görmesi
        // ve kendi kodunu kendi hesabında kullanamaması. Bağsız bir ortak
        // sessizce ikisini de kaybeder — bu yüzden listede görünür.
        { ad: 'uid', baslik: 'Hesap', siralanir: true,
          deger: function (p) { return p.uid ? 1 : 0; },
          bicim: function (p) {
            return p.uid ? b.rozet('Bağlı', 'aktif') : b.rozet('Bağlı değil', 'uyari');
          } },
        { ad: 'active', baslik: 'Durum', deger: function (p) { return p.active === false ? 0 : 1; },
          siralanir: true, bicim: function (p) { return durumRozeti(b, p); } },
        { ad: 'createdAt', baslik: 'Kayıt', siralanir: true,
          deger: function (p) { var d = b.tarihNesnesi(p.createdAt); return d ? d.getTime() : null; },
          bicim: function (p) { return '<span class="mono">' + b.e(b.tarih(p.createdAt)) + '</span>'; } }
      ],
      anahtar: function (p) { return p.id; },
      satirHref: function (p) { return RY.rotaBagi('ortaklar', [p.id]); },
      satirSinif: function (p) { return p.active === false ? 'durum-pasif' : ''; },
      siralama: { ad: 'name', yon: 'asc' },
      bosMetin: sahip ? 'Henüz ortak yok — "Yeni ortak" ile ekle.' : 'Henüz ortak yok.'
    });
    icerik.querySelector('#ortak-liste').appendChild(vt.el);
    vt.guncelle(ortaklar);

    var yeni = icerik.querySelector('#ortak-yeni');
    if (yeni) yeni.addEventListener('click', yeniOrtakAc);
  }

  function yeniOrtakAc() {
    var b = RY.b;
    var f = b.form({
      alanlar: [
        { ad: 'name', etiket: 'Ad', zorunlu: true, max: 80, otomatik: 'off',
          dogrula: function (v) { return v.length < 2 ? 'En az 2 karakter.' : null; } },
        { ad: 'contact', etiket: 'İletişim', tur: 'text', max: 160, yertutucu: 'e-posta / telefon',
          yardim: 'Ödeme yazışması için; kullanıcıya görünmez.' },
        { ad: 'rewardTry', etiket: 'Ödül (₺)', tur: 'number', zorunlu: true,
          min: 0.01, max: ODUL_TAVANI, adim: '1', deger: 30,
          yardim: 'Kazanılan abone başına SABİT tutar (sunucu tavanı ₺' + ODUL_TAVANI +
            '). Ortak başına ayrı ayarlanır.',
          dogrula: function (v) {
            return v > 0 && v <= ODUL_TAVANI ? null : '0 ile ' + ODUL_TAVANI + ' arası.';
          } },
        // ZORUNLU (K-b). Bağsız ortak "eksik kayıt" değil, SESSİZ AÇIK
        // kapıdır: `partner_service.redeem` kendi-kodunu-kullanma kapısını
        // `partners/{id}.uid == uid` karşılaştırmasına dayandırıyor, yani
        // uid boşken karşılaştırma hiç tutmaz ve ortak kendi kodunu kendi
        // hesabında kullanıp kendine ödül yazdırabilir.
        // Kapı burada YALNIZ DEĞİL: uç `PartnerCreate.uid` alanını
        // `min_length=1` ile zorunlu tutuyor ve `create_partner` boşluktan
        // oluşan uid'i 400 `uid_required` ile düşürüyor. Buradaki
        // zorunluluk kullanıcıya nedenini ZAMANINDA söylemek için —
        // yoksa formu gönderen gerekçesiz bir 422 görürdü.
        // `update_partner` alanı sonradan BOŞALTMAYA da izin vermiyor;
        // aksi hâlde tek bir PATCH kapıyı sessizce kapatırdı.
        { ad: 'uid', etiket: 'Giriş hesabı (kullanıcı kimliği)', zorunlu: true, max: 128,
          otomatik: 'off', yertutucu: 'Kullanıcı kimliği',
          // NEREDEN BULUNUR da yazılıyor: alan zorunlu ama panel uid'i
          // hiçbir yerde aratmıyor, yani operatör "nereden alacağım"
          // sorusunda kalıyordu. Yol ÖLÇÜLDÜ (`gorunumler/kullanicilar.js`):
          // arama alanları arasında `eposta` var ve kullanıcı 360 sayfası
          // kimlik kartında uid'i `title="uid"` ile gösteriyor.
          yardim: 'Ortağın kendi panosunu görmesi ve KENDİ kodunu kullanamaması ' +
            'buna bağlı — bu yüzden zorunlu. Nereden: Kullanıcılar → e-posta ile ' +
            'ara → hesabı aç → kimlik kartındaki kullanıcı kimliği.',
          dogrula: uidDogrula },
        { ad: 'notes', etiket: 'Not', tur: 'textarea', max: 500, satir: 2 }
      ],
      gonderMetin: 'Ortak ekle',
      iptal: { metin: 'Vazgeç', onTikla: function () { m.kapat(); } },
      onGonder: function (d) {
        // `sharePercent` GÖNDERİLMEZ — sunucu 0 varsayar. Yüzde modeli
        // kullanılmıyor; form alanı olarak durması operatöre hesaba giren
        // bir sayı yazdığını sanmasına yol açardı.
        return RY.post(yol(), {
          name: d.name, contact: d.contact || '',
          rewardTry: Number(d.rewardTry),
          // `null` DÜŞTÜ: alan artık zorunlu, `degerler()` de kırpıyor —
          // buraya boş dize gelemez. Eski `d.uid ? … : null` dalı kalsaydı
          // form kapısı ileride gevşetildiğinde uç yeniden bağsız kayıt
          // almaya başlardı ve bunu kimse fark etmezdi.
          uid: d.uid,
          notes: d.notes || ''
        }).then(function (res) {
          var p = (res && res.partner) || {};
          if (p.id) adOnbellek[p.id] = p.name;
          b.toast('Ortak eklendi: ' + (p.name || d.name), 'basari');
          m.kapat();
          if (p.id) RY.rotaYaz('ortaklar', [p.id]); else RY.rotaYenile();
        });
      }
    });
    var m = b.modal({ baslik: 'Yeni ortak', icerik: f.el, genislik: 520 });
    m.ac();
  }

  /* ---------------- Ortak erişimi ---------------- */

  /* "Ortak erişimi" modülünün gövdesi.

     NEDEN ayrı modül — ve yukarıdaki "Bağlı değil" bandıyla NEDEN
     çakışmıyor: bant PARA kapısını anlatıyor (uid boşken ortak kendi kodunu
     kendi hesabında kullanabilir), bu modül ERİŞİM durumunu ve giriş
     adresini. Aynı şeyi iki yerde söyleyen uyarı okunmaz, bu yüzden
     banttaki "panosunu göremez" cümlesi oradan çıkarılıp buraya —
     durumun yanına — taşındı.

     Üç durum AYRI çizilir: açık / kapalı / bilinmiyor. Bilinmeyeni kapalı
     gibi göstermek, panelin ölçmediği bir şeyi beyan etmesi olurdu. */
  function erisimIc(b, p, er, sahip) {
    var ic =
      '<div class="form-alan">' +
        '<label for="ortak-pano-adres">Ortağın giriş adresi</label>' +
        '<input class="girdi mono" id="ortak-pano-adres" readonly spellcheck="false" ' +
        'value="' + b.e(ORTAK_PANO_ADRESI) + '">' +
      '</div>' +
      '<div class="eylem-satir">' +
        '<button type="button" class="buton ikincil kucuk" id="ortak-pano-kopyala">' +
        b.ik('kopyala', 16) + 'Adresi kopyala</button>' +
        '<span class="dipnot">Ürün içinde bu sayfaya hiçbir yerden bağlantı verilmiyor ' +
        '(bilinçli) — adres ortağa ELDEN iletilmek zorunda.</span>' +
      '</div>' +
      '<dl class="alan-liste">' +
        '<dt>Erişim</dt><dd>' +
          (er.granted === true ? b.rozet('Erişim açık', 'aktif')
            : (er.granted === false ? b.rozet('Erişim kapalı', 'notr')
              : b.rozet('Bilinmiyor', 'uyari'))) + '</dd>' +
        '<dt>Bağlı hesap (kimlik)</dt><dd>' +
          (er.uid ? '<span class="mono">' + b.e(er.uid) + '</span>' : '—') + '</dd>' +
        // E-posta, yöneticinin DOĞRU hesabı bağladığını gözle doğrulamasının
        // tek yolu: uid karşılaştırılabilir bir şey değil, e-posta insanın
        // tanıdığı şey. Satır boş olsa da duruyor — yokluğu da bilgi.
        '<dt>Hesabın e-postası</dt><dd>' +
          (er.email ? '<span class="mono">' + b.e(er.email) + '</span>' : '—') + '</dd>' +
      '</dl>';

    if (er.granted !== true && er.reason && ERISIM_NEDEN[er.reason]) {
      ic += '<p class="dipnot">' + b.e(ERISIM_NEDEN[er.reason]) + '</p>';
    }
    if (!er.olcumVar) {
      // Uç `access` alanını hiç döndürmediyse (panel yeni, backend eski)
      // durum ÖLÇÜLMEMİŞTİR; sessizce "kapalı" çizmek yerine söylenir.
      ic += '<p class="dipnot">Sunucu bu istekte erişim durumunu döndürmedi — ' +
        'erişim panelden ölçülemiyor.</p>';
    }

    // ⚠️ Propagasyon: bu cümle olmadan sahip "açtım ama giremiyor" diye
    // geri döner. Firebase custom claim ANINDA geçmez; ölçülmüş davranış,
    // tahmin değil.
    ic += '<p class="dipnot">Erişim, ortağın giriş hesabına işlenen bir izinle verilir ve ANINDA ' +
      'geçerli olmaz: ortağın oturum jetonu yenilenene kadar (en çok 1 saat, ya da ' +
      'çıkış + yeniden giriş) eski hâl sürer. Yani açtıktan hemen sonra ' +
      '"giremiyorum" demesi normaldir — çıkıp yeniden girmesini söyle.</p>';

    // ⚠️ Ortağın O ANDA NE GÖRDÜĞÜ de yazılmak zorunda, yoksa propagasyon
    // cümlesi tek başına yetmez. ÖLÇÜLDÜ (`web/ortak/ortak.js`): claim'i
    // olmayan hesap `/partners/me`den 403 alıyor, panonun `RY.yetkisiz()`
    // dalı `signOut()` çağırıp jenerik "böyle bir sayfa yok" görünümünü
    // (`#bulunamadi`) çiziyor — hesap sayımını engellemek için BİLİNÇLİ.
    // Sonuç: ortak sahibe "verdiğin adres yanlış, sayfa yok" diye döner ve
    // sahip tam da bu turda kapatılan "adresi bulamıyorum" döngüsüne geri
    // girer. Adresi veren ekran, adresin yanlış GÖRÜNECEĞİNİ de söylemeli.
    ic += '<p class="dipnot">Erişimi henüz geçmemiş ortak "yetkin yok" yazan bir ekran ' +
      'GÖRMEZ: pano, hesap sayımını engellemek için jenerik <b>"böyle bir sayfa yok"</b> ' +
      'görünümü çizer ve oturumu kapatır. Ortak "adres yanlış" diye dönerse adres ' +
      'doğrudur — eksik olan erişim izni.</p>';

    if (!sahip) return ic;

    if (!er.uid) {
      // Düğme GÖSTERİLMEZ: uid yokken uç kesin 400 `no_uid` döner, yani
      // yalnız başarısız olabilecek bir düğme olurdu. Onun yerine gerçek
      // sıradaki iş söylenir.
      ic += '<p class="dipnot">Erişim açılabilmesi için önce giriş hesabı bağlanmalı: ' +
        '"Ödülü değiştir" penceresinden kullanıcı kimliğini gir.</p>';
      return ic;
    }

    var ac = er.granted !== true;
    ic += '<div class="eylem-satir">' +
      '<button type="button" class="' + (ac ? 'buton' : 'buton tehlike') + '" id="ortak-erisim">' +
      b.ik(ac ? 'anahtar' : 'kilit', 16) + (ac ? 'Erişimi aç' : 'Erişimi kapat') +
      '</button>' +
      (er.granted === null
        // "Bilinmiyor" İKİ ayrı şeydir ve tek cümleyle anlatılamaz:
        // `unavailable` hâlinde hesap OKUNAMADI, basmak zararsız (yazım
        // yolu Auth'u yeniden okur ve claim'i BİRLEŞTİRİR). `user_not_found`
        // hâlinde ise hesap YOK ve basmak kesin 400 döner — orada
        // "zararsız, aynı claim yeniden yazılır" demek OLMAYAN bir claim'i
        // beyan etmek olurdu (ölçüldü: `set_partner_access` o uid için
        // `user_not_found` fırlatıyor, hiçbir şey yazmıyor).
        ? (er.reason === 'user_not_found'
            ? '<span class="dipnot">Bu kullanıcı kimliğiyle hesap bulunmadığı sürece açma denemesi ' +
              'başarısız olur — önce kimlik düzeltilmeli.</span>'
            : '<span class="dipnot">Durum bilinmiyorken açmak zararsız: izin, hesabın ' +
              'öteki izinleriyle BİRLEŞTİRİLİR — ezilmez.</span>')
        : '') +
      '</div>';
    return ic;
  }

  /* ---------------- Detay ---------------- */

  async function detay(icerik, id, baglam) {
    var b = RY.b;
    var d = await RY.get(yol(id), { sinyal: baglam && baglam.sinyal });
    // Kırıntı kabın DIŞINDA: geç gelen eski bir detay yeni sayfanınkini ezmesin.
    if (baglam && !baglam.aktif()) return;
    var p = d.partner || {};
    var kodlar = Array.isArray(d.codes) ? d.codes : [];
    var odemeler = Array.isArray(d.payouts) ? d.payouts : [];
    var sahip = RY.sahipMi();
    var pasif = p.active === false;
    var er = erisimOku(d, p);
    var huni = huniOku(d);
    var od = odemeOku(d, p);
    adOnbellek[id] = p.name;
    RY.kirinti([{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Ortaklar', href: '#/ortaklar' },
                { metin: p.name || id }]);

    var eylemler = '<a class="buton ikincil" href="#/ortaklar">' + b.ik('daralt', 16) + 'Listeye dön</a>';
    if (sahip) {
      eylemler += '<button type="button" class="buton ikincil" id="ortak-odul">' +
        b.ik('kredi', 16) + 'Ödülü değiştir</button>';
      eylemler += '<button type="button" class="' + (pasif ? 'buton' : 'buton tehlike') +
        '" id="ortak-durum">' + b.ik(pasif ? 'basari' : 'kilit', 16) +
        (pasif ? 'Aktifleştir' : 'Pasifleştir') + '</button>';
    }

    /* Kurulum yönlendirmesi. Yeni eklenen ortak iki adım eksikken hiçbir
       işe yaramıyor: paylaşacağı bağlantı yok ve panosuna giremiyor. Panel
       bunu bir tur boyunca hiç söylemedi — sahip ortağı ekledikten sonra
       "şimdi ne olacak" noktasında yalnız kaldı. Burada YENİ BİR VAAT YOK,
       yalnız var olan iki adım adlandırılıyor ve nerede oldukları söyleniyor.

       "Bilinmiyor" hâli ayrı yazılır: erişimi DOĞRULA demek ile erişimi AÇ
       demek aynı şey değil ve bilinmeyeni kapalı gibi çizmek yanlış beyan. */
    var adimlar = [];
    if (!kodlar.length) adimlar.push('paylaşılacak bağlantıyı üret ("Ortak bağlantısı" modülü)');
    if (!er.uid) {
      // Hesap bağı yokken erişim adımı HENÜZ yapılabilir değil. Ne yapılacağı
      // yukarıdaki 'hata' bandında yazıyor; burada tekrarlanmaz, yalnız
      // sıranın oraya bağlı olduğu söylenir (aynı cümle iki bantta = gürültü).
      adimlar.push('panosuna erişimi aç — önce yukarıdaki hesap bağı gerekiyor');
    } else if (er.granted === false) {
      adimlar.push('panosuna erişimi aç ("Ortak erişimi" modülü)');
    } else if (er.granted !== true) {
      adimlar.push('panosuna erişimi doğrula — durum bilinmiyor ("Ortak erişimi" modülü)');
    }
    var kesinEksik = !kodlar.length || er.granted === false;

    /* Bandın METNİ role göre ayrılır. Destek rolü bu iki adımı YAPAMAZ:
       "Kod üret" formu ve erişim düğmesi yalnız owner'a çiziliyor, uçlar da
       `require_owner` arkasında. Ona modül adını söylemek, gidip
       yapamayacağı bir şeyi aramasına yol açardı — eksikliği bilmesi
       gerekiyor, talimatı değil. */
    var adimBant = '';
    if (adimlar.length) {
      var bandBas = kesinEksik
        ? 'Bu ortak henüz kullanılamıyor. '
        : 'Bu ortakta doğrulanmamış bir adım var. ';
      adimBant = b.bant(bandBas + (sahip
        ? 'Kalan: ' + adimlar.map(function (a, i) { return (i + 1) + ') ' + a; }).join(' · ') + '.'
        : 'Kalan ' + b.sayi(adimlar.length) + ' adım sahip yetkisi ister.'), 'uyari');
    }

    icerik.innerHTML =
      b.sayfaBaslik({
        baslik: p.name || 'Ortak',
        alt: [p.contact, 'ödül ' + odul(b, p),
              p.createdAt ? 'kayıt ' + b.tarih(p.createdAt) : null]
          .filter(Boolean).join(' · '),
        eylemlerHtml: eylemler
      }) +
      (pasif ? b.bant('Bu ortak PASİF — kodları çalışmaya devam eder, listede soluk görünür.', 'bilgi') : '') +
      // Bu bant PARA kapısıdır, erişim durumu DEĞİL: kendi-kodunu-kullanma
      // kapısı `partners/{id}.uid == uid` karşılaştırması olduğu için uid
      // boşken hiç tutmaz — ortak kendi kodunu kendi hesabında kullanıp
      // kendine ödül yazdırabilir. 'hata' (role="alert") çünkü bu eksik veri
      // değil, açık kapı.
      // Form artık uid'i zorunlu tutuyor, yani böyle bir kayıt ya zorunluluk
      // öncesinden kalmadır ya elle yazılmıştır — operatör "nasıl oldu"
      // sorusuna burada cevap bulsun.
      // ⚠️ Eski metindeki "kendi panosunu göremez" cümlesi BİLEREK
      // ÇIKARILDI: aynı şeyi aşağıdaki "Ortak erişimi" modülü durumla
      // birlikte söylüyor. İki yerde birden söylenen uyarı okunmaz, ve bu
      // bandın işi para riskini yalnız başına taşımak.
      (p.uid ? '' : b.bant('Bu ortağın giriş hesabı BAĞLI DEĞİL ve bunun PARA ' +
        'sonucu var: kendi kodunu kendi hesabında kullanıp kendine ödül yazdırması ' +
        'engellenemez — kapı hesap kimliği karşılaştırmasına dayanıyor, boş kimlikle hiç tutmaz. ' +
        'Yeni kayıtlarda kimlik zorunlu, yani bu kayıt zorunluluk öncesinden kalma ya da ' +
        'elle açılmış. "Ödülü değiştir" penceresinden hemen kullanıcı kimliği girilmeli.', 'hata')) +
      adimBant +
      // ⚠️ SIRA BİLİNÇLİ: sahibin bulamadığı iki şey (bağlantı ve ortak
      // erişimi) sayısal kartların ÜSTÜNDE. Önceki sırada kodlar sayfanın
      // en altındaydı ve huni/para kartları onları ekranın dışına itiyordu —
      // ölçülen şikâyetin bir yarısı tam buydu.
      b.modul('Ortak bağlantısı',
        '<div id="ortak-kodlar"></div>' +
        '<p class="dipnot">Ortak bu bağlantıyı paylaşır. Uygulama KURULUYKEN bağlantı ' +
        'doğrudan uygulamayı açar (Android App Links yalnız <b>rytho.app</b> için ' +
        'tanımlı); kurulu değilken sayfa Play’e yönlendirir ve kod Install Referrer ' +
        'ile taşınır — kullanıcı hiçbir yere kod GİRMEZ.</p>' +
        (sahip ? '<div id="ortak-kod-form"></div>' : ''),
        b.etiket(b.sayi(kodlar.length) + ' bağlantı'),
        // Eski alt metin "kullanıcıya jeton bonusu" diyordu; K-a ile panel
        // artık bonusTokens'ı hep 0 yolluyor, yani o cümle olmayan bir ödülü
        // beyan ediyordu. Kodun ÖLÇÜLEN işi tek: atıf yazmak.
        { alt: 'paylaşılan şey bağlantı · sonundaki kod yalnız atıf yazar · kullanıcıya ödül YOK' }) +
      b.modul('Ortak erişimi', erisimIc(b, p, er, sahip),
        er.granted === true ? b.rozet('Açık', 'aktif')
          : (er.granted === false ? b.rozet('Kapalı', 'notr') : b.rozet('Bilinmiyor', 'uyari')),
        { alt: 'ortağın kendi panosuna girip kazancını görmesi' }) +
      // Huni — sahibin sorduğu "benden kaç kişi gelmiş, kaçı alım yapmış".
      // ⚠️ TEPESİ BİR TUR BOYUNCA YOKTU: tıklama hiç ölçülmediği için
      // ızgara ortağın SONUCUNU gösteriyordu, çabasını değil. Linkini 500
      // kişiye gönderen ortak "3" görüyor ve tanıtımının işe yarayıp
      // yaramadığını bilemiyordu; dönüşüm oranı da bölen olmadan
      // hesaplanamıyordu.
      '<section class="izgara-kpi" aria-label="Huni">' +
      b.istatistikKarti({ ad: 'Tıklama',
        deger: huni.olcumVar ? b.sayi(huni.toplam) : '—',
        alt: huni.olcumVar
          ? (huni.sayi30 != null ? 'son 30 gün ' + b.sayi(huni.sayi30)
             : 'bağlantı açılışı')
          : 'uç bu alanı döndürmedi — ölçülemedi',
        // Kıvılcım son 30 günün günlük serisi: tek bir toplam, tanıtımın
        // BİTTİĞİNİ (seri sıfıra indi) hiç göstermez.
        kivilcim: huni.seri }) +
      // ⚠️ ETİKET DÜZELTİLDİ. Burada "Gelen kullanıcı" yazıyordu ve
      // ölçülen şey o DEĞİLDİ: sayı `referredUsers` = kodların
      // `redemptionCount` toplamı, o sayaç ise `partner_service.redeem`
      // içinde uygulama KURULDUKTAN sonra artıyor (kurulum sonrası ilk
      // açılışta Install Referrer okunup `/billing/redeem-code` çağrılıyor
      // — `partner_referrer.dart`). Yani bağlantıyı açıp kurmayan kimse bu
      // sayıya hiç girmiyor. Alan adı `referredUsers` olarak KALIYOR
      // (sözleşme kırılmasın); düzeltilen yalnız EKRAN ETİKETİ.
      b.istatistikKarti({ ad: 'Bağlantıyı kullanan', deger: b.sayi(d.referredUsers || 0),
        alt: 'kurulumdan sonra kod uygulandı' }) +
      // `conversionRate` sözleşmede BÖLÜM (kuran / tıklama), yüzde değil —
      // o yüzden 100 ile çarpılıyor. null "tıklama 0, oran hesaplanamaz"
      // demek ve 0'dan AYRI gösterilmek zorunda: 0 oran "tıklama var,
      // kuran yok" der ve ortağa söylediği şey bambaşkadır.
      b.istatistikKarti({ ad: 'Dönüşüm',
        deger: huni.oran == null ? '—' : b.yuzde(huni.oran * 100),
        // ⚠️ `null` + ölçüm VAR hâli "ölçemedik" DEĞİL: uç oranı yalnız
        // tıklama 0 iken null döndürüyor (`partner_service`), yani ölçtük ve
        // bölen sıfır. "Henüz ölçüm yok" demek ölçüleni yanlış adla sunmak
        // olurdu — özellikle tıklama sayacından ÖNCE kurulum almış eski
        // ortaklarda (Tıklama 0, kullanan 5) operatör paneli bozuk sanardı.
        alt: huni.oran == null
          ? (huni.olcumVar ? 'tıklama 0 — oran hesaplanamaz'
             : 'uç bu alanı döndürmedi')
          // %100'ün ÜSTÜ bozuk veri değil: sunucu oranı bilerek kırpmıyor
          // (`partner_service`), çünkü kırpmak ölçüm boşluğunu gizlerdi.
          // Operatör açıklamasız bir "%150" görünce paneli suçlar, o yüzden
          // sebep kartın altında yazıyor — uzun hâli aşağıdaki dipnotta.
          : (huni.oran > 1 ? 'tıklaması sayılmayan kurulumlar var'
             : 'tıklamanın kuruluma dönme oranı') }) +
      b.istatistikKarti({ ad: 'Bekleyen', deger: b.sayi(d.pendingCount || 0),
        alt: '15 gün olgunlaşma' }) +
      b.istatistikKarti({ ad: 'Kesinleşen', deger: b.sayi(d.qualifiedCount || 0),
        altin: Number(d.qualifiedCount) > 0, alt: 'ödemeye hazır' }) +
      b.istatistikKarti({ ad: 'İptal', deger: b.sayi(d.voidCount || 0),
        alt: 'iade / süre bitti' }) +
      '</section>' +
      // Bu dipnot KARTLARIN YANILTABİLECEĞİ üç noktayı kapatıyor; üçü de
      // ölçülmüş davranış, tahmin değil.
      '<p class="dipnot"><b>Tıklama kişi DEĞİL:</b> sayaç ' +
      '<span class="mono">/r/KOD</span> sayfası açıldığında artar — aynı ' +
      'kişinin iki cihazı iki tıklamadır (sekme içi yenileme sayılmaz). ' +
      'Sayfa <b>noindex</b> taşır ama bu ' +
      'WhatsApp/X önizleme çekicilerini durdurmaz; ping JS ile atıldığı için ' +
      'çoğu önizleyici sayıya girmez, girenler olabilir. ' +
      '<b>Dönüşümün böleni tüm platformları içerir:</b> atıf yalnız Android ' +
      'kurulumlarında yazılıyor (Install Referrer), yani iOS ve masaüstü ' +
      'tıklaması oranı kaçınılmaz olarak düşürür — düşük oran her zaman kötü ' +
      'tanıtım demek değil. Oran <b>%100’ü aşabilir</b> ve bu bozuk veri ' +
      'değildir: Play bağlantısını doğrudan paylaşan ya da tıklaması ' +
      'sayılamamış bir kurulum "kuran"ı artırır, tıklamayı artırmaz — sunucu ' +
      'oranı bilerek kırpmıyor, kırpmak ölçüm boşluğunu gizlemek olurdu. ' +
      // ⚠️ "YAZILMAZ" diyor, "YOK" DEMİYOR ve fark ölçüldü: tarayıcının
      // isteğe kendi eklediği çerez engellenemez (`sendBeacon`'un çerez
      // davranışı kapatılamaz) ve kota kovası isteğin IP'sini BELLEKTE
      // anahtar yapıyor (`core/ratelimit.py`). Panelde "IP yok" yazmak
      // ürünün tutmadığı bir söz olurdu; tutulan söz saklamamak
      // (bekçi: `test_tiklama_kaydinda_KISISEL_VERI_yok`).
      '<b>Kimlik saklanmıyor:</b> tıklama kaydına IP, ' +
      'User-Agent, çerez ya da ziyaretçi kimliği YAZILMAZ — saklanan tek ' +
      'şey gün başına bir sayaç. Sayfa çerez okumuyor; tarayıcının kendi ' +
      'eklediğini de sunucu ne okuyor ne kaydediyor.</p>' +
      // ⚠️ BİRİM UYUMSUZLUĞU BANDI — sayı kartlarının ÜSTÜNDE ve 'hata'.
      // Ölçülen hâl (`partner_service.partner_detail` + `add_payout`):
      // ortağın `payoutCurrency`si ödeme yazıldıktan SONRA değiştirilirse
      // eski kayıtlar uyumsuz olur, `paidTry` onları SAYMAZ ve `balanceTry`
      // olduğundan BÜYÜK çıkar — yani aşağıdaki iki kart ÖDENMİŞ parayı
      // ödenmemiş gösterir. Uç bu sayacı tam bunu işaretlemek için
      // döndürüyordu, panel ise bir tur boyunca hiç göstermiyordu: sessizce
      // yanlış bir bakiye, hiç bakiye göstermemekten kötüdür.
      //
      // Bandın yeri KARTLARDAN ÖNCE, çünkü işi kartları OKUMAYI durdurmak.
      // 'hata' (role="alert") seçildi: bu eksik veri değil, ekranda duran
      // yanlış bir para sayısı ve para ÇIKIŞI da bu hâlde kapalı.
      (od.uyumsuz > 0
        ? b.bant('Bu ortağın ödeme defterinde <b>' + b.sayi(od.uyumsuz) +
          '</b> kayıt, ortağın ödeme biriminden (<b>' + b.e(od.birim || '—') +
          '</b>) farklı bir birimde duruyor. Aşağıdaki <b>Ödenen</b> ve ' +
          '<b>Bakiye</b> o kayıtları SAYMIYOR, yani bakiye olduğundan BÜYÜK ' +
          'görünüyor. Sunucu bu hâlde yeni pozitif ödemeyi de reddediyor ' +
          '(<span class="mono">ledger_currency_mixed</span>). Çıkış yolu: ' +
          'ya birimi eski hâline al, ya uyumsuz kayıtları negatif düzeltme ' +
          'kaydıyla kapat.', 'hata', { html: true })
        : '') +
      // Para — ₺. Atfedilen brüt gelir ($) BİLEREK ayrı kartta: ödülü
      // artık o belirlemiyor ve iki birimi aynı ızgaraya koymak
      // "hakediş brütün yüzdesi" yanılgısını geri getirirdi.
      '<section class="izgara-kpi" aria-label="Hakediş özeti">' +
      b.istatistikKarti({ ad: 'Kesinleşen hakediş', deger: b.para(d.earnedTry, '₺'),
        altin: true, alt: 'abone başına ' + odul(b, p) }) +
      b.istatistikKarti({ ad: 'Beklemede', deger: b.para(d.pendingTry, '₺'),
        alt: 'henüz hak edilmedi' }) +
      // Alt satırda ÖDEME BİRİMİ: kartın kendisi ₺ ile çiziliyor çünkü
      // hakediş tarafı yalnız ₺ üretiyor (`rewardTry`), ama para ÇIKIŞI
      // ortağın biriminde yapılıyor. İkisinin aynı olmadığı bir kayıtta
      // yalnız "₺" görmek, operatöre ödemeyi hangi birimde yazacağını
      // yanlış söylerdi. Birim ölçülmemişse (eski backend) satır hiç yok.
      b.istatistikKarti({ ad: 'Ödenen', deger: b.para(d.paidTry, '₺'),
        alt: od.birim ? 'ödeme birimi ' + od.birim : null }) +
      b.istatistikKarti({ ad: 'Bakiye', deger: b.para(d.balanceTry, '₺'),
        // Karışık defterde `altin` DÜŞÜYOR: altın vurgu "ödenecek para
        // var" diyor ve o sayı orada güvenilmez.
        altin: Number(d.balanceTry) > 0 && !(od.uyumsuz > 0),
        alt: bakiyeAlt(b, d, od) }) +
      '</section>' +
      b.modul('Ödeme ayarları', odemeAyariIc(b, p, od, sahip),
        od.birim ? b.etiket(od.birim) : b.rozet('Bilinmiyor', 'uyari'),
        { alt: 'birim · alt sınır · ödeme kimliği' }) +
      b.modul('Atfedilen gelir (bilgi)',
        '<p class="dipnot">Bu ortağa atfedilen <b>' + b.sayi(d.attributedEvents || 0) +
        '</b> gerçek alım olayından ' + b.para(d.attributedGrossUsd) + ' brüt geldi (iade ' +
        'düşülmüş, test alımları çıkarılmış). Ödülü bu sayı BELİRLEMEZ — ödül kazanılan abone ' +
        'başına sabittir; bu kart yalnız programın getirisini görmek için.</p>') +
      (p.notes ? b.modul('Not', '<p class="dipnot">' + b.e(p.notes) + '</p>') : '') +
      // `izgara-2` DÜŞTÜ: kodlar modülü artık tam bağlantıyı taşıyor ve yarım
      // genişlikte tablo yatay kaydırmaya düşüyordu — kısaltılmış ya da
      // kaydırma ardında kalan bir bağlantı elle kopyalanamaz.
      b.modul('Ödemeler', '<div id="ortak-odemeler"></div>' +
        (sahip ? '<div id="ortak-odeme-form"></div>' : ''),
        b.etiket(b.sayi(odemeler.length) + ' kayıt'),
        // Birim alt metinde: ödeme formu birimi zorunlu tutuyor ve sunucu
        // ortağın biriminden başkasını `currency_mismatch` ile reddediyor,
        // yani operatörün hangi kodu yazacağını modülün başında görmesi
        // gerekiyor. Ölçülmemişse hiç yazılmıyor.
        { alt: 'hakediş ödemesi kaydı — mali işlem, ön-izli' +
          (od.birim ? ' · birim ' + od.birim : '') });

    /* Kodlar tablosu */
    var kodVt = b.veriTablosu({
      // `etiket` tablonun aria-label'ı: görünen başlık "Bağlantı" derken
      // ekran okuyucuya "Kodlar" demek aynı şeyi iki ada bölerdi.
      kimlik: 'ortak-kod-tablo', etiket: 'Ortak bağlantıları', yogunluk: 'sik',
      sutunlar: [
        // Satırın taşıdığı şey artık BAĞLANTI; kod onun sonundaki parça.
        // Kopyala düğmesi aynı hücrede duruyor ki kopyaladığı şeyin yanında
        // olsun — ayrı bir sütun olsaydı yarım genişlikte tablo yatay
        // kaydırmaya düşerdi.
        { ad: 'code', baslik: 'Bağlantı', siralanir: true,
          bicim: function (k) {
            var bag = BAGLANTI_KOKU + k.code;
            return '<div class="ortak-kod-hucre"><b class="mono">' + b.e(k.code) + '</b>' +
              '<button type="button" class="buton ikincil kucuk" data-kopya="' + b.e(bag) +
              '" aria-label="Bağlantıyı kopyala: ' + b.e(k.code) + '">' +
              b.ik('kopyala', 14) + 'Kopyala</button></div>' +
              '<span class="ortak-bag mono">' + b.e(bag) + '</span>';
          } },
        // "Bonus" sütunu KALDIRILDI (K-a): panel hep 0 yolladığı için sütun
        // her satırda 0 gösterip operatöre "ayarlanabilir bir ödül var"
        // izlenimi verirdi. Sıfır dolu bir sütun bilgi değil gürültüdür.
        //
        // Tıklama sütunu KOD BAŞINA gerekiyor: ortağın birden çok kodu
        // olabiliyor (kampanya başına ayrı bağlantı) ve toplam tıklama
        // hangi bağlantının çalıştığını söylemez. `clicks` alanı eski
        // backend'de HİÇ GELMEZ — o durumda '—' çizilir, 0 çizilmez:
        // "ölçüm yok" ile "tıklama yok" aynı şey değil ve ikincisi
        // operatörü bağlantıyı yeniden üretmeye iterdi.
        { ad: 'clicks', baslik: 'Tıklama', hizala: 'sag', siralanir: true,
          // ⚠️ `k.clicks == null` kontrolü `Number()`den ÖNCE olmak zorunda:
          // `Number(null)` 0 döner, yani ölçümü olmayan satır sıralamada
          // "0 tıklama"ymış gibi davranır ve `bicim` '—' derken `deger` 0
          // der — aynı hücre iki farklı şey söylerdi.
          deger: function (k) {
            if (k.clicks == null) return null;
            var v = Number(k.clicks);
            return isFinite(v) ? v : null;
          },
          bicim: function (k) {
            if (k.clicks == null) return '—';
            var v = Number(k.clicks);
            return b.e(isFinite(v) ? b.sayi(v) : '—');
          } },
        // Başlık "Kullanım" değil "Bağlantıyı kullanan": sütun `redemptionCount`
        // okuyor ve o sayaç kurulumdan sonra artıyor. Yukarıdaki KPI kartıyla
        // AYNI kelime olmak zorunda, yoksa iki ekran aynı sayıyı iki ada
        // bölerdi. ⚠️ "Kuran kullanıcı" da YANLIŞTI ve bir tur boyunca öyle
        // durdu: `redemptionCount` TEK satırdan artıyor
        // (`partner_service.py:400`) ve oraya İKİ yol ulaşıyor — kurulum +
        // Install Referrer, VE uygulaması zaten kurulu birinin bağlantıya
        // dokunması (App Links). İkincisinde kurulum HİÇ olmaz; kapalı
        // testte herkeste uygulama kurulu olduğu için oradaki her sayı o
        // yoldan gelir. Tek kelimeye de KISALTILAMAZ: Türkçede o kelime
        // tek başına bambaşka bir şey okunur ve ortağın kendi panosu da tam
        // bu gerekçeyle uzun hâli yazıyor (`web/ortak/ortak.js`,
        // `kodlarTablosu`). Limit gösterimi (`3 / 100`) bozulmuyor —
        // `maxRedemptions` tam bu sayacı sınırlıyor.
        { ad: 'redemptionCount', baslik: 'Bağlantıyı kullanan', hizala: 'sag',
          siralanir: true,
          bicim: function (k) {
            return b.e(b.sayi(k.redemptionCount || 0) + (k.maxRedemptions ? ' / ' + b.sayi(k.maxRedemptions) : ''));
          } },
        { ad: 'expiresAt', baslik: 'Son gün',
          deger: function (k) { var t = b.tarihNesnesi(k.expiresAt); return t ? t.getTime() : null; },
          siralanir: true,
          bicim: function (k) { return '<span class="mono">' + b.e(k.expiresAt ? b.tarih(k.expiresAt) : '—') + '</span>'; } },
        { ad: 'active', baslik: 'Durum', deger: function (k) { return k.active ? 1 : 0; },
          bicim: function (k) {
            var dolu = k.maxRedemptions && Number(k.redemptionCount || 0) >= Number(k.maxRedemptions);
            var t = b.tarihNesnesi(k.expiresAt);
            var gecmis = t && t.getTime() < Date.now();
            if (!k.active) return b.rozet('Pasif', 'notr');
            if (gecmis) return b.rozet('Süresi doldu', 'dolmus');
            if (dolu) return b.rozet('Limit doldu', 'uyari');
            return b.rozet('Aktif', 'aktif');
          } }
      ],
      anahtar: function (k) { return k.code; },
      siralama: { ad: 'code', yon: 'asc' },
      // Eski metin "Kod yok." diyordu: doğru ama eylemsiz. Sahip tam burada
      // "peki nerede üretiyorum" diye takıldı.
      bosMetin: sahip
        ? 'Henüz bağlantı üretilmedi — aşağıdaki "Kod üret" ile oluştur.'
        : 'Henüz bağlantı üretilmedi.'
    });
    icerik.querySelector('#ortak-kodlar').appendChild(kodVt.el);
    kodVt.guncelle(kodlar);

    /* Kopyalama dinleyicisi TABLO KÖKÜNE bağlanır, satırlara DEĞİL: sıralama
       her tıklamada `tbody.innerHTML`'i yeniden kuruyor (bilesenler.js
       `govdeCiz`), yani satıra bağlanan dinleyici ilk sıralamadan sonra
       sessizce ölürdü — düğme durur, tıklama hiçbir şey yapmaz. */
    kodVt.el.addEventListener('click', function (ev) {
      var dugme = ev.target.closest('[data-kopya]');
      if (!dugme) return;
      panoyaKopyala(dugme.getAttribute('data-kopya'), 'Ortak bağlantısı panoya kopyalandı.');
    });

    /* Ödemeler tablosu */
    var odemeVt = b.veriTablosu({
      kimlik: 'ortak-odeme-tablo', etiket: 'Ödemeler', yogunluk: 'sik',
      sutunlar: [
        { ad: 'at', baslik: 'Tarih', siralanir: true,
          deger: function (o) { var t = b.tarihNesnesi(o.at); return t ? t.getTime() : null; },
          bicim: function (o) { return '<span class="mono">' + b.e(b.tarih(o.at, true)) + '</span>'; } },
        // ⚠️ ALANSIZ KAYDIN VARSAYILANI DÜZELTİLDİ (ölçüldü): burada
        // `o.currency || 'USD'` yazıyordu, yani `currency` alanı olmayan
        // ESKİ bir kayıt "$400" diye çiziliyordu. Sunucu tam tersini
        // yapıyor — `partner_detail` alansız kaydı ORTAĞIN birimi sayıyor
        // ("o dönemde tek birim vardı ve varsayılan buydu") ve `paidTry`
        // toplamına öyle katıyor. İki varsayılan ayrışınca aynı ₺400'lük
        // kayıt tabloda $400, toplamda ₺400 görünüyordu; operatörün gözle
        // yaptığı mutabakat tam bu satırda yalan söylüyordu.
        //
        // Yeni varsayılan sunucununkiyle AYNI kaynaktan: `od.birim`
        // (`d.payoutCurrency`). Uç onu da göndermediyse birim BİLİNMİYOR
        // ve tutar birimsiz yazılıyor — uydurulmuş bir simge, eksik bir
        // simgeden kötüdür.
        { ad: 'amount', baslik: 'Tutar', hizala: 'sag', siralanir: true,
          bicim: function (o) {
            var birim = String(o.currency || od.birim || '').toUpperCase();
            var s = simge(birim);
            return b.e(s ? b.para(o.amount, s)
              : b.sayi(o.amount) + ' (birim bilinmiyor)');
          } },
        { ad: 'note', baslik: 'Not', bicim: function (o) { return b.e(o.note || '—'); } }
      ],
      anahtar: function (o) { return o.id || (String(o.at) + '-' + o.amount); },
      siralama: { ad: 'at', yon: 'desc' },
      bosMetin: 'Ödeme kaydı yok.'
    });
    icerik.querySelector('#ortak-odemeler').appendChild(odemeVt.el);
    odemeVt.guncelle(odemeler);

    /* Giriş adresini kopyalama OKUMA işidir — support rolü de görebilir,
       bu yüzden owner kapısının ÜSTÜNDE bağlanıyor. */
    icerik.querySelector('#ortak-pano-kopyala').addEventListener('click', function () {
      panoyaKopyala(ORTAK_PANO_ADRESI, 'Ortak giriş adresi panoya kopyalandı.');
    });

    if (!sahip) return;

    /* Ortak erişimi (claim) aç/kapat. Düğme yalnız uid varken çiziliyor
       (bkz. `erisimIc`), o yüzden burada null kontrolü yeterli. */
    var erisimDugme = icerik.querySelector('#ortak-erisim');
    if (erisimDugme) {
      erisimDugme.addEventListener('click', function () {
        // Bilinmeyen durum AÇMA tarafına düşer: kapatma yıkıcı taraf ve
        // ölçülmemiş bir durumda yıkıcı işlem önerilmez.
        var ac = er.granted !== true;
        b.onayla({
          baslik: ac ? 'Ortak erişimini aç' : 'Ortak erişimini kapat',
          mesaj: ac
            ? (p.name || 'Ortak') + ' adına bağlı hesap ortak panosuna girebilecek.'
            : (p.name || 'Ortak') + ' ortak panosunu artık göremeyecek; kodları, atıfları ve ' +
              'hakedişi DEĞİŞMEZ.',
          aciklama: 'Erişim izni ANINDA geçmez: ortağın oturum jetonu yenilenene ' +
            'kadar (en çok 1 saat, ya da çıkış + yeniden giriş) eski hâl sürer. ' +
            'Denetim izine yazılır.',
          tehlike: !ac,
          onaylaMetin: ac ? 'Erişimi aç' : 'Erişimi kapat'
        }).then(function (r) {
          if (!r) return null;
          return RY.post(yol(id, '/access'), { grant: ac }).then(function () {
            b.toast(ac
              ? 'Erişim açıldı. Ortak, oturum jetonu yenilenene kadar (en çok 1 saat) hâlâ ' +
                'giremeyebilir — çıkıp yeniden girmesi hızlandırır.'
              : 'Erişim kapatıldı. Açık oturumu, jetonu yenilenene kadar (en çok 1 saat) ' +
                'panoyu görmeye devam edebilir.',
              'basari', { sure: 10000 });
            RY.rotaYenile();
          });
        }).catch(erisimHataToast);
      });
    }

    /* Ödül tutarı + hesap bağı */
    icerik.querySelector('#ortak-odul').addEventListener('click', function () {
      var f = b.form({
        alanlar: [
          { ad: 'rewardTry', etiket: 'Ödül (₺)', tur: 'number', zorunlu: true,
            min: 0.01, max: ODUL_TAVANI, adim: '1',
            deger: Number(p.rewardTry) || 30,
            yardim: 'Kazanılan abone başına sabit tutar · tavan ₺' + ODUL_TAVANI,
            dogrula: function (v) {
              return v > 0 && v <= ODUL_TAVANI ? null : '0 ile ' + ODUL_TAVANI + ' arası.';
            } },
          // Aynı şekil kapısı BURADA DA olmak zorunda. Ekleme formu uid'i
          // zorunlu ve şekilli tutuyor, ama bağsız/bozuk bir kayda ulaşan
          // operatör uid'i tam BURADAN giriyor (detaydaki "hata" bandı da
          // buraya yönlendiriyor). Kapı yalnız ekleme formunda olsa, kapıyı
          // atlatan yol ürünün kendi onarım yolu olurdu.
          // `zorunlu` DEĞİL: boş bırakmak "bağı silme" değil "dokunma"
          // demek (aşağıda boş uid gönderilmiyor) ve `dogrula` boş değerde
          // hiç çağrılmıyor — yani ödül tutarını tek başına düzeltmek
          // isteyen operatör uid yazmaya zorlanmıyor.
          { ad: 'uid', etiket: 'Giriş hesabı (kullanıcı kimliği)', max: 128, otomatik: 'off',
            deger: p.uid || '', dogrula: uidDogrula,
            yardim: 'Kendi panosu ve kendi kodunu kullanma kapısı buna bağlı. ' +
              'Nereden: Kullanıcılar → e-posta ile ara → hesabı aç → kimlik ' +
              'kartındaki kullanıcı kimliği.' }
        ],
        gonderMetin: 'Kaydet',
        iptal: { metin: 'Vazgeç', onTikla: function () { m.kapat(); } },
        onGonder: function (v) {
          var govde = { rewardTry: Number(v.rewardTry) };
          // Boş uid GÖNDERİLMEZ — ama gerekçe "bağı silerdi" DEĞİL; o iddia
          // ölçülünce yanlış çıktı. `PartnerPatch.uid` şemada `min_length=1`
          // taşıyor ve `update_partner` boş değeri 400 `uid_required` ile
          // düşürüyor: boş dize bağı silmez, İSTEĞİ düşürür. Ölçülen zarar
          // bu: yalnız ödül tutarını düzeltmek isteyen operatör, uid alanına
          // hiç dokunmadığı hâlde gerekçesiz bir 422 görürdü.
          if (v.uid && String(v.uid).trim()) govde.uid = String(v.uid).trim();
          return RY.patch(yol(id), govde).then(function () {
            b.toast('Ödül güncellendi — yalnız bundan SONRAKİ kazanımlara uygulanır.',
                    'basari', { sure: 7000 });
            m.kapat();
            RY.rotaYenile();
          });
        }
      });
      // ⚠️ Bu not olmadan, tutarı düşüren sahip geçmiş hakedişin de
      // düşeceğini sanır. Tutar hakediş ANINDA `partnerQualifications`
      // dokümanına kopyalanıyor (donduruluyor) — geçmiş DEĞİŞMEZ.
      // `modal` bir `aciklama` seçeneği almıyor; not gövdenin içine girer.
      var kutu = b.el('<div></div>');
      kutu.insertAdjacentHTML('beforeend',
        '<p class="aciklama">Değişiklik yalnız bundan SONRAKİ kazanımlara uygulanır: ' +
        'tutar hakediş anında dondurulur, kesinleşmiş ve bekleyen kayıtlar eski ' +
        'tutarını korur.</p>');
      kutu.appendChild(f.el);
      var m = b.modal({ baslik: 'Ödül ve hesap', icerik: kutu, genislik: 480 });
      m.ac();
    });

    /* Ödeme ayarları: birim + alt sınır.
       Null kontrolü YOK ve gerekmiyor: bu satır `if (!sahip) return`
       kapısının ALTINDA, düğmeyi de `odemeAyariIc` aynı koşulla çiziyor.
       (Yukarıdaki `#ortak-erisim` kontrol ediyor çünkü o düğme AYRICA
       uid'in varlığına bağlı — burada öyle bir ikinci koşul yok.) */
    icerik.querySelector('#ortak-odeme-ayar').addEventListener('click', function () {
      var f2 = b.form({
        alanlar: [
          // ⚠️ Birim ÖLÇÜLMEDİYSE alan PASİF ve gövdeye HİÇ konmuyor
          // (`onGonder`). Uç alanı döndürmediğinde form 'TRY' ile dolu
          // geliyordu ve kaydetmek onu YAZIYORDU: kayıtlı birim TRY değilse
          // o tek tıklama defterdeki ödemeleri uyumsuz yapar, `paidTry`
          // onları saymaz ve sunucu yeni pozitif ödemeyi
          // `ledger_currency_mixed` ile reddeder — ortağın para yolu
          // kapanır. Ölçülmeyeni ekranda göstermemek yetmiyor; YAZMAMAK da
          // gerekiyor.
          { ad: 'payoutCurrency', etiket: 'Ödeme birimi', zorunlu: true, max: 3,
            otomatik: 'off', deger: od.birim || 'TRY',
            pasif: od.birim == null,
            yardim: od.birim == null
              ? 'Uç bu ortağın birimini döndürmedi, yani kayıtta ne yazdığı ' +
                'BİLİNMİYOR — alan bu yüzden kapalı ve kaydetmek onu ' +
                'DEĞİŞTİRMEZ. Sunucu güncellendikten sonra açılır.'
              : '3 harfli kod. Ödeme kayıtları bu birimde yazılır ve ' +
                'sunucu başka birimli kaydı reddeder.',
            dogrula: function (v) {
              return /^[A-Za-z]{3}$/.test(v) ? null : '3 harfli kod (TRY).';
            } },
          // `zorunlu` DEĞİL ve bu ölçülmüş bir ayrım: boş bırakmak
          // "DOKUNMA" demek, 0 girmek "alt sınır YOK" demek. Uç
          // `exclude_none` uyguluyor, yani gönderilmeyen alan değişmiyor —
          // bir kez yazılan eşiği bu uçtan SİLMEK mümkün değil, karşılığı 0.
          // Alanı zorunlu yapmak, yalnız birimi düzeltmek isteyen operatörü
          // eşik yazmaya zorlardı ve o an akılda olmayan bir sayı girilirdi.
          { ad: 'minPayoutTry', etiket: 'Ödeme alt sınırı (₺)', tur: 'number',
            min: 0, max: 100000, adim: '10',
            deger: od.esik == null ? '' : od.esik,
            yertutucu: 'boş = dokunma',
            yardim: 'Anlaşmada yazılı alt sınırın kopyası. 0 = alt sınır yok. ' +
              'Boş bırakırsan mevcut değer DEĞİŞMEZ (bu uçtan silinemez). ' +
              'Sunucu sınırı zorlamıyor — ödemeyi yine elle yazıyorsun.' }
        ],
        gonderMetin: 'Kaydet',
        iptal: { metin: 'Vazgeç', onTikla: function () { m2.kapat(); } },
        onGonder: function (v) {
          var govde = {};
          // Ölçülmemiş birim GÖVDEYE KONMUYOR (alan da pasif) — gerekçesi
          // alan tanımında.
          if (od.birim != null) {
            govde.payoutCurrency = String(v.payoutCurrency).toUpperCase();
          }
          // `!= null` ŞART, `if (v.minPayoutTry)` DEĞİL: 0 anlamlı bir değer
          // ("alt sınır yok") ve doğruluk kontrolü onu sessizce yutardı —
          // operatör eşiği kaldırdığını sanır, hiçbir şey değişmezdi.
          if (v.minPayoutTry != null) {
            govde.minPayoutTry = Number(v.minPayoutTry);
          }
          if (!Object.keys(govde).length) {
            // Boş PATCH sunucuda hiçbir alan yazmaz ama denetim izine bir
            // satır DÜŞER: "değiştirdi" diyen, hiçbir şeyi değiştirmemiş bir
            // kayıt. İz okunabilir kalsın diye istek hiç gitmiyor.
            var bos = new Error('bos-govde');
            bos.detay = 'Değişecek bir alan yok: birim ölçülmediği için ' +
              'yazılmıyor, alt sınır da boş.';
            throw bos;
          }
          // Birimi değiştiren İKİ ayrı tehlike var ve onay metni hangisiyse
          // ONU anlatmak zorunda; biri ötekinin yerine geçmiyor.
          //
          // (1) TRY DIŞINA çıkmak. Hakediş yalnız ₺ üretiyor (`rewardTry`)
          //     ama ödeme defteri ortağın biriminde yazılıyor ve sunucu
          //     ikisini ÇIKARIYOR (`balanceTry = earnedTry − paidTry`).
          //     Uyumsuzluk bandı bu hâlde YANMAZ (kayıtların birimi ortağın
          //     birimine eşit olur), yani ekranda kendiliğinden hiçbir uyarı
          //     olmaz. Kapı defterde kayıt olup olmamasına BAKMIYOR: zarar
          //     bu ayardan SONRA yazılacak ilk kayıtta doğuyor.
          // (2) Ölçülen birimi başka bir birime çevirmek, defterde kayıt
          //     varken: uyumsuz kayıt sayısı değişir, `paidTry` onları
          //     saymaz, bakiye ödenmiş parayı ödenmemiş gösterir ve sunucu
          //     yeni pozitif ödemeyi `ledger_currency_mixed` ile reddeder.
          var hedef = govde.payoutCurrency;
          var degisti = hedef && od.birim && hedef !== od.birim;
          var sor = null;
          if (degisti && hedef !== 'TRY') {
            sor = {
              baslik: 'TRY dışı ödeme birimi',
              mesaj: 'Hakediş yalnız ₺ üretiliyor; ödeme defteri ise ' +
                hedef + ' biriminde yazılacak ve sunucu ikisini birbirinden ' +
                'çıkarıyor. "Ödenen" ve "Bakiye" o andan sonra iki farklı ' +
                'parayı tek sayıda toplar.',
              aciklama: 'Bu hâlde ekranda uyumsuzluk uyarısı ÇIKMAZ (o bant ' +
                'yalnız kayıtların birimi ortağın biriminden farklıysa ' +
                'yanar) ve ortağın panosu da aynı sayıyı gösterir. Ödemeyi ' +
                '₺ olarak kaydedeceksen birimi TRY bırak.',
              onaylaMetin: 'Yine de ' + hedef + ' yap'
            };
          } else if (degisti && odemeler.length) {
            sor = {
              baslik: 'Ödeme birimi değişiyor',
              mesaj: 'Defterde ' + b.sayi(odemeler.length) + ' ödeme kaydı ' +
                'var' + (od.uyumsuz > 0
                  ? ' ve ' + b.sayi(od.uyumsuz) + ' tanesi şimdiden ortağın ' +
                    'biriminden farklı'
                  : ' ve hepsi ' + od.birim + ' biriminde') +
                '. Birimi ' + hedef + ' yapmak uyumsuz kayıt sayısını ' +
                'değiştirir.',
              aciklama: 'Sonuç: "Ödenen" toplamı uyumsuz kayıtları saymaz, ' +
                'bakiye olduğundan büyük görünür ve sunucu yeni pozitif ' +
                'ödemeyi reddeder. Geri dönüş yolu birimi eski hâline ' +
                'almaktır.',
              onaylaMetin: 'Yine de değiştir'
            };
          }
          var onay = sor
            ? b.onayla({ baslik: sor.baslik, mesaj: sor.mesaj,
                         aciklama: sor.aciklama, tehlike: true,
                         onaylaMetin: sor.onaylaMetin })
            : Promise.resolve(true);
          return onay.then(function (r) {
            if (!r) { var h = new Error('iptal'); h.iptal = true; throw h; }
            return RY.patch(yol(id), govde);
          }).then(function () {
            b.toast('Ödeme ayarları güncellendi.', 'basari');
            m2.kapat();
            RY.rotaYenile();
          });
        }
      });
      var kutu2 = b.el('<div></div>');
      kutu2.insertAdjacentHTML('beforeend',
        '<p class="aciklama">Alt sınır ürünün değil bu ortakla yapılan ' +
        'ANLAŞMANIN sayısıdır (tanıtım sayfası böyle diyor) — bu yüzden ' +
        'varsayılanı yok ve girilmediği sürece ortağın panosunda eşikten ' +
        'hiç söz edilmez.</p>');
      kutu2.appendChild(f2.el);
      var m2 = b.modal({ baslik: 'Ödeme ayarları', icerik: kutu2, genislik: 480 });
      m2.ac();
    });

    /* Aktif/pasif */
    icerik.querySelector('#ortak-durum').addEventListener('click', function () {
      b.onayla({
        baslik: pasif ? 'Ortağı aktifleştir' : 'Ortağı pasifleştir',
        mesaj: pasif
          ? (p.name || 'Ortak') + ' yeniden AKTİF olacak.'
          : (p.name || 'Ortak') + ' PASİF olacak — kodları çalışmaya devam eder, listede soluk görünür.',
        tehlike: !pasif, onaylaMetin: pasif ? 'Aktifleştir' : 'Pasifleştir'
      }).then(function (r) {
        if (!r) return;
        return RY.patch(yol(id), { active: pasif }).then(function () {
          b.toast(pasif ? 'Ortak aktifleştirildi.' : 'Ortak pasifleştirildi.', 'basari');
          RY.rotaYenile();
        });
      }).catch(hataToast);
    });

    /* Kod üret */
    var kodForm = b.form({
      alanlar: [
        { ad: 'code', etiket: 'Kod', yertutucu: 'boş = otomatik', max: 24, otomatik: 'off',
          yardim: '4–24 karakter, harf/rakam/_/-; küçük girilse de BÜYÜK saklanır.',
          dogrula: function (v) {
            return /^[A-Za-z0-9_-]{4,24}$/.test(v) ? null : '4–24 karakter; yalnız harf, rakam, _ ve -.';
          } },
        // "Bonus jeton" alanı KALDIRILDI (K-a). Alan kullanıcıya promo jeton
        // yatırıyordu; kilitli ödül modeli ve herkese açık tanıtım sayfası
        // ikisi de "kullanıcı ekstra bir şey almaz" diyor, yani form o iki
        // beyanı yalanlıyordu. Uç alanı hâlâ kabul ediyor (veri modelinde
        // UYUYOR, ölü değil) — panel sıfır dışını üretemiyor sadece.
        // ⚠️ Yeniden açılırsa kod tek başına yetmez: tanıtım sayfası
        // (web/ortaklik.html + web/en/partners.html) ve kullanım şartları da
        // güncellenmek zorunda, yoksa ürün sözünü tutmayan bir ödül doğar.
        { ad: 'maxRedemptions', etiket: 'Kullanım limiti', tur: 'number', min: 1, adim: '1',
          yertutucu: 'sınırsız' },
        { ad: 'expiresAt', etiket: 'Son gün', tur: 'date', yardim: 'Gün sonu UTC; boş = süresiz.' }
      ],
      gonderMetin: 'Kod üret',
      onGonder: function (v) {
        return RY.post(yol(id, '/codes'), {
          code: v.code || null,
          // SABİT 0 (K-a) — formdan gelmiyor, hesaplanmıyor. Alanı hiç
          // yollamamak da olurdu (uç `default=0`), ama açıkça 0 yazmak
          // "burada bilinçli bir sıfır var" diyor; atlanmış bir alan gibi
          // görünmez ve uç varsayılanı ileride değişse panel etkilenmez.
          bonusTokens: 0,
          maxRedemptions: v.maxRedemptions != null ? Math.round(Number(v.maxRedemptions)) : null,
          expiresAt: v.expiresAt || null
        }).then(function (res) {
          var k = (res && res.code) || {};
          b.toast('Kod üretildi: ' + (k.code || '—'), 'basari', { sure: 6000 });
          RY.rotaYenile();
        });
      }
    });
    icerik.querySelector('#ortak-kod-form').appendChild(kodForm.el);

    /* Ödeme işaretle */
    var odemeForm = b.form({
      alanlar: [
        { ad: 'amount', etiket: 'Tutar', tur: 'number', zorunlu: true, adim: '0.01',
          yardim: 'Pozitif = ortağa ödendi · NEGATİF = geri alma (düzeltme, not zorunlu). ' +
            'Sunucu bakiyeden fazla pozitif ödemeyi reddeder.',
          dogrula: function (v) { return Number(v) !== 0 ? null : 'Sıfır olamaz.'; } },
        // ⚠️ Varsayılan artık ORTAĞIN birimi, sabit 'TRY' DEĞİL: sunucu
        // ortağın `payoutCurrency`sinden başkasını `currency_mismatch` ile
        // reddediyor, yani birimi TRY olmayan bir ortakta sabit varsayılan
        // formu kesin başarısızlığa gönderiyordu. Uç birimi döndürmediyse
        // (eski backend) TRY'ye düşülüyor — sistemin varsayılanı o
        // (`partner_service.DEFAULT_PAYOUT_CURRENCY`).
        { ad: 'currency', etiket: 'Para birimi', deger: od.birim || 'TRY',
          zorunlu: true, max: 3, otomatik: 'off',
          yardim: 'Ortağın ödeme birimiyle AYNI olmak zorunda — sunucu ' +
            'farklısını reddeder (' + (od.birim || 'TRY') + ').',
          dogrula: function (v) { return /^[A-Za-z]{3}$/.test(v) ? null : '3 harfli kod (TRY).'; } },
        { ad: 'note', etiket: 'Not', max: 300, yertutucu: 'ör. Eylül hakedişi, havale' }
      ],
      gonderMetin: 'Ödeme işaretle',
      onGonder: function (v) {
        var birim = String(v.currency || 'TRY').toUpperCase();
        var tutar = Number(v.amount);
        var geri = tutar < 0;
        if (geri && !String(v.note || '').trim()) {
          // Sunucu da reddediyor (`reason_required`); burada erken durmak
          // kullanıcıya formu kaybetmeden söyler. Düz `Error` fırlatmak
          // form özetine "Veri alınamadı (…)" sargısıyla düşüyordu — bu bir
          // veri hatası değil, alan hatası.
          odemeForm.hata('note', 'Geri alma kaydı için not zorunlu.');
          return null;
        }
        var yazi = birim === 'TRY' ? b.para(tutar, '₺')
          : (birim === 'USD' ? b.para(tutar) : b.sayi(tutar) + ' ' + birim);
        return b.onayla({
          baslik: geri ? 'Geri alma kaydı' : 'Ödemeyi kaydet',
          mesaj: (p.name || 'Ortak') + ' için ' + yazi +
            (geri ? ' düzeltme kaydı açılacak' : ' ödeme işaretlenecek') +
            (v.note ? ' — "' + v.note + '"' : '') + '.',
          aciklama: 'Mali işlem: ön-izli denetim kaydı düşer; bakiye bu tutar kadar ' +
            (geri ? 'artar' : 'azalır') + '. Geri alma yok.',
          tehlike: geri,
          onaylaMetin: 'Kaydet'
        }).then(function (r) {
          if (!r) { var h = new Error('iptal'); h.iptal = true; throw h; }
          return RY.post(yol(id, '/payouts'), { amount: tutar, currency: birim, note: v.note || '' });
        }).then(function () {
          b.toast('Ödeme kaydedildi.', 'basari');
          RY.rotaYenile();
        });
      }
    });
    icerik.querySelector('#ortak-odeme-form').appendChild(odemeForm.el);
  }

  /* ---------------- Rota ---------------- */

  RY.gorunumler.ortaklar = async function (icerik, args, params, baglam) {
    if (args && args[0]) return detay(icerik, args[0], baglam);
    return liste(icerik, baglam);
  };

  RY.kirintiSaglayici.ortaklar = function (args) {
    var parcalar = [{ metin: 'Yönetim', href: '#/genel' }];
    if (args && args[0]) {
      parcalar.push({ metin: 'Ortaklar', href: '#/ortaklar' });
      parcalar.push({ metin: adOnbellek[args[0]] || 'Ortak' });
    } else parcalar.push({ metin: 'Ortaklar' });
    return parcalar;
  };

  RY.palet.eylemEkle({ ad: 'ortak-yeni', etiket: 'Yeni ortak ekle', aciklama: 'Ortaklık kaydı',
    ikon: 'ortaklar', rol: 'owner', calistir: yeniOrtakAc });
})();

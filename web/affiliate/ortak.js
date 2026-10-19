/* Ortak panosu (OP9) — ortağın KENDİ performansı.
 *
 * Tek uç: GET /api/v1/partners/me. `partnerId` CLAIM'den gelir, istekten
 * DEĞİL — bu yüzden bu sayfada "hangi ortak" diye bir parametre yoktur ve
 * olmamalı; ortak başka bir kimliği isteyip veri çekemez.
 *
 * Dönen görünüm BİLEREK DAR (partner_service.partner_self_view): atfedilen
 * gelir, kullanıcı kimlikleri ve diğer ortaklar YOK. Burada olmayan bir
 * sayıyı türetmeye çalışmak "ölçülmeyen söylenmez" ihlali olurdu — örneğin
 * kod başına limit (`maxRedemptions`) bu görünümde YOK, o yüzden kod
 * durumunda "limit doldu" diye bir hâl gösterilmiyor.
 *
 * HUNİ ÜÇ BASAMAK ve basamakların adı ÖLÇÜLENE göre konuldu:
 * Tıklama → Bağlantıyı kullanan → Abone. Ortadaki basamağın eski adı "Gelen
 * kullanıcı"ydı ve YANLIŞTI. Sayılan şey `referredUsers`, yani kodların
 * `redemptionCount` toplamı; o sayaç `partner_service.redeem` içindeki
 * işlemde artıyor ve o uca (`/api/v1/billing/redeem-code`) yalnız KURULU
 * ve OTURUM AÇMIŞ uygulama istek atıyor (`apps/mobile/lib/core/
 * partner_referrer.dart` — 401 bilerek yeniden denenir, çünkü atıf UID
 * başına yazılıyor). Yani ölçülen "gelen" değil "kurup açan": bağlantıya
 * dokunup vazgeçen kimse bu sayının içinde YOK. Alan ADI `referredUsers`
 * olarak KALIYOR (sözleşme kırılmasın), değişen yalnız EKRAN ETİKETİ.
 *
 * Huninin tepesi (tıklama) olmadan pano ortağa bir şey ÖĞRETMİYORDU:
 * bağlantısını beş yüz kişiye gönderen ortak "3" görüp tanıtımının mı
 * yoksa uygulamanın mı tutmadığını ayırt edemiyordu. Dönüşüm oranı da
 * matematiksel olarak ilk basamak olmadan hesaplanamaz.
 *
 * ⚠️ ALAN YOK ile ALAN SIFIR bu panoda AYNI ŞEY DEĞİL. Tıklama alanları
 * (`clicks`, `clicks30`, `clickSeries`, `conversionRate`) panodan ÖNCE
 * yayına girmiş bir backend'de hiç dönmez; orada "0" yazmak ölçülmemiş
 * bir sayıyı ölçülmüş gibi sunmak olurdu. Yokluk "—" ve açık bir notla
 * gösterilir, sıfırla karıştırılmaz. Pano her iki yanıtla da çizilir.
 *
 * Aynı kural ÖDEME EŞİĞİ için de geçerli ve orada sonucu daha ağır:
 * `minPayoutTry` yalnız o ortağın kaydına GİRİLDİYSE geliyor. Anahtar
 * yokken pano eşikten HİÇ söz etmez — 0 varsaymak "alt sınır yok" diye
 * anlaşmanın söylemediği bir söz vermek, bir sayı uydurmak da olmayan bir
 * kuralı duyurmak olurdu. 0 ise ölçülmüş bir DEĞER: "alt sınır yok".
 *
 * Tıklama ölçümünde KİMLİK YOK: ne IP, ne User-Agent, ne çerez — saklanan
 * tek şey gün başına bir sayaç. Bunun ortak için GÖRÜNÜR sonucu var ve
 * panoda yazılı: aynı kişinin ikinci dokunuşu ayrı sayılır, çünkü tekilleme
 * yapısal olarak İMKÂNSIZ. Yazılmazsa ortak tıklamayı "kişi" sanır.
 *
 * Yönetim panelinin bileşen kitaplığı (bilesenler.js 53 KB) ve admin.css
 * (54 KB) BİLEREK yüklenmiyor; bu pano yedi KPI ve iki tablodan oluşuyor.
 * Ortak olan yalnız kimlik kurulumu (/assets/ry-auth.js) ve API katmanı
 * (/assets/ry-api.js) — o ikisi kopyalanmadı, paylaşıldı.
 *
 * DİL: pano iki dilli (tr/en), seçim `?lang=` → tarayıcı → tr. NEDEN
 * (ölçüldü 2026-10-10): `web/en/partners.html` İngilizce bir ortaklık
 * programı sunup girişin arkasında bir pano VAAT EDİYOR; pano ise yalnız
 * Türkçeydi — dil mantığı sıfır, `toLocaleString('tr-TR')` beş yerde
 * sabit. İngilizce ortak girince Türkçe görüyordu ve hiçbir bekçi kırmızı
 * değildi. Kullanıcıya görünen her dize `SOZLUK`ta; bekçi
 * `backend/tests/test_web_ortak.py`.
 */
(function () {
  'use strict';

  var RY = window.RY = window.RY || {};

  /* Paylaşılabilir bağlantının ana makinesi SABİT: pano
     `rhytoai.web.app`ten açılmış olabilir ama ortağın paylaşacağı adres
     her zaman ürünün genel alan adı olmalı. location.origin kullanmak,
     ortağın sosyal medyaya panelin iç adresini yazmasına yol açardı. */
  var PAYLASIM_TABANI = 'https://rytho.app/r/';

  /* partner_service.MATURATION_DAYS ile aynı sayı; ortağa "neden hemen
     para almıyorum" cevabını burada veriyoruz. */
  var OLGUNLASMA_GUN = 15;

  /* ------------------------------------------------ dil */

  function kayitliDil() {
    try { return window.localStorage.getItem('ry.affiliate.dil'); } catch (h) { return null; }
  }

  /* `web/i/index.html` ile AYNI desen: `?lang=` → `navigator.language` →
     tr. Ortağın kaydında dil alanı YOK (`partner_self_view` taşımıyor), o
     yüzden tek sinyal tarayıcı; `?lang=` elle QA için. Pano hiçbir yerden
     linklenmez, adres ortağa elden verilir — `?lang=` taşıyan bir bağlantı
     EKLENMEZ, parametre yalnız okunur. */
  /* 2026-10-19 (sahip): varsayılan dil İNGİLİZCE — program uluslararası
     ortaklara da açılıyor. Sıra: `?lang=` (QA) → ortağın menüden SEÇTİĞİ
     dil (bu tarayıcıda saklı) → en. Tarayıcı dili artık okunmuyor. */
  var params = new URLSearchParams(window.location.search);
  var lang = (params.get('lang') || kayitliDil() || 'en')
    .toLowerCase().slice(0, 2);
  if (lang !== 'tr') lang = 'en';
  document.documentElement.lang = lang;

  /* Sayı/tarih/yüzde biçimi DİLDEN türer; sabit 'tr-TR' kalmaz (eskiden
     beş yerde sabitti ve İngilizce panoda "1.234,50", "28 Eyl" çıkardı).
     İngilizce için en-GB: tanıtım sayfası (`web/en/partners.html`)
     İngiliz yazımıyla ("programme") yazılı, en-US'nin "Sept 28" sırası o
     sayfayla çelişirdi. Yüzde işaretinin YERİ de buradan geliyor —
     tr-TR "%12,4", en-GB "12.4%" (ölçüldü, Intl.NumberFormat percent). */
  var YEREL = lang === 'en' ? 'en-GB' : 'tr-TR';

  /* Kullanıcıya görünen HER dize burada; iki dilin anahtar kümesi eşit
     (bekçi: backend/tests/test_web_ortak.py). `{ad}` yer tutucularını
     `t()` doldurur; `<b>`/`<i>` taşıyan değerler HTML olarak basılır, o
     yüzden içine giren değer ÇAĞIRAN tarafta `e()`den geçer. Gün sayısı
     ({gun}) sözlükte YAZILMAZ, `OLGUNLASMA_GUN`dan gelir: iki dilde iki
     sayı yazmak, `partner_service.MATURATION_DAYS`in iki kopyası daha
     demek olurdu. */
  var SOZLUK = {
    tr: {
      sayfaBasligi: 'Rytho Ortak Panosu',
      atla: 'İçeriğe atla',
      yokBaslik: 'Bu gökyüzünde böyle bir sayfa yok',
      kokSayfa: 'Ana sayfa',
      panoAdi: 'Ortak panosu',
      eposta: 'E-posta',
      sifre: 'Şifre',
      girisYap: 'Giriş yap',
      yaDa: 'ya da',
      googleIle: 'Google ile devam et',
      sifreUnut: 'Şifreni mi unuttun?',
      yenile: 'Yenile',
      cikis: 'Çıkış',
      girisHatali: 'E-posta ya da şifre hatalı.',
      cokDeneme: 'Çok fazla deneme — biraz bekleyip tekrar dene.',
      gecersizEposta: 'Geçerli bir e-posta gir.',
      girisBasarisiz: 'Giriş başarısız: {kod}',
      onceEposta: 'Önce e-posta alanını doldur.',
      sifirlamaGonderildi: 'E-posta kayıtlıysa sıfırlama bağlantısı ' +
        'gönderildi — spam kutusunu da kontrol et.',
      pencereKapandi: 'Pencere kapandı — tekrar dene.',
      oranAz: '%0,1’den az',
      uyariyiOku: 'aşağıdaki uyarıyı oku',
      odemeBekliyor: 'ödeme bekliyor',
      kapali: 'kapalı',
      altSinirYok: '{durum} · alt sınır yok',
      esikAsildi: 'eşik aşıldı · alt sınır {esik}',
      esigeKaldi: 'eşiğe {kalan} kaldı',
      huniEtiket: 'Huni: tıklamadan aboneye',
      olcumYok: 'henüz ölçüm yok',
      tiklama: 'Tıklama',
      tiklamaAnlam: 'Bağlantına dokunan sayısı — kurulum gerekmez. Kimlik ' +
        'saklanmadığı için tekil kişi sayısı ölçülemez.',
      son30: 'Son 30 gün: {n}.',
      tiklamaKapali: 'Tıklama ölçümü bu panoda henüz açılmadı.',
      oranTiklayan: 'tıklayanın atfı',
      kullanan: 'Bağlantıyı kullanan',
      kullananAnlam: 'Bağlantın bir hesaba yazıldığında sayılır: ya ' +
        'kurulumdan sonra otomatik, ya da uygulaması zaten kurulu biri ' +
        'bağlantına dokunduğunda. Kullanıcı başına bir kez.',
      oranKullanan: 'kullananın abonesi',
      abone: 'Abone',
      aboneAnlam: 'İlk ücretli aboneliğini başlatan sayısı; kazancın ' +
        'yalnız bu basamaktan doğar. İptal olan hakedişler bu sayıda yok.',
      kirilim: 'kesinleşen {kesin} · beklemede {bekleyen}',
      kirilimIptal: ' · iptal {n}',
      dipnotAndroid: 'Atıf yalnız Android kurulumlarında yazılabiliyor ' +
        '(iOS’ta Play Install Referrer dengi yok), yani iPhone ya da ' +
        'bilgisayardan gelen biri uygulamayı kursa bile “Bağlantıyı ' +
        'kullanan” sayısına girmez.',
      dipnotTiklama: 'Tıklama kişi değil: aynı kişinin iki cihazı iki ' +
        'tıklamadır (aynı sekmede yenilemek ikinci kez sayılmaz, tarayıcı ' +
        'depolaması kapalıysa sayılır). {android} Bu yüzden düşük oran ' +
        'her zaman kötü tanıtım demek değil. Oran %100’ü de aşabilir ve ' +
        'bu bozuk veri değil: mağaza bağlantısını doğrudan paylaşan bir ' +
        'kurulum “Bağlantıyı kullanan”ı artırır, tıklamayı artırmaz.',
      seriBos: 'Son {gun} günde tıklama yok.',
      enYuksek: 'en yüksek {gun}: {n}',
      seriCaption: 'Son {gun} günün tıklama sayıları',
      gun: 'Gün',
      seriBaslik: 'Son {gun} gün — tıklama',
      tiklamaToplamTek: '{n} tıklama',
      tiklamaToplam: '{n} tıklama',
      pasif: 'Pasif',
      suresiDoldu: 'Süresi doldu',
      aktif: 'Aktif',
      kodYok: 'Henüz kodun yok — Rytho ekibi açtığında burada görünür.',
      kodlarCaption: 'Kodların ve paylaşılabilir bağlantıları',
      kod: 'Kod',
      sonGun: 'Son gün',
      durum: 'Durum',
      paylasilabilir: 'Paylaşılabilir bağlantı',
      kodBaglantisi: '{kod} kodunun bağlantısı',
      kopyala: 'Kopyala',
      kodlar: 'Kodların',
      kanalDipnot: 'Her kanal için ayrı kod isteyebilirsin: tıklama ve ' +
        'bağlantıyı kullanan sayıları kod başına ayrı tutulduğu için ' +
        'hangi kanalın işe yaradığını yalnız bu tablodan görürsün.',
      kodSayisiTek: '{n} kod',
      kodSayisi: '{n} kod',
      odemeYok: 'Henüz ödeme yapılmadı.',
      odemelerCaption: 'Sana yapılan ödemeler',
      tarihSutun: 'Tarih',
      tutar: 'Tutar',
      notSutun: 'Not',
      bekleyenCumle: 'Bekleyen hakediş, satın almadan {gun} gün sonra ' +
        'kendiliğinden kesinleşir: iade penceresi kapanmadan ödeme ' +
        'yapılmıyor. İade ya da erken sona erme olursa o hakediş iptal ' +
        'olur.',
      odulCumlesi: 'Yeni hakedişlerde abone başına {tutar} — tutar panodan ' +
        'değiştirilemez. Her hakediş satış anındaki tutarı taşır; oran ' +
        'sonradan değişse bile geçmiş yeniden fiyatlanmaz, bu yüzden ' +
        'aşağıdaki toplamlar bu sayının tam katı olmak zorunda değil.',
      odulTanimsiz: 'Ödül tutarı henüz tanımlanmadı.',
      pasifBant: 'Hesabın şu anda <b>pasif</b>: kodların çalışmaya devam ' +
        'eder ama yeni hakediş açılmaz. Kesinleşen bakiyen olduğu gibi ' +
        'durur.',
      odulYokBant: 'Ödül tutarın henüz <b>tanımlanmadı</b>: kodların ' +
        'çalışır ve kullanım sayın artar, ama tutar girilene kadar yeni ' +
        'hakediş açılmaz. Rytho ekibiyle konuşman gerekiyor.',
      hakedis: 'Hakediş',
      kesinlesenHakedis: 'Kesinleşen hakediş',
      toplamKazanc: 'toplam kazanç',
      beklemede: 'Beklemede',
      gunSonraKesinlesir: '{gun} gün sonra kesinleşir',
      odenen: 'Ödenen',
      sanaAktarilan: 'sana aktarılan',
      bakiye: 'Bakiye',
      odemeGecmisi: 'Ödeme geçmişi',
      uyumsuzBant: 'Ödeme defterinde <b>{n}</b> kayıt senin ödeme ' +
        'biriminden ({birim}) farklı bir birimde duruyor. Yukarıdaki ' +
        '<b>Ödenen</b> ve <b>Bakiye</b> o kayıtları saymıyor, yani ' +
        'bakiyen olduğundan büyük görünüyor; bu hâlde yeni ödeme de ' +
        'yapılmıyor. Rytho ekibiyle konuşman gerekiyor.',
      odemeDipnotBas: 'Ödemeler Rytho ekibi tarafından elle kaydedilir; ' +
        'bu panoda bir ödeme takvimi gösterilmiyor. ',
      esikYok: 'Ödeme alt sınırı da burada yazılı değil — anlaşmanızda ' +
        'ne yazıyorsa o geçerli. ',
      esikSifir: 'Ödemen için bir alt sınır yok: kesinleşen bakiyen ne ' +
        'olursa ödenebilir. ',
      esikVar: 'Anlaşmandaki ödeme alt sınırı {esik} — "Bakiye" kartı ' +
        'eşiğe ne kadar kaldığını gösteriyor. Sınırın aşılması ödemeyi ' +
        'kendiliğinden başlatmaz; kaydı ekip elle yazar. ',
      odemeDipnotSon: 'Kesinleşen bakiyen için Rytho ekibiyle yazışırsın.',
      odemeBirimi: 'ödeme para birimi {birim}',
      odulNasil: 'Ödül nasıl işliyor',
      odulP1: 'Getirdiğin kullanıcının <b>ilk ücretli aboneliği</b> için ' +
        'sabit bir ₺ tutar kazanırsın. Kullanıcı için indirim ya da ödül ' +
        'yoktur — bağlantıya dokunması yeter, kod yazmasına gerek kalmaz.',
      odulP2: 'Deneme <i>başlatmak</i> ödül üretmez; deneme ücretli ' +
        'aboneliğe dönerse üretir. Yenileme, kredi paketi ve mağaza test ' +
        'alımları ödül üretmez. Kullanıcı başına en fazla bir hakediş ' +
        'açılır.',
      odulP3: 'Kendi kodunu kendi hesabında kullanamazsın.',
      panoYuklendi: 'Pano yüklendi',
      panoYukleniyor: 'Pano yükleniyor',
      gecici: 'Pano şu an ulaşılamıyor. Bu geçici bir durum: oturumun ' +
        'açık, kodların ve hakedişlerin olduğu gibi duruyor.',
      tekrarDene: 'Tekrar dene',
      kopyalandi: 'Bağlantı kopyalandı.',
      kopyalanamadi: 'Kopyalanamadı — bağlantı seçildi, Ctrl+C ile ' +
        'kopyalayabilirsin.',
      kimlikAg: 'Kimliğin doğrulanması için ağ bağlantısı gerekiyor — ' +
        'bağlantını kontrol edip tekrar dene.',
      bilinmeyenHata: 'Bilinmeyen hata.',
      agHatasi: 'Bağlantı kurulamadı — ağını kontrol edip tekrar dene.',
      istekSiniri: 'İstek sınırı aşıldı — {sn} sn sonra tekrar dene.',
      sunucuHatasi: 'Sunucu hatası — birazdan tekrar dene.',
      veriAlinamadi: 'Veri alınamadı ({sebep}).'
    },
    en: {
      sayfaBasligi: 'Rytho Affiliate Panel',
      atla: 'Skip to content',
      yokBaslik: 'There is no such page in this sky',
      kokSayfa: 'Home',
      panoAdi: 'Affiliate panel',
      eposta: 'Email',
      sifre: 'Password',
      girisYap: 'Sign in',
      yaDa: 'or',
      googleIle: 'Continue with Google',
      sifreUnut: 'Forgot your password?',
      yenile: 'Refresh',
      cikis: 'Sign out',
      girisHatali: 'Email or password is incorrect.',
      cokDeneme: 'Too many attempts — wait a moment and try again.',
      gecersizEposta: 'Enter a valid email address.',
      girisBasarisiz: 'Sign-in failed: {kod}',
      onceEposta: 'Fill in the email field first.',
      sifirlamaGonderildi: 'If the email is registered, a reset link has ' +
        'been sent — check your spam folder too.',
      pencereKapandi: 'The window was closed — try again.',
      oranAz: 'under 0.1%',
      uyariyiOku: 'read the notice below',
      odemeBekliyor: 'awaiting payout',
      kapali: 'nothing due',
      altSinirYok: '{durum} · no minimum',
      esikAsildi: 'threshold reached · minimum {esik}',
      esigeKaldi: '{kalan} to the threshold',
      huniEtiket: 'Funnel: from click to subscriber',
      olcumYok: 'not measured yet',
      tiklama: 'Clicks',
      tiklamaAnlam: 'Number of taps on your link — no install needed. No ' +
        'identity is stored, so unique people cannot be counted.',
      son30: 'Last 30 days: {n}.',
      tiklamaKapali: 'Click measurement is not enabled on this panel yet.',
      oranTiklayan: 'clicks attributed',
      kullanan: 'Used the link',
      kullananAnlam: 'Counted when your link is written onto an account: ' +
        'either automatically after an install, or when someone who ' +
        'already has the app taps your link. Once per user.',
      oranKullanan: 'users who subscribed',
      abone: 'Subscribers',
      aboneAnlam: 'Number who started their first paid subscription; your ' +
        'earnings come only from this step. Voided claims are not in ' +
        'this number.',
      kirilim: 'settled {kesin} · pending {bekleyen}',
      kirilimIptal: ' · void {n}',
      dipnotAndroid: 'Attribution can only be written on Android installs ' +
        '(iOS has no equivalent of the Play Install Referrer), so someone ' +
        'coming from an iPhone or a computer does not enter the “Used ' +
        'the link” count even if they install the app.',
      dipnotTiklama: 'A click is not a person: one person on two devices ' +
        'is two clicks (refreshing in the same tab does not count twice; ' +
        'it does if browser storage is off). {android} So a low rate does ' +
        'not always mean poor promotion. The rate can also exceed 100% ' +
        'and that is not broken data: an install from a directly shared ' +
        'store link raises “Used the link” without raising clicks.',
      seriBos: 'No clicks in the last {gun} days.',
      enYuksek: 'peak {gun}: {n}',
      seriCaption: 'Click counts for the last {gun} days',
      gun: 'Day',
      seriBaslik: 'Last {gun} days — clicks',
      tiklamaToplamTek: '{n} click',
      tiklamaToplam: '{n} clicks',
      pasif: 'Inactive',
      suresiDoldu: 'Expired',
      aktif: 'Active',
      kodYok: 'You have no codes yet — they appear here once the Rytho ' +
        'team creates them.',
      kodlarCaption: 'Your codes and their shareable links',
      kod: 'Code',
      sonGun: 'Expires',
      durum: 'Status',
      paylasilabilir: 'Shareable link',
      kodBaglantisi: 'Link for code {kod}',
      kopyala: 'Copy',
      kodlar: 'Your codes',
      kanalDipnot: 'You can ask for a separate code per channel: clicks ' +
        'and link uses are kept per code, so this table is the only ' +
        'place that shows which channel works.',
      kodSayisiTek: '{n} code',
      kodSayisi: '{n} codes',
      odemeYok: 'No payouts yet.',
      odemelerCaption: 'Payouts made to you',
      tarihSutun: 'Date',
      tutar: 'Amount',
      notSutun: 'Note',
      bekleyenCumle: 'A pending claim settles on its own {gun} days after ' +
        'the purchase: nothing is paid before the refund window closes. ' +
        'A refund or an early end voids that claim.',
      odulCumlesi: '{tutar} per subscriber on new claims — the amount ' +
        'cannot be changed from this panel. Each claim carries the amount ' +
        'at the time of sale; if the rate changes later, history is not ' +
        're-priced, so the totals below need not be exact multiples of ' +
        'this number.',
      odulTanimsiz: 'The reward amount has not been set yet.',
      pasifBant: 'Your account is currently <b>inactive</b>: your codes ' +
        'keep working but no new claim opens. Your settled balance stays ' +
        'as it is.',
      odulYokBant: 'Your reward amount is <b>not set</b> yet: your codes ' +
        'work and your usage count grows, but no new claim opens until ' +
        'the amount is entered. You need to talk to the Rytho team.',
      hakedis: 'Claims',
      kesinlesenHakedis: 'Settled claims',
      toplamKazanc: 'total earnings',
      beklemede: 'Pending',
      gunSonraKesinlesir: 'settles after {gun} days',
      odenen: 'Paid',
      sanaAktarilan: 'transferred to you',
      bakiye: 'Balance',
      odemeGecmisi: 'Payout history',
      uyumsuzBant: '<b>{n}</b> entries in the payout ledger are in a ' +
        'currency other than your payout currency ({birim}). <b>Paid</b> ' +
        'and <b>Balance</b> above do not count them, so your balance looks ' +
        'larger than it is; no new payout is made in this state. You need ' +
        'to talk to the Rytho team.',
      odemeDipnotBas: 'Payouts are recorded by hand by the Rytho team; ' +
        'this panel shows no payout schedule. ',
      esikYok: 'The payout minimum is not written here either — whatever ' +
        'your agreement says applies. ',
      esikSifir: 'There is no minimum for your payout: whatever your ' +
        'settled balance is, it can be paid. ',
      esikVar: 'The payout minimum in your agreement is {esik} — the ' +
        '"Balance" card shows how far you are from it. Reaching it does ' +
        'not start a payout by itself; the team records it by hand. ',
      odemeDipnotSon: 'For your settled balance, you correspond with the ' +
        'Rytho team.',
      odemeBirimi: 'payout currency {birim}',
      odulNasil: 'How the reward works',
      odulP1: 'You earn a fixed ₺ amount for the <b>first paid ' +
        'subscription</b> of a user you bring. There is no discount or ' +
        'reward for the user — tapping the link is enough, they never ' +
        'type a code.',
      odulP2: '<i>Starting</i> a trial earns nothing; a trial converting ' +
        'to a paid subscription does. Renewals, credit packs and store ' +
        'test purchases earn nothing. At most one claim opens per user.',
      odulP3: 'You cannot use your own code on your own account.',
      panoYuklendi: 'Panel loaded',
      panoYukleniyor: 'Panel loading',
      gecici: 'The panel cannot be reached right now. This is temporary: ' +
        'you are still signed in, and your codes and claims are untouched.',
      tekrarDene: 'Try again',
      kopyalandi: 'Link copied.',
      kopyalanamadi: 'Could not copy — the link is selected, you can copy ' +
        'it with Ctrl+C.',
      kimlikAg: 'Verifying your identity needs a network connection — ' +
        'check your connection and try again.',
      bilinmeyenHata: 'Unknown error.',
      agHatasi: 'Could not connect — check your network and try again.',
      istekSiniri: 'Request limit reached — try again in {sn} s.',
      sunucuHatasi: 'Server error — try again shortly.',
      veriAlinamadi: 'Could not load data ({sebep}).'
    }
  };
  var T = SOZLUK[lang];

  function t(anahtar, degerler) {
    var sablon = T[anahtar];
    /* Eksik anahtar ekranda ANAHTAR ADIYLA görünür, "undefined" ya da boş
       olarak değil: boş kalan bir etiket fark edilmez, anahtar adı fark
       edilir. Asıl kapı bekçi (anahtar kümeleri eşit); bu son perde. */
    if (sablon == null) return anahtar;
    if (!degerler) return sablon;
    return sablon.replace(/\{(\w+)\}/g, function (hepsi, ad) {
      return degerler[ad] != null ? String(degerler[ad]) : hepsi;
    });
  }

  /* İngilizce tekil/çoğul ("1 codes" yazmamak için). Türkçede sayıdan
     sonra çoğul eki gelmez, iki anahtar aynı metni taşır. */
  function cogul(n, tekAnahtar, cokAnahtar) {
    return t(Number(n) === 1 ? tekAnahtar : cokAnahtar, { n: sayi(n) });
  }

  /* HTML'deki sabit metinler: `data-i18n` → textContent,
     `data-i18n-placeholder` → placeholder. <title> da bu yoldan dolar;
     HTML'deki Türkçe, JS çalışmadan önceki tek kare. */
  Array.prototype.forEach.call(document.querySelectorAll('[data-i18n]'),
    function (el) { el.textContent = t(el.getAttribute('data-i18n')); });
  Array.prototype.forEach.call(
    document.querySelectorAll('[data-i18n-placeholder]'), function (el) {
      el.setAttribute('placeholder',
        t(el.getAttribute('data-i18n-placeholder')));
    });

  /* Hata → cümle, bu panonun DİLİNDE. `RY.hataMetni` (ry-api.js) yönetim
     paneliyle paylaşılan modül ve Türkçe sabit (panel TR); buradan
     çağırmak İngilizce panoya Türkçe bant basardı. Harita bilerek dar:
     yalnız bu sayfanın ekrana taşıdığı hâller (ağ, 429, sunucunun
     `detail`i olduğu gibi, 5xx, kalan). ry-api.js'in KENDİ bastığı 429
     toast'ı da bu haritadan geçer: modül RY.hataMetni'yi (varsa) kullanır,
     aşağıda kaydediliyor — yoksa İngilizce panoya Türkçe toast düşerdi. */
  function hataMetni(hata) {
    if (!hata) return T.bilinmeyenHata;
    if (hata.message === 'ag-hatasi') return T.agHatasi;
    if (hata.durum === 429) {
      return t('istekSiniri', { sn: hata.retryAfter || 60 });
    }
    if (hata.detay) return hata.detay;
    if (hata.durum >= 500) return T.sunucuHatasi;
    return t('veriAlinamadi', { sebep: hata.message || hata });
  }

  /* ------------------------------------------------ küçük yardımcılar */

  function e(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function sayi(v) {
    var n = Number(v);
    if (v == null || !isFinite(n)) return '—';
    return n.toLocaleString(YEREL);
  }

  /* Para birimi kodu → simge. Bilinmeyen kod OLDUĞU GİBİ yazılır: ₺
     varsaymak, ödemesi başka birimde yapılan ortağa yanlış birim
     göstermek olurdu. */
  function simge(kod) {
    var k = String(kod || 'TRY').toUpperCase();
    if (k === 'TRY') return '₺';
    if (k === 'USD') return '$';
    if (k === 'EUR') return '€';
    return k + ' ';
  }

  function para(v, birim) {
    var n = Number(v);
    if (v == null || !isFinite(n)) return '—';
    return (birim || '₺') + n.toLocaleString(YEREL,
      { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  /* Firestore zaman değeri ISO dizge, {seconds}, {_seconds}, ms sayı ya da
     Date gelebilir (bilesenler.js'teki aynı gerekçe) → Date ya da null. */
  function tarihNesnesi(v) {
    if (!v) return null;
    var d;
    if (v instanceof Date) d = v;
    else if (typeof v === 'string' || typeof v === 'number') d = new Date(v);
    else if (v.seconds != null) d = new Date(v.seconds * 1000);
    else if (v._seconds != null) d = new Date(v._seconds * 1000);
    else if (typeof v.toDate === 'function') d = v.toDate();
    else d = new Date(v);
    return isNaN(d.getTime()) ? null : d;
  }

  function tarih(v) {
    var d = tarihNesnesi(v);
    if (!d) return '—';
    return d.toLocaleDateString(YEREL,
      { day: 'numeric', month: 'short', year: 'numeric' });
  }

  /* "Bu alan ÖLÇÜLDÜ mü" kapısı. `d.clicks || 0` yazmak kısa olurdu ama
     eski backend'in hiç göndermediği alanı sıfıra çevirirdi — dosya
     başındaki "alan yok ≠ alan sıfır" kuralının tek uygulama noktası
     burası. Sıfır ölçülmüş bir sonuçtur ve öyle gösterilir. */
  function olculdu(v) {
    return v != null && v !== '' && isFinite(Number(v));
  }

  /* Oran 0..1 arası bir kesir olarak gelir (sözleşme: kuran / tıklama) →
     "%12,4". `null` dönmesi "oran YOK" demektir ve çağıran onu "henüz
     ölçüm yok" diye yazar; "%0" YAZILMAZ çünkü bölen sıfırken oran
     tanımsızdır, sıfır değil.

     Sıfıra yuvarlanan ama sıfır OLMAYAN oran ayrı yazılıyor: 500 tıklamada
     1 kuran %0,2'dir ve "%0" göstermek ölçülen bir dönüşümü yok saymak
     olurdu. */
  function oranMetni(oran) {
    var n = Number(oran);
    if (oran == null || !isFinite(n) || n < 0) return null;
    if (n > 0 && n < 0.001) return T.oranAz;
    /* İşaretin YERİ dile bağlı (tr "%12,4", en "12.4%"); "%" + sayı diye
       elle kurmak İngilizce panoda işareti yanlış tarafa koyardı. */
    return new Intl.NumberFormat(YEREL,
      { style: 'percent', maximumFractionDigits: 1 }).format(n);
  }

  /* 'YYYY-MM-DD' → '28 Eyl'.
     ⚠️ `new Date('2026-09-28')` ISO tarih dizgesini UTC GECE YARISI sayar;
     negatif ofsetli bir saat diliminde (ortak yurt dışındaysa) yerel gün
     BİR GERİ kayar ve çubuğun etiketi yanlış günü gösterir. Sunucu bu
     dizgeyi doküman kimliği olarak yazıyor, yani o bir ETİKET; saat
     dilimine çevrilecek bir an değil. Bileşenleri elle ayırıp YEREL bir
     Date kurmak kaymayı kapatıyor. */
  function gunEtiketi(gun) {
    var p = String(gun || '').split('-');
    if (p.length !== 3) return String(gun || '—');
    var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
    if (isNaN(d.getTime())) return String(gun);
    return d.toLocaleDateString(YEREL, { day: 'numeric', month: 'short' });
  }

  function $(id) { return document.getElementById(id); }

  function goster(id) {
    ['bulunamadi', 'giris', 'pano'].forEach(function (ad) {
      $(ad).hidden = ad !== id;
    });
    /* "İçeriğe atla" hedefi pano gövdesi: pano kapalıyken bağlantı da
       kapanır, yoksa klavye kullanıcısı gizli bir öğeye atlar. */
    $('atla-bag').hidden = id !== 'pano';
  }

  function duyur(metin) { $('duyuru').textContent = metin || ''; }

  /* Küçük toast kabı. ry-api.js 429'da RY.toast'ı arıyor (orada bu kanca
     yorumlanmış); kanca olmasa istek sınırı uyarısı sessizce yutulurdu. */
  function toast(metin, tur) {
    if (!metin) return;
    var kap = $('toast-kap');
    var kutu = document.createElement('div');
    kutu.className = 'toast ' + (tur || 'bilgi');
    kutu.textContent = metin;
    kap.appendChild(kutu);
    setTimeout(function () { if (kutu.parentNode) kutu.remove(); }, 5000);
  }
  RY.toast = toast;
  // ry-api.js'in 429 toast'ı için dil bilen harita (bkz. hataMetni yorumu).
  RY.hataMetni = hataMetni;

  /* ------------------------------------------------ kimlik */

  /* Kurulum ORTAK modülde (authDomain onarımı + App Check örnek başına);
     ikinci örneğin adı burada 'ortak'. */
  var auth = RY_authKur('ortak');
  RY.auth = auth;   /* ry-api.js jetonu buradan okur */

  /* Claim'i olmayan ya da ortak kaydı silinmiş kullanıcıya "yetkin yok"
     DENMEZ; yönetim panelindeki sahte-404 deseni.

     ⚠️ Bu desen sayfanın VARLIĞINI gizlemez, öyle sanmak yanlış gerekçe
     olurdu: aynı adreste çıkış yapan biri "Ortak panosu" başlıklı giriş
     kartını görür ve <title> zaten "Rytho Ortak Panosu" diyor. Gizlediği
     tek şey, giriş yapmış BU hesabın ortak erişimi olup olmadığı —
     hesap sayımı (enumeration) kapısı, sayfa gizliliği değil.

     ⚠️ KİLİT ŞART: `signOut()` ASENKRONDUR ve bitince `onAuthStateChanged`
     null ile tekrar ateşlenir. Kilitsiz hâli yerel sahnede ölçüldü —
     jenerik ekran bir an sonra GİRİŞ KARTIYLA değişiyordu ve kart
     "Ortak panosu" yazdığı için tam da gizlemek istediğimiz şeyi ele
     veriyordu. Kilit yalnız sayfa yeniden yüklenince açılır. */
  var jenerikKilit = false;

  RY.yetkisiz = function () {
    jenerikKilit = true;
    auth.signOut().catch(function () {});
    goster('bulunamadi');
  };

  function girisHatasi(metin) {
    var kutu = $('giris-hata');
    kutu.textContent = metin || '';
    kutu.hidden = !metin;
    if (metin) girisBilgi('');
  }
  function girisBilgi(metin) {
    var kutu = $('giris-bilgi');
    kutu.textContent = metin || '';
    kutu.hidden = !metin;
  }

  /* Hata metinleri hesap varlığını ELE VERMEZ (panel ve mobilin aynı
     anti-enumeration duruşu): "kullanıcı yok" ile "şifre yanlış" tek
     cümleye iner. */
  $('eposta-form').addEventListener('submit', function (ev) {
    ev.preventDefault();
    girisHatasi('');
    var f = ev.target;
    var dugme = f.querySelector('button');
    dugme.disabled = true;
    auth.signInWithEmailAndPassword(f.email.value.trim(), f.password.value)
      .catch(function (hata) {
        var kod = (hata && hata.code) || '';
        if (kod === 'auth/wrong-password' || kod === 'auth/user-not-found' ||
            kod === 'auth/invalid-credential' ||
            kod === 'auth/invalid-login-credentials') {
          girisHatasi(T.girisHatali);
        } else if (kod === 'auth/too-many-requests') {
          girisHatasi(T.cokDeneme);
        } else if (kod === 'auth/invalid-email') {
          girisHatasi(T.gecersizEposta);
        } else {
          girisHatasi(t('girisBasarisiz', { kod: kod || hata }));
        }
      })
      .then(function () { dugme.disabled = false; });
  });

  /* Şifre sıfırlama: sonuç her durumda AYNI metin (hesap varlığı sızmaz). */
  $('sifre-unut').addEventListener('click', function () {
    girisHatasi('');
    var eposta = $('giris-eposta').value.trim();
    if (!eposta) { girisHatasi(T.onceEposta); return; }
    auth.sendPasswordResetEmail(eposta).catch(function () {})
      .then(function () { girisBilgi(T.sifirlamaGonderildi); });
  });

  $('google-gir').addEventListener('click', function () {
    girisHatasi('');
    var saglayici = new firebase.auth.GoogleAuthProvider();
    auth.signInWithPopup(saglayici).catch(function (hata) {
      var kod = (hata && hata.code) || '';
      if (kod === 'auth/popup-blocked') {
        auth.signInWithRedirect(saglayici);
        return;
      }
      if (kod === 'auth/popup-closed-by-user' ||
          kod === 'auth/cancelled-popup-request') {
        girisHatasi(T.pencereKapandi);
        return;
      }
      girisHatasi(t('girisBasarisiz', { kod: kod || hata }));
    });
  });

  auth.getRedirectResult().catch(function (hata) {
    girisHatasi(t('girisBasarisiz', { kod: (hata && hata.code) || hata }));
  });

  $('cikis').addEventListener('click', function () {
    auth.signOut().then(function () { goster('giris'); });
  });

  /* ------------------------------------------------ çizim */

  function kpi(ad, deger, alt, altin) {
    return '<div class="kpi' + (altin ? ' altin' : '') + '">' +
      '<span class="ad">' + e(ad) + '</span>' +
      '<span class="deger">' + e(deger) + '</span>' +
      (alt ? '<span class="alt">' + e(alt) + '</span>' : '') +
      '</div>';
  }

  /* "Bakiye" kartının alt satırı.

     ÖDEME EŞİĞİ (`minPayoutTry`) artık bu panoya geliyor ve ÜÇ HÂLLİ; üçü
     ayrı şey ve üçü ayrı yazılıyor:
       · anahtar YOK  → anlaşmadaki alt sınır panele hiç girilmemiş. Pano
         eşikten HİÇ söz etmez. Bir sayı (0 dâhil) uydurmak, olmayan bir
         kuralı ortağa duyurmak olurdu.
       · 0            → alt sınır yok, kesinleşen her tutar ödenebilir.
       · >0           → eşik; kalan tutar yazılır.

     SIRA: birim uyumsuzluğu her şeyi geçiyor. O hâlde `balanceTry` ödenmiş
     parayı ödenmemiş gösteriyor (`partner_service.partner_detail` yorumu),
     yani "eşiğe ₺X kaldı" ekrana İKİNCİ bir yanlış sayı koymak olurdu.
     Ayrıntı ödeme geçmişindeki bantta duruyor; kart yalnız oraya
     yönlendiriyor (aynı uyarıyı iki yerde yazmak okunmaz yapar).

     `esik == null` kapısı `Number()`den ÖNCE: `Number(undefined)` NaN,
     `Number(null)` ise 0 — ikincisi girilmemiş bir eşiği "alt sınır yok"
     diye BEYAN ederdi. */
  function bakiyeAlt(d, uyumsuz) {
    if (uyumsuz > 0) return T.uyariyiOku;
    var bakiye = Number(d.balanceTry);
    var durum = isFinite(bakiye) && bakiye > 0 ? T.odemeBekliyor : T.kapali;
    if (!olculdu(d.minPayoutTry)) return durum;
    var esik = Number(d.minPayoutTry);
    if (esik === 0) return t('altSinirYok', { durum: durum });
    if (!isFinite(bakiye)) return durum;
    if (bakiye >= esik) return t('esikAsildi', { esik: para(esik, '₺') });
    return t('esigeKaldi', { kalan: para(esik - bakiye, '₺') });
  }

  /* Yan menü pano İÇERİĞİNDEN kurulur: her `section` başlığı (h2) bir
     bağlantı. NEDEN elle liste değil: bölümler veriye göre çizilip
     çizilmiyor (ör. tıklama serisi yoksa modül hiç yok) — elle yazılmış bir
     menü olmayan bölüme götürürdü. Sahip: "belge açmışım gibi, ne menü var
     ne profesyonel görünüm" (2026-10-19). */
  function menuKur() {
    var menu = $('pano-menu');
    if (!menu) return;
    menu.setAttribute('aria-label', T.panoAdi);
    var basliklar = $('pano-govde').querySelectorAll('section h2');
    var html = '';
    Array.prototype.forEach.call(basliklar, function (h, i) {
      var bolum = h.closest('section');
      if (!bolum) return;
      bolum.id = 'bolum-' + (i + 1);
      html += '<a href="#' + bolum.id + '">' + e(h.textContent) + '</a>';
    });
    menu.innerHTML = html;
  }

  /* Dil düğmeleri: seçim bu tarayıcıda saklanır ve sayfa yeniden açılır
     (bütün metinler açılışta SOZLUK'tan dolduruluyor). Adrese `lang=`
     YAZILMAZ — pano linklenmez, parametre yalnız okunur. */
  Array.prototype.forEach.call(document.querySelectorAll('[data-dil]'), function (b) {
    b.setAttribute('aria-pressed', b.getAttribute('data-dil') === lang ? 'true' : 'false');
    b.addEventListener('click', function () {
      try { window.localStorage.setItem('ry.affiliate.dil', b.getAttribute('data-dil')); } catch (h) { /* gizli pencere */ }
      window.location.replace(window.location.pathname);
    });
  });

  function modul(baslik, ic, alt) {
    return '<section class="modul">' +
      '<div class="bas"><h2>' + e(baslik) + '</h2>' +
      (alt ? '<span class="alt">' + e(alt) + '</span>' : '') + '</div>' +
      '<div class="ic">' + ic + '</div></section>';
  }

  /* ------------------------------------------------ huni */

  /* Bir basamak. `anlam` ZORUNLU tutuluyor (imzada opsiyonel değil):
     "Tıklama 500 / kullanan 3" satırını açıklamasız gören ortak ikisini aynı
     şeyin iki ölçümü sanıp panoyu bozuk sanıyor. Basamağın ne SAYDIĞINI
     yazmak sayının kendisi kadar veri. */
  function huniAdim(no, ad, deger, anlam, kirilim, not, altin) {
    return '<div class="huni-adim' + (altin ? ' altin' : '') + '">' +
      '<span class="bas"><span class="no" aria-hidden="true">' + e(no) +
      '</span><span class="ad">' + e(ad) + '</span></span>' +
      '<span class="deger">' + e(deger) + '</span>' +
      (kirilim ? '<span class="kirilim">' + e(kirilim) + '</span>' : '') +
      '<span class="anlam">' + e(anlam) + '</span>' +
      (not ? '<span class="not">' + e(not) + '</span>' : '') +
      '</div>';
  }

  /* İki basamak ARASINDAKİ oran. Ok yalnız SÜSTÜR (`aria-hidden`) —
     ekran okuyucuya "sağ ok" okutmak bilgi değil gürültü; oranın hangi
     ikiliye ait olduğunu `etiket` söylüyor ve o okunuyor. */
  function huniOran(etiket, oran) {
    var metin = oranMetni(oran);
    return '<div class="huni-oran">' +
      '<span class="ok" aria-hidden="true">→</span>' +
      '<span class="etiket">' + e(etiket) + '</span>' +
      (metin ? '<span class="oran">' + e(metin) + '</span>'
             : '<span class="yok">' + e(T.olcumYok) + '</span>') +
      '</div>';
  }

  function huniBolumu(d) {
    var tiklamaVar = olculdu(d.clicks);
    var tiklama = tiklamaVar ? Number(d.clicks) : 0;
    /* `referredUsers`/`pendingCount`/`qualifiedCount` ESKİ sözleşmenin
       alanları: her zaman geliyorlar, yokluğu bozuk yanıt demek. Bu yüzden
       burada `olculdu` kapısı YOK — kapıyı yeni alanlara koymanın nedeni
       tam olarak eski ve yeni yanıtı ayırmak. */
    var kuran = Number(d.referredUsers || 0);
    var bekleyen = Number(d.pendingCount || 0);
    var kesinlesen = Number(d.qualifiedCount || 0);
    var dusen = Number(d.voidCount || 0);
    var abone = bekleyen + kesinlesen;

    /* Sunucunun hükmü ÖNCE gelir (`conversionRate`). Yerel hesap yalnız
       alanın hiç gelmediği hâl için ve AYNI iki sayıdan türetiliyor, yani
       ikinci bir gerçek kaynak değil — panoda çelişen iki oran çıkmaz. */
    var oran1 = olculdu(d.conversionRate) ? Number(d.conversionRate)
      : (tiklama > 0 ? kuran / tiklama : null);

    /* İkinci oran sunucudan GELMİYOR ve gelmesi gerekmiyor: iki operandı
       da bu yanıtta ölçülü, yani burada yapılan şey aritmetik — yeni bir
       iddia değil. Bölen 0 ise oran YOK. */
    var oran2 = kuran > 0 ? abone / kuran : null;

    /* ⚠️ Burada "aynı kişinin ikinci dokunuşu ayrı sayılır" YAZIYORDU ve
       ölçümle ÇELİŞİYORDU: `web/r/index.html` ping'i `sessionStorage`da kod
       başına bir bayrak tutuyor, yani AYNI SEKMEDE yenileme ikinci kez
       SAYILMAZ (dedup yalnız depolamaya erişilemezse — gizli sekme, site
       verisi kapalı — devre dışı kalıyor). Yönetim paneli aynı olguyu doğru
       yazıyordu ("sekme içi yenileme sayılmaz"); iki ekran aynı sayıyı iki
       farklı şekilde tarif ediyordu ve biri yalandı. Tekil KİŞİ hâlâ
       ölçülemez — bu doğru ve söylenen şey artık o. */
    var anlam1 = T.tiklamaAnlam;
    if (olculdu(d.clicks30)) {
      anlam1 += ' ' + t('son30', { n: sayi(d.clicks30) });
    }

    var kirilim3 = t('kirilim', { kesin: sayi(kesinlesen),
                                  bekleyen: sayi(bekleyen) }) +
      (dusen > 0 ? t('kirilimIptal', { n: sayi(dusen) }) : '');

    /* Huninin ALTINDAKİ dipnot: basamak açıklamalarına sığmayan ama oranı
       YANLIŞ OKUTAN olguları kapatıyor. Hepsi ölçüldü.

       En ağırı atıf platformu: `apps/mobile/lib/core/partner_referrer.dart`
       ilk kapıda `defaultTargetPlatform != TargetPlatform.android` ise
       DÖNÜYOR (Play Install Referrer'ın iOS'ta dengi yok). Yani iPhone ya da
       masaüstünden gelen bir tıklama ATFA YAPISAL olarak
       geçemez ve o tıklamalar oranın BÖLENİNDE duruyor. Yazılmazsa iPhone
       kitlesine tanıtım yapan ortak "500 tıklama / 0 kuran" görüp kendi
       tanıtımını suçlar — panonun tam da önlemek için var olduğu yanlış
       teşhis. Bu dipnot YÖNETİM panelinde vardı, ortağın panosunda YOKTU;
       `web/r/index.html` ise yorumunda "panolarda YAZILI" diyordu, yani
       eksik olan yalnız metin değil o gerekçeydi.

       Basamaklara ADIYLA gönderme yapılıyor, "2. basamak" diye DEĞİL: sıra
       numaraları `aria-hidden` (bkz. `huniAdim`), yani ekran okuyucu onları
       hiç duymuyor ve numaraya gönderen bir cümle o kullanıcıda boşa düşer. */
    var dipnot = T.dipnotAndroid;
    if (tiklamaVar) {
      dipnot = t('dipnotTiklama', { android: T.dipnotAndroid });
    }

    return '<section class="huni" aria-label="' + e(T.huniEtiket) + '">' +
      huniAdim('1', T.tiklama, tiklamaVar ? sayi(tiklama) : '—', anlam1, '',
        tiklamaVar ? '' : T.tiklamaKapali) +
      huniOran(T.oranTiklayan, oran1) +
      huniAdim('2', T.kullanan, sayi(kuran), T.kullananAnlam, '') +
      huniOran(T.oranKullanan, oran2) +
      huniAdim('3', T.abone, sayi(abone), T.aboneAnlam,
        kirilim3, '', abone > 0) +
      '</section>' +
      /* Dipnot `.huni`nin DIŞINDA: içine konsaydı esnek bir öğe olur ve
         basamakların yanına bir sütun gibi otururdu. */
      '<p class="dipnot huni-dipnot">' + e(dipnot) + '</p>';
  }

  /* Tıklama serisi — saf flex/div, kütüphane YOK (dosya başındaki gerekçe:
     charts.js + bilesenler.js bu sayfaya bilerek yüklenmiyor). Yükseklik
     satır içi stille geliyor çünkü değer VERİDEN geliyor, CSS'te ifade
     edilemez.

     ERİŞİLEBİLİRLİK ÇİFT KATMAN: görsel çubuklar `aria-hidden` (ekran
     okuyucuya otuz anlamsız öğe okutmak bilgi değil) ve tam veri sr-only
     bir TABLODA duruyor — tablo gezilebilir bir yapıdır, çubuk yığını
     değil. `title` fare kullanıcısında kalıyor: `aria-hidden` yerel
     tarayıcı ipucunu kapatmaz.

     Boş dizi için `null` döner; çağıran o zaman modülü hiç çizmez. */
  function tiklamaSerisi(seri) {
    var gunler = [];
    for (var i = 0; i < seri.length; i++) {
      var g = seri[i] || {};
      var n = Number(g.count);
      /* Bozuk `count` günü seriden ATMIYOR, 0 çiziyor: günü düşürmek
         pencereyi kısaltır ve "son 30 gün" başlığını yalan yapar. Bu,
         sunucunun eksik günleri 0 ile doldurma sözleşmesiyle aynı
         davranış — burada uydurulan bir gün yok, gelen gün çiziliyor. */
      gunler.push({
        gun: String(g.day || ''),
        adet: (g.count == null || !isFinite(n) || n < 0) ? 0 : n
      });
    }
    if (!gunler.length) return null;

    var toplam = 0, enYuksek = 0, enYuksekGun = '';
    gunler.forEach(function (g) {
      toplam += g.adet;
      if (g.adet > enYuksek) { enYuksek = g.adet; enYuksekGun = g.gun; }
    });

    /* Hepsi sıfırsa boş bir seri çizilmiyor: otuz tane 2px'lik çizgi
       "veri yok" değil "pano bozuk" gibi okunur. */
    if (toplam === 0) {
      return {
        gun: gunler.length, toplam: 0,
        html: '<p class="bos-durum">' +
          e(t('seriBos', { gun: gunler.length })) + '</p>'
      };
    }

    var cubuklar = gunler.map(function (g) {
      /* Yükseklik EN YÜKSEK GÜNE göre — sabit bir tavan yoktu ve olmamalı,
         çünkü ortağın büyüklüğü bilinmiyor. Sıfır dışı bir günün yüzdesi
         sıfıra yuvarlanabiliyor (1/500 → %0) ve görünmez çubuk o günü
         "tıklama yok" diye okutur; taban %5'e sabitleniyor. */
      var yuzde = Math.round(g.adet / enYuksek * 100);
      if (g.adet > 0 && yuzde < 5) yuzde = 5;
      return '<div class="cubuk' + (g.adet > 0 ? '' : ' bos') +
        '" style="height:' + (g.adet > 0 ? yuzde + '%' : '2px') +
        '" title="' + e(gunEtiketi(g.gun) + ': ' + sayi(g.adet)) + '"></div>';
    }).join('');

    var satirlar = gunler.map(function (g) {
      return '<tr><th scope="row">' + e(gunEtiketi(g.gun)) + '</th>' +
        '<td>' + e(sayi(g.adet)) + '</td></tr>';
    }).join('');

    return {
      gun: gunler.length, toplam: toplam,
      html: '<div class="seri-kap">' +
        '<div class="seri" aria-hidden="true">' + cubuklar + '</div>' +
        '<div class="seri-bilgi">' +
        /* Aralıkta ok değil KISA ÇİZGİ: bu satır `aria-hidden` değil ve
           ekran okuyucu "→" işaretini "sağ ok" diye okur. */
        '<span>' + e(gunEtiketi(gunler[0].gun) + ' – ' +
          gunEtiketi(gunler[gunler.length - 1].gun)) + '</span>' +
        '<span>' + e(t('enYuksek', { gun: gunEtiketi(enYuksekGun),
                                     n: sayi(enYuksek) })) + '</span>' +
        '</div>' +
        '<table class="sr-only"><caption>' +
        e(t('seriCaption', { gun: gunler.length })) + '</caption>' +
        '<thead><tr><th scope="col">' + e(T.gun) + '</th>' +
        '<th scope="col">' + e(T.tiklama) + '</th></tr></thead><tbody>' +
        satirlar +
        '</tbody></table></div>'
    };
  }

  function kodDurumu(k) {
    if (k.active !== true) {
      return '<span class="rozet">' + e(T.pasif) + '</span>';
    }
    var son = tarihNesnesi(k.expiresAt);
    if (son && son.getTime() < Date.now()) {
      return '<span class="rozet dolmus">' + e(T.suresiDoldu) + '</span>';
    }
    return '<span class="rozet aktif">' + e(T.aktif) + '</span>';
  }

  function kodlarTablosu(kodlar) {
    if (!kodlar.length) {
      return '<p class="bos-durum">' + e(T.kodYok) + '</p>';
    }
    return '<div class="tablo-sar"><table class="tablo">' +
      '<caption class="sr-only">' + e(T.kodlarCaption) + '</caption>' +
      '<thead><tr>' +
      '<th scope="col">' + e(T.kod) + '</th>' +
      /* Sütun adı "Kullanım" değil "Bağlantıyı kullanan".
         ⚠️ "Kuran kullanıcı" da YANLIŞTI ve bir tur boyunca öyle durdu:
         `redemptionCount` tek bir satırdan artıyor
         (`partner_service.py:400`) ve o satıra İKİ yol birden ulaşıyor —
         kurulum + Install Referrer, VE uygulaması zaten kurulu birinin
         bağlantıya dokunması (App Links). İkincisinde kurulum HİÇ olmaz.
         Kapalı testte herkeste uygulama kurulu olduğu için oradaki her
         sayı ikinci yoldan gelir: "Kuran" desek 12 kurulum olmadığı hâlde
         12 kurulum raporlardık. */
      '<th scope="col" class="sag">' + e(T.tiklama) + '</th>' +
      '<th scope="col" class="sag">' + e(T.kullanan) + '</th>' +
      '<th scope="col">' + e(T.sonGun) + '</th>' +
      '<th scope="col">' + e(T.durum) + '</th>' +
      '<th scope="col">' + e(T.paylasilabilir) + '</th>' +
      '</tr></thead><tbody>' +
      kodlar.map(function (k, i) {
        // Bağlantı KÜÇÜK harfle (sahip, 2026-10-19): kod büyük harfle
        // saklanıyor ama paylaşılan adreste bağırıyordu. `/r/` sayfası gelen
        // kodu büyük harfe çevirip doğruluyor — iki biçim de çalışır.
        var bag = PAYLASIM_TABANI + encodeURIComponent(String(k.code || '').toLowerCase());
        var alanKimlik = 'bag-' + i;
        return '<tr>' +
          '<th scope="row" class="mono">' + e(k.code || '—') + '</th>' +
          /* Kod başına tıklama eski yanıtta YOK → "—". Burada "0" yazmak,
             hiç ölçülmemiş bir kanalı "denendi ama tutmadı" göstermek
             olurdu ve ortak o kanalı bırakırdı. */
          '<td class="sag">' + e(olculdu(k.clicks) ? sayi(k.clicks) : '—') + '</td>' +
          '<td class="sag">' + e(sayi(k.redemptionCount || 0)) + '</td>' +
          '<td class="mono">' + e(k.expiresAt ? tarih(k.expiresAt) : '—') + '</td>' +
          '<td>' + kodDurumu(k) + '</td>' +
          '<td><div class="bag-satir">' +
          '<label class="sr-only" for="' + alanKimlik + '">' +
          t('kodBaglantisi', { kod: e(k.code || '') }) + '</label>' +
          '<input class="girdi mono" id="' + alanKimlik + '" readonly value="' + e(bag) + '">' +
          '<button type="button" class="buton ikincil kucuk" data-kopya="' + alanKimlik +
          '">' + e(T.kopyala) + '</button>' +
          '</div></td></tr>';
      }).join('') +
      '</tbody></table></div>';
  }

  function odemelerTablosu(odemeler) {
    if (!odemeler.length) {
      return '<p class="bos-durum">' + e(T.odemeYok) + '</p>';
    }
    /* En yeni üstte: sunucu sıralama garantisi vermiyor (alt koleksiyon
       stream'i), sıralama burada yapılır. */
    var sirali = odemeler.slice().sort(function (a, b) {
      var ta = tarihNesnesi(a.at), tb = tarihNesnesi(b.at);
      return (tb ? tb.getTime() : 0) - (ta ? ta.getTime() : 0);
    });
    return '<div class="tablo-sar"><table class="tablo">' +
      '<caption class="sr-only">' + e(T.odemelerCaption) + '</caption>' +
      '<thead><tr>' +
      '<th scope="col">' + e(T.tarihSutun) + '</th>' +
      '<th scope="col" class="sag">' + e(T.tutar) + '</th>' +
      '<th scope="col">' + e(T.notSutun) + '</th>' +
      '</tr></thead><tbody>' +
      sirali.map(function (o) {
        /* Tutar SATIRIN kendi para biriminde yazılır — ortağın varsayılan
           birimiyle geçmiş bir ödemenin birimi aynı olmak zorunda değil. */
        return '<tr>' +
          '<th scope="row" class="mono">' + e(tarih(o.at)) + '</th>' +
          '<td class="sag mono">' + e(para(o.amount, simge(o.currency))) + '</td>' +
          '<td>' + e(o.note || '—') + '</td>' +
          '</tr>';
      }).join('') +
      '</tbody></table></div>';
  }

  function ciz(d) {
    var kodlar = Array.isArray(d.codes) ? d.codes : [];
    var odemeler = Array.isArray(d.payouts) ? d.payouts : [];
    var pasif = d.active === false;
    var odulSayisi = Number(d.rewardTry);
    var odulVar = isFinite(odulSayisi) && odulSayisi > 0;
    var odemeBirimi = simge(d.payoutCurrency);
    var uyumsuz = Number(d.payoutCurrencyMismatchCount || 0);
    /* Seri YOKSA modül hiç çizilmiyor (boş bir kutu "ölçüm yok" demez,
       "pano eksik" der). Dizi geldiyse ama boşsa `tiklamaSerisi` null
       döner — aynı yol. */
    var seriKutu = Array.isArray(d.clickSeries)
      ? tiklamaSerisi(d.clickSeries) : null;
    var bekleyenCumle = t('bekleyenCumle', { gun: OLGUNLASMA_GUN });

    var html =
      '<div class="sayfa-bas">' +
      '<h1 tabindex="-1">' + e(d.name || T.panoAdi) + '</h1>' +
      '<p>' + (odulVar
        /* Ödül tutarını ortak DEĞİŞTİREMEZ; yazma ucu da yok. Ama bu sayı
           GÜNCEL oran, geçmişin oranı değil: `rewardTry` hakediş açılırken
           dokümana KOPYALANIYOR (partner_service modül docstring'i +
           open_qualification), yani oran sonradan değişirse eski hakedişler
           eski tutarla kalır. Bunu yazmazsak ortak "3 abone × ₺50 = ₺150
           olmalı, neden ₺90?" diye panoyu bozuk sanır — sayılar doğru,
           eksik olan cümleydi. */
        ? t('odulCumlesi', { tutar: e(para(odulSayisi, '₺')) })
        : e(T.odulTanimsiz)) + '</p>' +
      '</div>' +

      /* Pasiflik ölçülmüş davranıştır (partner_service.open_qualification):
         kod kullanımı sürer, YENİ hakediş açılmaz, geçmiş durur. */
      (pasif ? '<div class="bant uyari">' + T.pasifBant + '</div>' : '') +

      /* Tutarsız ödül tutarı PASİFLİKLE AYNI sonucu veriyor ve bu ölçüldü:
         `open_qualification` geçersiz `rewardTry`de `_rewardi_dogrula`
         hatasını yutup False dönüyor — kod kullanılır, sayaç artar,
         hakediş AÇILMAZ. Yukarıdaki tek satırlık "tanımlanmadı" notu bu
         sonucu söylemiyordu; ortak huninin ilk basamağı artarken
         "Beklemede 0" görüp panoyu bozuk sanardı. */
      (!odulVar ? '<div class="bant uyari">' + T.odulYokBant + '</div>'
                : '') +

      /* Eski hâlde burada üç KPI vardı ve ikisi huninin AYNI basamağıydı
         ("Beklemede" + "Kesinleşen" = abone), birincisinin adı ise
         yanlıştı. Sayılar kaybolmuyor: ikisi 3. basamağın kırılımına
         indi, `voidCount` de oraya eklendi — self_view onu bilerek
         döndürüyor ama pano hiç göstermiyordu. */
      huniBolumu(d) +

      '<section class="izgara-kpi" aria-label="' + e(T.hakedis) + '">' +
      kpi(T.kesinlesenHakedis, para(d.earnedTry, '₺'), T.toplamKazanc, true) +
      kpi(T.beklemede, para(d.pendingTry, '₺'),
        t('gunSonraKesinlesir', { gun: OLGUNLASMA_GUN })) +
      kpi(T.odenen, para(d.paidTry, '₺'), T.sanaAktarilan) +
      kpi(T.bakiye, para(d.balanceTry, '₺'), bakiyeAlt(d, uyumsuz),
        Number(d.balanceTry) > 0 && uyumsuz === 0) +
      '</section>' +

      '<div class="bant bilgi">' + e(bekleyenCumle) + '</div>' +

      /* Başlıktaki gün sayısı SERİNİN KENDİ uzunluğundan geliyor, sabit
         30'dan değil: sunucu daha kısa bir pencere gönderirse başlık da
         kısalır. Alt metindeki toplam da yine çizilen günlerin toplamı —
         `clicks30` oraya YAZILMIYOR çünkü pencere 30 günden farklıysa iki
         sayı çelişir. `clicks30` 1. basamağın açıklamasında kullanılıyor,
         yani tam olarak "son 30 gün" dediği yerde. */
      (seriKutu ? modul(t('seriBaslik', { gun: seriKutu.gun }),
        seriKutu.html,
        cogul(seriKutu.toplam, 'tiklamaToplamTek', 'tiklamaToplam')) : '') +

      modul(T.kodlar,
        (kodlar.length
          /* Kod başına tıklama, ortağın KANALLARINI kıyaslamasının tek
             yolu (sektörde "sub-ID" denen şeyin karşılığı): aynı ortak
             birden fazla kod taşıyabiliyor, yani her kanala ayrı kod
             verilip hangisinin çalıştığı ölçülebilir. */
          ? '<p class="dipnot">' + e(T.kanalDipnot) + '</p>'
          : '') +
        kodlarTablosu(kodlar),
        kodlar.length ? cogul(kodlar.length, 'kodSayisiTek', 'kodSayisi')
                      : '') +

      /* ⚠️ ÖDEME EŞİĞİ artık GELİYOR — önceki tur burada "hiç gelmiyor"
         yazıyordu ve gerekçesi bu turda geçersizleşti. Ölçülen yeni hâl:
         `partner_self_view` `minPayoutTry`yi YALNIZ kayıtlıysa taşıyor,
         `partner_detail` zaten `partner` içinde döndürüyordu (eski notun
         "sonuca KOYMUYOR" cümlesi ölçülünce yanlış çıktı) ve yönetim
         paneli alanı artık girebiliyor ("Ödeme ayarları" modülü).

         DEĞİŞMEYEN kural: `create_partner` alanı hâlâ hiç yazmıyor ve bu
         bir karar. Tanıtım sayfası (`web/ortaklik.html`) "ödeme takvimi,
         alt sınır ve ödeme kanalı ANLAŞMADA yazılır" diyor, yani eşik
         ürünün değil o ortakla yapılan anlaşmanın sayısı — kodun bileceği
         bir varsayılanı YOK. Alan boşken bu pano eşikten HİÇ söz etmiyor
         (`bakiyeAlt`); olmayan bir kuralı tarif etmek bu depodaki en çok
         tekrarlanan kusur sınıfı.

         Sunucu eşiği ZORLAMIYOR ve pano bunu vaat de etmiyor: ödemeyi
         `add_payout` yazıyor, tek çağıranı yönetim ucu (`api/admin.py`),
         yani elle. Eşik ortağa "ne zaman para bekleyebilirim"i söyleyen
         bir sayıdır, otomatik bir tetik değil.

         Ödeme YÖNTEMİ (iban/taxId) yine BİLEREK gösterilmiyor: `self_view`
         onları yapısal olarak dışarıda bırakıyor (`payoutCurrency` ve
         `minPayoutTry` dışında hiçbiri geçmiyor) ve karar sözleşmeyi
         genişletmemek yönünde — ortak kendi IBAN'ını zaten biliyor, panoda
         tekrar okumasının karar değeri yok, buna karşılık ekran görüntüsü
         paylaşılan bir panoya bir ödeme kimliği daha koymak olurdu. */
      modul(T.odemeGecmisi,
        odemelerTablosu(odemeler) +
        /* Sıfır dışı uyumsuzluk EKRANDAKİ PARAYI yanlış yapıyor ve bunu
           ortağa söylemek şart: `partner_detail` yorumunun ölçtüğü hâl —
           `paidTry` farklı birimdeki kayıtları saymaz, dolayısıyla
           `balanceTry` olduğundan BÜYÜK çıkar. Para çıkışı da bu hâlde
           kapalı (`add_payout` → `ledger_currency_mixed`). self_view bu
           sayacı tam bunun için döndürüyordu, pano ise hiç göstermiyordu. */
        (uyumsuz > 0 ? '<div class="bant uyari">' +
          t('uyumsuzBant', { n: e(sayi(uyumsuz)),
                             birim: e(odemeBirimi.trim()) }) +
          '</div>' : '') +
        /* Dipnot ÜÇ HÂLE göre ayrılıyor, tek metin değil: eşiğin yokluğu,
           sıfırı ve pozitifi ortağa BAŞKA şeyler söyler. Tek bir cümle
           ("bir eşik gösterilmiyor") eşik girildiği anda yalan olurdu, ters
           yönde tek bir cümle de girilmediği anda olmayan bir kuralı
           duyururdu. Üç dalın hiçbirinde ÖDEME TAKVİMİ vaat edilmiyor:
           takvim de anlaşmada ve panoya hiç gelmiyor. */
        '<p class="dipnot">' + e(T.odemeDipnotBas) +
        (!olculdu(d.minPayoutTry)
          ? e(T.esikYok)
          : (Number(d.minPayoutTry) === 0
              ? e(T.esikSifir)
              : t('esikVar', { esik: e(para(Number(d.minPayoutTry), '₺')) }))) +
        e(T.odemeDipnotSon) + '</p>',
        t('odemeBirimi', { birim: odemeBirimi.trim() })) +

      /* Ödül kuralı, ölçülen davranışın birebir aynası
         (api/billing.py _ortaklik_hakedisi + partner_service):
         SANDBOX, yenileme, jeton paketi ve deneme BAŞLANGICI ödül
         üretmez; denemenin ücretliye dönmesi üretir. Bu ayrımı yazmak
         şart — "deneme ödül vermez" demek, dönen denemeyi kaybetmiş
         gösterirdi. */
      /* ⚠️ "Kullanıcı için indirim ya da ödül yoktur" MUTLAK bir iddia ve
         dayanağı bu turda DEĞİŞTİ. Eski hâlinde iddia ölçümle
         ÇELİŞİYORDU: `partnerCodes.bonusTokens` canlı bir alandı ve
         kullanım yolunda gerçekten promo jeton yatırıyordu
         (`partner_service.redeem` → `wallet.credit_promo`; uç yanıtı da
         `bonusTokens` döndürüyor). Yani pano, olan bir şeyi yok sayıyordu.

         Artık iddia YAPISAL, niyet beyanı değil (K-a) — dayanağın ÜÇ ayağı
         da ÖLÇÜLDÜ (2026-09-27): uç şeması sıfır dışını almıyor
         (`backend/api/admin.py`, `CodeCreate`: `bonusTokens` alanı
         `ge=0, le=0`), SERVİS de almıyor (`partner_service.create_code`
         sıfır dışında `RedeemError(400, "bonus_not_allowed")` fırlatır —
         yani kapı uç atlanınca da duruyor), panel ise o alanı hiç
         göstermeyip HER ZAMAN 0 yolluyor
         (`web/rytho-admin/gorunumler/ortaklar.js`). Alan veri modelinde
         UYUYOR durumda kalıyor, silinmedi — "vermiyoruz" değil
         "veremiyoruz". Aynı gerekçe `web/ortaklik.html`'deki tanıtım
         cümlesinin yanında da yazılı.

         ⚠️ Kapı YAZMA yolundadır, var olan dokümanları geriye dönük
         düzeltmez: `partner_service.redeem` içindeki `bonus > 0` dalı
         BİLEREK duruyor (verilmiş bir bakiyeyi açıklamasız düşürmemek
         için) ve K-a'dan ÖNCE sıfır dışı yazılmış bir kod hâlâ canlıysa
         `wallet.credit_promo` çağrılır — o kod için bu cümle yalan olur.
         Kalan iş kod değil VERİ denetimi (`partnerCodes` içinde
         `bonusTokens > 0` var mı). Dayanak kalkarsa (uç ya da servis
         yeniden sıfırdan büyük değer kabul ederse) önce bu cümle
         düzeltilmeli — kaynaksız kalan bir mutlak iddia kusurdur. */
      modul(T.odulNasil,
        '<p class="dipnot">' + T.odulP1 + '</p>' +
        '<p class="dipnot">' + T.odulP2 + '</p>' +
        '<p class="dipnot">' + e(T.odulP3) + '</p>');

    $('pano-govde').innerHTML = html;
    menuKur();
    duyur(T.panoYuklendi);
  }

  /* ------------------------------------------------ yükleme */

  function iskelet() {
    return '<div class="izgara-kpi" aria-hidden="true">' +
      '<div class="iskelet"></div><div class="iskelet"></div>' +
      '<div class="iskelet"></div><div class="iskelet"></div></div>';
  }

  /* Geçici durumun METNİ tek yerde: iki farklı yol (pano verisi ve kimlik
     jetonu) aynı cümleyi göstermek zorunda, yoksa aynı olguyu iki farklı
     dille anlatan bir pano çıkar. */
  var GECICI_METIN = T.gecici;

  /* Durum ekranı (bant + görünür "Tekrar dene"). Ayrı fonksiyon olmasının
     nedeni ölçülmüş bir kusur: geçici/kalıcı ayrımı yalnız `yukle()`ye
     yazıldığında KİMLİK yolu hâlâ zorunlu çıkış yapıyordu — yani kapı
     atlanabiliyordu, atlanabilen bir kapı da kapı değildir. Artık iki yol
     da buradan geçiyor.

     `goster('pano')` burada çağrılıyor çünkü kimlik yolunda pano henüz
     açılmamış olabilir; pano zaten açıksa çağrı etkisizdir.
     `aria-busy` de burada kapanıyor: kimlik yolunda `yukle()` hiç koşmaz
     ve gövde HTML'den `aria-busy="true"` ile geliyor — kapatılmazsa ekran
     okuyucu panoyu sonsuza kadar "yükleniyor" okur. */
  function durumEkrani(gecici, metin, ayrinti, tekrarIslev) {
    goster('pano');
    var govde = $('pano-govde');
    govde.innerHTML =
      '<div class="bant ' + (gecici ? 'uyari' : 'hata') + '">' +
      e(metin) + (ayrinti ? ' ' + e(ayrinti) : '') + '</div>' +
      '<div><button type="button" class="buton ikincil" id="tekrar-dene">' +
      e(T.tekrarDene) + '</button></div>';
    var tekrar = $('tekrar-dene');
    if (tekrar) tekrar.addEventListener('click', tekrarIslev);
    govde.setAttribute('aria-busy', 'false');
    duyur(metin);
  }

  var yukleniyor = false;

  function yukle() {
    if (yukleniyor) return;
    yukleniyor = true;
    var govde = $('pano-govde');
    govde.setAttribute('aria-busy', 'true');
    govde.innerHTML = iskelet();
    duyur(T.panoYukleniyor);
    return RY.get('/api/v1/partners/me').then(function (d) {
      ciz(d || {});
    }).catch(function (hata) {
      if (hata && (hata.message === 'yetkisiz' || hata.iptal)) return;

      /* ⚠️ BU AYRIM OTURUMUN KADERİNİ BELİRLİYOR, sadece bir metin
         seçimi değil.

         Eskiden tek dal vardı: 403 → zorunlu çıkış + jenerik ekran. Kök
         neden ÖLÇÜLDÜ: `partner_service.partner_detail` Firestore'a
         ulaşamadığında `RedeemError(500, "unavailable")` fırlatıyor, ama
         `api/partners.py` `/me` ucu HER `RedeemError`i tek bir 403'e
         düzleştiriyordu. Yani bir dakikalık altyapı kesintisi ortağa
         "burada senin için bir şey yok" diye gösterilip oturumu da
         kapatılıyordu — kendi kazancını göremeyen ortak programdan
         atıldığını sanardı. Kaybedilen veri yok, kaybedilen GÜVEN vardı
         ve geri kazanılması bir mesaj gerektiriyordu.

         Ayrım artık HTTP SINIFINA dayanıyor, tek bir koda değil:
         403 = kalıcı yetki yokluğu (claim var ama ortak kaydı silinmiş
         ya da erişim kapatılmış) → jenerik ekran; 5xx ve ağ hatası =
         GEÇİCİ → oturum durur, durum söylenir, yeniden dene düğmesi
         görünür.

         Uç tarafı ÖLÇÜLDÜ (2026-09-27, `backend/api/partners.py`): `/me`
         artık `RedeemError`i ikiye ayırıyor — `partner_service`in
         `TRANSIENT_REASONS` kümesindeki sebep (`"unavailable"`)
         `Retry-After` başlıklı **503**, diğerleri jenerik 403. Yani
         Firestore kesintisi bu dosyada geçici dala düşüyor; iki taraf
         ancak BİRLİKTE doğru çalışıyor.

         Sınıfa bağlamak (tek koda değil) bilinçli: uç ileride 502/504
         eklerse bu kod değişmeden doğru dala düşer. */
      if (hata && hata.durum === 403) { RY.yetkisiz(); return; }

      /* `hata.durum` yoksa `undefined >= 500` false'tur — yani beklenmeyen
         bir istemci hatası (örn. çizim sırasında fırlayan bir kusur)
         "geçici" diye ETİKETLENMEZ. Yanlış teşhis, yanlış gerekçe kadar
         zararlıdır: kullanıcı beyhude bekler. */
      var gecici = !!hata && (hata.durum >= 500 ||
        hata.message === 'ag-hatasi');

      /* Geçici durumda ayrıntı yalnız EYLEM DEĞİŞTİRİYORSA eklenir ve bu
         pratikte TEK durum: ağ hatası — orada eylem ortakta ("ağını
         kontrol et").

         Sunucunun `detail`ı BİLEREK eklenmiyor. Ölçüldü (2026-09-27):
         `api/partners.py` geçici hâlde MAKİNE-OKUR bir gövde dönüyor
         (`detail={"code": "temporarily_unavailable", "reason": ...}`) ve
         `ry-api.js`in `detayMetni`si dize olmayan detayı
         `JSON.stringify` ile metne çeviriyor — eklenseydi ortak, bandın
         sonunda ham JSON görürdü. Jenerik "Sunucu hatası — birazdan
         tekrar dene." de ilk cümlenin tekrarı olurdu; iki kez aynı şeyi
         söylemek metni gürültüye çevirir. */
      var ayrinti = (hata && hata.message === 'ag-hatasi')
        ? hataMetni(hata) : '';
      durumEkrani(gecici, gecici ? GECICI_METIN : hataMetni(hata),
        gecici ? ayrinti : '', yukle);
    }).then(function () {
      yukleniyor = false;
      $('pano-govde').setAttribute('aria-busy', 'false');
    });
  }

  $('yenile').addEventListener('click', function () { yukle(); });

  /* Kopyalama: pano yeniden çizildiği için olay GÖVDEYE bağlanır. */
  $('pano-govde').addEventListener('click', function (ev) {
    var dugme = ev.target.closest('[data-kopya]');
    if (!dugme) return;
    var alan = $(dugme.getAttribute('data-kopya'));
    if (!alan) return;
    /* Pano alanı salt okunur bir girdi olduğu için kopyalama başarısız
       olsa bile bağlantı elle seçilebilir durumda kalır — bu yüzden
       hata yolunda kullanıcıyı çıkmaza sokmuyoruz. */
    function tamam() {
      toast(T.kopyalandi, 'basari');
      duyur(T.kopyalandi);
    }
    function elle() {
      alan.focus();
      alan.select();
      var oldu = false;
      try { oldu = document.execCommand('copy'); } catch (yok) { oldu = false; }
      if (oldu) tamam();
      else {
        toast(T.kopyalanamadi, 'uyari');
      }
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(alan.value).then(tamam).catch(elle);
    } else elle();
  });

  /* ------------------------------------------------ oturum akışı */

  /* Kimliğin KENDİSİNİN geçersizleştiği kodlar — tek meşru zorunlu çıkış
     sebebi. Liste Firebase'in hata kodlarından seçildi, cihazda
     ÖLÇÜLMEDİ; bu yüzden kapsayıcı SAYILMIYOR ve bilinmeyen her kod
     GEÇİCİ kabul ediliyor. Bedel asimetrik: geçiciyi kalıcı sanmak ortağı
     oturumundan atar (çevrimdışıysa geri giremez de), kalıcıyı geçici
     sanmak yalnız bir "Tekrar dene" düğmesi fazla gösterir — yetkiyi
     zaten uç veriyor, buradaki kontrol UX'tir. */
  var KALICI_KIMLIK_HATASI = ['auth/user-disabled', 'auth/user-token-expired',
    'auth/invalid-user-token', 'auth/user-not-found'];

  /* Jetonu OKUYAMAMAK "ortak değil" DEMEK DEĞİLDİR. `getIdTokenResult()`
     jetonun süresi geçmişse ağa gider; çevrimdışı bir ortakta ya da bir
     securetoken/App Check hıçkırığında reddeder. Eski hâl her reddi
     `RY.yetkisiz()`e bağlıyordu: ortak hem jenerik "böyle bir sayfa yok"
     ekranını görüyor hem de oturumu KAPATILIYORDU — pano verisi yolundaki
     geçici/kalıcı ayrımının kapattığı deliğin tam eşi, bir satır yukarıda
     açık duruyordu. Yeniden dene AYNI kullanıcıyla kimlik kontrolünü
     tekrarlar; `onAuthStateChanged` yeniden ateşlenmez çünkü oturum
     kapanmıyor, bu yüzden tekrar bu fonksiyona bağlanıyor.

     Sahte-404 deseni BOZULMUYOR: bu geçici ekran claim'e BAKMADAN, yani
     ortak olan ve olmayan herkese aynı biçimde gösteriliyor — dolayısıyla
     "bu hesabın ortak erişimi var mı" sorusunu yanıtlamıyor. Gizlemediği
     tek şey sayfanın ortak panosu olduğu, o da zaten <title> ve giriş
     kartında yazılı. */
  function kimlikKontrol(kullanici) {
    return kullanici.getIdTokenResult().then(function (sonuc) {
      var c = sonuc.claims || {};
      /* Yetki SUNUCUDA: buradaki claim kontrolü yalnız UX. Claim'siz
         kullanıcı jenerik görünüm görür, uç zaten 403'ler. */
      if (c.partner !== true) { RY.yetkisiz(); return; }
      $('kim-eposta').textContent = kullanici.email || '';
      $('kim-eposta').setAttribute('title', kullanici.email || '');
      goster('pano');
      yukle();
    }).catch(function (hata) {
      var kod = (hata && hata.code) || '';
      if (KALICI_KIMLIK_HATASI.indexOf(kod) >= 0) { RY.yetkisiz(); return; }
      $('kim-eposta').textContent = kullanici.email || '';
      durumEkrani(true, GECICI_METIN, T.kimlikAg,
        function () { kimlikKontrol(kullanici); });
    });
  }

  auth.onAuthStateChanged(function (kullanici) {
    if (!kullanici) {
      /* Jenerik ekrana geçtiysek giriş kartını GÖSTERME (yukarıdaki
         kilit): bu null, kullanıcının çıkışı değil bizim yaptığımız
         zorunlu çıkışın yankısı. */
      if (!jenerikKilit) goster('giris');
      return;
    }
    kimlikKontrol(kullanici);
  });
})();

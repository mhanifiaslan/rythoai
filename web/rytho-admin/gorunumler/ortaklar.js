/* Ortaklar (W7 → AD19): affiliate liste + detay; kod üretimi, atıf,
   hakediş, ödeme. Okuma admin (owner+support), YAZIMLAR owner — düğmeler
   rol'e göre gizlenir, sunucu zaten 403'ler.

   Rotalar: #/ortaklar (liste) · #/ortaklar/{id} (detay).
   Uçlar:
   - GET   /api/v1/admin/partners → partner dokümanının TAMAMI
     [{id, name, contact, rewardTry, rewardModel, uid, active, notes,
       createdAt, sharePercent}]
   - POST  /api/v1/admin/partners {name, contact, notes, rewardTry, uid}
     `uid` ZORUNLU (K-b) ve kapı ÜÇ katmanda birden: bu form, uçtaki
     `PartnerCreate.uid: str = Field(min_length=1, …)` ve servisteki
     `create_partner` (boşluktan oluşan uid'i 400 `uid_required` ile
     düşürür). Formdaki zorunluluk bir UX kapısı — tek kapı O DEĞİL, yani
     gevşetilirse kullanıcı gerekçesiz bir 422 görür.
   - GET   /api/v1/admin/partners/{id} → {partner, codes:[...],
       referredUsers, pendingCount, qualifiedCount, voidCount,
       earnedTry, pendingTry, paidTry, balanceTry,
       attributedGrossUsd, attributedEvents, payouts:[...],
       access:{uid, granted, email, reason}}
   - POST  /api/v1/admin/partners/{id}/access {grant:bool} → {status, access}
     Ortağın Firebase custom claim'ini ({partner:true, partnerId}) basar ya
     da kaldırır. 400 gövdesi ÜÇ kod taşıyabilir: `no_uid`,
     `user_not_found`, `uid_taken` — üçü de ayrı ayrı çevrilir, çünkü
     hepsi operatörün YAPACAĞI şeyi değiştirir.
   - PATCH /api/v1/admin/partners/{id}
       {active|name|contact|notes|rewardTry|uid|payoutCurrency|taxId|iban}
   - POST  /api/v1/admin/partners/{id}/codes {code|null, bonusTokens,
     maxRedemptions|null, expiresAt|null} — panel `bonusTokens` için HEP 0
     yollar (K-a); uç alanı almaya devam ediyor, panelden sıfır dışı girilemez.
   - POST  /api/v1/admin/partners/{id}/payouts {amount, currency, note}
     (ön-izli: iz yazılamazsa 503 mesajı olduğu gibi)

   Dürüst model (OP-turu): ortak, getirdiği kullanıcının İLK aboneliği
   başına SABİT bir ₺ tutar kazanır. Kullanıcıya indirim ya da ödül YOK —
   Play Install Referrer sayesinde kullanıcı kod bile yazmıyor, yani
   ödüllendirilecek bir eylemi yok. Jeton paketleri, denemeler, SANDBOX
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
    if (/[\s@]/.test(v)) return 'uid bekleniyor (e-posta değil).';
    return v.length >= 6 ? null : 'En az 6 karakter.';
  }

  function hataToast(h) {
    var m = RY.hataMetni(h);
    if (m) RY.b.toast(m, 'hata');
  }

  /* `access.reason` çevirisi — YALNIZ "bilinmiyor" hâlinde gösterilir.
     Üç neden üç ayrı iş demek: uid gir / uid'i düzelt / tekrar dene. */
  var ERISIM_NEDEN = {
    no_uid: 'Firebase hesabı bağlı değil — sorgulanacak bir hesap yok.',
    user_not_found: 'Bu uid ile Firebase hesabı yok.',
    unavailable: 'Firebase Auth şu an okunamadı — durum ÖLÇÜLEMEDİ.'
  };

  /* POST /access 400 gövdesindeki kodlar. `RY.hataMetni` bu kodları olduğu
     gibi (`no_uid`) gösterirdi; makine kodu operatöre ne yapacağını
     söylemez. */
  var ERISIM_HATA = {
    no_uid: 'Ortağın Firebase hesabı bağlı değil: önce "Ödülü değiştir" ' +
      'penceresinden uid gir.',
    user_not_found: 'Bu uid ile Firebase hesabı yok — uid yanlış yazılmış olabilir.',
    uid_taken: 'Bu hesap BAŞKA bir ortağa bağlı. Bir Firebase hesabı yalnız ' +
      'tek ortak panosu görebilir; önce öteki ortağın erişimini kapat.',
    // 500 `unavailable` da buraya giriyor: `hataMetni` gövdedeki `detail`i
    // 500 dalından ÖNCE okuduğu için operatör ham "unavailable" görürdü.
    // Son cümle sunucunun kendi gerekçesiyle aynı: geçici arıza görüp
    // `partners/{id}.uid` alanını "düzeltmeye" başlamak asıl zararı verir.
    unavailable: 'Firebase Auth şu an okunamadı — claim YAZILMADI. Birazdan ' +
      'tekrar dene; uid alanını düzeltmeye çalışma, sorun uid değil.'
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

  /* ---------------- Liste ---------------- */

  async function liste(icerik) {
    var b = RY.b;
    var veri = await RY.get(yol());
    var ortaklar = Array.isArray(veri.partners) ? veri.partners : [];
    ortaklar.forEach(function (p) { adOnbellek[p.id] = p.name; });
    var sahip = RY.sahipMi();

    var aktifSayisi = ortaklar.filter(function (p) { return p.active !== false; }).length;

    icerik.innerHTML = b.sayfaBaslik({
      baslik: 'Ortaklar',
      alt: ortaklar.length
        ? b.sayi(ortaklar.length) + ' ortak · ' + b.sayi(aktifSayisi) + ' aktif'
        : 'Affiliate kodları ve hakediş',
      eylemlerHtml: sahip
        ? '<button type="button" class="buton" id="ortak-yeni">' + b.ik('arti', 16) + 'Yeni ortak</button>'
        : ''
    }) + b.modul('Ortak listesi', '<div id="ortak-liste"></div>', '',
      { alt: 'satıra git: huni, hakediş, kodlar, ödemeler' }) +
      '<p class="dipnot">Ortak, getirdiği kullanıcının <b>ilk aboneliği</b> başına sabit ' +
      'bir ₺ tutar kazanır; kullanıcıya indirim verilmez. Jeton paketi, deneme, yenileme ve ' +
      'test alımları ödül ÜRETMEZ. Hakediş satın almadan 15 gün sonra kesinleşir (iade ' +
      'penceresi). Mağaza fiyat indirimi buradan yapılamaz — gerekiyorsa RevenueCat/Play ' +
      'konsolundan elle.</p>';

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
        { ad: 'uid', etiket: 'Firebase hesabı (uid)', zorunlu: true, max: 128,
          otomatik: 'off', yertutucu: 'Firebase Auth kullanıcı kimliği',
          // NEREDEN BULUNUR da yazılıyor: alan zorunlu ama panel uid'i
          // hiçbir yerde aratmıyor, yani operatör "nereden alacağım"
          // sorusunda kalıyordu. Yol ÖLÇÜLDÜ (`gorunumler/kullanicilar.js`):
          // arama alanları arasında `eposta` var ve kullanıcı 360 sayfası
          // kimlik kartında uid'i `title="uid"` ile gösteriyor.
          yardim: 'Ortağın kendi panosunu görmesi ve KENDİ kodunu kullanamaması ' +
            'buna bağlı — bu yüzden zorunlu. Nereden: Kullanıcılar → e-posta ile ' +
            'ara → hesabı aç → kimlik kartındaki uid.',
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
        '<dt>Bağlı hesap (uid)</dt><dd>' +
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
      ic += '<p class="dipnot">Uç bu istekte <b>access</b> alanını döndürmedi — ' +
        'erişim durumu panelden ölçülemiyor.</p>';
    }

    // ⚠️ Propagasyon: bu cümle olmadan sahip "açtım ama giremiyor" diye
    // geri döner. Firebase custom claim ANINDA geçmez; ölçülmüş davranış,
    // tahmin değil.
    ic += '<p class="dipnot">Erişim Firebase custom claim ile verilir ve ANINDA ' +
      'geçerli olmaz: ortağın ID jetonu yenilenene kadar (en çok 1 saat, ya da ' +
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
      'doğrudur — eksik olan claim.</p>';

    if (!sahip) return ic;

    if (!er.uid) {
      // Düğme GÖSTERİLMEZ: uid yokken uç kesin 400 `no_uid` döner, yani
      // yalnız başarısız olabilecek bir düğme olurdu. Onun yerine gerçek
      // sıradaki iş söylenir.
      ic += '<p class="dipnot">Erişim açılabilmesi için önce Firebase hesabı bağlanmalı: ' +
        '"Ödülü değiştir" penceresinden uid gir.</p>';
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
            ? '<span class="dipnot">Bu uid ile hesap bulunmadığı sürece açma denemesi ' +
              'başarısız olur — önce uid düzeltilmeli.</span>'
            : '<span class="dipnot">Durum bilinmiyorken açmak zararsız: claim, hesabın ' +
              'öteki claim değerleriyle BİRLEŞTİRİLİR — ezilmez.</span>')
        : '') +
      '</div>';
    return ic;
  }

  /* ---------------- Detay ---------------- */

  async function detay(icerik, id) {
    var b = RY.b;
    var d = await RY.get(yol(id));
    var p = d.partner || {};
    var kodlar = Array.isArray(d.codes) ? d.codes : [];
    var odemeler = Array.isArray(d.payouts) ? d.payouts : [];
    var sahip = RY.sahipMi();
    var pasif = p.active === false;
    var er = erisimOku(d, p);
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
        : 'Kalan ' + b.sayi(adimlar.length) + ' adım owner yetkisi ister.'), 'uyari');
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
      (p.uid ? '' : b.bant('Bu ortağın Firebase hesabı BAĞLI DEĞİL ve bunun PARA ' +
        'sonucu var: kendi kodunu kendi hesabında kullanıp kendine ödül yazdırması ' +
        'engellenemez — kapı uid karşılaştırmasına dayanıyor, boş uid ile hiç tutmaz. ' +
        'Yeni kayıtlarda uid zorunlu, yani bu kayıt zorunluluk öncesinden kalma ya da ' +
        'elle açılmış. "Ödülü değiştir" penceresinden hemen uid girilmeli.', 'hata')) +
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
      '<section class="izgara-kpi" aria-label="Huni">' +
      b.istatistikKarti({ ad: 'Gelen kullanıcı', deger: b.sayi(d.referredUsers || 0),
        alt: 'kod kullanımı' }) +
      b.istatistikKarti({ ad: 'Bekleyen', deger: b.sayi(d.pendingCount || 0),
        alt: '15 gün olgunlaşma' }) +
      b.istatistikKarti({ ad: 'Kesinleşen', deger: b.sayi(d.qualifiedCount || 0),
        altin: Number(d.qualifiedCount) > 0, alt: 'ödemeye hazır' }) +
      b.istatistikKarti({ ad: 'İptal', deger: b.sayi(d.voidCount || 0),
        alt: 'iade / süre bitti' }) +
      '</section>' +
      // Para — ₺. Atfedilen brüt gelir ($) BİLEREK ayrı kartta: ödülü
      // artık o belirlemiyor ve iki birimi aynı ızgaraya koymak
      // "hakediş brütün yüzdesi" yanılgısını geri getirirdi.
      '<section class="izgara-kpi" aria-label="Hakediş özeti">' +
      b.istatistikKarti({ ad: 'Kesinleşen hakediş', deger: b.para(d.earnedTry, '₺'),
        altin: true, alt: 'abone başına ' + odul(b, p) }) +
      b.istatistikKarti({ ad: 'Beklemede', deger: b.para(d.pendingTry, '₺'),
        alt: 'henüz hak edilmedi' }) +
      b.istatistikKarti({ ad: 'Ödenen', deger: b.para(d.paidTry, '₺') }) +
      b.istatistikKarti({ ad: 'Bakiye', deger: b.para(d.balanceTry, '₺'),
        altin: Number(d.balanceTry) > 0,
        alt: Number(d.balanceTry) > 0 ? 'ödeme bekliyor' : 'kapalı' }) +
      '</section>' +
      b.modul('Atfedilen gelir (bilgi)',
        '<p class="dipnot">Bu ortağa atfedilen <b>' + b.sayi(d.attributedEvents || 0) +
        '</b> üretim olayından ' + b.para(d.attributedGrossUsd) + ' brüt geldi (iade ' +
        'düşülmüş, SANDBOX süzülmüş). Ödülü bu sayı BELİRLEMEZ — ödül kazanılan abone ' +
        'başına sabittir; bu kart yalnız programın getirisini görmek için.</p>') +
      (p.notes ? b.modul('Not', '<p class="dipnot">' + b.e(p.notes) + '</p>') : '') +
      // `izgara-2` DÜŞTÜ: kodlar modülü artık tam bağlantıyı taşıyor ve yarım
      // genişlikte tablo yatay kaydırmaya düşüyordu — kısaltılmış ya da
      // kaydırma ardında kalan bir bağlantı elle kopyalanamaz.
      b.modul('Ödemeler', '<div id="ortak-odemeler"></div>' +
        (sahip ? '<div id="ortak-odeme-form"></div>' : ''),
        b.etiket(b.sayi(odemeler.length) + ' kayıt'),
        { alt: 'hakediş ödemesi kaydı — mali işlem, ön-izli' });

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
        { ad: 'redemptionCount', baslik: 'Kullanım', hizala: 'sag', siralanir: true,
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
        { ad: 'amount', baslik: 'Tutar', hizala: 'sag', siralanir: true,
          bicim: function (o) {
            var birim = String(o.currency || 'USD').toUpperCase();
            return b.e(birim === 'USD' ? b.para(o.amount) : b.sayi(o.amount) + ' ' + birim);
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
          aciklama: 'Firebase custom claim ANINDA geçmez: ortağın ID jetonu yenilenene ' +
            'kadar (en çok 1 saat, ya da çıkış + yeniden giriş) eski hâl sürer. ' +
            'Denetim izine yazılır.',
          tehlike: !ac,
          onaylaMetin: ac ? 'Erişimi aç' : 'Erişimi kapat'
        }).then(function (r) {
          if (!r) return null;
          return RY.post(yol(id, '/access'), { grant: ac }).then(function () {
            b.toast(ac
              ? 'Erişim açıldı. Ortak, ID jetonu yenilenene kadar (en çok 1 saat) hâlâ ' +
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
          { ad: 'uid', etiket: 'Firebase hesabı (uid)', max: 128, otomatik: 'off',
            deger: p.uid || '', dogrula: uidDogrula,
            yardim: 'Kendi panosu ve kendi kodunu kullanma kapısı buna bağlı. ' +
              'Nereden: Kullanıcılar → e-posta ile ara → hesabı aç → kimlik ' +
              'kartındaki uid.' }
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
        { ad: 'currency', etiket: 'Para birimi', deger: 'TRY', zorunlu: true, max: 3, otomatik: 'off',
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
          // kullanıcıya formu kaybetmeden söyler.
          return Promise.reject(new Error('Geri alma kaydı için not zorunlu.'));
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

  RY.gorunumler.ortaklar = async function (icerik, args) {
    if (args && args[0]) return detay(icerik, args[0]);
    return liste(icerik);
  };

  RY.kirintiSaglayici.ortaklar = function (args) {
    var parcalar = [{ metin: 'Yönetim', href: '#/genel' }];
    if (args && args[0]) {
      parcalar.push({ metin: 'Ortaklar', href: '#/ortaklar' });
      parcalar.push({ metin: adOnbellek[args[0]] || 'Ortak' });
    } else parcalar.push({ metin: 'Ortaklar' });
    return parcalar;
  };

  RY.palet.eylemEkle({ ad: 'ortak-yeni', etiket: 'Yeni ortak ekle', aciklama: 'Affiliate kaydı',
    ikon: 'ortaklar', rol: 'owner', calistir: yeniOrtakAc });
})();

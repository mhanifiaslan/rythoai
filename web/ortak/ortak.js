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
 * Yönetim panelinin bileşen kitaplığı (bilesenler.js 53 KB) ve admin.css
 * (54 KB) BİLEREK yüklenmiyor; bu pano yedi KPI ve iki tablodan oluşuyor.
 * Ortak olan yalnız kimlik kurulumu (/assets/ry-auth.js) ve API katmanı
 * (/assets/ry-api.js) — o ikisi kopyalanmadı, paylaşıldı.
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

  /* ------------------------------------------------ küçük yardımcılar */

  function e(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function sayi(v) {
    var n = Number(v);
    if (v == null || !isFinite(n)) return '—';
    return n.toLocaleString('tr-TR');
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
    return (birim || '₺') + n.toLocaleString('tr-TR',
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
    return d.toLocaleDateString('tr-TR',
      { day: 'numeric', month: 'short', year: 'numeric' });
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
          girisHatasi('E-posta ya da şifre hatalı.');
        } else if (kod === 'auth/too-many-requests') {
          girisHatasi('Çok fazla deneme — biraz bekleyip tekrar dene.');
        } else if (kod === 'auth/invalid-email') {
          girisHatasi('Geçerli bir e-posta gir.');
        } else {
          girisHatasi('Giriş başarısız: ' + (kod || hata));
        }
      })
      .then(function () { dugme.disabled = false; });
  });

  /* Şifre sıfırlama: sonuç her durumda AYNI metin (hesap varlığı sızmaz). */
  $('sifre-unut').addEventListener('click', function () {
    girisHatasi('');
    var eposta = $('giris-eposta').value.trim();
    if (!eposta) { girisHatasi('Önce e-posta alanını doldur.'); return; }
    auth.sendPasswordResetEmail(eposta).catch(function () {})
      .then(function () {
        girisBilgi('E-posta kayıtlıysa sıfırlama bağlantısı gönderildi — ' +
          'spam kutusunu da kontrol et.');
      });
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
        girisHatasi('Pencere kapandı — tekrar dene.');
        return;
      }
      girisHatasi('Giriş başarısız: ' + (kod || hata));
    });
  });

  auth.getRedirectResult().catch(function (hata) {
    girisHatasi('Giriş başarısız: ' + ((hata && hata.code) || hata));
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

  function modul(baslik, ic, alt) {
    return '<section class="modul">' +
      '<div class="bas"><h2>' + e(baslik) + '</h2>' +
      (alt ? '<span class="alt">' + e(alt) + '</span>' : '') + '</div>' +
      '<div class="ic">' + ic + '</div></section>';
  }

  function kodDurumu(k) {
    if (k.active !== true) return '<span class="rozet">Pasif</span>';
    var son = tarihNesnesi(k.expiresAt);
    if (son && son.getTime() < Date.now()) {
      return '<span class="rozet dolmus">Süresi doldu</span>';
    }
    return '<span class="rozet aktif">Aktif</span>';
  }

  function kodlarTablosu(kodlar) {
    if (!kodlar.length) {
      return '<p class="bos-durum">Henüz kodun yok — Rytho ekibi açtığında ' +
        'burada görünür.</p>';
    }
    return '<div class="tablo-sar"><table class="tablo">' +
      '<caption class="sr-only">Kodların ve paylaşılabilir bağlantıları</caption>' +
      '<thead><tr>' +
      '<th scope="col">Kod</th>' +
      '<th scope="col" class="sag">Kullanım</th>' +
      '<th scope="col">Son gün</th>' +
      '<th scope="col">Durum</th>' +
      '<th scope="col">Paylaşılabilir bağlantı</th>' +
      '</tr></thead><tbody>' +
      kodlar.map(function (k, i) {
        var bag = PAYLASIM_TABANI + encodeURIComponent(k.code || '');
        var alanKimlik = 'bag-' + i;
        return '<tr>' +
          '<th scope="row" class="mono">' + e(k.code || '—') + '</th>' +
          '<td class="sag">' + e(sayi(k.redemptionCount || 0)) + '</td>' +
          '<td class="mono">' + e(k.expiresAt ? tarih(k.expiresAt) : '—') + '</td>' +
          '<td>' + kodDurumu(k) + '</td>' +
          '<td><div class="bag-satir">' +
          '<label class="sr-only" for="' + alanKimlik + '">' +
          e(k.code || '') + ' kodunun bağlantısı</label>' +
          '<input class="girdi mono" id="' + alanKimlik + '" readonly value="' + e(bag) + '">' +
          '<button type="button" class="buton ikincil kucuk" data-kopya="' + alanKimlik +
          '">Kopyala</button>' +
          '</div></td></tr>';
      }).join('') +
      '</tbody></table></div>';
  }

  function odemelerTablosu(odemeler) {
    if (!odemeler.length) {
      return '<p class="bos-durum">Henüz ödeme yapılmadı.</p>';
    }
    /* En yeni üstte: sunucu sıralama garantisi vermiyor (alt koleksiyon
       stream'i), sıralama burada yapılır. */
    var sirali = odemeler.slice().sort(function (a, b) {
      var ta = tarihNesnesi(a.at), tb = tarihNesnesi(b.at);
      return (tb ? tb.getTime() : 0) - (ta ? ta.getTime() : 0);
    });
    return '<div class="tablo-sar"><table class="tablo">' +
      '<caption class="sr-only">Sana yapılan ödemeler</caption>' +
      '<thead><tr>' +
      '<th scope="col">Tarih</th>' +
      '<th scope="col" class="sag">Tutar</th>' +
      '<th scope="col">Not</th>' +
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
    var bekleyenCumle = 'Bekleyen hakediş, satın almadan ' + OLGUNLASMA_GUN +
      ' gün sonra kendiliğinden kesinleşir: iade penceresi kapanmadan ödeme ' +
      'yapılmıyor. İade ya da erken sona erme olursa o hakediş iptal olur.';

    var html =
      '<div class="sayfa-bas">' +
      '<h1 tabindex="-1">' + e(d.name || 'Ortak panosu') + '</h1>' +
      '<p>' + (odulVar
        /* Ödül tutarını ortak DEĞİŞTİREMEZ; yazma ucu da yok. Ama bu sayı
           GÜNCEL oran, geçmişin oranı değil: `rewardTry` hakediş açılırken
           dokümana KOPYALANIYOR (partner_service modül docstring'i +
           open_qualification), yani oran sonradan değişirse eski hakedişler
           eski tutarla kalır. Bunu yazmazsak ortak "3 abone × ₺50 = ₺150
           olmalı, neden ₺90?" diye panoyu bozuk sanır — sayılar doğru,
           eksik olan cümleydi. */
        ? 'Yeni hakedişlerde abone başına ' + e(para(odulSayisi, '₺')) +
          ' — tutar panodan değiştirilemez. Her hakediş satış anındaki ' +
          'tutarı taşır; oran sonradan değişse bile geçmiş yeniden ' +
          'fiyatlanmaz, bu yüzden aşağıdaki toplamlar bu sayının tam katı ' +
          'olmak zorunda değil.'
        : 'Ödül tutarı henüz tanımlanmadı.') + '</p>' +
      '</div>' +

      /* Pasiflik ölçülmüş davranıştır (partner_service.open_qualification):
         kod kullanımı sürer, YENİ hakediş açılmaz, geçmiş durur. */
      (pasif ? '<div class="bant uyari">Hesabın şu anda <b>pasif</b>: ' +
        'kodların çalışmaya devam eder ama yeni hakediş açılmaz. Kesinleşen ' +
        'bakiyen olduğu gibi durur.</div>' : '') +

      /* Tutarsız ödül tutarı PASİFLİKLE AYNI sonucu veriyor ve bu ölçüldü:
         `open_qualification` geçersiz `rewardTry`de `_rewardi_dogrula`
         hatasını yutup False dönüyor — kod kullanılır, sayaç artar,
         hakediş AÇILMAZ. Yukarıdaki tek satırlık "tanımlanmadı" notu bu
         sonucu söylemiyordu; ortak huninin ilk basamağı artarken
         "Beklemede 0" görüp panoyu bozuk sanardı. */
      (!odulVar ? '<div class="bant uyari">Ödül tutarın henüz ' +
        '<b>tanımlanmadı</b>: kodların çalışır ve kullanım sayın artar, ama ' +
        'tutar girilene kadar yeni hakediş açılmaz. Rytho ekibiyle ' +
        'konuşman gerekiyor.</div>' : '') +

      '<section class="izgara-kpi" aria-label="Huni">' +
      kpi('Gelen kullanıcı', sayi(d.referredUsers || 0),
        'kodlarının kullanım toplamı') +
      kpi('Beklemede', sayi(d.pendingCount || 0),
        OLGUNLASMA_GUN + ' gün olgunlaşma') +
      kpi('Kesinleşen', sayi(d.qualifiedCount || 0), 'ödemeye hazır',
        Number(d.qualifiedCount) > 0) +
      '</section>' +

      '<section class="izgara-kpi" aria-label="Hakediş">' +
      kpi('Kesinleşen hakediş', para(d.earnedTry, '₺'), 'toplam kazanç', true) +
      kpi('Beklemede', para(d.pendingTry, '₺'),
        OLGUNLASMA_GUN + ' gün sonra kesinleşir') +
      kpi('Ödenen', para(d.paidTry, '₺'), 'sana aktarılan') +
      kpi('Bakiye', para(d.balanceTry, '₺'),
        Number(d.balanceTry) > 0 ? 'ödeme bekliyor' : 'kapalı',
        Number(d.balanceTry) > 0) +
      '</section>' +

      '<div class="bant bilgi">' + e(bekleyenCumle) + '</div>' +

      modul('Kodların', kodlarTablosu(kodlar),
        kodlar.length ? sayi(kodlar.length) + ' kod' : '') +

      modul('Ödeme geçmişi', odemelerTablosu(odemeler),
        'ödeme para birimi ' + odemeBirimi.trim()) +

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
      modul('Ödül nasıl işliyor',
        '<p class="dipnot">Getirdiğin kullanıcının <b>ilk ücretli aboneliği</b> ' +
        'için sabit bir ₺ tutar kazanırsın. Kullanıcı için indirim ya da ödül ' +
        'yoktur — bağlantıya dokunması yeter, kod yazmasına gerek kalmaz.</p>' +
        '<p class="dipnot">Deneme <i>başlatmak</i> ödül üretmez; deneme ücretli ' +
        'aboneliğe dönerse üretir. Yenileme, jeton paketi ve mağaza test ' +
        'alımları ödül üretmez. Kullanıcı başına en fazla bir hakediş açılır.</p>' +
        '<p class="dipnot">Kendi kodunu kendi hesabında kullanamazsın.</p>');

    $('pano-govde').innerHTML = html;
    duyur('Pano yüklendi');
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
  var GECICI_METIN = 'Pano şu an ulaşılamıyor. Bu geçici bir durum: ' +
    'oturumun açık, kodların ve hakedişlerin olduğu gibi duruyor.';

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
      'Tekrar dene</button></div>';
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
    duyur('Pano yükleniyor');
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
        ? RY.hataMetni(hata) : '';
      durumEkrani(gecici, gecici ? GECICI_METIN : RY.hataMetni(hata),
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
      toast('Bağlantı kopyalandı.', 'basari');
      duyur('Bağlantı kopyalandı');
    }
    function elle() {
      alan.focus();
      alan.select();
      var oldu = false;
      try { oldu = document.execCommand('copy'); } catch (yok) { oldu = false; }
      if (oldu) tamam();
      else {
        toast('Kopyalanamadı — bağlantı seçildi, Ctrl+C ile kopyalayabilirsin.', 'uyari');
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
      durumEkrani(true, GECICI_METIN,
        'Kimliğin doğrulanması için ağ bağlantısı gerekiyor — bağlantını ' +
        'kontrol edip tekrar dene.',
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

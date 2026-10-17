/* Panel kabuğu v3 (AD17): Firebase girişi + claim/rol + parametreli hash
   router (#/kullanicilar/{uid}/{sekme}?q=…) + yan menü (ray/çekmece) +
   kırıntı + Ctrl+K komut paleti + dikkat zili + sağlık noktası.

   YETKİ SUNUCUDA: buradaki claim kontrolü yalnız UX — claim'siz kullanıcı
   jenerik "bulunamadı" görür, backend zaten her isteği 403'ler. Sahte-404
   akışı v2'den aynen. */
(function () {
  'use strict';

  var RY = window.RY;
  var b = RY.b;

  /* Kimlik kurulumu ORTAK modülde: authDomain onarımı (aynı origin popup)
     ve App Check'in örnek başına etkinleştirilmesi ortak panosuyla
     birebir aynı olmak zorunda — bkz. /assets/ry-auth.js. İkinci örneğin
     adı burada 'yonetim'. */
  var auth = RY_authKur('yonetim');
  RY.auth = auth;

  /* ---------------- Rotalar ---------------- */

  var ROTALAR = [
    { ad: 'genel', baslik: 'Genel Bakış', ikon: 'panel' },
    { ad: 'kullanicilar', baslik: 'Kullanıcılar', ikon: 'kullanicilar' },
    { ad: 'gelir', baslik: 'Gelir & Abonelik', ikon: 'gelir' },
    { ad: 'kullanim', baslik: 'Kullanım & AI', ikon: 'ai' },
    { ad: 'bildirimler', baslik: 'Bildirimler', ikon: 'bildirim' },
    { ad: 'geribildirim', baslik: 'Geri bildirimler', ikon: 'geribildirim' },
    { ad: 'ortaklar', baslik: 'Ortaklar', ikon: 'ortaklar' },
    { ad: 'sistem', baslik: 'Sistem', ikon: 'sistem' }
  ];
  var BASLIKLAR = {};
  ROTALAR.forEach(function (r) { BASLIKLAR[r.ad] = r.baslik; });
  /* Eski yer imleri kırılmasın. */
  var TAKMA_ADLAR = { ekonomi: 'gelir', ai: 'kullanim' };
  RY.ROTALAR = ROTALAR;
  RY.BASLIKLAR = BASLIKLAR;
  RY.gorunumler = RY.gorunumler || {};

  function $(id) { return document.getElementById(id); }

  function goster(id) {
    ['bulunamadi', 'giris', 'uygulama'].forEach(function (ad) {
      $(ad).hidden = ad !== id;
    });
  }

  RY.yetkisiz = function () {
    auth.signOut().catch(function () {});
    goster('bulunamadi');
  };

  /* ---------------- Giriş ---------------- */

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

  /* Firebase hata kodu ("auth/network-request-failed") kullanıcıya
     gösterilmez — iç koddur ve İngilizcedir. Bilinenler Türkçe cümleye,
     gerisi genel cümleye düşer; ham kod konsolda kalır (teşhis için). */
  function girisHataMetni(kod) {
    if (window.console && kod) console.warn('giriş hatası:', kod);
    if (kod === 'auth/network-request-failed') return 'Bağlantı kurulamadı — ağını kontrol edip tekrar dene.';
    if (kod === 'auth/user-disabled') return 'Bu hesap devre dışı.';
    if (kod === 'auth/unauthorized-domain') return 'Bu adresten giriş yapılamıyor.';
    if (kod === 'auth/popup-blocked') return 'Giriş penceresi engellendi — tarayıcının açılır pencere iznini aç.';
    return 'Giriş yapılamadı — tekrar dene.';
  }

  /* Yetki YÖNTEMDEN değil admin claim'inden gelir; hata metinleri hesap
     varlığını ele vermez (mobil anti-enumeration duruşuyla aynı). */
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
          girisHatasi(girisHataMetni(kod));
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
      girisHatasi(girisHataMetni(kod));
    });
  });

  auth.getRedirectResult().catch(function (hata) {
    girisHatasi(girisHataMetni(hata && hata.code));
  });

  $('cikis').addEventListener('click', function () {
    auth.signOut().then(function () { goster('giris'); });
  });

  /* ---------------- Rol ---------------- */

  RY.rol = null;
  RY.sahipMi = function () { return RY.rol === 'owner'; };

  function rolAyarla(rol, kullanici) {
    RY.rol = rol || null;
    document.body.dataset.rol = rol || '';
    $('admin-rol').textContent = b.rolAdi(rol);
    if (kullanici) {
      $('admin-eposta').textContent = kullanici.email || '';
      $('admin-avatar').textContent = b.basHarfler(kullanici.displayName, kullanici.email);
      $('admin-eposta').setAttribute('title', kullanici.email || '');
    }
  }

  /* ---------------- Yan menü: ikonlar, ray, çekmece ---------------- */

  var kabuk = $('uygulama');
  var yanMenu = $('yan-menu');
  var YANMENU_ANAHTAR = 'ry.yanmenu';

  document.querySelectorAll('#yan-nav a').forEach(function (a) {
    a.insertAdjacentHTML('afterbegin', RY.ikon(a.getAttribute('data-ikon'), 20));
    var etiket = a.querySelector('.etiket').textContent;
    a.setAttribute('title', etiket);
    a.setAttribute('aria-label', etiket);
  });
  $('daralt').insertAdjacentHTML('afterbegin', RY.ikon('daralt', 18));
  $('cikis').insertAdjacentHTML('afterbegin', RY.ikon('cikis', 18));
  $('cekmece-ac').innerHTML = RY.ikon('menu', 20);
  $('palet-ac').querySelector('.ikon').innerHTML = RY.ikon('arama', 16);
  $('zil').insertAdjacentHTML('afterbegin', RY.ikon('zil', 20));

  function daraltUygula(dar) {
    kabuk.classList.toggle('daraltilmis', !!dar);
    var d = $('daralt');
    d.setAttribute('aria-label', dar ? 'Menüyü genişlet' : 'Menüyü daralt');
    d.setAttribute('title', dar ? 'Menüyü genişlet' : 'Menüyü daralt');
    d.querySelector('.etiket').textContent = dar ? 'Genişlet' : 'Menüyü daralt';
    $('cikis').setAttribute('title', 'Çıkış');
    $('cikis').setAttribute('aria-label', 'Çıkış');
  }
  try { daraltUygula(localStorage.getItem(YANMENU_ANAHTAR) === 'dar'); } catch (yok) { /* yok */ }
  $('daralt').addEventListener('click', function () {
    var dar = !kabuk.classList.contains('daraltilmis');
    daraltUygula(dar);
    try { localStorage.setItem(YANMENU_ANAHTAR, dar ? 'dar' : 'genis'); } catch (yok) { /* yok */ }
  });

  var darEkran = window.matchMedia('(max-width: 1080px)');
  var cekmeceOnceki = null;
  function cekmeceAc() {
    kabuk.classList.add('cekmece-acik');
    $('cekmece-ac').setAttribute('aria-expanded', 'true');
    cekmeceOnceki = document.activeElement;
    var ilk = yanMenu.querySelector('a, button');
    if (ilk) ilk.focus();
  }
  function cekmeceKapat() {
    if (!kabuk.classList.contains('cekmece-acik')) return;
    kabuk.classList.remove('cekmece-acik');
    $('cekmece-ac').setAttribute('aria-expanded', 'false');
    // Odak açan öğeye; o yoksa (programatik açılış) menü düğmesine döner.
    var hedef = (cekmeceOnceki && cekmeceOnceki !== document.body &&
                 document.contains(cekmeceOnceki)) ? cekmeceOnceki : $('cekmece-ac');
    if (hedef && hedef.offsetParent !== null) hedef.focus();
    cekmeceOnceki = null;
  }
  $('cekmece-ac').addEventListener('click', function () {
    if (kabuk.classList.contains('cekmece-acik')) cekmeceKapat(); else cekmeceAc();
  });
  $('perde').addEventListener('click', cekmeceKapat);
  yanMenu.addEventListener('click', function (ev) {
    if (ev.target.closest('a') && darEkran.matches) cekmeceKapat();
  });
  yanMenu.addEventListener('keydown', function (ev) {
    if (!kabuk.classList.contains('cekmece-acik')) return;
    if (ev.key === 'Escape') { ev.preventDefault(); cekmeceKapat(); return; }
    if (ev.key !== 'Tab') return;
    var liste = Array.prototype.filter.call(
      yanMenu.querySelectorAll('a[href], button:not([disabled])'),
      function (n) { return n.offsetParent !== null; });
    if (!liste.length) return;
    var ilk = liste[0], son = liste[liste.length - 1];
    if (ev.shiftKey && document.activeElement === ilk) { ev.preventDefault(); son.focus(); }
    else if (!ev.shiftKey && document.activeElement === son) { ev.preventDefault(); ilk.focus(); }
  });
  darEkran.addEventListener('change', function () { cekmeceKapat(); });

  /* ---------------- Rota çözümleme ---------------- */

  var mevcut = { ad: 'genel', args: [], params: {} };

  function rotaCozumle(hash) {
    var ham = (hash || location.hash || '#/genel').replace(/^#\/?/, '');
    var soruIsareti = ham.indexOf('?');
    var yol = soruIsareti >= 0 ? ham.slice(0, soruIsareti) : ham;
    var sorgu = soruIsareti >= 0 ? ham.slice(soruIsareti + 1) : '';
    var parcalar = yol.split('/').filter(Boolean).map(function (p) {
      try { return decodeURIComponent(p); } catch (yok) { return p; }
    });
    var ad = TAKMA_ADLAR[parcalar[0]] || parcalar[0] || 'genel';
    var params = {};
    if (sorgu) {
      sorgu.split('&').forEach(function (cift) {
        if (!cift) return;
        var i = cift.indexOf('=');
        var k = i >= 0 ? cift.slice(0, i) : cift;
        var v = i >= 0 ? cift.slice(i + 1) : '';
        try { k = decodeURIComponent(k); v = decodeURIComponent(v.replace(/\+/g, ' ')); } catch (yok) { /* ham */ }
        if (!k) return;
        if (params[k] !== undefined) {
          params[k] = [].concat(params[k], v);
        } else params[k] = v;
      });
    }
    return { ad: ad, args: parcalar.slice(1), params: params };
  }

  RY.rotaBagi = function (ad, args, params) {
    return '#/' + [ad].concat((args || []).map(function (a) {
      return encodeURIComponent(String(a));
    })).join('/') + RY.sorguDizesi(params || {});
  };
  RY.rotaParametreleri = function () { return Object.assign({}, mevcut.params); };
  RY.rotaMevcut = function () {
    return { ad: mevcut.ad, args: mevcut.args.slice(), params: Object.assign({}, mevcut.params) };
  };
  /* rotaYaz(ad, args, params, {sessiz:true}) — sessiz: URL güncellenir,
     görünüm yeniden çizilmez (süzgeç durumunu adres çubuğuna yazmak için). */
  RY.rotaYaz = function (ad, args, params, sec) {
    var bag = RY.rotaBagi(ad, args, params);
    if (sec && sec.sessiz) {
      history.replaceState(null, '', bag);
      mevcut = rotaCozumle(bag);
      return;
    }
    if (location.hash === bag) rota(); else location.hash = bag;
  };

  /* ---------------- Kırıntı ---------------- */

  RY.kirintiSaglayici = RY.kirintiSaglayici || {};

  /* kirinti([{metin, href}, …]) — sonuncusu geçerli sayfa (href'siz). */
  RY.kirinti = function (parcalar) {
    var kap = $('kirinti');
    if (!parcalar || !parcalar.length) {
      parcalar = [{ metin: 'Yönetim', href: '#/genel' }, { metin: BASLIKLAR[mevcut.ad] || 'Panel' }];
    }
    kap.innerHTML = parcalar.map(function (p, i) {
      var son = i === parcalar.length - 1;
      var ic = son || !p.href
        ? '<b' + (son ? ' aria-current="page"' : '') + '>' + b.e(p.metin) + '</b>'
        : '<a href="' + b.e(p.href) + '">' + b.e(p.metin) + '</a>';
      return (i ? '<span class="ayrac" aria-hidden="true">/</span>' : '') + ic;
    }).join('');
  };

  function varsayilanKirinti(r) {
    var saglayici = RY.kirintiSaglayici[r.ad];
    var parcalar = null;
    if (saglayici) {
      try { parcalar = saglayici(r.args, r.params); } catch (yok) { parcalar = null; }
    }
    if (!parcalar) {
      parcalar = [{ metin: 'Yönetim', href: '#/genel' }];
      if (r.args.length) {
        parcalar.push({ metin: BASLIKLAR[r.ad], href: '#/' + r.ad });
        parcalar.push({ metin: r.args[0] });
      } else parcalar.push({ metin: BASLIKLAR[r.ad] });
    }
    RY.kirinti(parcalar);
  }

  /* ---------------- Router ---------------- */

  var rotaSayaci = 0;
  var rotaDenetleyici = null;

  /* Her rota çizimi KENDİ kabına yazar ve kendi bağlamını taşır.

     NEDEN (yarış, ölçülen kusur): görünümler `await` sonrası
     `icerik.innerHTML` yazıyordu; sayaç yalnız router'ın kendi
     `then`ini koruyordu. Yavaş bir Gelir isteği sürerken Kullanıcılar'a
     geçilirse Gelir'in cevabı gelince Kullanıcılar ekranının ÜSTÜNE
     çiziliyordu — adres "kullanicilar" derken ekranda gelir. Tek tek her
     görünüme kontrol eklemek yetmez (biri unutulur), o yüzden iki katlı
     kapı merkezde:
     1. Kap: görünüm `#icerik`e değil, bu çizime ait bir alt kaba yazar. Yeni
        rota kabı DOM'dan çıkarır; eski görünüm geç gelse de ayrık bir
        düğüme yazar, ekrana hiçbir şey sızmaz.
     2. Bağlam: `{sinyal, aktif()}`. Yeni rota eski sinyali iptal eder,
        uçuştaki istekler kesilir; görünüm `await` sonrası `aktif()`e
        bakarak kırıntı/başlık gibi kap DIŞI yazımları da atlar.
     Kap `display: contents` (admin.css): düzen ve giriş animasyonu
     `#icerik`in doğrudan çocuklarıymış gibi işler. */
  function rota() {
    var r = rotaCozumle();
    if (!RY.gorunumler[r.ad]) { r.ad = 'genel'; r.args = []; }
    mevcut = r;
    var sira = ++rotaSayaci;
    if (rotaDenetleyici) rotaDenetleyici.abort();
    var denetleyici = rotaDenetleyici = new AbortController();
    var baglam = {
      sinyal: denetleyici.signal,
      aktif: function () { return sira === rotaSayaci && !denetleyici.signal.aborted; }
    };
    cekmeceKapat();
    paletKapat();
    zilKapat();

    document.querySelectorAll('#yan-nav a').forEach(function (a) {
      var aktif = a.getAttribute('href') === '#/' + r.ad;
      a.classList.toggle('aktif', aktif);
      if (aktif) a.setAttribute('aria-current', 'page');
      else a.removeAttribute('aria-current');
    });
    document.title = (BASLIKLAR[r.ad] || 'Panel') + ' — Rytho Yönetim';
    varsayilanKirinti(r);

    var icerik = $('icerik');
    icerik.setAttribute('aria-busy', 'true');
    var kap = document.createElement('div');
    kap.className = 'gorunum-kok';
    kap.innerHTML = b.iskelet();
    icerik.replaceChildren(kap);
    window.scrollTo(0, 0);

    Promise.resolve().then(function () {
      return RY.gorunumler[r.ad](kap, r.args, r.params, baglam);
    }).then(function () {
      if (!baglam.aktif()) return;
      icerik.setAttribute('aria-busy', 'false');
      rotaSonrasi(r);
    }).catch(function (hata) {
      if (!baglam.aktif()) return;
      icerik.setAttribute('aria-busy', 'false');
      // Yetkisiz: RY.yetkisiz jenerik ekrana geçti; iskeleti de kaldır ki
      // yeniden girişte yarım bir sayfa görünmesin.
      if (hata && hata.message === 'yetkisiz') { kap.innerHTML = ''; return; }
      // Görünüm hâlâ ekrandayken gelen iptal router'ın değil, görünümün
      // kendi işidir; eskiden burada sessizce dönülüyor ve iskelet sonsuza
      // dek dönüyordu. Tekrar denenebilir bir durum olarak gösterilir.
      kap.innerHTML = b.sayfaBaslik({ baslik: BASLIKLAR[r.ad] }) +
        b.hataDurum(hata && hata.iptal ? 'Yükleme yarıda kesildi.' : RY.hataMetni(hata));
      var tekrar = kap.querySelector('#tekrar-dene');
      if (tekrar) tekrar.addEventListener('click', rota);
      rotaSonrasi(r);
      if (window.console) console.error(hata);
    });
  }

  function rotaSonrasi(r) {
    var icerik = $('icerik');
    var h1 = icerik.querySelector('h1');
    var baslik = h1 ? h1.textContent.trim() : (BASLIKLAR[r.ad] || '');
    $('rota-duyuru').textContent = baslik + ' sayfası yüklendi';
    if (h1) {
      if (!h1.hasAttribute('tabindex')) h1.setAttribute('tabindex', '-1');
      h1.focus({ preventScroll: true });
    } else {
      icerik.focus({ preventScroll: true });
    }
    b.kivilcimlariCiz(icerik);
    b.canlandir(icerik);
  }
  window.addEventListener('hashchange', rota);
  RY.rotaYenile = rota;

  /* ---------------- Komut paleti (Ctrl+K) ---------------- */

  var paletEylemleri = [];
  var paletDiyalog = null;
  var paletKuyrugu = (RY.palet && RY.palet._kuyruk) || [];

  RY.palet = {
    ac: paletAc,
    kapat: paletKapat,
    /* eylemEkle({ad, etiket, aciklama, ikon, calistir(), rol:'owner'|null}) */
    eylemEkle: function (ey) {
      if (!ey || !ey.ad) return;
      paletEylemleri = paletEylemleri.filter(function (x) { return x.ad !== ey.ad; });
      paletEylemleri.push(ey);
    },
    eylemSil: function (ad) {
      paletEylemleri = paletEylemleri.filter(function (x) { return x.ad !== ad; });
    }
  };

  function paletKapat() { if (paletDiyalog) paletDiyalog.kapat(); }

  function paletAc() {
    if (paletDiyalog) return;
    var govde = b.el('<div class="palet-ic">' +
      '<div class="palet-girdi">' + RY.ikon('arama', 18) +
      '<input type="text" id="palet-girdi" role="combobox" aria-expanded="true" ' +
      'aria-autocomplete="list" aria-controls="palet-liste" autocomplete="off" ' +
      'spellcheck="false" placeholder="Kullanıcı, sayfa ya da eylem ara…" ' +
      'aria-label="Ara veya komut çalıştır"></div>' +
      '<div class="palet-sonuclar" id="palet-liste" role="listbox" aria-label="Sonuçlar"></div>' +
      '<div class="palet-alt"><span><kbd class="kbd">↑↓</kbd> gez</span>' +
      '<span><kbd class="kbd">Enter</kbd> aç</span><span><kbd class="kbd">Esc</kbd> kapat</span></div>' +
      '</div>');
    var girdi = govde.querySelector('input');
    var liste = govde.querySelector('.palet-sonuclar');
    var secenekler = [], secili = -1, sonQ = '';
    var kullanicilar = [], kullaniciYukleniyor = false;
    var zamanlayici = null, denetleyici = null;

    function ciz() {
      var q = b.kucult(girdi.value.trim());
      secenekler = [];
      var gruplar = [];
      var sayfalar = ROTALAR.filter(function (r) {
        return !q || b.kucult(r.baslik).indexOf(q) >= 0 || r.ad.indexOf(q) >= 0;
      }).map(function (r) {
        return { etiket: r.baslik, ikon: r.ikon, calistir: function () { location.hash = '#/' + r.ad; } };
      });
      if (sayfalar.length) gruplar.push({ ad: 'Sayfalar', liste: sayfalar });
      var eylemler = paletEylemleri.filter(function (ey) {
        if (ey.rol === 'owner' && !RY.sahipMi()) return false;
        return !q || b.kucult(ey.etiket).indexOf(q) >= 0 ||
          (ey.aciklama && b.kucult(ey.aciklama).indexOf(q) >= 0);
      }).map(function (ey) {
        return { etiket: ey.etiket, alt: ey.aciklama, ikon: ey.ikon || 'kivilcim',
                 calistir: ey.calistir };
      });
      if (eylemler.length) gruplar.push({ ad: 'Eylemler', liste: eylemler });
      if (kullanicilar.length) {
        gruplar.push({ ad: 'Kullanıcılar', liste: kullanicilar.map(function (u) {
          return { etiket: u.etiket, alt: u.alt, ikon: 'kullanici',
                   calistir: function () { location.hash = u.href; } };
        }) });
      } else if (kullaniciYukleniyor) {
        gruplar.push({ ad: 'Kullanıcılar', liste: [], not: 'Aranıyor…' });
      } else if (q.length >= 2) {
        gruplar.push({ ad: 'Kullanıcılar', liste: [], not: 'Eşleşen kullanıcı yok' });
      }
      var html = '', i = 0;
      gruplar.forEach(function (g) {
        html += '<div class="palet-grup" role="group" aria-label="' + b.e(g.ad) + '">' +
          '<div class="grup-ad" aria-hidden="true">' + b.e(g.ad) + '</div>';
        g.liste.forEach(function (s) {
          secenekler.push(s);
          html += '<div class="palet-satir" role="option" id="palet-sec-' + i +
            '" data-i="' + i + '" aria-selected="false">' + RY.ikon(s.ikon, 18) +
            '<span class="metin">' + b.e(s.etiket) +
            (s.alt ? '<span>' + b.e(s.alt) + '</span>' : '') + '</span></div>';
          i++;
        });
        if (g.not) html += '<div class="palet-bos">' + b.e(g.not) + '</div>';
        html += '</div>';
      });
      if (!secenekler.length && !gruplar.length) {
        html = '<div class="palet-bos">Sonuç yok</div>';
      }
      liste.innerHTML = html;
      secili = secenekler.length ? 0 : -1;
      vurgula();
    }

    function vurgula() {
      Array.prototype.forEach.call(liste.querySelectorAll('[role=option]'), function (n, j) {
        n.setAttribute('aria-selected', j === secili ? 'true' : 'false');
      });
      var aktif = liste.querySelector('[aria-selected="true"]');
      if (aktif) {
        girdi.setAttribute('aria-activedescendant', aktif.id);
        aktif.scrollIntoView({ block: 'nearest' });
      } else girdi.removeAttribute('aria-activedescendant');
    }

    function calistir(i) {
      var s = secenekler[i];
      if (!s) return;
      paletKapat();
      try { s.calistir(); } catch (h) { b.toast(RY.hataMetni(h) || String(h), 'hata'); }
    }

    function kullaniciAra(q) {
      if (denetleyici) denetleyici.abort();
      kullanicilar = [];
      if (q.length < 2) { kullaniciYukleniyor = false; ciz(); return; }
      denetleyici = new AbortController();
      kullaniciYukleniyor = true;
      var buDenetleyici = denetleyici;
      // Alan seçimi listeyle aynı sezgi: '@' içeriyorsa e-posta, '@' ile
      // başlıyorsa kullanıcı adı, değilse ad (kullanicilar.js alanSec).
      var alan = q.charAt(0) === '@' ? 'kullanici' : (q.indexOf('@') > 0 ? 'eposta' : 'ad');
      var qTemiz = alan === 'kullanici' ? q.slice(1) : q;
      RY.sorgu('/api/v1/admin/users', { q: qTemiz, alan: alan, limit: 8 }, { sinyal: buDenetleyici.signal })
        .then(function (res) {
          if (buDenetleyici.signal.aborted) return;
          var liste2 = Array.isArray(res) ? res : ((res && (res.users || res.items)) || []);
          kullanicilar = liste2.slice(0, 8).map(function (u) {
            var ad = u.displayName || u.name || u.username || u.email || u.uid;
            var alt = [u.email, u.username ? '@' + u.username : null]
              .filter(function (x) { return x && x !== ad; }).join(' · ');
            return { etiket: ad, alt: alt, href: '#/kullanicilar/' + encodeURIComponent(u.uid || u.id) };
          });
        })
        .catch(function () { /* iptal/ağ: sessiz */ })
        .then(function () {
          if (buDenetleyici.signal.aborted) return;
          kullaniciYukleniyor = false;
          ciz();
        });
    }

    girdi.addEventListener('input', function () {
      var q = girdi.value.trim();
      clearTimeout(zamanlayici);
      if (q !== sonQ) {
        sonQ = q;
        kullanicilar = [];
        // Debounce süresince "Aranıyor…" — "eşleşme yok" erken düşmesin.
        kullaniciYukleniyor = q.length >= 2;
        zamanlayici = setTimeout(function () { kullaniciAra(q); }, 250);
      }
      ciz();
    });
    girdi.addEventListener('keydown', function (ev) {
      if (ev.key === 'ArrowDown') { ev.preventDefault(); if (secenekler.length) { secili = (secili + 1) % secenekler.length; vurgula(); } }
      else if (ev.key === 'ArrowUp') { ev.preventDefault(); if (secenekler.length) { secili = (secili - 1 + secenekler.length) % secenekler.length; vurgula(); } }
      else if (ev.key === 'Enter') { ev.preventDefault(); calistir(secili); }
      else if (ev.key === 'Home' && ev.ctrlKey) { secili = 0; vurgula(); }
      else if (ev.key === 'End' && ev.ctrlKey) { secili = secenekler.length - 1; vurgula(); }
    });
    liste.addEventListener('click', function (ev) {
      var s = ev.target.closest('[role=option]');
      if (s) calistir(Number(s.getAttribute('data-i')));
    });
    liste.addEventListener('mousemove', function (ev) {
      var s = ev.target.closest('[role=option]');
      if (!s) return;
      var i = Number(s.getAttribute('data-i'));
      if (i !== secili) { secili = i; vurgula(); }
    });

    paletDiyalog = b.modal({
      etiket: 'Komut paleti', sinif: 'palet-kutu', icerik: govde,
      odak: '#palet-girdi',
      onKapat: function () {
        clearTimeout(zamanlayici);
        if (denetleyici) denetleyici.abort();
        paletDiyalog = null;
      }
    });
    paletDiyalog.ac();
    ciz();
  }

  $('palet-ac').addEventListener('click', paletAc);
  document.addEventListener('keydown', function (ev) {
    if ((ev.ctrlKey || ev.metaKey) && !ev.altKey && (ev.key === 'k' || ev.key === 'K')) {
      if ($('uygulama').hidden) return;
      ev.preventDefault();
      if (paletDiyalog) paletKapat(); else paletAc();
    }
  });

  paletKuyrugu.forEach(RY.palet.eylemEkle);
  RY.palet.eylemEkle({ ad: 'cikis', etiket: 'Çıkış yap', ikon: 'cikis',
    calistir: function () { $('cikis').click(); } });
  RY.palet.eylemEkle({ ad: 'menu-daralt', etiket: 'Menüyü daralt / genişlet', ikon: 'daralt',
    calistir: function () { $('daralt').click(); } });
  RY.palet.eylemEkle({ ad: 'yenile', etiket: 'Sayfayı yenile', ikon: 'yenile',
    calistir: function () { rota(); } });

  /* ---------------- Dikkat zili ---------------- */

  /* Kalem adları sözlükte (sozluk.js `dikkat`): zil ve Genel'deki Dikkat
     listesi aynı cümleyi okusun. Eskiden iki ayrı harita vardı ve aynı
     kalem zilde "Bayat rollup", Genel'de başka bir altyazıyla çıkıyordu. */
  function dikkatSablonu(k) { return RY.sozluk.dikkat(k); }

  RY.dikkat = { veri: null, maddeler: [] };

  /* Sunucu şekli (admin_service.attention): [{tur, sayi, rota, seviye}] —
     çıplak liste ya da {status:'ok', items|attention|kalemler:[…]} sargısı.
     Eski/alternatif alan adları (key/count/route/level) ve düz sayaç
     sözlüğü de kabul edilir; zil çizimi (sayaç, liste, bağlantı) değişmez. */
  function dikkatNormalize(res) {
    if (!res) return [];
    var kaynak = Array.isArray(res) ? res
      : (res.items || res.attention || res.kalemler || res.list || res.data || null);
    if (Array.isArray(kaynak)) {
      return kaynak.filter(function (m) { return m && typeof m === 'object'; }).map(function (m) {
        var anahtar = m.tur || m.key || m.kind || m.id || m.label;
        var sabl = dikkatSablonu(anahtar) || {};
        var sayi = m.sayi != null ? m.sayi : (m.count != null ? m.count : m.value);
        // Sözlükteki Türkçe ad önce: sunucu bir gün İngilizce `label`
        // gönderirse o yalnız sözlükte karşılığı olmayan kalemde görünür.
        return {
          anahtar: anahtar,
          etiket: sabl.etiket || m.label || m.title || m.etiket || (anahtar || 'Madde'),
          alt: sabl.alt || m.detail || m.description || m.alt || '',
          sayi: Number(sayi) || 0,
          href: m.rota || m.route || m.href || sabl.href || '#/genel',
          tur: m.seviye || m.level || m.severity || sabl.tur || 'bilgi'
        };
      });
    }
    return Object.keys(res).filter(function (k) { return k !== 'status'; }).map(function (k) {
      var sabl = dikkatSablonu(k);
      var v = res[k];
      var sayi = typeof v === 'number' ? v : (v && typeof v === 'object' ? Number(v.count) || 0 : (v === true ? 1 : 0));
      if (!sabl && typeof v !== 'number' && v !== true) return null;
      return { anahtar: k, etiket: (sabl && sabl.etiket) || k, alt: (sabl && sabl.alt) || '',
               sayi: sayi, href: (sabl && sabl.href) || '#/sistem', tur: (sabl && sabl.tur) || 'bilgi' };
    }).filter(Boolean);
  }

  function zilCiz(maddeler) {
    var aktif = maddeler.filter(function (m) { return m.sayi > 0; });
    var sayac = $('zil-sayac');
    sayac.textContent = aktif.length ? String(aktif.length) : '';
    $('zil').setAttribute('aria-label', aktif.length
      ? 'Dikkat: ' + aktif.length + ' madde' : 'Dikkat: bekleyen madde yok');
    var sistemSayisi = aktif.filter(function (m) { return /^#\/sistem/.test(m.href); }).length;
    $('sistem-sayac').textContent = sistemSayisi ? String(sistemSayisi) : '';
    $('zil-liste').innerHTML = aktif.length ? aktif.map(function (m) {
      return '<a href="' + b.e(m.href) + '"><span class="nokta ' + b.e(m.tur) + '"></span>' +
        '<span class="metin">' + b.e(m.etiket) + (m.alt ? '<span>' + b.e(m.alt) + '</span>' : '') +
        '</span><span class="sayi">' + b.e(b.sayi(m.sayi)) + '</span>' + RY.ikon('ok', 16) + '</a>';
    }).join('') : '<div class="palet-bos">Bekleyen madde yok</div>';
  }

  function dikkatYukle() {
    return RY.get('/api/v1/admin/attention').then(function (res) {
      RY.dikkat.veri = res;
      RY.dikkat.maddeler = dikkatNormalize(res);
      zilCiz(RY.dikkat.maddeler);
      document.dispatchEvent(new CustomEvent('ry:dikkat', { detail: RY.dikkat.maddeler }));
      return RY.dikkat.maddeler;
    }).catch(function () {
      // Uç yoksa/ düştüyse zil sessiz kalır — panel çalışmaya devam eder.
      RY.dikkat.maddeler = [];
      zilCiz([]);
      return [];
    });
  }
  RY.dikkat.yukle = dikkatYukle;

  function zilKapat() {
    $('zil-menu').hidden = true;
    $('zil').setAttribute('aria-expanded', 'false');
  }
  $('zil').addEventListener('click', function () {
    var acik = !$('zil-menu').hidden;
    if (acik) { zilKapat(); return; }
    $('zil-menu').hidden = false;
    $('zil').setAttribute('aria-expanded', 'true');
    var ilk = $('zil-menu').querySelector('a');
    if (ilk) ilk.focus();
  });
  document.addEventListener('click', function (ev) {
    if (!ev.target.closest('.zil-kap')) zilKapat();
  });
  document.addEventListener('keydown', function (ev) {
    if (ev.key === 'Escape' && !$('zil-menu').hidden) { zilKapat(); $('zil').focus(); }
  });

  /* ---------------- Sağlık ---------------- */

  function backendDurumu() {
    return RY.saglik('/health').then(function (res) {
      $('backend-nokta').className = 'durum-nokta iyi';
      var rev = res && (res.revision || res.rev || res.build);
      $('backend-durum').textContent = 'Sunucu çalışıyor';
      $('backend-satir').setAttribute('title', 'Sunucu çalışıyor' + (rev ? ' · sürüm ' + rev : ''));
    }).catch(function () {
      $('backend-nokta').className = 'durum-nokta kotu';
      $('backend-durum').textContent = 'Sunucuya erişilemiyor';
      $('backend-satir').setAttribute('title', 'Sunucuya erişilemiyor');
    });
  }

  /* ---------------- Oturum akışı ---------------- */

  var zamanlayicilar = null;
  function periyodikBasla() {
    if (zamanlayicilar) return;
    zamanlayicilar = [
      setInterval(backendDurumu, 5 * 60 * 1000),
      setInterval(dikkatYukle, 5 * 60 * 1000)
    ];
  }
  function periyodikDur() {
    (zamanlayicilar || []).forEach(clearInterval);
    zamanlayicilar = null;
  }

  auth.onAuthStateChanged(function (kullanici) {
    if (!kullanici) { periyodikDur(); goster('giris'); return; }
    kullanici.getIdTokenResult().then(function (sonuc) {
      var c = sonuc.claims || {};
      if (c.admin !== true) {
        // Claim yok: panelin varlığı ele verilmez — jenerik görünüm.
        RY.yetkisiz();
        return;
      }
      rolAyarla(c.role || (c.admin ? 'owner' : null), kullanici);
      goster('uygulama');
      // Sunucu teyidi: rol claim'i tazeyse aynı, değilse sunucununki kazanır.
      RY.get('/api/v1/admin/me').then(function (me) {
        if (me && me.role && me.role !== RY.rol) rolAyarla(me.role, kullanici);
      }).catch(function () { /* uç yoksa claim yeter */ });
      backendDurumu();
      dikkatYukle();
      periyodikBasla();
      rota();
    });
  });
})();

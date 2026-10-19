/* Kullanıcılar (AD19): imleçli liste (arama + alan çipleri + süzgeç
   çipleri + segmentler + owner CSV) ve Kullanıcı 360 (destek masası).

   Rotalar:
   - #/kullanicilar?q&alan&plan&language&platform&disabled&aktif&
     belowBuild&sort → liste. Süzgeç durumu adres çubuğuna SESSİZ yazılır
     (rotaYaz sessiz), yer imi/paylaşım çalışır. `aktif` GÖRELİ gün sayısıdır
     (7 | 30 …); uca giden `activeSince` tarihi istek anında ondan türetilir.
     Eski yer imlerindeki mutlak `activeSince=YYYY-AA-GG` okunur ve göreliye
     çevrilir.
   - #/kullanicilar/{uid}[/{sekme}] → 360; sekme ∈ ozet | abonelik |
     kullanim | bildirim | zaman | denetim (hash ile eşzamanlı).
   - #/kullanicilar/ara/{q} → eski üst-çubuk bağlantısı; listeye düşer.

   Uçlar:
   - GET  /api/v1/admin/users?q&alan&plan&language&platform&disabled&
     activeSince&belowBuild&sort&limit&cursor → {users:[{uid, displayName,
     email, username, plan, language, platform, appBuild, createdAt,
     lastSeenDaily, streakCount, authDisabled, onboardingCompleted,
     hasPush}], nextCursor, mode:'search'|'filter'}
   - GET  /api/v1/admin/min-build → {min_build} (eşik altı çipi)
   - GET  /api/v1/admin/users/{uid} → {profile, subscription, wallet,
     ledger, quota, attribution, device, notifications, revenueEvents,
     timeline, usage:{recent, calls, estCostUsd, byFeature, totals},
     revenueTotals, phoneAttempts, economics, counts}
   - POST /api/v1/admin/users/{uid}/credit {amount, reason}
   - POST /api/v1/admin/users/{uid}/device/release
   - POST /api/v1/admin/users/{uid}/auth-link {kind:'verify'|'reset'}
   - POST /api/v1/admin/users/{uid}/disable {disabled, reason} (owner)
   - DELETE /api/v1/admin/users/{uid} {confirm:'SIL', reason} (owner)
   - GET  /api/v1/admin/audit?targetUid&limit
   - GET  /api/v1/admin/users/export.csv?plan&language&platform&disabled&
     activeSince (owner)

   Mahremiyet: sunucu sohbet/hafıza İÇERİĞİ, fcmToken, ham telefon ve doğum
   verisi döndürmez; burada yalnız sayılar ve destek verisi çizilir.
   Sunucu sıralaması hep DESC; arama modunda alan sırası, aktiflik/eşik
   süzgeçlerinde ilgili alan sırası geçerlidir. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  var SAYFA = 50;
  var DENETIM_SAYFA = 50;
  var OTO_ATLAMA = 3;  // arama modunda boş sayfa gelirse en fazla bu kadar otomatik devam

  var BURC = { aries: '♈', taurus: '♉', gemini: '♊', cancer: '♋', leo: '♌', virgo: '♍',
               libra: '♎', scorpio: '♏', sagittarius: '♐', capricorn: '♑', aquarius: '♒', pisces: '♓' };
  var BURC_ADI = { aries: 'Koç', taurus: 'Boğa', gemini: 'İkizler', cancer: 'Yengeç', leo: 'Aslan',
                   virgo: 'Başak', libra: 'Terazi', scorpio: 'Akrep', sagittarius: 'Yay',
                   capricorn: 'Oğlak', aquarius: 'Kova', pisces: 'Balık' };
  function burc(kod) { return kod ? (BURC[String(kod).toLowerCase()] || '') : ''; }
  function burcAdi(kod) { return kod ? (BURC_ADI[String(kod).toLowerCase()] || String(kod)) : ''; }

  function S() { return RY.sozluk; }
  function dilAdi(k) { return S().dilAdi(k); }
  function platformAdi(k) { return S().platformAdi(k); }
  function ozellikAdi(k) { return S().ozellikAdi(k); }

  var ALANLAR = [['eposta', 'E-posta'], ['kullanici', 'Kullanıcı adı'], ['ad', 'Ad']];
  var PLANLAR = ['free', 'trial', 'plus'];
  var SIRALAMALAR = ['createdAt', 'lastSeenDaily', 'streakCount'];
  var SEKMELER = ['ozet', 'abonelik', 'kullanim', 'bildirim', 'zaman', 'denetim'];

  var ASAMA = { sent: ['gonder', 'Kod gönderildi'], auto: ['kivilcim', 'Otomatik doğrulandı'],
                verified: ['basari', 'Doğrulandı'], failed: ['hata', 'Hata'] };

  var adOnbellek = {};  // uid → görünen ad (kırıntı)

  function hataToast(h) {
    var m = RY.hataMetni(h);
    if (m) RY.b.toast(m, 'hata');
  }

  function alanSec(q) {
    if (q.charAt(0) === '@') return { alan: 'kullanici', q: q.slice(1) };
    if (q.indexOf('@') > 0) return { alan: 'eposta', q: q };
    return null;  // otomatik karar yok: seçili alan kalır
  }

  function gunOnce(n) {
    return new Date(Date.now() - n * 86400000).toISOString().slice(0, 10);
  }
  function gunFarki(tarihStr) {
    var d = RY.b.tarihNesnesi(tarihStr);
    return d ? Math.round((Date.now() - d.getTime()) / 86400000) : null;
  }

  function kullaniciYolu(uid, ek) {
    return '/api/v1/admin/users/' + encodeURIComponent(uid) + (ek || '');
  }

  function kisiHucresi(b, u) {
    var ad = u.displayName || u.email || u.uid;
    var alt = [u.displayName ? u.email : null, u.username ? '@' + u.username : null]
      .filter(Boolean).join(' · ') || (ad !== u.uid ? u.uid : '');
    return '<span class="vt-kimlik"><span class="avatar" aria-hidden="true">' +
      b.e(b.basHarfler(u.displayName, u.email)) + '</span><div>' + b.e(ad) +
      (u.sunSign ? ' <span title="' + b.e(burcAdi(u.sunSign)) + '">' + burc(u.sunSign) + '</span>' : '') +
      (alt ? '<span class="kimlik-alt">' + b.e(alt) + '</span>' : '') + '</div></span>';
  }

  /* =====================================================================
     LİSTE
     ===================================================================== */

  function durumOku(params) {
    params = params || {};
    var d = {
      q: String(params.q || '').trim(),
      alan: ALANLAR.some(function (a) { return a[0] === params.alan; }) ? params.alan : 'ad',
      plan: PLANLAR.indexOf(params.plan) >= 0 ? params.plan : undefined,
      language: params.language ? String(params.language).slice(0, 8) : undefined,
      platform: params.platform ? String(params.platform).slice(0, 16) : undefined,
      disabled: params.disabled === 'true' || params.disabled === '1' ? 'true' : undefined,
      aktif: aktiflikOku(params),
      belowBuild: Number(params.belowBuild) > 0 ? Math.round(Number(params.belowBuild)) : undefined,
      sort: SIRALAMALAR.indexOf(params.sort) >= 0 ? params.sort : undefined
    };
    if (params.q && !params.alan) {
      var oto = alanSec(d.q);
      if (oto) { d.alan = oto.alan; d.q = oto.q; }
    }
    return d;
  }

  /* Aktiflik süzgeci GÖRELİ saklanır (adres, segment). Eskiden çip
     "Son 7 gün"ü mutlak bir tarih olarak (`activeSince=2026-10-10`)
     yazıyordu: yer imi bir hafta sonra "son 14 gün" demeye başlıyor, çip
     ise o tarihi tanımayıp HİÇBİR durumu basılı göstermiyordu — süzgeç
     uygulanıyor ama görünmüyordu. Eski biçim okunur ve göreliye çevrilir. */
  function aktiflikOku(params) {
    var n = Number(params.aktif);
    if (n > 0 && n <= 365) return Math.round(n);
    if (/^\d{4}-\d{2}-\d{2}$/.test(params.activeSince || '')) {
      var fark = gunFarki(params.activeSince);
      if (fark != null && fark >= 0) return Math.max(1, Math.min(365, fark));
    }
    return undefined;
  }

  function paramsTemizle(d) {
    var p = {};
    if (d.q) { p.q = d.q; p.alan = d.alan; }
    ['plan', 'language', 'platform', 'disabled', 'aktif', 'belowBuild', 'sort'].forEach(function (k) {
      if (d[k] !== undefined && d[k] !== '' && d[k] !== null) p[k] = d[k];
    });
    return p;
  }

  /* Uca giden süzgeç: göreli aktiflik İSTEK ANINDA tarihe çevrilir. */
  function sorguSuzgeci(d) {
    var p = paramsTemizle(d);
    delete p.aktif;
    if (d.aktif) p.activeSince = gunOnce(d.aktif);
    return p;
  }

  function cipDegeri(d) {
    return {
      plan: d.plan, language: d.language, platform: d.platform, disabled: d.disabled,
      aktif: d.aktif ? String(d.aktif) : undefined,
      esik: d.belowBuild ? String(d.belowBuild) : undefined
    };
  }

  async function liste(icerik, params, baglam) {
    var b = RY.b;
    var sahip = RY.sahipMi();
    var durum = durumOku(params);
    var imlec = null, bekleyici = null, mod = null, istek = null;
    var yeniIstek = b.tazeleyici(baglam);

    var mb = await RY.get('/api/v1/admin/min-build').catch(function () { return null; });
    if (baglam && !baglam.aktif()) return;
    var minBuild = mb && Number(mb.min_build) > 0 ? Number(mb.min_build) : 0;

    var eylemler = '<button type="button" class="buton ikincil" id="kul-segment-kaydet">' + b.ik('yildiz', 16) + 'Segmenti kaydet</button>' +
      (sahip ? '<button type="button" class="buton ikincil" id="kul-csv">' + b.ik('indir', 16) + 'CSV indir</button>' : '');

    icerik.innerHTML =
      b.sayfaBaslik({ baslik: 'Kullanıcılar', alt: 'Ada, e-postaya ya da @kullanıcı adına göre ara; süzgeçlerle daralt.',
        eylemlerHtml: eylemler }) +
      '<div class="suzgec" id="kul-arama">' +
      '<label class="ara">' + b.ik('arama', 16) + '<input id="kul-ara" type="search" autocomplete="off" spellcheck="false" ' +
      'placeholder="Ad, e-posta ya da @kullanıcıadı" aria-label="Kullanıcı ara" value="' +
      b.e(durum.q ? (durum.alan === 'kullanici' ? '@' + durum.q : durum.q) : '') + '"></label>' +
      '<span class="dipnot" id="kul-mod" aria-live="polite"></span>' +
      '</div>' +
      '<div id="kul-filtre"></div>' +
      '<div id="kul-segment"></div>' +
      b.modul('Kullanıcılar', '<div id="kul-tablo"></div>', '<span class="dipnot" id="kul-sayac"></span>',
        { alt: 'Ayrıntı için satıra dokun' }) +
      '<p class="dipnot">Arama ile süzgeç birlikteyken sonuçlar sayfa sayfa gelir; boş sayfada "Daha fazla" ' +
      'aramayı sürdürür. Sürüm süzgeci tek başına çalışır. CSV aramayı ve sürüm süzgecini içermez.</p>';

    var modEl = icerik.querySelector('#kul-mod');
    var sayacEl = icerik.querySelector('#kul-sayac');

    /* ---- Tablo ---- */
    var vt = b.veriTablosu({
      kimlik: 'kul-vt', etiket: 'Kullanıcılar', yogunluk: 'sik',
      sutunlar: [
        { ad: 'displayName', baslik: 'Kullanıcı', deger: function (u) { return u.displayName || u.email || u.uid; },
          bicim: function (u) { return kisiHucresi(b, u); } },
        { ad: 'plan', baslik: 'Plan', bicim: function (u) {
          return b.planRozeti(u.plan, u.createdAt) +
            (u.authDisabled ? ' ' + b.rozet('Devre dışı', 'hata') : '') +
            (u.onboardingCompleted === false ? ' ' + b.rozet('Kurulum yarım', 'uyari') : '');
        } },
        { ad: 'language', baslik: 'Dil', bicim: function (u) { return b.e(dilAdi(u.language)); } },
        { ad: 'platform', baslik: 'Platform', bicim: function (u) { return b.e(platformAdi(u.platform)); } },
        { ad: 'appBuild', baslik: 'Sürüm', hizala: 'sag', bicim: function (u) {
          if (u.appBuild == null) return '<span class="dipnot">—</span>';
          var altinda = minBuild && Number(u.appBuild) < minBuild;
          return '<span class="mono">' + b.e(String(u.appBuild)) + '</span>' + (altinda ? ' ' + b.rozet('eşik altı', 'uyari') : '');
        } },
        { ad: 'createdAt', baslik: 'Kayıt', siralanir: true, bicim: function (u) { return b.e(b.tarih(u.createdAt)); } },
        { ad: 'lastSeenDaily', baslik: 'Son görülme', siralanir: true, bicim: function (u) {
          if (!u.lastSeenDaily) return '<span class="dipnot">—</span>';
          return '<span title="' + b.e(b.tarih(u.lastSeenDaily, true)) + '">' + b.e(b.goreliZaman(u.lastSeenDaily)) + '</span>';
        } },
        { ad: 'streakCount', baslik: 'Seri', hizala: 'sag', siralanir: true,
          bicim: function (u) { return b.e(b.sayi(Number(u.streakCount) || 0)); } },
        { ad: 'hasPush', baslik: 'Bildirim', bicim: function (u) { return u.hasPush ? b.rozet('alıyor', 'aktif') : b.rozet('almıyor', 'notr'); } }
      ],
      anahtar: function (u) { return u.uid; },
      satirHref: function (u) { return RY.rotaBagi('kullanicilar', [u.uid]); },
      satirSinif: function (u) {
        if (u.authDisabled) return 'durum-pasif';
        if (minBuild && u.appBuild != null && Number(u.appBuild) < minBuild) return 'durum-uyari';
        return '';
      },
      siralama: { ad: durum.sort || 'createdAt', yon: 'desc' },
      tekYon: true, // sunucu yalnız DESC (admin_service.list_users)
      onSirala: function (ad) {
        if (SIRALAMALAR.indexOf(ad) < 0) return;
        durum.sort = ad === 'createdAt' ? undefined : ad;
        urlYaz(); yukle(false);
      },
      bosMetin: 'Eşleşen kullanıcı yok — aramayı kısalt ya da süzgeci gevşet.',
      onTekrar: function () { yukle(false); }
    });
    icerik.querySelector('#kul-tablo').appendChild(vt.el);

    /* Boş sonuç metni ETKİN süzgeci söyler: "kayıt yok" ile "bu süzgeçte
       kayıt yok" farklı teşhislerdir. */
    function bosMetni() {
      var parcalar = [];
      if (durum.q) parcalar.push('"' + durum.q + '" araması');
      if (durum.plan) parcalar.push(S().planAdi(durum.plan));
      if (durum.language) parcalar.push(dilAdi(durum.language));
      if (durum.platform) parcalar.push(platformAdi(durum.platform));
      if (durum.disabled) parcalar.push('devre dışı');
      if (durum.aktif) parcalar.push('son ' + durum.aktif + ' günde aktif');
      if (durum.belowBuild) parcalar.push('sürüm < ' + durum.belowBuild);
      return parcalar.length
        ? 'Bu süzgeçle eşleşen kullanıcı yok (' + parcalar.join(' · ') + ') — aramayı kısalt ya da süzgeci gevşet.'
        : 'Henüz kullanıcı yok.';
    }

    function urlYaz() {
      RY.rotaYaz('kullanicilar', [], paramsTemizle(durum), { sessiz: true });
    }

    function yukle(devam, atlama) {
      // Yeni sorgu bir öncekini iptal eder; "Daha fazla" aynı sorgunun
      // devamıdır, kendi isteğini iptal etmez.
      if (!devam) { imlec = null; vt.durum('yukleniyor'); istek = yeniIstek(); }
      var bu = istek;
      var p = Object.assign(sorguSuzgeci(durum), { limit: SAYFA, cursor: devam ? imlec : null });
      return RY.sorgu('/api/v1/admin/users', p, { sinyal: bu.sinyal }).then(function (res) {
        if (!bu.gecerli()) return;
        var satirlar = Array.isArray(res && res.users) ? res.users : [];
        imlec = (res && res.nextCursor) || null;
        mod = (res && res.mode) || null;
        satirlar.forEach(function (u) { adOnbellek[u.uid] = u.displayName || u.email || u.uid; });
        var sayfa = { daha: !!imlec, onDaha: function () { return yukle(true, 0); } };
        if (devam) vt.ekle(satirlar, sayfa); else vt.guncelle(satirlar, sayfa);
        if (!devam && !satirlar.length && !imlec) vt.durum('bos', bosMetni());
        var n = vt.satirlar().length;
        sayacEl.textContent = n ? b.sayi(n) + ' satır' + (imlec ? ' · devamı var' : '') : '';
        var alanAdi = ((ALANLAR.filter(function (a) { return a[0] === durum.alan; })[0] || [])[1] || '').toLocaleLowerCase('tr-TR');
        modEl.textContent = mod === 'search' ? alanAdi + ' içinde aranıyor' : '';
        // Arama yapılırken süzgeç sayfa içinde uygulanır: boş sayfa + imleç → kendiliğinden devam.
        if (!satirlar.length && imlec && (atlama || 0) < OTO_ATLAMA) return yukle(true, (atlama || 0) + 1);
      }).catch(function (h) {
        if (!bu.gecerli() || (h && h.iptal)) return;
        if (devam) hataToast(h); else vt.durum('hata', RY.hataMetni(h));
      });
    }

    /* ---- Arama ---- */
    var ara = icerik.querySelector('#kul-ara');
    /* Arama alanı BİÇİMDEN anlaşılır: "@ad" kullanıcı adı, "a@b" e-posta,
       gerisi görünen ad. Eskiden ayrıca "Alan: E-posta / Kullanıcı adı /
       Ad" çipleri vardı; çip ile biçim çeliştiğinde (çip "Ad"da, yazılan
       e-posta) hangisinin geçerli olduğu ekrandan okunmuyordu (sahip,
       2026-10-19). Tek kural, tek kaynak. */
    function aramaUygula() {
      var ham = ara.value.trim();
      var oto = alanSec(ham) || { alan: 'ad', q: ham };
      durum.alan = oto.alan; durum.q = oto.q;
      urlYaz(); yukle(false);
    }
    ara.addEventListener('input', function () {
      clearTimeout(bekleyici);
      bekleyici = setTimeout(aramaUygula, 300);
    });
    ara.addEventListener('keydown', function (ev) {
      if (ev.key === 'Enter') { ev.preventDefault(); clearTimeout(bekleyici); aramaUygula(); }
    });

    /* ---- Süzgeç çipleri ----
       Seçenekler DURUMDAN kurulur ve durum değişince yeniden kurulur:
       adresten ya da segmentten gelen bir değer (ör. "son 14 gün", "sürüm
       < 40") sabit listede yoksa çip HİÇ basılı görünmüyordu — süzgeç
       uygulanıyor ama ekranda izi yoktu. Artık o değer kendi adıyla bir
       çip olarak görünür ve kapatılabilir. */
    var filtreKap = icerik.querySelector('#kul-filtre');
    var cipler = null;
    function cipSecenekleri() {
      var aktifSec = [7, 30];
      if (durum.aktif && aktifSec.indexOf(durum.aktif) < 0) aktifSec.push(durum.aktif);
      var esikEtiket = durum.belowBuild && durum.belowBuild !== minBuild
        ? 'Sürüm < ' + durum.belowBuild
        : (minBuild ? 'Eşik altı (< ' + minBuild + ')' : 'Eşik altı (eşik yok)');
      // Dil: uygulamanın arayüz dili yalnız tr/en (`backend/core/i18n.py`
      // SUPPORTED). Yedi dillik sözlük listesi süzgeçte sıfır sonuç veren
      // beş seçenek basıyordu. Adresten başka bir değer gelirse görünür
      // kalsın diye listeye eklenir (izsiz süzgeç olmasın).
      var diller = ['tr', 'en'];
      if (durum.language && diller.indexOf(durum.language) < 0) diller.push(durum.language);
      var liste = [
        { ad: 'plan', etiket: 'Plan', secenekler: ['plus', 'trial', 'free'].map(function (k) { return { deger: k, etiket: S().planAdi(k) }; }) },
        { ad: 'language', etiket: 'Dil', secenekler: diller.map(function (k) { return { deger: k, etiket: S().dilAdi(k) }; }) },
        { ad: 'platform', etiket: 'Platform', secenekler: ['android', 'ios'].map(function (k) { return { deger: k, etiket: platformAdi(k) }; }) },
        { ad: 'disabled', etiket: 'Durum', secenekler: [{ deger: 'true', etiket: 'Devre dışı' }] },
        { ad: 'aktif', etiket: 'Aktiflik', altin: true, secenekler: aktifSec.map(function (n) { return { deger: String(n), etiket: 'Son ' + n + ' gün' }; }) },
        { ad: 'esik', etiket: 'Sürüm', secenekler: [{ deger: String(durum.belowBuild || minBuild || 1), etiket: esikEtiket }] }
      ];
      // Zorunlu güncelleme eşiği yokken "Eşik altı (eşik yok)" seçilince
      // yalnız bir uyarı veriyordu — hiçbir şey süzmeyen seçenek gösterilmez.
      return (minBuild || durum.belowBuild) ? liste
        : liste.filter(function (f) { return f.ad !== 'esik'; });
    }
    function cipleriKur() {
      var odak = cipler && cipler.contains(document.activeElement)
        ? { f: document.activeElement.getAttribute('data-filtre'), d: document.activeElement.getAttribute('data-deger') } : null;
      var yeni = b.suzgecSecicileri({ etiket: 'Süzgeçler', filtreler: cipSecenekleri(), deger: cipDegeri(durum), onDegis: cipDegisti });
      if (cipler) cipler.replaceWith(yeni); else filtreKap.appendChild(yeni);
      cipler = yeni;
      if (odak) {
        var hedef = cipler.querySelector('[data-filtre="' + odak.f + '"]');
        if (hedef) hedef.focus();
      }
    }
    function cipDegisti(d) {
      var esikOnce = durum.belowBuild;
      durum.plan = d.plan; durum.language = d.language; durum.platform = d.platform;
      durum.disabled = d.disabled === 'true' ? 'true' : undefined;
      durum.aktif = d.aktif ? Number(d.aktif) : undefined;
      if (d.esik && !esikOnce && !minBuild) {
        b.toast('Zorunlu güncelleme eşiği 0 — eşik altı süzgeci anlamsız. Sistem sayfasından eşik yaz.', 'uyari');
        durum.belowBuild = undefined;
      } else if (d.esik) {
        durum.belowBuild = esikOnce || minBuild;
      } else durum.belowBuild = undefined;
      // Sunucu kuralı: eşik altı süzgeci (sürüm aralığı) BAŞKA hiçbir
      // süzgeçle birleşmez (veritabanı tek aralık + dizin). Eşik seçilince
      // diğerleri düşer; başka bir süzgeç seçilince eşik düşer.
      if (durum.belowBuild && (durum.plan || durum.language || durum.platform ||
          durum.disabled || durum.aktif)) {
        b.toast('Eşik altı süzgeci tek başına çalışır — diğer süzgeçler kaldırıldı.', 'uyari');
        if (esikOnce) {
          durum.belowBuild = undefined;
        } else {
          durum.plan = durum.language = durum.platform = undefined;
          durum.disabled = durum.aktif = undefined;
        }
      }
      cipleriKur();
      urlYaz(); yukle(false);
    }
    cipleriKur();

    /* ---- Segmentler (localStorage) ---- */
    var segKap = icerik.querySelector('#kul-segment');
    function segmentCiz() {
      var liste = b.segmentler.oku();
      if (!liste.length) { segKap.innerHTML = ''; return; }
      segKap.innerHTML = '<span class="cip-grup" role="group" aria-label="Kayıtlı segmentler">' +
        '<span class="grup-ad" aria-hidden="true">Segmentler</span>' + liste.map(function (s) {
          return '<button type="button" class="adm-cip" data-segment="' + b.e(s.ad) + '" title="' +
            b.e(segmentOzeti(s.filtre) || 'süzgeçsiz') + '">' +
            b.ik('yildiz', 14) + b.e(s.ad) + '</button>' +
            '<button type="button" class="adm-cip" data-segment-sil="' + b.e(s.ad) + '" aria-label="Segmenti sil: ' + b.e(s.ad) + '"><span class="x" aria-hidden="true">×</span></button>';
        }).join('') + '</span>';
    }
    segKap.addEventListener('click', function (ev) {
      var sil = ev.target.closest('[data-segment-sil]');
      if (sil) {
        b.segmentler.sil(sil.getAttribute('data-segment-sil'));
        segmentCiz();
        b.toast('Segment silindi.', 'bilgi');
        var ilk = segKap.querySelector('[data-segment]');
        (ilk || icerik.querySelector('#kul-segment-kaydet')).focus();
        return;
      }
      var d = ev.target.closest('[data-segment]');
      if (!d) return;
      var s = b.segmentler.oku().filter(function (x) { return x.ad === d.getAttribute('data-segment'); })[0];
      if (!s) return;
      durum = durumOku(s.filtre || {});
      ara.value = durum.q ? (durum.alan === 'kullanici' ? '@' + durum.q : durum.q) : '';
      cipleriKur();
      urlYaz(); yukle(false);
    });
    icerik.querySelector('#kul-segment-kaydet').addEventListener('click', function () {
      var f = b.form({
        alanlar: [{ ad: 'ad', etiket: 'Segment adı', zorunlu: true, max: 40, otomatik: 'off',
          yardim: 'Geçerli arama + süzgeçler bu tarayıcıda saklanır (en fazla 30).',
          dogrula: function (v) { return v.trim().length < 2 ? 'En az 2 karakter.' : null; } }],
        gonderMetin: 'Kaydet',
        iptal: { metin: 'Vazgeç', onTikla: function () { m.kapat(); } },
        onGonder: function (d) {
          b.segmentler.kaydet(d.ad.trim(), paramsTemizle(durum));
          segmentCiz();
          b.toast('Segment kaydedildi: ' + d.ad.trim(), 'basari');
          m.kapat();
        }
      });
      var m = b.modal({ baslik: 'Segmenti kaydet', icerik: f.el, genislik: 440 });
      m.ac();
    });
    segmentCiz();

    /* Segment ipucu Türkçe: "plan=plus · aktif=7" yerine "Plan: Rytho+ · Son 7 gün aktif". */
    function segmentOzeti(f) {
      var d = durumOku(f || {});
      var p = [];
      if (d.q) p.push('Arama: ' + d.q);
      if (d.plan) p.push('Plan: ' + S().planAdi(d.plan));
      if (d.language) p.push('Dil: ' + dilAdi(d.language));
      if (d.platform) p.push('Platform: ' + platformAdi(d.platform));
      if (d.disabled) p.push('Devre dışı');
      if (d.aktif) p.push('Son ' + d.aktif + ' gün aktif');
      if (d.belowBuild) p.push('Sürüm < ' + d.belowBuild);
      return p.join(' · ');
    }

    /* ---- CSV (owner) ---- */
    var csv = icerik.querySelector('#kul-csv');
    if (csv) csv.addEventListener('click', function () { csvIndir(durum); });

    yukle(false);
  }

  function csvIndir(durum) {
    var b = RY.b;
    var p = { plan: durum.plan, language: durum.language, platform: durum.platform,
              disabled: durum.disabled, activeSince: durum.aktif ? gunOnce(durum.aktif) : undefined };
    var gun = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    var t = b.toast('CSV hazırlanıyor…', 'bilgi', { sure: 0 });
    return RY.indir('/api/v1/admin/users/export.csv' + RY.sorguDizesi(p), 'rytho-kullanicilar-' + gun + '.csv')
      .then(function (r) {
        t.kapat();
        b.toast('CSV indirildi' + (r && r.boyut ? ' · ' + b.sayi(Math.round(r.boyut / 1024)) + ' KB' : '') +
          (durum.q || durum.belowBuild ? ' (arama ve eşik süzgeci CSV\'ye girmez)' : ''), 'basari', { sure: 7000 });
      }).catch(function (h) { t.kapat(); hataToast(h); });
  }
  RY.palet.eylemEkle({ ad: 'kullanicilar-csv', etiket: 'Kullanıcı CSV\'si indir', aciklama: 'süzgeçsiz · tüm kullanıcılar',
    ikon: 'indir', rol: 'owner', calistir: function () { return csvIndir({}); } });

  /* =====================================================================
     360 — eylemler
     ===================================================================== */

  function krediVerAc(uid, ad) {
    var b = RY.b;
    var f = b.form({
      alanlar: [
        { ad: 'amount', etiket: 'Kredi', tur: 'number', zorunlu: true, min: 1, max: 5000, adim: '1',
          yardim: '1–5000 · yalnız pozitif (düşüm bilerek yok)',
          dogrula: function (v) {
            var n = Number(v);
            return (!isFinite(n) || n < 1 || n > 5000 || n !== Math.round(n)) ? '1–5000 arası tam sayı.' : null;
          } },
        { ad: 'reason', etiket: 'Gerekçe', tur: 'textarea', zorunlu: true, max: 300, satir: 2,
          yardim: 'Cüzdan defterine ve denetim izine yazılır (en az 3 karakter).',
          dogrula: function (v) { return v.trim().length < 3 ? 'En az 3 karakter.' : null; } }
      ],
      gonderMetin: 'Kredi ver',
      iptal: { metin: 'Vazgeç', onTikla: function () { m.kapat(); } },
      onGonder: function (d) {
        var tutar = Math.round(Number(d.amount));
        return RY.post(kullaniciYolu(uid, '/credit'), { amount: tutar, reason: d.reason.trim() }).then(function (res) {
          var c = (res && res.wallet) || null;
          b.toast(b.sayi(tutar) + ' kredi verildi' + (c ? ' · bakiye ' + b.sayi((Number(c.allowance) || 0) + (Number(c.purchased) || 0)) : ''), 'basari');
          m.kapat();
          RY.rotaYenile();
        });
      }
    });
    var m = b.modal({ baslik: 'Kredi ver — ' + ad, icerik: f.el, genislik: 480 });
    m.ac();
  }

  function cihazSifirla(uid, cihaz) {
    var b = RY.b;
    return b.onayla({
      baslik: 'Cihaz kilidini sıfırla',
      mesaj: 'Cihaz kaydı (' + (cihaz && cihaz.deviceId ? cihaz.deviceId : 'yok') + ') silinir; bir sonraki korumalı isteği ' +
        'yapan cihaz kilidi sessizce yeniden alır. "Hesabın başka cihazda açıldı" ekranından çıkamayan kullanıcı için.',
      aciklama: 'Geri alınabilir: kullanıcı yeniden sahiplenir. Denetim izine yazılır; gerekçe yalnız panelde kalır.',
      gerekce: true, onaylaMetin: 'Sıfırla'
    }).then(function (r) {
      if (!r) return null;
      return RY.post(kullaniciYolu(uid, '/device/release'), {}).then(function (res) {
        b.toast(res && res.released ? 'Cihaz kilidi sıfırlandı.' : 'Kayıtlı cihaz yoktu; kilit zaten boştu.', 'basari');
        RY.rotaYenile();
      });
    }).catch(hataToast);
  }

  function baglantiAc(uid, eposta) {
    var b = RY.b;
    var govde = b.el('<div></div>');
    var sonuc = b.el('<div hidden><div class="form-alan"><label for="bl-link">Bağlantı (tek kullanımlık)</label>' +
      '<input class="girdi mono" id="bl-link" readonly spellcheck="false"></div>' +
      '<div class="eylem-satir"><button type="button" class="buton" id="bl-kopyala">' + b.ik('kopyala', 16) + 'Kopyala</button>' +
      '<span class="dipnot">E-posta GÖNDERİLMEZ — bağlantıyı kullanıcıya kendi kanalından ilet. İze yalnız türü düşer.</span></div></div>');
    var f = b.form({
      alanlar: [
        { ad: 'kind', etiket: 'Bağlantı türü', tur: 'select', deger: 'reset',
          secenekler: [{ deger: 'reset', etiket: 'Şifre sıfırlama' }, { deger: 'verify', etiket: 'E-posta doğrulama' }],
          yardim: eposta ? 'Hedef: ' + eposta : 'Hesabın e-postası yok — bağlantı üretilemez.' }
      ],
      gonderMetin: 'Bağlantı üret',
      iptal: { metin: 'Kapat', onTikla: function () { m.kapat(); } },
      onGonder: function (d) {
        return RY.post(kullaniciYolu(uid, '/auth-link'), { kind: d.kind }).then(function (res) {
          var link = (res && res.link) || '';
          sonuc.hidden = false;
          var girdi = sonuc.querySelector('#bl-link');
          girdi.value = link;
          girdi.focus(); girdi.select();
          b.toast('Bağlantı üretildi (' + (d.kind === 'verify' ? 'doğrulama' : 'şifre sıfırlama') + ').', 'basari');
        });
      }
    });
    govde.appendChild(f.el);
    govde.appendChild(sonuc);
    sonuc.querySelector('#bl-kopyala').addEventListener('click', function () {
      var girdi = sonuc.querySelector('#bl-link');
      var yaz = navigator.clipboard && navigator.clipboard.writeText
        ? navigator.clipboard.writeText(girdi.value) : Promise.reject(new Error('pano-yok'));
      yaz.then(function () { b.toast('Bağlantı panoya kopyalandı.', 'basari'); })
        .catch(function () { girdi.focus(); girdi.select(); b.toast('Pano erişimi yok — metni elle kopyala.', 'uyari'); });
    });
    var m = b.modal({ baslik: 'Şifre / doğrulama bağlantısı', icerik: govde, genislik: 520 });
    m.ac();
  }

  function durumDegistir(uid, ad, kapat) {
    var b = RY.b;
    return b.onayla(kapat
      ? { baslik: 'Hesabı devre dışı bırak — ' + ad, tehlike: true, onaylaMetin: 'Devre dışı bırak', gerekce: true,
          mesaj: 'Giriş hesabı kapanır, oturumları düşer; kullanıcı uygulamaya giremez. Veri silinmez.',
          aciklama: 'Geri alınabilir: "Aktif et" ile açılır. Denetim izine yazılır.' }
      : { baslik: 'Hesabı aktif et — ' + ad, onaylaMetin: 'Aktif et', gerekce: true,
          mesaj: 'Hesap yeniden açılır; kullanıcı bir sonraki girişte içeri alınır.' })
      .then(function (r) {
        if (!r) return null;
        return RY.post(kullaniciYolu(uid, '/disable'), { disabled: kapat, reason: r.gerekce }).then(function () {
          b.toast(kapat ? 'Hesap devre dışı bırakıldı.' : 'Hesap aktif edildi.', 'basari');
          if (RY.dikkat && RY.dikkat.yukle) RY.dikkat.yukle();
          RY.rotaYenile();
        });
      }).catch(hataToast);
  }

  function silAc(uid, ad) {
    var b = RY.b;
    return b.onayla({
      baslik: 'Hesabı KALICI olarak sil — ' + ad, tehlike: true, onaylaMetin: 'Hesabı sil',
      mesaj: 'Bu hesap ve TÜM verisi silinir (mobildeki "Hesabı sil" ile aynı boru: veri önce, kimlik en son). Geri alınamaz.',
      aciklama: 'Denetim izi yazılamazsa işlem yapılmaz ve hesap DURUR. E-posta yalnız denetim izinde kalır.',
      gerekce: true, yazili: 'SIL'
    }).then(function (r) {
      if (!r) return null;
      return RY.del(kullaniciYolu(uid), { confirm: 'SIL', reason: r.gerekce }).then(function () {
        b.toast('Hesap silindi: ' + ad, 'basari', { sure: 8000 });
        delete adOnbellek[uid];
        if (RY.dikkat && RY.dikkat.yukle) RY.dikkat.yukle();
        RY.rotaYaz('kullanicilar');
      });
    }).catch(hataToast);
  }

  /* =====================================================================
     360 — zaman çizelgesi
     ===================================================================== */

  var PARASAL_SINIF = { INITIAL_PURCHASE: 'celadon', RENEWAL: 'celadon', TRIAL_CONVERTED: 'celadon',
                        TRIAL_STARTED: 'altin', REFUND: 'madder', BILLING_ISSUE: 'madder',
                        CANCELLATION: '', EXPIRATION: '' };
  var DEFTER = {
    debit: ['', '−', 'Harcama'], credit: ['altin', '+', 'Paket alımı'], promo: ['altin', '+', 'Promosyon kodu'],
    admin: ['altin', '+', 'Yönetici kredisi'], refund: ['madder', '−', 'Paket iadesi'],
    spend_refund: ['altin', '+', 'Harcama iadesi'], allowance: ['altin', '+', 'Aylık hak']
  };

  function zamanOlaylari(b, d) {
    var olaylar = [];
    function ts(v) { var t = b.tarihNesnesi(v); return t ? t.getTime() : 0; }

    (d.timeline || []).forEach(function (o) {
      var tur = String(o.eventType || '?');
      var parasal = o.monetary !== false && Number(o.price);
      olaylar.push({
        at: o.at, ts: ts(o.at), grup: 'parasal',
        sinif: PARASAL_SINIF[tur] != null ? PARASAL_SINIF[tur] : '',
        baslik: S().olayAdi(tur) + (o.productId ? ' · ' + o.productId : ''),
        alt: [o.store ? S().magazaAdi(o.store) : null, o.periodType ? S().donemTuruAdi(o.periodType) : null,
              o.currency && o.price ? o.currency + ' ' + b.sayi(Number(o.price)) : null,
              o.environment ? S().ortamAdi(o.environment) : null].filter(Boolean).join(' · '),
        tutar: parasal ? (tur === 'REFUND' ? '−' : '') + b.para(Math.abs(Number(o.price))) : ''
      });
    });

    (d.ledger || []).forEach(function (k) {
      var t = DEFTER[k.type] || ['', '', String(k.type || '?')];
      var miktar = Number(k.amount) || 0;
      var alt = k.feature ? ozellikAdi(k.feature) : (k.productId ? 'paket ' + k.productId : (k.code ? 'kod ' + k.code
        : (k.reason ? '"' + k.reason + '"' + (k.adminUid ? ' · ' + String(k.adminUid).slice(0, 8) : '') : '')));
      olaylar.push({ at: k.at, ts: ts(k.at), grup: 'cuzdan', sinif: t[0],
        baslik: t[2] + ' · ' + b.sayi(miktar) + ' kredi', alt: alt,
        tutar: t[1] ? t[1] + b.sayi(miktar) : b.sayi(miktar) });
    });

    var p = d.profile || {};
    if (p.createdAt) {
      olaylar.push({ at: p.createdAt, ts: ts(p.createdAt), grup: 'sistem', sinif: '',
        baslik: 'Kayıt', alt: [platformAdi(p.platform), p.language ? dilAdi(p.language) : null].filter(Boolean).join(' · '), tutar: '' });
    }
    var c = d.device || {};
    if (c.claimedAt) {
      olaylar.push({ at: c.claimedAt, ts: ts(c.claimedAt), grup: 'sistem', sinif: '',
        baslik: 'Cihaz devralındı', alt: [platformAdi(c.platform), c.deviceId, 'son giriş kazandı'].filter(Boolean).join(' · '), tutar: '' });
    }
    (d.phoneAttempts || []).forEach(function (a) {
      var m = ASAMA[a.stage] || ['kivilcim', a.stage || 'telefon'];
      olaylar.push({ at: a.at, ts: ts(a.at), grup: 'sistem', sinif: a.stage === 'failed' ? 'madder' : '',
        baslik: 'Telefon · ' + m[1], alt: [a.masked, a.iso2, a.code].filter(Boolean).join(' · '), tutar: '' });
    });

    olaylar.sort(function (a, c2) { return c2.ts - a.ts; });
    return olaylar;
  }

  function zamanHtml(b, olaylar, grup) {
    var liste = grup === 'tumu' ? olaylar : olaylar.filter(function (o) { return o.grup === grup; });
    if (!liste.length) return b.bosDurum('Bu süzgeçte olay yok.', { ikon: 'zaman' });
    return '<div class="zaman">' + liste.slice(0, 120).map(function (o) {
      return '<div class="olay"><span class="zamanm" title="' + b.e(b.tarih(o.at, true)) + '">' + b.e(b.tarih(o.at, true)) + '</span>' +
        '<span class="cizgi" aria-hidden="true"><i' + (o.sinif ? ' class="' + b.e(o.sinif) + '"' : '') + '></i></span>' +
        '<span class="ne">' + b.e(o.baslik) + (o.alt ? '<span>' + b.e(o.alt) + '</span>' : '') + '</span>' +
        '<span class="tutar">' + b.e(o.tutar) + '</span></div>';
    }).join('') + '</div>';
  }

  /* =====================================================================
     360 — görünüm
     ===================================================================== */

  /* Marj cümlesi — ÜÇ terimli (OP13).

     NEDEN yeniden yazıldı: `admin_service` marjdan ortak edinme maliyetini
     de düşüyor (`marginUsd = gelir × (1 − mağaza) − AI − ortak`), ama bu
     cümle iki terim sayıyordu. Ekranda "= $6,00" yazarken cümledeki
     eşitliğin sağı $8,00 ediyordu; aradaki $2,00 ortak maliyetiydi ve
     sahibi bunu PANEL HATASI sanıyordu. Cümle yanlış olduğu için kusur
     yorumdan değil METİNden geliyordu.

     NEDEN ortak maliyeti ayrı satırda ve HAM BİRİMİYLE (₺) + kullanılan
     kurla: düşümün kendisi gizlenirse marjdaki eksilme açıklanamaz görünür;
     kur gizlenirse `RYTHO_USD_TRY` yanlış olduğunda (varsayılan 42,0'a
     düşmüş ya da elle yanlış girilmiş) sahibin bunu görebileceği HİÇBİR
     yer kalmaz — sessizce kaymış bir marja bakar. Ölçülen birim ₺'dir;
     dolar değeri bir TÜRETMEdir ve hangi kurla türetildiği söylenmeden
     sunulmamalı.

     Sentinel: −1 "ölçülemedi" demek ve `b.para` onu "—" basıyor (deponun
     mevcut doktrini). Eşitliğin ortasındaki çıplak bir "—" sıfır gibi
     okunabildiği için cümle bunu KELİMEYLE de söylüyor. "Bilinmiyor"
     hükmü `marginUsd === -1` testiyle DEĞİL, sunucunun kendi koşulunu
     (girdilerden biri negatif) aynalayarak veriliyor: gerçek bir marj da
     −1,00 olabilir ve o durumda "ölçülemedi" demek yalan olurdu. */
  var HAKEDIS_ADI = { pending: 'bekliyor (15 gün kesinleşme süresi)',
                      qualified: 'kesinleşti', void: 'iptal' };

  /* Uç ortak alanlarını HİÇ gönderiyor mu?

     ⚠️ Bu ayrım şu an VARSAYIMSAL DEĞİL: `partnerCostUsd` alanını ekleyen
     `admin_service` değişikliği henüz dağıtılmadı, canlı backend o alanları
     döndürmüyor. Hosting ise backend'den BAĞIMSIZ dağıtılıyor
     (`firebase deploy --only hosting` vs `infra/deploy-backend.ps1`), yani
     paneli önce yayınlamak tek satırlık bir sıra hatasıdır.

     Ayırmazsak `Number(undefined)` NaN olur, NaN >= 0 yanlıştır ve panel
     her kullanıcı için "hakediş kaydı okunamadı" diye HİÇ YAPILMAMIŞ bir
     okumanın teşhisini uydurur; üstelik aynı cümlede uçtan gelen gerçek
     (iki terimli) marjı basarken yanına "marj hesaplanamadı" yazar. Alanın
     YOKLUĞU ile "ölçüldü ama bilinmiyor" aynı şey değildir. */
  function ortakAlaniVar(eko) {
    return eko.partnerCostUsd != null && eko.partnerRewardTry != null;
  }

  /* Girdilerin hepsi ölçüldü mü? Sunucudaki koşulun aynası:
     `gelir >= 0 and maliyet >= 0 and ortak >= 0`. Sapma olursa iki taraf
     yan yana okunup bulunabilsin diye birebir aynı tutuluyor. Ortak terimi
     yalnız uç onu gönderiyorsa sayılır: göndermeyen uçta sunucunun marjı
     İKİ terimlidir ve o marj da ölçülmüştür — eksik olan terim değil,
     terimin kendisidir. */
  function marjOlculdu(eko) {
    var terimler = [eko.revenueUsd, eko.aiCostUsd];
    if (ortakAlaniVar(eko)) terimler.push(eko.partnerCostUsd);
    return terimler.every(function (v) { return Number(v) >= 0; });
  }

  /* Marj tutarının yazısı. `b.para` −1'i "bilinmiyor" sayıp "—" basıyor
     (deponun sentinel doktrini) ama marj GERÇEKTEN −1,00 olabilir: geliri
     olmayan, $1,00 AI maliyeti biriktirmiş bir ücretsiz kullanıcı tam bunu
     verir. O hâlde "—" basmak ölçülmüş bir zararı "bilinmiyor" adıyla
     sunmak olurdu — ters yönden aynı kusur. Bu yüzden girdiler ölçülmüşken
     −1 elle yazılıyor; biçimlendirme yine `b.para` ile, kendi para biçimimi
     uydurmamak için. Marj burada YENİDEN HESAPLANMIYOR: sunucunun sayısı
     neyse o gösteriliyor, yoksa iki formül zamanla sessizce ayrışırdı. */
  function marjYazisi(b, eko) {
    if (marjOlculdu(eko) && Number(eko.marginUsd) === -1) return '−' + b.para(1);
    return b.para(eko.marginUsd);
  }

  function marjCumlesi(b, eko) {
    var magaza = Math.round((Number(eko.storeCutRate) || 0.15) * 100);
    var ortakUsd = Number(eko.partnerCostUsd);
    var ortakTry = Number(eko.partnerRewardTry);
    var kur = Number(eko.usdTryRate);
    var durum = eko.partnerStatus || null;
    var olcusuz = !marjOlculdu(eko);
    var ucGondermiyor = !ortakAlaniVar(eko);

    // Formül uçtan GELEN sayıyı anlatmak zorunda: ortak alanı yoksa
    // sunucunun marjı iki terimlidir ve üçüncü terimi yazmak, düşülmemiş
    // bir maliyeti düşülmüş göstermek olur (bu cümlenin ilk hâlinin ters
    // yönde yaptığı hatanın aynısı).
    var formul = '<p class="dipnot">Marj = gerçek alım geliri × (1 − mağaza %' + magaza +
      ') − AI maliyeti' +
      (ucGondermiyor ? '' : ' − <b>ortak edinme maliyeti</b>') + ' = <b>' +
      b.e(marjYazisi(b, eko)) + '</b>' +
      (olcusuz ? ' <i>(terimlerden biri ölçülemedi — marj hesaplanamadı)</i>' : '') +
      '</p>';

    var ayrinti;
    if (ucGondermiyor) {
      // "Ölçülemedi" DEĞİL: hiç istenmedi. Sorun panelde de kullanıcıda da
      // değil, dağıtım sırasında — bu yüzden ne yapılacağı yazılı.
      ayrinti = 'Ortak edinme maliyeti sunucudan <b>gelmiyor</b>: sunucu ' +
        'bu panelden eski sürümde. Yukarıdaki marj bu yüzden İKİ terimli — ' +
        'ortak ödemesi DÜŞÜLMEMİŞ. Bu kullanıcı bir ortak bağlantısıyla ' +
        'geldiyse marj olduğundan yüksektir; geldiği de sunucudan gelmiyor, ' +
        'yani BİLİNMİYOR. Sunucu güncellenince kendiliğinden düzelir.';
    } else if (!(ortakTry >= 0)) {
      // Hem ₺ hem $ bilinmiyor: hakediş dokümanı okunamadı ya da
      // `rewardTry` çözümlenemedi (ör. elle "30,00" dizesi yazılmış).
      ayrinti = 'Ortak edinme maliyeti <b>ölçülemedi</b>: hakediş kaydı ' +
        'okunamadı ya da tutarı çözümlenemedi. Yükümlülük VAR sayılıyor, ' +
        'tutarı bilinmiyor — bu yüzden marj da boş.';
    } else if (!(ortakUsd >= 0)) {
      // ₺ ölçüldü ama kur yok (`RYTHO_USD_TRY` pozitif değil): dolar
      // karşılığı türetilemiyor, marj da düşüyor. ₺ tutarı yine dürüst.
      ayrinti = 'Ortak edinme maliyeti <b>' + b.e(b.para(ortakTry, '₺')) +
        '</b> — <b>kur ayarlı değil</b>: sunucu ayarına USD/TRY kuru girilmeli, ' +
        'dolara çevrilemedi. Marj bu yüzden hesaplanamıyor.';
    } else if (durum === null) {
      ayrinti = 'Ortak edinme maliyeti <b>yok</b>: bu kullanıcı bir ortak ' +
        'bağlantısıyla gelmedi.';
    } else if (durum === 'void') {
      ayrinti = 'Ortak hakedişi <b>iptal</b> — yükümlülük ortadan ' +
        'kalktı, marjdan düşülmüyor.';
    } else {
      ayrinti = 'Düşülen ortak edinme maliyeti: <b>' + b.e(b.para(ortakUsd)) +
        '</b> = ' + b.e(b.para(ortakTry, '₺')) + ' ÷ kur ' +
        (kur > 0 ? b.e(b.sayi(kur)) : '—') + ' · hakediş ' +
        b.e(HAKEDIS_ADI[durum] || durum) + '.';
    }
    return formul + '<p class="dipnot">' + ayrinti + '</p>';
  }

  async function detay(icerik, uid, sekme, baglam) {
    var b = RY.b;
    var d = await RY.get(kullaniciYolu(uid), { sinyal: baglam && baglam.sinyal });
    // Kırıntı ve sekme başlığı kabın DIŞINDA: eski bir 360 geç gelirse
    // yeni sayfanın başlığını ezmesin.
    if (baglam && !baglam.aktif()) return;
    var p = d.profile || {}, sub = d.subscription || {}, w = d.wallet || {};
    var kul = d.usage || {}, toplamlar = kul.totals || null, sayilar = d.counts || {};
    var bild = d.notifications || {}, kota = d.quota || {}, cihaz = d.device || {};
    var eko = d.economics || {}, gelirT = d.revenueTotals || null;
    var sahip = RY.sahipMi();
    var ad = p.displayName || p.email || uid;
    adOnbellek[uid] = ad;
    RY.kirinti([{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Kullanıcılar', href: '#/kullanicilar' }, { metin: ad }]);
    document.title = ad + ' — Rytho Yönetim';

    var devreDisi = p.authDisabled === true;
    var pasifNit = sahip ? '' : ' disabled title="Yalnız sahip" aria-disabled="true"';

    /* ---- Kimlik başlığı ---- */
    var rozetler = b.planRozeti(p.plan, p.createdAt) +
      (devreDisi ? ' ' + b.rozet('Devre dışı', 'hata') : (p.authDisabled == null ? ' ' + b.rozet('Giriş durumu bilinmiyor', 'notr') : '')) +
      ' ' + (p.hasPush ? b.rozet('Bildirim alıyor', 'aktif') : b.rozet('Bildirim almıyor', 'notr')) +
      (p.sunSign ? ' ' + b.rozet(burcAdi(p.sunSign) + ' ' + burc(p.sunSign), 'yeni') : '') +
      (p.onboardingCompleted === false ? ' ' + b.rozet('Kurulum yarım', 'uyari') : '');
    var meta = [
      p.email ? '<span class="mono">' + b.e(p.email) + '</span>' : '',
      p.username ? '<span class="mono">@' + b.e(p.username) + '</span>' : '',
      '<span class="mono" title="Kullanıcı kimliği">' + b.e(uid) + '</span>',
      '<span>Kayıt ' + b.e(b.tarih(p.createdAt)) + '</span>',
      '<span>Son görülme ' + b.e(p.lastSeenDaily ? b.goreliZaman(p.lastSeenDaily) : '—') + '</span>',
      '<span>' + b.e([p.platform ? platformAdi(p.platform) : null, p.appBuild != null ? 'sürüm ' + p.appBuild : null,
        p.language ? dilAdi(p.language) : null].filter(Boolean).join(' · ') || '—') + '</span>',
      '<span>Seri ' + b.e(b.sayi(Number(p.streakCount) || 0)) + (Number(p.streakCount) > 0 ? ' 🔥' : '') + '</span>'
    ].filter(Boolean).join('');
    var eylemler =
      '<button type="button" class="buton ikincil" id="k360-kredi">' + b.ik('jeton', 16) + 'Kredi ver</button>' +
      '<button type="button" class="buton ikincil" id="k360-cihaz"' + (cihaz.deviceId ? '' : ' disabled title="Kayıtlı cihaz yok"') + '>' +
      b.ik('cihaz', 16) + 'Cihaz kilidini sıfırla</button>' +
      '<button type="button" class="buton ikincil" id="k360-baglanti">' + b.ik('anahtar', 16) + 'Şifre / doğrulama bağlantısı</button>' +
      '<button type="button" class="buton ' + (devreDisi ? 'ikincil' : 'tehlike') + '" id="k360-durum"' + pasifNit + '>' +
      b.ik(devreDisi ? 'basari' : 'kilit', 16) + (devreDisi ? 'Aktif et' : 'Devre dışı bırak') + '</button>' +
      '<button type="button" class="buton tehlike" id="k360-sil"' + pasifNit + '>' + b.ik('cop', 16) + 'Sil</button>';

    var kimlik = '<section class="kimlik-bas" aria-label="Kullanıcı kimliği">' +
      '<div class="avatar buyuk" aria-hidden="true">' + b.e(b.basHarfler(p.displayName, p.email)) + '</div>' +
      '<div><h1 class="ad" tabindex="-1">' + b.e(ad) + ' ' + rozetler + '</h1><div class="meta">' + meta + '</div></div>' +
      '<div class="eylemler">' + eylemler + '</div></section>';

    icerik.innerHTML = kimlik +
      (devreDisi ? b.bant('<b>Hesap devre dışı</b> — kullanıcı giriş yapamaz.' + (sahip ? ' "Aktif et" ile açılır.' : ''), 'uyari', { html: true }) : '') +
      (eko.revenueUsd === -1 || eko.aiCostUsd === -1
        ? b.bant('Bu kullanıcının gelir ve kullanım toplamı henüz yok — ekonomi alanları "—". Eski hesaplarda ' +
          'toplamlar, geçmişi dolduran bakım işi çalıştırılınca oluşur.', 'bilgi') : '') +
      '<div id="k360-sekmeler"></div>';

    /* ---- Sekme içerikleri ---- */
    var olaylar = zamanOlaylari(b, d);
    var cuzdanToplam = (Number(w.allowance) || 0) + (Number(w.purchased) || 0);
    var byFeatureMaliyet = toplamlar && toplamlar.byFeature ? toplamlar.byFeature : null;

    function abonelikRozeti() {
      if (sub.active) return sub.isTrial ? b.rozet('Deneme', 'trial') : b.rozet('Aktif', 'aktif');
      if (sub.productId) return b.rozet('Süresi dolmuş', 'dolmus');
      return b.rozet('Abonelik yok', 'notr');
    }
    function abonelikListesi(tam) {
      var s = '<dl class="alan-liste">' +
        '<dt>Ürün</dt><dd>' + b.e(sub.productId || '—') + '</dd>' +
        '<dt>Mağaza</dt><dd>' + b.e(sub.store ? S().magazaAdi(sub.store) : '—') + '</dd>' +
        '<dt>' + (sub.willRenew ? 'Yenileme' : 'Bitiş') + '</dt><dd>' + b.e(b.tarih(sub.expiresAt)) + '</dd>' +
        '<dt>Otomatik yenileme</dt><dd>' + b.e(sub.willRenew == null ? '—' : (sub.willRenew ? 'açık' : 'kapalı')) + '</dd>' +
        '<dt>Deneme</dt><dd>' + b.e(sub.isTrial == null ? '—' : (sub.isTrial ? 'evet' : 'hayır')) + '</dd>' +
        '<dt>Son olay</dt><dd>' + b.e(sub.lastEvent ? S().olayAdi(sub.lastEvent) : '—') + (sub.updatedAt ? ' · ' + b.e(b.tarih(sub.updatedAt)) : '') + '</dd>';
      if (tam) {
        s += '<dt>Profildeki plan</dt><dd>' + b.e(p.plan ? S().planAdi(p.plan) : '—') + (p.planProduct ? ' · ' + b.e(p.planProduct) : '') + '</dd>' +
          '<dt>Ortak kodu</dt><dd>' + b.e(d.attribution && d.attribution.code ? d.attribution.code : '—') + '</dd>';
      }
      return s + '</dl>';
    }
    function cihazListesi() {
      var sonlar = Object.keys(bild).filter(function (k) { return /LastSent$/.test(k); }).sort();
      return '<dl class="alan-liste">' +
        '<dt>Cihaz</dt><dd>' + b.e(cihaz.deviceId || 'kayıt yok') + '</dd>' +
        '<dt>Platform</dt><dd>' + b.e(platformAdi(cihaz.platform)) + '</dd>' +
        '<dt>Devralma</dt><dd>' + b.e(b.tarih(cihaz.claimedAt, true)) + '</dd>' +
        sonlar.slice(0, 3).map(function (k) {
          var tur = k.replace(/LastSent$/, '');
          return '<dt>Son ' + b.e(S().bildirimAdi(tur)) + '</dt><dd>' + b.e(b.goreliZaman(bild[k])) + '</dd>';
        }).join('') +
        (bild.dailyTheme ? '<dt>Tema</dt><dd>' + b.e(bild.dailyTheme) + '</dd>' : '') +
        '</dl>';
    }

    var sekmeApi = b.sekmeler({
      kimlik: 'k360', etiket: 'Kullanıcı bölümleri',
      aktif: SEKMELER.indexOf(sekme) >= 0 ? sekme : 'ozet',
      onDegis: function (ad2) { RY.rotaYaz('kullanicilar', [uid, ad2], {}, { sessiz: true }); },
      sekmeler: [
        { ad: 'ozet', etiket: 'Özet', icerik: function () {
          var el = b.el('<div class="sutun"></div>');
          el.innerHTML =
            '<section class="izgara-kpi" aria-label="Özet sayılar">' +
            b.istatistikKarti({ ad: 'Gelir (gerçek alımlar)', deger: b.para(eko.revenueUsd), altin: true,
              alt: gelirT && gelirT.PRODUCTION ? b.sayi(Number(gelirT.PRODUCTION.events) || 0) + ' olay · iade ' + b.para(Number(gelirT.PRODUCTION.refundsUsd) || 0) : 'toplam yok' }) +
            // "AI maliyeti $X · marj $Y" yan yana durunca okuyucu marjı
            // gelir×(1−mağaza)−X sanıp aradaki farkı panel hatası okuyor —
            // formül cümlesi düzeltilse bile ÖZET ilk görülen ekran olduğu
            // için aynı yanılgıyı burada üretiyordu. Ortak maliyeti gerçekten
            // düşüldüyse kart bunu söylüyor; düşülmediyse (0) sessiz kalıyor,
            // çünkü her kullanıcıya "ortak −$0,00" yazmak gürültü olurdu.
            b.istatistikKarti({ ad: 'AI maliyeti', deger: b.para(eko.aiCostUsd),
              alt: (eko.calls >= 0 ? b.sayi(eko.calls) + ' çağrı' : '—') +
                (Number(eko.partnerCostUsd) > 0 ? ' · ortak −' + b.para(eko.partnerCostUsd) : '') +
                ' · marj ' + marjYazisi(b, eko) }) +
            b.istatistikKarti({ ad: 'Cüzdan', deger: b.sayi(cuzdanToplam),
              alt: 'hak ' + b.sayi(Number(w.allowance) || 0) + ' · satın alınan ' + b.sayi(Number(w.purchased) || 0) }) +
            b.istatistikKarti({ ad: 'Sohbet', deger: b.sayi(sayilar.conversations),
              alt: 'konuşma · ' + (sayilar.friends >= 0 ? b.sayi(sayilar.friends) + ' kişi Çevrem\'de' : 'çevre sayılamadı') }) +
            '</section>' +
            '<div class="izgara-3">' +
            b.modul('Abonelik', abonelikListesi(false), abonelikRozeti(), { alt: sub.store ? S().magazaAdi(sub.store) : 'mağaza bilgisi yok' }) +
            b.modul('Cihaz & bildirim', cihazListesi(), '', { alt: 'Tek cihaz kilidi · bildirim' }) +
            b.modul('Kullanım', '<div class="grafik-kap"><canvas id="g-360-ozellik" class="grafik grafik-kucuk" aria-label="Özellik başına maliyet"></canvas></div>',
              '', { alt: byFeatureMaliyet ? 'Ömür boyu · özellik başına maliyet' : 'Son 30 olay · özellik başına çağrı' }) +
            '</div>' +
            b.modul('Zaman çizelgesi', zamanHtml(b, olaylar.slice(0, 8), 'tumu'),
              '<button type="button" class="buton sade" id="k360-zaman-tum">Tümü</button>', { alt: 'Son 8 olay' });
          el.querySelector('#k360-zaman-tum').addEventListener('click', function () { sekmeApi.sec('zaman'); });
          requestAnimationFrame(function () {
            var kaynak = byFeatureMaliyet || kul.byFeature || {};
            var anahtarlar = Object.keys(kaynak).sort(function (x, y) {
              return deger(y) - deger(x);
            });
            function deger(k) { var v = kaynak[k]; return typeof v === 'object' ? (Number(v.estCostUsd) || 0) : (Number(v) || 0); }
            RY.grafik.cubuk(el.querySelector('#g-360-ozellik'), {
              etiketler: anahtarlar.map(ozellikAdi), degerler: anahtarlar.map(deger), yatay: true,
              bicim: byFeatureMaliyet ? 'para' : 'sayi', enCok: 6, etiket: 'Özellik kırılımı',
              bosMetin: 'Kullanım olayı yok'
            });
          });
          return el;
        } },
        { ad: 'abonelik', etiket: 'Abonelik & Cüzdan', icerik: function () {
          var el = b.el('<div class="sutun"></div>');
          var envler = gelirT ? Object.keys(gelirT).filter(function (k) { return gelirT[k] && typeof gelirT[k] === 'object'; }) : [];
          var gelirHtml = envler.length ? '<dl class="alan-liste">' + envler.map(function (env) {
            var k = gelirT[env] || {};
            var brut = Number(k.grossUsd) || 0, iade = Number(k.refundsUsd) || 0;
            var ad = S().ortamAdi(env);
            return '<dt>' + b.e(ad) + ' · brüt</dt><dd>' + b.e(b.para(brut)) + '</dd>' +
              '<dt>' + b.e(ad) + ' · iade</dt><dd>−' + b.e(b.para(iade)) + '</dd>' +
              '<dt>' + b.e(ad) + ' · net</dt><dd>' + b.e(b.para(brut - iade)) + ' · ' + b.e(b.sayi(Number(k.events) || 0)) + ' olay</dd>';
          }).join('') + '</dl>' : b.bosDurum('Gelir toplamı yok — ilk parasal olayla oluşur.', { ikon: 'gelir' });
          el.innerHTML =
            '<div class="izgara-2">' +
            b.modul('Abonelik', abonelikListesi(true), abonelikRozeti(), { alt: 'mağazadan gelen son durum' }) +
            b.modul('Gelir toplamları', gelirHtml + marjCumlesi(b, eko),
              '', { alt: 'ortam başına · ömür boyu · ortak maliyeti düşülmüş' }) +
            '</div>' +
            '<div class="izgara-2">' +
            b.modul('Cüzdan', '<dl class="alan-liste">' +
              '<dt>Toplam</dt><dd>' + b.e(b.sayi(cuzdanToplam)) + ' kredi</dd>' +
              '<dt>Aylık hak</dt><dd>' + b.e(b.sayi(Number(w.allowance) || 0)) + ' / ' + b.e(b.sayi(Number(w.monthly_allowance) || 0)) + '</dd>' +
              '<dt>Satın alınan</dt><dd>' + b.e(b.sayi(Number(w.purchased) || 0)) + '</dd>' +
              '<dt>Hak sıfırlanır</dt><dd>' + b.e(b.tarih(w.allowance_resets_at)) + '</dd></dl>' +
              '<div class="eylem-satir"><button type="button" class="buton ikincil kucuk" id="k360-kredi2">' + b.ik('jeton', 14) + 'Kredi ver</button></div>',
              '', { alt: 'yalnız pozitif kredi · düşüm yok' }) +
            b.modul('Günlük kota', Object.keys(kota).filter(function (k) { return k !== 'date' && k !== 'resetAtUtc'; }).length
              ? '<dl class="alan-liste">' + Object.keys(kota).filter(function (k) { return k !== 'date' && k !== 'resetAtUtc'; }).map(function (k) {
                  return '<dt>' + b.e(ozellikAdi(k)) + '</dt><dd>' + b.e(b.sayi(kota[k])) + '</dd>';
                }).join('') + '</dl>'
              : b.bosDurum('Bugün sayaç yok.'), '', { alt: kota.date ? 'gün ' + b.tarih(kota.date) : 'bugün' }) +
            '</div>' +
            b.modul('Cüzdan defteri', '<div id="k360-defter"></div>', '', { alt: 'son 50 hareket' });
          el.querySelector('#k360-kredi2').addEventListener('click', function () { krediVerAc(uid, ad); });
          var vt = b.veriTablosu({
            kimlik: 'k360-defter-vt', etiket: 'Cüzdan defteri', yogunluk: 'sik',
            sutunlar: [
              { ad: 'at', baslik: 'Zaman', siralanir: true, deger: function (k) { var t = b.tarihNesnesi(k.at); return t ? t.getTime() : 0; },
                bicim: function (k) { return '<span class="mono">' + b.e(b.tarih(k.at, true)) + '</span>'; } },
              { ad: 'type', baslik: 'Tür', siralanir: true, bicim: function (k) {
                var t = DEFTER[k.type] || ['', '', String(k.type || '?')];
                return b.rozet(t[2], t[0] === 'madder' ? 'hata' : (t[0] === 'altin' ? 'altin' : 'notr'));
              } },
              { ad: 'amount', baslik: 'Kredi', hizala: 'sag', siralanir: true, bicim: function (k) {
                var t = DEFTER[k.type] || ['', '', ''];
                return '<span class="mono">' + b.e((t[1] || '') + b.sayi(Number(k.amount) || 0)) + '</span>';
              } },
              { ad: 'ayrinti', baslik: 'Ayrıntı', deger: function (k) { return k.feature || k.productId || k.code || k.reason || ''; },
                bicim: function (k) {
                  return b.e(k.feature ? ozellikAdi(k.feature) : (k.productId || k.code || k.reason || '—')) +
                    (k.adminUid ? ' <span class="mono dipnot">' + b.e(String(k.adminUid).slice(0, 8)) + '</span>' : '');
                } }
            ],
            anahtar: function (k) { return k.id || (k.type + '-' + k.at); },
            siralama: { ad: 'at', yon: 'desc' },
            bosMetin: 'Henüz cüzdan hareketi yok.'
          });
          el.querySelector('#k360-defter').appendChild(vt.el);
          vt.guncelle(d.ledger || []);
          return el;
        } },
        { ad: 'kullanim', etiket: 'Kullanım & Maliyet', icerik: function () {
          var el = b.el('<div class="sutun"></div>');
          var t = toplamlar || {};
          el.innerHTML =
            '<section class="izgara-kpi" aria-label="Kullanım toplamları">' +
            b.istatistikKarti({ ad: 'Çağrı (ömür boyu)', deger: toplamlar ? b.sayi(Number(t.calls) || 0) : '—',
              alt: t.lastAt ? 'son ' + b.goreliZaman(t.lastAt) : 'toplam yok' }) +
            b.istatistikKarti({ ad: 'Tahmini maliyet', deger: toplamlar ? b.para(Number(t.estCostUsd) || 0) : '—', altin: true, alt: 'model birimi × birim fiyat' }) +
            b.istatistikKarti({ ad: 'Girdi birimi', deger: toplamlar ? b.sayi(Number(t.promptTokens) || 0) : '—' }) +
            b.istatistikKarti({ ad: 'Çıktı birimi', deger: toplamlar ? b.sayi(Number(t.outputTokens) || 0) : '—',
              alt: t.thinkingTokens ? 'düşünme ' + b.sayi(Number(t.thinkingTokens)) : 'düşünme dahil' }) +
            '</section>' +
            '<div class="izgara-2">' +
            b.modul('Özellik başına maliyet', '<div class="halka-kap"><div class="grafik-kap"><canvas id="g-360-halka" class="grafik" aria-label="Özellik başına maliyet payı"></canvas></div></div>',
              '', { alt: byFeatureMaliyet ? 'ömür boyu · tahmini $' : 'son 30 olay · çağrı' }) +
            b.modul('Son 30 olay özeti', '<dl class="alan-liste"><dt>Çağrı</dt><dd>' + b.e(b.sayi(Number(kul.calls) || 0)) + '</dd>' +
              '<dt>Maliyet</dt><dd>' + b.e(b.para(Number(kul.estCostUsd) || 0)) + '</dd></dl>' +
              '<p class="dipnot">Liste hep boşsa ilgili veritabanı dizini eksik olabilir (Sistem → Veritabanı dizinleri); sayfanın geri kalanı etkilenmez.</p>',
              '', { alt: 'son 30 çağrı' }) +
            '</div>' +
            b.modul('Son çağrılar', '<div id="k360-kullanim-tablo"></div>', '', { alt: 'Son 30 · en yeni üstte' });
          var vt = b.veriTablosu({
            kimlik: 'k360-kullanim-vt', etiket: 'Son kullanım olayları', yogunluk: 'sik',
            sutunlar: [
              { ad: 'at', baslik: 'Zaman', bicim: function (k) { return '<span class="mono">' + b.e(b.tarih(k.at, true)) + '</span>'; } },
              { ad: 'feature', baslik: 'Özellik', bicim: function (k) { return b.e(ozellikAdi(k.feature || 'unknown')); } },
              { ad: 'model', baslik: 'Model', bicim: function (k) { return '<span class="mono">' + b.e(k.model || '—') + '</span>'; } },
              { ad: 'promptTokens', baslik: 'Girdi', hizala: 'sag', bicim: function (k) { return b.e(b.sayi(Number(k.promptTokens) || 0)); } },
              { ad: 'outputTokens', baslik: 'Çıktı', hizala: 'sag', bicim: function (k) { return b.e(b.sayi(Number(k.outputTokens) || 0)); } },
              { ad: 'estCostUsd', baslik: 'Maliyet', hizala: 'sag', bicim: function (k) { return b.e(b.para(Number(k.estCostUsd) || 0)); } },
              { ad: 'latencyMs', baslik: 'Süre', hizala: 'sag', bicim: function (k) { return k.latencyMs != null ? b.e(b.sayi(Number(k.latencyMs))) + ' ms' : '—'; } }
            ],
            anahtar: function (k) { return String(k.at) + '-' + (k.feature || '') + '-' + (k.latencyMs || '') + '-' + (k.estCostUsd || ''); },
            onSirala: function () { /* sunucu sıralı */ },
            bosMetin: 'Kullanım olayı yok.'
          });
          el.querySelector('#k360-kullanim-tablo').appendChild(vt.el);
          vt.guncelle(kul.recent || []);
          requestAnimationFrame(function () {
            var kaynak = byFeatureMaliyet || kul.byFeature || {};
            RY.grafik.halka(el.querySelector('#g-360-halka'), {
              dilimler: Object.keys(kaynak).map(function (k) {
                var v = kaynak[k];
                return { ad: ozellikAdi(k), deger: typeof v === 'object' ? (Number(v.estCostUsd) || 0) : (Number(v) || 0) };
              }),
              bicim: byFeatureMaliyet ? 'para' : 'sayi', merkezAlt: byFeatureMaliyet ? 'maliyet' : 'çağrı',
              etiket: 'Özellik başına maliyet', bosMetin: 'Kullanım kaydı yok'
            });
          });
          return el;
        } },
        { ad: 'bildirim', etiket: 'Bildirim & Cihaz', icerik: function () {
          var el = b.el('<div class="sutun"></div>');
          var sonlar = Object.keys(bild).filter(function (k) { return /LastSent$/.test(k); }).sort();
          var bildHtml = (sonlar.length || bild.dailyTheme)
            ? '<dl class="alan-liste">' + (bild.dailyTheme ? '<dt>Bugünkü tema</dt><dd>' + b.e(bild.dailyTheme) + '</dd>' : '') +
              sonlar.map(function (k) {
                var tur = k.replace(/LastSent$/, '');
                return '<dt>' + b.e(S().bildirimAdi(tur)) + '</dt><dd>' + b.e(b.tarih(bild[k], true)) + ' · ' + b.e(b.goreliZaman(bild[k])) + '</dd>';
              }).join('') + '</dl>'
            : b.bosDurum('Gönderim kaydı yok.', { ikon: 'zil' });
          var tel = d.phoneAttempts || [];
          var telHtml = tel.length ? '<div class="liste">' + tel.map(function (a) {
            var m = ASAMA[a.stage] || ['kivilcim', a.stage || '—'];
            return '<div class="satir"><span class="satir-ikon' + (a.stage === 'failed' ? ' kirmizi' : (a.stage === 'verified' || a.stage === 'auto' ? ' yesil' : '')) + '">' +
              b.ik(m[0], 18) + '</span><span class="metin">' + b.e(m[1]) + '<span>' +
              b.e([a.masked, a.iso2, a.code].filter(Boolean).join(' · ') || '—') + '</span></span>' +
              '<span class="sayi">' + b.e(b.tarih(a.at, true)) + '</span></div>';
          }).join('') + '</div>' : b.bosDurum('Telefon denemesi yok.');
          el.innerHTML =
            '<div class="izgara-2">' +
            b.modul('Bildirim', bildHtml, p.hasPush ? b.rozet('Bildirim alıyor', 'aktif') : b.rozet('Bildirim almıyor', 'notr'),
              { alt: 'yalnız zamanlar · bildirim metinleri gelmez' }) +
            b.modul('Cihaz kilidi', cihazListesi() +
              '<div class="eylem-satir"><button type="button" class="buton ikincil kucuk" id="k360-cihaz2"' + (cihaz.deviceId ? '' : ' disabled title="Kayıtlı cihaz yok"') + '>' +
              b.ik('cihaz', 14) + 'Cihaz kilidini sıfırla</button></div>' +
              '<p class="dipnot">Cihaz kimliği maskeli (son 6). Burada "son görülme" yok: sunucu cihaz kaydını yalnız devralma anında günceller.</p>',
              '', { alt: 'yalnız ücretli abonede etkin' }) +
            '</div>' +
            b.modul('Telefon doğrulama denemeleri', telHtml + '<p class="dipnot">"Kod gelmiyor" başvurusunda ilk bakılacak yer; numara maskeli tutulur.</p>',
              '', { alt: 'son 20' });
          el.querySelector('#k360-cihaz2').addEventListener('click', function () { cihazSifirla(uid, cihaz); });
          return el;
        } },
        { ad: 'zaman', etiket: 'Zaman çizelgesi', sayac: olaylar.length || null, icerik: function () {
          var el = b.el('<div class="sutun"></div>');
          var GRUPLAR = [['tumu', 'Tümü'], ['parasal', 'Parasal'], ['cuzdan', 'Cüzdan'], ['sistem', 'Sistem']];
          el.innerHTML = b.modul('Zaman çizelgesi', '<div id="k360-zaman"></div>',
            '<span class="cip-grup" role="group" aria-label="Olay türü" id="k360-zaman-cip">' + GRUPLAR.map(function (g) {
              return '<button type="button" class="adm-cip" data-grup="' + g[0] + '" aria-pressed="' + (g[0] === 'tumu' ? 'true' : 'false') + '">' + g[1] + '</button>';
            }).join('') + '</span>', { alt: 'Abonelik olayları + cüzdan defteri + sistem · son 50\'şer' });
          var kap = el.querySelector('#k360-zaman');
          kap.innerHTML = zamanHtml(b, olaylar, 'tumu');
          el.querySelector('#k360-zaman-cip').addEventListener('click', function (ev) {
            var d2 = ev.target.closest('.adm-cip');
            if (!d2) return;
            this.querySelectorAll('.adm-cip').forEach(function (c) { c.setAttribute('aria-pressed', c === d2 ? 'true' : 'false'); });
            kap.innerHTML = zamanHtml(b, olaylar, d2.getAttribute('data-grup'));
          });
          return el;
        } },
        { ad: 'denetim', etiket: 'Denetim', icerik: function () {
          var el = b.el('<div class="sutun"></div>');
          el.innerHTML = b.modul('Bu kullanıcıya yapılan yönetici işlemleri', '<div id="k360-denetim"></div>', '',
            { alt: 'En yeni üstte' });
          var imlec = null, istek = null;
          // Sekme 360'ın ömrüne bağlı: 360'tan çıkılınca uçuştaki istek
          // kesilir; tekrar dene / daha fazla bir öncekini iptal eder.
          var yeniIstek = b.tazeleyici(baglam);
          var vt = b.veriTablosu({
            kimlik: 'k360-denetim-vt', etiket: 'Denetim izi', yogunluk: 'sik',
            sutunlar: [
              { ad: 'at', baslik: 'Zaman', bicim: function (k) { return '<span class="mono">' + b.e(b.tarih(k.at, true)) + '</span>'; } },
              { ad: 'adminEmail', baslik: 'Yönetici', bicim: function (k) {
                return b.e(k.adminEmail || k.adminUid || '—') + (k.adminRole ? ' ' + b.rolRozeti(k.adminRole) : '');
              } },
              { ad: 'action', baslik: 'Eylem', bicim: function (k) {
                var a = String(k.action || '?');
                var tur = /delete|disable/.test(a) ? 'hata' : (/credit|enable/.test(a) ? 'altin' : 'notr');
                return b.rozet(S().eylemAdi(a), tur);
              } },
              // Sonuç ve ayrıntı Sistem → Denetim izi ile AYNI çizim (sistem.js):
              // aynı kayıt iki ekranda iki dille görünmesin.
              { ad: 'phase', baslik: 'Sonuç', bicim: function (k) { return RY.denetimFazRozeti(b, k.phase); } },
              { ad: 'params', baslik: 'Ayrıntı', bicim: function (k) { return RY.denetimAyrinti(b, k); } }
            ],
            anahtar: function (k) { return k.id; },
            satirSinif: function (k) { return k.phase === 'failed' ? 'durum-hata' : (k.phase === 'intent' ? 'durum-uyari' : ''); },
            onSirala: function () { /* sunucu sıralı */ },
            bosMetin: 'Bu kullanıcıya henüz yönetici işlemi yapılmamış.',
            onTekrar: function () { yukle(false); }
          });
          el.querySelector('#k360-denetim').appendChild(vt.el);
          function yukle(devam) {
            if (!devam) { vt.durum('yukleniyor'); imlec = null; istek = yeniIstek(); }
            var bu = istek;
            return RY.sorgu('/api/v1/admin/audit', { targetUid: uid, limit: DENETIM_SAYFA, cursor: devam ? imlec : null },
              { sinyal: bu.sinyal })
              .then(function (res) {
                if (!bu.gecerli()) return;
                var kayitlar = Array.isArray(res && res.entries) ? res.entries : [];
                imlec = (res && res.nextCursor) || null;
                var sayfa = { daha: !!imlec, onDaha: function () { return yukle(true); } };
                if (devam) vt.ekle(kayitlar, sayfa); else vt.guncelle(kayitlar, sayfa);
              }).catch(function (h) {
                if (!bu.gecerli() || (h && h.iptal)) return;
                if (devam) hataToast(h); else vt.durum('hata', RY.hataMetni(h));
              });
          }
          yukle(false);
          return el;
        } }
      ]
    });
    icerik.querySelector('#k360-sekmeler').appendChild(sekmeApi.el);

    /* ---- Eylem çubuğu ---- */
    icerik.querySelector('#k360-kredi').addEventListener('click', function () { krediVerAc(uid, ad); });
    icerik.querySelector('#k360-cihaz').addEventListener('click', function () { cihazSifirla(uid, cihaz); });
    icerik.querySelector('#k360-baglanti').addEventListener('click', function () { baglantiAc(uid, p.email); });
    var durumDugme = icerik.querySelector('#k360-durum');
    if (sahip) durumDugme.addEventListener('click', function () { durumDegistir(uid, ad, !devreDisi); });
    var silDugme = icerik.querySelector('#k360-sil');
    if (sahip) silDugme.addEventListener('click', function () { silAc(uid, ad); });
  }

  /* =====================================================================
     Rota
     ===================================================================== */

  RY.gorunumler.kullanicilar = async function (icerik, args, params, baglam) {
    args = args || [];
    if (!args.length) return liste(icerik, params, baglam);
    if (args[0] === 'ara') return liste(icerik, { q: args[1] || '' }, baglam);
    return detay(icerik, args[0], args[1], baglam);
  };

  RY.kirintiSaglayici.kullanicilar = function (args) {
    args = args || [];
    if (!args.length || args[0] === 'ara') return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Kullanıcılar' }];
    return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Kullanıcılar', href: '#/kullanicilar' },
            { metin: adOnbellek[args[0]] || 'Kullanıcı' }];
  };
})();

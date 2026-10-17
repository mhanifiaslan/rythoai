/* Geri bildirimler (AD20): uygulama içi geri bildirim kuyruğu (Profil →
   Geri bildirim). Liste + yan panelde ayrıntı; durum, iç not ve kullanıcıya
   push'lu yanıt. Sahip ve destek aynı yetkiyle çalışır.

   Rotalar:
   - #/geribildirim?status&type → liste. status ∈ new (varsayılan) |
     in_review | closed | all; type ∈ bug | suggestion | other. Süzgeç
     durumu adres çubuğuna SESSİZ yazılır (rotaYaz sessiz).
   - #/geribildirim/{id} → liste + o kaydın yan paneli açık (derin bağlantı;
     panel açılınca/kapanınca adres sessizce güncellenir).

   Uçlar (hepsi /api/v1/admin, yanıtlar {status:'ok', …} sargılı):
   - GET   /feedback?status&type&limit≤100&cursor → {items:[{id, uid, type,
     text, screen, appBuild, platform, language, createdAt, status,
     reply:{text, at, adminUid, pushSent}|null, noteCount,
     user:{displayName, email}}], nextCursor}
   - GET   /feedback/{id} → tam doküman + notes:[{at, adminUid, adminEmail, text}]
   - PATCH /feedback/{id} {status?, note?} → güncel doküman
   - POST  /feedback/{id}/reply {text 1..500} → {reply, pushSent}
     (kullanıcının telefonuna push; durum new → in_review sunucuda)
   Dikkat zili: {tur:'newFeedback', sayi, rota:'#/geribildirim?status=new'}. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  var SAYFA = 50;
  var KISA = 120;        // listede metin kırpma
  /* Yanıt kullanıcıya YALNIZCA push gövdesi olarak ulaşıyor; uygulamada
     `reply` alanını okuyan ekran yok. Sunucu 500 kabul ediyor (tam metin
     Firestore'da saklanıyor) ama gönderimde notification_service
     .MAX_PUSH_BODY = 110 üstü SESSİZCE kırpılıyor: admin 300 karakter
     yazınca kullanıcıya 109'u gidiyor, gerisi kayboluyor ve panel
     `pushSent: true` gösterdiği için kimse fark etmiyordu. Panelin sınırı
     kanalın sınırından geniş olamaz. Uzun açıklama iç nota yazılır. */
  var YANIT_MAX = 110;   // = backend notification_service.MAX_PUSH_BODY
  var NOT_MAX = 1000;

  // Adlar sözlükte (sozluk.js): denetim izi de `feedback.update` kaydının
  // durumunu aynı adla gösteriyor. Burada yalnız sıra ve rozet rengi.
  var DURUMLAR = [
    { deger: 'new', etiket: RY.sozluk.GB_DURUM.new, rozet: 'yeni' },
    { deger: 'in_review', etiket: RY.sozluk.GB_DURUM.in_review, rozet: 'uyari' },
    { deger: 'closed', etiket: RY.sozluk.GB_DURUM.closed, rozet: 'notr' }
  ];
  var TURLER = [
    { deger: 'bug', etiket: RY.sozluk.GB_TUR.bug, rozet: 'madder' },
    { deger: 'suggestion', etiket: RY.sozluk.GB_TUR.suggestion, rozet: 'lilac' },
    { deger: 'other', etiket: RY.sozluk.GB_TUR.other, rozet: 'notr' }
  ];
  var DURUM_ADI = {}, DURUM_ROZET = {};
  DURUMLAR.forEach(function (d) { DURUM_ADI[d.deger] = d.etiket; DURUM_ROZET[d.deger] = d.rozet; });
  var TUR_ADI = {}, TUR_ROZET = {};
  TURLER.forEach(function (t) { TUR_ADI[t.deger] = t.etiket; TUR_ROZET[t.deger] = t.rozet; });

  function dilAdi(k) { return RY.sozluk.dilAdi(k); }
  function platformAdi(k) { return RY.sozluk.platformAdi(k); }

  function durumRozeti(b, s) { return b.rozet(DURUM_ADI[s] || String(s || '—'), DURUM_ROZET[s] || 'notr'); }
  function turRozeti(b, t) { return b.rozet(TUR_ADI[t] || String(t || '—'), TUR_ROZET[t] || 'notr'); }

  function yol(id, ek) { return '/api/v1/admin/feedback/' + encodeURIComponent(id) + (ek || ''); }

  function hataToast(h) {
    var m = RY.hataMetni(h);
    if (m) RY.b.toast(m, 'hata');
  }

  function kirp(metin, n) {
    var s = String(metin || '').replace(/\s+/g, ' ').trim();
    return s.length > n ? s.slice(0, n - 1) + '…' : s;
  }

  function baglamMetni(k) {
    return [k.appBuild != null ? 'sürüm ' + String(k.appBuild) : null, k.platform ? platformAdi(k.platform) : null,
            k.language ? dilAdi(k.language) : null].filter(Boolean).join(' · ') || '—';
  }

  function yanitOzeti(b, k) {
    if (!k.reply) return '<span class="dipnot">—</span>';
    return k.reply.pushSent
      ? b.rozet('✓ gönderildi', 'aktif')
      : '<span title="Yanıt kaydedildi; kullanıcının cihazına bildirim gidemedi (cihaz jetonu yok)">' + b.rozet('✓ bildirim gitmedi', 'uyari') + '</span>';
  }

  function kisiHucresi(b, k) {
    var u = k.user || {};
    var ad = u.displayName || u.email || k.uid || '—';
    var alt = u.displayName && u.email ? u.email : (ad !== k.uid ? k.uid : '');
    if (!k.uid) return b.e(ad);
    return '<a href="' + b.e(RY.rotaBagi('kullanicilar', [k.uid])) + '" class="gb-kisi" title="Kullanıcı ayrıntısı">' +
      b.e(ad) + (alt ? '<span class="mono">' + b.e(alt) + '</span>' : '') + '</a>';
  }

  /* ---------------- Rota durumu ---------------- */

  function durumOku(params) {
    params = params || {};
    var status = String(params.status || 'new');
    if (status !== 'all' && !DURUM_ADI[status]) status = 'new';
    var type = TUR_ADI[params.type] ? params.type : undefined;
    return { status: status, type: type };
  }

  function paramsTemizle(d) {
    var p = {};
    if (d.status && d.status !== 'new') p.status = d.status;
    if (d.type) p.type = d.type;
    return p;
  }

  function sorguParametreleri(d) {
    return { status: d.status === 'all' ? undefined : d.status, type: d.type };
  }

  /* =====================================================================
     Yan panel — ayrıntı
     ===================================================================== */

  /* detayAc(id, satir, {onDegis(doc), onKapat}) — satır verisi hemen
     çizilir, tam doküman (notlar) sonra gelir. */
  function detayAc(id, satir, sec) {
    var b = RY.b;
    sec = sec || {};
    var doc = satir || { id: id };
    var govde = b.el('<div class="sutun gb-detay"></div>');
    var panel = b.yanPanel({
      baslik: 'Geri bildirim', icerik: govde, genislik: 600, sinif: 'gb-panel',
      odak: '#gb-yanit-form textarea',  // yeniden çizilmeyen sabit hedef
      onKapat: function () { if (sec.onKapat) sec.onKapat(); }
    });

    /* Formlar BİR kez kurulur; yenile yalnız başlık/yanıt/not bölümlerini
       yeniden çizer — GET geç gelince yazılmakta olan yanıt ve odak
       silinmez. */
    var durumF = null, yanitF = null, notF = null;

    function yenile(yeni) {
      if (yeni && typeof yeni === 'object') {
        doc = Object.assign({}, doc, yeni);
        if (sec.onDegis) sec.onDegis(doc);
      }
      var bas = govde.querySelector('#gb-bas');
      var odakIcerde = bas.contains(document.activeElement);
      bas.innerHTML = baglamHtml() + yanitHtml();
      if (odakIcerde) panel.el.focus();
      var yanitAlt = govde.querySelector('#gb-m-yanit + p');
      if (yanitAlt) yanitAlt.textContent = doc.reply ? 'yeni yanıt yeni bir bildirim gönderir' : 'kullanıcının telefonuna bildirim gider';
      govde.querySelector('#gb-notlar').innerHTML = notlarHtml();
      var sayac = govde.querySelector('#gb-not-sayac');
      sayac.innerHTML = Array.isArray(doc.notes) ? b.etiket(String(doc.notes.length)) : '';
      if (durumF) durumF.ayarla({ status: doc.status || 'new' });
    }

    function baglamHtml() {
      var u = doc.user || {};
      var ad = u.displayName || u.email || doc.uid || '—';
      return '<section class="gb-kimlik" aria-label="Gönderen">' +
        '<div class="avatar" aria-hidden="true">' + b.e(b.basHarfler(u.displayName, u.email)) + '</div>' +
        '<div class="gb-kim"><b>' + b.e(ad) + '</b>' +
        (u.email && u.displayName ? '<span class="mono">' + b.e(u.email) + '</span>' : '') +
        '<span class="mono dipnot" title="Kullanıcı kimliği">' + b.e(doc.uid || '—') + '</span></div>' +
        (doc.uid ? '<a class="buton ikincil kucuk" href="' + b.e(RY.rotaBagi('kullanicilar', [doc.uid])) + '">' +
          b.ik('kullanici', 14) + 'Ayrıntı</a>' : '') +
        '</section>' +
        '<div class="rozet-grup">' + turRozeti(b, doc.type) + ' ' + durumRozeti(b, doc.status) +
        (doc.reply ? ' ' + (doc.reply.pushSent ? b.rozet('Yanıtlandı · bildirim gitti', 'aktif') : b.rozet('Yanıtlandı · bildirim gitmedi', 'uyari')) : '') +
        '</div>' +
        '<p class="gb-metin">' + b.e(doc.text || '') + '</p>' +
        '<dl class="alan-liste">' +
        '<dt>Tarih</dt><dd>' + b.e(b.tarih(doc.createdAt, true)) + ' · ' + b.e(b.goreliZaman(doc.createdAt)) + '</dd>' +
        '<dt>Ekran</dt><dd>' + b.e(doc.screen || '—') + '</dd>' +
        '<dt>Sürüm</dt><dd>' + b.e(doc.appBuild != null ? String(doc.appBuild) : '—') + '</dd>' +
        '<dt>Platform</dt><dd>' + b.e(platformAdi(doc.platform)) + '</dd>' +
        '<dt>Dil</dt><dd>' + b.e(dilAdi(doc.language)) + '</dd>' +
        '<dt>Kayıt</dt><dd>' + b.e(doc.id || id) + '</dd>' +
        '</dl>';
    }

    function yanitHtml() {
      var r = doc.reply;
      if (!r) return '';
      return '<div class="gb-yanit"><div class="gb-yanit-bas">' + b.ik('gonder', 14) + '<b>Yanıt</b>' +
        '<span class="dipnot">' + b.e(b.tarih(r.at, true)) + (r.adminUid ? ' · ' + b.e(String(r.adminUid).slice(0, 8)) : '') + '</span>' +
        (r.pushSent ? b.rozet('bildirim gitti', 'aktif') : b.rozet('bildirim gitmedi', 'uyari')) + '</div>' +
        '<p class="gb-metin">' + b.e(r.text || '') + '</p></div>';
    }

    function notlarHtml() {
      var notlar = Array.isArray(doc.notes) ? doc.notes.slice() : null;
      if (!notlar) return b.iskelet('modul');
      if (!notlar.length) return b.bosDurum('Henüz iç not yok.', { ikon: 'kalem' });
      notlar.sort(function (x, y) {
        var tx = b.tarihNesnesi(x.at), ty = b.tarihNesnesi(y.at);
        return (ty ? ty.getTime() : 0) - (tx ? tx.getTime() : 0);
      });
      return '<div class="liste">' + notlar.map(function (n) {
        return '<div class="satir"><span class="satir-ikon">' + b.ik('kalem', 18) + '</span>' +
          '<span class="metin gb-not">' + b.e(n.text || '') +
          '<span>' + b.e(n.adminEmail || n.adminUid || '—') + ' · ' + b.e(b.tarih(n.at, true)) + '</span></span></div>';
      }).join('') + '</div>';
    }

    function ciz() {
      govde.innerHTML = '<div id="gb-bas" class="sutun"></div>' +
        b.modul('Yanıtla', '<div id="gb-yanit-form"></div>', '', { kimlik: 'gb-m-yanit', alt: 'telefona bildirim olarak gider · uygulamada yanıtı gösteren ekran YOK' }) +
        b.modul('Durum', '<div id="gb-durum-form"></div>', '', { kimlik: 'gb-m-durum', alt: 'denetim izine yazılır' }) +
        b.modul('İç notlar', '<div id="gb-notlar"></div><div id="gb-not-form"></div>',
          '<span id="gb-not-sayac"></span>', { kimlik: 'gb-m-not', alt: 'yalnız panelde görünür' });
      formlariBagla();
      yenile(null);
    }

    function formlariBagla() {
      /* Yanıt */
      yanitF = b.form({
        alanlar: [{ ad: 'text', etiket: 'Yanıt metni', tur: 'textarea', zorunlu: true, max: YANIT_MAX, satir: 4,
          yardim: 'En fazla ' + YANIT_MAX + ' karakter — bildirim metni sınırı, fazlası kırpılır · kullanıcının dilinde yaz (' + dilAdi(doc.language) + ').',
          dogrula: function (v) {
            var n = v.trim().length;
            return n < 1 ? 'Boş yanıt gönderilmez.' : (n > YANIT_MAX ? 'En fazla ' + YANIT_MAX + ' karakter.' : null);
          } }],
        gonderMetin: 'Yanıtla',
        onGonder: function (d) {
          var metin = d.text.trim();
          return b.onayla({
            baslik: 'Yanıtı gönder',
            mesaj: 'Kullanıcının telefonuna bildirim gider; metin geri alınamaz.',
            aciklama: 'Cihaz jetonu yoksa ya da kullanıcı bildirimi kaydırıp atarsa yanıt kaydedilir ama kullanıcıya HİÇ ulaşmaz: uygulamada yanıtı gösteren ekran yok. Durum "İnceleniyor" olur.',
            onaylaMetin: 'Gönder'
          }).then(function (r) {
            if (!r) return null;
            return RY.post(yol(id, '/reply'), { text: metin }).then(function (res) {
              var pushGitti = !!(res && (res.pushSent || (res.reply && res.reply.pushSent)));
              b.toast('Yanıt kaydedildi · bildirim ' + (pushGitti ? 'gitti' : 'gitmedi'), pushGitti ? 'basari' : 'uyari', { sure: 7000 });
              var yeni = { reply: (res && res.reply) || { text: metin, at: new Date().toISOString(), pushSent: pushGitti } };
              if (doc.status === 'new') yeni.status = 'in_review';
              yenile(yeni);
              yanitF.ayarla({ text: '' });
              if (RY.dikkat && RY.dikkat.yukle) RY.dikkat.yukle();
            });
          });
        }
      });
      govde.querySelector('#gb-yanit-form').appendChild(yanitF.el);

      /* Durum */
      durumF = b.form({
        alanlar: [{ ad: 'status', etiket: 'Durum', tur: 'select', deger: doc.status || 'new',
          secenekler: DURUMLAR.map(function (d) { return { deger: d.deger, etiket: d.etiket }; }) }],
        gonderMetin: 'Kaydet',
        onGonder: function (d) {
          if (d.status === doc.status) { b.toast('Durum zaten ' + DURUM_ADI[d.status] + '.', 'bilgi'); return null; }
          return RY.patch(yol(id), { status: d.status }).then(function (res) {
            b.toast('Durum güncellendi: ' + DURUM_ADI[d.status], 'basari');
            yenile(res && res.id ? res : { status: d.status });
            if (RY.dikkat && RY.dikkat.yukle) RY.dikkat.yukle();
          });
        }
      });
      govde.querySelector('#gb-durum-form').appendChild(durumF.el);

      /* Not */
      notF = b.form({
        alanlar: [{ ad: 'note', etiket: 'Yeni not', tur: 'textarea', zorunlu: true, max: NOT_MAX, satir: 2,
          yardim: 'Kullanıcı görmez; yönetici e-postası ve zamanla saklanır.',
          dogrula: function (v) { return v.trim().length < 2 ? 'En az 2 karakter.' : null; } }],
        gonderMetin: 'Not ekle',
        onGonder: function (d) {
          return RY.patch(yol(id), { note: d.note.trim() }).then(function (res) {
            b.toast('Not eklendi.', 'basari');
            notF.ayarla({ note: '' });
            if (res && res.id) yenile(res);
            else {
              var notlar = (doc.notes || []).concat([{ at: new Date().toISOString(), text: d.note.trim(),
                adminEmail: (RY.auth && RY.auth.currentUser && RY.auth.currentUser.email) || null }]);
              yenile({ notes: notlar, noteCount: notlar.length });
            }
          });
        }
      });
      govde.querySelector('#gb-not-form').appendChild(notF.el);
    }

    ciz();
    panel.ac();

    RY.get(yol(id)).then(function (res) {
      if (!panel.acikMi()) return;
      var tam = res && typeof res === 'object' ? (res.item || res.feedback || res) : {};
      if (!Array.isArray(tam.notes)) tam.notes = [];
      yenile(tam);
    }).catch(function (h) {
      if (!panel.acikMi()) return;
      var kap = govde.querySelector('#gb-notlar');
      if (kap) kap.innerHTML = b.hataDurum(RY.hataMetni(h) || 'Kayıt alınamadı.', { kimlik: 'gb-not-tekrar' });
      var t = govde.querySelector('#gb-not-tekrar');
      if (t) t.addEventListener('click', function () {
        kap.innerHTML = b.iskelet('modul');
        RY.get(yol(id)).then(function (res) { var tam = (res && (res.item || res.feedback || res)) || {}; if (!Array.isArray(tam.notes)) tam.notes = []; yenile(tam); })
          .catch(hataToast);
      });
    });

    return panel;
  }

  /* =====================================================================
     Liste
     ===================================================================== */

  async function liste(icerik, params, acikId, baglam) {
    var b = RY.b;
    var durum = durumOku(params);
    var imlec = null, istek = null, sayfaObj = null, acikPanel = null;
    var yeniIstek = b.tazeleyici(baglam);

    icerik.innerHTML =
      b.sayfaBaslik({ baslik: 'Geri bildirimler',
        alt: 'Uygulama içi Profil → Geri bildirim · yanıt kullanıcıya bildirim olarak gider · sayfa başına ' + SAYFA }) +
      '<div id="gb-filtre"></div>' +
      b.modul('Kayıtlar', '<div id="gb-tablo"></div>', '<span class="dipnot" id="gb-sayac"></span>',
        { alt: 'satıra tıkla → ayrıntı · yeniden eskiye' }) +
      '<p class="dipnot">Yanıt kullanıcının telefonuna bildirim olarak gider ve durumu "İnceleniyor" yapar; ' +
      'iç notlar yalnız panelde görünür. Durum ve not değişiklikleri denetim izine yazılır.</p>';

    var sayacEl = icerik.querySelector('#gb-sayac');

    var vt = b.veriTablosu({
      kimlik: 'gb-vt', etiket: 'Geri bildirimler', yogunluk: 'sik',
      sutunlar: [
        { ad: 'createdAt', baslik: 'Tarih', bicim: function (k) {
          return '<span class="mono" title="' + b.e(b.tarih(k.createdAt, true)) + '">' + b.e(b.goreliZaman(k.createdAt)) + '</span>';
        } },
        { ad: 'type', baslik: 'Tür', bicim: function (k) { return turRozeti(b, k.type); } },
        { ad: 'user', baslik: 'Kullanıcı', bicim: function (k) { return kisiHucresi(b, k); } },
        { ad: 'screen', baslik: 'Ekran', bicim: function (k) { return k.screen ? '<span class="mono">' + b.e(k.screen) + '</span>' : '<span class="dipnot">—</span>'; } },
        { ad: 'appBuild', baslik: 'Sürüm · platform · dil', bicim: function (k) { return '<span class="mono">' + b.e(baglamMetni(k)) + '</span>'; } },
        { ad: 'text', baslik: 'Metin', bicim: function (k) {
          return '<span class="gb-kisa" title="' + b.e(kirp(k.text, 400)) + '">' + b.e(kirp(k.text, KISA)) + '</span>' +
            (Number(k.noteCount) > 0 ? ' <span class="dipnot" title="iç not">' + b.ik('kalem', 12) + b.e(String(k.noteCount)) + '</span>' : '');
        } },
        { ad: 'status', baslik: 'Durum', bicim: function (k) { return durumRozeti(b, k.status); } },
        { ad: 'reply', baslik: 'Yanıt', bicim: function (k) { return yanitOzeti(b, k); } }
      ],
      anahtar: function (k) { return k.id; },
      satirHref: function (k) { return RY.rotaBagi('geribildirim', [k.id], paramsTemizle(durum)); },
      satirSinif: function (k) { return k.status === 'closed' ? 'durum-pasif' : (k.type === 'bug' && k.status === 'new' ? 'durum-uyari' : ''); },
      onSirala: function () { /* sunucu sıralı */ },
      bosMetin: 'Geri bildirim yok — testçiler uygulamadan Profil → Geri bildirim ile yazar.',
      onTekrar: function () { yukle(false); }
    });
    icerik.querySelector('#gb-tablo').appendChild(vt.el);

    /* Boş liste metni ETKİN süzgeci söyler. Varsayılan süzgeç "Yeni" ve
       eskiden boş liste "Geri bildirim yok" diyordu — yeni kayıt yokken
       sahip hiç geri bildirim gelmediğini sanıyordu; oysa İnceleniyor ve
       Kapandı'da kayıtlar duruyordu. */
    function bosMetni() {
      var parca = [];
      if (durum.status !== 'all') parca.push('"' + DURUM_ADI[durum.status] + '" durumunda');
      if (durum.type) parca.push('"' + TUR_ADI[durum.type] + '" türünde');
      if (!parca.length) return 'Geri bildirim yok — testçiler uygulamadan Profil → Geri bildirim ile yazar.';
      return parca.join(' ve ') + ' geri bildirim yok. Öteki kayıtlar için Durum: Tümü\'nü seç.';
    }

    function urlYaz(id) {
      RY.rotaYaz('geribildirim', id ? [id] : [], paramsTemizle(durum), { sessiz: true });
      // Sessiz yazım kırıntıyı yenilemez; panel açık/kapalı durumunu elle yansıt.
      RY.kirinti(RY.kirintiSaglayici.geribildirim(id ? [id] : []));
    }

    function satirGuncelle(doc) {
      var mevcut = vt.satirlar();
      var bulundu = false;
      var yeni = mevcut.map(function (k) {
        if (k.id !== doc.id) return k;
        bulundu = true;
        return Object.assign({}, k, { status: doc.status, reply: doc.reply,
          noteCount: Array.isArray(doc.notes) ? doc.notes.length : (doc.noteCount != null ? doc.noteCount : k.noteCount) });
      });
      if (bulundu) vt.guncelle(yeni, sayfaObj);
    }

    function panelAc(id, satir) {
      if (acikPanel && acikPanel.acikMi()) acikPanel.kapat();
      urlYaz(id);
      acikPanel = detayAc(id, satir, {
        onDegis: satirGuncelle,
        onKapat: function () {
          acikPanel = null;
          if (RY.rotaMevcut().ad === 'geribildirim') urlYaz(null);
        }
      });
    }

    vt.el.addEventListener('click', function (ev) {
      if (ev.target.closest('a.gb-kisi')) return;             // 360 bağlantısı kendi yoluna gider
      var tr = ev.target.closest('tr[data-id]');
      if (!tr || tr.classList.contains('vt-durum') || tr.classList.contains('vt-iskelet')) return;
      ev.preventDefault();
      var id = tr.getAttribute('data-id');
      var satir = vt.satirlar().filter(function (k) { return k.id === id; })[0];
      panelAc(id, satir || null);
    });

    function yukle(devam) {
      if (!devam) { imlec = null; vt.durum('yukleniyor'); istek = yeniIstek(); }
      var bu = istek;
      var p = Object.assign(sorguParametreleri(durum), { limit: SAYFA, cursor: devam ? imlec : null });
      return RY.sorgu('/api/v1/admin/feedback', p, { sinyal: bu.sinyal }).then(function (res) {
        if (!bu.gecerli()) return;
        var satirlar = Array.isArray(res && res.items) ? res.items : [];
        imlec = (res && res.nextCursor) || null;
        sayfaObj = { daha: !!imlec, onDaha: function () { return yukle(true); } };
        if (devam) vt.ekle(satirlar, sayfaObj); else vt.guncelle(satirlar, sayfaObj);
        if (!devam && !satirlar.length && !imlec) vt.durum('bos', bosMetni());
        var n = vt.satirlar().length;
        sayacEl.textContent = n ? b.sayi(n) + ' kayıt' + (imlec ? ' · devamı var' : '') : '';
        if (acikId && !devam) {
          var hedef = satirlar.filter(function (k) { return k.id === acikId; })[0] || null;
          var id = acikId; acikId = null;
          panelAc(id, hedef);
        }
      }).catch(function (h) {
        if (!bu.gecerli() || (h && h.iptal)) return;
        if (devam) hataToast(h); else vt.durum('hata', RY.hataMetni(h));
      });
    }

    var cipler = b.filtreCipleri({
      etiket: 'Süzgeçler',
      filtreler: [
        { ad: 'status', etiket: 'Durum', altin: true,
          secenekler: DURUMLAR.map(function (d) { return { deger: d.deger, etiket: d.etiket }; })
            .concat([{ deger: 'all', etiket: 'Tümü' }]) },
        { ad: 'type', etiket: 'Tür', secenekler: TURLER.map(function (t) { return { deger: t.deger, etiket: t.etiket }; }) }
      ],
      deger: { status: durum.status, type: durum.type },
      onDegis: function (d) {
        // Durum çipi kapatılınca varsayılana (Yeni) döner; "Tümü" açıkça süzgeçsizdir.
        durum.status = d.status || 'new';
        durum.type = d.type || undefined;
        if (!d.status) cipler.ayarla({ status: durum.status, type: durum.type });
        urlYaz(null);
        yukle(false);
      }
    });
    icerik.querySelector('#gb-filtre').appendChild(cipler);

    yukle(false);
  }

  /* =====================================================================
     Rota, kırıntı, palet
     ===================================================================== */

  RY.gorunumler.geribildirim = async function (icerik, args, params, baglam) {
    args = args || [];
    return liste(icerik, params, args[0] || null, baglam);
  };

  RY.kirintiSaglayici.geribildirim = function (args) {
    args = args || [];
    if (!args.length) return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Geri bildirimler' }];
    return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Geri bildirimler', href: '#/geribildirim' },
            { metin: 'Kayıt' }];
  };

  RY.palet.eylemEkle({ ad: 'geribildirim-yeni', etiket: 'Yeni geri bildirimler',
    aciklama: 'Yanıt bekleyen kayıtlar', ikon: 'geribildirim',
    calistir: function () { RY.rotaYaz('geribildirim', [], { status: 'new' }); } });
})();

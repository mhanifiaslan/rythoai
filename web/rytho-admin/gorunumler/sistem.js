/* Sistem (AD10/AD19): sağlık kartları, özet tazeliği, zamanlayıcı son
   koşuları, veritabanı dizini yoklaması, sunucu sürümü; zorunlu güncelleme
   eşiği (owner), panel duyurusu (owner), denetim izi (süzgeç + imleç),
   "Topla" (owner).

   Rota: #/sistem?action&adminUid&targetUid&from&to — denetim izi süzgeci
   adrese SESSİZ yazılır (yer imi/yenileme süzgeci korur, geçmişe kayıt
   düşmez).
   Uçlar:
   - GET  /api/v1/admin/system → {health:{firestore, fcm, rag:{healthy,
     bases:{dil:{mode, chunks, artifact}}}}, rollups:{lastStatsDate,
     lastStatsAt, lastStatsMs, lastEconomicsDate}, scheduler:{notify:{tür:
     {lastRunAt, lastStatus, date}}, stats:{lastRunAt}}, indexes:[{name, ok,
     error}], build:{revision, service, startedAt}, config:{minBuild,
     envFloor, notice}}
   - GET  /health (herkese açık) → sunucu ayakta mı + sürüm
   - GET  /api/v1/admin/min-build → {min_build, env_floor, doc, below_min_live}
   - GET  /api/v1/admin/stats?days=1 → days[0].builds {byBuild, unknown}
   - POST /api/v1/admin/min-build {min_build, reason} (owner; K9: 400
     "eşiğin üstünde kullanıcı görülmedi" mesajı olduğu gibi)
   - POST /api/v1/admin/config/notice {text, level} (owner; boş = kaldır)
   - GET  /api/v1/admin/audit?action&adminUid&targetUid&from&to&limit&cursor
     → {entries:[…], nextCursor}
   - POST /api/v1/admin/collect (owner)

   Nav sayacı RY.dikkat'ten gelir (app.js) — burada tekrarlanmaz. Ham JSON,
   koleksiyon adı, ortam değişkeni ya da komut satırı EKRANA basılmaz:
   operatöre yapılacak iş düz Türkçe cümleyle söylenir. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  var DENETIM_SAYFA = 50;
  var SERBEST_GECIKME = 400;  // ms — serbest metin süzgeci her tuşta istek atmasın
  var TURKCE_HARF = /[ğüşıöçĞÜŞİÖÇ]/;

  function S() { return RY.sozluk; }

  function eylemTuru(a) {
    if (/delete|disable/.test(a)) return 'hata';
    if (/min_build|payout|export|recompute/.test(a)) return 'uyari';
    if (/credit|enable|create|code/.test(a)) return 'altin';
    return 'notr';
  }

  function hataToast(h) {
    var m = RY.hataMetni(h);
    if (m) RY.b.toast(m, 'hata');
  }

  function durumRozeti(b, v, evet, hayir, bilinmiyor) {
    if (v === true) return b.rozet(evet || 'Sağlıklı', 'aktif');
    if (v === false) return b.rozet(hayir || 'Sorun', 'hata');
    return b.rozet(bilinmiyor || 'Bilinmiyor', 'notr');
  }

  /* Dizin yoklamasının adı ("adminAudit(action, at DESC)") koleksiyon ve
     alan adlarından oluşan bir iç tanımdır. Ekranda okunur karşılığı
     gösterilir; ham ad yalnız `title`da kalır (operatör konsolda aynı
     dizini arıyorsa). */
  var KOLEKSIYON = { adminAudit: 'Denetim izi', revenueEvents: 'Gelir olayları', usageEvents: 'Kullanım olayları',
                     phoneAttempts: 'Telefon denemeleri', users: 'Kullanıcılar', feedback: 'Geri bildirimler' };
  var ALAN = { action: 'eylem', adminUid: 'yönetici', targetUid: 'hedef', uid: 'kullanıcı', at: 'zaman',
               environment: 'ortam', eventType: 'olay türü', plan: 'plan', createdAt: 'kayıt tarihi',
               lastSeenDaily: 'son görülme', streakCount: 'seri', language: 'dil', platform: 'platform',
               authDisabled: 'devre dışı', status: 'durum', type: 'tür' };
  function dizinAdi(ham) {
    var m = /^(\w+)\((.*)\)$/.exec(String(ham || ''));
    if (!m) return String(ham || '—');
    var alanlar = m[2].split(',').map(function (x) {
      var p = x.trim().split(/\s+/);
      return (ALAN[p[0]] || p[0]) + (p[1] === 'DESC' ? ' (yeniden eskiye)' : '');
    });
    return (KOLEKSIYON[m[1]] || m[1]) + ': ' + alanlar.join(' + ');
  }

  /* Cloud Run revizyonu "rytho-backend-00110-7q7" → "00110-7q7": servis
     adı iç bir tanımlayıcı, ayırt edici kısım sondaki sayı. Kalıba
     uymazsa son 12 karakter. */
  function surumKisa(rev) {
    var m = /(\d{4,6}-[a-z0-9]+)$/i.exec(String(rev || ''));
    return m ? m[1] : String(rev || '').slice(-12);
  }

  var RAG_MOD = { vector: 'anlamsal (vektör)', keyword: 'kelime eşleşmesi', lexical: 'kelime eşleşmesi' };

  /* ---------------- Zorunlu güncelleme modülü (v2 mantığı korunur) ----------------
     İki kaynak, iki etiket: `mb` (/admin/min-build) CANLI — etkin eşik,
     sunucu tabanı, "eşiğin altında" sayımı; `builds` (son özet) — sürüm
     kırılımı ve sürüm bildirmeyen ≤34 istemcilerin "bilinmiyor" sayısı.
     Canlı sayım sürümü bilinmeyenleri görmez, o yüzden "bilinmiyor" ayrı
     karttır. */
  function esikCiz(kap, mb, builds) {
    var b = RY.b;
    var esik = mb ? mb.min_build : null;
    var dokuman = (mb && mb.doc) || null;
    var byBuild = (builds && builds.byBuild) || {};
    var kapiAcik = esik != null && esik > 0;
    var sahip = RY.sahipMi();

    var sonYazim = dokuman && dokuman.minBuild != null
      ? 'Son yazım: eşik ' + b.sayi(dokuman.minBuild) + ' — "' + (dokuman.reason || '') + '" · ' +
        (dokuman.updatedBy || '?') + ' · ' + b.tarih(dokuman.updatedAt, true)
      : (mb ? 'Henüz panelden yazılmadı — eşik yalnız sunucu ayarındaki tabandan.' : 'Eşik durumu alınamadı.');

    kap.innerHTML =
      '<section class="izgara-kpi" aria-label="Eşik durumu">' +
      b.istatistikKarti({ ad: 'Etkin eşik', deger: mb ? b.sayi(esik) : '—', altin: kapiAcik,
        alt: kapiAcik ? 'altındaki sürümler güncelleme ekranına yönlenir' : 'kapı kapalı (0)' }) +
      b.istatistikKarti({ ad: 'Sunucu tabanı', deger: mb ? b.sayi(mb.env_floor) : '—',
        alt: 'sunucu ayarında sabit en düşük eşik · isteğe bağlı' }) +
      b.istatistikKarti({ ad: 'Eşiğin altında (şu an)', deger: mb ? b.sayi(mb.below_min_live) : '—',
        alt: 'son bildirdiği sürüm eşiğin altında olan kullanıcı' }) +
      b.istatistikKarti({ ad: 'Sürümü bilinmeyen (≤34)', deger: builds ? b.sayi(builds.unknown) : '—',
        alt: 'sürüm bildirmeyen eski uygulamalar · son toplama' }) +
      '</section>' +
      '<div id="esik-tablo"></div>' +
      '<p class="dipnot">' + b.e(sonYazim) + '</p>' +
      (sahip ? '<div id="esik-form"></div>' : '<p class="dipnot">Eşiği yalnız sahip yazar.</p>') +
      '<p class="dipnot">Sunucu 0\'dan büyük eşiği ancak o sürümü bir kullanıcıda görmüşse kabul eder: ' +
      'önce yeni sürümü bir cihazda açıp giriş yap. Sıra: veritabanı kuralları → sunucu → mağazadaki ' +
      'paket → eşik.</p>';

    var satirlar = Object.keys(byBuild).map(function (s) {
      return { surum: s, sira: Number(s), kullanici: Number(byBuild[s]) || 0,
               altinda: kapiAcik && Number(s) < esik, bilinmiyor: false };
    });
    if (builds && builds.unknown > 0) {
      satirlar.push({ surum: 'bilinmiyor (≤34)', sira: -1, kullanici: Number(builds.unknown),
                      altinda: kapiAcik, bilinmiyor: true });
    }
    var vt = b.veriTablosu({
      kimlik: 'esik-surum-tablo', etiket: 'Sürüm kırılımı', yogunluk: 'sik',
      sutunlar: [
        { ad: 'sira', baslik: 'Sürüm kodu', siralanir: true,
          bicim: function (s) { return '<span class="mono">' + b.e(s.surum) + '</span>'; } },
        { ad: 'kullanici', baslik: 'Kullanıcı', hizala: 'sag', siralanir: true },
        { ad: 'altinda', baslik: 'Durum', deger: function (s) { return s.altinda ? 1 : 0; },
          bicim: function (s) {
            if (!s.altinda) return b.rozet('geçer', 'aktif');
            return b.rozet(s.bilinmiyor ? 'kilitli (sürüm bildirmiyor)' : 'eşiğin altında', 'hata');
          } }
      ],
      anahtar: function (s) { return s.surum; },
      satirSinif: function (s) { return s.altinda ? 'durum-hata' : ''; },
      siralama: { ad: 'sira', yon: 'desc' },
      bosMetin: 'Henüz sürüm kırılımı yok — 35 ve üstü uygulamaların ilk isteğiyle dolar, sonraki toplamada görünür.'
    });
    kap.querySelector('#esik-tablo').appendChild(vt.el);
    vt.guncelle(satirlar);

    if (!sahip) return;
    var f = b.form({
      alanlar: [
        { ad: 'min_build', etiket: 'Yeni eşik', tur: 'number', zorunlu: true, min: 0, max: 100000,
          adim: '1', deger: esik != null ? esik : 0, yardim: 'Sürüm kodu; 0 = kapıyı kapat' },
        { ad: 'reason', etiket: 'Gerekçe', tur: 'textarea', zorunlu: true, max: 300, satir: 2,
          yardim: 'Denetim izine yazılır (en az 3 karakter).',
          dogrula: function (v) { return v.length < 3 ? 'En az 3 karakter.' : null; } }
      ],
      gonderMetin: 'Eşiği yaz',
      onGonder: function (d) {
        var yeni = Math.round(Number(d.min_build));
        var soru = yeni > 0
          ? { baslik: 'Eşiği ' + yeni + ' yap', tehlike: true, onaylaMetin: 'Eşiği yaz',
              mesaj: 'Sürüm kodu ' + yeni + ' altındaki HER uygulama güncelleme ekranına kilitlenir — ' +
                'sürüm bildirmeyen eski uygulamalar (≤34) dahil.',
              aciklama: 'Gerekçe: "' + d.reason + '"' }
          : { baslik: 'Kapıyı kapat', onaylaMetin: 'Kapat',
              mesaj: 'Eşik 0 olacak; sunucu ayarında bir taban varsa o geçerli kalır.',
              aciklama: 'Gerekçe: "' + d.reason + '"' };
        return b.onayla(soru).then(function (r) {
          if (!r) { var h = new Error('iptal'); h.iptal = true; throw h; }
          return RY.post('/api/v1/admin/min-build', { min_build: yeni, reason: d.reason });
        }).then(function (res) {
          b.toast('Eşik yazıldı: ' + b.sayi(res && res.min_build != null ? res.min_build : yeni), 'basari');
          esikCiz(kap, res && res.min_build != null ? res : null, builds);
          if (RY.dikkat && RY.dikkat.yukle) RY.dikkat.yukle();
          var h1 = kap.closest('.modul') && kap.closest('.modul').querySelector('h2');
          if (h1) h1.focus();
        });
        // 400 (K9) ve 503 (denetim izi) Türkçe mesajları form özetine olduğu gibi düşer.
      }
    });
    kap.querySelector('#esik-form').appendChild(f.el);
  }

  /* ---------------- Duyuru ---------------- */

  function duyuruBant(b, notice) {
    if (!notice || !notice.text) return '';
    var tur = notice.level === 'warn' ? 'uyari' : 'bilgi';
    return '<div id="sistem-duyuru">' + b.bant('<b>Panel duyurusu</b> — ' + b.e(notice.text) +
      (notice.updatedAt ? ' <span class="dipnot">(' + b.e(b.tarih(notice.updatedAt, true)) + ')</span>' : ''),
      tur, { html: true }) + '</div>';
  }

  function duyuruModulu(icerik, notice) {
    var b = RY.b;
    var kap = icerik.querySelector('#duyuru-form');
    if (!kap) return;
    var f = b.form({
      alanlar: [
        { ad: 'text', etiket: 'Metin', tur: 'textarea', max: 300, satir: 2,
          deger: notice && notice.text ? notice.text : '',
          yardim: 'Boş kaydedersen duyuru kalkar. Mobil uygulama bunu OKUMAZ — yalnız panel.' },
        { ad: 'level', etiket: 'Seviye', tur: 'select',
          secenekler: [{ deger: 'info', etiket: S().SEVIYE.info }, { deger: 'warn', etiket: S().SEVIYE.warn }],
          deger: notice && notice.level ? notice.level : 'info' }
      ],
      gonderMetin: 'Duyuruyu kaydet',
      onGonder: function (d) {
        return RY.post('/api/v1/admin/config/notice', { text: d.text || '', level: d.level })
          .then(function (res) {
            var yeni = res && res.notice;
            var eski = icerik.querySelector('#sistem-duyuru');
            if (eski) eski.remove();
            if (yeni && yeni.text) {
              var bas = icerik.querySelector('.sayfa-bas');
              if (bas) bas.insertAdjacentHTML('afterend', duyuruBant(b, yeni));
            }
            b.toast(yeni && yeni.text ? 'Duyuru güncellendi.' : 'Duyuru kaldırıldı.', 'basari');
          });
      }
    });
    kap.appendChild(f.el);
  }

  /* ---------------- Denetim izi ---------------- */

  /* Kaydın `params`ı: anahtar ve değer sözlükten Türkçeye. Hata metni
     yalnız Türkçeyse olduğu gibi; değilse (ham istisna, İngilizce) genel
     bir cümle — ham metin ekrana basılmaz. */
  function ayrintiHtml(b, k) {
    var params = k.params && typeof k.params === 'object' ? k.params : {};
    function kisalt(v) { v = String(v); return v.length > 80 ? v.slice(0, 77) + '…' : v; }
    var parcalar = Object.keys(params).filter(function (a) {
      var v = params[a];
      return v !== null && v !== undefined && v !== '' && typeof v !== 'object';
    }).map(function (a) {
      return '<span>' + b.e(S().parametreAdi(a)) + '<b>' + b.e(kisalt(S().parametreDegeri(a, params[a]))) + '</b></span>';
    });
    Object.keys(params).forEach(function (a) {
      var v = params[a];
      if (v && typeof v === 'object') {
        var ic = Object.keys(v).filter(function (x) { return v[x] != null && v[x] !== ''; })
          .map(function (x) { return S().parametreAdi(x) + ': ' + S().parametreDegeri(x, v[x]); }).join(', ');
        if (ic) parcalar.push('<span>' + b.e(S().parametreAdi(a)) + '<b>' + b.e(kisalt(ic)) + '</b></span>');
      }
    });
    if (k.error) {
      var hata = TURKCE_HARF.test(String(k.error)) ? kisalt(k.error) : 'işlem tamamlanamadı';
      parcalar.push('<span>Hata<b>' + b.e(hata) + '</b></span>');
    }
    return parcalar.length ? '<span class="ayrinti-liste">' + parcalar.join('') + '</span>' : '—';
  }

  function hedefHtml(b, k) {
    if (k.targetUid) {
      return '<a class="mono" href="' + b.e(RY.rotaBagi('kullanicilar', [k.targetUid])) + '">' +
        b.e(k.targetUid) + '</a>';
    }
    var p = k.params || {};
    if (p.partnerId) {
      return '<a href="' + b.e(RY.rotaBagi('ortaklar', [p.partnerId])) + '">Ortak ' +
        b.e(String(p.partnerId).slice(0, 8)) + '</a>';
    }
    return '<span class="dipnot">—</span>';
  }

  function fazRozeti(b, faz) {
    if (!faz) return '<span class="dipnot">—</span>';
    if (faz === 'done') return b.rozet('tamam', 'aktif');
    if (faz === 'failed') return b.rozet('başarısız', 'hata');
    // `intent`: iz işlemden ÖNCE yazıldı, sonucu yazılmadı — işlem yarıda
    // kalmış ya da sunucu sonucu kaydedemeden düşmüş olabilir.
    return b.rozet('sonuçlanmadı', 'uyari');
  }
  RY.denetimFazRozeti = fazRozeti;
  RY.denetimAyrinti = ayrintiHtml;

  var SUZGEC_ALANLARI = ['action', 'adminUid', 'targetUid', 'from', 'to'];
  var GUN_DESENI = /^\d{4}-\d{2}-\d{2}$/;

  function suzgecOku(params) {
    params = params || {};
    var d = {};
    SUZGEC_ALANLARI.forEach(function (a) {
      var v = params[a] != null ? String(params[a]).trim() : '';
      if ((a === 'from' || a === 'to') && v && !GUN_DESENI.test(v)) v = '';
      d[a] = v.slice(0, a === 'action' ? 60 : 128);
    });
    return d;
  }
  function suzgecParam(d) {
    var p = {};
    SUZGEC_ALANLARI.forEach(function (a) { if (d[a]) p[a] = d[a]; });
    return p;
  }

  function denetimKur(icerik, params, baglam) {
    var b = RY.b;
    var kap = icerik.querySelector('#denetim-kap');
    if (!kap) return;
    var suzgec = suzgecOku(params);
    var imlec = null, bekleyici = null, istek = null;
    var yeniIstek = b.tazeleyici(baglam);

    /* Tek eylem kontrolü. Eskiden yanında bir de serbest metin kutusu vardı
       ve doluysa seçiciyi SESSİZCE eziyordu: seçicide "Kredi verme" görünür
       dururken liste başka bir eylemle süzülüyordu. Sözlük sunucunun tüm
       `_audit` eylemlerini taşıyor; adresten bilinmeyen bir eylem gelirse
       seçiciye o adla eklenir ki seçim görünür kalsın. */
    var bilinen = S().EYLEMLER.some(function (x) { return x[0] === suzgec.action; });
    var secenekler = '<option value="">Tümü</option>' + S().EYLEMLER.map(function (x) {
      return '<option value="' + b.e(x[0]) + '">' + b.e(x[1]) + '</option>';
    }).join('') + (suzgec.action && !bilinen
      ? '<option value="' + b.e(suzgec.action) + '">' + b.e(suzgec.action) + '</option>' : '');
    kap.innerHTML =
      '<form class="suzgec-form" id="denetim-suzgec" novalidate role="search" aria-label="Denetim izi süzgeci">' +
      '<div class="form-alan"><label for="dz-action">Eylem</label>' +
      '<select class="girdi" id="dz-action">' + secenekler + '</select></div>' +
      '<div class="form-alan"><label for="dz-admin">Yönetici kimliği</label>' +
      '<input class="girdi" id="dz-admin" maxlength="128" autocomplete="off" spellcheck="false"></div>' +
      '<div class="form-alan"><label for="dz-hedef">Hedef kullanıcı kimliği</label>' +
      '<input class="girdi" id="dz-hedef" maxlength="128" autocomplete="off" spellcheck="false"></div>' +
      '<div class="form-alan dar"><label for="dz-bas">Başlangıç</label>' +
      '<input class="girdi girdi-kisa" id="dz-bas" type="date"></div>' +
      '<div class="form-alan dar"><label for="dz-son">Bitiş (dahil)</label>' +
      '<input class="girdi girdi-kisa" id="dz-son" type="date"></div>' +
      '<div class="form-alan dar"><span class="form-etiket" aria-hidden="true">&nbsp;</span>' +
      '<button type="button" class="buton sade" id="dz-temizle">Temizle</button></div>' +
      '</form>' +
      '<p class="dipnot" id="dz-not">Süzgeç anında uygulanır · tarihler UTC gününe göre.</p>' +
      '<div id="denetim-tablo"></div>';

    var form = kap.querySelector('#denetim-suzgec');
    var alanlar = {
      action: form.querySelector('#dz-action'), adminUid: form.querySelector('#dz-admin'),
      targetUid: form.querySelector('#dz-hedef'), from: form.querySelector('#dz-bas'),
      to: form.querySelector('#dz-son')
    };
    SUZGEC_ALANLARI.forEach(function (a) { alanlar[a].value = suzgec[a]; });

    var vt = b.veriTablosu({
      kimlik: 'denetim-vt', etiket: 'Denetim izi', yogunluk: 'sik',
      sutunlar: [
        { ad: 'at', baslik: 'Zaman',
          bicim: function (k) {
            return '<span title="' + b.e(b.tarih(k.at, true)) + '">' + b.e(b.goreliZaman(k.at)) +
              '</span><span class="dipnot"> ' + b.e(b.tarih(k.at, true)) + '</span>';
          } },
        { ad: 'adminEmail', baslik: 'Yönetici',
          bicim: function (k) {
            return b.e(k.adminEmail || k.adminUid || '—') +
              (k.adminRole ? ' ' + b.rolRozeti(k.adminRole) : '');
          } },
        { ad: 'action', baslik: 'Eylem',
          bicim: function (k) {
            var a = String(k.action || '?');
            return b.rozet(S().eylemAdi(a), eylemTuru(a));
          } },
        { ad: 'targetUid', baslik: 'Hedef', bicim: function (k) { return hedefHtml(b, k); } },
        { ad: 'phase', baslik: 'Sonuç', bicim: function (k) { return fazRozeti(b, k.phase); } },
        { ad: 'params', baslik: 'Ayrıntı', bicim: function (k) { return ayrintiHtml(b, k); } }
      ],
      anahtar: function (k) { return k.id; },
      satirSinif: function (k) {
        if (k.phase === 'failed') return 'durum-hata';
        if (k.phase === 'intent') return 'durum-uyari';
        return '';
      },
      onSirala: function () { /* sunucu sıralı: en yeniden eskiye */ },
      bosMetin: 'Kayıt yok.',
      onTekrar: function () { yukle(false); }
    });
    kap.querySelector('#denetim-tablo').appendChild(vt.el);

    function suzgecVar() { return SUZGEC_ALANLARI.some(function (a) { return !!suzgec[a]; }); }

    function yukle(devam) {
      if (!devam) { vt.durum('yukleniyor'); imlec = null; istek = yeniIstek(); }
      var bu = istek;
      var p = Object.assign(suzgecParam(suzgec), { limit: DENETIM_SAYFA, cursor: devam ? imlec : null });
      return RY.sorgu('/api/v1/admin/audit', p, { sinyal: bu.sinyal }).then(function (res) {
        if (!bu.gecerli()) return;
        var kayitlar = Array.isArray(res && res.entries) ? res.entries : [];
        imlec = (res && res.nextCursor) || null;
        var sayfa = { daha: !!imlec, onDaha: function () { return yukle(true); } };
        if (devam) vt.ekle(kayitlar, sayfa);
        else if (!kayitlar.length) {
          vt.guncelle([], sayfa);
          vt.durum('bos', suzgecVar()
            ? 'Bu süzgeçle eşleşen kayıt yok — süzgeci gevşet ya da "Temizle"ye bas.'
            : 'Henüz denetim kaydı yok — ilk yazan yönetici işlemiyle dolar.');
        } else vt.guncelle(kayitlar, sayfa);
      }).catch(function (h) {
        if (!bu.gecerli() || (h && h.iptal)) return;
        if (devam) hataToast(h); else vt.durum('hata', RY.hataMetni(h));
      });
    }

    function uygula() {
      var yeni = {};
      SUZGEC_ALANLARI.forEach(function (a) { yeni[a] = String(alanlar[a].value || '').trim(); });
      if (yeni.from && yeni.to && yeni.to < yeni.from) {
        alanlar.to.setAttribute('aria-invalid', 'true');
        kap.querySelector('#dz-not').textContent = 'Bitiş, başlangıçtan önce olamaz — süzgeç uygulanmadı.';
        return;
      }
      alanlar.to.removeAttribute('aria-invalid');
      kap.querySelector('#dz-not').textContent = 'Süzgeç anında uygulanır · tarihler UTC gününe göre.';
      var degisti = SUZGEC_ALANLARI.some(function (a) { return yeni[a] !== suzgec[a]; });
      if (!degisti) return;
      suzgec = yeni;
      RY.rotaYaz('sistem', [], suzgecParam(suzgec), { sessiz: true });
      yukle(false);
    }

    // Seçici ve tarihler: değişince hemen. Serbest metin: 400 ms durunca.
    ['action', 'from', 'to'].forEach(function (a) {
      alanlar[a].addEventListener('change', function () { clearTimeout(bekleyici); uygula(); });
    });
    ['adminUid', 'targetUid'].forEach(function (a) {
      alanlar[a].addEventListener('input', function () {
        clearTimeout(bekleyici);
        bekleyici = setTimeout(uygula, SERBEST_GECIKME);
      });
    });
    form.addEventListener('submit', function (ev) { ev.preventDefault(); clearTimeout(bekleyici); uygula(); });
    kap.querySelector('#dz-temizle').addEventListener('click', function () {
      clearTimeout(bekleyici);
      SUZGEC_ALANLARI.forEach(function (a) { alanlar[a].value = ''; });
      uygula();
      alanlar.action.focus();
    });
    yukle(false);
  }

  /* ---------------- Topla (owner) ---------------- */

  function toplaAc() {
    var b = RY.b;
    return b.onayla({
      baslik: 'İstatistikleri şimdi topla',
      mesaj: 'Bugünün istatistik özeti (kullanıcı, gelir, kullanım ve ekonomi) canlı taramayla yeniden ' +
        'üretilir. Saatlik otomatik toplamayla aynı iştir; tekrar basmak zarar vermez (aynı gün ' +
        'üzerine yazılır, birikmez).',
      aciklama: 'Binlerce kullanıcıda bir-iki dakika sürebilir; denetim izine düşer.',
      onaylaMetin: 'Topla'
    }).then(function (r) {
      if (!r) return null;
      var t = b.toast('Toplanıyor…', 'bilgi', { sure: 0 });
      return RY.post('/api/v1/admin/collect').then(function (res) {
        t.kapat();
        b.toast('Toplandı: ' + (res && res.date ? b.tarih(res.date) : 'bugün') +
          (res && res.durationMs != null ? ' · ' + b.sayi(Math.max(1, Math.round(res.durationMs / 1000))) + ' sn' : ''),
          'basari', { sure: 7000 });
        if (RY.dikkat && RY.dikkat.yukle) RY.dikkat.yukle();
        var r2 = RY.rotaMevcut();
        if (r2.ad === 'sistem' || r2.ad === 'genel') RY.rotaYenile();
      }).catch(function (h) { t.kapat(); throw h; });
    }).catch(hataToast);
  }
  RY.palet.eylemEkle({ ad: 'sistem-topla', etiket: 'İstatistikleri şimdi topla',
    aciklama: 'bugünün istatistik özeti', ikon: 'yenile', rol: 'owner', calistir: toplaAc });

  /* ---------------- Görünüm ---------------- */

  RY.gorunumler.sistem = async function (icerik, args, params, baglam) {
    var b = RY.b;
    // /admin/system görünümün omurgası — düşerse router hata durumunu çizer.
    // Yardımcı uçlar düşse de sayfa açılır; ilgili bölüm "—" gösterir.
    var hepsi = await Promise.all([
      RY.get('/api/v1/admin/system', { sinyal: baglam && baglam.sinyal }),
      RY.saglik('/health').catch(function () { return null; }),
      RY.get('/api/v1/admin/min-build').catch(function () { return null; }),
      RY.sorgu('/api/v1/admin/stats', { days: 1 }).catch(function () { return { days: [] }; })
    ]);
    if (baglam && !baglam.aktif()) return;
    var sys = hepsi[0] || {}, saglik = hepsi[1], mb = hepsi[2];
    var builds = (((hepsi[3] || {}).days || [])[0] || {}).builds || null;
    var health = sys.health || {}, rag = health.rag || {};
    var rollups = sys.rollups || {}, scheduler = sys.scheduler || {};
    var indexes = Array.isArray(sys.indexes) ? sys.indexes : [];
    var build = sys.build || {}, config = sys.config || {};
    var sahip = RY.sahipMi();

    var statsSaat = b.saatFarki(rollups.lastStatsAt);
    var bayat = statsSaat == null || statsSaat > b.OZET_BAYAT_SAAT;
    var indeksEksik = indexes.filter(function (i) { return i.ok === false; }).length;
    var indeksBilinmiyor = indexes.filter(function (i) { return i.ok == null; }).length;
    var revizyon = (saglik && (saglik.revision || saglik.rev || saglik.build)) || build.revision || null;

    var eylemler = '';
    if (sahip) {
      eylemler = '<button type="button" class="buton" id="sistem-topla">' + b.ik('yenile', 16) + 'Topla</button>';
    }

    var dilSayisi = Object.keys(rag.bases || {}).length;
    var kartlar = '<section class="izgara-kpi" aria-label="Sağlık">' +
      b.istatistikKarti({ ad: 'Sunucu', deger: saglik ? 'Açık' : 'Erişilemiyor', altin: !!saglik,
        alt: revizyon ? 'sürüm ' + surumKisa(revizyon) : 'sürüm bilgisi yok' }) +
      b.istatistikKarti({ ad: 'Veritabanı', deger: health.firestore === true ? 'Sağlıklı'
        : (health.firestore === false ? 'Sorun' : '—'), alt: 'uygulama ayarı okunabiliyor mu' }) +
      b.istatistikKarti({ ad: 'Bildirim servisi', deger: health.fcm === true ? 'Hazır'
        : (health.fcm === false ? 'Kapalı' : '—'), alt: 'cihazlara bildirim gönderimi' }) +
      b.istatistikKarti({ ad: 'Bilgi tabanı', deger: rag.healthy === true ? 'Anlamsal arama' : (rag.healthy === false ? 'Eksik' : '—'),
        alt: dilSayisi + ' dil' }) +
      b.istatistikKarti({ ad: 'İstatistik özeti', deger: statsSaat == null ? '—' : b.goreliZaman(rollups.lastStatsAt),
        alt: bayat ? 'bayat (' + b.OZET_BAYAT_SAAT + ' saatten eski)' : 'saatte bir güncellenir', altin: !bayat }) +
      b.istatistikKarti({ ad: 'Veritabanı dizinleri', deger: b.sayi(indexes.length - indeksEksik - indeksBilinmiyor) + ' / ' + b.sayi(indexes.length),
        alt: indeksEksik ? indeksEksik + ' eksik' : (indeksBilinmiyor ? indeksBilinmiyor + ' yoklanamadı' : 'hepsi tamam') }) +
      '</section>';

    var ragSatirlar = Object.keys(rag.bases || {}).map(function (dil) {
      var t = rag.bases[dil] || {};
      return '<tr><th scope="row">' + b.e(S().dilAdi(dil)) + '</th><td>' +
        (t.mode === 'vector' ? b.rozet(RAG_MOD.vector, 'aktif') : b.rozet(RAG_MOD[t.mode] || t.mode || '—', 'uyari')) +
        '</td><td class="sayi">' + b.e(b.sayi(t.chunks)) + '</td><td>' +
        (t.artifact ? b.rozet('var', 'aktif') : b.rozet('yok', 'hata')) + '</td></tr>';
    }).join('');
    var ragTablo = ragSatirlar
      ? '<div class="tablo-sarici"><table class="tablo"><thead><tr><th scope="col">Dil</th>' +
        '<th scope="col">Arama türü</th><th scope="col">Parça</th><th scope="col">Dizin dosyası</th></tr></thead>' +
        '<tbody>' + ragSatirlar + '</tbody></table></div>'
      : b.bosDurum(rag.healthy == null ? 'Bilgi tabanı özeti alınamadı.' : 'Dil tabanı yok.');

    function kosuRozeti(k) {
      if (!k.lastRunAt) return b.rozet('kayıt yok', 'notr');
      if (k.lastStatus === 'ok') return b.rozet(S().kosuDurumAdi('ok'), 'aktif');
      return b.rozet(S().kosuDurumAdi(k.lastStatus || '?'), /tamamen/.test(String(k.lastStatus)) ? 'hata' : 'uyari');
    }
    var bildirimSatirlari = S().bildirimTurleri().map(function (t) {
      var k = (scheduler.notify || {})[t.deger] || {};
      return '<tr><th scope="row">Bildirim · ' + b.e(t.etiket) + '</th><td>' +
        b.e(b.tarih(k.lastRunAt, true)) + '</td><td>' + b.e(k.date ? b.tarih(k.date) : '—') +
        '</td><td>' + kosuRozeti(k) + '</td></tr>';
    });
    var zamanlayiciSatir = [
      '<tr><th scope="row">İstatistik toplama (saatte bir)</th><td>' + b.e(b.tarih(scheduler.stats && scheduler.stats.lastRunAt, true)) +
      '</td><td>' + b.e(rollups.lastStatsDate ? b.tarih(rollups.lastStatsDate) : '—') +
      '</td><td>' + (bayat ? b.rozet('bayat', 'hata') : b.rozet('güncel', 'aktif')) + '</td></tr>'
    ].concat(bildirimSatirlari).join('');
    var zamanlayiciTablo = '<div class="tablo-sarici"><table class="tablo"><thead><tr>' +
      '<th scope="col">İş</th><th scope="col">Son koşu</th><th scope="col">Gün (UTC)</th><th scope="col">Durum</th>' +
      '</tr></thead><tbody>' + zamanlayiciSatir + '</tbody></table></div>';

    var tazelik = '<dl class="alan-liste">' +
      '<dt>Son özet günü</dt><dd>' + b.e(rollups.lastStatsDate ? b.tarih(rollups.lastStatsDate) : '—') + '</dd>' +
      '<dt>Üretildi</dt><dd>' + b.e(rollups.lastStatsAt ? b.tarih(rollups.lastStatsAt, true) + ' · ' + b.goreliZaman(rollups.lastStatsAt) : '—') + '</dd>' +
      '<dt>Toplama süresi</dt><dd>' + b.e(rollups.lastStatsMs != null ? b.sayi(Math.max(1, Math.round(rollups.lastStatsMs / 1000))) + ' sn' : '—') + '</dd>' +
      '<dt>Son ekonomi özeti günü</dt><dd>' + b.e(rollups.lastEconomicsDate ? b.tarih(rollups.lastEconomicsDate) : '—') + '</dd>' +
      '<dt>Sunucu sürümü</dt><dd>' + (build.revision ? '<span class="mono">' + b.e(build.revision) + '</span>' : '—') + '</dd>' +
      '<dt>Sunucu örneği</dt><dd>' + b.e(build.startedAt ? b.sureMetni(build.startedAt) + ' açık' : '—') + '</dd>' +
      '</dl>';

    var indeksSatir = indexes.map(function (i) {
      return '<tr' + (i.ok === false ? ' class="durum-hata"' : '') + '><th scope="row" title="' + b.e(i.name) + '">' +
        b.e(dizinAdi(i.name)) + '</th><td>' + durumRozeti(b, i.ok, 'tamam', 'eksik', 'yoklanamadı') + '</td></tr>';
    }).join('');
    var indeksTablo = indeksSatir
      ? '<div class="tablo-sarici"><table class="tablo"><thead><tr><th scope="col">Sorgu</th>' +
        '<th scope="col">Durum</th></tr></thead><tbody>' + indeksSatir + '</tbody></table></div>'
      : b.bosDurum('Dizin yoklaması yapılamadı (veritabanına ulaşılamadı).');

    icerik.innerHTML =
      b.sayfaBaslik({ baslik: 'Sistem', alt: 'Sağlık, istatistik özeti, zamanlayıcı, veritabanı dizinleri, zorunlu güncelleme, duyuru, denetim izi',
        eylemlerHtml: eylemler }) +
      duyuruBant(b, config.notice) +
      (bayat ? b.bant('<b>İstatistik özeti bayat</b> — özet ' + (statsSaat == null ? 'hiç üretilmemiş'
        : b.e(b.sayi(Math.round(statsSaat))) + ' saattir yenilenmedi') + '; saatlik toplama kaçmış olabilir.' +
        (sahip ? ' "Topla" ile bugünü üret.' : ''), 'uyari', { html: true }) : '') +
      (indeksEksik ? b.bant('<b>' + indeksEksik + ' veritabanı dizini eksik</b> — ilgili panel sorguları boş ya da hata döner. ' +
        'Dizin tanımları veritabanına yeniden yüklenince oluşur; derlenmesi dakikalar sürer.', 'hata', { html: true }) : '') +
      kartlar +
      '<div class="izgara-2">' +
      b.modul('Özet ve sunucu', tazelik, '', { alt: 'saatlik toplama · çalışan sunucu sürümü' }) +
      b.modul('Zamanlayıcı son koşular', zamanlayiciTablo, '', { alt: 'bugün, yoksa en son' }) +
      '</div>' +
      '<div class="izgara-2">' +
      b.modul('Bilgi tabanları', ragTablo, '', { alt: 'dil başına anlamsal arama tabanı' }) +
      b.modul('Veritabanı dizinleri', indeksTablo, '', { alt: 'her dizin için tek kayıtlık deneme sorgusu' }) +
      '</div>' +
      b.modul('Zorunlu güncelleme', '<div id="sistem-esik"></div>', '',
        { alt: 'eşiğin altındaki uygulamalar güncelleme ekranına yönlenir · anında etkili' }) +
      b.modul('Panel duyurusu', sahip ? '<div id="duyuru-form"></div>'
        : '<p class="dipnot">' + b.e(config.notice && config.notice.text
          ? 'Geçerli duyuru sayfanın üstünde. Yalnız sahip değiştirir.' : 'Duyuru yok. Yalnız sahip yazar.') + '</p>',
        '', { alt: 'yalnız bu panelin üstünde görünür · mobil uygulama okumaz' }) +
      b.modul('Denetim izi', '<div id="denetim-kap"></div>', '',
        { alt: 'Yöneticilerin yaptığı her değişiklik · en yeni üstte' });

    esikCiz(icerik.querySelector('#sistem-esik'), mb, builds);
    duyuruModulu(icerik, config.notice);
    denetimKur(icerik, params, baglam);

    var topla = icerik.querySelector('#sistem-topla');
    if (topla) topla.addEventListener('click', toplaAc);
  };

  RY.kirintiSaglayici.sistem = function () {
    return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Sistem' }];
  };
})();

/* Genel Bakış (AD19): işletme masasının ilk ekranı — bugünün sayıları,
   eğilim (fetch'siz metrik × aralık geçişi), dikkat listesi, son
   yönetici işlemleri, işletme durumu (30g üretim marjı), plan dağılımı,
   bugünkü AI kırılımı; hızlı kredi ve "Topla" (owner).

   Rota: #/genel (parametre yok).
   Uçlar (hepsi paralel; yalnız stats omurgadır, gerisi düşerse ilgili
   bölüm "—" gösterir):
   - GET /api/v1/admin/stats?days=90 → {days:[{date, generatedAt,
     durationMs, users:{dau, newToday, total, byPlan}, subs:{active,
     trialing, mrrUsd}, revenue:{grossToday, refundsToday, byEnv:{ENV:
     {gross, refunds, eventCounts}}}, ai:{callsToday, estCostToday,
     byFeature, costByFeature}, notify:{tür:{sent, failed}}}]} yeniden eskiye
   - GET /api/v1/admin/live → {today, newUsersToday (−1 = sayılamadı)}
   - GET /api/v1/admin/attention → [{tur, sayi, rota, seviye}]
   - GET /api/v1/admin/audit?limit=8 → {entries}
   - GET /api/v1/admin/notify-runs?days=2 → {runs:[{date, type, sent,
     failed}]}
   - POST /api/v1/admin/users/{uid}/credit {amount, reason}
   - POST /api/v1/admin/collect (owner)
   economics çağrısı YOK (AD19): işletme durumu stats günlerinden türetilir.
   Günler UTC; maliyetler tahmini. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  var MAGAZA_PAYI = 0.15;
  var ARALIKLAR = [7, 30, 90];
  var KIVILCIM_GUN = 14;

  /* Özellik anahtarı → okunur ad (kullanim.js ile aynı sözlük). */
  var OZELLIK = {
    chat: 'Sohbet', signal: 'Sinyal paketi', natal: 'Natal rapor',
    iching: 'İ Ching', iching_verdict: 'İ Ching hükmü', face: 'Yüz okuma',
    bazi: 'BaZi', dyad: 'İkili', synastry: 'Sinastri', relationship: 'İlişki',
    birth_hexagram: 'Doğum heksagramı', solar_return: 'Yıl haritası',
    progressions: 'Progresyon', calendar: 'Takvim', daily: 'Günlük',
    horoscope: 'Burç yorumu', memory_extract: 'Hafıza çıkarımı',
    push_daily: 'Günlük push', unknown: 'Bilinmeyen'
  };
  function ozellikAdi(k) { return OZELLIK[k] || String(k); }

  /* admin_service.attention() `tur` anahtarları → etiket/alt. Bilinmeyen
     anahtar olduğu gibi yazılır; rota ve seviye sunucudan gelir. */
  var DIKKAT = {
    failedPushesToday: ['Başarısız push (bugün)', 'Bugünkü koşularda geçersiz jeton'],
    billingIssues7d: ['Fatura sorunu (7 gün)', 'BILLING_ISSUE olayları · üretim'],
    trialsExpiring3d: ['Süresi dolan deneme (3 gün)', 'Dönüşüm fırsatı'],
    belowMin: ['Eşik altı istemci', 'Zorunlu güncelleme eşiğinin altında'],
    disabledTotal: ['Devre dışı hesap', 'authDisabled'],
    rollupStale: ['Bayat rollup', 'adminStats 30 saatten eski (değer: saat)']
  };
  var SEVIYE_SIRA = { hata: 0, uyari: 1, bilgi: 2 };

  /* Denetim eylemi → [ad, ikon, ikon sınıfı]. */
  var EYLEM = {
    'user.credit': ['Kredi', 'jeton', 'altin'], 'user.disable': ['Devre dışı', 'kilit', 'kirmizi'],
    'user.enable': ['Devreye al', 'basari', 'yesil'], 'user.delete': ['Hesap sil', 'cop', 'kirmizi'],
    'user.auth_link': ['Kimlik bağlantısı', 'anahtar', ''], 'device.release': ['Cihaz kilidi sıfırla', 'cihaz', ''],
    'config.min_build': ['Eşik yaz', 'sistem', 'altin'], 'config.notice': ['Duyuru', 'duyuru', ''],
    'notify.dry_run': ['Prova', 'zil', ''], 'notify.test_send': ['Test bildirimi', 'gonder', ''],
    'partner.create': ['Ortak ekle', 'ortaklar', 'yesil'], 'partner.update': ['Ortak güncelle', 'ortaklar', ''],
    'partner.code': ['Ortak kodu', 'ortaklar', 'altin'], 'partner.payout': ['Ortak ödemesi', 'gelir', 'altin'],
    'export.users': ['CSV: kullanıcılar', 'indir', ''], 'export.revenue': ['CSV: gelir', 'indir', ''],
    'stats.collect': ['Topla', 'yenile', ''], 'stats.recompute': ['Yeniden hesapla', 'gelir', '']
  };

  function hataToast(h) {
    var m = RY.hataMetni(h);
    if (m) RY.b.toast(m, 'hata');
  }

  function sayiMi(v) { return typeof v === 'number' && isFinite(v) && v !== -1; }

  /* ---------------- Gün serisi yardımcıları ---------------- */

  function uretimKova(g) {
    var r = g.revenue || {};
    return (r.byEnv && r.byEnv.PRODUCTION) || null;
  }
  function uretimGelir(g) {
    var k = uretimKova(g);
    if (k) return Number(k.gross) || 0;
    return Number((g.revenue || {}).grossToday) || 0;
  }
  function uretimIade(g) {
    var k = uretimKova(g);
    if (k) return Number(k.refunds) || 0;
    return Number((g.revenue || {}).refundsToday) || 0;
  }
  function olaySayisi(g, tur) {
    var k = uretimKova(g);
    var sayaclar = (k && k.eventCounts) || (g.revenue || {}).eventCounts || {};
    return Number(sayaclar[tur]) || 0;
  }
  function aiMaliyet(g) {
    var v = (g.ai || {}).estCostToday;
    return sayiMi(v) ? v : 0;
  }
  function toplam(dilim, al) {
    return dilim.reduce(function (t, g) { return t + (Number(al(g)) || 0); }, 0);
  }
  function ortalama(dilim, al) {
    return dilim.length ? toplam(dilim, al) / dilim.length : 0;
  }
  function yuzdeFark(simdi, once) {
    if (!once) return null;
    return (simdi - once) / Math.abs(once) * 100;
  }

  var METRIKLER = {
    dau: { ad: 'Günlük aktif kullanıcı', bicim: 'sayi', renk: 'magenta', birikimli: false,
      al: function (g) { return Number((g.users || {}).dau) || 0; } },
    yeni: { ad: 'Yeni kayıt', bicim: 'sayi', renk: 'lilac', birikimli: true,
      al: function (g) { return Number((g.users || {}).newToday) || 0; } },
    gelir: { ad: 'Brüt gelir (üretim)', bicim: 'para', renk: 'gold', birikimli: true, al: uretimGelir },
    maliyet: { ad: 'Tahmini AI maliyeti', bicim: 'para', renk: 'madder', birikimli: true, al: aiMaliyet }
  };
  var METRIK_ETIKET = { dau: 'DAU', yeni: 'Yeni', gelir: 'Gelir', maliyet: 'Maliyet' };

  /* ---------------- Dikkat ---------------- */

  function dikkatListesi(res) {
    var kaynak = Array.isArray(res) ? res
      : (res && (res.items || res.attention || res.kalemler)) || null;
    if (!Array.isArray(kaynak)) {
      // Uç düştüyse zilin son bildiği liste (app.js normalize etmiştir).
      return (RY.dikkat && RY.dikkat.maddeler || []).map(function (m) {
        return { anahtar: m.anahtar, etiket: m.etiket, alt: m.alt, sayi: m.sayi,
                 href: m.href, tur: m.tur };
      });
    }
    return kaynak.filter(function (m) { return m && typeof m === 'object'; }).map(function (m) {
      var anahtar = m.tur || m.key || m.kind || '';
      var sabl = DIKKAT[anahtar] || [anahtar || 'Madde', ''];
      var sayi = Number(m.sayi != null ? m.sayi : m.count) || 0;
      var tur = m.seviye || m.level || 'bilgi';
      return { anahtar: anahtar, etiket: m.label || sabl[0], alt: m.detail || sabl[1],
               sayi: sayi, href: m.rota || m.route || '#/genel',
               tur: SEVIYE_SIRA[tur] != null ? tur : 'bilgi' };
    }).filter(function (m) { return m.sayi > 0; }).sort(function (a, c) {
      return SEVIYE_SIRA[a.tur] - SEVIYE_SIRA[c.tur] || c.sayi - a.sayi;
    });
  }

  function dikkatHtml(b, maddeler) {
    if (!maddeler.length) return b.bosDurum('Bekleyen madde yok — gökyüzü sakin.', { ikon: 'basari' });
    return '<div class="liste">' + maddeler.map(function (m) {
      return '<a href="' + b.e(m.href) + '"><span class="nokta ' + b.e(m.tur) + '" aria-hidden="true"></span>' +
        '<span class="metin">' + b.e(m.etiket) + (m.alt ? '<span>' + b.e(m.alt) + '</span>' : '') + '</span>' +
        '<span class="sayi">' + b.e(b.sayi(m.sayi)) + '</span>' + b.ik('ok', 18) + '</a>';
    }).join('') + '</div>';
  }

  /* ---------------- Son işlemler ---------------- */

  function islemHtml(b, k) {
    var a = String(k.action || '?');
    var e = EYLEM[a] || [a, 'denetim', ''];
    var p = k.params && typeof k.params === 'object' ? k.params : {};
    var baslik = e[0];
    if (a === 'user.credit' && p.amount != null) baslik += ' · ' + b.sayi(Number(p.amount)) + ' kredi';
    if (a === 'notify.dry_run' || a === 'notify.test_send') baslik += p.type ? ' · ' + p.type : '';
    if (a === 'stats.recompute' && p.from) baslik += ' · ' + b.tarih(p.from) + '–' + b.tarih(p.to);
    if (a === 'config.min_build' && p.min_build != null) baslik += ' · ' + b.sayi(Number(p.min_build));
    var hedef = k.targetUid ? ' → <b class="mono">' + b.e(String(k.targetUid).slice(0, 10)) + '…</b>' : '';
    var kim = k.adminEmail ? String(k.adminEmail).split('@')[0] : (k.adminUid || '?');
    var alt = kim + (p.reason ? ' · "' + String(p.reason).slice(0, 60) + '"' : '') +
      (k.phase === 'failed' ? ' · DÜŞTÜ' : '');
    var govde = '<span class="satir-ikon' + (e[2] ? ' ' + e[2] : '') + '">' + b.ik(e[1], 18) + '</span>' +
      '<span class="metin">' + b.e(baslik) + hedef + '<span>' + b.e(alt) + '</span></span>' +
      '<span class="sayi" title="' + b.e(b.tarih(k.at, true)) + '">' + b.e(b.goreliZaman(k.at)) + '</span>';
    return k.targetUid
      ? '<a class="satir" href="' + b.e(RY.rotaBagi('kullanicilar', [k.targetUid])) + '">' + govde + '</a>'
      : '<div class="satir">' + govde + '</div>';
  }

  /* ---------------- Hızlı kredi (modal) ---------------- */

  function alanSec(q) {
    if (q.charAt(0) === '@') return { alan: 'kullanici', q: q.slice(1) };
    if (q.indexOf('@') > 0) return { alan: 'eposta', q: q };
    return { alan: 'ad', q: q };
  }

  function hizliKrediAc(onBitti) {
    var b = RY.b;
    var secili = null;
    var denetleyici = null, bekleyici = null;

    var govde = b.el('<div class="form"></div>');
    govde.innerHTML =
      '<div class="form-alan"><label for="hk-ara">Kullanıcı</label>' +
      '<input class="girdi" id="hk-ara" type="search" autocomplete="off" spellcheck="false" ' +
      'placeholder="e-posta, @kullanıcıadı ya da ad (önek)" aria-describedby="hk-ara-y" ' +
      'aria-controls="hk-sonuc" aria-autocomplete="list"></div>' +
      '<div class="form-yardim" id="hk-ara-y">En az 2 karakter; ilk 8 eşleşme listelenir.</div>' +
      '<div class="liste" id="hk-sonuc" role="listbox" aria-label="Eşleşen kullanıcılar"></div>' +
      '<div id="hk-secili" hidden></div>' +
      '<div id="hk-form" hidden></div>';
    var ara = govde.querySelector('#hk-ara');
    var sonuc = govde.querySelector('#hk-sonuc');
    var seciliKap = govde.querySelector('#hk-secili');
    var formKap = govde.querySelector('#hk-form');

    var m = b.modal({ baslik: 'Hızlı kredi', icerik: govde, genislik: 520, odak: '#hk-ara',
      onKapat: function () { if (denetleyici) denetleyici.abort(); clearTimeout(bekleyici); } });

    var f = b.form({
      alanlar: [
        { ad: 'amount', etiket: 'Kredi', tur: 'number', zorunlu: true, min: 1, max: 5000, adim: '1',
          yardim: '1–5000 · yalnız pozitif (düşüm bilerek yok)',
          dogrula: function (v) {
            var n = Number(v);
            return (!isFinite(n) || n < 1 || n > 5000 || n !== Math.round(n)) ? '1–5000 arası tam sayı.' : null;
          } },
        { ad: 'reason', etiket: 'Gerekçe', tur: 'textarea', zorunlu: true, max: 300, satir: 2,
          yardim: 'Defter + denetim izine yazılır (en az 3 karakter).',
          dogrula: function (v) { return v.trim().length < 3 ? 'En az 3 karakter.' : null; } }
      ],
      gonderMetin: 'Kredi ver',
      iptal: { metin: 'Vazgeç', onTikla: function () { m.kapat(); } },
      onGonder: function (d) {
        if (!secili) { f.hata(null, 'Önce listeden bir kullanıcı seç.'); ara.focus(); return; }
        var tutar = Math.round(Number(d.amount));
        return RY.post('/api/v1/admin/users/' + encodeURIComponent(secili.uid) + '/credit',
          { amount: tutar, reason: d.reason.trim() }).then(function (res) {
          var c = (res && res.wallet) || null;
          b.toast(b.sayi(tutar) + ' kredi verildi → ' + (secili.displayName || secili.email || secili.uid) +
            (c ? ' · bakiye ' + b.sayi((Number(c.allowance) || 0) + (Number(c.purchased) || 0)) : ''),
            'basari', { eylem: { metin: '360', onTikla: function () { RY.rotaYaz('kullanicilar', [secili.uid]); } } });
          m.kapat();
          if (onBitti) onBitti();
        });
      }
    });
    formKap.appendChild(f.el);

    function sec(u) {
      secili = u;
      seciliKap.hidden = false;
      seciliKap.innerHTML = '<div class="liste"><div class="satir"><span class="satir-ikon avatar-hucre">' +
        b.e(b.basHarfler(u.displayName, u.email)) + '</span><span class="metin">' +
        b.e(u.displayName || u.email || u.uid) + '<span>' + b.e([u.email, u.username ? '@' + u.username : null, u.uid]
          .filter(Boolean).join(' · ')) + '</span></span>' +
        (u.plan ? b.planRozeti(u.plan, u.createdAt) : '') +
        '<button type="button" class="buton sade kucuk" id="hk-degistir">Değiştir</button></div></div>';
      sonuc.innerHTML = '';
      ara.setAttribute('aria-expanded', 'false');
      formKap.hidden = false;
      seciliKap.querySelector('#hk-degistir').addEventListener('click', function () {
        secili = null; seciliKap.hidden = true; formKap.hidden = true; ara.focus();
      });
      f.kontrol('amount').focus();
    }

    function listele(liste) {
      if (!liste.length) {
        sonuc.innerHTML = '<div class="palet-bos">Eşleşme yok</div>';
        ara.setAttribute('aria-expanded', 'true');
        return;
      }
      sonuc.innerHTML = liste.map(function (u, i) {
        return '<button type="button" class="satir" role="option" data-i="' + i + '" aria-selected="false">' +
          '<span class="satir-ikon avatar-hucre">' + b.e(b.basHarfler(u.displayName, u.email)) + '</span>' +
          '<span class="metin">' + b.e(u.displayName || u.email || u.uid) + '<span>' +
          b.e([u.email, u.username ? '@' + u.username : null].filter(Boolean).join(' · ') || u.uid) +
          '</span></span>' + (u.plan ? b.planRozeti(u.plan) : '') + '</button>';
      }).join('');
      ara.setAttribute('aria-expanded', 'true');
      sonuc.querySelectorAll('[data-i]').forEach(function (d) {
        d.addEventListener('click', function () { sec(liste[Number(d.getAttribute('data-i'))]); });
      });
    }

    ara.addEventListener('input', function () {
      clearTimeout(bekleyici);
      if (denetleyici) denetleyici.abort();
      var ham = ara.value.trim();
      if (ham.length < 2) { sonuc.innerHTML = ''; ara.setAttribute('aria-expanded', 'false'); return; }
      bekleyici = setTimeout(function () {
        var s = alanSec(ham);
        denetleyici = new AbortController();
        var bu = denetleyici;
        sonuc.innerHTML = '<div class="palet-bos">Aranıyor…</div>';
        RY.sorgu('/api/v1/admin/users', { q: s.q, alan: s.alan, limit: 8 }, { sinyal: bu.signal })
          .then(function (res) {
            if (bu.signal.aborted) return;
            listele(((res && res.users) || []).slice(0, 8));
          }).catch(function (h) {
            if (h && h.iptal) return;
            sonuc.innerHTML = '<div class="palet-bos">' + b.e(RY.hataMetni(h)) + '</div>';
          });
      }, 300);
    });
    ara.addEventListener('keydown', function (ev) {
      if (ev.key === 'ArrowDown') {
        var ilk = sonuc.querySelector('[role="option"]');
        if (ilk) { ev.preventDefault(); ilk.focus(); }
      }
    });
    sonuc.addEventListener('keydown', function (ev) {
      var d = ev.target.closest('[role="option"]');
      if (!d) return;
      var hepsi = Array.prototype.slice.call(sonuc.querySelectorAll('[role="option"]'));
      var i = hepsi.indexOf(d);
      if (ev.key === 'ArrowDown' && hepsi[i + 1]) { ev.preventDefault(); hepsi[i + 1].focus(); }
      else if (ev.key === 'ArrowUp') { ev.preventDefault(); (hepsi[i - 1] || ara).focus(); }
    });

    m.ac();
  }
  RY.palet.eylemEkle({ ad: 'genel-hizli-kredi', etiket: 'Hızlı kredi ver', aciklama: 'kullanıcı ara → kredi yükle',
    ikon: 'jeton', calistir: function () { hizliKrediAc(); } });

  /* ---------------- Topla (owner) ---------------- */

  function toplaAc() {
    var b = RY.b;
    return b.onayla({
      baslik: 'İstatistikleri şimdi topla',
      mesaj: 'Bugünün adminStats ve adminEconomics dokümanları canlı taramayla yeniden üretilir; ' +
        'gecelik işle aynıdır ve idempotenttir (aynı gün ezilir, birikmez).',
      aciklama: 'Binlerce kullanıcıda bir-iki dakika sürebilir; denetim izine düşer.',
      onaylaMetin: 'Topla'
    }).then(function (r) {
      if (!r) return null;
      var t = b.toast('Toplanıyor…', 'bilgi', { sure: 0 });
      return RY.post('/api/v1/admin/collect').then(function (res) {
        t.kapat();
        b.toast('Toplandı: ' + (res && res.date ? res.date : 'bugün') +
          (res && res.durationMs != null ? ' · ' + b.sayi(res.durationMs) + ' ms' : ''), 'basari', { sure: 7000 });
        if (RY.dikkat && RY.dikkat.yukle) RY.dikkat.yukle();
        RY.rotaYenile();
      }).catch(function (h) { t.kapat(); throw h; });
    }).catch(hataToast);
  }
  // Palet kaydı sistem.js'te ('sistem-topla'); burada yalnız başlık düğmesi.

  /* ---------------- Görünüm ---------------- */

  RY.gorunumler.genel = async function (icerik) {
    var b = RY.b;
    var hepsi = await Promise.all([
      RY.sorgu('/api/v1/admin/stats', { days: 90 }),
      RY.get('/api/v1/admin/live').catch(function () { return {}; }),
      RY.get('/api/v1/admin/attention').catch(function () { return null; }),
      RY.sorgu('/api/v1/admin/audit', { limit: 8 }).catch(function () { return { entries: [] }; }),
      RY.sorgu('/api/v1/admin/notify-runs', { days: 2 }).catch(function () { return { runs: [] }; })
    ]);
    var stats = hepsi[0] || {}, canli = hepsi[1] || {};
    var dikkat = dikkatListesi(hepsi[2]);
    var izler = Array.isArray((hepsi[3] || {}).entries) ? hepsi[3].entries : [];
    var kosular = Array.isArray((hepsi[4] || {}).runs) ? hepsi[4].runs : [];
    var sahip = RY.sahipMi();

    var gunler = (stats.days || []).slice().reverse();  // eskiden yeniye
    var son = gunler[gunler.length - 1] || null;
    var bugun = new Date().toISOString().slice(0, 10);
    var dun = new Date(Date.now() - 86400000).toISOString().slice(0, 10);

    var eylemler = (sahip ? '<button type="button" class="buton ikincil" id="genel-topla">' + b.ik('yenile', 16) + 'Topla</button>' : '') +
      '<button type="button" class="buton" id="genel-kredi">' + b.ik('jeton', 16) + 'Hızlı kredi</button>';

    var tarihMetni = new Date().toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric', weekday: 'long' });
    var rollupMetni = son
      ? 'son rollup ' + (son.generatedAt ? b.goreliZaman(son.generatedAt) : son.date) +
        (son.durationMs != null ? ' (' + b.sayi(Math.round(son.durationMs / 1000)) + ' sn)' : '')
      : 'henüz rollup yok';

    var bas = b.sayfaBaslik({ baslik: 'Bugün gökyüzünde neler oluyor',
      alt: tarihMetni + ' · ' + rollupMetni, eylemlerHtml: eylemler });

    if (!son) {
      icerik.innerHTML = bas + b.bosDurum(
        'Henüz adminStats dokümanı yok — gecelik toplama ya da "Topla" ile dolmaya başlar.',
        { ikon: 'panel', eylemHtml: sahip ? '<button type="button" class="buton" id="genel-topla-bos">' +
          b.ik('yenile', 16) + 'Şimdi topla</button>' : '' });
      var tb = icerik.querySelector('#genel-topla-bos');
      if (tb) tb.addEventListener('click', toplaAc);
      var tb2 = icerik.querySelector('#genel-topla');
      if (tb2) tb2.addEventListener('click', toplaAc);
      icerik.querySelector('#genel-kredi').addEventListener('click', function () { hizliKrediAc(); });
      return;
    }

    /* ---- Türetilmiş sayılar ---- */
    var onceki = gunler[gunler.length - 2] || null;
    var son30 = gunler.slice(-30), once30 = gunler.slice(-60, -30);
    var son14 = gunler.slice(-KIVILCIM_GUN);

    var dau = METRIKLER.dau.al(son);
    var dauOnceki = onceki ? METRIKLER.dau.al(onceki) : null;
    var dauOrt30 = ortalama(son30, METRIKLER.dau.al);

    var yeniBugun = sayiMi(canli.newUsersToday) ? canli.newUsersToday : null;
    var yeniKarsi = son.date === bugun ? (onceki ? METRIKLER.yeni.al(onceki) : null) : METRIKLER.yeni.al(son);

    var subs = son.subs || {};
    var aktifAbone = sayiMi(subs.active) ? subs.active : null;
    var haftaOnce = gunler[gunler.length - 8];
    var aboneFark = aktifAbone != null && haftaOnce && sayiMi((haftaOnce.subs || {}).active)
      ? aktifAbone - haftaOnce.subs.active : null;

    var denemeBas = toplam(son30, function (g) { return olaySayisi(g, 'TRIAL_STARTED'); });
    var denemeDon = toplam(son30, function (g) { return olaySayisi(g, 'TRIAL_CONVERTED'); });
    var donusum = denemeBas ? denemeDon / denemeBas * 100 : null;
    var denemeBasO = toplam(once30, function (g) { return olaySayisi(g, 'TRIAL_STARTED'); });
    var denemeDonO = toplam(once30, function (g) { return olaySayisi(g, 'TRIAL_CONVERTED'); });
    var donusumO = denemeBasO ? denemeDonO / denemeBasO * 100 : null;

    var maliyet30 = toplam(son30, aiMaliyet), maliyetO = toplam(once30, aiMaliyet);
    var brut30 = toplam(son30, uretimGelir), iade30 = toplam(son30, uretimIade);
    var maliyetPay = brut30 > 0 ? maliyet30 / brut30 * 100 : null;
    var telemetriYok = !son30.some(function (g) { return sayiMi((g.ai || {}).estCostToday); });

    // Bildirim sağlığı: dünün koşuları (yoksa en son koşu günü).
    var kosuGunleri = {};
    kosular.forEach(function (k) {
      if (!k || !k.date) return;
      var g = kosuGunleri[k.date] || (kosuGunleri[k.date] = { sent: 0, failed: 0, n: 0 });
      g.sent += Number(k.sent) || 0; g.failed += Number(k.failed) || 0; g.n++;
    });
    var kosuGun = kosuGunleri[dun] ? dun : Object.keys(kosuGunleri).sort().pop();
    var kosu = kosuGun ? kosuGunleri[kosuGun] : null;
    var saglik = kosu && (kosu.sent + kosu.failed) ? kosu.sent / (kosu.sent + kosu.failed) * 100 : null;
    function bildirimGonderim(g) {
      var n = g.notify || {};
      return Object.keys(n).reduce(function (t, tur) { return t + (Number(n[tur].sent) || 0); }, 0);
    }

    var bant = '';
    if (dikkat.length) {
      var ilk = dikkat[0];
      bant = b.bant('<b>' + b.e(ilk.etiket) + ': ' + b.e(b.sayi(ilk.sayi)) + '</b>' +
        (ilk.alt ? ' — ' + b.e(ilk.alt) : '') +
        (dikkat.length > 1 ? ' <span class="dipnot">(+' + (dikkat.length - 1) + ' madde daha)</span>' : ''),
        ilk.tur, { html: true,
          eylemHtml: '<a class="buton sade" href="' + b.e(ilk.href) + '">Git</a>' });
    }

    var kpiler = '<section class="izgara-kpi" aria-label="Bugünün sayıları">' +
      b.istatistikKarti({ ad: 'Günlük aktif', deger: b.sayi(dau),
        delta: dauOnceki != null && dauOnceki > 0 ? { fark: b.yuzde(Math.abs(yuzdeFark(dau, dauOnceki))),
          yon: dau > dauOnceki ? 'yukari' : (dau < dauOnceki ? 'asagi' : 'duz'), metin: 'önceki güne göre' } : null,
        alt: b.tarih(son.date), kivilcim: son14.map(METRIKLER.dau.al) }) +
      b.istatistikKarti({ ad: '30 gün ort. DAU', deger: b.sayi(Math.round(dauOrt30)),
        alt: 'en yüksek ' + b.sayi(Math.max.apply(null, son30.map(METRIKLER.dau.al).concat([0]))),
        kivilcim: son30.map(METRIKLER.dau.al) }) +
      b.istatistikKarti({ ad: 'Yeni kayıt', deger: yeniBugun != null ? b.sayi(yeniBugun) : '—',
        delta: yeniBugun != null && yeniKarsi != null ? { fark: yeniBugun - yeniKarsi, metin: 'önceki güne göre' } : null,
        alt: yeniBugun != null ? 'bugün · canlı sayım' : 'canlı sayım yapılamadı',
        kivilcim: son14.map(METRIKLER.yeni.al), renk: 'lilac' }) +
      b.istatistikKarti({ ad: 'Aktif abone', deger: aktifAbone != null ? b.sayi(aktifAbone) : '—', altin: true,
        delta: aboneFark != null ? { fark: aboneFark, metin: 'bu hafta' } : null,
        alt: 'MRR ' + b.para(subs.mrrUsd), kivilcim: son30.map(function (g) {
          return sayiMi((g.subs || {}).active) ? g.subs.active : 0; }), renk: 'gold' }) +
      b.istatistikKarti({ ad: 'Deneme → ödeme', deger: donusum != null ? b.yuzde(donusum) : '—',
        delta: donusum != null && donusumO != null ? { fark: b.yuzde(Math.abs(donusum - donusumO)),
          yon: donusum > donusumO ? 'yukari' : (donusum < donusumO ? 'asagi' : 'duz'), metin: 'önceki 30 güne göre' } : null,
        alt: b.sayi(denemeDon) + ' / ' + b.sayi(denemeBas) + ' · 30 gün' }) +
      b.istatistikKarti({ ad: 'AI maliyeti (30g)', deger: telemetriYok ? '—' : b.para(maliyet30),
        delta: !telemetriYok && maliyetO > 0 ? { fark: b.yuzde(Math.abs(yuzdeFark(maliyet30, maliyetO))),
          yon: maliyet30 > maliyetO ? 'yukari' : (maliyet30 < maliyetO ? 'asagi' : 'duz'), metin: 'önceki 30 gün' } : null,
        alt: telemetriYok ? 'telemetri kapalı' : (maliyetPay != null ? 'gelirin ' + b.yuzde(maliyetPay) + '\'i' : 'tahmini'),
        kivilcim: son14.map(aiMaliyet), renk: 'madder' }) +
      b.istatistikKarti({ ad: 'Bildirim sağlığı', deger: saglik != null ? b.yuzde(saglik) : '—',
        delta: kosu && kosu.failed ? { fark: b.sayi(kosu.failed) + ' başarısız', yon: 'asagi' } : null,
        alt: kosu ? b.sayi(kosu.sent) + ' gönderildi · ' + (kosuGun === dun ? 'dün' : b.tarih(kosuGun)) : 'koşu kaydı yok',
        kivilcim: son14.map(bildirimGonderim), renk: 'celadon' }) +
      '</section>';

    /* ---- Hero ---- */
    var metrikCipleri = Object.keys(METRIKLER).map(function (m) {
      return '<button type="button" class="adm-cip" data-metrik="' + m + '" aria-pressed="' +
        (m === 'dau' ? 'true' : 'false') + '">' + METRIK_ETIKET[m] + '</button>';
    }).join('');
    var aralikCipleri = ARALIKLAR.map(function (n) {
      return '<button type="button" class="adm-cip altin" data-aralik="' + n + '" aria-pressed="' +
        (n === 30 ? 'true' : 'false') + '">' + n + 'g</button>';
    }).join('');
    var hero = b.modul('Eğilim',
      '<div class="hero-deger"><span class="buyuk" id="hero-buyuk">—</span><span id="hero-delta"></span>' +
      '<span class="not" id="hero-not"></span></div>' +
      '<div class="grafik-kap"><canvas id="g-genel-hero" class="grafik grafik-hero" aria-label="Eğilim grafiği"></canvas></div>',
      '<span class="cip-grup" role="group" aria-label="Metrik" id="hero-metrik">' + metrikCipleri + '</span>' +
      '<span class="bosluk" aria-hidden="true"></span>' +
      '<span class="cip-grup" role="group" aria-label="Aralık" id="hero-aralik">' + aralikCipleri + '</span>',
      { alt: 'Günlük aktif kullanıcı, son 30 gün', kimlik: 'genel-hero' });

    var dikkatModul = b.modul('Dikkat', dikkatHtml(b, dikkat),
      dikkat.length ? b.rozet(String(dikkat.length), dikkat[0].tur === 'hata' ? 'hata' : 'uyari') : '',
      { alt: 'Bugün bakılması gerekenler' });
    var islemModul = b.modul('Son işlemler',
      izler.length ? '<div class="liste">' + izler.map(function (k) { return islemHtml(b, k); }).join('') + '</div>'
                   : b.bosDurum('Henüz denetim kaydı yok.', { ikon: 'denetim' }),
      '<a class="buton sade" href="#/sistem">Tümü</a>', { alt: 'Denetim izi · son 8' });

    /* ---- Sağ ray ---- */
    var magaza = brut30 * MAGAZA_PAYI;
    var marj = brut30 - magaza - (telemetriYok ? 0 : maliyet30) - iade30;
    var isletme = b.modul('İşletme durumu',
      '<div class="hero-deger"><span class="buyuk altin">' + b.e(b.para(marj)) + '</span>' +
      '<span class="not">tahmini katkı marjı</span></div>' +
      '<dl class="alan-liste">' +
      '<dt>Brüt gelir</dt><dd>' + b.e(b.para(brut30)) + '</dd>' +
      '<dt>Mağaza payı (~%' + Math.round(MAGAZA_PAYI * 100) + ')</dt><dd>−' + b.e(b.para(magaza)) + '</dd>' +
      '<dt>AI maliyeti</dt><dd>' + (telemetriYok ? '—' : '−' + b.e(b.para(maliyet30))) + '</dd>' +
      '<dt>İade</dt><dd>−' + b.e(b.para(iade30)) + '</dd>' +
      '</dl><p class="dipnot">Sabit giderler (Cloud Run + FCM, ~$30/ay) hariç; AI maliyeti ölçülen token × birim fiyat.</p>',
      '', { alt: '30 gün · üretim' });

    var byPlan = (son.users || {}).byPlan || {};
    var toplamKullanici = Number((son.users || {}).total) || 0;
    var planModul = b.modul('Plan dağılımı',
      '<div class="halka-kap"><div class="grafik-kap"><canvas id="g-genel-plan" class="grafik" ' +
      'aria-label="Plan dağılımı"></canvas></div></div>', '',
      { alt: b.sayi(toplamKullanici) + ' kullanıcı' });

    var byFeature = (son.ai || {}).byFeature || {};
    var ozellikler = Object.keys(byFeature).sort(function (x, y) {
      return (Number(byFeature[y]) || 0) - (Number(byFeature[x]) || 0);
    }).slice(0, 8);
    var aiModul = b.modul('Bugün AI', ozellikler.length
      ? '<dl class="alan-liste">' + ozellikler.map(function (k) {
          return '<dt>' + b.e(ozellikAdi(k)) + '</dt><dd>' + b.e(b.sayi(Number(byFeature[k]) || 0)) + '</dd>';
        }).join('') + '</dl>'
      : b.bosDurum('Rollup gününde AI çağrısı yok.', { ikon: 'ai' }),
      '', { alt: 'Özellik başına çağrı · ' + b.tarih(son.date) });

    icerik.innerHTML = bas + bant + kpiler +
      '<div class="izgara-ana">' +
      '<div class="pano-sol">' + hero + '<div class="izgara-2">' + dikkatModul + islemModul + '</div></div>' +
      '<div class="pano-ray">' + isletme + planModul + aiModul + '</div>' +
      '</div>' +
      '<p class="dipnot">Sayılar gecelik rollup\'tan (' + b.e(son.date) + '); "Yeni kayıt" canlı sayımdır. ' +
      'Gelir yalnız PRODUCTION; maliyetler tahmini. Günler UTC.</p>';

    /* ---- Hero durum makinesi (fetch'siz) ---- */
    var durum = { metrik: 'dau', aralik: 30 };
    var heroKap = icerik.querySelector('#genel-hero').closest('.modul');
    function heroCiz() {
      var m = METRIKLER[durum.metrik];
      var dilim = gunler.slice(-durum.aralik);
      var oncekiDilim = gunler.slice(-durum.aralik * 2, -durum.aralik);
      var degerler = dilim.map(m.al);
      var bicimle = m.bicim === 'para' ? b.para : b.sayi;
      var buyuk, fark, not;
      var enYuksek = degerler.reduce(function (en, v, i) { return v > en.v ? { v: v, i: i } : en; }, { v: -Infinity, i: -1 });
      if (m.birikimli) {
        var t = toplam(dilim, m.al), tO = toplam(oncekiDilim, m.al);
        buyuk = bicimle(t);
        fark = oncekiDilim.length === dilim.length ? yuzdeFark(t, tO) : null;
        not = durum.aralik + ' gün toplamı · günlük ort. ' + bicimle(m.bicim === 'para' ? t / (dilim.length || 1) : Math.round(t / (dilim.length || 1)));
      } else {
        var s = degerler[degerler.length - 1] || 0, o = degerler[degerler.length - 2];
        buyuk = bicimle(s);
        fark = o != null && o > 0 ? yuzdeFark(s, o) : null;
        not = durum.aralik + ' gün ort. ' + bicimle(Math.round(ortalama(dilim, m.al)));
      }
      if (enYuksek.i >= 0 && isFinite(enYuksek.v)) {
        not += ' · en yüksek ' + bicimle(enYuksek.v) + ' (' + b.tarih(dilim[enYuksek.i].date) + ')';
      }
      heroKap.querySelector('#hero-buyuk').textContent = buyuk;
      heroKap.querySelector('#hero-buyuk').classList.toggle('altin', durum.metrik === 'gelir');
      heroKap.querySelector('#hero-delta').innerHTML = fark == null ? '' :
        '<span class="delta ' + (fark > 0 ? 'yukari' : fark < 0 ? 'asagi' : 'duz') + '">' +
        (fark > 0 ? '▲' : fark < 0 ? '▼' : '◆') + ' ' + b.e(b.yuzde(Math.abs(fark))) + '</span>';
      heroKap.querySelector('#hero-not').textContent = not;
      heroKap.querySelector('.modul-bas p').textContent = m.ad + ', son ' + durum.aralik + ' gün' +
        (fark != null ? ' · önceki döneme göre' : '');
      RY.grafik.cizgi(heroKap.querySelector('#g-genel-hero'), {
        seriler: [{ ad: m.ad, renk: m.renk, veri: dilim.map(function (g) { return { x: g.date, y: m.al(g) }; }) }],
        alan: true, bicim: m.bicim, etiket: m.ad + ' eğilimi'
      });
    }
    function cipBagla(kimlik, attr, ayarla) {
      var grup = heroKap.querySelector('#' + kimlik);
      grup.addEventListener('click', function (ev) {
        var d = ev.target.closest('.adm-cip');
        if (!d) return;
        ayarla(d.getAttribute(attr));
        grup.querySelectorAll('.adm-cip').forEach(function (c) {
          c.setAttribute('aria-pressed', c === d ? 'true' : 'false');
        });
        heroCiz();
      });
    }
    cipBagla('hero-metrik', 'data-metrik', function (v) { if (METRIKLER[v]) durum.metrik = v; });
    cipBagla('hero-aralik', 'data-aralik', function (v) { durum.aralik = Number(v) || 30; });
    heroCiz();

    /* ---- Halka ---- */
    var PLAN_SIRA = [['free', 'Ücretsiz', 'parchment-dim'], ['trial', 'Deneme', 'lilac'], ['plus', 'Rytho+', 'gold']];
    var dilimler = PLAN_SIRA.map(function (p) { return { ad: p[1], deger: Number(byPlan[p[0]]) || 0, renk: p[2] }; });
    Object.keys(byPlan).forEach(function (k) {
      if (!PLAN_SIRA.some(function (p) { return p[0] === k; })) dilimler.push({ ad: k, deger: Number(byPlan[k]) || 0 });
    });
    RY.grafik.halka(icerik.querySelector('#g-genel-plan'), {
      dilimler: dilimler, bicim: 'sayi', merkezAlt: 'kullanıcı', etiket: 'Plan dağılımı',
      bosMetin: 'Plan kırılımı rollup\'ta yok — ilk toplamayla dolar'
    });

    /* ---- Eylemler ---- */
    icerik.querySelector('#genel-kredi').addEventListener('click', function () { hizliKrediAc(); });
    var topla = icerik.querySelector('#genel-topla');
    if (topla) topla.addEventListener('click', toplaAc);
  };

  RY.kirintiSaglayici.genel = function () {
    return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Genel Bakış' }];
  };
})();

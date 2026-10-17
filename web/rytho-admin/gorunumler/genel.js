/* Genel Bakış (AD19): işletme masasının ilk ekranı — bugünün sayıları,
   eğilim (fetch'siz metrik × dönem geçişi), dikkat listesi, son yönetici
   işlemleri, işletme durumu (dönem marjı, kaba tahmin), plan dağılımı,
   bugünkü AI kırılımı; hızlı kredi ve "Topla" (owner).

   Rota: #/genel?days=7|30|90&metrik=dau|yeni|gelir|maliyet (varsayılan
   30 / dau). Dönem ve metrik adrese SESSİZ yazılır; veri bir kez çekilir,
   seçim değişince yalnız veri bölgesi yeniden çizilir (istek yok).
   Uçlar (hepsi paralel; yalnız stats omurgadır, gerisi düşerse ilgili
   bölüm "—" gösterir):
   - GET /api/v1/admin/stats?days=181 → {days:[{date, generatedAt,
     durationMs, users:{dau, newToday, total, byPlan}, subs:{active,
     trialing, mrrUsd}, revenue:{grossToday, refundsToday, byEnv:{ENV:
     {gross, refunds, eventCounts}}}, ai:{callsToday, estCostToday,
     byFeature, costByFeature}, notify:{tür:{sent, failed}}}]} yeniden eskiye.
     181 = 90 günlük dönem + karşılaştırılacak önceki 90 gün + bugün.
   - GET /api/v1/admin/live → {today, newUsersToday (−1 = sayılamadı)}
   - GET /api/v1/admin/attention → [{tur, sayi, rota, seviye}]
   - GET /api/v1/admin/audit?limit=8 → {entries}
   - GET /api/v1/admin/notify-runs?days=2 → {runs:[{date, type, sent,
     failed}]}
   - POST /api/v1/admin/users/{uid}/credit {amount, reason}
   - POST /api/v1/admin/collect (owner)
   economics çağrısı YOK (AD19): işletme durumu stats günlerinden türetilir
   ve bu yüzden KABA TAHMİNDİR (ortak edinme maliyeti burada yok).

   BUGÜN AYRI: özet saatlik üretiliyor, yani bugünün dokümanı günün tamamı
   değil o ana kadarki kısmı. Eskiden "Günlük aktif" bugünün yarım gününü
   dünün tam günüyle kıyaslayıp her sabah sahte bir "düşüş" gösteriyordu.
   Artık dönem sayıları (ortalama, toplam, kıyas) TAMAMLANMIŞ günlerden;
   bugün kendi kartlarında "şu ana kadar" etiketiyle durur. Günler UTC. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  var MAGAZA_PAYI = 0.15;
  var ARALIKLAR = [7, 30, 90];
  var VARSAYILAN_ARALIK = 30;
  var KIVILCIM_GUN = 14;

  function S() { return RY.sozluk; }
  var SEVIYE_SIRA = { hata: 0, uyari: 1, bilgi: 2 };

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
  function yon(fark) { return fark > 0 ? 'yukari' : (fark < 0 ? 'asagi' : 'duz'); }

  var METRIKLER = {
    dau: { ad: 'Günlük aktif kullanıcı', bicim: 'sayi', renk: 'magenta', birikimli: false,
      al: function (g) { return Number((g.users || {}).dau) || 0; } },
    yeni: { ad: 'Yeni kayıt', bicim: 'sayi', renk: 'lilac', birikimli: true,
      al: function (g) { return Number((g.users || {}).newToday) || 0; } },
    gelir: { ad: 'Brüt gelir (gerçek alımlar)', bicim: 'para', renk: 'gold', birikimli: true, al: uretimGelir },
    maliyet: { ad: 'Tahmini AI maliyeti', bicim: 'para', renk: 'madder', birikimli: true, al: aiMaliyet }
  };
  var METRIK_ETIKET = { dau: 'Aktif kullanıcı', yeni: 'Yeni kayıt', gelir: 'Gelir', maliyet: 'AI maliyeti' };

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
      var sabl = S().dikkat(anahtar) || { etiket: anahtar || 'Madde', alt: '' };
      var sayi = Number(m.sayi != null ? m.sayi : m.count) || 0;
      var tur = m.seviye || m.level || 'bilgi';
      return { anahtar: anahtar, etiket: sabl.etiket || m.label, alt: sabl.alt || m.detail || '',
               sayi: sayi, href: m.rota || m.route || sabl.href || '#/genel',
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
    var e = S().eylem(a);
    var p = k.params && typeof k.params === 'object' ? k.params : {};
    var baslik = e[1];
    if (a === 'user.credit' && p.amount != null) baslik += ' · ' + b.sayi(Number(p.amount)) + ' kredi';
    if ((a === 'notify.dry_run' || a === 'notify.test_send') && p.type) baslik += ' · ' + S().bildirimAdi(p.type);
    if (a === 'stats.recompute' && p.from) baslik += ' · ' + b.tarih(p.from) + ' – ' + b.tarih(p.to);
    if (a === 'config.min_build' && p.min_build != null) baslik += ' · ' + b.sayi(Number(p.min_build));
    var hedef = k.targetUid ? ' → <b class="mono">' + b.e(String(k.targetUid).slice(0, 10)) + '…</b>' : '';
    var kim = k.adminEmail ? String(k.adminEmail).split('@')[0] : (k.adminUid || '?');
    var alt = kim + (p.reason ? ' · "' + String(p.reason).slice(0, 60) + '"' : '') +
      (k.phase === 'failed' ? ' · başarısız oldu' : '');
    var govde = '<span class="satir-ikon' + (e[3] ? ' ' + e[3] : '') + '">' + b.ik(e[2], 18) + '</span>' +
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
          yardim: 'Cüzdan defterine ve denetim izine yazılır (en az 3 karakter).',
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
          var hedefUid = secili.uid;
          b.toast(b.sayi(tutar) + ' kredi verildi → ' + (secili.displayName || secili.email || secili.uid) +
            (c ? ' · bakiye ' + b.sayi((Number(c.allowance) || 0) + (Number(c.purchased) || 0)) : ''),
            'basari', { eylem: { metin: 'Ayrıntı', onTikla: function () { RY.rotaYaz('kullanicilar', [hedefUid]); } } });
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
        b.e(u.displayName || u.email || u.uid) + '<span>' + b.e([u.email, u.username ? '@' + u.username : null]
          .filter(Boolean).join(' · ') || u.uid) + '</span></span>' +
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
        RY.rotaYenile();
      }).catch(function (h) { t.kapat(); throw h; });
    }).catch(hataToast);
  }
  // Palet kaydı sistem.js'te ('sistem-topla'); burada yalnız başlık düğmesi.

  /* ---------------- Rota parametreleri ---------------- */

  function paramOku(params) {
    params = params || {};
    var gun = Number(params.days);
    return {
      aralik: ARALIKLAR.indexOf(gun) >= 0 ? gun : VARSAYILAN_ARALIK,
      metrik: METRIKLER[params.metrik] ? params.metrik : 'dau'
    };
  }
  function rotaParam(d) {
    var p = {};
    if (d.aralik !== VARSAYILAN_ARALIK) p.days = d.aralik;
    if (d.metrik !== 'dau') p.metrik = d.metrik;
    return p;
  }

  /* ---------------- Görünüm ---------------- */

  RY.gorunumler.genel = async function (icerik, args, params, baglam) {
    var b = RY.b;
    var hepsi = await Promise.all([
      RY.sorgu('/api/v1/admin/stats', { days: 181 }, { sinyal: baglam && baglam.sinyal }),
      RY.get('/api/v1/admin/live').catch(function () { return {}; }),
      RY.get('/api/v1/admin/attention').catch(function () { return null; }),
      RY.sorgu('/api/v1/admin/audit', { limit: 8 }).catch(function () { return { entries: [] }; }),
      RY.sorgu('/api/v1/admin/notify-runs', { days: 2 }).catch(function () { return { runs: [] }; })
    ]);
    if (baglam && !baglam.aktif()) return;
    var stats = hepsi[0] || {}, canli = hepsi[1] || {};
    var veri = {
      gunler: (stats.days || []).slice().reverse(),  // eskiden yeniye
      canli: canli,
      dikkat: dikkatListesi(hepsi[2]),
      izler: Array.isArray((hepsi[3] || {}).entries) ? hepsi[3].entries : [],
      kosular: Array.isArray((hepsi[4] || {}).runs) ? hepsi[4].runs : []
    };
    var son = veri.gunler[veri.gunler.length - 1] || null;
    var durum = paramOku(params);
    var sahip = RY.sahipMi();

    var eylemler = (sahip ? '<button type="button" class="buton ikincil" id="genel-topla">' + b.ik('yenile', 16) + 'Topla</button>' : '') +
      '<button type="button" class="buton" id="genel-kredi">' + b.ik('jeton', 16) + 'Hızlı kredi</button>';

    // Tarih başlığı Türkiye saatiyle: sahip "bugün" derken İstanbul'daki
    // günü kastediyor. Kova günleri (UTC) bundan ayrı ve şeritte yazılı.
    var tarihMetni = new Date().toLocaleDateString('tr-TR',
      { day: 'numeric', month: 'long', year: 'numeric', weekday: 'long', timeZone: 'Europe/Istanbul' });
    var bas = b.sayfaBaslik({ baslik: 'Genel Bakış',
      alt: tarihMetni + ' · ' + b.guncellemeMetni(son && son.generatedAt), eylemlerHtml: eylemler });

    if (!son) {
      icerik.innerHTML = bas + b.bosDurum(
        'Henüz istatistik özeti yok — saatlik toplama ya da "Topla" ile dolmaya başlar.',
        { ikon: 'panel', eylemHtml: sahip ? '<button type="button" class="buton" id="genel-topla-bos">' +
          b.ik('yenile', 16) + 'Şimdi topla</button>' : '' });
      eylemBagla(icerik);
      var tb = icerik.querySelector('#genel-topla-bos');
      if (tb) tb.addEventListener('click', toplaAc);
      return;
    }

    icerik.innerHTML = bas +
      '<div class="suzgec-seridi" id="genel-suzgec"><span class="dipnot suzgec-not">Günler UTC\'ye göre (Türkiye saatinden 3 saat geride)</span></div>' +
      '<div class="veri-alani" id="genel-veri"></div>';
    eylemBagla(icerik);

    var alan = icerik.querySelector('#genel-veri');
    var serit = icerik.querySelector('#genel-suzgec');
    serit.insertBefore(b.donemSecici({
      secenekler: ARALIKLAR, deger: durum.aralik,
      onDegis: function (yeni) {
        durum.aralik = yeni;
        RY.rotaYaz('genel', [], rotaParam(durum), { sessiz: true });
        veriCiz(alan, veri, durum);
      }
    }), serit.firstChild);

    veriCiz(alan, veri, durum);
  };

  function eylemBagla(icerik) {
    icerik.querySelector('#genel-kredi').addEventListener('click', function () { hizliKrediAc(); });
    var topla = icerik.querySelector('#genel-topla');
    if (topla) topla.addEventListener('click', toplaAc);
  }

  /* Veri bölgesi: tek veri setinden, seçili dönemle. İstek yok — dönem
     değişince yalnız bu fonksiyon yeniden koşar. */
  function veriCiz(alan, veri, durum) {
    var b = RY.b;
    var N = durum.aralik;
    var gunler = veri.gunler, canli = veri.canli, dikkat = veri.dikkat;
    var son = gunler[gunler.length - 1];
    var bugun = b.utcGun(0), dun = b.utcGun(1);

    // Bugünün dokümanı yarım gündür; dönem hesapları tam günlerden.
    var bugunDok = son.date === bugun ? son : null;
    var tamGunler = bugunDok ? gunler.slice(0, -1) : gunler;
    var oncekiTam = tamGunler[tamGunler.length - 2] || null;
    var donem = tamGunler.slice(-N), onceDonem = tamGunler.slice(-2 * N, -N);
    var kivilcimDilim = tamGunler.slice(-KIVILCIM_GUN);
    var oncedenVar = onceDonem.length === donem.length && donem.length > 0;

    /* ---- Türetilmiş sayılar ---- */
    var dauAl = METRIKLER.dau.al;
    var dauOrt = ortalama(donem, dauAl);

    var yeniBugun = sayiMi(canli.newUsersToday) ? canli.newUsersToday : null;
    var dunDok = gunler.filter(function (g) { return g.date === dun; })[0] || null;

    var subs = son.subs || {};
    var aktifAbone = sayiMi(subs.active) ? subs.active : null;
    var haftaOnce = gunler[gunler.length - 8];
    var aboneFark = aktifAbone != null && haftaOnce && sayiMi((haftaOnce.subs || {}).active)
      ? aktifAbone - haftaOnce.subs.active : null;

    var denemeBas = toplam(donem, function (g) { return olaySayisi(g, 'TRIAL_STARTED'); });
    var denemeDon = toplam(donem, function (g) { return olaySayisi(g, 'TRIAL_CONVERTED'); });
    var donusum = denemeBas ? denemeDon / denemeBas * 100 : null;
    var denemeBasO = toplam(onceDonem, function (g) { return olaySayisi(g, 'TRIAL_STARTED'); });
    var denemeDonO = toplam(onceDonem, function (g) { return olaySayisi(g, 'TRIAL_CONVERTED'); });
    var donusumO = oncedenVar && denemeBasO ? denemeDonO / denemeBasO * 100 : null;

    var maliyetD = toplam(donem, aiMaliyet), maliyetO = toplam(onceDonem, aiMaliyet);
    var brutD = toplam(donem, uretimGelir), iadeD = toplam(donem, uretimIade);
    var maliyetPay = brutD > 0 ? maliyetD / brutD * 100 : null;
    var telemetriYok = !donem.some(function (g) { return sayiMi((g.ai || {}).estCostToday); });

    // Bildirim sağlığı: dünün koşuları (yoksa en son koşu günü).
    var kosuGunleri = {};
    veri.kosular.forEach(function (k) {
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

    /* "Günlük aktif": bugün yarımsa kıyas YOK, dünün tam sayısı yanında
       düz metin olarak durur — iki farklı uzunluktaki günü ok işaretiyle
       kıyaslamak uydurma bir eğilim olurdu. */
    var dauKarti = bugunDok
      ? b.istatistikKarti({ ad: 'Günlük aktif', deger: b.sayi(dauAl(bugunDok)),
          alt: 'bugün, şu ana kadar' + (dunDok ? ' · dün ' + b.sayi(dauAl(dunDok)) : ''),
          kivilcim: kivilcimDilim.map(dauAl) })
      : b.istatistikKarti({ ad: 'Günlük aktif', deger: b.sayi(dauAl(son)),
          delta: oncekiTam && dauAl(oncekiTam) > 0 ? { fark: b.yuzde(Math.abs(yuzdeFark(dauAl(son), dauAl(oncekiTam)))),
            yon: yon(dauAl(son) - dauAl(oncekiTam)), metin: 'önceki güne göre' } : null,
          alt: b.tarih(son.date), kivilcim: kivilcimDilim.map(dauAl) });

    var kpiler = '<section class="izgara-kpi" aria-label="Bugünün ve dönemin sayıları">' +
      dauKarti +
      b.istatistikKarti({ ad: 'Ortalama günlük aktif', deger: donem.length ? b.sayi(Math.round(dauOrt)) : '—',
        alt: 'son ' + N + ' tam gün · en yüksek ' + b.sayi(Math.max.apply(null, donem.map(dauAl).concat([0]))),
        kivilcim: donem.map(dauAl) }) +
      b.istatistikKarti({ ad: 'Yeni kayıt', deger: yeniBugun != null ? b.sayi(yeniBugun) : '—',
        alt: yeniBugun != null
          ? 'bugün, şu ana kadar' + (dunDok ? ' · dün ' + b.sayi(METRIKLER.yeni.al(dunDok)) : '')
          : 'canlı sayım yapılamadı',
        kivilcim: kivilcimDilim.map(METRIKLER.yeni.al), renk: 'lilac' }) +
      b.istatistikKarti({ ad: 'Aktif abone', deger: aktifAbone != null ? b.sayi(aktifAbone) : '—', altin: true,
        delta: aboneFark != null ? { fark: aboneFark, metin: 'son 7 günde' } : null,
        alt: 'aylık düzenli gelir ' + b.para(subs.mrrUsd), kivilcim: tamGunler.slice(-30).map(function (g) {
          return sayiMi((g.subs || {}).active) ? g.subs.active : 0; }), renk: 'gold' }) +
      b.istatistikKarti({ ad: 'Denemeden aboneliğe', deger: donusum != null ? b.yuzde(donusum) : '—',
        delta: donusum != null && donusumO != null ? { fark: b.yuzde(Math.abs(donusum - donusumO)),
          yon: yon(donusum - donusumO), metin: 'önceki ' + N + ' güne göre' } : null,
        alt: b.sayi(denemeDon) + ' / ' + b.sayi(denemeBas) + ' · son ' + N + ' tam gün' }) +
      b.istatistikKarti({ ad: 'AI maliyeti (' + N + ' gün)', deger: telemetriYok ? '—' : b.para(maliyetD),
        delta: !telemetriYok && oncedenVar && maliyetO > 0 ? { fark: b.yuzde(Math.abs(yuzdeFark(maliyetD, maliyetO))),
          yon: yon(maliyetD - maliyetO), metin: 'önceki ' + N + ' gün' } : null,
        alt: telemetriYok ? 'ölçüm kapalı' : (maliyetPay != null ? 'gelirin ' + b.yuzde(maliyetPay) + '\'i' : 'tahmini'),
        kivilcim: kivilcimDilim.map(aiMaliyet), renk: 'madder' }) +
      b.istatistikKarti({ ad: 'Bildirim sağlığı', deger: saglik != null ? b.yuzde(saglik) : '—',
        delta: kosu && kosu.failed ? { fark: b.sayi(kosu.failed) + ' başarısız', yon: 'asagi' } : null,
        alt: kosu ? b.sayi(kosu.sent) + ' gönderildi · ' + (kosuGun === dun ? 'dün' : b.tarih(kosuGun)) : 'koşu kaydı yok',
        kivilcim: kivilcimDilim.map(bildirimGonderim), renk: 'celadon' }) +
      '</section>';

    /* ---- Hero ---- */
    var hero = b.modul('Eğilim',
      '<div class="hero-deger"><span class="buyuk" id="hero-buyuk">—</span><span id="hero-delta"></span>' +
      '<span class="not" id="hero-not"></span></div>' +
      '<div class="grafik-kap"><canvas id="g-genel-hero" class="grafik grafik-hero" aria-label="Eğilim grafiği"></canvas></div>',
      '<span id="hero-metrik"></span>',
      { alt: METRIKLER[durum.metrik].ad + ', son ' + N + ' tam gün', kimlik: 'genel-hero' });

    var dikkatModul = b.modul('Dikkat', dikkatHtml(b, dikkat),
      dikkat.length ? b.rozet(String(dikkat.length), dikkat[0].tur === 'hata' ? 'hata' : 'uyari') : '',
      { alt: 'Bugün bakılması gerekenler' });
    var islemModul = b.modul('Son işlemler',
      veri.izler.length ? '<div class="liste">' + veri.izler.map(function (k) { return islemHtml(b, k); }).join('') + '</div>'
                        : b.bosDurum('Henüz denetim kaydı yok.', { ikon: 'denetim' }),
      '<a class="buton sade" href="#/sistem">Tümü</a>', { alt: 'Denetim izi · son 8' });

    /* ---- Sağ ray ---- */
    /* Marj TANIMI Gelir sayfasındaki ekonomi tablosuyla AYNI: brüt × (1 −
       mağaza payı) − AI maliyeti. Eskiden burada iadeler de düşülüyordu ve
       iki ekran aynı dönem için iki farklı marj gösteriyordu. Fark kalan
       tek terim ortak edinme maliyeti (bu uç onu taşımıyor) — bu yüzden
       sayı "kaba tahmin" adıyla ve kesin sayının yeri söylenerek durur. */
    var magaza = brutD * MAGAZA_PAYI;
    var marj = brutD - magaza - (telemetriYok ? 0 : maliyetD);
    var isletme = b.modul('İşletme durumu',
      '<div class="hero-deger"><span class="buyuk altin">' + b.e(b.para(marj)) + '</span>' +
      '<span class="not">kaba katkı marjı tahmini</span></div>' +
      '<dl class="alan-liste">' +
      '<dt>Brüt gelir</dt><dd>' + b.e(b.para(brutD)) + '</dd>' +
      '<dt>Mağaza payı (~%' + Math.round(MAGAZA_PAYI * 100) + ')</dt><dd>−' + b.e(b.para(magaza)) + '</dd>' +
      '<dt>AI maliyeti</dt><dd>' + (telemetriYok ? '—' : '−' + b.e(b.para(maliyetD))) + '</dd>' +
      '</dl><p class="dipnot">Kaba tahmin: Gelir sayfasındaki tanımla aynı, yalnız ortak edinme maliyeti ' +
      'düşülmedi — kesin sayı Gelir &amp; Abonelik sayfasında. Bu dönemdeki iadeler ' + b.e(b.para(iadeD)) +
      '. Sabit giderler (sunucu ve bildirim altyapısı, tahminen ~$30/ay) hariç; AI maliyeti ölçülen ' +
      'model birimi × birim fiyattır.</p>',
      '', { alt: 'son ' + N + ' tam gün · gerçek alımlar' });

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
          return '<dt>' + b.e(S().ozellikAdi(k)) + '</dt><dd>' + b.e(b.sayi(Number(byFeature[k]) || 0)) + '</dd>';
        }).join('') + '</dl>'
      : b.bosDurum('Bu günde AI çağrısı yok.', { ikon: 'ai' }),
      '', { alt: 'Özellik başına çağrı · ' + (bugunDok ? 'bugün, şu ana kadar' : b.tarih(son.date)) });

    alan.innerHTML = bant + kpiler +
      '<div class="izgara-ana">' +
      '<div class="pano-sol">' + hero + '<div class="izgara-2">' + dikkatModul + islemModul + '</div></div>' +
      '<div class="pano-ray">' + isletme + planModul + aiModul + '</div>' +
      '</div>' +
      '<p class="dipnot">Sayılar saatlik istatistik özetinden (son gün ' + b.e(b.tarih(son.date)) + '); ' +
      '"Yeni kayıt" canlı sayımdır. Dönem sayıları tamamlanmış günlerden, bugün ayrı gösterilir. ' +
      'Gelir yalnız gerçek alımlar; maliyetler tahmini.</p>';

    /* ---- Hero (fetch'siz) ---- */
    var heroKap = alan.querySelector('#genel-hero').closest('.modul');
    function heroCiz() {
      var m = METRIKLER[durum.metrik];
      var dilim = donem;
      var degerler = dilim.map(m.al);
      var bicimle = m.bicim === 'para' ? b.para : b.sayi;
      var buyuk, fark, not;
      var enYuksek = degerler.reduce(function (en, v, i) { return v > en.v ? { v: v, i: i } : en; }, { v: -Infinity, i: -1 });
      if (m.birikimli) {
        var t = toplam(dilim, m.al), tO = toplam(onceDonem, m.al);
        buyuk = bicimle(t);
        fark = oncedenVar ? yuzdeFark(t, tO) : null;
        not = N + ' tam gün toplamı · günlük ort. ' + bicimle(m.bicim === 'para' ? t / (dilim.length || 1) : Math.round(t / (dilim.length || 1)));
      } else {
        var s = degerler[degerler.length - 1] || 0, o = degerler[degerler.length - 2];
        buyuk = bicimle(s);
        fark = o != null && o > 0 ? yuzdeFark(s, o) : null;
        not = 'son tam gün · ' + N + ' gün ort. ' + bicimle(Math.round(ortalama(dilim, m.al)));
      }
      if (enYuksek.i >= 0 && isFinite(enYuksek.v)) {
        not += ' · en yüksek ' + bicimle(enYuksek.v) + ' (' + b.tarih(dilim[enYuksek.i].date) + ')';
      }
      heroKap.querySelector('#hero-buyuk').textContent = buyuk;
      heroKap.querySelector('#hero-buyuk').classList.toggle('altin', durum.metrik === 'gelir');
      heroKap.querySelector('#hero-delta').innerHTML = fark == null ? '' :
        '<span class="delta ' + yon(fark) + '">' +
        (fark > 0 ? '▲' : fark < 0 ? '▼' : '◆') + ' ' + b.e(b.yuzde(Math.abs(fark))) + '</span>';
      heroKap.querySelector('#hero-not').textContent = not;
      heroKap.querySelector('.modul-bas p').textContent = m.ad + ', son ' + N + ' tam gün' +
        (fark != null ? (m.birikimli ? ' · önceki ' + N + ' güne göre' : ' · önceki güne göre') : '');
      RY.grafik.cizgi(heroKap.querySelector('#g-genel-hero'), {
        seriler: [{ ad: m.ad, renk: m.renk, veri: dilim.map(function (g) { return { x: g.date, y: m.al(g) }; }) }],
        alan: true, bicim: m.bicim, etiket: m.ad + ' eğilimi'
      });
    }
    heroKap.querySelector('#hero-metrik').replaceWith(b.secimCipleri({
      etiket: 'Metrik', secenekler: Object.keys(METRIKLER).map(function (k) {
        return { deger: k, etiket: METRIK_ETIKET[k] };
      }),
      deger: durum.metrik,
      onDegis: function (v) {
        if (!METRIKLER[v]) return;
        durum.metrik = v;
        RY.rotaYaz('genel', [], rotaParam(durum), { sessiz: true });
        heroCiz();
      }
    }));
    heroCiz();

    /* ---- Halka ---- */
    var PLAN_RENK = { free: 'parchment-dim', trial: 'lilac', plus: 'gold' };
    var dilimler = ['free', 'trial', 'plus'].map(function (p) {
      return { ad: S().planAdi(p), deger: Number(byPlan[p]) || 0, renk: PLAN_RENK[p] };
    });
    Object.keys(byPlan).forEach(function (k) {
      if (!PLAN_RENK[k]) dilimler.push({ ad: S().planAdi(k), deger: Number(byPlan[k]) || 0 });
    });
    RY.grafik.halka(alan.querySelector('#g-genel-plan'), {
      dilimler: dilimler, bicim: 'sayi', merkezAlt: 'kullanıcı', etiket: 'Plan dağılımı',
      bosMetin: 'Plan kırılımı özette yok — ilk toplamayla dolar'
    });
  }

  RY.kirintiSaglayici.genel = function () {
    return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Genel Bakış' }];
  };
})();

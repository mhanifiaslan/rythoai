/* El yazması canvas grafikleri v3 (AD16). Dış kütüphane yok.

   cizgi, cubuk, yigin, halka, kivilcim → her biri {ciz, yokEt}.
   Erişilebilirlik: canvas tabindex=0 role=img aria-describedby → kardeş
   sr-only <table class="grafik-tablo"> (tüm veri); ←/→ imleci gezdirir,
   ipucu görünür ve aria-live ile okunur; pointer + dokunma ipucu; boş
   veri "Veri yok" görünür metin (yalnız tuvale boyanmaz).
   Renkler CSS token'larından (getComputedStyle); reduced-motion'da çizim
   animasyonu yok; ResizeObserver yeniden çizer.

   v2 uyumluluğu: cizgi(canvas, {degerler, etiketler, birim}) ve
   cubuk(canvas, {etiket: sayı}, sec) çağrıları yeni biçime çevrilir. */
(function () {
  'use strict';

  var RY = window.RY = window.RY || {};
  var b = function () { return RY.b || {}; };

  /* ---------------- Renk ---------------- */

  var _renkler = {};
  function renk(ad) {
    if (!_renkler[ad]) {
      var v = getComputedStyle(document.documentElement)
        .getPropertyValue('--' + ad).trim();
      _renkler[ad] = v || '';
    }
    return _renkler[ad] || renk('parchment-dim') || '#888';
  }

  function hexRgb(hex) {
    var m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(hex).trim());
    if (!m) return null;
    var h = m[1];
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    var n = parseInt(h, 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }

  /* Token + alfa → rgba dizesi (canvas color-mix anlamaz). */
  function seffaf(ad, a) {
    var rgb = hexRgb(renk(ad));
    if (!rgb) return renk(ad);
    return 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',' + a + ')';
  }

  /* --parchment-mid'in canvas karşılığı: parchment 70% + dim 30%. */
  function parchmentMid() {
    var p = hexRgb(renk('parchment')), d = hexRgb(renk('parchment-dim'));
    if (!p || !d) return renk('parchment-dim');
    var k = [0, 1, 2].map(function (i) { return Math.round(p[i] * 0.7 + d[i] * 0.3); });
    return 'rgb(' + k.join(',') + ')';
  }

  var PALET = ['magenta', 'gold', 'lilac', 'celadon', 'violet', 'madder', 'purple'];
  function seriRengi(s, i) {
    return (s && s.renk) || PALET[i % PALET.length];
  }

  /* ---------------- Biçim ---------------- */

  function bicimle(v, bicim) {
    if (v == null || !isFinite(v)) return '—';
    if (bicim === 'para') return b().para ? b().para(v) : '$' + v;
    if (bicim === 'yuzde') return b().yuzde ? b().yuzde(v) : '%' + v;
    return Number(v).toLocaleString('tr-TR', { maximumFractionDigits: 2 });
  }
  /* Pay metni Türkçe yazımla, işaret önde: "%12,5". Halka grafiği dört
     yerde "12,5%" basıyordu; panelin geri kalanı (b.yuzde) ile ayrışmıştı. */
  function payMetni(deger, toplam, basamak) {
    if (!toplam) return '—';
    var p = deger / toplam * 100;
    return b().yuzde ? b().yuzde(p, basamak == null ? 1 : basamak)
      : '%' + p.toFixed(basamak == null ? 1 : basamak).replace('.', ',');
  }
  /* Eksen kısaltması Türkçe: bin → "B", milyon → "Mn" ("k"/"M" İngilizce). */
  function eksenKisa(v, bicim) {
    var on = bicim === 'para' ? '$' : (bicim === 'yuzde' ? '%' : '');
    var m = Math.abs(v);
    var s;
    if (m >= 1e6) s = (v / 1e6).toFixed(1).replace(/\.0$/, '') + ' Mn';
    else if (m >= 1000) s = (v / 1000).toFixed(1).replace(/\.0$/, '') + ' B';
    else if (m === 0) s = '0';
    else if (m < 1) s = v.toFixed(2);
    else if (m < 10) s = v.toFixed(1).replace(/\.0$/, '');
    else s = String(Math.round(v));
    return on + s.replace('.', ',');
  }
  function eksenEtiket(x) {
    // ISO tarih gelirse gün.ay; aksi halde olduğu gibi.
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(x == null ? '' : x));
    if (m) return Number(m[3]) + '.' + Number(m[2]);
    return String(x == null ? '' : x);
  }
  function e(s) { return b().e ? b().e(s) : String(s); }

  /* ---------------- Altyapı ---------------- */

  var azaltilmis = function () {
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  };

  function hazirla(canvas) {
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var g = canvas.clientWidth, y = canvas.clientHeight;
    canvas.width = Math.max(1, Math.round(g * dpr));
    canvas.height = Math.max(1, Math.round(y * dpr));
    var ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, g, y);
    return { ctx: ctx, g: g, y: y };
  }

  /* Tek gözlemci: canvas.__ryCiz kapanışını saklar, boyut değişince çağırır. */
  var gozlemci = null;
  function izle(canvas, ciz) {
    canvas.__ryCiz = ciz;
    if (!('ResizeObserver' in window)) return;
    if (!gozlemci) {
      gozlemci = new ResizeObserver(function (girisler) {
        girisler.forEach(function (gi) {
          if (gi.target.__ryCiz && gi.target.clientWidth) gi.target.__ryCiz();
        });
      });
    }
    gozlemci.observe(canvas);
  }
  function birak(canvas) {
    canvas.__ryCiz = null;
    if (gozlemci) gozlemci.unobserve(canvas);
  }

  var sayac = 0;

  /* Kap + kardeşler: ipucu, sr-only tablo, duyuru, boş metin. */
  function kur(canvas, sec) {
    var kap = canvas.parentElement;
    if (!kap) return null;
    if (!kap.classList.contains('grafik-kap')) kap.classList.add('grafik-kap');
    yokEtKardesler(canvas);
    var id = canvas.id || ('grafik-' + (++sayac));
    if (!canvas.id) canvas.id = id;
    var ip = document.createElement('div');
    ip.className = 'grafik-ipucu';
    ip.setAttribute('aria-hidden', 'true');
    var duyuru = document.createElement('div');
    duyuru.className = 'grafik-duyuru';
    duyuru.setAttribute('aria-live', 'polite');
    var tablo = document.createElement('table');
    tablo.className = 'grafik-tablo';
    tablo.id = id + '-tablo';
    kap.appendChild(ip);
    kap.appendChild(duyuru);
    kap.appendChild(tablo);
    canvas.setAttribute('role', 'img');
    canvas.setAttribute('tabindex', '0');
    canvas.setAttribute('aria-describedby', tablo.id);
    if (!canvas.getAttribute('aria-label') && sec && sec.etiket) {
      canvas.setAttribute('aria-label', sec.etiket);
    }
    return { kap: kap, ip: ip, duyuru: duyuru, tablo: tablo };
  }

  function yokEtKardesler(canvas) {
    var kap = canvas.parentElement;
    if (!kap) return;
    Array.prototype.slice.call(kap.children).forEach(function (c) {
      if (c === canvas) return;
      if (/\bgrafik-(ipucu|duyuru|tablo|bos)\b/.test(c.className)) c.remove();
    });
  }

  function bos(canvas, sec) {
    var kap = canvas.parentElement;
    yokEtKardesler(canvas);
    birak(canvas);
    canvas.hidden = true;
    canvas.removeAttribute('tabindex');
    var d = document.createElement('div');
    d.className = 'grafik-bos';
    d.textContent = (sec && sec.bosMetin) || 'Veri yok';
    if (kap) kap.appendChild(d);
    return { ciz: function () {}, yokEt: function () { d.remove(); canvas.hidden = false; } };
  }

  /* İpucu konumu: kap koordinatında; kenara yakınsa hizalama sınıfı. */
  function ipucuGoster(k, x, y, html) {
    k.ip.innerHTML = html;
    k.ip.classList.add('gorunur');
    var gen = k.kap.clientWidth;
    k.ip.classList.toggle('sol', x < 90);
    k.ip.classList.toggle('sag', x > gen - 90);
    k.ip.style.setProperty('--ip-x', Math.round(x) + 'px');
    k.ip.style.setProperty('--ip-y', Math.round(y) + 'px');
  }
  function ipucuGizle(k) { k.ip.classList.remove('gorunur'); }

  /* Ortak etkileşim: imleç indeksi (klavye/pointer/dokunma). */
  function etkilesim(canvas, k, sec) {
    var imlec = -1;
    var kilit = false; // klavye ile açıldıysa fare ayrılınca kapanmasın
    function goster(i, klavye) {
      if (i < 0 || i >= sec.adet()) { gizle(); return; }
      imlec = i;
      var p = sec.konum(i);
      ipucuGoster(k, p.x, p.y, sec.html(i));
      if (klavye) {
        kilit = true;
        k.duyuru.textContent = sec.metin(i);
      }
      if (sec.vurgula) sec.vurgula(i);
    }
    function gizle() {
      imlec = -1;
      kilit = false;
      ipucuGizle(k);
      if (sec.vurgula) sec.vurgula(-1);
    }
    function pointer(ev) {
      var kutu = canvas.getBoundingClientRect();
      var nokta = ev.touches ? ev.touches[0] : ev;
      var i = sec.enYakin(nokta.clientX - kutu.left, nokta.clientY - kutu.top);
      if (i < 0) { if (!kilit) gizle(); return; }
      kilit = false;
      goster(i, false);
    }
    canvas.addEventListener('pointermove', pointer);
    canvas.addEventListener('pointerdown', pointer);
    canvas.addEventListener('pointerleave', function () { if (!kilit) gizle(); });
    canvas.addEventListener('touchstart', function (ev) { pointer(ev); }, { passive: true });
    canvas.addEventListener('keydown', function (ev) {
      var n = sec.adet();
      if (!n) return;
      var i = imlec;
      if (ev.key === 'ArrowRight' || ev.key === 'ArrowDown') i = imlec < 0 ? 0 : Math.min(n - 1, imlec + 1);
      else if (ev.key === 'ArrowLeft' || ev.key === 'ArrowUp') i = imlec < 0 ? n - 1 : Math.max(0, imlec - 1);
      else if (ev.key === 'Home') i = 0;
      else if (ev.key === 'End') i = n - 1;
      else if (ev.key === 'Escape') { gizle(); return; }
      else return;
      ev.preventDefault();
      goster(i, true);
    });
    canvas.addEventListener('blur', gizle);
    return { goster: goster, gizle: gizle, imlec: function () { return imlec; } };
  }

  /* Giriş animasyonu: 450ms süpürme; reduced-motion'da tek kare. */
  function canlandir(ciz) {
    if (azaltilmis()) { ciz(1); return; }
    var basla = null;
    (function adim(t) {
      if (basla === null) basla = t;
      var f = Math.min((t - basla) / 450, 1);
      ciz(1 - Math.pow(1 - f, 3));
      if (f < 1) requestAnimationFrame(adim);
    })(performance.now());
  }

  function srTablo(tablo, basliklar, satirlar, ozet) {
    tablo.innerHTML = '<caption>' + e(ozet || 'Grafik verisi') + '</caption>' +
      '<thead><tr>' + basliklar.map(function (h) {
        return '<th scope="col">' + e(h) + '</th>';
      }).join('') + '</tr></thead><tbody>' + satirlar.map(function (r) {
        return '<tr>' + r.map(function (c, i) {
          return (i ? '<td>' : '<th scope="row">') + e(c) + (i ? '</td>' : '</th>');
        }).join('') + '</tr>';
      }).join('') + '</tbody>';
  }

  function yokEtOlustur(canvas, k) {
    return function () {
      birak(canvas);
      yokEtKardesler(canvas);
      var yeni = canvas.cloneNode(false); // dinleyiciler düşer
      yeni.removeAttribute('tabindex');
      yeni.removeAttribute('aria-describedby');
      if (canvas.parentElement) canvas.parentElement.replaceChild(yeni, canvas);
      void k;
    };
  }

  /* ---------------- Çizgi / alan ---------------- */

  /* cizgi(canvas, {seriler:[{ad, veri:[{x,y}], renk}], alan, bicim, etiket}) */
  function cizgi(canvas, sec) {
    if (!canvas) return null;
    sec = sec || {};
    // v2 uyumu
    if (!sec.seriler && sec.degerler) {
      var et = sec.etiketler || [];
      sec = Object.assign({}, sec, {
        seriler: [{ ad: sec.ad || '', veri: sec.degerler.map(function (y, i) {
          return { x: et[i] != null ? et[i] : i + 1, y: Number(y) || 0 };
        }) }],
        alan: true,
        bicim: sec.birim === '$' ? 'para' : (sec.bicim || 'sayi')
      });
    }
    var seriler = (sec.seriler || []).filter(function (s) { return s && s.veri && s.veri.length; });
    var n = seriler.length ? Math.max.apply(null, seriler.map(function (s) { return s.veri.length; })) : 0;
    if (!n) return bos(canvas, sec);
    var k = kur(canvas, sec);
    if (!k) return null;
    var bicim = sec.bicim || 'sayi';
    var alan = sec.alan !== false;
    var etiketler = [];
    for (var i = 0; i < n; i++) {
      var x = null;
      seriler.forEach(function (s) { if (x == null && s.veri[i]) x = s.veri[i].x; });
      etiketler.push(x == null ? i + 1 : x);
    }
    var maks = 0, min = 0;
    seriler.forEach(function (s) { s.veri.forEach(function (p) {
      if (p && isFinite(p.y)) { maks = Math.max(maks, p.y); min = Math.min(min, p.y); }
    }); });
    if (!(maks > min)) maks = min + 1;
    var SOL = 44, SAG = 10, UST = 10, ALT = 20;
    var vurgu = -1;
    var oran = 1;

    srTablo(k.tablo, ['Nokta'].concat(seriler.map(function (s, j) {
      return s.ad || ('Seri ' + (j + 1));
    })), etiketler.map(function (x, i) {
      return [eksenEtiket(x)].concat(seriler.map(function (s) {
        return bicimle(s.veri[i] ? s.veri[i].y : null, bicim);
      }));
    }), canvas.getAttribute('aria-label') || sec.etiket);

    var gx, gy;
    function ciz(o) {
      if (o != null) oran = o;
      var t = hazirla(canvas), ctx = t.ctx;
      var w = t.g - SOL - SAG, h = t.y - UST - ALT;
      gx = function (i) { return SOL + (n === 1 ? w / 2 : (i / (n - 1)) * w); };
      gy = function (v) { return UST + h - ((v - min) / (maks - min)) * h; };

      // Izgara + y etiketleri
      ctx.strokeStyle = seffaf('line', 0.6);
      ctx.lineWidth = 1;
      ctx.fillStyle = parchmentMid();
      ctx.font = '11px "JetBrains Mono", monospace';
      ctx.textAlign = 'right';
      ctx.textBaseline = 'middle';
      [min, (min + maks) / 2, maks].forEach(function (v) {
        var yy = gy(v);
        ctx.beginPath(); ctx.moveTo(SOL, yy); ctx.lineTo(t.g - SAG, yy); ctx.stroke();
        ctx.fillText(eksenKisa(v, bicim), SOL - 6, yy);
      });
      // x etiketleri: ilk, orta, son
      ctx.textBaseline = 'alphabetic';
      var xi = n > 2 ? [0, Math.floor((n - 1) / 2), n - 1] : (n === 2 ? [0, 1] : [0]);
      xi.forEach(function (i, j) {
        ctx.textAlign = j === 0 ? 'left' : (i === n - 1 ? 'right' : 'center');
        ctx.fillText(eksenEtiket(etiketler[i]), gx(i), t.y - 4);
      });

      if (oran < 1) {
        ctx.save();
        ctx.beginPath();
        ctx.rect(0, 0, SOL + w * oran + 4, t.y);
        ctx.clip();
      }
      seriler.forEach(function (s, j) {
        var r = seriRengi(s, j);
        var yol = function () {
          ctx.beginPath();
          var basladi = false;
          s.veri.forEach(function (p, i) {
            if (!p || !isFinite(p.y)) return;
            if (basladi) ctx.lineTo(gx(i), gy(p.y)); else { ctx.moveTo(gx(i), gy(p.y)); basladi = true; }
          });
        };
        if (alan) {
          yol();
          var son = s.veri.length - 1;
          ctx.lineTo(gx(son), UST + h);
          ctx.lineTo(gx(0), UST + h);
          ctx.closePath();
          var dolgu = ctx.createLinearGradient(0, UST, 0, UST + h);
          dolgu.addColorStop(0, seffaf(r, j === 0 ? 0.32 : 0.14));
          dolgu.addColorStop(1, seffaf(r, 0));
          ctx.fillStyle = dolgu;
          ctx.fill();
        }
        yol();
        ctx.strokeStyle = renk(r);
        ctx.lineWidth = sec.kalin ? 3 : 2.2;
        ctx.lineJoin = 'round';
        ctx.lineCap = 'round';
        ctx.stroke();
        // Son nokta
        var sonP = s.veri[s.veri.length - 1];
        if (sonP && isFinite(sonP.y) && oran === 1) {
          ctx.beginPath();
          ctx.arc(gx(s.veri.length - 1), gy(sonP.y), 3.5, 0, Math.PI * 2);
          ctx.fillStyle = renk(r);
          ctx.fill();
        }
      });
      if (oran < 1) ctx.restore();

      // İmleç
      if (vurgu >= 0) {
        var vx = gx(vurgu);
        ctx.strokeStyle = seffaf('lilac', 0.6);
        ctx.setLineDash([3, 3]);
        ctx.beginPath(); ctx.moveTo(vx, UST); ctx.lineTo(vx, UST + h); ctx.stroke();
        ctx.setLineDash([]);
        seriler.forEach(function (s, j) {
          var p = s.veri[vurgu];
          if (!p || !isFinite(p.y)) return;
          ctx.beginPath();
          ctx.arc(vx, gy(p.y), 4.5, 0, Math.PI * 2);
          ctx.fillStyle = renk('ink');
          ctx.fill();
          ctx.lineWidth = 2;
          ctx.strokeStyle = renk(seriRengi(s, j));
          ctx.stroke();
        });
      }
    }

    var et = etkilesim(canvas, k, {
      adet: function () { return n; },
      konum: function (i) {
        var enUst = Infinity;
        seriler.forEach(function (s) {
          var p = s.veri[i];
          if (p && isFinite(p.y)) enUst = Math.min(enUst, gy(p.y));
        });
        return { x: gx(i), y: isFinite(enUst) ? enUst : UST };
      },
      enYakin: function (mx) {
        if (!gx) return -1;
        var enk = 1e9, en = -1;
        for (var i = 0; i < n; i++) {
          var f = Math.abs(gx(i) - mx);
          if (f < enk) { enk = f; en = i; }
        }
        return en;
      },
      html: function (i) {
        return '<b>' + e(eksenEtiket(etiketler[i])) + '</b>' + seriler.map(function (s, j) {
          var p = s.veri[i];
          return '<span class="seri"><i class="renk-' + e(seriRengi(s, j)) + '"></i>' +
            (s.ad ? e(s.ad) + ': ' : '') + e(bicimle(p ? p.y : null, bicim)) + '</span>';
        }).join('');
      },
      metin: function (i) {
        return eksenEtiket(etiketler[i]) + ', ' + seriler.map(function (s, j) {
          var p = s.veri[i];
          return (s.ad || 'Seri ' + (j + 1)) + ' ' + bicimle(p ? p.y : null, bicim);
        }).join(', ');
      },
      vurgula: function (i) { vurgu = i; ciz(); }
    });
    void et;

    canlandir(ciz);
    izle(canvas, function () { ciz(1); });
    return { ciz: function () { ciz(1); }, yokEt: yokEtOlustur(canvas, k) };
  }

  /* ---------------- Çubuk ---------------- */

  /* cubuk(canvas, {etiketler, degerler, yatay:true, bicim, renk, enCok}) —
     v2: cubuk(canvas, {etiket: sayı}, {enCok, birim}) */
  function cubuk(canvas, sec, eskiSec) {
    if (!canvas) return null;
    sec = sec || {};
    if (!Array.isArray(sec.degerler) && !Array.isArray(sec.etiketler)) {
      var s2 = eskiSec || {};
      var girisler = Object.keys(sec).map(function (a) {
        return [a, Number(sec[a]) || 0];
      }).sort(function (a, c) { return c[1] - a[1]; }).slice(0, s2.enCok || 8);
      sec = { etiketler: girisler.map(function (g) { return g[0]; }),
              degerler: girisler.map(function (g) { return g[1]; }),
              yatay: true, bicim: s2.birim === '$' ? 'para' : 'sayi',
              etiket: s2.etiket };
    }
    var etiketler = sec.etiketler || [];
    var degerler = (sec.degerler || []).map(function (v) { return Number(v) || 0; });
    var n = Math.min(etiketler.length, degerler.length);
    if (sec.enCok && n > sec.enCok) n = sec.enCok;
    if (!n) return bos(canvas, sec);
    var k = kur(canvas, sec);
    if (!k) return null;
    var bicim = sec.bicim || 'sayi';
    var yatay = sec.yatay !== false;
    var rAd = sec.renk || 'violet';
    var maks = Math.max.apply(null, degerler.slice(0, n).map(Math.abs).concat([1]));
    var vurgu = -1, oran = 1;
    var kutular = [];

    srTablo(k.tablo, ['Etiket', 'Değer'], etiketler.slice(0, n).map(function (x, i) {
      return [String(x), bicimle(degerler[i], bicim)];
    }), canvas.getAttribute('aria-label') || sec.etiket);

    var SATIR = sec.satirYuksekligi || 26;
    if (yatay && !sec.sabitYukseklik) {
      canvas.style.height = (n * SATIR + 6) + 'px'; // dinamik yükseklik
    }

    function ciz(o) {
      if (o != null) oran = o;
      var t = hazirla(canvas), ctx = t.ctx;
      kutular = [];
      ctx.font = '12px Manrope, sans-serif';
      ctx.textBaseline = 'middle';
      if (yatay) {
        var SOL = Math.min(130, Math.max(70, Math.round(t.g * 0.28))), SAG = 62;
        for (var i = 0; i < n; i++) {
          var yy = i * SATIR + 5;
          var gen = Math.max((Math.abs(degerler[i]) / maks) * (t.g - SOL - SAG) * oran, 2);
          ctx.fillStyle = parchmentMid();
          ctx.textAlign = 'left';
          var ad = String(etiketler[i]);
          while (ad.length > 3 && ctx.measureText(ad).width > SOL - 10) ad = ad.slice(0, -2) + '…';
          ctx.fillText(ad, 0, yy + 7);
          ctx.fillStyle = degerler[i] < 0 ? renk('madder')
            : (vurgu === i ? renk('gold') : renk(rAd));
          ctx.beginPath();
          if (ctx.roundRect) ctx.roundRect(SOL, yy, gen, 14, 7); else ctx.rect(SOL, yy, gen, 14);
          ctx.fill();
          ctx.fillStyle = renk('parchment');
          ctx.font = '11.5px "JetBrains Mono", monospace';
          ctx.fillText(bicimle(degerler[i], bicim), SOL + gen + 7, yy + 7);
          ctx.font = '12px Manrope, sans-serif';
          kutular.push({ x: SOL, y: yy, w: t.g - SOL, h: 14, ux: SOL + gen, uy: yy });
        }
      } else {
        var UST = 8, ALT = 22, SOLD = 40;
        var w = t.g - SOLD - 8, h = t.y - UST - ALT;
        var adim = w / n, bw = Math.max(4, Math.min(adim * 0.62, 48));
        ctx.strokeStyle = seffaf('line', 0.6);
        ctx.fillStyle = parchmentMid();
        ctx.font = '11px "JetBrains Mono", monospace';
        ctx.textAlign = 'right';
        [0, maks / 2, maks].forEach(function (v) {
          var yy = UST + h - (v / maks) * h;
          ctx.beginPath(); ctx.moveTo(SOLD, yy); ctx.lineTo(t.g - 8, yy); ctx.stroke();
          ctx.fillText(eksenKisa(v, bicim), SOLD - 6, yy);
        });
        for (var j = 0; j < n; j++) {
          var cx = SOLD + adim * j + adim / 2;
          var bh = (Math.abs(degerler[j]) / maks) * h * oran;
          ctx.fillStyle = degerler[j] < 0 ? renk('madder') : (vurgu === j ? renk('gold') : renk(rAd));
          ctx.beginPath();
          if (ctx.roundRect) ctx.roundRect(cx - bw / 2, UST + h - bh, bw, bh, [4, 4, 0, 0]);
          else ctx.rect(cx - bw / 2, UST + h - bh, bw, bh);
          ctx.fill();
          kutular.push({ x: cx - adim / 2, y: UST, w: adim, h: h, ux: cx, uy: UST + h - bh });
          if (n <= 12 || j % Math.ceil(n / 12) === 0) {
            ctx.fillStyle = parchmentMid();
            ctx.font = '11px "JetBrains Mono", monospace';
            ctx.textAlign = 'center';
            ctx.fillText(eksenEtiket(etiketler[j]), cx, t.y - 6);
          }
        }
      }
    }

    etkilesim(canvas, k, {
      adet: function () { return n; },
      konum: function (i) { var q = kutular[i]; return q ? { x: q.ux, y: q.uy } : { x: 0, y: 0 }; },
      enYakin: function (mx, my) {
        for (var i = 0; i < kutular.length; i++) {
          var q = kutular[i];
          if (yatay ? (my >= q.y - 6 && my <= q.y + q.h + 6) : (mx >= q.x && mx <= q.x + q.w)) return i;
        }
        return -1;
      },
      html: function (i) {
        return '<b>' + e(etiketler[i]) + '</b>' + e(bicimle(degerler[i], bicim));
      },
      metin: function (i) { return etiketler[i] + ' ' + bicimle(degerler[i], bicim); },
      vurgula: function (i) { vurgu = i; ciz(); }
    });

    canlandir(ciz);
    izle(canvas, function () { ciz(1); });
    return { ciz: function () { ciz(1); }, yokEt: yokEtOlustur(canvas, k) };
  }

  /* ---------------- Yığın ---------------- */

  /* yigin(canvas, {etiketler, seriler:[{ad, veri:[sayı], renk}], bicim}) */
  function yigin(canvas, sec) {
    if (!canvas) return null;
    sec = sec || {};
    var etiketler = sec.etiketler || [];
    var seriler = (sec.seriler || []).filter(function (s) { return s && s.veri; });
    var n = etiketler.length;
    if (!n || !seriler.length) return bos(canvas, sec);
    var k = kur(canvas, sec);
    if (!k) return null;
    var bicim = sec.bicim || 'sayi';
    var toplamlar = [];
    for (var i = 0; i < n; i++) {
      toplamlar.push(seriler.reduce(function (t, s) { return t + (Number(s.veri[i]) || 0); }, 0));
    }
    var maks = Math.max.apply(null, toplamlar.concat([1]));
    var vurgu = -1, oran = 1, kutular = [];

    srTablo(k.tablo, ['Etiket'].concat(seriler.map(function (s, j) { return s.ad || 'Seri ' + (j + 1); }))
      .concat(['Toplam']), etiketler.map(function (x, i) {
        return [eksenEtiket(x)].concat(seriler.map(function (s) {
          return bicimle(Number(s.veri[i]) || 0, bicim);
        })).concat([bicimle(toplamlar[i], bicim)]);
      }), canvas.getAttribute('aria-label') || sec.etiket);

    // Lejant (kardeş)
    var lejant = document.createElement('div');
    lejant.className = 'grafik-lejant';
    lejant.setAttribute('aria-hidden', 'true');
    lejant.innerHTML = seriler.map(function (s, j) {
      return '<span><i class="lejant-nokta renk-' + e(seriRengi(s, j)) + '"></i>' +
        e(s.ad || 'Seri ' + (j + 1)) + '</span>';
    }).join('');
    k.kap.appendChild(lejant);

    function ciz(o) {
      if (o != null) oran = o;
      var t = hazirla(canvas), ctx = t.ctx;
      var UST = 8, ALT = 22, SOL = 44;
      var w = t.g - SOL - 8, h = t.y - UST - ALT;
      var adim = w / n, bw = Math.max(4, Math.min(adim * 0.62, 40));
      kutular = [];
      ctx.strokeStyle = seffaf('line', 0.6);
      ctx.fillStyle = parchmentMid();
      ctx.font = '11px "JetBrains Mono", monospace';
      ctx.textAlign = 'right';
      ctx.textBaseline = 'middle';
      [0, maks / 2, maks].forEach(function (v) {
        var yy = UST + h - (v / maks) * h;
        ctx.beginPath(); ctx.moveTo(SOL, yy); ctx.lineTo(t.g - 8, yy); ctx.stroke();
        ctx.fillText(eksenKisa(v, bicim), SOL - 6, yy);
      });
      for (var i = 0; i < n; i++) {
        var cx = SOL + adim * i + adim / 2;
        var taban = UST + h;
        seriler.forEach(function (s, j) {
          var v = (Number(s.veri[i]) || 0);
          var bh = (v / maks) * h * oran;
          ctx.fillStyle = vurgu === i ? seffaf(seriRengi(s, j), 1) : seffaf(seriRengi(s, j), 0.85);
          ctx.fillRect(cx - bw / 2, taban - bh, bw, bh);
          taban -= bh;
        });
        kutular.push({ x: cx - adim / 2, w: adim, ux: cx, uy: taban });
        if (n <= 12 || i % Math.ceil(n / 12) === 0) {
          ctx.fillStyle = parchmentMid();
          ctx.textAlign = 'center';
          ctx.textBaseline = 'alphabetic';
          ctx.fillText(eksenEtiket(etiketler[i]), cx, t.y - 6);
          ctx.textBaseline = 'middle';
        }
      }
      if (vurgu >= 0 && kutular[vurgu]) {
        ctx.strokeStyle = seffaf('lilac', 0.6);
        ctx.setLineDash([3, 3]);
        ctx.strokeRect(kutular[vurgu].x + 1, UST, kutular[vurgu].w - 2, h);
        ctx.setLineDash([]);
      }
    }

    etkilesim(canvas, k, {
      adet: function () { return n; },
      konum: function (i) { var q = kutular[i]; return q ? { x: q.ux, y: q.uy } : { x: 0, y: 0 }; },
      enYakin: function (mx) {
        for (var i = 0; i < kutular.length; i++) {
          if (mx >= kutular[i].x && mx <= kutular[i].x + kutular[i].w) return i;
        }
        return -1;
      },
      html: function (i) {
        return '<b>' + e(eksenEtiket(etiketler[i])) + ' · ' + e(bicimle(toplamlar[i], bicim)) +
          '</b>' + seriler.map(function (s, j) {
            return '<span class="seri"><i class="renk-' + e(seriRengi(s, j)) + '"></i>' +
              e(s.ad || 'Seri ' + (j + 1)) + ': ' + e(bicimle(Number(s.veri[i]) || 0, bicim)) + '</span>';
          }).join('');
      },
      metin: function (i) {
        return eksenEtiket(etiketler[i]) + ', toplam ' + bicimle(toplamlar[i], bicim) + ', ' +
          seriler.map(function (s, j) {
            return (s.ad || 'Seri ' + (j + 1)) + ' ' + bicimle(Number(s.veri[i]) || 0, bicim);
          }).join(', ');
      },
      vurgula: function (i) { vurgu = i; ciz(); }
    });

    canlandir(ciz);
    izle(canvas, function () { ciz(1); });
    var yok = yokEtOlustur(canvas, k);
    return { ciz: function () { ciz(1); }, yokEt: function () { lejant.remove(); yok(); } };
  }

  /* ---------------- Halka ---------------- */

  /* halka(canvas, {dilimler:[{ad, deger, renk}], bicim, merkez}) — lejant
     kardeş <ul class="halka-lejant">. Kap `.halka-kap` içindeyse yan yana. */
  function halka(canvas, sec) {
    if (!canvas) return null;
    sec = sec || {};
    var dilimler = (sec.dilimler || []).map(function (d, i) {
      return { ad: d.ad, deger: Math.max(0, Number(d.deger) || 0), renk: seriRengi(d, i) };
    }).filter(function (d) { return d.deger > 0; });
    var toplam = dilimler.reduce(function (t, d) { return t + d.deger; }, 0);
    if (!dilimler.length || !toplam) return bos(canvas, sec);
    var k = kur(canvas, sec);
    if (!k) return null;
    var bicim = sec.bicim || 'sayi';
    var vurgu = -1, oran = 1, merkez = null, yaricap = 0, acilar = [];

    srTablo(k.tablo, ['Dilim', 'Değer', 'Pay'], dilimler.map(function (d) {
      return [d.ad, bicimle(d.deger, bicim), payMetni(d.deger, toplam)];
    }), canvas.getAttribute('aria-label') || sec.etiket);

    var lejant = document.createElement('ul');
    lejant.className = 'halka-lejant';
    lejant.setAttribute('aria-hidden', 'true');
    lejant.innerHTML = dilimler.map(function (d, i) {
      return '<li data-i="' + i + '"><i class="lejant-nokta renk-' + e(d.renk) + '"></i>' +
        '<span class="ad">' + e(d.ad) + '</span><span class="deger">' + e(bicimle(d.deger, bicim)) +
        '</span><span class="oran">' + e(payMetni(d.deger, toplam)) + '</span></li>';
    }).join('');
    // Lejant kabın yanına: halka-kap varsa oraya, yoksa grafik-kap'ın ardına.
    var dis = k.kap.parentElement && k.kap.parentElement.classList.contains('halka-kap')
      ? k.kap.parentElement : k.kap;
    dis.appendChild(lejant);

    function ciz(o) {
      if (o != null) oran = o;
      var t = hazirla(canvas), ctx = t.ctx;
      merkez = { x: t.g / 2, y: t.y / 2 };
      yaricap = Math.min(t.g, t.y) / 2 - 6;
      var kalin = Math.max(12, yaricap * 0.32);
      var a = -Math.PI / 2;
      acilar = [];
      ctx.lineWidth = kalin;
      ctx.strokeStyle = seffaf('line', 0.8);
      ctx.beginPath(); ctx.arc(merkez.x, merkez.y, yaricap - kalin / 2, 0, Math.PI * 2); ctx.stroke();
      dilimler.forEach(function (d, i) {
        var pay = d.deger / toplam * Math.PI * 2 * oran;
        acilar.push([a, a + pay]);
        ctx.beginPath();
        ctx.arc(merkez.x, merkez.y, yaricap - kalin / 2 + (vurgu === i ? 2 : 0), a + 0.01, a + pay - 0.01);
        ctx.strokeStyle = renk(d.renk);
        ctx.lineWidth = kalin + (vurgu === i ? 4 : 0);
        ctx.stroke();
        a += pay;
      });
      // Merkez metni
      var orta = vurgu >= 0 ? dilimler[vurgu] : null;
      ctx.fillStyle = renk('parchment');
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.font = '700 ' + Math.max(13, yaricap * 0.3) + 'px Sora, sans-serif';
      ctx.fillText(orta ? payMetni(orta.deger, toplam, 0) :
        (sec.merkez != null ? String(sec.merkez) : bicimle(toplam, bicim)), merkez.x, merkez.y - 2);
      ctx.fillStyle = parchmentMid();
      ctx.font = '11px Manrope, sans-serif';
      var altMetin = orta ? String(orta.ad) : (sec.merkezAlt || 'toplam');
      while (altMetin.length > 3 && ctx.measureText(altMetin).width > (yaricap - kalin) * 1.7) {
        altMetin = altMetin.slice(0, -2) + '…';
      }
      ctx.fillText(altMetin, merkez.x, merkez.y + Math.max(11, yaricap * 0.2));
    }

    function vurgula(i) {
      vurgu = i;
      Array.prototype.forEach.call(lejant.children, function (li, j) {
        li.classList.toggle('secili', j === i);
      });
      ciz();
    }
    lejant.addEventListener('mouseover', function (ev) {
      var li = ev.target.closest('li');
      if (li) vurgula(Number(li.getAttribute('data-i')));
    });
    lejant.addEventListener('mouseleave', function () { vurgula(-1); });

    etkilesim(canvas, k, {
      adet: function () { return dilimler.length; },
      konum: function (i) {
        var ac = acilar[i];
        if (!ac || !merkez) return { x: 0, y: 0 };
        var orta = (ac[0] + ac[1]) / 2;
        return { x: merkez.x + Math.cos(orta) * yaricap * 0.75,
                 y: merkez.y + Math.sin(orta) * yaricap * 0.75 };
      },
      enYakin: function (mx, my) {
        if (!merkez) return -1;
        var dx = mx - merkez.x, dy = my - merkez.y;
        var uz = Math.sqrt(dx * dx + dy * dy);
        if (uz > yaricap + 4 || uz < yaricap * 0.4) return -1;
        var ac = Math.atan2(dy, dx);
        if (ac < -Math.PI / 2) ac += Math.PI * 2;
        for (var i = 0; i < acilar.length; i++) {
          if (ac >= acilar[i][0] && ac < acilar[i][1]) return i;
        }
        return -1;
      },
      html: function (i) {
        var d = dilimler[i];
        return '<b>' + e(d.ad) + '</b>' + e(bicimle(d.deger, bicim)) + ' · ' +
          e(payMetni(d.deger, toplam));
      },
      metin: function (i) {
        var d = dilimler[i];
        return d.ad + ' ' + bicimle(d.deger, bicim) + ', yüzde ' +
          (d.deger / toplam * 100).toFixed(1).replace('.', ',');
      },
      vurgula: vurgula
    });

    canlandir(ciz);
    izle(canvas, function () { ciz(1); });
    var yok = yokEtOlustur(canvas, k);
    return { ciz: function () { ciz(1); }, yokEt: function () { lejant.remove(); yok(); } };
  }

  /* ---------------- Kıvılcım ---------------- */

  /* kivilcim(canvas, {veri:[sayı], renk}) — süsleyici: KPI kartında değer
     zaten metin olarak var; tuval aria-hidden, odaklanmaz, ipucu yok. */
  function kivilcim(canvas, sec) {
    if (!canvas) return null;
    sec = sec || {};
    var veri = (sec.veri || []).map(Number).filter(isFinite);
    canvas.setAttribute('aria-hidden', 'true');
    canvas.removeAttribute('tabindex');
    if (veri.length < 2) {
      birak(canvas);
      return { ciz: function () {}, yokEt: function () {} };
    }
    var r = sec.renk || 'lilac';
    function ciz() {
      var t = hazirla(canvas), ctx = t.ctx;
      if (!t.g || !t.y) return;
      var maks = Math.max.apply(null, veri), min = Math.min.apply(null, veri);
      if (!(maks > min)) { maks = min + 1; }
      var w = t.g - 4, h = t.y - 4;
      var x = function (i) { return 2 + (i / (veri.length - 1)) * w; };
      var y = function (v) { return 2 + h - ((v - min) / (maks - min)) * h; };
      ctx.beginPath();
      veri.forEach(function (v, i) { i ? ctx.lineTo(x(i), y(v)) : ctx.moveTo(x(i), y(v)); });
      ctx.lineTo(x(veri.length - 1), 2 + h);
      ctx.lineTo(x(0), 2 + h);
      ctx.closePath();
      var dolgu = ctx.createLinearGradient(0, 0, 0, t.y);
      dolgu.addColorStop(0, seffaf(r, 0.25));
      dolgu.addColorStop(1, seffaf(r, 0));
      ctx.fillStyle = dolgu;
      ctx.fill();
      ctx.beginPath();
      veri.forEach(function (v, i) { i ? ctx.lineTo(x(i), y(v)) : ctx.moveTo(x(i), y(v)); });
      ctx.strokeStyle = renk(r);
      ctx.lineWidth = 1.6;
      ctx.lineJoin = 'round';
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(x(veri.length - 1), y(veri[veri.length - 1]), 2.2, 0, Math.PI * 2);
      ctx.fillStyle = renk(r);
      ctx.fill();
    }
    ciz();
    izle(canvas, ciz);
    return { ciz: ciz, yokEt: function () { birak(canvas); } };
  }

  RY.grafik = { renk: renk, seffaf: seffaf, izle: izle, cizgi: cizgi,
                cubuk: cubuk, yigin: yigin, halka: halka, kivilcim: kivilcim };
})();

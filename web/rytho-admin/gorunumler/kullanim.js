/* Kullanım & AI (AD19): adminStats rollup'ından çağrı/maliyet/token
   kırılımı — usageEvents TARANMAZ.

   Rota: #/kullanim?days=7|30|90 (varsayılan 30; başka değer 30'a düşer).
   Uç: GET /api/v1/admin/usage?days → {days, byDay:{gün:{calls,
   estCostUsd}}, byFeature:{öz:{calls, estCostUsd, promptTokens,
   outputTokens}}, byModel:{model:{calls, estCostUsd}}, totals:{calls,
   estCostUsd, promptTokens, outputTokens}, topUsers:[{uid, aiCostUsd,
   calls, displayName, email}], costs:{öz: jeton}}.

   Maliyetler TAHMİNİDİR (ölçülen token × birim fiyat); gerçek fatura Cloud
   Console'da. Anomali: son günün maliyeti önceki 7 günün ortalamasının
   1,5 katını aşarsa uyarı bandı. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  var GUNLER = [7, 30, 90];

  /* Özellik anahtarı → okunur ad (bilinmeyen anahtar olduğu gibi). */
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

  function gunSec(params) {
    var d = Number(params && params.days);
    return GUNLER.indexOf(d) >= 0 ? d : 30;
  }

  /* byDay {gün: {...}} → [{gun, calls, cost}] eskiden yeniye. */
  function gunSerisi(byDay) {
    return Object.keys(byDay || {}).sort().map(function (g) {
      var k = byDay[g] || {};
      return { gun: g, calls: Number(k.calls) || 0, cost: Number(k.estCostUsd) || 0 };
    });
  }

  function anomali(seri) {
    if (seri.length < 2) return null;
    var son = seri[seri.length - 1];
    var onceki = seri.slice(Math.max(0, seri.length - 8), seri.length - 1);
    if (!onceki.length) return null;
    var ort = onceki.reduce(function (t, g) { return t + g.cost; }, 0) / onceki.length;
    if (ort > 0 && son.cost > ort * 1.5) return { gun: son.gun, cost: son.cost, ort: ort };
    return null;
  }

  function kisiHucresi(b, u) {
    var ad = u.displayName || u.email || u.uid;
    var alt = u.displayName && u.email ? u.email : (u.uid !== ad ? u.uid : '');
    return '<span class="vt-kimlik"><span class="avatar">' +
      b.e(b.basHarfler(u.displayName, u.email)) + '</span><div>' + b.e(ad) +
      (alt ? '<span>' + b.e(alt) + '</span>' : '') + '</div></span>';
  }

  RY.gorunumler.kullanim = async function (icerik, args, params) {
    var b = RY.b;
    var gun = gunSec(params);

    var veri = await RY.sorgu('/api/v1/admin/usage', { days: gun });
    var toplam = veri.totals || {};
    var seri = gunSerisi(veri.byDay);
    var son = seri.length ? seri[seri.length - 1] : null;
    var byFeature = veri.byFeature || {};
    var byModel = veri.byModel || {};
    var costs = veri.costs || {};
    var topUsers = Array.isArray(veri.topUsers) ? veri.topUsers : [];

    var cipler = GUNLER.map(function (d) {
      return '<button type="button" class="adm-cip altin" data-gun="' + d +
        '" aria-pressed="' + (d === gun ? 'true' : 'false') + '">' + d + ' gün</button>';
    }).join('');

    var bas = b.sayfaBaslik({
      baslik: 'Kullanım & AI',
      alt: 'Son ' + gun + ' gün · gecelik rollup · maliyetler tahmini',
      eylemlerHtml: '<div class="cip-grup" role="group" aria-label="Dönem" id="kullanim-donem">' +
        cipler + '</div>'
    });

    if (!toplam.calls) {
      icerik.innerHTML = bas + b.bosDurum(
        'Bu dönemde kullanım olayı yok — ilk LLM çağrısı ve gecelik toplamayla ' +
        'dolmaya başlar. Önbellekten servis edilen istekler burada görünmez.',
        { ikon: 'ai' });
      donemBagla(icerik, gun);
      return;
    }

    var an = anomali(seri);
    var bant = an
      ? b.bant('<b>Maliyet sıçraması</b> — ' + b.e(b.tarih(an.gun)) + ' günü ' +
          b.e(b.para(an.cost)) + ', önceki 7 günün ortalaması ' + b.e(b.para(an.ort)) +
          ' (×' + (an.cost / an.ort).toFixed(1).replace('.', ',') + ').', 'uyari',
          { html: true })
      : '';

    var ciktiToken = Number(toplam.outputTokens) || 0;
    var kpiler = '<section class="izgara-kpi" aria-label="Kullanım özeti">' +
      b.istatistikKarti({ ad: son ? 'Son gün çağrı' : 'Bugün çağrı',
        deger: b.sayi(son ? son.calls : 0), alt: son ? b.tarih(son.gun) : '—',
        kivilcim: seri.map(function (g) { return g.calls; }) }) +
      b.istatistikKarti({ ad: son ? 'Son gün maliyet' : 'Bugün maliyet',
        deger: b.para(son ? son.cost : 0), alt: an ? 'ortalamanın üstünde' : 'tahmini',
        kivilcim: seri.map(function (g) { return g.cost; }), renk: an ? 'madder' : 'lilac' }) +
      b.istatistikKarti({ ad: gun + ' gün çağrı', deger: b.sayi(toplam.calls) }) +
      b.istatistikKarti({ ad: gun + ' gün maliyet', deger: b.para(toplam.estCostUsd),
        altin: true, alt: 'tahmini' }) +
      b.istatistikKarti({ ad: 'Girdi token', deger: b.sayi(toplam.promptTokens || 0) }) +
      b.istatistikKarti({ ad: 'Çıktı token', deger: b.sayi(ciktiToken),
        alt: 'düşünme dahil' }) +
      '</section>';

    var grafikler =
      '<div class="izgara-2">' +
      b.modul('Günlük çağrı', '<div class="grafik-kap"><canvas id="g-kul-cagri" class="grafik" ' +
        'aria-label="Günlük çağrı sayısı"></canvas></div>', '', { alt: gun + ' gün' }) +
      b.modul('Günlük maliyet', '<div class="grafik-kap"><canvas id="g-kul-maliyet" class="grafik" ' +
        'aria-label="Günlük tahmini maliyet"></canvas></div>', '', { alt: gun + ' gün · $' }) +
      '</div>' +
      '<div class="izgara-2">' +
      b.modul('Özellik başına maliyet', '<div class="grafik-kap"><canvas id="g-kul-ozellik" ' +
        'class="grafik grafik-kucuk" aria-label="Özellik başına tahmini maliyet"></canvas></div>',
        '', { alt: 'tahmini $' }) +
      b.modul('Model kırılımı', '<div class="halka-kap"><div class="grafik-kap"><canvas id="g-kul-model" ' +
        'class="grafik" aria-label="Model başına maliyet"></canvas></div></div>', '',
        { alt: 'tahmini maliyet payı' }) +
      '</div>' +
      b.modul('Özellik başına girdi ve çıktı token', '<div class="grafik-kap"><canvas id="g-kul-token" ' +
        'class="grafik" aria-label="Özellik başına girdi ve çıktı token"></canvas></div>', '',
        { alt: 'girdi + çıktı' });

    var tablolar = '<div class="izgara-2">' +
      b.modul('En çok maliyet üreten kullanıcılar', '<div id="kul-top"></div>', '',
        { alt: 'son rollup günü · ilk 20 · 360\'a gider' }) +
      b.modul('Kredi bedelleri', '<div id="kul-bedel"></div>', '',
        { alt: 'sunucu gerçeği · özellik başına düşülen kredi' }) +
      '</div>' +
      '<p class="dipnot">Tahmini maliyet = ölçülen token × sabit birim fiyat. Gerçek fatura ' +
      'için Cloud Console. Yalnız GERÇEK model çağrıları sayılır — önbellek isabetleri ' +
      'bedava ve burada yok. Günler UTC.</p>';

    icerik.innerHTML = bas + bant + kpiler + grafikler + tablolar;
    donemBagla(icerik, gun);

    /* Grafikler */
    var g = RY.grafik;
    g.cizgi(document.getElementById('g-kul-cagri'), {
      seriler: [{ ad: 'Çağrı', renk: 'magenta',
        veri: seri.map(function (x) { return { x: x.gun, y: x.calls }; }) }],
      alan: true, bicim: 'sayi', etiket: 'Günlük çağrı'
    });
    g.cizgi(document.getElementById('g-kul-maliyet'), {
      seriler: [{ ad: 'Maliyet', renk: 'gold',
        veri: seri.map(function (x) { return { x: x.gun, y: x.cost }; }) }],
      alan: true, bicim: 'para', etiket: 'Günlük maliyet'
    });

    var ozellikler = Object.keys(byFeature).sort(function (x, y) {
      return (Number(byFeature[y].estCostUsd) || 0) - (Number(byFeature[x].estCostUsd) || 0);
    });
    g.cubuk(document.getElementById('g-kul-ozellik'), {
      etiketler: ozellikler.map(ozellikAdi),
      degerler: ozellikler.map(function (k) { return Number(byFeature[k].estCostUsd) || 0; }),
      yatay: true, bicim: 'para', enCok: 10, etiket: 'Özellik başına maliyet'
    });

    var modeller = Object.keys(byModel);
    var modelMaliyetVar = modeller.some(function (m) { return (Number(byModel[m].estCostUsd) || 0) > 0; });
    g.halka(document.getElementById('g-kul-model'), {
      dilimler: modeller.map(function (m) {
        return { ad: m, deger: modelMaliyetVar ? (Number(byModel[m].estCostUsd) || 0)
                                               : (Number(byModel[m].calls) || 0) };
      }),
      bicim: modelMaliyetVar ? 'para' : 'sayi',
      merkezAlt: modelMaliyetVar ? 'maliyet' : 'çağrı', etiket: 'Model kırılımı'
    });

    var tokenVar = ozellikler.some(function (k) {
      return (Number(byFeature[k].promptTokens) || 0) + (Number(byFeature[k].outputTokens) || 0) > 0;
    });
    g.yigin(document.getElementById('g-kul-token'), {
      etiketler: tokenVar ? ozellikler.map(ozellikAdi) : [],
      seriler: [
        { ad: 'Girdi', renk: 'lilac', veri: ozellikler.map(function (k) { return Number(byFeature[k].promptTokens) || 0; }) },
        { ad: 'Çıktı', renk: 'gold', veri: ozellikler.map(function (k) { return Number(byFeature[k].outputTokens) || 0; }) }
      ],
      bicim: 'sayi', etiket: 'Özellik başına girdi ve çıktı token',
      bosMetin: 'Token kırılımı rollup\'ta yok — ilk toplamayla dolar'
    });

    /* Top kullanıcılar */
    var vt = b.veriTablosu({
      kimlik: 'kul-top-tablo', etiket: 'En çok maliyet üreten kullanıcılar', yogunluk: 'sik',
      sutunlar: [
        { ad: 'ad', baslik: 'Kullanıcı', deger: function (u) { return u.displayName || u.email || u.uid; },
          bicim: function (u) { return kisiHucresi(b, u); } },
        { ad: 'calls', baslik: 'Çağrı', hizala: 'sag', siralanir: true },
        { ad: 'aiCostUsd', baslik: 'Maliyet', hizala: 'sag', siralanir: true,
          bicim: function (u) { return b.e(b.para(u.aiCostUsd)); } }
      ],
      anahtar: function (u) { return u.uid; },
      satirHref: function (u) { return RY.rotaBagi('kullanicilar', [u.uid]); },
      siralama: { ad: 'aiCostUsd', yon: 'desc' },
      bosMetin: 'Rollup\'ta kullanıcı satırı yok — adminEconomics ilk toplamayla dolar.'
    });
    document.getElementById('kul-top').appendChild(vt.el);
    vt.guncelle(topUsers);

    /* Bedel tablosu */
    var bedeller = Object.keys(costs).map(function (k) {
      var kova = byFeature[k] || {};
      return { ad: k, etiket: ozellikAdi(k), jeton: Number(costs[k]) || 0,
               calls: Number(kova.calls) || 0 };
    });
    var bt = b.veriTablosu({
      kimlik: 'kul-bedel-tablo', etiket: 'Kredi bedelleri', yogunluk: 'sik',
      sutunlar: [
        { ad: 'etiket', baslik: 'Özellik', siralanir: true,
          bicim: function (s) { return b.e(s.etiket) + ' <span class="mono dipnot">' + b.e(s.ad) + '</span>'; } },
        { ad: 'jeton', baslik: 'Kredi', hizala: 'sag', siralanir: true },
        { ad: 'calls', baslik: 'Çağrı (' + gun + 'g)', hizala: 'sag', siralanir: true }
      ],
      anahtar: function (s) { return s.ad; },
      siralama: { ad: 'jeton', yon: 'desc' },
      bosMetin: 'Bedel tablosu gelmedi.'
    });
    document.getElementById('kul-bedel').appendChild(bt.el);
    bt.guncelle(bedeller);
  };

  /* Dönem çipleri: URL'ye yazılır, görünüm yeniden çizilir (rotaYaz). */
  function donemBagla(icerik, gun) {
    var kap = icerik.querySelector('#kullanim-donem');
    if (!kap) return;
    kap.addEventListener('click', function (ev) {
      var d = ev.target.closest('.adm-cip');
      if (!d) return;
      var yeni = Number(d.getAttribute('data-gun'));
      if (yeni === gun) return;
      RY.rotaYaz('kullanim', [], { days: yeni });
    });
  }

  RY.kirintiSaglayici.kullanim = function () {
    return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Kullanım & AI' }];
  };
})();

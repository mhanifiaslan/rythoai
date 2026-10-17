/* Kullanım & AI (AD19): adminStats rollup'ından çağrı/maliyet/model birimi
   kırılımı — usageEvents TARANMAZ.

   Rota: #/kullanim?days=7|30|90 (varsayılan 30; başka değer 30'a düşer).
   Dönem değişince yalnız veri bölgesi yeniden çekilir; adres sessizce
   güncellenir (geçmişe kayıt düşmez, yenilemede seçim kalır).
   Uç: GET /api/v1/admin/usage?days → {days, byDay:{gün:{calls,
   estCostUsd}}, byFeature:{öz:{calls, estCostUsd, promptTokens,
   outputTokens}}, byModel:{model:{calls, estCostUsd}}, totals:{calls,
   estCostUsd, promptTokens, outputTokens}, topUsers:[{uid, aiCostUsd,
   calls, displayName, email}], costs:{öz: kredi bedeli}}.

   Maliyetler TAHMİNİDİR (ölçülen model birimi × birim fiyat); gerçek fatura
   Google Cloud'da. Ekranda "token" kelimesi yok: kullanıcıya görünen tek
   sayaç kelimesi "kredi" (depo sözlük kuralı) ve modelin faturalandırma
   birimi kredi DEĞİL — ona "birim" deniyor. Anomali: son günün maliyeti
   önceki 7 günün ortalamasının 1,5 katını aşarsa uyarı bandı. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  var GUNLER = [7, 30, 90];
  var VARSAYILAN_GUN = 30;

  function ozellikAdi(k) { return RY.sozluk.ozellikAdi(k); }

  function gunSec(params) {
    var d = Number(params && params.days);
    return GUNLER.indexOf(d) >= 0 ? d : VARSAYILAN_GUN;
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

  RY.gorunumler.kullanim = async function (icerik, args, params, baglam) {
    var b = RY.b;
    var gun = gunSec(params);
    var yeniIstek = b.tazeleyici(baglam);

    icerik.innerHTML = b.sayfaBaslik({
      baslik: 'Kullanım & AI',
      alt: 'Model çağrıları, tahmini maliyet ve kredi bedelleri · saatlik özetten'
    }) +
      '<div class="suzgec-seridi" id="kullanim-suzgec"><span class="dipnot suzgec-not">Günler UTC\'ye göre (Türkiye saatinden 3 saat geride)</span></div>' +
      '<div class="veri-alani" id="kullanim-veri">' + b.iskelet() + '</div>';

    var alan = icerik.querySelector('#kullanim-veri');
    var serit = icerik.querySelector('#kullanim-suzgec');
    serit.insertBefore(b.donemSecici({
      secenekler: GUNLER, deger: gun,
      onDegis: function (yeni) {
        gun = yeni;
        RY.rotaYaz('kullanim', [], gun === VARSAYILAN_GUN ? {} : { days: gun }, { sessiz: true });
        yukle();
      }
    }), serit.firstChild);

    function yukle() {
      var istek = yeniIstek();
      alan.setAttribute('aria-busy', 'true');
      return RY.sorgu('/api/v1/admin/usage', { days: gun }, { sinyal: istek.sinyal }).then(function (veri) {
        if (!istek.gecerli()) return;
        alan.removeAttribute('aria-busy');
        veriCiz(alan, veri || {}, gun);
      }).catch(function (h) {
        if (!istek.gecerli() || (h && h.iptal)) return;
        alan.removeAttribute('aria-busy');
        alan.innerHTML = b.hataDurum(RY.hataMetni(h), { kimlik: 'kullanim-tekrar' });
        alan.querySelector('#kullanim-tekrar').addEventListener('click', yukle);
      });
    }
    await yukle();
  };

  function veriCiz(alan, veri, gun) {
    var b = RY.b;
    var toplam = veri.totals || {};
    var seri = gunSerisi(veri.byDay);
    var son = seri.length ? seri[seri.length - 1] : null;
    var byFeature = veri.byFeature || {};
    var byModel = veri.byModel || {};
    var costs = veri.costs || {};
    var topUsers = Array.isArray(veri.topUsers) ? veri.topUsers : [];

    if (!toplam.calls) {
      alan.innerHTML = b.bosDurum(
        'Son ' + gun + ' günde model çağrısı yok — ilk çağrı ve sonraki saatlik toplamayla ' +
        'dolmaya başlar. Önbellekten verilen yanıtlar burada görünmez.',
        { ikon: 'ai' });
      return;
    }

    var an = anomali(seri);
    var bant = an
      ? b.bant('<b>Maliyet sıçraması</b> — ' + b.e(b.tarih(an.gun)) + ' günü ' +
          b.e(b.para(an.cost)) + ', önceki 7 günün ortalaması ' + b.e(b.para(an.ort)) +
          ' (×' + (an.cost / an.ort).toFixed(1).replace('.', ',') + ').', 'uyari',
          { html: true })
      : '';

    // Son gün çoğu zaman BUGÜNDÜR ve özet saatlik: sayı günün tamamı değil,
    // o ana kadarki kısmıdır. Etiket bunu söylemezse dünün tam günüyle
    // kıyaslanan yarım bir gün "düşüş" gibi okunur.
    var sonBugun = son && son.gun === b.utcGun(0);
    var sonAlt = son ? (sonBugun ? 'bugün, şu ana kadar' : b.tarih(son.gun)) : '—';

    var ciktiBirimi = Number(toplam.outputTokens) || 0;
    var kpiler = '<section class="izgara-kpi" aria-label="Kullanım özeti">' +
      b.istatistikKarti({ ad: 'Son gün çağrı',
        deger: b.sayi(son ? son.calls : 0), alt: sonAlt,
        kivilcim: seri.map(function (g) { return g.calls; }) }) +
      b.istatistikKarti({ ad: 'Son gün maliyet',
        deger: b.para(son ? son.cost : 0), alt: an ? 'ortalamanın üstünde' : sonAlt + ' · tahmini',
        kivilcim: seri.map(function (g) { return g.cost; }), renk: an ? 'madder' : 'lilac' }) +
      b.istatistikKarti({ ad: gun + ' gün çağrı', deger: b.sayi(toplam.calls) }) +
      b.istatistikKarti({ ad: gun + ' gün maliyet', deger: b.para(toplam.estCostUsd),
        altin: true, alt: 'tahmini' }) +
      b.istatistikKarti({ ad: 'Girdi birimi', deger: b.sayi(toplam.promptTokens || 0),
        alt: 'modele giden metin' }) +
      b.istatistikKarti({ ad: 'Çıktı birimi', deger: b.sayi(ciktiBirimi),
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
      b.modul('Özellik başına girdi ve çıktı birimi', '<div class="grafik-kap"><canvas id="g-kul-birim" ' +
        'class="grafik" aria-label="Özellik başına girdi ve çıktı birimi"></canvas></div>', '',
        { alt: 'girdi + çıktı' });

    var tablolar = '<div class="izgara-2">' +
      b.modul('En çok maliyet üreten kullanıcılar', '<div id="kul-top"></div>', '',
        { alt: 'son özet günü · ilk 20 · satır → ayrıntı' }) +
      b.modul('Kredi bedelleri', '<div id="kul-bedel"></div>', '',
        { alt: 'sunucudaki değer · özellik başına düşülen kredi' }) +
      '</div>' +
      '<p class="dipnot">Tahmini maliyet = ölçülen model birimi × sabit birim fiyat. Gerçek fatura ' +
      'Google Cloud hesabında. Yalnız GERÇEK model çağrıları sayılır — önbellekten verilen yanıtlar ' +
      'bedava ve burada yok.</p>';

    alan.innerHTML = bant + kpiler + grafikler + tablolar;

    /* Grafikler — kap içinden aranır (bkz. bildirimler.js aynı not). */
    var g = RY.grafik;
    g.cizgi(alan.querySelector('#g-kul-cagri'), {
      seriler: [{ ad: 'Çağrı', renk: 'magenta',
        veri: seri.map(function (x) { return { x: x.gun, y: x.calls }; }) }],
      alan: true, bicim: 'sayi', etiket: 'Günlük çağrı'
    });
    g.cizgi(alan.querySelector('#g-kul-maliyet'), {
      seriler: [{ ad: 'Maliyet', renk: 'gold',
        veri: seri.map(function (x) { return { x: x.gun, y: x.cost }; }) }],
      alan: true, bicim: 'para', etiket: 'Günlük maliyet'
    });

    var ozellikler = Object.keys(byFeature).sort(function (x, y) {
      return (Number(byFeature[y].estCostUsd) || 0) - (Number(byFeature[x].estCostUsd) || 0);
    });
    g.cubuk(alan.querySelector('#g-kul-ozellik'), {
      etiketler: ozellikler.map(ozellikAdi),
      degerler: ozellikler.map(function (k) { return Number(byFeature[k].estCostUsd) || 0; }),
      yatay: true, bicim: 'para', enCok: 10, etiket: 'Özellik başına maliyet'
    });

    var modeller = Object.keys(byModel);
    var modelMaliyetVar = modeller.some(function (m) { return (Number(byModel[m].estCostUsd) || 0) > 0; });
    g.halka(alan.querySelector('#g-kul-model'), {
      dilimler: modeller.map(function (m) {
        return { ad: m, deger: modelMaliyetVar ? (Number(byModel[m].estCostUsd) || 0)
                                               : (Number(byModel[m].calls) || 0) };
      }),
      bicim: modelMaliyetVar ? 'para' : 'sayi',
      merkezAlt: modelMaliyetVar ? 'maliyet' : 'çağrı', etiket: 'Model kırılımı'
    });

    var birimVar = ozellikler.some(function (k) {
      return (Number(byFeature[k].promptTokens) || 0) + (Number(byFeature[k].outputTokens) || 0) > 0;
    });
    g.yigin(alan.querySelector('#g-kul-birim'), {
      etiketler: birimVar ? ozellikler.map(ozellikAdi) : [],
      seriler: [
        { ad: 'Girdi', renk: 'lilac', veri: ozellikler.map(function (k) { return Number(byFeature[k].promptTokens) || 0; }) },
        { ad: 'Çıktı', renk: 'gold', veri: ozellikler.map(function (k) { return Number(byFeature[k].outputTokens) || 0; }) }
      ],
      bicim: 'sayi', etiket: 'Özellik başına girdi ve çıktı birimi',
      bosMetin: 'Birim kırılımı özette yok — ilk toplamayla dolar'
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
      bosMetin: 'Özette kullanıcı satırı yok — ilk toplamayla dolar.'
    });
    alan.querySelector('#kul-top').appendChild(vt.el);
    vt.guncelle(topUsers);

    /* Bedel tablosu */
    var bedeller = Object.keys(costs).map(function (k) {
      var kova = byFeature[k] || {};
      return { ad: k, etiket: ozellikAdi(k), kredi: Number(costs[k]) || 0,
               calls: Number(kova.calls) || 0 };
    });
    var bt = b.veriTablosu({
      kimlik: 'kul-bedel-tablo', etiket: 'Kredi bedelleri', yogunluk: 'sik',
      sutunlar: [
        { ad: 'etiket', baslik: 'Özellik', siralanir: true },
        { ad: 'kredi', baslik: 'Kredi', hizala: 'sag', siralanir: true },
        { ad: 'calls', baslik: 'Çağrı (' + gun + ' gün)', hizala: 'sag', siralanir: true }
      ],
      anahtar: function (s) { return s.ad; },
      siralama: { ad: 'kredi', yon: 'desc' },
      bosMetin: 'Bedel tablosu gelmedi.'
    });
    alan.querySelector('#kul-bedel').appendChild(bt.el);
    bt.guncelle(bedeller);
  }

  RY.kirintiSaglayici.kullanim = function () {
    return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Kullanım & AI' }];
  };
})();

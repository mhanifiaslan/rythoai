/* Gelir & Abonelik (AD19): rollup'tan gelir özeti (tarama YOK), ortam
   anahtarı, kohortlar, kullanıcı ekonomisi (top-200), ham olay akışı
   (imleçli), owner "Yeniden hesapla" ve CSV.

   Rota: #/gelir?env=PRODUCTION|SANDBOX&days=30|90 (varsayılan
   PRODUCTION / 30; başka değer varsayılana düşer). Eski #/ekonomi takma
   adı app.js'te buraya gelir.
   Uçlar (üçü paralel; her biri tek başına düşebilir — revenue VE stats
   birlikte düşerse görünüm hata durumuna geçer):
   - GET /api/v1/admin/revenue?days&env → {byDay:[{date, gross, refunds,
     count}] eskiden yeniye, byProduct/byStore/byCountry:{ad:{gross,
     count}}, eventCounts:{TÜR:n}, grossUsd, refundsUsd, mrrUsd,
     mrrByProduct, activeSubs (−1 = bilinmiyor), trialing, trialExpiring3d,
     cohorts:{AY:{signups, plus}}, asOf}
   - GET /api/v1/admin/stats?days → {days:[{date, subs:{active, mrrUsd}}]}
     yeniden eskiye (kıvılcımlar)
   - GET /api/v1/admin/economics?days&env → {users:[{uid, displayName,
     email, revenueUsd, sandboxUsd, storeCutUsd, aiCostUsd, calls,
     tokensSpent, partnerCostTry, partnerCostUsd, grossMarginUsd,
     marginUsd}], totals (+ partnerCostTry/Usd, grossMarginUsd,
     partnerDaysMissing, usdTryRate), coverage:{daysFound, oldest}}
     ⚠️ Ortak (affiliate) maliyeti −1 ise ÖLÇÜLMEMİŞTİR (0 DEĞİL) ve
     `marginUsd` de −1'dir. O durumda ekranda ölçülü olan
     `grossMarginUsd` yıldızla gösterilir: ortak maliyeti düşülmemiş ama
     ölçülmüş bir marjı "—" ile silmek de bir kayıptır.
   - GET /api/v1/admin/revenue/events?env&type&limit&cursor → {events,
     nextCursor}
   - POST /api/v1/admin/economics/recompute {from, to} (owner; 409 =
     zaten sürüyor)
   - GET /api/v1/admin/revenue/export.csv?days&env (owner)
   Sayılar rollup gününe kadar (asOf); "bugün" gecelik toplamayla gelir.
   Churn = (EXPIRATION + CANCELLATION) / aktif abone — dönem içi kaba
   oran, kohort bazlı değil. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  var ENVLER = ['PRODUCTION', 'SANDBOX'];
  var GUNLER = [30, 90];
  var OLAY_SAYFA = 50;
  var OLAY_TURLERI = ['INITIAL_PURCHASE', 'RENEWAL', 'CANCELLATION', 'EXPIRATION',
                      'BILLING_ISSUE', 'REFUND', 'TRIAL_STARTED', 'TRIAL_CONVERTED'];
  var OLAY_ROZET = { INITIAL_PURCHASE: 'aktif', RENEWAL: 'aktif', TRIAL_CONVERTED: 'altin', TRIAL_STARTED: 'trial',
                     CANCELLATION: 'uyari', EXPIRATION: 'notr', BILLING_ISSUE: 'hata', REFUND: 'hata' };

  /* =====================================================================
     Ortak (affiliate) edinme maliyeti — üç ayrı hâl, üç ayrı metin (P4)
     ===================================================================== */

  /* Uç ortak alanlarını HİÇ gönderiyor mu?

     Hosting backend'den BAĞIMSIZ dağıtılıyor (`firebase deploy --only
     hosting` vs `infra/deploy-backend.ps1`), yani paneli önce yayınlamak
     tek satırlık bir sıra hatasıdır ve o hâlde alan HİÇ gelmez. Alanın
     YOKLUĞU ile "ölçüldü ama bilinmiyor" (−1) aynı şey DEĞİL: birincide
     sunucunun marjı iki terimlidir ve o marj ÖLÇÜLMÜŞTÜR. Ayırmazsak
     `Number(undefined)` NaN olur, NaN >= 0 yanlıştır ve panel her satır
     için hiç yapılmamış bir okumanın teşhisini uydurur (Kullanıcı
     360'taki `ortakAlaniVar` ile aynı gerekçe). */
  function ortakAlaniVar(x) {
    return !!x && x.partnerCostUsd != null && x.grossMarginUsd != null;
  }

  function ortakOlculdu(x) {
    return ortakAlaniVar(x) && Number(x.partnerCostUsd) >= 0;
  }

  /* Ekranda gösterilecek marj. Ortak maliyeti ölçülüyse sunucunun ÜÇ
     terimli marjı; ölçülmüyorsa ortak maliyeti DÜŞÜLMEMİŞ ama ölçülü olan
     iki terimli sayı (yeni uçta `grossMarginUsd`, eski uçta `marginUsd` —
     ikisi de aynı hesap). Sayıyı "—" ile silmiyoruz: ölçülmüş bir marjı
     yok etmek de bir kayıptır; eksikliği yıldız ve bant söylüyor. */
  function gosterilenMarj(x) {
    if (ortakOlculdu(x)) return Number(x.marginUsd);
    return Number(ortakAlaniVar(x) ? x.grossMarginUsd : x.marginUsd);
  }

  /* `b.para` −1'i "bilinmiyor" sayıp "—" basıyor (deponun sentinel
     doktrini) ama bir marj GERÇEKTEN −$1,00 olabilir: geliri olmayan,
     $1,00 AI maliyeti biriktirmiş bir satır tam bunu verir. "—" basmak
     ölçülmüş bir zararı "bilinmiyor" adıyla sunmak olurdu — ters yönden
     aynı kusur. Bu yüzden ÖLÇÜLMÜŞ olduğu bilinen her tutar buradan
     geçer: yalnız satır marjı değil, toplamlardaki "ortak öncesi marj"
     da (o da her zaman ölçülüdür). */
  function olculmusPara(b, v) {
    if (Number(v) === -1) return '−' + b.para(1);
    return b.para(v);
  }

  /* `gosterilenMarj` yalnız ölçülmüş terimlerden gelen sayıyı döndürdüğü
     için buradaki −1 her zaman gerçek bir −1'dir. */
  function marjMetni(b, x) {
    return olculmusPara(b, gosterilenMarj(x));
  }

  function marjHucresi(b, x) {
    var yildiz = ortakOlculdu(x) ? ''
      : '<sup title="Ortak edinme maliyeti düşülmedi">*</sup>';
    return '<b class="' + (gosterilenMarj(x) < 0 ? 'metin-madder' : 'metin-celadon') +
      '">' + b.e(marjMetni(b, x)) + yildiz + '</b>';
  }

  /* Ortak maliyeti hücresi. Sıfır ile "ölçülmedi" AYNI işaretle
     gösterilemez: çıplak "—" sıfır gibi okunur ve "ortak maliyeti yoktu"
     ölçülmemiş bir iddiadır. Kur yoksa ₺ tutar yine dürüsttür — ölçülen
     birim odur, dolar bir türetmedir. */
  function ortakHucresi(b, x, ayrintili) {
    if (!ortakAlaniVar(x)) return '<span class="dipnot">uçtan gelmiyor</span>';
    if (!ortakOlculdu(x)) {
      return Number(x.partnerCostTry) >= 0
        ? '<span class="dipnot">' + b.e(b.para(x.partnerCostTry, '₺')) + ' · kur yok</span>'
        : '<span class="dipnot">ölçülmedi</span>';
    }
    if (!Number(x.partnerCostUsd)) return '<span class="dipnot">—</span>';
    return '−' + b.e(b.para(x.partnerCostUsd)) +
      (ayrintili ? ' <span class="dipnot">= ' + b.e(b.para(x.partnerCostTry, '₺')) + '</span>' : '');
  }
  var OLAY_ADI = { INITIAL_PURCHASE: 'İlk satın alma', RENEWAL: 'Yenileme', CANCELLATION: 'İptal',
                   EXPIRATION: 'Süre doldu', BILLING_ISSUE: 'Fatura sorunu', REFUND: 'İade',
                   TRIAL_STARTED: 'Deneme başladı', TRIAL_CONVERTED: 'Deneme → ödeme' };
  var MAGAZA_ADI = { PLAY_STORE: 'Google Play', APP_STORE: 'App Store', MAC_APP_STORE: 'Mac App Store',
                     STRIPE: 'Stripe', PROMOTIONAL: 'Promosyon', AMAZON: 'Amazon', '-': 'Bilinmiyor' };
  function magazaAdi(k) { return MAGAZA_ADI[k] || String(k || '—'); }
  function olayAdi(k) { return OLAY_ADI[k] || String(k || '?'); }

  function hataToast(h) {
    var m = RY.hataMetni(h);
    if (m) RY.b.toast(m, 'hata');
  }

  function paramOku(params) {
    params = params || {};
    var env = String(params.env || '').toUpperCase();
    var days = Number(params.days);
    return { env: ENVLER.indexOf(env) >= 0 ? env : 'PRODUCTION', days: GUNLER.indexOf(days) >= 0 ? days : 30 };
  }
  function rotaParam(sec) {
    var p = {};
    if (sec.env !== 'PRODUCTION') p.env = sec.env;
    if (sec.days !== 30) p.days = sec.days;
    return p;
  }

  /* Kırılım sözlüğü → sıralı [{ad, deger}] (gross'a göre), enCok+Diğer. */
  function kirilim(sozluk, enCok, adla) {
    var liste = Object.keys(sozluk || {}).map(function (k) {
      return { ad: adla ? adla(k) : k, deger: Number((sozluk[k] || {}).gross) || 0, sayi: Number((sozluk[k] || {}).count) || 0 };
    }).filter(function (x) { return x.deger > 0; }).sort(function (a, c) { return c.deger - a.deger; });
    if (enCok && liste.length > enCok) {
      var diger = liste.slice(enCok).reduce(function (t, x) { return t + x.deger; }, 0);
      liste = liste.slice(0, enCok).concat([{ ad: 'Diğer', deger: diger, renk: 'parchment-dim' }]);
    }
    return liste;
  }

  function kisiHucresi(b, u) {
    var ad = u.displayName || u.email || u.uid;
    var alt = u.displayName && u.email ? u.email : (ad !== u.uid ? u.uid : '');
    return '<span class="vt-kimlik"><span class="avatar" aria-hidden="true">' + b.e(b.basHarfler(u.displayName, u.email)) +
      '</span><div>' + b.e(ad) + (alt ? '<span>' + b.e(alt) + '</span>' : '') + '</div></span>';
  }

  /* ---------------- Owner eylemleri ---------------- */

  function yenidenHesaplaAc() {
    var b = RY.b;
    var bugun = new Date().toISOString().slice(0, 10);
    var dun = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
    var f = b.form({
      alanlar: [
        { ad: 'from', etiket: 'Başlangıç', tur: 'date', zorunlu: true, deger: dun, yardim: 'UTC gün · dahil' },
        { ad: 'to', etiket: 'Bitiş', tur: 'date', zorunlu: true, deger: dun, yardim: 'Dahil · en fazla 90 gün · bugünden ileri olamaz',
          dogrula: function (v, d) {
            var bas = d && d.from;
            if (!bas || !v) return null;
            if (v < bas) return 'Bitiş, başlangıçtan önce olamaz.';
            if (v > bugun) return 'Bitiş bugünden ileri olamaz.';
            var fark = (new Date(v) - new Date(bas)) / 86400000;
            return fark > 89 ? 'Aralık en fazla 90 gün.' : null;
          } }
      ],
      gonderMetin: 'Yeniden hesapla',
      iptal: { metin: 'Vazgeç', onTikla: function () { m.kapat(); } },
      onGonder: function (d) {
        var gun = Math.round((new Date(d.to) - new Date(d.from)) / 86400000) + 1;
        return b.onayla({
          baslik: gun + ' günü yeniden hesapla', onaylaMetin: 'Başlat', tehlike: gun > 30,
          mesaj: d.from + ' – ' + d.to + ' arası adminStats ve adminEconomics dokümanları canlı taramayla EZİLİR. ' +
            'İş sunucuda kilitli çalışır; ikinci istek 409 alır.',
          aciklama: 'Binlerce kullanıcıda gün başına saniyeler sürer; denetim izine yazılır.'
        }).then(function (r) {
          if (!r) { var h = new Error('iptal'); h.iptal = true; throw h; }
          var t = b.toast('Yeniden hesaplanıyor…', 'bilgi', { sure: 0 });
          return RY.post('/api/v1/admin/economics/recompute', { from: d.from, to: d.to }).then(function (res) {
            t.kapat();
            var s = (res && res.result) || {};
            b.toast('Yeniden hesaplandı: ' + d.from + ' – ' + d.to +
              (s.days != null ? ' · ' + b.sayi(s.days) + ' gün' : '') +
              (s.durationMs != null ? ' · ' + b.sayi(Math.round(s.durationMs / 1000)) + ' sn' : ''), 'basari', { sure: 8000 });
            m.kapat();
            var r2 = RY.rotaMevcut();
            if (r2.ad === 'gelir' || r2.ad === 'genel') RY.rotaYenile();
          }).catch(function (h) {
            t.kapat();
            if (h && h.durum === 409) b.toast('Yeniden hesaplama zaten sürüyor — bitince tekrar dene.', 'uyari', { sure: 7000 });
            throw h;
          });
        });
      }
    });
    var m = b.modal({ baslik: 'Rollup\'ı yeniden hesapla', icerik: f.el, genislik: 460 });
    m.ac();
  }
  RY.palet.eylemEkle({ ad: 'gelir-yeniden-hesapla', etiket: 'Rollup\'ı yeniden hesapla', aciklama: 'geçmiş günler · adminStats + adminEconomics',
    ikon: 'yenile', rol: 'owner', calistir: yenidenHesaplaAc });

  function csvIndir(sec) {
    var b = RY.b;
    var gun = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    var t = b.toast('CSV hazırlanıyor…', 'bilgi', { sure: 0 });
    return RY.indir('/api/v1/admin/revenue/export.csv' + RY.sorguDizesi({ days: sec.days, env: sec.env }),
      'rytho-gelir-' + sec.env.toLowerCase() + '-' + sec.days + 'g-' + gun + '.csv')
      .then(function (r) {
        t.kapat();
        b.toast('CSV indirildi' + (r && r.boyut ? ' · ' + b.sayi(Math.round(r.boyut / 1024)) + ' KB' : ''), 'basari');
      }).catch(function (h) { t.kapat(); hataToast(h); });
  }
  RY.palet.eylemEkle({ ad: 'gelir-csv', etiket: 'Gelir CSV\'si indir', aciklama: 'geçerli ortam ve dönem',
    ikon: 'indir', rol: 'owner', calistir: function () {
      var r = RY.rotaMevcut();
      return csvIndir(paramOku(r.ad === 'gelir' ? r.params : {}));
    } });

  /* ---------------- Olay akışı ---------------- */

  function olaylarKur(kap, sec) {
    var b = RY.b;
    var tur = '', imlec = null, denetleyici = null;
    kap.innerHTML =
      '<span class="cip-grup" role="group" aria-label="Olay türü" id="gelir-olay-tur">' +
      '<button type="button" class="adm-cip" data-tur="" aria-pressed="true">Tümü</button>' +
      OLAY_TURLERI.map(function (t) {
        return '<button type="button" class="adm-cip" data-tur="' + t + '" aria-pressed="false">' + b.e(olayAdi(t)) + '</button>';
      }).join('') + '</span>' +
      '<div id="gelir-olay-tablo"></div>';

    var vt = b.veriTablosu({
      kimlik: 'gelir-olay-vt', etiket: 'Gelir olayları', yogunluk: 'sik',
      sutunlar: [
        { ad: 'at', baslik: 'Zaman', bicim: function (o) {
          return '<span class="mono" title="' + b.e(b.tarih(o.at, true)) + '">' + b.e(b.tarih(o.at, true)) + '</span>';
        } },
        { ad: 'eventType', baslik: 'Tür', bicim: function (o) {
          var t = String(o.eventType || '?');
          return b.rozet(olayAdi(t), OLAY_ROZET[t] || 'notr') + (o.monetary === false ? ' <span class="dipnot">parasız</span>' : '');
        } },
        { ad: 'uid', baslik: 'Kullanıcı', bicim: function (o) {
          return o.uid ? '<a class="mono" href="' + b.e(RY.rotaBagi('kullanicilar', [o.uid])) + '">' + b.e(String(o.uid).slice(0, 12)) + '…</a>' : '—';
        } },
        { ad: 'productId', baslik: 'Ürün', bicim: function (o) { return '<span class="mono">' + b.e(o.productId || '—') + '</span>'; } },
        { ad: 'store', baslik: 'Mağaza', bicim: function (o) { return b.e(magazaAdi(o.store)); } },
        { ad: 'price', baslik: 'Tutar', hizala: 'sag', bicim: function (o) {
          var f = Number(o.price) || 0;
          if (!f) return '<span class="dipnot">—</span>';
          return '<span class="mono">' + b.e((o.eventType === 'REFUND' ? '−' : '') + b.para(Math.abs(f))) + '</span>' +
            (o.currency && o.currency !== 'USD' ? ' <span class="dipnot">' + b.e(o.currency) + '</span>' : '');
        } },
        { ad: 'countryCode', baslik: 'Ülke', bicim: function (o) { return '<span class="mono">' + b.e(o.countryCode || '—') + '</span>'; } },
        { ad: 'periodType', baslik: 'Dönem', bicim: function (o) { return b.e(o.periodType || '—'); } }
      ],
      anahtar: function (o) { return o.id; },
      satirSinif: function (o) { return o.eventType === 'REFUND' || o.eventType === 'BILLING_ISSUE' ? 'durum-hata' : ''; },
      onSirala: function () { /* sunucu sıralı (at DESC) */ },
      bosMetin: 'Bu ortamda / türde olay yok.',
      onTekrar: function () { yukle(false); }
    });
    kap.querySelector('#gelir-olay-tablo').appendChild(vt.el);

    function yukle(devam) {
      if (!devam) { vt.durum('yukleniyor'); imlec = null; }
      if (denetleyici) denetleyici.abort();
      denetleyici = new AbortController();
      var bu = denetleyici;
      return RY.sorgu('/api/v1/admin/revenue/events',
        { env: sec.env, type: tur || null, limit: OLAY_SAYFA, cursor: devam ? imlec : null }, { sinyal: bu.signal })
        .then(function (res) {
          if (bu.signal.aborted) return;
          var olaylar = Array.isArray(res && res.events) ? res.events : [];
          imlec = (res && res.nextCursor) || null;
          var sayfa = { daha: !!imlec, onDaha: function () { return yukle(true); } };
          if (devam) vt.ekle(olaylar, sayfa); else vt.guncelle(olaylar, sayfa);
        }).catch(function (h) {
          if (h && h.iptal) return;
          if (devam) hataToast(h); else vt.durum('hata', RY.hataMetni(h));
        });
    }
    kap.querySelector('#gelir-olay-tur').addEventListener('click', function (ev) {
      var d = ev.target.closest('.adm-cip');
      if (!d) return;
      tur = d.getAttribute('data-tur') || '';
      this.querySelectorAll('.adm-cip').forEach(function (c) { c.setAttribute('aria-pressed', c === d ? 'true' : 'false'); });
      yukle(false);
    });
    yukle(false);
  }

  /* ---------------- Görünüm ---------------- */

  RY.gorunumler.gelir = async function (icerik, args, params) {
    var b = RY.b;
    var sec = paramOku(params);
    var sahip = RY.sahipMi();

    var hepsi = await Promise.all([
      RY.sorgu('/api/v1/admin/revenue', { days: sec.days, env: sec.env }).catch(function (h) { return { hata: h }; }),
      RY.sorgu('/api/v1/admin/stats', { days: sec.days }).catch(function () { return null; }),
      RY.sorgu('/api/v1/admin/economics', { days: sec.days, env: sec.env }).catch(function () { return null; })
    ]);
    var rev = hepsi[0] && !hepsi[0].hata ? hepsi[0] : null;
    var stats = hepsi[1], eko = hepsi[2];
    if (!rev && !stats) throw hepsi[0].hata;

    var gunler = ((stats && stats.days) || []).slice().reverse();  // eskiden yeniye
    var byDay = (rev && rev.byDay) || [];
    var sayaclar = (rev && rev.eventCounts) || {};
    function olay(t) { return Number(sayaclar[t]) || 0; }

    var aktif = rev && rev.activeSubs >= 0 ? rev.activeSubs : null;
    var churnPay = olay('EXPIRATION') + olay('CANCELLATION');
    var churn = aktif ? churnPay / aktif * 100 : null;
    var denemeBas = olay('TRIAL_STARTED'), denemeDon = olay('TRIAL_CONVERTED');
    var donusum = denemeBas ? denemeDon / denemeBas * 100 : null;
    var brut = rev ? Number(rev.grossUsd) || 0 : null;
    var iade = rev ? Number(rev.refundsUsd) || 0 : null;
    var mrrUrun = (rev && rev.mrrByProduct) || {};
    var mrrUrunMetin = Object.keys(mrrUrun).sort(function (x, y) { return (Number(mrrUrun[y]) || 0) - (Number(mrrUrun[x]) || 0); })
      .slice(0, 2).map(function (k) { return k + ' ' + b.para(mrrUrun[k]); }).join(' · ');

    /* ---- Başlık ve çipler ---- */
    var eylemler = sahip
      ? '<button type="button" class="buton ikincil" id="gelir-csv">' + b.ik('indir', 16) + 'CSV</button>' +
        '<button type="button" class="buton ikincil" id="gelir-hesapla">' + b.ik('yenile', 16) + 'Yeniden hesapla</button>'
      : '';
    var cipler = '<div class="suzgec" id="gelir-cipler">' +
      '<span class="cip-grup" role="group" aria-label="Ortam"><span class="grup-ad" aria-hidden="true">Ortam</span>' +
      '<button type="button" class="adm-cip" data-env="PRODUCTION" aria-pressed="' + (sec.env === 'PRODUCTION' ? 'true' : 'false') + '">Üretim</button>' +
      '<button type="button" class="adm-cip" data-env="SANDBOX" aria-pressed="' + (sec.env === 'SANDBOX' ? 'true' : 'false') + '">Test alımlarını göster</button></span>' +
      '<span class="cip-grup" role="group" aria-label="Dönem"><span class="grup-ad" aria-hidden="true">Dönem</span>' +
      GUNLER.map(function (g) {
        return '<button type="button" class="adm-cip altin" data-gun="' + g + '" aria-pressed="' + (g === sec.days ? 'true' : 'false') + '">' + g + ' gün</button>';
      }).join('') + '</span></div>';

    var bantlar = '';
    if (!rev) bantlar += b.bant('<b>Gelir özeti alınamadı</b> — ' + b.e(RY.hataMetni(hepsi[0].hata)) + '. Kıvılcımlar ve kohortlar rollup\'tan.', 'hata', { html: true });
    if (sec.env === 'SANDBOX') bantlar += b.bant('<b>Test ortamı</b> — SANDBOX alımları gerçek gelir değildir; işletme sayılarına girmez.', 'bilgi', { html: true });
    if (eko && eko.coverage && Number(eko.coverage.daysFound) < sec.days) {
      bantlar += b.bant('<b>Eksik rollup</b> — ' + sec.days + ' günün yalnız ' + b.e(b.sayi(Number(eko.coverage.daysFound) || 0)) +
        ' günü için adminEconomics dokümanı var' + (eko.coverage.oldest ? ' (en eski ' + b.e(b.tarih(eko.coverage.oldest)) + ')' : '') +
        '. Kullanıcı ekonomisi eksik günleri saymaz' + (sahip ? '; "Yeniden hesapla" ile doldur.' : '.'), 'uyari', { html: true });
    }
    /* Ortak maliyetinin üç eksik hâli üç ayrı bant: teşhis farklı, yapılacak
       iş de farklı. Tek bant yazmak sahibi yanlış yere baktırırdı. */
    var ekoT = (eko && eko.totals) || null;
    if (ekoT && !ortakAlaniVar(ekoT)) {
      bantlar += b.bant('<b>Ortak maliyeti bu uçtan gelmiyor</b> — backend, paneldeki bu sürümden eski ' +
        '(<code>partnerCostUsd</code> alanı yok). Marj İKİ terimli: ortak (affiliate) edinme maliyeti ' +
        'DÜŞÜLMEMİŞ, yani atıflı abonelerde olduğundan yüksek. infra/deploy-backend.ps1 ile düzelir.',
        'uyari', { html: true });
    } else if (ekoT && Number(ekoT.partnerDaysMissing) > 0) {
      /* İKİ neden aynı sayaca düşüyor (`partnerDaysMissing`): alanı hiç
         taşımayan eski gün ve o günün sorgusu düşmüş gün (`partnerTry` =
         −1). Uç ikisini ayırmadığı için bant da AYIRMAZ; yalnız birini
         sebep diye yazmak, sahibi olmayan bir gerekçeye inandırırdı.
         Yapılacak iş ikisinde de aynı: o günleri yeniden yaz. */
      bantlar += b.bant('<b>Ortak maliyeti ölçülmemiş</b> — ' + b.e(b.sayi(Number(ekoT.partnerDaysMissing))) +
        ' günün adminEconomics dokümanı ortak edinme maliyetini taşımıyor — o günler bu ölçüm ' +
        'eklenmeden önce yazıldı ya da o günün sorgusu düştü. Eksik günde hangi kullanıcının ' +
        'ödülünün kayıp olduğu bilinmediği için marj ' +
        '<b>yıldızlı</b> gösteriliyor: ortak maliyeti düşülmemiş ama ölçülmüş sayı' +
        (sahip ? '. "Yeniden hesapla" o günleri yeniden yazar, alan kendiliğinden dolar.' : '.'),
        'uyari', { html: true });
    } else if (ekoT && !ortakOlculdu(ekoT)) {
      bantlar += b.bant('<b>Kur ayarlı değil</b> — ortak edinme maliyeti ₺ olarak ölçüldü (' +
        b.e(b.para(ekoT.partnerCostTry, '₺')) + ') ama dolara çevrilemedi (<code>RYTHO_USD_TRY</code>). ' +
        'Marj bu yüzden hesaplanamıyor; yıldızlı sayı ortak maliyeti düşülmemiş marjdır.',
        'uyari', { html: true });
    }

    /* ---- KPI ---- */
    var kpiler = '<section class="izgara-kpi" aria-label="Gelir özeti">' +
      b.istatistikKarti({ ad: 'Brüt gelir', deger: rev ? b.para(brut) : '—', altin: true,
        alt: rev ? b.sayi(byDay.reduce(function (t, g) { return t + (Number(g.count) || 0); }, 0)) + ' parasal olay · ' + sec.days + ' gün' : '—',
        kivilcim: byDay.map(function (g) { return Number(g.gross) || 0; }), renk: 'gold' }) +
      b.istatistikKarti({ ad: 'MRR', deger: rev ? b.para(rev.mrrUsd) : '—', altin: true,
        alt: mrrUrunMetin || 'aktif abone × birim fiyat', kivilcim: gunler.map(function (g) { return Number((g.subs || {}).mrrUsd) || 0; }), renk: 'gold' }) +
      b.istatistikKarti({ ad: 'Aktif abone', deger: aktif != null ? b.sayi(aktif) : '—',
        alt: rev && rev.asOf ? 'rollup ' + b.tarih(rev.asOf) : 'rollup yok',
        kivilcim: gunler.map(function (g) { var v = (g.subs || {}).active; return v >= 0 ? Number(v) || 0 : 0; }) }) +
      b.istatistikKarti({ ad: 'Deneme', deger: rev ? b.sayi(rev.trialing) : '—',
        alt: rev && rev.trialExpiring3d ? b.sayi(rev.trialExpiring3d) + ' tanesi 3 gün içinde bitiyor' : 'mağaza denemesi', renk: 'lilac' }) +
      b.istatistikKarti({ ad: 'Churn', deger: churn != null ? b.yuzde(churn) : '—',
        alt: b.sayi(olay('EXPIRATION')) + ' süre doldu · ' + b.sayi(olay('CANCELLATION')) + ' iptal', renk: 'madder' }) +
      b.istatistikKarti({ ad: 'Deneme dönüşümü', deger: donusum != null ? b.yuzde(donusum) : '—',
        alt: b.sayi(denemeDon) + ' / ' + b.sayi(denemeBas) + ' deneme' }) +
      b.istatistikKarti({ ad: 'İadeler', deger: rev ? b.para(iade) : '—',
        alt: b.sayi(olay('REFUND')) + ' iade · ' + b.sayi(olay('BILLING_ISSUE')) + ' fatura sorunu',
        kivilcim: byDay.map(function (g) { return Number(g.refunds) || 0; }), renk: 'madder' }) +
      '</section>';

    /* ---- Grafik ve tablolar ---- */
    var grafikler =
      '<div class="izgara-2">' +
      b.modul('Günlük gelir', '<div class="grafik-kap"><canvas id="g-gelir-gun" class="grafik" aria-label="Günlük brüt gelir ve iade"></canvas></div>',
        '', { alt: sec.days + ' gün · brüt ve iade · $' }) +
      b.modul('Ürün kırılımı', '<div class="grafik-kap"><canvas id="g-gelir-urun" class="grafik" aria-label="Ürün başına brüt gelir"></canvas></div>',
        '', { alt: 'brüt · ilk 8' }) +
      '</div>' +
      '<div class="izgara-2">' +
      b.modul('Mağaza', '<div class="halka-kap"><div class="grafik-kap"><canvas id="g-gelir-magaza" class="grafik" aria-label="Mağaza payı"></canvas></div></div>',
        '', { alt: 'brüt payı' }) +
      b.modul('Ülke', '<div class="halka-kap"><div class="grafik-kap"><canvas id="g-gelir-ulke" class="grafik" aria-label="Ülke payı"></canvas></div></div>',
        '', { alt: 'brüt payı · ilk 8 + diğer' }) +
      '</div>';

    var kohortlar = (rev && rev.cohorts) || {};
    var aylar = Object.keys(kohortlar).sort().reverse().slice(0, 12);
    var kohortHtml = aylar.length
      ? '<div class="tablo-sarici"><table class="tablo"><thead><tr><th scope="col">Kayıt ayı</th><th scope="col">Kayıt</th>' +
        '<th scope="col">Rytho+ (bugün)</th><th scope="col">Dönüşüm</th></tr></thead><tbody>' + aylar.map(function (ay) {
          var k = kohortlar[ay] || {};
          var kayit = Number(k.signups) || 0, plus = Number(k.plus) || 0;
          return '<tr><th scope="row" class="mono">' + b.e(ay) + '</th><td class="sayi">' + b.e(b.sayi(kayit)) + '</td>' +
            '<td class="sayi">' + b.e(b.sayi(plus)) + '</td><td class="sayi">' + b.e(kayit ? b.yuzde(plus / kayit * 100) : '—') + '</td></tr>';
        }).join('') + '</tbody></table></div>'
      : b.bosDurum('Kohort verisi rollup\'ta yok — ilk toplamayla dolar.');

    var t = (eko && eko.totals) || null;
    var ekoHtml = t
      ? '<dl class="alan-liste">' +
        '<dt>Üretim geliri</dt><dd>' + b.e(b.para(t.revenueUsd)) + '</dd>' +
        '<dt>Sandbox geliri</dt><dd>' + b.e(b.para(t.sandboxUsd)) + '</dd>' +
        '<dt>Mağaza payı (~%' + Math.round((Number(t.storeCutRate) || 0.15) * 100) + ')</dt><dd>−' + b.e(b.para(t.storeCutUsd)) + '</dd>' +
        '<dt>AI maliyeti</dt><dd>−' + b.e(b.para(t.aiCostUsd)) + '</dd>' +
        '<dt>· paylaşımlı (kullanıcısız)</dt><dd>' + b.e(b.para(t.sharedAiCostUsd)) + '</dd>' +
        '<dt>Ortak edinme maliyeti</dt><dd>' + ortakHucresi(b, t, true) + '</dd>' +
        /* "Marj (ortak öncesi)" satırı yalnız uç o sayıyı GÖNDERİYORSA
           çizilir. Alan yokken `b.para(undefined)` "—" basardı, oysa hemen
           altındaki yıldızlı "Tahmini marj" tam o ölçülmüş sayının
           kendisidir: aynı büyüklük bir satırda "bilinmiyor", bir satırda
           değer olarak görünürdü. */
        (ortakAlaniVar(t)
          ? '<dt>Marj (ortak öncesi)</dt><dd>' + b.e(olculmusPara(b, t.grossMarginUsd)) + '</dd>'
          : '') +
        '<dt>Tahmini marj</dt><dd>' + marjHucresi(b, t) + '</dd>' +
        '<dt>Çağrı · harcanan kredi</dt><dd>' + b.e(b.sayi(t.calls)) + ' · ' + b.e(b.sayi(t.tokensSpent)) + '</dd>' +
        '<dt>Sayılan kullanıcı</dt><dd>' + b.e(b.sayi(t.usersCounted)) + '</dd></dl>' +
        /* Formül cümlesi GÖSTERİLEN marjı tarif eder, sunucunun ideal
           formülünü değil: ortak maliyeti düşülmemişken "− ortak edinme
           maliyeti" yazmak yapılmamış bir hesabı beyan etmek olurdu ve
           ekrandaki yıldızın tersini söylerdi. Aynı gerekçe
           `kullanicilar.js` `marjCumlesi`nde de var; orada terim yalnız
           `ucGondermiyor` iken çıkıyor çünkü 360 ölçülemeyen marjı "—"
           basıyor, burada ise ölçülü (ortak öncesi) sayı yıldızla
           GÖSTERİLİYOR — yani cümlenin yanlış olabileceği hâl bir fazla.
           Kur cümlesi de ancak
           kur BİLİNİYORSA yazılır — ödülü sıfır olan pencerede kur
           okunamamış olabilir ve "kur — ile türetilir" bir şey söylemez. */
        '<p class="dipnot">Marj = seçili ortam geliri × (1 − mağaza payı) − AI maliyeti' +
        (ortakOlculdu(t)
          ? ' − ortak edinme maliyeti; sabit giderler hariç.' +
            (Number(t.usdTryRate) > 0
              ? ' Ortak ödülü ₺ ölçülür, dolar karşılığı kur ' +
                b.e(b.sayi(t.usdTryRate)) + ' ile türetilir.'
              : '')
          : '; sabit giderler hariç. Yıldızlı sayı ortak edinme maliyeti ' +
            'DÜŞÜLMEMİŞ marjdır; nedenini yukarıdaki bant söylüyor.') + '</p>'
      : b.bosDurum('Ekonomi rollup\'ı alınamadı.', { ikon: 'gelir' });

    var tablolar =
      '<div class="izgara-2">' +
      b.modul('Kayıt kohortları', kohortHtml, '', { alt: 'aya göre kayıt · bugün Rytho+ olanlar' }) +
      b.modul('Ekonomi toplamları', ekoHtml, '', { alt: sec.days + ' gün · ' + sec.env }) +
      '</div>' +
      b.modul('Kullanıcı ekonomisi', '<div id="gelir-eko-tablo"></div>', b.etiket('adminEconomics'),
        { alt: 'marja göre ilk 200 · satır → 360' }) +
      b.modul('Olay akışı', '<div id="gelir-olaylar"></div>', b.etiket('revenueEvents'),
        { alt: sec.env + ' · at DESC · imleçli · parasız olaylar dahil' }) +
      '<p class="dipnot">Gelir yalnız rollup gününe kadar (' + b.e(rev && rev.asOf ? b.tarih(rev.asOf) : '—') + '); ' +
      'churn dönem içi kaba orandır. Fiyatlar RevenueCat USD; mağaza payı sabit ~%15 varsayımı.</p>';

    icerik.innerHTML =
      b.sayfaBaslik({ baslik: 'Gelir & Abonelik', alt: 'Son ' + sec.days + ' gün · ' + (sec.env === 'PRODUCTION' ? 'üretim' : 'SANDBOX') +
        (rev && rev.asOf ? ' · rollup ' + b.tarih(rev.asOf) : ''), eylemlerHtml: eylemler }) +
      cipler + bantlar + kpiler + grafikler + tablolar;

    /* ---- Çipler ---- */
    icerik.querySelector('#gelir-cipler').addEventListener('click', function (ev) {
      var d = ev.target.closest('.adm-cip');
      if (!d) return;
      var yeni = { env: sec.env, days: sec.days };
      if (d.hasAttribute('data-env')) yeni.env = d.getAttribute('data-env');
      if (d.hasAttribute('data-gun')) yeni.days = Number(d.getAttribute('data-gun'));
      if (yeni.env === sec.env && yeni.days === sec.days) return;
      RY.rotaYaz('gelir', [], rotaParam(yeni));
    });

    /* ---- Grafikler ---- */
    var g = RY.grafik;
    g.cizgi(icerik.querySelector('#g-gelir-gun'), {
      seriler: [
        { ad: 'Brüt', renk: 'gold', veri: byDay.map(function (x) { return { x: x.date, y: Number(x.gross) || 0 }; }) },
        { ad: 'İade', renk: 'madder', veri: byDay.map(function (x) { return { x: x.date, y: Number(x.refunds) || 0 }; }) }
      ],
      alan: true, bicim: 'para', etiket: 'Günlük gelir', bosMetin: 'Bu dönemde parasal olay yok'
    });
    var urunler = kirilim((rev && rev.byProduct) || {}, 8);
    g.cubuk(icerik.querySelector('#g-gelir-urun'), {
      etiketler: urunler.map(function (u) { return u.ad; }), degerler: urunler.map(function (u) { return u.deger; }),
      yatay: true, bicim: 'para', enCok: 8, etiket: 'Ürün başına brüt', bosMetin: 'Ürün kırılımı yok'
    });
    g.halka(icerik.querySelector('#g-gelir-magaza'), {
      dilimler: kirilim((rev && rev.byStore) || {}, 6, magazaAdi), bicim: 'para', merkezAlt: 'brüt', etiket: 'Mağaza payı',
      bosMetin: 'Mağaza kırılımı yok'
    });
    g.halka(icerik.querySelector('#g-gelir-ulke'), {
      dilimler: kirilim((rev && rev.byCountry) || {}, 8), bicim: 'para', merkezAlt: 'brüt', etiket: 'Ülke payı',
      bosMetin: 'Ülke kırılımı yok'
    });

    /* ---- Kullanıcı ekonomisi ---- */
    var ekoVt = b.veriTablosu({
      kimlik: 'gelir-eko-vt', etiket: 'Kullanıcı ekonomisi', yogunluk: 'sik',
      sutunlar: [
        { ad: 'ad', baslik: 'Kullanıcı', deger: function (u) { return u.displayName || u.email || u.uid; },
          bicim: function (u) { return kisiHucresi(b, u); } },
        { ad: 'revenueUsd', baslik: 'Üretim geliri', hizala: 'sag', siralanir: true, bicim: function (u) { return b.e(b.para(u.revenueUsd)); } },
        { ad: 'sandboxUsd', baslik: 'Sandbox', hizala: 'sag', siralanir: true, bicim: function (u) {
          return Number(u.sandboxUsd) ? b.e(b.para(u.sandboxUsd)) : '<span class="dipnot">—</span>'; } },
        { ad: 'storeCutUsd', baslik: 'Mağaza payı', hizala: 'sag', bicim: function (u) { return Number(u.storeCutUsd) ? '−' + b.e(b.para(u.storeCutUsd)) : '—'; } },
        { ad: 'aiCostUsd', baslik: 'AI maliyeti', hizala: 'sag', siralanir: true, bicim: function (u) { return b.e(b.para(u.aiCostUsd)); } },
        { ad: 'partnerCostUsd', baslik: 'Ortak', hizala: 'sag', siralanir: true,
          bicim: function (u) { return ortakHucresi(b, u); } },
        { ad: 'calls', baslik: 'Çağrı', hizala: 'sag', siralanir: true },
        // Sıralama anahtarı GÖSTERİLEN marjdır. Ham `marginUsd`e
        // bakılsaydı ortak maliyeti ölçülmemiş pencerede her satır −1
        // olur, "Marj" başlığına basmak hiçbir şeyi kıpırdatmazdı — üstelik
        // başlık `aria-sort="ascending"` derken satırlar azalan dururdu.
        { ad: 'marginUsd', baslik: 'Marj', hizala: 'sag', siralanir: true,
          deger: function (u) { return gosterilenMarj(u); },
          bicim: function (u) { return marjHucresi(b, u); } }
      ],
      anahtar: function (u) { return u.uid; },
      satirHref: function (u) { return RY.rotaBagi('kullanicilar', [u.uid]); },
      // Uyarı boyası GÖSTERİLEN marja bakar: ölçülmemiş ortak maliyeti
      // yüzünden −1 olan `marginUsd`e bakılsaydı kârlı satırlar da zararlı
      // görünürdü — hem de her satır, aynı anda.
      satirSinif: function (u) { return gosterilenMarj(u) < 0 ? 'durum-uyari' : ''; },
      siralama: { ad: 'marginUsd', yon: 'desc' },
      bosMetin: eko ? 'Bu dönemde kullanıcı satırı yok.' : 'Ekonomi rollup\'ı alınamadı.'
    });
    icerik.querySelector('#gelir-eko-tablo').appendChild(ekoVt.el);
    ekoVt.guncelle((eko && Array.isArray(eko.users)) ? eko.users : []);

    /* ---- Olaylar ---- */
    olaylarKur(icerik.querySelector('#gelir-olaylar'), sec);

    /* ---- Owner ---- */
    var csv = icerik.querySelector('#gelir-csv');
    if (csv) csv.addEventListener('click', function () { csvIndir(sec); });
    var hesapla = icerik.querySelector('#gelir-hesapla');
    if (hesapla) hesapla.addEventListener('click', yenidenHesaplaAc);
  };

  RY.kirintiSaglayici.gelir = function () {
    return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Gelir & Abonelik' }];
  };
})();

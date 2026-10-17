/* Gelir & Abonelik (AD19): saatlik özetten gelir (tarama YOK), ortam
   anahtarı, kohortlar, kullanıcı ekonomisi (top-200), ham olay akışı
   (imleçli), owner "Yeniden hesapla" ve CSV.

   Rota: #/gelir?env=PRODUCTION|SANDBOX&days=7|30|90&olay=TÜR (varsayılan
   PRODUCTION / 30 / tümü; başka değer varsayılana düşer). Süzgeçler adrese
   SESSİZ yazılır (geçmişe kayıt düşmez), değişince yalnız veri bölgesi
   yeniden çekilir. Eski #/ekonomi takma adı app.js'te buraya gelir.
   Uçlar (üçü paralel; her biri tek başına düşebilir — revenue VE stats
   birlikte düşerse veri bölgesi hata durumuna geçer):
   - GET /api/v1/admin/revenue?days(1..365)&env → {byDay:[{date, gross,
     refunds, count}] eskiden yeniye, byProduct/byStore/byCountry:{ad:
     {gross, count}}, eventCounts:{TÜR:n}, grossUsd, refundsUsd, mrrUsd,
     mrrByProduct, activeSubs (−1 = bilinmiyor), trialing, trialExpiring3d,
     cohorts:{AY:{signups, plus}}, asOf}
   - GET /api/v1/admin/stats?days → {days:[{date, generatedAt, subs,
     revenue:{byEnv:{ENV:{eventCounts}}}}]} yeniden eskiye (kıvılcımlar,
     tazelik, eksik gün ve öteki ortamın olay sayısı)
   - GET /api/v1/admin/economics?days(30|90)&env → {users:[…], totals
     (+ partnerCostTry/Usd, grossMarginUsd, partnerDaysMissing,
     usdTryRate), coverage:{daysFound, oldest}}
     ⚠️ Uç YALNIZ 30 ve 90 kabul ediyor (`_ECON_DAYS`). 7 gün seçiliyken
     ekonomi bölümü 30 gün çeker ve bunu başlığında açıkça söyler — 7
     günlük gelirin yanında sessizce 30 günlük marj durmasın.
     ⚠️ Ortak (affiliate) maliyeti −1 ise ÖLÇÜLMEMİŞTİR (0 DEĞİL) ve
     `marginUsd` de −1'dir. O durumda ekranda ölçülü olan
     `grossMarginUsd` yıldızla gösterilir: ortak maliyeti düşülmemiş ama
     ölçülmüş bir marjı "—" ile silmek de bir kayıptır.
   - GET /api/v1/admin/revenue/events?env&type&limit&cursor → {events,
     nextCursor} — dönem parametresi YOK; olay akışı tüm zamanlardır.
   - POST /api/v1/admin/economics/recompute {from, to} (owner; 409 =
     zaten sürüyor)
   - GET /api/v1/admin/revenue/export.csv?days&env (owner)

   Özet SAATLİK (Cloud Scheduler); bugünün geliri bir saat içinde görünür,
   "Yeniden hesapla"ya basmak gerekmez. Bant yalnız yanıt GERÇEKTEN eksik
   veri bildirdiğinde çıkar (özet 2 saatten eski, dönemde özeti olmayan
   gün, ortak maliyeti ölçülmemiş gün) ve neyin eksik olduğunu söyler.
   Kayıp oranı = (sona eren + iptal) / aktif abone — dönem içi kaba oran,
   kohort bazlı değil. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  var ENVLER = ['PRODUCTION', 'SANDBOX'];
  var GUNLER = [7, 30, 90];
  var VARSAYILAN_GUN = 30;
  var EKONOMI_GUNLERI = [30, 90];
  var OLAY_SAYFA = 50;
  var OLAY_TURLERI = ['INITIAL_PURCHASE', 'RENEWAL', 'NON_RENEWING_PURCHASE', 'TRIAL_STARTED',
                      'TRIAL_CONVERTED', 'CANCELLATION', 'UNCANCELLATION', 'EXPIRATION',
                      'BILLING_ISSUE', 'REFUND', 'PRODUCT_CHANGE', 'SUBSCRIPTION_EXTENDED'];
  var OLAY_ROZET = { INITIAL_PURCHASE: 'aktif', RENEWAL: 'aktif', TRIAL_CONVERTED: 'altin', TRIAL_STARTED: 'trial',
                     NON_RENEWING_PURCHASE: 'altin', UNCANCELLATION: 'aktif', SUBSCRIPTION_EXTENDED: 'aktif',
                     CANCELLATION: 'uyari', EXPIRATION: 'notr', BILLING_ISSUE: 'hata', REFUND: 'hata' };

  function S() { return RY.sozluk; }
  function magazaAdi(k) { return S().magazaAdi(k); }
  function olayAdi(k) { return S().olayAdi(k); }
  function ortamAdi(k) { return S().ortamAdi(k); }

  /* Ekonomi ucu 7'yi kabul etmiyor: en yakın izinli değer (30). */
  function ekonomiGunu(gun) {
    return EKONOMI_GUNLERI.indexOf(gun) >= 0 ? gun : EKONOMI_GUNLERI[0];
  }

  /* Ülke kodu ("TR") → "Türkiye". Tarayıcı bölge adlarını bilmiyorsa kod. */
  var bolgeAdlari = null;
  try { bolgeAdlari = new Intl.DisplayNames(['tr'], { type: 'region' }); } catch (yok) { bolgeAdlari = null; }
  function ulkeAdi(k) {
    if (!k || k === '-') return 'Bilinmiyor';
    try { return (bolgeAdlari && bolgeAdlari.of(String(k).toUpperCase())) || String(k); } catch (yok) { return String(k); }
  }

  /* Kohort ayı "2026-10" → "Eki 2026". */
  function ayAdi(ay) {
    var m = /^(\d{4})-(\d{2})$/.exec(String(ay || ''));
    if (!m) return String(ay || '—');
    return new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, 1))
      .toLocaleDateString('tr-TR', { month: 'short', year: 'numeric', timeZone: 'UTC' });
  }

  /* =====================================================================
     Ortak (affiliate) edinme maliyeti — üç ayrı hâl, üç ayrı metin (P4)
     ===================================================================== */

  /* Uç ortak alanlarını HİÇ gönderiyor mu?

     Hosting backend'den BAĞIMSIZ dağıtılıyor, yani paneli önce yayınlamak
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
    if (!ortakAlaniVar(x)) return '<span class="dipnot">sunucudan gelmiyor</span>';
    if (!ortakOlculdu(x)) {
      return Number(x.partnerCostTry) >= 0
        ? '<span class="dipnot">' + b.e(b.para(x.partnerCostTry, '₺')) + ' · kur yok</span>'
        : '<span class="dipnot">ölçülmedi</span>';
    }
    if (!Number(x.partnerCostUsd)) return '<span class="dipnot">—</span>';
    return '−' + b.e(b.para(x.partnerCostUsd)) +
      (ayrintili ? ' <span class="dipnot">= ' + b.e(b.para(x.partnerCostTry, '₺')) + '</span>' : '');
  }

  function hataToast(h) {
    var m = RY.hataMetni(h);
    if (m) RY.b.toast(m, 'hata');
  }

  function paramOku(params) {
    params = params || {};
    var env = String(params.env || '').toUpperCase();
    var days = Number(params.days);
    var olay = String(params.olay || '').toUpperCase();
    return { env: ENVLER.indexOf(env) >= 0 ? env : 'PRODUCTION',
             days: GUNLER.indexOf(days) >= 0 ? days : VARSAYILAN_GUN,
             olay: OLAY_TURLERI.indexOf(olay) >= 0 ? olay : '' };
  }
  function rotaParam(sec) {
    var p = {};
    if (sec.env !== 'PRODUCTION') p.env = sec.env;
    if (sec.days !== VARSAYILAN_GUN) p.days = sec.days;
    if (sec.olay) p.olay = sec.olay;
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

  /* Bir ortamın dönemdeki olay sayısı — stats günlerinden. Gelir ucu yalnız
     SEÇİLİ ortamı döndürüyor; "öteki ortamda kaç olay var" sorusunu ancak
     günlük özetin `byEnv` kovası cevaplar. */
  function ortamOlaySayisi(gunler, env) {
    return gunler.reduce(function (t, g) {
      var kova = (((g.revenue || {}).byEnv || {})[env]) || {};
      var sayaclar = kova.eventCounts || {};
      var n = Object.keys(sayaclar).reduce(function (s, k) { return s + (Number(sayaclar[k]) || 0); }, 0);
      return t + (n || Number(kova.count) || 0);
    }, 0);
  }

  /* Dönem içinde özeti OLMAYAN geçmiş günler. Takvim penceresi (backend
     `read_days`) eksik günü artık eksik gösteriyor; burada hangi günler
     olduğu bulunur. İlk kayıttan önceki günler eksik sayılmaz — o günlerde
     ürün yoktu, "eksik" demek yanlış olurdu. Bugün de sayılmaz: gece
     yarısından sonraki ilk saatlik koşuya kadar bugünün dokümanı henüz
     yazılmamış olabilir. */
  function eksikGunler(b, gunler, donemGun) {
    if (!gunler.length) return [];
    var var_ = {};
    gunler.forEach(function (g) { if (g.date) var_[g.date] = true; });
    var enEski = gunler.reduce(function (en, g) { return !en || g.date < en ? g.date : en; }, null);
    var eksik = [];
    for (var i = donemGun - 1; i >= 1; i--) {
      var gun = b.utcGun(i);
      if (gun < enEski) continue;
      if (!var_[gun]) eksik.push(gun);
    }
    return eksik;
  }

  /* ---------------- Owner eylemleri ---------------- */

  function yenidenHesaplaAc(onDeger) {
    var b = RY.b;
    var bugun = b.utcGun(0);
    var dun = b.utcGun(1);
    var ilk = (onDeger && onDeger.from) || dun, son = (onDeger && onDeger.to) || dun;
    var f = b.form({
      alanlar: [
        { ad: 'from', etiket: 'Başlangıç', tur: 'date', zorunlu: true, deger: ilk, yardim: 'Gün UTC\'ye göre · dahil' },
        { ad: 'to', etiket: 'Bitiş', tur: 'date', zorunlu: true, deger: son, yardim: 'Dahil · en fazla 90 gün · bugünden ileri olamaz',
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
        var aralik = b.tarih(d.from) + ' – ' + b.tarih(d.to);
        return b.onayla({
          baslik: gun + ' günü yeniden hesapla', onaylaMetin: 'Başlat', tehlike: gun > 30,
          mesaj: aralik + ' arasındaki günlerin istatistik ve ekonomi özeti canlı taramayla yeniden ' +
            'üretilir ve eskisinin YERİNE yazılır. İş sunucuda tek seferde bir kez çalışır; o sırada ' +
            'gelen ikinci istek "zaten sürüyor" yanıtı alır.',
          aciklama: 'Binlerce kullanıcıda gün başına saniyeler sürer; denetim izine yazılır.'
        }).then(function (r) {
          if (!r) { var h = new Error('iptal'); h.iptal = true; throw h; }
          var t = b.toast('Yeniden hesaplanıyor…', 'bilgi', { sure: 0 });
          return RY.post('/api/v1/admin/economics/recompute', { from: d.from, to: d.to }).then(function (res) {
            t.kapat();
            var s = (res && res.result) || {};
            b.toast('Yeniden hesaplandı: ' + aralik +
              (s.days != null ? ' · ' + b.sayi(s.days) + ' gün' : '') +
              (s.durationMs != null ? ' · ' + b.sayi(Math.round(s.durationMs / 1000)) + ' sn' : ''), 'basari', { sure: 8000 });
            m.kapat();
            var r2 = RY.rotaMevcut();
            if (r2.ad === 'gelir' || r2.ad === 'genel') RY.rotaYenile();
          }).catch(function (h) {
            t.kapat();
            if (h && h.durum === 409) {
              b.toast('Yeniden hesaplama zaten sürüyor — bitince tekrar dene.', 'uyari', { sure: 7000 });
              var iptal = new Error('iptal'); iptal.iptal = true; throw iptal;
            }
            throw h;
          });
        });
      }
    });
    var m = b.modal({ baslik: 'Geçmiş günleri yeniden hesapla', icerik: f.el, genislik: 460 });
    m.ac();
  }
  RY.palet.eylemEkle({ ad: 'gelir-yeniden-hesapla', etiket: 'Geçmiş günleri yeniden hesapla',
    aciklama: 'istatistik ve ekonomi özeti · seçilen günler',
    ikon: 'yenile', rol: 'owner', calistir: function () { yenidenHesaplaAc(); } });

  function csvIndir(sec) {
    var b = RY.b;
    var gun = b.utcGun(0).replace(/-/g, '');
    var t = b.toast('CSV hazırlanıyor…', 'bilgi', { sure: 0 });
    return RY.indir('/api/v1/admin/revenue/export.csv' + RY.sorguDizesi({ days: sec.days, env: sec.env }),
      'rytho-gelir-' + (sec.env === 'PRODUCTION' ? 'gercek' : 'test') + '-' + sec.days + 'gun-' + gun + '.csv')
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

  /* Tür çipi adrese yazılır (onTur), dönem UYGULANMAZ: uç tarih aralığı
     almıyor, imleçle en yeniden geriye gidiyor. Bunu dönem süzgeciyle
     süzülmüş gibi göstermek ölçülmemiş bir şeyi söylemek olurdu; modül
     başlığı "tüm zamanlar" diyor. */
  function olaylarKur(kap, sec, baglam, onTur) {
    var b = RY.b;
    var imlec = null;
    var yeniIstek = b.tazeleyici(baglam);
    kap.innerHTML = '<div class="suzgec" id="gelir-olay-tur"></div><div id="gelir-olay-tablo"></div>';

    var turCip = b.secimCipleri({
      etiket: 'Olay türü', grupAdi: 'Tür',
      secenekler: [{ deger: '', etiket: 'Tümü' }].concat(OLAY_TURLERI.map(function (t) {
        return { deger: t, etiket: olayAdi(t) };
      })),
      deger: sec.olay || '',
      onDegis: function (v) { sec.olay = v; if (onTur) onTur(v); yukle(false); }
    });
    kap.querySelector('#gelir-olay-tur').appendChild(turCip);

    var istek = null;
    var vt = b.veriTablosu({
      kimlik: 'gelir-olay-vt', etiket: 'Gelir olayları', yogunluk: 'sik',
      sutunlar: [
        { ad: 'at', baslik: 'Zaman', bicim: function (o) {
          return '<span class="mono">' + b.e(b.tarih(o.at, true)) + '</span>';
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
        { ad: 'countryCode', baslik: 'Ülke', bicim: function (o) { return b.e(o.countryCode ? ulkeAdi(o.countryCode) : '—'); } },
        { ad: 'periodType', baslik: 'Dönem türü', bicim: function (o) { return b.e(S().donemTuruAdi(o.periodType)); } }
      ],
      anahtar: function (o) { return o.id; },
      satirSinif: function (o) { return o.eventType === 'REFUND' || o.eventType === 'BILLING_ISSUE' ? 'durum-hata' : ''; },
      onSirala: function () { /* sunucu sıralı: en yeniden eskiye */ },
      bosMetin: 'Bu ortamda ve türde olay yok.',
      onTekrar: function () { yukle(false); }
    });
    kap.querySelector('#gelir-olay-tablo').appendChild(vt.el);

    function yukle(devam) {
      if (!devam) { vt.durum('yukleniyor'); imlec = null; istek = yeniIstek(); }
      var bu = istek;
      return RY.sorgu('/api/v1/admin/revenue/events',
        { env: sec.env, type: sec.olay || null, limit: OLAY_SAYFA, cursor: devam ? imlec : null }, { sinyal: bu.sinyal })
        .then(function (res) {
          if (!bu.gecerli()) return;
          var olaylar = Array.isArray(res && res.events) ? res.events : [];
          imlec = (res && res.nextCursor) || null;
          var sayfa = { daha: !!imlec, onDaha: function () { return yukle(true); } };
          if (devam) vt.ekle(olaylar, sayfa); else vt.guncelle(olaylar, sayfa);
        }).catch(function (h) {
          if (!bu.gecerli() || (h && h.iptal)) return;
          if (devam) hataToast(h); else vt.durum('hata', RY.hataMetni(h));
        });
    }
    yukle(false);
  }

  /* ---------------- Görünüm ---------------- */

  RY.gorunumler.gelir = async function (icerik, args, params, baglam) {
    var b = RY.b;
    var sec = paramOku(params);
    var sahip = RY.sahipMi();
    var yeniIstek = b.tazeleyici(baglam);

    var eylemler = sahip
      ? '<button type="button" class="buton ikincil" id="gelir-csv">' + b.ik('indir', 16) + 'CSV</button>' +
        '<button type="button" class="buton ikincil" id="gelir-hesapla">' + b.ik('yenile', 16) + 'Yeniden hesapla</button>'
      : '';
    icerik.innerHTML =
      b.sayfaBaslik({ baslik: 'Gelir & Abonelik', alt: 'Abonelik ve kredi paketi gelirleri · tutarlar USD (RevenueCat)',
        eylemlerHtml: eylemler }) +
      '<div class="suzgec-seridi" id="gelir-suzgec"><span class="dipnot suzgec-not">Günler UTC\'ye göre (Türkiye saatinden 3 saat geride)</span></div>' +
      '<div class="veri-alani" id="gelir-veri">' + b.iskelet() + '</div>';

    var alan = icerik.querySelector('#gelir-veri');
    var serit = icerik.querySelector('#gelir-suzgec');
    var not = serit.firstChild;

    function adresYaz() { RY.rotaYaz('gelir', [], rotaParam(sec), { sessiz: true }); }

    var ortamSecici = b.secimCipleri({
      etiket: 'Ortam', grupAdi: 'Ortam', bitisik: true,
      secenekler: ENVLER.map(function (e) { return { deger: e, etiket: ortamAdi(e) }; }),
      deger: sec.env,
      onDegis: function (v) { sec.env = v; adresYaz(); yukle(); }
    });
    var donemSecici = b.donemSecici({
      secenekler: GUNLER, deger: sec.days,
      notlar: { 7: 'Kullanıcı ekonomisi ve marj en kısa 30 gün hesaplanıyor; 7 gün seçiliyken o bölüm 30 günü gösterir.' },
      onDegis: function (v) { sec.days = v; adresYaz(); yukle(); }
    });
    serit.insertBefore(ortamSecici, not);
    serit.insertBefore(donemSecici, not);

    /* Bant düğmeleri veri bölgesinde yeniden çiziliyor; dinleyici tek, kökte. */
    alan.addEventListener('click', function (ev) {
      var gec = ev.target.closest('[data-ortama-gec]');
      if (gec) {
        sec.env = gec.getAttribute('data-ortama-gec');
        ortamSecici.ayarla(sec.env);
        adresYaz(); yukle();
        return;
      }
      var hes = ev.target.closest('[data-hesapla]');
      if (hes) {
        yenidenHesaplaAc({ from: hes.getAttribute('data-from') || null, to: hes.getAttribute('data-to') || null });
      }
    });

    var csv = icerik.querySelector('#gelir-csv');
    if (csv) csv.addEventListener('click', function () { csvIndir(sec); });
    var hesapla = icerik.querySelector('#gelir-hesapla');
    if (hesapla) hesapla.addEventListener('click', function () { yenidenHesaplaAc(); });

    function yukle() {
      var istek = yeniIstek();
      var bu = { env: sec.env, days: sec.days, olay: sec.olay };
      var ekoGun = ekonomiGunu(bu.days);
      alan.setAttribute('aria-busy', 'true');
      var s = { sinyal: istek.sinyal };
      return Promise.all([
        RY.sorgu('/api/v1/admin/revenue', { days: bu.days, env: bu.env }, s).catch(function (h) { return { hata: h }; }),
        RY.sorgu('/api/v1/admin/stats', { days: bu.days }, s).catch(function () { return null; }),
        RY.sorgu('/api/v1/admin/economics', { days: ekoGun, env: bu.env }, s).catch(function () { return null; })
      ]).then(function (hepsi) {
        if (!istek.gecerli()) return;
        alan.removeAttribute('aria-busy');
        var rev = hepsi[0] && !hepsi[0].hata ? hepsi[0] : null;
        if (!rev && !hepsi[1]) {
          alan.innerHTML = b.hataDurum(RY.hataMetni(hepsi[0].hata), { kimlik: 'gelir-tekrar' });
          alan.querySelector('#gelir-tekrar').addEventListener('click', yukle);
          return;
        }
        veriCiz(alan, { rev: rev, revHata: hepsi[0] && hepsi[0].hata, stats: hepsi[1], eko: hepsi[2],
                        ekoGun: ekoGun }, bu, sahip, baglam, function (v) { sec.olay = v; adresYaz(); });
      });
    }
    await yukle();
  };

  function veriCiz(alan, v, sec, sahip, baglam, onTur) {
    var b = RY.b;
    var rev = v.rev, stats = v.stats, eko = v.eko, ekoGun = v.ekoGun;
    var digerEnv = sec.env === 'PRODUCTION' ? 'SANDBOX' : 'PRODUCTION';

    var statsGunleri = (stats && stats.days) || [];     // yeniden eskiye
    var gunler = statsGunleri.slice().reverse();         // eskiden yeniye
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

    /* ---- Tazelik satırı ---- */
    var enYeni = statsGunleri[0] || null;
    var ozetSaat = enYeni ? b.saatFarki(enYeni.generatedAt) : null;
    var tazelik = '<p class="dipnot">' + b.e(b.guncellemeMetni(enYeni && enYeni.generatedAt)) + '</p>';

    /* ---- Bantlar: yalnız yanıtın GERÇEKTEN bildirdiği eksikler ---- */
    var bantlar = '';
    var hesaplaDugmesi = function (metin, from, to) {
      return sahip ? '<button type="button" class="buton sade kucuk" data-hesapla="1"' +
        (from ? ' data-from="' + b.e(from) + '"' : '') + (to ? ' data-to="' + b.e(to) + '"' : '') + '>' +
        b.e(metin) + '</button>' : '';
    };
    if (!rev) {
      bantlar += b.bant('<b>Gelir özeti alınamadı</b> — ' + b.e(RY.hataMetni(v.revHata)) +
        ' Kıvılcımlar ve kohortlar özetten geliyor.', 'hata', { html: true });
    }
    if (sec.env === 'SANDBOX') {
      bantlar += b.bant('<b>Test alımları gösteriliyor</b> — bunlar gerçek para değildir ve işletme ' +
        'sayılarına girmez.', 'bilgi', { html: true });
    }
    if (stats && rev) {
      var buOrtam = ortamOlaySayisi(gunler, sec.env), oteki = ortamOlaySayisi(gunler, digerEnv);
      if (!buOrtam && oteki) {
        // Cümle ekleri ortam adına göre elle: ad sözlükte değişirse burası
        // da değişmeli (Türkçe ek, adın son hecesine bağlı).
        var YOK = { PRODUCTION: 'gerçek alım olayı yok', SANDBOX: 'test alımı olayı yok' };
        var VAR = { PRODUCTION: 'gerçek alımlarda', SANDBOX: 'test alımlarında' };
        var GEC = { PRODUCTION: 'Gerçek alımları göster', SANDBOX: 'Test alımlarını göster' };
        bantlar += b.bant('Son ' + sec.days + ' günde ' + YOK[sec.env] + '; ' + VAR[digerEnv] + ' ' +
          b.e(b.sayi(oteki)) + ' olay var.', 'bilgi', { html: true,
            eylemHtml: '<button type="button" class="buton sade kucuk" data-ortama-gec="' + b.e(digerEnv) + '">' +
              GEC[digerEnv] + '</button>' });
      }
    }
    if (stats && (ozetSaat == null || ozetSaat > b.OZET_BAYAT_SAAT)) {
      bantlar += b.bant('<b>İstatistik özeti ' + (ozetSaat == null ? 'bu dönemde hiç üretilmemiş'
        : b.e(b.sayi(Math.round(ozetSaat))) + ' saattir yenilenmedi') + '</b> — saatlik toplama aksamış ' +
        'olabilir; bugünün geliri bu sayılarda eksik.' +
        (sahip ? ' "Yeniden hesapla" bugünü ve eksik günleri yeniden üretir.' : ' Sahip yeniden hesaplatabilir.'),
        'uyari', { html: true, eylemHtml: hesaplaDugmesi('Yeniden hesapla', b.utcGun(1), b.utcGun(0)) });
    }
    var eksik = stats ? eksikGunler(b, statsGunleri, sec.days) : [];
    if (eksik.length) {
      var ilkEksik = eksik[0], sonEksik = eksik[eksik.length - 1];
      bantlar += b.bant('<b>' + b.e(b.sayi(eksik.length)) + ' günün özeti yok</b> (' +
        b.e(eksik.length === 1 ? b.tarih(ilkEksik) : b.tarih(ilkEksik) + ' – ' + b.tarih(sonEksik)) +
        ') — gelir, ekonomi ve kıvılcımlar o günleri saymıyor.' +
        (sahip ? ' "Yeniden hesapla" o günleri doldurur.' : ''),
        'uyari', { html: true, eylemHtml: hesaplaDugmesi('Eksik günleri hesapla', ilkEksik, sonEksik) });
    }
    /* Ortak maliyetinin üç eksik hâli üç ayrı bant: teşhis farklı, yapılacak
       iş de farklı. Tek bant yazmak sahibi yanlış yere baktırırdı. */
    var ekoT = (eko && eko.totals) || null;
    if (ekoT && !ortakAlaniVar(ekoT)) {
      bantlar += b.bant('<b>Ortak edinme maliyeti sunucudan gelmiyor</b> — sunucu bu panelden eski sürümde. ' +
        'Marj İKİ terimli: ortak edinme maliyeti DÜŞÜLMEMİŞ, yani ortak bağlantısıyla gelen abonelerde ' +
        'olduğundan yüksek. Sunucu güncellenince kendiliğinden düzelir.',
        'uyari', { html: true });
    } else if (ekoT && Number(ekoT.partnerDaysMissing) > 0) {
      /* İKİ neden aynı sayaca düşüyor (`partnerDaysMissing`): alanı hiç
         taşımayan eski gün ve o günün sorgusu düşmüş gün (`partnerTry` =
         −1). Uç ikisini ayırmadığı için bant da AYIRMAZ; yalnız birini
         sebep diye yazmak, sahibi olmayan bir gerekçeye inandırırdı.
         Yapılacak iş ikisinde de aynı: o günleri yeniden yaz. Hangi
         günler olduğunu uç söylemiyor, o yüzden düğme aralığı önermez. */
      bantlar += b.bant('<b>Ortak edinme maliyeti ölçülmemiş</b> — ' + b.e(b.sayi(Number(ekoT.partnerDaysMissing))) +
        ' günün ekonomi özeti ortak edinme maliyetini taşımıyor: o günler bu ölçüm eklenmeden önce ' +
        'yazıldı ya da o günün sorgusu düştü. Eksik günde hangi kullanıcının ödülünün kayıp olduğu ' +
        'bilinmediği için marj <b>yıldızlı</b> gösteriliyor: ortak maliyeti düşülmemiş ama ölçülmüş sayı' +
        (sahip ? '. "Yeniden hesapla" o günleri yeniden yazar, alan kendiliğinden dolar.' : '.'),
        'uyari', { html: true, eylemHtml: hesaplaDugmesi('Yeniden hesapla') });
    } else if (ekoT && !ortakOlculdu(ekoT)) {
      bantlar += b.bant('<b>Kur ayarlı değil</b> — sunucu ayarına USD/TRY kuru girilmeli. Ortak edinme ' +
        'maliyeti ₺ olarak ölçüldü (' + b.e(b.para(ekoT.partnerCostTry, '₺')) + ') ama dolara ' +
        'çevrilemedi; marj bu yüzden hesaplanamıyor. Yıldızlı sayı ortak maliyeti düşülmemiş marjdır.',
        'uyari', { html: true });
    }

    /* ---- KPI ---- */
    var kpiler = '<section class="izgara-kpi" aria-label="Gelir özeti">' +
      b.istatistikKarti({ ad: 'Brüt gelir', deger: rev ? b.para(brut) : '—', altin: true,
        alt: rev ? b.sayi(byDay.reduce(function (t, g) { return t + (Number(g.count) || 0); }, 0)) + ' parasal olay · ' + sec.days + ' gün' : '—',
        kivilcim: byDay.map(function (g) { return Number(g.gross) || 0; }), renk: 'gold' }) +
      b.istatistikKarti({ ad: 'Aylık düzenli gelir', deger: rev ? b.para(rev.mrrUsd) : '—', altin: true,
        alt: mrrUrunMetin || 'aktif abone × birim fiyat', kivilcim: gunler.map(function (g) { return Number((g.subs || {}).mrrUsd) || 0; }), renk: 'gold' }) +
      b.istatistikKarti({ ad: 'Aktif abone', deger: aktif != null ? b.sayi(aktif) : '—',
        alt: rev && rev.asOf ? 'son özet ' + b.tarih(rev.asOf) : 'özet yok',
        kivilcim: gunler.map(function (g) { var x = (g.subs || {}).active; return x >= 0 ? Number(x) || 0 : 0; }) }) +
      b.istatistikKarti({ ad: 'Deneme', deger: rev ? b.sayi(rev.trialing) : '—',
        alt: rev && rev.trialExpiring3d ? b.sayi(rev.trialExpiring3d) + ' tanesi 3 gün içinde bitiyor' : 'mağaza denemesi', renk: 'lilac' }) +
      b.istatistikKarti({ ad: 'Kayıp oranı', deger: churn != null ? b.yuzde(churn) : '—',
        alt: b.sayi(olay('EXPIRATION')) + ' sona erme · ' + b.sayi(olay('CANCELLATION')) + ' iptal', renk: 'madder' }) +
      b.istatistikKarti({ ad: 'Denemeden aboneliğe', deger: donusum != null ? b.yuzde(donusum) : '—',
        alt: b.sayi(denemeDon) + ' / ' + b.sayi(denemeBas) + ' deneme' }) +
      b.istatistikKarti({ ad: 'İadeler', deger: rev ? b.para(iade) : '—',
        alt: b.sayi(olay('REFUND')) + ' iade · ' + b.sayi(olay('BILLING_ISSUE')) + ' ödeme sorunu',
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
          return '<tr><th scope="row">' + b.e(ayAdi(ay)) + '</th><td class="sayi">' + b.e(b.sayi(kayit)) + '</td>' +
            '<td class="sayi">' + b.e(b.sayi(plus)) + '</td><td class="sayi">' + b.e(kayit ? b.yuzde(plus / kayit * 100) : '—') + '</td></tr>';
        }).join('') + '</tbody></table></div>'
      : b.bosDurum('Kohort verisi özette yok — ilk toplamayla dolar.');

    var ekoNot = ekoGun !== sec.days ? ' (' + sec.days + ' günlük ekonomi hesabı yok)' : '';
    var t = (eko && eko.totals) || null;
    var ekoHtml = t
      ? '<dl class="alan-liste">' +
        '<dt>Gerçek alım geliri</dt><dd>' + b.e(b.para(t.revenueUsd)) + '</dd>' +
        '<dt>Test alımı geliri</dt><dd>' + b.e(b.para(t.sandboxUsd)) + '</dd>' +
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
           Kur cümlesi de ancak kur BİLİNİYORSA yazılır — ödülü sıfır olan
           pencerede kur okunamamış olabilir ve "kur — ile türetilir" bir
           şey söylemez. */
        '<p class="dipnot">Marj = seçili ortamın geliri × (1 − mağaza payı) − AI maliyeti' +
        (ortakOlculdu(t)
          ? ' − ortak edinme maliyeti; sabit giderler hariç.' +
            (Number(t.usdTryRate) > 0
              ? ' Ortak ödülü ₺ ölçülür, dolar karşılığı ' +
                b.e(b.sayi(t.usdTryRate)) + ' kuruyla türetilir.'
              : '')
          : '; sabit giderler hariç. Yıldızlı sayı ortak edinme maliyeti ' +
            'DÜŞÜLMEMİŞ marjdır; nedenini yukarıdaki bant söylüyor.') + '</p>'
      : b.bosDurum('Ekonomi özeti alınamadı.', { ikon: 'gelir' });

    var tablolar =
      '<div class="izgara-2">' +
      b.modul('Kayıt kohortları', kohortHtml, '', { alt: 'aya göre kayıt · bugün Rytho+ olanlar' }) +
      b.modul('Ekonomi toplamları', ekoHtml, '', { alt: ekoGun + ' gün' + ekoNot + ' · ' + ortamAdi(sec.env) }) +
      '</div>' +
      b.modul('Kullanıcı ekonomisi', '<div id="gelir-eko-tablo"></div>', '',
        { alt: ekoGun + ' gün' + ekoNot + ' · marja göre ilk 200 · satır → ayrıntı' }) +
      b.modul('Olay akışı', '<div id="gelir-olaylar"></div>', '',
        { alt: ortamAdi(sec.env) + ' · tüm zamanlar, en yeniden eskiye (dönem süzgeci uygulanmaz) · parasız olaylar dahil' }) +
      '<p class="dipnot">Gelir saatlik özetten (son gün ' + b.e(rev && rev.asOf ? b.tarih(rev.asOf) : '—') + '); ' +
      'kayıp oranı dönem içi kaba orandır. Mağaza payı sabit ~%15 varsayımı.</p>';

    alan.innerHTML = tazelik + bantlar + kpiler + grafikler + tablolar;

    /* ---- Grafikler ---- */
    var g = RY.grafik;
    g.cizgi(alan.querySelector('#g-gelir-gun'), {
      seriler: [
        { ad: 'Brüt', renk: 'gold', veri: byDay.map(function (x) { return { x: x.date, y: Number(x.gross) || 0 }; }) },
        { ad: 'İade', renk: 'madder', veri: byDay.map(function (x) { return { x: x.date, y: Number(x.refunds) || 0 }; }) }
      ],
      alan: true, bicim: 'para', etiket: 'Günlük gelir', bosMetin: 'Bu dönemde parasal olay yok'
    });
    var urunler = kirilim((rev && rev.byProduct) || {}, 8);
    g.cubuk(alan.querySelector('#g-gelir-urun'), {
      etiketler: urunler.map(function (u) { return u.ad; }), degerler: urunler.map(function (u) { return u.deger; }),
      yatay: true, bicim: 'para', enCok: 8, etiket: 'Ürün başına brüt', bosMetin: 'Ürün kırılımı yok'
    });
    g.halka(alan.querySelector('#g-gelir-magaza'), {
      dilimler: kirilim((rev && rev.byStore) || {}, 6, magazaAdi), bicim: 'para', merkezAlt: 'brüt', etiket: 'Mağaza payı',
      bosMetin: 'Mağaza kırılımı yok'
    });
    g.halka(alan.querySelector('#g-gelir-ulke'), {
      dilimler: kirilim((rev && rev.byCountry) || {}, 8, ulkeAdi), bicim: 'para', merkezAlt: 'brüt', etiket: 'Ülke payı',
      bosMetin: 'Ülke kırılımı yok'
    });

    /* ---- Kullanıcı ekonomisi ---- */
    var ekoVt = b.veriTablosu({
      kimlik: 'gelir-eko-vt', etiket: 'Kullanıcı ekonomisi', yogunluk: 'sik',
      sutunlar: [
        { ad: 'ad', baslik: 'Kullanıcı', deger: function (u) { return u.displayName || u.email || u.uid; },
          bicim: function (u) { return kisiHucresi(b, u); } },
        { ad: 'revenueUsd', baslik: 'Gerçek alım', hizala: 'sag', siralanir: true, bicim: function (u) { return b.e(b.para(u.revenueUsd)); } },
        { ad: 'sandboxUsd', baslik: 'Test alımı', hizala: 'sag', siralanir: true, bicim: function (u) {
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
      bosMetin: eko ? 'Bu dönemde kullanıcı satırı yok.' : 'Ekonomi özeti alınamadı.'
    });
    alan.querySelector('#gelir-eko-tablo').appendChild(ekoVt.el);
    ekoVt.guncelle((eko && Array.isArray(eko.users)) ? eko.users : []);

    /* ---- Olaylar ---- */
    olaylarKur(alan.querySelector('#gelir-olaylar'), sec, baglam, onTur);
  }

  RY.kirintiSaglayici.gelir = function () {
    return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Gelir & Abonelik' }];
  };
})();

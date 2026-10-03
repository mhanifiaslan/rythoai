/* Bildirimler (AD8/AD19): koşu sağlığı (notifyRuns 14 gün), dil dağılımı,
   atlanma nedenleri, başarısız eğilimi; "Prova" ve "Kendime test gönder".

   Rota: #/bildirimler (parametre yok).
   Uçlar:
   - GET  /api/v1/admin/notify-runs?days=14 → {runs:[{id, date, type, runs,
     scanned, queued, sent, failed, pruned, skipped:{neden:n},
     languages:{dil:n}, lastStatus, lastRunAt}]}
   - POST /api/v1/admin/notify/dry-run {type, force} → {result:{status,
     type, scanned, queued, sent, failed, pruned, skipped, languages}}
     (GÖNDERİM YOK — kim kuyruğa girerdi, hangi dilde)
   - POST /api/v1/admin/notify/test-send {type} → {result:{sent, failed,
     lang, title, body, skippedReason, type}}; jeton yoksa 400 ve mesaj
     olduğu gibi gösterilir (destek de kullanabilir).

   İki eylem komut paletine de kaydedilir; modal'lar sayfadan bağımsızdır. */
(function () {
  'use strict';

  var RY = window.RY;
  RY.gorunumler = RY.gorunumler || {};

  // ⚠️ Bu liste `notify_runner.RUN_TYPES` ile AYNI KÜMEYİ taşımak zorunda ve
  // elle yazılı olmasının tek sebebi etiketler: Türkçe görünen adlar panele
  // ait, sunucuya değil. Küme `test_notify_turleri_tek_kaynak.py` ile çivili.
  //
  // Bir tur boyunca dörtte kaldı ve bedeli ölçüldü: `circle`/`winback`
  // slotları eklenince operatör onları panelden ne izleyebildi ne prova
  // edebildi — koşu türü seçicisinde HİÇ görünmüyorlardı ve koşu kayıtları
  // "—" diye çiziliyordu. Aynı küme depoda ALTI yerde yaşıyordu; beşi tek
  // kaynağa bağlandı, bu altıncısı bekçiyle bağlı.
  var TURLER = [
    { deger: 'daily', etiket: 'Günlük (sabah)' },
    { deger: 'midday', etiket: 'Öğle' },
    { deger: 'circle', etiket: 'Çevrem (yakınların)' },
    { deger: 'winback', etiket: 'Geri kazanım' },
    { deger: 'checkin', etiket: 'Check-in (akşam)' },
    { deger: 'streak', etiket: 'Seri hatırlatma' }
  ];
  var TUR_ADI = {};
  TURLER.forEach(function (t) { TUR_ADI[t.deger] = t.etiket; });
  function turAdi(t) { return TUR_ADI[t] || String(t || '—'); }

  var DIL_ADI = { tr: 'Türkçe', en: 'İngilizce', de: 'Almanca', fr: 'Fransızca',
                  es: 'İspanyolca', ar: 'Arapça', ru: 'Rusça' };
  function dilAdi(k) { return DIL_ADI[k] || String(k); }

  /* Atlanma nedeni anahtarı → okunur ad (bilinmeyen olduğu gibi). */
  var NEDEN = { 'jeton-yok': 'Jeton yok', 'jeton-baska-hesapta': 'Jeton başka hesapta',
                'burc-bilinmiyor': 'Burç bilinmiyor', 'soru-yok': 'Soru yok',
                'dil-uyusmaz': 'Dil uyuşmaz', 'bugun-gonderildi': 'Bugün gönderildi',
                'saat-disi': 'Saat dışı', 'kapali': 'Bildirim kapalı' };
  function nedenAdi(k) { return NEDEN[k] || String(k); }

  function sozlukTopla(liste, alan) {
    var t = {};
    liste.forEach(function (k) {
      var kova = k[alan] || {};
      Object.keys(kova).forEach(function (a) { t[a] = (t[a] || 0) + (Number(kova[a]) || 0); });
    });
    return t;
  }

  function rozetGrubu(b, kova, adla) {
    var anahtarlar = Object.keys(kova || {}).filter(function (k) { return Number(kova[k]) > 0; })
      .sort(function (x, y) { return Number(kova[y]) - Number(kova[x]); });
    if (!anahtarlar.length) return '<span class="dipnot">—</span>';
    return '<span class="rozet-grup">' + anahtarlar.map(function (k) {
      return b.rozet(adla(k) + ' · ' + b.sayi(Number(kova[k])), 'notr');
    }).join('') + '</span>';
  }

  /* ---------------- Eylem modal'ları (sayfadan bağımsız) ---------------- */

  function provaAc() {
    var b = RY.b;
    var f = b.form({
      alanlar: [
        { ad: 'type', etiket: 'Koşu türü', tur: 'select', secenekler: TURLER, deger: 'daily' },
        { ad: 'force', etiket: 'Saat penceresini yok say (force)', tur: 'checkbox',
          yardim: 'Kapalıyken yalnız şu an gönderim saatinde olan kullanıcılar kuyruğa girer.' }
      ],
      gonderMetin: 'Provayı çalıştır',
      iptal: { metin: 'Vazgeç', onTikla: function () { m.kapat(); } },
      onGonder: function (d) {
        return RY.post('/api/v1/admin/notify/dry-run', { type: d.type, force: !!d.force })
          .then(function (res) {
            var r = (res && res.result) || res || {};
            sonucGoster(r, d.type);
          });
      }
    });
    var govde = b.el('<div class="form"></div>');
    govde.insertAdjacentHTML('beforeend', '<p class="aciklama">Gönderim YAPILMAZ, LastSent ' +
      'işaretlenmez; yalnız kim kuyruğa girerdi ve hangi dilde görünür. Denetim izine düşer.</p>');
    govde.appendChild(f.el);
    var sonucKutu = b.el('<div id="prova-sonuc" hidden></div>');
    govde.appendChild(sonucKutu);
    var m = b.modal({ baslik: 'Bildirim provası', icerik: govde, genislik: 560 });

    function sonucGoster(r, tur) {
      var skipped = r.skipped || {}, diller = r.languages || {};
      sonucKutu.innerHTML =
        b.bant('<b>' + b.e(turAdi(tur)) + '</b> provası bitti — ' + b.e(b.sayi(r.queued || 0)) +
          ' kuyruk, ' + b.e(b.sayi(r.scanned || 0)) + ' taranan.', 'basari', { html: true }) +
        '<dl class="alan-liste">' +
        '<dt>Taranan</dt><dd>' + b.e(b.sayi(r.scanned || 0)) + '</dd>' +
        '<dt>Kuyruğa girecek</dt><dd>' + b.e(b.sayi(r.queued || 0)) + '</dd>' +
        '<dt>Gönderilen</dt><dd>' + b.e(b.sayi(r.sent || 0)) + ' (prova)</dd>' +
        '<dt>Temizlenecek jeton</dt><dd>' + b.e(b.sayi(r.pruned || 0)) + '</dd>' +
        '</dl>' +
        '<div class="form-alan"><span class="form-etiket">Diller</span>' +
        rozetGrubu(b, diller, dilAdi) + '</div>' +
        '<div class="form-alan"><span class="form-etiket">Atlanma nedenleri</span>' +
        rozetGrubu(b, skipped, nedenAdi) + '</div>';
      sonucKutu.hidden = false;
      sonucKutu.setAttribute('tabindex', '-1');
      sonucKutu.focus();
    }
    m.ac();
  }

  function testGonderAc() {
    var b = RY.b;
    var f = b.form({
      alanlar: [
        { ad: 'type', etiket: 'Koşu türü', tur: 'select', secenekler: TURLER, deger: 'daily',
          yardim: 'Koşu bu hesaba bir şey kuyruklarsa o gider; atlanırsa sabit test metni gider.' }
      ],
      gonderMetin: 'Kendime gönder',
      iptal: { metin: 'Vazgeç', onTikla: function () { m.kapat(); } },
      onGonder: function (d) {
        return RY.post('/api/v1/admin/notify/test-send', { type: d.type })
          .then(function (res) {
            var r = (res && res.result) || res || {};
            var ozet = (r.lang ? '[' + r.lang + '] ' : '') + (r.title || '') +
              (r.body ? ' — ' + r.body : '');
            if (r.failed && !r.sent) {
              b.toast('Gönderim başarısız: ' + ozet, 'hata');
            } else {
              b.toast('Test gönderildi ' + ozet +
                (r.skippedReason ? ' (koşu atladı: ' + nedenAdi(r.skippedReason) + ')' : ''),
                'basari', { sure: 8000 });
              m.kapat();
            }
          });
        // 400 (jeton yok): form onGonder'in catch'i RY.hataMetni(h) → detay
        // olduğu gibi form özetine yazılır.
      }
    });
    var govde = b.el('<div class="form"></div>');
    govde.insertAdjacentHTML('beforeend', '<p class="aciklama">Yalnız senin hesabına (bu ' +
      'oturumun uid\'i) gerçek push gider; LastSent işaretlenmez. Mobilde bu hesapla giriş ' +
      'yapılmış olmalı.</p>');
    govde.appendChild(f.el);
    var m = b.modal({ baslik: 'Kendime test bildirimi', icerik: govde, genislik: 480 });
    m.ac();
  }

  RY.palet.eylemEkle({ ad: 'bildirim-prova', etiket: 'Bildirim provası çalıştır',
    aciklama: 'Gönderim yok — kim kuyruğa girerdi', ikon: 'prova', calistir: provaAc });
  RY.palet.eylemEkle({ ad: 'bildirim-test', etiket: 'Kendime test bildirimi gönder',
    aciklama: 'Yalnız senin hesabına', ikon: 'gonder', calistir: testGonderAc });

  /* ---------------- Görünüm ---------------- */

  RY.gorunumler.bildirimler = async function (icerik) {
    var b = RY.b;
    var veri = await RY.sorgu('/api/v1/admin/notify-runs', { days: 14 });
    var kosular = Array.isArray(veri.runs) ? veri.runs : [];

    var toplamGonderilen = 0, toplamBasarisiz = 0, toplamTemizlenen = 0, sonKosu = null;
    kosular.forEach(function (k) {
      toplamGonderilen += Number(k.sent) || 0;
      toplamBasarisiz += Number(k.failed) || 0;
      toplamTemizlenen += Number(k.pruned) || 0;
      var d = b.tarihNesnesi(k.lastRunAt);
      if (d && (!sonKosu || d > sonKosu)) sonKosu = d;
    });
    var oran = toplamGonderilen + toplamBasarisiz
      ? (toplamGonderilen / (toplamGonderilen + toplamBasarisiz)) * 100 : null;

    var bas = b.sayfaBaslik({
      baslik: 'Bildirimler', alt: 'Son 14 gün · koşu sağlığı, dil dağılımı, atlanma nedenleri',
      eylemlerHtml:
        '<button type="button" class="buton ikincil" id="bil-prova">' + b.ik('prova', 16) + 'Prova</button>' +
        '<button type="button" class="buton" id="bil-test">' + b.ik('gonder', 16) + 'Kendime test gönder</button>'
    });

    if (!kosular.length) {
      icerik.innerHTML = bas + b.bosDurum('Henüz koşu kaydı yok — zamanlayıcının ilk koşusuyla ' +
        'dolar. Prova ve test gönderimi yine çalışır.', { ikon: 'bildirim' });
      eylemBagla(icerik);
      return;
    }

    var bugunBasarisiz = kosular.filter(function (k) {
      return k.date === new Date().toISOString().slice(0, 10);
    }).reduce(function (t, k) { return t + (Number(k.failed) || 0); }, 0);
    var bant = bugunBasarisiz
      ? b.bant('<b>' + b.e(b.sayi(bugunBasarisiz)) + ' push bugün başarısız</b> — geçersiz ' +
          'jetonlar temizlenir; tekrar edenlerde cihaz/oturum kontrolü gerekir.', 'uyari', { html: true })
      : '';

    var kpiler = '<section class="izgara-kpi" aria-label="Bildirim özeti">' +
      b.istatistikKarti({ ad: 'Gönderilen (14g)', deger: b.sayi(toplamGonderilen), altin: true }) +
      b.istatistikKarti({ ad: 'Başarısız (14g)', deger: b.sayi(toplamBasarisiz),
        alt: toplamBasarisiz ? 'jeton temizlendi' : 'temiz' }) +
      b.istatistikKarti({ ad: 'Başarı oranı', deger: oran == null ? '—' : b.yuzde(oran) }) +
      b.istatistikKarti({ ad: 'Temizlenen jeton', deger: b.sayi(toplamTemizlenen) }) +
      b.istatistikKarti({ ad: 'Son koşu', deger: sonKosu ? b.goreliZaman(sonKosu) : '—',
        alt: sonKosu ? b.tarih(sonKosu, true) : 'kayıt yok' }) +
      '</section>';

    var grafikler = '<div class="izgara-3">' +
      b.modul('Diller', '<div class="halka-kap"><div class="grafik-kap"><canvas id="g-bil-dil" class="grafik" ' +
        'aria-label="Kuyruğa giren mesajların dil dağılımı"></canvas></div></div>', '', { alt: 'kuyruğa giren · 14 gün' }) +
      b.modul('Atlanma nedenleri', '<div class="grafik-kap"><canvas id="g-bil-neden" class="grafik grafik-kucuk" ' +
        'aria-label="Atlanma nedenleri"></canvas></div>', '', { alt: 'sessiz düşenler görünür' }) +
      b.modul('Başarısız eğilimi', '<div class="grafik-kap"><canvas id="g-bil-basarisiz" class="grafik grafik-kucuk" ' +
        'aria-label="Günlük başarısız gönderim"></canvas></div>', '', { alt: 'gün başına · tüm türler' }) +
      '</div>';

    var tablo = b.modul('Koşular', '<div id="bil-tablo"></div>', '',
      { alt: 'gün × tür · sayılar saatlik koşularda birikir' });

    icerik.innerHTML = bas + bant + kpiler + grafikler + tablo +
      '<p class="dipnot">Bir gün-tür dokümanı zamanlayıcının o günkü tüm koşularını toplar ' +
      '(Increment). Prova iz bırakmaz; test gönderimi yalnız çağıranın hesabına gider.</p>';
    eylemBagla(icerik);

    /* Grafikler */
    var g = RY.grafik;
    var diller = sozlukTopla(kosular, 'languages');
    g.halka(document.getElementById('g-bil-dil'), {
      dilimler: Object.keys(diller).map(function (k) { return { ad: dilAdi(k), deger: diller[k] }; }),
      merkezAlt: 'mesaj', etiket: 'Dil dağılımı', bosMetin: 'Dil dökümü henüz yok'
    });
    var nedenler = sozlukTopla(kosular, 'skipped');
    var nedenSira = Object.keys(nedenler).sort(function (x, y) { return nedenler[y] - nedenler[x]; });
    g.cubuk(document.getElementById('g-bil-neden'), {
      etiketler: nedenSira.map(nedenAdi), degerler: nedenSira.map(function (k) { return nedenler[k]; }),
      yatay: true, enCok: 8, etiket: 'Atlanma nedenleri', bosMetin: 'Atlanan yok'
    });
    var gunler = {};
    kosular.forEach(function (k) {
      if (!k.date) return;
      gunler[k.date] = (gunler[k.date] || 0) + (Number(k.failed) || 0);
    });
    var gunSira = Object.keys(gunler).sort();
    g.cizgi(document.getElementById('g-bil-basarisiz'), {
      seriler: [{ ad: 'Başarısız', renk: 'madder',
        veri: gunSira.map(function (d) { return { x: d, y: gunler[d] }; }) }],
      alan: true, bicim: 'sayi', etiket: 'Başarısız eğilimi'
    });

    /* Tablo */
    var vt = b.veriTablosu({
      kimlik: 'bil-kosu-tablo', etiket: 'Bildirim koşuları', yogunluk: 'sik',
      sutunlar: [
        { ad: 'date', baslik: 'Gün', siralanir: true,
          bicim: function (k) { return '<span class="mono">' + b.e(k.date || '') + '</span>'; } },
        { ad: 'type', baslik: 'Tür', siralanir: true,
          bicim: function (k) { return b.rozet(turAdi(k.type), k.type === 'daily' ? 'altin' : 'notr'); } },
        { ad: 'runs', baslik: 'Koşu', hizala: 'sag', siralanir: true },
        { ad: 'scanned', baslik: 'Taranan', hizala: 'sag', siralanir: true },
        { ad: 'sent', baslik: 'Gönderilen', hizala: 'sag', siralanir: true },
        { ad: 'failed', baslik: 'Başarısız', hizala: 'sag', siralanir: true,
          bicim: function (k) {
            return Number(k.failed) ? b.rozet(b.sayi(k.failed), 'hata') : b.rozet('0', 'aktif');
          } },
        { ad: 'pruned', baslik: 'Temizlenen', hizala: 'sag', siralanir: true },
        { ad: 'skipped', baslik: 'Atlanan', bicim: function (k) { return rozetGrubu(b, k.skipped, nedenAdi); } },
        { ad: 'lastRunAt', baslik: 'Son koşu', deger: function (k) {
            var d = b.tarihNesnesi(k.lastRunAt); return d ? d.getTime() : null; },
          siralanir: true,
          bicim: function (k) {
            return '<span class="mono">' + b.e(b.tarih(k.lastRunAt, true)) + '</span>' +
              (k.lastStatus && k.lastStatus !== 'ok'
                ? ' ' + b.rozet(String(k.lastStatus), 'uyari') : '');
          } }
      ],
      anahtar: function (k) { return k.id || (k.date + '-' + k.type); },
      satirSinif: function (k) { return Number(k.failed) ? 'durum-uyari' : ''; },
      siralama: { ad: 'date', yon: 'desc' },
      bosMetin: 'Koşu yok'
    });
    document.getElementById('bil-tablo').appendChild(vt.el);
    vt.guncelle(kosular);
  };

  function eylemBagla(icerik) {
    var p = icerik.querySelector('#bil-prova'), t = icerik.querySelector('#bil-test');
    if (p) p.addEventListener('click', provaAc);
    if (t) t.addEventListener('click', testGonderAc);
  }

  RY.kirintiSaglayici.bildirimler = function () {
    return [{ metin: 'Yönetim', href: '#/genel' }, { metin: 'Bildirimler' }];
  };
})();

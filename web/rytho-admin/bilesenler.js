/* Paylaşılan arayüz bileşenleri v3 (AD15).

   İki katman:
   - HTML dizesi üreten yardımcılar: e, sayi, para, yuzde, tarih,
     rozet, modul, istatistikKarti, bant, sayfaBaslik, bosDurum,
     hataDurum, iskelet, planRozeti, rolRozeti… Görünüm innerHTML'e gömer.
   - Etkileşimli bileşenler (Element döner): veriTablosu, modal, yanPanel,
     onayla (Promise), toast, filtreCipleri, secimCipleri/donemSecici,
     sekmeler, form; ve görünümlerin veri bölgesini yarışsız tazeleyen
     `tazeleyici`.

   Tüm çıktılar admin.css sınıflarına dayanır — inline stil yalnız dinamik
   genişlik (sütun) ve modal genişliği (CSS değişkeni). Her serbest metin
   e() ile kaçırılır; bicim()/icerik() gibi görünümün ürettiği HTML'in
   güvenliği görünümün sorumluluğudur (o da e() kullanır). */
(function () {
  'use strict';

  var RY = window.RY = window.RY || {};
  var sayac = 0;

  /* ---------------- Temel yardımcılar ---------------- */

  function e(metin) {
    return String(metin == null ? '-' : metin)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function ik(ad, boyut) { return RY.ikon ? RY.ikon(ad, boyut) : ''; }

  /* HTML dizesinden TEK kök eleman. */
  function el(html) {
    var t = document.createElement('template');
    t.innerHTML = String(html).trim();
    return t.content.firstElementChild;
  }

  /* Türkçe küçültme: İ→i, I→ı (toLowerCase tek başına İ'yi "i̇" yapar). */
  function kucult(s) {
    return String(s == null ? '' : s)
      .replace(/İ/g, 'i').replace(/I/g, 'ı').toLowerCase();
  }

  function sayi(v) {
    if (v == null || v === -1) return '—';
    return typeof v === 'number' ? v.toLocaleString('tr-TR') : String(v);
  }

  /* Para: 2 basamak; yalnız bir sentin ALTINDAKİ (sıfır olmayan) tutarlar 4
     basamak. Eski kural 1 doların altını 4 basamak yazıyordu ve aynı
     tabloda "$0,4500" ile "$1,20" yan yana duruyordu; 4 basamağın tek
     gerekçesi tek çağrılık AI maliyeti gibi sent altı tutarların "$0,00"
     diye silinmemesi. */
  function para(v, birim) {
    if (v == null || v === -1) return '—';
    var n = Number(v);
    if (isNaN(n)) return '—';
    var kucuk = n !== 0 && Math.abs(n) < 0.01;
    // Eksi işaret birimin ÖNÜNDE ("−$1,12"; "$-1,12" değil).
    return (n < 0 ? '−' : '') + (birim || '$') + Math.abs(n).toLocaleString('tr-TR', {
      minimumFractionDigits: kucuk ? 4 : 2,
      maximumFractionDigits: kucuk ? 4 : 2
    });
  }

  /* Yüzde Türkçe yazımla: işaret ÖNDE ("%12,5"); eksi işaret yüzdenin
     önüne gelir ("−%3,0"). */
  function yuzde(v, basamak) {
    if (v == null || !isFinite(Number(v))) return '—';
    var n = Number(v);
    var b = basamak == null ? 1 : basamak;
    return (n < 0 ? '−' : '') + '%' + Math.abs(n).toLocaleString('tr-TR', {
      minimumFractionDigits: b, maximumFractionDigits: b
    });
  }

  /* Firestore zaman değeri ISO dizge, {seconds}, {_seconds}, ms sayı ya da
     Date gelebilir → Date ya da null. */
  function tarihNesnesi(v) {
    if (!v) return null;
    var d;
    if (v instanceof Date) d = v;
    else if (typeof v === 'string' || typeof v === 'number') d = new Date(v);
    else if (v.seconds != null) d = new Date(v.seconds * 1000);
    else if (v._seconds != null) d = new Date(v._seconds * 1000);
    else if (typeof v.toDate === 'function') d = v.toDate();
    else d = new Date(v);
    return isNaN(d.getTime()) ? null : d;
  }

  /* Görünen saat dilimi SABİT: işletme Türkiye'de, yönetici hangi
     makineden açarsa açsın "dün 23:50" aynı an olmalı. Eskiden tarayıcının
     dilimi kullanılıyordu — yurt dışından açılan panelde aynı olay başka
     güne düşüyordu. */
  var SAAT_DILIMI = 'Europe/Istanbul';
  var GUN_DESENI = /^\d{4}-\d{2}-\d{2}$/;

  /* Tek tarih biçimi: "17 Eki 2026", saatliyse "17 Eki 2026 14:05".
     Çıplak "YYYY-AA-GG" bir AN değil bir GÜN etiketidir (rollup kovaları
     UTC günü) — dilime çevrilmez, aynen o gün yazılır; çevrilseydi gece
     yarısına yakın bir kova komşu güne kayabilirdi. */
  function tarih(v, saatli) {
    if (!v) return '—';
    var gunEtiketi = typeof v === 'string' && GUN_DESENI.test(v);
    var d = tarihNesnesi(v);
    if (!d) return String(v);
    var dilim = gunEtiketi ? 'UTC' : SAAT_DILIMI;
    var gun = d.toLocaleDateString('tr-TR',
      { day: 'numeric', month: 'short', year: 'numeric', timeZone: dilim });
    if (!saatli || gunEtiketi) return gun;
    return gun + ' ' + d.toLocaleTimeString('tr-TR',
      { hour: '2-digit', minute: '2-digit', timeZone: SAAT_DILIMI });
  }

  /* Kısa gün: "17.10" (grafik ekseniyle aynı). */
  function kisaGun(v) {
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v || ''));
    if (m) return Number(m[3]) + '.' + m[2];
    var d = tarihNesnesi(v);
    if (!d) return '—';
    return d.toLocaleDateString('tr-TR', { day: 'numeric', month: '2-digit', timeZone: SAAT_DILIMI });
  }

  /* "az önce", "12 dk önce", "3 sa önce", "dün", "5 gün önce", sonra tarih. */
  function goreliZaman(v) {
    var d = tarihNesnesi(v);
    if (!d) return '—';
    var fark = (Date.now() - d.getTime()) / 1000;
    if (fark < 45) return 'az önce';
    if (fark < 3600) return Math.round(fark / 60) + ' dk önce';
    if (fark < 86400) return Math.round(fark / 3600) + ' sa önce';
    if (fark < 172800) return 'dün';
    if (fark < 30 * 86400) return Math.round(fark / 86400) + ' gün önce';
    return tarih(d);
  }

  /* Süreklilik: "12 dakikadır", "3 saattir", "5 gündür". "…önceden beri"
     kuruluşu Türkçe değildi ("3 sa önceden beri"); birim kelimeleri sabit
     olduğu için ek uyumu burada elle doğru yazılabiliyor. */
  function sureMetni(v) {
    var d = tarihNesnesi(v);
    if (!d) return '—';
    var fark = Math.max(0, (Date.now() - d.getTime()) / 1000);
    if (fark < 60) return 'bir dakikadan az süredir';
    if (fark < 3600) return Math.round(fark / 60) + ' dakikadır';
    if (fark < 86400) return Math.round(fark / 3600) + ' saattir';
    return Math.round(fark / 86400) + ' gündür';
  }

  /* UTC gün anahtarı ("YYYY-AA-GG") — rollup kovalarıyla AYNI takvim. */
  function utcGun(farkGun) {
    return new Date(Date.now() - (farkGun || 0) * 86400000).toISOString().slice(0, 10);
  }

  /* İstatistik özeti saatlik üretiliyor (Cloud Scheduler `rytho-stats`).
     Bir koşu kaçabilir; iki saat geçmişse bir şey ters gidiyor demektir.
     Eşik tek yerde: Genel, Gelir ve Sistem aynı hükmü versin. */
  var OZET_BAYAT_SAAT = 2;

  function saatFarki(v) {
    var d = tarihNesnesi(v);
    return d ? (Date.now() - d.getTime()) / 3600000 : null;
  }

  /* "Güncelleme: saatte bir · son: 12 dk önce" — en yeni rollup
     dokümanının `generatedAt`ından. Doküman yoksa söyler, uydurmaz. */
  function guncellemeMetni(generatedAt) {
    if (!tarihNesnesi(generatedAt)) return 'Güncelleme: saatte bir · henüz toplanmış özet yok';
    return 'Güncelleme: saatte bir · son: ' + goreliZaman(generatedAt);
  }

  /* Ad/e-postadan 1-2 harfli avatar kısaltması. */
  function basHarfler(ad, eposta) {
    var kaynak = String(ad || '').trim() || String(eposta || '').split('@')[0];
    var parcalar = kaynak.split(/[\s._-]+/).filter(Boolean);
    if (!parcalar.length) return '?';
    var s = parcalar[0].charAt(0);
    if (parcalar.length > 1) s += parcalar[parcalar.length - 1].charAt(0);
    return s.toLocaleUpperCase('tr-TR');
  }

  /* ---------------- v2 mirası (HTML dizesi) ---------------- */

  /* Tam sayı KPI'ları 0'dan hedefe sayar (~600ms, easeOut). */
  function canlandir(kok) {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    (kok || document).querySelectorAll('[data-hedef]').forEach(function (n) {
      var hedef = Number(n.getAttribute('data-hedef'));
      if (!isFinite(hedef) || hedef <= 0) return;
      var basla = null;
      function adim(t) {
        if (basla === null) basla = t;
        var f = Math.min((t - basla) / 600, 1);
        f = 1 - Math.pow(1 - f, 3);
        n.textContent = Math.round(hedef * f).toLocaleString('tr-TR');
        if (f < 1) requestAnimationFrame(adim);
      }
      requestAnimationFrame(adim);
    });
  }

  function rozet(metin, tur) {
    return '<span class="rozet rozet-' + e(tur || 'notr') + '">' +
      e(metin) + '</span>';
  }

  /* plan ∈ {plus, trial, free}; createdAt 3 gün içindeyse "Yeni" eklenir.
     Ad sözlükten (sozluk.js), burada yalnız rozet rengi. */
  var PLAN_ROZET = { plus: 'plus', trial: 'trial', free: 'free' };
  function planRozeti(plan, createdAt) {
    var anahtar = PLAN_ROZET[plan] ? plan : 'free';
    var html = rozet(RY.sozluk ? RY.sozluk.planAdi(anahtar) : anahtar, PLAN_ROZET[anahtar]);
    var d = tarihNesnesi(createdAt);
    if (d && Date.now() - d.getTime() < 3 * 86400 * 1000) {
      html += ' ' + rozet('Yeni', 'yeni');
    }
    return html;
  }

  var ROLLER = { owner: ['Sahip', 'owner'], support: ['Destek', 'support'] };
  function rolRozeti(rol) {
    var r = ROLLER[rol];
    return r ? rozet(r[0], r[1]) : rozet('—', 'notr');
  }
  function rolAdi(rol) { return (ROLLER[rol] || ['—'])[0]; }

  /* iskelet('kpi'|'tablo'|'modul'); argümansız → v2 birleşik (kpi + blok). */
  function iskelet(tur, adet) {
    if (tur === 'kpi') {
      return '<div class="iskelet-kartlar" aria-hidden="true">' +
        '<div class="iskelet iskelet-kart"></div>'.repeat(adet || 4) + '</div>';
    }
    if (tur === 'tablo') {
      var satir = '<tr class="vt-iskelet"><td colspan="99">' +
        '<div class="iskelet iskelet-satir"></div></td></tr>';
      return '<div class="vt" aria-hidden="true"><table><tbody>' +
        satir.repeat(adet || 6) + '</tbody></table></div>';
    }
    if (tur === 'modul') {
      return '<div class="iskelet iskelet-modul" aria-hidden="true">' +
        '<div class="iskelet iskelet-satir"></div>'.repeat(3) + '</div>';
    }
    return '<div class="iskelet-kartlar" aria-hidden="true">' +
      '<div class="iskelet iskelet-kart"></div>'.repeat(4) + '</div>' +
      '<div class="iskelet iskelet-blok" aria-hidden="true"></div>';
  }

  /* bosDurum(metin, {ikon, eylemHtml}) — v2'deki (metin, ekHtml) de çalışır. */
  function bosDurum(metin, sec) {
    if (typeof sec === 'string') sec = { eylemHtml: sec };
    sec = sec || {};
    return '<div class="bos-durum">' +
      (sec.ikon ? ik(sec.ikon, 28) : '<span class="yildiz">✦</span>') +
      '<span>' + e(metin) + '</span>' +
      (sec.eylemHtml ? '<span class="eylem-satir">' + sec.eylemHtml + '</span>'
                     : '') + '</div>';
  }

  function hataDurum(metin, sec) {
    sec = sec || {};
    return '<div class="hata-durum" role="alert">' + ik('uyari', 24) +
      '<span>' + e(metin) + '</span>' +
      '<button class="buton ikincil" type="button" id="' +
      e(sec.kimlik || 'tekrar-dene') + '">' + ik('yenile', 16) +
      'Tekrar dene</button></div>';
  }

  /* modul(baslik, icHtml, kontrolHtml, {alt, kimlik}) */
  function modul(baslik, icHtml, kontrolHtml, sec) {
    sec = sec || {};
    var id = sec.kimlik || ('modul-' + (++sayac));
    return '<section class="modul" aria-labelledby="' + e(id) + '">' +
      '<div class="modul-bas"><div><h2 id="' + e(id) + '">' + e(baslik) +
      '</h2>' + (sec.alt ? '<p>' + e(sec.alt) + '</p>' : '') + '</div>' +
      (kontrolHtml ? '<div class="kontrol">' + kontrolHtml + '</div>' : '') +
      '</div>' + icHtml + '</section>';
  }

  function etiket(metin) {
    return '<span class="modul-etiket">' + e(metin) + '</span>';
  }

  /* ---------------- Yeni HTML yardımcıları ---------------- */

  /* istatistikKarti({ad, deger, delta:{fark, yon, metin}, alt, altin,
     kivilcim:[sayılar], renk}) → HTML. delta.fark sayı ya da hazır dize;
     yon verilmezse fark'ın işaretinden. Kıvılcım canvas'ı DOM'a girince
     kendiliğinden çizilir (MutationObserver → RY.grafik.kivilcim). */
  function istatistikKarti(o) {
    o = o || {};
    var altParcalar = [];
    if (o.delta) {
      var d = o.delta;
      var fark = d.fark;
      var yon = d.yon || (typeof fark === 'number'
        ? (fark > 0 ? 'yukari' : fark < 0 ? 'asagi' : 'duz') : 'duz');
      var ok = yon === 'yukari' ? '▲' : yon === 'asagi' ? '▼' : '◆';
      var farkMetin = typeof fark === 'number'
        ? Math.abs(fark).toLocaleString('tr-TR') : String(fark == null ? '' : fark);
      altParcalar.push('<span class="delta ' + yon + '">' + ok + ' ' +
        e(farkMetin) + '</span>');
      if (d.metin) altParcalar.push('<span>' + e(d.metin) + '</span>');
    }
    if (o.alt) altParcalar.push('<span>' + e(o.alt) + '</span>');
    var kivilcim = '';
    if (Array.isArray(o.kivilcim) && o.kivilcim.length > 1) {
      kivilcim = '<canvas class="kivilcim" aria-hidden="true" data-kivilcim="' +
        e(o.kivilcim.map(Number).join(',')) + '" data-renk="' +
        e(o.renk || (o.altin ? 'gold' : 'lilac')) + '"></canvas>';
    }
    return '<div class="istat-kart"' + (o.kimlik ? ' id="' + e(o.kimlik) + '"' : '') +
      '><span class="ad">' + e(o.ad) + '</span>' +
      '<span class="deger' + (o.altin ? ' altin' : '') + '">' + e(o.deger) +
      '</span>' +
      (altParcalar.length ? '<span class="alt">' + altParcalar.join(' ') +
        '</span>' : '') + kivilcim + '</div>';
  }

  var BANT_IKON = { uyari: 'uyari', hata: 'hata', basari: 'basari', bilgi: 'bilgi' };
  /* bant(metin, tur, {eylemHtml, html:true}) — html:true metni kaçırmaz
     (görünüm zaten e() ile kurmuştur). */
  function bant(metin, tur, sec) {
    sec = sec || {};
    tur = tur || 'bilgi';
    return '<div class="bant ' + e(tur) + '"' +
      (tur === 'hata' ? ' role="alert"' : '') + '>' +
      ik(BANT_IKON[tur] || 'bilgi') +
      '<span class="metin">' + (sec.html ? metin : e(metin)) + '</span>' +
      (sec.eylemHtml ? '<span class="eylem">' + sec.eylemHtml + '</span>' : '') +
      '</div>';
  }

  /* sayfaBaslik({baslik, alt, eylemlerHtml}) — h1[tabindex=-1] rota
     sonrası odağı alır (app.js). */
  function sayfaBaslik(o) {
    o = o || {};
    return '<div class="sayfa-bas"><div><h1 tabindex="-1">' + e(o.baslik) +
      '</h1>' + (o.alt ? '<p>' + e(o.alt) + '</p>' : '') + '</div>' +
      (o.eylemlerHtml ? '<div class="eylemler">' + o.eylemlerHtml + '</div>' : '') +
      '</div>';
  }

  /* Kıvılcımlar: data-kivilcim taşıyan canvas'lar bir kez çizilir. */
  function kivilcimlariCiz(kok) {
    if (!RY.grafik || !RY.grafik.kivilcim) return;
    (kok || document).querySelectorAll('canvas[data-kivilcim]:not([data-cizildi])')
      .forEach(function (c) {
        c.setAttribute('data-cizildi', '1');
        var veri = c.getAttribute('data-kivilcim').split(',')
          .map(Number).filter(isFinite);
        RY.grafik.kivilcim(c, { veri: veri, renk: c.getAttribute('data-renk') });
      });
  }
  if ('MutationObserver' in window) {
    var kivilcimBekle = null;
    new MutationObserver(function () {
      if (kivilcimBekle) return;
      kivilcimBekle = requestAnimationFrame(function () {
        kivilcimBekle = null;
        kivilcimlariCiz(document);
      });
    }).observe(document.documentElement, { childList: true, subtree: true });
  }

  /* ---------------- Veri tablosu ---------------- */

  var ODAKLANABILIR = 'a[href],button:not([disabled]),input:not([disabled]),' +
    'select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';

  function hucreDeger(satirVerisi, s) {
    if (s.deger) return s.deger(satirVerisi);
    return satirVerisi == null ? null : satirVerisi[s.ad];
  }

  /* veriTablosu(opts) → {el, guncelle(satirlar, sayfa), ekle(satirlar, sayfa),
     durum(ad, mesaj), satirlar()}
     opts: kimlik, sutunlar:[{ad, baslik, hizala:'sol'|'sag', siralanir,
       bicim(satir)→html, deger(satir)→ham (yerel sıralama/metin), genislik}],
     anahtar(satir)→id, satirHref(satir)→'#/…' (ilk hücre a[role=link]),
     satirSinif(satir)→'durum-hata'|'durum-uyari'|'durum-pasif'|'',
     siralama:{ad, yon:'asc'|'desc'}, onSirala(ad, yon) (yoksa yerel sıralama),
     sayfa:{daha:bool, onDaha()}, yogunluk:'sik'|'normal', bosMetin, hataMetin,
     onTekrar(), etiket (aria-label). */
  function veriTablosu(o) {
    o = o || {};
    var sutunlar = o.sutunlar || [];
    var kok = el('<div class="vt' + (o.yogunluk === 'sik' ? ' sik' : '') + '"' +
      (o.kimlik ? ' id="' + e(o.kimlik) + '"' : '') + '>' +
      '<table' + (o.etiket ? ' aria-label="' + e(o.etiket) + '"' : '') + '>' +
      '<thead><tr></tr></thead><tbody></tbody></table>' +
      '<div class="vt-sayfa" hidden><span class="bilgi"></span></div>' +
      '<div class="sr-only" aria-live="polite"></div></div>');
    var basTr = kok.querySelector('thead tr');
    var tbody = kok.querySelector('tbody');
    var sayfaCubuk = kok.querySelector('.vt-sayfa');
    var duyuru = kok.querySelector('[aria-live]');
    var siralama = o.siralama ? { ad: o.siralama.ad, yon: o.siralama.yon || 'desc' } : null;
    var satirlar = [];
    var sayfa = o.sayfa || null;
    var durumAd = null;

    function basliklariCiz() {
      basTr.innerHTML = sutunlar.map(function (s) {
        var siniflar = [];
        if (s.hizala === 'sag') siniflar.push('sag', 'sayi');
        var sirali = siralama && siralama.ad === s.ad;
        var ariaSort = sirali
          ? ' aria-sort="' + (siralama.yon === 'asc' ? 'ascending' : 'descending') + '"'
          : (s.siralanir ? ' aria-sort="none"' : '');
        var stil = s.genislik ? ' style="width:' + e(s.genislik) + '"' : '';
        var ic = s.siralanir
          ? '<button type="button" class="vt-sirala" data-ad="' + e(s.ad) + '">' +
            e(s.baslik) + ik('ok-asagi', 12) + '</button>'
          : e(s.baslik);
        return '<th scope="col"' + (siniflar.length ? ' class="' +
          siniflar.join(' ') + '"' : '') + ariaSort + stil + '>' + ic + '</th>';
      }).join('');
    }

    function satirHtml(satirVerisi, i) {
      var id = o.anahtar ? o.anahtar(satirVerisi)
        : (satirVerisi.id != null ? satirVerisi.id
          : satirVerisi.uid != null ? satirVerisi.uid : i);
      var href = o.satirHref ? o.satirHref(satirVerisi) : null;
      var sinif = o.satirSinif ? (o.satirSinif(satirVerisi) || '') : '';
      var hucreler = sutunlar.map(function (s, j) {
        var ic = s.bicim ? s.bicim(satirVerisi) : e(hucreDeger(satirVerisi, s));
        if (ic == null) ic = '';
        if (j === 0 && href) {
          ic = '<a class="vt-baglanti" role="link" href="' + e(href) + '">' +
            ic + '</a>';
        }
        var siniflar = [];
        if (s.hizala === 'sag') siniflar.push('sag', 'sayi');
        if (s.sinif) siniflar.push(s.sinif);
        return '<td' + (siniflar.length ? ' class="' + siniflar.join(' ') + '"' : '') +
          '>' + ic + '</td>';
      }).join('');
      return '<tr data-id="' + e(id) + '"' + (sinif ? ' class="' + e(sinif) + '"' : '') +
        '>' + hucreler + '</tr>';
    }

    function yerelSirala(liste) {
      if (!siralama) return liste;
      var s = sutunlar.filter(function (x) { return x.ad === siralama.ad; })[0];
      if (!s) return liste;
      var yon = siralama.yon === 'asc' ? 1 : -1;
      return liste.slice().sort(function (a, b) {
        var va = hucreDeger(a, s), vb = hucreDeger(b, s);
        if (va == null && vb == null) return 0;
        if (va == null) return 1;
        if (vb == null) return -1;
        if (typeof va === 'number' && typeof vb === 'number') return (va - vb) * yon;
        return kucult(va).localeCompare(kucult(vb), 'tr') * yon;
      });
    }

    function govdeCiz() {
      var liste = o.onSirala ? satirlar : yerelSirala(satirlar);
      tbody.innerHTML = liste.map(satirHtml).join('');
      kok.removeAttribute('aria-busy');
    }

    function sayfaCiz() {
      var bilgi = sayfaCubuk.querySelector('.bilgi');
      var eski = sayfaCubuk.querySelector('.buton');
      if (eski) eski.remove();
      if (!satirlar.length && !(sayfa && sayfa.daha)) {
        sayfaCubuk.hidden = true;
        return;
      }
      sayfaCubuk.hidden = false;
      bilgi.textContent = satirlar.length.toLocaleString('tr-TR') + ' satır' +
        (sayfa && sayfa.daha ? ' · devamı var' : '');
      if (sayfa && sayfa.daha) {
        var d = el('<button type="button" class="buton ikincil kucuk">' +
          ik('ok-asagi', 14) + 'Daha fazla</button>');
        d.addEventListener('click', function () {
          d.classList.add('mesgul');
          d.disabled = true;
          Promise.resolve(sayfa.onDaha && sayfa.onDaha()).catch(function () {})
            .then(function () { d.classList.remove('mesgul'); d.disabled = false; });
        });
        sayfaCubuk.appendChild(d);
      }
    }

    function guncelle(yeni, yeniSayfa) {
      satirlar = Array.isArray(yeni) ? yeni : [];
      if (yeniSayfa !== undefined) sayfa = yeniSayfa;
      durumAd = null;
      basliklariCiz();
      if (!satirlar.length) {
        durum('bos');
        // Arama modunda eşitlik süzgeçleri sayfa içinde uygulanır: boş
        // sayfa ama imleç dolu olabilir — "Daha fazla" gizlenmemeli.
        if (sayfa && sayfa.daha) { sayfaCiz(); sayfaCubuk.hidden = false; }
        return;
      }
      govdeCiz();
      sayfaCiz();
    }

    function ekle(yeni, yeniSayfa) {
      yeni = Array.isArray(yeni) ? yeni : [];
      if (yeniSayfa !== undefined) sayfa = yeniSayfa;
      if (durumAd) { guncelle(yeni, sayfa); return; }
      var basla = satirlar.length;
      satirlar = satirlar.concat(yeni);
      tbody.insertAdjacentHTML('beforeend', yeni.map(function (s, i) {
        return satirHtml(s, basla + i);
      }).join(''));
      sayfaCiz();
      duyuru.textContent = yeni.length + ' satır daha yüklendi';
    }

    /* durum('yukleniyor'|'bos'|'hata'|null, mesaj) */
    function durum(ad, mesaj) {
      durumAd = ad || null;
      var kolon = Math.max(sutunlar.length, 1);
      if (!ad) { govdeCiz(); sayfaCiz(); return; }
      if (ad === 'yukleniyor') {
        kok.setAttribute('aria-busy', 'true');
        var tekSatir = '<tr class="vt-iskelet" aria-hidden="true"><td colspan="' + kolon +
          '"><div class="iskelet iskelet-satir"></div></td></tr>';
        tbody.innerHTML = tekSatir.repeat(6);
        sayfaCubuk.hidden = true;
        return;
      }
      kok.removeAttribute('aria-busy');
      var ic = ad === 'hata'
        ? hataDurum(mesaj || o.hataMetin || 'Veri alınamadı.',
                    { kimlik: 'vt-tekrar-' + (++sayac) })
        : bosDurum(mesaj || o.bosMetin || 'Kayıt yok');
      tbody.innerHTML = '<tr class="vt-durum"><td colspan="' + kolon + '">' + ic +
        '</td></tr>';
      var tekrar = tbody.querySelector('.hata-durum .buton');
      if (tekrar) {
        tekrar.addEventListener('click', function () {
          if (o.onTekrar) o.onTekrar();
        });
      }
      sayfaCubuk.hidden = true;
    }

    /* Sıralama düğmeleri */
    basTr.addEventListener('click', function (ev) {
      var d = ev.target.closest('.vt-sirala');
      if (!d) return;
      var ad = d.getAttribute('data-ad');
      // `tekYon`: sunucu yalnız DESC sıralıyorsa ikinci tık "ascending"
      // İLAN EDİLMEZ (ekran okuyucuya yalan olurdu) — sütun değişir, yön
      // sabit kalır.
      var yon = (!o.tekYon && siralama && siralama.ad === ad && siralama.yon === 'desc')
        ? 'asc' : 'desc';
      siralama = { ad: ad, yon: yon };
      basliklariCiz();
      if (o.onSirala) o.onSirala(ad, yon);
      else if (!durumAd) govdeCiz();
      // Yeniden çizilen başlıkta odağı koru.
      var yeni = basTr.querySelector('.vt-sirala[data-ad="' + ad + '"]');
      if (yeni) yeni.focus();
    });

    /* Klavye: ↑/↓ satır bağlantıları arasında, Home/End uçlar, Space izler. */
    kok.addEventListener('keydown', function (ev) {
      var a = ev.target.closest('a.vt-baglanti');
      if (!a) return;
      var baglar = Array.prototype.slice.call(tbody.querySelectorAll('a.vt-baglanti'));
      var i = baglar.indexOf(a);
      var hedef = null;
      if (ev.key === 'ArrowDown') hedef = baglar[i + 1];
      else if (ev.key === 'ArrowUp') hedef = baglar[i - 1];
      else if (ev.key === 'Home') hedef = baglar[0];
      else if (ev.key === 'End') hedef = baglar[baglar.length - 1];
      else if (ev.key === ' ') { ev.preventDefault(); a.click(); return; }
      if (hedef) { ev.preventDefault(); hedef.focus(); }
    });

    basliklariCiz();
    return {
      el: kok,
      guncelle: guncelle,
      ekle: ekle,
      durum: durum,
      satirlar: function () { return satirlar.slice(); },
      siralama: function () { return siralama ? Object.assign({}, siralama) : null; }
    };
  }

  /* ---------------- Modal / yan panel ---------------- */

  var diyaloglar = [];

  function inertGuncelle() {
    var ust = diyaloglar[diyaloglar.length - 1];
    Array.prototype.forEach.call(document.body.children, function (c) {
      if (c.classList.contains('toast-kap') || c.classList.contains('gokyuzu') ||
          c.tagName === 'SCRIPT') return;
      var acikKalsin = ust ? c === ust.perde : true;
      if (acikKalsin) {
        c.inert = false;
        c.removeAttribute('inert');
        c.removeAttribute('aria-hidden');
      } else {
        c.inert = true;
        c.setAttribute('inert', '');
        c.setAttribute('aria-hidden', 'true');
      }
    });
    document.body.classList.toggle('modal-acik', diyaloglar.length > 0);
  }

  function gorunur(n) {
    return !!(n.offsetWidth || n.offsetHeight || n.getClientRects().length);
  }

  var EYLEM_SINIF = { birincil: 'buton', ikincil: 'buton ikincil',
                      tehlike: 'buton tehlike', sade: 'buton sade' };

  /* diyalog({baslik|etiket, icerik, eylemler, genislik, sinif, onKapat,
     odak, zorunlu, basliksiz}, tur:'modal'|'yan') */
  function diyalog(o, tur) {
    o = o || {};
    var yan = tur === 'yan';
    var perde = el('<div class="modal-perde' + (yan ? ' yan' : '') +
      (o.sinif ? ' ' + e(o.sinif) + '-perde' : '') + '"></div>');
    var kutu = el('<div class="modal' + (yan ? ' yan-panel' : '') +
      (o.sinif ? ' ' + e(o.sinif) : '') +
      '" role="dialog" aria-modal="true" tabindex="-1"></div>');
    if (o.genislik) {
      kutu.style.setProperty('--modal-genislik',
        typeof o.genislik === 'number' ? o.genislik + 'px' : String(o.genislik));
    }
    var basId = 'diyalog-' + (++sayac);
    if (o.baslik) {
      kutu.setAttribute('aria-labelledby', basId);
      kutu.insertAdjacentHTML('beforeend', '<div class="modal-bas"' +
        (o.basliksiz ? ' hidden' : '') + '><h2 id="' + basId + '">' + e(o.baslik) +
        '</h2><button type="button" class="ust-ikon kapat" aria-label="Kapat">' +
        ik('kapat', 18) + '</button></div>');
    } else if (o.etiket) {
      kutu.setAttribute('aria-label', o.etiket);
    }
    var govde = el('<div class="modal-govde"></div>');
    icerikYaz(govde, o.icerik);
    kutu.appendChild(govde);

    var eylemKutusu = null;
    if (o.eylemler && o.eylemler.length) {
      eylemKutusu = el('<div class="modal-eylemler"></div>');
      o.eylemler.forEach(function (ey) {
        var d = el('<button type="button" class="' +
          (EYLEM_SINIF[ey.tur] || EYLEM_SINIF.ikincil) +
          (ey.sol ? ' sol' : '') + '"' +
          (ey.kimlik ? ' data-eylem="' + e(ey.kimlik) + '"' : '') +
          (ey.pasif ? ' disabled' : '') + '>' +
          (ey.ikon ? ik(ey.ikon, 16) : '') + e(ey.metin) + '</button>');
        d.addEventListener('click', function () {
          if (ey.onTikla) ey.onTikla(kapat, d);
          else kapat();
        });
        eylemKutusu.appendChild(d);
      });
      kutu.appendChild(eylemKutusu);
    }
    perde.appendChild(kutu);

    var onceki = null, acik = false, sonuc;
    var api = { perde: perde, el: kutu, govde: govde };

    function odaklanabilirler() {
      return Array.prototype.filter.call(kutu.querySelectorAll(ODAKLANABILIR), gorunur);
    }

    function tusla(ev) {
      if (ev.key === 'Escape' && !o.zorunlu) { ev.stopPropagation(); kapat(); return; }
      if (ev.key !== 'Tab') return;
      var liste = odaklanabilirler();
      if (!liste.length) { ev.preventDefault(); kutu.focus(); return; }
      var ilk = liste[0], son = liste[liste.length - 1];
      if (ev.shiftKey && (document.activeElement === ilk || document.activeElement === kutu)) {
        ev.preventDefault(); son.focus();
      } else if (!ev.shiftKey && document.activeElement === son) {
        ev.preventDefault(); ilk.focus();
      }
    }

    perde.addEventListener('keydown', tusla);
    perde.addEventListener('mousedown', function (ev) {
      if (ev.target === perde && !o.zorunlu) perde.__disTikla = true;
      else perde.__disTikla = false;
    });
    perde.addEventListener('click', function (ev) {
      if (ev.target === perde && perde.__disTikla) kapat();
      perde.__disTikla = false;
    });
    var kapatDugme = kutu.querySelector('.modal-bas .kapat');
    if (kapatDugme) kapatDugme.addEventListener('click', function () { kapat(); });

    function ac() {
      if (acik) return api;
      acik = true;
      onceki = document.activeElement;
      document.body.appendChild(perde);
      diyaloglar.push(api);
      inertGuncelle();
      requestAnimationFrame(function () { perde.classList.add('acik'); });
      var hedef = o.odak ? kutu.querySelector(o.odak) : null;
      if (!hedef) {
        var liste = odaklanabilirler().filter(function (n) {
          return !n.classList.contains('kapat');
        });
        hedef = liste[0] || kutu;
      }
      hedef.focus();
      if (o.onAc) o.onAc(api);
      return api;
    }

    function kapat(deger) {
      if (!acik) return;
      acik = false;
      sonuc = deger;
      var i = diyaloglar.indexOf(api);
      if (i >= 0) diyaloglar.splice(i, 1);
      inertGuncelle();
      perde.remove();
      if (onceki && typeof onceki.focus === 'function' && document.contains(onceki)) {
        onceki.focus();
      }
      if (o.onKapat) o.onKapat(sonuc);
    }

    api.ac = ac;
    api.kapat = kapat;
    api.acikMi = function () { return acik; };
    api.eylem = function (kimlik) {
      return eylemKutusu ? eylemKutusu.querySelector('[data-eylem="' + kimlik + '"]') : null;
    };
    return api;
  }

  function icerikYaz(hedef, icerik) {
    hedef.innerHTML = '';
    if (icerik == null) return;
    var v = typeof icerik === 'function' ? icerik() : icerik;
    if (v == null) return;
    if (typeof v === 'string') hedef.innerHTML = v;
    else if (v.nodeType) hedef.appendChild(v);
  }

  function modal(o) { return diyalog(o, 'modal'); }
  function yanPanel(o) { return diyalog(o, 'yan'); }

  /* onayla({baslik, mesaj, gerekce, yazili:'SİL'|null, tehlike, onaylaMetin,
     vazgecMetin, aciklama}) → Promise<{gerekce}|null> */
  function onayla(o) {
    o = o || {};
    return new Promise(function (coz) {
      var gId = 'gerekce-' + (++sayac), yId = 'yazili-' + sayac;
      var govde = el('<div class="form"></div>');
      if (o.mesaj) govde.insertAdjacentHTML('beforeend', '<p>' + e(o.mesaj) + '</p>');
      if (o.aciklama) {
        govde.insertAdjacentHTML('beforeend', '<p class="aciklama">' + e(o.aciklama) + '</p>');
      }
      if (o.gerekce) {
        govde.insertAdjacentHTML('beforeend', '<div class="form-alan"><label for="' +
          gId + '">Gerekçe<span class="zorunlu" aria-hidden="true">*</span></label>' +
          '<textarea class="girdi" id="' + gId + '" rows="3" maxlength="300" ' +
          'aria-required="true" aria-describedby="' + gId + '-y" placeholder="' +
          e(o.gerekceYertutucu || 'Denetim izine yazılır') + '"></textarea>' +
          '<div class="form-yardim" id="' + gId + '-y">Neden yaptığını bir cümleyle yaz; ' +
          'denetim izinde görünür.</div></div>');
      }
      if (o.yazili) {
        govde.insertAdjacentHTML('beforeend', '<div class="form-alan"><label for="' +
          yId + '">Onaylamak için <b class="mono">' + e(o.yazili) + '</b> yaz</label>' +
          '<input class="girdi" id="' + yId + '" autocomplete="off" spellcheck="false" ' +
          'aria-required="true"></div>');
      }
      var sonuc = null;
      var m = modal({
        baslik: o.baslik || 'Emin misin?',
        icerik: govde,
        genislik: o.genislik || 460,
        odak: o.gerekce ? '#' + gId : (o.yazili ? '#' + yId : null),
        eylemler: [
          { metin: o.vazgecMetin || 'Vazgeç', tur: 'ikincil',
            onTikla: function (kapat) { kapat(); } },
          { metin: o.onaylaMetin || (o.tehlike ? 'Evet, yap' : 'Onayla'),
            tur: o.tehlike ? 'tehlike' : 'birincil', kimlik: 'onayla',
            onTikla: function (kapat) {
              if (!gecerli()) return;
              var g = govde.querySelector('#' + gId);
              sonuc = { gerekce: g ? g.value.trim() : '' };
              kapat();
            } }
        ],
        onKapat: function () { coz(sonuc); }
      });
      var dugme = m.eylem('onayla');
      function gecerli() {
        var g = govde.querySelector('#' + gId);
        var y = govde.querySelector('#' + yId);
        // Sunucu gerekçe için min 3 karakter ister (DisableRequest,
        // DeleteRequest); kapı burada — 422 ham gövdesi kullanıcıya gitmez.
        if (g && g.value.trim().length < 3) return false;
        if (y && y.value.trim() !== String(o.yazili)) return false;
        return true;
      }
      function tazele() { dugme.disabled = !gecerli(); }
      govde.addEventListener('input', tazele);
      tazele();
      m.ac();
    });
  }

  /* ---------------- Toast ---------------- */

  var TOAST_IKON = { basari: 'basari', uyari: 'uyari', hata: 'hata', bilgi: 'bilgi' };

  function toastKap(acil) {
    var id = acil ? 'toast-acil' : 'toast-kibar';
    var kap = document.getElementById(id);
    if (!kap) {
      kap = el('<div id="' + id + '" class="toast-kap' + (acil ? ' acil' : '') +
        '" role="' + (acil ? 'alert' : 'status') + '" aria-live="' +
        (acil ? 'assertive' : 'polite') + '" aria-atomic="false"></div>');
      document.body.appendChild(kap);
    }
    return kap;
  }

  /* toast(metin, tur:'basari'|'uyari'|'hata'|'bilgi', {sure, eylem:{metin,
     onTikla}}) → {el, kapat}. hata → assertive kap; diğerleri polite. */
  function toast(metin, tur, sec) {
    tur = TOAST_IKON[tur] ? tur : 'bilgi';
    sec = sec || {};
    var acil = tur === 'hata';
    var kap = toastKap(acil);
    var t = el('<div class="toast ' + tur + '">' + ik(TOAST_IKON[tur], 18) +
      '<span class="metin">' + e(metin) + '</span>' +
      (sec.eylem ? '<button type="button" class="buton sade kucuk">' +
        e(sec.eylem.metin) + '</button>' : '') +
      '<button type="button" class="ust-ikon kapat" aria-label="Kapat">' +
      ik('kapat', 16) + '</button></div>');
    var sure = sec.sure != null ? sec.sure : (acil ? 7000 : 4000);
    var zamanlayici = null, kapali = false;
    function kapat() {
      if (kapali) return;
      kapali = true;
      clearTimeout(zamanlayici);
      t.classList.add('kapaniyor');
      setTimeout(function () { t.remove(); }, 180);
    }
    function kur() {
      clearTimeout(zamanlayici);
      if (sure > 0) zamanlayici = setTimeout(kapat, sure);
    }
    t.querySelector('.kapat').addEventListener('click', kapat);
    if (sec.eylem) {
      t.querySelector('.buton.sade').addEventListener('click', function () {
        if (sec.eylem.onTikla) sec.eylem.onTikla();
        kapat();
      });
    }
    t.addEventListener('mouseenter', function () { clearTimeout(zamanlayici); });
    t.addEventListener('mouseleave', kur);
    t.addEventListener('focusin', function () { clearTimeout(zamanlayici); });
    t.addEventListener('focusout', kur);
    kap.appendChild(t);
    // En fazla 4 toast; en eskisi düşer.
    while (kap.children.length > 4) kap.firstElementChild.remove();
    kur();
    return { el: t, kapat: kapat };
  }

  /* ---------------- Süzgeç çipleri ---------------- */

  /* filtreCipleri({filtreler:[{ad, etiket, secenekler:[{deger, etiket}],
     coklu, altin}], deger:{ad:deger}, onDegis(deger)}) → el
     el.deger() → kopya; el.ayarla(deger) → yeniden çizer (onDegis çağırmaz). */
  function filtreCipleri(o) {
    o = o || {};
    var filtreler = o.filtreler || [];
    var deger = Object.assign({}, o.deger || {});
    var kok = el('<div class="filtre-cipleri" role="group" aria-label="' +
      e(o.etiket || 'Süzgeçler') + '"></div>');

    function basili(f, s) {
      var v = deger[f.ad];
      if (f.coklu) return Array.isArray(v) && v.map(String).indexOf(String(s.deger)) >= 0;
      return v != null && String(v) === String(s.deger);
    }

    function ciz() {
      kok.innerHTML = filtreler.map(function (f) {
        return '<span class="cip-grup" role="group" aria-label="' + e(f.etiket || f.ad) +
          '">' + (f.etiket ? '<span class="grup-ad" aria-hidden="true">' + e(f.etiket) +
          '</span>' : '') +
          (f.secenekler || []).map(function (s) {
            return '<button type="button" class="adm-cip' + (f.altin ? ' altin' : '') +
              '" data-filtre="' + e(f.ad) + '" data-deger="' + e(s.deger) +
              '" aria-pressed="' + (basili(f, s) ? 'true' : 'false') + '">' +
              (s.ikon ? ik(s.ikon, 14) : '') + e(s.etiket) + '</button>';
          }).join('') + '</span>';
      }).join('');
    }

    kok.addEventListener('click', function (ev) {
      var d = ev.target.closest('.adm-cip');
      if (!d) return;
      var ad = d.getAttribute('data-filtre');
      var v = d.getAttribute('data-deger');
      var f = filtreler.filter(function (x) { return x.ad === ad; })[0];
      if (!f) return;
      if (f.coklu) {
        var liste = Array.isArray(deger[ad]) ? deger[ad].map(String) : [];
        var i = liste.indexOf(v);
        if (i >= 0) liste.splice(i, 1); else liste.push(v);
        deger[ad] = liste.length ? liste : undefined;
      } else {
        deger[ad] = (deger[ad] != null && String(deger[ad]) === v) ? undefined : v;
      }
      ciz();
      var yeni = kok.querySelector('[data-filtre="' + ad + '"][data-deger="' +
        v.replace(/"/g, '\\"') + '"]');
      if (yeni) yeni.focus();
      if (o.onDegis) o.onDegis(kok.deger());
    });

    kok.deger = function () { return Object.assign({}, deger); };
    kok.ayarla = function (yeni) { deger = Object.assign({}, yeni || {}); ciz(); };
    ciz();
    return kok;
  }

  /* ---------------- Tek seçimli çipler / dönem seçici ---------------- */

  /* secimCipleri({etiket, grupAdi, secenekler:[{deger, etiket, ipucu}],
     deger, altin, bitisik, kimlik, onDegis(deger)}) → el; el.deger(),
     el.ayarla(deger) (onDegis çağırmaz).

     NEDEN ayrı bileşen: tek seçimli süzgeçler (dönem, ortam) her görünümde
     elle yazılmış `aria-pressed` düğmeleriydi ve davranışları ayrışmıştı;
     etiketler de "30g" / "30 gün" diye ikiye bölünmüştü. Gelir'deki ortam
     çipi radyo gibi görünüp ("Üretim" | "Test alımlarını göster") anahtar
     gibi okunuyordu. Tek seçim her zaman bir değer taşır, o yüzden ARIA
     radyo grubu: ok tuşları seçimi taşır, seçili olan tek sekme durağıdır.
     `bitisik` iki seçenekli "biri ya da öteki" kontrollerini birleşik bir
     şerit olarak çizer — iki ayrı çip gibi görünüp ikisinin birden açık
     olabileceği izlenimini vermesin. */
  function secimCipleri(o) {
    o = o || {};
    var secenekler = o.secenekler || [];
    var deger = o.deger != null ? String(o.deger)
      : (secenekler[0] ? String(secenekler[0].deger) : '');
    var kok = el('<span class="cip-grup secim-cipleri" role="radiogroup" aria-label="' +
      e(o.etiket || o.grupAdi || 'Seçim') + '"' +
      (o.kimlik ? ' id="' + e(o.kimlik) + '"' : '') + '></span>');

    function ciz() {
      var dugmeler = secenekler.map(function (s) {
        var secili = String(s.deger) === deger;
        return '<button type="button" class="adm-cip' + (o.altin ? ' altin' : '') +
          '" role="radio" aria-checked="' + (secili ? 'true' : 'false') + '" tabindex="' +
          (secili ? '0' : '-1') + '" data-deger="' + e(s.deger) + '"' +
          (s.ipucu ? ' title="' + e(s.ipucu) + '"' : '') + '>' + e(s.etiket) + '</button>';
      }).join('');
      kok.innerHTML = (o.grupAdi ? '<span class="grup-ad" aria-hidden="true">' + e(o.grupAdi) + '</span>' : '') +
        (o.bitisik ? '<span class="segment">' + dugmeler + '</span>' : dugmeler);
    }

    function odakla() {
      Array.prototype.forEach.call(kok.querySelectorAll('[role="radio"]'), function (d) {
        if (d.getAttribute('data-deger') === deger) d.focus();
      });
    }

    function sec(v) {
      v = String(v);
      if (v === deger) return;
      deger = v;
      ciz();
      odakla();
      if (o.onDegis) o.onDegis(deger);
    }

    kok.addEventListener('click', function (ev) {
      var d = ev.target.closest('[role="radio"]');
      if (d) sec(d.getAttribute('data-deger'));
    });
    kok.addEventListener('keydown', function (ev) {
      var sira = secenekler.map(function (s) { return String(s.deger); });
      var i = sira.indexOf(deger);
      var hedef = null;
      if (ev.key === 'ArrowRight' || ev.key === 'ArrowDown') hedef = sira[(i + 1) % sira.length];
      else if (ev.key === 'ArrowLeft' || ev.key === 'ArrowUp') hedef = sira[(i - 1 + sira.length) % sira.length];
      else if (ev.key === 'Home') hedef = sira[0];
      else if (ev.key === 'End') hedef = sira[sira.length - 1];
      if (hedef != null) { ev.preventDefault(); sec(hedef); }
    });

    kok.deger = function () { return deger; };
    kok.ayarla = function (v) { deger = String(v); ciz(); };
    ciz();
    return kok;
  }

  /* Dönem seçici: her görünümde AYNI etiket ("7 gün / 30 gün / 90 gün"),
     aynı yer (sayfa başlığının hemen altındaki süzgeç şeridi), aynı
     davranış (anında uygulanır, adrese sessizce yazılır). `notlar` bir
     seçeneğin neyi farklı ölçtüğünü ipucu olarak söyler — örn. ekonomi
     tablosu 7 günü hesaplamıyorsa bu seçimin üstünde yazılı durur. */
  function donemSecici(o) {
    o = o || {};
    var notlar = o.notlar || {};
    return secimCipleri({
      kimlik: o.kimlik, etiket: 'Dönem', grupAdi: 'Dönem', altin: true,
      secenekler: (o.secenekler || [7, 30, 90]).map(function (g) {
        return { deger: g, etiket: g + ' gün', ipucu: notlar[g] };
      }),
      deger: o.deger,
      onDegis: function (v) { if (o.onDegis) o.onDegis(Number(v)); }
    });
  }

  /* ---------------- Yarışsız veri bölgesi ---------------- */

  /* tazeleyici(baglam) → yeni() → {sinyal, gecerli()}.

     NEDEN: süzgeç değişince yalnız veri bölgesi yeniden çekiliyor; kullanıcı
     7 → 30 → 90'a hızlı basarsa üç istek yarışır ve YAVAŞ gelen eski cevap
     yenisinin üstüne çizer — ekranda "90 gün" basılıyken 7 günün sayıları
     durur. Her `yeni()` bir öncekini iptal eder; `gecerli()` hem bu isteğin
     hâlâ son istek olduğunu hem de görünümün hâlâ ekranda olduğunu
     (router bağlamı, app.js) sorar. Çizimden hemen önce bakılır. */
  function tazeleyici(baglam) {
    var son = null;
    return function () {
      if (son) son.abort();
      var d = son = new AbortController();
      var ust = baglam && baglam.sinyal;
      if (ust) {
        if (ust.aborted) d.abort();
        else ust.addEventListener('abort', function () { d.abort(); }, { once: true });
      }
      return {
        sinyal: d.signal,
        gecerli: function () {
          return !d.signal.aborted && (!baglam || !baglam.aktif || baglam.aktif());
        }
      };
    };
  }

  /* ---------------- Sekmeler ---------------- */

  /* sekmeler({kimlik, sekmeler:[{ad, etiket, icerik()→el|html, sayac}],
     aktif, onDegis(ad), etiket}) → {el, sec(ad), panel(ad), yenile(ad)}.
     İçerik ilk seçimde tembel üretilir; yenile(ad) yeniden üretir. */
  function sekmeler(o) {
    o = o || {};
    var kimlik = o.kimlik || ('sekme-' + (++sayac));
    var liste = o.sekmeler || [];
    var kok = el('<div class="sekmeler-kap"></div>');
    var tablist = el('<div class="sekmeler" role="tablist" aria-label="' +
      e(o.etiket || 'Sekmeler') + '"></div>');
    kok.appendChild(tablist);
    var paneller = {}, tablar = {}, yuklendi = {};
    var aktif = null;

    liste.forEach(function (s) {
      var tabId = kimlik + '-tab-' + s.ad, panelId = kimlik + '-panel-' + s.ad;
      var tab = el('<button type="button" role="tab" id="' + e(tabId) +
        '" aria-controls="' + e(panelId) + '" aria-selected="false" tabindex="-1">' +
        e(s.etiket) + (s.sayac != null ? '<span class="sayac">' + e(s.sayac) +
        '</span>' : '') + '</button>');
      var panel = el('<div class="sekme-panel" role="tabpanel" id="' + e(panelId) +
        '" aria-labelledby="' + e(tabId) + '" tabindex="0" hidden></div>');
      tab.addEventListener('click', function () { sec(s.ad, false); });
      tablist.appendChild(tab);
      kok.appendChild(panel);
      tablar[s.ad] = tab;
      paneller[s.ad] = panel;
    });

    function sec(ad, odakla) {
      if (!tablar[ad]) return;
      var degisti = aktif !== ad;
      aktif = ad;
      liste.forEach(function (s) {
        var secili = s.ad === ad;
        tablar[s.ad].setAttribute('aria-selected', secili ? 'true' : 'false');
        tablar[s.ad].tabIndex = secili ? 0 : -1;
        paneller[s.ad].hidden = !secili;
      });
      if (!yuklendi[ad]) yenile(ad);
      if (odakla) tablar[ad].focus();
      if (degisti && o.onDegis) o.onDegis(ad);
    }

    function yenile(ad) {
      var s = liste.filter(function (x) { return x.ad === ad; })[0];
      if (!s) return;
      yuklendi[ad] = true;
      icerikYaz(paneller[ad], s.icerik);
    }

    tablist.addEventListener('keydown', function (ev) {
      var sira = liste.map(function (s) { return s.ad; });
      var i = sira.indexOf(aktif);
      var hedef = null;
      if (ev.key === 'ArrowRight') hedef = sira[(i + 1) % sira.length];
      else if (ev.key === 'ArrowLeft') hedef = sira[(i - 1 + sira.length) % sira.length];
      else if (ev.key === 'Home') hedef = sira[0];
      else if (ev.key === 'End') hedef = sira[sira.length - 1];
      if (hedef) { ev.preventDefault(); sec(hedef, true); }
    });

    sec(o.aktif && tablar[o.aktif] ? o.aktif : (liste[0] && liste[0].ad), false);
    return {
      el: kok, sec: function (ad) { sec(ad, false); },
      panel: function (ad) { return paneller[ad]; }, yenile: yenile,
      aktif: function () { return aktif; }
    };
  }

  /* ---------------- Form ---------------- */

  /* form({alanlar:[{ad, etiket, tur:'text'|'number'|'textarea'|'select'|
     'email'|'password'|'date'|'checkbox', zorunlu, min, max, adim, yardim,
     secenekler:[{deger, etiket}], deger, yertutucu, dogrula(deger)→hata|null,
     satirIci}], gonderMetin, iptal:{metin, onTikla}, onGonder(degerler, ctx)})
     → {el, hata(alan|null, metin), temizle(), mesgul(bool), degerler(),
        ayarla(degerler)} */
  function form(o) {
    o = o || {};
    var alanlar = o.alanlar || [];
    var kimlik = 'form-' + (++sayac);
    var f = el('<form class="form" novalidate></form>');
    var ozet = el('<div class="bant hata form-ozet" role="alert" tabindex="-1" hidden>' +
      ik('uyari') + '<div class="metin"><b class="ozet-baslik"></b><ul></ul></div></div>');
    f.appendChild(ozet);
    var kontroller = {};

    alanlar.forEach(function (a) {
      var id = kimlik + '-' + a.ad, yId = id + '-yardim', hId = id + '-hata';
      var aciklama = [];
      if (a.yardim) aciklama.push(yId);
      aciklama.push(hId);
      var ortak = ' class="girdi" id="' + e(id) + '" name="' + e(a.ad) + '"' +
        (a.zorunlu ? ' aria-required="true"' : '') +
        ' aria-describedby="' + aciklama.join(' ') + '"' +
        (a.yertutucu ? ' placeholder="' + e(a.yertutucu) + '"' : '') +
        (a.otomatik ? ' autocomplete="' + e(a.otomatik) + '"' : '') +
        (a.pasif ? ' disabled' : '');
      var kontrol;
      if (a.tur === 'textarea') {
        kontrol = '<textarea' + ortak + ' rows="' + (a.satir || 3) + '"' +
          (a.max ? ' maxlength="' + Number(a.max) + '"' : '') + '>' +
          e(a.deger == null ? '' : a.deger) + '</textarea>';
      } else if (a.tur === 'select') {
        kontrol = '<select' + ortak + '>' + (a.secenekler || []).map(function (s) {
          return '<option value="' + e(s.deger) + '"' +
            (a.deger != null && String(a.deger) === String(s.deger) ? ' selected' : '') +
            '>' + e(s.etiket) + '</option>';
        }).join('') + '</select>';
      } else if (a.tur === 'checkbox') {
        kontrol = '<label class="anahtar"><input type="checkbox" id="' + e(id) +
          '" name="' + e(a.ad) + '"' + (a.deger ? ' checked' : '') +
          ' aria-describedby="' + aciklama.join(' ') + '"><span>' +
          e(a.etiket) + '</span></label>';
      } else {
        kontrol = '<input' + ortak + ' type="' + e(a.tur || 'text') + '"' +
          (a.min != null ? ' min="' + Number(a.min) + '"' : '') +
          (a.max != null ? ' max="' + Number(a.max) + '"' : '') +
          (a.adim != null ? ' step="' + e(a.adim) + '"' : '') +
          (a.deger != null ? ' value="' + e(a.deger) + '"' : '') + '>';
      }
      var alanHtml = '<div class="form-alan" data-alan="' + e(a.ad) + '">' +
        (a.tur === 'checkbox' ? '' : '<label for="' + e(id) + '">' + e(a.etiket) +
          (a.zorunlu ? '<span class="zorunlu" aria-hidden="true">*</span>' : '') +
          '</label>') +
        kontrol +
        (a.yardim ? '<div class="form-yardim" id="' + yId + '">' + e(a.yardim) + '</div>' : '') +
        '<div class="form-hata" id="' + hId + '" role="alert"></div></div>';
      f.insertAdjacentHTML('beforeend', alanHtml);
      kontroller[a.ad] = f.querySelector('#' + CSS.escape(id));
    });

    var eylemler = el('<div class="eylem-satir"></div>');
    var gonder = el('<button type="submit" class="buton">' +
      e(o.gonderMetin || 'Kaydet') + '</button>');
    eylemler.appendChild(gonder);
    if (o.iptal) {
      var iptal = el('<button type="button" class="buton ikincil">' +
        e(o.iptal.metin || 'Vazgeç') + '</button>');
      iptal.addEventListener('click', function () { if (o.iptal.onTikla) o.iptal.onTikla(); });
      eylemler.appendChild(iptal);
    }
    f.appendChild(eylemler);

    var hatalar = {};
    function ozetCiz() {
      var adlar = Object.keys(hatalar);
      if (!adlar.length) { ozet.hidden = true; return; }
      ozet.querySelector('.ozet-baslik').textContent = hatalar.__genel
        ? hatalar.__genel
        : (adlar.length === 1 ? '1 alan düzeltilmeli' : adlar.length + ' alan düzeltilmeli');
      ozet.querySelector('ul').innerHTML = adlar.filter(function (ad) {
        return ad !== '__genel';
      }).map(function (ad) {
        var a = alanlar.filter(function (x) { return x.ad === ad; })[0];
        return '<li><a href="#' + e(kimlik + '-' + ad) + '">' +
          e((a ? a.etiket : ad) + ': ' + hatalar[ad]) + '</a></li>';
      }).join('');
      ozet.hidden = false;
    }
    ozet.addEventListener('click', function (ev) {
      var a = ev.target.closest('a[href^="#"]');
      if (!a) return;
      ev.preventDefault();
      var hedef = f.querySelector('#' + CSS.escape(a.getAttribute('href').slice(1)));
      if (hedef) hedef.focus();
    });

    function hata(alan, metin) {
      if (!alan) {
        if (metin) hatalar.__genel = metin; else delete hatalar.__genel;
        ozetCiz();
        if (metin) ozet.focus();
        return;
      }
      var k = kontroller[alan];
      var kutu = f.querySelector('.form-alan[data-alan="' + alan + '"] .form-hata');
      if (metin) hatalar[alan] = metin; else delete hatalar[alan];
      if (kutu) kutu.textContent = metin || '';
      if (k) {
        if (metin) k.setAttribute('aria-invalid', 'true');
        else k.removeAttribute('aria-invalid');
      }
      ozetCiz();
    }

    function temizle() {
      Object.keys(hatalar).forEach(function (ad) {
        if (ad !== '__genel') hata(ad, null);
      });
      delete hatalar.__genel;
      ozetCiz();
    }

    function mesgul(v) {
      gonder.classList.toggle('mesgul', !!v);
      gonder.disabled = !!v;
      f.setAttribute('aria-busy', v ? 'true' : 'false');
    }

    function degerler() {
      var d = {};
      alanlar.forEach(function (a) {
        var k = kontroller[a.ad];
        if (!k) return;
        if (a.tur === 'checkbox') d[a.ad] = !!k.checked;
        else if (a.tur === 'number') d[a.ad] = k.value === '' ? null : Number(k.value);
        else d[a.ad] = k.value.trim();
      });
      return d;
    }

    function ayarla(d) {
      Object.keys(d || {}).forEach(function (ad) {
        var k = kontroller[ad];
        if (!k) return;
        var a = alanlar.filter(function (x) { return x.ad === ad; })[0];
        if (a && a.tur === 'checkbox') k.checked = !!d[ad];
        else k.value = d[ad] == null ? '' : d[ad];
      });
    }

    function dogrula(d) {
      var ilkHatali = null;
      alanlar.forEach(function (a) {
        var v = d[a.ad];
        var m = null;
        var bos = v == null || v === '' || (a.tur === 'checkbox' && !v && a.zorunlu);
        if (a.zorunlu && bos) m = 'Bu alan zorunlu.';
        else if (a.tur === 'number' && v != null) {
          if (!isFinite(v)) m = 'Sayı gir.';
          else if (a.min != null && v < a.min) m = 'En az ' + a.min + ' olmalı.';
          else if (a.max != null && v > a.max) m = 'En çok ' + a.max + ' olmalı.';
        } else if (a.tur === 'email' && v && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)) {
          m = 'Geçerli bir e-posta gir.';
        } else if (a.max != null && typeof v === 'string' && v.length > a.max) {
          m = 'En çok ' + a.max + ' karakter.';
        }
        if (!m && a.dogrula && !bos) m = a.dogrula(v, d) || null;
        if (m) {
          hata(a.ad, m);
          if (!ilkHatali) ilkHatali = kontroller[a.ad];
        }
      });
      return ilkHatali;
    }

    var api = { el: f, hata: hata, temizle: temizle, mesgul: mesgul,
                degerler: degerler, ayarla: ayarla, kontrol: function (ad) {
                  return kontroller[ad]; } };

    f.addEventListener('submit', function (ev) {
      ev.preventDefault();
      temizle();
      var d = degerler();
      var hatali = dogrula(d);
      if (hatali) { hatali.focus(); return; }
      if (!o.onGonder) return;
      mesgul(true);
      Promise.resolve().then(function () { return o.onGonder(d, api); })
        .catch(function (h) {
          if (h && h.iptal) return;
          hata(null, RY.hataMetni ? RY.hataMetni(h) : String(h));
        })
        .then(function () { mesgul(false); });
    });

    return api;
  }

  /* ---------------- Segmentler (localStorage) ---------------- */

  var SEG_ANAHTAR = 'ry.segmentler.v1';
  var segmentler = {
    oku: function () {
      try {
        var v = JSON.parse(localStorage.getItem(SEG_ANAHTAR) || '[]');
        return Array.isArray(v) ? v : [];
      } catch (yok) { return []; }
    },
    kaydet: function (ad, filtre) {
      ad = String(ad || '').trim();
      if (!ad) return segmentler.oku();
      var liste = segmentler.oku().filter(function (s) { return s.ad !== ad; });
      liste.unshift({ ad: ad, filtre: filtre || {}, at: new Date().toISOString() });
      liste = liste.slice(0, 30);
      try { localStorage.setItem(SEG_ANAHTAR, JSON.stringify(liste)); } catch (yok) { /* dolu */ }
      return liste;
    },
    sil: function (ad) {
      var liste = segmentler.oku().filter(function (s) { return s.ad !== ad; });
      try { localStorage.setItem(SEG_ANAHTAR, JSON.stringify(liste)); } catch (yok) { /* dolu */ }
      return liste;
    }
  };

  /* ---------------- Dışa aktarım ---------------- */

  /* Görünümler app.js'ten ÖNCE yüklenir: kırıntı sağlayıcı ve palet eylemi
     kaydı yükleme anında yapılabilsin diye burada tohumlanır; app.js
     kuyruğu devralır. */
  RY.kirintiSaglayici = RY.kirintiSaglayici || {};
  RY.palet = RY.palet || {
    _kuyruk: [],
    eylemEkle: function (ey) { this._kuyruk.push(ey); },
    eylemSil: function (ad) {
      this._kuyruk = this._kuyruk.filter(function (x) { return x.ad !== ad; });
    },
    ac: function () {}, kapat: function () {}
  };

  RY.b = {
    // temel
    e: e, el: el, ik: ik, kucult: kucult, sayi: sayi, para: para, yuzde: yuzde,
    tarih: tarih, kisaGun: kisaGun, tarihNesnesi: tarihNesnesi, goreliZaman: goreliZaman,
    sureMetni: sureMetni, utcGun: utcGun, saatFarki: saatFarki,
    OZET_BAYAT_SAAT: OZET_BAYAT_SAAT, guncellemeMetni: guncellemeMetni,
    basHarfler: basHarfler,
    // HTML dizesi
    canlandir: canlandir, rozet: rozet, iskelet: iskelet,
    bosDurum: bosDurum, hataDurum: hataDurum, modul: modul, etiket: etiket,
    // v3 HTML
    istatistikKarti: istatistikKarti, bant: bant, sayfaBaslik: sayfaBaslik,
    planRozeti: planRozeti, rolRozeti: rolRozeti, rolAdi: rolAdi,
    kivilcimlariCiz: kivilcimlariCiz,
    // v3 etkileşimli
    veriTablosu: veriTablosu, modal: modal, yanPanel: yanPanel,
    onayla: onayla, toast: toast, filtreCipleri: filtreCipleri,
    secimCipleri: secimCipleri, donemSecici: donemSecici, tazeleyici: tazeleyici,
    sekmeler: sekmeler, form: form, segmentler: segmentler
  };
})();

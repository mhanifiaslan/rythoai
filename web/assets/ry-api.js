/* Web panellerinin ORTAK API katmanı (v3, AD18 → OP9): her veri
   backend'den, Firestore'a doğrudan erişim YOK (kurallar kapalı kalır).
   Kimlik: Firebase ID token.

   NEDEN /assets/ ALTINDA: iki panel bunu kullanıyor — yönetim paneli
   (/rytho-admin/) ve ortağın kendi panosu (/ortak/). Dosya OP9'da
   `rytho-admin/api.js`'ten buraya TAŞINDI, kopyalanmadı: iki kopya
   zamanla ayrışır ve aşağıdaki acı derslerden biri yalnız bir kopyada
   onarılırsa diğer panel sessizce bozuk kalır.

   v2'den farklar: AbortController (sinyal), 429 → toast + err.retryAfter,
   RY.sorgu (boş parametreleri atlayan sorgu dizesi), RY.indir (yetkili
   blob indirme), 503 denetim izi mesajı olduğu gibi geçer, 204 → null. */
(function () {
  'use strict';

  /* AYNI ORIGIN (AP2 onarımı): istekler Hosting'in Cloud Run
     yönlendirmesinden geçer (firebase.json /api/** ve /health**). */
  var BACKEND = '';

  var RY = window.RY = window.RY || {};

  function iptalHatasi() {
    var h = new Error('iptal');
    h.iptal = true;
    return h;
  }

  async function token() {
    var kullanici = (RY.auth || (window.firebase && firebase.auth())).currentUser;
    if (!kullanici) throw new Error('oturum-yok');
    return kullanici.getIdToken();
  }

  /* Son 429 uyarısı: aynı anda 5 istek düşünce 5 toast basılmasın. */
  var son429 = 0;

  /* Toast kabı panele göre değişir: yönetim panelinde bileşen kitaplığı
     (RY.b.toast, 53 KB'lik bilesenler.js), ortak panosunda o kitaplık
     YÜKLENMEZ ve kendi küçük kabını RY.toast olarak kaydeder. Bu kanca
     olmadan 429 uyarısı ortak panosunda sessizce yutulurdu — kullanıcı
     "veri gelmiyor" sanırdı. */
  function toastBas(metin) {
    if (RY.b && RY.b.toast) { RY.b.toast(metin, 'uyari', { sure: 6000 }); return true; }
    if (RY.toast) { RY.toast(metin, 'uyari'); return true; }
    return false;
  }

  /* Sunucu `detail`i: düz metin olduğu gibi; pydantic 422 listesi
     ("[{type, loc, msg}]") alan adı + mesaj olarak — ham JSON basılmaz. */
  function detayMetni(detail) {
    if (typeof detail === 'string') return detail;
    if (Array.isArray(detail)) {
      return detail.map(function (d) {
        var alan = Array.isArray(d.loc) ? d.loc.filter(function (x) { return x !== 'body' && x !== 'query'; }).join('.') : '';
        return (alan ? alan + ': ' : '') + (d.msg || d.type || '');
      }).filter(Boolean).join(' · ') || 'Geçersiz istek.';
    }
    try { return JSON.stringify(detail); } catch (yok) { return String(detail); }
  }

  async function apiIste(yol, secenekler) {
    secenekler = secenekler || {};
    var sinyal = secenekler.sinyal || secenekler.signal;
    if (sinyal && sinyal.aborted) throw iptalHatasi();
    var jeton = await token();
    // Başlıklar AYRI birleştirilir: Object.assign(secenekler) çağıranın
    // headers'ı verdiği anda Authorization'ı eziyordu (eski kusur).
    var basliklar = Object.assign({
      'Authorization': 'Bearer ' + jeton,
      'Content-Type': 'application/json'
    }, secenekler.headers || {});
    var ayar = {
      method: secenekler.method || 'GET',
      headers: basliklar,
      body: secenekler.body,
      signal: sinyal
    };
    var yanit;
    try {
      yanit = await fetch(BACKEND + yol, ayar);
    } catch (aghata) {
      if (sinyal && sinyal.aborted) throw iptalHatasi();
      // Anlık ağ kesintisi/uyku dönüşü için TEK otomatik tekrar —
      // yalnız güvenli metotlarda (POST/PATCH çift işlem yapmasın).
      if (ayar.method.toUpperCase() !== 'GET') throw new Error('ag-hatasi');
      await new Promise(function (t) { setTimeout(t, 700); });
      if (sinyal && sinyal.aborted) throw iptalHatasi();
      try {
        yanit = await fetch(BACKEND + yol, ayar);
      } catch (yine) {
        if (sinyal && sinyal.aborted) throw iptalHatasi();
        throw new Error('ag-hatasi');
      }
    }
    if (yanit.status === 401) {
      // Kimlik düştü: oturumu kapat, jenerik görünüme dön. 403 BURAYA
      // GİRMEZ: "kimlikli ama yetkili değil" (destek rolü, propagasyon
      // bekleyen claim, pasifleştirilmiş ortak) normal bir hatadır —
      // oturumu yok etmek yanlıştı. Çağıran taraf ne yapacağına kendi
      // karar verir: ortak panosu 403'te jenerik ekrana düşüyor.
      if (RY.yetkisiz) RY.yetkisiz();
      throw new Error('yetkisiz');
    }
    if (!yanit.ok) {
      var hata = new Error('api-' + yanit.status);
      hata.durum = yanit.status;
      try {
        var govde = await yanit.json();
        if (govde && govde.detail) hata.detay = detayMetni(govde.detail);
      } catch (yok) { /* gövdesiz hata */ }
      if (yanit.status === 429) {
        var ra = Number(yanit.headers.get('Retry-After'));
        hata.retryAfter = isFinite(ra) && ra > 0 ? ra : 60;
        var simdi = Date.now();
        if (simdi - son429 > 5000 && toastBas(hataMetni(hata))) {
          son429 = simdi;
        }
      }
      throw hata;
    }
    if (yanit.status === 204) return null;
    var metin = await yanit.text();
    if (!metin) return null;
    return JSON.parse(metin);
  }

  /* Ham hata → yöneticinin okuyacağı cümle. 503 denetim izi mesajı
     sunucudan geldiği gibi (detail) geçer — "Denetim izi yazılamadı;
     işlem yapılmadı." kelimesi kelimesine görünür. */
  function hataMetni(hata) {
    if (!hata) return 'Bilinmeyen hata.';
    if (hata.iptal || hata.message === 'iptal') return '';
    if (hata.message === 'ag-hatasi') {
      return 'Bağlantı kurulamadı — ağını kontrol edip tekrar dene.';
    }
    if (hata.message === 'oturum-yok') return 'Oturum bulunamadı.';
    if (hata.message === 'yetkisiz') return 'Yetki yok.';
    if (hata.durum === 429) {
      return 'İstek sınırı aşıldı — ' + (hata.retryAfter || 60) +
        ' sn sonra tekrar dene.';
    }
    if (hata.detay) return hata.detay;
    if (hata.durum === 404) return 'Kayıt bulunamadı.';
    if (hata.durum === 409) return 'İşlem zaten sürüyor — birazdan tekrar dene.';
    if (hata.durum >= 500) return 'Sunucu hatası — birazdan tekrar dene.';
    return 'Veri alınamadı (' + (hata.message || hata) + ').';
  }

  /* Sorgu dizesi: undefined/null/'' atlanır, her değer encodeURIComponent.
     Diziler tekrar eden anahtar olur (?plan=a&plan=b). */
  function sorguDizesi(params) {
    var parcalar = [];
    Object.keys(params || {}).forEach(function (ad) {
      var v = params[ad];
      if (v === undefined || v === null || v === '') return;
      (Array.isArray(v) ? v : [v]).forEach(function (tek) {
        if (tek === undefined || tek === null || tek === '') return;
        parcalar.push(encodeURIComponent(ad) + '=' + encodeURIComponent(tek));
      });
    });
    return parcalar.length ? '?' + parcalar.join('&') : '';
  }

  RY.apiIste = apiIste;
  RY.get = function (yol, sec) { return apiIste(yol, sec); };
  RY.post = function (yol, govde, sec) {
    return apiIste(yol, Object.assign({}, sec, { method: 'POST',
      body: govde !== undefined ? JSON.stringify(govde) : undefined }));
  };
  RY.patch = function (yol, govde, sec) {
    return apiIste(yol, Object.assign({}, sec, { method: 'PATCH',
      body: JSON.stringify(govde || {}) }));
  };
  RY.del = function (yol, govde, sec) {
    return apiIste(yol, Object.assign({}, sec, { method: 'DELETE',
      body: JSON.stringify(govde || {}) }));
  };
  /* RY.sorgu('/api/v1/admin/users', {q:'asl', plan:'', limit:8}, {sinyal})
     → GET /api/v1/admin/users?q=asl&limit=8 */
  RY.sorgu = function (yol, params, sec) {
    return apiIste(yol + sorguDizesi(params), sec);
  };
  RY.sorguDizesi = sorguDizesi;

  /* Yetkili dosya indirme: fetch + Authorization → blob → a[download].
     Tarayıcı indirme diyaloğu; dosya adı sunucu Content-Disposition'ından
     değil çağırandan (aynı origin olsa da başlığa güvenmiyoruz). */
  RY.indir = async function (yol, dosyaAdi, sec) {
    sec = sec || {};
    var jeton = await token();
    var yanit;
    try {
      yanit = await fetch(BACKEND + yol, {
        headers: { 'Authorization': 'Bearer ' + jeton },
        signal: sec.sinyal
      });
    } catch (ag) {
      if (sec.sinyal && sec.sinyal.aborted) throw iptalHatasi();
      throw new Error('ag-hatasi');
    }
    if (yanit.status === 401) {
      if (RY.yetkisiz) RY.yetkisiz();
      throw new Error('yetkisiz');
    }
    if (!yanit.ok) {
      var hata = new Error('api-' + yanit.status);
      hata.durum = yanit.status;
      try {
        var govde = await yanit.json();
        if (govde && govde.detail) {
          hata.detay = typeof govde.detail === 'string'
            ? govde.detail : JSON.stringify(govde.detail);
        }
      } catch (yok) { /* gövdesiz */ }
      throw hata;
    }
    var blob = await yanit.blob();
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = dosyaAdi || 'rytho-export';
    a.rel = 'noopener';
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 4000);
    return { boyut: blob.size, tur: blob.type };
  };

  // Sağlık uçları herkese açık — token gerekmez.
  RY.saglik = function (yol) {
    return fetch(BACKEND + yol).then(function (y) {
      if (!y.ok) throw new Error('saglik-' + y.status);
      return y.json();
    });
  };
  RY.hataMetni = hataMetni;
  RY.BACKEND = BACKEND;
})();

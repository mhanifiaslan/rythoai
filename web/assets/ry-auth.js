/* Firebase Auth kurulumu — WEB panellerinin ORTAĞI (OP9).
 *
 * NEDEN VAR: aynı iki incelik hem yönetim panelinde (/rytho-admin/) hem
 * ortağın kendi panosunda (/ortak/) geçerli. OP9'da `rytho-admin/app.js`
 * içinden buraya ÇIKARILDI, kopyalanmadı: kopya olsaydı biri onarılırken
 * diğeri sessizce eski kalırdı ve arıza "giriş çalışmıyor" diye
 * görünürdü — kök nedeni bu dosyada olmak zorunda.
 *
 * İNCELİK 1 — authDomain onarımı. Varsayılan Hosting alanlarında
 * (*.web.app / *.firebaseapp.com) açılır pencere el sıkışması, sayfanın
 * kendi ana makinesiyle aynı origin olsun diye `authDomain` bulunduğumuz
 * ana makineye çevrilir ve bunun için İKİNCİ bir Firebase örneği kurulur
 * (varsayılan örneğin seçenekleri sonradan değiştirilemez).
 *
 * İNCELİK 2 — App Check ÖRNEK BAŞINADIR. `identitytoolkit` zorlaması açık
 * (2026-09-26); etkinleştirilmeyen örneğin istekleri JETONSUZ gider ve
 * reddedilir. Bu yüzden hem varsayılan hem ikinci örnek için ayrı ayrı
 * RY_appCheckKur() çağrılır.
 *
 * ⚠️ rytho.app'te `uygun` FALSE olur ve VARSAYILAN örnek kullanılır. Bu
 * doğru: Firebase Auth yetkili alan listesinde rytho.app var, hata
 * `authDomain`'den değil sayfanın kendi ana makinesinden gelirdi.
 * Ölçüldü (2026-09-26) — bu davranış DEĞİŞTİRİLMEZ.
 */
(function (w) {
  'use strict';

  /* RY_authKur('yonetim') → auth nesnesi.
     Örnek adı ÇAĞIRANDAN gelir (yönetim paneli 'yonetim', ortak panosu
     'ortak') — niyet çağrı yerinde okunsun diye parametreli; aynı adla
     iki kez çağrılırsa Firebase 'app/duplicate-app' fırlatır, yani
     sayfa başına bir çağrı. */
  w.RY_authKur = function (ornekAdi) {
    var ana = location.hostname;
    var uygun = /\.web\.app$|\.firebaseapp\.com$/.test(ana);
    if (w.RY_appCheckKur) RY_appCheckKur();
    if (!uygun) return firebase.auth();
    var cfg = Object.assign({}, firebase.app().options, { authDomain: ana });
    var ornek = firebase.initializeApp(cfg, ornekAdi || 'ikincil');
    if (w.RY_appCheckKur) RY_appCheckKur(ornek);
    return ornek.auth();
  };
})(window);

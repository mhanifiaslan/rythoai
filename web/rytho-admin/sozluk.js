/* Panelin TEK Türkçe sözlüğü: sunucudan gelen her kod (ortam, gelir olayı,
   mağaza, dönem türü, AI özelliği, dil, platform, plan, denetim eylemi,
   dikkat kalemi) ekrana BURADAN geçerek çıkar.

   NEDEN tek modül: aynı sözlükler üç dört görünümde ayrı ayrı yaşıyordu ve
   ayrışmıştı — bildirim türü listesi bir yerde altı, iki yerde dört türdü
   (`circle`/`winback` iki ekranda "—" çiziliyordu); denetim eylemi adları
   Genel'de "Eşik yaz", Sistem'de başka; dikkat kalemleri zilde ve Genel'de
   iki farklı cümleyle. Sahibin şikâyeti tam buydu: aynı şey iki ekranda iki
   adla, üstelik İngilizce kodla yan yana. Kural: görünüm KOD basmaz, bu
   modülün adını basar; bilinmeyen kod (sunucu yeni bir değer eklediyse)
   tek başına görünür ki eksik çeviri fark edilsin, uydurma bir ad almasın.

   Bu dosya görünümlerden ÖNCE yüklenir (index.html) ve yalnız veri taşır;
   DOM'a dokunmaz. */
(function () {
  'use strict';

  var RY = window.RY = window.RY || {};

  function adla(sozluk) {
    return function (k, yedek) {
      if (k == null || k === '') return yedek != null ? yedek : '—';
      var v = sozluk[k];
      if (v == null) v = sozluk[String(k).toUpperCase()];
      if (v == null) v = sozluk[String(k).toLowerCase()];
      return v != null ? (Array.isArray(v) ? v[0] : v) : String(k);
    };
  }

  /* RevenueCat ortamı. "Üretim/Sandbox" sahibe bir şey söylemiyordu; asıl
     soru "bu para gerçek mi" ve ad bunu cevaplıyor. */
  var ORTAM = { PRODUCTION: 'Gerçek alımlar', SANDBOX: 'Test alımları' };

  /* RevenueCat olay türleri — webhook'un gönderdiği tam küme. */
  var OLAY = {
    INITIAL_PURCHASE: 'İlk satın alma', RENEWAL: 'Yenileme', CANCELLATION: 'İptal',
    EXPIRATION: 'Sona erme', BILLING_ISSUE: 'Ödeme sorunu', REFUND: 'İade',
    TRIAL_STARTED: 'Deneme başladı', TRIAL_CONVERTED: 'Denemeden aboneliğe',
    NON_RENEWING_PURCHASE: 'Kredi paketi', PRODUCT_CHANGE: 'Plan değişikliği',
    UNCANCELLATION: 'İptal geri alındı', SUBSCRIPTION_EXTENDED: 'Süre uzatıldı',
    SUBSCRIPTION_PAUSED: 'Abonelik duraklatıldı', TRANSFER: 'Hesap aktarımı',
    TEMPORARY_ENTITLEMENT_GRANT: 'Geçici erişim'
  };

  var MAGAZA = {
    PLAY_STORE: 'Google Play', APP_STORE: 'App Store', MAC_APP_STORE: 'Mac App Store',
    STRIPE: 'Stripe', PROMOTIONAL: 'Promosyon', AMAZON: 'Amazon',
    RC_BILLING: 'Web ödemesi', TEST_STORE: 'Test mağazası', '-': 'Bilinmiyor'
  };

  /* RevenueCat `period_type`. */
  var DONEM_TURU = { NORMAL: 'Normal', TRIAL: 'Deneme', INTRO: 'Tanıtım', PROMOTIONAL: 'Promosyon',
                     PREPAID: 'Ön ödemeli' };

  /* AI özellik anahtarı (usageEvents.feature) → ad. */
  var OZELLIK = {
    chat: 'Sohbet', signal: 'Sinyal paketi', natal: 'Doğum haritası raporu',
    iching: 'İ Ching', iching_verdict: 'İ Ching hükmü', face: 'Yüz okuma',
    bazi: 'BaZi', dyad: 'İkili dinamik', synastry: 'Sinastri', relationship: 'İlişki',
    birth_hexagram: 'Doğum heksagramı', solar_return: 'Yıl haritası',
    progressions: 'Progresyon', calendar: 'Takvim', daily: 'Günlük okuma',
    horoscope: 'Burç yorumu', memory_extract: 'Hafıza çıkarımı',
    push_daily: 'Sabah bildirimi', unknown: 'Bilinmeyen özellik'
  };

  var DIL = { tr: 'Türkçe', en: 'İngilizce', de: 'Almanca', fr: 'Fransızca',
              es: 'İspanyolca', ar: 'Arapça', ru: 'Rusça' };

  var PLATFORM = { android: 'Android', ios: 'iOS', web: 'Web' };

  var PLAN = { free: 'Ücretsiz', trial: 'Deneme', plus: 'Rytho+' };

  /* Geri bildirim durumu ve türü — denetim izinde (feedback.update) de
     görünüyor, o yüzden görünümün içinde değil burada. */
  var GB_DURUM = { new: 'Yeni', in_review: 'İnceleniyor', closed: 'Kapandı' };
  var GB_TUR = { bug: 'Hata', suggestion: 'Öneri', other: 'Diğer' };

  /* Denetim eylemi → [ad, ikon, ikon sınıfı]. Küme `api/admin.py`
     `_audit(...)` çağrılarından; ad bir İŞLEM adıdır (ne yapıldı). */
  var EYLEMLER = [
    ['user.credit', 'Kredi verme', 'jeton', 'altin'],
    ['user.disable', 'Hesabı devre dışı bırakma', 'kilit', 'kirmizi'],
    ['user.enable', 'Hesabı yeniden açma', 'basari', 'yesil'],
    ['user.delete', 'Hesap silme', 'cop', 'kirmizi'],
    ['user.auth_link', 'Giriş bağlantısı üretme', 'anahtar', ''],
    ['device.release', 'Cihaz kilidini sıfırlama', 'cihaz', ''],
    ['config.min_build', 'Zorunlu güncelleme eşiği', 'sistem', 'altin'],
    ['config.notice', 'Panel duyurusu', 'duyuru', ''],
    ['notify.dry_run', 'Bildirim provası', 'zil', ''],
    ['notify.test_send', 'Test bildirimi', 'gonder', ''],
    ['feedback.update', 'Geri bildirim güncelleme', 'geribildirim', ''],
    ['feedback.reply', 'Geri bildirime yanıt', 'gonder', ''],
    ['partner.create', 'Ortak ekleme', 'ortaklar', 'yesil'],
    ['partner.update', 'Ortak güncelleme', 'ortaklar', ''],
    ['partner.code', 'Ortak bağlantısı üretme', 'ortaklar', 'altin'],
    ['partner.access', 'Ortak panosu erişimi', 'anahtar', ''],
    ['partner.payout', 'Ortak ödemesi', 'gelir', 'altin'],
    ['export.users', 'Kullanıcı listesi indirme', 'indir', ''],
    ['export.revenue', 'Gelir listesi indirme', 'indir', ''],
    ['stats.collect', 'İstatistik toplama', 'yenile', ''],
    ['stats.recompute', 'Geçmiş günleri yeniden hesaplama', 'gelir', '']
  ];
  var EYLEM = {};
  EYLEMLER.forEach(function (x) { EYLEM[x[0]] = x; });

  /* Denetim kaydı `params` anahtarları → ad. Değerler `parametreDegeri`
     ile ayrıca çevrilir (ortam, tür, durum, evet/hayır). */
  var PARAMETRE = {
    reason: 'Gerekçe', email: 'E-posta', type: 'Tür', force: 'Saat penceresi yok sayıldı',
    filters: 'Süzgeçler', days: 'Gün', env: 'Ortam', amount: 'Miktar', kind: 'Bağlantı türü',
    fid: 'Kayıt', status: 'Durum', note: 'Not', pushSent: 'Bildirim gitti', text: 'Metin',
    level: 'Seviye', min_build: 'Eşik', name: 'Ad', partnerId: 'Ortak', code: 'Kod',
    grant: 'Erişim', from: 'Başlangıç', to: 'Bitiş', date: 'Gün', currency: 'Para birimi',
    rewardTry: 'Ödül (₺)', active: 'Aktif', contact: 'İletişim', uid: 'Hesap',
    plan: 'Plan', language: 'Dil', platform: 'Platform', disabled: 'Devre dışı',
    activeSince: 'Şu tarihten beri aktif', minPayout: 'Alt sınır', payoutCurrency: 'Ödeme birimi'
  };
  var SEVIYE = { info: 'Bilgi', warn: 'Uyarı' };
  var BAGLANTI = { reset: 'Şifre sıfırlama', verify: 'E-posta doğrulama' };

  /* Dikkat zili kalemleri (admin_service.attention `tur`). Eski/alternatif
     anahtarlar aynı kaleme bağlanır; rota ve seviye sunucudan gelirse o
     kazanır, buradaki yalnız yedek. */
  var DIKKAT = {
    failedPushesToday: { etiket: 'Başarısız bildirim (bugün)', alt: 'Bugünkü koşularda geçersiz cihaz jetonu', href: '#/bildirimler', tur: 'uyari' },
    billingIssues7d: { etiket: 'Ödeme sorunu (7 gün)', alt: 'Mağazanın bildirdiği tahsilat sorunları · gerçek alımlar', href: '#/gelir', tur: 'uyari' },
    trialsExpiring3d: { etiket: 'Bitmek üzere olan deneme (3 gün)', alt: 'Dönüşüm fırsatı', href: '#/kullanicilar?plan=trial', tur: 'bilgi' },
    belowMin: { etiket: 'Eşik altı sürüm', alt: 'Zorunlu güncelleme eşiğinin altındaki kullanıcılar', href: '#/sistem', tur: 'bilgi' },
    disabledTotal: { etiket: 'Devre dışı hesap', alt: 'Girişi kapatılmış hesaplar', href: '#/kullanicilar?disabled=true', tur: 'bilgi' },
    rollupStale: { etiket: 'İstatistik özeti bayat', alt: 'Son toplamadan bu yana geçen saat', href: '#/sistem', tur: 'hata' },
    newFeedback: { etiket: 'Yeni geri bildirim', alt: 'Uygulama içi · yanıt bekliyor', href: '#/geribildirim?status=new', tur: 'bilgi' }
  };
  var DIKKAT_TAKMA = {
    failedPush: 'failedPushesToday', pushFailed: 'failedPushesToday',
    billingIssue: 'billingIssues7d', billingIssues: 'billingIssues7d',
    trialExpiring: 'trialsExpiring3d', trialsExpiring: 'trialsExpiring3d',
    belowMinBuild: 'belowMin', belowBuild: 'belowMin',
    disabled: 'disabledTotal', disabledUsers: 'disabledTotal',
    staleRollup: 'rollupStale'
  };
  function dikkat(k) {
    return DIKKAT[k] || DIKKAT[DIKKAT_TAKMA[k]] || null;
  }

  /* Bildirim türleri: liste `bildirimler.js`teki TURLER'dir ve oradan
     kaydedilir. Neden orada: `test_notify_turleri_tek_kaynak` kümeyi O
     dosyadaki literal listeye çiviliyor (sunucunun RUN_TYPES'ıyla aynı
     küme). Listeyi buraya taşımak bekçiyi kör bırakırdı; ikinci bir kopya
     tutmak ise bu modülün var olma sebebini bozardı. Okuyanlar (Sistem,
     Kullanıcı 360) çizim anında okur — o an bütün betikler yüklenmiştir. */
  var bildirimListesi = [];
  var BILDIRIM = {};
  function bildirimTurleriKaydet(liste) {
    bildirimListesi = (liste || []).slice();
    BILDIRIM = {};
    bildirimListesi.forEach(function (t) { BILDIRIM[t.deger] = t.etiket; });
  }

  /* Zamanlanmış bildirim koşusunun son durumu (`notifyRuns.lastStatus`,
     `notify_runner.RunResult.status`). İki "tamamen düştü" adı sunucuda
     uca 503 döndüren kararla aynı — panelde de kırmızı okunmalı. */
  var KOSU_DURUMU = {
    ok: 'tamam', 'dry-run': 'prova',
    'uretim-tamamen-dustu': 'metin üretimi tamamen düştü',
    'gonderim-tamamen-dustu': 'gönderim tamamen düştü'
  };

  function evetHayir(v) { return v === true ? 'evet' : (v === false ? 'hayır' : v); }

  function parametreDegeri(anahtar, v) {
    if (typeof v === 'boolean') return evetHayir(v);
    var s = String(v);
    if (anahtar === 'env') return ORTAM[s] || s;
    if (anahtar === 'type') return BILDIRIM[s] || GB_TUR[s] || OLAY[s] || s;
    if (anahtar === 'status') return GB_DURUM[s] || s;
    if (anahtar === 'level') return SEVIYE[s] || s;
    if (anahtar === 'kind') return BAGLANTI[s] || s;
    if (anahtar === 'plan') return PLAN[s] || s;
    if (anahtar === 'language') return DIL[s] || s;
    if (anahtar === 'platform') return PLATFORM[s] || s;
    return s;
  }

  RY.sozluk = {
    ORTAM: ORTAM, OLAY: OLAY, MAGAZA: MAGAZA, DONEM_TURU: DONEM_TURU, OZELLIK: OZELLIK,
    DIL: DIL, PLATFORM: PLATFORM, PLAN: PLAN, GB_DURUM: GB_DURUM, GB_TUR: GB_TUR,
    EYLEMLER: EYLEMLER, SEVIYE: SEVIYE, BAGLANTI: BAGLANTI,
    ortamAdi: adla(ORTAM),
    olayAdi: adla(OLAY),
    magazaAdi: adla(MAGAZA),
    donemTuruAdi: adla(DONEM_TURU),
    ozellikAdi: adla(OZELLIK),
    dilAdi: adla(DIL),
    platformAdi: adla(PLATFORM),
    planAdi: adla(PLAN),
    gbDurumAdi: adla(GB_DURUM),
    gbTurAdi: adla(GB_TUR),
    kosuDurumAdi: function (k) { return KOSU_DURUMU[k] || String(k || '—'); },
    eylemAdi: function (k) { return EYLEM[k] ? EYLEM[k][1] : String(k || '—'); },
    eylem: function (k) { return EYLEM[k] || [k, String(k || '—'), 'denetim', '']; },
    parametreAdi: function (k) { return PARAMETRE[k] || String(k); },
    parametreDegeri: parametreDegeri,
    evetHayir: evetHayir,
    dikkat: dikkat,
    bildirimTurleriKaydet: bildirimTurleriKaydet,
    bildirimTurleri: function () { return bildirimListesi.slice(); },
    bildirimAdi: function (k) { return BILDIRIM[k] || String(k || '—'); }
  };
})();

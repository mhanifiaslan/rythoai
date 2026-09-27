"""Kullanıcıya dönen hata ve kilit mesajları — dile göre.

Neden ayrı bir modül: istemci (`friendlyError`, apps/mobile/lib/core/api.dart)
sunucunun `detail` alanını **olduğu gibi** ekrana basar. Yani buradaki her
metin doğrudan kullanıcı arayüzüdür ve kullanıcının dilinde olmak zorundadır.
Faz 3'te uç yanıtları iki dile taşındı ama hata yolu Türkçe kalmıştı; İngilizce
kullanan biri kilitli bir ekrana geldiğinde Türkçe metin görüyordu.

İkinci kural burada uygulanır: **ham istisna metni kullanıcıya gösterilmez.**
Uçlar eskiden `detail=str(e)` döndürüyordu; bu hem anlaşılmaz (kullanıcı
"KeyError: 'sun'" görüyordu) hem de sunucunun iç yapısını dışarı sızdırıyordu.
Artık istisna sunucu tarafında loglanır, kullanıcıya sabit bir metin döner.
"""
from __future__ import annotations

import logging

from core.i18n import DEFAULT, SUPPORTED

logger = logging.getLogger(__name__)

#: anahtar -> {dil: metin}. İngilizce metinler Türkçenin birebir çevirisi
#: değildir; aynı bilgiyi o dilde doğal duran bir tonla verir.
_MESSAGES: dict[str, dict[str, str]] = {
    # --- Kimlik ---
    "auth_required": {
        "tr": "Devam etmek için oturum açman gerekiyor.",
        "en": "You need to be signed in to continue.",
    },
    "auth_invalid": {
        "tr": "Oturumun geçerliliğini yitirmiş. Lütfen tekrar giriş yap.",
        "en": "Your session is no longer valid. Please sign in again.",
    },

    # --- Abonelik kilidi (HTTP 402 -> istemci paywall açar) ---
    "paywall.personal_daily": {
        "tr": "Kişiye özel günlük okuma Rytho+ aboneliğine dahildir.",
        "en": "Your personalised daily reading is part of Rytho+.",
    },
    "paywall.natal_report": {
        "tr": "Derinlemesine doğum haritası raporu Rytho+ aboneliğine dahildir.",
        "en": "The in-depth birth chart report is part of Rytho+.",
    },
    "paywall.dyad": {
        "tr": "Arkadaşınla günlük ikili dinamik Rytho+ aboneliğine dahildir.",
        "en": "Your daily dynamic with a friend is part of Rytho+.",
    },
    "paywall.synastry": {
        "tr": "Sinastri raporu Rytho+ aboneliğine dahildir.",
        "en": "The synastry report is part of Rytho+.",
    },
    "paywall.bazi": {
        "tr": "BaZi analizi Rytho+ aboneliğine dahildir.",
        "en": "BaZi analysis is part of Rytho+.",
    },
    "paywall.iching": {
        "tr": "İ Ching çekimi Rytho+ aboneliğine dahildir.",
        "en": "I Ching readings are part of Rytho+.",
    },
    # Uç `require_plus("firasa")` ile kilitli ama mesajı YOKTU: kullanıcı
    # jenerik "Bu özellik..." metnine düşüyordu. test_messages.py'deki
    # "her require_plus özelliğinin mesajı var" denetimi de bu anahtarı
    # görmüyordu çünkü liste elle tutuluyor — anahtar eklenince liste de
    # güncellendi.
    "paywall.firasa": {
        "tr": "Yüz okuma Rytho+ aboneliğine dahildir.",
        "en": "Face reading is part of Rytho+.",
    },
    "paywall.birth_hexagram": {
        "tr": "Doğum Heksagramı Rytho+ aboneliğine dahildir.",
        "en": "The Birth Hexagram is part of Rytho+.",
    },
    "paywall.solar_return": {
        "tr": "Yıl Haritası (güneş dönüşü) Rytho+ aboneliğine dahildir.",
        "en": "The Year Chart (solar return) is part of Rytho+.",
    },
    "paywall.progressions": {
        "tr": "İç Takvim (progresyon) okuması Rytho+ aboneliğine dahildir.",
        "en": "The Inner Calendar (progressions) reading is part of Rytho+.",
    },
    "paywall.transit_calendar": {
        "tr": "Kişisel transit takvimi Rytho+ aboneliğine dahildir.",
        "en": "The personal transit calendar is part of Rytho+.",
    },
    # Profilden hesap yapan uçlar (transit takvimi): doğum kaydı gerçekten
    # girilmemişse varsayılanla "senin haritan" üretilmez (chart_context
    # kuralı) — istemciye açık neden döner.
    "birth.missing": {
        "tr": "Bu hesap için önce doğum tarihini ve şehrini kaydetmen "
              "gerekiyor. Profil bölümünden ekleyebilirsin.",
        "en": "This needs your birth date and city on file first. You can "
              "add them under Profile.",
    },
    "paywall.default": {
        "tr": "Bu özellik Rytho+ aboneliğine dahildir.",
        "en": "This feature is part of Rytho+.",
    },
    # --- Rehber eşleşmesi ---
    "contacts.disabled": {
        "tr": "Rehber eşleşmesi kapalı. Profil > Gizlilik bölümünden "
              "açabilirsin.",
        "en": "Contact matching is off. You can enable it under "
              "Profile > Privacy.",
    },

    # --- Telefon doğrulama ---
    "phone.not_verified": {
        "tr": "Telefon numarası doğrulanmamış görünüyor. Doğrulamayı "
              "tamamlayıp tekrar dene.",
        "en": "Your phone number doesn't look verified yet. Complete "
              "verification and try again.",
    },
    "phone.taken": {
        "tr": "Bu numara başka bir hesaba bağlı.",
        "en": "This number is linked to another account.",
    },

    # 409 + X-Device-Conflict: 1 ile birlikte döner (TC-turu). İstemci
    # oturumu KAPATMAZ; kapı ekranında "Bu cihazda kullan" / "Çıkış yap"
    # sunar — metin o düğmeye yönlendirir. Öbür cihazın bilgisi başlıkta
    # (X-Device-Other-Platform / X-Device-Claimed-At), detail düz metin.
    "device.conflict": {
        "tr": "Hesabın başka bir cihazda açıldı. Rytho+ tek cihazda "
              "kullanılabilir — burada devam etmek için 'Bu cihazda "
              "kullan'a dokun.",
        "en": "Your account was opened on another device. Rytho+ works on "
              "one device at a time — tap 'Use on this device' to continue "
              "here.",
    },
    # 402 + X-Paywall-Reason: tokens ile birlikte döner; istemci bu metni
    # token mağazası ekranında gösterir.
    "tokens.empty": {
        "tr": "Token bakiyen bitti. Aylık hakkın dönem başında yenilenir; "
              "istersen şimdi token paketi alabilirsin.",
        "en": "You're out of tokens. Your monthly allowance renews next "
              "period, or you can top up with a token pack now.",
    },

    # --- Günlük ücretsiz kota ---
    "quota.chat": {
        "tr": "Bugünlük ücretsiz sohbet hakkın doldu ({limit} mesaj). "
              "Rytho+ ile sınırsız konuşabilirsin.",
        "en": "You've used today's free messages ({limit}). "
              "Rytho+ removes the limit.",
    },
    "quota.iching": {
        "tr": "Bugünlük çekilişini yaptın. Yarın yeni bir heksagram seni "
              "bekliyor; Rytho+ ile istediğin kadar çekebilirsin.",
        "en": "You've cast today's hexagram. A new one waits tomorrow — "
              "or cast as often as you like with Rytho+.",
    },
    "quota.default": {
        "tr": "Bugünlük ücretsiz hakkın doldu.",
        "en": "You've used today's free allowance.",
    },

    # --- I Ching soru kapısı (R10, hüküm R11'de LLM'e devredildi) ---
    "iching.question_invalid": {
        "tr": "Kâhin bu metinde yorumlayacağı bir soru bulamadı — niyetini "
              "kendi yaşamınla ilgili bir cümleyle yaz.",
        "en": "The oracle found no question to read in this text — put your "
              "intention into a sentence about your own life.",
    },
    # --- Ortak kodu (W7) ---
    "promo.invalid": {
        "tr": "Bu kod geçerli değil.",
        "en": "That code isn't valid.",
    },
    "promo.not_found": {
        "tr": "Böyle bir kod bulunamadı.",
        "en": "No such code was found.",
    },
    "promo.expired": {
        "tr": "Bu kodun süresi dolmuş.",
        "en": "This code has expired.",
    },
    "promo.exhausted": {
        "tr": "Bu kodun kullanım hakkı dolmuş.",
        "en": "This code has reached its redemption limit.",
    },
    "promo.self_referral": {
        "tr": "Kendi ortaklık kodunu kendi hesabında kullanamazsın.",
        "en": "You can't use your own partner code on your own account.",
    },
    "promo.already_redeemed": {
        "tr": "Zaten bir kod kullandın — her hesapta tek kod geçerlidir.",
        "en": "You've already used a code — one code per account.",
    },

    "iching.question_chat": {
        "tr": "Bu soru kâhine değil bana sorulmuş gibi. Konuşmak istersen "
              "Sohbet orada — İching'e ise kendi yolunla ilgili bir soru "
              "getir.",
        "en": "That sounds like a question for me, not the oracle. If you "
              "want to talk, Chat is right there — bring the I Ching a "
              "question about your own path.",
    },

    # --- İkili dinamik ---
    "dyad.self": {
        "tr": "Kendinle ikili okuma yapılamaz.",
        "en": "A dyad reading needs two different people.",
    },
    "dyad.not_friends": {
        "tr": "Bu okuma yalnızca karşılıklı olarak eklenmiş arkadaşlar için "
              "üretilir.",
        "en": "This reading is only produced for people who have added each "
              "other as friends.",
    },
    "reaction.unknown": {
        "tr": "Bilinmeyen tepki.",
        "en": "Unknown reaction.",
    },
    "invite.none": {
        "tr": "Böyle bir davet görünmüyor.",
        "en": "No such invite found.",
    },

    "dyad.profile_missing": {
        "tr": "Okuma için gereken doğum kaydı bulunamadı.",
        "en": "The birth details needed for this reading are missing.",
    },

    # --- Kriz yanıtı (S-turu) ---
    #
    # Bu metin bir astroloji yanıtı DEĞİL ve olmamalı. Ölçüldü: "artık
    # yaşamak istemiyorum" hiçbir kapıya takılmadan modele gidiyordu ve
    # persona gereği burç yorumuyla karşılanıyordu.
    #
    # Ton kuralları: tanı koymaz, "geçer" demez, sebep sormaz, yıldızlara
    # bağlamaz. Yalnız üç şey yapar — duyguyu ciddiye alır, yalnız
    # olmadığını söyler, somut bir numara verir.
    "crisis.support": {
        "tr": "Şu an yazdıkların benim yorumlayabileceğim bir şeyin çok "
              "ötesinde ve bunu ciddiye alıyorum. Bu ağırlığı tek başına "
              "taşımak zorunda değilsin.\n\n"
              "Türkiye'de 7/24 ulaşabileceğin destek hatları var:\n"
              "• 112 — acil yardım\n"
              "• 182 — sağlık danışma\n"
              "• 183 — sosyal destek hattı (şiddet, istismar, psikolojik "
              "destek)\n\n"
              "Hemen şimdi güvende değilsen 112'yi ara. Güvendeysen ama "
              "içinden çıkamıyorsan, güvendiğin birine bugün haber ver.\n\n"
              "Buradayım; hazır olduğunda başka bir şey konuşmak istersen "
              "yanındayım.",
        "en": "What you've written is far beyond something I should try to "
              "interpret, and I take it seriously. You don't have to carry "
              "this alone.\n\n"
              "Support is available around the clock:\n"
              "• Your local emergency number\n"
              "• findahelpline.com — free, confidential helplines by country\n"
              "• In the US: call or text 988 (Suicide & Crisis Lifeline)\n\n"
              "If you are not safe right now, please call emergency services. "
              "If you are safe but struggling, tell someone you trust "
              "today.\n\n"
              "I'm here whenever you want to talk about something else.",
    },

    # --- Eklenen kişiler (P-turu) ---
    # İkisi de 402 + X-Paywall-Reason: people ile döner (istemci jeton
    # mağazasını değil abonelik sayfasını açar). Metin ikiye ayrık, çünkü
    # kontenjanı dolan ABONEYE "Rytho+ al" demek saçmadır — ve sayı hem 1
    # hem 10 olabildiği için ifade tekil/çoğuldan bağımsız kuruldu.
    "people.limit_free": {
        "tr": "{limit} kişilik sınıra ulaştın. Rytho+ ile eşini, "
              "çocuklarını ve yakınlarını birlikte takip edebilirsin.",
        "en": "You've reached your limit of {limit}. Rytho+ lets you follow "
              "your partner, children and close ones together.",
    },
    "people.limit_plus": {
        "tr": "{limit} kişilik sınıra ulaştın. Yeni birini eklemek için "
              "listeden bir kişiyi çıkarabilirsin.",
        "en": "You've reached your limit of {limit}. Remove someone from "
              "your list to add a new person.",
    },
    "people.invalid": {
        "tr": "Bu kişinin doğum bilgileri eksik ya da hatalı görünüyor.",
        "en": "This person's birth details look incomplete or invalid.",
    },
    "people.missing": {
        "tr": "Bu kişi bulunamadı.",
        "en": "This person could not be found.",
    },

    # --- Genel ---
    "face_consent_required": {
        "tr": "Yüz okuma için biyometrik işleme rızası gerekiyor. "
              "Profil > Gizlilik bölümünden verebilirsin.",
        "en": "Face reading needs your consent to biometric processing. "
              "You can give it under Profile > Privacy.",
    },
    "face_invalid_ratios": {
        "tr": "Yüz ölçümü tutarsız geldi. Işığın yeterli olduğundan ve "
              "yüzünün çerçevede olduğundan emin olup tekrar dene.",
        "en": "The facial measurement came back inconsistent. Make sure the "
              "light is good and your face is inside the frame, then retry.",
    },
    "internal": {
        "tr": "Hesap yapılırken bir sorun çıktı. Lütfen biraz sonra tekrar dene.",
        "en": "Something went wrong while calculating this. Please try again "
              "in a moment.",
    },
    "llm_unavailable": {
        "tr": "Kozmik bağlantıda geçici bir parazit var; yıldız haritaların ve "
              "kadim kaynaklar her zamanki yerinde. Lütfen birkaç saniye sonra "
              "tekrar sor.",
        "en": "There's a little static on the line right now — your charts and "
              "the old sources are exactly where they were. Try again in a "
              "few seconds.",
    },
    "rate_limited": {
        "tr": "Gökyüzü biraz nefes istiyor: kısa sürede çok fazla istek "
              "gönderdin. Lütfen bir dakika sonra tekrar dene.",
        "en": "The sky needs a breath: that's a lot of requests in a short "
              "time. Please try again in a minute.",
    },
    "hexagram_not_found": {
        "tr": "Böyle bir heksagram yok (1-64 arası olmalı).",
        "en": "No such hexagram (it must be between 1 and 64).",
    },

    # --- Geri bildirim (GB-turu) — 429, uid başına günde 10 kayıt ---
    "feedback.limit": {
        "tr": "Bugünlük geri bildirim sınırına ulaştın — yarın tekrar dene.",
        "en": "You've reached today's feedback limit — try again tomorrow.",
    },

    # --- Zorunlu güncelleme (HTTP 426, core/app_gate.py) ---
    # ≤34 istemciler 426'yı tanımaz ve `detail`i SnackBar'da olduğu gibi
    # basar (K6); ham "update_required" kodu ayrı `code` alanında kalır.
    "update_required": {
        "tr": "Rytho'nun bu sürümü artık desteklenmiyor — Google Play'den "
              "güncelle.",
        "en": "This version of Rytho is no longer supported — update it "
              "from Google Play.",
    },
}


def text(key: str, lang: str = DEFAULT, *, fallback: str | None = None,
         **biçim: object) -> str:
    """Anahtarın verilen dildeki karşılığı.

    Dil desteklenmiyorsa veya anahtar o dile henüz çevrilmemişse varsayılan
    dile düşer — eksik çeviri yüzünden istek patlamaz.

    ``fallback``: anahtar tabloda yoksa denenecek ikinci anahtar. Özelliğe
    özel paywall/kota metinleri için kullanılır (``paywall.dyad`` yoksa
    ``paywall.default``). O da yoksa genel hata metni döner; sessizce boş
    string dönmek, kullanıcıya boş bir hata kutusu göstermek olurdu.
    """
    if lang not in SUPPORTED:
        lang = DEFAULT

    seçenekler = _MESSAGES.get(key)
    if seçenekler is None and fallback is not None:
        seçenekler = _MESSAGES.get(fallback)
    if seçenekler is None:
        logger.warning("Bilinmeyen mesaj anahtarı: %s", key)
        seçenekler = _MESSAGES["internal"]

    metin = seçenekler.get(lang) or seçenekler.get(DEFAULT) or ""
    return metin.format(**biçim) if biçim else metin

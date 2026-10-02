"""Firaset — yüz oranlarından mizaç belirtileri.

Bu servis **görüntü görmez.** İstemci tespiti cihazda yapar, oranları çıkarır
ve buraya yalnızca sayılar gelir. Sunucuda hiçbir aşamada biyometrik veri
bulunmaz; buradaki iş, o sayıları geleneğin dilindeki **belirtilere**
çevirmektir.

## Dört kural

**1. Belirti üretilir, hüküm değil.** Çıktı "geniş alın" gibi bir gözlemdir;
"zeki" gibi bir yargı değil. Yargı zaten geleneğin işi ve o da tek belirtiye
dayanmayı yasaklıyor (bkz. korpustaki "Firasetin Sınırı").

**2. Ölçemediğimizi söyleriz.** Gelenekte mizaç iki eksende okunur:
sıcak–soğuk ve kuru–nemli. Durağan geometriden **yalnızca kuru–nemli** ekseni
çıkarılabilir; sıcak–soğuk ekseni renk, hareket ve sese bakar ve elimizde
onlar yok. Bu eksiklik modele açıkça bildirilir — bilmediğini bilmeyen bir
model uydurur.

**3. Adlar dilden bağımsız.** Belirtiler anahtar olarak üretilir, adlandırma
isteğin dilinde yapılır. Bu, projedeki her hesap katmanının kuralı.

**4. GÜN BU DOSYADA DEĞİL.** Bu dosyanın KODUNDA tarih, gökyüzü ya da
transit tek kelime geçmiyor (bu paragraf dışında; bir şeyin yokluğunu arayan
bekçi onu anlatan yorumu görmemeli) ve yokluk kasıtlı: oranlar güne göre
değişmiyor, dolayısıyla belirtiler de değişmiyor. `prompt_block`un çıktısı
prompt'ta "ÖLÇÜLEN BELİRTİLER (kullanıcının cihazında hesaplandı)"
başlığının altına giriyor; oraya günün gökyüzünü koymak, ölçülmeyen bir şeyi
ölçülmüş adıyla sunmak olurdu.

⚠️ Bu, FİRASET YÜZEYİNİN günden habersiz olduğu anlamına GELMEZ — gelmiyor
(sahip kararı, 2026-10-03: yüzey gerçekten günlük). Gün prompt'a AYRI bir
blok ve AYRI bir başlıkla giriyor: `chart_context.gunun_gokyuzu` üretiyor,
`api/face_reading` taşıyor, `report_service.firasa_report` `sky` olarak
alıyor ve aynı dizeden önbellek kovasını kuruyor (`_gun_kovasi`). Yani
günün prompt'taki hâli ile anahtardaki hâli tek bir kaynaktan türüyor,
ayrışamıyor.

Bu dosyanın işi değişmedi ve DEĞİŞMEMELİ: belirti tablosu sabit kalır,
günün ışığında YORUMLANMASI modelin işi. Buraya bir "bugüne göre belirti
seç" mantığı eklemek, ölçülen oranları güne göre oynatmak olurdu — yani
ölçülmüş bir çekirdeği uydurmaya çevirmek.
"""
from __future__ import annotations

from typing import Any

from services import prompts

#: Belirti eşikleri.
#:
#: DÜRÜSTLÜK NOTU: bunlar ölçülmüş nüfus normları değil, **kalibrasyon
#: sabitleridir**. İnsan yüzlerinin tipik aralıklarına dayanarak seçildiler ve
#: amaçları uç değilse belirti üretmemek. Gerçek nüfus dağılımıyla ayarlamak
#: ayrı bir iş; o yapılana kadar eşikler bilinçli olarak GENİŞ tutuldu, yani
#: sistem belirti üretmemeye eğilimli. Az belirti üretip emin olmak, çok
#: belirti üretip uydurmaktan iyidir.
_T = {
    # San Ting: bir bölgenin "önde" ya da "geride" sayılması için ortalamadan
    # ne kadar ayrılması gerektiği. Üç bölge 1'e toplandığı için ortalama her
    # zaman 1/3; yani bu, mutlak bir eşik değil bir AYRIŞMA payı.
    #
    # Cihazda ölçülen gerçek bir yüz: 0,26 / 0,37 / 0,37. Ayrışmalar
    # sırasıyla -0,073 / +0,037 / +0,037 — yani üst bölge belirgin şekilde
    # geride, öteki ikisi birbirine eşit. Doğru okuma "alın kısa"; "orta ve
    # alt baskın" değil.
    "third_lead": 0.045,
    "face_broad": 0.75,
    "face_long": 0.65,
    "jaw_square": 0.85,
    "jaw_tapered": 0.75,
    "mouth_wide": 0.46,
    "mouth_small": 0.36,
    "lips_full": 0.060,
    "lips_thin": 0.040,
    "eyes_wide": 0.48,
    "eyes_close": 0.42,
    "asymmetry": 0.93,
}


def descriptors(ratios: dict[str, Any]) -> list[str]:
    """Oranlardan dilden bağımsız belirti anahtarları.

    Hiçbir oran uç değilse **boş liste** döner ve bu doğru davranıştır:
    ortalama bir yüz hakkında söylenecek belirti yoktur. Boş listeyi
    doldurmak için eşik gevşetmek, yorum uydurmaya davetiye olurdu.
    """
    def f(anahtar: str) -> float:
        try:
            return float(ratios.get(anahtar) or 0.0)
        except (TypeError, ValueError):
            return 0.0

    bulunan: list[str] = []

    # San Ting — üç bölge.
    #
    # `> 0` koruması ŞART: eksik ya da gönderilmemiş alan 0.0 olarak geliyor.
    # Koruma olmadan boş bir istek "alın dar, çene kısa" belirtileri
    # üretiyordu — yani OLMAYAN bir ölçümden hüküm çıkıyordu.
    #
    # Baskınlık GÖRELİ ölçülür, mutlak eşikle değil.
    #
    # Once her bolge kendi sabit esigiyle karsilastiriliyordu ve bu mantiken
    # tutarsiz sonuclar uretiyordu. Cihazda olculen gercek bir yuzde:
    #
    #     ust 0,26   orta 0,37   alt 0,37
    #
    # Eski kuralla orta VE alt bolgenin ikisi birden "baskin" cikiyordu.
    # Bir yuzun iki bolgesi ayni anda baskin olamaz; ucu birden 1'e
    # toplandigi icin baskinlik ancak OTEKILERE GORE tanimlanabilir.
    #
    # Gelenek de boyle okuyor: hangi bolge ONDE, hangisi geride. Artik en
    # fazla BIR baskin ve en fazla BIR kisa belirti uretiliyor.
    ust, orta, alt = f("upperThird"), f("middleThird"), f("lowerThird")
    if ust > 0 and orta > 0 and alt > 0:
        bolgeler = {"forehead": ust, "midface": orta, "jaw": alt}
        ortalama = (ust + orta + alt) / 3
        en_buyuk = max(bolgeler, key=lambda k: bolgeler[k])
        en_kucuk = min(bolgeler, key=lambda k: bolgeler[k])

        if bolgeler[en_buyuk] - ortalama >= _T["third_lead"]:
            bulunan.append(f"{en_buyuk}_dominant")
        if ortalama - bolgeler[en_kucuk] >= _T["third_lead"]:
            bulunan.append(f"{en_kucuk}_short")

    en_boy = f("widthToHeight")
    if en_boy >= _T["face_broad"]:
        bulunan.append("face_broad")
    elif 0 < en_boy <= _T["face_long"]:
        bulunan.append("face_long")

    cene = f("jawToCheek")
    if cene >= _T["jaw_square"]:
        bulunan.append("jaw_square")
    elif 0 < cene <= _T["jaw_tapered"]:
        bulunan.append("jaw_tapered")

    agiz = f("mouthToFaceWidth")
    if agiz >= _T["mouth_wide"]:
        bulunan.append("mouth_wide")
    elif 0 < agiz <= _T["mouth_small"]:
        bulunan.append("mouth_small")

    dudak = f("lipFullness")
    if dudak >= _T["lips_full"]:
        bulunan.append("lips_full")
    elif 0 < dudak <= _T["lips_thin"]:
        bulunan.append("lips_thin")

    goz = f("eyeSpacing")
    if goz >= _T["eyes_wide"]:
        bulunan.append("eyes_wide")
    elif 0 < goz <= _T["eyes_close"]:
        bulunan.append("eyes_close")

    # Simetri YALNIZCA belirginse anılır. Hiçbir yüz tam simetrik değildir;
    # her okumada "yüzün biraz asimetrik" demek bilgi değil gürültüdür.
    simetri = f("symmetry")
    if 0 < simetri <= _T["asymmetry"]:
        bulunan.append("asymmetry_marked")

    return bulunan


#: Belirti -> kuru/nemli eğilimi.
#:
#: Korpustaki firaset bölümünden geliyor: "Kuruluk belirtileri (ince yapı,
#: sert hat, keskin çizgi) → tutmama, ayırma, sınır çekme. Nemlilik
#: belirtileri (dolgun yapı, yumuşak hat) → tutma, uyum sağlama, bırakamama."
_MOISTURE = {
    "face_long": "dry",
    "jaw_tapered": "dry",
    "lips_thin": "dry",
    "mouth_small": "dry",
    "face_broad": "moist",
    "jaw_square": "moist",
    "lips_full": "moist",
    "mouth_wide": "moist",
}


#: Sıcak–soğuk eşikleri (yüz genişliği / saniye).
#:
#: Bu eksen uzun süre "ölçülemedi" diye modele bildiriliyordu. Üç aday
#: değerlendirildi ve HAREKET seçildi:
#:
#: * **Ten rengi: hayır.** Kamera mutlak yüz rengini ölçtüğünde ölçtüğü şey
#:   mizaç değil etnisitedir. Korpustan tam da bu sebeple çıkardığımız
#:   eşlemeleri otomatik ölçüm olarak geri getirirdi.
#: * **Ses perdesi: hayır.** Perde büyük ölçüde cinsiyete bağlı; erkeklere ve
#:   kadınlara sistematik olarak farklı okuma vermek olurdu.
#: * **Hareket: evet.** Irkla da cinsiyetle de korele değil.
#:
#: Eşikler arası boşluk BİLEREK geniş: arada kalan bir ölçüm için taraf
#: seçmektense hiçbir şey söylememek doğru. İstemci tarafındaki
#: `kHeatFast` / `kHeatSlow` ile aynı olmalı.
_HEAT_FAST = 0.18
_HEAT_SLOW = 0.06


def heat_lean(ratios: dict[str, Any]) -> str | None:
    """Sıcak–soğuk ekseninde durum.

    Üç ayrı sonuç döner ve üçü de birbirinden farklı şey söyler:

    * ``"fast"`` / ``"slow"`` — ölçüldü ve bir tarafa düştü.
    * ``"ambiguous"`` — **ölçüldü ama arada kaldı.** Veri var, sonuç yok.
    * ``None`` — hiç ölçülemedi.

    Son ikisini aynı kefeye koymak yanlış olurdu: "ölçemedim, elimde yalnızca
    durağan biçim var" ile "ölçtüm, net bir tarafa düşmedi" farklı
    ifadelerdir ve modele farklı söylenmeleri gerekir.

    İstemci ölçümü güvenilir bulmazsa hareket alanlarını **hiç göndermiyor**.
    Alanın yokluğu "ölçemedim" demek; sıfır göndermek "ölçtüm ve sıfır çıktı"
    demek olurdu ve o yalan olurdu.
    """
    if "motionRate" not in ratios and "stillness" not in ratios:
        return None
    try:
        hiz = max(float(ratios.get("motionRate") or 0.0),
                  float(ratios.get("stillness") or 0.0))
    except (TypeError, ValueError):
        return None

    if hiz >= _HEAT_FAST:
        return "fast"
    if 0 < hiz <= _HEAT_SLOW:
        return "slow"
    return "ambiguous"


def moisture_lean(keys: list[str]) -> str | None:
    """Kuru–nemli ekseninde baskın taraf; belirsizse ``None``.

    Beraberlikte ``None`` döner ve bu kasıtlı: gelenek "tek belirti hüküm
    vermez" diyor, aynı mantıkla dengeli bir yüzde bir tarafı seçmek de
    hüküm uydurmaktır.
    """
    kuru = sum(1 for k in keys if _MOISTURE.get(k) == "dry")
    nemli = sum(1 for k in keys if _MOISTURE.get(k) == "moist")
    if kuru == nemli:
        return None
    return "dry" if kuru > nemli else "moist"


def summary(ratios: dict[str, Any], lang: str | None = None) -> dict[str, Any]:
    """Prompt'a girecek belirti bloğu.

    Dönen sözlükte hem anahtarlar (test ve teşhis için) hem de isteğin
    dilindeki adlar bulunur.
    """
    anahtarlar = descriptors(ratios)
    p = prompts.get(lang)
    return {
        "keys": anahtarlar,
        "lines": [p.FIRASA_SIGNS[k] for k in anahtarlar
                  if k in p.FIRASA_SIGNS],
        "moisture": moisture_lean(anahtarlar),
        "heat": heat_lean(ratios),
    }


def prompt_block(ratios: dict[str, Any], lang: str | None = None) -> str:
    """Belirtileri prompt'a iliştirilecek metne çevirir."""
    p = prompts.get(lang)
    ozet = summary(ratios, lang)

    satirlar = list(ozet["lines"])
    if not satirlar:
        # Ortalama bir yüzde belirti yok. Modele bunu AÇIKÇA söylemek şart;
        # boş bir blok göndermek "bir şeyler bul" demek olurdu.
        satirlar.append(p.FIRASA_NO_MARKED_SIGNS)

    # Üst bölge kafatası tepesinden ölçüldüyse SÖYLENİR.
    #
    # Gelenek bu bölgeyi saç çizgisiyle tanımlıyor; kel bir kafada o çizgi
    # geri getirilemez. Ölçüm yapılabiliyor ama neyi ölçtüğü farklı ve bunu
    # gizlemek, ölçmediğimiz bir şeyi ölçmüş gibi sunmak olurdu. Aynı ilke
    # sıcak–soğuk ekseninde de uygulanıyor.
    try:
        tepeden = float(ratios.get("foreheadFromCrown") or 0.0) >= 0.5
    except (TypeError, ValueError):
        tepeden = False
    if tepeden:
        satirlar.append(p.FIRASA_FOREHEAD_FROM_CROWN)

    nem = ozet["moisture"]
    if nem:
        satirlar.append(p.FIRASA_MOISTURE[nem])

    # Sıcak–soğuk ekseni artık hareketten ölçülebiliyor. Ölçülemediğinde
    # bunu SÖYLEMEK gerekiyor — sessiz kalmak modelin o eksende de hüküm
    # vermesine kapı açar.
    sicak = ozet["heat"]
    if sicak in p.FIRASA_HEAT:
        satirlar.append(p.FIRASA_HEAT[sicak])
    elif sicak == "ambiguous":
        satirlar.append(p.FIRASA_HEAT_AMBIGUOUS)
    else:
        satirlar.append(p.FIRASA_HEAT_UNKNOWN)

    return "\n".join(f"- {s}" for s in satirlar)

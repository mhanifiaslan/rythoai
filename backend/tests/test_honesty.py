"""Dürüstlük bekçileri (R2-D1): ürün HESAPLAMADIĞINI iddia edemez.

Tespit (docs/ozellikler.md "İddia edilemeyecekler"): persona ve README
Vedik astroloji (Nakshatra/Dasha) sayıyordu ama motor bunları hiçbir yerde
hesaplamıyor. Bu testler o sınıf tutarsızlığın geri gelmesini engeller —
"ölçülmeyen söylenmez" ilkesinin iddia tarafı.
"""
from __future__ import annotations

import json
import pathlib
import re

from services import prompts

_KOK = pathlib.Path(__file__).resolve().parents[2]


def _turkce_kucult(metin: str) -> str:
    """Eşleştirme için küçültme — noktalı harfler ÖNCE karşılığına çevrilir.

    `str.lower()` Türkçe bilmez: "İ".lower() bir harf değil "i" + U+0307
    (birleşen nokta) üretir, yani "İyileştirir" aranan "iyileştirir" kalıbına
    HİÇ takılmaz. Bu, dürüstlük bekçisini sessizce kör bırakıyordu; kusur
    2026-09-27'de ölçüldü (web/ortaklik.html'de kelime büyük harfle yazılı).
    """
    return metin.replace("İ", "i").replace("I", "ı").lower()


def _yorumsuz_html(metin: str) -> str:
    """HTML yorumlarını atar.

    Bir şeyin YOKLUĞUNU arayan bekçi, onu ANLATAN yorumu görmemeli — bu depoda
    iki kez patladı (build kapısı kendi manifest yorumuna, davet sayfası testi
    kendi HTML yorumuna takıldı). Aynı gerekçe ters yönde de geçerli: yorum
    içinde kalmış bir madde VARLIK bekçisini de kandırmamalı.
    """
    return re.sub(r"<!--.*?-->", " ", metin, flags=re.S)


#: Hesaplanmayan sistemin persona/korpus yoluyla İDDİAYA dönüşen anahtar
#: kelimeleri. "Vedik/Jyotish" kelimesinin kendisi dürüstlük cümlesinde
#: ("hesaplanmıyor") geçebilir; yasak olan bunları BİLGİ diye sunmaktır.
_IDDIA_KALIPLARI = ("Nakshatra'lar", "Dasha dönemleri",
                    "nakshatras, dasha periods")


class TestPersona:
    def test_persona_hesaplanmayani_bilgi_saymaz(self):
        for lang in ("tr", "en"):
            metin = prompts.get(lang).SYSTEM_INSTRUCTION
            for kalip in _IDDIA_KALIPLARI:
                assert kalip not in metin, (lang, kalip)

    def test_persona_durustluk_cumlesi_tasir(self):
        assert "HESAPLANMIYOR" in prompts.get("tr").SYSTEM_INSTRUCTION
        assert "NOT computed" in prompts.get("en").SYSTEM_INSTRUCTION

    def test_persona_mizac_adi_saymaz(self):
        """H1 kararının persona ayağı: mizaç adları v1'de hesaplanmıyor,
        'bilgin' listesinde de geçmemeli (raporda yasak, personada teşvik
        çelişkiydi)."""
        for lang in ("tr", "en"):
            metin = prompts.get(lang).SYSTEM_INSTRUCTION.lower()
            for ad in ("demevi", "safrai", "sevdavi", "balgami",
                       "sanguine", "choleric", "melancholic", "phlegmatic"):
                assert ad not in metin, (lang, ad)


class TestKorpusVeBelgeler:
    def test_korpus_nakshatra_icermez(self):
        """RAG, korpustaki Vedik pasajını raporlara taşıyabilirdi —
        pasaj kaldırıldı, geri gelmesin."""
        for md in (_KOK / "knowledge" / "corpus").rglob("*.md"):
            metin = md.read_text(encoding="utf-8", errors="ignore").lower()
            assert "nakshatra" not in metin, md
            assert "dasha" not in metin, md

    def test_readme_vedik_iddia_etmez(self):
        metin = (_KOK / "README.md").read_text(encoding="utf-8")
        assert "Vedik" not in metin


class TestPazarlamaDili:
    """Yayına çıkan METİNLER koddaki kapılarla ve kendi kılavuzumuzla
    uyuşmalı.

    Bu sınıf kapalı test denetiminde (2026-09-14) eklendi. Aynı kusur
    sınıfı ÜÇ kez tekrarladı: önce mağaza metni ücretsiz I Ching vadetti
    (R9-5'te düzeltildi), sonra aynı vaat web sitesinde bulundu, üstelik
    yanında "Sınırsız sohbet" ve projenin kendi kılavuzunun (ozellikler.md
    §12b) açıkça yasakladığı "NASA" ibaresi vardı. Metin koddan sapıyor ve
    bunu kimse fark etmiyor; bekçi bu yüzden var.
    """

    #: Yayına çıkan ziyaretçi yüzeyleri: Firebase Hosting `public: "web"`.
    #: `web/en/legal/terms.html` listede YOKTU — İngilizce kullanım şartları
    #: aylarca bekçisiz kaldı (ölçüldü 2026-09-27). Ortaklık sayfaları da
    #: eklendi: para vaadi taşıyan METİN en çok orada kayar.
    #: Listenin TAM olduğunu `test_yayindaki_her_sayfa_listede` kanıtlıyor;
    #: elle tutulan liste "yayındaki sayfalar" diye anılıp dört yüzeyi
    #: dışarıda bırakmıştı (ölçüldü 2026-09-28) — en kötüsü `web/r/`, yani
    #: ortak bağlantısının İNDİĞİ sayfa.
    _SAYFALAR = ("web/index.html", "web/en/index.html",
                 "web/legal/gizlilik.html", "web/en/legal/privacy.html",
                 "web/legal/kullanim.html", "web/en/legal/terms.html",
                 "web/legal/hesap-silme.html",
                 "web/en/legal/delete-account.html",
                 "web/ortaklik.html", "web/en/partners.html",
                 "web/ortak/index.html",
                 "web/i/index.html", "web/r/index.html",
                 "web/404.html", "web/auth/action/index.html")

    #: Bilinçli dışarıda kalanlar — taranmayan her dosya BURADA gerekçesiyle
    #: durur, yoksa "liste tam" iddiası ölçülemez.
    _LISTE_DISI = {
        # Girişin arkasındaki iç araç; pazarlama yüzeyi değil.
        "web/rytho-admin/index.html",
        # Google Search Console doğrulaması: 53 baytlık jeton, metin değil.
        # Tek bayt değişirse mülk doğrulanmamışa döner (test_web_seo.py).
        "web/googleb6af2cb19834337d.html",
    }

    #: Sayfa başına, yasak kelimeyi YASAKLAMAK için alıntılayan literaller.
    #: Ortaklık sayfasındaki "yasak dil" panosu kelimelerin kendisini sayarak
    #: yasaklıyor; alıntı çıkarılmazsa bekçi, kuralı UYGULAYAN sayfaya takılır.
    #: Kapsam bilerek dar: tırnaklı tam literal atılır, o yüzden gerçek bir
    #: iddia ("şifa buldum" gibi) taranmaya devam eder.
    _META_ALINTI = {
        "web/ortaklik.html": ('"şifa"', '"tedavi eder"', '"İyileştirir"'),
    }

    #: (aranan, neden yasak)
    _YASAKLAR = (
        ("nasa", "ozellikler.md §12b: 'NASA' ASLA — doğrusu 'astronomik "
                 "efemeris verisi'"),
        ("sınırsız sohbet", "Rytho+ aylık 300 kredidir; sınırsız değil"),
        ("unlimited chat", "Rytho+ is 300 credits a month, not unlimited"),
        ("iyileştirir", "sağlık iddiası — mağaza politikası"),
        ("tedavi eder", "sağlık iddiası — mağaza politikası"),
        ("şifa", "sağlık iddiası — mağaza politikası"),
        (" heals ", "health claim — store policy"),
        (" cures ", "health claim — store policy"),
    )

    def test_yayindaki_sayfalarda_yasak_ifade_yok(self):
        for yol in self._SAYFALAR:
            dosya = _KOK / yol
            # Eskiden eksik dosya sessizce atlanıyordu; bir sayfanın adı
            # değişse bekçi susar ve kimse fark etmezdi. Artık bağırıyor.
            assert dosya.exists(), (
                f"{yol} yok — taşındıysa _SAYFALAR güncellenmeli, yoksa "
                f"yayındaki bir sayfa bekçisiz kalır")
            ham = _yorumsuz_html(dosya.read_text(encoding="utf-8"))
            for alinti in self._META_ALINTI.get(yol, ()):
                ham = ham.replace(alinti, " ")
            metin = _turkce_kucult(ham)
            for aranan, neden in self._YASAKLAR:
                assert aranan not in metin, (
                    f"{yol} içinde yasak ifade {aranan!r} — {neden}")

    def test_yayindaki_her_sayfa_listede(self):
        """Listeye YAZILMAYAN yeni bir sayfa, bekçinin hiç görmediği sayfadır.

        Liste elle tutuluyor ve "yayına çıkan ziyaretçi yüzeyleri" diye
        anılıyordu; oysa dört sayfa dışındaydı (ölçüldü 2026-09-28): davet
        `web/i/`, ortak bağlantısının indiği `web/r/`, 404 ve hesap işlemi
        sayfası. Yeni bir pazarlama sayfası açan kişi listeyi güncellemeyi
        unutursa hiçbir test patlamazdı — bu test o sessizliği kapatıyor.
        Hosting'in yayınladığı kök `firebase.json` `hosting.public` = "web".
        """
        bulunan = {p.relative_to(_KOK).as_posix()
                   for p in (_KOK / "web").rglob("*.html")}
        eksik = bulunan - set(self._SAYFALAR) - self._LISTE_DISI
        assert not eksik, (
            f"Yayındaki bu sayfalar bekçisiz: {sorted(eksik)} — ya _SAYFALAR'a "
            f"ekle ya da _LISTE_DISI'na gerekçesiyle yaz")
        # Ters yön: silinen/taşınan bir sayfa listede kalmasın. Var olmayan
        # dosyayı taramak "taradım" yanılsaması üretir.
        assert not (set(self._SAYFALAR) | self._LISTE_DISI) - bulunan, (
            "Listede yayında olmayan sayfa var: taşındıysa yolu düzelt")

    def test_site_ucretsiz_i_ching_vadetmiyor(self):
        """`require_plus("iching")` kapıda; site 'ücretsiz' diyemez."""
        for yol in ("web/index.html", "web/en/index.html"):
            dosya = _KOK / yol
            if not dosya.exists():
                continue
            metin = dosya.read_text(encoding="utf-8").lower()
            for kalip in ("günde 1 i ching", "günde bir i ching",
                          "1 i ching cast a day"):
                assert kalip not in metin, (
                    f"{yol}: I Ching ücretsiz katmanda gösteriliyor ama "
                    f"backend/api/reports.py require_plus('iching') ile "
                    f"kilitliyor")

    def test_iching_gercekten_plus_kapisinda(self):
        """Yukarıdaki iki testin dayanağı: kapı hâlâ orada mı?

        Kapı kaldırılırsa (ürün kararı değişirse) bu test düşer ve site
        metinlerinin de güncellenmesi gerektiği hatırlatılır.
        """
        kaynak = (_KOK / "backend" / "api" / "reports.py").read_text(
            encoding="utf-8")
        assert 'require_plus("iching")' in kaynak, (
            "I Ching kapısı kalkmış: web sitesi ve mağaza metinleri de "
            "gözden geçirilmeli")


class TestKullanimSartlariKopyalari:
    """Kullanım şartları DÖRT yerde duruyor; hiçbiri geride kalmamalı.

    Ortaklık maddesi ilk turda yalnız iki HTML kopyasına eklendi. Somut
    kırılma ölçülmedi ama yolu açıktı: markdown dosyası şartların "kaynağı"
    sanılıp web sayfası ondan yeniden üretilirse (ya da hukukçuya o
    gönderilirse) madde SESSİZCE silinir — hiçbir test patlamazdı. Mobil
    kopyada eksik kalması daha kötüsü: uygulama içinde gösterilen şartlar,
    kabul edilen şartlardır.

    Bekçi bilerek KIRILGAN DEĞİL: dört biçim (markdown, iki HTML, Dart dize
    literalleri) birebir aynı metni taşıyamaz, o yüzden tam eşitlik değil
    maddenin ANLAMINI taşıyan kısa çapalar aranır. Çapa seçimi ölçüt: madde
    silinirse ya da anlamı kayarsa (ödül ilk aboneliğe bağlı değilse, süre
    değişirse, devredilemezlik kalkarsa) çapa düşer.
    """

    #: (yol, dil, biçim). Dart dosyası İKİ gövde taşır, o yüzden iki satır.
    _KOPYALAR = (
        ("docs/legal/kullanim-sartlari.md", "tr", "markdown"),
        ("web/legal/kullanim.html", "tr", "html"),
        ("web/en/legal/terms.html", "en", "html"),
        ("apps/mobile/lib/features/profile/legal_texts.dart", "tr", "dart"),
        ("apps/mobile/lib/features/profile/legal_texts.dart", "en", "dart"),
    )

    #: Türkçe çapalar EK ALMADAN önce kesilir: "abonelik" kelimesi ek alınca
    #: "aboneliği" oluyor (k→ğ yumuşaması), yani tam kelime çapa olarak
    #: KULLANILAMAZ — bu bekçi ilk koşuşunda tam o yüzden düştü.
    _CAPALAR = {
        "tr": ("ortaklık program", "ilk rytho+ abonel", "15 gün",
               "devredilemez"),
        "en": ("partner programme", "first rytho+ subscription", "15 days",
               "cannot be transferred"),
    }

    #: Çapadan ÖNCE gelmemesi gereken karakterler. Ham alt dize eşleşmesi
    #: yanlış pozitif üretir (bu depoda ölçüldü: "ilişkimde" içinde "iş",
    #: `feedback` içinde `HapticFeedback`), o yüzden eşleşme kelime başına
    #: bağlanır.
    _HARF = "0-9A-Za-zçğıöşü"

    @staticmethod
    def _dart_govdesi(kaynak: str, dil: str) -> str:
        ad = "kTermsOfUseTr" if dil == "tr" else "kTermsOfUseEn"
        parcalar = kaynak.split(f"const LegalSections {ad} = [", 1)
        assert len(parcalar) == 2, f"{ad} sabiti bulunamadı — adı mı değişti?"
        return parcalar[1].split("\n];", 1)[0]

    @classmethod
    def _duzlestir(cls, yol: str, bicim: str, dil: str) -> str:
        metin = (_KOK / yol).read_text(encoding="utf-8")
        if bicim == "dart":
            metin = cls._dart_govdesi(metin, dil)
            # `//` yorumları atılır: madde silinip yerine "ortaklık programı
            # web'de anlatılıyor" diye bir yorum bırakılsa bekçi buna
            # kanmamalı. Ardından tek tırnaklar atılır, çünkü Dart uzun metni
            # yan yana dizilmiş dize literallerine bölüyor ve bir çapa iki
            # literalin arasına düşebiliyor.
            metin = re.sub(r"^[ \t]*//.*$", " ", metin, flags=re.M)
            metin = metin.replace("'", " ")
        elif bicim == "html":
            metin = _yorumsuz_html(metin)
            # Etiketler boşluğa çevrilir: `<strong>15 gün</strong>` gibi
            # vurgular çapayı ortadan kesebiliyor.
            metin = re.sub(r"<[^>]+>", " ", metin)
        return _turkce_kucult(re.sub(r"\s+", " ", metin))

    def test_dort_kopya_da_ortaklik_maddesini_tasir(self):
        for yol, dil, bicim in self._KOPYALAR:
            assert (_KOK / yol).exists(), f"{yol} yok"
            duz = self._duzlestir(yol, bicim, dil)
            for capa in self._CAPALAR[dil]:
                kalip = rf"(?<![{self._HARF}]){re.escape(capa)}"
                assert re.search(kalip, duz), (
                    f"{yol} ({dil}): kullanım şartlarındaki ortaklık maddesi "
                    f"eksik ya da anlamı kaymış — {capa!r} bulunamadı. "
                    f"Dört kopya da güncellenmeli: docs/legal, iki web "
                    f"sayfası ve apps/mobile/.../legal_texts.dart")

    def test_metindeki_15_gun_koddaki_pencereyle_ayni(self):
        """Şartlar "15 gün" diyor; kapı gerçekten 15 günde mi açılıyor?

        Ölçülmeyen söylenmez ilkesinin hukuk metni ayağı. Kod penceresi
        değişirse bu test düşer ve dört kopyanın da gözden geçirilmesi
        gerektiği hatırlatılır.
        """
        kaynak = (_KOK / "backend" / "services"
                  / "partner_service.py").read_text(encoding="utf-8")
        # `$` yerine `\b`: satır sonuna bir yorum eklenmesi (örn.
        # `MATURATION_DAYS = 15  # iade penceresi`) bekçiyi YANLIŞ ALARMA
        # düşürüyordu. `\b` yine ısırır — 14 ya da 150 eşleşmez.
        assert re.search(r"^MATURATION_DAYS = 15\b", kaynak, flags=re.M), (
            "Olgunlaşma penceresi 15 gün değil artık: kullanım şartlarının "
            "DÖRT kopyasındaki süre de düzeltilmeli")

    def test_metindeki_dusme_maddesi_koddaki_yola_dayaniyor(self):
        """Şartlar "çıkarılma halinde kesinleşmemiş hakedişler düşer" diyor.

        Bu cümle bu turda YAZILDI ve tek bir kod yoluna dayanıyor:
        olgunlaştırma, ortak pasifse bekleyen hakedişi `partner_inactive`
        gerekçesiyle `void` ediyor. Yol kalkarsa dört hukuk kopyası da
        sessizce yalan söyler — sahibi "düştü" denen parayı borç sanar.
        Sabit yalnız TANIMLI olması yetmez, bir `voidReason` olarak
        YAZILIYOR olması aranır; tanımlı ama kullanılmayan bir sabit
        maddeyi karşılamaz.
        """
        kaynak = (_KOK / "backend" / "services"
                  / "partner_service.py").read_text(encoding="utf-8")
        assert re.search(r'"voidReason":\s*VOID_REASON_PARTNER_INACTIVE',
                         kaynak), (
            "Pasif ortağın bekleyen hakedişini düşüren yol yok: kullanım "
            "şartlarının DÖRT kopyasındaki 'kesinleşmemiş hakedişler düşer' "
            "maddesi dayanaksız kalır")


class TestJetonIddialari:
    """Pazarlama sayfalarının JETON cümleleri koddaki gerçeğe bağlanır.

    Bu sınıf tek bir cümlenin üç ayrı hâlinden doğdu; üçü de aynı sınıf
    kusurdu — sayfa, ürünün PARA tarafı hakkında ölçülmemiş bir şey
    söylüyordu:

    1. Sayfa bedelleri kendi içinde sayıyordu ("sohbet 1 · I Ching 2 ·
       natal/BaZi 5"). Liste EKSİKTİ (ikili okuma 3 ve yüz okuma 5 yoktu)
       ve `TOKEN_COSTS` değişince sessizce bayatlardı.
    2. Yerine "uygulama bir raporun kaça geldiğini harcamadan önce
       gösterir" kondu. Ölçüm bunu yalanladı: bedeli harcamadan ÖNCE
       gösteren TEK ekran İ Ching (`iching_tab.dart`, rozet
       `/reports/iching/status` yanıtındaki `token_cost`tan okunuyor).
       Derin raporlar, ikili okuma, yüz okuma ve sohbet göstermiyor.
    3. Onun yerine gelen cümle de tekrar okumayı KOŞULSUZ bedava saydı.
       Oysa harcamayı atlatan şey önbellek (`report_service
       ._cached_generate`) ve önbellek ÖMÜRLÜ — ömür dolunca yeniden
       üretim olur ve bedel düşer.

    Bekçi bilerek İKİ TARAFLI: sayfadaki cümle kod değiştiğinde de düşer,
    çünkü asıl risk sayfanın yalan söylemesi değil, altındaki kodun
    sessizce kaymasıdır.
    """

    _SAYFALAR = ("web/index.html", "web/en/index.html")

    #: "Bedeli harcamadan ÖNCE görürsün" sınıfı iddianın işaretleri:
    #: (zaman kalıbı, AYNI cümlede aranan bedel kelimeleri). İkisi birlikte
    #: aranır çünkü "harcamadan önce" tek başına masum bir cümle de kurar
    #: (örn. "niyetsiz soru çekim hakkını harcamadan geri çevrilir").
    _ONCEDEN_GOSTERIR = (
        (r"harcamadan\s+önce", ("bedel", "kaça", "kaç jeton", "kaç kredi",
                                "fiyat")),
        (r"before\s+(?:you\s+)?spend", ("cost", "price", "how much")),
        (r"before\s+spending", ("cost", "price", "how much")),
    )

    @classmethod
    def _govde(cls, yol: str) -> str:
        """Sayfanın yorumsuz, tek boşluklu, Türkçe-küçültülmüş gövdesi.

        Yorumlar ATILIR: aşağıdaki bekçilerin yarısı bir cümlenin
        YOKLUĞUNU arıyor ve o yokluğun GEREKÇESİ aynı dosyada, HTML yorumu
        içinde duruyor (yasak cümlenin adını anan yorum). Bu depoda tam bu
        yüzden iki kez bekçi patladı. Boşluk tekleştirme de şart: cümleler
        satır sonlarıyla bölünmüş durumda, ham metinde "Aboneler ayrıca
        süresiz geçerli\\n          jeton paketi" yazıyor.
        """
        metin = _yorumsuz_html((_KOK / yol).read_text(encoding="utf-8"))
        return _turkce_kucult(re.sub(r"\s+", " ", metin))

    @staticmethod
    def _token_bedelleri() -> dict[str, int]:
        """`wallet.TOKEN_COSTS` tablosunu KAYNAKTAN okur.

        İçe alma yerine metin okuma: bu bekçinin derdi çalışma zamanı
        davranışı değil, iki yerde yazılı iki sayının aynı olup olmadığı.
        """
        kaynak = (_KOK / "backend" / "core" / "wallet.py").read_text(
            encoding="utf-8")
        tablo = re.search(r"TOKEN_COSTS: dict\[str, int\] = \{(.*?)\n\}",
                          kaynak, flags=re.S)
        assert tablo, "TOKEN_COSTS tablosu bulunamadı: bekçi kör kalırdı"
        return {ad: int(deger)
                for ad, deger in re.findall(r'"(\w+)":\s*(\d+)',
                                            tablo.group(1))}

    def test_sitede_bedeli_harcamadan_once_gosterir_iddiasi_yok(self):
        """Ölçüm: bedeli önceden gösteren tek ekran İ Ching.

        Bir tur boyunca iki sayfada da bu iddia yazılıydı ve kimse ölçmedi.
        """
        for yol in self._SAYFALAR:
            govde = self._govde(yol)
            for kalip, kelimeler in self._ONCEDEN_GOSTERIR:
                for eslesme in re.finditer(kalip, govde):
                    pencere = govde[max(0, eslesme.start() - 160):
                                    eslesme.end() + 160]
                    for kelime in kelimeler:
                        assert kelime not in pencere, (
                            f"{yol}: '{eslesme.group(0)}' ile '{kelime}' aynı "
                            f"cümlede — bedeli harcamadan önce gösteren tek "
                            f"ekran İ Ching (iching_tab.dart). Uygulamanın "
                            f"geneli için bu iddia yazılamaz; mağaza "
                            f"ekranındaki bedel satırına işaret et")

    def test_sitedeki_iki_iddianin_dayanagi_kodda_duruyor(self):
        """Sayfa "bedeller jeton mağazasında yazılıdır" diyor — gerçekten?

        İkinci iddia: "jeton yalnız yeni bir rapor üretilirken düşer".
        Dayanağı `_cached_generate`in SIRASI — önbellek dolu dönüşü
        `spend()` çağrısından ÖNCE olmak zorunda. Sıra ters çevrilse
        testler yine geçerdi (harcama yine bir kez işler), yalnız sayfadaki
        ve mağaza ekranındaki cümle yalan olurdu.
        """
        ekran = (_KOK / "apps" / "mobile" / "lib" / "features" / "paywall"
                 / "token_store_screen.dart").read_text(encoding="utf-8")
        assert "l10n.tokenCostsNote" in ekran, (
            "Jeton mağazası ekranı bedel satırını artık çizmiyor: iki "
            "pazarlama sayfasındaki 'bedeller jeton mağazasında yazılıdır' "
            "cümlesi dayanaksız kaldı")

        kaynak = (_KOK / "backend" / "services"
                  / "report_service.py").read_text(encoding="utf-8")
        govde = kaynak[kaynak.index("def _cached_generate("):]
        govde = govde[:govde.index("\ndef ", 1)]
        onbellek = govde.index('return {"text": cached, "cached": True}')
        harcama = govde.index("spend()")
        assert onbellek < harcama, (
            "_cached_generate artık önbellek dolu olsa da harcıyor: "
            "'hazır duran rapora yeniden bakmak hiç düşürmez' cümlesi "
            "(iki web sayfası + l10n tokenCostsNote) yalan oldu")

    def test_magazadaki_bedel_satiri_koddaki_bedellerle_ayni(self):
        """Mağazadaki bedel satırı ELLE yazılmış bir l10n dizesi.

        `/wallet` yanıtı `costs` haritasını gönderiyor ve `wallet.dart` onu
        ayrıştırıyor, ama arayüz onu HİÇ kullanmıyor. Yani `TOKEN_COSTS`
        değiştiği an ekrandaki rakam sessizce yanlışa düşer — ve sayfadaki
        "bedeller jeton mağazasında yazılıdır" cümlesi yanlış bir tabloya
        işaret etmiş olur. Sayfanın kendisi artık rakam saymadığı için
        bayatlama riskinin tamamı bu tek dizede toplandı; bekçi oraya
        kondu.
        """
        bedeller = self._token_bedelleri()
        #: Satır derin raporları TEK sayıyla özetliyor; özet ancak hepsi
        #: aynı bedeldeyken doğru.
        derin = ("natal", "bazi", "synastry", "face", "birth_hexagram",
                 "solar_return", "progressions")
        ayri = {ad: bedeller[ad] for ad in derin if ad in bedeller}
        assert len(set(ayri.values())) == 1, (
            f"Derin raporların bedeli artık tek sayı değil ({ayri}): mağaza "
            f"satırındaki 'derin raporlar ve yüz okuma N kredi' özeti "
            f"yanlış oldu, l10n dizesi ayrıştırılmalı")
        derin_bedel = next(iter(set(ayri.values())))

        capalar = {
            "app_tr.arb": (f"Sohbet mesajı {bedeller['chat']}",
                           f"I Ching {bedeller['iching']}",
                           f"ikili dinamik {bedeller['dyad']}",
                           f"derin raporlar ve yüz okuma {derin_bedel}"),
            "app_en.arb": (f"Chat message {bedeller['chat']}",
                           f"I Ching {bedeller['iching']}",
                           f"daily dyad {bedeller['dyad']}",
                           f"deep reports and face reading {derin_bedel}"),
        }
        for dosya, beklenen in capalar.items():
            yol = _KOK / "apps" / "mobile" / "lib" / "l10n" / dosya
            satir = json.loads(yol.read_text(encoding="utf-8"))[
                "tokenCostsNote"]
            for capa in beklenen:
                assert capa in satir, (
                    f"{dosya}: tokenCostsNote '{capa}' demiyor — "
                    f"wallet.TOKEN_COSTS ile ayrıştı. Mağaza ekranı yanlış "
                    f"bedel gösteriyor, iki web sayfası da oraya işaret "
                    f"ediyor")

    def test_sitedeki_aylik_hak_koddaki_sayiyla_ayni(self):
        """K1: hak 300'den 100'e indi. Sayfadaki sayı kodu izlemek zorunda.

        Eski hâl iki sayfada da 300 yazıyordu; sayı tek bir yerde
        (`MONTHLY_TOKEN_ALLOWANCE`) tanımlı olduğu için ayrışma sessizdi.
        """
        kaynak = (_KOK / "backend" / "core" / "wallet.py").read_text(
            encoding="utf-8")
        eslesme = re.search(r"^MONTHLY_TOKEN_ALLOWANCE = (\d+)\b", kaynak,
                            flags=re.M)
        assert eslesme, "MONTHLY_TOKEN_ALLOWANCE bulunamadı: bekçi kör kalırdı"
        hak = int(eslesme.group(1))

        kaliplar = {"web/index.html": r"aylık (\d+) jeton",
                    "web/en/index.html": r"(\d+) tokens every month"}
        for yol, kalip in kaliplar.items():
            govde = self._govde(yol)
            bulunan = re.findall(kalip, govde)
            assert bulunan, (
                f"{yol}: aylık jeton hakkı cümlesi kayboldu — kalıp "
                f"değiştiyse bekçi de düzeltilmeli, yoksa sayı sessizce "
                f"bayatlar")
            for sayi in bulunan:
                assert int(sayi) == hak, (
                    f"{yol}: sayfa aylık {sayi} jeton diyor, kod {hak} "
                    f"veriyor (wallet.MONTHLY_TOKEN_ALLOWANCE)")

    def test_sitede_paketler_yalniz_aboneye_vadediliyor(self):
        """K2: paketler abone olmayana mağazada HİÇ gösterilmiyor.

        Eski cümle "dileyen ayrıca süresiz geçerli jeton paketi alır"
        diyordu — ekran onu abone kapısının arkasına aldıktan sonra bu
        cümle satın alınamayan bir ürün vadediyordu.
        """
        beklenen = {"web/index.html": ("jeton paketi", "abone"),
                    "web/en/index.html": ("token packs", "subscriber")}
        for yol, (urun, ozne) in beklenen.items():
            govde = self._govde(yol)
            cumleler = [c for c in govde.split(".") if urun in c]
            assert cumleler, f"{yol}: '{urun}' cümlesi kayboldu"
            for cumle in cumleler:
                assert ozne in cumle, (
                    f"{yol}: paket cümlesi '{ozne}' demiyor —"
                    f" paketler yalnız aboneye satılıyor"
                    f" (token_store_screen.dart `_PaketlerPlusaOzel`)")

        # Kapının ADI değil KULLANIM YERİ aranır. İlk hâl yalnız
        # "_PaketlerPlusaOzel" dizesini arıyordu ve mutasyonda YEŞİL kaldı:
        # pencere ağacından sökülse bile sınıf TANIMI dosyada duruyor, yani
        # ad her hâlükârda bulunuyordu. Aranan şey `!abone` dalının
        # gerçekten o pencereyi seçmesi.
        ekran = (_KOK / "apps" / "mobile" / "lib" / "features" / "paywall"
                 / "token_store_screen.dart").read_text(encoding="utf-8")
        assert re.search(r"!abone\)\s*const _PaketlerPlusaOzel\(\)", ekran), (
            "Mağazadaki abone kapısı kalkmış: iki web sayfasındaki "
            "'aboneler ayrıca paket alabilir' daraltması gereksiz kaldı, "
            "cümleler gözden geçirilmeli")

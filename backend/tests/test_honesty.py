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


def _aylik_hak() -> int:
    """`wallet.MONTHLY_TOKEN_ALLOWANCE` — KAYNAKTAN okunur, ICE ALINMAZ.

    Dosyanin geri kalaniyla ayni yontem: bu bekci iki yerde YAZILI iki
    sayinin ayni olup olmadigini olcuyor, calisma zamani davranisini
    degil.

    ⚠️ Modul duzeyinde ve BIR KEZ: sayi hem bir testin iddiasinda hem
    `TestPazarlamaDili._YASAKLAR` GEREKCESINDE geciyor ve iki ayri okuyucu
    olsaydi biri guncellenip oteki bayatlardi — nitekim dogrulama turunda
    (2026-10-03) tam bu oldu: gerekce ELLE "300" yaziyordu, sunucu 100
    veriyordu. Bulunamazsa modul HIC yuklenmez; sessizce kor kalmaktansa
    yuklenmemesi istenir.
    """
    kaynak = (_KOK / "backend" / "core" / "wallet.py").read_text(
        encoding="utf-8")
    eslesme = re.search(r"^MONTHLY_TOKEN_ALLOWANCE = (\d+)\b", kaynak,
                        flags=re.M)
    assert eslesme, "MONTHLY_TOKEN_ALLOWANCE bulunamadi: bekci kor kalirdi"
    return int(eslesme.group(1))


#: Aylik hak — gerekce metinlerine ve iddialara BURADAN giriyor.
_AYLIK_HAK = _aylik_hak()


def _olgunlasma_gunu() -> int:
    """`partner_service.MATURATION_DAYS` — KAYNAKTAN okunur.

    `\b` ile baglanir, `$` ile DEGIL: satir sonuna yorum eklenmesi
    (`MATURATION_DAYS = 15  # iade penceresi`) bekciyi yanlis alarma
    dusuruyordu. `\b` yine isirir — 14 ya da 150 eslesmez.
    """
    kaynak = (_KOK / "backend" / "services" / "partner_service.py").read_text(
        encoding="utf-8")
    eslesme = re.search(r"^MATURATION_DAYS = (\d+)\b", kaynak, flags=re.M)
    assert eslesme, "MATURATION_DAYS bulunamadi: bekci kor kalirdi"
    return int(eslesme.group(1))


#: Olgunlasma penceresi — hem hukuk kopyalarinin hem ORTAKLIK
#: SAYFALARININ iddiasi buna bagli.
_OLGUNLASMA_GUNU = _olgunlasma_gunu()


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
                 "web/affiliate/index.html",
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

    #: "Sınırsız" SINIFI — hepsi aynı vaadin ayrı kılığı. ozellikler.md
    #: "İddia edilemeyecekler" tablosu "Sınırsız AI"yı yasaklıyor; doğrusu
    #: "Ayda N AI kredisi". Eski liste yalnız "sınırsız sohbet" / "unlimited
    #: chat" diyordu ve vaat ÜÇ başka kılıkta yaşıyordu (ölçüldü
    #: 2026-10-10, core/messages.py quota.*): "Rytho+ ile sınırsız
    #: konuşabilirsin", "removes the limit", "istediğin kadar çekebilirsin"
    #: / "as often as you like". Nesne kelimesi ("sohbet") eşleşmeyi
    #: daraltıyordu; vaadin kendisi yasak, nesnesi değil. Bu demet
    #: `test_yasak_gerekcesindeki_aylik_hak_SABITTEN_geliyor`un seçicisi:
    #: sınıfın her üyesinin gerekçesi aylık hakkı sabitten söylemek zorunda.
    _SINIRSIZ_SINIFI = ("sınırsız", "sinirsiz", "limitsiz", "unlimited",
                        "istediğin kadar", "dilediğin kadar",
                        "as often as you like", "removes the limit")

    #: (aranan, neden yasak)
    _YASAKLAR = (
        ("nasa", "ozellikler.md §12b: 'NASA' ASLA — doğrusu 'astronomik "
                 "efemeris verisi'"),
        # ⚠️ Gerekçe ELLE YAZILMAZ, sabitten türetilir. Doğrulama turunda
        # (2026-10-03) iki satır da "300 kredi" diyordu; sunucu 100
        # veriyordu (`wallet.MONTHLY_TOKEN_ALLOWANCE`). Gerekçe, bekçi
        # kızdığında okunan tek metindir — yanlış sayı tam o anda
        # karar vericiye gider. Üstelik bu tur 300→100 ayrışmasını
        # kapatmak için vardı ve ayrışmanın son kopyası BEKÇİNİN KENDİ
        # gerekçesinde kalmıştı; `test_belge_tarifesi.py` yalnız
        # `docs/` tarıyor, test kaynağını kimse taramıyor.
        # Sınıfın HER üyesi burada ve gerekçesinde `_AYLIK_HAK`tan başka
        # sayı YOK (§ işaretli madde numarası bile) — aşağıdaki bekçi onu
        # sayıyor.
        ("sınırsız",
         f"Rytho+ aylık {_AYLIK_HAK} kredidir; sınırsız değil"),
        ("sinirsiz",
         f"Rytho+ aylık {_AYLIK_HAK} kredidir; sınırsız değil (ASCII yazım)"),
        ("limitsiz",
         f"Rytho+ aylık {_AYLIK_HAK} kredidir; limitsiz değil"),
        ("istediğin kadar",
         f"'istediğin kadar' = sınırsız vaadi; Rytho+ aylık {_AYLIK_HAK} "
         f"kredidir ve mesaj/çekim başına bedel düşer"),
        ("dilediğin kadar",
         f"'dilediğin kadar' = sınırsız vaadi; Rytho+ aylık {_AYLIK_HAK} "
         f"kredidir ve mesaj/çekim başına bedel düşer"),
        ("unlimited",
         f"Rytho+ is {_AYLIK_HAK} credits a month, not unlimited"),
        ("as often as you like",
         f"'as often as you like' = unlimited; Rytho+ is {_AYLIK_HAK} "
         f"credits a month and each message/cast costs credits"),
        ("removes the limit",
         f"the limit is not removed: Rytho+ is {_AYLIK_HAK} credits a month"),
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

    def test_yasak_gerekcesindeki_aylik_hak_SABITTEN_geliyor(self):
        """Gerekçe metnindeki sayı `MONTHLY_TOKEN_ALLOWANCE` ile aynı.

        NEDEN bu test var (ölçüldü 2026-10-03, doğrulama turu): iki gerekçe
        satırı ELLE "300" yazıyordu, sunucu 100 veriyordu. Gerekçe yanlış
        sayı taşıyorsa kusurdur — bekçi kızdığında okunan TEK metin odur ve
        yanlış sayı tam o anda karar vericiye gider. Üstelik bu paket
        300→100 ayrışmasını kapatmak için vardı: ayrışmanın son kopyası
        bekçinin KENDİ gerekçesinde kalmıştı ve `docs/` tarayan bekçi
        (`test_belge_tarifesi.py`) test kaynağına hiç bakmıyor.

        Bugün satırlar f-string, yani sapma yapısal olarak imkânsız. Test
        o YAPIYI çiviliyor: biri f-string'i tekrar sabit metne çevirirse
        kırmızı olur. İki yöne de çalışıyor — sayı GEÇMEK zorunda (gerekçe
        hakkı anmayı bırakırsa yasak kelimenin niçin yasak olduğu kaybolur)
        ve geçen sayı sabitle AYNI olmak zorunda.

        Seçici `_SINIRSIZ_SINIFI`: eski hâli "sohbet/chat içeren aranan"
        idi ve tam iki girdi sayıyordu; liste vaadin öbür kılıklarına
        ("istediğin kadar", "removes the limit", …) genişleyince o seçici
        yeni girdilerin gerekçesini HİÇ görmezdi — elle yazılmış bir "300"
        yine bekçisiz kalırdı. Sınıfın her üyesi listede olmak VE aynı
        sayıyı söylemek zorunda.
        """
        hak = str(_AYLIK_HAK)
        gerekceler = {aranan: neden for aranan, neden in self._YASAKLAR
                      if aranan in self._SINIRSIZ_SINIFI}
        eksik = set(self._SINIRSIZ_SINIFI) - set(gerekceler)
        assert not eksik, (
            f"sınırsız sınıfının üyesi _YASAKLAR'da yok: {sorted(eksik)} — "
            "vaat o kılıkta bekçisiz kalır")
        for neden in gerekceler.values():
            assert hak in neden, (
                f"gerekçe aylık hakkı {hak} demiyor: {neden!r} — "
                f"`wallet.MONTHLY_TOKEN_ALLOWANCE` ile ayrışmış. Sayı elle "
                f"yazılmaz, `_AYLIK_HAK` ile kurulur.")
            # Eski sayının BULUNMAMASI da ayrıca sorulur: f-string'e
            # dönüştürülürken eski literal cümlede kalsa (ör. "100 kredidir
            # — eskiden 300'dü") gerekçe yine iki sayı söylerdi ve bekçi
            # kızdığında hangisinin geçerli olduğu belirsiz kalırdı.
            oteki = [p for p in re.findall(r"\d+", neden) if p != hak]
            assert not oteki, (
                f"gerekçede aylık haktan BAŞKA sayı var ({oteki!r}): "
                f"{neden!r} — bekçi kızdığında hangi sayının geçerli "
                f"olduğu belirsiz kalır")

    def test_arb_ve_sunucu_metinlerinde_yasak_vaat_yok(self):
        """Yasak ifade yalnız web sayfalarında değil, UYGULAMANIN kendi
        cümlelerinde de aranır: sunucunun 402/429 `detail` metinleri
        (`core.messages._MESSAGES`) ve iki ARB sözlüğü.

        Neden gerekti (ölçüldü 2026-10-10): web sayfaları temizken sunucu
        kota metni "Rytho+ ile sınırsız konuşabilirsin" / "removes the
        limit" / "istediğin kadar çekebilirsin" diyordu ve istemci `detail`i
        olduğu gibi ekrana basıyor (friendlyError) — yani vaat, bekçinin
        taramadığı bir yüzeyden kullanıcıya ulaşıyordu. Kota dolan kullanıcı
        bu metni tam satın alma kararı anında okur.

        Sunucu metinleri İÇE ALINARAK okunur, ham dosya DEĞİL: messages.py
        yasak kelimeyi niçin yasakladığını yorumda anlatıyor ve yorumu
        tarayan bekçi kendi gerekçesine takılır (bu depoda iki kez oldu).
        ARB JSON olarak yüklenir, `@`-meta girdileri (dict/placeholder
        açıklamaları) değer sayılmaz.
        """
        from core.messages import _MESSAGES

        kaynaklar: dict[str, str] = {}
        for anahtar, ceviriler in _MESSAGES.items():
            for dil, metin in ceviriler.items():
                kaynaklar[f"core/messages.py:{anahtar}/{dil}"] = metin
        for dosya in ("app_tr.arb", "app_en.arb"):
            yol = _KOK / "apps" / "mobile" / "lib" / "l10n" / dosya
            sozluk = json.loads(yol.read_text(encoding="utf-8"))
            for anahtar, deger in sozluk.items():
                if anahtar.startswith("@") or not isinstance(deger, str):
                    continue
                kaynaklar[f"{dosya}:{anahtar}"] = deger

        # Tarama BOŞ olmasın: kaynaklardan biri taşınırsa/boşalırsa bekçi
        # "hiçbir şey bulamadım" diye yeşil kalmamalı.
        assert any(k.startswith("core/messages.py:quota.") for k in kaynaklar)
        assert sum(k.startswith("app_tr.arb:") for k in kaynaklar) > 100
        assert sum(k.startswith("app_en.arb:") for k in kaynaklar) > 100

        for yer, metin in kaynaklar.items():
            kucuk = _turkce_kucult(metin)
            for aranan, neden in self._YASAKLAR:
                assert aranan not in kucuk, (
                    f"{yer} içinde yasak ifade {aranan!r} — {neden}: "
                    f"{metin!r}")

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
        # Pencere modül düzeyindeki TEK okuyucudan gelir
        # (`_olgunlasma_gunu`): sayı burada ELLE yazılıydı ("= 15") ve
        # aynı sayı başka bir iddiada da geçiyor, yani iki okuyucu
        # bayatlamaya giden yoldu.
        assert _OLGUNLASMA_GUNU == 15, (
            f"Olgunlaşma penceresi artık {_OLGUNLASMA_GUNU} gün: metnin "
            f"ALTI kopyasındaki süre de düzeltilmeli — kullanım şartlarının "
            f"dört kopyası (`_KOPYALAR`) VE iki ortaklık sayfası "
            f"(`_ORTAKLIK_SAYFALARI`). ⚠️ Bu mesaj bir tur boyunca 'DÖRT "
            f"kopya' diyordu ve o sayı EKSİKTİ (ölçüldü 2026-10-03): iki "
            f"ortaklık sayfası da pencereyi yazıyor ve mesajı okuyan onları "
            f"atlardı.")

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


class TestOrtaklikSayfalari:
    """Herkese açık ortaklık sayfaları, PARA zamanlamasını koddan sapamaz.

    NEDEN bu sınıf doğdu (ölçüldü 2026-10-03, doğrulama turu): olgunlaşma
    penceresi "15 gün" ALTI yüzeyde yazılı ama bekçi yalnız DÖRDÜNÜ
    tanıyordu (`TestKullanimSartlariKopyalari._KOPYALAR`). Kalan ikisi
    `web/ortaklik.html` (üç kez) ve `web/en/partners.html` (iki kez) —
    ve bunlar hukuk metni değil PAZARLAMA yüzeyi, yani ortağın "paramı ne
    zaman alırım" sorusunu okuduğu yer.

    Kırılma iki kademeliydi: pencere değişse `MATURATION_DAYS` bekçisi
    kırmızı OLUR (yani sapma yakalanır), ama o bekçinin mesajı "DÖRT
    kopyadaki süre de düzeltilmeli" diyordu. Mesajı izleyen dördü düzeltir,
    iki ortaklık sayfası eski süreyi söylemeye devam eder ve bunu hiçbir
    test görmez. Yani kusur sayının kendisinde değil, ONARIM TALİMATININ
    eksikliğindeydi — CLAUDE.md'ye göre eksik gerekçe kusurdur.

    ⚠️ KAPSAMIN SINIRI ölçülerek seçildi: bu iki sayfadaki GÜN sayılarının
    TAMAMI pencereye eşit olmak zorunda. Ölçüm (2026-10-03): TR'de üç,
    EN'de iki geçiş var ve hepsi penceredir — sayfalar başka bir süre
    tartışmıyor. Hukuk kopyalarına aynı kural konamazdı
    (`web/legal/kullanim.html` ayrıca "3 gün" deneme süresini anıyor), bu
    yüzden kapsam o sayfalara GENİŞLETİLMEDİ. Sayfalara ikinci bir süre
    eklenirse bu test kırmızı olur ve çapanın bilerek daraltılmasını
    ister — sessizce geçmez.
    """

    #: Pencereyi yazan PAZARLAMA yüzeyleri. Hukuk kopyaları ayrı sınıfta.
    _ORTAKLIK_SAYFALARI = ("web/ortaklik.html", "web/en/partners.html")

    #: Gün sayısı kalıbı: TR ekli hâlleri ("günlük") ve EN tekil/çoğul.
    _GUN = re.compile(r"(\d+)\s*(?:günlük|gün|days|day)\b")

    def test_ortaklik_sayfalarindaki_SURE_koddaki_pencereyle_ayni(self):
        for yol in self._ORTAKLIK_SAYFALARI:
            dosya = _KOK / yol
            assert dosya.exists(), (
                f"{yol} yok — sayfa taşındıysa bu bekçi de yeniden "
                f"nişanlanmalı, yoksa para zamanlaması bekçisiz kalır")
            metin = re.sub(r"<[^>]+>", " ",
                           _yorumsuz_html(dosya.read_text(encoding="utf-8")))
            metin = re.sub(r"\s+", " ", metin)
            bulunan = [int(s) for s in self._GUN.findall(metin)]
            # Taban: iddia GEÇMEK zorunda. Yoksa üstteki eşitlik kontrolü
            # "bulunan her sayı doğru" diyerek, hiç sayı kalmadığında da
            # yeşil kalırdı — yani ortağa pencereyi söylemeyi bırakmak
            # sessizce geçerdi.
            assert bulunan, (
                f"{yol}: olgunlaşma penceresini anan gün sayısı YOK. "
                f"Cümle silindiyse geri konur; yeniden yazıldıysa "
                f"`TestOrtaklikSayfalari._GUN` kalıbı da birlikte "
                f"güncellenir (iddia kalıptan kaçarsa bekçi hiçbir şey "
                f"ölçmez).")
            sapma = [s for s in bulunan if s != _OLGUNLASMA_GUNU]
            assert not sapma, (
                f"{yol}: sayfa {sapma} gün diyor, kod {_OLGUNLASMA_GUNU} "
                f"gün bekliyor (`partner_service.MATURATION_DAYS`). Bu "
                f"sayfa ortağın 'paramı ne zaman alırım' sorusunu okuduğu "
                f"yer; sapma doğrudan yanlış beyandır.")


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

    #: Mağaza ekranı: sayfanın işaret ettiği bedel satırının kaynağı.
    _MAGAZA_EKRANI = ("apps/mobile/lib/features/paywall/"
                      "token_store_screen.dart")

    #: Bedel satırının SUNUCUDAN kurulduğunu söyleyen kablo. Çapa tek bir
    #: ada bağlanmıyor; ÜÇ TERİM birden aranıyor: biçimlendirici çağrılıyor
    #: (`bedelNotu`), şablonu çeviriden alıyor (`l10n.tokenCostsNote`),
    #: ve ikinci argüman bir `.costs` ALANI. Terimler BİLEREK bağımsız
    #: değil — hepsi TEK bir çağrının içinde aranıyor, çünkü ölçülen şey
    #: üç olgunun ayrı ayrı var olması değil BİRBİRİNE BAĞLI olması
    #: (dosyada üçü ayrı ayrı dursa satır yine şablonla çizilebilir).
    #: Üçüncüsü asıl olan — `bedelNotu(…, const {})` yazmak kodu
    #: derlenebilir bırakır, satır ekranda da görünür (işlev ön koşul
    #: tutmayınca şablonu olduğu gibi döndürüyor), yani de-kablolama
    #: SESSİZDİR. Önceki hâl yalnız `"l10n.tokenCostsNote" in ekran` diye
    #: soruyordu ve o bir VEKİLDİ: satırın ÇİZİLDİĞİNİ ölçüyor, sayıların
    #: nereden geldiğini ölçmüyordu.
    _BEDEL_KABLOSU = re.compile(
        r"bedelNotu\(\s*l10n\s*,"
        r"\s*[A-Za-z_]\w*(?:\.\w+)*\.costs\s*[,)]")

    def test_sitedeki_iki_iddianin_dayanagi_kodda_duruyor(self):
        """Sayfa "bedeller jeton mağazasında yazılıdır" diyor — gerçekten?

        İkinci iddia: "jeton yalnız yeni bir rapor üretilirken düşer".
        Dayanağı `_cached_generate`in SIRASI — önbellek dolu dönüşü
        `spend()` çağrısından ÖNCE olmak zorunda. Sıra ters çevrilse
        testler yine geçerdi (harcama yine bir kez işler), yalnız sayfadaki
        ve mağaza ekranındaki cümle yalan olurdu.
        """
        ekran = (_KOK / self._MAGAZA_EKRANI).read_text(encoding="utf-8")
        assert self._BEDEL_KABLOSU.search(ekran), (
            f"{self._MAGAZA_EKRANI}: bedel satırı artık sunucudan "
            f"kurulmuyor (`bedelNotu(l10n, …costs)` "
            f"kablosu yok). İki pazarlama sayfası 'bedeller jeton "
            f"mağazasında yazılıdır' diyor; satır ya hiç çizilmiyor ya da "
            f"yalnız şablonun kendi sayılarını gösteriyor")

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

    def test_bedel_kablosu_capasinin_DISI_var(self):
        """Üstteki çapa gerçekten ayırt ediyor mu — mutasyonla ölçülüyor.

        NEDEN gerekli: `_BEDEL_KABLOSU` bir VEKİLİN yerine kondu ve çapanın
        kendisi kör olabilir. Bu depoda üç paket "mutasyonların hepsi
        kırmızı" dedi, minimal mutasyonla sınandığında 8 + 11 + 2 kör bekçi
        çıktı — yani "bugün yeşil" bir çapanın bir şey ÖLÇTÜĞÜ kanıt değil.

        Mutasyon BELLEKTE yapılıyor, diske DEĞİL. İki gerekçe: (1)
        `token_store_screen.dart` bu turda başka bir paketin dosyası ve
        yedi ajan aynı depoda çalışıyor — diske inen geçici bir mutasyon
        başka bir ajanın yazısını ezebilirdi; (2) ölçülen metin yine
        GERÇEK dosyanın metni, değişen tek şey bir TERİM (ikinci argüman),
        yani bileşik mutasyonun gürültüsü yok. Emsal: aynı zincirin Dart
        ucu da şablon tarafını sentetik girdiyle ölçüyor
        (`apps/mobile/test/bedel_notu_test.dart`, "denetimin DİŞİ var").
        """
        ekran = (_KOK / self._MAGAZA_EKRANI).read_text(encoding="utf-8")
        eslesme = self._BEDEL_KABLOSU.search(ekran)
        assert eslesme, (
            "ön koşul tutmuyor: kablo bugün yok, yani bu testin ölçtüğü "
            "şey kalmadı (üstteki bekçi zaten kırmızı olmalı)")

        # Son karakter (`,` ya da `)`) korunuyor: mutasyon yalnız İKİNCİ
        # ARGÜMANA dokunsun, çağrının kapanışına değil.
        kuyruk = ekran[eslesme.end() - 1:]

        # M1 — harita sabit boş literale indiriliyor. Gerçek bir gerileme:
        # kod derlenir, satır ekranda GÖRÜNÜR (işlev ön koşul tutmayınca
        # şablonu olduğu gibi döndürüyor), yani kusur sessizdir.
        m1 = (ekran[:eslesme.start()]
              + "bedelNotu(l10n, const {}" + kuyruk)
        assert not self._BEDEL_KABLOSU.search(m1), (
            "çapa KÖR: harita `const {}` ile değiştirildiğinde de "
            "eşleşiyor, yani sunucu bağını hiç ölçmüyor")

        # M2 — biçimlendirici tamamen atlanıp şablon doğrudan çiziliyor.
        # Onarımdan ÖNCEKİ hâl buydu; çapa onu da ayırt etmek zorunda.
        m2 = ekran[:eslesme.start()] + "Text(l10n.tokenCostsNote(1, 2, 3, 5" + kuyruk
        assert not self._BEDEL_KABLOSU.search(m2), (
            "çapa KÖR: `bedelNotu` hiç çağrılmasa da eşleşiyor, yani "
            "eski 'elle yazılmış dizeyi çiz' hâli geri gelse görmez")

    def test_magazadaki_bedel_satiri_koddaki_bedellerle_ayni(self):
        """Mağaza satırının ŞABLONU `TOKEN_COSTS` ile aynı sayıları söyler.

        ⚠️ Bu docstring'in eski hâli "satır ELLE yazılmış bir l10n dizesi,
        arayüz `/wallet` `costs` haritasını HİÇ kullanmıyor" diyordu ve o
        gerekçe artık YANLIŞ (ölçüldü 2026-10-03): ekran satırı
        `bedelNotu(l10n.tokenCostsNote, cuzdan.costs)` ile kuruyor, yani
        dize bedel gerçeğinin ikinci KAYNAĞI değil ŞABLONU. Yanlış gerekçe
        kusurdur — bekçi doğru yeri çiviliyordu ama NİÇİN'i yanlış
        anlatıyordu ve onu okuyan "bu bekçi gereksizleşti" diye karar
        verebilirdi.

        Bekçi gereksizleşMEDİ, iki ölçülmüş sebeple:

        * `bedelNotu` ön koşulları tutmazsa şablonu OLDUĞU GİBİ döndürüyor
          (harita boş, sayı adedi tutmuyor, derin raporlar tek bedelde
          anlaşmıyor). O hâlde ekranda şablonun KENDİ sayıları görünür —
          yani ARB'deki rakamlar hâlâ kullanıcıya gösterilebilen bir yüzey.
        * Eşleştirme KONUMA bağlı: sayılar şablondaki sırayla tüketiliyor.
          Etiket↔sayı bağı bu yüzden aşağıdaki bekçiyle ayrıca çivili.

        İki web sayfası da "bedeller jeton mağazasında yazılıdır" diyerek
        bu satıra işaret ediyor.
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

        # D7: şablon artık SAYI taşımıyor, yer tutucu taşıyor — her etiketin
        # yanında kendi yer tutucusu; sayılar `bedelNotu` ile sunucudan.
        # `derin_bedel` yukarıda yine ölçülüyor: özetin tek sayı olabilmesi
        # sunucu tarafının değişmezi.
        assert derin_bedel > 0
        capalar = {
            "app_tr.arb": ("Sohbet mesajı {chat}", "I Ching {iching}",
                           "ikili dinamik {dyad}",
                           "derin raporlar ve yüz okuma {deep}"),
            "app_en.arb": ("Chat message {chat}", "I Ching {iching}",
                           "daily dyad {dyad}",
                           "deep reports and face reading {deep}"),
        }
        for dosya, beklenen in capalar.items():
            yol = _KOK / "apps" / "mobile" / "lib" / "l10n" / dosya
            satir = json.loads(yol.read_text(encoding="utf-8"))[
                "tokenCostsNote"]
            for capa in beklenen:
                assert capa in satir, (
                    f"{dosya}: tokenCostsNote '{capa}' demiyor — "
                    f"yer tutucu etiketinin yanından ayrıldı. Mağaza ekranı yanlış "
                    f"bedel gösteriyor, iki web sayfası da oraya işaret "
                    f"ediyor")

    def test_bedel_satirinin_ETIKET_SIRASI_dart_sabitiyle_ayni(self):
        """ARB'deki etiket SIRASI `_kBedelSirasi` ile aynı kalmak ZORUNDA.

        Yukarıdaki bekçi her etiketin yanındaki sayıyı çiviliyor ama SIRAYI
        çivilemiyordu; `token_store_screen.dart`'taki eşleştirme ise
        KONUMA bağlı (`_kBedelSirasi`, şablondaki sayıları sırayla
        tüketiyor). İki kaynak ayrışınca kimse görmez: çeviri yeniden
        sıralanırsa şablon hâlâ doğru etiket-sayı çiftlerini içerir (bu
        yüzden öteki bekçi yeşil kalır) ama Dart, sunucudan gelen `costs`
        değerlerini YANLIŞ SLOTLARA yazar ve ekranda "I Ching 1" görünür.

        Bu kusur bu turda GERÇEKTEN yaşandı — ters yönden: sabit
        `['chat', 'dyad', 'iching']` yazılıydı, dosyanın kendi yorumu
        doğru sırayı söylüyordu, ve ekranda İ Ching ile ikili dinamiğin
        bedelleri yer değişmiş görünüyordu. Bekçi o takası iki yönden de
        yakalasın diye buraya kondu.
        """
        etiketler = {
            "app_tr.arb": ("Sohbet mesajı", "I Ching", "ikili dinamik",
                           "derin raporlar ve yüz okuma"),
            "app_en.arb": ("Chat message", "I Ching", "daily dyad",
                           "deep reports and face reading"),
        }
        for dosya, sirali in etiketler.items():
            yol = _KOK / "apps" / "mobile" / "lib" / "l10n" / dosya
            satir = json.loads(yol.read_text(encoding="utf-8"))[
                "tokenCostsNote"]
            yerler = []
            for etiket in sirali:
                yer = satir.find(etiket)
                assert yer >= 0, f"{dosya}: '{etiket}' etiketi kayboldu"
                yerler.append(yer)
            assert yerler == sorted(yerler), (
                f"{dosya}: tokenCostsNote etiket sırası değişti ({sirali} "
                f"konumları {yerler}). `token_store_screen.dart`'taki "
                f"`_kBedelSirasi` KONUMA göre eşleştiriyor — sıra kayarsa "
                f"ekranda yanlış bedel görünür")

    def test_ucretsiz_katman_uyarisi_sohbet_bedelini_UYDURMUYOR(self):
        """"1 kredi = 1 sohbet mesajı" cümlesi koddaki bedele bağlı.

        Bedel gerçeğinin ÜÇÜNCÜ elle yazılmış kaynağı buydu ve aynı
        ekranda duruyor (`_PaketlerPlusaOzel` paneli). İlk ikisi bu turda
        koda bağlandı; bu cümle atlandı ve `TOKEN_COSTS['chat']` bir gün
        2 olursa ekran "1 kredi = 1 sohbet mesajı" demeye DEVAM eder.
        Cümle parametreli bir l10n dizesi olmadığı için burada
        ÇİVİLENİYOR: bedel değiştiği an bu test düşer ve dizeyi
        güncellemek (ya da parametreli hâle getirmek) zorunlu olur.
        """
        sohbet = self._token_bedelleri()["chat"]
        beklenen = {
            "app_tr.arb": f"{sohbet} kredi = {sohbet} sohbet mesajı",
            "app_en.arb": f"{sohbet} credit = {sohbet} chat message",
        }
        for dosya, capa in beklenen.items():
            yol = _KOK / "apps" / "mobile" / "lib" / "l10n" / dosya
            govde = json.loads(yol.read_text(encoding="utf-8"))[
                "tokenFreeTierWarnBody"]
            assert capa in govde, (
                f"{dosya}: tokenFreeTierWarnBody '{capa}' demiyor — "
                f"wallet.TOKEN_COSTS['chat']={sohbet} ile ayrıştı")

    def test_sitedeki_aylik_hak_koddaki_sayiyla_ayni(self):
        """K1: hak 300'den 100'e indi. Sayfadaki sayı kodu izlemek zorunda.

        Eski hâl iki sayfada da 300 yazıyordu; sayı tek bir yerde
        (`MONTHLY_TOKEN_ALLOWANCE`) tanımlı olduğu için ayrışma sessizdi.
        """
        # Sayi modul duzeyindeki TEK okuyucudan gelir (bkz. `_aylik_hak`):
        # ikinci bir okuyucu, gerekce metninin bayatlamasina giden yoldu.
        hak = _AYLIK_HAK

        # Sözlük kararı (D0): kullanıcıya görünen tek kelime kredi/credit.
        kaliplar = {"web/index.html": r"aylık (\d+) kredi",
                    "web/en/index.html": r"(\d+) credits every month"}
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
        beklenen = {"web/index.html": ("kredi paketi", "abone"),
                    "web/en/index.html": ("credit packs", "subscriber")}
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
class TestPinBeyanlari:
    """`conftest.py`'deki hermetiklik pinlerinin BEYANI ölçülür.

    NEDEN bu sınıf bu dosyada: bu dosyanın doktrini "ölçülmeyen söylenmez"
    ve onun öteki yarısı "beyan edilen ölçülür". `gemini_hermetik` pininin
    docstring'i **"Hiçbir test istemeden GERÇEK Gemini'ye gidemesin"**
    diyor; bu bir kapsam BEYANIDIR ve bir tur boyunca YANLIŞTI. Pinlerin
    kendi bekçileri bugün dağınık duruyor (`kapi_hermetik`in bekçisi
    `test_app_gate.py`'de), ama Gemini pininin hiç bekçisi yoktu.

    ⚠️ ÖLÇÜLDÜ (2026-10-03, doğrulama turu): Gemini'ye İKİ kapı var ve pin
    yalnız birini kapatıyordu.

    * Kapı 1 — `gemini_service._get_client()`: pinliydi.
    * Kapı 2 — `rag_service._KnowledgeBase._embed_texts()`: `gemini_service`
      hiç devreye girmiyor; işlev `from google import genai` ile İÇİNDE
      kendi `genai.Client(api_key=config.GEMINI_API_KEY)`ini kuruyor.
      Ölçüm: `genai.Client` bir kaydediciyle değiştirildiğinde kaydediciye
      ULAŞILDI ve geçen anahtar gerçek üretim anahtarıydı. Yani her soğuk
      sorgu üretim kotasından PARA harcıyordu.

    CLAUDE.md bu kapı çiftini adıyla yazıyor ("`gemini_service`
    `generate_content` VE `rag_service` `embed_content` — iki yüzey, biri
    atlanırsa teşhis eksik kalır") ve kota bu depoda GERÇEK PARA: pin,
    bir ajanın ~4 çağrı harcamasının bedeli ödenerek doğdu.

    Bekçi DAVRANIŞSAL, kaynak eşleştirme DEĞİL. Gerekçe: kaynakta
    `monkeypatch.setattr(config, "GEMINI_API_KEY", "")` satırını aramak
    yalnız BUGÜNKÜ yamayı çivilerdi — `rag_service` yarın anahtar ön
    koşulunu kaldırsa satır yerinde durur, pin körleşir ve metin bekçisi
    YEŞİL kalır. Burada ölçülen şey niyet değil ERİŞİM: dışa çıkan kapı
    gerçekten çalınıyor mu.
    """

    @staticmethod
    def _kapi_kaydedicisi(monkeypatch):
        """`genai.Client` yerine kaydedici koyar; ulaşılan her çağrıyı sayar.

        Para HARCANMIYOR: kaydediciye gelen çağrı ağa hiç çıkmıyor.
        Kaydediciye ULAŞILMASI, pin olmasaydı gerçek bir çağrı yapılacağı
        anlamına gelir — yani ölçüm "kapı açık mı" sorusunu harcamadan
        yanıtlıyor.
        """
        from google import genai

        ulasildi: list[str] = []

        def _kaydedici(*_a, **kw):
            ulasildi.append(str(kw.get("api_key", ""))[:4])
            raise AssertionError("pin yok: bu çağrı ağa çıkacaktı")

        monkeypatch.setattr(genai, "Client", _kaydedici)
        return ulasildi

    def test_gemini_pini_RAG_embedding_kapisini_da_kapatir(self, monkeypatch):
        """Kapı 2: `rag_service` kendi istemcisini KURAMAZ."""
        from services import rag_service

        ulasildi = self._kapi_kaydedicisi(monkeypatch)
        rag_service._KnowledgeBase("tr")._embed_texts(["ölçüm metni"])
        assert not ulasildi, (
            "conftest `gemini_hermetik` pini RAG embedding kapısını "
            "KAPATMIYOR: `rag_service._embed_texts` kendi "
            f"`genai.Client`ini kurdu (anahtar öneki {ulasildi!r}). "
            "Bu kapı pinsizken her soğuk sorgu üretim kotasından para "
            "harcar — CLAUDE.md'nin iki-yüzey kuralı.")

    def test_gemini_pini_URETIM_istemcisi_kapisini_da_kapatir(self,
                                                              monkeypatch):
        """Kapı 1: `gemini_service` istemci kurmaz ve `None` döner.

        İki şey birden sorulur. Yalnız `_get_client() is None` demek
        yetmezdi: pin lambda'yı söküp anahtarı bıraksa istemci GERÇEKTEN
        kurulabilirdi; yalnız kaydediciye bakmak da yetmezdi, çünkü
        `_get_client` modül düzeyinde `_client`ı ÖNBELLEKLİYOR ve önceki
        bir testin kurduğu istemci yeni bir `genai.Client` çağrısı
        YAPMADAN dönebilirdi.
        """
        from services import gemini_service

        ulasildi = self._kapi_kaydedicisi(monkeypatch)
        assert gemini_service._get_client() is None, (
            "conftest `gemini_hermetik` pini `gemini_service` kapısını "
            "kapatmıyor: istemci kuruldu")
        assert not ulasildi, (
            f"`genai.Client` kuruldu (anahtar öneki {ulasildi!r}) — "
            "pin yalnız dönüş değerini değil ÇAĞRIYI da engellemeli")

    def test_pin_olcumunun_DISI_var(self, monkeypatch):
        """Yukarıdaki iki ölçüm gerçekten ısırıyor mu — MİNİMAL mutasyon.

        NEDEN gerekli: ölçüm "kaydediciye ulaşılmadı" diyor ve bu YOKLUK
        iddiası iki ayrı sebeple de doğru çıkabilir — kapı kapalı olduğu
        için, ya da ölçüm hiç o kapıya DOKUNMADIĞI için. İkincisi tam
        olarak kör bekçidir: bu depoda üç paket "mutasyonların hepsi
        kırmızı" dedi, minimal mutasyonla sınandığında 8, 11 ve 2 kör
        bekçi çıktı.

        Mutasyon TEK TERİM ve pinin kendi terimi: anahtar geri konuyor
        (`monkeypatch.setattr` ile, yani bu testin dışına taşmaz). Pinin
        öteki ayağı (`_get_client` lambda'sı) BİLEREK yerinde bırakılıyor
        — ölçülen şey yalnız ANAHTAR ayağının yük taşıyıp taşımadığı.
        """
        from core import config
        from services import rag_service

        # Pin bugün anahtarı boşaltıyor; ön koşul bu.
        assert not config.GEMINI_API_KEY, (
            "ön koşul tutmuyor: pin anahtarı boşaltmıyor, yani aşağıdaki "
            "mutasyonun geri koyacağı bir terim yok")

        monkeypatch.setattr(config, "GEMINI_API_KEY", "AIza-olcum-anahtari")
        ulasildi = self._kapi_kaydedicisi(monkeypatch)
        rag_service._KnowledgeBase("tr")._embed_texts(["ölçüm metni"])
        assert ulasildi, (
            "ÖLÇÜM KÖR: anahtar geri konduğunda bile RAG kapısına "
            "ulaşılmıyor. Yani üstteki bekçi pinin değil başka bir şeyin "
            "sonucunu ölçüyor ve anahtar ayağı sökülse yeşil kalırdı "
            "(`rag_service` kendi istemcisini kurmayı bıraktıysa çapa "
            "yeniden nişanlanmalı).")

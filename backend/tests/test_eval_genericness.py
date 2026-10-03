"""Jeneriklik ÖLÇERİNİN kendi bekçisi.

`scripts/eval_genericness.py` bir BETİK, test değil: koşması LLM çağrısı
gerektiriyor, yani CI'da hiç koşmuyor ve bugüne kadar **bekçisiz**ti.
Oysa ölçüm aracının kendisi yanlış ölçerse hüküm de yanlış olur — bu
depoda bir kez tam olarak bu oldu (bkz. `_ad_gecti` ve `_ev_gecti`).

Buradaki testler aracın MANTIĞINI sahte girdilerle ölçer: kapsam tablosu,
kalıp tespiti, Türkçe eşleştirme disiplini, olgu çıkarıcılar, hafıza
çapaları ve skorlama. **Hiçbiri LLM'e gitmez** ve gitmeye çalışan bir
test `_llm_hermetik` pini yüzünden açık bir hatayla düşer.

Kapsam testleri KAYNAĞI TARAYARAK ölçer (`ast`), elle yazılmış listeyle
değil: yeni bir LLM yüzeyi eklenip ölçere kaydedilmezse test kırmızı olur.
`ast` kullanılması ayrıca CLAUDE.md'nin "bir şeyin YOKLUĞUNU arayan bekçi
onu ANLATAN yorumu görmemeli" kuralını yapısal olarak karşılar: yorumlar
ve docstring'ler ağaçta çağrı DÜĞÜMÜ değil, o yüzden bekçi kendi
açıklamasına takılamaz.
"""
from __future__ import annotations

import ast
import dataclasses
import importlib.util
import io
import sys
from pathlib import Path

import pytest

_BACKEND = Path(__file__).resolve().parent.parent
_BETIK = _BACKEND / "scripts" / "eval_genericness.py"

#: Betik `scripts/` altında ve paket değil; dosya yolundan yüklenir.
#:
#: `sys.modules`a kayıt **gövde koşmadan ÖNCE** yapılır ve bu zorunlu:
#: betik `@dataclasses.dataclass` kullanıyor, `dataclasses` ise tip
#: çözümlemesi için `sys.modules[cls.__module__]`a bakıyor. Kayıt sonraya
#: bırakılırsa toplama anında `AttributeError: 'NoneType' object has no
#: attribute '__dict__'` ile düşer — ölçüldü.
_spec = importlib.util.spec_from_file_location("eval_genericness", _BETIK)
assert _spec and _spec.loader
ev = importlib.util.module_from_spec(_spec)
sys.modules["eval_genericness"] = ev
_spec.loader.exec_module(ev)

from services import gemini_service, prompt_composer, prompts  # noqa: E402

N = prompt_composer.normalize


@pytest.fixture(autouse=True)
def _llm_hermetik(monkeypatch):
    """Bu dosyadaki HİÇBİR test LLM'e gitmesin.

    ⚠️ GEREKÇE YENİLENDİ (doğrulama turunda ölçüldü). Bu pin yazıldığında
    gerekçesi "`conftest.py` Gemini'yi hiç pinlemiyor" idi ve o gerekçe
    AYNI TUR İÇİNDE bayatladı: `conftest.py` artık `gemini_hermetik`
    adında beşinci bir autouse pin taşıyor. Yani buradaki pinin sebebi
    "orada pin yok" DEĞİL.

    Gerçek sebep ikisinin KİPİ farklı: `conftest` pini
    `gemini_service._get_client`i `None`a çekiyor, yani üretim kodu
    anahtarsız kurulum dalına düşüyor ve çağrı SESSİZCE yedeğe gidiyor —
    para harcanmaz ama test de yeşil kalır. Bir ÖLÇÜM dosyasında bu en
    kötü sonuç: araç yedek metni gerçek model çıktısı sanıp ona jeneriklik
    hükmü verir, üstelik hüküm yeşil görünür. Buradaki pin bu yüzden
    GÜRÜLTÜLÜ: sahte girdi kullanmayı unutan test açık bir hatayla düşer.

    `GEMINI_API_KEY` ortamda var (yerelde `backend/.env` üzerinden), yani
    pinlerden biri düşerse bedeli üretim kotasıdır — CLAUDE.md'nin "dış
    dünyaya çıkan her istemci için ayrı pin" kuralının bedeli bu turda
    bir kez ödendi.
    """
    def _yasak(*a, **kw):
        raise AssertionError(
            "Jeneriklik ölçer testi LLM'e gitmeye çalıştı; sahte girdi "
            "kullanılmalı (bkz. modül docstring'i).")

    for ad in ("generate", "chat", "extract_json"):
        if hasattr(gemini_service, ad):
            monkeypatch.setattr(gemini_service, ad, _yasak)


class TestLlmPini:
    """Pinin KENDISI sinanir.

    Mutasyon sinavinda olculdu: `_llm_hermetik` pini tamamen kaldirildiginda
    106 testin HICBIRI kirilmiyordu. Bu iyi haber (hicbir test LLM'e
    muhtac degil) ama pinin CALISTIGINI kanitlamiyordu — kaza ile guvenli
    olan sey guvence degildir. Bu test pini canli tutar: pin dusurulurse
    burasi kirmizi olur.
    """

    def test_gemini_cagrisi_acik_hatayla_duser(self):
        with pytest.raises(AssertionError, match="LLM"):
            gemini_service.generate("herhangi bir prompt")

    def test_sohbet_cagrisi_da_pinli(self):
        with pytest.raises(AssertionError, match="LLM"):
            gemini_service.chat([], "merhaba")


# ---------------------------------------------------------------------------
# KAPSAM — aracın neyi ölçtüğü artık veri, iddia değil
# ---------------------------------------------------------------------------

#: LLM metni üreten fonksiyonların aranacağı servis modülleri. `api/chat.py`
#: listede YOK çünkü sohbet ucu fonksiyon değil uç noktadır; o yüzey
#: aşağıda adıyla sınanıyor.
_TARANAN_MODULLER = ("report_service", "signal_service",
                     "notification_service")


def _kaynaktan_llm_yuzeyleri() -> set[str]:
    """Kaynağı tarayıp LLM metni üreten AÇIK fonksiyonları bulur.

    Ölçüt: gövdesinde `gemini_service.<x>` ya da `_cached_generate`
    geçen, alt çizgiyle başlamayan modül düzeyi fonksiyon. `ast` ile
    yapılıyor; dize ve yorum içindeki aynı kelimeler düğüm olmadığı için
    tarama kendi belgesine takılamaz.
    """
    bulunan: set[str] = set()
    for modul in _TARANAN_MODULLER:
        kaynak = io.open(_BACKEND / "services" / f"{modul}.py",
                         encoding="utf-8").read()
        for dugum in ast.parse(kaynak).body:
            if not isinstance(dugum, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            if dugum.name.startswith("_"):
                continue
            for n in ast.walk(dugum):
                if (isinstance(n, ast.Attribute)
                        and isinstance(n.value, ast.Name)
                        and n.value.id == "gemini_service"):
                    bulunan.add(f"{modul}.{dugum.name}")
                    break
                if isinstance(n, ast.Name) and n.id == "_cached_generate":
                    bulunan.add(f"{modul}.{dugum.name}")
                    break
    return bulunan


class TestKapsam:
    def test_kaynaktaki_her_llm_yuzeyi_tabloda_kayitli(self):
        """Yeni bir LLM yüzeyi kaydedilmeden eklenemesin.

        Ölçerin kör noktası tam olarak buydu: `report_service`'e yüzey
        eklendi, ölçere hiç dokunulmadı ve kapsamın daraldığını kimse
        görmedi. Artık kaynak tarama ile tablo kıyaslanıyor.
        """
        tablo = ev._yuzeyler()
        kayitli = {y.kaynak for y in tablo.values()}
        eksik = _kaynaktan_llm_yuzeyleri() - kayitli
        assert not eksik, (
            "Bu yüzeyler LLM metni üretiyor ama ölçerin `_yuzeyler()` "
            f"tablosunda yok: {sorted(eksik)}")

    def test_tabloda_var_olmayan_yuzey_yok(self):
        """Tablo bayatlamasın: silinmiş bir yüzey kayıtlı kalmasın."""
        tablo = ev._yuzeyler()
        gercek = _kaynaktan_llm_yuzeyleri() | {"api/chat.py"}
        hayalet = {y.kaynak for y in tablo.values()} - gercek
        assert not hayalet, f"Kaynakta olmayan yüzey kayıtlı: {hayalet}"

    def test_sohbet_yuzeyi_kayitli(self):
        tablo = ev._yuzeyler()
        assert tablo["chat"].kaynak == "api/chat.py"
        assert tablo["chat"].kapsam == "olculuyor"

    @pytest.mark.parametrize("ad", ["bazi", "firasa", "birth-gate"])
    def test_sahibin_sordugu_uc_yuzey_gercekten_olculuyor(self, ad):
        """Bu üç yüzey ölçümün dışındaydı ve sahibin elle sorduğu yüzeylerdi.

        "Kapsam genişledi" iddiasının somut ayağı: yüzey kayıtlı olmakla
        kalmaz, üreticisi ve olgu çıkarıcısı da BAĞLI olmalı — yoksa
        tabloya adını yazmak ölçmek sayılırdı.
        """
        y = ev._yuzeyler()[ad]
        assert y.kapsam == "olculuyor"
        assert y.girdiler is not None, f"{ad}: girdi üreticisi yok"
        assert y.uret is not None, f"{ad}: metin üreticisi yok"
        assert y.olgular is not None, f"{ad}: olgu çıkarıcısı yok"

    def test_her_kapsam_disi_yuzey_gerekce_tasiyor(self):
        """Kapsam dışı olmak serbest, SESSİZ kapsam dışı olmak değil."""
        for y in ev._yuzeyler().values():
            if y.kapsam != "olculuyor":
                assert len(y.neden_kapsam_disi) > 40, (
                    f"{y.ad}: kapsam dışı ama gerekçesi yok/yetersiz")

    def test_her_yuzeyin_kendi_olcusu_var_ve_benzersiz(self):
        """Sohbetin ölçüsü burç yorumuna uymaz.

        İki yüzeyin `olcu` metni birebir aynıysa biri ötekinden
        kopyalanmış demektir — ölçüleni yanlış adla sunmanın en sinsi
        hâli, çünkü sayı doğru görünür.
        """
        olculen = [y for y in ev._yuzeyler().values()
                   if y.kapsam == "olculuyor"]
        for y in olculen:
            assert len(y.eksen) > 5, f"{y.ad}: eksen tanımsız"
            assert len(y.olcu) > 20, f"{y.ad}: ölçü tanımsız"
        olculer = [y.olcu for y in olculen]
        assert len(set(olculer)) == len(olculer), (
            "iki yüzey aynı ölçüyü paylaşıyor")

    def test_kapsam_modu_llm_anahtari_olmadan_kosuyor(self, monkeypatch):
        """Kapsam tablosu LLM'e dokunmuyor; anahtar kapısı önünde durmamalı.

        `--mode kapsam` anahtarsız makinede de cevap vermeli, yoksa
        "bu araç neyi ölçüyor" sorusu cevapsız kalır.
        """
        monkeypatch.setattr(ev.config, "GEMINI_API_KEY", "")
        monkeypatch.setattr("sys.argv", ["eval", "--mode", "kapsam"])
        assert ev.main() == 0


class TestHafizaliYuzeySayisi:
    def test_hafizali_bayrak_kaynakla_uyusuyor(self):
        """"Hafıza üç yüzeye ulaşıyor" iddiası kaynaktan doğrulanır.

        Bu bir sayı değil bir İDDİA: hafızayı dikkate ALMAYAN bir yüzey
        için "hafızanı hesaba katıyor" demek, ölçülmeyeni söylemektir.
        Çağrı yerleri `memory_context` üzerinden sayılır.
        """
        sayi = 0
        for dosya in (_BACKEND / "services" / "report_service.py",
                      _BACKEND / "api" / "chat.py"):
            kaynak = io.open(dosya, encoding="utf-8").read()
            for n in ast.walk(ast.parse(kaynak)):
                if (isinstance(n, ast.Call)
                        and isinstance(n.func, ast.Attribute)
                        and n.func.attr == "memory_context"):
                    sayi += 1
        assert sayi == ev.HAFIZALI_YUZEY_SAYISI, (
            f"kaynakta {sayi} `memory_context` çağrısı var ama ölçer "
            f"{ev.HAFIZALI_YUZEY_SAYISI} diyor")

    def test_bayrakli_yuzey_sayisi_sabitle_uyusuyor(self):
        hafizali = [y.ad for y in ev._yuzeyler().values() if y.hafizali]
        assert len(hafizali) == ev.HAFIZALI_YUZEY_SAYISI
        assert set(hafizali) == {"chat", "daily", "iching"}

    def test_hafiza_modu_hafizasiz_yuzeyi_reddediyor(self):
        """Hafıza promptuna girmeyen yüzeyde bu ölçümün hükmü yok.

        Koşup bir sayı basmak, ölçülmeyeni ölçülmüş gibi sunmak olurdu.
        """
        y = ev._yuzeyler()["bazi"]
        assert not y.hafizali
        assert ev._hafiza_modu(y) == 1


# ---------------------------------------------------------------------------
# YAĞCILIK — dedektörün kendi kuyruğunu ısırması
# ---------------------------------------------------------------------------


class TestYagcilikSinifi:
    #: Hepsi AYNI sınıfın üyesi ve hiçbiri sabit ifade listesine eşit değil.
    #: Çapa tek bir Türkçe yazıma bağlanmıyor: büyük/küçük harf, araya
    #: giren bağlaç, iyelik eki ve farklı baş/kuyruk çiftleri ayrı ayrı
    #: sorulur — biri geçse öteki yakalamalı.
    @pytest.mark.parametrize("metin, beklenen", [
        ("Bu senin için bir dikkat ve büyüme alanı.", "büyüme alanı"),
        ("Bölümler: (3) Dikkat ve Büyüme Alanı.", "büyüme alanı"),
        ("Güçlü yönün ve büyüme alanın birlikte okunur.", "büyüme alanın"),
        ("Burada bir gelişim ve dikkat alanı var.", "gelişim ve dikkat alanı"),
        ("Bu bir büyüme fırsatı.", "büyüme fırsatı"),
        ("Onu bir gelişim alanı olarak gör.", "gelişim alanı"),
        ("Bu bir öğrenme yolculuğu.", "öğrenme yolculuğu"),
        ("Sana bir farkındalık daveti.", "farkındalık daveti"),
    ])
    def test_sinif_uyeleri_yakalaniyor(self, metin, beklenen):
        bulgular = ev._yagcilik_bulgulari(metin)
        assert beklenen in bulgular, f"{metin!r} -> {bulgular}"

    def test_urunun_kendi_bolum_basligi_yakalaniyor(self):
        """Kaçırılan şey kenar durum değildi: ürünün KENDİ prompt'u bunu
        yazdırıyordu (44da74b'de `services/prompts/tr.py` sinastri bölüm
        listesi), yani üretilmesi en olası örnekti ve sayaç yine 0
        dönüyordu.

        Prompt tarafı aynı turda o başlığı kaldırdı; bu test yine de
        GEÇERLİ ve bilerek prompt'a BAĞLANMIYOR (dizge burada literal).
        Sebep: dedektörün işi prompt'un bugün ne emrettiği değil, modelin
        ne üretebileceğidir — bu register prompt'tan bağımsız olarak
        modelin varsayılan dilidir ve prompt'u düzeltmek onu
        yasaklamıyor, yalnız emretmeyi bırakıyor.
        """
        baslik = ("Bölümler: (1) Genel rezonans, (2) Güçlü bağ noktaları, "
                  "(3) Dikkat ve büyüme alanı.")
        assert ev._yagcilik_bulgulari(baslik)

    def test_ayni_ifade_iki_kez_sayilmiyor(self):
        """Sabit liste ile sınıf ÇAKIŞMAMALI.

        "büyüme fırsatı" bir zamanlar sabit listede de vardı; sınıf
        eklenince aynı ifade iki bulgu üretirdi ve rapor tek kusuru iki
        kusur gibi gösterirdi.
        """
        assert len(ev._yagcilik_bulgulari("Bu bir büyüme fırsatı.")) == 1

    @pytest.mark.parametrize("metin", [
        "Satürn kare Güneş; bu dönem sorumluluk ister.",
        "Bu alan senin mesleki alanın; Merkür burada güçlü.",
        "Büyüme çağındaki bir çocuk gibi aceleci davranıyorsun.",
        "Fırsat penceresi mart ayında kapanıyor.",
    ])
    def test_notr_metin_yanlis_pozitif_uretmiyor(self, metin):
        assert ev._yagcilik_bulgulari(metin) == []

    def test_sinif_paragraf_boyu_atlamiyor(self):
        """Baş ile kuyruk arası en çok iki kelime.

        Sınırsız bırakılsa "büyüme" ile paragrafın sonundaki "alanı"
        eşleşir ve ölçüm yanlış pozitife boğulurdu — tam olarak düz alt
        dizi aramasının hatası.
        """
        uzak = ("Büyüme konusunu bir kenara bırakıp önce mesleki "
                "tercihlerini konuşmamız gereken alanı işaret ediyor.")
        assert ev._yagcilik_bulgulari(uzak) == []

    def test_sabit_ifadeler_hala_calisiyor(self):
        assert "muhteşem" in ev._yagcilik_bulgulari("Bu muhteşem bir dönem.")
        assert "endişelenme" in ev._yagcilik_bulgulari("Hiç endişelenme.")


class TestYasakAlan:
    def test_yasak_kalip_kelime_siniriyla_araniyor(self):
        assert ev._kalip_sayisi("Borsada yatırım yapma.", ev.YASAK,
                                regex=True)

    def test_hissettiren_kelimesi_sahte_sizinti_uretmiyor(self):
        """Ölçülmüş bir gerileme: düz alt dizi araması "hissedebileceğini"
        ve "hissettiren" içinde "hisse" bulup 6 sahte sızıntı sayıyordu.
        """
        metin = ("Bunu hissedebileceğini düşünüyorum; seni hissettiren "
                 "şey Ay'ın konumu.")
        assert ev._kalip_sayisi(metin, ev.YASAK, regex=True) == []


# ---------------------------------------------------------------------------
# TÜRKÇE EŞLEŞTİRME DİSİPLİNİ
# ---------------------------------------------------------------------------


class TestAdEslestirme:
    @pytest.mark.parametrize("metin", [
        "Ayrıca bunu düşünmelisin.",
        "Aynı yere geliyorsun.",
        "Bu bir olay değil.",
        "Sayıca fazla.",
        "Ayakkabılarını giy.",
    ])
    def test_ay_gunluk_kelimelere_takilmiyor(self, metin):
        """Aracın en pahalı kusuru buydu: "ay" (Ay) Türkçe yazılmış hemen
        her cevapta alt dizi olarak eşleşiyordu. Ay her haritada var, yani
        hata hem olgu sayısını hem haritalar arası örtüşmeyi şişiriyordu.
        """
        assert not ev._ad_gecti(N(metin), "ay")

    @pytest.mark.parametrize("metin", [
        "Ay burcunda gerilim var.",
        "Ay'ın konumu belirleyici.",
        "Bu dönemde Ay öne çıkıyor.",
    ])
    def test_ay_gercekten_anildiginda_yakalaniyor(self, metin):
        assert ev._ad_gecti(N(metin), "ay")

    @pytest.mark.parametrize("ad, metin", [
        ("boğa", "Boğazım ağrıyor."),
        ("kova", "Kovalıyor beni."),
        ("yay", "Yayılıyor her yere."),
        ("mars", "Marsilya'ya gitti."),
        ("koç", "Koçluk yapıyor."),
    ])
    def test_kisa_adlar_onek_oldugu_kelimelere_takilmiyor(self, ad, metin):
        assert not ev._ad_gecti(N(metin), ad)

    @pytest.mark.parametrize("ad, metin", [
        ("boğa", "Venüs Boğa burcunda."),
        ("boğa", "Venüs Boğa'da duruyor."),
        ("kova", "Satürn Kova burcunda."),
        ("yay", "Jüpiter Yay burcunda."),
        ("mars", "Mars'ın etkisi sürüyor."),
    ])
    def test_kisa_adlar_gercek_anilmada_yakalaniyor(self, ad, metin):
        assert ev._ad_gecti(N(metin), ad)

    @pytest.mark.parametrize("ad, metin", [
        ("güneş", "Güneşin konumu önemli."),
        ("merkür", "Merkür'ün geri hareketi."),
        ("aslan", "Aslanda duran bir yerleşim."),
        ("başak", "Başak burcunun titizliği."),
        ("terazi", "Terazideki denge."),
    ])
    def test_uzun_adlar_ek_almis_bicimi_yakaliyor(self, ad, metin):
        """Türkçe sondan eklemeli: tam kelime eşleşmesi çekimli biçimi
        kaçırır ve bu da ölçümü aşağı çeker. 5+ harfli adlarda kelime BAŞI
        eşleşmesi güvenli (ölçüldü: çakışan günlük kelime bulunamadı).
        """
        assert ev._ad_gecti(N(metin), ad)

    def test_noktali_i_ile_baslayan_metin_normalize_ediliyor(self):
        """`str.lower()` Türkçe bilmez; normalize edilmemiş metinde büyük
        harfle başlayan kelimeler hiç eşleşmezdi.
        """
        assert ev._ad_gecti(N("İkizler burcunda Merkür var."), "ikizler")


class TestEvEslestirme:
    @pytest.mark.parametrize("metin, ev_no", [
        ("Güneş 12. evde.", 2),
        ("Ay 11. evde.", 1),
        ("Mars 10. evde.", 0),
    ])
    def test_komsu_sayiya_kacmiyor(self, metin, ev_no):
        """"12. evde" dizesi "2. ev" alt dizisini İÇERİYOR: düz arama 12.
        evdeki bir yerleşimi 2. ev olarak da sayıyordu.
        """
        assert not ev._ev_gecti(N(metin), ev_no)

    @pytest.mark.parametrize("metin, ev_no", [
        ("Güneş 12. evde.", 12),
        ("Merkür 1. evde duruyor.", 1),
        ("Venüs 7.ev vurgusu.", 7),
    ])
    def test_dogru_ev_yakalaniyor(self, metin, ev_no):
        assert ev._ev_gecti(N(metin), ev_no)


# ---------------------------------------------------------------------------
# OLGU ÇIKARICILAR — her yüzeyin kendi tanımı
# ---------------------------------------------------------------------------


class TestAstroOlgular:
    FACTS = {
        "sun": {"planet": "Sun", "sign": "leo", "house": 12},
        "moon": {"planet": "Moon", "sign": "taurus", "house": 9},
        "placements": [{"planet": "Mercury", "sign": "virgo", "house": 1}],
        "aspects": [{"p1": "Mars", "p2": "Uranus", "aspect": "square"}],
    }

    def test_yalniz_gezegen_anilinca_yerlesim_sayilmiyor(self):
        """İki işaret kuralı: gezegen VE burç birlikte anılmalı."""
        assert "Sun-leo" not in ev._astro_olgular("Güneş öne çıkıyor.",
                                                  self.FACTS)

    def test_gezegen_ve_burc_birlikte_anilinca_sayiliyor(self):
        olgu = ev._astro_olgular("Güneş Aslan burcunda.", self.FACTS)
        assert "Sun-leo" in olgu

    def test_yanlis_burc_sayilmiyor(self):
        olgu = ev._astro_olgular("Güneş Başak burcunda.", self.FACTS)
        assert "Sun-leo" not in olgu

    def test_aci_adi_gecerse_tam_etiket(self):
        olgu = ev._astro_olgular("Mars kare Uranüs okunuyor.", self.FACTS)
        assert "Mars-square-Uranus" in olgu

    def test_aci_adi_gecmezse_cift_etiketi(self):
        """Ölçülen "iki gezegen birlikte anıldı"; sunulan "açıyı adıyla
        andı" olamaz. Eskiden iki gezegenin ayrı cümlelerde geçmesi
        `Mars-square-Uranus` etiketini doğuruyordu.
        """
        olgu = ev._astro_olgular("Mars hareketli. Uranüs de etkili.",
                                 self.FACTS)
        assert "Mars+Uranus" in olgu
        assert "Mars-square-Uranus" not in olgu

    def test_ay_sahte_eslesmesi_olgu_uretmiyor(self):
        """Bütünleşik gerileme: "ayrıca ... boğazım" metni eskiden
        Ay-Boğa yerleşimini "anılmış" sayıyordu (iki alt dizi birden).
        """
        metin = "Ayrıca boğazım ağrıyor, aynı şey yine oldu."
        assert "Moon-taurus" not in ev._astro_olgular(metin, self.FACTS)


class TestNatalOlgular:
    def test_burc_kodu_tam_anahtara_cevriliyor(self):
        """Ham harita noktaları burç KODU taşıyor ("Tau"), `sign_name` ise
        yalnız tam anahtarı biliyor. Köprü atlanırsa çıkarıcı patlamaz,
        SESSİZCE her zaman 0 olgu bulur ve araç "rapor jenerik" diye
        yanlış hüküm verir.
        """
        natal = {"points": [{"name": "Venus", "sign": "Tau",
                             "house_no": 3}], "aspects": []}
        olgu = ev._natal_olgular("Venüs Boğa burcunda, 3. evde.", natal)
        assert "Venus-taurus" in olgu
        assert "Venus-ev3" in olgu

    def test_ev_adi_metninden_de_okunuyor(self):
        """kerykeion evi "Twelfth_House" diye veriyor, `house_no` her
        zaman dolu değil."""
        natal = {"points": [{"name": "Sun", "sign": "Leo",
                             "house": "Twelfth_House"}], "aspects": []}
        assert "Sun-ev12" in ev._natal_olgular("Güneş 12. evde Aslan.",
                                               natal)


class TestBaziOlgular:
    CHART = {
        "day_master": {"pinyin": "Xin", "cn": "辛", "element": "metal",
                       "polarity": "Yin"},
        "pillars": {"year": {
            "stem": {"index": 6, "pinyin": "Geng", "cn": "庚",
                     "element": "metal", "polarity": "Yang"},
            "branch": {"index": 6, "pinyin": "Wu", "cn": "午",
                       "animal": "horse", "element": "fire"}}},
        "dominant_element": "metal",
        "strength": {"verdict": "strong"},
        "zodiac_animal": "horse",
        "element_distribution": {"metal": 3.6},
    }

    def test_hayvan_adi_tek_basina_olgu_uretmiyor(self):
        """"At" iki harfli ve "atmak" fiilinin emir kipi. Tek işarete
        bağlanan çapa kör olur; bu yüzden sütunun gövdesi de istenir.
        """
        olgu = ev._bazi_olgular("Bunu bir kenara at, acele etme.",
                                self.CHART)
        assert not any(o.startswith("year-hayvan") for o in olgu)

    def test_govde_ve_dal_birlikte_anilinca_sutun_sayiliyor(self):
        olgu = ev._bazi_olgular("Yıl sütunu Geng Wu olarak okunuyor.",
                                self.CHART)
        assert "year-GengWu" in olgu

    def test_gunun_efendisi_pinyin_ve_elementle_sayiliyor(self):
        olgu = ev._bazi_olgular("Günün Efendisi Yin Metal, yani Xin.",
                                self.CHART)
        assert "dm-Xin-metal" in olgu

    def test_element_adi_tek_basina_yetmiyor(self):
        """"Metal" tek başına geçtiğinde "baskın element + güç hükmü"
        okunmuş sayılmaz; hüküm adı da istenir.
        """
        olgu = ev._bazi_olgular("Metal bir tını var bu haritada.",
                                self.CHART)
        assert not any(o.startswith("baskin-") for o in olgu)

    def test_baskin_element_ve_hukum_birlikte(self):
        olgu = ev._bazi_olgular("Baskın element Metal ve hüküm güçlü.",
                                self.CHART)
        assert "baskin-Metal-strong" in olgu

    def test_alakasiz_metin_sifir_olgu(self):
        assert ev._bazi_olgular("Bugün kendine iyi bak.", self.CHART) == set()


class TestHeksagramOlgular:
    VERI = {"primary": {"number": 24, "name": "Fu", "name_tr": "Dönüş"},
            "transformed": None, "moving_lines": [2, 6]}
    KAPI = {"gate": 4, "line": 3,
            "hexagram": {"number": 4, "name": "Meng",
                         "name_tr": "Gençlik Toyluğu"}}

    def test_numara_tek_basina_yetmiyor(self):
        """"24" her metinde geçebilir (tarih, yaş, derece)."""
        olgu = ev._heksagram_olgular("24 Eylül'de bir dönüm var.", self.VERI)
        assert "heks-24" not in olgu

    def test_numara_ve_ad_birlikte_sayiliyor(self):
        olgu = ev._heksagram_olgular("24. heksagram, Dönüş.", self.VERI)
        assert "heks-24" in olgu

    def test_hareketli_cizgi_sayiliyor(self):
        olgu = ev._heksagram_olgular("2. çizgi hareketli.", self.VERI)
        assert "hareketli-2" in olgu

    def test_dogum_kapisi_numara_ve_kelimeyle(self):
        olgu = ev._heksagram_olgular("4. kapı, 3. çizgi; Meng heksagramı.",
                                     self.KAPI)
        assert {"kapi-4", "cizgi-3", "heks-4"} <= olgu


class TestFirasaOlgular:
    RATIOS = {"upperThird": 0.26, "middleThird": 0.37, "lowerThird": 0.37,
              "lipFullness": 0.065, "eyeSpacing": 0.40}

    def test_olculen_belirti_anilinca_sayiliyor(self):
        """Firasette harita değil ÖLÇÜM var: jenerik okuma her yüze aynı
        şeyi söyleyendir.
        """
        olgu = ev._firasa_olgular("Dudaklar dolgun, gözler birbirine yakın.",
                                  self.RATIOS)
        assert "lips_full" in olgu
        assert "eyes_close" in olgu

    def test_tek_capa_yetmiyor(self):
        olgu = ev._firasa_olgular("Dudaklarına dikkat et.", self.RATIOS)
        assert "lips_full" not in olgu

    def test_olculmeyen_belirti_uydurulmuyor(self):
        """Ölçümde olmayan bir belirti metinde geçse de olgu sayılmaz —
        olgu kümesi ÖLÇÜMDEN türetiliyor, metinden değil.
        """
        olgu = ev._firasa_olgular("Çene kare ve geniş.", self.RATIOS)
        assert "jaw_square" not in olgu

    def test_alakasiz_metin_sifir_olgu(self):
        assert ev._firasa_olgular("Haftaya güzel bir haber var.",
                                  self.RATIOS) == set()


class TestSinastriOlgular:
    SYN = {"aspects": [{"p1": "Mars", "p2": "Uranus", "aspect": "square"},
                       {"p1": "Venus", "p2": "Saturn", "aspect": "trine"}]}

    def test_cifte_ozel_aci_sayiliyor(self):
        olgu = ev._sinastri_olgular("Venüs üçgen Satürn bağı güçlü.",
                                    self.SYN)
        assert "Venus-trine-Saturn" in olgu

    def test_yerlesim_sayilmiyor(self):
        """Sinastride ayırt edici hesap yerleşim değil AÇI; yerleşimleri
        de saymak örtüşmeyi sahte yükseltirdi.
        """
        olgu = ev._sinastri_olgular("Venüs Boğa burcunda.", self.SYN)
        assert not any("taurus" in o for o in olgu)


class TestProgresyonOlgular:
    PROG = ({"prog_sun": {"sign": "Gem"}, "prog_moon": {"sign": "Ari",
             "natal_house": 8}},
            [{"directed": "Venus", "natal": "Neptune", "aspect": "trine"}])

    def test_progres_yerlesimi_sayiliyor(self):
        """Progresyon çıktısı natal biçimde DEĞİL: gezegen adı anahtarın
        kendisinde, `points` listesi yok.
        """
        olgu = ev._progresyon_olgular("Progres Güneş İkizler burcunda.",
                                      self.PROG)
        assert "Sun-gemini" in olgu

    def test_solar_arc_degmesi_sayiliyor(self):
        olgu = ev._progresyon_olgular("Venüs üçgen Neptün değmesi yakın.",
                                      self.PROG)
        assert "Venus-trine-Neptune" in olgu


# ---------------------------------------------------------------------------
# HAFIZA — P2'nin dış doğrulaması
# ---------------------------------------------------------------------------


class TestHafiza:
    def test_iki_hafiza_var_ve_capalari_kesismiyor(self):
        """Çapalar kesişirse "sızıntı" ölçümü kendi kendine yanlış pozitif
        üretir: A'nın cevabında B'nin çapası görünür ve ölçüm bunu
        zehirlenme sanar.
        """
        assert len(ev.HAFIZALAR) >= 2
        kokler = [set(k for c in h.capalar for k in c) for h in ev.HAFIZALAR]
        for i in range(len(kokler)):
            for j in range(i + 1, len(kokler)):
                assert not kokler[i] & kokler[j], (
                    f"{ev.HAFIZALAR[i].ad} ve {ev.HAFIZALAR[j].ad} "
                    f"çapaları kesişiyor: {kokler[i] & kokler[j]}")

    def test_her_capa_en_az_iki_kokten_olusuyor(self):
        """Tek köke bağlanan çapa kör olur — bu turda tam olarak bu oldu."""
        for h in ev.HAFIZALAR:
            for c in h.capalar:
                assert len(c) >= 2, f"{h.ad}: tek köklü çapa {c}"

    #: `memory_context`in kendi imza varsayilani. Anahtar kelime
    #: gecilmeyen cagri yeri (bugun `api/chat.py`) bu butceyi alir.
    VARSAYILAN_BUTCE = 600

    @classmethod
    def _butce_cikar(cls, kaynaklar) -> list[int]:
        """Verilen KAYNAK METİNLERİNDEKİ `memory_context` bütçelerini çıkarır.

        Kaynak metni parametre, dosya yolu DEĞİL — ve bu tercih mutasyonla
        ölçüldü. Fonksiyon dosya yoluna bağlıyken "en dar çağrı yeri
        kazanır" kuralı SINANAMIYORDU: `min(...)` yerine `[0]` yazıldığında
        test yeşil kalıyordu, çünkü bugün iki çağrı yeri de 400 ve ikisi
        aynı sonucu veriyor. Yani kural doğruydu ama kanıtlanmıyordu; ancak
        AYRIŞAN sentetik kaynakla kanıtlanabilir.

        `ast` kullanılması aynı zamanda CLAUDE.md'nin "bir şeyin YOKLUĞUNU
        arayan bekçi onu ANLATAN yorumu görmemeli" kuralını yapısal
        karşılar: yorumdaki bir sayı çağrı düğümü değildir.
        """
        butceler: list[int] = []
        for kaynak in kaynaklar:
            for n in ast.walk(ast.parse(kaynak)):
                if not (isinstance(n, ast.Call)
                        and isinstance(n.func, ast.Attribute)
                        and n.func.attr == "memory_context"):
                    continue
                deger = cls.VARSAYILAN_BUTCE
                for kw in n.keywords:
                    if kw.arg == "max_chars" and isinstance(kw.value,
                                                            ast.Constant):
                        deger = kw.value.value
                butceler.append(deger)
        return butceler

    @classmethod
    def _en_dar_butce(cls, kaynaklar=None) -> int:
        """Hafıza bütçesini KAYNAKTAN ölçer — en dar çağrı yeri kazanır.

        Bütçe bir zamanlar bu dosyaya `400` diye ELLE yazılmıştı ve
        kaynaktaki karşılığı tek bir dizge araması
        (`"memory_context(user_id, max_chars=400)" in kaynak`) ile
        kontrol ediliyordu. O kontrol eksikti: `memory_context` ÜÇ yerden
        çağrılıyor ve dizge araması "en az biri 400" demekten öteye
        gitmiyordu — biri 200'e düşse arama yine eşleşir, test yeşil kalır
        ve sentetik hafızanın son çapaları O yüzeyde sessizce düşerdi.
        Ölçüm sınırı artık çağrı yerlerinin EN DARINDAN türetiliyor, yani
        elle yazılmış bir sayı kalmadı.
        """
        if kaynaklar is None:
            kaynaklar = [
                io.open(d, encoding="utf-8").read()
                for d in (_BACKEND / "services" / "report_service.py",
                          _BACKEND / "api" / "chat.py")]
        butceler = cls._butce_cikar(kaynaklar)
        assert butceler, "kaynakta hiç `memory_context` çağrısı bulunamadı"
        return min(butceler)

    def test_en_dar_cagri_yeri_kazaniyor(self):
        """Ölçümün geçerliliği EN DAR yüzeyde belirlenir, ortalamada değil."""
        assert self._en_dar_butce([
            "m.memory_context(u, max_chars=400)",
            "m.memory_context(u, max_chars=200)"]) == 200

    def test_anahtarsiz_cagri_imza_varsayilanini_aliyor(self):
        assert self._en_dar_butce(["m.memory_context(u)"]) == 600

    def test_yorumdaki_sayi_butce_sayilmiyor(self):
        assert self._en_dar_butce([
            "# eskiden memory_context(u, max_chars=200) ile cagriliyordu\n"
            "m.memory_context(u, max_chars=400)"]) == 400

    def test_hafiza_metni_kaynaktaki_butceye_siginiyor(self):
        """Ölçümün geçerlilik koşulu.

        `report_service` hafızayı daraltılmış bir bütçeyle çağırıyor ve
        `memory_context` sığmayan parçayı ATIYOR. Bütçeyi aşan bir
        sentetik hafızada son çapalar sessizce düşer ve ölçüm "hafıza
        okunmadı" der — oysa hafıza prompta hiç girmemiştir. Yani bu bir
        estetik sınır değil, hükmün geçerlilik koşulu.
        """
        butce = self._en_dar_butce()
        for h in ev.HAFIZALAR:
            assert len(h.metin) <= butce, (
                f"{h.ad}: {len(h.metin)} karakter > bütçe {butce}")

    def test_butce_beklenen_degerde(self):
        """Bütçe daralırsa HABER VER (sessizce dar bir ölçüm koşmasın)."""
        assert self._en_dar_butce() == 400, (
            "report_service hafıza bütçesi değişmiş; HAFIZALAR metinleri "
            "yeniden ölçülmeli")

    def test_kendi_capasini_taniyor(self):
        h = ev.HAFIZALAR[0]
        cevap = ("Bir mimarlık ofisinde çalışıyorsun ve İzmir'e yeni "
                 "taşındın; kedin Pamuk yanında.")
        assert h.anilan(cevap)

    def test_oteki_hafizanin_capasini_tanimiyor(self):
        """Sızıntı ölçümünün tersi: A'nın cevabı B'nin çapasını vermemeli."""
        a, b = ev.HAFIZALAR[0], ev.HAFIZALAR[1]
        cevap = "Bir mimarlık ofisinde çalışıyorsun, İzmir'e taşındın."
        assert a.anilan(cevap)
        assert b.anilan(cevap) == set()

    def test_birebir_dokum_yakalaniyor(self):
        """Prompt hafızayı "arka plan fısıltısı" diye veriyor ve blok
        halinde aktarmayı yasaklıyor; birebir satır o yasağın ihlalidir.
        """
        h = ev.HAFIZALAR[0]
        satir = "Bir mimarlık ofisinde proje yürütüyor"
        assert h.birebir_satir(f"Notlarım: {satir}. Bugün...")

    def test_ozetlenmis_hafiza_dokum_sayilmiyor(self):
        h = ev.HAFIZALAR[0]
        cevap = "Mimarlık işin ve yeni şehrin birlikte ağırlık yapıyor."
        assert h.birebir_satir(cevap) == []


# ---------------------------------------------------------------------------
# SKORLAMA
# ---------------------------------------------------------------------------


class TestSkorlama:
    def test_ortusme_bos_kumeleri_atiyor(self):
        """Boş küme "örtüşme yok" DEĞİL "ölçüm yok"tur; hesaba katmak
        örtüşmeyi sahte bir %0'a çekerdi.
        """
        assert ev._ortusme_orani([set(), set()]) is None
        assert ev._ortusme_orani([{"a"}, set()]) is None

    def test_ortusme_jaccard_hesapliyor(self):
        assert ev._ortusme_orani([{"a", "b"}, {"b", "c"}]) == pytest.approx(
            1 / 3)
        assert ev._ortusme_orani([{"a"}, {"a"}]) == 1.0
        assert ev._ortusme_orani([{"a"}, {"b"}]) == 0.0

    def test_puan_sizintisi_sayiliyor(self):
        """Ürün kalıcı uyum puanı GÖSTERMEZ."""
        assert ev._puan_sizintisi(["Uyumunuz %82", "normal metin"]) == 1
        assert ev._puan_sizintisi(["10 uzerinden 7"]) == 1
        assert ev._puan_sizintisi(["hiçbir puan yok"]) == 0

    def test_ortalama_benzerlik_ayni_vektorde_bir(self):
        import numpy as np
        m = np.asarray([[1.0, 0.0], [1.0, 0.0]], dtype=np.float32)
        assert ev._ortalama_benzerlik(m) == pytest.approx(1.0)
        d = np.asarray([[1.0, 0.0], [0.0, 1.0]], dtype=np.float32)
        assert ev._ortalama_benzerlik(d) == pytest.approx(0.0)

    def test_tek_metinde_benzerlik_sifir(self):
        import numpy as np
        m = np.asarray([[1.0, 0.0]], dtype=np.float32)
        assert ev._ortalama_benzerlik(m) == 0.0
# ---------------------------------------------------------------------------
# MOD HÜKÜMLERİ — "0 döndü" ile "sorun yok" aynı şey mi
# ---------------------------------------------------------------------------


class TestModHukumleri:
    """Modların DÖNÜŞ KODU bir hükümdür ve yanlış hüküm sessizdir.

    Mod çıktısını insan okuyor ama dönüş kodunu betik/CI okuyor. Kod
    yanlışsa "ölçtüm, sorun yok" denmiş olur — ölçülmeyeni söylemenin en
    sinsi hâli. Burada LLM ve gömme (embedding) yerine sahteler konuyor;
    ölçülen şey yalnızca hüküm mantığı.
    """

    @staticmethod
    def _sahtele(monkeypatch, metinler):
        """Üretimi sabit bir metin dizisine, vektörlemeyi None'a pinler.

        `_vektorle` None dönebilen bir daldır (gerçek koşuda gömme
        çağrısı düşerse olan budur) ve mod o dalda ÇÖKMEMELİ — hüküm
        benzerliğe değil birebir farka bağlı.
        """
        sira = list(metinler)
        monkeypatch.setattr(ev, "_vektorle", lambda m: None)
        monkeypatch.setattr(ev, "_onbellegi_atla", lambda: None)
        monkeypatch.setattr(ev, "_cevap_uret",
                            lambda b, s, lang="tr", hafiza="": sira.pop(0))

    def test_ayni_metin_hafiza_modunda_kirmizi(self, monkeypatch):
        """Farklı hafıza aynı metni veriyorsa hafıza HÜKME girmiyor."""
        self._sahtele(monkeypatch, ["Aynı cevap.", "Aynı cevap."])
        assert ev._hafiza_modu(ev._yuzeyler()["chat"]) == 1

    def test_ayrisan_ve_temiz_metin_yesil(self, monkeypatch):
        """Ayrışıyor, sızıntı yok, birebir döküm yok -> hüküm 0."""
        self._sahtele(monkeypatch, [
            "Mimarlık işin ve İzmir'e taşınman birlikte ağırlık yapıyor.",
            "Kimya öğretmenliğin ve Berke ile konuşmaların seni tutuyor.",
        ])
        assert ev._hafiza_modu(ev._yuzeyler()["chat"]) == 0

    def test_oteki_hafizanin_capasi_sizarsa_kirmizi(self, monkeypatch):
        """Zehirlenme: A'nın hafızasıyla sorulan soru B'nin çapalarını
        anıyorsa cevap kendi bağlamından kopmuş demektir.
        """
        self._sahtele(monkeypatch, [
            "Mimarlık işin; ayrıca kimya öğretmenliğin de etkili.",
            "Kimya öğretmenliğin ve Berke ile bağın.",
        ])
        assert ev._hafiza_modu(ev._yuzeyler()["chat"]) == 1

    def test_birebir_dokum_kirmizi(self, monkeypatch):
        self._sahtele(monkeypatch, [
            "Notum: Bir mimarlık ofisinde proje yürütüyor. Devam edelim.",
            "Kimya öğretmenliğin ve Berke ile bağın.",
        ])
        assert ev._hafiza_modu(ev._yuzeyler()["chat"]) == 1

    def test_rapor_modu_ayni_metinde_kirmizi(self, monkeypatch):
        """Rapor yüzeyinde hüküm: iki girdi aynı metni aldıysa jenerik."""
        monkeypatch.setattr(ev, "_vektorle", lambda m: None)
        monkeypatch.setattr(ev, "_onbellegi_atla", lambda: None)
        y = ev._yuzeyler()["bazi"]
        sahte = dataclasses.replace(
            y, uret=lambda g, l: {"text": "Her haritaya aynı metin."},
            olgular=None,
            girdiler=lambda n: [("x", {}), ("y", {})])
        assert ev._rapor_modu(sahte, 2) == 1

    def test_rapor_modu_farkli_metinde_yesil(self, monkeypatch):
        monkeypatch.setattr(ev, "_vektorle", lambda m: None)
        monkeypatch.setattr(ev, "_onbellegi_atla", lambda: None)
        sayac = {"n": 0}

        def uret(g, l):
            sayac["n"] += 1
            return {"text": f"Haritaya özel metin {sayac['n']}."}

        y = dataclasses.replace(
            ev._yuzeyler()["bazi"], uret=uret, olgular=None,
            girdiler=lambda n: [("x", {}), ("y", {})])
        assert ev._rapor_modu(y, 2) == 0

    def test_kapsam_disi_yuzey_rapor_modunda_olculmez(self):
        """Kapsam dışı yüzeye sayı basmak, ölçülmeyeni söylemek olurdu."""
        assert ev._rapor_modu(ev._yuzeyler()["signal-bundle"], 2) == 1
# ---------------------------------------------------------------------------
# KÖR NOKTA SINAVI — mutasyonla ölçülmüş boşluklar
#
# Aşağıdaki testlerin HEPSİ mutasyon sınavında bulundu: ilgili onarım TEK
# KATMAN geri alındığında 108 testin hiçbiri kırılmıyordu. Yani onarım
# gerçekten vardı ama KANITLANMIYORDU — kaza ile güvenli olan şey güvence
# değildir (aynı ders `TestLlmPini`de yazılı).
#
# Mutasyonun bileşik olmaması önemli: üç katmanı birden geri alan bir
# mutasyon, bir katmanı tutan bekçinin ötekinin kör olmasını maskeler.
# Buradaki her test TEK bir katmanı sorar.
# ---------------------------------------------------------------------------


class TestUzunAdKelimeOrtasi:
    """`_ad_gecti`nin UZUN ad dalının kendi bekçisi.

    Mutasyon: uzun ad dalı düz alt diziye çevrildiğinde takımın TAMAMI
    yeşil kaldı. Sebep ölçüldü: dosyadaki bütün yanlış-pozitif testleri
    KISA adlarla yazılmış ("ay", "boğa", "kova", "yay", "mars"); uzun
    adlar için yalnız "eşleşmeli" yönü sorulmuş ve düz alt dizi o yönü de
    geçiyor. Yani aracın en pahalı kusurunun YARISI bekçisizdi.

    Aşağıdaki çakışmalar ölçüldü, uydurulmadı: "aslan" (Aslan burcu)
    "p**aslan**mış" kelimesinin içinde, "balık" (Balık burcu)
    "k**abalık**" kelimesinin içinde geçiyor. İkisi de astroloji
    metninde geçmesi beklenen günlük Türkçe.
    """

    @pytest.mark.parametrize("ad, metin", [
        ("aslan", "Zihnin paslanmış gibi, harekete geçmiyorsun."),
        ("aslan", "Bu konu paslanıyor, ertelemek işe yaramıyor."),
        ("balık", "Bu kabalık değil, sınır koymak."),
    ])
    def test_uzun_ad_kelime_ortasinda_sayilmiyor(self, ad, metin):
        assert not ev._ad_gecti(N(metin), ad)


class TestKalipKelimeSiniri:
    r"""`_kalip_sayisi`nin `\b` sınırının kendi bekçisi.

    Mutasyon: `\b` kaldırıldığında takımın tamamı yeşil kaldı. Var olan
    `test_hissettiren_kelimesi_sahte_sizinti_uretmiyor` sanıldığı şeyi
    ölçmüyor: o gerileme kalıp LİSTESİ düzeltilerek ("hisse" ->
    "hisse senedi") kapatılmıştı, yani o test listeyi çiviliyor, SINIRI
    değil. Sınır ayrı bir katman ve ayrı sorulmalı.

    Ölçülen çakışmalar — en kötüsü ürünün KENDİ diline ait:
    `ölüm\w*` ⊂ "**bölüm**ler" / "**bölüm**ünde". Raporların kendi bölüm
    başlıkları bu kelimeyi kullanıyor, yani sınır düşerse yasak alan
    sayacı HER yapılandırılmış raporda "ölüm" sızıntısı bildirirdi — hem
    de tam olarak sahibin güvenmesi gereken sayıda.
    İkinci çakışma: `gebe(lik)?\w*` ⊂ "en**gebe**li".
    """

    @pytest.mark.parametrize("metin", [
        "Bölümler: (1) Genel rezonans, (2) Güçlü bağ noktaları.",
        "Raporun ikinci bölümünde bunu açıkladım.",
        "Engebeli bir arazide yürüyor gibisin.",
    ])
    def test_yasak_kalip_kelime_ortasinda_sayilmiyor(self, metin):
        assert ev._kalip_sayisi(metin, ev.YASAK, regex=True) == []

    def test_gercek_sizinti_hala_yakalaniyor(self):
        """İki yön birlikte sorulur: sınır sıkılaşırken avın kaçmaması."""
        assert ev._kalip_sayisi("Ölüm korkusu ağır basıyor.", ev.YASAK,
                                regex=True)


class TestKelimeBasiSiniri:
    r"""`_kelime_basi`nin SOL `\b` sınırının kendi bekçisi.

    Mutasyon: düz alt diziye çevrildiğinde takım yeşil kaldı. Fonksiyonun
    kendi docstring'i sol sınırı "şart" diye yazıyor ama hiçbir test onu
    sormuyordu — yazılı gerekçe ile ölçülmüş davranış arasındaki boşluk.

    Ölçülen çakışma: "doğ" kökü (öğretmen hafızasının "Trabzon'da doğdu"
    çapası) "güney**doğ**uda" kelimesinin İÇİNDE geçiyor. Yani
    coğrafyadan söz eden sıradan bir cevap, hafıza olgusunu anılmış
    sayardı ve hafıza ölçümü yanlış pozitif üretirdi.
    """

    @pytest.mark.parametrize("metin", [
        "Güneydoğuda yaşayan biri gibi düşünüyorsun.",
        "Kuzeydoğuya bakan bir pencere.",
    ])
    def test_kok_kelime_ortasinda_sayilmiyor(self, metin):
        assert not ev._kelime_basi(N(metin), "doğ")

    def test_kok_kelime_basinda_sayiliyor(self):
        assert ev._kelime_basi(N("Trabzon'da doğdu."), "doğ")


class TestHafizaCapaEsigi:
    """Çapa EŞİĞİNİN (en az iki kök) kendi bekçisi.

    Mutasyon: eşik 1'e düşürüldüğünde takım yeşil kaldı. Var olan
    `test_her_capa_en_az_iki_kokten_olusuyor` VERİYİ ölçüyor (demetin iki
    kökü var mı), EŞLEŞME KURALINI değil. İkisi ayrı katman: iki köklü bir
    demet, tek kök görülünce de sayılabilir ve veri testi bunu görmez.

    Eşik neden hayati: "karar", "umut", "kaygı" gibi kökler hemen her
    cevapta geçer. Tek kök yeterse "sızıntı" ölçümü kendi kendine yanlış
    pozitif üretir ve ölçüm P2'nin onarımını haksız yere suçlar — yani
    ölçerin hatası başka bir paketin kusuru gibi okunur.
    """

    def test_tek_kok_capa_saymiyor(self):
        h = ev.HAFIZALAR[1]
        assert ("umut", "karar") in h.capalar
        assert h.anilan("Bir karar vermem gerekiyor.") == set()

    def test_iki_kok_birlikte_sayiliyor(self):
        h = ev.HAFIZALAR[1]
        assert "umut+karar" in h.anilan(
            "Umutluyum ama karar veremiyorum.")


class TestYagcilikBasYumusamasi:
    """Son ses yumuşamasının BAŞ tarafı.

    Bu kusur doğrulama turunda ölçüldü ve onarıldı: `_ek_toleransli_desen`
    ilk hâlinde yalnız KUYRUĞA uygulanıyordu, gerekçesi de "öteki
    üyelerde mutasyon yok" diye çivilenmişti. O gerekçe yanlıştı — BAŞ
    listesinin kendisinde `k` ile biten bir üye var: "farkındalık".
    Ölçüldü: tek taraflı hâlde "Farkındalığın alanı genişliyor." ifadesi
    HİÇ yakalanmıyordu. Yani kuyruk onarımı kusuru kaldırmamış, yalnız
    BAŞA TAŞIMIŞTI.

    Çapa tek bir yazıma bağlanmaz: hem yumuşamış hem yumuşamamış biçim,
    hem de iki ayrı kuyrukla sorulur.
    """

    @pytest.mark.parametrize("metin, beklenen", [
        ("Farkındalığın alanı genişliyor.", "farkındalığın alanı"),
        ("Farkındalığının kapısı aralanıyor.", "farkındalığının kapısı"),
        ("Bu bir farkındalık davetidir.", "farkındalık davetidir"),
    ])
    def test_bas_yumusamasi_yakalaniyor(self, metin, beklenen):
        assert beklenen in ev._yagcilik_bulgulari(metin), metin

    def test_sinif_ayni_ifadeyi_iki_kez_saymiyor(self):
        """Mutasyon: `set` yerine `list` kullanıldığında takım yeşil kaldı.

        Kodun kendi yorumu "aynı ifade iki kez geçiyorsa bir kez sayılır"
        diyor ama kimse sormuyordu. Önemi: rapor "YAGCILIK: 2" basarsa
        okuyan iki ayrı kusur arar, oysa tek ifade vardır — ölçülenin
        yanlış adla sunulması.
        """
        metin = ("Bu bir büyüme alanı; evet, gerçekten bir büyüme alanı.")
        assert ev._yagcilik_bulgulari(metin) == ["büyüme alanı"]


class TestPuanSizintisiYazim:
    """`_puan_sizintisi`nin yazıma bağlı kör noktası — doğrulama turunda
    ölçüldü ve onarıldı.

    Eski hâl HAM metinde ASCII `"10 uzerinden"` dizesini arıyordu; ölçüldü:
    modelin gerçekten üreteceği Türkçe yazım ("10 üzerinden") KAÇIYORDU.
    Üstelik kendi testi ASCII biçimi çivileyerek kusuru GİZLİYORDU — yeşil
    bir test, avlaması gereken biçime kör bir dedektörü doğruluyordu.
    """

    @pytest.mark.parametrize("metin", [
        "Uyumunuz 10 üzerinden 7.",
        "Uyumunuz 100 ÜZERİNDEN 82.",
        "10 uzerinden 7",
        "Uyum: 82/100",
        "Uyumunuz %82",
    ])
    def test_puan_her_yazimda_yakalaniyor(self, metin):
        assert ev._puan_sizintisi([metin]) == 1, metin

    @pytest.mark.parametrize("metin", [
        "Üzerinden bir yıl geçti.",
        "Bu konunun üzerinden gitmek gerek.",
        "hiçbir puan yok",
    ])
    def test_puansiz_metin_sahte_sizinti_uretmiyor(self, metin):
        assert ev._puan_sizintisi([metin]) == 0, metin


class TestFirasetCapaEsigi:
    """Çapa UZUNLUK eşiğinin (4+ harf) kendi bekçisi.

    Mutasyon: eşik 1'e düşürüldüğünde takım yeşil kaldı. Eşik ölçüldü ve
    gerçekten taşıyor: `firasa_service.summary` satırlarında 4 harften
    kısa iki kelime geçiyor — **"üst"** ve **"dar"** ("Üst bölge ... dar"
    satırı). İkisi de sıradan Türkçe, yani eşik düşerse alın belirtisiyle
    hiç ilgisi olmayan bir cümle o belirtiyi anılmış sayar.
    """

    RATIOS = {"upperThird": 0.26, "middleThird": 0.37, "lowerThird": 0.37,
              "lipFullness": 0.065, "eyeSpacing": 0.40}

    @pytest.mark.parametrize("metin", [
        "Dar bir yolun üst kısmında duruyorsun.",
        "Üst üste gelen işler var, zaman dar.",
    ])
    def test_kisa_tasiyici_kelimeler_capa_olmuyor(self, metin):
        assert "forehead_short" not in ev._firasa_olgular(metin, self.RATIOS)


class TestHeksagramKisaPinyin:
    """Heksagramda `_ad_gecti` seçiminin kendi bekçisi.

    Mutasyon: `_ad_gecti` -> `_kelime_basi` yapıldığında takım yeşil kaldı.
    Kodun kendi yorumu bu seçimi açıkça gerekçelendiriyor ("pinyin
    adlarının bir kısmı iki harfli: Fu, Bi, Lu") ama kimse sormuyordu.

    Ölçüldü: `_kelime_basi(metin, "Fu")` "**fu**tbol" ve "**fu**ar"
    kelimelerinde True döner. Numara her metinde geçtiği için ikinci
    işaret tek başına hükmü taşıyor; o işaret gevşerse çekilmemiş bir
    heksagram "anılmış" sayılır.
    """

    VERI = {"primary": {"number": 24, "name": "Fu", "name_tr": "Dönüş"},
            "transformed": None, "moving_lines": []}

    @pytest.mark.parametrize("metin", [
        "24. yılda futbol konuşuyoruz.",
        "24 kişi için bir fuar düzenlendi.",
    ])
    def test_kisa_pinyin_kelime_onune_takilmiyor(self, metin):
        assert "heks-24" not in ev._heksagram_olgular(metin, self.VERI)

    def test_gercek_anilma_hala_yakalaniyor(self):
        assert "heks-24" in ev._heksagram_olgular("24. heksagram, Dönüş.",
                                                  self.VERI)


class TestKapsamCiktisiYalanBasmiyor:
    """Kapsam çıktısındaki "olgu YOK" satırının kendi bekçisi.

    İKİ mutasyon birden buraya bakıyor ve her biri BAĞIMSIZ olarak bu
    testi kırmalı: (1) `kendi_modu` alanı kaldırılırsa, (2) `elif`
    `if`e çevrilirse. İkisinde de sohbet yüzeyi için "olgu : YOK"
    basılır — oysa sohbet modu olgu ÖLÇÜYOR, yalnız ortak rapor tablosunu
    kullanmıyor. Paket bu yalanı onardığını bildirdi ama bekçisini
    yazmadı, yani onarım kanıtsızdı.

    Test İKİ YÖNE çalışır: gerçekten olgu ölçmeyen tek yüzeyde (burç
    yorumu) satır basILMALI. Tek yön sorulsaydı "satırı hiç basmamak" da
    testi geçerdi ve o zaman "ölçülmeyen söylenmez" ilkesinin öteki yarısı
    (ölçülmeyeni SÖYLEMEMEK) kaybolurdu.
    """

    @staticmethod
    def _blok(ad):
        import contextlib
        tampon = io.StringIO()
        with contextlib.redirect_stdout(tampon):
            ev._kapsam_modu()
        for parca in tampon.getvalue().split("["):
            if parca.startswith(f"+] {ad} ") or parca.startswith(f"-] {ad} "):
                return parca
        raise AssertionError(f"kapsam çıktısında {ad} bloğu yok")

    def test_sohbet_icin_olgu_YOK_basilmiyor(self):
        blok = self._blok("chat")
        assert "olgu : YOK" not in blok, (
            "sohbet olgu ÖLÇÜYOR; 'olgu YOK' yazmak ölçüleni yok saymak")
        assert "--mode chat" in blok, "sohbetin kendi modu yazılmalı"

    def test_gercekten_olcmeyen_yuzeyde_olgu_YOK_basiliyor(self):
        assert "olgu : YOK" in self._blok("horoscope")


class TestRaporModuGercektenOlcuyor:
    """Rapor modunun yağcılık/yasak sayaçlarının kendi bekçisi.

    Mutasyon: iki toplama satırı silindiğinde takım yeşil kaldı — ve
    çıktı yine "YAGCILIK: 0 (hedef 0)" basıyordu. Bu, ürün ilkesinin tam
    tersi: ölçülmemiş bir şeyin ölçülmüş gibi, hem de TEMİZ gibi
    sunulması. Dönüş kodu da değişmediği için hiçbir yerden kırmızı
    görünmezdi.
    """

    @staticmethod
    def _cikti(monkeypatch, metin):
        import contextlib
        monkeypatch.setattr(ev, "_vektorle", lambda m: None)
        monkeypatch.setattr(ev, "_onbellegi_atla", lambda: None)
        sayac = {"n": 0}

        def uret(g, l):
            sayac["n"] += 1
            return {"text": f"{metin} (girdi {sayac['n']})"}

        y = dataclasses.replace(
            ev._yuzeyler()["bazi"], uret=uret, olgular=None,
            girdiler=lambda n: [("x", {}), ("y", {})])
        tampon = io.StringIO()
        with contextlib.redirect_stdout(tampon):
            ev._rapor_modu(y, 2)
        return tampon.getvalue()

    def test_yagcilik_sayaci_gercekten_sayiyor(self, monkeypatch):
        cikti = self._cikti(monkeypatch, "Bu muhteşem bir dönem.")
        assert "YAGCILIK: 2" in cikti, cikti

    def test_yasak_sayaci_gercekten_sayiyor(self, monkeypatch):
        cikti = self._cikti(monkeypatch, "Borsada yatırım yapma.")
        assert "YASAK   : 4" in cikti, cikti

    def test_temiz_metinde_sayaclar_sifir(self, monkeypatch):
        cikti = self._cikti(monkeypatch, "Satürn kare Güneş okunuyor.")
        assert "YAGCILIK: 0" in cikti
        assert "YASAK   : 0" in cikti


# ---------------------------------------------------------------------------
# YEDEK METNI OLCMEK — "metinler farkli" tek basina yesil yapmaz
# ---------------------------------------------------------------------------


def _metin_ayiklayan_ureticiler() -> set[str]:
    """`_uret_*` ureticilerinden `["text"]` ile metni AYIKLAYANLARI bulur.

    `ast` ile yapiliyor, metin aramasiyla degil: bu dosyanin ve betigin
    yorumlari bu kaliptan bolca soz ediyor ve duz arama kendi
    aciklamasina takilirdi (CLAUDE.md: yoklugu arayan bekci onu anlatan
    yorumu gormemeli).
    """
    kaynak = io.open(_BETIK, encoding="utf-8").read()
    bulunan: set[str] = set()
    for dugum in ast.parse(kaynak).body:
        if not isinstance(dugum, ast.FunctionDef):
            continue
        if not dugum.name.startswith("_uret_"):
            continue
        for n in ast.walk(dugum):
            if (isinstance(n, ast.Subscript)
                    and isinstance(n.slice, ast.Constant)
                    and n.slice.value == "text"):
                bulunan.add(dugum.name)
    return bulunan


class TestYedekMetinHukmu:
    """Olcum SABLON metnini model ciktisi sanmasin.

    Bu, bu depoda bir kez CANLI olarak olusmus kusur sinifinin aynisi
    (CLAUDE.md §6: "Zamanlanmis isler bir AY boyunca YESIL yalan
    soyledi"). Olcerin eski hâli `report_service` sozlugunden yalniz
    `["text"]` aliyor, `fallback` bayragini ATIYORDU; sablonlar ise
    girdiye ozel alan tasiyor (`NATAL_FALLBACK` "Günesin {sun_sign}…"),
    yani tam dususte dort girdi dort FARKLI dize uretiyor ve hukum
    "jenerik degil" cikiyordu.

    Testler IKI YONE sorar: yedek varken kirmizi, yedek yokken yesil.
    Tek yon sorulsaydi "her kosuda kirmizi don" da gecerdi ve arac
    kullanilamaz hâle gelirken bekci bunu gormezdi.
    """

    @staticmethod
    def _kos(monkeypatch, sonuclar):
        import contextlib
        monkeypatch.setattr(ev, "_vektorle", lambda m: None)
        monkeypatch.setattr(ev, "_onbellegi_atla", lambda: None)
        sira = list(sonuclar)
        y = dataclasses.replace(
            ev._yuzeyler()["bazi"], uret=lambda g, l: sira.pop(0),
            olgular=None,
            girdiler=lambda n: [("x", {}), ("y", {})])
        tampon = io.StringIO()
        with contextlib.redirect_stdout(tampon):
            kod = ev._rapor_modu(y, 2)
        return kod, tampon.getvalue()

    #: Girdiye OZEL alan tasiyan iki sablon — gercek sablonlarin biçimi.
    _AYRISIK_YEDEK = (
        {"text": "Günesin Aslan, Ayin Boga.", "fallback": True},
        {"text": "Günesin Terazi, Ayin Yay.", "fallback": True},
    )

    def test_ayrisik_yedekler_yesil_donmez(self, monkeypatch):
        """Iki yedek BIREBIR FARKLI olsa da hukum kirmizi olmali."""
        kod, cikti = self._kos(monkeypatch, self._AYRISIK_YEDEK)
        assert "birebir farkli metin : 2/2" in cikti, cikti
        assert kod == 1, (
            "yedek metinler farkli diye yesil dondu; hic LLM metni "
            "uretilmemisken 'jenerik degil' hukmu verilmis olurdu")

    def test_yedek_sayisi_basiliyor(self, monkeypatch):
        """Sayi EKRANDA da olmali: donus kodunu insan okumuyor."""
        _, cikti = self._kos(monkeypatch, self._AYRISIK_YEDEK)
        assert "YEDEK (sablon) metin : 2/2" in cikti, cikti
        assert "OLCMUYOR" in cikti, cikti

    def test_yedeksiz_kosu_yine_yesil(self, monkeypatch):
        """Ters yon: bayrak yoksa hukum degismemeli."""
        kod, cikti = self._kos(monkeypatch, (
            {"text": "Satürn kare Günes okunuyor."},
            {"text": "Jüpiter ucgen Ay okunuyor."},
        ))
        assert "YEDEK (sablon) metin : 0/2" in cikti, cikti
        assert kod == 0, cikti

    def test_tek_yedek_de_kirmizi(self, monkeypatch):
        """Kismi dusus de hukmu baglar: olculen kume karisik olur."""
        kod, _ = self._kos(monkeypatch, (
            {"text": "Satürn kare Günes okunuyor."},
            {"text": "Günesin Terazi, Ayin Yay.", "fallback": True},
        ))
        assert kod == 1

    @staticmethod
    def _hafiza_kos(monkeypatch, sonuclar):
        import contextlib
        monkeypatch.setattr(ev, "_vektorle", lambda m: None)
        monkeypatch.setattr(ev, "_onbellegi_atla", lambda: None)
        monkeypatch.setattr(ev, "_hafizayi_sabitle", lambda m: None)
        sira = list(sonuclar)
        y = dataclasses.replace(
            ev._yuzeyler()["daily"], uret=lambda g, l: sira.pop(0),
            girdiler=lambda n: [("x", {}), ("y", {})])
        tampon = io.StringIO()
        with contextlib.redirect_stdout(tampon):
            kod = ev._hafiza_modu(y)
        return kod, tampon.getvalue()

    def test_hafiza_modunda_kismi_yedek_yesil_donmez(self, monkeypatch):
        """Hafiza modunun hukmu YEDEGE de bakmali.

        ⚠️ Bu test ilk hâlinde KÖR BEKCIYDI ve mutasyonla olculdu: iki
        yedek metin VERILIYORDU ve girdi sabit oldugu icin ikisi birebir
        ayni oluyordu, yani hukum zaten "ayrismadi" uzerinden kirmiziya
        dusuyordu. Hukumden yedek terimi silindiginde test YESIL kaliyordu.

        Terimin gercekten korudugu hâl bu: GECICI dusus. Ilk cagri
        sablona duser, ikincisi model metni dondurur -> metinler FARKLI,
        sizinti yok, birebir dokum yok. Yedek terimi olmasa mod yesil
        doner ve okuyan "hafiza kilidi saglam" der — oysa iki metnin biri
        hic uretilmemistir.
        """
        kod, cikti = self._hafiza_kos(monkeypatch, (
            {"text": "Bugun soylenecek olculmus bir sey yok.",
             "fallback": True},
            {"text": "Lisedeki dersin ve verecegin karar birlikte duruyor.",
             "fallback": False},
        ))
        assert "birebir farkli metin: 2/2" in cikti, cikti
        assert kod == 1, cikti

    def test_hafiza_modunda_yedek_teshisi_saptirmiyor(self, monkeypatch):
        """Yedek, hafiza modunda AYRISMAMA gibi gorunur.

        Girdi sabit oldugu icin TAM dususte iki metin birebir ayni olur
        ve okuyan "hafiza hukme girmiyor" der — oysa sebep uretimin
        dusmesi. Yanlis gerekceye varilmasin diye yedek ONCE ve ADIYLA
        basilmali (CLAUDE.md §6'daki "403 biçim hatasi olarak
        loglaniyor" tuzaginin aynisi). Burada olculen sey HUKUM degil
        TESHIS: yazi olmazsa sayi dogru, gerekce yanlis olur.
        """
        kod, cikti = self._hafiza_kos(monkeypatch, (
            {"text": "Sablon.", "fallback": True},
            {"text": "Sablon.", "fallback": True},
        ))
        assert "hafizadan degil" in cikti, cikti
        assert kod == 1

    def test_ureticiler_metni_ayiklamiyor(self):
        """Ureticiler sozlugun TAMAMINI dondurmeli.

        Yapisal bekci: bir uretici `["text"]` ile metni ayiklarsa
        `fallback` bayragi o yuzeyde SESSIZCE kaybolur — yukaridaki
        hukum testleri sahte uretici kullandigi icin bunu goremez.
        """
        ayiklayan = _metin_ayiklayan_ureticiler()
        assert not ayiklayan, (
            "bu ureticiler sozlukten yalniz metni AYIKLIYOR ve fallback "
            f"bayragini dusuruyor: {sorted(ayiklayan)}")


# ---------------------------------------------------------------------------
# GUN SINIRI — olcum betigi uretim profilini okumaz
# ---------------------------------------------------------------------------


class TestGunSinirPini:
    """Gunluk yuzeylere gun PARAMETREYLE veriliyor mu.

    Betik uc gunluk yuzeyi `today`/`sky` gecirmeden cagiriyordu. Cagri
    kirilmiyordu (hepsi varsayilanli) ama iki sey birden oluyordu:
    (1) BaZi/dogum kapisi/gunluk okuma/ikili dinamik gunu
    `entitlements.user_local_date("eval")`den aliyordu — var olmayan bir
    uid icin IKI uretim okumasi (olculdu: `cache.get("user-tz-eval")` +
    `profile_service.get_profile("eval")`); (2) firasette gun blogu BOS
    geciyordu ve sablon o hâlde "bugun" kelimesini yasakliyor, yani
    "GUNLUK yuzey" diye kayitli bir yuzeyin gun kesisimi hic
    olculmuyordu.
    """

    @staticmethod
    def _yakala(monkeypatch):
        """`report_service` cagrilarini kwargs'lariyla yakalar.

        Girdi hesaplari (kerykeion/BaZi) da pinleniyor: olculen sey
        BAGLANTI, hesap degil.
        """
        from core import entitlements
        from services import report_service

        def _yasak(uid):
            raise AssertionError(
                "Olcum betigi uretim profilini okumaya kalkti: "
                f"user_local_date({uid!r})")

        monkeypatch.setattr(entitlements, "user_local_date", _yasak)
        monkeypatch.setattr(ev, "_bazi_harita", lambda g: {"pillars": {}})
        monkeypatch.setattr(ev, "_dogum_kapisi", lambda g: {"gate": 1})
        monkeypatch.setattr(ev, "_natal", lambda g: {"points": []})
        monkeypatch.setattr(ev, "_sinastri", lambda c: {"aspects": []})
        monkeypatch.setattr(ev, "_gokyuzu", lambda lang="tr": {})

        cagrilar: dict = {}

        def kayit(ad):
            def f(*a, **kw):
                cagrilar[ad] = kw
                return {"text": "metin"}
            return f

        for ad in ("bazi_report", "birth_hexagram_report", "daily_reading",
                   "dyad_reading", "firasa_report", "horoscope_reading"):
            monkeypatch.setattr(report_service, ad, kayit(ad))
        return cagrilar

    def test_bazi_gunu_parametreyle_geciyor(self, monkeypatch):
        c = self._yakala(monkeypatch)
        ev._uret_bazi(ev.HARITALAR[0][1], "tr")
        assert c["bazi_report"].get("today") == ev._olcum_gunu()

    def test_dogum_kapisi_gunu_parametreyle_geciyor(self, monkeypatch):
        c = self._yakala(monkeypatch)
        ev._uret_dogum_kapisi(ev.HARITALAR[0][1], "tr")
        assert c["birth_hexagram_report"].get("today") == ev._olcum_gunu()

    def test_gunluk_okuma_gunu_parametreyle_geciyor(self, monkeypatch):
        """Ayni sinif: bu yuzey bulgu kaydinda ANILMIYORDU.

        Kayit uc yuzey sayiyordu; ayni kusur `daily_reading` ve
        `dyad_reading`de de vardi (ikisi de `today or
        user_local_date(uid)` yaziyor). Bulgu listesine guvenip ucunu
        onarmak, ayni kusuru iki yerde birakmak olurdu.
        """
        c = self._yakala(monkeypatch)
        ev._uret_gunluk(ev.HARITALAR[0][1], "tr")
        assert c["daily_reading"].get("today") == ev._olcum_gunu()

    def test_ikili_dinamik_gunu_parametreyle_geciyor(self, monkeypatch):
        c = self._yakala(monkeypatch)
        ev._uret_ikili(({"name": "Ada"}, {"name": "Bora"}), "tr")
        assert c["dyad_reading"].get("today") == ev._olcum_gunu()

    def test_burc_yorumu_gunu_parametreyle_geciyor(self, monkeypatch):
        """BESINCI yuzey: bir sonraki turda yakalandi.

        `horoscope_reading` gunu dogrudan prompta yaziyor ve parametre
        verilmezse SUNUCUNUN UTC gununu kullaniyor; kardes yuzey (gunluk
        bildirim govdesi) ise `_olcum_gunu()` aliyor. Tablodaki `olcu`
        satiri ikisini ayni sinifa koydugu ve girdilerini (`_burclar`)
        PAYLASTIRDIGI icin gun teriminin ayrismasi tam olarak
        kiyaslanabilirligi bozardi.
        """
        c = self._yakala(monkeypatch)
        ev._uret_burc("leo", "tr")
        assert c["horoscope_reading"].get("today") == ev._olcum_gunu()

    def test_today_alabilen_her_yuzey_today_aliyor(self, monkeypatch):
        """TUKETICI LISTESI IMZALARDAN okunur, elle yazilmaz.

        Bu bekci, elle sayilan listenin iki kez eksik kalmasindan sonra
        yazildi (ilk turda uc yuzey yazilmisti, dort eksikti; ikinci
        turda biri — burc yorumu — hâlâ eksikti). Soru artik tek tek
        yuzey adi degil DEGISMEZ: "`report_service`'te `today`
        parametresi olan ve olculen her yuzey onu GECMELI". Yeni bir
        gunluk yuzey eklendiginde ya da var olan birine `today`
        eklendiginde bu test kendiliginden sorar.

        Yuzey -> uretim fonksiyonu baglantisi uydurulmuyor: tablonun
        kendi `kaynak` alani zaten o adi tasiyor.
        """
        import inspect

        from services import report_service

        # Imzalar YAMADAN ONCE okunur: `_yakala` fonksiyonlari degistiriyor.
        # `ValueError`/`TypeError` yutulur cunku modulde imzasi okunamayan
        # bir sey (C fonksiyonu, yeniden ice alinmis bir sinif) bulunmasi
        # bu bekcinin DERDI DEGIL — olmeyen bekci daha iyi bekcidir.
        imzalar = {}
        for ad in dir(report_service):
            nesne = getattr(report_service, ad, None)
            if ad.startswith("_") or not callable(nesne):
                continue
            try:
                imzalar[ad] = inspect.signature(nesne).parameters
            except (ValueError, TypeError):  # pragma: no cover
                continue
        c = self._yakala(monkeypatch)

        sorulan = []
        for y in ev._yuzeyler().values():
            if y.kapsam != "olculuyor" or y.uret is None:
                continue
            modul, _, fn = y.kaynak.partition(".")
            if modul != "report_service" or "today" not in imzalar.get(fn, {}):
                continue
            girdiler = y.girdiler(2) if y.girdiler else []
            assert girdiler, f"{y.ad}: girdi uretilemedi"
            y.uret(girdiler[0][1], "tr")
            assert c[fn].get("today") == ev._olcum_gunu(), (
                f"{y.ad} ({y.kaynak}) gunu GECMIYOR")
            sorulan.append(y.ad)

        # Dongunun bos donmesi testi sessizce ise yaramaz yapardi.
        assert len(sorulan) >= 5, sorulan

    def test_firaset_harita_ve_gun_blogu_geciyor(self, monkeypatch):
        c = self._yakala(monkeypatch)
        monkeypatch.setattr(ev, "_firaset_baglam_onbellek", {})
        monkeypatch.setattr(ev.chart_context, "natal_facts", lambda b: {})
        monkeypatch.setattr(ev.chart_context, "transit_facts",
                            lambda b: {"hits": [{"x": 1}], "upcoming": []})
        bayraklar: dict = {}

        def sahte_render(f, lang=None, include_transits=True):
            bayraklar["include_transits"] = include_transits
            return "HARITA-BLOGU"

        def sahte_gokyuzu(f, lang=None, today=None):
            bayraklar["today"] = today
            return "GUN-BLOGU"

        monkeypatch.setattr(ev.chart_context, "render", sahte_render)
        monkeypatch.setattr(ev.chart_context, "gunun_gokyuzu",
                            sahte_gokyuzu)
        ev._uret_firasa({"jawWidth": 0.8}, "tr")

        assert c["firasa_report"].get("chart") == "HARITA-BLOGU"
        assert c["firasa_report"].get("sky") == "GUN-BLOGU"
        assert bayraklar["today"] == ev._olcum_gunu()
        # Kalici blok gun satirlarini TASIMAMALI: gun ayri baslik altinda
        # veriliyor, iki kez verilse model hangisinin bugune ait oldugunu
        # ayirt edemezdi.
        assert bayraklar["include_transits"] is False

    def test_olcum_gunu_varsayilan_dilimde(self, monkeypatch):
        """Gun SUNUCUNUN degil varsayilan dilimin gunu olmali.

        Fark yalniz 21:00-24:00 UTC arasinda gorunur, yani gercek saate
        bagli bir test gunun %87'sinde kor olurdu. Bu yuzden an
        SABITLENIYOR: 22:30 UTC'de Istanbul ERTESI gunde.
        """
        import datetime as _dt
        import types

        sabit = _dt.datetime(2026, 10, 3, 22, 30, tzinfo=_dt.timezone.utc)

        class _Dt(_dt.datetime):
            @classmethod
            def now(cls, tz=None):
                return sabit.astimezone(tz) if tz else sabit

        monkeypatch.setattr(ev, "_gun_onbellek", {})
        monkeypatch.setattr(ev, "dt", types.SimpleNamespace(
            datetime=_Dt, timezone=_dt.timezone, date=_dt.date))
        assert ev._olcum_gunu() == _dt.date(2026, 10, 4)

    def test_olcum_gunu_profil_okumuyor(self, monkeypatch):
        """Gun URETIMDEN sorulmuyor.

        ⚠️ GEREKCE DARALTILDI (dogrulama turu, 2026-10-03). Bu testin
        eski hâli adinda ve docstring'inde IKI sey iddia ediyordu:
        "profil okunmuyor VE deger kosu boyunca ayni". Ikincisini
        `_olcum_gunu() == _olcum_gunu()` ile soruyordu ve o esitlik
        onbellek OLMASA DA dogrudur — iki ardisik cagri arasinda gun
        donmez. Mutasyonla olculdu: onbellek tamamen kaldirildiginda
        takim 164/164 YESIL kaldi. Yani test adinin yarisi kanitsizdi.
        Onbellek katmani artik ayri sorulyor (bkz. asagidaki test).
        """
        from core import entitlements
        from services import profile_service

        def _yasak(*a, **kw):
            raise AssertionError("olcum betigi uretimden gun sordu")

        import datetime as _dt

        monkeypatch.setattr(entitlements, "user_local_date", _yasak)
        monkeypatch.setattr(profile_service, "get_profile", _yasak)
        monkeypatch.setattr(ev, "_gun_onbellek", {})
        assert isinstance(ev._olcum_gunu(), _dt.date)

    def test_olcum_gunu_gun_sinirini_bolen_kosuda_degismiyor(
            self, monkeypatch):
        """Onbellek katmaninin KENDISI: saat ilerlerken deger ilerlemez.

        Korudugu hâl olculebilir ve gercek: kosu DAKIKALAR suruyor
        (yuzey basina birkac LLM uretimi) ve gun sinirini ortadan
        bolebilir. Burada saat iki cagri arasinda 23:59:30'dan
        00:00:30'a (Istanbul) ilerletiliyor — onbellek olmasa BaZi ile
        dogum kapisi iki AYRI gunun blogunu alir ve o ayrisma urunun
        degil OLCUMUN artifakti olurdu.

        Sahte saat `now()` cagrisini SAYIYOR, gercek saate bakmiyor:
        aksi hâlde test gunun %99'unda kor olurdu (gerceginde gun
        yalniz gece yarisi doner).
        """
        import datetime as _dt
        import types
        from zoneinfo import ZoneInfo

        from services.notification_service import DEFAULT_TIMEZONE

        anlar = [
            _dt.datetime(2026, 10, 3, 20, 59, 30, tzinfo=_dt.timezone.utc),
            _dt.datetime(2026, 10, 3, 21, 0, 30, tzinfo=_dt.timezone.utc),
        ]
        # Fixture'in GERCEKTEN gun sinirini astigi, kodun kac kez saat
        # sordugundan BAGIMSIZ olarak burada kanitlanir: yoksa test, saat
        # hic ilerlemedigi icin de yesil kalirdi (yanlis guvence).
        yerel = ZoneInfo(DEFAULT_TIMEZONE)
        assert anlar[0].astimezone(yerel).date() == _dt.date(2026, 10, 3)
        assert anlar[1].astimezone(yerel).date() == _dt.date(2026, 10, 4)

        sira = iter(anlar)

        class _Dt(_dt.datetime):
            @classmethod
            def now(cls, tz=None):
                an = next(sira)
                return an.astimezone(tz) if tz else an

        monkeypatch.setattr(ev, "_gun_onbellek", {})
        monkeypatch.setattr(ev, "dt", types.SimpleNamespace(
            datetime=_Dt, timezone=_dt.timezone, date=_dt.date))

        assert ev._olcum_gunu() == ev._olcum_gunu() == _dt.date(2026, 10, 3)


# ---------------------------------------------------------------------------
# PUSH YUZEYI — "kapsam disi" gerekcesi olculdu ve YANLIS cikti
# ---------------------------------------------------------------------------


class TestPushYuzeyiKapsamda:
    """Gunluk bildirim govdesi artik olculuyor.

    Kapsam disi gerekcesi *"bildirim zamanlama/quiet-hours kurulumunu da
    tasimak demek"* diye yaziliydi ve olculdugunde yanlis cikti:
    `daily_push_body(sign, sky, lang, gun)` — burc anahtari, zaten elde
    olan yerelleştirilmiş gokyuzu ve bir gun dizesi. Zamanlama, sessiz
    saatler, cihaz jetonu: hicbiri gerekmiyor. Gerekcesi yanlis olan
    yorum kusurdur (CLAUDE.md §1).
    """

    def test_yuzey_gercekten_olculuyor(self):
        y = ev._yuzeyler()["push-daily"]
        assert y.kapsam == "olculuyor"
        assert y.girdiler is not None
        assert y.uret is not None

    def test_paylasimli_gokyuzu_yuzeyleri_ayni_girdiyi_kullaniyor(self):
        """Burc listesi iki yerde elle tutulmasin.

        Ikisi ayni sinifta (paylasimli gokyuzu) ve ayrismayi olcen bir
        aracta girdinin ayni olmasi, iki yuzeyin kiyaslanabilir olmasinin
        kosulu.
        """
        t = ev._yuzeyler()
        assert t["push-daily"].girdiler is t["horoscope"].girdiler

    def test_push_olgu_olcusu_iddia_etmiyor(self):
        """Gokyuzu on iki burca ayni gelir: girdiye ozel olgu kumesi YOK.

        Olgu cikarici baglanmis olsaydi arac olcmedigi bir seyi
        olcuyormus gibi gosterirdi (olculmeyen soylenmez).
        """
        assert ev._yuzeyler()["push-daily"].olgular is None

    @staticmethod
    def _sahte_govde(monkeypatch, metin):
        from services import notification_service
        monkeypatch.setattr(ev, "_gokyuzu", lambda lang="tr": {})
        monkeypatch.setattr(notification_service, "daily_push_body",
                            lambda sign, sky, lang, gun=None: metin)

    def test_sablona_dusen_satir_yedek_isaretleniyor(self, monkeypatch):
        """Bayrak SABLONDAN turetilir, elle kopyalanmaz.

        `daily_push_body` bayrak dondurmuyor (donusu duz dize), bu yuzden
        kiyas burada kuruluyor. Beklenen metin `prompts`tan okundugu icin
        sablon degistiginde kiyas da degisir — bayatlayamaz.
        """
        from services import prompts as _prompts
        p = _prompts.get("tr")
        gun = ev._olcum_gunu().isoformat()
        sablon = p.PUSH_DAILY_FALLBACK.format(
            sign=p.SIGN_NAMES.get("leo", "leo"),
            date=_prompts.signal_date("tr", gun))
        self._sahte_govde(monkeypatch, sablon)
        assert ev._uret_push("leo", "tr")["fallback"] is True

    def test_model_satiri_yedek_sayilmiyor(self, monkeypatch):
        """Ters yon: her satiri yedek saymak da yalan olurdu."""
        self._sahte_govde(monkeypatch, "Ay Boga'da; bugun somut bir adim.")
        sonuc = ev._uret_push("leo", "tr")
        assert sonuc["fallback"] is False
        assert sonuc["text"].startswith("Ay")


# ---------------------------------------------------------------------------
# SON SES YUMUSAMASI — ayni Turkce olgusu AD eslestirmesinde de var
# ---------------------------------------------------------------------------

#: Turkce'de sozcuk sonundaki sert unsuz, unlu ile baslayan bir ek alinca
#: yumusar. Tablo BETIKTEN okunuyor, burada yeniden yazilmiyor: iki yerde
#: elle tutulsa bekci kendi kopyasini dogrulayip betigin kopyasini
#: gormezdi (bu dosyada bir kez olan hata).
_YUMUSAMA = ev._SON_SES_YUMUSAMASI


def _yumusamis_tamlayan(ad: str) -> str:
    """Adin yumusamis ilgi hâli — modelin gercekten yazacagi bicim.

    Tek ek varyanti (ilgi hâli) yeterli kanit: eslesme EKE hic bakmiyor,
    yalniz govdenin yumusamis yazimina bakiyor. Unlu uyumu yuzunden
    gercek metinde dort varyant birden gorulur; hepsini sormak ayni
    katmani dort kez sormak olurdu.
    """
    return ad[:-1] + _YUMUSAMA[ad[-1]] + "in"


def _yumusayan_adlar() -> list[str]:
    """Olcerin GERCEK tablolarindaki, yumusamaya ugrayan uzun adlar.

    Liste elle yazilmaz: burc / aci / BaZi element ve hayvan adlari
    `prompts`tan okunur, boylece yeni bir ad eklendiginde bekci
    kendiliginden sorar ve bayatlayamaz.

    `_KISA_AD_SINIRI` esigi filtre olarak KULLANILIYOR cunku kisa ad dali
    tam kelime eslesmesi yapiyor: yumusamis yazim ancak ekle birlikte
    goruldugu icin orada ZATEN eslesemez (gerekcesi `_ad_gecti`de).
    """
    p = prompts.get("tr")
    havuz: list[str] = list(p.SIGN_NAMES.values())
    havuz += list(getattr(p, "ASPECT_NAMES", {}).values())
    havuz += list(getattr(p, "BAZI_ELEMENTS", {}).values())
    havuz += list(getattr(p, "BAZI_ANIMALS", {}).values())
    return sorted({a for a in havuz
                   if isinstance(a, str) and a[-1:] in _YUMUSAMA
                   and len(a) >= ev._KISA_AD_SINIRI})


class TestAdYumusamasi:
    """`_ad_gecti`nin UZUN ad dali yumusamis yazimi gormeli.

    ⚠️ Bu kusur bir DOGRULAMA turunda bulundu (2026-10-03) ve degerli
    olan yeri sudur: ayni Turkce olgusu bu dosyada ZATEN kayitliydi —
    `_ek_toleransli_desen` tam bunun icin yazilmis ve docstring'i
    "kural genel" diyordu. Ama genellik yalnizca YAGCILIK listesi
    icindeydi; ad tablolari ayni fonksiyonu hic cagirmiyordu. Yani
    onarilmis bir kusurun ikizi, bir fonksiyon oteside aciktaydi.

    Kayip olculdu, tahmin edilmedi: bes burc adi, iki aci adi, BaZi'de
    `Kopek` ve `Ahsap`, 64 heksagram adinin 17'si. Sapma TEK YONLU —
    hepsi olguyu KAYBETTIRIYOR, yani araci "rapor kendi hesabindan
    konusmuyor" demeye iter. Gurultu gibi gorunmez, hukmu sistematik
    olarak kotuye ceker.
    """

    def test_tablo_betikten_okunuyor(self):
        """Dort sert unsuzun hepsi haritada olmali.

        `k` ile sinirli hal yagcilik listesinde yetiyordu (orada baska
        uye yoktu); ad tablolarinda ucu birden geciyor.
        """
        assert _YUMUSAMA == {"k": "ğ", "p": "b", "t": "d", "ç": "c"}

    def test_olcerin_kendi_tablolarinda_yumusayan_ad_var(self):
        """Bekcinin on kosulu: havuz bosalirsa test sessizce ise yaramaz.

        Esik 5: bes burc adi (Yengec, Basak, Akrep, Oglak, Balik) + iki
        aci adi (Altmislik, Beslik) + Kopek + Ahsap.
        """
        adlar = _yumusayan_adlar()
        assert len(adlar) >= 5, adlar
        assert "Başak" in adlar and "Akrep" in adlar and "Yengeç" in adlar

    @pytest.mark.parametrize("ad", _yumusayan_adlar())
    def test_yumusamis_bicim_yakalaniyor(self, ad):
        bicim = _yumusamis_tamlayan(ad)
        assert ev._ad_gecti(N(f"Bu dönemde {bicim} vurgusu var."), ad), bicim

    @pytest.mark.parametrize("ad, metin", [
        # Yumusamamis bicimler KACMAMALI: cozum bir yonu onarip otekini
        # bozmamali.
        ("Başak", "Merkür Başak burcunda."),
        ("Başak", "Merkür Başakta duruyor."),
        ("Balık", "Venüs Balık burcunda."),
        ("Akrep", "Satürn Akrep burcunda."),
    ])
    def test_yumusamamis_bicim_hala_yakalaniyor(self, ad, metin):
        assert ev._ad_gecti(N(metin), ad)

    @pytest.mark.parametrize("ad, metin", [
        # Yumusamis desen kelime ORTASINA da kacmamali — uzun ad dalinin
        # kendi bekcisiyle (TestUzunAdKelimeOrtasi) ayni disiplin.
        ("Balık", "Bu kabalık değil, sınır koymak."),
        ("Balık", "Bu kabalığın sebebi başka."),
        ("Başak", "Başarının bedeli var."),
        ("Akrep", "Akreditasyon süreci uzadı."),
        ("Oğlak", "Oğlan çocuğu gibi davranıyor."),
    ])
    def test_yumusamis_desen_yanlis_pozitif_uretmiyor(self, ad, metin):
        assert not ev._ad_gecti(N(metin), ad)

    def test_olgu_cikarici_yumusamis_metinde_olgu_buluyor(self):
        """Uctan uca: kusur burada ZARAR veriyordu.

        `_ad_gecti` tek basina bir sayi degil; `_astro_olgular` gezegen
        VE burcu birlikte istiyor, yani burc adinin kacmasi yerlesimi
        TAMAMEN dusuruyordu.
        """
        facts = {"placements": [{"planet": "Mercury", "sign": "virgo",
                                 "house": 3}]}
        assert ev._astro_olgular(
            "Merkür Başağın üçüncü derecesinde, 3. evde.",
            facts) == {"Mercury-virgo", "Mercury-ev3"}

    def test_yagcilik_sinifi_hala_calisiyor(self):
        """Paylasilan fonksiyon genisletildi: eski cagiran bozulmamali."""
        assert ev._yagcilik_bulgulari("Bu bir öğrenme yolculuğu.") == [
            "öğrenme yolculuğu"]
        assert ev._yagcilik_bulgulari(
            "Farkındalığın alanı genişliyor.") == ["farkındalığın alanı"]


# ---------------------------------------------------------------------------
# KONSOL AKIS KIPI — cokme UCRETLI uretimlerden SONRA gelir
# ---------------------------------------------------------------------------


def _modul_duzeyi_reconfigure() -> list[tuple[str, dict]]:
    """Betikte MODUL DUZEYINDE yapilan `reconfigure` cagrilarini bulur.

    `ast` ile: bu dosyanin ve betigin yorumlari `reconfigure`dan ve
    `errors="replace"`dan bolca soz ediyor, duz metin aramasi kendi
    aciklamasina takilirdi (CLAUDE.md: yoklugu arayan bekci onu anlatan
    yorumu gormemeli).

    Donen: (uzerinde cagrildigi akis adi, anahtar kelimeler) ikilileri.
    Akis adi dongu degiskeninden geliyorsa dongunun GEZDIGI adlar
    yazilir — betik iki akisi tek dongude geziyor ve o bicim degisirse
    bekci yine dogruyu soylemeli.
    """
    kaynak = io.open(_BETIK, encoding="utf-8").read()
    agac = ast.parse(kaynak)
    bulunan: list[tuple[str, dict]] = []

    def _akis_adlari(dugum: ast.AST) -> list[str]:
        """`sys.stdout` / `sys.stderr` niteliklerini toplar."""
        return [n.attr for n in ast.walk(dugum)
                if isinstance(n, ast.Attribute)
                and isinstance(n.value, ast.Name) and n.value.id == "sys"]

    for ust in agac.body:
        hedefler = _akis_adlari(ust) if isinstance(ust, ast.For) else []
        for n in ast.walk(ust):
            if not (isinstance(n, ast.Call)
                    and isinstance(n.func, ast.Attribute)
                    and n.func.attr == "reconfigure"):
                continue
            kw = {k.arg: getattr(k.value, "value", None) for k in n.keywords}
            for ad in (hedefler or _akis_adlari(n.func)):
                bulunan.append((ad, kw))
    return bulunan


class TestKonsolAkisKipi:
    """cp1254 konsolunda yazdirma programi DUSURMEMELI.

    ⚠️ Bu katman KOR cikti (dogrulama turu, 2026-10-03): kayit "zaten
    kapali" diye isaretlenmisti, kod gercekten yerindeydi — ama hicbir
    test onu tutmuyordu. Minimal mutasyonla olculdu: `reconfigure`
    satiri silindiginde takim 164/164 YESIL kaldi. Kaza ile guvenli olan
    sey guvence degildir (ayni ders `TestLlmPini`de yazili).

    Bedeli ASIMETRIK oldugu icin onemli: cokme UCRETLI uretimlerden
    SONRA gelir, yani jeton/kota harcanmis olup olcum kaybedilir.

    ⚠️ Risk CJK ile sinirli DEGIL ve bu olculdu: `_rapor_modu` ile
    `_hafiza_modu` uyari satirlarini "⚠️" ile basiyor, `--help` ise
    modul docstring'ini basiyor (o da tasiyor). Yani dar bir "BaZi
    sutunlari" gerekcesi yanlis olurdu — katman her kosuda yuk tasiyor.
    """

    #: cp1254'un kodlayamadigi karakterler. "⚠" betigin BUGUN GERCEKTEN
    #: yazdirdigi karakter (asagidaki `test_gerekce_HALA_gecerli...` onu
    #: kaynaktan dogruluyor). CJK ikisi bugun YAZDIRILMIYOR ve bu burada
    #: durmalarinin sebebi: BaZi prompt'u modele CJK sutun etiketi
    #: VERIYOR ("庚午 (Geng Wu)", bkz. `_bazi_olgular`), yani yerel bir
    #: etiketi oldugu gibi basan bir degisiklik onlari cikti yoluna geri
    #: koyar. Sinif testi sinif olarak sorulmali — tek yazima baglanan
    #: capa kor olur (CLAUDE.md §5).
    SORUNLU = ("⚠", "庚", "蒙")

    @pytest.mark.parametrize("karakter", SORUNLU)
    def test_cp1254_strict_bu_karakterlerde_patliyor(self, karakter):
        """Onculun kendisi sinanir: risk VAR mi.

        Bu test olmasa sonraki testler bos bir seyi kanitlardi — "replace
        kipi calisiyor" cumlesi, strict kipin hic patlamadigi bir
        dunyada da dogrudur.
        """
        akis = io.TextIOWrapper(io.BytesIO(), encoding="cp1254",
                                errors="strict")
        with pytest.raises(UnicodeEncodeError):
            akis.write(karakter)
            akis.flush()

    @pytest.mark.parametrize("karakter", SORUNLU)
    def test_replace_kipi_ayni_karakteri_gecirir(self, karakter):
        akis = io.TextIOWrapper(io.BytesIO(), encoding="cp1254",
                                errors="strict")
        akis.reconfigure(errors="replace")
        akis.write(f"GOKYUZU {karakter} satiri")
        akis.flush()
        assert akis.buffer.getvalue()

    def test_betik_iki_akisi_da_replace_kipine_cekiyor(self):
        """Hem `stdout` hem `stderr`: biri atlanirsa teshis yarim kalir.

        `_rapor_modu` hukmu `stdout`a, kapsam disi uyarisi `stderr`e
        basiyor; yalniz birini gevsetmek cokmeyi oteki akisa tasirdi.
        """
        cagrilar = _modul_duzeyi_reconfigure()
        kipler = {ad: kw.get("errors") for ad, kw in cagrilar}
        assert kipler.get("stdout") == "replace", cagrilar
        assert kipler.get("stderr") == "replace", cagrilar

    def test_kodlama_DEGISTIRILMIYOR(self):
        """Yalniz hata kipi gevsetilir.

        `encoding="utf-8"` demek cp1254 konsolunda Turkce'yi mojibake
        yapmaktir (CLAUDE.md §5: `GÖKYÜZÜ` -> `GÃ–KYÃœZÃœ`). Yani bu
        satirin DAR olmasi kasitli ve gerekcesi olculmus.
        """
        for ad, kw in _modul_duzeyi_reconfigure():
            assert "encoding" not in kw, (ad, kw)

    def test_gerekce_HALA_gecerli_yazdirilan_metinde(self):
        """Katmanin sebebi olculebilir kalmali.

        Betigin yazdirdigi dize sabitleri taranir: en az biri cp1254'te
        kodlanamayan bir karakter tasimali. Tasimiyorsa gerekce
        BAYATLAMIS demektir ve o zaman yorumun kendisi kusurdur — bu
        depoda bayat gerekce iki kez kusur sayildi.

        Tarama `ast` ile ve yalniz `print` ARGUMANLARINDA: yorumlar ve
        docstring'ler cagri argumani degil.
        """
        kaynak = io.open(_BETIK, encoding="utf-8").read()
        tasiyan = []
        for n in ast.walk(ast.parse(kaynak)):
            if not (isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                    and n.func.id == "print"):
                continue
            for parca in ast.walk(n):
                if not (isinstance(parca, ast.Constant)
                        and isinstance(parca.value, str)):
                    continue
                try:
                    parca.value.encode("cp1254")
                except UnicodeEncodeError:
                    tasiyan.append(parca.value[:40])
        assert tasiyan, ("Yazdirilan hicbir dize cp1254 disi karakter "
                         "tasimiyor: akis kipi gerekcesi yeniden olculmeli.")

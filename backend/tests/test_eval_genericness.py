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

from services import gemini_service, prompt_composer  # noqa: E402

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
            y, uret=lambda g, l: "Her haritaya aynı metin.",
            olgular=None,
            girdiler=lambda n: [("x", {}), ("y", {})])
        assert ev._rapor_modu(sahte, 2) == 1

    def test_rapor_modu_farkli_metinde_yesil(self, monkeypatch):
        monkeypatch.setattr(ev, "_vektorle", lambda m: None)
        monkeypatch.setattr(ev, "_onbellegi_atla", lambda: None)
        sayac = {"n": 0}

        def uret(g, l):
            sayac["n"] += 1
            return f"Haritaya özel metin {sayac['n']}."

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
            return f"{metin} (girdi {sayac['n']})"

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

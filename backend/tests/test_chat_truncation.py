"""S-turu: sohbet yaniti KESILMIS halde kullaniciya ulasmamali.

## Bu testin varlik sebebi

Cihaz bulgusu: "sohbet bazen yarida kesiliyor, baslamadan bitebiliyor."
Ayni soru uretimdeki ayarla 6 kez soruldu, **3'u kesildi**: dusunme 300
token'in 284'unu yiyip geriye 10-12 token birakiyor ve cumle kelime
ortasinda bitiyordu ("Gokyuzunde bugun zih").

Iki kusur ust uste binmisti:
  1. `thinking_budget: 0` modelde artik uygulanmiyordu (takma ad kaydi),
  2. kod `finish_reason`'a HIC bakmiyordu — kesik metin basari sayilip
     oldugu gibi donuyordu.

Ikincisi asil olan: birincisi tek basina olsa bile kod kesilmeyi gorseydi
kullanici yarim cumle gormezdi. Bu yuzden test MODELE degil KODUN
DAVRANISINA bakiyor — model yarin yine kayabilir.

Calistirma:  .venv\\Scripts\\python.exe -m pytest tests/test_chat_truncation.py -q
"""
from __future__ import annotations

import pytest

from services import gemini_service as gs


# --------------------------------------------------------------------------
# Sahte SDK yaniti
# --------------------------------------------------------------------------

class _Aday:
    def __init__(self, finish_reason):
        self.finish_reason = finish_reason


class _Yanit:
    """`response.text` + `candidates[0].finish_reason` tasiyan asgari yanit."""

    def __init__(self, text, finish_reason="STOP"):
        self._text = text
        self.candidates = [_Aday(finish_reason)]

    @property
    def text(self):
        return self._text


class _PatlayanYanit(_Yanit):
    """Parca yokken `response.text` istisna atan SDK surumleri icin."""

    @property
    def text(self):
        raise ValueError("no parts in candidate")


class _SahteModeller:
    """Sirayla verilen yanitlari dondurur; her cagriyi kaydeder."""

    def __init__(self, yanitlar):
        self._yanitlar = list(yanitlar)
        self.cagrilar: list[dict] = []

    def generate_content(self, *, model, contents, config):
        self.cagrilar.append(config)
        if not self._yanitlar:
            raise AssertionError("beklenenden fazla cagri yapildi")
        sonuc = self._yanitlar.pop(0)
        if isinstance(sonuc, Exception):
            raise sonuc
        return sonuc


class _SahteIstemci:
    def __init__(self, yanitlar):
        self.models = _SahteModeller(yanitlar)


@pytest.fixture(autouse=True)
def temiz_varyant():
    """Varyant tercihi testler arasinda sizmamali."""
    onceki = gs._variant_state["preferred"]
    gs._variant_state["preferred"] = 0
    yield
    gs._variant_state["preferred"] = onceki


def _istemciyi_degistir(monkeypatch, yanitlar):
    istemci = _SahteIstemci(yanitlar)
    monkeypatch.setattr(gs, "_get_client", lambda: istemci)
    return istemci


# --------------------------------------------------------------------------
# 1. Kesik metin kullaniciya ULASMAZ
# --------------------------------------------------------------------------

class TestKesikMetinDonmez:
    KESIK = "Gökyüzünde bugün zih"

    def test_tek_varyant_keserse_digeri_denenir(self, monkeypatch):
        istemci = _istemciyi_degistir(monkeypatch, [
            _Yanit(self.KESIK, "FinishReason.MAX_TOKENS"),
            _Yanit("Bugün Ay senin duygusal eksenine dokunuyor.", "STOP"),
        ])
        sonuc = gs.chat([], "Bugün nasıl bir gün?", lang="tr")
        assert sonuc == "Bugün Ay senin duygusal eksenine dokunuyor."
        assert len(istemci.models.cagrilar) == 2

    def test_hepsi_keserse_YARIM_CUMLE_yerine_None(self, monkeypatch):
        """Yarim cumle gostermek, 'su an yanit uretemedim' demekten kotu."""
        _istemciyi_degistir(monkeypatch, [
            _Yanit(self.KESIK, "FinishReason.MAX_TOKENS"),
            _Yanit(self.KESIK, "FinishReason.MAX_TOKENS"),
        ])
        assert gs.chat([], "Bugün nasıl bir gün?", lang="tr") is None

    def test_kesik_metin_ASLA_donmez(self, monkeypatch):
        """Kusurun ta kendisi: kesik metin basari sayiliyordu."""
        _istemciyi_degistir(monkeypatch, [
            _Yanit(self.KESIK, "FinishReason.MAX_TOKENS"),
            _Yanit(self.KESIK, "FinishReason.MAX_TOKENS"),
        ])
        assert gs.chat([], "x", lang="tr") != self.KESIK

    def test_kesilme_LOGLANIR(self, monkeypatch, caplog):
        """Sessiz kalmak, bir ayarin artik tutmadigini gizler."""
        _istemciyi_degistir(monkeypatch, [
            _Yanit(self.KESIK, "FinishReason.MAX_TOKENS"),
            _Yanit("Tam yanıt.", "STOP"),
        ])
        with caplog.at_level("WARNING"):
            gs.chat([], "x", lang="tr")
        assert any("KESİLDİ" in r.message or "KESILDI" in r.message
                   for r in caplog.records)


# --------------------------------------------------------------------------
# 2. Saglam yollar bozulmadi
# --------------------------------------------------------------------------

class TestSaglamYollar:
    def test_tam_yanit_ilk_varyanttan_doner(self, monkeypatch):
        istemci = _istemciyi_degistir(monkeypatch, [_Yanit("Tam yanıt.", "STOP")])
        assert gs.chat([], "x", lang="tr") == "Tam yanıt."
        assert len(istemci.models.cagrilar) == 1, "gereksiz ikinci cagri"

    def test_bos_metin_sonraki_varyanti_dener(self, monkeypatch):
        _istemciyi_degistir(monkeypatch, [
            _Yanit("", "STOP"),
            _Yanit("İkinci varyant.", "STOP"),
        ])
        assert gs.chat([], "x", lang="tr") == "İkinci varyant."

    def test_400_hatasi_sonraki_varyanti_dener(self, monkeypatch):
        """`thinking_level: minimal` bu modelde 400 veriyordu."""
        _istemciyi_degistir(monkeypatch, [
            RuntimeError("400 INVALID_ARGUMENT"),
            _Yanit("İkinci varyant.", "STOP"),
        ])
        assert gs.chat([], "x", lang="tr") == "İkinci varyant."

    def test_text_istisna_atarsa_cokmez(self, monkeypatch):
        _istemciyi_degistir(monkeypatch, [
            _PatlayanYanit(None, "STOP"),
            _Yanit("İkinci varyant.", "STOP"),
        ])
        assert gs.chat([], "x", lang="tr") == "İkinci varyant."


# --------------------------------------------------------------------------
# 3. Butce ve varyant listesi
# --------------------------------------------------------------------------

class TestButce:
    def test_tavan_dusunmeye_yer_birakir(self):
        """Tavan dusunme + gorunur metni BIRDEN tasimali.

        ## Esik 1000'den 500'e indi (48-turu) ve sebep MODEL PINI

        Eski gerekce: "300'du ve dusunme 284'unu yiyordu." O gun dogruydu
        ama BUGUN GECERSIZ, cunku o olcum `gemini-flash-latest` TAKMA ADI
        uzerinde yapildi: orada `thinking_budget: 0` uygulanmiyordu ve 6
        cagrinin 3'unde 190-286 token dusunmeye gidiyordu. Tavan onun icin
        1000+ isteniyordu.

        Model o turda sabitlendi ve `core/config.py`'de olculen davranis
        bunun TERSI: `gemini-3.5-flash` 4 cagrinin 0'inda kesildi, 0 token
        dusundu. Yani dusunme sizintisini kapatan sey tavan degil PINDI.

        Yeni esik ayni mantikla, guncel olcumle: pin disina cikilirsa
        olculen en kotu sizinti 286 token ve promptun yeni ust siniri 8
        cumle (~195 token) → 481. 500 bunun hemen ustunde, yani iddia
        hala "dusunmeye yer birakir" diyor; yalnizca bayat gerekceyle
        degil olculen gerekceyle.
        """
        assert gs.CHAT_MAX_OUTPUT_TOKENS >= 500

    def test_her_varyant_tavan_tasir(self):
        """Esik 500 (gerekce yukarida). Kurtarma varyantinin 2048'lik genis
        butcesi ayrica `test_chat_prompt_disiplini.py`'de olculuyor."""
        for v in gs._CHAT_CONFIG_VARIANTS:
            assert v.get("max_output_tokens", 0) >= 500

    def test_desteklenmeyen_thinking_level_varyanti_YOK(self):
        """Her soguk baslangicta bir cagriyi bosa harciyordu (400)."""
        for v in gs._CHAT_CONFIG_VARIANTS:
            tc = v.get("thinking_config") or {}
            assert "thinking_level" not in tc

    def test_model_takma_ad_DEGIL(self):
        """`-latest` takma adi bir gecede davranis degistirdi ve sohbetin
        yarisi bozuldu; surum bilincli bir karar olmali."""
        from core import config
        assert not config.GEMINI_MODEL.endswith("-latest")


# --------------------------------------------------------------------------
# 4. Rapor yolu (bedeli 5 jeton)
# --------------------------------------------------------------------------

class TestRaporYolu:
    def test_kesik_rapor_genis_butceyle_yeniden_denenir(self, monkeypatch):
        istemci = _istemciyi_degistir(monkeypatch, [
            _Yanit("Yarım rapo", "FinishReason.MAX_TOKENS"),
            _Yanit("Tam rapor metni.", "STOP"),
        ])
        assert gs.generate("prompt", lang="tr") == "Tam rapor metni."
        # Ikinci cagri acik bir tavanla yapilmali.
        assert istemci.models.cagrilar[1].get("max_output_tokens") == \
            gs._REPORT_RETRY_TOKENS

    def test_ikinci_denemede_de_keserse_None(self, monkeypatch):
        """None -> `_cached_generate` jetonu IADE eder; kullanici
        almadigi rapora odemez."""
        _istemciyi_degistir(monkeypatch, [
            _Yanit("Yarım rapo", "FinishReason.MAX_TOKENS"),
            _Yanit("Yine yarım rapo", "FinishReason.MAX_TOKENS"),
        ])
        assert gs.generate("prompt", lang="tr") is None

    def test_tam_rapor_tek_cagriyla_doner(self, monkeypatch):
        istemci = _istemciyi_degistir(monkeypatch, [_Yanit("Tam rapor.", "STOP")])
        assert gs.generate("prompt", lang="tr") == "Tam rapor."
        assert len(istemci.models.cagrilar) == 1

    def test_dusunme_kapali_ve_ilk_deneme_tavanli(self, monkeypatch):
        """KA3: S-turu'nun sohbet dersi (`thinking_budget: 0` + acik tavan)
        `generate()`'e YARIM uygulanmisti — dusunme acikti ve ilk deneme
        tavansizdi; bos/kesik cikti bu yuzden sohbetten daha olasiydi."""
        istemci = _istemciyi_degistir(monkeypatch, [_Yanit("Tam.", "STOP")])
        gs.generate("prompt", lang="tr")
        cagri = istemci.models.cagrilar[0]
        assert cagri.get("thinking_config") == {"thinking_budget": 0}
        assert cagri.get("max_output_tokens") == 2048

"""Faz 4 testleri: olgu çıkarımı ve hafızanın prompt'a enjeksiyonu.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_memory.py -q
"""
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys

import pytest

from services import memory_extractor, memory_service, prompt_composer


# --------------------------------------------------------------------------
# Çıkarım tetikleme koşulları (maliyet kontrolü)
# --------------------------------------------------------------------------

def test_kisa_konusmada_cikarim_yapilmaz():
    """İlk "merhaba" turundan olgu çıkarmaya çalışmak boşa LLM çağrısıdır."""
    assert memory_extractor.should_extract([]) is False


def test_ikinci_kullanici_mesajinda_cikarim_yapilir():
    """Eşik 3 → 2 (KA9): eskiden her yeni konunun ilk İKİ mesajı hiç
    işlenmiyordu ve günde 1 kota ile çoğu kullanıcının hafızası boş
    kalıyordu — "beni tanımıyor" şikâyetinin ölçülen parçalarından biri."""
    assert memory_extractor.should_extract(
        [{"sender": "USER", "text": "selam"}]) is True
    gecmis = [
        {"sender": "USER", "text": "selam"},
        {"sender": "AI", "text": "merhaba"},
        {"sender": "USER", "text": "işimden ayrılmayı düşünüyorum"},
    ]
    assert memory_extractor.should_extract(gecmis) is True


def test_ai_turlari_sayilmaz():
    gecmis = [{"sender": "AI", "text": f"cevap {i}"} for i in range(10)]
    assert memory_extractor.should_extract(gecmis) is False


def test_kota_dolduysa_llm_e_gidilmez(monkeypatch):
    """Günlük çıkarım hakkı bitince ek LLM çağrısı yapılmamalı."""
    gecmis = [{"sender": "USER", "text": f"mesaj {i}"} for i in range(4)]
    monkeypatch.setattr(memory_extractor.entitlements, "consume_quota",
                        lambda uid, key, limit: False)
    monkeypatch.setattr(memory_extractor.gemini_service, "extract_json",
                        lambda *a, **k: pytest.fail("kota dolarken LLM çağrılmamalı"))

    assert memory_extractor.extract_and_store("u", gecmis, "son mesaj") is None


def test_checkin_cevabi_tek_turda_islenir(monkeypatch):
    """KA9: akşam sorusuna verilen TEK mesajlık cevap tur eşiğini atlar ve
    kotayı +1 kullanır — aksi hâlde ürünün kendi sorduğu sorunun cevabı
    hafızaya hiç düşmezdi (döngünün bütün amacı)."""
    kotalar = []

    def sahte_kota(uid, key, limit):
        kotalar.append(limit)
        return True

    monkeypatch.setattr(memory_extractor.entitlements, "consume_quota",
                        sahte_kota)
    monkeypatch.setattr(
        memory_extractor.gemini_service, "extract_json",
        lambda *a, **k: json.dumps({"facts": []}))
    monkeypatch.setattr(memory_extractor.memory_service, "upsert_facts",
                        lambda uid, facts: {"facts": []})
    sonuc = memory_extractor.extract_and_store(
        "u", [], "Kötü geçti, işten kötü haber aldım", source="checkin")
    assert sonuc is not None
    assert kotalar == [memory_extractor.DAILY_EXTRACTIONS + 1]
    # Normal yol tek mesajda hiç LLM'e gitmez (eşik).
    monkeypatch.setattr(
        memory_extractor.gemini_service, "extract_json",
        lambda *a, **k: pytest.fail("eşik altında LLM çağrılmamalı"))
    assert memory_extractor.extract_and_store("u", [], "selam") is None


# --------------------------------------------------------------------------
# Çıkarım ve şemaya oturtma
# --------------------------------------------------------------------------

def _cikarima_izin_ver(monkeypatch):
    monkeypatch.setattr(memory_extractor.entitlements, "consume_quota",
                        lambda uid, key, limit: True)


def test_cikarilan_olgular_hafizaya_yazilir(monkeypatch):
    _cikarima_izin_ver(monkeypatch)
    gecmis = [{"sender": "USER", "text": f"m{i}"} for i in range(4)]

    yanit = json.dumps({
        "facts": [
            {"category": "work", "key": "work.transition",
             "value": "yeni bir işe geçmeyi tartıyor", "confidence": 0.9},
        ],
        "mood": "kaygılı",
    })
    monkeypatch.setattr(memory_extractor.gemini_service, "extract_json",
                        lambda *a, **k: yanit)

    yazilan: list = []
    monkeypatch.setattr(memory_service, "upsert_facts",
                        lambda uid, facts: yazilan.append(facts) or {"facts": facts})
    ruh: list = []
    # S-turu: imza `intensity`/`needs` ile genisledi. Taklit ESNEK tutuluyor
    # (**kw) — cikarici hatayi yutuyor ve imza uyusmazligi sessizce "ruh hali
    # hic yazilmadi"a donusuyor; testin bunu bir sonraki genislemede yeniden
    # yasamasi gereksiz.
    monkeypatch.setattr(memory_service, "record_mood",
                        lambda uid, mood, **kw: ruh.append((mood, kw)))

    memory_extractor.extract_and_store("u", gecmis, "son mesaj")

    assert yazilan and yazilan[0][0]["key"] == "work.transition"
    assert [m for m, _ in ruh] == ["kaygılı"]


def test_yogunluk_ve_ihtiyac_hafizaya_akar(monkeypatch):
    """S-turu: tek kelimelik ruh hali yetmiyordu — "biraz kaygiliyim" ile
    "dagilmak uzereyim" ayni satira dusuyor ve model ikisine de ayni tonda
    cevap veriyordu."""
    _cikarima_izin_ver(monkeypatch)
    gecmis = [{"sender": "USER", "text": f"m{i}"} for i in range(4)]
    monkeypatch.setattr(
        memory_extractor.gemini_service, "extract_json",
        lambda *a, **k: json.dumps({
            "facts": [], "mood": "tükenmiş",
            "intensity": "high", "needs": "understanding"}))

    kayit: list = []
    monkeypatch.setattr(memory_service, "upsert_facts",
                        lambda uid, facts: {"facts": facts})
    monkeypatch.setattr(memory_service, "record_mood",
                        lambda uid, mood, **kw: kayit.append((mood, kw)))

    memory_extractor.extract_and_store("u", gecmis, "son mesaj")

    assert kayit, "ruh hali hic yazilmadi"
    mood, kw = kayit[0]
    assert mood == "tükenmiş"
    assert kw.get("intensity") == "high"
    assert kw.get("needs") == "understanding"


def test_uydurma_yogunluk_semadan_gecmez():
    """Model tanimsiz bir etiket uydurursa kayda GIRMEMELI."""
    assert "extreme" not in memory_service.INTENSITIES
    assert "vibes" not in memory_service.NEEDS


def test_hassasiyet_kategorisi_var():
    """"Bunu konusmak istemiyorum" bir kez soylenir ve kalici olmali."""
    assert "sensitivity" in memory_service.CATEGORIES


def test_bozuk_json_istegi_dusurmez(monkeypatch):
    """Çıkarım en iyi çaba bir zenginleştirmedir; hata sohbeti etkilemez."""
    _cikarima_izin_ver(monkeypatch)
    gecmis = [{"sender": "USER", "text": f"m{i}"} for i in range(4)]
    monkeypatch.setattr(memory_extractor.gemini_service, "extract_json",
                        lambda *a, **k: "{bu json degil")

    assert memory_extractor.extract_and_store("u", gecmis, "x") is None


def test_saglik_kategorisi_sematik_olarak_reddedilir():
    """Sağlık verisi hiç tutulmuyor; model yine de gönderirse şema atar."""
    assert "health" not in memory_service.CATEGORIES
    assert memory_service._normalize_fact(
        {"category": "health", "value": "ilaç kullanıyor"}) is None


def test_konusma_metni_son_mesaji_icerir():
    gecmis = [{"sender": "USER", "text": "ilk"}, {"sender": "AI", "text": "yanit"}]
    metin = memory_extractor._conversation_text(gecmis, "son soru")
    assert "Kullanıcı: ilk" in metin
    assert "Rytho: yanit" in metin
    assert metin.strip().endswith("Kullanıcı: son soru")


# --------------------------------------------------------------------------
# Prompt'a enjeksiyon
# --------------------------------------------------------------------------

def test_hafiza_yoksa_mesaj_degismez():
    assert prompt_composer.compose_chat_message("selam", [], memory="") == "selam"


def test_hafiza_fisilti_olarak_eklenir():
    sonuc = prompt_composer.compose_chat_message(
        "bugün nasıl geçer", [], memory="- (work) yeni işe geçmeyi tartıyor")

    assert "yeni işe geçmeyi tartıyor" in sonuc
    assert "KULLANICININ MESAJI: bugün nasıl geçer" in sonuc
    # Modele hafızayı ilan etmemesi söylenmeli; aksi halde kullanıcıya
    # "hakkında tuttuğum notlar" okumak gibi olur.
    assert "ilan ETME" in sonuc or "ilan etme" in sonuc.lower()


def test_hafiza_ve_pasajlar_birlikte_eklenir():
    sonuc = prompt_composer.compose_chat_message(
        "merkür retrosu ne yapar",
        [{"text": "Merkür retrosu iletişimde yavaşlama getirir."}],
        memory="- (work) yeni işe geçmeyi tartıyor",
    )
    assert "ARKA PLAN FISILTISI" in sonuc
    assert "HATIRLADIKLARIN" in sonuc
    assert sonuc.rstrip().endswith("KULLANICININ MESAJI: merkür retrosu ne yapar")


def test_hafiza_celisirse_son_soylenen_gecerli():
    """Hafıza eskiyebilir; model kullanıcının son sözünü esas almalı."""
    sonuc = prompt_composer.compose_chat_message(
        "artık o işte değilim", [], memory="- (work) X şirketinde çalışıyor")
    assert "SON söylediği" in sonuc


def test_butce_sigmayan_parcayi_atlar_sonrakini_alir(monkeypatch):
    """KA9: eski döngü sığmayan İLK parçada DURUYORDU — olgular bütçeyi
    doldurunca ruh hali seyri, günlük ve ton tercihi tamamen düşüyordu.
    Artık sığmayan atlanır, sonraki kısa parçalar yine girer."""
    monkeypatch.setattr(memory_service, "get_memory", lambda uid: {
        "facts": [{"category": "work", "value": "k" * 500,
                   "confidence": 0.9},
                  {"category": "goal", "value": "kısa hedef",
                   "confidence": 0.5}],
        "moodTrail": [{"date": "2026-08-23", "mood": "yorgun",
                       "intensity": "high"}],
        "diary": [],
        "toneHint": "nazik",
    })
    sonuc = memory_service.memory_context("u", max_chars=200)
    # 500 karakterlik olgu sığmaz ve ATLANIR; kısa olgu, ruh hali ve ton
    # yine de girer — eski davranışta üçü de kaybolurdu.
    assert "kısa hedef" in sonuc
    assert "yorgun(high)" in sonuc
    assert "nazik" in sonuc


def test_cevre_fisiltisi_eklenir():
    """KA6: çevre yuvası — model listeyi bilir ama sayıp dökmez."""
    sonuc = prompt_composer.compose_chat_message(
        "bugün nasıl geçer", [], circle="- eşin: Güneş Terazi")
    assert "ÇEVRESİ" in sonuc
    assert "eşin: Güneş Terazi" in sonuc
    assert "sayma" in sonuc  # sayıp dökme yasağı etikette


# --------------------------------------------------------------------------
# Harita ve gökyüzü enjeksiyonu
# --------------------------------------------------------------------------

def test_harita_ozeti_turetilmis_alanlari_alir():
    from services.profile_service import chart_summary

    ozet = chart_summary({
        "sunSign": "Kova ♒", "moonSign": "Aslan ♌", "ascendant": "Terazi ♎",
        "mizac": "Demevi", "wuXingElement": "Ateş",
    })
    assert "Kova" in ozet and "Aslan" in ozet and "Terazi" in ozet
    assert "Demevi" in ozet and "Ateş" in ozet


def test_harita_ozetine_ham_dogum_verisi_girmez():
    """Modelin doğum tarihini/saatini/şehrini bilmesine gerek yok."""
    from services.profile_service import chart_summary

    ozet = chart_summary({
        "sunSign": "Kova", "birthDate": "1985-02-03",
        "birthTime": "04:15", "birthCity": "Bursa",
    })
    for hassas in ("1985-02-03", "04:15", "Bursa"):
        assert hassas not in ozet, f"ham doğum verisi sızdı: {hassas}"


def test_bos_profil_bos_ozet():
    from services.profile_service import chart_summary
    assert chart_summary(None) == ""
    assert chart_summary({}) == ""


def test_harita_sohbet_baglamina_eklenir():
    sonuc = prompt_composer.compose_chat_message(
        "bugün nasılım", [], chart="- Güneş: Kova, Ay: Aslan")

    assert "KULLANICININ HARİTASI" in sonuc
    assert "Kova" in sonuc
    # Modele konum uydurmaması söylenmeli
    assert "uydurma" in sonuc


def test_gokyuzu_sohbet_baglamina_eklenir():
    sonuc = prompt_composer.compose_chat_message(
        "ne var ne yok", [], sky="- Ay evresi: Dolunay")
    assert "BUGÜNÜN GERÇEK GÖKYÜZÜ" in sonuc
    assert "Dolunay" in sonuc


def test_persona_verilmeyen_konumu_uydurmayi_yasaklar():
    from services import gemini_service
    assert "uydurma" in gemini_service.CHAT_SYSTEM_INSTRUCTION


def test_bos_hafiza_bloku_baslik_yazmaz():
    """Boş bir "kullanıcı hakkında" başlığı modeli uydurmaya davet eder."""
    from services.report_service import _memory_block
    assert _memory_block("") == ""
    assert _memory_block("   ") == ""
    assert "ÖNCEDEN BİLDİKLERİN" in _memory_block("- (goal) maraton koşmak istiyor")


# --------------------------------------------------------------------------
# Günlük (R2-G1)
# --------------------------------------------------------------------------

def _gunluk_deposu(monkeypatch):
    """Hafiza depolamasini bellek-ici sahteyle degistirir (Firestore yok)."""
    depo = {"version": 1, "facts": [], "moodTrail": [],
            "toneHint": None, "diary": []}

    def oku(uid):
        return {k: (list(v) if isinstance(v, list) else v)
                for k, v in depo.items()}

    def yaz(uid, memory):
        depo.update(memory)

    monkeypatch.setattr(memory_service, "get_memory", oku)
    monkeypatch.setattr(memory_service, "_write", yaz)
    return depo


def test_gunluk_girisi_eklenir_ve_kimlik_tasir(monkeypatch):
    _gunluk_deposu(monkeypatch)
    giris = memory_service.add_diary_entry("u", "Bugun patronumla tartistim",
                                           theme="career")
    assert giris is not None
    assert giris["id"].startswith("d")
    assert giris["theme"] == "career"
    assert memory_service.get_diary("u")[0]["text"].startswith("Bugun")


def test_gunluk_bos_metin_ve_uydurma_tema_reddedilir(monkeypatch):
    _gunluk_deposu(monkeypatch)
    assert memory_service.add_diary_entry("u", "   ") is None
    assert memory_service.add_diary_entry("u", "x", theme="saglik") is None


def test_gunluk_metni_kirpilir_ve_sinir_asilmaz(monkeypatch):
    depo = _gunluk_deposu(monkeypatch)
    giris = memory_service.add_diary_entry("u", "a" * 500)
    assert len(giris["text"]) == memory_service.MAX_DIARY_CHARS
    for i in range(memory_service.MAX_DIARY_ENTRIES + 5):
        memory_service.add_diary_entry("u", f"giris {i}")
    assert len(depo["diary"]) == memory_service.MAX_DIARY_ENTRIES


def test_gunluk_silme(monkeypatch):
    _gunluk_deposu(monkeypatch)
    giris = memory_service.add_diary_entry("u", "silinecek")
    assert memory_service.delete_diary_entry("u", giris["id"]) is True
    assert memory_service.delete_diary_entry("u", "yok") is False
    assert memory_service.get_diary("u") == []


def test_gunluk_sohbet_fisiltisina_girer(monkeypatch):
    """'Son ayda ne oldu?' sorusunun hammaddesi: girisler baglama akar."""
    _gunluk_deposu(monkeypatch)
    memory_service.add_diary_entry("u", "Is gorusmesine gittim",
                                   theme="career")
    baglam = memory_service.memory_context("u")
    assert "Is gorusmesine gittim" in baglam
    assert "(günlük" in baglam
# --------------------------------------------------------------------------
# Unutma: omur, celiski, kararli anahtar (K6)
#
# Sahibin tarifi: "bir bilgiye takiliyor ve sanki hep o varmis gibi yorum
# yapiyor... biriyle bir problem yasadin, tum AI yorumlarini zehirliyor ve
# HIC GITMIYOR". Tarif mecaz degildi: unutma mekanizmasi HIC YOKTU.
# Siralama yalniz guvene bakiyordu, cikarici "acikca soylediyse 0.9"
# yaziyordu, yani bir kez soylenen her sey kalici bir birincilik bileti
# aliyordu. Asagidaki bekcilerin her biri o zincirin bir halkasini tutuyor.
# --------------------------------------------------------------------------

_AN = dt.datetime(2026, 10, 2, 12, 0, tzinfo=dt.timezone.utc)


def _gun_once(n: int) -> dt.datetime:
    return _AN - dt.timedelta(days=n)


def _hafiza_deposu(monkeypatch, olgular):
    """Hafizayi bellek-ici sahteyle degistirir (Firestore yok)."""
    depo = {"version": 1, "facts": list(olgular), "moodTrail": [],
            "toneHint": None, "diary": []}

    def oku(uid):
        return {k: (list(v) if isinstance(v, list) else v)
                for k, v in depo.items()}

    def yaz(uid, memory):
        depo.update(memory)

    monkeypatch.setattr(memory_service, "get_memory", oku)
    monkeypatch.setattr(memory_service, "_write", yaz)
    return depo


def _fisilti_satirlari(metin: str) -> list[str]:
    return [s for s in metin.splitlines() if s.startswith("- (")]


def _fisilti(monkeypatch, olgular, max_chars: int = 4000) -> str:
    """Verilen olgularla fisiltiyi uretir (butce BILEREK bol).

    Butce genis tutuluyor cunku siralama bekcilerinin olctugu sey SIRA;
    butce kirpmasi devreye girerse ayni test iki ayri mekanizmayi birden
    olcer ve hangisinin kirildigi belirsizlesir."""
    monkeypatch.setattr(memory_service, "get_memory", lambda uid: {
        "facts": list(olgular), "moodTrail": [], "diary": [],
        "toneHint": None})
    return memory_service.memory_context("u", max_chars=max_chars, simdi=_AN)


def test_her_kategorinin_omru_tanimli():
    """Omur tablosu TEK KAYNAK; yeni kategori eklenip omru unutulursa o
    kategori sessizce "omursuz" davranirdi — yani asla unutulmazdi."""
    assert set(memory_service.FACT_LIFESPAN_DAYS) == set(
        memory_service.CATEGORIES)
    # Yasak listesi omursuz KALMALI: "bunu konusmak istemiyorum" bir kez
    # soylenir; omur verilmesi yasagin sessizce kalkmasi olurdu.
    assert memory_service.FACT_LIFESPAN_DAYS["sensitivity"] is None
    # Kaygi ise kisa omurlu OLMALI; zehirlenen sey buydu.
    assert memory_service.FACT_LIFESPAN_DAYS["concern"] is not None


def test_omrunu_tamamlayan_kaygi_fisiltiya_girmez(monkeypatch):
    """Zehirlenmenin cekirdegi: 40 gun once soylenen bir kaygi 0.9 guvenle
    yaziliyor ve siralama yalniz guvene baktigi icin HER turda butcenin
    basini kapiyordu. Omur kapisi onu dusurur; ama kapi KATEGORIYE gore
    oldugu icin yasak ve milestone yerinde kalir."""
    monkeypatch.setattr(memory_service, "get_memory", lambda uid: {
        "facts": [
            {"category": "concern", "key": "concern.relationship",
             "value": "sevgilisiyle kavga etti", "confidence": 0.9,
             "topic": "relationship", "updatedAt": _gun_once(40)},
            {"category": "concern", "key": "concern.work",
             "value": "is yerinde zorlaniyor", "confidence": 0.9,
             "topic": "work", "updatedAt": _gun_once(3)},
            {"category": "sensitivity", "key": "sensitivity.babasi",
             "value": "babasindan soz edilmesini istemiyor",
             "confidence": 0.9, "updatedAt": _gun_once(400)},
            {"category": "milestone", "key": "milestone.yildonumu",
             "value": "yildonumu subatta", "confidence": 0.9,
             "updatedAt": _gun_once(400)},
        ],
        "moodTrail": [], "diary": [], "toneHint": None,
    })
    sonuc = memory_service.memory_context("u", max_chars=4000, simdi=_AN)
    assert "kavga etti" not in sonuc, "omru gecen kaygi fisiltida"
    assert "zorlaniyor" in sonuc, "taze kaygi dusmus"
    assert "babasindan" in sonuc, "yasak omurlu gibi davranmis"
    assert "yildonumu" in sonuc, "milestone omurlu gibi davranmis"


def test_celiskili_yeni_bilgi_eski_kaygiyi_gecersiz_kilar(monkeypatch):
    """K6-b: "ayrildik" dedikten sonra "sevgilisiyle sorun yasiyor" kaydi
    yasamaya devam ediyordu — iki kaydin anahtari da kategorisi de farkli
    oldugu icin `key` birlestirmesi ikisini hic karsilastirmiyordu.
    Her iki eski olgu da OMRU ICINDE (12 gun), yani bu testin kirmizisi
    yalniz celiski kuralini olcer, omru olcmez."""
    depo = _hafiza_deposu(monkeypatch, [
        {"category": "concern", "key": "concern.relationship",
         "value": "sevgilisiyle sorun yasiyor", "confidence": 0.9,
         "topic": "relationship", "updatedAt": _gun_once(12)},
        {"category": "concern", "key": "concern.work",
         "value": "is yerinde zorlaniyor", "confidence": 0.9,
         "topic": "work", "updatedAt": _gun_once(12)},
    ])

    memory_service.upsert_facts("u", [
        {"category": "relationship", "key": "relationship.status",
         "value": "ayrildi", "confidence": 0.9},
    ], _AN)

    kayit = {f["key"]: f for f in depo["facts"]}
    assert kayit["concern.relationship"].get("invalidatedAt") is not None, \
        "ayni konudaki eski kaygi gecersiz kilinmadi"
    # Kural KONUYA bagli: "yeni bilgi geldi, hepsini sil" degil.
    assert kayit["concern.work"].get("invalidatedAt") is None, \
        "baska konudaki kaygi da dusurulmus"

    baglam = memory_service.memory_context("u", max_chars=4000, simdi=_AN)
    assert "sorun yasiyor" not in baglam
    assert "ayrildi" in baglam
    assert "zorlaniyor" in baglam


def test_ayni_turda_gelen_iki_kaygi_birbirini_gecersiz_kilmaz(monkeypatch):
    """Ayni konusmadan cikan iki kaygi ayni damgayi tasir; aralarinda
    "yenisi" yok. Damga karsilastirmasi olmasa ikinci, birinciyi sessizce
    silerdi — ayni turda soylenmis bir bilgi kaybi."""
    depo = _hafiza_deposu(monkeypatch, [])
    memory_service.upsert_facts("u", [
        {"category": "concern", "key": "concern.relationship",
         "value": "tartisma yasadi", "confidence": 0.9,
         "topic": "relationship"},
        {"category": "concern", "key": "concern.guven",
         "value": "guven sorunu var", "confidence": 0.9,
         "topic": "relationship"},
    ], _AN)
    assert len(depo["facts"]) == 2
    assert all(not f.get("invalidatedAt") for f in depo["facts"])


def test_ayni_olgu_iki_ayri_surecte_ayni_anahtari_alir():
    """Gercek hata: yedek anahtar `abs(hash(value))` ile kuruluyordu ve
    PYTHONHASHSEED ayarli olmadigi icin CPython dize hash'ini her surecte
    baska tohumlar. Yani ayni olgu her Cloud Run orneginde BASKA anahtar
    aliyor, birlesmesi gereken kayit sessizce cogaliyordu.

    Bekci surec ICINDEN olculemez (tohum yorumlayici basinda sabitlenir),
    bu yuzden gercekten ayri surecler kosturuluyor."""
    kod = ("from services import memory_service as m;"
           "print(m._normalize_fact({'category': 'concern',"
           " 'value': 'sevgilimle kavga ettim'})['key'])")
    backend = pathlib.Path(__file__).resolve().parents[1]
    anahtarlar = set()
    for tohum in ("0", "1", "524287"):
        ortam = dict(os.environ, PYTHONHASHSEED=tohum,
                     PYTHONPATH=str(backend))
        sonuc = subprocess.run(
            [sys.executable, "-c", kod], cwd=str(backend), env=ortam,
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=180)
        assert sonuc.returncode == 0, sonuc.stderr
        anahtarlar.add(sonuc.stdout.strip())
    assert len(anahtarlar) == 1, \
        f"anahtar surece gore degisiyor: {anahtarlar}"


def test_butcenin_basini_en_yeni_olgu_kapar(monkeypatch):
    """Karakter butcesinin basini en ISRARLI (= en yuksek guvenli) olgu
    degil en GUNCEL olgu kapmali. Ikisi de omru icinde, yani bu testin
    kirmizisi yalniz siralamayi olcer."""
    monkeypatch.setattr(memory_service, "get_memory", lambda uid: {
        "facts": [
            {"category": "concern", "key": "concern.relationship",
             "value": "ISRARLI eski kaygi", "confidence": 0.9,
             "updatedAt": _gun_once(25)},
            {"category": "work", "key": "work.transition",
             "value": "YENI is haberi", "confidence": 0.5,
             "updatedAt": _gun_once(0)},
        ],
        "moodTrail": [], "diary": [], "toneHint": None,
    })
    satirlar = _fisilti_satirlari(
        memory_service.memory_context("u", max_chars=4000, simdi=_AN))
    assert "YENI" in satirlar[0], f"butcenin basini israrli kapmis: {satirlar}"
    assert "ISRARLI" in satirlar[1]


def test_yasak_butce_yarisina_girmez(monkeypatch):
    """`sensitivity` bilgi degil YASAKTIR: butce kirpmasi onu dusurursa
    model yasakli konuyu acar — eski bir kayginin kalmasinin tam tersi
    yonde ama ayni agirlikta bir kusur."""
    olgular = [{"category": "goal", "key": f"goal.{i}",
                "value": f"taze hedef {i}", "confidence": 1.0,
                "updatedAt": _gun_once(0)}
               for i in range(memory_service.MAX_WHISPER_FACTS + 5)]
    olgular.append({"category": "sensitivity", "key": "sensitivity.babasi",
                    "value": "babasindan soz edilmesini istemiyor",
                    "confidence": 0.5, "updatedAt": _gun_once(300)})
    monkeypatch.setattr(memory_service, "get_memory", lambda uid: {
        "facts": olgular, "moodTrail": [], "diary": [], "toneHint": None})
    satirlar = _fisilti_satirlari(
        memory_service.memory_context("u", max_chars=4000, simdi=_AN))
    assert len(satirlar) == memory_service.MAX_WHISPER_FACTS, \
        "olgu dilimi uygulanmamis; olgular butcenin tamamini yiyor"
    assert "babasindan" in satirlar[0], "yasak butce yarisinda dusmus"


def test_olgu_fisiltiya_tarihiyle_girer(monkeypatch):
    """Eski fisilti tarih YAZMIYORDU: model bilginin dunku mu alti ay
    onceki mi oldugunu bilemiyor, hepsini "su an gecerli" okuyordu.
    Tarihi OLMAYAN olguya tarih YAZILMAZ — olculmeyen soylenmez."""
    monkeypatch.setattr(memory_service, "get_memory", lambda uid: {
        "facts": [
            {"category": "work", "key": "work.transition",
             "value": "YAKIN olay", "confidence": 0.9,
             "updatedAt": _gun_once(3)},
            {"category": "family", "key": "family.tasinma",
             "value": "UZAK olay", "confidence": 0.9,
             "updatedAt": _gun_once(150)},
            {"category": "preference", "key": "preference.ton",
             "value": "TARIHSIZ tercih", "confidence": 0.9},
        ],
        "moodTrail": [], "diary": [], "toneHint": None,
    })
    satirlar = _fisilti_satirlari(
        memory_service.memory_context("u", max_chars=4000, simdi=_AN))
    yakin = [s for s in satirlar if "YAKIN" in s][0]
    uzak = [s for s in satirlar if "UZAK" in s][0]
    tarihsiz = [s for s in satirlar if "TARIHSIZ" in s][0]

    etiket = lambda s: s.split(")")[0]  # noqa: E731
    # Uc bagimsiz isaret: etiketler birbirinden FARKLI, ikisi de kendi
    # yas sayisini tasiyor, tarihsiz olgu hic yas tasimiyor.
    assert etiket(yakin) != etiket(uzak), "iki yas ayni etiketi almis"
    assert "3" in etiket(yakin)
    assert "150" in etiket(uzak)
    # ⚠️ "Rakam yok" diye okunan iddia KOR cikti (dogrulama turu, minimal
    # mutasyonla olculdu): `_yas_gun` tarihsiz olguya 0 donse etiket
    # "bugün" olur, icinde RAKAM YOK ve bekci gecerdi — yani tarih
    # UYDURMANIN en dogal bicimi bu bekciyi asiyordu. Capa artik dize
    # LITERALI: etiket kategorinin kendisine birebir esit, yani hicbir ek
    # (ne sayi ne kelime) yok.
    assert etiket(tarihsiz) == "- (preference", \
        f"tarihi olmayan olguya yas uydurulmus: {tarihsiz}"
    # Sozlesmenin kendisi: tarihsiz olgunun yasi "0 gun" DEGIL "bilinmiyor".
    assert memory_service._yas_gun(
        {"category": "preference", "key": "preference.ton"}, _AN) is None, \
        "tarihsiz olguya yas uyduruluyor"


def test_budama_omru_gecmis_olguyu_yuksek_guvenli_olsa_da_duser():
    """Budamanin OMUR katmanini olcer (ucun ikincisi).

    Eski budama guveni onceliyordu ve docstring'i bunu itiraf ediyordu:
    0.9 guvenli ESKI bir olgu BUDANAMIYORDU. Omru gecmis olgu zaten
    fisiltiya giremiyor; depolama slotunu tutmasinin gerekcesi yok.

    DIKKAT: bu bekci yalniz OMUR katmanini tutuyor — fikstur 500 gunluk
    `work`, yani omrunu (180) ASMIS durumda. Siralamadaki tazelik terimi
    bu testten BAGIMSIZ ve onu bir sonraki bekci olcuyor; ikisini tek
    teste yiginca tazelik terimi geri alinsa da yesil kaliyordu
    (mutasyonla olculdu)."""
    eski = [{"key": f"eski{i}", "category": "work", "value": f"e{i}",
             "confidence": 0.95, "updatedAt": _gun_once(500)}
            for i in range(memory_service.MAX_FACTS)]
    yeni = [{"key": f"yeni{i}", "category": "work", "value": f"y{i}",
             "confidence": 0.5, "updatedAt": _AN}
            for i in range(5)]
    # Ankorun kendisi sinaniyor: fikstur omrunu ASMIYORSA bu test adinin
    # soyledigi seyi olcmez.
    assert memory_service._omru_gecti(eski[0], _AN), \
        "fikstur omru icinde; test omur katmanini olcmuyor"

    kalan = memory_service._prune_facts(eski + yeni, _AN)

    assert len(kalan) == memory_service.MAX_FACTS
    kalan_anahtar = {f["key"] for f in kalan}
    assert all(f["key"] in kalan_anahtar for f in yeni), \
        "yuksek guvenli eski olgular yeni olgulari dusurmus"


def test_budama_omru_icindeki_eski_olguyu_da_zayif_sayar():
    """Budamanin TAZELIK terimini olcer (ucun ucuncusu) — OMURDEN bagimsiz.

    Bir ustteki bekci tek basina KORDU: fiksturu omrunu asmis oldugu icin
    siralama anahtarini `guven x tazelik`ten yalniz `guven`e geri cevirsen
    de YESIL kaliyordu (olculdu). Burada olgular omrunu ASMIYOR (170 < 180),
    yani uc katmanin ilk ikisi esit ve ayirt eden tek sey tazelik.

    Gerekcesi: bir olgu "henuz dusmedi" ile "hala en guclu" ayni sey
    degil. Ikisini ayirmazsan 170 gunluk 0.95'lik bir kayit, dunku bir
    kaydin depolama slotunu almaya devam eder."""
    eski = [{"key": f"eski{i}", "category": "work", "value": f"e{i}",
             "confidence": 0.95, "updatedAt": _gun_once(170)}
            for i in range(memory_service.MAX_FACTS)]
    yeni = [{"key": f"yeni{i}", "category": "work", "value": f"y{i}",
             "confidence": 0.5, "updatedAt": _AN}
            for i in range(5)]
    assert not memory_service._omru_gecti(eski[0], _AN), \
        "fikstur omrunu asmis; test tazelik yerine omur katmanini olcuyor"

    kalan = memory_service._prune_facts(eski + yeni, _AN)

    assert len(kalan) == memory_service.MAX_FACTS
    kalan_anahtar = {f["key"] for f in kalan}
    assert all(f["key"] in kalan_anahtar for f in yeni), \
        "guven tek basina siralamis; eski olgu yeni olgunun slotunu almis"


def test_siralamada_guven_hala_rol_oynar(monkeypatch):
    """Agirlik `guven x tazelik`; tazelik TEK BASINA degil.

    Curumeyi eklerken guveni yok saymak, bir kusuru onarirken digerini
    dogurmak olurdu: cikarici "acikca soylediyse 0.9, ima ettiyse 0.5"
    yaziyor, yani guven bilginin DOGRULUK derecesi ve onu atmak ima
    edilmis bir seyi soylenmis saymaktir. Olgular ayni yasta ve ayni
    kategoride, yani ayirt eden tek sey guven.

    Olculdu: bu bekci olmadan `_etkin_agirlik` guveni tumden yok saysa
    bile takim 41/41 yesil kaliyordu."""
    satirlar = _fisilti_satirlari(_fisilti(monkeypatch, [
        # DUSUK olan BILEREK basta: esit agirlikta Python siralamasi
        # kararli oldugu icin mutasyon hali girdi sirasini korur ve bekci
        # ancak boyle kirmizi olur.
        {"category": "work", "key": "work.a", "value": "DUSUK guven",
         "confidence": 0.4, "updatedAt": _gun_once(3)},
        {"category": "work", "key": "work.b", "value": "YUKSEK guven",
         "confidence": 0.9, "updatedAt": _gun_once(3)},
    ]))
    assert "YUKSEK" in satirlar[0], f"guven siralamada rol oynamiyor: {satirlar}"
    assert "DUSUK" in satirlar[1]


def test_tarihsiz_olgu_cok_eski_sayilmaz(monkeypatch):
    """`_yas_gun` docstring'i "``None`` 'cok eski' DEGIL 'bilmiyoruz'
    demektir ve HER YERDE oyle davranilir" diyor. Omur ve tarih etiketi
    tarafinin bekcisi vardi, SIRALAMA tarafinin yoktu: tarihsiz olgunun
    tazeligini 1.0 yerine 0.0 yapan mutasyon 53/53 YESIL geciyordu — yani
    iddianin yarisi olculmemisti.

    Neden onemli: sema oncesi ve elle kurulmus kayitlar tarihsiz. Onlari
    "cok eski" saymak, hic olculmemis bir seyi olculmus gibi sunmaktir ve
    sirayi sessizce dibe atar.

    Iki bagimsiz isaret: tarihsiz olgu daha YUKSEK guvenli ESKI bir
    olgunun ONUNE geciyor (= cok eski sayilmiyor), ama daha yuksek guvenli
    TAZE bir olgunun onune GECMIYOR (= sinirsiz ayricalik da yok)."""
    satirlar = _fisilti_satirlari(_fisilti(monkeypatch, [
        {"category": "work", "key": "work.eski", "value": "ESKI kayit",
         "confidence": 0.95, "updatedAt": _gun_once(170)},
        {"category": "goal", "key": "goal.tarihsiz", "value": "TARIHSIZ",
         "confidence": 0.5},
    ]))
    assert "TARIHSIZ" in satirlar[0], \
        f"tarihsiz olgu cok eski sayilmis: {satirlar}"

    satirlar2 = _fisilti_satirlari(_fisilti(monkeypatch, [
        {"category": "goal", "key": "goal.tarihsiz", "value": "TARIHSIZ",
         "confidence": 0.5},
        {"category": "goal", "key": "goal.taze", "value": "TAZE kayit",
         "confidence": 0.9, "updatedAt": _gun_once(0)},
    ]))
    assert "TAZE" in satirlar2[0], \
        f"tarihsiz olgu taze olgunun onune gecmis: {satirlar2}"


def test_omursuz_olgu_dusmez_ama_sirada_geriler(monkeypatch):
    """`KALICI_YARILANMA_GUN`: omursuz olmak "hic eskimez" demek DEGIL.

    Bes yil once soylenen bir `milestone` fisiltidan DUSMEZ (omru yok) ama
    dun soylenen bir tercihin ONUNE de gecmemeli. Iki bagimsiz iddia tek
    testte: olgu DURUYOR ve sira GERIDE. Olculdu: omursuz kategorileri hic
    curutmeyen bir mutasyon bu bekci olmadan yesil geciyordu, yani
    `KALICI_YARILANMA_GUN`in hicbir bekcisi yoktu."""
    satirlar = _fisilti_satirlari(_fisilti(monkeypatch, [
        {"category": "milestone", "key": "milestone.x",
         "value": "BES YIL once soylenen tarih", "confidence": 0.9,
         "updatedAt": _gun_once(1825)},
        {"category": "preference", "key": "preference.ton",
         "value": "DUNKU tercih", "confidence": 0.5,
         "updatedAt": _gun_once(1)},
    ]))
    assert any("BES YIL" in s for s in satirlar), "omursuz olgu dusmus"
    assert "DUNKU" in satirlar[0], \
        f"bes yillik kayit dunku kaydin onune gecmis: {satirlar}"


def test_modelin_verdigi_konu_celiskide_kullanilir(monkeypatch):
    """`_SCHEMA`'ya eklenen `topic` alaninin TEK isi bu.

    Anahtar konu ipucu VERMIYOR ("concern.kavga") ve kategori de konu
    degil; yani alan okunmazsa celiski kurali bu kaydi hic gormez.
    Olculdu: alani yok sayan mutasyon bu bekci olmadan yesil geciyordu —
    sema degisikliginin hicbir bekcisi yoktu."""
    depo = _hafiza_deposu(monkeypatch, [
        {"category": "concern", "key": "concern.kavga",
         "value": "kavga var", "confidence": 0.9,
         "topic": "relationship", "updatedAt": _gun_once(12)},
    ])
    memory_service.upsert_facts("u", [
        {"category": "relationship", "key": "relationship.status",
         "value": "ayrildi", "confidence": 0.9}], _AN)
    kayit = {f["key"]: f for f in depo["facts"]}
    assert kayit["concern.kavga"].get("invalidatedAt") is not None, \
        "modelin verdigi konu okunmamis; celiski kurali calismadi"


def test_topic_alani_olmayan_eski_kayit_da_gecersiz_kilinir(monkeypatch):
    """GERIYE DONUK ETKI — bu turun en sessiz bosluguydu.

    ``topic`` alani bu turda dogdu, yani URETIMDEKI hicbir kayitta YOK.
    Celiski kurali alani DOGRUDAN okursa yalniz bu degisiklikten sonra
    yazilmis kayitlara isler; oysa zehir tam da eski kayitta duruyor.
    Sahibin hesabinda 5 gunluk bir `concern` varsa "ayrildik" dedikten
    sonra o kayit 25 gun daha yasardi (30 gunluk omur kapisi onu ancak o
    zaman duserdi) — yani sikayetin tam olarak kendisi, onarimdan SONRA.
    Konu anahtarin parcalarindan cikarilabildigi icin kural ilk deploy
    aninda eski kayitlara da isliyor."""
    depo = _hafiza_deposu(monkeypatch, [
        # `topic` alani YOK; uretimdeki kayitlarin hali bu.
        {"category": "concern", "key": "concern.relationship",
         "value": "sevgilisiyle sorun yasiyor", "confidence": 0.9,
         "updatedAt": _gun_once(5)},
    ])
    memory_service.upsert_facts("u", [
        {"category": "relationship", "key": "relationship.status",
         "value": "ayrildi", "confidence": 0.9}], _AN)
    kayit = {f["key"]: f for f in depo["facts"]}
    assert kayit["concern.relationship"].get("invalidatedAt") is not None, \
        "topic alani olmayan eski kayit celiskiye ragmen yasiyor"


def test_ayni_konudaki_kaygi_disi_kayit_gecersiz_kilinmaz(monkeypatch):
    """`CELISKIDE_DUSEN`in TEK bekcisi — ve yoktu.

    Kuralin kategoriye bagli olmasinin gerekcesi koda yazilmisti
    ("work.transition ile work.employer iki ayri KAYITtir, birlikte
    yasamalari gerekir") ama OLCUSU YOKTU: kapiyi kaldiran minimal mutasyon
    takimi 49/49 YESIL geciyordu. Oysa kapisiz hal SESSIZ VERI KAYBI —
    ayni hayat alanindaki yeni bir olgu, o alandaki butun eski kayitlari
    (isveren, aile baglami, iliski durumu) gecersiz isaretler.

    Iki bagimsiz isaret tek turda: kaygi DUSER, kaygi disi kayit KALIR.
    Ikincisi olmasa test "hicbir sey gecersiz kilinmiyor" halini de yesil
    gecerdi."""
    depo = _hafiza_deposu(monkeypatch, [
        {"category": "work", "key": "work.employer",
         "value": "X sirketinde calisiyor", "confidence": 0.9,
         "topic": "work", "updatedAt": _gun_once(20)},
        {"category": "concern", "key": "concern.work",
         "value": "is yerinde zorlaniyor", "confidence": 0.9,
         "topic": "work", "updatedAt": _gun_once(20)},
    ])
    memory_service.upsert_facts("u", [
        {"category": "work", "key": "work.transition",
         "value": "yeni bir role gecti", "confidence": 0.9},
    ], _AN)
    kayit = {f["key"]: f for f in depo["facts"]}
    assert kayit["work.employer"].get("invalidatedAt") is None, \
        "kaygi disi kayit da gecersiz kilinmis; sessiz veri kaybi"
    assert kayit["concern.work"].get("invalidatedAt") is not None, \
        "ayni konudaki eski kaygi dusmemis; test celiski kuralini olcmuyor"


def test_gecersiz_kaydin_damgasi_yeniden_yazilmaz(monkeypatch):
    """`not eski.get("invalidatedAt")` kapisinin bekcisi — ve yoktu.

    Kapi kaldirildiginda kayit YINE gecersiz kalir, yani fisiltida hicbir
    sey degismez; bu yuzden kolay atlaniyor. Ama damga "bu bilgi NE ZAMAN
    asildi" diye okunuyor ve her yeni olguda ustune yazilmasi o tarihi
    UYDURMA yapar — olculen yanlis adla sunulmaz. Ileri tura notta duran
    kullaniciya gorunen hafiza ekrani tam bu alani gosterecek."""
    ilk_damga = _gun_once(9)
    depo = _hafiza_deposu(monkeypatch, [
        {"category": "concern", "key": "concern.relationship",
         "value": "sevgilisiyle sorun yasiyor", "confidence": 0.9,
         "topic": "relationship", "updatedAt": _gun_once(20),
         "invalidatedAt": ilk_damga},
    ])
    memory_service.upsert_facts("u", [
        {"category": "relationship", "key": "relationship.status",
         "value": "yeni biriyle tanisti", "confidence": 0.9},
    ], _AN)
    kayit = {f["key"]: f for f in depo["facts"]}
    assert kayit["concern.relationship"]["invalidatedAt"] == ilk_damga, \
        "gecersizlik damgasi yeniden yazilmis; asilma tarihi uyduruluyor"


def test_tarihsiz_eski_kaygi_da_gecersiz_kilinir(monkeypatch):
    """`_eski_mi`nin "tarihi bilinmeyen kayit ESKI sayilir" dalinin bekcisi
    — ve yoktu (dali ters ceviren mutasyon 49/49 yesil geciyordu).

    Load-bearing cunku tarihsiz kayit tam da en TEHLIKELI sinif: `_yas_gun`
    ona yas vermez, dolayisiyla OMUR KAPISI onu hic dusurmez. Celiski
    kurali da atlarsa o kaydin hicbir cikisi kalmaz — sonsuza dek
    fisiltida. Sema oncesi kayitlar ve elle kurulmus kayitlar bu sinifta."""
    depo = _hafiza_deposu(monkeypatch, [
        # `updatedAt` YOK: ne omur kapisi ne tazelik bu kaydi dusurebilir.
        {"category": "concern", "key": "concern.relationship",
         "value": "sevgilisiyle sorun yasiyor", "confidence": 0.9,
         "topic": "relationship"},
    ])
    assert not memory_service._omru_gecti(depo["facts"][0], _AN), \
        "fikstur omurle dusuyor; test `_eski_mi` dalini olcmuyor"

    memory_service.upsert_facts("u", [
        {"category": "relationship", "key": "relationship.status",
         "value": "ayrildi", "confidence": 0.9}], _AN)

    kayit = {f["key"]: f for f in depo["facts"]}
    assert kayit["concern.relationship"].get("invalidatedAt") is not None, \
        "tarihsiz eski kayit yeni bilgiyi bastirdi"


def test_naive_damga_tasiyan_eski_olgu_da_omurle_duser(monkeypatch):
    """`ts.replace(tzinfo=utc)` varsayiminin bekcisi — ve yoktu.

    O satirin yorumu ilk halinde YANLIS gerekce tasiyordu ("except hafizayi
    tumden susturur"); olculen sonuc TERSI: varsayim olmadan `_yas_gun`
    yalniz O OLGU icin None doner, `_omru_gecti` bilinmeyen yasi gecmis
    saymaz ve olgu OLUMSUZ olur — 400 gunluk bir kaygi fisiltida tarihsiz
    ve sonsuza dek kalir. Yani varsayimi kaldirmak, paketin onardigi
    zehirlenmeyi geri getirir.

    Uc bagimsiz isaret: yas SAYISAL cikiyor, omur kapisi DUSURUYOR, ve
    olgu fisiltida YOK."""
    naive = dt.datetime(2026, 8, 28, 12, 0)  # tzinfo YOK (sema oncesi hal)
    olgu = {"category": "concern", "key": "concern.relationship",
            "value": "NAIVE kavga kaydi", "confidence": 0.9,
            "updatedAt": naive}
    yas = memory_service._yas_gun(olgu, _AN)
    assert yas is not None and yas > 30, f"naive damgadan yas cikmadi: {yas}"
    assert memory_service._omru_gecti(olgu, _AN), \
        "naive damgali kaygi omurle dusmuyor; olumsuz"
    monkeypatch.setattr(memory_service, "get_memory", lambda uid: {
        "facts": [olgu], "moodTrail": [], "diary": [], "toneHint": None})
    assert "NAIVE" not in memory_service.memory_context(
        "u", max_chars=4000, simdi=_AN)


def test_konu_alt_dize_ile_degil_parcayla_eslesir():
    """Depo kurali: ALT DIZE eslesmesi yanlis pozitif uretir.

    "workaround" icinde "work" var. Konu yanlis cikarsa YANLIS kayit
    gecersiz kilinir — yani bu sessiz bir veri kaybi, kozmetik bir hata
    degil. `_konu` yorumunun kendi gerekcesi buydu ve olcusu yoktu:
    alt dize aramasina ceviren mutasyon yesil geciyordu."""
    assert memory_service._konu(
        {"category": "concern", "key": "concern.work"}) == "work"
    assert memory_service._konu(
        {"category": "concern", "key": "concern.workaround"}) is None
    # Model alanini da parcayla degil TAM eslesmeyle okur.
    assert memory_service._konu(
        {"category": "concern", "key": "concern.x",
         "topic": "relationships"}) is None
    # Alan bastaysa da sondaysa da bulunur (ad alanina bakmak birini
    # kacirirdi).
    assert memory_service._konu(
        {"category": "goal", "key": "relationship.status"}) == "relationship"
    # UCUNCU kaynak: kategorinin KENDISI. `_konu` docstring'i uc kaynak
    # sayiyordu ama bu ucuncusunun olcusu yoktu (kaldiran mutasyon yesil
    # geciyordu). Load-bearing: modelden "ayrilik" gibi ad alansiz bir
    # anahtar gelirse konu YALNIZ kategoriden cikar; cikmazsa o olgu
    # hicbir eski kaygiyi gecersiz kilamaz ve zehir yasar.
    assert memory_service._konu(
        {"category": "relationship", "key": "ayrilik"}) == "relationship"
    # Ters yon: kategori kapali kumede degilse konu YINE None kalir
    # (kategori != konu; "concern" bir hayat alani degil).
    assert memory_service._konu(
        {"category": "concern", "key": "ayrilik"}) is None


def test_yas_etiketi_bugun_ve_dun_ayri_yazilir():
    """Fisilti modelin OKUDUGU bir cumle, log satiri degil: "0 gun once"
    makine konusmasidir. Uc ayri esik, uc ayri ifade.

    Capa diyakritige BAGLANMIYOR (depo kurali: tek Turkce kelimeye capa
    atmak ASCII yazimda korlesir). Uc bagimsiz isaret: ucu birbirinden
    farkli, ilk ikisi sayi TASIMIYOR, ucuncusu tasiyor."""
    etiketler = [memory_service._yas_etiketi(y) for y in (0.0, 1.4, 12.0)]
    assert len(set(etiketler)) == 3, etiketler
    assert not any(c.isdigit() for c in etiketler[0]), etiketler[0]
    assert not any(c.isdigit() for c in etiketler[1]), etiketler[1]
    assert "12" in etiketler[2], etiketler[2]


def test_budama_omru_gecmisi_agir_olsa_da_canlinin_onune_gecirmez():
    """Budamanin OMUR KATMANI tek basina olculur (ucun ikincisi, izole).

    Bir ustteki iki bekci omur katmanini ATLAYARAK da yesil kaliyordu:
    500 gunluk olgularin tazeligi zaten dibe vurmus oldugu icin agirlik
    terimi ayni sonucu veriyordu (mutasyonla olculdu — katmani silmek
    48/48 yesil geciyordu). Burada fikstur TERS kurulu: omru GECMIS olgu
    agirlik olarak CANLI olgudan DAHA GUCLU. Katman yoksa olu kayit canli
    kaydin slotunu alir ve docstring'in vaadi ("canli bir olgu onlarin
    yuzunden dusmez") yalan olur."""
    # Omru 1 gun gecmis kaygi: 0.5^(31/15) x 1.0 = 0.239
    olu = [{"key": f"olu{i}", "category": "concern", "value": f"o{i}",
            "confidence": 1.0, "updatedAt": _gun_once(31)}
           for i in range(memory_service.MAX_FACTS)]
    # Omursuz ama cok eski milestone: 0.5^(1000/365) x 0.9 = 0.135
    canli = [{"key": f"canli{i}", "category": "milestone", "value": f"c{i}",
              "confidence": 0.9, "updatedAt": _gun_once(1000)}
             for i in range(5)]
    # Fikstur ANKORLARI — ucu birden: olu gercekten omrunu asmis, canli
    # asmamis, VE olunun agirligi canlidan BUYUK. Ucuncusu olmazsa test
    # omur katmanini degil yine agirligi olcer.
    assert memory_service._omru_gecti(olu[0], _AN)
    assert not memory_service._omru_gecti(canli[0], _AN)
    assert (memory_service._etkin_agirlik(olu[0], _AN)
            > memory_service._etkin_agirlik(canli[0], _AN)), \
        "fikstur ters kurulmamis; test omur katmanini olcmuyor"

    kalan = memory_service._prune_facts(olu + canli, _AN)

    assert len(kalan) == memory_service.MAX_FACTS
    kalan_anahtar = {f["key"] for f in kalan}
    assert all(f["key"] in kalan_anahtar for f in canli), \
        "omru gecmis olgu canli olgunun depolama slotunu almis"


def test_budama_once_gecersiz_kilinani_duser():
    """Gecersiz olgular ilk kurban sinifi: fisiltiya hic girmiyorlar, yani
    canli bir olgu onlarin yuzunden duserse hafiza bilerek yanlis
    kirpilmis olurdu."""
    gecersiz = [{"key": f"gecersiz{i}", "category": "work", "value": f"g{i}",
                 "confidence": 1.0, "updatedAt": _AN,
                 "invalidatedAt": _gun_once(1)}
                for i in range(3)]
    canli = [{"key": f"canli{i}", "category": "work", "value": f"c{i}",
              "confidence": 0.1, "updatedAt": _AN}
             for i in range(memory_service.MAX_FACTS)]

    kalan = memory_service._prune_facts(gecersiz + canli, _AN)

    assert len(kalan) == memory_service.MAX_FACTS
    assert not any(f.get("invalidatedAt") for f in kalan), \
        "gecersiz olgu canli olgunun slotunu almis"


def test_cikarim_promptu_mevcut_anahtarlari_ve_konuyu_tasir(monkeypatch):
    """"Ustune yigilma"nin kokten onarimi: model mevcut anahtari GORURSE
    ayni konuda yeni anahtar uydurmaz ve `upsert_facts` birlestirebilir.
    Gecersiz kilinmis anahtar modele VERILMEZ — yoksa model olu bir kaydi
    diriltir."""
    _cikarima_izin_ver(monkeypatch)
    # Ankorlar BILEREK uydurma: `_PROMPT` sablonu `key` kuralinin ornegi
    # olarak "relationship.status" dizesini kendi icinde tasiyor, yani o
    # anahtari aramak bekciyi KOR yapiyordu (mevcut anahtarlar prompta hic
    # girmese de yesil kaliyordu — mutasyonla olculdu). Sablonda gecmesi
    # imkansiz bir anahtar tek gecerli ankor.
    canli_anahtar = "relationship.ankor7q"
    olu_anahtar = "concern.ankor9z"
    monkeypatch.setattr(memory_extractor.memory_service, "get_memory",
                        lambda uid: {"facts": [
                            {"key": canli_anahtar, "value": "x"},
                            {"key": olu_anahtar, "value": "y",
                             "invalidatedAt": _gun_once(1)},
                        ]})
    gorulen: dict = {}

    def sahte_llm(prompt, **kw):
        gorulen["prompt"] = prompt
        return json.dumps({"facts": []})

    monkeypatch.setattr(memory_extractor.gemini_service, "extract_json",
                        sahte_llm)
    monkeypatch.setattr(memory_extractor.memory_service, "upsert_facts",
                        lambda uid, facts: {"facts": []})

    memory_extractor.extract_and_store(
        "u", [{"sender": "USER", "text": "a"},
              {"sender": "USER", "text": "b"}], "son mesaj")

    p = gorulen.get("prompt", "")
    assert canli_anahtar in p, "mevcut anahtarlar prompta girmemis"
    assert olu_anahtar not in p, "gecersiz anahtar modele verilmis"
    # Ankorun kendisi de sinaniyor: sablon o dizeyi zaten tasiyorsa yukaridaki
    # iddia hicbir sey olcmez. Bu satir korlugun geri gelmesini engeller.
    assert canli_anahtar not in memory_extractor._PROMPT, \
        "ankor prompt sablonunda geciyor; bekci kor"
    # Bicimlendirme yer tutucusu sizmamis olmali (format() atlanmis olurdu).
    assert "{anahtarlar}" not in p and "{konular}" not in p
    assert "topic" in memory_extractor._SCHEMA["properties"]["facts"][
        "items"]["properties"]
    # ⚠️ Testin adi "ve konuyu tasir" diyordu ama KONU LISTESI hic
    # olculmuyordu: `konular=""` gecen mutasyon yesil geciyordu, yani
    # modele izinli konu adlari HIC gitmese de bekci susuyordu.
    #
    # Capanin SATIRA baglanmasi zorunlu. Ilk denemem butun promptta
    # ", ".join(KONULAR) ariyordu ve KENDISI de kor cikti: `CATEGORIES`
    # ayni uc adla BASLIYOR, yani "relationship, work, family" dizesi
    # KATEGORILER satirinin icinde zaten var. Kategori listesi `topic`
    # kuralinin satirina girmedigi icin dogru kapsam o satir.
    konu_satiri = [s for s in p.splitlines() if "`topic`" in s]
    assert len(konu_satiri) == 1, f"konu kurali satiri yok: {konu_satiri}"
    for konu in memory_service.KONULAR:
        assert konu in konu_satiri[0], \
            f"izinli konu '{konu}' prompta girmemis: {konu_satiri[0]}"
    # Capanin kendisi sinaniyor: sablon konulari zaten yaziyorsa yukaridaki
    # dongu hicbir sey olcmez.
    sablon_satiri = [s for s in memory_extractor._PROMPT.splitlines()
                     if "`topic`" in s][0]
    assert not any(k in sablon_satiri for k in memory_service.KONULAR), \
        "konu adlari sablonda sabit yazili; bekci kor"


# ---------------------------------------------------------------------------
# B4: fisilti butcesinin BILESEN PAYLARI
# ---------------------------------------------------------------------------

def _b4_hafiza(olgu_sayisi: int = 40):
    """Butceyi ZORLAYAN hafiza: her bilesen dolu ve olgular bol.

    Olgu sayisi bilerek `MAX_WHISPER_FACTS`in cok ustunde: aclik kusuru
    ancak olgular butceyi doldurabildiginde gorunur, az olguyla her
    bilesen zaten sigar ve bekci hicbir sey olcmez.
    """
    return {
        "facts": [
            {"category": "concern", "key": "concern.is%d" % i,
             "value": "is yerinde surekli bir tedirginlik var %02d" % i,
             "confidence": 0.9, "updatedAt": _gun_once(1)}
            for i in range(olgu_sayisi)
        ],
        "moodTrail": [
            {"date": "2026-09-%02d" % (20 + i), "mood": "kaygili",
             "intensity": "orta", "needs": "sakinlesmek"}
            for i in range(5)
        ],
        "diary": [
            {"date": "2026-09-%02d" % (25 + i),
             "text": "bugun uzun bir yuruyus yaptim ve kafam dagildi"}
            for i in range(6)
        ],
        "toneHint": "kisa ve dogrudan yanit tercih ediyor",
    }


def _b4_bilesenler(metin: str) -> dict[str, int]:
    """Fisiltiyi BILESENE gore sayar.

    Capa her bilesenin kendi ETIKET ONEKI (`- (ton tercihi)` gibi), tek
    bir Turkce kelime DEGIL: "gunluk" gibi bir kelime olgu
    degerlerinin icinde de gecebilir ve sayac sessizce sisirdi.
    Diyakritik de capaya giriyor (`gunluk` yerine `g\u00fcnl\u00fck`),
    cunku ASCII'ye indirgenen bir capa uretim satirini hic gormez.
    """
    sayac = {"olgu": 0, "ruh_hali": 0, "aradigi": 0, "gunluk": 0, "ton": 0}
    for satir in metin.splitlines():
        if not satir.startswith("- ("):
            continue
        if satir.startswith("- (ruh hali seyri)"):
            sayac["ruh_hali"] += 1
        elif satir.startswith("- (son turda arad"):
            sayac["aradigi"] += 1
        elif satir.startswith("- (g\u00fcnl\u00fck "):
            sayac["gunluk"] += 1
        elif satir.startswith("- (ton tercihi)"):
            sayac["ton"] += 1
        else:
            sayac["olgu"] += 1
    return sayac


def test_fisilti_her_bilesene_en_az_bir_satir_ayirir(monkeypatch):
    """B4: olgular otekileri ACLIKTAN olduruyordu.

    OLCULDU (onarim oncesi, ayni hafiza): `max_chars=400`'de fisiltiya
    **7 olgu ve baska HICBIR SEY** giriyordu; ruh hali seyri, gunluk ve
    ton tercihi 0 satirdi. `report_service` tam o butceyle cagiriyor,
    yani raporlarda kullanicinin ruh hali ve gunlugu HIC gorunmuyordu.

    Bekci uretim butcesine (400) baglanmistir: 4000'de her sey zaten
    sigar ve ayni bekci hicbir sey olcmez.
    """
    monkeypatch.setattr(memory_service, "get_memory",
                        lambda uid: _b4_hafiza())
    sayac = _b4_bilesenler(memory_service.memory_context(
        "u", max_chars=400, simdi=_AN))
    for ad in ("olgu", "ruh_hali", "gunluk", "ton"):
        assert sayac[ad] >= 1, \
            f"'{ad}' uretim butcesinde fisiltiya hic girmedi: {sayac}"


def test_fisilti_payi_olgularin_tekelini_kesiyor(monkeypatch):
    """B4 ikinci isaret: garanti turu TEK BASINA yetmez.

    Ustteki bekci yalnizca "en az bir satir" olcuyor, yani paylari
    bozan bir mutasyon (ornegin olgu payini 1.0 yapmak) ondan GECER:
    garanti turu her bilesene birer satir vermeye devam eder. Bu yuzden
    pay ayri olculuyor — gunluk uretim butcesinde BIRDEN COK satir
    almali ve olgular dilimi doldurmamali.
    """
    monkeypatch.setattr(memory_service, "get_memory",
                        lambda uid: _b4_hafiza())
    sayac = _b4_bilesenler(memory_service.memory_context(
        "u", max_chars=600, simdi=_AN))
    assert sayac["gunluk"] >= 2, \
        f"gunluk payini alamamis, tek satirda kalmis: {sayac}"
    assert sayac["olgu"] < memory_service.MAX_WHISPER_FACTS, \
        f"olgular yine butcenin tamamini yiyor: {sayac}"
    # Paylarin toplami 1.0 olmali: eksikse butce bosa gider, fazlaysa
    # oransal tur tavan olmaktan cikar ve ilk bilesen yine tekel kurar.
    assert abs(sum(memory_service._FISILTI_PAYLARI.values()) - 1.0) < 1e-9


def test_ruh_hali_seyri_tek_girise_inmez(monkeypatch):
    """"Seyir" adi bir EGILIM iddia eder; tek giris FOTOGRAFtir.

    Payina sigdirmak icin satiri kirpan kod ikinin altina inerse
    olculen sey (tek gun) yanlis adla (seyir) sunulmus olur. Dar butce
    secildi: pay ne kadar kucukse kirpma o kadar agresif.
    """
    monkeypatch.setattr(memory_service, "get_memory",
                        lambda uid: _b4_hafiza(olgu_sayisi=2))
    metin = memory_service.memory_context("u", max_chars=400, simdi=_AN)
    seyir = [s for s in metin.splitlines()
             if s.startswith("- (ruh hali seyri)")]
    assert len(seyir) == 1, f"seyir satiri yok: {metin!r}"
    # Giris sayisi iki nokta sayisiyla olculuyor: her giris "tarih: ruh"
    # kalibinda ve etiketin kendisinde iki nokta YOK ("- (ruh hali
    # seyri)"). Yani tek giris 1, iki giris 2 eder; esik bu yuzden 2.
    # (Ilk yazimda 3 yazmistim ve bekci KENDI hatasiyla kirmizi yandi —
    # kod dogru davraniyordu.)
    assert seyir[0].count(":") >= 2, \
        f"seyir tek girise inmis (ad artik yanlis): {seyir[0]!r}"


def test_fisilti_kullanilmayan_PAYI_bos_birakmaz(monkeypatch):
    """B4 ucuncu isaret: paylar aclik keserken ISRAF uretmemeli.

    ⚠️ Bu bekci bir KOR BEKCI onarimidir (dogrulama turu, minimal
    mutasyonla olculdu): `_paylara_bol`un ARTAN turunu TAMAMEN
    kaldiran mutasyon dosyanin tamamini 57/57 YESIL birakiyordu.
    Sebep olculdu: ustteki iki bekci de `_b4_hafiza()` kullaniyor ve
    ORADA her bilesen dolu oldugu icin ARTAN turu hicbir sey
    eklemiyor (370 -> 370 karakter, BIREBIR ayni). Yani turun
    gerekcesi ("gunlugu olmayan kullanicinin butcesinin %35'i bos
    durur") yoruma yazilmis ama HIC olculmemisti.

    Kusur GUNLUGU OLMAYAN kullanicida gorunur — cogu kullanici.
    Olculdu (uretim butcesi 400, gunluk bos):
      ARTAN VAR -> 5 olgu, 394 karakter (butcenin %98'i)
      ARTAN YOK -> 2 olgu, 232 karakter (butcenin %58'i)
    """
    hafiza = _b4_hafiza()
    hafiza["diary"] = []
    monkeypatch.setattr(memory_service, "get_memory",
                        lambda uid: hafiza)
    metin = memory_service.memory_context("u", max_chars=400,
                                          simdi=_AN)
    sayac = _b4_bilesenler(metin)
    assert sayac["gunluk"] == 0, f"kurulum bozuk, gunluk dolu: {sayac}"

    # 1. Bos kalan pay BASKA bilesenlere gecmeli.
    assert len(metin) >= 340, (
        f"butcenin {400 - len(metin)} karakteri bos durdu; "
        f"kullanilmayan pay dagitilmiyor: {sayac}")

    # 2. BAGIMSIZ isaret, uzunluktan degil SAYIMDAN: olgular kendi
    # payinin (400 * 0.40 = 160 karakter, yani ~2 satir) USTUNE
    # cikabilmeli. Garanti turu 1, oransal tur 1 satir verir; DORT
    # satira ancak ARTAN turuyla cikilir. Bu yuzden esik uzunluga
    # paralel bir kapi DEGIL, turun kendi imzasi.
    assert sayac["olgu"] >= 4, (
        f"olgular artan payi alamadi, kendi tavaninda kaldi: {sayac}")

"""BaZi cinsiyet bekçisi: "belirtmek istemiyorum" KADIN SAYILMAZ.

Ölçülen kusur: `get_bazi_chart` yalnız male/female tanıyordu; ikili olmayan
her değer (``other``, boş dize, ``unspecified``) sessizce ``is_male=False``
→ yin (kadın) kuralına düşüyor, yanıta ``gender: "female"`` yazılıyor ve
kullanıcı tek yönlü sekiz şans dönemi görüyordu. Bir beyan anahtarı
(``luck_direction_yin``) vardı ama beyan bir varsayımı ölçüm yapmaz —
"ölçülmeyen söylenmez" (CLAUDE.md §1).

Yeni sözleşme:
  * cinsiyet biliniyorsa  → ``luck_direction_known: True``, yön ve sekiz
    dönem eskisi gibi;
  * bilinmiyorsa          → ``luck_direction_known: False``,
    ``luck_direction: None``, ``luck_pillars: []`` ve iki aday dizi
    ``luck_pillar_candidates`` altında ("yönsüz sütun" yok: dönem sütunu
    ±i adımla, başlangıç yaşı yönün Jie sınırından gelir — iki yön iki
    ayrı dizidir, bkz. `_sans_dizisi` docstring'i).

Şema varsayılanları da sınanır: istemci cinsiyeti artık önseçili
göndermiyor; sunucu tarafındaki ``"female"`` varsayılanı aynı kusuru
arka kapıdan geri getirirdi.

Çalıştırma:  .venv\\Scripts\\python.exe -m pytest tests/test_bazi_cinsiyet.py -q
"""
from __future__ import annotations

import pytest

from services.bazi_service import get_bazi_chart

#: 1990 = Geng (yang) yılı: erkek → ileri, kadın → geri. Yang yıl seçildi ki
#: "kadın sayma" kusuru ölçülebilir olsun — yin yılda kadın ileri gider ve
#: erkekle karışmazdı ama eski kusur yine kadın dizisini verirdi.
DOGUM = dict(year=1990, month=5, day=12, hour=14, minute=30, city="Istanbul")


def _harita(cinsiyet: str | None = None) -> dict:
    if cinsiyet is None:
        return get_bazi_chart(**DOGUM)
    return get_bazi_chart(**DOGUM, gender=cinsiyet)


# ---------------------------------------------------------------------------
# Bilinmeyen cinsiyet
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("cinsiyet", ["unspecified", "other", "", "x"])
def test_bilinmeyen_cinsiyette_yon_BILINMIYOR(cinsiyet):
    chart = _harita(cinsiyet)

    assert chart["luck_direction_known"] is False
    assert chart["luck_direction"] is None, "yön uyduruldu"
    assert chart["luck_pillars"] == [], "tek yönlü dizi 'senin dönemlerin' diye sunuldu"
    assert chart["luck_start"] is None
    assert chart["current_luck_index"] is None
    assert chart["gender"] == "unspecified"
    assert "luck_direction_unknown" in chart["note_keys"]
    assert "luck_direction_yin" not in chart["note_keys"], (
        "eski anahtar bir VARSAYIMI beyan ediyordu; artık varsayım yok")


def test_eski_davranis_unspecified_KADIN_SAYILMAZ():
    """Kırmızı tarafı: unspecified'ın çıktısı kadının çıktısıyla ÇAKIŞMAMALI.

    Eski motor ikisine birebir aynı sözlüğü döndürüyordu (gender "female",
    yön "backward", aynı sekiz dönem).
    """
    bilinmeyen = _harita("unspecified")
    kadin = _harita("female")

    assert kadin["luck_direction"] == "backward"  # yang yıl + kadın
    assert bilinmeyen["gender"] != kadin["gender"]
    assert bilinmeyen["luck_direction"] != kadin["luck_direction"]
    assert bilinmeyen["luck_pillars"] != kadin["luck_pillars"]


def test_adaylar_IKI_yonu_de_tasir_ve_bilinen_cinsiyetin_dizisiyle_birebir():
    """Yön bilinmeyince dönemler ATILMAZ, iki aday olarak taşınır.

    Adayların doğruluğu bilinen cinsiyetlerin dizileriyle ölçülür: yang
    yılda erkek = ileri, kadın = geri; aday diziler bunlarla birebir aynı
    olmalı — başlangıç yaşı dahil (ileri/geri Jie mesafeleri farklı).
    """
    bilinmeyen = _harita("unspecified")
    erkek = _harita("male")
    kadin = _harita("female")
    adaylar = bilinmeyen["luck_pillar_candidates"]

    assert set(adaylar) == {"forward", "backward"}
    assert adaylar["forward"]["luck_pillars"] == erkek["luck_pillars"]
    assert adaylar["forward"]["luck_start"] == erkek["luck_start"]
    assert adaylar["backward"]["luck_pillars"] == kadin["luck_pillars"]
    assert adaylar["backward"]["luck_start"] == kadin["luck_start"]
    assert len(adaylar["forward"]["luck_pillars"]) == 8
    # İki yön gerçekten ayrışıyor: ilk dönem ay sütununun bir ilerisi
    # ya da bir gerisi.
    assert (adaylar["forward"]["luck_pillars"][0]["label"]
            != adaylar["backward"]["luck_pillars"][0]["label"])


# ---------------------------------------------------------------------------
# Bilinen cinsiyet — eski davranış korunur
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("cinsiyet,yon", [("male", "forward"),
                                          ("female", "backward"),
                                          ("erkek", "forward"),
                                          ("kadın", "backward")])
def test_bilinen_cinsiyette_yon_biliniyor(cinsiyet, yon):
    chart = _harita(cinsiyet)

    assert chart["luck_direction_known"] is True
    assert chart["luck_direction"] == yon
    assert len(chart["luck_pillars"]) == 8
    assert chart["luck_start"] is not None
    assert chart["luck_pillar_candidates"] is None, (
        "yön ölçüldüyse aday listesi bir anlam taşımaz")
    assert "luck_direction_unknown" not in chart["note_keys"]


# ---------------------------------------------------------------------------
# Varsayılanlar — "female" arka kapıdan geri gelmesin
# ---------------------------------------------------------------------------

def test_motor_varsayilani_unspecified():
    """Cinsiyet geçirmeyen çağıran (ör. chart_context boş dize) yön almaz."""
    chart = _harita(None)
    assert chart["gender"] == "unspecified"
    assert chart["luck_direction_known"] is False


def test_istek_semalari_cinsiyeti_onsecili_VERMEZ():
    """İki Pydantic şemanın varsayılanı: /reports BirthData ve /people.

    İstemci alanı göndermezse sunucu "female" yazıyordu; o değer aşağıda
    motora gidip kadın kuralıyla yön üretiyordu.
    """
    from api.people import PersonRequest
    from api.reports import BirthData

    assert BirthData(year=1990, month=5, day=12).gender == "unspecified"
    assert PersonRequest(birth_date="1990-05-12",
                         birth_city="Istanbul").gender == "unspecified"

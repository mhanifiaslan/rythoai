"""BaZi motoru altın harita vektörleri (Revize B0).

Bu dosyadan önce motorun ARİTMETİĞİNİ hiçbir test doğrulamıyordu — yalnız
dil izolasyonu test ediliyordu. Beş Kaplan tablosunda tek bir indeks kayması
hiçbir istisna üretmez; yalnızca herkesin ay sütunu sessizce yanlış olur.

ALTIN DEĞER KURALI: her vektör iki bağımsız kaynakla doğrulanmadan
dondurulmaz; kaynak, vektörün yanına yorum olarak yazılır. "Test var ama
yanlış değeri kilitliyor" durumunun tek panzehiri bu.

Şehirler gazetteer'den seçilir (geo_service._GAZETTEER) — GeoNames ağına
düşülmez, testler çevrimdışı koşar.

B1'den itibaren saat dalı ve 23:00 gün-devri kararı GERÇEK GÜNEŞ ZAMANI ile
verilir (boylam + Zaman Denklemi). `TestSaatVeGunDevri` beklenenleri TST'ye
göredir; el hesabı her vektörün yanındadır.
"""
from __future__ import annotations

import datetime as dt

import pytest

from services import bazi_service
from services.bazi_service import get_bazi_chart


def _sutun(chart, ad):
    p = chart["pillars"][ad]
    return (p["stem"]["pinyin"], p["branch"]["pinyin"])


# --------------------------------------------------------------------------
# Gün çapası — 60'lık döngü
# --------------------------------------------------------------------------

class TestGunCapasi:
    def test_prc_kurulus_gunu_jiazi(self):
        # 1949-10-01: motorun kendi docstring iddiası VE tarihsel olarak
        # bilinen 甲子 günü (ÇHC kuruluş günü — yaygın almanak kaydı).
        # İkinci kaynak: 1900-01-01=JiaXu çapasından el hesabı
        # (18170 gün + 10) % 60 = 0 → JiaZi.
        chart = get_bazi_chart(1949, 10, 1, 12, 0, city="Beijing",
                               gender="male")
        assert _sutun(chart, "day") == ("Jia", "Zi")

    def test_milenyum_gunu_wuwu(self):
        # 2000-01-01: yayımlanmış daimi takvimlerde 戊午 (WuWu) günü.
        # İkinci kaynak: çapadan el hesabı (36524 + 10) % 60 = 54.
        chart = get_bazi_chart(2000, 1, 1, 12, 0, city="Istanbul",
                               gender="female")
        assert _sutun(chart, "day") == ("Wu", "Wu")

    def test_milenyum_yili_hala_1999(self):
        # 1 Ocak Li Chun'dan ÖNCE: yıl sütunu 1999 = JiMao (己卯, tavşan).
        # Kaynak: (1999-4)%10=5 Ji, %12=3 Mao; 1999 yaygın olarak Tavşan yılı.
        chart = get_bazi_chart(2000, 1, 1, 12, 0, city="Istanbul",
                               gender="female")
        assert _sutun(chart, "year") == ("Ji", "Mao")
        assert chart["zodiac_animal"] == "rabbit"


# --------------------------------------------------------------------------
# Li Chun yıl sınırı
# --------------------------------------------------------------------------

class TestLiChunSiniri:
    # Li Chun 1984 ≈ 4 Şubat akşam geç saat (Pekin, ~23:19) — Güneş 315°.
    # Vektörler sınırın iki yanına 10+ saat payla konur ki "anın dakikası"
    # kaynaklar arasında oynasa da test kararlı kalsın.

    def test_li_chun_oncesi_onceki_yil(self):
        # 4 Şubat 1984 sabahı: hâlâ 1983 = GuiHai (癸亥, domuz) yılı.
        chart = get_bazi_chart(1984, 2, 4, 10, 0, city="Beijing",
                               gender="male")
        assert _sutun(chart, "year") == ("Gui", "Hai")
        assert chart["zodiac_animal"] == "pig"

    def test_li_chun_sonrasi_yeni_yil(self):
        # 5 Şubat 1984: 60'lık döngünün başı JiaZi (甲子, sıçan) yılı.
        chart = get_bazi_chart(1984, 2, 5, 10, 0, city="Beijing",
                               gender="male")
        assert _sutun(chart, "year") == ("Jia", "Zi")
        assert chart["zodiac_animal"] == "rat"

    def test_aralik_ayinda_yil_geri_alinmaz(self):
        # Boylam Aralık sonunda da [270,315) aralığındadır; koddaki
        # `month <= 2` koruması olmasa yıl yanlışlıkla geri alınırdı.
        # 25 Aralık 1983 → yıl yine 1983 GuiHai.
        chart = get_bazi_chart(1983, 12, 25, 12, 0, city="Istanbul",
                               gender="female")
        assert _sutun(chart, "year") == ("Gui", "Hai")


# --------------------------------------------------------------------------
# Ay sütunu — Beş Kaplan ve Jie sınırı
# --------------------------------------------------------------------------

class TestAySutunu:
    def test_jia_yilinin_ilk_ayi_bingyin(self):
        # Beş Kaplan: Jia/Ji yılı → ilk ay Bing Yin (丙寅). Klasik tablo;
        # ikinci kaynak: five_tigers[0]=2 → Bing, ay 1 dalı Yin.
        chart = get_bazi_chart(1984, 2, 5, 10, 0, city="Beijing",
                               gender="male")
        assert _sutun(chart, "month") == ("Bing", "Yin")

    def test_jing_zhe_oncesi_yin_ayi(self):
        # Jing Zhe (345°) ≈ 5-6 Mart; 3 Mart güvenli payla ÖNCE → hâlâ Yin ayı.
        chart = get_bazi_chart(1984, 3, 3, 12, 0, city="Beijing",
                               gender="male")
        assert _sutun(chart, "month") == ("Bing", "Yin")

    def test_jing_zhe_sonrasi_mao_ayi(self):
        # 8 Mart güvenli payla SONRA → ikinci ay DingMao (丁卯).
        chart = get_bazi_chart(1984, 3, 8, 12, 0, city="Beijing",
                               gender="male")
        assert _sutun(chart, "month") == ("Ding", "Mao")


# --------------------------------------------------------------------------
# Saat sütunu + 23:00 gün devri — B1'de TST'ye göre güncellenecek sınıf
# --------------------------------------------------------------------------

class TestSaatVeGunDevri:
    # TST el hesabı (İstanbul, Haziran 1990, duvar = UTC+3 yaz saati):
    # boylam 28.9784° → Güneş'ten +115.9 dk (UTC'ye göre); duvara göre
    # 115.9 − 180 = −64.1 dk; EoT ~15 Haziran ≈ −0.3 dk → toplam ≈ −64 dk.

    def test_tst_saat_dalini_degistirir(self):
        # Duvar 14:00 → güneş ≈ 12:56: dal Wei DEĞİL Wu. Beş Sıçan:
        # Bing/Xin günü saatler WuZi'den başlar → Wu saati = JiaWu.
        # (TST'siz eski davranış YiWei üretiyordu — düzeltmenin kanıtı.)
        chart = get_bazi_chart(1990, 6, 15, 14, 0, city="Istanbul",
                               gender="male")
        assert _sutun(chart, "day") == ("Xin", "Hai")
        assert _sutun(chart, "hour") == ("Jia", "Wu")
        assert -75 <= chart["tst_offset_minutes"] <= -55

    def test_tst_gun_devrini_iptal_eder(self):
        # Duvar 23:30 → güneş ≈ 22:26: gün DEVRİLMEZ (XinHai kalır),
        # saat Hai. Beş Sıçan: Xin günü → Hai saati JiHai.
        # Duvar saatiyle karar verilseydi ertesi günün RenZi'si çıkardı.
        chart = get_bazi_chart(1990, 6, 15, 23, 30, city="Istanbul",
                               gender="male")
        assert _sutun(chart, "day") == ("Xin", "Hai")
        assert _sutun(chart, "hour") == ("Ji", "Hai")

    def test_meridyene_yakin_sehirde_devir_yasanir(self):
        # Pekin boylamı (116.4°) dilim meridyenine (120°) yakın: sapma
        # ≈ −14 dk. 23:30 → güneş ≈ 23:16 → gün YİNE devrilir (geç Zi).
        # YIL SEÇİMİ BİLİNÇLİ: Çin 1986-1991 arası yaz saati uyguladı
        # (duvar UTC+9 → sapma −75 olurdu); 1995'te DST yok — tzdata'nın
        # tarihsel doğruluğu ilk taslakta tam bu vektörü düzeltti.
        # 16 Haziran 1995 = WuYin (çapadan: 34864 gün + 10 ≡ 14).
        # Wu günü → Zi saati RenZi (Beş Sıçan: Wu/Gui → RenZi başlar).
        chart = get_bazi_chart(1995, 6, 15, 23, 30, city="Beijing",
                               gender="male")
        assert _sutun(chart, "day") == ("Wu", "Yin")
        assert _sutun(chart, "hour") == ("Ren", "Zi")

    def test_amsterdam_kis_devir_iptali(self):
        # Amsterdam (4.90°D, CET +1, Ocak'ta DST yok): boylam 19.6 − 60 =
        # −40.4 dk; EoT 10 Ocak ≈ −7.3 dk → toplam ≈ −48 dk.
        # 23:30 duvar → güneş ≈ 22:42 → devir YOK: 10 Ocak 1995 = XinChou
        # (çapadan: 34707 gün + 10 ≡ 37). Xin günü → Hai saati JiHai.
        chart = get_bazi_chart(1995, 1, 10, 23, 30, city="Amsterdam",
                               gender="female")
        assert _sutun(chart, "day") == ("Xin", "Chou")
        assert _sutun(chart, "hour") == ("Ji", "Hai")


class TestZamanDenklemi:
    # `swe.time_equ` işaret/birim kilidi: gün cinsinden, görünür − ortalama.
    # Kaynak: standart EoT tablosu (Kasım başı +16.4 dk, Şubat ortası −14.2).
    # İşaret ters okunursa tüm saat sütunları sessizce 30 dk'ya kadar kayar.

    def test_kasim_gunes_ileri(self):
        _, sapma = bazi_service._true_solar_time(
            dt.datetime(2000, 11, 3, 12, 0, tzinfo=dt.timezone.utc), lng=0.0)
        assert 15 <= sapma <= 18

    def test_subat_gunes_geri(self):
        _, sapma = bazi_service._true_solar_time(
            dt.datetime(2000, 2, 11, 12, 0, tzinfo=dt.timezone.utc), lng=0.0)
        assert -16 <= sapma <= -12


class TestSaatBilinmiyor:
    def test_uc_sutun_modu(self):
        # hour=None: saat sütunu HİÇ kurulmaz — 12:00 uydurup Wu saati
        # üretmek, ölçmediğini ölçmüş gibi göstermekti (Revize B1).
        chart = get_bazi_chart(1990, 5, 12, None, 0, city="Istanbul",
                               gender="female")
        assert chart["pillars"]["hour"] is None
        assert "hour" not in chart["ten_gods"]
        assert chart["hour_known"] is False
        assert sum(chart["element_distribution"].values()) == \
            pytest.approx(6.0, abs=0.05)
        assert "hour_unknown" in chart["note_keys"]
        assert chart["luck_start_uncertainty_months"] == 4
        assert chart["solar_time"] is None

    def test_gun_ve_yil_sutunlari_yine_dogru(self):
        # Saatsiz modda diğer üç sütun aynı kalmalı (iç hesap gün ortası).
        saatli = get_bazi_chart(1990, 5, 12, 14, 30, city="Istanbul",
                                gender="female")
        saatsiz = get_bazi_chart(1990, 5, 12, None, 0, city="Istanbul",
                                 gender="female")
        for ad in ("year", "month", "day"):
            assert _sutun(saatli, ad) == _sutun(saatsiz, ad)


# --------------------------------------------------------------------------
# Şans sütunları — yön ve yapı
# --------------------------------------------------------------------------

class TestSansSutunlari:
    # Klasik kural: yang yıl + erkek → ileri, yang + kadın → geri;
    # yin yıl + erkek → geri, yin + kadın → ileri.

    @pytest.mark.parametrize("yil,cinsiyet,beklenen", [
        (1984, "male", "forward"),    # Jia (yang) + erkek
        (1984, "female", "backward"),
        (1985, "male", "backward"),   # Yi (yin) + erkek
        (1985, "female", "forward"),
    ])
    def test_yon_dort_kombinasyon(self, yil, cinsiyet, beklenen):
        chart = get_bazi_chart(yil, 6, 1, 12, 0, city="Istanbul",
                               gender=cinsiyet)
        assert chart["luck_direction"] == beklenen

    def test_sekiz_donem_ve_ardisik_yaslar(self):
        chart = get_bazi_chart(1990, 5, 12, 14, 30, city="Istanbul",
                               gender="female")
        lp = chart["luck_pillars"]
        assert len(lp) == 8
        for onceki, sonraki in zip(lp, lp[1:]):
            assert sonraki["from_age"] == onceki["to_age"] + 1
            assert sonraki["from_year"] == onceki["to_year"] + 1

    def test_jie_sinirina_yakin_dogum_ay_cozunurlugu(self):
        # 3 Mart 1984 (Jing Zhe'ye ~2 gün) + JiaZi yang yıl + erkek →
        # ileri sayım: klasik dönüşümle 1 gün = 4 ay → 0 yıl, ~8-10 ay.
        # Eski round(days/3) burada "1 yaş" derdi — ay bilgisi yoktu.
        chart = get_bazi_chart(1984, 3, 3, 12, 0, city="Beijing",
                               gender="male")
        ls = chart["luck_start"]
        assert ls["years"] == 0
        assert 7 <= ls["months"] <= 11
        assert ls["date"].startswith("1984-")
        assert chart["luck_pillars"][0]["from_year"] == 1984

    def test_liu_nian_sabit_tarihlerle(self):
        # Zamana bağlı altın değer YOK: yardımcı fonksiyon sabit tarihle
        # test edilir. 2026-08-04 → BingWu (至 2026 At yılı); 2026-01-15
        # Li Chun'dan önce → 2025 = YiSi.
        import datetime as dtm
        p1 = bazi_service.year_pillar_for_date(dtm.date(2026, 8, 4))
        assert (p1["stem"]["pinyin"], p1["branch"]["pinyin"]) == \
            ("Bing", "Wu")
        p2 = bazi_service.year_pillar_for_date(dtm.date(2026, 1, 15))
        assert (p2["stem"]["pinyin"], p2["branch"]["pinyin"]) == \
            ("Yi", "Si")

    def test_guncel_donem_isaretcisi(self):
        # 1990 doğumlu için bugün bir Da Yun dönemi aktif olmalı ve
        # işaretçi takvim yılını kapsayan dönemi göstermeli.
        chart = get_bazi_chart(1990, 5, 12, 14, 30, city="Istanbul",
                               gender="female")
        idx = chart["current_luck_index"]
        assert idx is not None
        lp = chart["luck_pillars"][idx]
        import datetime as dtm
        assert lp["from_year"] <= dtm.date.today().year <= lp["to_year"]
        assert chart["current_year_pillar"]["ten_god"]["name"]


# --------------------------------------------------------------------------
# On Tanrı ilişki tablosu
# --------------------------------------------------------------------------

class TestOnTanri:
    def test_klasik_ornekler(self):
        # Zi Ping sınıflandırması — klasik ders kitabı örnekleri:
        # Jia (Yang ahşap) için Xin (Yin metal) = Zheng Guan (doğru yönetici),
        # Ren (Yang su) = Pian Yin (dolaylı kaynak),
        # Yi (Yin ahşap) = Jie Cai (omuzdaş/rakip).
        assert bazi_service._ten_god(0, 7)["name"] == "Zheng Guan"
        assert bazi_service._ten_god(0, 8)["name"] == "Pian Yin"
        assert bazi_service._ten_god(0, 1)["name"] == "Jie Cai"


# --------------------------------------------------------------------------
# Değişmezler ve beyanlar
# --------------------------------------------------------------------------

class TestGizliKokler:
    def test_her_dal_toplam_bir_dagitir(self):
        # Ağırlık korunumu: dal başına 1.0 — dağılım toplamı 8.0 değişmezi
        # buna dayanıyor. Tablodaki tek bir yazım hatası burada yakalanır.
        for dal_idx, kokler in bazi_service.HIDDEN_STEMS.items():
            toplam = sum(w for _, w in kokler)
            assert toplam == pytest.approx(1.0), (
                f"dal {dal_idx} toplam {toplam}")

    def test_yin_dalinin_kokleri(self):
        # Kanonik tablo: 寅 = Jia(ana), Bing, Wu. Ana qi önce gelmeli —
        # dalın On Tanrısı ana qi'den okunuyor.
        kokler = bazi_service.HIDDEN_STEMS[2]
        assert [s for s, _ in kokler] == [0, 2, 4]
        assert kokler[0][1] == 0.6

    def test_haritada_gizli_kokler_ve_dal_tanrisi(self):
        # 15 Haziran 1990 (XinHai günü): gün dalı Hai = Ren(0.7) + Jia(0.3).
        # Dalın On Tanrısı ana qi'den: Xin (Yin metal) SUYU üretir
        # (i_produce) ve Ren Yang'dır (farklı polarite) → Shang Guan.
        chart = get_bazi_chart(1990, 6, 15, 14, 0, city="Istanbul",
                               gender="male")
        dal = chart["pillars"]["day"]["branch"]
        assert [h["pinyin"] for h in dal["hidden"]] == ["Ren", "Jia"]
        assert dal["ten_god"]["name"] == "Shang Guan"

    def test_duz_sayimin_gordugu_eksik_agirlikli_sayimda_var(self):
        # Saf fonksiyon üzerinde kurgu: Shen (Ren 0.3) + Chen (Gui 0.1)
        # dallarında su YALNIZ gizli köklerde. Düz element sayımı "su yok"
        # derdi; ağırlıklı sayım 0.4 bulur ve 0.35 eşiği onu VAR sayar.
        pillars = {
            "a": bazi_service._pillar(0, 8),   # Jia Shen
            "b": bazi_service._pillar(2, 4),   # Bing Chen
        }
        bazi_service.attach_hidden_stems(pillars, day_stem=0)
        dagilim = bazi_service.element_distribution_for(pillars)
        assert dagilim["water"] == pytest.approx(0.4)
        assert dagilim["water"] >= bazi_service.MISSING_THRESHOLD


class TestGucHukmu:
    """B3: mevsimsel durum matrisi + Day Master gücü + yong shen.

    Altın haritalar KURGULANMIŞTIR (saf fonksiyon üzerinden): klasik
    hükmün tartışmasız olduğu uç örnekler. Tarihten harita avlamak yerine
    sütunlar doğrudan kurulur — test neyi ölçtüğünü tam bilir.
    """

    @staticmethod
    def _degerlendir(pillars):
        from services import bazi_strength
        bazi_service.attach_hidden_stems(pillars, day_stem=pillars["day"]
                                         ["stem"]["index"])
        dagilim = bazi_service.element_distribution_for(pillars)
        return bazi_strength.assess_strength(
            pillars, pillars["day"]["stem"]["index"], dagilim)

    def test_mevsim_matrisi_kuraldan_turetilir(self):
        # Matris tek kuraldan çıkar: mevsim=hükümran, ürettiği=destekli,
        # üreten=dinlenen, kontrol eden=kısıtlı, kontrol ettiği=sönük.
        from services.bazi_strength import season_state
        assert season_state("wood", "wood") == "wang"
        assert season_state("wood", "fire") == "xiang"   # ağaç ateşi üretir
        assert season_state("wood", "water") == "xiu"    # su ağacı üretir
        assert season_state("wood", "metal") == "qiu"    # metal ağacı keser
        assert season_state("wood", "earth") == "si"     # ağaç toprağı yarar

    def test_bariz_guclu_harita(self):
        # Jia (ağaç) DM, Mao (ilkbahar) ayında, kökler ağaç/su dolu:
        # klasik hüküm tartışmasız GÜÇLÜ.
        pillars = {
            "year": bazi_service._pillar(8, 0),   # Ren Zi (su/su)
            "month": bazi_service._pillar(1, 3),  # Yi Mao (ağaç/ağaç)
            "day": bazi_service._pillar(0, 2),    # Jia Yin (ağaç kökü)
            "hour": bazi_service._pillar(9, 11),  # Gui Hai (su/su)
        }
        sonuc = self._degerlendir(pillars)
        assert sonuc["verdict"] == "strong"
        assert sonuc["season_state"] == "wang"

    def test_bariz_zayif_harita(self):
        # Jia (ağaç) DM, You (sonbahar/metal) ayında, çevre metal/toprak:
        # klasik hüküm tartışmasız ZAYIF.
        pillars = {
            "year": bazi_service._pillar(6, 8),   # Geng Shen (metal/metal)
            "month": bazi_service._pillar(7, 9),  # Xin You (metal/metal)
            "day": bazi_service._pillar(0, 10),   # Jia Xu (toprak dalı)
            "hour": bazi_service._pillar(4, 1),   # Wu Chou (toprak/toprak)
        }
        sonuc = self._degerlendir(pillars)
        assert sonuc["verdict"] == "weak"
        assert sonuc["season_state"] == "si"

    def test_dokum_toplami_skora_esit(self):
        # Bileşen dökümü hükmün TAM açıklaması olmalı: parçaların toplamı
        # destek+yük toplamına eşit — döküm eksik kalırsa "neden" sorusu
        # cevapsız kalır.
        chart = get_bazi_chart(1990, 5, 12, 14, 30, city="Istanbul",
                               gender="female")
        s = chart["strength"]
        toplam = sum(c["points"] for c in s["components"])
        assert toplam == pytest.approx(s["support"] + s["burden"], abs=0.5)

    def test_guclu_bosaltan_zayif_destekleyen_ister(self):
        # Yong shen denge kuralı: güçlüye boşaltan/servet, zayıfa kaynak.
        chart_g = self._degerlendir({
            "year": bazi_service._pillar(8, 0),
            "month": bazi_service._pillar(1, 3),
            "day": bazi_service._pillar(0, 2),
            "hour": bazi_service._pillar(9, 11),
        })
        assert "wood" not in chart_g["favorable_elements"]
        assert "wood" in chart_g["unfavorable_elements"]

        chart_z = self._degerlendir({
            "year": bazi_service._pillar(6, 8),
            "month": bazi_service._pillar(7, 9),
            "day": bazi_service._pillar(0, 10),
            "hour": bazi_service._pillar(4, 1),
        })
        assert chart_z["favorable_elements"] == ["water", "wood"]

    def test_kis_haritasi_ates_ister(self):
        # İklim ekseni (Qiong Tong Bao Jian'ın tartışmasız çekirdeği):
        # Zi (kış) ayı → soğuk → düzenleyici ateş.
        pillars = {
            "year": bazi_service._pillar(8, 0),
            "month": bazi_service._pillar(9, 0),   # Gui Zi — kış
            "day": bazi_service._pillar(0, 2),
            "hour": bazi_service._pillar(9, 11),
        }
        sonuc = self._degerlendir(pillars)
        assert sonuc["climate"] == "cold"
        assert sonuc["climate_element"] == "fire"

    def test_kapsam_beyani_var(self):
        # Kombinasyonlar v1'de hesapta yok — bu SÖYLENMEK zorunda.
        chart = get_bazi_chart(1990, 5, 12, 14, 30, city="Istanbul",
                               gender="female")
        assert chart["strength"]["scope_note_key"] == "combinations_ignored"


class TestShenSha:
    """B4: beş yıldız + Kong Wang — tablo ve formül doğrulaması."""

    def test_kong_wang_alti_xun(self):
        # Formül 6 xun'un tamamında elle doğrulanmış klasik çiftleri
        # vermeli: JiaZi→Xu/Hai, JiaXu→Shen/You, JiaShen→Wu/Wei,
        # JiaWu→Chen/Si, JiaChen→Yin/Mao, JiaYin→Zi/Chou.
        from services.bazi_stars import void_branches
        beklenen = {0: (10, 11), 15: (8, 9), 23: (6, 7),
                    34: (4, 5), 45: (2, 3), 59: (0, 1)}
        for cycle, cift in beklenen.items():
            assert void_branches(cycle) == cift, f"xun {cycle}"

    def test_kurgulanmis_haritada_uc_yildiz(self):
        # JiaZi günü: Tian Yi hedefi Chou yıl dalında; su üçlüsünden (Zi)
        # Tao Hua hedefi You saatte, Yi Ma hedefi Yin ayda.
        from services.bazi_stars import find_shen_sha
        pillars = {
            "year": bazi_service._pillar(4, 1),   # Wu Chou
            "month": bazi_service._pillar(2, 2),  # Bing Yin
            "day": bazi_service._pillar(0, 0),    # Jia Zi
            "hour": bazi_service._pillar(5, 9),   # Ji You
        }
        bulgular = find_shen_sha(pillars, day_cycle=0)
        ozet = {(b["key"], b["pillar"]) for b in bulgular}
        assert ozet == {("tian_yi", "year"), ("tao_hua", "hour"),
                        ("yi_ma", "month")}

    def test_ayni_yildiz_ayni_sutunda_tekillesir(self):
        # Yukarıdaki haritada Chou'yu hem gün gövdesi (Jia) hem yıl
        # gövdesi (Wu) işaret eder — kayıt TEK olmalı: liste okuma
        # yüzeyi, kanıt defteri değil.
        from services.bazi_stars import find_shen_sha
        pillars = {
            "year": bazi_service._pillar(4, 1),
            "month": bazi_service._pillar(2, 2),
            "day": bazi_service._pillar(0, 0),
            "hour": bazi_service._pillar(5, 9),
        }
        bulgular = find_shen_sha(pillars, day_cycle=0)
        tian_yi = [b for b in bulgular if b["key"] == "tian_yi"]
        assert len(tian_yi) == 1

    def test_bos_liste_mesru(self):
        # Hiçbir yıldız düşmeyen harita: boş liste bir hata değil,
        # dürüst bir sonuçtur (UI da öyle gösterir).
        from services.bazi_stars import find_shen_sha
        pillars = {
            "year": bazi_service._pillar(2, 4),   # Bing Chen
            "month": bazi_service._pillar(3, 6),  # Ding Wu
            "day": bazi_service._pillar(6, 10),   # Geng Xu
            "hour": bazi_service._pillar(4, 0),   # Wu Zi
        }
        assert find_shen_sha(pillars, day_cycle=46) == []

    def test_motor_ciktisinda_yildizlar(self):
        chart = get_bazi_chart(1990, 5, 12, 14, 30, city="Istanbul",
                               gender="female")
        from services.bazi_stars import STAR_KEYS
        for b in chart["shen_sha"]:
            assert b["key"] in STAR_KEYS
            assert {"key", "basis", "branch", "pillar"} <= set(b)


class TestDegismezler:
    def test_element_dagilimi_sekiz_karakter(self):
        # B2'den beri ağırlıklı: gövdeler 1.0 + dal başına gizli kök 1.0.
        chart = get_bazi_chart(1990, 5, 12, 14, 30, city="Istanbul",
                               gender="female")
        assert sum(chart["element_distribution"].values()) == \
            pytest.approx(8.0, abs=0.05)

    def test_calc_version_var(self):
        chart = get_bazi_chart(1990, 5, 12, 14, 30, city="Istanbul",
                               gender="female")
        assert chart["calc_version"] == "5"

    def test_ikili_cinsiyette_cinsiyet_beyani_yok(self):
        for cinsiyet in ("male", "female"):
            chart = get_bazi_chart(1990, 5, 12, 14, 30, city="Istanbul",
                                   gender=cinsiyet)
            assert "luck_direction_unknown" not in chart["note_keys"]
            assert chart["luck_direction_known"] is True

    def test_other_cinsiyet_yon_HESAPLANMAZ_ve_beyanla_gelir(self):
        # Bu test eskiden "other → yin kuralıyla GERİ" diye kilitliyordu:
        # bir varsayımı beyan etmek onu ölçüm yapmaz. İkili olmayan
        # cinsiyette yön ÖLÇÜLEMEZ; motor yön uydurmaz, yokluğu beyan eder
        # (ayrıntı: tests/test_bazi_cinsiyet.py).
        chart = get_bazi_chart(1990, 5, 12, 14, 30, city="Istanbul",
                               gender="other")
        assert "luck_direction_unknown" in chart["note_keys"]
        assert "luck_direction_yin" not in chart["note_keys"]
        # 1990 = Geng (yang) yılı; eski kusur "backward" yazardı.
        assert chart["luck_direction"] is None

    def test_taninmayan_sehir_beyanla_gelir(self):
        # Gazetteer + GeoNames çözemezse İstanbul boylamına düşülür; TST
        # yanlış boylamla hatayı BÜYÜTEBİLİR — düşüş beyansız kalamaz.
        chart = get_bazi_chart(1990, 5, 12, 14, 30,
                               city="Hicbiryerkoyu-XYZ", gender="female")
        assert "tst_fallback_city" in chart["note_keys"]

"""`RYTHO_USD_TRY` makul bant kapısının bekçisi (F3-3).

Bu dosya `test_admin_users.py`'den AYRI duruyor: oradaki kur testi
"bozuk değer varsayılana DÜŞMEZ" değişmezini koruyor, burada korunan
değişmez ise onun tam sınırı — "basamağı kaymış AMA pozitif bir sayı
varsayılana DÜŞER". İkisi aynı fonksiyonun iki farklı girdi sınıfı ve
karıştırıldığında biri sessizce diğerini gevşetir.

Neden bekçi: kur panelde ₺ ödülü $'a çeviren tek çarpan. Bant olmadan
`RYTHO_USD_TRY=420` (fazladan sıfır) ₺30 ödülü $0,07'ye, `4,2` (ondalık
ayracı kayması) $7,14'e düşürüyordu — biri programı bedava, diğeri
zararlı gösterir ve HİÇBİR yerde hata görünmez. Ölçülmeyen söylenmez
ilkesinin buradaki karşılığı: kazara girilmiş bir kurla hesaplanmış sayı
"marj" adıyla sunulmaz.
"""
from __future__ import annotations

import logging
import pathlib
import re

import pytest

from services import admin_service

#: Deploy betiği — bekçi onu METİN olarak okur, çalıştırmaz.
_DEPLOY_BETIGI = (pathlib.Path(__file__).resolve().parents[2]
                  / "infra" / "deploy-backend.ps1")


def test_bant_disi_pozitif_deger_varsayilana_duser(monkeypatch, caplog):
    """Bandın dışındaki POZİTİF değer = yazım hatası → varsayılan + uyarı.

    Somut iki senaryo ölçülmüş kırılmalardır: `420` (fazladan sıfır) ve
    `4,2` (ondalık ayracı kayması). İkisi de "sayıya çevrilebiliyor ve
    pozitif" olduğu için eski kapıdan sessizce geçiyordu.
    """
    for bozuk in ("420", "4,2", "4.2", "0.5", "1000", "201", "4,99"):
        monkeypatch.setenv("RYTHO_USD_TRY", bozuk)
        caplog.clear()
        with caplog.at_level(logging.WARNING, logger=admin_service.__name__):
            kur = admin_service._kur_oku()
        assert kur == admin_service.USD_TRY_DEFAULT, bozuk
        # Uyarı ŞART: sessiz bir düzeltme, operatörün yazdığı kurun
        # yürürlükte olduğunu sanmasına yol açar — kapının kendisi
        # görünmez olurdu.
        assert any("makul bandın dışında" in k.getMessage()
                   for k in caplog.records), bozuk


def test_bant_ici_deger_oldugu_gibi_kullanilir(monkeypatch, caplog):
    """Bandın İÇİ dokunulmaz: gerçek bir değer kaybı kapıya takılmamalı.

    Bant bir tahmin aralığı olsaydı 60/80/120 gibi değerler "fazla
    yüksek" diye ezilirdi ve kapı, önlediği hatadan büyük bir hata
    üretirdi — kur gerçekten oynadığında panel marjı yanlışa kayardı.
    Sınırlar DAHİL (5 ve 200) olduğu da burada sabitleniyor.
    """
    for deger, beklenen in (("5", 5.0), ("42", 42.0), ("42,5", 42.5),
                            ("60", 60.0), ("120", 120.0), ("200", 200.0)):
        monkeypatch.setenv("RYTHO_USD_TRY", deger)
        caplog.clear()
        with caplog.at_level(logging.WARNING, logger=admin_service.__name__):
            assert admin_service._kur_oku() == pytest.approx(beklenen), deger
        assert not [k for k in caplog.records
                    if "makul bandın dışında" in k.getMessage()], deger


def test_kur_olmayan_deger_bandin_disina_sayilmaz(monkeypatch, caplog):
    """`0`, negatif ve çöp değer BANT yoluna girmez → 0.0 ("bilinmiyor").

    Sıra load-bearing: pozitiflik kapısı bandın ÖNÜNDE. 0 ve −42 de
    teknik olarak bandın dışındadır; bant önce çalışsaydı ikisi de
    varsayılana düşer ve hiç ölçülmemiş bir marj ölçülmüş gibi
    sunulurdu. `test_admin_users.py`'deki eşi bu değerlerin sonucunu
    koruyor, bu test hangi KAPIDAN geçtiklerini koruyor.
    """
    for kur_olmayan in ("0", "-42", "kirk-iki"):
        monkeypatch.setenv("RYTHO_USD_TRY", kur_olmayan)
        caplog.clear()
        with caplog.at_level(logging.WARNING, logger=admin_service.__name__):
            assert admin_service._kur_oku() == 0.0, kur_olmayan
        assert not [k for k in caplog.records
                    if "makul bandın dışında" in k.getMessage()], kur_olmayan


def test_bant_sabitleri_belgedeki_varsayimi_kapsar():
    """Varsayılan kur bandın İÇİNDE olmalı.

    Kendi varsayılanını reddeden bir kapı, bandın dışındaki değeri
    yine bandın dışındaki bir değere çevirirdi — kusur sessiz olurdu
    çünkü dönen sayı hâlâ "makul" görünür.
    """
    assert (admin_service.USD_TRY_MIN
            <= admin_service.USD_TRY_DEFAULT
            <= admin_service.USD_TRY_MAX)
    assert admin_service.USD_TRY_MIN < admin_service.USD_TRY_MAX


def test_deploy_bayragi_varsayilan_kurla_ayni_kalir():
    """`--set-env-vars` satırındaki `RYTHO_USD_TRY` = `USD_TRY_DEFAULT`.

    NEDEN bekçi: o bayrak MEVCUT değişkenlerin TAMAMINI değiştiriyor, yani
    satırı elle düzenleyen biri bayrağı düşürürse ya da belgedeki varsayım
    değişip `USD_TRY_DEFAULT` güncellenirken satır güncellenmezse Cloud
    Run'daki kur koddan SESSİZCE ayrılır: derleme başarılı, testler yeşil,
    yalnız paneldeki marj yanlış. `RYTHO_MIN_BUILD` yarası tam bu yüzden 34
    sürüm sürdü.

    ⚠️ Yorumlar önce ATILIYOR. Bayrağı ANLATAN yorum bloğu aynı dosyada ve
    içinde `RYTHO_USD_TRY=42` dizesi geçiyor; yorumlar atılmazsa bayrak
    komuttan silinse bile bekçi yeşil kalır — bu depoda aynı tuzak iki kez
    patladı (manifest kapısı ve davet sayfası testi).
    """
    satirlar = [s for s in _DEPLOY_BETIGI.read_text(encoding="utf-8").splitlines()
                if not s.lstrip().startswith("#")]
    env_satiri = [s for s in satirlar if "--set-env-vars" in s]
    assert len(env_satiri) == 1, "--set-env-vars satırı bulunamadı/tekil değil."
    eslesme = re.search(r"RYTHO_USD_TRY=([0-9]+(?:[.,][0-9]+)?)", env_satiri[0])
    assert eslesme, ("RYTHO_USD_TRY deploy betiğinin --set-env-vars satırında "
                     "YOK — elle verilen kur ilk deploy'da silinir.")
    assert (float(eslesme.group(1).replace(",", "."))
            == admin_service.USD_TRY_DEFAULT)

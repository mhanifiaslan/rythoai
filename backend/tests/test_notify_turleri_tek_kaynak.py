"""Bildirim türü listesi TEK gerçektir; kopyaları onunla aynı kalır.

NEDEN bu bekçi var (ölçüldü 2026-10-03): aynı küme depoda ALTI yerde
yaşıyordu ve 48-turunda `notify_runner.RUN_TYPES`a `circle` ile `winback`
eklendiğinde DÖRDÜ dörtte kaldı. Hiçbir test düşmedi. Üç somut sonuç:

* `api/admin.py` `_NotifyType` Literal'i yeni türleri kabul etmiyordu, yani
  operatör onları panelden ne prova edebiliyor ne kendine test
  gönderebiliyordu — uç 422 dönüyordu.
* `stats_service` ve `admin_service` `notify.{tür}` rollup'ını yalnız dört
  tür için topluyordu, yani iki yeni slot panelde HİÇ görünmüyordu.
* Sonuç, bu turun kendi dersinin yarım kalmasıydı: "zamanlanmış işler bir ay
  yeşil yalan söyledi" diye onarılan görünürlük, YENİ slotlar için yoktu.

Üç kopya artık `RUN_TYPES`tan türetiliyor (`_notify_turleri`). Dördüncüsü
(`Literal`) türetilemiyor çünkü FastAPI OpenAPI enum'unu statik tipten
üretiyor — o yüzden ELLE yazılı ve bu testle bağlı.

⚠️ Çapa SIRA DEĞİL KÜME: `Literal`ın yazım sırası OpenAPI çıktısında
görünür ama anlamı yok; sıraya bağlamak bu bekçiyi gereksiz kırılgan
yapardı. Buna karşılık kümedeki tek bir eksik ya da fazla tür GERÇEK bir
kusurdur ve yakalanır.
"""
from __future__ import annotations

import re
from pathlib import Path
import typing

from api import admin as admin_api
from services import admin_service, notify_runner, stats_service


def test_admin_literali_RUN_TYPES_ile_ayni_kumeyi_tasir():
    literal_turleri = set(typing.get_args(admin_api._NotifyType))
    assert literal_turleri == set(notify_runner.RUN_TYPES), (
        "api/admin.py::_NotifyType ile notify_runner.RUN_TYPES ayrıştı. "
        "Literal statik olduğu için ELLE güncellenmeli — eksik bir tür "
        "operatörün o slotu panelden prova etmesini 422 ile engeller.")


def test_turetilmis_kopyalar_RUN_TYPES_ile_ayni():
    """Üç kopya türetiliyor; bu test türetmenin GERÇEKTEN koştuğunu ölçer.

    Sabit bir tuple bırakılıp yorumda "türetiliyor" yazılması bu depoda
    yanlış gerekçe sayılır — bekçi o ihtimali kapatıyor.
    """
    beklenen = tuple(notify_runner.RUN_TYPES)
    assert admin_service._notify_turleri() == beklenen
    assert stats_service._notify_turleri() == beklenen


def test_panel_js_listesi_RUN_TYPES_ile_ayni_kumeyi_tasir():
    """Kümenin ALTINCI kopyası: yönetim panelinin vanilla-JS listesi.

    Panel bir derleme adımı olmadan çalışıyor, yani listeyi sunucudan
    türetmenin yolu ya bir API ucu ya da elle yazım. Elle yazım seçildi
    çünkü etiketler (Türkçe görünen adlar) panele ait, sunucuya değil —
    ama KÜME sunucuya ait ve burada çivileniyor.

    Bedeli ölçüldü: liste bir tur boyunca dörtte kaldı ve `circle`/`winback`
    koşuları panelde "—" diye çizildi, koşu türü seçicisinde hiç
    görünmediler. Yani operatör yeni slotları ne izleyebildi ne prova
    edebildi — bu turun kendi dersi ("zamanlanmış işler bir ay yeşil yalan
    söyledi") yeni slotlar için yarım kalıyordu.

    ⚠️ Çapa `deger:` alanı; etiket metnine BAKILMIYOR. Etiket panelin
    tasarım kararı ve değişmesi bu bekçiyi kırmamalı.
    """
    yol = (Path(__file__).resolve().parents[2] / "web" / "rytho-admin" /
           "gorunumler" / "bildirimler.js")
    kaynak = yol.read_text(encoding="utf-8")
    # Yorumlar ATILIR: bu bekçinin gerekçesi aynı dosyada ve içinde tür
    # adları geçiyor. Bu depoda bir şeyin varlığını/yokluğunu arayan bekçi
    # iki kez kendi yorumuna takıldı.
    govde = re.sub(r"//[^\n]*", "", kaynak)
    blok = re.search(r"var TURLER = \[(.*?)\];", govde, re.S)
    assert blok, "bildirimler.js içinde TURLER dizisi bulunamadı"
    bulunan = set(re.findall(r"deger:\s*'([a-z_]+)'", blok.group(1)))
    assert bulunan == set(notify_runner.RUN_TYPES), (
        f"Panel JS türleri {sorted(bulunan)} ile RUN_TYPES "
        f"{sorted(notify_runner.RUN_TYPES)} ayrıştı — eksik tür panelde "
        f"HİÇ görünmez ve koşuları '—' diye çizilir")


def test_yeni_slotlar_gercekten_listede():
    """48-turunun iki yeni slotu adıyla çivili.

    Küme karşılaştırması tek başına "ikisi de silinirse" sessiz kalır:
    `RUN_TYPES`tan da çıkarılırsa yukarıdaki iki test yine yeşil olur.
    Ürün kararı (K7 geri kazanım + Çevrem slotu) bu iki adı gerektiriyor.
    """
    for tur in ("circle", "winback"):
        assert tur in notify_runner.RUN_TYPES, (
            f"{tur} slotu RUN_TYPES'tan düşmüş — K7 geri kazanım merdiveni "
            f"ya da Çevrem slotu sessizce kapanmış olabilir")

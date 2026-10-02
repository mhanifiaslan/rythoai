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

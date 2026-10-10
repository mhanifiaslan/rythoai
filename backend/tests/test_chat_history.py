"""Sohbet arşivinin değişmezleri (Revize R4).

Kilit noktalar:

* `prepare` SENKRON ve ucuz — yanıtın döndürdüğü konu kimliği buradan
  gelir; yazım arka planda. Kimlik/yazım ayrışması yanlış kurulursa istemci
  var olmayan bir konuyu izler ve arşiv sessizce boş kalır.
* Konu dolunca DEVAM konusu açılır; istemci dönen kimliği izlediği için
  konuşma kesintisiz sürer.
* Temizlik mesajları ÖNCE siler — ters sıra yetim mesaj bırakır
  (faturalanır, `write: false` yüzünden sahibi de silemez).
"""
from __future__ import annotations

import datetime as dt

import pytest

from services import chat_history


class _Anlik:
    def __init__(self, data, ref=None):
        self._data = data
        self.reference = ref

    @property
    def exists(self):
        return self._data is not None

    def to_dict(self):
        return dict(self._data) if self._data else {}

    @property
    def id(self):
        return self.reference._yol.rsplit("/", 1)[1] if self.reference else ""


class _Doc:
    _sayac = 0

    def __init__(self, depo, yol):
        self._depo = depo
        self._yol = yol

    def get(self):
        return _Anlik(self._depo.get(self._yol), self)

    def set(self, data, merge=False):
        mevcut = dict(self._depo.get(self._yol) or {}) if merge else {}
        mevcut.update(data)
        self._depo[self._yol] = mevcut

    def delete(self):
        self._depo.pop(self._yol, None)

    def collection(self, ad):
        return _Koleksiyon(self._depo, f"{self._yol}/{ad}")

    @property
    def id(self):
        return self._yol.rsplit("/", 1)[1]


class _Koleksiyon:
    def __init__(self, depo, yol):
        self._depo = depo
        self._yol = yol

    def document(self, ad=None):
        if ad is None:
            _Doc._sayac += 1
            ad = f"oto{_Doc._sayac}"
        return _Doc(self._depo, f"{self._yol}/{ad}")

    def _docs(self):
        onek = self._yol + "/"
        return [
            _Doc(self._depo, yol) for yol in sorted(self._depo)
            if yol.startswith(onek) and "/" not in yol[len(onek):]
        ]

    def limit(self, n):
        parent = self

        class _Sinirli:
            def stream(self):
                return [d.get() for d in parent._docs()[:n]]

        return _Sinirli()

    def order_by(self, alan, direction="ASCENDING"):
        parent = self

        class _Sirali:
            def offset(self, n):
                docs = parent._docs()
                docs.sort(key=lambda d: str((d.get().to_dict() or {}).get(alan)),
                          reverse=(direction == "DESCENDING"))

                class _Akis:
                    def stream(self):
                        return [d.get() for d in docs[n:]]

                return _Akis()

        return _Sirali()


class _Client:
    def __init__(self, depo):
        self._depo = depo

    def collection(self, ad):
        return _Koleksiyon(self._depo, ad)

    def collection_group(self, ad):
        depo = self._depo

        class _Grup:
            def where(self, alan, op, deger):
                class _Sorgu:
                    def limit(self, n):
                        class _Akis:
                            def stream(self):
                                sonuc = []
                                for yol in sorted(depo):
                                    parcalar = yol.split("/")
                                    if len(parcalar) >= 2 and \
                                            parcalar[-2] == ad:
                                        veri = depo[yol]
                                        if veri.get(alan) and \
                                                veri[alan] < deger:
                                            sonuc.append(
                                                _Anlik(veri, _Doc(depo, yol)))
                                return sonuc[:n]
                        return _Akis()
                return _Sorgu()
        return _Grup()


@pytest.fixture()
def depo(monkeypatch):
    veriler: dict = {}
    monkeypatch.setattr(chat_history.firestore_client, "get_client",
                        lambda: _Client(veriler))
    return veriler


def _konu_yollari(depo, uid="u1"):
    onek = f"users/{uid}/conversations/"
    return [y for y in depo if y.startswith(onek)
            and "/" not in y[len(onek):]]


def test_yeni_konu_kimligi_senkron_ve_yazim_uyumlu(depo):
    hazir = chat_history.prepare("u1", None)
    assert hazir is not None and hazir.create

    chat_history.write_turn("u1", hazir, "Merhaba, işim hakkında?", "Selam!",
                            "tr")

    konu = depo[f"users/u1/conversations/{hazir.conversation_id}"]
    assert konu["messageCount"] == 2
    assert konu["title"].startswith("Merhaba")
    mesajlar = [y for y in depo
                if f"conversations/{hazir.conversation_id}/messages/" in y]
    assert len(mesajlar) == 2


def test_devam_ayni_konuya_yazar(depo):
    h1 = chat_history.prepare("u1", None)
    chat_history.write_turn("u1", h1, "ilk", "cevap", "tr")

    h2 = chat_history.prepare("u1", h1.conversation_id)
    assert not h2.create
    assert h2.conversation_id == h1.conversation_id
    chat_history.write_turn("u1", h2, "ikinci", "cevap2", "tr")

    konu = depo[f"users/u1/conversations/{h1.conversation_id}"]
    assert konu["messageCount"] == 4


def test_dolu_konu_devam_konusu_acar(depo):
    h1 = chat_history.prepare("u1", None)
    chat_history.write_turn("u1", h1, "ilk", "cevap", "tr")
    # Konuyu suni olarak doldur.
    depo[f"users/u1/conversations/{h1.conversation_id}"]["messageCount"] = \
        chat_history.MAX_MESSAGES_PER_CONVERSATION

    h2 = chat_history.prepare("u1", h1.conversation_id)
    assert h2.create
    assert h2.conversation_id != h1.conversation_id
    assert h2.title_prefix  # eski başlık taşınır ("... ↪")


def test_baglam_konuya_yapisir_ve_geri_gelir(depo):
    """KA7: friend/person kimliği konu dokümanına yazılır ve `prepare`
    geri getirir — listeden yeniden açılan konuşma "eşin" bağlamını
    KAYBETMEZ (eski davranış: bağlam yalnız ekran ömrü kadar yaşıyordu)."""
    h1 = chat_history.prepare("u1", None)
    chat_history.write_turn("u1", h1, "eşimle aram nasıl?", "cevap", "tr",
                            None, "kisi-1")

    h2 = chat_history.prepare("u1", h1.conversation_id)
    assert h2.person_id == "kisi-1"
    assert h2.friend_uid is None

    # Bağlam sonradan da gelebilir (konuşmanın ortasında kişi ekranından
    # dönüş): doluysa her turda yazılır.
    chat_history.write_turn("u1", h2, "peki arkadaşım?", "cevap", "tr",
                            "arkadas-1", None)
    h3 = chat_history.prepare("u1", h1.conversation_id)
    assert h3.friend_uid == "arkadas-1"
    assert h3.person_id == "kisi-1"  # eski bağlam silinmez


def test_dolu_konu_baglami_devam_konusuna_tasir(depo):
    h1 = chat_history.prepare("u1", None)
    chat_history.write_turn("u1", h1, "ilk", "cevap", "tr", None, "kisi-9")
    depo[f"users/u1/conversations/{h1.conversation_id}"]["messageCount"] = \
        chat_history.MAX_MESSAGES_PER_CONVERSATION

    h2 = chat_history.prepare("u1", h1.conversation_id)
    assert h2.create
    assert h2.person_id == "kisi-9"


def test_silinmis_kimlik_ayni_kimlikle_yeniden_kurulur(depo):
    """Temizlik istemcinin elindeki konuyu silmiş olabilir; istemci fark
    etmeden aynı kimliğe yeni doküман kurulur."""
    h = chat_history.prepare("u1", "kayip-kimlik")
    assert h.create
    assert h.conversation_id == "kayip-kimlik"


def test_baslik_kirpilir_ve_tek_satir(depo):
    uzun = "çok  uzun\nbir   soru " * 20
    baslik = chat_history.title_from(uzun)
    assert len(baslik) <= chat_history.TITLE_CHARS
    assert "\n" not in baslik
    assert baslik.endswith("…")


def test_mesaj_kirpilir(depo):
    metin = "a" * 5000
    assert len(chat_history.clip_message(metin)) == \
        chat_history.MAX_MESSAGE_CHARS


def test_silme_mesajlari_da_goturur(depo):
    h = chat_history.prepare("u1", None)
    chat_history.write_turn("u1", h, "soru", "cevap", "tr")

    silinen = chat_history.delete_conversation("u1", h.conversation_id)

    assert silinen == 2
    assert _konu_yollari(depo) == []
    assert not any("messages" in y for y in depo)


def test_temizlik_suresi_gecmisi_yetimsiz_siler(depo):
    h = chat_history.prepare("u1", None)
    chat_history.write_turn("u1", h, "eski soru", "eski cevap", "tr")
    # Süreyi geçmişe çek.
    depo[f"users/u1/conversations/{h.conversation_id}"]["expireAt"] = \
        dt.datetime(2020, 1, 1, tzinfo=dt.timezone.utc)

    sonuc = chat_history.purge_expired()

    assert sonuc == {"conversations": 1, "messages": 2}
    assert not any("conversations" in y for y in depo), "yetim kaldı"


def test_temizlik_dry_run_silmez(depo):
    h = chat_history.prepare("u1", None)
    chat_history.write_turn("u1", h, "soru", "cevap", "tr")
    depo[f"users/u1/conversations/{h.conversation_id}"]["expireAt"] = \
        dt.datetime(2020, 1, 1, tzinfo=dt.timezone.utc)

    sonuc = chat_history.purge_expired(dry_run=True)

    assert sonuc["conversations"] == 1
    assert _konu_yollari(depo), "dry_run silmemeli"


def test_konu_tavani_en_eskiyi_dusurur(depo):
    for i in range(chat_history.MAX_CONVERSATIONS):
        h = chat_history.prepare("u1", None)
        chat_history.write_turn("u1", h, f"soru {i}", "cevap", "tr")
        # updatedAt sıralanabilir olsun.
        depo[f"users/u1/conversations/{h.conversation_id}"]["updatedAt"] = \
            f"2026-01-{i + 1:02d}"

    h = chat_history.prepare("u1", None)
    chat_history.write_turn("u1", h, "yeni konu", "cevap", "tr")

    assert len(_konu_yollari(depo)) == chat_history.MAX_CONVERSATIONS


# --------------------------------------------------------------------------
# Engellenen tur damgasi (K-turu)
#
# Engellenen turlar bir tur boyunca arşive HİÇ yazılmıyordu ve 498
# mesajlık korpusta kayıtlı engel SIFIRDI — kapının yanlış pozitifleri
# ("hissediyorum" → finans reddi) yalnız ekranda görüldü. Kaydı olmayan
# kusur ölçülemez.
# --------------------------------------------------------------------------

def test_engellenen_tur_damgali_yazilir(depo):
    """`blocked` iki mesajda da durur; AI metni kapının sabit ret metnidir."""
    hazir = chat_history.prepare("u1", None)
    chat_history.write_turn("u1", hazir, "Hisselerimi satsam mı?",
                            "Al-sat kararı benim alanım değil…", "tr",
                            blocked="finans")

    mesajlar = sorted(
        (veri for yol, veri in depo.items()
         if f"conversations/{hazir.conversation_id}/messages/" in yol),
        key=lambda v: v["createdAt"])
    assert [m["sender"] for m in mesajlar] == ["USER", "AI"]
    assert all(m["blocked"] == "finans" for m in mesajlar), (
        "ölçüm sorgusu iki mesajı da tek seferde getirmeli")
    assert mesajlar[1]["text"].startswith("Al-sat")
    konu = depo[f"users/u1/conversations/{hazir.conversation_id}"]
    assert konu["messageCount"] == 2, "engellenen tur da bir turdur"


def test_engellenmeyen_turda_blocked_alani_yok(depo):
    """Alan YALNIZ engelde yazılır: yokluğu "model cevapladı" demek. `null`
    yazılsaydı `blocked` dolu olanları süzen ölçüm sorgusu boş alanla
    kirlenirdi."""
    hazir = chat_history.prepare("u1", None)
    chat_history.write_turn("u1", hazir, "Bugün nasıl bir gün?", "Sakin.",
                            "tr")

    mesajlar = [veri for yol, veri in depo.items()
                if f"conversations/{hazir.conversation_id}/messages/" in yol]
    assert len(mesajlar) == 2
    assert all("blocked" not in m for m in mesajlar)

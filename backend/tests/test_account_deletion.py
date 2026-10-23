"""Faz 7a testleri: hesap silme.

Silme mağaza zorunlulugu (Apple 5.1.1(v), Google Play) ve tek basina red
sebebi. Ama asil risk redde ugramak degil: bir koleksiyonu atlarsak
"hesabimi sildim" diyen kullanicinin verisi sistemde kalir ve bunu kimse
fark etmez. Bu yuzden testler "silindi mi" degil, HANGI YOLLARIN
DOKUNULDUGUNU dogruluyor.

Calistirma:  .venv\\Scripts\\python.exe -m pytest tests/test_account_deletion.py -q
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from services import account_service

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulamasi ice aktarilamadi: {_APP_IMPORT_ERROR}",
)


# --------------------------------------------------------------------------
# Asgari sahte Firestore
# --------------------------------------------------------------------------

class _Anlik:
    def __init__(self, kimlik, veri, referans):
        self.id = kimlik
        self._veri = veri
        self.reference = referans

    @property
    def exists(self):
        return self._veri is not None

    def to_dict(self):
        return dict(self._veri) if self._veri is not None else None


class _Dokuman:
    def __init__(self, store, yol):
        self._store = store
        self._yol = yol

    def collection(self, ad):
        return _Koleksiyon(self._store, f"{self._yol}/{ad}")

    def get(self):
        return _Anlik(self._yol.rsplit("/", 1)[-1],
                      self._store.veriler.get(self._yol), self)

    def set(self, veri, merge=False):
        self._store.veriler[self._yol] = dict(veri)

    def delete(self):
        self._store.veriler.pop(self._yol, None)
        self._store.silinenler.append(self._yol)


class _Sorgu:
    def __init__(self, store, yol, filtreler=None, limit=None):
        self._store = store
        self._yol = yol
        self._filtreler = filtreler or []
        self._limit = limit

    def where(self, filter=None, **_):
        return _Sorgu(self._store, self._yol,
                      self._filtreler + [(filter.field_path, filter.value)],
                      self._limit)

    def limit(self, n):
        return _Sorgu(self._store, self._yol, self._filtreler, n)

    def stream(self):
        sonuc = []
        for yol, veri in list(self._store.veriler.items()):
            ust, _, kimlik = yol.rpartition("/")
            if ust != self._yol:
                continue
            if any(veri.get(alan) != deger for alan, deger in self._filtreler):
                continue
            sonuc.append(_Anlik(kimlik, veri, _Dokuman(self._store, yol)))
        return sonuc[:self._limit] if self._limit else sonuc


class _Koleksiyon(_Sorgu):
    def document(self, kimlik):
        return _Dokuman(self._store, f"{self._yol}/{kimlik}")


class SahteFirestore:
    """Yol -> veri sozlugu. Yol "users/u1/friends/u2" bicimindedir."""

    def __init__(self, veriler=None):
        self.veriler = dict(veriler or {})
        self.silinenler: list[str] = []

    def collection(self, ad):
        return _Koleksiyon(self, ad)


def ornek_store():
    """Silinmesi gereken her seyi iceren bir kullanici."""
    return SahteFirestore({
        "users/ben": {"username": "gezgin", "birthDate": "1990-05-12"},
        "users/ben/private/memory": {"facts": ["x"]},
        "users/ben/private/subscription": {"active": True},
        "users/ben/private/notifications": {"dailyLastSent": "2026-08-01"},
        # Kurulumdaki yapay zeka onayının kanıtı: geri alma yolu hesabı
        # silmek, yani kayıt hesapla birlikte GİTMELİ (onu silen başka yol
        # olmadığı `test_ai_consent` (e)'de ayrıca bekçili).
        "users/ben/private/aiConsent": {"granted": True, "version": 1,
                                        "grantedAt": "2026-10-22T20:12:58",
                                        "locale": "tr"},
        "users/ben/friends/arkadas": {"status": "accepted"},
        "users/ben/nudges/n1": {"fromUid": "arkadas", "reaction": "shine"},
        "users/ben/blocked/kotu": {"at": 1},
        # Eklenen kisi (P-turu): ucuncu bir kisinin dogum verisi. Rizasi
        # ALINAMAMIS bir kisinin verisi, sahibi hesabini sildikten sonra
        # sunucuda kalamaz.
        "users/ben/people/p1": {"relation": "partner",
                                "birthDate": "1990-03-12"},
        # Karsi taraftaki izler
        "users/arkadas/friends/ben": {"status": "accepted"},
        "users/arkadas/nudges/n9": {"fromUid": "ben", "reaction": "streak"},
        "users/arkadas/nudges/n8": {"fromUid": "baskasi", "reaction": "shine"},
        # Herkese acik kart ve kullanici adi
        "publicProfiles/ben": {"uid": "ben"},
        "usernames/gezgin": {"uid": "ben"},
        # Kisiye ozel ve paylasimli onbellek
        "aiCache/a1": {"ownerUid": "ben", "value": "natal"},
        "aiCache/a2": {"ownerUid": "ben", "value": "gunluk"},
        "aiCache/a3": {"value": "burc yorumu"},  # paylasimli, sahipsiz
        # `users/ben` AGACININ DISINDA, ama uid ile bana bagli kayitlar.
        # Kapali test denetiminde (2026-09-14) bunlarin silinmedigi
        # bulundu; hukuk metni "tum veriler silinir" diyordu.
        "usageEvents/u1": {"uid": "ben", "feature": "chat", "estCostUsd": 0.002},
        "usageEvents/u2": {"uid": "ben", "feature": "natal", "estCostUsd": 0.003},
        "usageEvents/u3": {"uid": "arkadas", "feature": "chat"},
        "phoneAttempts/p1": {"uid": "ben", "stage": "sent",
                             "masked": "+90532***4567"},
        "phoneAttempts/p2": {"uid": "arkadas", "stage": "sent"},
        # Kullanicinin KENDI yazdigi serbest metin.
        "feedback/f1": {"uid": "ben", "type": "bug", "text": "sohbet donuyor"},
        "feedback/f2": {"uid": "baskasi", "type": "idea", "text": "x"},
        # BILEREK SAKLANANLAR — mali kayit ve denetim izi.
        "revenueEvents/r1": {"uid": "ben", "productId": "rytho_plus_monthly",
                             "priceUsd": 4.4},
        "adminAudit/a9": {"targetUid": "ben", "action": "user.credit"},
        # Baska kullanicinin verisi — dokunulmamali
        "users/arkadas": {"username": "deniz"},
        "usernames/deniz": {"uid": "arkadas"},
        "publicProfiles/arkadas": {"uid": "arkadas"},
    })


@pytest.fixture(autouse=True)
def onbellek_yalitimi(monkeypatch, tmp_path):
    """Hesap silme artık arkadaşların çevre önbelleğine YAZIYOR
    (`circle_context.invalidate`). Bu dosyadaki her silme testi o yazımı
    depodaki gerçek önbellek dizinine ve süreç boyu yaşayan bellek
    katmanına bırakmasın: dosya arka ucu `tmp_path`te, bellek teste özel."""
    from collections import OrderedDict

    from core import cache, config
    monkeypatch.setattr(config, "CACHE_BACKEND", "file")
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(cache, "_memory", OrderedDict())


@pytest.fixture
def store(monkeypatch):
    s = ornek_store()
    monkeypatch.setattr(account_service.firestore_client, "get_client",
                        lambda: s)
    monkeypatch.setattr(account_service, "_delete_auth_user", lambda uid: True)
    return s


# --------------------------------------------------------------------------
# Silinmesi gerekenler
# --------------------------------------------------------------------------

@pytest.mark.parametrize("yol", [
    "users/ben",
    "users/ben/private/memory",
    "users/ben/private/subscription",
    "users/ben/private/notifications",
    "users/ben/private/aiConsent",
    "users/ben/friends/arkadas",
    "users/ben/nudges/n1",
    "users/ben/blocked/kotu",
    "users/ben/people/p1",
    "publicProfiles/ben",
    "usernames/gezgin",
])
def test_kullanici_verisi_silinir(store, yol):
    account_service.delete_account("ben")
    assert yol not in store.veriler, f"silinmedi: {yol}"


def test_karsi_taraftaki_arkadaslik_silinir(store):
    """Silinmezse arkadasin listesinde var olmayan bir kisi gorunur ve o
    kisiye ikili okuma denenebilir."""
    account_service.delete_account("ben")
    assert "users/arkadas/friends/ben" not in store.veriler


def test_gonderdigim_tepkiler_silinir(store):
    account_service.delete_account("ben")
    assert "users/arkadas/nudges/n9" not in store.veriler


def test_arkadasin_cevre_onbellegi_silinen_kisiyi_tasimaz(store):
    """Silinen kişinin adı + burcu arkadaşının sohbet fısıltısında kalıyordu.

    Fısıltı `circle-{arkadaş}-{dil}` anahtarında 6 saat önbellekli ve
    kaydın sahibi ARKADAŞ — `_delete_owned_cache` onu görmüyordu, yani ad
    ve burç 6 saate kadar her sohbet turunda yapay zekaya gidiyordu.
    Fısıltı burada GERÇEKTEN kurulur (aynı sahte Firestore'dan), sonra
    hesap silinir. Önbellek gerçek `core.cache` (yalıtımı autouse
    `onbellek_yalitimi`)."""
    from core import cache
    from services import circle_context
    store.veriler["users/ben"]["sunSign"] = "Boğa ♉"
    for dil in ("tr", "en"):
        onceki = circle_context.circle_whisper("arkadas", dil)
        # Ölçüm kör değil: silmeden önce ad ve burç fısıltıda.
        assert "gezgin" in onceki, (dil, onceki)
        assert ("Boğa" if dil == "tr" else "Taurus") in onceki, onceki

    account_service.delete_account("ben")

    anahtarlar = [circle_context._anahtar("arkadas", dil)
                  for dil in ("tr", "en")]
    for anahtar in anahtarlar:
        kalan = cache.get(anahtar) or ""
        assert "gezgin" not in kalan and "Boğa" not in kalan, kalan
    # Kalıcı katman da: belleğinde kopyası olmayan bir instance orayı okur.
    cache._memory.clear()
    for anahtar in anahtarlar:
        kalan = cache.get(anahtar) or ""
        assert "gezgin" not in kalan and "Boğa" not in kalan, kalan


def test_cevre_onbellegi_dusurulemezse_silme_tamamlanir(store, monkeypatch):
    """Önbellek best-effort: düşürme fırlatsa da hesap silinir — kimliğin
    kalması, 6 saatlik bir önbellek kaydının kalmasından kötü."""
    from services import circle_context

    def patla(uid):
        raise RuntimeError("onbellek kizdi")

    monkeypatch.setattr(circle_context, "invalidate", patla)
    sayac = account_service.delete_account("ben")
    assert sayac["user"] == 1
    assert sayac["auth"] == 1
    assert "users/arkadas/friends/ben" not in store.veriler
    assert "users/arkadas/nudges/n9" not in store.veriler


def test_kisiye_ozel_uretimler_silinir(store):
    account_service.delete_account("ben")
    assert "aiCache/a1" not in store.veriler
    assert "aiCache/a2" not in store.veriler


# --------------------------------------------------------------------------
# Silinmemesi gerekenler
# --------------------------------------------------------------------------

def test_paylasimli_onbellek_korunur(store):
    """Bir kullanicinin hesabini silmesi herkesin burc yorumunu silmemeli."""
    account_service.delete_account("ben")
    assert "aiCache/a3" in store.veriler


def test_baskalarinin_verisi_korunur(store):
    account_service.delete_account("ben")
    for yol in ("users/arkadas", "usernames/deniz", "publicProfiles/arkadas",
                "users/arkadas/nudges/n8"):
        assert yol in store.veriler, f"baskasinin verisi silindi: {yol}"


def test_baskasinin_kullanici_adi_serbest_birakilmaz(monkeypatch):
    """Kullanici adi devredilmis olabilir; kayit baskasina aitse silinmemeli."""
    s = SahteFirestore({
        "users/ben": {"username": "gezgin"},
        "usernames/gezgin": {"uid": "baskasi"},  # ad devredilmis
    })
    monkeypatch.setattr(account_service.firestore_client, "get_client",
                        lambda: s)
    monkeypatch.setattr(account_service, "_delete_auth_user", lambda uid: True)

    account_service.delete_account("ben")
    assert "usernames/gezgin" in s.veriler


# --------------------------------------------------------------------------
# Sira ve dayaniklilik
# --------------------------------------------------------------------------

def test_kimlik_en_son_silinir(monkeypatch):
    """Kimligi once silseydik ve veri silme yarida kalsaydi, kullanici geri
    donup tekrar deneyemezdi."""
    s = ornek_store()
    monkeypatch.setattr(account_service.firestore_client, "get_client",
                        lambda: s)

    sira: list[str] = []
    monkeypatch.setattr(account_service, "_delete_auth_user",
                        lambda uid: sira.append("auth") or True)

    account_service.delete_account("ben")
    # Auth cagrisi yapildiginda kullanici dokumani coktan silinmis olmali.
    assert sira == ["auth"]
    assert "users/ben" not in s.veriler


def test_firestore_yoksa_silme_yapilmaz(monkeypatch):
    """Veriyi silemeden kimligi silmek, sahipsiz veri birakmak olurdu."""
    monkeypatch.setattr(account_service.firestore_client, "get_client",
                        lambda: None)

    def kimlik_silinmemeli(uid):
        raise AssertionError("Firestore yokken kimlik silinmemeli")

    monkeypatch.setattr(account_service, "_delete_auth_user",
                        kimlik_silinmemeli)

    with pytest.raises(RuntimeError):
        account_service.delete_account("ben")


def test_sayim_dondurulur(store):
    sayim = account_service.delete_account("ben")
    assert sayim["user"] == 1
    assert sayim["publicProfile"] == 1
    assert sayim["username"] == 1
    assert sayim["friendEdges"] == 1
    assert sayim["sentNudges"] == 1
    assert sayim["aiCache"] == 2
    assert sayim["auth"] == 1


def test_kimlik_silinemezse_sayimda_gorunur(monkeypatch):
    """Veri silindi ama kimlik kaldiysa bu sessizce gecilmemeli."""
    s = ornek_store()
    monkeypatch.setattr(account_service.firestore_client, "get_client",
                        lambda: s)
    monkeypatch.setattr(account_service, "_delete_auth_user", lambda uid: False)

    sayim = account_service.delete_account("ben")
    assert sayim["auth"] == 0


# --------------------------------------------------------------------------
# Uc davranisi
# --------------------------------------------------------------------------

@pytest.fixture
def gercek_kullanici():
    """Dogrulanmis (anonim olmayan) bir oturum.

    Gelistirme modunda `get_current_user` anonim bir kullanici donduruyor ve
    uc onu bilincli olarak reddediyor — silinecek gercek bir hesap yok.
    """
    from core.auth import AuthUser, get_current_user

    app.dependency_overrides[get_current_user] = lambda: AuthUser(
        uid="gercek-uid", email="a@b.c")
    yield
    app.dependency_overrides.clear()


@uygulama_gerekir
def test_uc_yalnizca_kendi_hesabini_siler(monkeypatch, gercek_kullanici):
    """Hedef kimlik govdeden degil, dogrulanmis oturumdan alinmali; aksi
    halde gecerli oturumu olan herkes baskasinin hesabini silebilirdi."""
    from api import account

    silinen: list[str] = []
    monkeypatch.setattr(account.account_service, "delete_account",
                        lambda uid: silinen.append(uid) or {"user": 1})

    with TestClient(app) as client:
        yanit = client.request(
            "DELETE", "/api/v1/account/me",
            json={"uid": "baskasi"},  # yok sayilmali
            headers={"Authorization": "Bearer test-silme"})

    assert yanit.status_code == 200
    assert silinen == ["gercek-uid"], "govdedeki uid dikkate alinmamali"


@uygulama_gerekir
def test_anonim_oturum_silme_yapamaz():
    """Gelistirme modundaki anonim kullanicinin silinecek hesabi yok."""
    with TestClient(app) as client:
        yanit = client.request("DELETE", "/api/v1/account/me",
                               headers={"Authorization": "Bearer test-anon"})
    assert yanit.status_code == 400


@uygulama_gerekir
def test_uc_hata_durumunda_ic_ayrinti_sizdirmaz(monkeypatch, gercek_kullanici):
    from api import account

    def patla(uid):
        raise RuntimeError("gizli_ic_detay")

    monkeypatch.setattr(account.account_service, "delete_account", patla)

    with TestClient(app, raise_server_exceptions=False) as client:
        yanit = client.request("DELETE", "/api/v1/account/me",
                               headers={"Authorization": "Bearer test-hata"})

    assert yanit.status_code == 500
    assert "gizli_ic_detay" not in yanit.text


# --------------------------------------------------------------------------
# uid'li ÜST DÜZEY koleksiyonlar (kapalı test denetimi, 2026-09-14)
# --------------------------------------------------------------------------
#
# Bulgu: hesap silme yalnız `users/{uid}` ağacını temizliyordu. Üç
# koleksiyon uid taşıyarak dışarıda duruyordu — biri (`feedback`)
# kullanıcının kendi yazdığı serbest metni. Hukuk metni ise
# "Hesabını sildiğinde tüm veriler kalıcı olarak silinir" diyordu.
# Vaat ile kod arasındaki bu açık, mağaza politikası ve KVKK riski.


def test_kullanim_telemetrisi_silinir(store):
    account_service.delete_account("ben")
    assert "usageEvents/u1" not in store.veriler
    assert "usageEvents/u2" not in store.veriler


def test_telefon_deneme_kaydi_silinir(store):
    """Maskeli de olsa numara kişisel veridir."""
    account_service.delete_account("ben")
    assert "phoneAttempts/p1" not in store.veriler


def test_gonderilen_geri_bildirim_silinir(store):
    """Serbest metin: kullanıcının kendi cümlesi, kesinlikle kalmamalı."""
    account_service.delete_account("ben")
    assert "feedback/f1" not in store.veriler


def test_baskasinin_uid_kayitlarina_dokunulmaz(store):
    account_service.delete_account("ben")
    assert store.veriler["usageEvents/u3"]["uid"] == "arkadas"
    assert store.veriler["phoneAttempts/p2"]["uid"] == "arkadas"
    assert store.veriler["feedback/f2"]["uid"] == "baskasi"


def test_mali_kayit_ve_denetim_izi_BILEREK_kalir(store):
    """Silinmeyenler kaza değil karar: mali kayıt saklama yükümlülüğü ve
    denetim izinin bütünlüğü. İkisi de hukuk metninde YAZILI olmalı —
    `test_legal_texts.py` bunu ayrıca zorluyor."""
    account_service.delete_account("ben")
    assert "revenueEvents/r1" in store.veriler
    assert "adminAudit/a9" in store.veriler


def test_silme_raporu_yeni_koleksiyonlari_sayar(store):
    """Rapor log'a ve teste kanıt olarak giriyor; sessiz atlama olmasın."""
    sayac = account_service.delete_account("ben")
    assert sayac.get("usageEvents") == 2
    assert sayac.get("phoneAttempts") == 1
    assert sayac.get("feedback") == 1


def test_uid_koleksiyonu_dusse_bile_silme_tamamlanir(store, monkeypatch):
    """Telemetri silinemezse hesap yine de silinmeli — kimliğin kalması
    veri kalmasından kötü."""
    gercek = store.collection

    def patlak(ad):
        if ad == "usageEvents":
            raise RuntimeError("firestore kizdi")
        return gercek(ad)

    monkeypatch.setattr(store, "collection", patlak)
    sayac = account_service.delete_account("ben")
    assert sayac["user"] == 1
    assert "feedback/f1" not in store.veriler, "diğer koleksiyonlar silinmeli"


# ---------------------------------------------------------------------------
# Cloud Storage (kapalı test denetimi, 2026-09-18)
# ---------------------------------------------------------------------------
#
# Bulgu: Firestore temizleniyordu ama `avatars/{uid}/avatar.png` kovada
# kalıyordu ve infra/storage.rules gereği GİRİŞLİ HERKES onu okuyabiliyor —
# hesabı silinmiş birinin yüz fotoğrafı erişilebilir kalıyordu. Hukuk metni
# ise fotoğrafın "hesabını silerek kaldırılabileceğini" söylüyor.


class _SahteBlob:
    def __init__(self, ad, kova):
        self.name = ad
        self._kova = kova

    def delete(self):
        self._kova.dosyalar.remove(self.name)


class _SahteKova:
    """Gerçek API'nin KULLANILAN yüzü: list_blobs(prefix=...) + blob.delete()."""

    def __init__(self, dosyalar):
        self.dosyalar = list(dosyalar)

    def list_blobs(self, prefix=""):
        return [_SahteBlob(ad, self) for ad in list(self.dosyalar)
                if ad.startswith(prefix)]


@pytest.fixture
def kova(monkeypatch):
    k = _SahteKova(["avatars/ben/avatar.png",
                    "avatars/arkadas/avatar.png"])
    monkeypatch.setattr(account_service, "_kova", lambda: k)
    return k


def test_avatar_dosyasi_kovadan_silinir(store, kova):
    account_service.delete_account("ben")
    assert "avatars/ben/avatar.png" not in kova.dosyalar


def test_silinen_dosya_raporda_sayilir(store, kova):
    """Sessiz atlama olmasın: rapor log'a ve teste kanıt olarak giriyor."""
    sayac = account_service.delete_account("ben")
    assert sayac.get("storageFiles") == 1


def test_baskasinin_avatari_kalir(store, kova):
    """Önek filtresi şart: uid önekini kaçıran bir sorgu herkesi silerdi."""
    account_service.delete_account("ben")
    assert "avatars/arkadas/avatar.png" in kova.dosyalar


def test_pin_kova_sahtelenmemisken_GERCEK_APIYE_GITMEZ(store):
    """`conftest.depolama_hermetik` pini: kovayi sahtelemeyen bir silme
    testi gercek `firebase_admin.storage`e ULASMAZ.

    Bu dosyadaki 18 mevcut silme testi kovayi sahtelemiyor. Bugun kazara
    guvenliler (varsayilan Firebase uygulamasi testte hic baslatilmiyor),
    ama o kaza bir gun bozulursa makinede ADC varken URETIM kovasinda
    list+delete kosarlardi. Bekci, pinin `_kova`yi gercekten devraldigini
    kimlikle dogruluyor -- import edilen modul niteligi bos kova olmali.
    """
    from services import account_service as hedef

    assert hedef._kova is not None
    kova = hedef._kova()
    assert tuple(kova.list_blobs(prefix="avatars/ben/")) == ()
    # Silme yine tamamlanir: depolama best-effort, kimlik silme degil.
    sayac = hedef.delete_account("ben")
    assert sayac["auth"] == 1
    assert sayac.get("storageFiles", 0) == 0


def test_kova_erisilemezse_silme_TAMAMLANIR(store, monkeypatch):
    """Kimliğin kalması dosyanın kalmasından kötü: depolama best-effort."""
    def patlak():
        raise RuntimeError("kova yok")

    monkeypatch.setattr(account_service, "_kova", patlak)
    sayac = account_service.delete_account("ben")
    assert sayac["user"] == 1
    assert sayac["auth"] == 1

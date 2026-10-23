r"""Yapay zeka aktarım onayı — kurulumdaki ikinci kutu, KAPI DEĞİL.

Sahip kararı 2026-10-22 (U06'nın sunucu kapısının yerine geçti): onay
YALNIZ kurulumun ilk adımında, şartlar kutusunun altındaki ikinci, ayrı
ve zorunlu kutuyla bir kez alınır. Onay sayfası, her açılışta ya da her
AI özelliğinde soran yollar, "Şimdi değil", sunucu kapıları (403, `ai=0`,
bildirimde teknik satır, akşam sorusunun kesilmesi), eşik
(`aiConsentMinBuild`) ve Profil'deki geri alma anahtarı KALKTI. Hiçbir
özellik onay yüzünden kapanmaz ya da kötüleşmez; geri alma yolu hesabı
silmek.

Korunan değişmezler:

1. **Kayıt yalnız ispat.** `POST /account/ai-consent`, kutuyu işaretleyip
   kurulumu bitiren kullanıcı için `users/{uid}/private/aiConsent`'e
   onay + gösterilen sürüm + zaman + dil yazar; tekrar İLK onayın anını,
   dilini ve sürümünü korur. Onu çağıran tek yol bu uç; önekte GET,
   DELETE ya da alt yol yok; dokümanı silen tek yol hesap silme.
2. **Kapı yok.** Kaydı OLMAYAN kullanıcı — 53'ten güncelleyen herkes
   böyledir, onun adına kayıt yazılmaz — sohbette, okumalarda, yüz
   okumada, yumuşak uçlarda ve sabah/öğle/akşam bildiriminde 53'ün
   kaynağındaki (`33bb9f4`) gibi AI çıktısı alır. AI uçları onay kaydına
   dokunmaz bile.
3. **"Hayır" yazan yol yok.** Onu üretecek bir ekran kalmadı; hiçbir
   kodun okumadığı bir red kaydı, kaldırılan kapıyı geri çağırmaya
   davetiye olurdu.

Çalıştırma:  .venv/bin/python -m pytest tests/test_ai_consent.py -q
"""
from __future__ import annotations

import ast
import datetime as dt
import functools
import hashlib
import importlib.util
import json
import pathlib
import types

import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from core import cache, config, entitlements, wallet
from core.auth import AuthUser, get_current_user
from services import consent_service

try:
    from main import app
    _APP_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover - ortama bagli
    app = None
    _APP_IMPORT_ERROR = str(exc)

uygulama_gerekir = pytest.mark.skipif(
    _APP_IMPORT_ERROR is not None,
    reason=f"FastAPI uygulamasi ice aktarilamadi: {_APP_IMPORT_ERROR}",
)

BACKEND = pathlib.Path(__file__).resolve().parent.parent

UID = "ai-onay-uid"
ONAY_UCU = "/api/v1/account/ai-consent"

#: Kaydı olmayan kullanıcının istemci sürümleri: başlıksız (eski/el ile
#: çağrı), 53 (Play'deki kutusuz paket) ve 54 (sıradaki paket — kurulumu
#: 53'te bitirip güncelleyen kutuyu hiç görmez, kaydı yine yoktur).
#: Kaldırılan eşik bu sayılara göre karar veriyordu; artık hiçbiri bir
#: şeyi değiştirmemeli.
SURUMLER = (None, "53", "54")

DOGUM = {"name": "Ada", "year": 1994, "month": 8, "day": 11,
         "hour": 9, "minute": 30, "city": "Izmir"}

ORANLAR = {"jawToCheek": 0.80, "mouthToFaceWidth": 0.41,
           "eyeSpacing": 0.45, "symmetry": 0.98,
           "upperThird": 0.33, "middleThird": 0.33, "lowerThird": 0.34,
           "widthToHeight": 0.70, "lipFullness": 0.05}

#: Sahte LLM'in ürettiği metin — yanıtta görünmesi, AI katmanının
#: ATLANMADIĞININ kanıtı.
AI_METNI = "Gercek AI raporu."


@pytest.fixture
def basliklar(request):
    """İstek başlıkları: sürüm + teste ÖZEL hız sınırı kovası.

    `RateLimitMiddleware` süreç boyunca yaşar ve Authorization'sız isteği
    IP'ye ("testclient") yazar — LLM uçlarında dakikada 20. Bu dosya
    onlarca LLM isteği atıyor; ortak kovayı doldursaydı kendi testleri ve
    sonra koşan BAŞKA dosyaların testleri 429 alırdı (ilk koşuda ölçüldü:
    İç Takvim isteği 429). Kova anahtarı Authorization özeti
    (test_horoscope ile aynı çare); kimlik `dependency_overrides` ile
    verildiği için başlık doğrulanmaz.
    """
    kova = hashlib.sha256(request.node.nodeid.encode()).hexdigest()[:12]

    def kur(surum: str | None = None, **ek: str) -> dict[str, str]:
        b = {"Authorization": f"Bearer test-onay-{kova}", **ek}
        if surum is not None:
            b["X-App-Build"] = surum
        return b

    return kur


def _icinde(veri, aranan: str) -> bool:
    return aranan in json.dumps(veri, ensure_ascii=False)


@pytest.fixture(autouse=True)
def yerel_depo(monkeypatch, tmp_path):
    """Firestore pinliyken (conftest `firestore_hermetik`) onay kaydı
    `config.CACHE_DIR` altındaki yerel dosyaya yazılır — depodaki GERÇEK
    önbellek dizini. Testin yazdığı kayıt orada kalıcı olmasın."""
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path)


@pytest.fixture
def kullanici():
    app.dependency_overrides[get_current_user] = lambda: AuthUser(
        uid=UID, email="a@b.c", auth_time=1000)
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def kayda_dokunan(monkeypatch):
    """AI yollarının onay kaydına HİÇ dokunmadığının ölçüsü.

    Kaydın iki kapısı (Firestore dokümanı ve yerel dosya) sayaçla sarılır.
    Kayda bakan bir kapı geri gelse, 53'ten güncelleyen ve kaydı hiç
    olmayan kullanıcıyı cezalandırmanın ilk adımı bu okuma olurdu.
    """
    sayac = {"n": 0}
    gercek_doc = consent_service._ai_doc
    gercek_oku = consent_service._ai_local_read

    def doc(uid):
        sayac["n"] += 1
        return gercek_doc(uid)

    def oku():
        sayac["n"] += 1
        return gercek_oku()

    monkeypatch.setattr(consent_service, "_ai_doc", doc)
    monkeypatch.setattr(consent_service, "_ai_local_read", oku)
    return sayac


# --------------------------------------------------------------------------
# (a) Kayıt: POST yazar; tekrar İLK onayın anını, dilini, sürümünü korur
# --------------------------------------------------------------------------

@pytest.fixture
def saat(monkeypatch):
    """`consent_service`in saatini elle ilerletir.

    İki POST arasında zaman GERÇEKTEN geçmeli: aynı mikrosaniyede koşan
    iki çağrıda ezilen `grantedAt` eskisiyle aynı çıkar ve kusur görünmez.
    Başlangıç anı ölçülen vakanın kendisi (20:12:58.778 → 20:12:59.983).
    """
    anlar = [dt.datetime(2026, 10, 22, 20, 12, 58, 778000,
                         tzinfo=dt.timezone.utc)]

    class _Saat(dt.datetime):
        @classmethod
        def now(cls, tz=None):
            return anlar[-1]

    monkeypatch.setattr(consent_service, "dt", types.SimpleNamespace(
        datetime=_Saat, timezone=dt.timezone))

    def ilerlet(saniye: float) -> None:
        anlar.append(anlar[-1] + dt.timedelta(seconds=saniye))

    return ilerlet


@uygulama_gerekir
def test_post_kaydi_yazar(kullanici, basliklar):
    with TestClient(app) as client:
        yanit = client.post(ONAY_UCU, json={"version": 1},
                            headers=basliklar(**{"Accept-Language": "en"}))

    assert yanit.status_code == 200, yanit.text
    assert yanit.json() == {"status": "success", "granted": True}

    kayitlar = consent_service._ai_local_read()
    assert list(kayitlar) == [UID]
    kayit = kayitlar[UID]
    assert kayit["granted"] is True
    assert kayit["version"] == 1
    assert kayit["locale"] == "en"
    dt.datetime.fromisoformat(kayit["grantedAt"])
    # Kanıtın alanları bunlar; "geri alındı" izi taşıyan alan yok.
    assert set(kayit) == {"granted", "version", "grantedAt", "locale"}


@uygulama_gerekir
def test_tekrar_post_ilk_onayi_ezmez_yerel_depo(kullanici, basliklar, saat):
    """Ölçülen kusur: ikinci çağrı `grantedAt`'i 20:12:58.778'den
    20:12:59.983'e, `locale`'i tr'den en'e çekiyordu. Kanıtın sorusu
    "kullanıcı İLK NE ZAMAN izin verdi" — veri o andan beri gidiyor;
    sonraki bir tekrar (ağ yeniden denemesi, dili değişmiş cihaz) o anı
    ileri iterse aradaki aktarımların dayanağı kayıttan silinir."""
    with TestClient(app) as client:
        ilk = client.post(ONAY_UCU, json={"version": 1},
                          headers=basliklar(**{"Accept-Language": "tr"}))
        ilk_kayit = dict(consent_service._ai_local_read()[UID])
        saat(1.205)
        ikinci = client.post(ONAY_UCU, json={"version": 2},
                             headers=basliklar(**{"Accept-Language": "en"}))

    assert ilk.status_code == ikinci.status_code == 200, ikinci.text
    # Yanıt sürümü YANKILAMAZ: kayıt ilk sürümü taşırken istekteki 2'yi
    # döndürmek, yazılmamış bir kaydı yazılmış gibi sunmak olurdu.
    assert ikinci.json() == {"status": "success", "granted": True}
    assert consent_service._ai_local_read() == {UID: ilk_kayit}
    assert ilk_kayit["grantedAt"] == "2026-10-22T20:12:58.778000+00:00"
    assert ilk_kayit["locale"] == "tr"
    assert ilk_kayit["version"] == 1


@uygulama_gerekir
def test_post_gosterilen_surumu_yazar_surumsuzde_guncel(kullanici,
                                                        basliklar):
    """İspat kullanıcının GÖRDÜĞÜ metne bağlanır (şartlar kabulüyle aynı
    ilke); sürüm gelmezse güncel metnin sürümü yazılır."""
    with TestClient(app) as client:
        assert client.post(ONAY_UCU, json={},
                           headers=basliklar()).status_code == 200
        assert consent_service._ai_local_read()[UID]["version"] == \
            consent_service.AI_CONSENT_VERSION
        assert client.post(ONAY_UCU, json={"version": 0},
                           headers=basliklar()).status_code == 422


@uygulama_gerekir
def test_post_abonelik_istemez(kullanici, basliklar, monkeypatch):
    """Kutu kurulumda, abonelikten önce işaretlenir — kanıtı her
    kullanıcı için yazılabilmeli."""
    monkeypatch.setattr(entitlements, "FORCE_PLUS", False)
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: False)
    with TestClient(app) as client:
        assert client.post(ONAY_UCU, json={"version": 1},
                           headers=basliklar()).status_code == 200


class _Doc:
    """Sahte doküman: `yazilan["kayitlar"]` yol → veri deposu.

    `create` gerçek istemcinin ön koşulunu taklit eder (doküman varsa
    `AlreadyExists`); `set` koşulsuz üzerine yazar. İkisinin farkı tam
    da korunan değişmez: üretim kodu `set`e dönerse ikinci POST kaydı
    ezer ve aşağıdaki test kırmızıya döner.
    """

    def __init__(self, yol, yazilan, patlat=False):
        self.yol = yol
        self.yazilan = yazilan
        self.patlat = patlat

    def collection(self, ad):
        return _Koleksiyon(self.yol + [ad], self.yazilan, self.patlat)

    def _yaz(self, islem, veri):
        if self.patlat:
            raise RuntimeError("firestore hıçkırığı")
        yol = "/".join(self.yol)
        self.yazilan.setdefault("islemler", []).append((islem, yol))
        self.yazilan.setdefault("kayitlar", {})[yol] = dict(veri)

    def create(self, veri):
        from google.api_core.exceptions import AlreadyExists
        if "/".join(self.yol) in self.yazilan.get("kayitlar", {}):
            raise AlreadyExists("Document already exists")
        self._yaz("create", veri)

    def set(self, veri, merge=False):
        self._yaz("set-merge" if merge else "set", veri)


class _Koleksiyon:
    def __init__(self, yol, yazilan, patlat):
        self.yol = yol
        self.yazilan = yazilan
        self.patlat = patlat

    def document(self, ad):
        return _Doc(self.yol + [ad], self.yazilan, self.patlat)


class _Istemci:
    def __init__(self, yazilan, patlat=False):
        self.yazilan = yazilan
        self.patlat = patlat

    def collection(self, ad):
        return _Koleksiyon([ad], self.yazilan, self.patlat)


class _YokAnlik:
    exists = False

    def to_dict(self):
        return None


class _HerSeyiKaydeden:
    """Her yolu kabul eden sahte istemci; yazımları `yol → veri` kaydeder.

    Bir isteğin Firestore'a NEREYE yazdığını ölçmek için: okumalar boş
    döner (doküman yok, sorgu sonuçsuz), `set`/`create`/`update` yolu
    kaydeder. Tanımadığı çağrı (ör. işlem/transaction) `AttributeError`
    ile düşer; o yollar zaten best-effort `try` içinde.
    """

    def __init__(self, yazilan, yol=()):
        self._yazilan = yazilan
        self._yol = tuple(yol)

    def collection(self, ad):
        return _HerSeyiKaydeden(self._yazilan, self._yol + (ad,))

    document = collection

    def where(self, *a, **k):
        return self

    order_by = limit = where

    def stream(self):
        return iter(())

    def get(self, *a, **k):
        return _YokAnlik()

    def _yaz(self, veri, *a, **k):
        self._yazilan["/".join(self._yol)] = dict(veri)

    set = create = update = _yaz


def test_firestoreda_kayit_private_altinda_olusturmayla_durur(monkeypatch):
    """`users/{uid}` alanı DEĞİL: yeni sunucu alanı firestore.rules
    hasOnly listesine girmezse istemcinin tüm profil yazımları düşer.
    Yazım `create` (yoksa-oluştur): ilk onay anı ancak ön koşullu
    yazımla atomik olarak korunur."""
    from core import firestore as firestore_client
    yazilan: dict = {}
    monkeypatch.setattr(firestore_client, "get_client",
                        lambda: _Istemci(yazilan))
    assert consent_service.grant_ai_consent(UID, 1, "tr") is True
    yol = f"users/{UID}/private/aiConsent"
    assert yazilan["islemler"] == [("create", yol)]
    veri = yazilan["kayitlar"][yol]
    assert veri["granted"] is True
    assert veri["version"] == 1
    assert veri["locale"] == "tr"


@uygulama_gerekir
def test_tekrar_post_ilk_onayi_ezmez_firestore(kullanici, basliklar, saat,
                                               monkeypatch):
    """Yerel depo testinin Firestore yüzü: üretimde koşan dal bu. İkinci
    POST başarılı döner (istemci bayrağını silsin, sonsuz yeniden deneme
    olmasın) ama dokümana dokunmaz."""
    from core import firestore as firestore_client
    yazilan: dict = {}
    monkeypatch.setattr(firestore_client, "get_client",
                        lambda: _Istemci(yazilan))
    yol = f"users/{UID}/private/aiConsent"
    with TestClient(app) as client:
        ilk = client.post(ONAY_UCU, json={"version": 1},
                          headers=basliklar(**{"Accept-Language": "tr"}))
        ilk_kayit = dict(yazilan["kayitlar"][yol])
        saat(1.205)
        ikinci = client.post(ONAY_UCU, json={"version": 2},
                             headers=basliklar(**{"Accept-Language": "en"}))

    assert ilk.status_code == ikinci.status_code == 200, ikinci.text
    assert yazilan["kayitlar"][yol] == ilk_kayit
    assert ilk_kayit["grantedAt"] == "2026-10-22T20:12:58.778000+00:00"
    assert ilk_kayit["locale"] == "tr"
    assert ilk_kayit["version"] == 1
    # Tek yazım: ikinci çağrı ezen bir `set` göndermedi. (Sahtenin
    # `update`i yok; ona dönen bir kod 500 alır ve yukarıda düşer.)
    assert yazilan["islemler"] == [("create", yol)]


@uygulama_gerekir
def test_kanit_yazilamazsa_500_istemci_basari_sanmaz(kullanici, basliklar,
                                                     monkeypatch):
    from core import firestore as firestore_client
    monkeypatch.setattr(firestore_client, "get_client",
                        lambda: _Istemci({}, patlat=True))
    with TestClient(app) as client:
        assert client.post(ONAY_UCU, json={"version": 1},
                           headers=basliklar()).status_code == 500


def test_firestore_kurallari_degismedi():
    """Bu kayıt için kural değişikliği GEREKMEMELİ: `private/` zaten
    istemciye kapalı. Kullanıcı dokümanına `aiConsent` alanı eklenirse bu
    test hatırlatır: o yol hasOnly listesi + değişmezlik ister."""
    kurallar = (BACKEND.parent / "infra" / "firestore.rules").read_text(
        encoding="utf-8")
    bas = kurallar.index("match /private/{document=**}")
    assert "allow read, write: if false;" in kurallar[bas:bas + 120]


@uygulama_gerekir
def test_get_ve_delete_uclari_yok(kullanici, basliklar):
    """Durum okuyan ve geri alan uçlar kalktı (sahip kararı): onları
    çağıran ekran yok, geri alma yolu hesabı silmek."""
    with TestClient(app) as client:
        assert client.get(ONAY_UCU,
                          headers=basliklar()).status_code == 405
        assert client.delete(ONAY_UCU,
                             headers=basliklar()).status_code == 405
    assert consent_service._ai_local_read() == {}


# --------------------------------------------------------------------------
# (b) Kaydı olmayan kullanıcı AI çıktısı alır — sohbet
# --------------------------------------------------------------------------

@pytest.fixture
def sohbet_llm(monkeypatch):
    """Ücretsiz kullanıcının günlük hakkı açık; LLM sahte ve sayılıyor."""
    from api import chat
    from core import device
    monkeypatch.setattr(entitlements, "FORCE_PLUS", False)
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: False)
    monkeypatch.setattr(entitlements, "get_subscription", lambda uid: {})
    monkeypatch.setattr(entitlements, "consume_quota",
                        lambda uid, key, limit: True)
    monkeypatch.setattr(device, "enforce_single_device",
                        lambda *a, **k: None)
    sayac = {"n": 0}

    def sahte_sohbet(*a, **k):
        sayac["n"] += 1
        return "Bugün Ay senin tarafında, acele etme."

    monkeypatch.setattr(chat.gemini_service, "chat", sahte_sohbet)
    return sayac


@uygulama_gerekir
def test_kayitsiz_kullanici_sohbette_ai_cevabi_alir(kullanici, sohbet_llm,
                                                    kayda_dokunan,
                                                    basliklar):
    with TestClient(app) as client:
        for surum in SURUMLER:
            yanit = client.post("/api/v1/chat",
                                json={"message": "Bugün nasıl bir gün?",
                                      "history": []},
                                headers=basliklar(surum))
            assert yanit.status_code == 200, (surum, yanit.text)
            govde = yanit.json()
            assert "blocked" not in govde, surum
            assert govde["reply"], surum
            assert "x-ai-consent" not in yanit.headers, surum

    assert sohbet_llm["n"] >= len(SURUMLER), "model hiç çağrılmadı"
    assert kayda_dokunan["n"] == 0


# --------------------------------------------------------------------------
# (b) Kaydı olmayan kullanıcı AI çıktısı alır — okumalar ve yüz okuma
# --------------------------------------------------------------------------

@pytest.fixture
def abone(monkeypatch):
    """Ücretli abone; cihaz kilidi ve cüzdan devre dışı. Konu jeton ya da
    harita hesabı değil: uç AI üretimine ULAŞIYOR mu?"""
    from core import device
    app.dependency_overrides[get_current_user] = lambda: AuthUser(
        uid=UID, email="a@b.c", admin=False, auth_time=1000)
    monkeypatch.setattr(entitlements, "FORCE_PLUS", False)
    monkeypatch.setattr(entitlements, "is_subscriber", lambda uid: True)
    monkeypatch.setattr(entitlements, "user_local_date",
                        lambda uid: dt.date(2026, 10, 22))
    monkeypatch.setattr(device, "enforce_single_device",
                        lambda *a, **k: None)
    monkeypatch.setattr(wallet, "spender", lambda uid, ozellik, **k: None)
    monkeypatch.setattr(wallet, "refund_spend", lambda uid, ozellik: True)
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def harita_sahte(monkeypatch):
    """Efemeris ve yerelleştirme devre dışı: uç yalnız sözlük kuruyor."""
    from api import reports
    harita = {"sun_sign": "Leo", "moon_sign": "Aries", "ascendant": "Libra",
              "planets": {}}
    monkeypatch.setattr(reports.astro_service, "get_natal_chart",
                        lambda **k: harita)
    monkeypatch.setattr(reports.astro_service, "subject_kwargs", lambda d: {})
    monkeypatch.setattr(reports, "get_bazi_chart", lambda **k: {"pillars": {}})
    monkeypatch.setattr(reports, "get_sky_now",
                        lambda: {"moon_phase": None, "retrogrades": []})
    monkeypatch.setattr(reports.prompts, "localize_sky",
                        lambda lang, sky: {"moon_phase": None,
                                           "retrogrades": []})
    monkeypatch.setattr(reports.prompts, "localize_chart",
                        lambda lang, c: c)
    monkeypatch.setattr(reports.prompts, "localize_bazi", lambda lang, c: c)
    return reports


@pytest.fixture
def karsi_taraf(harita_sahte, monkeypatch):
    """Arkadaş yolu: iki profil de sunucuda, hesap sahte, ölçüm LLM'siz."""
    from services import synastry_service
    r = harita_sahte
    karsi = synastry_service.Counterpart(key="onay-dost", birth={},
                                         label="Deniz")
    monkeypatch.setattr(r.profile_service, "are_friends", lambda a, b: True)
    monkeypatch.setattr(synastry_service, "friend_counterpart",
                        lambda uid, dost: karsi)
    monkeypatch.setattr(r.profile_service, "get_profile",
                        lambda uid: {"displayName": "Ada"})
    monkeypatch.setattr(r.profile_service, "birth_kwargs",
                        lambda p, lang=None: {})
    monkeypatch.setattr(r.chart_context, "has_birth_data", lambda p: True)
    monkeypatch.setattr(r.astro_service, "get_synastry",
                        lambda a, b: {"person1": {}, "person2": {}})
    monkeypatch.setattr(synastry_service, "pair_transits",
                        lambda *a, **k: None)
    return synastry_service


@pytest.fixture
def uretim(monkeypatch):
    """`report_service` üretim fonksiyonunu sayan sahte LLM kurar."""
    sayac = {"n": 0}

    def kur(modul, ad, deger=None):
        deger = deger or {"text": AI_METNI, "cached": False}

        def sahte(*a, **k):
            sayac["n"] += 1
            return dict(deger)

        monkeypatch.setattr(modul.report_service, ad, sahte)

    kur.sayac = sayac
    return kur


def _kur_iching(r, mp):
    mp.setattr(r, "cast_iching",
               lambda soru, method="coins": {"hexagram": {"n": 1}})
    mp.setattr(r, "enrich_cast", lambda cast, **k: cast)
    mp.setattr(r.profile_service, "get_profile", lambda uid: None)
    mp.setattr(r.prompts, "localize_iching", lambda lang, c: c)


def _kur_yil(r, mp):
    from services import predict_service
    mp.setattr(predict_service, "solar_return",
               lambda *a, **k: {"sun_sign": "Leo"})
    mp.setattr(r.profile_service, "get_profile", lambda uid: {})


def _kur_ic_takvim(r, mp):
    from services import predict_service
    mp.setattr(predict_service, "secondary_progressions",
               lambda *a, **k: {"moon": "Aries"})
    mp.setattr(predict_service, "solar_arc_hits", lambda *a, **k: [])
    mp.setattr(r.prompts, "localize_progressions",
               lambda lang, prog, hits: {"prog": prog, "hits": hits})


def _kur_dogum_heksagrami(r, mp):
    konum = {"gate": 25, "line": 3, "longitude": 10.0, "hour_known": True,
             "hexagram": {"number": 25}, "alternate_gate": None,
             "alternate_hexagram": None,
             "gate_passage": {"gate_tr": "Kapı dokusu", "gate_en": "Gate"}}
    mp.setattr(r.birth_hexagram_service, "birth_hexagram", lambda **k: konum)
    mp.setattr(r.prompts, "localize_hexagram", lambda lang, h: h)


def _kur_sinastri(r, mp):
    mp.setattr(r.astro_service, "get_synastry",
               lambda a, b: {"aspects": [{"p1": "sun"}]})


def _kur_hicbir_sey(r, mp):
    return None


#: Tamamen AI olan rapor uçları — U06'da hepsi `ai_onayi_zorunlu` ile
#: 403 dönebiliyordu. (yol, gövde, üretim fonksiyonu, ek kurulum)
RAPOR_UCLARI = [
    ("/api/v1/reports/daily", DOGUM, "daily_reading", _kur_hicbir_sey),
    ("/api/v1/reports/natal", DOGUM, "natal_report", _kur_hicbir_sey),
    ("/api/v1/reports/bazi", DOGUM, "bazi_report", _kur_hicbir_sey),
    ("/api/v1/reports/iching", {"method": "coins"}, "iching_reading",
     _kur_iching),
    ("/api/v1/reports/solar-return", DOGUM, "solar_return_report", _kur_yil),
    ("/api/v1/reports/progressions", DOGUM, "progressions_report",
     _kur_ic_takvim),
    ("/api/v1/reports/birth-hexagram", DOGUM, "birth_hexagram_report",
     _kur_dogum_heksagrami),
    ("/api/v1/reports/synastry", {"person1": DOGUM, "person2": DOGUM},
     "synastry_report", _kur_sinastri),
]


@uygulama_gerekir
@pytest.mark.parametrize("yol,govde,uretici,kurulum", RAPOR_UCLARI,
                         ids=[u[0].rsplit("/", 1)[1] for u in RAPOR_UCLARI])
def test_kayitsiz_kullanici_raporda_ai_okumasi_alir(
        abone, harita_sahte, uretim, kayda_dokunan, basliklar, monkeypatch,
        yol, govde, uretici, kurulum):
    kurulum(harita_sahte, monkeypatch)
    uretim(harita_sahte, uretici)

    with TestClient(app) as client:
        for surum in SURUMLER:
            yanit = client.post(yol, json=govde, headers=basliklar(surum))
            assert yanit.status_code == 200, (surum, yanit.text)
            assert "x-ai-consent" not in yanit.headers, surum
            assert _icinde(yanit.json(), AI_METNI), (surum, yanit.text)

    assert uretim.sayac["n"] == len(SURUMLER)
    assert kayda_dokunan["n"] == 0


@uygulama_gerekir
def test_kayitsiz_kullanici_ikili_dinamik_alir(abone, harita_sahte,
                                               karsi_taraf, uretim,
                                               kayda_dokunan, basliklar,
                                               monkeypatch):
    monkeypatch.setattr(harita_sahte.prompts, "sign_from_point",
                        lambda lang, p: None)
    uretim(harita_sahte, "dyad_reading")

    with TestClient(app) as client:
        for surum in SURUMLER:
            yanit = client.post("/api/v1/reports/dyad",
                                json={"friend_uid": "d"},
                                headers=basliklar(surum))
            assert yanit.status_code == 200, (surum, yanit.text)
            assert yanit.json()["data"]["reading"] == AI_METNI, surum

    assert uretim.sayac["n"] == len(SURUMLER)
    assert kayda_dokunan["n"] == 0


@uygulama_gerekir
def test_kayitsiz_kullanici_yuz_okumasi_alir(abone, uretim, kayda_dokunan,
                                             basliklar, monkeypatch):
    """Biyometrik rıza AYRI bir konu ve yerinde duruyor (sahip kararı
    yalnız AI onayını değiştirdi); burada verilmiş sayılıyor."""
    from api import face_reading
    monkeypatch.setattr(face_reading.consent_service, "has_face_consent",
                        lambda uid: True)
    monkeypatch.setattr(face_reading.profile_service, "get_profile",
                        lambda uid: {})
    monkeypatch.setattr(face_reading.chart_context, "chart_whisper",
                        lambda *a, **k: None)
    uretim(face_reading, "firasa_report")

    with TestClient(app) as client:
        for surum in SURUMLER:
            yanit = client.post("/api/v1/face/reading", json=ORANLAR,
                                headers=basliklar(surum))
            assert yanit.status_code == 200, (surum, yanit.text)
            assert _icinde(yanit.json(), AI_METNI), (surum, yanit.text)

    assert uretim.sayac["n"] == len(SURUMLER)
    assert kayda_dokunan["n"] == 0


# --------------------------------------------------------------------------
# (b) Yumuşak uçlar: hesap + yorum katmanı, `ai=0` artık hiçbir şey kapatmaz
# --------------------------------------------------------------------------

#: U06 istemcisinin "henüz karar yok" işareti. Böyle bir istemci yayına
#: hiç çıkmadı; yine de parametre artık bir şey KAPATMAMALI.
ESKI_AI0 = "?ai=0"


@pytest.fixture
def sahte_takvim(monkeypatch):
    from api import astrology
    from services import (chart_context, predict_service, profile_service,
                          signal_service)
    monkeypatch.setattr(entitlements, "FORCE_PLUS", False)
    monkeypatch.setattr(profile_service, "get_profile",
                        lambda uid: {"birthTime": "14:30"})
    monkeypatch.setattr(chart_context, "has_birth_data", lambda p: True)
    monkeypatch.setattr(profile_service, "birth_kwargs", lambda p, lang=None: {
        "name": "t", "year": 1990, "month": 5, "day": 12,
        "hour": 14, "minute": 30, "city": "Istanbul", "nation": "TR"})
    monkeypatch.setattr(predict_service, "transit_calendar", lambda **kw: {
        "events": [{"type": "aspect_exact", "date": "2026-10-25",
                    "transit": "Mars", "natal": "Venus", "aspect": "trine",
                    "orb": 0.4, "theme": "relationships",
                    "tone": "support"}],
        "active_now": []})
    monkeypatch.setattr(chart_context, "chart_facts",
                        lambda uid, p, today=None: {})
    monkeypatch.setattr(signal_service, "enrich_events",
                        lambda olaylar, natal: olaylar)
    sayac = {"n": 0}

    def sahte_yorum(events, lang):
        sayac["n"] += 1
        return {signal_service.event_fingerprint(events[0]): "Cümle."}

    monkeypatch.setattr(signal_service, "calendar_insights", sahte_yorum)
    bellek: dict = {}
    monkeypatch.setattr(cache, "get", lambda k: bellek.get(k))
    monkeypatch.setattr(cache, "set",
                        lambda k, v, ttl_seconds=None, owner_uid=None:
                        bellek.update({k: v}))
    monkeypatch.setattr(astrology, "is_subscriber", lambda uid: True)
    return sayac


@uygulama_gerekir
def test_kayitsiz_abone_takvimde_ai_yorumu_alir(kullanici, sahte_takvim,
                                                kayda_dokunan, basliklar):
    with TestClient(app) as client:
        istekler = [("/api/v1/astrology/transit-calendar" + ESKI_AI0, None)]
        istekler += [("/api/v1/astrology/transit-calendar", s)
                     for s in SURUMLER]
        for yol, surum in istekler:
            yanit = client.get(yol, headers=basliklar(surum))
            assert yanit.status_code == 200, (yol, surum, yanit.text)
            olay = yanit.json()["data"]["events"][0]
            assert olay.get("line") == "Cümle.", (yol, surum)
            assert "locked" not in olay

    # İlk istek üretti, sonrakiler aynı yorumu önbellekten okudu.
    assert sahte_takvim["n"] == 1
    assert kayda_dokunan["n"] == 0


@pytest.fixture
def sahte_sinyal(monkeypatch):
    """Sinyal hesabı ve paylaşılan AI paketi sahte; paket okuması sayılır.

    Sinyal yerelleştirilmiş alanları (technical/theme_local) zaten
    taşıyor ki uç ve bildirim yolu aynı düzenekle koşsun. `exact_on` +
    `days_to_exact == 0`: öğle bildiriminin tek kaynağı.
    """
    from services import prompts, signal_service
    ham = {"signals": [{"transit": "Mars", "natal": "Venus",
                        "aspect": "trine", "theme": "relationships",
                        "theme_local": "İlişkiler",
                        "technical": "Mars üçgen Venüs",
                        "exact_on": "2026-10-22", "days_to_exact": 0}],
           "generated_for": "2026-10-22"}
    monkeypatch.setattr(signal_service, "cached_signals",
                        lambda profile, today=None: dict(ham))
    sayac = {"n": 0}

    def paket(h, lang, generate_if_missing=True):
        sayac["n"] += 1
        return {"insights": ["Bugün ilişkilerinde sabır işine yarar."],
                "checkin_question": "Bugün kime sabır gösterdin?"}

    monkeypatch.setattr(signal_service, "cached_insight_bundle", paket)
    monkeypatch.setattr(prompts, "localize_signals",
                        lambda lang, h: {"signals": list(h["signals"])})
    monkeypatch.setattr(signal_service, "signals_fingerprint",
                        lambda h: "iz")
    monkeypatch.setattr(signal_service, "daily_focus_index",
                        lambda ham, prev_theme=None, prev_fp=None: 0)
    return sayac


@uygulama_gerekir
def test_kayitsiz_kullanici_sinyallerde_ai_yorumu_alir(kullanici, sahte_sinyal,
                                                       kayda_dokunan,
                                                       basliklar,
                                                       monkeypatch):
    from services import profile_service
    monkeypatch.setattr(profile_service, "get_profile", lambda uid: {})
    istekler = [("/api/v1/reports/signals" + ESKI_AI0, None)]
    istekler += [("/api/v1/reports/signals", s) for s in SURUMLER]
    with TestClient(app) as client:
        for yol, surum in istekler:
            yanit = client.get(yol, headers=basliklar(surum))
            assert yanit.status_code == 200, (yol, surum, yanit.text)
            veri = yanit.json()["data"]
            assert veri["signals"][0]["insight"] == \
                "Bugün ilişkilerinde sabır işine yarar.", (yol, surum)
            assert veri["checkin_question"] == "Bugün kime sabır gösterdin?"

    assert sahte_sinyal["n"] == len(istekler)
    assert kayda_dokunan["n"] == 0


@uygulama_gerekir
def test_kayitsiz_abone_iliski_yorumu_alir(abone, harita_sahte, karsi_taraf,
                                           uretim, kayda_dokunan,
                                           basliklar, monkeypatch):
    """U06'da onaysız abone `reading_ai_off` alıyordu; şimdi 33bb9f4'teki
    gibi okumayı alır."""
    monkeypatch.setattr(karsi_taraf, "axes_for",
                        lambda uid, o: {"calc_version": "1", "axes": []})
    monkeypatch.setattr(harita_sahte.prompts, "localize_relationship_axes",
                        lambda lang, e, rel: {"axes": [
                            {"axis": "communication", "level": "high"}]})
    uretim(harita_sahte, "relationship_reading",
           {"text": AI_METNI, "cached": False, "theme": AI_METNI,
            "axis_lines": {"communication": "Konuşmanız akıyor."}})

    istekler = [("/api/v1/reports/relationship" + ESKI_AI0, None)]
    istekler += [("/api/v1/reports/relationship", s) for s in SURUMLER]
    with TestClient(app) as client:
        for yol, surum in istekler:
            yanit = client.post(yol, json={"friend_uid": "d"},
                                headers=basliklar(surum))
            assert yanit.status_code == 200, (yol, surum, yanit.text)
            veri = yanit.json()["data"]
            assert "reading_ai_off" not in veri, (yol, surum)
            assert veri["reading"] == AI_METNI, (yol, surum)
            assert veri["axes"][0]["line"] == "Konuşmanız akıyor."

    assert uretim.sayac["n"] == len(istekler)
    assert kayda_dokunan["n"] == 0


# --------------------------------------------------------------------------
# (c) Sabah / öğle / akşam bildirimi — kaydı olmayan profil, appBuild 53/54
# --------------------------------------------------------------------------

@pytest.mark.parametrize("app_build", [53, 54])
def test_kayitsiz_profilde_sabah_bildirimi_ai_cumlesini_kullanir(
        sahte_sinyal, kayda_dokunan, app_build):
    """U06'nın arka plan kararı 54'ü (ve kayıtsız her yeni sürümü) teknik
    satıra düşürüyordu; 53'ün kaynağında böyle bir ayrım yok."""
    from services import notification_service as ns
    sonuc = ns.signal_push({"uid": UID, "appBuild": app_build}, "tr")
    assert sonuc is not None
    assert sonuc[1] == "Bugün ilişkilerinde sabır işine yarar."
    assert sonuc[1] != "Mars üçgen Venüs"
    assert sahte_sinyal["n"] == 1
    assert kayda_dokunan["n"] == 0


@pytest.mark.parametrize("app_build", [53, 54])
def test_kayitsiz_profilde_ogle_bildirimi_ai_cumlesini_kullanir(
        sahte_sinyal, kayda_dokunan, app_build):
    from services import notification_service as ns
    yuk, gerekce = ns.midday_push({"uid": UID, "appBuild": app_build}, "tr",
                                  today=dt.date(2026, 10, 22))
    assert gerekce == "gonderilecek"
    assert yuk[1] == "Bugün ilişkilerinde sabır işine yarar."
    assert kayda_dokunan["n"] == 0


@pytest.mark.parametrize("app_build", [53, 54])
def test_kayitsiz_profile_aksam_sorusu_gider(sahte_sinyal, kayda_dokunan,
                                            app_build):
    """U06 onaysız profilde akşam sorusunu tamamen KESİYORDU."""
    from services import notification_service as ns
    icerik = ns.checkin_push({"uid": UID, "appBuild": app_build}, "tr")
    assert icerik is not None
    assert icerik.govde == "Bugün kime sabır gösterdin?"
    assert icerik.soru is True
    assert kayda_dokunan["n"] == 0


# --------------------------------------------------------------------------
# (d) Bekçiler: kapı geri dönmez, "hayır" yazan yol doğmaz
# --------------------------------------------------------------------------

def _bagimliliklar(dependant) -> set:
    toplam = {getattr(d, "call", None) for d in dependant.dependencies}
    for alt in dependant.dependencies:
        toplam |= _bagimliliklar(alt)
    return toplam


def _parametre_adlari(dependant) -> set[str]:
    adlar = {p.name for p in dependant.query_params}
    for alt in dependant.dependencies:
        adlar |= _parametre_adlari(alt)
    return adlar


def _rotalar(rotalar, onek: str = "", ust: tuple = ()):
    """(tam yol, APIRoute, üst düzey bağımlılık çağrıları) üçlüleri.

    ⚠️ `app.routes` DÜZ DEĞİL: bu FastAPI sürümünde `include_router` alt
    yolları `_IncludedRouter` sarmalayıcısı altında bırakıyor (ölçüldü:
    düz okumada 4 APIRoute, ilk yazımda bekçi tam bu yüzden kördü —
    test_web_seo ve test_horoscope_warm aynı tuzağı yazıyor). Sarmalayıcı
    `original_router` + `include_context` (önek ve ekleme anındaki
    bağımlılıklar) taşıyor; ikisi de gezilir. Ekleme anındaki bağımlılık
    rotanın `dependant`ına girmeyebilir, o yüzden ayrıca toplanır.
    """
    for rota in rotalar:
        if isinstance(rota, APIRoute):
            yield onek + rota.path, rota, ust
        alt = getattr(rota, "original_router", None)
        if alt is None:
            continue
        baglam = rota.include_context
        ek = tuple(getattr(d, "dependency", None)
                   for d in [*(baglam.dependencies or []),
                             *(alt.dependencies or [])])
        yield from _rotalar(alt.routes, onek + (baglam.prefix or ""),
                            ust + ek)


@uygulama_gerekir
def test_hicbir_rota_bagimliliginda_onay_kapisi_yok():
    """Kapı bir route bağımlılığıydı (`ai_onayi_zorunlu`) ve yumuşak
    uçlarda `ai` sorgu parametresiydi. İkisinin de hiçbir rotada geri
    gelmediği burada ölçülür — uç başına test, yazılmayan ucu korumaz."""
    rotalar = list(_rotalar(app.routes))
    yollar = {yol for yol, _, _ in rotalar}
    # Ölçüm kör değil: U06'nın kapı koyduğu uçlar gerçekten geziliyor.
    assert {"/api/v1/chat", "/api/v1/reports/daily", "/api/v1/face/reading",
            "/api/v1/reports/signals", "/api/v1/astrology/transit-calendar",
            "/api/v1/reports/relationship"} <= yollar
    for yol, rota, ust in rotalar:
        for cagri in _bagimliliklar(rota.dependant) | set(ust):
            ad = (getattr(cagri, "__qualname__", "") or "").lower()
            modul = getattr(cagri, "__module__", "") or ""
            assert "ai_consent" not in modul, (yol, modul)
            assert "onay" not in ad and "consent" not in ad, (yol, ad)
        assert "ai" not in _parametre_adlari(rota.dependant), yol


def _tum_rotalar(rotalar, onek: str = ""):
    """HER yaprak rota: (yöntem, tam yol) çiftleri.

    `_rotalar` yalnız APIRoute veriyor (bağımlılık bekçisinin işi o);
    burada soru "bu önekte NE var" ve cevap türden bağımsız olmalı:
    düz Starlette `Route` (/openapi.json bunlardan), WebSocket rotası ve
    `Mount` altındaki alt uygulama da bir geri alma ya da okuma yolu
    açabilir. Sarmalayıcıya (`original_router`) ve `Mount`a (`routes`)
    iner; yöntemsiz yaprak "WS" sayılır ki gözden kaçmasın.
    """
    for rota in rotalar:
        alt = getattr(rota, "original_router", None)
        if alt is not None:
            yield from _tum_rotalar(
                alt.routes, onek + (rota.include_context.prefix or ""))
            continue
        yol = onek + getattr(rota, "path", "")
        ic = getattr(rota, "routes", None)
        if ic is not None and not isinstance(rota, APIRoute):
            yield from _tum_rotalar(ic, yol)
            continue
        for yontem in (getattr(rota, "methods", None) or {"WS"}):
            yield yontem, yol


@uygulama_gerekir
def test_onay_onekinde_yalniz_post_var():
    """`/api/v1/account/ai-consent` ile BAŞLAYAN her rota — alt yollar
    (`/ai-consent/geri-al`, `/ai-consent/durum`) ve aynı ucun başka
    yöntemleri dahil — tam olarak tek POST. Kaldırılan GET/DELETE ya da
    yeni bir "geri al" ucu, kimsenin okumadığı bir red durumu üretirdi
    (sahip kararı 2026-10-22: geri alma yolu hesabı silmek)."""
    rotalar = set(_tum_rotalar(app.routes))
    # Ölçüm kör değil: iç içe `include_router` altındaki komşu uçlar ve
    # sarmalayıcı dışındaki düz Starlette rotası da görülüyor.
    assert {("POST", "/api/v1/account/consent"),
            ("DELETE", "/api/v1/account/me"),
            ("GET", "/openapi.json")} <= rotalar
    onekte = {(yontem, yol) for yontem, yol in rotalar
              if yol.startswith(ONAY_UCU)}
    assert onekte == {("POST", ONAY_UCU)}


def _cagri_yerleri(ad: str) -> set[tuple[str, str]]:
    """`ad` adına yapılan HER başvurunun (dosya, kapsayan fonksiyon) kümesi.

    Yalnız `x.ad(...)` çağrısı değil: çıplak `ad` adı (`from ... import
    ad`), içe aktarma takma adı ve `getattr(m, "ad")` dizesi de sayılır
    — bunların her biri fonksiyonu başka bir yerden çağırmanın yolu.
    Tanımın kendisi (`def ad`) bir başvuru değildir, sayılmaz.
    """
    bulunan: set[tuple[str, str]] = set()

    class _Gezgin(ast.NodeVisitor):
        def __init__(self, goreli):
            self.goreli = goreli
            self.yigin: list[str] = []

        def _isaretle(self):
            bulunan.add((self.goreli,
                         self.yigin[-1] if self.yigin else "<modül>"))

        def visit_FunctionDef(self, dugum):
            self.yigin.append(dugum.name)
            self.generic_visit(dugum)
            self.yigin.pop()

        visit_AsyncFunctionDef = visit_FunctionDef

        def visit_Attribute(self, dugum):
            if dugum.attr == ad:
                self._isaretle()
            self.generic_visit(dugum)

        def visit_Name(self, dugum):
            if dugum.id == ad:
                self._isaretle()

        def visit_alias(self, dugum):
            if dugum.name == ad:
                self._isaretle()

        def visit_Constant(self, dugum):
            if dugum.value == ad:
                self._isaretle()

    for goreli, agac in _kaynaklar():
        _Gezgin(goreli).visit(agac)
    return bulunan


@uygulama_gerekir
def test_ai_onayini_yalniz_onay_ucu_yazar():
    """`grant_ai_consent`i çağıran TEK fonksiyon POST /ai-consent işleyicisi.

    Kanıt yalnız kutuyu İŞARETLEYEN kişi için yazılır; şartlar ucu, giriş
    kancası ya da bir göç betiği onu da yazarsa 53'ten gelen ve kutuyu hiç
    görmemiş hesaplar adına sunucuda VERİLMEMİŞ bir onay belirir. AST —
    yorumlar ("tek yazan grant_ai_consent") görülmez."""
    assert _cagri_yerleri("grant_ai_consent") == {
        ("api/account.py", "grant_ai_consent")}
    # O fonksiyon gerçekten POST /ai-consent işleyicisi: ad eşleşmesi
    # başka bir uca taşınmış bir çağrıyı örtmesin.
    isleyiciler = {(rota.endpoint.__module__, rota.endpoint.__name__,
                    tuple(sorted(rota.methods)))
                   for yol, rota, _ in _rotalar(app.routes)
                   if yol == ONAY_UCU}
    assert isleyiciler == {("api.account", "grant_ai_consent", ("POST",))}


@uygulama_gerekir
def test_sartlar_onayi_ai_onayi_kaydi_dogurmaz(kullanici, basliklar,
                                              monkeypatch):
    """Davranış yüzü: şartlar kutusunun kanıtı (`POST /consent`) AI
    onayının kanıtını yazmaz. İki kutu ayrı; birinin kaydı ötekini
    doğursaydı ayrı kutunun anlamı kalmazdı (GDPR Md.7(2) paket rıza)."""
    from core import firestore as firestore_client
    with TestClient(app) as client:
        # Yerel dal (Firestore pinli): şartlar kaydı yazılır, AI kaydı yok.
        assert client.post("/api/v1/account/consent", json={"version": 1},
                           headers=basliklar()).status_code == 200
        assert consent_service._ai_local_read() == {}

        # Firestore dalı: aynı istek `private/aiConsent`e hiçbir şey
        # yazmaz (şartlar kaydı kullanıcı dokümanına iner).
        yazilan: dict = {}
        monkeypatch.setattr(firestore_client, "get_client",
                            lambda: _HerSeyiKaydeden(yazilan))
        assert client.post("/api/v1/account/consent", json={"version": 1},
                           headers=basliklar()).status_code == 200
    assert f"users/{UID}" in yazilan, "ölçüm kör: şartlar kaydı görülmedi"
    assert not any(yol.endswith("/aiConsent") for yol in yazilan), yazilan


def test_kapi_modulu_geri_dogmaz():
    """`core/ai_consent.py` eşiği, kararı ve 403'ü taşıyordu; kaldırıldı.
    Aynı adla geri gelen bir modül büyük olasılıkla kapıyı geri getirir —
    sahip kararı (2026-10-22) değişmeden bu dosya doğmamalı."""
    assert importlib.util.find_spec("core.ai_consent") is None


@functools.lru_cache(maxsize=1)
def _kaynak_agaclari() -> tuple:
    """Bir kez ayrıştırılır: bu dosyadaki AST bekçileri tüm kaynağı
    defalarca geziyor ve her gezinti yeniden ayrıştırınca takıma saniyeler
    ekliyordu. Ağaçlar salt okunur gezilir, paylaşmak güvenli; mutasyon
    sınaması her mutasyonda yeni süreç açtığı için bayat ağaç görmez."""
    sonuc = []
    for yol in sorted(BACKEND.rglob("*.py")):
        goreli = yol.relative_to(BACKEND).as_posix()
        if goreli.startswith((".venv/", "tests/")) or "/." in "/" + goreli:
            continue
        sonuc.append((goreli, ast.parse(yol.read_text(encoding="utf-8"))))
    return tuple(sonuc)


def _kaynaklar():
    """Testler ve sanal ortam dışındaki backend kaynakları."""
    return iter(_kaynak_agaclari())


#: "granted: False" yazmasına İZİN verilen yerler — yalnız BİYOMETRİK
#: (yüz) rızanın geri alınması. O rıza sahip kararının dışında ve geri
#: alınabilir kalmalı (GDPR Md.9; `consent_service` dosya başı).
_YUZ_RIZASI_GERI_ALMA = {
    ("services/consent_service.py", "withdraw_face_consent"),
    ("api/face_reading.py", "withdraw_consent"),
}


class _RedBulucu(ast.NodeVisitor):
    """`"granted": False` kuran sözlük, `granted=False` anahtar sözcüğü ve
    `x["granted"] = False` ataması — hangi fonksiyonun içinde olduğuyla."""

    def __init__(self):
        self.yigin: list[str] = []
        self.bulunan: list[str] = []

    def _isaretle(self):
        self.bulunan.append(self.yigin[-1] if self.yigin else "<modül>")

    def visit_FunctionDef(self, dugum):
        self.yigin.append(dugum.name)
        self.generic_visit(dugum)
        self.yigin.pop()

    visit_AsyncFunctionDef = visit_FunctionDef

    @staticmethod
    def _yanlis_mi(deger) -> bool:
        return isinstance(deger, ast.Constant) and deger.value is False

    def visit_Dict(self, dugum):
        for anahtar, deger in zip(dugum.keys, dugum.values):
            if (isinstance(anahtar, ast.Constant)
                    and anahtar.value == "granted" and self._yanlis_mi(deger)):
                self._isaretle()
        self.generic_visit(dugum)

    def visit_Call(self, dugum):
        for kw in dugum.keywords:
            if kw.arg == "granted" and self._yanlis_mi(kw.value):
                self._isaretle()
        self.generic_visit(dugum)

    def visit_Assign(self, dugum):
        for hedef in dugum.targets:
            if (isinstance(hedef, ast.Subscript)
                    and isinstance(hedef.slice, ast.Constant)
                    and hedef.slice.value == "granted"
                    and self._yanlis_mi(dugum.value)):
                self._isaretle()
        self.generic_visit(dugum)


def test_ai_onayi_icin_granted_false_yazan_yol_yok():
    """AST ile, metinle DEĞİL: "bir şeyin yokluğunu arayan bekçi onu
    anlatan yorumu görmemeli" (CLAUDE.md §5) — bu dosyanın ve
    `consent_service`in yorumları tam da "hayır yazan yol yok" diyor."""
    bulunan = set()
    for goreli, agac in _kaynaklar():
        bulucu = _RedBulucu()
        bulucu.visit(agac)
        bulunan |= {(goreli, fn) for fn in bulucu.bulunan}
    # Ölçüm kör değil: yüz rızasının geri alma yolları görülüyor.
    assert _YUZ_RIZASI_GERI_ALMA <= bulunan
    assert bulunan - _YUZ_RIZASI_GERI_ALMA == set()


def test_kapinin_adlari_kodda_yasamaz():
    """403 işareti, insan metni ve eşik anahtarları yalnız kapıya
    hizmet ediyordu. Kod sabiti olarak geri dönmeleri kapının geri
    döndüğünün işaretidir. AST sabitleri — yorumlar görülmez."""
    yasak = {"X-Ai-Consent", "ai_consent_required", "aiConsentMinBuild",
             "RYTHO_AI_CONSENT_MIN_BUILD", "reading_ai_off"}
    bulunan = set()
    for goreli, agac in _kaynaklar():
        for dugum in ast.walk(agac):
            if isinstance(dugum, ast.Constant) and isinstance(dugum.value,
                                                              str):
                for ad in yasak:
                    if ad in dugum.value:
                        bulunan.add((goreli, ad))
    assert bulunan == set()


def test_ai_onay_dokumanina_yalniz_onay_yazilir():
    """`aiConsent` dokümanının adı kodda tek yerde: `_ai_doc`. Ona giden
    tek yazım `grant_ai_consent`'in ``granted: True`` kaydı."""
    bulunan = set()
    for goreli, agac in _kaynaklar():
        for dugum in ast.walk(agac):
            if isinstance(dugum, ast.Constant) and dugum.value == "aiConsent":
                bulunan.add(goreli)
    assert bulunan == {"services/consent_service.py"}
    assert {ad for ad in dir(consent_service) if "ai" in ad.lower()
            and "consent" in ad.lower()} == {"AI_CONSENT_VERSION",
                                             "grant_ai_consent"}


# --------------------------------------------------------------------------
# (e) aiConsent dokümanını silen TEK yol hesap silme
# --------------------------------------------------------------------------
#
# Geri alma yolu hesabı silmek (sahip kararı 2026-10-22; gizlilik metni bu
# yolu anlatıyor). Kanıtı tek başına silen bir yol — "geri al" ucu, bakım
# betiği, `private` altını süpüren bir yardımcı — iki kusur birden üretir:
# hesap ve ondan beri giden veri dururken aktarımın dayanağı kaybolur, ve
# kimsenin okumadığı bir "geri alındı" durumu doğar.

#: Firestore istemcisinin silme yüzü. `.delete()` blob ve HTTP istemcisinde
#: de var; o fonksiyonlar yalnız aşağıdaki `private` erişimiyle BİRLİKTE
#: sayıldığı için yanlış pozitif üretmez.
_SILME_ADLARI = {"delete", "recursive_delete"}


def _fonksiyonlar(agac):
    return [d for d in ast.walk(agac)
            if isinstance(d, (ast.FunctionDef, ast.AsyncFunctionDef))]


def _silen_fonksiyonlar(agac) -> set[str]:
    """Doğrudan ya da AYNI modüldeki bir silen yardımcıyı çağırarak silen
    fonksiyon adları.

    Modül içi geçişlilik şart: hesap silme `private`'ı
    `_delete_user_subcollections` → `_delete_collection` zinciriyle
    siliyor ve `.delete()` yalnız ikincisinde yazılı. Modüller ARASI ad
    eşleştirmesi bilerek yok: `get` gibi ortak adlar (önbellek okuması
    süresi geçmiş dokümanı siler) her okumayı "silen" yapardı.
    """
    fonksiyonlar = _fonksiyonlar(agac)
    silen = {f.name for f in fonksiyonlar
             if any(isinstance(c, ast.Call)
                    and isinstance(c.func, ast.Attribute)
                    and c.func.attr in _SILME_ADLARI
                    for c in ast.walk(f))}
    degisti = True
    while degisti:
        degisti = False
        for f in fonksiyonlar:
            if f.name in silen:
                continue
            if any(isinstance(c, ast.Call) and isinstance(c.func, ast.Name)
                   and c.func.id in silen for c in ast.walk(f)):
                silen.add(f.name)
                degisti = True
    return silen


def _private_kumeleri() -> set[str]:
    """Değeri "private" içeren modül düzeyi demet/liste/küme adları.

    `_SUB_COLLECTIONS` böyle bir ad: `collection(ad)` çağrısında koleksiyon
    adı değişkenden geldiği için "private" sabiti çağrının yanında hiç
    görünmez. Bu adlara başvuru, `private`'ın tamamına erişim sayılır.
    """
    adlar: set[str] = set()
    for _, agac in _kaynaklar():
        for dugum in agac.body:
            if isinstance(dugum, ast.Assign):
                hedefler, deger = dugum.targets, dugum.value
            elif isinstance(dugum, ast.AnnAssign) and dugum.value:
                hedefler, deger = [dugum.target], dugum.value
            else:
                continue
            if (isinstance(deger, (ast.Tuple, ast.List, ast.Set))
                    and any(isinstance(e, ast.Constant)
                            and e.value == "private"
                            for e in ast.walk(deger))):
                adlar |= {h.id for h in hedefler if isinstance(h, ast.Name)}
    return adlar


def _belirli_private_dokumani_mi(sabit, ust) -> bool:
    """`collection("private").document("<sabit>")` — aiConsent DIŞINDA
    adı sabit tek bir doküman (wallet, memory, phone...)."""
    cagri = ust.get(id(sabit))
    oz = ust.get(id(cagri))
    dok_cagri = ust.get(id(oz))
    return (isinstance(cagri, ast.Call) and len(cagri.args) == 1
            and cagri.args[0] is sabit
            and isinstance(cagri.func, ast.Attribute)
            and cagri.func.attr == "collection"
            and isinstance(oz, ast.Attribute) and oz.value is cagri
            and oz.attr == "document"
            and isinstance(dok_cagri, ast.Call) and dok_cagri.func is oz
            and len(dok_cagri.args) == 1
            and isinstance(dok_cagri.args[0], ast.Constant)
            and isinstance(dok_cagri.args[0].value, str)
            and dok_cagri.args[0].value != "aiConsent")


def _genel_private_erisimi(fonksiyon, kumeler: set[str]) -> bool:
    """Fonksiyon `private` altında aiConsent'e UZANABİLEN bir şeye dokunuyor
    mu: koleksiyonun tamamı (akış, sorgu, `collection_group`, değişken
    doküman adı, "private"in argüman olarak taşınması), "private" içeren
    bir modül kümesi ya da `recursive_delete`."""
    ust = {id(cocuk): dugum for dugum in ast.walk(fonksiyon)
           for cocuk in ast.iter_child_nodes(dugum)}
    for dugum in ast.walk(fonksiyon):
        if (isinstance(dugum, ast.Constant) and dugum.value == "private"
                and not _belirli_private_dokumani_mi(dugum, ust)):
            return True
        if isinstance(dugum, ast.Name) and dugum.id in kumeler:
            return True
        if isinstance(dugum, ast.Attribute) and (
                dugum.attr in kumeler or dugum.attr == "recursive_delete"):
            return True
    return False


def test_ai_onay_dokumani_yalniz_hesap_silmeyle_silinir():
    """aiConsent'e uzanan HER silme yolu hesap silmeden geçer.

    Üç kapı:
    1. Dokümanı ADIYLA tutan fonksiyonlar (`"aiConsent"` sabiti ya da
       `_ai_doc` başvurusu) yalnız yazanlar ve hiçbiri silmez — "geri al"
       fonksiyonu ancak bu adlardan biriyle kurulabilir.
    2. `private`'ın tamamına dokunan silen fonksiyon yalnız
       `_delete_user_subcollections`.
    3. Onu çağıran yalnız `delete_account` (kullanıcının ve panelin hesap
       silmesi ikisi de bu fonksiyon).

    Sınır beyanı: değişken adlı bir fabrika (`entitlements._private_doc`)
    üzerinden silme burada görülmez; ona "aiConsent" adını verecek sabit
    `test_ai_onay_dokumanina_yalniz_onay_yazilir` ile tek dosyaya
    kilitli. Davranış yüzü (hesap silme dokümanı gerçekten siler)
    `test_account_deletion.py`de.
    """
    adlayan = _cagri_yerleri("aiConsent") | _cagri_yerleri("_ai_doc")
    assert adlayan == {("services/consent_service.py", "_ai_doc"),
                       ("services/consent_service.py", "grant_ai_consent")}
    consent_agaci = ast.parse((BACKEND / "services" / "consent_service.py")
                              .read_text(encoding="utf-8"))
    assert {fn for _, fn in adlayan} & _silen_fonksiyonlar(consent_agaci) \
        == set()

    kumeler = _private_kumeleri()
    # Ölçüm kör değil: hesap silmenin değişken adlı süpürmesi görülüyor.
    assert "_SUB_COLLECTIONS" in kumeler
    supurenler = set()
    for goreli, agac in _kaynaklar():
        silen = _silen_fonksiyonlar(agac)
        for f in _fonksiyonlar(agac):
            if f.name in silen and _genel_private_erisimi(f, kumeler):
                supurenler.add((goreli, f.name))
    assert supurenler == {("services/account_service.py",
                           "_delete_user_subcollections")}

    assert _cagri_yerleri("_delete_user_subcollections") == {
        ("services/account_service.py", "delete_account")}

r"""infra/build-ipa.sh — iOS yayın kapısının her kapısı, kırmızı ve yeşil.

Betik `build-aab.ps1`'in aynası (U05): Android'de 1.5.0+17 düz komutla
anahtarsız çıktı ve kusur ancak mağazada görüldü; iOS'ta `test_` önekli
RevenueCat anahtarıyla yapılan Release derlemesi "başarılı" çıkıyordu
(hazırlık denetimi, 2026-10-23). Her kapı SESSİZ bir kusuru durduruyor;
bu dosya her birinin hem kusurlu girdide KALDI hem doğru girdide GEÇTİ
dediğini ölçüyor.

Yöntem: betik SAHTE bir depo ağacına kopyalanıp orada koşturulur (kendi
kökünü kendi yerinden çözüyor, üretim kodunda test kancası YOK). Dış
araçlar (`xcodebuild`, `codesign`, `flutter`) PATH'in önüne konan sahte
betiklerle değiştirilir; `python3`, `unzip`, `mktemp` gerçektir.

Yalnız macOS: betik /bin/bash 3.2 + BSD `mktemp -t` + `codesign` dünyası
için yazıldı ve iOS paketi zaten yalnız Mac'te derlenir.

Çalıştırma:
    .venv/bin/python -m pytest tests/test_build_ipa.py -q
"""
from __future__ import annotations

import json
import os
import pathlib
import plistlib
import shutil
import stat
import subprocess
import sys
import zipfile

import pytest

pytestmark = pytest.mark.skipif(
    sys.platform != "darwin",
    reason="build-ipa.sh yalnız macOS'ta koşar (iOS derlemesi yalnız Mac'te)")

_KOK = pathlib.Path(__file__).resolve().parents[2]
_BETIK = _KOK / "infra" / "build-ipa.sh"

TAKIM = "292WJ9TP74"
IOS_ANAHTAR = "appl_SahteIosAnahtariOlcum0000"
YETKI = "RhytoAI Pro"
IZINLER = [
    "NSCameraUsageDescription",
    "NSContactsUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSPhotoLibraryAddUsageDescription",
    "NSPhotoLibraryUsageDescription",
]
IYI_YETKILER = {
    "aps-environment": "production",
    "com.apple.developer.applesignin": ["Default"],
    "com.apple.developer.associated-domains": ["applinks:rytho.app"],
    "com.apple.developer.devicecheck.appattest-environment": "production",
}

_SAHTE_XCODEBUILD = """#!/bin/bash
echo "${SAHTE_XCODE:-Xcode 26.6}"
echo "Build version 17F113"
"""

# SAHTE_IMZA: yok | adhoc | <yetki plist yolu> (imzalı)
_SAHTE_CODESIGN = """#!/bin/bash
if [ "$1" = "-dv" ]; then
  case "${SAHTE_IMZA:-yok}" in
    yok) echo "$2: code object is not signed at all" >&2; exit 1 ;;
    adhoc) echo "Executable=$2/Runner" >&2; echo "Signature=adhoc" >&2; exit 0 ;;
    *) echo "Authority=Apple Distribution: Sahte" >&2; echo "TeamIdentifier=292WJ9TP74" >&2; exit 0 ;;
  esac
fi
cat "$SAHTE_IMZA"
"""

# Çağrıyı kaydeder; SAHTE_IPA verilmişse onu derleme çıktısına koyar.
_SAHTE_FLUTTER = """#!/bin/bash
echo "$PWD|$*" >> "$SAHTE_FLUTTER_KAYIT"
if [ -n "${SAHTE_IPA:-}" ]; then
  mkdir -p build/ios/ipa
  cp "$SAHTE_IPA" build/ios/ipa/Rytho.ipa
fi
exit "${SAHTE_FLUTTER_KODU:-0}"
"""


def _calistirilabilir(yol: pathlib.Path, icerik: str) -> None:
    yol.parent.mkdir(parents=True, exist_ok=True)
    yol.write_text(icerik, encoding="utf-8")
    yol.chmod(yol.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _pbxproj(takim: str = TAKIM, yorum: str = "") -> str:
    satir = f"\t\t\t\tDEVELOPMENT_TEAM = {takim};\n"
    return ("// !$*UTF8*$!\n{\n" + yorum + satir * 3
            + "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = ai.rytho;\n}\n")


def _aasa(app_id: str = f"{TAKIM}.ai.rytho") -> str:
    return json.dumps({"applinks": {"apps": [], "details": [
        {"appID": app_id, "paths": ["/i/*", "/r/*"]}]}})


class Agac:
    """Sahte depo: betik, kaynak dosyalar, sahte araçlar, sahte paketler."""

    def __init__(self, kok: pathlib.Path):
        self.kok = kok
        self.betik = kok / "infra" / "build-ipa.sh"
        self.betik.parent.mkdir(parents=True)
        shutil.copy2(_BETIK, self.betik)
        self.mobil = kok / "apps" / "mobile"
        self.bin = kok / "sahte-bin"
        self.kayit = kok / "flutter-kayit.txt"
        _calistirilabilir(self.bin / "xcodebuild", _SAHTE_XCODEBUILD)
        _calistirilabilir(self.bin / "codesign", _SAHTE_CODESIGN)
        _calistirilabilir(self.bin / "flutter", _SAHTE_FLUTTER)
        self.pubspec("1.20.0+54")
        self.pbxproj(_pbxproj())
        self.aasa(_aasa())
        self.defines()

    def pubspec(self, surum: str) -> None:
        yol = self.mobil / "pubspec.yaml"
        yol.parent.mkdir(parents=True, exist_ok=True)
        yol.write_text(f"name: rytho\nversion: {surum}\n\nenvironment:\n"
                       "  sdk: ^3.12.0\n", encoding="utf-8")

    def pbxproj(self, metin: str) -> None:
        yol = self.mobil / "ios" / "Runner.xcodeproj" / "project.pbxproj"
        yol.parent.mkdir(parents=True, exist_ok=True)
        yol.write_text(metin, encoding="utf-8")

    def aasa(self, metin: str) -> None:
        yol = self.kok / "web" / ".well-known" / "apple-app-site-association"
        yol.parent.mkdir(parents=True, exist_ok=True)
        yol.write_text(metin, encoding="utf-8")

    def defines(self, **alanlar) -> pathlib.Path:
        d = {"REVENUECAT_ANDROID_KEY": "goog_SahteAndroidAnahtari00000",
             "REVENUECAT_IOS_KEY": IOS_ANAHTAR,
             "APPSTORE_APP_ID": "1234567890",
             "RYTHO_PLUS_ENTITLEMENT": YETKI}
        d.update(alanlar)
        yol = self.mobil / "dart_defines.local.json"
        yol.write_text(json.dumps(d), encoding="utf-8")
        return yol

    def app(self, ad: str = "Runner.app", *, app_ikilisi: bytes | None = None,
            runner_ikilisi: bytes | None = None, info: dict | None = None,
            izinler: list[str] | None = None, manifest: bytes | None = b"ok",
            ek_dosya: tuple[str, bytes] | None = None) -> pathlib.Path:
        """Gerçek Release paketinin kapıların baktığı iskeleti.

        Varsayılanlar YEŞİL. App ikilisinde çıplak 'test_' öneki de var:
        gerçek pakette uygulamanın kendi `kRcTestStoreOneki` sabiti duruyor
        (ölçüldü 2026-10-23) ve kapı ona takılmamalı.
        """
        app = self.kok / "paketler" / ad
        (app / "Frameworks" / "App.framework").mkdir(parents=True)
        if app_ikilisi is None:
            app_ikilisi = (b"\x00dart\x00" + IOS_ANAHTAR.encode() + b"\x00"
                           + YETKI.encode() + b"\x00test_\x00son")
        (app / "Frameworks" / "App.framework" / "App").write_bytes(app_ikilisi)
        if runner_ikilisi is None:
            runner_ikilisi = b"\xcf\xfa\xed\xfe MLKFaceDetector \x00"
        (app / "Runner").write_bytes(runner_ikilisi)
        plist = {"CFBundleIdentifier": "ai.rytho",
                 "CFBundleVersion": "54",
                 "CFBundleSupportedPlatforms": ["iPhoneOS"]}
        for k in (IZINLER if izinler is None else izinler):
            plist[k] = "metin"
        plist.update(info or {})
        (app / "Info.plist").write_bytes(
            plistlib.dumps(plist, fmt=plistlib.FMT_BINARY))
        if manifest == b"ok":
            manifest = plistlib.dumps({"NSPrivacyTracking": False})
        if manifest is not None:
            (app / "PrivacyInfo.xcprivacy").write_bytes(manifest)
        if ek_dosya:
            yol = app / ek_dosya[0]
            yol.parent.mkdir(parents=True, exist_ok=True)
            yol.write_bytes(ek_dosya[1])
        return app

    def ipa(self, app: pathlib.Path) -> pathlib.Path:
        yol = self.kok / "paketler" / (app.stem + ".ipa")
        with zipfile.ZipFile(yol, "w") as z:
            for dosya in app.rglob("*"):
                z.write(dosya, "Payload/" + app.name + "/"
                        + dosya.relative_to(app).as_posix())
        return yol

    def yetkiler(self, **degisen) -> pathlib.Path:
        y = dict(IYI_YETKILER)
        for k, v in degisen.items():
            k = k.replace("__", "-").replace("_", ".")
            if v is None:
                y.pop(k, None)
            else:
                y[k] = v
        yol = self.kok / "yetkiler.plist"
        yol.write_bytes(plistlib.dumps(y))
        return yol

    def kos(self, *args: str, **ortam: str) -> subprocess.CompletedProcess:
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}{os.pathsep}{env.get('PATH', '')}"
        env["SAHTE_FLUTTER_KAYIT"] = str(self.kayit)
        env.update(ortam)
        return subprocess.run([str(self.betik), *args], cwd=self.kok,
                              env=env, capture_output=True, text=True,
                              encoding="utf-8", timeout=120)


def _durum(cikti: str, kapi: str) -> str:
    """Kapının satırındaki hüküm: GEÇTİ / KALDI / ATLANDI (…)."""
    for satir in cikti.splitlines():
        if not satir.startswith("["):
            continue
        hukum, _, kalan = satir[1:].partition("] ")
        if kalan.split(":")[0].strip() == kapi:
            return hukum
    raise AssertionError(f"'{kapi}' kapısının satırı yok:\n{cikti}")


def _satir(cikti: str, kapi: str) -> str:
    return next(s for s in cikti.splitlines() if f"] {kapi}" in s)


@pytest.fixture
def agac(tmp_path) -> Agac:
    return Agac(tmp_path)


# ---------------------------------------------------------------- ön kapılar

_ON_KAPILAR = ["xcode-surumu", "define-dosyasi", "revenuecat-ios-anahtari",
               "revenuecat-android-anahtari", "appstore-app-id",
               "plus-yetkisi", "imza-takimi", "derleme-numarasi"]


def test_kuru_yesil_derleme_yok(agac):
    s = agac.kos("--kuru")
    assert s.returncode == 0, s.stdout + s.stderr
    for kapi in _ON_KAPILAR:
        assert _durum(s.stdout, kapi) == "GEÇTİ", kapi
    assert not agac.kayit.exists(), "--kuru flutter'ı çağırmamalı"


def test_xcode_27_kalir(agac):
    s = agac.kos("--kuru", SAHTE_XCODE="Xcode 27.0")
    assert s.returncode == 1
    assert _durum(s.stdout, "xcode-surumu") == "KALDI"
    assert "Xcode-26.app" in _satir(s.stdout, "xcode-surumu")


@pytest.mark.parametrize("anahtar, beklenen_parca", [
    ("", "boş"),
    ("test_SahteTestStoreAnahtari0000", "Test Store"),
    ("goog_SahteAndroidAnahtari00000", "'appl_' ile başlamıyor"),
])
def test_ios_anahtari_appl_degilse_kalir(agac, anahtar, beklenen_parca):
    agac.defines(REVENUECAT_IOS_KEY=anahtar)
    s = agac.kos("--kuru")
    assert s.returncode == 1
    assert _durum(s.stdout, "revenuecat-ios-anahtari") == "KALDI"
    assert beklenen_parca in _satir(s.stdout, "revenuecat-ios-anahtari")
    if anahtar:
        assert anahtar not in s.stdout, "anahtarın kendisi basılmamalı"


@pytest.mark.parametrize("deger", ["", "TODO", "12a4"])
def test_appstore_app_id_sayisal_olmali(agac, deger):
    agac.defines(APPSTORE_APP_ID=deger)
    s = agac.kos("--kuru")
    assert _durum(s.stdout, "appstore-app-id") == "KALDI"
    assert s.returncode == 1


@pytest.mark.parametrize("alan_adi, deger", [
    # Bu beklenti bir tur boyunca TERSTİ ("kapı onu kırpıp kabul ediyor").
    # Uygulama HAM değeri okur — `--dart-define-from-file` kırpmıyor
    # (ölçüldü 2026-10-24: " 123" → mağaza bağlantısı "id%20123").
    ("APPSTORE_APP_ID", "1234567890 "),
    ("APPSTORE_APP_ID", " 1234567890"),
    ("REVENUECAT_IOS_KEY", IOS_ANAHTAR + " "),
    ("REVENUECAT_IOS_KEY", " " + IOS_ANAHTAR),
])
def test_bas_son_boslugu_olan_deger_kalir(agac, alan_adi, deger):
    agac.defines(**{alan_adi: deger})
    s = agac.kos("--kuru")
    kapi = {"APPSTORE_APP_ID": "appstore-app-id",
            "REVENUECAT_IOS_KEY": "revenuecat-ios-anahtari"}[alan_adi]
    assert s.returncode == 1
    satir = _satir(s.stdout, kapi)
    assert satir.startswith("[KALDI]")
    assert "baş/son boşluk" in satir and "ham değeri okur" in satir
    assert IOS_ANAHTAR not in s.stdout, "anahtarın kendisi basılmamalı"


def test_bosluklu_anahtar_paket_kapisinda_da_kalir(agac):
    # Kırpılmış anahtar ham değerin ALT DİZESİ: eski kapı paketi kırpılmış
    # hâliyle arayıp "anahtar pakette" diyordu (çürütme turu, 2026-10-24).
    agac.defines(REVENUECAT_IOS_KEY=IOS_ANAHTAR + " ")
    s = agac.kos("--yalniz-denetle", str(agac.app()))
    assert s.returncode == 1
    satir = _satir(s.stdout, "paket-revenuecat-anahtari")
    assert satir.startswith("[KALDI]") and "baş/son boşluk" in satir


@pytest.mark.parametrize("anahtar, beklenen", [
    ("test_SahteAndroidTestStore00000", "KALDI"),
    ("goog_SahteAndroidAnahtari00000", "GEÇTİ"),
    # Boş Android anahtarı bu kapının işi değil: iOS paketine dokunmuyor ve
    # build-aab.ps1 onu ayrıca reddediyor.
    ("", "GEÇTİ"),
])
def test_android_anahtari_test_ise_kalir(agac, anahtar, beklenen):
    agac.defines(REVENUECAT_ANDROID_KEY=anahtar)
    s = agac.kos("--kuru")
    satir = _satir(s.stdout, "revenuecat-android-anahtari")
    assert satir.startswith("[" + beklenen + "]"), satir
    if beklenen == "KALDI":
        assert s.returncode == 1
        # Gerekçe ÖLÇÜLENİ söylemeli: iOS paketi bozulmaz (Android anahtarı
        # iOS ikilisine girmiyor), sebep define dosyasının kendisi.
        assert "yayın dosyası değil" in satir and "girmiyor" in satir
        assert anahtar not in s.stdout, "anahtarın kendisi basılmamalı"


def test_plus_yetkisi_bos_kalir(agac):
    agac.defines(RYTHO_PLUS_ENTITLEMENT="  ")
    s = agac.kos("--kuru")
    assert _durum(s.stdout, "plus-yetkisi") == "KALDI"
    assert s.returncode == 1
    # Yalnız boşluktan ibaret değer "boş" sayılır, "baş/son boşluk" DEĞİL:
    # okuyan için doğru söz "yetki kimliği yok".
    assert "RYTHO_PLUS_ENTITLEMENT boş" in _satir(s.stdout, "plus-yetkisi")


def test_define_dosyasi_yoksa_kalir(agac):
    (agac.mobil / "dart_defines.local.json").unlink()
    s = agac.kos("--kuru")
    assert s.returncode == 1
    assert _durum(s.stdout, "define-dosyasi") == "KALDI"
    assert _durum(s.stdout, "revenuecat-ios-anahtari") == "KALDI"


def test_defines_secenegi_baska_dosyayi_okur(agac, tmp_path):
    baska = tmp_path / "baska.json"
    baska.write_text(json.dumps({"REVENUECAT_IOS_KEY": "test_X" * 6,
                                 "APPSTORE_APP_ID": "1",
                                 "RYTHO_PLUS_ENTITLEMENT": YETKI}),
                     encoding="utf-8")
    s = agac.kos("--kuru", "--defines", str(baska))
    assert _durum(s.stdout, "revenuecat-ios-anahtari") == "KALDI"


def test_imza_takimi_yer_tutucuysa_kalir(agac):
    # AASA doğru bırakıldı: kalan sebep YALNIZ pbxproj'deki yer tutucu.
    agac.pbxproj(_pbxproj(takim="TEAMID"))
    s = agac.kos("--kuru")
    assert _durum(s.stdout, "imza-takimi") == "KALDI"
    assert "pbxproj takımı yer tutucu" in _satir(s.stdout, "imza-takimi")


def test_aasa_yer_tutucusu_kalir(agac):
    agac.aasa(_aasa("TEAMID.ai.rytho"))
    s = agac.kos("--kuru")
    assert _durum(s.stdout, "imza-takimi") == "KALDI"
    assert "'TEAMID' yer tutucusu" in _satir(s.stdout, "imza-takimi")


def test_aasa_takimi_imza_takimindan_farkliysa_kalir(agac):
    agac.aasa(_aasa("ABCDE12345.ai.rytho"))
    s = agac.kos("--kuru")
    assert _durum(s.stdout, "imza-takimi") == "KALDI"
    assert "≠ imza takımı" in _satir(s.stdout, "imza-takimi")


def test_pbxproj_takimi_yoksa_ya_da_ikiyse_kalir(agac):
    agac.pbxproj("{\n\t\tPRODUCT_BUNDLE_IDENTIFIER = ai.rytho;\n}\n")
    assert "DEVELOPMENT_TEAM yok" in _satir(agac.kos("--kuru").stdout,
                                            "imza-takimi")
    agac.pbxproj(_pbxproj() + "\t\t\t\tDEVELOPMENT_TEAM = ABCDE12345;\n")
    assert "birden fazla takım" in _satir(agac.kos("--kuru").stdout,
                                          "imza-takimi")


def test_pbxproj_yorumundaki_teamid_kapiyi_dusurmez(agac):
    # Bir şeyin yokluğunu arayan bekçi onu ANLATAN yorumu görmemeli.
    agac.pbxproj(_pbxproj(yorum="\t\t/* eski hâl: TEAMID yer tutucusu */\n"))
    assert _durum(agac.kos("--kuru").stdout, "imza-takimi") == "GEÇTİ"


# CLAUDE.md'den ölçülen kullanılmış Android kodları (2026-10-24): 17 §4'te,
# geri kalanı §6'da. Betik listesi buradan sapmamalı.
@pytest.mark.parametrize("kod", [17, 41, 43, 44, 46, 48, 50, 52, 53])
def test_derleme_numarasi_yanmis_android_kodu_kalir(agac, kod):
    agac.pubspec(f"1.20.0+{kod}")
    s = agac.kos("--kuru")
    assert s.returncode == 1
    assert _durum(s.stdout, "derleme-numarasi") == "KALDI"
    satir = _satir(s.stdout, "derleme-numarasi")
    assert "YANMIŞ" in satir
    # Gerekçe MAĞAZA değil: Apple'ın derleme numarası Play'den bağımsız;
    # engel sunucunun platformsuz aynası (U29). Mesaj bunu söylemezse okuyan
    # "Apple reddeder" sanır.
    assert "Play'den bağımsız" in satir and "U29" in satir


def test_derleme_numarasi_51_bilinmiyor_diye_kalir_yanmis_denmez(agac):
    # CLAUDE.md §6: 51'in Console'a yüklenip yüklenmediği bilinmiyor.
    # Bilinmeyen kod kullanılmış sayılır ama "yanmış" diye BEYAN edilmez.
    agac.pubspec("1.20.0+51")
    satir = _satir(agac.kos("--kuru").stdout, "derleme-numarasi")
    assert satir.startswith("[KALDI]")
    assert "BİLİNMİYOR" in satir and "YANMIŞ" not in satir
    assert "U29" in satir


def test_derleme_numarasi_54_altinda_kalir_gerekce_gizlilik_metni(agac):
    # 49 yanmış listede DEĞİL (CLAUDE.md §6: "49'luk AAB yalnız ölçüm
    # artefaktıydı"), ama tabanın altında.
    agac.pubspec("1.20.0+49")
    satir = _satir(agac.kos("--kuru").stdout, "derleme-numarasi")
    assert satir.startswith("[KALDI]")
    assert "1.20.0+54" in satir and "YANMIŞ" not in satir
    assert "BİLİNMİYOR" not in satir


@pytest.mark.parametrize("surum", ["1.20.0+54", "1.21.0+60", "1.20.0+55 # yorum"])
def test_derleme_numarasi_54_ve_ustu_gecer(agac, surum):
    agac.pubspec(surum)
    assert _durum(agac.kos("--kuru").stdout, "derleme-numarasi") == "GEÇTİ"


@pytest.mark.parametrize("surum", ["1.20.0", "1.20.0+abc", "1.20.0+"])
def test_derleme_numarasi_yoksa_ya_da_sayi_degilse_kalir(agac, surum):
    # Numarasız pubspec'te Flutter numarayı kendisi seçer; kapı onu
    # göremeyeceği için geçirmemeli. Mesaj NEYİN okunamadığını söyler.
    agac.pubspec(surum)
    satir = _satir(agac.kos("--kuru").stdout, "derleme-numarasi")
    assert satir.startswith("[KALDI]")
    assert "derleme numarası okunamadı" in satir


# -------------------------------------------------------------- paket kapıları

_PAKET_KAPILARI = ["paket-test-anahtari-yok", "paket-revenuecat-anahtari",
                   "paket-simulator-taslagi-yok", "paket-mlkit-gercek",
                   "paket-izin-anahtarlari", "paket-gizlilik-manifesti",
                   "paket-derleme-numarasi"]
_IMZA_KAPILARI = ["imza-aps-ortami", "imza-get-task-allow", "imza-yetkileri"]


def test_imzasiz_yesil_paket_imza_kapilari_ATLANDI_asla_GECTI_degil(agac):
    s = agac.kos("--yalniz-denetle", str(agac.app()))
    assert s.returncode == 0, s.stdout + s.stderr
    for kapi in _PAKET_KAPILARI:
        assert _durum(s.stdout, kapi) == "GEÇTİ", kapi
    for kapi in _IMZA_KAPILARI:
        assert _durum(s.stdout, kapi) == "ATLANDI (imzasız)", kapi
    assert "GEÇMİŞ sayılmaz" in s.stdout
    assert not agac.kayit.exists(), "--yalniz-denetle derleme yapmamalı"


def test_adhoc_imza_da_imzasiz_sayilir(agac):
    # Apple Silicon'da bağlayıcı ad-hoc imza koyuyor: ne takım ne yetki.
    s = agac.kos("--yalniz-denetle", str(agac.app()), SAHTE_IMZA="adhoc")
    for kapi in _IMZA_KAPILARI:
        assert _durum(s.stdout, kapi) == "ATLANDI (imzasız)", kapi


def test_paketteki_test_anahtari_kalir(agac):
    app = agac.app(app_ikilisi=b"\x00test_SahteTestStoreAnahtari0000\x00"
                   + IOS_ANAHTAR.encode() + YETKI.encode())
    s = agac.kos("--yalniz-denetle", str(app))
    assert s.returncode == 1
    assert _durum(s.stdout, "paket-test-anahtari-yok") == "KALDI"
    assert "test_SahteTestStore" not in s.stdout, "anahtar basılmamalı"
    # Bayt hangi anahtardan geldiğini söylemiyor: mesaj iki olasılığı
    # adlandırır, tek sebep beyan etmez (Android anahtarı test_ olan
    # pakette "satın alma kapalı çıkar" yanlış gerekçe olurdu).
    satir = _satir(s.stdout, "paket-test-anahtari-yok")
    assert "İki olasılık" in satir
    assert "REVENUECAT_IOS_KEY" in satir and "REVENUECAT_ANDROID_KEY" in satir


def test_define_anahtari_pakette_yoksa_kalir(agac):
    app = agac.app(app_ikilisi=b"\x00appl_BaskaBirAnahtar0000000000\x00"
                   + YETKI.encode())
    s = agac.kos("--yalniz-denetle", str(app))
    assert _durum(s.stdout, "paket-revenuecat-anahtari") == "KALDI"
    assert "anahtarı pakette YOK" in _satir(s.stdout, "paket-revenuecat-anahtari")


def test_yetki_kimligi_pakette_yoksa_kalir(agac):
    app = agac.app(app_ikilisi=b"\x00" + IOS_ANAHTAR.encode() + b"\x00")
    s = agac.kos("--yalniz-denetle", str(app))
    assert _durum(s.stdout, "paket-revenuecat-anahtari") == "KALDI"
    assert "Yetki kimliği" in _satir(s.stdout, "paket-revenuecat-anahtari")


def test_define_dosyasi_yoksa_anahtar_kapisi_ATLANDI(agac):
    (agac.mobil / "dart_defines.local.json").unlink()
    s = agac.kos("--yalniz-denetle", str(agac.app()))
    assert _durum(s.stdout, "paket-revenuecat-anahtari").startswith("ATLANDI")


def test_simulator_taslagi_dizesi_kalir(agac):
    app = agac.app(ek_dosya=("Frameworks/google_mlkit_commons.framework/"
                             "google_mlkit_commons", b"..SIMULATORDE_YOK.."))
    s = agac.kos("--yalniz-denetle", str(app))
    assert _durum(s.stdout, "paket-simulator-taslagi-yok") == "KALDI"
    assert "google_mlkit_commons" in _satir(s.stdout, "paket-simulator-taslagi-yok")


def test_simulator_paketi_kalir(agac):
    app = agac.app(info={"CFBundleSupportedPlatforms": ["iPhoneSimulator"]})
    s = agac.kos("--yalniz-denetle", str(app))
    assert _durum(s.stdout, "paket-simulator-taslagi-yok") == "KALDI"


def test_gercek_mlkit_yoksa_kalir(agac):
    app = agac.app(runner_ikilisi=b"\xcf\xfa\xed\xfe yalniz taslak \x00")
    s = agac.kos("--yalniz-denetle", str(app))
    assert _durum(s.stdout, "paket-mlkit-gercek") == "KALDI"


def test_okunamayan_paket_bos_mesajla_kalmaz(agac):
    # Info.plist yoksa kapı KALDI der ve NEYİN okunamadığını yazar; boş
    # mesajlı kırmızı, sebebi aratır.
    app = agac.app()
    (app / "Info.plist").unlink()
    satir = _satir(agac.kos("--yalniz-denetle", str(app)).stdout,
                   "paket-izin-anahtarlari")
    assert satir.startswith("[KALDI]") and "Info.plist" in satir


def test_izin_kumesi_fazlasi_kalir(agac):
    app = agac.app(izinler=IZINLER + ["NSUserTrackingUsageDescription"])
    satir = _satir(agac.kos("--yalniz-denetle", str(app)).stdout,
                   "paket-izin-anahtarlari")
    assert satir.startswith("[KALDI]") and "NSUserTracking" in satir


@pytest.mark.parametrize("anahtar", [
    # NS öneki taşımayan gizlilik anahtarı (NFC eklentisi getirir).
    "NFCReaderUsageDescription",
    # Sözlük sonekli gizlilik anahtarı (konum eklentisi getirir).
    "NSLocationTemporaryUsageDescriptionDictionary",
])
def test_izin_kumesi_NS_oneksiz_ve_sozluk_anahtari_da_fazla_sayilir(agac, anahtar):
    # Eski kalıp "NS…UsageDescription" ikisini de görmüyordu ve kapı
    # "küme aynı" deyip GEÇİRİYORDU (çürütme turu, 2026-10-24).
    app = agac.app(izinler=IZINLER + [anahtar])
    s = agac.kos("--yalniz-denetle", str(app))
    satir = _satir(s.stdout, "paket-izin-anahtarlari")
    assert satir.startswith("[KALDI]") and "BEKLENMEYEN: " + anahtar in satir
    assert s.returncode == 1


def test_izin_kumesi_eksigi_kalir_mikrofon_bilerek_beklenir(agac):
    # U03: anahtarsız paket ITMS-90683 ile geri çevrilir.
    app = agac.app(izinler=[k for k in IZINLER if "Microphone" not in k])
    satir = _satir(agac.kos("--yalniz-denetle", str(app)).stdout,
                   "paket-izin-anahtarlari")
    assert satir.startswith("[KALDI]") and "EKSİK: NSMicrophone" in satir


def test_gizlilik_manifesti_yoksa_ya_da_bozuksa_kalir(agac):
    s = agac.kos("--yalniz-denetle", str(agac.app("A.app", manifest=None)))
    assert "PrivacyInfo.xcprivacy pakette yok" in _satir(
        s.stdout, "paket-gizlilik-manifesti")
    s = agac.kos("--yalniz-denetle", str(agac.app("B.app", manifest=b"<bozuk")))
    assert "okunamadı" in _satir(s.stdout, "paket-gizlilik-manifesti")


def test_paket_derleme_numarasi_kalir(agac):
    app = agac.app(info={"CFBundleVersion": "53"})
    s = agac.kos("--yalniz-denetle", str(app))
    assert _durum(s.stdout, "paket-derleme-numarasi") == "KALDI"


def test_ipa_da_denetlenir(agac):
    ipa = agac.ipa(agac.app(info={"CFBundleVersion": "53"}))
    s = agac.kos("--yalniz-denetle", str(ipa))
    assert _durum(s.stdout, "paket-izin-anahtarlari") == "GEÇTİ"
    assert _durum(s.stdout, "paket-derleme-numarasi") == "KALDI"


def test_yalniz_denetle_imzasiz_IPA_KALIR_cikis_1(agac):
    # .ipa yalnız yüklemek için üretilen biçim: imzasızı ATLANDI ile çıkış
    # 0'a bırakmak onu otomasyonda yeşil gösterirdi (çürütme turu,
    # 2026-10-24). Paket kapılarının hepsi yeşil — kalan sebep YALNIZ imza.
    s = agac.kos("--yalniz-denetle", str(agac.ipa(agac.app())))
    assert s.returncode == 1, s.stdout
    for kapi in _PAKET_KAPILARI:
        assert _durum(s.stdout, kapi) == "GEÇTİ", kapi
    for kapi in _IMZA_KAPILARI:
        assert _durum(s.stdout, kapi) == "KALDI", kapi
    # Ad-hoc imza da imzasız sayılır; IPA'da o da KALDI.
    s = agac.kos("--yalniz-denetle", str(agac.ipa(agac.app("B.app"))),
                 SAHTE_IMZA="adhoc")
    assert s.returncode == 1
    assert _durum(s.stdout, "imza-aps-ortami") == "KALDI"


def test_yalniz_denetle_imzali_IPA_gecer(agac):
    s = agac.kos("--yalniz-denetle", str(agac.ipa(agac.app())),
                 SAHTE_IMZA=str(agac.yetkiler()))
    assert s.returncode == 0, s.stdout
    for kapi in _PAKET_KAPILARI + _IMZA_KAPILARI:
        assert _durum(s.stdout, kapi) == "GEÇTİ", kapi


# --------------------------------------------------------------- imza kapıları

def test_imzali_iyi_paket_uc_imza_kapisi_gecer(agac):
    s = agac.kos("--yalniz-denetle", str(agac.app()),
                 SAHTE_IMZA=str(agac.yetkiler()))
    assert s.returncode == 0, s.stdout
    for kapi in _IMZA_KAPILARI:
        assert _durum(s.stdout, kapi) == "GEÇTİ", kapi


@pytest.mark.parametrize("degisen, kalan_kapi", [
    ({"aps__environment": "development"}, "imza-aps-ortami"),
    ({"get__task__allow": True}, "imza-get-task-allow"),
    ({"com_apple_developer_devicecheck_appattest__environment": None},
     "imza-yetkileri"),
    ({"com_apple_developer_applesignin": None}, "imza-yetkileri"),
])
def test_imza_kusuru_kendi_kapisinda_kalir(agac, degisen, kalan_kapi):
    s = agac.kos("--yalniz-denetle", str(agac.app()),
                 SAHTE_IMZA=str(agac.yetkiler(**degisen)))
    assert s.returncode == 1
    assert _durum(s.stdout, kalan_kapi) == "KALDI"


def test_get_task_allow_false_gecer(agac):
    s = agac.kos("--yalniz-denetle", str(agac.app()),
                 SAHTE_IMZA=str(agac.yetkiler(get__task__allow=False)))
    assert _durum(s.stdout, "imza-get-task-allow") == "GEÇTİ"


# ------------------------------------------------------------------ tam kip

def test_tam_kip_dogru_komutla_derler_ve_IPA_icini_denetler(agac):
    ipa = agac.ipa(agac.app())
    s = agac.kos(SAHTE_IPA=str(ipa), SAHTE_IMZA=str(agac.yetkiler()))
    assert s.returncode == 0, s.stdout + s.stderr
    cagri = agac.kayit.read_text(encoding="utf-8").strip().splitlines()
    defines = agac.mobil / "dart_defines.local.json"
    assert cagri == [f"{agac.mobil}|build ipa --release "
                     f"--dart-define-from-file={defines}"]
    for kapi in _PAKET_KAPILARI + _IMZA_KAPILARI:
        assert _durum(s.stdout, kapi) == "GEÇTİ", kapi
    assert "yükleme ELLE" in s.stdout


def test_tam_kip_on_kapi_kalirsa_derleme_baslamaz(agac):
    agac.defines(REVENUECAT_IOS_KEY="test_SahteTestStoreAnahtari0000")
    s = agac.kos(SAHTE_IPA=str(agac.ipa(agac.app())))
    assert s.returncode == 1
    assert "derleme BAŞLATILMADI" in s.stdout
    assert not agac.kayit.exists()


def test_tam_kipte_imzasiz_IPA_ATLANMAZ_KALIR(agac):
    s = agac.kos(SAHTE_IPA=str(agac.ipa(agac.app())))
    assert s.returncode == 1
    for kapi in _IMZA_KAPILARI:
        assert _durum(s.stdout, kapi) == "KALDI", kapi


def test_tam_kip_bayat_IPA_olcmez(agac):
    # Önceki derlemenin IPA'sı klasörde dururken dışa aktarma IPA üretmezse
    # kapılar o bayat paketi ölçüp "geçti" dememeli.
    bayat = agac.mobil / "build" / "ios" / "ipa" / "Rytho.ipa"
    bayat.parent.mkdir(parents=True)
    shutil.copy2(agac.ipa(agac.app()), bayat)
    s = agac.kos(SAHTE_IMZA=str(agac.yetkiler()))
    assert s.returncode == 1
    assert "IPA üretilmedi" in s.stdout


def test_tam_kip_flutter_dusunce_durur(agac):
    s = agac.kos(SAHTE_FLUTTER_KODU="1")
    assert s.returncode == 1
    assert "flutter build ipa başarısız" in s.stdout


def test_depodaki_betik_calistirilabilir():
    assert os.access(_BETIK, os.X_OK), "infra/build-ipa.sh çalıştırılabilir değil"

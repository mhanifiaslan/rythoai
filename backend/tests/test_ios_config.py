r"""iOS yapılandırma sözleşmesi — hepsi SESSİZ bozulan şeyler.

Bu dosyadaki her iddia 2026-09-26'da ölçülmüş gerçek bir kusurdan doğdu.
Ortak yanları: bozulduklarında derleme BAŞARILI olur, test yeşil kalır,
kusur ancak cihazda ya da mağazada görülür.

Asıl tetikleyici: Firebase'de iOS uygulaması bir kez `app.rytho` diye
kaydedildi (`ai` yerine `app` — tek harf). İnen GoogleService-Info.plist
`BUNDLE_ID = app.rytho` taşıyordu ve `FirebaseApp.configure()` bu
uyuşmazlığı HATA ile değil yalnız bir UYARI ile geçiyor. Sonuç: uygulama
"çalışıyor" görünürken App Check (App Attest kimliği tutmaz), Google ile
giriş (geri dönüş şeması tutmaz), push (APNs bundle'a bağlı) ve
Crashlytics/Analytics (var olmayan uygulamaya rapor) tek tek sessizce
bozuluyordu.

Çalıştırma:
    .venv\Scripts\python.exe -m pytest tests/test_ios_config.py -q
"""
from __future__ import annotations

import os
import pathlib
import plistlib
import re
import shutil
import subprocess

import pytest

_KOK = pathlib.Path(__file__).resolve().parents[2]
_IOS = _KOK / "apps" / "mobile" / "ios"
_RUNNER = _IOS / "Runner"

#: Ürünün tek gerçek kimliği. Değiştirilecekse AYNI anda beş yerde
#: değişmeli; bu testin varlık sebebi tam olarak o beşi bağlamak.
KIMLIK = "ai.rytho"


def _plist(yol: pathlib.Path) -> dict:
    return plistlib.loads(yol.read_bytes())


def _pbxproj() -> str:
    return (_IOS / "Runner.xcodeproj" / "project.pbxproj").read_text(
        encoding="utf-8")


def test_bundle_kimligi_bes_yerde_de_ayni():
    """Beşinden biri kayarsa ürün sessizce yanlış uygulamaya bağlanır."""
    pbx = _pbxproj()
    # RunnerTests kendi kimliğini taşır (ai.rytho.RunnerTests); yalnız
    # uygulama hedefinin satırları sayılır.
    hedefler = [s for s in re.findall(
        r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", pbx)
        if not s.endswith(".RunnerTests")]
    assert hedefler, "pbxproj'de uygulama hedefi bulunamadı"
    assert set(hedefler) == {KIMLIK}, f"pbxproj: {set(hedefler)}"

    gradle = (_KOK / "apps" / "mobile" / "android" / "app"
              / "build.gradle.kts")
    if not gradle.exists():
        gradle = gradle.with_suffix("")  # build.gradle
    assert f'applicationId = "{KIMLIK}"' in gradle.read_text(encoding="utf-8") \
        or f'applicationId "{KIMLIK}"' in gradle.read_text(encoding="utf-8"), \
        "Android applicationId tutmuyor"

    aasa = (_KOK / "web" / ".well-known"
            / "apple-app-site-association").read_text(encoding="utf-8")
    assert f'.{KIMLIK}"' in aasa, (
        "apple-app-site-association'daki appID bundle ile bitmiyor — "
        "evrensel bağlantılar sessizce çalışmaz")

    g = _plist(_RUNNER / "GoogleService-Info.plist")
    assert g["BUNDLE_ID"] == KIMLIK, (
        f"GoogleService-Info.plist BUNDLE_ID = {g['BUNDLE_ID']!r}. "
        "Firebase'de kayıt yanlış bundle ile açılmış; kaydı SİLİP yeniden "
        "oluştur — Firebase bundle kimliğini düzenlettirmiyor.")
    assert g["PROJECT_ID"] == "rhytoai"


def test_google_girisi_info_pliste_bagli():
    """Geri dönüş şeması YALNIZ Info.plist'ten okunur; Dart'tan verilemez.

    Kayıtlı değilse Google tarayıcıda oturumu açar ama uygulamaya
    dönemez — giriş yarıda kalır ve hiçbir hata görünmez.
    """
    g = _plist(_RUNNER / "GoogleService-Info.plist")
    info = _plist(_RUNNER / "Info.plist")

    semalar = [s for t in info.get("CFBundleURLTypes", [])
               for s in t.get("CFBundleURLSchemes", [])]
    assert g["REVERSED_CLIENT_ID"] in semalar, (
        "REVERSED_CLIENT_ID Info.plist'teki URL şemaları arasında yok")
    assert info.get("GIDClientID") == g["CLIENT_ID"], (
        "GIDClientID, GoogleService-Info.plist'teki CLIENT_ID ile aynı olmalı")


def test_push_ortami_yapilandirmaya_gore_ayrilmis():
    """Debug/Profile `development`, Release `production` ve iki dosya
    aps-environment DIŞINDA aynı.

    Asıl koruma ikinci yarı: Release ayrı dosyaya baktığı için oraya
    düşmeyen bir yetki yalnız yayın paketinden eksik kalır ve Debug'da
    hiçbir şey görünmez.

    ⚠️ Ayrımın eski gerekçesi YANLIŞTI ("tek dosyada `development` kalsa
    üretim paketi sandbox jetonu alır, sunucu üretim APNs'ine gönderir:
    TestFlight'ta çalışır, mağazada ölür"). Apple'a göre imzadaki değeri
    provizyon profili belirler ve dağıtım profili (TestFlight + App Store)
    production yazar; FCM de ortamı gömülü profilden okuyup jetonla
    bildirir. TestFlight ile mağaza aynı ortamda. Ayrı Release dosyasının
    gerekip gerekmediği ölçülmedi — ilk imzalı Release'te bakılır
    (docs/mac-devir.md B9); ölçüm "gerekmiyor" derse ayrım ve bu iki
    değer iddiası birlikte değişir."""
    dev = _plist(_RUNNER / "Runner.entitlements")
    yayin = _plist(_RUNNER / "RunnerRelease.entitlements")
    assert dev["aps-environment"] == "development"
    assert yayin["aps-environment"] == "production"

    # İkisi aps-environment DIŞINDA birebir aynı kalmalı; ayrılırsa üretim
    # paketi Apple ile Giriş, Universal Links ya da App Attest yetkisi
    # olmadan çıkar.
    a = {k: v for k, v in dev.items() if k != "aps-environment"}
    b = {k: v for k, v in yayin.items() if k != "aps-environment"}
    assert a == b, "iki entitlements dosyası aps-environment dışında ayrışmış"

    pbx = _pbxproj()
    assert "CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease.entitlements;" in pbx, (
        "Release yapılandırması üretim entitlements dosyasına bakmıyor")

    # remote-notification arka plan kipi görünür bildirim için DEĞİL
    # (Apple: uyarısız arka plan bildirimi içindir; uzak bildirimin
    # paketteki şartı yukarıdaki aps-environment). Firebase'in iOS telefon
    # doğrulaması sessiz push yolunu kullandığı ve Flutter kurulum belgesi
    # istediği için duruyor (gerekçe Info.plist'teki yorumda). Kaybı
    # SESSİZDİR: görünür push gelmeye devam eder, yalnız telefon
    # doğrulaması reCAPTCHA'ya düşer (Firebase belgesi; cihazda ölçülmedi).
    info = _plist(_RUNNER / "Info.plist")
    assert "remote-notification" in info.get("UIBackgroundModes", [])


def test_podfile_ve_deployment_target_ayni_tabani_soyluyor():
    """Podfile'daki `platform` satırı ile pbxproj ayrışırsa CocoaPods
    çözümlemesi "not compatible" ile düşer — ve Flutter'ın ürettiği
    şablonda o satır YORUMLU geldiği için sorun kendiliğinden çözülmez."""
    podfile = (_IOS / "Podfile").read_text(encoding="utf-8")
    m = re.search(r"^platform :ios, '([\d.]+)'", podfile, re.M)
    assert m, "Podfile'da açık bir `platform :ios` satırı yok"
    taban = m.group(1)

    hedefler = set(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);",
                              _pbxproj()))
    assert hedefler == {taban}, (
        f"Podfile {taban} diyor, pbxproj {hedefler}")


def test_ihracat_beyani_ve_strip_ayari_duruyor():
    """İkisi de 'yokluğu sessiz' ayarlar: biri her TestFlight yüklemesinde
    ihracat sorusunu yeniden sordurur, diğeri arşivde sembolleri soydurup
    `flutter build ipa` sonrası çalışma anında patlatır."""
    info = _plist(_RUNNER / "Info.plist")
    assert info.get("ITSAppUsesNonExemptEncryption") is False
    assert 'STRIP_STYLE = "non-global";' in _pbxproj()


def test_aasa_takim_kimligi_imza_takimiyla_ayni():
    """Evrensel bağlantının kimliği İKİ parçadan oluşur: Team ID + bundle.
    `apple-app-site-association`daki appID, uygulamayı imzalayan takımla
    (pbxproj `DEVELOPMENT_TEAM`) birebir eşleşmezse iOS bağlantıyı
    uygulamaya DEVRETMEZ — davet linki sessizce Safari'de açılır, derleme
    ve testler yeşil kalır. Dosya uzun süre `TEAMID` yer tutucusuyla durdu
    (2026-09-27'de gerçek değer yazıldı). Ayrıca Team ID ile kayıt
    e-postasındaki Enrollment ID aynı biçimde (10 karakter) — yanlışı
    yazılırsa ikisi yine de "geçerli görünür"; bu test ikisini birbirine
    bağlar, doğru olanı sahip Membership details'ten doğruladı."""
    import json

    takimlar = set(re.findall(r"DEVELOPMENT_TEAM = ([A-Z0-9]+);",
                              _pbxproj()))
    assert len(takimlar) == 1, (
        f"pbxproj'de tek bir imza takımı bekleniyordu: {takimlar or 'yok'}")
    takim = takimlar.pop()
    assert re.fullmatch(r"[A-Z0-9]{10}", takim), takim

    aasa = json.loads((_KOK / "web" / ".well-known"
                       / "apple-app-site-association").read_text(
                           encoding="utf-8"))
    kimlikler = {d["appID"] for d in aasa["applinks"]["details"]}
    assert kimlikler == {f"{takim}.{KIMLIK}"}, (
        f"AASA appID {kimlikler}, imza takımı {takim} — evrensel bağlantı "
        "uygulamayı açmaz")


def test_aasa_android_app_links_yollarini_kapsiyor():
    """İki platform aynı bağlantıyı uygulamaya devretmeli (mac-devir 4.10).

    Ölçüldü (2026-10-22): AndroidManifest App Links'te `/i/` VE `/r/`
    dinliyordu, AASA yalnız `/i/*` taşıyordu. Ortak bağlantısı Android'de
    uygulamayı açıp kodu sayarken iPhone'da tarayıcıya düşüyordu ve hiçbir
    test kırmızı değildi — iki dosya ayrı ekiplerin elinde ayrı zamanlarda
    değişiyor. Yön: Android'in dinlediği her yol öneki AASA'da `önek*`
    olarak bulunmalı. AASA tek dosya ve iki host'tan birden sunuluyor;
    Android'de host başına filtre var, bu yüzden kıyas YOL kümesinde.

    Manifest yorumları eşleşmeden ÖNCE atılır: bekçi bir yolu ANLATAN
    yorumu görüp geçmemeli (CLAUDE.md §5).
    """
    import json

    manifest = (_KOK / "apps" / "mobile" / "android" / "app" / "src"
                / "main" / "AndroidManifest.xml").read_text(encoding="utf-8")
    manifest = re.sub(r"<!--.*?-->", "", manifest, flags=re.S)
    onekler = set(re.findall(r'android:pathPrefix="([^"]+)"', manifest))
    assert onekler, "AndroidManifest'te App Links yol öneki bulunamadı"

    aasa = json.loads((_KOK / "web" / ".well-known"
                       / "apple-app-site-association").read_text(
                           encoding="utf-8"))
    yollar = {y for d in aasa["applinks"]["details"]
              for y in d.get("paths", [])}
    eksik = sorted(o for o in onekler if f"{o.rstrip('/')}/*" not in yollar)
    assert not eksik, (
        f"Android bu yolları uygulamaya devrediyor ama AASA devretmiyor: "
        f"{eksik} — iPhone'da bu bağlantılar tarayıcıya düşer")


def _crashlytics_betigi() -> str:
    """pbxproj'deki 'Crashlytics dSYM yukle' fazının ÇÖZÜLMÜŞ kabuk betiği.

    pbxproj bir OpenStep plist'i: `shellScript` tırnaklı bir dize ve içinde
    `\\n`, `\\"` kaçışları var. Çözücü Windows'ta da çalışsın diye elle
    yazıldı (`plutil` yalnız macOS'ta).
    """
    m = re.search(r"/\* Crashlytics dSYM yukle \*/ = \{(.*?)\n\t\t\};",
                  _pbxproj(), re.S)
    assert m, "pbxproj'de 'Crashlytics dSYM yukle' fazı yok"
    s = re.search(r'shellScript = "((?:[^"\\]|\\.)*)";', m.group(1))
    assert s, "Crashlytics fazında shellScript yok"
    return re.sub(r"\\(.)",
                  lambda k: {"n": "\n", "t": "\t"}.get(k.group(1), k.group(1)),
                  s.group(1))


def test_crashlytics_fazi_imzasiz_derlemede_atlamayi_run_dan_once_yapar():
    """İmzasız ölçüm derlemesi (`flutter build ios --no-codesign` →
    xcodebuild'e `CODE_SIGNING_ALLOWED=NO`) sembol YÜKLEMEMELİ.

    Ölçüldü (2026-10-23): faz Debug dışındaki HER derlemede koşuyordu ve
    imzasız Release ölçüm derlemesinde `upload-symbols` çalışıp "Symbol
    uploading will proceed in the background" dedi — cihaza hiç
    kurulamayacak bir paketin sembolleri üretim projesine yola çıktı
    (sunucuya ulaştığı ölçülemedi). CLAUDE.md §5 "testler üretime
    yazabiliyordu" ile aynı sınıf: dış dünyaya çıkan her yazımın bir
    kapısı olmalı. Onarımdan sonra ölçüldü (2026-10-24, imzasız Release,
    xcactivitylog): faz "yukleme ATLANDI" yazdı, `upload-symbols` 0 kez.

    Bu yapısal yarı (her işletim sisteminde koşar): atlama satırı `run`
    çağrısından ÖNCE ve `exit 0` ile. Yorum satırları önce atılır — atlamayı
    ANLATAN yorum atlamanın kendisi sayılmasın (CLAUDE.md §5).
    """
    satirlar = [s.strip() for s in _crashlytics_betigi().splitlines()
                if s.strip() and not s.strip().startswith("#")]
    kapi = 'if [ "${CODE_SIGNING_ALLOWED}" = "NO" ]; then'
    run = '"${PODS_ROOT}/FirebaseCrashlytics/run"'
    assert kapi in satirlar, "imzasız derlemede atlama yok"
    assert run in satirlar, "Crashlytics run çağrısı fazdan düşmüş"
    i = satirlar.index(kapi)
    assert i < satirlar.index(run), "atlama run çağrısından SONRA"
    blok = satirlar[i + 1:satirlar.index("fi", i)]
    assert "exit 0" in blok, f"atlama bloğu çıkmıyor: {blok}"


@pytest.mark.skipif(os.name == "nt" or shutil.which("sh") is None,
                    reason="fazın betiği POSIX sh ile koşturuluyor")
@pytest.mark.parametrize("yapilandirma, imza, yuklenir", [
    # Ölçüm derlemesi: imzasız Release — YÜKLEMEZ.
    ("Release", "NO", False),
    ("Profile", "NO", False),
    # Yayın yolu (`flutter build ipa`, Xcode arşivi): imza açık — YÜKLER.
    # Bu satır aşırı geniş bir atlamaya karşı: dSYM olmadan TestFlight ve
    # mağaza çökmeleri okunamaz adres olarak kalır.
    ("Release", "YES", True),
    ("Release", None, True),
    # Debug'da dSYM yok (eski kural, değişmedi).
    ("Debug", "YES", False),
])
def test_crashlytics_fazi_davranisi(tmp_path, yapilandirma, imza, yuklenir):
    """Fazın gerçek betiği sahte bir PODS_ROOT ile koşturulur; `run`
    çağrılırsa iz bırakır. Ağ yok, Crashlytics yok."""
    betik = tmp_path / "faz.sh"
    betik.write_text(_crashlytics_betigi(), encoding="utf-8")
    run = tmp_path / "Pods" / "FirebaseCrashlytics" / "run"
    run.parent.mkdir(parents=True)
    iz = tmp_path / "run-cagrildi"
    run.write_text(f'#!/bin/sh\ntouch "{iz}"\n', encoding="utf-8")
    run.chmod(0o755)
    ortam = {"PATH": os.environ.get("PATH", ""),
             "CONFIGURATION": yapilandirma,
             "PODS_ROOT": str(tmp_path / "Pods")}
    if imza is not None:
        ortam["CODE_SIGNING_ALLOWED"] = imza
    s = subprocess.run(["sh", str(betik)], env=ortam, capture_output=True,
                       text=True, timeout=30)
    assert s.returncode == 0, s.stdout + s.stderr
    assert iz.exists() is yuklenir, (
        f"{yapilandirma}/CODE_SIGNING_ALLOWED={imza}: run "
        f"{'çağrılmadı' if yuklenir else 'ÇAĞRILDI'}\n{s.stdout}")

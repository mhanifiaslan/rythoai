#!/usr/bin/env bash
# RythoAI iOS yayın paketi (IPA) — infra/build-aab.ps1'in iOS aynası.
#
# Kullanım (depo kökünden):
#   infra/build-ipa.sh                         ön kapılar → flutter build ipa → paket kapıları
#   infra/build-ipa.sh --kuru                  yalnız ön kapılar; derleme YOK
#   infra/build-ipa.sh --yalniz-denetle <yol>  yalnız paket kapıları; <yol> bir .app ya da .ipa
#                                              (.ipa'da imza ZORUNLU, .app'te imzasızsa ATLANDI)
#   --defines <dosya>                          varsayılan apps/mobile/dart_defines.local.json
#
# Çıkış: 0 = kalan kapı yok, 1 = en az bir kapı KALDI, 2 = kullanım hatası.
# Betik HİÇBİR ŞEYİ YÜKLEMEZ; App Store Connect'e gönderim elle yapılır
# (Xcode Organizer ya da Transporter).
#
# ## Neden bu betik var
#
# Android'de 1.5.0+17 düz `flutter build appbundle` ile çıktı: derleme
# başarılı, testler yeşil, imza doğru — RevenueCat anahtarı pakette yoktu ve
# kusur ancak mağaza ekranında görüldü. iOS'ta aynı sınıfın daha sert bir
# hâli var: hazırlık denetimi (2026-10-23) `dart_defines.local.json`da
# `test_` önekli iOS anahtarı ölçtü ve RevenueCat 5.67.1 yayın derlemesinde
# Test Store anahtarını görünce BİLEREK çöküyor (`Configuration.swift:471-495`,
# `#if !DEBUG`). `flutter build ios --release` o anahtarla hiçbir engele
# takılmadan "başarılı" çıktı (aynı denetim). Uygulama artık
# o anahtarla `configure` etmiyor (lib/core/subscription.dart
# `rcEtkinAnahtar`) — yani çökme yerine satın alma SESSİZCE kapalı çıkar;
# sessizliği burada durduruyoruz.
#
# Kapı türleri:
#   ÖN KAPILAR (derlemeden önce, kaynaktan): Xcode sürümü, define dosyası
#     içeriği, imza takımı ↔ AASA, derleme numarası.
#   PAKET KAPILARI (derlemeden sonra, ARTEFAKTTAN): "define'ı geçtim" demek
#     yetmez, pakette OLDUĞU ölçülür (build-aab.ps1 ile aynı ders).
#   İMZA KAPILARI: yalnız imzalı pakette anlamlı. İmzasız .app'te
#     "ATLANDI (imzasız)" yazar, ASLA "GEÇTİ" demez — imzasız bir paket
#     mağazaya gidecek paket değildir. IPA'da (tam kip VE --yalniz-denetle
#     <.ipa>) imza ZORUNLU, imzasızsa KALDI: .ipa yalnız yüklemek için
#     üretilen biçim; otomasyonda bu kipi kullanan biri imzasız IPA'yı
#     çıkış 0 ile yeşil görürdü (çürütme turu, 2026-10-24).
#
# macOS'ta pwsh yok, bu yüzden bash. /bin/bash 3.2'ye uyumlu yazıldı
# (ilişkisel dizi, mapfile, ${x,,} yok). Ayrıştırma işi gömülü python3'te
# (/usr/bin/python3 3.9) — plistlib ikili Info.plist'i de okuyor, JSON ve
# bayt taraması bash'te kırılgan olurdu. Gömülü Python'da ters bölü YOK:
# düzenli ifadeler [0-9] / [ ] ile yazıldı (CLAUDE.md §5, ters bölü tuzağı).
set -uo pipefail
export PYTHONIOENCODING=utf-8

BETIK_DIZINI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOK="$(dirname "$BETIK_DIZINI")"
MOBIL="$KOK/apps/mobile"
PBXPROJ="$MOBIL/ios/Runner.xcodeproj/project.pbxproj"
AASA="$KOK/web/.well-known/apple-app-site-association"
PUBSPEC="$MOBIL/pubspec.yaml"
DEFINES="$MOBIL/dart_defines.local.json"

# Ürün kimliği — backend/tests/test_ios_config.py beş yerde bağlıyor.
export RYTHO_KIMLIK="ai.rytho"

# Derleme numarası kapısının gerekçesi MAĞAZA DEĞİL. App Store Connect'in
# derleme numaraları Play'in sürüm kodlarından bağımsızdır; Android'in
# yaktığı bir sayıyı Apple reddetmez. Kapıyı iki şey kuruyor:
#  1. Sunucunun `users/{uid}.appBuild` aynası ve `minBuild` eşiği platform
#     AYIRMIYOR (backend/core/app_gate.py `remember_build`,
#     `current_min_build`; docs/ios-uyum-denetimi.md U29). Aynı sayı iki
#     platformda farklı içerikli iki paketi gösterir ve eşik ikisini birden
#     açar ya da kapatır: Android 53'te AI onay kutusu yok, HEAD'den derlenen
#     iOS paketinde var.
#  2. Gizlilik metni (aşağıda, taban) kutuyu 1.20.0+54'e bağlıyor.
#
# Android'de KULLANILMIŞ kodlar — CLAUDE.md'den ölçüldü (2026-10-24): 17
# (§4, mağazaya çıktı), 41 (§6 dahili test, AD_ID'li), 43 (§6 App Check'in
# geldiği sürüm; testçilere "yeniden kursunlar" kararı ona dayanıyor), 44
# (§6 AD_ID izni kaldırılan, kapalı test), 46 (§6 kapalı test), 48 (§6
# kapalı test), 50 (§6 iki kanal), 52 (§6 üç kanal), 53 (§6 canlı). Liste TAM
# DEĞİL: 41'in altını ve 42/45/47'yi CLAUDE.md kaydetmiyor. Tabanın altında
# kaldıkları için hepsi zaten kapıda kalır; liste yalnız MESAJI keskinleştirir.
# Asıl işini TABANIN ÜSTÜNDE görür: Android 54 ve sonrasını yaktıkça buraya
# eklenmeli, yoksa iOS aynı sayıyı farklı içerikle alır.
export RYTHO_YANMIS_KODLAR="17 41 43 44 46 48 50 52 53"
# Kullanılıp kullanılmadığı BİLİNMEYEN kodlar: 51 (CLAUDE.md §6: "51'in
# Console'a yüklenip yüklenmediği bilinmiyordu", sıra bu yüzden 52'ye
# çekildi). Bilinmeyen kod kullanılmış sayılır ama mesaj onu "yanmış" diye
# beyan etmez — ölçülmeyen söylenmez.
export RYTHO_BELIRSIZ_KODLAR="51"
# Taban 54 bugünkü gizlilik metninin gereği: web/legal/gizlilik.html:224 ve
# lib/features/profile/legal_texts.dart:282 "Bu ayrı kutu 1.20.0+54
# sürümüyle eklendi" diyor. Kutuyu taşıyan bir iOS paketi 54'ün altında
# numaralanırsa o cümle bu paket için yanlış olur. Bu bir ALT SINIR, başlangıç
# kararı değil: iOS'un ilk paketinin hangi sayıyı alacağı sahip kararı ve
# henüz verilmedi (öneri: Android 54 ile AYNI commit'ten çıkmayacaksa iOS,
# Android'in o gün kullanacağı koddan farklı bir sayı almalı — madde 1).
export RYTHO_EN_DUSUK_KOD=54

# Pakette BEKLENEN izin metinleri — küme EŞİTLİĞİYLE denetlenir: fazlası
# (yeni bir eklentinin getirdiği izin, NSUserTracking) da eksiği de kapıda
# kalır. NSMicrophoneUsageDescription BİLEREK listede: Rytho mikrofonu
# kullanmıyor ama camera_avfoundation ikilisi ses API'lerine başvuruyor ve
# App Store Connect anahtarsız paketi ITMS-90683 ile geri çeviriyor
# (docs/ios-uyum-denetimi.md U03; ölçüldü 2026-10-23: Release paketinde
# `Frameworks/camera_avfoundation.framework` `setEnableAudio:` taşıyor).
# Android'deki RECORD_AUDIO sökümünün iOS karşılığı YOK.
export RYTHO_BEKLENEN_IZINLER="NSCameraUsageDescription NSContactsUsageDescription NSMicrophoneUsageDescription NSPhotoLibraryAddUsageDescription NSPhotoLibraryUsageDescription"

KIP="tam"
HEDEF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --kuru) KIP="kuru"; shift ;;
    --yalniz-denetle)
      KIP="denetle"
      if [ $# -lt 2 ]; then
        echo "--yalniz-denetle bir .app ya da .ipa yolu ister." >&2; exit 2
      fi
      HEDEF="$2"; shift 2 ;;
    --defines)
      if [ $# -lt 2 ]; then echo "--defines bir dosya yolu ister." >&2; exit 2; fi
      DEFINES="$2"; shift 2 ;;
    -h|--yardim|--help)
      sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Bilinmeyen argüman: $1 (yardım: --yardim)" >&2; exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 bulunamadı; kapılar onunla ayrıştırılıyor. Xcode komut satırı araçlarını kur: xcode-select --install" >&2
  exit 2
fi

# Göreli define yolu mutlaklaştırılır: derleme apps/mobile içinden koşuyor
# ve göreli yol orada başka bir dosyayı gösterirdi.
case "$DEFINES" in
  /*) ;;
  *) DEFINES="$(pwd)/$DEFINES" ;;
esac

KALAN=0
ATLANAN=0
# Satır başı hep '[' — echo bir seçenek sanmaz; dosyada ters bölü kalmasın.
gecti()   { echo "[GEÇTİ] $1: $2"; }
kaldi()   { echo "[KALDI] $1: $2"; KALAN=$((KALAN + 1)); }
atlandi() { echo "[ATLANDI ($2)] $1"; ATLANAN=$((ATLANAN + 1)); }

# Bir denetimi koşturur: çıkış 0 → GEÇTİ, 1 → KALDI. Mesaj her iki hâlde
# denetçinin tek satırı.
kapi() {
  local ad="$1"; shift
  local mesaj
  if mesaj="$(denetci "$@")"; then gecti "$ad" "$mesaj"; else kaldi "$ad" "$mesaj"; fi
}

# Gömülü denetçi. Her alt komut tek satır yazar; 0 = geçti, 1 = kaldı.
denetci() {
  python3 - "$@" <<'PY'
import json, os, plistlib, re, sys

komut, args = sys.argv[1], sys.argv[2:]


def sonuc(gecti, mesaj):
    print(mesaj)
    sys.exit(0 if gecti else 1)


def define_oku(yol):
    try:
        with open(yol, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        sonuc(False, "define dosyası yok: " + yol)
    except ValueError as e:
        sonuc(False, "define dosyası JSON değil (" + str(e) + "): " + yol)


def alan(d, ad):
    v = d.get(ad)
    if v is None:
        return ""
    ham = str(v)
    kirpik = ham.strip()
    # Kapı KIRPILMIŞ değeri onaylayıp uygulama HAM değeri okursa yeşil yalan
    # olur: `--dart-define-from-file` değeri kırpmıyor (ölçüldü 2026-10-24,
    # `flutter test --dart-define-from-file` ile: "appl_X " →
    # String.fromEnvironment uzunluğu 7; " 123" → force_update'in mağaza
    # bağlantısı biçiminde "id%20123"). Sonda boşluklu anahtar RevenueCat'e
    # boşlukla gider; kırpılmış hâl ham değerin alt dizesi olduğu için paket
    # araması da geçiyordu. Yalnız boşluktan ibaret değer "boş" sayılır — o
    # hâlin kendi, daha açıklayıcı mesajı var. Değerin kendisi BASILMAZ.
    if kirpik and kirpik != ham:
        sonuc(False, ad + " baş/son boşluk taşıyor: uygulama ham değeri okur "
              "(dart-define kırpmaz), paket boşluklu değerle çıkardı. Define "
              "dosyasında boşluğu sil.")
    return kirpik


def plist_oku(yol):
    with open(yol, "rb") as f:
        return plistlib.load(f)


def derleme_numarasi_karari(ham, kaynak):
    if not re.fullmatch("[0-9]+", ham or ""):
        sonuc(False, kaynak + " derleme numarası okunamadı ('" + str(ham) + "')")
    n = int(ham)
    yanmis = [int(k) for k in os.environ["RYTHO_YANMIS_KODLAR"].split()]
    belirsiz = [int(k) for k in os.environ["RYTHO_BELIRSIZ_KODLAR"].split()]
    taban = int(os.environ["RYTHO_EN_DUSUK_KOD"])
    # Engel App Store DEĞİL (Apple derleme numarası Play'den bağımsız);
    # mesaj bunu söylemezse okuyan "Apple bunu reddeder" sanıp yanlış
    # gerekçeye varır. Asıl engel sunucunun platformsuz aynası (U29).
    sunucu = ("App Store Connect bu sayıyı Play'den bağımsız kabul eder; engel "
              "mağaza değil SUNUCU: appBuild aynası ve minBuild eşiği platform "
              "ayırmıyor (app_gate.py, U29), aynı sayı farklı içerikli iki paketi "
              "gösterir. ")
    duzelt = "pubspec.yaml 'version:' satırında +" + str(taban) + " ya da üstünü kullan."
    if n in yanmis:
        sonuc(False, kaynak + " derleme numarası " + str(n) + " Android'de YANMIŞ bir kod "
              "(" + ", ".join(map(str, yanmis)) + "). " + sunucu + duzelt)
    if n in belirsiz:
        sonuc(False, kaynak + " derleme numarası " + str(n) + ": Android'de kullanılıp "
              "kullanılmadığı BİLİNMİYOR (Console'a yüklenip yüklenmediği ölçülmedi); "
              "bilinmeyen kod kullanılmış sayılır. " + sunucu + duzelt)
    if n < taban:
        sonuc(False, kaynak + " derleme numarası " + str(n) + " < " + str(taban) + ". Gizlilik "
              "metni (web/legal/gizlilik.html, legal_texts.dart) AI onay kutusunun "
              "1.20.0+" + str(taban) + " ile geldiğini söylüyor; kutuyu taşıyan bu paket "
              "daha küçük numarayla o cümleyi yalanlar. pubspec.yaml'da +" + str(taban) +
              " ya da üstünü kullan.")
    sonuc(True, kaynak + " derleme numarası " + str(n))


def app_ikilisi(app):
    yol = os.path.join(app, "Frameworks", "App.framework", "App")
    if not os.path.isfile(yol):
        sonuc(False, "Frameworks/App.framework/App yok — bu bir Flutter iOS paketi mi? (" + app + ")")
    with open(yol, "rb") as f:
        return f.read()


def beklenmeyen_hata(tur, deger, iz):
    # Okunamayan dosya (bozuk JSON, eksik Info.plist) kapıyı BOŞ mesajla
    # kırmızıya düşürmesin: neyin okunamadığı yazılır. sonuc()'un
    # SystemExit'i buraya gelmez.
    print("denetim okunamadı: " + tur.__name__ + ": " + str(deger))
    sys.exit(1)


sys.excepthook = beklenmeyen_hata

if komut == "rc-ios-anahtari":
    v = alan(define_oku(args[0]), "REVENUECAT_IOS_KEY")
    if not v:
        sonuc(False, "REVENUECAT_IOS_KEY boş. Uygulama satın almayı tamamen kapalı "
              "açar. RevenueCat'te App Store uygulamasını aç ve 'appl_' anahtarını "
              "define dosyasına yaz (docs/ios-uyum-denetimi.md U02).")
    if v.startswith("test_"):
        sonuc(False, "REVENUECAT_IOS_KEY 'test_' önekli (RevenueCat Test Store). Yayın "
              "derlemesinde SDK bu anahtarla BİLEREK çöker; uygulama onu yok sayar ve "
              "satın alma kapalı çıkar. Gerçek 'appl_' anahtarını yaz (U02).")
    if not v.startswith("appl_"):
        sonuc(False, "REVENUECAT_IOS_KEY 'appl_' ile başlamıyor (önek: '" + v[:5] +
              "'). App Store anahtarı RevenueCat'te iOS uygulamasının anahtarıdır; "
              "'goog_' Android'inkidir.")
    sonuc(True, "'appl_' önekli, " + str(len(v)) + " karakter")

elif komut == "rc-android-anahtari":
    # iOS paketi bu anahtardan BOZULMAZ: Release AOT Android dalını iOS
    # ikilisinden atıyor (ölçüldü 2026-10-24: sahte test_ Android anahtarıyla
    # imzasız Release, App.framework/App içinde 0 kez). Kapının sebebi
    # dosyanın kendisi: varsayılan define dosyası İKİ platformun yayın
    # dosyası (build-aab.ps1 aynı dosyayı okuyor ve test_ önekli Android
    # anahtarını REDDEDİYOR). Bu dosyayla iOS yayını çıkarmak, Android'in
    # aynı dosyadan çıkamayacağı bir yayın demek; ucuz olduğu yerde, derleme
    # BAŞLAMADAN söylenir. Boş Android anahtarı bu kapının işi değil: iOS
    # paketine dokunmuyor ve build-aab.ps1 onu ayrıca reddediyor.
    v = alan(define_oku(args[0]), "REVENUECAT_ANDROID_KEY")
    if v.startswith("test_"):
        sonuc(False, "REVENUECAT_ANDROID_KEY 'test_' önekli (RevenueCat Test Store): bu "
              "define dosyası yayın dosyası değil, aynı dosyayla AAB üretilemez "
              "(build-aab.ps1 reddeder). iOS paketi bundan bozulmaz — Release "
              "derlemesinde Android anahtarı iOS ikilisine girmiyor (ölçüldü). "
              "Gerçek 'goog_' anahtarını yaz; yalnız ölçüm derlemesiyse "
              "--yalniz-denetle kullan.")
    sonuc(True, "'test_' önekli değil" if v else "boş (iOS paketine dokunmaz)")

elif komut == "appstore-app-id":
    v = alan(define_oku(args[0]), "APPSTORE_APP_ID")
    if not re.fullmatch("[0-9]+", v):
        sonuc(False, "APPSTORE_APP_ID sayısal değil ('" + v + "'). App Store Connect kaydı "
              "açılınca doğan sayısal kimliği yaz; boşken zorunlu güncelleme ekranı "
              "iOS'ta mağaza düğmesi GÖSTERMEZ (force_update_screen.dart).")
    sonuc(True, v)

elif komut == "plus-yetkisi":
    v = alan(define_oku(args[0]), "RYTHO_PLUS_ENTITLEMENT")
    if not v:
        sonuc(False, "RYTHO_PLUS_ENTITLEMENT boş. RevenueCat panelindeki yetki kimliğini "
              "birebir yaz; yanlışsa satın alma başarılı olur ama abonelik açılmaz.")
    sonuc(True, "'" + v + "'")

elif komut == "imza-takimi":
    pbx_yol, aasa_yol, kimlik = args
    with open(pbx_yol, encoding="utf-8") as f:
        pbx = f.read()
    # /* … */ yorumları ÖNCE atılır: bir şeyin yokluğunu arayan bekçi onu
    # ANLATAN yorumu görmemeli (CLAUDE.md §5).
    pbx = re.sub("/[*].*?[*]/", "", pbx, flags=re.S)
    takimlar = sorted(set(re.findall('DEVELOPMENT_TEAM = "?([^";]+)"?;', pbx)))
    if not takimlar:
        sonuc(False, "pbxproj'de DEVELOPMENT_TEAM yok. Xcode → Runner → Signing & "
              "Capabilities'te takımı seç.")
    if len(takimlar) > 1:
        sonuc(False, "pbxproj'de birden fazla takım: " + ", ".join(takimlar))
    takim = takimlar[0]
    if "TEAMID" in pbx or not re.fullmatch("[A-Z0-9]{10}", takim):
        sonuc(False, "pbxproj takımı yer tutucu ya da geçersiz ('" + takim + "').")
    with open(aasa_yol, encoding="utf-8") as f:
        aasa = json.load(f)
    kimlikler = sorted({d.get("appID", "") for d in aasa.get("applinks", {}).get("details", [])})
    if any("TEAMID" in k for k in kimlikler):
        sonuc(False, "AASA appID hâlâ 'TEAMID' yer tutucusu taşıyor: " + ", ".join(kimlikler) +
              ". Evrensel bağlantılar uygulamayı açmaz.")
    beklenen = takim + "." + kimlik
    if kimlikler != [beklenen]:
        sonuc(False, "AASA appID " + ", ".join(kimlikler) + " ≠ imza takımı " + beklenen +
              ". iOS bağlantıyı uygulamaya devretmez; davetler Safari'de açılır.")
    sonuc(True, beklenen)

elif komut == "derleme-numarasi-pubspec":
    with open(args[0], encoding="utf-8") as f:
        satirlar = [s for s in f.read().splitlines() if s.startswith("version:")]
    if not satirlar:
        sonuc(False, "pubspec.yaml'da 'version:' satırı yok")
    surum = satirlar[0][len("version:"):].split("#")[0].strip()
    derleme_numarasi_karari(surum.split("+")[1] if "+" in surum else "", "pubspec")

elif komut == "derleme-numarasi-paket":
    info = plist_oku(os.path.join(args[0], "Info.plist"))
    derleme_numarasi_karari(str(info.get("CFBundleVersion", "")), "paket")

elif komut == "test-anahtari-yok":
    # Dart AOT dizeleri ikiliye bitişik ASCII olarak gömülür (bugünkü test_
    # anahtarı bu yolla App içinde bulundu, hazırlık denetimi 2026-10-23).
    # Önek tek başına aranmaz: uygulamanın KENDİ `kRcTestStoreOneki`
    # sabiti ('test_', subscription.dart) temiz pakette de duruyor —
    # ölçüldü 2026-10-23, `appl_` anahtarlı derlemede çıplak 'test_' 1 kez.
    # Anahtar biçimi önek + uzun harf-rakam dizisi.
    #
    # Mesaj İKİ olasılığı adlandırır: bayt hangi anahtardan geldiğini
    # söylemiyor. Eski mesaj "satın alma kapalı çıkar" diye tek sebep
    # beyan ediyordu; Android anahtarı test_ olan bir pakette bu yanlış
    # gerekçe olurdu (iOS yalnız kendi anahtarına bakıyor).
    bulunan = re.findall(b"test_[A-Za-z0-9]{20,}", app_ikilisi(args[0]))
    if bulunan:
        sonuc(False, str(len(bulunan)) + " adet 'test_' önekli anahtar baytı App.framework/App "
              "içinde. İki olasılık: (1) REVENUECAT_IOS_KEY 'test_' önekli — uygulama "
              "yayında onu yapılandırılmamış sayar, satın alma 'kullanılamıyor' çıkar "
              "(ön kapı bunu durdurur; paket başka bir define dosyasıyla mı derlendi?); "
              "(2) başka bir 'test_' anahtarı pakete girmiş, ör. REVENUECAT_ANDROID_KEY "
              "— bugünkü Release derlemesinde Android anahtarı iOS ikilisine girmiyor "
              "(ölçüldü 2026-10-24), yani bu ancak derleme biçimi değişirse olur ve iOS "
              "satın almasını bozmaz.")
    sonuc(True, "App.framework/App içinde 'test_' anahtarı yok")

elif komut == "rc-anahtar-pakette":
    d = define_oku(args[1])
    ikili = app_ikilisi(args[0])
    anahtar = alan(d, "REVENUECAT_IOS_KEY")
    if not anahtar:
        sonuc(False, "define dosyasında REVENUECAT_IOS_KEY boş; paketteki anahtar doğrulanamaz")
    # Anahtarın TAMAMI aranır, yalnız öneki değil: yanlış anahtarla
    # derlenmiş paket de geçmemeli (build-aab.ps1 ile aynı kural).
    if anahtar.encode() not in ikili:
        sonuc(False, "RevenueCat iOS anahtarı pakette YOK. Satın almalar cihazda "
              "'kullanılamıyor' diyecek. Derleme dart-define'sız mı ya da başka bir "
              "define dosyasıyla mı yapıldı?")
    yetki = alan(d, "RYTHO_PLUS_ENTITLEMENT")
    if yetki and yetki.encode() not in ikili:
        sonuc(False, "Yetki kimliği ('" + yetki + "') pakette yok; abonelik satın alınsa "
              "bile açılmaz.")
    sonuc(True, "anahtar ve yetki kimliği ('" + yetki + "') pakette")

elif komut == "simulator-taslagi-yok":
    app = args[0]
    info = plist_oku(os.path.join(app, "Info.plist"))
    platformlar = info.get("CFBundleSupportedPlatforms", [])
    if platformlar != ["iPhoneOS"]:
        sonuc(False, "paket cihaz paketi değil: CFBundleSupportedPlatforms = " + str(platformlar))
    # SimulatorStubs/MLKitSimulatorStubs.m'nin hata kodu. Cihazda dosyanın
    # içi TARGET_OS_SIMULATOR yüzünden boş derlenir; dize pakette görünürse
    # yüz okuma cihazda "simülatörde yok" der.
    for kok, _, dosyalar in os.walk(app):
        for ad in dosyalar:
            yol = os.path.join(kok, ad)
            if os.path.islink(yol):
                continue
            with open(yol, "rb") as f:
                if b"SIMULATORDE_YOK" in f.read():
                    sonuc(False, "simülatör ML Kit taslağı pakette: 'SIMULATORDE_YOK' → " +
                          os.path.relpath(yol, app))
    sonuc(True, "iPhoneOS paketi, 'SIMULATORDE_YOK' yok")

elif komut == "mlkit-gercek":
    # Taslağın yokluğu tek başına yetmez: Podfile simülatörde ML Kit
    # çerçevelerini bağlamadan ÇIKARIYOR. Cihaz paketinde gerçek yüz
    # algılayıcının sınıf adı bulunmalı (MLKitFaceDetection).
    app = args[0]
    for kok, _, dosyalar in os.walk(app):
        for ad in dosyalar:
            yol = os.path.join(kok, ad)
            if os.path.islink(yol) or ad.endswith((".png", ".car", ".tflite", ".ttf", ".otf")):
                continue
            with open(yol, "rb") as f:
                if b"MLKFaceDetector" in f.read():
                    sonuc(True, "gerçek ML Kit yüz algılayıcısı pakette (" +
                          os.path.relpath(yol, app) + ")")
    sonuc(False, "pakette 'MLKFaceDetector' yok: ML Kit bağlanmamış; yüz okuma cihazda "
          "çalışmaz. Simülatör derlemesi mi denetleniyor?")

elif komut == "izinler":
    info = plist_oku(os.path.join(args[0], "Info.plist"))
    # Kalıp NS öneki ve Dictionary soneki İSTEMEZ: Apple'ın gizlilik
    # anahtarlarının hepsi NS ile başlamıyor (NFCReaderUsageDescription) ve
    # bir kısmı sözlük (NSLocationTemporaryUsageDescriptionDictionary).
    # Eski "NS…UsageDescription" kalıbı ikisini de görmüyordu; NFC ya da
    # konum eklentisi gelse kapı "küme aynı" deyip GEÇİRİYORDU (çürütme
    # turu, 2026-10-24, değiştirilmemiş betikle ölçüldü).
    var = {k for k in info if re.fullmatch("[A-Za-z]*UsageDescription(Dictionary)?", k)}
    beklenen = set(os.environ["RYTHO_BEKLENEN_IZINLER"].split())
    fazla, eksik = sorted(var - beklenen), sorted(beklenen - var)
    if fazla or eksik:
        parca = []
        if fazla:
            parca.append("BEKLENMEYEN: " + ", ".join(fazla) + " (yeni bir eklenti izin getirmiş "
                         "olabilir; mağaza listesinde görünür ve gizlilik beyanını yalanlar)")
        if eksik:
            parca.append("EKSİK: " + ", ".join(eksik) + " (App Store Connect ikilideki API "
                         "başvurusunu görüp ITMS-90683 ile geri çevirir)")
        sonuc(False, "; ".join(parca))
    sonuc(True, str(len(var)) + " izin metni, küme beklenenle aynı")

elif komut == "gizlilik-manifesti":
    yol = os.path.join(args[0], "PrivacyInfo.xcprivacy")
    if not os.path.isfile(yol):
        sonuc(False, "PrivacyInfo.xcprivacy pakette yok; App Store Connect gerekli-neden "
              "API beyanı olmadan ITMS-91053 uyarısı verir. pbxproj Copy Bundle "
              "Resources'a bak.")
    try:
        plist_oku(yol)
    except Exception as e:
        sonuc(False, "PrivacyInfo.xcprivacy okunamadı: " + str(e))
    sonuc(True, "pakette ve geçerli plist")

elif komut in ("imza-aps-ortami", "imza-get-task-allow", "imza-yetkileri"):
    try:
        yetkiler = plist_oku(args[0])
    except Exception as e:
        sonuc(False, "imzadaki yetkiler okunamadı: " + str(e))
    if komut == "imza-aps-ortami":
        v = yetkiler.get("aps-environment")
        if v != "production":
            sonuc(False, "aps-environment = " + repr(v) + ". Mağaza paketi SANDBOX jetonu "
                  "alırsa sunucu üretim APNs'ine gönderir ve bildirim hiçbir yere düşmez.")
        sonuc(True, "aps-environment = production")
    if komut == "imza-get-task-allow":
        if yetkiler.get("get-task-allow", False) is not False:
            sonuc(False, "get-task-allow = " + repr(yetkiler.get("get-task-allow")) +
                  ". Geliştirme profiliyle imzalanmış; App Store Connect reddeder.")
        sonuc(True, "get-task-allow yok/false")
    gerekli = ["aps-environment", "com.apple.developer.applesignin",
               "com.apple.developer.associated-domains",
               "com.apple.developer.devicecheck.appattest-environment"]
    eksik = [k for k in gerekli if k not in yetkiler]
    if eksik:
        sonuc(False, "imzada eksik yetki: " + ", ".join(eksik) + ". App ID'de yetenek "
              "kapalı olabilir (developer.apple.com → Identifiers → ai.rytho).")
    sonuc(True, "dört yetki imzada")

else:
    sonuc(False, "bilinmeyen denetim: " + komut)
PY
}

on_kapilar() {
  echo "== Ön kapılar (kaynak) =="
  local xc
  xc="$(xcodebuild -version 2>/dev/null | head -n 1)"
  local xc_desen='^Xcode 26[.]'
  if [[ "$xc" =~ $xc_desen ]]; then
    gecti "xcode-surumu" "$xc"
  else
    kaldi "xcode-surumu" "'${xc:-xcodebuild yok}'. Bu depo Xcode 26.x ister: Xcode 27 RevenueCat'i Swift 6.4'te derleyemiyor ve lipo değişikliğiyle düşüyor (CLAUDE.md §7). sudo xcode-select -s /Applications/Xcode-26.app"
  fi

  if [ ! -f "$DEFINES" ]; then
    kaldi "define-dosyasi" "$DEFINES yok. dart_defines.example.json'u kopyalayıp gerçek anahtarları yaz; dosya gitignore'da, depoya GİRMEZ."
  else
    gecti "define-dosyasi" "$DEFINES"
  fi
  kapi "revenuecat-ios-anahtari" rc-ios-anahtari "$DEFINES"
  kapi "revenuecat-android-anahtari" rc-android-anahtari "$DEFINES"
  kapi "appstore-app-id" appstore-app-id "$DEFINES"
  kapi "plus-yetkisi" plus-yetkisi "$DEFINES"
  kapi "imza-takimi" imza-takimi "$PBXPROJ" "$AASA" "$RYTHO_KIMLIK"
  kapi "derleme-numarasi" derleme-numarasi-pubspec "$PUBSPEC"
}

# $1 = .app dizini, $2 = 1 ise imza zorunlu (denetlenen şey bir IPA: tam
# kipte ya da --yalniz-denetle <.ipa>; IPA mağazaya gider).
paket_kapilari() {
  local app="$1" imza_zorunlu="$2"
  echo "== Paket kapıları: $app =="
  kapi "paket-test-anahtari-yok" test-anahtari-yok "$app"
  if [ -f "$DEFINES" ]; then
    kapi "paket-revenuecat-anahtari" rc-anahtar-pakette "$app" "$DEFINES"
  else
    atlandi "paket-revenuecat-anahtari" "define dosyası yok: $DEFINES"
  fi
  kapi "paket-simulator-taslagi-yok" simulator-taslagi-yok "$app"
  kapi "paket-mlkit-gercek" mlkit-gercek "$app"
  kapi "paket-izin-anahtarlari" izinler "$app"
  kapi "paket-gizlilik-manifesti" gizlilik-manifesti "$app"
  kapi "paket-derleme-numarasi" derleme-numarasi-paket "$app"

  # İmza. `--no-codesign` paketi hiç imzalanmamış olur; Apple Silicon'da
  # bağlayıcının kendiliğinden koyduğu ad-hoc imza ise ne takım ne yetki
  # taşır — ikisi de "imzasız" sayılır, yetkileri okunacak bir şey yok.
  local imza
  imza="$(codesign -dv "$app" 2>&1)"
  local imza_kodu=$?
  local imzasiz=0
  if [ $imza_kodu -ne 0 ] || printf '%s' "$imza" | grep -q 'Signature=adhoc'; then
    imzasiz=1
  fi
  local ad
  if [ $imzasiz -eq 1 ]; then
    for ad in imza-aps-ortami imza-get-task-allow imza-yetkileri; do
      if [ "$imza_zorunlu" = "1" ]; then
        kaldi "$ad" "paket imzasız; mağazaya gidecek IPA dağıtım imzası taşımalı."
      else
        atlandi "$ad" "imzasız"
      fi
    done
    return
  fi
  local yetki_dosyasi
  yetki_dosyasi="$(mktemp -t rytho-yetki)"
  codesign -d --entitlements :- "$app" > "$yetki_dosyasi" 2>/dev/null
  for ad in imza-aps-ortami imza-get-task-allow imza-yetkileri; do
    kapi "$ad" "$ad" "$yetki_dosyasi"
  done
  rm -f "$yetki_dosyasi"
}

# Geçici dizin ANA kabukta kurulur: `$(…)` içinde atanan değişken alt
# kabukta kalır ve `trap` silinecek yolu hiç görmezdi.
GECICI="$(mktemp -d -t rytho-ipa)"
temizle() { rm -rf "$GECICI"; }
trap temizle EXIT

# $1 = .ipa → $GECICI içine açar, Payload/*.app yolunu yazar.
ipa_ac() {
  if ! unzip -q -o "$1" -d "$GECICI" >/dev/null; then
    echo ""; return 1
  fi
  local app
  for app in "$GECICI"/Payload/*.app; do
    if [ -d "$app" ]; then echo "$app"; return 0; fi
  done
  echo ""; return 1
}

ozet() {
  echo
  if [ $KALAN -gt 0 ]; then
    if [ $ATLANAN -gt 0 ]; then
      echo "SONUÇ: $KALAN kapı KALDI; ayrıca $ATLANAN kapı ATLANDI (atlanan GEÇMİŞ sayılmaz)."
    else
      echo "SONUÇ: $KALAN kapı KALDI."
    fi
    exit 1
  fi
  if [ $ATLANAN -gt 0 ]; then
    echo "SONUÇ: kalan kapı yok; $ATLANAN kapı ATLANDI. Atlanan kapı GEÇMİŞ sayılmaz: bu paket mağazaya gidecek paket değil."
  else
    echo "SONUÇ: bütün kapılar geçti."
  fi
  exit 0
}

case "$KIP" in
  kuru)
    on_kapilar
    ozet ;;
  denetle)
    APP="$HEDEF"
    case "$HEDEF" in
      *.ipa)
        if ! APP="$(ipa_ac "$HEDEF")" || [ -z "$APP" ]; then
          echo "IPA açılamadı ya da içinde Payload/*.app yok: $HEDEF" >&2; exit 2
        fi ;;
    esac
    if [ ! -d "$APP" ]; then
      echo "Paket bulunamadı: $HEDEF" >&2; exit 2
    fi
    # .ipa yalnız yüklemek için üretilen biçim: imzasızı "ATLANDI" ile
    # çıkış 0'a bırakmak onu yeşil gösterirdi. .app ise imzasız ölçüm
    # derlemesinin (flutter build ios --no-codesign) doğal çıktısı.
    IMZA_ZORUNLU=0
    case "$HEDEF" in *.ipa) IMZA_ZORUNLU=1 ;; esac
    paket_kapilari "$APP" "$IMZA_ZORUNLU"
    ozet ;;
  tam)
    on_kapilar
    if [ $KALAN -gt 0 ]; then
      echo
      echo "SONUÇ: $KALAN ön kapı KALDI; derleme BAŞLATILMADI."
      exit 1
    fi
    echo "== Derleme: flutter build ipa --release =="
    # Eski IPA ÖNCE silinir: dışa aktarma düşüp önceki derlemenin IPA'sı
    # klasörde kalırsa kapılar BAYAT paketi ölçüp "geçti" derdi.
    rm -rf "$MOBIL/build/ios/ipa"
    if ! (cd "$MOBIL" && flutter build ipa --release --dart-define-from-file="$DEFINES"); then
      echo "SONUÇ: flutter build ipa başarısız." ; exit 1
    fi
    IPA=""
    for aday in "$MOBIL"/build/ios/ipa/*.ipa; do
      if [ -f "$aday" ]; then IPA="$aday"; fi
    done
    if [ -z "$IPA" ]; then
      echo "SONUÇ: IPA üretilmedi ($MOBIL/build/ios/ipa/). Dışa aktarma imzası düşmüş olabilir; arşiv build/ios/archive altında."
      exit 1
    fi
    if ! APP="$(ipa_ac "$IPA")" || [ -z "$APP" ]; then
      echo "SONUÇ: IPA açılamadı: $IPA"; exit 1
    fi
    paket_kapilari "$APP" 1
    if [ $KALAN -eq 0 ]; then
      echo "IPA: $IPA (yükleme ELLE: Xcode Organizer ya da Transporter)"
    fi
    ozet ;;
esac

# RythoAI yayin AAB'sini uretir ve SATIN ALMA ANAHTARININ paketde oldugunu
# DOGRULAR.
#
# Kullanim: infra klasorunden  ./build-aab.ps1
#
# ## Neden bu betik var
#
# 2026-08-16'da 1.5.0+17 duz `flutter build appbundle --release` ile
# uretildi. RevenueCat genel anahtari kaynakta DEGIL, derleme aninda
# `--dart-define-from-file` ile giriyor (bkz. lib/core/subscription.dart).
# Define verilmeyince `String.fromEnvironment` bos dondu, `billingConfigured`
# false oldu, SDK hic baslatilmadi ve cihazda hem abonelik hem jeton
# paketleri "Satin alma su an kullanilamiyor" dedi.
#
# Kotu tarafi sessiz olmasiydi: derleme BASARIYLA bitti, testler yesildi,
# imza ve surum kodu dogruydu. Kusur ancak magaza ekraninda goruldu.
#
# Bu yuzden burada iki kapi var: define dosyasi YOKSA derleme hic
# baslamaz; derleme bittikten sonra uretilen Dart snapshot'i icinde
# anahtar ARANIR ve bulunmazsa betik hata verir. Ikincisi onemli olan -
# "define'i gectim" demek yetmez, paketde OLDUGU olculur.
#
# NOT: bu dosyada ASCII DISI KARAKTER KULLANMA. PowerShell 5.1 BOM'suz
# .ps1 dosyalarini ANSI olarak okur; tek bir uzun tire betigi ayristirma
# hatasiyla dusuruyor (bir kez dusurdu).
$ErrorActionPreference = "Stop"

# YOL AYIRACI: her yerde ILERI BOLU. `Join-Path $kok "apps\mobile"` macOS'ta
# ters boluyu AYIRAC SAYMAZ, dosya adinin PARCASI sayar ve "apps\mobile" diye
# var olmayan tek bir klasor arar. Ileri bolu iki platformda da calisir
# (Windows API'si onu da kabul eder).
$repoRoot = Split-Path -Parent $PSScriptRoot
$mobil = Join-Path $repoRoot "apps/mobile"
$defines = Join-Path $mobil "dart_defines.local.json"

# Flutter once PATH'ten aranir; bulunamazsa Windows'taki bilinen kurulum.
# Sabit yol tek basina birakilsaydi betik macOS'ta hic calismazdi.
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter -and (Test-Path "C:/flutter/bin/flutter.bat")) {
    $flutter = "C:/flutter/bin/flutter.bat"
}
if (-not $flutter) {
    throw ("flutter bulunamadi: ne PATH'te var ne C:/flutter/bin/flutter.bat. " +
           "Flutter SDK'yi kur ve bin klasorunu PATH'e ekle.")
}

if (-not (Test-Path $defines)) {
    throw ("dart_defines.local.json bulunamadi ($defines). " +
           "dart_defines.example.json'u kopyalayip RevenueCat anahtarlarini " +
           "yaz. Bu dosya gitignore'da; depoya GIRMEZ.")
}

# Anahtarin gercek magaza anahtari oldugunu da soyle: `test_` onekli
# anahtar RevenueCat Test Store'a aittir ve satin almalari SIMULE eder.
# Yayin AAB'sinde bu sessiz bir tuzak olurdu.
$defineIcerik = Get-Content $defines -Raw | ConvertFrom-Json
$androidKey = $defineIcerik.REVENUECAT_ANDROID_KEY
if (-not $androidKey) {
    throw "dart_defines.local.json icinde REVENUECAT_ANDROID_KEY yok."
}
if ($androidKey.StartsWith("test_")) {
    # KT4: uyari yetmez - test anahtarli yayin AAB'si magazada satin
    # almayi sessizce simulasyona cevirir. Yayin betigi bunu URETMEZ.
    throw ("REVENUECAT_ANDROID_KEY 'test_' onekli (RevenueCat Test Store). " +
           "Yayin AAB'si gercek 'goog_' anahtari ister; " +
           "dart_defines.local.json'u duzelt.")
}

# KT4: release imzasi dogrulanir. build.gradle.kts key.properties yoksa
# SESSIZCE debug anahtarina dusuyor - Play boyle bir AAB'yi ya reddeder
# ya da App Signing'e yanlis anahtar gider. Kapi burada.
$keyProps = Join-Path $mobil "android/key.properties"
if (-not (Test-Path $keyProps)) {
    throw ("android\key.properties yok - release imzasi kurulmamis. " +
           "Bu haliyle AAB DEBUG anahtariyla imzalanirdi.")
}

Write-Host "1/3 Surum bilgisi..."
$surum = (Select-String -Path (Join-Path $mobil "pubspec.yaml") `
    -Pattern "^version:\s*(.+)$").Matches[0].Groups[1].Value.Trim()
Write-Host "    pubspec version: $surum"

Write-Host "2/3 AAB derleniyor (dart-define ile)..."
Push-Location $mobil
try {
    $eskiTercih = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $flutter build appbundle --release `
        --dart-define-from-file=dart_defines.local.json
    $kod = $LASTEXITCODE
    $ErrorActionPreference = $eskiTercih
    if ($kod -ne 0) { throw "flutter build appbundle basarisiz (cikis $kod)." }
} finally {
    Pop-Location
}

Write-Host "3/3 Paket dogrulaniyor..."
$aab = Join-Path $mobil "build/app/outputs/bundle/release/app-release.aab"
if (-not (Test-Path $aab)) { throw "AAB uretilmedi: $aab" }

# Dart snapshot'i (libapp.so) cikarilip icinde anahtar ARANIR. Sabit
# dizeler AOT snapshot'a gomulur; define gecmediyse dize hic olmaz.
# $env:TEMP yalniz Windows'ta tanimli; macOS'ta bos gelir ve Join-Path
# kok dizine yazmaya calisirdi. .NET'in kendi gecici klasoru iki
# platformda da dogru yeri verir.
$gecici = Join-Path ([System.IO.Path]::GetTempPath()) ("rytho-aab-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $gecici | Out-Null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($aab)
    try {
        $girdi = $zip.Entries | Where-Object {
            $_.FullName -eq "base/lib/arm64-v8a/libapp.so" }
        if (-not $girdi) { throw "AAB icinde arm64 libapp.so yok." }
        $libapp = Join-Path $gecici "libapp.so"
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile(
            $girdi, $libapp, $true)
    } finally { $zip.Dispose() }

    $metin = [System.Text.Encoding]::ASCII.GetString(
        [System.IO.File]::ReadAllBytes($libapp))
    # Anahtarin TAMAMI aranir, yalnizca oneki degil: yanlis anahtarla
    # derlenmis bir paket de gecmemeli.
    if ($metin.Contains($androidKey)) {
        Write-Host "    OK: RevenueCat Android anahtari pakette."
    } else {
        throw ("RevenueCat anahtari pakette YOK. Satin almalar cihazda " +
               "'kullanilamiyor' diyecek. Derleme dart-define'siz mi " +
               "yapildi?")
    }

    $entitlement = $defineIcerik.RYTHO_PLUS_ENTITLEMENT
    if ($entitlement -and -not $metin.Contains($entitlement)) {
        throw ("Yetki kimligi ('$entitlement') pakette yok; abonelik " +
               "satin alinsa bile acilmaz.")
    }
    Write-Host "    OK: yetki kimligi pakette ('$entitlement')."
} finally {
    Remove-Item -Recurse -Force $gecici -ErrorAction SilentlyContinue
}

# KT4: imza GERCEKTEN dogrulanir (elle keytool ipucu yerine). Debug
# anahtarinin CN'i "Android Debug"tur; yayin paketinde gorunmemeli.
$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if ($keytool) {
    $imza = & $keytool.Source -printcert -jarfile $aab 2>$null | Out-String
    if ($imza -match "Android Debug") {
        throw "AAB DEBUG anahtariyla imzalanmis - key.properties okunamadi mi?"
    }
    Write-Host "    OK: imza debug degil (keytool dogrulandi)."
} else {
    Write-Warning "keytool bulunamadi; imza elle dogrulanmali."
}

# Izin kapisi (kapali test denetimi, 2026-09-14).
#
# Birlesmis RELEASE manifesti okundugunda paket RECORD_AUDIO (mikrofon),
# READ_PHONE_STATE (telefon), USE_BIOMETRIC/USE_FINGERPRINT ve
# WRITE_EXTERNAL_STORAGE istiyordu. Hicbirini kod kullanmiyor; hepsi
# eklentilerden devralinmisti. Magaza listesinde "Mikrofon" ve "Telefon"
# yazardi ve gizlilik metnimiz "mikrofona hic erisilmez" diyor - beyan ile
# paket celisiyordu. AndroidManifest.xml'e tools:node="remove" satirlari
# kondu; bu kapi onlarin durdugunu ARTEFAKTTAN dogrular. Yeni bir eklenti
# ayni izni geri getirirse build burada duser, magazada degil.
$yasakIzinler = @(
    "android.permission.RECORD_AUDIO",
    "android.permission.READ_PHONE_STATE",
    "android.permission.USE_BIOMETRIC",
    "android.permission.USE_FINGERPRINT",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    # Reklam kimligi (2026-09-18): Play Console "Reklam Kimligi" beyani
    # bu izni gorunce kapali testi durdurdu. Uygulamada reklam YOK; izin
    # firebase_analytics'ten ortuk geliyordu. Cikarildi, formda "Hayir"
    # isaretleniyor. Geri gelirse beyan yalan olur ve surum bloklanir.
    "com.google.android.gms.permission.AD_ID",
    "android.permission.ACCESS_ADSERVICES_AD_ID",
    "android.permission.ACCESS_ADSERVICES_ATTRIBUTION"
)
$birlesmis = Get-ChildItem -Path (Join-Path $mobil "build/app/intermediates/merged_manifest/release") -Filter "AndroidManifest.xml" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($birlesmis) {
    $mf = Get-Content $birlesmis.FullName -Raw
    # YORUMLAR ONCE ATILIR. Kendi manifest yorumlarimiz bu izin adlarini
    # KELIMESI KELIMESINE anlatiyor (neden kaldirildiklarini yaziyor) ve
    # birlestirme yorumlari cikti dosyasina AYNEN tasiyor. Ham metinde
    # arasak kendi aciklamamiza takilip her derlemede sahte hata verirdik.
    $mfTemiz = [regex]::Replace($mf, "(?s)<!--.*?-->", "")
    $bulunan = @($yasakIzinler | Where-Object { $mfTemiz -match [regex]::Escape($_) })
    if ($bulunan.Count -gt 0) {
        throw ("Pakette kullanilmayan izin(ler) var: " +
               ($bulunan -join ", ") +
               ". Magaza listesinde gorunur ve gizlilik beyanimizi yalanlar. " +
               "AndroidManifest.xml'deki tools:node=`"remove`" satirlarini " +
               "kontrol et (yeni bir eklenti izni geri getirmis olabilir).")
    }
    Write-Host "    OK: kullanilmayan izin yok (mikrofon/telefon/biyometrik)."

    # Kamera ZORUNLU olmamali. camerax `camera.any`'yi `required`
    # BELIRTMEDEN ekliyor ve Android varsayilani `true`; bu, bizim bilerek
    # koydugumuz required="false" kararini sessizce geri aliyor ve Play
    # uygulamayi kamerasiz cihazlara HIC gostermiyordu. Yorumlar disarida
    # birakilarak gercek girdi okunur.
    $anyEtiket = [regex]::Match(
        $mfTemiz, "(?s)<uses-feature\b[^>]*android\.hardware\.camera\.any[^>]*/>")
    if ($anyEtiket.Success -and $anyEtiket.Value -notmatch 'android:required="false"') {
        throw ("camera.any ZORUNLU gorunuyor; Play uygulamayi kamerasiz " +
               "cihazlara gostermez. AndroidManifest.xml'deki " +
               "tools:replace=`"android:required`" satirini kontrol et.")
    }
    Write-Host "    OK: kamera zorunlu degil (camera.any required=false)."
} else {
    Write-Warning "Birlesmis manifest bulunamadi; izin kapisi atlandi."
}

# R8 OPTIMIZASYON kapisi (Play "DEX kodu optimizasyonu esigin altinda",
# 2026-10-10). Play bu olcumu AAB'deki BUNDLE-METADATA/com.android.tools/
# r8.json'dan okuyor. Surum 48'de `isOptimizationsEnabled: false` ve
# `noOptimizationPercentage: 100` idi: kucultme ve karartma ACIK, optimizasyon
# KAPALI - derleme basarili, testler yesil, kusur yalniz Play'in ekraninda.
# Kaynagi RevenueCat'in Amazon modulunun consumer kuralindaki -dontoptimize
# idi (build.gradle.kts keepRules.ignoreFrom ile disarida). Kaynak kurali
# dogru olsa da YARIN baska bir kutuphane ayni satiri getirebilir; R8'de tek
# bir -dontoptimize butun uygulamayi kapatir ve bunu yalniz ARTEFAKT soyler.
# Esik Play'in esigi: en az %25 optimize edilmis = en fazla %75 edilmemis.
$r8Girdi = $null
$zip = [System.IO.Compression.ZipFile]::OpenRead($aab)
try {
    $r8Girdi = $zip.Entries | Where-Object {
        $_.FullName -eq "BUNDLE-METADATA/com.android.tools/r8.json" }
    if (-not $r8Girdi) {
        throw ("AAB'de r8.json yok - R8 hic kosmamis mi? Play bu paketi " +
               "'optimize edilmemis' sayar.")
    }
    $okuyucu = New-Object System.IO.StreamReader($r8Girdi.Open())
    try { $r8Metin = $okuyucu.ReadToEnd() } finally { $okuyucu.Dispose() }
} finally { $zip.Dispose() }
$r8 = $r8Metin | ConvertFrom-Json
if (-not $r8.options.isOptimizationsEnabled) {
    throw ("R8 optimizasyonu KAPALI (r8.json isOptimizationsEnabled=false). " +
           "Bir kutuphanenin consumer kurali -dontoptimize getirmis olabilir: " +
           "build/app/outputs/mapping/release/configuration.txt icinde " +
           "'-dontoptimize' ara, kaynagi keepRules.ignoreFrom ile disarida birak.")
}
$edilmemis = [double]$r8.stats.noOptimizationPercentage
if ($edilmemis -gt 75) {
    throw ("DEX'in yuzde $edilmemis'i optimize edilmemis; Play esigi en az %25 " +
           "optimize ister. r8.json stats.noOptimizationPercentage'a bak.")
}
Write-Host ("    OK: R8 optimizasyonu acik (optimize edilmemis DEX %" +
            $edilmemis + ", esik %75).")

$boyut = [math]::Round((Get-Item $aab).Length / 1MB, 1)
Write-Host ""
Write-Host "Tamamlandi: $aab ($boyut MiB, surum $surum)"
Write-Host "Imzayi dogrulamak icin: keytool -printcert -jarfile `"$aab`""

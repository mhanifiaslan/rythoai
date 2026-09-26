# RythoAI backend'i Cloud Run'a deploy eder.
# Kullanım: infra klasöründen ./deploy-backend.ps1
$ErrorActionPreference = "Stop"

$PROJECT = "rhytoai"
$REGION = "us-central1"
$SERVICE = "rytho-backend"
$IMAGE = "us-central1-docker.pkg.dev/$PROJECT/rytho/backend:latest"

$repoRoot = Split-Path -Parent $PSScriptRoot

# Vektor artefakti imaja gomuluyor; korpusla uyumsuzsa her sogut baslatma
# yeniden vektorleme faturasi cikarir ve ilk istekler anahtar kelime moduna
# duser. Bu yuzden deploy'dan ONCE kapsama dogrulanir.
Write-Host "0/2 Vektor artefakti dogrulaniyor..."
# venv duzeni platforma gore degisiyor: Windows'ta .venv/Scripts/python.exe,
# macOS/Linux'ta .venv/bin/python. Yalniz birini aramak betigi digerinde
# "venv bulunamadi" uyarisiyla SESSIZCE artefakt dogrulamasiz birakirdi.
$pythonExe = Join-Path $repoRoot "backend/.venv/Scripts/python.exe"
if (-not (Test-Path $pythonExe)) {
    $pythonExe = Join-Path $repoRoot "backend/.venv/bin/python"
}
if (Test-Path $pythonExe) {
    # PS 5.1 tuzagi: dogrulama betigi INFO loglarini STDERR'e yazar ve
    # ErrorActionPreference=Stop bunu gercek hata sanip deploy'u yarida
    # keser ("INFO [tr] 42 parca, 0 eksik vektor" bir kez tam boyle kesti).
    # Cikti dosyaya yonlendirilir, karar YALNIZCA cikis koduna bakar.
    $eskiTercih = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $pythonExe (Join-Path $repoRoot "backend/scripts/build_embeddings.py") --check 2>$null
    $kontrolKodu = $LASTEXITCODE
    $ErrorActionPreference = $eskiTercih
    if ($kontrolKodu -ne 0) {
        throw "Vektor artefakti korpusla uyumsuz. Once su komutu calistir: backend\scripts\build_embeddings.py"
    }
} else {
    Write-Warning "backend\.venv bulunamadi; artefakt kapsamasi DOGRULANMADI."
}

# gcloud ILERLEMEYI STDERR'E yazar ("Creating temporary archive of 362
# file(s)...", "Building and deploying..."). PowerShell 5.1 bunu
# ErrorActionPreference=Stop altinda GERCEK hata sayip deploy'u daha ilk
# satirda kesiyordu. Native komutun basarisi yalnizca CIKIS KODUNDAN
# okunur; bu sarmalayici o kurali uygular. (Ayni ders yukaridaki vektor
# kontrolunde de ogrenilmisti.)
function Invoke-Gcloud {
    param([Parameter(Mandatory = $true)][string[]]$Arguments,
          [Parameter(Mandatory = $true)][string]$Adim)
    $eskiTercih = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & gcloud @Arguments
    $kod = $LASTEXITCODE
    $ErrorActionPreference = $eskiTercih
    if ($kod -ne 0) { throw "$Adim basarisiz (gcloud cikis kodu $kod)." }
}

Write-Host "1/2 Cloud Build ile imaj derleniyor..."
Invoke-Gcloud -Adim "Cloud Build" -Arguments @(
    "builds", "submit", $repoRoot,
    "--project", $PROJECT,
    "--config", "$PSScriptRoot/cloudbuild.yaml")

Write-Host "2/2 Cloud Run'a deploy ediliyor..."

# DIKKAT: --set-env-vars mevcut degiskenleri TUMUYLE degistirir.
# Konsoldan elle verilen bayraklar bir sonraki deploy'da SESSIZCE
# silinir - kalici olacak her bayrak asagidaki satira yazilmali.
# RYTHO_MIN_BUILD (F3 -> PBZ): BILEREK YOK. Eskiden burada 0 duruyordu
# ve her deploy --set-env-vars ile onu yeniden yazip elle gcloud'la
# verilen esigi SESSIZCE sifirliyordu; 34 surumdur kapi hic kurulmadi.
# Zorunlu guncelleme anahtari artik Firestore config/app.minBuild
# dokumaninda yasar (panel -> Sistem -> "Zorunlu guncelleme"; 60 sn
# icinde her instance gorur, deploy gerektirmez). Env yalnizca ISTEGE
# BAGLI TABAN: etkin esik = max(env, dokuman). Tanimlanirsa panel o
# tabanin altina inemez - bu satira EKLEME, bkz. backend/core/app_gate.py.
# RYTHO_TOKENS_ENFORCE=1 (K5, 2026-08-13): jeton zorlamasi ACIK -
# bakiye yetmezse 402 + X-Paywall-Reason: tokens. Kuru calisma bitti;
# maliyet tavanlari artik gercekten uygulaniyor.
#
# NOT (R5-8): bu yorum blogu daha once bayraklarin ARASINDAYDI. Geri
# tirnakla devam eden bir komut satirinin ardindan yorum gelemez;
# PowerShell zinciri orada kesip "Missing expression after unary
# operator '--'" diye dusuyordu ve deploy hic calismiyordu. Yorumlar
# komutun ustunde durur, bayrak zinciri kesintisiz kalir.
#
# RYTHO_SUB_PRICES_USD TIRNAKSIZ yaziliyor — bilincli, olculdu (2026-09-14).
# Burada {`"rytho_plus_monthly`":4.4} yazildiginda Cloud Run'a
# {rytho_plus_monthly:4.4} olarak iniyordu: gcloud'un arguman ayristiricisi
# cift tirnaklari soyuyor. Sunucudaki json.loads dusuyor, fiyat sessizce
# 0.0'a ve panel MRR'i 0'a iniyordu - hicbir hata, hicbir log. Artik
# core/config.py `_fiyat_env` tirnaksiz bicimi de okuyor (test_fiyat_env.py);
# burada da soyulacak tirnak birakmiyoruz ki iki taraf birbirini dogrulasin.
Invoke-Gcloud -Adim "Cloud Run deploy" -Arguments @(
    "run", "deploy", $SERVICE,
    "--project", $PROJECT,
    "--region", $REGION,
    "--image", $IMAGE,
    "--allow-unauthenticated",
    "--memory", "2Gi",
    "--cpu", "2",
    "--timeout", "300",
    "--max-instances", "3",
    "--min-instances", "1",
    "--set-env-vars", "RYTHO_DEV_MODE=0,GOOGLE_CLOUD_PROJECT=$PROJECT,RYTHO_TOKENS_ENFORCE=1,RYTHO_SUB_PRICES_USD={rytho_plus_monthly:4.4}",
    "--set-secrets", "GEMINI_API_KEY=GEMINI_API_KEY:latest,REVENUECAT_WEBHOOK_SECRET=REVENUECAT_WEBHOOK_SECRET:latest,NOTIFY_SCHEDULER_SECRET=NOTIFY_SCHEDULER_SECRET:latest")

# --min-instances 1 BILINCLI VE UCRETLI bir karar.
#
# Olculen: servis sifira inince sonraki ilk istek 14,65 saniye suruyordu
# (hemen sonraki 0,0036 sn). Kullanicinin "bekliyor bekliyor bekliyor, sonra
# mesajlar geliyor" diye bildirdigi sey buydu. Bir instance surekli ayakta
# tutmak bunu bitiriyor; bedeli aylik ~25 USD ve kullanici sayisindan
# BAGIMSIZ, yani buyudukce kullanici basina dusen pay azaliyor.
#
# Bu tek basina yetmiyor: --max-instances 3 oldugu icin yuk 2. ve 3.
# instance'i actirdiginda onlar hala soguk basliyor. Onun icin agir
# kutuphaneler modul duzeyinden cikarildi (bkz. tests/test_cold_start.py).
#
# Bayrak burada durmali; yalnizca konsoldan verilirse bir sonraki deploy
# sessizce geri alir.
#
# REVENUECAT_WEBHOOK_SECRET olmadan /api/v1/billing/revenuecat 503 doner ve
# hicbir kullanici abone olarak isaretlenemez (dogrulamasiz abonelik yazmaya
# izin verilmiyor). Ayni deger RevenueCat panelindeki webhook'un Authorization
# basligina da yazilmali.
#
# NOTIFY_SCHEDULER_SECRET, Cloud Scheduler'in toplu bildirim ucunu tetiklerken
# tasidigi anahtardir. Anahtar ve zamanlayici isleri ./create-scheduler.ps1
# ile kurulur; bu deploy o anahtari konteynere tasir. Tanimsizken uc 503
# doner — acik birakmak, herkesin tum kullanicilara bildirim gonderebilmesi
# demek olurdu.
#
# Gelistirme sirasinda odemesiz test icin --set-env-vars satirina
# RYTHO_FORCE_PLUS=1 eklenebilir; uretimde ASLA acik birakilmamali.

Write-Host "Tamamlandı. Servis URL'i:"
gcloud run services describe $SERVICE --project $PROJECT --region $REGION --format "value(status.url)"

# Bildirim zamanlayicisini kurar (Cloud Scheduler).
#
# Kullanim: infra klasorunden ./create-scheduler.ps1
#
# TASARIM: iki is de SAATTE BIR calisir. Kullaniciya hangi saatte gidecegine
# sunucu karar verir (backend/services/notification_service.py): her kullanici
# icin YEREL saat hesaplanir ve yalnizca hedef saate denk gelenlere gonderilir.
# Saat dilimi basina ayri is tanimlamak yerine bu yol secildi — dunyada 38
# farkli UTC farki var ve her biri icin is tanimlamak yonetilemez olurdu.
#
# Gizli anahtar Secret Manager'da tutulur ve isin Authorization basliginda
# tasinir. Anahtar tanimsizken uc 503 doner (backend/api/notify.py).
# NOT: ErrorActionPreference bilincli olarak "Stop" DEGIL. PowerShell 5.1'de
# yerel bir exe'nin stderr'e yazmasi tek basina betigi dusuruyor; gcloud ise
# "kaynak yok" gibi BEKLENEN durumlari stderr'e yaziyor. Var mi yok mu
# kontrolleri $LASTEXITCODE ile yapilir.
$ErrorActionPreference = "Continue"

function Test-GcloudKaynak {
    <#
        gcloud komutunu calistirir ve kaynagin var olup olmadigini doner.
        Ciktiyi yutar: burada aranan sey bilgi degil, varlik.
    #>
    param([scriptblock]$Komut)
    & $Komut *> $null
    return $LASTEXITCODE -eq 0
}

$PROJECT = "rhytoai"
$REGION = "us-central1"
$SERVICE = "rytho-backend"
$SECRET = "NOTIFY_SCHEDULER_SECRET"

Write-Host "1/4 Servis adresi okunuyor..."
$URL = gcloud run services describe $SERVICE `
    --project $PROJECT --region $REGION --format "value(status.url)"
if (-not $URL) { throw "Servis adresi alinamadi." }
Write-Host "    $URL"

Write-Host "2/4 Gizli anahtar hazirlaniyor..."
$anahtarVar = Test-GcloudKaynak {
    gcloud secrets describe $SECRET --project $PROJECT
}
if ($env:RYTHO_ROTATE_SCHEDULER_SECRET -eq "1") {
    # Anahtari yenile: mevcut sirra yeni bir surum eklenir ve isler
    # asagida bu surumle guncellenir.
    Write-Host "    Anahtar dondurulecek (RYTHO_ROTATE_SCHEDULER_SECRET=1)."
    $anahtarVar = $false
}
if (-not $anahtarVar) {
    # 32 baytlik rastgele anahtar. Uretilen deger EKRANA YAZDIRILMAZ;
    # yalnizca Secret Manager'a ve zamanlayici isine gider.
    #
    # DIKKAT: RandomNumberGenerator::Fill .NET Framework'te (PowerShell 5.1)
    # YOKTUR. Cagrilirsa dizi sifir kalir ve anahtar tahmin edilebilir bir
    # degere ("AAAA...=") duser. Her iki surumde de calisan yol asagidaki.
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }

    # Uretilen anahtarin gercekten rastgele oldugunu dogrula: sessizce sifir
    # kalan bir anahtarla devam etmek, ucu korumasiz birakmak demek.
    if (($bytes | Where-Object { $_ -ne 0 }).Count -lt 16) {
        throw "Rastgele anahtar uretilemedi; islem durduruldu."
    }
    $deger = [Convert]::ToBase64String($bytes)

    $gecici = New-TemporaryFile
    try {
        # Anahtar dosyaya yazilir; komut satirina verilseydi surec listesinde
        # ve kabuk gecmisinde gorunurdu.
        [System.IO.File]::WriteAllText($gecici.FullName, $deger)
        $sirVar = Test-GcloudKaynak {
            gcloud secrets describe $SECRET --project $PROJECT
        }
        if ($sirVar) {
            gcloud secrets versions add $SECRET --project $PROJECT `
                --data-file $gecici.FullName
        } else {
            gcloud secrets create $SECRET --project $PROJECT `
                --replication-policy automatic --data-file $gecici.FullName
        }
    } finally {
        Remove-Item $gecici.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-Host "    Yeni anahtar olusturuldu."
} else {
    Write-Host "    Anahtar zaten var, korunuyor."
}

# Cloud Run'in calistigi servis hesabina okuma izni. Verilmezse deploy
# "Permission denied on secret" ile duser — sir var ama konteyner okuyamaz.
$PROJE_NO = gcloud projects describe $PROJECT --format "value(projectNumber)"
$SERVIS_HESABI = "$PROJE_NO-compute@developer.gserviceaccount.com"
gcloud secrets add-iam-policy-binding $SECRET --project $PROJECT `
    --member "serviceAccount:$SERVIS_HESABI" `
    --role "roles/secretmanager.secretAccessor" *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Servis hesabina sir okuma izni verilemedi."
}
Write-Host "    Servis hesabina okuma izni verildi."

$ANAHTAR = gcloud secrets versions access latest --secret $SECRET --project $PROJECT

Write-Host "3/4 Zamanlayici isleri kuruluyor..."
# Saatte bir, dakikanin 5'inde: gokyuzu onbelleginin tazelenmesi icin tam
# saatten birkac dakika sonra calisir.
$isler = @(
    @{ ad = "rytho-notify-daily";  tur = "daily";  cron = "5 * * * *" },
    # KA4: aksam check-in sorusu. Streak'ten (:10) ONCE kosar; ayni aksam
    # ikisinden yalniz biri gider (should_send'deki karsilikli koruma).
    @{ ad = "rytho-notify-checkin"; tur = "checkin"; cron = "8 * * * *" },
    # OB3: ogle olculu slotu (yerel 13:00) — yalniz gercekten olay olan
    # gunlerde gider; olaysiz gun sessizdir.
    @{ ad = "rytho-notify-midday"; tur = "midday"; cron = "12 * * * *" },
    @{ ad = "rytho-notify-streak"; tur = "streak"; cron = "10 * * * *" }
    # Sohbet arsivi temizligi (R4): 30 gundur kullanilmayan konusmalar.
    @{ ad = "rytho-cleanup"; uri = "/api/v1/maintenance/cleanup"; cron = "20 3 * * *" }
    # Admin istatistik toplama (W5): gecelik adminStats/{tarih} dokumani.
    # UTC gununun SONUNDA toplanir. Uc tarih parametresi almazsa BUGUNU
    # toplar ve gun penceresi [00:00, +1 gun) oldugu icin 02:40'taki eski
    # saat gunun yalniz ilk 2s40d'sini goruyordu: DAU ~0, gelir/AI/jeton
    # serileri bos. Kusur SESSIZ kaldi cunku rollupStale uyarisi generatedAt'e
    # bakiyor: dokuman TAZE sayilir, zil calmaz ve operator yanlis sayiyi
    # dogru sanip fiyat/maliyet karari verir.
    # 23:50 degil 23:40: gece yarisini GECEN bir tetik now().date()'i ertesi
    # gune tasir ve o gun HIC yazilmaz. Kalan 20 dakika YALNIZ sevk
    # gecikmesi ve kosu suresi payidir — yeniden deneme payi DEGIL: bu
    # betik islere `--max-retry-attempts` vermiyor, yani Cloud Scheduler
    # varsayilani (retryCount=0) geciyor ve dusen kosu bir sonraki gunu
    # bekler. Pay zaten dar: `--attempt-deadline 900s` tek basina 23:55'e
    # kadar surebilir.
    # Bedeli gunun son 20 dakikasi: gelir/olay bolumleri panelden "Yeniden
    # hesapla" ile geri doldurulabilir ama DAU (lastSeenDaily == gun)
    # KAPANMAZ.
    # Cleanup (03:20) ile SIRA DEGISTI, bunun tek gorunur etkisi soyle:
    # `stats_service._snapshot_users` icindeki `conversations` sayimi gun
    # penceresine bagli DEGIL, ANLIK bir toplam. Eski sirada (02:40)
    # fotograf o sabahki purge'den ONCE cekiliyordu; simdi ~20 saat SONRA
    # cekiliyor, yani `system.conversations` her gece silinen kadar dusuk
    # raporlanir. Kabul edildi: sayi artik "su anki gercek"e daha yakin.
    # Gunun OLAY bolumleri (gelir, AI, jeton) etkilenmiyor — onlarin
    # penceresi [00:00, +1 gun) ve purge'un sildigi sey 30 gundur
    # kullanilmayan konusmalar.
    @{ ad = "rytho-stats"; uri = "/api/v1/admin/collect"; cron = "40 23 * * *" }
    # Ortaklik hakedisi olgunlastirma (OP): satin almadan 15 gun sonra,
    # iade gelmediyse bekleyen hakedis KESINLESIR.
    #
    # Saat secimi onemsiz (gunde bir kez yeter, is dakikalar surmez) ama
    # stats (23:40) ve cleanup (03:20) ile CAKISMAYACAK sekilde secildi.
    #
    # Yukaridaki "yeniden deneme payi YOK" uyarisi bu is icin de gecerli;
    # fakat burada telafi SORGUNUN KENDISINE gomulu: is ">=15 gun olmus VE
    # hala beklemede" olanlari tariyor, yani kacirilan bir kosu ertesi gun
    # ayni kayitlari yine bulur. Tek bedeli hakedisin bir gun gec
    # kesinlesmesi — para kaybi yok.
    @{ ad = "rytho-partner-mature"; uri = "/api/v1/partners/mature"; cron = "30 2 * * *" }
)

foreach ($is in $isler) {
    if ($is.ContainsKey("uri")) {
        $uri = "$URL$($is.uri)"
    } else {
        $uri = "$URL/api/v1/notify/run?type=$($is.tur)"
    }
    $isVar = Test-GcloudKaynak {
        gcloud scheduler jobs describe $is.ad `
            --project $PROJECT --location $REGION
    }
    # Cikti YUTULUR: gcloud isin tanimini basiyor ve tanim Authorization
    # basligini icerdigi icin gizli anahtar ekrana ve kabuk gecmisine duserdi.
    if ($isVar) {
        Write-Host "    $($is.ad) guncelleniyor"
        gcloud scheduler jobs update http $is.ad `
            --project $PROJECT --location $REGION `
            --schedule "$($is.cron)" --time-zone "UTC" `
            --uri $uri --http-method POST `
            --update-headers "Authorization=$ANAHTAR" `
            --attempt-deadline 900s *> $null
    } else {
        Write-Host "    $($is.ad) olusturuluyor"
        gcloud scheduler jobs create http $is.ad `
            --project $PROJECT --location $REGION `
            --schedule "$($is.cron)" --time-zone "UTC" `
            --uri $uri --http-method POST `
            --headers "Authorization=$ANAHTAR" `
            --attempt-deadline 900s *> $null
    }
    if ($LASTEXITCODE -ne 0) {
        throw "$($is.ad) kurulamadi (cikis kodu $LASTEXITCODE)."
    }
}

Write-Host "4/4 Tamamlandi."
Write-Host ""
Write-Host "ONEMLI: Backend'i yeniden deploy etmeden anahtar konteynere"
Write-Host "gecmez ve uc 503 doner:"
Write-Host "  ./deploy-backend.ps1"
Write-Host ""
Write-Host "Elle tetiklemek icin:"
Write-Host "  gcloud scheduler jobs run rytho-notify-daily --project $PROJECT --location $REGION"

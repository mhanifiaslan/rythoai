r"""Android derleme sözleşmesi — hepsi SESSİZ bozulan şeyler (test_ios_config emsali).

Bu dosyadaki iddialar 2026-10-10'da Play Console'un iki uyarısından doğdu:

1. "DEX kodu optimizasyonu eşiğin altında — Optimizasyon %0" (son tarih
   Şubat 2027; görünürlük ve yayınlama olanaklarını etkiler). Ölçüldü:
   AAB'deki `BUNDLE-METADATA/com.android.tools/r8.json`
   `isOptimizationsEnabled: false`, `noOptimizationPercentage: 100.0`.
   Küçültme ve karartma AÇIKTI; optimizasyonu kapatan tek şey RevenueCat'in
   Amazon Appstore modülünün consumer kuralındaki `-dontoptimize` idi
   (R8 birleşik `configuration.txt:482`). Derleme BAŞARILI, testler yeşil,
   kusur yalnız Play'in ölçümünde görünüyordu.
   Onarım SONRASI ölçüldü (2026-10-10 19:53, AAB 1.19.0+49, R8 9.0.32):
   `isOptimizationsEnabled: true`, `noOptimizationPercentage: 37.53`,
   birleşik konfigürasyonda sıfır `-dontoptimize`. Kalan %37 `-keep`
   kurallarının tuttuğu sınıflar (Flutter/Firebase/RevenueCat), eşik %75.

2. "Uçtan uca ekran tüm kullanıcılara gösterilmeyebilir" (targetSdk 36).
   Davranış sürüme göre değişiyordu; `main()` artık her sürümde uçtan uca
   açıyor.

Çalıştırma:
    .venv\Scripts\python.exe -m pytest tests/test_android_build_config.py -q
"""
from __future__ import annotations

import pathlib
import re

_KOK = pathlib.Path(__file__).resolve().parents[2]
_MOBIL = _KOK / "apps" / "mobile"
_APP = _MOBIL / "android" / "app"

#: Optimizasyonu kapatan modül. Değişirse (RevenueCat paket adı) hem
#: build.gradle.kts hem bu sabit birlikte değişir.
AMAZON_MODUL = "com.revenuecat.purchases:purchases-store-amazon"


def _yorumsuz(metin: str, isaret: str) -> str:
    return "\n".join(s for s in metin.splitlines()
                     if not s.lstrip().startswith(isaret))


def test_amazon_modulunun_keep_kurallari_DISARIDA():
    """`keepRules { ignoreFrom(...) }` yoksa modülün `-dontoptimize`'ı yeniden
    birleşik konfigürasyona girer ve R8 optimizasyonu sessizce kapanır."""
    k = _yorumsuz((_APP / "build.gradle.kts").read_text(encoding="utf-8"), "//")
    assert f'ignoreFrom("{AMAZON_MODUL}")' in k, (
        "build.gradle.kts release bloğunda optimization.keepRules.ignoreFrom "
        f"({AMAZON_MODUL}) yok — Amazon modülünün -dontoptimize'ı geri gelir")


def test_amazon_modulunun_diger_kurallari_proguard_rules_pro_da():
    """Dışarıda bırakılan dosyanın `-dontoptimize` HARİÇ üç kuralı geri
    verilmeli: modül DEX'te duruyor, keep kuralı olmadan R8 onu yarım budar."""
    yol = _APP / "proguard-rules.pro"
    assert yol.exists(), "proguard-rules.pro yok — Flutter eklentisi onu varsa ekler"
    k = _yorumsuz(yol.read_text(encoding="utf-8"), "#")
    for kural in ("-dontwarn com.amazon.**", "-keep class com.amazon.** {*;}",
                  "-keepattributes *Annotation*"):
        assert kural in k, f"proguard-rules.pro'da eksik: {kural}"


def test_proguard_rules_pro_optimizasyonu_KAPATMAZ():
    """Tek bir -dontoptimize bütün uygulamanın optimizasyonunu kapatır;
    yorumlar atılarak aranır (bu dosya kuralı ANLATAN bir yorum taşıyor)."""
    k = _yorumsuz((_APP / "proguard-rules.pro").read_text(encoding="utf-8"), "#")
    for yasak in ("-dontoptimize", "-dontobfuscate", "-dontshrink"):
        assert yasak not in k, f"proguard-rules.pro {yasak} içeriyor"


def test_aab_kapisi_r8_json_u_okuyor():
    """Kaynak kuralı doğru olsa da başka bir kütüphane yarın -dontoptimize
    getirebilir; bunu yalnız ARTEFAKT söyler. infra/build-aab.ps1 altıncı
    kapı olarak r8.json'u okumalı."""
    k = _yorumsuz((_KOK / "infra" / "build-aab.ps1").read_text(encoding="utf-8"), "#")
    # Sözcüğün geçmesi yetmez — hata mesajında da geçiyor ve giriş yolu
    # bozulunca bekçi yeşil kalıyordu (mutasyon turunda ölçüldü). Çapa
    # gerçek okuma noktaları: zip girişinin tam yolu ve iki özellik okuması.
    assert '"BUNDLE-METADATA/com.android.tools/r8.json"' in k, (
        "build-aab.ps1 r8.json'u AAB'den tam yoluyla okumuyor")
    assert "$r8.options.isOptimizationsEnabled" in k
    assert "$r8.stats.noOptimizationPercentage" in k
    assert "-gt 75" in k, "Play eşiği (en fazla %75 optimize edilmemiş) betikte yok"


def test_main_uctan_uca_HER_surumde_aciyor():
    """targetSdk 36: Android 15+ zorluyor, altında değil — iki davranış tek
    cihaz testiyle ölçülemez. main() açıkça edgeToEdge kurar."""
    k = _yorumsuz((_MOBIL / "lib" / "main.dart").read_text(encoding="utf-8"), "//")
    assert "SystemUiMode.edgeToEdge" in k
    assert "systemNavigationBarContrastEnforced: false" in k


def test_manifest_uctan_ucadan_VAZGECMIYOR():
    """`windowOptOutEdgeToEdgeEnforcement` geçici bir kaçış; Google kaldıracak.
    Tasarım inset'leri zaten okuyor (glass.dart dock), vazgeçmeye gerek yok."""
    manifest = (_APP / "src" / "main" / "AndroidManifest.xml").read_text(encoding="utf-8")
    assert "windowOptOutEdgeToEdgeEnforcement" not in re.sub(r"<!--.*?-->", "", manifest, flags=re.S)
    for stil in (_APP / "src" / "main" / "res").rglob("styles.xml"):
        assert "windowOptOutEdgeToEdgeEnforcement" not in stil.read_text(encoding="utf-8"), stil

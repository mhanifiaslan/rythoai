import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Yükleme anahtarı (M1): android/key.properties git DIŞI, keystore C:\keys
// altında (repo dışı). Dosya yoksa release DEBUG anahtarına düşer —
// geliştirici makinesinde `flutter run --release` çalışmaya devam etsin;
// Play'e giden AAB'yi üreten makinede key.properties ZORUNLU (yanlış
// imzalı AAB'yi Play zaten reddeder).
val keyProps = Properties()
val keyPropsFile = rootProject.file("key.properties")
val releaseImzasiVar = keyPropsFile.exists()
if (releaseImzasiVar) {
    keyProps.load(FileInputStream(keyPropsFile))
}

android {
    namespace = "ai.rytho"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications, eski Android surumlerinde java.time
        // kullanabilmek icin core library desugaring istiyor. Acilmazsa
        // derleme "requires core library desugaring to be enabled" ile duser.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ai.rytho"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseImzasiVar) {
            create("release") {
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseImzasiVar) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 OPTIMIZASYONU (Play "DEX kodu optimizasyonu esigin altinda",
            // 2026-10-10). Olculdu: AAB'deki r8.json
            // `isOptimizationsEnabled: false`, `noOptimizationPercentage: 100`
            // diyordu — Play'in "%0" dedigi sey bu. Kucultme ve karartma
            // ACIKTI (Flutter eklentisi proguard-android-optimize.txt +
            // minify'i zaten kuruyor); optimizasyonu kapatan tek sey
            // RevenueCat'in Amazon Appstore modulunun consumer kurali
            // (purchases-store-amazon/proguard.txt: `-dontoptimize`). R8'de
            // TEK bir -dontoptimize butun uygulamanin optimizasyonunu kapatir.
            // Uygulama Amazon'da satilmiyor; o modulun kurallari disarida
            // birakilir, -dontoptimize HARIC uc kurali proguard-rules.pro'da
            // geri verilir (Amazon kodu hic kosmaz ama keep kurali kalsin).
            // Kapi: infra/build-aab.ps1 r8.json'u okur; test_android_build_config.py.
            // Onarim SONRASI olculdu (2026-10-10, R8 9.0.32): optimizasyon acik,
            // optimize edilmemis DEX %100 -> %37,53 (kalan -keep'li siniflar).
            optimization {
                keepRules {
                    ignoreFrom("com.revenuecat.purchases:purchases-store-amazon")
                }
            }
        }
    }
}

dependencies {
    // isCoreLibraryDesugaringEnabled ile birlikte zorunlu: desugaring
    // kutuphanesi olmadan bayrak tek basina ise yaramaz.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

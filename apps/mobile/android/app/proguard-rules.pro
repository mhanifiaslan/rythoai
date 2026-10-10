# Uygulamanin kendi R8 kurallari. Flutter eklentisi bu dosyayi, varsa,
# proguard-android-optimize.txt ve flutter_proguard_rules.pro'nun ARKASINA
# ekler (FlutterPlugin.kt:223-225). Bos degil diye var: asagidaki uc satir
# bir kutuphanenin disarida birakilan consumer kuralinin yerine gecer.

# RevenueCat Amazon Appstore modulu (purchases-store-amazon): consumer
# kurali `-dontoptimize` tasiyordu ve R8'de tek bir -dontoptimize BUTUN
# uygulamanin optimizasyonunu kapatiyordu (Play "DEX optimizasyonu %0",
# 2026-10-10, r8.json ile olculdu). build.gradle.kts o modulun kurallarini
# `keepRules { ignoreFrom(...) }` ile disarida birakiyor; modulun geri kalan
# uc kurali burada aynen duruyor. Uygulama Amazon'da satilmiyor, bu kod hic
# kosmaz — ama modul DEX'te durdugu surece keep kurali da dursun ki R8 onu
# yarim budamasin.
-dontwarn com.amazon.**
-keep class com.amazon.** {*;}
-keepattributes *Annotation*

# ⚠️ Bu dosyaya -dontoptimize / -dontobfuscate / -dontshrink YAZILMAZ:
# test_android_build_config.py bunu bagliyor.

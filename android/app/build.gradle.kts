plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.teddytales.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications считает время уведомлений через
        // java.time — на старых Android его даёт только desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Тот же идентификатор, что у iPhone-версии (BUNDLE_ID в codemagic.yaml).
        applicationId = "com.teddytales.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Ключ Google Play (КП 17.2). Codemagic кладёт его сам, когда в сборке
    // подключён `android_signing` (переменные CM_KEYSTORE_*). Нет ключа —
    // отладочная подпись, как раньше: APK для тестировщиков ставится
    // напрямую, без Google Play.
    val uploadKeystore = System.getenv("CM_KEYSTORE_PATH")
    signingConfigs {
        if (uploadKeystore != null) {
            create("upload") {
                storeFile = file(uploadKeystore)
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CM_KEY_ALIAS")
                keyPassword = System.getenv("CM_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (uploadKeystore != null) "upload" else "debug",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

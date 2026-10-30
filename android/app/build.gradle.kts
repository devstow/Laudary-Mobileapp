import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (git-ignored, see key.properties.example) names the
// keystore + passwords. Every public build (sideloaded APK today, Play Store later) MUST use the
// same key so Android treats a new version as an update of the installed app.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// The --dart-define values Flutter passes to Gradle (base64, comma separated). API_BASE_URL is exposed to the native
// side as R.string.sw_api_base_url so a crash during process start can still be reported (SmartWashApplication).
val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as String?).orEmpty()
    .split(",").filter { it.isNotBlank() }
    .mapNotNull { runCatching { String(Base64.getDecoder().decode(it)) }.getOrNull() }
    .mapNotNull { d -> d.indexOf('=').takeIf { it > 0 }?.let { d.substring(0, it) to d.substring(it + 1) } }
    .toMap()

android {
    namespace = "com.example.mobileapp"
    compileSdk = flutter.compileSdkVersion
    // Use the NDK already installed on this machine to avoid Gradle
    // auto-downloading a corrupt copy of flutter.ndkVersion (28.2.13676358).
    ndkVersion = "30.0.15729638"

    // Compress native libraries inside the APK (extracted at install time). The universal APK carries the
    // Flutter engine + app for arm64, armv7 and x86_64; stored uncompressed that is a ~54 MB download, which
    // is what truncates on slow mobile data and then fails with "App not installed". Compressed it is about
    // half. Extracted libraries also work on 16 KB-page devices (Android 15+).
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Keep this id stable: changing it turns every future build into a different app that
        // cannot update an existing installation (users would have to uninstall first).
        applicationId = "com.cyberstackmedia.smartwash"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Version + build number come from pubspec.yaml ("version: x.y.z+n") — the single source.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "sw_api_base_url", dartDefines["API_BASE_URL"] ?: "")
    }

    buildFeatures {
        resValues = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                // v2 + v3 (v3 allows future key rotation). v1 is requested too but AGP omits it because
                // minSdk is 24 (Android 7+ verifies v2), so apksigner reports v1=false — expected.
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        // Debug builds (flutter run) get their OWN application id so a developer's phone can hold the
        // debug-key-signed dev build AND the sideloaded release side by side. Without this, a leftover
        // debug install (same id, different key) makes the release APK fail with "App not installed".
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-dev"
            // Label "Smart Wash (dev)" comes from src/debug/res/values/strings.xml.
        }
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // No key.properties → debug key so `flutter run --release` still works locally.
                // tool/build_release_apk.ps1 refuses to produce a distributable APK in this state.
                logger.warn("WARNING: android/key.properties not found — release build is signed with the DEBUG key and must not be distributed.")
                signingConfig = signingConfigs.getByName("debug")
            }
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
    // Background unread-badge sync while the app is closed (AppNotifications.kt / BadgeSyncWorker).
    implementation("androidx.work:work-runtime-ktx:2.10.1")
}

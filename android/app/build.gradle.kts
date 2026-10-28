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

android {
    namespace = "com.example.mobileapp"
    compileSdk = flutter.compileSdkVersion
    // Use the NDK already installed on this machine to avoid Gradle
    // auto-downloading a corrupt copy of flutter.ndkVersion (28.2.13676358).
    ndkVersion = "30.0.15729638"

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

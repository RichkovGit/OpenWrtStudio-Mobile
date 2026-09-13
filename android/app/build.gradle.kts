import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cogwheel.LuCIMobile"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.cogwheel.LuCIMobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val defaultKeystore = file("openwrt_studio_release.jks")
    val rawStoreFile = keystoreProperties.getProperty("storeFile", "")
    val resolvedStoreFile = when {
        rawStoreFile.isNotEmpty() && file(rawStoreFile).exists() -> file(rawStoreFile)
        rawStoreFile.isNotEmpty() && rootProject.file(rawStoreFile).exists() -> rootProject.file(rawStoreFile)
        rawStoreFile.isNotEmpty() && rootProject.file("app/$rawStoreFile").exists() -> rootProject.file("app/$rawStoreFile")
        defaultKeystore.exists() -> defaultKeystore
        else -> null
    }
    val hasReleaseKeystore = resolvedStoreFile != null && resolvedStoreFile.exists()

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = resolvedStoreFile
                storePassword = keystoreProperties.getProperty("storePassword", "openwrtstudio")
                keyAlias = keystoreProperties.getProperty("keyAlias", "openwrtstudio")
                keyPassword = keystoreProperties.getProperty("keyPassword", "openwrtstudio")
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        getByName("debug") {
            // Debug builds use the default debug signing config
            // No custom keystore required for debug builds
        }
    }

    dependenciesInfo {
        // Disables dependency metadata when building APKs (for IzzyOnDroid/F-Droid)
        includeInApk = false
        // Disables dependency metadata when building Android App Bundles (for Google Play)
        includeInBundle = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

dependencies {
    implementation("androidx.core:core:1.12.0")
    implementation("androidx.activity:activity:1.8.2")
}

flutter {
    source = "../.."
}

import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use { signingProperties.load(it) }
    require(listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
        !signingProperties.getProperty(it).isNullOrBlank()
    }) { "key.properties must provide storeFile, storePassword, keyAlias and keyPassword" }
}

android {
    namespace = "com.finora.fintech"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        applicationId = "com.finora.fintech"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 1.31: 64-bit ARM only (all current phones, the owner's Samsung
        // A56 included): the offline speech model makes a universal APK too
        // big for one release file.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }
    signingConfigs {
        if (signingPropertiesFile.exists()) {
            create("release") {
                storeFile = rootProject.file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }
    // 1.31: only 64-bit ARM native libraries go into the APK.
    packaging {
        jniLibs {
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86_64/**", "lib/x86/**")
        }
    }
    buildTypes {
        release {
            if (signingPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            // With no local signing setup, output is unsigned, never debug-signed.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
    implementation("androidx.exifinterface:exifinterface:1.4.1")
    // 1.31: Finora's own offline, silent speech recognition (Vosk, Apache-2.0;
    // Russian small model in assets/model-ru).
    implementation("com.alphacephei:vosk-android:0.3.47")
    implementation("net.java.dev.jna:jna:5.13.0@aar")
    // Developer-only on-device OCR check (not part of the release APK).
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

flutter {
    source = "../.."
}

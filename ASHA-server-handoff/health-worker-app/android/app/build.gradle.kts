import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: put the upload keystore details in android/key.properties (NOT committed; see DEPLOY notes). Without that file the
// release build falls back to the debug key so local `flutter run --release` still works, but such an APK must never be distributed.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProps.getProperty("storeFile") != null

android {
    namespace = "in.healthcompanion.health_companion"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "in.healthcompanion.health_companion"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    // Release builds leave out the x86 / x86_64 (emulator-only) native libraries: ONNX Runtime alone is 41 MB there. Build the phone APKs with
    //   flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
    // which makes one small APK per phone type (64-bit about 56 MB, 32-bit about 42 MB) instead of one 100 MB APK holding both.
    if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) {
        packaging { jniLibs { excludes += listOf("lib/x86_64/**", "lib/x86/**") } }
    }

    buildTypes {
        release {
            // real phones today are 64-bit ARM: leaving out the 32-bit ARM and x86 (emulator) copies of the native libraries (ONNX Runtime
            // alone is 24 + 41 MB there) takes the APK from about 139 MB to about 57 MB
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            if (!hasReleaseKey) println("WARNING: android/key.properties not found - the release APK is signed with the DEBUG key. Do not distribute it.")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // offline Telugu speech recognition (TeluguAsr.kt); runs the model on the phone
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.31.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 让产出的 APK 文件名前缀为软件名（NexHub-arm64-v8a-release.apk 而非 app-*.apk）。
// 注意：archivesBaseName 是 project 级属性，Kotlin DSL 中不能在 defaultConfig 内直接赋值，
// 必须用 project.setProperty 在顶层设置（Groovy DSL 才允许写在 defaultConfig 里）。
project.setProperty("archivesBaseName", "NexHub")

android {
    namespace = "com.nexhub.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nexhub.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // super_clipboard（复制图片）要求 minSdk >= 23；flutter_tts 要求 minSdk >= 24。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

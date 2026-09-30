import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// リリース署名（アップロード鍵）。android/key.properties から読む（Git 非コミット）。
// 鍵が無い環境では debug 署名へ落として開発ビルドを壊さないが、
// 公開用の bundleRelease / assembleRelease は下のガードで明示的に失敗させる。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.amkn.aori_shogi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.amkn.aori_shogi"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // アップロード鍵があれば本番署名（Play App Signing 前提）、無ければ debug。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "WARNING: android/key.properties が無いため release は debug 署名です" +
                        "（公開不可・ローカル検証専用）。",
                )
                signingConfigs.getByName("debug")
            }
            // R8 は入れない。flutter_gemma と FFI の keep ルールを詰めていないため、
            // 初版では縮小より確実に動くことを優先する（DEP: 次版で検討）。
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

flutter {
    source = "../.."
}

// 公開用 release 成果物は本番署名鍵を必須にする（debug 鍵で公開する事故を防ぐ）。
tasks.matching { it.name == "bundleRelease" || it.name == "assembleRelease" }
    .configureEach {
        doFirst {
            if (!hasReleaseSigning) {
                throw GradleException(
                    "公開用 release ビルドには android/key.properties（本番署名鍵）が必須です。",
                )
            }
        }
    }

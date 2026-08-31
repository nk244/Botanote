import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// key.properties からリリース署名情報を読み込む
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.inputStream())
}

android {
    namespace = "com.example.bota_note"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.bota_note"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String?
            keyPassword = keyProperties["keyPassword"] as String?
            storeFile = keyProperties["storeFile"]?.let { file(it as String) }
            storePassword = keyProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // key.properties が存在すればリリース署名、なければデバッグ署名にフォールバック
            signingConfig = if (keyPropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")

            // リソース縮小を無効にする。
            //
            // 通知アイコン ic_notification は Dart 側の文字列からしか参照されず
            // （lib/services/notification_service.dart の '@drawable/ic_notification'）、
            // flutter_local_notifications が実行時に名前でリソースを解決する。
            // 縮小が有効だとこの drawable が未使用と判定されて削除・名前変更されるため、
            // リリースビルドでのみ PlatformException(invalid_icon) が発生し、
            // 水やりリマインダーが動かず、通知の再スケジュールを伴うインポートも失敗する。
            // res/raw/keep.xml では防ぎきれなかったため、縮小自体を止める。
            // コード縮小（R8）は有効なままにする。
            isShrinkResources = false
        }
    }

    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    }
}

flutter {
    source = "../.."
}

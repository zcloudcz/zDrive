plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cz.zcloud.zdrive_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cz.zcloud.zdrive_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseSigningValues = mapOf(
        "ZDRIVE_ANDROID_KEYSTORE_PATH" to System.getenv("ZDRIVE_ANDROID_KEYSTORE_PATH"),
        "ZDRIVE_ANDROID_KEYSTORE_PASSWORD" to System.getenv("ZDRIVE_ANDROID_KEYSTORE_PASSWORD"),
        "ZDRIVE_ANDROID_KEY_ALIAS" to System.getenv("ZDRIVE_ANDROID_KEY_ALIAS"),
        "ZDRIVE_ANDROID_KEY_PASSWORD" to System.getenv("ZDRIVE_ANDROID_KEY_PASSWORD"),
    )
    val missingReleaseSigningValues = releaseSigningValues
        .filterValues { it.isNullOrBlank() }
        .keys
    val releaseTaskRequested = gradle.startParameter.taskNames.any {
        it.contains("release", ignoreCase = true)
    }

    if (releaseTaskRequested && missingReleaseSigningValues.isNotEmpty()) {
        throw GradleException(
            "Android release signing is not configured. Set: " +
                missingReleaseSigningValues.joinToString(", "),
        )
    }

    if (missingReleaseSigningValues.isEmpty()) {
        signingConfigs {
            create("release") {
                storeFile = file(releaseSigningValues.getValue("ZDRIVE_ANDROID_KEYSTORE_PATH"))
                storePassword = releaseSigningValues.getValue("ZDRIVE_ANDROID_KEYSTORE_PASSWORD")
                keyAlias = releaseSigningValues.getValue("ZDRIVE_ANDROID_KEY_ALIAS")
                keyPassword = releaseSigningValues.getValue("ZDRIVE_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            if (missingReleaseSigningValues.isEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

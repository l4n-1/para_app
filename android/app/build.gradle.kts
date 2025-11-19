plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") // ✅ Google Services plugin
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.para2"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.para2"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug") // Replace with release config later
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Firebase BoM (Bill of Materials) - manages versions for Firebase libraries
    implementation(platform("com.google.firebase:firebase-bom:33.0.0"))

    // ✅ Firebase core dependencies
    implementation("com.google.firebase:firebase-analytics")
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.23")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
    // ✅ Add these if you use them in Flutter:
    // implementation("com.google.firebase:firebase-auth")
    // implementation("com.google.firebase:firebase-firestore")
    // implementation("com.google.firebase:firebase-database")
    // implementation("com.google.firebase:firebase-messaging")
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.checkpoint.vpn.oneclick"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.checkpoint.vpn.oneclick"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Sideload v1: sign with the debug keystore (no Play Store upload).
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            isDebuggable = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.datastore:datastore-preferences:1.1.1")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.camera:camera-camera2:1.4.1")
    implementation("androidx.camera:camera-lifecycle:1.4.1")
    implementation("androidx.camera:camera-view:1.4.1")
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
    testImplementation("junit:junit:4.13.2")
}

fun cargoNdkAvailable(): Boolean {
    val cargo = System.getenv("CARGO") ?: "cargo"
    return try {
        ProcessBuilder(cargo, "ndk", "--version").start().waitFor() == 0
    } catch (_: Exception) {
        false
    }
}

tasks.register<Exec>("buildNativeEngine") {
    group = "build"
    description = "Build snxcore JNI shared library with cargo-ndk"
    workingDir = rootProject.file("engine")
    val sdkDir = System.getenv("ANDROID_HOME")
        ?: System.getenv("ANDROID_SDK_ROOT")
        ?: rootProject.file(".sdk").absolutePath
    val ndkVersion = "27.2.12479018"
    // Device default: arm64 only. Set ANDROID_NATIVE_ABIS=arm64-v8a,x86_64 for emulator too.
    val abis = (System.getenv("ANDROID_NATIVE_ABIS") ?: "arm64-v8a")
        .split(',')
        .map { it.trim() }
        .filter { it.isNotEmpty() }
    environment("ANDROID_HOME", sdkDir)
    environment("ANDROID_SDK_ROOT", sdkDir)
    environment("ANDROID_NDK_HOME", "$sdkDir/ndk/$ndkVersion")
    val cmd = mutableListOf("cargo", "ndk")
    abis.forEach { abi ->
        cmd += listOf("-t", abi)
    }
    cmd += listOf(
        "-o", "../app/src/main/jniLibs",
        "build", "--release",
        "--features", "snxcore",
    )
    commandLine(cmd)
    // Skip cargo when .so is newer than engine/snxcore sources (make apk feels fast again).
    inputs.files(
        fileTree(rootProject.file("engine")) {
            include("Cargo.toml", "Cargo.lock", "src/**/*.rs")
        },
        fileTree(rootProject.file("../Vendor/snx-rs/crates/snxcore")) {
            include("Cargo.toml", "src/**/*.rs")
        },
    )
    outputs.files(
        abis.map { rootProject.file("app/src/main/jniLibs/$it/libcheckpoint_engine.so") },
    )
    onlyIf { cargoNdkAvailable() && file("$sdkDir/ndk/$ndkVersion").exists() }
}

tasks.named("preBuild").configure {
    dependsOn("buildNativeEngine")
}

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// Clave de firma de release: la CI la decodifica desde los secretos de GitHub
// (ver docs/RELEASING.md). Sin ella, el build de release usa la clave de depuración.
val releaseKeystore: String? = System.getenv("ANDROID_KEYSTORE_PATH")

android {
    namespace = "app.libremusic"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.libremusic"
        minSdk = 26
        targetSdk = 35
        // Versión de la app (ver docs/RELEASING.md). versionCode siempre sube.
        versionCode = 21
        versionName = "1.2.0"
    }

    // Tres apps con el mismo código (Fase 1 de la 1.0). Lo que cambia entre ellas son estas banderas de
    // BuildConfig, nunca código duplicado. Ver docs/FLAVORS.md.
    //  - usr: la pública (web, GitHub). Mismo applicationId de siempre para actualizar encima.
    //  - pref: la de Toxbox. Estable, sin herramientas de administración.
    //  - dev: pruebas y administración (panel, botón de pánico, registro detallado).
    // dev y pref sólo se instalan por adb en el móvil de Toxbox: no se publican nunca.
    flavorDimensions += "canal"
    productFlavors {
        create("usr") {
            dimension = "canal"
            buildConfigField("String", "CHANNEL", "\"usr\"")
            buildConfigField("boolean", "ADMIN_TOOLS", "false")
            buildConfigField("boolean", "VERBOSE_LOGS", "false")
        }
        create("pref") {
            dimension = "canal"
            applicationIdSuffix = ".pref"
            versionNameSuffix = "-pref"
            buildConfigField("String", "CHANNEL", "\"pref\"")
            buildConfigField("boolean", "ADMIN_TOOLS", "false")
            buildConfigField("boolean", "VERBOSE_LOGS", "false")
        }
        create("dev") {
            dimension = "canal"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            buildConfigField("String", "CHANNEL", "\"dev\"")
            buildConfigField("boolean", "ADMIN_TOOLS", "true")
            buildConfigField("boolean", "VERBOSE_LOGS", "true")
        }
    }

    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (releaseKeystore != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        // Como la release (R8, sin depuración) pero instalable al lado: para medir fluidez y tiempos.
        create("perf") {
            initWith(getByName("release"))
            applicationIdSuffix = ".perf"
            versionNameSuffix = "-perf"
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }


    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests {
            // Capturas de pantalla con Robolectric + Roborazzi (ScreenshotTest).
            isIncludeAndroidResources = true
            all { it.systemProperty("roborazzi.test.record", "true") }
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.guava)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.exoplayer.hls)
    implementation(libs.androidx.media3.session)

    // Barra estilo SimpMusic: vidrio de Kyant y el plegado de SimpMusic 2.2.0 (ConstraintLayout).
    implementation(libs.kyant.backdrop)
    implementation(libs.androidx.constraintlayout.compose)

    implementation(libs.okhttp)
    implementation(libs.bouncycastle)
    implementation(libs.androidx.work.runtime.ktx)
    implementation(libs.coil.compose)

    // QR del Jam: generar (core) y escanear (embedded)
    implementation(libs.zxing.core)
    implementation(libs.zxing.embedded)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    // Implementación real de org.json para los tests de JVM (en Android la da el sistema)
    testImplementation(libs.org.json)
}

// AGP 9 trae Kotlin integrado: el destino de la JVM va aquí y no en android { kotlinOptions }.
kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// AGP y los plugins de Kotlin están en el classpath del buildscript raíz (ver ../build.gradle.kts).
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    // PLACEHOLDER: namespace/applicationId provisionales hasta que exista identidad de publicación.
    namespace = "org.caminoseguro.watch"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "org.caminoseguro.watch"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        debug {
            // Debug: MockCaminoApi (src/debug/.../ApiModule.kt) — la UI muestra "DEMO".
        }
        release {
            // Release: BlockedCaminoApi (src/release/.../ApiModule.kt). Sin firma en V1 (APK unsigned en CI).
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = false
    }

    sourceSets {
        // Fixtures compartidas (DATOS DE DEMOSTRACIÓN) empaquetadas como assets sin copiarlas.
        getByName("main").assets.srcDir(rootProject.file("../shared/fixtures"))
    }

    lint {
        abortOnError = true
        warningsAsErrors = false
        checkDependencies = false
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core"))

    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)

    implementation(libs.androidx.wear.compose.material)
    implementation(libs.androidx.wear.compose.foundation)
    implementation(libs.androidx.wear.compose.navigation)

    testImplementation(libs.junit)
}

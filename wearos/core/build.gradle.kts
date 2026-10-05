import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.kotlin.plugin.serialization")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    api(libs.kotlinx.coroutines.core)
    api(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}

// Los tests de conformidad leen los vectores compartidos directamente de ../shared.
val sharedDir = rootProject.layout.projectDirectory.dir("../shared")

tasks.test {
    systemProperty("camino.conformanceDir", sharedDir.dir("conformance").asFile.absolutePath)
    systemProperty("camino.fixturesDir", sharedDir.dir("fixtures").asFile.absolutePath)
    inputs.dir(sharedDir.dir("conformance")).withPropertyName("conformanceVectors").withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(sharedDir.dir("fixtures")).withPropertyName("fixtures").withPathSensitivity(PathSensitivity.RELATIVE)
    testLogging {
        events("failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}

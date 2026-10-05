// Los plugins se cargan en el classpath del buildscript raíz para que AGP y el plugin de
// Kotlin compartan classloader. AGP (y el plugin de Compose) sólo se añaden si :app está
// incluido (coreOnly != true), así un entorno sin Google Maven puede compilar y testear :core.
buildscript {
    val coreOnly = providers.gradleProperty("coreOnly").orNull == "true"
    repositories {
        if (!coreOnly) {
            google {
                content {
                    includeGroupByRegex("com\\.android.*")
                    includeGroupByRegex("com\\.google.*")
                    includeGroupByRegex("androidx.*")
                }
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
    dependencies {
        classpath(libs.kotlin.gradlePlugin)
        classpath(libs.kotlin.serializationGradlePlugin)
        if (!coreOnly) {
            classpath(libs.android.gradlePlugin)
            classpath(libs.kotlin.composeGradlePlugin)
        }
    }
}

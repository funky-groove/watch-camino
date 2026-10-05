// Camino Seguro Watch — Wear OS
//
// -PcoreOnly=true  → sólo se incluye :core (Kotlin/JVM puro). Sirve para entornos sin
// Android SDK ni acceso a Google Maven: no se resuelve AGP ni ninguna dependencia androidx.
pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
    }
}

rootProject.name = "camino-seguro-wear"

include(":core")

val coreOnly = providers.gradleProperty("coreOnly").orNull == "true"
if (!coreOnly) {
    include(":app")
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// mapbox_maps_flutter's build script only applies the Kotlin plugin itself on
// AGP < 9. This project runs AGP 9 with android.builtInKotlin=false (Flutter
// template), so apply it here before the plugin's script evaluates.
// mapbox_maps_flutter ships the NDK 27 flavour of the Maps SDK (android-ndk27
// 11.31.1) while flutter_mapbox pulls the plain flavour through the Navigation
// SDK. Both flavours share Android namespaces, so the merge fails. Mapbox
// publishes every navigation artifact as -ndk27 too: resolve everything to
// that flavour and let Gradle pick the newest version of each module.
subprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            val g = requested.group
            val n = requested.name
            if (n.endsWith("-ndk27")) return@eachDependency
            when (g) {
                "com.mapbox.navigationcore" -> useTarget("$g:$n-ndk27:${requested.version ?: "3.23.0"}")
                "com.mapbox.maps", "com.mapbox.plugin", "com.mapbox.extension", "com.mapbox.module" -> useTarget("$g:$n-ndk27:11.31.1")
                "com.mapbox.common" -> if (n == "common") useTarget("$g:common-ndk27:24.31.1")
            }
        }
    }
}

subprojects {
    if (name == "mapbox_maps_flutter") {
        plugins.apply("org.jetbrains.kotlin.android")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.variant.LibraryAndroidComponentsExtension

plugins {
    id("com.android.application") apply false
}

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
    if (name == "jni") {
        pluginManager.withPlugin("com.android.library") {
            val appAndroid = project(":app").extensions.getByType<ApplicationExtension>()
            extensions.getByType<LibraryAndroidComponentsExtension>().finalizeDsl { library ->
                library.compileSdk = appAndroid.compileSdk
                library.ndkVersion = appAndroid.ndkVersion
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

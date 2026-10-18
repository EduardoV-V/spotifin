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
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            val current = androidExt.compileSdkVersion
            if (current != null) {
                val versionNum = current.removePrefix("android-").toIntOrNull()
                if (versionNum != null && versionNum < 36) {
                    logger.warn(
                        "Ajustando compileSdk do plugin '${project.name}': $current → 36"
                    )
                    androidExt.compileSdkVersion(36)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
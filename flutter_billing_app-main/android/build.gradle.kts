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

// Normalize old Flutter plugins (e.g. flutter_vibrate 1.3.0) that hard-code Java
// 1.8 and an old compileSdk. AGP 8 / Kotlin 2 reject the JVM-target mismatch, and
// a compileSdk < 31 fails resource linking (android:attr/lStar not found). Force
// every Android library module to compileSdk 35 + Java 17. Configured on the
// android extension (what AGP reads) via plugins.withId, which fires even though
// the subprojects above are already evaluated.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            compileSdk = 35
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
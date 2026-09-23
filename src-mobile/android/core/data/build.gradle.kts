import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Persistence on plain java.nio, so the tests run against a real file system on the JVM.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    api(project(":core:domain"))
    api(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}

tasks.test {
    // The synthetic v1–v6 archives double as seed data.
    val archives = rootProject.file("../../docs/android/synthetic-archives")
    inputs.dir(archives)
    systemProperty("owc.syntheticArchives", archives.absolutePath)
}

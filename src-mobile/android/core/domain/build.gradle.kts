import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Pure JVM: no android.*, Room, Compose or Billing (docs/agent-guides/android.md).
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
    testImplementation(libs.junit)
}

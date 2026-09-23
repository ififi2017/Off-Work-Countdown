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
    // JSON parsing only (no compiler plugin): the bundled holiday calendar.
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
}

tasks.test {
    // The holiday dataset is shared with iOS rather than copied.
    val holidays = rootProject.file("../ios/Shared/Resources/HolidayTemplates.json")
    inputs.file(holidays)
    systemProperty("owc.holidayTemplates", holidays.absolutePath)
}

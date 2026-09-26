plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.rainif.doneat"
    compileSdk = 37

    defaultConfig {
        // Candidate identity (D-10); frozen before the first Play upload.
        applicationId = "com.rainif.doneat"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "3.2.0"
        // Public Play configuration only. Empty values keep the store unavailable.
        val plusProduct = providers.gradleProperty("doneatPlusSubscriptionProduct").orElse("").get()
        val lifetimeProduct = providers.gradleProperty("doneatPlusLifetimeProduct").orElse("").get()
        val monthlyBasePlan = providers.gradleProperty("doneatPlusMonthlyBasePlan").orElse("").get()
        val yearlyBasePlan = providers.gradleProperty("doneatPlusYearlyBasePlan").orElse("").get()
        val playKey = providers.gradleProperty("doneatPlayBillingPublicKey").orElse("").get()
        buildConfigField("String", "PLUS_SUBSCRIPTION_PRODUCT", "\"$plusProduct\"")
        buildConfigField("String", "PLUS_LIFETIME_PRODUCT", "\"$lifetimeProduct\"")
        buildConfigField("String", "PLUS_MONTHLY_BASE_PLAN", "\"$monthlyBasePlan\"")
        buildConfigField("String", "PLUS_YEARLY_BASE_PLAN", "\"$yearlyBasePlan\"")
        buildConfigField("String", "PLAY_BILLING_PUBLIC_KEY", "\"$playKey\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    bundle {
        // The app switches language itself (per-app language); every language must ship in every install.
        language { enableSplit = false }
    }

    sourceSets {
        // The holiday calendar and its attributions, shared with iOS rather than copied.
        getByName("main").assets.directories.add("../../ios/Shared/Resources")
    }
}

dependencies {
    implementation(project(":core:domain"))
    implementation(project(":core:data"))
    implementation(project(":core:designsystem"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3.navigation.suite)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.kotlinx.serialization.json)
    // Owner confirmation before earnings are revealed; hosts BiometricPrompt, so MainActivity is a FragmentActivity.
    implementation(libs.androidx.biometric)
    implementation(libs.androidx.fragment)
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.play.billing)
    implementation(libs.play.review)
    implementation(libs.androidx.work.runtime.ktx)
    debugImplementation(libs.androidx.compose.ui.tooling)
    testImplementation(libs.junit)
}

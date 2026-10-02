plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.rainif.doneat"
    compileSdk = 37

    defaultConfig {
        // Registered in Play Console for the first internal test release.
        applicationId = "com.rainif.doneat"
        minSdk = 26
        targetSdk = 36
        // Play uploads need a higher code each time; the release workflow passes one in.
        versionCode = providers.gradleProperty("doneatVersionCode").orNull?.toInt() ?: 5
        versionName = "3.2.1"
        // Public Play configuration only. Empty values keep the store unavailable.
        val plusProduct = providers.gradleProperty("doneatPlusSubscriptionProduct").orElse("").get()
        val lifetimeProduct = providers.gradleProperty("doneatPlusLifetimeProduct").orElse("").get()
        val monthlyBasePlan = providers.gradleProperty("doneatPlusMonthlyBasePlan").orElse("").get()
        val yearlyBasePlan = providers.gradleProperty("doneatPlusYearlyBasePlan").orElse("").get()
        val yearlyTrial = providers.gradleProperty("doneatPlusYearlyTrialOffer").orElse("").get()
        val lifetimeOption = providers.gradleProperty("doneatPlusLifetimePurchaseOption").orElse("").get()
        val playKey = providers.gradleProperty("doneatPlayBillingPublicKey").orElse("").get()
        buildConfigField("String", "PLUS_SUBSCRIPTION_PRODUCT", "\"$plusProduct\"")
        buildConfigField("String", "PLUS_LIFETIME_PRODUCT", "\"$lifetimeProduct\"")
        buildConfigField("String", "PLUS_MONTHLY_BASE_PLAN", "\"$monthlyBasePlan\"")
        buildConfigField("String", "PLUS_YEARLY_BASE_PLAN", "\"$yearlyBasePlan\"")
        buildConfigField("String", "PLUS_YEARLY_TRIAL_OFFER", "\"$yearlyTrial\"")
        buildConfigField("String", "PLUS_LIFETIME_PURCHASE_OPTION", "\"$lifetimeOption\"")
        buildConfigField("String", "PLAY_BILLING_PUBLIC_KEY", "\"$playKey\"")
    }

    // Play upload key, supplied by the release workflow or an untracked local gradle.properties.
    // Without it the release output stays unsigned, as before.
    val uploadStoreFile = providers.gradleProperty("doneatUploadStoreFile").orNull
    signingConfigs {
        if (uploadStoreFile != null) {
            create("upload") {
                storeFile = file(uploadStoreFile)
                storePassword = providers.gradleProperty("doneatUploadStorePassword").get()
                keyAlias = providers.gradleProperty("doneatUploadKeyAlias").get()
                keyPassword = providers.gradleProperty("doneatUploadKeyPassword").get()
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    testImplementation(libs.kotlinx.coroutines.test)
}

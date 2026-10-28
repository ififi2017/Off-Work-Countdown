import java.util.Properties
import java.security.KeyFactory
import java.security.interfaces.RSAPublicKey
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import groovy.json.JsonSlurper

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

val cnDebugProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val cnChannel = providers.gradleProperty("doneatChannel").orElse("play").get() == "cn"
fun quoted(value: String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
val cnKeys = providers.gradleProperty("doneatCnLicensePublicKeys").orElse("").get()
val cnAudience = providers.gradleProperty("doneatCnLicenseAudience").orElse("").get()

android {
    namespace = "com.rainif.doneat"
    compileSdk = 37

    defaultConfig {
        // Registered in Play Console for the first internal test release.
        applicationId = if (cnChannel) "com.rainif.doneat.cn" else "com.rainif.doneat"
        buildConfigField("boolean", "CN_CHANNEL", cnChannel.toString())
        buildConfigField("String", "CN_LICENSE_PUBLIC_KEYS", quoted(cnKeys))
        buildConfigField("String", "CN_LICENSE_AUDIENCE", quoted(cnAudience))
        buildConfigField("String", "CN_LICENSE_API", quoted("https://api.doneat.com.cn"))
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
        // Public receipt verification keys (kid -> base64 DER/SPKI). Empty keeps the existing client-only path.
        val receiptKeys = providers.gradleProperty("doneatBillingApiPublicKeys").orElse("").get()
        val escapedReceiptKeys = receiptKeys.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")
        buildConfigField("String", "BILLING_API_PUBLIC_KEYS", "\"$escapedReceiptKeys\"")
    }

    // Play upload key, supplied by the release workflow or an untracked local gradle.properties.
    // Read leniently: tests and debug builds configure this script too and must not need it.
    // Without all four values the release output stays unsigned; the release workflow
    // verifies the AAB's signature, so a missing secret fails there, not here.
    val uploadStoreFile = providers.gradleProperty(if (cnChannel) "doneatCnUploadStoreFile" else "doneatUploadStoreFile").orNull
    val uploadStorePassword = providers.gradleProperty(if (cnChannel) "doneatCnUploadStorePassword" else "doneatUploadStorePassword").orNull
    val uploadKeyAlias = providers.gradleProperty(if (cnChannel) "doneatCnUploadKeyAlias" else "doneatUploadKeyAlias").orNull
    val uploadKeyPassword = providers.gradleProperty(if (cnChannel) "doneatCnUploadKeyPassword" else "doneatUploadKeyPassword").orNull
    signingConfigs {
        if (uploadStoreFile != null && uploadStorePassword != null && uploadKeyAlias != null && uploadKeyPassword != null) {
            create("upload") {
                storeFile = file(uploadStoreFile)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            if (cnChannel) {
                applicationIdSuffix = ".debug"
                buildConfigField("String", "CN_LICENSE_PUBLIC_KEYS", quoted(cnDebugProperties.getProperty("doneatCnDebugPublicKeys", cnKeys)))
                buildConfigField("String", "CN_LICENSE_AUDIENCE", quoted(cnDebugProperties.getProperty("doneatCnDebugAudience", cnAudience)))
            }
            buildConfigField("String", "CN_LICENSE_API", quoted(if (cnChannel) providers.gradleProperty("doneatCnLicenseDebugUrl").orElse(cnDebugProperties.getProperty("doneatCnDebugUrl", "https://api.doneat.com.cn")).get() else "https://api.doneat.com.cn"))
        }
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
        getByName("main").kotlin.directories.add(if (cnChannel) "src/cn/kotlin" else "src/play/kotlin")
        getByName("test").kotlin.directories.add(if (cnChannel) "src/testCn/kotlin" else "src/testPlay/kotlin")
        if (cnChannel) {
            getByName("debug").kotlin.directories.add("src/cnDebug/kotlin")
            getByName("debug").res.directories.add("src/cnDebug/res")
        }
        if (cnChannel) getByName("debug").manifest.srcFile("src/cnDebug/AndroidManifest.xml")
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
    if (!cnChannel) {
        implementation(libs.play.billing)
        implementation(libs.play.review)
    }
    implementation(libs.androidx.work.runtime.ktx)
    debugImplementation(libs.androidx.compose.ui.tooling)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}

// Gate before packaging, rather than failing after an unconfigured APK already exists.
val cnReleaseTrustConfigured = runCatching {
    val entries = JsonSlurper().parseText(cnKeys) as Map<*, *>
    require(entries.isNotEmpty() && cnAudience == "com.rainif.doneat.cn")
    entries.forEach { (kid, value) ->
        require(kid is String && kid.isNotBlank() && !kid.contains("test", ignoreCase = true))
        val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(value as String))) as RSAPublicKey
        require(key.modulus.bitLength() >= 2048)
    }
    true
}.getOrDefault(false)
tasks.configureEach {
    if (cnChannel && name == "preReleaseBuild") {
        val trustConfigured = cnReleaseTrustConfigured
        doFirst {
            require(trustConfigured) {
                "CN release requires production RSA doneatCnLicensePublicKeys and audience com.rainif.doneat.cn; debug test keys are not release configuration"
            }
        }
    }
}

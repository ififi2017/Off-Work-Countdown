package com.rainif.doneat.ui.timer

import android.app.KeyguardManager
import android.content.Context
import android.content.ContextWrapper
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * The asymmetry behind the eye button (iOS `OWCEarningsVisibilityButton`):
 * anyone holding the device can hide earnings, only its owner can bring them
 * back. The owner is whoever passes the device's own lock: a fingerprint or
 * face, or the PIN, pattern or password.
 */
object EarningsGate {
    enum class Result {
        CONFIRMED,

        /** No screen lock is set, so nothing can confirm anyone; the caller reveals and says so. */
        NO_LOCK,

        /** Cancelled or failed; earnings stay hidden. */
        REFUSED,
    }

    suspend fun confirmOwner(context: Context, title: String): Result {
        val activity = context.findActivity() ?: return Result.REFUSED
        if (!activity.getSystemService(KeyguardManager::class.java).isDeviceSecure) return Result.NO_LOCK
        return suspendCancellableCoroutine { continuation ->
            val prompt = BiometricPrompt(
                activity,
                ContextCompat.getMainExecutor(activity),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        if (continuation.isActive) continuation.resume(Result.CONFIRMED)
                    }

                    // A single unrecognised finger keeps the prompt open; only an error ends it.
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        if (continuation.isActive) continuation.resume(Result.REFUSED)
                    }
                },
            )
            // Weak biometrics or the device credential: the combination every supported API level accepts.
            prompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle(title)
                    .setAllowedAuthenticators(BIOMETRIC_WEAK or DEVICE_CREDENTIAL)
                    .build(),
            )
            continuation.invokeOnCancellation { prompt.cancelAuthentication() }
        }
    }

    private tailrec fun Context.findActivity(): FragmentActivity? = when (this) {
        is FragmentActivity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }
}

package com.rainif.doneat.ui.timer

import android.app.KeyguardManager
import android.content.Context
import android.content.ContextWrapper
import android.view.HapticFeedbackConstants
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import kotlinx.coroutines.launch
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

/**
 * The eye button (iOS `OWCEarningsVisibilityButton`): hides earnings at once,
 * reveals them only for the owner. The icon shows what a tap does, not the
 * current state. [onShownWithoutLock] explains a reveal no lock could confirm.
 */
@Composable
fun EarningsVisibilityButton(graph: AppGraph, onShownWithoutLock: (String) -> Unit) {
    val context = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val revealReason = stringResource(R.string.unlockSalaryReason)
    val noLockNote = stringResource(R.string.earningsShownWithoutLock)
    IconButton(onClick = {
        if (!device.hideEarnings) {
            scope.launch { graph.settings.updateDevice { it.copy(hideEarnings = true) } }
        } else {
            scope.launch {
                when (EarningsGate.confirmOwner(context, revealReason)) {
                    EarningsGate.Result.CONFIRMED -> graph.settings.updateDevice { it.copy(hideEarnings = false) }
                    EarningsGate.Result.NO_LOCK -> {
                        graph.settings.updateDevice { it.copy(hideEarnings = false) }
                        onShownWithoutLock(noLockNote)
                    }
                    EarningsGate.Result.REFUSED -> Unit
                }
            }
        }
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }) {
        Icon(
            if (device.hideEarnings) Icons.Outlined.Visibility else Icons.Outlined.VisibilityOff,
            contentDescription = stringResource(if (device.hideEarnings) R.string.unlockSalary else R.string.salaryLocked),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

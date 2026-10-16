package com.rainif.doneat.plus

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.PageFooter
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** A public review destination. The input never enters saved state, settings or logs. */
@Composable
fun ReviewAccessScreen(repository: ReviewAccessRepository, onBack: () -> Unit) {
    val state by repository.state.collectAsStateWithLifecycle()
    // Deliberately not rememberSaveable: recreation, leaving the route and backgrounding clear it.
    var code by remember { mutableStateOf("") }
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val resources = LocalResources.current
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) code = ""
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(repository) { repository.refresh() }
    fun submit() {
        if (state.busy || !state.configured || code.isBlank()) return
        val submitted = code.trim()
        code = ""
        keyboard?.hide()
        focus.clearFocus()
        repository.activate(submitted)
    }
    DoneAtPage(stringResource(R.string.reviewAccessTitle), onBack, stringResource(R.string.aboutProject)) {
        SettingsGroup(footer = stringResource(R.string.reviewAccessConnection)) {
            Column(Modifier.fillMaxWidth().padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                Text(stringResource(R.string.reviewAccessPurpose), style = MaterialTheme.typography.bodyMedium)
                Column(Modifier.semantics { liveRegion = LiveRegionMode.Polite }, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                    Text(stringResource(if (state.active) R.string.reviewAccessActive else R.string.reviewAccessInactive),
                        style = MaterialTheme.typography.titleMedium)
                    if (state.active) state.expiresAtMs?.let { expires ->
                        val locale = resources.configuration.locales[0]
                        val formatted = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
                            .withLocale(locale).format(Instant.ofEpochMilli(expires).atZone(ZoneId.systemDefault()))
                        Text(Strings.reviewAccessExpires(resources, time = formatted), style = MaterialTheme.typography.bodyMedium)
                    }
                    if (!state.configured) Text(stringResource(R.string.reviewAccessNotConfigured), style = MaterialTheme.typography.bodyMedium)
                    else state.error?.let { error ->
                        Text(stringResource(error.message), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                if (state.busy) CircularProgressIndicator(Modifier.size(DoneAtSpacing.l))
                if (state.hasSession) {
                    TextButton(onClick = repository::refresh, enabled = !state.busy) {
                        Text(stringResource(R.string.reviewAccessRefresh))
                    }
                    TextButton(onClick = { code = ""; repository.exit() }, enabled = !state.busy) {
                        Text(stringResource(R.string.reviewAccessExit))
                    }
                }
                if (!state.active && state.configured) {
                    Column(Modifier.imePadding(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                        OutlinedTextField(
                            value = code,
                            onValueChange = { code = it.take(256) },
                            label = { Text(stringResource(R.string.reviewAccessCode)) },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            enabled = !state.busy,
                            visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                            keyboardActions = KeyboardActions(onDone = { submit() }),
                        )
                        DoneAtPrimaryButton(stringResource(R.string.reviewAccessActivate), ::submit,
                            Modifier.fillMaxWidth(), enabled = !state.busy && code.isNotBlank())
                    }
                }
            }
        }
        PageFooter(stringResource(R.string.reviewAccessExitNote))
    }
}

private val ReviewAccessError.message: Int
    get() = when (this) {
        ReviewAccessError.UNAVAILABLE -> R.string.reviewAccessUnavailable
        ReviewAccessError.INVALID_CODE -> R.string.reviewAccessInvalidCode
        ReviewAccessError.NETWORK -> R.string.reviewAccessNetwork
        ReviewAccessError.REVOKED -> R.string.reviewAccessRevoked
        ReviewAccessError.STORAGE -> R.string.reviewAccessStorage
    }

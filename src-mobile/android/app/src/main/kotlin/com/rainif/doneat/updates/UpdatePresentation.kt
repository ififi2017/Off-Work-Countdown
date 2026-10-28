package com.rainif.doneat.updates

import android.os.Build
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.SystemUpdateAlt
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.pm.PackageInfoCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.rainif.doneat.BuildConfig
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.ui.components.ActionRow
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.settings.openUrl
import kotlinx.coroutines.*
import kotlinx.serialization.json.Json

@Composable
private fun ReleaseText(release: AndroidRelease) {
    val chinese = LocalResources.current.configuration.locales[0].language == "zh"
    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
        Text("${release.versionName} (${release.versionCode})", style = MaterialTheme.typography.titleMedium)
        val notes = release.releaseNotes[if (chinese) "zh-CN" else "en"] ?: release.releaseNotes["en"]
        if (!notes.isNullOrBlank()) Text(notes, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun UpdateDialog(release: AndroidRelease, onDismiss: () -> Unit) {
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Outlined.SystemUpdateAlt, contentDescription = null) },
        title = { Text(stringResource(R.string.androidUpdateAvailable)) },
        text = {
            Column(Modifier.heightIn(max = 400.dp).verticalScroll(rememberScrollState())) {
                ReleaseText(release)
            }
        },
        confirmButton = {
            Button(onClick = { onDismiss(); openUrl(context, AppUpdates.DOWNLOAD_PAGE) }) {
                Text(stringResource(R.string.androidUpdateDownload))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.notNow)) } },
    )
}

@Composable
fun ReleaseHistory() {
    val context = LocalContext.current
    val releases = remember {
        Json.decodeFromString<List<AndroidRelease>>(context.assets.open("cn-release-notes.json").bufferedReader().use { it.readText() })
    }
    var visible by remember { mutableStateOf(false) }
    SettingsGroup {
        ActionRow(stringResource(R.string.whatsNewTitle), { visible = true }, trailing = Icons.Outlined.SystemUpdateAlt)
    }
    if (visible) AlertDialog(
        onDismissRequest = { visible = false },
        title = { Text(stringResource(R.string.whatsNewTitle)) },
        text = {
            Column(Modifier.heightIn(max = 400.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xl)) {
                releases.forEach { ReleaseText(it) }
            }
        },
        confirmButton = { TextButton(onClick = { visible = false }) { Text(stringResource(R.string.close)) } },
    )
}

/** Foreground only, after setup; no worker, push permission, identifier or installer. */
@Composable
fun AutomaticUpdateReminder() {
    if (!BuildConfig.CN_CHANNEL) return
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var release by remember { mutableStateOf<AndroidRelease?>(null) }
    val preferences = remember { context.getSharedPreferences("update-reminders", 0) }
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            delay(3_000)
            try {
                val candidate = withContext(Dispatchers.IO) {
                    val now = System.currentTimeMillis()
                    if (!UpdatePolicy.checkDue(now, preferences.getLong("lastAttempt", 0))) return@withContext null
                    // Persist attempts too, so network failure cannot cause a launch retry storm.
                    if (!preferences.edit().putLong("lastAttempt", now).commit()) return@withContext null
                    val installed = PackageInfoCompat.getLongVersionCode(context.packageManager.getPackageInfo(context.packageName, 0))
                    val result = AppUpdates.check(installed, Build.VERSION.SDK_INT) as? UpdateResult.Available
                    result?.release?.takeIf {
                        UpdatePolicy.reminderDue(now, it.versionCode, preferences.getLong("lastCode", 0), preferences.getLong("lastShown", 0))
                    }
                }
                if (candidate != null) {
                    release = candidate
                    preferences.edit().putLong("lastCode", candidate.versionCode)
                        .putLong("lastShown", System.currentTimeMillis()).apply()
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { /* Automatic checks stay silent when offline or unavailable. */ }
            awaitCancellation()
        }
    }
    release?.let { UpdateDialog(it, onDismiss = { release = null }) }
}

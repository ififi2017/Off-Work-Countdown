package com.rainif.doneat.ui.settings

import android.os.Build
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.SystemUpdateAlt
import androidx.compose.material3.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.pm.PackageInfoCompat
import com.rainif.doneat.BuildConfig
import com.rainif.doneat.R
import com.rainif.doneat.ui.components.ActionRow
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.updates.AppUpdates
import com.rainif.doneat.updates.UpdateResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun AboutUpdates() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var checking by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<UpdateResult?>(null) }
    var failed by remember { mutableStateOf(false) }
    var showDialog by remember { mutableStateOf(false) }
    if (!BuildConfig.CN_CHANNEL) {
        SettingsGroup {
            ActionRow(stringResource(R.string.androidUpdatePlay), { openUrl(context, AppUpdates.PLAY_PAGE) })
        }
        return
    }
    val status = when {
        checking -> R.string.androidCheckingUpdates
        result == UpdateResult.Current -> R.string.androidUpdateCurrent
        result is UpdateResult.Available -> R.string.androidUpdateAvailable
        else -> R.string.androidCheckUpdates
    }
    SettingsGroup {
        // Status replaces the action in place; no footer or extra row shifts the page.
        ListItem(
            headlineContent = {
                Text(stringResource(status), maxLines = 1, overflow = TextOverflow.Ellipsis)
            },
            trailingContent = {
                if (checking) {
                    CircularProgressIndicator(Modifier.size(DoneAtSpacing.xl), strokeWidth = DoneAtSpacing.xxs)
                } else {
                    Icon(
                        when (result) {
                            UpdateResult.Current -> Icons.Outlined.CheckCircle
                            is UpdateResult.Available -> Icons.Outlined.SystemUpdateAlt
                            else -> Icons.Outlined.Refresh
                        },
                        contentDescription = null,
                        tint = if (result is UpdateResult.Available) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            modifier = Modifier
                .semantics { liveRegion = LiveRegionMode.Polite }
                .clickable(enabled = !checking, role = Role.Button) {
                    if (result is UpdateResult.Available) {
                        showDialog = true
                    } else {
                        checking = true
                        result = null
                        failed = false
                        scope.launch {
                            try {
                                val installed = PackageInfoCompat.getLongVersionCode(context.packageManager.getPackageInfo(context.packageName, 0))
                                result = AppUpdates.check(installed, Build.VERSION.SDK_INT)
                            } catch (cancelled: CancellationException) { throw cancelled }
                            catch (_: Exception) { failed = true }
                            finally { checking = false }
                            showDialog = true
                        }
                    }
                },
        )
    }
    if (showDialog && (failed || result == UpdateResult.Incompatible)) {
        AlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text(stringResource(R.string.androidCheckUpdates)) },
            text = { Text(stringResource(if (failed) R.string.androidUpdateFailed else R.string.androidUpdateIncompatible)) },
            confirmButton = {
                TextButton(onClick = { showDialog = false }) { Text(stringResource(R.string.close)) }
            },
        )
    }
    val available = result as? UpdateResult.Available
    if (showDialog && available != null) {
        com.rainif.doneat.updates.UpdateDialog(available.release, onDismiss = { showDialog = false })
    }
    com.rainif.doneat.updates.ReleaseHistory()
}

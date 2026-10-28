package com.rainif.doneat.ui.settings

import android.os.Build
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.pm.PackageInfoCompat
import com.rainif.doneat.BuildConfig
import com.rainif.doneat.R
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.components.ActionRow
import com.rainif.doneat.ui.components.SettingsFooter
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
    SettingsGroup {
        ActionRow(stringResource(if (checking) R.string.androidCheckingUpdates else R.string.androidCheckUpdates), {
            if (!checking) {
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
                    showDialog = result is UpdateResult.Available
                }
            }
        })
    }
    when {
        failed -> SettingsFooter(stringResource(R.string.androidUpdateFailed))
        result == UpdateResult.Current -> SettingsFooter(stringResource(R.string.androidUpdateCurrent))
        result == UpdateResult.Incompatible -> SettingsFooter(stringResource(R.string.androidUpdateIncompatible))
    }
    val available = result as? UpdateResult.Available
    if (showDialog && available != null) {
        AlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text(stringResource(R.string.androidUpdateAvailable)) },
            text = { Text(Strings.androidUpdateMessage(androidx.compose.ui.platform.LocalResources.current, available.release.versionName)) },
            confirmButton = { TextButton(onClick = { showDialog = false; openUrl(context, AppUpdates.DOWNLOAD_PAGE) }) { Text(stringResource(R.string.androidUpdateDownload)) } },
            dismissButton = { TextButton(onClick = { showDialog = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

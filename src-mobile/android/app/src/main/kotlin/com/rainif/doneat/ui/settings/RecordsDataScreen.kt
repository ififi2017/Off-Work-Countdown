package com.rainif.doneat.ui.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.data.ImportPreview
import com.rainif.doneat.core.data.RecordsTransfer
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsFooter
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.ValueRow
import com.rainif.doneat.ui.files.BackupFiles
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Records & data (iOS `RecordsDataSettingsView`): backups in and out through
 * the system's document picker, and deleting this device's records.
 *
 * An import is read (at most 25 MB), previewed on a copy, and written only
 * after the user confirms, in one archive write computed against the archive
 * as it is at that moment. Same-key conflicts keep this device's copy.
 */
@Composable
fun RecordsDataScreen(graph: AppGraph, onBack: () -> Unit) {
    val context = LocalContext.current
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
    var pending by remember { mutableStateOf<Pair<ByteArray, ImportPreview.Ready>?>(null) }
    var reading by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var exportWithLife by remember { mutableStateOf(true) }

    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        reading = true
        scope.launch {
            val bytes = withContext(Dispatchers.IO) { BackupFiles.read(context, uri, RecordsTransfer.MAX_BYTES) }
            val preview = bytes?.let { withContext(Dispatchers.Default) { RecordsTransfer.preview(it, graph.records.state.value) } }
            reading = false
            when (preview) {
                is ImportPreview.Ready -> pending = bytes to preview
                ImportPreview.TooLarge -> message = res.getString(R.string.recordsImportTooLarge)
                ImportPreview.UnsupportedVersion -> message = res.getString(R.string.recordsOperationUnsupportedVersion)
                ImportPreview.Invalid -> message = res.getString(R.string.recordsOperationInvalidDocument)
                null -> message = res.getString(R.string.recordsOperationReadFailed)
            }
        }
    }
    val create = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            val text = RecordsTransfer.export(graph.records.state.value, exportWithLife, graph.nowMs(), prefs.recordsTimeZoneIdentifier)
            val written = withContext(Dispatchers.IO) { BackupFiles.write(context, uri, text) }
            if (!written) message = res.getString(R.string.recordsOperationExportFailed)
        }
    }
    fun export(includeLife: Boolean) {
        exportWithLife = includeLife
        val date = DateTimeFormatter.ISO_LOCAL_DATE.format(LocalDate.now())
        create.launch(if (includeLife) "doneat-records-$date.json" else "doneat-records-without-life-$date.json")
    }

    DoneAtPage(stringResource(R.string.recordsDataTitle), onBack, stringResource(R.string.settings)) {
        SettingsGroup {
            ValueRow(stringResource(R.string.recordsTimeZone), prefs.recordsTimeZoneIdentifier)
        }
        SettingsGroup(title = stringResource(R.string.recordsExport), footer = stringResource(R.string.recordsExportFooterLocal)) {
            DataRow(Icons.Outlined.FileDownload, stringResource(R.string.recordsImport), busy = reading) { if (!reading) pick.launch(BackupFiles.OPEN_TYPES) }
            RowDivider()
            DataRow(Icons.Outlined.FileUpload, stringResource(R.string.recordsExportFull)) { export(includeLife = true) }
            RowDivider()
            DataRow(Icons.Outlined.FileUpload, stringResource(R.string.recordsExportWithoutLife)) { export(includeLife = false) }
        }
        SettingsGroup {
            DataRow(Icons.Outlined.DeleteOutline, stringResource(R.string.recordsDeleteAll), destructive = true) { confirmDelete = true }
        }
    }

    pending?.let { (bytes, preview) ->
        AlertDialog(
            onDismissRequest = { pending = null },
            title = { Text(stringResource(R.string.recordsImportPreviewTitle)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    Text(Strings.recordsImportAdded(res, preview.added.toString()))
                    Text(Strings.recordsImportSame(res, preview.unchanged.toString()))
                    Text(Strings.recordsImportConflicts(res, preview.conflicts.toString()))
                    Text(Strings.recordsImportSkipped(res, preview.skippedErased.toString()))
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    pending = null
                    scope.launch {
                        val skipped = RecordsTransfer.commit(graph.records, bytes)
                        message = if (skipped != null) Strings.recordsImportReport(res, skipped.toString()) else res.getString(R.string.recordsOperationImportFailed)
                    }
                }) { Text(stringResource(R.string.recordsImportApplyNew)) }
            },
            dismissButton = { TextButton(onClick = { pending = null }) { Text(stringResource(R.string.cancelAction)) } },
        )
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.recordsDeleteAll)) },
            text = { Text(stringResource(R.string.recordsDeleteAllConfirm)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    scope.launch { RecordsTransfer.deleteRecords(graph.records) }
                }) { Text(stringResource(R.string.recordsDeleteAll), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancelAction)) } },
        )
    }
    message?.let {
        AlertDialog(
            onDismissRequest = { message = null },
            title = { Text(stringResource(R.string.recordsDataTitle)) },
            text = { Text(it) },
            confirmButton = { TextButton(onClick = { message = null }) { Text(stringResource(R.string.close)) } },
        )
    }
}

@Composable
private fun DataRow(icon: ImageVector, title: String, busy: Boolean = false, destructive: Boolean = false, onClick: () -> Unit) {
    val tint = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = DoneAtSpacing.l),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = if (destructive) tint else MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, Modifier.weight(1f).padding(horizontal = DoneAtSpacing.l), style = MaterialTheme.typography.bodyLarge, color = tint)
        if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
    }
}

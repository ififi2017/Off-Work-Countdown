package com.rainif.doneat.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.ui.components.DoneAtPage
import kotlinx.coroutines.launch

/** An unreadable archive is never presented as an empty first launch. */
@Composable
fun ArchiveRecoveryScreen(graph: AppGraph) {
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    var confirms by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    DoneAtPage(res.getString(R.string.recordsArchiveDamagedTitle)) {
        Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
            Text(res.getString(R.string.recordsArchiveDamagedBody))
            Button(enabled = !busy, onClick = {
                busy = true
                scope.launch {
                    try { graph.records.load() } finally { busy = false }
                }
            }) { Text(res.getString(R.string.retryAction)) }
            TextButton(enabled = !busy, onClick = { confirms = true }) {
                Text(res.getString(R.string.recordsArchiveQuarantine))
            }
            if (failed) Text(res.getString(R.string.recordsArchiveSaveFailedTitle), color = MaterialTheme.colorScheme.error)
        }
    }
    if (confirms) AlertDialog(
        onDismissRequest = { confirms = false },
        title = { Text(res.getString(R.string.recordsArchiveQuarantine)) },
        text = { Text(res.getString(R.string.recordsArchiveQuarantineConfirm)) },
        confirmButton = {
            TextButton(onClick = {
                confirms = false
                busy = true
                scope.launch {
                    try { graph.records.quarantine() } catch (_: java.io.IOException) { failed = true }
                    finally { busy = false }
                }
            }) { Text(res.getString(R.string.continue_)) }
        },
        dismissButton = { TextButton(onClick = { confirms = false }) { Text(res.getString(R.string.cancel)) } },
    )
}

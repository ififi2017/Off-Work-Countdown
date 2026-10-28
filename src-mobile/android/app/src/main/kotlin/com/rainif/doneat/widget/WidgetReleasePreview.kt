package com.rainif.doneat.widget

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.core.domain.widget.WidgetSnapshot
import com.rainif.doneat.core.domain.widget.WidgetSuiteSnapshot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** The release introduction uses the shipping renderers and the user's salary-free projections. */
@Composable
internal fun WidgetReleasePreview(graph: AppGraph, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val records by graph.records.state.collectAsStateWithLifecycle()
    var snapshots by remember { mutableStateOf<Pair<WidgetSuiteSnapshot?, WidgetSnapshot?>>(null to null) }
    var now by remember { mutableLongStateOf(graph.nowMs().toLong()) }
    LaunchedEffect(session, records) {
        graph.widgets.refresh()
        snapshots = withContext(Dispatchers.IO) { WidgetSuiteCoordinator.read(context) to WidgetCoordinator.read(context) }
        now = graph.nowMs().toLong()
    }
    val top = remember(context, snapshots, now) {
        widgetCountdownPreviewBitmap(context, DoneAtWidgetKind.CLASSIC, snapshots.second, snapshots.first, now, DpSize(364.dp, 118.dp))
    }
    val ring = remember(context, snapshots, now) {
        widgetCountdownPreviewBitmap(context, DoneAtWidgetKind.RING, snapshots.second, snapshots.first, now, DpSize(170.dp, 170.dp))
    }
    val week = remember(context, snapshots, now) {
        widgetCardBitmap(context, widgetSuiteCard(context, DoneAtWidgetKind.WEEK, snapshots.first, now), DpSize(170.dp, 170.dp))
    }
    Surface(modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerHighest) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Image(top.asImageBitmap(), null, Modifier.fillMaxWidth().aspectRatio(364f / 118f))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Image(ring.asImageBitmap(), null, Modifier.weight(1f).aspectRatio(1f))
                Image(week.asImageBitmap(), null, Modifier.weight(1f).aspectRatio(1f))
            }
        }
    }
}

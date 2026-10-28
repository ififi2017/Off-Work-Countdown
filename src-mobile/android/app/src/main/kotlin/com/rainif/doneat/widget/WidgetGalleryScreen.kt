package com.rainif.doneat.widget

import android.appwidget.AppWidgetManager
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.widget.WidgetSnapshot
import com.rainif.doneat.core.domain.widget.WidgetSuiteSnapshot
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.SettingsGroup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Real data and the same card renderer as the launcher; Plus stays locked until verified. */
@Composable
fun WidgetGalleryScreen(graph: AppGraph, onBack: () -> Unit, open: (Route) -> Unit) {
    val context = LocalContext.current
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val records by graph.records.state.collectAsStateWithLifecycle()
    val authorized by graph.plus.authorized.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val queue by graph.focus.queue.collectAsStateWithLifecycle()
    var suite by remember { mutableStateOf<WidgetSuiteSnapshot?>(null) }
    var countdown by remember { mutableStateOf<WidgetSnapshot?>(null) }
    var now by remember { mutableLongStateOf(graph.nowMs().toLong()) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                now = graph.nowMs().toLong()
                delay(60_000 - now % 60_000)
            }
        }
    }
    LaunchedEffect(session, records, authorized, device, queue) {
        graph.widgets.refresh()
        withContext(Dispatchers.IO) { WidgetSuiteCoordinator.read(context) to WidgetCoordinator.read(context) }.let {
            now = graph.nowMs().toLong()
            suite = it.first
            countdown = it.second
        }
    }
    val pinSupported = remember(context) { AppWidgetManager.getInstance(context).isRequestPinAppWidgetSupported }
    DoneAtPage(stringResource(R.string.widgetGalleryTitle), onBack, stringResource(R.string.settings)) {
        Text(stringResource(R.string.androidWidgetGalleryIntro), Modifier.padding(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.s),
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(stringResource(R.string.androidWidgetGalleryStepsHome), Modifier.padding(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.s),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        val sections = listOf(
            R.string.widgetGallerySectionCountdown to DoneAtWidgetKind.entries.filter { it.countdown },
            R.string.widgetGallerySectionWeek to listOf(DoneAtWidgetKind.WEEK, DoneAtWidgetKind.ROSTER, DoneAtWidgetKind.WEEKEND, DoneAtWidgetKind.HOLIDAY),
            R.string.widgetGallerySectionRecords to listOf(DoneAtWidgetKind.SUMMARY, DoneAtWidgetKind.LIFE, DoneAtWidgetKind.YEAR),
            R.string.focusTitle to listOf(DoneAtWidgetKind.FOCUS),
        )
        sections.forEach { (sectionTitle, kinds) ->
            Text(stringResource(sectionTitle), Modifier.padding(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.m).semantics { heading() },
                style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            SettingsGroup {
                kinds.forEach { kind ->
                    WidgetGalleryItem(kind, suite, countdown, now, pinSupported, open)
                }
            }
        }
    }
}

@Composable
private fun WidgetGalleryItem(kind: DoneAtWidgetKind, suite: WidgetSuiteSnapshot?, countdown: WidgetSnapshot?, now: Long,
                              pinSupported: Boolean, open: (Route) -> Unit) {
    val context = LocalContext.current
    var sizeIndex by remember(kind) { mutableIntStateOf(if (kind.defaultSize.height >= 250.dp) 2 else if (kind.defaultSize.width >= 220.dp) 1 else 0) }
    val allSizes = listOf(DpSize(150.dp, 150.dp), DpSize(260.dp, 150.dp), DpSize(260.dp, 290.dp))
    val supportedIndices = if (kind == DoneAtWidgetKind.DETAIL) listOf(1, 2) else listOf(0, 1, 2)
    val size = allSizes[sizeIndex]
    val card = remember(kind, suite, now, context) { widgetSuiteCard(context, kind, suite, now) }
    val bitmap = remember(kind, card, countdown, suite, now, size, context) {
        if (kind.countdown) widgetCountdownPreviewBitmap(context, kind, countdown, suite, now, size)
        else widgetCardBitmap(context, card, size)
    }
    var pinUnavailable by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(kind.titleRes), Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
            Text(if (kind.plus) "Plus" else stringResource(if (kind == DoneAtWidgetKind.HOLIDAY) R.string.widgetGalleryFreeAndPlus else R.string.widgetGalleryFree),
                style = MaterialTheme.typography.labelSmall, color = if (kind.plus) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
        }
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            val labels = listOf(R.string.widgetGallerySizeSmall, R.string.widgetGallerySizeMedium, R.string.widgetGallerySizeLarge)
            supportedIndices.forEachIndexed { position, index ->
                val label = labels[index]
                SegmentedButton(sizeIndex == index, { sizeIndex = index }, SegmentedButtonDefaults.itemShape(position, supportedIndices.size)) {
                    Text(stringResource(label), style = MaterialTheme.typography.labelSmall)
                }
            }
        }
        Box(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainerHighest, MaterialTheme.shapes.large)
            .padding(DoneAtSpacing.m).horizontalScroll(rememberScrollState()), contentAlignment = Alignment.Center) {
            Image(bitmap.asImageBitmap(), if (kind.countdown) stringResource(kind.titleRes) else card.description,
                Modifier.size(size.width, size.height))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            if (kind.plus && card.locked) TextButton({ open(Route.Plus) }) { Text(stringResource(R.string.widgetSuiteLearnPlus)) }
            if (pinSupported) TextButton({ pinUnavailable = !kind.pin(context) }) { Text(stringResource(R.string.androidWidgetGalleryPin)) }
        }
        if (!pinSupported || pinUnavailable) Text(stringResource(R.string.androidWidgetGalleryPinUnavailable),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        HorizontalDivider()
    }
}

package com.rainif.doneat.ui.release

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Widgets
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.plus.PlusStatus

/** The caller persists Continue successfully before removing this screen. */
@Composable
fun WhatsNewScreen(graph: AppGraph, onDismiss: () -> Unit, continuing: Boolean = false, errorText: String? = null) {
    val authorized by graph.plus.authorized.collectAsStateWithLifecycle()
    val store by graph.plus.state.collectAsStateWithLifecycle()
    // Neither system Back nor an overlay dismissal acknowledges the update.
    BackHandler { }
    LaunchedEffect(Unit) { graph.plus.refresh() }
    LaunchedEffect(authorized, store.status, store.currentEntitlementsVerified, store.hasActiveSubscription) {
        if (ReleaseNotesPolicy.mayInviteUpdateOffer(authorized, store.status == PlusStatus.FREE,
                store.currentEntitlementsVerified, store.hasActiveSubscription)) {
            graph.plus.inviteUpdateGift()
        }
    }
    var showsWidgets by rememberSaveable { mutableStateOf(false) }
    if (showsWidgets) {
        BackHandler { showsWidgets = false }
        com.rainif.doneat.widget.WidgetGalleryScreen(graph, { showsWidgets = false }) {
            graph.requestedTab.value = "plus"
            onDismiss()
        }
        return
    }
    val largeText = LocalDensity.current.fontScale >= 1.5f
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.fillMaxSize().safeDrawingPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                        Text("DoneAt ${ReleaseNotesPolicy.CURRENT}", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.whatsNewWidgetsTitle), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                    }
                    com.rainif.doneat.widget.WidgetReleasePreview(graph)
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        ReleaseFeature(Icons.Outlined.Widgets, R.string.whatsNewHomeTitle, R.string.whatsNewHomeBody, largeText)
                        ReleaseFeature(Icons.Outlined.BarChart, R.string.widgetSuiteYearName, R.string.widgetSuiteYearDescription, largeText)
                        ReleaseFeature(Icons.Outlined.Star, R.string.widgetSuiteSummaryName, R.string.widgetSuiteSummaryDescription, largeText)
                    }
                }
            }
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(DoneAtSpacing.xl), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                if (errorText != null) Text(errorText, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
                TextButton({ showsWidgets = true }, Modifier.fillMaxWidth(), enabled = !continuing) {
                    Text(stringResource(R.string.widgetGalleryTitle))
                }
                DoneAtPrimaryButton(stringResource(R.string.whatsNewContinue), onDismiss, Modifier.fillMaxWidth(), enabled = !continuing)
            }
        }
    }
}

@Composable
private fun ReleaseFeature(symbol: ImageVector, title: Int, body: Int, largeText: Boolean) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), verticalAlignment = Alignment.Top) {
        if (!largeText) Icon(symbol, null, Modifier.size(DoneAtSpacing.xl), tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
            Text(stringResource(title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(stringResource(body), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

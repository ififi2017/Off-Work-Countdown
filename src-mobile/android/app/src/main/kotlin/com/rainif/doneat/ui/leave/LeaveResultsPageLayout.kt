package com.rainif.doneat.ui.leave

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtBottomBarPadding

/** Result lists keep their back button reachable and return to the selected preview's headline. */
@Composable
internal fun LeaveResultsPageLayout(
    title: String, onBack: () -> Unit, backLabel: String, page: LeaveResultsPage,
    footer: (@Composable ColumnScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val summaryScroll = rememberScrollState()
    val plansScroll = rememberScrollState()
    val datesScroll = rememberScrollState()
    val scroll = when (page) {
        LeaveResultsPage.SUMMARY -> summaryScroll
        LeaveResultsPage.ALL_PLANS -> plansScroll
        LeaveResultsPage.DATES -> datesScroll
    }
    LaunchedEffect(page) { scroll.scrollTo(0) }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Box(Modifier.fillMaxSize().safeDrawingPadding(), contentAlignment = Alignment.TopCenter) {
            Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight()) {
                Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, backLabel) }
                    Text(title, Modifier.weight(1f).padding(start = DoneAtSpacing.page - DoneAtSpacing.xs, end = DoneAtSpacing.page).semantics { heading() },
                        style = MaterialTheme.typography.headlineMedium)
                }
                Column(Modifier.weight(1f).verticalScroll(scroll).padding(top = DoneAtSpacing.s,
                    bottom = if (footer == null) DoneAtSpacing.xl + LocalDoneAtBottomBarPadding.current else DoneAtSpacing.m),
                    verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l), content = content)
                if (footer != null) {
                    Column(Modifier.fillMaxWidth().padding(start = DoneAtSpacing.page, end = DoneAtSpacing.page,
                        top = DoneAtSpacing.s, bottom = DoneAtSpacing.s + LocalDoneAtBottomBarPadding.current),
                        verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), content = footer)
                }
            }
        }
    }
}

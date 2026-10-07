package com.rainif.doneat.ui.leave

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.filled.Luggage
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.Contrast
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtLeaveTokens
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.core.domain.leave.LeavePlanCalendarPage
import com.rainif.doneat.core.domain.leave.LeavePlanProposal
import com.rainif.doneat.core.domain.leave.LeavePlannerSchedule
import com.rainif.doneat.core.domain.schedule.LeavePortion
import kotlinx.coroutines.delay
import java.time.DayOfWeek
import java.time.format.TextStyle

private enum class LeaveMark { REST, HOLIDAY, LEAVE, HALF_LEAVE }

/** Complete six-row months. Only the proposal supplies marks; adjacent dates stay neutral. */
@Composable
internal fun LeavePlanCalendar(proposal: LeavePlanProposal, text: LeaveText, firstWeekday: DayOfWeek, modifier: Modifier = Modifier) {
    val months = remember(proposal) { LeavePlanCalendarPage.months(proposal) }
    var monthIndex by remember(proposal.firstRestDayNumber, proposal.lastRestDayNumber) { mutableIntStateOf(0) }
    val activeMonth = monthIndex.coerceIn(months.indices)
    val page = remember(months[activeMonth], firstWeekday) { LeavePlanCalendarPage(months[activeMonth], firstWeekday) }
    val reduced = LocalDoneAtMotion.current.reduced
    val travel = with(LocalDensity.current) { DoneAtLeaveTokens.monthTravel.roundToPx() }
    val marks = remember(proposal) { LeavePlanCalendarPage.coverage(proposal).associateWith { mark(proposal, it) } }
    val used = marks.values.filterNotNull().toSet()

    Column(modifier, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        Row(Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch), verticalAlignment = Alignment.CenterVertically) {
            Text(text.month(page.firstDayNumber), Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (months.size > 1) {
                IconButton(onClick = { monthIndex = activeMonth - 1 }, enabled = activeMonth > 0) {
                    Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, text.string(R.string.extendedPreviousMonth), tint = monthArrowTint(activeMonth > 0))
                }
                IconButton(onClick = { monthIndex = activeMonth + 1 }, enabled = activeMonth < months.lastIndex) {
                    Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, text.string(R.string.extendedNextMonth), tint = monthArrowTint(activeMonth < months.lastIndex))
                }
            }
        }
        AnimatedContent(
            targetState = page, label = "leaveMonth",
            transitionSpec = {
                val enter = fadeIn(DoneAtLeaveTokens.navigation(reduced))
                ((if (reduced) enter else enter + slideInVertically(DoneAtLeaveTokens.navigation(false)) { travel }) togetherWith
                    fadeOut(DoneAtLeaveTokens.navigation(reduced))).using(null)
            },
        ) { shown ->
            Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                Row(Modifier.clearAndSetSemantics {}) {
                    (0 until 7).forEach { column ->
                        Text(
                            DayOfWeek.of(Math.floorMod(firstWeekday.value - 1 + column, 7) + 1).getDisplayName(TextStyle.NARROW_STANDALONE, text.locale),
                            Modifier.weight(1f), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
                shown.days.chunked(7).forEach { week ->
                    Row {
                        week.forEach { day ->
                            CalendarDay(day, shown, proposal, marks[day], text, Modifier.weight(1f))
                        }
                    }
                }
            }
        }
        FlowRow(
            Modifier.fillMaxWidth().padding(top = DoneAtSpacing.xs).clearAndSetSemantics {},
            horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs),
        ) {
            LeaveMark.entries.filter { it in used }.forEach { kind ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    MarkIcon(kind, Modifier.size(DoneAtLeaveTokens.markSize))
                    Text(markLabel(kind, text), style = MaterialTheme.typography.labelSmall, color = markTint(kind))
                }
            }
        }
    }
}

@Composable
private fun monthArrowTint(enabled: Boolean) = MaterialTheme.colorScheme.primary.copy(alpha = if (enabled) 1f else DoneAtLeaveTokens.inactiveAlpha)

private fun mark(proposal: LeavePlanProposal, day: Int): LeaveMark? {
    proposal.items.firstOrNull { it.dayNumber == day }?.let {
        return if (it.portion == LeavePortion.WHOLE) LeaveMark.LEAVE else LeaveMark.HALF_LEAVE
    }
    return when (proposal.dayKinds.getOrNull(day - proposal.firstRestDayNumber)) {
        LeavePlanProposal.DayKind.HOLIDAY -> LeaveMark.HOLIDAY
        LeavePlanProposal.DayKind.LEAVE -> LeaveMark.LEAVE
        LeavePlanProposal.DayKind.REST -> LeaveMark.REST
        null -> null
    }
}

@Composable
private fun CalendarDay(day: Int, page: LeavePlanCalendarPage, proposal: LeavePlanProposal, kind: LeaveMark?, text: LeaveText, modifier: Modifier) {
    val reduced = LocalDoneAtMotion.current.reduced
    var revealed by remember(page.firstDayNumber, proposal) { mutableStateOf(false) }
    LaunchedEffect(page.firstDayNumber, proposal, reduced) {
        revealed = false
        if (!reduced) delay(DoneAtLeaveTokens.dayCommitMs + DoneAtLeaveTokens.delay(day - LeavePlanCalendarPage.coverage(proposal).first))
        revealed = true
    }
    val alpha by animateFloatAsState(if (revealed) 1f else 0f, DoneAtLeaveTokens.fade(reduced), label = "leaveDayFade")
    val iconScale by animateFloatAsState(if (revealed || reduced) 1f else DoneAtLeaveTokens.iconStartScale, DoneAtLeaveTokens.reveal(reduced), label = "leaveDayIcon")
    val tileScale by animateFloatAsState(if (revealed || reduced) 1f else DoneAtLeaveTokens.tileStartScale, DoneAtLeaveTokens.reveal(reduced), label = "leaveDayTile")
    val scheme = MaterialTheme.colorScheme
    val inBreak = day in proposal.firstRestDayNumber..proposal.lastRestDayNumber
    val first = day == proposal.firstRestDayNumber
    val last = day == proposal.lastRestDayNumber
    val isLeave = kind == LeaveMark.LEAVE || kind == LeaveMark.HALF_LEAVE
    val cellHeight = DoneAtLeaveTokens.cellHeight * LocalDensity.current.fontScale
    val label = listOfNotNull(text.day(day), kind?.let { markLabel(it, text) }).joinToString(", ")
    Box(modifier.heightIn(min = cellHeight).clearAndSetSemantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        if (inBreak) Box(
            Modifier.matchParentSize().background(scheme.primary.copy(alpha = alpha * DoneAtLeaveTokens.rangeAlpha), RoundedCornerShape(
                topStart = if (first) DoneAtLeaveTokens.rangeCorner else 0.dp, bottomStart = if (first) DoneAtLeaveTokens.rangeCorner else 0.dp,
                topEnd = if (last) DoneAtLeaveTokens.rangeCorner else 0.dp, bottomEnd = if (last) DoneAtLeaveTokens.rangeCorner else 0.dp,
            )),
        )
        if (isLeave) Box(
            Modifier.matchParentSize().padding(DoneAtSpacing.xxs).graphicsLayer { scaleX = tileScale; scaleY = tileScale }
                .background(scheme.primary.copy(alpha = alpha * DoneAtLeaveTokens.leaveAlpha), MaterialTheme.shapes.small),
        )
        Column(Modifier.fillMaxWidth().padding(vertical = DoneAtSpacing.xxs), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs)) {
            Text(
                text.wholeNumber(LeavePlannerSchedule.date(day).dayOfMonth),
                style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                fontWeight = if (kind == null) FontWeight.Normal else FontWeight.SemiBold,
                color = if (kind != null || page.contains(day)) scheme.onSurface else scheme.onSurface.copy(alpha = DoneAtLeaveTokens.inactiveAlpha),
            )
            Box(Modifier.size(DoneAtLeaveTokens.markSize).graphicsLayer { this.alpha = alpha; scaleX = iconScale; scaleY = iconScale }) {
                if (kind != null) MarkIcon(kind, Modifier.size(DoneAtLeaveTokens.markSize))
            }
        }
    }
}

@Composable
private fun markTint(mark: LeaveMark) = if (mark == LeaveMark.LEAVE || mark == LeaveMark.HALF_LEAVE) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant

@Composable
private fun MarkIcon(mark: LeaveMark, modifier: Modifier) {
    val icon = when (mark) {
        LeaveMark.REST -> Icons.Outlined.Bedtime
        LeaveMark.HOLIDAY -> Icons.Outlined.Flag
        LeaveMark.LEAVE -> Icons.Filled.Luggage
        LeaveMark.HALF_LEAVE -> Icons.Outlined.Contrast
    }
    Icon(icon, null, modifier, tint = markTint(mark))
}

private fun markLabel(mark: LeaveMark, text: LeaveText): String = text.string(when (mark) {
    LeaveMark.REST -> R.string.leaveDayRest
    LeaveMark.HOLIDAY -> R.string.leaveDayHoliday
    LeaveMark.LEAVE -> R.string.leaveDayLeave
    LeaveMark.HALF_LEAVE -> R.string.leaveDayHalf
})

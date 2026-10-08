package com.rainif.doneat.ui.leave

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalResources
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.schedule.HolidayDayAnnotation
import com.rainif.doneat.ui.schedule.HolidayDayCaption
import com.rainif.doneat.ui.schedule.holidayDayAnnotation
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
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
internal fun LeavePlanCalendar(proposal: LeavePlanProposal, text: LeaveText, firstWeekday: DayOfWeek, modifier: Modifier = Modifier, holidays: HolidayCalendar = HolidayCalendar.EMPTY, holidayRegion: String? = null) {
    val months = remember(proposal) { LeavePlanCalendarPage.months(proposal) }
    var monthIndex by remember(proposal.firstRestDayNumber, proposal.lastRestDayNumber) { mutableIntStateOf(0) }
    val activeMonth = monthIndex.coerceIn(months.indices)
    val page = remember(months[activeMonth], firstWeekday) { LeavePlanCalendarPage(months[activeMonth], firstWeekday) }
    val reduced = LocalDoneAtMotion.current.reduced
    val travel = with(LocalDensity.current) { DoneAtLeaveTokens.monthTravel.roundToPx() }
    val marks = remember(proposal) { LeavePlanCalendarPage.coverage(proposal).associateWith { mark(proposal, it) } }
    // A caption replaces the symbol; only explain icons actually rendered in this month.
    val used = page.days.mapNotNull { day ->
        val kind = marks[day] ?: return@mapNotNull null
        val annotation = holidayDayAnnotation(holidays, holidayRegion, LeavePlannerSchedule.date(day), text.locale)
        kind.takeIf { annotation == null || kind == LeaveMark.LEAVE || kind == LeaveMark.HALF_LEAVE }
    }.toSet()
    var selectedHoliday by remember(proposal) { mutableStateOf<Pair<Int, HolidayDayAnnotation>?>(null) }
    val resources = LocalResources.current

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
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val density = LocalDensity.current
                val dateHeight = with(density) { MaterialTheme.typography.bodyMedium.lineHeight.toDp() }
                val captionHeight = maxOf(DoneAtLeaveTokens.markSize * density.fontScale,
                    with(density) { MaterialTheme.typography.labelSmall.fontSize.toDp() })
                val textHeight = dateHeight + captionHeight + DoneAtSpacing.xxs * 3
                val minimumDayHeight = maxOf(maxWidth / 7, DoneAtLeaveTokens.cellHeight * density.fontScale, textHeight)
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
                        Row(Modifier.height(IntrinsicSize.Min)) {
                            week.forEach { day ->
                                val annotation = holidayDayAnnotation(holidays, holidayRegion, LeavePlannerSchedule.date(day), text.locale)
                                CalendarDay(day, shown, proposal, marks[day], text, Modifier.weight(1f).fillMaxHeight(), annotation, minimumDayHeight) {
                                    annotation?.let { selectedHoliday = day to it }
                                }
                            }
                        }
                    }
                }
            }
        }
        if (used.isNotEmpty()) FlowRow(
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
    selectedHoliday?.let { (day, annotation) ->
        AlertDialog(
            onDismissRequest = { selectedHoliday = null },
            title = { Text(annotation.name) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                    Text(text.fullDate(day))
                    Text(text.string(if (annotation.isMakeupWorkday) R.string.holidayMakeupWorkday else R.string.holidayRestDay))
                    if (annotation.isEstimated) Text(Strings.holidayEstimatedYearWarning(resources, LeavePlannerSchedule.date(day).year.toString()))
                }
            },
            confirmButton = { TextButton(onClick = { selectedHoliday = null }) { Text(text.string(R.string.close)) } },
        )
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
private fun CalendarDay(day: Int, page: LeavePlanCalendarPage, proposal: LeavePlanProposal, kind: LeaveMark?, text: LeaveText, modifier: Modifier, holiday: HolidayDayAnnotation?, minimumHeight: Dp, onHoliday: () -> Unit) {
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
    val density = LocalDensity.current
    val dateSlotHeight = with(density) { MaterialTheme.typography.bodyMedium.lineHeight.toDp() }
    val captionSlotHeight = DoneAtLeaveTokens.markSize * density.fontScale
    val label = listOfNotNull(text.day(day), holiday?.description(text.string(R.string.holidayMakeupWorkday), text.string(R.string.holidayEstimatedLabel)), kind?.let { markLabel(it, text) }).joinToString(", ")
    val action = if (holiday != null) Modifier.clickable(role = Role.Button, onClick = onHoliday) else Modifier
    Box(modifier.heightIn(min = minimumHeight).then(action).clearAndSetSemantics {
        contentDescription = label
        if (holiday != null) {
            role = Role.Button
            onClick { onHoliday(); true }
        }
    }, contentAlignment = Alignment.Center) {
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
        if (holiday != null && isLeave) MarkIcon(kind, Modifier.align(Alignment.TopEnd).padding(DoneAtSpacing.xxs).size(DoneAtLeaveTokens.markSize)
            .graphicsLayer { this.alpha = alpha; scaleX = iconScale; scaleY = iconScale })
        Column(Modifier.fillMaxWidth().padding(vertical = DoneAtSpacing.xxs), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs)) {
            Box(Modifier.fillMaxWidth().heightIn(min = dateSlotHeight), contentAlignment = Alignment.Center) {
                Text(
                    text.wholeNumber(LeavePlannerSchedule.date(day).dayOfMonth),
                    style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum", lineHeight = MaterialTheme.typography.bodyMedium.fontSize),
                    fontWeight = if (kind == null) FontWeight.Normal else FontWeight.SemiBold,
                    color = if (kind != null || page.contains(day)) scheme.onSurface else scheme.onSurface.copy(alpha = DoneAtLeaveTokens.inactiveAlpha),
                )
            }
            Box(Modifier.fillMaxWidth().heightIn(min = captionSlotHeight).graphicsLayer { this.alpha = alpha; scaleX = iconScale; scaleY = iconScale }, contentAlignment = Alignment.Center) {
                if (holiday != null) HolidayDayCaption(holiday)
                else if (kind != null) MarkIcon(kind, Modifier.size(DoneAtLeaveTokens.markSize))
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

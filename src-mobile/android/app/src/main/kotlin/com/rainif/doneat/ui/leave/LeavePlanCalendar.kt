package com.rainif.doneat.ui.leave

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Luggage
import androidx.compose.material.icons.outlined.Contrast
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtLeave322Tokens
import com.rainif.doneat.core.designsystem.DoneAtLeaveTokens
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.leave.LeavePlanProposal
import com.rainif.doneat.core.domain.leave.LeavePlannerSchedule
import com.rainif.doneat.core.domain.leave.LeavePresentation
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.schedule.HolidayDayAnnotation
import com.rainif.doneat.ui.schedule.holidayDayAnnotation
import java.time.DayOfWeek
import java.time.format.TextStyle

/** Only the weeks around the break, with one continuous green band per week. */
@Composable
internal fun LeavePlanCalendar(proposal: LeavePlanProposal, text: LeaveText, firstWeekday: DayOfWeek, modifier: Modifier = Modifier,
    holidays: HolidayCalendar = HolidayCalendar.EMPTY, holidayRegion: String? = null,
) {
    val calendar = remember(proposal, firstWeekday) { LeavePresentation.calendar(proposal, firstWeekday) }
    var selectedHoliday by remember(proposal) { mutableStateOf<Pair<Int, HolidayDayAnnotation>?>(null) }
    val resources = LocalResources.current
    val rest = leaveRestColor()
    Column(modifier, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
        Row(Modifier.clearAndSetSemantics {}) {
            (0 until 7).forEach { column ->
                Text(DayOfWeek.of(Math.floorMod(firstWeekday.value - 1 + column, 7) + 1).getDisplayName(TextStyle.NARROW_STANDALONE, text.locale),
                    Modifier.weight(1f), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            }
        }
        calendar.weeks.forEachIndexed { index, week ->
            val firstDay = week.days.first()
            if (index == 0 || LeavePlannerSchedule.date(firstDay).month != LeavePlannerSchedule.date(calendar.weeks[index - 1].days.first()).month) {
                Text(text.month(firstDay), Modifier.padding(top = if (index == 0) DoneAtSpacing.xs else DoneAtSpacing.s),
                    style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(Modifier.heightIn(min = DoneAtLeave322Tokens.calendarDayMinimum)) {
                Row(Modifier.fillMaxWidth()) {
                    week.days.forEach { day ->
                        val kind = LeavePresentation.kind(proposal, day)
                        val holiday = holidayDayAnnotation(holidays, holidayRegion, LeavePlannerSchedule.date(day), text.locale)
                        val label = listOfNotNull(text.day(day), dayLabel(kind, text),
                            holiday?.description(text.string(R.string.holidayMakeupWorkday), text.string(R.string.holidayEstimatedLabel))).joinToString(", ")
                        Column(Modifier.weight(1f).then(if (holiday == null) Modifier else Modifier.clickable(role = Role.Button) { selectedHoliday = day to holiday })
                            .clearAndSetSemantics {
                                contentDescription = label
                                if (holiday != null) { role = Role.Button; onClick { selectedHoliday = day to holiday; true } }
                            }.padding(vertical = DoneAtSpacing.xs), horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs)) {
                            Text(text.wholeNumber(LeavePlannerSchedule.date(day).dayOfMonth),
                                style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                                fontWeight = if (kind == LeavePresentation.DayKind.WORK) FontWeight.Normal else FontWeight.SemiBold)
                            Box(Modifier.heightIn(min = DoneAtLeaveTokens.markSize), contentAlignment = Alignment.Center) {
                                CalendarMark(kind)
                            }
                        }
                    }
                }
                // Put the label on the first widest overlap, not on a one-day opening fragment.
                week.breakColumns?.let { columns ->
                    BoxWithConstraints(Modifier.fillMaxWidth().clearAndSetSemantics {}) {
                        val cell = maxWidth / 7
                        Row {
                            Spacer(Modifier.width(cell * columns.first))
                            Box(Modifier.width(cell * columns.count()).padding(horizontal = DoneAtSpacing.xxs)
                                .background(rest.copy(alpha = DoneAtLeave322Tokens.restBandAlpha), RoundedCornerShape(DoneAtLeave322Tokens.bandCorner))
                                .heightIn(min = DoneAtLeave322Tokens.bandMinimumHeight).padding(horizontal = DoneAtSpacing.xxs), contentAlignment = Alignment.CenterStart) {
                                if (calendar.labelWeek == index) Text(Strings.leaveDaysOff(resources, proposal.fullRestDays), style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.SemiBold, color = leaveRestTextColor())
                            }
                        }
                    }
                }
            }
        }
        FlowRow(Modifier.fillMaxWidth().padding(top = DoneAtSpacing.s), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
            val kinds = (proposal.firstRestDayNumber..proposal.lastRestDayNumber).map { LeavePresentation.kind(proposal, it) } + proposal.items.map { LeavePresentation.kind(proposal, it.dayNumber) }
            listOf(LeavePresentation.DayKind.LEAVE, LeavePresentation.DayKind.HALF_LEAVE, LeavePresentation.DayKind.HOLIDAY).filter { it in kinds }.forEach { kind ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    CalendarMark(kind)
                    Text(dayLabel(kind, text).orEmpty(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                Box(Modifier.width(DoneAtSpacing.m).heightIn(min = DoneAtLeave322Tokens.barHeight)
                    .background(rest.copy(alpha = DoneAtLeave322Tokens.restBandAlpha), RoundedCornerShape(DoneAtLeave322Tokens.bandCorner)).clearAndSetSemantics {})
                Text(text.string(R.string.leaveLegendBreak), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    selectedHoliday?.let { (day, annotation) ->
        AlertDialog(onDismissRequest = { selectedHoliday = null }, title = { Text(annotation.name) }, text = {
            Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                Text(text.fullDate(day))
                Text(text.string(if (annotation.isMakeupWorkday) R.string.holidayMakeupWorkday else R.string.holidayRestDay))
                if (annotation.isEstimated) Text(Strings.holidayEstimatedYearWarning(resources, LeavePlannerSchedule.date(day).year.toString()))
            }
        }, confirmButton = { TextButton(onClick = { selectedHoliday = null }) { Text(text.string(R.string.close)) } })
    }
}

@Composable
private fun CalendarMark(kind: LeavePresentation.DayKind) {
    val icon = when (kind) {
        LeavePresentation.DayKind.LEAVE -> Icons.Filled.Luggage
        LeavePresentation.DayKind.HALF_LEAVE -> Icons.Outlined.Contrast
        LeavePresentation.DayKind.HOLIDAY -> Icons.Outlined.WbSunny
        else -> null
    }
    icon?.let { Icon(it, null, Modifier.size(DoneAtLeaveTokens.markSize), tint = if (kind == LeavePresentation.DayKind.HOLIDAY) leaveRestColor() else MaterialTheme.colorScheme.primary) }
}

private fun dayLabel(kind: LeavePresentation.DayKind, text: LeaveText): String? = when (kind) {
    LeavePresentation.DayKind.LEAVE -> text.string(R.string.leaveDayLeave)
    LeavePresentation.DayKind.HALF_LEAVE -> text.string(R.string.leaveDayHalf)
    LeavePresentation.DayKind.HOLIDAY -> text.string(R.string.leaveDayHoliday)
    LeavePresentation.DayKind.REST -> text.string(R.string.leaveDayRest)
    LeavePresentation.DayKind.WORK -> null
}

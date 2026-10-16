package com.rainif.doneat.ui.leave

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtLeave322Tokens
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.leave.LeavePlanProposal
import com.rainif.doneat.core.domain.leave.LeavePresentation
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.onboarding.appIsDark

@Composable
internal fun leaveRestColor(): Color = if (appIsDark()) DoneAtLeave322Tokens.restDark else DoneAtLeave322Tokens.restLight

@Composable
internal fun leaveRestTextColor(): Color = if (appIsDark()) DoneAtLeave322Tokens.restTextDark else DoneAtLeave322Tokens.restTextLight

@Composable
internal fun LeaveHeroNumber(full: String, number: String, modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.onSurface) {
    val position = full.indexOf(number)
    val headline = MaterialTheme.typography.headlineLarge
    val value = buildAnnotatedString {
        if (position < 0) append(full) else {
            append(full.substring(0, position))
            withStyle(SpanStyle(fontSize = headline.fontSize, fontWeight = FontWeight.SemiBold)) { append(number) }
            append(full.substring(position + number.length))
        }
    }
    Text(value, modifier, style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = "tnum"), color = color)
}

@Composable
internal fun LeaveBalanceBar(bar: LeavePresentation.BalanceBar, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    BoxWithConstraints(modifier.fillMaxWidth().height(DoneAtLeave322Tokens.barHeight).clearAndSetSemantics {}) {
        val total = bar.total.coerceAtLeast(1).toFloat()
        val availableWidth = maxWidth
        Row(Modifier.fillMaxWidth().height(DoneAtLeave322Tokens.barHeight).clip(RoundedCornerShape(DoneAtLeave322Tokens.barHeight)).background(scheme.surfaceContainerHighest)) {
            if (bar.used > 0) Box(Modifier.width(availableWidth * (bar.used / total)).height(DoneAtLeave322Tokens.barHeight)
                .background(scheme.onSurfaceVariant.copy(alpha = DoneAtLeave322Tokens.usedAlpha)))
            if (bar.planned > 0) Box(Modifier.width(availableWidth * (bar.planned / total)).height(DoneAtLeave322Tokens.barHeight).background(scheme.primary))
        }
    }
}

@Composable
internal fun leaveStripTint(kind: LeavePresentation.DayKind): Color = when (kind) {
    LeavePresentation.DayKind.LEAVE, LeavePresentation.DayKind.HALF_LEAVE -> MaterialTheme.colorScheme.primary
    LeavePresentation.DayKind.HOLIDAY -> leaveRestColor()
    LeavePresentation.DayKind.REST -> leaveRestColor().copy(alpha = DoneAtLeave322Tokens.weekendAlpha)
    LeavePresentation.DayKind.WORK -> MaterialTheme.colorScheme.surfaceContainerHighest
}

/** A shared width per day across the whole list makes break lengths comparable. */
@Composable
internal fun LeaveDayStrip(proposal: LeavePlanProposal, longest: Int, modifier: Modifier = Modifier) {
    val kinds = LeavePresentation.strip(proposal)
    BoxWithConstraints(modifier.fillMaxWidth().clearAndSetSemantics {}) {
        val count = longest.coerceAtLeast(1)
        val gap = if (maxWidth / count < DoneAtLeave322Tokens.stripMaximumCell / 2)
            minOf(DoneAtLeave322Tokens.stripGap / 2, maxWidth / (count * 2)) else DoneAtLeave322Tokens.stripGap
        val cell = minOf(DoneAtLeave322Tokens.stripMaximumCell, (maxWidth - gap * (count - 1)) / count)
            .coerceAtLeast(Dp.Hairline)
        Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
            kinds.forEach { kind ->
                Box(Modifier.width(cell), contentAlignment = Alignment.CenterEnd) {
                    Box(Modifier.width(if (kind == LeavePresentation.DayKind.HALF_LEAVE) cell / 2 else cell)
                        .height(DoneAtLeave322Tokens.barHeight).background(leaveStripTint(kind), RoundedCornerShape(DoneAtLeave322Tokens.stripCorner)))
                }
            }
        }
    }
}

@Composable
internal fun LeaveStripLegend(text: LeaveText) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
        listOf(LeavePresentation.DayKind.LEAVE to R.string.leaveDayLeave,
            LeavePresentation.DayKind.HOLIDAY to R.string.leaveDayHoliday,
            LeavePresentation.DayKind.REST to R.string.leaveLegendWeekend,
            LeavePresentation.DayKind.WORK to R.string.leaveLegendWork).forEach { (kind, label) ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                Box(Modifier.width(DoneAtSpacing.m).height(DoneAtLeave322Tokens.barHeight).background(leaveStripTint(kind), MaterialTheme.shapes.extraSmall).clearAndSetSemantics {})
                Text(text.string(label), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
internal fun LeaveProposalHeadline(proposal: LeavePlanProposal, text: LeaveText, modifier: Modifier = Modifier, holidayName: String? = null) {
    val resources = LocalResources.current
    Column(modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
        Text(if (proposal.costHalfDays == 0) text.string(R.string.leaveNoLeaveNeeded)
            else Strings.leaveAskFor(resources, text.halfDays(proposal.costHalfDays)),
            style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
        LeaveHeroNumber(Strings.leaveDaysOff(resources, proposal.fullRestDays), text.wholeNumber(proposal.fullRestDays),
            Modifier.semantics { heading() }, leaveRestTextColor())
        Text(listOfNotNull(text.range(text.fullDate(proposal.firstRestDayNumber), text.fullDate(proposal.lastRestDayNumber)), holidayName).joinToString(" · "),
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun LeaveBridgeCard(proposal: LeavePlanProposal, text: LeaveText) {
    val resources = LocalResources.current
    val rest = leaveRestColor()
    val middle: @Composable () -> Unit = {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs),
            modifier = Modifier.semantics(mergeDescendants = true) {}) {
            Icon(Icons.Outlined.WbSunny, null, tint = rest)
            Text(Strings.leaveDaysOff(resources, proposal.fullRestDays), style = MaterialTheme.typography.labelMedium, color = leaveRestTextColor())
        }
    }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        if (maxWidth < DoneAtLeave322Tokens.bridgeStackWidth || LocalDensity.current.fontScale >= DoneAtLeave322Tokens.bridgeStackFontScale) {
            Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), horizontalAlignment = Alignment.CenterHorizontally) {
                LeaveBridgeEndpoint(R.string.leaveLastShiftEnds, proposal.lastShiftEndAtMs, text, Modifier.fillMaxWidth())
                middle()
                LeaveBridgeEndpoint(R.string.leaveNextShiftStarts, proposal.nextShiftStartAtMs, text, Modifier.fillMaxWidth())
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                LeaveBridgeEndpoint(R.string.leaveLastShiftEnds, proposal.lastShiftEndAtMs, text, Modifier.weight(1f))
                Box(Modifier.width(DoneAtLeave322Tokens.bridgeMiddleWidth), contentAlignment = Alignment.Center) { middle() }
                LeaveBridgeEndpoint(R.string.leaveNextShiftStarts, proposal.nextShiftStartAtMs, text, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun LeaveBridgeEndpoint(label: Int, instant: Double?, text: LeaveText, modifier: Modifier = Modifier) {
    Column(modifier.background(MaterialTheme.colorScheme.surfaceContainerLow, MaterialTheme.shapes.medium)
        .padding(DoneAtSpacing.m).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
        Text(text.string(label), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(instant?.let(text::time) ?: "—", style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = "tnum"))
        instant?.let { Text(text.momentDay(it), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

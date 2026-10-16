package com.rainif.doneat.plus

import android.text.format.DateFormat
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.*
import com.rainif.doneat.core.domain.leave.LeavePlanItem
import com.rainif.doneat.core.domain.leave.LeavePlanProposal
import com.rainif.doneat.core.domain.leave.LeavePlannerSchedule
import com.rainif.doneat.core.domain.schedule.LeavePortion
import com.rainif.doneat.ui.leave.LeavePlanCalendar
import com.rainif.doneat.ui.leave.LeaveText
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.timer.TimerText
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle
import java.text.NumberFormat

/** Shared illustrative modules; they never start a session or write a record. */
enum class PlusDemoKind { RECORDS, REPORTS, FOCUS, REST }

/** Purchase stays manual: three tabs share the onboarding demos without an autoplaying price page. */
@Composable
fun PlusFeatureStage(modifier: Modifier = Modifier, initialSelection: PlusDemoKind = PlusDemoKind.REPORTS, showsFocus: Boolean = true) {
    val choices = if (showsFocus) listOf(PlusDemoKind.REPORTS, PlusDemoKind.REST, PlusDemoKind.FOCUS)
        else listOf(PlusDemoKind.REPORTS, PlusDemoKind.REST)
    var selected by rememberSaveable { mutableStateOf(initialSelection.takeIf { it in choices } ?: PlusDemoKind.REPORTS) }
    val still = showcaseStill()
    val stacked = LocalDensity.current.fontScale >= 1.5f
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
        @Composable
        fun tab(kind: PlusDemoKind, modifier: Modifier) {
            val fullLabel = stringResource(when (kind) {
                PlusDemoKind.REST -> R.string.leavePlanAction
                PlusDemoKind.FOCUS -> R.string.plusBenefitFocus
                else -> R.string.reportEntryTitle
            })
            TextButton(onClick = { selected = kind }, modifier = modifier.semantics {
                this.selected = selected == kind
                contentDescription = fullLabel
            }) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    Icon(when (kind) { PlusDemoKind.REST -> Icons.Outlined.WbTwilight; PlusDemoKind.FOCUS -> Icons.Outlined.Timer; else -> Icons.Outlined.BarChart }, null, tint = if (selected == kind) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(when (kind) { PlusDemoKind.REST -> R.string.leavePlanAction; PlusDemoKind.FOCUS -> R.string.plusBenefitFocus; else -> R.string.reportEntryShort }),
                        modifier = Modifier.clearAndSetSemantics {}, style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.Center,
                        color = if (selected == kind) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (stacked) Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            choices.forEach { kind -> tab(kind, Modifier.fillMaxWidth().background(
                if (selected == kind) MaterialTheme.colorScheme.primary.copy(alpha = .10f) else Color.Transparent, MaterialTheme.shapes.medium)) }
        } else Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            choices.forEach { kind -> tab(kind, Modifier.weight(1f).background(
                if (selected == kind) MaterialTheme.colorScheme.primary.copy(alpha = .10f) else Color.Transparent, MaterialTheme.shapes.medium)) }
        }
        AnimatedContent(selected, transitionSpec = {
            val duration = if (still) DoneAtMotion.REDUCED_MS else DoneAtMotion.SELECTION_MS
            (fadeIn(tween(duration)) togetherWith fadeOut(tween(duration))).using(null)
        }, label = "plusFeatureStage") { kind -> PlusFeatureDemo(kind, isActive = kind == selected) }
        Text(stringResource(when (selected) { PlusDemoKind.REST -> R.string.onboardingPlusRestTitle; PlusDemoKind.FOCUS -> R.string.onboardingPlusFocusTitle; else -> R.string.onboardingPlusReportsTitle }),
            Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
        Text(stringResource(R.string.plusIllustration), Modifier.fillMaxWidth(), textAlign = TextAlign.Center,
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Flexible height for accessibility lists. Every newly active module replays its source entrance. */
@Composable
fun PlusFeatureDemo(kind: PlusDemoKind, modifier: Modifier = Modifier, isActive: Boolean = true) {
    val still = showcaseStill()
    val phase by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val progress = remember(kind) { Animatable(if (still) 1f else 0f) }
    LaunchedEffect(kind, isActive, still, phase) {
        when {
            still -> progress.snapTo(1f)
            !isActive -> progress.snapTo(0f)
            phase.isAtLeast(Lifecycle.State.RESUMED) -> progress.animateTo(1f,
                tween(DoneAtOfferTokens.SHOWCASE_TOTAL_MS, easing = LinearEasing))
        }
    }
    val value = if (still) 1f else progress.value
    CompositionLocalProvider(LocalDoneAtMotion provides DoneAtMotion(still)) {
        when (kind) {
            PlusDemoKind.RECORDS -> RecordsFeatureDemo(value, modifier.showcaseEntrance(value))
            PlusDemoKind.REPORTS -> ReportsFeatureDemo(value, modifier.showcaseEntrance(value))
            PlusDemoKind.FOCUS -> FocusFeatureDemo(value, modifier.showcaseEntrance(value))
            PlusDemoKind.REST -> RestFeatureDemo(value, modifier.showcaseEntrance(value))
        }
    }
}

private fun Modifier.showcaseEntrance(progress: Float): Modifier = graphicsLayer {
    val entrance = DoneAtOfferTokens.fraction(progress, 0)
    alpha = entrance
    translationY = DoneAtOfferTokens.showcaseOffset.toPx() * (1 - entrance)
}

@Composable
private fun showcaseStill(): Boolean = LocalDoneAtMotion.current.reduced ||
    offerTouchExplorationEnabled() || LocalDensity.current.fontScale >= 1.5f

@Composable
private fun demoText(): TimerText {
    val context = LocalContext.current
    return TimerText(LocalResources.current, LocalConfiguration.current.locales[0], DateFormat.is24HourFormat(context), false)
}

@Composable
private fun DemoCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLowest,
        border = BorderStroke(DoneAtSpacing.xxs / 2, MaterialTheme.colorScheme.outlineVariant.copy(alpha = .35f))) {
        Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), content = content)
    }
}

@Composable
private fun DemoLabel(title: Int, icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        Icon(icon, null, Modifier.size(DoneAtSpacing.l))
        Text(stringResource(title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun RecordsFeatureDemo(p: Float, modifier: Modifier) {
    val colors = LocalDoneAtRecordsColors.current
    val marker = MaterialTheme.colorScheme.onSurface
    val stacked = LocalDensity.current.fontScale >= 1.5f
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
        DemoCard {
            DemoLabel(R.string.recordsTitle, Icons.Outlined.CalendarMonth)
            TimelineExample(R.string.recordsPlanned, "09:00–18:00", true, 1f)
            TimelineExample(R.string.onboardingPlusRecordsActual, "09:08–18:42", false, DoneAtOfferTokens.fraction(p, 200))
        }
        val entrance = DoneAtOfferTokens.fraction(p, 300, DoneAtOfferTokens.SHOWCASE_STEP_MS)
        DemoCard(Modifier.graphicsLayer {
            alpha = entrance
            translationY = DoneAtOfferTokens.showcaseOffset.toPx() * (1 - entrance)
        }) {
            DemoLabel(R.string.lifeProfileTitle, Icons.Outlined.AccountCircle)
            // Final Life grammar: each year is a dot, solid for lived years
            // and outlined for future years, grouped into visible age rows.
            Canvas(Modifier.fillMaxWidth().height(DoneAtWelcome322Tokens.previewDotHeight).clearAndSetSemantics {}) {
                val columns = 20
                val rows = 4
                val cellWidth = size.width / columns
                val cellHeight = size.height / rows
                val radius = minOf(cellWidth, cellHeight) * .24f
                val current = 18 + (27 * DoneAtOfferTokens.fraction(p, 400)).toInt()
                for (year in 0 until columns * rows) {
                    val color = when {
                        year < 18 -> colors.childhood
                        year < 26 -> colors.study
                        year < 65 -> colors.lifeWork
                        else -> colors.retirement
                    }
                    val center = Offset((year % columns + .5f) * cellWidth, (year / columns + .5f) * cellHeight)
                    if (year <= current) drawCircle(color, radius, center)
                    else drawCircle(color.copy(alpha = DoneAtRecordsStyle.estimateStrokeOpacity), radius, center,
                        style = Stroke(DoneAtSpacing.xxs.toPx() / 2))
                    if (year == current) drawCircle(marker, radius + DoneAtSpacing.xxs.toPx(), center,
                        style = Stroke(DoneAtSpacing.xxs.toPx() / 2))
                }
            }
            if (stacked) Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                listOf(R.string.lifeStageChildhood, R.string.lifeStagePresent, R.string.lifeStageRetirement).forEach {
                    Text(stringResource(it), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                listOf(R.string.lifeStageChildhood, R.string.lifeStagePresent, R.string.lifeStageRetirement).forEach {
                    Text(stringResource(it), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun TimelineExample(title: Int, time: String, planned: Boolean, progress: Float) {
    val colors = LocalDoneAtRecordsColors.current
    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(stringResource(title), style = MaterialTheme.typography.labelMedium)
            Text(time, style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum",
                textDirection = androidx.compose.ui.text.style.TextDirection.Ltr), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Canvas(Modifier.fillMaxWidth().height(DoneAtOfferTokens.timelineHeight).clearAndSetSemantics {}) {
            val gap = size.width * .08f
            val first = size.width * .41f * progress
            val second = size.width * (if (planned) .43f else .39f) * progress
            val stroke = Stroke(DoneAtSpacing.xxs.toPx() / 2)
            val inset = stroke.width / 2
            fun segment(x: Float, width: Float) {
                if (width <= stroke.width) return
                if (planned) drawRoundRect(colors.work.copy(alpha = DoneAtRecordsStyle.estimateStrokeOpacity),
                    Offset(x + inset, inset), Size(width - stroke.width, size.height - stroke.width),
                    CornerRadius(size.height / 2), style = stroke)
                else drawRoundRect(colors.work, Offset(x, 0f), Size(width, size.height), CornerRadius(size.height / 2))
            }
            segment(0f, first)
            segment(size.width * .41f + gap, second)
            if (!planned) drawRoundRect(colors.overtime, Offset(size.width * .88f, 0f),
                Size(size.width * .12f * progress, size.height), CornerRadius(size.height / 2))
        }
    }
}

@Composable
private fun ReportsFeatureDemo(p: Float, modifier: Modifier) {
    val text = demoText()
    val total = text.hours(41.0)
    val reportColors = DoneAtReportPalette
    val locale = LocalConfiguration.current.locales[0]
    val big = LocalDensity.current.fontScale >= 1.5f
    Column(modifier.fillMaxWidth().heightIn(min = DoneAtOfferTokens.reportMinimumHeight)
        .background(Brush.verticalGradient(listOf(reportColors.plum, reportColors.deep)), MaterialTheme.shapes.large)
        .padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.reportWeekly), style = MaterialTheme.typography.labelLarge, color = reportColors.cream.copy(alpha = .7f))
            Icon(Icons.Outlined.PlayArrow, null, Modifier.size(DoneAtSpacing.l), tint = reportColors.cream.copy(alpha = .7f))
        }
        Text(Strings.reportHeadlineOvertime(LocalResources.current, text.hours(2.0)), style = MaterialTheme.typography.titleMedium,
            color = reportColors.cream, fontWeight = FontWeight.SemiBold)
        DoneAtCountdown(if (p * DoneAtOfferTokens.SHOWCASE_TOTAL_MS < 200) text.hours(0.0) else total, total,
            color = reportColors.orange, style = MaterialTheme.typography.headlineLarge.copy(fontSize = DoneAtOfferTokens.reportTotalSize, fontFeatureSettings = "tnum"), countsDown = false)
        Spacer(Modifier.height(DoneAtSpacing.s))
        Row(Modifier.fillMaxWidth().clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), verticalAlignment = Alignment.Bottom) {
            val work = listOf(8f, 8f, 8f, 8f, 7f, 0f, 0f)
            val overtime = listOf(.5f, 0f, 1.5f, 0f, 0f, 0f, 0f)
            for (day in 0..6) {
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    val reveal = DoneAtOfferTokens.fraction(p, 150 + day * 60)
                    Canvas(Modifier.fillMaxWidth().height(DoneAtOfferTokens.chartHeight)) {
                        val workHeight = if (work[day] > 0) size.height * work[day] / 9.5f else DoneAtSpacing.xs.toPx()
                        drawRoundRect(if (work[day] > 0) Brush.verticalGradient(listOf(reportColors.orange, reportColors.cream))
                            else Brush.verticalGradient(listOf(reportColors.control, reportColors.control)),
                            Offset(0f, size.height - workHeight * reveal), Size(size.width, workHeight * reveal), CornerRadius(DoneAtSpacing.xs.toPx()))
                        if (overtime[day] > 0) {
                            val overtimeHeight = size.height * overtime[day] / 9.5f * reveal
                            drawRoundRect(Brush.verticalGradient(listOf(reportColors.hot, reportColors.orange)),
                                Offset(0f, size.height - workHeight * reveal - overtimeHeight - DoneAtSpacing.xxs.toPx()),
                                Size(size.width, overtimeHeight), CornerRadius(DoneAtSpacing.xs.toPx()))
                        }
                    }
                    Text(DayOfWeek.of(day + 1).getDisplayName(if (big) TextStyle.NARROW_STANDALONE else TextStyle.SHORT_STANDALONE, locale),
                        style = MaterialTheme.typography.labelSmall, color = reportColors.cream.copy(alpha = .6f), maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun FocusFeatureDemo(p: Float, modifier: Modifier) {
    val text = demoText()
    val progress = .04f + .60f * DoneAtOfferTokens.fraction(p, 200, 1_000)
    val time = if (p * DoneAtOfferTokens.SHOWCASE_TOTAL_MS < 200) "25:00" else "09:00"
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
        DemoCard {
            DemoLabel(R.string.onboardingPlusFocusTask, Icons.Outlined.Timer)
            DoneAtCountdown(time, time, color = MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.headlineLarge.copy(fontFeatureSettings = "tnum"))
            val scheme = MaterialTheme.colorScheme
            Canvas(Modifier.fillMaxWidth().height(DoneAtOfferTokens.timelineHeight).clearAndSetSemantics {}) {
                drawRoundRect(scheme.surfaceContainerHighest, cornerRadius = CornerRadius(size.height / 2))
                drawRoundRect(scheme.primary, size = Size(size.width * progress, size.height), cornerRadius = CornerRadius(size.height / 2))
            }
            Text(Strings.focusActivityThenBreak(LocalResources.current, NumberFormat.getIntegerInstance(text.locale).format(5)),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val entrance = DoneAtOfferTokens.fraction(p, 390, DoneAtOfferTokens.SHOWCASE_STEP_MS)
        DemoCard(Modifier.graphicsLayer { alpha = entrance; translationY = DoneAtOfferTokens.showcaseOffset.toPx() * (1 - entrance) }) {
            Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Coffee, null, Modifier.size(DoneAtSpacing.xxl), tint = MaterialTheme.colorScheme.primary)
                Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs)) {
                    Text(stringResource(R.string.focusShortBreak), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text(stringResource(R.string.onboardingPlusFocusBreakBody), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun RestFeatureDemo(p: Float, modifier: Modifier) {
    val scheme = MaterialTheme.colorScheme
    val text = demoText()
    val zone = ZoneId.systemDefault()
    val sampleDay = LocalDate.of(2026, 9, 25)
    val resources = LocalResources.current
    val use24Hour = DateFormat.is24HourFormat(LocalContext.current)
    val leaveText = remember(resources, text.locale, zone, use24Hour) { LeaveText(resources, text.locale, zone, use24Hour) }
    val proposal = remember { restDemoProposal() }
    val firstWeekday = java.time.temporal.WeekFields.of(text.locale).firstDayOfWeek
    fun clock(hour: Int) = text.time(sampleDay.atTime(hour, 0).atZone(zone).toInstant().toEpochMilli().toDouble())
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
        DemoCard {
            DemoLabel(R.string.leaveTitle, Icons.Outlined.Luggage)
            // Render the same read-only calendar as a real result: date,
            // suitcase/half-day/sun mark, then the continuous green break band.
            // The shared projection chooses the first widest week for its label.
            LeavePlanCalendar(proposal, leaveText, firstWeekday)
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                Text(Strings.leaveDaysOff(LocalResources.current, proposal.fullRestDays), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(Strings.leaveUses(LocalResources.current, leaveText.halfDays(proposal.costHalfDays)), style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
            }
        }

        val entrance = DoneAtOfferTokens.fraction(p, 480, DoneAtOfferTokens.SHOWCASE_STEP_MS)
        DemoCard(Modifier.graphicsLayer { alpha = entrance; translationY = DoneAtOfferTokens.showcaseOffset.toPx() * (1 - entrance) }) {
            DemoLabel(R.string.shiftAlarmsTitle, Icons.Outlined.Alarm)
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                Text(clock(7), style = MaterialTheme.typography.headlineSmall.copy(fontFeatureSettings = "tnum"), fontWeight = FontWeight.SemiBold)
                Text(Strings.shiftAlarmTitle(LocalResources.current, stringResource(R.string.extendedDefaultWorkShift), clock(8)),
                    style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
            }
        }

    }
}

/** An illustrative nine-day break plus an early half day; no user schedule is read or changed. */
private fun restDemoProposal(): LeavePlanProposal {
    val first = LocalDate.of(2026, 9, 26)
    val last = first.plusDays(8)
    fun item(date: LocalDate, portion: LeavePortion, role: LeavePlanItem.Role) = LeavePlanItem(
        LeavePlannerSchedule.dayNumber(date), date.toString(), portion, emptyList(), emptyList(), role,
    )
    val items = listOf(item(first.minusDays(1), LeavePortion.SECOND_HALF, LeavePlanItem.Role.EARLY_DEPARTURE)) +
        (2L..4L).map { offset -> item(first.plusDays(offset), LeavePortion.WHOLE, LeavePlanItem.Role.BRIDGE) }
    return LeavePlanProposal(
        firstRestDayNumber = LeavePlannerSchedule.dayNumber(first), lastRestDayNumber = LeavePlannerSchedule.dayNumber(last),
        firstRestDayKey = first.toString(), lastRestDayKey = last.toString(), items = items, uses = emptyList(),
        lastShiftEndAtMs = null, nextShiftStartAtMs = null,
        dayKinds = listOf(LeavePlanProposal.DayKind.REST, LeavePlanProposal.DayKind.REST,
            LeavePlanProposal.DayKind.LEAVE, LeavePlanProposal.DayKind.LEAVE, LeavePlanProposal.DayKind.LEAVE,
            LeavePlanProposal.DayKind.HOLIDAY, LeavePlanProposal.DayKind.HOLIDAY,
            LeavePlanProposal.DayKind.REST, LeavePlanProposal.DayKind.REST),
        caveats = emptySet(),
    )
}

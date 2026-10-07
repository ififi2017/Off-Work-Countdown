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
            TextButton(onClick = { selected = kind }, modifier = modifier.semantics { this.selected = selected == kind }) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    Icon(when (kind) { PlusDemoKind.REST -> Icons.Outlined.WbTwilight; PlusDemoKind.FOCUS -> Icons.Outlined.Timer; else -> Icons.Outlined.BarChart }, null, tint = if (selected == kind) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(when (kind) { PlusDemoKind.REST -> R.string.leavePlanAction; PlusDemoKind.FOCUS -> R.string.plusBenefitFocus; else -> R.string.reportEntryTitle }),
                        style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.Center,
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
            Canvas(Modifier.fillMaxWidth().height(DoneAtOfferTokens.lifeHeight).clearAndSetSemantics {}) {
                val gap = DoneAtSpacing.xxs.toPx() * 1.5f
                val usable = (size.width - gap * 3).coerceAtLeast(0f)
                val parts = listOf(.18f to colors.childhood, .16f to colors.study, .42f to colors.lifeWork, .24f to colors.retirement)
                var x = 0f
                parts.forEach { (width, color) ->
                    drawRoundRect(color, Offset(x, 0f), Size(usable * width, size.height), CornerRadius(size.height / 2))
                    x += usable * width + gap
                }
                val position = .18f + .38f * DoneAtOfferTokens.fraction(p, 400)
                drawRoundRect(marker, Offset(size.width * position, 0f), Size(DoneAtOfferTokens.lifeMarkerWidth.toPx(), size.height), CornerRadius(1.dp.toPx()))
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
            Text(time, style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Canvas(Modifier.fillMaxWidth().height(DoneAtOfferTokens.timelineHeight).clearAndSetSemantics {}) {
            val gap = size.width * .08f
            val first = size.width * .41f * progress
            val second = size.width * (if (planned) .43f else .39f) * progress
            val color = colors.work.copy(alpha = if (planned) .24f else 1f)
            drawRoundRect(color, Offset.Zero, Size(first, size.height), CornerRadius(size.height / 2))
            drawRoundRect(color, Offset(size.width * .41f + gap, 0f), Size(second, size.height), CornerRadius(size.height / 2))
            if (planned) {
                // Planned time is hatched as on the real records surface; actual time is solid.
                val step = DoneAtSpacing.xs.toPx()
                for (x in 0..(size.width / step).toInt()) {
                    val start = x * step
                    if (start < first || start > size.width * .49f && start < size.width * .92f) {
                        drawLine(colors.work.copy(alpha = .7f), Offset(start, size.height), Offset(start + step, 0f), 1.dp.toPx())
                    }
                }
            } else drawRoundRect(colors.overtime, Offset(size.width * .88f, 0f), Size(size.width * .12f * progress, size.height), CornerRadius(size.height / 2))
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
    val sampleDay = LocalDate.of(2026, 1, 5)
    fun clock(hour: Int) = text.time(sampleDay.atTime(hour, 0).atZone(zone).toInstant().toEpochMilli().toDouble())
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
        DemoCard {
            DemoLabel(R.string.leaveTitle, Icons.Outlined.Luggage)
            Row(Modifier.fillMaxWidth().clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                for (day in 0..8) {
                    val leave = day in 3..5
                    val reveal = if (leave) DoneAtOfferTokens.fraction(p, 250 + (day - 3) * 120, 500) else 1f
                    Surface(Modifier.weight(1f).height(DoneAtOfferTokens.timeOffCellHeight).graphicsLayer {
                        scaleX = .86f + .14f * reveal; scaleY = scaleX
                    }, shape = MaterialTheme.shapes.small,
                        color = if (leave) scheme.primary.copy(alpha = .16f * reveal) else scheme.surfaceContainerHighest) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(if (leave) Icons.Outlined.Luggage else Icons.Outlined.Flag, null,
                                Modifier.size(DoneAtOfferTokens.timeOffIconSize), tint = if (leave) scheme.primary else scheme.onSurfaceVariant)
                        }
                    }
                }
            }
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                Text(Strings.leaveDaysOff(LocalResources.current, 9), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(Strings.leaveUses(LocalResources.current, text.days(3.0)), style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
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

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
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
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
import androidx.compose.ui.graphics.asImageBitmap
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
import kotlinx.coroutines.launch
import com.rainif.doneat.core.domain.widget.*
import com.rainif.doneat.widget.DoneAtWidgetKind
import com.rainif.doneat.widget.widgetCardBitmap
import com.rainif.doneat.widget.widgetSuiteCard

/** Shared illustrative modules; they never start a session or write a record. */
enum class PlusDemoKind { RECORDS, REPORTS, FOCUS, REST }

private enum class PlusFeaturePage(val caption: Int) {
    REPORTS(R.string.onboardingPlusReportsTitle), RECORDS(R.string.onboardingPlusRecordsTitle),
    LIFE(R.string.plusBenefitLife), REST(R.string.onboardingPlusRestTitle),
    FOCUS(R.string.onboardingPlusFocusTitle), WIDGETS(R.string.plusWidgetsSlideTitle),
}

/** Manual paging only; the price page never auto-advances while someone decides. */
@Composable
fun PlusFeatureStage(modifier: Modifier = Modifier, initialSelection: PlusDemoKind = PlusDemoKind.REPORTS, showsFocus: Boolean = true) {
    val choices = remember(showsFocus) { PlusFeaturePage.entries.filter { showsFocus || it != PlusFeaturePage.FOCUS } }
    val initialPage = when (initialSelection) {
        PlusDemoKind.REPORTS -> PlusFeaturePage.REPORTS
        PlusDemoKind.RECORDS -> PlusFeaturePage.RECORDS
        PlusDemoKind.FOCUS -> PlusFeaturePage.FOCUS
        PlusDemoKind.REST -> PlusFeaturePage.REST
    }
    val pager = rememberPagerState(initialPage = choices.indexOf(initialPage).coerceAtLeast(0)) { choices.size }
    val scope = rememberCoroutineScope()
    val still = showcaseStill()
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        HorizontalPager(pager, Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) { index ->
            PlusCarouselScene(choices[index])
        }
        Text(stringResource(choices[pager.currentPage].caption), Modifier.fillMaxWidth(), textAlign = TextAlign.Center,
            style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            choices.forEachIndexed { index, page ->
                val label = stringResource(page.caption)
                Box(Modifier.size(32.dp).semantics { selected = index == pager.currentPage; contentDescription = label }
                    .clickable { scope.launch { if (still) pager.scrollToPage(index) else pager.animateScrollToPage(index) } },
                    contentAlignment = Alignment.Center) {
                    Box(Modifier.size(if (index == pager.currentPage) 18.dp else 7.dp, 7.dp)
                        .background(if (index == pager.currentPage) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant, CircleShape))
                }
            }
        }
        Text(stringResource(R.string.plusIllustration), Modifier.fillMaxWidth(), textAlign = TextAlign.Center,
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Compact, explicitly illustrative scenes. No account, purchase, schedule or record is mutated. */
@Composable
private fun PlusCarouselScene(page: PlusFeaturePage) {
    if (page == PlusFeaturePage.REPORTS) {
        ReportsFeatureDemo(1f, Modifier.fillMaxWidth())
        return
    }
    if (page == PlusFeaturePage.WIDGETS) {
        PlusWidgetsScene()
        return
    }
    val palette = DoneAtReportPalette
    val text = demoText()
    val locale = LocalConfiguration.current.locales[0]
    Column(Modifier.fillMaxWidth().heightIn(min = DoneAtOfferTokens.reportMinimumHeight)
        .background(Brush.verticalGradient(listOf(palette.plum, palette.deep)), MaterialTheme.shapes.large)
        .padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
        Text(stringResource(when (page) {
            PlusFeaturePage.RECORDS -> R.string.reportYearly
            PlusFeaturePage.LIFE -> R.string.lifeProfileTitle
            PlusFeaturePage.REST -> R.string.leaveTitle
            else -> R.string.onboardingPlusFocusTask
        }), style = MaterialTheme.typography.labelLarge, color = palette.cream.copy(alpha = .75f))
        if (page == PlusFeaturePage.FOCUS) {
            Box(Modifier.fillMaxWidth().height(170.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(156.dp).clearAndSetSemantics {}) {
                    val width = DoneAtSpacing.s.toPx()
                    drawCircle(palette.control, radius = size.minDimension / 2 - width, style = Stroke(width))
                    drawArc(palette.orange, -90f, 235f, false, Offset(width, width),
                        Size(size.width - 2 * width, size.height - 2 * width), style = Stroke(width, cap = androidx.compose.ui.graphics.StrokeCap.Round))
                }
                Text("18:24", style = MaterialTheme.typography.headlineLarge.copy(fontFeatureSettings = "tnum"),
                    fontWeight = FontWeight.Bold, color = palette.cream)
            }
        } else {
            Text(when (page) {
                PlusFeaturePage.RECORDS -> text.hours(1_846.0)
                PlusFeaturePage.LIFE -> NumberFormat.getPercentInstance(locale).format(.38)
                else -> Strings.leaveDaysOff(LocalResources.current, 9)
            }, style = MaterialTheme.typography.headlineLarge, color = palette.orange, fontWeight = FontWeight.Bold)
            Canvas(Modifier.fillMaxWidth().height(132.dp).clearAndSetSemantics {}) {
                val columns = when (page) { PlusFeaturePage.RECORDS -> 52; PlusFeaturePage.LIFE -> 24; else -> 7 }
                val count = when (page) { PlusFeaturePage.RECORDS -> 364; PlusFeaturePage.LIFE -> 240; else -> 14 }
                val rows = (count + columns - 1) / columns
                val cellWidth = size.width / columns
                val cellHeight = size.height / rows
                for (i in 0 until count) {
                    val color = when (page) {
                        PlusFeaturePage.RECORDS -> if (i % 7 >= 5) palette.control else palette.orange.copy(alpha = .35f + (i % 3) * .3f)
                        PlusFeaturePage.LIFE -> if (i < 91) palette.orange else if (i == 91) palette.cream else palette.control
                        else -> if (i in 7..10) palette.orange else if (i >= 5) palette.hot.copy(alpha = .4f) else palette.control
                    }
                    val inset = if (columns > 24) 1f else DoneAtSpacing.xxs.toPx()
                    val box = Size((cellWidth - inset * 2).coerceAtLeast(1f), (cellHeight - inset * 2).coerceAtLeast(1f))
                    if (page == PlusFeaturePage.LIFE) drawCircle(color, minOf(box.width, box.height) / 2,
                        Offset((i % columns + .5f) * cellWidth, (i / columns + .5f) * cellHeight))
                    else drawRoundRect(color, Offset(i % columns * cellWidth + inset, i / columns * cellHeight + inset), box,
                        CornerRadius(minOf(DoneAtSpacing.xs.toPx(), box.width / 3)))
                }
            }
        }
    }
}

/** Uses the launcher renderer with salary-free sample payloads, rather than unrelated marketing cards. */
@Composable
private fun PlusWidgetsScene() {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0].toLanguageTag()
    val now = remember { LocalDate.of(2026, 10, 19).atTime(15, 0).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli() }
    val access = WidgetAccess(true)
    val snapshot = remember(locale, now) {
        val midnight = LocalDate.of(2026, 10, 19).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val today = kotlin.math.floor(midnight / 86_400_000.0 + .5).toLong()
        WidgetSuiteSnapshot(generatedAtMs = now, locale = locale, timeZoneIdentifier = ZoneId.systemDefault().id,
            calendar = WidgetCalendarPayload(ZoneId.systemDefault().id, 1, WidgetCalendarScheduleKind.NONE),
            summary = WidgetSummaryPayload(access, listOf(WidgetSummaryPeriod(WidgetSummaryPeriodKind.WEEK, "", null,
                "2026-10-19", "2026-10-25", 31_600L * 3_600, 2 * 3_600_000L, 4, 5, 1, .8,
                listOf(8.0, 8.0, 8.0, 7.6, 0.0).mapIndexed { i, hours -> WidgetSummaryBar((i + 1).toString(),
                    (hours * 3_600_000).toLong(), if (i == 3) WidgetSummaryBarState.CURRENT else WidgetSummaryBarState.PAST) }))),
            life = WidgetLifePayload(access, bornDay = today - 11_470, careerStartDay = today - 3_400, retirementDay = today + 10_400),
            holiday = WidgetHolidayPayload(WidgetAccess.LOCKED), focus = WidgetFocusPayload(access))
    }
    Surface(Modifier.fillMaxWidth().heightIn(min = DoneAtOfferTokens.reportMinimumHeight),
        shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerHighest) {
        Row(Modifier.padding(DoneAtSpacing.m), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), verticalAlignment = Alignment.CenterVertically) {
            listOf(DoneAtWidgetKind.SUMMARY, DoneAtWidgetKind.LIFE).forEach { kind ->
                val bitmap = remember(context, snapshot, kind) {
                    widgetCardBitmap(context, widgetSuiteCard(context, kind, snapshot, now), androidx.compose.ui.unit.DpSize(170.dp, 170.dp))
                }
                Image(bitmap.asImageBitmap(), stringResource(kind.titleRes), Modifier.weight(1f).aspectRatio(1f))
            }
        }
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

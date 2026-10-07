package com.rainif.doneat.ui.timer

import android.text.format.DateFormat
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.*
import com.rainif.doneat.core.domain.session.heroRemainingMs
import com.rainif.doneat.core.domain.session.TimerPhase
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.text.NumberFormat

/** A presentation over the still-mounted Timer tab; no session, editor or stack is replaced. */
@Composable
fun LandscapeClock(graph: AppGraph) {
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val now by remember { timerTicks() }.collectAsStateWithLifecycle(System.currentTimeMillis().toDouble())
    val text = TimerText(LocalResources.current, LocalConfiguration.current.locales[0],
        DateFormat.is24HourFormat(LocalContext.current), device.hideEarnings)
    val shift = if (session.shouldQuerySnapshot(now)) session.snapshot(now) else null
    val phase = session.visualPhase(shift, now)
    DoneAtTheme(themeMode = ThemeMode.DARK) {
        Surface(Modifier.fillMaxSize(), color = Color.Black, contentColor = MaterialTheme.colorScheme.onSurface) {
        Box(Modifier.fillMaxSize().safeDrawingPadding(), contentAlignment = Alignment.Center) {
            Column(Modifier.widthIn(max = 760.dp).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = DoneAtSpacing.xl, vertical = DoneAtSpacing.m), horizontalAlignment = Alignment.CenterHorizontally) {
                if (shift == null) Text("—", style = DoneAtType.countdown)
                else {
                    val beforeStart = phase == TimerPhase.CLOCK_IN || phase == TimerPhase.REST || phase == TimerPhase.COMPLETED
                    val remaining = if (beforeStart) session.countdownToClockInMs(shift, now) else shift.heroRemainingMs(now)
                    val progress = if (beforeStart) session.countdownToClockInProgress(shift) else shift.progress
                    val caption = stringResource(when (phase) {
                        TimerPhase.CLOCK_IN, TimerPhase.REST, TimerPhase.COMPLETED -> R.string.nextShiftLabelShort
                        TimerPhase.LUNCH -> if (session.usesExtendedSchedule(now)) R.string.extendedBreak else R.string.lunchInProgress
                        TimerPhase.OVERTIME -> R.string.overtimeTimeLeftCaption
                        else -> R.string.timeLeftCaption
                    })
                    Text(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(text.locale, "EEEEMMMd"), text.locale)
                        .format(Instant.ofEpochMilli(now.toLong()).atZone(ZoneId.systemDefault())),
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        val density = LocalDensity.current
                        val digits = text.duration(remaining)
                        val style = with(density) {
                            val fitted = minOf(DoneAtType.countdown.fontSize.toPx(), constraints.maxWidth / (digits.length * .62f))
                            DoneAtType.countdown.copy(fontSize = fitted.toSp(), lineHeight = (fitted * 1.12f).toSp())
                        }
                        DoneAtCountdown(digits, "$caption, ${text.relativeDuration(remaining)}", style = style)
                    }
                    Text(caption, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(DoneAtSpacing.l))
                    DoneAtProgressMeter(progress, stringResource(R.string.progress), locale = text.locale,
                        overtime = phase == TimerPhase.OVERTIME, paused = phase == TimerPhase.LUNCH)
                    Row(Modifier.fillMaxWidth().padding(top = DoneAtSpacing.s), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(text.time(if (beforeStart) shift.countdownAnchorAtMs ?: now else shift.startAtMs), style = MaterialTheme.typography.labelMedium)
                        Text(text.time(if (beforeStart) shift.countdownTargetAtMs ?: shift.nextShiftStartAtMs ?: shift.startAtMs else shift.endAtMs), style = MaterialTheme.typography.labelMedium)
                    }
                    FlowRow(Modifier.fillMaxWidth().padding(top = DoneAtSpacing.l), horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                        ClockStat(stringResource(R.string.progress), NumberFormat.getPercentInstance(text.locale).apply { maximumFractionDigits = 1 }.format(progress / 100))
                        if (session.env.preferences.salaryEnabled) ClockStat(stringResource(R.string.moneyEarned), text.money(shift.earnedSoFar))
                        if (session.followsSchedule(now)) {
                            val zone = ZoneId.systemDefault()
                            val rest = shift.nextRestAtMs?.let { ChronoUnit.DAYS.between(
                                Instant.ofEpochMilli(now.toLong()).atZone(zone).toLocalDate(),
                                Instant.ofEpochMilli(it.toLong()).atZone(zone).toLocalDate()).coerceAtLeast(0).toDouble() }
                            ClockStat(stringResource(R.string.daysUntilRest), rest?.let(text::days) ?: "—")
                        }
                    }
                }
            }
        }
        }
    }
}

@Composable
private fun ClockStat(title: String, value: String) {
    Column(Modifier.padding(horizontal = DoneAtSpacing.m), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    }
}

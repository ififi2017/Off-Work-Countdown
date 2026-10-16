package com.rainif.doneat.ui.records

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Work
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtRecords322 as T
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtRecordsColors
import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.schedule.HolidayDayAnnotation
import androidx.compose.ui.platform.LocalResources
import java.time.LocalDate
import kotlin.math.max
import kotlin.math.min

@Composable
internal fun recordsHolidayColor(): Color = if (MaterialTheme.colorScheme.surface.luminanceValue() < .5f) T.holidayDark else T.holidayLight
private fun Color.luminanceValue(): Float = (red + green + blue) / 3

private fun Modifier.calendarDaySemantics(cell: RecordsDayCell, text: RecordsText, isSelected: Boolean, onSelect: () -> Unit, onOpen: () -> Unit, holiday: HolidayDayAnnotation?) = clearAndSetSemantics {
    val unlocked = cell.appearance != RecordsDayAppearance.LOCKED
    contentDescription = listOfNotNull(text.cellDescription(cell), holiday?.takeIf { unlocked }?.description(text.string(R.string.holidayMakeupWorkday), text.string(R.string.holidayEstimatedLabel))).joinToString(", ")
    role = Role.Button
    selected = isSelected
    onClick { onSelect(); true }
    if (unlocked) customActions = listOf(CustomAccessibilityAction(text.string(R.string.recordsSeeThisDay)) { onOpen(); true })
}

@Composable
private fun DayNumber(look: RecordsDayLook, selected: Boolean, text: RecordsText) {
    val scheme = MaterialTheme.colorScheme
    val fill = when { look.cell.isToday && !look.isLocked -> scheme.primary; selected -> scheme.onSurface; else -> Color.Transparent }
    val ink = when { look.cell.isToday && !look.isLocked -> scheme.onPrimary; selected -> scheme.surface; look.isLocked -> scheme.outline; else -> scheme.onSurface }
    Box(Modifier.size(T.dateSize).clip(CircleShape).background(fill), contentAlignment = Alignment.Center) {
        Text(text.count(look.cell.date.dayOfMonth), color = ink, style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (look.cell.isToday || selected) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1)
    }
}

@Composable
private fun DayBadge(look: RecordsDayLook, holiday: HolidayDayAnnotation?, modifier: Modifier = Modifier) {
    if (look.isLocked) return
    val icon = when { look.hasConflict -> Icons.Filled.Warning; holiday?.isMakeupWorkday == true -> Icons.Filled.Work; holiday != null -> Icons.Outlined.WbSunny; else -> return }
    Icon(icon, null, modifier.size(DoneAtSpacing.s + DoneAtSpacing.xxs), tint = when { look.hasConflict -> MaterialTheme.colorScheme.primary; holiday?.isMakeupWorkday == true -> MaterialTheme.colorScheme.onSurfaceVariant; else -> recordsHolidayColor() })
}

@Composable
private fun DayBar(look: RecordsDayLook) {
    val colors = LocalDoneAtRecordsColors.current
    Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs), verticalAlignment = Alignment.CenterVertically) {
        if (look.hasHours) {
            val width = min(24.0, 6 + look.totalMs / 3_600_000.0 * 1.8)
            val overtimeWidth = if (look.cell.overtimeMs > 0) max(3.0, width * look.cell.overtimeMs / look.totalMs) else 0.0
            if (look.cell.workMs > 0) Box(Modifier.size(max(2.0, width - overtimeWidth).dp, T.workBarHeight).clip(CircleShape)
                .then(if (look.isEstimated) Modifier.border(T.outline, colors.work.copy(alpha = .65f), CircleShape) else Modifier.background(colors.work)))
            if (overtimeWidth > 0) Box(Modifier.size(overtimeWidth.dp, T.workBarHeight).clip(CircleShape).background(colors.overtime))
        }
        if (!look.isLocked && look.cell.appearance == RecordsDayAppearance.CORRECTED) Box(Modifier.size(DoneAtSpacing.xs).clip(CircleShape).background(MaterialTheme.colorScheme.onSurfaceVariant))
    }
}

@Composable
private fun HolidayRuns(row: List<RecordsDayCell?>, holidays: Map<String, HolidayDayAnnotation>, modifier: Modifier = Modifier) {
    val runs = recordsHolidayRuns(row.map { cell -> cell?.takeUnless { it.appearance == RecordsDayAppearance.LOCKED }?.let { holidays[it.dayKey]?.takeUnless { it.isMakeupWorkday }?.name } })
    val green = recordsHolidayColor()
    Row(modifier.fillMaxWidth().height(T.holidayHeight).clearAndSetSemantics {}) {
        var index = 0
        while (index < 7) {
            val run = runs.firstOrNull { it.start == index }
            if (run == null) { Spacer(Modifier.weight(1f)); index++ } else {
                Box(Modifier.weight(run.length.toFloat()).padding(horizontal = DoneAtSpacing.xxs).clip(MaterialTheme.shapes.extraSmall).background(green.copy(alpha = .14f))) {
                    Text(run.name, Modifier.padding(horizontal = DoneAtSpacing.xs), style = MaterialTheme.typography.labelSmall, color = green, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                index += run.length
            }
        }
    }
}

/** Calendar date, one spanning holiday lane and a solid/outlined hours bar. */
@Composable
internal fun MonthGrid(cells: List<RecordsDayCell>, leadingBlanks: Int, weekdayLabels: List<String>, selectedDayKey: String?, text: RecordsText,
    onSelect: (RecordsDayCell) -> Unit, onOpen: (RecordsDayCell) -> Unit, modifier: Modifier = Modifier, holidays: Map<String, HolidayDayAnnotation> = emptyMap()) {
    CappedFontScale {
        Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs)) {
            Row(Modifier.fillMaxWidth().clearAndSetSemantics {}) { weekdayLabels.forEach { Text(it, Modifier.weight(1f), textAlign = TextAlign.Center, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
            val slots: List<RecordsDayCell?> = List(leadingBlanks) { null } + cells
            slots.chunked(7).forEach { week ->
                val row = week + List(7 - week.size) { null }
                Box(Modifier.fillMaxWidth().height(T.monthRowHeight)) {
                    Row(Modifier.fillMaxSize()) { row.forEach { cell ->
                        if (cell == null) Spacer(Modifier.weight(1f)) else {
                            val look = RecordsDayLook(cell)
                            val selected = selectedDayKey == cell.dayKey
                            Box(Modifier.weight(1f).fillMaxHeight().then(if (selected) modifier else Modifier).clickable { onSelect(cell) }
                                .calendarDaySemantics(cell, text, selected, { onSelect(cell) }, { onOpen(cell) }, holidays[cell.dayKey])) {
                                Column(Modifier.fillMaxSize().padding(top = DoneAtSpacing.xxs), horizontalAlignment = Alignment.CenterHorizontally) {
                                    DayNumber(look, selected, text)
                                    Spacer(Modifier.height(T.holidayHeight + DoneAtSpacing.xxs))
                                    DayBar(look)
                                }
                                DayBadge(look, holidays[cell.dayKey], Modifier.align(Alignment.TopEnd).padding(DoneAtSpacing.xxs))
                            }
                        }
                    } }
                    HolidayRuns(row, holidays, Modifier.padding(top = T.dateSize + DoneAtSpacing.xxs))
                }
            }
        }
    }
}

/** Shared hours axis; the outlined column is a plan, orange above it is overtime. */
@Composable
internal fun WeekStrips(cells: List<RecordsDayCell>, selectedDayKey: String?, text: RecordsText, onSelect: (RecordsDayCell) -> Unit, onOpen: (RecordsDayCell) -> Unit,
    modifier: Modifier = Modifier, holidays: Map<String, HolidayDayAnnotation> = emptyMap(), authorized: Boolean = true, overtimeMs: Double? = null) {
    val looks = cells.map(::RecordsDayLook)
    val colors = LocalDoneAtRecordsColors.current
    val scheme = MaterialTheme.colorScheme
    val ceiling = RecordsWeekAxis.ceiling(cells).toDouble()
    val reference = looks.filter { it.hasHours }.map { it.cell.workMs }.groupingBy { it }.eachCount().entries.maxWithOrNull(compareBy<Map.Entry<Long, Int>> { it.value }.thenBy { it.key })?.key
    CappedFontScale {
        Column {
            if (authorized) {
                Text(text.duration(looks.filter { it.hasSolidHours }.sumOf { it.totalMs }.toDouble()), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text(Strings.recordsWorkdaysRecorded(LocalResources.current, text.count(looks.count { it.hasSolidHours })), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
            } else Text(overtimeMs?.let { text.string(R.string.recordsOvertimeRecorded) + " " + text.duration(it) } ?: text.string(R.string.recordsNoOvertime), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(DoneAtSpacing.m))
            Box(Modifier.fillMaxWidth().height(T.weekHeight + DoneAtSpacing.xl)) {
                val lineColor = scheme.outlineVariant
                if (reference != null) Canvas(Modifier.fillMaxWidth().height(T.weekHeight).align(Alignment.BottomCenter).clearAndSetSemantics {}) {
                    val y = size.height * (1 - reference / ceiling).toFloat()
                    drawLine(lineColor, Offset(0f, y), Offset(size.width, y), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())))
                }
                Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.Bottom) { looks.forEach { look ->
                    Column(Modifier.weight(1f).then(if (look.cell.dayKey == selectedDayKey) modifier else Modifier).clickable { onSelect(look.cell) }.clearAndSetSemantics {}, horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(if (look.hasHours) text.decimal(look.totalMs / 3_600_000.0) else if (look.isUnrecordedWorkday) text.string(R.string.recordsUnrecorded) else "", style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant, maxLines = 1)
                        Column(Modifier.fillMaxWidth().height(T.weekHeight), verticalArrangement = Arrangement.Bottom, horizontalAlignment = Alignment.CenterHorizontally) {
                            if (look.hasHours) {
                                if (look.cell.overtimeMs > 0) Box(Modifier.size(T.weekBarWidth, max(4.0, T.weekHeight.value * look.cell.overtimeMs / ceiling).dp).clip(MaterialTheme.shapes.extraSmall).background(colors.overtime))
                                if (look.cell.workMs > 0) Box(Modifier.padding(top = DoneAtSpacing.xxs).size(T.weekBarWidth, max(4.0, T.weekHeight.value * look.cell.workMs / ceiling).dp).clip(MaterialTheme.shapes.extraSmall)
                                    .then(if (look.isEstimated) Modifier.border(T.outline, colors.work.copy(alpha = .65f), MaterialTheme.shapes.extraSmall) else Modifier.background(colors.work)))
                            }
                        }
                    }
                } }
            }
            Box(Modifier.padding(top = DoneAtSpacing.s)) {
                Row(Modifier.fillMaxWidth().height(T.holidayHeight).clearAndSetSemantics {}) { looks.forEach { look ->
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                        if (holidays[look.cell.dayKey]?.isMakeupWorkday == true && !look.isLocked) Icon(Icons.Filled.Work, null, Modifier.size(DoneAtSpacing.s), tint = scheme.onSurfaceVariant)
                        else if (holidays[look.cell.dayKey] == null) Text(text.weekdayNarrow(look.cell.date), style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant)
                    }
                } }
                HolidayRuns(cells, holidays)
            }
            Row(Modifier.fillMaxWidth()) { looks.forEach { look ->
                Box(Modifier.weight(1f).heightIn(min = DoneAtSpacing.minTouch).clickable { onSelect(look.cell) }
                    .calendarDaySemantics(look.cell, text, look.cell.dayKey == selectedDayKey, { onSelect(look.cell) }, { onOpen(look.cell) }, holidays[look.cell.dayKey]), contentAlignment = Alignment.Center) {
                    DayNumber(look, look.cell.dayKey == selectedDayKey, text)
                    DayBadge(look, holidays[look.cell.dayKey], Modifier.align(Alignment.TopEnd))
                }
            } }
        }
    }
}

@Composable
fun MarkLegend(includesLock: Boolean, text: RecordsText, dots: Boolean = false, showsHolidays: Boolean = false, showsMakeup: Boolean = false) {
    val colors = LocalDoneAtRecordsColors.current
    val green = recordsHolidayColor()
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
        @Composable fun item(label: Int, hollow: Boolean = false, color: Color = colors.work) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                val size = if (dots) Modifier.size(T.yearDot) else Modifier.size(DoneAtSpacing.m, T.workBarHeight)
                Box(size.clip(CircleShape).then(if (hollow) Modifier.border(T.outline, color.copy(alpha = .65f), CircleShape) else Modifier.background(color)))
                Text(text.string(label), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item(R.string.recordsLegendRecordedShort)
        item(R.string.recordsPlanned, hollow = true)
        item(R.string.recordsOvertime, color = colors.overtime)
        if (showsHolidays) item(R.string.holidayRestDay, color = green)
        if (showsMakeup) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
            Icon(Icons.Filled.Work, null, Modifier.size(DoneAtSpacing.s), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(text.string(R.string.holidayMakeupWorkday), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Twelve real mini calendars: one dot per day, never sampled heatmap buckets. */
@Composable
internal fun YearCanvas(cells: List<RecordsDayCell>, year: Int, selectedMonth: Int?, showCallout: Boolean, text: RecordsText, onSelectMonth: (Int) -> Unit, onOpenMonth: (Int) -> Unit,
    holidays: Map<String, HolidayDayAnnotation> = emptyMap(), leadingBlanks: (LocalDate) -> Int = { (it.dayOfWeek.value - 1) % 7 }) {
    val scheme = MaterialTheme.colorScheme
    val colors = LocalDoneAtRecordsColors.current
    val green = recordsHolidayColor()
    CappedFontScale {
        Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
            (1..12).chunked(3).forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                row.forEach { month ->
                    val date = LocalDate.of(year, month, 1)
                    val selected = month == selectedMonth
                    Column(Modifier.weight(1f).clip(MaterialTheme.shapes.medium).background(if (selected) scheme.surfaceContainerHighest else Color.Transparent)
                        .clickable { if (selected && showCallout) onOpenMonth(month) else onSelectMonth(month) }
                        .clearAndSetSemantics {
                            contentDescription = text.monthYear(date)
                            role = Role.Button
                            this.selected = selected
                            onClick { onSelectMonth(month); true }
                            customActions = listOf(CustomAccessibilityAction(text.string(R.string.recordsSeeThisMonth)) { onOpenMonth(month); true })
                        }.padding(DoneAtSpacing.xs), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                        Text(text.shortMonth(date), style = MaterialTheme.typography.labelMedium, color = if (selected) scheme.primary else scheme.onSurface, fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal, maxLines = 1)
                        val monthCells = cells.filter { it.date.monthValue == month }
                        val slots: List<RecordsDayCell?> = List(leadingBlanks(date)) { null } + monthCells
                        // Six week rows keep every month's baseline stable.
                        (0 until 6).forEach { week -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                            (0 until 7).forEach { column ->
                                val cell = slots.getOrNull(week * 7 + column)
                                Box(Modifier.weight(1f).height(DoneAtSpacing.m), contentAlignment = Alignment.Center) {
                                    if (cell != null) {
                                        val look = RecordsDayLook(cell)
                                        val holiday = holidays[cell.dayKey]?.takeUnless { look.isLocked || it.isMakeupWorkday }
                                        val tint = when { look.isLocked -> scheme.outlineVariant; cell.isToday -> scheme.primary; look.hasSolidHours && cell.overtimeMs > 0 -> colors.overtime; look.hasSolidHours -> colors.work; holiday != null -> green; look.hasHours -> colors.work; else -> scheme.outline }
                                        val mark = if (!look.hasHours && holiday == null && !cell.isToday) DoneAtSpacing.xxs + 1.dp else T.yearDot
                                        Box(Modifier.size(mark).clip(CircleShape).then(if (look.isEstimated && !cell.isToday && holiday == null) Modifier.border(1.dp, tint.copy(alpha = .65f), CircleShape) else Modifier.background(tint)))
                                        if (cell.isToday && !look.isLocked) Box(Modifier.size(DoneAtSpacing.s + DoneAtSpacing.xxs).border(T.outline, scheme.primary, CircleShape))
                                    }
                                }
                            }
                        } }
                    }
                }
            } }
        }
    }
}

/** Only one Plus entry below every free calendar, including locked scales. */
@Composable
internal fun RecordsFreeWindowNote(text: RecordsText, onUnlock: () -> Unit) {
    TextButton(onClick = onUnlock, modifier = Modifier.fillMaxWidth()) {
        Text(text.string(R.string.recordsFreeWindowNote) + " " + text.string(R.string.recordsFreeWindowAction), style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Start)
    }
}

/** The month selection describes only already-authorized cell projections. */
@Composable
internal fun recordsMonthDescription(cells: List<RecordsDayCell>, holidays: Map<String, HolidayDayAnnotation>, text: RecordsText): String {
    val res = LocalResources.current
    val looks = cells.map(::RecordsDayLook)
    if (looks.isNotEmpty() && looks.all { it.isLocked }) return text.string(R.string.recordsLockedDayDetail)
    val recorded = looks.filter { it.hasSolidHours }
    val projected = looks.count { !it.isLocked && it.cell.isProjection && it.hasHours }
    val planned = looks.count { !it.isLocked && it.cell.isFuture && it.hasHours }
    val overtime = recorded.sumOf { it.cell.overtimeMs }
    val daysOff = looks.count { !it.isLocked && holidays[it.cell.dayKey]?.isMakeupWorkday == false }
    val parts = buildList {
        if (recorded.isNotEmpty()) add(Strings.recordsDaysRecordedTotal(res, text.count(recorded.size), text.duration(recorded.sumOf { it.totalMs }.toDouble())))
        if (projected > 0) add(Strings.recordsProjectedWorkdays(res, text.count(projected)))
        if (overtime > 0) add(Strings.recordsOvertimeAmount(res, text.duration(overtime.toDouble())))
        if (planned > 0) add(Strings.recordsPlannedWorkdaysLeft(res, text.count(planned)))
        if (daysOff > 0) add(Strings.recordsDaysOff(res, text.count(daysOff)))
    }
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ") ?: text.string(R.string.recordsUnrecorded)
}

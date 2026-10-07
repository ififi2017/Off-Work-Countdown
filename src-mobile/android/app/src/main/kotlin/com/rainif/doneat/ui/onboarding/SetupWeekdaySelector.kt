package com.rainif.doneat.ui.onboarding

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import java.time.DayOfWeek
import java.time.format.TextStyle
import java.util.Locale

/** Equal weekday cells like iOS; large text uses balanced rows and full spoken names. */
@Composable
internal fun SetupWeekdaySelector(workdays: List<Int>, locale: Locale, onToggle: (Int) -> Unit) {
    val density = LocalDensity.current
    val measurer = rememberTextMeasurer()
    val style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold)
    BoxWithConstraints(Modifier.fillMaxWidth().padding(DoneAtSpacing.m)) {
        val columns = when {
            maxWidth >= 360.dp && density.fontScale < 1.5f -> 7
            maxWidth >= 204.dp -> 4
            else -> 3
        }
        val rows = when (columns) { 7 -> listOf(7); 4 -> listOf(4, 3); else -> listOf(3, 2, 2) }
        val cellWidth = (maxWidth - DoneAtSpacing.xs * (columns - 1)) / columns
        var firstDay = 1
        Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
            rows.forEach { count ->
                val days = firstDay until firstDay + count
                firstDay += count
                Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    days.forEach { day ->
                        val weekday = DayOfWeek.of(day)
                        val value = if (day == 7) 0 else day
                        val selected = value in workdays
                        val short = weekday.getDisplayName(TextStyle.SHORT_STANDALONE, locale)
                        val available = with(density) { (cellWidth - DoneAtSpacing.xs * 2).toPx() }
                        val label = if (measurer.measure(AnnotatedString(short), style).size.width <= available) short
                            else weekday.getDisplayName(TextStyle.NARROW_STANDALONE, locale)
                        val scheme = MaterialTheme.colorScheme
                        Surface(
                            Modifier.width(cellWidth).heightIn(min = 48.dp)
                                .toggleable(selected, role = Role.Checkbox, onValueChange = { onToggle(value) })
                                .semantics { contentDescription = weekday.getDisplayName(TextStyle.FULL, locale) },
                            shape = MaterialTheme.shapes.small,
                            color = if (selected) scheme.primaryContainer else scheme.surface,
                            contentColor = if (selected) scheme.onPrimaryContainer else scheme.onSurfaceVariant,
                            border = if (selected) null else BorderStroke(1.dp, scheme.outlineVariant),
                        ) {
                            Box(contentAlignment = androidx.compose.ui.Alignment.Center,
                                modifier = Modifier.padding(DoneAtSpacing.xs)) {
                                Text(label, Modifier.clearAndSetSemantics {}, style = style,
                                    maxLines = 1, softWrap = false, textAlign = TextAlign.Center)
                            }
                        }
                    }
                }
            }
        }
    }
}

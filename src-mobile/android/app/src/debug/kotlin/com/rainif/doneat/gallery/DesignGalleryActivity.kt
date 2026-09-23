package com.rainif.doneat.gallery

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.rainif.doneat.core.designsystem.DoneAtCard
import com.rainif.doneat.core.designsystem.DoneAtColors
import com.rainif.doneat.core.designsystem.DoneAtCountdown
import com.rainif.doneat.core.designsystem.DoneAtDestructiveButton
import com.rainif.doneat.core.designsystem.DoneAtPhase
import com.rainif.doneat.core.designsystem.DoneAtPhaseBadge
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtProgressMeter
import com.rainif.doneat.core.designsystem.DoneAtShapes
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.DoneAtTheme
import com.rainif.doneat.core.designsystem.DoneAtValueRow
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.core.designsystem.ThemeMode
import com.rainif.doneat.core.designsystem.supportsDynamicColor
import com.rainif.doneat.core.designsystem.systemRemovesAnimations
import com.rainif.doneat.ui.SystemBarsFollowTheme
import kotlinx.coroutines.delay

/**
 * Debug-only gallery of the DoneAt tokens (T04): the main-timer wireframe from
 * plan 01 §7.2 and every token, under the theme, dynamic-colour and
 * reduced-motion switches. Strings are fixed English: this screen never ships.
 *
 *     adb shell am start -n com.rainif.doneat/.gallery.DesignGalleryActivity
 */
class DesignGalleryActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val initialMode = when (intent.getStringExtra("theme")) {
            "light" -> ThemeMode.LIGHT
            "dark" -> ThemeMode.DARK
            else -> ThemeMode.SYSTEM
        }
        setContent {
            var mode by rememberSaveable { mutableStateOf(initialMode) }
            var dynamic by rememberSaveable { mutableStateOf(false) }
            val systemReduced = systemRemovesAnimations(LocalContext.current)
            var reduced by rememberSaveable { mutableStateOf(systemReduced) }
            val dark = when (mode) {
                ThemeMode.SYSTEM -> isSystemInDarkTheme()
                ThemeMode.LIGHT -> false
                ThemeMode.DARK -> true
            }
            SystemBarsFollowTheme(dark)
            DoneAtTheme(themeMode = mode, dynamicColor = dynamic, reducedMotion = reduced) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                    Column(
                        Modifier
                            .safeDrawingPadding()
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.l),
                        verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.section),
                    ) {
                        Controls(mode, { mode = it }, dynamic, { dynamic = it }, reduced, { reduced = it })
                        TimerWireframe()
                        Rollover()
                        Meters()
                        Phases()
                        Actions()
                        PeriodPicker()
                        Swatches()
                        TypeScale()
                    }
                }
            }
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        content()
    }
}

@Composable
private fun Controls(
    mode: ThemeMode, onMode: (ThemeMode) -> Unit,
    dynamic: Boolean, onDynamic: (Boolean) -> Unit,
    reduced: Boolean, onReduced: (Boolean) -> Unit,
) = Section("Probe") {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        ThemeMode.entries.forEachIndexed { i, m ->
            SegmentedButton(mode == m, { onMode(m) }, SegmentedButtonDefaults.itemShape(i, ThemeMode.entries.size)) {
                Text(m.name.lowercase().replaceFirstChar { it.uppercase() })
            }
        }
    }
    DoneAtCard {
        if (supportsDynamicColor) DoneAtValueRow("Dynamic colour", "") { Switch(dynamic, onDynamic) }
        DoneAtValueRow("Reduced motion", if (LocalDoneAtMotion.current.reduced) "on" else "off") { Switch(reduced, onReduced) }
    }
}

/** Plan 01 §7.2 main timer: one highest-emphasis action, digits the only thing that changes each second. */
@Composable
private fun TimerWireframe() = Section("Main timer") {
    DoneAtCard(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Mon, Sep 21 · 09:00–18:00", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            TextButton(onClick = {}) { Text("Focus") }
        }
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            DoneAtPhaseBadge(DoneAtPhase.WORK, "Working")
            val left = ticking(3 * 3600 + 25 * 60 + 18)
            DoneAtCountdown(clock(left), "${left / 3600} hours ${left / 60 % 60} minutes of work left")
            Text("Effective work time left", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            DoneAtProgressMeter(62.4, "Progress", Modifier.padding(bottom = DoneAtSpacing.s))
        }
        HorizontalDivider()
        DoneAtValueRow("Next", "Lunch at 12:00")
        DoneAtValueRow("Worked today", "4 h 35 min")
        Spacer(Modifier.height(DoneAtSpacing.s))
        DoneAtPrimaryButton("Start overtime", {}, Modifier.fillMaxWidth())
    }
}

/** Seconds left, ticking down once a second from [start] (restarts when it reaches zero). */
@Composable
private fun ticking(start: Int): Int {
    var left by remember { mutableIntStateOf(start) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            left = if (left > 0) left - 1 else start
        }
    }
    return left
}

private fun clock(seconds: Int) = "%02d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)

/** Every digit rolling at once: 01:00:00 → 00:59:59. */
@Composable
private fun Rollover() = Section("Countdown rollover (five digits change at 00:59:59)") {
    val left = ticking(3600 + 5)
    DoneAtCountdown(clock(left), "Rollover demo", Modifier.fillMaxWidth())
}

/** The bubble at both ends (pointer on the mark, bubble sliding), in overtime and paused for lunch. */
@Composable
private fun Meters() = Section("Progress meter: 0 %, 100 %, overtime, lunch") {
    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
        DoneAtProgressMeter(0.0, "Progress")
        DoneAtProgressMeter(100.0, "Progress")
        DoneAtProgressMeter(91.7, "Progress", overtime = true)
        DoneAtProgressMeter(47.5, "Progress", paused = true)
    }
}

@Composable
private fun Phases() = Section("Phase badges (label + colour, never colour alone)") {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        DoneAtPhaseBadge(DoneAtPhase.WORK, "Working")
        DoneAtPhaseBadge(DoneAtPhase.REST, "Lunch break")
        DoneAtPhaseBadge(DoneAtPhase.OFF_WORK, "Off work")
        DoneAtPhaseBadge(DoneAtPhase.OVERTIME, "Overtime")
    }
}

@Composable
private fun Actions() = Section("Actions (press and hold the first: pill → rounded square)") {
    DoneAtPrimaryButton("Start", {}, Modifier.fillMaxWidth())
    DoneAtPrimaryButton("Heute Überstunden bis Schichtende eintragen", {}, Modifier.fillMaxWidth())
    Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        DoneAtDestructiveButton("End today", {})
        TextButton(onClick = {}) { Text("Details") }
    }
}

@Composable
private fun PeriodPicker() = Section("Period picker") {
    var selected by rememberSaveable { mutableIntStateOf(1) }
    val labels = listOf("Day", "Week", "Month", "Year")
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        labels.forEachIndexed { i, label ->
            SegmentedButton(selected == i, { selected = i }, SegmentedButtonDefaults.itemShape(i, labels.size)) { Text(label) }
        }
    }
}

@Composable
private fun Swatches() = Section("Colour roles") {
    val s = MaterialTheme.colorScheme
    val roles = listOf(
        Triple("primary", s.primary, s.onPrimary),
        Triple("primaryContainer", s.primaryContainer, s.onPrimaryContainer),
        Triple("secondaryContainer", s.secondaryContainer, s.onSecondaryContainer),
        Triple("tertiaryContainer", s.tertiaryContainer, s.onTertiaryContainer),
        Triple("surfaceContainerLow", s.surfaceContainerLow, s.onSurface),
        Triple("surfaceContainerHighest", s.surfaceContainerHighest, s.onSurfaceVariant),
        Triple("error", s.error, s.onError),
        Triple("brand (decoration)", DoneAtColors.brand, Color.Black),
    )
    FlowRow(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        roles.forEach { (name, bg, fg) ->
            Box(Modifier.width(160.dp).background(bg, MaterialTheme.shapes.medium).padding(DoneAtSpacing.m)) {
                Text(name, color = fg, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        listOf("xs" to MaterialTheme.shapes.extraSmall, "s" to MaterialTheme.shapes.small, "m 14" to MaterialTheme.shapes.medium, "l 22" to MaterialTheme.shapes.large, "xl" to MaterialTheme.shapes.extraLarge).forEach { (n, shape) ->
            Box(Modifier.size(56.dp).background(s.surfaceContainerHighest, shape), contentAlignment = Alignment.Center) {
                Text(n, style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center)
            }
        }
    }
    Text("Action height ${DoneAtShapes.actionHeight.value.toInt()} dp · touch ≥ ${DoneAtSpacing.minTouch.value.toInt()} dp", style = MaterialTheme.typography.bodySmall)
}

@Composable
private fun TypeScale() = Section("Type") {
    val t = MaterialTheme.typography
    Text("Headline small", style = t.headlineSmall)
    Text("Title medium", style = t.titleMedium)
    Text("Body large — 16 sp body copy that wraps onto a second line under a large font setting.", style = t.bodyLarge)
    Text("Body small — supporting text", style = t.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Text("Label large", style = t.labelLarge)
}

package com.rainif.doneat.ui.onboarding

import android.text.format.DateFormat
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rainif.doneat.R
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.plus.PlusDemoKind
import com.rainif.doneat.plus.PlusFeatureDemo
import com.rainif.doneat.core.designsystem.*
import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.TimelineKind
import com.rainif.doneat.core.domain.settings.PreferencesRules
import com.rainif.doneat.core.domain.settings.SetupProjection
import com.rainif.doneat.ui.components.*
import com.rainif.doneat.ui.timer.TimerText
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/** Content scrolls independently of the persistent next/finish controls. */
@Composable
internal fun JourneyScaffold(title: String, subtitle: String?, onBack: (() -> Unit)?, finishing: Boolean,
                             onFinish: () -> Unit, exploreLabel: String, onExplore: () -> Unit,
                             header: (@Composable () -> Unit)? = null,
                             content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            if (onBack != null) IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.onboardingBack))
            }
        }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
            .padding(horizontal = DoneAtSpacing.xl), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
            header?.invoke()
            Text(title, Modifier.widthIn(max = 560.dp).semantics { heading() },
                style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            if (subtitle != null) Text(subtitle, Modifier.widthIn(max = 560.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l),
                horizontalAlignment = Alignment.CenterHorizontally, content = content)
            Spacer(Modifier.height(DoneAtSpacing.m))
        }
        Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().align(Alignment.CenterHorizontally)
            .padding(horizontal = DoneAtSpacing.xl, vertical = DoneAtSpacing.s), horizontalAlignment = Alignment.CenterHorizontally) {
            TextButton(onClick = onExplore, enabled = !finishing) { Text(exploreLabel, textAlign = TextAlign.Center) }
            DoneAtPrimaryButton(stringResource(R.string.onboardingStartUsing), onFinish, Modifier.fillMaxWidth(), enabled = !finishing)
        }
    }
}

@Composable
private fun projectionText(projection: SetupProjection?): TimerText {
    val res = LocalResources.current
    val context = LocalContext.current
    return remember(res, projection?.input?.zone) { TimerText(res, res.configuration.locales[0], DateFormat.is24HourFormat(context), true,
        projection?.input?.zone ?: ZoneId.systemDefault()) }
}

@Composable
internal fun ReadyJourneyPage(p: SyncedPreferences, projection: SetupProjection?, now: Double,
                             onBack: (() -> Unit)?, finishing: Boolean, onFinish: () -> Unit,
                             onExplore: () -> Unit, onPrivacy: () -> Unit, anchor: (Rect) -> Unit) {
    val text = projectionText(projection)
    val resources = LocalResources.current
    val locale = resources.configuration.locales[0]
    val weekdays = p.workdays.map { DayOfWeek.of(if (it == 0) 7 else it).getDisplayName(TextStyle.SHORT, locale) }.joinToString(" · ")
    val pattern = when (p.scheduleMode) { "alternating" -> stringResource(R.string.scheduleAlternating); "rotation" -> stringResource(R.string.scheduleRotation); else -> weekdays }
    val recap = if (p.scheduleMode == "off") stringResource(R.string.scheduleManualTimer)
        else pattern + " · " + formatClock(p.startMinutes) + " – " + formatClock(p.endMinutes)
    JourneyScaffold(stringResource(R.string.onboardingAllSetTitle), recap, onBack, finishing, onFinish,
        stringResource(R.string.onboardingExplore), onExplore) {
        if (projection != null) {
            val shift = projection.snapshot
            Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLowest) {
                Column(Modifier.padding(DoneAtSpacing.l), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                    Text(Instant.ofEpochMilli(shift.startAtMs.toLong()).atZone(projection.input.zone)
                        .format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "EEEEMMMd"), locale)), style = MaterialTheme.typography.titleMedium)
                    Text(text.timeRange(shift.startAtMs, shift.endAtMs), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                    Row(Modifier.fillMaxWidth().height(6.dp), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                        shift.segments.forEach { segment -> Box(Modifier.weight((segment.endAtMs - segment.startAtMs).toFloat())
                            .fillMaxHeight().background(MaterialTheme.colorScheme.primary, MaterialTheme.shapes.small)) }
                    }
                    HorizontalDivider()
                    Text(stringResource(if (now < shift.startAtMs) R.string.nextShiftLabelShort else R.string.timeLeftCaption),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    JourneyClockSlot(anchor)
                }
            }
            Text(stringResource(R.string.comingUp), Modifier.fillMaxWidth(), style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLowest) {
                Column {
                    projection.upcoming.forEachIndexed { index, event ->
                        if (index > 0) HorizontalDivider(Modifier.padding(horizontal = DoneAtSpacing.l))
                        val key = when (event.kind) {
                            TimelineKind.SHIFT_START -> R.string.startTime
                            TimelineKind.SHIFT_END -> R.string.endTime
                            TimelineKind.LUNCH_START -> R.string.lunchStartTime
                            TimelineKind.LUNCH_END -> R.string.lunchBackAt
                            TimelineKind.HEALTH -> R.string.microBreakReminder
                            else -> R.string.offWorkReminder
                        }
                        val detail = when (event.kind) {
                            TimelineKind.HEALTH -> Strings.minutesShort(resources, text.count(p.microBreakIntervalMinutes))
                            TimelineKind.MILESTONE -> event.id.substringAfterLast(":").toIntOrNull()?.let {
                                Strings.notificationMilestoneTitle(resources, text.count(100 - it))
                            }
                            else -> null
                        }
                        ListItem(headlineContent = { Text(stringResource(key)) },
                            supportingContent = detail?.let { value -> { Text(value) } }, trailingContent = {
                            Text(text.eventTime(event.atMs, now), style = MaterialTheme.typography.bodyMedium)
                        }, colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent))
                    }
                }
            }
        } else Text(stringResource(R.string.scheduleOffManualStart), style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center)
        TextButton(onClick = onPrivacy) { Text(stringResource(R.string.onboardingPrivacyTitle)) }
    }
}

@Composable
internal fun JourneyClockSlot(anchor: (Rect) -> Unit) {
    Box(Modifier.fillMaxWidth().height(58.dp).clearAndSetSemantics {}.onGloballyPositioned { anchor(it.boundsInRoot()) })
}

/** A single countdown stays alive and moves between Ready and the Android system surfaces. */
@Composable
internal fun JourneyClockOverlay(projection: SetupProjection, now: Double, anchor: Rect?, root: Offset,
                                 opacity: Float, entranceX: Float, continuity: Boolean, previewEndAtMs: Double?) {
    anchor ?: return
    val density = LocalDensity.current
    val reduced = LocalDoneAtMotion.current.reduced || onboardingTouchExplorationEnabled()
    // Initial entrance follows the incoming page's measured slot and shared
    // opacity. Ready <-> Glance keeps the existing persistent-clock geometry
    // interpolation, and reduced motion never moves it.
    val spec = DoneAtOnboardingTokens.continuity<Float>(reduced || !continuity)
    val x by animateFloatAsState(anchor.left - root.x, spec, label = "journeyClockX")
    val y by animateFloatAsState(anchor.top - root.y, spec, label = "journeyClockY")
    val width by animateFloatAsState(anchor.width, spec, label = "journeyClockWidth")
    val text = projectionText(projection)
    // NotificationCompat's WORK chronometer uses the snapshot's absolute end;
    // the widget keeps SetupProjection's start/work-remaining countdown rule.
    val ms = previewEndAtMs?.let { (it - now).coerceAtLeast(0.0) } ?: projection.remainingMs(now)
    val size by animateFloatAsState((anchor.width / density.density / density.fontScale / 6.1f).coerceIn(20f, 40f), spec, label = "journeyClockSize")
    Box(Modifier.offset { IntOffset(x.roundToInt(), y.roundToInt()) }.width(with(density) { width.toDp() })
        .height(58.dp).graphicsLayer { alpha = opacity; translationX = entranceX }, contentAlignment = Alignment.Center) {
        CompositionLocalProvider(LocalDoneAtMotion provides remember(reduced) { DoneAtMotion(reduced) }) {
            DoneAtCountdown(text.duration(ms), text.duration(ms), style = MaterialTheme.typography.headlineLarge.copy(fontSize = size.sp, fontWeight = FontWeight.Bold))
        }
    }
}

@Composable
internal fun GlanceJourneyPage(projection: SetupProjection?, now: Double, onBack: (() -> Unit)?, finishing: Boolean,
                              onFinish: () -> Unit, onExplore: () -> Unit, onClockTargetChanged: (Double?) -> Unit,
                              anchor: (Rect) -> Unit) {
    var notification by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(notification, projection?.snapshot?.endAtMs) {
        onClockTargetChanged(if (notification) projection?.snapshot?.endAtMs else null)
    }
    val scheme = MaterialTheme.colorScheme
    JourneyScaffold(stringResource(R.string.onboardingEverywhereTitle), stringResource(R.string.onboardingSystemBody), onBack,
        finishing, onFinish, stringResource(R.string.onboardingExplorePlus), onExplore) {
        // Two actual Android surface structures, sharing the one clock owned
        // by SetupFlow rather than mounting a second countdown in either host.
        if (notification) GlanceNotificationScene(projection, now, anchor)
        else GlanceWidgetScene(projection, now, anchor)
        Text(stringResource(R.string.onboardingShiftPreview), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            listOf(R.string.onboardingWidgetSurface, R.string.onboardingOngoingSurface).forEachIndexed { index, key ->
                SegmentedButton(notification == (index == 1), { notification = index == 1 }, SegmentedButtonDefaults.itemShape(index, 2)) {
                    Text(stringResource(key), textAlign = TextAlign.Center)
                }
            }
        }
    }
}

/** Small widget layout: Header, phase Badge, Countdown, Progress and Boundary. */
@Composable
private fun GlanceWidgetScene(projection: SetupProjection?, now: Double, anchor: (Rect) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val text = projectionText(projection)
    val locale = LocalResources.current.configuration.locales[0]
    val zone = projection?.input?.zone ?: ZoneId.systemDefault()
    val before = projection != null && now < projection.snapshot.startAtMs
    val progress = if (projection == null || before) 0f else (projection.snapshot.progress / 100).toFloat().coerceIn(0f, 1f)
    Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, color = scheme.secondaryContainer) {
        Column(Modifier.background(Brush.linearGradient(listOf(scheme.secondaryContainer, scheme.primaryContainer)))
            .padding(DoneAtSpacing.l), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
            Text(Instant.ofEpochMilli(now.toLong()).atZone(zone).format(DateTimeFormatter.ofPattern(
                DateFormat.getBestDateTimePattern(locale, "EEEEMMMd"), locale)),
                style = MaterialTheme.typography.bodyMedium, color = scheme.onSecondaryContainer,
                textAlign = TextAlign.Center)
            Surface(Modifier.widthIn(max = 248.dp).fillMaxWidth(), shape = MaterialTheme.shapes.large,
                color = scheme.surfaceContainerLowest) {
                Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                        DoneAtBrandMark(Modifier.size(20.dp))
                        Text(stringResource(R.string.app_name), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
                    }
                    if (projection != null) {
                        Surface(shape = MaterialTheme.shapes.large, color = scheme.primaryContainer) {
                            Row(Modifier.padding(horizontal = DoneAtSpacing.s, vertical = DoneAtSpacing.xs),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                                Box(Modifier.size(6.dp).background(scheme.primary, androidx.compose.foundation.shape.CircleShape))
                                Text(stringResource(if (before) R.string.nextShiftLabelShort else R.string.widgetWorking), style = MaterialTheme.typography.labelSmall)
                            }
                        }
                        JourneyClockSlot(anchor)
                        Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                            LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth().height(7.dp),
                                drawStopIndicator = {})
                            Row(Modifier.fillMaxWidth()) {
                                Text(java.text.NumberFormat.getPercentInstance(locale).format(progress), style = MaterialTheme.typography.labelSmall, color = scheme.primary)
                                Spacer(Modifier.weight(1f))
                                Text(text.time(if (before) projection.snapshot.startAtMs else projection.snapshot.endAtMs), style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    } else Text(stringResource(R.string.scheduleManualTimer), style = MaterialTheme.typography.titleMedium)
                }
            }
            // Launcher context is decoration, not fictitious interactive apps.
            Row(Modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                listOf(Icons.Outlined.CalendarMonth, Icons.Outlined.Email, Icons.Outlined.Settings).forEach { icon ->
                    Surface(Modifier.size(40.dp), shape = androidx.compose.foundation.shape.CircleShape,
                        color = scheme.surface.copy(alpha = .6f)) {
                        Box(contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(20.dp), tint = scheme.onSurfaceVariant) }
                    }
                }
            }
        }
    }
}

/** Android notification shade, matching OngoingCoordinator's WORK title/icon/chronometer. */
@Composable
private fun GlanceNotificationScene(projection: SetupProjection?, now: Double, anchor: (Rect) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val text = projectionText(projection)
    Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, color = scheme.surfaceContainerHighest) {
        Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
            Row(Modifier.fillMaxWidth().clearAndSetSemantics {}, verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                Text(text.time(now), style = MaterialTheme.typography.labelMedium)
                Spacer(Modifier.weight(1f))
                Icon(Icons.Outlined.Wifi, null, Modifier.size(16.dp))
                Icon(Icons.Outlined.BatteryFull, null, Modifier.size(16.dp))
            }
            Surface(shape = MaterialTheme.shapes.large, color = scheme.surfaceContainerLowest) {
                Column(Modifier.fillMaxWidth().padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                        Icon(painterResource(R.drawable.ic_stat_reminder), null, Modifier.size(18.dp), tint = scheme.primary)
                        Text(stringResource(R.string.app_name), style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant)
                    }
                    if (projection != null) {
                        Text("${stringResource(R.string.endTime)} ${text.time(projection.snapshot.endAtMs)}",
                            style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Box(Modifier.widthIn(max = 180.dp)) { JourneyClockSlot(anchor) }
                    } else Text(stringResource(R.string.scheduleManualTimer), style = MaterialTheme.typography.titleMedium)
                }
            }
            // No fake action buttons or progress percentage: the real ongoing
            // notification uses a system chronometer, not setProgress().
            Box(Modifier.width(40.dp).height(4.dp).align(Alignment.CenterHorizontally)
                .background(scheme.onSurfaceVariant.copy(alpha = .35f), MaterialTheme.shapes.small).clearAndSetSemantics {})
        }
    }
}

private val demoIcons = listOf(Icons.Outlined.CalendarMonth, Icons.Outlined.BarChart, Icons.Outlined.Timer, Icons.Outlined.Luggage)

@Composable
internal fun PlusJourneyPage(onBack: (() -> Unit)?, finishing: Boolean, onFinish: () -> Unit, onExplore: () -> Unit,
                             offerContent: (@Composable (Boolean) -> Unit)?, active: Boolean = true) {
    var stage by rememberSaveable { mutableIntStateOf(0) }
    var manuallySelected by rememberSaveable { mutableStateOf(false) }
    var reachedEnd by rememberSaveable { mutableStateOf(false) }
    val largeText = LocalDensity.current.fontScale >= 1.5f
    val reduced = LocalDoneAtMotion.current.reduced || onboardingTouchExplorationEnabled()
    val dwell = remember { Animatable(0f) }
    val canAutoplay = !manuallySelected && !reachedEnd && !reduced && !largeText && active
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(canAutoplay, lifecycle) {
        if (canAutoplay) lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                dwell.snapTo(0f)
                dwell.animateTo(1f, tween(DoneAtOnboardingTokens.STAGE_MS, easing = LinearEasing))
                if (stage == 3) { reachedEnd = true; break }
                stage++
            }
        } else dwell.snapTo(1f)
    }
    val dragThreshold = with(LocalDensity.current) { 48.dp.toPx() }
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val swipe = Modifier.pointerInput(dragThreshold, rtl) {
        var distance = 0f
        detectHorizontalDragGestures(
            onDragStart = { distance = 0f; manuallySelected = true },
            onHorizontalDrag = { change, amount -> change.consume(); distance += amount },
            onDragEnd = {
                if (kotlin.math.abs(distance) >= dragThreshold) {
                    val direction = if ((distance < 0) != rtl) 1 else -1
                    stage = (stage + direction).coerceIn(0, 3)
                }
            },
        )
    }
    JourneyScaffold(stringResource(R.string.onboardingPlusShowcaseTitle), null, onBack,
        finishing, onFinish, stringResource(R.string.onboardingExplorePlus), onExplore, header = {
            Surface(shape = MaterialTheme.shapes.small, color = MaterialTheme.colorScheme.primaryContainer) {
                Row(Modifier.padding(horizontal = DoneAtSpacing.m, vertical = DoneAtSpacing.xs), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    Icon(Icons.Outlined.Star, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                    Text(stringResource(R.string.plusSection), style = MaterialTheme.typography.labelMedium)
                }
            }
        }) {
        if (largeText) {
            for (selected in 0..3) {
                PlusFeatureDemo(PlusDemoKind.entries[selected], isActive = active)
                Text(stringResource(journeyStageCaption(selected)), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            }
        } else {
            Column(swipe, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                AnimatedContent(stage, transitionSpec = {
                    val duration = if (reduced) DoneAtMotion.REDUCED_MS else DoneAtOnboardingTokens.PAGE_MS
                    (fadeIn(tween(duration)) togetherWith fadeOut(tween(duration))).using(null)
                }, label = "plusJourneyStage") { selected ->
                    PlusFeatureDemo(PlusDemoKind.entries[selected], Modifier.heightIn(min = 268.dp), isActive = active && selected == stage)
                }
                Text(stringResource(journeyStageCaption(stage)), Modifier.fillMaxWidth().heightIn(min = 76.dp), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                demoIcons.forEachIndexed { index, icon ->
                    IconButton(onClick = { manuallySelected = true; stage = index }, Modifier.size(width = 58.dp, height = 52.dp)) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                            Icon(icon, stringResource(journeyStageCaption(index)), Modifier.size(24.dp),
                                tint = if (stage == index) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                            LinearProgressIndicator(progress = { when { index < stage -> 1f; index == stage -> dwell.value; else -> 0f } },
                                modifier = Modifier.width(44.dp).height(3.dp))
                        }
                    }
                }
            }
        }
        offerContent?.invoke(active)
    }
}

private fun journeyStageCaption(stage: Int): Int = when (stage) {
    0 -> R.string.onboardingPlusRecordsTitle
    1 -> R.string.onboardingPlusReportsTitle
    2 -> R.string.onboardingPlusFocusTitle
    else -> R.string.onboardingPlusRestTitle
}

@Composable
internal fun SetupScheduleExtras(p: SyncedPreferences, edit: ((SyncedPreferences) -> SyncedPreferences) -> Unit,
                                 holidays: HolidayCalendar, region: String?, onRegion: (String) -> Unit) {
    val locale = LocalResources.current.configuration.locales[0]
    var picksRegion by remember { mutableStateOf(false) }
    SettingsGroup {
        if (p.scheduleMode == "rotation") {
            SetupCounter(stringResource(R.string.rotationWorkDays), p.rotationWorkDays) { value -> edit { it.copy(rotationWorkDays = value) } }
            SetupCounter(stringResource(R.string.rotationRestDays), p.rotationRestDays) { value -> edit { it.copy(rotationRestDays = value) } }
        } else SetupWeekdaySelector(p.workdays, locale) { value ->
            edit { PreferencesRules.toggleWorkday(it, value) }
        }
        if (p.scheduleMode == "alternating") {
            ChoiceRow(stringResource(R.string.doubleRestWeek), p.alternatingWeekType == "double", { edit { it.copy(alternatingWeekType = "double") } })
            ChoiceRow(stringResource(R.string.singleRestWeek), p.alternatingWeekType == "single", { edit { it.copy(alternatingWeekType = "single") } })
            Row(Modifier.padding(horizontal = DoneAtSpacing.l), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                for ((day, label) in listOf(6 to DayOfWeek.SATURDAY, 0 to DayOfWeek.SUNDAY)) {
                    FilterChip(p.alternatingWeekendWorkday == day, { edit { it.copy(alternatingWeekendWorkday = day) } },
                        label = { Text(label.getDisplayName(TextStyle.FULL, locale)) })
                }
            }
        }
        RowDivider(inset = false)
        Box(Modifier.clickable { picksRegion = true }) { ValueRow(stringResource(R.string.holidayCalendar), if (region.isNullOrEmpty()) stringResource(R.string.holidayCalendarOff) else Locale.Builder().setRegion(region).build().getDisplayCountry(locale)) }
    }
    if (picksRegion) AlertDialog(onDismissRequest = { picksRegion = false }, title = { Text(stringResource(R.string.holidayCalendar)) },
        text = {
            Column(Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState())) {
                TextButton(onClick = { onRegion(""); picksRegion = false }) { Text(stringResource(R.string.holidayCalendarOff)) }
                holidays.regionIdentifiers.sortedBy { Locale.Builder().setRegion(it).build().getDisplayCountry(locale) }.forEach { code ->
                    TextButton(onClick = { onRegion(code); picksRegion = false }) { Text(Locale.Builder().setRegion(code).build().getDisplayCountry(locale)) }
                }
            }
        }, confirmButton = { TextButton(onClick = { picksRegion = false }) { Text(stringResource(R.string.close)) } })
}

@Composable
private fun SetupCounter(title: String, value: Int, change: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.l), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        IconButton(onClick = { change(value - 1) }, enabled = value > 1) { Icon(Icons.Outlined.Remove, "$title −") }
        Text(java.text.NumberFormat.getIntegerInstance(LocalResources.current.configuration.locales[0]).format(value))
        IconButton(onClick = { change(value + 1) }, enabled = value < 31) { Icon(Icons.Outlined.Add, "$title +") }
    }
}

@Composable
internal fun OnboardingWelcomeMark(modifier: Modifier) {
    val reduced = LocalDoneAtMotion.current.reduced || onboardingTouchExplorationEnabled()
    val hand = remember { Animatable(if (reduced) 0f else -120f) }
    var settled by remember { mutableStateOf(reduced) }
    LaunchedEffect(reduced) {
        if (reduced) hand.snapTo(0f)
        else hand.animateTo(0f, tween(DoneAtOnboardingTokens.WELCOME_HAND_MS, easing = DoneAtOnboardingTokens.welcomeEasing))
        settled = true
    }
    if (settled) CelebratingBrandMark(stringResource(R.string.app_name), modifier)
    else DoneAtBrandMark(modifier, handRotation = hand.value)
}


/** iOS welcomes each group at a 70 ms stagger; accessibility motion stays immediate. */
@Composable
internal fun Modifier.onboardingArrival(index: Int, enabled: Boolean): Modifier {
    if (!enabled) return this
    val reduced = LocalDoneAtMotion.current.reduced || onboardingTouchExplorationEnabled()
    val arrival = remember { Animatable(if (reduced) 1f else 0f) }
    val rise = with(LocalDensity.current) { 12.dp.toPx() }
    LaunchedEffect(reduced) {
        if (reduced) arrival.snapTo(1f)
        else {
            delay(index * DoneAtOnboardingTokens.WELCOME_STAGGER_MS.toLong())
            arrival.animateTo(1f, tween(DoneAtOnboardingTokens.PAGE_MS, easing = DoneAtOnboardingTokens.welcomeEasing))
        }
    }
    return graphicsLayer { alpha = arrival.value; translationY = (1f - arrival.value) * rise }
}


/** React immediately when TalkBack changes, including while this page is open. */
@Composable
internal fun onboardingTouchExplorationEnabled(): Boolean {
    val manager = LocalContext.current.getSystemService(AccessibilityManager::class.java)
    var enabled by remember(manager) { mutableStateOf(manager?.isTouchExplorationEnabled == true) }
    DisposableEffect(manager) {
        val listener = AccessibilityManager.TouchExplorationStateChangeListener { enabled = it }
        manager?.addTouchExplorationStateChangeListener(listener)
        onDispose { manager?.removeTouchExplorationStateChangeListener(listener) }
    }
    return enabled
}

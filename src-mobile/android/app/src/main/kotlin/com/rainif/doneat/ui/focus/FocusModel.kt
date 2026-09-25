package com.rainif.doneat.ui.focus

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Work
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.focus.FocusDayCanvas
import com.rainif.doneat.core.domain.focus.FocusNextAction
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.ui.timer.TimerText
import kotlinx.coroutines.delay

val FocusTaskIcon.image: ImageVector
    get() = when (this) {
        FocusTaskIcon.FOCUS -> Icons.Outlined.Timer
        FocusTaskIcon.WORK -> Icons.Outlined.Work
        FocusTaskIcon.CODE -> Icons.Outlined.Code
        FocusTaskIcon.STUDY -> Icons.AutoMirrored.Outlined.MenuBook
        FocusTaskIcon.WRITING -> Icons.Outlined.Edit
        FocusTaskIcon.COMMUNICATION -> Icons.Outlined.Email
        FocusTaskIcon.MEETING -> Icons.Outlined.Group
        FocusTaskIcon.IDEA -> Icons.Outlined.Lightbulb
    }

val FocusTaskIcon.title: Int
    get() = when (this) {
        FocusTaskIcon.FOCUS -> R.string.focusIconFocus
        FocusTaskIcon.WORK -> R.string.focusIconWork
        FocusTaskIcon.CODE -> R.string.focusIconCode
        FocusTaskIcon.STUDY -> R.string.focusIconStudy
        FocusTaskIcon.WRITING -> R.string.focusIconWriting
        FocusTaskIcon.COMMUNICATION -> R.string.focusIconCommunication
        FocusTaskIcon.MEETING -> R.string.focusIconMeeting
        FocusTaskIcon.IDEA -> R.string.focusIconIdea
    }

/**
 * One pass of the Focus page: the canvas and everything read beside it, built
 * once and passed down (iOS builds the model once per `body` for the same
 * reason: each read walks the shift).
 */
@Immutable
class FocusContext(
    val nowMs: Double,
    val state: RecordState,
    val canvas: FocusDayCanvas,
    val session: FocusSession?,
    val nextAction: FocusNextAction,
    val authorized: Boolean,
    val text: TimerText,
) {
    fun range(block: FocusDayCanvas.Block) = "${text.time(block.startAtMs.toDouble())} – ${text.time(block.endAtMs.toDouble())}"
    fun task(id: String?) = id?.let { taskID -> state.focusTasks.firstOrNull { it.id == taskID && it.deletedAtMs == null } }
}

/**
 * The page's clock: it moves on the minute and at the next block boundary or
 * phase end, only while the page is visible. The countdown ticks by itself.
 */
@Composable
fun rememberFocusContext(graph: AppGraph): FocusContext {
    val context = LocalContext.current
    val state by graph.records.state.collectAsStateWithLifecycle()
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val authorized by graph.plus.authorized.collectAsStateWithLifecycle()
    val nextAction by graph.focus.nextAction.collectAsStateWithLifecycle()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var now by remember { mutableDoubleStateOf(graph.nowMs()) }
    val canvas = remember(state, session, authorized, now) { graph.focus.canvas(now, state) }
    // Keyed on the lifecycle alone: a new canvas must not restart the clock,
    // or setting `now` rebuilds the canvas and spins the page every frame.
    val latestCanvas by rememberUpdatedState(canvas)
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                val current = graph.nowMs()
                now = current
                graph.focus.finishElapsed(current)
                val nextMinute = (kotlin.math.floor(current / 60_000) + 1) * 60_000
                val boundary = latestCanvas.blocks.flatMap { listOf(it.startAtMs, it.endAtMs) }.map { it.toDouble() }.filter { it > current }.minOrNull() ?: nextMinute
                val end = graph.focus.activeSession(graph.records.state.value)?.plannedEndAtMs ?: nextMinute
                delay((minOf(boundary, nextMinute, end) - current).toLong().coerceAtLeast(100))
            }
        }
    }
    val text = TimerText(LocalResources.current, LocalConfiguration.current.locales[0], android.text.format.DateFormat.is24HourFormat(context), hideEarnings = false)
    return FocusContext(now, state, canvas, graph.focus.activeSession(state), nextAction, authorized, text)
}

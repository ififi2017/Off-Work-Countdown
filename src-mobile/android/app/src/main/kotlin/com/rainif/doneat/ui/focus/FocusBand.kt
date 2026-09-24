package com.rainif.doneat.ui.focus

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Coffee
import androidx.compose.material.icons.outlined.Restaurant
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.LocalDoneAtRecordsColors
import com.rainif.doneat.core.domain.focus.FocusDayCanvas
import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.records.RecordsCard
import kotlin.math.abs

/**
 * The shift, drawn to scale (iOS `FocusBandView`). Vertical, because one block
 * is one target and a whole shift across a phone's width cannot give a
 * 25-minute block a 48 dp target. Proportion is the point, so nothing has a
 * minimum height: a five-minute break is a fifth of a focus block.
 */
@Composable
fun FocusBand(
    context: FocusContext,
    model: FocusDayCanvas,
    selectedBlock: Long?,
    isPreview: Boolean = false,
    onPick: (FocusDayCanvas.Block) -> Unit,
) {
    // At large text the band's meaning is in heights the text then eats; the list keeps the same order and actions.
    if (LocalDensity.current.fontScale >= 1.5f) {
        FocusBandList(context, model, isPreview, onPick)
        return
    }
    val hour = 3_600_000L
    val total = (model.shiftEndAtMs - model.shiftStartAtMs).coerceAtLeast(0)
    val scheme = MaterialTheme.colorScheme
    fun y(ms: Long) = model.offset(ms).dp
    fun h(ms: Long) = model.height(ms).dp
    val nowMs = model.nowAtMs?.takeIf { !isPreview }
    Row(Modifier.fillMaxWidth().height(h(total))) {
        // The ruler: whole hours of this shift, which keeps counting past midnight rather than restarting.
        Box(Modifier.width(58.dp).fillMaxHeight().padding(end = 8.dp).clearAndSetSemantics {}) {
            var mark = (model.shiftStartAtMs / hour) * hour
            if (mark < model.shiftStartAtMs) mark += hour
            while (mark <= model.shiftEndAtMs) {
                val near = nowMs != null && abs(model.offset(mark) - model.offset(nowMs)) < 20
                if (!near) {
                    Text(
                        context.text.time(mark.toDouble()),
                        Modifier.align(Alignment.TopEnd).offset(y = y(mark) - 7.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = scheme.outline,
                        maxLines = 1,
                    )
                }
                mark += hour
            }
            if (nowMs != null) {
                Text(
                    context.text.time(context.nowMs),
                    Modifier.align(Alignment.TopEnd).offset(y = y(nowMs) - 9.dp)
                        .background(scheme.surface, CircleShape)
                        .background(scheme.primary.copy(alpha = 0.16f), CircleShape)
                        .padding(horizontal = 5.dp, vertical = 2.dp),
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1,
                )
            }
        }
        Box(Modifier.weight(1f).fillMaxHeight()) {
            model.gaps.forEach { gap -> GapTile(context, gap, Modifier.offset(y = y(gap.startAtMs)).height(h(gap.endAtMs - gap.startAtMs))) }
            model.blocks.forEach { block ->
                BlockTile(
                    context, block, selectedBlock == block.startAtMs, isPreview, onPick,
                    Modifier.offset(y = y(block.startAtMs)).height(h(block.endAtMs - block.startAtMs)),
                )
            }
            if (nowMs != null) {
                // On the rail, so it never strikes through a task title as it moves.
                Box(Modifier.offset(x = (-3.5).dp, y = y(nowMs) - 3.5.dp).size(7.dp).background(scheme.primary, CircleShape).clearAndSetSemantics {})
            }
        }
    }
}

/** Lunch belongs to the shift; the leftover a segment cannot fill is only an outline. */
@Composable
private fun GapTile(context: FocusContext, gap: FocusDayCanvas.Gap, modifier: Modifier) {
    val res = LocalResources.current
    val breakColor = LocalDoneAtRecordsColors.current.workBreak
    val scheme = MaterialTheme.colorScheme
    val height = context.canvas.height(gap.endAtMs - gap.startAtMs)
    when (gap.kind) {
        FocusDayCanvas.Gap.Kind.BETWEEN_SEGMENTS -> {
            val detail = "${Strings.lunchWindow(res, context.text.time(gap.startAtMs.toDouble()), context.text.time(gap.endAtMs.toDouble()))} · " +
                context.text.relativeDuration((gap.endAtMs - gap.startAtMs).toDouble())
            val title = res.getString(R.string.extendedBreak)
            Row(
                modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(breakColor.copy(alpha = 0.10f)).padding(start = 14.dp)
                    .clearAndSetSemantics { contentDescription = "$title · $detail" },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (height >= 44) {
                    Icon(Icons.Outlined.Restaurant, null, Modifier.size(16.dp), tint = breakColor)
                    Column {
                        Text(title, style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
                        Text(detail, style = MaterialTheme.typography.labelSmall, color = scheme.outline)
                    }
                } else if (height >= 20) {
                    Text(title, style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant)
                }
            }
        }
        FocusDayCanvas.Gap.Kind.TAIL -> Box(
            modifier.fillMaxWidth().dashedBorder(scheme.outlineVariant, 4.dp).padding(start = 14.dp).clearAndSetSemantics {},
            contentAlignment = Alignment.CenterStart,
        ) {
            if (height >= 20) Text(Strings.focusBandGapTooShort(res, gap.durationMinutes.toString()), style = MaterialTheme.typography.labelSmall, color = scheme.outline)
        }
    }
}

private fun Modifier.dashedBorder(color: Color, radius: Dp) = drawBehind {
    drawRoundRect(color, cornerRadius = CornerRadius(radius.toPx()), style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))))
}

fun spokenLabel(context: FocusContext, res: android.content.res.Resources, block: FocusDayCanvas.Block): String {
    val time = context.text.time(block.startAtMs.toDouble())
    val minutes = ((block.endAtMs - block.startAtMs) / 60_000).toString()
    if (block.rendersAsBreak) return "$time · ${Strings.focusBandBreakMinutes(res, minutes)}"
    val what = block.taskTitle ?: res.getString(R.string.focusBandEmptyBlock)
    val state = when (block.state) {
        FocusDayCanvas.State.PAST -> res.getString(R.string.focusBandStatePast)
        FocusDayCanvas.State.CURRENT -> res.getString(R.string.focusBandStateCurrent)
        FocusDayCanvas.State.FUTURE -> ""
    }
    return listOf(time, what, state).filter { it.isNotEmpty() }.joinToString(" · ")
}

@Composable
private fun BlockTile(
    context: FocusContext,
    block: FocusDayCanvas.Block,
    selected: Boolean,
    isPreview: Boolean,
    onPick: (FocusDayCanvas.Block) -> Unit,
    modifier: Modifier,
) {
    val res = LocalResources.current
    val scheme = MaterialTheme.colorScheme
    val breakColor = LocalDoneAtRecordsColors.current.workBreak
    val height = context.canvas.height(block.endAtMs - block.startAtMs)
    val pickable = block.kind == FocusPlanBlockKind.TASK && (block.isEditable || block.isAssigned)
    val shape = RoundedCornerShape(6.dp)
    val outline = when {
        block.state == FocusDayCanvas.State.CURRENT -> Modifier.border(2.dp, scheme.primary, shape)
        selected -> Modifier.border(2.dp, scheme.primary.copy(alpha = 0.6f), shape)
        else -> Modifier
    }
    val label = spokenLabel(context, res, block)
    val hint = res.getString(if (isPreview) R.string.plusSeePlans else R.string.focusBandBlockHint)
    Box(
        modifier
            .fillMaxWidth()
            .alpha(if (block.state == FocusDayCanvas.State.PAST) 0.45f else 1f)
            .clip(shape)
            .then(if (pickable) Modifier.clickable { onPick(block) } else Modifier)
            .clearAndSetSemantics {
                contentDescription = label
                if (pickable) {
                    role = Role.Button
                    this.selected = selected
                    onClick(hint) { onPick(block); true }
                }
            }
            .then(outline),
    ) {
        if (block.rendersAsBreak) {
            Box(Modifier.matchParentSize().background(breakColor.copy(alpha = 0.16f)))
            Box(Modifier.width(3.5.dp).fillMaxHeight().background(breakColor))
            if (height >= 20) {
                Row(Modifier.align(Alignment.CenterStart).padding(start = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Outlined.Coffee, null, Modifier.size(12.dp), tint = breakColor)
                    Text(Strings.focusBandBreakMinutes(res, ((block.endAtMs - block.startAtMs) / 60_000).toString()), style = MaterialTheme.typography.labelSmall, color = breakColor)
                }
            }
        } else {
            if (block.isAssigned) {
                Box(Modifier.matchParentSize().background(scheme.primary.copy(alpha = 0.12f)))
                Box(Modifier.width(3.5.dp).fillMaxHeight().background(scheme.primary))
            } else {
                Box(Modifier.matchParentSize().dashedBorder(scheme.outline, 6.dp))
            }
            Column(Modifier.align(Alignment.CenterStart).padding(start = 14.dp, end = 10.dp)) {
                Text(context.text.time(block.startAtMs.toDouble()), style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant)
                val title = block.taskTitle
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (title != null) {
                        Icon((block.taskIcon ?: com.rainif.doneat.core.domain.records.FocusTaskIcon.FOCUS).image, null, Modifier.size(16.dp), tint = scheme.onSurface)
                        Text(title, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    } else {
                        Icon(Icons.Outlined.Add, null, Modifier.size(14.dp), tint = scheme.onSurfaceVariant)
                        Text(res.getString(R.string.focusBandEmptyBlock), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
                    }
                }
            }
            if (block.state == FocusDayCanvas.State.PAST && block.isAssigned) {
                Icon(Icons.Outlined.Check, null, Modifier.align(Alignment.CenterEnd).padding(end = 12.dp).size(16.dp), tint = scheme.onSurfaceVariant)
            }
        }
    }
}

/** The band as a list: the large-text layout, with the same order, states and actions. */
@Composable
private fun FocusBandList(context: FocusContext, model: FocusDayCanvas, isPreview: Boolean, onPick: (FocusDayCanvas.Block) -> Unit) {
    val res = LocalResources.current
    val scheme = MaterialTheme.colorScheme
    val rows = model.blocks.filter { it.kind == FocusPlanBlockKind.TASK || it.endAtMs - it.startAtMs >= 5 * 60_000 }
    RecordsCard {
        Column {
            rows.forEachIndexed { index, block ->
                if (index > 0) HorizontalDivider(Modifier.padding(start = 56.dp), color = scheme.outlineVariant)
                val pickable = block.kind == FocusPlanBlockKind.TASK && (block.isEditable || block.isAssigned)
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp)
                        .then(if (pickable) Modifier.clickable(role = Role.Button) { onPick(block) } else Modifier)
                        .clearAndSetSemantics {
                            contentDescription = spokenLabel(context, res, block)
                            if (pickable) onClick(if (isPreview) res.getString(R.string.plusSeePlans) else null) { onPick(block); true }
                        }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Icon(if (block.rendersAsBreak) Icons.Outlined.Coffee else (block.taskIcon ?: com.rainif.doneat.core.domain.records.FocusTaskIcon.FOCUS).image, null, tint = scheme.onSurfaceVariant)
                    Column {
                        Text(context.text.time(block.startAtMs.toDouble()), style = MaterialTheme.typography.bodyLarge)
                        val what = if (block.rendersAsBreak) {
                            Strings.focusBandBreakMinutes(res, ((block.endAtMs - block.startAtMs) / 60_000).toString())
                        } else {
                            val title = block.taskTitle ?: res.getString(R.string.focusBandEmptyBlock)
                            when (block.state) {
                                FocusDayCanvas.State.PAST -> "$title · ${res.getString(R.string.focusBandStatePast)}"
                                FocusDayCanvas.State.CURRENT -> "$title · ${res.getString(R.string.focusBandStateCurrent)}"
                                FocusDayCanvas.State.FUTURE -> title
                            }
                        }
                        Text(what, style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

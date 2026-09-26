package com.rainif.doneat.ui.records

import androidx.compose.animation.core.animateIntOffsetAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import kotlin.math.roundToInt

/** Match iOS: above the selected cell, below near the top, inside the chart edges. */
internal fun recordsCalloutOffset(anchor: Rect, label: IntSize, chart: IntSize, inset: Int): IntOffset {
    val above = anchor.top - inset - label.height
    val y = if (above >= inset) above else anchor.bottom + inset
    return IntOffset(
        (anchor.center.x - label.width / 2f).roundToInt().coerceIn(inset, maxOf(inset, chart.width - inset - label.width)),
        y.roundToInt().coerceIn(inset, maxOf(inset, chart.height - inset - label.height)),
    )
}

/** Only the label moves; its text changes immediately and the chart stays still. */
@Composable
internal fun RecordsCallout(anchor: Rect, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val motion = LocalDoneAtMotion.current
    val density = LocalDensity.current
    var labelSize by remember { mutableStateOf(IntSize.Zero) }
    BoxWithConstraints(modifier) {
        val chartSize = IntSize(constraints.maxWidth, constraints.maxHeight)
        val inset = with(density) { DoneAtSpacing.s.roundToPx() }
        val ready = labelSize != IntSize.Zero
        val offset = if (ready) {
            val target = recordsCalloutOffset(anchor, labelSize, chartSize, inset)
            val animated by animateIntOffsetAsState(target, motion.selection(), label = "Records callout position")
            animated
        } else IntOffset.Zero
        Box(
            Modifier.absoluteOffset { offset }
                .widthIn(max = minOf(300.dp, (maxWidth - DoneAtSpacing.l).coerceAtLeast(0.dp)))
                .onSizeChanged { labelSize = it }
                .graphicsLayer { alpha = if (ready) 1f else 0f },
        ) { content() }
    }
}

/** Measures the selected day relative to its chart, including RTL and scaled text. */
@Composable
internal fun RecordsDaySelection(
    selectedID: String?,
    callout: @Composable () -> Unit,
    chart: @Composable (selectionAnchor: Modifier) -> Unit,
) {
    var chartCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var anchor by remember { mutableStateOf<Rect?>(null) }
    Box(Modifier.onGloballyPositioned { chartCoordinates = it }) {
        chart(Modifier.onGloballyPositioned { cell ->
            chartCoordinates?.takeIf { it.isAttached }?.let { parent ->
                anchor = parent.localBoundingBoxOf(cell, clipBounds = false)
            }
        })
        if (selectedID != null) {
            anchor?.let { RecordsCallout(it, Modifier.matchParentSize(), callout) }
        }
    }
}

/** Compact shared day/month/stage label. Only actionable labels intercept touches. */
@Composable
internal fun RecordsSelectionPill(
    icon: ImageVector,
    title: String,
    subtitle: String?,
    action: String? = null,
    onClick: (() -> Unit)? = null,
) {
    val scheme = MaterialTheme.colorScheme
    val label: @Composable () -> Unit = {
        Row(
            Modifier.heightIn(min = if (onClick != null) DoneAtSpacing.minTouch else 0.dp)
                .padding(horizontal = DoneAtSpacing.m, vertical = DoneAtSpacing.s),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s),
        ) {
            Icon(icon, null, Modifier.size(16.dp), tint = scheme.onSurfaceVariant)
            Column(Modifier.weight(1f, fill = false)) {
                Text(title, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant)
                if (action != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(action, Modifier.weight(1f, fill = false), style = MaterialTheme.typography.labelMedium, color = scheme.primary)
                        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, Modifier.size(14.dp), tint = scheme.primary)
                    }
                }
            }
        }
    }
    val border = BorderStroke(0.8.dp, scheme.outlineVariant)
    if (onClick != null) {
        Surface(onClick = onClick, shape = CircleShape, color = scheme.surfaceContainerHigh, border = border, content = label)
    } else {
        // A decorative label must not swallow another tap on the canvas below it.
        Box(Modifier.background(scheme.surfaceContainerHigh, CircleShape).border(border, CircleShape)) { label() }
    }
}

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

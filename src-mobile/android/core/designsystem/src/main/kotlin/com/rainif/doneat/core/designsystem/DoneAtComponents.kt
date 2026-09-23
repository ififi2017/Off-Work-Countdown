package com.rainif.doneat.core.designsystem

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow

/**
 * The one highest-emphasis action on a screen (plan 01 §7.2). A pill at rest
 * that squares toward [DoneAtShapes.pressedActionCorner] while pressed: the
 * Expressive shape morph, built from stable APIs (D-12). With reduced motion
 * the shape changes without animating.
 */
@Composable
fun DoneAtPrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    // Half the measured height, so the button stays a pill when a large font makes it taller.
    val density = LocalDensity.current
    var height by remember { mutableStateOf(DoneAtShapes.actionHeight) }
    val corner by animateDpAsState(
        if (pressed) DoneAtShapes.pressedActionCorner else height / 2,
        LocalDoneAtMotion.current.spatial(),
        label = "primaryActionCorner",
    )
    Button(
        onClick = onClick,
        modifier = modifier
            .defaultMinSize(minHeight = DoneAtShapes.actionHeight)
            .onSizeChanged { height = with(density) { it.height.toDp() } },
        enabled = enabled,
        shape = RoundedCornerShape(corner),
        contentPadding = PaddingValues(horizontal = DoneAtSpacing.xl, vertical = DoneAtSpacing.m),
        interactionSource = interaction,
    ) {
        Text(text, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
    }
}

/**
 * Ending something (stopping the day, clearing a plan): outlined in the error
 * colour so it is never mistaken for the filled start action beside it.
 */
@Composable
fun DoneAtDestructiveButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minHeight = DoneAtSpacing.minTouch),
        enabled = enabled,
        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
        border = ButtonDefaults.outlinedButtonBorder(enabled).copy(brush = SolidColor(MaterialTheme.colorScheme.error)),
    ) {
        Text(text, textAlign = TextAlign.Center)
    }
}

/** A grouped container: tonal surface, the large (22 dp) corner, no shadow. */
@Composable
fun DoneAtCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier = modifier, shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), content = content)
    }
}

/** What the day is doing. Each phase has its own label; colour only reinforces it. */
enum class DoneAtPhase { WORK, REST, OFF_WORK, OVERTIME }

@Composable
fun DoneAtPhaseBadge(phase: DoneAtPhase, label: String, modifier: Modifier = Modifier) {
    val colors = LocalDoneAtStateColors.current
    val motion = LocalDoneAtMotion.current
    val (container, content) = when (phase) {
        DoneAtPhase.WORK -> colors.work to colors.onWork
        DoneAtPhase.REST -> colors.rest to colors.onRest
        DoneAtPhase.OFF_WORK -> colors.offWork to colors.onOffWork
        DoneAtPhase.OVERTIME -> colors.overtime to colors.onOvertime
    }
    val background by animateColorAsState(container, motion.phase(), label = "phaseContainer")
    val foreground by animateColorAsState(content, motion.phase(), label = "phaseContent")
    Surface(modifier = modifier, shape = CircleShape, color = background, contentColor = foreground) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = DoneAtSpacing.m, vertical = DoneAtSpacing.xs),
            style = MaterialTheme.typography.labelLarge,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * The main countdown. Tabular figures keep its width still; [spokenLabel]
 * replaces the digits for TalkBack so it is not re-read every second.
 */
@Composable
fun DoneAtCountdown(text: String, spokenLabel: String, modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.onSurface) {
    Text(
        text,
        modifier = modifier.clearAndSetSemantics { contentDescription = spokenLabel },
        style = DoneAtType.countdown,
        color = color,
        maxLines = 1,
        textAlign = TextAlign.Center,
    )
}

/** A label and value on one row that wraps under large fonts instead of truncating. */
@Composable
fun DoneAtValueRow(label: String, value: String, modifier: Modifier = Modifier, trailing: @Composable RowScope.() -> Unit = {}) {
    Row(
        modifier = modifier.defaultMinSize(minHeight = DoneAtSpacing.minTouch),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m),
    ) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Text(value, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.End)
        trailing()
    }
}


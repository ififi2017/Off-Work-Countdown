package com.rainif.doneat.core.designsystem

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterExitState
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.animateDp
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp

/**
 * The main countdown, with each digit rolling over as it changes (iOS
 * `OWCCountdownTextTransition`, which uses `.numericText(countsDown: true)`).
 *
 * - Only the digits that changed move: each position animates on its own, so
 *   most seconds only the last digit rolls. Tabular figures keep every
 *   position the same width, so nothing around it re-lays out.
 * - [countsDown]: the old digit leaves downward and the new one arrives from
 *   above, as a countdown reads; `false` rolls the other way (counts going up).
 * - Movement, fade and a light blur (Android 12+; older versions skip the
 *   blur) over `DoneAtMotion.countdownTick`. Reduced motion swaps digits in place.
 * - TalkBack hears [spokenLabel] once instead of the digits every second.
 */
@Composable
fun DoneAtCountdown(
    text: String,
    spokenLabel: String,
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.onSurface,
    style: TextStyle = DoneAtType.countdown,
    countsDown: Boolean = true,
) {
    val motion = LocalDoneAtMotion.current
    // A clock reads left to right in every language; a mirrored row would show SS:MM:HH in Arabic.
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Row(
            modifier.clearAndSetSemantics { contentDescription = spokenLabel },
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            text.forEach { char ->
                if (motion.reduced || !char.isDigit()) {
                    Text(char.toString(), style = style, color = color, maxLines = 1)
                } else {
                    RollingDigit(char, style, color, countsDown, motion)
                }
            }
        }
    }
}

@Composable
private fun RollingDigit(digit: Char, style: TextStyle, color: Color, countsDown: Boolean, motion: DoneAtMotion) {
    AnimatedContent(
        targetState = digit,
        transitionSpec = {
            // A partial travel with a fade reads as a roll without the digit leaving its line.
            val direction = if (countsDown) 1 else -1
            ContentTransform(
                targetContentEnter = slideInVertically(motion.countdownTick()) { -direction * it * ROLL / 100 } + fadeIn(motion.countdownTick()),
                initialContentExit = slideOutVertically(motion.countdownTick()) { direction * it * ROLL / 100 } + fadeOut(motion.countdownTick()),
                sizeTransform = SizeTransform(clip = false),
            )
        },
        contentAlignment = Alignment.Center,
        label = "countdownDigit",
    ) { value ->
        val blur by transition.animateDp(transitionSpec = { motion.countdownTick() }, label = "digitBlur") {
            if (it == EnterExitState.Visible) 0.dp else BLUR
        }
        Text(
            value.toString(),
            modifier = Modifier.blur(blur, BlurredEdgeTreatment.Unbounded),
            style = style,
            color = color,
            maxLines = 1,
        )
    }
}

/** Match the Web clock's 0.3 em travel; the longer tick leaves time to see the blur resolve. */
private const val ROLL = 30
private val BLUR = 3.dp

/*
 * Glass layering adapted from Kyant0/AndroidLiquidGlass's LiquidBottomTabs,
 * Copyright Kyant, Apache-2.0 (see app/src/main/assets/licenses/Backdrop.txt).
 * Modified for DoneAt: native tab semantics, cancellable drag, app theme,
 * flexible text height, RTL, reduced motion, and older Android fallback.
 */
package com.rainif.doneat.core.designsystem

import android.os.Build
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberCombinedBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import com.kyant.backdrop.highlight.Highlight
import com.kyant.backdrop.shadow.InnerShadow
import com.kyant.backdrop.shadow.Shadow
import kotlin.math.roundToInt

/** Extra space above the system inset: inside scroll content, outside pinned controls. */
val LocalDoneAtBottomBarPadding = staticCompositionLocalOf { 0.dp }

data class DoneAtNavigationItem(val title: String, val icon: ImageVector)

private object GlassNavigation {
    val shape = RoundedCornerShape(50)
    val minHeight = 64.dp
    val iconSize = 24.dp
    val blur = 8.dp
    val lensHeight = 14.dp
    val lensAmount = 24.dp
    val lift = 3.dp
    val verticalTravel = 8.dp
    val shadow = Shadow(radius = 12.dp, color = Color.Black.copy(alpha = 0.09f))
    val highlight = Highlight(alpha = 0.25f)
    const val LIGHT_ALPHA = 0.32f
    const val DARK_ALPHA = 0.48f
    const val PRESSED_SCALE = 1.32f
    const val CONTENT_SCALE = 1.2f
}

/** Physical pointer coordinates to logical tab position, including RTL and end stops. */
internal fun glassTabPosition(x: Float, width: Int, count: Int, rtl: Boolean): Float {
    if (width <= 0 || count <= 1) return 0f
    val fraction = x / width
    return ((if (rtl) 1f - fraction else fraction) * count - 0.5f).coerceIn(0f, (count - 1).toFloat())
}

/** One page capture; the floating lens additionally samples an enlarged tab-label layer. */
@Composable
fun DoneAtGlassNavigation(
    items: List<DoneAtNavigationItem>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    content: @Composable () -> Unit,
) {
    require(items.isNotEmpty() && selectedIndex in items.indices)
    val colors = MaterialTheme.colorScheme
    val density = LocalDensity.current
    val keyboardVisible = WindowInsets.ime.getBottom(density) > 0
    var barHeight by remember { mutableStateOf(GlassNavigation.minHeight + DoneAtSpacing.s * 2) }
    val background = colors.surface
    val backdrop = rememberLayerBackdrop { drawRect(background); drawContent() }
    val supportsBlur = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    Box(Modifier.fillMaxSize().background(background)) {
        CompositionLocalProvider(LocalDoneAtBottomBarPadding provides if (keyboardVisible) 0.dp else barHeight) {
            Box(Modifier.fillMaxSize().then(if (supportsBlur) Modifier.layerBackdrop(backdrop) else Modifier)) {
                content()
            }
        }
        if (!keyboardVisible) {
            Box(Modifier.align(Alignment.BottomCenter)
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
                .onSizeChanged { barHeight = with(density) { it.height.toDp() } }
                .padding(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.s)) {
                GlassTabBar(items, selectedIndex, onSelect, backdrop, supportsBlur)
            }
        }
    }
}

@Composable
private fun GlassTabBar(
    items: List<DoneAtNavigationItem>, selectedIndex: Int, onSelect: (Int) -> Unit,
    backdrop: Backdrop, supportsBlur: Boolean,
) {
    val colors = MaterialTheme.colorScheme
    val motion = LocalDoneAtMotion.current
    val density = LocalDensity.current
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsState()
    val interactive = lifecycle == Lifecycle.State.RESUMED && LocalWindowInfo.current.isWindowFocused
    val latestSelect by rememberUpdatedState(onSelect)
    var pressed by remember { mutableStateOf(false) }
    var dragPosition by remember { mutableStateOf<Float?>(null) }
    var verticalDrag by remember { mutableFloatStateOf(0f) }
    var rowWidth by remember { mutableIntStateOf(0) }
    val progress by animateFloatAsState(if (pressed && !motion.reduced) 1f else 0f,
        motion.press(), label = "glassPress")
    val position by animateFloatAsState(
        if (motion.reduced) selectedIndex.toFloat() else dragPosition ?: selectedIndex.toFloat(),
        if (pressed) motion.tracking() else motion.spatial(), label = "glassPosition")
    val verticalOffset by animateFloatAsState(if (pressed && !motion.reduced) verticalDrag else 0f,
        motion.tracking(), label = "glassVerticalOffset")
    val dark = colors.surface.luminance() < 0.5f
    val tint = colors.surfaceContainer.copy(alpha = when {
        !supportsBlur -> 1f
        dark -> GlassNavigation.DARK_ALPHA
        else -> GlassNavigation.LIGHT_ALPHA
    })
    val tabsBackdrop = rememberLayerBackdrop()
    val lensBackdrop = rememberCombinedBackdrop(backdrop, tabsBackdrop)
    val travelPx = with(density) { GlassNavigation.verticalTravel.toPx() }

    Box(Modifier.fillMaxWidth()) {
        // drawBackdrop clips its children. Keep the bar and lens as siblings so
        // the pressed lens can grow past the bar's capsule without being cut off.
        Box(Modifier.matchParentSize().then(if (supportsBlur) Modifier.drawBackdrop(
            backdrop, shape = { GlassNavigation.shape },
            effects = { blur(GlassNavigation.blur.toPx()); lens(GlassNavigation.lensHeight.toPx(), GlassNavigation.lensAmount.toPx()) },
            highlight = { GlassNavigation.highlight }, shadow = { GlassNavigation.shadow },
            onDrawSurface = { drawRect(tint) },
        ) else Modifier.background(tint, GlassNavigation.shape)))
        Box(Modifier.padding(DoneAtSpacing.xs)
        .selectableGroup()
        .pointerInput(items.size, rtl, interactive) {
            if (!interactive) return@pointerInput
            // Observe taps without stealing them from selectable/TalkBack. Take ownership
            // only after touch slop; dragging never navigates until a successful release.
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                var dragging = false
                pressed = true
                dragPosition = glassTabPosition(down.position.x, size.width, items.size, rtl).roundToInt().toFloat()
                try {
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (event.changes.count { it.pressed } > 1 || change.isConsumed) break
                        if ((change.position - down.position).getDistance() > viewConfiguration.touchSlop) dragging = true
                        if (dragging) {
                            change.consume()
                            dragPosition = glassTabPosition(change.position.x, size.width, items.size, rtl)
                            verticalDrag = (change.position.y - down.position.y).coerceIn(-travelPx, travelPx)
                        }
                        if (!change.pressed) {
                            if (dragging && change.position.y in -size.height.toFloat()..size.height * 2f) {
                                latestSelect(checkNotNull(dragPosition).roundToInt())
                            }
                            break
                        }
                    }
                } finally {
                    // Includes pointer cancellation, app backgrounding, rotation and IME.
                    pressed = false
                    dragPosition = null
                    verticalDrag = 0f
                }
            }
        }) {
        if (!supportsBlur) {
            Box(Modifier.matchParentSize()) {
                Box(Modifier.align(AbsoluteAlignment.TopLeft).fillMaxHeight().fillMaxWidth(1f / items.size).graphicsLayer {
                    translationX = (if (rtl) items.lastIndex - position else position) * rowWidth / items.size
                }.background(colors.surfaceContainerHighest, GlassNavigation.shape))
            }
        }
        TabLabels(items, selectedIndex, onSelect, Modifier.fillMaxWidth().height(IntrinsicSize.Min)
            .onSizeChanged { rowWidth = it.width }, lensLayer = false,
            selectedInLens = supportsBlur, scale = { 1f })
        if (supportsBlur) {
            // This row is invisible and has no input/semantics. The lens samples its
            // enlarged orange labels, without duplicating accessibility targets.
            TabLabels(items, selectedIndex, onSelect,
                Modifier.matchParentSize().clearAndSetSemantics {}.alpha(0f).layerBackdrop(tabsBackdrop)
                    .drawBackdrop(backdrop, shape = { GlassNavigation.shape },
                        effects = { blur(GlassNavigation.blur.toPx()) },
                        highlight = null, shadow = null, onDrawSurface = { drawRect(tint) }),
                lensLayer = true, selectedInLens = true,
                scale = { 1f + (GlassNavigation.CONTENT_SCALE - 1f) * progress })
            Box(Modifier.matchParentSize().clearAndSetSemantics {}) {
                Box(Modifier.align(AbsoluteAlignment.TopLeft).fillMaxHeight().fillMaxWidth(1f / items.size)
                    .graphicsLayer {
                        translationX = (if (rtl) items.lastIndex - position else position) * rowWidth / items.size
                        translationY = verticalOffset - GlassNavigation.lift.toPx() * progress
                    }
                    .drawBackdrop(
                        backdrop = lensBackdrop, shape = { GlassNavigation.shape },
                        effects = { lens(10.dp.toPx() * progress, 14.dp.toPx() * progress, chromaticAberration = true) },
                        highlight = { Highlight(alpha = progress) },
                        shadow = { GlassNavigation.shadow.copy(alpha = progress) },
                        innerShadow = { InnerShadow(radius = 8.dp, alpha = progress) },
                        layerBlock = {
                            val scale = 1f + (GlassNavigation.PRESSED_SCALE - 1f) * progress
                            scaleX = scale
                            scaleY = scale
                        },
                        onDrawSurface = {
                            drawRect((if (dark) Color.White else Color.Black).copy(alpha = 0.08f * (1f - progress)))
                        },
                    ))
            }
        }
        }
    }
}

@Composable
private fun TabLabels(
    items: List<DoneAtNavigationItem>, selectedIndex: Int, onSelect: (Int) -> Unit,
    modifier: Modifier, lensLayer: Boolean, selectedInLens: Boolean, scale: () -> Float,
) {
    val colors = MaterialTheme.colorScheme
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        items.forEachIndexed { index, item ->
            val foreground = if (lensLayer || (!selectedInLens && index == selectedIndex)) colors.primary else colors.onSurface
            Column(Modifier.weight(1f).fillMaxHeight().heightIn(min = GlassNavigation.minHeight)
                .then(if (lensLayer) Modifier else Modifier.selectable(index == selectedIndex,
                    interactionSource = null, indication = null, role = Role.Tab, onClick = { onSelect(index) }))
                .graphicsLayer { scaleX = scale(); scaleY = scale() }
                .padding(horizontal = DoneAtSpacing.xs, vertical = DoneAtSpacing.s),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs, Alignment.CenterVertically)) {
                Icon(item.icon, null, Modifier.size(GlassNavigation.iconSize), tint = foreground)
                Text(item.title, color = foreground, style = MaterialTheme.typography.labelMedium,
                    textAlign = TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

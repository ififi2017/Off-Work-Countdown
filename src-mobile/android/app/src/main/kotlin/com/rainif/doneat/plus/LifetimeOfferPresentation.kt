package com.rainif.doneat.plus

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.findRootCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.currentStateAsState
import androidx.lifecycle.repeatOnLifecycle
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtOfferTokens
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.l10n.Strings
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.text.NumberFormat
import java.util.Date
import java.util.Locale
import kotlin.math.floor

/** Used by the purchase page and onboarding's offer slot; all prices are current Play terms. */
@Composable
fun LifetimeOfferCard(plus: PlusAccess, modifier: Modifier = Modifier, active: Boolean = true) {
    val offer by plus.lifetimeOffer.collectAsStateWithLifecycle()
    val store by plus.state.collectAsStateWithLifecycle()
    val authorized by plus.authorized.collectAsStateWithLifecycle()
    val invitation = offer ?: return
    val price = store.discountedLifetimeOffer ?: return
    if (authorized || !plus.hasAvailableLifetimeOffer) return
    val now = observeOfferClock(plus)
    // A priced reveal, including reopening an unopened invitation, starts the one local deadline.
    var priceVisible by remember { mutableStateOf(false) }
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    LaunchedEffect(price, invitation.claimedAtMs, priceVisible, active, lifecycleState) {
        if (active && lifecycleState == Lifecycle.State.RESUMED && priceVisible && invitation.claimedAtMs == null) plus.claimLifetimeOffer()
    }
    val activity = LocalContext.current.activity()
    LifetimeOfferCardContent(invitation, price, now, activity != null && !store.busy,
        onClaim = { plus.claimLifetimeOffer() },
        onPurchase = { activity?.let { plus.purchaseLifetimeOffer(it, price) } },
        modifier = modifier, onPriceVisible = { priceVisible = true })
}

/** Data-only rendering for the debug gallery. Its callbacks never acquire billing or entitlement access. */
@Composable
internal fun LifetimeOfferCardContent(
    invitation: LifetimeOffer,
    price: PlusOffer,
    nowMs: Long,
    enabled: Boolean,
    onClaim: () -> Unit,
    onPurchase: () -> Unit,
    modifier: Modifier = Modifier,
    onPriceVisible: () -> Unit = {},
) {
    val reduced = LocalDoneAtMotion.current.reduced || offerTouchExplorationEnabled()
    val entrance = remember { Animatable(if (reduced) 1f else 0f) }
    LaunchedEffect(reduced) { if (reduced) entrance.snapTo(1f) else entrance.animateTo(1f, DoneAtOfferTokens.reveal(false)) }
    val density = LocalDensity.current
    val locale = LocalConfiguration.current.locales[0]
    val resources = LocalResources.current
    val deadline = invitation.expiresAtMs?.let { offerDeadline(it, locale) }
    val savings = savingsLabel(price, locale)?.let { Strings.plusOfferSavings(resources, it) }
    Surface(
        modifier.fillMaxWidth().graphicsLayer {
            alpha = entrance.value
            translationY = if (reduced) 0f else with(density) { DoneAtOfferTokens.revealDistance.toPx() } * (1f - entrance.value)
        },
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.primary.copy(alpha = DoneAtOfferTokens.cardTint),
        border = BorderStroke(DoneAtSpacing.xxs / 2, MaterialTheme.colorScheme.primary.copy(alpha = DoneAtOfferTokens.cardStroke)),
    ) {
        Column(Modifier.padding(DoneAtOfferTokens.cardPadding), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                OfferGiftIcon(size = DoneAtOfferTokens.toolbarGiftSize)
                Text(stringResource(R.string.plusOfferTitle), Modifier.semantics { heading() },
                    style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            }
            if (savings != null) Text(savings, style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            Text(stringResource(if (invitation.source == LifetimeOfferSource.UPDATE_321) R.string.plusOfferWelcomeBack else R.string.plusOfferWelcome),
                style = MaterialTheme.typography.bodyMedium)
            FlowRow(Modifier.onGloballyPositioned { coordinates ->
                val bounds = coordinates.boundsInWindow()
                val rootHeight = coordinates.findRootCoordinates().size.height
                if (bounds.height > 0 && bounds.bottom > 0 && bounds.top < rootHeight) onPriceVisible()
            }, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                Text(price.price, style = MaterialTheme.typography.headlineMedium.copy(fontFeatureSettings = "tnum"), fontWeight = FontWeight.Bold)
                Text(price.regularPrice!!, Modifier.align(Alignment.CenterVertically),
                    style = MaterialTheme.typography.bodyLarge.copy(textDecoration = TextDecoration.LineThrough, fontFeatureSettings = "tnum"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(stringResource(R.string.plusOfferTerms), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (deadline != null) {
                val accessibilityDeadline = Strings.plusOfferDeadline(resources, deadline)
                FlowRow(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = accessibilityDeadline },
                    horizontalArrangement = Arrangement.SpaceBetween, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    Text(stringResource(R.string.plusOfferRemaining), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    Text(offerDuration(invitation.remainingMs(nowMs), locale),
                        style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"), fontWeight = FontWeight.SemiBold)
                }
            }
            DoneAtPrimaryButton(
                stringResource(if (invitation.claimedAtMs == null) R.string.plusOfferClaim else R.string.plusBuyLifetime),
                onClick = { if (invitation.claimedAtMs == null) onClaim() else onPurchase() },
                modifier = Modifier.fillMaxWidth(), enabled = enabled,
            )
        }
    }
}

/** Persistent timer entry exists only after the priced reveal has started its countdown. */
@Composable
fun LifetimeOfferToolbarButton(plus: PlusAccess, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val offer by plus.lifetimeOffer.collectAsStateWithLifecycle()
    val store by plus.state.collectAsStateWithLifecycle()
    val authorized by plus.authorized.collectAsStateWithLifecycle()
    val invitation = offer ?: return
    if (invitation.claimedAtMs == null || authorized || !plus.canOfferLifetime) return
    val now = observeOfferClock(plus)
    if (!invitation.isActive(now)) return
    val locale = LocalConfiguration.current.locales[0]
    val res = LocalResources.current
    val title = stringResource(R.string.plusOfferTitle)
    val deadline = Strings.plusOfferDeadline(res, offerDeadline(invitation.expiresAtMs!!, locale))
    val savings = store.discountedLifetimeOffer?.let { savingsLabel(it, locale) }?.let { Strings.plusOfferSavings(res, it) } ?: title
    TextButton(onClick = onOpen, modifier = modifier.semantics { contentDescription = "$title. $deadline" }) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            OfferGiftIcon(size = DoneAtOfferTokens.toolbarGiftSize)
            Column {
                Text(savings, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
                Text(offerDuration(invitation.remainingMs(now), locale), style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"))
            }
        }
    }
}

/** Observe in the foreground; keep clock rollback from adding time and persist at lifecycle edges. */
@Composable
private fun observeOfferClock(plus: PlusAccess): Long {
    val owner = LocalLifecycleOwner.current
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(owner, plus) {
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                now = System.currentTimeMillis()
                plus.observeLifetimeOffer(now, persist = false)
                delay(1_000)
            }
        }
    }
    DisposableEffect(owner, plus) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE || event == Lifecycle.Event.ON_STOP) plus.observeLifetimeOffer()
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer); plus.observeLifetimeOffer() }
    }
    return now
}

/** Vector ribbon, removable lid and box. Reduced motion/assistive reading uses a still gift. */
@Composable
fun OfferGiftIcon(modifier: Modifier = Modifier, size: Dp = DoneAtOfferTokens.invitationGiftSize) {
    val reduced = LocalDoneAtMotion.current.reduced || offerTouchExplorationEnabled()
    val phase by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val float = remember { Animatable(0f) }
    val lid = remember { Animatable(0f) }
    LaunchedEffect(reduced, phase) {
        float.snapTo(0f)
        lid.snapTo(0f)
        if (reduced || !phase.isAtLeast(Lifecycle.State.RESUMED)) return@LaunchedEffect
        while (true) {
            float.animateTo(DoneAtOfferTokens.FLOAT_FRACTION, DoneAtOfferTokens.float())
            delay(DoneAtOfferTokens.PEEK_PAUSE_MS)
            lid.animateTo(DoneAtOfferTokens.LID_FRACTION, DoneAtOfferTokens.peek())
            coroutineScope {
                launch { lid.animateTo(0f, DoneAtOfferTokens.peek()) }
                launch { float.animateTo(0f, DoneAtOfferTokens.float()) }
            }
        }
    }
    Canvas(modifier.size(size * 1.3f).clearAndSetSemantics { }) {
        val unit = this.size.width / 100f
        val orange = Brush.linearGradient(listOf(DoneAtOfferTokens.orange, DoneAtOfferTokens.orangeDeep))
        val satin = Brush.horizontalGradient(listOf(DoneAtOfferTokens.satin, DoneAtOfferTokens.satinBright, DoneAtOfferTokens.satin))
        translate(top = -this.size.height * float.value) {
            drawRoundRect(orange, Offset(17 * unit, 42 * unit), Size(66 * unit, 49 * unit), CornerRadius(7 * unit))
            drawRoundRect(DoneAtOfferTokens.seam, Offset(76 * unit, 48 * unit), Size(3 * unit, 36 * unit), CornerRadius(1.5f * unit))
            drawRect(satin, Offset(44 * unit, 42 * unit), Size(12 * unit, 49 * unit))
            drawRoundRect(DoneAtOfferTokens.seam, Offset(17 * unit, 47 * unit), Size(66 * unit, 4 * unit), CornerRadius(2 * unit))
            translate(top = -this.size.height * lid.value) {
                val bow = Path().apply {
                    moveTo(49 * unit, 32 * unit)
                    cubicTo(25 * unit, 33 * unit, 20 * unit, 28 * unit, 27 * unit, 19 * unit)
                    cubicTo(34 * unit, 8 * unit, 45 * unit, 17 * unit, 49 * unit, 32 * unit)
                    moveTo(51 * unit, 32 * unit)
                    cubicTo(75 * unit, 33 * unit, 80 * unit, 28 * unit, 73 * unit, 19 * unit)
                    cubicTo(66 * unit, 8 * unit, 55 * unit, 17 * unit, 51 * unit, 32 * unit)
                }
                drawPath(bow, satin, style = Stroke(6 * unit, cap = StrokeCap.Round, join = StrokeJoin.Round))
                drawRoundRect(orange, Offset(12 * unit, 34 * unit), Size(76 * unit, 16 * unit), CornerRadius(4 * unit))
                drawRect(satin, Offset(44 * unit, 34 * unit), Size(12 * unit, 16 * unit))
                drawRoundRect(satin, Offset(43 * unit, 27 * unit), Size(14 * unit, 10 * unit), CornerRadius(3 * unit))
            }
        }
    }
}

@Composable
internal fun offerTouchExplorationEnabled(): Boolean {
    val manager = LocalContext.current.getSystemService(android.view.accessibility.AccessibilityManager::class.java)
    var enabled by remember(manager) { mutableStateOf(manager?.isTouchExplorationEnabled == true) }
    DisposableEffect(manager) {
        val listener = android.view.accessibility.AccessibilityManager.TouchExplorationStateChangeListener { enabled = it }
        manager?.addTouchExplorationStateChangeListener(listener)
        onDispose { manager?.removeTouchExplorationStateChangeListener(listener) }
    }
    return enabled
}

internal fun savingsLabel(price: PlusOffer, locale: Locale): String? {
    val regular = price.regularPriceMicros ?: return null
    if (!LifetimeOfferPolicy.validPrice(regular, price.priceMicros, true)) return null
    val saving = (1.0 - price.priceMicros.toDouble() / regular) * 100
    val percent = if (saving in 23.0..27.0) 25.0 else floor(saving)
    val amount = if (locale.language == "zh") (100 - percent) / 10 else percent
    return NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 1 }.format(amount)
}

private fun offerDuration(ms: Long, locale: Locale): String {
    val seconds = (ms / 1_000).coerceAtLeast(0)
    val format = NumberFormat.getIntegerInstance(locale).apply { minimumIntegerDigits = 2; isGroupingUsed = false }
    return "${format.format(seconds / 3600)}:${format.format(seconds % 3600 / 60)}:${format.format(seconds % 60)}"
}

private fun offerDeadline(atMs: Long, locale: Locale): String =
    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, locale).format(Date(atMs))

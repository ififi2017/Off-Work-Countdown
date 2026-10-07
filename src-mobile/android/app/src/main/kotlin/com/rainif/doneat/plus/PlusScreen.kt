package com.rainif.doneat.plus

import com.rainif.doneat.core.designsystem.LocalDoneAtBottomBarPadding
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.saveable.rememberSaveable
import kotlinx.coroutines.CancellationException
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Autorenew
import androidx.compose.material.icons.outlined.AllInclusive
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Luggage
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.expand
import androidx.compose.ui.semantics.collapse
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.CelebratingBrandMark
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.PlusPendingAction
import com.rainif.doneat.ui.settings.openUrl
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import kotlinx.coroutines.launch

@Composable
fun PlusScreen(graph: AppGraph, onBack: () -> Unit,
    pendingAction: PlusPendingAction? = null, onAuthorized: (PlusPendingAction) -> Unit = {}) {
    PlusScreen(graph, onBack, pendingAction, dismissLabel = null, onAuthorized = onAuthorized)
}

@Composable
private fun PlusScreen(graph: AppGraph, onBack: () -> Unit,
    pendingAction: PlusPendingAction? = null, dismissLabel: Int?,
    onAuthorized: (PlusPendingAction) -> Unit = {}) {
    val authorized by graph.plus.authorized.collectAsStateWithLifecycle()
    val store by graph.plus.state.collectAsStateWithLifecycle()
    val lifetimeOffer by graph.plus.lifetimeOffer.collectAsStateWithLifecycle()
    val activity = LocalContext.current.activity()
    val authorizedAtPresentation = rememberSaveable { authorized }
    LaunchedEffect(Unit) { graph.plus.refresh() }
    LaunchedEffect(authorized, pendingAction) {
        // An existing member can proceed immediately. A new grant first shows
        // the thank-you page; Continue resumes the action they were buying for.
        if (authorizedAtPresentation && authorized && pendingAction != null) onAuthorized(pendingAction)
    }
    PlusPage(store, authorized, activity != null, onBack,
        onPurchase = { offer -> activity?.let { graph.plus.purchase(it, offer) } },
        onRestore = graph.plus::restore, onRefresh = graph.plus::refresh,
        onOpenUrl = { url -> activity?.let { openUrl(it, url) } },
        playsCelebrationOnAppear = !authorizedAtPresentation,
        onContinue = pendingAction?.let { action -> { onAuthorized(action) } },
        initialFeature = when (pendingAction) {
            is PlusPendingAction.FocusCreate, PlusPendingAction.FocusHome -> PlusDemoKind.FOCUS
            is PlusPendingAction.LeavePlan, PlusPendingAction.ShiftAlarms -> PlusDemoKind.REST
            else -> PlusDemoKind.REPORTS
        },
        offerCard = { LifetimeOfferCard(graph.plus) },
        showsLifetimeOffer = lifetimeOffer != null && graph.plus.hasAvailableLifetimeOffer,
        backLabel = dismissLabel ?: when (pendingAction) {
            is PlusPendingAction.FocusCreate, PlusPendingAction.FocusHome -> R.string.focusTitle
            is PlusPendingAction.RecordsDay, PlusPendingAction.RecordsLifeEdit, PlusPendingAction.RecordsCharts -> R.string.recordsTab
            PlusPendingAction.CycleSummary, null -> R.string.settings
            PlusPendingAction.ShiftAlarms -> R.string.shiftAlarmsTitle
            is PlusPendingAction.LeavePlan -> R.string.leaveResultsTitle
        })
}

/** Only the first introduction offers a new lifetime invitation after closing its regular paywall. */
@Composable
fun PlusIntroScreen(graph: AppGraph) {
    val scope = rememberCoroutineScope()
    var checkingOffer by remember { mutableStateOf(false) }
    var showsOffer by rememberSaveable { mutableStateOf(false) }
    fun finish() {
        if (checkingOffer || showsOffer) return
        checkingOffer = true
        scope.launch {
            try {
                if (graph.plus.refreshAndRevealLifetimeOffer(LifetimeOfferSource.ONBOARDING)) showsOffer = true
                else graph.plus.markIntroSeen()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                graph.plus.markIntroSeen()
            } finally { checkingOffer = false }
        }
    }
    BackHandler(!showsOffer) { finish() }
    Box(Modifier.fillMaxSize()) {
        PlusScreen(graph, onBack = ::finish, dismissLabel = R.string.close)
        if (checkingOffer) CircularProgressIndicator(Modifier.align(Alignment.Center).size(DoneAtSpacing.xl))
    }
    if (showsOffer) LifetimeOfferSheet(graph.plus, onDismiss = { scope.launch { graph.plus.markIntroSeen() } })
}

/** Shared with the Debug gallery so visual checks exercise the complete purchase page. */
@Composable
internal fun PlusPage(
    store: PlusStoreState, authorized: Boolean, canPurchase: Boolean,
    onBack: () -> Unit, onPurchase: (PlusOffer) -> Unit,
    onRestore: () -> Unit, onRefresh: () -> Unit, onOpenUrl: (String) -> Unit,
    playsCelebrationOnAppear: Boolean = false, onContinue: (() -> Unit)? = null,
    backLabel: Int = R.string.settings,
    showsLifetimeOffer: Boolean = false,
    offerCard: (@Composable () -> Unit)? = null,
    initialFeature: PlusDemoKind = PlusDemoKind.REPORTS,
) {
    var selectedPlan by rememberSaveable { mutableStateOf(PlusPlan.YEARLY) }
    val scroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    val reduced = LocalDoneAtMotion.current.reduced
    var viewport by remember { mutableStateOf(Rect.Zero) }
    var pricingBounds by remember { mutableStateOf(Rect.Zero) }
    val pricingVisible = viewport.height > 0f && pricingBounds.height > 0f &&
        (minOf(viewport.bottom, pricingBounds.bottom) - maxOf(viewport.top, pricingBounds.top)) / pricingBounds.height >= .15f
    LaunchedEffect(authorized) { scroll.scrollTo(0) }
    val offers = listOf(PlusPlan.YEARLY, PlusPlan.MONTHLY, PlusPlan.LIFETIME)
        .mapNotNull { plan -> store.offers.firstOrNull { it.plan == plan } }
    val selected = offers.firstOrNull { it.plan == selectedPlan } ?: offers.firstOrNull()
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.safeDrawingPadding().padding(bottom = LocalDoneAtBottomBarPadding.current)) {
            Box(Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
                IconButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart)) {
                    Icon(if (backLabel == R.string.close) Icons.Outlined.Close else Icons.AutoMirrored.Outlined.ArrowBack,
                        stringResource(backLabel))
                }
                Text(stringResource(R.string.plusSettings), Modifier.align(Alignment.Center).padding(horizontal = 48.dp),
                    style = MaterialTheme.typography.titleMedium)
            }
            Column(
                Modifier.fillMaxSize().weight(1f).onGloballyPositioned { viewport = it.boundsInWindow() }.verticalScroll(scroll),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = if (authorized) Arrangement.Center else Arrangement.Top,
            ) {
                Column(
                    Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(DoneAtSpacing.page),
                    verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l),
                ) {
                    if (authorized) {
                        PlusSubscriberThankYou(store, playsCelebrationOnAppear, onContinue,
                            onManage = { onOpenUrl("https://play.google.com/store/account/subscriptions") })
                    } else Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                        Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = .12f)) {
                            Row(Modifier.padding(horizontal = DoneAtSpacing.m, vertical = DoneAtSpacing.xs),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                                Icon(Icons.Outlined.Star, null, Modifier.size(DoneAtSpacing.l), tint = MaterialTheme.colorScheme.primary)
                                Text(stringResource(R.string.plusSection), style = MaterialTheme.typography.labelLarge,
                                    color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                            }
                        }
                        Text(stringResource(R.string.onboardingPlusShowcaseTitle),
                            Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold)
                        Text(stringResource(R.string.plusStoryBody),
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (!authorized) PlusFeatureStage(initialSelection = initialFeature)
                    if (!authorized) Column(Modifier.fillMaxWidth().onGloballyPositioned { pricingBounds = Rect(it.positionInWindow(), Size(it.size.width.toFloat(), it.size.height.toFloat())) },
                        verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                        if (showsLifetimeOffer) offerCard?.invoke()
                        val regularPlans: @Composable () -> Unit = {
                            if (store.status == PlusStatus.FREE && selected != null) {
                                PlusPurchasePlans(offers, selected, store.busy, canPurchase,
                                    onSelection = { selectedPlan = it }, onPurchase = onPurchase)
                            }
                        }
                        if (showsLifetimeOffer) PlusDisclosure(R.string.plusSeePlans, regularPlans)
                        else regularPlans()
                        if (!authorized && (store.status == PlusStatus.LOADING || store.busy)) {
                            Box(Modifier.fillMaxWidth()) {
                                CircularProgressIndicator(Modifier.align(Alignment.Center).size(DoneAtSpacing.xl))
                            }
                        }
                        val message = when {
                            store.operationFailed -> R.string.plusAndroidRequestFailed
                            store.status == PlusStatus.UNCONFIGURED -> R.string.plusAndroidStoreUnconfigured
                            store.status in listOf(PlusStatus.OFFLINE, PlusStatus.ERROR) -> R.string.plusAndroidStoreOffline
                            store.status == PlusStatus.PENDING -> R.string.plusStatusPending
                            !authorized && store.status == PlusStatus.FREE && offers.isEmpty() -> R.string.plusAndroidPlansUnavailable
                            else -> null
                        }
                        if (message != null) Text(stringResource(message), style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (store.status in listOf(PlusStatus.OFFLINE, PlusStatus.ERROR) ||
                            (store.status == PlusStatus.FREE && offers.isEmpty())) {
                            TextButton(onClick = onRefresh, enabled = !store.busy, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                                Text(stringResource(R.string.retryAction))
                            }
                        }
                    }
                    if (!authorized) PlusDisclosure(R.string.plusAllBenefits) { PlusBenefits() }
                    if (!authorized && store.status != PlusStatus.UNCONFIGURED) {
                        TextButton(onClick = onRestore, enabled = !store.busy, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                            Text(stringResource(R.string.plusRestore), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    if (!authorized && store.hasPurchasedBefore) {
                        TextButton(onClick = { onOpenUrl("https://play.google.com/store/account/subscriptions") },
                            modifier = Modifier.align(Alignment.CenterHorizontally)) {
                            Text(stringResource(R.string.plusManage))
                        }
                    }
                    if ((!authorized && offers.any { it.plan != PlusPlan.LIFETIME }) || store.status == PlusStatus.SUBSCRIBED) {
                        Text(stringResource(if (authorized) R.string.plusAutoRenew else R.string.plusAndroidRenewalNotice), style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                        TextButton(onClick = { onOpenUrl("https://doneat.app/privacy") }) { Text(stringResource(R.string.plusPrivacy)) }
                        TextButton(onClick = { onOpenUrl("https://play.google.com/about/play-terms/") }) { Text(stringResource(R.string.plusTerms)) }
                    }
                }
            }
            if (!authorized && !pricingVisible) {
                DoneAtPrimaryButton(stringResource(R.string.plusSeePlans), onClick = {
                    scope.launch {
                        val target = (scroll.value + pricingBounds.top - viewport.top).toInt().coerceAtLeast(0)
                        if (reduced) scroll.scrollTo(target) else scroll.animateScrollTo(target)
                    }
                }, modifier = Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.s))
            }
        }
    }
}

@Composable
private fun PlusPurchasePlans(offers: List<PlusOffer>, selected: PlusOffer, busy: Boolean, canPurchase: Boolean,
    onSelection: (PlusPlan) -> Unit, onPurchase: (PlusOffer) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
        BoxWithConstraints(Modifier.fillMaxWidth().selectableGroup()) {
            val rows = maxWidth < 352.dp || LocalDensity.current.fontScale >= 1.3f
            if (rows) Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                offers.forEach { offer -> PlusPlanCard(offer, selected.plan == offer.plan, !busy, Modifier.fillMaxWidth()) { onSelection(offer.plan) } }
            } else Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                offers.forEach { offer -> PlusPlanCard(offer, selected.plan == offer.plan, !busy, Modifier.weight(1f).fillMaxHeight()) { onSelection(offer.plan) } }
            }
        }
        if (selected.sevenDayTrial) Text(Strings.plusAndroidYearlyTrialPrice(LocalResources.current, price = selected.price),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        DoneAtPrimaryButton(stringResource(when {
            selected.sevenDayTrial -> R.string.plusStartTrialShort
            selected.plan == PlusPlan.LIFETIME -> R.string.plusBuyLifetime
            else -> R.string.plusSubscribe
        }), onClick = { onPurchase(selected) }, modifier = Modifier.fillMaxWidth(), enabled = canPurchase && !busy)
    }
}

@Composable
private fun PlusDisclosure(title: Int, content: @Composable () -> Unit) {
    var expanded by rememberSaveable(title) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        TextButton(onClick = { expanded = !expanded }, modifier = Modifier.fillMaxWidth().semantics {
            if (expanded) collapse { expanded = false; true } else expand { expanded = true; true }
        }) {
            Text(stringResource(title), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            Icon(if (expanded) Icons.Outlined.KeyboardArrowUp else Icons.Outlined.KeyboardArrowDown, null)
        }
        val duration = if (LocalDoneAtMotion.current.reduced) com.rainif.doneat.core.designsystem.DoneAtMotion.REDUCED_MS
            else com.rainif.doneat.core.designsystem.DoneAtMotion.SELECTION_MS
        AnimatedVisibility(expanded, enter = fadeIn(androidx.compose.animation.core.tween(duration)),
            exit = fadeOut(androidx.compose.animation.core.tween(duration))) { content() }
    }
}

@Composable
private fun PlusSubscriberThankYou(store: PlusStoreState, playsOnAppear: Boolean, onContinue: (() -> Unit)?, onManage: () -> Unit) {
    val lifetime = store.status == PlusStatus.LIFETIME
    val stacked = LocalDensity.current.fontScale >= 1.3f
    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.section)) {
        CelebratingBrandMark(
            label = stringResource(R.string.plusReplayCelebration),
            modifier = Modifier.size(260.dp).align(Alignment.CenterHorizontally),
            showsDepth = true, replaysOnTap = true, playsOnAppear = playsOnAppear,
        )
        Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            Text(stringResource(R.string.plusThanksTitle), Modifier.semantics { heading() },
                style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.plusThanksBody), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(DoneAtSpacing.l)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                    Icon(if (lifetime) Icons.Outlined.AllInclusive else Icons.Outlined.Autorenew, null,
                        Modifier.size(DoneAtSpacing.xl), tint = MaterialTheme.colorScheme.primary)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                        Text(stringResource(if (lifetime) R.string.plusOwnedTitle else R.string.plusThanksCurrentPlan),
                            style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                        Text(stringResource(when {
                            lifetime && store.hasActiveSubscription -> R.string.plusLifetimeWhileSubscribed
                            lifetime -> R.string.plusOwnedBody
                            else -> R.string.plusStatusSubscribed
                        }), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (!stacked && store.hasActiveSubscription) TextButton(onClick = onManage) {
                        Text(stringResource(R.string.plusThanksManagePlan))
                    }
                }
                if (stacked && store.hasActiveSubscription) TextButton(onClick = onManage,
                    modifier = Modifier.align(Alignment.End)) { Text(stringResource(R.string.plusThanksManagePlan)) }
            }
        }
        if (onContinue != null) DoneAtPrimaryButton(stringResource(R.string.plusThanksContinue),
            onClick = onContinue, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun PlusBenefits() {
    val benefits = listOf(
        Icons.Outlined.BarChart to R.string.plusBenefitCharts,
        Icons.Outlined.GridView to R.string.plusBenefitLife,
        Icons.Outlined.Edit to R.string.plusBenefitEdit,
        Icons.Outlined.Timer to R.string.plusBenefitFocus,
        Icons.Outlined.Luggage to R.string.plusBenefitLeave,
    )
    Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column {
            benefits.forEachIndexed { index, (icon, label) ->
                Row(Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.s),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                    Box(Modifier.size(DoneAtSpacing.xxl).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.10f), MaterialTheme.shapes.small),
                        contentAlignment = Alignment.Center) {
                        Icon(icon, null, Modifier.size(DoneAtSpacing.xl), tint = MaterialTheme.colorScheme.primary)
                    }
                    Text(stringResource(label), style = MaterialTheme.typography.bodyMedium)
                }
                if (index != benefits.lastIndex) HorizontalDivider(
                    Modifier.padding(start = DoneAtSpacing.l + DoneAtSpacing.xxl + DoneAtSpacing.m),
                    color = MaterialTheme.colorScheme.outlineVariant)
            }
        }
    }
}

@Composable
private fun PlusPlanCard(offer: PlusOffer, selected: Boolean, enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val label = when (offer.plan) {
        PlusPlan.MONTHLY -> R.string.plusMonthly
        PlusPlan.YEARLY -> R.string.plusYearly
        PlusPlan.LIFETIME -> R.string.plusLifetime
    }
    Surface(
        modifier.selectable(selected, enabled = enabled, role = Role.RadioButton, onClick = onClick)
            .semantics(mergeDescendants = true) {},
        shape = MaterialTheme.shapes.medium,
        color = if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.10f) else MaterialTheme.colorScheme.surfaceContainerLow,
        border = BorderStroke(if (selected) 2.dp else 1.dp,
            if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant),
    ) {
        Column(Modifier.padding(DoneAtSpacing.m), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                Text(stringResource(label), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Icon(if (selected) Icons.Outlined.CheckCircle else Icons.Outlined.RadioButtonUnchecked, null,
                    Modifier.size(DoneAtSpacing.l), tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(offer.price, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            if (offer.sevenDayTrial) Text(stringResource(R.string.plusTrialBadge), style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary)
        }
    }
}

internal fun Context.activity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return current as? Activity
}

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
import androidx.compose.foundation.layout.width
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
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.Alarm
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
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.layout.findRootCoordinates
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
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.currentStateAsState
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.DoneAtWelcome322Tokens
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
    val reviewAccess by graph.plus.reviewAccess.state.collectAsStateWithLifecycle()
    val lifetimeOffer by graph.plus.lifetimeOffer.collectAsStateWithLifecycle()
    val offerNow = if (lifetimeOffer != null) observeOfferClock(graph.plus) else 0L
    val lifetimePrice = store.discountedLifetimeOffer?.takeIf { graph.plus.hasAvailableLifetimeOffer }
    var offerPriceVisible by remember(lifetimePrice?.offerToken) { mutableStateOf(false) }
    val lifecycleState by androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    LaunchedEffect(lifetimePrice, lifetimeOffer?.claimedAtMs, offerPriceVisible, lifecycleState) {
        if (lifetimePrice != null && offerPriceVisible && lifecycleState == androidx.lifecycle.Lifecycle.State.RESUMED &&
            lifetimeOffer?.claimedAtMs == null) graph.plus.claimLifetimeOffer()
    }
    val activity = LocalContext.current.activity()
    val authorizedAtPresentation = rememberSaveable { authorized }
    LaunchedEffect(Unit) { graph.plus.refresh() }
    LaunchedEffect(authorized, reviewAccess.active, pendingAction) {
        // An existing member can proceed immediately. A new grant first shows
        // the thank-you page; Continue resumes the action they were buying for.
        if ((authorizedAtPresentation || reviewAccess.active) && authorized && pendingAction != null) onAuthorized(pendingAction)
    }
    PlusPage(store, store.authorized || (authorized && !reviewAccess.active), activity != null, onBack,
        onPurchase = { offer -> activity?.let { graph.plus.purchase(it, offer) } },
        onRestore = graph.plus::restore, onRefresh = graph.plus::refresh,
        onOpenUrl = { url -> activity?.let { openUrl(it, url) } },
        playsCelebrationOnAppear = !authorizedAtPresentation,
        onContinue = pendingAction?.let { action -> { onAuthorized(action) } },
        title = plusPaywallTitle(pendingAction),
        initialFeature = when (pendingAction) {
            is PlusPendingAction.FocusCreate, PlusPendingAction.FocusHome -> PlusDemoKind.FOCUS
            is PlusPendingAction.LeavePlan, PlusPendingAction.ShiftAlarms -> PlusDemoKind.REST
            else -> PlusDemoKind.REPORTS
        },
        showsLifetimeOffer = lifetimeOffer != null && graph.plus.hasAvailableLifetimeOffer,
        lifetimePrice = lifetimePrice, lifetimeInvitation = lifetimeOffer, offerNowMs = offerNow,
        onOfferPriceVisible = { offerPriceVisible = true },
        onLifetimePurchase = { price -> activity?.let { graph.plus.purchaseLifetimeOffer(it, price) } },
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
    if (showsOffer) {
        DisposableEffect(graph) {
            graph.reviewLifetimeGift.value = true
            onDispose { graph.reviewLifetimeGift.value = false }
        }
        LifetimeOfferSheet(graph.plus, onDismiss = { scope.launch { graph.plus.markIntroSeen() } })
    }
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
    title: Int = R.string.onboardingPlusShowcaseTitle,
    lifetimePrice: PlusOffer? = null,
    lifetimeInvitation: LifetimeOffer? = null,
    offerNowMs: Long = 0L,
    onOfferPriceVisible: () -> Unit = {},
    onLifetimePurchase: (PlusOffer) -> Unit = onPurchase,
) {
    var selectedPlan by rememberSaveable { mutableStateOf(if (lifetimePrice != null) PlusPlan.LIFETIME else PlusPlan.YEARLY) }
    val scroll = rememberScrollState()
    LaunchedEffect(authorized) { scroll.scrollTo(0) }
    LaunchedEffect(authorized) { if (authorized) GiftOfferMotion.fromToolbar = false }
    val offers = listOf(PlusPlan.YEARLY, PlusPlan.LIFETIME, PlusPlan.MONTHLY)
        .mapNotNull { plan -> if (plan == PlusPlan.LIFETIME) lifetimePrice ?: store.offers.firstOrNull { it.plan == plan }
            else store.offers.firstOrNull { it.plan == plan } }
    val selected = selectVisiblePlusOffer(offers, selectedPlan)
    LaunchedEffect(lifetimePrice?.offerToken) { if (lifetimePrice != null) selectedPlan = PlusPlan.LIFETIME }
    LaunchedEffect(selected?.plan) { selected?.let { selectedPlan = it.plan } }
    fun closePage() {
        if (!authorized && lifetimePrice != null) GiftOfferMotion.returnToToolbar()
        onBack()
    }
    BackHandler { closePage() }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.safeDrawingPadding().padding(bottom = LocalDoneAtBottomBarPadding.current)) {
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.page),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = .10f)) {
                    Text(stringResource(R.string.plusSettings), Modifier.padding(horizontal = DoneAtSpacing.m, vertical = DoneAtSpacing.xs),
                        style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                }
                IconButton(onClick = ::closePage) {
                    Icon(if (backLabel == R.string.close) Icons.Outlined.Close else Icons.AutoMirrored.Outlined.ArrowBack,
                        stringResource(backLabel))
                }
            }
            Column(
                Modifier.fillMaxWidth().weight(1f).verticalScroll(scroll),
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
                    } else if (lifetimePrice != null && lifetimeInvitation != null) {
                        LifetimeOfferHeader(lifetimeInvitation)
                    } else if (title != R.string.onboardingPlusShowcaseTitle) Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                        Text(stringResource(title),
                            Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold)
                    }
                    if (!authorized) PlusFeatureStage(initialSelection = initialFeature)
                    if (!authorized) Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                        if (store.status == PlusStatus.FREE && selected != null) {
                            Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                                offers.forEach { offer ->
                                    val special = lifetimePrice != null && offer == lifetimePrice
                                    PlusPlanCard(offer, selected.plan == offer.plan, !store.busy, Modifier.fillMaxWidth(),
                                        invitation = lifetimeInvitation.takeIf { special }, nowMs = offerNowMs,
                                        onPriceVisible = if (special) onOfferPriceVisible else ({})) { selectedPlan = offer.plan }
                                }
                            }
                        }
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
                    if (!authorized && store.hasPurchasedBefore) {
                        TextButton(onClick = { onOpenUrl("https://play.google.com/store/account/subscriptions") },
                            modifier = Modifier.align(Alignment.CenterHorizontally)) {
                            Text(stringResource(R.string.plusManage))
                        }
                    }
                    if (store.status == PlusStatus.SUBSCRIBED) {
                        Text(stringResource(R.string.plusAutoRenew), style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (!authorized) {
                Surface(color = MaterialTheme.colorScheme.surface, tonalElevation = 1.dp) {
                    Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.s),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                        if (selected != null && store.status == PlusStatus.FREE) {
                            val cta = stringResource(when {
                                showsPlusTrialTimeline(selected) -> R.string.plusStartTrialShort
                                selected.plan == PlusPlan.LIFETIME -> R.string.plusBuyLifetime
                                else -> R.string.plusSubscribe
                            }) + if (showsPlusTrialTimeline(selected)) "" else " · ${selected.price}"
                            DoneAtPrimaryButton(cta, onClick = {
                                if (lifetimePrice != null && selected == lifetimePrice) onLifetimePurchase(selected) else onPurchase(selected)
                            }, modifier = Modifier.fillMaxWidth().onGloballyPositioned {
                                if (selected == lifetimePrice) onOfferPriceVisible()
                            }, enabled = canPurchase && !store.busy)
                            Text(if (selected == lifetimePrice && lifetimeInvitation != null)
                                stringResource(if (lifetimeInvitation.source == LifetimeOfferSource.UPDATE_323) R.string.plusOfferTermsWeek else R.string.plusOfferTerms)
                            else if (showsPlusTrialTimeline(selected)) Strings.plusTrialThen(LocalResources.current, selected.price)
                            else stringResource(if (selected.plan == PlusPlan.LIFETIME) R.string.plusLifetimeOnce else R.string.plusAndroidRenewalNotice),
                                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                        }
                        FlowRow(horizontalArrangement = Arrangement.Center) {
                            if (store.status != PlusStatus.UNCONFIGURED) TextButton(onClick = onRestore, enabled = !store.busy) {
                                Text(stringResource(R.string.plusRestore), style = MaterialTheme.typography.labelSmall)
                            }
                            TextButton(onClick = { onOpenUrl("https://play.google.com/about/play-terms/") }) { Text(stringResource(R.string.plusTerms), style = MaterialTheme.typography.labelSmall) }
                            TextButton(onClick = { onOpenUrl("https://doneat.app/privacy") }) { Text(stringResource(R.string.plusPrivacy), style = MaterialTheme.typography.labelSmall) }
                        }
                    }
                }
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
        if (showsPlusTrialTimeline(selected)) PlusTrialTimeline(selected.price)
        DoneAtPrimaryButton(stringResource(when {
            showsPlusTrialTimeline(selected) -> R.string.plusStartTrialShort
            selected.plan == PlusPlan.LIFETIME -> R.string.plusBuyLifetime
            else -> R.string.plusSubscribe
        }), onClick = { onPurchase(selected) }, modifier = Modifier.fillMaxWidth(), enabled = canPurchase && !busy)
        if (showsPlusTrialTimeline(selected)) Text(Strings.plusTrialThen(LocalResources.current, price = selected.price),
            Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodySmall,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** UI projection only: trial eligibility and prices come from the selected Play offer. */
internal fun showsPlusTrialTimeline(offer: PlusOffer): Boolean =
    offer.plan == PlusPlan.YEARLY && offer.sevenDayTrial

internal fun selectVisiblePlusOffer(offers: List<PlusOffer>, selectedPlan: PlusPlan): PlusOffer? =
    offers.firstOrNull { it.plan == selectedPlan } ?: offers.firstOrNull { it.plan == PlusPlan.YEARLY } ?: offers.firstOrNull()

internal fun plusPaywallTitle(action: PlusPendingAction?): Int = when (action) {
    is PlusPendingAction.FocusCreate, PlusPendingAction.FocusHome -> R.string.plusFocusLocked
    is PlusPendingAction.RecordsDay -> R.string.plusEditLocked
    PlusPendingAction.RecordsLifeEdit -> R.string.plusLifeLocked
    PlusPendingAction.RecordsCharts -> R.string.plusChartsLocked
    PlusPendingAction.CycleSummary -> R.string.plusReportsLocked
    PlusPendingAction.ShiftAlarms -> R.string.plusShiftAlarmsLocked
    is PlusPendingAction.LeavePlan -> R.string.plusLeaveLocked
    null -> R.string.onboardingPlusShowcaseTitle
}

@Composable
private fun PlusTrialTimeline(price: String) {
    val tokens = DoneAtWelcome322Tokens
    val steps = listOf(
        Triple(Icons.Outlined.LockOpen, stringResource(R.string.plusTrialToday), stringResource(R.string.plusTrialTodayBody)),
        Triple(Icons.Outlined.CalendarMonth, stringResource(R.string.plusTrialEnd), Strings.plusTrialEndBody(LocalResources.current, price)),
        Triple(Icons.Outlined.Close, stringResource(R.string.plusTrialAnytime), stringResource(R.string.plusAndroidTrialCancelBody)),
    )
    Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.fillMaxWidth().padding(DoneAtSpacing.l)) {
            steps.forEachIndexed { index, (icon, title, body) ->
                Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).semantics(mergeDescendants = true) {},
                    horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                    Column(Modifier.fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                        Surface(Modifier.size(tokens.timelineIcon), shape = CircleShape,
                            color = if (index == 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.primaryContainer) {
                            Box(contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(DoneAtSpacing.l),
                                tint = if (index == 0) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.primary) }
                        }
                        if (index < steps.lastIndex) Box(Modifier.width(tokens.timelineLine).weight(1f)
                            .background(MaterialTheme.colorScheme.primary.copy(alpha = .22f)))
                    }
                    Column(Modifier.weight(1f).padding(top = DoneAtSpacing.xs,
                        bottom = if (index < steps.lastIndex) DoneAtSpacing.l else 0.dp), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs)) {
                        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Text(body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
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
        Icons.Outlined.Alarm to R.string.plusBenefitShiftAlarms,
        Icons.Outlined.BarChart to R.string.plusBenefitReports,
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
private fun PlusPlanCard(offer: PlusOffer, selected: Boolean, enabled: Boolean, modifier: Modifier,
                         invitation: LifetimeOffer? = null, nowMs: Long = 0L,
                         onPriceVisible: () -> Unit = {}, onClick: () -> Unit) {
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
        Row(Modifier.padding(horizontal = DoneAtSpacing.m, vertical = DoneAtSpacing.s).heightIn(min = 46.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
            Icon(if (selected) Icons.Outlined.CheckCircle else Icons.Outlined.RadioButtonUnchecked, null,
                Modifier.size(DoneAtSpacing.xl), tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs)) {
                Text(stringResource(if (invitation != null) R.string.plusOfferTitle else label),
                    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                if (invitation?.expiresAtMs != null) Text(Strings.plusOfferEndsIn(LocalResources.current,
                    offerDuration(invitation.remainingMs(nowMs), LocalResources.current.configuration.locales[0])),
                    style = MaterialTheme.typography.labelSmall.copy(fontFeatureSettings = "tnum"), color = MaterialTheme.colorScheme.primary)
                else Text(stringResource(when {
                    showsPlusTrialTimeline(offer) -> R.string.plusTrialBadge
                    offer.plan == PlusPlan.LIFETIME -> R.string.plusLifetimeOnce
                    offer.plan == PlusPlan.YEARLY -> R.string.androidPlusYearlyPlanDetail
                    else -> R.string.androidPlusMonthlyPlanDetail
                }), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs)) {
                Text(offer.price, Modifier.onGloballyPositioned { c ->
                    val bounds = c.boundsInWindow()
                    if (bounds.height > 0 && bounds.bottom > 0 && bounds.top < c.findRootCoordinates().size.height) onPriceVisible()
                }, style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"), fontWeight = FontWeight.Bold)
                if (invitation != null) offer.regularPrice?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall.copy(textDecoration = TextDecoration.LineThrough, fontFeatureSettings = "tnum"),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
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

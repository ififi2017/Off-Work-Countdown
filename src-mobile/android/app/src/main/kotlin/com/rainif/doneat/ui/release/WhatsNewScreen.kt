package com.rainif.doneat.ui.release

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Alarm
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Luggage
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtOfferTokens
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.plus.LifetimeOfferCard
import com.rainif.doneat.plus.LifetimeOfferSource
import com.rainif.doneat.plus.OfferGiftIcon
import com.rainif.doneat.plus.PlusDemoKind
import com.rainif.doneat.plus.PlusFeatureStage
import com.rainif.doneat.plus.PlusPage
import com.rainif.doneat.plus.PlusStatus
import com.rainif.doneat.plus.activity
import com.rainif.doneat.ui.settings.openUrl

/** The caller persists Continue successfully before removing this screen. */
@Composable
fun WhatsNewScreen(graph: AppGraph, onDismiss: () -> Unit, continuing: Boolean = false, errorText: String? = null) {
    val authorized by graph.plus.authorized.collectAsStateWithLifecycle()
    val store by graph.plus.state.collectAsStateWithLifecycle()
    val invitation by graph.plus.lifetimeOffer.collectAsStateWithLifecycle()
    var showsPlus by rememberSaveable { mutableStateOf(false) }
    var showsGift by rememberSaveable { mutableStateOf(false) }
    val activity = LocalContext.current.activity()
    // Neither system Back nor an overlay dismissal acknowledges the update.
    BackHandler { }
    LaunchedEffect(Unit) { graph.plus.refresh() }
    LaunchedEffect(authorized, store.status, store.currentEntitlementsVerified, store.hasActiveSubscription, store.discountedLifetimeOffer) {
        if (ReleaseNotesPolicy.mayInviteUpdateOffer(authorized, store.status == PlusStatus.FREE,
                store.currentEntitlementsVerified, store.hasActiveSubscription) && graph.plus.canInviteLifetime) {
            graph.plus.inviteLifetimeOffer(LifetimeOfferSource.UPDATE_321)
        }
        if (authorized) showsGift = false
    }
    val showsInvitation = invitation != null && graph.plus.hasAvailableLifetimeOffer
    val largeText = LocalDensity.current.fontScale >= 1.5f
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.safeDrawingPadding().verticalScroll(rememberScrollState()).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(DoneAtSpacing.xl), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xl)) {
                Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                    Text("DoneAt ${ReleaseNotesPolicy.CURRENT}", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    Text(stringResource(R.string.whatsNewTitle), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                }
                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primaryContainer) {
                    Row(Modifier.padding(horizontal = DoneAtSpacing.m, vertical = DoneAtSpacing.xs), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Star, null, Modifier.size(DoneAtSpacing.l), tint = MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.plusSection), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    }
                }
                PlusFeatureStage(initialSelection = PlusDemoKind.REST, showsFocus = false)
                Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m + DoneAtSpacing.s)) {
                    ReleaseFeature(Icons.Outlined.Luggage, R.string.leavePlanAction, R.string.whatsNewLeaveBody, largeText)
                    ReleaseFeature(Icons.Outlined.Alarm, R.string.shiftAlarmsTitle, R.string.whatsNewAlarmsBody, largeText)
                    ReleaseFeature(Icons.Outlined.BarChart, R.string.reportEntryTitle, R.string.whatsNewReportsBody, largeText)
                }
                if (showsInvitation) {
                    Surface(Modifier.fillMaxWidth().clickable(role = Role.Button) { showsGift = true }, shape = MaterialTheme.shapes.large,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = DoneAtOfferTokens.cardTint)) {
                        Column(Modifier.padding(DoneAtSpacing.xl), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), horizontalAlignment = Alignment.CenterHorizontally) {
                            OfferGiftIcon()
                            Text(stringResource(R.string.plusOfferTitle), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                            Text(stringResource(R.string.plusOfferWelcomeBack), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                        }
                    }
                }
                if (store.status == PlusStatus.PENDING) Text(stringResource(R.string.plusWaitingApproval), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (!authorized) TextButton(onClick = { showsPlus = true }, modifier = Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch)) {
                    Text(stringResource(R.string.onboardingExplorePlus), fontWeight = FontWeight.SemiBold)
                }
                if (errorText != null) Text(errorText, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
                DoneAtPrimaryButton(stringResource(R.string.whatsNewContinue), onDismiss, Modifier.fillMaxWidth(), enabled = !continuing)
            }
        }
    }
    if (showsPlus) {
        Dialog(onDismissRequest = { showsPlus = false }, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
            // The normal paywall composes an available offer card. This route
            // deliberately keeps the unopened gift unclaimed until gift-open.
            PlusPage(store, authorized, activity != null,
                onBack = { showsPlus = false },
                onPurchase = { offer -> activity?.let { graph.plus.purchase(it, offer) } },
                onRestore = graph.plus::restore, onRefresh = graph.plus::refresh,
                onOpenUrl = { url -> activity?.let { openUrl(it, url) } },
                backLabel = R.string.whatsNewTitle, initialFeature = PlusDemoKind.REST,
                playsCelebrationOnAppear = true,
            )
        }
    }
    if (showsGift) {
        Dialog(onDismissRequest = { showsGift = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding(), contentAlignment = Alignment.Center) {
                Surface(Modifier.widthIn(max = 560.dp).fillMaxWidth().heightIn(max = maxHeight), shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surface) {
                    Column(Modifier.verticalScroll(rememberScrollState()).padding(DoneAtSpacing.xl), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                        TextButton(onClick = { showsGift = false }) { Text(stringResource(R.string.close)) }
                        // Only this explicit user-open path displays a priced
                        // card; its viewport callback starts the single timer.
                        LifetimeOfferCard(graph.plus)
                    }
                }
            }
        }
    }
}

@Composable
private fun ReleaseFeature(symbol: ImageVector, title: Int, body: Int, largeText: Boolean) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), verticalAlignment = Alignment.Top) {
        if (!largeText) Icon(symbol, null, Modifier.size(DoneAtSpacing.xl), tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
            Text(stringResource(title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(stringResource(body), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

package com.rainif.doneat.plus

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.PlusPendingAction
import com.rainif.doneat.ui.settings.openUrl

@Composable
fun PlusScreen(graph: AppGraph, onBack: () -> Unit,
    pendingAction: PlusPendingAction? = null, onAuthorized: (PlusPendingAction) -> Unit = {}) {
    val authorized by graph.plus.authorized.collectAsStateWithLifecycle()
    val store by graph.plus.state.collectAsStateWithLifecycle()
    val activity = LocalContext.current.activity()
    LaunchedEffect(Unit) { graph.plus.refresh() }
    LaunchedEffect(authorized, pendingAction) {
        if (authorized && pendingAction != null) onAuthorized(pendingAction)
    }
    DoneAtPage(stringResource(R.string.plusSettings), onBack, stringResource(R.string.settings)) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.page),
            verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s),
        ) {
            Text(
                stringResource(if (authorized) R.string.plusStatusSubscribed else R.string.plusIntroTitle),
                style = MaterialTheme.typography.headlineSmall,
            )
            val message = when (store.status) {
                PlusStatus.UNCONFIGURED -> R.string.plusAndroidStoreUnconfigured
                PlusStatus.OFFLINE, PlusStatus.ERROR -> R.string.plusAndroidStoreOffline
                PlusStatus.PENDING -> R.string.plusStatusPending
                else -> null
            }
            if (message != null) Text(stringResource(message), color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (store.operationFailed) Text(stringResource(R.string.plusAndroidRequestFailed),
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (!authorized && store.status == PlusStatus.FREE) {
                store.offers.forEach { offer ->
                    val label = when (offer.plan) {
                        PlusPlan.MONTHLY -> R.string.plusMonthly
                        PlusPlan.YEARLY -> R.string.plusYearly
                        PlusPlan.LIFETIME -> R.string.plusLifetime
                    }
                    Button(onClick = { activity?.let { graph.plus.purchase(it, offer.plan) } },
                        enabled = activity != null && !store.busy,
                        modifier = Modifier.fillMaxWidth()) {
                        Text("${stringResource(label)} · ${offer.price}")
                    }
                }
                if (store.offers.any { it.plan != PlusPlan.LIFETIME }) {
                    Text(stringResource(R.string.plusAndroidRenewalNotice),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (store.status != PlusStatus.UNCONFIGURED) {
                OutlinedButton(onClick = graph.plus::restore, enabled = !store.busy, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.plusRestore))
                }
            }
            if (store.status == PlusStatus.SUBSCRIBED || store.hasPurchasedBefore) {
                TextButton(onClick = { openUrl(activity ?: return@TextButton,
                    "https://play.google.com/store/account/subscriptions") }) {
                    Text(stringResource(R.string.plusManage))
                }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                TextButton(onClick = { openUrl(activity ?: return@TextButton, "https://doneat.app/privacy") }) {
                    Text(stringResource(R.string.plusPrivacy))
                }
                TextButton(onClick = { openUrl(activity ?: return@TextButton, "https://play.google.com/about/play-terms/") }) {
                    Text(stringResource(R.string.plusTerms))
                }
            }
        }
        SettingsGroup {
            listOf(
                R.string.plusBenefitCharts,
                R.string.plusBenefitLife,
                R.string.plusBenefitEdit,
                R.string.plusBenefitFocus,
            ).forEach { benefit ->
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.s),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(Icons.Outlined.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
                    Text(stringResource(benefit), style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

private fun Context.activity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return current as? Activity
}

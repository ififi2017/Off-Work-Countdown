package com.rainif.doneat.plus

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.BuildConfig
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtBrandMark
import com.rainif.doneat.core.designsystem.DoneAtCard
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtBottomBarPadding
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.PlusPendingAction
import com.rainif.doneat.ui.settings.openUrl
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.net.URI
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@Composable
internal fun CnMembershipScreen(graph: AppGraph, onBack: () -> Unit, pendingAction: PlusPendingAction?, onAuthorized: (PlusPendingAction) -> Unit) {
    val repo = graph.plus.repository as CnLicenseRepository
    val state by repo.membership.collectAsStateWithLifecycle()
    val plus by graph.plus.state.collectAsStateWithLifecycle()
    val authorized by graph.plus.authorized.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    // Codes, expanded code entry and confirmation consent stay out of savedInstanceState.
    var code by remember { mutableStateOf("") }
    var codeExpanded by remember { mutableStateOf(false) }
    var redeem by remember { mutableStateOf(false) }
    var trialConsent by remember { mutableStateOf(false) }
    val debugLoopback = BuildConfig.DEBUG && runCatching {
        URI(BuildConfig.CN_LICENSE_API).host in setOf("localhost", "127.0.0.1")
    }.getOrDefault(false)
    val notice = cnMembershipNotice(state.error, state.pending, debugLoopback)
    LaunchedEffect(Unit) { graph.plus.refresh() }
    LaunchedEffect(state.confirmation) { if (state.confirmation != null) code = "" }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.safeDrawingPadding()) {
            Box(Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch + DoneAtSpacing.s)) {
                IconButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart)) {
                    Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.settings))
                }
                Text(stringResource(R.string.plusSettings), Modifier.align(Alignment.Center).padding(horizontal = DoneAtSpacing.minTouch),
                    style = MaterialTheme.typography.titleMedium)
            }
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = DoneAtSpacing.page)
                .padding(top = DoneAtSpacing.s, bottom = DoneAtSpacing.xl + LocalDoneAtBottomBarPadding.current),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.widthIn(max = 560.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                    CnAccessCard(state, authorized,
                        canStartTrial = !plus.hasPurchasedBefore && state.receipt == null,
                        onTrial = { trialConsent = true }, onRefresh = graph.plus::refresh)

                    if (notice != CnMembershipNotice.NONE || !state.configured) {
                        CnConnectionNotice(state, notice, authorized && state.receipt?.reason == "valid" && state.trialDaysRemaining != 0, onRetry = graph.plus::refresh,
                            onRecover = { scope.launch { repo.recoverPending() } })
                    }
                    if (authorized && pendingAction != null) DoneAtPrimaryButton(stringResource(R.string.continue_),
                        onClick = { onAuthorized(pendingAction) }, modifier = Modifier.fillMaxWidth())

                    if (state.receipt?.plan != "lifetime") DoneAtCard(Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.cnPurchaseTitle), style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold)
                        Text(stringResource(R.string.cnPurchaseBody), style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(DoneAtSpacing.xs))
                        if (authorized && pendingAction != null) OutlinedButton(
                            onClick = { openUrl(context, "https://doneat.com.cn/android/buy") }, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.cnBuy))
                        } else DoneAtPrimaryButton(stringResource(R.string.cnBuy),
                            onClick = { openUrl(context, "https://doneat.com.cn/android/buy") }, modifier = Modifier.fillMaxWidth())
                        Text(stringResource(R.string.cnNoAutomaticCharge), style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }

                    Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                        Column {
                            Surface(onClick = { codeExpanded = !codeExpanded }, color = Color.Transparent) {
                                Row(Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch)
                                    .padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.m),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                                    Icon(Icons.Outlined.Key, null, tint = MaterialTheme.colorScheme.primary)
                                    Text(stringResource(R.string.cnHaveCode), Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
                                    Icon(if (codeExpanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null,
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                            if (codeExpanded) Column(Modifier.padding(horizontal = DoneAtSpacing.l).padding(bottom = DoneAtSpacing.l),
                                verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                                Text(stringResource(R.string.cnCodeHelp), style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                                if (state.receipt?.source == "license" && state.receipt?.plan != "lifetime") {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Checkbox(checked = redeem, onCheckedChange = { if (!state.busy && !state.pending) redeem = it })
                                        Text(stringResource(R.string.cnRedeem), style = MaterialTheme.typography.bodyMedium)
                                    }
                                }
                                OutlinedTextField(value = code, onValueChange = { if (it.length <= 100) code = it }, singleLine = true,
                                    enabled = !state.busy && !state.pending, label = { Text(stringResource(R.string.cnLicenseCode)) },
                                    keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, keyboardType = KeyboardType.Password),
                                    colors = OutlinedTextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent),
                                    modifier = Modifier.fillMaxWidth())
                                FilledTonalButton(onClick = { scope.launch { repo.preview(code, redeem) } }, modifier = Modifier.fillMaxWidth(),
                                    enabled = state.configured && !state.busy && !state.pending && code.isNotBlank()) {
                                    Text(stringResource(R.string.cnPreview), style = MaterialTheme.typography.labelLarge)
                                }
                            }
                        }
                    }
                    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center,
                        verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                        TextButton(onClick = { openUrl(context, "https://doneat.com.cn/android/faq") }) {
                            Text(stringResource(R.string.cnFaq), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        TextButton(onClick = { openUrl(context, "https://doneat.com.cn/android/privacy") }) {
                            Text(stringResource(R.string.privacyPolicy), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
    if (trialConsent) AlertDialog(onDismissRequest = { trialConsent = false }, title = { Text(stringResource(R.string.cnStartTrial)) },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            Text(stringResource(R.string.cnTrialNotice))
            TextButton(onClick = { openUrl(context, "https://doneat.com.cn/android/privacy") }) { Text(stringResource(R.string.privacyPolicy)) }
        } }, confirmButton = { TextButton(onClick = { trialConsent = false; scope.launch { repo.startTrial() } }) { Text(stringResource(R.string.cnStartTrial)) } },
        dismissButton = { TextButton(onClick = { trialConsent = false }) { Text(stringResource(R.string.cancel)) } })
    state.confirmation?.let { c ->
        val replacement = c["willReplaceDevice"]?.jsonPrimitive?.boolean == true
        val newPlan = (c["newPlan"] ?: c["plan"])?.jsonPrimitive?.content
        AlertDialog(onDismissRequest = repo::cancelConfirmation, title = { Text(stringResource(if (redeem) R.string.cnRedeem else R.string.cnConfirm)) },
            text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                Text(stringResource(if (newPlan == "lifetime") R.string.plusLifetime else R.string.plusYearly))
                (c["newExpiresAt"] ?: c["expiresAt"])?.takeUnless { it == JsonNull }?.jsonPrimitive?.content?.let {
                    val expiry = runCatching { localDate(Instant.parse(it).toEpochMilli()) }.getOrDefault(it)
                    Text(Strings.cnExpiry(LocalResources.current, date = expiry))
                }
                if (replacement) Text(stringResource(R.string.cnTransferWarning))
                c["transferRemaining"]?.jsonPrimitive?.content?.let { Text(Strings.cnTransferRemaining(LocalResources.current, count = it)) }
            } }, confirmButton = { TextButton(onClick = { scope.launch { repo.confirm() } }, enabled = !state.busy && !state.pending) { Text(stringResource(R.string.cnConfirm)) } },
            dismissButton = { TextButton(onClick = repo::cancelConfirmation, enabled = !state.busy) { Text(stringResource(R.string.cancel)) } })
    }
}

@Composable
private fun CnAccessCard(state: CnMembershipState, authorized: Boolean, canStartTrial: Boolean, onTrial: () -> Unit, onRefresh: () -> Unit) {
    val receipt = state.receipt
    val access = cnAccessPresentation(receipt?.reason, authorized, state.busy, state.error, state.trialDaysRemaining)
    val statusLabel = when (access) {
        CnAccessPresentation.VERIFIED -> R.string.cnAccessVerified
        CnAccessPresentation.SAVED -> R.string.cnUsingSavedAccess
        CnAccessPresentation.CHECKING -> R.string.cnCheckingAccess
        CnAccessPresentation.EXPIRED -> R.string.cnStatusExpired
        CnAccessPresentation.REVOKED -> R.string.cnStatusRevoked
        CnAccessPresentation.REPLACED -> R.string.cnStatusReplaced
        CnAccessPresentation.NEEDS_PROOF -> R.string.cnInactive
    }
    Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                Surface(shape = MaterialTheme.shapes.small, color = MaterialTheme.colorScheme.primaryContainer) {
                    Text(stringResource(when (receipt?.plan) { "lifetime" -> R.string.plusLifetime; "annual" -> R.string.plusYearly; else -> R.string.cnTrialPlan }),
                        Modifier.padding(horizontal = DoneAtSpacing.m, vertical = DoneAtSpacing.s),
                        style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onPrimaryContainer)
                }
                Spacer(Modifier.weight(1f))
                DoneAtBrandMark(Modifier.size(DoneAtSpacing.xxl + DoneAtSpacing.s), showsDepth = true)
            }
            if (receipt?.source == "trial" && state.trialDaysRemaining != null) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), modifier = Modifier.semantics(mergeDescendants = true) {}) {
                    Text(NumberFormat.getIntegerInstance(LocalResources.current.configuration.locales[0]).format(state.trialDaysRemaining),
                        style = MaterialTheme.typography.displayMedium, fontWeight = FontWeight.SemiBold)
                    Text(stringResource(R.string.cnDaysRemaining), Modifier.padding(bottom = DoneAtSpacing.s).weight(1f),
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else if (receipt == null) {
                Text(stringResource(R.string.plusIntroTitle), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.plusAndroidIntroBody), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else Text(stringResource(statusLabel),
                style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            receipt?.expiresAtMs?.let {
                Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Outlined.Event, null, Modifier.size(DoneAtSpacing.l), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(Strings.cnExpiry(LocalResources.current, date = localDate(it)), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (receipt != null) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
                FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs), itemVerticalAlignment = Alignment.CenterVertically) {
                    Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), verticalAlignment = Alignment.CenterVertically) {
                        Icon(when (access) {
                            CnAccessPresentation.REVOKED -> Icons.Outlined.Block
                            CnAccessPresentation.REPLACED -> Icons.Outlined.DevicesOther
                            CnAccessPresentation.EXPIRED -> Icons.Outlined.EventBusy
                            CnAccessPresentation.CHECKING -> Icons.Outlined.Sync
                            CnAccessPresentation.SAVED, CnAccessPresentation.NEEDS_PROOF -> Icons.Outlined.WifiOff
                            else -> Icons.Outlined.CheckCircle
                        },
                            null, Modifier.size(DoneAtSpacing.l), tint = if (authorized) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(statusLabel),
                            style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    TextButton(onClick = onRefresh, enabled = state.configured && !state.busy, contentPadding = PaddingValues(horizontal = DoneAtSpacing.s)) {
                        Text(stringResource(R.string.cnRefresh), style = MaterialTheme.typography.labelMedium)
                    }
                }
                if (!authorized && receipt.reason in setOf("expired", "revoked", "replaced")) Text(
                    stringResource(if (receipt.reason == "expired" && receipt.source == "trial") R.string.cnTrialUnavailable else R.string.cnLicenseUnavailable),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (canStartTrial) OutlinedButton(onClick = onTrial, modifier = Modifier.fillMaxWidth(), enabled = state.configured && !state.busy && !state.pending) {
                Text(stringResource(R.string.cnStartTrial))
            }
        }
    }
}

@Composable
private fun CnConnectionNotice(state: CnMembershipState, notice: CnMembershipNotice, authorized: Boolean, onRetry: () -> Unit, onRecover: () -> Unit) {
    Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), verticalAlignment = Alignment.Top) {
                Icon(Icons.Outlined.Info, null, Modifier.size(DoneAtSpacing.l), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                    Text(stringResource(when {
                        !state.configured -> R.string.cnServiceUnconfigured
                        BuildConfig.DEBUG && notice == CnMembershipNotice.DEBUG_CONNECTION -> R.string.cnDebugConnectionHelp
                        notice == CnMembershipNotice.CONNECTION -> R.string.cnConnectionHelp
                        notice == CnMembershipNotice.RETRY_ORIGINAL -> R.string.cnOperationNotFound
                        notice == CnMembershipNotice.PENDING -> R.string.cnPendingNotice
                        notice == CnMembershipNotice.TRIAL_UNAVAILABLE -> R.string.cnTrialUnavailable
                        else -> R.string.cnRequestFailed
                    }), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (authorized) Text(stringResource(R.string.cnUsingSavedAccess), style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary)
                }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                TextButton(onClick = onRetry, enabled = state.configured && !state.busy) {
                    Text(stringResource(if (state.pending) R.string.cnRetryOriginal else R.string.cnRefresh))
                }
                if (state.pending && notice != CnMembershipNotice.RETRY_ORIGINAL) TextButton(onClick = onRecover, enabled = !state.busy) {
                    Text(stringResource(R.string.cnCheckResult))
                }
            }
        }
    }
}

private fun localDate(ms: Long): String = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
    .withZone(ZoneId.systemDefault()).format(Instant.ofEpochMilli(ms))

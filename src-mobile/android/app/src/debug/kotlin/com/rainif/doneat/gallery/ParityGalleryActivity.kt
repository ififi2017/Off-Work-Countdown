package com.rainif.doneat.gallery

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import android.content.res.AssetManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.BuildConfig
import com.rainif.doneat.DoneAtApplication
import com.rainif.doneat.core.data.WriteResult
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.DoneAtTheme
import com.rainif.doneat.core.designsystem.ThemeMode
import com.rainif.doneat.core.domain.leave.LeavePlanProposal
import com.rainif.doneat.core.domain.leave.LeavePlanner
import com.rainif.doneat.core.domain.leave.LeavePlannerSchedule
import com.rainif.doneat.core.domain.records.LeaveBalance
import com.rainif.doneat.core.domain.records.LeaveBudget
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ShiftCycleRule
import com.rainif.doneat.core.domain.schedule.ShiftType
import com.rainif.doneat.core.domain.schedule.WallClock
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import com.rainif.doneat.plus.LifetimeOffer
import com.rainif.doneat.plus.LifetimeOfferCardContent
import com.rainif.doneat.plus.LifetimeOfferSource
import com.rainif.doneat.plus.PlusOffer
import com.rainif.doneat.plus.PlusPlan
import com.rainif.doneat.plus.PlusScreen
import com.rainif.doneat.ui.AppLanguageScope
import com.rainif.doneat.ui.AppShell
import com.rainif.doneat.ui.PlusPendingAction
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.SystemBarsFollowTheme
import com.rainif.doneat.ui.adaptive.AdaptiveBounds
import com.rainif.doneat.ui.adaptive.DisplayFold
import com.rainif.doneat.ui.adaptive.FoldAxis
import com.rainif.doneat.ui.adaptive.LocalDoneAtWindowPosture
import com.rainif.doneat.ui.adaptive.WindowPosture
import com.rainif.doneat.ui.adaptive.rememberWindowPosture
import com.rainif.doneat.ui.leave.LeavePlanDetailScreen
import com.rainif.doneat.ui.leave.LeavePlanResultsScreen
import com.rainif.doneat.ui.onboarding.SetupFlow
import com.rainif.doneat.ui.onboarding.SetupPage
import androidx.activity.compose.LocalActivityResultRegistryOwner
import com.rainif.doneat.ui.onboarding.SetupWeekdaySelector
import com.rainif.doneat.ui.release.WhatsNewScreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Debug-only QA over real screens. Checks the runtime package before
 * any seed or debug entitlement mutation. Build with .parity321 isolation.
 *
 * screen: results (default), shell, plus, release, offer, onboarding.
 * theme/locale/fontScale/reduced/authorized keep their existing meanings.
 * previewWidthDp + previewHeightDp fit a local dp viewport into this window;
 * they do not change device settings. posture (or fold): none/horizontal/vertical
 * injects a visual fold only when explicitly present. requestedTab (or tab)
 * selects timer/focus/records/settings. No injected pose is hardware evidence.
 *
 * Only results + explicit seedBalance writes the synthetic adoption budget.
 * Onboarding is read-only and requires an uncompleted isolated setup; its
 * optional onboardingPage selects a real page over an unsaved device draft.
 * No alarm, permission, setup completion or price/entitlement fixture is seeded.
 */
class ParityGalleryActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!BuildConfig.DEBUG || packageName != "com.rainif.doneat.parity321") {
            finish()
            return
        }
        enableEdgeToEdge()
        val graph = (application as DoneAtApplication).graph
        val initialScreen = intent.getStringExtra("screen")?.takeIf {
            it in setOf("results", "shell", "plus", "release", "offer", "onboarding", "weekdays")
        } ?: "results"
        val mode = when (intent.getStringExtra("theme")) {
            "light" -> ThemeMode.LIGHT
            "dark" -> ThemeMode.DARK
            else -> ThemeMode.SYSTEM
        }
        setContent {
            val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
            var ready by remember { mutableStateOf(false) }
            var failed by remember { mutableStateOf(false) }
            var onboardingAvailable by remember { mutableStateOf(false) }
            var screen by rememberSaveable { mutableStateOf(initialScreen) }
            var planIndex by rememberSaveable { mutableIntStateOf(0) }
            val holder = rememberSaveableStateHolder()
            LaunchedEffect(Unit) {
                graph.loaded.first { it }
                try {
                    if (initialScreen == "results") {
                        val proposals = withContext(Dispatchers.Default) {
                            val calendar = assets.open("HolidayTemplates.json").use { HolidayCalendar.parse(it.readBytes().decodeToString()) }
                            previewProposals(calendar)
                        }
                        if (intent.getBooleanExtra("seedBalance", false)) {
                            val now = graph.nowMs()
                            val balance = LeaveBalance(BUDGET_ID, "annual", null, 10, 0, null, null, now, 1, graph.newId())
                            val saved = graph.records.update { records ->
                                records.copy(leaveBalances = records.leaveBalances.filterNot { it.id == BUDGET_ID } + balance) to true
                            }
                            check(saved is WriteResult.Saved)
                        }
                        graph.leaveProposals.value = proposals
                    }
                    graph.plus.setDebugAuthorized(intent.getBooleanExtra("authorized", false))
                    if (initialScreen == "shell") {
                        (intent.getStringExtra("requestedTab") ?: intent.getStringExtra("tab"))?.takeIf {
                            it in setOf("timer", "focus", "records", "settings")
                        }?.let { graph.requestedTab.value = it }
                    }
                    if (initialScreen == "onboarding") {
                        // SetupFlow applies reminder defaults on composition. Existing
                        // archives must never be edited merely for a screenshot.
                        onboardingAvailable = !graph.settings.device.value.onboardingComplete &&
                            graph.records.state.value.syncedPreferences == null
                        if (onboardingAvailable) {
                            val page = SetupPage.entries.firstOrNull {
                                it.name.equals(intent.getStringExtra("onboardingPage"), ignoreCase = true)
                            } ?: SetupPage.WELCOME
                            graph.settings.updateDevice { it.copy(setupPage = page.name,
                                setupDraft = it.setupDraft ?: graph.settings.preferences.value) }
                        }
                    }
                    ready = true
                } catch (_: Exception) { failed = true }
            }
            val dark = when (mode) {
                ThemeMode.LIGHT -> false
                ThemeMode.DARK -> true
                ThemeMode.SYSTEM -> isSystemInDarkTheme()
            }
            SystemBarsFollowTheme(dark)
            AppLanguageScope(intent.getStringExtra("locale") ?: prefs.languageOverride) {
                DoneAtTheme(themeMode = mode, reducedMotion = if (intent.hasExtra("reduced")) intent.getBooleanExtra("reduced", false) else null) {
                    GalleryViewport { previewLabel ->
                        // Preserve this language scope's resources/theme but remove
                        // the Activity needed by real Plus purchase callbacks.
                        val themedContext = LocalContext.current
                        val noPurchaseContext = remember(themedContext) { NoPurchasePreviewContext(themedContext) }
                        CompositionLocalProvider(LocalContext provides noPurchaseContext) {
                            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                                if (!ready) {
                                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                        if (failed) Text("Could not prepare parity preview.") else CircularProgressIndicator()
                                    }
                                } else {
                                    fun back() { if (screen in setOf("detail", "plan-plus")) screen = "results" else finish() }
                                    BackHandler(enabled = screen != "shell") { back() }
                                    when (screen) {
                                        "shell" -> AppShell(graph)
                                        "release" -> WhatsNewScreen(graph, onDismiss = ::back)
                                        "onboarding" -> if (onboardingAvailable) {
                                            CompositionLocalProvider(LocalActivityResultRegistryOwner provides this@ParityGalleryActivity) {
                                                ReadOnlyOnboarding { SetupFlow(graph) }
                                            }
                                        } else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                            Text("Read-only onboarding needs a fresh isolated setup. Existing settings were preserved.", Modifier.padding(DoneAtSpacing.xl))
                                        }
                                        "offer" -> SampleOfferPreview()
                                        "weekdays" -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
                                            Text("Read-only weekday layout preview", Modifier.padding(DoneAtSpacing.l))
                                            SetupWeekdaySelector(prefs.workdays, androidx.compose.ui.platform.LocalResources.current.configuration.locales[0]) {}
                                        }
                                        "plus" -> PlusScreen(graph, ::back)
                                        "detail" -> holder.SaveableStateProvider("detail:$planIndex") {
                                            LeavePlanDetailScreen(graph, planIndex, ::back, onAdopted = { screen = "results" })
                                        }
                                        "plan-plus" -> holder.SaveableStateProvider("plus:$planIndex") {
                                            PlusScreen(graph, ::back, PlusPendingAction.LeavePlan(planIndex)) { action ->
                                                if (action is PlusPendingAction.LeavePlan) { planIndex = action.index; screen = "detail" }
                                            }
                                        }
                                        else -> holder.SaveableStateProvider("results") {
                                            LeavePlanResultsScreen(graph, open = { route -> when (route) {
                                                is Route.LeavePlanDetail -> { planIndex = route.index; screen = "detail" }
                                                is Route.PlusFor -> (route.action as? PlusPendingAction.LeavePlan)?.let { planIndex = it.index; screen = "plan-plus" }
                                                else -> Unit
                                            } }, onBack = ::back)
                                        }
                                    }
                                }
                            }
                        }
                        // A separate overlay labels simulation without reserving or
                        // changing the actual root screen's content constraints.
                        if (previewLabel != null || screen == "onboarding") {
                            Surface(Modifier.align(Alignment.BottomEnd).safeDrawingPadding(), color = MaterialTheme.colorScheme.surfaceContainerHighest) {
                                TextButton(onClick = { finish() }) {
                                    Text(previewLabel ?: "Read-only onboarding preview · Exit", style = MaterialTheme.typography.labelSmall)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /** All geometry changes are inside this Compose subtree, never system settings. */
    @Composable
    private fun GalleryViewport(content: @Composable androidx.compose.foundation.layout.BoxScope.(String?) -> Unit) {
        val realDensity = LocalDensity.current
        val configuration = LocalConfiguration.current
        val widthExtra = numberExtra("previewWidthDp")
        val heightExtra = numberExtra("previewHeightDp")
        val foldMode = (intent.getStringExtra("posture") ?: intent.getStringExtra("fold"))?.takeIf {
            it in setOf("none", "horizontal", "vertical")
        }
        val font = intent.getFloatExtra("fontScale", realDensity.fontScale).takeIf { it.isFinite() && it > 0 } ?: realDensity.fontScale
        BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val widthPx = with(realDensity) { maxWidth.toPx() }
            val heightPx = with(realDensity) { maxHeight.toPx() }
            val width = widthExtra ?: widthPx / realDensity.density
            val height = heightExtra ?: if (widthExtra != null) heightPx / (widthPx / width) else heightPx / realDensity.density
            val scaledDensity = if (widthExtra != null || heightExtra != null) min(widthPx / width, heightPx / height) else realDensity.density
            val localDensity = Density(scaledDensity, font)
            val localConfiguration = remember(configuration, width, height, font) {
                Configuration(configuration).apply {
                    screenWidthDp = width.roundToInt()
                    screenHeightDp = height.roundToInt()
                    smallestScreenWidthDp = min(width, height).roundToInt()
                    fontScale = font
                    orientation = if (width > height) Configuration.ORIENTATION_LANDSCAPE else Configuration.ORIENTATION_PORTRAIT
                }
            }
            CompositionLocalProvider(LocalDensity provides localDensity, LocalConfiguration provides localConfiguration) {
                val systemPosture = rememberWindowPosture()
                var origin by remember { mutableStateOf(Offset.Zero) }
                val posture = if (foldMode == null) systemPosture else {
                    val x = origin.x / scaledDensity
                    val y = origin.y / scaledDensity
                    when (foldMode) {
                        "horizontal" -> WindowPosture(listOf(DisplayFold(AdaptiveBounds(x, y + height / 2 - 4f, x + width, y + height / 2 + 4f), FoldAxis.HORIZONTAL, true, true, true)))
                        "vertical" -> WindowPosture(listOf(DisplayFold(AdaptiveBounds(x + width / 2 - 4f, y, x + width / 2 + 4f, y + height), FoldAxis.VERTICAL, true, true, true)))
                        else -> WindowPosture()
                    }
                }
                CompositionLocalProvider(LocalDoneAtWindowPosture provides posture) {
                    Box(Modifier.requiredSize(width.dp, height.dp).onGloballyPositioned { origin = it.positionInWindow() }) {
                        val simulated = widthExtra != null || heightExtra != null || foldMode != null
                        val label = if (simulated) "Visual preview ${width.roundToInt()}×${height.roundToInt()} dp · ${foldMode ?: "system posture"} · not hardware evidence · Exit" else null
                        content(label)
                    }
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun numberExtra(key: String): Float? = (intent.extras?.get(key) as? Number)?.toFloat()?.takeIf {
        it.isFinite() && it in 240f..2400f
    }

    private companion object {
        const val BUDGET_ID = "00000000-0000-0000-0000-000000000211"

        /** Same schedule, range, holiday source and 10-half-day budget as pinned iOS. */
        fun previewProposals(calendar: HolidayCalendar): List<LeavePlanProposal> {
            val work = UUID.fromString("00000000-0000-0000-0000-000000000201")
            val rest = UUID.fromString("00000000-0000-0000-0000-000000000202")
            val types = listOf(work to ShiftType.Kind.WORK, rest to ShiftType.Kind.REST).map { (id, kind) ->
                ShiftType(id, if (kind == ShiftType.Kind.WORK) "Office" else "Rest", kind, 540, 1020, false, 720, 0, "#FF7A00", false)
            }
            val plan = ExtendedSchedulePlan(
                shiftTypes = types,
                rule = ShiftCycleRule(ShiftCycleRule.Preset.WEEKLY, "2026-09-21", listOf(work, work, work, work, work, rest, rest)),
                handSetDays = emptyMap(), holidayRegionIdentifier = "CN", holidays = calendar,
            )
            val hours = ScheduleHours("09:00", "17:00", listOf(1, 2, 3, 4, 5), WorkSchedule(ScheduleMode.CLASSIC), null, 0, plan)
            val first = LeavePlannerSchedule.dayNumber(LocalDate.of(2026, 9, 21))
            val last = first + 364
            val zone = ZoneId.of("Asia/Shanghai")
            val days = LeavePlannerSchedule.days(hours, first..last, zone, calendar)
            return LeavePlanner.proposals(days, LeavePlanner.Query(
                goal = LeavePlanner.Goal.LeaveAtMost(10), fromDayNumber = first, throughDayNumber = last,
                nowMs = CivilZone(zone).utcMs(first, WallClock.MIDNIGHT), budgets = listOf(LeaveBudget(BUDGET_ID, 10)),
            ))
        }
    }
}

/**
 * Keep ContextWrapper's real UI delegate for window/display/system services.
 * Only the public unwrap chain is cut: Plus's activity() cannot find a purchase
 * host, while native isUiContext/display/window association still delegates to
 * the actual localized Activity context on every supported Android version.
 */
private class NoPurchasePreviewContext(private val themed: Context) : ContextWrapper(themed) {
    override fun getBaseContext(): Context = themed.applicationContext
    override fun getResources(): Resources = themed.resources
    override fun getAssets(): AssetManager = themed.assets
    override fun getTheme(): Resources.Theme = themed.theme
}

@Composable
private fun ReadOnlyOnboarding(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize().clearAndSetSemantics { contentDescription = "Read-only onboarding visual preview; setup and permissions disabled." }
        .onPreviewKeyEvent { true }
        .pointerInput(Unit) {
            awaitPointerEventScope {
                while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
            }
        }) { content() }
}

/** Real presentation component over explicit data-only sample terms; no billing/offer store. */
@Composable
private fun SampleOfferPreview() {
    val now = remember { System.currentTimeMillis() }
    val invitation = remember { LifetimeOffer(LifetimeOfferSource.UPDATE_321, now).claim(now) }
    val price = remember { PlusOffer(PlusPlan.LIFETIME, "€74.99", "sample-no-purchase", priceMicros = 74_990_000,
        currency = "EUR", regularPrice = "€99.99", regularPriceMicros = 99_990_000,
        purchaseOptionId = "sample-no-purchase", offerId = "sample-no-purchase") }
    Column(Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(DoneAtSpacing.xl), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
        Text("Sample price fixture · no purchase · no offer timer saved", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        LifetimeOfferCardContent(invitation, price, now, enabled = true, onClaim = {}, onPurchase = {}, onPriceVisible = {})
    }
}

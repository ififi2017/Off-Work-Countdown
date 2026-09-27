package com.rainif.doneat

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.tween
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import com.rainif.doneat.core.designsystem.DoneAtTheme
import com.rainif.doneat.core.designsystem.DoneAtBrandMark
import com.rainif.doneat.core.designsystem.DoneAtMotion
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.core.designsystem.ThemeMode
import com.rainif.doneat.reminders.Reminders
import com.rainif.doneat.ui.AppLanguageScope
import com.rainif.doneat.ui.AppLocale
import com.rainif.doneat.ui.ArchiveRecoveryScreen
import com.rainif.doneat.core.data.RecordPersistenceError
import com.rainif.doneat.ui.AppShell
import com.rainif.doneat.ui.SystemBarsFollowTheme
import com.rainif.doneat.ui.onboarding.SetupFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/** A [FragmentActivity] so `BiometricPrompt` can confirm the owner before earnings are revealed. */
class MainActivity : FragmentActivity() {
    override fun onResume() {
        super.onResume()
        (application as DoneAtApplication).graph.plus.refresh()
    }

    override fun onStart() {
        super.onStart()
        // Revoking the exact-alarm grant sends no broadcast; re-check it whenever the app comes back.
        lifecycleScope.launch(Dispatchers.IO) { Reminders.sync(applicationContext).revalidate(System.currentTimeMillis()) }
        // Midnight resets, expired marks and a finished manual run: settled before the timer draws.
        val graph = (application as DoneAtApplication).graph
        lifecycleScope.launch {
            if (graph.loaded.value) {
                graph.timer.reconcile()
                graph.focusCoordinator.reconcile()
                graph.widgets.refresh()
                graph.ongoing.apply()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val graph = (application as DoneAtApplication).graph
        if (savedInstanceState == null) openRequestedTab(intent)
        setContent {
            val loaded by graph.loaded.collectAsStateWithLifecycle()
            val archiveError by graph.records.persistenceError.collectAsStateWithLifecycle()
            val setUp by graph.settings.isSetUp.collectAsStateWithLifecycle()
            val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
            val device by graph.settings.device.collectAsStateWithLifecycle()

            LaunchedEffect(loaded) { if (loaded) reconcileLanguage(graph) }

            val mode = when (prefs.theme) {
                "light" -> ThemeMode.LIGHT
                "dark" -> ThemeMode.DARK
                else -> ThemeMode.SYSTEM
            }
            val dark = when (mode) {
                ThemeMode.SYSTEM -> isSystemInDarkTheme()
                ThemeMode.LIGHT -> false
                ThemeMode.DARK -> true
            }
            SystemBarsFollowTheme(dark)
            AppLanguageScope(prefs.languageOverride) {
                DoneAtTheme(themeMode = mode, dynamicColor = device.dynamicColor) {
                    val motion = LocalDoneAtMotion.current
                    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                        // Until the archive is read nothing can tell a first launch from a restored one.
                        if (!loaded) {
                            LaunchPlaceholder()
                        } else if (archiveError == RecordPersistenceError.INVALID_ARCHIVE || archiveError == RecordPersistenceError.UNREADABLE_ARCHIVE) {
                            ArchiveRecoveryScreen(graph)
                        } else AnimatedContent(
                            targetState = setUp,
                            transitionSpec = {
                                if (motion.reduced) {
                                    fadeIn(tween(DoneAtMotion.REDUCED_MS)) togetherWith fadeOut(tween(DoneAtMotion.REDUCED_MS))
                                } else {
                                    (slideInVertically(motion.phase()) { it / 16 } + fadeIn(tween(DoneAtMotion.PHASE_MS))) togetherWith
                                        (slideOutVertically(motion.phase()) { -it / 16 } + fadeOut(tween(DoneAtMotion.STATE_ENTER_MS)))
                                }.using(null)
                            },
                            label = "setupComplete",
                        ) { complete ->
                            if (complete) AppShell(graph) else SetupFlow(graph)
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openRequestedTab(intent)
    }

    /** A notification names the tab it belongs to: a focus alert opens Focus, as on iOS. */
    private fun openRequestedTab(intent: Intent?) {
        val tab = intent?.getStringExtra(EXTRA_TAB)?.takeIf { it in setOf("timer", "focus", "records", "settings") } ?: return
        intent.removeExtra(EXTRA_TAB)
        val graph = (application as DoneAtApplication).graph
        lifecycleScope.launch {
            graph.loaded.first { it }
            graph.requestedTab.value = tab
        }
    }

    companion object {
        /** The tab to show, by its stored name ("focus"). */
        const val EXTRA_TAB = "com.rainif.doneat.TAB"
    }

    /**
     * Android 13+: the system's per-app language and the synced preference can
     * disagree at launch. A choice made on the system's app settings page wins;
     * when the system holds none (a restored or new device), the preference is
     * handed to it.
     */
    private suspend fun reconcileLanguage(graph: AppGraph) {
        if (!AppLocale.hasPerAppLanguage) return
        val system = AppLocale.systemOverride(this)
        val preferred = graph.settings.preferences.value.languageOverride
        when {
            system == preferred -> Unit
            system != null -> graph.settings.edit { it.copy(languageOverride = system) }
            else -> AppLocale.applyToSystem(this, preferred)
        }
    }
}

/** Same quiet brand row as the iOS launch storyboard, while the archive is loading. */
@Composable
private fun LaunchPlaceholder() {
    Box(Modifier.fillMaxSize().safeDrawingPadding().padding(bottom = 88.dp), contentAlignment = Alignment.BottomCenter) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            DoneAtBrandMark(Modifier.size(44.dp))
            Text("DoneAt", fontSize = 34.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

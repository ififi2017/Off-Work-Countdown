package com.rainif.doneat

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import com.rainif.doneat.core.designsystem.DoneAtTheme
import com.rainif.doneat.core.designsystem.ThemeMode
import com.rainif.doneat.reminders.Reminders
import com.rainif.doneat.ui.AppLanguageScope
import com.rainif.doneat.ui.AppLocale
import com.rainif.doneat.ui.AppShell
import com.rainif.doneat.ui.SystemBarsFollowTheme
import com.rainif.doneat.ui.onboarding.SetupFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/** A [FragmentActivity] so `BiometricPrompt` can confirm the owner before earnings are revealed. */
class MainActivity : FragmentActivity() {
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
                    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                        // Until the archive is read nothing can tell a first launch from a restored one.
                        when {
                            !loaded -> Unit
                            setUp -> AppShell(graph)
                            else -> SetupFlow(graph)
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
        val tab = intent?.getStringExtra(EXTRA_TAB) ?: return
        intent.removeExtra(EXTRA_TAB)
        val graph = (application as DoneAtApplication).graph
        lifecycleScope.launch {
            graph.loaded.first { it }
            graph.settings.updateDevice { it.copy(selectedTab = tab) }
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

package com.rainif.doneat

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
import kotlinx.coroutines.launch

/** A [FragmentActivity] so `BiometricPrompt` can confirm the owner before earnings are revealed. */
class MainActivity : FragmentActivity() {
    override fun onStart() {
        super.onStart()
        // Revoking the exact-alarm grant sends no broadcast; re-check it whenever the app comes back.
        lifecycleScope.launch(Dispatchers.IO) { Reminders.sync(applicationContext).revalidate(System.currentTimeMillis()) }
        // Midnight resets, expired marks and a finished manual run: settled before the timer draws.
        val graph = (application as DoneAtApplication).graph
        lifecycleScope.launch { if (graph.loaded.value) graph.timer.reconcile() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val graph = (application as DoneAtApplication).graph
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

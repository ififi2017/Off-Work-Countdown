package com.rainif.doneat.plus

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.core.content.edit
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.SwitchRow

/** Debug builds only: a developer switch standing in for a purchase, so both tiers can be checked. */
object PlusDebugOverride {
    const val AVAILABLE = true
    private const val FILE = "debug_plus"
    private const val KEY = "authorized"

    fun read(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY, false)

    fun write(context: Context, value: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit { putBoolean(KEY, value) }
    }
}

/** The switch, shown on the About page of debug builds. Not translated: it never ships. */
@Composable
fun PlusDebugSection(plus: PlusAccess) {
    val authorized by plus.authorized.collectAsStateWithLifecycle()
    SettingsGroup(title = "Debug") {
        SwitchRow("Plus unlocked", authorized, plus::setDebugAuthorized, supporting = "Debug builds only. Stands in for a purchase.")
    }
}

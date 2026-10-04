package com.rainif.doneat.ui

import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.view.ContextThemeWrapper
import android.content.res.Resources
import android.os.Build
import android.os.LocaleList
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.unit.LayoutDirection
import com.rainif.doneat.core.domain.settings.AppLanguages
import java.util.Locale

/**
 * The app's own language, as iOS pins it with `languageOverride`.
 *
 * Android 13+ has a per-app language: setting it there also reaches the
 * system's app settings page and every context the app creates, and a change
 * the user makes on that page comes back into the preference. Earlier
 * versions have none, so the Compose tree renders in a context configured
 * for the chosen language instead.
 */
object AppLocale {
    /** Catalog code to BCP 47. `es-MX` is `es-419` so it hits `values-b+es+419`. */
    fun tag(code: String) = AppLanguages.resourceTag(code)

    val hasPerAppLanguage get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    /** The device's languages, most preferred first, ignoring any per-app choice. */
    fun systemPreferred(): List<String> = Resources.getSystem().configuration.locales.let { list -> (0 until list.size()).map { list[it].toLanguageTag() } }

    /** The per-app language the system holds now (Android 13+), as a catalog code; null for "follow the system". */
    fun systemOverride(context: Context): String? {
        if (!hasPerAppLanguage) return null
        val locales = context.getSystemService(LocaleManager::class.java).applicationLocales
        return if (locales.isEmpty) null else AppLanguages.resolve(listOf(locales[0].toLanguageTag()))
    }

    /** Hands [override] to the system (Android 13+); the activity is recreated in the new language. */
    fun applyToSystem(context: Context, override: String?) {
        if (!hasPerAppLanguage || systemOverride(context) == override) return
        context.getSystemService(LocaleManager::class.java).applicationLocales =
            override?.let { LocaleList.forLanguageTags(tag(it)) } ?: LocaleList.getEmptyLocaleList()
    }
}

/**
 * Renders [content] in the resolved language when the current configuration
 * would not already select those resources.
 *
 * Android 13+ per-app language covers an explicit choice. Following the
 * system does not: `en-AU` never selects `values-en-rGB`, so that case is
 * overlaid here too. `es-AR` already selects `values-b+es+419` and is left
 * alone.
 */
@Composable
fun AppLanguageScope(override: String?, content: @Composable () -> Unit) {
    val code = AppLanguages.effective(override, AppLocale.systemPreferred())
    val direction = if (AppLanguages.isRightToLeft(code)) LayoutDirection.Rtl else LayoutDirection.Ltr
    val base = LocalContext.current
    val current = LocalConfiguration.current
    val deviceTags = (0 until current.locales.size()).map { current.locales[it].toLanguageTag() }
    if (AppLanguages.deviceAlreadyUses(code, deviceTags)) {
        CompositionLocalProvider(LocalLayoutDirection provides direction, content = content)
        return
    }
    val localized = remember(base, current, code) {
        val configuration = Configuration(current).apply {
            setLocales(LocaleList(Locale.forLanguageTag(AppLocale.tag(code))))
        }
        // A wrapper around the activity, not createConfigurationContext: whatever looks for the
        // activity through the context (permission and file launchers, back handling) must still find it.
        ContextThemeWrapper(base, base.theme).apply { applyOverrideConfiguration(configuration) } to configuration
    }
    CompositionLocalProvider(
        LocalContext provides localized.first,
        // stringResource reads LocalResources, not LocalContext: both must carry the chosen language.
        LocalResources provides localized.first.resources,
        LocalConfiguration provides localized.second,
        LocalLayoutDirection provides direction,
        content = content,
    )
}

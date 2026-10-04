package com.rainif.doneat.core.domain.settings

import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.SyncedPreferences
import java.time.DayOfWeek
import java.time.Instant
import java.time.temporal.TemporalAdjusters

/**
 * The committed settings and how they change (iOS `PreferencesStore`).
 *
 * The archive's `syncedPreferences` is the only home of a committed setting.
 * Before first-run setup completes there is none: the defaults (or a draft)
 * live outside the archive, so a fresh install never stamps default values
 * as a newer edit over data restored from elsewhere.
 */
object PreferencesRules {
    /** A stamp for values that have never been committed (iOS `Date.distantPast` and the unset tie-breaker). */
    const val UNSET_EDITED_AT_MS = -62_135_769_600_000.0
    const val UNSET_TIE_BREAKER = "00000000-0000-0000-0000-000000000000"

    /** iOS first-launch defaults: 09:00–17:00 Mon–Fri, no lunch, salary off, reminders off. */
    fun defaults(recordsZone: String, nowMs: Double) = SyncedPreferences(
        startMinutes = 9 * 60,
        endMinutes = 17 * 60,
        workdays = listOf(1, 2, 3, 4, 5),
        scheduleMode = "classic",
        alternatingWeekType = "double",
        alternatingWeekendWorkday = 6,
        alternatingReferenceWeekStartMs = startOfWeekMs(nowMs, recordsZone),
        rotationWorkDays = 2,
        rotationRestDays = 2,
        rotationAnchorMs = startOfDayMs(nowMs, recordsZone),
        lunchEnabled = false,
        lunchStartMinutes = 12 * 60,
        lunchDurationMinutes = 60,
        recordsTimeZoneIdentifier = recordsZone,
        salaryAmount = "0",
        salaryEnabled = false,
        salaryType = "monthly",
        monthlyWorkingDays = 22.0,
        annualBonusEnabled = false,
        annualBonusMonths = 1.0,
        notificationMode = "off",
        cycleEndSummaryNotificationEnabled = false,
        lunchStartReminderEnabled = false,
        lunchEndReminderEnabled = false,
        microBreakEnabled = false,
        microBreakIntervalMinutes = 60,
        theme = "auto",
        languageOverride = null,
        editedAtMs = UNSET_EDITED_AT_MS,
        editCount = 0,
        editTieBreaker = UNSET_TIE_BREAKER,
    )

    /** Everything but the stamp: archive metadata is not a setting. */
    fun SyncedPreferences.hasSameSettings(other: SyncedPreferences) =
        copy(editedAtMs = other.editedAtMs, editCount = other.editCount, editTieBreaker = other.editTieBreaker) == other

    /** The settings in effect: the committed row, or [fallback] (defaults or a first-run draft). */
    fun current(state: RecordState, fallback: SyncedPreferences) = state.syncedPreferences?.takeIf { it.isValid } ?: fallback

    /**
     * Writes [draft] as the committed settings (iOS `upsertSyncedPreferences`).
     * An invalid draft or one with the same settings writes nothing; otherwise
     * the row gets a fresh stamp one edit past the stored one.
     */
    fun commit(state: RecordState, draft: SyncedPreferences, nowMs: Double, tieBreaker: String): RecordState {
        if (!draft.isValid) return state
        val stored = state.syncedPreferences
        if (stored != null && stored.hasSameSettings(draft)) return state
        val editCount = (stored?.editCount ?: maxOf(draft.editCount, 0)) + 1
        return state.copy(syncedPreferences = draft.copy(editedAtMs = nowMs, editCount = editCount, editTieBreaker = tieBreaker))
    }

    /**
     * Applies an edit to the current settings (iOS `applyPreferences`). Returns
     * null when the edit is invalid or changes nothing, so no write happens.
     */
    fun edit(current: SyncedPreferences, change: (SyncedPreferences) -> SyncedPreferences): SyncedPreferences? {
        val next = change(current)
        return next.takeIf { it.isValid && !current.hasSameSettings(it) }
    }

    /** Adds or removes a workday; the last one cannot be removed. */
    fun toggleWorkday(p: SyncedPreferences, day: Int): SyncedPreferences = when {
        day in p.workdays && p.workdays.size <= 1 -> p
        day in p.workdays -> p.copy(workdays = p.workdays - day)
        else -> p.copy(workdays = (p.workdays + day).sorted())
    }

    /** The quick theme button: automatic → light → dark → automatic. */
    fun nextQuickTheme(theme: String) = when (theme) {
        "auto" -> "light"
        "light" -> "dark"
        else -> "auto"
    }

    /**
     * The first-run reminder page's defaults (iOS `applyOnboardingReminderDefaultsIfNeeded`):
     * lunch with both reminders, and a clock-off reminder if none was chosen.
     */
    fun onboardingReminderDefaults(p: SyncedPreferences) = p.copy(
        lunchEnabled = true,
        lunchStartReminderEnabled = true,
        lunchEndReminderEnabled = true,
        notificationMode = if (p.notificationMode == "off") "simple" else p.notificationMode,
    )

    fun startOfDayMs(nowMs: Double, zone: String): Double {
        val z = FoundationCompat.javaZone(zone)
        return Instant.ofEpochMilli(nowMs.toLong()).atZone(z).toLocalDate().atStartOfDay(z).toInstant().toEpochMilli().toDouble()
    }

    /** Monday 00:00 of the week containing [nowMs] (iOS `startOfWeek`, `firstWeekday = 2`). */
    fun startOfWeekMs(nowMs: Double, zone: String): Double {
        val z = FoundationCompat.javaZone(zone)
        val monday = Instant.ofEpochMilli(nowMs.toLong()).atZone(z).toLocalDate().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        return monday.atStartOfDay(z).toInstant().toEpochMilli().toDouble()
    }
}

/**
 * The app's languages and how the system's choice maps onto them (iOS `NativeLocalizer`).
 *
 * `en-GB` is British spelling, also used for other Commonwealth English when the
 * device is followed. `es-MX` is Latin American Spanish (`es-419` on Android).
 * Display names: English (UK), Español (Latinoamérica) — the Spanish variant
 * covers the whole es-419 region, not Mexico alone. Region sets match
 * `scripts/regional-variants.mjs`.
 */
object AppLanguages {
    /** In the order the language picker lists them, with each language's own name. */
    val supported: List<Pair<String, String>> = listOf(
        "en" to "English",
        "en-GB" to "English (UK)",
        "zh-CN" to "简体中文",
        "zh-HK" to "繁體中文（香港）",
        "zh-TW" to "繁體中文（台灣）",
        "ja" to "日本語",
        "ko" to "한국어",
        "de" to "Deutsch",
        "es" to "Español",
        "es-MX" to "Español (Latinoamérica)",
        "fr" to "Français",
        "it" to "Italiano",
        "pt" to "Português",
        "ru" to "Русский",
        "ar" to "العربية",
        "hi-IN" to "हिन्दी",
        "mr-IN" to "मराठी",
        "id" to "Bahasa Indonesia",
        "th" to "ไทย",
        "tr" to "Türkçe",
        "vi" to "Tiếng Việt",
    )

    private val ids = supported.map { it.first }

    /**
     * The first of [preferred] (BCP 47 tags, most preferred first) the app
     * supports: exact match, then Traditional Chinese by region, then any
     * Chinese as Simplified, then English and Spanish by region, then by
     * language prefix; English otherwise. Android's legacy `in` counts as
     * Indonesian.
     *
     * Region tables run before the prefix match. Otherwise `en-AU` hits `en`
     * and `es-AR` hits `es`. Bare `en` and `en-US` / `en-CA` / `en-PH` stay
     * on `en`. Other English regions (GB, IE, AU, NZ, IN, ZA, …) use `en-GB`.
     * `es-419` and its CLDR children, including `es-US`, use `es-MX`. `es-ES`
     * stays on `es`.
     */
    fun resolve(preferred: List<String>): String {
        for (raw in preferred) {
            val tag = raw.replace('_', '-').let { if (it == "in" || it.startsWith("in-")) "id" + it.drop(2) else it }
            val lower = tag.lowercase()
            ids.firstOrNull { it.equals(tag, ignoreCase = true) }?.let { return it }
            if (lower.startsWith("zh-hant-hk") || lower.startsWith("zh-hk")) return "zh-HK"
            if (lower.startsWith("zh-hant") || lower.startsWith("zh-tw")) return "zh-TW"
            if (lower.startsWith("zh")) return "zh-CN"
            if (lower == "en" || lower.startsWith("en-")) return if (isAmericanEnglish(lower)) "en" else "en-GB"
            if (lower == "es" || lower.startsWith("es-")) return if (isLatinAmerican(lower)) "es-MX" else "es"
            ids.firstOrNull { lower.startsWith(it.lowercase() + "-") || it.lowercase().startsWith("$lower-") }?.let { return it }
        }
        return "en"
    }

    /** Catalog code to the BCP 47 tag Android resources and per-app language use. `es-MX` is `es-419`. */
    fun resourceTag(code: String) = when (code) {
        "zh-CN" -> "zh-Hans-CN"
        "zh-HK" -> "zh-Hant-HK"
        "zh-TW" -> "zh-Hant-TW"
        "es-MX" -> "es-419"
        else -> code
    }

    /**
     * Whether [deviceTags] (the configuration's locales, most preferred first)
     * already select the resources for [code]. When this is false the UI and
     * notifications overlay [resourceTag] themselves.
     *
     * `en-AU` does not select `values-en-rGB`. `es-AR` does select
     * `values-b+es+419`, because minSdk 26 follows the es-419 parent.
     */
    fun deviceAlreadyUses(code: String, deviceTags: List<String>): Boolean {
        val raw = deviceTags.firstOrNull()?.replace('_', '-') ?: return code == "en"
        val core = languageTagCore(raw)
        val language = core.substringBefore('-').lowercase().let { if (it == "in") "id" else it }
        val region = regionSubtag(core)
        return when (code) {
            "en-GB" -> language == "en" && region == "GB"
            "en" -> language == "en" && region != "GB"
            "es-MX" -> language == "es" && region in LATIN_AMERICAN_REGIONS
            "es" -> language == "es" && region !in LATIN_AMERICAN_REGIONS
            "zh-CN", "zh-HK", "zh-TW" -> core.equals(resourceTag(code), ignoreCase = true)
            "id" -> language == "id"
            else -> {
                val expected = resourceTag(code)
                core.equals(expected, ignoreCase = true) || (language == expected.lowercase() && !expected.contains('-'))
            }
        }
    }

    private val AMERICAN_ENGLISH_REGIONS = setOf("US", "CA", "PH", "LR", "PR", "GU", "AS", "VI", "UM", "MP")
    private val LATIN_AMERICAN_REGIONS = setOf(
        "419", "MX", "AR", "BO", "BR", "BZ", "CL", "CO", "CR", "CU", "DO", "EC", "GT", "HN",
        "NI", "PA", "PE", "PR", "PY", "SV", "US", "UY", "VE",
    )

    private fun isAmericanEnglish(tag: String): Boolean {
        val region = regionSubtag(tag)
        return region.isEmpty() || region in AMERICAN_ENGLISH_REGIONS
    }

    private fun isLatinAmerican(tag: String): Boolean = regionSubtag(tag) in LATIN_AMERICAN_REGIONS

    /** Language, optional script and optional region. Drops Unicode extensions. */
    private fun languageTagCore(tag: String): String {
        val parts = tag.split('-')
        if (parts.isEmpty() || parts[0].isEmpty()) return ""
        val kept = mutableListOf(parts[0])
        var index = 1
        if (index < parts.size && parts[index].length == 4 && parts[index].all { it.isLetter() }) {
            kept.add(parts[index])
            index++
        }
        if (index < parts.size && isRegion(parts[index])) kept.add(parts[index])
        return kept.joinToString("-")
    }

    private fun regionSubtag(tag: String): String {
        val parts = tag.split('-')
        if (parts.size < 2) return ""
        var index = 1
        if (parts[index].length == 4 && parts[index].all { it.isLetter() }) index++
        if (index >= parts.size || !isRegion(parts[index])) return ""
        return parts[index].uppercase()
    }

    private fun isRegion(part: String) =
        (part.length == 2 && part.all { it.isLetter() }) || (part.length == 3 && part.all { it.isDigit() })

    /** The language the UI renders in: the pinned one, else the system's. */
    fun effective(override: String?, systemPreferred: List<String>) = override?.takeIf { it in ids } ?: resolve(systemPreferred)

    fun isRightToLeft(code: String) = code == "ar"
}

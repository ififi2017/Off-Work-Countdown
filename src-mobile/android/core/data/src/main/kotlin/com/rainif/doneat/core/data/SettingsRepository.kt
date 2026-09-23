package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.settings.PreferencesRules
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.file.Files
import java.nio.file.Path

/**
 * Settings that belong to this device and are never part of the records
 * archive (iOS keeps these in `UserDefaults` only).
 */
data class DeviceSettings(
    val onboardingComplete: Boolean = false,
    /** Shared by the timer and every other money surface; no per-screen reveal. */
    val hideEarnings: Boolean = false,
    val lifeSetupPromptDismissed: Boolean = false,
    val recordsScale: String = "month",
    /** Android asks for POST_NOTIFICATIONS once; after a denial the app points to system settings instead. */
    val notificationPermissionRequested: Boolean = false,
    /** First-run choices not yet committed; survives the process being killed mid-setup. */
    val setupDraft: SyncedPreferences? = null,
    /** Wallpaper colours instead of the brand scheme (Android 12+); a device choice, not synced. */
    val dynamicColor: Boolean = false,
    /** The main tab the app reopens on (iOS remembers it too). */
    val selectedTab: String = "timer",
    /** The first-run page to resume on, with [setupDraft], after any interruption. */
    val setupPage: String? = null,
)

/**
 * One small JSON file. A missing or damaged file reads as the defaults: these
 * are conveniences, and losing one must never block the app.
 */
class DeviceSettingsStore(private val file: Path) {
    private val mutex = Mutex()
    private val _settings = MutableStateFlow(read())
    val settings: StateFlow<DeviceSettings> = _settings.asStateFlow()

    suspend fun update(change: (DeviceSettings) -> DeviceSettings) = mutex.withLock {
        val next = change(_settings.value)
        if (next == _settings.value) return@withLock
        Files.createDirectories(file.parent)
        RecordStore.writeAtomically(file, encode(next).toByteArray())
        _settings.value = next
    }

    private fun read(): DeviceSettings = runCatching {
        if (!Files.exists(file)) return DeviceSettings()
        val o = Json.parseToJsonElement(Files.readString(file)).jsonObject
        fun bool(key: String, default: Boolean) = o[key]?.jsonPrimitive?.booleanOrNull ?: default
        DeviceSettings(
            onboardingComplete = bool("onboardingComplete", false),
            hideEarnings = bool("hideEarnings", false),
            lifeSetupPromptDismissed = bool("lifeSetupPromptDismissed", false),
            recordsScale = o["recordsScale"]?.jsonPrimitive?.contentOrNull ?: "month",
            notificationPermissionRequested = bool("notificationPermissionRequested", false),
            setupDraft = (o["setupDraft"] as? JsonObject)?.let(PreferencesJson::decode)?.takeIf { it.isValid },
            dynamicColor = bool("dynamicColor", false),
            selectedTab = o["selectedTab"]?.jsonPrimitive?.contentOrNull ?: "timer",
            setupPage = o["setupPage"]?.jsonPrimitive?.contentOrNull,
        )
    }.getOrElse { DeviceSettings() }

    private fun encode(s: DeviceSettings) = JsonObject(
        mapOf(
            "onboardingComplete" to JsonPrimitive(s.onboardingComplete),
            "hideEarnings" to JsonPrimitive(s.hideEarnings),
            "lifeSetupPromptDismissed" to JsonPrimitive(s.lifeSetupPromptDismissed),
            "recordsScale" to JsonPrimitive(s.recordsScale),
            "notificationPermissionRequested" to JsonPrimitive(s.notificationPermissionRequested),
            "setupDraft" to (s.setupDraft?.let(PreferencesJson::encode) ?: JsonNull),
            "dynamicColor" to JsonPrimitive(s.dynamicColor),
            "selectedTab" to JsonPrimitive(s.selectedTab),
            "setupPage" to (s.setupPage?.let(::JsonPrimitive) ?: JsonNull),
        ),
    ).toString()
}

/** The draft's own small codec; the archive encodes committed settings through `RecordJson`. */
internal object PreferencesJson {
    fun encode(p: SyncedPreferences) = JsonObject(
        mapOf(
            "startMinutes" to JsonPrimitive(p.startMinutes), "endMinutes" to JsonPrimitive(p.endMinutes),
            "workdays" to JsonArray(p.workdays.map(::JsonPrimitive)),
            "scheduleMode" to JsonPrimitive(p.scheduleMode), "alternatingWeekType" to JsonPrimitive(p.alternatingWeekType),
            "alternatingWeekendWorkday" to JsonPrimitive(p.alternatingWeekendWorkday),
            "alternatingReferenceWeekStartMs" to JsonPrimitive(p.alternatingReferenceWeekStartMs),
            "rotationWorkDays" to JsonPrimitive(p.rotationWorkDays), "rotationRestDays" to JsonPrimitive(p.rotationRestDays),
            "rotationAnchorMs" to JsonPrimitive(p.rotationAnchorMs), "lunchEnabled" to JsonPrimitive(p.lunchEnabled),
            "lunchStartMinutes" to JsonPrimitive(p.lunchStartMinutes), "lunchDurationMinutes" to JsonPrimitive(p.lunchDurationMinutes),
            "recordsTimeZoneIdentifier" to JsonPrimitive(p.recordsTimeZoneIdentifier), "salaryAmount" to JsonPrimitive(p.salaryAmount),
            "salaryEnabled" to JsonPrimitive(p.salaryEnabled), "salaryType" to JsonPrimitive(p.salaryType),
            "monthlyWorkingDays" to JsonPrimitive(p.monthlyWorkingDays), "annualBonusEnabled" to JsonPrimitive(p.annualBonusEnabled),
            "annualBonusMonths" to JsonPrimitive(p.annualBonusMonths), "notificationMode" to JsonPrimitive(p.notificationMode),
            "cycleEndSummaryNotificationEnabled" to JsonPrimitive(p.cycleEndSummaryNotificationEnabled),
            "lunchStartReminderEnabled" to JsonPrimitive(p.lunchStartReminderEnabled),
            "lunchEndReminderEnabled" to JsonPrimitive(p.lunchEndReminderEnabled),
            "microBreakEnabled" to JsonPrimitive(p.microBreakEnabled), "microBreakIntervalMinutes" to JsonPrimitive(p.microBreakIntervalMinutes),
            "theme" to JsonPrimitive(p.theme), "languageOverride" to (p.languageOverride?.let(::JsonPrimitive) ?: JsonNull),
        ),
    )

    fun decode(o: JsonObject): SyncedPreferences? = runCatching {
        fun p(key: String): JsonPrimitive = o.getValue(key).jsonPrimitive
        SyncedPreferences(
            startMinutes = p("startMinutes").content.toInt(), endMinutes = p("endMinutes").content.toInt(),
            workdays = (o.getValue("workdays") as JsonArray).map { it.jsonPrimitive.content.toInt() },
            scheduleMode = p("scheduleMode").content, alternatingWeekType = p("alternatingWeekType").content,
            alternatingWeekendWorkday = p("alternatingWeekendWorkday").content.toInt(),
            alternatingReferenceWeekStartMs = p("alternatingReferenceWeekStartMs").content.toDouble(),
            rotationWorkDays = p("rotationWorkDays").content.toInt(), rotationRestDays = p("rotationRestDays").content.toInt(),
            rotationAnchorMs = p("rotationAnchorMs").content.toDouble(), lunchEnabled = p("lunchEnabled").content.toBooleanStrict(),
            lunchStartMinutes = p("lunchStartMinutes").content.toInt(), lunchDurationMinutes = p("lunchDurationMinutes").content.toInt(),
            recordsTimeZoneIdentifier = p("recordsTimeZoneIdentifier").content, salaryAmount = p("salaryAmount").content,
            salaryEnabled = p("salaryEnabled").content.toBooleanStrict(), salaryType = p("salaryType").content,
            monthlyWorkingDays = p("monthlyWorkingDays").content.toDouble(), annualBonusEnabled = p("annualBonusEnabled").content.toBooleanStrict(),
            annualBonusMonths = p("annualBonusMonths").content.toDouble(), notificationMode = p("notificationMode").content,
            cycleEndSummaryNotificationEnabled = p("cycleEndSummaryNotificationEnabled").content.toBooleanStrict(),
            lunchStartReminderEnabled = p("lunchStartReminderEnabled").content.toBooleanStrict(),
            lunchEndReminderEnabled = p("lunchEndReminderEnabled").content.toBooleanStrict(),
            microBreakEnabled = p("microBreakEnabled").content.toBooleanStrict(),
            microBreakIntervalMinutes = p("microBreakIntervalMinutes").content.toInt(),
            theme = p("theme").content, languageOverride = (o["languageOverride"] as? JsonPrimitive)?.contentOrNull,
            editedAtMs = PreferencesRules.UNSET_EDITED_AT_MS, editCount = 0, editTieBreaker = PreferencesRules.UNSET_TIE_BREAKER,
        )
    }.getOrNull()
}

/**
 * The settings the app runs on, from two homes (iOS `PreferencesStore`):
 *
 * - Once set up, the archive's `syncedPreferences`. Each edit is one stamped
 *   archive write, and only when the settings actually change.
 * - Before first-run setup completes, a draft on this device. Nothing reaches
 *   the archive until [completeSetup], so a fresh install never commits its
 *   defaults as a newer edit.
 *
 * An archive that already holds settings (restored by Android backup or device
 * transfer) counts as set up: the app opens on its main screen, not the welcome.
 */
class SettingsRepository(
    private val records: RecordStore,
    private val deviceStore: DeviceSettingsStore,
    scope: CoroutineScope,
    private val nowMs: () -> Double,
    private val systemZone: () -> String,
    private val newId: () -> String,
) {
    val device: StateFlow<DeviceSettings> = deviceStore.settings

    val isSetUp: StateFlow<Boolean> = combine(records.state, device) { state, local ->
        local.onboardingComplete || state.syncedPreferences != null
    }.stateIn(scope, SharingStarted.Eagerly, device.value.onboardingComplete || records.state.value.syncedPreferences != null)

    val preferences: StateFlow<SyncedPreferences> = combine(records.state, device) { state, local ->
        PreferencesRules.current(state, local.setupDraft ?: fallback())
    }.stateIn(scope, SharingStarted.Eagerly, PreferencesRules.current(records.state.value, device.value.setupDraft ?: fallback()))

    private fun fallback() = PreferencesRules.defaults(systemZone(), nowMs())

    /**
     * Applies [change] to the current settings. Returns false when it changed
     * nothing, was invalid, or the archive refused the write (the caller keeps
     * showing the old value).
     */
    suspend fun edit(change: (SyncedPreferences) -> SyncedPreferences): Boolean {
        // Read the sources, not the derived flow, which may not have caught up yet.
        if (device.value.onboardingComplete || records.state.value.syncedPreferences != null) {
            val result = records.update { state ->
                val current = PreferencesRules.current(state, fallback())
                val next = PreferencesRules.edit(current, change) ?: return@update state to false
                PreferencesRules.commit(state, next, nowMs(), newId()) to true
            }
            return (result as? WriteResult.Saved)?.value == true
        }
        var changed = false
        deviceStore.update { local ->
            val current = local.setupDraft ?: fallback()
            val next = PreferencesRules.edit(current, change)
            changed = next != null
            if (next == null) local else local.copy(setupDraft = next)
        }
        return changed
    }

    /** Commits the first-run choices in one archive write, then marks setup done. */
    suspend fun completeSetup(): Boolean {
        val draft = device.value.setupDraft ?: fallback()
        val result = records.update { state -> PreferencesRules.commit(state, draft, nowMs(), newId()) to Unit }
        if (result !is WriteResult.Saved) return false
        deviceStore.update { it.copy(onboardingComplete = true, setupDraft = null, setupPage = null) }
        return true
    }

    /**
     * After a backup was restored onto this device: when it carried settings,
     * setup is done and the draft is dropped; otherwise setup continues with
     * the draft, and the restored records are kept.
     */
    suspend fun finishRestore(hasSettings: Boolean) {
        if (hasSettings) deviceStore.update { it.copy(onboardingComplete = true, setupDraft = null, setupPage = null) }
    }

    suspend fun updateDevice(change: (DeviceSettings) -> DeviceSettings) = deviceStore.update(change)
}

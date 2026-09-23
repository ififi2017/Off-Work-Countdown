package com.rainif.doneat.core.domain.settings

import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.settings.PreferencesRules.hasSameSettings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

class PreferencesRulesTest {
    private val zone = "Asia/Shanghai"
    /** Wednesday 2026-09-23 14:30 in Shanghai. */
    private val now = ZonedDateTime.of(2026, 9, 23, 14, 30, 0, 0, ZoneId.of(zone)).toInstant().toEpochMilli().toDouble()
    private val defaults = PreferencesRules.defaults(zone, now)

    @Test fun defaultsMatchIosFirstLaunch() {
        assertTrue(defaults.isValid)
        assertEquals(listOf(540, 1020), listOf(defaults.startMinutes, defaults.endMinutes))
        assertEquals(listOf(1, 2, 3, 4, 5), defaults.workdays)
        assertEquals("off", defaults.notificationMode)
        assertEquals(zone, defaults.recordsTimeZoneIdentifier)
        // Monday 2026-09-21 and today, both at 00:00 in the records zone.
        assertEquals(ZonedDateTime.of(2026, 9, 21, 0, 0, 0, 0, ZoneId.of(zone)).toInstant().toEpochMilli().toDouble(), defaults.alternatingReferenceWeekStartMs, 0.0)
        assertEquals(ZonedDateTime.of(2026, 9, 23, 0, 0, 0, 0, ZoneId.of(zone)).toInstant().toEpochMilli().toDouble(), defaults.rotationAnchorMs, 0.0)
        assertEquals(0, defaults.editCount)
    }

    @Test fun readingDefaultsNeverWritesTheArchive() {
        val empty = RecordState()
        assertSame(defaults, PreferencesRules.current(empty, defaults))
        assertNull(empty.syncedPreferences)
    }

    @Test fun aCommitStampsOnlyARealChange() {
        val first = PreferencesRules.commit(RecordState(), defaults, now, "T1")
        val row = first.syncedPreferences!!
        assertEquals(1, row.editCount)
        assertEquals(now, row.editedAtMs, 0.0)
        assertEquals("T1", row.editTieBreaker)
        assertSame("same settings, new stamp: nothing written", first, PreferencesRules.commit(first, row.copy(editCount = 9, editTieBreaker = "X"), now + 1, "T2"))
        val next = PreferencesRules.commit(first, row.copy(theme = "dark"), now + 1, "T2")
        assertEquals(2, next.syncedPreferences!!.editCount)
        assertSame("invalid drafts never reach the archive", first, PreferencesRules.commit(first, row.copy(startMinutes = 2_000), now, "T3"))
    }

    @Test fun anEditThatChangesNothingOrBreaksValidityIsDropped() {
        assertNull(PreferencesRules.edit(defaults) { it })
        assertNull(PreferencesRules.edit(defaults) { it.copy(microBreakIntervalMinutes = 0) })
        assertEquals("dark", PreferencesRules.edit(defaults) { it.copy(theme = "dark") }!!.theme)
        assertTrue(defaults.hasSameSettings(defaults.copy(editCount = 5)))
    }

    @Test fun theLastWorkdayCannotBeRemoved() {
        val one = defaults.copy(workdays = listOf(3))
        assertSame(one, PreferencesRules.toggleWorkday(one, 3))
        assertEquals(listOf(0, 3), PreferencesRules.toggleWorkday(one, 0).workdays)
        assertEquals(listOf(1, 2, 4, 5), PreferencesRules.toggleWorkday(defaults, 3).workdays)
    }

    @Test fun onboardingReminderDefaultsKeepAChosenMode() {
        val applied = PreferencesRules.onboardingReminderDefaults(defaults)
        assertTrue(applied.lunchEnabled && applied.lunchStartReminderEnabled && applied.lunchEndReminderEnabled)
        assertEquals("simple", applied.notificationMode)
        assertEquals("milestones", PreferencesRules.onboardingReminderDefaults(defaults.copy(notificationMode = "milestones")).notificationMode)
        assertEquals(listOf("light", "dark", "auto"), listOf("auto", "light", "dark").map(PreferencesRules::nextQuickTheme))
    }

    @Test fun systemLanguagesMapLikeIos() {
        val cases = mapOf(
            listOf("zh-Hans-CN") to "zh-CN",
            listOf("zh-Hant-HK") to "zh-HK",
            listOf("zh-Hant-TW") to "zh-TW",
            listOf("zh-Hant-MO") to "zh-TW",
            listOf("zh-TW") to "zh-TW",
            listOf("zh-SG") to "zh-CN",
            listOf("in-ID") to "id",
            listOf("id") to "id",
            listOf("hi") to "hi-IN",
            listOf("mr-IN") to "mr-IN",
            listOf("pt-BR") to "pt",
            listOf("de-AT") to "de",
            listOf("sv-SE", "fr-CA") to "fr",
            listOf("sv-SE") to "en",
            emptyList<String>() to "en",
        )
        for ((preferred, expected) in cases) assertEquals(preferred.toString(), expected, AppLanguages.resolve(preferred))
        assertEquals("ja", AppLanguages.effective("ja", listOf("de")))
        assertEquals("de", AppLanguages.effective("xx", listOf("de")))
        assertEquals(19, AppLanguages.supported.size)
    }
}

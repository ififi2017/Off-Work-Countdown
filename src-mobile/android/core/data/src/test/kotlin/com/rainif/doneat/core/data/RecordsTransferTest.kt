package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.settings.PreferencesRules
import com.rainif.doneat.core.domain.salary.SalaryRules
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files
import java.util.UUID

@OptIn(ExperimentalCoroutinesApi::class)
class RecordsTransferTest {
    @get:Rule val folder = TemporaryFolder()
    private val now = 1_790_000_000_000.0
    private fun archive(name: String) = File(System.getProperty("owc.syntheticArchives"), name).readBytes()

    private suspend fun TestScope.store(): RecordStore =
        RecordStore(folder.root.toPath().resolve("records.json"), { now }, { "Asia/Shanghai" }, UnconfinedTestDispatcher(testScheduler)).also { it.load() }

    @Test fun everyKnownVersionPreviewsAndImports() = runTest {
        for (version in 1..6) {
            val bytes = archive("v$version.json")
            val preview = RecordsTransfer.preview(bytes, RecordState())
            assertTrue("v$version: $preview", preview is ImportPreview.Ready)
            val records = store()
            assertNotNull("v$version commits", RecordsTransfer.commit(records, bytes))
            assertTrue("v$version wrote something", records.state.value != RecordState())
            RecordsTransfer.deleteRecords(records)
        }
    }

    @Test fun aNewerOrBrokenFileIsRefusedWithItsReason() {
        assertSame(ImportPreview.UnsupportedVersion, RecordsTransfer.preview(archive("illegal-v7.json"), RecordState()))
        for (name in listOf("illegal-not-json.txt", "illegal-v0.json")) {
            assertSame(name, ImportPreview.Invalid, RecordsTransfer.preview(archive(name), RecordState()))
        }
        assertSame(ImportPreview.TooLarge, RecordsTransfer.preview(ByteArray((RecordsTransfer.MAX_BYTES + 1).toInt()), RecordState()))
    }

    @Test fun invalidRowsAreCountedSeparatelyFromUnreadableDocuments() = runTest {
        val root = Json.parseToJsonElement(archive("v6.json").decodeToString()).jsonObject
        val rows = root.getValue("dayOverrides").jsonArray
        val malformed = JsonObject(root + ("dayOverrides" to JsonArray(rows.mapIndexed { index, row ->
            if (index == 0) JsonObject(row.jsonObject + ("dayKey" to JsonPrimitive("2026-99-99"))) else row
        }))).toString().toByteArray()
        val preview = RecordsTransfer.preview(malformed, RecordState()) as ImportPreview.Ready
        assertEquals(1, preview.rejected)
        assertTrue(preview.added > 0)
        val records = store()
        val original = records.state.value
        for (bytes in listOf("[]".toByteArray(), "{broken".toByteArray(), archive("illegal-v7.json"))) {
            assertTrue(RecordsTransfer.preview(bytes, original) !is ImportPreview.Ready)
            assertNull(RecordsTransfer.commit(records, bytes))
            assertEquals(original, records.state.value)
        }
    }

    @Test fun cancellingAConflictedImportLeavesTheLocalFileUntouched() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val local = records.state.value
        val incoming = RecordsTransfer.export(local.copy(periods = local.periods.map { it.copy(label = "Incoming") }), true, now, "Asia/Shanghai").toByteArray()
        val before = folder.root.toPath().resolve("records.json").toFile().readBytes()
        val preview = RecordsTransfer.preview(incoming, local) as ImportPreview.Ready
        assertEquals(1, preview.conflicts)
        // Cancel is a UI decision: no commit is called after preview.
        assertEquals(local, records.state.value)
        assertTrue(before.contentEquals(folder.root.toPath().resolve("records.json").toFile().readBytes()))
    }

    @Test fun importingTheSameBackupTwiceAddsNothingTheSecondTime() = runTest {
        val records = store()
        val bytes = archive("v6.json")
        RecordsTransfer.commit(records, bytes)
        val once = records.state.value
        val second = RecordsTransfer.preview(bytes, once) as ImportPreview.Ready
        assertEquals(0, second.added)
        assertEquals(0, second.conflicts)
        RecordsTransfer.commit(records, bytes)
        assertEquals(once, records.state.value)
    }

    @Test fun aFailedImportLeavesTheArchiveAsItWas() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val before = records.state.value
        assertNull(RecordsTransfer.commit(records, archive("illegal-v7.json")))
        assertEquals(before, records.state.value)
    }

    @Test fun anExportReadsBackAsTheSameRecords() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val exported = RecordsTransfer.export(records.state.value, includeLifeProfile = true, now, "Asia/Shanghai")
        val (roundTrip, _) = RecordJson.apply(RecordJson.decode(exported), RecordState(), RecordJson.ImportMode.SKIP_ERASED)
        val original = records.state.value
        assertEquals(original.periods, roundTrip.periods)
        assertEquals(original.snapshots, roundTrip.snapshots)
        assertEquals(original.overrides, roundTrip.overrides)
        assertEquals(original.observations, roundTrip.observations)
        assertEquals(original.lifeProfile, roundTrip.lifeProfile)
    }

    @Test fun theLifeProfileCanBeLeftOut() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val withLife = RecordJson.apply(RecordJson.decode(RecordsTransfer.export(records.state.value, true, now, "UTC")), RecordState(), RecordJson.ImportMode.SKIP_ERASED).first
        val withoutLife = RecordJson.apply(RecordJson.decode(RecordsTransfer.export(records.state.value, false, now, "UTC")), RecordState(), RecordJson.ImportMode.SKIP_ERASED).first
        assertNotNull("the fixture carries a Life profile", withLife.lifeProfile)
        assertNull(withoutLife.lifeProfile)
        assertEquals(withLife.periods, withoutLife.periods)
    }

    @Test fun exportsOnlySchemaSixRecordsEvenAfterImportingUnknownPrivateFields() = runTest {
        val raw = Json.parseToJsonElement(archive("v6.json").decodeToString()).jsonObject
        val tainted = JsonObject(raw + mapOf(
            "purchaseToken" to JsonPrimitive("secret-token"),
            "oauthToken" to JsonPrimitive("secret-oauth"),
            "notificationPermission" to JsonPrimitive(true),
            "syncState" to JsonPrimitive("secret-sync"),
        )).toString().toByteArray()
        val records = store()
        assertNotNull(RecordsTransfer.commit(records, tainted))
        for (includeLife in listOf(true, false)) {
            val exported = RecordsTransfer.export(records.state.value, includeLife, now, "Asia/Shanghai")
            val keys = Json.parseToJsonElement(exported).jsonObject.keys
            assertTrue(keys.all { it in setOf(
                "schemaVersion", "exportedAtMs", "timeZoneIdentifier", "calendarIdentifier", "careerPeriods",
                "scheduleSnapshots", "calendarExceptions", "dayOverrides", "workObservations", "lifeProfile",
                "focusTasks", "focusSessions", "focusPlanningConfiguration", "syncedPreferences", "recordsStartedOn",
                "extendedSchedule", "rosterDays",
            ) })
            assertTrue("no imported private metadata", listOf("secret-token", "secret-oauth", "secret-sync").none { it in exported })
            assertEquals(includeLife, "lifeProfile" in keys)
            assertEquals(6, Json.parseToJsonElement(exported).jsonObject.getValue("schemaVersion").toString().toInt())
        }
    }

    @Test fun invalidSalaryTextInARecoveredArchiveDoesNotBecomeAnAmount() = runTest {
        val root = Json.parseToJsonElement(archive("v6.json").decodeToString()).jsonObject
        val preferences = root.getValue("syncedPreferences").jsonObject
        for (amount in listOf("1,5", "NaN", "-1", "1e309")) {
            Files.deleteIfExists(folder.root.toPath().resolve("records.json"))
            val document = JsonObject(root + ("syncedPreferences" to JsonObject(preferences + ("salaryAmount" to JsonPrimitive(amount))))).toString().toByteArray()
            val records = store()
            assertNotNull(amount, RecordsTransfer.commit(records, document))
            val reopened = store()
            val saved = reopened.state.value.syncedPreferences!!
            assertEquals(amount, saved.salaryAmount)
            assertNull(amount, SalaryRules.dailySalary(SalarySettings(saved.salaryAmount, SalaryType.fromRaw(saved.salaryType), saved.monthlyWorkingDays, saved.annualBonusMonths)))
        }
    }

    @Test fun deletingRecordsKeepsTheSettings() = runTest {
        val records = store()
        val prefs = PreferencesRules.defaults("Asia/Shanghai", now)
        records.update { PreferencesRules.commit(it, prefs, now, "00000000-0000-0000-0000-000000000001") to Unit }
        RecordsTransfer.commit(records, archive("v6.json"))
        assertTrue(RecordsTransfer.deleteRecords(records))
        assertTrue(records.state.value.periods.isEmpty())
        assertTrue(records.state.value.observations.isEmpty())
        assertNotNull(records.state.value.syncedPreferences)
    }

    @Test fun importConflictsSurviveReloadAndCanKeepOrReplaceTheLocalCopy() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val local = records.state.value.periods.first()
        val changed = records.state.value.copy(periods = records.state.value.periods.map {
            if (it.id == local.id) it.copy(label = "From another device", editCount = it.editCount + 1) else it
        })
        val incoming = RecordsTransfer.export(changed, true, now, "Asia/Shanghai").toByteArray()
        val preview = RecordsTransfer.preview(incoming, records.state.value) as ImportPreview.Ready
        assertEquals(1, preview.conflicts)
        RecordsTransfer.commit(records, incoming)
        assertEquals(1, records.state.value.importConflicts.size)
        records.load()
        val conflict = records.state.value.importConflicts.single()
        val review = RecordsConflictResolution.review(records.state.value, conflict)!!
        assertTrue(review.fields.any { it.name == "label" })
        assertTrue(RecordsConflictResolution.resolve(records, conflict, review.current, RecordsConflictResolution.Choice.KEEP_CURRENT, now + 1) { "00000000-0000-0000-0000-000000000002" })
        assertEquals(local.label, records.state.value.periods.first { it.id == local.id }.label)
        RecordsTransfer.commit(records, incoming)
        val again = records.state.value.importConflicts.single()
        assertTrue(RecordsConflictResolution.resolve(records, again, RecordsConflictResolution.review(records.state.value, again)!!.current, RecordsConflictResolution.Choice.USE_IMPORTED, now + 2) { "00000000-0000-0000-0000-000000000003" })
        assertEquals("From another device", records.state.value.periods.first { it.id == local.id }.label)
        assertTrue(records.state.value.importConflicts.isEmpty())
    }

    @Test fun aConflictChoiceCannotOverwriteAnEditMadeAfterReview() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val state = records.state.value
        val changed = state.copy(periods = state.periods.map { it.copy(label = "Imported") })
        RecordsTransfer.commit(records, RecordsTransfer.export(changed, true, now, "UTC").toByteArray())
        val pending = records.state.value.importConflicts.single()
        val review = RecordsConflictResolution.review(records.state.value, pending)!!
        records.update { current -> current.copy(periods = current.periods.map { it.copy(label = "New local edit", editCount = it.editCount + 1) }) to Unit }
        assertTrue(!RecordsConflictResolution.resolve(records, pending, review.current, RecordsConflictResolution.Choice.USE_IMPORTED, now + 1) { "00000000-0000-0000-0000-000000000005" })
        assertEquals("New local edit", records.state.value.periods.single().label)
        assertEquals(pending.id, records.state.value.importConflicts.single().id)
        val refreshed = RecordsConflictResolution.review(records.state.value, pending)!!
        assertTrue(RecordsConflictResolution.resolve(records, pending, refreshed.current, RecordsConflictResolution.Choice.KEEP_CURRENT, now + 2) { "00000000-0000-0000-0000-000000000006" })
        assertTrue(records.state.value.periods.single().editCount > refreshed.current.let { (it as com.rainif.doneat.core.domain.records.CareerPeriod).editCount })
    }

    @Test fun aConflictChoiceCannotResolveAReplacementCandidate() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val local = records.state.value
        val candidate = local.copy(periods = local.periods.map { it.copy(label = "First import") })
        RecordsTransfer.commit(records, RecordsTransfer.export(candidate, true, now, "UTC").toByteArray())
        val old = records.state.value.importConflicts.single()
        val review = RecordsConflictResolution.review(records.state.value, old)!!
        records.update { current -> current.copy(importConflicts = emptyList()) to Unit }
        val replacement = local.copy(periods = local.periods.map { it.copy(label = "Second import") })
        RecordsTransfer.commit(records, RecordsTransfer.export(replacement, true, now + 1, "UTC").toByteArray())
        assertTrue(records.state.value.importConflicts.single().id != old.id)
        assertTrue(!RecordsConflictResolution.resolve(records, old, review.current, RecordsConflictResolution.Choice.USE_IMPORTED, now + 2) { "00000000-0000-0000-0000-000000000007" })
        assertEquals(local.periods.single().label, records.state.value.periods.single().label)
    }

    @Test fun importedPreferencesCannotSwitchTheRecordsZoneOutsideMigration() = runTest {
        val records = store()
        val prefs = PreferencesRules.defaults("Asia/Shanghai", now)
        records.update { PreferencesRules.commit(it, prefs, now, "00000000-0000-0000-0000-000000000001") to Unit }
        val changed = records.state.value.copy(syncedPreferences = records.state.value.syncedPreferences!!.copy(recordsTimeZoneIdentifier = "UTC"))
        RecordsTransfer.commit(records, RecordsTransfer.export(changed, true, now, "UTC").toByteArray())
        val pending = records.state.value.importConflicts.single()
        val review = RecordsConflictResolution.review(records.state.value, pending)!!
        assertTrue(!review.canUseIncoming)
        assertTrue(!RecordsConflictResolution.resolve(records, pending, review.current, RecordsConflictResolution.Choice.USE_IMPORTED, now + 1) { "00000000-0000-0000-0000-000000000008" })
        assertEquals("Asia/Shanghai", records.state.value.syncedPreferences?.recordsTimeZoneIdentifier)
        assertTrue(RecordsConflictResolution.resolve(records, pending, review.current, RecordsConflictResolution.Choice.KEEP_CURRENT, now + 2) { "00000000-0000-0000-0000-000000000009" })
    }

    @Test fun migrationMovesCivilAnchorsAndObservationsInOneArchiveWrite() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val prefs = PreferencesRules.defaults("Asia/Shanghai", now)
        records.update { PreferencesRules.commit(it, prefs, now, "00000000-0000-0000-0000-000000000001") to Unit }
        val before = records.state.value
        val migrated = RecordsTimeZoneMigration.migrate(before, "UTC", now + 1) { "00000000-0000-0000-0000-000000000004" }
        assertNotNull(migrated)
        val write = records.update { migrated!! to Unit }
        assertTrue(write is WriteResult.Saved)
        records.load()
        assertEquals("UTC", records.state.value.syncedPreferences?.recordsTimeZoneIdentifier)
        assertEquals(before.periods.map { it.startsOn }, records.state.value.periods.map { it.startsOn })
        assertEquals(before.overrides.map { it.dayKey }, records.state.value.overrides.map { it.dayKey })
        assertEquals(before.observations.size, records.state.value.observations.size)
        assertTrue(before.observations.zip(records.state.value.observations).all { (old, newer) ->
            old.timeZoneIdentifier == "UTC" || (newer.eventID == RecordsTimeZoneMigration.migratedObservationId(old.eventID, "UTC") &&
                records.state.value.erased.any { it.logicalKey == old.eventID })
        })
    }

    @Test fun failedDeleteKeepsRecordsAndReportsFailure() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val before = records.state.value
        val file = folder.root.toPath().resolve("records.json")
        val failing = RecordStore(file, { now }, { "Asia/Shanghai" }, UnconfinedTestDispatcher(testScheduler)) { _, _ ->
            throw java.io.IOException("disk full")
        }
        failing.load()
        assertTrue(!RecordsTransfer.deleteRecords(failing))
        assertEquals(before, failing.state.value)
    }

    @Test fun exportAllEntitiesForSwiftRoundTrip() {
        val output = System.getProperty("owc.roundtripOutput") ?: return
        val source = RecordJson.decode(archive("v6.json").toString(Charsets.UTF_8))
        val (state, report) = RecordJson.apply(source, RecordState(), RecordJson.ImportMode.SKIP_ERASED)
        assertTrue(report.rejected.isEmpty())
        File(output).writeText(RecordsTransfer.export(state, true, source.exportedAtMs, source.timeZoneIdentifier))
    }

    @Test fun largeDistinctAndRepeatedIdentitiesMergeWithinTheFileCeiling() = runTest {
        val seed = RecordJson.apply(RecordJson.decode(archive("v6.json").toString(Charsets.UTF_8)), RecordState(), RecordJson.ImportMode.SKIP_ERASED).first
        val task = seed.focusTasks.single()
        val period = seed.periods.single()
        val many = seed.copy(
            focusTasks = (0..10_000).map { index -> task.copy(id = UUID.nameUUIDFromBytes("task-$index".toByteArray()).toString()) },
            periods = listOf(period) + (0 until 5_000).map { period.copy(label = "Repeated $it") },
        )
        val bytes = RecordsTransfer.export(many, true, now, "UTC").toByteArray()
        assertTrue(bytes.size < RecordsTransfer.MAX_BYTES)
        val preview = RecordsTransfer.preview(bytes, RecordState()) as ImportPreview.Ready
        assertTrue(preview.added >= 10_001)
        assertEquals(1, preview.conflicts)
        val records = store()
        assertTrue("preview never creates a partial archive", !Files.exists(folder.root.toPath().resolve("records.json")))
        assertNotNull(RecordsTransfer.commit(records, bytes))
        assertEquals(10_001, records.state.value.focusTasks.size)
        assertEquals(1, records.state.value.periods.size)
        assertEquals(1, records.state.value.importConflicts.size)
        val reopened = store()
        assertEquals(records.state.value, reopened.state.value)
    }

    @Test fun hostileBackupDepthAndNumbersFailBeforeChangingRecords() = runTest {
        val records = store()
        val original = archive("v6.json").toString(Charsets.UTF_8).trimEnd().dropLast(1)
        val deep = (original + ",\"unknown\":" + "[".repeat(129) + "0" + "]".repeat(129) + "}").toByteArray()
        val wide = (original + ",\"unknown\":[" + "0,".repeat(100_000) + "0]}").toByteArray()
        val duplicates = (original + ",\"unknown\":[" + "{\"id\":\"same\"},".repeat(100_000) + "{}]}").toByteArray()
        val huge = original.replace(Regex("\"exportedAtMs\"\\s*:\\s*[0-9]+"), "\"exportedAtMs\":1e999") + "}"
        for (bytes in listOf(deep, wide, duplicates, huge.toByteArray())) {
            assertSame(ImportPreview.Invalid, RecordsTransfer.preview(bytes, records.state.value))
            assertNull(RecordsTransfer.commit(records, bytes))
            assertSame(RestorePreview.Unreadable, FirstRunRestore.preview(bytes, now))
            assertEquals(RecordState(), records.state.value)
        }
    }
}

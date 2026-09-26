package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.CalendarEffect
import com.rainif.doneat.core.domain.records.DayEditDraft
import com.rainif.doneat.core.domain.records.DayOverrideKind
import com.rainif.doneat.core.domain.records.DayRecordWrite
import com.rainif.doneat.core.domain.records.RecordEditContext
import com.rainif.doneat.core.domain.records.SnapshotHours
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException
import java.nio.file.Files

@OptIn(ExperimentalCoroutinesApi::class)
class RecordsEditingTest {
    @get:Rule val folder = TemporaryFolder()
    private val now = 1_789_000_000_000.0
    private var ids = 0
    private val hours = SnapshotHours("09:00", "18:00", listOf(1, 2, 3, 4, 5), "classic", breakStartTime = "12:00", breakDurationMinutes = 60)

    private suspend fun TestScope.store() =
        RecordStore(folder.root.toPath().resolve("records.json"), { now }, { "Asia/Shanghai" }, UnconfinedTestDispatcher(testScheduler)).also { it.load() }

    private fun context(canEdit: Boolean = true) = RecordEditContext(
        now, "Asia/Shanghai", canEdit, HolidayCalendar.EMPTY, { hours }, { "00000000-0000-4000-8000-%012d".format(++ids) },
    )

    private fun submission(write: DayRecordWrite, start: Int = 10 * 60, end: Int = 16 * 60) = DayEditDraft.Submission("2026-09-14", write, start, end, 1)

    @Test fun customHoursSeedTheArchiveAndLandInOneWrite() = runTest {
        val records = store()
        assertTrue(RecordsEditing.save(records, submission(DayRecordWrite.CUSTOM_HOURS), context()))
        val state = records.state.value
        assertEquals(1, state.periods.size)
        val override = state.overrides.single()
        assertEquals(DayOverrideKind.CUSTOM_SEGMENTS, override.kind)
        // The lunch gap inside the new hours is kept, not pressed into one stretch.
        assertEquals(2, override.segments.size)
    }

    @Test fun aRestDayClearsLeftoverHoursAndClearingUndoesBoth() = runTest {
        val records = store()
        RecordsEditing.save(records, submission(DayRecordWrite.CUSTOM_HOURS), context())
        assertTrue(RecordsEditing.save(records, submission(DayRecordWrite.REST), context()))
        assertEquals(DayOverrideKind.CLEARED, records.state.value.overrides.single().kind)
        assertEquals(CalendarEffect.REST, records.state.value.exceptions.single().effect)
        assertTrue(RecordsEditing.save(records, submission(DayRecordWrite.CLEAR), context()))
        assertTrue(records.state.value.exceptions.single().isCleared)
    }

    @Test fun aRefusedEditLeavesTheArchiveUntouched() = runTest {
        val records = store()
        val before = records.state.value
        assertFalse(RecordsEditing.save(records, submission(DayRecordWrite.LEAVE), context(canEdit = false)))
        assertFalse(RecordsEditing.save(records, submission(DayRecordWrite.LEAVE).copy(dayKey = "2026-9-14"), context()))
        assertEquals(before, records.state.value)
    }

    @Test fun aFailedDayEditKeepsBothLayersAndTheDraftAfterReopen() = runTest {
        val records = store()
        assertTrue(RecordsEditing.save(records, submission(DayRecordWrite.CUSTOM_HOURS), context()))
        val before = records.state.value
        val file = folder.root.toPath().resolve("records.json")
        val bytes = Files.readAllBytes(file)
        val draft = submission(DayRecordWrite.REST)
        val failing = RecordStore(file, { now }, { "Asia/Shanghai" }, UnconfinedTestDispatcher(testScheduler)) { _, _ ->
            throw IOException("No space left on device")
        }
        failing.load()
        assertFalse(RecordsEditing.save(failing, draft, context()))
        assertEquals(before.overrides, failing.state.value.overrides)
        assertEquals(before.exceptions, failing.state.value.exceptions)
        assertTrue(bytes.contentEquals(Files.readAllBytes(file)))
        val reopened = store()
        assertEquals(before, reopened.state.value)
    }
}

package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Restoring erased rows (`RESTORE_ERASED`) gives UUID identities new ids and
 * carries every reference with them (plan 02 §6.3): a snapshot keeps pointing
 * at its period, an observation at its snapshot, a session at its task.
 */
class RestoreErasedRemapTest {
    private val now = 1_790_000_000_000.0
    private fun archive(name: String) = File(System.getProperty("owc.syntheticArchives"), name).readBytes()

    @Test fun restoredIdentitiesCarryTheirReferences() {
        val original = RecordJson.apply(RecordJson.decode(archive("v6.json").decodeToString()), RecordState(), RecordJson.ImportMode.SKIP_ERASED).first
        assertTrue("the fixture has periods, snapshots and observations", original.periods.isNotEmpty() && original.snapshots.isNotEmpty() && original.observations.isNotEmpty())
        val backup = RecordsTransfer.export(original, includeLifeProfile = true, now, "Asia/Shanghai")

        var erased = original
        original.periods.forEach { erased = RecordJson.erase(erased, RecordEntityType.CAREER_PERIOD, it.id, now) }
        original.snapshots.forEach { erased = RecordJson.erase(erased, RecordEntityType.SCHEDULE_SNAPSHOT, it.id, now) }
        original.observations.forEach { erased = RecordJson.erase(erased, RecordEntityType.WORK_OBSERVATION, it.eventID, now) }
        original.focusTasks.forEach { erased = RecordJson.erase(erased, RecordEntityType.FOCUS_TASK, it.id, now) }

        var n = 0
        val (restored, report) = RecordJson.apply(RecordJson.decode(backup), erased, RecordJson.ImportMode.RESTORE_ERASED) { "00000000-0000-4000-8000-%012d".format(++n) }

        assertEquals(original.periods.size, restored.periods.size)
        assertTrue("restored under new ids", restored.periods.none { p -> original.periods.any { it.id == p.id } })
        val periodIds = restored.periods.map { it.id }.toSet()
        assertTrue("every snapshot points at a restored period", restored.snapshots.all { it.periodID in periodIds })
        val snapshotIds = restored.snapshots.map { it.id }.toSet()
        assertTrue("every observation points at a restored snapshot", restored.observations.all { it.scheduleSnapshotID in snapshotIds || original.snapshots.none { s -> s.id == it.scheduleSnapshotID } })
        val taskIds = restored.focusTasks.map { it.id }.toSet()
        assertTrue("sessions follow their tasks", restored.focusSessions.all { s -> s.taskID == null || s.taskID in taskIds || original.focusTasks.none { it.id == s.taskID } })
        assertTrue(report.restored.values.sum() > 0)

        // The default import never brings an erased identity back.
        val skipped = RecordJson.apply(RecordJson.decode(backup), erased, RecordJson.ImportMode.SKIP_ERASED).first
        assertTrue(skipped.periods.isEmpty())
        assertFalse(skipped.observations.any { o -> original.observations.any { it.eventID == o.eventID } })
    }
}

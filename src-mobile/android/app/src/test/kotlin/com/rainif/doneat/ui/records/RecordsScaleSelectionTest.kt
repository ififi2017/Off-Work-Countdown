package com.rainif.doneat.ui.records

import com.rainif.doneat.core.domain.records.RecordsScale
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordsScaleSelectionTest {
    @Test fun freeMonthAppearsBeforeTheDeviceWriteFinishes() = runBlocking {
        val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val allowWrite = CompletableDeferred<Unit>()
        val saved = CompletableDeferred<String>()
        var shown = RecordsScale.LIFE.raw

        assertTrue(RecordsScale.LIFE.requiresPlus)
        assertFalse(RecordsScale.MONTH.requiresPlus)
        switchRecordsScale(RecordsScale.MONTH, { shown = it }, appScope) { raw ->
            allowWrite.await()
            saved.complete(raw)
        }

        assertEquals("month", shown)
        assertFalse(saved.isCompleted)
        allowWrite.complete(Unit)
        assertEquals("month", saved.await())
        appScope.cancel()
    }
}

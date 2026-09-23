package com.rainif.doneat.core.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupSchemaTest {
    @Test
    fun exportsSchemaSix() {
        assertEquals(6, BackupSchema.EXPORT_VERSION)
    }

    @Test
    fun acceptsOneThroughSixOnly() {
        (1..6).forEach { assertTrue(BackupSchema.accepts(it)) }
        assertFalse(BackupSchema.accepts(0))
        assertFalse(BackupSchema.accepts(7))
    }
}

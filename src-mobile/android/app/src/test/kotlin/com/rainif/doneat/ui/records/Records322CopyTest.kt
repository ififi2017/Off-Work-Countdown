package com.rainif.doneat.ui.records

import org.junit.Assert.assertEquals
import org.junit.Test

class Records322CopyTest {
    @Test fun conclusionsJoinSentencesWithoutAddingSpacesToCjkPunctuation() {
        assertEquals("First. Second.", joinRecordsSentences(listOf("First.", "", "Second.")))
        assertEquals("一天。两天。", joinRecordsSentences(listOf("一天。", "两天。")))
        assertEquals("", joinRecordsSentences(emptyList()))
    }
}

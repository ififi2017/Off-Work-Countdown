package com.rainif.doneat.core.domain.salary

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NumberInputTest {
    @Test fun foldsDecimalDigitsAndAcceptedSeparatorsWithoutChangingTheirValue() {
        for ((input, expected) in listOf("١٫٥" to "1.5", "१२,५" to "12.5", "𝟙𝟚.５" to "12.5", "0" to "0", ".5" to ".5", "5." to "5.", "12345678.9" to "12345678.9")) {
            val draft = NumberInput.draft(input, decimal = true, maxDigits = 9)
            assertEquals(input, expected, draft)
            assertEquals(expected, NumberInput.committedText(draft, decimal = true, maxDigits = 9))
        }
    }

    @Test fun invalidEditsStayVisibleAndNeverBecomeADifferentCommittedAmount() {
        for (input in listOf("-500", "1.2.3", "1234567890", "1e3", "1e309", "NaN", "Infinity", "0x10", "1,234.56", "١a٢", " 5 ", "½", "²")) {
            assertNull(input, NumberInput.normalize(input, decimal = true, maxDigits = 9))
            assertEquals(input, NumberInput.draft(input, decimal = true, maxDigits = 9))
            assertNull(input, NumberInput.committedText(input, decimal = true, maxDigits = 9))
        }
        assertNull(NumberInput.parse("9".repeat(400)))
    }

    @Test fun emptyAndZeroStayDistinctWhileAPartialDecimalCannotCommit() {
        assertEquals("", NumberInput.committedText("", decimal = true, maxDigits = 9))
        assertNull(NumberInput.parse(""))
        assertEquals(".", NumberInput.draft(",", decimal = true, maxDigits = 9))
        assertNull(NumberInput.committedText(".", decimal = true, maxDigits = 9))
        assertEquals(0.0, NumberInput.parse("0")!!, 0.0)
        assertEquals(0.5, NumberInput.parse(".5")!!, 0.0)
    }

    @Test fun integerFieldsDoNotRemoveASeparatorOrTruncateDigits() {
        assertEquals("60", NumberInput.draft("٦٠", decimal = false, maxDigits = 3))
        for (input in listOf("1,5", "22,000", "1234", "-60")) {
            assertEquals(input, NumberInput.draft(input, decimal = false, maxDigits = 3))
            assertNull(NumberInput.committedText(input, decimal = false, maxDigits = 3))
        }
    }

    @Test fun anImportedCommaAmountIsNotChangedUntilTheUserEditsIt() {
        val stored = "1,5"
        assertNull(NumberInput.committedText(stored, decimal = true, maxDigits = 9))
        assertNull(NumberInput.parse(stored))
        val edited = NumberInput.draft(stored, decimal = true, maxDigits = 9)
        assertEquals("1.5", NumberInput.committedText(edited, decimal = true, maxDigits = 9))
    }
}

package com.rainif.doneat.core.domain.salary

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NumberInputTest {
    @Test fun foldsDigitsOfAnyScriptAndEverySeparator() {
        assertEquals("1.5", NumberInput.sanitize("١٫٥", decimal = true, maxDigits = 9))
        assertEquals("12.5", NumberInput.sanitize("१२,५", decimal = true, maxDigits = 9))
        assertEquals("22000", NumberInput.sanitize("22,000", decimal = false, maxDigits = 9))
    }

    @Test fun keepsOnlyTheFirstSeparatorAndCapsTheLength() {
        assertEquals("1.23", NumberInput.sanitize("1.2.3", decimal = true, maxDigits = 9))
        assertEquals("123456789", NumberInput.sanitize("1234567890", decimal = true, maxDigits = 9))
        assertEquals("", NumberInput.sanitize("-abc", decimal = true, maxDigits = 9))
    }

    @Test fun emptyIsNotZero() {
        assertNull(NumberInput.parse(""))
        assertNull(NumberInput.parse("."))
        assertEquals(0.0, NumberInput.parse("0")!!, 0.0)
        assertEquals(0.5, NumberInput.parse(".5")!!, 0.0)
    }
}

package com.rainif.doneat.core.domain.salary

/**
 * What a number field keeps of what was typed (iOS `OWCNumberField.sanitize`):
 * digits in any script folded to ASCII, and any accepted decimal separator
 * (`.`, `,`, the Arabic `٫`) folded to `.`. The stored salary is always this
 * canonical text, never a locale's formatting, so `Number()` in the shared
 * rules reads it the same everywhere.
 */
object NumberInput {
    fun sanitize(text: String, decimal: Boolean, maxDigits: Int): String {
        val folded = StringBuilder()
        var seenSeparator = false
        for (c in text) {
            val digit = Character.digit(c, 10)
            when {
                digit in 0..9 && Character.isDigit(c) -> folded.append(('0' + digit))
                // Keep only the first separator; "1.2.3" is not a number anybody meant.
                decimal && (c == '.' || c == ',' || c == '٫') && !seenSeparator -> {
                    seenSeparator = true
                    folded.append('.')
                }
            }
        }
        return folded.take(maxDigits).toString()
    }

    /** The field's text as a non-negative finite value, or null when it holds none. */
    fun parse(text: String): Double? = text.takeIf { it.isNotEmpty() && it != "." }?.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 }
}

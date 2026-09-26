package com.rainif.doneat.core.domain.salary

/** Number-pad input. Normalizing digits/separators must never remove a sign or truncate an amount. */
object NumberInput {
    /** Null means the entire edit is invalid. Empty and a lone separator are editable drafts. */
    fun normalize(text: String, decimal: Boolean, maxDigits: Int): String? {
        val folded = StringBuilder()
        var digits = 0
        var seenSeparator = false
        val points = text.codePoints().iterator()
        while (points.hasNext()) {
            val c = points.nextInt()
            val digit = Character.digit(c, 10)
            when {
                digit in 0..9 && Character.isDigit(c) -> {
                    if (++digits > maxDigits) return null
                    folded.append(('0' + digit))
                }
                decimal && c in listOf('.'.code, ','.code, '٫'.code) && !seenSeparator -> {
                    seenSeparator = true
                    folded.append('.')
                }
                else -> return null
            }
        }
        return folded.toString()
    }

    /** Invalid text stays visible so it can be corrected; it must not be committed. */
    fun draft(text: String, decimal: Boolean, maxDigits: Int): String = normalize(text, decimal, maxDigits) ?: text

    /** Empty clears the amount; zero remains a real value. Invalid drafts never reach settings. */
    fun committedText(text: String, decimal: Boolean, maxDigits: Int): String? =
        text.takeIf { it == normalize(it, decimal, maxDigits) && (it.isEmpty() || parse(it) != null) }

    /** A canonical decimal value, excluding signs, exponents, non-finite values and partial drafts. */
    fun parse(text: String): Double? = text.takeIf {
        it.isNotEmpty() && it != "." && it == normalize(it, decimal = true, maxDigits = Int.MAX_VALUE)
    }?.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 }
}

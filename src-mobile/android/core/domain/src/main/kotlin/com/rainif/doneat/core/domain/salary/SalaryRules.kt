package com.rainif.doneat.core.domain.salary

enum class SalaryType(val raw: String) {
    MONTHLY("monthly"),
    DAILY("daily");

    companion object {
        /** Anything but `daily` is monthly, as `getDailySalary` treats it. */
        fun fromRaw(raw: String) = if (raw == DAILY.raw) DAILY else MONTHLY
    }
}

/**
 * How a monthly salary becomes daily pay (`DailySalaryBasis` in
 * `lib/countdown.ts`). `fixed` divides by the configured monthly working days;
 * `scheduledMonth` divides each civil month by its own scheduled workdays. A
 * daily salary ignores it.
 */
enum class DailySalaryBasis(val raw: String) {
    FIXED("fixed"),
    SCHEDULED_MONTH("scheduledMonth");

    companion object {
        /** Anything unknown or absent is the fixed divisor, as for archives written before the basis existed. */
        fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: FIXED
    }
}

/** The salary fields as stored: the amount stays the text the user typed. */
data class SalarySettings(
    val amount: String,
    val type: SalaryType,
    val monthlyWorkingDays: Double,
    val annualBonusMonths: Double,
    val dailySalaryBasis: DailySalaryBasis = DailySalaryBasis.FIXED,
    /** Plan 024: pay multiplier for overtime (0 = unpaid). 1 is the original hourly rate. */
    val overtimePayMultiplier: Double = 1.0,
) {
    /** Whether pay divides each civil month by its own scheduled workdays. */
    val usesScheduledMonthBasis: Boolean
        get() = dailySalaryBasis == DailySalaryBasis.SCHEDULED_MONTH && type == SalaryType.MONTHLY
}

object SalaryRules {
    /**
     * Daily pay (`getDailySalary` in `lib/countdown.ts`), or null when the settings give none.
     * [scheduledMonthDays] replaces the fixed divisor when it is at least 1.
     */
    fun dailySalary(settings: SalarySettings, scheduledMonthDays: Int? = null): Double? {
        if (JavaScriptNumber.trim(settings.amount).isEmpty()) return null
        val parsed = JavaScriptNumber.parse(settings.amount)
        if (!parsed.isFinite() || parsed < 0) return null
        val bonus = settings.annualBonusMonths
        if (!bonus.isFinite() || bonus < 0) return null
        val multiplier = 1 + bonus / 12
        if (settings.type == SalaryType.DAILY) return (parsed * multiplier).takeIf { it.isFinite() }
        val days = scheduledMonthDays?.takeIf { it >= 1 }?.toDouble() ?: settings.monthlyWorkingDays
        if (!days.isFinite() || days <= 0 || days > 31) return null
        return ((parsed / days) * multiplier).takeIf { it.isFinite() }
    }
}

/**
 * `Number(string)` as ECMAScript defines it, for the salary field. Kotlin's
 * `toDouble` differs: it rejects surrounding whitespace and `0x`/`0o`/`0b`
 * literals, and accepts `NaN`, hexadecimal floats and `d`/`f` suffixes.
 */
object JavaScriptNumber {
    private const val EXTRA_WHITESPACE = "\t\n\u000B\u000C\r﻿"
    private val decimal = Regex("(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?")

    private fun isWhitespace(c: Char) = c in EXTRA_WHITESPACE || Character.isSpaceChar(c)

    fun trim(value: String) = value.trim(::isWhitespace)

    fun parse(value: String): Double {
        val text = trim(value)
        if (text.isEmpty()) return 0.0
        for ((prefix, radix) in listOf("0x" to 16, "0o" to 8, "0b" to 2)) {
            if (!text.lowercase().startsWith(prefix)) continue
            val digits = text.substring(2)
            if (digits.isEmpty()) return Double.NaN
            var result = 0.0
            for (c in digits) {
                val digit = Character.digit(c, 16)
                if (digit < 0 || digit >= radix) return Double.NaN
                result = result * radix + digit
            }
            return result
        }
        var body = text
        var sign = 1.0
        if (body.startsWith("+") || body.startsWith("-")) {
            if (body[0] == '-') sign = -1.0
            body = body.substring(1)
        }
        if (body == "Infinity") return sign * Double.POSITIVE_INFINITY
        if (!decimal.matches(body)) return Double.NaN
        return sign * body.toDouble()
    }
}

package com.rainif.doneat.core.domain.records

import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor

/**
 * The Foundation behaviours the records archive depends on, so documents move
 * between iOS and Android unchanged. Each was probed against Foundation and is
 * held by `record-json-fixtures.json`.
 */
object FoundationCompat {
    // `TimeZone.abbreviationDictionary` keys: Foundation accepts these as identifiers and keeps them.
    private val ABBREVIATIONS = setOf(
        "ADT", "AKDT", "AKST", "ART", "AST", "BDT", "BRST", "BRT", "BST", "CAT", "CDT", "CEST", "CET", "CLST",
        "CLT", "COT", "CST", "EAT", "EDT", "EEST", "EET", "EST", "GMT", "GST", "HKT", "HST", "ICT", "IRST",
        "IST", "JST", "KST", "MDT", "MSD", "MSK", "MST", "NDT", "NST", "NZDT", "NZST", "PDT", "PET", "PHT",
        "PKT", "PST", "SGT", "TRT", "UTC", "WAT", "WEST", "WET", "WIT",
    )
    private val OFFSET = Regex("(?:GMT|UTC)([+-])([0-9]{1,2})(?::?([0-9]{2}))?")
    private val AVAILABLE by lazy { ZoneId.getAvailableZoneIds() }

    /**
     * `TimeZone(identifier:)?.identifier`: null when Foundation rejects the
     * name. `UTC` reads back as `GMT`, and offset names as `GMT+HHMM`.
     */
    fun timeZoneIdentifier(raw: String): String? {
        if (raw == "UTC") return "GMT"
        OFFSET.matchEntire(raw)?.let { match ->
            val hours = match.groupValues[2].toInt()
            val minutes = match.groupValues[3].ifEmpty { "0" }.toInt()
            if (hours == 0 && minutes == 0) return "GMT"
            return "GMT${match.groupValues[1]}%02d%02d".format(Locale.ROOT, hours, minutes)
        }
        if (raw in ABBREVIATIONS || raw in AVAILABLE) return raw
        return null
    }

    fun isValidTimeZone(raw: String) = timeZoneIdentifier(raw) != null

    /**
     * A stored identifier as a `java.time` zone for arithmetic. Abbreviations
     * resolve through `SHORT_IDS` as Foundation's dictionary resolves them; an
     * unusable name falls back to GMT (iOS falls back to the device zone).
     */
    fun javaZone(identifier: String): ZoneId =
        runCatching { ZoneId.of(if (identifier == "UTC") "GMT" else identifier, ZoneId.SHORT_IDS) }.getOrElse { ZoneId.of("GMT") }

    private val UUID_TEXT = Regex("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    /** `UUID(uuidString:)?.uuidString`: strict shape, any case in, upper case out. */
    fun uuid(raw: String): String? = if (UUID_TEXT.matches(raw)) raw.uppercase(Locale.ROOT) else null

    /** A civil label as `RecordJSON.dayKey(year:month:day:)` writes it. */
    fun dayKey(date: LocalDate): String = "%04d-%02d-%02d".format(Locale.ROOT, date.year, date.monthValue, date.dayOfMonth)

    /**
     * `RecordJSON.date(fromDayKey:)`, returning the canonical label: exactly
     * three dash-separated fields of 4, 2 and 2 characters that name a real
     * Gregorian date from year 1.
     */
    fun canonicalDayKey(key: String): String? {
        val parts = key.split("-")
        if (parts.size != 3 || parts[0].length != 4 || parts[1].length != 2 || parts[2].length != 2) return null
        val year = parts[0].toIntOrNull() ?: return null
        val month = parts[1].toIntOrNull() ?: return null
        val day = parts[2].toIntOrNull() ?: return null
        if (year < 1 || month !in 1..12 || day !in 1..31) return null
        val date = runCatching { LocalDate.of(year, month, day) }.getOrNull() ?: return null
        return dayKey(date)
    }

    /** `Calendar.date(from: DateComponents)` without validation: out-of-range months and days roll over. */
    fun lenientDate(year: Int, month: Int, day: Int): LocalDate =
        LocalDate.of(year, 1, 1).plusMonths((month - 1).toLong()).plusDays((day - 1).toLong())

    /** Swift `Double.rounded()`: half away from zero. */
    fun roundedHalfAwayFromZero(value: Double) = if (value >= 0) floor(value + 0.5) else ceil(value - 0.5)

    /** Seconds since 2001-01-01, Foundation's default `Date` encoding, as Unix milliseconds. */
    fun referenceDateSecondsToUnixMs(seconds: Double) = (seconds + 978_307_200.0) * 1_000

    /** Foundation base64 decoding: standard alphabet, padded, no whitespace. */
    fun base64(text: String): ByteArray? {
        if (text.length % 4 != 0) return null
        return runCatching { java.util.Base64.getDecoder().decode(text) }.getOrNull()
    }

    fun base64(bytes: ByteArray): String = java.util.Base64.getEncoder().encodeToString(bytes)
}

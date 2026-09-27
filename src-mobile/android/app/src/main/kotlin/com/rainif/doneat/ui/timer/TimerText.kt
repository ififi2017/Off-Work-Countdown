package com.rainif.doneat.ui.timer

import android.content.Context
import android.content.res.Resources
import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.text.format.DateFormat
import com.rainif.doneat.R
import com.rainif.doneat.l10n.Strings
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToLong

/**
 * iOS `AppText`'s formatters for the timer, in the app's language. Times are
 * read in the device's zone and follow its 12/24-hour setting.
 *
 * [hideEarnings] is the product's one switch for money: every amount goes
 * through [money], so no screen can forget the mask.
 */
class TimerText(
    private val res: Resources,
    val locale: Locale,
    private val use24Hour: Boolean,
    private val hideEarnings: Boolean,
    private val zone: ZoneId = ZoneId.systemDefault(),
) {
    private val timeFormat = DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, if (use24Hour) "Hm" else "hm"), locale)
    private val weekdayTimeFormat =
        DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, if (use24Hour) "EEEHm" else "EEEhm"), locale)
    private val weekdayFormat = DateTimeFormatter.ofPattern("EEEE", locale)

    fun string(id: Int) = res.getString(id)

    /** The countdown's `HH:MM:SS`, never negative. */
    fun duration(ms: Double): String = countdownDuration(ms)

    /**
     * Hours and minutes, dropping a zero part ("8 h", "45 m", "8 h 5 m"). English
     * keeps iOS's compact units; other languages use their own short units.
     */
    fun relativeDuration(ms: Double): String {
        val total = maxOf(0L, (ms / 1_000).toLong())
        val hours = total / 3_600
        val minutes = (total % 3_600) / 60
        if (locale.language == "en") {
            val number = NumberFormat.getIntegerInstance(locale)
            if (hours == 0L) return "${number.format(minutes)} m"
            return if (minutes == 0L) "${number.format(hours)} h" else "${number.format(hours)} h ${number.format(minutes)} m"
        }
        val measures = buildList {
            if (hours > 0) add(Measure(hours, MeasureUnit.HOUR))
            if (minutes > 0 || hours == 0L) add(Measure(minutes, MeasureUnit.MINUTE))
        }
        return MeasureFormat.getInstance(locale, MeasureFormat.FormatWidth.SHORT).formatMeasures(*measures.toTypedArray())
    }

    fun time(atMs: Double): String = timeFormat.format(Instant.ofEpochMilli(atMs.toLong()).atZone(zone))

    /**
     * Each time is isolated, so an Arabic AM/PM marker stays with its own
     * digits; the range itself reads in the language's direction, start first.
     */
    fun timeRange(startMs: Double, endMs: Double) = "${isolate(time(startMs))} – ${isolate(time(endMs))}"

    /** The time alone today, with a short weekday on any other day. */
    fun eventTime(atMs: Double, nowMs: Double): String {
        val at = Instant.ofEpochMilli(atMs.toLong()).atZone(zone)
        val now = Instant.ofEpochMilli(nowMs.toLong()).atZone(zone)
        return if (at.toLocalDate() == now.toLocalDate()) timeFormat.format(at) else weekdayTimeFormat.format(at)
    }

    /** "Tomorrow", or the weekday's full name. */
    fun relativeDay(atMs: Double, nowMs: Double): String {
        val at = Instant.ofEpochMilli(atMs.toLong()).atZone(zone).toLocalDate()
        val today = Instant.ofEpochMilli(nowMs.toLong()).atZone(zone).toLocalDate()
        return if (at == today.plusDays(1)) res.getString(R.string.tomorrow) else weekdayFormat.format(at)
    }

    /** Two decimals, no currency symbol, as iOS; masked while earnings are hidden. */
    fun money(value: Double?): String {
        if (hideEarnings) return MASK
        value ?: return "—"
        return NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = 2
            maximumFractionDigits = 2
        }.format(value)
    }

    fun days(value: Double): String {
        val whole = value == Math.rint(value)
        val number = NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = if (whole) 0 else 1
            maximumFractionDigits = if (whole) 0 else 1
        }.format(value)
        return Strings.daysShort(res, number)
    }

    fun hours(value: Double): String {
        val rounded = (value * 10).roundToLong() / 10.0
        val format = MeasureFormat.getInstance(
            locale, MeasureFormat.FormatWidth.SHORT,
            android.icu.text.NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = if (value == Math.rint(value)) 0 else 1 },
        )
        return format.format(Measure(rounded, MeasureUnit.HOUR))
    }

    fun count(value: Int): String = NumberFormat.getIntegerInstance(locale).format(value)

    companion object {
        const val MASK = "••••"

        internal fun countdownDuration(ms: Double): String {
            val total = maxOf(0L, (ms / 1_000).toLong())
            return "%02d:%02d:%02d".format(Locale.ROOT, total / 3_600, (total % 3_600) / 60, total % 60)
        }

        /** A first-strong isolate: the text keeps its own direction inside the surrounding line. */
        fun isolate(text: String) = "\u2068$text\u2069"

        fun of(context: Context, hideEarnings: Boolean): TimerText {
            val locale = context.resources.configuration.locales[0]
            return TimerText(context.resources, locale, DateFormat.is24HourFormat(context), hideEarnings)
        }
    }
}

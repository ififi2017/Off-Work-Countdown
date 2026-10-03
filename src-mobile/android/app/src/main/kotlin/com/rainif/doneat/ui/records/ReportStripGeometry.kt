package com.rainif.doneat.ui.records

import com.rainif.doneat.core.designsystem.DoneAtReportMotion as Ease

/** Draw-only geometry. The calendar, travelling dots and hours share one fixed chart surface. */
internal data class ReportRect(val x: Float, val y: Float, val width: Float, val height: Float) {
    val centerX get() = x + width / 2
    val centerY get() = y + height / 2
    fun towards(other: ReportRect, fraction: Float) = ReportRect(
        x + (other.x - x) * fraction, y + (other.y - y) * fraction,
        width + (other.width - width) * fraction, height + (other.height - height) * fraction,
    )
}

internal fun reportStripFrame(calendar: ReportRect, bar: ReportRect, floor: Float, morph: Float, reveal: Float, index: Int, count: Int, week: Boolean, rise: Float): ReportRect {
    val rect = if (week) calendar.towards(bar, morph) else {
        val dot = ReportRect(calendar.centerX - bar.width / 2, calendar.centerY - bar.width / 2, bar.width, bar.width)
        val landing = ReportRect(bar.x, floor - bar.width, bar.width, bar.width)
        when {
            morph < .2f -> calendar.towards(dot, Ease.morphCurve.transform(Ease.window(morph, 0f, .2f)))
            morph < .64f -> dot.towards(landing, Ease.morphCurve.transform(Ease.window(morph, .2f, .64f)))
            else -> landing.towards(bar, Ease.outCubic(Ease.stagger(Ease.window(morph, .64f, 1f), index, count, .85f)))
        }
    }
    val land = Ease.outBack(reveal)
    val scale = .55f + .45f * land
    return ReportRect(rect.centerX - rect.width * scale / 2, rect.centerY + (1 - land) * rise - rect.height * scale / 2, rect.width * scale, rect.height * scale)
}

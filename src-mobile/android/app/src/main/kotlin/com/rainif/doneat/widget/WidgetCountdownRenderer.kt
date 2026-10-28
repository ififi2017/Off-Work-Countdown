package com.rainif.doneat.widget

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.ui.unit.DpSize
import com.rainif.doneat.core.domain.widget.WidgetSnapshot
import com.rainif.doneat.core.domain.widget.WidgetSuiteSnapshot
import java.time.ZoneId

/** Same geometry as the live widget; only the system timer's current value is sampled for this still preview. */
internal fun widgetCountdownPreviewBitmap(context: Context, kind: DoneAtWidgetKind, snapshot: WidgetSnapshot?, suite: WidgetSuiteSnapshot?, nowMs: Long, size: DpSize): Bitmap =
    widgetCountdownVisual(context, kind, snapshot?.entry(nowMs), snapshot?.upcoming.orEmpty(), suite?.countdownSegments.orEmpty(), nowMs, size,
        suite?.countdownTimeZoneIdentifier?.let(ZoneId::of) ?: ZoneId.systemDefault(), sampleTimer = true).bitmap

package com.rainif.doneat.widget

import com.rainif.doneat.core.domain.session.TimelineKind

/** Snapshot rows can outlive today; keep shift boundaries independent of the generation day. */
internal fun widgetTimelineDetail(kind: TimelineKind, overtime: Boolean, detail: String, overtimeLabel: String): String = when (kind) {
    TimelineKind.SHIFT_START -> ""
    TimelineKind.SHIFT_END -> if (overtime) overtimeLabel else ""
    else -> detail
}

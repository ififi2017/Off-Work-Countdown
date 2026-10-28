package com.rainif.doneat.widget

import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind

/** A cached control can act only on the exact still-running focus phase it displayed. */
internal fun widgetFocusActionAllowed(authorized: Boolean, action: String?, displayedStartMs: Long?, current: FocusSession?, nowMs: Double): Boolean =
    authorized && action in setOf("add", "stop") && displayedStartMs != null && current != null &&
        current.kind == FocusSessionKind.FOCUS && current.endedAtMs == null &&
        current.startedAtMs.toLong() == displayedStartMs && current.startedAtMs <= nowMs && nowMs < current.plannedEndAtMs

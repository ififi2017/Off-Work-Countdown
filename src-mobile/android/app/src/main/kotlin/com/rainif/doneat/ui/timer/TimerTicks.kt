package com.rainif.doneat.ui.timer

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.flow

/** Every collection starts with the current clock; missed seconds are never replayed. */
internal fun timerTicks(nowMs: () -> Long = System::currentTimeMillis) = flow {
    while (true) {
        val now = nowMs()
        emit(now.toDouble())
        delay(1_000L - Math.floorMod(now, 1_000L))
    }
}

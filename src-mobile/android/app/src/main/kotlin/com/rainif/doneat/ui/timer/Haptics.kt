package com.rainif.doneat.ui.timer

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View

/** Confirm and warning ticks; before Android 11 the closest older constants stand in. */
internal object Haptics {
    fun confirm(view: View) {
        view.performHapticFeedback(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY)
    }

    fun warn(view: View) {
        view.performHapticFeedback(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)
    }
}

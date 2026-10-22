package com.rainif.doneat.review

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.edit
import com.rainif.doneat.ui.components.ActionRow
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.SwitchRow

/**
 * Debug builds only. Release uses an empty stub with no preferences and no
 * controls. Ignoring thresholds still waits for the first foreground after
 * off-work, once a day, and still defers while a blocking layer is up.
 * Force asks on the next clear foreground and does not rewrite eligibility.
 */
object ReviewDebugGate {
    private const val FILE = "debug_review"
    private const val IGNORE = "ignore_thresholds"
    private const val FORCE = "force"

    fun ignoresThresholds(context: Context) = prefs(context).getBoolean(IGNORE, false)

    fun setIgnoresThresholds(context: Context, value: Boolean) {
        prefs(context).edit { putBoolean(IGNORE, value) }
    }

    fun forceArmed(context: Context) = prefs(context).getBoolean(FORCE, false)

    fun armForce(context: Context) {
        prefs(context).edit { putBoolean(FORCE, true) }
    }

    /**
     * Null lets the production decision run. A non-null result replaces it,
     * including a forced request that leaves [policy] unchanged.
     */
    internal fun intercept(context: Context, policy: ReviewPolicy, event: ReviewForeground): ReviewForegroundResult? {
        val stored = prefs(context)
        val mode = when {
            stored.getBoolean(FORCE, false) -> ReviewDebugMode.FORCE
            stored.getBoolean(IGNORE, false) -> ReviewDebugMode.IGNORE
            else -> return null
        }
        val decision = policy.debugIntercept(mode, event)
        if (decision.consumeForce) stored.edit { putBoolean(FORCE, false) }
        return decision.result
    }

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)
}

internal enum class ReviewDebugMode { IGNORE, FORCE }

internal data class ReviewDebugDecision(val result: ReviewForegroundResult, val consumeForce: Boolean)

/** Pure debug override. Preferences stay in [ReviewDebugGate]. */
internal fun ReviewPolicy.debugIntercept(mode: ReviewDebugMode, event: ReviewForeground): ReviewDebugDecision =
    when (mode) {
        ReviewDebugMode.FORCE -> ReviewDebugDecision(
            ReviewForegroundResult(this, event.blocker == ReviewBlocker.NONE),
            consumeForce = event.blocker == ReviewBlocker.NONE,
        )
        ReviewDebugMode.IGNORE -> ReviewDebugDecision(onForegroundIgnoringThresholds(event), consumeForce = false)
    }

/** Skips the day count, version dedup and 120-day gap. A manual opt-out still wins. */
internal fun ReviewPolicy.onForegroundIgnoringThresholds(event: ReviewForeground): ReviewForegroundResult {
    val counted = countingFinishedShift(event)
    if (counted.disabled || event.blocker != ReviewBlocker.NONE) return ReviewForegroundResult(counted, false)
    val offWorkAtMs = event.offWorkAtMs
    if (offWorkAtMs == null || event.nowMs < offWorkAtMs) return ReviewForegroundResult(counted, false)
    if (counted.lastAttemptDayKey == event.todayKey) return ReviewForegroundResult(counted, false)
    return ReviewForegroundResult(counted.copy(lastAttemptDayKey = event.todayKey), true)
}

/** The switch, shown on the About page of debug builds. Not translated: it never ships. */
@Composable
fun ReviewDebugSection() {
    val context = LocalContext.current
    var ignore by remember { mutableStateOf(ReviewDebugGate.ignoresThresholds(context)) }
    var armed by remember { mutableStateOf(ReviewDebugGate.forceArmed(context)) }
    SettingsGroup(title = "评分请求") {
        SwitchRow(
            "忽略评分门槛",
            ignore,
            {
                ignore = it
                ReviewDebugGate.setIgnoresThresholds(context, it)
            },
            supporting = "仍要下班后当天第一次打开，一天一次。付费墙、终身礼包、新版说明、编辑器、排班、专注和其它弹层会推迟到下一次打开。",
        )
        ActionRow(
            if (armed) "已预约：下次回到前台强制请求评分" else "下次回到前台强制请求评分",
            {
                ReviewDebugGate.armForce(context)
                armed = true
            },
        )
    }
}

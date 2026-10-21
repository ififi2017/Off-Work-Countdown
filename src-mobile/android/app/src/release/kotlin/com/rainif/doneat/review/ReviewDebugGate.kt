package com.rainif.doneat.review

import android.content.Context
import androidx.compose.runtime.Composable

/**
 * Release builds have no review test switch. This stub cannot arm a request,
 * ignore a threshold, or draw a control; the debug source set is the only
 * implementation that can.
 */
object ReviewDebugGate {
    @Suppress("UNUSED_PARAMETER")
    internal fun intercept(context: Context, policy: ReviewPolicy, event: ReviewForeground): ReviewForegroundResult? = null
}

@Composable
fun ReviewDebugSection() = Unit

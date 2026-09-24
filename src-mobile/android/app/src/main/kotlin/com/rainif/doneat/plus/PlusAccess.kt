package com.rainif.doneat.plus

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Whether Plus is active (iOS `PlusEntitlement.isAuthorized`). Purchases
 * arrive with Play Billing in T20; until then a release build is always the
 * free tier. A debug build can pretend otherwise through [PlusDebugOverride],
 * which the release source set replaces with a no-op.
 */
class PlusAccess(private val context: Context) {
    private val _authorized = MutableStateFlow(PlusDebugOverride.read(context))
    val authorized: StateFlow<Boolean> = _authorized.asStateFlow()

    fun setDebugAuthorized(value: Boolean) {
        if (!PlusDebugOverride.AVAILABLE) return
        PlusDebugOverride.write(context, value)
        _authorized.value = value
    }
}

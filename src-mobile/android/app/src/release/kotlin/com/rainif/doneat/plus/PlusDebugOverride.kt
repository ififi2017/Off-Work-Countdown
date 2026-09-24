package com.rainif.doneat.plus

import android.content.Context
import androidx.compose.runtime.Composable

/** Release builds have no way to unlock Plus except a purchase. */
object PlusDebugOverride {
    const val AVAILABLE = false

    @Suppress("UNUSED_PARAMETER")
    fun read(context: Context) = false

    @Suppress("UNUSED_PARAMETER")
    fun write(context: Context, value: Boolean) = Unit
}

@Suppress("UNUSED_PARAMETER")
@Composable
fun PlusDebugSection(plus: PlusAccess) = Unit

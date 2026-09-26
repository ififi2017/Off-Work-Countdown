package com.rainif.doneat.ui.records

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** CPU work checks the owning page's job; cancellation also prevents publishing its result. */
internal suspend fun <T> computeRecords(block: (checkActive: () -> Unit) -> T): T =
    withContext(Dispatchers.Default) { block { ensureActive() } }

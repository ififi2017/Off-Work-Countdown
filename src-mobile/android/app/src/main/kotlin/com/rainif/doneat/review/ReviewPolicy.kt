package com.rainif.doneat.review

/** One completed, genuinely started countdown earns a possible request on a later launch. */
internal data class ReviewPolicy(
    val trackedEndAtMs: Long? = null,
    val readyEndAtMs: Long? = null,
    val handledEndAtMs: Long = 0,
    val lastRequestAtMs: Long = 0,
    val disabled: Boolean = false,
) {
    fun trackRunning(endAtMs: Long, nowMs: Long) =
        if (disabled || endAtMs <= nowMs) this else copy(trackedEndAtMs = endAtMs)

    fun completed(endAtMs: Long): ReviewPolicy =
        if (disabled || endAtMs <= handledEndAtMs) this else copy(
            trackedEndAtMs = trackedEndAtMs?.takeUnless { it == endAtMs },
            readyEndAtMs = maxOf(endAtMs, readyEndAtMs ?: 0),
        )

    fun revoked(endAtMs: Long): ReviewPolicy = copy(
        trackedEndAtMs = trackedEndAtMs?.takeUnless { it == endAtMs },
        readyEndAtMs = readyEndAtMs?.takeUnless { it == endAtMs },
    )

    fun coldLaunch(nowMs: Long): Pair<ReviewPolicy, Boolean> {
        val pending = trackedEndAtMs
        val next = if (pending != null && pending <= nowMs) completed(pending) else this
        val eligible = !next.disabled && next.readyEndAtMs != null &&
            (next.lastRequestAtMs == 0L || nowMs - next.lastRequestAtMs >= REQUEST_GAP_MS)
        return next to eligible
    }

    /** Consume before calling Play: even a quota-suppressed or failed request must not loop. */
    fun requested(nowMs: Long) = copy(
        trackedEndAtMs = trackedEndAtMs?.takeIf { it > (readyEndAtMs ?: 0) },
        readyEndAtMs = null,
        handledEndAtMs = maxOf(handledEndAtMs, readyEndAtMs ?: 0),
        lastRequestAtMs = nowMs,
    )

    fun disable() = copy(trackedEndAtMs = null, readyEndAtMs = null, disabled = true)

    companion object {
        const val REQUEST_GAP_MS = 90L * 24 * 60 * 60 * 1_000
    }
}

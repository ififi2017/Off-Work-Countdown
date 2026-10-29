package com.rainif.doneat.updates

/** Local-only throttles. Future timestamps caused by clock correction do not block forever. */
object UpdatePolicy {
    const val CHECK_INTERVAL = 24 * 60 * 60 * 1000L
    const val REMIND_INTERVAL = 7 * CHECK_INTERVAL
    fun checkDue(now: Long, lastAttempt: Long): Boolean =
        lastAttempt <= 0 || now < lastAttempt || now - lastAttempt >= CHECK_INTERVAL
    fun reminderDue(now: Long, code: Long, lastCode: Long, lastShown: Long): Boolean =
        code != lastCode || lastShown <= 0 || now < lastShown || now - lastShown >= REMIND_INTERVAL
}

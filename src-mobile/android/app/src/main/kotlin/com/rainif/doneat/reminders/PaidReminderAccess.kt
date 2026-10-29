package com.rainif.doneat.reminders

import com.rainif.doneat.BuildConfig
import com.rainif.doneat.core.domain.reminders.ReminderChannel
import com.rainif.doneat.plus.PlusStoreState

/** Delivery rechecks both the monotonic proof and the signed deadline after process suspension. */
internal fun paidReminderDeliveryAllowed(channel: ReminderChannel, store: PlusStoreState,
    authorizedNow: Boolean, nowMs: Long): Boolean =
    !BuildConfig.CN_CHANNEL || channel !in setOf(ReminderChannel.REPORT, ReminderChannel.FOCUS) ||
        (authorizedNow && store.hasCurrentCnLease(nowMs))

package com.rainif.doneat.alarms

/** A write returning normally does not prove the registered identity reached durable storage. */
internal class VerifiedAlarmLedgerCommit(
    private val write: (ByteArray) -> Unit,
    private val read: () -> ByteArray,
) {
    fun save(bytes: ByteArray): Boolean = runCatching {
        write(bytes)
        read().contentEquals(bytes)
    }.getOrDefault(false)
}

/** The pure transaction used by the Android platform: acceptance needs two durable saves and an OS success. */
internal fun commitShiftAlarmRegistration(
    persistPending: () -> Boolean,
    register: () -> Unit,
    persistAccepted: () -> Boolean,
    rollback: () -> Unit,
): AlarmScheduleOutcome {
    val result = try {
        when {
            !persistPending() -> AlarmScheduleOutcome.FAILED
            else -> {
                register()
                if (persistAccepted()) AlarmScheduleOutcome.ACCEPTED else AlarmScheduleOutcome.FAILED
            }
        }
    } catch (_: SecurityException) { AlarmScheduleOutcome.FAILED }
    catch (_: IllegalStateException) { AlarmScheduleOutcome.LIMIT }
    catch (_: Exception) { AlarmScheduleOutcome.FAILED }
    if (result != AlarmScheduleOutcome.ACCEPTED) rollback()
    return result
}

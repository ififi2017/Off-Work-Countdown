package com.rainif.doneat.core.domain.records

/** Hide a superseded sync copy only when its surviving session is still present. */
object RecordsFocusHistory {
    fun visible(sessions: List<FocusSession>): List<FocusSession> = sessions.filter { session ->
        session.endReason != FocusEndReason.SUPERSEDED_BY_SYNC || sessions.none { other ->
            other.id != session.id && other.endReason != FocusEndReason.SUPERSEDED_BY_SYNC &&
                other.kind == session.kind && other.taskID == session.taskID &&
                kotlin.math.abs(other.startedAtMs - session.startedAtMs) < 60_000
        }
    }
}

package com.rainif.doneat.plus

/** Device-local: returning installations and restored settings have already completed their introduction. */
data class PlusIntroState(val loaded: Boolean = false, val seen: Boolean = false, val writeFailed: Boolean = false)

internal object PlusIntroPolicy {
    fun initialSeen(existingSetup: Boolean, storedSeen: Boolean?, damaged: Boolean): Boolean =
        damaged || storedSeen == true || storedSeen == null && existingSetup

    fun shouldPresent(state: PlusIntroState, setupComplete: Boolean, authorized: Boolean): Boolean =
        state.loaded && setupComplete && !state.seen && !authorized

    /** Intro metadata failure must not trap the user on the paywall; offer deadlines remain separately fail-closed. */
    fun afterFinish(previous: PlusIntroState, persisted: Boolean): PlusIntroState =
        previous.copy(seen = true, writeFailed = !persisted)
}

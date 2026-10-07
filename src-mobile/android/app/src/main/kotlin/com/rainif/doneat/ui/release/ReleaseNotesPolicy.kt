package com.rainif.doneat.ui.release

/** Device-local release introduction, independent of versionCode and user archives. */
data class ReleaseNotesState(val loaded: Boolean = false, val seenRelease: String? = null, val writeFailed: Boolean = false)

object ReleaseNotesPolicy {
    const val CURRENT = "3.2.1"

    fun shouldPresent(loaded: Boolean, onboardingComplete: Boolean, seenRelease: String?): Boolean =
        loaded && onboardingComplete && seenRelease != CURRENT

    /** Called once, after the archive and device settings have both loaded. */
    fun marksSeenOnInitialLoad(onboardingComplete: Boolean): Boolean = !onboardingComplete

    /** Never hide an update by changing memory before its atomic write succeeds. */
    fun afterMarkSeen(previous: ReleaseNotesState, persisted: Boolean): ReleaseNotesState =
        if (persisted) previous.copy(seenRelease = CURRENT, writeFailed = false)
        else previous.copy(writeFailed = true)

    fun mayInviteUpdateOffer(authorized: Boolean, free: Boolean, verified: Boolean, activeSubscription: Boolean,
                            release: String = CURRENT): Boolean =
        release == "3.2.1" && !authorized && free && verified && !activeSubscription
}

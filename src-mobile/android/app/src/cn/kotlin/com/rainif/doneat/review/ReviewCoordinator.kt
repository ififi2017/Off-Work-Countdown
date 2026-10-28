package com.rainif.doneat.review
import android.content.Context
import androidx.fragment.app.FragmentActivity
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.core.domain.session.ShiftSession
/** CN has no Google Play SDK, review prompt, or store dependency. */
class ReviewCoordinator {
 fun trackRunningShift(session: ShiftSession, shift: ShiftSnapshot?, nowMs: Long) = Unit
 fun noteCompletion(endAtMs: Long) = Unit
 fun revokeCompletion(endAtMs: Long) = Unit
 fun clearTrackedCompletion() = Unit
 fun disableAutomatic() = Unit
 fun requestIfEligible(activity: FragmentActivity, canPresent: () -> Boolean) = Unit
 companion object { fun get(context: Context) = ReviewCoordinator() }
}

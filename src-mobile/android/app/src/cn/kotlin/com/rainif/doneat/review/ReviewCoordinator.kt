package com.rainif.doneat.review
import android.content.Context
import androidx.fragment.app.FragmentActivity
import com.rainif.doneat.core.domain.session.ShiftSession
import java.time.ZoneId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
/** CN has no Google Play SDK, review prompt, review history or store dependency. */
class ReviewCoordinator {
 val foreground = MutableStateFlow(0).asStateFlow()
 fun noteCompletion(endAtMs: Long, recordsZone: ZoneId) = Unit
 fun revokeCompletion(endAtMs: Long, recordsZone: ZoneId) = Unit
 fun disableAutomatic() = Unit
 fun noteForeground() = Unit
 fun noteStop(changingConfigurations: Boolean) = Unit
 internal fun consumeForeground(visit: Int, event: ReviewForeground, stillInForeground: Boolean) = false
 fun launchReview(activity: FragmentActivity) = Unit
 companion object {
  fun get(context: Context) = ReviewCoordinator()
  internal fun foregroundEvent(session: ShiftSession, nowMs: Double, blocker: ReviewBlocker): ReviewForeground =
   ReviewPolicy.foreground(nowMs.toLong(), null, session.recordsZone, blocker)
 }
}

package com.rainif.doneat.plus
import com.rainif.doneat.core.domain.alarms.ShiftAlarmAuthorization
import org.junit.Assert.*
import org.junit.Test
class CnAccessPolicyTest {
 @Test fun lifetimeAlsoRequiresAnUnexpiredVerifiedLeaseForAlarms() {
  assertEquals(ShiftAlarmAuthorization.Unavailable, PlusStoreState(PlusStatus.LIFETIME).shiftAlarmAuthorization(1000))
  val signed = PlusStoreState(PlusStatus.LIFETIME, verifiedAuthorizationUntilMs = 2000)
  assertEquals(ShiftAlarmAuthorization.VerifiedUntil(2000), signed.shiftAlarmAuthorization(1999))
  assertEquals(ShiftAlarmAuthorization.Unavailable, signed.shiftAlarmAuthorization(2000))
 }
 @Test fun paidAnnualExpiryOrDeadlineAloneCannotGrantCnAlarms() {
  assertEquals(ShiftAlarmAuthorization.Unavailable, PlusStoreState(PlusStatus.SUBSCRIBED, verifiedSubscriptionExpiresAtMs = 100000).shiftAlarmAuthorization(1000))
  assertEquals(ShiftAlarmAuthorization.Unavailable, PlusStoreState(PlusStatus.FREE, verifiedAuthorizationUntilMs = 100000).shiftAlarmAuthorization(1000))
 }
}

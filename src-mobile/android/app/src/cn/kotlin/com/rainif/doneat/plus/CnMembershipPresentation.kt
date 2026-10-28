package com.rainif.doneat.plus

/** Presentation only. These values never participate in Plus authorization or command handling. */
internal enum class CnMembershipNotice { NONE, DEBUG_CONNECTION, CONNECTION, RETRY_ORIGINAL, PENDING, TRIAL_UNAVAILABLE, REQUEST }

internal fun cnMembershipNotice(error: String?, pending: Boolean, debugLoopback: Boolean): CnMembershipNotice = when {
    error == "operation_not_found" -> CnMembershipNotice.RETRY_ORIGINAL
    error == "connection_unavailable" && debugLoopback -> CnMembershipNotice.DEBUG_CONNECTION
    error == "connection_unavailable" -> CnMembershipNotice.CONNECTION
    error == "trial_unavailable" -> CnMembershipNotice.TRIAL_UNAVAILABLE
    error != null -> CnMembershipNotice.REQUEST
    pending -> CnMembershipNotice.PENDING
    else -> CnMembershipNotice.NONE
}

/** A rounded-up display count from the signed server time and its monotonic anchor, never a grant. */
internal fun cnTrialDaysRemaining(expiryMs: Long, serverTimeMs: Long, elapsedMs: Long?): Int? {
    if (elapsedMs == null || elapsedMs < 0) return null
    val remaining = expiryMs - serverTimeMs - elapsedMs
    if (remaining <= 0) return 0
    return (1 + (remaining - 1) / CnLicenseProtocol.DAY_MS).coerceAtMost(14).toInt()
}

internal enum class CnAccessPresentation { VERIFIED, SAVED, CHECKING, EXPIRED, REVOKED, REPLACED, NEEDS_PROOF }

internal fun cnAccessPresentation(reason: String?, authorized: Boolean, busy: Boolean, error: String?, trialDays: Int?): CnAccessPresentation = when {
    reason == "revoked" -> CnAccessPresentation.REVOKED
    reason == "replaced" -> CnAccessPresentation.REPLACED
    reason == "expired" || trialDays == 0 -> CnAccessPresentation.EXPIRED
    busy -> CnAccessPresentation.CHECKING
    authorized && error != null -> CnAccessPresentation.SAVED
    authorized -> CnAccessPresentation.VERIFIED
    else -> CnAccessPresentation.NEEDS_PROOF
}

import LocalAuthentication

/// Face ID / Touch ID in front of the salary figures, falling back to the
/// device passcode.
///
/// `deviceOwnerAuthentication` is the policy that already does what we want:
/// biometrics first, and the phone's own passcode when the face is not
/// recognised, the finger is wet, or the hardware has none. There is no need
/// for the app to invent a PIN of its own, and inventing one would be worse —
/// a home-made four-digit code stored by the app is weaker than the one the
/// Secure Enclave already guards.
enum BiometricGate {
    /// Whether the device has biometric hardware the app cannot currently use:
    /// permission declined, nothing enrolled, or locked out after too many
    /// failed attempts.
    ///
    /// The `biometryType` check is what keeps a device that never had Face ID
    /// from being told to go and switch it on. It reads as `.none` until
    /// `canEvaluatePolicy` has run, which is why the call above it is not
    /// discarded.
    ///
    /// This exists because iOS shows an app's biometric permission alert
    /// exactly once, ever. After a decline there is no API to ask again — the
    /// only way back is the app's own page in Settings — so the app has to say
    /// so rather than quietly falling back to the passcode forever.
    static var isBiometryBlocked: Bool {
        let context = LAContext()
        var error: NSError?
        let usable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return !usable && context.biometryType != .none
    }

    /// Ask the device owner to confirm it is them.
    ///
    /// Returns `true` when there is nothing to ask: a device with no passcode
    /// set cannot authenticate anybody, and refusing there would lock the owner
    /// out of their own salary settings rather than protecting them.
    static func confirmOwner(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            // Cancelled, or failed too many times. Either way the answer is no.
            return false
        }
    }
}

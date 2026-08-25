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
    /// Why biometry is or is not usable on this device.
    ///
    /// The `biometryType` check is what keeps a device that never had biometric
    /// hardware from being told to go and switch it on.
    ///
    /// This exists because iOS shows an app's biometric permission alert
    /// exactly once, ever. After a decline there is no API to ask again — the
    /// only way back is the app's own page in Settings — so the app has to say
    /// so rather than quietly falling back to the passcode forever.
    /// What the device can do, and when it cannot, why.
    struct Status {
        /// The hardware this device has, whether or not it is usable.
        let biometry: LABiometryType
        /// `nil` when biometry works, or when the device has none to begin with.
        let obstacle: Obstacle?
    }

    /// Why biometry is present but unusable.
    ///
    /// These used to be collapsed into a single `Bool` and the `NSError` from
    /// `canEvaluatePolicy` was discarded — so the app knew exactly which of
    /// these it was and said only "unavailable". The three want different
    /// things from the user and only one of them is about permission.
    enum Obstacle: Equatable {
        /// No face or finger recorded. Nothing to grant; go and enrol one.
        case notEnrolled
        /// Too many failed attempts. One passcode unlock restores it.
        case lockedOut
        /// Refused for this app. Only Face ID can reach this state, because it
        /// is the only one that asks.
        case notPermitted
    }

    static func status() -> Status {
        let context = LAContext()

        // `biometryType` is only meaningful once a policy has been evaluated on
        // this same context, and it reports what the hardware *is* rather than
        // what is currently usable — which is what lets the messages below name
        // Touch ID on a device whose owner has not enrolled a finger.
        var deviceError: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &deviceError)
        let biometry = context.biometryType

        var biometryError: NSError?
        let usable = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &biometryError
        )
        guard !usable, biometry != .none else {
            return Status(biometry: biometry, obstacle: nil)
        }

        let obstacle: Obstacle = switch LAError.Code(rawValue: biometryError?.code ?? 0) {
        case .biometryNotEnrolled: .notEnrolled
        case .biometryLockout: .lockedOut
        default: .notPermitted
        }
        return Status(biometry: biometry, obstacle: obstacle)
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

extension LABiometryType {
    /// The translation key naming this hardware, or nil when there is none.
    ///
    /// Only Simplified Chinese translates these; every other language keeps
    /// Apple's product names as they ship, which is what Apple's own
    /// localisations do. The copy used to say "Face ID" everywhere, which is
    /// simply wrong on an iPad with Touch ID — and wrong in the one place it
    /// matters most, the button asking for the permission.
    var nameKey: String? {
        switch self {
        case .faceID: "biometryFaceID"
        case .touchID: "biometryTouchID"
        case .opticID: "biometryOpticID"
        default: nil
        }
    }

    /// The matching SF Symbol. `faceid` was hardcoded next to copy that had
    /// just been made device-aware, which would have been worse than leaving
    /// both wrong: a face drawn beside the words "Touch ID".
    var symbolName: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.shield"
        }
    }
}

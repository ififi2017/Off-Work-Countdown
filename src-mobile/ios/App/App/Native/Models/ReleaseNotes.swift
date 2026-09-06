import Foundation

enum ReleaseNotes {
    // Bump when there is a new introduction to read, independently of build numbers.
    static let current = "3.1.9"
    static let seenKey = "ios.native.releaseNotesSeen"

    static func shouldPresent(onboardingComplete: Bool, seenRelease: String?) -> Bool {
        onboardingComplete && seenRelease != current
    }
}

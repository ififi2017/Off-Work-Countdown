import Foundation

enum ReleaseNotes {
    // Bump when there is a new introduction to read, independently of build numbers.
    // 3.3.0 introduces workplace automation, so it only becomes the current
    // page in builds that show the automation settings it points to.
    static let current = WorkplaceAutomation.showsSettingsEntry ? "3.3.0" : "3.2.3"
    static let seenKey = "ios.native.releaseNotesSeen"

    static func shouldPresent(onboardingComplete: Bool, seenRelease: String?) -> Bool {
        onboardingComplete && seenRelease != current
    }

    /// The release that already had its "see what's new" notice.
    static let noticeSentKey = "ios.native.releaseNoticeSent"

    /// One notice per release, only for someone who updated but has not
    /// opened the app since: opening it shows the page itself.
    static func shouldPostNotice(onboardingComplete: Bool, seenRelease: String?, noticeSent: String?) -> Bool {
        current == "3.3.0" && shouldPresent(onboardingComplete: onboardingComplete, seenRelease: seenRelease)
            && noticeSent != current
    }
}

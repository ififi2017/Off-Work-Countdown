import Foundation
import UserNotifications

/// The app's half of the widget extension's one-time 3.2.3 note
/// (`UpdateAnnouncement` in WidgetExtension/OffWorkWidgets.swift): once
/// someone has opened the app they have seen What's New, so the note is
/// cancelled if pending and never scheduled afterwards.
enum UpdateAnnouncementGate {
    /// Must match `UpdateAnnouncement.identifier` and `.handledKey`.
    static let identifier = "doneat.update.3.2.3.widgets"
    static let handledKey = "ios.updateAnnouncement.323.handled"

    static func appOpened(groupDefaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshotPublisher.appGroupIdentifier),
                          center: UNUserNotificationCenter = .current()) {
        groupDefaults?.set(true, forKey: handledKey)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

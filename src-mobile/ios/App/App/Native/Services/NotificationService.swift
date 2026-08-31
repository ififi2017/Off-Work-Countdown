import UIKit
import UserNotifications

@MainActor
@Observable
final class NotificationService {
    enum Status: Equatable {
        case unknown
        case notDetermined
        case denied
        case allowed
    }

    private(set) var status: Status = .unknown
    enum FocusScheduleResult: Equatable, Sendable {
        case scheduled
        case permissionDenied
        case failed
        /// The session changed while a system call was suspended. This request
        /// must not clear or replace the newer session's notification.
        case superseded
    }

    enum FocusSchedulingDecision: Equatable, Sendable {
        case requestPermission
        case schedule
        case blocked
    }

    static func focusSchedulingDecision(for status: Status) -> FocusSchedulingDecision {
        switch status {
        case .notDetermined: .requestPermission
        case .allowed: .schedule
        case .unknown, .denied: .blocked
        }
    }

    /// Pure ownership check used after the system's asynchronous add call.
    /// A phase that stopped or was replaced while awaiting permission may not
    /// resurrect its notification afterward.
    static func shouldKeepFocusNotification(
        requestGeneration: UInt64,
        currentGeneration: UInt64,
        requestID: UUID,
        activeSessionID: UUID?
    ) -> Bool {
        requestGeneration == currentGeneration && requestID == activeSessionID
    }

    /// The same ownership rule must protect destructive preflight work as well
    /// as the final request. Keeping it as a named pure decision gives tests a
    /// way to cover the race without talking to the system notification center.
    static func mayMutateFocusNotificationChannel(
        requestGeneration: UInt64,
        currentGeneration: UInt64,
        requestID: UUID,
        activeSessionID: UUID?
    ) -> Bool {
        shouldKeepFocusNotification(
            requestGeneration: requestGeneration,
            currentGeneration: currentGeneration,
            requestID: requestID,
            activeSessionID: activeSessionID
        )
    }

    static func cancelAllFocusTimers() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("owc.focus.") }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    private var scheduleGeneration = 0

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: status = .notDetermined
        case .denied: status = .denied
        case .authorized, .provisional, .ephemeral: status = .allowed
        @unknown default: status = .unknown
        }
    }

    func request() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refresh()
            return granted
        } catch {
            await refresh()
            return false
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Owns the focus/break notification lifecycle. It intentionally has no
    /// dependency on `OffWorkStore`, so timer model tests can inject a pure
    /// decision while production still uses the system notification center.
    static func scheduleFocusTimer(
        id: UUID,
        endAt: Date,
        title: String,
        body: String,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> FocusScheduleResult {
        let center = UNUserNotificationCenter.current()
        // A phase start owns this channel even when authorization later turns
        // out to be denied. Clear a predecessor first so it cannot become a
        // stale alert if the user re-enables notifications in Settings.
        let previous = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("owc.focus.") }
        // `pendingNotificationRequests()` suspends. A stopped/replaced phase
        // can therefore finish and schedule its successor before this old
        // request resumes. Check ownership before it clears the shared focus
        // channel, not only after it has attempted to add its own request.
        guard isCurrent() else { return .superseded }
        center.removePendingNotificationRequests(withIdentifiers: previous)
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return .failed
            }
        }
        let refreshed = await center.notificationSettings()
        guard refreshed.authorizationStatus == .authorized || refreshed.authorizationStatus == .provisional || refreshed.authorizationStatus == .ephemeral else {
            return .permissionDenied
        }
        // Permission prompts add another suspension point. Do not let an old
        // phase write after a newly started phase has claimed the channel.
        guard isCurrent() else { return .superseded }
        let identifier = focusTimerIdentifier(id)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, endAt.timeIntervalSinceNow),
                repeats: false
            )
        )
        do {
            try await center.add(request)
            // A replacement can win while `add` is in flight. Removing only
            // this request is safe; removing all focus notifications here
            // would reintroduce the race this guard closes.
            guard isCurrent() else {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                return .superseded
            }
            return .scheduled
        } catch {
            return .failed
        }
    }

    static func cancelFocusTimer(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [focusTimerIdentifier(id)]
        )
    }

    private static func focusTimerIdentifier(_ id: UUID) -> String {
        "owc.focus.\(id.uuidString)"
    }

    func reschedule(store: OffWorkStore, now: Date = .now) async {
        scheduleGeneration += 1
        let generation = scheduleGeneration
        await refresh()
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existingIdentifiers = Set(
            pending.map(\.identifier).filter { $0.hasPrefix("owc.shift.") }
        )

        guard status == .allowed, store.publishesLiveSurfaces else {
            center.removePendingNotificationRequests(withIdentifiers: Array(existingIdentifiers))
            return
        }
        guard let reminders = try? store.shiftReminders(at: now) else { return }
        guard generation == scheduleGeneration, store.publishesLiveSurfaces else { return }

        let snapshot = store.snapshot(at: now)
        let future = reminders.filter { reminder in
            guard reminder.atMs > now.timeIntervalSince1970 * 1_000,
                  reminder.title != nil,
                  reminder.body != nil
            else { return false }
            guard let snapshot else { return true }
            return store.shouldDeliverReminder(reminder, for: snapshot)
        }
        let essential = future.filter { $0.kind != "microBreak" }.sorted { $0.atMs < $1.atMs }
        let health = future.filter { $0.kind == "microBreak" }.sorted { $0.atMs < $1.atMs }
        let desired = Array((essential + health).prefix(store.liveActivityEnabled && store.notificationMode == .off ? 59 : 60))
        var desiredIdentifiers = Set<String>()
        var allSucceeded = true

        for reminder in desired {
            guard generation == scheduleGeneration, store.publishesLiveSurfaces else { return }
            guard let title = reminder.title, let body = reminder.body else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["kind": reminder.kind]
            let date = Date(timeIntervalSince1970: reminder.atMs / 1_000)
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = "owc.shift.\(reminder.id)"
            desiredIdentifiers.insert(identifier)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                allSucceeded = false
            }
        }

        if store.liveActivityEnabled,
           store.notificationMode == .off,
           let snapshot,
           store.shouldScheduleLiveActivityEndFallback(snapshot: snapshot, at: now),
           generation == scheduleGeneration {
            let identifier = "owc.shift.live.end.\(Int64(snapshot.endAtMs))"
            let content = UNMutableNotificationContent()
            content.title = store.t("offWorkTime")
            content.body = store.t("offWorkToday")
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: snapshot.endDate
            )
            do {
                try await center.add(UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                ))
                desiredIdentifiers.insert(identifier)
            } catch {
                allSucceeded = false
            }
        }

        if allSucceeded, generation == scheduleGeneration, store.publishesLiveSurfaces {
            let stale = existingIdentifiers.subtracting(desiredIdentifiers)
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }
    }

    /// Removes this app's shift notifications.
    ///
    /// Guarded by the same generation the scheduling path uses, and for the same
    /// reason. Two `await`s separate reading the identifiers from deleting
    /// them, and a countdown stopped and restarted across that gap left this
    /// call holding a list captured before the restart — so it deleted the
    /// notifications the restart had just written. The identifiers are stable,
    /// which is what made the collision silent: same ids, so nothing looked
    /// wrong until the reminders never arrived.
    func clearShiftNotifications() async {
        scheduleGeneration += 1
        let generation = scheduleGeneration
        let center = UNUserNotificationCenter.current()
        let pendingIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("owc.shift.") }
        let deliveredIdentifiers = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix("owc.shift.") }
        // Somebody rescheduled while we were reading. That work is newer than
        // this one, so it wins; the notifications it wrote are not ours to drop.
        guard generation == scheduleGeneration else { return }
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)
    }
}

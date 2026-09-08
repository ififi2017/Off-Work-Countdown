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
    /// Notification-center operations shared by both channels; each owns separate IDs.
    struct ShiftCenter {
        var authorization: () async -> Status
        var pendingIDs: () async -> [String]
        var deliveredIDs: () async -> [String]
        var add: (UNNotificationRequest) async throws -> Void
        var removePending: ([String]) -> Void
        var removeDelivered: ([String]) -> Void

        static let system = Self(
            authorization: {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                switch settings.authorizationStatus {
                case .notDetermined: return .notDetermined
                case .denied: return .denied
                case .authorized, .provisional, .ephemeral: return .allowed
                @unknown default: return .unknown
                }
            },
            pendingIDs: { await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier) },
            deliveredIDs: { await UNUserNotificationCenter.current().deliveredNotifications().map(\.request.identifier) },
            add: { try await UNUserNotificationCenter.current().add($0) },
            removePending: { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: $0) },
            removeDelivered: { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: $0) }
        )
    }

    private let shiftCenter: ShiftCenter
    private var scheduleGeneration = 0
    private var pendingShiftOperation: Task<Void, Never>?

    init(shiftCenter: ShiftCenter = .system) {
        self.shiftCenter = shiftCenter
    }

    func refresh() async {
        status = await shiftCenter.authorization()
    }

    /// A submitted system add must finish before a later clear reads its IDs.
    /// Keep queued cleanup alive even if its view task is cancelled; a newer
    /// intent supersedes it through the generation instead.
    private func enqueueShiftOperation(_ work: @escaping (Int) async -> Void) async {
        scheduleGeneration += 1
        let generation = scheduleGeneration
        let previous = pendingShiftOperation
        let task = Task { @MainActor in
            _ = await previous?.value
            guard generation == self.scheduleGeneration else { return }
            await work(generation)
        }
        pendingShiftOperation = task
        await task.value
        if generation == scheduleGeneration { pendingShiftOperation = nil }
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

    /// Which alert of a phase this is. A pomodoro owes the user two of them —
    /// the block ending and the break that follows it ending — and a suspended
    /// phone cannot be asked to compose the second one when it comes due, so
    /// both are written at the same time. Fixed slots keep cancellation a
    /// synchronous, exact-identifier operation.
    enum FocusAlertSlot: String, CaseIterable, Sendable {
        case end
        case breakEnd
    }

    struct FocusAlert: Equatable, Sendable {
        var slot: FocusAlertSlot
        var at: Date
        var title: String
        var body: String
    }

    /// Owns the focus/break notification lifecycle. It intentionally has no
    /// dependency on `OffWorkStore`, so timer model tests can inject a pure
    /// decision while production still uses the system notification center.
    static func scheduleFocusTimers(
        id: UUID,
        alerts: [FocusAlert],
        center: ShiftCenter = .system,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> FocusScheduleResult {
        let previous = pendingFocusOperation
        let task = Task { @MainActor in
            _ = await previous?.value
            guard isCurrent() else { return FocusScheduleResult.superseded }
            return await writeFocusTimers(id: id, alerts: alerts, center: center, isCurrent: isCurrent)
        }
        pendingFocusOperation = task
        return await task.value
    }

    // Reusing a session's fixed notification IDs requires serial writes: an
    // older in-flight add must clean up before the refreshed plan writes them.
    private static var pendingFocusOperation: Task<FocusScheduleResult, Never>?

    private static func writeFocusTimers(
        id: UUID,
        alerts: [FocusAlert],
        center: ShiftCenter,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> FocusScheduleResult {
        // A phase start owns this channel even when authorization later turns
        // out to be denied. Clear a predecessor first so it cannot become a
        // stale alert if the user re-enables notifications in Settings.
        let previous = await center.pendingIDs()
            .filter { $0.hasPrefix("owc.focus.") }
        // `pendingNotificationRequests()` suspends. A stopped/replaced phase
        // can therefore finish and schedule its successor before this old
        // request resumes. Check ownership before it clears the shared focus
        // channel, not only after it has attempted to add its own request.
        guard isCurrent() else { return .superseded }
        center.removePending(previous)
        // Restoring elapsed blocks must not open a permission prompt for
        // reminders that can no longer fire (or hold up the next phase).
        guard alerts.contains(where: { $0.at > .now }) else { return .scheduled }
        let settings = await center.authorization()
        if settings == .notDetermined {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return .failed
            }
        }
        let refreshed = await center.authorization()
        guard refreshed == .allowed else {
            return .permissionDenied
        }
        // Permission prompts add another suspension point. Do not let an old
        // phase write after a newly started phase has claimed the channel.
        guard isCurrent() else { return .superseded }
        var written: [String] = []
        for alert in alerts {
            // Permission and queue waits must not backfill an alert that passed.
            guard alert.at > .now else { continue }
            let identifier = focusTimerIdentifier(id, slot: alert.slot)
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, alert.at.timeIntervalSinceNow),
                    repeats: false
                )
            )
            do {
                try await center.add(request)
            } catch {
                center.removePending(written)
                return .failed
            }
            written.append(identifier)
            // A replacement can win while `add` is in flight. Removing only
            // what this phase wrote is safe; removing all focus notifications
            // here would reintroduce the race this guard closes.
            guard isCurrent() else {
                center.removePending(written)
                return .superseded
            }
        }
        return .scheduled
    }

    static func cancelFocusTimer(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: FocusAlertSlot.allCases.map { focusTimerIdentifier(id, slot: $0) }
        )
    }

    private static func focusTimerIdentifier(_ id: UUID, slot: FocusAlertSlot) -> String {
        "owc.focus.\(id.uuidString).\(slot.rawValue)"
    }

    func reschedule(store: OffWorkStore, now: Date? = nil) async {
        await enqueueShiftOperation { generation in
            await self.performReschedule(store: store, now: now ?? .now, generation: generation)
        }
    }

    private func performReschedule(store: OffWorkStore, now: Date, generation: Int) async {
        await refresh()
        let center = shiftCenter
        let pending = await center.pendingIDs()
        let existingIdentifiers = Set(
            pending.filter { $0.hasPrefix("owc.shift.") }
        )

        guard generation == scheduleGeneration else { return }
        guard status == .allowed, store.publishesLiveSurfaces else {
            center.removePending(Array(existingIdentifiers))
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
        let schedulesLiveActivityFallback = store.shouldScheduleLiveActivityEndFallback(
            snapshot: snapshot,
            at: now
        )
        let desired = Array((essential + health).prefix(schedulesLiveActivityFallback ? 59 : 60))
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

        if schedulesLiveActivityFallback,
           let snapshot,
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
            center.removePending(Array(stale))
        }
    }

    /// Clears after any in-flight add has completed, so stopping cannot leave
    /// behind a notification that arrives after the clear's initial read.
    func clearShiftNotifications() async {
        await enqueueShiftOperation { generation in
            let pending = await self.shiftCenter.pendingIDs().filter { $0.hasPrefix("owc.shift.") }
            let delivered = await self.shiftCenter.deliveredIDs().filter { $0.hasPrefix("owc.shift.") }
            guard generation == self.scheduleGeneration else { return }
            self.shiftCenter.removePending(pending)
            self.shiftCenter.removeDelivered(delivered)
        }
    }
}

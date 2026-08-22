import UIKit
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    enum Status: Equatable {
        case unknown
        case notDetermined
        case denied
        case allowed
    }

    @Published private(set) var status: Status = .unknown
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

    func reschedule(store: OffWorkStore, now: Date = .now) async {
        scheduleGeneration += 1
        let generation = scheduleGeneration
        await refresh()
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existingIdentifiers = Set(
            pending.map(\.identifier).filter { $0.hasPrefix("owc.shift.") }
        )

        guard status == .allowed, store.countdownStarted else {
            center.removePendingNotificationRequests(withIdentifiers: Array(existingIdentifiers))
            return
        }
        guard let reminders = try? CountdownRules.shared.reminders(
            input: store.rulesInput(at: now),
            reminderInputs: store.reminderInputs()
        ) else { return }
        guard generation == scheduleGeneration, store.countdownStarted else { return }

        let future = reminders.filter {
            $0.atMs > now.timeIntervalSince1970 * 1_000 && $0.title != nil && $0.body != nil
        }
        let essential = future.filter { $0.kind != "microBreak" }.sorted { $0.atMs < $1.atMs }
        let health = future.filter { $0.kind == "microBreak" }.sorted { $0.atMs < $1.atMs }
        let desired = Array((essential + health).prefix(store.liveActivityEnabled && store.notificationMode == .off ? 59 : 60))
        var desiredIdentifiers = Set<String>()
        var allSucceeded = true

        for reminder in desired {
            guard generation == scheduleGeneration, store.countdownStarted else { return }
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
           let snapshot = store.snapshot(at: now),
           snapshot.endAtMs > now.timeIntervalSince1970 * 1_000,
           generation == scheduleGeneration,
           store.countdownStarted {
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

        if allSucceeded, generation == scheduleGeneration, store.countdownStarted {
            let stale = existingIdentifiers.subtracting(desiredIdentifiers)
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }
    }

    func clearShiftNotifications() async {
        scheduleGeneration += 1
        let center = UNUserNotificationCenter.current()
        let pendingIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("owc.shift.") }
        let deliveredIdentifiers = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix("owc.shift.") }
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)
    }
}

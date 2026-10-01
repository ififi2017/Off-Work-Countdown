import AlarmKit
import SwiftUI
import UserNotifications

/// What the alarms should be right now: the planned list with finished text,
/// and how long the entitlement lets them run.
struct ShiftAlarmPlan: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        var alarm: PlannedShiftAlarm
        /// The id AlarmKit knows it by: the planned alarm plus everything it
        /// shows, so a language change or new copy replaces it.
        var systemID: UUID
        var title: String
    }

    var isEnabled: Bool
    /// `nil` when the entitlement allows no alarms.
    var windowEnd: Date?
    /// A lifetime window ends a year out with shifts still to come; a
    /// subscription's ends at its expiry, which a reminder must not suggest
    /// refreshing past.
    var windowIsLifetime: Bool
    var items: [Item]
    var stopLabel: String
    var snoozeLabel: String
    var snoozingLabel: String
    var refreshTitle: String
    var refreshBody: String

    static let disabled = ShiftAlarmPlan(
        isEnabled: false, windowEnd: nil, windowIsLifetime: false, items: [],
        stopLabel: "", snoozeLabel: "", snoozingLabel: "", refreshTitle: "", refreshBody: ""
    )
}

/// AlarmKit behind a seam, so reconciliation can be tested without the
/// system. `existing` only ever lists this app's own alarms.
struct ShiftAlarmSystem {
    enum Authorization: Equatable, Sendable {
        case notDetermined
        case denied
        case authorized
    }

    struct Existing: Equatable, Sendable {
        var id: UUID
        var fireAt: Date?
        /// `false` while it rings, snoozes or is paused.
        var isWaiting: Bool
    }

    struct Request: Equatable, Sendable {
        var fireAt: Date
        var title: String
        var stopLabel: String
        var snoozeLabel: String
        var snoozingLabel: String
    }

    enum Outcome: Equatable, Sendable {
        case scheduled
        case limitReached
        case failed
    }

    var authorization: @MainActor () -> Authorization
    var requestAuthorization: @MainActor () async -> Authorization
    var existing: @MainActor () -> [Existing]
    var schedule: @MainActor (_ id: UUID, _ request: Request) async -> Outcome
    var cancel: @MainActor (_ id: UUID) -> Void

    static let system = ShiftAlarmSystem(
        authorization: { Self.authorization(AlarmManager.shared.authorizationState) },
        requestAuthorization: {
            do { return Self.authorization(try await AlarmManager.shared.requestAuthorization()) }
            catch { return Self.authorization(AlarmManager.shared.authorizationState) }
        },
        existing: {
            ((try? AlarmManager.shared.alarms) ?? []).map { alarm in
                var fireAt: Date?
                if case .fixed(let date) = alarm.schedule { fireAt = date }
                return Existing(id: alarm.id, fireAt: fireAt, isWaiting: alarm.state == .scheduled)
            }
        },
        schedule: { id, request in
            // Verbatim text: the copy is already in the app's language, and a
            // finished sentence never matches a catalog key.
            let attributes = AlarmAttributes<ShiftAlarmMetadata>(
                presentation: AlarmPresentation(
                    alert: .init(
                        title: LocalizedStringResource(stringLiteral: request.title),
                        stopButton: AlarmButton(
                            text: LocalizedStringResource(stringLiteral: request.stopLabel),
                            textColor: .white, systemImageName: "stop.fill"
                        ),
                        secondaryButton: AlarmButton(
                            text: LocalizedStringResource(stringLiteral: request.snoozeLabel),
                            textColor: .white, systemImageName: "repeat"
                        ),
                        secondaryButtonBehavior: .countdown
                    ),
                    countdown: .init(title: LocalizedStringResource(stringLiteral: request.snoozingLabel))
                ),
                metadata: ShiftAlarmMetadata(title: request.title, snoozeLabel: request.snoozingLabel),
                tintColor: OWCDesign.accent
            )
            let configuration = AlarmManager.AlarmConfiguration<ShiftAlarmMetadata>(
                countdownDuration: .init(preAlert: nil, postAlert: TimeInterval(ShiftAlarmSettings.snoozeMinutes * 60)),
                schedule: .fixed(request.fireAt),
                attributes: attributes
            )
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                return .scheduled
            } catch AlarmManager.AlarmError.maximumLimitReached {
                return .limitReached
            } catch {
                return .failed
            }
        },
        cancel: { try? AlarmManager.shared.cancel(id: $0) }
    )

    private static func authorization(_ state: AlarmManager.AuthorizationState) -> Authorization {
        switch state {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}

/// Keeps this device's AlarmKit alarms equal to the plan (plan 020 §3).
///
/// Alarms are one-off absolute times, never a weekly repeat that something
/// would have to wake up and cancel at expiry. Each run cancels the alarms the
/// plan no longer wants and adds the missing ones earliest first, so when the
/// system's limit is reached the nearest shifts are the ones covered. One
/// ordinary notification follows the last alarm that actually got in, when
/// more could follow after a refresh.
@MainActor
@Observable
final class ShiftAlarmService {
    struct Status: Equatable, Sendable {
        var authorization: ShiftAlarmSystem.Authorization
        /// Alarms waiting to ring that the plan still wants.
        var scheduledCount: Int
        /// The last alarm in the unbroken run from the next one: the date the
        /// alarms are actually good until.
        var coveredThrough: Date?
        var windowEnd: Date?
        var reachedSystemLimit: Bool
        var failedCount: Int
        var refreshReminderAt: Date?
        /// Notifications are off, so the refresh reminder cannot be relied on.
        var refreshReminderUnavailable: Bool
    }

    static let refreshIdentifier = "owc.alarm.refresh"
    /// How long after the last alarm's planned time the refresh reminder
    /// comes. Planned, not observed: nothing reports when the person stops it.
    static let refreshDelay: TimeInterval = 10 * 60

    private(set) var status: Status
    private let system: ShiftAlarmSystem
    private let notifications: NotificationService.ShiftCenter
    private var pending: Task<Void, Never>?
    private var generation = 0

    init(system: ShiftAlarmSystem = .system, notifications: NotificationService.ShiftCenter = .system) {
        self.system = system
        self.notifications = notifications
        status = Status(
            authorization: system.authorization(), scheduledCount: 0, coveredThrough: nil, windowEnd: nil,
            reachedSystemLimit: false, failedCount: 0, refreshReminderAt: nil, refreshReminderUnavailable: false
        )
    }

    @ObservationIgnored private var authorizationTask: Task<Void, Never>?

    /// Permission changes in Settings while the app is away. Picks up the
    /// latest plan each time, so a grant schedules and a revoke clears.
    func observeAuthorization(plan: @escaping @MainActor () -> ShiftAlarmPlan) {
        guard authorizationTask == nil else { return }
        authorizationTask = Task { @MainActor [weak self] in
            for await _ in AlarmManager.shared.authorizationUpdates {
                guard let self, !Task.isCancelled else { return }
                await self.reconcile(plan())
            }
        }
    }

    func requestAuthorization() async -> ShiftAlarmSystem.Authorization {
        let result = await system.requestAuthorization()
        status.authorization = result
        return result
    }

    /// Serialised: a run that is still adding alarms finishes before the next
    /// one reads what exists, so two runs never add the same alarm twice. A
    /// newer request supersedes queued ones.
    func reconcile(_ plan: ShiftAlarmPlan, now: Date = .now) async {
        generation += 1
        let mine = generation
        let previous = pending
        let task = Task { @MainActor in
            _ = await previous?.value
            guard mine == self.generation else { return }
            await self.perform(plan, now: now)
        }
        pending = task
        await task.value
        if mine == generation { pending = nil }
    }

    private func perform(_ plan: ShiftAlarmPlan, now: Date) async {
        let authorization = system.authorization()
        let existing = system.existing()
        guard plan.isEnabled, plan.windowEnd != nil, authorization == .authorized else {
            // Switched off, or the entitlement ended: nothing of ours stays,
            // including one ringing or snoozing right now. Other apps' and
            // the Clock app's alarms are never listed here.
            for alarm in existing { system.cancel(alarm.id) }
            await setRefreshReminder(nil, plan: plan)
            status = Status(
                authorization: authorization, scheduledCount: 0, coveredThrough: nil, windowEnd: plan.windowEnd,
                reachedSystemLimit: false, failedCount: 0, refreshReminderAt: nil,
                refreshReminderUnavailable: false
            )
            return
        }

        let wanted = plan.items.sorted { $0.alarm.fireAtMs < $1.alarm.fireAtMs }
        let wantedIDs = Set(wanted.map(\.systemID))
        // One that is ringing or snoozing has already left the plan (its time
        // has passed) but must be left to finish.
        for alarm in existing where alarm.isWaiting && !wantedIDs.contains(alarm.id) {
            system.cancel(alarm.id)
        }
        var held: [UUID: Date] = [:]
        for alarm in existing where alarm.isWaiting && wantedIDs.contains(alarm.id) {
            held[alarm.id] = alarm.fireAt ?? .distantFuture
        }

        var reachedLimit = false
        var failed = 0
        for item in wanted where held[item.systemID] == nil {
            let fireAt = Date(timeIntervalSince1970: item.alarm.fireAtMs / 1_000)
            let request = ShiftAlarmSystem.Request(
                fireAt: fireAt, title: item.title, stopLabel: plan.stopLabel,
                snoozeLabel: plan.snoozeLabel, snoozingLabel: plan.snoozingLabel
            )
            var outcome = await system.schedule(item.systemID, request)
            if outcome == .limitReached,
               let latest = held.max(by: { $0.value < $1.value }), latest.value > fireAt {
                // A later alarm gives its place to a nearer one.
                system.cancel(latest.key)
                held[latest.key] = nil
                outcome = await system.schedule(item.systemID, request)
            }
            switch outcome {
            case .scheduled: held[item.systemID] = fireAt
            case .limitReached: reachedLimit = true
            case .failed: failed += 1
            }
            if reachedLimit { break }
        }

        // Good until the last alarm with none missing before it.
        var coveredThrough: Date?
        for item in wanted {
            guard held[item.systemID] != nil else { break }
            coveredThrough = Date(timeIntervalSince1970: item.alarm.fireAtMs / 1_000)
        }
        let incomplete = reachedLimit || failed > 0
        let moreAfterRefresh = incomplete || (plan.windowIsLifetime && !wanted.isEmpty)
        let reminderAt = moreAfterRefresh
            ? coveredThrough.map { $0.addingTimeInterval(Self.refreshDelay) } ?? now.addingTimeInterval(Self.refreshDelay)
            : nil
        let delivered = await setRefreshReminder(reminderAt, plan: plan)
        status = Status(
            authorization: authorization,
            scheduledCount: held.count,
            coveredThrough: coveredThrough,
            windowEnd: plan.windowEnd,
            reachedSystemLimit: reachedLimit,
            failedCount: failed,
            refreshReminderAt: delivered ? reminderAt : nil,
            refreshReminderUnavailable: reminderAt != nil && !delivered
        )
    }

    /// Replaces the single refresh reminder, and clears one already shown,
    /// since this run has just refreshed. Returns whether a reminder is now
    /// waiting.
    @discardableResult
    private func setRefreshReminder(_ date: Date?, plan: ShiftAlarmPlan) async -> Bool {
        notifications.removePending([Self.refreshIdentifier])
        notifications.removeDelivered([Self.refreshIdentifier])
        guard let date, await notifications.authorization() == .allowed else { return false }
        let content = UNMutableNotificationContent()
        content.title = plan.refreshTitle
        content.body = plan.refreshBody
        content.sound = .default
        content.userInfo = ["route": AppRoute.shiftAlarms.rawValue]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        do {
            try await notifications.add(UNNotificationRequest(
                identifier: Self.refreshIdentifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
            return true
        } catch {
            return false
        }
    }
}

import Foundation
import Testing
import UserNotifications
@testable import App

/// Plan 020 §3: keeping AlarmKit equal to the plan, without the system.
@MainActor
@Suite("Shift alarm service")
struct ShiftAlarmServiceTests {
    /// An in-memory AlarmKit with a fixed capacity.
    @MainActor
    final class FakeAlarms {
        var authorization: ShiftAlarmSystem.Authorization = .authorized
        var capacity = Int.max
        var alarms: [UUID: ShiftAlarmSystem.Existing] = [:]
        var scheduleCalls: [UUID] = []

        var system: ShiftAlarmSystem {
            ShiftAlarmSystem(
                authorization: { self.authorization },
                requestAuthorization: { self.authorization },
                existing: { Array(self.alarms.values) },
                schedule: { id, request in
                    self.scheduleCalls.append(id)
                    guard self.alarms.count < self.capacity else { return .limitReached }
                    self.alarms[id] = .init(id: id, fireAt: request.fireAt, isWaiting: true)
                    return .scheduled
                },
                cancel: { self.alarms[$0] = nil }
            )
        }
    }

    @MainActor
    final class FakeNotifications {
        var allowed = true
        var pending: [String: Date] = [:]
        var bodies: [String: String] = [:]

        var center: NotificationService.ShiftCenter {
            NotificationService.ShiftCenter(
                authorization: { self.allowed ? .allowed : .denied },
                pendingIDs: { Array(self.pending.keys) },
                deliveredIDs: { [] },
                add: { request in
                    let trigger = request.trigger as? UNCalendarNotificationTrigger
                    self.pending[request.identifier] = trigger?.nextTriggerDate() ?? .distantFuture
                    self.bodies[request.identifier] = request.content.body
                },
                removePending: { ids in for id in ids { self.pending[id] = nil } },
                removeDelivered: { _ in }
            )
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// One alarm a day at `now` plus `days` days.
    private static func plan(
        days: [Int], lifetime: Bool = false, renews: Bool = false, enabled: Bool = true, windowDays: Int? = 30
    ) -> ShiftAlarmPlan {
        ShiftAlarmPlan(
            isEnabled: enabled,
            windowEnd: windowDays.map { now.addingTimeInterval(Double($0) * 86_400) },
            windowIsLifetime: lifetime,
            windowRenews: renews,
            items: days.map { day in
                let fire = (now.timeIntervalSince1970 + Double(day) * 86_400) * 1_000
                let alarm = PlannedShiftAlarm(
                    id: ShiftAlarmPlanner.stableID(dayKey: "d\(day)", fireAtMs: fire, shiftStartAtMs: fire + 3_600_000, shiftName: nil),
                    fireAtMs: fire, shiftStartAtMs: fire + 3_600_000, dayKey: "d\(day)", shiftTypeID: nil, shiftName: nil
                )
                return .init(alarm: alarm, systemID: alarm.id, title: "Work \(day)")
            },
            stopLabel: "Stop", snoozeLabel: "Snooze", snoozingLabel: "Snoozing",
            refreshTitle: "Refresh", refreshBody: "Open DoneAt", renewBody: "Next period"
        )
    }

    private static func date(day: Int) -> Date { now.addingTimeInterval(Double(day) * 86_400) }

    @Test("Wanted alarms are added once, earliest first; a subscription gets no refresh reminder, lifetime does")
    func schedulesAndCovers() async {
        let alarms = FakeAlarms()
        let notifications = FakeNotifications()
        let service = ShiftAlarmService(system: alarms.system, notifications: notifications.center)

        await service.reconcile(Self.plan(days: [3, 1, 2]), now: Self.now)
        #expect(alarms.scheduleCalls.count == 3)
        #expect(alarms.alarms.values.compactMap(\.fireAt).sorted() == [1, 2, 3].map(Self.date(day:)))
        #expect(service.status.scheduledCount == 3)
        #expect(service.status.coveredThrough == Self.date(day: 3))
        #expect(!service.status.reachedSystemLimit)
        #expect(service.status.refreshReminderAt == nil)
        #expect(notifications.pending.isEmpty)

        // Nothing new to add the second time.
        await service.reconcile(Self.plan(days: [1, 2, 3]), now: Self.now)
        #expect(alarms.scheduleCalls.count == 3)

        await service.reconcile(Self.plan(days: [1, 2, 3], lifetime: true), now: Self.now)
        #expect(service.status.refreshReminderAt == Self.date(day: 3).addingTimeInterval(ShiftAlarmService.refreshDelay))
        #expect(notifications.pending[ShiftAlarmService.refreshIdentifier] != nil)
    }

    @Test("A changed plan cancels what it no longer wants and adds the rest")
    func replacesStaleAlarms() async {
        let alarms = FakeAlarms()
        let service = ShiftAlarmService(system: alarms.system, notifications: FakeNotifications().center)
        await service.reconcile(Self.plan(days: [1, 2, 3]), now: Self.now)
        await service.reconcile(Self.plan(days: [2, 4]), now: Self.now)
        #expect(alarms.alarms.values.compactMap(\.fireAt).sorted() == [2, 4].map(Self.date(day:)))
        #expect(service.status.coveredThrough == Self.date(day: 4))
    }

    @Test("At the system limit the nearest shifts win, coverage stops at the gap, and a refresh reminder follows")
    func systemLimit() async {
        let alarms = FakeAlarms()
        alarms.capacity = 3
        let notifications = FakeNotifications()
        let service = ShiftAlarmService(system: alarms.system, notifications: notifications.center)

        await service.reconcile(Self.plan(days: [1, 2, 3, 4, 5]), now: Self.now)
        #expect(alarms.alarms.values.compactMap(\.fireAt).sorted() == [1, 2, 3].map(Self.date(day:)))
        #expect(service.status.reachedSystemLimit)
        #expect(service.status.coveredThrough == Self.date(day: 3))
        // Even a subscription gets the reminder: refreshing really does add more.
        #expect(service.status.refreshReminderAt == Self.date(day: 3).addingTimeInterval(ShiftAlarmService.refreshDelay))

        // A nearer shift appears: the latest alarm gives up its place.
        await service.reconcile(Self.plan(days: [0, 1, 2, 3, 4, 5]), now: Self.now)
        #expect(alarms.alarms.values.compactMap(\.fireAt).sorted() == [0, 1, 2].map(Self.date(day:)))
        #expect(service.status.coveredThrough == Self.date(day: 2))
    }

    @Test("A ringing alarm is left to finish, unless alarms are switched off or the entitlement ends")
    func ringingAlarms() async {
        let alarms = FakeAlarms()
        let service = ShiftAlarmService(system: alarms.system, notifications: FakeNotifications().center)
        let ringing = UUID()
        alarms.alarms[ringing] = .init(id: ringing, fireAt: Self.now, isWaiting: false)

        await service.reconcile(Self.plan(days: [1]), now: Self.now)
        #expect(alarms.alarms[ringing] != nil)

        await service.reconcile(Self.plan(days: [1], windowDays: nil), now: Self.now)
        #expect(alarms.alarms.isEmpty)

        alarms.alarms[ringing] = .init(id: ringing, fireAt: Self.now, isWaiting: false)
        await service.reconcile(Self.plan(days: [1], enabled: false), now: Self.now)
        #expect(alarms.alarms.isEmpty)
        #expect(service.status.scheduledCount == 0)
    }

    @Test("Without alarm permission nothing is added; without notifications the reminder is reported missing")
    func permissions() async {
        let alarms = FakeAlarms()
        alarms.authorization = .denied
        let notifications = FakeNotifications()
        notifications.allowed = false
        let service = ShiftAlarmService(system: alarms.system, notifications: notifications.center)

        await service.reconcile(Self.plan(days: [1, 2]), now: Self.now)
        #expect(alarms.scheduleCalls.isEmpty)
        #expect(service.status.authorization == .denied)

        alarms.authorization = .authorized
        await service.reconcile(Self.plan(days: [1, 2], lifetime: true), now: Self.now)
        #expect(service.status.scheduledCount == 2)
        #expect(service.status.refreshReminderAt == nil)
        #expect(service.status.refreshReminderUnavailable)
    }

    @Test("A subscription set to renew gets a next-period reminder after its last alarm; one that is not gets none")
    func renewalReminder() async {
        let alarms = FakeAlarms()
        let notifications = FakeNotifications()
        let service = ShiftAlarmService(system: alarms.system, notifications: notifications.center)

        await service.reconcile(Self.plan(days: [1, 2], renews: true), now: Self.now)
        #expect(service.status.refreshReminderAt == Self.date(day: 2).addingTimeInterval(ShiftAlarmService.refreshDelay))
        #expect(notifications.bodies[ShiftAlarmService.refreshIdentifier] == "Next period")

        // Auto-renew switched off: the period ends and nothing suggests otherwise.
        await service.reconcile(Self.plan(days: [1, 2]), now: Self.now)
        #expect(service.status.refreshReminderAt == nil)
        #expect(notifications.pending[ShiftAlarmService.refreshIdentifier] == nil)

        // Short of the limit, refreshing adds more this period: the ordinary text.
        alarms.capacity = 3
        await service.reconcile(Self.plan(days: [1, 2, 3, 4], renews: true), now: Self.now)
        #expect(notifications.bodies[ShiftAlarmService.refreshIdentifier] == "Open DoneAt")
    }
}

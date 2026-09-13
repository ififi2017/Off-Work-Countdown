#if DEBUG
import Foundation

@MainActor
final class DebugScenarioController {
    static let resetKey = "ios.native.debugResetNextLaunch"
    let shifts: ShiftSessionStore
    private let defaults: UserDefaults
    private let recordActions: RecordsActions
    private let life: LifeSummaryModel

    init(
        shifts: ShiftSessionStore,
        defaults: UserDefaults,
        actions: RecordsActions,
        life: LifeSummaryModel
    ) {
        self.shifts = shifts
        self.defaults = defaults
        self.recordActions = actions
        self.life = life
    }

    func scheduleDebugResetOnNextLaunch() {
        defaults.set(true, forKey: Self.resetKey)
    }

    @discardableResult
    func debugSeedSampleRecords(now: Date = .now) -> RecordCommand<Bool> {
        let records = shifts.records
        return records.submitCommand { [self] in
        let marker = DebugRecordSeed.id(0)
        guard !records.state.observations.contains(where: { $0.eventID == marker }) else { return false }
        records.ensureSeeded(
            hours: shifts.session.hoursConfiguration(at: now), at: now,
            timeZone: shifts.preferences.recordsTimeZone
        )
        let calendar = shifts.preferences.recordsCalendar
        let zone = shifts.preferences.recordsTimeZone
        let today = calendar.startOfDay(for: now)
        guard let snapshotID = records.currentSnapshotID(on: today) ?? records.state.snapshots.first?.id else {
            return false
        }
        var cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var index = 0
        for _ in 0..<32 {
            if (2...6).contains(calendar.component(.weekday, from: cursor)) {
                seedSampleWorkday(cursor, index: index, snapshotID: snapshotID, calendar: calendar, zone: zone)
                index += 1
            }
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        _ = life.saveLifeProfile(
            birthYear: 1992, workStartedYear: 2015, retirementAge: 60,
            sleepHours: 7.5, hidesExactAges: false
        ).synchronousResult
        records.upsertFocusTask(.init(
            id: DebugRecordSeed.id(800), createdAt: now, plannedForDate: today,
            scheduledStartAt: nil, title: "Weekly notes", estimatedPomodoros: 1,
            completedAt: nil, sortIndex: 0, editedAt: now, editCount: 0,
            editTieBreaker: DebugRecordSeed.id(801)
        ))
        records.upsertFocusTask(.init(
            id: DebugRecordSeed.id(802), createdAt: now, plannedForDate: today,
            scheduledStartAt: nil, title: "Review last month", estimatedPomodoros: 2,
            completedAt: now, sortIndex: 1, editedAt: now, editCount: 0,
            editTieBreaker: DebugRecordSeed.id(803)
        ))
        return true
        }
    }

    private func seedSampleWorkday(
        _ day: Date, index: Int, snapshotID: UUID, calendar: Calendar, zone: TimeZone
    ) {
        let records = shifts.records
        let dayKey = RecordJSON.dayKey(day, calendar: calendar)
        let startMinutes: Int
        let stopMinutes: Int
        switch index {
        case 2: (startMinutes, stopMinutes) = (8 * 60 + 25, 18 * 60)
        case 5:
            _ = recordActions.markDayNotWorking(dayKey: dayKey).synchronousResult
            return
        case 8:
            (startMinutes, stopMinutes) = (9 * 60, 16 * 60 + 10)
            _ = recordActions.saveCustomHours(
                dayKey: dayKey, startMinutes: startMinutes, endMinutes: stopMinutes
            ).synchronousResult
        default:
            (startMinutes, stopMinutes) = (9 * 60 + index % 7, 18 * 60 + index % 5)
        }
        let started = calendar.date(
            bySettingHour: startMinutes / 60, minute: startMinutes % 60, second: 0, of: day
        ) ?? day
        let stopped = calendar.date(
            bySettingHour: stopMinutes / 60, minute: stopMinutes % 60, second: 0, of: day
        ) ?? day
        records.recordObservation(
            kind: .countdownStarted,
            eventID: index == 0 ? DebugRecordSeed.id(0) : DebugRecordSeed.id(100 + index * 2),
            shiftAnchorDate: day, occurredAt: started, snapshotID: snapshotID,
            timeZoneIdentifier: zone.identifier
        )
        records.recordObservation(
            kind: .countdownStopped, eventID: DebugRecordSeed.id(100 + index * 2 + 1),
            shiftAnchorDate: day, occurredAt: stopped, snapshotID: snapshotID,
            timeZoneIdentifier: zone.identifier
        )
        if index == 11 {
            let overtimeEnd = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: day) ?? day
            let plannedEnd = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? stopped
            let payload = try? JSONEncoder().encode(OvertimeDeclarationPayload(
                overtimeEndAtMs: overtimeEnd.timeIntervalSince1970 * 1_000,
                plannedEndAtMs: plannedEnd.timeIntervalSince1970 * 1_000
            ))
            records.recordObservation(
                kind: .overtimeDeclared, eventID: DebugRecordSeed.id(700),
                shiftAnchorDate: day, occurredAt: stopped, snapshotID: snapshotID,
                valueData: payload, timeZoneIdentifier: zone.identifier
            )
        }
    }

    func debugSeedSampleConflict(at date: Date = .now) async {
        let records = shifts.records
        guard records.state.sync.conflicts.isEmpty,
              let local = records.state.overrides.first(where: { $0.kind == .notWorking })
        else { return }
        var incoming = local
        incoming.kind = .confirmedAsScheduled
        incoming.note = "Imported correction"
        incoming.editedAt = local.editedAt
        incoming.editCount = local.editCount
        incoming.editTieBreaker = DebugRecordSeed.id(900)
        let calendar = RecordsSyncPayload.fileCalendar(for: records.state)
        guard let localPayload = RecordsSyncPayload.encode(.override(local), calendar: calendar),
              let incomingPayload = RecordsSyncPayload.encode(.override(incoming), calendar: calendar)
        else { return }
        let conflicts: [SyncConflictCopy] = [.init(
            id: DebugRecordSeed.id(901), entityType: .dayOverride, logicalKey: local.dayKey,
            payload: incomingPayload, lostAtMs: date.timeIntervalSince1970 * 1_000,
            source: nil, localPayload: localPayload, incomingPayload: incomingPayload,
            localEditedAtMs: local.editedAt.timeIntervalSince1970 * 1_000,
            incomingEditedAtMs: incoming.editedAt.timeIntervalSince1970 * 1_000,
            currentWinner: .local
        )]
        _ = await records.commitSyncState { sync, _ in sync.conflicts = conflicts }
    }

    func activateDebugTimerScenario(_ scenario: DebugTimerScenario, at date: Date = .now) {
        shifts.session.debugTimerSession = .init(
            scenario: scenario, realAnchor: date, virtualAnchor: DebugTimerScenario.virtualStartDate
        )
        shifts.resetCelebratedSession()
    }
}
#endif

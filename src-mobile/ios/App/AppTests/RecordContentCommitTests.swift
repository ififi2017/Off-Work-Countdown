import Foundation
import Testing
@testable import App

@MainActor
@Suite("Record content commits")
struct RecordContentCommitTests {
    @Test("Queries inside a batch see every edit while consumers receive one committed change")
    func queriesDuringBatch() throws {
        let suite = "RecordBatchQueries.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
        let day = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)
        ))
        let key = RecordJSON.dayKey(day, calendar: store.preferences.recordsCalendar)
        store.records.ensureSeeded(hours: store.session.hoursConfiguration(at: day), at: day, timeZone: store.preferences.recordsTimeZone)
        let snapshotID = try #require(store.records.state.snapshots.first?.id)
        #expect(store.queries.observations(on: day).isEmpty)
        #expect(!store.queries.isRecordedDay(key))
        let initialKey = store.life.lifeViewModelCacheKey(now: day)
        let revision = store.records.historyRevision
        var notifications = 0
        store.records.onDirty = { notifications += 1 }
        store.records.withBatchedWrites {
            for index in 0..<2 {
                let segments = [NativeShiftSegment(startAtMs: day.timeIntervalSince1970 * 1_000,
                    endAtMs: day.addingTimeInterval(Double((index + 1) * 3_600)).timeIntervalSince1970 * 1_000)]
                store.records.upsertOverride(DayOverride(
                    dayKey: key, shiftAnchorDate: day, kind: .customSegments,
                    segments: segments, timeZoneIdentifier: "UTC"
                ))
                store.records.recordObservation(kind: .countdownStarted, eventID: UUID(),
                    shiftAnchorDate: day, occurredAt: day.addingTimeInterval(Double(index)),
                    snapshotID: snapshotID, timeZoneIdentifier: "UTC")
                #expect(store.queries.resolvedDays(from: day, through: day, now: day).first?.segments == segments)
                #expect(store.queries.observations(on: day).count == index + 1)
                #expect(store.queries.isRecordedDay(key))
                #expect(store.life.lifeViewModelCacheKey(now: day).observations.count == index + 1)
                #expect(store.records.historyRevision == revision)
                #expect(notifications == 0)
            }
        }
        #expect(store.records.historyRevision == revision + 1)
        #expect(notifications == 1)
        #expect(store.queries.observations(on: day).count == 2)
        #expect(store.life.lifeViewModelCacheKey(now: day) != initialKey)
    }

    @Test("Repeating unchanged local rows preserves stamps, outbox and projection revisions")
    func repeatedRows() throws {
        let records = RecordCoordinator.inMemory()
        let date = Date(timeIntervalSince1970: 1_788_739_200)
        let task = FocusTask(
            id: UUID(), createdAt: date, title: "Write", estimatedPomodoros: 1,
            sortIndex: 0, editedAt: date, editCount: 0, editTieBreaker: UUID()
        )
        let session = FocusSession(
            id: UUID(), taskID: task.id, shiftAnchorDate: date,
            startedAt: date, plannedEndAt: date.addingTimeInterval(1_500),
            editedAt: date, editCount: 0, editTieBreaker: UUID()
        )
        let planning = FocusPlanningConfiguration(
            planning: .init(), timerSettings: .default,
            editedAt: date, editCount: 0, editTieBreaker: UUID()
        )
        let profile = LifeProfile(
            birthYear: 1990, retirementAge: 60,
            editedAt: date, editCount: 0, editTieBreaker: UUID()
        )
        let override = DayOverride(
            dayKey: "2026-09-06", shiftAnchorDate: date,
            kind: .notWorking, segments: [], timeZoneIdentifier: "UTC"
        )
        let exception = CalendarException(
            dayKey: "2026-09-06#user", date: date, effect: .rest,
            origin: .user, isCleared: false, editedAt: date,
            editCount: 0, editTieBreaker: UUID(), timeZoneIdentifier: "UTC"
        )
        func submit() {
            records.upsertFocusTask(task)
            records.upsertFocusSession(session)
            records.upsertFocusPlanningConfiguration(planning)
            records.updateLifeProfile(profile)
            records.applyDayLayers(override: override, exception: exception)
        }
        submit()
        let committed = records.state
        let revision = records.revision
        let contentRevision = records.contentRevision
        var notifications = 0
        records.onDirty = { notifications += 1 }
        submit()
        records.applyDayLayers(override: nil, exception: nil)
        #expect(records.state == committed)
        #expect(records.revision == revision)
        #expect(records.contentRevision == contentRevision)
        #expect(notifications == 0)

        // Deletion and completion are business content, not metadata.
        var deleted = task
        deleted.deletedAt = date
        records.upsertFocusTask(deleted)
        #expect(records.state.focusTasks.first?.deletedAt == date)
        #expect(records.revision == revision + 1)
        #expect(notifications == 1)
    }

    @Test("Reapplying unchanged Focus configuration does not invalidate services")
    func unchangedFocusPlanning() throws {
        let suite = "FocusConfigurationNoOp.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        store.focus.persistFocusPlanning()
        let state = store.records.state
        let signal = ServiceScheduleSignal(shifts: store.shifts)
        store.focus.persistFocusPlanning()
        #expect(store.records.state == state)
        #expect(ServiceScheduleSignal(shifts: store.shifts) == signal)
    }
}

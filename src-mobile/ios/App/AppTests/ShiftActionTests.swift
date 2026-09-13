import Foundation
import Testing
@testable import App

@MainActor
@Suite("Shift command admission without an application or scene")
struct ShiftActionTests {
    private func fixture(defaults: UserDefaults, records: RecordCoordinator) -> ShiftSessionStore {
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        let preferences = PreferencesStore(defaults: defaults, records: records)
        let text = AppText(preferences: preferences)
        let session = ShiftSession(defaults: defaults, preferences: preferences, text: text)
        let plus = PlusEntitlement(defaults: defaults)
        plus.debugSetAuthorized(true)
        let queries = RecordsQueries(records: records, plus: plus, localizer: text.localizer, sources: .init(
            calendar: { preferences.recordsCalendar }, hours: { session.hoursConfiguration(at: $0) },
            rules: { session.rulesInput(at: $0, using: $1) }, snapshot: { session.snapshot(at: $0) },
            isCounting: { session.countdownStarted }, salaryIsVisible: { false },
            salaryType: { preferences.salaryType }, language: { preferences.languageCode }
        ))
        let focus = FocusStore(records: records, defaults: defaults, plus: plus, sources: .init(
            calendar: { preferences.recordsCalendar }, snapshot: { session.snapshot(at: $0) },
            scheduleEnabled: { session.followsSchedule(at: $0) },
            shouldQuerySnapshot: { session.shouldQuerySnapshot(at: $0) },
            isWorkday: { shift, _ in shift.isWorkday }, overtimeEnd: { session.overtimeEndAtMs },
            microBreakEnabled: { preferences.microBreakEnabled },
            text: { text.t($0, values: $1) }, count: { text.formatCount($0) },
            time: { text.formatTime($0) }
        ))
        return ShiftSessionStore(session: session, records: records, queries: queries,
            focus: focus, plus: plus, defaults: defaults)
    }

    private func date(_ shifts: ShiftSessionStore, hour: Int) throws -> Date {
        try #require(shifts.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: hour)))
    }

    @Test("Invalid start input leaves the stopped session, early finish and archive unchanged")
    func invalidStartIsAtomic() throws {
        let suite = "ShiftAdmission.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shifts = fixture(defaults: defaults, records: .inMemory())
        shifts.preferences.applyPreferences { $0.scheduleMode = .off }
        shifts.session.earlyOffAtMs = 123
        shifts.session.earlyStartAtMs = 456
        let previous = shifts.records.state
        #expect(!shifts.startCountdown(startMinutes: 8 * 60, endMinutes: -1, at: try date(shifts, hour: 10)).synchronousResult)
        #expect(!shifts.session.countdownStarted)
        #expect(shifts.session.earlyOffAtMs == 123)
        #expect(shifts.session.earlyStartAtMs == 456)
        #expect(shifts.preferences.startMinutes == 9 * 60)
        #expect(shifts.records.state == previous)
    }

    @Test("Repeated session actions do not create extra archive writes or completion events")
    func repeatedActionsAreNoOps() async throws {
        let suite = "ShiftRepeat.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "shift-repeat-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let shifts = fixture(defaults: defaults, records: RecordCoordinator(fileURL: file))
        shifts.preferences.completeSetup(enableNotifications: false)
        let beforeStart = try date(shifts, hour: 8)
        let during = try date(shifts, hour: 10)
        let overtime = try date(shifts, hour: 19)
        let actions: [() -> Bool] = [
            { shifts.startCountdown(at: beforeStart).synchronousResult },
            { shifts.clockInEarly(at: beforeStart).synchronousResult },
            { shifts.clockOffEarly(at: during).synchronousResult },
            { shifts.applyOvertime(date: overtime, declaredAt: during).synchronousResult }
        ]
        for action in actions {
            #expect(action())
            try await shifts.records.flush()
            let previous = shifts.records.state
            let writes = shifts.records.archiveWriteCount
            let revision = shifts.records.revision
            shifts.markCelebrated(endAtMs: 123)
            #expect(!action())
            try await shifts.records.flush()
            #expect(shifts.records.state == previous)
            #expect(shifts.records.revision == revision)
            #expect(shifts.records.archiveWriteCount == writes)
            #expect(shifts.lastCelebratedEndAtMs == 123)
        }
        #expect(shifts.applyOvertime(date: overtime.addingTimeInterval(3600), declaredAt: during).synchronousResult)
        #expect(shifts.lastCelebratedEndAtMs == 0)
        try await shifts.records.flush()
    }

    @Test("A protected archive rejects all session mutations before touching device state")
    func protectedArchiveRejectsActions() throws {
        let suite = "ShiftProtected.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "shift-protected-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("damaged".utf8).write(to: file)
        let records = RecordCoordinator(fileURL: file)
        let shifts = fixture(defaults: defaults, records: records)
        let during = try date(shifts, hour: 10)
        #expect(records.blocksWrites)
        let previous = records.state
        let deviceState = defaults.dictionaryRepresentation() as NSDictionary
        #expect(!shifts.startCountdown(at: during).synchronousResult)
        #expect(!shifts.clockOffEarly(at: during).synchronousResult)
        #expect(!shifts.clockInEarly(at: try date(shifts, hour: 8)).synchronousResult)
        #expect(!shifts.applyOvertime(date: try date(shifts, hour: 19), declaredAt: during).synchronousResult)
        #expect(!shifts.cancelManualTiming().synchronousResult)
        #expect(!shifts.stopCountdown(at: during).synchronousResult)
        #expect(!shifts.applyScheduleChange(ScheduleFieldChange(endMinutes: 18 * 60), decision: .applyToToday, at: during).synchronousResult)
        shifts.undoEarlyClockOff()
        shifts.undoEarlyClockIn()
        shifts.clearOvertime()
        #expect(records.state == previous)
        #expect(defaults.dictionaryRepresentation() as NSDictionary == deviceState)
        #expect(try Data(contentsOf: file) == Data("damaged".utf8))
    }

    @Test("Ordinary disk failure retains an accepted edit and admits the next edit")
    func failedWriteKeepsEditableMemory() async throws {
        let suite = "ShiftWriteFailure.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "shift-failed-\(UUID()).json")
        let records = RecordCoordinator(fileURL: file, prepareArchive: { _, _ in
            throw RecordPersistenceError.writeFailed
        })
        let shifts = fixture(defaults: defaults, records: records)
        shifts.preferences.completeSetup(enableNotifications: false)
        let during = try date(shifts, hour: 10)
        #expect(shifts.startCountdown(startMinutes: 8 * 60, endMinutes: 18 * 60, at: during).synchronousResult)
        await #expect(throws: RecordPersistenceError.writeFailed) { try await records.flush() }
        #expect(!records.blocksWrites)
        #expect(shifts.session.countdownStarted)
        #expect(shifts.preferences.endMinutes == 18 * 60)
        #expect(shifts.applyScheduleChange(ScheduleFieldChange(endMinutes: 19 * 60), decision: .applyToToday, at: during).synchronousResult)
        #expect(shifts.preferences.endMinutes == 19 * 60)
        await #expect(throws: RecordPersistenceError.writeFailed) { try await records.flush() }
    }
    @Test("Session marks and manual reset use the session civil midnight", arguments: ["UTC", "Asia/Tokyo"])
    func sessionMidnight(timeZoneIdentifier: String) throws {
        let suite = "ShiftCivilMidnight.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shifts = fixture(defaults: defaults, records: .inMemory())
        shifts.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = timeZoneIdentifier }
        let calendar = shifts.preferences.recordsCalendar
        let beforeStart = try date(shifts, hour: 8)
        let midnight = try #require(calendar.date(from:
            DateComponents(year: 2026, month: 9, day: 8)))
        #expect(shifts.startCountdown(at: beforeStart).synchronousResult)
        #expect(shifts.clockInEarly(at: beforeStart).synchronousResult)
        #expect(shifts.session.earlyStartUntilMs == midnight.timeIntervalSince1970 * 1_000)
        shifts.applyScheduleChange(ScheduleFieldChange(scheduleMode: .off), decision: .applyToToday, at: beforeStart)
        #expect(shifts.startCountdown(at: beforeStart).synchronousResult)
        let identity = shifts.session.sessionID
        // New manual sessions intentionally follow the device's current zone
        // when it differs from Records. Keep that session zone through settlement.
        let manualShift = try #require(shifts.session.snapshot(at: beforeStart))
        let manualCalendar = shifts.session.countdownCalendar
        let manualMidnight = try #require(manualCalendar.date(byAdding: .day, value: 1,
            to: manualCalendar.startOfDay(for: manualShift.endDate)))
        shifts.reconcileCountdownSession(at: manualMidnight.addingTimeInterval(-60))
        #expect(shifts.session.countdownStarted)
        #expect(shifts.session.sessionID == identity)
        shifts.reconcileCountdownSession(at: manualMidnight.addingTimeInterval(60))
        #expect(!shifts.session.countdownStarted)
    }

}

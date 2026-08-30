import Foundation
import Testing
@testable import App

@MainActor
@Test("A retry reuses eventID and a second click is a new observation")
func observationEventIDIsIdempotentPerWrite() {
    let records = RecordCoordinator.inMemory()
    let day = startOf(2026, 8, 24)
    let snapshotID = UUID()
    let firstID = UUID()
    records.recordObservation(
        kind: .countdownStarted,
        eventID: firstID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: snapshotID
    )
    records.recordObservation(
        kind: .countdownStarted,
        eventID: firstID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: snapshotID
    )
    records.recordObservation(
        kind: .countdownStarted,
        eventID: UUID(),
        shiftAnchorDate: day,
        occurredAt: day.addingTimeInterval(1),
        snapshotID: snapshotID
    )
    #expect(records.state.observations.count == 2)
}

@MainActor
@Test("First-seen is once per shift day; start/stop/overtime stay distinct")
func observationKindsStayDistinct() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .off
    let monday = date(2026, 8, 24, 9)
    store.noteTimerSurfaceVisible(at: monday)
    store.noteTimerSurfaceVisible(at: monday.addingTimeInterval(60))
    store.startCountdown(at: monday)
    store.stopCountdown(at: monday.addingTimeInterval(30))
    store.startCountdown(at: monday.addingTimeInterval(45))
    store.applyOvertime(date: monday.addingTimeInterval(90))

    let kinds = store.records.state.observations.map(\.kind)
    #expect(kinds.filter { $0 == .timerSurfaceFirstSeen }.count == 1)
    #expect(kinds.filter { $0 == .countdownStarted }.count == 2)
    #expect(kinds.filter { $0 == .countdownStopped }.count == 1)
    #expect(kinds.filter { $0 == .overtimeDeclared }.count == 1)
}

@MainActor
@Test("Reconcile reconnects without writing another start")
func reconcileDoesNotRecordStart() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    let monday = date(2026, 8, 24, 10)
    store.startCountdown(at: monday)
    let afterStart = store.records.state.observations.filter { $0.kind == .countdownStarted }.count
    _ = store.reconcileCountdownSession(at: monday.addingTimeInterval(60))
    let afterReconcile = store.records.state.observations.filter { $0.kind == .countdownStarted }.count
    #expect(afterStart == 1)
    #expect(afterReconcile == 1)
}

@MainActor
@Test("Overnight first-seen keys the shift start day")
func overnightObservationKeysStartDay() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.startMinutes = 22 * 60
    store.endMinutes = 6 * 60
    store.workdays = [5]
    store.scheduleMode = .classic
    let saturdayMorning = date(2026, 8, 29, 1)
    store.noteTimerSurfaceVisible(at: saturdayMorning)
    let observation = store.records.state.observations.first { $0.kind == .timerSurfaceFirstSeen }
    #expect(observation != nil)
    #expect(OffWorkStore.dayKey(for: observation!.shiftAnchorDate) == "2026-08-28")
}

@MainActor
@Test("Deleted observations are not rebuilt from the same eventID")
func erasedObservationIsNotRecreated() {
    let records = RecordCoordinator.inMemory()
    let eventID = UUID()
    let day = startOf(2026, 8, 24)
    records.recordObservation(
        kind: .countdownStarted,
        eventID: eventID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: UUID()
    )
    records.erase(.workObservation, key: eventID.uuidString, at: day)
    records.recordObservation(
        kind: .countdownStarted,
        eventID: eventID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: UUID()
    )
    #expect(records.state.observations.isEmpty)
}

@MainActor
@Test("A seeded store can resolve a week of schedule days")
func resolvedDaysUseTheSeededSnapshot() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    let from = startOf(2026, 8, 24)
    let through = startOf(2026, 8, 30)
    let days = store.resolvedDays(from: from, through: through)
    #expect(days.count == 7)
    #expect(days.filter(\.isScheduledWorkday).count == 5)
    #expect(days[0].layer == .schedule)
    #expect(days[5].isScheduledWorkday == false)
}

@MainActor
@Test("Coordinator export then import after erase still skips")
func coordinatorImportHonorsErasedIDs() throws {
    let records = RecordCoordinator.inMemory()
    let hours = ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "17:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
    records.ensureSeeded(hours: hours, at: startOf(2026, 8, 24))
    let periodID = records.state.periods[0].id
    let data = try records.exportJSON(exportedAt: startOf(2026, 8, 24), timeZone: TimeZone(secondsFromGMT: 0)!)
    records.erase(.careerPeriod, key: periodID.uuidString, at: startOf(2026, 8, 25))
    let report = try records.import(data, mode: .skipErased)
    #expect(report.skippedErased[.careerPeriod] == 1)
    #expect(records.state.periods.isEmpty)
}

@MainActor
@Test("Migrating the records time zone keeps civil day keys")
func migrateCalendarTimeZoneKeepsDayKeys() {
    let records = RecordCoordinator.inMemory()
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let hours = ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "17:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
    records.ensureSeeded(hours: hours, at: startOf(2026, 8, 24), timeZone: shanghai)
    let snapshotEditCount = records.state.snapshots[0].editCount
    var shanghaiCalendar = Calendar(identifier: .gregorian)
    shanghaiCalendar.timeZone = shanghai
    let civilAnchor = shanghaiCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
    records.upsertException(
        CalendarException(
            dayKey: "2026-08-24#user",
            date: civilAnchor,
            effect: .rest,
            origin: .user,
            isCleared: false,
            regionIdentifier: nil,
            datasetVersion: nil,
            label: nil,
            editedAt: civilAnchor,
            editCount: 1,
            editTieBreaker: recordID(20),
            timeZoneIdentifier: shanghai.identifier
        )
    )
    let occurredAt = Date(timeIntervalSince1970: 1_777_000_123)
    records.recordObservation(
        kind: .countdownStarted,
        eventID: recordID(21),
        shiftAnchorDate: civilAnchor,
        occurredAt: occurredAt,
        snapshotID: records.state.snapshots[0].id,
        timeZoneIdentifier: shanghai.identifier
    )
    records.updateLifeProfile(
        LifeProfile(
            workStartedOn: civilAnchor,
            editedAt: civilAnchor,
            editCount: 2,
            editTieBreaker: recordID(22)
        )
    )
    records.upsertOverride(
        DayOverride(
            dayKey: "2026-08-24",
            shiftAnchorDate: startOf(2026, 8, 24),
            kind: .notWorking,
            segments: [],
            timeZoneIdentifier: shanghai.identifier
        )
    )
    records.migrateCalendarTimeZone(to: "America/Los_Angeles", at: startOf(2026, 8, 25))
    #expect(records.state.periods[0].timeZoneIdentifier == "America/Los_Angeles")
    var losAngelesCalendar = Calendar(identifier: .gregorian)
    losAngelesCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    #expect(RecordJSON.dayKey(records.state.periods[0].startsOn, calendar: losAngelesCalendar) == "2000-01-01")
    #expect(RecordJSON.dayKey(records.state.snapshots[0].effectiveFrom, calendar: losAngelesCalendar) == "2000-01-01")
    #expect(records.state.snapshots[0].editCount == snapshotEditCount + 1)
    #expect(records.state.overrides[0].dayKey == "2026-08-24")
    #expect(records.state.overrides[0].timeZoneIdentifier == "America/Los_Angeles")
    #expect(RecordJSON.dayKey(records.state.overrides[0].shiftAnchorDate, calendar: losAngelesCalendar) == "2026-08-24")
    #expect(RecordJSON.dayKey(records.state.exceptions[0].date, calendar: losAngelesCalendar) == "2026-08-24")
    #expect(RecordJSON.dayKey(records.state.observations[0].shiftAnchorDate, calendar: losAngelesCalendar) == "2026-08-24")
    #expect(records.state.observations[0].occurredAt == occurredAt)
    #expect(RecordJSON.dayKey(records.state.lifeProfile!.workStartedOn!, calendar: losAngelesCalendar) == "2026-08-24")
    #expect(records.state.lifeProfile!.editCount == 3)
}

@MainActor
@Test("Records year bounds stay on this year unless authored rows are older")
func recordsYearBoundsIgnoreSeededCareerStart() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
    let (thisYearFrom, thisYearThrough) = RecordsDesignView.recordsYearBounds(
        for: today,
        earliest: nil,
        calendar: calendar
    )
    #expect(RecordJSON.dayKey(thisYearFrom, calendar: calendar) == "2026-01-01")
    #expect(RecordJSON.dayKey(thisYearThrough, calendar: calendar) == "2026-12-31")

    let authored = calendar.date(from: DateComponents(year: 2024, month: 3, day: 1))!
    let (authoredFrom, authoredThrough) = RecordsDesignView.recordsYearBounds(
        for: today,
        earliest: authored,
        calendar: calendar
    )
    #expect(RecordJSON.dayKey(authoredFrom, calendar: calendar) == "2024-03-01")
    #expect(RecordJSON.dayKey(authoredThrough, calendar: calendar) == "2026-12-31")
}

@MainActor
@Test("Archive banners split damage from a save failure")
func archiveBannerDistinguishesDamageFromSaveFailure() {
    #expect(RecordsArchiveBanner(error: .invalidArchive) == .damaged)
    #expect(RecordsArchiveBanner(error: .unreadableArchive) == .damaged)
    #expect(RecordsArchiveBanner(error: .writeFailed) == .saveFailed)
    #expect(RecordsArchiveBanner(error: nil) == nil)
}

@MainActor
@Test("Quarantining a damaged archive keeps a .corrupt copy and unlocks writes")
func quarantineDamagedArchiveSucceedsAndAllowsWrites() throws {
    let (root, fileURL) = try makeArchiveRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let damaged = Data("not-json".utf8)
    try damaged.write(to: fileURL)
    let records = RecordCoordinator(fileURL: fileURL)
    #expect(records.archiveBanner == .damaged)
    #expect(records.blocksWrites)
    records.deleteAllLocalData()
    #expect(try Data(contentsOf: fileURL) == damaged)

    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let backup = try records.quarantineCorruptedArchive(at: now)
    #expect(backup == RecordCoordinator.corruptBackupURL(for: fileURL, at: now))
    #expect(backup?.lastPathComponent.contains("corrupt-") == true)
    #expect(try Data(contentsOf: backup!) == damaged)
    #expect(records.persistenceError == nil)
    #expect(records.archiveBanner == nil)
    #expect(try Data(contentsOf: fileURL) != damaged)

    records.ensureSeeded(hours: sampleHours(), at: startOf(2026, 8, 24))
    #expect(!records.state.periods.isEmpty)
    #expect(records.persistenceError == nil)
}

@MainActor
@Test("A failed quarantine leaves the damaged archive in place")
func quarantineDamagedArchiveFailureKeepsOriginal() throws {
    let (root, fileURL) = try makeArchiveRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let damaged = Data("not-json".utf8)
    try damaged.write(to: fileURL)
    let records = RecordCoordinator(fileURL: fileURL)
    let now = Date(timeIntervalSince1970: 1_777_000_111)
    let backup = RecordCoordinator.corruptBackupURL(for: fileURL, at: now)
    try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)

    #expect(throws: RecordPersistenceError.writeFailed) {
        try records.quarantineCorruptedArchive(at: now)
    }
    #expect(records.persistenceError == .invalidArchive)
    #expect(records.archiveBanner == .damaged)
    #expect(try Data(contentsOf: fileURL) == damaged)
    #expect(records.blocksWrites)
}

@MainActor
@Test("A save failure is not a damaged archive and cannot be quarantined")
func writeFailedDoesNotEnterQuarantine() throws {
    let (root, fileURL) = try makeArchiveRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let records = RecordCoordinator(fileURL: fileURL)
    records.ensureSeeded(hours: sampleHours(), at: startOf(2026, 8, 24))
    #expect(records.persistenceError == nil)
    try FileManager.default.removeItem(at: fileURL)
    try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)

    records.recordObservation(
        kind: .countdownStarted,
        eventID: recordID(40),
        shiftAnchorDate: startOf(2026, 8, 24),
        occurredAt: startOf(2026, 8, 24),
        snapshotID: records.state.snapshots[0].id
    )
    #expect(records.persistenceError == .writeFailed)
    #expect(records.archiveBanner == .saveFailed)
    #expect(!records.blocksWrites)

    let backup = try records.quarantineCorruptedArchive()
    #expect(backup == nil)
    #expect(records.persistenceError == .writeFailed)
    #expect(records.archiveBanner == .saveFailed)
    let leftovers = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.contains("corrupt-") }
    #expect(leftovers.isEmpty)
}

@MainActor
@Test("Following the schedule writes observations in the locked records time zone")
func scheduledFollowUsesLockedRecordsTimeZone() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.recordsTimeZoneIdentifier = "Asia/Shanghai"
    store.noteTimerSurfaceVisible(at: date(2026, 8, 24, 9))
    let observation = store.records.state.observations.first { $0.kind == .timerSurfaceFirstSeen }
    #expect(observation?.timeZoneIdentifier == "Asia/Shanghai")
    #expect(store.timeZoneIdentifierForWriting() == "Asia/Shanghai")
    #expect(store.countdownTimeZoneIdentifier == "Asia/Shanghai")
}

@MainActor
@Test("Migrating while a countdown is running keeps the session time zone")
func migrateWhileRunningKeepsSessionTimeZone() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.recordsTimeZoneIdentifier = "Asia/Shanghai"
    store.countdownStarted = true
    store.migrateRecordsTimeZone(
        to: TimeZone(identifier: "America/Los_Angeles")!,
        at: date(2026, 8, 24, 10)
    )
    #expect(store.recordsTimeZoneIdentifier == "America/Los_Angeles")
    #expect(store.sessionTimeZoneIdentifier == "Asia/Shanghai")
    #expect(store.countdownTimeZoneIdentifier == "Asia/Shanghai")
}

@MainActor
@Test("Days recorded in another time zone are listed for the life view")
func daysRecordedOutsidePeriodTimeZoneFoundation() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let hours = ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "17:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
    store.recordsTimeZoneIdentifier = shanghai.identifier
    store.records.ensureSeeded(hours: hours, at: startOf(2026, 8, 24), timeZone: shanghai)
    let anchor = ISO8601DateFormatter().date(from: "2026-08-24T12:00:00Z")!
    store.records.recordObservation(
        kind: .countdownStarted,
        eventID: UUID(),
        shiftAnchorDate: anchor,
        occurredAt: anchor,
        snapshotID: UUID(),
        timeZoneIdentifier: "America/Los_Angeles"
    )
    #expect(store.daysRecordedOutsidePeriodTimeZone() == ["2026-08-24"])
}

@MainActor
private func makeArchiveRoot() throws -> (root: URL, fileURL: URL) {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "owc-records-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (root, root.appending(path: "archive.json"))
}

@MainActor
private func sampleHours() -> ScheduleHoursConfiguration {
    ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "17:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
}

@MainActor
private func isolatedRecordDefaults() -> UserDefaults {
    let suite = "RecordCoordinatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func startOf(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
}

@MainActor
private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
}

@MainActor
private func recordID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
}

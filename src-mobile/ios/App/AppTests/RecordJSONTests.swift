import Foundation
import Testing
@testable import App

@MainActor
@Test("Unknown JSON schema versions are rejected")
func recordJSONRejectsUnknownVersion() throws {
    let data = Data(#"{"schemaVersion":2,"exportedAtMs":0,"timeZoneIdentifier":"UTC","calendarIdentifier":"gregorian","careerPeriods":[],"scheduleSnapshots":[],"calendarExceptions":[],"dayOverrides":[],"workObservations":[]}"#.utf8)
    #expect(throws: RecordJSONError.unknownSchemaVersion(2)) {
        _ = try RecordJSON.decode(data)
    }
}

@MainActor
@Test("Export then import is idempotent and never includes salary")
func recordJSONRoundTripIsIdempotent() throws {
    let state = sampleState()
    let timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let data = try RecordJSON.export(state, exportedAt: Date(timeIntervalSince1970: 1_777_000_000), timeZone: timeZone, calendar: calendar)
    let text = String(data: data, encoding: .utf8) ?? ""
    #expect(!text.contains("salary"))
    #expect(!text.contains("dailySalary"))

    let document = try RecordJSON.decode(data)
    var imported = RecordState()
    let first = try RecordJSON.apply(document, to: &imported, mode: .skipErased)
    #expect(first.inserted[.careerPeriod] == 1)
    #expect(first.inserted[.dayOverride] == 1)
    #expect(imported.periods.count == 1)
    #expect(imported.periods[0].id == state.periods[0].id)
    #expect(imported.periods[0].label == "Current")
    #expect(imported.overrides.count == 1)
    #expect(imported.overrides[0].dayKey == "2026-08-24")
    #expect(imported.overrides[0].kind == .customSegments)
    #expect(imported.overrides[0].segments == state.overrides[0].segments)

    let second = try RecordJSON.apply(document, to: &imported, mode: .skipErased)
    #expect(second.unchanged[.careerPeriod] == 1)
    #expect(second.unchanged[.dayOverride] == 1)
    #expect(second.inserted.isEmpty)
    #expect(second.conflicts.isEmpty)
}

@MainActor
@Test("Same identity with different content is a conflict, not a silent overwrite")
func recordJSONConflictDoesNotOverwrite() throws {
    var state = sampleState()
    let data = try export(state)
    var incoming = try RecordJSON.decode(data)
    incoming.dayOverrides[0].kind = .notWorking
    incoming.dayOverrides[0].segments = []

    let report = try RecordJSON.apply(incoming, to: &state, mode: .skipErased)
    #expect(report.conflicts.count == 1)
    #expect(report.conflicts[0].entityType == .dayOverride)
    #expect(state.overrides[0].kind == .customSegments)
}

@MainActor
@Test("Permanent delete then default import skips the erased identity")
func recordJSONSkipsErasedIdentities() throws {
    var state = sampleState()
    let data = try export(state)
    state.erase(.dayOverride, key: "2026-08-24", at: Date(timeIntervalSince1970: 1_777_000_100))
    #expect(state.overrides.isEmpty)

    let report = try RecordJSON.apply(try RecordJSON.decode(data), to: &state, mode: .skipErased)
    #expect(report.skippedErased[.dayOverride] == 1)
    #expect(state.overrides.isEmpty)
    #expect(state.isErased(.dayOverride, key: "2026-08-24"))
}

@MainActor
@Test("Explicit restore keeps the erase row and issues a new UUID for UUID identities")
func recordJSONRestoreIssuesNewUUID() throws {
    var state = sampleState()
    let originalID = state.periods[0].id
    let data = try export(state)
    state.erase(.careerPeriod, key: originalID.uuidString, at: Date(timeIntervalSince1970: 1_777_000_100))
    #expect(state.periods.isEmpty)

    let report = try RecordJSON.apply(try RecordJSON.decode(data), to: &state, mode: .restoreErased)
    #expect(report.restored[.careerPeriod] == 1)
    #expect(state.periods.count == 1)
    #expect(state.periods[0].id != originalID)
    #expect(state.isErased(.careerPeriod, key: originalID.uuidString))
}

@MainActor
@Test("Civil dates stay on the file calendar when the device timezone differs")
func recordJSONCivilDatesFollowFileTimeZone() throws {
    var tokyo = Calendar(identifier: .gregorian)
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    var state = RecordState()
    state.periods = [
        CareerPeriod(
            id: id(1),
            startsOn: tokyo.date(from: DateComponents(year: 2026, month: 8, day: 24))!,
            endsBefore: nil,
            label: nil,
            timeZoneIdentifier: "Asia/Tokyo",
            calendarIdentifier: "gregorian",
            createdAt: Date(timeIntervalSince1970: 0),
            editedAt: Date(timeIntervalSince1970: 0),
            editCount: 1,
            editTieBreaker: id(1)
        )
    ]
    let data = try RecordJSON.export(
        state,
        exportedAt: Date(timeIntervalSince1970: 0),
        timeZone: tokyo.timeZone,
        calendar: tokyo
    )
    let text = String(data: data, encoding: .utf8) ?? ""
    #expect(text.contains("2026-08-24"))

    var imported = RecordState()
    _ = try RecordJSON.apply(try RecordJSON.decode(data), to: &imported, mode: .skipErased)
    #expect(RecordJSON.dayKey(imported.periods[0].startsOn, calendar: tokyo) == "2026-08-24")
}

@MainActor
@Test("Older JSON without a per-row time zone inherits the file zone")
func recordJSONMissingRowTimeZoneInheritsFileZone() throws {
    let state = sampleState()
    let data = try export(state)
    var document = try RecordJSON.decode(data)
    document.dayOverrides[0].timeZoneIdentifier = nil
    var imported = RecordState()
    _ = try RecordJSON.apply(document, to: &imported, mode: .skipErased)
    #expect(imported.overrides[0].timeZoneIdentifier == TimeZone(secondsFromGMT: 0)!.identifier)
}

@MainActor
@Test("Each row keeps its own civil timezone during round trip")
func recordJSONMixedRowTimeZonesRoundTrip() throws {
    var state = sampleState()
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let la = TimeZone(identifier: "America/Los_Angeles")!
    var tokyoCalendar = Calendar(identifier: .gregorian)
    tokyoCalendar.timeZone = tokyo
    var laCalendar = Calendar(identifier: .gregorian)
    laCalendar.timeZone = la
    state.periods[0].startsOn = tokyoCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
    state.periods[0].timeZoneIdentifier = tokyo.identifier
    state.overrides[0].timeZoneIdentifier = la.identifier
    state.overrides[0].shiftAnchorDate = laCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
    state.snapshots = [
        ScheduleSnapshot(
            id: id(30),
            periodID: id(1),
            effectiveFrom: tokyoCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!,
            configurationData: Data("{}".utf8),
            fingerprint: "test",
            editedAt: Date(timeIntervalSince1970: 0),
            editCount: 1,
            editTieBreaker: id(31)
        )
    ]
    state.exceptions = [
        CalendarException(
            dayKey: "2026-08-24#user",
            date: laCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!,
            effect: .rest,
            origin: .user,
            isCleared: false,
            regionIdentifier: nil,
            datasetVersion: nil,
            label: nil,
            editedAt: Date(timeIntervalSince1970: 0),
            editCount: 1,
            editTieBreaker: id(32),
            timeZoneIdentifier: la.identifier
        )
    ]
    state.observations = [
        WorkObservation(
            eventID: id(33),
            shiftAnchorDate: tokyoCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!,
            occurredAt: Date(timeIntervalSince1970: 1_777_000_123),
            kind: .countdownStarted,
            valueData: nil,
            scheduleSnapshotID: id(30),
            timeZoneIdentifier: tokyo.identifier
        )
    ]

    let data = try export(state)
    var imported = RecordState()
    _ = try RecordJSON.apply(try RecordJSON.decode(data), to: &imported, mode: .skipErased)
    #expect(imported.periods[0].timeZoneIdentifier == tokyo.identifier)
    #expect(RecordJSON.dayKey(imported.periods[0].startsOn, calendar: tokyoCalendar) == "2026-08-24")
    #expect(imported.overrides[0].timeZoneIdentifier == la.identifier)
    #expect(RecordJSON.dayKey(imported.overrides[0].shiftAnchorDate, calendar: laCalendar) == "2026-08-24")
    #expect(RecordJSON.dayKey(imported.snapshots[0].effectiveFrom, calendar: tokyoCalendar) == "2026-08-24")
    #expect(imported.exceptions[0].timeZoneIdentifier == la.identifier)
    #expect(RecordJSON.dayKey(imported.exceptions[0].date, calendar: laCalendar) == "2026-08-24")
    #expect(imported.observations[0].timeZoneIdentifier == tokyo.identifier)
    #expect(RecordJSON.dayKey(imported.observations[0].shiftAnchorDate, calendar: tokyoCalendar) == "2026-08-24")
}

@MainActor
@Test("Invalid civil dates and override segments are rejected")
func recordJSONRejectsInvalidCivilData() throws {
    var document = try RecordJSON.decode(export(sampleState()))
    document.dayOverrides[0].dayKey = "2026-02-30"
    var state = RecordState()
    var report = try RecordJSON.apply(document, to: &state, mode: .skipErased)
    #expect(report.rejected.contains { $0.entityType == .dayOverride })

    document = try RecordJSON.decode(export(sampleState()))
    document.dayOverrides[0].segments = [
        NativeShiftSegment(startAtMs: 2, endAtMs: 3),
        NativeShiftSegment(startAtMs: 1, endAtMs: 4),
    ]
    state = RecordState()
    report = try RecordJSON.apply(document, to: &state, mode: .skipErased)
    #expect(report.rejected.contains { $0.entityType == .dayOverride })

    document = try RecordJSON.decode(export(sampleState()))
    document.careerPeriods[0].endsBefore = "2026-02-30"
    state = RecordState()
    report = try RecordJSON.apply(document, to: &state, mode: .skipErased)
    #expect(report.rejected.contains { $0.entityType == .careerPeriod })

    document = try RecordJSON.decode(export(sampleState()))
    document.lifeProfile = LifeProfileDTO(
        LifeProfile(
            workStartedOn: Date(timeIntervalSince1970: 0),
            editedAt: Date(timeIntervalSince1970: 0),
            editCount: 1,
            editTieBreaker: id(40)
        ),
        calendar: Calendar(identifier: .gregorian)
    )
    document.lifeProfile?.workStartedOn = "2026-02-30"
    state = RecordState()
    report = try RecordJSON.apply(document, to: &state, mode: .skipErased)
    #expect(report.rejected.contains { $0.entityType == .lifeProfile })
}

@MainActor
@Test("Duplicate period identities are reported without trapping")
func recordJSONDuplicatePeriodDoesNotTrap() throws {
    var document = try RecordJSON.decode(export(sampleState()))
    document.careerPeriods.append(document.careerPeriods[0])
    var state = RecordState()
    let report = try RecordJSON.apply(document, to: &state, mode: .skipErased)
    #expect(state.periods.count == 1)
    #expect(report.unchanged[.careerPeriod] == 1)
}

@MainActor
private func export(_ state: RecordState) throws -> Data {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return try RecordJSON.export(
        state,
        exportedAt: Date(timeIntervalSince1970: 0),
        timeZone: calendar.timeZone,
        calendar: calendar
    )
}

@MainActor
private func sampleState() -> RecordState {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
    var state = RecordState()
    state.periods = [
        CareerPeriod(
            id: id(1),
            startsOn: day,
            endsBefore: nil,
            label: "Current",
            timeZoneIdentifier: "UTC",
            calendarIdentifier: "gregorian",
            createdAt: day,
            editedAt: day,
            editCount: 1,
            editTieBreaker: id(1)
        )
    ]
    state.overrides = [
        DayOverride(
            dayKey: "2026-08-24",
            shiftAnchorDate: day,
            kind: .customSegments,
            segments: [NativeShiftSegment(startAtMs: 1, endAtMs: 2)],
            editedAt: day,
            editCount: 1,
            editTieBreaker: id(9)
        )
    ]
    return state
}

@MainActor
private func id(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
}

import Foundation

/// Which records-table a logical identity belongs to.
enum RecordEntityType: String, Codable, Sendable, CaseIterable {
    case careerPeriod
    case scheduleSnapshot
    case calendarException
    case dayOverride
    case workObservation
    case lifeProfile
}

/// Local tombstone so a later import cannot resurrect a permanently deleted
/// identity. `logicalKey` is a string because DayOverride and CalendarException
/// are keyed by `dayKey`, not a UUID — the plan snippet used `logicalID: UUID`
/// for CloudKit record names, but those names are already strings
/// (`day.2026-08-26`, `calx.2026-08-26#user`).
struct ErasedID: Equatable, Sendable, Hashable {
    var entityType: RecordEntityType
    var logicalKey: String
    var erasedAt: Date

    var identity: String { "\(entityType.rawValue).\(logicalKey)" }
}

enum RecordImportMode: Sendable {
    /// Skip identities listed in the local ErasedID table (default).
    case skipErased
    /// Write erased rows back. UUID identities get a new random id; natural
    /// keys keep the same `dayKey`. The erase row itself stays.
    case restoreErased
}

struct RecordImportConflict: Equatable, Sendable {
    var entityType: RecordEntityType
    var logicalKey: String
}

struct RecordImportReport: Equatable, Sendable {
    var inserted: [RecordEntityType: Int] = [:]
    var unchanged: [RecordEntityType: Int] = [:]
    var skippedErased: [RecordEntityType: Int] = [:]
    var restored: [RecordEntityType: Int] = [:]
    var conflicts: [RecordImportConflict] = []

    var skippedErasedTotal: Int { skippedErased.values.reduce(0, +) }
}

enum RecordJSONError: Error, Equatable {
    case unknownSchemaVersion(Int)
    case invalidDocument
}

/// In-memory records archive. JSON is the Android / backup contract;
/// SwiftData `@Model` mapping waits until P1 needs a query cache.
struct RecordState: Equatable, Sendable {
    var periods: [CareerPeriod] = []
    var snapshots: [ScheduleSnapshot] = []
    var exceptions: [CalendarException] = []
    var overrides: [DayOverride] = []
    var observations: [WorkObservation] = []
    var lifeProfile: LifeProfile?
    var erased: [ErasedID] = []

    func isErased(_ type: RecordEntityType, key: String) -> Bool {
        erased.contains { $0.entityType == type && $0.logicalKey == key }
    }

    mutating func erase(_ type: RecordEntityType, key: String, at date: Date) {
        switch type {
        case .careerPeriod:
            periods.removeAll { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame }
        case .scheduleSnapshot:
            snapshots.removeAll { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame }
        case .calendarException:
            exceptions.removeAll { $0.dayKey == key }
        case .dayOverride:
            overrides.removeAll { $0.dayKey == key }
        case .workObservation:
            observations.removeAll { $0.eventID.uuidString.caseInsensitiveCompare(key) == .orderedSame }
        case .lifeProfile:
            lifeProfile = nil
        }
        if !isErased(type, key: key) {
            erased.append(ErasedID(entityType: type, logicalKey: key, erasedAt: date))
        }
    }

    mutating func deleteAllLocalData() {
        self = RecordState()
    }
}

/// Versioned JSON import / export. Civil dates are `YYYY-MM-DD` in the file's
/// calendar; instants are Unix milliseconds so a timezone shift cannot move a
/// day. Salary never appears.
enum RecordJSON {
    static let schemaVersion = 1

    static func export(
        _ state: RecordState,
        exportedAt: Date,
        timeZone: TimeZone,
        calendar: Calendar
    ) throws -> Data {
        var fileCalendar = calendar
        fileCalendar.timeZone = timeZone
        let document = RecordJSONDocument(
            schemaVersion: schemaVersion,
            exportedAtMs: exportedAt.timeIntervalSince1970 * 1_000,
            timeZoneIdentifier: timeZone.identifier,
            calendarIdentifier: calendarIdentifier(fileCalendar),
            careerPeriods: state.periods.map { CareerPeriodDTO($0, calendar: fileCalendar) },
            scheduleSnapshots: state.snapshots.map { ScheduleSnapshotDTO($0, calendar: fileCalendar) },
            calendarExceptions: state.exceptions.map { CalendarExceptionDTO($0, calendar: fileCalendar) },
            dayOverrides: state.overrides.map { DayOverrideDTO($0, calendar: fileCalendar) },
            workObservations: state.observations.map { WorkObservationDTO($0, calendar: fileCalendar) },
            lifeProfile: state.lifeProfile.map { LifeProfileDTO($0, calendar: fileCalendar) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> RecordJSONDocument {
        let document: RecordJSONDocument
        do {
            document = try JSONDecoder().decode(RecordJSONDocument.self, from: data)
        } catch {
            throw RecordJSONError.invalidDocument
        }
        guard document.schemaVersion == schemaVersion else {
            throw RecordJSONError.unknownSchemaVersion(document.schemaVersion)
        }
        return document
    }

    static func apply(
        _ document: RecordJSONDocument,
        to state: inout RecordState,
        mode: RecordImportMode
    ) throws -> RecordImportReport {
        guard document.schemaVersion == schemaVersion else {
            throw RecordJSONError.unknownSchemaVersion(document.schemaVersion)
        }
        let calendar = calendar(from: document)
        var report = RecordImportReport()
        var periodIDMap: [UUID: UUID] = [:]
        var snapshotIDMap: [UUID: UUID] = [:]

        for dto in document.careerPeriods {
            guard let incoming = dto.value(calendar: calendar) else { continue }
            merge(
                incoming,
                type: .careerPeriod,
                key: incoming.id.uuidString,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.periods.first { $0.id == incoming.id } },
                insert: { archive, value in
                    var next = value
                    if mode == .restoreErased, archive.isErased(.careerPeriod, key: incoming.id.uuidString) {
                        let newID = UUID()
                        periodIDMap[incoming.id] = newID
                        next.id = newID
                    }
                    archive.periods.append(next)
                }
            )
        }

        for dto in document.scheduleSnapshots {
            guard let incoming = dto.value(calendar: calendar) else { continue }
            merge(
                incoming,
                type: .scheduleSnapshot,
                key: incoming.id.uuidString,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.snapshots.first { $0.id == incoming.id } },
                insert: { archive, value in
                    var next = value
                    if mode == .restoreErased, archive.isErased(.scheduleSnapshot, key: incoming.id.uuidString) {
                        let newID = UUID()
                        snapshotIDMap[incoming.id] = newID
                        next.id = newID
                    }
                    if let mapped = periodIDMap[next.periodID] {
                        next.periodID = mapped
                    }
                    archive.snapshots.append(next)
                }
            )
        }

        for dto in document.calendarExceptions {
            guard let incoming = dto.value(calendar: calendar) else { continue }
            merge(
                incoming,
                type: .calendarException,
                key: incoming.dayKey,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.exceptions.first { $0.dayKey == incoming.dayKey } },
                insert: { archive, value in archive.exceptions.append(value) }
            )
        }

        for dto in document.dayOverrides {
            guard let incoming = dto.value(calendar: calendar) else { continue }
            merge(
                incoming,
                type: .dayOverride,
                key: incoming.dayKey,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.overrides.first { $0.dayKey == incoming.dayKey } },
                insert: { archive, value in archive.overrides.append(value) }
            )
        }

        for dto in document.workObservations {
            guard let incoming = dto.value(calendar: calendar) else { continue }
            merge(
                incoming,
                type: .workObservation,
                key: incoming.eventID.uuidString,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.observations.first { $0.eventID == incoming.eventID } },
                insert: { archive, value in
                    var next = value
                    if mode == .restoreErased, archive.isErased(.workObservation, key: incoming.eventID.uuidString) {
                        next.eventID = UUID()
                    }
                    if let mapped = snapshotIDMap[next.scheduleSnapshotID] {
                        next.scheduleSnapshotID = mapped
                    }
                    archive.observations.append(next)
                }
            )
        }

        if let dto = document.lifeProfile, let incoming = dto.value(calendar: calendar) {
            merge(
                incoming,
                type: .lifeProfile,
                key: LifeProfile.profileID.uuidString,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.lifeProfile },
                insert: { archive, value in archive.lifeProfile = value }
            )
        }

        return report
    }

    private static func merge<T: Equatable>(
        _ incoming: T,
        type: RecordEntityType,
        key: String,
        mode: RecordImportMode,
        state: inout RecordState,
        report: inout RecordImportReport,
        existing: (RecordState) -> T?,
        insert: (inout RecordState, T) -> Void
    ) {
        if state.isErased(type, key: key) {
            switch mode {
            case .skipErased:
                report.skippedErased[type, default: 0] += 1
                return
            case .restoreErased:
                insert(&state, incoming)
                report.restored[type, default: 0] += 1
                return
            }
        }
        if let current = existing(state) {
            if current == incoming {
                report.unchanged[type, default: 0] += 1
            } else {
                report.conflicts.append(RecordImportConflict(entityType: type, logicalKey: key))
            }
            return
        }
        insert(&state, incoming)
        report.inserted[type, default: 0] += 1
    }

    static func calendar(from document: RecordJSONDocument) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if document.calendarIdentifier == "iso8601" {
            calendar = Calendar(identifier: .iso8601)
        }
        calendar.timeZone = TimeZone(identifier: document.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func calendarIdentifier(_ calendar: Calendar) -> String {
        calendar.identifier == .iso8601 ? "iso8601" : "gregorian"
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

struct RecordJSONDocument: Codable, Equatable {
    var schemaVersion: Int
    var exportedAtMs: Double
    var timeZoneIdentifier: String
    var calendarIdentifier: String
    var careerPeriods: [CareerPeriodDTO]
    var scheduleSnapshots: [ScheduleSnapshotDTO]
    var calendarExceptions: [CalendarExceptionDTO]
    var dayOverrides: [DayOverrideDTO]
    var workObservations: [WorkObservationDTO]
    var lifeProfile: LifeProfileDTO?
}

struct CareerPeriodDTO: Codable, Equatable {
    var id: String
    var startsOn: String
    var endsBefore: String?
    var label: String?
    var timeZoneIdentifier: String
    var calendarIdentifier: String
    var createdAtMs: Double
    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: String

    init(_ value: CareerPeriod, calendar: Calendar) {
        id = value.id.uuidString
        startsOn = RecordJSON.dayKey(value.startsOn, calendar: calendar)
        endsBefore = value.endsBefore.map { RecordJSON.dayKey($0, calendar: calendar) }
        label = value.label
        timeZoneIdentifier = value.timeZoneIdentifier
        calendarIdentifier = value.calendarIdentifier
        createdAtMs = value.createdAt.timeIntervalSince1970 * 1_000
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
    }

    func value(calendar: Calendar) -> CareerPeriod? {
        guard let id = UUID(uuidString: id),
              let startsOn = RecordJSON.date(fromDayKey: startsOn, calendar: calendar),
              let editTieBreaker = UUID(uuidString: editTieBreaker)
        else { return nil }
        let endsBefore = endsBefore.flatMap { RecordJSON.date(fromDayKey: $0, calendar: calendar) }
        return CareerPeriod(
            id: id,
            startsOn: startsOn,
            endsBefore: endsBefore,
            label: label,
            timeZoneIdentifier: timeZoneIdentifier,
            calendarIdentifier: calendarIdentifier,
            createdAt: Date(timeIntervalSince1970: createdAtMs / 1_000),
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker
        )
    }
}

struct ScheduleSnapshotDTO: Codable, Equatable {
    var id: String
    var periodID: String
    var effectiveFrom: String
    var configurationData: Data
    var fingerprint: String
    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: String

    init(_ value: ScheduleSnapshot, calendar: Calendar) {
        id = value.id.uuidString
        periodID = value.periodID.uuidString
        effectiveFrom = RecordJSON.dayKey(value.effectiveFrom, calendar: calendar)
        configurationData = value.configurationData
        fingerprint = value.fingerprint
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
    }

    func value(calendar: Calendar) -> ScheduleSnapshot? {
        guard let id = UUID(uuidString: id),
              let periodID = UUID(uuidString: periodID),
              let effectiveFrom = RecordJSON.date(fromDayKey: effectiveFrom, calendar: calendar),
              let editTieBreaker = UUID(uuidString: editTieBreaker)
        else { return nil }
        return ScheduleSnapshot(
            id: id,
            periodID: periodID,
            effectiveFrom: effectiveFrom,
            configurationData: configurationData,
            fingerprint: fingerprint,
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker
        )
    }
}

struct CalendarExceptionDTO: Codable, Equatable {
    var dayKey: String
    var date: String
    var effect: CalendarEffect
    var origin: CalendarExceptionOrigin
    var isCleared: Bool
    var regionIdentifier: String?
    var datasetVersion: String?
    var label: String?
    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: String

    init(_ value: CalendarException, calendar: Calendar) {
        dayKey = value.dayKey
        date = RecordJSON.dayKey(value.date, calendar: calendar)
        effect = value.effect
        origin = value.origin
        isCleared = value.isCleared
        regionIdentifier = value.regionIdentifier
        datasetVersion = value.datasetVersion
        label = value.label
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
    }

    func value(calendar: Calendar) -> CalendarException? {
        guard let date = RecordJSON.date(fromDayKey: date, calendar: calendar),
              let editTieBreaker = UUID(uuidString: editTieBreaker)
        else { return nil }
        return CalendarException(
            dayKey: dayKey,
            date: date,
            effect: effect,
            origin: origin,
            isCleared: isCleared,
            regionIdentifier: regionIdentifier,
            datasetVersion: datasetVersion,
            label: label,
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker
        )
    }
}

struct DayOverrideDTO: Codable, Equatable {
    var dayKey: String
    var kind: DayOverrideKind
    var segments: [NativeShiftSegment]
    var note: String?
    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: String

    init(_ value: DayOverride, calendar: Calendar) {
        _ = calendar
        dayKey = value.dayKey
        kind = value.kind
        segments = value.segments
        note = value.note
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
    }

    func value(calendar: Calendar) -> DayOverride? {
        guard let shiftAnchorDate = RecordJSON.date(fromDayKey: dayKey, calendar: calendar),
              let editTieBreaker = UUID(uuidString: editTieBreaker)
        else { return nil }
        return DayOverride(
            dayKey: dayKey,
            shiftAnchorDate: shiftAnchorDate,
            kind: kind,
            segments: segments,
            note: note,
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker
        )
    }
}

struct WorkObservationDTO: Codable, Equatable {
    var eventID: String
    var shiftAnchorDate: String
    var occurredAtMs: Double
    var kind: WorkObservationKind
    var valueData: Data?
    var scheduleSnapshotID: String
    var schemaVersion: Int

    init(_ value: WorkObservation, calendar: Calendar) {
        eventID = value.eventID.uuidString
        shiftAnchorDate = RecordJSON.dayKey(value.shiftAnchorDate, calendar: calendar)
        occurredAtMs = value.occurredAt.timeIntervalSince1970 * 1_000
        kind = value.kind
        valueData = value.valueData
        scheduleSnapshotID = value.scheduleSnapshotID.uuidString
        schemaVersion = value.schemaVersion
    }

    func value(calendar: Calendar) -> WorkObservation? {
        guard let eventID = UUID(uuidString: eventID),
              let shiftAnchorDate = RecordJSON.date(fromDayKey: shiftAnchorDate, calendar: calendar),
              let scheduleSnapshotID = UUID(uuidString: scheduleSnapshotID)
        else { return nil }
        return WorkObservation(
            eventID: eventID,
            shiftAnchorDate: shiftAnchorDate,
            occurredAt: Date(timeIntervalSince1970: occurredAtMs / 1_000),
            kind: kind,
            valueData: valueData,
            scheduleSnapshotID: scheduleSnapshotID,
            schemaVersion: schemaVersion
        )
    }
}

struct LifeProfileDTO: Codable, Equatable {
    var profileID: String
    var birthYear: Int?
    var workStartedOn: String?
    var retirementAge: Int?
    var averageSleepHours: Double?
    var hidesExactAges: Bool
    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: String

    init(_ value: LifeProfile, calendar: Calendar) {
        profileID = value.profileID.uuidString
        birthYear = value.birthYear
        workStartedOn = value.workStartedOn.map { RecordJSON.dayKey($0, calendar: calendar) }
        retirementAge = value.retirementAge
        averageSleepHours = value.averageSleepHours
        hidesExactAges = value.hidesExactAges
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
    }

    func value(calendar: Calendar) -> LifeProfile? {
        guard let profileID = UUID(uuidString: profileID),
              let editTieBreaker = UUID(uuidString: editTieBreaker)
        else { return nil }
        return LifeProfile(
            profileID: profileID,
            birthYear: birthYear,
            workStartedOn: workStartedOn.flatMap { RecordJSON.date(fromDayKey: $0, calendar: calendar) },
            retirementAge: retirementAge,
            averageSleepHours: averageSleepHours,
            hidesExactAges: hidesExactAges,
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker
        )
    }
}

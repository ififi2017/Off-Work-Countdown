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
    /// Same-id conflicts keep the local row and include the incoming value
    /// so a caller can ask, then `applyIncoming`.
    case skipErased
    /// Write erased rows back. UUID identities get a new random id; natural
    /// keys keep the same `dayKey`. The erase row itself stays.
    case restoreErased
    /// Same-id conflicts pick `(editCount, editTieBreaker)` — wall clock
    /// never decides. Erased identities still skip.
    case resolveByEditStamp
}

enum RecordIncomingValue: Equatable, Sendable {
    case period(CareerPeriod)
    case snapshot(ScheduleSnapshot)
    case exception(CalendarException)
    case override(DayOverride)
    case observation(WorkObservation)
    case lifeProfile(LifeProfile)
}

struct RecordImportConflict: Equatable, Sendable {
    var entityType: RecordEntityType
    var logicalKey: String
    var incoming: RecordIncomingValue
    var localEditCount: Int
    var incomingEditCount: Int
    var appliedIncoming: Bool
}

struct RecordImportRejection: Equatable, Sendable {
    var entityType: RecordEntityType
    var logicalKey: String
}

struct RecordImportReport: Equatable, Sendable {
    var inserted: [RecordEntityType: Int] = [:]
    var unchanged: [RecordEntityType: Int] = [:]
    var skippedErased: [RecordEntityType: Int] = [:]
    var restored: [RecordEntityType: Int] = [:]
    var rejected: [RecordImportRejection] = []
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
            careerPeriods: state.periods.map { CareerPeriodDTO($0, calendar: $0.civilCalendar()) },
            scheduleSnapshots: state.snapshots.map { snapshot in
                let period = state.periods.first(where: { $0.id == snapshot.periodID })
                return ScheduleSnapshotDTO(snapshot, calendar: period?.civilCalendar() ?? fileCalendar)
            },
            calendarExceptions: state.exceptions.map { exception in
                var rowCalendar = Calendar(identifier: .gregorian)
                rowCalendar.timeZone = TimeZone(identifier: exception.timeZoneIdentifier) ?? fileCalendar.timeZone
                return CalendarExceptionDTO(exception, calendar: rowCalendar)
            },
            dayOverrides: state.overrides.map { override in
                var rowCalendar = Calendar(identifier: .gregorian)
                rowCalendar.timeZone = TimeZone(identifier: override.timeZoneIdentifier) ?? fileCalendar.timeZone
                return DayOverrideDTO(override, calendar: rowCalendar)
            },
            workObservations: state.observations.map { observation in
                var rowCalendar = Calendar(identifier: .gregorian)
                rowCalendar.timeZone = TimeZone(identifier: observation.timeZoneIdentifier) ?? fileCalendar.timeZone
                return WorkObservationDTO(observation, calendar: rowCalendar)
            },
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
        let periodCalendars = document.careerPeriods.reduce(into: [String: Calendar]()) { result, dto in
            guard UUID(uuidString: dto.id) != nil, result[dto.id] == nil else { return }
            result[dto.id] = rowCalendar(
                timeZoneIdentifier: dto.timeZoneIdentifier,
                calendarIdentifier: dto.calendarIdentifier,
                fallback: calendar
            )
        }

        for dto in document.careerPeriods {
            guard let incoming = dto.value(calendar: periodCalendars[dto.id] ?? calendar) else {
                report.rejected.append(RecordImportRejection(entityType: .careerPeriod, logicalKey: dto.id))
                continue
            }
            merge(
                incoming,
                type: .careerPeriod,
                key: incoming.id.uuidString,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.periods.first { $0.id == incoming.id } },
                incomingValue: { .period($0) },
                insert: { archive, value in
                    var next = value
                    if mode == .restoreErased, archive.isErased(.careerPeriod, key: incoming.id.uuidString) {
                        let newID = UUID()
                        periodIDMap[incoming.id] = newID
                        next.id = newID
                    }
                    archive.periods.append(next)
                },
                replace: { archive, value in
                    if let index = archive.periods.firstIndex(where: { $0.id == value.id }) {
                        archive.periods[index] = value
                    }
                }
            )
        }

        for dto in document.scheduleSnapshots {
            guard let incoming = dto.value(calendar: periodCalendars[dto.periodID] ?? calendar) else {
                report.rejected.append(RecordImportRejection(entityType: .scheduleSnapshot, logicalKey: dto.id))
                continue
            }
            merge(
                incoming,
                type: .scheduleSnapshot,
                key: incoming.id.uuidString,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.snapshots.first { $0.id == incoming.id } },
                incomingValue: { .snapshot($0) },
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
                },
                replace: { archive, value in
                    if let index = archive.snapshots.firstIndex(where: { $0.id == value.id }) {
                        archive.snapshots[index] = value
                    }
                }
            )
        }

        for dto in document.calendarExceptions {
            let calendarForRow = rowCalendar(
                timeZoneIdentifier: dto.timeZoneIdentifier,
                calendarIdentifier: nil,
                fallback: calendar
            )
            guard let incoming = dto.value(calendar: calendarForRow) else {
                report.rejected.append(RecordImportRejection(entityType: .calendarException, logicalKey: dto.dayKey))
                continue
            }
            merge(
                incoming,
                type: .calendarException,
                key: incoming.dayKey,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.exceptions.first { $0.dayKey == incoming.dayKey } },
                incomingValue: { .exception($0) },
                insert: { archive, value in archive.exceptions.append(value) },
                replace: { archive, value in
                    if let index = archive.exceptions.firstIndex(where: { $0.dayKey == value.dayKey }) {
                        archive.exceptions[index] = value
                    }
                }
            )
        }

        for dto in document.dayOverrides {
            let calendarForRow = rowCalendar(
                timeZoneIdentifier: dto.timeZoneIdentifier,
                calendarIdentifier: nil,
                fallback: calendar
            )
            guard let incoming = dto.value(calendar: calendarForRow) else {
                report.rejected.append(RecordImportRejection(entityType: .dayOverride, logicalKey: dto.dayKey))
                continue
            }
            merge(
                incoming,
                type: .dayOverride,
                key: incoming.dayKey,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.overrides.first { $0.dayKey == incoming.dayKey } },
                incomingValue: { .override($0) },
                insert: { archive, value in archive.overrides.append(value) },
                replace: { archive, value in
                    if let index = archive.overrides.firstIndex(where: { $0.dayKey == value.dayKey }) {
                        archive.overrides[index] = value
                    }
                }
            )
        }

        for dto in document.workObservations {
            let calendarForRow = rowCalendar(
                timeZoneIdentifier: dto.timeZoneIdentifier,
                calendarIdentifier: nil,
                fallback: calendar
            )
            guard let incoming = dto.value(calendar: calendarForRow) else {
                report.rejected.append(RecordImportRejection(entityType: .workObservation, logicalKey: dto.eventID))
                continue
            }
            merge(
                incoming,
                type: .workObservation,
                key: incoming.eventID.uuidString,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.observations.first { $0.eventID == incoming.eventID } },
                incomingValue: { .observation($0) },
                insert: { archive, value in
                    var next = value
                    if mode == .restoreErased, archive.isErased(.workObservation, key: incoming.eventID.uuidString) {
                        next.eventID = UUID()
                    }
                    if let mapped = snapshotIDMap[next.scheduleSnapshotID] {
                        next.scheduleSnapshotID = mapped
                    }
                    archive.observations.append(next)
                },
                replace: { archive, value in
                    if let index = archive.observations.firstIndex(where: { $0.eventID == value.eventID }) {
                        archive.observations[index] = value
                    }
                }
            )
        }

        if let dto = document.lifeProfile {
            guard let incoming = dto.value(calendar: calendar) else {
                report.rejected.append(
                    RecordImportRejection(entityType: .lifeProfile, logicalKey: dto.profileID)
                )
                return report
            }
            merge(
                incoming,
                type: .lifeProfile,
                key: LifeProfile.profileID.uuidString,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.lifeProfile },
                incomingValue: { .lifeProfile($0) },
                insert: { archive, value in archive.lifeProfile = value },
                replace: { archive, value in archive.lifeProfile = value }
            )
        }

        return report
    }

    static func applyIncoming(_ value: RecordIncomingValue, to state: inout RecordState) {
        switch value {
        case .period(let period):
            if let index = state.periods.firstIndex(where: { $0.id == period.id }) {
                state.periods[index] = period
            } else {
                state.periods.append(period)
            }
        case .snapshot(let snapshot):
            if let index = state.snapshots.firstIndex(where: { $0.id == snapshot.id }) {
                state.snapshots[index] = snapshot
            } else {
                state.snapshots.append(snapshot)
            }
        case .exception(let exception):
            if let index = state.exceptions.firstIndex(where: { $0.dayKey == exception.dayKey }) {
                state.exceptions[index] = exception
            } else {
                state.exceptions.append(exception)
            }
        case .override(let override):
            if let index = state.overrides.firstIndex(where: { $0.dayKey == override.dayKey }) {
                state.overrides[index] = override
            } else {
                state.overrides.append(override)
            }
        case .observation(let observation):
            if let index = state.observations.firstIndex(where: { $0.eventID == observation.eventID }) {
                state.observations[index] = observation
            } else {
                state.observations.append(observation)
            }
        case .lifeProfile(let profile):
            state.lifeProfile = profile
        }
    }

    private static func merge<T: Equatable>(
        _ incoming: T,
        type: RecordEntityType,
        key: String,
        mode: RecordImportMode,
        state: inout RecordState,
        report: inout RecordImportReport,
        existing: (RecordState) -> T?,
        incomingValue: (T) -> RecordIncomingValue,
        insert: (inout RecordState, T) -> Void,
        replace: (inout RecordState, T) -> Void
    ) {
        if state.isErased(type, key: key) {
            switch mode {
            case .skipErased, .resolveByEditStamp:
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
                return
            }
            let localCount = editCount(of: current)
            let incomingCount = editCount(of: incoming)
            let takeIncoming = mode == .resolveByEditStamp && incomingWins(incoming, over: current)
            if takeIncoming {
                replace(&state, incoming)
            }
            report.conflicts.append(
                RecordImportConflict(
                    entityType: type,
                    logicalKey: key,
                    incoming: incomingValue(incoming),
                    localEditCount: localCount,
                    incomingEditCount: incomingCount,
                    appliedIncoming: takeIncoming
                )
            )
            return
        }
        insert(&state, incoming)
        report.inserted[type, default: 0] += 1
    }

    private static func editCount(of value: some Equatable) -> Int {
        switch value {
        case let period as CareerPeriod: period.editCount
        case let snapshot as ScheduleSnapshot: snapshot.editCount
        case let exception as CalendarException: exception.editCount
        case let override as DayOverride: override.editCount
        case let profile as LifeProfile: profile.editCount
        default: 0
        }
    }

    private static func tieBreaker(of value: some Equatable) -> UUID {
        switch value {
        case let period as CareerPeriod: period.editTieBreaker
        case let snapshot as ScheduleSnapshot: snapshot.editTieBreaker
        case let exception as CalendarException: exception.editTieBreaker
        case let override as DayOverride: override.editTieBreaker
        case let profile as LifeProfile: profile.editTieBreaker
        case let observation as WorkObservation: observation.eventID
        default: DayOverride.unsetTieBreaker
        }
    }

    private static func incomingWins<T: Equatable>(_ incoming: T, over current: T) -> Bool {
        let incomingCount = editCount(of: incoming)
        let localCount = editCount(of: current)
        if incomingCount != localCount { return incomingCount > localCount }
        return tieBreaker(of: incoming).uuidString > tieBreaker(of: current).uuidString
    }

    static func calendar(from document: RecordJSONDocument) -> Calendar {
        var fallback = Calendar(identifier: .gregorian)
        fallback.timeZone = TimeZone(secondsFromGMT: 0)!
        return rowCalendar(
            timeZoneIdentifier: document.timeZoneIdentifier,
            calendarIdentifier: document.calendarIdentifier,
            fallback: fallback
        )
    }

    static func rowCalendar(
        timeZoneIdentifier: String?,
        calendarIdentifier: String?,
        fallback: Calendar
    ) -> Calendar {
        var calendar: Calendar
        switch calendarIdentifier {
        case "iso8601": calendar = Calendar(identifier: .iso8601)
        case "gregorian", nil: calendar = Calendar(identifier: fallback.identifier)
        default: calendar = Calendar(identifier: fallback.identifier)
        }
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier ?? fallback.timeZone.identifier)
            ?? fallback.timeZone
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
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        // Calendar.date(from:) may normalize invalid dates. Round-trip the
        // components so 2026-02-30 and similar input are rejected.
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else {
            return nil
        }
        return date
    }

    static func validOverrideSegments(
        _ segments: [NativeShiftSegment],
        kind: DayOverrideKind
    ) -> Bool {
        if kind == .customSegments {
            guard !segments.isEmpty else { return false }
        } else if !segments.isEmpty {
            return false
        }
        var previousEnd: Double?
        for segment in segments {
            guard segment.startAtMs.isFinite,
                  segment.endAtMs.isFinite,
                  segment.endAtMs > segment.startAtMs
            else { return false }
            if let previousEnd, segment.startAtMs < previousEnd { return false }
            previousEnd = segment.endAtMs
        }
        return true
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
    var timeZoneIdentifier: String?
    var calendarIdentifier: String?
    var createdAtMs: Double
    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: String

    init(_ value: CareerPeriod, calendar _: Calendar) {
        let ownCalendar = value.civilCalendar()
        id = value.id.uuidString
        startsOn = RecordJSON.dayKey(value.startsOn, calendar: ownCalendar)
        endsBefore = value.endsBefore.map { RecordJSON.dayKey($0, calendar: ownCalendar) }
        label = value.label
        timeZoneIdentifier = value.timeZoneIdentifier
        calendarIdentifier = value.calendarIdentifier
        createdAtMs = value.createdAt.timeIntervalSince1970 * 1_000
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
    }

    func value(calendar: Calendar) -> CareerPeriod? {
        let rowCalendar = RecordJSON.rowCalendar(
            timeZoneIdentifier: timeZoneIdentifier,
            calendarIdentifier: calendarIdentifier,
            fallback: calendar
        )
        guard let id = UUID(uuidString: id),
              let startsOn = RecordJSON.date(fromDayKey: startsOn, calendar: rowCalendar),
              let editTieBreaker = UUID(uuidString: editTieBreaker)
        else { return nil }
        let parsedEndsBefore: Date?
        if let endsBefore {
            guard let date = RecordJSON.date(fromDayKey: endsBefore, calendar: rowCalendar) else { return nil }
            parsedEndsBefore = date
        } else {
            parsedEndsBefore = nil
        }
        if let parsedEndsBefore, parsedEndsBefore <= startsOn { return nil }
        return CareerPeriod(
            id: id,
            startsOn: startsOn,
            endsBefore: parsedEndsBefore,
            label: label,
            timeZoneIdentifier: timeZoneIdentifier ?? rowCalendar.timeZone.identifier,
            calendarIdentifier: calendarIdentifier ?? RecordJSON.calendarIdentifier(rowCalendar),
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
    var timeZoneIdentifier: String?

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
        timeZoneIdentifier = value.timeZoneIdentifier
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
            editTieBreaker: editTieBreaker,
            timeZoneIdentifier: timeZoneIdentifier ?? calendar.timeZone.identifier
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
    var timeZoneIdentifier: String?

    init(_ value: DayOverride, calendar: Calendar) {
        _ = calendar
        dayKey = value.dayKey
        kind = value.kind
        segments = value.segments
        note = value.note
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
        timeZoneIdentifier = value.timeZoneIdentifier
    }

    func value(calendar: Calendar) -> DayOverride? {
        guard RecordJSON.validOverrideSegments(segments, kind: kind),
              let shiftAnchorDate = RecordJSON.date(fromDayKey: dayKey, calendar: calendar),
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
            editTieBreaker: editTieBreaker,
            timeZoneIdentifier: timeZoneIdentifier ?? calendar.timeZone.identifier
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
    var timeZoneIdentifier: String?

    init(_ value: WorkObservation, calendar: Calendar) {
        eventID = value.eventID.uuidString
        shiftAnchorDate = RecordJSON.dayKey(value.shiftAnchorDate, calendar: calendar)
        occurredAtMs = value.occurredAt.timeIntervalSince1970 * 1_000
        kind = value.kind
        valueData = value.valueData
        scheduleSnapshotID = value.scheduleSnapshotID.uuidString
        schemaVersion = value.schemaVersion
        timeZoneIdentifier = value.timeZoneIdentifier
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
            schemaVersion: schemaVersion,
            timeZoneIdentifier: timeZoneIdentifier ?? calendar.timeZone.identifier
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
        let parsedWorkStartedOn: Date?
        if let workStartedOn {
            guard let date = RecordJSON.date(fromDayKey: workStartedOn, calendar: calendar) else { return nil }
            parsedWorkStartedOn = date
        } else {
            parsedWorkStartedOn = nil
        }
        return LifeProfile(
            profileID: profileID,
            birthYear: birthYear,
            workStartedOn: parsedWorkStartedOn,
            retirementAge: retirementAge,
            averageSleepHours: averageSleepHours,
            hidesExactAges: hidesExactAges,
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker
        )
    }
}

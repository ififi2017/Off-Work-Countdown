import Foundation

/// Which records-table a logical identity belongs to.
enum RecordEntityType: String, Codable, Sendable, CaseIterable {
    case careerPeriod
    case scheduleSnapshot
    case calendarException
    case dayOverride
    case workObservation
    case lifeProfile
    case focusTask
    case focusSession
    case focusPlanningConfiguration
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
    /// The row's `editCount` at the moment it was erased.
    ///
    /// A natural key (`dayKey`) can be recorded again under the identity it was
    /// erased under, so "erased" and "recorded again" have to be orderable.
    /// A revival writes an `editCount` above this one and therefore wins on
    /// every device, whichever order CloudKit delivers the two in. Wall clock
    /// never decides, exactly as with `editCount` elsewhere.
    var editCount: Int = 0

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
    case focusTask(FocusTask)
    case focusSession(FocusSession)
    case focusPlanningConfiguration(FocusPlanningConfiguration)
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

struct RecordImportAdoption: Equatable, Sendable {
    var entityType: RecordEntityType
    var logicalKey: String
    var editCount: Int
    var editTieBreaker: String
}

struct RecordImportReport: Equatable, Sendable {
    var inserted: [RecordEntityType: Int] = [:]
    var unchanged: [RecordEntityType: Int] = [:]
    var skippedErased: [RecordEntityType: Int] = [:]
    var restored: [RecordEntityType: Int] = [:]
    var rejected: [RecordImportRejection] = []
    var conflicts: [RecordImportConflict] = []
    var adopted: [RecordImportAdoption] = []

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
    var focusTasks: [FocusTask] = []
    var focusSessions: [FocusSession] = []
    var focusPlanningConfiguration: FocusPlanningConfiguration?
    var recordsStartedOn: Date?
    var erased: [ErasedID] = []
    var sync = SyncLocalState.empty

    func isErased(_ type: RecordEntityType, key: String) -> Bool {
        erased.contains { $0.entityType == type && $0.logicalKey == key }
    }

    /// The `editCount` a tombstone was written at, or nil when the identity is
    /// not erased. A revival has to land above this.
    func erasedEditCount(_ type: RecordEntityType, key: String) -> Int? {
        erased.first { $0.entityType == type && $0.logicalKey == key }?.editCount
    }

    /// Drops a tombstone because the identity exists again, returning the
    /// `editCount` it was written at so the caller can out-rank it. Natural keys
    /// (`dayKey`) are recorded under the same identity they were erased under,
    /// so a surviving tombstone would re-delete the new row on the next sync
    /// and make `.skipErased` imports skip that day forever.
    @discardableResult
    mutating func clearErased(_ type: RecordEntityType, key: String) -> Int? {
        guard let index = erased.firstIndex(where: {
            $0.entityType == type && $0.logicalKey == key
        }) else { return nil }
        let editCount = erased[index].editCount
        erased.remove(at: index)
        return editCount
    }

    /// `atLeastEditCount` carries the version a remote tombstone was written at,
    /// so a device that never held the row still buries it at the right height.
    mutating func erase(
        _ type: RecordEntityType,
        key: String,
        at date: Date,
        atLeastEditCount: Int = 0
    ) {
        // Captured before the row goes away: the tombstone has to carry the
        // version it buried so a later revival can be ranked against it.
        let buriedEditCount = max(
            RecordsSyncPayload.editStamp(type: type, key: key, in: self)?.0 ?? 0,
            atLeastEditCount
        )
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
        case .focusTask:
            focusTasks.removeAll { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame }
        case .focusSession:
            focusSessions.removeAll { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame }
        case .focusPlanningConfiguration:
            focusPlanningConfiguration = nil
        }
        if let index = erased.firstIndex(where: {
            $0.entityType == type && $0.logicalKey == key
        }) {
            erased[index].editCount = max(erased[index].editCount, buriedEditCount)
        } else {
            erased.append(
                ErasedID(
                    entityType: type,
                    logicalKey: key,
                    erasedAt: date,
                    editCount: buriedEditCount
                )
            )
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
    static let schemaVersion = 4
    static let acceptedSchemaVersions = 1...4

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
            lifeProfile: state.lifeProfile.map { LifeProfileDTO($0, calendar: fileCalendar) },
            focusTasks: state.focusTasks.map { FocusTaskDTO($0, calendar: fileCalendar) },
            focusSessions: state.focusSessions.map { FocusSessionDTO($0, calendar: fileCalendar) },
            focusPlanningConfiguration: state.focusPlanningConfiguration.map(FocusPlanningConfigurationDTO.init),
            recordsStartedOn: state.recordsStartedOn.map { RecordJSON.dayKey($0, calendar: fileCalendar) }
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
        guard acceptedSchemaVersions.contains(document.schemaVersion) else {
            throw RecordJSONError.unknownSchemaVersion(document.schemaVersion)
        }
        return document
    }

    static func apply(
        _ document: RecordJSONDocument,
        to state: inout RecordState,
        mode: RecordImportMode
    ) throws -> RecordImportReport {
        guard acceptedSchemaVersions.contains(document.schemaVersion) else {
            throw RecordJSONError.unknownSchemaVersion(document.schemaVersion)
        }
        let calendar = calendar(from: document)
        var report = RecordImportReport()
        var periodIDMap: [UUID: UUID] = [:]
        var snapshotIDMap: [UUID: UUID] = [:]
        var taskIDMap: [UUID: UUID] = [:]
        var periodsByID = index(state.periods, \.id)
        var snapshotsByID = index(state.snapshots, \.id)
        var exceptionsByKey = index(state.exceptions, \.dayKey)
        var overridesByKey = index(state.overrides, \.dayKey)
        var observationsByID = index(state.observations, \.eventID)
        var tasksByID = index(state.focusTasks, \.id)
        var sessionsByID = index(state.focusSessions, \.id)
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
                existing: { archive in periodsByID[incoming.id].map { archive.periods[$0] } },
                incomingValue: { .period($0) },
                insert: { archive, value in
                    var next = value
                    if mode == .restoreErased, archive.isErased(.careerPeriod, key: incoming.id.uuidString) {
                        let newID = UUID()
                        periodIDMap[incoming.id] = newID
                        next.id = newID
                    }
                    periodsByID[next.id] = archive.periods.count
                    archive.periods.append(next)
                    return next
                },
                replace: { archive, value in
                    if let index = periodsByID[value.id] {
                        archive.periods[index] = value
                    }
                    return value
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
                existing: { archive in snapshotsByID[incoming.id].map { archive.snapshots[$0] } },
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
                    snapshotsByID[next.id] = archive.snapshots.count
                    archive.snapshots.append(next)
                    return next
                },
                replace: { archive, value in
                    var next = value
                    if let mapped = periodIDMap[next.periodID] {
                        next.periodID = mapped
                    }
                    if let index = snapshotsByID[next.id] {
                        archive.snapshots[index] = next
                    }
                    return next
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
                existing: { archive in exceptionsByKey[incoming.dayKey].map { archive.exceptions[$0] } },
                incomingValue: { .exception($0) },
                insert: { archive, value in
                    exceptionsByKey[value.dayKey] = archive.exceptions.count
                    archive.exceptions.append(value)
                    return value
                },
                replace: { archive, value in
                    if let index = exceptionsByKey[value.dayKey] {
                        archive.exceptions[index] = value
                    }
                    return value
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
                existing: { archive in overridesByKey[incoming.dayKey].map { archive.overrides[$0] } },
                incomingValue: { .override($0) },
                insert: { archive, value in
                    overridesByKey[value.dayKey] = archive.overrides.count
                    archive.overrides.append(value)
                    return value
                },
                replace: { archive, value in
                    if let index = overridesByKey[value.dayKey] {
                        archive.overrides[index] = value
                    }
                    return value
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
                existing: { archive in observationsByID[incoming.eventID].map { archive.observations[$0] } },
                incomingValue: { .observation($0) },
                insert: { archive, value in
                    var next = value
                    if mode == .restoreErased, archive.isErased(.workObservation, key: incoming.eventID.uuidString) {
                        next.eventID = UUID()
                    }
                    if let mapped = snapshotIDMap[next.scheduleSnapshotID] {
                        next.scheduleSnapshotID = mapped
                    }
                    observationsByID[next.eventID] = archive.observations.count
                    archive.observations.append(next)
                    return next
                },
                replace: { archive, value in
                    var next = value
                    if let mapped = snapshotIDMap[next.scheduleSnapshotID] {
                        next.scheduleSnapshotID = mapped
                    }
                    if let index = observationsByID[next.eventID] {
                        archive.observations[index] = next
                    }
                    return next
                }
            )
        }

        for dto in document.focusTasks ?? [] {
            guard let incoming = dto.value(calendar: calendar) else {
                report.rejected.append(
                    RecordImportRejection(entityType: .focusTask, logicalKey: dto.id)
                )
                continue
            }
            merge(
                incoming,
                type: .focusTask,
                key: incoming.id.uuidString,
                mode: mode,
                state: &state,
                report: &report,
                existing: { archive in tasksByID[incoming.id].map { archive.focusTasks[$0] } },
                incomingValue: { .focusTask($0) },
                insert: { archive, value in
                    var next = value
                    if mode == .restoreErased, archive.isErased(.focusTask, key: incoming.id.uuidString) {
                        let newID = UUID()
                        taskIDMap[incoming.id] = newID
                        next.id = newID
                    }
                    tasksByID[next.id] = archive.focusTasks.count
                    archive.focusTasks.append(next)
                    return next
                },
                replace: { archive, value in
                    if let index = tasksByID[value.id] {
                        archive.focusTasks[index] = value
                    }
                    return value
                }
            )
        }

        for dto in document.focusSessions ?? [] {
            guard let incoming = dto.value(calendar: calendar) else {
                report.rejected.append(
                    RecordImportRejection(entityType: .focusSession, logicalKey: dto.id)
                )
                continue
            }
            merge(
                incoming,
                type: .focusSession,
                key: incoming.id.uuidString,
                mode: mode,
                state: &state,
                report: &report,
                existing: { archive in sessionsByID[incoming.id].map { archive.focusSessions[$0] } },
                incomingValue: { .focusSession($0) },
                insert: { archive, value in
                    var next = value
                    if mode == .restoreErased, archive.isErased(.focusSession, key: incoming.id.uuidString) {
                        next.id = UUID()
                    }
                    if let taskID = next.taskID, let mapped = taskIDMap[taskID] {
                        next.taskID = mapped
                    }
                    sessionsByID[next.id] = archive.focusSessions.count
                    archive.focusSessions.append(next)
                    return next
                },
                replace: { archive, value in
                    var next = value
                    if let taskID = next.taskID, let mapped = taskIDMap[taskID] {
                        next.taskID = mapped
                    }
                    if let index = sessionsByID[next.id] {
                        archive.focusSessions[index] = next
                    }
                    return next
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
                insert: { archive, value in
                    archive.lifeProfile = value
                    return value
                },
                replace: { archive, value in
                    archive.lifeProfile = value
                    return value
                }
            )
        }

        if let dto = document.focusPlanningConfiguration {
            guard let incoming = dto.value() else {
                report.rejected.append(
                    RecordImportRejection(
                        entityType: .focusPlanningConfiguration,
                        logicalKey: FocusPlanningConfiguration.logicalKey
                    )
                )
                return report
            }
            merge(
                incoming,
                type: .focusPlanningConfiguration,
                key: FocusPlanningConfiguration.logicalKey,
                mode: mode,
                state: &state,
                report: &report,
                existing: { $0.focusPlanningConfiguration },
                incomingValue: { .focusPlanningConfiguration($0) },
                insert: { archive, value in
                    archive.focusPlanningConfiguration = value
                    return value
                },
                replace: { archive, value in
                    archive.focusPlanningConfiguration = value
                    return value
                }
            )
        }

        for index in state.snapshots.indices {
            if let mapped = periodIDMap[state.snapshots[index].periodID] {
                state.snapshots[index].periodID = mapped
            }
        }
        for index in state.observations.indices {
            if let mapped = snapshotIDMap[state.observations[index].scheduleSnapshotID] {
                state.observations[index].scheduleSnapshotID = mapped
            }
        }
        for index in state.focusSessions.indices {
            if let taskID = state.focusSessions[index].taskID, let mapped = taskIDMap[taskID] {
                state.focusSessions[index].taskID = mapped
            }
        }
        if var profile = state.lifeProfile {
            profile.migrateLegacyFields(calendar: calendar)
            state.lifeProfile = profile
        }
        if let started = document.recordsStartedOn,
           let date = date(fromDayKey: started, calendar: calendar) {
            if state.recordsStartedOn == nil || date < state.recordsStartedOn! {
                state.recordsStartedOn = date
            }
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
        case .focusTask(let task):
            if let index = state.focusTasks.firstIndex(where: { $0.id == task.id }) {
                state.focusTasks[index] = task
            } else {
                state.focusTasks.append(task)
            }
        case .focusSession(let session):
            if let index = state.focusSessions.firstIndex(where: { $0.id == session.id }) {
                state.focusSessions[index] = session
            } else {
                state.focusSessions.append(session)
            }
        case .focusPlanningConfiguration(let configuration):
            state.focusPlanningConfiguration = configuration
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
        insert: (inout RecordState, T) -> T,
        replace: (inout RecordState, T) -> T
    ) {
        if state.isErased(type, key: key) {
            switch mode {
            case .skipErased, .resolveByEditStamp:
                report.skippedErased[type, default: 0] += 1
                return
            case .restoreErased where existing(state) == nil:
                let written = insert(&state, incoming)
                report.restored[type, default: 0] += 1
                report.adopted.append(adoption(of: written, type: type, fallbackKey: key))
                return
            case .restoreErased:
                // A natural key (dayKey) keeps its identity across a restore, so
                // the tombstone can outlive a row that already exists again.
                // Inserting here would append a second row under the same key.
                break
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
                let written = replace(&state, incoming)
                report.adopted.append(adoption(of: written, type: type, fallbackKey: key))
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
        let written = insert(&state, incoming)
        report.inserted[type, default: 0] += 1
        report.adopted.append(adoption(of: written, type: type, fallbackKey: key))
    }

    /// First occurrence wins, matching the `firstIndex(where:)` lookups the
    /// coordinator uses everywhere else. `uniqueKeysWithValues` used to trap the
    /// process on a duplicate logical key, so one damaged archive turned every
    /// later import into a crash instead of a merge.
    private static func index<T, K: Hashable>(_ items: [T], _ key: KeyPath<T, K>) -> [K: Int] {
        Dictionary(
            items.enumerated().map { ($0.element[keyPath: key], $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func adoption(
        of value: some Equatable,
        type: RecordEntityType,
        fallbackKey: String
    ) -> RecordImportAdoption {
        RecordImportAdoption(
            entityType: type,
            logicalKey: identityKey(of: value) ?? fallbackKey,
            editCount: editCount(of: value),
            editTieBreaker: tieBreaker(of: value).uuidString
        )
    }

    private static func identityKey(of value: some Equatable) -> String? {
        switch value {
        case let period as CareerPeriod: period.id.uuidString
        case let snapshot as ScheduleSnapshot: snapshot.id.uuidString
        case let exception as CalendarException: exception.dayKey
        case let override as DayOverride: override.dayKey
        case let observation as WorkObservation: observation.eventID.uuidString
        case let task as FocusTask: task.id.uuidString
        case let session as FocusSession: session.id.uuidString
        case is FocusPlanningConfiguration: FocusPlanningConfiguration.logicalKey
        case is LifeProfile: LifeProfile.profileID.uuidString
        default: nil
        }
    }

    private static func editCount(of value: some Equatable) -> Int {
        switch value {
        case let period as CareerPeriod: period.editCount
        case let snapshot as ScheduleSnapshot: snapshot.editCount
        case let exception as CalendarException: exception.editCount
        case let override as DayOverride: override.editCount
        case let observation as WorkObservation:
            observation.editCount > 0 ? observation.editCount : 1
        case let profile as LifeProfile: profile.editCount
        case let task as FocusTask: task.editCount
        case let session as FocusSession: session.editCount
        case let configuration as FocusPlanningConfiguration: configuration.editCount
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
        case let observation as WorkObservation:
            observation.editTieBreaker == WorkObservation.unsetTieBreaker
                ? observation.eventID
                : observation.editTieBreaker
        case let task as FocusTask: task.editTieBreaker
        case let session as FocusSession: session.editTieBreaker
        case let configuration as FocusPlanningConfiguration: configuration.editTieBreaker
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
        return dayKey(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// The hottest string in the app: every resolved day, cell, observation and
    /// override is addressed by one of these. `String(format:)` goes through
    /// NSString's formatter, which measured at 42 ms of the 133 ms a
    /// life-sized day walk spent resolving days — a third of the walk in one
    /// line. Padding by hand is about forty times cheaper for the same output.
    /// `RecordJSONTests` holds the two implementations to the same result.
    static func dayKey(year: Int, month: Int, day: Int) -> String {
        "\(padded(year, width: 4))-\(padded(month, width: 2))-\(padded(day, width: 2))"
    }

    private static func padded(_ value: Int, width: Int) -> String {
        // Records dates are civil dates in a proleptic Gregorian or ISO 8601
        // calendar, so a negative component cannot occur; it is handled only so
        // the function is total.
        guard value >= 0 else { return "-\(padded(-value, width: width))" }
        return switch (width, value) {
        case (2, 0..<10): "0\(value)"
        case (4, 0..<10): "000\(value)"
        case (4, 10..<100): "00\(value)"
        case (4, 100..<1_000): "0\(value)"
        default: "\(value)"
        }
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
    var focusTasks: [FocusTaskDTO]?
    var focusSessions: [FocusSessionDTO]?
    var focusPlanningConfiguration: FocusPlanningConfigurationDTO?
    var recordsStartedOn: String?
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
    /// These were introduced by document schema v3. Missing fields from v1/v2
    /// records migrate to their immutable event values in `value(calendar:)`.
    var editedAtMs: Double?
    var editCount: Int?
    var editTieBreaker: String?

    init(_ value: WorkObservation, calendar: Calendar) {
        eventID = value.eventID.uuidString
        shiftAnchorDate = RecordJSON.dayKey(value.shiftAnchorDate, calendar: calendar)
        occurredAtMs = value.occurredAt.timeIntervalSince1970 * 1_000
        kind = value.kind
        valueData = value.valueData
        scheduleSnapshotID = value.scheduleSnapshotID.uuidString
        schemaVersion = value.schemaVersion
        timeZoneIdentifier = value.timeZoneIdentifier
        editedAtMs = (value.editedAt == .distantPast ? value.occurredAt : value.editedAt)
            .timeIntervalSince1970 * 1_000
        editCount = value.editCount > 0 ? value.editCount : 1
        editTieBreaker = (value.editTieBreaker == WorkObservation.unsetTieBreaker
            ? value.eventID
            : value.editTieBreaker).uuidString
    }

    func value(calendar: Calendar) -> WorkObservation? {
        guard let eventID = UUID(uuidString: eventID),
              let shiftAnchorDate = RecordJSON.date(fromDayKey: shiftAnchorDate, calendar: calendar),
              let scheduleSnapshotID = UUID(uuidString: scheduleSnapshotID)
        else { return nil }
        let occurredAt = Date(timeIntervalSince1970: occurredAtMs / 1_000)
        return WorkObservation(
            eventID: eventID,
            shiftAnchorDate: shiftAnchorDate,
            occurredAt: occurredAt,
            kind: kind,
            valueData: valueData,
            scheduleSnapshotID: scheduleSnapshotID,
            schemaVersion: schemaVersion,
            timeZoneIdentifier: timeZoneIdentifier ?? calendar.timeZone.identifier,
            editedAt: editedAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) } ?? occurredAt,
            editCount: max(1, editCount ?? 1),
            editTieBreaker: editTieBreaker.flatMap(UUID.init(uuidString:)) ?? eventID
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
    var bornOn: PartialCivilDate?
    var schoolStartedOn: PartialCivilDate?
    var workStartedPartial: PartialCivilDate?
    var retirementOn: PartialCivilDate?
    var averageSleepMinutes: Int?
    var sleepSource: SleepSource?
    var sleepSourceUpdatedAtMs: Double?
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
        bornOn = value.bornOn
        schoolStartedOn = value.schoolStartedOn
        workStartedPartial = value.workStartedPartial
        retirementOn = value.retirementOn
        averageSleepMinutes = value.averageSleepMinutes
        sleepSource = value.sleepSource
        sleepSourceUpdatedAtMs = value.sleepSourceUpdatedAt.map { $0.timeIntervalSince1970 * 1_000 }
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
        var profile = LifeProfile(
            profileID: profileID,
            birthYear: birthYear,
            workStartedOn: parsedWorkStartedOn,
            retirementAge: retirementAge,
            averageSleepHours: averageSleepHours,
            hidesExactAges: hidesExactAges,
            bornOn: bornOn,
            schoolStartedOn: schoolStartedOn,
            workStartedPartial: workStartedPartial,
            retirementOn: retirementOn,
            averageSleepMinutes: averageSleepMinutes,
            sleepSource: sleepSource,
            sleepSourceUpdatedAt: sleepSourceUpdatedAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) },
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker
        )
        profile.migrateLegacyFields(calendar: calendar)
        return profile
    }
}

struct FocusTaskDTO: Codable, Equatable {
    var id: String
    var createdAtMs: Double
    var plannedForDate: String?
    var scheduledStartAtMs: Double?
    var title: String
    var estimatedPomodoros: Int
    var icon: String?
    var isFavorite: Bool?
    var completedAtMs: Double?
    var deletedAtMs: Double?
    var sortIndex: Int
    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: String
    var templateID: String?
    var templateTaskKey: String?

    init(_ value: FocusTask, calendar: Calendar) {
        id = value.id.uuidString
        createdAtMs = value.createdAt.timeIntervalSince1970 * 1_000
        plannedForDate = value.plannedForDate.map { RecordJSON.dayKey($0, calendar: calendar) }
        scheduledStartAtMs = value.scheduledStartAt.map { $0.timeIntervalSince1970 * 1_000 }
        title = value.title
        estimatedPomodoros = value.estimatedPomodoros
        icon = value.icon.rawValue
        isFavorite = value.isFavorite
        completedAtMs = value.completedAt.map { $0.timeIntervalSince1970 * 1_000 }
        deletedAtMs = value.deletedAt.map { $0.timeIntervalSince1970 * 1_000 }
        sortIndex = value.sortIndex
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
        templateID = value.templateID?.uuidString
        templateTaskKey = value.templateTaskKey?.uuidString
    }

    func value(calendar: Calendar) -> FocusTask? {
        guard let id = UUID(uuidString: id),
              let editTieBreaker = UUID(uuidString: editTieBreaker)
        else { return nil }
        let planned: Date?
        if let plannedForDate {
            guard let date = RecordJSON.date(fromDayKey: plannedForDate, calendar: calendar) else { return nil }
            planned = date
        } else {
            planned = nil
        }
        return FocusTask(
            id: id,
            createdAt: Date(timeIntervalSince1970: createdAtMs / 1_000),
            plannedForDate: planned,
            scheduledStartAt: scheduledStartAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) },
            title: title,
            estimatedPomodoros: estimatedPomodoros,
            icon: icon.flatMap(FocusTaskIcon.init(rawValue:)) ?? .focus,
            isFavorite: isFavorite ?? false,
            completedAt: completedAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) },
            deletedAt: deletedAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) },
            sortIndex: sortIndex,
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker,
            templateID: templateID.flatMap(UUID.init(uuidString:)),
            templateTaskKey: templateTaskKey.flatMap(UUID.init(uuidString:))
        )
    }
}

struct FocusPlanningConfigurationDTO: Codable, Equatable {
    struct DayPlanDTO: Codable, Equatable {
        var dayKey: String
        var shiftStartAtMs: Int64
        var assignments: [FocusPlanAssignment]
        var appliedTemplateID: String?

        init(_ value: FocusDayPlan) {
            dayKey = value.dayKey
            shiftStartAtMs = value.shiftStartAtMs
            assignments = value.assignments.sorted { $0.blockStartAtMs < $1.blockStartAtMs }
            appliedTemplateID = value.appliedTemplateID?.uuidString
        }

        func value() -> FocusDayPlan? {
            let templateID: UUID?
            if let appliedTemplateID {
                guard let parsed = UUID(uuidString: appliedTemplateID) else { return nil }
                templateID = parsed
            } else {
                templateID = nil
            }
            return FocusDayPlan(
                dayKey: dayKey,
                shiftStartAtMs: shiftStartAtMs,
                assignments: assignments.sorted { $0.blockStartAtMs < $1.blockStartAtMs },
                appliedTemplateID: templateID
            )
        }
    }

    struct TemplateDTO: Codable, Equatable {
        var id: String
        var name: String
        var slots: [FocusTemplateSlot]
        var createdAtMs: Double
        var updatedAtMs: Double

        init(_ value: FocusTemplate) {
            id = value.id.uuidString
            name = value.name
            slots = value.slots.sorted { $0.blockIndex < $1.blockIndex }
            createdAtMs = value.createdAt.timeIntervalSince1970 * 1_000
            updatedAtMs = value.updatedAt.timeIntervalSince1970 * 1_000
        }

        func value() -> FocusTemplate? {
            guard let id = UUID(uuidString: id),
                  createdAtMs.isFinite,
                  updatedAtMs.isFinite
            else { return nil }
            return FocusTemplate(
                id: id,
                name: name,
                slots: slots.sorted { $0.blockIndex < $1.blockIndex },
                createdAt: Date(timeIntervalSince1970: createdAtMs / 1_000),
                updatedAt: Date(timeIntervalSince1970: updatedAtMs / 1_000)
            )
        }
    }

    var plans: [DayPlanDTO]
    var templates: [TemplateDTO]
    var defaultTemplateID: String?
    var autoAppliedDayKeys: [String]
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var longBreakEvery: Int
    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: String

    init(_ value: FocusPlanningConfiguration) {
        plans = value.planning.plans.values
            .sorted { $0.dayKey < $1.dayKey }
            .map(DayPlanDTO.init)
        templates = value.planning.templates
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map(TemplateDTO.init)
        defaultTemplateID = value.planning.defaultTemplateID?.uuidString
        autoAppliedDayKeys = value.planning.autoAppliedDayKeys.sorted()
        let settings = value.timerSettings.normalized
        focusMinutes = settings.focusMinutes
        shortBreakMinutes = settings.shortBreakMinutes
        longBreakMinutes = settings.longBreakMinutes
        longBreakEvery = settings.longBreakEvery
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
    }

    func value() -> FocusPlanningConfiguration? {
        guard let editTieBreaker = UUID(uuidString: editTieBreaker),
              editedAtMs.isFinite,
              editCount >= 0
        else { return nil }
        let decodedPlans = plans.compactMap { $0.value() }
        guard decodedPlans.count == plans.count else { return nil }
        var planMap: [String: FocusDayPlan] = [:]
        for plan in decodedPlans {
            guard planMap[plan.dayKey] == nil else { return nil }
            planMap[plan.dayKey] = plan
        }

        let decodedTemplates = templates.compactMap { $0.value() }
        guard decodedTemplates.count == templates.count,
              Set(decodedTemplates.map(\.id)).count == decodedTemplates.count
        else { return nil }

        let parsedDefaultTemplateID: UUID?
        if let defaultTemplateID {
            guard let parsed = UUID(uuidString: defaultTemplateID) else { return nil }
            parsedDefaultTemplateID = parsed
        } else {
            parsedDefaultTemplateID = nil
        }
        let availableTemplateIDs = Set(decodedTemplates.map(\.id))
        let safeDefault = parsedDefaultTemplateID.flatMap { availableTemplateIDs.contains($0) ? $0 : nil }
        return FocusPlanningConfiguration(
            planning: FocusPlanningState(
                plans: planMap,
                templates: decodedTemplates,
                defaultTemplateID: safeDefault,
                autoAppliedDayKeys: Set(autoAppliedDayKeys)
            ),
            timerSettings: FocusTimerSettings(
                focusMinutes: focusMinutes,
                shortBreakMinutes: shortBreakMinutes,
                longBreakMinutes: longBreakMinutes,
                longBreakEvery: longBreakEvery
            ).normalized,
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker
        )
    }
}

struct FocusSessionDTO: Codable, Equatable {
    var id: String
    var taskID: String?
    var shiftAnchorDate: String
    var startedAtMs: Double
    var plannedEndAtMs: Double
    var endedAtMs: Double?
    var endReason: FocusEndReason?
    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: String
    var kind: FocusSessionKind?
    var timeZoneIdentifier: String?
    var anchorDayKey: String?
    var actualDurationSeconds: Int?
    var plannedEndReason: FocusEndReason?

    init(_ value: FocusSession, calendar: Calendar) {
        id = value.id.uuidString
        taskID = value.taskID?.uuidString
        shiftAnchorDate = RecordJSON.dayKey(value.shiftAnchorDate, calendar: calendar)
        startedAtMs = value.startedAt.timeIntervalSince1970 * 1_000
        plannedEndAtMs = value.plannedEndAt.timeIntervalSince1970 * 1_000
        endedAtMs = value.endedAt.map { $0.timeIntervalSince1970 * 1_000 }
        endReason = value.endReason
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
        kind = value.kind
        timeZoneIdentifier = value.timeZoneIdentifier
        anchorDayKey = value.anchorDayKey
        actualDurationSeconds = value.actualDurationSeconds
        plannedEndReason = value.plannedEndReason
    }

    func value(calendar: Calendar) -> FocusSession? {
        guard let id = UUID(uuidString: id),
              let shiftAnchorDate = RecordJSON.date(fromDayKey: shiftAnchorDate, calendar: calendar),
              let editTieBreaker = UUID(uuidString: editTieBreaker)
        else { return nil }
        return FocusSession(
            id: id,
            taskID: taskID.flatMap(UUID.init(uuidString:)),
            shiftAnchorDate: shiftAnchorDate,
            startedAt: Date(timeIntervalSince1970: startedAtMs / 1_000),
            plannedEndAt: Date(timeIntervalSince1970: plannedEndAtMs / 1_000),
            endedAt: endedAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) },
            endReason: endReason,
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker,
            kind: kind ?? .focus,
            timeZoneIdentifier: timeZoneIdentifier ?? calendar.timeZone.identifier,
            anchorDayKey: anchorDayKey ?? RecordJSON.dayKey(shiftAnchorDate, calendar: calendar),
            actualDurationSeconds: actualDurationSeconds,
            plannedEndReason: plannedEndReason ?? FocusPlanner.endReason(
                startedAt: Date(timeIntervalSince1970: startedAtMs / 1_000),
                plannedEndAt: Date(timeIntervalSince1970: plannedEndAtMs / 1_000)
            )
        )
    }
}

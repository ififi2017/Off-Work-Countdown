import Foundation

enum SyncOutboxAction: String, Codable, Sendable {
    case save
    case erasePair
}

struct SyncAdapterRow: Equatable, Codable, Sendable {
    var entityType: RecordEntityType
    var logicalKey: String
    var recordName: String
    var dirty: Bool
    var generation: Int
    var lastKnownRecord: Data?
    var lastKnownPayload: Data?
    var pendingErase: Bool
    var editCount: Int
    var editTieBreaker: String
}

struct SyncConflictCopy: Equatable, Codable, Sendable {
    var entityType: RecordEntityType
    var logicalKey: String
    var payload: Data
    var lostAtMs: Double
}

struct SyncLocalState: Equatable, Codable, Sendable {
    var accountID: String?
    var generation: Int
    var syncEnabled: Bool
    var engineState: Data?
    var rows: [String: SyncAdapterRow]
    var conflicts: [SyncConflictCopy]
    var deletingCloud: Bool

    static let empty = SyncLocalState(
        accountID: nil,
        generation: 1,
        syncEnabled: false,
        engineState: nil,
        rows: [:],
        conflicts: [],
        deletingCloud: false
    )
}

enum RecordsSyncIdentity {
    static let controlZone = "owc-control"
    static let fenceRecord = "fence"

    static func dataZone(generation: Int) -> String {
        "owc-records.\(generation)"
    }

    static func generation(fromZoneName name: String) -> Int? {
        let prefix = "owc-records."
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }

    static func recordName(type: RecordEntityType, key: String) -> String {
        switch type {
        case .dayOverride: return "day.\(key)"
        case .calendarException: return "calx.\(key)"
        case .lifeProfile: return "profile"
        case .careerPeriod: return "period.\(key.lowercased())"
        case .scheduleSnapshot: return "snapshot.\(key.lowercased())"
        case .workObservation: return "obs.\(key.lowercased())"
        case .focusTask: return "task.\(key.lowercased())"
        case .focusSession: return "session.\(key.lowercased())"
        }
    }

    static func erasedName(type: RecordEntityType, key: String) -> String {
        "erased.\(type.rawValue).\(key)"
    }
}

enum RecordsSyncConflict {
    /// Winner = larger editCount; tie uses larger editTieBreaker string.
    static func localWins(
        localCount: Int,
        localTie: String,
        serverCount: Int,
        serverTie: String
    ) -> Bool {
        if localCount != serverCount { return localCount > serverCount }
        return localTie > serverTie
    }

    static func mergeLifeProfile(
        local: LifeProfile,
        server: LifeProfile,
        baseline: LifeProfile?
    ) -> LifeProfile {
        var merged = server
        let base = baseline
        if local.birthYear != base?.birthYear { merged.birthYear = local.birthYear }
        if local.workStartedOn != base?.workStartedOn { merged.workStartedOn = local.workStartedOn }
        if local.retirementAge != base?.retirementAge { merged.retirementAge = local.retirementAge }
        if local.averageSleepHours != base?.averageSleepHours {
            merged.averageSleepHours = local.averageSleepHours
        }
        if local.hidesExactAges != (base?.hidesExactAges ?? false) {
            merged.hidesExactAges = local.hidesExactAges
        }
        merged.editCount = max(local.editCount, server.editCount)
        merged.editTieBreaker = local.editTieBreaker > server.editTieBreaker
            ? local.editTieBreaker
            : server.editTieBreaker
        merged.editedAt = max(local.editedAt, server.editedAt)
        return merged
    }
}

enum RecordsSyncGeneration {
    static func shouldDiscard(recordGeneration: Int, fence: Int) -> Bool {
        recordGeneration < fence
    }

    static func staleZones(named names: [String], fence: Int) -> [String] {
        names.filter { name in
            guard let generation = RecordsSyncIdentity.generation(fromZoneName: name) else {
                return false
            }
            return generation < fence
        }
    }
}

enum RecordsSyncApplyAction: Equatable, Sendable {
    case ignore
    case insert
    case takeServer
    case keepLocalAndCopyServer
    case takeServerAndCopyLocal
    case mergeLife
}

enum RecordsSyncApply {
    static func action(
        type: RecordEntityType,
        locallyErased: Bool,
        localCount: Int?,
        localTie: String?,
        serverCount: Int,
        serverTie: String
    ) -> RecordsSyncApplyAction {
        if locallyErased { return .ignore }
        if type == .workObservation {
            return localCount == nil ? .insert : .ignore
        }
        guard let localCount, let localTie else { return .insert }
        if type == .lifeProfile { return .mergeLife }
        if RecordsSyncConflict.localWins(
            localCount: localCount,
            localTie: localTie,
            serverCount: serverCount,
            serverTie: serverTie
        ) {
            return .keepLocalAndCopyServer
        }
        return .takeServerAndCopyLocal
    }
}

enum RecordsSyncPayload {
    static func encode(type: RecordEntityType, key: String, from state: RecordState) -> Data? {
        let calendar = fileCalendar(for: state)
        switch type {
        case .careerPeriod:
            return state.periods.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .flatMap { try? JSONEncoder().encode(CareerPeriodDTO($0, calendar: $0.civilCalendar())) }
        case .scheduleSnapshot:
            guard let snapshot = state.snapshots.first(where: {
                $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }) else { return nil }
            let period = state.periods.first(where: { $0.id == snapshot.periodID })
            return try? JSONEncoder().encode(ScheduleSnapshotDTO(snapshot, calendar: period?.civilCalendar() ?? calendar))
        case .calendarException:
            return state.exceptions.first(where: { $0.dayKey == key })
                .flatMap { try? JSONEncoder().encode(CalendarExceptionDTO($0, calendar: calendar)) }
        case .dayOverride:
            return state.overrides.first(where: { $0.dayKey == key })
                .flatMap { try? JSONEncoder().encode(DayOverrideDTO($0, calendar: calendar)) }
        case .workObservation:
            return state.observations.first(where: {
                $0.eventID.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }).flatMap { try? JSONEncoder().encode(WorkObservationDTO($0, calendar: calendar)) }
        case .lifeProfile:
            return state.lifeProfile.flatMap { try? JSONEncoder().encode(LifeProfileDTO($0, calendar: calendar)) }
        case .focusTask:
            return state.focusTasks.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .flatMap { try? JSONEncoder().encode(FocusTaskDTO($0, calendar: calendar)) }
        case .focusSession:
            return state.focusSessions.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .flatMap { try? JSONEncoder().encode(FocusSessionDTO($0, calendar: calendar)) }
        }
    }

    static func incoming(from data: Data, type: RecordEntityType, calendar: Calendar) -> RecordIncomingValue? {
        switch type {
        case .careerPeriod:
            return (try? JSONDecoder().decode(CareerPeriodDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .period($0) }
        case .scheduleSnapshot:
            return (try? JSONDecoder().decode(ScheduleSnapshotDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .snapshot($0) }
        case .calendarException:
            return (try? JSONDecoder().decode(CalendarExceptionDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .exception($0) }
        case .dayOverride:
            return (try? JSONDecoder().decode(DayOverrideDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .override($0) }
        case .workObservation:
            return (try? JSONDecoder().decode(WorkObservationDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .observation($0) }
        case .lifeProfile:
            return (try? JSONDecoder().decode(LifeProfileDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .lifeProfile($0) }
        case .focusTask:
            return (try? JSONDecoder().decode(FocusTaskDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .focusTask($0) }
        case .focusSession:
            return (try? JSONDecoder().decode(FocusSessionDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .focusSession($0) }
        }
    }

    static func editStamp(type: RecordEntityType, key: String, in state: RecordState) -> (Int, String)? {
        switch type {
        case .careerPeriod:
            return state.periods.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .scheduleSnapshot:
            return state.snapshots.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .calendarException:
            return state.exceptions.first(where: { $0.dayKey == key })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .dayOverride:
            return state.overrides.first(where: { $0.dayKey == key })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .workObservation:
            return state.observations.contains(where: {
                $0.eventID.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }) ? (1, key) : nil
        case .lifeProfile:
            return state.lifeProfile.map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .focusTask:
            return state.focusTasks.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .focusSession:
            return state.focusSessions.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        }
    }

    static func fileCalendar(for state: RecordState) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: state.periods.first?.timeZoneIdentifier ?? "") ?? .current
        return calendar
    }
}

enum RecordsSyncOutbox {
    static func markDirty(
        _ state: inout SyncLocalState,
        type: RecordEntityType,
        key: String,
        editCount: Int,
        editTieBreaker: UUID,
        erase: Bool = false
    ) {
        let name = RecordsSyncIdentity.recordName(type: type, key: key)
        var row = state.rows[name] ?? SyncAdapterRow(
            entityType: type,
            logicalKey: key,
            recordName: name,
            dirty: true,
            generation: state.generation,
            lastKnownRecord: nil,
            lastKnownPayload: nil,
            pendingErase: erase,
            editCount: editCount,
            editTieBreaker: editTieBreaker.uuidString
        )
        row.dirty = true
        row.pendingErase = erase
        row.generation = state.generation
        row.editCount = editCount
        row.editTieBreaker = editTieBreaker.uuidString
        state.rows[name] = row
    }

    static func pending(_ state: SyncLocalState) -> [SyncAdapterRow] {
        state.rows.values.filter(\.dirty).sorted { $0.recordName < $1.recordName }
    }

    static func clearDirty(_ state: inout SyncLocalState, recordName: String) {
        state.rows[recordName]?.dirty = false
        state.rows[recordName]?.pendingErase = false
    }

    static func applyHigherFence(_ state: inout SyncLocalState, fence: Int) -> Bool {
        guard fence > state.generation else { return false }
        state.generation = fence
        state.rows.removeAll()
        state.conflicts.removeAll()
        state.deletingCloud = false
        return true
    }
}

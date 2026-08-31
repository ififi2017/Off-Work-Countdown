import CryptoKit
import Foundation

enum ScheduleHoursCodec {
    static func encode(_ configuration: ScheduleHoursConfiguration) throws -> (data: Data, fingerprint: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(configuration)
        let digest = SHA256.hash(data: data)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        return (data, fingerprint)
    }
}

enum RecordPersistenceError: Error, Equatable {
    case unreadableArchive
    case invalidArchive
    case writeFailed
}

/// What Records should show when persistence is not healthy.
/// Damaged/unreadable files get a quarantine action; a save failure does not.
enum RecordsArchiveBanner: Equatable {
    case damaged
    case saveFailed

    init?(error: RecordPersistenceError?) {
        switch error {
        case .invalidArchive, .unreadableArchive:
            self = .damaged
        case .writeFailed:
            self = .saveFailed
        case nil:
            return nil
        }
    }
}

/// Serializes every records write. The archive is a local JSON file in
/// Application Support — not the App Group, and not SwiftData yet.
@MainActor
@Observable
final class RecordCoordinator {
    private(set) var state = RecordState()
    /// A damaged archive is never treated as an empty first launch. Once set
    /// to `.invalidArchive` or `.unreadableArchive`, writes are blocked until
    /// the caller quarantines the file. `.writeFailed` does not lock writes.
    private(set) var persistenceError: RecordPersistenceError?
    var archiveBanner: RecordsArchiveBanner? { RecordsArchiveBanner(error: persistenceError) }
    var blocksWrites: Bool {
        persistenceError == .invalidArchive || persistenceError == .unreadableArchive
    }
    private let fileURL: URL?
    var captureEnabled = true

    static func inMemory() -> RecordCoordinator {
        RecordCoordinator(fileURL: nil)
    }

    static func persisted() -> RecordCoordinator {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "owc-records", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return RecordCoordinator(fileURL: root.appending(path: "archive.json"))
    }

    init(fileURL: URL?) {
        self.fileURL = fileURL
        if fileURL != nil { load() }
    }

    func deleteAllLocalData() {
        guard !blocksWrites else { return }
        state.deleteAllLocalData()
        state.sync = SyncLocalState.empty
        persist()
    }

    /// Moves a damaged archive aside as `.corrupt-*` and starts a fresh file.
    /// This does not restore old rows. `.writeFailed` is a no-op — it must not
    /// enter the quarantine path.
    @discardableResult
    func quarantineCorruptedArchive(at date: Date = .now) throws -> URL? {
        guard blocksWrites else { return nil }
        var backupURL: URL?
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            let backup = Self.corruptBackupURL(for: fileURL, at: date)
            do {
                try FileManager.default.moveItem(at: fileURL, to: backup)
                backupURL = backup
            } catch {
                throw RecordPersistenceError.writeFailed
            }
        }
        state = RecordState()
        persistenceError = nil
        persist()
        if let persistenceError { throw persistenceError }
        return backupURL
    }

    static func corruptBackupURL(for fileURL: URL, at date: Date = .now) -> URL {
        let stamp = Int(date.timeIntervalSince1970)
        let ext = fileURL.pathExtension
        let suffix = ext.isEmpty ? "corrupt-\(stamp)" : "corrupt-\(stamp).\(ext)"
        return fileURL.deletingPathExtension().appendingPathExtension(suffix)
    }

    func erase(_ type: RecordEntityType, key: String, at date: Date = .now) {
        guard !blocksWrites else { return }
        state.erase(type, key: key, at: date)
        RecordsSyncOutbox.markDirty(
            &state.sync,
            type: type,
            key: key,
            editCount: 0,
            editTieBreaker: UUID(),
            erase: true
        )
        persist()
    }

    func exportJSON(exportedAt: Date = .now, timeZone: TimeZone = .current) throws -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try RecordJSON.export(state, exportedAt: exportedAt, timeZone: timeZone, calendar: calendar)
    }

    func `import`(_ data: Data, mode: RecordImportMode = .skipErased) throws -> RecordImportReport {
        if let persistenceError, blocksWrites { throw persistenceError }
        let document = try RecordJSON.decode(data)
        let report = try RecordJSON.apply(document, to: &state, mode: mode)
        persist()
        return report
    }

    func ensureSeeded(
        hours: ScheduleHoursConfiguration,
        at date: Date,
        timeZone: TimeZone = .current
    ) {
        guard !blocksWrites else { return }
        if !state.periods.isEmpty { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startsOn = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? date
        let period = CareerPeriod(
            id: UUID(),
            startsOn: startsOn,
            endsBefore: nil,
            label: nil,
            timeZoneIdentifier: timeZone.identifier,
            calendarIdentifier: "gregorian",
            createdAt: date,
            editedAt: date,
            editCount: 1,
            editTieBreaker: UUID()
        )
        state.periods.append(period)
        appendSnapshot(hours, periodID: period.id, effectiveFrom: startsOn, at: date)
        markDirty(.careerPeriod, key: period.id.uuidString, editCount: period.editCount, tie: period.editTieBreaker)
        persist()
    }

    func commitHours(
        _ hours: ScheduleHoursConfiguration,
        effectiveFrom: Date,
        at date: Date,
        timeZone: TimeZone = .current
    ) {
        guard !blocksWrites else { return }
        ensureSeeded(hours: hours, at: date, timeZone: timeZone)
        guard let period = DayRecordResolver.period(on: effectiveFrom, from: state.periods) else { return }
        guard let encoded = try? ScheduleHoursCodec.encode(hours) else { return }
        if let current = DayRecordResolver.snapshot(on: effectiveFrom, in: period, from: state.snapshots),
           current.fingerprint == encoded.fingerprint {
            return
        }
        appendSnapshot(hours, periodID: period.id, effectiveFrom: effectiveFrom, at: date)
        persist()
    }

    func upsertOverride(_ draft: DayOverride, at date: Date = .now) {
        guard !blocksWrites else { return }
        if let index = state.overrides.firstIndex(where: { $0.dayKey == draft.dayKey }) {
            var next = draft
            next.editCount = state.overrides[index].editCount + 1
            next.editTieBreaker = UUID()
            next.editedAt = date
            state.overrides[index] = next
        } else {
            var next = draft
            next.editCount = max(next.editCount, 0) + 1
            next.editTieBreaker = UUID()
            next.editedAt = date
            state.overrides.append(next)
        }
        if let row = state.overrides.first(where: { $0.dayKey == draft.dayKey }) {
            markDirty(.dayOverride, key: row.dayKey, editCount: row.editCount, tie: row.editTieBreaker)
        }
        persist()
    }

    func upsertException(_ draft: CalendarException, at date: Date = .now) {
        guard !blocksWrites else { return }
        if let index = state.exceptions.firstIndex(where: { $0.dayKey == draft.dayKey }) {
            var next = draft
            next.editCount = state.exceptions[index].editCount + 1
            next.editTieBreaker = UUID()
            next.editedAt = date
            state.exceptions[index] = next
        } else {
            var next = draft
            next.editCount = max(next.editCount, 0) + 1
            next.editTieBreaker = UUID()
            next.editedAt = date
            state.exceptions.append(next)
        }
        if let row = state.exceptions.first(where: { $0.dayKey == draft.dayKey }) {
            markDirty(.calendarException, key: row.dayKey, editCount: row.editCount, tie: row.editTieBreaker)
        }
        persist()
    }

    func updateLifeProfile(_ profile: LifeProfile) {
        guard !blocksWrites else { return }
        var next = profile
        if let current = state.lifeProfile {
            next.editCount = current.editCount + 1
        } else {
            next.editCount = max(next.editCount, 0) + 1
        }
        next.editTieBreaker = UUID()
        next.editedAt = .now
        state.lifeProfile = next
        markDirty(.lifeProfile, key: LifeProfile.profileID.uuidString, editCount: next.editCount, tie: next.editTieBreaker)
        persist()
    }

    func upsertFocusTask(_ draft: FocusTask, at date: Date = .now) {
        guard !blocksWrites else { return }
        var next = draft
        if let index = state.focusTasks.firstIndex(where: { $0.id == draft.id }) {
            next.editCount = state.focusTasks[index].editCount + 1
            next.editTieBreaker = UUID()
            next.editedAt = date
            state.focusTasks[index] = next
        } else {
            next.editCount = max(next.editCount, 0) + 1
            next.editTieBreaker = UUID()
            next.editedAt = date
            state.focusTasks.append(next)
        }
        markDirty(.focusTask, key: next.id.uuidString, editCount: next.editCount, tie: next.editTieBreaker)
        persist()
    }

    func upsertFocusSession(_ draft: FocusSession, at date: Date = .now) {
        guard !blocksWrites else { return }
        var next = draft
        if let index = state.focusSessions.firstIndex(where: { $0.id == draft.id }) {
            next.editCount = state.focusSessions[index].editCount + 1
            next.editTieBreaker = UUID()
            next.editedAt = date
            state.focusSessions[index] = next
        } else {
            next.editCount = max(next.editCount, 0) + 1
            next.editTieBreaker = UUID()
            next.editedAt = date
            state.focusSessions.append(next)
        }
        markDirty(.focusSession, key: next.id.uuidString, editCount: next.editCount, tie: next.editTieBreaker)
        persist()
    }

    func replaceSyncState(_ sync: SyncLocalState) {
        state.sync = sync
        persist()
    }

    func applyIncomingValue(_ value: RecordIncomingValue) {
        guard !blocksWrites else { return }
        RecordJSON.applyIncoming(value, to: &state)
        persist()
    }

    func applyRemoteErase(type: RecordEntityType, key: String, at date: Date = .now) {
        guard !blocksWrites else { return }
        state.erase(type, key: key, at: date)
        persist()
    }

    /// Applies a CloudKit row without treating it as a local edit.
    func applyRemotePayload(
        type: RecordEntityType,
        key: String,
        payload: Data,
        editCount: Int,
        editTieBreaker: String,
        systemFields: Data?,
        generation: Int
    ) {
        guard !blocksWrites else { return }
        let calendar = RecordsSyncPayload.fileCalendar(for: state)
        guard let incoming = RecordsSyncPayload.incoming(from: payload, type: type, calendar: calendar) else {
            return
        }
        let local = RecordsSyncPayload.editStamp(type: type, key: key, in: state)
        let action = RecordsSyncApply.action(
            type: type,
            locallyErased: state.isErased(type, key: key),
            localCount: local?.0,
            localTie: local?.1,
            serverCount: editCount,
            serverTie: editTieBreaker
        )
        let name = RecordsSyncIdentity.recordName(type: type, key: key)
        switch action {
        case .ignore:
            break
        case .insert, .takeServer:
            RecordJSON.applyIncoming(incoming, to: &state)
            RecordsSyncOutbox.clearDirty(&state.sync, recordName: name)
        case .keepLocalAndCopyServer:
            state.sync.conflicts.append(
                SyncConflictCopy(
                    entityType: type,
                    logicalKey: key,
                    payload: payload,
                    lostAtMs: Date.now.timeIntervalSince1970 * 1_000
                )
            )
        case .takeServerAndCopyLocal:
            if let localPayload = RecordsSyncPayload.encode(type: type, key: key, from: state) {
                state.sync.conflicts.append(
                    SyncConflictCopy(
                        entityType: type,
                        logicalKey: key,
                        payload: localPayload,
                        lostAtMs: Date.now.timeIntervalSince1970 * 1_000
                    )
                )
            }
            RecordJSON.applyIncoming(incoming, to: &state)
            RecordsSyncOutbox.clearDirty(&state.sync, recordName: name)
        case .mergeLife:
            if case .lifeProfile(let server) = incoming, let localProfile = state.lifeProfile {
                let baseline = lastKnownLifeProfile()
                let merged = RecordsSyncConflict.mergeLifeProfile(
                    local: localProfile,
                    server: server,
                    baseline: baseline
                )
                state.lifeProfile = merged
                RecordsSyncOutbox.markDirty(
                    &state.sync,
                    type: .lifeProfile,
                    key: LifeProfile.profileID.uuidString,
                    editCount: merged.editCount,
                    editTieBreaker: merged.editTieBreaker
                )
            } else {
                RecordJSON.applyIncoming(incoming, to: &state)
                RecordsSyncOutbox.clearDirty(&state.sync, recordName: name)
            }
        }
        var row = state.sync.rows[name] ?? SyncAdapterRow(
            entityType: type,
            logicalKey: key,
            recordName: name,
            dirty: action == .keepLocalAndCopyServer || action == .mergeLife,
            generation: generation,
            lastKnownRecord: systemFields,
            lastKnownPayload: payload,
            pendingErase: false,
            editCount: editCount,
            editTieBreaker: editTieBreaker
        )
        row.lastKnownRecord = systemFields
        row.lastKnownPayload = payload
        row.generation = generation
        state.sync.rows[name] = row
        persist()
    }

    private func lastKnownLifeProfile() -> LifeProfile? {
        guard let data = state.sync.rows[RecordsSyncIdentity.recordName(type: .lifeProfile, key: LifeProfile.profileID.uuidString)]?
            .lastKnownPayload
        else { return nil }
        let calendar = RecordsSyncPayload.fileCalendar(for: state)
        if case .lifeProfile(let profile) = RecordsSyncPayload.incoming(from: data, type: .lifeProfile, calendar: calendar) {
            return profile
        }
        return nil
    }

    func currentSnapshotID(on day: Date) -> UUID? {
        guard let period = DayRecordResolver.period(on: day, from: state.periods) else { return nil }
        return DayRecordResolver.snapshot(on: day, in: period, from: state.snapshots)?.id
    }

    func migrateCalendarTimeZone(to identifier: String, at date: Date = .now) {
        guard !blocksWrites else { return }
        guard let targetTimeZone = TimeZone(identifier: identifier) else { return }
        let oldPeriods = Dictionary(uniqueKeysWithValues: state.periods.map { ($0.id, $0) })
        let oldLifeCalendar = state.periods.first?.civilCalendar() ?? defaultCalendar(timeZone: .current)
        for index in state.periods.indices {
            let oldCalendar = state.periods[index].civilCalendar()
            var targetCalendar = Calendar(identifier: state.periods[index].calendarIdentifier == "iso8601" ? .iso8601 : .gregorian)
            targetCalendar.timeZone = targetTimeZone
            state.periods[index].startsOn = preserveCivilDate(state.periods[index].startsOn, from: oldCalendar, in: targetCalendar)
            if let endsBefore = state.periods[index].endsBefore {
                state.periods[index].endsBefore = preserveCivilDate(endsBefore, from: oldCalendar, in: targetCalendar)
            }
            state.periods[index].timeZoneIdentifier = identifier
            state.periods[index].editedAt = date
            state.periods[index].editCount += 1
            state.periods[index].editTieBreaker = UUID()
        }
        for index in state.snapshots.indices {
            guard let oldPeriod = oldPeriods[state.snapshots[index].periodID] else { continue }
            let oldCalendar = oldPeriod.civilCalendar()
            var targetCalendar = Calendar(identifier: oldPeriod.calendarIdentifier == "iso8601" ? .iso8601 : .gregorian)
            targetCalendar.timeZone = targetTimeZone
            let migrated = preserveCivilDate(
                state.snapshots[index].effectiveFrom,
                from: oldCalendar,
                in: targetCalendar
            )
            if migrated != state.snapshots[index].effectiveFrom {
                state.snapshots[index].effectiveFrom = migrated
                state.snapshots[index].editedAt = date
                state.snapshots[index].editCount += 1
                state.snapshots[index].editTieBreaker = UUID()
            }
        }
        for index in state.overrides.indices {
            let oldCalendar = calendar(timeZoneIdentifier: state.overrides[index].timeZoneIdentifier)
            var targetCalendar = Calendar(identifier: .gregorian)
            targetCalendar.timeZone = targetTimeZone
            state.overrides[index].shiftAnchorDate = preserveCivilDate(
                state.overrides[index].shiftAnchorDate,
                from: oldCalendar,
                in: targetCalendar
            )
            state.overrides[index].timeZoneIdentifier = identifier
            state.overrides[index].editedAt = date
            state.overrides[index].editCount += 1
            state.overrides[index].editTieBreaker = UUID()
        }
        for index in state.exceptions.indices {
            let oldCalendar = calendar(timeZoneIdentifier: state.exceptions[index].timeZoneIdentifier)
            var targetCalendar = Calendar(identifier: .gregorian)
            targetCalendar.timeZone = targetTimeZone
            state.exceptions[index].date = preserveCivilDate(
                state.exceptions[index].date,
                from: oldCalendar,
                in: targetCalendar
            )
            state.exceptions[index].timeZoneIdentifier = identifier
            state.exceptions[index].editedAt = date
            state.exceptions[index].editCount += 1
            state.exceptions[index].editTieBreaker = UUID()
        }
        for index in state.observations.indices {
            let oldCalendar = calendar(timeZoneIdentifier: state.observations[index].timeZoneIdentifier)
            var targetCalendar = Calendar(identifier: .gregorian)
            targetCalendar.timeZone = targetTimeZone
            state.observations[index].shiftAnchorDate = preserveCivilDate(
                state.observations[index].shiftAnchorDate,
                from: oldCalendar,
                in: targetCalendar
            )
            state.observations[index].timeZoneIdentifier = identifier
        }
        if var profile = state.lifeProfile {
            var targetCalendar = Calendar(identifier: .gregorian)
            targetCalendar.timeZone = targetTimeZone
            if let workStartedOn = profile.workStartedOn {
                let migrated = preserveCivilDate(workStartedOn, from: oldLifeCalendar, in: targetCalendar)
                if migrated != workStartedOn {
                    profile.workStartedOn = migrated
                }
            }
            state.lifeProfile = profile
        }
        persist()
    }

    private func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    private func defaultCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func preserveCivilDate(_ date: Date, from source: Calendar, in target: Calendar) -> Date {
        let parts = source.dateComponents([.era, .year, .month, .day], from: date)
        return target.date(from: parts) ?? date
    }

    func recordObservation(
        kind: WorkObservationKind,
        eventID: UUID,
        shiftAnchorDate: Date,
        occurredAt: Date,
        snapshotID: UUID,
        valueData: Data? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        guard captureEnabled, !blocksWrites else { return }
        if state.isErased(.workObservation, key: eventID.uuidString) { return }
        if state.observations.contains(where: { $0.eventID == eventID }) { return }
        if kind == .timerSurfaceFirstSeen {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
            let day = calendar.startOfDay(for: shiftAnchorDate)
            let already = state.observations.contains {
                $0.kind == .timerSurfaceFirstSeen
                    && calendar.isDate($0.shiftAnchorDate, inSameDayAs: day)
            }
            if already { return }
        }
        state.observations.append(
            WorkObservation(
                eventID: eventID,
                shiftAnchorDate: shiftAnchorDate,
                occurredAt: occurredAt,
                kind: kind,
                valueData: valueData,
                scheduleSnapshotID: snapshotID,
                timeZoneIdentifier: timeZoneIdentifier
            )
        )
        markDirty(.workObservation, key: eventID.uuidString, editCount: 1, tie: eventID)
        persist()
    }

    private func appendSnapshot(
        _ hours: ScheduleHoursConfiguration,
        periodID: UUID,
        effectiveFrom: Date,
        at date: Date
    ) {
        guard let encoded = try? ScheduleHoursCodec.encode(hours) else { return }
        let snapshot = ScheduleSnapshot(
            id: UUID(),
            periodID: periodID,
            effectiveFrom: effectiveFrom,
            configurationData: encoded.data,
            fingerprint: encoded.fingerprint,
            editedAt: date,
            editCount: 1,
            editTieBreaker: UUID()
        )
        state.snapshots.append(snapshot)
        markDirty(.scheduleSnapshot, key: snapshot.id.uuidString, editCount: snapshot.editCount, tie: snapshot.editTieBreaker)
    }

    private func markDirty(
        _ type: RecordEntityType,
        key: String,
        editCount: Int,
        tie: UUID,
        erase: Bool = false
    ) {
        RecordsSyncOutbox.markDirty(
            &state.sync,
            type: type,
            key: key,
            editCount: editCount,
            editTieBreaker: tie,
            erase: erase
        )
    }

    private func load() {
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let file = try JSONDecoder().decode(RecordLocalFile.self, from: data)
            let document = try RecordJSON.decode(file.document)
            var archive = RecordState()
            let report = try RecordJSON.apply(document, to: &archive, mode: .skipErased)
            guard report.rejected.isEmpty else { throw RecordJSONError.invalidDocument }
            archive.erased = file.erased.map {
                ErasedID(
                    entityType: $0.entityType,
                    logicalKey: $0.logicalKey,
                    erasedAt: Date(timeIntervalSince1970: $0.erasedAtMs / 1_000)
                )
            }
            archive.sync = file.sync ?? .empty
            state = archive
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            persistenceError = .unreadableArchive
        } catch {
            persistenceError = .invalidArchive
        }
    }

    private func persist() {
        guard let fileURL,
              persistenceError != .invalidArchive,
              persistenceError != .unreadableArchive
        else { return }
        let timeZone = TimeZone(identifier: state.periods.first?.timeZoneIdentifier ?? "") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        do {
            let documentData = try RecordJSON.export(
                state,
                exportedAt: .now,
                timeZone: timeZone,
                calendar: calendar
            )
            _ = try RecordJSON.decode(documentData)
            let file = RecordLocalFile(
                schemaVersion: RecordJSON.schemaVersion,
                document: documentData,
                erased: state.erased.map {
                    ErasedDTO(entityType: $0.entityType, logicalKey: $0.logicalKey, erasedAtMs: $0.erasedAt.timeIntervalSince1970 * 1_000)
                },
                sync: state.sync
            )
            let data = try JSONEncoder().encode(file)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = .writeFailed
        }
    }
}

private struct RecordLocalFile: Codable {
    var schemaVersion: Int
    var document: Data
    var erased: [ErasedDTO]
    var sync: SyncLocalState?
}

private struct ErasedDTO: Codable {
    var entityType: RecordEntityType
    var logicalKey: String
    var erasedAtMs: Double
}

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
    /// Cheap invalidation token for views. Comparing `state` is an Equatable
    /// walk of the whole archive, which is what made switching to the Records
    /// tab hitch even when the list was empty.
    private(set) var revision: UInt64 = 0
    var archiveBanner: RecordsArchiveBanner? { RecordsArchiveBanner(error: persistenceError) }
    var blocksWrites: Bool {
        persistenceError == .invalidArchive || persistenceError == .unreadableArchive
    }
    private let fileURL: URL?
    var captureEnabled = true
    /// CKSyncEngine must hear about every dirty row, not only the first enable.
    var onDirty: (() -> Void)?
    /// The owning store resolves cross-device open focus sessions after a
    /// complete remote batch has reached durable local storage.
    var onRemoteBatchApplied: (() -> Void)?
    /// Import and remote sync both replace external record state. Consumers
    /// that derive transient timers must reconcile only after that state is
    /// durable, rather than relying on a particular transport.
    var onExternalStateApplied: (() -> Void)?

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

    @discardableResult
    func deleteAllLocalData() -> Bool {
        guard !blocksWrites else { return false }
        let next = RecordState()
        do {
            try writeArchive(next)
            state = next
            revision &+= 1
            persistenceError = nil
            onExternalStateApplied?()
            return true
        } catch {
            persistenceError = .writeFailed
            return false
        }
    }

    func discardForHigherFence(_ fence: Int) -> Bool {
        var next = state
        guard RecordsSyncOutbox.discardLocalArchive(&next, fence: fence) else { return false }
        do {
            try writeArchive(next)
            state = next
            revision &+= 1
            persistenceError = nil
            return true
        } catch {
            persistenceError = .writeFailed
            return false
        }
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

    func exportJSON(
        exportedAt: Date = .now,
        timeZone: TimeZone = .current,
        includeLifeProfile: Bool = true
    ) throws -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var archive = state
        if !includeLifeProfile { archive.lifeProfile = nil }
        return try RecordJSON.export(archive, exportedAt: exportedAt, timeZone: timeZone, calendar: calendar)
    }

    func `import`(_ data: Data, mode: RecordImportMode = .skipErased) throws -> RecordImportReport {
        if let persistenceError, blocksWrites { throw persistenceError }
        let document = try RecordJSON.decode(data)
        var candidate = state
        let report = try RecordJSON.apply(document, to: &candidate, mode: mode)
        RecordsSyncOutbox.markAdopted(&candidate.sync, report: report, state: candidate)
        parkUnresolvedImportConflicts(into: &candidate, report.conflicts)
        do {
            try writeArchive(candidate)
            state = candidate
            revision &+= 1
            persistenceError = nil
            onExternalStateApplied?()
            if !report.adopted.isEmpty { onDirty?() }
        } catch {
            persistenceError = .writeFailed
            throw RecordPersistenceError.writeFailed
        }
        return report
    }

    func ensureSeeded(
        hours: ScheduleHoursConfiguration,
        at date: Date,
        timeZone: TimeZone = .current
    ) {
        guard !blocksWrites else { return }
        if !state.periods.isEmpty { return }
        LaunchTrace.interval("recordsSeed") {
            seedFirstPeriod(hours: hours, at: date, timeZone: timeZone)
        }
    }

    private func seedFirstPeriod(
        hours: ScheduleHoursConfiguration,
        at date: Date,
        timeZone: TimeZone
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startsOn = calendar.startOfDay(for: date)
        if state.recordsStartedOn == nil {
            state.recordsStartedOn = startsOn
        }
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

    @discardableResult
    func commitHours(
        _ hours: ScheduleHoursConfiguration,
        effectiveFrom: Date,
        at date: Date,
        timeZone: TimeZone = .current
    ) -> Bool {
        guard !blocksWrites else { return false }
        ensureSeeded(hours: hours, at: date, timeZone: timeZone)
        return commitHoursToExistingPeriod(hours, effectiveFrom: effectiveFrom, at: date)
    }

    /// Repairs drift between device-local schedule preferences and an existing
    /// Records archive without turning app launch into the first record. Old
    /// versions could persist the preferences without appending their matching
    /// snapshot, leaving Records on the original 09:00–17:00 / 60-minute
    /// defaults indefinitely.
    @discardableResult
    func reconcileExistingHours(
        _ hours: ScheduleHoursConfiguration,
        effectiveFrom: Date,
        at date: Date
    ) -> Bool {
        guard !blocksWrites, !state.periods.isEmpty else { return false }
        return commitHoursToExistingPeriod(hours, effectiveFrom: effectiveFrom, at: date)
    }

    private func commitHoursToExistingPeriod(
        _ hours: ScheduleHoursConfiguration,
        effectiveFrom: Date,
        at date: Date
    ) -> Bool {
        guard let period = DayRecordResolver.period(on: effectiveFrom, from: state.periods) else {
            return false
        }
        guard let encoded = try? ScheduleHoursCodec.encode(hours) else { return false }
        if let current = DayRecordResolver.snapshot(on: effectiveFrom, in: period, from: state.snapshots),
           current.fingerprint == encoded.fingerprint {
            return false
        }
        upsertSnapshot(
            data: encoded.data,
            fingerprint: encoded.fingerprint,
            periodID: period.id,
            effectiveFrom: effectiveFrom,
            at: date
        )
        persist()
        return persistenceError == nil
    }

    func upsertOverride(_ draft: DayOverride, at date: Date = .now, persist persistAfter: Bool = true) {
        guard !blocksWrites else { return }
        let revokedErase = state.clearErased(.dayOverride, key: draft.dayKey)
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
        if let index = state.overrides.firstIndex(where: { $0.dayKey == draft.dayKey }) {
            reviveAboveTombstone(&state.overrides[index].editCount, over: revokedErase)
            let row = state.overrides[index]
            markDirty(
                .dayOverride,
                key: row.dayKey,
                editCount: row.editCount,
                tie: row.editTieBreaker,
                revokeErase: revokedErase != nil
            )
        }
        if persistAfter { persist() }
    }

    func upsertException(_ draft: CalendarException, at date: Date = .now, persist persistAfter: Bool = true) {
        guard !blocksWrites else { return }
        let revokedErase = state.clearErased(.calendarException, key: draft.dayKey)
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
        if let index = state.exceptions.firstIndex(where: { $0.dayKey == draft.dayKey }) {
            reviveAboveTombstone(&state.exceptions[index].editCount, over: revokedErase)
            let row = state.exceptions[index]
            markDirty(
                .calendarException,
                key: row.dayKey,
                editCount: row.editCount,
                tie: row.editTieBreaker,
                revokeErase: revokedErase != nil
            )
        }
        if persistAfter { persist() }
    }

    func updateLifeProfile(_ profile: LifeProfile) {
        guard !blocksWrites else { return }
        var next = profile
        next.migrateLegacyFields(calendar: defaultCalendar(timeZone: TimeZone(identifier: state.periods.first?.timeZoneIdentifier ?? "") ?? .current))
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

    func upsertFocusPlanningConfiguration(
        _ draft: FocusPlanningConfiguration,
        at date: Date = .now
    ) {
        guard !blocksWrites else { return }
        var next = draft
        if let current = state.focusPlanningConfiguration {
            next.editCount = current.editCount + 1
        } else {
            next.editCount = max(next.editCount, 0) + 1
        }
        next.editTieBreaker = UUID()
        next.editedAt = date
        state.focusPlanningConfiguration = next
        markDirty(
            .focusPlanningConfiguration,
            key: FocusPlanningConfiguration.logicalKey,
            editCount: next.editCount,
            tie: next.editTieBreaker
        )
        persist()
    }

    func upsertSyncedPreferences(_ draft: SyncedPreferences, at date: Date = .now) {
        guard !blocksWrites, draft.isValid else { return }
        var next = draft
        next.editCount = (state.syncedPreferences?.editCount ?? max(next.editCount, 0)) + 1
        next.editTieBreaker = UUID()
        next.editedAt = date
        state.syncedPreferences = next
        markDirty(
            .syncedPreferences,
            key: SyncedPreferences.logicalKey,
            editCount: next.editCount,
            tie: next.editTieBreaker
        )
        persist()
    }

    @discardableResult
    func replaceSyncState(_ sync: SyncLocalState) -> Bool {
        guard !blocksWrites else { return false }
        var next = state
        next.sync = sync
        do {
            try writeArchive(next)
            state = next
            revision &+= 1
            persistenceError = nil
            return true
        } catch {
            persistenceError = .writeFailed
            return false
        }
    }

    func applyIncomingValue(_ value: RecordIncomingValue) {
        guard !blocksWrites else { return }
        RecordJSON.applyIncoming(value, to: &state)
        if let stamp = incomingStamp(value),
           let bumped = bumpEntityStamp(in: &state, type: stamp.type, key: stamp.key) {
            markDirty(stamp.type, key: stamp.key, editCount: bumped.0, tie: bumped.1)
        }
        persist()
    }

    @discardableResult
    func restoreConflict(_ copy: SyncConflictCopy) -> Bool {
        guard !blocksWrites else { return false }
        let calendar = RecordsSyncPayload.fileCalendar(for: state)
        guard let incoming = RecordsSyncPayload.incoming(
            from: copy.effectiveAlternatePayload,
            type: copy.entityType,
            calendar: calendar
        ) else { return false }

        var candidate = state
        RecordJSON.applyIncoming(incoming, to: &candidate)
        let conflictMaximum = [copy.localPayload, copy.incomingPayload, copy.payload]
            .compactMap { $0 }
            .compactMap { RecordsSyncPayload.editStamp(from: $0, type: copy.entityType, calendar: calendar)?.0 }
            .max() ?? 0
        if let bumped = bumpEntityStamp(
            in: &candidate,
            type: copy.entityType,
            key: copy.logicalKey,
            atLeastEditCount: conflictMaximum + 1
        ) {
            RecordsSyncOutbox.markDirty(
                &candidate.sync,
                type: copy.entityType,
                key: copy.logicalKey,
                editCount: bumped.0,
                editTieBreaker: bumped.1
            )
        }
        candidate.sync.conflicts.removeAll { $0.id == copy.id }
        do {
            try writeArchive(candidate)
            state = candidate
            revision &+= 1
            persistenceError = nil
            onExternalStateApplied?()
            onDirty?()
            return true
        } catch {
            persistenceError = .writeFailed
            return false
        }
    }

    func consumeConflict(_ copy: SyncConflictCopy) {
        var candidate = state
        candidate.sync.conflicts.removeAll { $0.id == copy.id }
        do {
            try writeArchive(candidate)
            state = candidate
            revision &+= 1
            persistenceError = nil
        } catch {
            persistenceError = .writeFailed
        }
    }

    /// A user's explicit “keep the version I am seeing” choice is a new edit,
    /// not housekeeping. Re-stamping it above both candidates prevents the
    /// rejected version from winning again on the next CloudKit fetch.
    @discardableResult
    func keepCurrentConflict(_ copy: SyncConflictCopy) -> Bool {
        guard !blocksWrites else { return false }
        let calendar = RecordsSyncPayload.fileCalendar(for: state)
        var candidate = state
        let conflictMaximum = [copy.localPayload, copy.incomingPayload, copy.payload]
            .compactMap { $0 }
            .compactMap { RecordsSyncPayload.editStamp(from: $0, type: copy.entityType, calendar: calendar)?.0 }
            .max() ?? 0
        guard let bumped = bumpEntityStamp(
            in: &candidate,
            type: copy.entityType,
            key: copy.logicalKey,
            atLeastEditCount: conflictMaximum + 1
        ) else { return false }
        RecordsSyncOutbox.markDirty(
            &candidate.sync,
            type: copy.entityType,
            key: copy.logicalKey,
            editCount: bumped.0,
            editTieBreaker: bumped.1
        )
        candidate.sync.conflicts.removeAll { $0.id == copy.id }
        do {
            try writeArchive(candidate)
            state = candidate
            revision &+= 1
            persistenceError = nil
            onExternalStateApplied?()
            onDirty?()
            return true
        } catch {
            persistenceError = .writeFailed
            return false
        }
    }

    /// Resolves an editable conflict from the currently applied version plus
    /// explicitly selected fields from the other version. JSON arrays and
    /// objects are copied as one value, so paired schedule segments and other
    /// composite fields cannot be split into an invalid half-state.
    @discardableResult
    func resolveConflict(_ copy: SyncConflictCopy, fieldsFromAlternate: Set<String>) -> Bool {
        guard !blocksWrites, copy.supportsFieldMerge else { return false }
        guard var current = try? JSONSerialization.jsonObject(with: copy.effectiveCurrentPayload) as? [String: Any],
              let alternate = try? JSONSerialization.jsonObject(with: copy.effectiveAlternatePayload) as? [String: Any]
        else { return false }
        let expandedFields = RecordsConflictFieldSelection.expanded(
            fieldsFromAlternate,
            for: copy.entityType
        )
        for field in expandedFields {
            if let value = alternate[field] {
                current[field] = value
            } else {
                current.removeValue(forKey: field)
            }
        }
        guard let mergedPayload = try? JSONSerialization.data(withJSONObject: current),
              let incoming = RecordsSyncPayload.incoming(
                from: mergedPayload,
                type: copy.entityType,
                calendar: RecordsSyncPayload.fileCalendar(for: state)
              )
        else { return false }

        let calendar = RecordsSyncPayload.fileCalendar(for: state)
        var candidate = state
        RecordJSON.applyIncoming(incoming, to: &candidate)
        let conflictMaximum = [copy.localPayload, copy.incomingPayload, copy.payload]
            .compactMap { $0 }
            .compactMap { RecordsSyncPayload.editStamp(from: $0, type: copy.entityType, calendar: calendar)?.0 }
            .max() ?? 0
        guard let bumped = bumpEntityStamp(
            in: &candidate,
            type: copy.entityType,
            key: copy.logicalKey,
            atLeastEditCount: conflictMaximum + 1
        ) else { return false }
        RecordsSyncOutbox.markDirty(
            &candidate.sync,
            type: copy.entityType,
            key: copy.logicalKey,
            editCount: bumped.0,
            editTieBreaker: bumped.1
        )
        candidate.sync.conflicts.removeAll { $0.id == copy.id }
        do {
            try writeArchive(candidate)
            state = candidate
            revision &+= 1
            persistenceError = nil
            onExternalStateApplied?()
            onDirty?()
            return true
        } catch {
            persistenceError = .writeFailed
            return false
        }
    }

    /// Same-id import rows keep the local winner. The incoming payload is
    /// parked so Settings → Conflicts can still choose it.
    private func parkUnresolvedImportConflicts(
        into state: inout RecordState,
        _ conflicts: [RecordImportConflict],
        at date: Date = .now
    ) {
        let calendar = RecordsSyncPayload.fileCalendar(for: state)
        for conflict in conflicts where !conflict.appliedIncoming {
            guard let payload = RecordsSyncPayload.encode(conflict.incoming, calendar: calendar) else { continue }
            if state.sync.conflicts.contains(where: {
                $0.entityType == conflict.entityType && $0.logicalKey == conflict.logicalKey
            }) {
                continue
            }
            let local = RecordsSyncPayload.encode(
                type: conflict.entityType,
                key: conflict.logicalKey,
                from: state
            )
            state.sync.conflicts.append(
                SyncConflictCopy(
                    entityType: conflict.entityType,
                    logicalKey: conflict.logicalKey,
                    payload: payload,
                    lostAtMs: date.timeIntervalSince1970 * 1_000,
                    source: "import",
                    localPayload: local,
                    incomingPayload: payload,
                    baselinePayload: nil,
                    localEditedAtMs: local.flatMap { RecordsSyncPayload.editedAtMs(from: $0, type: conflict.entityType, calendar: calendar) },
                    incomingEditedAtMs: RecordsSyncPayload.editedAtMs(from: payload, type: conflict.entityType, calendar: calendar),
                    currentWinner: .local
                )
            )
        }
    }

    private func bumpEntityStamp(
        in target: inout RecordState,
        type: RecordEntityType,
        key: String,
        atLeastEditCount: Int = 0,
        at date: Date = .now
    ) -> (Int, UUID)? {
        switch type {
        case .careerPeriod:
            guard let index = target.periods.firstIndex(where: {
                $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }) else { return nil }
            target.periods[index].editCount = max(target.periods[index].editCount + 1, atLeastEditCount)
            target.periods[index].editTieBreaker = UUID()
            target.periods[index].editedAt = date
            return (target.periods[index].editCount, target.periods[index].editTieBreaker)
        case .scheduleSnapshot:
            guard let index = target.snapshots.firstIndex(where: {
                $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }) else { return nil }
            target.snapshots[index].editCount = max(target.snapshots[index].editCount + 1, atLeastEditCount)
            target.snapshots[index].editTieBreaker = UUID()
            target.snapshots[index].editedAt = date
            return (target.snapshots[index].editCount, target.snapshots[index].editTieBreaker)
        case .calendarException:
            guard let index = target.exceptions.firstIndex(where: { $0.dayKey == key }) else { return nil }
            target.exceptions[index].editCount = max(target.exceptions[index].editCount + 1, atLeastEditCount)
            target.exceptions[index].editTieBreaker = UUID()
            target.exceptions[index].editedAt = date
            return (target.exceptions[index].editCount, target.exceptions[index].editTieBreaker)
        case .dayOverride:
            guard let index = target.overrides.firstIndex(where: { $0.dayKey == key }) else { return nil }
            target.overrides[index].editCount = max(target.overrides[index].editCount + 1, atLeastEditCount)
            target.overrides[index].editTieBreaker = UUID()
            target.overrides[index].editedAt = date
            return (target.overrides[index].editCount, target.overrides[index].editTieBreaker)
        case .workObservation:
            guard let index = target.observations.firstIndex(where: {
                $0.eventID.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }) else { return nil }
            target.observations[index].editCount = max(target.observations[index].editCount + 1, atLeastEditCount)
            target.observations[index].editTieBreaker = UUID()
            target.observations[index].editedAt = date
            return (target.observations[index].editCount, target.observations[index].editTieBreaker)
        case .lifeProfile:
            guard var profile = target.lifeProfile else { return nil }
            profile.editCount = max(profile.editCount + 1, atLeastEditCount)
            profile.editTieBreaker = UUID()
            profile.editedAt = date
            target.lifeProfile = profile
            return (profile.editCount, profile.editTieBreaker)
        case .focusTask:
            guard let index = target.focusTasks.firstIndex(where: {
                $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }) else { return nil }
            target.focusTasks[index].editCount = max(target.focusTasks[index].editCount + 1, atLeastEditCount)
            target.focusTasks[index].editTieBreaker = UUID()
            target.focusTasks[index].editedAt = date
            return (target.focusTasks[index].editCount, target.focusTasks[index].editTieBreaker)
        case .focusSession:
            guard let index = target.focusSessions.firstIndex(where: {
                $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }) else { return nil }
            target.focusSessions[index].editCount = max(target.focusSessions[index].editCount + 1, atLeastEditCount)
            target.focusSessions[index].editTieBreaker = UUID()
            target.focusSessions[index].editedAt = date
            return (target.focusSessions[index].editCount, target.focusSessions[index].editTieBreaker)
        case .focusPlanningConfiguration:
            guard var configuration = target.focusPlanningConfiguration else { return nil }
            configuration.editCount = max(configuration.editCount + 1, atLeastEditCount)
            configuration.editTieBreaker = UUID()
            configuration.editedAt = date
            target.focusPlanningConfiguration = configuration
            return (configuration.editCount, configuration.editTieBreaker)
        case .syncedPreferences:
            guard var preferences = target.syncedPreferences else { return nil }
            preferences.editCount = max(preferences.editCount + 1, atLeastEditCount)
            preferences.editTieBreaker = UUID()
            preferences.editedAt = date
            target.syncedPreferences = preferences
            return (preferences.editCount, preferences.editTieBreaker)
        }
    }

    private func incomingStamp(_ value: RecordIncomingValue) -> (type: RecordEntityType, key: String, editCount: Int)? {
        switch value {
        case .period(let period): return (.careerPeriod, period.id.uuidString, period.editCount)
        case .snapshot(let snapshot): return (.scheduleSnapshot, snapshot.id.uuidString, snapshot.editCount)
        case .exception(let exception): return (.calendarException, exception.dayKey, exception.editCount)
        case .override(let override): return (.dayOverride, override.dayKey, override.editCount)
        case .observation(let observation):
            return (.workObservation, observation.eventID.uuidString, max(1, observation.editCount))
        case .lifeProfile(let profile): return (.lifeProfile, LifeProfile.profileID.uuidString, profile.editCount)
        case .focusTask(let task): return (.focusTask, task.id.uuidString, task.editCount)
        case .focusSession(let session): return (.focusSession, session.id.uuidString, session.editCount)
        case .focusPlanningConfiguration(let configuration):
            return (.focusPlanningConfiguration, FocusPlanningConfiguration.logicalKey, configuration.editCount)
        case .syncedPreferences(let preferences):
            return (.syncedPreferences, SyncedPreferences.logicalKey, preferences.editCount)
        }
    }

    /// A tombstone was deleted in iCloud because the identity was recorded
    /// again. Forget it locally without marking the row dirty — the revival
    /// itself arrives as an ordinary record in the same atomic batch.
    func applyRemoteEraseRevocation(type: RecordEntityType, key: String) {
        guard !blocksWrites else { return }
        guard state.clearErased(type, key: key) != nil else { return }
        persist()
    }

    /// `erasedEditCount` is the version the sender buried. Nil means the
    /// tombstone carries no version — a record written before revocation
    /// existed — and is trusted unconditionally, as it always was.
    func applyRemoteErase(
        type: RecordEntityType,
        key: String,
        erasedEditCount: Int? = nil,
        systemFields: Data? = nil,
        generation: Int? = nil,
        at date: Date = .now
    ) {
        guard !blocksWrites else { return }
        // A live row that already out-ranks this tombstone is a revival we
        // have and the sender had not seen. Keep it; our own revocation push
        // removes the tombstone from iCloud.
        if let erasedEditCount,
           let local = RecordsSyncPayload.editStamp(type: type, key: key, in: state),
           local.0 > erasedEditCount {
            return
        }
        state.erase(type, key: key, at: date, atLeastEditCount: erasedEditCount ?? 0)
        RecordsSyncOutbox.markDirty(
            &state.sync,
            type: type,
            key: key,
            editCount: 0,
            editTieBreaker: UUID(),
            erase: true
        )
        let name = RecordsSyncIdentity.recordName(type: type, key: key)
        if var row = state.sync.rows[name] {
            row.lastKnownErasedRecord = systemFields ?? row.lastKnownErasedRecord
            if let generation { row.generation = generation }
            state.sync.rows[name] = row
        }
        persist()
        if persistenceError == nil { onDirty?() }
    }

    /// Applies a CloudKit row without treating it as a local edit.
    func applyRemotePayload(
        type: RecordEntityType,
        key: String,
        payload: Data,
        editCount: Int,
        editTieBreaker: String,
        systemFields: Data?,
        generation: Int,
        persistImmediately: Bool = true
    ) {
        guard !blocksWrites else { return }
        let local = RecordsSyncPayload.editStamp(type: type, key: key, in: state)
        var action = RecordsSyncApply.action(
            type: type,
            locallyErased: state.isErased(type, key: key),
            localCount: local?.0,
            localTie: local?.1,
            serverCount: editCount,
            serverTie: editTieBreaker
        )
        let name = RecordsSyncIdentity.recordName(type: type, key: key)
        if action == .reassertErase {
            RecordsSyncOutbox.markDirty(
                &state.sync,
                type: type,
                key: key,
                editCount: 0,
                editTieBreaker: UUID(),
                erase: true
            )
            if persistImmediately { persist() }
            return
        }
        let calendar = RecordsSyncPayload.fileCalendar(for: state)
        guard let incoming = RecordsSyncPayload.incoming(from: payload, type: type, calendar: calendar) else {
            return
        }
        let localPayload = RecordsSyncPayload.encode(type: type, key: key, from: state)
        let baselinePayload = state.sync.rows[name]?.lastKnownPayload
        let localEditedAtMs = localPayload.flatMap {
            RecordsSyncPayload.editedAtMs(from: $0, type: type, calendar: calendar)
        }
        let incomingEditedAtMs = RecordsSyncPayload.editedAtMs(
            from: payload,
            type: type,
            calendar: calendar
        )
        let hasSameBusinessContent = localPayload.map {
            RecordsSyncConflict.payloadsHaveSameBusinessContent($0, payload)
        } ?? false
        let automaticallyMergedPayload = localPayload.flatMap {
            RecordsSyncConflict.automaticallyMergedPayload(
                local: $0,
                server: payload,
                baseline: baselinePayload,
                type: type
            )
        }
        var requiresManualReview = false
        if action == .keepLocalAndCopyServer || action == .takeServerAndCopyLocal,
           let localCount = local?.0 {
            switch RecordsSyncConflict.automaticallyPreferredWinner(
                localCount: localCount,
                localEditedAtMs: localEditedAtMs,
                incomingCount: editCount,
                incomingEditedAtMs: incomingEditedAtMs
            ) {
            case .local:
                action = .keepLocalAndCopyServer
            case .incoming:
                action = .takeServerAndCopyLocal
            case .unknown:
                assertionFailure("Automatic conflict resolution never returns an unknown winner")
                requiresManualReview = true
            case nil:
                requiresManualReview = true
            }
        }
        // The server row out-ranked the tombstone, so this identity is alive
        // again. Drop the local tombstone or `.skipErased` imports would keep
        // skipping the day and the next fetch would erase it a second time.
        state.clearErased(type, key: key)
        switch action {
        case .ignore:
            break
        case .insert, .takeServer:
            RecordJSON.applyIncoming(incoming, to: &state)
            RecordsSyncOutbox.clearDirty(&state.sync, recordName: name)
        case .keepLocalAndCopyServer:
            guard !hasSameBusinessContent else {
                removeCloudConflict(type: type, key: key)
                break
            }
            if let automaticallyMergedPayload,
               applyAutomaticallyMergedPayload(
                   automaticallyMergedPayload,
                   type: type,
                   key: key,
                   localPayload: localPayload,
                   incomingPayload: payload,
                   calendar: calendar
               ) {
                break
            }
            if requiresManualReview {
                parkCloudConflict(
                    SyncConflictCopy(
                        entityType: type,
                        logicalKey: key,
                        payload: payload,
                        lostAtMs: Date.now.timeIntervalSince1970 * 1_000,
                        localPayload: localPayload,
                        incomingPayload: payload,
                        baselinePayload: baselinePayload,
                        localEditedAtMs: localEditedAtMs,
                        incomingEditedAtMs: incomingEditedAtMs,
                        currentWinner: .local
                    )
                )
            } else {
                removeCloudConflict(type: type, key: key)
            }
        case .takeServerAndCopyLocal:
            if !hasSameBusinessContent,
               let automaticallyMergedPayload,
               applyAutomaticallyMergedPayload(
                   automaticallyMergedPayload,
                   type: type,
                   key: key,
                   localPayload: localPayload,
                   incomingPayload: payload,
                   calendar: calendar
               ) {
                break
            }
            if requiresManualReview, let localPayload, !hasSameBusinessContent {
                parkCloudConflict(
                    SyncConflictCopy(
                        entityType: type,
                        logicalKey: key,
                        payload: localPayload,
                        lostAtMs: Date.now.timeIntervalSince1970 * 1_000,
                        localPayload: localPayload,
                        incomingPayload: payload,
                        baselinePayload: baselinePayload,
                        localEditedAtMs: localEditedAtMs,
                        incomingEditedAtMs: incomingEditedAtMs,
                        currentWinner: .incoming
                    )
                )
            }
            if hasSameBusinessContent || !requiresManualReview {
                removeCloudConflict(type: type, key: key)
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
        case .mergeFocusPlanning:
            if case .focusPlanningConfiguration(let server) = incoming,
               let localConfiguration = state.focusPlanningConfiguration {
                if RecordsSyncConflict.focusPlanningContentIsEqual(localConfiguration, server) {
                    removeCloudConflict(type: type, key: key)
                    if RecordsSyncConflict.localWins(
                        localCount: localConfiguration.editCount,
                        localTie: localConfiguration.editTieBreaker.uuidString,
                        serverCount: server.editCount,
                        serverTie: server.editTieBreaker.uuidString
                    ) {
                        // The local stamp is already dirty or will be found by
                        // the pending scan. No user-visible conflict exists.
                    } else {
                        state.focusPlanningConfiguration = server
                        RecordsSyncOutbox.clearDirty(&state.sync, recordName: name)
                    }
                } else {
                    let baseline = lastKnownFocusPlanningConfiguration()
                    let merged = RecordsSyncConflict.mergeFocusPlanningConfiguration(
                        local: localConfiguration,
                        server: server,
                        baseline: baseline
                    )
                    state.focusPlanningConfiguration = merged
                    RecordsSyncOutbox.markDirty(
                        &state.sync,
                        type: .focusPlanningConfiguration,
                        key: FocusPlanningConfiguration.logicalKey,
                        editCount: merged.editCount,
                        editTieBreaker: merged.editTieBreaker
                    )
                }
            } else {
                RecordJSON.applyIncoming(incoming, to: &state)
                RecordsSyncOutbox.clearDirty(&state.sync, recordName: name)
            }
        case .mergeSyncedPreferences:
            if case .syncedPreferences(let server) = incoming,
               let localPreferences = state.syncedPreferences {
                if hasSameBusinessContent {
                    removeCloudConflict(type: type, key: key)
                    if !RecordsSyncConflict.localWins(
                        localCount: localPreferences.editCount,
                        localTie: localPreferences.editTieBreaker.uuidString,
                        serverCount: server.editCount,
                        serverTie: server.editTieBreaker.uuidString
                    ) {
                        state.syncedPreferences = server
                        RecordsSyncOutbox.clearDirty(&state.sync, recordName: name)
                    }
                } else {
                    let merged = RecordsSyncConflict.mergeSyncedPreferences(
                        local: localPreferences,
                        server: server,
                        baseline: lastKnownSyncedPreferences()
                    )
                    state.syncedPreferences = merged
                    RecordsSyncOutbox.markDirty(
                        &state.sync,
                        type: .syncedPreferences,
                        key: SyncedPreferences.logicalKey,
                        editCount: merged.editCount,
                        editTieBreaker: merged.editTieBreaker
                    )
                }
            } else {
                RecordJSON.applyIncoming(incoming, to: &state)
                RecordsSyncOutbox.clearDirty(&state.sync, recordName: name)
            }
        case .reassertErase:
            assertionFailure("Reasserted erasures return before payload application")
        }
        var row = state.sync.rows[name] ?? SyncAdapterRow(
            entityType: type,
            logicalKey: key,
            recordName: name,
            dirty: action == .keepLocalAndCopyServer
                || action == .mergeLife
                || action == .mergeFocusPlanning
                || action == .mergeSyncedPreferences,
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
        if persistImmediately { persist() }
    }

    func persistRemoteBatch() {
        persist()
        guard persistenceError == nil else { return }
        onRemoteBatchApplied?()
        onExternalStateApplied?()
        if !RecordsSyncOutbox.pending(state.sync).isEmpty {
            onDirty?()
        }
    }

    func applyDayLayers(override: DayOverride?, exception: CalendarException?, at date: Date = .now) {
        guard !blocksWrites else { return }
        if let override {
            upsertOverride(override, at: date, persist: false)
        }
        if let exception {
            upsertException(exception, at: date, persist: false)
        }
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

    private func lastKnownFocusPlanningConfiguration() -> FocusPlanningConfiguration? {
        let name = RecordsSyncIdentity.recordName(
            type: .focusPlanningConfiguration,
            key: FocusPlanningConfiguration.logicalKey
        )
        guard let data = state.sync.rows[name]?.lastKnownPayload,
              case .focusPlanningConfiguration(let configuration) = RecordsSyncPayload.incoming(
                  from: data,
                  type: .focusPlanningConfiguration,
                  calendar: RecordsSyncPayload.fileCalendar(for: state)
              )
        else { return nil }
        return configuration
    }

    private func lastKnownSyncedPreferences() -> SyncedPreferences? {
        let name = RecordsSyncIdentity.recordName(
            type: .syncedPreferences,
            key: SyncedPreferences.logicalKey
        )
        guard let data = state.sync.rows[name]?.lastKnownPayload,
              case .syncedPreferences(let preferences) = RecordsSyncPayload.incoming(
                  from: data,
                  type: .syncedPreferences,
                  calendar: RecordsSyncPayload.fileCalendar(for: state)
              )
        else { return nil }
        return preferences
    }

    /// One logical identity has at most one pending review. Repeated engine
    /// delivery updates the candidates instead of multiplying cards with
    /// random conflict IDs.
    private func parkCloudConflict(_ copy: SyncConflictCopy) {
        removeCloudConflict(type: copy.entityType, key: copy.logicalKey)
        state.sync.conflicts.append(copy)
    }

    private func removeCloudConflict(type: RecordEntityType, key: String) {
        state.sync.conflicts.removeAll {
            $0.entityType == type && $0.logicalKey == key
        }
    }

    private func applyAutomaticallyMergedPayload(
        _ payload: Data,
        type: RecordEntityType,
        key: String,
        localPayload: Data?,
        incomingPayload: Data,
        calendar: Calendar
    ) -> Bool {
        guard let incoming = RecordsSyncPayload.incoming(from: payload, type: type, calendar: calendar) else {
            return false
        }
        RecordJSON.applyIncoming(incoming, to: &state)
        let conflictMaximum = [localPayload, incomingPayload]
            .compactMap { $0 }
            .compactMap { RecordsSyncPayload.editStamp(from: $0, type: type, calendar: calendar)?.0 }
            .max() ?? 0
        guard let bumped = bumpEntityStamp(
            in: &state,
            type: type,
            key: key,
            atLeastEditCount: conflictMaximum + 1
        ) else { return false }
        RecordsSyncOutbox.markDirty(
            &state.sync,
            type: type,
            key: key,
            editCount: bumped.0,
            editTieBreaker: bumped.1
        )
        removeCloudConflict(type: type, key: key)
        return true
    }

    func currentSnapshotID(on day: Date) -> UUID? {
        guard let period = DayRecordResolver.period(on: day, from: state.periods) else { return nil }
        return DayRecordResolver.snapshot(on: day, in: period, from: state.snapshots)?.id
    }

    func migrateCalendarTimeZone(to identifier: String, at date: Date = .now) {
        guard !blocksWrites else { return }
        guard let targetTimeZone = TimeZone(identifier: identifier) else { return }
        let oldPeriods = Dictionary(uniqueKeysWithValues: state.periods.map { ($0.id, $0) })
        let oldSnapshotEditCounts = Dictionary(uniqueKeysWithValues: state.snapshots.map { ($0.id, $0.editCount) })
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
        let originalObservations = state.observations
        state.observations.removeAll(keepingCapacity: true)
        for original in originalObservations {
            guard original.timeZoneIdentifier != identifier else {
                state.observations.append(original)
                continue
            }
            let oldCalendar = calendar(timeZoneIdentifier: original.timeZoneIdentifier)
            var targetCalendar = Calendar(identifier: .gregorian)
            targetCalendar.timeZone = targetTimeZone
            var migrated = original
            migrated.eventID = migratedObservationID(from: original.eventID, to: identifier)
            migrated.shiftAnchorDate = preserveCivilDate(
                original.shiftAnchorDate,
                from: oldCalendar,
                in: targetCalendar
            )
            migrated.timeZoneIdentifier = identifier
            migrated.editedAt = date
            migrated.editCount = 1
            migrated.editTieBreaker = migrated.eventID
            state.erase(.workObservation, key: original.eventID.uuidString, at: date)
            markDirty(
                .workObservation,
                key: original.eventID.uuidString,
                editCount: 0,
                tie: original.eventID,
                erase: true
            )
            state.observations.append(migrated)
            markDirty(.workObservation, key: migrated.eventID.uuidString, editCount: 1, tie: migrated.eventID)
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
            profile.editedAt = date
            profile.editCount += 1
            profile.editTieBreaker = UUID()
            state.lifeProfile = profile
        }
        for index in state.snapshots.indices {
            guard let oldPeriod = oldPeriods[state.snapshots[index].periodID] else { continue }
            let oldCalendar = oldPeriod.civilCalendar()
            var targetCalendar = Calendar(identifier: oldPeriod.calendarIdentifier == "iso8601" ? .iso8601 : .gregorian)
            targetCalendar.timeZone = targetTimeZone
            if var hours = try? JSONDecoder().decode(
                ScheduleHoursConfiguration.self,
                from: state.snapshots[index].configurationData
            ) {
                hours.schedule = migrateScheduleAnchors(
                    hours.schedule,
                    from: oldCalendar,
                    to: targetCalendar
                )
                if let encoded = try? ScheduleHoursCodec.encode(hours) {
                    state.snapshots[index].configurationData = encoded.data
                    state.snapshots[index].fingerprint = encoded.fingerprint
                }
            }
            if state.snapshots[index].editCount == oldSnapshotEditCounts[state.snapshots[index].id] {
                state.snapshots[index].editedAt = date
                state.snapshots[index].editCount += 1
                state.snapshots[index].editTieBreaker = UUID()
            }
        }
        for period in state.periods {
            markDirty(.careerPeriod, key: period.id.uuidString, editCount: period.editCount, tie: period.editTieBreaker)
        }
        for snapshot in state.snapshots {
            markDirty(.scheduleSnapshot, key: snapshot.id.uuidString, editCount: snapshot.editCount, tie: snapshot.editTieBreaker)
        }
        for override in state.overrides {
            markDirty(.dayOverride, key: override.dayKey, editCount: override.editCount, tie: override.editTieBreaker)
        }
        for exception in state.exceptions {
            markDirty(.calendarException, key: exception.dayKey, editCount: exception.editCount, tie: exception.editTieBreaker)
        }
        if let profile = state.lifeProfile {
            markDirty(.lifeProfile, key: LifeProfile.profileID.uuidString, editCount: profile.editCount, tie: profile.editTieBreaker)
        }
        persist()
    }

    private func migrateScheduleAnchors(
        _ schedule: NativeWorkSchedule,
        from source: Calendar,
        to target: Calendar
    ) -> NativeWorkSchedule {
        func civilMs(_ ms: Double?) -> Double? {
            guard let ms else { return nil }
            let date = Date(timeIntervalSince1970: ms / 1_000)
            return preserveCivilDate(date, from: source, in: target).timeIntervalSince1970 * 1_000
        }
        return NativeWorkSchedule(
            mode: schedule.mode,
            referenceWeekStartMs: civilMs(schedule.referenceWeekStartMs),
            referenceWeekType: schedule.referenceWeekType,
            singleWeekendWorkday: schedule.singleWeekendWorkday,
            rotationAnchorMs: civilMs(schedule.rotationAnchorMs),
            rotationWorkDays: schedule.rotationWorkDays,
            rotationRestDays: schedule.rotationRestDays
        )
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

    /// Two devices explicitly migrating the same immutable observation to the
    /// same zone must create the same replacement identity, not duplicates.
    private func migratedObservationID(from eventID: UUID, to timeZoneIdentifier: String) -> UUID {
        let input = "owc.observation.time-zone-migration.v1|\(eventID.uuidString.lowercased())|\(timeZoneIdentifier)"
        var bytes = Array(SHA256.hash(data: Data(input.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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
                timeZoneIdentifier: timeZoneIdentifier,
                editedAt: occurredAt,
                editCount: 1,
                editTieBreaker: eventID
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

    /// A schedule has day-level effective dates. Saving it twice for the same
    /// day must therefore edit the winning logical row, not append two
    /// editCount-1 rows and let a random UUID decide which one Records sees.
    private func upsertSnapshot(
        data: Data,
        fingerprint: String,
        periodID: UUID,
        effectiveFrom: Date,
        at date: Date
    ) {
        let candidateIndices = state.snapshots.indices.filter {
            state.snapshots[$0].periodID == periodID
                && state.snapshots[$0].effectiveFrom == effectiveFrom
        }
        let winningIndex = candidateIndices.max { lhsIndex, rhsIndex in
            let lhs = state.snapshots[lhsIndex]
            let rhs = state.snapshots[rhsIndex]
            if lhs.editCount != rhs.editCount { return lhs.editCount < rhs.editCount }
            if lhs.editTieBreaker != rhs.editTieBreaker {
                return lhs.editTieBreaker.uuidString < rhs.editTieBreaker.uuidString
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard let winningIndex else {
            let snapshot = ScheduleSnapshot(
                id: UUID(),
                periodID: periodID,
                effectiveFrom: effectiveFrom,
                configurationData: data,
                fingerprint: fingerprint,
                editedAt: date,
                editCount: 1,
                editTieBreaker: UUID()
            )
            state.snapshots.append(snapshot)
            markDirty(
                .scheduleSnapshot,
                key: snapshot.id.uuidString,
                editCount: snapshot.editCount,
                tie: snapshot.editTieBreaker
            )
            return
        }

        let nextEditCount = (candidateIndices.map { state.snapshots[$0].editCount }.max() ?? 0) + 1
        state.snapshots[winningIndex].configurationData = data
        state.snapshots[winningIndex].fingerprint = fingerprint
        state.snapshots[winningIndex].editedAt = date
        state.snapshots[winningIndex].editCount = nextEditCount
        state.snapshots[winningIndex].editTieBreaker = UUID()
        let snapshot = state.snapshots[winningIndex]
        markDirty(
            .scheduleSnapshot,
            key: snapshot.id.uuidString,
            editCount: snapshot.editCount,
            tie: snapshot.editTieBreaker
        )
    }

    private func migrateLegacyAutomaticPeriod(in archive: inout RecordState, at date: Date) {
        guard archive.periods.count == 1, archive.periods[0].label == nil else { return }
        let calendar = archive.periods[0].civilCalendar()
        guard RecordJSON.dayKey(archive.periods[0].startsOn, calendar: calendar) == "2000-01-01" else {
            return
        }
        let candidates = archive.observations.map(\.shiftAnchorDate)
            + archive.overrides.map(\.shiftAnchorDate)
            + archive.exceptions.map(\.date)
            + [date]
        guard let earliest = candidates.min() else { return }
        archive.periods[0].startsOn = calendar.startOfDay(for: earliest)
        archive.recordsStartedOn = archive.recordsStartedOn ?? archive.periods[0].startsOn
    }

    /// A revived natural key has to out-rank the tombstone it replaces, so a
    /// device that has not fetched the revocation yet still keeps the new row.
    private func reviveAboveTombstone(_ editCount: inout Int, over erasedEditCount: Int?) {
        guard let erasedEditCount, editCount <= erasedEditCount else { return }
        editCount = erasedEditCount + 1
    }

    private func markDirty(
        _ type: RecordEntityType,
        key: String,
        editCount: Int,
        tie: UUID,
        erase: Bool = false,
        revokeErase: Bool = false
    ) {
        RecordsSyncOutbox.markDirty(
            &state.sync,
            type: type,
            key: key,
            editCount: editCount,
            editTieBreaker: tie,
            erase: erase,
            revokeErase: revokeErase
        )
        onDirty?()
    }

    private func load() {
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        LaunchTrace.interval("recordsSeed") { loadArchive(from: fileURL) }
    }

    private func loadArchive(from fileURL: URL) {
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
                    erasedAt: Date(timeIntervalSince1970: $0.erasedAtMs / 1_000),
                    editCount: $0.editCount ?? 0
                )
            }
            archive.sync = file.sync ?? .empty
            migrateLegacyAutomaticPeriod(in: &archive, at: .now)
            if var profile = archive.lifeProfile {
                profile.migrateLegacyFields(calendar: RecordsSyncPayload.fileCalendar(for: archive))
                archive.lifeProfile = profile
            }
            let normalizedConflicts = normalizeStoredConflicts(in: &archive)
            state = archive
            revision &+= 1
            if normalizedConflicts { try writeArchive(archive) }
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            persistenceError = .unreadableArchive
        } catch {
            persistenceError = .invalidArchive
        }
    }

    private func persist() {
        revision &+= 1
        do {
            try writeArchive(state)
            persistenceError = nil
        } catch {
            persistenceError = .writeFailed
        }
    }

    /// Archives written by earlier builds may contain metadata-only copies,
    /// an already-selected newer CloudKit revision, or repeated deliveries for
    /// the same logical identity. None represents a decision a person can make,
    /// so remove them during archive migration before the badge is rendered.
    @discardableResult
    private func normalizeStoredConflicts(in archive: inout RecordState) -> Bool {
        let original = archive.sync.conflicts
        var latestByIdentity: [String: SyncConflictCopy] = [:]
        let calendar = RecordsSyncPayload.fileCalendar(for: archive)
        for conflict in original {
            if let local = conflict.localPayload,
               let incoming = conflict.incomingPayload,
               RecordsSyncConflict.payloadsHaveSameBusinessContent(local, incoming) {
                continue
            }
            if conflict.source != "import",
               let local = conflict.localPayload,
               let incoming = conflict.incomingPayload,
               let localStamp = RecordsSyncPayload.editStamp(
                   from: local,
                   type: conflict.entityType,
                   calendar: calendar
               ),
               let incomingStamp = RecordsSyncPayload.editStamp(
                   from: incoming,
                   type: conflict.entityType,
                   calendar: calendar
               ),
               let preferred = RecordsSyncConflict.automaticallyPreferredWinner(
                   localCount: localStamp.0,
                   localEditedAtMs: conflict.localEditedAtMs ?? RecordsSyncPayload.editedAtMs(
                       from: local,
                       type: conflict.entityType,
                       calendar: calendar
                   ),
                   incomingCount: incomingStamp.0,
                   incomingEditedAtMs: conflict.incomingEditedAtMs ?? RecordsSyncPayload.editedAtMs(
                       from: incoming,
                       type: conflict.entityType,
                       calendar: calendar
                   )
               ),
               preferred == conflict.currentWinner {
                continue
            }
            let identity = "\(conflict.entityType.rawValue).\(conflict.logicalKey)"
            if let previous = latestByIdentity[identity], previous.lostAtMs > conflict.lostAtMs {
                continue
            }
            latestByIdentity[identity] = conflict
        }
        archive.sync.conflicts = latestByIdentity.values.sorted {
            if $0.lostAtMs != $1.lostAtMs { return $0.lostAtMs < $1.lostAtMs }
            return $0.id.uuidString < $1.id.uuidString
        }
        return archive.sync.conflicts != original
    }

    private func writeArchive(_ archive: RecordState) throws {
        guard let fileURL else { return }
        guard persistenceError != .invalidArchive, persistenceError != .unreadableArchive else {
            throw persistenceError ?? RecordPersistenceError.writeFailed
        }
        let timeZone = TimeZone(identifier: archive.periods.first?.timeZoneIdentifier ?? "") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let documentData = try RecordJSON.export(
            archive,
            exportedAt: .now,
            timeZone: timeZone,
            calendar: calendar
        )
        _ = try RecordJSON.decode(documentData)
        let file = RecordLocalFile(
            schemaVersion: RecordJSON.schemaVersion,
            document: documentData,
            erased: archive.erased.map {
                ErasedDTO(
                    entityType: $0.entityType,
                    logicalKey: $0.logicalKey,
                    erasedAtMs: $0.erasedAt.timeIntervalSince1970 * 1_000,
                    editCount: $0.editCount
                )
            },
            sync: archive.sync
        )
        let data = try JSONEncoder().encode(file)
        try data.write(to: fileURL, options: .atomic)
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
    /// Optional so an archive written before versioned tombstones still decodes.
    var editCount: Int?
}

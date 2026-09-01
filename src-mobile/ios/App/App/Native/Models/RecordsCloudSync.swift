import CloudKit
import Foundation

enum RecordsCloudSyncStatus: Equatable, Sendable {
    case off
    case idle
    case syncing
    case deleting
    case deleted
    case needsNetwork
    case noCloudRecords
    case accountChanged
    case failed(String)
}

@MainActor
@Observable
final class RecordsCloudSync: NSObject, @unchecked Sendable {
    static let containerID = "iCloud.com.rainif.offworkcountdown.macappstore"

    private(set) var status: RecordsCloudSyncStatus = .off
    private(set) var lastError: String?
    private weak var records: RecordCoordinator?
    private var engine: CKSyncEngine?
    private var accountObserver: NSObjectProtocol?
    private var starting = false
    private var operation: Task<Void, Never>?
    private var acceptRemote = true

    func attach(records: RecordCoordinator) {
        self.records = records
        records.onDirty = { [weak self] in
            Task { @MainActor in
                await self?.enqueueLocalRecords()
            }
        }
        if records.state.sync.syncEnabled {
            status = .idle
        }
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reconcileAccountNotification()
            }
        }
    }

    func startIfEnabled() {
        guard records?.state.sync.syncEnabled == true else { return }
        Task { await runExclusive { await self.resumeUnsynchronized() } }
    }

    func enable(authorized: Bool) async {
        await runExclusive { await self.enableUnsynchronized(authorized: authorized) }
    }

    func restore() async {
        await runExclusive { await self.restoreUnsynchronized() }
    }

    func disable(deleteCloud: Bool) async {
        await runExclusive { await self.disableUnsynchronized(deleteCloud: deleteCloud) }
    }

    func deleteAllCloud() async {
        await runExclusive { await self.deleteAllCloudUnsynchronized() }
    }

    func wipeLocalRecords() async {
        await runExclusive {
            self.stopAndInvalidate()
            guard let records = self.records, records.deleteAllLocalData() else {
                self.failPersistence()
                return
            }
            self.lastError = nil
            self.status = .off
        }
    }

    private func runExclusive(_ work: @escaping () async -> Void) async {
        let previous = operation
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        operation = task
        await task.value
    }

    private func stopAndInvalidate() {
        acceptRemote = false
        let invalidatedEngine = engine
        engine = nil
        Task { await invalidatedEngine?.cancelOperations() }
    }

    private func pauseForAccountChange() {
        stopAndInvalidate()
        if let records {
            var sync = records.state.sync
            sync.syncEnabled = false
            sync.engineState = nil
            if !records.replaceSyncState(sync) {
                lastError = RecordPersistenceError.writeFailed.localizedDescription
            }
        }
        status = .accountChanged
    }

    /// `CKAccountChanged` does not say which account is active. Resolve it
    /// after any in-flight sync operation, then pause only when the account
    /// really differs. Treating the notification itself as proof of a switch
    /// made a normal CKSyncEngine sign-in disable a just-restored sync.
    private func reconcileAccountNotification() async {
        await runExclusive { await self.reconcileAccountNotificationUnsynchronized() }
    }

    private func reconcileAccountNotificationUnsynchronized() async {
        guard let records, records.state.sync.syncEnabled else { return }
        do {
            let currentAccountID = try await CKContainer(identifier: Self.containerID)
                .userRecordID()
                .recordName
            guard RecordsSyncCloudPrerequisites.acceptsAccount(
                storedAccountID: records.state.sync.accountID,
                currentAccountID: currentAccountID,
                mayAdoptCurrentAccount: false
            ) else {
                pauseForAccountChange()
                return
            }
        } catch let error as CKError where error.code == .notAuthenticated {
            pauseForAccountChange()
        } catch {
            noteNetworkFailure(error)
        }
    }

    /// A newly-created CKSyncEngine reports `.signIn` even when it signed in
    /// to the exact account we persisted moments earlier. That is a healthy
    /// bootstrap event, not an account replacement. Sign-out and a genuinely
    /// different account still fail closed.
    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        let currentAccountID: String?
        switch change.changeType {
        case .signIn(let currentUser):
            currentAccountID = currentUser.recordName
        case .switchAccounts(_, let currentUser):
            currentAccountID = currentUser.recordName
        case .signOut:
            currentAccountID = nil
        @unknown default:
            currentAccountID = nil
        }

        if let records, let currentAccountID,
           RecordsSyncCloudPrerequisites.acceptsAccount(
               storedAccountID: records.state.sync.accountID,
               currentAccountID: currentAccountID,
               mayAdoptCurrentAccount: false
           ) {
            return
        }
        pauseForAccountChange()
    }

    private func failPersistence() {
        stopAndInvalidate()
        lastError = RecordPersistenceError.writeFailed.localizedDescription
        status = .failed("persistence")
    }

    private func failClosed(_ reason: String) {
        stopAndInvalidate()
        lastError = reason
        status = .failed("prerequisite")
    }

    private func noteNetworkFailure(_ error: Error) {
        stopAndInvalidate()
        lastError = error.localizedDescription
        status = .needsNetwork
    }

    private func resumeUnsynchronized() async {
        guard let records, records.state.sync.syncEnabled else { return }
        let container = CKContainer(identifier: Self.containerID)
        do {
            let accountID = try await container.userRecordID().recordName
            guard RecordsSyncCloudPrerequisites.acceptsAccount(
                storedAccountID: records.state.sync.accountID,
                currentAccountID: accountID,
                mayAdoptCurrentAccount: false
            ) else {
                pauseForAccountChange()
                return
            }
            let remoteFence = try await fetchFence(container: container)
            guard RecordsSyncCloudPrerequisites.canResume(
                localGeneration: records.state.sync.generation,
                remoteFence: remoteFence
            ) else {
                if remoteFence == 0 {
                    stopAndInvalidate()
                    status = .noCloudRecords
                } else {
                    failClosed("The iCloud fence is older than this device's local generation.")
                }
                return
            }
            if remoteFence > records.state.sync.generation,
               !records.discardForHigherFence(remoteFence) {
                failPersistence()
                return
            }
            status = .syncing
            await createEngine(container: container)
            if records.state.sync.syncEnabled { status = .idle }
        } catch {
            noteNetworkFailure(error)
        }
    }

    private func enableUnsynchronized(authorized: Bool) async {
        guard authorized else {
            status = .failed("plus")
            return
        }
        guard let records else { return }
        do {
            let container = CKContainer(identifier: Self.containerID)
            let accountID = try await container.userRecordID().recordName
            guard RecordsSyncCloudPrerequisites.acceptsAccount(
                storedAccountID: records.state.sync.accountID,
                currentAccountID: accountID,
                mayAdoptCurrentAccount: true
            ) else {
                pauseForAccountChange()
                return
            }
            let fetchedFence = try await fetchFence(container: container)
            let remoteFence = if fetchedFence == 0 {
                try await saveFenceCAS(
                    database: container.privateCloudDatabase,
                    atLeast: max(1, records.state.sync.generation)
                )
            } else {
                fetchedFence
            }
            guard RecordsSyncCloudPrerequisites.canResume(
                localGeneration: records.state.sync.generation,
                remoteFence: remoteFence
            ) else {
                failClosed("The iCloud fence is older than this device's local generation.")
                return
            }
            if remoteFence > records.state.sync.generation {
                guard records.discardForHigherFence(remoteFence) else {
                    failPersistence()
                    return
                }
            }
            var sync = records.state.sync
            if sync.accountID == nil { sync.engineState = nil }
            sync.accountID = accountID
            sync.syncEnabled = true
            sync.generation = remoteFence
            guard records.replaceSyncState(sync) else {
                failPersistence()
                return
            }
            status = .syncing
            await createEngine(container: container)
            if records.state.sync.syncEnabled { status = .idle }
        } catch {
            noteNetworkFailure(error)
        }
    }

    private func restoreUnsynchronized() async {
        guard let records else { return }
        do {
            let container = CKContainer(identifier: Self.containerID)
            let accountID = try await container.userRecordID().recordName
            guard RecordsSyncCloudPrerequisites.acceptsAccount(
                storedAccountID: records.state.sync.accountID,
                currentAccountID: accountID,
                mayAdoptCurrentAccount: true
            ) else {
                pauseForAccountChange()
                return
            }
            let fence = try await fetchFence(container: container)
            let zoneNames = try await container.privateCloudDatabase.allRecordZones().map(\.zoneID.zoneName)
            guard RecordsSyncCloudPrerequisites.hasRestorableData(
                fence: fence,
                zoneNames: zoneNames
            ) else {
                stopAndInvalidate()
                status = .noCloudRecords
                return
            }
            if fence > records.state.sync.generation {
                guard records.discardForHigherFence(fence) else {
                    failPersistence()
                    return
                }
            } else if fence < records.state.sync.generation {
                failClosed("The iCloud fence is older than this device's local generation.")
                return
            }
            var sync = records.state.sync
            if sync.accountID == nil { sync.engineState = nil }
            sync.accountID = accountID
            sync.generation = fence
            sync.syncEnabled = true
            guard records.replaceSyncState(sync) else {
                failPersistence()
                return
            }
            status = .syncing
            await createEngine(container: container)
            if records.state.sync.syncEnabled { status = .idle }
        } catch {
            noteNetworkFailure(error)
        }
    }

    private func disableUnsynchronized(deleteCloud: Bool) async {
        guard let records else { return }
        stopAndInvalidate()
        if deleteCloud {
            await deleteAllCloudUnsynchronized()
            guard status == .deleted else { return }
            // "Delete everywhere" recreates the engine for the new generation
            // because sync is still enabled at that point. Turning sync off is
            // the whole reason we are here, so tear it down again before the
            // flag flips — otherwise the next local edit uploads through it.
            stopAndInvalidate()
        }
        var sync = records.state.sync
        sync.syncEnabled = false
        guard records.replaceSyncState(sync) else {
            failPersistence()
            return
        }
        status = deleteCloud && self.status == .deleted ? .deleted : .off
    }

    private func deleteAllCloudUnsynchronized() async {
        guard let records else { return }
        status = .deleting
        do {
            let container = CKContainer(identifier: Self.containerID)
            let database = container.privateCloudDatabase
            let next = try await saveFenceCAS(database: database, atLeast: records.state.sync.generation + 1)
            stopAndInvalidate()
            guard records.discardForHigherFence(next) else {
                failPersistence()
                return
            }
            try await deleteStaleZones(database: database, fence: next)
            // "Delete everywhere" keeps an already-enabled sync relationship
            // alive. Recreate the engine in the new, empty generation now so
            // a record written later in this session does not wait for the next
            // app launch before it can upload.
            if records.state.sync.syncEnabled {
                await createEngine(container: container)
            }
            status = .deleted
        } catch {
            status = .needsNetwork
            lastError = error.localizedDescription
        }
    }

    func handleAccountChange() {
        pauseForAccountChange()
    }

    private func createEngine(container: CKContainer) async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        guard let records, records.state.sync.syncEnabled else { return }
        let database = container.privateCloudDatabase
        acceptRemote = true
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: records.state.sync.engineState.flatMap {
                try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
            },
            delegate: self
        )
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
        let zoneID = CKRecordZone.ID(
            zoneName: RecordsSyncIdentity.dataZone(generation: records.state.sync.generation)
        )
        // Zone creation belongs to the engine's database-change queue. The
        // previous fire-and-forget save in `makeNextBatch` raced the first
        // record upload, so a fresh account could send RecordRow before its
        // custom zone existed and fail with `zoneNotFound`.
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        await enqueueLocalRecords()
        await deleteStaleZonesIfNeeded(database: database)
    }

    private func enqueueLocalRecords() async {
        guard let records, records.state.sync.syncEnabled, let engine else { return }
        let zoneID = CKRecordZone.ID(
            zoneName: RecordsSyncIdentity.dataZone(generation: records.state.sync.generation)
        )
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for row in RecordsSyncOutbox.pending(records.state.sync) {
            let dataID = CKRecord.ID(recordName: row.recordName, zoneID: zoneID)
            let erasedID = CKRecord.ID(
                recordName: RecordsSyncIdentity.erasedName(type: row.entityType, key: row.logicalKey),
                zoneID: zoneID
            )
            if row.pendingErase {
                changes.append(.saveRecord(erasedID))
                changes.append(.deleteRecord(dataID))
            } else {
                changes.append(.saveRecord(dataID))
                // A row recorded again after an erase has to take its tombstone
                // down too. Saving only the data record leaves `erased.*` in
                // iCloud, and every other device erases the row again.
                if row.revokesErase {
                    changes.append(.deleteRecord(erasedID))
                }
            }
        }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private func fetchFence(container: CKContainer) async throws -> Int {
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: RecordsSyncIdentity.controlZone)
        _ = try? await database.save(CKRecordZone(zoneID: zoneID))
        let recordID = CKRecord.ID(recordName: RecordsSyncIdentity.fenceRecord, zoneID: zoneID)
        do {
            let record = try await database.record(for: recordID)
            return record["generation"] as? Int ?? 0
        } catch let error as CKError where error.code == .unknownItem {
            return 0
        }
    }

    private func saveFenceCAS(database: CKDatabase, atLeast minimum: Int) async throws -> Int {
        let zoneID = CKRecordZone.ID(zoneName: RecordsSyncIdentity.controlZone)
        _ = try? await database.save(CKRecordZone(zoneID: zoneID))
        let recordID = CKRecord.ID(recordName: RecordsSyncIdentity.fenceRecord, zoneID: zoneID)
        var attempts = 0
        while attempts < 8 {
            attempts += 1
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: "Fence", recordID: recordID)
            }
            let current = record["generation"] as? Int ?? 0
            if current >= minimum, record.recordChangeTag != nil {
                return current
            }
            let target = record.recordChangeTag == nil ? max(minimum, 1) : max(minimum, current + 1)
            record["generation"] = target as CKRecordValue
            do {
                _ = try await database.save(record)
                return target
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            }
        }
        throw CKError(.serverRecordChanged)
    }

    private func deleteStaleZonesIfNeeded(database: CKDatabase) async {
        guard let records else { return }
        try? await deleteStaleZones(database: database, fence: records.state.sync.generation)
    }

    private func deleteStaleZones(database: CKDatabase, fence: Int) async throws {
        let zones = try await database.allRecordZones()
        let stale = RecordsSyncGeneration.staleZones(
            named: zones.map(\.zoneID.zoneName),
            fence: fence
        )
        for name in stale {
            try await database.deleteRecordZone(withID: CKRecordZone.ID(zoneName: name))
        }
    }
}

extension RecordsCloudSync: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run {
            guard self.engine === syncEngine, self.acceptRemote else { return }
            self.applyEvent(event)
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await MainActor.run {
            guard self.engine === syncEngine, self.acceptRemote else { return nil }
            return self.makeNextBatch()
        }
    }

    private func applyEvent(_ event: CKSyncEngine.Event) {
        guard acceptRemote, let records else { return }
        switch event {
        case .stateUpdate(let update):
            var sync = records.state.sync
            sync.engineState = try? JSONEncoder().encode(update.stateSerialization)
            if !records.replaceSyncState(sync) {
                failPersistence()
            }
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedRecordZoneChanges(let changes):
            applyFetched(changes.modifications.map(\.record), deletions: changes.deletions.map(\.recordID))
        case .sentDatabaseChanges(let sent):
            applySentDatabaseChanges(sent)
        case .sentRecordZoneChanges(let sent):
            applySent(sent)
        default:
            break
        }
    }

    private func applySentDatabaseChanges(_ sent: CKSyncEngine.Event.SentDatabaseChanges) {
        for failure in sent.failedZoneSaves {
            noteCloudFailure(failure.error)
        }
        for (_, error) in sent.failedZoneDeletes where error.code != .zoneNotFound {
            noteCloudFailure(error)
        }
    }

    private func applySent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        guard let records else { return }
        var sync = records.state.sync
        let savedNames = Set(sent.savedRecords.map(\.recordID.recordName))
        // A tombstone CloudKit says was never there is a tombstone that is
        // gone, which is all a revocation wanted. Counting it as deleted keeps
        // the revived row from staying dirty and retrying forever.
        let deletedNames = Set(sent.deletedRecordIDs.map(\.recordName))
            .union(
                sent.failedRecordDeletes
                    .filter { $0.value.code == .unknownItem }
                    .map(\.key.recordName)
            )
        for saved in sent.savedRecords {
            let name = saved.recordID.recordName
            guard let row = sync.rows[name] ?? sync.rows.first(where: { _, value in
                RecordsSyncIdentity.erasedName(type: value.entityType, key: value.logicalKey) == name
            })?.value else {
                continue
            }
            let count = saved["editCount"] as? Int ?? row.editCount
            let tie = saved["editTieBreaker"] as? String ?? row.editTieBreaker
            if RecordsSyncSent.shouldClearSave(
                row: row,
                savedCount: count,
                savedTie: tie,
                deletedNames: deletedNames
            ) {
                RecordsSyncOutbox.clearDirty(&sync, recordName: row.recordName)
            }
            if var current = sync.rows[row.recordName] {
                if name == row.recordName {
                    current.lastKnownRecord = encodeSystemFields(saved)
                    // The baseline must describe the version CloudKit just
                    // acknowledged. Re-encoding current local state here can
                    // accidentally store an N+1 edit while this receipt is
                    // only for N, breaking the next three-way merge.
                    current.lastKnownPayload = saved["payload"] as? Data
                } else {
                    current.lastKnownErasedRecord = encodeSystemFields(saved)
                }
                sync.rows[row.recordName] = current
            }
        }
        for (name, row) in sync.rows where row.pendingErase {
            if RecordsSyncSent.shouldClearErase(row: row, savedNames: savedNames, deletedNames: deletedNames) {
                RecordsSyncOutbox.clearDirty(&sync, recordName: name)
            }
        }
        guard records.replaceSyncState(sync) else {
            failPersistence()
            return
        }
        for failure in sent.failedRecordSaves {
            handleFailedSave(failure)
        }
        for (_, error) in sent.failedRecordDeletes {
            if error.code == .zoneNotFound {
                recoverMissingDataZone()
            } else if error.code != .unknownItem {
                noteCloudFailure(error)
            }
        }
    }

    private func handleFailedSave(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave
    ) {
        let error = failure.error
        if error.code == .serverRecordChanged, let server = error.serverRecord {
            applyFetched([server], deletions: [])
        } else if error.code == .zoneNotFound {
            recoverMissingDataZone()
        } else {
            noteCloudFailure(error)
        }
    }

    private func recoverMissingDataZone() {
        guard let records, let engine else { return }
        let zoneID = CKRecordZone.ID(
            zoneName: RecordsSyncIdentity.dataZone(generation: records.state.sync.generation)
        )
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        Task { @MainActor in
            await enqueueLocalRecords()
        }
        status = .syncing
    }

    private func noteCloudFailure(_ error: CKError?) {
        if error?.code == .zoneBusy || error?.code == .requestRateLimited {
            status = .needsNetwork
        } else if let error {
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
        }
    }

    private func makeNextBatch() -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let records else { return nil }
        let zoneID = CKRecordZone.ID(
            zoneName: RecordsSyncIdentity.dataZone(generation: records.state.sync.generation)
        )
        let pending = RecordsSyncOutbox.nextBatch(records.state.sync)
        guard !pending.isEmpty else { return nil }
        var saves: [CKRecord] = []
        var deletes: [CKRecord.ID] = []
        var atomic = false
        for row in pending {
            let dataID = CKRecord.ID(recordName: row.recordName, zoneID: zoneID)
            let erasedID = CKRecord.ID(
                recordName: RecordsSyncIdentity.erasedName(type: row.entityType, key: row.logicalKey),
                zoneID: zoneID
            )
            if row.pendingErase {
                deletes.append(dataID)
                if let erased = makeRecord(for: erasedID, zoneID: zoneID) {
                    saves.append(erased)
                }
                atomic = true
            } else if let record = makeRecord(for: dataID, zoneID: zoneID) {
                saves.append(record)
                // Revival is the mirror of the erase pair and is just as
                // atomic: a fetching device must not see the record without
                // also seeing that its tombstone is gone.
                if row.revokesErase {
                    deletes.append(erasedID)
                    atomic = true
                }
            }
        }
        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: saves,
            recordIDsToDelete: deletes,
            atomicByZone: atomic
        )
    }

    private func makeRecord(for recordID: CKRecord.ID, zoneID: CKRecordZone.ID) -> CKRecord? {
        guard let records else { return nil }
        if recordID.recordName.hasPrefix("erased.") {
            let row = records.state.sync.rows.values.first {
                RecordsSyncIdentity.erasedName(type: $0.entityType, key: $0.logicalKey) == recordID.recordName
            }
            let record = restoreOrCreate(
                recordID: recordID,
                type: "ErasedID",
                systemFields: row?.lastKnownErasedRecord
            )
            record["generation"] = records.state.sync.generation as CKRecordValue
            // The version this tombstone buried. A device that never held the
            // row needs it to rank a later revival against the erase.
            if let row {
                let buried = records.state.erasedEditCount(row.entityType, key: row.logicalKey) ?? 0
                record["editCount"] = buried as CKRecordValue
            }
            return record
        }
        let row = records.state.sync.rows[recordID.recordName]
        let record = restoreOrCreate(
            recordID: recordID,
            type: "RecordRow",
            systemFields: row?.lastKnownRecord
        )
        record["generation"] = records.state.sync.generation as CKRecordValue
        if let row {
            record["entityType"] = row.entityType.rawValue as CKRecordValue
            record["logicalKey"] = row.logicalKey as CKRecordValue
            record["editCount"] = row.editCount as CKRecordValue
            record["editTieBreaker"] = row.editTieBreaker as CKRecordValue
            if let payload = RecordsSyncPayload.encode(
                type: row.entityType,
                key: row.logicalKey,
                from: records.state
            ) {
                record["payload"] = payload as CKRecordValue
            }
        }
        return record
    }

    private func restoreOrCreate(recordID: CKRecord.ID, type: String, systemFields: Data?) -> CKRecord {
        if let systemFields,
           let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFields) {
            coder.requiresSecureCoding = true
            if let restored = CKRecord(coder: coder),
               restored.recordID == recordID,
               restored.recordType == type {
                return restored
            }
        }
        return CKRecord(recordType: type, recordID: recordID)
    }

    /// Splits `erased.<type>.<key>` into its two halves.
    private func erasedIdentity(_ recordName: String) -> (RecordEntityType, String)? {
        guard recordName.hasPrefix("erased.") else { return nil }
        let parts = recordName.split(separator: ".", maxSplits: 2).map(String.init)
        guard parts.count == 3, let type = RecordEntityType(rawValue: parts[1]) else { return nil }
        return (type, parts[2])
    }

    private func applyFetched(_ recordsFetched: [CKRecord], deletions: [CKRecord.ID]) {
        guard let records else { return }
        // Tombstone revocations first. A revival ships the record save and the
        // `erased.*` delete in one atomic batch, and applying the save while the
        // local tombstone still stood would reassert the erase and delete the
        // row the user just recorded again.
        for deletion in deletions {
            guard let (type, key) = erasedIdentity(deletion.recordName) else { continue }
            records.applyRemoteEraseRevocation(type: type, key: key)
        }
        var discarded = false
        for record in recordsFetched {
            if record.recordType == "Fence" || record.recordID.recordName == RecordsSyncIdentity.fenceRecord {
                let fence = record["generation"] as? Int ?? 0
                if fence > records.state.sync.generation {
                    stopAndInvalidate()
                    guard records.discardForHigherFence(fence) else {
                        failPersistence()
                        return
                    }
                    discarded = true
                }
                continue
            }
            if discarded { continue }
            let generation = record["generation"] as? Int ?? 0
            if RecordsSyncGeneration.shouldDiscard(
                recordGeneration: generation,
                fence: records.state.sync.generation
            ) {
                continue
            }
            if let (type, key) = erasedIdentity(record.recordID.recordName) {
                records.applyRemoteErase(
                    type: type,
                    key: key,
                    erasedEditCount: record["editCount"] as? Int,
                    systemFields: encodeSystemFields(record),
                    generation: generation
                )
                continue
            }
            guard let type = RecordEntityType(rawValue: record["entityType"] as? String ?? ""),
                  let key = record["logicalKey"] as? String,
                  let payload = record["payload"] as? Data
            else { continue }
            records.applyRemotePayload(
                type: type,
                key: key,
                payload: payload,
                editCount: record["editCount"] as? Int ?? 0,
                editTieBreaker: record["editTieBreaker"] as? String ?? "",
                systemFields: encodeSystemFields(record),
                generation: generation,
                persistImmediately: false
            )
        }
        if !deletions.isEmpty {
            var sync = records.state.sync
            for deletion in deletions {
                sync.rows[deletion.recordName] = nil
            }
            guard records.replaceSyncState(sync) else {
                failPersistence()
                return
            }
        }
        if !recordsFetched.isEmpty || !deletions.isEmpty {
            records.persistRemoteBatch()
        }
        if discarded {
            startIfEnabled()
        }
    }

    private func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }
}

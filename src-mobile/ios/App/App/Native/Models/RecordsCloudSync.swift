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

    func attach(records: RecordCoordinator) {
        self.records = records
        if records.state.sync.syncEnabled {
            status = .idle
        }
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAccountChange()
            }
        }
    }

    func startIfEnabled() {
        guard records?.state.sync.syncEnabled == true else { return }
        Task { await startEngine() }
    }

    func enable(authorized: Bool) async {
        guard authorized else {
            status = .failed("plus")
            return
        }
        guard let records else { return }
        do {
            let account = try await CKContainer(identifier: Self.containerID).userRecordID()
            if let previous = records.state.sync.accountID,
               previous != account.recordName {
                status = .accountChanged
                return
            }
            var sync = records.state.sync
            sync.accountID = account.recordName
            sync.syncEnabled = true
            if sync.generation < 1 { sync.generation = 1 }
            records.replaceSyncState(sync)
            status = .syncing
            await startEngine()
            await enqueueLocalRecords()
            status = .idle
        } catch {
            status = .needsNetwork
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        guard let records else { return }
        do {
            let container = CKContainer(identifier: Self.containerID)
            let fence = try await fetchFence(container: container)
            guard fence > 0 else {
                status = .noCloudRecords
                return
            }
            var sync = records.state.sync
            sync.generation = fence
            sync.syncEnabled = true
            records.replaceSyncState(sync)
            status = .syncing
            await startEngine()
            status = .idle
        } catch {
            status = .needsNetwork
            lastError = error.localizedDescription
        }
    }

    func disable(deleteCloud: Bool) async {
        guard let records else { return }
        engine = nil
        if deleteCloud {
            await deleteAllCloud()
        }
        var sync = records.state.sync
        sync.syncEnabled = false
        records.replaceSyncState(sync)
        status = deleteCloud && self.status == .deleted ? .deleted : .off
    }

    func deleteAllCloud() async {
        guard let records else { return }
        status = .deleting
        do {
            let container = CKContainer(identifier: Self.containerID)
            let database = container.privateCloudDatabase
            let current = try await fetchFence(container: container)
            let next = current + 1
            try await saveFence(generation: next, database: database)
            var sync = records.state.sync
            _ = RecordsSyncOutbox.applyHigherFence(&sync, fence: next)
            records.replaceSyncState(sync)
            try await deleteStaleZones(database: database, fence: next)
            status = .deleted
        } catch {
            status = .needsNetwork
            lastError = error.localizedDescription
        }
    }

    func handleAccountChange() {
        guard let records else { return }
        engine = nil
        var sync = records.state.sync
        sync.syncEnabled = false
        sync.engineState = nil
        records.replaceSyncState(sync)
        status = .accountChanged
    }

    private func startEngine() async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        guard let records, records.state.sync.syncEnabled else { return }
        let container = CKContainer(identifier: Self.containerID)
        let database = container.privateCloudDatabase
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: records.state.sync.engineState.flatMap {
                try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
            },
            delegate: self
        )
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
        await deleteStaleZonesIfNeeded(database: database)
    }

    private func enqueueLocalRecords() async {
        guard let records, let engine else { return }
        let pending = RecordsSyncOutbox.pending(records.state.sync)
        let pendingIDs = pending.map { row in
            CKRecord.ID(
                recordName: row.pendingErase
                    ? RecordsSyncIdentity.erasedName(type: row.entityType, key: row.logicalKey)
                    : row.recordName,
                zoneID: CKRecordZone.ID(
                    zoneName: RecordsSyncIdentity.dataZone(generation: records.state.sync.generation)
                )
            )
        }
        engine.state.add(pendingRecordZoneChanges: pendingIDs.map { .saveRecord($0) })
    }

    private func fetchFence(container: CKContainer) async throws -> Int {
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: RecordsSyncIdentity.controlZone)
        try? await database.save(CKRecordZone(zoneID: zoneID))
        let recordID = CKRecord.ID(recordName: RecordsSyncIdentity.fenceRecord, zoneID: zoneID)
        do {
            let record = try await database.record(for: recordID)
            return record["generation"] as? Int ?? 0
        } catch let error as CKError where error.code == .unknownItem {
            return 0
        }
    }

    private func saveFence(generation: Int, database: CKDatabase) async throws {
        let zoneID = CKRecordZone.ID(zoneName: RecordsSyncIdentity.controlZone)
        try? await database.save(CKRecordZone(zoneID: zoneID))
        let recordID = CKRecord.ID(recordName: RecordsSyncIdentity.fenceRecord, zoneID: zoneID)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch {
            record = CKRecord(recordType: "Fence", recordID: recordID)
        }
        record["generation"] = generation as CKRecordValue
        _ = try await database.save(record)
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
        await MainActor.run { self.applyEvent(event) }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await MainActor.run { self.makeNextBatch(database: syncEngine.database) }
    }

    private func applyEvent(_ event: CKSyncEngine.Event) {
        guard let records else { return }
        switch event {
        case .stateUpdate(let update):
            var sync = records.state.sync
            sync.engineState = try? JSONEncoder().encode(update.stateSerialization)
            records.replaceSyncState(sync)
        case .accountChange:
            handleAccountChange()
        case .fetchedRecordZoneChanges(let changes):
            applyFetched(changes.modifications.map(\.record), deletions: changes.deletions.map(\.recordID))
        case .sentRecordZoneChanges(let sent):
            var sync = records.state.sync
            for saved in sent.savedRecords {
                RecordsSyncOutbox.clearDirty(&sync, recordName: saved.recordID.recordName)
                if var row = sync.rows[saved.recordID.recordName] {
                    row.lastKnownRecord = encodeSystemFields(saved)
                    row.lastKnownPayload = RecordsSyncPayload.encode(
                        type: row.entityType,
                        key: row.logicalKey,
                        from: records.state
                    )
                    sync.rows[saved.recordID.recordName] = row
                }
            }
            records.replaceSyncState(sync)
        default:
            break
        }
    }

    private func makeNextBatch(database: CKDatabase) -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let records else { return nil }
        let zoneID = CKRecordZone.ID(
            zoneName: RecordsSyncIdentity.dataZone(generation: records.state.sync.generation)
        )
        Task { try? await database.save(CKRecordZone(zoneID: zoneID)) }
        let pending = RecordsSyncOutbox.pending(records.state.sync)
        guard !pending.isEmpty else { return nil }
        var saves: [CKRecord] = []
        var deletes: [CKRecord.ID] = []
        var atomic = false
        for row in pending {
            let dataID = CKRecord.ID(recordName: row.recordName, zoneID: zoneID)
            if row.pendingErase {
                let erasedID = CKRecord.ID(
                    recordName: RecordsSyncIdentity.erasedName(type: row.entityType, key: row.logicalKey),
                    zoneID: zoneID
                )
                deletes.append(dataID)
                if let erased = makeRecord(for: erasedID, zoneID: zoneID) {
                    saves.append(erased)
                }
                atomic = true
            } else if let record = makeRecord(for: dataID, zoneID: zoneID) {
                saves.append(record)
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
            let record = CKRecord(recordType: "ErasedID", recordID: recordID)
            record["generation"] = records.state.sync.generation as CKRecordValue
            return record
        }
        let record = CKRecord(recordType: "RecordRow", recordID: recordID)
        record["generation"] = records.state.sync.generation as CKRecordValue
        if let row = records.state.sync.rows[recordID.recordName] {
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

    private func applyFetched(_ recordsFetched: [CKRecord], deletions: [CKRecord.ID]) {
        guard let records else { return }
        for record in recordsFetched {
            let generation = record["generation"] as? Int ?? 0
            if RecordsSyncGeneration.shouldDiscard(
                recordGeneration: generation,
                fence: records.state.sync.generation
            ) {
                continue
            }
            if record.recordID.recordName.hasPrefix("erased.") {
                let parts = record.recordID.recordName.split(separator: ".", maxSplits: 2).map(String.init)
                if parts.count == 3, let type = RecordEntityType(rawValue: parts[1]) {
                    records.applyRemoteErase(type: type, key: parts[2])
                }
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
                generation: generation
            )
        }
        if !deletions.isEmpty {
            var sync = records.state.sync
            for deletion in deletions {
                sync.rows[deletion.recordName] = nil
            }
            records.replaceSyncState(sync)
        }
    }

    private func encodeSystemFields(_ record: CKRecord) -> Data {
        let archive = NSMutableData()
        let coder = NSKeyedArchiver(forWritingWith: archive)
        coder.requiresSecureCoding = true
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return archive as Data
    }
}

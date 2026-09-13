import Foundation

/// The existing local archive envelope. Backup JSON and CloudKit payloads
/// retain their own contracts; only the local file contains sync metadata.
nonisolated struct RecordLocalFile: Codable, Sendable {
    var schemaVersion: Int
    var document: Data
    var erased: [ErasedDTO]
    var sync: SyncLocalState?
}

nonisolated struct ErasedDTO: Codable, Sendable {
    var entityType: RecordEntityType
    var logicalKey: String
    var erasedAtMs: Double
    /// Optional so an archive written before versioned tombstones still decodes.
    var editCount: Int?
}

nonisolated struct PreparedRecordImport: Sendable {
    var state: RecordState
    var report: RecordImportReport
}

nonisolated enum RecordArchiveLoadResult: Sendable {
    case missing
    case loaded(RecordState, normalizedConflicts: Bool)
    case failed(RecordPersistenceError)
}

nonisolated enum RecordArchiveReadError: Error {
    case securityScopedFileUnavailable
    case readFailed
}

/// Pure encoding and validation, usable by the serial persistence worker.
nonisolated enum RecordArchive {
    @concurrent
    static func load(from fileURL: URL, at date: Date = .now) async -> RecordArchiveLoadResult {
        loadSynchronously(from: fileURL, at: date)
    }

    static func loadSynchronously(from fileURL: URL, at date: Date = .now) -> RecordArchiveLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let decoded = try decodeLocalFile(Data(contentsOf: fileURL), at: date)
            return .loaded(decoded.0, normalizedConflicts: decoded.normalizedConflicts)
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .failed(.unreadableArchive)
        } catch {
            return .failed(.invalidArchive)
        }
    }

    @concurrent
    static func quarantineFile(at fileURL: URL, backupURL: URL) async throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
        return backupURL
    }

    @concurrent
    static func validate(_ archive: RecordState) async throws {
        _ = try encode(archive)
    }

    @concurrent
    static func prepareImport(_ data: Data, into archive: RecordState, mode: RecordImportMode) async throws -> PreparedRecordImport {
        let document = try RecordJSON.decode(data)
        var candidate = archive
        let report = try RecordJSON.apply(document, to: &candidate, mode: mode)
        return PreparedRecordImport(state: candidate, report: report)
    }

    @concurrent
    static func exportBackup(_ archive: RecordState, exportedAt: Date, timeZone: TimeZone) async throws -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try RecordJSON.export(archive, exportedAt: exportedAt, timeZone: timeZone, calendar: calendar)
    }

    /// Keep the filename readable in the share sheet while isolating concurrent
    /// exports from one another.
    @concurrent
    static func writeExport(_ data: Data, named filename: String) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "doneat-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let url = directory.appending(path: filename)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Security-scoped access must cover the actual read. File-provider URLs
    /// can block while materializing their contents, so keep the whole lifetime
    /// away from the main actor.
    @concurrent
    static func readSecurityScopedFile(_ url: URL) async throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw access ? RecordArchiveReadError.readFailed : .securityScopedFileUnavailable
        }
    }

    /// Write the complete file away from the main actor. The coordinator
    /// validates its revision before publishing this prepared candidate.
    @concurrent
    static func prepare(_ archive: RecordState, for fileURL: URL) async throws -> URL {
        let data = try encode(archive)
        let prepared = fileURL.deletingLastPathComponent()
            .appending(path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).pending")
        do {
            try data.write(to: prepared, options: .atomic)
            return prepared
        } catch {
            try? FileManager.default.removeItem(at: prepared)
            throw error
        }
    }

    /// Both ordinary edits and exclusively admitted candidates publish on the
    /// persistence worker. Their coordinator retains the ordered write chain.
    @concurrent
    static func publishPrepared(_ prepared: URL, at fileURL: URL) async throws {
        try publish(prepared, at: fileURL)
    }

    @concurrent
    static func discardPrepared(_ prepared: URL) async {
        try? FileManager.default.removeItem(at: prepared)
    }

    static func publish(_ prepared: URL, at fileURL: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
            guard !isDirectory.boolValue else { throw CocoaError(.fileWriteInvalidFileName) }
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: prepared)
        } else {
            try FileManager.default.moveItem(at: prepared, to: fileURL)
        }
    }

    static func encode(_ archive: RecordState) throws -> Data {
        let timeZone = TimeZone(identifier: archive.periods.first?.timeZoneIdentifier ?? "") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let documentData = try RecordJSON.export(
            archive,
            exportedAt: .now,
            timeZone: timeZone,
            calendar: calendar
        )
        let document = try RecordJSON.decode(documentData)
        var validated = RecordState()
        let report = try RecordJSON.apply(document, to: &validated, mode: .skipErased)
        guard report.rejected.isEmpty else { throw RecordJSONError.invalidDocument }
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
        return try JSONEncoder().encode(file)
    }

    private static func decodeLocalFile(
        _ data: Data,
        at date: Date
    ) throws -> (RecordState, normalizedConflicts: Bool) {
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
        migrateLegacyAutomaticPeriod(in: &archive, at: date)
        if var profile = archive.lifeProfile {
            profile.migrateLegacyFields(calendar: RecordsSyncPayload.fileCalendar(for: archive))
            archive.lifeProfile = profile
        }
        return (archive, normalizeStoredConflicts(in: &archive))
    }

    private static func migrateLegacyAutomaticPeriod(in archive: inout RecordState, at date: Date) {
        guard archive.periods.count == 1, archive.periods[0].label == nil else { return }
        let calendar = archive.periods[0].civilCalendar()
        guard RecordJSON.dayKey(archive.periods[0].startsOn, calendar: calendar) == "2000-01-01" else { return }
        let candidates = archive.observations.map(\.shiftAnchorDate)
            + archive.overrides.map(\.shiftAnchorDate)
            + archive.exceptions.map(\.date)
            + [date]
        guard let earliest = candidates.min() else { return }
        archive.periods[0].startsOn = calendar.startOfDay(for: earliest)
        archive.recordsStartedOn = archive.recordsStartedOn ?? archive.periods[0].startsOn
    }

    private static func normalizeStoredConflicts(in archive: inout RecordState) -> Bool {
        let original = archive.sync.conflicts
        var latestByIdentity: [String: SyncConflictCopy] = [:]
        let calendar = RecordsSyncPayload.fileCalendar(for: archive)
        for conflict in original {
            if let local = conflict.localPayload,
               let incoming = conflict.incomingPayload,
               RecordsSyncConflict.payloadsHaveSameBusinessContent(local, incoming) { continue }
            if conflict.source != "import",
               let local = conflict.localPayload,
               let incoming = conflict.incomingPayload,
               let localStamp = RecordsSyncPayload.editStamp(from: local, type: conflict.entityType, calendar: calendar),
               let incomingStamp = RecordsSyncPayload.editStamp(from: incoming, type: conflict.entityType, calendar: calendar),
               let preferred = RecordsSyncConflict.automaticallyPreferredWinner(
                   localCount: localStamp.0,
                   localEditedAtMs: conflict.localEditedAtMs ?? RecordsSyncPayload.editedAtMs(from: local, type: conflict.entityType, calendar: calendar),
                   incomingCount: incomingStamp.0,
                   incomingEditedAtMs: conflict.incomingEditedAtMs ?? RecordsSyncPayload.editedAtMs(from: incoming, type: conflict.entityType, calendar: calendar)
               ), preferred == conflict.currentWinner { continue }
            let identity = "\(conflict.entityType.rawValue).\(conflict.logicalKey)"
            if let previous = latestByIdentity[identity], previous.lostAtMs > conflict.lostAtMs { continue }
            latestByIdentity[identity] = conflict
        }
        archive.sync.conflicts = latestByIdentity.values.sorted {
            if $0.lostAtMs != $1.lostAtMs { return $0.lostAtMs < $1.lostAtMs }
            return $0.id.uuidString < $1.id.uuidString
        }
        return archive.sync.conflicts != original
    }
}

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

/// Serializes every records write. The archive is a local JSON file in
/// Application Support — not the App Group, and not SwiftData yet.
@MainActor
@Observable
final class RecordCoordinator {
    private(set) var state = RecordState()
    private let fileURL: URL?
    var captureEnabled = true

    static func inMemory() -> RecordCoordinator {
        RecordCoordinator(fileURL: nil)
    }

    static func persisted() -> RecordCoordinator {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "owc-records", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let coordinator = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
        coordinator.load()
        return coordinator
    }

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    func deleteAllLocalData() {
        state.deleteAllLocalData()
        persist()
    }

    func erase(_ type: RecordEntityType, key: String, at date: Date = .now) {
        state.erase(type, key: key, at: date)
        persist()
    }

    func exportJSON(exportedAt: Date = .now, timeZone: TimeZone = .current) throws -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try RecordJSON.export(state, exportedAt: exportedAt, timeZone: timeZone, calendar: calendar)
    }

    func `import`(_ data: Data, mode: RecordImportMode = .skipErased) throws -> RecordImportReport {
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
        persist()
    }

    func commitHours(
        _ hours: ScheduleHoursConfiguration,
        effectiveFrom: Date,
        at date: Date,
        timeZone: TimeZone = .current
    ) {
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

    func currentSnapshotID(on day: Date) -> UUID? {
        guard let period = DayRecordResolver.period(on: day, from: state.periods) else { return nil }
        return DayRecordResolver.snapshot(on: day, in: period, from: state.snapshots)?.id
    }

    func recordObservation(
        kind: WorkObservationKind,
        eventID: UUID,
        shiftAnchorDate: Date,
        occurredAt: Date,
        snapshotID: UUID,
        valueData: Data? = nil
    ) {
        guard captureEnabled else { return }
        if state.isErased(.workObservation, key: eventID.uuidString) { return }
        if state.observations.contains(where: { $0.eventID == eventID }) { return }
        if kind == .timerSurfaceFirstSeen {
            let day = Calendar.current.startOfDay(for: shiftAnchorDate)
            let already = state.observations.contains {
                $0.kind == .timerSurfaceFirstSeen
                    && Calendar.current.isDate($0.shiftAnchorDate, inSameDayAs: day)
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
                scheduleSnapshotID: snapshotID
            )
        )
        persist()
    }

    private func appendSnapshot(
        _ hours: ScheduleHoursConfiguration,
        periodID: UUID,
        effectiveFrom: Date,
        at date: Date
    ) {
        guard let encoded = try? ScheduleHoursCodec.encode(hours) else { return }
        state.snapshots.append(
            ScheduleSnapshot(
                id: UUID(),
                periodID: periodID,
                effectiveFrom: effectiveFrom,
                configurationData: encoded.data,
                fingerprint: encoded.fingerprint,
                editedAt: date,
                editCount: 1,
                editTieBreaker: UUID()
            )
        )
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(RecordLocalFile.self, from: data)
        else { return }
        var archive = RecordState()
        if let document = try? RecordJSON.decode(file.document) {
            _ = try? RecordJSON.apply(document, to: &archive, mode: .skipErased)
        }
        archive.erased = file.erased.map {
            ErasedID(
                entityType: $0.entityType,
                logicalKey: $0.logicalKey,
                erasedAt: Date(timeIntervalSince1970: $0.erasedAtMs / 1_000)
            )
        }
        state = archive
    }

    private func persist() {
        guard let fileURL else { return }
        let timeZone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let documentData = try? RecordJSON.export(
            state,
            exportedAt: .now,
            timeZone: timeZone,
            calendar: calendar
        ), let document = try? RecordJSON.decode(documentData) else { return }
        let file = RecordLocalFile(
            schemaVersion: RecordJSON.schemaVersion,
            document: documentData,
            erased: state.erased.map {
                ErasedDTO(entityType: $0.entityType, logicalKey: $0.logicalKey, erasedAtMs: $0.erasedAt.timeIntervalSince1970 * 1_000)
            }
        )
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private struct RecordLocalFile: Codable {
    var schemaVersion: Int
    var document: Data
    var erased: [ErasedDTO]
}

private struct ErasedDTO: Codable {
    var entityType: RecordEntityType
    var logicalKey: String
    var erasedAtMs: Double
}

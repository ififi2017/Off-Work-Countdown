#if DEBUG
import Foundation
import Testing
@testable import App

/// Plan 021 P0: the probe's log, file and export, without Core Location.
@Suite("Workplace probe log")
struct WorkplaceProbeLogTests {
    private static let start = Date(timeIntervalSince1970: 1_794_000_000)

    private static func entry(_ seconds: TimeInterval, kind: WorkplaceProbeEntry.Kind = .event) -> WorkplaceProbeEntry {
        WorkplaceProbeEntry(
            receivedAt: start.addingTimeInterval(seconds), kind: kind, identifier: nil, state: nil,
            observedAt: start, appState: "background", protectedDataAvailable: false,
            authorization: "always", accuracy: "full"
        )
    }

    private static let office = WorkplaceProbePlace(
        id: UUID(), name: "Place 1", latitude: 31.234567, longitude: 121.456789,
        innerRadius: 200, outerRadius: 300, isFiller: false
    )

    @Test("Delivery delay is the gap between observation and receipt")
    func delay() {
        #expect(Self.entry(95).deliveryDelay == 95)
    }

    @Test("The log keeps the newest 3,000 entries")
    func cap() {
        var archive = WorkplaceProbeArchive()
        for second in 0..<(WorkplaceProbeArchive.maximumEntries + 5) {
            archive.append(Self.entry(TimeInterval(second)))
        }
        #expect(archive.entries.count == WorkplaceProbeArchive.maximumEntries)
        #expect(archive.entries.first?.receivedAt == Self.start.addingTimeInterval(5))
    }

    @Test("Fillers bring the probe to five places and ten conditions")
    func fillers() {
        var archive = WorkplaceProbeArchive()
        archive.places = [Self.office]
        archive.places += WorkplaceProbeArchive.fillers(
            around: (Self.office.latitude, Self.office.longitude), existing: 1, radius: 200
        )
        #expect(archive.places.count == 5)
        #expect(archive.conditionCount == 10)
        #expect(archive.places.dropFirst().allSatisfy { $0.isFiller && $0.latitude > Self.office.latitude })
        #expect(archive.places.last?.outerRadius == 300)
    }

    @Test("Exports name places by label and carry no coordinates")
    func export() {
        var archive = WorkplaceProbeArchive()
        archive.places = [Self.office]
        var event = Self.entry(60)
        event.identifier = Self.office.innerIdentifier
        event.state = "satisfied"
        archive.append(event)
        let text = archive.exportText(timeZone: TimeZone(identifier: "UTC")!)
        #expect(text.contains("Place 1/inner\tsatisfied"))
        #expect(text.contains("\t60\t"))
        #expect(!text.contains("31.2345"))
        #expect(!text.contains("121.4567"))
        #expect(!text.contains(Self.office.id.uuidString))
    }

    @Test("The probe file round-trips and is excluded from backup")
    func storage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WorkplaceProbeLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "WorkplaceProbe/probe.json")
        #expect(WorkplaceProbeStorage.load(from: url) == WorkplaceProbeArchive())

        var archive = WorkplaceProbeArchive()
        archive.isEnabled = true
        archive.places = [Self.office]
        archive.append(Self.entry(1, kind: .launch))
        try WorkplaceProbeStorage.save(archive, to: url)
        #expect(WorkplaceProbeStorage.load(from: url) == archive)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(
            try url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
        )
    }
}
#endif

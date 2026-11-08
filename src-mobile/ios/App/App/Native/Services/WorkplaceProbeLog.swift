#if DEBUG || WORKPLACE_PROBE
import Foundation

// Plan 021 P0: what the DEBUG geofence probe records on a real iPhone.
// Pure storage and formatting, so it is testable without Core Location.
// The probe writes no records and sends no notifications; it only observes.

nonisolated struct WorkplaceProbePlace: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var innerRadius: Double
    var outerRadius: Double
    /// A synthetic place added only to fill the condition quota.
    var isFiller: Bool

    var innerIdentifier: String { "probe.\(id.uuidString).inner" }
    var outerIdentifier: String { "probe.\(id.uuidString).outer" }
}

nonisolated struct WorkplaceProbeEntry: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Process start; `appState` tells whether the system launched it in the background.
        case launch
        case event
        case monitorDiagnostic
        case sessionDiagnostic
        case note
        case error
    }

    var id = UUID()
    var receivedAt: Date
    var kind: Kind
    /// Condition identifier, when the entry is about one.
    var identifier: String?
    /// `satisfied`, `unsatisfied`, `unknown` or `unmonitored`.
    var state: String?
    /// When the system says the state changed (`CLMonitor.Event.date`).
    var observedAt: Date?
    var appState: String
    var protectedDataAvailable: Bool
    var authorization: String
    var accuracy: String
    /// Diagnostic flags the system reported with the event or session.
    var flags: [String] = []
    var detail: String?

    /// Seconds between the system's observation and this app receiving it.
    var deliveryDelay: TimeInterval? {
        observedAt.map { receivedAt.timeIntervalSince($0) }
    }
}

nonisolated struct WorkplaceProbeArchive: Codable, Equatable, Sendable {
    static let maximumEntries = 3_000
    static let maximumPlaces = 5

    var isEnabled = false
    var places: [WorkplaceProbePlace] = []
    var entries: [WorkplaceProbeEntry] = []

    /// Conditions registered for the current places: inner and outer each.
    var conditionCount: Int { places.count * 2 }

    mutating func append(_ entry: WorkplaceProbeEntry) {
        entries.append(entry)
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
    }

    /// Four synthetic places 1–4 km north of `center`, so five places hold
    /// the ten conditions the real feature will need (§3.10).
    static func fillers(around center: (latitude: Double, longitude: Double), existing: Int, radius: Double) -> [WorkplaceProbePlace] {
        let missing = max(0, maximumPlaces - existing)
        return (0..<missing).map { index in
            WorkplaceProbePlace(
                id: UUID(),
                name: "Filler \(index + 1)",
                latitude: center.latitude + Double(index + 1) * 0.009, // ≈ 1 km per step
                longitude: center.longitude,
                innerRadius: radius,
                outerRadius: radius + WorkplaceAutomation.defaultOuterRadiusMargin,
                isFiller: true
            )
        }
    }

    /// Plain text for sharing, one entry per line, oldest first.
    func exportText(timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = ["# DoneAt workplace probe export"]
        lines.append("# places: " + places.map {
            "\($0.name) inner=\(Int($0.innerRadius))m outer=\(Int($0.outerRadius))m\($0.isFiller ? " filler" : "")"
        }.joined(separator: "; "))
        lines.append("received\tkind\tidentifier\tstate\tobserved\tdelay_s\tapp\tprotected\tauth\taccuracy\tflags\tdetail")
        for entry in entries {
            lines.append([
                formatter.string(from: entry.receivedAt),
                entry.kind.rawValue,
                entry.identifier.map { placeLabel(for: $0) } ?? "",
                entry.state ?? "",
                entry.observedAt.map(formatter.string(from:)) ?? "",
                entry.deliveryDelay.map { String(format: "%.0f", $0) } ?? "",
                entry.appState,
                entry.protectedDataAvailable ? "yes" : "no",
                entry.authorization,
                entry.accuracy,
                entry.flags.joined(separator: ","),
                entry.detail ?? "",
            ].joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "Office/inner" instead of the raw identifier, so exports carry no UUIDs
    /// worth correlating and stay readable.
    func placeLabel(for identifier: String) -> String {
        for place in places {
            if identifier == place.innerIdentifier { return "\(place.name)/inner" }
            if identifier == place.outerIdentifier { return "\(place.name)/outer" }
        }
        return identifier
    }
}

/// Reads and writes the probe file: device-only, excluded from backups,
/// writable after first unlock like the real automation store.
nonisolated enum WorkplaceProbeStorage {
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "WorkplaceProbe", directoryHint: .isDirectory)
            .appending(path: "probe.json", directoryHint: .notDirectory)
    }

    static func load(from url: URL = defaultURL) -> WorkplaceProbeArchive {
        guard let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(WorkplaceProbeArchive.self, from: data)
        else { return WorkplaceProbeArchive() }
        return archive
    }

    static func save(_ archive: WorkplaceProbeArchive, to url: URL = defaultURL) throws {
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let data = try JSONEncoder().encode(archive)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var file = url
        try file.setResourceValues(values)
    }
}
#endif

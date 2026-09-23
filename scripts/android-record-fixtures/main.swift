import Foundation

// Android task T10/T11. The records backup codec (RecordJSON) is the iOS
// specification for v1–v6 documents, the local archive and imports. This tool
// compiles the real RecordJSON and models and answers each case in the file
// named by argv[1]; `scripts/generate-android-record-fixtures.mjs` writes the
// results for the Kotlin port. Not shipped.

struct Case: Decodable {
    let name: String
    let input: String
    /// Applied first, into an empty archive, when present.
    let base: String?
    /// `[entityType, logicalKey]` pairs erased after `base`.
    let erase: [[String]]?
    let mode: String?
}

func modeValue(_ raw: String?) -> RecordImportMode {
    switch raw {
    case "restoreErased": .restoreErased
    case "resolveByEditStamp": .resolveByEditStamp
    default: .skipErased
    }
}

func counts(_ values: [RecordEntityType: Int]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
}

func export(_ state: RecordState, like document: RecordJSONDocument) -> String {
    let zone = TimeZone(identifier: document.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    let data = try! RecordJSON.export(
        state,
        exportedAt: Date(timeIntervalSince1970: document.exportedAtMs / 1_000),
        timeZone: zone,
        calendar: RecordJSON.calendar(from: document)
    )
    return String(decoding: data, as: UTF8.self)
}

struct Outcome: Encodable {
    let name: String
    var outcome: String
    var schemaVersion: Int?
    var inserted: [String: Int]?
    var unchanged: [String: Int]?
    var skippedErased: [String: Int]?
    var restored: [String: Int]?
    var rejected: [[String]]?
    var conflicts: [[String]]?
    var adopted: [[String]]?
    var exportJSON: String?
}

let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let at = Date(timeIntervalSince1970: 1_790_000_000)
var lines: [String] = []
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

for item in cases {
    var result = Outcome(name: item.name, outcome: "ok")
    var state = RecordState()
    if let base = item.base {
        let document = try! RecordJSON.decode(Data(base.utf8))
        _ = try! RecordJSON.apply(document, to: &state, mode: .skipErased)
    }
    for pair in item.erase ?? [] {
        state.erase(RecordEntityType(rawValue: pair[0])!, key: pair[1], at: at)
    }
    do {
        let document = try RecordJSON.decode(Data(item.input.utf8))
        result.schemaVersion = document.schemaVersion
        let report = try RecordJSON.apply(document, to: &state, mode: modeValue(item.mode))
        result.inserted = counts(report.inserted)
        result.unchanged = counts(report.unchanged)
        result.skippedErased = counts(report.skippedErased)
        result.restored = counts(report.restored)
        result.rejected = report.rejected.map { [$0.entityType.rawValue, $0.logicalKey] }
        result.conflicts = report.conflicts.map {
            [$0.entityType.rawValue, $0.logicalKey, "\($0.localEditCount)", "\($0.incomingEditCount)", $0.appliedIncoming ? "applied" : "kept"]
        }
        result.adopted = report.adopted.map { [$0.entityType.rawValue, $0.logicalKey, "\($0.editCount)", $0.editTieBreaker] }
        result.exportJSON = export(state, like: document)
    } catch RecordJSONError.unknownSchemaVersion(let version) {
        result.outcome = "unknownSchemaVersion"
        result.schemaVersion = version
    } catch {
        result.outcome = "invalidDocument"
    }
    lines.append(String(decoding: try encoder.encode(result), as: UTF8.self))
}
print("[\n" + lines.joined(separator: ",\n") + "\n]")

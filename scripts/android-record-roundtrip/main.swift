import Foundation

// Compiled with the real iOS RecordJSON and model sources by check-android-record-roundtrip.mjs.
// argv: iOS all-entity v6 fixture, then the Kotlin export of that fixture.
func imported(_ path: String) throws -> RecordState {
    let document = try RecordJSON.decode(Data(contentsOf: URL(fileURLWithPath: path)))
    var state = RecordState()
    let report = try RecordJSON.apply(document, to: &state, mode: .skipErased)
    guard report.rejected.isEmpty, report.conflicts.isEmpty else { throw NSError(domain: "roundtrip", code: 1) }
    return state
}

let original = try imported(CommandLine.arguments[1])
let kotlin = try imported(CommandLine.arguments[2])
guard original == kotlin else {
    fputs("Kotlin export changed an iOS record identity or field\n", stderr)
    exit(1)
}
guard original.periods.count == 1, original.snapshots.count == 1,
      original.exceptions.count == 1, original.overrides.count == 1,
      original.observations.count == 1, original.lifeProfile != nil,
      original.focusTasks.count == 1, original.focusSessions.count == 1,
      original.focusPlanningConfiguration != nil, original.syncedPreferences != nil,
      original.extendedSchedule != nil, original.rosterDays.count == 1 else {
    fputs("all-entity fixture is incomplete\n", stderr)
    exit(1)
}
print("iOS → Kotlin → iOS: 12 entity families, all identities and fields preserved")

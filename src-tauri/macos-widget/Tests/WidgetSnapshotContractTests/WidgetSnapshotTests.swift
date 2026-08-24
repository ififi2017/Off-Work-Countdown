import Foundation
import Testing
@testable import WidgetSnapshotContract

@Test("Swift decodes the fixture serialized by TypeScript")
func decodesTypeScriptFixture() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "widget-snapshot-v1",
            withExtension: "json",
            subdirectory: "Fixtures"
        )
    )
    let snapshot = try JSONDecoder().decode(
        WidgetSnapshot.self,
        from: Data(contentsOf: fixtureURL)
    )

    #expect(snapshot.schemaVersion == widgetSnapshotSchemaVersion)
    #expect(snapshot.locale == "en")
    #expect(snapshot.entries.map(\.phase) == [.working, .break, .working, .done])
    #expect(snapshot.entries[1].remainingEffectiveMsAtDateMs == 4_000)
    #expect(snapshot.entries[1].progressAtDate == 50)
    #expect(snapshot.entry(atMs: 7_500)?.phase == .working)
    #expect(snapshot.entry(atMs: 13_000) == nil)
}

@Test("Unknown schemas and pre-generation dates are not rendered")
func rejectsUnsupportedOrPrematureSnapshots() throws {
    let data = try #require(
        """
        {
          "schemaVersion": 2,
          "generatedAtMs": 100,
          "expiresAtMs": 200,
          "locale": "en",
          "shift": null,
          "entries": []
        }
        """.data(using: .utf8)
    )
    let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

    #expect(snapshot.entry(atMs: 150) == nil)
    #expect(snapshot.entry(atMs: 50) == nil)
}

@Test("Working entries project progress without crossing their boundary")
func projectsWorkingProgress() {
    let entry = WidgetTimelineEntry(
        dateMs: 1_000,
        validUntilMs: 6_000,
        phase: .working,
        labelKey: "widgetWorking",
        countdownKind: .workRemaining,
        countdownValueAtDateMs: 8_000,
        countdownTargetAtMs: 9_000,
        remainingEffectiveMsAtDateMs: 8_000,
        progressAtDate: 20,
        nextBoundaryAtMs: 6_000
    )

    let projected = entry.projected(atMs: 3_000)
    #expect(projected.dateMs == 3_000)
    #expect(projected.remainingEffectiveMsAtDateMs == 6_000)
    #expect(projected.countdownValueAtDateMs == 6_000)
    #expect(projected.progressAtDate == 40)

    let capped = entry.projected(atMs: 10_000)
    #expect(capped.dateMs == 6_000)
    #expect(capped.remainingEffectiveMsAtDateMs == 3_000)
    #expect(capped.progressAtDate == 70)
}

@Test("Break entries keep the progress captured by the schedule producer")
func leavesBreakProgressPaused() {
    let entry = WidgetTimelineEntry(
        dateMs: 1_000,
        validUntilMs: 6_000,
        phase: .break,
        labelKey: "lunchInProgress",
        countdownKind: .breakEnds,
        countdownValueAtDateMs: 5_000,
        countdownTargetAtMs: 6_000,
        remainingEffectiveMsAtDateMs: 8_000,
        progressAtDate: 20,
        nextBoundaryAtMs: 6_000
    )

    #expect(entry.projected(atMs: 4_000) == entry)
}

@Test("Snapshot expands working progress but not paused intervals")
func expandsPresentationTimeline() {
    let working = WidgetTimelineEntry(
        dateMs: 1_000,
        validUntilMs: 5_000,
        phase: .working,
        labelKey: "widgetWorking",
        countdownKind: .workRemaining,
        countdownValueAtDateMs: 8_000,
        countdownTargetAtMs: 9_000,
        remainingEffectiveMsAtDateMs: 8_000,
        progressAtDate: 20,
        nextBoundaryAtMs: 5_000
    )
    let paused = WidgetTimelineEntry(
        dateMs: 5_000,
        validUntilMs: 8_000,
        phase: .break,
        labelKey: "lunchInProgress",
        countdownKind: .breakEnds,
        countdownValueAtDateMs: 3_000,
        countdownTargetAtMs: 8_000,
        remainingEffectiveMsAtDateMs: 4_000,
        progressAtDate: 60,
        nextBoundaryAtMs: 8_000
    )
    let snapshot = WidgetSnapshot(
        schemaVersion: widgetSnapshotSchemaVersion,
        generatedAtMs: 1_000,
        expiresAtMs: 8_000,
        locale: "en",
        shift: nil,
        entries: [working, paused]
    )

    let entries = snapshot.presentationEntries(startingAtMs: 2_000, progressStepMs: 1_000)
    #expect(entries.map(\.dateMs) == [2_000, 3_000, 4_000, 5_000])
    #expect(entries.map(\.progressAtDate) == [30, 40, 50, 60])
    #expect(entries.last?.phase == .break)
}

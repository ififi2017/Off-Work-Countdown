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

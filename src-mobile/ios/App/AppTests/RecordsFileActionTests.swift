import Foundation
import Testing
@testable import App

@MainActor
@Suite("Records file actions")
struct RecordsFileActionTests {
    private func fixture(_ defaults: UserDefaults, records: RecordCoordinator = .inMemory()) -> RecordsActions {
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        let preferences = PreferencesStore(defaults: defaults, records: records)
        let plus = PlusEntitlement(defaults: defaults)
        let text = AppText(preferences: preferences)
        return RecordsActions(
            records: records,
            preferences: preferences,
            plus: plus,
            text: text,
            currentHours: { _ in
                ScheduleHoursConfiguration(
                    startTime: "09:00",
                    endTime: "17:00",
                    workdays: [1, 2, 3, 4, 5],
                    schedule: NativeWorkSchedule(
                        mode: "classic",
                        referenceWeekStartMs: nil,
                        referenceWeekType: nil,
                        singleWeekendWorkday: nil,
                        rotationAnchorMs: nil,
                        rotationWorkDays: nil,
                        rotationRestDays: nil
                    ),
                    breakStartTime: nil,
                    breakDurationMinutes: 0
                )
            }
        )
    }

    @Test("Import preview uses the complete archive validation path without changing live records")
    func previewValidation() async throws {
        let suite = "RecordsFilePreview.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = fixture(defaults)
        let original = actions.records.state
        let data = try await RecordArchive.exportBackup(original, exportedAt: .now, timeZone: .gmt)

        let expected = try await RecordArchive.prepareImport(data, into: original, mode: .skipErased).report
        let actual = try await actions.previewRecordsImport(data)
        #expect(actual == expected)
        #expect(actions.records.state == original)
        await #expect(throws: RecordJSONError.self) {
            try await actions.previewRecordsImport(Data("not-json".utf8))
        }
    }

    @Test("Concurrent exports keep readable names in separate temporary directories")
    func concurrentExportsAreIsolated() async throws {
        let suite = "RecordsFileExport.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = fixture(defaults)

        let exportedAt = Date(timeIntervalSince1970: 1_788_775_200)
        async let first = actions.exportRecordsFile(at: exportedAt)
        async let second = actions.exportRecordsFile(at: exportedAt)
        let urls = try await [first, second]
        defer {
            for url in urls {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }

        #expect(urls[0].lastPathComponent == "doneat-records.json")
        #expect(urls[1].lastPathComponent == "doneat-records.json")
        #expect(urls[0].deletingLastPathComponent() != urls[1].deletingLastPathComponent())
        #expect(try Data(contentsOf: urls[0]) == Data(contentsOf: urls[1]))
    }

    @Test("A local import file remains readable when security-scoped access is unnecessary")
    func readsLocalImportFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "records-import-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let expected = Data("local backup".utf8)
        try expected.write(to: url)

        let actual = try await RecordArchive.readSecurityScopedFile(url)
        #expect(actual == expected)
    }
}

import Foundation
import Testing
@testable import App

@MainActor
@Suite("Cold archive loading")
struct ColdArchiveLoadTests {
    @Test("Async runtime load publishes the decoded archive and preserves damaged-file state")
    func asyncLoad() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cold-load-\(UUID())", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "archive.json")
        let sourceSuite = "ColdLoadSource.\(UUID())"
        let sourceDefaults = try #require(UserDefaults(suiteName: sourceSuite))
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        sourceDefaults.set(true, forKey: "ios.native.onboardingComplete")
        let source = AppRuntime(defaults: sourceDefaults, records: RecordCoordinator(fileURL: file))
        #expect(source.preferences.applyPreferences {
            $0.theme = .dark
            $0.salaryAmount = "13500"
        }.synchronousResult)
        try await source.records.flush()

        let loadedSuite = "ColdLoadTarget.\(UUID())"
        let loadedDefaults = try #require(UserDefaults(suiteName: loadedSuite))
        defer { loadedDefaults.removePersistentDomain(forName: loadedSuite) }
        loadedDefaults.set(true, forKey: "ios.native.onboardingComplete")
        let loaded = try await AppRuntime.load(defaults: loadedDefaults, archiveURL: file)
        #expect(loaded.records.persistenceError == nil)
        #expect(loaded.preferences.theme == .dark)
        #expect(loaded.preferences.salaryAmount == "13500")

        try Data("damaged".utf8).write(to: file, options: .atomic)
        let damaged = try await AppRuntime.load(defaults: loadedDefaults, archiveURL: file)
        #expect(damaged.records.persistenceError == .invalidArchive)
        #expect(damaged.records.blocksWrites)
    }
}

import Foundation
import Testing
@testable import App

private actor CandidatePublishGate {
    private var armedFailure: Bool?
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func arm(failing: Bool = false) {
        armedFailure = failing
        entered = false
    }

    func pauseIfArmed() async throws {
        guard let failing = armedFailure else { return }
        armedFailure = nil
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        if failing { throw RecordPersistenceError.writeFailed }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
@Suite("Record candidate publication")
struct RecordCandidatePublicationTests {
    private func fixture() throws -> (
        store: AppRuntime, defaults: UserDefaults, suite: String,
        directory: URL, file: URL, gate: CandidatePublishGate
    ) {
        let suite = "CandidatePublication.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "candidate-publication-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "archive.json")
        let gate = CandidatePublishGate()
        let records = RecordCoordinator(fileURL: file, publishArchive: { prepared, destination in
            try await gate.pauseIfArmed()
            try await RecordArchive.publishPrepared(prepared, at: destination)
        })
        return (AppRuntime(defaults: defaults, records: records), defaults, suite, directory, file, gate)
    }

    private func candidate(from store: AppRuntime, theme: AppTheme, salary: String) throws -> RecordState {
        var candidate = store.records.state
        var preferences = try #require(candidate.syncedPreferences)
        preferences.theme = theme
        preferences.salaryAmount = salary
        candidate.syncedPreferences = preferences
        return candidate
    }

    @Test("A preference patch waits until candidate publication finishes")
    func patchWaitsForPublish() async throws {
        let fixture = try fixture()
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        try await fixture.store.records.flush()
        let candidate = try candidate(from: fixture.store, theme: .dark, salary: "candidate")
        let oldTheme = fixture.store.preferences.theme
        await fixture.gate.arm()
        let replacement = Task { try await fixture.store.records.commitRestoredState(candidate) }
        await fixture.gate.waitUntilEntered()

        let patch = fixture.store.preferences.applyPreferences { $0.salaryAmount = "patched" }
        #expect(patch.immediateResult == nil)
        #expect(fixture.store.preferences.theme == oldTheme)
        #expect(fixture.store.preferences.salaryAmount != "patched")

        await fixture.gate.release()
        try await replacement.value
        #expect(await patch.value)
        try await fixture.store.records.flush()
        #expect(fixture.store.preferences.theme == .dark)
        #expect(fixture.store.preferences.salaryAmount == "patched")
        let reopened = RecordCoordinator(fileURL: fixture.file)
        #expect(reopened.state.syncedPreferences?.theme == .dark)
        #expect(reopened.state.syncedPreferences?.salaryAmount == "patched")
    }

    @Test("A publication failure keeps old memory and releases its queued patch")
    func failedPublishKeepsOldState() async throws {
        let fixture = try fixture()
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        try await fixture.store.records.flush()
        let oldTheme = fixture.store.preferences.theme
        let candidate = try candidate(from: fixture.store, theme: oldTheme == .dark ? .light : .dark, salary: "rejected")
        await fixture.gate.arm(failing: true)
        let replacement = Task { try await fixture.store.records.commitRestoredState(candidate) }
        await fixture.gate.waitUntilEntered()
        let patch = fixture.store.preferences.applyPreferences { $0.salaryAmount = "old state patch" }
        #expect(patch.immediateResult == nil)

        await fixture.gate.release()
        await #expect(throws: RecordPersistenceError.writeFailed) { try await replacement.value }
        #expect(await patch.value)
        try await fixture.store.records.flush()
        #expect(fixture.store.preferences.theme == oldTheme)
        #expect(fixture.store.preferences.salaryAmount == "old state patch")
        let reopened = RecordCoordinator(fileURL: fixture.file)
        #expect(reopened.state.syncedPreferences?.theme == oldTheme)
        #expect(reopened.state.syncedPreferences?.salaryAmount == "old state patch")
    }

    @Test("Two candidates and an intervening patch publish in submission order")
    func consecutiveCandidatesStayFIFO() async throws {
        let fixture = try fixture()
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        try await fixture.store.records.flush()
        let firstCandidate = try candidate(from: fixture.store, theme: .dark, salary: "first")
        let secondCandidate = try candidate(from: fixture.store, theme: .light, salary: "second")
        await fixture.gate.arm()
        let first = Task { try await fixture.store.records.commitRestoredState(firstCandidate) }
        await fixture.gate.waitUntilEntered()
        let patch = fixture.store.preferences.applyPreferences { $0.salaryAmount = "between" }
        let second = Task { try await fixture.store.records.commitRestoredState(secondCandidate) }
        #expect(patch.immediateResult == nil)

        await fixture.gate.release()
        try await first.value
        #expect(await patch.value)
        try await second.value
        try await fixture.store.records.flush()
        #expect(fixture.store.preferences.theme == .light)
        #expect(fixture.store.preferences.salaryAmount == "second")
        let reopened = RecordCoordinator(fileURL: fixture.file)
        #expect(reopened.state.syncedPreferences?.theme == .light)
        #expect(reopened.state.syncedPreferences?.salaryAmount == "second")
    }
}

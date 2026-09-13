import Foundation
import Testing
@testable import App

private actor RecordAdmissionGate {
    private var armed = false
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func arm() { armed = true }

    func pauseIfArmed() async -> Bool {
        guard armed else { return false }
        armed = false
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        return true
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
@Suite("Record command admission")
struct RecordCommandAdmissionTests {
    private func fixture(
        prepare: @escaping @Sendable (RecordState, URL) async throws -> URL
    ) throws -> (AppRuntime, UserDefaults, String, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "record-command-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "RecordCommand.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        let records = RecordCoordinator(
            fileURL: directory.appending(path: "archive.json"),
            prepareArchive: prepare
        )
        return (AppRuntime(defaults: defaults, records: records), defaults, suite, directory)
    }

    @Test("Commands wait for a candidate, then patch its latest fields in FIFO order")
    func candidateSuccess() async throws {
        let gate = RecordAdmissionGate()
        let (store, defaults, suite, directory) = try fixture { state, url in
            _ = await gate.pauseIfArmed()
            return try await RecordArchive.prepare(state, for: url)
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try await store.records.flush()

        var candidate = store.records.state
        var remotePreferences = try #require(candidate.syncedPreferences)
        remotePreferences.theme = .dark
        remotePreferences.salaryAmount = "remote"
        remotePreferences.startMinutes = 7 * 60
        remotePreferences.recordsTimeZoneIdentifier = "Asia/Tokyo"
        remotePreferences.scheduleMode = .rotation
        remotePreferences.rotationWorkDays = 2
        remotePreferences.rotationRestDays = 2
        var candidateCalendar = Calendar(identifier: .gregorian)
        candidateCalendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let anchorDate = Date(timeIntervalSince1970: 1_788_739_200)
        remotePreferences.rotationAnchorMs = candidateCalendar.startOfDay(for: anchorDate)
            .timeIntervalSince1970 * 1_000
        candidate.syncedPreferences = remotePreferences
        candidate.lifeProfile = LifeProfile(
            birthYear: 1988, retirementAge: 62, editedAt: .now,
            editCount: 3, editTieBreaker: UUID()
        )

        await gate.arm()
        let replacement = Task { try await store.records.commitRestoredState(candidate) }
        await gate.waitUntilEntered()

        let first = store.preferences.applyPreferences { $0.salaryAmount = "local" }
        let second = store.preferences.applyPreferences { $0.endMinutes = $0.startMinutes + 90 }
        let schedule = store.preferences.applySetupScheduleChange(
            ScheduleFieldChange(rotationCycleDay: 3),
            at: anchorDate
        )
        let life = store.life.applyProfileEdit { $0.retirementAge = 65 }
        #expect(first.immediateResult == nil)
        #expect(second.immediateResult == nil)
        #expect(schedule.immediateResult == nil)
        #expect(life.immediateResult == nil)
        #expect(store.preferences.salaryAmount != "local")
        #expect(store.records.state.lifeProfile?.retirementAge != 65)

        await gate.release()
        try await replacement.value
        #expect(await first.value)
        #expect(await second.value)
        #expect(await schedule.value)
        #expect(await life.value)
        try await store.records.flush()

        #expect(store.preferences.theme == .dark)
        #expect(store.preferences.salaryAmount == "local")
        #expect(store.preferences.startMinutes == 7 * 60)
        #expect(store.preferences.endMinutes == 8 * 60 + 30)
        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let expectedAnchor = try #require(tokyoCalendar.date(
            byAdding: .day, value: -2, to: tokyoCalendar.startOfDay(for: anchorDate)
        ))
        #expect(store.preferences.rotationAnchorMs == expectedAnchor.timeIntervalSince1970 * 1_000)
        #expect(store.records.state.lifeProfile?.birthYear == 1988)
        #expect(store.records.state.lifeProfile?.retirementAge == 65)
    }

    @Test("A failed candidate releases queued commands onto the old state")
    func candidateFailure() async throws {
        let gate = RecordAdmissionGate()
        let (store, defaults, suite, directory) = try fixture { state, url in
            if await gate.pauseIfArmed() { throw RecordPersistenceError.writeFailed }
            return try await RecordArchive.prepare(state, for: url)
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try await store.records.flush()
        let oldTheme = store.preferences.theme
        var candidate = store.records.state
        candidate.syncedPreferences?.theme = oldTheme == .dark ? .light : .dark

        await gate.arm()
        let replacement = Task { try await store.records.commitRestoredState(candidate) }
        await gate.waitUntilEntered()
        let command = store.preferences.applyPreferences { $0.salaryAmount = "after failure" }
        #expect(command.immediateResult == nil)
        #expect(store.preferences.salaryAmount != "after failure")
        await gate.release()
        await #expect(throws: RecordPersistenceError.writeFailed) { try await replacement.value }
        #expect(await command.value)
        #expect(store.preferences.theme == oldTheme)
        #expect(store.preferences.salaryAmount == "after failure")
    }

    @Test("Ordinary and reconciliation commands are synchronous, and their writes flush")
    func immediateAndNested() async throws {
        let (store, defaults, suite, directory) = try fixture { state, url in
            try await RecordArchive.prepare(state, for: url)
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try await store.records.flush()
        let immediate = store.preferences.applyPreferences { $0.salaryAmount = "ordinary" }
        #expect(immediate.immediateResult == true)

        var nestedResult: Bool?
        store.records.onExternalStateApplied = {
            store.preferences.reloadFromArchive()
            nestedResult = store.preferences.applyPreferences {
                $0.annualBonusMonths = 2
            }.synchronousResult
        }
        var candidate = store.records.state
        candidate.syncedPreferences?.theme = .dark
        try await store.records.commitRestoredState(candidate)
        try await store.records.flush()
        #expect(nestedResult == true)
        #expect(store.preferences.theme == .dark)
        #expect(store.preferences.annualBonusMonths == 2)
    }
}

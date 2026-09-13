import Foundation
import Testing
@testable import App

private actor SceneTimerPublishGate {
    private var failure: Bool?
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func arm(failing: Bool) { failure = failing; entered = false }

    func pauseIfArmed() async throws {
        guard let failure else { return }
        self.failure = nil
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        if failure { throw RecordPersistenceError.writeFailed }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

@MainActor
@Suite("Scene timer command admission")
struct SceneTimerCommandTests {
    enum Action: String, CaseIterable, Sendable {
        case clockIn, clockOff, cancelManual

        @MainActor
        func prepare(_ store: AppRuntime, at date: Date) {
            if self == .cancelManual {
                _ = store.shifts.startCountdown(force: true, at: date).synchronousResult
            }
        }

        @MainActor
        func request(_ scene: SceneState, store: AppRuntime, at date: Date) -> RecordCommand<Bool> {
            switch self {
            case .clockIn: scene.requestClockInEarly(at: date, using: store.shifts)
            case .clockOff: scene.requestClockOffEarly(at: date, using: store.shifts)
            case .cancelManual: scene.requestCancelManualTiming(at: date, using: store.shifts)
            }
        }

        @MainActor
        func confirmationID(_ scene: SceneState, store: AppRuntime, at date: Date) -> UUID? {
            switch self {
            case .clockIn: scene.clockInConfirmationID(at: date, using: store.shifts)
            case .clockOff: scene.clockOffConfirmationID(at: date, using: store.shifts)
            case .cancelManual: scene.cancelManualTimingConfirmationID(at: date, using: store.shifts)
            }
        }
    }

    private func fixture(_ action: Action) async throws -> (
        store: AppRuntime, scene: SceneState, date: Date, candidate: RecordState,
        gate: SceneTimerPublishGate, defaults: UserDefaults, suite: String, directory: URL
    ) {
        let suite = "SceneTimerCommand.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set(true, forKey: "ios.native.automaticCountdownMigrationCompleted")
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "scene-timer-command-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let gate = SceneTimerPublishGate()
        let records = RecordCoordinator(
            fileURL: directory.appending(path: "archive.json"),
            publishArchive: { prepared, destination in
                try await gate.pauseIfArmed()
                try await RecordArchive.publishPrepared(prepared, at: destination)
            }
        )
        let store = AppRuntime(defaults: defaults, records: records)
        _ = store.preferences.applyPreferences {
            $0.scheduleMode = .classic
            $0.workdays = action == .cancelManual ? [0] : [0, 1, 2, 3, 4, 5, 6]
            $0.startMinutes = 9 * 60
            $0.endMinutes = 17 * 60
        }.synchronousResult
        let hour = action == .clockIn ? 8 : 10
        let date = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: hour)))
        action.prepare(store, at: date)
        try await records.flush()
        var candidate = records.state
        candidate.syncedPreferences?.endMinutes = 18 * 60
        if action == .cancelManual {
            candidate.syncedPreferences?.workdays = [0, 1, 2, 3, 4, 5, 6]
        }
        return (store, SceneState(), date, candidate, gate, defaults, suite, directory)
    }

    @Test("A changed candidate rejects a queued second confirmation", arguments: Action.allCases)
    func changedContext(action: Action) async throws {
        let fixture = try await fixture(action)
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        #expect(!action.request(fixture.scene, store: fixture.store, at: fixture.date).synchronousResult)
        let oldID = try #require(action.confirmationID(fixture.scene, store: fixture.store, at: fixture.date))
        await fixture.gate.arm(failing: false)
        let replacement = Task { try await fixture.store.records.commitRestoredState(fixture.candidate) }
        await fixture.gate.waitUntilEntered()
        let command = action.request(fixture.scene, store: fixture.store, at: fixture.date)
        #expect(command.immediateResult == nil)
        #expect(action.confirmationID(fixture.scene, store: fixture.store, at: fixture.date) == oldID)
        await fixture.gate.release()
        try await replacement.value
        #expect(await !command.value)

        if action == .cancelManual {
            #expect(fixture.store.session.forcedWorkdayDate == nil)
            #expect(fixture.store.preferences.applyPreferences {
                $0.workdays = [0]
            }.synchronousResult)
            #expect(fixture.store.shifts.startCountdown(force: true, at: fixture.date).synchronousResult)
        }
        #expect(!action.request(fixture.scene, store: fixture.store, at: fixture.date).synchronousResult)
        let newID = try #require(action.confirmationID(fixture.scene, store: fixture.store, at: fixture.date))
        #expect(newID != oldID)
    }

    @Test("A failed candidate lets the queued confirmation consume its matching ID", arguments: Action.allCases)
    func failedCandidate(action: Action) async throws {
        let fixture = try await fixture(action)
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        #expect(!action.request(fixture.scene, store: fixture.store, at: fixture.date).synchronousResult)
        let armedID = try #require(action.confirmationID(fixture.scene, store: fixture.store, at: fixture.date))
        await fixture.gate.arm(failing: true)
        let replacement = Task { try await fixture.store.records.commitRestoredState(fixture.candidate) }
        await fixture.gate.waitUntilEntered()
        let command = action.request(fixture.scene, store: fixture.store, at: fixture.date)
        #expect(command.immediateResult == nil)
        #expect(action.confirmationID(fixture.scene, store: fixture.store, at: fixture.date) == armedID)
        await fixture.gate.release()
        await #expect(throws: RecordPersistenceError.writeFailed) { try await replacement.value }
        #expect(await command.value)
        #expect(action.confirmationID(fixture.scene, store: fixture.store, at: fixture.date) == nil)
        try await fixture.store.records.flush()
    }
}

import Foundation
import Testing
@testable import App

private actor SceneCandidateGate {
    private var armed = false
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func arm() { armed = true }

    func pauseIfArmed() async {
        guard armed else { return }
        armed = false
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
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
@Suite("Scene command admission")
struct SceneCommandAdmissionTests {
    @Test("Queued scene commits patch the candidate without clearing newer matching drafts")
    func queuedDraftsKeepTheirIdentity() async throws {
        let suite = "SceneCommandAdmission.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set(true, forKey: "ios.native.automaticCountdownMigrationCompleted")
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "scene-command-\(UUID())", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let gate = SceneCandidateGate()
        let records = RecordCoordinator(
            fileURL: directory.appending(path: "archive.json"),
            prepareArchive: { state, url in
                await gate.pauseIfArmed()
                return try await RecordArchive.prepare(state, for: url)
            }
        )
        let store = AppRuntime(defaults: defaults, records: records)
        try await records.flush()
        var candidate = records.state
        var remote = try #require(candidate.syncedPreferences)
        remote.theme = .dark
        remote.languageOverride = "ja"
        remote.startMinutes = 9 * 60
        remote.endMinutes = 17 * 60
        remote.lunchDurationMinutes = 60
        candidate.syncedPreferences = remote

        await gate.arm()
        let replacement = Task { try await records.commitRestoredState(candidate) }
        await gate.waitUntilEntered()

        let scene = SceneState()
        let timeA = 8 * 60
        let scheduleA = ScheduleFieldChange(endMinutes: 18 * 60)
        let lunchA = ScheduleFieldChange(lunchEnabled: true, lunchDurationMinutes: 45)
        scene.setDisplayedStartMinutes(timeA, using: store.preferences)
        scene.scheduleSettingsDraft = scheduleA
        scene.lunchSettingsDraft = lunchA
        let timeCommand = scene.commitDisplayedHours(using: store.shifts)
        let scheduleCommand = scene.commitScheduleDraft(
            .schedule, decision: .nextShiftOnly, using: store.shifts
        )
        let lunchCommand = scene.commitScheduleDraft(
            .lunch, decision: .nextShiftOnly, using: store.shifts
        )
        #expect(timeCommand.immediateResult == nil)
        #expect(scheduleCommand.immediateResult == nil)
        #expect(lunchCommand.immediateResult == nil)
        #expect(store.preferences.startMinutes != timeA)

        scene.setDisplayedStartMinutes(10 * 60, using: store.preferences)
        scene.setDisplayedStartMinutes(timeA, using: store.preferences)
        scene.scheduleSettingsDraft = ScheduleFieldChange(endMinutes: 19 * 60)
        scene.scheduleSettingsDraft = scheduleA
        scene.lunchSettingsDraft = ScheduleFieldChange(lunchDurationMinutes: 30)
        scene.lunchSettingsDraft = lunchA

        await gate.release()
        try await replacement.value
        #expect(await timeCommand.value)
        #expect(await scheduleCommand.value)
        #expect(await lunchCommand.value)
        try await records.flush()

        #expect(scene.draftStartMinutes == timeA)
        #expect(scene.scheduleSettingsDraft == scheduleA)
        #expect(scene.lunchSettingsDraft == lunchA)
        #expect(store.preferences.startMinutes == timeA)
        #expect(store.preferences.endMinutes == 18 * 60)
        #expect(store.preferences.lunchEnabled)
        #expect(store.preferences.lunchDurationMinutes == 45)
        #expect(store.preferences.theme == .dark)
        #expect(store.preferences.languageOverride == "ja")
    }

    @Test("Immediate scene commits clear the exact drafts they accepted")
    func immediateDraftsClear() throws {
        let suite = "SceneCommandImmediate.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set(true, forKey: "ios.native.automaticCountdownMigrationCompleted")
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        let scene = SceneState()

        scene.setDisplayedStartMinutes(8 * 60, using: store.preferences)
        #expect(scene.commitDisplayedHours(using: store.shifts).synchronousResult)
        #expect(scene.draftStartMinutes == nil)

        scene.scheduleSettingsDraft = ScheduleFieldChange(endMinutes: 18 * 60)
        #expect(scene.commitScheduleDraft(
            .schedule, decision: .nextShiftOnly, using: store.shifts
        ).synchronousResult)
        #expect(scene.scheduleSettingsDraft.isEmpty)

        scene.lunchSettingsDraft = ScheduleFieldChange(lunchEnabled: true, lunchDurationMinutes: 45)
        #expect(scene.commitScheduleDraft(
            .lunch, decision: .nextShiftOnly, using: store.shifts
        ).synchronousResult)
        #expect(scene.lunchSettingsDraft.isEmpty)
    }
}

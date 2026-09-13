import Foundation
import Testing
@testable import App

/// Holds one write boundary, without timing assumptions or sleeps.
private actor ArchiveWriteGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pauseFirst() async {
        if !entered {
            entered = true
            enteredWaiter?.resume()
            enteredWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
        }
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
@Suite("Ordered record persistence")
struct RecordPersistenceTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "archive-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func profile(age: Int) -> LifeProfile {
        LifeProfile(birthYear: 1990, retirementAge: age, editedAt: Date(timeIntervalSince1970: 1_788_739_200), editCount: 1, editTieBreaker: UUID())
    }

    private func expectSaved(_ records: RecordCoordinator, at file: URL) throws {
        let saved = RecordCoordinator(fileURL: file)
        #expect(saved.persistenceError == nil)
        var expected = records.state
        if let written = saved.state.lifeProfile, let inMemory = expected.lifeProfile {
            #expect(abs(written.editedAt.timeIntervalSince(inMemory.editedAt)) < 0.002)
            expected.lifeProfile?.editedAt = written.editedAt
        }
        #expect(saved.state == expected)
    }

    @Test("Starting with draft hours and clocking off each save their complete operation once")
    func shiftActionBatches() async throws {
        let scene = SceneState()
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
        let suite = "ShiftActionBatch.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppRuntime(defaults: defaults, records: records)
        store.preferences.applyPreferences {
            $0.recordsTimeZoneIdentifier = "UTC"
            $0.workdays = [0, 1, 2, 3, 4, 5, 6]
            $0.scheduleMode = .classic
        }
        store.preferences.completeSetup(enableNotifications: false)
        try await records.flush()
        let start = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)
        ))
        var writes = records.archiveWriteCount
        var notifications = 0
        records.onDirty = { notifications += 1 }
        scene.setDisplayedStartMinutes(8 * 60, using: store.preferences)
        scene.setDisplayedEndMinutes(18 * 60, using: store.preferences)
        scene.startCountdown(at: start, using: store.shifts)
        #expect(store.preferences.startMinutes == 8 * 60)
        #expect(store.preferences.endMinutes == 18 * 60)
        #expect(store.session.countdownStarted)
        #expect(notifications == 0)
        try await records.flush()
        #expect(records.archiveWriteCount == writes + 1)
        #expect(notifications == 1)
        #expect(records.state.syncedPreferences?.startMinutes == 8 * 60)
        #expect(records.state.observations.contains { $0.kind == .countdownStarted })
        writes = records.archiveWriteCount
        let end = start.addingTimeInterval(3_600)
        store.shifts.clockOffEarly(at: end)
        try await records.flush()
        #expect(records.archiveWriteCount == writes + 1)
        #expect(notifications == 2)
        #expect(store.session.earlyOffAtMs == end.timeIntervalSince1970 * 1_000)
        #expect(records.state.observations.contains { $0.kind == .countdownStopped })
        #expect(records.state.overrides.contains { $0.kind == .customSegments })
    }

    @Test("Completing a Focus block commits its session and completed task together")
    func focusCompletionBatch() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
        let suite = "FocusCompletionBatch.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppRuntime(defaults: defaults, records: records)
        store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
        let start = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)
        ))
        let end = start.addingTimeInterval(1_500)
        let task = FocusTask(id: UUID(), createdAt: start, title: "Finish draft",
            estimatedPomodoros: 1, sortIndex: 0, editedAt: start, editCount: 0, editTieBreaker: UUID())
        let session = FocusSession(id: UUID(), taskID: task.id, shiftAnchorDate: start,
            startedAt: start, plannedEndAt: end, editedAt: start, editCount: 0,
            editTieBreaker: UUID(), timeZoneIdentifier: "UTC")
        records.withBatchedWrites {
            records.upsertFocusTask(task)
            records.upsertFocusSession(session)
        }
        try await records.flush()
        let writes = records.archiveWriteCount
        var notifications = 0
        records.onDirty = { notifications += 1 }
        _ = store.focus.stopFocus(reason: .completed, at: end).synchronousResult
        try await records.flush()
        #expect(records.archiveWriteCount == writes + 1)
        #expect(notifications == 1)
        #expect(records.state.focusTasks.first { $0.id == task.id }?.completedAt == end)
        #expect(records.state.focusSessions.first { $0.id == session.id }?.endReason == .completed)
    }

    @Test("Queued edits keep immediate memory feedback and flush the newest complete archive")
    func orderedEdits() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "archive.json")
        let gate = ArchiveWriteGate()
        let records = RecordCoordinator(fileURL: file, prepareArchive: { state, url in
            await gate.pauseFirst()
            return try await RecordArchive.prepare(state, for: url)
        })
        var notifications = 0
        records.onDirty = { notifications += 1 }
        records.updateLifeProfile(profile(age: 60))
        await gate.waitUntilEntered()
        records.updateLifeProfile(profile(age: 65))
        #expect(records.state.lifeProfile?.retirementAge == 65)
        #expect(records.isSaving)
        #expect(notifications == 0)
        await gate.release()
        try await records.flush()
        #expect(records.durableRevision == records.revision)
        #expect(records.archiveWriteCount == 2)
        #expect(notifications == 1)
        try expectSaved(records, at: file)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["archive.json"])
    }

    @Test("An edit queued behind a candidate applies to the published state")
    func supersededCandidate() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "archive.json")
        let gate = ArchiveWriteGate()
        let records = RecordCoordinator(fileURL: file, prepareArchive: { state, url in
            await gate.pauseFirst()
            return try await RecordArchive.prepare(state, for: url)
        })
        var candidate = RecordState()
        candidate.lifeProfile = profile(age: 70)
        let restore = Task { @MainActor in
            do { try await records.commitRestoredState(candidate); return true }
            catch { return false }
        }
        await gate.waitUntilEntered()
        let edit = records.submitCommand {
            records.updateLifeProfile(profile(age: 62))
            return true
        }
        #expect(edit.immediateResult == nil)
        #expect(records.state.lifeProfile == nil)
        await gate.release()
        #expect(await restore.value)
        #expect(await edit.value)
        try await records.flush()
        #expect(records.state.lifeProfile?.retirementAge == 62)
        try expectSaved(records, at: file)
        #expect(records.archiveWriteCount == 2)
        #expect(records.persistenceError == nil)
    }

    @Test("A disk replacement can suspend while the main actor accepts the next edit")
    func editsDuringPublication() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "archive.json")
        let gate = ArchiveWriteGate()
        let records = RecordCoordinator(fileURL: file, publishArchive: { prepared, file in
            await gate.pauseFirst()
            try await RecordArchive.publishPrepared(prepared, at: file)
        })
        records.updateLifeProfile(profile(age: 60))
        await gate.waitUntilEntered()
        records.updateLifeProfile(profile(age: 66))
        #expect(records.state.lifeProfile?.retirementAge == 66)
        #expect(records.archiveWriteCount == 0)
        await gate.release()
        try await records.flush()
        #expect(records.archiveWriteCount == 2)
        try expectSaved(records, at: file)
    }

    @Test("A sync receipt and an edit arriving during its save both reach disk")
    func editDuringSyncCommit() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "archive.json")
        let gate = ArchiveWriteGate()
        let records = RecordCoordinator(fileURL: file, prepareArchive: { state, url in
            await gate.pauseFirst()
            return try await RecordArchive.prepare(state, for: url)
        })
        var sync = records.state.sync
        sync.engineState = Data("test-receipt".utf8)
        let receipt = Task { @MainActor in
            await records.commitSyncState { current, _ in
                current.engineState = sync.engineState
            }
        }
        await gate.waitUntilEntered()
        let edit = records.submitCommand { records.updateLifeProfile(profile(age: 63)) }
        #expect(edit.immediateResult == nil)
        await gate.release()
        #expect(await receipt.value)
        await edit.value
        try await records.flush()
        try expectSaved(records, at: file)
        #expect(records.state.sync.engineState == sync.engineState)
        #expect(records.state.lifeProfile?.retirementAge == 63)
        #expect(records.persistenceError == nil)
    }

    @Test("A batch writes once and a repeated preferences submission writes nothing")
    func noOpAndBatch() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
        let suite = "batch-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppRuntime(defaults: defaults, records: records)
        store.preferences.completeSetup(enableNotifications: false)
        try await records.flush()
        let initialCount = records.archiveWriteCount
        let original = try #require(records.state.syncedPreferences)
        var notifications = 0
        records.onDirty = { notifications += 1 }
        records.upsertSyncedPreferences(original)
        try await records.flush()
        #expect(records.archiveWriteCount == initialCount)
        #expect(notifications == 0)
        records.withBatchedWrites {
            var changed = original
            changed.startMinutes += 10
            records.upsertSyncedPreferences(changed)
            records.updateLifeProfile(profile(age: 60))
        }
        try await records.flush()
        #expect(records.archiveWriteCount == initialCount + 1)
        #expect(notifications == 1)
        _ = store
    }

    @Test("A candidate rejected by the cold loader cannot replace a valid archive")
    func invalidCandidatePreservesArchive() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "archive.json")
        let records = RecordCoordinator(fileURL: file)
        records.updateLifeProfile(profile(age: 60))
        try await records.flush()
        let original = records.state
        let originalData = try Data(contentsOf: file)
        var candidate = original
        candidate.lifeProfile = profile(age: 70)
        candidate.overrides.append(DayOverride(
            dayKey: "2026-09-06", shiftAnchorDate: Date(timeIntervalSince1970: 1_788_739_200),
            kind: .customSegments,
            segments: [.init(startAtMs: 2_000, endAtMs: 1_000)],
            timeZoneIdentifier: "UTC"
        ))
        await #expect(throws: RecordPersistenceError.writeFailed) {
            try await records.commitRestoredState(candidate)
        }
        #expect(records.state == original)
        #expect(try Data(contentsOf: file) == originalData)
        #expect(records.archiveWriteCount == 1)
    }

    @Test("Flush retries an unchanged edit after storage becomes writable")
    func failureRetry() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appending(path: "missing")
        let file = missing.appending(path: "archive.json")
        let records = RecordCoordinator(fileURL: file)
        records.updateLifeProfile(profile(age: 61))
        await #expect(throws: RecordPersistenceError.writeFailed) { try await records.flush() }
        #expect(records.state.lifeProfile?.retirementAge == 61)
        #expect(records.durableRevision != records.revision)
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        try await records.flush()
        #expect(records.durableRevision == records.revision)
        #expect(records.persistenceError == nil)
        try expectSaved(records, at: file)
    }

    @Test("A failed remote batch reconciles consumers once after a successful retry")
    func failedRemoteBatch() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = RecordCoordinator(fileURL: root.appending(path: "missing/archive.json"))
        var reconciliations = 0
        records.onRemoteBatchApplied = { reconciliations += 1 }
        records.onExternalStateApplied = { reconciliations += 1 }
        await #expect(throws: RecordPersistenceError.writeFailed) {
            try await records.persistRemoteBatch()
        }
        #expect(reconciliations == 0)
        #expect(records.persistenceError == .writeFailed)
        try FileManager.default.createDirectory(at: root.appending(path: "missing"), withIntermediateDirectories: true)
        try await records.flush()
        #expect(reconciliations == 2)
        try await records.flush()
        #expect(reconciliations == 2)
    }

}

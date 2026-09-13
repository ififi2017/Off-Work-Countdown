import Foundation
import Testing
@testable import App

private actor ExternalReconciliationWriteGate {
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
@Test func externalScheduleReplacementDropsLocalTimerAdjustmentsWithoutRewritingArchive() async throws {
    let suite = "ExternalShiftSessionReconciliationTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let records = RecordCoordinator.inMemory()
    let runtime = AppRuntime(defaults: defaults, records: records)
    runtime.preferences.onboardingComplete = true
    #expect(runtime.preferences.applyPreferences { $0.salaryEnabled.toggle() }.synchronousResult)

    let calendar = runtime.preferences.recordsCalendar
    let now = try #require(calendar.date(from: DateComponents(
        year: 2026, month: 9, day: 14, hour: 10
    )))
    #expect(runtime.shifts.startCountdown(at: now).synchronousResult)
    #expect(runtime.shifts.applyOvertime(
        date: now.addingTimeInterval(9 * 3_600), declaredAt: now
    ).synchronousResult)
    runtime.session.earlyStartAtMs = now.timeIntervalSince1970 * 1_000
    runtime.session.earlyStartUntilMs = now.addingTimeInterval(86_400).timeIntervalSince1970 * 1_000
    runtime.session.todayOverride = TodayScheduleOverride(
        startMinutes: runtime.preferences.startMinutes,
        endMinutes: runtime.preferences.endMinutes,
        workdays: Array(runtime.preferences.workdays).sorted(),
        scheduleMode: runtime.preferences.scheduleMode.rawValue,
        lunchEnabled: runtime.preferences.lunchEnabled,
        lunchStartMinutes: runtime.preferences.lunchStartMinutes,
        lunchDurationMinutes: runtime.preferences.lunchDurationMinutes,
        alternatingWeekType: runtime.preferences.alternatingWeekType.rawValue,
        alternatingWeekendWorkday: runtime.preferences.alternatingWeekendWorkday,
        alternatingReferenceWeekStartMs: runtime.preferences.alternatingReferenceWeekStartMs,
        rotationWorkDays: runtime.preferences.rotationWorkDays,
        rotationRestDays: runtime.preferences.rotationRestDays,
        rotationAnchorMs: runtime.preferences.rotationAnchorMs,
        untilMs: now.addingTimeInterval(86_400).timeIntervalSince1970 * 1_000
    )
    let previousSessionID = runtime.session.sessionID

    var replacement = records.state
    var imported = try #require(replacement.syncedPreferences)
    imported.startMinutes += 30
    imported.editedAtMs += 1
    imported.editCount += 1
    replacement.syncedPreferences = imported

    try await records.commitRestoredState(replacement)

    #expect(runtime.preferences.startMinutes == imported.startMinutes)
    #expect(runtime.session.countdownStarted)
    #expect(runtime.session.sessionID != previousSessionID)
    #expect(runtime.session.overtimeEndAtMs == nil)
    #expect(runtime.session.earlyOffAtMs == nil)
    #expect(runtime.session.earlyStartAtMs == nil)
    #expect(runtime.session.todayOverride == nil)
    #expect(records.state.syncedPreferences == imported)
}

@MainActor
@Test func ordinaryDurableCallbackCanArriveWhileCandidateCommandIsPending() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "external-reconcile-race-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "archive.json")
    let gate = ExternalReconciliationWriteGate()
    let records = RecordCoordinator(fileURL: file, publishArchive: { prepared, destination in
        await gate.pauseIfArmed()
        try await RecordArchive.publishPrepared(prepared, at: destination)
    })
    try await records.flush()

    var callbackWasAdmitted: [Bool] = []
    let derivedProfile = LifeProfile(
        birthYear: 1990,
        retirementAge: 60,
        bornOn: .yearOnly(1990),
        workStartedPartial: .yearOnly(2012),
        retirementOn: .yearOnly(2050),
        workHistoryMode: .rough,
        roughCurrentSalary: nil,
        employmentPeriods: [],
        editedAt: .now,
        editCount: 1,
        editTieBreaker: UUID()
    )
    records.onExternalStateApplied = {
        let nested = records.submitCommand {
            records.updateLifeProfile(derivedProfile)
            return true
        }
        callbackWasAdmitted.append(nested.immediateResult != nil)
    }

    await gate.arm()
    let remoteWrite = Task { try await records.persistRemoteBatch([], deletedRecordNames: []) }
    await gate.waitUntilEntered()
    var builderSawDerivedWrite = false
    let replacement = Task {
        try await records.commitRestoredState { latest in
            builderSawDerivedWrite = latest.lifeProfile != nil
            return (latest, ())
        }
    }
    await Task.yield()
    let behindCandidate = records.submitCommand { true }
    #expect(behindCandidate.immediateResult == nil)

    await gate.release()
    try await remoteWrite.value
    try await replacement.value
    _ = await behindCandidate.value

    #expect(callbackWasAdmitted == [true, true])
    #expect(builderSawDerivedWrite)
    #expect(records.state.lifeProfile != nil)
}

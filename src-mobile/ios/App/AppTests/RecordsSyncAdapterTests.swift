import Foundation
import Testing
@testable import App

@MainActor
@Test("Revision stamp winner is editCount, then its deterministic tie-breaker")
func syncRevisionStampIsDeterministic() {
    #expect(RecordsSyncConflict.localWins(localCount: 3, localTie: "a", serverCount: 2, serverTie: "z"))
    #expect(!RecordsSyncConflict.localWins(localCount: 2, localTie: "z", serverCount: 3, serverTie: "a"))
    #expect(RecordsSyncConflict.localWins(localCount: 2, localTie: "b", serverCount: 2, serverTie: "a"))
}

@MainActor
@Test("Automatic conflict handling uses revision count, then the later user edit")
func automaticConflictWinnerPrefersNewestEdit() {
    #expect(
        RecordsSyncConflict.automaticallyPreferredWinner(
            localCount: 3,
            localEditedAtMs: 10,
            incomingCount: 2,
            incomingEditedAtMs: 20
        ) == .local
    )
    #expect(
        RecordsSyncConflict.automaticallyPreferredWinner(
            localCount: 2,
            localEditedAtMs: 10,
            incomingCount: 2,
            incomingEditedAtMs: 20
        ) == .incoming
    )
    #expect(
        RecordsSyncConflict.automaticallyPreferredWinner(
            localCount: 2,
            localEditedAtMs: 20,
            incomingCount: 2,
            incomingEditedAtMs: 20
        ) == nil
    )
}

@MainActor
@Test("Legacy conflict copies decode as a neutral current-versus-other choice")
func legacyConflictCopyRemainsReadable() throws {
    let data = Data(#"{"entityType":"dayOverride","logicalKey":"2026-08-24","payload":"","lostAtMs":0}"#.utf8)
    let copy = try JSONDecoder().decode(SyncConflictCopy.self, from: data)
    #expect(copy.currentWinner == .unknown)
    #expect(copy.localPayload == nil)
    #expect(copy.incomingPayload == nil)
    #expect(copy.effectiveAlternatePayload == Data())
}

@MainActor
@Test("Conflict field choices keep composite day values atomic")
func conflictFieldChoicesExpandCompositeValues() {
    #expect(
        RecordsConflictFieldSelection.expanded(["segments"], for: .dayOverride)
            == Set(["kind", "segments"])
    )
    #expect(
        RecordsConflictFieldSelection.expanded(["effect"], for: .calendarException)
            == Set(["effect", "isCleared"])
    )
}

@MainActor
@Test("A higher fence drops old dirty rows so they cannot upload")
func higherFenceDiscardsLocalOutbox() {
    var state = SyncLocalState.empty
    state.generation = 2
    RecordsSyncOutbox.markDirty(
        &state,
        type: .dayOverride,
        key: "2026-08-26",
        editCount: 1,
        editTieBreaker: UUID()
    )
    #expect(!RecordsSyncOutbox.pending(state).isEmpty)
    #expect(RecordsSyncOutbox.applyHigherFence(&state, fence: 3))
    #expect(RecordsSyncOutbox.pending(state).isEmpty)
    #expect(state.generation == 3)
}

@MainActor
@Test("CloudKit outbox batches stay under the server limit and isolate erasures")
func cloudOutboxBatchingIsBounded() {
    var state = SyncLocalState.empty
    for index in 0..<251 {
        RecordsSyncOutbox.markDirty(
            &state,
            type: .dayOverride,
            key: String(format: "%03d", index),
            editCount: 1,
            editTieBreaker: UUID()
        )
    }
    #expect(RecordsSyncOutbox.nextBatch(state).count == 250)

    RecordsSyncOutbox.markDirty(
        &state,
        type: .calendarException,
        key: "000",
        editCount: 2,
        editTieBreaker: UUID(),
        erase: true
    )
    let eraseBatch = RecordsSyncOutbox.nextBatch(state)
    #expect(eraseBatch.count == 1)
    #expect(eraseBatch[0].pendingErase)
}

@MainActor
@Test("Low-generation records are discarded")
func lowGenerationIsDropped() {
    #expect(RecordsSyncGeneration.shouldDiscard(recordGeneration: 2, fence: 3))
    #expect(!RecordsSyncGeneration.shouldDiscard(recordGeneration: 3, fence: 3))
    #expect(
        RecordsSyncGeneration.staleZones(named: ["owc-records.1", "owc-records.4", "owc-control"], fence: 4)
            == ["owc-records.1"]
    )
}

@MainActor
@Test("Life profile merges field-by-field against the last known baseline")
func lifeProfileMergesByField() {
    let baseline = LifeProfile(
        birthYear: 1990,
        retirementAge: 60,
        averageSleepHours: 8,
        editedAt: .distantPast,
        editCount: 1,
        editTieBreaker: UUID()
    )
    var local = baseline
    local.retirementAge = 62
    local.editCount = 2
    var server = baseline
    server.averageSleepHours = 7
    server.editCount = 2
    let merged = RecordsSyncConflict.mergeLifeProfile(local: local, server: server, baseline: baseline)
    #expect(merged.retirementAge == 62)
    #expect(merged.averageSleepHours == 7)
}

@MainActor
@Test("Revision-only payload differences are not user-visible conflicts")
func syncConflictIgnoresRevisionOnlyPayloadDifferences() {
    let local = Data(#"{"calendarIdentifier":"gregorian","createdAtMs":1788245646901.092,"editCount":2,"editTieBreaker":"local","editedAtMs":1788245646901.092,"startsOn":"2026-09-01","timeZoneIdentifier":"Asia/Shanghai"}"#.utf8)
    let server = Data(#"{"timeZoneIdentifier":"Asia/Shanghai","startsOn":"2026-09-01","editedAtMs":1788245650000,"editTieBreaker":"server","editCount":3,"createdAtMs":1788245646901.092,"calendarIdentifier":"gregorian"}"#.utf8)
    let changed = Data(#"{"calendarIdentifier":"gregorian","createdAtMs":1788245646901.092,"editCount":3,"editTieBreaker":"server","editedAtMs":1788245650000,"startsOn":"2026-09-02","timeZoneIdentifier":"Asia/Shanghai"}"#.utf8)

    #expect(RecordsSyncConflict.payloadsHaveSameBusinessContent(local, server))
    #expect(!RecordsSyncConflict.payloadsHaveSameBusinessContent(local, changed))
}

@MainActor
@Test("Disjoint edits to one day merge without asking the user")
func syncConflictAutomaticallyMergesDisjointDayFields() throws {
    let baseline = Data(#"{"dayKey":"2026-09-01","editCount":1,"editTieBreaker":"base","editedAtMs":1,"kind":"customSegments","note":"Original","segments":[{"endAtMs":20,"startAtMs":10}],"timeZoneIdentifier":"Asia/Shanghai"}"#.utf8)
    let local = Data(#"{"dayKey":"2026-09-01","editCount":2,"editTieBreaker":"local","editedAtMs":2,"kind":"customSegments","note":"Local note","segments":[{"endAtMs":20,"startAtMs":10}],"timeZoneIdentifier":"Asia/Shanghai"}"#.utf8)
    let server = Data(#"{"dayKey":"2026-09-01","editCount":2,"editTieBreaker":"server","editedAtMs":3,"kind":"customSegments","note":"Original","segments":[{"endAtMs":30,"startAtMs":10}],"timeZoneIdentifier":"Asia/Shanghai"}"#.utf8)

    let merged = try #require(
        RecordsSyncConflict.automaticallyMergedPayload(
            local: local,
            server: server,
            baseline: baseline,
            type: .dayOverride
        )
    )
    let values = try #require(JSONSerialization.jsonObject(with: merged) as? [String: Any])
    #expect(values["note"] as? String == "Local note")
    let segments = try #require(values["segments"] as? [[String: Any]])
    #expect(segments.first?["endAtMs"] as? Int == 30)
}

@MainActor
@Test("Focus planning merges separate days and timer fields")
func focusPlanningConfigurationMergesWithoutConflictUI() {
    let baseline = focusPlanningConfiguration(editCount: 1)
    var local = baseline
    local.planning.plans["2026-09-01"] = FocusDayPlan(
        dayKey: "2026-09-01",
        shiftStartAtMs: 1,
        assignments: [],
        appliedTemplateID: nil
    )
    local.timerSettings.focusMinutes = 40
    local.editCount = 2
    local.editTieBreaker = syncTestID(2)

    var server = baseline
    server.planning.plans["2026-09-02"] = FocusDayPlan(
        dayKey: "2026-09-02",
        shiftStartAtMs: 2,
        assignments: [],
        appliedTemplateID: nil
    )
    server.timerSettings.shortBreakMinutes = 8
    server.editCount = 2
    server.editTieBreaker = syncTestID(3)

    let merged = RecordsSyncConflict.mergeFocusPlanningConfiguration(
        local: local,
        server: server,
        baseline: baseline
    )
    #expect(merged.planning.plans.keys.sorted() == ["2026-09-01", "2026-09-02"])
    #expect(merged.timerSettings.focusMinutes == 40)
    #expect(merged.timerSettings.shortBreakMinutes == 8)
    #expect(merged.editCount == 3)
}

@MainActor
@Test("Observation sync uses its revision stamp, and erased rows are reasserted")
func syncApplyUsesObservationRevisionAndProtectsErased() {
    #expect(
        RecordsSyncApply.action(
            type: .workObservation,
            locallyErased: false,
            localCount: 9,
            localTie: "z",
            serverCount: 8,
            serverTie: "a"
        ) == .keepLocalAndCopyServer
    )
    #expect(
        RecordsSyncApply.action(
            type: .dayOverride,
            locallyErased: true,
            localCount: nil,
            localTie: nil,
            serverCount: 2,
            serverTie: "b"
        ) == .reassertErase
    )
    #expect(
        RecordsSyncApply.action(
            type: .dayOverride,
            locallyErased: false,
            localCount: 3,
            localTie: "b",
            serverCount: 2,
            serverTie: "z"
        ) == .keepLocalAndCopyServer
    )
}

@MainActor
@Test("Cloud payloads preserve observation revision stamps")
func cloudPayloadPreservesObservationRevisionStamp() throws {
    let eventID = UUID()
    let tie = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_788_000_000)
    let observation = WorkObservation(
        eventID: eventID,
        shiftAnchorDate: occurredAt,
        occurredAt: occurredAt,
        kind: .countdownStopped,
        valueData: Data("remote".utf8),
        scheduleSnapshotID: UUID(),
        timeZoneIdentifier: "UTC",
        editedAt: occurredAt.addingTimeInterval(30),
        editCount: 6,
        editTieBreaker: tie
    )
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let payload = try #require(RecordsSyncPayload.encode(.observation(observation), calendar: calendar))
    #expect(
        RecordsSyncPayload.editStamp(from: payload, type: .workObservation, calendar: calendar)?.0 == 6
    )
    #expect(
        RecordsSyncPayload.editStamp(from: payload, type: .workObservation, calendar: calendar)?.1 == tie.uuidString
    )
    let restored = try #require(
        RecordsSyncPayload.incoming(from: payload, type: .workObservation, calendar: calendar)
    )
    guard case let .observation(value) = restored else {
        Issue.record("Expected a work observation payload")
        return
    }
    #expect(value.editCount == 6)
    #expect(value.editTieBreaker == tie)
}

@MainActor
@Test("Sync startup requires the same known Apple Account")
func syncStartupRequiresKnownAccount() {
    #expect(
        RecordsSyncCloudPrerequisites.acceptsAccount(
            storedAccountID: "account-a",
            currentAccountID: "account-a",
            mayAdoptCurrentAccount: false
        )
    )
    #expect(
        !RecordsSyncCloudPrerequisites.acceptsAccount(
            storedAccountID: nil,
            currentAccountID: "account-a",
            mayAdoptCurrentAccount: false
        )
    )
    #expect(
        !RecordsSyncCloudPrerequisites.acceptsAccount(
            storedAccountID: "account-a",
            currentAccountID: "account-b",
            mayAdoptCurrentAccount: true
        )
    )
    #expect(
        RecordsSyncCloudPrerequisites.acceptsAccount(
            storedAccountID: nil,
            currentAccountID: "account-a",
            mayAdoptCurrentAccount: true
        )
    )
}

@MainActor
@Test("Sync startup rejects missing or regressed fences")
func syncStartupRequiresCurrentFence() {
    #expect(RecordsSyncCloudPrerequisites.canResume(localGeneration: 2, remoteFence: 2))
    #expect(RecordsSyncCloudPrerequisites.canResume(localGeneration: 2, remoteFence: 3))
    #expect(!RecordsSyncCloudPrerequisites.canResume(localGeneration: 2, remoteFence: 0))
    #expect(!RecordsSyncCloudPrerequisites.canResume(localGeneration: 3, remoteFence: 2))
}

@MainActor
@Test("Restore requires the current generation data zone")
func restoreRequiresCurrentGenerationZone() {
    #expect(
        RecordsSyncCloudPrerequisites.hasRestorableData(
            fence: 3,
            zoneNames: ["owc-control", "owc-records.3"]
        )
    )
    #expect(
        !RecordsSyncCloudPrerequisites.hasRestorableData(
            fence: 3,
            zoneNames: ["owc-control", "owc-records.2"]
        )
    )
    #expect(
        !RecordsSyncCloudPrerequisites.hasRestorableData(
            fence: 0,
            zoneNames: ["owc-records.0"]
        )
    )
}

@MainActor
@Test("Dirty scan keeps an edit that was saved before enqueue")
func dirtyScanKeepsUnsentEdit() {
    var state = SyncLocalState.empty
    let tie = UUID()
    RecordsSyncOutbox.markDirty(
        &state,
        type: .dayOverride,
        key: "2026-08-26",
        editCount: 4,
        editTieBreaker: tie
    )
    let pending = RecordsSyncOutbox.pending(state)
    #expect(pending.count == 1)
    #expect(pending[0].recordName == "day.2026-08-26")
    #expect(pending[0].editCount == 4)
}

@MainActor
@Test("A save acknowledgement does not clear a newer local edit")
func sentSaveDoesNotClearNewerEdit() {
    var row = SyncAdapterRow(
        entityType: .dayOverride,
        logicalKey: "2026-08-26",
        recordName: "day.2026-08-26",
        dirty: true,
        generation: 1,
        lastKnownRecord: nil,
        lastKnownPayload: nil,
        pendingErase: false,
        editCount: 5,
        editTieBreaker: "n+1"
    )
    #expect(!RecordsSyncSent.shouldClearSave(row: row, savedCount: 4, savedTie: "n"))
    row.editCount = 4
    row.editTieBreaker = "n"
    #expect(RecordsSyncSent.shouldClearSave(row: row, savedCount: 4, savedTie: "n"))
}

@MainActor
@Test("An erase pair confirms only after the data delete and the erased save")
func erasePairNeedsBothHalves() {
    let row = SyncAdapterRow(
        entityType: .dayOverride,
        logicalKey: "2026-08-26",
        recordName: "day.2026-08-26",
        dirty: true,
        generation: 1,
        lastKnownRecord: nil,
        lastKnownPayload: nil,
        pendingErase: true,
        editCount: 0,
        editTieBreaker: ""
    )
    let erased = RecordsSyncIdentity.erasedName(type: .dayOverride, key: "2026-08-26")
    #expect(!RecordsSyncSent.shouldClearErase(row: row, savedNames: [erased], deletedNames: []))
    #expect(!RecordsSyncSent.shouldClearErase(row: row, savedNames: [], deletedNames: ["day.2026-08-26"]))
    #expect(RecordsSyncSent.shouldClearErase(row: row, savedNames: [erased], deletedNames: ["day.2026-08-26"]))
}

@MainActor
@Test("Same-field LifeProfile conflicts increment the merge version")
func lifeProfileConflictIncrementsVersion() {
    let baseline = LifeProfile(
        birthYear: 1990,
        retirementAge: 60,
        editedAt: .distantPast,
        editCount: 1,
        editTieBreaker: UUID()
    )
    var local = baseline
    local.retirementAge = 62
    local.editCount = 2
    var server = baseline
    server.retirementAge = 65
    server.editCount = 2
    let merged = RecordsSyncConflict.mergeLifeProfile(local: local, server: server, baseline: baseline)
    #expect(merged.editCount == 3)
    #expect(merged.retirementAge == 62 || merged.retirementAge == 65)
}

@MainActor
@Test("A later same-revision life edit wins the overlapping field")
func laterLifeProfileEditWinsOverlappingField() {
    let baseline = LifeProfile(
        birthYear: 1990,
        retirementAge: 60,
        editedAt: Date(timeIntervalSince1970: 1),
        editCount: 1,
        editTieBreaker: syncTestID(70)
    )
    var local = baseline
    local.retirementAge = 62
    local.editedAt = Date(timeIntervalSince1970: 2)
    local.editCount = 2
    local.editTieBreaker = syncTestID(99)
    var server = baseline
    server.retirementAge = 65
    server.editedAt = Date(timeIntervalSince1970: 3)
    server.editCount = 2
    server.editTieBreaker = syncTestID(1)

    let merged = RecordsSyncConflict.mergeLifeProfile(local: local, server: server, baseline: baseline)
    #expect(merged.retirementAge == 65)
    #expect(merged.editCount == 3)
}

@MainActor
@Test("A higher fence discards local records, conflicts, and engine state")
func higherFenceDiscardsLocalArchive() {
    var archive = RecordState()
    archive.overrides = [
        DayOverride(
            dayKey: "2026-08-26",
            shiftAnchorDate: Date(timeIntervalSince1970: 0),
            kind: .customSegments,
            segments: []
        )
    ]
    archive.sync.generation = 1
    archive.sync.engineState = Data("engine".utf8)
    archive.sync.conflicts = [
        SyncConflictCopy(entityType: .dayOverride, logicalKey: "2026-08-26", payload: Data(), lostAtMs: 0)
    ]
    RecordsSyncOutbox.markDirty(
        &archive.sync,
        type: .dayOverride,
        key: "2026-08-26",
        editCount: 1,
        editTieBreaker: UUID()
    )
    #expect(RecordsSyncOutbox.discardLocalArchive(&archive, fence: 4))
    #expect(archive.overrides.isEmpty)
    #expect(archive.sync.rows.isEmpty)
    #expect(archive.sync.conflicts.isEmpty)
    #expect(archive.sync.engineState == nil)
    #expect(archive.sync.generation == 4)
}

@MainActor
@Test("Rest and clear writes neutralize a leftover hours override")
func dayLayersClearOverrideWhenWritingException() {
    #expect(DayRecordLayers.plan(for: .customHours) == .overrideOnly(.customSegments))
    #expect(DayRecordLayers.plan(for: .leave) == .overrideOnly(.notWorking))
    #expect(
        DayRecordLayers.plan(for: .rest)
            == .exception(override: .cleared, effect: .rest, exceptionCleared: false)
    )
    #expect(
        DayRecordLayers.plan(for: .clear)
            == .exception(override: .cleared, effect: .rest, exceptionCleared: true)
    )
}

@MainActor
private func focusPlanningConfiguration(editCount: Int) -> FocusPlanningConfiguration {
    FocusPlanningConfiguration(
        planning: FocusPlanningState(),
        timerSettings: .default,
        editedAt: Date(timeIntervalSince1970: Double(editCount)),
        editCount: editCount,
        editTieBreaker: syncTestID(editCount)
    )
}

@MainActor
private func syncTestID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}

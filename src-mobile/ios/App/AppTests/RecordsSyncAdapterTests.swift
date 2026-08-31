import Foundation
import Testing
@testable import App

@MainActor
@Test("Conflict winner is editCount, then tie-breaker, never the wall clock")
func syncConflictIgnoresClock() {
    #expect(RecordsSyncConflict.localWins(localCount: 3, localTie: "a", serverCount: 2, serverTie: "z"))
    #expect(!RecordsSyncConflict.localWins(localCount: 2, localTie: "z", serverCount: 3, serverTie: "a"))
    #expect(RecordsSyncConflict.localWins(localCount: 2, localTie: "b", serverCount: 2, serverTie: "a"))
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
@Test("Observations never overwrite, and erased rows stay gone")
func syncApplyProtectsObservationsAndErased() {
    #expect(
        RecordsSyncApply.action(
            type: .workObservation,
            locallyErased: false,
            localCount: 1,
            localTie: "a",
            serverCount: 9,
            serverTie: "z"
        ) == .ignore
    )
    #expect(
        RecordsSyncApply.action(
            type: .dayOverride,
            locallyErased: true,
            localCount: nil,
            localTie: nil,
            serverCount: 2,
            serverTie: "b"
        ) == .ignore
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

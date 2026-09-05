import Foundation
import Testing
@testable import App

@MainActor
@Test("Missing server record recovery preserves the local edit and revival intent")
func missingServerRecordPreservesOutbox() {
    var state = SyncLocalState.empty
    RecordsSyncOutbox.markDirty(
        &state, type: .focusTask, key: "test", editCount: 7,
        editTieBreaker: UUID(), revokeErase: true
    )
    let name = RecordsSyncIdentity.recordName(type: .focusTask, key: "test")
    let fields = Data([1])
    state.rows[name]!.lastKnownRecord = fields
    state.rows[name]!.lastKnownPayload = Data([2])
    var expected = state.rows[name]!
    expected.lastKnownRecord = nil
    #expect(RecordsSyncOutbox.forgetMissingRecord(
        &state, name: name, generation: state.generation, expectedSystemFields: fields
    ))
    #expect(state.rows[name] == expected)
    #expect(RecordsSyncOutbox.pending(state).count == 1)
}

@MainActor
@Test("An old failure cannot erase a newer receipt or cross a deletion fence")
func missingServerRecordRejectsStaleFailure() {
    var state = SyncLocalState.empty
    RecordsSyncOutbox.markDirty(
        &state, type: .focusTask, key: "test", editCount: 2, editTieBreaker: UUID()
    )
    let name = RecordsSyncIdentity.recordName(type: .focusTask, key: "test")
    state.rows[name]!.lastKnownRecord = Data([2])
    let expected = state.rows[name]
    #expect(!RecordsSyncOutbox.forgetMissingRecord(
        &state, name: name, generation: state.generation, expectedSystemFields: Data([1])
    ))
    #expect(!RecordsSyncOutbox.forgetMissingRecord(
        &state, name: name, generation: state.generation - 1, expectedSystemFields: Data([2])
    ))
    #expect(state.rows[name] == expected)
}

@MainActor
@Test("A missing deletion marker is recreated without reviving the data row")
func missingDeletionMarkerPreservesErase() {
    var state = SyncLocalState.empty
    RecordsSyncOutbox.markDirty(
        &state, type: .focusTask, key: "test", editCount: 3, editTieBreaker: UUID(), erase: true
    )
    let name = RecordsSyncIdentity.recordName(type: .focusTask, key: "test")
    let erasedName = RecordsSyncIdentity.erasedName(type: .focusTask, key: "test")
    state.rows[name]!.lastKnownRecord = Data([1])
    state.rows[name]!.lastKnownErasedRecord = Data([2])
    var expected = state.rows[name]!
    expected.lastKnownErasedRecord = nil
    #expect(RecordsSyncOutbox.forgetMissingRecord(
        &state, name: erasedName, generation: state.generation, expectedSystemFields: Data([2])
    ))
    #expect(state.rows[name] == expected)
}

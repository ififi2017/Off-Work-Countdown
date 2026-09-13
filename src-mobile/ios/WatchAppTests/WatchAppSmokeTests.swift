import Testing
@testable import DoneAtWatchApp

@Test func watchContractVersionIsAvailable() {
    #expect(WatchSnapshotContract.schemaVersion == 1)
}

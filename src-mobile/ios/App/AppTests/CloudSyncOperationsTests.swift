import Testing
@testable import App

@MainActor
@Suite("Cloud sync operation admission")
struct CloudSyncOperationsTests {
    @Test("Adjacent identical requests share one operation")
    func adjacentIdenticalRequestsCoalesce() async {
        let operations = CloudSyncOperations()
        let probe = CloudSyncOperationProbe()

        let first = operations.enqueue(.enable(authorized: true)) {
            await probe.suspendRecording("enable")
        }
        await probe.waitUntilSuspended()
        let duplicate = operations.enqueue(.enable(authorized: true)) {
            probe.record("duplicate")
        }

        probe.release()
        await first.value
        await duplicate.value

        #expect(probe.events == ["enable"])
    }

    @Test("Adjacent restore requests share one operation")
    func adjacentRestoreRequestsCoalesce() async {
        let operations = CloudSyncOperations()
        let probe = CloudSyncOperationProbe()

        let first = operations.enqueue(.restore) {
            await probe.suspendRecording("restore")
        }
        await probe.waitUntilSuspended()
        let duplicate = operations.enqueue(.restore) {
            probe.record("duplicate")
        }

        probe.release()
        await first.value
        await duplicate.value

        #expect(probe.events == ["restore"])
    }

    @Test("A different operation fences a later enable")
    func differentOperationBreaksCoalescing() async {
        let operations = CloudSyncOperations()
        let probe = CloudSyncOperationProbe()

        let first = operations.enqueue(.enable(authorized: true)) {
            await probe.suspendRecording("enable-1")
        }
        await probe.waitUntilSuspended()
        let disable = operations.enqueue { probe.record("disable") }
        let second = operations.enqueue(.enable(authorized: true)) { probe.record("enable-2") }

        probe.release()
        await first.value
        await disable.value
        await second.value

        #expect(probe.events == ["enable-1", "disable", "enable-2"])
    }

    @Test("Enable authorization is part of request identity")
    func authorizationBreaksCoalescing() async {
        let operations = CloudSyncOperations()
        let probe = CloudSyncOperationProbe()

        let authorized = operations.enqueue(.enable(authorized: true)) {
            await probe.suspendRecording("authorized")
        }
        await probe.waitUntilSuspended()
        let unauthorized = operations.enqueue(.enable(authorized: false)) {
            probe.record("unauthorized")
        }

        probe.release()
        await authorized.value
        await unauthorized.value

        #expect(probe.events == ["authorized", "unauthorized"])
    }

    @Test("A completed request can run again")
    func completedRequestCanRetry() async {
        let operations = CloudSyncOperations()
        let probe = CloudSyncOperationProbe()

        await operations.enqueue(.restore) { probe.record("restore-1") }.value
        await operations.enqueue(.restore) { probe.record("restore-2") }.value

        #expect(probe.events == ["restore-1", "restore-2"])
    }
}

@MainActor
private final class CloudSyncOperationProbe {
    private(set) var events: [String] = []
    private var isSuspended = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func record(_ event: String) {
        events.append(event)
    }

    func suspendRecording(_ event: String) async {
        record(event)
        isSuspended = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilSuspended() async {
        if isSuspended { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

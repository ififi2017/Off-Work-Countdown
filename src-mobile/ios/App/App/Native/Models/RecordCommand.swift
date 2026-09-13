import Foundation

/// An ordinary edit has already run when submitted. During archive replacement,
/// its result arrives only after the edit runs against the newly committed state.
@MainActor
enum RecordCommand<Value: Sendable> {
    case immediate(Value)
    case queued(Task<Value, Never>)

    var immediateResult: Value? {
        guard case .immediate(let result) = self else { return nil }
        return result
    }

    var value: Value {
        get async {
            switch self {
            case .immediate(let result): result
            case .queued(let task): await task.value
            }
        }
    }

    /// Only a synchronous compound command may consume a nested result this
    /// way. UI and system callers must await `value` when completion matters.
    var synchronousResult: Value {
        guard case .immediate(let result) = self else {
            preconditionFailure("A compound record command must enter admission before deriving state")
        }
        return result
    }
}

/// One FIFO for semantic edits and archive replacements. Only synchronous
/// command bodies are reentrant: an async replacement never lends its access
/// to an unrelated MainActor task while suspended on the persistence executor.
@MainActor
final class RecordCommandQueue {
    private struct Pending {
        let id: UUID
        let wait: @MainActor () async -> Void
    }

    private var tail: Pending?
    private var synchronousDepth = 0

    func waitForPending() async {
        precondition(synchronousDepth == 0, "Flush follows the synchronous record command")
        while let pending = tail { await pending.wait() }
    }

    @discardableResult
    func submit<Value: Sendable>(
        _ work: @escaping @MainActor () -> Value
    ) -> RecordCommand<Value> {
        guard let previous = tail, synchronousDepth == 0 else {
            return .immediate(runSynchronous(work))
        }
        let id = UUID()
        let task = Task { @MainActor in
            await previous.wait()
            defer { self.finish(id) }
            return self.runSynchronous(work)
        }
        tail = Pending(id: id, wait: { _ = await task.value })
        return .queued(task)
    }

    func replace<Value: Sendable>(
        _ work: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        precondition(synchronousDepth == 0, "A synchronous record command cannot suspend for replacement")
        let previous = tail
        let id = UUID()
        let task = Task { @MainActor in
            await previous?.wait()
            defer { self.finish(id) }
            return try await work()
        }
        tail = Pending(id: id, wait: { _ = try? await task.value })
        return try await task.value
    }

    /// Used for a committed candidate's synchronous reconciliation callback.
    /// No async body can escape with this privilege: the depth is reset before
    /// the MainActor can run another task.
    func runSynchronous<Value>(_ work: () -> Value) -> Value {
        synchronousDepth += 1
        defer { synchronousDepth -= 1 }
        return work()
    }

    func preconditionWriteAdmission() {
        precondition(
            tail == nil || synchronousDepth > 0,
            "Record writes must enter submitCommand while a candidate is pending"
        )
    }

    private func finish(_ id: UUID) {
        if tail?.id == id { tail = nil }
    }
}

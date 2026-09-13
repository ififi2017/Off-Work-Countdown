/// A text field edits locally until blur/Done. Receiving a committed update
/// refreshes an untouched field without discarding an edit already in progress.
nonisolated struct SettingsFieldDraft<Value: Equatable & Sendable>: Equatable, Sendable {
    private var storedValue: Value
    private var baseline: Value?
    private(set) var editGeneration: UInt64 = 0

    init(_ value: Value) { storedValue = value }

    var value: Value {
        get { storedValue }
        set {
            guard storedValue != newValue else { return }
            storedValue = newValue
            editGeneration &+= 1
        }
    }

    var hasChanges: Bool { baseline.map { value != $0 } ?? false }

    mutating func receive(_ committed: Value) {
        if !hasChanges { storedValue = committed }
        baseline = committed
    }

    mutating func accept(_ committed: Value) {
        storedValue = committed
        baseline = committed
    }

    @discardableResult
    mutating func accept(_ committed: Value, ifUnchangedSince generation: UInt64) -> Bool {
        guard editGeneration == generation else { return false }
        accept(committed)
        return true
    }
}

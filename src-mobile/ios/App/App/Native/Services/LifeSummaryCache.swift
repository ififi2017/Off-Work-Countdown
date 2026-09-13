import Foundation

/// Disposable, device-local derived data. The archive remains the source of truth.
nonisolated struct LifeSummaryCache: Codable, Sendable {
    var version = 1
    var key: LifeViewModelCacheKey
    var model: LifeViewModel

    @concurrent fileprivate static func read(from url: URL) async -> Self? {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.version == 1 else { return nil }
        return value
    }

    @concurrent fileprivate static func remove(at url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }

    @concurrent fileprivate static func write(_ value: Self, to url: URL) async {
        guard let data = try? JSONEncoder().encode(value) else { return }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var url = url
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try url.setResourceValues(resources)
        } catch {
            // A cache failure must not block saving the user's actual records.
        }
    }
}

/// Orders cache operations at the point the main-actor model requests them.
/// The file work still runs off the main actor, but an older suspended write
/// cannot land after a later removal or replacement write.
@MainActor
final class LifeSummaryCacheStore {
    typealias Read = @Sendable (URL) async -> LifeSummaryCache?
    typealias Write = @Sendable (LifeSummaryCache, URL) async -> Void
    typealias Remove = @Sendable (URL) async -> Void

    static let shared = LifeSummaryCacheStore()

    private let readValue: Read
    private let writeValue: Write
    private let removeValue: Remove
    private var tail: Task<Void, Never>?

    init(
        read: @escaping Read = { await LifeSummaryCache.read(from: $0) },
        write: @escaping Write = { await LifeSummaryCache.write($0, to: $1) },
        remove: @escaping Remove = { await LifeSummaryCache.remove(at: $0) }
    ) {
        readValue = read
        writeValue = write
        removeValue = remove
    }

    func read(from url: URL) async -> LifeSummaryCache? {
        await enqueue { [readValue] in await readValue(url) }.value
    }

    func write(_ value: LifeSummaryCache, to url: URL) async {
        await enqueue { [writeValue] in await writeValue(value, url) }.value
    }

    func remove(at url: URL) async {
        await enqueueRemove(at: url).value
    }

    /// Reserves the removal before returning so a subsequent replacement
    /// profile can safely enqueue its cache write behind it.
    func enqueueRemove(at url: URL) -> Task<Void, Never> {
        enqueue { [removeValue] in await removeValue(url) }
    }

    private func enqueue<Result: Sendable>(
        _ operation: @escaping @Sendable () async -> Result
    ) -> Task<Result, Never> {
        let predecessor = tail
        let task = Task {
            if let predecessor { await predecessor.value }
            return await operation()
        }
        tail = Task { _ = await task.value }
        return task
    }
}

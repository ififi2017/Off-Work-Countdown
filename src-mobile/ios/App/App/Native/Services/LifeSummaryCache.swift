import Foundation

/// Disposable, device-local derived data. The archive remains the source of truth.
nonisolated struct LifeSummaryCache: Codable, Sendable {
    var version = 1
    var key: OffWorkStore.LifeViewModelCacheKey
    var model: LifeViewModel

    @concurrent static func read(from url: URL) async -> Self? {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.version == 1 else { return nil }
        return value
    }

    @concurrent static func remove(at url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }

    @concurrent static func write(_ value: Self, to url: URL) async {
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

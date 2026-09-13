import Foundation

/// Warm schedule expansions for Records and Life.
///
/// A Life expansion covers a whole career. `prefetch` computes it off the main
/// actor so a year or life view can paint its first frame first; the main-actor
/// day walk then reads it back from here instead of expanding again.
@MainActor
final class ScheduleExpansionCache {
    static let shared = ScheduleExpansionCache()

    private var entries: [String: [NativeScheduleDayExpansion]] = [:]
    /// Insertion order, oldest first. This is a warm path, not a store, so it
    /// must not grow with browsing history.
    private var order: [String] = []
    private var dayCount = 0
    /// Counted in days, not entries: one Life expansion is worth thousands of
    /// Records windows, so an entry cap would not bound anything.
    private static let dayBudget = 40_000

    func days(
        configuration: ScheduleHoursConfiguration,
        from: Date,
        through: Date,
        timeZone: TimeZone? = nil
    ) -> [NativeScheduleDayExpansion] {
        let key = Self.key(configuration: configuration, from: from, through: through, timeZone: timeZone)
        if let cached = entries[key] { return cached }
        let days = ScheduleRules.expandScheduleRange(
            configuration: configuration,
            from: from,
            through: through,
            timeZone: timeZone
        )
        store(days, forKey: key)
        return days
    }

    func prefetch(
        configuration: ScheduleHoursConfiguration,
        from: Date,
        through: Date,
        timeZone: TimeZone? = nil
    ) async {
        let key = Self.key(configuration: configuration, from: from, through: through, timeZone: timeZone)
        if entries[key] != nil { return }
        let days = await Self.expandInBackground(
            configuration: configuration,
            from: from,
            through: through,
            timeZone: timeZone
        )
        store(days, forKey: key)
    }

    /// Drops every warmed expansion. The next read expands again.
    func purge() {
        entries.removeAll()
        order.removeAll()
        dayCount = 0
    }

    @concurrent
    private nonisolated static func expandInBackground(
        configuration: ScheduleHoursConfiguration,
        from: Date,
        through: Date,
        timeZone: TimeZone?
    ) async -> [NativeScheduleDayExpansion] {
        ScheduleRules.expandScheduleRange(
            configuration: configuration,
            from: from,
            through: through,
            timeZone: timeZone
        )
    }

    private func store(_ days: [NativeScheduleDayExpansion], forKey key: String) {
        if let existing = entries.removeValue(forKey: key) {
            dayCount -= existing.count
            order.removeAll { $0 == key }
        }
        entries[key] = days
        order.append(key)
        dayCount += days.count
        // Keep at least the entry just stored, however large it is: evicting it
        // immediately would turn every Life read back into a cold walk.
        while dayCount > Self.dayBudget, order.count > 1 {
            let oldest = order.removeFirst()
            dayCount -= entries.removeValue(forKey: oldest)?.count ?? 0
        }
    }

    private static func key(
        configuration: ScheduleHoursConfiguration,
        from: Date,
        through: Date,
        timeZone: TimeZone?
    ) -> String {
        let fingerprint = (try? ScheduleHoursCodec.encode(configuration).fingerprint) ?? "hours"
        let zone = timeZone?.identifier ?? "_"
        return "\(fingerprint)|\(zone)|\(from.timeIntervalSince1970)|\(through.timeIntervalSince1970)"
    }
}

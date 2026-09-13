import Foundation

/// Only projection inputs invalidate the decades-long schedule walk.
/// Settings and focus edits also bump the general archive revision, but
/// do not change Life. The civil day separates lived and projected time;
/// current hours backfill an empty or short archive.
nonisolated struct LifeViewModelCacheKey: Codable, Equatable, Sendable {
    var profile: LifeProfile?
    var periods: [CareerPeriod]
    var snapshots: [ScheduleSnapshot]
    var exceptions: [CalendarException]
    var overrides: [DayOverride]
    var observations: [WorkObservation]
    var dayKey: String
    var timeZoneIdentifier: String
    var hours: ScheduleHoursConfiguration?
    var salary: LifeSalaryPreferences

    func hasSameSchedule(as other: Self) -> Bool {
        var copy = self
        copy.salary = other.salary
        return copy == other
    }
}

nonisolated struct LifeSalaryPreferences: Codable, Equatable, Sendable {
    var amount: String
    var enabled: Bool
    var type: String
    var workingDays: Double
    var bonusMonths: Double
}

/// Cheap refresh input: no history-array normalization or observation scan.
nonisolated struct LifeSummaryRefreshInput: Equatable, Sendable {
    var projectionRevision: UInt64
    var dayKey: String
    var timeZoneIdentifier: String
    var hours: ScheduleHoursConfiguration
    var salary: LifeSalaryPreferences
}

/// Normalization belongs to the projection input cache, not the application
/// store. Unrelated commits return the existing key without mapping history.
@MainActor
final class LifeSummaryInputsCache {
    private var cached: (input: LifeSummaryRefreshInput, key: LifeViewModelCacheKey)?

    func key(for archive: RecordState, input: LifeSummaryRefreshInput, cacheAllowed: Bool = true) -> LifeViewModelCacheKey {
        if cacheAllowed, let cached, cached.input == input { return cached.key }
        // The archive transports timestamps in milliseconds. Normalize their
        // sub-millisecond floating-point noise so a cold reload hits the cache.
        func stable(_ date: Date) -> Date {
            Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1_000).rounded() / 1_000)
        }
        var profile = archive.lifeProfile
        if var value = profile {
            value.editedAt = stable(value.editedAt)
            value.sleepSourceUpdatedAt = value.sleepSourceUpdatedAt.map(stable)
            profile = value
        }
        let key = LifeViewModelCacheKey(
            profile: profile,
            periods: archive.periods.map { value in
                var copy = value; copy.editedAt = stable(value.editedAt); copy.createdAt = stable(value.createdAt)
                return copy
            },
            snapshots: archive.snapshots.map { value in
                var copy = value; copy.editedAt = stable(value.editedAt); return copy
            },
            exceptions: archive.exceptions.map { value in
                var copy = value; copy.editedAt = stable(value.editedAt); return copy
            },
            overrides: archive.overrides.map { value in
                var copy = value; copy.editedAt = stable(value.editedAt); return copy
            },
            observations: archive.observations.map { value in
                var copy = value; copy.editedAt = stable(value.editedAt); copy.occurredAt = stable(value.occurredAt)
                return copy
            },
            dayKey: input.dayKey,
            timeZoneIdentifier: input.timeZoneIdentifier,
            hours: input.hours,
            salary: input.salary
        )
        if cacheAllowed { cached = (input, key) }
        return key
    }
}

/// Only the current schedule and salary inputs needed by the Life projection.
nonisolated struct LifeSummaryPreferences: Equatable, Sendable {
    var hours: ScheduleHoursConfiguration
    var salary: LifeSalaryPreferences
}

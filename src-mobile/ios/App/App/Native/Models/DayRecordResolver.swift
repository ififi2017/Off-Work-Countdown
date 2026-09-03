import Foundation

/// Which layer produced a day's conclusion. Matches 002 §7 `resolvedFrom`.
enum DayResolutionLayer: String, Codable, Sendable {
    case override
    case calendarException
    case schedule
    case none
}

/// Hours the winning schedule snapshot already expanded through the shared
/// rules. The resolver does not run a second schedule algorithm.
struct ScheduleExpansion: Equatable, Sendable {
    var isWorkday: Bool
    var segments: [NativeShiftSegment]
    var failed: Bool = false

    static let failed = ScheduleExpansion(isWorkday: false, segments: [], failed: true)
}

/// One day's conclusion after the three-layer chain.
struct DayResolution: Equatable, Sendable {
    var dayKey: String
    var shiftAnchorDate: Date
    var layer: DayResolutionLayer
    var periodID: UUID?
    var snapshotID: UUID?
    var isScheduledWorkday: Bool
    var segments: [NativeShiftSegment]
    /// The schedule snapshot before a calendar exception or a user override
    /// wins the three-layer resolution. Records income uses this projection so
    /// leave and temporary schedule edits cannot rewrite salary history.
    var baseScheduleIsWorkday: Bool = false
    var baseScheduleSegments: [NativeShiftSegment] = []
    var expansionFailed: Bool = false
}

/// The winning exception and override for every day an archive mentions,
/// decided once instead of per resolved day.
///
/// Both layers are addressed by day key, so their winner never depends on
/// which day is being resolved — only on the archive. Deriving it per day
/// meant a `filter` over the whole exception list and a linear scan of the
/// override list for each of a career's fifteen thousand days, each one
/// allocating.
///
/// It deliberately does not restate the chooser rules: it buckets the archive
/// by day and asks `DayRecordResolver` itself, in the original array order, so
/// there is still exactly one definition of which exception wins.
struct DayRecordLookup {
    private let exceptions: [String: CalendarException]
    private let overrides: [String: DayOverride]

    init(exceptions allExceptions: [CalendarException], overrides allOverrides: [DayOverride]) {
        var byDate: [String: [CalendarException]] = [:]
        for exception in allExceptions {
            // `matches(dateKey:)` is a `"<date>#<origin>"` prefix test, so the
            // date half is the bucket.
            guard let dateKey = exception.dayKey.split(
                separator: "#",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first else { continue }
            byDate[String(dateKey), default: []].append(exception)
        }
        var winners: [String: CalendarException] = [:]
        winners.reserveCapacity(byDate.count)
        for (dateKey, bucket) in byDate {
            // Assigning `nil` removes the key, which is what a day with only
            // cleared exceptions should look like.
            winners[dateKey] = DayRecordResolver.exception(matching: dateKey, from: bucket)
        }
        exceptions = winners

        // `first(where:)` is what the per-day accessor used, so an earlier row
        // shadows a later one with the same key — including a `.cleared` row,
        // which the accessor below drops exactly as the original did.
        var firstByKey: [String: DayOverride] = [:]
        firstByKey.reserveCapacity(allOverrides.count)
        for override in allOverrides where firstByKey[override.dayKey] == nil {
            firstByKey[override.dayKey] = override
        }
        overrides = firstByKey
    }

    func exception(on dayKey: String) -> CalendarException? { exceptions[dayKey] }

    /// `nil` when missing or `.cleared`, so the chain falls through.
    func dayOverride(on dayKey: String) -> DayOverride? {
        guard let override = overrides[dayKey], override.kind != .cleared else { return nil }
        return override
    }
}

/// Read-time resolution for 002 §1–§2 and §5.
///
/// Order is fixed: an active day override, else a calendar exception, else
/// the winning schedule snapshot. `.cleared` on either override or exception
/// is a fall-through, not a leftover "cleared" layer. Observations are not
/// consulted.
enum DayRecordResolver {
    static func period(on day: Date, from periods: [CareerPeriod]) -> CareerPeriod? {
        periods
            .filter { $0.covers(day) }
            .max { lhs, rhs in
                if lhs.startsOn != rhs.startsOn { return lhs.startsOn < rhs.startsOn }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func snapshot(
        on day: Date,
        in period: CareerPeriod,
        from snapshots: [ScheduleSnapshot]
    ) -> ScheduleSnapshot? {
        let eligible = snapshots.filter {
            $0.periodID == period.id && $0.effectiveFrom <= day
        }
        guard let latestFrom = eligible.map(\.effectiveFrom).max() else { return nil }
        return eligible
            .filter { $0.effectiveFrom == latestFrom }
            .max { lhs, rhs in
                if lhs.editCount != rhs.editCount { return lhs.editCount < rhs.editCount }
                if lhs.editTieBreaker != rhs.editTieBreaker {
                    return lhs.editTieBreaker.uuidString < rhs.editTieBreaker.uuidString
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func exception(
        matching dateKey: String,
        from exceptions: [CalendarException]
    ) -> CalendarException? {
        let active = exceptions.filter { !$0.isCleared && $0.matches(dateKey: dateKey) }
        if let user = active.first(where: { $0.origin == .user }) { return user }
        return active
            .filter { $0.origin == .bundled }
            .max { lhs, rhs in
                switch (lhs.datasetVersion, rhs.datasetVersion) {
                case let (left?, right?) where left != right:
                    return left < right
                case (nil, .some):
                    return true
                case (.some, nil):
                    return false
                default:
                    return lhs.editCount < rhs.editCount
                }
            }
    }

    /// `nil` when missing or `.cleared`, so the chain falls through.
    static func dayOverride(
        matching dateKey: String,
        from overrides: [DayOverride]
    ) -> DayOverride? {
        guard let override = overrides.first(where: { $0.dayKey == dateKey }) else {
            return nil
        }
        if override.kind == .cleared { return nil }
        return override
    }

    static func resolve(
        dayKey: String,
        shiftAnchorDate: Date,
        periods: [CareerPeriod],
        snapshots: [ScheduleSnapshot],
        exceptions: [CalendarException],
        overrides: [DayOverride],
        expand: (ScheduleSnapshot) -> ScheduleExpansion
    ) -> DayResolution {
        // Qualified and renamed: a local `period`/`snapshot` shadows the static
        // lookup of the same name inside its own initializer.
        let coveringPeriod = Self.period(on: shiftAnchorDate, from: periods)
        let winningSnapshot = coveringPeriod.flatMap {
            Self.snapshot(on: shiftAnchorDate, in: $0, from: snapshots)
        }
        return resolve(
            dayKey: dayKey,
            shiftAnchorDate: shiftAnchorDate,
            period: coveringPeriod,
            snapshot: winningSnapshot,
            lookup: DayRecordLookup(exceptions: exceptions, overrides: overrides),
            expansion: winningSnapshot.map(expand) ?? ScheduleExpansion(isWorkday: false, segments: [])
        )
    }

    /// The same chain with its four archive lookups already done.
    ///
    /// Resolving one day is cheap; resolving a career is not. The convenience
    /// above re-derives the covering period, its snapshot and a filtered copy
    /// of the exception and override lists for every day it is handed, which
    /// over fifteen thousand days is the same scan fifteen thousand times. A
    /// caller walking a range decides the period and snapshot as it goes and
    /// builds the lookup once.
    static func resolve(
        dayKey: String,
        shiftAnchorDate: Date,
        period: CareerPeriod?,
        snapshot: ScheduleSnapshot?,
        lookup: DayRecordLookup,
        expansion resolvedExpansion: ScheduleExpansion
    ) -> DayResolution {
        // A day with no snapshot has no expansion to speak of, whatever the
        // caller passed.
        let expansion = snapshot == nil
            ? ScheduleExpansion(isWorkday: false, segments: [])
            : resolvedExpansion
        let empty = DayResolution(
            dayKey: dayKey,
            shiftAnchorDate: shiftAnchorDate,
            layer: .none,
            periodID: nil,
            snapshotID: nil,
            isScheduledWorkday: false,
            segments: []
        )
        guard let period else { return empty }
        let baseScheduleIsWorkday = snapshot != nil && expansion.isWorkday
        let baseScheduleSegments = baseScheduleIsWorkday ? expansion.segments : []
        let exception = lookup.exception(on: dayKey)
        let dayOverride = lookup.dayOverride(on: dayKey)
        if expansion.failed, dayOverride == nil, exception == nil {
            return DayResolution(
                dayKey: dayKey,
                shiftAnchorDate: shiftAnchorDate,
                layer: .none,
                periodID: period.id,
                snapshotID: snapshot?.id,
                isScheduledWorkday: false,
                segments: [],
                baseScheduleIsWorkday: false,
                baseScheduleSegments: [],
                expansionFailed: true
            )
        }

        if let override = dayOverride {
            switch override.kind {
            case .customSegments:
                return DayResolution(
                    dayKey: dayKey,
                    shiftAnchorDate: shiftAnchorDate,
                    layer: .override,
                    periodID: period.id,
                    snapshotID: snapshot?.id,
                    isScheduledWorkday: true,
                    segments: override.segments,
                    baseScheduleIsWorkday: baseScheduleIsWorkday,
                    baseScheduleSegments: baseScheduleSegments,
                    expansionFailed: expansion.failed
                )
            case .notWorking:
                return DayResolution(
                    dayKey: dayKey,
                    shiftAnchorDate: shiftAnchorDate,
                    layer: .override,
                    periodID: period.id,
                    snapshotID: snapshot?.id,
                    isScheduledWorkday: false,
                    segments: [],
                    baseScheduleIsWorkday: baseScheduleIsWorkday,
                    baseScheduleSegments: baseScheduleSegments,
                    expansionFailed: expansion.failed
                )
            case .confirmedAsScheduled:
                return DayResolution(
                    dayKey: dayKey,
                    shiftAnchorDate: shiftAnchorDate,
                    layer: .override,
                    periodID: period.id,
                    snapshotID: snapshot?.id,
                    isScheduledWorkday: expansion.isWorkday,
                    segments: expansion.isWorkday ? expansion.segments : [],
                    baseScheduleIsWorkday: baseScheduleIsWorkday,
                    baseScheduleSegments: baseScheduleSegments,
                    expansionFailed: expansion.failed
                )
            case .cleared:
                break
            }
        }

        if exception != nil {
            return applyExceptionOrSchedule(
                dayKey: dayKey,
                shiftAnchorDate: shiftAnchorDate,
                layer: .calendarException,
                periodID: period.id,
                snapshotID: snapshot?.id,
                exception: exception,
                expansion: expansion
            )
        }

        guard snapshot != nil else { return empty }
        return DayResolution(
            dayKey: dayKey,
            shiftAnchorDate: shiftAnchorDate,
            layer: .schedule,
            periodID: period.id,
            snapshotID: snapshot?.id,
            isScheduledWorkday: expansion.isWorkday,
            segments: expansion.isWorkday ? expansion.segments : [],
            baseScheduleIsWorkday: baseScheduleIsWorkday,
            baseScheduleSegments: baseScheduleSegments,
            expansionFailed: expansion.failed
        )
    }

    private static func applyExceptionOrSchedule(
        dayKey: String,
        shiftAnchorDate: Date,
        layer: DayResolutionLayer,
        periodID: UUID,
        snapshotID: UUID?,
        exception: CalendarException?,
        expansion: ScheduleExpansion
    ) -> DayResolution {
        if let exception {
            let isWorkday = exception.effect == .work
            return DayResolution(
                dayKey: dayKey,
                shiftAnchorDate: shiftAnchorDate,
                layer: layer,
                periodID: periodID,
                snapshotID: snapshotID,
                isScheduledWorkday: isWorkday,
                segments: isWorkday ? expansion.segments : [],
                baseScheduleIsWorkday: expansion.isWorkday,
                baseScheduleSegments: expansion.isWorkday ? expansion.segments : [],
                expansionFailed: expansion.failed
            )
        }
        return DayResolution(
            dayKey: dayKey,
            shiftAnchorDate: shiftAnchorDate,
            layer: layer,
            periodID: periodID,
            snapshotID: snapshotID,
            isScheduledWorkday: expansion.isWorkday,
            segments: expansion.isWorkday ? expansion.segments : [],
            baseScheduleIsWorkday: expansion.isWorkday,
            baseScheduleSegments: expansion.isWorkday ? expansion.segments : [],
            expansionFailed: expansion.failed
        )
    }
}

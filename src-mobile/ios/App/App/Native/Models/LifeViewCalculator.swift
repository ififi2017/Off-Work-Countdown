import Foundation

enum LifeWeekKind: String, Sendable {
    case childhood
    case study
    case workEstimated
    case workProjected
    case workOverride
    case retirement
    case none

    /// A week spent working, whether it already happened or is still ahead.
    var isWork: Bool {
        switch self {
        case .workEstimated, .workProjected, .workOverride: true
        case .childhood, .study, .retirement, .none: false
        }
    }

    /// Already lived through, as opposed to projected forward.
    var isPast: Bool {
        switch self {
        case .workEstimated, .workOverride, .childhood, .study: true
        case .workProjected, .retirement, .none: false
        }
    }
}

struct LifeWeekCell: Equatable, Sendable, Identifiable {
    var id: String { "\(year)-\(weekIndex)" }
    var year: Int
    var weekIndex: Int
    var start: Date
    var kind: LifeWeekKind
    var outsidePeriodTimeZone: Bool
}

struct LifeViewModel: Equatable, Sendable {
    var cells: [LifeWeekCell]
    var workShare: Double
    var ownAwakeShare: Double

    /// Working weeks already behind the user.
    var workedWeeks: Int {
        cells.count(where: { $0.kind.isWork && $0.kind.isPast })
    }

    /// Working weeks still to come before retirement.
    var remainingWeeks: Int {
        cells.count(where: { $0.kind == .workProjected })
    }
}

/// One career-period day after the shared TypeScript rules and the complete
/// override / calendar-exception / schedule chain have already been applied.
/// An absent day is an uncovered career gap; a present day with no segments is
/// a covered rest or leave day. Life calculations never interpret schedules.
struct LifeScheduleDay: Equatable, Sendable {
    let periodID: UUID
    let dayKey: String
    let shiftAnchorDate: Date
    let segments: [NativeShiftSegment]
    let isOverride: Bool

    init(
        periodID: UUID,
        dayKey: String,
        shiftAnchorDate: Date,
        segments: [NativeShiftSegment],
        isOverride: Bool
    ) {
        self.periodID = periodID
        self.dayKey = dayKey
        self.shiftAnchorDate = shiftAnchorDate
        self.segments = segments
        self.isOverride = isOverride
    }

    init?(resolution: DayResolution) {
        guard let periodID = resolution.periodID else { return nil }
        self.init(
            periodID: periodID,
            dayKey: resolution.dayKey,
            shiftAnchorDate: resolution.shiftAnchorDate,
            segments: resolution.segments,
            isOverride: resolution.layer == .override && !resolution.segments.isEmpty
        )
    }
}

enum LifeViewCalculator {
    static func build(
        profile: LifeProfile,
        scheduleDays: [LifeScheduleDay],
        outsideZoneDays: Set<String>,
        now: Date,
        calendar: Calendar
    ) -> LifeViewModel {
        var resolvedProfile = profile
        resolvedProfile.migrateLegacyFields(calendar: calendar)
        guard let lifeStart = resolvedProfile.bornOn?.calculationAnchor(in: calendar),
              let lifeEnd = resolvedProfile.retirementOn?.calculationAnchor(in: calendar),
              lifeEnd > lifeStart
        else {
            return LifeViewModel(cells: [], workShare: 0, ownAwakeShare: 0)
        }
        let schoolStart = resolvedProfile.schoolStartedOn?.calculationAnchor(in: calendar)
            ?? calendar.date(byAdding: .year, value: 6, to: lifeStart)
            ?? lifeStart
        let workStart = resolvedProfile.workStartedPartial?.calculationAnchor(in: calendar)
            ?? resolvedProfile.workStartedOn
            ?? calendar.date(byAdding: .year, value: 22, to: lifeStart)
            ?? now
        let workIntervals = mergedIntervals(
            scheduleDays.flatMap(\.segments),
            clippedFrom: lifeStart,
            through: lifeEnd
        )
        let overrideIntervals = mergedIntervals(
            scheduleDays.filter(\.isOverride).flatMap(\.segments),
            clippedFrom: lifeStart,
            through: lifeEnd
        )
        let outsideZoneAnchors = scheduleDays.compactMap { day in
            outsideZoneDays.contains(day.dayKey) ? day.shiftAnchorDate : nil
        }.sorted()
        var cursor = lifeStart
        var cells: [LifeWeekCell] = []
        var weekIndex = 0
        // All three sorted streams advance monotonically with the week cursor;
        // a life-sized range never rescans every segment or day per cell.
        var workIntervalIndex = 0
        var overrideIntervalIndex = 0
        var outsideZoneIndex = 0
        while cursor < lifeEnd {
            guard let proposedEnd = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            let cellEnd = min(proposedEnd, lifeEnd)
            let year = calendar.component(.year, from: cursor)
            let kind: LifeWeekKind
            let cellHasWork = intersects(
                workIntervals,
                from: cursor,
                through: cellEnd,
                startingAt: &workIntervalIndex
            )
            if cellHasWork {
                let cellHasOverride = intersects(
                    overrideIntervals,
                    from: cursor,
                    through: cellEnd,
                    startingAt: &overrideIntervalIndex
                )
                if cellHasOverride, cursor <= now {
                    kind = .workOverride
                } else if cursor > now {
                    kind = .workProjected
                } else {
                    kind = .workEstimated
                }
            } else if cellEnd <= workStart {
                kind = cellEnd <= schoolStart ? .childhood : .study
            } else {
                // No expanded work in this interval means a career gap, a
                // covered rest stretch, or leave — never implicit work.
                kind = .none
            }
            while outsideZoneIndex < outsideZoneAnchors.count,
                  outsideZoneAnchors[outsideZoneIndex] < cursor {
                outsideZoneIndex += 1
            }
            let isOutsidePeriodTimeZone = outsideZoneIndex < outsideZoneAnchors.count
                && outsideZoneAnchors[outsideZoneIndex] < cellEnd
            cells.append(
                LifeWeekCell(
                    year: year,
                    weekIndex: weekIndex,
                    start: cursor,
                    kind: kind,
                    outsidePeriodTimeZone: isOutsidePeriodTimeZone
                )
            )
            cursor = cellEnd
            weekIndex += 1
        }
        let totalMs = lifeEnd.timeIntervalSince(lifeStart) * 1_000
        let workMs = workIntervals.reduce(0) { $0 + ($1.endMs - $1.startMs) }
        let workShare = totalMs > 0 ? min(1, max(0, workMs / totalMs)) : 0
        let configuredSleepHours = resolvedProfile.averageSleepHours
            ?? resolvedProfile.averageSleepMinutes.map { Double($0) / 60 }
            ?? 8
        let sleepHours = min(24, max(0, configuredSleepHours))
        let sleepMs = totalMs * sleepHours / 24
        let ownAwakeShare = totalMs > 0
            ? min(1, max(0, (totalMs - sleepMs - workMs) / totalMs))
            : 0
        return LifeViewModel(cells: cells, workShare: workShare, ownAwakeShare: ownAwakeShare)
    }

    private struct WorkInterval {
        var startMs: Double
        var endMs: Double
    }

    /// Unioning is necessary because an overnight segment and a correction can
    /// otherwise make the same absolute time count twice in a life percentage.
    private static func mergedIntervals(
        _ segments: [NativeShiftSegment],
        clippedFrom start: Date,
        through end: Date
    ) -> [WorkInterval] {
        let lowerBound = start.timeIntervalSince1970 * 1_000
        let upperBound = end.timeIntervalSince1970 * 1_000
        let sorted = segments.compactMap { segment -> WorkInterval? in
            let clippedStart = max(lowerBound, segment.startAtMs)
            let clippedEnd = min(upperBound, segment.endAtMs)
            guard clippedEnd > clippedStart else { return nil }
            return WorkInterval(startMs: clippedStart, endMs: clippedEnd)
        }.sorted { lhs, rhs in
            if lhs.startMs != rhs.startMs { return lhs.startMs < rhs.startMs }
            return lhs.endMs < rhs.endMs
        }

        var merged: [WorkInterval] = []
        for interval in sorted {
            guard var previous = merged.popLast() else {
                merged.append(interval)
                continue
            }
            if interval.startMs <= previous.endMs {
                previous.endMs = max(previous.endMs, interval.endMs)
                merged.append(previous)
            } else {
                merged.append(previous)
                merged.append(interval)
            }
        }
        return merged
    }

    private static func intersects(
        _ intervals: [WorkInterval],
        from start: Date,
        through end: Date,
        startingAt index: inout Int
    ) -> Bool {
        let lowerBound = start.timeIntervalSince1970 * 1_000
        let upperBound = end.timeIntervalSince1970 * 1_000
        while index < intervals.count, intervals[index].endMs <= lowerBound {
            index += 1
        }
        return index < intervals.count && intervals[index].startMs < upperBound
    }
}

enum TimeAllocationKind: Equatable, Hashable, Sendable {
    case work
    case overtime
    case workBreak
    case sleep
    case free
    case unclassified
}

struct TimeAllocationShare: Equatable, Sendable {
    var workMs: Int64
    var overtimeMs: Int64
    var breakMs: Int64 = 0
    var sleepMs: Int64
    var freeMs: Int64
    var unclassifiedMs: Int64 = 0
    var dayLengthMs: Int64

    var totalMs: Int64 { workMs + overtimeMs + breakMs + sleepMs + freeMs + unclassifiedMs }
    var wakingFreeMs: Int64 { breakMs + freeMs }
}

enum TimeAllocationCalculator {
    /// Intersects work segments with a civil day. An overnight 20:00–04:00
    /// contributes four hours to each calendar day; the shift still counts as
    /// one workday on its anchor. Sleep is clipped so it cannot go negative
    /// against remaining awake time.
    static func share(
        dayStart: Date,
        nextDayStart: Date,
        workSegments: [NativeShiftSegment],
        overtimeSegments: [NativeShiftSegment] = [],
        sleepHours: Double
    ) -> TimeAllocationShare {
        share(
            dayStart: dayStart,
            nextDayStart: nextDayStart,
            workSegments: workSegments,
            overtimeSegments: overtimeSegments,
            breakSegments: [],
            sleepHours: sleepHours
        )
    }

    static func clippedDuration(
        _ segments: [NativeShiftSegment],
        from startMs: Int64,
        to endMs: Int64
    ) -> Int64 {
        segments.reduce(0) { total, segment in
            let lo = max(startMs, Int64(segment.startAtMs.rounded()))
            let hi = min(endMs, Int64(segment.endAtMs.rounded()))
            return total + max(0, hi - lo)
        }
    }
}

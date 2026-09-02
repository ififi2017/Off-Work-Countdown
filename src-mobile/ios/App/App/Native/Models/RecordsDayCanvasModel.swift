import Foundation

/// Where one fact on a records surface came from.
///
/// Every drawn stretch and every day header carries one of these. Hatching,
/// correction marks and locks are the visual shorthand for a source — they are
/// never a substitute for the words, because "estimated" and "you changed it"
/// are not distinguishable as two shades of the same colour.
enum RecordsDaySource: String, Equatable, Hashable, Sendable, CaseIterable {
    /// The user's own timer wrote this day.
    case recorded
    /// The user edited this day in Records.
    case corrected
    /// A holiday or makeup day from the calendar.
    case exception
    /// Expanded from the schedule that governed that date.
    case scheduleEstimate
    /// Today, past the now line: the rest of today's schedule, not a fact yet.
    case afterNow
    /// Before Records began, or after today, from the life profile.
    case lifeProjection
    /// A future day the schedule plans.
    case planned
    /// The sleep budget from the life profile, placed for reading.
    case sleepEstimate
    /// A workday with nothing written on it.
    case unrecorded
    /// Not a workday.
    case rest
    /// Outside the free window and without Plus.
    case locked

    var titleKey: String {
        switch self {
        case .recorded: "recordsSourceRecorded"
        case .corrected: "recordsSourceOverride"
        case .exception: "recordsSourceException"
        case .scheduleEstimate: "recordsSourceSchedule"
        case .afterNow: "recordsSourceAfterNow"
        case .lifeProjection: "recordsSourceProjection"
        case .planned: "recordsPlanned"
        case .sleepEstimate: "recordsSleepEstimated"
        case .unrecorded: "recordsUnrecorded"
        case .rest: "recordsRestDay"
        case .locked: "recordsLockedDay"
        }
    }

    /// Drawn with 135° hatching. Deliberately not "drawn fainter": a lower
    /// opacity reads as *less important*, which is not what an estimate is.
    var isEstimated: Bool {
        switch self {
        case .scheduleEstimate, .afterNow, .lifeProjection, .planned, .sleepEstimate: true
        case .recorded, .corrected, .exception, .unrecorded, .rest, .locked: false
        }
    }

    /// Earns a mark of its own beside the texture.
    var isCorrection: Bool { self == .corrected }
}

/// One classified, attributed stretch of a civil day.
struct RecordsDayInterval: Equatable, Sendable, Identifiable {
    var kind: TimeAllocationKind
    var startAtMs: Double
    var endAtMs: Double
    var source: RecordsDaySource
    /// The localized key that names the source. Sleep resolves to the life
    /// profile or to Health, so the model carries the resolved key rather than
    /// letting each view re-decide.
    var sourceKey: String
    /// The shift this stretch belongs to, so an editor can open the right
    /// original record. `nil` for sleep, own time and unclassified time, none
    /// of which have an input to edit.
    var anchorDayKey: String?

    var id: String { "\(kind.rawValue)-\(Int64(startAtMs.rounded()))" }
    var durationMs: Int64 { max(0, Int64((endAtMs - startAtMs).rounded())) }
}

/// A shift that reaches into the civil day being drawn. A 20:00–04:00 shift is
/// one of these for two consecutive days.
struct RecordsDayShift: Equatable, Sendable {
    var anchorDayKey: String
    var segments: [NativeShiftSegment]
    var overtimeSegments: [NativeShiftSegment] = []
    var source: RecordsDaySource
    /// Only a shift with an editable original input offers an edit entry.
    /// A pure plan or projection must not grow a button that cannot save.
    var isEditable: Bool = false
}

/// A shift the day's edit entry can open, labelled by its own real hours
/// rather than by the part that happens to fall inside this civil day.
struct RecordsDayEditableShift: Equatable, Sendable, Identifiable {
    var anchorDayKey: String
    var startAtMs: Double
    var endAtMs: Double
    /// A rest day is editable — it can become a makeup day — but it has no
    /// hours to name it by, so the picker falls back to its date.
    var hasHours: Bool

    var id: String { anchorDayKey }
}

/// One civil day, ready to draw and ready to read aloud.
///
/// This is the only place a day is cut out of the shifts that cross it. Views
/// receive finished intervals; they never intersect, clip overtime, derive a
/// lunch gap or decide what a source is.
struct RecordsDayCanvasModel: Equatable, Sendable {
    var dayKey: String
    var dayStart: Date
    var dayEnd: Date
    /// What the day as a whole is. Individual stretches can differ.
    var source: RecordsDaySource
    var intervals: [RecordsDayInterval]
    var allocation: TimeAllocationShare
    var isToday: Bool
    /// Only set for today, and only on a minute boundary. A retrospective page
    /// does not need a second per-second refresh surface.
    var nowAtMs: Double?
    /// Where the "the rest is the schedule, not a fact" hatching begins.
    var projectionStartsAtMs: Double?
    var editableShifts: [RecordsDayEditableShift]
    var isLocked: Bool
    var sleepSourceKey: String
    /// The shared rules could not expand this day, so part of it is honestly
    /// unaccounted for instead of padded out to 100%.
    var hasIncompleteRules: Bool

    /// The day's one conclusion: breaks at work plus the rest of your own
    /// waking time. Not the same value as `allocation.freeMs`, which is only
    /// the second half of it.
    var wakingFreeMs: Int64 { allocation.wakingFreeMs }

    /// Share of the day's real length — 23 or 25 hours on a DST day.
    var wakingFreeShare: Double {
        guard allocation.dayLengthMs > 0 else { return 0 }
        return min(1, max(0, Double(wakingFreeMs) / Double(allocation.dayLengthMs)))
    }

    var workIntervals: [RecordsDayInterval] {
        intervals.filter { $0.kind == .work || $0.kind == .overtime }
    }

    /// A locked day carries no real interval, duration, source or anchor. The
    /// view tree and the accessibility tree get the same nothing.
    static func locked(dayKey: String, dayStart: Date, dayEnd: Date) -> RecordsDayCanvasModel {
        RecordsDayCanvasModel(
            dayKey: dayKey,
            dayStart: dayStart,
            dayEnd: dayEnd,
            source: .locked,
            intervals: [],
            allocation: TimeAllocationShare(
                workMs: 0,
                overtimeMs: 0,
                breakMs: 0,
                sleepMs: 0,
                freeMs: 0,
                unclassifiedMs: 0,
                dayLengthMs: 0
            ),
            isToday: false,
            nowAtMs: nil,
            projectionStartsAtMs: nil,
            editableShifts: [],
            isLocked: true,
            sleepSourceKey: "recordsSleepEstimated",
            hasIncompleteRules: false
        )
    }
}

extension RecordsDayCanvasModel {
    struct Input: Sendable {
        var dayKey: String
        var dayStart: Date
        var dayEnd: Date
        var source: RecordsDaySource
        /// Every shift that can reach this day, the day's own included.
        var shifts: [RecordsDayShift]
        var sleepHours: Double
        var sleepSourceKey: String
        var isToday: Bool
        var now: Date
        /// Schedule expansion failed, so the leftover awake time is unknown
        /// rather than free.
        var rulesFailed: Bool

        init(
            dayKey: String,
            dayStart: Date,
            dayEnd: Date,
            source: RecordsDaySource,
            shifts: [RecordsDayShift],
            sleepHours: Double,
            sleepSourceKey: String = "recordsSleepEstimated",
            isToday: Bool = false,
            now: Date = .now,
            rulesFailed: Bool = false
        ) {
            self.dayKey = dayKey
            self.dayStart = dayStart
            self.dayEnd = dayEnd
            self.source = source
            self.shifts = shifts
            self.sleepHours = sleepHours
            self.sleepSourceKey = sleepSourceKey
            self.isToday = isToday
            self.now = now
            self.rulesFailed = rulesFailed
        }
    }

    /// Cuts the civil day out of the shifts that cross it, then fills what is
    /// left. The allocation is summed from what was actually placed, so the
    /// band and the numbers under it cannot disagree.
    static func build(_ input: Input) -> RecordsDayCanvasModel {
        let lower = milliseconds(input.dayStart)
        let upper = milliseconds(input.dayEnd)
        let dayLength = max(0, Int64((upper - lower).rounded()))
        guard upper > lower else {
            return RecordsDayCanvasModel(
                dayKey: input.dayKey,
                dayStart: input.dayStart,
                dayEnd: input.dayEnd,
                source: input.source,
                intervals: [],
                allocation: TimeAllocationShare(
                    workMs: 0, overtimeMs: 0, breakMs: 0,
                    sleepMs: 0, freeMs: 0, unclassifiedMs: 0, dayLengthMs: 0
                ),
                isToday: input.isToday,
                nowAtMs: nil,
                projectionStartsAtMs: nil,
                editableShifts: [],
                isLocked: false,
                sleepSourceKey: input.sleepSourceKey,
                hasIncompleteRules: input.rulesFailed
            )
        }

        // Shifts run oldest first so an overlap between a corrected day and the
        // night before resolves the same way every time instead of by array
        // order.
        let shifts = input.shifts.sorted { $0.anchorDayKey < $1.anchorDayKey }
        var intervals: [RecordsDayInterval] = []
        var occupied: [Span] = []

        for shift in shifts {
            let work = subtract(
                occupied,
                from: clip(shift.segments, lower: lower, upper: upper)
            )
            occupied = merge(occupied + work)
            intervals += work.map {
                interval(.work, $0, shift: shift, sleepSourceKey: input.sleepSourceKey)
            }
        }
        for shift in shifts {
            let overtime = subtract(
                occupied,
                from: clip(shift.overtimeSegments, lower: lower, upper: upper)
            )
            occupied = merge(occupied + overtime)
            intervals += overtime.map {
                interval(.overtime, $0, shift: shift, sleepSourceKey: input.sleepSourceKey)
            }
        }
        for shift in shifts {
            // Only the gaps inside one shift are breaks. Unioning every shift
            // first would turn the sixteen hours between two night shifts into
            // one enormous lunch break.
            let breaks = subtract(
                occupied,
                from: clip(
                    TimeAllocationCalculator.gaps(in: shift.segments),
                    lower: lower,
                    upper: upper
                )
            )
            occupied = merge(occupied + breaks)
            intervals += breaks.map {
                interval(.workBreak, $0, shift: shift, sleepSourceKey: input.sleepSourceKey)
            }
        }

        let openBlocks = complement(of: occupied, lower: lower, upper: upper)
        let sleepBudget = max(0, input.sleepHours) * 3_600_000
        let (sleepSpans, remainder) = placeSleep(sleepBudget, in: openBlocks)
        intervals += sleepSpans.map { span in
            RecordsDayInterval(
                kind: .sleep,
                startAtMs: span.start,
                endAtMs: span.end,
                source: .sleepEstimate,
                sourceKey: input.sleepSourceKey,
                anchorDayKey: nil
            )
        }
        let ownKind: TimeAllocationKind = input.rulesFailed ? .unclassified : .free
        intervals += remainder.map { span in
            RecordsDayInterval(
                kind: ownKind,
                startAtMs: span.start,
                endAtMs: span.end,
                source: input.rulesFailed ? .scheduleEstimate : input.source,
                sourceKey: input.rulesFailed
                    ? "recordsSourceNone"
                    : input.source.titleKey,
                anchorDayKey: nil
            )
        }
        intervals.sort { $0.startAtMs < $1.startAtMs }

        let nowMs = input.isToday ? milliseconds(minuteFloor(input.now)) : nil
        let projectionStart = nowMs.flatMap { value -> Double? in
            guard value >= lower, value < upper else { return nil }
            return value
        }

        let editable = shifts.compactMap { shift -> RecordsDayEditableShift? in
            guard shift.isEditable else { return nil }
            let hours = !clip(shift.segments, lower: lower, upper: upper).isEmpty
            // The day on screen is always one of the answers to "which shift?",
            // even when it has no hours of its own — marking a rest day as a
            // makeup day is exactly the edit someone comes here to make. A
            // neighbouring shift only earns a place once it reaches into today.
            guard hours || shift.anchorDayKey == input.dayKey else { return nil }
            return RecordsDayEditableShift(
                anchorDayKey: shift.anchorDayKey,
                startAtMs: shift.segments.map(\.startAtMs).min() ?? lower,
                endAtMs: shift.segments.map(\.endAtMs).max() ?? upper,
                hasHours: hours
            )
        }

        return RecordsDayCanvasModel(
            dayKey: input.dayKey,
            dayStart: input.dayStart,
            dayEnd: input.dayEnd,
            source: input.source,
            intervals: intervals,
            allocation: allocation(of: intervals, dayLengthMs: dayLength),
            isToday: input.isToday,
            nowAtMs: nowMs,
            projectionStartsAtMs: projectionStart,
            editableShifts: editable,
            isLocked: false,
            sleepSourceKey: input.sleepSourceKey,
            hasIncompleteRules: input.rulesFailed
        )
    }

    // MARK: - Span arithmetic

    private struct Span: Equatable {
        var start: Double
        var end: Double
    }

    private static func milliseconds(_ date: Date) -> Double {
        date.timeIntervalSince1970 * 1_000
    }

    /// The now line advances on minute boundaries. Rebuilding this model once a
    /// second would be a second countdown surface, which the timer tab already
    /// is.
    private static func minuteFloor(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    private static func interval(
        _ kind: TimeAllocationKind,
        _ span: Span,
        shift: RecordsDayShift,
        sleepSourceKey: String
    ) -> RecordsDayInterval {
        RecordsDayInterval(
            kind: kind,
            startAtMs: span.start,
            endAtMs: span.end,
            source: shift.source,
            sourceKey: shift.source.titleKey,
            anchorDayKey: shift.anchorDayKey
        )
    }

    private static func clip(
        _ segments: [NativeShiftSegment],
        lower: Double,
        upper: Double
    ) -> [Span] {
        merge(segments.compactMap { segment in
            let start = max(lower, segment.startAtMs)
            let end = min(upper, segment.endAtMs)
            guard end > start else { return nil }
            return Span(start: start, end: end)
        })
    }

    private static func merge(_ spans: [Span]) -> [Span] {
        let sorted = spans.sorted { $0.start < $1.start }
        var merged: [Span] = []
        for span in sorted {
            if var last = merged.last, span.start <= last.end {
                last.end = max(last.end, span.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    private static func subtract(_ taken: [Span], from spans: [Span]) -> [Span] {
        guard !taken.isEmpty else { return spans }
        var result: [Span] = []
        for span in spans {
            var cursor = span.start
            for block in taken where block.end > span.start && block.start < span.end {
                if block.start > cursor {
                    result.append(Span(start: cursor, end: min(block.start, span.end)))
                }
                cursor = max(cursor, block.end)
                if cursor >= span.end { break }
            }
            if cursor < span.end {
                result.append(Span(start: cursor, end: span.end))
            }
        }
        return result.filter { $0.end > $0.start }
    }

    private static func complement(of taken: [Span], lower: Double, upper: Double) -> [Span] {
        subtract(merge(taken), from: [Span(start: lower, end: upper)])
    }

    /// Sleep is a budget, not a recorded time, so it is drawn at the start of
    /// the longest unbroken stretch of non-work time — the one place a night's
    /// sleep can actually have been. Whatever it cannot cover stays awake time.
    private static func placeSleep(
        _ budgetMs: Double,
        in blocks: [Span]
    ) -> (sleep: [Span], remainder: [Span]) {
        guard budgetMs > 0 else { return ([], blocks) }
        var remaining = budgetMs
        var sleep: [Span] = []
        var remainder: [Span] = []
        let order = blocks.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.end - lhs.element.start
                let right = rhs.element.end - rhs.element.start
                if left != right { return left > right }
                return lhs.offset < rhs.offset
            }
            .map(\.offset)
        var filled: [Int: Double] = [:]
        for index in order where remaining > 0 {
            let block = blocks[index]
            let taken = min(remaining, block.end - block.start)
            guard taken > 0 else { continue }
            filled[index] = taken
            remaining -= taken
        }
        for (index, block) in blocks.enumerated() {
            guard let taken = filled[index] else {
                remainder.append(block)
                continue
            }
            sleep.append(Span(start: block.start, end: block.start + taken))
            if block.start + taken < block.end {
                remainder.append(Span(start: block.start + taken, end: block.end))
            }
        }
        return (sleep, remainder)
    }

    private static func allocation(
        of intervals: [RecordsDayInterval],
        dayLengthMs: Int64
    ) -> TimeAllocationShare {
        func total(_ kind: TimeAllocationKind) -> Int64 {
            intervals.filter { $0.kind == kind }.reduce(0) { $0 + $1.durationMs }
        }
        return TimeAllocationShare(
            workMs: total(.work),
            overtimeMs: total(.overtime),
            breakMs: total(.workBreak),
            sleepMs: total(.sleep),
            freeMs: total(.free),
            unclassifiedMs: total(.unclassified),
            dayLengthMs: dayLengthMs
        )
    }
}

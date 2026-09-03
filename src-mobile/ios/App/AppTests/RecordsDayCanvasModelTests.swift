import Foundation
import Testing
@testable import App

/// The day canvas is the only place a civil day is cut out of the shifts that
/// cross it, so these are the acceptance tests for every records surface that
/// prints a per-day number — not only for the day page.
private let hour = 3_600_000.0

private func utcDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

private func segment(_ start: Date, plus startHours: Double, to endHours: Double) -> NativeShiftSegment {
    let base = start.timeIntervalSince1970 * 1_000
    return NativeShiftSegment(startAtMs: base + startHours * hour, endAtMs: base + endHours * hour)
}

@MainActor
private func model(
    dayStart: Date,
    dayEnd: Date? = nil,
    // The key has to be the real one: the model asks whether a shift's anchor
    // is the day on screen when it decides what can be edited.
    dayKey: String = "2026-08-24",
    shifts: [RecordsDayShift],
    sleepHours: Double = 8,
    source: RecordsDaySource = .recorded,
    isToday: Bool = false,
    now: Date = .distantPast,
    rulesFailed: Bool = false
) -> RecordsDayCanvasModel {
    RecordsDayCanvasModel.build(
        RecordsDayCanvasModel.Input(
            dayKey: dayKey,
            dayStart: dayStart,
            dayEnd: dayEnd ?? dayStart.addingTimeInterval(86_400),
            source: source,
            shifts: shifts,
            sleepHours: sleepHours,
            isToday: isToday,
            now: now,
            rulesFailed: rulesFailed
        )
    )
}

@MainActor
@Suite("Records day canvas")
struct RecordsDayCanvasModelTests {
    @Test("A day shift, its lunch gap and the time around it never overlap")
    func dayCanvasSeparatesWorkBreakAndOwnTime() {
        let day = utcDay(2026, 8, 24)
        let shift = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [segment(day, plus: 9, to: 12), segment(day, plus: 13, to: 18)],
            source: .recorded
        )
        let canvas = model(dayStart: day, shifts: [shift])

        #expect(canvas.allocation.workMs == Int64(8 * hour))
        #expect(canvas.allocation.breakMs == Int64(1 * hour))
        #expect(canvas.allocation.sleepMs == Int64(8 * hour))
        #expect(canvas.allocation.freeMs == Int64(7 * hour))
        #expect(canvas.allocation.totalMs == canvas.allocation.dayLengthMs)

        // Nothing may be double counted: consecutive intervals must not overlap.
        let sorted = canvas.intervals.sorted { $0.startAtMs < $1.startAtMs }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            #expect(earlier.endAtMs <= later.startAtMs)
        }
    }

    @Test("Own waking time is breaks plus free time, and is not the same number as free time")
    func wakingFreeTimeIsNotFreeTime() {
        let day = utcDay(2026, 8, 24)
        let shift = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [segment(day, plus: 9, to: 12), segment(day, plus: 13, to: 18)],
            source: .recorded
        )
        let canvas = model(dayStart: day, shifts: [shift])

        #expect(canvas.allocation.freeMs == Int64(7 * hour))
        #expect(canvas.wakingFreeMs == Int64(8 * hour))
        #expect(canvas.wakingFreeMs != canvas.allocation.freeMs)
        #expect(canvas.wakingFreeMs == canvas.allocation.breakMs + canvas.allocation.freeMs)
    }

    @Test("An overnight shift shows its real intersection with each of the two civil days")
    func overnightShiftSplitsAcrossTwoCivilDays() {
        let day = utcDay(2026, 8, 24)
        let next = utcDay(2026, 8, 25)
        let shift = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [segment(day, plus: 20, to: 28)],
            source: .recorded
        )

        let first = model(dayStart: day, shifts: [shift])
        let second = model(
            dayStart: next,
            dayKey: "2026-08-25",
            shifts: [shift],
            source: .rest
        )

        #expect(first.allocation.workMs == Int64(4 * hour))
        #expect(second.allocation.workMs == Int64(4 * hour))
        #expect(first.allocation.totalMs == first.allocation.dayLengthMs)
        #expect(second.allocation.totalMs == second.allocation.dayLengthMs)
        #expect(second.source == .recorded)
        // The morning half still belongs to the shift that produced it, so the
        // editor can open the right record from either day.
        #expect(second.workIntervals.allSatisfy { $0.anchorDayKey == "2026-08-24" })
    }

    @Test("Two shifts touching one day are both drawn and both editable")
    func twoShiftsOnOneDayKeepTheirOwnAnchors() {
        let day = utcDay(2026, 8, 24)
        let previous = RecordsDayShift(
            anchorDayKey: "2026-08-23",
            segments: [segment(day, plus: -4, to: 6)],
            source: .recorded,
            isEditable: true
        )
        let own = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [segment(day, plus: 20, to: 28)],
            source: .corrected,
            isEditable: true
        )
        let canvas = model(dayStart: day, shifts: [own, previous])

        #expect(canvas.allocation.workMs == Int64(10 * hour))
        #expect(canvas.editableShifts.map(\.anchorDayKey) == ["2026-08-23", "2026-08-24"])
        // The label is the shift's own hours, not the sliver inside this day.
        let earlier = canvas.editableShifts[0]
        #expect(earlier.endAtMs - earlier.startAtMs == 10 * hour)
        #expect(earlier.hasHours)
        #expect(canvas.workIntervals.first?.anchorDayKey == "2026-08-23")
        #expect(canvas.workIntervals.last?.anchorDayKey == "2026-08-24")
        #expect(canvas.workIntervals.last?.source == .corrected)
    }

    @Test("Sixteen hours between two night shifts is not a lunch break")
    func gapsBetweenDifferentShiftsAreNotBreaks() {
        let day = utcDay(2026, 8, 24)
        let previous = RecordsDayShift(
            anchorDayKey: "2026-08-23",
            segments: [segment(day, plus: -4, to: 4)],
            source: .recorded
        )
        let own = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [segment(day, plus: 20, to: 28)],
            source: .recorded
        )
        let canvas = model(dayStart: day, shifts: [previous, own])

        #expect(canvas.allocation.breakMs == 0)
        #expect(canvas.allocation.workMs == Int64(8 * hour))
    }

    @Test("Declared overtime and regular work are drawn once, never twice")
    func overtimeNeverOverlapsRegularWork() {
        let day = utcDay(2026, 8, 24)
        let shift = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [segment(day, plus: 9, to: 18)],
            overtimeSegments: [segment(day, plus: 17, to: 20)],
            source: .recorded
        )
        let canvas = model(dayStart: day, shifts: [shift])

        #expect(canvas.allocation.workMs == Int64(9 * hour))
        #expect(canvas.allocation.overtimeMs == Int64(2 * hour))
        #expect(canvas.allocation.totalMs == canvas.allocation.dayLengthMs)
    }

    @Test("A 23-hour and a 25-hour day sum to their real length, never to a forced 24")
    func dstDaysUseTheirRealLength() {
        let day = utcDay(2026, 8, 24)
        let shift = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [segment(day, plus: 9, to: 18)],
            source: .recorded
        )

        let short = model(
            dayStart: day,
            dayEnd: day.addingTimeInterval(23 * 3_600),
            shifts: [shift]
        )
        let long = model(
            dayStart: day,
            dayEnd: day.addingTimeInterval(25 * 3_600),
            shifts: [shift]
        )

        #expect(short.allocation.dayLengthMs == Int64(23 * hour))
        #expect(short.allocation.totalMs == short.allocation.dayLengthMs)
        #expect(long.allocation.dayLengthMs == Int64(25 * hour))
        #expect(long.allocation.totalMs == long.allocation.dayLengthMs)
        for interval in short.intervals + long.intervals {
            #expect(interval.durationMs >= 0)
        }
        #expect(short.wakingFreeShare >= 0 && short.wakingFreeShare <= 1)
        #expect(long.wakingFreeShare >= 0 && long.wakingFreeShare <= 1)
    }

    @Test("A failed rule expansion leaves the day unclassified instead of padding it to 100%")
    func failedExpansionBecomesUnclassifiedTime() {
        let day = utcDay(2026, 8, 24)
        let complete = model(dayStart: day, shifts: [])
        let incomplete = model(dayStart: day, shifts: [], rulesFailed: true)

        #expect(complete.allocation.unclassifiedMs == 0)
        #expect(complete.allocation.freeMs == Int64(16 * hour))
        #expect(incomplete.allocation.freeMs == 0)
        #expect(incomplete.allocation.unclassifiedMs == Int64(16 * hour))
        #expect(incomplete.allocation.totalMs == incomplete.allocation.dayLengthMs)
        #expect(incomplete.hasIncompleteRules)
    }

    @Test("Sleep is drawn in the longest stretch of non-work time and never on top of work")
    func sleepIsPlacedInFreeSpaceOnly() {
        let day = utcDay(2026, 8, 24)
        let night = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [segment(day, plus: 0, to: 6)],
            source: .recorded
        )
        let canvas = model(dayStart: day, shifts: [night])
        let sleep = canvas.intervals.filter { $0.kind == .sleep }

        #expect(canvas.allocation.sleepMs == Int64(8 * hour))
        #expect(sleep.count == 1)
        // The night worker sleeps after the shift, not through it.
        #expect(sleep[0].startAtMs == day.timeIntervalSince1970 * 1_000 + 6 * hour)
        #expect(sleep[0].source == .sleepEstimate)
        #expect(sleep[0].anchorDayKey == nil)
    }

    @Test("The now line only exists today, and it lands on a whole minute")
    func nowLineExistsOnlyOnToday() {
        let day = utcDay(2026, 8, 24)
        let now = day.addingTimeInterval(14 * 3_600 + 32 * 60 + 47)
        let shift = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [segment(day, plus: 9, to: 18)],
            source: .recorded
        )

        let today = model(dayStart: day, shifts: [shift], isToday: true, now: now)
        let past = model(dayStart: day, shifts: [shift], isToday: false, now: now)

        #expect(past.nowAtMs == nil)
        #expect(past.projectionStartsAtMs == nil)
        let expected = day.timeIntervalSince1970 * 1_000 + (14 * 60 + 32) * 60_000
        #expect(today.nowAtMs == expected)
        #expect(today.projectionStartsAtMs == expected)
        #expect(today.workIntervals.count == 2)
        #expect(today.workIntervals[0].endAtMs == expected)
        #expect(today.workIntervals[0].source == .recorded)
        #expect(today.workIntervals[1].startAtMs == expected)
        #expect(today.workIntervals[1].source == .afterNow)
    }

    @Test("A locked day carries no interval, duration, anchor or source of its own")
    func lockedDayCarriesNothingReal() {
        let day = utcDay(2026, 8, 24)
        let canvas = RecordsDayCanvasModel.locked(
            dayKey: "2026-08-24",
            dayStart: day,
            dayEnd: day.addingTimeInterval(86_400)
        )

        #expect(canvas.isLocked)
        #expect(canvas.intervals.isEmpty)
        #expect(canvas.editableShifts.isEmpty)
        #expect(canvas.allocation.totalMs == 0)
        #expect(canvas.allocation.dayLengthMs == 0)
        #expect(canvas.wakingFreeMs == 0)
        #expect(canvas.source == .locked)
    }

    @Test("A rest day is still editable, and is named by its date rather than by hours")
    func restDaysStayEditable() {
        let day = utcDay(2026, 8, 24)
        let empty = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [],
            source: .rest,
            isEditable: true
        )
        let canvas = model(dayStart: day, shifts: [empty], source: .rest)

        #expect(canvas.editableShifts.map(\.anchorDayKey) == ["2026-08-24"])
        #expect(canvas.editableShifts[0].hasHours == false)
        #expect(canvas.allocation.workMs == 0)
    }

    @Test("A plan or a projection never offers an edit entry")
    func plansAndProjectionsAreNotEditable() {
        let day = utcDay(2026, 8, 24)
        let planned = RecordsDayShift(
            anchorDayKey: "2026-08-24",
            segments: [segment(day, plus: 9, to: 18)],
            source: .planned,
            isEditable: false
        )
        let canvas = model(dayStart: day, shifts: [planned], source: .planned)

        #expect(canvas.editableShifts.isEmpty)
        #expect(canvas.workIntervals.allSatisfy { $0.source == .planned })
        #expect(canvas.source.isEstimated)
    }

    @Test("Every source has words of its own, and estimates are never merely faded")
    func everySourceNamesItself() {
        for source in RecordsDaySource.allCases {
            #expect(!source.titleKey.isEmpty)
        }
        #expect(RecordsDaySource.recorded.isEstimated == false)
        #expect(RecordsDaySource.corrected.isEstimated == false)
        #expect(RecordsDaySource.corrected.isCorrection)
        #expect(RecordsDaySource.scheduleEstimate.isEstimated)
        #expect(RecordsDaySource.afterNow.isEstimated)
        #expect(RecordsDaySource.lifeProjection.isEstimated)
        #expect(RecordsDaySource.planned.isEstimated)
        #expect(RecordsDaySource.sleepEstimate.isEstimated)
    }
}

import Foundation
import Testing
@testable import App

@MainActor
@Test("Metrics use resolved work days and ignore empty rest days")
func recordsMetricsCountWorkdays() {
    let monday = Date(timeIntervalSince1970: 1_787_529_600)
    let work = DayResolution(
        dayKey: "2026-08-24",
        shiftAnchorDate: monday,
        layer: .schedule,
        periodID: nil,
        snapshotID: nil,
        isScheduledWorkday: true,
        segments: [NativeShiftSegment(startAtMs: 0, endAtMs: 8 * 3_600_000)]
    )
    let rest = DayResolution(
        dayKey: "2026-08-25",
        shiftAnchorDate: monday.addingTimeInterval(86_400),
        layer: .schedule,
        periodID: nil,
        snapshotID: nil,
        isScheduledWorkday: false,
        segments: []
    )
    let metrics = RecordsMetrics.summarize(
        days: [work, rest],
        observations: [],
        sleepHours: 8,
        dailySalary: 100,
        salaryEnabled: true
    )
    #expect(metrics.workdayCount == 1)
    #expect(metrics.workDurationMs == 8 * 3_600_000)
    #expect(metrics.longestStreak == 1)
    #expect(metrics.estimatedIncome == 100)
}

@MainActor
@Test("A broken streak resets")
func recordsMetricsStreakResets() {
    let start = Date(timeIntervalSince1970: 1_787_529_600)
    let days = (0..<4).map { offset in
        let work = offset != 2
        return DayResolution(
            dayKey: "2026-08-2\(4 + offset)",
            shiftAnchorDate: start.addingTimeInterval(Double(offset) * 86_400),
            layer: .schedule,
            periodID: nil,
            snapshotID: nil,
            isScheduledWorkday: work,
            segments: work ? [NativeShiftSegment(startAtMs: 0, endAtMs: 1)] : []
        )
    }
    #expect(RecordsMetrics.longestStreak(in: days) == 2)
}

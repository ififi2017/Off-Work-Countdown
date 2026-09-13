import Foundation
import Testing
@testable import App

@Suite("Watch display projection")
struct WatchDisplayProjectionTests {
    @Test("Availability is resolved before content")
    func availabilityFirst() {
        #expect(WatchDisplayProjection.project(nil, nowMs: 200) == .waiting)
        #expect(WatchDisplayProjection.project(package(access: .locked), nowMs: 200) == .locked)
        #expect(WatchDisplayProjection.project(package(access: .unknown), nowMs: 200) == .confirmationRequired)
        #expect(WatchDisplayProjection.project(package(access: .pending, accessUntilMs: 500), nowMs: 200) == .pending)
        #expect(WatchDisplayProjection.project(package(access: .pending), nowMs: 200) == .confirmationRequired)
        // The next-shift preview must end inside the package window, or the package is invalid rather than expired.
        #expect(WatchDisplayProjection.project(package(expiresAtMs: 500, nextStart: 400), nowMs: 500) == .contentExpired)
    }

    @Test("Absolute segments preserve lunch and early finish")
    func earlyFinish() throws {
        let resting = try #require(content(package(shift: shift(finishedAtMs: 650)), at: 550))
        #expect(resting.phase == .resting)
        // 300 of the 500 planned effective ms are worked by lunch; lunch does not count down.
        #expect(resting.remainingMs == 200)
        #expect(resting.effectiveEndAtMs == 650)
        let finished = try #require(content(package(shift: shift(finishedAtMs: 650)), at: 700))
        #expect(finished.phase == .finished)
        #expect(finished.remainingMs == 150)
    }

    @Test("Stopped, unconfigured and rest projections stay distinct")
    func emptyStates() throws {
        let stoppedShift = shift(finishedAtMs: nil)
        let stopped = try #require(content(package(state: .stopped, shift: .init(
            segments: stoppedShift.segments, plannedEndAtMs: stoppedShift.plannedEndAtMs,
            overtimeEndAtMs: nil, finishedAtMs: nil, isRunning: false,
            transitions: stoppedShift.transitions
        )), at: 300))
        #expect(stopped.scheduleState == .stopped)
        #expect(stopped.phase == nil)
        #expect(stopped.remainingMs == nil)
        #expect(stopped.effectiveEndAtMs == nil)
        #expect(stopped.nextShiftStartAtMs == 900)
        let unconfigured = try #require(content(package(state: .notConfigured, shift: nil, nextStart: nil), at: 200))
        #expect(unconfigured.scheduleState == .notConfigured)
        #expect(unconfigured.nextShiftStartAtMs == nil)
    }

    @Test("Timeline contains both expiries and exact shift boundaries")
    func boundaries() {
        let dates = WatchDisplayProjection.timelineDates(
            for: package(access: .active, accessUntilMs: 700, expiresAtMs: 1_000, shift: shift(finishedAtMs: 650)),
            from: Date(timeIntervalSince1970: 0.2), minuteCount: 0
        ).map { Int64(($0.timeIntervalSince1970 * 1_000).rounded()) }
        for expected in [500, 600, 650, 700, 1_000] as [Int64] { #expect(dates.contains(expected)) }

        let pendingDates = WatchDisplayProjection.timelineDates(
            for: package(access: .pending, accessUntilMs: 700),
            from: Date(timeIntervalSince1970: 0.2), minuteCount: 0
        ).map { Int64(($0.timeIntervalSince1970 * 1_000).rounded()) }
        #expect(pendingDates.contains(700))
    }

    @Test("Formats in the package's language and time zone, with units and rounding that match a countdown")
    func formatting() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let nineUTC = Int64(try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 9)))
            .timeIntervalSince1970 * 1_000)
        let shanghai = presentation(locale: "zh-CN", timeZone: "Asia/Shanghai")
        let newYork = presentation(locale: "en-US", timeZone: "America/New_York")
        let spaces: (String) -> String = { $0.replacingOccurrences(of: "\u{202F}", with: " ") }

        // The shift's zone, not the Watch's: 09:00 UTC is 17:00 in Shanghai and 5:00 AM in New York.
        #expect(WatchDisplayFormat.time(nineUTC, shanghai) == "17:00")
        #expect(spaces(WatchDisplayFormat.time(nineUTC, newYork)) == "5:00 AM")

        let remaining: Int64 = 3 * 3_600_000 + 40 * 60_000 + 55_500
        #expect(WatchDisplayFormat.clock(remaining, showsSeconds: true, shanghai) == "3:40:55")
        #expect(WatchDisplayFormat.clock(remaining, showsSeconds: false, shanghai) == "3:41")
        #expect(WatchDisplayFormat.clock(1, showsSeconds: false, shanghai) == "0:01")
        #expect(WatchDisplayFormat.shortDuration(3 * 3_600_000 + 17 * 60_000 + 1, newYork) == "3h 18m")
        #expect(WatchDisplayFormat.shortDuration(45 * 60_000, newYork) == "45m")
        #expect(WatchDisplayFormat.percent(59.6, newYork) == "60%")
        #expect(WatchDisplayFormat.fill("剩余 {{duration}}", ["duration": "3小时"]) == "剩余 3小时")
    }

    @Test("Each state's footnote names the time that explains its countdown")
    func footnotes() {
        let labels = presentation(locale: "en", timeZone: "UTC")
        func content(_ phase: WatchShiftPhase?, end: Int64? = 800, boundary: Int64? = 600, next: Int64? = 900) -> WatchDisplayContent {
            .init(scheduleState: .scheduled, phase: phase, remainingMs: 100, progress: 50, effectiveEndAtMs: end,
                  nextBoundaryAtMs: boundary, nextShiftStartAtMs: next, presentation: labels)
        }
        #expect(WatchDisplayFormat.footnote(for: content(.working)) == .init(key: "watchOffAt", atMs: 800, includesWeekday: false))
        #expect(WatchDisplayFormat.footnote(for: content(.overtime)) == .init(key: "watchOvertimeUntil", atMs: 800, includesWeekday: false))
        #expect(WatchDisplayFormat.footnote(for: content(.resting)) == .init(key: "watchBackAt", atMs: 600, includesWeekday: false))
        #expect(WatchDisplayFormat.footnote(for: content(.before)) == .init(key: "watchNextShiftAt", atMs: 600, includesWeekday: false))
        #expect(WatchDisplayFormat.footnote(for: content(.finished)) == .init(key: "watchOffAt", atMs: 800, includesWeekday: false))
        #expect(WatchDisplayFormat.footnote(for: content(nil)) == .init(key: "watchNextShiftAt", atMs: 900, includesWeekday: true))
        #expect(WatchDisplayFormat.footnote(for: content(nil, next: nil)) == nil)
    }

    private func presentation(locale: String, timeZone: String) -> WatchPresentationV1 {
        .init(localeIdentifier: locale, timeZoneIdentifier: timeZone, workingLabel: "Working", lunchLabel: "Lunch",
              restingLabel: "Resting", overtimeLabel: "Overtime", finishedLabel: "Finished")
    }

    private func content(_ package: WatchSnapshotPackageV1, at nowMs: Int64) -> WatchDisplayContent? {
        guard case .content(let value) = WatchDisplayProjection.project(package, nowMs: nowMs) else { return nil }
        return value
    }

    private func shift(finishedAtMs: Int64?) -> WatchShiftProjectionV1 {
        .init(segments: [.init(startAtMs: 200, endAtMs: 500), .init(startAtMs: 600, endAtMs: 800)],
              plannedEndAtMs: 800, overtimeEndAtMs: nil, finishedAtMs: finishedAtMs, isRunning: finishedAtMs == nil,
              transitions: [.init(atMs: 200, state: .working), .init(atMs: 500, state: .lunch),
                            .init(atMs: 600, state: .working), .init(atMs: finishedAtMs ?? 800, state: .finished)])
    }

    private func package(
        access: WatchAccessProjectionV1.Status = .lifetime, accessUntilMs: Int64? = nil,
        expiresAtMs: Int64 = 1_000, state: WatchShiftContentV1.ScheduleState = .scheduled,
        shift: WatchShiftProjectionV1? = nil, nextStart: Int64? = 900
    ) -> WatchSnapshotPackageV1 {
        let grants = access == .active || access == .lifetime
        return .init(schemaVersion: 1, sourceGeneration: "phone", revision: 1, generatedAtMs: 100,
                     expiresAtMs: expiresAtMs,
                     access: .init(schemaVersion: 1, revision: 1, verifiedAtMs: 50, status: access,
                                   validUntilMs: accessUntilMs),
                     content: grants ? .init(scheduleState: state, shift: shift,
                        nextShift: nextStart.map { .init(startAtMs: $0, validUntilMs: $0) },
                        presentation: .init(localeIdentifier: "en", timeZoneIdentifier: "UTC",
                            workingLabel: "Working", lunchLabel: "Lunch", restingLabel: "Resting",
                            overtimeLabel: "Overtime", finishedLabel: "Finished")) : nil)
    }
}

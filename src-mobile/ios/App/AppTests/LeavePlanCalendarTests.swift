import Foundation
import Testing
@testable import App

@Suite("Leave plan month preview")
struct LeavePlanCalendarTests {
    private func day(_ key: String) throws -> Int {
        try #require(ExtendedScheduleResolver.dayNumber(dayKey: key))
    }

    private func proposal(from: String, through: String, early: String? = nil) throws -> LeavePlanProposal {
        let first = try day(from)
        let last = try day(through)
        let items: [LeavePlanItem]
        if let early {
            items = [LeavePlanItem(dayNumber: try day(early), dayKey: early, portion: .secondHalf,
                                   segments: [], uses: [], role: .earlyDeparture)]
        } else {
            items = []
        }
        return LeavePlanProposal(firstRestDayNumber: first, lastRestDayNumber: last,
                                 firstRestDayKey: from, lastRestDayKey: through,
                                 items: items, uses: [], lastShiftEndAtMs: nil, nextShiftStartAtMs: nil,
                                 dayKinds: Array(repeating: .rest, count: last - first + 1), caveats: [])
    }

    @Test("Every week-start preference produces a full six-row month", arguments: Array(1...7))
    func completeMonth(firstWeekday: Int) throws {
        let page = LeavePlanCalendarPage(containing: try day("2026-10-24"), firstWeekday: firstWeekday)
        #expect(page.firstDayNumber == (try day("2026-10-01")))
        #expect(page.days.count == 42)
        #expect(((page.days[0] + 4) % 7 + 7) % 7 == firstWeekday - 1)
        #expect(page.days.filter(page.contains) == Array(try day("2026-10-01")...day("2026-10-31")))
        #expect(page.days == Array(page.days[0]..<(page.days[0] + 42)))
    }

    @Test("October to November option exposes both complete months")
    func crossMonth() throws {
        let plan = try proposal(from: "2026-10-24", through: "2026-11-01")
        let months = LeavePlanCalendarPage.months(for: plan)
        #expect(months == [try day("2026-10-01"), try day("2026-11-01")])
        let coverage = LeavePlanCalendarPage.coverage(of: plan)
        #expect(coverage == (try day("2026-10-24"))...(try day("2026-11-01")))
        for day in coverage {
            #expect(months.contains { LeavePlanCalendarPage(containing: $0, firstWeekday: 2).contains(day) })
        }
    }

    @Test("Early departure belongs to the preview even in the preceding year")
    func halfDayAcrossYear() throws {
        let plan = try proposal(from: "2027-01-01", through: "2027-01-09", early: "2026-12-31")
        #expect(LeavePlanCalendarPage.months(for: plan) == [try day("2026-12-01"), try day("2027-01-01")])
        #expect(LeavePlanCalendarPage.coverage(of: plan).lowerBound == (try day("2026-12-31")))
    }

    @Test("Leap February includes the 29th without leaking March into the month")
    func leapMonth() throws {
        let page = LeavePlanCalendarPage(containing: try day("2028-02-29"), firstWeekday: 2)
        #expect(page.days.filter(page.contains).count == 29)
        #expect(page.contains(try day("2028-02-29")))
        #expect(!page.contains(try day("2028-03-01")))
    }
}

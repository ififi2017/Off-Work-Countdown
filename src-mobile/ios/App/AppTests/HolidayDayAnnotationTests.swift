import Foundation
import Testing
@testable import App

@Suite("Calendar holiday annotations")
struct HolidayDayAnnotationTests {
    @Test("Makeup workdays retain the festival they belong to")
    func makeupFestival() throws {
        let holiday = try #require(HolidayDayAnnotation.make(dayKey: "2027-02-05", region: "CN", language: "zh-CN"))
        let makeup = try #require(HolidayDayAnnotation.make(dayKey: "2027-02-14", region: "CN", language: "zh-CN"))
        #expect(holiday.name == "春节")
        #expect(makeup.name == holiday.name)
        #expect(!holiday.isMakeupWorkday)
        #expect(makeup.isMakeupWorkday)
        #expect(holiday.isEstimated && makeup.isEstimated)
        let official = try #require(HolidayDayAnnotation.make(dayKey: "2026-10-10", region: "CN", language: "zh-CN"))
        #expect(official.name == "国庆节")
        #expect(official.isMakeupWorkday && !official.isEstimated)
    }

    @Test("Other regions show their own holiday names and no makeup label")
    func otherRegion() throws {
        let day = try #require(HolidayDayAnnotation.make(dayKey: "2026-02-11", region: "JP", language: "ja"))
        #expect(day.name == "建国記念の日")
        #expect(!day.isMakeupWorkday && !day.isEstimated)
    }

    @Test("An ordinary date, disabled calendar and uncovered year have no annotation")
    func noHoliday() {
        #expect(HolidayDayAnnotation.make(dayKey: "2027-02-16", region: "CN", language: "zh-CN") == nil)
        #expect(HolidayDayAnnotation.make(dayKey: "2027-02-05", region: nil, language: "zh-CN") == nil)
        #expect(HolidayDayAnnotation.make(dayKey: "2027-02-05", region: "", language: "zh-CN") == nil)
        #expect(HolidayDayAnnotation.make(dayKey: "2028-01-01", region: "CN", language: "zh-CN") == nil)
    }
}

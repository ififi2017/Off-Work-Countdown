import Foundation
import Testing
@testable import App

@Suite("Overtime sheet title and button follow what the sheet is doing")
struct OvertimeSheetModeTests {
    private let plannedEnd = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func addsBeforeClockOffWithoutOvertime() {
        let mode = OvertimeSheetMode(hasOvertime: false, plannedEnd: plannedEnd, now: plannedEnd.addingTimeInterval(-60))
        #expect(mode == .add)
        #expect(mode.titleKey == "overtimeTitle")
        #expect(mode.confirmKey == "confirmOvertime")
    }

    @Test func adjustsWhenOvertimeIsSet() {
        for now in [plannedEnd.addingTimeInterval(-60), plannedEnd.addingTimeInterval(3_600)] {
            let mode = OvertimeSheetMode(hasOvertime: true, plannedEnd: plannedEnd, now: now)
            #expect(mode == .adjust)
            #expect(mode.titleKey == "adjustOvertime")
            #expect(mode.confirmKey == "saveAction")
        }
    }

    @Test func logsAfterClockOffWithoutOvertime() {
        let mode = OvertimeSheetMode(hasOvertime: false, plannedEnd: plannedEnd, now: plannedEnd)
        #expect(mode == .log)
        #expect(mode.titleKey == "logOvertimeTitle")
        #expect(mode.confirmKey == "saveAction")
    }

    @Test func addsWithoutAPlannedEnd() {
        #expect(OvertimeSheetMode(hasOvertime: false, plannedEnd: nil, now: plannedEnd) == .add)
    }
}

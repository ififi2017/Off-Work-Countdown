import CoreGraphics
import Foundation
import Testing
@testable import App

@Suite("Schedule calendar paint selection")
struct ScheduleCalendarPaintSelectionTests {
    @Test("A stroke visits each day once; a later stroke restores its previous assignment")
    func strokeDeduplicationAndUndo() {
        let brush = UUID()
        let previous = UUID()
        var selection = ScheduleCalendarPaintSelection()
        selection.choose(brush)
        #expect(selection.edit(dayKey: "2026-10-01", currentShiftID: previous) == .shift(brush))
        #expect(selection.edit(dayKey: "2026-10-01", currentShiftID: brush) == nil)
        #expect(selection.edit(dayKey: "2026-10-02", currentShiftID: nil) == .shift(brush))
        #expect(selection.edit(dayKey: "2026-10-01", currentShiftID: brush) == nil)
        selection.endStroke()
        #expect(selection.edit(dayKey: "2026-10-01", currentShiftID: brush) == .shift(previous))
        #expect(selection.edit(dayKey: "2026-10-02", currentShiftID: brush) == .followPattern)
    }

    @Test("An existing brush assignment can be cleared, and switching brush preserves the current draft")
    func existingAssignmentAndBrushChanges() {
        let first = UUID()
        let second = UUID()
        var selection = ScheduleCalendarPaintSelection()
        selection.choose(first)
        #expect(selection.edit(dayKey: "2026-10-01", currentShiftID: first) == .followPattern)
        #expect(selection.edit(dayKey: "2026-10-02", currentShiftID: nil) == .shift(first))
        selection.choose(second)
        #expect(selection.edit(dayKey: "2026-10-02", currentShiftID: first) == .shift(second))
        selection.endStroke()
        #expect(selection.edit(dayKey: "2026-10-02", currentShiftID: second) == .shift(first))
        selection.choose(second)
        #expect(selection.brushID == nil)
        #expect(selection.edit(dayKey: "2026-10-03", currentShiftID: nil) == nil)
    }

    @Test("Fast swipes include crossed cells in finger order and ignore gutters")
    func swipeGeometry() {
        let frames = [
            "01": CGRect(x: 0, y: 0, width: 40, height: 40),
            "02": CGRect(x: 45, y: 0, width: 40, height: 40),
            "03": CGRect(x: 90, y: 0, width: 40, height: 40),
            "04": CGRect(x: 0, y: 45, width: 40, height: 40),
        ]
        #expect(ScheduleCalendarPaintSelection.crossedDays(
            from: CGPoint(x: 10, y: 20), to: CGPoint(x: 120, y: 20), frames: frames
        ) == ["01", "02", "03"])
        #expect(ScheduleCalendarPaintSelection.crossedDays(
            from: CGPoint(x: 120, y: 20), to: CGPoint(x: 10, y: 20), frames: frames
        ) == ["03", "02", "01"])
        #expect(ScheduleCalendarPaintSelection.crossedDays(
            from: CGPoint(x: 42, y: 0), to: CGPoint(x: 42, y: 80), frames: frames
        ).isEmpty)
        #expect(ScheduleCalendarPaintSelection.crossedDays(
            from: CGPoint(x: 10, y: 20), to: CGPoint(x: 10, y: 20), frames: frames
        ) == ["01"])
    }
}

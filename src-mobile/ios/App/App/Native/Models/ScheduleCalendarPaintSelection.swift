import CoreGraphics
import Foundation

/// Draft-only selection and undo for the calendar brush; it never saves a roster.
nonisolated struct ScheduleCalendarPaintSelection {
    private(set) var brushID: UUID?
    private var originals: [String: RosterDayEdit] = [:]
    private var visited: Set<String> = []

    mutating func choose(_ id: UUID?) {
        brushID = brushID == id ? nil : id
        originals.removeAll()
        endStroke()
    }

    mutating func endStroke() {
        visited.removeAll()
    }

    /// A day changes once per stroke, including when the finger doubles back.
    mutating func edit(dayKey: String, currentShiftID: UUID?) -> RosterDayEdit? {
        guard let brushID, visited.insert(dayKey).inserted else { return nil }
        if currentShiftID == brushID {
            return originals.removeValue(forKey: dayKey) ?? .followPattern
        }
        originals[dayKey] = currentShiftID.map(RosterDayEdit.shift) ?? .followPattern
        return .shift(brushID)
    }

    /// Include cells crossed between samples so a quick swipe does not skip dates.
    static func crossedDays(from start: CGPoint, to end: CGPoint, frames: [String: CGRect]) -> [String] {
        var intersections: [(key: String, entry: CGFloat)] = []
        for (key, frame) in frames {
            var entry: CGFloat = 0
            var exit: CGFloat = 1
            var intersects = true
            for axis in 0..<2 {
                let origin: CGFloat = axis == 0 ? start.x : start.y
                let delta: CGFloat = axis == 0 ? end.x - start.x : end.y - start.y
                let lower: CGFloat = axis == 0 ? frame.minX : frame.minY
                let upper: CGFloat = axis == 0 ? frame.maxX : frame.maxY
                if delta == 0 {
                    if origin < lower || origin > upper { intersects = false; break }
                } else {
                    let first = (lower - origin) / delta
                    let last = (upper - origin) / delta
                    entry = max(entry, min(first, last))
                    exit = min(exit, max(first, last))
                    if entry > exit { intersects = false; break }
                }
            }
            if intersects { intersections.append((key, entry)) }
        }
        return intersections.sorted {
            $0.entry == $1.entry ? $0.key < $1.key : $0.entry < $1.entry
        }.map(\.key)
    }
}

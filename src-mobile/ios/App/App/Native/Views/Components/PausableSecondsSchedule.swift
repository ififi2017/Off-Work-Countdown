import SwiftUI

/// Once a second, or one entry and silence while the surface is off screen.
///
/// Swapping the `TimelineView` for a static branch when its tab lost focus
/// replaced the whole timer page on every tab switch, and built it again on
/// the way back. Pausing keeps the page in place; resuming starts a fresh
/// schedule, so the first entry is the current second.
struct PausableSecondsSchedule: TimelineSchedule {
    let isPaused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        isPaused
            ? AnySequence(CollectionOfOne(startDate))
            : AnySequence(PeriodicTimelineSchedule(from: startDate, by: 1).entries(from: startDate, mode: mode))
    }
}

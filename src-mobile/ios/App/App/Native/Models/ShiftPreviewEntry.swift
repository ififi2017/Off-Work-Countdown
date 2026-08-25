import Foundation

/// One line of the "what today looks like" preview shown before a countdown
/// starts.
///
/// Deliberately not `UpcomingTimelineEvent`. That type is one row per firing,
/// which is right for the running screen — it answers "what happens next" — but
/// listing an hourly micro-break across a nine-hour shift produced eight
/// identical rows and pushed the shift times off screen. A preview needs one
/// row per *kind* of thing, so its height does not grow with the shift.
struct ShiftPreviewEntry: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case shiftStart
        case lunchStart
        case lunchEnd
        case health
        case milestone
        case liveActivity
        /// The standing "off-work reminder" row, as opposed to the Live
        /// Activity's own timed appearance.
        case offWorkReminder
        case schedule
        case shiftEnd
    }

    /// Explicit, because milestones contribute several rows of the same kind.
    let id: String
    let kind: Kind
    let title: String
    /// The recurrence or span — "1 h 30 m", "60 min", "15 min early". Nil when
    /// there is nothing to add, such as a start time that has rolled over to
    /// the next working day and is described by its own weekday instead.
    let detail: String?
    /// When it first happens. Nil when there is nothing meaningful to point at.
    let date: Date?
    /// Where tapping goes. Nil for the shift's own boundaries, which are edited
    /// in the hero directly above.
    let route: AppRoute?
}

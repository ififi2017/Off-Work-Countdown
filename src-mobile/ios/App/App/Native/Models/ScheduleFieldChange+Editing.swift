import Foundation

// MARK: - Editing a schedule without committing on every keystroke

extension ScheduleFieldChange {
    var isEmpty: Bool { self == ScheduleFieldChange() }

    /// Drops every field that already matches what the store holds.
    ///
    /// Without this, opening a picker and putting the value back would leave
    /// the page "dirty": Save lit up over nothing, and leaving asked whether a
    /// change that is not a change should include today.
    func settled(against store: PreferencesStore, at date: Date = .now) -> ScheduleFieldChange {
        var next = self
        if next.startMinutes == store.startMinutes { next.startMinutes = nil }
        if next.endMinutes == store.endMinutes { next.endMinutes = nil }
        if next.workdays == store.workdays { next.workdays = nil }
        if next.scheduleMode == store.scheduleMode { next.scheduleMode = nil }
        if next.lunchEnabled == store.lunchEnabled { next.lunchEnabled = nil }
        if next.lunchStartMinutes == store.lunchStartMinutes { next.lunchStartMinutes = nil }
        if next.lunchDurationMinutes == store.lunchDurationMinutes { next.lunchDurationMinutes = nil }
        if next.alternatingWeekType == store.alternatingWeekType { next.alternatingWeekType = nil }
        if next.alternatingWeekendWorkday == store.alternatingWeekendWorkday {
            next.alternatingWeekendWorkday = nil
        }
        if next.rotationWorkDays == store.rotationWorkDays { next.rotationWorkDays = nil }
        if next.rotationRestDays == store.rotationRestDays { next.rotationRestDays = nil }
        if next.rotationCycleDay == store.rotationCycleDay(at: date) { next.rotationCycleDay = nil }
        return next
    }
}


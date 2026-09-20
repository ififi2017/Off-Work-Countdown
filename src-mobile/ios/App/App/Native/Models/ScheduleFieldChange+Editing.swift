import Foundation

// MARK: - Editing a schedule without committing on every keystroke

extension ScheduleFieldChange {
    var isEmpty: Bool { self == ScheduleFieldChange() }

    mutating func restorePatternAfterFreePreview() {
        guard !materializedRosterDays.isEmpty else { return }
        rosterEdits = rosterEdits?.filter { !materializedRosterDays.contains($0.key) }
        if rosterEdits?.isEmpty == true { rosterEdits = nil }
        materializedRosterDays.removeAll()
    }

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
        if next.extendedScheduleEnabled == store.isExtendedScheduleEnabled { next.extendedScheduleEnabled = nil }
        if next.extendedContent == store.extendedScheduleContent { next.extendedContent = nil }
        if let edits = next.rosterEdits {
            let stored = store.handSetDays
            let changed = edits.filter { key, edit in
                switch edit {
                case .shift(let id): stored[key] != id
                case .followPattern: stored[key] != nil
                }
            }
            next.rosterEdits = changed.isEmpty ? nil : changed
        }
        next.materializedRosterDays.formIntersection(Set(next.rosterEdits?.keys.map { $0 } ?? []))
        // The cycle day is only "unchanged" against the anchor it will land on.
        // Switching to rotation re-anchors to today, and a new work or rest
        // length changes what day N means, so with either in the same edit the
        // current day says nothing and the chosen one must survive.
        if next.scheduleMode == nil, next.rotationWorkDays == nil, next.rotationRestDays == nil,
           next.rotationCycleDay == store.rotationCycleDay(at: date) {
            next.rotationCycleDay = nil
        }
        return next
    }
}

import Foundation

extension OffWorkStore {
    /// Today's plan expressed as template slots, for prefilling the editor.
    ///
    /// "Save today as a usual day" cannot be the whole story on its own. The
    /// planner refuses to edit an elapsed block, so a template captured at
    /// 15:00 is missing every morning slot — while `applyFocusTemplate`, which
    /// maps purely by index, is perfectly happy to write those same morning
    /// blocks on another day. The template could describe a morning the user
    /// was never allowed to draw. Prefilling an editor closes that gap.
    func focusTemplateDraftFromToday(at date: Date = .now) -> [FocusTemplateSlot] {
        guard let shift = focusCanvasShift(at: date)?.snapshot else { return [] }
        let dayKey = RecordJSON.dayKey(shift.startDate, calendar: recordsCalendar)
        let assignments = focusPlanning.plans[dayKey]?.assignments ?? []
        var taskKeys: [UUID: UUID] = [:]
        return focusTemplateBlocks(at: date).compactMap { block in
            guard block.kind == .task else { return nil }
            guard let assignment = assignments.first(where: { $0.blockStartAtMs == block.startAtMs })
            else { return nil }
            let taskKey = assignment.taskID.map { taskID -> UUID in
                if let existing = taskKeys[taskID] { return existing }
                let created = UUID()
                taskKeys[taskID] = created
                return created
            }
            return FocusTemplateSlot(
                blockIndex: block.index,
                kind: assignment.kind,
                taskKey: taskKey,
                taskTitle: assignment.taskTitle,
                taskIcon: assignment.taskIcon
            )
        }
    }

    /// The blocks a template is drawn against: the same grid as the canvas,
    /// with the clock taken out. Every block is editable here, which is the
    /// entire reason the editor exists.
    func focusTemplateBlocks(at date: Date = .now) -> [FocusWorkBlock] {
        guard let shift = focusCanvasShift(at: date)?.snapshot else { return [] }
        return FocusPlanner.workBlocks(segments: shift.segments, settings: focusTimerSettings)
    }

    /// Saves slots the user actually drew, rather than deriving them from a
    /// day that may be half spent.
    @discardableResult
    func saveFocusTemplate(name: String, slots: [FocusTemplateSlot]) -> FocusTemplate? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plus.isAuthorized, !trimmed.isEmpty, !slots.isEmpty else { return nil }
        let now = Date.now
        let template = FocusTemplate(
            id: UUID(),
            name: trimmed,
            slots: slots.sorted { $0.blockIndex < $1.blockIndex },
            createdAt: now,
            updatedAt: now
        )
        appendFocusTemplate(template)
        return template
    }

    @discardableResult
    func updateFocusTemplate(_ template: FocusTemplate, name: String, slots: [FocusTemplateSlot]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plus.isAuthorized, !trimmed.isEmpty else { return false }
        return replaceFocusTemplate(
            id: template.id,
            name: trimmed,
            slots: slots.sorted { $0.blockIndex < $1.blockIndex }
        )
    }

    /// How many of a template's slots the shift being drawn can actually hold.
    ///
    /// Slots are numbered against a grid, so a shorter shift silently drops
    /// the tail. Saying how many are lost is cheaper than pretending the
    /// template is shape-independent.
    func focusTemplateFit(_ template: FocusTemplate, at date: Date = .now) -> (fits: Int, dropped: Int) {
        let available = focusTemplateBlocks(at: date).count
        let fits = template.slots.count { $0.blockIndex < available }
        return (fits, template.slots.count - fits)
    }
}

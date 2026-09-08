import Foundation

extension OffWorkStore {
    /// Capture task order and estimates without retaining the day’s clock times.
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

    /// Available focus and recovery blocks from the shared shift projection.
    func focusTemplateBlocks(at date: Date = .now) -> [FocusWorkBlock] {
        guard let shift = focusCanvasShift(at: date)?.snapshot else { return [] }
        return FocusPlanner.workBlocks(segments: shift.segments, settings: focusTimerSettings)
    }

    /// Keep the existing archive format, normalizing new writes into task order.
    @discardableResult
    func saveFocusTemplate(name: String, slots: [FocusTemplateSlot]) -> FocusTemplate? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plus.isAuthorized, !trimmed.isEmpty, !FocusTemplate.tasks(from: slots).isEmpty else { return nil }
        let now = Date.now
        let template = FocusTemplate(
            id: UUID(),
            name: trimmed,
            slots: FocusTemplate.slots(from: FocusTemplate.tasks(from: slots)),
            createdAt: now,
            updatedAt: now
        )
        appendFocusTemplate(template)
        return template
    }

    @discardableResult
    func updateFocusTemplate(_ template: FocusTemplate, name: String, slots: [FocusTemplateSlot], at date: Date = .now) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plus.isAuthorized, !trimmed.isEmpty else { return false }
        return replaceFocusTemplate(
            id: template.id,
            name: trimmed,
            slots: FocusTemplate.slots(from: FocusTemplate.tasks(from: slots)),
            at: date
        )
    }

    /// Complete tasks that fit, and rounds omitted from the tail for this shift.
    func focusTemplateFit(_ template: FocusTemplate, at date: Date = .now) -> (fits: Int, dropped: Int) {
        let fits = template.placedSlots(in: focusTemplateBlocks(at: date)).count
        return (fits, template.tasks.reduce(0) { $0 + $1.pomodoros } - fits)
    }
}

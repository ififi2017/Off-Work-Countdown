import SwiftUI

struct FocusTaskEditSheet: View {
    let focus: FocusStore
    let text: AppText
    let task: FocusTask
    @State private var draft: FocusTaskEditorDraft
    @State private var isSubmitting = false
    @Environment(\.dismiss) private var dismiss

    init(focus: FocusStore, text: AppText, task: FocusTask) {
        self.focus = focus
        self.text = text
        self.task = task
        var value = FocusTaskEditorDraft()
        value.select(task, favorite: false)
        value.isFavorite = focus.savedFocusFavorite(title: task.title, icon: task.icon) != nil
        value.pomodoros = max(task.estimatedPomodoros, focus.protectedFocusPomodoros(task))
        _draft = State(initialValue: value)
    }

    var body: some View {
        let minimum = max(1, focus.protectedFocusPomodoros(task))
        let proposed = focus.editedFocusTaskBlocks(task, pomodoros: draft.pomodoros)
        let scheduled = task.scheduledStartAt != nil
        FocusTaskEditorShell(title: focus.t("focusEditTask"), cancelTitle: focus.t("cancel"), saveTitle: focus.t("saveAction"),
            canSave: draft.canSave && (draft.pomodoros == task.estimatedPomodoros || proposed != nil),
            onCancel: { dismiss() }, onSave: {
                let submitted = draft
                let command = focus.editFocusTask(task, title: submitted.title, icon: submitted.icon,
                                                   pomodoros: submitted.pomodoros,
                                                   isFavorite: submitted.isFavorite)
                if let saved = command.immediateResult {
                    if saved { dismiss() }
                    return
                }
                isSubmitting = true
                Task { @MainActor in
                    let saved = await command.value
                    isSubmitting = false
                    if saved,
                       draft.title == submitted.title,
                       draft.icon == submitted.icon,
                       draft.pomodoros == submitted.pomodoros,
                       draft.isFavorite == submitted.isFavorite {
                        dismiss()
                    }
                }
            }) {
                FocusTaskEditorFields(focus: focus, text: text, draft: $draft,
                    destination: task.scheduledStartAt.map {
                        focus.t("focusFavoriteLands", values: ["time": text.formatDate($0) + " · " + focus.formatTime($0)])
                    } ?? focus.t("focusLeaveUnscheduled"),
                    finish: proposed?.last.map { Date(timeIntervalSince1970: Double($0.endAtMs) / 1_000) },
                    showsFinish: scheduled, minimumPomodoros: minimum)
                Button(focus.t("focusDeleteTask"), role: .destructive) {
                    let command = focus.deleteFocusTask(task)
                    if let deleted = command.immediateResult {
                        if deleted { dismiss() }
                        return
                    }
                    isSubmitting = true
                    Task { @MainActor in
                        let deleted = await command.value
                        isSubmitting = false
                        if deleted { dismiss() }
                    }
                }
                .buttonStyle(OWCSecondaryButtonStyle())
                .disabled(focus.activeFocusSession()?.taskID == task.id)
            }
            .disabled(isSubmitting)
            .interactiveDismissDisabled(isSubmitting)
    }
}

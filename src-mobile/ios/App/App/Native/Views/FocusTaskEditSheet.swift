import SwiftUI

struct FocusTaskEditSheet: View {
    let store: OffWorkStore
    let task: FocusTask
    @State private var draft: FocusTaskEditorDraft
    @Environment(\.dismiss) private var dismiss

    init(store: OffWorkStore, task: FocusTask) {
        self.store = store
        self.task = task
        var value = FocusTaskEditorDraft()
        value.select(task, favorite: false)
        value.isFavorite = store.savedFocusFavorite(title: task.title, icon: task.icon) != nil
        value.pomodoros = max(task.estimatedPomodoros, store.protectedFocusPomodoros(task))
        _draft = State(initialValue: value)
    }

    var body: some View {
        let minimum = max(1, store.protectedFocusPomodoros(task))
        let proposed = store.editedFocusTaskBlocks(task, pomodoros: draft.pomodoros)
        let scheduled = task.scheduledStartAt != nil
        FocusTaskEditorShell(store: store, saveTitle: store.t("saveAction"), titleKey: "focusEditTask",
            canSave: draft.canSave && (draft.pomodoros == task.estimatedPomodoros || proposed != nil),
            onCancel: { dismiss() }, onSave: {
                if store.editFocusTask(task, title: draft.title, icon: draft.icon,
                                       pomodoros: draft.pomodoros, isFavorite: draft.isFavorite) {
                    dismiss()
                }
            }) {
                FocusTaskEditorFields(store: store, draft: $draft,
                    destination: task.scheduledStartAt.map {
                        store.t("focusFavoriteLands", values: ["time": store.formatDate($0) + " · " + store.formatTime($0)])
                    } ?? store.t("focusLeaveUnscheduled"),
                    finish: proposed?.last.map { Date(timeIntervalSince1970: Double($0.endAtMs) / 1_000) },
                    showsFinish: scheduled, minimumPomodoros: minimum)
                Button(store.t("focusDeleteTask"), role: .destructive) {
                    if store.deleteFocusTask(task) { dismiss() }
                }
                .buttonStyle(OWCSecondaryButtonStyle())
                .disabled(store.activeFocusSession()?.taskID == task.id)
            }
    }
}

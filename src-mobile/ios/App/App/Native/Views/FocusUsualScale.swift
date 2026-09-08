import SwiftUI

/// Synthetic examples only; previewing Plus never reads or edits saved tasks.
struct FocusLockedUsualScale: View {
    let store: OffWorkStore

    private let samples: [(key: String, icon: FocusTaskIcon)] = [
        ("focusDemoWriting", .writing),
        ("focusDemoMessages", .communication),
        ("focusDemoLearning", .study)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                OWCSectionHeader(title: store.t("focusFavorites"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(samples, id: \.key) { sample in
                            Button { store.presentedRoute = .plus } label: {
                                Label(store.t(sample.key), systemImage: sample.icon.systemName)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(OWCDesign.primary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(OWCDesign.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                OWCSectionHeader(title: store.t("focusUsualDays"))
                OWCGroupCard {
                    Button { store.presentedRoute = .plus } label: {
                        OWCRow(
                            icon: "star.fill",
                            title: store.t("focusUsualDayDefaultName"),
                            subtitle: store.t("focusTemplateSlots", values: ["count": "4"])
                                + " · " + store.t("focusTemplateAuto"),
                            isLast: true
                        ) {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(OWCDesign.tertiary)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
            }
            Text(store.t("focusCadenceNote"))
                .font(.caption)
                .foregroundStyle(OWCDesign.secondary)
                .padding(.horizontal, 6)
        }
    }
}

/// What the editor was opened for.
struct FocusTemplateDraft: Identifiable {
    var id: UUID { template?.id ?? newID }
    /// nil when this is a new template being drawn from today.
    var template: FocusTemplate?
    var newID = UUID()
    var name: String
    var slots: [FocusTemplateSlot]


}

/// The third scale. Favourites and usual days finally sit together — a usual
/// day used to be a section at the bottom of the *second* scale's page, which
/// put a cross-day thing inside today.
struct FocusUsualScale: View {
    let store: OffWorkStore
    let model: FocusDayCanvasModel
    var onPlaceFavorite: (FocusTask) -> Void
    var onEditTemplate: (FocusTemplateDraft) -> Void

    @State private var showsCapacityWarning = false

    private var favorites: [FocusTask] { store.favoriteFocusTasks() }
    private var templates: [FocusTemplate] { store.focusPlanning.templates }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            favoritesSection
            templatesSection
            Text(store.t("focusCadenceNote"))
                .font(.caption)
                .foregroundStyle(OWCDesign.secondary)
                .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                OWCSectionHeader(title: store.t("focusFavorites"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(favorites) { task in
                            Button { onPlaceFavorite(task) } label: {
                                Label(task.title, systemImage: "star.fill")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(OWCDesign.primary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(OWCDesign.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            // Says where it will land, so the tap is not a
                            // guess. The old chip copied the task into a list
                            // further down the page and looked inert.
                            .accessibilityHint(landingHint)
                            .contextMenu {
                                Button(store.t("focusRemoveFavorite"), systemImage: "trash", role: .destructive) {
                                    store.toggleFocusFavorite(task)
                                }
                            }
                        }
                }
                Text(landingHint)
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var landingHint: String {
        guard let next = model.nextEmptyBlock else { return store.t("focusNoEmptyBlockShort") }
        let start = Date(timeIntervalSince1970: Double(next.startAtMs) / 1_000)
        return store.t("focusFavoriteLands", values: ["time": store.formatTime(start)])
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OWCSectionHeader(title: store.t("focusUsualDays"))
            OWCGroupCard {
                Button {
                    onEditTemplate(FocusTemplateDraft(
                        template: nil,
                        name: store.t("focusUsualDayDefaultName"),
                        slots: store.focusTemplateDraftFromToday()
                    ))
                } label: {
                    OWCRow(
                        icon: "square.and.arrow.down",
                        title: store.t("focusSaveTodayAsUsual"),
                        subtitle: store.t("focusSaveTodayAsUsualDetail"),
                        isLast: templates.isEmpty,
                        centersVertically: true
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.tertiary)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())

                ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                    Button {
                        onEditTemplate(FocusTemplateDraft(
                            template: template,
                            name: template.name,
                            slots: template.slots
                        ))
                    } label: {
                        OWCRow(
                            icon: store.focusPlanning.defaultTemplateID == template.id ? "star.fill" : "square.grid.2x2",
                            title: template.name,
                            subtitle: templateSubtitle(template),
                            isLast: index == templates.count - 1,
                            centersVertically: true
                        ) {
                            HStack(spacing: 0) {
                                if store.focusTemplateFit(template).dropped > 0 {
                                    Button { showsCapacityWarning = true } label: {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundStyle(.orange)
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(store.t("focusTemplateCapacityWarning"))
                                }
                                Menu {
                                    Button(store.t("focusApplyTemplate")) {
                                        _ = store.applyFocusTemplate(template)
                                    }
                                    Button(store.t(
                                        store.focusPlanning.defaultTemplateID == template.id
                                            ? "focusUnsetDefaultTemplate"
                                            : "focusSetDefaultTemplate"
                                    )) {
                                        store.setDefaultFocusTemplate(
                                            store.focusPlanning.defaultTemplateID == template.id ? nil : template
                                        )
                                    }
                                    Button(store.t("focusTemplateDelete"), role: .destructive) {
                                        store.deleteFocusTemplate(template)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundStyle(OWCDesign.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel(store.t("moreActions"))
                            }
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
            }
        }
        .alert(store.t("focusTemplateCapacityWarning"), isPresented: $showsCapacityWarning) {
            Button(store.t("close"), role: .cancel) { }
        } message: {
            Text(store.t("focusTemplateSequenceNote"))
        }
    }

    private func templateSubtitle(_ template: FocusTemplate) -> String {
        let filled = template.slots.count { $0.kind == .task && $0.taskTitle != nil }
        var parts = [store.t("focusTemplateSlots", values: ["count": "\(filled)"])]
        if store.focusPlanning.defaultTemplateID == template.id {
            parts.append(store.t("focusTemplateAuto"))
        }
        let fit = store.focusTemplateFit(template)
        if fit.dropped > 0 {
            parts.append(store.t("focusTemplateDropped", values: ["count": "\(fit.dropped)"]))
        }
        return parts.joined(separator: " · ")
    }
}

/// Templates edit task order and estimates; actual times belong to the day
/// where that list is applied, so a shift edit cannot turn a task into a break.
struct FocusTemplateEditorView: View {
    let store: OffWorkStore
    @State private var draft: FocusTemplateDraft
    @State private var tasks: [FocusTemplateTask]
    @State private var editingTask: FocusTemplateTask?
    @State private var taskDraft = FocusTaskEditorDraft()
    @State private var favoriteChanges: [String: Bool] = [:]
    @Environment(\.dismiss) private var dismiss

    init(store: OffWorkStore, draft: FocusTemplateDraft) {
        self.store = store
        _draft = State(initialValue: draft)
        _tasks = State(initialValue: FocusTemplate.tasks(from: draft.slots))
    }

    private var omittedTaskIDs: Set<String> {
        let count = FocusTemplate.fittingTaskCount(tasks, in: store.focusTemplateBlocks())
        return Set(tasks.dropFirst(count).map(\.id))
    }

    var body: some View {
        let omittedTaskIDs = omittedTaskIDs
        NavigationStack {
            List {
                Section {
                    TextField(store.t("focusUsualDayName"), text: $draft.name)
                }
                Section {
                    ForEach(tasks) { task in
                        Button { edit(task) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: task.icon.systemName)
                                    .foregroundStyle(OWCDesign.accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).foregroundStyle(OWCDesign.primary)
                                    Text(store.t("focusEstimateDetail", values: [
                                        "count": "\(task.pomodoros)",
                                        "minutes": "\(store.focusTimerSettings.normalized.focusMinutes)"
                                    ]))
                                    .font(.footnote).foregroundStyle(OWCDesign.secondary)
                                    if omittedTaskIDs.contains(task.id) {
                                        Label {
                                            Text(store.t("focusTemplateTaskDoesNotFit"))
                                                .foregroundStyle(OWCDesign.secondary)
                                        } icon: {
                                            Image(systemName: "exclamationmark.triangle")
                                                .foregroundStyle(OWCDesign.accent)
                                        }
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }.buttonStyle(.plain)
                    }
                    .onMove { tasks.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { tasks.remove(atOffsets: $0) }
                    Button {
                        edit(FocusTemplateTask(taskKey: UUID(), legacyIndex: tasks.count,
                                               title: "", icon: .focus, pomodoros: 1))
                    } label: {
                        Label(store.t("focusNewTask"), systemImage: "plus")
                    }
                    .deleteDisabled(true)
                    .moveDisabled(true)
                } footer: {
                    Text(store.t("focusTemplateSequenceNote"))
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(store.t("focusUsualDay"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("saveAction"), action: save)
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tasks.isEmpty)
                }
            }
        }
        .sheet(item: $editingTask) { task in
            FocusTaskEditorShell(store: store, saveTitle: store.t("saveAction"),
                titleKey: tasks.contains(where: { $0.id == task.id }) ? "focusEditTask" : "focusNewTask",
                canSave: taskDraft.canSave, onCancel: { editingTask = nil }, onSave: {
                    var updated = task
                    updated.title = taskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.icon = taskDraft.icon
                    updated.pomodoros = taskDraft.pomodoros
                    if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = updated }
                    else { tasks.append(updated) }
                    favoriteChanges[task.id] = taskDraft.isFavorite
                    editingTask = nil
                }) {
                    FocusTaskEditorFields(store: store, draft: $taskDraft,
                        destination: store.t("focusUsualDay"), finish: nil, showsDate: false, showsFinish: false)
                }
        }
    }

    private func edit(_ task: FocusTemplateTask) {
        taskDraft = FocusTaskEditorDraft()
        taskDraft.title = task.title
        taskDraft.icon = task.icon
        taskDraft.pomodoros = task.pomodoros
        taskDraft.isFavorite = favoriteChanges[task.id]
            ?? (store.savedFocusFavorite(title: task.title, icon: task.icon) != nil)
        editingTask = task
    }

    private func save() {
        for task in tasks {
            guard let favorite = favoriteChanges[task.id] else { continue }
            if favorite {
                store.saveFocusFavorite(title: task.title, pomodoros: task.pomodoros, icon: task.icon)
            } else if let saved = store.savedFocusFavorite(title: task.title, icon: task.icon) {
                store.toggleFocusFavorite(saved)
            }
        }
        let slots = FocusTemplate.slots(from: tasks)
        if let template = draft.template {
            _ = store.updateFocusTemplate(template, name: draft.name, slots: slots)
        } else {
            _ = store.saveFocusTemplate(name: draft.name, slots: slots)
        }
        dismiss()
    }
}

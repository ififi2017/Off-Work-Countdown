import SwiftUI

/// Synthetic examples only; previewing Plus never reads or edits saved tasks.
struct FocusLockedUsualScale: View {
    @Environment(SceneState.self) private var scene
    let focus: FocusStore

    private let samples: [(key: String, icon: FocusTaskIcon)] = [
        ("focusDemoWriting", .writing),
        ("focusDemoMessages", .communication),
        ("focusDemoLearning", .study)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                OWCSectionHeader(title: focus.t("focusFavorites"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(samples, id: \.key) { sample in
                            Button { scene.presentedRoute = .plus } label: {
                                Label(focus.t(sample.key), systemImage: sample.icon.systemName)
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
                OWCSectionHeader(title: focus.t("focusUsualDays"))
                OWCGroupCard {
                    Button { scene.presentedRoute = .plus } label: {
                        OWCRow(
                            icon: "star.fill",
                            title: focus.t("focusUsualDayDefaultName"),
                            subtitle: focus.t("focusTemplateSlots", values: ["count": "4"])
                                + " · " + focus.t("focusTemplateAuto"),
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
            Text(focus.t("focusCadenceNote"))
                .font(.caption)
                .foregroundStyle(OWCDesign.secondary)
                .padding(.horizontal, 6)
        }
    }
}

/// The third scale. Favourites and usual days finally sit together — a usual
/// day used to be a section at the bottom of the *second* scale's page, which
/// put a cross-day thing inside today.
struct FocusUsualScale: View {
    let focus: FocusStore
    let model: FocusDayCanvasModel
    var onPlaceFavorite: (FocusTask) -> Void
    var onEditTemplate: (FocusTemplateDraft) -> Void

    @State private var showsCapacityWarning = false

    private var favorites: [FocusTask] { focus.favoriteFocusTasks() }
    private var templates: [FocusTemplate] { focus.focusPlanning.templates }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            favoritesSection
            templatesSection
            Text(focus.t("focusCadenceNote"))
                .font(.caption)
                .foregroundStyle(OWCDesign.secondary)
                .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                OWCSectionHeader(title: focus.t("focusFavorites"))
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
                                Button(focus.t("focusRemoveFavorite"), systemImage: "trash", role: .destructive) {
                                    _ = focus.toggleFocusFavorite(task)
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
        guard let next = model.nextEmptyBlock else { return focus.t("focusNoEmptyBlockShort") }
        let start = Date(timeIntervalSince1970: Double(next.startAtMs) / 1_000)
        return focus.t("focusFavoriteLands", values: ["time": focus.formatTime(start)])
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OWCSectionHeader(title: focus.t("focusUsualDays"))
            OWCGroupCard {
                Button {
                    onEditTemplate(FocusTemplateDraft(
                        template: nil,
                        name: focus.t("focusUsualDayDefaultName"),
                        slots: focus.focusTemplateDraftFromToday()
                    ))
                } label: {
                    OWCRow(
                        icon: "square.and.arrow.down",
                        title: focus.t("focusSaveTodayAsUsual"),
                        subtitle: focus.t("focusSaveTodayAsUsualDetail"),
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
                            icon: focus.focusPlanning.defaultTemplateID == template.id ? "star.fill" : "square.grid.2x2",
                            title: template.name,
                            subtitle: templateSubtitle(template),
                            isLast: index == templates.count - 1,
                            centersVertically: true
                        ) {
                            HStack(spacing: 0) {
                                if focus.focusTemplateFit(template).dropped > 0 {
                                    Button { showsCapacityWarning = true } label: {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundStyle(OWCDesign.warning)
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(focus.t("focusTemplateCapacityWarning"))
                                }
                                Menu {
                                    Button(focus.t("focusApplyTemplate")) {
                                        _ = focus.applyFocusTemplate(template)
                                    }
                                    Button(focus.t(
                                        focus.focusPlanning.defaultTemplateID == template.id
                                            ? "focusUnsetDefaultTemplate"
                                            : "focusSetDefaultTemplate"
                                    )) {
                                        _ = focus.setDefaultFocusTemplate(
                                            focus.focusPlanning.defaultTemplateID == template.id ? nil : template
                                        )
                                    }
                                    Button(focus.t("focusTemplateDelete"), role: .destructive) {
                                        _ = focus.deleteFocusTemplate(template)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundStyle(OWCDesign.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel(focus.t("moreActions"))
                            }
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
            }
        }
        .alert(focus.t("focusTemplateCapacityWarning"), isPresented: $showsCapacityWarning) {
            Button(focus.t("close"), role: .cancel) { }
        } message: {
            Text(focus.t("focusTemplateSequenceNote"))
        }
    }

    private func templateSubtitle(_ template: FocusTemplate) -> String {
        let filled = template.slots.count { $0.kind == .task && $0.taskTitle != nil }
        var parts = [focus.t("focusTemplateSlots", values: ["count": "\(filled)"])]
        if focus.focusPlanning.defaultTemplateID == template.id {
            parts.append(focus.t("focusTemplateAuto"))
        }
        let fit = focus.focusTemplateFit(template)
        if fit.dropped > 0 {
            parts.append(focus.t("focusTemplateDropped", values: ["count": "\(fit.dropped)"]))
        }
        return parts.joined(separator: " · ")
    }
}

/// Templates edit task order and estimates; actual times belong to the day
/// where that list is applied, so a shift edit cannot turn a task into a break.
struct FocusTemplateEditorView: View {
    let focus: FocusStore
    let text: AppText
    @State private var draft: FocusTemplateDraft
    @State private var tasks: [FocusTemplateTask]
    @State private var editingTask: FocusTemplateTask?
    @State private var taskDraft = FocusTaskEditorDraft()
    @State private var favoriteChanges: [String: Bool] = [:]
    @State private var isSubmitting = false
    @Environment(\.dismiss) private var dismiss

    init(focus: FocusStore, text: AppText, draft: FocusTemplateDraft) {
        self.focus = focus
        self.text = text
        _draft = State(initialValue: draft)
        _tasks = State(initialValue: FocusTemplate.tasks(from: draft.slots))
    }

    private var omittedTaskIDs: Set<String> {
        let count = FocusTemplate.fittingTaskCount(tasks, in: focus.focusTemplateBlocks())
        return Set(tasks.dropFirst(count).map(\.id))
    }

    var body: some View {
        let omittedTaskIDs = omittedTaskIDs
        let remaining = FocusTemplate.remainingPomodoros(tasks, in: focus.focusTemplateBlocks())
        NavigationStack {
            List {
                Section {
                    TextField(focus.t("focusUsualDayName"), text: $draft.name)
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
                                    Text(focus.t("focusEstimateDetail", values: [
                                        "count": "\(task.pomodoros)",
                                        "minutes": "\(focus.focusTimerSettings.normalized.focusMinutes)"
                                    ]))
                                    .font(.footnote).foregroundStyle(OWCDesign.secondary)
                                    if omittedTaskIDs.contains(task.id) {
                                        Label {
                                            Text(focus.t("focusTemplateTaskDoesNotFit"))
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
                        Label(focus.t("focusNewTask"), systemImage: "plus")
                    }
                    .disabled(remaining == 0)
                    .deleteDisabled(true)
                    .moveDisabled(true)
                    Text(focus.t("focusTemplateRemainingPomodoros", values: ["count": "\(remaining)"]))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .deleteDisabled(true)
                        .moveDisabled(true)
                } footer: {
                    Text(focus.t("focusTemplateSequenceNote"))
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(focus.t("focusUsualDay"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(focus.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(focus.t("saveAction"), action: save)
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tasks.isEmpty)
                }
            }
        }
        .disabled(isSubmitting)
        .interactiveDismissDisabled(isSubmitting)
        .sheet(item: $editingTask) { task in
            let editingCapacity = FocusTemplate.remainingPomodoros(
                tasks, in: focus.focusTemplateBlocks(), excluding: task.id
            )
            FocusTaskEditorShell(title: focus.t(tasks.contains(where: { $0.id == task.id }) ? "focusEditTask" : "focusNewTask"),
                cancelTitle: focus.t("cancel"), saveTitle: focus.t("saveAction"),
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
                    FocusTaskEditorFields(focus: focus, text: text, draft: $taskDraft,
                        destination: focus.t("focusUsualDay"), finish: nil, showsDate: false, showsFinish: false,
                        maximumPomodoros: editingCapacity,
                        capacityNote: focus.t("focusTemplateRemainingPomodoros", values: ["count": "\(editingCapacity)"]))
                }
        }
    }

    private func edit(_ task: FocusTemplateTask) {
        taskDraft = FocusTaskEditorDraft()
        taskDraft.title = task.title
        taskDraft.icon = task.icon
        taskDraft.pomodoros = task.pomodoros
        taskDraft.isFavorite = favoriteChanges[task.id]
            ?? (focus.savedFocusFavorite(title: task.title, icon: task.icon) != nil)
        editingTask = task
    }

    private func save() {
        let submittedTasks = tasks
        let submittedChanges = favoriteChanges
        let submittedName = draft.name
        let submittedTemplate = draft.template
        isSubmitting = true
        Task { @MainActor in
            for task in submittedTasks {
                guard let favorite = submittedChanges[task.id] else { continue }
                if favorite {
                    await focus.saveFocusFavorite(title: task.title, pomodoros: task.pomodoros, icon: task.icon).value
                } else if let saved = focus.savedFocusFavorite(title: task.title, icon: task.icon) {
                    await focus.toggleFocusFavorite(saved).value
                }
            }
            let slots = FocusTemplate.slots(from: submittedTasks)
            let saved: Bool
            if let template = submittedTemplate {
                saved = await focus.updateFocusTemplate(template, name: submittedName, slots: slots).value
            } else {
                saved = await focus.saveFocusTemplate(name: submittedName, slots: slots).value != nil
            }
            isSubmitting = false
            guard saved, tasks == submittedTasks, favoriteChanges == submittedChanges,
                  draft.name == submittedName, draft.template?.id == submittedTemplate?.id else { return }
            dismiss()
        }
    }
}

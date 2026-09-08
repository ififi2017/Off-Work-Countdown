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

    func taskIndices(at index: Int) -> [Int] {
        guard let key = slots.first(where: { $0.blockIndex == index })?.taskKey else { return [index] }
        return slots.filter { $0.kind == .task && $0.taskKey == key }.map(\.blockIndex).sorted()
    }

    func availableTaskIndices(at index: Int, blocks: [FocusWorkBlock]) -> [Int] {
        var indices = taskIndices(at: index)
        for block in blocks where block.kind == .task && block.index > (indices.last ?? index) {
            guard !slots.contains(where: { $0.blockIndex == block.index }) else { break }
            indices.append(block.index)
        }
        return indices
    }

    mutating func setTask(at index: Int, count: Int, title: String, icon: FocusTaskIcon, blocks: [FocusWorkBlock]) {
        let oldIndices = taskIndices(at: index)
        let indices = availableTaskIndices(at: index, blocks: blocks)
        guard count > 0, count <= indices.count else { return }
        let key = slots.first(where: { $0.blockIndex == index })?.taskKey ?? UUID()
        slots.removeAll { oldIndices.contains($0.blockIndex) }
        slots.append(contentsOf: indices.prefix(count).map {
            FocusTemplateSlot(blockIndex: $0, kind: .task, taskKey: key, taskTitle: title, taskIcon: icon)
        })
    }
}

/// The third scale. Favourites and usual days finally sit together — a usual
/// day used to be a section at the bottom of the *second* scale's page, which
/// put a cross-day thing inside today.
struct FocusUsualScale: View {
    let store: OffWorkStore
    let model: FocusDayCanvasModel
    var onPlaceFavorite: (FocusTask) -> Void
    var onEditTemplate: (FocusTemplateDraft) -> Void

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
                    .buttonStyle(OWCRowButtonStyle())
                }
            }
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

/// A usual day gets its own canvas, drawn against a whole shift with no
/// "now" on it.
///
/// Editing today cannot produce a whole day once today is half over: the
/// planner refuses elapsed blocks. Using today as the mould was the source of
/// the problem, so the mould here is the shift shape alone.
struct FocusTemplateEditorView: View {
    let store: OffWorkStore
    @State var draft: FocusTemplateDraft
    @State private var editingBlock: FocusDayCanvasModel.Block?
    @State private var taskDraft = FocusTaskEditorDraft()
    @State private var favoriteChanges: [UUID: Bool] = [:]
    @Environment(\.dismiss) private var dismiss

    private func templateCanvas(from base: FocusDayCanvasModel) -> FocusDayCanvasModel {
        var model = base
        model.nowAtMs = nil
        model.tasks = []
        model.overflow = []
        model.blocks = model.blocks.map { block in
            var next = block
            // No elapsed state and no current block: a usual day has no clock,
            // which is exactly what makes the morning reachable.
            next.state = .future
            let slot = draft.slots.first { $0.blockIndex == block.index }
            next.taskID = nil
            next.taskTitle = slot?.taskTitle
            next.taskIcon = slot?.taskIcon
            next.isUserBreak = block.kind == .task && slot?.kind == .breakTime
            return next
        }
        return model
    }

    var body: some View {
        // Same reason as the canvas page: each of these is a rule-bundle round
        // trip, so they are resolved once and passed down.
        let blocks = store.focusTemplateBlocks()
        let canvas = templateCanvas(from: store.focusDayCanvas())
        let emptyWorkBlocks = canvas.blocks.count { $0.kind == .task && !$0.isUserBreak && $0.taskTitle == nil }
        return NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    OWCGroupCard {
                        OWCRow(
                            icon: "textformat",
                            title: store.t("focusUsualDayName"),
                            isLast: true
                        ) {
                            TextField(store.t("focusUsualDayDefaultName"), text: $draft.name)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 180)
                        }
                    }

                    Text(shapeNote(blocks))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.horizontal, 6)

                    FocusBandView(
                        store: store,
                        model: canvas,
                        selectedBlock: .constant(nil)
                    ) { block in
                        taskDraft = FocusTaskEditorDraft()
                        editingBlock = block

                    }

                    if emptyWorkBlocks > 0 {
                        Text(store.t("focusUsualDayEmptyNote", values: ["count": "\(emptyWorkBlocks)"]))
                            .font(.caption)
                            .foregroundStyle(OWCDesign.secondary)
                            .padding(.horizontal, 6)
                    }
                    Text(store.t("focusUsualDayCadenceLock"))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.horizontal, 6)
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 14)
                .padding(.bottom, OWCDesign.detailBottomInset)
            }
            .background(OWCDesign.page)
            .navigationTitle(store.t("focusUsualDay"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(store.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("saveAction"), action: save)
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || draft.slots.isEmpty)
                }
            }

        }
        .sheet(item: $editingBlock) { block in
            let occupied = draft.slots.contains { $0.blockIndex == block.index }
            if occupied {
                NavigationStack {
                    VStack(spacing: 14) {
                        Text(block.taskTitle ?? store.t("focusBreak")).font(.headline)
                        Button(store.t("focusBlockClear"), role: .destructive) {
                            draft.slots.removeAll { $0.blockIndex == block.index }
                            editingBlock = nil
                        }.buttonStyle(OWCSecondaryButtonStyle())
                    }.padding(OWCDesign.pageInset)
                    .toolbar { ToolbarItem(placement: .topBarLeading) {
                        Button(store.t("close")) { editingBlock = nil }
                    } }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            } else {
                let available = draft.availableTaskIndices(at: block.index, blocks: blocks)
                let finalIndex = available.prefix(taskDraft.pomodoros).last
                let finish = available.count >= taskDraft.pomodoros
                    ? blocks.first { $0.index == finalIndex }?.end : nil
                FocusTaskEditorShell(store: store, saveTitle: store.t("saveAction"),
                                     canSave: taskDraft.canSave && finish != nil,
                                     onCancel: { editingBlock = nil }, onSave: {
                    setSlot(block.index, title: taskDraft.title, icon: taskDraft.icon)
                    editingBlock = nil
                }) {
                    FocusTaskEditorFields(store: store, draft: $taskDraft,
                        destination: store.t("focusUsualDay") + " · " + store.formatTime(Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)),
                        finish: finish, showsDate: false)
                    Button(store.t("focusBlockMakeBreak")) {
                        draft.slots.append(FocusTemplateSlot(blockIndex: block.index, kind: .breakTime,
                                                            taskKey: nil, taskTitle: nil, taskIcon: nil))
                        editingBlock = nil
                    }.buttonStyle(OWCSecondaryButtonStyle())
                }
            }
        }
    }

    private func shapeNote(_ blocks: [FocusWorkBlock]) -> String {
        let workBlocks = blocks.count { $0.kind == .task }
        guard let first = blocks.first, let last = blocks.last else {
            return store.t("focusNoShift")
        }
        return store.t("focusUsualDayShape", values: [
            "start": store.formatTime(first.start),
            "end": store.formatTime(last.end),
            "count": "\(workBlocks)"
        ])
    }

    private func setSlot(_ blockIndex: Int, title: String, icon: FocusTaskIcon) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let previousKey = draft.slots.first(where: { $0.blockIndex == blockIndex })?.taskKey
        draft.setTask(at: blockIndex, count: taskDraft.pomodoros, title: trimmed, icon: icon, blocks: store.focusTemplateBlocks())
        if let key = previousKey ?? draft.slots.first(where: { $0.blockIndex == blockIndex })?.taskKey {
            favoriteChanges[key] = taskDraft.isFavorite
        }
    }

    private func save() {
        let blocks = store.focusTemplateBlocks()
        // Keep recovery slots the user drew inside task blocks as well.
        var slots = draft.slots.filter { slot in blocks.contains { $0.index == slot.blockIndex && $0.kind == .task } }
        slots.append(contentsOf: blocks.filter { $0.kind == .breakTime }.map {
            FocusTemplateSlot(blockIndex: $0.index, kind: .breakTime, taskKey: nil, taskTitle: nil, taskIcon: nil)
        })
        for (key, favorite) in favoriteChanges {
            let taskSlots = slots.filter { $0.kind == .task && $0.taskKey == key }
            guard let slot = taskSlots.first, let title = slot.taskTitle else { continue }
            let icon = slot.taskIcon ?? .focus
            if favorite {
                store.saveFocusFavorite(title: title, pomodoros: taskSlots.count, icon: icon)
            } else if let saved = store.savedFocusFavorite(title: title, icon: icon) {
                store.toggleFocusFavorite(saved)
            }
        }
        if let template = draft.template {
            _ = store.updateFocusTemplate(template, name: draft.name, slots: slots)
        } else {
            _ = store.saveFocusTemplate(name: draft.name, slots: slots)
        }
        dismiss()
    }
}

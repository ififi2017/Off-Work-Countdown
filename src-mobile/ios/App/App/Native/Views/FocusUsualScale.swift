import SwiftUI

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
                OWCSectionHeader(title: store.t("focusFavoritesPlace"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(favorites) { task in
                            Button { onPlaceFavorite(task) } label: {
                                Label(task.title, systemImage: task.icon.systemName)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(OWCDesign.primary)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 44)
                                    .background(OWCDesign.card, in: Capsule())
                                    .overlay(Capsule().strokeBorder(OWCDesign.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            // Says where it will land, so the tap is not a
                            // guess. The old chip copied the task into a list
                            // further down the page and looked inert.
                            .accessibilityHint(landingHint)
                        }
                    }
                    .padding(.horizontal, 2)
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
                        isLast: templates.isEmpty
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
                            isLast: index == templates.count - 1
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
    @State private var editingIndex: Int?
    @State private var newTitle = ""
    @State private var newIcon = FocusTaskIcon.focus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            return next
        }
        return model
    }

    var body: some View {
        // Same reason as the canvas page: each of these is a rule-bundle round
        // trip, so they are resolved once and passed down.
        let blocks = store.focusTemplateBlocks()
        let canvas = templateCanvas(from: store.focusDayCanvas())
        let emptyWorkBlocks = canvas.blocks.count { $0.kind == .task && $0.taskTitle == nil }
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
                        editingIndex = block.index
                        newTitle = draft.slots.first { $0.blockIndex == block.index }?.taskTitle ?? ""
                        newIcon = draft.slots.first { $0.blockIndex == block.index }?.taskIcon ?? .focus
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
            .sheet(item: Binding(
                get: { editingIndex.map { FocusEditableSlot(blockIndex: $0) } },
                set: { if $0 == nil { editingIndex = nil } }
            )) { slot in
                slotSheet(slot.blockIndex)
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

    private func slotSheet(_ blockIndex: Int) -> some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField(store.t("focusBlockNewPlaceholder"), text: $newTitle)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                        .background(
                            OWCDesign.control,
                            in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
                        )
                    FocusTaskIconPicker(store: store, selection: $newIcon)
                    Button(store.t("saveAction")) {
                        setSlot(blockIndex, title: newTitle, icon: newIcon)
                        editingIndex = nil
                    }
                    .buttonStyle(OWCPrimaryButtonStyle())
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(store.t("focusBlockClear"), role: .destructive) {
                        draft.slots.removeAll { $0.blockIndex == blockIndex }
                        editingIndex = nil
                    }
                    .buttonStyle(OWCSecondaryButtonStyle())
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 14)
            }
            .background(OWCDesign.page)
            .navigationTitle(store.t("focusBlockWhat"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func setSlot(_ blockIndex: Int, title: String, icon: FocusTaskIcon) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft.slots.removeAll { $0.blockIndex == blockIndex }
        draft.slots.append(FocusTemplateSlot(
            blockIndex: blockIndex,
            kind: .task,
            taskKey: UUID(),
            taskTitle: trimmed,
            taskIcon: icon
        ))
    }

    private func save() {
        // Break slots come from the cadence, not from the user, so they are
        // rebuilt here rather than carried in the draft.
        var slots = draft.slots.filter { $0.kind == .task }
        slots.append(contentsOf: store.focusTemplateBlocks().filter { $0.kind == .breakTime }.map {
            FocusTemplateSlot(blockIndex: $0.index, kind: .breakTime, taskKey: nil, taskTitle: nil, taskIcon: nil)
        })
        if let template = draft.template {
            _ = store.updateFocusTemplate(template, name: draft.name, slots: slots)
        } else {
            _ = store.saveFocusTemplate(name: draft.name, slots: slots)
        }
        dismiss()
    }
}

private struct FocusEditableSlot: Identifiable {
    let blockIndex: Int
    var id: Int { blockIndex }
}

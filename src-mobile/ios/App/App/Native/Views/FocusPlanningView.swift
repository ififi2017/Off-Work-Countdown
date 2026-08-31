import SwiftUI

struct FocusPlanningView: View {
    let store: OffWorkStore
    @State private var selectedBlock: FocusWorkBlock?
    @State private var showsTemplateName = false
    @State private var templateName = ""
    @State private var savedFeedback = 0
    @State private var changedFeedback = 0
    @Environment(\.colorSchemeContrast) private var contrast

    private var blocks: [FocusWorkBlock] { store.focusWorkBlocks() }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intro

                if blocks.isEmpty {
                    emptyState
                } else {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        ForEach(Array(blockGroups.enumerated()), id: \.offset) { _, group in
                            blockGroup(group, at: timeline.date)
                        }
                    }
                    templatesSection
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("focusPlanTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedBlock) { block in
            FocusBlockAssignmentSheet(store: store, block: block) {
                changedFeedback += 1
                selectedBlock = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(store.t("focusTemplateSave"), isPresented: $showsTemplateName) {
            TextField(store.t("focusTemplateName"), text: $templateName)
            Button(store.t("focusTemplateSave")) {
                if store.saveFocusTemplate(name: templateName) != nil { savedFeedback += 1 }
                templateName = ""
            }
            Button(store.t("cancel"), role: .cancel) { templateName = "" }
        } message: {
            Text(store.t("focusTemplateSaveBody"))
        }
        .sensoryFeedback(.success, trigger: savedFeedback)
        .sensoryFeedback(.selection, trigger: changedFeedback)
        .task { _ = store.applyDefaultFocusTemplateIfNeeded() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.t("focusPlanIntroTitle"))
                .font(.title3.weight(.semibold))
            Text(
                store.t(
                    "focusPlanIntroBody",
                    values: ["minutes": store.formatCount(store.focusTimerSettings.normalized.focusMinutes)]
                )
            )
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(store.t("focusPlanUnavailable"), systemImage: "calendar.badge.exclamationmark")
                    .font(.body.weight(.medium))
                Text(
                    store.t(
                        "focusPlanUnavailableBody",
                        values: ["minutes": store.formatCount(store.focusTimerSettings.normalized.focusMinutes)]
                    )
                )
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var blockGroups: [[FocusWorkBlock]] {
        blocks.reduce(into: []) { groups, block in
            guard let last = groups.last?.last,
                  abs(block.start.timeIntervalSince(last.end)) < 1
            else {
                groups.append([block])
                return
            }
            groups[groups.count - 1].append(block)
        }
    }

    private func blockGroup(_ group: [FocusWorkBlock], at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let first = group.first, let last = group.last {
                Text(OWCText.ltrRange(store.formatTime(first.start), store.formatTime(last.end)))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92, maximum: 132), spacing: 9)],
                alignment: .leading,
                spacing: 9
            ) {
                ForEach(group) { block in
                    blockButton(block, at: date)
                }
            }
        }
    }

    private func blockButton(_ block: FocusWorkBlock, at date: Date) -> some View {
        let assignment = store.focusAssignment(for: block)
        let isBreak = assignment?.kind == .breakTime
        let isElapsed = block.end <= date
        let isCurrent = block.start <= date && date < block.end
        let tint = isBreak ? Color.mint : OWCDesign.accent
        return Button { selectedBlock = block } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(store.formatTime(block.start))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                Image(systemName: isBreak
                    ? "cup.and.saucer.fill"
                    : (assignment?.taskIcon?.systemName ?? "plus"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(assignment == nil ? OWCDesign.tertiary : tint)
                Text(isBreak
                    ? store.t("focusBreak")
                    : (assignment?.taskTitle ?? store.t("focusPlanOpenBlock")))
                    .font(.caption.weight(assignment == nil ? .regular : .medium))
                    .foregroundStyle(assignment == nil ? OWCDesign.secondary : OWCDesign.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                isElapsed
                    ? OWCDesign.control
                    : (assignment == nil ? OWCDesign.control : tint.opacity(0.10)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isCurrent
                            ? OWCDesign.accent
                            : (assignment == nil || isElapsed ? OWCDesign.separator : tint.opacity(0.42)),
                        lineWidth: isCurrent
                            ? (contrast == .increased ? 2.5 : 2)
                            : (contrast == .increased ? 1.5 : 1)
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isElapsed {
                    Image(systemName: "clock.fill")
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.tertiary)
                        .padding(11)
                        .accessibilityHidden(true)
                } else if isCurrent {
                    Image(systemName: "record.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.accent)
                        .padding(11)
                        .accessibilityHidden(true)
                }
            }
            .saturation(isElapsed ? 0.1 : 1)
            .opacity(isElapsed ? 0.62 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(blockAccessibilityLabel(
            block,
            assignment: assignment,
            isElapsed: isElapsed,
            isCurrent: isCurrent
        ))
        .accessibilityHint(isElapsed ? store.t("focusPlanElapsed") : "")
        // A block whose end is already in the past is history, not an editable
        // slot. Keep it visible for orientation but prevent the assignment
        // sheet from opening; VoiceOver still receives the elapsed state above.
        .disabled(isElapsed)
    }

    private func blockAccessibilityLabel(
        _ block: FocusWorkBlock,
        assignment: FocusPlanAssignment?,
        isElapsed: Bool,
        isCurrent: Bool
    ) -> String {
        let title = assignment?.kind == .breakTime
            ? store.t("focusBreak")
            : (assignment?.taskTitle ?? store.t("focusPlanOpenBlock"))
        let timeState = isElapsed
            ? store.t("focusPlanElapsed")
            : (isCurrent ? store.t("focusPlanCurrent") : nil)
        return [store.formatTime(block.start), title, timeState]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: store.t("focusTemplates"))
            OWCGroupCard {
                Button {
                    templateName = store.t("focusTemplateDefaultName")
                    showsTemplateName = true
                } label: {
                    OWCRow(icon: "square.and.arrow.down", title: store.t("focusTemplateSave"), isLast: store.focusPlanning.templates.isEmpty) {
                        Image(systemName: "plus")
                            .foregroundStyle(OWCDesign.accent)
                            .frame(width: 44, height: 44)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())

                ForEach(Array(store.focusPlanning.templates.enumerated()), id: \.element.id) { index, template in
                    Button {
                        if store.applyFocusTemplate(template) { changedFeedback += 1 }
                    } label: {
                        OWCRow(
                            icon: store.focusPlanning.defaultTemplateID == template.id ? "star.fill" : "square.grid.3x3.fill",
                            title: template.name,
                            subtitle: store.t(
                                "focusTemplateBlockCount",
                                values: ["count": store.formatCount(template.slots.count)]
                            ),
                            isLast: index == store.focusPlanning.templates.count - 1,
                            centersVertically: true
                        ) {
                            Menu {
                                Button {
                                    store.setDefaultFocusTemplate(
                                        store.focusPlanning.defaultTemplateID == template.id ? nil : template
                                    )
                                } label: {
                                    Label(
                                        store.t(
                                            store.focusPlanning.defaultTemplateID == template.id
                                                ? "focusTemplateRemoveDefault"
                                                : "focusTemplateSetDefault"
                                        ),
                                        systemImage: store.focusPlanning.defaultTemplateID == template.id
                                            ? "star.slash"
                                            : "star"
                                    )
                                }
                                Button(role: .destructive) {
                                    store.deleteFocusTemplate(template)
                                } label: {
                                    Label(store.t("focusTemplateDelete"), systemImage: "trash")
                                }
                            } label: {
                                Label(store.t("focusTemplates"), systemImage: "ellipsis")
                                    .labelStyle(.iconOnly)
                                    .frame(width: 44, height: 44)
                            }
                            .foregroundStyle(OWCDesign.secondary)
                            .accessibilityLabel(store.t("focusTemplates"))
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
            }
        }
    }
}

private struct FocusBlockAssignmentSheet: View {
    let store: OffWorkStore
    let block: FocusWorkBlock
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var tasks: [FocusTask] {
        store.focusTasksForToday().filter { $0.completedAt == nil && $0.deletedAt == nil }
    }

    private var assignment: FocusPlanAssignment? { store.focusAssignment(for: block) }

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(
                        OWCText.ltrRange(store.formatTime(block.start), store.formatTime(block.end))
                    )
                    .font(.title3.weight(.semibold).monospacedDigit())

                    OWCGroupCard {
                        Button { chooseBreak() } label: {
                            OWCRow(icon: "cup.and.saucer.fill", title: store.t("focusBreak"), isLast: tasks.isEmpty) {
                                Image(systemName: assignment?.kind == .breakTime ? "checkmark" : "")
                                    .foregroundStyle(OWCDesign.accent)
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())

                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            Button { choose(task) } label: {
                                OWCRow(
                                    icon: task.icon.systemName,
                                    title: task.title,
                                    subtitle: store.t(
                                        "focusTaskProgress",
                                        values: [
                                            "count": store.formatCount(store.completedFocusBlocks(for: task)),
                                            "total": store.formatCount(max(1, task.estimatedPomodoros)),
                                        ]
                                    ),
                                    isLast: index == tasks.count - 1,
                                    centersVertically: true
                                ) {
                                    Image(systemName: assignment?.taskID == task.id ? "checkmark" : "")
                                        .foregroundStyle(OWCDesign.accent)
                                }
                            }
                            .buttonStyle(OWCRowButtonStyle())
                        }
                    }

                    if assignment != nil {
                        Button(role: .destructive) {
                            store.clearFocusBlock(block)
                            onChanged()
                            dismiss()
                        } label: {
                            Label(store.t("focusPlanClearBlock"), systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }

                    if tasks.isEmpty {
                        Text(store.t("focusPlanAddTasksFirst"))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 14)
            }
            .background(OWCDesign.page)
            .navigationTitle(store.t("focusAssignBlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("close")) { dismiss() }
                }
            }
        }
    }

    private func choose(_ task: FocusTask) {
        store.assignFocusBlock(block, to: task)
        onChanged()
        dismiss()
    }

    private func chooseBreak() {
        store.assignFocusBreak(block)
        onChanged()
        dismiss()
    }
}
